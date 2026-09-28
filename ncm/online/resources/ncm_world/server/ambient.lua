-- ncm_world / server / ambient — the ambient population service (`L177`, `IDEA-635`).
--
-- Night City with nobody in it is the first thing every tester says about NCM Online, and it is not a
-- taste question: an empty street removes the only scale reference a driver has. This file puts people
-- back, and takes them out of the way of a race.
--
-- TWO POPULATION SYSTEMS, AND THEY ARE NOT INTERCHANGEABLE. The reconnaissance note that "vanilla traffic
-- is per-client" is TRUE and was read as "traffic is not server side", which is FALSE. Both halves are
-- confirmed against the platform's own embedded Lua prelude at 2.31.13+op77.102:
--
--   * `Open77.world.setPopulation(bucket, { crowd, traffic, police })` is SERVER-OWNED and replicated to
--     every client in the bucket; the client half is read-only. `crowd` is a real multiplier on vanilla
--     pedestrian density; `traffic` and `police` are binary on 2.31 and `getPopulation` says so itself
--     (`trafficGranularity = "binary"`). Needs the `world.population` permission.
--   * The ENTITIES that switch produces are per-client. Nothing on the server can name, move or remove
--     one vanilla traffic car, and two players on one corner are not looking at the same cars.
--
-- So the ask -- "despawn traffic in a radius before a race" -- lands in two places, and this file does
-- both because neither alone is enough:
--
--   1. OUR OWN ambient layer (`Open77.vehicles.create` + an attached NPC driver on the engine's own
--      `joinTraffic` lane enrollment, and `Open77.npcs.create` + `wander` on the pavements). Canonical,
--      identical for every player, removable by id at any radius. This is the half that can honour a
--      corridor, and it is the half that makes the world shared rather than merely busy.
--   2. The VANILLA switch, which can only be turned down for a WHOLE BUCKET -- and which is therefore
--      NOT used in the shared world. There are 21 scheduled starts in any three-hour window on the
--      shipped cadence, so a corridor is in its window almost always; throwing a bucket-wide switch for
--      one would leave the city permanently empty, which is this file's own purpose inverted. The switch
--      is thrown only in a bucket a race has to itself, where the only players it reaches are racing.
--      `Open77.world.clearArea` reaches the same conclusion in the platform's own words: its
--      `population = true` option refuses without a bucket, because "there is no radius-scoped
--      vanilla-population control on 2.31 and inventing one here would only move the surprise".
--
-- These are NOT AI racers. Nothing here enters a session, is scored, or appears in a result. Platform AI
-- needs a simulating client and would be a competitor nobody agreed to race.
NcmAmbient = {}

local Core = NcmCore
local A = Core.get("world.ambient")

local function log(fmt, ...)
    print(("[ncm_world/ambient] " .. fmt):format(...))
end

-- Read tunables AT THE POINT OF USE. `NcmIdentity.settings` is a live proxy behind a metatable, so a
-- local captured at file scope would freeze the value at load and make Warden's panel a liar.
local function tune(key, fallback)
    local s = NcmIdentity and NcmIdentity.settings
    if not s then return fallback end
    local ok, v = pcall(function() return s[key] end)
    if not ok or v == nil then return fallback end
    return v
end

local function settings()
    return A.settings({
        vehicleBudget     = tonumber(tune("ambientVehicleBudget", 24)),
        pedBudget         = tonumber(tune("ambientPedBudget", 48)),
        perPlayerVehicles = tonumber(tune("ambientPerPlayerVehicles", 5)),
        perPlayerPeds     = tonumber(tune("ambientPerPlayerPeds", 10)),
        spawnPerTick      = tonumber(tune("ambientSpawnPerTick", 3)),
        spawnMinM         = tonumber(tune("ambientSpawnMinM", 110)),
        spawnMaxM         = tonumber(tune("ambientSpawnMaxM", 240)),
        retireM           = tonumber(tune("ambientRetireM", 420)),
        sightM            = tonumber(tune("ambientSightM", 220)),
        corridorRadiusM   = tonumber(tune("ambientCorridorRadiusM", 70)),
        leadSeconds       = tonumber(tune("ambientLeadSeconds", 240)),
        holdSeconds       = tonumber(tune("ambientHoldSeconds", 180)),
        graceSeconds      = tonumber(tune("ambientGraceSeconds", 120)),
        sharedBucket      = tonumber(tune("ambientSharedBucket", 0)),
        vanillaSuppress   = tune("ambientVanillaSuppress", true) and true or false,
        suppressShared    = tune("ambientVanillaSuppressShared", false) and true or false,
        crowd             = tonumber(tune("ambientCrowd", 1.0)),
        traffic           = tonumber(tune("ambientTraffic", 1.0)),
        police            = tune("ambientPolice", true) and true or false,
    })
