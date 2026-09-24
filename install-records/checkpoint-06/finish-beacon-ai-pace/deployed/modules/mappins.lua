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

-- NcmRaceBeaconSystem (r6/scripts/MT_Ecosystem/MTERaceBeacon.reds): a ScriptableSystem that owns
-- the start/finish pins and the GPS waypoint. Called directly from Lua, so there is no UI-event
-- bridge to lose and every call returns something we can log. Falls back to the legacy event
-- path when the system is not compiled in.
local _beaconMissingLogged = false
local function beacon()
    local ok, sys = pcall(function()
        local container = Game.GetScriptableSystemsContainer()
        return container and container:Get("NcmRaceBeaconSystem") or nil
    end)
    if ok and sys then return sys end
    if not _beaconMissingLogged then
        _beaconMissingLogged = true
        print("[NCM/Mappins] NcmRaceBeaconSystem not available (" .. tostring(sys) .. ") - using legacy event pins")
    end
    return nil
end

local function beaconStatus(sys)
    local ok, st = pcall(function() return sys:Status() end)
    return ok and tostring(st) or ("status error: " .. tostring(st))
end

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

    local sys = beacon()
    if sys then
        local ok, res = pcall(function()
            return sys:PlaceWaypoint(node.x or 0, node.y or 0, node.z or 0)
        end)
        if ok and res then
            activeGpsWaypointId = "beacon"
            activeGpsWaypointKey = key
            print("[NCM/Mappins] GPS waypoint placed via beacon @ "
                .. tostring(node.x or 0) .. "," .. tostring(node.y or 0) .. " (" .. beaconStatus(sys) .. ")")
            return
        end
        print("[NCM/Mappins] beacon PlaceWaypoint failed: " .. tostring(res) .. " - falling back")
    end

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
        if activeGpsWaypointId == "beacon" then
            local sys = beacon()
            if sys then pcall(function() sys:ClearWaypoint() end) end
        else
            pcall(function()
                Game.GetMappinSystem():UnregisterMappin(activeGpsWaypointId)
            end)
        end
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

    -- Primary: beacon system pins (world map + minimap + in-world icon)
    local sys = beacon()
    if sys then
        if startNode then
            local ok, res = pcall(function()
                return sys:PlaceStart(startNode.x or 0, startNode.y or 0, startNode.z or 0,
                    "Race Start" .. (startNode.name and (": " .. tostring(startNode.name)) or ""))
            end)
            print("[NCM/Mappins] beacon START " .. (ok and tostring(res) or ("error " .. tostring(res)))
                .. " @ " .. tostring(startNode.x or 0) .. "," .. tostring(startNode.y or 0))
        end
        if finishNode then
            local ok, res = pcall(function()
                return sys:PlaceFinish(finishNode.x or 0, finishNode.y or 0, finishNode.z or 0,
                    "RACE FINISH" .. (finishNode.name and (": " .. tostring(finishNode.name)) or ""))
            end)
            print("[NCM/Mappins] beacon FINISH " .. (ok and tostring(res) or ("error " .. tostring(res)))
                .. " @ " .. tostring(finishNode.x or 0) .. "," .. tostring(finishNode.y or 0))
        end
        print("[NCM/Mappins] beacon status: " .. beaconStatus(sys))
    end

    -- Legacy event pins are kept as a second layer (harmless if both render).

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
    local sys = beacon()
    if sys then pcall(function() sys:ClearPins() end) end
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

--- Diagnostic: drop a start pin at the player and a finish pin + GPS waypoint 60 m ahead.
--- CET console:  MTE.Mappins.testHere()      (clear with MTE.Mappins.clearRaceMarkers())
function Mappins.testHere()
    local player = Game.GetPlayer()
    if not player then print("[NCM/Mappins] testHere: no player") return end
    local p = player:GetWorldPosition()
    local f = player:GetWorldForward()
    local startNode = { x = p.x, y = p.y, z = p.z, name = "test" }
    local finishNode = { x = p.x + f.x * 60.0, y = p.y + f.y * 60.0, z = p.z, name = "test" }
    Mappins.showRaceMarkers(startNode, finishNode)
    Mappins.setGpsWaypoint(finishNode)
    print("[NCM/Mappins] testHere: pins placed; open the map / look 60 m ahead")
end

function Mappins.update(dt)
    -- reserved for future use
end

return Mappins



