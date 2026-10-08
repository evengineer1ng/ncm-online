-- ncm_world / server — v0.1.0 (M2.1): NCM Driver identity on join; `ncm` and `ncm.where` commands.
local WORLD_VERSION = "0.5.0"   -- KB-24: keep in step with `version` in open77.lua; the banner said 0.2.0 while the manifest said 0.5.0
local RESOURCE = "ncm_world"

local Core = NcmCore -- created by shared/core/init.lua, loaded before this file (manifest order)

-- KB-60 readiness watch. Declared here, above every handler that touches it, because a handler closure can
-- only capture locals that already exist when the closure is created. The rule itself is in `world.readiness`;
-- see the long note further down for why the old per-player watchdog could not see the player it was for.
local Readiness = Core.get("world.readiness")
local Location = Core.get("world.location")
local limbo = Readiness.new()
local SWEEP_S = 5

-- KB-113 session bookkeeping. Both are keyed by player id, both are cleared on disconnect, and both exist
-- so the location code can tell "where this driver logged out" from "what this join has written so far".
local connectedAtUnix = {}   -- playerId -> unix seconds this session began
local playedThisSession = {} -- playerId -> true once they were observed playable at least once

--- Monotonic seconds. `GetGameTimer` is the platform's own clock and cannot walk backwards over an NTP step,
--- which `os.time` can -- and a clock that jumps is a watchdog that either nags or goes quiet.
--- The world's identity, published by ncm_league (separate resource, separate Lua VM -- `NcmCalendar` is nil
--- here). Falling back to a literal is what keyed `driver_location` rows under `"ncm"` while the rest of the
--- canonical world used `"ncm-dev"`, so the fallback now degrades to the SAME default the league declares
--- rather than inventing a third value.
local function worldIdentity()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    if ok and type(id) == "table" and type(id.serverId) == "string" and id.serverId ~= "" then
        return id.serverId, tostring(id.environment or "unknown")
    end
    return "ncm-dev", "unknown"
end

local function nowS()
    local ok, ms = pcall(GetGameTimer)
    return (ok and tonumber(ms) or 0) / 1000
end

local function log(fmt, ...)
    print(("[ncm_world] " .. fmt):format(...))
end