end

local hostRng = function() return math.random() end
local now = function() return Open77.time.unix() end

-- key -> { key, kind, npcId, vehicleId, bucket, x, y, z, bornAt, record }
local owned = {}
local nextKey = 0
local stats = { spawned = 0, despawned = 0, refused = 0, deferred = 0, lastTick = 0, groundMisses = 0 }
NcmAmbient.owned = owned
NcmAmbient.stats = stats

-- ---------------------------------------------------------------------------------------------
-- Vanilla density, per routing bucket
-- ---------------------------------------------------------------------------------------------

local applied = {}   -- bucket -> "open" | "suppressed"

--- Tell one bucket what its vanilla density should be. Idempotent: the platform replicates on every
--- call, so re-asserting an unchanged policy every tick is wire traffic for nothing.
local function applyPopulation(bucket, held)
    local want = held and "suppressed" or "open"
    if applied[bucket] == want then return true end
    local policy = A.populationFor(held, settings())
    local ok, reason = Open77.world.setPopulation(bucket, policy)
    if not ok then
        -- A missing permission and a missing API are indistinguishable unless the reason is read, which
        -- is the lesson `machine.lua` learned about `world.environment` on 2026-09-26. Say which.
        log("setPopulation(bucket=%d) refused: %s  (needs the `world.population` permission)",
            bucket, tostring(reason))
        applied[bucket] = nil
        return false
    end
    applied[bucket] = want
    if held then
        log("bucket %d: vanilla population SUPPRESSED for a race corridor. This is BUCKET-WIDE -- every " ..
            "player in this bucket sees an empty city wherever they are standing, which is only " ..
            "acceptable because this is not the shared world bucket (%d).", bucket, settings().sharedBucket)
    else
        log("bucket %d: vanilla population restored (crowd=%.2f traffic=%s police=%s)",
            bucket, policy.crowd, tostring(policy.traffic), tostring(policy.police))
    end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Corridors
-- ---------------------------------------------------------------------------------------------

-- routeId -> corridor. Cached because the calendar stops publishing an event once it closes, which is
-- roughly when the race it describes actually starts: without the cache the corridor would be released
-- at exactly the moment it matters most.
local corridorCache = {}

local function corridorFor(row)
    local routeId = row.routeId
    if routeId and corridorCache[routeId] then return corridorCache[routeId] end
    local s = settings()
    local c
    if row.venue and row.finish and row.finish.x then
        c = A.corridorFromRoute({
            routeId = routeId or "unknown",
            start = row.venue,
            intermediate = row.via,
            finish = row.finish,
        }, s)
    elseif row.venue then
        -- The publication is old, or this is a venue with no published finish. A disc round the grid is
        -- a poor corridor and a much better nothing: clearing where the cars line up is the part a
        -- driver sees first.
        c = { id = routeId or "venue", points = { { x = row.venue.x, y = row.venue.y, z = row.venue.z } },
              radiusM = s.corridorRadiusM }
    end
    if c and routeId then corridorCache[routeId] = c end
    return c
end

