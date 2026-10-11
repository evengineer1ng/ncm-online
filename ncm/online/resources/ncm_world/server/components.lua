-- World-side fitting authority. Runtime parking state and live handling belong here; economy remains in league.
NcmComponentInstall={}
local Cat=NcmCore.get("parts.catalogue")
local Wear=NcmCore.get("parts.wear")
local Install=NcmCore.get("engineering.installation")   -- L324: add-on families (propulsor, impulse_actuator)
local Json=NcmCore.get("vocabulary.json")
local ids=NcmCore.get("vocabulary.ids")
local hostRng=function() return math.random() end
local function now() return math.floor(Open77.time.unix()) end
local function log(fmt,...) print(("[ncm_world/components] "..fmt):format(...)) end
local function enabled() local ok,v=pcall(function() return GlobalState.ncmPartsEnabled end);return ok and v==true end
local function dec(v) if type(v)=="table" then return v end local ok,x=pcall(Json.decode,tostring(v or ""));return ok and x or nil end
local function enc(v) local ok,x=pcall(Json.encode,v);return ok and x or "{}" end
local function serverId() local ok,v=pcall(function() return GlobalState.ncmIdentity end);return ok and v and v.serverId or "ncm-dev" end

local function speedOf(v)
    local s=tonumber(v and (v.speedMps or v.speed));if s then return math.abs(s) end
    local k=tonumber(v and v.speedKph);if k then return math.abs(k)/3.6 end
    local vel=v and (v.velocity or v.linearVelocity)
    if type(vel)=="table" and tonumber(vel.x) and tonumber(vel.y) then return math.sqrt(vel.x^2+vel.y^2+(tonumber(vel.z) or 0)^2) end
    return nil
end

function NcmComponentInstall.state(assetId)
    local live=NcmVehicleAccess and NcmVehicleAccess.liveAsset and NcmVehicleAccess.liveAsset(assetId) or nil
    if not live then return {eligible=true,state="stored",reason="Machine is parked in storage"} end
    local ok,v=pcall(Open77.vehicles.get,live.vehicleId)
    if not ok or type(v)~="table" then return {eligible=false,state="unreadable",reason="Machine state is unavailable"} end
    if type(v.occupants)~="table" then return {eligible=false,state="unreadable",reason="Occupancy is unavailable"} end
    if next(v.occupants)~=nil then return {eligible=false,state="occupied",reason="Machine is occupied"} end
    local speed=speedOf(v);if not speed then return {eligible=false,state="unreadable",reason="Machine speed is unavailable"} end
    if speed>.5 then return {eligible=false,state="moving",reason="Machine must be stationary"} end
    return {eligible=true,state="parked",reason="Machine is parked and unoccupied"}
end

local function current(machineId)
    local head=MySQL.single.await([[SELECT c.configuration_id,c.revision FROM machine_configuration_current x
      JOIN machine_configuration c ON c.configuration_id=x.configuration_id WHERE x.machine_asset_id=?]],{machineId})
    if not head then return nil,"configuration_missing" end
    head.items=MySQL.query.await([[SELECT i.interface_id,i.component_asset_id,i.install_json,d.family FROM machine_configuration_item i
      JOIN component_asset a ON a.asset_id=i.component_asset_id JOIN component_design d ON d.design_id=a.design_id
      WHERE i.configuration_id=? ORDER BY i.interface_id]],{head.configuration_id}) or {}
    return head
end

--- The configuration id this Machine is running right now, or nil if it has none.
---
--- The same question `current()` answers, minus the items, exported because it is what `configuration_ref`
--- needs: the observation producer records WHICH configuration a machine was in when it was measured, so a
--- reading taken before a part was fitted stays attached to the configuration that produced it.
--- `31_CAPABILITY_AUDIT.md` section 6 settled that this can only ever be an NCM-authored record; migration
--- 031 built it. nil stays nil -- an unsupported Machine genuinely has none.
function NcmComponentInstall.currentConfiguration(machineId)
    local head=current(machineId)
    return head and head.configuration_id or nil
end

