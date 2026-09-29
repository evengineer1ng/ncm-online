-- ncm_radial / client / radial -- the NCM quick menu.
--
-- HOLD the quick-menu key (keyboard, default B) or button (controller, default Start), point, RELEASE. Releasing
-- on a live slot runs it; releasing on nothing, or on an open slot, just closes the wheel. Left click / pad A
-- confirms early; Escape closes without running anything. Every action is also a hotkey and a chat command, and
-- those are unchanged: the wheel is a way to REACH them, not a replacement (owner, 2026-09-28).
--
-- Who does what:
--   * THIS FILE decides everything: whether the wheel is open, what is highlighted, what runs. It reads the pad
--     and keyboard physically (`Open77.input`), exactly like `ncm_world/client/nav_input.lua`.
--   * `ncm_radial.dll` (+ `ncm_radial.reds`), a required mod, only DRAWS what this file sends it, natively on the
--     HUD. The page below is transport ONLY: 16x16, invisible, never shown and never focused.
--   * `ncm_world` RUNS the action (`quickAction` export), through the same function its hotkey runs.
--
-- **The transport page must stay invisible and unfocused (`KB-182`).** 0.1.1 made it a full-screen visible
-- page so it could hold a cursor for mouse aiming, and it turned the owner's gamepad into keyboard-and-mouse from
-- the moment the resource started -- on every rejoin, since every start recreated it. No cursor, no focus, ever.
--
-- **The mouse** (first live test: "mouse still moves camera"). While the wheel is up, camera rotation is frozen
-- (`players.freezeRotation`) and the mouse's raw movement (`mouseDeltaX/Y`) aims, the way the vanilla weapon wheel
-- reads a flick. **Every release happens here in Lua** (`resetControls`), never through the page, and the resource
-- also releases once at start, so nothing a previous run held can survive a rejoin.
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
local MOUSE_AIM_PX, MOUSE_CLAMP_PX = 60, 260   -- accumulated mouse travel before it aims, and its ceiling
local OPEN_TICK_MS, IDLE_TICK_MS = 16, 50
local KEY_REFRESH_MS = 2000          -- bindings are re-read this often, not every tick

-- ------------------------------------------------------------------------------------------------------------
-- Transport: a loopback surface to the plugin (L129). The plugin owns 38560-38563 -- a range of its own, never
-- the Carrier's or Rig Bridge's. 16x16 and invisible, exactly like the Carrier's channel (`KB-182`).
-- ------------------------------------------------------------------------------------------------------------
local PORT_BASE, PORT_SPAN = 38560, 4
local portIndex = 0
local surface, surfaceReady = nil, false
local health = nil
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
-- Bindings. Both are ordinary `RegisterKeyMapping`s, so both appear in the pause menu's key-bindings tab. The
-- handlers only exist so the rows exist; the hold is read physically below, the idiom the platform's own
-- hold-to-open context menu uses. Resolved keys are CACHED: re-reading them every tick made this the costliest
-- resource on the client in the first live test.
-- ------------------------------------------------------------------------------------------------------------
local padMappingOk = false
local keys = { keyboard = KEY_DEFAULT, pad = PAD_DEFAULT, at = -KEY_REFRESH_MS }

local function refreshKeys(force)
    local t = now()
    if not force and t - keys.at < KEY_REFRESH_MS then return end
    keys.at = t
    local ok, k = pcall(Open77.input.keyFor, KEY_MAPPING)
    keys.keyboard = (ok and type(k) == "string" and k ~= "") and k or KEY_DEFAULT
    local pad = nil
    if padMappingOk then
        local okP, p = pcall(Open77.input.keyFor, PAD_MAPPING)
        if okP and type(p) == "string" and p ~= "" then pad = p end
    end
    if not pad then
        local okK, v = pcall(GetResourceKvp, PAD_KVP)
        if okK and type(v) == "string" and v ~= "" then pad = v end
    end
    keys.pad = pad or PAD_DEFAULT
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
        log("controller mapping not accepted (%s); change the button with /ncm.radial pad <control>",
            tostring(reasonP or resultP))
    end
    refreshKeys(true)
end

-- ------------------------------------------------------------------------------------------------------------
-- The wheel
-- ------------------------------------------------------------------------------------------------------------
local W = {
    open = false, source = nil,      -- "key" | "pad"
    sel = nil,                       -- 1-based slot, sticky
    pointer = nil,                   -- degrees, nil when nothing is aimed at
    mouse = { x = 0, y = 0 },        -- accumulated raw mouse travel since the wheel opened
    controls = nil,                  -- what the control calls answered, for /ncm.radial
    confirmHeld = true,              -- a confirm button already down when the wheel opened is ignored
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
        hint = ("release to choose  ·  click / A to confirm  ·  Esc to close  ·  %s / %s"):format(keys.keyboard, keys.pad),
    }
end