--- A corridor from a live session's own gates, or nil. Gates are the racing line as race control laid it
--- out for THIS session -- including a reversed grid or a shortened route -- so where they exist they beat
--- anything the calendar said about the route in the abstract.
local function corridorFromGates(v)
    local g = v and v.gates
    if type(g) ~= "table" or #g < 2 then return nil end
    local line = {}
    for i = 1, #g do
        if tonumber(g[i].x) then line[#line + 1] = { x = g[i].x, y = g[i].y, z = g[i].z } end
    end
    if #line < 2 then return nil end
    local s = settings()
    return {
        id = "session:" .. tostring(v.sessionId or v.eventId or "?"),
        points = A.densify(line, s.corridorStepM),
        radiusM = s.corridorRadiusM,
    }
end

--- Every corridor that should be held clear right now, from the calendar and the live session boards.
function NcmAmbient.corridors(t)
    local out, seen = {}, {}
    local s = settings()

    -- `entries` is the calendar's own entrant count, and passing it is what stops every empty slot on a
    -- 20-minute cadence clearing a road nobody is going to race on.
    local cal = GlobalState and GlobalState.ncmCalendar
    for _, row in ipairs((cal and cal.next) or {}) do
        if A.isHeldClear({ startsAt = row.startsAt, entrants = row.entries }, t, s) then
            local c = corridorFor(row)
            if c and not seen[c.id] then seen[c.id] = true; out[#out + 1] = c end
        end
    end

    -- A live session outranks the schedule: a race that overran its estimate still owns its road. It is
    -- also the BETTER corridor source, because the session view publishes the session's own ordered gate
    -- geometry -- the racing line as race control actually laid it out, rather than as the calendar
    -- described it. `phase` is the field the kernel publishes (forming / gridded / countdown / running /
    -- finishing / complete); there is no `state` on a session view, and reading one would have made
    -- every session look live forever.
    local sessions = GlobalState and GlobalState.ncmSessions
    for key, v in pairs(sessions or {}) do
        if key ~= "serverNow" and type(v) == "table" then
            local held = A.isHeldClear({
                startsAt = tonumber(v.startsAt) or (t - s.leadSeconds),
                live = v.phase ~= "complete",
                endedAt = tonumber(v.completedAt),
            }, t, s)
            if held then
                local c = corridorFromGates(v) or (v.routeId and (corridorCache[v.routeId] or corridorFor(v)))
                if c and not seen[c.id] then seen[c.id] = true; out[#out + 1] = c end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Reading the world
-- ---------------------------------------------------------------------------------------------

local function players()
    local out = {}
    local ok, all = pcall(Open77.players.all)
    if not ok or type(all) ~= "table" then return out end
    for _, raw in ipairs(all) do
        local id = tonumber(raw) or 0
        if id > 0 then
            local pos = select(1, Open77.players.position(id))
            if type(pos) == "table" and tonumber(pos.x) then
                local bucket = 0
                pcall(function() bucket = tonumber(Open77.routingBuckets.getPlayer(id)) or 0 end)
                out[#out + 1] = { id = id, x = pos.x, y = pos.y, z = pos.z or 0, bucket = bucket }
            end
        end
    end
    return out
end

--- Is anybody rendering this entity? true / false / nil for "could not tell".
---
--- The NPC read is the exact one: `readyClients` counts clients that have reported a ready projection,
--- and zero means nothing anywhere is drawing it. The vehicle read is coarser -- an owner table with no
--- authority player, or a `not_streamed` refusal, is nobody simulating it -- so a car is judged by its
--- DRIVER where it has one. Neither is a view frustum, which is why the director pairs whatever comes
--- back with a distance rule and needs both to agree before a corridor despawn.
local function watchedBy(e)
    if e.npcId then
        local ok, owner = pcall(Open77.npcs.owner, e.npcId)
        if ok and type(owner) == "table" then return (tonumber(owner.readyClients) or 0) > 0 end
    end
    if e.vehicleId then
        local ok, owner, reason = pcall(Open77.vehicles.owner, e.vehicleId)
        if ok and type(owner) == "table" then
            return (tonumber(owner.authorityPlayerId) or 0) > 0 or (tonumber(owner.physicsOwner) or 0) > 0
        end
        if ok and owner == nil and reason == "not_streamed" then return false end
    end
    return nil
end

--- Refresh a registry entry's position from the entity itself. An ambient car on `joinTraffic` drives
--- away: judging it at the coordinates it was CREATED at would clear a corridor of cars that left it
--- twenty minutes ago and leave the ones that have since driven into it.
local function refresh(e)
    if e.vehicleId then
        local ok, v = pcall(Open77.vehicles.get, e.vehicleId)
        if ok and type(v) == "table" and tonumber(v.x) then
            e.x, e.y, e.z = v.x, v.y, v.z or e.z
            return true
        end
        return false   -- gone from under us (a client crash, a platform sweep)
    end
    if e.npcId then
        local ok, n = pcall(Open77.npcs.get, e.npcId)
        if ok and type(n) == "table" and tonumber(n.x) then
            e.x, e.y, e.z = n.x, n.y, n.z or e.z
            return true
        end
        return false
    end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Making and unmaking
-- ---------------------------------------------------------------------------------------------

local function remove(e, reason)
    if e.vehicleId then pcall(Open77.vehicles.ai.removeDriver, e.vehicleId) end
    if e.npcId then pcall(Open77.npcs.remove, e.npcId) end
    if e.vehicleId then pcall(Open77.vehicles.remove, e.vehicleId) end
    owned[e.key] = nil
    stats.despawned = stats.despawned + 1
    if reason == "corridor" then
        log("cleared %s %s from a race corridor", e.kind, tostring(e.record))
    end
end

--- Settle a site onto the ground. `groundZ` asks a nearby client for a downward ray, so it WAITS and
--- must run on a scheduler coroutine -- which the tick is. A site with no ground under it (water, a
--- void, a sector nobody has streamed) is refused rather than guessed at: an NPC dropped into the sea
--- is worse than an NPC not spawned.
local function settle(site)
    local ok, z = pcall(Open77.world.groundZ, { x = site.x, y = site.y },
        { radius = 300, fromZ = (site.z or 0) + 200, timeout = 2500, cache = true })
    if not ok or type(z) ~= "number" then
        stats.groundMisses = stats.groundMisses + 1
        return nil
    end
    return z
end

local function makePed(site)
    local z = settle(site)
    if not z then return false end
    local record = A.pickPed(site.region, hostRng)
    local id, reason = Open77.npcs.create({
        record = record,
        position = { x = site.x, y = site.y, z = z + 0.2 },
        yaw = site.heading or 0,
        bucket = site.bucket or 0,
        aiMode = Open77.npcs.ai.tasks,
        damagePolicy = Open77.npcs.damage.invulnerable,   -- ambient life is not a target range
        -- We manage the lifetime ourselves through the director's budget and reclaim rules, so the
        -- engine must not quietly delete an id the registry still holds.
        despawnWhenUnobserved = false,
        persistent = false,
    })
    if not id then
        stats.refused = stats.refused + 1
        log("ped %s refused: %s", tostring(record), tostring(reason))
        return false
    end
    -- The engine's own crowd wander. A refusal is not fatal: a standing pedestrian is still a person.
    local okTask, why = Open77.npcs.tasks.wander(id, { radius = 45, speed = "walk" })
    if not okTask then log("ped %d wander refused: %s (left standing)", id, tostring(why)) end
    nextKey = nextKey + 1
    local key = "p" .. nextKey
    owned[key] = { key = key, kind = "ped", npcId = id, bucket = site.bucket or 0,
                   x = site.x, y = site.y, z = z, bornAt = now(), record = record }
    stats.spawned = stats.spawned + 1
    return true
end

local function makeVehicle(site)
    local z = settle(site)
    if not z then return false end
    local record = A.pickVehicle(hostRng)
    local vid, reason = Open77.vehicles.create({
        record = record,
        position = { x = site.x, y = site.y, z = z + 0.5 },
        yaw = site.heading or 0,
        bucket = site.bucket or 0,
    })
    if not vid then
        stats.refused = stats.refused + 1
        log("ambient car %s refused: %s", tostring(record), tostring(reason))
        return false
    end
    -- A car with nobody in it is scenery. The driver is what makes it traffic, and `joinTraffic` is the
    -- engine's OWN lane enrollment -- not a destination and not a wander, because Cyberpunk traffic AI
    -- drives authored lanes and has no free roam. It takes no speed and no behaviour: asking for either
    -- is refused by name (`traffic_speed_unsupported`), which is better than a number nothing applies.
    local driver = Open77.npcs.create({
        record = A.pickDriver(hostRng),
        position = { x = site.x, y = site.y, z = z + 0.5 },
        yaw = site.heading or 0,
        bucket = site.bucket or 0,
        aiMode = Open77.npcs.ai.tasks,
        damagePolicy = Open77.npcs.damage.invulnerable,
        despawnWhenUnobserved = false,
    })
    if driver then
        local ok, why = Open77.vehicles.ai.attachDriver(vid, { npcId = driver })
        if not ok then
            log("ambient car %d: attachDriver refused: %s (parked instead)", vid, tostring(why))
        else
            local joined, joinWhy = Open77.vehicles.ai.joinTraffic(vid, { pattern = "default" })
            if not joined then log("ambient car %d: joinTraffic refused: %s", vid, tostring(joinWhy)) end
        end
    end
    nextKey = nextKey + 1
    local key = "v" .. nextKey
    owned[key] = { key = key, kind = "vehicle", vehicleId = vid, npcId = driver, bucket = site.bucket or 0,
                   x = site.x, y = site.y, z = z, bornAt = now(), record = record }
    stats.spawned = stats.spawned + 1
    return true
end

-- ---------------------------------------------------------------------------------------------
-- The tick
-- ---------------------------------------------------------------------------------------------

function NcmAmbient.tick()
    local t = now()
    stats.lastTick = t
    local s = settings()
    local live = players()

    -- 1. Registry hygiene. An entity the platform no longer knows about is dropped before it can be
    -- planned against; otherwise the budget leaks and the corridor report lies.
    local entities = {}
    for key, e in pairs(owned) do
        if refresh(e) then
            entities[#entities + 1] = {
                key = key, kind = e.kind, x = e.x, y = e.y, z = e.z, bucket = e.bucket,
                watched = watchedBy(e),
            }
        else
            owned[key] = nil
        end
    end

    local corridors = NcmAmbient.corridors(t)

    -- 2. The vanilla switch, per bucket. Only the buckets somebody is actually in: a bucket with nobody
    -- in it has no clients to replicate to and no city to empty.
    --
    -- `maySuppress` is what keeps this service from undoing itself. A corridor is in its window almost
    -- all the time on the shipped race cadence, and the vanilla switch has no radius -- so in the SHARED
    -- bucket a held corridor changes nothing here, and the corridor is cleared entirely by removing our
    -- own entities below. Only a bucket a race has to itself gets the switch thrown.
    local buckets = {}
    for _, p in ipairs(live) do buckets[p.bucket] = true end
    for bucket in pairs(buckets) do
        local held = false
        for _, c in ipairs(corridors) do
            if c.bucket == nil or c.bucket == bucket then held = true; break end
        end
        if held and not A.maySuppress(bucket, s) then held = false end
        applyPopulation(bucket, held)
    end

    -- 3. The plan.
    local plan = A.plan({
        now = t, players = live, entities = entities, corridors = corridors,
        settings = s, rng = hostRng,
    })
    if not plan then return end

    for _, d in ipairs(plan.despawn) do
        local e = owned[d.key]
        if e then remove(e, d.reason) end
    end
    stats.deferred = #plan.deferred

    for _, site in ipairs(plan.spawn) do
        if site.kind == "vehicle" then makeVehicle(site) else makePed(site) end
    end

    if #corridors > 0 and #plan.deferred > 0 then
        -- Say it out loud. A corridor that is not clear yet looks exactly like a corridor that failed,
        -- and the difference is the whole reason the sight rule exists.
        log("%d corridor(s) held; %d ambient entit(ies) left standing this tick because somebody is " ..
            "close enough to watch them vanish -- they come out on a later tick", #corridors, #plan.deferred)
    end
end

--- Remove everything this resource owns. Called on stop so a reload does not orphan a city's worth of
--- NPCs with ids nothing holds any more.
function NcmAmbient.clear()
    local n = 0
    for _, e in pairs(owned) do remove(e); n = n + 1 end
    for bucket in pairs(applied) do applyPopulation(bucket, false) end
    return n
end

CreateThread(function()
    Wait(8000)   -- let identity, the calendar publication and the first joins settle
    log("ambient population service starting (enabled=%s)", tostring(tune("ambientEnabled", true)))
    while true do
        if tune("ambientEnabled", true) then
            local ok, err = pcall(NcmAmbient.tick)
            if not ok then log("tick error: %s", tostring(err)) end
        end
        Wait((tonumber(tune("ambientTickSeconds", 6)) or 6) * 1000)
    end
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= Open77.resource.name() then return end
    local n = NcmAmbient.clear()
    log("stopped: removed %d ambient entit(ies)", n)
end)

-- ---------------------------------------------------------------------------------------------
-- Console
-- ---------------------------------------------------------------------------------------------

RegisterCommand("ncm.ambient", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local sub = (args and args[1]) or "status"
    if sub == "clear" then
        log("ncm.ambient clear: removed %d", NcmAmbient.clear())
        return
    end
    CreateThread(function()
        local t = now()
        local cars, peds = 0, 0
        for _, e in pairs(owned) do
            if e.kind == "vehicle" then cars = cars + 1 else peds = peds + 1 end
        end
        local s = settings()
        log("ambient: %d car(s)/%d of budget, %d ped(s)/%d, %d spawned, %d despawned, %d refused, " ..
            "%d ground miss(es), %d deferred last tick",
            cars, s.vehicleBudget, peds, s.pedBudget, stats.spawned, stats.despawned, stats.refused,
            stats.groundMisses, stats.deferred)
        local corridors = NcmAmbient.corridors(t)
        if #corridors == 0 then
            log("ambient: no race corridor held right now")
        else
            for _, c in ipairs(corridors) do
                log("ambient: corridor %s held, %d point(s), radius %d m", tostring(c.id), #c.points, c.radiusM)
            end
        end
        for bucket, state in pairs(applied) do
            local may, why = A.maySuppress(bucket, s)
            log("ambient: bucket %d vanilla population %s (suppression %s: %s)",
                bucket, state, may and "permitted" or "withheld", why)
        end
        -- The one read that settles "is the population API even reachable from here".
        local pop, why = Open77.world.getPopulation(0)
        if pop then
            log("ambient: bucket 0 reports crowd=%s traffic=%s police=%s enabled=%s (trafficGranularity=%s)",
                tostring(pop.crowd), tostring(pop.traffic), tostring(pop.police), tostring(pop.enabled),
                tostring(pop.trafficGranularity))
        else
            log("ambient: getPopulation(0) refused: %s", tostring(why))
        end
    end)
end, false)