--- Render a return value truthfully for the log, whatever shape it turns out to be. KB-21's residual was
--- `tostring(ok)` on a value that is a table, so the line ended in a hex address. We do not know which keys the
--- platform puts in it, so we print what is actually there rather than guessing at a field name.
local function describe(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for k, val in pairs(v) do
        if type(val) ~= "table" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(val) end
    end
    table.sort(parts)
    if #parts == 0 then return "{}" end
    return "{" .. table.concat(parts, " ") .. "}"
end

local function luaVersion()
    local ok, v = pcall(function() return Open77.runtime.luaVersion() end)
    return ok and tostring(v) or _VERSION
end

local function fmt1(n)
    return string.format("%.1f", tonumber(n) or 0)
end

local function describePlayer(playerId)
    local id = tonumber(playerId) or 0
    local userId = GetPlayerIdentifier(id)
    local name = GetPlayerName(id)
    local pos = Open77.players.position(id)
    local bucket = Open77.routingBuckets.getPlayer(id)
    local where = "position unknown"
    if pos then
        where = ("x=%s y=%s z=%s"):format(fmt1(pos.x), fmt1(pos.y), fmt1(pos.z))
    end
    local prof = NcmIdentity.get(id)
    return ("player=%d user=%s name=%s bucket=%s %s | driver=%s"):format(
        id, tostring(userId), tostring(name), tostring(bucket), where,
        prof and prof.ncmDriverId or "none")
end

local function tell(playerId, text)
    pcall(Open77.chat.send, playerId, "[NCM] " .. text)
end

AddEventHandler("onResourceStart", function(name)
    if name ~= RESOURCE then return end
    local ok, a, b = pcall(Open77.ready.participate, { timeoutMs = 20000, reason = "NCM driver identity" })
    log("started v%s | server lua %s | ncm-core %s | modules: %s | ready.participate=%s %s",
        WORLD_VERSION, luaVersion(), Core.VERSION, table.concat(Core.defined(), ", "), tostring(a), tostring(b or ""))
    -- Adopt players already connected across a reload (gamemode-kernel contract: reload-safe roster).
    for _, pid in ipairs(Open77.players.all()) do
        CreateThread(function()
            local prof, reason = NcmIdentity.resolve(pid)
            if not prof then log("adopt failed player=%s: %s", tostring(pid), tostring(reason)) end
        end)
    end
end)

AddEventHandler("onPlayerConnected", function(playerId)
    local id = tonumber(playerId) or 0
    log("connected: player=%d user=%s name=%s", id, tostring(GetPlayerIdentifier(id)), tostring(GetPlayerName(id)))
    limbo:connected(id, nowS(), GetPlayerName(id))   -- KB-60: the limbo clock starts here, not at readiness
    local okNow, nowUnix = pcall(Open77.time.unix)
    connectedAtUnix[id] = okNow and math.floor(nowUnix) or nil   -- KB-113: what "this session" means, in save clock
    playedThisSession[id] = nil
    local session = Open77.ready.hold(id, "NCM driver identity")
    CreateThread(function()
        local prof, reason = NcmIdentity.resolve(id)
        if not prof then
            log("identity unavailable for player=%d: %s (player continues without an NCM driver this session)", id, tostring(reason))
        end
        Open77.ready.release(id, session, prof and "ncm driver ready" or ("ncm driver unavailable: " .. tostring(reason)))
    end)
end)

-- KB-39: a joiner can sit for minutes never becoming gameplay-ready, then give up and leave.
--
-- NCM cannot fix the cause and must not paper over it. `open77:session:gameplayReady` is emitted by the platform's
-- own appearance shell (`open77_appearance/client/main.lua`, `announce()`), and that function opens with
-- `if announced or failed ~= nil then return end` -- so once an appearance restore has failed, the readiness
-- signal is never sent again for that session. There is no retry, which is exactly why reconnecting works and
-- waiting does not. Emitting it ourselves would be a lie: it would tell freeroam to spawn a player whose world
-- is not up.
--
-- What NCM owes is the thing that was missing: somebody noticing. Note that `onPlayerReady` is NOT this signal --
-- it is the hold barrier lifting, which says only that nobody is blocking the player any more, not that their
-- world exists.
--
-- KB-60 then showed the first version of this was watching from inside the burning building. It hung off
-- `onPlayerReady`, so for the one player it was written for -- `Trip[ABK]`, eleven minutes at
-- `stage=appearance_failed` -- it never started at all. An event cannot report the absence of itself. The
-- question is now asked by a PERIODIC SWEEP over everyone `Open77.players.all()` reports, and the test for
-- "can play" is no longer `fresh and position`, which that player satisfied. The rule lives in
-- `world.readiness` so it can be tested offline; this file only observes and speaks.
-- (`Readiness`, `limbo`, `SWEEP_S` and `nowS` are declared at the top of this file: the connect handler is
-- created above this point and has to be able to see them.)

local function stillConnected(id)
    local ok, all = pcall(Open77.players.all)
    if not ok or type(all) ~= "table" then return false end
    for _, pid in ipairs(all) do if tonumber(pid) == id then return true end end
    return false
end

--- Has a puppet with a position. This is what `separate()` needs and it is a fine test FOR THAT -- you cannot
--- step someone sideways until there is a someone. It is NOT a test of being able to play (KB-60): the player
--- who could not play for eleven minutes returned true here the whole time.
local function inTheWorld(id)
    local ok, p = pcall(Open77.players.get, id)
    return ok and type(p) == "table" and p.fresh == true and p.position ~= nil
end

--- Nobody arrives inside somebody else (KB-58).
---
--- Two players occupying the same point is not a cosmetic problem: Cyberpunk resolves the overlap by refusing
--- to resolve it, and both puppets stick until one of them teleports away. It happens on a plain join, because
--- the platform's spawn point does not know who is already standing on it, and it happens on NCM's own resume
--- teleport, which deliberately returns a dropped racer to their last position -- a position another player may
--- since have walked into.
---
--- NCM cannot choose the platform's spawn point, so this runs AFTER arrival: if the player is too close to
--- someone else, step them off to the nearest clear offset. Small, sideways, same ground -- never a relocation.
local SEPARATION_M = 3.0        -- closer than this and the puppets interpenetrate
local SEPARATION_TRIES = 8      -- eight points around a ring, then give up rather than fling anyone

--- The nearest player to `pos` in the same bucket, excluding `selfId`: distance, or nil when alone.
local function nearestPlayer(selfId, pos, bucket)
    local ok, all = pcall(Open77.players.all)
    if not ok or type(all) ~= "table" then return nil end
    local best
    for _, raw in ipairs(all) do
        local other = tonumber(raw) or 0
        if other ~= selfId then
            local okP, p = pcall(Open77.players.get, other)
            if okP and type(p) == "table" and p.position and tonumber(p.bucket or 0) == tonumber(bucket or 0) then
                local dx, dy = pos.x - p.position.x, pos.y - p.position.y
                local d = math.sqrt(dx * dx + dy * dy)
                if not best or d < best then best = d end
            end
        end
    end
    return best
end

--- Step `id` off anyone they are standing inside. Returns true when the player was moved.
local function separate(id, why)
    local ok, p = pcall(Open77.players.get, id)
    if not ok or type(p) ~= "table" or not p.position then return false end
    local near = nearestPlayer(id, p.position, p.bucket)
    if not near or near >= SEPARATION_M then return false end

    -- walk a ring outward: the first clear point wins, so the move is as small as it can be
    for i = 1, SEPARATION_TRIES do
        local angle = (i / SEPARATION_TRIES) * math.pi * 2
        local radius = SEPARATION_M + 1.0
        local candidate = {
            x = p.position.x + math.cos(angle) * radius,
            y = p.position.y + math.sin(angle) * radius,
            z = p.position.z,
        }
        local clear = nearestPlayer(id, candidate, p.bucket)
        if not clear or clear >= SEPARATION_M then
            -- no fade: this is a half-step sideways, and fading the screen for it would read as a bug
            local moved, reason = Open77.players.teleport(id, { x = candidate.x, y = candidate.y, z = candidate.z + 0.2 },
                { heading = p.heading, fade = false, dismount = false })
            log("separation: player=%d was %.1f m from another player (%s) -> stepped %.1f m aside: %s",
                id, near, tostring(why), radius, moved and "ok" or tostring(reason))
            return moved and true or false
        end
    end
    log("separation: player=%d is %.1f m from another player (%s) but every offset was occupied; left alone",
        id, near, tostring(why))
    return false
end

--- Check once the player is actually in the world. A join is not a position: `onPlayerReady` fires before the
--- puppet exists (KB-39), so separating immediately would measure a position that is not there yet.
local function separateWhenReady(id, why)
    CreateThread(function()
        local waited = 0
        while waited < 60 do
            Wait(2000); waited = waited + 2
            if not stillConnected(id) then return end
            if inTheWorld(id) then Wait(1000); separate(id, why); return end
        end
    end)
end

-- Server console: ncm.unstick <playerId> -- step someone off whoever they are standing inside, right now.
RegisterCommand("ncm.unstick", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.unstick <playerId>"); return end
    CreateThread(function()
        if not separate(pid, "manual") then log("separation: player=%d needed no move", pid) end
    end)
end, false)

--- The platform's own readiness diagnostic, which NCM was not reading (KB-60). `open77_appearance/server`
--- registers this net event and prints it as [OP77-INIT-002]; a second resource may listen to the same event,
--- and this one is pure evidence -- it never releases a hold or grants anything, it only tells the sweep that
--- a client is still waiting for gameplay readiness. If the platform ever refuses the registration we lose the
--- stage detail and nothing else: the sweep does not depend on it.
---
--- A registration that throws is caught here; a registration that is accepted and then never delivers is not,
--- and this codebase has now lost three deploys to platform limits that fail without a word (KB-59, KB-61,
--- KB-63). So the first diagnostic that actually arrives says so once, and its absence from the log is itself
--- the answer when nobody can play and no stage is ever named.
local stageHeard = false
local stageListener = pcall(function()
    RegisterNetEvent("open77:appearance:readinessDiagnostic",
        function(stage, _resetPhase, _bootstrapPhase, elapsed)
            local id = tonumber(source) or 0
            if id <= 0 then return end
            local kind, changed = limbo:stage(id, stage, nowS(), elapsed)
            if kind and not stageHeard then
                stageHeard = true
                log("readiness: platform stage listener is live (first report: player=%d stage=%s)", id, tostring(stage))
            end
            if kind == "terminal" and changed then
                log("readiness: player=%d name=%s reported stage=%s after %ss -- the appearance shell will not retry this session (KB-60)",
                    id, tostring(GetPlayerName(id)), tostring(stage), tostring(math.floor(tonumber(elapsed) or 0)))
            end
        end)
end)

--- Say the thing, once per decision, to the player and to the host log (L63: during a tester window the host
--- reads these lines under time pressure, so the line carries the diagnosis, not just the fact).
local function actOnReadiness(a)
    local name = tostring(a.name or GetPlayerName(a.id))
    if a.kind == "advise" then
        local advice = Readiness.advice(a)
        log("readiness: player=%d name=%s connected %ds and CANNOT PLAY (%s) -- warning %d (KB-60). Advising reconnect.",
            a.id, name, math.floor(a.waited), Readiness.why(a), a.warned)
        tell(a.id, advice.chat)
        pcall(Open77.notifications.send, a.id, {
            type = "warning", title = advice.title, icon = "NCM", durationMs = 12000,
            message = advice.message,
        })
    elseif a.kind == "gaveup" then
        log("readiness: player=%d name=%s still cannot play after %ds (%s); no longer warning (KB-60)",
            a.id, name, math.floor(a.waited), Readiness.why(a))
    elseif a.kind == "recovered" then
        log("readiness: player=%d name=%s reached a playable world after %ds", a.id, name, math.floor(a.waited))
    elseif a.kind == "vanished" then
        log("readiness: player=%d name=%s left after %ds without ever being able to play (%s) (KB-60)",
            a.id, name, math.floor(a.waited), Readiness.why(a))
    end
end

--- One sweep thread for the whole server, started at resource start and never stopped. It asks the platform
--- who is connected -- which is the only question that gets a truthful answer when a player's own readiness
--- events are the thing that failed.
local function startReadinessSweep()
    CreateThread(function()
        while true do
            Wait(SWEEP_S * 1000)
            local ok, all = pcall(Open77.players.all)
            if ok and type(all) == "table" then
                local snapshot = {}
                for _, raw in ipairs(all) do
                    local id = tonumber(raw)
                    if id then
                        snapshot[#snapshot + 1] = {
                            id = id, name = GetPlayerName(id), inWorld = inTheWorld(id),
                        }
                    end
                end
                for _, a in ipairs(limbo:sweep(nowS(), snapshot)) do
                    local okAct, err = pcall(actOnReadiness, a)
                    if not okAct then log("readiness: acting on %s for player=%s failed: %s", tostring(a.kind), tostring(a.id), tostring(err)) end
                end
            end
        end
    end)
end

-- ---------------------------------------------------------------------------------------------
-- L110: where you log out is where you log in
-- ---------------------------------------------------------------------------------------------
--
-- A property of the WORLD, not of racing. Freeroam and races alike: leave in Pacifica, return in Pacifica.
--
-- **Restoring somebody into a live race is explicitly not the goal.** L20's 180 s reconnect grace is a
-- sporting rule with tests behind it and is untouched; this only decides WHERE a rejoining driver is placed.
-- Continuing a race inside that grace stays the driver's choice.
--
-- The rule lives in `world.location`; this file only observes, stores and acts. The safety argument that makes
-- it tractable without a server-side raycast: **we never invent a position, we replay one the player was
-- standing at**, which was standable ground when it was recorded. What can still change is the world, so the
-- remaining guards are staleness, sanity, refusing a saved seat, and KB-58 separation on arrival.
local LOCATION_SAVE_S = 20
local lastSaved = {}       -- driverId -> the position last written, so a stationary player is not re-written
local saveRefused = {}     -- playerId -> the last refusal logged, so the join window is one line and not a stream

--- Is this player standing anywhere yet? (KB-113)
---
--- The bug this exists to stop: during the join window the client reports a placeholder puppet at the world
--- origin, the sweep stored it as a location, and the restore three seconds later teleported the player into
--- it. `fresh` cannot separate those -- the placeholder snapshots are genuinely fresh, and the readiness sweep
--- logged `in-world=yes` for a player it was simultaneously reporting as CANNOT PLAY. The rule that CAN tell
--- them apart is the one KB-60 already established, so this asks that question instead.
---
--- The disconnect save is the exception, and deliberately so: it is the most valuable position we ever take,
--- and by the time the handler runs the puppet may already be gone, which would read as "not playable" for a
--- driver who spent an hour racing. Having been playable once this session is enough for that one caller.
local function standingSomewhere(pid, reason)
    local st = limbo:state(pid, nowS(), inTheWorld(pid))
    if st.playable then
        playedThisSession[pid] = true
        return true
    end
    if reason == "disconnect" and playedThisSession[pid] then return true end
    return false, st.known and Readiness.why(st) or "not tracked"
end

local restoring = {}   -- playerId -> true while the client is being moved to its saved spot (KB-207)
local lastSample = {}  -- playerId -> { z, t }: the previous save sample, for the airborne rule (KB-339)

local function saveLocation(pid, driverId, reason)
    if not (driverId and MySQL and MySQL.isReady()) then return end
    -- The platform's spawn (the template save's Badlands point) is where the body stands until the restore
    -- lands; storing it would make the NEXT join restore to the Badlands. Disconnect included.
    if restoring[pid] then return end
    local standing, why = standingSomewhere(pid, reason)
    if not standing then
        -- One line per reason per player: the join window is ~12-120 s of sweeps and this must not become a
        -- stream. Saves were silent before KB-113, which is exactly why a write of the world origin hid.
        if saveRefused[pid] ~= why then
            saveRefused[pid] = why
            log("location: not saving for driver=%s -- %s (not a position anyone is standing at)",
                tostring(driverId):sub(1, 8), tostring(why))
        end
        return
    end
    saveRefused[pid] = nil
    local ok, p = pcall(Open77.players.get, pid)
    if not ok or type(p) ~= "table" or not p.position then return end
    local here = { x = p.position.x, y = p.position.y, z = p.position.z }
    -- KB-339: a car in flight under `maxZ` is not standing anywhere. Judged against the previous sample, and for
    -- the disconnect save too (leaving at altitude must keep the last grounded spot, not the sky).
    local prevSample = lastSample[pid]
    lastSample[pid] = { z = here.z, t = nowS() }
    local flying, vz = Location.airborne(prevSample, here, nowS())
    if flying then
        if saveRefused[pid] ~= "airborne" then
            saveRefused[pid] = "airborne"
            log("location: not saving %.1f,%.1f,%.1f for driver=%s -- airborne (%.1f m/s vertical since the last sample)",
                here.x, here.y, here.z, tostring(driverId):sub(1, 8), vz)
        end
        return
    end
    local sane, badly = Location.valid(here)
    if not sane then
        -- A fall reaches here as a legitimate-looking reading (KB-113: z = -906 was stored and replayed).
        if saveRefused[pid] ~= badly then
            saveRefused[pid] = badly
            log("location: not saving %.1f,%.1f,%.1f for driver=%s -- %s",
                here.x, here.y, here.z, tostring(driverId):sub(1, 8), tostring(badly))
        end
        return
    end
    if not Location.worthSaving(lastSaved[driverId], here) and reason ~= "disconnect" then return end
    lastSaved[driverId] = here
    local seated = false
    local okV, v = pcall(function() return p.vehicle or p.inVehicle end)
    if okV and v then seated = true end
    pcall(function()
        MySQL.insert.await(
            "INSERT INTO driver_location (ncm_driver_id, server_id, x, y, z, heading, bucket, in_vehicle, saved_at) " ..
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE " ..
            "x=VALUES(x), y=VALUES(y), z=VALUES(z), heading=VALUES(heading), bucket=VALUES(bucket), " ..
            "in_vehicle=VALUES(in_vehicle), saved_at=VALUES(saved_at)",
            { driverId, (worldIdentity()), here.x, here.y, here.z,
              tonumber(p.heading or p.yaw) or 0, tonumber(p.bucket) or 0, seated and 1 or 0,
              math.floor(Open77.time.unix()) })
    end)
