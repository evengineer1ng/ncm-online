-- MT_Diag: temporary diagnostic for Manual Transmission V10 "stuck automatic".
-- Press the bound hotkey (CET > Bindings > "MT Diag: dump state") while sitting on the vehicle.
-- Remove this folder when done.

local function safe(f, ...)
  local ok, r = pcall(f, ...)
  if ok then return r end
  return "ERR:" .. tostring(r)
end

local function dump()
  print("[MT_Diag] ---------------- dump ----------------")
  local player = Game.GetPlayer()
  if not player then print("[MT_Diag] no player") return end

  local vehicle = safe(function() return Game.GetMountedVehicle(player) end)
  print("[MT_Diag] mounted vehicle: " .. tostring(vehicle))
  if type(vehicle) ~= "userdata" then return end

  print("[MT_Diag] record: " .. tostring(safe(function() return vehicle:GetRecordID().value end)))
  print("[MT_Diag] IsA bike: " .. tostring(safe(function() return vehicle:IsA(CName("vehicleBikeBaseObject")) end))
    .. "  IsPlayerDriver: " .. tostring(safe(function() return vehicle:IsPlayerDriver() end))
    .. "  IsAttached: " .. tostring(safe(function() return vehicle:IsAttached() end)))

  -- mounting slot (MT's utils.isDriver requires 'seat_front_left')
  print("[MT_Diag] mount slot: " .. tostring(safe(function()
    local mi = Game.GetMountingFacility():GetMountingInfoSingleWithIds(player:GetEntityID())
    return Game.NameToString(mi.slotId.id) .. " parentHash=" .. tostring(mi.parentId.hash)
  end)))

  -- HUD blackboard that psiberx GameUI / hudCarController rely on
  print("[MT_Diag] UI_ActiveVehicleData: " .. tostring(safe(function()
    local defs = Game.GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UI_ActiveVehicleData)
    return "IsPlayerMounted=" .. tostring(bb:GetBool(defs.UI_ActiveVehicleData.IsPlayerMounted))
      .. " IsTPPCameraOn=" .. tostring(bb:GetBool(defs.UI_ActiveVehicleData.IsTPPCameraOn))
      .. " IsUIActive=" .. tostring(bb:GetBool(defs.UI_ActiveVehicleData.IsUIActive))
  end)))

  -- vehicle blackboard gear/speed
  print("[MT_Diag] vehicle bb: " .. tostring(safe(function()
    local defs = Game.GetAllBlackboardDefs()
    local bb = vehicle:GetBlackboard()
    return "GearValue=" .. tostring(bb:GetInt(defs.Vehicle.GearValue)) .. " SpeedValue=" .. tostring(bb:GetFloat(defs.Vehicle.SpeedValue))
      .. " RPMValue=" .. tostring(bb:GetFloat(defs.Vehicle.RPMValue))
  end)))

  -- engine option MT flips for manual mode
  print("[MT_Diag] GameOptions Vehicle/BlockChangeGear = " .. tostring(safe(function() return GameOptions.Get("Vehicle", "BlockChangeGear") end)))

  -- record data MT's cache needs
  print("[MT_Diag] record data: " .. tostring(safe(function()
    local rec = vehicle:GetRecord()
    local eng = rec:VehEngineData()
    local isBike = vehicle:IsA(CName("vehicleBikeBaseObject"))
    local dm = isBike and rec:BikeDriveModelData() or rec:VehDriveModelData()
    local gears = eng and eng:GetGearsCount() or "nil"
    return "engineData=" .. tostring(eng ~= nil) .. " gearsCount=" .. tostring(gears)
      .. " driveModel=" .. tostring(dm ~= nil) .. " gearChangeTime=" .. tostring(eng and eng:GearChangeTime())
  end)))

  -- ManualClutch native bridge presence
  print("[MT_Diag] natives: MtSetThrottle=" .. tostring(Game.MtSetThrottle ~= nil)
    .. " MtClutchEngage=" .. tostring(Game.MtClutchEngage ~= nil)
    .. " MtClutchDisengage=" .. tostring(Game.MtClutchDisengage ~= nil))

  -- quest fact MT/NCM share for clutch
  print("[MT_Diag] fact mt_clutch: " .. tostring(safe(function() return Game.GetQuestsSystem():GetFactStr("mt_clutch_engagement") end)))
  print("[MT_Diag] ---------------- end ----------------")
end

registerHotkey("mt_diag_dump", "MT Diag: dump state", dump)

registerForEvent("onInit", function()
  print("[MT_Diag] loaded. Bind 'MT Diag: dump state' in CET > Bindings, press it while on the bike.")
end)

return { dump = dump }
