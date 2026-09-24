-- ============================================================
-- MT_Ecosystem: modules/events.lua
-- Lightweight pub/sub event bus.
-- Usage:
--   Events.on("HardBrake", function(data) ... end)
--   Events.emit("HardBrake", { g = 0.8, speed = 120 })
--   Events.off("HardBrake", fn)   -- unregister specific listener
--   Events.clear("HardBrake")     -- remove all listeners for event
-- ============================================================

local Events = {}

-- _listeners[name] = { fn, fn, ... }
local _listeners = {}

--- Register a listener for an event.
function Events.on(name, fn)
    if not _listeners[name] then
        _listeners[name] = {}
    end
    table.insert(_listeners[name], fn)
end

--- Remove a specific listener function for an event.
function Events.off(name, fn)
    local list = _listeners[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then
            table.remove(list, i)
        end
    end
end

--- Remove all listeners for an event.
function Events.clear(name)
    _listeners[name] = nil
end

--- Fire all listeners for an event, passing data as first argument.
--- Listeners are called with pcall so one bad listener can't crash others.
function Events.emit(name, data)
    local list = _listeners[name]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, data)
        if not ok then
            print("[NCM/Events] Error in listener for '" .. tostring(name) .. "': " .. tostring(err))
        end
    end
end

--- Debug: print all registered event names and listener counts.
function Events.debug()
    for name, list in pairs(_listeners) do
        print(string.format("[NCM/Events] %s — %d listener(s)", name, #list))
    end
end

return Events
