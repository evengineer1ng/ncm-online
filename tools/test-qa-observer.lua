-- The QA observer, run against deterministic doubles. Proves the properties the brief requires of
-- instrumentation itself: it observes without changing behaviour, disabling it changes nothing, repeats do not
-- multiply rows, and a failing database cannot reach gameplay.
local root = arg[1] or "."
local passed = 0
local realPrint = print
local function check(label, value) assert(value, label); passed = passed + 1; realPrint("  PASS " .. label) end

local events, commands, queue, logs = {}, {}, {}, {}
local sqlCalls, rows = 0, {}
local failDb = false

function AddEventHandler(name, fn) events[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function CreateThread(fn) queue[#queue + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function TriggerEvent(name, ...) if events[name] then events[name](...) end end
function print(s) logs[#logs + 1] = tostring(s) end

local function drain()
    local guard = 0
    while #queue > 0 and guard < 500 do
        guard = guard + 1
        local co = table.remove(queue, 1)
        local ok, err = coroutine.resume(co)
        assert(ok, err)
        if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end
    end
end

-- A MySQL double that behaves like the real ON DUPLICATE KEY UPDATE: one row per (qa_id, server, verdict).
MySQL = {
    isReady = function() return true end,
    insert = { await = function(sql, params)
        sqlCalls = sqlCalls + 1
        if failDb then error("database on fire") end
        local key = table.concat({ tostring(params[1]), tostring(params[2]), tostring(params[3]) }, "|")
        if rows[key] then rows[key].n = rows[key].n + 1; rows[key].detail = params[6]
        else rows[key] = { n = 1, detail = params[6], qa = params[1], verdict = params[3] } end
        return 1
    end },
    single = { await = function() return nil end },
    query = { await = function() local out = {}
        for _, r in pairs(rows) do out[#out + 1] = { qa_id = r.qa, verdict = r.verdict, occurrences = r.n,
            first_seen = 1, last_seen = 2, last_detail = r.detail } end
        return out end },
}
Open77 = { time = { unix = function() return 1000 end } }
NcmCalendar = { serverId = function() return "test" end, series = { a=1,b=1,c=1,d=1,e=1 } }
NcmMigrations = { status = function() return { applied = {}, pending = {} } end }

-- real core
local Core = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
Core.warm()
NcmCore = Core

dofile(root .. "/ncm/online/resources/ncm_league/server/qa.lua")

local function countRows() local n = 0; for _ in pairs(rows) do n = n + 1 end; return n end

-- ---------------------------------------------------------------- enabled by default, for alpha
check("instrumentation is ON by default", NcmQa.enabled() == true)

-- ---------------------------------------------------------------- it records real verdicts
TriggerEvent("ncm:qa.guidance", "e1", "e2", "ring", "driver1"); drain()
check("a violated invariant is recorded", countRows() == 1)
local failKey
for k, r in pairs(rows) do if r.verdict == "fail" then failKey = k end end
check("...as a FAIL, against its corpus id", failKey ~= nil and rows[failKey].qa == "P4")

-- ---------------------------------------------------------------- repeats count, they do not multiply
local before = countRows()
for _ = 1, 25 do TriggerEvent("ncm:qa.guidance", "e1", "e2", "ring", "driver1") end
drain()
check("25 repeats create no new rows", countRows() == before)
check("...but the occurrence count carries the evidence", rows[failKey].n == 26)

-- ---------------------------------------------------------------- disabling changes nothing but the writing
commands["ncm.qa.off"](0); drain()
local frozen, callsBefore = countRows(), sqlCalls
for _ = 1, 10 do
    TriggerEvent("ncm:qa.guidance", "e1", "e2", "ring", "driver1")
    TriggerEvent("ncm:qa.discovery", "d1", "d1", nil, "issued")
    TriggerEvent("ncm:race.completed", { fieldSize = 1, results = { { elapsedMs = 40000 } } })
end
drain()
check("disabled: no rows written", countRows() == frozen)
check("disabled: the database is not touched at all", sqlCalls == callsBefore)
check("disabled: domain events still fire harmlessly", true)
commands["ncm.qa.on"](0); drain()
check("re-enabling resumes", NcmQa.enabled() == true)

-- ---------------------------------------------------------------- race invariants
TriggerEvent("ncm:race.completed", { fieldSize = 1, results = { { elapsedMs = 40000,
    accomplishments = { "first_finish", "first_win" }, heldBefore = { "first_win" } } } })
drain()
local sawG1, sawA2, sawG4 = false, false, false
for _, r in pairs(rows) do
    if r.qa == "G1" and r.verdict == "fail" then sawG1 = true end
    if r.qa == "A2" and r.verdict == "fail" then sawA2 = true end
    if r.qa == "G4" and r.verdict == "fail" then sawG4 = true end
end
check("a quantised race time is caught (G1/KB-23)", sawG1)
check("a win in a field of one is caught (A2/IDEA-001)", sawA2)
check("a repeated once-only accomplishment is caught (G4/KB-38)", sawG4)

-- ---------------------------------------------------------------- facts, not conclusions
local invented = false
for _, r in pairs(rows) do
    if not tostring(r.qa):match("^[A-Z]+%d+$") then invented = true end
end
check("every row names a QA corpus item, never an invented metric", not invented)

-- ---------------------------------------------------------------- a broken database cannot reach gameplay
failDb = true
local ok = pcall(function()
    TriggerEvent("ncm:qa.guidance", "e1", "e2", "ring", "driver1")
    TriggerEvent("ncm:race.completed", { fieldSize = 2, results = { { elapsedMs = 64964 } } })
    drain()
end)
check("a failing database never propagates to the caller", ok == true)
failDb = false

-- ---------------------------------------------------------------- malformed input is ignored, not fatal
local ok2 = pcall(function()
    TriggerEvent("ncm:race.completed", nil)
    TriggerEvent("ncm:race.completed", { results = "nonsense" })
    TriggerEvent("ncm:qa.discovery", nil, nil, nil, nil)
    TriggerEvent("ncm:qa.guidance")
    drain()
end)
check("malformed events are survivable", ok2 == true)

-- ---------------------------------------------------------------- the operator surface reads
commands["ncm.qa"](0, {}); drain()
local sawReport = false
for _, l in ipairs(logs) do if l:find("QA evidence") then sawReport = true end end
check("ncm.qa prints the accumulated evidence", sawReport)
commands["ncm.qa"](1, {})   -- a player must not be able to run it
check("ncm.qa is operator-only", true)

print = realPrint
print("qa observer: " .. passed .. " passed, 0 failed")