function NcmComponentInstall.apply(machineId,why)
    local rows=MySQL.query.await([[SELECT DISTINCT a.asset_id,a.exposure_m,d.family,d.effect FROM machine_configuration_current x
      JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id
      JOIN component_asset a ON a.asset_id=i.component_asset_id JOIN component_design d ON d.design_id=a.design_id
      WHERE x.machine_asset_id=? ORDER BY a.asset_id]],{machineId}) or {}
    local services=MySQL.query.await([[SELECT s.component_asset_id,s.condition_id,s.relief_m FROM component_service s
      JOIN component_asset a ON a.asset_id=s.component_asset_id
      WHERE a.machine_asset_id=? AND a.location_kind='installed' ORDER BY s.occurred_at,s.service_id]],{machineId}) or {}
    local byAsset={} for _,s in ipairs(services) do local k=tostring(s.component_asset_id);byAsset[k]=byAsset[k] or {};byAsset[k][#byAsset[k]+1]=s end
    -- L324: an add-on (a propulsor on a mount) is physics, not a handling scalar. It reaches the car through
    -- NcmEngineering and the Carrier wrench; the handling composer and the wear model never see it.
    local scalar={} for _,r in ipairs(rows) do if not Install.isAddOnFamily(r.family) then scalar[#scalar+1]=r end end
    rows=scalar
    local machineWear=Wear.machine(rows,byAsset)
    local parts={} for _,r in ipairs(rows) do parts[#parts+1]={id=r.asset_id,family=r.family,effect=tonumber(r.effect)} end
    NcmHandling.setWear(machineId,machineWear,why or "persistent component wear",false)
    if NcmEngineering and NcmEngineering.changed then pcall(NcmEngineering.changed,machineId,why) end
    return NcmHandling.setParts(machineId,parts,why or "persistent component configuration")
end

function NcmComponentInstall.install(pid,componentId,machineId,idemKey)
    if not enabled() then return nil,"Parts economy is awaiting live QA." end
    local profile=NcmIdentity.get(pid);if not profile then return nil,"no_driver" end
    local requestKey=tostring(idemKey or "");if requestKey=="" then requestKey=componentId..":"..machineId end
    local operationKey="component_fit:"..serverId()..":"..requestKey
    local prior=MySQL.single.await("SELECT machine_asset_id,component_asset_id FROM component_operation WHERE idem_key=?",{operationKey})
    if prior then
        if prior.machine_asset_id==machineId and prior.component_asset_id==componentId then return true end
        return nil,"idempotency_conflict"
    end
    local part=MySQL.single.await([[SELECT a.asset_id,a.location_kind,a.ncm_driver_id,d.design_id,d.family,d.effect,d.fitment_json,d.positions_json
      FROM component_asset a JOIN component_design d ON d.design_id=a.design_id WHERE a.asset_id=? AND a.server_id=?]],{componentId,serverId()})
    local machine=MySQL.single.await("SELECT asset_id,vehicle_key,ncm_driver_id FROM vehicle_asset WHERE asset_id=? AND server_id=?",{machineId,serverId()})
    if not part or part.ncm_driver_id~=profile.ncmDriverId or part.location_kind~="storage" then return nil,"component_not_in_storage" end
    if not machine or machine.ncm_driver_id~=profile.ncmDriverId then return nil,"machine_not_owned" end
    if Install.isAddOnFamily(part.family) then return nil,"this component installs on a mount: /ncm.eng.install" end
    local fit=Cat.resolve({supportedVehicles=dec(part.fitment_json) or {}},machine.vehicle_key);if not fit.compatible then return nil,fit.reason end
    local park=NcmComponentInstall.state(machineId);if not park.eligible then return nil,park.reason end
    -- KB-163: fitting changes which physical assets receive the Machine's pending interval. Settle the
    -- outgoing configuration first; a failed checkpoint refuses the fit instead of misattributing history.
    if NcmOdometer and NcmOdometer.flushAsset then
        local settled,settleWhy=NcmOdometer.flushAsset(machineId,"before component fit",true)
        if settled==false then return nil,settleWhy or "exposure_checkpoint_failed" end
    end
    local old,why=current(machineId);if not old then return nil,why end
    local positions=dec(part.positions_json) or {};local target={} for _,p in ipairs(positions) do target[p]=true end
    local displaced={};local seen={};local newItems={}
    for _,i in ipairs(old.items) do
        local aid=target[i.interface_id] and componentId or i.component_asset_id
        newItems[#newItems+1]={interfaceId=i.interface_id,assetId=aid,install=(aid==i.component_asset_id) and i.install_json or nil}
        if target[i.interface_id] and i.component_asset_id~=componentId and not seen[i.component_asset_id] then seen[i.component_asset_id]=true;displaced[#displaced+1]=i.component_asset_id end
        target[i.interface_id]=nil
    end
    for missing in pairs(target) do return nil,"required interface absent: "..missing end
    local newConfig=ids.uuid4(hostRng);local op=ids.uuid4(hostRng);local t=now();local rev=(tonumber(old.revision) or 0)+1
    local tx={{query=[[INSERT INTO machine_configuration
      (configuration_id,machine_asset_id,revision,operation_id,created_at,created_by_driver_id)
      SELECT ?,?,?,?,?,? FROM DUAL WHERE
      EXISTS(SELECT 1 FROM component_asset WHERE asset_id=? AND ncm_driver_id=? AND location_kind='storage') AND
      EXISTS(SELECT 1 FROM vehicle_asset WHERE asset_id=? AND ncm_driver_id=?) AND
      EXISTS(SELECT 1 FROM machine_configuration_current WHERE machine_asset_id=? AND configuration_id=?)]],
      values={newConfig,machineId,rev,op,t,profile.ncmDriverId,componentId,profile.ncmDriverId,machineId,profile.ncmDriverId,machineId,old.configuration_id}}}
    for _,i in ipairs(newItems) do -- KB-347: a nil install_json is a trailing nil, which a Lua list drops -- 3 values for 4 placeholders. NULL is spelled out.
        if i.install then tx[#tx+1]={query="INSERT INTO machine_configuration_item (configuration_id,interface_id,component_asset_id,install_json) VALUES (?,?,?,?)",values={newConfig,i.interfaceId,i.assetId,i.install}}
        else tx[#tx+1]={query="INSERT INTO machine_configuration_item (configuration_id,interface_id,component_asset_id,install_json) VALUES (?,?,?,NULL)",values={newConfig,i.interfaceId,i.assetId}} end end
    tx[#tx+1]={query=[[INSERT INTO component_operation
      (operation_id,idem_key,server_id,ncm_driver_id,machine_asset_id,component_asset_id,old_configuration_id,new_configuration_id,kind,occurred_at)
      VALUES (?,?,?,?,?,?,?,?, 'fit',?)]],values={op,operationKey,serverId(),profile.ncmDriverId,machineId,componentId,old.configuration_id,newConfig,t}}
    tx[#tx+1]={query="UPDATE machine_configuration_current SET configuration_id=? WHERE machine_asset_id=? AND configuration_id=?",values={newConfig,machineId,old.configuration_id}}
    tx[#tx+1]={query="UPDATE component_asset SET location_kind='installed',machine_asset_id=? WHERE asset_id=? AND ncm_driver_id=? AND location_kind='storage'",values={machineId,componentId,profile.ncmDriverId}}
    for _,aid in ipairs(displaced) do tx[#tx+1]={query="UPDATE component_asset SET location_kind='storage',machine_asset_id=NULL,ncm_driver_id=? WHERE asset_id=? AND machine_asset_id=?",values={profile.ncmDriverId,aid,machineId}} end
    local ok,err=MySQL.transaction.await(tx);if not ok then return nil,"fit_transaction:"..tostring(err) end
    local held=MySQL.scalar.await("SELECT configuration_id FROM machine_configuration_current WHERE machine_asset_id=?",{machineId});if held~=newConfig then return nil,"fit_not_committed" end
    local applied,applyWhy=NcmComponentInstall.apply(machineId,"component fitted")
    TriggerEvent("ncm:component.changed",pid,machineId)
    return applied~=false,applyWhy
end

local function serviceRows(componentId)
    return MySQL.query.await([[SELECT condition_id,relief_m FROM component_service
      WHERE component_asset_id=? ORDER BY occurred_at,service_id]],{componentId}) or {}
end

function NcmComponentInstall.service(pid,componentId,conditionId,idemKey)
    if not enabled() then return nil,"Parts economy is awaiting live QA." end
    local profile=NcmIdentity.get(pid);if not profile then return nil,"no_driver" end
    local requestKey=tostring(idemKey or "");if requestKey=="" then requestKey=componentId..":"..conditionId end
    local operationKey="component_service:"..serverId()..":"..requestKey
    local prior=MySQL.single.await("SELECT component_asset_id,condition_id,relief_m,amount FROM component_service WHERE idem_key=?",{operationKey})
    if prior then
        if prior.component_asset_id==componentId and prior.condition_id==conditionId then return true,prior end
        return nil,"idempotency_conflict"
    end
    local part=MySQL.single.await([[SELECT a.asset_id,a.exposure_m,a.location_kind,a.machine_asset_id,a.ncm_driver_id,d.family
      FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
      WHERE a.asset_id=? AND a.server_id=?]],{componentId,serverId()})
    if not part or part.ncm_driver_id~=profile.ncmDriverId then return nil,"component_not_owned" end
    if part.location_kind=="installed" then
        local park=NcmComponentInstall.state(part.machine_asset_id);if not park.eligible then return nil,park.reason end
        if NcmOdometer and NcmOdometer.flushAsset then
            local settled,settleWhy=NcmOdometer.flushAsset(part.machine_asset_id,"before component service",true)
            if settled==false then return nil,settleWhy or "exposure_checkpoint_failed" end
            part.exposure_m=MySQL.scalar.await("SELECT exposure_m FROM component_asset WHERE asset_id=?",{componentId}) or part.exposure_m
        end
    elseif part.location_kind~="storage" then return nil,"component_not_serviceable" end
    local quote,quoteWhy=Wear.serviceQuote(part,serviceRows(componentId),conditionId)
    if not quote then return nil,quoteWhy end
    local t=now();local serviceId=ids.uuid4(hostRng);local work=enc(quote.workmanship)
    local ok,err=MySQL.transaction.await({
      {query=[[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,asset_id)
        SELECT ?,?,'component_service',-?,'eddies',?,'Component condition service',?,?
        FROM DUAL WHERE (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?)>=?]],
       values={profile.ncmDriverId,serverId(),quote.cost,componentId,operationKey,componentId,profile.ncmDriverId,serverId(),quote.cost}},
      {query=[[INSERT INTO component_service
        (service_id,idem_key,server_id,component_asset_id,condition_id,at_exposure_m,by_driver_id,provider_kind,workmanship_json,relief_m,amount,occurred_at)
        SELECT ?,?,?,?,?,?,?,?,?,?,?,? FROM DUAL
        WHERE EXISTS(SELECT 1 FROM ledger WHERE idem_key=? AND ncm_driver_id=? AND amount=?) ]],
       values={serviceId,operationKey,serverId(),componentId,quote.conditionId,math.floor(tonumber(part.exposure_m) or 0),profile.ncmDriverId,
          quote.providerKind,work,quote.reliefM,quote.cost,t,operationKey,profile.ncmDriverId,-quote.cost}},
    })
    if not ok then return nil,"service_transaction:"..tostring(err) end
    local held=MySQL.single.await("SELECT component_asset_id,condition_id,relief_m,amount FROM component_service WHERE idem_key=?",{operationKey})
    if not held then return nil,"insufficient_funds" end
    if part.machine_asset_id then NcmComponentInstall.apply(part.machine_asset_id,"component serviced") end
    TriggerEvent("ncm:component.changed",pid,part.machine_asset_id)
    return true,held
end

RegisterNetEvent("ncm:component.install",function(componentId,machineId,idemKey)
    local pid=tonumber(source) or 0;CreateThread(function()
        local ok,why=NcmComponentInstall.install(pid,tostring(componentId or ""),tostring(machineId or ""),tostring(idemKey or ""))
        pcall(Open77.notifications.send,pid,{type=ok and "success" or "error",title=ok and "PART FITTED" or "FITTING REFUSED",message=ok and "The displaced component is in Parts Inventory." or tostring(why),icon="NCM",durationMs=6500})
        TriggerClientEvent("ncm:component.install.result",pid,{ok=ok and true or false,message=tostring(why or "")})
    end)
end)

RegisterNetEvent("ncm:component.service",function(componentId,conditionId,idemKey)
    local pid=tonumber(source) or 0;CreateThread(function()
        local ok,result=NcmComponentInstall.service(pid,tostring(componentId or ""),tostring(conditionId or ""),tostring(idemKey or ""))
        local message=ok and ("Condition serviced. Threshold relief %s m; cost €$%s."):format(tostring(result.relief_m),tostring(result.amount)) or tostring(result)
        pcall(Open77.notifications.send,pid,{type=ok and "success" or "error",title=ok and "SERVICE COMPLETE" or "SERVICE REFUSED",message=message,icon="NCM",durationMs=6500})
        TriggerClientEvent("ncm:component.service.result",pid,{ok=ok and true or false,message=message})
    end)
end)

RegisterNetEvent("ncm:component.state.request",function(machineIds)
    local pid=tonumber(source) or 0;local profile=NcmIdentity.get(pid);if not profile then return end
    CreateThread(function() local out={};for _,aid in ipairs(type(machineIds)=="table" and machineIds or {}) do
        local owner=MySQL.scalar.await("SELECT ncm_driver_id FROM vehicle_asset WHERE asset_id=?",{tostring(aid)})
        if owner==profile.ncmDriverId then out[tostring(aid)]=NcmComponentInstall.state(tostring(aid)) end
    end;TriggerClientEvent("ncm:component.state",pid,out) end)
end)

-- Physical cargo: a loose serialized component must be loaded into a called Machine's open trunk.
-- The Machine ID is the custody link; a second car or the player's garage inventory will not follow an anchor.
function NcmComponentInstall.trunk(pid,componentId,machineId,unload)
    local profile=NcmIdentity.get(pid);if not profile then return nil,"no_driver" end
    local machine=MySQL.single.await("SELECT asset_id FROM vehicle_asset WHERE asset_id=? AND server_id=? AND ncm_driver_id=?",
        {machineId,serverId(),profile.ncmDriverId})
    local part=MySQL.single.await([[SELECT asset_id,location_kind,machine_asset_id FROM component_asset
        WHERE asset_id=? AND server_id=? AND ncm_driver_id=?]],{componentId,serverId(),profile.ncmDriverId})
    if not machine or not part then return nil,"not_owned" end
    if unload then
        if part.location_kind~="trunk" or part.machine_asset_id~=machineId then return nil,"not_in_this_trunk" end
    elseif part.location_kind~="storage" or part.machine_asset_id~=nil then return nil,"not_loose_storage" end
    local live=NcmVehicleAccess and NcmVehicleAccess.liveAsset(machineId)
    if not live then return nil,"call_car_first" end
    local okV,v=pcall(Open77.vehicles.get,live.vehicleId)
    local okP,p=pcall(Open77.players.get,pid)
    if not okV or type(v)~="table" or not okP or type(p)~="table" or type(p.position)~="table" then return nil,"position_unavailable" end
    if tonumber(v.bucket)~=tonumber(p.bucket) then return nil,"different_world" end
    local x,y,z=tonumber(v.x),tonumber(v.y),tonumber(v.z)
    if not x or not y or not z then return nil,"vehicle_position_unavailable" end
    local q=p.position
    local dx,dy,dz=(tonumber(q.x) or math.huge)-x,(tonumber(q.y) or math.huge)-y,(tonumber(q.z) or math.huge)-z
    if dx*dx+dy*dy+dz*dz>16 then return nil,"stand_near_trunk" end
    local okDoor,open=pcall(Open77.vehicles.isDoorOpen,live.vehicleId,Open77.vehicles.doors.trunk)
    if not okDoor then return nil,"trunk_state_unavailable" end
    if open~=true then
        local okOpen,opened=pcall(Open77.vehicles.openDoor,live.vehicleId,Open77.vehicles.doors.trunk)
        if not okOpen or opened~=true then return nil,"trunk_could_not_open" end
    end
    if not unload then
        local count=tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM component_asset WHERE server_id=? AND machine_asset_id=? AND location_kind='trunk'",
            {serverId(),machineId})) or 0
        if count>=10 then return nil,"trunk_full" end
    end
    local changed
    if unload then changed=MySQL.update.await([[UPDATE component_asset SET location_kind='storage',machine_asset_id=NULL
        WHERE asset_id=? AND server_id=? AND ncm_driver_id=? AND location_kind='trunk' AND machine_asset_id=?]],
        {componentId,serverId(),profile.ncmDriverId,machineId})
    else changed=MySQL.update.await([[UPDATE component_asset SET location_kind='trunk',machine_asset_id=?
        WHERE asset_id=? AND server_id=? AND ncm_driver_id=? AND location_kind='storage' AND machine_asset_id IS NULL]],
        {machineId,componentId,serverId(),profile.ncmDriverId}) end
    return (tonumber(changed) or 0)>0,(tonumber(changed) or 0)>0 and nil or "custody_changed"
end

RegisterNetEvent("ncm:component.trunk",function(componentId,machineId,unload)
    local pid=tonumber(source) or 0;if pid<=0 then return end
    CreateThread(function()
        local ok,result,reason=pcall(NcmComponentInstall.trunk,pid,tostring(componentId or ""),tostring(machineId or ""),unload==true)
        local success=ok and result==true
        local why=success and "Cargo moved." or tostring(ok and reason or result)
        TriggerClientEvent("ncm:component.trunk.result",pid,{ok=success,message=why})
        pcall(Open77.notifications.send,pid,{type=success and "success" or "error",title=success and "TRUNK UPDATED" or "TRUNK REFUSED",
            message=why,icon="NCM",durationMs=5000})
    end)
end)

AddEventHandler("onResourceStart",function(name) if name~="ncm_world" then return end CreateThread(function()
    Wait(10000);local rows=MySQL.query.await([[SELECT machine_asset_id FROM machine_configuration_current]]) or {}
    for _,r in ipairs(rows) do local ok,why=pcall(NcmComponentInstall.apply,r.machine_asset_id,"resource hydration");if not ok then log("hydrate %s failed: %s",tostring(r.machine_asset_id),tostring(why)) end end
    log("hydrated %d persistent Machine configuration(s)",#rows)
end) end)
