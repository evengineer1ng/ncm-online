-- ncm_world / server / scars -- what Race Week leaves on the city (IDEA-1262, L351; core `week.scars`).
--
-- The Day 1 map is a static world package and never changes; scars are SERVER-OWNED PROPS added around it
-- (`Open77.props`, replicated, late joiners get a snapshot). Rebuilt from facts, never remembered: this run's
-- incidents with a position (`incident` x/y/z since the run opened) and the lowest tolerance the city has reached
-- this run (the hourly `racing_week_event` samples, plus the live read) -- so a restart rebuilds the same scars.
-- The level ratchets: what the city reached does not heal before rollover. Rollover is a new run, every key carries
-- the run, so the old run's props are removed and Day 1 is clean again.
--
-- Pinned/scratch hours never scar the real city. Console: `ncm.scars` (status) | `rebuild` | `off` | `on`.
local Scars = NcmCore.get("week.scars")
local Sites = NcmCore.get("data.race_week_sites")
local function log(fmt, ...) print(("[ncm_world/scars] " .. fmt):format(...)) end

local PERIOD_MS = 60000
local BATCH, BATCH_WAIT_MS = 12, 50     -- props created per tick slice, then yield
local have = {}            -- key -> prop id
local enabled = true
local last = { run = nil, level = 0, incidents = 0, planned = 0, failed = 0 }

local function lowestTolerance(win)
    local low = 1
    local ok, rows = pcall(MySQL.query.await, [[SELECT data_json FROM racing_week_event
        WHERE server_id = ? AND run_index = ? AND kind = 'sample' AND ref NOT LIKE 'radio:%']],
        { (NcmIdentity and NcmIdentity.serverId and NcmIdentity.serverId()) or GetConvar("ncm_server_id", "ncm"), win.index })
    if ok and type(rows) == "table" then
        for _, r in ipairs(rows) do
            local t = tonumber(tostring(r.data_json or ""):match('"tolerance"%s*:%s*([%-%d%.eE]+)'))
            if t and t < low then low = t end
        end
    end
    local read = NcmWeek.read()
    local now = read and read.read and tonumber(read.read.tolerance)
    if now and now < low then low = now end
    return low
end

local function incidents(win)
    local ok, rows = pcall(MySQL.query.await, [[SELECT id, kind, band, x, y, z FROM incident
        WHERE t >= ? AND kind IN ('person', 'car', 'object') AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL
        ORDER BY id LIMIT 4000]], { win.startUnix or 0 })
    return (ok and type(rows) == "table") and rows or {}
end

local function create(p)
    -- static set dressing: a scar never simulates (lag A/B 2026-10-08)
    local def = { model = p.model, position = { x = p.x, y = p.y, z = p.z }, yaw = p.yaw, collision = false,
                  physics = "static", streamingRadius = 150.0 }
    local id, reason = Open77.props.create(def)
    if not id and tostring(reason):find("collision") then      -- a host that is its own collision refuses `false`
        def.collision = true
        id, reason = Open77.props.create(def)
    end
    return id, reason
end

local function setting()
    local ok, v = pcall(function() return NcmIdentity and NcmIdentity.settings and NcmIdentity.settings.scarsEnabled end)
    return not (ok and v == false)
end

function NcmScarsSync()
    if not enabled then return end
    if not setting() then
        local n, i = 0, 0
        for key, id in pairs(have) do
            pcall(Open77.props.remove, id); have[key] = nil; n = n + 1; i = i + 1
            if i % BATCH == 0 then Wait(BATCH_WAIT_MS) end
        end
        if n > 0 or last.run ~= "off" then log("scarsEnabled=false: %d scar prop(s) removed; none placed", n) end
        last.run = "off"
        return
    end
    local win = NcmWeek.window and NcmWeek.window()
    if not win or win.scratch then return end
    local seed = NcmWeek.seed()
    local level = Scars.level(lowestTolerance(win))
    Wait(0)
    local inc = incidents(win)
    Wait(0)
    local plan = Scars.plan({ run = win.index, seed = seed, level = level, incidents = inc, sites = Sites.SITES,
        yield = function() Wait(0) end })   -- KB-410: the plan itself overran the quota at 19:37:57
    Wait(0)
    local d = Scars.diff(have, plan)
    Wait(0)
    local failed = 0
    -- OPEN//77 caps the Lua work a resource does per tick ("instruction quota exceeded", 2026-10-08): batch and yield
    for i, key in ipairs(d.remove) do
        pcall(Open77.props.remove, have[key])
        have[key] = nil
        if i % BATCH == 0 then Wait(BATCH_WAIT_MS) end
    end
    for i, p in ipairs(d.add) do
        if i % BATCH == 0 then Wait(BATCH_WAIT_MS) end
        local ok, id, reason = pcall(create, p)
        if ok and id then have[p.key] = id
        else
            failed = failed + 1
            if failed <= 3 then log("create refused %s (%s): %s", p.key, p.model, tostring(ok and reason or id)) end
        end
    end
    if #d.add > 0 or #d.remove > 0 or last.run ~= win.index or last.level ~= level then
        log("run %d level %d: %d incident(s) -> %d planned, +%d -%d, %d refused", win.index, level, #inc, #plan,
            #d.add - failed, #d.remove, failed)
    end
    last = { run = win.index, level = level, incidents = #inc, planned = #plan, failed = failed }
end

CreateThread(function()
    Wait(20000)                       -- after ncm_world/week has opened or resumed the run
    while true do
        local ok, err = pcall(NcmScarsSync)
        if not ok then log("sync failed: %s", tostring(err)) end
        Wait(PERIOD_MS)
    end
end)

RegisterCommand("ncm.scars", function(source, args)
    if source ~= 0 then return end
    local verb = args[1]
    local function clearAll()
        local i = 0
        for key, id in pairs(have) do
            pcall(Open77.props.remove, id); have[key] = nil
            i = i + 1
            if i % BATCH == 0 then Wait(BATCH_WAIT_MS) end
        end
    end
    if verb == "rebuild" then
        CreateThread(function() clearAll(); NcmScarsSync() end)
    elseif verb == "off" then
        enabled = false
        CreateThread(function() clearAll(); log("off: scars removed; `ncm.scars on` to resume") end)
    elseif verb == "on" then
        enabled = true; CreateThread(NcmScarsSync)
    end
    local n = 0
    for _ in pairs(have) do n = n + 1 end
    log("run %s level %d | incidents %d | planned %d | live %d | refused %d | %s", tostring(last.run), last.level or 0,
        last.incidents or 0, last.planned or 0, n, last.failed or 0, enabled and "on" or "OFF")
end, true)
