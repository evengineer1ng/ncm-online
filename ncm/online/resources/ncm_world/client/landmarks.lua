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

local function log(fmt, ...)
    print(("[ncm_world/client/landmarks] " .. fmt):format(...))
end

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

-- The world has to exist before a pin can stand in it; this is the signal the platform's own gamemode waits
-- for. The delayed attempt covers a resource that starts after the world is already up, which is every
-- ordinary NCM deploy.
AddEventHandler("open77:worldReady", function() create() end)
CreateThread(function() Wait(8000); create() end)

--- Thirty-odd pins is a real amount of map, so it is the player's call. Off is not remembered between
--- sessions on purpose: the default is the useful one, and a toggle that quietly stays off is a support
--- question later.
RegisterCommand("ncm.nodes", function()
    if shown then
        remove()
        log("landmarks hidden")
        pcall(function()
            Open77.exports.call("open77_notifications", "show", { id = "ncm_nodes", replace = true, type = "info",
                title = "NCM", message = "Location names hidden. /ncm.nodes to show them again.", icon = "NCM", durationMs = 5000 })
        end)
    else
        create()
        pcall(function()
            Open77.exports.call("open77_notifications", "show", { id = "ncm_nodes", replace = true, type = "info",
                title = "NCM", message = "NCM locations are on your map. /ncm.nodes to hide them.", icon = "NCM", durationMs = 5000 })
        end)
    end
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then remove() end
end)
