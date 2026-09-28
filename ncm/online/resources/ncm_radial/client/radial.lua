-- ncm_radial / client / radial -- the NCM quick menu.
--
-- HOLD the quick-menu key (keyboard, default B) or button (controller, default Start), point, RELEASE. Releasing
-- on a live slot runs it; releasing on nothing, or on an open slot, just closes the wheel. Left click / pad A
-- confirms early. Every action is also a hotkey and a chat command, and those are unchanged: the wheel is a way
-- to REACH them, not a replacement (owner, 2026-09-28: "keep our hotkeys").
--
-- Who does what:
--   * THIS FILE decides everything: whether the wheel is open, what is highlighted, what runs. It reads the pad
--     and keyboard physically (`Open77.input`), exactly like `ncm_world/client/nav_input.lua`.
--   * `ncm_radial.dll` (+ `ncm_radial.reds`), a required mod, only DRAWS what this file sends it, natively on the
--     HUD -- no WebUI is visible. The hidden page below is transport, not UI.
--   * `ncm_world` RUNS the action (`quickAction` export), through the same function its hotkey runs.
--
-- Slots are FIXED positions, clockwise from the top. A slot is greyed or left open, never moved, so a thumb can
-- learn the wheel; three of the eight are open on purpose, for features that have not shipped yet.
local function log(fmt, ...) print(("[ncm_radial] " .. fmt):format(...)) end

local SLOTS = {                      -- index 1 = top, then clockwise in 45-degree steps
    [1] = { id = "hub",   label = "Hub",         key = "F6", mapping = "ncm.guidepage",
            detail = "Race guide, market, machine index, messages" },
    [2] = { id = "graph", label = "Race graph",  key = "F8", mapping = "ncm.graph",
            detail = "Live gaps on or off" },
    [3] = { id = "call",  label = "Call a race", key = "F5", mapping = "ncm.build",
            detail = "Start a race where you stand" },
    [5] = { id = "map",   label = "Map",         key = "M",
            detail = "The city map" },
    [7] = { id = "gps",   label = "GPS",         key = "/ncm.gps",
            detail = "Route to your next race" },
}
local SLOT_COUNT = 8

local KEY_MAPPING, KEY_DEFAULT = "ncm.radial", "B"
local PAD_MAPPING, PAD_DEFAULT = "ncm.radial.pad", "padStart"
local PAD_KVP = "radial.pad"

local STICK_ON = 0.55                -- past this a stick AIMS; below it the last aim is kept (sticky, like vanilla)
local MOUSE_AIM_PX, MOUSE_CLAMP_PX = 60, 260
local OPEN_TICK_MS, IDLE_TICK_MS = 16, 50

-- ------------------------------------------------------------------------------------------------------------
-- Transport: a hidden loopback surface to the plugin (L129). The plugin owns 38560-38563 -- a range of its own,
-- never the Carrier's or Rig Bridge's.
-- ------------------------------------------------------------------------------------------------------------
local PORT_BASE, PORT_SPAN = 38560, 4
local portIndex = 0
local surface, surfaceReady = nil, false
local health = nil                   -- last health payload from the plugin
local layoutSent = false
local lastAttemptAt, attempts = 0, 0

local function url() return ("http://127.0.0.1:%d/radial.html"):format(PORT_BASE + portIndex) end
local function now() return GetGameTimer() end

local function send(payload)
    if not (surface and surfaceReady) then return false end
    local ok = pcall(function() surface:send("ncm:radial.send", payload) end)
    return ok
end

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("transport closed (%s)", tostring(why))
    end
    surface, surfaceReady, health, layoutSent = nil, false, nil, false
end

