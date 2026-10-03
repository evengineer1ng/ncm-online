-- ncm_broadcast / client -- feeds the NCM Broadcast plugin (L235): names over race cars, and the opt-in tower.
--
--   * transport: a hidden 16x16 loopback page to `ncm_broadcast.dll` (127.0.0.1:38680-38683, the L129 pattern the
--     Scanner and Pace use), for the tower.
--   * names (`/ncm.names`, on by default): every Paddock car near you gets a plate -- position, name, team. The
--     server's rows carry each car's OPEN//77 vehicle id; each car gets an `Open77.anchors` anchor on its
--     `Open77.vehicles.get(id).entity`, and web/names.html draws the plates where the platform projects them (KB-223;
--     the plugin's own plates piled up in one spot). Players are never labelled here: they have nameplates.
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
local namesDown          -- assigned with the names section below
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
    if not namesOn then namesDown() end
    toast(namesOn and "Race car names ON." or "Race car names OFF.")
end, false)

RegisterNetEvent("ncm:broadcast.view", function(v)
    if type(v) == "table" then send(v) end
end)

-- ------------------------------------------------------------------------------------------------------ feeds
local paddock = {}        -- raceId -> { at = ms, m = message }
local sessions = {}       -- sessionId -> view (targeted ncm:session)

RegisterNetEvent("ncm:broadcast.paddock", function(m)
    if type(m) ~= "table" or not m.raceId then return end
    paddock[m.raceId] = { at = GetGameTimer(), m = m }
end)

RegisterNetEvent("ncm:session", function(sessionId, view)
    sessionId = tostring(sessionId or "")
    if sessionId == "" then return end
    sessions[sessionId] = type(view) == "table" and view or nil
end)

-- ------------------------------------------------------------------------------------------------------ names
-- A plate over each Paddock car near you: position, name, team. It is an `Open77.anchors` anchor on the car's engine
-- entity with `render = "card"`, so the platform projects AND draws it in the frame it presents -- it rides on the
-- car and follows the camera, which the plugin's own plates (KB-223, piled in one screen spot) never did. No WebUI
-- page is involved.
--
-- KB-223 history: the first anchor attempt (2026-09-30 02:48) crashed the owner's game 0.13 s after its page and
-- anchors came up, while the grid's cars were still spawning and having drivers seated; the suspect was an anchor on
-- a car entity the platform replaced mid-spawn. So a car gets its plate only after its entity has stayed the same
-- for SETTLE_MS, a changed entity drops the plate and starts the wait again, and `/ncm.names` turns plates off.
-- SUBTLE (owner, 2026-10-02: "they obscure the car too much especially when a gaggle of them are together"): one
-- short line ("P3 VARGAS") well above the roof; none on a car right beside you (you can see who it is) or beyond
-- PLATE_FAR_M; at most MAX_PLATES, nearest first; and when plates overlap on screen only the nearest car's stays.
local NAME_LIFT = { x = 0.0, y = 0.0, z = 2.7 }
local SETTLE_MS = 3000
local MAX_PLATES = 8                           -- visible at once (declutter picks the nearest)
local ANCHOR_CAP = 20                          -- anchors held (the platform allows 32 per resource)
local PLATE_NEAR_M, PLATE_FAR_M = 7, 120
local anchorOf = {}        -- vehicleId -> { id, entity, sig }
local seenEntity = {}      -- vehicleId -> { entity, since }
local cardsRefused = nil   -- the platform's reason, once, if this build cannot draw native cards

local function vehicleEntity(vid)
    local ok, snap = pcall(Open77.vehicles.get, vid)
    local e = ok and type(snap) == "table" and snap.entity or nil
    return e ~= nil and tostring(e) or nil
end

local function dropAnchor(vid)
    local a = anchorOf[vid]
    if a then pcall(Open77.anchors.remove, a.id) end
    anchorOf[vid] = nil
