-- ncm_link / server: Night City's side of the cross-server link (L323; doc 54 §S). See open77.lua.
local function log(fmt, ...) print(("[ncm_link] " .. fmt):format(...)) end

local HUB = (GetConvar and GetConvar("ncm_link_hub", "http://127.0.0.1:30120/ncm_ls_space")) or "http://127.0.0.1:30120/ncm_ls_space"
local SERVER_ID = (GetConvar and GetConvar("ncm_server_id", "ncm-dev")) or "ncm-dev"
local up = nil                 -- nil = not yet known, true/false after the first call

local function tell(pid, msg)
    pcall(Open77.notifications.send, pid, { type = "info", title = "NCM LINK", message = msg, icon = "NCM", durationMs = 15000 })
    pcall(Open77.chat.send, pid, "[NCM] " .. msg)
end

local function post(path, body, cb)
    local ok, err = pcall(PerformHttpRequest, HUB .. path, function(status, text)
        local was = up
        up = (tonumber(status) or 0) >= 200 and (tonumber(status) or 0) < 300
        if up ~= was then log("hub %s at %s (HTTP %s)", up and "REACHABLE" or "unreachable", HUB, tostring(status)) end
        local data = nil
        if up and type(text) == "string" and text ~= "" then
            local okJ, d = pcall(json.decode, text)
            data = okJ and d or nil
        end
        if cb then cb(up, data, status) end
    end, "POST", json.encode(body or {}), { ["Content-Type"] = "application/json" })
    if not ok then
        if up ~= false then log("cannot call the hub: %s (is server.jsonc http enabled with 127.0.0.1 allowed?)", tostring(err)) end
        up = false
        if cb then cb(false, nil, 0) end
    end
end

-- the NCM driver of a connected player (the binding table ncm_world mints; same query as ncm_league/calendar)
local driverOf = {}
local function resolveDriver(pid)
    pid = tonumber(pid) or 0
    if driverOf[pid] then return driverOf[pid] end
    local userId = GetPlayerIdentifier(pid)
    if type(userId) ~= "string" or userId == "" or not (MySQL and MySQL.isReady and MySQL.isReady()) then return nil end
    local row = MySQL.single.await(
        "SELECT b.ncm_driver_id, p.display FROM ncm_driver_binding b " ..
        "LEFT JOIN driver_profile p ON p.ncm_driver_id = b.ncm_driver_id AND p.server_id = b.server_id " ..
        "WHERE b.server_id = ? AND b.user_id = ?", { SERVER_ID, userId })
    if not row or not row.ncm_driver_id then return nil end
    driverOf[pid] = { id = row.ncm_driver_id, display = row.display or GetPlayerName(pid), userId = userId }
    return driverOf[pid]
end
AddEventHandler("playerDropped", function() driverOf[tonumber(source) or 0] = nil end)

RegisterCommand("ncm.link", function(source)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local d = resolveDriver(pid)
    if not d then tell(pid, "No NCM driver yet -- drive first."); return end
    post("/link/code", { driverId = d.id, identity = "op77:" .. d.userId, display = d.display, nonce = tostring(Open77.time.unix()) }, function(ok, data)
        if ok and data and data.code then
            tell(pid, ("Link code %s -- in Los Santos type /ncm.link %s within %d minutes."):format(data.code, data.code, math.floor((data.ttl or 600) / 60)))
            log("link code issued for driver %s (%s)", d.id:sub(1, 8), d.display)
        else
            tell(pid, "Nothing answered.")               -- no hint of what should have answered
        end
    end)
end, false)

-- Race Week facts: tallied here, exchanged every 5 minutes, logged both ways, never shown
local facts = {}
AddEventHandler("ncm:week:fact", function(kind, n)
    kind = tostring(kind or "")
    facts[kind] = (facts[kind] or 0) + (tonumber(n) or 1)
end)

local function weekRun()
    local ok, w = pcall(function() return GlobalState.ncmWeek end)
    return ok and type(w) == "table" and w.run or nil
end

-- every finished human race: a candidate Three Cities leg (position = rank among the humans in that race)
AddEventHandler("ncm:paddock.human.result", function(raceId, rows)
    if type(rows) ~= "table" then return end
    local fin = {}
    for _, r in ipairs(rows) do if r.state == "finished" and r.finishMs then fin[#fin + 1] = r end end
    table.sort(fin, function(a, b) return a.finishMs < b.finishMs end)
    for i, r in ipairs(fin) do
        post("/results", { driverId = r.driverId, leg = { venue = "paddock:" .. tostring(raceId), position = i, raceS = r.finishMs / 1000,
            state = "finished", week = weekRun() } })
    end
end)

-- a finished Badlands Sky Sprint (ncm_space): a Night City leg too
AddEventHandler("ncm:space.result", function(pid, venue, position, raceS, state)
    local d = resolveDriver(pid)
    if not d or state ~= "finished" then return end
    post("/results", { driverId = d.id, leg = { venue = tostring(venue), position = position, raceS = raceS, state = state, week = weekRun() } })
end)

CreateThread(function()
    Wait(5000)
    post("/facts", { week = weekRun(), facts = facts }, function(ok, data)
        log("Snowglobe hub %s; Night City week %s", ok and "linked" or "not reachable (Los Santos server down, or http not enabled) -- idling",
            tostring(weekRun()))
    end)
    while true do
        Wait(300000)
        local sent = facts
        facts = {}
        post("/facts", { week = weekRun(), facts = sent }, function(ok, data)
            if ok and data then
                log("facts out (week %s): %s | in: snowglobe %s (hidden)", tostring(weekRun()), json.encode(sent), json.encode(data.snowglobe or {}))
            else
                for k, v in pairs(sent) do facts[k] = (facts[k] or 0) + v end       -- keep them for the next try
            end
        end)
    end
end)
