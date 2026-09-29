-- ncm_paddock / server / live -- declared physical-authoritative Paddock races (doc 44 §12, phase 5, L222).
--
--   declare  (F6 RESULTS, NEXT UP)   a player asks for an upcoming race to run on the street; the field freezes
--   stage    (liveStageLeadSec out)  the declarer must be at the start: the grid is spawned there, pole first
--   go       (window opens + count)  every car drives the route at a ceiling taken from ITS OWN sim splits:
--              platform  Open77.vehicles.ai.followRoute over a human ghost's line, capped at 55 m/s by the platform
--              pace      the Pace DLL (ncm/pace) on the declarer's client, uncapped, with 20 Hz gate reports
--   run      (every liveSampleMs)    the SERVER times every gate from canonical positions, whatever the backend
--   verdict  (all done or timeout)   `paddock.live.classify`: physical -> the result replaces the sealed sim result
--                                    before the close; fallback -> the sim result stands and the reason is kept
--
-- The race's close waits for the verdict (`PaddockLive.holds`), and Billie settles at the close, so a physical
-- result settles slips exactly once and nothing is ever re-settled. The sim ran at the window's opening as always:
-- a live race can fail at any step and the Paddock still has its result.
PaddockLive = { byRace = {}, paceClients = {} }

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

local byRace = PaddockLive.byRace
local byVehicle = {}                 -- vehicleId -> { raceId, personId }

local function nowMs() return math.floor((Open77.time.unix() or 0) * 1000) end
local function notify(pid, msg, ms)
    if pid then pcall(Open77.notifications.send, pid, { type = "info", title = "PADDOCK LIVE", message = msg, icon = "NCM", durationMs = ms or 6000 }) end
end

--- Is a race's close held for a live verdict?
function PaddockLive.holds(raceId)
    local lr = byRace[raceId]
    return lr ~= nil and (lr.state == "declared" or lr.state == "staging" or lr.state == "running")
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
    return { state = lr.state, backend = lr.backend, declaredBy = lr.declaredByName, verdict = lr.verdict }
end

