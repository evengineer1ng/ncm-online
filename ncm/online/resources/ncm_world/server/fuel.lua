-- Persistent per-Machine fuel, driven only by accepted server odometer distance.
local Fuel=NcmCore.get("economy.fuel")
local function log(f,...) print(("[ncm_world/fuel] "..f):format(...)) end
-- Whole seconds: the host clock is fractional and `%d` refuses it (KB-206: every /ncm.refuel died on the idem key).
local function now() return math.floor(Open77.time.unix()) end
-- Owner, 2026-10-06: on the DEVELOPMENT server fuel must never stop a test flight ("fuel should be taken care of ...
-- cant get to space like this"). Development burns nothing -- not distance, not installed components -- and every tank
-- reads full. Online is untouched. A deliberate dev fuel test turns it off with the convar `ncm_dev_fuel 0`.
local function devFuel()
 local ok,id=pcall(function() return GlobalState.ncmIdentity end)
 local env=ok and type(id)=="table" and id.environment or "development"
 if tostring(env)~="development" then return false end
 local okC,v=pcall(GetConvar,"ncm_dev_fuel","1")
 return not okC or tostring(v)~="0"
end
NcmFuel_devFuel=devFuel
local state={} -- asset -> {fuelMl,capacityMl,remainderMl,dirtyMl,lastWrite,emptyNotified}

-- One map/recovery target per physical forecourt; every individual pump remains a valid refuelling point.
local Locations=NcmCore.get("data.fuel_locations")
local STATIONS=Locations.sites
local PUMPS=Locations.pumps
NcmFuel={stations=function() return STATIONS end,pumps=function() return PUMPS end}

local function send(pid,asset,s)
 if not pid or pid<=0 then return end
 TriggerClientEvent("ncm:fuel",pid,{assetId=asset,ml=s.fuelMl,capacityMl=s.capacityMl,
  pct=math.floor((s.fuelMl/s.capacityMl)*100+0.5),empty=s.fuelMl<=0})
end
local function load(asset)
 if state[asset] then return state[asset] end
 local p=Fuel.profile();local row=MySQL.single.await("SELECT fuel_ml,capacity_ml FROM machine_fuel WHERE asset_id=?",{asset})
 local s={fuelMl=row and tonumber(row.fuel_ml) or p.capacityMl,capacityMl=row and tonumber(row.capacity_ml) or p.capacityMl,
  remainderMl=0,dirtyMl=0,lastWrite=now()};state[asset]=s
 if not row then MySQL.insert.await("INSERT IGNORE INTO machine_fuel(asset_id,fuel_ml,capacity_ml,updated_at) VALUES(?,?,?,?)",{asset,s.fuelMl,s.capacityMl,now()}) end
 return s
end
-- `L208`: the handling composer and the tyre model read the tank. Only a loaded state answers; an unloaded
-- Machine is inert rather than assumed full.
NcmFuel.level=function(asset) local s=state[asset];if s then return s.fuelMl,s.capacityMl end;return nil end
local function persist(asset,s)
 MySQL.update.await("UPDATE machine_fuel SET fuel_ml=?,capacity_ml=?,updated_at=? WHERE asset_id=?",{s.fuelMl,s.capacityMl,now(),asset})
 s.dirtyMl=0;s.lastWrite=now()
end
local function notifyEmpty(pid)
 local msg="Stuck? Type /ncm.nofuel for help."
 pcall(Open77.chat.send,pid,"[NCM] "..msg)
 pcall(Open77.notifications.send,pid,{type="warning",title="OUT OF FUEL",message=msg,icon="NCM",durationMs=12000})
end
AddEventHandler("ncm:fuel:distance",function(entry,metres)
 if type(entry)~="table" or type(entry.assetId)~="string" then return end
 if devFuel() then return end
 CreateThread(function()
  local s=load(entry.assetId);local r=Fuel.burn(s.fuelMl,metres,{capacityMl=s.capacityMl},s.remainderMl)
  s.fuelMl=r.fuelMl;s.remainderMl=r.remainderMl;s.dirtyMl=s.dirtyMl+r.burnedMl
  if r.becameEmpty then
   persist(entry.assetId,s);pcall(Open77.vehicles.setEngine,entry.vehicleId,false);notifyEmpty(tonumber(entry.pid) or 0)
  elseif s.dirtyMl>=100 or now()-s.lastWrite>=30 then persist(entry.assetId,s) end
  send(tonumber(entry.pid) or 0,entry.assetId,s)
 end)
end)
-- L324: propellant drawn by an installed component (a propulsor, an impulse actuator) out of the same tank the
-- odometer burns. Whole millilitres, the remainder carried like the distance burn's. Returns the tank after the draw,
-- or nil for a bad request. An empty tank is the same event wherever it came from: engine off, the driver told.
NcmFuel.draw=function(asset,ml,pid,vehicleId)
 if type(asset)~="string" or asset=="" then return nil end
 if devFuel() then local s=load(asset);s.fuelMl=s.capacityMl;send(tonumber(pid) or 0,asset,s);return s.fuelMl,s.capacityMl,0 end
 local s=load(asset);local want=math.max(0,tonumber(ml) or 0)+(s.remainderMl or 0)
 local whole=math.floor(want);s.remainderMl=want-whole
 local before=s.fuelMl;s.fuelMl=math.max(0,s.fuelMl-whole);local burned=before-s.fuelMl;s.dirtyMl=s.dirtyMl+burned
 if before>0 and s.fuelMl<=0 then
  persist(asset,s);if vehicleId then pcall(Open77.vehicles.setEngine,vehicleId,false) end;notifyEmpty(tonumber(pid) or 0)
 elseif s.dirtyMl>=100 or now()-s.lastWrite>=30 then persist(asset,s) end
 send(tonumber(pid) or 0,asset,s)
 return s.fuelMl,s.capacityMl,burned
end
NcmFuel.ensure=function(asset) if type(asset)~="string" or asset=="" then return nil end local s=load(asset);return s.fuelMl,s.capacityMl end
AddEventHandler("ncm:vehicle:materialized",function(asset,vehicleId,pid)
 CreateThread(function() local s=load(asset);if devFuel() and s.fuelMl<s.capacityMl then s.fuelMl=s.capacityMl;persist(asset,s) end;send(tonumber(pid) or 0,asset,s);if s.fuelMl<=0 then pcall(Open77.vehicles.setEngine,vehicleId,false);notifyEmpty(tonumber(pid) or 0) end end)
end)

local function help(pid)
 local binding=NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority and NcmVehicleAccess.bindingForAuthority(pid)
 local pos=Open77.players.get(pid);pos=pos and pos.position
 local station,dist=Fuel.nearest(pos,STATIONS)
 if not station then return end
 TriggerClientEvent("ncm:fuel.route",pid,station)
 if binding and binding.vehicleId then pcall(Open77.vehicles.setEngine,binding.vehicleId,false) end
 -- No verified hand-held can asset/method is configured: use the owner's requested tow fallback. Teleport
 -- dismounts first; only after it settles do we store the empty Machine, preserving title and fuel state.
 local ok,moved=pcall(Open77.players.teleport,pid,{x=station.x,y=station.y,z=station.z+0.5},{fade=true,dismount=true})
 if ok and moved then
  if binding and NcmVehicleAccess.recoveryStore then pcall(NcmVehicleAccess.recoveryStore,binding.assetId,"out-of-fuel tow") end
  pcall(Open77.chat.send,pid,("[NCM] Towed to %s. Call the Machine from F6, then /ncm.refuel."):format(station.name))
  pcall(Open77.notifications.send,pid,{type="info",title="FUEL RECOVERY",message="No verified jerry can is configured; you were towed to the nearest station.",icon="NCM",durationMs=10000})
 else
  pcall(Open77.chat.send,pid,("[NCM] Recovery marked %s (%.1f km), but the tow was refused. Follow the route."):format(station.name,(dist or 0)/1000))
  pcall(Open77.notifications.send,pid,{type="warning",title="FUEL RECOVERY",message="Tow refused; nearest station marked.",icon="NCM",durationMs=10000})
 end
end
RegisterCommand("ncm.nofuel",function(source) local pid=tonumber(source) or 0;if pid>0 then help(pid) end end,false)

-- Finding fuel before the tank is empty must not depend on station pins rendering (KB-203): route the one
-- routable NCM nav blip — the only blip type the platform's mappin filter logs as allowed — to the nearest site.
RegisterCommand("ncm.fuel",function(source)
 local pid=tonumber(source) or 0;if pid<=0 then return end
 local pos=Open77.players.get(pid);pos=pos and pos.position
 local station,dist=Fuel.nearest(pos,STATIONS)
 if not station then pcall(Open77.chat.send,pid,"[NCM] No fuel station found near you.");return end
 TriggerClientEvent("ncm:fuel.route",pid,station,"Nearest fuel station")
 local msg=("%s, %.1f km. GPS set; park at the pumps and type /ncm.refuel."):format(station.name,(dist or 0)/1000)
 pcall(Open77.chat.send,pid,"[NCM] "..msg)
 pcall(Open77.notifications.send,pid,{type="info",title="FUEL",message=msg,icon="NCM",durationMs=8000})
end,false)

local function refuel(pid)
 local b,why=NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority and NcmVehicleAccess.bindingForAuthority(pid)
 if not b then return nil,why or "Sit in your NCM Machine at a fuel station." end
 local player=Open77.players.get(pid);local station,dist=Fuel.nearest(player and player.position,PUMPS)
 if not station or not dist or dist>18 then return nil,"Park at a marked fuel station first." end
 local profile=NcmIdentity and NcmIdentity.get and NcmIdentity.get(pid);if not profile then return nil,"Driver identity unavailable." end
 local s=load(b.assetId);local missing=math.max(0,s.capacityMl-s.fuelMl)
 if missing<=0 then return true,"Tank already full." end
 local cost=math.max(1,math.ceil((missing/1000)*2)) -- authored alpha price: €$2/L
 local sid=NcmIdentity.serverId();local idem=("fuel:%s:%s:%d"):format(station.id,b.assetId,now())
 local ok,err=MySQL.transaction.await({
  {query="INSERT IGNORE INTO economy_balance_lock(server_id,ncm_driver_id,revision) VALUES(?,?,0)",values={sid,profile.ncmDriverId}},
  {query="UPDATE economy_balance_lock SET revision=revision+1 WHERE server_id=? AND ncm_driver_id=?",values={sid,profile.ncmDriverId}},
  {query=[[INSERT IGNORE INTO ledger(ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,asset_id)
    SELECT ?,?,'fuel_purchase',-?,'eddies',?,'CHOOH2 fill',?,? FROM DUAL
    WHERE (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?)>=?]],
   values={profile.ncmDriverId,sid,cost,station.id,idem,b.assetId,profile.ncmDriverId,sid,cost}},
  {query=[[UPDATE machine_fuel SET fuel_ml=capacity_ml,updated_at=?,last_station_id=? WHERE asset_id=?
    AND EXISTS(SELECT 1 FROM ledger WHERE idem_key=? AND ncm_driver_id=? AND amount=?)]],
   values={now(),station.id,b.assetId,idem,profile.ncmDriverId,-cost}},
 })
 if not ok then return nil,"Fuel transaction failed: "..tostring(err) end
 local paid=tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM ledger WHERE idem_key=?",{idem})) or 0
 if paid<1 then return nil,"Not enough eddies for a full tank (€$"..cost..")." end
 s.fuelMl=s.capacityMl;s.remainderMl=0;s.dirtyMl=0;s.lastWrite=now();pcall(Open77.vehicles.setEngine,b.vehicleId,true);send(pid,b.assetId,s)
 return true,("Filled %.1f L for €$%d."):format(missing/1000,cost)
end
RegisterCommand("ncm.refuel",function(source)
 local pid=tonumber(source) or 0;if pid<=0 then return end
 CreateThread(function() local okCall,ok,msg=pcall(refuel,pid);if not okCall then log("refuel error player=%d: %s",pid,tostring(ok));ok,msg=nil,"Refuel failed on the server. Check your balance and tell the host." end;pcall(Open77.chat.send,pid,"[NCM] "..tostring(msg));pcall(Open77.notifications.send,pid,{type=ok and "success" or "error",title=ok and "REFUELLED" or "REFUEL REFUSED",message=tostring(msg),icon="NCM",durationMs=7000}) end)
end,false)
RegisterNetEvent("ncm:fuel.request",function() local pid=tonumber(source) or 0;local b=NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority and NcmVehicleAccess.bindingForAuthority(pid);if b then CreateThread(function() send(pid,b.assetId,load(b.assetId)) end) end end)
AddEventHandler("onPlayerDisconnected",function(pid) for asset,s in pairs(state) do if s.dirtyMl>0 then pcall(persist,asset,s) end end end)
AddEventHandler("onResourceStop",function(name) if name==GetCurrentResourceName() then for asset,s in pairs(state) do if s.dirtyMl>0 then pcall(persist,asset,s) end end end end)
