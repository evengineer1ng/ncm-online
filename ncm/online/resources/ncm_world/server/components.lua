-- World-side fitting authority. Runtime parking state and live handling belong here; economy remains in league.
NcmComponentInstall={}
local Cat=NcmCore.get("parts.catalogue")
local Json=NcmCore.get("vocabulary.json")
local ids=NcmCore.get("vocabulary.ids")
local hostRng=function() return math.random() end
local function now() return math.floor(Open77.time.unix()) end
local function log(fmt,...) print(("[ncm_world/components] "..fmt):format(...)) end
local function enabled() local ok,v=pcall(function() return GlobalState.ncmPartsEnabled end);return ok and v==true end
local function dec(v) if type(v)=="table" then return v end local ok,x=pcall(Json.decode,tostring(v or ""));return ok and x or nil end
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
    head.items=MySQL.query.await([[SELECT i.interface_id,i.component_asset_id,d.family FROM machine_configuration_item i
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
    local rows=MySQL.query.await([[SELECT DISTINCT a.asset_id,d.family,d.effect FROM machine_configuration_current x
      JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id
      JOIN component_asset a ON a.asset_id=i.component_asset_id JOIN component_design d ON d.design_id=a.design_id
      WHERE x.machine_asset_id=? ORDER BY a.asset_id]],{machineId}) or {}
    local parts={} for _,r in ipairs(rows) do parts[#parts+1]={id=r.asset_id,family=r.family,effect=tonumber(r.effect)} end
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
    local fit=Cat.resolve({supportedVehicles=dec(part.fitment_json) or {}},machine.vehicle_key);if not fit.compatible then return nil,fit.reason end
    local park=NcmComponentInstall.state(machineId);if not park.eligible then return nil,park.reason end
    local old,why=current(machineId);if not old then return nil,why end
    local positions=dec(part.positions_json) or {};local target={} for _,p in ipairs(positions) do target[p]=true end
    local displaced={};local seen={};local newItems={}
    for _,i in ipairs(old.items) do
        local aid=target[i.interface_id] and componentId or i.component_asset_id
        newItems[#newItems+1]={interfaceId=i.interface_id,assetId=aid}
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
    for _,i in ipairs(newItems) do tx[#tx+1]={query="INSERT INTO machine_configuration_item (configuration_id,interface_id,component_asset_id) VALUES (?,?,?)",values={newConfig,i.interfaceId,i.assetId}} end
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

RegisterNetEvent("ncm:component.install",function(componentId,machineId,idemKey)
    local pid=tonumber(source) or 0;CreateThread(function()
        local ok,why=NcmComponentInstall.install(pid,tostring(componentId or ""),tostring(machineId or ""),tostring(idemKey or ""))
        pcall(Open77.notifications.send,pid,{type=ok and "success" or "error",title=ok and "PART FITTED" or "FITTING REFUSED",message=ok and "The displaced component is in Parts Inventory." or tostring(why),icon="NCM",durationMs=6500})
        TriggerClientEvent("ncm:component.install.result",pid,{ok=ok and true or false,message=tostring(why or "")})
    end)
end)

RegisterNetEvent("ncm:component.state.request",function(machineIds)
    local pid=tonumber(source) or 0;local profile=NcmIdentity.get(pid);if not profile then return end
    CreateThread(function() local out={};for _,aid in ipairs(type(machineIds)=="table" and machineIds or {}) do
        local owner=MySQL.scalar.await("SELECT ncm_driver_id FROM vehicle_asset WHERE asset_id=?",{tostring(aid)})
        if owner==profile.ncmDriverId then out[tostring(aid)]=NcmComponentInstall.state(tostring(aid)) end
    end;TriggerClientEvent("ncm:component.state",pid,out) end)
end)

AddEventHandler("onResourceStart",function(name) if name~="ncm_world" then return end CreateThread(function()
    Wait(10000);local rows=MySQL.query.await([[SELECT machine_asset_id FROM machine_configuration_current]]) or {}
    for _,r in ipairs(rows) do local ok,why=pcall(NcmComponentInstall.apply,r.machine_asset_id,"resource hydration");if not ok then log("hydrate %s failed: %s",tostring(r.machine_asset_id),tostring(why)) end end
    log("hydrated %d persistent Machine configuration(s)",#rows)
end) end)
