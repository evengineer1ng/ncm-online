-- MT_Ecosystem: modules/mappins.lua
-- Fires Redscript HUD/mappin bridge events for race marker icons.
-- GPS waypoint uses a CustomPositionVariant mappin (same type as the
-- player's map marker) placed directly via MappinSystem from CET Lua,
-- which gives the blue minimap navigation line.

local Mappins = {}
local i18n = require("modules/i18n")
local active = false
local activeGpsWaypointId = nil     -- NewMappinID for GPS waypoint
local activeGpsWaypointKey = nil    -- dedup key

local function waypointKey(node)
    if not node then return nil end
    return i18n.concat({
        tostring(math.floor(((tonumber(node.x) or 0.0) * 10.0) + 0.5)),
        tostring(math.floor(((tonumber(node.y) or 0.0) * 10.0) + 0.5)),
        tostring(math.floor(((tonumber(node.z) or 0.0) * 10.0) + 0.5)),
    }, "|")
end

-- â”€â”€ GPS waypoint (blue minimap line) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function placeGpsWaypoint(node)
    if not node then return end
    local key = waypointKey(node)
    if key == activeGpsWaypointKey then return end

    -- Remove old GPS waypoint first
    Mappins.clearGpsWaypoint()

    local ok, id = pcall(function()
        local pos = Vector4.new(node.x or 0, node.y or 0, (node.z or 0) + 0.5, 1.0)
        local mappinData = NewObject("gamemappinsMappinData")
        if not mappinData then
            -- Fallback: use direct RegisterMappin with TweakDB variant
            local system = Game.GetMappinSystem()
            return system:RegisterMappinWithObject(t"Mappins.DefaultStaticMappin", nil, pos,
                Enum.new("gamedataMappinVariant", "CustomPositionVariant"))
        end
        mappinData.mappinType = TweakDBID.new("Mappins.DefaultStaticMappin")
        mappinData.variant = Enum.new("gamedataMappinVariant", "CustomPositionVariant")
        mappinData.active = true
        return Game.GetMappinSystem():RegisterMappin(mappinData, pos)
    end)
    if ok and id then
        activeGpsWaypointId = id
        activeGpsWaypointKey = key
        print("[NCM/Mappins] GPS waypoint placed @ "
            .. tostring(node.x or 0) .. "," .. tostring(node.y or 0))
    else
        print("[NCM/Mappins] GPS waypoint FAILED: " .. tostring(id))
    end
end

function Mappins.clearGpsWaypoint()
    if activeGpsWaypointId then
        pcall(function()
            Game.GetMappinSystem():UnregisterMappin(activeGpsWaypointId)
        end)
        activeGpsWaypointId = nil
        activeGpsWaypointKey = nil
    end
end

-- â”€â”€ Race marker pins (start/finish icons on map) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Mappins.init()
    Mappins.clearRaceMarkers()
end

function Mappins.showRaceMarkers(startNode, finishNode)
    Mappins.clearRaceMarkers()

    if startNode and MTEPlaceMappinEvent then
        local evt = MTEPlaceMappinEvent.new()
        evt.posX       = startNode.x or 0
        evt.posY       = startNode.y or 0
        evt.posZ       = (startNode.z or 0) + 0.5
        evt.isStart    = true
        evt.trackAsNav = false
        evt.markerRole = "center"
        Game.GetUISystem():QueueEvent(evt)
        print("[NCM/Mappins] START event fired @ " .. tostring(evt.posX) .. "," .. tostring(evt.posY))
    end

    if finishNode and MTEPlaceMappinEvent then
        local evt = MTEPlaceMappinEvent.new()
        evt.posX       = finishNode.x or 0
        evt.posY       = finishNode.y or 0
        evt.posZ       = (finishNode.z or 0) + 0.5
        evt.isStart    = false
        evt.trackAsNav = false
        evt.markerRole = "center"
        Game.GetUISystem():QueueEvent(evt)
        print("[NCM/Mappins] FINISH event fired @ " .. tostring(evt.posX) .. "," .. tostring(evt.posY))
    end

    active = startNode ~= nil or finishNode ~= nil
end

function Mappins.clearRaceMarkers()
    if MTEClearMappinsEvent then
        local evt = MTEClearMappinsEvent.new()
        Game.GetUISystem():QueueEvent(evt)
    end
    Mappins.clearGpsWaypoint()
    active = false
    print("[NCM/Mappins] cleared")
end

-- â”€â”€ GPS waypoint public API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Mappins.setGpsWaypoint(node)
    placeGpsWaypoint(node)
end

-- Backwards compat aliases used by racing.lua / knockout.lua
function Mappins.setFinishWaypoint(node)
    placeGpsWaypoint(node)
end

function Mappins.clearFinishWaypoint()
    Mappins.clearGpsWaypoint()
end

-- Legacy track calls (no-ops now; GPS handled by CustomPositionVariant)
function Mappins.trackFinish() end
function Mappins.trackStart() end

function Mappins.isActive() return active end

function Mappins.update(dt)
    -- reserved for future use
end

return Mappins



