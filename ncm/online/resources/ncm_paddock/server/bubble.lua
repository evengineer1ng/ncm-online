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

-- send a physical car along the rest of the line from path point `from`
local function drive(race, car, from)
    local pts = race.model.path.points
    from = math.max(2, math.min(#pts, from))
    local route = {}
    for i = from, #pts do route[#route + 1] = pts[i] end
    local a, b = pts[#pts - 1], pts[#pts]
    local len = math.max(1, L.dist(a, b))
    route[#route + 1] = { x = b.x + (b.x - a.x) / len * 80, y = b.y + (b.y - a.y) / len * 80, z = b.z or 0 }
    while #route > 64 do table.remove(route, 1) end
    car.base = #pts + 1 - #route
    local okF, st, why = pcall(Open77.vehicles.ai.followRoute, car.vid, { points = route,
        speed = car.plan[math.max(1, car.base)] or car.plan[#car.plan] or 20, behavior = "aggressive", arrivalRadius = 12,
        timeoutMilliseconds = 900000 })
    if not okF or not st then log("%s: followRoute for %s refused: %s", race.raceId, car.id, tostring(why or st)) return false end
    return true
end

local function remove(car)
    byVehicle[car.vid] = nil
    pcall(Open77.vehicles.ai.removeDriver, car.vid)
    pcall(Open77.vehicles.remove, car.vid)
    if car.npc then pcall(Open77.npcs.remove, car.npc) end
end

local function spawn(race, id, p, tMs, bucket)
    local w = PaddockStore.world
    local person = w.people[id]
    local zOk, z = pcall(Open77.world.groundZ, { x = p.x, y = p.y }, { radius = 400, fromZ = (p.z or 0) + 30, timeout = 1500, cache = true })
    z = (zOk and type(z) == "number") and z or (p.z or 0)
    local okV, vid, why = pcall(Open77.vehicles.create, { record = PaddockLive.recordFor(w.orgs[(person and person.orgId) or ""], race.tier),
        position = { x = p.x, y = p.y, z = z + 0.8 }, yaw = p.yaw, bucket = bucket or 0 })
    if not okV or not vid then stats.refused = stats.refused + 1; log("%s: %s refused: %s", race.raceId, id, tostring(why or vid)) return nil end
    local okN, npc = pcall(Open77.npcs.create, { record = Hash.pick(DRIVER_RECORDS[(person and person.gender == "f") and "f" or "m"], "driver", id),
        position = { x = p.x, y = p.y, z = z + 0.8 }, yaw = p.yaw, bucket = bucket or 0, aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or nil,
        damagePolicy = Open77.npcs.damage and Open77.npcs.damage.invulnerable or nil, despawnWhenUnobserved = false, persistent = false })
    local okA, st = pcall(Open77.vehicles.ai.attachDriver, vid, (okN and npc) and { npcId = npc } or nil)
    if (not okA or not st) and okN and npc then pcall(Open77.npcs.remove, npc); npc = nil; okA, st = pcall(Open77.vehicles.ai.attachDriver, vid, nil) end
    if not okA or not st then pcall(Open77.vehicles.remove, vid); stats.refused = stats.refused + 1 return nil end
    local car = { id = id, vid = vid, npc = (okN and npc) or nil, spawnT = tMs, spawnD = p.d, lastD = p.d,
        anchorPos = { x = p.x, y = p.y }, progressT = tMs, recoveries = 0, resets = 0, lastHelpT = -1e9, lastResetT = -1e9,
        plan = L.speedPlan(race.model.path.points, race.model.lengthM, splitsOf(race, id), race.model.segments, L.PLATFORM_MAX_MPS) }
    byVehicle[vid] = { raceId = race.raceId, id = id }
    drive(race, car, (p.index or 2))
    stats.spawned = stats.spawned + 1
    return car
end

local function handBack(race, b, car, tMs, stopped, why)
    local okP, pos = pcall(Open77.vehicles.getPosition, car.vid)
    local d = car.lastD
    if okP and type(pos) == "table" then d = R.project(race.model, pos) end
    R.anchor(race.model, car.id, tMs, d, stopped)
    R.markPhysical(race.model, car.id, car.spawnD or 0, d, car.spawnT, tMs)
    remove(car)
    b.cars[car.id] = nil
    if stopped then stats.stopped = stats.stopped + 1 else stats.handedBack = stats.handedBack + 1 end
    log("%s: %s handed back at %.0f m (%s)", race.raceId, car.id, d, why)
end

-- keep a stuck physical car racing; anchor it as out only after liveRetireSec
local function persevere(race, b, car, pos, tMs)
    local idle = tMs - car.progressT
    if idle > set("liveRetireSec", 180) * 1000 then return handBack(race, b, car, tMs, true, "stuck for good") end
    local resetMs = set("liveResetSec", 20) * 1000
    if idle > resetMs and tMs - car.lastResetT > resetMs then
        local rp = L.resetPoint(race.model.path.points, pos)
        if pcall(Open77.vehicles.setTransform, car.vid, { position = { x = rp.x, y = rp.y, z = (rp.z or 0) + 1.0 }, yaw = rp.yaw }) then
            drive(race, car, rp.index + 1)
        end
        car.resets, car.lastResetT, car.lastHelpT = car.resets + 1, tMs, tMs
        car.anchorPos = { x = rp.x, y = rp.y }
    elseif idle > set("liveRecoverSec", 8) * 1000 and tMs - car.lastHelpT > set("liveRecoverSec", 8) * 1000 then
        car.recoveries, car.lastHelpT = car.recoveries + 1, tMs
        drive(race, car, L.nearestIndex(race.model.path.points, pos) + 1)
    end
end

--- One bubble pass over every running race. Bounded: at most `bubbleSpawnsPerPass` new cars per pass.
function PaddockBubble.tick()
    if not set("bubbleEnabled", true) or set("liveMode", "watched") == "off" then return end
    local okP, players = pcall(Open77.players.positions)
    players = (okP and type(players) == "table") and players or {}
    local inM, outM = set("bubbleInM", 250), set("bubbleOutM", 400)
    local now = nowMs()
    local spawns, cap = 0, set("bubbleSpawnsPerPass", 3)
    for _, race in pairs(PaddockRaces.byId) do
        local lr = PaddockLive.byRace[race.raceId]
        local street = lr and (lr.state == "staging" or lr.state == "running" or lr.state == "finished")
        if race.state == "running" and race.model and not street then
            local b = state(race.raceId)
            local tMs = now - race.modelGoAt * 1000
            -- physical cars: time them, keep them racing, hand back the ones nobody is near
            for id, car in pairs(b.cars) do
                local okC, pos = pcall(Open77.vehicles.getPosition, car.vid)
                if not okC or type(pos) ~= "table" then
                    R.anchor(race.model, id, tMs, car.lastD, false); remove(car); b.cars[id] = nil
                else
                    local d = R.project(race.model, pos)
                    if L.dist(car.anchorPos, pos) > L.PROGRESS_M then car.anchorPos = { x = pos.x, y = pos.y }; car.progressT = tMs end
                    car.lastD = d
                    local nearest = math.huge
                    for _, pp in pairs(players) do nearest = math.min(nearest, L.dist(pp, pos)) end
                    if d >= race.model.lengthM then handBack(race, b, car, tMs, false, "finished")
                    elseif nearest > outM then handBack(race, b, car, tMs, false, ("nobody within %d m"):format(outM))
                    else persevere(race, b, car, pos, tMs) end
                end
            end
            -- model cars coming into a player's range become physical
            for _, pp in pairs(players) do
                for _, id in ipairs(R.near(race.model, tMs, pp, inM)) do
                    if not b.cars[id] and spawns < cap then
                        local p = R.carAt(race.model, id, tMs)
                        if p and p.state == "racing" and p.d > 5 then
                            local car = spawn(race, id, p, tMs, pp.bucket)
                            if car then b.cars[id] = car; b.touched = true; spawns = spawns + 1 end
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
        if v then pcall(Open77.vehicles.ai.setSpeed, vid, v) end
    elseif ev == "failed" or ev == "cancelled" then
        local okP, pos = pcall(Open77.vehicles.getPosition, vid)
        if okP and type(pos) == "table" then car.recoveries = car.recoveries + 1; drive(race, car, L.nearestIndex(race.model.path.points, pos) + 1) end
    end
end

--- At the close: the model's classification with every anchor, written over the sim's rows. Called by races.lua.
function PaddockBubble.writeBack(race)
    local b = PaddockBubble.byRace[race.raceId]
    if not b or not b.touched or not race.model then return false end
    for id, car in pairs(b.cars) do R.anchor(race.model, id, nowMs() - race.modelGoAt * 1000, car.lastD, false); remove(car); b.cars[id] = nil end
    local entrants = R.result(race.model)
    local all = true
    for _, e in ipairs(entrants) do if (e.physicalShare or 0) < 0.95 then all = false end end
    local shares = {}
    for _, e in ipairs(entrants) do shares[e.id] = math.floor((e.physicalShare or 0) * 100 + 0.5) end
    local ok, err = PaddockLive.writeResult(race, entrants, all and "physical" or "mixed", "bubble", { mode = "bubble", physicalPct = shares })
    if not ok then log("%s: write-back FAILED: %s", race.raceId, tostring(err)) return false end
    log("%s: result written from the model (%s)", race.raceId, all and "physical" or "mixed")
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

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    for _, b in pairs(PaddockBubble.byRace) do for _, car in pairs(b.cars) do remove(car) end end
end)
