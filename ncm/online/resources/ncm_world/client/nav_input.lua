-- ncm_world / client / nav_input -- the gamepad driver for every interactive NCM WebUI surface.
--
-- **Why this is Lua and not JavaScript.** A CEF page cannot see the gamepad. `Open77.input.isDown` and
-- `Open77.input.axis` are client-Lua natives and they are PHYSICAL device reads -- they do not know the
-- player's bindings and do not know whether the game is currently consuming the control. So the pad is read
-- here, turned into semantic actions ("up", "activate", "back"), and sent to the page. The page never learns
-- that a gamepad exists; `web/ncm-nav.js` only ever receives words.
--
-- **Why BACK is authoritative here and not in the page.** `KB-61`: the panel took keyboard and cursor focus,
-- and BOTH ways out ran through the page. When the page broke, the player could not move, could not open the
-- pause menu, and had to kill Cyberpunk. The rule from that incident is that nothing about releasing focus may
-- depend on the page being healthy. So a pad BACK press calls the owner's `onBack` **in Lua** and does not
-- wait for the page to agree. The page is also told, so the visual closes smoothly, but it is not consulted.
--
-- **Cost.** Polling only runs while a surface is attached. `isDown` is a native call per control per tick, so
-- the tick is 60 ms rather than per-frame, and the API's own advice is followed: press edges and hold timers,
-- never "fire every frame". Nothing here runs while the player is just driving.
local Core = NcmCore

NcmNavInput = {}

local page, owner = nil, nil
local running, polling = true, false
local padAvailable, padReason = nil, nil
local lastFamily = nil

-- Hysteresis on the stick: a direction must be pushed past ON and released below OFF before it can fire
-- again. A single threshold with a held stick is exactly the "runaway navigation" failure, because the axis
-- sits at 0.9 forever and every tick looks like a fresh press.
local STICK_ON, STICK_OFF = 0.55, 0.32
local REPEAT_FIRST_MS, REPEAT_NEXT_MS = 340, 130
local TICK_MS = 60

local BUTTONS = {
    { control = "padA", action = "activate" },
    { control = "padB", action = "back" },
    { control = "padUp", action = "up", repeats = true },
    { control = "padDown", action = "down", repeats = true },
    { control = "padLeft", action = "left", repeats = true },
    { control = "padRight", action = "right", repeats = true },
    { control = "padLeftShoulder", action = "pageUp", repeats = true },
    { control = "padRightShoulder", action = "pageDown", repeats = true },
}

local held = {}      -- control -> { since, nextAt }
local stick = {}     -- direction -> true while latched past ON

local function log(fmt, ...) print(("[ncm_world/client/nav_input] " .. fmt):format(...)) end
local function ms() return GetGameTimer() end

local function isDown(control)
    local ok, down, reason = pcall(Open77.input.isDown, control)
    if not ok then return false, tostring(down) end
    return down == true, reason
end

local function axis(name)
    local ok, value = pcall(Open77.input.axis, name)
    if not ok or type(value) ~= "number" then return nil end
    return value
end

--- Ask the platform what this machine can answer for, once, and say so out loud. A pad that cannot be read
--- is a supportable state; a pad that silently reads as "nothing pressed" is a support ticket.
local function probeDevices()
    local ok, devices = pcall(Open77.input.devices)
    if not ok or type(devices) ~= "table" then
        padAvailable, padReason = false, "devices_unavailable"
        log("input.devices unavailable (%s); gamepad navigation is off", tostring(devices))
        return
    end
    local total, ready = 0, 0
    for _, control in ipairs(devices) do
        if control.device == "gamepad" then
            total = total + 1
            if control.available == true then ready = ready + 1
            elseif not padReason then padReason = tostring(control.reason or "unavailable") end
        end
    end
    padAvailable = ready > 0
    if padAvailable then
        log("gamepad navigation available (%d/%d controls readable)", ready, total)
    else
        log("no readable gamepad (%s); keyboard and mouse only", tostring(padReason or "unknown"))
    end
end

local function tellFamily(family)
    if family == lastFamily then return end
    lastFamily = family
    if page then pcall(function() page:send("nav:family", { family = family }) end) end
end

--- Send one semantic action. The page is best-effort: a fault here must never strand the player, which is
--- the whole reason BACK is resolved before this is called.
local function sendAction(action)
    tellFamily("pad")
    if not page then return end
    pcall(function() page:send("nav:pad", { action = action }) end)
end

