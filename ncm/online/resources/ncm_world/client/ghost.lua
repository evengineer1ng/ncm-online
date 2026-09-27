-- ncm_world / client / ghost — record my own lap, replay my best one as a car I can chase (L166).
--
-- Two halves, deliberately in one file because they share the run boundary: the recorder fills a buffer while
-- I am on a timed lap, and the player draws a client-local prop along a stored one.
--
-- **Poses come from the CAR, not from my body.** `client/telemetry.lua` samples `Open77.character.position`,
-- which is the mounted driver, and it records no heading at all. For scoring that is fine. For drawing a car
-- it is not: it would sit half a metre off to the side of where the car really was, and it could not be
-- pointed anywhere. So this reads the vehicle snapshot through `NcmClientOwnVehicle`, the one sanctioned
-- accessor, and takes `position` and `yaw` from it.
--
-- **A ghost is never an entrant.** It has no collision and no physics, it is local to this client, it is not
-- in the standings, and it cannot be hit. It is a thing to chase.
local function log(fmt, ...) print(("[ncm_world/client/ghost] " .. fmt):format(...)) end

local Pose = NcmCore.get("replay.pose")
local Lap = NcmCore.get("replay.lap")
local Chunks = NcmCore.get("vocabulary.chunks")
local Templates = NcmCore.get("data.vehicle_templates")
local Telemetry = NcmCore.get("telemetry")
local Reading = NcmCore.get("competition.machine_knowledge").reading

local RECORD_HZ = Pose.DEFAULT_HZ
local RECORD_INTERVAL = 1.0 / RECORD_HZ    -- seconds between stored poses
-- **Playback is faster than recording, deliberately.** One loop, ticking at the cadence gate detection
-- already uses while racing, moving the ghost every tick and storing a pose only every other one. Recording
-- at 10 Hz sets how much of the real line survives; drawing at 10 Hz would make a car visibly step.
local PLAY_WAIT = 50
local POSES_PER_PACKET = 40                -- must match the server's, or reassembly counts disagree
local STREAM_RADIUS_M = 300

-- Selector. `session` and `route` are deliberately present and inert: the vocabulary is the same one the
-- public tiers will use, so turning them on later is not a rename (L166).
local MODES = { personal = true, session = false, route = false, off = true }
local mode = "personal"

-- Recording
local buffer = {}
local lastPoseAt = nil
local recording = false
local skipped = 0
local lastRunMs = nil

-- Playback
local ghost = nil        -- { head, poses, index, propId, model, candidate, startedAt, finished }
local pending = nil      -- in-flight download
local lastDeltaMs = nil
local haveNone = false   -- the server said explicitly that there is no stored ghost here

--- The session I am actually in, and only when it is a timed one.
---
--- Ghosts are for practice, qualifying and time trials. In a live race a ghost is visual clutter among real
--- competitors and could be read as another entrant, which is exactly the confusion this feature must not
--- create -- so there is no race branch here at all.
--- Which ghost-eligible activity this session is, IGNORING its phase, or nil.
---
--- Separate from `timedView` because the two questions have different answers at different moments. A time
--- trial only becomes *recordable* at green -- which is the same instant its run starts -- so if the stored
--- ghost were requested then, it would arrive after the lap had already begun and nothing would be drawn for
--- it. The trace has to be asked for while the lights are still on.
local function ghostKind(g)
    if type(g) ~= "table" then return nil end
    if type(g.routeId) ~= "string" or g.routeId == "" then return nil end
    local kind = g.kind or (g.formatId == "practice" and "practice" or nil)
    if kind == "practice" or kind == "quali" then return kind end
    if kind == "race" and #(g.entrants or {}) <= 1 then return "time_trial" end
    return nil
end