end

--- Put a rejoining driver back where they were, or say why not. A refusal is never silent: a stranded player
--- looks exactly like a working one, which is the lesson of KB-72 and KB-76.
local function decideLocation(pid, driverId)
    if not (driverId and MySQL and MySQL.isReady()) then return nil end
    -- L329: the driver may canonically be in NCM Deep or at another host's place; then Night City is not where they are
    if NcmCanonical and NcmCanonical.claimJoin and NcmCanonical.claimJoin(pid, driverId) then
        log("location: driver=%s is canonically away from Night City's surface -- no surface restore", tostring(driverId):sub(1, 8))
        return nil
    end
    local ok, row = pcall(function()
        return MySQL.single.await(
            "SELECT x, y, z, heading, bucket, in_vehicle, saved_at FROM driver_location " ..
            "WHERE ncm_driver_id = ? AND server_id = ?",
            { driverId, (worldIdentity()) })
    end)
    if not ok or type(row) ~= "table" then
        log("location: nothing stored for driver=%s (default spawn)", tostring(driverId):sub(1, 8))
        return nil
    end
    local saved = { x = row.x, y = row.y, z = row.z, heading = row.heading, bucket = row.bucket,
                    inVehicle = tonumber(row.in_vehicle) == 1, savedAt = tonumber(row.saved_at) }
    -- L330: the Racing Week is a temporal loop -- a position from before this run began is not where the driver wakes
    local okW, wk = pcall(function() return NcmWeek and NcmWeek.read and NcmWeek.read() end)
    local runStart = okW and type(wk) == "table" and wk.clock and wk.clock.startUtc or nil
    local should, why = Location.shouldRestore(saved, math.floor(Open77.time.unix()),
        { connectedAt = connectedAtUnix[pid], runStartUtc = runStart })
    if not should then
        log("location: NOT restoring driver=%s (%s) -- default spawn", tostring(driverId):sub(1, 8), tostring(why))
        return nil
    end
    local pose = Location.arrivalPose(saved)
    -- L110 owes them their position back, not a second arrival. The platform has already placed them, and
    -- when it placed them where they left, a faded teleport to the same spot is the "I spawn in twice" the
    -- owner reported -- paid on every single join, because the two positions usually agree.
    local okHere, here = pcall(Open77.players.get, pid)
    local current = okHere and type(here) == "table" and here.fresh and here.position or nil
    -- **The guard is conditional, and that is the remaining hole.** `fresh` is exactly the field KB-113
    -- records as unreliable -- the readiness sweep reported `in-world=yes` for a player it simultaneously
    -- called CANNOT PLAY -- so when it reads false `current` is nil, `alreadyThere` never runs, and the
    -- teleport fires unconditionally. That is the double spawn coming back without the fix being touched.
    -- Say so in the log rather than inferring it later from a silence.
    if not current then
        log("location: driver=%s cannot be read before restore (ok=%s fresh=%s) -- the already-there guard " ..
            "is being SKIPPED, so a second arrival is possible",
            tostring(driverId):sub(1, 8), tostring(okHere),
            tostring(type(here) == "table" and here.fresh or "?"))
    end
    if current and Location.alreadyThere(current, pose) then
        log("location: driver=%s is already at %.1f,%.1f,%.1f -- no second arrival",
            tostring(driverId):sub(1, 8), pose.x, pose.y, pose.z)
        return nil
    end
    return pose, saved