local function setRow(lr, fields)
    local sets, vals = {}, {}
    for k, v in pairs(fields) do sets[#sets + 1] = k .. " = ?"; vals[#vals + 1] = v end
    vals[#vals + 1] = U.sid(); vals[#vals + 1] = lr.raceId
    pcall(MySQL.update.await, "UPDATE paddock_live SET " .. table.concat(sets, ", ") .. " WHERE server_id = ? AND race_id = ?", vals)
end

-- ------------------------------------------------------------------------------------------------------ declare

local function activeCount()
    local n = 0
    for _, lr in pairs(byRace) do if PaddockLive.holds(lr.raceId) then n = n + 1 end end
    return n
end

--- Whether a race could be declared live right now, and why not. Used by the view (the button) and declare.
function PaddockLive.eligible(race, t)
    if not PaddockSettings.get("liveEnabled", true) then return false, "disabled" end
    if not race or (race.state ~= "scheduled" and race.state ~= "priced") then return false, "not_open" end
    if byRace[race.raceId] then return false, "already_live" end
    local lead = race.opensAt - t
    if lead < PaddockSettings.get("liveDeclareLeadSec", 150) then return false, "too_late" end
    if lead > PaddockSettings.get("liveDeclareHorizonMin", 90) * 60 then return false, "too_early" end
    if activeCount() > 0 then return false, "one_at_a_time" end
    return true
end

function PaddockLive.declare(pid, raceId)
    local t = U.now()
    local race = PaddockRaces.byId[raceId or ""]
    local ok, why = PaddockLive.eligible(race, t)
    if not ok then return false, why end
    local d = PaddockPlayers.driver(pid)
    if not d then return false, "no_driver" end
    PaddockRaces.freeze(race)
    local n = #(race.frozen and race.frozen.grid or {})
    if n < 2 then return false, "no_field" end
    if n > PaddockSettings.get("liveMaxCars", 16) then return false, "field_too_big" end
    local route = PaddockWorld.route(race.routeId)
    if not route then return false, "no_route" end
    local okDb = pcall(MySQL.update.await, [[INSERT INTO paddock_live (server_id, race_id, declared_by, declared_at, state, cars)
        VALUES (?, ?, ?, ?, 'declared', ?)]], { U.sid(), race.raceId, d.ncmDriverId, t, n })
    if not okDb then return false, "database" end
    byRace[race.raceId] = { raceId = race.raceId, state = "declared", pid = pid, driverId = d.ncmDriverId,
        declaredByName = d.display, declaredAt = t, route = route }
    log("declared %s by %s (%d cars, opens %s)", race.raceId, tostring(d.display), n, NcmCore.get("world.clock").hhmm(race.opensAt))
    return true, { start = { x = route.start.x, y = route.start.y, z = route.start.z }, name = route.start.name or route.name,
        opensAt = race.opensAt, cars = n }
end

local function cancel(lr, reason)
    lr.state, lr.reason = "cancelled", reason
    setRow(lr, { state = "cancelled", reason = reason, ended_at = U.now() })
    for _, c in ipairs(lr.cars or {}) do
        if c.vehicleId then
            byVehicle[c.vehicleId] = nil
            pcall(Open77.vehicles.ai.removeDriver, c.vehicleId)
            pcall(Open77.vehicles.remove, c.vehicleId)
        end
        if c.npcId then pcall(Open77.npcs.remove, c.npcId) end
    end
    if lr.pid then TriggerClientEvent("ncm:paddock.live.end", lr.pid, { raceId = lr.raceId }) end
    notify(lr.pid, "Live run of " .. PaddockWorld.routeName(PaddockRaces.byId[lr.raceId] and PaddockRaces.byId[lr.raceId].routeId) ..
        " called off: " .. tostring(reason) .. ". The sim result stands.")
    log("cancelled %s: %s", lr.raceId, tostring(reason))
end

-- -------------------------------------------------------------------------------------------------------- stage

local function bestGhost(routeId)
    local okQ, row = pcall(MySQL.single.await, [[SELECT poses_json, format FROM ghost_lap WHERE server_id = ? AND route_id = ?
        ORDER BY elapsed_ms LIMIT 1]], { U.sid(), routeId })
    if not okQ or not row or type(row.poses_json) ~= "string" then return nil end
    local okJ, raw = pcall(Json.decode, row.poses_json)
    if not okJ then return nil end
    local poses = Pose.decode(raw, tonumber(row.format))
    return poses
end

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

local function stage(lr, race, t)
    local okP, positions = pcall(Open77.players.positions)
    local me = okP and type(positions) == "table" and positions[lr.pid] or nil
    if not me then return cancel(lr, "you were not in the city") end
    local route = lr.route
    local dStart = L.dist(me, route.start)
    if dStart > PaddockSettings.get("liveStartRadiusM", 300) then
        return cancel(lr, ("you were %.0f m from the start"):format(dStart))
    end
    local w = PaddockStore.world
    local field = PaddockRaces.buildField(race)
    local segments = Sim.segments(route.distanceM, route.laps)
    local path = L.path(route, bestGhost(race.routeId))
    local gates = L.checkpoints(route, path, segments)
    local slots = L.gridSlots(gates[1], #field)
    local want = PaddockSettings.get("liveBackend", "auto")
    local pace = PaddockLive.paceClients[lr.pid]
    local backend = (want == "pace" or (want == "auto" and pace and pace.ok)) and "pace" or "platform"
    if want == "pace" and not (pace and pace.ok) then return cancel(lr, "the Pace plugin is not running on your game") end
    lr.backend, lr.path, lr.gates, lr.segments, lr.field, lr.cars, lr.bucket = backend, path, gates, segments, field, {}, me.bucket or 0
    local npcDrivers = backend == "platform" and PaddockSettings.get("liveNpcDrivers", true)
    for i, e in ipairs(field) do
        local s = slots[i]
        local org = w.orgs[e.orgId or ""]
        local okV, vid, reason = pcall(Open77.vehicles.create, { record = recordFor(org, race.tier),
            position = { x = s.x, y = s.y, z = (s.z or 0) + 0.6 }, yaw = s.yaw, bucket = lr.bucket })
        if not okV or not vid then
            log("stage %s: car %d (%s) refused: %s", race.raceId, i, e.id, tostring(reason or vid))
            return cancel(lr, "the grid could not be built")
        end
        local car = { personId = e.id, orgId = e.orgId, vehicleId = vid, slot = i }
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
        else
            -- The Pace DLL drives on the declarer's client, so that client must simulate every car.
            local okR, st, why = pcall(Open77.vehicles.requestAuthority, vid, lr.pid)
            if not okR or not st then log("stage %s: requestAuthority %d -> %d: %s", race.raceId, vid, lr.pid, tostring(why or st)) end
        end
        Wait(0)
    end
    lr.state = "staging"
    setRow(lr, { state = "staging", backend = backend, path_source = path.source })
    local names = {}
    for i, c in ipairs(lr.cars) do
        names[i] = { vehicleId = c.vehicleId, personId = c.personId, name = PaddockWorld.personName(c.personId),
            org = PaddockWorld.orgName(c.orgId), slot = c.slot }
    end
    TriggerClientEvent("ncm:paddock.live.stage", lr.pid, { raceId = race.raceId, backend = backend, cars = names,
        opensAt = race.opensAt, series = PaddockWorld.seriesName(race.seriesId), route = PaddockWorld.routeName(race.routeId) })
    notify(lr.pid, ("%s on %s: the grid is out. %s. Lights at %s ET."):format(PaddockWorld.seriesName(race.seriesId),
        PaddockWorld.routeName(race.routeId), backend == "pace" and "Pace plugin driving" or "Platform AI driving",
        NcmCore.get("world.clock").hhmm(race.opensAt)), 9000)
    log("staged %s: %d cars, backend=%s, path=%s (%d pts, %.0f m), %d gates", race.raceId, #lr.cars, backend,
        path.source, #path.points, path.lengthM or 0, #gates)
end

-- ----------------------------------------------------------------------------------------------------------- go

local function splitsOf(race, personId)
    local r = race.result
    if not r then return nil end
    for _, e in ipairs(r.entrants or {}) do if e.id == personId then return e.splits end end
    return nil
end

local function go(lr, race)
    local points = {}
    for i = 2, #lr.path.points do points[#points + 1] = lr.path.points[i] end   -- the grid is point 1
    local cap = lr.backend == "pace" and PaddockSettings.get("livePaceMaxMps", 90) or L.PLATFORM_MAX_MPS
    local leaderMs
    for _, c in ipairs(lr.cars) do
        c.plan = L.speedPlan(lr.path.points, lr.path.lengthM, splitsOf(race, c.personId), lr.segments, cap)
    end
    if race.result and race.result.entrants and race.result.entrants[1] then leaderMs = race.result.entrants[1].finishMs end
    leaderMs = leaderMs or math.floor((lr.path.lengthM or 3000) / 30 * 1000)
    lr.goMs = nowMs() + PaddockSettings.get("liveCountdownSec", 5) * 1000
    lr.deadlineMs = math.floor(leaderMs * PaddockSettings.get("liveTimeoutFactor", 2.5)) + 30000
    lr.timing = L.newTiming(lr.gates, (function() local ids = {} for i, c in ipairs(lr.cars) do ids[i] = c.personId end return ids end)())
    lr.out, lr.client = {}, {}
    lr.state = "running"
    setRow(lr, { state = "running", go_at = lr.goMs / 1000 })
    TriggerClientEvent("ncm:paddock.live.countdown", lr.pid, { raceId = lr.raceId, goInMs = lr.goMs - nowMs() })
    notify(lr.pid, ("Lights out in %d seconds."):format(PaddockSettings.get("liveCountdownSec", 5)), 4000)
    if lr.backend == "pace" then
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
            for _, c in ipairs(lr.cars) do
                local okF, st, why = pcall(Open77.vehicles.ai.followRoute, c.vehicleId, { points = points, speed = c.plan[1] or 20,
                    behavior = "aggressive", arrivalRadius = 12, timeoutMilliseconds = math.min(3600000, lr.deadlineMs + 60000) })
                if not okF or not st then
                    log("go %s: followRoute %d refused: %s", lr.raceId, c.vehicleId, tostring(why or st))
                    lr.out[c.personId] = "no_start"
                end
            end
        end
        PaddockLive.sample(lr, race)
    end)
end

-- ----------------------------------------------------------------------------------------------------- run/finish

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
    local c = L.classify(lr.timing, fieldIds, lr.out, { clientOk = clientOk })
    lr.verdict, lr.reason = c.verdict, c.reason
    if c.verdict == "physical" then
        local ok, err = writeBack(lr, race, c)
        if not ok then lr.verdict, lr.reason = "fallback", "write-back failed: " .. tostring(err) end
    end
    storeCrossings(lr)
    lr.state = "finished"
    setRow(lr, { state = "finished", verdict = lr.verdict, reason = lr.reason or "", ended_at = U.now(),
        detail_json = U.encode({ finishers = c.finishers, out = lr.out }) or "{}" })
    local winner = c.entrants[1] and c.entrants[1].state == "finished" and PaddockWorld.personName(c.entrants[1].id) or nil
    notify(lr.pid, lr.verdict == "physical"
        and ("Live result stands: %s wins on the street. %d of %d finished."):format(tostring(winner), c.finishers, #lr.cars)
        or ("The street run didn't count (%s). The sim result stands."):format(tostring(lr.reason)), 9000)
    TriggerClientEvent("ncm:paddock.live.end", lr.pid, { raceId = lr.raceId, verdict = lr.verdict })
    log("finished %s: verdict=%s reason=%s finishers=%d/%d", lr.raceId, lr.verdict, tostring(lr.reason), c.finishers, #lr.cars)
    -- the cars linger a moment where they stopped, then go
    CreateThread(function()
        Wait(20000)
        for _, car in ipairs(lr.cars) do
            byVehicle[car.vehicleId] = nil
            pcall(Open77.vehicles.ai.removeDriver, car.vehicleId)
            pcall(Open77.vehicles.remove, car.vehicleId)
            if car.npcId then pcall(Open77.npcs.remove, car.npcId) end
        end
    end)
end

--- The server's own timing loop. Every car's canonical position every `liveSampleMs`, until every car is done or
--- out, or the deadline passes.
function PaddockLive.sample(lr, race)
    local stallSec = PaddockSettings.get("liveStallSec", 30)
    while lr.state == "running" do
        local tMs = nowMs() - lr.goMs
        for _, c in ipairs(lr.cars) do
            if not lr.out[c.personId] and not lr.timing.cars[c.personId].done then
                local okP, pos = pcall(Open77.vehicles.getPosition, c.vehicleId)
                if not okP or type(pos) ~= "table" then
                    lr.out[c.personId] = "lost"
                else
                    L.observe(lr.timing, c.personId, pos, tMs)
                    local okH, health = pcall(Open77.vehicles.getHealth, c.vehicleId)
                    if okH and type(health) == "number" and health <= 0 then lr.out[c.personId] = "wrecked"
                    elseif tMs > 15000 and L.stalled(lr.timing, c.personId, tMs, stallSec) then lr.out[c.personId] = "stalled" end
                end
            end
        end
        if L.allDone(lr.timing, lr.out) or tMs > lr.deadlineMs then
            for _, c in ipairs(lr.cars) do
                if not lr.timing.cars[c.personId].done and not lr.out[c.personId] then lr.out[c.personId] = "timeout" end
            end
            finish(lr, race)
            return
        end
        Wait(PaddockSettings.get("liveSampleMs", 250))
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
                -- followRoute's points are path points 2..N, so route point k ends plan leg k. The card does not say
                -- whether `routeIndex` counts from 0 or 1; either way this picks the leg after the one just ended,
                -- or the one after that, and a ceiling one leg early is harmless.
                local idx = (tonumber(state.routeIndex) or 0) + 1
                local v = c.plan and (c.plan[idx + 1] or c.plan[#c.plan])
                if v then pcall(Open77.vehicles.ai.setSpeed, vid, v) end
                return
            end
        end
    end)
end

-- --------------------------------------------------------------------------------------------------------- tick

--- One pass from the main scheduler: stage what is due, start what is staged. Bounded: at most one of each.
function PaddockLive.tick(t)
    for _, lr in pairs(byRace) do
        local race = PaddockRaces.byId[lr.raceId]
        if not race or race.state == "void" then
            if PaddockLive.holds(lr.raceId) then cancel(lr, "the race was voided") end
        elseif lr.state == "declared" and t >= race.opensAt - PaddockSettings.get("liveStageLeadSec", 75) then
            local ok, err = pcall(stage, lr, race, t)
            if not ok then log("stage %s FAILED: %s", lr.raceId, tostring(err)); if lr.state ~= "cancelled" then cancel(lr, "staging failed") end end
            return
        elseif lr.state == "staging" and t >= race.opensAt and race.state == "running" then
            local ok, err = pcall(go, lr, race)
            if not ok then log("go %s FAILED: %s", lr.raceId, tostring(err)); cancel(lr, "the start failed") end
            return
        end
    end
    -- forget finished records after a while
    for id, lr in pairs(byRace) do
        if (lr.state == "finished" or lr.state == "cancelled") and (lr.declaredAt or 0) < t - 6 * 3600 then byRace[id] = nil end
    end
end

--- Boot: a live race cannot survive a restart (its cars went with the old process). Say so in the ledger.
function PaddockLive.boot()
    pcall(MySQL.update.await, [[UPDATE paddock_live SET state = 'cancelled', reason = 'server restarted', ended_at = ?
        WHERE server_id = ? AND state IN ('declared','staging','running')]], { U.now(), U.sid() })
end

-- --------------------------------------------------------------------------------------------------------- events

RegisterNetEvent("ncm:paddock.live", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(req) ~= "table" or not PaddockWorld.ready then return end
    CreateThread(function()
        local ok, res = PaddockLive.declare(pid, tostring(req.raceId or ""))
        local REASONS = { disabled = "Live races are switched off.", not_open = "That race is not open.", already_live = "It's already going live.",
            too_late = "Too close to the lights. Declare a live run at least a few minutes out.", too_early = "Too far out. Come back nearer the time.",
            one_at_a_time = "One live race at a time.", no_driver = "No Driver on file.", no_field = "No field.", field_too_big = "That grid is too big to run live.",
            no_route = "No route.", database = "The ledger refused it." }
        if ok then
            TriggerClientEvent("ncm:paddock.result", pid, { op = "live", ok = true,
                text = ("Declared. Be at %s before %s ET; the grid spawns there."):format(tostring(res.name), NcmCore.get("world.clock").hhmm(res.opensAt)) })
            TriggerClientEvent("ncm:paddock.live.declared", pid, { raceId = req.raceId, start = res.start, name = res.name })
        else
            TriggerClientEvent("ncm:paddock.result", pid, { op = "live", ok = false, text = REASONS[res] or tostring(res) })
        end
        PaddockViews.send(pid, { view = "results" })
    end)
end)

-- The client says whether the Pace plugin answered on loopback (client/live.lua).
RegisterNetEvent("ncm:paddock.live.pace", function(info)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(info) ~= "table" then return end
    PaddockLive.paceClients[pid] = { ok = info.ok == true, version = tostring(info.version or "") }
end)

-- Gate reports from the Pace DLL, relayed by the declarer's client. Evidence, not authority: they count only when
-- the server's own times agree (paddock.live.corroborate).
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
    local pid = tonumber(playerId) or 0
    PaddockLive.paceClients[pid] = nil
    for _, lr in pairs(byRace) do
        if lr.pid == pid and (lr.state == "declared" or lr.state == "staging") then cancel(lr, "the declarer left") end
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    for _, lr in pairs(byRace) do
        for _, c in ipairs(lr.cars or {}) do
            pcall(Open77.vehicles.remove, c.vehicleId)
            if c.npcId then pcall(Open77.npcs.remove, c.npcId) end
        end
    end
end)
