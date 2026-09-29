-- NCM Chrome's server host (`ncm_world/server/chrome.lua`) run against deterministic doubles of OPEN//77's hacking,
-- cyberware, combat and vehicle natives. The roster and composition are proved by ncm/core/tests/test_chrome.lua;
-- this proves the host: that the deck and implants are defined cosmetic, that a slotted hack reaches
-- `Open77.hacking.start` against the DRIVER while its consequence lands on the CAR, that AI traffic runs the NCM
-- route with a lock heartbeat, that governor hacks reach the handling layer only on a Carrier-bound Machine, that
-- purge strips the car, and that the PvP scope never lets a weapon through.
local root = arg[1] or "."
local passed = 0
local realPrint = print
local logs = {}
local function check(label, value)
    if not value then
        realPrint("  FAIL " .. label)
        for _, l in ipairs(logs) do realPrint("    log| " .. l) end
        error(label, 0)
    end
    passed = passed + 1; realPrint("  PASS " .. label)
end
local function logged(pattern)
    for _, l in ipairs(logs) do if l:find(pattern, 1, true) then return l end end
end

local events, queue, toClient, toServerLocal = {}, {}, {}, {}
function AddEventHandler(name, fn) events[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterCommand() end
function CreateThread(fn) queue[#queue + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function TriggerEvent(name, ...) if events[name] then events[name](...) end end
function TriggerClientEvent(name, pid, body) toClient[#toClient + 1] = { name = name, pid = pid, body = body } end
function print(s) logs[#logs + 1] = tostring(s) end
local unpack = table.unpack or unpack

local clock = 1000.0   -- seconds
local function advance(ms) clock = clock + ms / 1000 end

-- Run every queued coroutine once per "frame" (the host's main loop Waits TICK_MS each tick).
local function frames(n)
    for _ = 1, n or 1 do
        local q = queue; queue = {}
        for _, co in ipairs(q) do
            local ok, err = coroutine.resume(co)
            assert(ok, err)
            if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end
        end
    end
end

local function fire(name, pid, ...)
    source = pid
    local args = { ... }
    local co = coroutine.create(function() events[name](unpack(args)) end)
    local ok, err = coroutine.resume(co)
    assert(ok, err)
end

local function lastState(pid)
    for i = #toClient, 1, -1 do
        if toClient[i].name == "ncm:chrome.state" and toClient[i].pid == pid then return toClient[i].body end
    end
end
local function presented(pid, phase)
    for i = #toClient, 1, -1 do
        local c = toClient[i]
        if c.name == "ncm:chrome.present" and c.pid == pid and c.body.phase == phase then return c.body end
    end
end

-- ---------------------------------------------------------------- doubles
local calls = { define = {}, install = {}, start = {}, purge = {}, cancel = {}, scopes = {}, engine = {}, tires = {},
                lights = {}, health = {}, explode = {}, recompute = {} }
local players = {
    [1] = { bucket = 0, ready = true, position = { x = 0, y = 0, z = 0 }, seat = 101 },   -- attacker, in car 101
    [2] = { bucket = 0, ready = true, position = { x = 30, y = 0, z = 0 }, seat = 102 },  -- defender, driving 102
}
local vehicles = {
    [101] = { x = 0, y = 0, z = 0, driver = 1, health = 1 },
    [102] = { x = 30, y = 0, z = 0, driver = 2, health = 1 },     -- a player's NCM Machine
    [201] = { x = 40, y = 0, z = 0, driver = nil, health = 1 },   -- AI traffic
    [202] = { x = 500, y = 0, z = 0, driver = nil, health = 1 },  -- AI traffic, far away
}
local nextAction, revision, arbiter = 7000, 1, nil
local transitions = {}

Open77 = {
    time = { unix = function() return clock end },
    players = {
        all = function() return { 1, 2 } end,
        get = function(id) return players[id] end,
        getVehicleSeat = function(id) return players[id] and { vehicleId = players[id].seat } end,
    },
    vehicles = {
        get = function(id) local v = vehicles[id]; return v and { x = v.x, y = v.y, z = v.z } or nil end,
        getDriver = function(id) return vehicles[id] and vehicles[id].driver end,
        setEngine = function(id, on) calls.engine[#calls.engine + 1] = { id, on }; return true end,
        breakTire = function(id, i) calls.tires[#calls.tires + 1] = { id, i }; return true end,
        getLights = function() return "on" end,
        setLights = function(id, m) calls.lights[#calls.lights + 1] = { id, m }; return true end,
        breakLight = function() return true end,
        repairAllLights = function() return true end,
        repairAllTires = function() return true end,
        getHealth = function(id) return vehicles[id].health end,
        setHealth = function(id, h) vehicles[id].health = h; calls.health[#calls.health + 1] = { id, h }; return true end,
        explode = function(id) calls.explode[#calls.explode + 1] = id; return true end,
    },
    hacking = {
        define = function(d) calls.define[#calls.define + 1] = d; return { ok = true } end,
        defineIce = function(d) calls.define[#calls.define + 1] = d; return { ok = true } end,
        definePurge = function(d) calls.define[#calls.define + 1] = d; return { ok = true } end,
        start = function(a, t, def, grade, o)
            nextAction = nextAction + 1
            calls.start[#calls.start + 1] = { a = a, t = t, def = def, grade = grade, op = o and o.operationId }
            return { ok = true, actionId = nextAction }
        end,
        purge = function(a, t, def, grade) calls.purge[#calls.purge + 1] = { a = a, t = t }; return { ok = true } end,
        cancel = function(id) calls.cancel[#calls.cancel + 1] = id; return { ok = true } end,
    },
    cyberware = {
        define = function(d) calls.define[#calls.define + 1] = d; return { ok = true } end,
        current = function() return { revision = revision } end,
        newOperationId = function() revision = revision + 1; return "op-" .. revision end,
        install = function(pid, id, grade) calls.install[#calls.install + 1] = { pid = pid, id = id, grade = grade }
            return { ok = true } end,
    },
    combat = {
        createScope = function(def) calls.scopes[#calls.scopes + 1] = def; return "scope-" .. #calls.scopes end,
        removeScope = function() return true end,
        onDamage = function(fn) arbiter = fn; return fn end,
    },
}
MySQL = { insert = { await = function() return 1 end } }
NcmIdentity = { get = function(pid) return { ncmDriverId = "driver-" .. pid } end, serverId = function() return "test" end }
NcmVehicleAccess = {
    liveAssets = function() return { { assetId = "asset-102", vehicleId = 102, pid = 2 } } end,
    liveAsset = function(a) return a == "asset-102" and { assetId = a, vehicleId = 102, pid = 2 } or nil end,
}
NcmHandling = { recompute = function(assetId) calls.recompute[#calls.recompute + 1] = assetId; return true end }

local Core = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
dofile(root .. "/ncm/online/resources/ncm_world/server/chrome.lua")

-- Boot: the host waits 2 s, defines, equips, then ticks.
frames(1); advance(2000); frames(2)
check("the deck, Self-ICE, purge and three implants are defined", #calls.define == 6)
local deckDef = calls.define[1]
local allCosmetic = true
for _, g in ipairs(deckDef.grades) do if not (g.cosmetic and g.damage == 0) then allCosmetic = false end end
check("...and every deck grade is cosmetic with zero damage", deckDef.id == "ncm.chrome" and allCosmetic)
check("present players are equipped (ICE, purge, deck)", #calls.install >= 3)
advance(5000); frames(1)
check("one PvP scope admits the bucket's players", #calls.scopes == 1 and #calls.scopes[1].players == 2)
check("the arbiter refuses a real player-on-player hit", arbiter and arbiter({ attacker = 1, victim = 2, amount = 25 }) == false)
check("...but lets a zero-amount event and NPC damage through",
    arbiter({ attacker = 1, victim = 2, amount = 0 }) == nil and arbiter({ attacker = 99, victim = 2, amount = 25 }) == nil)

-- Platform route: a slotted ENGINE CUT against the driven car 102.
fire("ncm:chrome.select", 1, "engine_cut")
check("selecting a hack slots it into the deck", calls.install[#calls.install].grade == "engine_cut")
fire("ncm:chrome.start", 1, { token = "t1", hack = "engine_cut", vehicleId = 102 })
check("the upload goes to the platform against the DRIVER", calls.start[1] and calls.start[1].t == 2
    and calls.start[1].def == "ncm.chrome" and calls.start[1].grade == "engine_cut")
local actionId = nextAction
events["onHackingTransition"]('{"actionId":' .. actionId .. ',"definition":"ncm.chrome","phase":"upload_progress","startedAt":' ..
    math.floor(clock * 1000) .. ',"deadline":' .. math.floor(clock * 1000 + 2500) .. '}')
check("the attacker sees UPLOAD and the defender sees INCOMING", presented(1, "upload") and presented(2, "incoming"))
events["onHackingTransition"]('{"actionId":' .. actionId .. ',"definition":"ncm.chrome","phase":"impact"}')
check("impact kills the defender's ENGINE, not the defender", calls.engine[#calls.engine][1] == 102
    and calls.engine[#calls.engine][2] == false)
advance(3100); frames(1)
check("...and restarts it when the effect ends", calls.engine[#calls.engine][1] == 102 and calls.engine[#calls.engine][2] == true)

-- Governor hacks: POWER SURGE lands in the handling layer of the bound Machine.
fire("ncm:chrome.select", 1, "power_surge")
fire("ncm:chrome.start", 1, { token = "t2", hack = "power_surge", vehicleId = 102 })
events["onHackingTransition"]('{"actionId":' .. nextAction .. ',"definition":"ncm.chrome","phase":"impact"}')
local c = NcmChrome.contributorFor("asset-102")
check("POWER SURGE pushes the chrome layer: drive up, grip down, top speed up",
    c and c.driveScale == 1.6 and c.gripScale == 0.8 and c.topSpeedScale == 1.15)
check("...and the Machine is republished to its Carrier", calls.recompute[#calls.recompute] == "asset-102")
advance(5200); frames(1)
check("...and it expires", NcmChrome.contributorFor("asset-102") == nil)

-- LIMITER caps the governor target against the authored baseline.
advance(30000)
fire("ncm:chrome.select", 1, "limiter")
fire("ncm:chrome.start", 1, { token = "t3", hack = "limiter", vehicleId = 102 })
events["onHackingTransition"]('{"actionId":' .. nextAction .. ',"definition":"ncm.chrome","phase":"impact"}')
check("LIMITER caps a 151 km/h Machine at 106 km/h", NcmChrome.capKph("asset-102", 151) == 106)

-- Purge: the defender strips their own car.
fire("ncm:chrome.start", 2, { token = "p1", hack = "purge" })
check("the defender's PURGE clears the platform upload and their car", calls.purge[#calls.purge].a == 2
    and NcmChrome.capKph("asset-102", 151) == nil)

-- AI traffic: the NCM route.
fire("ncm:chrome.start", 1, { token = "a1", hack = "limiter", vehicleId = 201 })
check("a governor hack on AI traffic is refused by name", lastState(1).reason == "needs_driven_ncm_machine")
fire("ncm:chrome.start", 1, { token = "a2", hack = "tire_sabotage", vehicleId = 202 })
check("an AI car out of range is refused", lastState(1).reason == "out_of_range")
advance(60000)
fire("ncm:chrome.start", 1, { token = "a3", hack = "tire_sabotage", vehicleId = 201 })
check("TIRE SABOTAGE on AI traffic starts on the NCM route", lastState(1).result == "uploading" and lastState(1).route == "ncm")
for _ = 1, 16 do advance(200); fire("ncm:chrome.hold", 1, 201); frames(1) end
check("with the lock held it lands: a tyre breaks on the AI car", calls.tires[#calls.tires] and calls.tires[#calls.tires][1] == 201)

advance(60000)
fire("ncm:chrome.start", 1, { token = "a4", hack = "blackout", vehicleId = 201 })
for _ = 1, 6 do advance(200); frames(1) end
check("a lost lock interrupts the NCM route", lastState(1).result == "interrupted" and lastState(1).reason == "lock_lost")

-- Releasing the key cancels a platform upload.
advance(60000)
fire("ncm:chrome.select", 1, "blackout")
fire("ncm:chrome.start", 1, { token = "c1", hack = "blackout", vehicleId = 102 })
fire("ncm:chrome.cancel", 1)
local cancelledIt = false
for _, id in ipairs(calls.cancel) do if id == nextAction then cancelledIt = true end end
check("releasing G cancels the platform upload", cancelledIt)

-- Self hacks and refusals.
fire("ncm:chrome.start", 1, { token = "s1", hack = "system_restore" })
check("SYSTEM RESTORE channels on your own car", lastState(1).result == "channel")
advance(3100); frames(1)
check("...and completes", lastState(1).result == "impact" and lastState(1).hack == "system_restore")
fire("ncm:chrome.start", 1, { token = "o1", hack = "explode_everything" })
check("an unknown hack is refused, not crashed", lastState(1).reason == "unknown_hack")
fire("ncm:chrome.start", 1, { token = "o2", hack = "engine_cut", vehicleId = 101 })
check("you cannot hack your own car", lastState(1).reason == "own_vehicle")

realPrint(("chrome host: %d passed, 0 failed"):format(passed))
