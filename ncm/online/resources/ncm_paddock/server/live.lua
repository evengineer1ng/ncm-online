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
local Ovals = NcmCore.get("data.ovals")
local Sim = NcmCore.get("paddock.sim")
local Season = NcmCore.get("paddock.season")
local Finance = NcmCore.get("paddock.finance")
local Hash = NcmCore.get("vocabulary.hash")
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

--- Use the exact closed line baked into Pace's oval spline for model positions and the grid. The old polar ring can
--- be several metres off the traffic lane; a bubble car set down there may hit a wall before it joins the racer.
local function ovalRoadPath(route)
    local enc = type(PaddockOvalLines) == "table" and PaddockOvalLines[route.routeId]
    if not enc then return nil end
    local loop = {}
    for x, y, z in enc:gmatch("([^,;]+),([^,;]+),([^,;]+)") do
        loop[#loop + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end
    if #loop < 8 then return nil end
    local cum = { 0 }
    for i = 2, #loop do cum[i] = cum[i - 1] + L.dist(loop[i - 1], loop[i]) end
    local lapLen = cum[#loop] + L.dist(loop[#loop], loop[1])
    local markD = {}
    for k = 2, #route.oval.loop do
        local mark, best = route.oval.loop[k], math.huge
        for i, p in ipairs(loop) do
            local d = L.dist(mark, p)
            if d < best then best, markD[k] = d, cum[i] end
        end
    end
    local behind = { loop[1] }
    for i = #loop, 1, -1 do behind[#behind + 1] = loop[i] end
    local points, nodeD = {}, { 0 }
    for lap = 0, route.oval.laps - 1 do
        for _, p in ipairs(loop) do points[#points + 1] = p end
        for k = 2, #route.oval.loop do nodeD[#nodeD + 1] = lap * lapLen + markD[k] end
        nodeD[#nodeD + 1] = (lap + 1) * lapLen
    end
    points[#points + 1] = loop[1]
    return { points = points, lengthM = lapLen * route.oval.laps, source = "ring", nodeD = nodeD, ovalBehind = behind }
end

--- The line for a route: its authored points (start, checkpoints, finish), or an oval's ring. Cached ten minutes.
--- **Never a ghost** (owner, 2026-09-30, L243): "ghosts are not there as a crutch for the race system". Whether a human
--- once drove a route cannot decide how a race runs -- the route combinations are far too many -- and a 48-point ghost
--- tape is what blew the host client's script budget at 20:42 (KB-241). Pace finds the road between the points.
function PaddockLive.pathFor(routeId)
    local c = pathCache[routeId]
    if c and U.now() - c.at < 600 then return c.path end
    local route = PaddockWorld.route(routeId)
    if not route then return nil end
    local path = (route.oval and ovalRoadPath(route)) or L.path(route, nil)
    if path.source == "direct" then path = PaddockLive.roadPath(route, path) or path end
    pathCache[routeId] = { path = path, at = U.now() }
    return path
end

local roadCache = {}                 -- "from__to" -> decoded points

--- One baked leg's road line, decoded once (nil if it was never baked).
local function legLine(key)
    local leg = roadCache[key]
    if leg then return leg end
    local enc = type(PaddockRoadLines) == "table" and PaddockRoadLines[key]
    if not enc then return nil end
    leg = {}
    for x, y, z in enc:gmatch("([^,;]+),([^,;]+),([^,;]+)") do leg[#leg + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
    if #leg < 2 then return nil end
    roadCache[key] = leg
    return leg
end

--- A street route's ROAD line (IDEA-787, L247): each leg's line from NCM Pace's bake (server/roadlines_data.lua, the
--- same lane-graph route the leg's race spline follows), joined end to end. The race model, the watchers and the
--- bubble then stand on the road instead of a chord through the buildings between checkpoints. `nodes` keeps the
--- authored points: Pace's leg index is the authored point a car is heading for, so its plan is still those.
--- nil when a leg is not two race nodes or was never baked.
function PaddockLive.roadPath(route, direct)
    if type(PaddockRoadLines) ~= "table" then return nil end
    local chain = { route.start and route.start.id }
    for _, m in ipairs(route.intermediate or {}) do chain[#chain + 1] = m.nodeId or false end
    chain[#chain + 1] = route.finish and route.finish.id
    local pts, total, nodeD = {}, 0, { 0 }
    for i = 2, #chain do
        if not chain[i - 1] or not chain[i] then return nil end
        local leg = legLine(chain[i - 1] .. "__" .. chain[i])
        if not leg then return nil end
        for k = (#pts > 0) and 2 or 1, #leg do
            local p = leg[k]
            if #pts > 0 then total = total + L.dist(pts[#pts], p) end
            pts[#pts + 1] = p
        end
        nodeD[i] = total
    end
    if #pts < 2 then return nil end
    -- nodeD[k]: how far along the road authored point k is (the bubble's car.add starts a car on the leg it is in)
    return { points = pts, lengthM = total, source = "road", nodes = direct.points, nodeD = nodeD }
end

--- The road behind a street route's start, start first and running back (L247): where its grid stands. Baked per leg
--- from the lane graph (`bake_legs --grids` -> server/roadlines_data.lua `PaddockGridLines`): from the lane the race
--- leaves on, back through the predecessor that runs straightest into it. 1,099 of the 1,190 first legs have one (992
--- long enough for twelve cars; roadSlots runs straight on from a shorter one's end). nil for the rest (under 20 m of
--- road behind the start) -- SP's straight grid then stands as before. `needM` is unused (kept for callers).
function PaddockLive.gridLine(route, needM)
    if not route or not route.start or not route.start.id or type(PaddockGridLines) ~= "table" then return nil end
    local nextId = (route.intermediate and route.intermediate[1] and route.intermediate[1].nodeId) or (route.finish and route.finish.id)
    if not nextId then return nil end
    local key = route.start.id .. "__" .. nextId
    local c = roadCache["grid:" .. key]
    if c then return c end
    local enc = PaddockGridLines[key]
    if not enc then return nil end
    local line = {}
    for x, y, z in enc:gmatch("([^,;]+),([^,;]+),([^,;]+)") do line[#line + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
    if #line < 2 then return nil end
    roadCache["grid:" .. key] = line
    return line
end

--- A street route's start grid (L250): the lane-based bake for its first leg, through course.grid_solver (hand
--- overrides first). Returns slots ({ x, y, z, yaw, slot, col, row }) and a note ("baked", "override", "short",
--- "none"); with no bake at all, the old straight grid along the road into the start (note "fallback").
function PaddockLive.gridSlots(route, n, profile)
    local nextId = (route.intermediate and route.intermediate[1] and route.intermediate[1].nodeId) or (route.finish and route.finish.id)
    local key = route.start and route.start.id and nextId and (route.start.id .. "__" .. nextId)
    local entry = key and type(PaddockGridSlots) == "table" and PaddockGridSlots[key] or nil
    local slots, note = NcmCore.get("course.grid_solver").slotsFor(entry, route.start and route.start.id, nextId, n, profile)
    if note ~= "none" then return slots, note end
    local rowM, backM = profile.aiGridRowSpacingM or 12, profile.aiGridStartSetbackM or 12
    local behind = PaddockLive.gridLine(route, backM + rowM * (math.ceil(n / 2) - 1) + 1)
    return behind and L.roadSlots(behind, n, profile) or L.gridSlots(route.start, route.finish, n, profile), "fallback"
end

--- Does a race run on the continuous model and the physical bubble (L230, L247)? An oval (its ring), and a street
--- route with a road line. Such a race is never a grid street run: the cars near a player are physical with a driver
--- in the seat, the rest are the model, and no car with a driver is left out at the edge of anyone's streaming (KB-238).
function PaddockLive.onBubble(routeId)
    if Ovals.isOval(routeId) then return true end
    local path = PaddockLive.pathFor(routeId)
    return path ~= nil and path.source == "road"
end

--- The race spline for each leg of a route, in order: `$/mod/ncm_pace/#leg_<from>__<to>`, the refs
--- tools/bake-race-splines.py bakes for every ordered pair of race nodes (L246). nil when a leg's ends are not both
--- nodes (an authored point that is not a node has no spline).
function PaddockLive.legsFor(route)
    local chain = { route.start and route.start.id }
    for _, m in ipairs(route.intermediate or {}) do chain[#chain + 1] = m.nodeId or false end
    chain[#chain + 1] = route.finish and route.finish.id
    local legs = {}
    for i = 2, #chain do
        if not chain[i - 1] or not chain[i] then return nil end
        legs[#legs + 1] = ("$/mod/ncm_pace/#leg_%s__%s"):format(chain[i - 1], chain[i])
    end
    return legs
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

local function recordFor(org, tier, oval)
    local band = (Season.TIERS[tier] or {}).band or {}
    local list = {}
    for _, class in ipairs(band.classes or { "Sport" }) do
        for _, r in ipairs(Pool.records(class, band.prestigeMax)) do
            if (tonumber(r.prestige) or 1) >= (band.prestigeMin or 0) then list[#list + 1] = r.id end
        end
    end
    if #list == 0 then list = { "Vehicle.v_sport2_quadra_type66" } end
    local record = Hash.pick(list, "livecar", org and org.id or "none")
    -- Ovals only: NCM Pace ships isolated TweakXL racer clones with its higher RaceDrive profile.
    if oval then return (record:gsub("^Vehicle%.", "Vehicle.ncm_racer_")) end
    return record
end

local DRIVER_RECORDS = { m = { "Character.WorkerMale", "Character.YoungsterMale", "Character.AsianMale" },
    f = { "Character.YoungsterFemale", "Character.AsianFemale" } }
PaddockLive.recordFor = recordFor

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
    PaddockLive.lowerAreas(lr.raceId)
    log("cancelled %s: %s", lr.raceId, tostring(reason))
end

local function stage(race, host, t)
    local w = PaddockStore.world
    local route = PaddockWorld.route(race.routeId)
    local path = PaddockLive.pathFor(race.routeId)
    if not route or not path then return end
    -- A live grid used to stage at T-75 and froze the field while entries were still allowed. Hold staging
    -- until the shared T-1 cutoff; the scheduler will retry on its next tick.
    if race.opensAt - t > NcmCore.get("paddock.mixed").FREEZE_LEAD_SEC then return end
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
    -- the owner's own single-player grid: authored node heading, SP's road-axis correction, the route's tuning
    -- (data.grid_profiles); tools/test-grid-oracle.lua holds it to SP's code (L232)
    local allSlots = route.oval and L.ovalSlots(route.oval, #field + 8, NcmCore.get("data.grid_profiles").forRoot(race.routeId))   -- SP formation along the ring (L236, KB-223)
        or L.gridSlots(route.start, route.finish, #field + 8, NcmCore.get("data.grid_profiles").forRoot(race.routeId))
    -- never set a car down on a person: a slot with a player within liveSlotClearM is skipped, and its car takes the
    -- next free slot at the back (the banner told them to clear the area, L233)
    local clearM = set("liveSlotClearM", 6)
    local people = positions()
    local slots, skipped = {}, 0
    for _, s in ipairs(allSlots) do
        local taken = false
        for _, pos in pairs(people) do if L.dist(pos, s) <= clearM then taken = true break end end
        if taken then skipped = skipped + 1 elseif #slots < #field then slots[#slots + 1] = s end
    end
    -- an oval's points may come from map waypoints, whose height is not the road's: ground every oval slot (L236)
    -- from just above the marked height first: a ray from 30 m up lands on whatever deck or walkway spans the road
    -- (Corpo Circle, KB-223); the high ray only when the low one finds nothing
    if route.oval then
        for i, sl in ipairs(slots) do
            local marked = sl.z or 0
            local zOk, z = pcall(Open77.world.groundZ, { x = sl.x, y = sl.y }, { radius = 400, fromZ = marked + 4, timeout = 1500, cache = true })
            if not (zOk and type(z) == "number") then
                zOk, z = pcall(Open77.world.groundZ, { x = sl.x, y = sl.y }, { radius = 400, fromZ = marked + 30, timeout = 1500, cache = true })
            end
            if zOk and type(z) == "number" then sl.z = z end
            if i <= 2 then log("stage %s: oval slot %d at %.1f, %.1f z %.1f (marked %.1f) yaw %.0f", race.raceId, i, sl.x, sl.y, sl.z or 0, marked, sl.yaw or 0) end
        end
    end
    if #slots < #field and route.oval and #slots >= 4 then
        for i = #field, #slots + 1, -1 do field[i] = nil end            -- an oval grids what it has room for
    end
    if #slots < #field then return cancel(lr, "the grid is blocked: players are standing on it") end
    if skipped > 0 then log("stage %s: %d slot(s) had a player on them; those cars start further back", race.raceId, skipped) end
    -- L246: a street run is the engine's racer on NCM Pace's race splines, or nothing -- the platform AI backend is
    -- retired. No Pace on the host, or a route whose legs have no race spline, means the race stays the sim's.
    local pace = host and PaddockLive.paceClients[host.pid]
    if not (pace and pace.ok) then return cancel(lr, "the host has no NCM Pace: street runs are on race splines only") end
    local backend = "pace"
    local legs = PaddockLive.legsFor(route)
    if not legs then return cancel(lr, "a leg of this route has no race spline") end
    lr.legs = legs
    -- the platform's followRoute takes 1..64 points; only Pace takes a longer plan, as a tape (0.3.1, KB-223)
    if backend == "platform" and #path.points > L.MAX_POINTS then
        return cancel(lr, ("a %d-point line needs the Pace plugin (platform AI takes %d)"):format(#path.points, L.MAX_POINTS))
    end
    lr.backend, lr.path, lr.gates, lr.segments, lr.field = backend, path, gates, segments, field
    local npcDrivers = set("liveNpcDrivers", true) and (backend == "platform" or set("livePaceDrivers", true))
    for i, e in ipairs(field) do
        local s = slots[i]
        local org = w.orgs[e.orgId or ""]
        -- The vanilla record: the race profile is every vehicle record's own `drivingParamsRace`, which the engine's racing
        -- command uses (L246). No custom records -- nothing the platform could refuse.
        local record = recordFor(org, race.tier, route.oval ~= nil)
        local okV, vid, reason = pcall(Open77.vehicles.create, { record = record,
            position = { x = s.x, y = s.y, z = (s.z or 0) + 0.6 }, yaw = s.yaw, bucket = lr.bucket })
        if not okV or not vid then
            log("stage %s: car %d (%s) refused: %s", race.raceId, i, e.id, tostring(reason or vid))
            return cancel(lr, "the grid could not be built")
        end
        local car = { personId = e.id, orgId = e.orgId, vehicleId = vid, slot = i, row = s.row, recoveries = 0, resets = 0 }
        lr.cars[#lr.cars + 1] = car
        byVehicle[vid] = { raceId = race.raceId, personId = e.id }
        log("TRACE race=%s stage slot=%d person=%s vid=%s record=%s host=%s bucket=%s backend=%s",
            race.raceId, i, e.id, tostring(vid), record, tostring(host and host.pid), tostring(lr.bucket), backend)
        if backend == "platform" or npcDrivers then
            -- a visible driver at the wheel (SP seats one, L234). On the Pace backend the car gets no platform task:
            -- the attach only seats the NPC, and the Pace plugin sends the drive commands on the host's client.
            local npcId
            if npcDrivers then
                local p = w.people[e.id]
                local okN, id = pcall(Open77.npcs.create, { record = Hash.pick(DRIVER_RECORDS[(p and p.gender == "f") and "f" or "m"], "driver", e.id),
                    position = { x = s.x, y = s.y, z = (s.z or 0) + 0.6 }, yaw = s.yaw, bucket = lr.bucket,
                    aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or nil,
                    damagePolicy = Open77.npcs.damage and Open77.npcs.damage.invulnerable or nil,
                    despawnWhenUnobserved = false, persistent = false })
                if okN and id then npcId = id; car.npcId = id end
                log("TRACE race=%s driver slot=%d vid=%s npc=%s created=%s", race.raceId, i,
                    tostring(vid), tostring(npcId), tostring(okN and id ~= nil))
            end
            local okA, st, why = pcall(Open77.vehicles.ai.attachDriver, vid, npcId and { npcId = npcId } or nil)
            if (not okA or not st) and npcId then
                pcall(Open77.npcs.remove, npcId); car.npcId = nil
                okA, st, why = pcall(Open77.vehicles.ai.attachDriver, vid, nil)
            end
            log("TRACE race=%s attach slot=%d vid=%s npc=%s accepted=%s reason=%s", race.raceId, i,
                tostring(vid), tostring(car.npcId), tostring(okA and st ~= nil and st ~= false), tostring(why))
            if (not okA or not st) and backend == "pace" then
                -- a seat is a nicety on the Pace backend: fall back to 0.2.0's driverless car under the host
                log("stage %s: attachDriver %d refused (%s); driverless under the host", race.raceId, vid, tostring(why or st))
                local okR, stR, whyR = pcall(Open77.vehicles.requestAuthority, vid, host.pid)
                if not okR or not stR then log("stage %s: requestAuthority %d -> %d: %s", race.raceId, vid, host.pid, tostring(whyR or stR)) end
            elseif not okA or not st then
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
        PaddockLive.raiseArea(race, wch.pid, t)
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
    local ceilingFactor = (lr.route and lr.route.oval)
        and math.max(2.25, tonumber(set("liveOvalSpeedCeilingFactor", 2.25)) or 2.25) or 1
    for _, c in ipairs(lr.cars) do
        -- Pace's plan is the authored points, one per leg (its leg index is the point a car is heading for, L246)
        local plan = L.speedPlan(lr.path.nodes or lr.path.points, lr.path.lengthM, splitsOf(race, c.personId), lr.segments, cap)
        if ceilingFactor ~= 1 then
            for i, mps in ipairs(plan) do
                plan[i] = math.floor(math.min(cap, mps * ceilingFactor) * 10 + 0.5) / 10
            end
        end
        c.plan = plan
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
        -- KB-223: the plan crosses a WebUI hop that drops large payloads without a word (KB-86: ~18 KB arrives, ~22.5 KB
        -- does not). A street plan is ~1.5 KB; an oval's 33-61 points, gates and per-leg speeds reached 15-28 KB at full
        -- precision, and no oval plan was ever acknowledged by Pace. Centimetres and 1e-4 directions are ample.
        local function r(v, k) return math.floor(v * k + 0.5) / k end
        local cars = {}
        for i, c in ipairs(lr.cars) do cars[i] = { vehicleId = c.vehicleId, personId = c.personId, speeds = c.plan } end
        local gates = {}
        for i, g in ipairs(lr.gates) do gates[i] = { x = r(g.x, 100), y = r(g.y, 100), z = r(g.z or 0, 100), dx = r(g.dir.x, 1e4), dy = r(g.dir.y, 1e4),
            halfWidth = r(g.halfWidthM, 10), capture = r(g.captureM, 10) } end
        local points = {}
        for i, p in ipairs(lr.path.nodes or lr.path.points) do points[i] = { x = r(p.x, 100), y = r(p.y, 100), z = r(p.z or 0, 100) } end
        -- The plan crosses the NETWORK as a tape too (KB-223): a 25-lap oval in one event was "dropped malformed network
        -- event payload" on the client, 1 ms after the go. Numbered parts of DRIVE_PART points, gates and per-leg speeds;
        -- the client rebuilds the plan once every part is in. Part 1 carries the header. Never an empty list: an empty
        -- Lua table crosses as {}, so a missing field means "none in this part".
        local DRIVE_PART = 24
        local function slice(t, a, b) local o = {} for i = a, math.min(b, #t) do o[#o + 1] = t[i] end return #o > 0 and o or nil end
        local parts = math.max(1, math.ceil(math.max(#points, #gates) / DRIVE_PART))
        for k = 1, parts do
            local a, b = (k - 1) * DRIVE_PART + 1, k * DRIVE_PART
            local speeds = {}
            for i, c in ipairs(cars) do speeds[i] = slice(c.speeds or {}, a, b) or { (c.speeds and c.speeds[#c.speeds]) or 20 } end
            local msg = { raceId = lr.raceId, part = k, parts = parts, points = slice(points, a, b), gates = slice(gates, a, b), speeds = speeds }
            if k == 1 then
                local header = {}
                for i, c in ipairs(cars) do header[i] = { vehicleId = c.vehicleId, personId = c.personId } end
                msg.cars = header
                msg.goInMs = lr.goMs - nowMs()
                -- SP's launch: the capped release, the grace, the recommand cadence and the stall rule, per route (L234)
                msg.launch = L.launchProfile(NcmCore.get("data.grid_profiles").forRoot(race.routeId))
                -- switch to the next point sooner on authored points than on a ghost line: a generated route's checkpoint
                -- or an oval's pole must actually be reached, or its gate is missed (L236)
                msg.advanceM = (lr.path.source == "ghost") and 40 or (lr.route.oval and math.max(6, math.min(15, lr.route.oval.radius * 0.5)) or 15)
                msg.legs = lr.legs           -- L246: the race spline for each leg
            end
            TriggerClientEvent("ncm:paddock.live.drive", lr.pid, msg)
        end
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

--- Replace a race's sealed sim rows with a classification the street produced (the whole street run, or the model
--- with the bubble's anchors). provenance: physical | mixed. Before the close only, so Billie settles once, after this.
function PaddockLive.writeResult(race, entrants, provenance, backend, detailExtra)
    local purse = Finance.purse(race.tier, #entrants)
    local st = { { query = "DELETE FROM paddock_result WHERE server_id = ? AND race_id = ?", values = { U.sid(), race.raceId } } }
    local splits = {}
    for _, e in ipairs(entrants) do
        e.points = Season.pointsFor(e.position, e.state)
        -- a human's pay is the league's (Economy v1, by the same place); the Paddock's purse is its NPCs'
        e.purse = (e.state == "finished" and not e.human) and (purse[e.position] or 0) or 0
        splits[e.id] = e.splits
        st[#st + 1] = { query = [[INSERT INTO paddock_result (server_id, race_id, person_id, org_id, series_id, season_id,
            cup_id, position, grid, state, finish_ms, gap_ms, points, purse, dnf_reason, at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, -1), ?, ?, NULLIF(?, ''), ?)]],
            values = { U.sid(), race.raceId, e.id, e.orgId or "", race.seriesId, race.seasonId, race.cupId, e.position,
                e.grid, e.state, e.finishMs or -1, e.gapMs or -1, e.points, e.purse, e.dnfReason or "", race.opensAt } }
    end
    local detail = { frozen = race.frozen, splits = splits, events = {}, segments = race.result and race.result.segments, live = detailExtra }
    st[#st + 1] = { query = [[UPDATE paddock_race SET provenance = ?, backend = ?, detail_json = ?, window_closes_at = ?
        WHERE server_id = ? AND race_id = ?]], values = { provenance, backend, U.encode(detail) or "{}", U.now() + 5, U.sid(), race.raceId } }
    local ok, err = U.transact(st)
    if not ok then return false, err end
    race.result = { entrants = entrants, events = {}, segments = race.result and race.result.segments }
    race.provenance = provenance
    race.closesAt = U.now() + 5
    return true
end

local function writeBack(lr, race, c)
    return PaddockLive.writeResult(race, c.entrants, "physical", lr.backend == "pace" and "pace" or "platformAI",
        { backend = lr.backend, path = lr.path.source, gates = #lr.gates })
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
    PaddockLive.lowerAreas(lr.raceId)
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
                        c.lastPos = pos
                    end
                end
            end
            -- an oval's first live runs are evidence (KB-223): where each car really is, off the ring and round it
            local o = lr.route and lr.route.oval
            if o then
                for _, mark in ipairs({ 10000, 30000 }) do
                    lr.ovalSnap = lr.ovalSnap or {}
                    if tMs >= mark and not lr.ovalSnap[mark] then
                        lr.ovalSnap[mark] = true
                        for _, c in ipairs(lr.cars) do
                            local p = c.lastPos
                            if p then
                                local off = L.dist({ x = o.cx, y = o.cy }, p) - o.radius
                                local ang = math.deg((math.atan(p.y - o.cy, p.x - o.cx) - o.startAngle) * o.sign) % 360
                                log("%s +%ds: %s off-ring %+.0f m, %.0f deg round, z %.1f, next gate %d%s", lr.raceId, math.floor(mark / 1000),
                                    c.personId, off, ang, p.z or 0, lr.timing.cars[c.personId].next, lr.out[c.personId] and (" OUT " .. lr.out[c.personId]) or "")
                            end
                        end
                    end
                end
            end
        end
        local leader = L.leaderMs(lr.timing)
        if leader and not lr.closeMs then
            lr.closeMs = leader + math.max(set("liveFinishGraceSec", 90) * 1000, math.floor(leader * 0.5))
            log("%s: the winner is home at %.1f s; the rest have until %.0f s", lr.raceId, leader / 1000, lr.closeMs / 1000)
        end
        local over = L.allDone(lr.timing, lr.out) or tMs > lr.deadlineMs or (lr.closeMs and tMs > lr.closeMs)
        -- Pace's gate reports reach the server AFTER the server sees the crossing (client relay), so the last finisher's
        -- would always be missing at the instant the race is over, and the whole result "not corroborated". Wait up to
        -- livePaceReportGraceMs for them before the verdict (L246).
        if over and lr.backend == "pace" and not L.corroborate(lr.timing, lr.client) then
            lr.reportsBy = lr.reportsBy or (tMs + set("livePaceReportGraceMs", 3000))
            if tMs < lr.reportsBy then over = false end
        end
        if over then
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

-- KB-238: pair the client's native engine entity hashes with authoritative lease transitions.
-- OPEN//77 event IDs arrive as strings; the race lookup is keyed by numeric vehicle ID.
AddEventHandler("onVehicleAuthorityChanged", function(id, owner, epoch, reason)
    local ref = byVehicle[tonumber(id)]
    if not ref then return end
    local ok, v = pcall(Open77.vehicles.get, tonumber(id))
    local p = ok and type(v) == "table" and v.position or nil
    log("TRACE race=%s authority person=%s vid=%s owner=%s epoch=%s reason=%s pos=%s", ref.raceId,
        ref.personId, tostring(id), tostring(owner), tostring(epoch), tostring(reason),
        type(p) == "table" and ("%.1f,%.1f,%.1f"):format(p.x or 0, p.y or 0, p.z or 0) or "nil")
end)

AddEventHandler("onVehicleRemoved", function(id, reason)
    local ref = byVehicle[tonumber(id)]
    if ref then log("TRACE race=%s removed person=%s vid=%s reason=%s", ref.raceId,
        ref.personId, tostring(id), tostring(reason)) end
end)

-- Per-leg ceilings on the platform backend: each waypoint reached sets the next leg's speed.
if Open77.vehicles and Open77.vehicles.ai and Open77.vehicles.ai.on then
    pcall(Open77.vehicles.ai.on, "waypointReached", function(state)
        local vid = tonumber(state and state.vehicleId)
        local ref = vid and byVehicle[vid]
        if not ref then if PaddockBubble then PaddockBubble.onAi("waypointReached", state) end return end
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
            if not ref and PaddockBubble then PaddockBubble.onAi(ev, state) return end
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

-- --------------------------------------------------------------------------------------------------------- warn

local warned = {}                    -- raceId -> { [pid] = true }
local areas = {}                     -- raceId -> { [pid] = true }: who holds a traffic null area for it

--- The native traffic null area over a start (L234, NCM Pace 0.3.0): gameCommunitySystem.EnableDynamicCrowdNullArea on
--- the player's own client, a square of the route's SP trafficClearRadiusM around the start node, until
--- liveTrafficClearTailSec after the lights. Traffic is simulated per client, so every nearby client needs its own.
local function raiseArea(race, pid, t)
    if not set("liveTrafficClear", true) then return end
    local route = PaddockWorld.route(race.routeId)
    if not route then return end
    local prof = NcmCore.get("data.grid_profiles").forRoot(race.routeId)
    local seconds = math.max(1, race.opensAt - t) + set("liveCountdownSec", 5) + set("liveTrafficClearTailSec", 60)
    -- an oval races ON the roundabout for its whole distance: hold the area for the race, not a start's minute
    if route.oval then seconds = math.max(1, race.opensAt - t) + math.floor((route.distanceM or 0) / 25) + 120 end
    areas[race.raceId] = areas[race.raceId] or {}
    areas[race.raceId][pid] = true
    local at, half = route.start, prof.trafficClearRadiusM or 140
    local ovalMode = route.oval and set("liveOvalClearMode", "ring") or nil
    if ovalMode == "off" then return end
    -- an oval races the whole ring, not a start line: clear the roundabout and a margin round it (L236)
    if ovalMode == "ring" then
        at = { x = route.oval.cx, y = route.oval.cy, z = route.oval.cz }
        half = math.max(half, route.oval.radius + set("liveOvalClearMarginM", 80))
    end
    TriggerClientEvent("ncm:paddock.live.area", pid, { raceId = race.raceId, x = at.x, y = at.y, z = at.z or 0,
        half = half, halfZ = 30, seconds = seconds })
end

PaddockLive.raiseArea = raiseArea

--- Take a race's null areas down on every client that holds one.
function PaddockLive.lowerAreas(raceId)
    for pid in pairs(areas[raceId] or {}) do
        TriggerClientEvent("ncm:paddock.live.area", pid, { raceId = raceId, seconds = 0 })
    end
    areas[raceId] = nil
end

--- From liveWarnLeadSec before the lights, players near a start line get the HUD banner (NCM Pace draws it; a
--- notification goes too, for a client without the plugin): WARNING: IMPENDING RACE START / CLEAR THE AREA.
local function warn(t)
    local lead, radius = set("liveWarnLeadSec", 150), set("liveWarnRadiusM", 200)
    local people = positions()
    for _, race in pairs(PaddockRaces.byId) do
        local left = race.opensAt - t
        local lr = byRace[race.raceId]
        local skipped = lr and (lr.state == "skipped" or lr.state == "cancelled")
        if left > 0 and left <= lead and (race.state == "scheduled" or race.state == "priced") and not skipped then
            local route = PaddockWorld.route(race.routeId)
            if route then
                warned[race.raceId] = warned[race.raceId] or {}
                for pid, pos in pairs(people) do
                    pid = tonumber(pid)
                    -- an oval's "start" is the whole ring: anyone within `radius` of the roundabout is at it (L236)
                    local d = route.oval and math.max(0, L.dist({ x = route.oval.cx, y = route.oval.cy }, pos) - route.oval.radius)
                        or L.dist(route.start, pos)
                    if d <= radius and not warned[race.raceId][pid] then
                        warned[race.raceId][pid] = true
                        local detail = ("CLEAR THE AREA  ·  %s on %s"):format(PaddockWorld.seriesName(race.seriesId), PaddockWorld.routeName(race.routeId))
                        -- the banner reaches 0 exactly when the cars go: the window's opening (modelGoAt, L247), by
                        -- the clock NOW. Not `left + liveCountdownSec`: that was the retired grid run's 5 s countdown
                        -- after the opening, and `t` is taken at the start of the scheduler pass, seconds of database
                        -- work earlier -- cars went ~10 s before the banner cleared (owner, 2026-10-01).
                        TriggerClientEvent("ncm:paddock.live.warn", pid, { title = "WARNING: IMPENDING RACE START", detail = detail,
                            seconds = math.max(0, math.floor(race.opensAt * 1000 - nowMs()) / 1000) })
                        notify(pid, route.oval and "Oval race about to start on this roundabout. Clear the road."
                            or "Impending race start: the grid spawns here. Clear the area.", 8000)
                        raiseArea(race, pid, t)
                    end
                end
            end
        end
    end
    for id in pairs(warned) do
        local race = PaddockRaces.byId[id]
        if not race or race.opensAt < t - 600 then warned[id] = nil end
    end
    for id in pairs(areas) do
        local race = PaddockRaces.byId[id]
        if not race or race.opensAt < t - 3600 then areas[id] = nil end
    end
end
PaddockLive.warn = warn

-- --------------------------------------------------------------------------------------------------------- tick

local function running()
    local n = 0
    for _, lr in pairs(byRace) do if PaddockLive.holds(lr.raceId) then n = n + 1 end end
    return n
end

--- One pass from the main scheduler: stage the next race that is due, start what is staged. Bounded.
function PaddockLive.tick(t)
    local mode = set("liveMode", "watched")
    if mode ~= "off" then pcall(warn, t) end
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
            -- an oval is never a grid street run: it runs on the continuous model and goes physical in the bubble
            -- round whoever is at the roundabout (L230; KB-223 -- four oval grid runs never turned a wheel). Nor, since
            -- L247, is a street route with a road line: the grid run kept twelve driven cars alive however far from the
            -- host they got, and its CTDs (KB-238) came as they crossed the edge of the host's streaming.
            if not byRace[race.raceId] and not PaddockLive.onBubble(race.routeId) and (race.state == "scheduled" or race.state == "priced")
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
                -- the host is whoever is nearest THE GRID, and only within liveHostGridM of it: the cars spawn there and a
                -- client only has a car in its game within streaming range. Near the route's far end is not near enough
                -- (20:24, KB-242: the host was on the line, 0 of 12 cars ever reached its game, the LIVE tab showed twelve
                -- parked cars for three minutes). Nobody that close: the race is the sim's, and LIVE shows the sim.
                local route = PaddockWorld.route(due.routeId)
                local gridM = set("liveHostGridM", 250)
                for _, wch in ipairs(watchers(due.routeId)) do
                    local d = route and L.dist(route.start, wch.pos) or math.huge
                    if d <= gridM and (not host or d < host.gridD) then host = wch; host.gridD = d end
                end
                if not host then byRace[due.raceId] = { raceId = due.raceId, state = "skipped", reason = "nobody near the grid" } return end
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

-- The host's client says which cars actually reached its game before it fed Pace (client/live.lua). A car that never
-- did can never be driven: it is taken off the grid and out of the classification at once. Fewer than half: the street
-- run is called off now, not three minutes later by the stall rule, and the race is the sim's (KB-242).
RegisterNetEvent("ncm:paddock.live.mapped", function(msg)
    local pid = tonumber(source) or 0
    if type(msg) ~= "table" then return end
    local lr = byRace[tostring(msg.raceId or "")]
    if not lr or lr.pid ~= pid or (lr.state ~= "staging" and lr.state ~= "running") then return end
    local got = {}
    for _, v in ipairs(type(msg.mapped) == "table" and msg.mapped or {}) do got[tonumber(v) or -1] = true end
    local n = 0
    for _, c in ipairs(lr.cars) do if got[c.vehicleId] then n = n + 1 end end
    log("%s: %d of %d cars reached the host's game", lr.raceId, n, #lr.cars)
    if n < math.max(2, math.ceil(#lr.cars / 2)) then
        return cancel(lr, ("only %d of %d cars reached the host's game; the sim runs it"):format(n, #lr.cars))
    end
    lr.out = lr.out or {}
    for _, c in ipairs(lr.cars) do
        if not got[c.vehicleId] then
            lr.out[c.personId] = "not_streamed"
            byVehicle[c.vehicleId] = nil
            pcall(Open77.vehicles.ai.removeDriver, c.vehicleId)
            pcall(Open77.vehicles.remove, c.vehicleId)
            if c.npcId then pcall(Open77.npcs.remove, c.npcId) end
            log("%s: %s never reached the host's game: off the grid, out of the classification", lr.raceId, c.personId)
        end
    end
end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    PaddockLive.paceClients[tonumber(playerId) or 0] = nil
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    for _, lr in pairs(byRace) do removeCars(lr) end
end)
