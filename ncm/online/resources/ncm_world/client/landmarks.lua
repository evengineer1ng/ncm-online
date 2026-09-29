-- ncm_world / client / landmarks -- NCM's named places, on the player's own map.
--
-- **Why.** NCM's race messaging already speaks in node names -- "Pothole", "Deep Dive", "Japantown Crossway" --
-- but the map had never heard of them, so the vocabulary was private to the server. That is fine until
-- automatic navigation fails, at which point a driver who has been told to get to Pothole has no way to find
-- Pothole. These pins are the fallback navigation layer: open the map, find the name, set an ordinary
-- Cyberpunk waypoint on it, carry on. They are also the cheapest way to make the node names mean something
-- shared rather than something internal.
--
-- **Feasibility, checked before building (owner's scope limit).** This is not a reverse-engineering project:
-- `Open77.blips.create{ position, sprite, title, description }` is the supported API the platform's own
-- freeroam gamemode uses for exactly this, at `gamemodes/freeroam/client/main.lua`, with
-- `open77:worldReady` as the creation signal. Nothing here is invasive and nothing is duplicated.
--
-- **Single source.** Names and coordinates come from `data.nodes`, the same canonical module the routes and
-- race messaging read. No second dataset, no hand-copied coordinates -- a node added there appears here.
--
-- Deliberately NOT routable and never tracked: these are landmarks, not destinations. `client/nav.lua` owns
-- the one blip that is allowed to steer the GPS, and two systems fighting over the route selection is the
-- exact failure this release is fixing.
local SPRITE = "fast_travel"     -- the platform's own sprite for a named place worth travelling to

local handles = {}
local shown = false
local wanted = true   -- the player's /ncm.nodes choice; a world rebuild must not undo it

local function log(fmt, ...)
    print(("[ncm_world/client/landmarks] " .. fmt):format(...))
end

-- **KB-203: pins made before the player's world exists are lost with it.** Resources start in the pre-game
-- menu world; OPEN//77 then loads the character save, which replaces that world and every native mappin in it,
-- while `Open77.blips` still reports the handles as owned and active. Observed 2026-09-28: 88 pins created at
-- 23:10:27, save load 23:10:28, loading bar full 23:10:38, player at spawn ~23:10:47 -- no pin visible; probe
-- pins created later all visible. There is no documented "entered the world" event, so each map layer
-- registers a rebuild here and the gate runs it once the local body is settled away from the menu origin, again
-- 20 s later as a safety net, and again after any later `open77:worldReady` (a fresh world).
NcmMapPins = NcmMapPins or { layers = {} }
local function settled()
    local stable, last = 0, nil
    while stable < 5 do
        Wait(1000)
        local ok, st = pcall(Open77.character.state)
        local p = ok and type(st) == "table" and st.position or nil
        if type(p) == "table" and type(p.x) == "number" and math.abs(p.x) + math.abs(p.y) > 100 and st.alive ~= false then
            if last and math.abs(p.x - last.x) + math.abs(p.y - last.y) < 3 then stable = stable + 1 else stable = 0 end
            last = { x = p.x, y = p.y }
        else stable, last = 0, nil end
    end
end
local epoch = 0
local function rebuildAll(why)
    for name, fn in pairs(NcmMapPins.layers) do
        local ok, err = pcall(fn)
        if not ok then log("map layer %s rebuild failed (%s): %s", name, why, tostring(err)) end
    end
end
local function gate(why)
    epoch = epoch + 1
    local mine = epoch
    CreateThread(function()
        settled()
        if mine ~= epoch then return end
        log("player settled in world (%s); building map pins", why)
        rebuildAll(why)
        Wait(20000)
        if mine ~= epoch then return end
        rebuildAll(why .. "+20s")
    end)
end
function NcmMapPins.register(name, rebuild) NcmMapPins.layers[name] = rebuild end
local gateStarted = false
AddEventHandler("open77:worldReady", function()
    -- the first signal only starts the gate; a later one means the world was replaced under our pins
    gate(gateStarted and "worldReady" or "start"); gateStarted = true
end)
CreateThread(function() Wait(1000); if not gateStarted then gateStarted = true; gate("start") end end)

local function nodes()
    local ok, M = pcall(NcmCore.get, "data.nodes")
    if not ok or type(M) ~= "table" or type(M.LIST) ~= "table" then return nil end
    return M.LIST
end

local function remove()
    for _, h in ipairs(handles) do pcall(Open77.blips.remove, h) end
    handles = {}
    shown = false
end

local function create()
    if shown then return end
    local list = nodes()
    if not list then log("data.nodes unavailable; no landmarks drawn"); return end
    local made, failed = 0, nil
    for _, n in ipairs(list) do
        -- `waypointable` is the node's own statement that it is a place a driver can be sent to. A node that
        -- is not waypointable is route geometry, not a landmark, and drawing it would be noise.
        if n.waypointable and type(n.x) == "number" then
            local ok, id, reason = pcall(Open77.blips.create, {
                position = { x = n.x, y = n.y, z = n.z or 0 },
                sprite = SPRITE,
                title = tostring(n.name or n.id),
                description = ("NCM location%s. Set a waypoint here to drive to it."):format(
                    n.region and (" in " .. tostring(n.region)) or ""),
            })
            if ok and id ~= nil then
                handles[#handles + 1] = id
                made = made + 1
            else
                failed = failed or tostring((not ok) and id or reason)
            end
        end
    end
    if made > 0 then
        shown = true
        log("%d landmark(s) on the map", made)
    else
        -- A build without blip creation simply has no landmarks; it is not worth a retry loop.
        log("no landmarks created (%s)", tostring(failed or "nothing waypointable"))
    end
end

-- Creation waits for the player's real world (KB-203 gate above); a rebuild replaces rather than stacks.
NcmMapPins.register("landmarks", function()
    remove()
    if wanted then create() end
end)

--- Thirty-odd pins is a real amount of map, so it is the player's call. Off is not remembered between
--- sessions on purpose: the default is the useful one, and a toggle that quietly stays off is a support
--- question later.
RegisterCommand("ncm.nodes", function()
    if shown then
        wanted = false
        remove()
        log("landmarks hidden")
        pcall(function()
            Open77.exports.call("open77_notifications", "show", { id = "ncm_nodes", replace = true, type = "info",
                title = "NCM", message = "Location names hidden. /ncm.nodes to show them again.", icon = "NCM", durationMs = 5000 })
        end)
    else
        wanted = true
        create()
        pcall(function()
            Open77.exports.call("open77_notifications", "show", { id = "ncm_nodes", replace = true, type = "info",
                title = "NCM", message = "NCM locations are on your map. /ncm.nodes to hide them.", icon = "NCM", durationMs = 5000 })
        end)
    end
end, false)

--- KB-203 probe. Every create() has returned an id while the owner sees no pin, so ask the platform what it
--- thinks this resource owns, then drop one test pin per candidate sprite around the player (8 m apart).
--- Whichever of these shows on the map is the sprite the landmark and fuel layers should use. Run again to clear.
local probe = {}
RegisterCommand("ncm.blips", function()
    if #probe > 0 then
        for _, h in ipairs(probe) do pcall(Open77.blips.remove, h) end
        probe = {}
        log("probe pins removed")
        return
    end
    local ok, list, reason = pcall(Open77.blips.list)
    if ok and type(list) == "table" then
        local active, bySprite = 0, {}
        for _, b in ipairs(list) do
            if b.active ~= false then active = active + 1 end
            local s = tostring(b.sprite); bySprite[s] = (bySprite[s] or 0) + 1
        end
        local parts = {}
        for s, n in pairs(bySprite) do parts[#parts + 1] = s .. "=" .. n end
        log("owned blips: %d (%d active) | %s", #list, active, table.concat(parts, " "))
        if list[1] then
            local b = list[1]
            log("sample: id=%s sprite=%s active=%s range=%s icon=%s pos=%s", tostring(b.id), tostring(b.sprite),
                tostring(b.active), tostring(b.range), tostring(b.icon),
                type(b.position) == "table" and ("%.0f,%.0f"):format(b.position.x or 0, b.position.y or 0) or "-")
        end
    else
        log("blips.list refused: %s", tostring((not ok) and list or reason))
    end
    local okS, st = pcall(Open77.character.state)
    local pos = okS and type(st) == "table" and st.position or nil
    if type(pos) ~= "table" then log("probe skipped: no local position"); return end
    local sprites = { "objective", "quest", "vendor", "fast_travel" }
    for i, s in ipairs(sprites) do
        local okC, id, why = pcall(Open77.blips.create, {
            position = { x = pos.x + (i - 2.5) * 8, y = pos.y, z = pos.z },
            sprite = s, title = "NCM probe: " .. s, description = "KB-203 blip probe. /ncm.blips again to clear.",
            active = true })
        if okC and id then probe[#probe + 1] = id end
        log("probe %s -> %s", s, (okC and id) and tostring(id) or tostring((not okC) and id or why))
    end
    pcall(function()
        Open77.exports.call("open77_notifications", "show", { id = "ncm_blips", replace = true, type = "info",
            title = "NCM", message = "4 probe pins dropped around you (west to east: objective, quest, vendor, fast_travel). Open the map; say which appear.",
            icon = "NCM", durationMs = 10000 })
    end)
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then
        remove()
        for _, h in ipairs(probe) do pcall(Open77.blips.remove, h) end
    end
end)
