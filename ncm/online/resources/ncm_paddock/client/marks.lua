-- ncm_paddock / client / marks -- a point-marking tool for authoring ovals (and anything else) in game (L236).
--
-- The owner knows where each roundabout's poles are but not their coordinates. Set a waypoint on the map where a
-- point should go (or stand on it) and type `/ncm.mark`. Each mark:
--   * drops a numbered map pin, so the set can be seen and checked before anything is built from it;
--   * writes one line to this client's own log (`red4ext/logs/open77-*.log`) in a fixed shape, which the build
--     tooling reads back: `NCMMARK {"set":"corpo_plaza","n":1,"x":..,"y":..,"z":..,"src":"waypoint","label":".."}`.
-- Nothing is sent to the server or stored anywhere else: marks are authoring notes, not game state.
--
--   /ncm.mark [label]        mark the map waypoint (or, with none set, where you stand); clears the waypoint after
--   /ncm.mark.here [label]   mark where you stand, ignoring any waypoint (the exact ground height)
--   /ncm.mark.set <name>     start (or switch to) a named set, e.g. /ncm.mark.set corpo_plaza
--   /ncm.mark.undo           drop the last mark of the current set
--   /ncm.mark.list           print the current set again (the log gets a fresh copy)
--   /ncm.mark.clear          forget the current set and its pins
local function log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    print("[ncm_paddock/marks] " .. (ok and line or tostring(fmt)))
end

local current = "oval"
local sets = {}          -- name -> { { x, y, z, src, label, pin } }

local function toast(msg)
    log("%s", msg)
    TriggerServerEvent("ncm:broadcast.toast", { message = msg })
end

local function num(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end

local function emit(name, i, m)
    -- a fixed, greppable, machine-readable line: tools read these back out of the client log
    print(('NCMMARK {"set":"%s","n":%d,"x":%.2f,"y":%.2f,"z":%.2f,"src":"%s","label":"%s"}'):format(
        name, i, m.x, m.y, m.z, m.src, tostring(m.label or ""):gsub('[%c"\\]', "")))
end

local function here()
    local ok, st = pcall(Open77.character.state)
    if ok and type(st) == "table" and type(st.position) == "table" then return st.position end
    return nil
end

local function pinFor(name, i, m)
    local ok, id = pcall(Open77.blips.create, { position = { x = m.x, y = m.y, z = m.z }, sprite = "vendor",   -- a sprite NCM already uses (fuel stations); proven to draw
        title = ("%s #%d"):format(name, i), description = ("NCM mark%s · %.1f, %.1f, %.1f"):format(m.label ~= "" and (" · " .. m.label) or "", m.x, m.y, m.z) })
    return ok and id or nil
end

local function add(label, forceHere)
    local set = sets[current] or {}
    sets[current] = set
    local p, src
    if not forceHere then
        local ok, wp = pcall(Open77.blips.waypoint)
        if ok and type(wp) == "table" and wp.x then p, src = wp, "waypoint" end
    end
    if not p then p, src = here(), "here" end
    if not p then toast("Could not read a waypoint or your position.") return end
    local m = { x = num(p.x), y = num(p.y), z = num(p.z), src = src, label = label or "" }
    set[#set + 1] = m
    m.pin = pinFor(current, #set, m)
    emit(current, #set, m)
    if src == "waypoint" then pcall(Open77.blips.clearWaypoint) end
    toast(("Marked %s #%d (%s): %.1f, %.1f, %.1f"):format(current, #set, src, m.x, m.y, m.z))
end

RegisterCommand("ncm.mark", function(_, args) add(table.concat(args or {}, " "), false) end, false)
RegisterCommand("ncm.mark.here", function(_, args) add(table.concat(args or {}, " "), true) end, false)

RegisterCommand("ncm.mark.set", function(_, args)
    local name = tostring((args or {})[1] or ""):lower():gsub("[^%w_]", "_")
    if name == "" then toast("Usage: /ncm.mark.set <name>") return end
    current = name
    toast(("Marking set '%s' (%d point(s) so far)."):format(current, #(sets[current] or {})))
end, false)

RegisterCommand("ncm.mark.undo", function()
    local set = sets[current] or {}
    local m = table.remove(set)
    if not m then toast("Nothing to undo in '" .. current .. "'.") return end
    if m.pin then pcall(Open77.blips.remove, m.pin) end
    print(('NCMMARK {"set":"%s","n":%d,"undo":true}'):format(current, #set + 1))
    toast(("Removed %s #%d."):format(current, #set + 1))
end, false)

RegisterCommand("ncm.mark.list", function()
    local set = sets[current] or {}
    for i, m in ipairs(set) do emit(current, i, m) end
    toast(("Set '%s': %d point(s), written to the log again."):format(current, #set))
end, false)

RegisterCommand("ncm.mark.clear", function()
    for _, m in ipairs(sets[current] or {}) do if m.pin then pcall(Open77.blips.remove, m.pin) end end
    print(('NCMMARK {"set":"%s","clear":true}'):format(current))
    sets[current] = {}
    toast(("Cleared '%s'."):format(current))
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    for _, set in pairs(sets) do for _, m in ipairs(set) do if m.pin then pcall(Open77.blips.remove, m.pin) end end end
end)
