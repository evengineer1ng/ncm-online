-- The ambient population host (`ncm_world/server/ambient.lua`), run against deterministic doubles.
--
-- The core director is proved by ncm/core/tests/test_ambient.lua. What is only provable HERE is the part
-- that talks to the platform: that a corridor really reaches `Open77.*` removals, that a vanilla
-- suppression is asserted once and restored once, that a site with no ground under it creates nothing,
-- that an entity the platform has lost is dropped from the registry rather than leaking budget, and that
-- a refused `setPopulation` (the shape of a missing `world.population` permission) does not stop the
-- server-owned half from working. Those are the failures that reach a live server silently.
local root = arg[1] or "."
local passed = 0
local realPrint = print
-- On failure this prints the captured resource log before it raises. A host harness failure is almost
-- always explained by a line the resource already wrote, and `assert` alone throws that away.
local logs
local function check(label, value)
    if not value then
        realPrint("  FAIL " .. label)
        for _, l in ipairs(logs or {}) do realPrint("    log| " .. l) end
        error(label, 0)
    end
    passed = passed + 1; realPrint("  PASS " .. label)
end

local events, commands, queue = {}, {}, {}
logs = {}

function AddEventHandler(name, fn) events[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function CreateThread(fn) queue[#queue + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function TriggerEvent(name, ...) if events[name] then events[name](...) end end
function print(s) logs[#logs + 1] = tostring(s) end

local function drain(rounds)
    local guard = 0
    while #queue > 0 and guard < (rounds or 400) do
        guard = guard + 1
        local co = table.remove(queue, 1)
        local ok, err = coroutine.resume(co)
        assert(ok, err)
        if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end
    end
end

local function logged(pattern)
    for _, line in ipairs(logs) do if line:find(pattern, 1, true) then return line end end
    return nil
end

-- ---------------------------------------------------------------- the world double
local clock = 1789920000
local nextId = 1
local npcs, vehicles = {}, {}
local roster = {}                -- playerId -> { x, y, z, bucket }
local population = {}            -- bucket -> policy
local populationCalls = 0
local populationRefuses = false
local groundAt = function() return 10 end     -- swap for a void
local tasks = {}                 -- npcId -> task name
local joined = {}                -- vehicleId -> true once enrolled in traffic
local attached = {}              -- vehicleId -> npcId
local tunables = {}

Open77 = {
    time = { unix = function() return clock end },
    resource = { name = function() return "ncm_world" end },
    tunables = { declare = function(spec)
        for k, v in pairs(spec) do if tunables[k] == nil then tunables[k] = v.value end end
        return setmetatable({}, { __index = function(_, k) return tunables[k] end })
    end },
    players = {
        all = function()
            local out = {}
            for id in pairs(roster) do out[#out + 1] = id end
            table.sort(out)
            return out
        end,
        position = function(id) return roster[id] end,
    },
    routingBuckets = { getPlayer = function(id) return roster[id] and roster[id].bucket or 0 end },
    world = {
        setPopulation = function(bucket, policy)
            populationCalls = populationCalls + 1
            if populationRefuses then return nil, "permission_denied:world.population" end
            population[bucket] = policy
            return true
        end,
        getPopulation = function(bucket)
            return population[bucket] or { bucket = bucket, crowd = 1, traffic = 1, police = true,
                                           enabled = true, trafficGranularity = "binary" }
        end,
        groundZ = function(p) local z = groundAt(p); if z == nil then return nil, "no_ground" end; return z end,
    },
    npcs = {
        ai = { tasks = 0, frozen = 1, native = 2 },
        damage = { mortal = 0, immortal = 1, invulnerable = 2 },
        create = function(def)
            nextId = nextId + 1
            npcs[nextId] = { id = nextId, x = def.position.x, y = def.position.y, z = def.position.z,
                             bucket = def.bucket, record = def.record, readyClients = 0 }
            return nextId
        end,
        get = function(id) return npcs[id] end,
        remove = function(id) if not npcs[id] then return false end; npcs[id] = nil; return true end,
        owner = function(id)
            local n = npcs[id]
            if not n then return nil, "not_found" end
            return { authorityPlayerId = 0, readyClients = n.readyClients or 0, epoch = 1 }
        end,
        tasks = { wander = function(id, o) tasks[id] = "wander"; return true end },
    },
    vehicles = {
        create = function(def)
            nextId = nextId + 1
            vehicles[nextId] = { id = nextId, x = def.position.x, y = def.position.y, z = def.position.z,
                                 bucket = def.bucket, record = def.record }
            return nextId
        end,
        get = function(id) return vehicles[id] end,
        remove = function(id) if not vehicles[id] then return false end; vehicles[id] = nil; return true end,
        owner = function(id)
            if not vehicles[id] then return nil, "not_streamed" end
            -- a streamed car has a client simulating it (the seat handshake waits for that, KB-238)
            return { authorityPlayerId = vehicles[id].authority or 0, physicsOwner = vehicles[id].physicsOwner or 1 }
        end,
        ai = {
            attachDriver = function(vid, o) attached[vid] = o and o.npcId; return true end,
            removeDriver = function(vid) attached[vid] = nil; return true end,
            joinTraffic = function(vid) joined[vid] = true; return { status = "traffic" } end,
        },
    },
}

GlobalState = {}

-- real core
local Core = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
Core.warm()
NcmCore = Core

-- identity.lua owns the tunable declaration for this resource; ambient reads it through NcmIdentity.
NcmIdentity = { settings = Open77.tunables.declare({
    -- OFF, so the resource's own timer thread never ticks behind the harness's back: every tick in this
    -- file is one the test asked for, which is what makes the counts assertable at all.
    ambientEnabled = { value = false }, ambientTickSeconds = { value = 6 },
    ambientVehicleBudget = { value = 4 }, ambientPedBudget = { value = 6 },
    ambientPerPlayerVehicles = { value = 2 }, ambientPerPlayerPeds = { value = 3 },
    ambientSpawnPerTick = { value = 3 },
    ambientSpawnMinM = { value = 110 }, ambientSpawnMaxM = { value = 240 },
    ambientRetireM = { value = 300 }, ambientSightM = { value = 220 },
    ambientCorridorRadiusM = { value = 70 }, ambientLeadSeconds = { value = 240 },
    ambientHoldSeconds = { value = 180 },
    ambientCrowd = { value = 1.0 }, ambientTraffic = { value = 1.0 }, ambientPolice = { value = true },
    ambientVanillaSuppress = { value = true },
}) }

dofile(root .. "/ncm/online/resources/ncm_world/server/ambient.lua")

local function ownedCount()
    local cars, peds = 0, 0
    for _, e in pairs(NcmAmbient.owned) do
        if e.kind == "vehicle" then cars = cars + 1 else peds = peds + 1 end
    end
    return cars, peds
end

local function tick() NcmAmbient.tick(); drain() end

-- ---------------------------------------------------------------- it populates around a player
roster[1] = { x = 0, y = 0, z = 10, bucket = 0 }
math.randomseed(7)
tick()
local cars, peds = ownedCount()
check("a joined player gets ambient population", cars + peds == 3)

-- KB-238: a car comes up EMPTY; its driver is seated only after a client has held it for ambientSeatDelayMs
do
    local before = {}
    for k in pairs(NcmAmbient.owned) do before[k] = true end
    local fresh
    for _ = 1, 10 do
        NcmAmbient.tick()
        for k, e in pairs(NcmAmbient.owned) do if not before[k] and e.kind == "vehicle" then fresh = e end end
        if fresh then break end
        drain()
        for k in pairs(NcmAmbient.owned) do before[k] = true end
    end
    check("a new ambient car comes up with no driver seated", fresh ~= nil and fresh.npcId == nil and attached[fresh.vehicleId] == nil)
    drain()
    check("...and has one once a client has held it past the delay", fresh ~= nil and fresh.npcId ~= nil
        and attached[fresh.vehicleId] == fresh.npcId and joined[fresh.vehicleId] == true)
end
for _ = 1, 6 do tick() end
cars, peds = ownedCount()
check("the per-player cap holds", cars <= 2 and peds <= 3)
check("every ambient car is enrolled in traffic, not parked", (function()
    for _, e in pairs(NcmAmbient.owned) do
        if e.kind == "vehicle" and not joined[e.vehicleId] then return false end
    end
    return true
end)())
check("every ambient car has an attached driver", (function()
    for _, e in pairs(NcmAmbient.owned) do
        if e.kind == "vehicle" and attached[e.vehicleId] ~= e.npcId then return false end
    end
    return true
end)())
check("every ambient pedestrian was told to wander", (function()
    for _, e in pairs(NcmAmbient.owned) do
        if e.kind == "ped" and tasks[e.npcId] ~= "wander" then return false end
    end
    return true
end)())
check("nothing was spawned within the no-pop radius of the player", (function()
    for _, e in pairs(NcmAmbient.owned) do
        if math.sqrt(e.x * e.x + e.y * e.y) < 110 then return false end
    end
    return true
end)())

-- ---------------------------------------------------------------- vanilla density is server-asserted
check("the vanilla population switch was set for the player's bucket", population[0] ~= nil)
check("...to the open policy while no race is due", population[0].crowd == 1.0)
local callsAfterFirst = populationCalls
for _ = 1, 3 do tick() end
check("an unchanged policy is not re-asserted every tick", populationCalls == callsAfterFirst)

-- ---------------------------------------------------------------- the race corridor
-- Put everything we own onto a line, then publish a race down that line starting in two minutes.
local placed = {}
for _, e in pairs(NcmAmbient.owned) do
    e.x, e.y = 1200, 0
    if e.vehicleId then vehicles[e.vehicleId].x, vehicles[e.vehicleId].y = 1200, 0 end
    if e.npcId and npcs[e.npcId] then npcs[e.npcId].x, npcs[e.npcId].y = 1200, 0 end
    placed[#placed + 1] = e.key
end
check("the fixture put something in the corridor's path", #placed > 0)

GlobalState.ncmCalendar = { next = { {
    eventId = "e1", routeId = "r1", startsAt = clock + 120, state = "entry_open", entries = 2,
    venue = { x = 1000, y = 0, z = 10 }, finish = { x = 1600, y = 0, z = 10 },
} } }

-- The player is standing right there, so nothing may vanish yet.
roster[1] = { x = 1200, y = 30, z = 10, bucket = 0 }
tick()
check("a corridor entity in plain sight is NOT despawned", (function()
    for _, k in ipairs(placed) do if NcmAmbient.owned[k] then return true end end
    return false
end)())
check("...and the hold is reported rather than looking like a failure",
    logged("left standing this tick because somebody is") ~= nil)
-- THE GUARD, and the reason it exists. A corridor is in its window essentially all the time on the
-- shipped race cadence, and the vanilla switch has no radius -- so emptying the shared bucket for one
-- would leave the city permanently empty, which is this service's own purpose inverted.
check("a held corridor does NOT empty the shared world bucket", population[0].crowd == 1.0)
check("...and leaves its police alone too", population[0].police == true)

-- Walk the player away. Now it is out of sight and out of projection, and it must go.
roster[1] = { x = 1200, y = 900, z = 10, bucket = 0 }
tick()
check("a corridor entity nobody can see is despawned", (function()
    for _, k in ipairs(placed) do if NcmAmbient.owned[k] then return false end end
    return true
end)())
check("the despawn reached the platform, not just the registry", (function()
    for _, v in pairs(vehicles) do if v.x == 1200 and v.y == 0 then return false end end
    for _, n in pairs(npcs) do if n.x == 1200 and n.y == 0 then return false end end
    return true
end)())

-- ---------------------------------------------------------------- a live session uses its OWN gates
-- The calendar describes a route in the abstract; a running session publishes the line race control
-- actually laid out. Where both exist the gates must win, or a reversed or shortened session would be
-- cleared along a road it is not using.
GlobalState.ncmCalendar = { next = {} }
GlobalState.ncmSessions = { serverNow = clock, s1 = {
    sessionId = "s1", eventId = "e1", routeId = "r1", phase = "running", startsAt = clock - 30,
    gates = {
        { index = 1, x = 0, y = 5000, z = 10 },
        { index = 2, x = 600, y = 5000, z = 10 },
    },
} }
local held = NcmAmbient.corridors(clock)
check("a running session holds a corridor", #held == 1)
check("...built from its own gates, not the route id", held[1].id == "session:s1")
check("...covering the whole line between them, not just the gate points",
    NcmCore.get("world.ambient").inCorridor(held, { x = 300, y = 5000 }) ~= nil)
check("...and not the road beside it", NcmCore.get("world.ambient").inCorridor(held, { x = 300, y = 5200 }) == nil)

GlobalState.ncmSessions.s1.phase = "complete"
GlobalState.ncmSessions.s1.completedAt = clock - (180 + 5)
check("a finished session releases its corridor once the hold expires", #NcmAmbient.corridors(clock) == 0)
GlobalState.ncmSessions = {}
tick()

-- ---------------------------------------------------------------- a Paddock race holds its line (KB-223)
-- ncm_paddock publishes the races a player is near; without them the service spawned its own traffic into the
-- roundabout all through every oval.
GlobalState.ncmPaddockRaces = { { id = "pr-x", routeId = "oval_x", startsAt = clock + 60, points = {
    { x = 100, y = 7000, z = 10 }, { x = 0, y = 7100, z = 10 }, { x = -100, y = 7000, z = 10 }, { x = 0, y = 6900, z = 10 }, { x = 100, y = 7000, z = 10 } } } }
local pheld = NcmAmbient.corridors(clock)
check("a Paddock race about to start holds a corridor", #pheld == 1 and pheld[1].id == "paddock:pr-x")
check("...over its ring, not just its points", NcmCore.get("world.ambient").inCorridor(pheld, { x = 50, y = 7050 }) ~= nil)
GlobalState.ncmPaddockRaces[1].startsAt = clock + 3600
check("...but not an hour out", #NcmAmbient.corridors(clock) == 0)
GlobalState.ncmPaddockRaces = {}

-- ---------------------------------------------------------------- a projected entity is protected
-- Same geometry, but a client reports it as rendered: distance alone must not be enough. A PED: a car past
-- ambientRetireM goes watched or not (L247, KB-238 -- its seated driver at a client's streaming edge).
roster[1] = { x = 1200, y = 900, z = 10, bucket = 0 }
tick()
local guarded = nil
for _, e in pairs(NcmAmbient.owned) do
    if e.npcId and e.kind == "ped" then
        e.x, e.y = 1200, 0
        npcs[e.npcId].x, npcs[e.npcId].y = 1200, 0
        npcs[e.npcId].readyClients = 1        -- somebody's client is drawing this
        if e.vehicleId then vehicles[e.vehicleId].x, vehicles[e.vehicleId].y = 1200, 0 end
        guarded = e.key
        break
    end
end
check("the fixture found something to protect", guarded ~= nil)
tick()
check("an entity a client is still projecting survives the corridor", NcmAmbient.owned[guarded] ~= nil)
npcs[NcmAmbient.owned[guarded].npcId].readyClients = 0
tick()
check("...and goes the moment that projection drops", NcmAmbient.owned[guarded] == nil)

-- ---------------------------------------------------------------- the corridor releases
GlobalState.ncmCalendar = { next = {} }
GlobalState.ncmSessions = {}
tick()
check("the shared bucket's vanilla population was never disturbed at all", population[0].crowd == 1.0)
check("...and its police never left", population[0].police == true)

-- ---------------------------------------------------------------- a dedicated race bucket IS suppressed
-- The same switch in a bucket a race has to itself is exactly right: the only players it can reach are
-- the ones racing. This is the case `IDEA-638` would put into production.
roster[9] = { x = 0, y = 0, z = 10, bucket = 7 }
GlobalState.ncmCalendar = { next = { {
    eventId = "e7", routeId = "r7", startsAt = clock + 120, state = "entry_open", entries = 2,
    venue = { x = 0, y = 0, z = 10 }, finish = { x = 600, y = 0, z = 10 },
} } }
tick()
check("a bucket a race has to itself IS suppressed", population[7] ~= nil and population[7].crowd == 0)
check("...and the shared bucket beside it still is not", population[0].crowd == 1.0)
GlobalState.ncmCalendar = { next = {} }
tick()
check("the dedicated bucket gets its city back when the corridor releases", population[7].crowd == 1.0)
roster[9] = nil

-- ---------------------------------------------------------------- no ground, no spawn
local before = select(1, ownedCount()) + select(2, ownedCount())
groundAt = function() return nil end          -- water, a void, an unstreamed sector
roster[2] = { x = 9000, y = 9000, z = 10, bucket = 0 }
tick()
local after = select(1, ownedCount()) + select(2, ownedCount())
check("a site with no ground under it creates nothing", after <= before)
check("...and the miss is counted rather than swallowed", NcmAmbient.stats.groundMisses > 0)
groundAt = function() return 10 end
roster[2] = nil

-- ---------------------------------------------------------------- the registry cannot leak
tick()
local victim = next(NcmAmbient.owned)
check("the fixture has something to lose", victim ~= nil)
local v = NcmAmbient.owned[victim]
if v.vehicleId then vehicles[v.vehicleId] = nil end
if v.npcId then npcs[v.npcId] = nil end
tick()
check("an entity the platform has lost is dropped from the registry", NcmAmbient.owned[victim] == nil)

-- ---------------------------------------------------------------- a refused permission is survivable
-- The shape of a missing `world.population`: the switch refuses the moment a corridor asks a bucket to
-- change. It has to be a DEDICATED bucket to ask at all now, since the shared one is never suppressed.
-- The server-owned half must carry on regardless -- it is the half that can be radius-scoped, and losing
-- it to one missing permission would leave no ambient world at all.
populationRefuses = true
roster[9] = { x = 4000, y = 0, z = 10, bucket = 7 }
GlobalState.ncmCalendar = { next = { {
    eventId = "e8", routeId = "r8", startsAt = clock + 120, state = "entry_open", entries = 2,
    venue = { x = 4000, y = 0, z = 10 }, finish = { x = 4600, y = 0, z = 10 },
} } }
local ownedBefore = select(1, ownedCount()) + select(2, ownedCount())
tick()
check("a refused setPopulation does not stop the server-owned half",
    select(1, ownedCount()) + select(2, ownedCount()) >= ownedBefore)
check("...and names the permission in the log", logged("world.population") ~= nil)
-- A refusal must not be cached as success, or the retry never happens.
populationRefuses = false
tick()
check("a refusal is retried rather than remembered as done",
    population[7] ~= nil and population[7].crowd == 0)
GlobalState.ncmCalendar = { next = {} }
roster[9] = nil
tick()

-- ---------------------------------------------------------------- stopping cleans up after itself
tick()
check("there is something to clean up", next(NcmAmbient.owned) ~= nil)
TriggerEvent("onResourceStop", "ncm_world"); drain()
check("stopping removes every ambient entity", next(NcmAmbient.owned) == nil)
check("...and hands the world back its vanilla population", population[0] ~= nil and population[0].crowd == 1.0)

-- ---------------------------------------------------------------- the console read
commands["ncm.ambient"](0, { "status" }); drain()
check("ncm.ambient reports without throwing", logged("ambient: ") ~= nil)

realPrint(("ambient host: %d passed, 0 failed"):format(passed))