end

local function dropAnchors()
    for vid in pairs(anchorOf) do dropAnchor(vid) end
    seenEntity = {}
end

namesDown = dropAnchors

local ACCENT = { [0] = "#FFB833", [1] = "#FFD24D", [2] = "#73E68C", [3] = "#80808C" }

local function surname(name)
    local last = tostring(name or ""):match("(%S+)%s*$") or tostring(name or "")
    return string.upper(last)
end

local function presentation(r)
    local accent = (r.state == "finished" and 2) or (r.state == "out" and 3) or (tonumber(r.pos) == 1 and 1) or 0
    local label = ("P%s %s"):format(tostring(r.pos or "?"), surname(r.name))
    return { label = label, color = "#E6EBEF", accent = ACCENT[accent], showDistance = false },
        label .. "|" .. accent
end

--- rows = the Paddock rows near us that carry a vehicle id. One settled anchor per car.
local function showNames(rows, now)
    if cardsRefused then return end
    local live = {}
    for _, r in ipairs(rows) do
        local vid = r.vid
        local entity = vehicleEntity(vid)
        if entity then
            live[vid] = true
            local seen = seenEntity[vid]
            if not seen or seen.entity ~= entity then
                -- a new car, or the platform replaced its entity: wait for it to settle before anchoring anything
                seenEntity[vid] = { entity = entity, since = now }
                dropAnchor(vid)
            elseif now - seen.since >= SETTLE_MS then
                local pres, sig = presentation(r)
                local a = anchorOf[vid]
                if not a then
                    local id, why = Open77.anchors.create({ tag = "ncm.name." .. tostring(vid), entity = entity, offset = NAME_LIFT,
                        maxDistance = PLATE_FAR_M, render = "card", visible = true, presentation = pres })
                    if id then
                        anchorOf[vid] = { id = id, entity = entity, sig = sig, shown = true }
                    else
                        local reason = tostring(why)
                        if reason:find("render", 1, true) or reason == "anchors_backend_unavailable" then
                            cardsRefused = reason
                            log("race names off: this client cannot draw native anchored cards (%s)", reason)
                            dropAnchors()
                            return
                        end
                        log("anchor for vehicle %s refused: %s", tostring(vid), reason)
                    end
                elseif a.sig ~= sig then
                    pcall(Open77.anchors.update, a.id, { presentation = pres })
                    a.sig = sig
                end
            end
        end
    end
    for vid in pairs(anchorOf) do if not live[vid] then dropAnchor(vid) end end
    for vid in pairs(seenEntity) do if not live[vid] then seenEntity[vid] = nil end end
end

