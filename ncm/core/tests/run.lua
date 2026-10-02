-- ncm-core test runner. Usage: lua run.lua <core-root> [test-name-filter]
-- Loads init.lua, then every MANIFEST.lua entry, then every tests/test_*.lua (each returns a
-- table of name -> function(T)). Exits non-zero on any failure. Runs under Lua 5.4 and LuaJIT.
local unpack = table.unpack or unpack

local root = arg and arg[1]
if not root then
    io.stderr:write("usage: lua run.lua <core-root> [filter]\n")
    os.exit(2)
end
root = root:gsub("[\\/]+$", "")
local filter = arg and arg[2]

local function join(a, b) return a .. "/" .. b end

local function readDir(path)
    -- Portable directory listing without lfs: use the platform's shell.
    local names = {}
    local isWindows = package.config:sub(1, 1) == "\\"
    local cmd
    if isWindows then
        cmd = 'dir /b "' .. path:gsub("/", "\\") .. '" 2>nul'
    else
        cmd = 'ls -1 "' .. path .. '" 2>/dev/null'
    end
    local p = io.popen(cmd)
    if not p then return names end
    for line in p:lines() do
        line = line:gsub("%s+$", "")
        if line ~= "" then names[#names + 1] = line end
    end
    p:close()
    table.sort(names)
    return names
end

-- Load core exactly the way a host does.
local Core = dofile(join(root, "init.lua"))
local manifest = dofile(join(root, "MANIFEST.lua"))
for i = 1, #manifest do
    dofile(join(root, manifest[i]))
end
Core.warm()

-- Harness.
local T = {}
T.root = root            -- the core directory, for tests that read shipped data beside it
local current = { name = "", failures = {} }

local function fail(msg, level)
    local info = debug.getinfo((level or 2) + 1, "Sl")
    local where = info and (info.short_src .. ":" .. tostring(info.currentline)) or "?"
    current.failures[#current.failures + 1] = where .. ": " .. msg
    error("__ncm_test_fail__", 0)
end

local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "table" then
        local parts = {}
        for k, val in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. show(val) end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

function T.ok(cond, msg)
    if not cond then fail(msg or "expected truthy", 2) end
end
-- `truthy`/`falsy` are `ok` and its negation under the names the newer suites reach for. Added because
-- `test_chunks` called both and the harness had neither, so two real assertions were being reported as
-- harness errors rather than as results.
function T.truthy(cond, msg)
    if not cond then fail(msg or "expected truthy", 2) end
end
function T.falsy(cond, msg)
    if cond then fail((msg and (msg .. ": ") or "") .. "expected falsy, got " .. show(cond), 2) end
end
function T.eq(actual, expected, msg)
    if actual ~= expected then
        fail((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
    end
end
function T.neq(actual, unexpected, msg)
    if actual == unexpected then
        fail((msg and (msg .. ": ") or "") .. "did not expect " .. show(unexpected), 2)
    end
end
function T.match(s, pattern, msg)
    if type(s) ~= "string" or not s:match(pattern) then
        fail((msg and (msg .. ": ") or "") .. show(s) .. " does not match " .. pattern, 2)
    end
end
function T.errors(fn, pattern, msg)
    local ok, err = pcall(fn)
    if ok then fail((msg and (msg .. ": ") or "") .. "expected an error", 2) end
    if pattern and not tostring(err):match(pattern) then
        fail((msg and (msg .. ": ") or "") .. "error " .. show(tostring(err)) .. " does not match " .. pattern, 2)
    end
end
T.Core = Core
T.show = show

-- Discover and run tests.
local testDir = join(root, "tests")
local files = {}
for _, name in ipairs(readDir(testDir)) do
    if name:match("^test_.*%.lua$") then files[#files + 1] = name end
end

local total, failed = 0, 0
local version = (jit and jit.version) or _VERSION
print(string.format("ncm-core tests | %s | core %s | %d file(s)", version, Core.VERSION, #files))

for _, file in ipairs(files) do
    local cases = dofile(join(testDir, file))
    local names = {}
    for name in pairs(cases) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local full = file:gsub("%.lua$", "") .. "." .. name
        if not filter or full:find(filter, 1, true) then
            total = total + 1
            current = { name = full, failures = {} }
            local ok, err = pcall(cases[name], T)
            if ok and #current.failures == 0 then
                print("  PASS " .. full)
            else
                failed = failed + 1
                print("  FAIL " .. full)
                for _, f in ipairs(current.failures) do print("       " .. f) end
                if not ok and err ~= "__ncm_test_fail__" then print("       error: " .. tostring(err)) end
            end
        end
    end
end

print(string.format("%d passed, %d failed", total - failed, failed))
os.exit(failed == 0 and 0 or 1)
