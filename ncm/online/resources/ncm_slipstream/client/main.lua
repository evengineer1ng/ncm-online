-- ncm_slipstream / client -- the wake you are in, and the SL-1 if your Machine carries one (L356).
--
-- Every 100 ms while you drive a bound Machine:
--   1. MEASURE: your car and every streamed server car near you, as positions over time. Direction of travel comes
--      from the position deltas (a velocity), never from a heading convention: the client vehicle read carries no
--      velocity, and the old check assumed a heading convention nobody verified (aero.wake.fromPositions).
--   2. THE WAKE: aero.wake picks the best wake and its quality q (continuous: gap, offset, alignment, speed).
--   3. THE UNIT (only if installed AND switched on): aero.slipstream advances its lock (searching -> detected ->
--      acquiring -> active -> lost), adds its active share, draws the ink HUD, and tells the server when it holds or
--      lets go of a wake (the network: ncm_slipstream/server).
--   4. THE TOW: natural + active relief x aerodynamic drag at your speed, along your travel, handed to ncm_world's
--      wrench lease (`slipTow`) -- with no unit at all the natural draft still pushes.
-- Once a second while a wake is in play, the numbers go to the server log (`SLIPTRACE`) for the live A/B checks.
local Wake = NcmCore.get("aero.wake")
local Slip = NcmCore.get("aero.slipstream")
local Json = NcmCore.get("vocabulary.json")

local function log(fmt, ...) print(("[ncm_slipstream] " .. fmt):format(...)) end
local function ms() return GetGameTimer() end

local TICK_MS, RADIUS_M, TRACE_MS, TOW_TTL_MS = 100, 110, 1000, 250

local unit = { present = false }                 -- from the server: { assetId, vehicleId, present, enabled, boot, componentId, ... }
local cfg = Slip.CONFIG                          -- the unit's own numbers override these (its design's perf)
local st = Slip.newState()
local bound = { asset = nil, vehicle = nil }
local peer, inbound = nil, nil                   -- the leader's identity (units only); a unit behind us
local booting = false

-- ------------------------------------------------------------------------------------------------ the page
local page, pageReady = nil, false
local function send(name, payload)
    if not (page and pageReady) then return false end
    return (pcall(function() page:send(name, payload or {}) end))
end
local shown = false
local function show(on)
    if not page or shown == on then return end
    shown = on
    pcall(function() if on then page:show() else page:hide() end end)
end

AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    local reason
    page, reason = WebUI.create({ entry = "web/hud.html", layer = "hud", width = 1920, height = 1080, fps = 30,
        zIndex = 40, transparent = true, visible = true })
    if not page then log("HUD unavailable: %s", tostring(reason)); return end
    pcall(function() page:hide() end)
    page:on("slip:ready", function() pageReady = true end)
end)

-- ------------------------------------------------------------------------------------------------ the unit
local function unitConfig(u)
    local o = {}
    for k, v in pairs(Slip.CONFIG) do o[k] = v end
    if tonumber(u.reliefMax) then o.moduleReliefMax = tonumber(u.reliefMax) end
    if tonumber(u.lockPerS) then o.lockPerS = tonumber(u.lockPerS) end
    if tonumber(u.acquireQ) then o.acquireQ = tonumber(u.acquireQ) end
    return o
end
local function enabled() return unit.present and unit.enabled and unit.assetId == bound.asset end

