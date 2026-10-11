-- ncm_radio / client / radio -- the relay between the server's programme and the NCM Radio plugin (doc 59 §6).
--
-- A hidden loopback surface to `ncm_radio.dll` (127.0.0.1:38720-38723, the L129 pattern Pace and the Scanner use).
-- The plugin plays; redscript decides whether the player is listening; this file only carries messages. With no
-- plugin installed nothing happens and nothing complains: the station simply is not in the radio list.
local function log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    print("[ncm_radio] " .. (ok and line or tostring(fmt)))
end

local PORT_BASE, PORT_SPAN = 38720, 4   -- its own block: 38680 is NCM Broadcast's (KB-420)
local portIndex, attempts = 0, 0
local surface, ready, health = nil, false, nil
local pending = nil            -- the latest item, kept until the plugin can take it

local function url() return ("http://127.0.0.1:%d/radio.html"):format(PORT_BASE + portIndex) end

local function send(payload)
    if not (surface and ready) then return false end
    return (pcall(function() surface:send("ncm:radio.send", payload) end))
end

local function tearDown()
    if surface then pcall(function() surface:destroy() end) end
    surface, ready, health = nil, false, nil
end

local function bringUp()
    if surface then return end
    local page, why = WebUI.create({ entry = url(), layer = "hud", width = 16, height = 16, fps = 5,
        zIndex = 1, transparent = true, visible = true })
    if not page then
        attempts = attempts + 1
        portIndex = (portIndex + 1) % PORT_SPAN
        if attempts == PORT_SPAN then log("no NCM Radio plugin on 127.0.0.1:%d-%d (%s)", PORT_BASE, PORT_BASE + PORT_SPAN - 1, tostring(why)) end
        return
    end
    surface = page
    pcall(function() page:hide() end)
    local tried = page
    CreateThread(function()
        Wait(8000)
        if surface == tried and not ready then
            tearDown()
            portIndex = (portIndex + 1) % PORT_SPAN
            attempts = attempts + 1
        end
    end)
    page:on("ncm:radio.ready", function()
        ready, attempts = true, 0
        send({ cmd = "hello" })
    end)
    page:on("ncm:radio.closed", function()
        local was = ready
        ready = false
        if not was then tearDown(); portIndex = (portIndex + 1) % PORT_SPAN; attempts = attempts + 1 end
    end)
    page:on("ncm:radio.msg", function(m)
        if type(m) ~= "table" then return end
        if m.health then
            if not health then
                log("NCM Radio plugin %s (pack %s) on %s", tostring(m.health.version), tostring(m.health.packVersion), url())
                TriggerServerEvent("ncm:radio.hello", { version = m.health.version, pack = m.health.packVersion })
            end
            health = m.health
            if pending then send(pending); pending = nil end
        elseif m.listening ~= nil then
            TriggerServerEvent("ncm:radio.listening", { on = m.listening and true or false })
        end
    end)
end

RegisterNetEvent("ncm:radio.item", function(item)
    if type(item) ~= "table" then return end
    local msg = { cmd = "item", seq = item.seq, beat = item.beat, clips = item.clips, offsetMs = item.offsetMs or 0 }
    if not send(msg) then pending = msg end
end)

CreateThread(function()
    Wait(5000)
    while true do
        if not surface then bringUp() end
        Wait(ready and 10000 or 2000)
        if ready then send({ cmd = "health" }) end
    end
end)
