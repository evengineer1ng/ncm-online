-- ncm_world / server / pickup — the chauffeur (M7.5a, P24 "platform vehicle AI with the player as passenger").
--
-- ncm_league says who rides and where (`ncm:pickup`); this file runs each ride as its own thread:
--   spawn a team transport ahead of the player -> AI drives up to them -> wait for them to board (any seat)
--   -> AI drives to the venue drop-off -> stop, tell them where their car is -> remove the transport once
--   they are out. Failure is handled on the road, never by teleport: a drive that reports blocked / failed /
--   no progress is re-issued twice, then the AI lets go and the passenger takes the wheel.
-- The RB15 is a single-seater, so the transport is a different car (an executive sedan for now).
-- Every ride logs its timings and any AI failure with positions: that is the E4-for-transport data.
NcmPickup = {}

local Core = NcmCore
local Provisioning = Core.get("world.provisioning")
local Nodes = Core.get("data.nodes")

local function log(fmt, ...) print(("[ncm_world/pickup] " .. fmt):format(...)) end
local function tell(pid, text) pcall(Open77.chat.send, pid, "[NCM] " .. text) end
local function toast(pid, n) pcall(Open77.notifications.send, pid, n) end
local function now() return Open77.time.unix() end

local TRANSPORT_RECORD = "Vehicle.v_standard3_chevalier_emperor"
local BOARD_TIMEOUT_S = 150       -- the ride waits this long for the player to get in
local AT_VENUE_M = 120            -- already this close to the drop-off: no ride
local ARRIVE_M = 10               -- drop-off reached
local PULLUP_M = 8                -- pulled up next to the player
local STALL_S = 30                -- a stop this long is a stall; `blocked`/`no_progress` (<2 m over 8 s, guide) is a wait, not a failure
local MAX_REISSUE = 2
local MAX_FIND_ROAD = 2           -- joinTraffic "find the lane" phases per drive (off-road start, mid-route wedge)
local AFTER_EXIT_S = 45           -- transport lingers this long after the passenger leaves
-- No headless physics: a server vehicle only moves while a ready client has it streamed in (KB-10: a transport born
-- 437 m from its passenger sat still for 80 s). The car must be born next to the passenger, so a road node is used
-- only when it is inside streaming range; otherwise it spawns ahead of the player, off-road or not.
local ROAD_NODE_MAX_M = 60
local ROAD_NODE_MIN_M = 30

local rides = {}                  -- playerId -> ride
local byEvent = {}                -- eventId -> { [playerId] = true }
NcmPickup.rides = rides

local function dist2d(a, b)
    if not a or not b then return math.huge end
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

--- Nearest curated on-road node to a point within [minM, maxM] (data.nodes: all on-road, with heading).
local function nearestRoadNode(pos, minM, maxM)
    local best, bestD
    for _, n in ipairs(Nodes.LIST or {}) do
        if n.road ~= false then
            local d = dist2d(pos, n)
            if d >= (minM or 0) and d <= (maxM or math.huge) and (not bestD or d < bestD) then best, bestD = n, d end
        end
    end
    return best, bestD
end
NcmPickup.nearestRoadNode = nearestRoadNode

local function vehiclePos(vid)
    local ok, v = pcall(Open77.vehicles.get, vid)
    if ok and v then return v.position or { x = v.x, y = v.y, z = v.z }, v end
    return nil
end

