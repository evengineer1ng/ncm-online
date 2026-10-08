-- NCM Host SQL gate (L338, doc 55 Â§4): the resources' MariaDB SQL runs on the single-player host's SQLite.
--   1. Every migration (ncm_league/server/schema, manifest order) replays into the schema model without error.
--   2. (LuaJIT + sqlite3.dll) The model syncs into a fresh SQLite database, the migrations' own DML runs, and a
--      second sync is a no-op.
--   3. (LuaJIT + sqlite3.dll) Every literal SQL statement passed to MySQL.* in the resources translates and PREPARES
--      against that database -- syntax, tables and columns all checked by SQLite itself.
--   4. Translator unit cases.
-- Under Lua 5.4 steps 2-3 are skipped (no FFI); the gate runs this file under both interpreters.
--   lua tools/test-host-sql.lua <repo>
local REPO = (arg and arg[1]) or "."
REPO = REPO:gsub("\\", "/")
local HOST = REPO .. "/ncm/host/"
local RES = REPO .. "/ncm/online/resources/"

local T = dofile(HOST .. "sql/translate.lua")
local S = dofile(HOST .. "sql/schema.lua").init(T)

local fails, passes = 0, 0
local function check(cond, fmt, ...)
    if cond then passes = passes + 1 else fails = fails + 1; print("  FAIL " .. string.format(fmt, ...)) end
end

local ctx = { datetime = function() return "2026-10-07 12:00:00" end, unix = function() return 1791388800 end,
    uuid = function() return "00000000-0000-4000-8000-000000000000" end }

-- ------------------------------------------------------------------------------------------------ 4. units
do
    local function tr(s) return (T.dml(s, ctx):gsub("%s+", " ")) end
    check(tr("INSERT IGNORE INTO t (a) VALUES (?)") == "INSERT OR IGNORE INTO t (a) VALUES (?)", "insert ignore: %s", tr("INSERT IGNORE INTO t (a) VALUES (?)"))
    local up = tr("INSERT INTO t (a, b) VALUES (?, ?) ON DUPLICATE KEY UPDATE b = VALUES(b), n = n + 1")
    check(up == "INSERT INTO t (a, b) VALUES (?, ?) ON CONFLICT DO UPDATE SET b = excluded.b, n = n + 1", "upsert: %s", up)
    local sel = tr("INSERT INTO t (a) SELECT x FROM u ON DUPLICATE KEY UPDATE a = VALUES(a)")
    check(sel:find("FROM u WHERE 1 ON CONFLICT", 1, true) ~= nil, "insert-select upsert gets WHERE 1: %s", sel)
    check(tr("SELECT GREATEST(a, 1), LEAST(b, 2), IF(c, 1, 0)") == "SELECT MAX(a, 1), MIN(b, 2), IIF(c, 1, 0)", "scalar fns: %s", tr("SELECT GREATEST(a, 1), LEAST(b, 2), IF(c, 1, 0)"))
    check(tr("SELECT CONCAT(a, '-', b)"):gsub("%s", "") == "SELECT((a)||('-')||(b))", "concat: %s", tr("SELECT CONCAT(a, '-', b)"))
    check(tr("SELECT NOW(), UUID(), UNIX_TIMESTAMP()") == "SELECT '2026-10-07 12:00:00', '00000000-0000-4000-8000-000000000000', 1791388800", "clock fns: %s", tr("SELECT NOW(), UUID(), UNIX_TIMESTAMP()"))
    check(tr([[SELECT "x\'y"]]) == "SELECT 'x''y'", "string normalisation: %s", tr([[SELECT "x\'y"]]))
    local uj = tr("UPDATE a x JOIN b y ON y.id = x.bid SET x.v = y.v, x.n = ? WHERE x.k = ?")
    check(uj == "UPDATE a AS x SET v = y.v, n = ? FROM b AS y WHERE ( y.id = x.bid ) AND ( x.k = ?)", "update join: %s", uj)
    local b = T.bind("SELECT ? , '?' , ?", { "it's", nil, n = 2 }, 2)
    check(b == "SELECT 'it''s' , '?' , NULL", "bind: %s", tostring(b))
    check(select(2, T.bind("SELECT ?", { 1, 2 })) ~= nil and T.bind("SELECT ?", { 1, 2 }) == nil, "bind count mismatch refused")
    check(T.bind("SELECT ?", { 2.5 }) == "SELECT 2.5" and T.bind("SELECT ?", { true }) == "SELECT 1", "bind number/bool")