local function timedView()
    local g = NcmClientView
    if type(g) ~= "table" then return nil end
    if type(g.routeId) ~= "string" or g.routeId == "" then return nil end
    local kind = g.kind or (g.formatId == "practice" and "practice" or nil)

    -- Practice and qualifying run on the time-attack kernel: one phase, `open`, and a run is bounded by the
    -- start and finish gates.
    if kind == "practice" or kind == "quali" then
        if g.phase ~= "open" then return nil end
        return g, kind
    end

    -- **A TIME TRIAL is a race with a field of one** (`driver.progression.isTimeTrial`, L67 / `IDEA-001`), so
    -- it arrives here as `kind = "race"` on the race kernel with the race phases -- not as its own kind. It is
    -- the same solo activity as practice under a different name, so it gets a ghost.
    --
    -- A CONTESTED race does not. There a ghost would be visual clutter among real competitors and could be
    -- read as another entrant, which is the one presentation mistake this feature must not make.
    if kind == "race" and #(g.entrants or {}) <= 1 then
        if g.phase ~= "running" and g.phase ~= "finishing" then return nil end
        return g, "time_trial"
    end

    return nil
end

--- One pose, or nothing at all.
---
--- All-or-nothing, the same rule the telemetry sampler follows: zero is a measurement, absence is not. A pose
--- assembled from a half-readable snapshot would put the ghost at the origin, pointing north, and it would be
--- indistinguishable forever from a car that was genuinely there.
local function samplePose(nowSec)
    local v = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
    if type(v) ~= "table" then skipped = skipped + 1; return nil end
    local p = v.position
    local x, y, z
    if type(p) == "table" then
        x, y, z = Reading(p.x), Reading(p.y), Reading(p.z)
    else
        x, y, z = Reading(v.x), Reading(v.y), Reading(v.z)
    end
    -- `heading` and `yaw` are the same number under two names on this build; take either, invent neither.
    local yaw = Reading(v.yaw)
    if yaw == nil then yaw = Reading(v.heading) end
    if x == nil or y == nil or z == nil or yaw == nil then skipped = skipped + 1; return nil end
    return { t = nowSec, x = x, y = y, z = z, yaw = yaw }
end

local function observedRecord()
    local v = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
    if type(v) ~= "table" then return nil end
    return type(v.record) == "string" and v.record or nil
end

-- ---------------------------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------------------------

local function removeProp(why)
    if ghost and ghost.propId then
        pcall(Open77.props.remove, ghost.propId)
        log("removed ghost prop %s (%s)", tostring(ghost.propId), tostring(why or "done"))
        ghost.propId = nil
    end
end

