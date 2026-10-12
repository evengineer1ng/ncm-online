-- ncm_paddock / server / bubble -- the physical bubble around players on a continuous race (L228, L229).
--
-- Every running Paddock race has a continuous model (`paddock.racestate`, built at the window's opening). A client
-- only simulates an AI car within a few hundred metres of it (probe v1, L229), so the race cannot be physical
-- everywhere; it does not have to be. Near a player it is:
--
--   in     a model car that is racing and comes within `bubbleInM` of a player is spawned exactly where the model says
--          it is, facing along the line, and driven along the rest of the line at its own sim pace
--   race   while physical it is timed from its canonical position, re-sent when stuck and put back on the road when
--          stuck longer (the same perseverance as a street race)
--   out    once it is further than `bubbleOutM` from every player, its real distance and time become an ANCHOR in the
--          model: from there it runs at its own pace again, carrying whatever it lost or gained. Its physical stretch is
--          recorded. A car that stays stuck past `liveRetireSec` is anchored as stopped (out of the race).
--
-- At the close (races.lua), if any car of the race ever drove physically, the classification comes from the model with
-- every anchor applied: provenance `physical` when every car drove its whole line, else `mixed`. The close waits while a
-- bubble car is still on the road or the model says someone has yet to finish.
--
-- Races run as a whole street race (a player at the start at staging, live.lua) are left alone here.
PaddockBubble = { byRace = {}, stats = { spawned = 0, handedBack = 0, refused = 0, stopped = 0 } }

local U = PaddockUtil
local log = U.logger("bubble")
local L = NcmCore.get("paddock.live")
local R = NcmCore.get("paddock.racestate")
local Incidents = NcmCore.get("competition.incidents")
local Ovals = NcmCore.get("data.ovals")
local Hash = NcmCore.get("vocabulary.hash")

local stats = PaddockBubble.stats
local byVehicle = {}                  -- vehicleId -> { raceId, id }
local function set(k, d) return PaddockSettings.get(k, d) end

local function nowMs() return math.floor((Open77.time.unix() or 0) * 1000) end
local DRIVER_RECORDS = { m = { "Character.WorkerMale", "Character.YoungsterMale", "Character.AsianMale" },
    f = { "Character.YoungsterFemale", "Character.AsianFemale" } }

local function state(raceId)
    local b = PaddockBubble.byRace[raceId]
    if not b then b = { cars = {}, touched = false }; PaddockBubble.byRace[raceId] = b end
    return b
end

--- Did any car of this race drive physically?
function PaddockBubble.touched(raceId)
    local b = PaddockBubble.byRace[raceId]
    return b ~= nil and b.touched
end

--- Is a race's close held: a bubble car still on the road, or the model says someone has yet to finish?
function PaddockBubble.holds(race, t)
    local b = PaddockBubble.byRace[race.raceId]
    if not b or not b.touched then return false end
    if next(b.cars) then return true end
    if not race.model then return false end
    local tMs = (t - race.modelGoAt) * 1000
    for _, id in ipairs(race.model.order) do
        local fin = R.finishAt(race.model, id)
        if fin and fin > tMs then return true end
    end
    return false
end

local function splitsOf(race, id)
    for _, e in ipairs((race.result and race.result.entrants) or {}) do if e.id == id then return e.splits end end
    return nil
end

local function speedPlanFor(race, id)
    if not race.model then return nil end
    local plan = L.speedPlan(race.model.path.points, race.model.lengthM, splitsOf(race, id), race.model.segments, L.PLATFORM_MAX_MPS)
    local route = PaddockWorld.route(race.routeId)
    if route and route.oval then
        local factor = math.max(2.25, tonumber(set("liveOvalSpeedCeilingFactor", 2.25)) or 2.25)
        for i, mps in ipairs(plan) do
            plan[i] = math.floor(math.min(L.PLATFORM_MAX_MPS, mps * factor) * 10 + 0.5) / 10
        end
    end
    return plan
end

local function paceSpeedFactor(race)
    local route = PaddockWorld.route(race.routeId)
    return (route and route.oval) and math.max(2.25, tonumber(set("liveOvalSpeedCeilingFactor", 2.25)) or 2.25)
        or set("bubblePaceSpeedFactor", 1.5)
end

--- The line index a distance falls in: the first point at or past `d`. By DISTANCE, never by nearest point: on an
--- oval every lap passes the same place, and "nearest" is always lap 1 (KB-223).
local function indexAt(model, d)
    local cum = model.cum
    for i = 1, #cum do if cum[i] >= d then return i end end
    return #cum
end

local WINDOW = 63                     -- followRoute takes 1..64 points; one more is the runoff past the finish

-- --------------------------------------------------------------------------------------------------- Pace driving
-- KB-223: the platform's AI never drove a bubble car (probe v1, L229; 03:54 and 04:06 Corpo). NCM Pace is what has
-- driven every Paddock car that raced (L234, L235), so a bubble car near a player with Pace is Pace's: the line goes
-- to that player's Pace once per race as a DYNAMIC plan (Pace 0.4.0), each car joins with `car.add` from the point it
-- is set down at, and leaves with `car.remove`. Pace re-commands a stalled car itself (SP's stall rule); the server
-- only puts back on the road a car that has made no way for liveResetSec.
local PLAN_PART = 96                  -- line points per network part (~4 KB): the network drops large events (KB-223)

-- ------------------------------------------------------------------------------------------------ the formation
local FORMATION_MS = 30000            -- the first 30 s of a race: cars come in at their grid slots
local SPAWN_CLEAR_M = 7               -- never set a car down within this of another physical car

--- A car's grid slot for the start, or nil once the race is under way. An oval's slots run round the ring behind the
--- line (paddock.live.ovalSlots, L236); a street line's are SP's own grid (gridSlots, L232). Grid order is the frozen
--- grid's.
local slotsFor = {}
local function formationSlot(race, id, tMs, p)
    if tMs > FORMATION_MS or (p.d or 0) > 250 then return nil end
    local route = PaddockWorld.route(race.routeId)
    if not route then return nil end
    local order = (race.frozen and race.frozen.grid) or race.model.order
    local k
    for i, x in ipairs(order) do if x == id then k = i break end end
    if not k then return nil end
    local slots = slotsFor[race.raceId]
    if not slots then
        local profile = NcmCore.get("data.grid_profiles").forRoot(race.routeId)
        if route.oval then
            local ring = PaddockLive.pathFor(race.routeId)
            slots = (ring and ring.ovalBehind and L.roadSlots(ring.ovalBehind, #order, profile))
                or L.ovalSlots(route.oval, #order, profile)
        else
            -- L250: the lane-based grid (tools/bake-grids.py, course.grid_solver) -- every slot on a lane centreline,
            -- 2-4 wide, never past the end of the road behind the start. A short grid leaves the cars it cannot place
            -- to come in from the model once the race is under way; a leg with no bake falls back to the old grid.
            local note
            slots, note = PaddockLive.gridSlots(route, #order, profile)
            if note ~= "baked" and note ~= "override" then
                log("%s: grid %s for %s (%d of %d slots)", race.raceId, tostring(note), tostring(race.routeId), slots and #slots or 0, #order)
            end
        end
        slotsFor[race.raceId] = slots
    end
    local s = slots and slots[k]
    if not s then return nil end
    return { x = s.x, y = s.y, z = s.z or route.start.z, yaw = s.yaw, d = 0, index = 2, slot = k }
end

local function paceOf(pid)
    local p = pid and PaddockLive.paceClients[pid]
    return (p and p.ok) and pid or nil
end

--- A street race's cars race their legs' splines on the bubble, which needs Pace 0.8.1 (`legs` on a dynamic plan).
--- An older Pace drops the legs without a word and drives the retired drive-to-point command (01:36, 2026-10-01: the
--- field crawled or never moved) -- so it brings no street car in. Race splines, or nothing (L245).
local PACE_STREET = { 0, 8, 1 }
local PACE_OVAL = { 0, 8, 2 }
local tooOld = {}
local function paceAtLeast(pid, minimum, kind)
    local p = pid and PaddockLive.paceClients[pid]
    if not (p and p.ok) then return nil end
    local v = {}
    for n in tostring(p.version or ""):gmatch("%d+") do v[#v + 1] = tonumber(n) end
    for i = 1, 3 do
        local a, b = v[i] or 0, minimum[i]
        if a > b then return pid end
        if a < b then
            local key = tostring(pid) .. kind
            if not tooOld[key] then
                tooOld[key] = true
                log("player %d's NCM Pace is %s; %s races on the bubble need %d.%d.%d", pid, tostring(p.version), kind,
                    minimum[1], minimum[2], minimum[3])
            end
            return nil
        end
    end
    return pid
end
local function paceForStreet(pid) return paceAtLeast(pid, PACE_STREET, "street") end
local function paceForOval(pid) return paceAtLeast(pid, PACE_OVAL, "oval") end

local function r2(v) return math.floor((v or 0) * 100 + 0.5) / 100 end

-- ------------------------------------------------------------------------------------------ the owner's marks
-- The plan's marks repeat lap after lap for progress. Pace 0.8.2 steers an oval on one baked closed spline;
-- PaddockLive.pathFor supplies that same line to the model and bubble, so none of the marks steers a car.
local function markPlan(route)
    local out = { route.start }
    for _, m in ipairs(route.intermediate or {}) do out[#out + 1] = m end
    out[#out + 1] = route.finish
    return out
end

--- The 1-based index in markPlan of the next node ahead of a car `d` metres along a street race's road line (L247):
--- the end of the leg it is on, so Pace races it on that leg's spline.
local function nodeIndexAt(path, d)
    local nd = path.nodeD or {}
    for k = 2, #nd do if nd[k] > d then return k end end
    return math.max(2, #nd)
end

--- The 1-based index in markPlan of the next mark ahead of a car `d` metres into an oval.
local function markIndexAt(race, route, d)
    local path = (race.model and race.model.path) or PaddockLive.pathFor(race.routeId)
    if path and path.nodeD then return nodeIndexAt(path, d or 0) end
    local g = route.oval
    local n = #g.loop
    local laps = g.laps or 1
    local lapLen = ((race.model and race.model.lengthM) or route.distanceM or 1) / laps
    local lap = math.max(0, math.min(laps - 1, math.floor((d or 0) / lapLen)))
    local t = (((d or 0) - lap * lapLen) / lapLen) * 2 * math.pi
    local passed = 0
    for k = 2, n do
        local p = g.loop[k]
        local a = ((math.atan(p.y - g.cy, p.x - g.cx) - g.startAngle) * g.sign) % (2 * math.pi)
        if a <= t then passed = passed + 1 end
    end
    return math.min(1 + laps * n, 2 + lap * n + passed)
end

local function sendPlan(race, b, pid)
    b.planned = b.planned or {}
    if b.planned[pid] then return end
    b.planned[pid] = true
    -- before the lights (the pre-grid) there is no model yet: the route's own line, held until the window opens
    local path = race.model and race.model.path or PaddockLive.pathFor(race.routeId)
    local route = PaddockWorld.route(race.routeId)
    local ovalRoute = route and route.oval and route or nil
    -- a street race on its road line (L247): Pace's plan is the route's own nodes with the race spline for each leg,
    -- exactly the grid run's -- the road line is the model's, for setting cars down and handing them back
    local street = route and not ovalRoute and path.source == "road"
    local pts = (ovalRoute or street) and markPlan(route) or path.points
    local line = {}
    for i, p in ipairs(pts) do line[i] = { x = r2(p.x), y = r2(p.y), z = r2(p.z) } end
    local function gate(a, c)
        local dx, dy = c.x - a.x, c.y - a.y
        local len = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
        return { x = r2(a.x), y = r2(a.y), z = r2(a.z), dx = math.floor(dx / len * 1e4 + 0.5) / 1e4, dy = math.floor(dy / len * 1e4 + 0.5) / 1e4 }
    end
    local finish = gate(pts[#pts], pts[#pts])
    local fdx, fdy = pts[#pts].x - pts[#pts - 1].x, pts[#pts].y - pts[#pts - 1].y
    local flen = math.max(1e-6, math.sqrt(fdx * fdx + fdy * fdy))
    finish.dx, finish.dy = math.floor(fdx / flen * 1e4 + 0.5) / 1e4, math.floor(fdy / flen * 1e4 + 0.5) / 1e4
    local parts = math.max(1, math.ceil(#line / PLAN_PART))
    for k = 1, parts do
        local msg = { raceId = race.raceId, part = k, parts = parts, points = {} }
        for i = (k - 1) * PLAN_PART + 1, math.min(k * PLAN_PART, #line) do msg.points[#msg.points + 1] = line[i] end
        if k == 1 then
            msg.gates = { gate(pts[1], pts[2]), finish }
            -- positive before the lights: Pace holds every car on its slot until then (mode 0), as a street grid
            msg.goInMs = math.floor((race.modelGoAt or race.opensAt) * 1000 - nowMs())
            msg.launch = L.launchProfile(NcmCore.get("data.grid_profiles").forRoot(race.routeId))
            msg.advanceM = (path.source == "ghost") and 40 or 15
            if street then msg.legs = PaddockLive.legsFor(route) end
            if ovalRoute then msg.loopSpline = ("$/mod/ncm_pace/#leg_%s__loop"):format(race.routeId) end
            msg.lookaheadM = 150
            msg.reaimFrac = 0.9
            if ovalRoute then
                -- These only advance the progress cursor; the engine racer follows loopSpline for the whole run.
                msg.lookaheadM = 0
                msg.advanceM = 10
            end
        end
        TriggerClientEvent("ncm:paddock.bubble.plan", pid, msg)
    end
    log("%s: line sent to player %d's Pace: %d points in %d part(s)", race.raceId, pid, #line, parts)
end

local function paceCar(race, car, op, from)
    if not car.pace then return end
    -- the car's own sim pace (its average leg ceiling), or before the lights the race's estimated pace; times
    -- bubblePaceSpeedFactor: a CEILING, the planner brakes for the corners itself. The bare average (~17 m/s at
    -- Corpo) drove round the roundabout visibly slowly (05:08, owner).
    local speed = 0
    for _, v in ipairs(car.plan or {}) do speed = speed + v end
    speed = (#(car.plan or {}) > 0) and (speed / #car.plan) or (race.provisionalMps or 20)
    speed = math.min(set("livePaceMaxMps", 90), speed * paceSpeedFactor(race))
    speed = math.floor(speed * 10 + 0.5) / 10
    if op == "add" then car.sentSpeed = speed end
    -- a staggered start (2026-10-02, twelve cars at once piled up): a grid car is released by row, front row first,
    -- bubbleStartGapMs apart (0 = all at the lights); two cars a row
    local releaseMs
    if op == "add" and car.gridSlot and not (race.modelGoAt and nowMs() > race.modelGoAt * 1000) then
        releaseMs = (math.ceil(car.gridSlot / 2) - 1) * set("bubbleStartGapMs", 500)
    end
    -- a car joining mid-race starts at its model speed (Pace 0.8.8 pre-roll; 0 = standing start)
    local startMps = (op == "add" and not car.gridSlot and set("bubbleRollingRestream", true)) and car.startMps or nil
    TriggerClientEvent("ncm:paddock.bubble.car", car.pace, { raceId = race.raceId, op = op, vehicleId = car.vid,
        from = from and math.max(1, from - 1) or nil, speed = speed, releaseMs = releaseMs,
        startMps = startMps and math.floor(startMps * 10 + 0.5) / 10 or nil })
end

--- THE SIM, MODELLED (owner, 05:53: "the sim underneath it isn't being modelled"), WITHOUT ITS TRAFFIC (owner,
--- 06:25: "they catch a driver, with space, and then back off"). A Pace car's ceiling is the driver's CLEAN sim pace
--- -- driver, car, form, conditions: the sim's per-car segment time before anyone is held up -- times
--- bubblePaceSpeedFactor. It is NOT the car's splits: paddock.sim gates overtakes (a lost duel sets the car 0.25 s
--- behind the one ahead, and dirty air slows a follower), so a ceiling from splits made every physical car back off
--- to the sim's held-up pace exactly where the sim had it stuck. On the street the drivers settle passes themselves.
local function cleanPace(race, id)
    for _, e in ipairs((race.result and race.result.entrants) or {}) do
        if e.id == id and tonumber(e.segSec) and e.segSec > 0 and race.model then
            return (race.model.lengthM / math.max(1, race.model.segments or 1)) / e.segSec
        end
    end
    return nil
end

local function paceFollowSim(race, car, d, tMs)
    if not car.pace or car.simPaceSent then return end
    local mps = cleanPace(race, car.id)
    if not mps then return end
    local factor = paceSpeedFactor(race)
    local v = math.floor(math.min(set("livePaceMaxMps", 90), mps * factor) * 10 + 0.5) / 10
    car.simPaceSent, car.sentSpeed = true, v
    TriggerClientEvent("ncm:paddock.bubble.car", car.pace, { raceId = race.raceId, op = "set", vehicleId = car.vid, speed = v })
    -- NOTE: Pace's racing command (mode 3, every street and oval car) has no speed input and ignores this value;
    -- the racer's pace is the vehicle record's race profile (racers.yaml). Logged only as the sim's reference.
    log("%s: %s sim reference pace %.1f m/s (sim %.1f x %.2f; not applied to the racing command)", race.raceId, car.id, v, mps, factor)
end

-- send a physical car along the line from path point `from`: the next WINDOW points AHEAD of it (a long line --
-- a 25-lap oval is 1,600 points -- is re-sent as the car nears the end of its window, bubble tick)
local function drive(race, car, from)
    if car.pace then return true end          -- Pace drives it and re-commands it itself
    local pts = race.model.path.points
    from = math.max(2, math.min(#pts, from))
    local route = {}
    for i = from, math.min(#pts, from + WINDOW - 1) do route[#route + 1] = pts[i] end
    local last = from + #route - 1
    if last >= #pts then
        -- the finish is in this window: carry on past it so the line is crossed, not parked on
        local a, b = pts[#pts - 1], pts[#pts]
        local len = math.max(1, L.dist(a, b))
        route[#route + 1] = { x = b.x + (b.x - a.x) / len * 80, y = b.y + (b.y - a.y) / len * 80, z = b.z or 0 }
    end
    car.base, car.windowEnd = from, last
    local okF, st, why = pcall(Open77.vehicles.ai.followRoute, car.vid, { points = route,
        speed = (PaddockSlip and PaddockSlip.leg(car, car.plan[math.max(1, car.base)] or car.plan[#car.plan] or 20)) or car.plan[math.max(1, car.base)] or car.plan[#car.plan] or 20,
        behavior = "aggressive", arrivalRadius = 12, timeoutMilliseconds = 900000 })
    if not okF or not st then log("%s: followRoute for %s refused: %s", race.raceId, car.id, tostring(why or st)) return false end
    return true
end

--- Seat a race car's driver: an invulnerable NPC in the driver's seat through the platform's attachDriver. A car the
--- platform will not give a driver gets the controller alone (the NPC is removed). Returns ok, npcId.
local function seatDriver(vid, person, id, at, yaw, bucket)
    local okN, npc = pcall(Open77.npcs.create, { record = Hash.pick(DRIVER_RECORDS[(person and person.gender == "f") and "f" or "m"], "driver", id),
        position = at, yaw = yaw, bucket = bucket or 0, aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or nil,
        damagePolicy = Open77.npcs.damage and Open77.npcs.damage.invulnerable or nil, despawnWhenUnobserved = false, persistent = false })
    local okA, st = pcall(Open77.vehicles.ai.attachDriver, vid, (okN and npc) and { npcId = npc } or nil)
    if (not okA or not st) and okN and npc then pcall(Open77.npcs.remove, npc); npc = nil; okA, st = pcall(Open77.vehicles.ai.attachDriver, vid, nil) end
    if not okA or not st then return false end
    return true, (okN and npc) or nil
end

local function remove(car, race)
    if race then paceCar(race, car, "remove") end
    -- every way off the road leaves the model where the car really was (a live car is otherwise frozen)
    local mc = race and race.model and race.model.cars[car.id]
    if mc and mc.live then R.anchor(race.model, car.id, mc.live.t, mc.live.d) end
    byVehicle[car.vid] = nil
    if PaddockSlip then PaddockSlip.detach(car) end
    if PaddockHack then pcall(PaddockHack.carRemoved, race, car.id, car.vid) end
    pcall(Open77.vehicles.ai.removeDriver, car.vid)
    pcall(Open77.vehicles.remove, car.vid)
    if car.npc then pcall(Open77.npcs.remove, car.npc) end
end

local function spawn(race, id, p, tMs, bucket, pid)
    local w = PaddockStore.world
    local person = w.people[id]
    -- from just above the line first: a ray from 30 m up lands on a deck over the road (Corpo Circle, KB-223)
    local zOk, z = pcall(Open77.world.groundZ, { x = p.x, y = p.y }, { radius = 400, fromZ = (p.z or 0) + 4, timeout = 1500, cache = true })
    if not (zOk and type(z) == "number") then
        zOk, z = pcall(Open77.world.groundZ, { x = p.x, y = p.y }, { radius = 400, fromZ = (p.z or 0) + 30, timeout = 1500, cache = true })
    end
    local grounded = zOk and type(z) == "number"
    z = grounded and z or (p.z or 0)
    local raceRoute = PaddockWorld.route(race.routeId)
    local ovalRace = raceRoute and raceRoute.oval ~= nil
    -- Bubble cars are the ones physically beside the player: NCM Pace's racer clone, street and oval (KB-287).
    -- L298: the car this NPC actually owns (its model, in the Pace variant its installed parts compose to); before
    -- the car exists, the old team-hashed record
    local assetId = race.frozen and race.frozen.carOf and race.frozen.carOf[id]
    local record = PaddockLive.recordFor(w.orgs[(person and person.orgId) or ""], race.tier, ovalRace, person, race.seriesId, assetId)
    race.cloneLogged = race.cloneLogged or {}
    if not race.cloneLogged[id] then race.cloneLogged[id] = true; log("%s: bubble %s spawning racer clone %s", race.raceId, id, record) end
    local okV, vid, why = pcall(Open77.vehicles.create, { record = record,
        position = { x = p.x, y = p.y, z = z + 0.8 }, yaw = p.yaw, bucket = bucket or 0 })
    if not okV or not vid then stats.refused = stats.refused + 1; log("%s: %s refused: %s", race.raceId, id, tostring(why or vid)) return nil end
    if assetId and PaddockCars then
        local condition = PaddockCars.condition(assetId)
        if condition and (tonumber(condition.health) or 1) < 1 then pcall(Open77.vehicles.setDamage, vid, condition) end
    end
    local pace = (raceRoute and raceRoute.oval) and paceForOval(pid) or paceOf(pid)
    -- KB-238 (02:06, 00:46, 00:54): every new car goes through the engine's own physics cycle in the host's game --
    -- observed ~1.0 s after it appears, unobserved ~0.5 s later -- and the NPC's seat mount landed inside that cycle every
    -- time; each crash followed within a second of a mount there. A Pace car comes up EMPTY: the host's client says when
    -- it has stood in its game for bubbleSeatDelayMs, and only then is the driver seated (seatDriver) and Pace takes it.
    local npc
    if not pace then
        local okS
        okS, npc = seatDriver(vid, person, id, { x = p.x, y = p.y, z = z + 0.8 }, p.yaw, bucket)
        if not okS then pcall(Open77.vehicles.remove, vid); stats.refused = stats.refused + 1 return nil end
    end
    local car = { id = id, vid = vid, npc = npc, seated = not pace, spawnT = tMs, spawnD = p.d, lastD = p.d, bucket = bucket, yaw = p.yaw,
        gridSlot = tonumber(p.slot),
        anchorPos = { x = p.x, y = p.y }, progressT = tMs, recoveries = 0, resets = 0, lastHelpT = -1e9, lastResetT = -1e9,
        -- no model before the lights (the pre-grid): the plan comes when the race opens (tick)
        plan = speedPlanFor(race, id) }
    byVehicle[vid] = { raceId = race.raceId, id = id }
    car.pace = pace
    if PaddockSlip then PaddockSlip.attach(car, vid, id) end     -- L356: the wake, and an SL-1 if the team runs one
    if PaddockHack then pcall(PaddockHack.carSpawned, race, id, vid) end
    local sent
    if car.pace then
        sendPlan(race, state(race.raceId), car.pace)
        local route = PaddockWorld.route(race.routeId)
        local path = race.model and race.model.path or PaddockLive.pathFor(race.routeId)
        local from = p.index or 2
        if route and route.oval then from = markIndexAt(race, route, p.d or 0)
        elseif path and path.source == "road" then from = nodeIndexAt(path, p.d or 0) end
        -- Pace takes it once its driver is in (PaddockBubble.seated); until then the host's client is watching for it
        car.addFrom, car.seatAskedMs = from, nowMs()
        TriggerClientEvent("ncm:paddock.bubble.car", car.pace, { raceId = race.raceId, op = "seat", vehicleId = vid,
            delayMs = set("bubbleSeatDelayMs", 0) })
        sent = true
    else
        sent = drive(race, car, (p.index or 2))
    end
    stats.spawned = stats.spawned + 1
    log("%s: %s in at %.0f m (point %d of %d%s), vehicle %s, driver %s, %s, placed at %.1f, %.1f, %.1f (ground %s)",
        race.raceId, id, p.d or 0, p.index or 2, race.model and #race.model.path.points or #(PaddockLive.pathFor(race.routeId) or { points = {} }).points, car.pace and "" or (", window to " .. tostring(car.windowEnd)),
        tostring(vid), tostring(car.npc), car.pace and ("Pace on player " .. car.pace) or ("platform AI " .. (sent and "sent" or "REFUSED")),
        p.x, p.y, z + 0.8, grounded and "found" or ("not found, line z " .. tostring(p.z)))
    -- KB-223: where the platform says the car actually is, a moment later (the owner saw no car where one was placed)
    CreateThread(function()
        Wait(1500)
        local okA, at = pcall(Open77.vehicles.getPosition, vid)
        if okA and type(at) == "table" then
            log("%s: %s after 1.5 s at %.1f, %.1f, %.1f (%.0f m from where it was placed)", race.raceId, id, at.x, at.y, at.z or 0,
                L.dist(at, p))
        else
            log("%s: %s after 1.5 s: no position (%s)", race.raceId, id, tostring(at))
        end
    end)
    return car
end

local function handBack(race, b, car, tMs, stopped, why)
    local okP, pos = pcall(Open77.vehicles.getPosition, car.vid)
    local d = car.lastD
    if okP and type(pos) == "table" then d = R.project(race.model, pos, (car.lastD or 0) - 150, (car.lastD or 0) + 150) end
    local physicalFinishMs = why == "finished" and tMs or nil
    if physicalFinishMs then d = math.max(d or 0, race.model.lengthM) end
    -- the stretch first, so the anchor can carry the pace the car was measured driving (truth rules, racestate 0.2.0).
    -- Measured from when the car was first UNDER WAY, not from the spawn: a set-down car stands while its driver is seated
    -- (KB-238), and counting that halved every measured pace (every 15:45 hand-back logged the 0.50 floor).
    R.markPhysical(race.model, car.id, car.movingD or car.spawnD or 0, d, car.movingT or car.spawnT, tMs)
    local rate = R.observedRate(race.model, car.id, 600) or R.fieldRate(race.model)
    -- L296: a car still racing (not wrecked, not stuck) adds its at-speed stretch to the race's physical pace
    if not stopped and car.paceT and d and tMs > car.paceT and d - car.paceD >= 300 then
        race.paceObs = race.paceObs or { m = 0, ms = 0 }
        race.paceObs.m, race.paceObs.ms = race.paceObs.m + (d - car.paceD), race.paceObs.ms + (tMs - car.paceT)
    end
    R.anchor(race.model, car.id, tMs, d, stopped, physicalFinishMs, rate)
    remove(car, race)
    b.cars[car.id] = nil
    if stopped then stats.stopped = stats.stopped + 1 else stats.handedBack = stats.handedBack + 1 end
    log("%s: %s handed back at %.0f m (%s)%s", race.raceId, car.id, d, why, rate and (" at %.2fx its sim pace"):format(rate) or "")
    if car.pace then PaddockBubble.streamline(car.pace, "%s %s handed back (%s)", race.raceId, car.id, why) end
end

--- NPC incidents (owner, 2026-10-02: "npcs ... should be handed out penalties as well"). A physical car's vehicle health
--- is read every pass; a drop is scored by the SAME scorer and ledger as a human's (`competition.incidents` damage
--- bands, escalation, one incident per crash episode), and the seconds go on the car in the model -- the provisional
--- order and the classification both carry them. Health is normalised to the car's own best reading; the damage a car
--- arrives with is never charged; a destroyed car is out (persevere), not penalised.
local function npcIncident(race, car, id, pos, tMs)
    local okH, hp = pcall(Open77.vehicles.getHealth, car.vid)
    if not okH or type(hp) ~= "number" or hp <= 0 then return end
    car.maxHp = math.max(car.maxHp or 0, hp)
    local cur = { health = hp / car.maxHp }
    local prev = car.hpSnap
    car.hpSnap = cur
    -- L298: the damage this car took is a repair bill at the race's close (races.lua resolve)
    race.carDamage = race.carDamage or {}
    local dmg = race.carDamage[id] or { frac = 0 }
    dmg.frac = math.max(dmg.frac, 1 - cur.health)
    race.carDamage[id] = dmg
    if not prev or (prev.health - cur.health) < 0.002 then return end
    local rec = Incidents.damage(prev, cur, car.lastSpeed or 0, pos, tMs / 1000)
    if not rec then return end
    race.npcLedger = race.npcLedger or Incidents.Ledger.new()
    local got = race.npcLedger:add(id, rec, { baseSec = set("incidentBaseSec", 2) })
    if got and (got.seconds or 0) > 0 then
        R.penalize(race.model, id, math.floor(got.seconds * 1000 + 0.5))
        log("%s: NPC INCIDENT %s band=%d +%.1fs (health %.0f%% -> %.0f%%) total=%.1fs (#%d)", race.raceId, id, got.band, got.seconds,
            prev.health * 100, cur.health * 100, race.npcLedger:sum(id), race.npcLedger:count(id))
    end
end

-- keep a stuck physical car racing; anchor it as out only after liveRetireSec
local function persevere(race, b, car, pos, tMs)
    local idle = tMs - car.progressT
    if idle > set("liveRetireSec", 180) * 1000 then return handBack(race, b, car, tMs, true, "stuck for good") end
    local resetMs = set("liveResetSec", 20) * 1000
    -- A car the engine has destroyed is out of the race -- EVERY car, Pace's or not (2026-10-08: only Pace cars were
    -- checked, so a destroyed platform-AI car was reset and re-sent for 180 s). The destruction is a physical incident
    -- whatever caused it (a crash, a chain explosion, a quickhack): Race Week and the tape hear it here.
    local okH, health = pcall(Open77.vehicles.getHealth, car.vid)
    if okH and type(health) == "number" and health <= 0 then
        race.carDamage = race.carDamage or {}
        race.carDamage[car.id] = { frac = 1, wrecked = true }      -- L298: a wreck is a repair bill and a tow
        if PaddockHack then pcall(PaddockHack.destroyed, race, car.id, car.vid, pos) end
        return handBack(race, b, car, tMs, true, "wrecked")
    end
    -- A Pace car is Pace's: its stall rule kicks it (SP's), and a server reset only drags it about -- at 05:22 nine
    -- wrecks were moved 10 m BACK every 20 s for minutes.
    if car.pace then return end
    -- never on the grid (a car there is at 0 m, and "10 m back" put every stuck car on the one start point, on top of
    -- each other: 04:31 Corpo), and never onto another car
    local backD = math.max(0, (car.lastD or 0) - 10)
    local rp = R.pointAt(race.model, backD)
    local onGrid = (car.lastD or 0) < 30
    local blocked = false
    for _, other in pairs(b.cars) do
        if other ~= car and other.pos and L.dist(other.pos, rp) < SPAWN_CLEAR_M then blocked = true break end
    end
    if idle > resetMs and tMs - car.lastResetT > resetMs and (onGrid or blocked) then
        car.lastResetT = tMs
        log("%s: %s stuck %d s but not reset (%s); Pace keeps kicking it", race.raceId, car.id, math.floor(idle / 1000),
            onGrid and "still on the grid" or "another car is on that spot")
    elseif idle > resetMs and tMs - car.lastResetT > resetMs then
        -- back on the road just behind where it is ON ITS OWN LAP (by distance, KB-223), facing along the line
        if pcall(Open77.vehicles.setTransform, car.vid, { position = { x = rp.x, y = rp.y, z = (rp.z or 0) + 1.0 }, yaw = rp.yaw }) then
            drive(race, car, indexAt(race.model, backD) + 1)
        end
        car.resets, car.lastResetT, car.lastHelpT = car.resets + 1, tMs, tMs
        car.anchorPos = { x = rp.x, y = rp.y }
        log("%s: %s reset %d at %.0f m (stuck %d s)", race.raceId, car.id, car.resets, backD, math.floor(idle / 1000))
    elseif not car.pace and idle > set("liveRecoverSec", 8) * 1000 and tMs - car.lastHelpT > set("liveRecoverSec", 8) * 1000 then
        car.recoveries, car.lastHelpT = car.recoveries + 1, tMs
        drive(race, car, indexAt(race.model, car.lastD or 0) + 1)
        log("%s: %s re-sent %d at %.0f m (idle %d s)", race.raceId, car.id, car.recoveries, car.lastD or 0, math.floor(idle / 1000))
    end
end

-- ---------------------------------------------------------------------------------------------- corridors
-- The ambient population service (ncm_world) holds race corridors clear of ITS OWN traffic -- but only for league
-- calendar races and multiplayer sessions. It never knew a Paddock race existed, so it kept spawning traffic cars
-- (NPC driver + joinTraffic, one every ~12 s) into the roundabout during every oval (06:34, Westbrook). Publish the
-- Paddock races a player is near, within 5 minutes of their lights or running, with their line; ncm_world reads
-- GlobalState.ncmPaddockRaces exactly as it reads the league calendar. (The vanilla traffic the Pace null area
-- clears is a different system; this is only NCM's own ambient cars.)
local lastCorridors = 0
function PaddockBubble.publishCorridors(now, players)
    if now - lastCorridors < 5000 then return end
    lastCorridors = now
    local t = now / 1000
    local out, watch = {}, set("liveWatchRadiusM", 600)
    for _, race in pairs(PaddockRaces.byId) do
        local lead = race.opensAt - t
        local live = race.state == "running"
        if (live or ((race.state == "scheduled" or race.state == "priced") and lead <= 300 and lead > -60)) then
            local route = PaddockWorld.route(race.routeId)
            if route then
                local pts
                if route.oval then
                    pts = Ovals.ringLine(route.oval, 1, 30).points
                else
                    pts = { route.start }
                    for _, m in ipairs(route.intermediate or {}) do pts[#pts + 1] = m end
                    pts[#pts + 1] = route.finish
                end
                local near = false
                for _, pp in pairs(players) do
                    if L.distToPath(pts, pp) <= watch then near = true break end
                end
                if near then
                    local line = {}
                    for i, p in ipairs(pts) do line[i] = { x = r2(p.x), y = r2(p.y), z = r2(p.z) } end
                    out[#out + 1] = { id = race.raceId, routeId = race.routeId, startsAt = race.opensAt, live = live or nil, points = line }
                end
            end
        end
    end
    local sig = {}
    for _, e in ipairs(out) do sig[#sig + 1] = e.id .. (e.live and "L" or "") end
    local key = table.concat(sig, ",")
    if key ~= PaddockBubble.corridorKey then
        PaddockBubble.corridorKey = key
        GlobalState.ncmPaddockRaces = out
        log("corridors for ncm_world's ambient traffic: %s", key ~= "" and key or "none")
    end
end

-- KB-286: a player pulling away from the field. 2026-10-02 13:46: the owner was ahead; model cars were set down
-- 219-248 m behind them and handed back 1-3 s later at 300 m, over and over. A car is not set down where the gap to
-- the player is OPENING faster than the car's own model pace by `bubbleRecedeMarginMps`; a car the player is catching,
-- or one catching the player, still comes in. Velocity is each player's movement between passes.
local playerSeen = {}       -- pid -> { x, y, ms, v = { x, y } }
local function updateVelocities(players, now)
    for pid, pp in pairs(players) do
        local key = tostring(pid)
        local prev = playerSeen[key]
        local v = prev and prev.v or nil
        if prev and type(pp.x) == "number" then
            local dt = (now - prev.ms) / 1000
            if dt >= 0.2 and dt <= 5 then v = { x = (pp.x - prev.x) / dt, y = (pp.y - prev.y) / dt }
            elseif dt > 5 then v = nil end
        end
        if type(pp.x) == "number" then playerSeen[key] = { x = pp.x, y = pp.y, ms = now, v = v } end
    end
    for key in pairs(playerSeen) do
        if players[key] == nil and players[tonumber(key)] == nil then playerSeen[key] = nil end
    end
end

--- How fast the player is moving directly away from point p, and whether that outruns the car there.
local function recedingFrom(ppid, pp, p)
    local seen = playerSeen[tostring(ppid)]
    local v = seen and seen.v
    if not v then return false end
    local dx, dy = pp.x - p.x, pp.y - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return false end
    local away = (v.x * dx + v.y * dy) / dist
    local carMps = tonumber(p.speed) or 0
    return away > carMps + set("bubbleRecedeMarginMps", 2), away, carMps
end

--- One bubble pass over every running race. Bounded: at most `bubbleSpawnsPerPass` new cars per pass.
function PaddockBubble.tick()
    if not set("bubbleEnabled", true) or set("liveMode", "watched") == "off" then return end
    local okP, players = pcall(Open77.players.positions)
    players = (okP and type(players) == "table") and players or {}
    local inM, outM = set("bubbleInM", 250), set("bubbleOutM", 300)
    local now = nowMs()
    updateVelocities(players, now)
    pcall(PaddockBubble.publishCorridors, now, players)
    -- a car its Pace player's game never reported (never streamed in there, or the player left): it goes, still empty
    for raceId, b in pairs(PaddockBubble.byRace) do
        for id, car in pairs(b.cars) do
            if not car.seated and car.seatAskedMs and now - car.seatAskedMs > set("bubbleSeatTimeoutMs", 20000) then
                log("%s: %s never settled in player %s's game in %d s; removed before a driver was seated", raceId, id,
                    tostring(car.pace), math.floor((now - car.seatAskedMs) / 1000))
                remove(car, PaddockRaces.byId[raceId]); b.cars[id] = nil
            end
        end
    end
    local spawns, cap = 0, set("bubbleSpawnsPerPass", 3)
    if PaddockHack then pcall(PaddockHack.prune) end
    for _, race in pairs(PaddockRaces.byId) do
        local lr = PaddockLive.byRace[race.raceId]
        local street = lr and (lr.state == "staging" or lr.state == "running" or lr.state == "finished")
        -- only on a real road line: without a recorded human line the model's "line" is a straight segment from start
        -- to finish, and a car set down on it would stand in a building (L232)
        -- an oval's line is its ring (KB-223), a road line like a ghost's
        local src = race.model and race.model.path.source
        local lead = race.opensAt - now / 1000
        if (race.state == "scheduled" or race.state == "priced") and lead > 0 and lead <= set("bubbleGridLeadSec", 30)
            and PaddockLive.onBubble(race.routeId) then
            -- THE PRE-GRID (owner, 05:08: "spawn the grid 30 seconds earlier, needs some build up"): a player with Pace near
            -- an oval's start sees the whole frozen grid come up on SP's slots and wait there; Pace holds every car until
            -- the lights (its goInMs is still ahead), then SP's launch release. Without Pace no car is held, so none comes.
            local b = state(race.raceId)
            local route = PaddockWorld.route(race.routeId)
            if not race.frozen then PaddockRaces.freeze(race) end
            if not race.provisionalMps and route then
                local okS, _, _, base = pcall(PaddockRaces.setup, race)
                race.provisionalMps = (okS and base and base > 0) and (route.distanceM / base) or 20
            end
            local host
            for ppid, pp in pairs(players) do
                local pace = route and (route.oval and paceForOval(tonumber(ppid)) or (not route.oval and paceForStreet(tonumber(ppid))))
                if pace and L.dist(pp, route.start) <= inM then host = { pid = tonumber(ppid), pos = pp } break end
            end
            if host then
                for _, id in ipairs(race.frozen.grid or {}) do
                    -- L250: a human's slot is theirs -- never an NPC on it, and never an NPC set down on a player
                    local human = PaddockHumans and PaddockHumans.isHuman(race, id)
                    if not human and not b.cars[id] and spawns < cap then
                        local slot = formationSlot(race, id, 0, { d = 0 })
                        if slot then
                            for _, pp in pairs(players) do
                                if L.dist(pp, slot) < SPAWN_CLEAR_M then
                                    b.clashes = (b.clashes or 0) + 1
                                    if b.clashes % 20 == 1 then log("%s: pre-grid %s held back: a player is on slot %d", race.raceId, id, slot.slot) end
                                    slot = nil
                                    break
                                end
                            end
                        end
                        if slot then
                            log("%s: pre-grid %s to slot %d, %.0f s before the lights, player %d at %.0f m", race.raceId, id, slot.slot, lead,
                                host.pid, L.dist(host.pos, slot))
                            local car = spawn(race, id, slot, math.floor((now / 1000 - race.opensAt) * 1000), host.pos.bucket, host.pid)
                            if car then car.pos = { x = slot.x, y = slot.y }; b.cars[id] = car; b.touched = true; spawns = spawns + 1 end
                        end
                    end
                end
                -- the pre-grid: racers can already be choosing their moment for the lights
                if PaddockHack then pcall(PaddockHack.step, race, b, players) end
            elseif next(b.cars) then
                -- nobody with Pace near the start any more: the held grid goes (nothing to anchor, the race has not begun)
                for id, car in pairs(b.cars) do remove(car, race); b.cars[id] = nil end
                log("%s: pre-grid taken down: nobody with Pace within %d m of the start", race.raceId, inM)
            end
        end
        if race.state == "running" and race.model and not street and (src == "ghost" or src == "ring" or src == "road") then
            local b = state(race.raceId)
            local tMs = now - race.modelGoAt * 1000
            -- KB-318 (owner, 2026-10-03: restreams "too obvious and damaging to race integrity especially during oval"): a
            -- ring is about as wide as the bubble, so every lap the far side crossed bubbleOutM and its cars went out and came
            -- back in. On an oval the bubble covers the whole ring: a player at the venue keeps the whole field physical.
            local raceIn, raceOut = inM, outM
            local rroute = PaddockWorld.route(race.routeId)
            if rroute and rroute.oval and tonumber(rroute.oval.radius) then
                local reach = 2 * rroute.oval.radius + set("bubbleOvalMarginM", 80)
                raceIn, raceOut = math.floor(math.max(inM, reach)), math.floor(math.max(outM, reach + 50))
            end
            -- instrumentation (KB-223): every 10 s, each physical car -- where it is, how far it moved, its window
            local report = tMs - (b.reportedMs or -1e9) >= 10000
            if report and next(b.cars) then b.reportedMs = tMs end
            -- physical cars: time them, keep them racing, hand back the ones nobody is near
            for id, car in pairs(b.cars) do
                local okC, pos = pcall(Open77.vehicles.getPosition, car.vid)
                if not okC or type(pos) ~= "table" then
                    R.anchor(race.model, id, tMs, car.lastD, false); remove(car, race); b.cars[id] = nil
                else
                    -- near its last distance: a line that passes the same place twice keeps the right pass (KB-223).
                    -- +-150 m: a car covers at most ~45 m a tick, and the smallest ring lap is 431 m.
                    -- a car from the pre-grid had no model when it came up: its plan now
                    if not car.plan then
                        car.plan = speedPlanFor(race, id)
                    end
                    local d, gap = R.project(race.model, pos, (car.lastD or 0) - 150, (car.lastD or 0) + 150)
                    -- the street is the truth for a car on it (racestate truth rules): its place, and its incidents
                    if car.lastT and tMs > car.lastT then car.lastSpeed = math.abs(d - (car.lastD or d)) / ((tMs - car.lastT) / 1000) end
                    if not car.movingT and (car.lastSpeed or 0) > 5 then car.movingT, car.movingD = car.lastT or tMs, car.lastD or d end
                    -- L296: the stretch the tier's pace is learned from -- a car restreamed mid-race counts only once at
                    -- speed (its launch is the restream's cost, not the street's pace); a grid car from under way
                    if not car.paceT and car.movingT and not car.expect then car.paceT, car.paceD = car.lastT or tMs, car.lastD or d end
                    local ex = car.expect
                    if ex and ((car.lastSpeed or 0) >= 0.85 * ex.v or tMs - ex.t0 > 20000) then
                        -- placed at d0 + lead; with no standstill it would be at d0 + lead + v*dt: the shortfall is the cost
                        local loss = (ex.d0 + ex.lead + ex.v * (tMs - ex.t0) / 1000) - d
                        if loss > -100 and loss < 600 then
                            race.restreamLossM = race.restreamLossM and (0.7 * race.restreamLossM + 0.3 * loss) or loss
                            log("%s: %s restream: at speed after %.1f s, cost %.0f m (led by %.0f m); race average now %.0f m", race.raceId, id,
                                (tMs - ex.t0) / 1000, loss, ex.lead, race.restreamLossM)
                        end
                        car.expect = nil
                    end
                    car.lastT = tMs
                    -- KB-318: while a restreamed car is still launching (set down ahead by the learned lead, not yet at
                    -- 85 % of its pace) the model keeps its race position -- nobody gains places on a car that has not
                    -- got going yet; from its first moment at speed the street is the truth again
                    if not car.expect then R.observe(race.model, id, tMs, d) end
                    pcall(npcIncident, race, car, id, pos, tMs)
                    if L.dist(car.anchorPos, pos) > L.PROGRESS_M then car.anchorPos = { x = pos.x, y = pos.y }; car.progressT = tMs end
                    if report then
                        local laps = race.model.path.source == "ring" and PaddockWorld.route(race.routeId).oval.laps or nil
                        local lapTxt = laps and (" lap %d/%d"):format(math.min(laps, math.floor(d / (race.model.lengthM / laps)) + 1), laps) or ""
                        local nearestP = math.huge
                        for _, pp in pairs(players) do nearestP = math.min(nearestP, L.dist(pp, pos)) end
                        local targetMps = car.pace and car.sentSpeed or (car.plan and car.plan[math.max(1, indexAt(race.model, d))]) or 0
                        log("%s +%ds: %s at %.0f m%s (%.1f, %.1f, %.1f), moved %.0f m in 10 s, target %.1f m/s, %.0f m off the line, nearest player %.0f m, window to %d of %d, re-sent %d, reset %d",
                            race.raceId, math.floor(tMs / 1000), id, d, lapTxt, pos.x, pos.y, pos.z or 0, d - (car.reportD or car.spawnD or d), targetMps,
                            gap or -1, nearestP, car.windowEnd or 0, #race.model.path.points, car.recoveries, car.resets)
                        car.reportD = d
                    end
                    car.lastD = d
                    car.pos = { x = pos.x, y = pos.y }
                    paceFollowSim(race, car, d, tMs)
                    -- the window ahead is running out: send the next one before the car reaches its end
                    if car.windowEnd and car.windowEnd < #race.model.path.points and indexAt(race.model, d) >= car.windowEnd - 6 then
                        drive(race, car, indexAt(race.model, d) + 1)
                    end
                    local nearest = math.huge
                    for _, pp in pairs(players) do nearest = math.min(nearest, L.dist(pp, pos)) end
                    -- a Pace car is driven by ONE client, the player who brought it in: once that player is past
                    -- bubbleOutM it goes back, whoever else is near (L247, KB-238). Kept, it would sit at the edge of
                    -- its driver's streaming -- the crash pattern. A Pace player near it brings it in again.
                    local hostD = math.huge
                    local hp = car.pace and (players[car.pace] or players[tostring(car.pace)])
                    if hp then hostD = L.dist(hp, pos) end
                    if d >= race.model.lengthM then handBack(race, b, car, tMs, false, "finished")
                    elseif nearest > raceOut then handBack(race, b, car, tMs, false, ("nobody within %d m: nearest player %.0f m"):format(raceOut, nearest))
                    elseif car.pace and hostD > raceOut then
                        handBack(race, b, car, tMs, false, ("its Pace player %d is %s m away (over %d)"):format(car.pace,
                            hostD < math.huge and ("%.0f"):format(hostD) or "gone", raceOut))
                    else persevere(race, b, car, pos, tMs) end
                end
            end
            -- L356: the physical field in each other's wakes (and players'); server-driven cars towed through their leg speed
            if PaddockSlip and next(b.cars) then
                local field = {}
                for _, car in pairs(b.cars) do field[#field + 1] = car end
                table.sort(field, function(x, y) return tostring(x.id) < tostring(y.id) end)
                pcall(PaddockSlip.step, field, set("bubbleTickMs", 500) / 1000, function(car) return not car.pace end)
            end
            -- NPC racers' quickhacking: the physical field on the real chrome machinery, the rest on the model
            if PaddockHack then
                pcall(PaddockHack.step, race, b, players)
                local okM, errM = pcall(PaddockHack.modelStep, race, b)
                if not okM then log("%s: hack model step failed: %s", race.raceId, tostring(errM)) end
            end
            -- model cars coming into a player's range become physical
            for ppid, pp in pairs(players) do
                -- a street race is the engine's racer on race splines, or nothing (L245): only a player with Pace
                -- brings its cars in. The platform AI that drives an oval's cars without Pace is not that.
                local eligible = (src == "road" and paceForStreet(tonumber(ppid)))
                    or (src == "ring" and paceForOval(tonumber(ppid))) or (src ~= "road" and src ~= "ring")
                local near = eligible and R.near(race.model, tMs, pp, raceIn) or {}
                for _, id in ipairs(near) do
                    if not b.cars[id] and spawns < cap then
                        local p = R.carAt(race.model, id, tMs)
                        if p and p.state == "racing" and p.d > 5 then
                            -- the start (KB-223): the model starts every car at 0 m with no spacing, so in the first
                            -- FORMATION_MS a car comes in at its GRID SLOT (SP's formation; round the ring on an oval)
                            local slot = formationSlot(race, id, tMs, p)
                            if slot then p = slot end
                            -- SEAMLESS RESTREAM (owner, 2026-10-02: restreamed drivers "spawn in at standstill and take
                            -- seconds to get up to speed", so a driver who fell back made up places). A mid-race car is set
                            -- down AHEAD of its model position by what a restream measurably costs in this race (seat,
                            -- command, launch: race.restreamLossM, learned below), so it is where it should be once at speed.
                            -- The lead shrinks to keep the car out of a player's sight (bubbleRestreamClearM).
                            local trueD, trueSpeed = p.d, p.speed
                            if not slot and p.d and p.d > 5 then
                                local lead = math.max(0, math.min(set("bubbleRestreamMaxLeadM", 220), race.restreamLossM or set("bubbleRestreamLeadM", 90)))
                                local clearM = set("bubbleRestreamClearM", 150)
                                while lead > 0 do
                                    local q = R.pointAt(race.model, math.min(race.model.lengthM - 5, p.d + lead))
                                    local nearP = math.huge
                                    for _, pp2 in pairs(players) do nearP = math.min(nearP, L.dist(pp2, q)) end
                                    if nearP >= clearM then
                                        q.d, q.speed, q.state = math.min(race.model.lengthM - 5, p.d + lead), p.speed, p.state
                                        p = q
                                        break
                                    end
                                    lead = lead - 30
                                end
                                p.restreamLead = math.max(0, lead)
                            end
                            p.trueD, p.trueSpeed = trueD, trueSpeed
                            -- never set a car down on another: wait a pass for the model to string the field out
                            local clash
                            -- KB-286: nor where this player is driving away from it faster than it can follow
                            if not slot then
                                local receding, away, carMps = recedingFrom(ppid, pp, p)
                                if receding then
                                    clash = "receding"
                                    b.recedes = (b.recedes or 0) + 1
                                    if b.recedes % 20 == 1 then
                                        log("%s: %s not set down: player %s is pulling away from it at %.1f m/s, the car's pace is %.1f m/s (%d skips)",
                                            race.raceId, id, tostring(ppid), away, carMps, b.recedes)
                                    end
                                end
                            end
                            for _, other in pairs(b.cars) do
                                if other.pos and L.dist(other.pos, p) < SPAWN_CLEAR_M then clash = other.id break end
                            end
                            -- L250: nor on a player -- on a mixed grid a human's car stands among the slots
                            if not clash then
                                for ppid2, pp2 in pairs(players) do
                                    if L.dist(pp2, p) < SPAWN_CLEAR_M then clash = "player " .. tostring(ppid2) break end
                                end
                            end
                            if clash == "receding" then
                                -- skipped above, logged there
                            elseif clash then
                                b.clashes = (b.clashes or 0) + 1
                                if b.clashes % 20 == 1 then log("%s: %s held back: within %d m of %s (%d holds)", race.raceId, id, SPAWN_CLEAR_M, clash, b.clashes) end
                            else
                                -- KB-223 evidence: how far the player was from the car when it came in
                                log("%s: %s coming in %.0f m from a player at %.0f, %.0f%s", race.raceId, id, L.dist(pp, p), pp.x or 0, pp.y or 0,
                                    slot and (" (grid slot " .. slot.slot .. ")") or "")
                                local car = spawn(race, id, p, tMs, pp.bucket, tonumber(ppid))
                                if car and not slot and p.trueD and (p.trueSpeed or 0) > 3 then
                                    car.expect = { d0 = p.trueD, t0 = tMs, v = p.trueSpeed, lead = p.restreamLead or 0 }
                                    car.startMps = p.trueSpeed
                                end
                                if car then car.pos = { x = p.x, y = p.y }; b.cars[id] = car; b.touched = true; spawns = spawns + 1 end
                                if car and car.pace then
                                    PaddockBubble.streamline(car.pace, "%s %s set down as vehicle %s, %.0f m from player %s", race.raceId, id,
                                        tostring(car.vid), L.dist(pp, p), tostring(ppid))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

--- Per-leg ceilings and immediate re-sends for bubble cars (live.lua forwards AI events it does not own).
function PaddockBubble.onAi(ev, st)
    local vid = tonumber(st and st.vehicleId)
    local ref = vid and byVehicle[vid]
    if not ref then return end
    local race = PaddockRaces.byId[ref.raceId]
    local b = PaddockBubble.byRace[ref.raceId]
    local car = b and b.cars[ref.id]
    if not race or not car then return end
    if ev == "waypointReached" then
        local v = car.plan[(car.base or 2) + (tonumber(st.routeIndex) or 0)] or car.plan[#car.plan]
        if v then pcall(Open77.vehicles.ai.setSpeed, vid, PaddockSlip and PaddockSlip.leg(car, v) or v) end
    elseif ev == "failed" then
        -- NOT on "cancelled": issuing a route cancels the car's previous task, so answering a cancel with a re-send
        -- is a loop -- 2,117 cancels in 30 s and every car stood still (03:54 Corpo, KB-223). A stuck car is the
        -- tick's job (liveRecoverSec / liveResetSec); a failed task gets one re-send per 2 s at most.
        local t = nowMs()
        if t - (car.lastAiResendMs or 0) < 2000 then return end
        car.lastAiResendMs = t
        local okP, pos = pcall(Open77.vehicles.getPosition, vid)
        if okP and type(pos) == "table" then
            car.recoveries = car.recoveries + 1
            drive(race, car, indexAt(race.model, car.lastD or 0) + 1)
            log("%s: %s AI task %s at %.0f m; re-sent", race.raceId, car.id, ev, car.lastD or 0)
        end
    end
end

--- At the close: the model's classification with every anchor, written over the sim's rows. Called by races.lua.
function PaddockBubble.writeBack(race)
    local b = PaddockBubble.byRace[race.raceId]
    if not b or not b.touched or not race.model then return false end
    for id, car in pairs(b.cars) do R.anchor(race.model, id, nowMs() - race.modelGoAt * 1000, car.lastD, false); remove(car, race); b.cars[id] = nil end
    -- the flag: only the cars home by then are finishers; the rest are classified by how far they got
    local cutoff = race.flagAt and race.modelGoAt and math.floor((race.flagAt - race.modelGoAt) * 1000) or nil
    local entrants = R.result(race.model, cutoff)
    race.modelEntrants = entrants          -- raw finishes and penalties, for the classification ceremony (humans.lua)
    local all = true
    for _, e in ipairs(entrants) do if (e.physicalShare or 0) < 0.95 then all = false end end
    local shares = {}
    for _, e in ipairs(entrants) do shares[e.id] = math.floor((e.physicalShare or 0) * 100 + 0.5) end
    local ok, err = PaddockLive.writeResult(race, entrants, all and "physical" or "mixed", "bubble", { mode = "bubble", physicalPct = shares })
    if not ok then log("%s: write-back FAILED: %s", race.raceId, tostring(err)) return false end
    log("%s: result written from the model (%s)", race.raceId, all and "physical" or "mixed")
    -- L296: what the street measured, into the sim's base pace for the next race of this tier
    if race.paceObs then pcall(PaddockCalibration.learnPhysical, race, race.paceObs.m, race.paceObs.ms) end
    return true
end

function PaddockBubble.start()
    CreateThread(function()
        while true do
            Wait(set("bubbleTickMs", 500))
            if PaddockSettings.get("paddockEnabled", true) then
                local ok, err = pcall(PaddockBubble.tick)
                if not ok then log("tick FAILED: %s", tostring(err)) end
            end
        end
    end)
end

--- The host's client: this car has stood in its game for bubbleSeatDelayMs, past the engine's spawn physics cycle
--- (KB-238). Now its driver is seated, and Pace takes it.
function PaddockBubble.seated(pid, msg)
    local vid = tonumber(msg and msg.vehicleId)
    local ref = vid and byVehicle[vid]
    local b = ref and PaddockBubble.byRace[ref.raceId]
    local car = b and b.cars[ref.id]
    local race = ref and PaddockRaces.byId[ref.raceId]
    if not car or not race or car.seated or car.pace ~= pid then return false end
    local okP, at = pcall(Open77.vehicles.getPosition, vid)
    at = (okP and type(at) == "table") and { x = at.x, y = at.y, z = (at.z or 0) + 0.5 } or { x = car.anchorPos.x, y = car.anchorPos.y, z = 0 }
    local ok, npc = seatDriver(vid, PaddockStore.world.people[car.id], car.id, at, car.yaw, car.bucket)
    if not ok then
        log("%s: %s refused a driver after settling; removed", race.raceId, car.id)
        remove(car, race); b.cars[car.id] = nil
        return false
    end
    car.npc, car.seated = npc, true
    log("%s: %s driver seated %d ms after it was set down (it settled in player %d's game)", race.raceId, car.id,
        nowMs() - (car.seatAskedMs or nowMs()), pid)
    paceCar(race, car, "add", car.addFrom)
    return true
end

--- The stream line (KB-238): a line about a bubble car that must survive -- the server console does not -- written to
--- the Pace player's own client log as `STREAMLINE ...`.
function PaddockBubble.streamline(pid, fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    if not ok or not pid then return end
    log("streamline p%s %s", tostring(pid), text)
    TriggerClientEvent("ncm:paddock.bubble.streamline", pid, text)
end

-- a race car's state changed in this player's game: how far from the player was it?
RegisterNetEvent("ncm:paddock.bubble.stream", function(msg)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(msg) ~= "table" then return end
    local vid = tonumber(msg.vehicleId)
    local ref = vid and byVehicle[vid]
    local okP, players = pcall(Open77.players.positions)
    local me = okP and type(players) == "table" and (players[pid] or players[tostring(pid)]) or nil
    local okV, at = pcall(Open77.vehicles.getPosition, vid)
    local d = (me and okV and type(at) == "table") and L.dist(me, at) or -1
    local car = ref and PaddockBubble.byRace[ref.raceId] and PaddockBubble.byRace[ref.raceId].cars[ref.id]
    PaddockBubble.streamline(pid, "vehicle %s %s: %s -> %s at %.0f m (player %.0f,%.0f; car %.0f,%.0f)%s", tostring(vid),
        ref and ref.id or "?", tostring(msg.was or "new"), tostring(msg.state), d, me and me.x or 0, me and me.y or 0,
        (okV and type(at) == "table") and at.x or 0, (okV and type(at) == "table") and at.y or 0,
        car and (car.seated and " seated" or " empty") or " gone")
end)

RegisterNetEvent("ncm:paddock.bubble.settled", function(msg)
    local pid = tonumber(source) or 0
    if pid > 0 and type(msg) == "table" then pcall(PaddockBubble.seated, pid, msg) end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    for _, b in pairs(PaddockBubble.byRace) do for _, car in pairs(b.cars) do remove(car) end end
end)