-- The boot ceremony: the unit speaks (Play2DSound, its own rendered voice) and its interface draws itself in ink.
local lines = {}
do
    local ok, text = pcall(Open77.resource.readFile, "audio/lines.json")
    local okJ, meta = pcall(Json.decode, ok and text or "")
    for _, b in ipairs(Slip.BOOT) do
        local m = okJ and type(meta) == "table" and meta.lines and meta.lines[b.id] or nil
        lines[#lines + 1] = { id = b.id, text = b.text, hud = b.hud, ms = m and tonumber(m.ms) or (#b.text * 62) }
    end
end
local function boot()
    if booting then return end
    booting = true
    CreateThread(function()
        log("boot: %s %s on Machine ..%s", Slip.MAKER.name, Slip.PRODUCT.name, tostring(bound.asset):sub(-6))
        show(true)
        send("slip:boot", { step = 0, maker = Slip.MAKER.name, line = Slip.MAKER.line, product = Slip.PRODUCT.name, code = Slip.PRODUCT.code })
        Wait(700)
        for i, l in ipairs(lines) do
            if not enabled() then break end
            local id, why = Play2DSound(("audio/%s.wav"):format(l.id), { volume = 0.9 })
            if not id then log("boot voice %s: %s", l.id, tostring(why)) end
            send("slip:boot", { step = i, hud = l.hud, text = l.text, ms = l.ms, last = i == #lines })
            Wait(l.ms + 450)
        end
        Wait(1600)
        if enabled() then TriggerServerEvent("ncm:slip.booted", { componentId = unit.componentId }) end
        unit.boot = false
        send("slip:boot", { done = true })
        booting = false
    end)
end

RegisterNetEvent("ncm:slip.unit", function(u)
    unit = type(u) == "table" and u or { present = false }
    cfg = unitConfig(unit)
    if not enabled() then Slip.step(st, nil, 0, false); peer = nil end
    if unit.boot and enabled() then boot() end
end)
RegisterNetEvent("ncm:slip.peer", function(m)
    peer = type(m) == "table" and m.on and m.name and { name = tostring(m.name), npc = m.npc } or nil
end)
RegisterNetEvent("ncm:slip.inbound", function(m)
    if type(m) ~= "table" then return end
    inbound = m.on and { name = tostring(m.from or "another vehicle"), npc = m.npc, at = ms() } or nil
end)

-- ------------------------------------------------------------------------------------------------ binding
local function readBinding()
    local ok, bag = pcall(Open77.state.localPlayer)
    local h = ok and type(bag) == "table" and bag.ncmHandling or nil
    if type(h) == "table" and h.bound and type(h.assetId) == "string" and h.assetId ~= "" then return h.assetId, tostring(h.vehicleId) end
    return nil, nil
end
local function seatedIn(vid)
    local ok, seat = pcall(Open77.vehicles.getPlayerSeat)
    return ok and type(seat) == "table" and tostring(seat.vehicleId or seat.vehicle or seat.id) == tostring(vid)
end

CreateThread(function()
    Wait(8000)
    local lastHello = 0
    while true do
        local aid, vid = readBinding()
        if aid ~= bound.asset or vid ~= bound.vehicle or (aid and ms() - lastHello > 60000) then
            bound.asset, bound.vehicle = aid, vid
            lastHello = ms()
            if aid then TriggerServerEvent("ncm:slip.machine", { assetId = aid, vehicleId = vid })
            else unit = { present = false } end
        end
        Wait(500)
    end
end)

-- ------------------------------------------------------------------------------------------------ measuring
local track = {}       -- vehicle id -> { x, y, t, vx, vy } (velocity from position deltas, lightly smoothed)
local function observe(id, pos, t)
    if type(pos) ~= "table" or not tonumber(pos.x) or not tonumber(pos.y) then return nil end
    local k = tostring(id)
    local tr = track[k]
    if tr and t > tr.t then
        local dt = (t - tr.t) / 1000
        local vx, vy = (pos.x - tr.x) / dt, (pos.y - tr.y) / dt
        if dt > 0.6 then tr.vx, tr.vy = vx, vy            -- a long gap: no smoothing across it
        else tr.vx, tr.vy = (tr.vx or vx) * 0.4 + vx * 0.6, (tr.vy or vy) * 0.4 + vy * 0.6 end
        tr.x, tr.y, tr.t = pos.x, pos.y, t
    elseif not tr then
        tr = { x = pos.x, y = pos.y, t = t }
        track[k] = tr
        return nil
    end
    tr.seen = t
    if not tr.vx then return nil end
    return Wake.fromSnapshot(id, { position = pos, velocity = { x = tr.vx, y = tr.vy } })
end

local function others(mine, t)
    local out = {}
    local ok, near = pcall(Open77.vehicles.nearby, RADIUS_M, { streamed = true, limit = 16 })
    if not ok or type(near) ~= "table" then return out end
    for _, e in ipairs(near) do
        if type(e) == "table" and tostring(e.id) ~= tostring(mine) then
            local w = observe(e.id, e.position, t)
            if w then out[#out + 1] = w end
        end
    end
    return out
end

-- ------------------------------------------------------------------------------------------------ the loop
local lastT, lastTow, lastTrace, lastPhase, linkedTo = nil, 0, 0, "searching", nil
local function tow(fx, fy, ttl)
    pcall(Open77.exports.call, "ncm_world", "slipTow", fx, fy, 0, ttl, bound.asset)
end

CreateThread(function()
    Wait(9000)
    while true do
        Wait(TICK_MS)
        local t = ms()
        local driving = bound.asset and bound.vehicle and seatedIn(bound.vehicle)
        if not driving then
            if lastTow > 0 then tow(0, 0, 0); lastTow = 0 end
            if linkedTo then TriggerServerEvent("ncm:slip.link", { leader = linkedTo, on = false }); linkedTo = nil end
            Slip.step(st, nil, 0, false)
            if not booting then show(false) end
            lastT = nil
        else
            local dt = lastT and math.min(0.5, (t - lastT) / 1000) or (TICK_MS / 1000)
            lastT = t
            local okV, snap = pcall(Open77.vehicles.get, tonumber(bound.vehicle) or bound.vehicle)
            local me = okV and type(snap) == "table" and observe(bound.vehicle, snap.position, t) or nil
            if me then me.speed = tonumber(snap.speed) or me.speed end
            local best = me and Wake.best(me, others(bound.vehicle, t)) or nil
            local on = enabled()
            Slip.step(st, best, dt, on, cfg)
            local q = best and best.q or 0
            local relief, natural, active = Slip.relief(q, st, on, cfg)
            local n = me and Slip.towN(relief, me.speed) or 0
            if n > 5 and me then
                local r = math.rad(me.heading)
                tow(math.cos(r) * n, math.sin(r) * n, TOW_TTL_MS)
                lastTow = n
            elseif lastTow > 0 then
                tow(0, 0, 0); lastTow = 0
            end
            -- the network: a held wake, and letting go of it
            if on and st.phase == "active" and linkedTo ~= st.leader then
                if linkedTo then TriggerServerEvent("ncm:slip.link", { leader = linkedTo, on = false }) end
                linkedTo = st.leader
                TriggerServerEvent("ncm:slip.link", { leader = linkedTo, on = true })
            elseif linkedTo and st.phase ~= "active" then
                TriggerServerEvent("ncm:slip.link", { leader = linkedTo, on = false })
                linkedTo, peer = nil, nil
            end
            if lastPhase ~= st.phase then log("phase %s -> %s (q %.2f, lock %.2f)", lastPhase, st.phase, q, st.lock); lastPhase = st.phase end
            -- the ink: only a switched-on unit has an interface; it shows when there is something to say
            if inbound and t - inbound.at > 6000 then inbound = nil end
            local relevant = on and (st.phase ~= "searching" or inbound ~= nil)
            if booting then
                -- the ceremony owns the page
            elseif relevant then
                show(true)
                local g = best and best.geometry or {}
                send("slip:state", { phase = st.phase, q = q, lock = st.lock, ahead = g.ahead, lateral = g.lateral,
                    sigma = g.ahead and (Wake.CONFIG.halfWidthM + Wake.CONFIG.spreadPerM * math.max(0, g.ahead)) or nil,
                    peer = peer and peer.name or nil, inbound = inbound and inbound.name or nil, active = active, natural = natural })
            else
                show(false)
            end
            if (q > 0 or st.phase ~= "searching") and t - lastTrace >= TRACE_MS then
                lastTrace = t
                local g = best and best.geometry or {}
                TriggerServerEvent("ncm:slip.trace", { unit = on and "on" or (unit.present and "off" or "none"), phase = st.phase, q = q,
                    lock = st.lock, ahead = g.ahead, lat = g.lateral, v = me and me.speed, relief = relief, natural = natural,
                    active = active, towN = n, leader = best and tostring(best.id) or nil })
            end
        end
        -- forget cars not seen for a while
        for k, tr in pairs(track) do if t - (tr.seen or tr.t) > 5000 then track[k] = nil end end
    end
end)

--- `/ncm.slip` -- the unit and the wake, once, in the console.
RegisterCommand("ncm.slip", function()
    print(("[SLIP] Machine ..%s unit=%s enabled=%s phase=%s lock=%.2f q=%.3f peer=%s inbound=%s"):format(tostring(bound.asset):sub(-6),
        tostring(unit.present), tostring(enabled()), st.phase, st.lock, st.q or 0, peer and peer.name or "-", inbound and inbound.name or "-"))
end, false)