--- Which vehicle the player sits in, if the host can tell (defensive over the seat record's shape).
local function seatedIn(pid)
    local ok, seat = pcall(Open77.players.getVehicleSeat, pid)
    if not ok or type(seat) ~= "table" then return nil end
    return seat.vehicleId or seat.vehicle or seat.id
end

local function aiStatus(vid)
    local ok, st = pcall(Open77.vehicles.ai.state, vid)
    if not ok or type(st) ~= "table" then return nil end
    return tostring(st.status or st.state or st.phase or st.task or "?"), st
end

--- One-line dump of a state table (learning the shape of ai.state — E4).
local function flat(t, depth)
    if type(t) ~= "table" then return tostring(t) end
    if (depth or 0) > 1 then return "{…}" end
    local parts = {}
    for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. flat(v, (depth or 0) + 1) end
    table.sort(parts)
    return "{" .. table.concat(parts, " ") .. "}"
end

local function aiBusy(status)
    return status == "driving" or status == "moving" or status == "active" or status == "running" or status == "en_route"
        or status == "waiting" or status == "yielding" or status == "started" or status == "pending"
end

--- Only the AI's own `failed` is a failure. `blocked`/`no_progress` are waits (lights, queues) until they last too
--- long (E4: treating `blocked` as failure cancelled the drive at every stop and sent the car off in recovery).
local function aiFailed(status)
    return status == "failed" or status == "error"
end

--- Ask the AI to drive to `target`; returns true when the task was accepted.
local function drive(ride, target, speed, why)
    -- minSpeed / forcedStartSpeed / boostDrivingStats are the engine command's fields NCM's SP rivals use to keep
    -- rolling through lights and launch instantly (MT_Ecosystem ai_vehicles.lua). Undocumented on the platform's
    -- wrapper; passed in case it forwards them, and requested from the devs (E4).
    local ok, state, reason = pcall(Open77.vehicles.ai.driveTo, ride.vehicleId, {
        position = { x = target.x, y = target.y, z = target.z or 0 }, speed = speed, arrivalRadius = 6, timeoutMilliseconds = 420000,
        behavior = "aggressive", minSpeed = math.min(10, speed), forcedStartSpeed = 8, boostDrivingStats = true, clearTrafficOnPath = true,
    })
    if not ok or not state then
        log("ride player=%d %s: driveTo refused: %s", ride.playerId, why, tostring(reason or state))
        return false
    end
    ride.lastMoveAt = now(); ride.lastPos = nil
    return true
end

--- Off-road start: native routing cannot begin from here (E4 finding, 2026-09-20). Let the traffic AI pull the car
--- onto the nearest lane for a few seconds, then hand back. Returns true when the car actually moved.
local function findRoad(ride, why)
    local from = vehiclePos(ride.vehicleId)
    local ok, st, reason = pcall(Open77.vehicles.ai.joinTraffic, ride.vehicleId, { speed = 6 })
    if not ok or not st then log("ride player=%d %s: joinTraffic refused: %s", ride.playerId, why, tostring(reason or st)); return false end
    local moved = false
    for _ = 1, 12 do
        Wait(1000)
        local pos = vehiclePos(ride.vehicleId)
        if pos and from and dist2d(pos, from) > 4 then moved = true end
        if moved and _ >= 6 then break end
    end
    pcall(Open77.vehicles.ai.stop, ride.vehicleId)
    local pos = vehiclePos(ride.vehicleId)
    log("ride player=%d %s: find-road via joinTraffic -> %s (%.0f m)", ride.playerId, why, moved and "moved" or "did not move", (pos and from) and dist2d(pos, from) or 0)
    return moved
end

--- The navigator (E4, 2026-09-20). Native `driveTo` is a point-and-go planner that fails on some intersections and
--- cannot start off-road, so the drive is done in legs of LEG_M toward the destination, and a leg that stops climbs
--- a recovery ladder: lane-find (joinTraffic) -> back out -> re-aim the leg off the direct bearing -> ride the
--- traffic while it gains ground. Every step logs what it tried and the ground gained.
--- Returns "arrived" | "gave_up" | "abandoned".
local LEG_M = 350
local LEG_REACHED_M = 45
local MAX_RECOVERIES_NO_GAIN = 6
local DRIVE_BUDGET_S = 600

local function bearingPoint(from, to, distance, offsetDeg)
    local dx, dy = to.x - from.x, to.y - from.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1 then return { x = to.x, y = to.y, z = to.z or from.z } end
    local a = math.atan(dy, dx) + math.rad(offsetDeg or 0)
    local r = math.min(distance, d)
    return { x = from.x + math.cos(a) * r, y = from.y + math.sin(a) * r, z = from.z }
end

--- Drive a leg toward `legTarget`; returns "reached" | "stopped" | "abandoned" and the last position.
local function driveLeg(ride, legTarget, radius, speed, why)
    if not drive(ride, legTarget, speed, why) then return "stopped" end
    while true do
        Wait(1000)
        if ride.cancelled then return "abandoned" end
        local pos, v = vehiclePos(ride.vehicleId)
        if not pos then return "abandoned" end
        if dist2d(pos, legTarget) <= radius then return "reached", pos end
        if v and v.moving and (v.speed or 0) > 0.5 then
            ride.lastMoveAt = now()
            if ride.boardedAt and not ride.firstMoveAt then
                ride.firstMoveAt = now()
                log("ride player=%d first movement %.0f s after boarding (%.1f m/s)", ride.playerId, ride.firstMoveAt - ride.boardedAt, v.speed or 0)
            end
        end
        local status, st = aiStatus(ride.vehicleId)
        local still = now() - (ride.lastMoveAt or now())
        if still > 8 and not ride.dumpedState then
            ride.dumpedState = true
            log("ride player=%d %s: standing %.0f s, ai.state = %s", ride.playerId, why, still, flat(st))
        end
        -- Standing still is normal at lights and behind traffic; only the AI's own failure, or a long stop
        -- while it does not claim to be busy, is a stall (E4: 25 s stall detection derailed rides at lights).
        if aiFailed(status) or still > STALL_S then
            log("ride player=%d %s: %s at %.1f,%.1f (ai %s)", ride.playerId, why, aiFailed(status) and ("ai " .. status) or ("stalled " .. math.floor(still) .. " s"), pos.x, pos.y, tostring(status))
            pcall(Open77.vehicles.ai.stop, ride.vehicleId)
            return "stopped", pos
        end
    end
end

--- Let traffic carry the car while distance to `dest` keeps shrinking (max `maxS` seconds). Returns metres gained.
local function rideTraffic(ride, dest, maxS)
    local start = vehiclePos(ride.vehicleId)
    if not start then return 0 end
    local ok, st = pcall(Open77.vehicles.ai.joinTraffic, ride.vehicleId, { speed = 10 })
    if not ok or not st then return 0 end
    local best = dist2d(start, dest)
    local worse = 0
    for _ = 1, maxS do
        Wait(1000)
        if ride.cancelled then break end
        local pos = vehiclePos(ride.vehicleId)
        if not pos then break end
        local d = dist2d(pos, dest)
        if d < best - 2 then best = d; worse = 0 else worse = worse + 1 end
        if worse >= 8 then break end
    end
    pcall(Open77.vehicles.ai.stop, ride.vehicleId)
    return dist2d(start, dest) - best
end

--- A known road node that is ahead (closer to `dest` than `from` by a margin) and within `maxM` of `from`.
local function forwardNode(from, dest, maxM)
    local best, bestScore
    for _, n in ipairs(Nodes.LIST or {}) do
        local dFrom, dDest = dist2d(from, n), dist2d(n, dest)
        if dFrom > 60 and dFrom <= maxM and dDest < dist2d(from, dest) - 80 then
            local score = dFrom + dDest   -- least detour
            if not bestScore or score < bestScore then best, bestScore = n, score end
        end
    end
    return best
end

--- One drive to `target` (a road point: legs to made-up bearing points make the native planner creep — E4),
--- with the recovery ladder only when it stalls: lane-find -> back out -> detour via a road node ahead ->
--- ride the traffic. Returns "arrived" | "gave_up" | "abandoned".
local function driveUntil(ride, target, radius, speed, why)
    local t0 = now()
    local noGain, lastStopPos = 0, nil
    local detour = nil
    while true do
        if ride.cancelled then return "abandoned" end
        if now() - t0 > DRIVE_BUDGET_S then log("ride player=%d %s: drive budget spent", ride.playerId, why); return "gave_up" end
        local pos = vehiclePos(ride.vehicleId)
        if not pos then return "abandoned" end
        if dist2d(pos, target) <= radius then return "arrived" end
        local legTarget, legRadius, label = target, radius, ("%s %.0f m to go"):format(why, dist2d(pos, target))
        if detour then legTarget, legRadius, label = detour, LEG_REACHED_M, ("%s via %s"):format(why, detour.name) end
        local result, stopPos = driveLeg(ride, legTarget, legRadius, speed, label)
        if result == "abandoned" then return "abandoned" end
        if result == "reached" then
            if detour then log("ride player=%d %s: detour node %s reached, resuming direct", ride.playerId, why, detour.name) end
            detour = nil; noGain = 0; ride.lastMoveAt = now()
        else
            local gained = lastStopPos and (dist2d(lastStopPos, target) - dist2d(stopPos, target)) or math.huge
            lastStopPos = stopPos
            if gained < 15 then noGain = noGain + 1 else noGain = 0 end
            ride.failures = (ride.failures or 0) + 1
            if noGain >= MAX_RECOVERIES_NO_GAIN then
                log("ride player=%d %s: %d recoveries without gaining ground — giving up at %.1f,%.1f", ride.playerId, why, noGain, stopPos.x, stopPos.y)
                return "gave_up"
            end
            local rung = noGain % 4
            Wait(500)
            if rung == 0 then
                findRoad(ride, why)
            elseif rung == 1 then
                local behind = bearingPoint(stopPos, target, -15, 0); behind.z = stopPos.z
                drive(ride, behind, 4, why .. " back-out"); Wait(6000); pcall(Open77.vehicles.ai.stop, ride.vehicleId)
                local p2 = vehiclePos(ride.vehicleId) or stopPos
                log("ride player=%d %s: backed out %.0f m", ride.playerId, why, dist2d(p2, stopPos))
            elseif rung == 2 then
                detour = forwardNode(stopPos, target, 700)
                log("ride player=%d %s: detour via %s", ride.playerId, why, detour and detour.name or "no road node ahead")
                if not detour then findRoad(ride, why) end
            else
                local gainedT = rideTraffic(ride, target, 45)
                log("ride player=%d %s: rode traffic, gained %.0f m", ride.playerId, why, gainedT)
                if gainedT > 15 then noGain = 0 end
            end
            ride.lastMoveAt = now()
        end
    end
end

local function removeTransport(ride, reason)
    if ride.removed then return end
    ride.removed = true
    pcall(Open77.vehicles.ai.removeDriver, ride.vehicleId)
    pcall(Open77.vehicles.remove, ride.vehicleId)
    rides[ride.playerId] = nil
    if byEvent[ride.eventId] then byEvent[ride.eventId][ride.playerId] = nil end
    log("ride player=%d ended: %s (%.0f s, failures %d)", ride.playerId, reason, now() - ride.startedAt, ride.failures or 0)
end

--- The passenger drives the rest: release the AI and put them in the driver seat.
local function handOver(ride, why)
    pcall(Open77.vehicles.ai.stop, ride.vehicleId)
    pcall(Open77.vehicles.ai.removeDriver, ride.vehicleId)
    Wait(500)
    local ok, reason = pcall(Open77.players.warpIntoVehicle, ride.playerId, ride.vehicleId, "driver")
    log("ride player=%d hand-over (%s): warp driver -> %s %s", ride.playerId, why, tostring(ok), tostring(reason or ""))
    tell(ride.playerId, ("The ride can't find a road from here — take the wheel and head to %s."):format(ride.venueName))
    toast(ride.playerId, { type = "warning", title = "TAKE THE WHEEL", message = "Drive yourself to " .. ride.venueName, icon = ride.teamShort or "NCM", durationMs = 8000 })
end

--- Follow an authored point list (≤64) to `dest`. `blocked` is a wait; `failed` or a long stall re-issues the
--- route from the nearest remaining point (twice), then gives up so the caller can fall back.
local function followUntil(ride, route, dest, radius, speed, why)
    local t0 = now()
    local reissues = 0
    local startIdx = 1
    while true do
        if ride.cancelled then return "abandoned" end
        if now() - t0 > DRIVE_BUDGET_S then return "gave_up" end
        local pts = {}
        for i = startIdx, #route do pts[#pts + 1] = { x = route[i].x, y = route[i].y, z = route[i].z or 0 } end
        if #pts == 0 or dist2d(pts[#pts], dest) > 20 then pts[#pts + 1] = { x = dest.x, y = dest.y, z = dest.z or 0 } end
        while #pts > 64 do table.remove(pts, 2) end
        local ok, st, reason = pcall(Open77.vehicles.ai.followRoute, ride.vehicleId, {
            points = pts, speed = speed, arrivalRadius = 8, behavior = "aggressive", timeoutMilliseconds = 900000,
            minSpeed = math.min(10, speed), forcedStartSpeed = 8, boostDrivingStats = true, clearTrafficOnPath = true,
        })
        if not ok or not st then log("ride player=%d %s: followRoute refused: %s", ride.playerId, why, tostring(reason or st)); return "gave_up" end
        log("ride player=%d %s: following %d point(s) from index %d", ride.playerId, why, #pts, startIdx)
        ride.lastMoveAt = now()
        while true do
            Wait(1000)
            if ride.cancelled then return "abandoned" end
            local pos, v = vehiclePos(ride.vehicleId)
            if not pos then return "abandoned" end
            if dist2d(pos, dest) <= radius then return "arrived" end
            if v and v.moving and (v.speed or 0) > 0.5 then
                ride.lastMoveAt = now()
                if ride.boardedAt and not ride.firstMoveAt then
                    ride.firstMoveAt = now()
                    log("ride player=%d first movement %.0f s after boarding (%.1f m/s)", ride.playerId, ride.firstMoveAt - ride.boardedAt, v.speed or 0)
                end
            end
            local status, stt = aiStatus(ride.vehicleId)
            local still = now() - (ride.lastMoveAt or now())
            if still > 6 and not ride.dumpedState then
                ride.dumpedState = true
                log("ride player=%d %s: standing %.0f s, ai.state = %s", ride.playerId, why, still, flat(stt))
            end
            if status == "arrived" and dist2d(pos, dest) > radius * 3 then
                log("ride player=%d %s: ai says arrived %.0f m short; finishing direct", ride.playerId, why, dist2d(pos, dest))
                return "gave_up"
            end
            if aiFailed(status) or still > STALL_S then
                log("ride player=%d %s: %s at %.1f,%.1f (ai %s%s)", ride.playerId, why, aiFailed(status) and "ai failed" or ("stalled " .. math.floor(still) .. " s"), pos.x, pos.y,
                    tostring(status), (stt and stt.reason) and (" · " .. tostring(stt.reason)) or "")
                pcall(Open77.vehicles.ai.stop, ride.vehicleId)
                ride.failures = (ride.failures or 0) + 1
                if reissues >= 2 then return "gave_up" end
                reissues = reissues + 1
                -- resume from the nearest point that still lies ahead
                local best, bestD = startIdx, math.huge
                for i = startIdx, #route do
                    local d = dist2d(pos, route[i])
                    if d < bestD then best, bestD = i, d end
                end
                startIdx = math.min(best + 1, #route)
                Wait(500)
                if bestD > 25 then findRoad(ride, why) end
                break
            end
        end
    end
end

--- Start a ride for one player outside the event flow (authoring playback, dev). opts: spawnAt {x,y,z,heading}?,
--- pullUpTo {x,y,z}?, route {points}?, dropoff {x,y,z}, speed?, venueName, teamName/teamShort/colour?, replace?
--- Host kit (Batch 2): cancel every ride and remove its transport.
function NcmPickup.clearAll(reason)
    local n = 0
    for pid, ride in pairs(rides) do
        ride.cancelled = true
        pcall(removeTransport, ride, reason or "world_reset")
        rides[pid] = nil
        n = n + 1
    end
    log("rides cleared: %d (%s)", n, tostring(reason))
    return n
end

function NcmPickup.request(pid, opts)
    TriggerEvent("ncm:pickup", opts.eventId or "dev", {
        dropoff = opts.dropoff, speed = opts.speed or 18, venueName = opts.venueName or "the venue", replace = opts.replace,
        riders = { { playerId = pid, driverId = opts.driverId or "dev", teamId = opts.teamId, teamName = opts.teamName or "NCM", teamShort = opts.teamShort or "NCM",
                     colour = opts.colour, number = opts.number or 0, seatIndex = opts.seatIndex or 0,
                     spawnAt = opts.spawnAt, pullUpTo = opts.pullUpTo, route = opts.route } },
    })
end

local function runRide(ride)
    local pid = ride.playerId
    local p = Open77.players.get(pid)
    if not p or not p.position then log("ride player=%d: no position", pid); rides[pid] = nil; return end
    if dist2d(p.position, ride.dropoff) <= AT_VENUE_M then
        tell(pid, ("You're already at %s — your #%s %s RB15 will be in grid slot %d."):format(ride.venueName, tostring(ride.number or "?"), ride.teamName, ride.seatIndex or 0))
        rides[pid] = nil
        return
    end
    -- Spawn at the kerb beside the passenger (the pose /ncm car has used reliably: 6 m ahead, 3 m right, same
    -- heading) — a spawn further out lands in barriers and, past streaming range, never moves (KB-10). A known
    -- road node is used only when it is practically next to the player.
    local yaw = tonumber(p.heading or p.yaw or 0) or 0
    local node, nodeD = nearestRoadNode(p.position, ROAD_NODE_MIN_M, ROAD_NODE_MAX_M)
    local spawn, spawnYaw, how
    if ride.spawnAt then
        -- authored chauffeur node (P35): born out of sight on a road, pulls up to the spot
        spawn, spawnYaw, how = { x = ride.spawnAt.x, y = ride.spawnAt.y, z = (ride.spawnAt.z or p.position.z) + 0.5 }, tonumber(ride.spawnAt.heading) or 0, "authored node"
        node = nil
    elseif node then
        spawn, spawnYaw, how = { x = node.x, y = node.y, z = (node.z or p.position.z) + 0.5 }, tonumber(node.heading) or 0, ("road node %s (%.0f m)"):format(node.name, nodeD)
    else
        local rad = math.rad(yaw)
        local fx, fy, rx, ry = -math.sin(rad), math.cos(rad), math.cos(rad), math.sin(rad)
        spawn, spawnYaw, how = { x = p.position.x + fx * 6 + rx * 3, y = p.position.y + fy * 6 + ry * 3, z = p.position.z + 0.5 }, yaw, "kerb beside the player"
    end
    ride.spawnHow = how
    local vid, reason
    for _, rec in ipairs(Provisioning.spawnCandidates(TRANSPORT_RECORD)) do
        vid, reason = Open77.vehicles.create({ record = rec, position = spawn, yaw = spawnYaw, bucket = p.bucket or 0 })
        if vid then ride.record = rec; break end
    end
    if not vid then
        log("ride player=%d: transport create refused: %s", pid, tostring(reason))
        tell(pid, ("No ride available — make your own way to %s."):format(ride.venueName))
        rides[pid] = nil
        return
    end
    ride.vehicleId = vid
    ride.startedAt = now()
    local okAi, aiErr = pcall(Open77.vehicles.ai.attachDriver, vid, { behavior = "aggressive" })   -- normal pulls away like traffic: slow
    log("ride player=%d transport=%s %s at %.1f,%.1f via %s ai=%s", pid, tostring(vid), ride.record, spawn.x, spawn.y, how, tostring(okAi))
    if dist2d(spawn, ride.pullUpTo or p.position) > PULLUP_M then
        tell(pid, ("Your ride from %s is pulling up — get in when it stops, any seat. They'll take you to %s."):format(ride.teamName, ride.venueName))
    else
        tell(pid, ("Your ride from %s is here — get in, any seat. They'll take you to %s."):format(ride.teamName, ride.venueName))
    end
    toast(pid, { type = "info", title = string.upper(ride.teamName) .. " · YOUR RIDE", message = "Get in — heading to " .. ride.venueName, icon = ride.teamShort or "NCM", color = ride.colour, durationMs = 12000 })

    -- 1. pull up, only when the car was born more than a few metres away
    local pullTo = ride.pullUpTo or p.position
    if dist2d(spawn, pullTo) > PULLUP_M then
        local pull = driveUntil(ride, pullTo, PULLUP_M, 10, "pull-up")
        pcall(Open77.vehicles.ai.stop, vid)
        if pull == "abandoned" then removeTransport(ride, "vehicle_lost"); return end
        log("ride player=%d pulled up: %s after %.0f s", pid, pull, now() - ride.startedAt)
    end

    -- 2. wait for the passenger
    local waitFrom = now()
    while seatedIn(pid) ~= vid do
        Wait(1000)
        if ride.cancelled then removeTransport(ride, "cancelled"); return end
        if now() - waitFrom > BOARD_TIMEOUT_S then
            tell(pid, ("Your ride left without you. Make your own way to %s."):format(ride.venueName))
            removeTransport(ride, "not_boarded"); return
        end
    end
    ride.boardedAt = now()
    local km = dist2d(p.position, ride.dropoff) / 1000
    tell(pid, ("En route to %s — %.1f km. Sit back; your #%s car is waiting on the grid."):format(ride.venueName, km, tostring(ride.number or "?")))
    log("ride player=%d boarded after %.0f s, %.2f km to go", pid, ride.boardedAt - ride.startedAt, km)

    -- 3. the drive: an authored route (P36) when the ride has one, else the direct navigator
    local result
    if ride.route and #ride.route >= 2 then
        result = followUntil(ride, ride.route, ride.dropoff, ARRIVE_M, ride.speed, "route")
        if result == "gave_up" then
            log("ride player=%d route: falling back to the direct navigator", pid)
            result = driveUntil(ride, ride.dropoff, ARRIVE_M, ride.speed, "drive")
        end
    else
        result = driveUntil(ride, ride.dropoff, ARRIVE_M, ride.speed, "drive")
    end
    if result == "abandoned" then removeTransport(ride, "vehicle_lost"); return end
    if result == "gave_up" then handOver(ride, "drive"); return end
    pcall(Open77.vehicles.ai.stop, vid)
    ride.arrivedAt = now()
    log("ride player=%d ARRIVED after %.0f s (%.0f s riding), failures %d", pid, ride.arrivedAt - ride.startedAt, ride.arrivedAt - ride.boardedAt, ride.failures or 0)
    tell(pid, ("You've arrived at %s. Your #%s %s RB15 is in grid slot %d — it's on the grid from one minute before the start."):format(
        ride.venueName, tostring(ride.number or "?"), ride.teamName, ride.seatIndex or 0))
    toast(pid, { type = "success", title = "ARRIVED · " .. string.upper(ride.venueName), message = ("#%s · grid slot %d"):format(tostring(ride.number or "?"), ride.seatIndex or 0), icon = ride.teamShort or "NCM", color = ride.colour, durationMs = 10000 })

    -- 4. linger until the passenger is out, then leave
    local leftAt
    while true do
        Wait(1000)
        if ride.cancelled then break end
        if seatedIn(pid) ~= vid then leftAt = leftAt or now() else leftAt = nil end
        if leftAt and now() - leftAt > AFTER_EXIT_S then break end
        if now() - ride.arrivedAt > 600 then break end
    end
    removeTransport(ride, "done")
end

--- ncm_league: rides for an event. payload = { dropoff, speed, venueName, routeName, startsAt, riders = { {playerId, ...} } }
AddEventHandler("ncm:pickup", function(eventId, payload)
    if type(payload) ~= "table" or type(payload.riders) ~= "table" then return end
    byEvent[eventId] = byEvent[eventId] or {}
    for _, r in ipairs(payload.riders) do
        local pid = tonumber(r.playerId) or 0
        if pid > 0 and rides[pid] and (payload.replace or rides[pid].eventId == "dev") then
            rides[pid].cancelled = true
            removeTransport(rides[pid], "replaced")
        end
        if pid > 0 and not rides[pid] then
            local ride = {
                eventId = eventId, playerId = pid, driverId = r.driverId, teamId = r.teamId, teamName = r.teamName or "NCX", teamShort = r.teamShort,
                colour = r.colour, number = r.number, seatIndex = r.seatIndex, venueName = payload.venueName or r.venueName or "the venue",
                dropoff = payload.dropoff, speed = tonumber(payload.speed) or 18, failures = 0, startedAt = now(),
                spawnAt = r.spawnAt, pullUpTo = r.pullUpTo, route = r.route,
            }
            -- TW1 mode (venue authoring): the driver's spot has a node, a route and the paddock as the drop-off
            if NcmVenue and NcmVenue.tw1() and not ride.route and r.driverId then
                local spotKey = NcmVenue.spotOf[r.driverId]
                local ap = spotKey and NcmVenue.approach(spotKey)
                if ap then
                    ride.spawnAt, ride.pullUpTo, ride.route, ride.dropoff = ap.node, ap.spot, ap.route, ap.paddock
                    ride.venueName = payload.venueName or ride.venueName
                    log("ride player=%d: TW1 approach from spot %s (%s route)", pid, spotKey, ap.route and (#ap.route .. " pts") or "no")
                end
            end
            rides[pid] = ride
            byEvent[eventId][pid] = true
            CreateThread(function()
                local ok, err = pcall(runRide, ride)
                if not ok then log("ride player=%d crashed: %s", pid, tostring(err)); removeTransport(ride, "error") end
            end)
        end
    end
end)

AddEventHandler("ncm:pickupRelease", function(eventId)
    for pid in pairs(byEvent[eventId] or {}) do
        local ride = rides[pid]
        if ride then ride.cancelled = true end
    end
    byEvent[eventId] = nil
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    local ride = rides[tonumber(playerId) or 0]
    if ride then ride.cancelled = true; removeTransport(ride, "disconnected") end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_world" then return end
    for _, ride in pairs(rides) do ride.cancelled = true; removeTransport(ride, "resource_stopped") end
end)

--- Dispatch a dev ride (no event) for one player to a point.
local function devRide(pid, target, venue)
    log("dev ride player=%d -> %s at %.1f,%.1f", pid, venue, target.x, target.y)
    TriggerEvent("ncm:pickup", "dev", { dropoff = target, speed = 18, venueName = venue, replace = true, riders = {
        { playerId = pid, driverId = "dev", teamName = "NCM", teamShort = "NCM", number = 0, seatIndex = 0 } } })
end

-- Warden: ncm.pickup <pid> <x> <y> [z]  — a ride for one player to explicit coordinates.
RegisterCommand("ncm.pickup", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    local x, y = tonumber(args and args[2]), tonumber(args and args[3])
    if not (pid and x and y) then log("usage: ncm.pickup <playerId> <x> <y> [z]  (players: /ncm.ride to your map waypoint)"); return end
    local p = Open77.players.get(pid)
    devRide(pid, { x = x, y = y, z = tonumber(args[4]) or (p and p.position and p.position.z) or 0 }, ("%.0f,%.0f"):format(x, y))
end, false)

-- Player: /ncm.ride — the client reads its map waypoint and asks for a ride there (client/main.lua).
RegisterNetEvent("ncm:ride", function(x, y, z)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then tell(pid, "Set a waypoint on the map first, then /ncm.ride."); return end
    devRide(pid, { x = x, y = y, z = tonumber(z) or 0 }, "your waypoint")
end)
