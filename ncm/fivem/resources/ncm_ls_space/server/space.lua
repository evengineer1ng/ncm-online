-- ncm_ls_space / server: moves and records (L319/L320; doc 53).
--
-- The Snowglobe frame -- the universe state {u, w} under NCM gravity -- is integrated by the player's own client every
-- frame (client/frame.lua); the client decides WHEN the GTA body must be moved (doorway, floating-origin band, home).
-- The MOVE stays the server's: a networked entity is moved by the authority (Night City §SG2), and only the requesting
-- player's own ped or the car they drive. Every move is logged with what it did (target reached, speed, owner, driver).
--
-- NCM machine identity: a UUID minted in the car's state bag the first time a driver sits in it (doc 52 §4 rule 3).
-- Known v1 gap: the universe state lives on the client; a resource restart or a crash loses it (persistence later).
local Core = NcmCore
local U = Core.get("space.universe")
local C = NcmLsConfig
U.setWorld({ earthRadius = C.earthRadius, surfaceG = C.surfaceG })

local function log(fmt, ...) print(("[ncm_ls_space] " .. fmt):format(...)) end

local function uuid()
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        return ("%x"):format(c == "x" and math.random(0, 15) or math.random(8, 11))
    end))
end

local function machineOf(veh)
    local st = Entity(veh).state
    if not st.ncmMachineId then
        st:set("ncmMachineId", uuid(), true)
        log("machine %s minted for vehicle net=%d (model %d)", st.ncmMachineId, NetworkGetNetworkIdFromEntity(veh), GetEntityModel(veh))
    end
    return st.ncmMachineId
end

-- mint identities, and record GTA's own view of high flights (the ceiling question, §LS3)
local peak = {}
CreateThread(function()
    Wait(1000)
    log("space.universe %s loaded: Snowglobe Earth radius %.0f m, surface g %.2f; Los Santos anchor %.2f, %.2f; Night City %.0f km away",
        tostring(U.version), U.BODIES.earth.radius, C.surfaceG, U.ANCHORS.los_santos.lat, U.ANCHORS.los_santos.lon,
        U.surfaceDistance("los_santos", "night_city") / 1000)
    log("doorway at game z %d; Snowglobe band %d..%d (rebase to %d); home below universe %d m over the Los Santos patch",
        C.up, C.down, C.up, C.mid, C.homeAlt)
    while true do
        Wait(500)
        for _, src in ipairs(GetPlayers()) do
            local ped = GetPlayerPed(src)
            local veh = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then machineOf(veh) end
            local z = GetEntityCoords(ped).z
            if z > (peak[src] or -1e9) then peak[src] = z end
        end
    end
end)

RegisterNetEvent("ncm:ls:rebase", function(netId, x, y, z, why)
    local src = source
    local ent = NetworkGetEntityFromNetworkId(netId)
    local ped = GetPlayerPed(src)
    if ent == 0 or not DoesEntityExist(ent) then log("rebase refused for %d: no entity %s", src, tostring(netId)); return end
    local isPed = ent == ped
    local isTheirCar = GetEntityType(ent) == 2 and GetPedInVehicleSeat(ent, -1) == ped
    if not (isPed or isTheirCar) then log("rebase refused for %d: entity %s is not theirs", src, tostring(netId)); return end
    local before = GetEntityCoords(ent)
    if tostring(why):find("DOORWAY") and NcmLsLink then NcmLsLink.discoverDomain(src, "snowglobe") end
    SetEntityCoords(ent, x, y, z, false, false, false, false)
    log("MOVE %s (%s, player %d%s): game %.0f,%.0f,%.0f -> %.0f,%.0f,%.0f | owner=%s",
        tostring(why), isPed and "on foot" or "vehicle", src, isTheirCar and (" machine " .. tostring(Entity(ent).state.ncmMachineId):sub(1, 8)) or "",
        before.x, before.y, before.z, x, y, z, tostring(NetworkGetEntityOwner(ent)))
    CreateThread(function()
        local t0 = GetGameTimer()
        for _, ms in ipairs({ 100, 500, 1500 }) do
            Wait(math.max(0, ms - (GetGameTimer() - t0)))
            if DoesEntityExist(ent) then
                local p, v = GetEntityCoords(ent), GetEntityVelocity(ent)
                log("  +%dms: z %.1f (target %.1f) | speed %.1f | owner=%s | %s", ms, p.z, z, #v, tostring(NetworkGetEntityOwner(ent)),
                    isTheirCar and (GetPedInVehicleSeat(ent, -1) ~= 0 and "driver seated" or "NO DRIVER") or "on foot")
            end
        end
    end)
end)

local lastState = {}
RegisterNetEvent("ncm:ls:state", function(active, kind, localZ, alt, uspeed, hspeed, vcirc, g)
    local src = source
    local now = GetGameTimer()
    if lastState[src] and now - lastState[src] < 900 then return end
    lastState[src] = now
    log("alt player %d %s: %s altitude %.0f m | game z %.0f (GTA peak %.0f) | speed %.1f | sideways %.1f / orbit %.1f | g %.2f",
        src, tostring(kind), active and "UNIVERSE" or "game", tonumber(alt) or -1, tonumber(localZ) or -1, peak[src] or -1,
        tonumber(uspeed) or 0, tonumber(hspeed) or 0, tonumber(vcirc) or 0, tonumber(g) or 0)
end)

RegisterNetEvent("ncm:ls:report", function(text)
    log("client %d: %s", source, tostring(text):sub(1, 300))
end)