local function fire(action)
    if action == "back" then
        -- Authoritative, in Lua, first. See the header and `KB-61`.
        if owner and type(owner.onBack) == "function" then
            local ok, err = pcall(owner.onBack)
            if not ok then log("onBack raised: %s", tostring(err)) end
        end
        sendAction("back")
        return
    end
    sendAction(action)
end

--- One control's edge and repeat behaviour. Returns true when it should fire this tick.
local function edge(key, down, repeats)
    local now = ms()
    local state = held[key]
    if not down then
        held[key] = nil
        return false
    end
    if not state then
        held[key] = { since = now, nextAt = now + REPEAT_FIRST_MS }
        return true                                   -- the press edge
    end
    if not repeats then return false end              -- activate/back never auto-repeat
    if now >= state.nextAt then
        state.nextAt = now + REPEAT_NEXT_MS
        return true
    end
    return false
end

local function pollButtons()
    for _, entry in ipairs(BUTTONS) do
        local down = isDown(entry.control)
        if edge(entry.control, down, entry.repeats) then fire(entry.action) end
    end
end

local function pollStick()
    local x, y = axis("padLeftStickX"), axis("padLeftStickY")
    if x == nil and y == nil then return end
    -- Stick Y is positive UP, per the platform's own card. Getting this backwards is the classic bug.
    local pairs4 = {
        { dir = "left", value = -(x or 0) }, { dir = "right", value = (x or 0) },
        { dir = "up", value = (y or 0) },   { dir = "down", value = -(y or 0) },
    }
    for _, entry in ipairs(pairs4) do
        local key = "stick_" .. entry.dir
        if entry.value >= STICK_ON then
            if not stick[key] then stick[key] = true end
            if edge(key, true, true) then fire(entry.dir) end
        elseif entry.value < STICK_OFF then
            stick[key] = nil
            held[key] = nil
        end
    end
end

local function pollScroll()
    local y = axis("padRightStickY")
    if y == nil then return end
    if math.abs(y) < STICK_OFF then held["scroll"] = nil; return end
    if edge("scroll", true, true) then fire(y > 0 and "scrollUp" or "scrollDown") end
end

--- Attach a surface. `spec.onBack` is the escape hatch and is called in Lua, so make it the same function the
--- surface's own close path uses -- not a page round trip.
function NcmNavInput.attach(surfacePage, spec)
    page = surfacePage or nil
    owner = type(spec) == "table" and spec or {}
    held, stick, lastFamily = {}, {}, nil
    if padAvailable == nil then probeDevices() end
    polling = true
    if page then
        pcall(function() page:send("nav:family", { family = padAvailable and "pad" or "keyboard" }) end)
    end
    return padAvailable == true
end

function NcmNavInput.detach()
    polling = false
    page, owner = nil, nil
    held, stick, lastFamily = {}, {}, nil
end

function NcmNavInput.padAvailable() return padAvailable == true, padReason end

--- Re-probe on demand: a pad plugged in mid-session is the normal case, not an exception.
function NcmNavInput.reprobe() padReason = nil; probeDevices(); return padAvailable == true end

CreateThread(function()
    Wait(2500)                       -- let the plugin and permissions settle before the first probe
    probeDevices()
    while running do
        if polling and padAvailable then
            pollButtons()
            pollStick()
            pollScroll()
        end
        Wait(TICK_MS)
    end
end)

-- A pad can appear at any time. Cheap: one native read a second, only while nothing is attached and no pad
-- has been seen, so a player who plugs one in before opening a panel is ready when they do.
CreateThread(function()
    while running do
        Wait(5000)
        if not padAvailable then
            local down, reason = isDown("padA")
            if down or reason ~= "gamepad_not_connected" then NcmNavInput.reprobe() end
        end
    end
end)

RegisterCommand("ncm.input", function()
    local ok = padAvailable == true
    log("gamepad: %s%s", ok and "available" or "unavailable",
        ok and "" or (" (" .. tostring(padReason or "unknown") .. ")"))
    log("attached surface: %s", page and "yes" or "no")
    for _, entry in ipairs(BUTTONS) do
        local down, reason = isDown(entry.control)
        log("  %-18s %-8s %s", entry.control, tostring(down), tostring(reason or ""))
    end
    for _, name in ipairs({ "padLeftStickX", "padLeftStickY", "padRightStickY", "padLeftTrigger" }) do
        log("  %-18s %s", name, tostring(axis(name)))
    end
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then running = false; NcmNavInput.detach() end
end)