end

--- The old server-side arrival: a faded teleport after the platform has already shown its spawn. Kept only as
--- the fallback for a client that never asked (KB-207) or whose own settle failed.
local function teleportTo(pid, driverId, pose, saved)
    local okTp, reason = pcall(Open77.players.teleport, pid,
        { x = pose.x, y = pose.y, z = pose.z }, { fade = true, dismount = true })
    if not okTp or reason == false then
        log("location: teleport refused for driver=%s: %s -- default spawn", tostring(driverId):sub(1, 8), tostring(reason))
        return
    end
    log("location: restored driver=%s to %.1f,%.1f,%.1f (saved %ds ago) by SERVER teleport",
        tostring(driverId):sub(1, 8), pose.x, pose.y, pose.z,
        math.floor(Open77.time.unix()) - ((saved and saved.savedAt) or 0))
    Wait(1200)
    separate(pid, "location restore")   -- KB-58: nobody arrives inside somebody else
end

local function restoreLocation(pid, driverId)
    local pose, saved = decideLocation(pid, driverId)
    if pose then teleportTo(pid, driverId, pose, saved) end
end

-- **KB-207: one arrival, not two.** NCM cannot choose the platform's spawn point, so every join first showed the
-- template save's Badlands spawn (2566.9, 112.6) and then, ~4 km away, a second loading screen for the restore.
-- Now the client covers its own screen the moment its body exists, ASKS for its destination, moves itself with
-- `travel.teleportAndSettle` under black and reports back (`client/arrival.lua`). The decision is unchanged
-- (`decideLocation`); only who moves the body, and when the player is allowed to see, changed.
local readyAt, decided, pendingPose = {}, {}, {}
local function answerLocation(pid)
    if decided[pid] then TriggerClientEvent("ncm:location.restore", pid, false); return end
    decided[pid] = true
    -- Same timing as the old restore: after readiness plus the platform's placement window.
    for _ = 1, 60 do if readyAt[pid] then break end; Wait(500) end
    if readyAt[pid] then
        local left = 2.5 - (nowS() - readyAt[pid])
        if left > 0 then Wait(math.floor(left * 1000)) end
    end
    local prof = NcmIdentity.get(pid)
    local pose, saved = nil, nil
    if prof and prof.ncmDriverId then pose, saved = decideLocation(pid, prof.ncmDriverId) end
    if not pose then TriggerClientEvent("ncm:location.restore", pid, false); return end
    restoring[pid] = true
    local mine = { pose = pose, saved = saved, driverId = prof.ncmDriverId }
    pendingPose[pid] = mine
    TriggerClientEvent("ncm:location.restore", pid, { x = pose.x, y = pose.y, z = pose.z, heading = pose.heading })
    -- A client that never reports must not leave saving switched off for the session.
    Wait(45000)
    if pendingPose[pid] == mine then pendingPose[pid] = nil; restoring[pid] = nil end
end
RegisterNetEvent("ncm:location.request", function()
    local pid = tonumber(source) or 0
    if pid > 0 then CreateThread(function() answerLocation(pid) end) end
end)
RegisterNetEvent("ncm:location.arrived", function(state)
    local pid = tonumber(source) or 0
    local p = pendingPose[pid]; pendingPose[pid] = nil
    restoring[pid] = nil
    if not p then return end
    state = tostring(state or "?")
    CreateThread(function()
        if state == "settled" or state == "near" then
            log("location: restored driver=%s to %.1f,%.1f,%.1f under cover (%s)", tostring(p.driverId):sub(1, 8),
                p.pose.x, p.pose.y, p.pose.z, state)
            Wait(1200)
            separate(pid, "location restore")   -- KB-58
        else
            log("location: client settle failed for driver=%s (%s) -- falling back to a server teleport",
                tostring(p.driverId):sub(1, 8), state)
            teleportTo(pid, p.driverId, p.pose, p.saved)
        end
    end)
end)

--- One sweep for the whole server, same shape as the readiness sweep (L98): driven by a periodic pass over
--- who is actually connected, never by an event that may not fire.
local function startLocationSweep()
    CreateThread(function()
        while true do
            Wait(LOCATION_SAVE_S * 1000)
            local ok, all = pcall(Open77.players.all)
            if ok and type(all) == "table" then
                for _, raw in ipairs(all) do
                    local pid = tonumber(raw)
                    local prof = pid and NcmIdentity.get(pid) or nil
                    if prof and prof.ncmDriverId then
                        pcall(saveLocation, pid, prof.ncmDriverId, "sweep")
                    end
                end
            end
        end
    end)
end

-- A second `onResourceStart` handler, deliberately down here: the one at the top of this file is created
-- before `startReadinessSweep` exists as a local, so it could not call it.
AddEventHandler("onResourceStart", function(name)
    if name ~= RESOURCE then return end
    local now = nowS()
    local ok, all = pcall(Open77.players.all)
    local adopted = 0
    if ok and type(all) == "table" then
        for _, raw in ipairs(all) do
            -- Already connected when we started, so `onPlayerReady` will never fire for them again.
            -- Presume they are past the barrier; a platform stage report still overrides that.
            if limbo:adopt(raw, now, GetPlayerName(tonumber(raw) or 0)) then adopted = adopted + 1 end
        end
    end
    startReadinessSweep()
    startLocationSweep()
    log("location: saving every %ds (L110)", LOCATION_SAVE_S)
    log("readiness: sweep every %ds over the connected list (KB-60); adopted %d player(s); platform stage listener=%s",
        SWEEP_S, adopted, stageListener and "on" or "OFF (stage detail unavailable; sweep unaffected)")
end)

-- Server console: ncm.readiness.test <playerId> [stage] -- inject a platform stage report as if the appearance
-- shell had sent one, so the whole advise path can be watched firing on a real player.
--
-- A watchdog that has never been seen fire is not a tested watchdog. KB-58 is on the "live but unverified" list
-- for exactly that reason, and KB-60 itself is a watchdog that turned out not to work when its moment came.
-- Waiting for another stranger to break is not a test plan.
--
-- This injects EVIDENCE only, never readiness itself: nothing here releases a hold, mints anything or lies to
-- freeroam. It is also self-healing -- the report goes stale after `staleStageS` and the player is logged as
-- recovered -- so it is safe to run against a live, healthy session.
RegisterCommand("ncm.readiness.test", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    local stage = (args and args[2]) or "appearance_failed"
    if not pid then
        log("usage: ncm.readiness.test <playerId> [stage]  (stages: player_reset, appearance_record, appearance_applying, appearance_failed, alive_or_gameplay_announcement)")
        return
    end
    local kind = limbo:stage(pid, stage, nowS(), 0)
    if not kind then log("readiness: '%s' is not a stage the appearance shell reports", tostring(stage)); return end
    log("readiness: INJECTED stage=%s (%s) for player=%d -- the sweep will treat this as real until it goes stale",
        stage, kind, pid)
end, false)

-- Server console: ncm.readiness -- who is connected, and who among them can actually play.
RegisterCommand("ncm.readiness", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    local now = nowS()
    local ok, all = pcall(Open77.players.all)
    if not ok or type(all) ~= "table" then log("readiness: player list unavailable"); return end
    if #all == 0 then log("readiness: nobody connected"); return end
    for _, raw in ipairs(all) do
        local id = tonumber(raw) or 0
        local st = limbo:state(id, now, inTheWorld(id))
        if st.known then
            log("readiness: player=%d name=%s %s (%s) waited=%ds warned=%d",
                id, tostring(GetPlayerName(id)), st.playable and "PLAYABLE" or "CANNOT PLAY",
                Readiness.why(st), math.floor(st.waited), st.warned)
        else
            log("readiness: player=%d name=%s not tracked yet", id, tostring(GetPlayerName(id)))
        end
    end
end, false)

