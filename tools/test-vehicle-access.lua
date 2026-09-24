-- Execute the real host and probe adapters against deterministic platform doubles. No live proof claimed.
local root=arg[1] or "."
local passed=0
local function check(label,value) assert(value,label); passed=passed+1; print("  PASS "..label) end
local events,localEvents,queue,probes,notices,created,registry={},{},{},{},{},{},{}
local painted={}   -- L111: a called machine wears its own finish
local results={}   -- outcome events sent to the PAGE, distinct from placement probes
local t=100
local owns=true
local failDb,failCreate=false,false
local me={ready=true,fresh=true,speed=0,position={x=0,y=0,z=0},bucket=0}
local id="10000000-0000-4000-8000-000000000001"
local id2="10000000-0000-4000-8000-000000000002"
local record="Vehicle.v_standard2_makigai_maimai"
function RegisterNetEvent(name,fn) events[name]=fn end
function AddEventHandler(name,fn) localEvents[name]=fn end
function CreateThread(fn) queue[#queue+1]=coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
local timers={}
local function drain()
    while #queue>0 do
        local co=table.remove(queue,1)
        local ok,ms=coroutine.resume(co); assert(ok,ms)
        if coroutine.status(co)~="dead" then
            if ms==0 then queue[#queue+1]=co else timers[#timers+1]=co end
        end
    end
end
function TriggerClientEvent(name,pid,token,origin)
    if name=="ncm:vehicle.probe" then probes[#probes+1]={name=name,pid=pid,token=token,origin=origin}
    else results[#results+1]={name=name,pid=pid,payload=token} end
end
local function lastResult() return results[#results] end
local registrations={}
function TriggerEvent(...) registrations[#registrations+1]={...} end
NcmIdentity={get=function(pid) return {ncmDriverId="driver"..pid,serverId="test"} end}
MySQL={isReady=function() return true end,single={await=function(sql,params)
    assert(sql:find("SELECT") and sql:find("ncm_driver_id") and sql:find("server_id"))
    if failDb then error("db down") end
    if owns and params[2]=="driver1" then return {asset_id=params[1],record=record,vehicle_key="makigai_maimai"} end
end}}
Open77={time={unix=function() return t end},notifications={send=function(_,n) notices[#notices+1]=n end},
    players={get=function() return me end,all=function() return {1} end},
    vehicles={get=function(vid) return registry[vid] end,all=function() return {} end,
        create=function(def) if failCreate then return nil,"refused" end; created[#created+1]=def; registry[#created]=def; return #created end,
        remove=function(vid) registry[vid]=nil; return true end,
        setPaint=function(vid,paint) painted[#painted+1]={vid=vid,paint=paint}; return true end}}
NcmCore = dofile(root.."/ncm/core/init.lua")
for _,f in ipairs(dofile(root.."/ncm/core/MANIFEST.lua")) do dofile(root.."/ncm/core/"..f) end
NcmCore.warm()
dofile(root.."/ncm/online/resources/ncm_world/server/vehicle_access.lua")
local function call(asset,pid) source=pid or 1; events["ncm:vehicle.call"](asset or id); drain() end
local function reply(pose,pid,token) source=pid or 1; events["ncm:vehicle.probed"](token or probes[#probes].token,pose); drain() end
local pose={x=0,y=8,z=.35,yaw=0}
call(id,2); check("non-owner receives no probe",#probes==0)
-- The button must react to every outcome, including refusals: a press that changes nothing reads as broken.
check("non-owner is still told why",lastResult() and lastResult().name=="ncm:vehicle.result"
    and lastResult().payload.state=="fail")
call(); check("owner receives placement probe",#probes==1)
reply(pose,2); check("another player cannot finish owner's call",#created==0)
reply(pose,1,"wrong"); check("wrong token cannot materialize",#created==0)
owns=false; reply(pose); check("ownership rechecked after probe",#created==0)
owns=true;t=t+4;call();reply(nil);check("failed placement creates nothing",#created==0)
check("a refused placement reports a reason the player can act on",
    lastResult().payload.state=="fail" and #tostring(lastResult().payload.message)>0)
-- "checking" is not "succeeded": the button must not go green merely because the server started looking.
t=t+4;call();check("the probe request acknowledges as pending, not success",
    lastResult().payload.state=="pending")
reply(nil)
t=t+4;call();reply({x=0,y=800,z=0,yaw=0});check("distant client pose rejected",#created==0)
t=t+4;call();reply({x=0/0,y=8,z=0,yaw=0});check("non-finite client pose rejected",#created==0)
t=t+4;call();me.bucket=1;reply(pose);check("bucket change rejected",#created==0);me.bucket=0
t=t+4;call();me.position.x=2;reply(pose);check("movement invalidates probe",#created==0);me.position.x=0
t=t+4;call();reply(pose);check("exact owned record materialized",#created==1 and created[1].record==record)
check("success reaches the button",lastResult().payload.state=="ok")
-- L111: colour is part of which machine this is. It reached for a global in another Lua VM and silently
-- never applied, which is why an owned MaiMai came back green and then red.
check("a called machine is painted its own finish",#painted==1 and painted[1].paint and painted[1].paint.primary)
check("persistent asset accompanies runtime registration",registrations[#registrations][7]==id)
reply(pose);t=t+4;call();check("replay and repeated CALL reuse existing representation",#created==1)
t=t+4;call(id2);reply(pose);check("two examples of same model remain distinct",#created==2 and registrations[#registrations][7]==id2)
-- Owner QA 2026-09-23: a called car outlived its owner's session and sat on the road forever. Ownership is
-- untouched by reclaiming it; CALL brings it straight back.
t=t+4;call();reply(pose)
local liveBefore=0; for _ in pairs(registry) do liveBefore=liveBefore+1 end
check("a car is in the world before the owner leaves",liveBefore>0)
localEvents.onPlayerDisconnected(1); drain()
local liveAfter=0; for _ in pairs(registry) do liveAfter=liveAfter+1 end
check("the called car is reclaimed when its owner disconnects",liveAfter<liveBefore)

localEvents.onResourceStop("ncm_world");check("resource stop removes runtime vehicles",next(registry)==nil)
t=t+4;failDb=true;call();check("database failure fails closed",#created==2);failDb=false
t=t+4;call();failCreate=true;reply(pose);check("create refusal never mints replacement",#created==2);failCreate=false
t=t+4;call();localEvents.onPlayerDisconnected(1);reply(pose);check("disconnect invalidates pending request",#created==2)
t=t+4;call();t=t+11;reply(pose);check("expired probe refused",#created==2)

-- Real client probe: flat support, wall, unsupported ground, ray failure, movement and being seated.
events={};queue={};timers={}
local probeMode="clear"
local state={alive=true,grounded=true,inVehicle=false,speed=0,position={x=0,y=0,z=0},yaw=0}
local results={}
Open77.character={state=function() return state end}
-- the client half legitimately reads a monotonic clock (client/calendar.lua does the same)
Open77.time.monotonic=function() return t end
Open77.world={raycast=function(a,b)
    if probeMode=="unavailable" then return nil end
    if probeMode=="wall" then return {hit=true,position={x=a.x,y=a.y,z=.5},normal={z=0}} end
    if a.z>b.z and b.z<0 then
        if probeMode=="void" then return {hit=false} end
        return {hit=true,position={x=a.x,y=a.y,z=0},normal={z=probeMode=="slope" and .5 or 1}}
    end
    if probeMode=="overhead" and b.z>a.z then return {hit=true} end
    if probeMode=="blocked_lane" and a.z==b.z then return {hit=true} end
    return {hit=false}
end}
function TriggerServerEvent(_,token,result) results[#results+1]={token=token,pose=result} end
dofile(root.."/ncm/online/resources/ncm_world/client/vehicle_access.lua")
local function runProbe(mode)
    probeMode=mode;events["ncm:vehicle.probe"]("probe",{x=0,y=0,z=0});drain();return results[#results].pose
end
check("clear grounded footprint yields candidate",runProbe("clear")~=nil)
for _,mode in ipairs({"wall","void","slope","unavailable","overhead","blocked_lane"}) do check(mode.." geometry fails closed",runProbe(mode)==nil) end
state.inVehicle=true;check("seated player refused",runProbe("clear")==nil)
state.inVehicle=false;state.speed=2;check("moving player refused",runProbe("clear")==nil)
print("vehicle access: "..passed.." passed, 0 failed")
