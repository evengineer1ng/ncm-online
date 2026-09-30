-- ncm_paddock / server / live -- Paddock races on the street, on schedule (doc 44 §12, phase 5, L222, L228).
--
-- Nobody declares a live race (owner, 2026-09-29: "it should just happen on schedule as intended"). Every scheduled
-- race is considered at its staging time; `liveMode` decides which run physically:
--   watched  (default) a race goes live when a player is near its route -- anywhere along it, not only the start
--   always   every race goes live whenever anyone is online (set this once the probe shows cars move with nobody near)
--   off      simulation only
--
--   stage    (liveStageLeadSec out)  the grid spawns at the start, pole first, with room between rows
--   go       (window opens + count)  a ROLLING start: rows are released one after another, never twelve cars at once
--   run      (every liveSampleMs)    the SERVER times every gate from canonical positions, and keeps the field racing:
--              no progress for liveRecoverSec  -> the car is sent on again from where it is on the line
--              no progress for liveResetSec    -> it is put back on the road just behind where it stopped, and sent on
--              no progress for liveRetireSec   -> only then is it out
--   finish   once the winner is home, everyone still running gets liveFinishGraceSec (or half the winner's time) to
--            finish; the hard deadline is liveTimeoutFactor x the sim winner's time
--   verdict  `paddock.live.classify`: physical -> the result replaces the sealed sim result before the close;
--            fallback -> the sim result stands and the reason is kept
--
-- The race's close waits for the verdict (`PaddockLive.holds`), and Billie settles at the close, so a physical result
-- settles slips exactly once. The sim still runs at the window's opening: a street run can fail at any step and the
-- Paddock keeps its result.
PaddockLive = { byRace = {}, paceClients = {}, probe = nil }

local U = PaddockUtil
local log = U.logger("live")
local L = NcmCore.get("paddock.live")
local Sim = NcmCore.get("paddock.sim")
local Season = NcmCore.get("paddock.season")
local Finance = NcmCore.get("paddock.finance")
local Hash = NcmCore.get("vocabulary.hash")
local Pose = NcmCore.get("replay.pose")
local Json = NcmCore.get("vocabulary.json")
local Pool = NcmCore.get("data.vehicle_pool")
local Clock = NcmCore.get("world.clock")

local byRace = PaddockLive.byRace
local byVehicle = {}                 -- vehicleId -> { raceId, personId }
local NO_DRIVER = "00000000-0000-0000-0000-000000000000"

local function nowMs() return math.floor((Open77.time.unix() or 0) * 1000) end
local function set(k, d) return PaddockSettings.get(k, d) end
local function notify(pid, msg, ms)
    if pid then pcall(Open77.notifications.send, pid, { type = "info", title = "PADDOCK LIVE", message = msg, icon = "NCM", durationMs = ms or 6000 }) end
end
local function positions()
    local ok, p = pcall(Open77.players.positions)
    return (ok and type(p) == "table") and p or {}
end

--- Is a race's close held for a live verdict?
function PaddockLive.holds(raceId)
    local lr = byRace[raceId]
    return lr ~= nil and (lr.state == "staging" or lr.state == "running")
end

--- People physically in a live race right now (garages.lua keeps them off the garage floor).
function PaddockLive.awayPeople()
    local out = {}
    for _, lr in pairs(byRace) do
        if lr.state == "staging" or lr.state == "running" then
            for _, c in ipairs(lr.cars or {}) do out[c.personId] = true end
        end
    end
    return out
end

--- What the RESULTS view shows beside a race.
function PaddockLive.statusOf(raceId)
    local lr = byRace[raceId]
    if not lr then return nil end
    return { state = lr.state, backend = lr.backend, verdict = lr.verdict }
end

local function setRow(lr, fields)
    local sets, vals = {}, {}
    for k, v in pairs(fields) do sets[#sets + 1] = k .. " = ?"; vals[#vals + 1] = v end
    vals[#vals + 1] = U.sid(); vals[#vals + 1] = lr.raceId
    pcall(MySQL.update.await, "UPDATE paddock_live SET " .. table.concat(sets, ", ") .. " WHERE server_id = ? AND race_id = ?", vals)
end

-- ------------------------------------------------------------------------------------------------------ the line

local pathCache = {}                 -- routeId -> { path, at }

local function bestGhost(routeId)
    local okQ, row = pcall(MySQL.single.await, [[SELECT poses_json, format FROM ghost_lap WHERE server_id = ? AND route_id = ?
        ORDER BY elapsed_ms LIMIT 1]], { U.sid(), routeId })
    if not okQ or not row or type(row.poses_json) ~= "string" then return nil end
    local okJ, raw = pcall(Json.decode, row.poses_json)
    if not okJ then return nil end
    return Pose.decode(raw, tonumber(row.format))
end

--- The road line for a route (a human ghost when one exists), cached for ten minutes.
function PaddockLive.pathFor(routeId)
    local c = pathCache[routeId]
    if c and U.now() - c.at < 600 then return c.path end
    local route = PaddockWorld.route(routeId)
    if not route then return nil end
    local path = L.path(route, bestGhost(routeId))
    pathCache[routeId] = { path = path, at = U.now() }
    return path
end

--- Players near a route: within liveWatchRadiusM of its line or its start. Returns a list of { pid, d, pos }.
local function watchers(routeId)
    local path = PaddockLive.pathFor(routeId)
    local route = PaddockWorld.route(routeId)
    if not path or not route then return {} end
    local radius = set("liveWatchRadiusM", 600)
    local out = {}
    for pid, pos in pairs(positions()) do
        local d = math.min(L.distToPath(path.points, pos), L.dist(route.start, pos))
        if d <= radius then out[#out + 1] = { pid = tonumber(pid), d = d, pos = pos } end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

-- -------------------------------------------------------------------------------------------------------- stage

local function recordFor(org, tier)
    local band = (Season.TIERS[tier] or {}).band or {}
    local list = {}
    for _, class in ipairs(band.classes or { "Sport" }) do
        for _, r in ipairs(Pool.records(class, band.prestigeMax)) do
            if (tonumber(r.prestige) or 1) >= (band.prestigeMin or 0) then list[#list + 1] = r.id end
        end
    end
    if #list == 0 then list = { "Vehicle.v_sport2_quadra_type66" } end
    return Hash.pick(list, "livecar", org and org.id or "none")
end

local DRIVER_RECORDS = { m = { "Character.WorkerMale", "Character.YoungsterMale", "Character.AsianMale" },
    f = { "Character.YoungsterFemale", "Character.AsianFemale" } }

local function removeCars(lr)
    for _, c in ipairs(lr.cars or {}) do
        if c.vehicleId then
            byVehicle[c.vehicleId] = nil
            pcall(Open77.vehicles.ai.removeDriver, c.vehicleId)
            pcall(Open77.vehicles.remove, c.vehicleId)
        end
        if c.npcId then pcall(Open77.npcs.remove, c.npcId) end
    end
end

local function cancel(lr, reason)
    lr.state, lr.reason = "cancelled", reason
    setRow(lr, { state = "cancelled", reason = reason, ended_at = U.now() })
    removeCars(lr)
    for _, w in ipairs(lr.watchers or {}) do TriggerClientEvent("ncm:paddock.live.end", w, { raceId = lr.raceId }) end
    log("cancelled %s: %s", lr.raceId, tostring(reason))
end

local function stage(race, host, t)
    local w = PaddockStore.world
    local route = PaddockWorld.route(race.routeId)
    local path = PaddockLive.pathFor(race.routeId)
    if not route or not path then return end
    PaddockRaces.freeze(race)
    local field = PaddockRaces.buildField(race)
    if #field < 2 then return end
    if #field > set("liveMaxCars", 16) then log("%s not live: %d cars is over liveMaxCars", race.raceId, #field) return end
    local d = host and PaddockPlayers.driver(host.pid)
    local lr = { raceId = race.raceId, state = "staging", pid = host and host.pid, route = route, cars = {}, bucket = host and host.pos.bucket or 0,
        watchers = {} }
    byRace[race.raceId] = lr
    pcall(MySQL.update.await, [[INSERT INTO paddock_live (server_id, race_id, declared_by, declared_at, state, cars)
        VALUES (?, ?, ?, ?, 'staging', ?) ON DUPLICATE KEY UPDATE state = 'staging', declared_at = VALUES(declared_at)]],
        { U.sid(), race.raceId, d and d.ncmDriverId or NO_DRIVER, t, #field })
    local segments = Sim.segments(route.distanceM, route.laps)
    local gates = L.checkpoints(route, path, segments)
    local slots = L.gridSlots(gates[1], #field)
    local want = set("liveBackend", "auto")
    local pace = host and PaddockLive.paceClients[host.pid]
    local backend = (want == "pace" or (want == "auto" and pace and pace.ok)) and "pace" or "platform"
    if want == "pace" and not (pace and pace.ok) then return cancel(lr, "liveBackend is pace but the nearest player has no Pace plugin") end
    lr.backend, lr.path, lr.gates, lr.segments, lr.field = backend, path, gates, segments, field
    local npcDrivers = backend == "platform" and set("liveNpcDrivers", true)
    for i, e in ipairs(field) do
        local s = slots[i]
        local org = w.orgs[e.orgId or ""]
        local okV, vid, reason = pcall(Open77.vehicles.create, { record = recordFor(org, race.tier),
            position = { x = s.x, y = s.y, z = (s.z or 0) + 0.6 }, yaw = s.yaw, bucket = lr.bucket })
        if not okV or not vid then
            log("stage %s: car %d (%s) refused: %s", race.raceId, i, e.id, tostring(reason or vid))
            return cancel(lr, "the grid could not be built")
        end
        local car = { personId = e.id, orgId = e.orgId, vehicleId = vid, slot = i, row = s.row, recoveries = 0, resets = 0 }
        lr.cars[#lr.cars + 1] = car
        byVehicle[vid] = { raceId = race.raceId, personId = e.id }
        if backend == "platform" then
            local npcId
            if npcDrivers then
                local p = w.people[e.id]
                local okN, id = pcall(Open77.npcs.create, { record = Hash.pick(DRIVER_RECORDS[(p and p.gender == "f") and "f" or "m"], "driver", e.id),
                    position = { x = s.x, y = s.y, z = (s.z or 0) + 0.6 }, yaw = s.yaw, bucket = lr.bucket,
                    aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or nil,
                    damagePolicy = Open77.npcs.damage and Open77.npcs.damage.invulnerable or nil,
                    despawnWhenUnobserved = false, persistent = false })
                if okN and id then npcId = id; car.npcId = id end
            end
            local okA, st, why = pcall(Open77.vehicles.ai.attachDriver, vid, npcId and { npcId = npcId } or nil)
            if (not okA or not st) and npcId then
                pcall(Open77.npcs.remove, npcId); car.npcId = nil
                okA, st, why = pcall(Open77.vehicles.ai.attachDriver, vid, nil)
            end
            if not okA or not st then
                log("stage %s: attachDriver %d refused: %s", race.raceId, vid, tostring(why or st))
                return cancel(lr, "the AI would not take the wheel")
            end
            -- No requestAuthority here: the platform refuses it for an AI-driven car by name (`ai_driven`, probe v1, L229).
            -- A client picks an AI car up by itself only within a few hundred metres; the physical bubble works with that.
        elseif host then
            local okR, st, why = pcall(Open77.vehicles.requestAuthority, vid, host.pid)
            if not okR or not st then log("stage %s: requestAuthority %d -> %d: %s", race.raceId, vid, host.pid, tostring(why or st)) end
        end
        Wait(0)
    end
    setRow(lr, { state = "staging", backend = backend, path_source = path.source })
    local names = {}
    for i, c in ipairs(lr.cars) do
        names[i] = { vehicleId = c.vehicleId, personId = c.personId, name = PaddockWorld.personName(c.personId), org = PaddockWorld.orgName(c.orgId), slot = c.slot }
    end
    local msg = ("%s on %s: the grid is out at %s. Lights at %s ET."):format(PaddockWorld.seriesName(race.seriesId),
        PaddockWorld.routeName(race.routeId), route.start.name or "the start", Clock.hhmm(race.opensAt))
    for _, wch in ipairs(watchers(race.routeId)) do
        lr.watchers[#lr.watchers + 1] = wch.pid
        notify(wch.pid, msg, 9000)
        TriggerClientEvent("ncm:paddock.live.stage", wch.pid, { raceId = race.raceId, backend = backend, cars = names, opensAt = race.opensAt,
            series = PaddockWorld.seriesName(race.seriesId), route = PaddockWorld.routeName(race.routeId),
            start = { x = route.start.x, y = route.start.y, z = route.start.z } })
    end
    log("staged %s: %d cars, backend=%s, path=%s (%d pts, %.0f m), %d gates, %d watcher(s)", race.raceId, #lr.cars, backend,
        path.source, #path.points, path.lengthM or 0, #gates, #lr.watchers)
end

-- ----------------------------------------------------------------------------------------------------- driving

local function splitsOf(race, personId)
    local r = race.result
    if not r then return nil end
    for _, e in ipairs(r.entrants or {}) do if e.id == personId then return e.splits end end
    return nil
end

--- Send a car along the line from path point `from` (>= 2) on the platform backend. The route's point k is path point
--- (from - 1 + k); `c.base` remembers the offset so per-leg ceilings stay aligned after a re-issue.
local function drive(lr, c, from)
    local pts = lr.path.points
    from = math.max(2, math.min(#pts, from or 2))
    local route = {}
    for i = from, #pts do route[#route + 1] = pts[i] end
    -- carry on past the finish so the line is crossed, not parked on
    local a, b = pts[#pts - 1], pts[#pts]
    local len = math.max(1, L.dist(a, b))
    route[#route + 1] = { x = b.x + (b.x - a.x) / len * 80, y = b.y + (b.y - a.y) / len * 80, z = b.z or 0 }
    while #route > 64 do table.remove(route, 1) end
    c.base = #pts + 1 - #route
    local okF, st, why = pcall(Open77.vehicles.ai.followRoute, c.vehicleId, { points = route,
        speed = c.plan[math.max(1, c.base)] or c.plan[#c.plan] or 20, behavior = "aggressive", arrivalRadius = 12,
        timeoutMilliseconds = math.min(3600000, lr.deadlineMs + 120000) })
    if not okF or not st then log("%s: followRoute for %s refused: %s", lr.raceId, c.personId, tostring(why or st)) return false end
    return true
end

local function go(lr, race)
    local cap = lr.backend == "pace" and set("livePaceMaxMps", 90) or L.PLATFORM_MAX_MPS
    for _, c in ipairs(lr.cars) do
        c.plan = L.speedPlan(lr.path.points, lr.path.lengthM, splitsOf(race, c.personId), lr.segments, cap)
    end
    local leaderMs = race.result and race.result.entrants and race.result.entrants[1] and race.result.entrants[1].finishMs
    leaderMs = leaderMs or math.floor((lr.path.lengthM or 3000) / 30 * 1000)
    lr.simLeaderMs = leaderMs
    lr.goMs = nowMs() + set("liveCountdownSec", 5) * 1000
    lr.deadlineMs = math.floor(leaderMs * set("liveTimeoutFactor", 4)) + 120000
    local ids = {}
    for i, c in ipairs(lr.cars) do ids[i] = c.personId end
    lr.timing = L.newTiming(lr.gates, ids)
    lr.out, lr.client = {}, {}
    lr.state = "running"
    setRow(lr, { state = "running", go_at = lr.goMs / 1000 })
    for _, pid in ipairs(lr.watchers) do
        notify(pid, ("Lights out in %d seconds."):format(set("liveCountdownSec", 5)), 4000)
        TriggerClientEvent("ncm:paddock.live.countdown", pid, { raceId = lr.raceId, goInMs = lr.goMs - nowMs() })
    end
    if lr.backend == "pace" and lr.pid then
        local cars = {}
        for i, c in ipairs(lr.cars) do cars[i] = { vehicleId = c.vehicleId, personId = c.personId, speeds = c.plan } end
        local gates = {}
        for i, g in ipairs(lr.gates) do gates[i] = { x = g.x, y = g.y, z = g.z, dx = g.dir.x, dy = g.dir.y, halfWidth = g.halfWidthM, capture = g.captureM } end
        TriggerClientEvent("ncm:paddock.live.drive", lr.pid, { raceId = lr.raceId, goInMs = lr.goMs - nowMs(), points = lr.path.points,
            gates = gates, cars = cars })
    end
    log("go %s at +%d ms: %d cars, deadline %d s", lr.raceId, lr.goMs - nowMs(), #lr.cars, math.floor(lr.deadlineMs / 1000))
    CreateThread(function()
        while nowMs() < lr.goMs do Wait(50) end
        if lr.backend == "platform" then
            -- rolling start: one grid row at a time, so the field strings out instead of arriving at turn one together
            local gap = set("liveStartGapMs", 900)
            local row = 1
            while lr.state == "running" do
                local any = false
                for _, c in ipairs(lr.cars) do
                    if c.row == row then any = true; if not drive(lr, c, 2) then lr.out[c.personId] = "no_start" end end
                end
                if not any then break end
                row = row + 1
                Wait(gap)
            end
        end
    end)
    CreateThread(function() PaddockLive.sample(lr, race) end)
end

-- ----------------------------------------------------------------------------------------------------- recovery

--- Keep a stuck car racing. Returns nothing; may retire the car only after liveRetireSec with no progress.
local function persevere(lr, c, pos, tMs)
    local tc = lr.timing.cars[c.personId]
    local idle = tMs - (tc.progressMs or 0)
    if idle > set("liveRetireSec", 180) * 1000 then
        lr.out[c.personId] = "stalled"
        log("%s: %s retired after %d s without progress (%d re-sends, %d resets)", lr.raceId, c.personId, math.floor(idle / 1000), c.recoveries, c.resets)
        return
    end
    if lr.backend ~= "platform" then return end            -- the Pace plugin keeps its own cars moving
    -- two clocks: a re-send every liveRecoverSec while stuck, and a reset every liveResetSec -- a re-send must never
    -- postpone the reset, or a car that cannot drive out is re-sent forever and never put back on the road
    local resetSec = set("liveResetSec", 20) * 1000
    if idle > resetSec and tMs - (c.lastResetMs or -1e9) > resetSec then
        local rp = L.resetPoint(lr.path.points, pos)
        local okT = pcall(Open77.vehicles.setTransform, c.vehicleId, { position = { x = rp.x, y = rp.y, z = (rp.z or 0) + 1.0 }, yaw = rp.yaw })
        L.forget(lr.timing, c.personId, tMs)
        c.resets, c.lastResetMs, c.lastHelpMs = c.resets + 1, tMs, tMs
        if okT then drive(lr, c, rp.index + 1) end
        log("%s: %s put back on the road at point %d (reset %d)", lr.raceId, c.personId, rp.index, c.resets)
    elseif idle > set("liveRecoverSec", 8) * 1000 and tMs - (c.lastHelpMs or -1e9) > set("liveRecoverSec", 8) * 1000 then
        local i = L.nearestIndex(lr.path.points, pos)
        c.recoveries, c.lastHelpMs = c.recoveries + 1, tMs
        drive(lr, c, i + 1)
    end
end

-- ----------------------------------------------------------------------------------------------------- finish

local function writeBack(lr, race, c)
    local purse = Finance.purse(race.tier, #c.entrants)
    local st = { { query = "DELETE FROM paddock_result WHERE server_id = ? AND race_id = ?", values = { U.sid(), race.raceId } } }
    local splits = {}
    for _, e in ipairs(c.entrants) do
        e.points = Season.pointsFor(e.position, e.state)
        e.purse = (e.state == "finished") and (purse[e.position] or 0) or 0
        splits[e.id] = e.splits
        st[#st + 1] = { query = [[INSERT INTO paddock_result (server_id, race_id, person_id, org_id, series_id, season_id,
            cup_id, position, grid, state, finish_ms, gap_ms, points, purse, dnf_reason, at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, -1), ?, ?, NULLIF(?, ''), ?)]],
            values = { U.sid(), race.raceId, e.id, e.orgId or "", race.seriesId, race.seasonId, race.cupId, e.position,
                e.grid, e.state, e.finishMs or -1, e.gapMs or -1, e.points, e.purse, e.dnfReason or "", race.opensAt } }
    end
    local detail = { frozen = race.frozen, splits = splits, events = {}, segments = lr.segments, live = { backend = lr.backend,
        path = lr.path.source, gates = #lr.gates } }
    st[#st + 1] = { query = [[UPDATE paddock_race SET provenance = 'physical', backend = ?, detail_json = ?, window_closes_at = ?
        WHERE server_id = ? AND race_id = ?]], values = { lr.backend == "pace" and "pace" or "platformAI", U.encode(detail) or "{}",
        U.now() + 5, U.sid(), race.raceId } }
    local ok, err = U.transact(st)
    if not ok then return false, err end
    race.result = { entrants = c.entrants, events = {}, segments = lr.segments }
    race.provenance = "physical"
    race.closesAt = U.now() + 5
    return true
end

local function storeCrossings(lr)
    local st = {}
    for _, id in ipairs(lr.timing.order) do
        for g, ms in pairs(lr.timing.cars[id].times) do
            st[#st + 1] = { query = "INSERT IGNORE INTO paddock_live_crossing (server_id, race_id, person_id, gate, source, t_ms) VALUES (?, ?, ?, ?, 'server', ?)",
                values = { U.sid(), lr.raceId, id, g, ms } }
        end
        for g, ms in pairs(lr.client[id] or {}) do
            st[#st + 1] = { query = "INSERT IGNORE INTO paddock_live_crossing (server_id, race_id, person_id, gate, source, t_ms) VALUES (?, ?, ?, ?, 'pace', ?)",
                values = { U.sid(), lr.raceId, id, tonumber(g) or 0, math.floor(tonumber(ms) or 0) } }
        end
    end
    if #st > 0 then
        local ok, err = U.transact(st)
        if not ok then log("crossings for %s not stored: %s", lr.raceId, tostring(err)) end
    end
end

local function finish(lr, race)
    local fieldIds = {}
    for i, c in ipairs(lr.cars) do fieldIds[i] = { id = c.personId, orgId = c.orgId } end
    local clientOk
    if lr.backend == "pace" then clientOk = L.corroborate(lr.timing, lr.client) end
    local c = L.classify(lr.timing, fieldIds, lr.out, { clientOk = clientOk, minFinishShare = set("liveMinFinishShare", 0.5) })
    lr.verdict, lr.reason = c.verdict, c.reason
    if c.verdict == "physical" then
        local ok, err = writeBack(lr, race, c)
        if not ok then lr.verdict, lr.reason = "fallback", "write-back failed: " .. tostring(err) end
    end
    storeCrossings(lr)
    lr.state = "finished"
    local help = {}
    for _, car in ipairs(lr.cars) do help[car.personId] = { resends = car.recoveries, resets = car.resets } end
    setRow(lr, { state = "finished", verdict = lr.verdict, reason = lr.reason or "", ended_at = U.now(),
        detail_json = U.encode({ finishers = c.finishers, out = lr.out, help = help }) or "{}" })
    local winner = c.entrants[1] and c.entrants[1].state == "finished" and PaddockWorld.personName(c.entrants[1].id) or nil
    for _, pid in ipairs(lr.watchers) do
        notify(pid, lr.verdict == "physical"
            and ("Street result stands: %s wins. %d of %d finished."):format(tostring(winner), c.finishers, #lr.cars)
            or ("The street run didn't count (%s). The sim result stands."):format(tostring(lr.reason)), 9000)
        TriggerClientEvent("ncm:paddock.live.end", pid, { raceId = lr.raceId, verdict = lr.verdict })
    end
    log("finished %s: verdict=%s reason=%s finishers=%d/%d", lr.raceId, lr.verdict, tostring(lr.reason), c.finishers, #lr.cars)
    CreateThread(function()
        Wait(30000)
        removeCars(lr)
    end)
end

--- The server's own timing loop: every car's canonical position every `liveSampleMs`, keeping the field racing,
--- until every car is home or out, the finish window closes, or the hard deadline passes.
function PaddockLive.sample(lr, race)
    while lr.state == "running" do
        local tMs = nowMs() - lr.goMs
        if tMs >= 0 then
            for _, c in ipairs(lr.cars) do
                if not lr.out[c.personId] and not lr.timing.cars[c.personId].done then
                    local okP, pos = pcall(Open77.vehicles.getPosition, c.vehicleId)
                    if not okP or type(pos) ~= "table" then
                        lr.out[c.personId] = "lost"
                    else
                        L.observe(lr.timing, c.personId, pos, tMs)
                        persevere(lr, c, pos, tMs)
                    end
                end
            end
        end
        local leader = L.leaderMs(lr.timing)
        if leader and not lr.closeMs then
            lr.closeMs = leader + math.max(set("liveFinishGraceSec", 90) * 1000, math.floor(leader * 0.5))
            log("%s: the winner is home at %.1f s; the rest have until %.0f s", lr.raceId, leader / 1000, lr.closeMs / 1000)
        end
        if L.allDone(lr.timing, lr.out) or tMs > lr.deadlineMs or (lr.closeMs and tMs > lr.closeMs) then
            for _, c in ipairs(lr.cars) do
                if not lr.timing.cars[c.personId].done and not lr.out[c.personId] then
                    lr.out[c.personId] = lr.closeMs and "not_classified" or "timeout"
                end
            end
            finish(lr, race)
            return
        end
        Wait(set("liveSampleMs", 250))
    end
end

-- Per-leg ceilings on the platform backend: each waypoint reached sets the next leg's speed.
if Open77.vehicles and Open77.vehicles.ai and Open77.vehicles.ai.on then
    pcall(Open77.vehicles.ai.on, "waypointReached", function(state)
        local vid = tonumber(state and state.vehicleId)
        local ref = vid and byVehicle[vid]
        if not ref then return end
        local lr = byRace[ref.raceId]
        if not lr or lr.state ~= "running" then return end
        for _, c in ipairs(lr.cars) do
            if c.vehicleId == vid then
                -- the route's point k is path point (base - 1 + k); the card does not say whether routeIndex counts from 0
                -- or 1, so this picks the leg after the one just ended or the one after that -- one leg early is harmless
                local leg = (c.base or 2) + (tonumber(state.routeIndex) or 0)
                local v = c.plan and (c.plan[leg] or c.plan[#c.plan])
                if v then pcall(Open77.vehicles.ai.setSpeed, vid, v) end
                return
            end
        end
    end)
    -- a failed or cancelled task is re-sent at once from where the car is; waiting would only lose it places
    for _, ev in ipairs({ "failed", "cancelled" }) do
        pcall(Open77.vehicles.ai.on, ev, function(state)
            local vid = tonumber(state and state.vehicleId)
            local ref = vid and byVehicle[vid]
            local lr = ref and byRace[ref.raceId]
            if not lr or lr.state ~= "running" or lr.out[ref.personId] then return end
            for _, c in ipairs(lr.cars) do
                if c.vehicleId == vid and not lr.timing.cars[c.personId].done then
                    local okP, pos = pcall(Open77.vehicles.getPosition, vid)
                    if okP and type(pos) == "table" then c.recoveries = c.recoveries + 1; drive(lr, c, L.nearestIndex(lr.path.points, pos) + 1) end
                    return
                end
            end
        end)
    end
end

-- --------------------------------------------------------------------------------------------------------- tick

local function running()
    local n = 0
    for _, lr in pairs(byRace) do if PaddockLive.holds(lr.raceId) then n = n + 1 end end
    return n
end

--- One pass from the main scheduler: stage the next race that is due, start what is staged. Bounded.
function PaddockLive.tick(t)
    local mode = set("liveMode", "watched")
    for _, lr in pairs(byRace) do
        local race = PaddockRaces.byId[lr.raceId]
        if not race or race.state == "void" then
            if PaddockLive.holds(lr.raceId) then cancel(lr, "the race was voided") end
        elseif lr.state == "staging" and t >= race.opensAt and race.state == "running" then
            local ok, err = pcall(go, lr, race)
            if not ok then log("go %s FAILED: %s", lr.raceId, tostring(err)); cancel(lr, "the start failed") end
            return
        end
    end
    if mode ~= "off" and running() < set("liveMaxConcurrent", 2) then
        local lead = set("liveStageLeadSec", 75)
        local due
        for _, race in pairs(PaddockRaces.byId) do
            if not byRace[race.raceId] and (race.state == "scheduled" or race.state == "priced")
                and t >= race.opensAt - lead and t < race.opensAt and (not due or race.opensAt < due.opensAt) then due = race end
        end
        if due then
            byRace[due.raceId] = { raceId = due.raceId, state = "considered" }
            local host
            if mode == "always" then
                local list = watchers(due.routeId)
                host = list[1]
                if not host then
                    for pid, pos in pairs(positions()) do host = { pid = tonumber(pid), pos = pos, d = math.huge } break end
                end
                if not host then byRace[due.raceId] = { raceId = due.raceId, state = "skipped", reason = "nobody online" } return end
            else
                host = watchers(due.routeId)[1]
                if not host then byRace[due.raceId] = { raceId = due.raceId, state = "skipped", reason = "nobody near the route" } return end
            end
            local ok, err = pcall(stage, due, host, t)
            if not ok then
                log("stage %s FAILED: %s", due.raceId, tostring(err))
                local lr = byRace[due.raceId]
                if lr and lr.state ~= "cancelled" and lr.cars then cancel(lr, "staging failed") end
            end
        end
    end
    for id, lr in pairs(byRace) do
        local race = PaddockRaces.byId[id]
        if (lr.state ~= "staging" and lr.state ~= "running") and (not race or race.opensAt < t - 6 * 3600) then byRace[id] = nil end
    end
end

--- Boot: a live race cannot survive a restart (its cars went with the old process). Say so in the ledger.
function PaddockLive.boot()
    pcall(MySQL.update.await, [[UPDATE paddock_live SET state = 'cancelled', reason = 'server restarted', ended_at = ?
        WHERE server_id = ? AND state IN ('declared','staging','running')]], { U.now(), U.sid() })
end

-- The AI-motion probe is its own file now (server/probe.lua): a distance ladder with three legs per car.

-- --------------------------------------------------------------------------------------------------------- events

-- The client says whether the Pace plugin answered on loopback (client/live.lua).
RegisterNetEvent("ncm:paddock.live.pace", function(info)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(info) ~= "table" then return end
    PaddockLive.paceClients[pid] = { ok = info.ok == true, version = tostring(info.version or "") }
end)

-- Gate reports from the Pace DLL, relayed by the host's client. Evidence, not authority: they count only when the
-- server's own times agree (paddock.live.corroborate).
RegisterNetEvent("ncm:paddock.live.gate", function(msg)
    local pid = tonumber(source) or 0
    if type(msg) ~= "table" then return end
    local lr = byRace[tostring(msg.raceId or "")]
    if not lr or lr.pid ~= pid or lr.state ~= "running" then return end
    local ref = byVehicle[tonumber(msg.vehicleId) or -1]
    if not ref or ref.raceId ~= lr.raceId then return end
    local g, ms = tonumber(msg.gate), tonumber(msg.tMs)
    if not g or not ms or g < 2 or g > #lr.gates then return end
    lr.client[ref.personId] = lr.client[ref.personId] or {}
    lr.client[ref.personId][g] = math.floor(ms)
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    PaddockLive.paceClients[tonumber(playerId) or 0] = nil
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    for _, lr in pairs(byRace) do removeCars(lr) end
end)
