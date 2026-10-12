-- ncm-core module: engineering.controls
--
-- L324: controls command components; controls never define capabilities.
--
--   physical component -> exposes commands (engineering.systems.COMMANDS: throttle 0..1, discharge)
--   control source     -> binding -> component command
--
-- A binding is { control, gesture, componentId, command }. The control is a physical input name the host can read
-- (`padY`, `H` ...). Triangle is only how one owner's Hella happens to command its two devices today; another build
-- binds differently, binds one control to several propulsors (they move together), or binds nothing at all.
--
-- Gestures:
--   press  an event the moment the control goes down
--   tap    an event the moment the control goes down (owner, 2026-10-06: the hop must answer the press, not the release)
--   held   analog 1 while the control is down
--   hold   analog 1 while the control has been down at least HOLD_MS
-- When tap and hold share a control, the tap still fires on the press and the hold starts once the control has been down
-- HOLD_MS (so a long press is one tap, then the hold). Alone, a hold starts at once.
local Core = NcmCore

Core.define("engineering.controls", function(C)
    local M = { version = "0.1.0" }

    M.HOLD_MS = 180
    M.GESTURES = { press = "event", tap = "event", held = "analog", hold = "analog" }

    local PAD = { padA = true, padB = true, padX = true, padY = true, padUp = true, padDown = true, padLeft = true,
        padRight = true, padLeftShoulder = true, padRightShoulder = true, padLeftThumb = true, padRightThumb = true }
    --- Friendly names a player can type.
    M.ALIASES = { triangle = "padY", square = "padX", cross = "padA", circle = "padB", y = "padY", x = "padX",
        a = "padA", b = "padB", lb = "padLeftShoulder", rb = "padRightShoulder", l1 = "padLeftShoulder", r1 = "padRightShoulder" }

    --- A control name the host can read, or nil + reason. Single letters and digits are keyboard keys.
    function M.normalize(control)
        local c = tostring(control or "")
        local alias = M.ALIASES[c:lower()]
        if alias then return alias end
        if PAD[c] then return c end
        for k in pairs(PAD) do if k:lower() == c:lower() then return k end end
        if c:match("^%a$") then return c:upper() end
        if c:match("^%d$") then return c end
        return nil, "unknown control " .. c .. " (a letter, a digit, triangle/square/cross/circle, lb/rb, or padUp...)"
    end

    --- Does `binding` make sense for `device`? (`device.commands` = { name = "analog"|"event" }.)
    function M.check(binding, device)
        if type(binding) ~= "table" then return false, "not a binding" end
        local g = M.GESTURES[binding.gesture or ""]
        if not g then return false, "gesture must be press, tap, held or hold" end
        if not device then return false, "that component is not installed on this Machine" end
        local ctype = device.commands and device.commands[binding.command or ""]
        if not ctype then
            local names = {}
            for k in pairs(device.commands or {}) do names[#names + 1] = k end
            table.sort(names)
            return false, ("%s has no command %s (it takes: %s)"):format(device.code or "component", tostring(binding.command), table.concat(names, ", "))
        end
        if ctype ~= g then
            return false, ("%s is an %s command; bind it with %s"):format(binding.command, ctype, ctype == "event" and "press or tap" or "held or hold")
        end
        return true
    end

    function M.newState() return { ctl = {} } end

    --- Bindings whose component is not among `devices` are skipped (an uninstalled component simply stops
    --- answering; its binding comes back to life if it is installed again).
    --- `down` = { [control] = true|false } for every control the bindings name. Returns commands, events.
    function M.step(state, bindings, devices, down, nowMs)
        local byId = {}
        for _, d in ipairs(devices or {}) do byId[d.componentId] = d end
        -- which controls carry both a short and a long gesture
        local has = {}
        for _, b in ipairs(bindings or {}) do
            if byId[b.componentId] then
                has[b.control] = has[b.control] or {}
                has[b.control][b.gesture] = true
            end
        end
        local commands, events = {}, {}
        local edges = {}
        for control in pairs(has) do
            local s = state.ctl[control] or { down = false, since = 0 }
            state.ctl[control] = s
            local now = down[control] == true
            local e = { pressed = now and not s.down, released = (not now) and s.down, down = now, heldMs = 0 }
            if e.pressed then s.since = nowMs end
            if now or e.released then e.heldMs = nowMs - s.since end
            s.down = now
            edges[control] = e
        end
        local function cmd(id) commands[id] = commands[id] or {}; return commands[id] end
        for _, b in ipairs(bindings or {}) do
            local e, h = edges[b.control], has[b.control]
            if e and byId[b.componentId] then
                local split = h.tap and h.hold
                local fire = false
                if b.gesture == "press" then fire = e.pressed
                elseif b.gesture == "tap" then
                    fire = e.pressed
                elseif b.gesture == "held" then
                    if e.down then cmd(b.componentId)[b.command] = 1 end
                elseif b.gesture == "hold" then
                    if e.down and ((not split) or e.heldMs >= M.HOLD_MS) then cmd(b.componentId)[b.command] = 1 end
                end
                if fire then
                    cmd(b.componentId)[b.command] = true
                    events[#events + 1] = { control = b.control, gesture = b.gesture, componentId = b.componentId, command = b.command }
                end
            end
        end
        return commands, events
    end

    --- The distinct controls a set of bindings reads (what the host must poll).
    function M.controls(bindings)
        local seen, out = {}, {}
        for _, b in ipairs(bindings or {}) do
            if not seen[b.control] then seen[b.control] = true; out[#out + 1] = b.control end
        end
        table.sort(out)
        return out
    end

    return M
end)
