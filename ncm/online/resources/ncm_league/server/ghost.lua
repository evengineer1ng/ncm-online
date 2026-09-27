-- Lap ghost host: accept an uploaded lap, keep it immutably, hand it back (L166).
--
-- A ghost is NOT an entrant and NOT evidence. Nothing here writes a result, a rating, a penalty or a
-- standing; a ghost only ever produces a thing to look at and a delta to read. That boundary is what makes it
-- safe for this file to accept a payload the client assembled at all.
--
-- **The client's word is never the stored fact.** The client sends poses, because only the client can see its
-- own car's heading. Everything else a stored lap carries -- the time, the interval, the route, the machine --
-- comes from the claim the race host wrote when the SERVER saw the lap finish. The client's own figures are
-- used only to check that these poses plausibly belong to that lap, and to log it when its observation of the
-- car disagrees with the asset record.
NcmGhost = {}

local Chunks = NcmCore.get("vocabulary.chunks")
local Json = NcmCore.get("vocabulary.json")
local Pose = NcmCore.get("replay.pose")
local Lap = NcmCore.get("replay.lap")
local Telemetry = NcmCore.get("telemetry")
local ids = NcmCore.get("vocabulary.ids")

local function now() return Open77.time.unix() end
local function serverId() return NcmCalendar.serverId() end
local function log(fmt, ...) print(("[ncm_league/ghost] " .. fmt):format(...)) end
local function driverOf(pid) return NcmCalendar.resolveDriver(tonumber(pid) or 0) end

--- Poses per net packet.
---
--- **Not one row per packet like the market.** A lap is around a thousand poses and the inbound limit is 32
--- events per second per session, so one row per packet would take half a minute and look like a hang. Forty
--- poses is roughly 1.8 KB per packet -- well under the envelope, and a whole lap in about 25 packets.
local POSES_PER_PACKET = 40

--- A run whose poses stop arriving is abandoned after this long. `vocabulary.chunks` has no timeout of its
--- own, so without this a client that drops mid-upload pins a receiver forever.
local UPLOAD_TTL_S = 60

-- pid -> { id, driverId, head, rx, startedAt }
local uploads = {}

--- Encoded size, measured rather than estimated. `KB-136` was a size limit nobody could see because nothing
--- printed a number, and a 45 KB lap is exactly the shape of payload that finds the next one.
local function encodedBytes(value)
    local ok, encoded = pcall(Json.encode, value)
    if not ok then return -1 end
    return #encoded
end

--- What the SERVER knows about the machine behind an asset id. Cached because a miss is a query.
local recordCache = {}
function NcmGhost.recordFor(assetId)
    if not ids.isUuid(assetId) then return nil end
    local cached = recordCache[assetId]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local ok, row = pcall(function()
        return MySQL.single.await("SELECT record FROM vehicle_asset WHERE asset_id = ? LIMIT 1", { assetId })
    end)
    if not ok or type(row) ~= "table" or type(row.record) ~= "string" or row.record == "" then
        recordCache[assetId] = false
        return nil
    end
    recordCache[assetId] = row.record
    return row.record
end

--- Refuse a pose stream that could not have come from a car driving a lap.
---
--- The same planar-jump rule the telemetry stream already applies, reused rather than restated, so a ghost and
--- a sample cannot disagree about what counts as a teleport.
local function poseStreamPlausible(poses)
    for i = 2, #poses do
        local a, b = poses[i - 1], poses[i]
        local jump = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        if jump > Telemetry.MAX_JUMP_M then
            return false, ("jump:%d@%d"):format(math.floor(jump), i)
        end
    end
    return true
end

