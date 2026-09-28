-- Host-adapter regression for the synchronous player Exchange (IDEA-247).
-- Exercises the real server module against deterministic platform/database doubles: invitation, exact revision
-- edits, active-Machine refusal, dual consent, construction of one heterogeneous SQL transaction, and cleanup
-- after the identity cache has already forgotten a disconnected player.
local root=arg[1] or "."
local modules={}
NcmCore={
    define=function(name,f) local m=f();modules[name]=m;return m end,
    get=function(name) return assert(modules[name],"missing core module "..tostring(name)) end,
}
dofile(root.."/ncm/core/economy/trade.lua")
modules["vocabulary.json"]={encode=function() return "{\"fixture\":true}" end}
local uuidN=0
modules["vocabulary.ids"]={uuid4=function() uuidN=uuidN+1;return ("00000000-0000-4000-8000-%012d"):format(uuidN) end}

local events,commands,streams,chats,txSeen={},{},{},{},nil
local clock=1000
local drivers={
    [1]={ncmDriverId="driver-a",display="A"},
    [2]={ncmDriverId="driver-b",display="B"},
}
local machines={m1={asset_id="m1",vehicle_key="quadra:type66",record="Vehicle.v_sport1_quadra_turbo",ncm_driver_id="driver-a"}}
local parts={
    pi={asset_id="pi",location_kind="installed",machine_asset_id="m1",ncm_driver_id="driver-a",code="TYRE.SPORT",family="tyres",display_manufacturer="GripWorks"},
    ps={asset_id="ps",location_kind="storage",machine_asset_id=nil,ncm_driver_id="driver-b",code="ECU.CLUB",family="engine_control",display_manufacturer="Circuitry"},
}

Open77={
    time={unix=function() return clock end},
    players={all=function() return {1,2} end,name=function(pid) return pid==1 and "A" or "B" end},
    chat={send=function(pid,msg) chats[#chats+1]={pid=pid,msg=msg} end},
}
NcmCalendar={serverId=function() return "test-world" end,resolveDriver=function(pid) return drivers[pid] end}
NcmEconomy={
    balanceOf=function() return 1000 end,
    withBalanceLocks=function(tx,driverIds)
        local out={}
        table.sort(driverIds)
        for _,id in ipairs(driverIds) do out[#out+1]={query="INSERT IGNORE INTO economy_balance_lock",values={"test-world",id}} end
        for _,id in ipairs(driverIds) do out[#out+1]={query="UPDATE economy_balance_lock",values={"test-world",id}} end
        for _,step in ipairs(tx) do out[#out+1]=step end
        return out
    end,
}
NcmRace={busySession=function() return false end}
NcmStream={send=function(pid,topic,payload) streams[pid]={topic=topic,payload=payload} end}
NcmComms={send=function() end}
NcmOwnership={invalidate=function() end}
NcmCollection={revealIdentity=function() end}
function AddEventHandler(name,fn) events[name]=fn end
function RegisterNetEvent(name,fn) events[name]=fn end
function RegisterCommand(name,fn) commands[name]=fn end
function TriggerClientEvent() end
function TriggerEvent(name,...) if events[name] then return events[name](...) end end
function CreateThread() end -- do not enter the production expiry loop in a deterministic harness.
function Wait() end

local function copy(row)
    if not row then return nil end
    local out={} for k,v in pairs(row) do out[k]=v end return out
end
MySQL={
    query={await=function(sql,values)
        if sql:find("machine_asset_id=%?") and sql:find("location_kind='installed'") then
            local out={} for _,p in pairs(parts) do if p.machine_asset_id==values[2] and p.location_kind=="installed" then out[#out+1]=copy(p) end end
            return out
        end
        if sql:find("FROM vehicle_asset WHERE") then
            local out={} for _,m in pairs(machines) do if m.ncm_driver_id==values[2] then out[#out+1]=copy(m) end end return out
        end
        if sql:find("FROM component_asset a JOIN component_design") then
            local out={} for _,p in pairs(parts) do if p.ncm_driver_id==values[2] and p.location_kind=="storage" then out[#out+1]=copy(p) end end return out
        end
        return {}
    end},
    single={await=function(sql,values)
        if sql:find("FROM vehicle_asset") then return copy(machines[values[2]]) end
        if sql:find("FROM component_asset") then return copy(parts[values[2]]) end
    end},
    scalar={await=function(sql)
        if sql:find("SELECT state FROM trade_envelope") then return "settled" end
        return 0
    end},
    transaction={await=function(tx) txSeen=tx;return true end},
}

dofile(root.."/ncm/online/resources/ncm_league/server/trade.lua")
local n=0
local function ok(value,label) n=n+1;assert(value,label);print("  PASS "..label) end

local invited,tradeId=NcmTrade.invite(1,2)
ok(invited and type(tradeId)=="string","one Driver can invite another online Driver")
ok(streams[2].payload.state=="invited" and streams[2].payload.role=="b","the recipient sees an explicit invitation")
ok(NcmTrade.respond(2,true),"the recipient can accept")
ok(streams[1].payload.state=="active" and streams[1].payload.revision==2,"acceptance opens one shared revision")

ok(NcmTrade.edit(1,{revision=2,machines={"m1"}}),"the owner can offer an exact Machine")
ok(NcmTrade.edit(2,{revision=3,money=500,components={"ps"}}),"the other side can combine cash and an exact stored Part")
ok(streams[1].payload.rows[1]~=nil,"the active Exchange projects inventory through the stream transport")

events["ncm:vehicle:materialized"]("m1",1)
local confirmed,why=NcmTrade.confirm(1,4)
ok(not confirmed and why=="store_machine_first:m1","an active Machine cannot move underneath the world representation")
events["ncm:vehicle:dematerialized"]("m1")
confirmed,why=NcmTrade.confirm(1,4)
ok(confirmed and why=="waiting","one confirmation waits and stays bound to the exact revision")
confirmed,why=NcmTrade.confirm(2,4)
ok(confirmed and why=="settled","the second matching confirmation settles the whole Exchange")
ok(type(txSeen)=="table" and #txSeen==20,"balance locks, asset locks, Machine, fitted Part, stored Part and cash share one SQL transaction")

local sql={};for i,step in ipairs(txSeen) do
    sql[#sql+1]=step.query
    for p=1,#step.values do assert(step.values[p]~=nil,"SQL parameter hole in step "..i) end
end
sql=table.concat(sql,"\n")
ok(sql:find("trade_envelope",1,true)~=nil and sql:find("trade_asset_leg",1,true)~=nil,"the durable envelope records every exact asset leg")
ok(sql:find("component_asset_transfer",1,true)~=nil and sql:find("vehicle_asset_transfer",1,true)~=nil,"ordinary provenance histories remain populated")
ok(sql:find("Exchange payment",1,true)~=nil and sql:find("Exchange receipt",1,true)~=nil,"cash is a paired debit and credit rather than a mint")
ok(sql:find("economy_balance_lock",1,true)~=nil,"concurrent NCM debits serialize before either balance predicate")
ok(streams[1].payload.state=="idle" and streams[2].payload.state=="idle","settlement releases both Drivers")

drivers[1]={ncmDriverId="driver-a",display="A"}
ok(NcmTrade.invite(1,2),"a later Exchange can open")
drivers[1]=nil -- model the calendar disconnect handler running before the Exchange handler.
events["onPlayerDisconnected"](1)
ok(streams[2].payload.state=="idle","disconnect cleanup does not depend on a stale identity-cache entry")

print(("trade host: %d assertion(s), 0 bad"):format(n))
