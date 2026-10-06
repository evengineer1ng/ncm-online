-- The OPEN//77 server sandbox, asserted statically (KB-322, KB-324). Joins the gate by existing.
--
--   * `os` and `collectgarbage` do not exist in a server VM (KB-327 found the second). `os.clock()` in ncm_world/server/speed.lua killed the lane index on its first
--     boot (KB-322) and neither `luac -p` nor the cross-scope check could see it.
--   * `Open77.tunables.declare` accepts `apply` = live | next_round | next_match only. One bad value rejects the WHOLE
--     declaration, every tunable falls back to its literal default -- and ncm_paddock's default serverId booted a
--     stale world for two minutes (KB-324).
-- A line carrying `sandbox-ok` is exempt (with a reason beside it).
local root = arg[1] or "."
local DIRS = { root .. "/ncm/online/resources", root .. "/prototypes" }

local function readDir(path)
    local names, isWindows = {}, package.config:sub(1, 1) == "\\"
    local cmd = isWindows and ('dir /b "' .. path:gsub("/", "\\") .. '" 2>nul') or ('ls -1 "' .. path .. '" 2>/dev/null')
    local p = io.popen(cmd)
    if not p then return names end
    for line in p:lines() do line = line:gsub("%s+$", ""); if line ~= "" then names[#names + 1] = line end end
    p:close()
    return names
end

local function serverFiles(dir, out, inServer)
    for _, name in ipairs(readDir(dir)) do
        local path = dir .. "/" .. name
        if name:match("%.lua$") then
            if inServer then out[#out + 1] = path end
        elseif not name:match("%.") and name ~= "shared" and name ~= "client" and name ~= "web" then
            serverFiles(path, out, inServer or name == "server")
        end
    end
    return out
end

local ALLOWED_APPLY = { live = true, next_round = true, next_match = true }
local bad, files = 0, 0
for _, dir in ipairs(DIRS) do
    for _, path in ipairs(serverFiles(dir, {}, false)) do
        files = files + 1
        local n = 0
        for line in io.lines(path) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            if not line:find("sandbox-ok", 1, true) then
                if code:match("[^%w_%.]collectgarbage[^%w_]") or code:match("^collectgarbage[^%w_]") then
                    bad = bad + 1
                    print(("  FAIL %s:%d uses `collectgarbage` (absent in the OPEN//77 server VM, KB-327): %s"):format(path, n, line:gsub("^%s+", "")))
                end
                if code:match("[^%w_%.]os%.%a") or code:match("^os%.%a") then
                    bad = bad + 1
                    print(("  FAIL %s:%d uses `os` (absent in the OPEN//77 server VM; use Open77.time): %s"):format(path, n, line:gsub("^%s+", "")))
                end
                for value in code:gmatch('apply%s*=%s*"([%w_]+)"') do
                    if not ALLOWED_APPLY[value] then
                        bad = bad + 1
                        print(("  FAIL %s:%d tunable apply \"%s\" (only live | next_round | next_match): the whole declaration would be rejected"):format(path, n, value))
                    end
                end
            end
        end
    end
end
print(("server sandbox: %d server file(s) checked, %d bad"):format(files, bad))
if bad > 0 then os.exit(1) end