--- Store an accepted lap. INSERT only: a faster lap is a new row, and nothing here updates or deletes one.
function NcmGhost.store(manifest, wire)
    local encoded = Json.encode(wire)
    local ok, err = pcall(function()
        MySQL.insert.await([[INSERT INTO ghost_lap
            (ghost_id, format, server_id, ncm_driver_id, session_id, event_id, route_id, discipline_id,
             ruleset_id, class_id, laps, run_started_at, run_finished_at, elapsed_ms, incident_ms,
             asset_id, record, appearance, configuration_ref, pose_count, pose_hz, poses_json, tier, at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''),
                    NULLIF(?, ''), ?, ?, ?, ?, ?)]],
            { manifest.ghostId, manifest.format, serverId(), manifest.driverId, manifest.sessionId,
              manifest.eventId, manifest.routeId, manifest.disciplineId,
              manifest.rulesetId, manifest.classId, manifest.laps,
              manifest.runStartedAt, manifest.runFinishedAt, manifest.elapsedMs, manifest.incidentMs,
              manifest.assetId or "", manifest.record or "", manifest.appearance or "",
              manifest.configurationRef or "", manifest.poseCount, manifest.poseHz, encoded,
              manifest.tier, math.floor(now()) })
    end)
    if not ok then
        log("store REFUSED ghost=%s: %s", tostring(manifest.ghostId), tostring(err))
        return nil, "insert_failed"
    end
    log("stored ghost=%s driver=%s route=%s %dms poses=%d %d bytes record=%s",
        manifest.ghostId, manifest.driverId, manifest.routeId, manifest.elapsedMs, manifest.poseCount,
        #encoded, tostring(manifest.record))
    return manifest.ghostId
end

--- The driver's fastest stored lap on a route, decoded and ready to replay, or nil, reason.
function NcmGhost.best(driverId, routeId)
    if not ids.isUuid(driverId) or type(routeId) ~= "string" or routeId == "" then return nil, "bad_key" end
    local ok, row = pcall(function()
        return MySQL.single.await([[SELECT ghost_id, format, elapsed_ms, incident_ms, record, appearance,
                   asset_id, pose_count, pose_hz, poses_json
            FROM ghost_lap
            WHERE server_id = ? AND route_id = ? AND ncm_driver_id = ? AND tier = 'personal'
            ORDER BY elapsed_ms ASC LIMIT 1]], { serverId(), routeId, driverId })
    end)
    if not ok or type(row) ~= "table" or not row.ghost_id then return nil, "no_ghost" end
    -- A stored row has survived a schema change, a client upload and a JSON round trip since it was written,
    -- so it is decoded and validated like anything else off the wire, not trusted because it is ours.
    local okJson, raw = pcall(Json.decode, row.poses_json)
    if not okJson or type(raw) ~= "table" then
        log("ghost %s has unreadable poses_json", tostring(row.ghost_id))
        return nil, "unreadable"
    end
    local poses, why = Pose.decode(raw, tonumber(row.format))
    if not poses then
        log("ghost %s refused on read: %s", tostring(row.ghost_id), tostring(why))
        return nil, why
    end
    return {
        ghostId = row.ghost_id, format = tonumber(row.format), elapsedMs = tonumber(row.elapsed_ms) or 0,
        incidentMs = tonumber(row.incident_ms) or 0, record = row.record, appearance = row.appearance,
        assetId = row.asset_id, poseHz = tonumber(row.pose_hz) or Pose.DEFAULT_HZ, poses = poses,
    }
end

-- ---------------------------------------------------------------------------------------------
-- Claims: what the server saw, recorded at the finish, consumed once by the matching upload
-- ---------------------------------------------------------------------------------------------

--- driverId -> the facts of the run that just finished. Written by the race host at the finish gate, so a
--- client can only ever upload poses for a lap the SERVER timed. This is the whole of the integrity story for
--- a personal ghost: the poses are the client's, every number attached to them is the server's.
NcmGhost.claims = {}

function NcmGhost.claim(driverId, facts)
    if not driverId or type(facts) ~= "table" then return end
    NcmGhost.claims[driverId] = facts
end

-- ---------------------------------------------------------------------------------------------
-- Upload: client -> server, in bounded packets
-- ---------------------------------------------------------------------------------------------

local function finishUpload(pid)
    local st = uploads[pid]
    if not st or not Chunks.complete(st.rx) then return end
    uploads[pid] = nil

    local raw, why = Chunks.collect(st.rx)
    if not raw then
        log("upload %s refused at assembly: %s", tostring(st.id), tostring(why))
        return
    end
    local poses, decodeWhy = Pose.decode(raw, st.head.format)
    if not poses then
        log("upload %s refused: %s", tostring(st.id), tostring(decodeWhy))
        return
    end
    local okPlausible, jumpWhy = poseStreamPlausible(poses)
    if not okPlausible then
        log("upload %s refused: %s", tostring(st.id), tostring(jumpWhy))
        return
    end

    local claim = NcmGhost.claims[st.driverId]
    if not claim then
        log("upload %s refused: no finished run on record for driver %s", tostring(st.id), tostring(st.driverId))
        return
    end
    NcmGhost.claims[st.driverId] = nil

    -- **The poses must plausibly belong to the lap the server timed -- not equal it.**
    --
    -- The buffer's span is legitimately shorter than the kernel's figure, for two independent reasons: the
    -- client starts and stops recording when the PUBLISHED view says its run did, which lags the kernel's own
    -- gate timestamps by up to one publish; and the kernel's time includes any incident penalty, which is
    -- added seconds during which the car was not driving a lap. So the comparison is against the raw
    -- gate-to-gate duration, with a band wide enough to cover the publish latency at either end.
    --
    -- The stored time is always the kernel's. This check only refuses a stream that belongs to a different
    -- lap altogether.
    local bufferMs = math.floor(tonumber(st.head.bufferMs) or 0)
    -- The kernel's own gate-to-gate duration, carried on the claim. **Not derived here**: for a practice run
    -- the official time adds the incident penalty, and for a time trial it adds the penalty seconds too, so
    -- subtracting one of them would be right for one kind of session and wrong for the other.
    local rawMs = math.floor(tonumber(claim.rawMs) or (claim.elapsedMs - (claim.incidentMs or 0)))
    local BAND_MS = 2000
    if bufferMs < (rawMs - BAND_MS) or bufferMs > (rawMs + BAND_MS) then
        log("upload %s refused: %d pose-ms does not match the %dms the server timed (raw %dms, band %dms)",
            tostring(st.id), bufferMs, claim.elapsedMs, rawMs, BAND_MS)
        return
    end

    -- The record is the server's, not the client's. The client's observation is kept only to log a mismatch,
    -- because a ghost wearing the wrong car is a bug worth seeing rather than a silently different model.
    local record = NcmGhost.recordFor(claim.assetId) or st.head.record
    if st.head.record and record and st.head.record ~= record then
        log("upload %s: client observed record %s, asset %s says %s -- storing the server's",
            tostring(st.id), tostring(st.head.record), tostring(claim.assetId), tostring(record))
    end

    local facts = {
        ghostId = ids.uuid4(function() return math.random() end),
        format = Pose.FORMAT, tier = "personal",
        driverId = st.driverId, sessionId = claim.sessionId, eventId = claim.eventId,
        routeId = claim.routeId, disciplineId = claim.disciplineId, rulesetId = claim.rulesetId,
        classId = claim.classId, laps = claim.laps or 1,
        runStartedAt = claim.startedAt, runFinishedAt = claim.finishedAt,
        elapsedMs = claim.elapsedMs, incidentMs = claim.incidentMs,
        assetId = claim.assetId, record = record, appearance = st.head.appearance,
        configurationRef = claim.configurationRef,
        poseCount = #poses, poseHz = tonumber(st.head.poseHz) or Pose.DEFAULT_HZ,
        gatesDone = claim.gatesDone, gatesTotal = claim.gatesTotal,
    }

    local eligible, elWhy = Lap.eligible(facts, "personal")
    if not eligible then
        log("upload %s refused as a ghost: %s", tostring(st.id), tostring(elWhy))
        return
    end
    local manifest, mWhy = Lap.manifest(facts)
    if not manifest then
        log("upload %s refused by the manifest: %s", tostring(st.id), tostring(mWhy))
        return
    end

    -- The kernel already said this run improved on the SESSION best; this is the same question against the
    -- durable store, which spans sessions and restarts.
    local incumbent = NcmGhost.best(st.driverId, manifest.routeId)
    if incumbent and not Lap.better(manifest.elapsedMs, incumbent.elapsedMs) then
        log("upload %s kept out: %dms does not beat the stored %dms", tostring(st.id),
            manifest.elapsedMs, incumbent.elapsedMs)
        return
    end

    local ghostId = NcmGhost.store(manifest, Pose.encode(poses))
    if ghostId then
        -- Tie the stored lap to the practice row it came from, so a run and its ghost are one fact.
        pcall(function()
            MySQL.update.await([[UPDATE practice_run SET ghost_id = ?
                WHERE session_id = ? AND ncm_driver_id = ? AND ghost_id IS NULL
                ORDER BY id DESC LIMIT 1]], { ghostId, claim.sessionId, st.driverId })
        end)
        NcmGhost.push(pid, manifest.routeId)
    end
end

RegisterNetEvent("ncm:ghost.upload.begin", function(meta)
    local pid = tonumber(source) or 0
    local d = driverOf(pid)
    if not d then return end
    if type(meta) ~= "table" or type(meta.id) ~= "string" then return end
    local parts = math.floor(tonumber(meta.parts) or 0)
    if parts < 1 or parts > (math.ceil(Pose.MAX_POSES / POSES_PER_PACKET) + 1) then
        log("upload begin refused player=%d parts=%s", pid, tostring(meta.parts))
        return
    end
    uploads[pid] = {
        id = meta.id, driverId = d.ncmDriverId, head = meta, rx = Chunks.receiver(parts), startedAt = now(),
    }
    log("upload begin player=%d id=%s parts=%d claimed=%sms record=%s", pid, meta.id, parts,
        tostring(meta.elapsedMs), tostring(meta.record))
    finishUpload(pid)
end)

RegisterNetEvent("ncm:ghost.upload.part", function(part)
    local pid = tonumber(source) or 0
    local st = uploads[pid]
    if not st or type(part) ~= "table" or tostring(part.id or "") ~= st.id then return end
    if (now() - st.startedAt) > UPLOAD_TTL_S then
        log("upload %s abandoned after %ds", st.id, UPLOAD_TTL_S)
        uploads[pid] = nil
        return
    end
    local accepted, why = Chunks.accept(st.rx, part.index, part.items)
    if accepted == nil then
        log("upload %s bad part %s: %s", st.id, tostring(part.index), tostring(why))
    end
    finishUpload(pid)
end)

-- ---------------------------------------------------------------------------------------------
-- Download: server -> client, the same bounded shape
-- ---------------------------------------------------------------------------------------------

local streamSeq = 0

--- Send this driver's stored best for a route, or an explicit "there is none".
---
--- The explicit empty answer matters: without it a client cannot tell "you have no ghost here yet" from "the
--- ghost failed to arrive", and those are different things to put on a HUD.
function NcmGhost.push(pid, routeId)
    local d = driverOf(pid)
    if not d then return end
    local g = NcmGhost.best(d.ncmDriverId, routeId)
    if not g then
        TriggerClientEvent("ncm:ghost.none", pid, { routeId = routeId })
        return
    end
    local wire = Pose.encode(g.poses)
    local parts = Chunks.partition(wire, POSES_PER_PACKET)
    streamSeq = streamSeq + 1
    local streamId = ("%d:%d:%d"):format(math.floor(now()), streamSeq, pid)
    TriggerClientEvent("ncm:ghost.stream.begin", pid, {
        id = streamId, parts = #parts, routeId = routeId,
        head = {
            ghostId = g.ghostId, format = g.format, elapsedMs = g.elapsedMs, incidentMs = g.incidentMs,
            record = g.record, appearance = g.appearance, poseHz = g.poseHz, tier = "personal",
            display = d.display or d.ncmDriverId,
        },
    })
    for i, items in ipairs(parts) do
        TriggerClientEvent("ncm:ghost.stream.part", pid, { id = streamId, index = i, items = items })
    end
    log("stream player=%d id=%s ghost=%s poses=%d packets=%d %d bytes", pid, streamId, g.ghostId,
        #g.poses, #parts, encodedBytes(wire))
end

RegisterNetEvent("ncm:ghost.want", function(routeId)
    local pid = tonumber(source) or 0
    if type(routeId) ~= "string" or routeId == "" or #routeId > 160 then return end
    NcmGhost.push(pid, routeId)
end)

RegisterCommand("ncm.ghost", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    local pending, inflight = 0, 0
    for _ in pairs(NcmGhost.claims) do pending = pending + 1 end
    for _ in pairs(uploads) do inflight = inflight + 1 end
    log("claims pending=%d · uploads in flight=%d · poses/packet=%d · max poses=%d · format=%d",
        pending, inflight, POSES_PER_PACKET, Pose.MAX_POSES, Pose.FORMAT)
    local ok, rows = pcall(function()
        return MySQL.query.await([[SELECT route_id, ncm_driver_id, elapsed_ms, pose_count, record, at
            FROM ghost_lap WHERE server_id = ? ORDER BY at DESC LIMIT 10]], { serverId() })
    end)
    if ok and type(rows) == "table" then
        log("%d stored ghost(s), newest first:", #rows)
        for _, r in ipairs(rows) do
            log("  %s driver=%s %dms poses=%s record=%s", tostring(r.route_id), tostring(r.ncm_driver_id),
                tonumber(r.elapsed_ms) or -1, tostring(r.pose_count), tostring(r.record))
        end
    end
end, false)
