-- The Scanner's server half (`ncm_league/server/collection.lua`, `L197`) run against deterministic doubles.
--
-- The lock and admission rules are proved by ncm/core/tests/test_scanner.lua. What is only provable HERE is the
-- host: that every query is ANSWERED (a query with no reply leaves the reticle on "READING..." forever, the
-- first live failure, 2026-09-28), that a networked ambient car resolves from the server's own snapshot, that a
-- scan writes through `revealIdentity(source = "scanner")`, and that an unknown machine's name never crosses the
-- wire before an admitted scan.
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

local events, queue, replies = {}, {}, {}
function AddEventHandler(name, fn) events[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterCommand() end
function CreateThread(fn) queue[#queue + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function TriggerEvent(name, ...) if events[name] then events[name](...) end end
function TriggerClientEvent(name, pid, body) replies[#replies + 1] = { name = name, pid = pid, body = body } end
function print(s) logs[#logs + 1] = tostring(s) end

local function drain()
    local guard = 0
    while #queue > 0 and guard < 200 do
        guard = guard + 1
        local co = table.remove(queue, 1)
        local ok, err = coroutine.resume(co)
        assert(ok, err)
        if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end
    end
end

-- A handler runs inside a coroutine on the host (MySQL `.await` yields), so the harness does the same.
local function fire(name, pid, ...)
    source = pid
    local args = { ... }
    local co = coroutine.create(function() events[name]((table.unpack or unpack)(args)) end)
    local ok, err = coroutine.resume(co)
    assert(ok, err)
    drain()
end

local function lastReply()
    return replies[#replies] and replies[#replies].body or nil
end

-- ---------------------------------------------------------------- doubles
local clock = 1789920000
local vehicles = {
    [41] = { record = "Vehicle.v_standard2_makigai_maimai", bucket = 0, x = 100, y = 0, z = 0 },   -- ambient, 20 m
    [42] = { record = "Vehicle.v_standard2_archer_hella", bucket = 0, x = 400, y = 0, z = 0 },     -- ambient, far
}
local players = { [1] = { bucket = 0, fresh = true, position = { x = 80, y = 0, z = 0 } } }
local discovered = {}   -- vehicle_key -> row

Open77 = {
    time = { unix = function() return clock end },
    vehicles = { get = function(id) local v = vehicles[id]; if not v then return nil end
        return { record = v.record, bucket = v.bucket, x = v.x, y = v.y, z = v.z } end },
    players = { get = function(id) return players[id] end, all = function() return { 1 } end },
}
MySQL = {
    query = { await = function(q)
        if q:find("FROM vehicle_discovery") then
            local rows = {}
            for key, r in pairs(discovered) do rows[#rows + 1] = { vehicle_key = key, first_discovered_at = r.at,
                last_encounter_at = r.at, encounter_count = 1, discovery_method = r.method } end
            return rows
        end
        return {}
    end },
    insert = { await = function() return 1 end },
    single = { await = function() return nil end },
    transaction = { await = function(list)
        for _, stmt in ipairs(list) do
            if stmt.query:find("INSERT INTO vehicle_discovery") then
                discovered[stmt.values[3]] = { at = stmt.values[4], method = stmt.values[7] }
            end
        end
        return true
    end },
}
NcmCalendar = { serverId = function() return "test" end,
    resolveDriver = function(pid) return pid == 1 and { ncmDriverId = "driver-000000001" } or nil end }
NcmOwnership = { keys = function() return {} end, list = function() return {} end }
NcmComms = { send = function() end }
NcmStream = { send = function() end }

local Core = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
dofile(root .. "/ncm/online/resources/ncm_league/server/collection.lua")

check("the scanner's two net events are registered", events["ncm:scanner.query"] and events["ncm:scanner.scan"])

-- 1. A networked ambient car the driver has never seen: answered, indexable, unknown, and NAMELESS.
fire("ncm:scanner.query", 1, { token = "1", kind = "networked", vehicleId = 41, distance = 20 })
local r = lastReply()
check("a query about an ambient car is answered", r and r.token == "1" and r.phase == "query")
check("...as an indexable, unknown machine", r and r.indexable == true and r.known == false)
check("...without its name (fog of war on the wire)", r and r.label == nil)

-- 2. Every query is answered, even a burst: a silent drop strands the reticle on READING forever.
clock = clock + 2
local before, busy = #replies, 0
for i = 1, 30 do fire("ncm:scanner.query", 1, { token = "b" .. i, kind = "networked", vehicleId = 41, distance = 20 }) end
for i = before + 1, #replies do if replies[i].body.busy then busy = busy + 1 end end
check("a burst of 30 queries in one second gets 30 answers", #replies - before == 30)
check("...and the ones over budget are answered 'busy', never dropped", busy == 10)
clock = clock + 2

-- 3. The scan writes, names it, and a second query now knows it.
fire("ncm:scanner.scan", 1, { token = "s1", kind = "networked", vehicleId = 41, distance = 20 })
r = lastReply()
check("an in-range networked scan is admitted as server_measured",
    r and r.phase == "scan" and r.ok == true and r.basis == "server_measured")
check("...names the machine and marks it a first discovery", r and r.first == true and type(r.label) == "string" and r.label ~= "")
check("...and writes the discovery with method 'scanner'", discovered["makigai_maimai"] ~= nil
    and discovered["makigai_maimai"].method == "scanner")
fire("ncm:scanner.query", 1, { token = "2", kind = "networked", vehicleId = 41, distance = 20 })
r = lastReply()
check("the next query knows it, by name", r and r.known == true and r.label ~= nil)

clock = clock + 2
-- 4. Range is the server's own: a far car is refused whatever the client claims.
fire("ncm:scanner.scan", 1, { token = "s2", kind = "networked", vehicleId = 42, distance = 5 })
r = lastReply()
check("a far networked car is refused out_of_range despite a claimed 5 m", r and r.ok == false and r.reason == "out_of_range")

-- 5. A vanilla car by record key: attested, then rate-limited.
local Scanner = Core.get("competition.scanner")
fire("ncm:scanner.scan", 1, { token = "v1", kind = "vanilla", recordKey = Scanner.recordKey("Vehicle.v_standard2_villefort_cortes"), distance = 15 })
r = lastReply()
check("a vanilla catalogue car scans as client_attested", r and r.ok == true and r.basis == "client_attested")
fire("ncm:scanner.scan", 1, { token = "v2", kind = "vanilla", recordKey = Scanner.recordKey("Vehicle.v_standard2_thorton_colby"), distance = 15 })
r = lastReply()
check("a second attested scan inside 20 s cools down", r and r.ok == false and r.reason == "attested_too_soon")
fire("ncm:scanner.query", 1, { token = "v3", kind = "vanilla", recordKey = "123", distance = 15 })
r = lastReply()
check("an unknown record key is answered, not dropped", r and r.token == "v3" and r.indexable == false)

-- 6. Garbage is answered too.
fire("ncm:scanner.query", 1, "nonsense")
check("a malformed query is answered rather than ignored", lastReply() and lastReply().phase == "query")

realPrint(("scanner host: %d passed, 0 failed"):format(passed))