end

-- ------------------------------------------------------------------------------------------------ 1. replay
local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end

local function loadMigrations()
    local manifest = assert(readFile(RES .. "ncm_league/open77.lua"), "ncm_league manifest")
    local env = setmetatable({}, { __index = _G })
    env.NcmSchema = {}
    local n = 0
    for path in manifest:gmatch('server_script%s+"(server/schema/[^"]+)"') do
        local src = assert(readFile(RES .. "ncm_league/" .. path), path)
        local chunk = assert(load(src, "@" .. path, "t", env))
        chunk(); n = n + 1
    end
    local list = {}
    for i = 1, #env.NcmSchema do list[i] = env.NcmSchema[i] end
    table.sort(list, function(a, b2) return a.version < b2.version end)
    return list, n
end

local migrations, files = loadMigrations()
check(#migrations >= 70 and files == #migrations, "migrations loaded: %d files, %d entries", files, #migrations)
local okReplay, model, dml = pcall(S.replay, migrations)
check(okReplay, "replay: %s", tostring(not okReplay and model or ""))
if not okReplay then print(("host sql: %d pass, %d FAIL"):format(passes, fails)); os.exit(1) end
local tables = #model.order
check(tables >= 130, "model has %d tables", tables)
check(S.table(model, "racing_week_run") and #S.table(model, "racing_week_run").cols >= 8, "racing_week_run carries 064's columns")
check(S.table(model, "ncm_presence") ~= nil and S.table(model, "machine_passport") ~= nil, "068/070 tables present")
local bools = S.booleanColumns(model)

-- ------------------------------------------------------------------------------------------------ 2-3. SQLite
local isJit = type(rawget(_G, "jit")) == "table"
local Driver = dofile(HOST .. "sql/driver_ffi.lua")
local dll = isJit and Driver.locate() or nil
if not isJit then
    print("  (Lua 5.4: SQLite steps skipped -- they run under LuaJIT)")
elseif not dll then
    print("  SKIP SQLite steps: no sqlite3.dll found (set NCM_SQLITE_DLL)")
else
    local d = assert(Driver.open(dll, ":memory:"))
    check(d.version() >= "3.35", "SQLite %s supports upsert without a target (>= 3.35)", d.version())
    local okSync, rep = pcall(S.sync, d, model, 1791388800)
    check(okSync, "sync: %s", tostring(not okSync and rep or ""))
    if okSync then check(#rep.created == tables, "sync created %d of %d tables", #rep.created, tables) end
    -- the migrations' own DML (seed rows, backfills), in order, against the final schema
    local dmlBad = 0
    for _, s in ipairs(dml) do
        local ok, e = pcall(function() d.exec(T.dml(s.sql, ctx)) end)
        if not ok then dmlBad = dmlBad + 1; print(("  migration %03d DML: %s"):format(s.version, tostring(e):sub(1, 220))) end
    end
    check(dmlBad == 0, "%d migration DML statement(s) ran, %d failed", #dml, dmlBad)
    local again = S.sync(d, model, 1791388800)
    check(#again.created == 0 and #again.altered == 0 and #again.rebuilt == 0, "second sync is a no-op")

    -- an appended column takes the fast path; a changed key rebuilds and keeps rows
    local m2 = S.replay(migrations)
    S.apply(m2, "ALTER TABLE racing_week_run ADD COLUMN IF NOT EXISTS ncm_test_note VARCHAR(32) NULL")
    d.exec("INSERT INTO racing_week_run (server_id, run_index, opened_at, state_json, updated_at) VALUES ('sp-test', 1, 1, '{}', 1)")
    local r2 = S.sync(d, m2, 1791388800)
    check(#r2.altered == 1 and #r2.rebuilt == 0, "appended column altered in place (altered %d, rebuilt %d)", #r2.altered, #r2.rebuilt)
    S.apply(m2, "ALTER TABLE racing_week_run MODIFY COLUMN ncm_test_note VARCHAR(64) NOT NULL DEFAULT 'x'")
    local r3 = S.sync(d, m2, 1791388800)
    check(#r3.rebuilt == 1, "modified column rebuilds the table")
    check(d.scalar("SELECT COUNT(*) FROM racing_week_run WHERE server_id = 'sp-test'") == 1, "rebuild kept the row")

    -- 3. corpus: every literal SQL statement in the resources
    local function luaFiles()
        local list = {}
        local h = io.popen('dir /s /b "' .. (RES:gsub("/", "\\")) .. '*.lua" 2>nul')
        for line in h:lines() do
            if not line:find("\\shared\\core\\", 1, true) and not line:find("\\schema\\", 1, true) and not line:find("open77.lua", 1, true) then
                list[#list + 1] = line
            end
        end
        h:close()
        return list
    end
    local corpus, seen = {}, {}
    local function take(file, s)
        s = s:gsub("^%s+", "")
        local w = s:match("^(%a+)")
        w = w and w:upper()
        if not (w == "SELECT" or w == "INSERT" or w == "UPDATE" or w == "DELETE" or w == "REPLACE" or w == "CREATE" or w == "ALTER") then return end
        if seen[s] then return end
        seen[s] = true
        corpus[#corpus + 1] = { file = file, sql = s }
    end
    local function unquote(lit)
        if lit:sub(1, 2) == "[[" then return lit:sub(3, -3) end
        local body = lit:sub(2, -2)
        return (body:gsub("\\(.)", function(c) return ({ n = "\n", t = "\t", ['"'] = '"', ["'"] = "'", ["\\"] = "\\" })[c] or c end))
    end
    local skippedDynamic = 0
    for _, file in ipairs(luaFiles()) do
        local src = readFile(file) or ""
        -- string literals that are the WHOLE first argument of MySQL.x.await(...) or a `query =` field
        for _, pat in ipairs({ "MySQL%.%w+%.await%(%s*()", "query%s*=%s*()" }) do
            for pos in src:gmatch(pat) do
                local lit, after
                if src:sub(pos, pos + 1) == "[[" then
                    local e = src:find("]]", pos + 2, true)
                    if e then lit = src:sub(pos, e + 1); after = e + 2 end
                elseif src:sub(pos, pos) == '"' then
                    local e = pos + 1
                    while e <= #src do
                        local c = src:sub(e, e)
                        if c == "\\" then e = e + 2 elseif c == '"' then break else e = e + 1 end
                    end
                    lit = src:sub(pos, e); after = e + 1
                end
                if lit then
                    local nxt = src:match("^%s*(%S)", after)
                    if nxt == "," or nxt == ")" or nxt == "}" then take(file, unquote(lit)) else skippedDynamic = skippedDynamic + 1 end
                end
            end
        end
    end
    local bad, translated = 0, 0
    -- statements the host deliberately does not translate (handled by a host hook instead); keep this list SHORT
    local HOOKED = {}
    for _, c in ipairs(corpus) do
        local hooked = false
        for _, h in ipairs(HOOKED) do if c.sql:find(h) then hooked = true end end
        if not hooked then
            local okT, out = pcall(T.dml, c.sql, ctx)
            local kind = S.kind(c.sql)
            if kind ~= "dml" then
                -- runtime DDL is applied to the model, never executed raw
                local okA, eA = pcall(S.apply, S.replay(migrations), c.sql)
                if not okA then bad = bad + 1; print(("  DDL %s: %s"):format(c.file:match("resources\\(.*)$") or c.file, tostring(eA):sub(1, 200))) end
            elseif not okT then
                bad = bad + 1; print(("  TRANSLATE %s: %s"):format(c.file:match("resources\\(.*)$") or c.file, tostring(out):sub(1, 200)))
            else
                translated = translated + 1
                local okP, e = d.check(out)
                if not okP then
                    bad = bad + 1
                    print(("  PREPARE %s: %s\n      %s"):format(c.file:match("resources\\(.*)$") or c.file, e, (out:gsub("%s+", " ")):sub(1, 260)))
                end
            end
        end
    end
    check(#corpus >= 400, "corpus has %d statements (%d dynamic skipped)", #corpus, skippedDynamic)
    check(bad == 0, "corpus: %d translated, %d failed", translated, bad)
    print(("  corpus: %d literal statements, %d translated + prepared, %d failed, %d built dynamically (not checked here)")
        :format(#corpus, translated, bad, skippedDynamic))
    d.close()
end

print(("host sql: %d pass, %d FAIL (%d tables, %d boolean columns)"):format(passes, fails, tables, (function() local n = 0; for _ in pairs(bools) do n = n + 1 end; return n end)()))
if fails > 0 then os.exit(1) end
