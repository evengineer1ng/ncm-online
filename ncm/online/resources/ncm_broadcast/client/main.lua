-- ncm_broadcast / client -- feeds the NCM Broadcast plugin (L235): names over race cars, and the opt-in tower.
--
--   * transport: a hidden 16x16 loopback page to `ncm_broadcast.dll` (127.0.0.1:38680-38683, the L129 pattern the
--     Scanner and Pace use). It is this resource's only WebUI surface; nothing visible is a WebUI page.
--   * names (`/ncm.names`, on by default): every Paddock car near you gets a plate -- position, name, team. The
--     server's rows carry each car's OPEN//77 vehicle id; `Open77.vehicles.get(id).engineEntity` is the hash
--     redscript finds it by (the same mapping Pace proved). Players are never labelled here: they have nameplates.
--   * tower (`/ncm.tower`, off until you opt in): the multiplayer session you are an entrant of, with usernames;
--     otherwise the nearest Paddock race the server says you are near.
local function log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    print("[ncm_broadcast] " .. (ok and line or tostring(fmt)))
end

local PORT_BASE, PORT_SPAN = 38680, 4
local portIndex, attempts = 0, 0
local surface, ready, health = nil, false, nil

local function url() return ("http://127.0.0.1:%d/broadcast.html"):format(PORT_BASE + portIndex) end

local function send(payload)
    if not (surface and ready) then return false end
    return (pcall(function() surface:send("ncm:bcast.send", payload) end))
end

local function tearDown()
    if surface then pcall(function() surface:destroy() end) end
    surface, ready, health = nil, false, nil
end

local function bringUp()
    if surface then return end
    local page, why = WebUI.create({ entry = url(), layer = "hud", width = 16, height = 16, fps = 10,
        zIndex = 1, transparent = true, visible = true })
    if not page then
        attempts = attempts + 1
        portIndex = (portIndex + 1) % PORT_SPAN
        if attempts == PORT_SPAN then log("no NCM Broadcast plugin on 127.0.0.1:%d-%d (%s)", PORT_BASE, PORT_BASE + PORT_SPAN - 1, tostring(why)) end
        return
    end
    surface = page
    pcall(function() page:hide() end)
    page:on("ncm:bcast.ready", function()
        ready, attempts = true, 0
        send({ cmd = "hello" })
        TriggerServerEvent("ncm:broadcast.hello")
    end)
    page:on("ncm:bcast.closed", function()
        local was = ready
        ready = false
        if not was then tearDown(); portIndex = (portIndex + 1) % PORT_SPAN; attempts = attempts + 1 end
    end)
    page:on("ncm:bcast.msg", function(m)
        if type(m) == "table" and m.health then
            if not health then log("NCM Broadcast plugin %s on %s", tostring(m.health.version), url()) end
            health = m.health
        end
    end)
end

-- ------------------------------------------------------------------------------------------------------ prefs
-- Client KVP, like the landing watermark: a presentation preference, per player, no schema.
local function pref(key, default)
    local ok, v = pcall(Open77.kvp.get, "broadcast." .. key)
    if ok and v == "1" then return true elseif ok and v == "0" then return false end
    return default
end
local function setPref(key, on) pcall(Open77.kvp.set, "broadcast." .. key, on and "1" or "0") end

local namesOn = pref("names", true)
local towerOn = pref("tower", false)

local function toast(msg)
    log("%s", msg)
    TriggerServerEvent("ncm:broadcast.toast", { message = msg })
end

RegisterCommand("ncm.tower", function()
    towerOn = not towerOn
    setPref("tower", towerOn)
    if not towerOn then send({ cmd = "tower", rows = {} }) end
    toast(towerOn and "Timing tower ON: your race, or the Paddock race you are near." or "Timing tower OFF.")
end, false)

RegisterCommand("ncm.names", function()
    namesOn = not namesOn
    setPref("names", namesOn)
    if not namesOn then send({ cmd = "labels", items = {} }) end
    toast(namesOn and "Race car names ON." or "Race car names OFF.")
end, false)

RegisterNetEvent("ncm:broadcast.view", function(v)
    if type(v) == "table" then send(v) end
end)

-- ------------------------------------------------------------------------------------------------------ feeds
local paddock = {}        -- raceId -> { at = ms, m = message }
local sessions = {}       -- sessionId -> view (targeted ncm:session)
local entities = {}       -- vehicleId -> { hash, at }

RegisterNetEvent("ncm:broadcast.paddock", function(m)
    if type(m) ~= "table" or not m.raceId then return end
    paddock[m.raceId] = { at = GetGameTimer(), m = m }
end)

RegisterNetEvent("ncm:session", function(sessionId, view)
    sessionId = tostring(sessionId or "")
    if sessionId == "" then return end
    sessions[sessionId] = type(view) == "table" and view or nil
end)

local function entityOf(vid, now)
    local e = entities[vid]
    if e and (e.hash or now - e.at < 2000) then return e.hash end
    local ok, snap = pcall(Open77.vehicles.get, vid)
    local hash = ok and type(snap) == "table" and snap.engineEntity and tostring(snap.engineEntity) or nil
    entities[vid] = { hash = hash, at = now }
    return hash
end

local function myPlayerId()
    local ok, v = pcall(Open77.players.localId)
    return ok and tonumber(v) or nil
end