local function bringUp()
    if surface then return end
    local page, reason = WebUI.create({
        entry = url(), layer = "hud", width = 16, height = 16,
        zIndex = 1, transparent = true, visible = false,
    })
    if not page then
        -- Nothing listening on this port. Walk the range; a missing plugin is an ordinary state, said once.
        attempts = attempts + 1
        portIndex = (portIndex + 1) % PORT_SPAN
        if attempts == PORT_SPAN then
            log("no NCM Radial plugin on 127.0.0.1:%d-%d (%s); the wheel cannot be drawn until it is installed",
                PORT_BASE, PORT_BASE + PORT_SPAN - 1, tostring(reason))
        end
        return
    end
    surface = page
    page:on("ncm:radial.ready", function()
        surfaceReady, attempts, layoutSent = true, 0, false
        log("transport connected at %s", url())
    end)
    page:on("ncm:radial.closed", function(info)
        local wasReady = surfaceReady
        surfaceReady = false
        -- A close BEFORE a handshake means the wrong port (or a stranger on it): move on. After one it is an
        -- ordinary drop and the page reconnects on its own.
        if not wasReady then
            tearDown("closed before connecting: " .. tostring(type(info) == "table" and info.detail or "?"))
            portIndex = (portIndex + 1) % PORT_SPAN
        end
    end)
    page:on("ncm:radial.health", function(h)
        if type(h) ~= "table" then return end
        if not health or health.host ~= h.host then
            log("plugin %s: host=%s drawn=%s", tostring(h.version), tostring(h.host), tostring(h.drawn))
        end
        health = h
    end)
end

-- ------------------------------------------------------------------------------------------------------------
-- Bindings. Both are ordinary `RegisterKeyMapping`s, so both appear in the pause menu's key-bindings tab and
-- can be rebound there. The handlers only ARM the wheel; the hold itself is read physically below, the same
-- idiom the platform's own hold-to-open context menu uses.
-- ------------------------------------------------------------------------------------------------------------
local padMappingOk = false

local function keyboardKey()
    local ok, k = pcall(Open77.input.keyFor, KEY_MAPPING)
    return (ok and type(k) == "string" and k ~= "") and k or KEY_DEFAULT
end

local function padControl()
    if padMappingOk then
        local ok, k = pcall(Open77.input.keyFor, PAD_MAPPING)
        if ok and type(k) == "string" and k ~= "" then return k end
    end
    local ok, v = pcall(GetResourceKvp, PAD_KVP)
    if ok and type(v) == "string" and v ~= "" then return v end
    return PAD_DEFAULT
end

do
    local ok, result = pcall(RegisterKeyMapping, KEY_MAPPING, "NCM: quick menu (hold)", KEY_DEFAULT, function() end)
    if not ok or result == false then log("keyboard mapping not registered: %s", tostring(result)) end
    -- A pad control as a mapping default is not something the platform documents. If it is refused, the pad
    -- button still works and is set with `/ncm.radial pad <control>` instead.
    local okP, resultP, reasonP = pcall(RegisterKeyMapping, PAD_MAPPING, "NCM: quick menu, controller (hold)",
        PAD_DEFAULT, function() end)
    padMappingOk = okP and resultP ~= false
    if not padMappingOk then
        log("controller mapping not accepted (%s); using %s -- change it with /ncm.radial pad <control>",
            tostring(reasonP or resultP), padControl())
    end
end

-- ------------------------------------------------------------------------------------------------------------
-- The wheel
-- ------------------------------------------------------------------------------------------------------------
local W = {
    open = false, source = nil,      -- "key" | "pad"
    sel = nil,                       -- 1-based slot, sticky
    pointer = nil,                   -- degrees, nil when nothing is aimed at
    mouse = { x = 0, y = 0 },
    blocked = nil,                   -- what setActionBlocked said, for /ncm.radial
    confirmHeld = true,              -- ignore a confirm button already down when the wheel opened
}

local function isDown(control)
    local ok, down = pcall(Open77.input.isDown, control)
    return ok and down == true
end

local function axis(name)
    local ok, v = pcall(Open77.input.axis, name)
    return (ok and type(v) == "number") and v or 0
end

