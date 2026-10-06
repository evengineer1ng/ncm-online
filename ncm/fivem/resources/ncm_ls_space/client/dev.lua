-- ncm_ls_space / client / dev: get a car on a bare dev server. `/ncm.car [model]` (default: sultan) spawns a networked
-- car beside you and seats you as the driver. Dev convenience only -- NCM machine identity is minted by the server
-- the moment a driver sits in any car (server/space.lua).
-- L323: the cross-server link. `/ncm.link CODE` claims a code issued in Night City (`/ncm.link` there): one NCM driver.
RegisterCommand("ncm.link", function(_, args)
    if not args[1] then print("[ncm_ls_space] /ncm.link CODE -- get the code with /ncm.link in Night City"); return end
    TriggerServerEvent("ncm:ls:link:claim", args[1])
end, false)
RegisterCommand("ncm.tri", function() TriggerServerEvent("ncm:ls:link:tri") end, false)

RegisterCommand("ncm.car", function(_, args)
    local model = joaat(args[1] or "sultan")
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        print(("[ncm_ls_space] /ncm.car: %s is not a vehicle model"):format(tostring(args[1])))
        return
    end
    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t0 < 5000 do Wait(0) end
    local ped = PlayerPedId()
    local p, h = GetOffsetFromEntityInWorldCoords(ped, 0.0, 4.0, 0.5), GetEntityHeading(ped)
    local veh = CreateVehicle(model, p.x, p.y, p.z, h, true, false)
    SetModelAsNoLongerNeeded(model)
    SetVehicleOnGroundProperly(veh)
    TaskWarpPedIntoVehicle(ped, veh, -1)
    print(("[ncm_ls_space] /ncm.car: %s spawned"):format(args[1] or "sultan"))
end, false)
