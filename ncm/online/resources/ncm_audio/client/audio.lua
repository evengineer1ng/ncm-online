-- ncm_audio / client / audio -- the voices for the `ncm-audio` required mod (NCM FX).
--
--   exports.voices(list, listener)   the whole set of voices that should sound now (looping ones are kept alive by
--                                    being named again; one-shots play once): { key, file, loop, oneShot, pitch, gain,
--                                    position = {x,y,z} }; listener = { pos, right, forward } in world space.
--   exports.status()                 whether the plugin is connected, and what it last reported.
--
-- Looping voices go to the DLL thirty times a second; a one-shot goes the moment it is named (a hop must not wait).
local function log(fmt, ...) print(("[ncm_audio] " .. fmt):format(...)) end

local PORT_BASE, PORT_SPAN = 38800, 4
local SEND_MS = 33
local portIndex, attempts = 0, 0
local surface, surfaceReady, health = nil, false, nil
local latest, listener = {}, nil
local shotSeen = {}        -- one-shot key -> ms it was played (a key names one event; it is not replayed for 1 s)

local function url() return ("http://127.0.0.1:%d/audio.html"):format(PORT_BASE + portIndex) end
local function now() return GetGameTimer() end

local function send(payload)
    if not (surface and surfaceReady) then return false end
    return (pcall(function() surface:send("ncm:audio.send", payload) end))
end

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("transport closed (%s)", tostring(why))
    end
    surface, surfaceReady, health = nil, false, nil
end

local function bringUp()
    if surface then return end
    local page, reason = WebUI.create({ entry = url(), layer = "hud", width = 16, height = 16, fps = 10,
        zIndex = 1, transparent = true, visible = true })
    if not page then
        attempts = attempts + 1
        portIndex = (portIndex + 1) % PORT_SPAN
        if attempts == PORT_SPAN then
            log("no NCM Audio plugin on 127.0.0.1:%d-%d (%s): NCM is silent", PORT_BASE, PORT_BASE + PORT_SPAN - 1, tostring(reason))
        end
        return
    end
    surface = page
    pcall(function() page:hide() end)
    page:on("ncm:audio.ready", function()
        surfaceReady, attempts = true, 0
        log("transport connected at %s", url())
        send({ cmd = "health" })
    end)
    page:on("ncm:audio.closed", function(info)
        local wasReady = surfaceReady
        surfaceReady = false
        if not wasReady then
            tearDown("closed before connecting: " .. tostring(type(info) == "table" and info.detail or "?"))
            portIndex = (portIndex + 1) % PORT_SPAN
        end
    end)
    page:on("ncm:audio.health", function(h)
        if type(h) ~= "table" then return end
        if not health then log("plugin %s (device %s)", tostring(h.version), tostring(h.device)) end
        health = h
    end)
end

local function vec(p) p = p or {}; return { x = tonumber(p.x or p[1]) or 0, y = tonumber(p.y or p[2]) or 0, z = tonumber(p.z or p[3]) or 0 } end

exports("voices", function(list, lis)
    local loops, shots = {}, {}
    local t = now()
    for k, at in pairs(shotSeen) do if t - at > 1000 then shotSeen[k] = nil end end
    for _, v in ipairs(type(list) == "table" and list or {}) do
        local item = { key = tostring(v.key or ""), file = tostring(v.file or ""), pitch = tonumber(v.pitch) or 1,
            gain = tonumber(v.gain) or 1, pos = v.position and vec(v.position) or nil }
        if v.oneShot then
            if not shotSeen[item.key] then shotSeen[item.key] = t; shots[#shots + 1] = item end
        elseif v.loop then
            loops[#loops + 1] = item
        end
    end
    latest = loops
    if type(lis) == "table" then listener = { pos = vec(lis.pos), right = vec(lis.right), forward = vec(lis.forward) } end
    if #shots > 0 then send({ cmd = "shot", listener = listener, shots = shots }) end
    return surfaceReady
end)

exports("status", function() return { connected = surfaceReady, plugin = health and health.version or nil, health = health } end)

CreateThread(function()
    Wait(5000)
    while true do
        if not surface then bringUp() end
        if surfaceReady then send({ cmd = "voices", listener = listener, voices = latest }) end
        Wait(SEND_MS)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    send({ cmd = "voices", voices = {} })
    tearDown("resource stop")
end)