AddEventHandler("onPlayerReady", function(playerId)
    local id = tonumber(playerId) or 0
    log("ready: %s", describePlayer(id))
    -- KB-39/KB-60: the barrier lifting is not the same as being able to play, so this only records the fact.
    -- The sweep decides, and the sweep runs whether or not this event ever arrives.
    limbo:ready(id, nowS())
    separateWhenReady(id, "join")   -- KB-58: the platform's spawn point does not know who is standing on it
    -- L110: put them back where they left, or log why not. After readiness, so there is a puppet to move.
    readyAt[id] = nowS()
    CreateThread(function()
        -- KB-207: the client asks for its destination and moves itself under black. This is only the fallback
        -- for a client that never asked.
        Wait(30000)
        if decided[id] or not readyAt[id] then return end
        decided[id] = true
        local prof = NcmIdentity.get(id)
        if prof and prof.ncmDriverId then
            log("location: client never asked for its arrival (player=%d) -- server restore fallback", id)
            pcall(restoreLocation, id, prof.ncmDriverId)
        end
    end)
    local prof = NcmIdentity.get(id)
    if prof then
        local title = prof.minted and "Welcome to Night City Motorsports" or "Welcome back"
        pcall(Open77.notifications.send, id, {
            type = "info",
            title = title,
            message = ("NCM Driver: %s  #%s  ·  rep %s  ·  SR %s"):format(
                prof.display, tostring(prof.number or "--"),
                tostring(prof.dimensions.reputation or 0), tostring(prof.sr.sr or "?")),
            icon = "NCM",
            durationMs = 8000,
        })
        tell(id, NcmIdentity.describe(prof) .. (prof.minted and "  (new driver minted)" or "  (persisted)"))

        -- Visitor welcome (owner, 2026-09-22). Strangers do walk in -- the server is reachable and the
        -- whitelist is off (KB-36, KB-52) -- and the owner's posture is that this is fine: "if they see
        -- plumbing, they see plumbing." What is NOT fine is someone spawning in, finding no car, no
        -- instructions and no idea what NCM is, and leaving. So a first-time driver gets one short toast and
        -- two chat lines: what this is, that it is half-built, and the single command that gets them moving.
        --
        -- Deliberately small. It fires ONCE, for a newly minted driver only -- a returning driver already
        -- knows, and an unsolicited card every join is the thing we just removed (IDEA-127).
        if prof.minted then
            CreateThread(function()
                Wait(6000)   -- let the arrival toast land and be read first
                TriggerEvent("ncm:comms:send", id, {
                    id="onboarding.paddock",category="orientation",priority="actionable",
                    title="NCM · THE CITY UNDER THE CITY",
                    message="F6 opens the paddock: your Driver File, live races, Market and Machine Index. /ncm help is always there.",
                    reference="driver",surface="toast",repeatPolicy={mode="once"},durationMs=14000,
                })
                tell(id, "Night City Motorsports — a racing layer for OPEN//77. We are in ALPHA: expect rough edges, and things may break or restart while you are here.")
                tell(id, "Paddock: press F6  ·  Driver snapshot: /ncm.status  ·  Full command list: /ncm help  ·  Buy a Machine in Market, then call it from Machine Index.")
            end)
        end

        CreateThread(function() NcmGarage.claimGridCar(id) end)   -- team car parked on the grid for this driver? (M7-lite)
        -- NCM Driver Profile questionnaire (L48, P29): first join, or a newer questionnaire version
        local Q = Core.get("onboarding.questionnaire")
        -- SHELVED for now (owner, 2026-09-22): the Driver Profile questionnaire is TW2 onboarding and must not
        -- be the first thing a walk-in visitor meets. Strangers do arrive -- the server is reachable and the
        -- whitelist is off (KB-36, KB-52) -- and being asked to fill in a profile before being told how to get
        -- a car is backwards for a server we want to feel friendly (owner: "regular joins (and mystery ones)
        -- should get normal expected server treatment").
        --
        -- Nothing is deleted: the questionnaire, its core module, `/ncm.q`, the panel and the `ncmOnboarding`
        -- bag all still work. Only the automatic prompt on join is off. `ncm.q.ask <playerId>` offers it
        -- deliberately, which is what TW1/TW2 will use; flipping `askOnJoin` back to true restores the old
        -- behaviour in one line.
        local askOnJoin = false   -- TW2 gate (L59/L60); see IDEA-087
        if askOnJoin and NcmIdentity.onboardingPending(prof, Q.VERSION) then
            pcall(function() Open77.state.player(id):set("ncmOnboarding", { pending = true, version = Q.VERSION }) end)
            tell(id, "Complete your NCM Driver Profile: the panel opens by itself, or answer here with /ncm.q a|b|c|d.")
            tell(id, Q.prompt(1))
        else
            -- publish a NON-pending bag either way: the client panel watches this key, and leaving it unset
            -- means a stale `pending = true` from an earlier session could re-open the questionnaire (KB-41).
            pcall(function()
                Open77.state.player(id):set("ncmOnboarding",
                    { version = prof.onboarding and prof.onboarding.version or nil, complete = true })
            end)
        end
    else
        tell(id, "NCM driver unavailable this session (database)")
    end
end)

-- ncm.q.ask <playerId> -- offer the Driver Profile questionnaire to one player on purpose.
-- The join-time prompt is shelved (above); this is how TW1/TW2 onboarding asks for it when it is actually wanted.
RegisterCommand("ncm.q.ask", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.q.ask <playerId>"); return end
    local prof = NcmIdentity.get(pid)
    if not prof then log("ncm.q.ask: no NCM driver on player %d", pid); return end
    local Q = Core.get("onboarding.questionnaire")
    pcall(function() Open77.state.player(pid):set("ncmOnboarding", { pending = true, version = Q.VERSION }) end)
    tell(pid, "Complete your NCM Driver Profile: the panel opens by itself, or answer here with /ncm.q a|b|c|d.")
    tell(pid, Q.prompt(1))
    log("questionnaire offered to player=%d", pid)
end, false)

-- E0 part B, probe 1 receiver (kept: cheap, documents host-wide TriggerEvent).
AddEventHandler("ncm:probe:ping", function(from, stamp)
    log("pong: received ncm:probe:ping from %s stamp=%s", tostring(from), tostring(stamp))
end)


AddEventHandler("onPlayerDisconnected", function(playerId, reason)
    log("disconnected: player=%s reason=%s", tostring(playerId), tostring(reason))
    -- KB-60: if they were being warned when they went, that is the line worth having. Trip[ABK]'s departure
    -- left no trace at all; this one does, with the diagnosis attached.
    -- Save before anything else: a clean disconnect is the most valuable position we ever get.
    local leaving = NcmIdentity.get(tonumber(playerId) or 0)
    if leaving and leaving.ncmDriverId then
        pcall(saveLocation, tonumber(playerId) or 0, leaving.ncmDriverId, "disconnect")
        lastSaved[leaving.ncmDriverId] = nil
    end
    local gone = tonumber(playerId) or 0
    connectedAtUnix[gone], playedThisSession[gone], saveRefused[gone] = nil, nil, nil
    readyAt[gone], decided[gone], pendingPose[gone], restoring[gone] = nil, nil, nil, nil
    local departure = limbo:forget(playerId, nowS())
    if departure then
        log("readiness: player=%s name=%s left after %ds without ever being able to play (%s) -- warned %d time(s) (KB-60)",
            tostring(playerId), tostring(departure.name), math.floor(departure.waited),
            Readiness.why(departure), departure.warned)
    end
    NcmIdentity.forget(playerId)
end)

--- `/ncm help` opens the NCM Help surface (a WebUI panel), and leaves a two-line trace in chat.
---
--- The panel is the experience, not the chat dump it replaces: Help has to hold orientation, what works today,
--- known player-affecting issues and a problem-report form, and none of that is a sequence of chat lines.
--- The COMMAND stays because it is the property chat has and a keybind does not -- memorable, typeable from
--- anywhere, and tellable to another player. Three of NCM's four bindings already collide (KB-62), so Help
--- deliberately takes no key of its own; when the F6 shell lands it becomes a tab and this command still works.
---
--- The two chat lines are the fallback section 1 asks for: if the panel never draws, the player is not left
--- with silence, and the KB-65 telemetry will say which happened.
local helpSeq = 0
local function showHelp(playerId)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return end
    helpSeq = helpSeq + 1
    local ok = pcall(function()
        Open77.state.player(pid):set("ncmHelp", { seq = helpSeq, at = math.floor(Open77.time.unix()) })
    end)
    tell(pid, "NIGHT CITY MOTORSPORTS · HELP is opening. It covers what NCM is, what works today, and how to report a problem.")
    tell(pid, "Races: F6 · Messages: F6 → MESSAGES · Vehicle Collection: F10 · This page again: /ncm help")
    if not ok then
        log("help: could not set the ncmHelp bag for player=%d", pid)
        tell(pid, "The Help screen could not open. Reconnecting usually fixes it.")
    end
    log("help requested by player=%d (seq=%d)", pid, helpSeq)
end

-- `/ncm` — your NCM driver; `/ncm garage|car <Class>|return` — issued cars (garage.lua).
-- Help is deliberately repeatable: every transient welcome points back to this permanent recovery surface.
RegisterCommand("ncm", function(source, args)
    local caller = tonumber(source) or 0
    args = type(args) == "table" and args or {}
    if caller > 0 then
        local sub = args[1] and tostring(args[1]):lower() or nil
        if sub == "help" or sub == "lost" or sub == "docs" then showHelp(caller); return end
        if args[1] and NcmGarage.command(caller, args) then return end
        tell(caller, NcmIdentity.describe(NcmIdentity.get(caller)))
        tell(caller, NcmGarage.describe(caller) .. "  —  /ncm garage · /ncm return")
    else
        for _, pid in ipairs(Open77.players.all()) do log("%s | %s", describePlayer(pid), NcmGarage.describe(pid)) end
    end
end, false)

-- Dot aliases are cheap forgiveness for players who infer the repository/console naming style.
RegisterCommand("ncm.help", function(source) if (tonumber(source) or 0) > 0 then showHelp(source) end end, false)
RegisterCommand("ncm.lost", function(source) if (tonumber(source) or 0) > 0 then showHelp(source) end end, false)
RegisterCommand("ncm.docs", function(source) if (tonumber(source) or 0) > 0 then showHelp(source) end end, false)

-- Chat-free paths (KB-4: a second local instance renders no WebUI, so no chat):
--   server console:  ncm.car <playerId> <Class> [team]   |   ncm.return <playerId>   (Formula + team = RB15 livery)
--   client dev console (`): resource.emit ncm:console car sport   (bridged to the same dispatcher)
RegisterCommand("ncm.car", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.car <playerId> <Class> [team]"); return end
    CreateThread(function()
        local ok = NcmGarage.command(pid, { "car", args[2] or "Sport", args[3] }, true)   -- operator (L102)
        log("ncm.car player=%d -> %s", pid, tostring(ok))
    end)
end, false)

-- Server console: ncm.tp <playerId> <toPlayerId|venue>  -- dev teleport beside another player or to the next venue
-- Host kit (Batch 2): the league asks the world to move a player (ncm.warp, /ncm.ar tp). Seated players are
-- dismounted first by warping them out of the car (KB-12: teleport's dismount flag is a no-op).
AddEventHandler("ncm:warp", function(pid, target)
    CreateThread(function()
        pid = tonumber(pid) or 0
        if pid <= 0 or type(target) ~= "table" then return end
        local ok, reason = Open77.players.teleport(pid, { x = target.x, y = target.y, z = (target.z or 0) + 1.0 }, { heading = target.heading, fade = true, dismount = true })
        if ok then CreateThread(function() Wait(1200); separate(pid, "tp") end) end   -- KB-58: "beside", not "inside"
        log("warp player=%d -> %.1f,%.1f (%s): %s %s", pid, target.x, target.y, tostring(target.why or ""), tostring(ok), tostring(reason or ""))
        pcall(Open77.chat.send, pid, ok and ("[NCM] Moved: " .. tostring(target.why or "host")) or ("[NCM] Warp failed: " .. tostring(reason)))
    end)
end)

-- Host kit: reset the world without a restart — every issued car back, the venue undressed, rides cleared.
AddEventHandler("ncm:worldReset", function()
    CreateThread(function()
        local cars = NcmGarage and NcmGarage.returnAll and NcmGarage.returnAll("world_reset") or 0
        if NcmVenue and NcmVenue.dressDown then NcmVenue.dressDown("world_reset") end
        if NcmPickup and NcmPickup.clearAll then NcmPickup.clearAll("world_reset") end
        log("world reset: %d car(s) returned", cars)
    end)
end)

RegisterCommand("ncm.tp", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.tp <playerId> <toPlayerId|venue>"); return end
    CreateThread(function()
        local target, targetName
        local to = tostring(args[2] or "venue")
        if tonumber(to) then
            local p = Open77.players.get(tonumber(to))
            if p and p.position then
                target = { x = p.position.x + 4, y = p.position.y + 4, z = p.position.z + 0.5 }
                targetName = ("player %s (%s)"):format(tostring(to), tostring(p.name or "?"))
            end
        else
            local cal = GlobalState.ncmCalendar
            local nxt = type(cal) == "table" and cal.next and cal.next[1] or nil
            if nxt then
                target = { x = nxt.venue.x + 6, y = nxt.venue.y, z = nxt.venue.z + 0.5 }
                targetName = ("%s (%s)"):format(tostring(nxt.venue.name or "venue"), tostring(nxt.eventId or "?"))
            end
        end
        if not target then log("ncm.tp: no target"); return end
        local ok, reason = Open77.players.teleport(pid, target, { fade = true, dismount = true })
        -- KB-21: name where the player went. This used to print a raw Lua table address and a bare `nil`,
        -- which is useless to a host reading the log under time pressure during a session (L63).
        log("ncm.tp player=%d -> %s at %.1f,%.1f,%.1f : ok=%s%s", pid, targetName or "point",
            target.x, target.y, target.z, describe(ok), reason ~= nil and (" reason=" .. describe(reason)) or "")
    end)
end, false)

-- L316 S0 (doc 51 §S0): the altitude expedition. Dev only; nothing here changes the world for anyone else.
-- Server console: ncm.lift <playerId> <metres> -- straight up from where the player stands (or sits: teleport
-- dismounts, KB-12, so this probes the world ON FOOT; the in-car climb is NCM Thrust's hold mode).
RegisterCommand("ncm.lift", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, metres = tonumber(args and args[1]), tonumber(args and args[2])
    if not pid or not metres then log("usage: ncm.lift <playerId> <metres>"); return end
    CreateThread(function()
        local p = Open77.players.get(pid)
        if not (p and p.position) then log("ncm.lift: player %d has no position", pid); return end
        local target = { x = p.position.x, y = p.position.y, z = p.position.z + metres }
        local ok, reason = Open77.players.teleport(pid, target, { fade = false, dismount = true })
        log("ncm.lift player=%d +%.0f m -> z=%.1f (from %.1f) : ok=%s%s", pid, metres, target.z, p.position.z,
            describe(ok), reason ~= nil and (" reason=" .. describe(reason)) or "")
    end)
end, false)

-- L317 SEAM-1b (doc 51 §6): the move from the side that owns it. A client teleport of a network vehicle is a
-- `motion_jump` to OPEN//77 and the server revokes the car (§SG2: three J moves, three `serverrevoke` in the same
-- millisecond, the car snapped back with no speed). `Open77.vehicles.setTransform` is the server's own move -- a teleport
-- PLUS a lease revoke PLUS an epoch bump, and it clears the electrical flags (open77_admin, freeroam race) -- so this
-- moves the seated car by `dz`, puts the flags back, and samples the platform's own snapshot for 8 s: does the car
-- stay where it was sent, is the speed kept, does the lease come back to the driver, is the driver still seated.
-- Server console: ncm.seam <playerId> <dz metres>   (dev only; refuses a target below 300 m)
local function seamVehicle(pid)
    local okS, seat = pcall(Open77.vehicles.getPlayerSeat, pid)
    return okS and type(seat) == "table" and tonumber(seat.vehicleId or seat.vehicle or seat.id) or nil, seat
end

--- The server move itself, shared by `ncm.seam` and the automatic doorway. `vz` is the measured climb, for the log.
local function seamMove(pid, vid, dz, why, vz)
    local okB, b = pcall(Open77.vehicles.get, vid)
    if not okB or type(b) ~= "table" then log("ncm.seam: vehicle %d has no snapshot", vid); return false end
    local target = { x = b.x, y = b.y, z = b.z + dz }
    if target.z < 300 then log("ncm.seam: refused, target z=%.1f is below 300 m", target.z); return false end
    local yaw = tonumber(b.yaw or b.heading) or 0
    log("SEAM-1b move (%s): vehicle=%d from %.1f,%.1f,%.1f to z=%.1f | speed %.2f%s owner=%s epoch=%s flags=%s yaw=%s",
        why, vid, b.x, b.y, b.z, target.z, tonumber(b.speed) or -1, vz and (" climbing %.1f m/s"):format(vz) or "",
        tostring(b.physicsOwner), tostring(b.authorityEpoch), tostring(b.flags), tostring(yaw))
    local okT, moved, mwhy = pcall(Open77.vehicles.setTransform, vid, { position = target, yaw = yaw })
    log("SEAM-1b setTransform -> %s %s", tostring(okT and moved), tostring(okT and mwhy or moved))
    if b.flags ~= nil then
        local okF, fl, fwhy = pcall(Open77.vehicles.update, vid, { flags = b.flags })
        log("SEAM-1b flags restored -> %s %s", tostring(okF and fl), tostring(okF and fwhy or fl))
    end
    CreateThread(function()
        local t0 = GetGameTimer()
        for _, at in ipairs({ 100, 300, 1000, 2000, 4000, 8000 }) do
            Wait(math.max(0, at - (GetGameTimer() - t0)))
            local okA, a = pcall(Open77.vehicles.get, vid)
            if okA and type(a) == "table" then
                local seated = false
                for _, o in ipairs(a.occupants or {}) do if tonumber(o.playerId) == pid then seated = true end end
                log("  +%4d ms: z=%.1f (%+.1f from the target) speed=%.2f owner=%s epoch=%s motionAgeMs=%s seated=%s",
                    at, a.z, a.z - target.z, tonumber(a.speed) or -1, tostring(a.physicsOwner), tostring(a.authorityEpoch),
                    tostring(a.motionAgeMs), tostring(seated))
            end
        end
    end)
    return true
end

RegisterCommand("ncm.seam", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, dz = tonumber(args and args[1]), tonumber(args and args[2])
    if not pid or not dz then log("usage: ncm.seam <playerId> <dz metres>"); return end
    CreateThread(function()
        local vid, seat = seamVehicle(pid)
        if not vid then log("ncm.seam: player %d is not seated (%s)", pid, tostring(seat)); return end
        seamMove(pid, vid, dz, "console")
    end)
end, false)

-- (`ncm.seamauto` was removed 2026-10-05: the automatic doorway is `server/snowglobe.lua`, on by itself in development.)

-- `/ncm.altlog` on a client sends its own position once a second; logged here beside the position the SERVER holds
-- for that player, so the gap between them is the replication answer at that altitude. At most 2 lines a second.
local altlogAt = {}
RegisterNetEvent("ncm:altlog", function(x, y, z, speed, inCar, weather)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local now = nowS()
    if altlogAt[pid] and now - altlogAt[pid] < 0.5 then return end
    altlogAt[pid] = now
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return end
    local p = Open77.players.get(pid)
    local sp = p and p.position
    if sp then
        local dx, dy, dz = x - sp.x, y - sp.y, z - sp.z
        log("altlog player=%d client z=%.1f server z=%.1f | gap %.1f m (dz %+.1f) | %s %.1f m/s", pid, z, sp.z,
            math.sqrt(dx * dx + dy * dy + dz * dz), dz, inCar and "in car" or "on foot", tonumber(speed) or -1)
    else
        log("altlog player=%d client z=%.1f | server holds no position | %s", pid, z, inCar and "in car" or "on foot")
    end
    if type(weather) == "string" and weather ~= "" then log("altlog player=%d weather: %s", pid, weather:sub(1, 400)) end
end)

RegisterCommand("ncm.return", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.return <playerId>"); return end
    CreateThread(function() NcmGarage.command(pid, { "return" }) end)
end, false)

-- A client panel failed to draw, or threw while drawing (KB-59 second defect, KB-61).
-- The client cannot say this to the player -- there is no client-side chat API -- and more importantly WE need
-- it: a render fault inside the CEF surface is otherwise visible only in a log file on the player's own machine.
RegisterNetEvent("ncm:panel.fault", function(panel, message, where)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    log("PANEL FAULT player=%d panel=%s: %s%s", pid, tostring(panel), tostring(message),
        (where and where ~= "" ) and (" @ " .. tostring(where)) or "")
    tell(pid, "That panel hit an error and closed itself -- your controls are back. It has been logged.")
end)

-- KB-65: every panel open reports itself, success AND failure, so the failures become interpretable.
--
-- Before this, only faults were reported, which meant the one question that mattered -- how OFTEN does a panel
-- fail to draw? -- had no answer and could not get one. It also could not be answered from a visitor's own
-- client log, because that file is on their machine. So the numbers come here.
--
-- Client-supplied and therefore untrusted: every field is clamped, and a player is rate-limited to one line a
-- second so a looping client cannot bury the log it is supposed to illuminate.
local panelStats = {}        -- panel -> { opens, faults, slowest, lastMs }
local panelLastAt = {}       -- pid -> GetGameTimer() of the last accepted report

local function clampNum(v, lo, hi)
    local n = tonumber(v)
    if not n or n ~= n then return -1 end
    n = math.floor(n)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

RegisterNetEvent("ncm:panel.telemetry", function(d)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(d) ~= "table" then return end
    local nowMs = GetGameTimer()
    if panelLastAt[pid] and (nowMs - panelLastAt[pid]) < 1000 then return end
    panelLastAt[pid] = nowMs

    local panel = tostring(d.panel or "?"):sub(1, 24)
    local ok = d.ok == true
    local ms, pageMs = clampNum(d.ms, -1, 600000), clampNum(d.pageMs, -1, 600000)
    local sent, want = clampNum(d.sent, -1, 4096), clampNum(d.want, -1, 4096)
    local got, held, head = clampNum(d.got, -1, 4096), clampNum(d.held, -1, 100000), clampNum(d.head, -1, 1)

    local st = panelStats[panel]
    if not st then st = { opens = 0, faults = 0, slowest = 0, lastMs = -1 }; panelStats[panel] = st end
    st.opens = st.opens + 1
    if not ok then st.faults = st.faults + 1 end
    if ms > st.slowest then st.slowest = ms end
    st.lastMs = ms

    -- `sent` vs `got` is the KB-63 detector: the bridge drops large messages without a word, so a gap between
    -- what the client put on it and what the page received is that drop, finally visible.
    local lost = (sent >= 0 and got >= 0 and got < sent)
    log("panel %s player=%d panel=%s ms=%d pageMs=%d chunks sent=%d/%d got=%d held=%d head=%d%s | %s: %d open(s) %d fault(s) slowest=%dms",
        ok and "OK" or "FAULT", pid, panel, ms, pageMs, sent, want, got, held, head,
        lost and "  *** CHUNKS LOST ON THE BRIDGE (KB-63) ***" or "",
        panel, st.opens, st.faults, st.slowest)
end)

-- Server console: ncm.panelstats -- how often panels actually fail, which is the question KB-65 could not answer.
RegisterCommand("ncm.panelstats", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    local any = false
    for panel, st in pairs(panelStats) do
        any = true
        local rate = st.opens > 0 and (100.0 * st.faults / st.opens) or 0
        log("panelstats %s: %d open(s), %d fault(s) (%.1f%%), slowest=%dms, last=%dms",
            panel, st.opens, st.faults, rate, st.slowest, st.lastMs)
    end
    if not any then log("panelstats: nothing recorded since start") end
end, false)

RegisterNetEvent("ncm:cmd", function(...)
    local caller = tonumber(source) or 0
    local args = { ... }
    if caller <= 0 then return end
    CreateThread(function()
        log("ncm:cmd from player=%d: %s", caller, table.concat(args, " "))
        if args[1] and NcmGarage.command(caller, args) then return end
        tell(caller, NcmGarage.describe(caller))
    end)
end)

-- A dropped racer came back (ncm_league): put them back where they were and give them a car.
AddEventHandler("ncm:driverResumed", function(playerId, lastPos)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return end
    CreateThread(function()
        if type(lastPos) == "table" then
            local ok, reason = Open77.players.teleport(pid, { x = lastPos.x, y = lastPos.y, z = lastPos.z + 0.5 }, { fade = true, dismount = true })
            log("resume teleport player=%d -> %.1f,%.1f : %s", pid, lastPos.x, lastPos.y, ok and "ok" or tostring(reason))
            Wait(1500)
            -- the racer's last position is where they left it, not where it is free now (KB-58)
            separate(pid, "resume")
        end
        local ok = NcmGarage.reissueLast(pid)
        log("resume car player=%d -> %s", pid, tostring(ok))
    end)
end)

-- ---------------------------------------------------------------------------------------------
-- Questionnaire (Batch 1, item 1): the panel sends all answers at once; chat answers one at a time.
-- ---------------------------------------------------------------------------------------------
local qProgress = {}   -- playerId -> { index, answers }

local function finishQuestionnaire(pid, answers)
    local Q = Core.get("onboarding.questionnaire")
    local ok, why = Q.validate(Q.VERSION, answers)
    if not ok then tell(pid, "Profile not saved: " .. tostring(why)); return false end
    local doc = Q.document(answers, math.floor(Open77.time.unix()))
    local saved, err = NcmIdentity.saveOnboarding(pid, doc)
    if not saved then tell(pid, "Profile not saved: " .. tostring(err)); return false end
    qProgress[pid] = nil
    local top = Q.top(doc.affinity)
    log("onboarding complete player=%d version=%d affinity_top=%s", pid, doc.version, tostring(top))   -- log only; never told
    tell(pid, "Profile complete. Welcome to Night City Motorsports.")
    pcall(Open77.notifications.send, pid, { type = "success", title = "DRIVER PROFILE COMPLETE", message = "Night City Motorsports has your file.", icon = "NCM", durationMs = 6000 })
    return true
end

RegisterNetEvent("ncm:onboarding", function(version, answers)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local Q = Core.get("onboarding.questionnaire")
    if tonumber(version) ~= Q.VERSION then tell(pid, "That questionnaire is out of date; reconnect and it will be offered again."); return end
    if type(answers) ~= "table" then return end
    local list = {}
    for i = 1, #Q.QUESTIONS do list[i] = answers[i] end
    finishQuestionnaire(pid, list)
end)

--- /ncm.q <key> — answer the next question in chat; console: ncm.q <pid> <key>.
RegisterCommand("ncm.q", function(source, args)
    local caller = tonumber(source) or 0
    local pid, key
    if caller > 0 then pid, key = caller, args and args[1] else pid, key = tonumber(args and args[1]), args and args[2] end
    if not pid then log("usage: ncm.q <playerId> <a|b|c|d>"); return end
    local Q = Core.get("onboarding.questionnaire")
    local st = qProgress[pid] or { index = 1, answers = {} }
    qProgress[pid] = st
    key = key and tostring(key):lower() or nil
    if not key then tell(pid, Q.prompt(st.index)); return end
    local q = Q.QUESTIONS[st.index]
    local valid = false
    for _, o in ipairs(q.options) do if o.key == key then valid = true end end
    if not valid then tell(pid, "Answer a, b, c or d. " .. Q.prompt(st.index)); return end
    st.answers[st.index] = key
    st.index = st.index + 1
    if st.index > #Q.QUESTIONS then
        finishQuestionnaire(pid, st.answers)
    else
        tell(pid, Q.prompt(st.index))
    end
end, false)

-- `/ncm.where` — every connected player's identity, bucket, position and driver id.
RegisterCommand("ncm.where", function(source, args)
    local caller = tonumber(source) or 0
    local players = Open77.players.all()
    log("ncm.where by %d | core %s | %d player(s)", caller, Core.VERSION, #players)
    for _, pid in ipairs(players) do
        local line = describePlayer(pid)
        log("  %s", line)
        if caller > 0 then tell(caller, line) end
    end
    if caller > 0 then tell(caller, ("ncm_world v%s, core %s"):format(WORLD_VERSION, Core.VERSION)) end
end, false)

-- ---------------------------------------------------------------------------------------------
-- Restart notice (L90)
--
-- Owner, 2026-09-22: "if we ever reset server we do it with a broadcast message and a 1:00 countdown."
-- KB-5 says never restart underneath clients; this is what to do when a restart must happen anyway. Dropping
-- people mid-race with no warning is the worst thing a host can do to a session, and it costs a race that
-- cannot be re-run.
--
-- NCM cannot restart the host -- it is a resource inside the process -- so this owns the ONLY part it can own:
-- telling every connected player, clearly and repeatedly, before it happens. The operator runs it from Warden's
-- Live Console and starts the restart alongside it (tools/staging/restart-with-warning.sh).
--
-- Deliberately NOT automated end-to-end: the platform has `filesystem.read`/`filesystem.write` permissions that
-- would let a script drop a marker file for NCM to poll, but nothing in the shipped resources uses them and the
-- API shape is undocumented. Guessing it and wrapping the guess in pcall would fail silently, which is the
-- failure mode this codebase keeps getting bitten by. See IDEA-130.
local restartNotice = { until_ = nil, lastSaid = nil }

local function announceAll(title, message, kind, ms)
    for _, pid in ipairs(Open77.players.all()) do
        pcall(Open77.notifications.send, pid, { type = kind or "warning", title = title, message = message,
                                                icon = "NCM", durationMs = ms or 8000 })
        tell(pid, title .. " - " .. message)
    end
end

--- ncm.restart [seconds]  -- default 60. Announces a countdown; does not restart anything itself.
RegisterCommand("ncm.restart", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local secs = math.max(5, math.min(600, tonumber(args and args[1]) or 60))
    restartNotice.until_ = Open77.time.unix() + secs
    restartNotice.lastSaid = nil
    local n = #Open77.players.all()
    log("RESTART NOTICE: %d second(s), %d player(s) connected", secs, n)
    announceAll("SERVER RESTART", ("in %d seconds - finish what you are doing"):format(secs), "warning", 10000)
end, false)

--- ncm.restart.cancel -- call this off if the restart is not happening after all.
RegisterCommand("ncm.restart.cancel", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    if not restartNotice.until_ then log("no restart notice active"); return end
    restartNotice.until_ = nil
    log("restart notice cancelled")
    announceAll("RESTART CANCELLED", "carry on", "success", 6000)
end, false)

CreateThread(function()
    while true do
        Wait(1000)
        local deadline = restartNotice.until_
        if deadline then
            local left = math.floor(deadline - Open77.time.unix() + 0.5)
            -- say it at the moments people actually act on, not every second
            local marks = { 60, 30, 10, 5 }
            for _, m in ipairs(marks) do
                if left == m and restartNotice.lastSaid ~= m then
                    restartNotice.lastSaid = m
                    announceAll("SERVER RESTART", ("in %d seconds"):format(m), "warning", m <= 10 and 5000 or 8000)
                end
            end
            if left <= 0 then
                restartNotice.until_ = nil
                log("RESTART NOTICE elapsed; the operator's restart should land now")
                announceAll("RESTARTING", "back shortly", "warning", 12000)
            end
        end
    end
end)
