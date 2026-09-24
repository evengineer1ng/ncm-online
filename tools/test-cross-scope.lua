-- Cross-scope global references: the defect class that bit three times in one day.
--
-- `ncm_world` and `ncm_league` are SEPARATE RESOURCES with separate Lua VMs, and within a resource the client
-- and server halves are separate again. A global defined in one scope is simply `nil` in another -- so the
-- idiomatic guard
--
--     if NcmOwnership and NcmOwnership.paintFor then ... end
--
-- does not fail loudly. It evaluates to false and the whole branch is skipped in silence, forever. Three
-- instances landed on 2026-09-23:
--
--   * KB-66  `ncm_world` asked `ncm_league` to grant ownership. The grant never happened.
--   * L110   `ncm_world` reached for `NcmCalendar.serverId()` and fell back to a literal, keying
--            `driver_location` rows under `"ncm"` while the rest of the world used `"ncm-dev"`.
--   * L111   `ncm_world` reached for `NcmOwnership.paintFor`. A called machine was never painted once, which
--            is why an owned MaiMai came back green and then red.
--
-- Each was found by a player noticing, not by a test. This is the test.
--
-- Escape hatch: a line carrying `cross-scope-ok` is allowed, for a reference that is genuinely guarded and
-- deliberate. Use it with a reason beside it, not to silence this.
local root = arg[1] or "."
local RES = root .. "/ncm/online/resources"

local function readDir(path)
    local names, isWindows = {}, package.config:sub(1, 1) == "\\"
    local cmd = isWindows and ('dir /b "' .. path:gsub("/", "\\") .. '" 2>nul')
                           or ('ls -1 "' .. path .. '" 2>/dev/null')
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

local function isDir(path) return #readDir(path) > 0 end

--- Every .lua under a directory, recursively.
local function luaFiles(dir, out)
    out = out or {}
    for _, name in ipairs(readDir(dir)) do
        local full = dir .. "/" .. name
        if name:match("%.lua$") then out[#out + 1] = full
        elseif isDir(full) then luaFiles(full, out) end
    end
    return out
end

-- Vendored into every resource by ncm-build, so it exists in all scopes.
local SHARED = { NcmCore = true, NcmSchema = true }

local scopes, order = {}, {}
for _, res in ipairs(readDir(RES)) do
    for _, side in ipairs({ "server", "client" }) do
        local dir = RES .. "/" .. res .. "/" .. side
        if isDir(dir) then
            local key = res .. "/" .. side
            scopes[key] = { defines = {}, refs = {} }
            order[#order + 1] = key
            for _, fp in ipairs(luaFiles(dir)) do
                local fh = io.open(fp, "r")
                if fh then
                    local n = 0
                    for line in fh:lines() do
                        n = n + 1
                        -- definitions: any top-level assignment, or a function/field on a global
                        -- `function NcmFoo()` is as much a definition as `NcmFoo = function()`; missing it
                        -- reported a defined global as a cross-VM reference (a false positive, 2026-09-24).
                        local d = line:match("^%s*(Ncm%a+)%s*=") or line:match("^%s*function%s+(Ncm%a+)[.:]")
                                  or line:match("^%s*function%s+(Ncm%a+)%s*%(")
                                  or line:match("^%s*(Ncm%a+)%.%w+%s*=")
                        if d then scopes[key].defines[d] = true end
                        -- references, ignoring comments and acknowledged exceptions
                        if not line:match("^%s*%-%-") and not line:find("cross%-scope%-ok") then
                            for g in line:gmatch("(Ncm%a+)") do
                                scopes[key].refs[g] = scopes[key].refs[g] or {}
                                local list = scopes[key].refs[g]
                                if #list < 4 then list[#list + 1] = fp:gsub("^%./", "") .. ":" .. n end
                            end
                        end
                    end
                    fh:close()
                end
            end
        end
    end
end

local bad, checked = 0, 0
for _, key in ipairs(order) do
    local sc = scopes[key]
    for g, sites in pairs(sc.refs) do
        checked = checked + 1
        if not SHARED[g] and not sc.defines[g] then
            local owner = "NOWHERE"
            for _, other in ipairs(order) do
                if scopes[other].defines[g] then owner = other end
            end
            bad = bad + 1
            print(("  CROSS-SCOPE  [%s] reads %s, which lives in %s"):format(key, g, owner))
            for _, site in ipairs(sites) do print("               " .. site) end
        end
    end
end

print(("cross-scope: %d global reference(s) checked across %d scope(s), %d bad")
    :format(checked, #order, bad))
if bad > 0 then
    print("  A global from another Lua VM is always nil. `if ThatGlobal and ...` is silently false forever.")
    print("  Fix by removing the dependency (shared core, the database, or GlobalState), not by bridging it.")
    os.exit(1)
end