--- Create the ghost's body, trying each candidate model in turn.
---
--- **A successful id is not proof that anything drew.** `props.create` returns an id for a model the client
--- cannot resolve (`KB-14`) and every client then fails projection with `template_backend_disabled`, so the
--- create return alone would make a missing ghost indistinguishable from a working one. The model string is
--- logged on every attempt and `props.get` is read back, which is the only signal available on this side; the
--- server's `prop projection failed ... reason=` line is the other half.
local function spawnProp(first, record)
    local candidates = Templates.candidates(record)
    for i, model in ipairs(candidates) do
        local ok, id, reason = pcall(Open77.props.create, {
            model = model,
            position = { x = first.x, y = first.y, z = first.z },
            yaw = first.yaw,
            -- Props default to STATIC COLLISION. Opting out is mandatory, not decoration: a ghost that can be
            -- hit is a hazard on the racing line and would be scored as a real impact.
            physics = "none",
            collision = false,
            visible = true,
            streamingRadius = STREAM_RADIUS_M,
        })
        if ok and id then
            local okGet, got = pcall(Open77.props.get, id)
            log("ghost prop id=%s model=%s candidate=%d/%d readback=%s%s", tostring(id), model, i, #candidates,
                okGet and type(got) == "table" and "present" or "ABSENT",
                Templates.isFallback(model) and "  [FALLBACK -- this record has no authored template]" or "")
            return id, model
        end
        log("ghost prop refused model=%s candidate=%d/%d: %s", model, i, #candidates, tostring(reason or id))
    end
    log("ghost prop could not be created for record=%s after %d candidate(s)", tostring(record), #candidates)
    return nil
end

--- Zero the ghost's clock. Called when *I* cross the start line, not when the stored lap began.
local function startPlayback(nowSec)
    if mode == "off" or not ghost or not ghost.poses or #ghost.poses < 2 then return end
    removeProp("restart")
    ghost.startedAt = nowSec
    ghost.finished = false
    local first = ghost.poses[1]
    ghost.propId, ghost.model = spawnProp(first, ghost.head and ghost.head.record)
end

local function stopPlayback(why)
    removeProp(why)
    if ghost then ghost.startedAt = nil end
    lastDeltaMs = nil
end

--- Move the ghost to where it was at this point in its lap.
---
--- `setTransform`, never destroy-and-recreate: the native layer is keyed by the prop id and transforms the
--- entity that is already there, so a ghost slides instead of popping.
local function tickPlayback(nowSec)
    if not ghost or not ghost.startedAt or not ghost.propId then return end
    local elapsed = nowSec - ghost.startedAt
    local p = Pose.poseAt(ghost.poses, elapsed)
    if not p then
        -- Off the end of the stored lap. It finished; it does not coast on in the direction it last pointed.
        if not ghost.finished and elapsed > 0 then
            ghost.finished = true
            removeProp("ghost finished")
        end
        return
    end
    pcall(Open77.props.setTransform, ghost.propId,
        { position = { x = p.x, y = p.y, z = p.z }, yaw = p.yaw })
end

--- Where I am against the ghost, in milliseconds. Negative means I am ahead.
local function tickDelta(nowSec)
    if not ghost or not ghost.index or not ghost.startedAt then return end
    local v = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
    if type(v) ~= "table" then return end
    local pos = v.position
    if type(pos) ~= "table" then pos = { x = v.x, y = v.y, z = v.z } end
    if type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end
    local pr = Telemetry.progress(ghost.course, pos, ghost.hintSeg)
    ghost.hintSeg = pr.seg
    lastDeltaMs = Lap.delta(ghost.index, pr.m, nowSec - ghost.startedAt)
end

--- What the HUD shows. Never a position, never a row in the standings: a target, not an entrant.
NcmClientGhost = function()
    if mode == "off" or not ghost or not ghost.head then
        return { mode = mode, present = false, none = haveNone }
    end
    return {
        mode = mode,
        present = true,
        label = mode == "personal" and "PERSONAL BEST" or mode:upper(),
        display = ghost.head.display,
        elapsedMs = ghost.head.elapsedMs,
        deltaMs = lastDeltaMs,
        playing = ghost.startedAt ~= nil and not ghost.finished,
        fallbackModel = ghost.model ~= nil and Templates.isFallback(ghost.model) or false,
    }
end

-- ---------------------------------------------------------------------------------------------
-- Download: server -> client
-- ---------------------------------------------------------------------------------------------

local function buildCourse()
    -- The gates the HUD already knows about are the course a delta is measured along.
    local g = NcmClientView
    local gates = type(g) == "table" and g.gates or nil
    if type(gates) ~= "table" or #gates < 2 then return nil end
    return Telemetry.polyline(gates)
end

local function finishDownload()
    if not pending or not Chunks.complete(pending.rx) then return end
    local raw, why = Chunks.collect(pending.rx)
    local head = pending.head
    pending = nil
    if not raw then
        log("ghost stream refused at assembly: %s", tostring(why))
        return
    end
    local poses, decodeWhy = Pose.decode(raw, head.format)
    if not poses then
        log("ghost stream refused: %s", tostring(decodeWhy))
        return
    end
    local course = buildCourse()
    ghost = {
        head = head, poses = poses, course = course,
        index = course and Lap.progressIndex(poses, course) or nil,
    }
    haveNone = false
    log("ghost ready %s: %d poses, %dms, record=%s%s", tostring(head.ghostId), #poses,
        head.elapsedMs or -1, tostring(head.record),
        course and "" or "  (no course yet -- the delta waits for gates)")
    -- Arrived while a lap is already under way: join it at the offset it should be at, rather than appearing
    -- at the start line however many seconds late.
    if runStartedAt then startPlayback(runStartedAt) end
end

RegisterNetEvent("ncm:ghost.stream.begin", function(meta)
    if type(meta) ~= "table" or type(meta.id) ~= "string" then return end
    pending = { id = meta.id, head = type(meta.head) == "table" and meta.head or {},
                rx = Chunks.receiver(tonumber(meta.parts) or 0) }
    pending.head.routeId = meta.routeId
    finishDownload()
end)

RegisterNetEvent("ncm:ghost.stream.part", function(part)
    if not pending or type(part) ~= "table" or tostring(part.id or "") ~= pending.id then return end
    local accepted, why = Chunks.accept(pending.rx, part.index, part.items)
    if accepted == nil then log("ghost stream bad part %s: %s", tostring(part.index), tostring(why)) end
    finishDownload()
end)

--- There is no stored ghost here. An EXPLICIT answer, so the HUD can say "no ghost yet" rather than leaving a
--- driver unable to tell that from a ghost that failed to arrive.
RegisterNetEvent("ncm:ghost.none", function(meta)
    haveNone = true
    stopPlayback("no ghost")
    ghost = nil
    log("no stored ghost for route=%s", type(meta) == "table" and tostring(meta.routeId) or "?")
end)

-- ---------------------------------------------------------------------------------------------
-- Upload: client -> server, on the server's invitation only
-- ---------------------------------------------------------------------------------------------

--- The server timed a new best and is inviting the poses for it.
---
--- Upload happens only here. The server already holds every number the stored lap will carry; all this sends
--- is the shape of the line, which is the one thing only this client could see.
RegisterNetEvent("ncm:ghost.invite", function(meta)
    if type(meta) ~= "table" then return end
    if #buffer < 4 then
        log("invited to upload but the buffer holds %d pose(s)", #buffer)
        return
    end
    local rebased = Pose.rebase(buffer)
    if not rebased then return end
    local thinned = Pose.decimate(rebased)
    local wire = Pose.encode(thinned)
    if not wire then return end
    local parts = Chunks.partition(wire, POSES_PER_PACKET)
    local okM, mono = pcall(Open77.time.monotonic)
    local streamId = ("%d:%d:%d"):format(math.floor((okM and mono or 0) * 1000), #wire, #parts)
    -- **`bufferMs` is the buffer's own span, and it is NOT the lap time.** Recording starts and stops when
    -- the published view says my run did, which lags the kernel's own gate timestamps by up to one publish,
    -- and the kernel's figure additionally includes any incident penalty. Sending this as `elapsedMs` would
    -- invite the server to compare two different quantities; the server stores its own time and uses this
    -- only to check that these poses plausibly belong to that lap.
    local head = {
        id = streamId, parts = #parts, format = Pose.FORMAT,
        bufferMs = Pose.durationMs(rebased), poseHz = RECORD_HZ,
        record = observedRecord(), routeId = meta.routeId,
    }
    TriggerServerEvent("ncm:ghost.upload.begin", head)
    for i, items in ipairs(parts) do
        TriggerServerEvent("ncm:ghost.upload.part", { id = streamId, index = i, items = items })
        -- The inbound limit is 32 events per second per session and a lap is ~25 packets. Yield between them
        -- rather than firing the whole stream inside one resume.
        if i % 8 == 0 then Wait(0) end
    end
    lastRunMs = tonumber(meta.elapsedMs) or head.bufferMs
    log("uploaded %d pose(s) in %d packet(s) (%d raw, %d after decimation) buffer=%dms kernel=%sms record=%s",
        #thinned, #parts, #rebased, #thinned, head.bufferMs, tostring(meta.elapsedMs), tostring(head.record))
end)

-- ---------------------------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------------------------

--- When the run in progress began, on the server clock. Kept outside the ghost so a ghost that finishes
--- downloading mid-lap can be anchored to the lap already under way instead of starting from wherever it
--- happened to arrive -- which would put it in the wrong place for the rest of the run.
local runStartedAt = nil

local function onRunStarted(nowSec)
    buffer = {}
    lastPoseAt = nil
    recording = true
    runStartedAt = nowSec
    startPlayback(nowSec)
end

local function onRunEnded(why)
    recording = false
    runStartedAt = nil
    stopPlayback(why)
end

CreateThread(function()
    Wait(3500)
    local wasRunning, lastRoute = false, nil
    while true do
        -- Prefetch first, on the view as it stands and whatever phase it is in. A time trial's run begins the
        -- moment it becomes recordable, so waiting for that would always be too late.
        local anyView = NcmClientView
        local anyKind = ghostKind(anyView)
        if anyKind and mode ~= "off" and anyView.routeId ~= lastRoute then
            lastRoute = anyView.routeId
            ghost, pending, haveNone = nil, nil, false
            TriggerServerEvent("ncm:ghost.want", anyView.routeId)
            log("asked for the stored ghost on route=%s (%s)", tostring(anyView.routeId), anyKind)
        end

        local g, kind = timedView()
        if g and mode ~= "off" then
            local nowSec = NcmClientServerNow and NcmClientServerNow() or 0

            -- `NcmClientMyEntrant` is the HUD's own view of me, so the recorder starts on the same fact the
            -- driver is looking at rather than on a second guess at which entrant is theirs.
            local mine = NcmClientMyEntrant
            local running
            if kind == "time_trial" then
                -- The race kernel has no per-run progress to watch: a time trial is ONE run, it starts at
                -- green and it ends when the entrant is classified. `ready -> racing` happens at green and
                -- `racing -> finished` at the finish gate, so the state is the boundary.
                running = g.greenAt ~= nil and type(mine) == "table" and mine.state == "racing"
            else
                -- On the time-attack kernel a run is in progress exactly when progress is non-zero: the start
                -- gate sets it to 1 and the finish resets it to 0.
                running = type(mine) == "table" and (tonumber(mine.progress) or 0) > 0
            end

            if running and not wasRunning then
                onRunStarted(nowSec)
            elseif wasRunning and not running then
                onRunEnded("run ended")
            end
            wasRunning = running

            if recording and (lastPoseAt == nil or (nowSec - lastPoseAt) >= RECORD_INTERVAL) then
                local p = samplePose(nowSec)
                if p then
                    lastPoseAt = nowSec
                    if #buffer < Pose.MAX_POSES then
                        buffer[#buffer + 1] = p
                    elseif #buffer == Pose.MAX_POSES then
                        buffer[#buffer + 1] = p   -- one over, so the refusal is legible rather than silent
                        log("buffer reached %d poses; this run is too long to store as a ghost", #buffer)
                    end
                end
            end

            tickPlayback(nowSec)
            tickDelta(nowSec)
            Wait(PLAY_WAIT)
        else
            if wasRunning then onRunEnded("left the session"); wasRunning = false end
            if ghost and ghost.propId then removeProp("not in a timed session") end
            -- Forget the route only when there is no ghost-eligible session AT ALL. Clearing it merely because
            -- the phase is not recordable yet would re-request the trace on every tick of a countdown, and
            -- each answer discards the ghost the previous one just delivered.
            if not anyKind then lastRoute = nil end
            -- Tighter while a ghost-eligible session is forming: a time trial's run begins the instant the
            -- phase turns, and a second of latency there is ten lost poses and a late ghost.
            Wait(anyKind and 250 or 1000)
        end
    end
end)

--- Cleanup is a requirement, not hygiene: a resource reload must take its props with it.
AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    removeProp("resource stopped")
end)

RegisterCommand("ncm.ghost", function(_, args)
    local a = args and args[1] and tostring(args[1]):lower() or nil
    if a and MODES[a] ~= nil then
        if MODES[a] == false then
            log("%s ghosts are not built yet -- personal bests only for now (L166)", a)
        else
            mode = a
            if mode == "off" then stopPlayback("turned off") end
            log("ghost mode %s", mode)
        end
        return
    end
    log("mode=%s · buffer=%d pose(s) · skipped=%d unreadable · last run=%s",
        mode, #buffer, skipped, lastRunMs and (lastRunMs .. "ms") or "none")
    if ghost and ghost.head then
        log("  loaded ghost=%s %dms poses=%d record=%s model=%s prop=%s delta=%s",
            tostring(ghost.head.ghostId), ghost.head.elapsedMs or -1, #ghost.poses,
            tostring(ghost.head.record), tostring(ghost.model), tostring(ghost.propId),
            lastDeltaMs and (lastDeltaMs .. "ms") or "none")
    else
        log("  no ghost loaded%s", haveNone and " (the server says there is none for this route)" or "")
    end
end, false)