local function layoutPayload()
    local slots = {}
    for i = 1, SLOT_COUNT do
        local s = SLOTS[i]
        if s then
            local key = s.key
            if s.mapping then
                local ok, k = pcall(Open77.input.keyFor, s.mapping)
                if ok and type(k) == "string" and k ~= "" then key = k end
            end
            slots[i] = { state = 1, label = s.label, key = key, detail = s.detail }
        else
            slots[i] = { state = 0 }
        end
    end
    return {
        cmd = "layout", title = "NCM", slots = slots,
        hint = ("release to open  ·  %s / %s"):format(keyboardKey(), padControl()),
    }
end

local function setBlocked(on)
    -- Only what a direction key or a click would otherwise do on foot. Driving is deliberately not blocked:
    -- a wheel that could take the car off a driver mid-corner is worse than one that shares the stick.
    local results = {}
    for _, action in ipairs({ "Movement", "Attack" }) do
        local ok, r, why = pcall(Open77.input.setActionBlocked, action, on)
        results[#results + 1] = action .. "=" .. (ok and tostring(r) .. (why and ("(" .. tostring(why) .. ")") or "") or ("error:" .. tostring(r)))
    end
    W.blocked = table.concat(results, " ")
end

local function angleOf(x, y)       -- x right, y up; 0 = up, clockwise
    local a = math.deg(math.atan(x, y))
    if a < 0 then a = a + 360 end
    return a
end

local function slotOf(angle)
    return (math.floor(((angle + 22.5) % 360) / 45) % SLOT_COUNT) + 1
end

local function aim()
    -- Controller: whichever stick is pushed further. Right is the vanilla wheel's stick; left is accepted because
    -- on foot it is where the thumb already is (movement is blocked while the wheel is up).
    local rx, ry = axis("padRightStickX"), axis("padRightStickY")
    local lx, ly = axis("padLeftStickX"), axis("padLeftStickY")
    local x, y = rx, ry
    if (lx * lx + ly * ly) > (rx * rx + ry * ry) then x, y = lx, ly end
    if (x * x + y * y) >= STICK_ON * STICK_ON then return angleOf(x, y) end

    -- Keyboard: eight directions from WASD and the arrows.
    local dx = ((isDown("D") or isDown("Right")) and 1 or 0) - ((isDown("A") or isDown("Left")) and 1 or 0)
    local dy = ((isDown("W") or isDown("Up")) and 1 or 0) - ((isDown("S") or isDown("Down")) and 1 or 0)
    if dx ~= 0 or dy ~= 0 then return angleOf(dx, dy) end

    -- Mouse: a flick, accumulated and clamped, as the vanilla wheel reads it. Screen Y grows downwards.
    local mx, my = axis("mouseDeltaX"), axis("mouseDeltaY")
    if mx ~= 0 or my ~= 0 then
        local m = W.mouse
        m.x, m.y = m.x + mx, m.y - my
        local len = math.sqrt(m.x * m.x + m.y * m.y)
        if len > MOUSE_CLAMP_PX then m.x, m.y = m.x / len * MOUSE_CLAMP_PX, m.y / len * MOUSE_CLAMP_PX; len = MOUSE_CLAMP_PX end
        if len >= MOUSE_AIM_PX then return angleOf(m.x, m.y) end
    end
    return nil
end

local function sendFrame()
    send({ cmd = "frame", open = W.open, sel = W.sel and (W.sel - 1) or -1, pointer = W.pointer or -1 })
end

local function openWheel(source)
    W.open, W.source, W.sel, W.pointer = true, source, nil, nil
    W.mouse.x, W.mouse.y = 0, 0
    W.confirmHeld = isDown("LeftMouse") or isDown("padA")
    if not layoutSent then layoutSent = send(layoutPayload()) end
    setBlocked(true)
    sendFrame()
end

local function run(slot)
    if not (slot and slot.id) then return end
    CreateThread(function()
        local promise, reason = Open77.exports.call("ncm_world", "quickAction", slot.id)
        if not promise then log("%s: ncm_world unreachable (%s)", slot.id, tostring(reason)); return end
        local ok, why = promise:await()
        if not ok then log("%s: %s", slot.id, tostring(why)) end
    end)
end

local function closeWheel(commit)
    local chosen = commit and W.sel and SLOTS[W.sel] or nil
    W.open, W.source, W.sel, W.pointer = false, nil, nil, nil
    setBlocked(false)
    sendFrame()
    run(chosen)
end

local wasDown = { key = false, pad = false }

CreateThread(function()
    Wait(3000)                                   -- let the plugin and permissions settle
    while true do
        -- Transport upkeep: retry a missing plugin slowly, ping a present one for health.
        local t = now()
        if not surface and t - lastAttemptAt > (attempts < PORT_SPAN and 1500 or 15000) then
            lastAttemptAt = t
            bringUp()
        elseif surface and surfaceReady and t - lastAttemptAt > 3000 then
            lastAttemptAt = t
            send({ cmd = "ping" })
            if not layoutSent then layoutSent = send(layoutPayload()) end
        end

        local captured = false
        pcall(function() captured = Open77.input.isCaptured() == true end)
        local keyDown, padDown = isDown(keyboardKey()), isDown(padControl())

        if not W.open then
            -- Opens on the press edge only, and never over a focused surface (the F6 hub owns input then).
            if not captured and keyDown and not wasDown.key then openWheel("key")
            elseif not captured and padDown and not wasDown.pad then openWheel("pad") end
        else
            local held = (W.source == "key") and keyDown or padDown
            local confirm = isDown("LeftMouse") or isDown("padA")
            if captured then
                closeWheel(false)                -- something else took input: stand down, run nothing
            elseif not held then
                closeWheel(true)
            elseif confirm and not W.confirmHeld and W.sel then
                closeWheel(true)
            else
                if not confirm then W.confirmHeld = false end
                local a = aim()
                if a then
                    W.pointer = a
                    W.sel = slotOf(a)
                elseif W.sel then
                    W.pointer = (W.sel - 1) * 45
                end
                sendFrame()
            end
        end
        wasDown.key, wasDown.pad = keyDown, padDown
        Wait(W.open and OPEN_TICK_MS or IDLE_TICK_MS)
    end
end)

-- ------------------------------------------------------------------------------------------------------------
-- /ncm.radial                     status: transport, plugin, host, bindings, last block result
-- /ncm.radial pad <control>       controller button when the mapping cannot be rebound (padStart, padBack, ...)
-- /ncm.radial input               three seconds of raw aim readings, for tuning the mouse and sticks
-- ------------------------------------------------------------------------------------------------------------
RegisterCommand("ncm.radial", function(_, args)
    local sub = args and args[1]
    if sub == "pad" and args[2] then
        pcall(SetResourceKvp, PAD_KVP, tostring(args[2]))
        layoutSent = false
        log("controller button set to %s%s", tostring(args[2]),
            padMappingOk and " (the pause-menu binding, if set, still wins)" or "")
        return
    end
    if sub == "input" then
        CreateThread(function()
            for _ = 1, 30 do
                log("R(%.2f,%.2f) L(%.2f,%.2f) mouseDelta(%.1f,%.1f) key=%s pad=%s",
                    axis("padRightStickX"), axis("padRightStickY"), axis("padLeftStickX"), axis("padLeftStickY"),
                    axis("mouseDeltaX"), axis("mouseDeltaY"), tostring(isDown(keyboardKey())), tostring(isDown(padControl())))
                Wait(100)
            end
        end)
        return
    end
    log("transport: %s (%s)", surfaceReady and "connected" or (surface and "connecting" or "down"), url())
    if health then
        log("plugin %s  host=%s  drawn=%s  open=%s  staleClosed=%s", tostring(health.version), tostring(health.host),
            tostring(health.drawn), tostring(health.open), tostring(health.staleClosed))
    else
        log("plugin: not heard from -- is the ncm-radial required mod installed?")
    end
    log("keyboard: %s   controller: %s (%s)", keyboardKey(), padControl(),
        padMappingOk and "pause-menu binding" or "/ncm.radial pad")
    log("last block result: %s", tostring(W.blocked or "never opened"))
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    if W.open then setBlocked(false) end
    send({ cmd = "frame", open = false, sel = -1, pointer = -1 })
    tearDown("resource stop")
end)