-- Controls while the wheel is up: no camera turn, no firing, no aiming, no interacting. Released by
-- `resetControls`, the same single call the platform's context menu uses, so nothing is left half-restored.
local function holdControls(on)
    local p = Open77.players
    if not p then W.controls = "players API unavailable"; return end
    if on then
        local answers = {}
        for _, step in ipairs({ { "freezeRotation", true }, { "allowAim", false }, { "allowShoot", false },
                                { "allowInteraction", false } }) do
            local fn = p[step[1]]
            local ok, r = pcall(function() return fn and fn(step[2]) end)
            answers[#answers + 1] = step[1] .. "=" .. (ok and tostring(r) or ("error:" .. tostring(r)))
        end
        -- Opened from the pad nothing holds keyboard focus, so the left stick would also walk the character.
        -- The platform does not document this call's shape, so its answer is recorded rather than assumed.
        local okM, m, why = pcall(Open77.input.setActionBlocked, "Movement", true)
        answers[#answers + 1] = "Movement=" .. (okM and (tostring(m) .. (why and ("(" .. tostring(why) .. ")") or "")) or ("error:" .. tostring(m)))
        W.controls = table.concat(answers, " ")
    else
        pcall(function() if p.resetControls then p.resetControls() end end)
        pcall(Open77.input.setActionBlocked, "Movement", false)
    end
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
    -- Controller: whichever stick is pushed further.
    local rx, ry = axis("padRightStickX"), axis("padRightStickY")
    local lx, ly = axis("padLeftStickX"), axis("padLeftStickY")
    local x, y = rx, ry
    if (lx * lx + ly * ly) > (rx * rx + ry * ry) then x, y = lx, ly end
    if (x * x + y * y) >= STICK_ON * STICK_ON then return angleOf(x, y) end

    -- Keyboard: eight directions from WASD and the arrows.
    local dx = ((isDown("D") or isDown("Right")) and 1 or 0) - ((isDown("A") or isDown("Left")) and 1 or 0)
    local dy = ((isDown("W") or isDown("Up")) and 1 or 0) - ((isDown("S") or isDown("Down")) and 1 or 0)
    if dx ~= 0 or dy ~= 0 then return angleOf(dx, dy) end

    -- Mouse: a flick, accumulated and clamped. The camera is frozen while the wheel is up. Screen Y grows down.
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
    holdControls(true)
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

-- Every release is here, in Lua, and runs whether or not the page is healthy.
local function closeWheel(commit)
    local chosen = commit and W.sel and SLOTS[W.sel] or nil
    W.open, W.source, W.sel, W.pointer = false, nil, nil, nil
    holdControls(false)
    sendFrame()
    run(chosen)
end

AddEventHandler("open77:pauseKey", function()
    if W.open then closeWheel(false) end
end)

local wasDown = { key = false, pad = false }

CreateThread(function()
    Wait(3000)                                   -- let the plugin and permissions settle
    -- Release anything a previous run of this resource could have left held (`KB-182`): a rejoin must always
    -- start from a clean controller.
    holdControls(false)
    while true do
        local t = now()
        if not surface and t - lastAttemptAt > (attempts < PORT_SPAN and 1500 or 15000) then
            lastAttemptAt = t
            bringUp()
        elseif surface and surfaceReady and t - lastAttemptAt > 3000 then
            lastAttemptAt = t
            send({ cmd = "ping" })
            if not layoutSent then layoutSent = send(layoutPayload()) end
        end
        if not W.open then refreshKeys(false) end

        local keyDown, padDown = isDown(keys.keyboard), isDown(keys.pad)

        if not W.open then
            -- Opens on the press edge only, never over another focused surface (the F6 hub owns input then),
            -- and never when there is no plugin to draw it.
            if surfaceReady and ((keyDown and not wasDown.key) or (padDown and not wasDown.pad)) then
                local captured = false
                pcall(function() captured = Open77.input.isCaptured() == true end)
                if not captured then openWheel(keyDown and not wasDown.key and "key" or "pad") end
            end
        else
            local held = (W.source == "key") and keyDown or padDown
            local confirm = isDown("LeftMouse") or isDown("padA")
            local captured = false
            pcall(function() captured = Open77.input.isCaptured() == true end)
            if captured or not surfaceReady then
                closeWheel(false)                -- another surface took input, or the plugin went away
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
-- /ncm.radial                     status: transport, plugin, host, bindings, last control answers
-- /ncm.radial pad <control>       controller button when the mapping cannot be rebound (padStart, padBack, ...)
-- /ncm.radial input               three seconds of raw aim readings
-- /ncm.radial close               force the wheel shut and release every control (should never be needed)
-- ------------------------------------------------------------------------------------------------------------
RegisterCommand("ncm.radial", function(_, args)
    local sub = args and args[1]
    if sub == "pad" and args[2] then
        pcall(SetResourceKvp, PAD_KVP, tostring(args[2]))
        refreshKeys(true)
        layoutSent = false
        log("controller button set to %s%s", tostring(args[2]),
            padMappingOk and " (the pause-menu binding, if set, still wins)" or "")
        return
    end
    if sub == "close" then
        closeWheel(false)
        log("closed and released")
        return
    end
    if sub == "input" then
        CreateThread(function()
            for _ = 1, 30 do
                log("R(%.2f,%.2f) L(%.2f,%.2f) mouseDelta(%.1f,%.1f) key=%s pad=%s",
                    axis("padRightStickX"), axis("padRightStickY"), axis("padLeftStickX"), axis("padLeftStickY"),
                    axis("mouseDeltaX"), axis("mouseDeltaY"), tostring(isDown(keys.keyboard)), tostring(isDown(keys.pad)))
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
    log("keyboard: %s   controller: %s (%s)", keys.keyboard, keys.pad, padMappingOk and "pause-menu binding" or "/ncm.radial pad")
    log("last control answers: %s", tostring(W.controls or "never opened"))
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    if W.open then closeWheel(false) end
    tearDown("resource stop")
end)