--- Screen-space declutter, several times a second: from the platform's own per-frame projection (`anchors.frame`),
--- hide a plate that is too close to you, or that overlaps a nearer car's plate on screen. Only visibility changes are
--- sent, so a steady scene costs nothing.
local function declutter()
    if not next(anchorOf) or type(Open77.anchors.frame) ~= "function" then return end
    local ok, frame = pcall(Open77.anchors.frame)
    if not ok or type(frame) ~= "table" then return end
    local byId = {}
    for _, a in ipairs(frame) do byId[tostring(a.id)] = a end
    local items = {}
    for vid, a in pairs(anchorOf) do
        local f = byId[tostring(a.id)]
        if f and f.projected ~= false and f.onScreen ~= false then
            local sc = type(f.screen) == "table" and f.screen or f
            if type(sc.x) == "number" and type(sc.y) == "number" then
                items[#items + 1] = { vid = vid, a = a, x = sc.x, y = sc.y, d = tonumber(f.distance) or 1e9 }
            end
        end
    end
    table.sort(items, function(p, q) return p.d < q.d end)
    -- normalised or pixel coordinates: size the overlap box to whichever the platform reports
    local norm = true
    for _, it in ipairs(items) do if math.abs(it.x) > 2 or math.abs(it.y) > 2 then norm = false break end end
    local W, H = norm and 0.09 or 170, norm and 0.04 or 44
    local kept, want = {}, {}
    for _, it in ipairs(items) do
        local show = it.d >= PLATE_NEAR_M and #kept < MAX_PLATES
        if show then
            for _, k in ipairs(kept) do
                if math.abs(k.x - it.x) < W and math.abs(k.y - it.y) < H then show = false break end
            end
        end
        if show then kept[#kept + 1] = it end
        want[it.vid] = show
    end
    for vid, a in pairs(anchorOf) do
        local show = want[vid] or false
        if a.shown ~= show then
            pcall(Open77.anchors.update, a.id, { visible = show })
            a.shown = show
        end
    end
end

CreateThread(function()
    while true do
        if namesOn then pcall(declutter) end
        Wait(150)
    end
end)

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
        -- the order is provisional and already includes penalties: say so on the row that carries them
        local gap = tostring(r.gap or "")
        if r.pen then gap = (gap ~= "" and (gap .. " ") or "") .. tostring(r.pen) end
        rows[#rows + 1] = { pos = tostring(r.pos or i), name = tostring(r.name or "?"), gap = gap, flag = flag }
    end
    return { cmd = "tower", ttl = 3, title = tostring(m.title or "PADDOCK"):upper(), sub = tostring(m.sub or ""), rows = rows }
end

--- My session's Paddock race, when it is a mixed grid and its field is fresh: the whole field, me marked.
local function mixedTower(v, pid, now)
    local p = v and v.paddockRaceId and paddock[v.paddockRaceId]
    if not p or now - p.at > 4000 then return nil end
    local myDriver
    for _, en in ipairs(v.entrants or {}) do if tonumber(en.playerId) == pid then myDriver = en.driverId end end
    local msg = paddockTower(p.m)
    for i, r in ipairs(p.m.rows or {}) do
        if msg.rows[i] and myDriver and r.driverId == myDriver then msg.rows[i].flag = "me" end
    end
    return msg
end

local towerShown = false

CreateThread(function()
    Wait(6000)
    local lastHealth, retryAt = 0, 0
    while true do
        local now = GetGameTimer()
        -- no plugin: back off the transport, never the loop -- names do not need the plugin
        if attempts >= PORT_SPAN * 3 then retryAt, attempts = now + 60000, 0 end
        if not surface and now >= retryAt then bringUp() end
        if ready and now - lastHealth > 5000 then lastHealth = now; send({ cmd = "health" }) end
        -- the Paddock races the server says we are near, freshest first; stale ones drop out
        local fresh = {}
        for id, p in pairs(paddock) do
            if now - p.at > 4000 then paddock[id] = nil else fresh[#fresh + 1] = p.m end
        end
        table.sort(fresh, function(a, b) return (tonumber(a.d) or 1e9) < (tonumber(b.d) or 1e9) end)
        -- names need no plugin: anchors and a page are the platform's own (KB-223)
        if namesOn then
            local rows = {}
            for _, m in ipairs(fresh) do
                for _, r in ipairs(m.rows or {}) do
                    if r.vid and not r.human and #rows < ANCHOR_CAP then rows[#rows + 1] = r end
                end
            end
            local ok, err = pcall(showNames, rows, now)
            if not ok then log("names: %s", tostring(err)) end
        end
        if ready and towerOn then
            local v = mySession()
            local pid = myPlayerId()
            local msg = (v and mixedTower(v, pid, now)) or (v and sessionTower(v, pid)) or (fresh[1] and paddockTower(fresh[1])) or nil
            if msg then send(msg); towerShown = true
            elseif towerShown then send({ cmd = "tower", rows = {} }); towerShown = false end
        end
        Wait(500)
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
    namesDown()
    pcall(Open77.anchors.clear)
    send({ cmd = "tower", rows = {} })
    tearDown()
end)