--- The multiplayer session this player is an entrant of (targeted first, GlobalState as recovery), or nil.
local function mySession()
    local pid = myPlayerId()
    if not pid then return nil end
    local function mine(v)
        if type(v) ~= "table" or not v.phase or v.phase == "none" then return nil end
        for _, en in ipairs(v.entrants or {}) do if tonumber(en.playerId) == pid then return v end end
        return nil
    end
    local ids = {}
    for sid in pairs(sessions) do ids[#ids + 1] = sid end
    table.sort(ids)
    for _, sid in ipairs(ids) do local v = mine(sessions[sid]) if v then return v end end
    local ok, ss = pcall(function() return GlobalState.ncmSessions end)
    if ok and type(ss) == "table" then
        ids = {}
        for sid, v in pairs(ss) do if type(v) == "table" then ids[#ids + 1] = sid end end
        table.sort(ids)
        for _, sid in ipairs(ids) do local v = mine(ss[sid]) if v then return v end end
    end
    return nil
end

local OUT = { dnf = true, dsq = true, retired = true, out = true, disqualified = true, abandoned = true }

--- A multiplayer session as tower rows: usernames, the kernel's own order, a gap to the leader.
local function sessionTower(v, pid)
    local rows, leader = {}, nil
    for i, en in ipairs(v.entrants or {}) do
        if i > 24 then break end
        leader = leader or en
        local gap
        if en.state == "finished" then
            local t, lt = tonumber(en.correctedSec or en.totalSec), tonumber(leader.correctedSec or leader.totalSec)
            gap = (i == 1 or not (t and lt)) and "FINISH" or ("+%.1fs"):format(t - lt)
        elseif OUT[tostring(en.state)] then
            gap = "OUT"
        elseif i == 1 then
            gap = "LEADER"
        else
            local d, ld = tonumber(en.correctedM or en.progressM), tonumber(leader.correctedM or leader.progressM)
            gap = (d and ld) and ("-%d m"):format(math.max(0, math.floor(ld - d))) or ""
        end
        local flag = (pid and tonumber(en.playerId) == pid) and "me" or (en.state == "finished" and "fin") or (OUT[tostring(en.state)] and "out") or ""
        rows[#rows + 1] = { pos = tostring(i), name = tostring(en.display or en.driverId or "?"), gap = gap, flag = flag }
    end
    local title = tostring(v.seriesName or v.routeName or "RACE"):upper()
    local sub = ("%s · %s"):format(tostring(v.phase or ""):upper(), tostring(v.routeName or ""))
    return { cmd = "tower", ttl = 3, title = title, sub = sub, rows = rows }
end

local function paddockTower(m)
    local rows = {}
    for i, r in ipairs(m.rows or {}) do
        if i > 24 then break end
        local flag = (r.state == "finished" and "fin") or (r.state == "out" and "out") or (r.physical and "phys") or ""
        rows[#rows + 1] = { pos = tostring(r.pos or i), name = tostring(r.name or "?"), gap = tostring(r.gap or ""), flag = flag }
    end
    return { cmd = "tower", ttl = 3, title = tostring(m.title or "PADDOCK"):upper(), sub = tostring(m.sub or ""), rows = rows }
end

local towerShown = false

CreateThread(function()
    Wait(6000)
    local lastHealth = 0
    while true do
        if not surface then bringUp() end
        local now = GetGameTimer()
        if ready and now - lastHealth > 5000 then lastHealth = now; send({ cmd = "health" }) end
        if ready then
            -- the Paddock races the server says we are near, freshest first; stale ones drop out
            local fresh = {}
            for id, p in pairs(paddock) do
                if now - p.at > 4000 then paddock[id] = nil else fresh[#fresh + 1] = p.m end
            end
            table.sort(fresh, function(a, b) return (tonumber(a.d) or 1e9) < (tonumber(b.d) or 1e9) end)
            if namesOn then
                local items = {}
                for _, m in ipairs(fresh) do
                    for _, r in ipairs(m.rows or {}) do
                        if r.vid and #items < 32 then
                            local hash = entityOf(r.vid, now)
                            if hash then
                                items[#items + 1] = { entity = hash, title = tostring(r.name or ""), sub = tostring(r.org or ""),
                                    chip = "P" .. tostring(r.pos or "?"),
                                    accent = (r.state == "finished" and 2) or (r.state == "out" and 3) or (tonumber(r.pos) == 1 and 1) or 0 }
                            end
                        end
                    end
                end
                send({ cmd = "labels", ttl = 2, items = items })
            end
            if towerOn then
                local v = mySession()
                local msg = v and sessionTower(v, myPlayerId()) or (fresh[1] and paddockTower(fresh[1])) or nil
                if msg then send(msg); towerShown = true
                elseif towerShown then send({ cmd = "tower", rows = {} }); towerShown = false end
            end
        end
        Wait(ready and 500 or 2000)
        if attempts >= PORT_SPAN * 3 then Wait(60000); attempts = 0 end
    end
end)

RegisterCommand("ncm.broadcast", function()
    log("transport: %s (%s); plugin %s; names=%s tower=%s", ready and "connected" or (surface and "connecting" or "down"), url(),
        health and tostring(health.version) or "not heard from -- is the ncm-broadcast required mod installed?", tostring(namesOn), tostring(towerOn))
    local n = 0
    for _ in pairs(paddock) do n = n + 1 end
    local v = mySession()
    log("paddock feeds: %d; my session: %s", n, v and tostring(v.sessionId) or "none")
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= "ncm_broadcast" then return end
    send({ cmd = "labels", items = {} })
    send({ cmd = "tower", rows = {} })
    tearDown()
end)
