-- ncm_league / server / trade -- the player Exchange (IDEA-247).
--
-- Offers are synchronous and memory-only. Accepted revisions settle as one guarded SQL transaction: the
-- envelope row is inserted only when every ownership/custody/balance precondition is still true, and every
-- mutation is conditional on that guard row. A failed condition therefore moves nothing.
NcmTrade={}

local Trade=NcmCore.get("economy.trade")
local Json=NcmCore.get("vocabulary.json")
local ids=NcmCore.get("vocabulary.ids")
local unpack=table.unpack or unpack
local active,byPlayer,materialized={},{},{}
local hostRng=function() return math.random() end
local function now() return math.floor(Open77.time.unix()) end
local function sid() return NcmCalendar.serverId() end
local function log(fmt,...) print(("[ncm_league/trade] "..fmt):format(...)) end
local function driver(pid) return NcmCalendar.resolveDriver(tonumber(pid) or 0) end
local function tell(pid,msg) pcall(Open77.chat.send,tonumber(pid) or 0,"[NCM] "..tostring(msg)) end
local function name(pid,d)
    if d and type(d.display)=="string" and d.display~="" then return d.display end
    local ok,n=pcall(Open77.players.name,tonumber(pid) or 0)
    return ok and type(n)=="string" and n or ("Driver "..tostring(pid))
end
local function hasPlayer(pid)
    pid=tonumber(pid)
    if not pid then return false end
    local ok,all=pcall(Open77.players.all)
    if not ok then return false end
    for _,v in ipairs(all or {}) do if tonumber(v)==pid then return true end end
    return false
end
local function side(t,key) return key=="a" and t.a or t.b end
local function otherKey(key) return key=="a" and "b" or "a" end
local function keyFor(t,driverId)
    if driverId==t.aDriverId then return "a" end
    if driverId==t.bDriverId then return "b" end
end
local function pidFor(t,key) return key=="a" and t.aPid or t.bPid end
local function driverFor(t,key) return key=="a" and t.aDriverId or t.bDriverId end
local function tradeForPlayer(pid)
    pid=tonumber(pid) or 0
    for _,t in pairs(active) do
        if t.aPid==pid then return t,"a" end
        if t.bPid==pid then return t,"b" end
    end
end
local function sortedCopy(input)
    local out={} for _,v in ipairs(input or {}) do out[#out+1]=v end
    table.sort(out);return out
end

AddEventHandler("ncm:vehicle:materialized",function(assetId,runtimeId)
    if type(assetId)=="string" and assetId~="" then materialized[assetId]=runtimeId or true end
end)
AddEventHandler("ncm:vehicle:dematerialized",function(assetId)
    if type(assetId)=="string" then materialized[assetId]=nil end
end)

local function publicSide(s)
    return {money=tonumber(s.money) or 0,machines=sortedCopy(s.machines),components=sortedCopy(s.components)}
end

local function syncReservations(t)
    local wanted={}
    for _,key in ipairs({"a","b"}) do for _,assetId in ipairs(side(t,key).machines or {}) do wanted[assetId]=true end end
    for assetId in pairs(t.reserved or {}) do
        if not wanted[assetId] then TriggerEvent("ncm:trade:releaseMachine",assetId,t.id);t.reserved[assetId]=nil end
    end
    t.reserved=t.reserved or {}
    for assetId in pairs(wanted) do
        if not t.reserved[assetId] then t.reserved[assetId]=true;TriggerEvent("ncm:trade:reserveMachine",assetId,t.id) end
    end
end

local function releaseReservations(t)
    for assetId in pairs((t and t.reserved) or {}) do TriggerEvent("ncm:trade:releaseMachine",assetId,t.id) end
    if t then t.reserved={} end
end

local function consentKey(snapshot)
    local p={"v"..Trade.VERSION,"r"..tostring(snapshot.revision)}
    for _,key in ipairs({"a","b"}) do
        local s=snapshot[key]
        p[#p+1]=key..":"..tostring(s.driverId)..":"..tostring(s.money or 0)
        for _,v in ipairs(s.machines or {}) do p[#p+1]="m:"..v end
        for _,v in ipairs(s.components or {}) do
            p[#p+1]="p:"..v.assetId..":"..tostring(v.custody)..":"..tostring(v.machineAssetId or "")
        end
    end
    return table.concat(p,"|")
end

local function componentRows(machineId)
    return MySQL.query.await([[SELECT a.asset_id,a.location_kind,a.machine_asset_id,a.ncm_driver_id,
      d.code,d.family,d.display_manufacturer FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
      WHERE a.server_id=? AND a.machine_asset_id=? AND a.location_kind='installed' ORDER BY a.asset_id]],{sid(),machineId}) or {}
end

local function hydrateSide(t,key)
    local s=side(t,key);local from=driverFor(t,key);local to=driverFor(t,otherKey(key))
    local out={driverId=from,toDriverId=to,money=tonumber(s.money) or 0,machines={},components={},rows={}}
    for _,assetId in ipairs(s.machines or {}) do
        local r=MySQL.single.await([[SELECT asset_id,vehicle_key,record,ncm_driver_id FROM vehicle_asset
          WHERE server_id=? AND asset_id=?]],{sid(),assetId})
        if not r or r.ncm_driver_id~=from then return nil,"machine_not_owned:"..tostring(assetId) end
        if materialized[assetId] then return nil,"store_machine_first:"..tostring(assetId) end
        local cargo=tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM component_asset WHERE server_id=?
          AND machine_asset_id=? AND location_kind='trunk']],{sid(),assetId})) or 0
        if cargo>0 then return nil,"unload_trunk_before_trade:"..tostring(assetId) end
        local committed=tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM entry WHERE asset_id=? AND
          state IN ('checked_in','provisioned','gridded','racing','suspended','substituted')]],{assetId})) or 0
        if committed>0 then return nil,"machine_committed:"..tostring(assetId) end
        out.machines[#out.machines+1]=assetId
        local installed=componentRows(assetId)
        local bundle={}
        for _,p in ipairs(installed) do
            if p.ncm_driver_id~=from then return nil,"installed_part_owner_mismatch:"..tostring(p.asset_id) end
            local leg={assetId=p.asset_id,custody="installed",machineAssetId=assetId,code=p.code,family=p.family,manufacturer=p.display_manufacturer}
            out.components[#out.components+1]=leg;bundle[#bundle+1]=leg
        end
        out.rows[#out.rows+1]={kind="machine",assetId=assetId,vehicleKey=r.vehicle_key,record=r.record,installed=bundle}
    end
    for _,assetId in ipairs(s.components or {}) do
        local p=MySQL.single.await([[SELECT a.asset_id,a.location_kind,a.machine_asset_id,a.ncm_driver_id,
          d.code,d.family,d.display_manufacturer FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
          WHERE a.server_id=? AND a.asset_id=?]],{sid(),assetId})
        if not p or p.ncm_driver_id~=from then return nil,"component_not_owned:"..tostring(assetId) end
        if p.location_kind~="storage" or p.machine_asset_id~=nil then return nil,"component_not_stored:"..tostring(assetId) end
        local leg={assetId=assetId,custody="storage",code=p.code,family=p.family,manufacturer=p.display_manufacturer}
        out.components[#out.components+1]=leg;out.rows[#out.rows+1]={kind="component",assetId=assetId,code=p.code,family=p.family,manufacturer=p.display_manufacturer}
    end
    table.sort(out.machines)
    table.sort(out.components,function(a,b)return a.assetId<b.assetId end)
    return out
end

local function hydrate(t)
    local valid,why=Trade.offer(t);if not valid then return nil,why end
    if NcmRace and NcmRace.busySession then
        if NcmRace.busySession(t.aDriverId) then return nil,"party_in_session" end
        if NcmRace.busySession(t.bDriverId) then return nil,"party_in_session" end
    end
    local a;a,why=hydrateSide(t,"a");if not a then return nil,why end
    local b;b,why=hydrateSide(t,"b");if not b then return nil,why end
    if NcmEconomy.balanceOf(t.aDriverId)<a.money then return nil,"insufficient_funds:a" end
    if NcmEconomy.balanceOf(t.bDriverId)<b.money then return nil,"insufficient_funds:b" end
    local snap={revision=t.revision,a=a,b=b}
    snap.consentKey=consentKey(snap)
    return snap
end

local function inventoryRows(driverId,selected)
    local chosenM,chosenP={},{}
    for _,v in ipairs(selected.machines or {}) do chosenM[v]=true end
    for _,v in ipairs(selected.components or {}) do chosenP[v]=true end
    local rows={}
    for _,r in ipairs(MySQL.query.await([[SELECT asset_id,vehicle_key,record,production_ordinal,maker_ordinal,model_ordinal
      FROM vehicle_asset WHERE server_id=? AND ncm_driver_id=? ORDER BY acquired_at,asset_id]],{sid(),driverId}) or {}) do
        local installed=componentRows(r.asset_id)
        local bundle={}
        for _,p in ipairs(installed) do bundle[#bundle+1]={assetId=p.asset_id,code=p.code,family=p.family,manufacturer=p.display_manufacturer} end
        rows[#rows+1]={kind="inventory_machine",assetId=r.asset_id,vehicleKey=r.vehicle_key,record=r.record,
            globalOrdinal=tonumber(r.production_ordinal),makerOrdinal=tonumber(r.maker_ordinal),modelOrdinal=tonumber(r.model_ordinal),
            selected=chosenM[r.asset_id] or false,transferable=materialized[r.asset_id]==nil,
            refusal=materialized[r.asset_id] and "STORE THIS MACHINE BEFORE EXCHANGE" or nil,installed=bundle}
    end
    for _,p in ipairs(MySQL.query.await([[SELECT a.asset_id,a.design_id,a.global_ordinal,a.maker_ordinal,a.design_ordinal,
      d.code,d.family,d.display_manufacturer,d.subtitle FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
      WHERE a.server_id=? AND a.ncm_driver_id=? AND a.location_kind='storage' AND a.machine_asset_id IS NULL
      ORDER BY d.family,d.code,a.asset_id]],{sid(),driverId}) or {}) do
        rows[#rows+1]={kind="inventory_component",assetId=p.asset_id,designId=p.design_id,code=p.code,family=p.family,
            manufacturer=p.display_manufacturer,subtitle=p.subtitle,globalOrdinal=tonumber(p.global_ordinal),
            makerOrdinal=tonumber(p.maker_ordinal),designOrdinal=tonumber(p.design_ordinal),selected=chosenP[p.asset_id] or false}
    end
    return rows
end

local function peers(pid)
    local rows={};local ok,all=pcall(Open77.players.all);if not ok then return rows end
    for _,raw in ipairs(all or {}) do
        local other=tonumber(raw)
        if other and other~=pid then local d=driver(other);if d then rows[#rows+1]={kind="peer",playerId=other,driverId=d.ncmDriverId,display=name(other,d),busy=byPlayer[d.ncmDriverId]~=nil} end end
    end
    table.sort(rows,function(a,b)return tostring(a.display)<tostring(b.display) end);return rows
end

function NcmTrade.payload(pid)
    pid=tonumber(pid) or 0;local d=driver(pid);if not d then return nil,"no_driver" end
    local id=byPlayer[d.ncmDriverId];local t=id and active[id] or nil
    if not t then return {version=1,state="idle",balance=NcmEconomy.balanceOf(d.ncmDriverId),rows=peers(pid),serverNow=now()} end
    local key=keyFor(t,d.ncmDriverId);if not key then return nil,"not_party" end
    local mine,theirs=side(t,key),side(t,otherKey(key));local otherPid=pidFor(t,otherKey(key));local otherDriver=driver(otherPid)
    local rows=inventoryRows(d.ncmDriverId,mine)
    if t.state~="invited" or key=="a" then
        local hs=hydrateSide(t,otherKey(key))
        if hs then for _,r in ipairs(hs.rows) do r.kind="their_"..r.kind;rows[#rows+1]=r end end
    end
    return {version=1,state=t.state,tradeId=t.id,revision=t.revision,expiresAt=t.expiresAt,serverNow=now(),
        balance=NcmEconomy.balanceOf(d.ncmDriverId),role=key,other={playerId=otherPid,driverId=driverFor(t,otherKey(key)),display=name(otherPid,otherDriver)},
        mine={money=mine.money or 0,machines=mine.machines or {},components=mine.components or {},confirmed=t[key.."Confirmed"]==true},
        theirs={money=theirs.money or 0,machines=theirs.machines or {},components=theirs.components or {},confirmed=t[otherKey(key).."Confirmed"]==true},rows=rows}
end

function NcmTrade.push(pid,openPanel)
    local ok,p=pcall(NcmTrade.payload,pid);if not ok or not p then log("payload failed player=%s: %s",tostring(pid),tostring(p));return end
    NcmStream.send(pid,"ncm:trade",p,"rows")
    if openPanel then TriggerClientEvent("ncm:trade.open",pid) end
end
local function pushBoth(t)
    NcmTrade.push(t.aPid,false);NcmTrade.push(t.bPid,false)
end
local function clear(t,state,reason)
    if not t then return end
    t.state=state or "cancelled";t.reason=reason
    releaseReservations(t)
    byPlayer[t.aDriverId]=nil;byPlayer[t.bDriverId]=nil;active[t.id]=nil
    NcmTrade.push(t.aPid,false);NcmTrade.push(t.bPid,false)
end

function NcmTrade.invite(pid,targetPid)
    pid,targetPid=tonumber(pid) or 0,tonumber(targetPid) or 0
    local a,b=driver(pid),driver(targetPid)
    if not a or not b or not hasPlayer(targetPid) then return nil,"player_unavailable" end
    if pid==targetPid or a.ncmDriverId==b.ncmDriverId then return nil,"cannot_trade_self" end
    if byPlayer[a.ncmDriverId] or byPlayer[b.ncmDriverId] then return nil,"player_already_trading" end
    local t={id=ids.uuid4(hostRng),state="invited",aPid=pid,bPid=targetPid,aDriverId=a.ncmDriverId,bDriverId=b.ncmDriverId,
        a={money=0,machines={},components={}},b={money=0,machines={},components={}},revision=1,createdAt=now(),expiresAt=now()+600}
    active[t.id]=t;byPlayer[t.aDriverId]=t.id;byPlayer[t.bDriverId]=t.id
    pushBoth(t)
    NcmComms.send(targetPid,{id="trade.invite:"..t.id,category="transaction",priority="actionable",title="EXCHANGE INVITATION",
        message=name(pid,a).." wants to open an Exchange. F6 → EXCHANGE to review.",reference="trade",surface="toast",repeatPolicy={mode="once"},durationMs=10000})
    tell(pid,"Exchange invitation sent to "..name(targetPid,b)..".")
    return true,t.id
end

function NcmTrade.respond(pid,accept)
    local d=driver(pid);local t=d and active[byPlayer[d.ncmDriverId] or ""] or nil
    if not t or t.bDriverId~=d.ncmDriverId or t.state~="invited" then return nil,"no_invitation" end
    if not accept then clear(t,"declined","declined");tell(t.aPid,name(pid,d).." declined the Exchange.");return true end
    t.state="active";t.revision=t.revision+1;pushBoth(t);tell(t.aPid,name(pid,d).." joined the Exchange.");return true
end

function NcmTrade.edit(pid,edit)
    local d=driver(pid);local t=d and active[byPlayer[d.ncmDriverId] or ""] or nil
    if not t or t.state~="active" then return nil,"no_active_trade" end
    if tonumber(edit and edit.revision)~=t.revision then return nil,"stale_revision" end
    local key=keyFor(t,d.ncmDriverId);local normalized,why=Trade.side(edit);if not normalized then return nil,why end
    if normalized.money>0 and (tonumber(side(t,otherKey(key)).money) or 0)>0 then return nil,"cash_on_both_sides" end
    t[key]=normalized;syncReservations(t);t.revision=t.revision+1;t.aConfirmed=false;t.bConfirmed=false;t.aConsentKey=nil;t.bConsentKey=nil
    pushBoth(t);return true
end

local function addGuard(clauses,values,sql,...)
    clauses[#clauses+1]=sql;for _,v in ipairs({...}) do values[#values+1]=v end
end
local function placeholders(n)local p={} for i=1,n do p[i]="?" end return table.concat(p,",") end

local function settle(t,snap)
    local clauses,guardValues={"? <> ?"},{t.aDriverId,t.bDriverId}
    for _,key in ipairs({"a","b"}) do
        local s=snap[key]
        if #s.machines>0 then
            local q={sid(),s.driverId};for _,v in ipairs(s.machines) do q[#q+1]=v end;q[#q+1]=#s.machines
            addGuard(clauses,guardValues,"(SELECT COUNT(*) FROM vehicle_asset WHERE server_id=? AND ncm_driver_id=? AND asset_id IN ("..placeholders(#s.machines).."))=?",unpack(q))
            for _,machineId in ipairs(s.machines) do
                addGuard(clauses,guardValues,"NOT EXISTS(SELECT 1 FROM entry WHERE asset_id=? AND state IN ('checked_in','provisioned','gridded','racing','suspended','substituted'))",machineId)
                local installed=0 for _,p in ipairs(s.components) do if p.machineAssetId==machineId then installed=installed+1 end end
                addGuard(clauses,guardValues,"(SELECT COUNT(*) FROM component_asset WHERE server_id=? AND machine_asset_id=? AND location_kind='installed')=?",sid(),machineId,installed)
            end
        end
        local allParts={} for _,p in ipairs(s.components) do allParts[#allParts+1]=p.assetId end
        if #allParts>0 then
            local q={sid(),s.driverId};for _,v in ipairs(allParts) do q[#q+1]=v end;q[#q+1]=#allParts
            addGuard(clauses,guardValues,"(SELECT COUNT(*) FROM component_asset WHERE server_id=? AND ncm_driver_id=? AND asset_id IN ("..placeholders(#allParts).."))=?",unpack(q))
            for _,p in ipairs(s.components) do
                if p.custody=="installed" then
                    addGuard(clauses,guardValues,"EXISTS(SELECT 1 FROM component_asset WHERE server_id=? AND asset_id=? AND ncm_driver_id=? AND location_kind='installed' AND machine_asset_id=?)",sid(),p.assetId,s.driverId,p.machineAssetId)
                else
                    addGuard(clauses,guardValues,"EXISTS(SELECT 1 FROM component_asset WHERE server_id=? AND asset_id=? AND ncm_driver_id=? AND location_kind='storage' AND machine_asset_id IS NULL)",sid(),p.assetId,s.driverId)
                end
            end
        end
        if s.money>0 then addGuard(clauses,guardValues,"(SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?)>=?",s.driverId,sid(),s.money) end
    end
    local offerJson=Json.encode({version=Trade.VERSION,revision=t.revision,a=snap.a,b=snap.b,consentKey=snap.consentKey})
    -- Lock the exact asset rows before evaluating the envelope predicate. This closes the last TOCTOU gap with
    -- fitting/service/title mutations under database isolation levels where INSERT..SELECT is a consistent read.
    local machineIds,partIds={},{}
    for _,key in ipairs({"a","b"}) do
        for _,assetId in ipairs(snap[key].machines) do machineIds[#machineIds+1]=assetId end
        for _,p in ipairs(snap[key].components) do partIds[#partIds+1]=p.assetId end
    end
    table.sort(machineIds);table.sort(partIds)
    local tx={}
    if #machineIds>0 then
        local values={} for _,assetId in ipairs(machineIds) do values[#values+1]=assetId end
        tx[#tx+1]={query="UPDATE vehicle_asset SET asset_id=asset_id WHERE asset_id IN ("..placeholders(#machineIds)..")",values=values}
    end
    if #partIds>0 then
        local values={} for _,assetId in ipairs(partIds) do values[#values+1]=assetId end
        tx[#tx+1]={query="UPDATE component_asset SET asset_id=asset_id WHERE asset_id IN ("..placeholders(#partIds)..")",values=values}
    end
    tx[#tx+1]={query=[[INSERT IGNORE INTO trade_envelope
      (trade_id,server_id,request_key,party_a_driver_id,party_b_driver_id,revision,state,offer_json,created_at,expires_at)
      SELECT ?,?,?,?,?,?,'settling',?,?,? WHERE ]]..table.concat(clauses," AND "),
      values={t.id,sid(),"trade:"..t.id,t.aDriverId,t.bDriverId,t.revision,offerJson,t.createdAt,t.expiresAt,unpack(guardValues)}}

    local function guarded() return "EXISTS(SELECT 1 FROM trade_envelope WHERE trade_id=? AND state='settling')" end
    for _,key in ipairs({"a","b"}) do local s=snap[key]
        for _,assetId in ipairs(s.machines) do
            tx[#tx+1]={query="INSERT IGNORE INTO trade_asset_leg (trade_id,asset_kind,asset_id,from_driver_id,to_driver_id,custody_kind) SELECT ?, 'machine', ?, ?, ?, 'title' WHERE "..guarded(),values={t.id,assetId,s.driverId,s.toDriverId,t.id}}
            tx[#tx+1]={query="UPDATE vehicle_asset SET ncm_driver_id=?,owner_principal_kind='driver',owner_principal_id=?,acquired_via='trade',granted_by=NULL,acquired_at=? WHERE asset_id=? AND ncm_driver_id=? AND "..guarded(),values={s.toDriverId,s.toDriverId,now(),assetId,s.driverId,t.id}}
            tx[#tx+1]={query=[[INSERT IGNORE INTO vehicle_asset_transfer
              (transfer_id,idem_key,server_id,asset_id,from_driver_id,to_driver_id,kind,amount,occurred_at,trade_id)
              SELECT ?,?,?,?,?,?,'player_trade',NULL,?,? FROM trade_envelope WHERE trade_id=? AND state='settling']],values={ids.uuid4(hostRng),"trade:"..t.id..":machine:"..assetId,sid(),assetId,s.driverId,s.toDriverId,now(),t.id,t.id}}
        end
        for _,p in ipairs(s.components) do
            tx[#tx+1]={query="INSERT IGNORE INTO trade_asset_leg (trade_id,asset_kind,asset_id,from_driver_id,to_driver_id,custody_kind,machine_asset_id) SELECT ?, 'component', ?, ?, ?, ?, NULLIF(?,'') WHERE "..guarded(),values={t.id,p.assetId,s.driverId,s.toDriverId,p.custody,p.machineAssetId or "",t.id}}
            tx[#tx+1]={query="UPDATE component_asset SET ncm_driver_id=?,acquired_via='trade',acquired_at=? WHERE asset_id=? AND ncm_driver_id=? AND "..guarded(),values={s.toDriverId,now(),p.assetId,s.driverId,t.id}}
            tx[#tx+1]={query=[[INSERT IGNORE INTO component_asset_transfer
              (transfer_id,idem_key,server_id,asset_id,from_driver_id,to_driver_id,kind,amount,occurred_at,trade_id)
              SELECT ?,?,?,?,?,?,'player_trade',NULL,?,? FROM trade_envelope WHERE trade_id=? AND state='settling']],values={ids.uuid4(hostRng),"trade:"..t.id..":component:"..p.assetId,sid(),p.assetId,s.driverId,s.toDriverId,now(),t.id,t.id}}
        end
    end
    local payer,payee,amount
    if snap.a.money>0 then payer,payee,amount=snap.a.driverId,snap.a.toDriverId,snap.a.money
    elseif snap.b.money>0 then payer,payee,amount=snap.b.driverId,snap.b.toDriverId,snap.b.money end
    if amount and amount>0 then
        tx[#tx+1]={query="INSERT IGNORE INTO trade_money_leg (trade_id,from_driver_id,to_driver_id,amount,currency) SELECT ?,?,?,?,'eddies' WHERE "..guarded(),values={t.id,payer,payee,amount,t.id}}
        tx[#tx+1]={query=[[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,owner_principal_kind,owner_principal_id,trade_id)
          SELECT ?,?,'player_trade',?,'eddies',?,'Exchange payment',?,'driver',?,? FROM trade_envelope WHERE trade_id=? AND state='settling']],values={payer,sid(),-amount,t.id,"trade:"..t.id..":debit",payer,t.id,t.id}}
        tx[#tx+1]={query=[[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,owner_principal_kind,owner_principal_id,trade_id)
          SELECT ?,?,'player_trade',?,'eddies',?,'Exchange receipt',?,'driver',?,? FROM trade_envelope WHERE trade_id=? AND state='settling']],values={payee,sid(),amount,t.id,"trade:"..t.id..":credit",payee,t.id,t.id}}
    end
    tx[#tx+1]={query="UPDATE trade_envelope SET state='settled',settled_at=? WHERE trade_id=? AND state='settling'",values={now(),t.id}}
    tx=NcmEconomy.withBalanceLocks(tx,{t.aDriverId,t.bDriverId})
    local ok,why=MySQL.transaction.await(tx);if not ok then return nil,"transaction:"..tostring(why) end
    local state=MySQL.scalar.await("SELECT state FROM trade_envelope WHERE trade_id=?",{t.id})
    if state~="settled" then return nil,"precondition_changed" end
    return true
end

function NcmTrade.confirm(pid,revision)
    local d=driver(pid);local t=d and active[byPlayer[d.ncmDriverId] or ""] or nil
    if not t or t.state~="active" then return nil,"no_active_trade" end
    if tonumber(revision)~=t.revision then return nil,"stale_revision" end
    local snap,why=hydrate(t);if not snap then return nil,why end
    local key=keyFor(t,d.ncmDriverId);local other=otherKey(key)
    if t[other.."Confirmed"] and t[other.."ConsentKey"]~=snap.consentKey then
        t.revision=t.revision+1;t.aConfirmed=false;t.bConfirmed=false;t.aConsentKey=nil;t.bConsentKey=nil;pushBoth(t)
        return nil,"offer_changed_reconfirm"
    end
    t[key.."Confirmed"]=true;t[key.."ConfirmedRevision"]=t.revision;t[key.."ConsentKey"]=snap.consentKey
    if not (t.aConfirmed and t.bConfirmed) then pushBoth(t);return true,"waiting" end
    local ready
    ready,why=Trade.canSettle(t,now());if not ready then return nil,why end
    local fresh;fresh,why=hydrate(t);if not fresh or fresh.consentKey~=t.aConsentKey or fresh.consentKey~=t.bConsentKey then
        t.revision=t.revision+1;t.aConfirmed=false;t.bConfirmed=false;t.aConsentKey=nil;t.bConsentKey=nil;pushBoth(t)
        return nil,why or "offer_changed_reconfirm"
    end
    t.state="settling";local ok;ok,why=settle(t,fresh)
    if not ok then t.state="active";t.aConfirmed=false;t.bConfirmed=false;pushBoth(t);return nil,why end
    if NcmOwnership and NcmOwnership.invalidate then NcmOwnership.invalidate(t.aDriverId);NcmOwnership.invalidate(t.bDriverId) end
    for _,key2 in ipairs({"a","b"}) do for _,r in ipairs(fresh[key2].rows) do if r.kind=="machine" and NcmCollection then
        pcall(NcmCollection.revealIdentity,pidFor(t,otherKey(key2)),r.vehicleKey,{source="ownership",assetId=r.assetId,basis="server_measured"})
    end end end
    local aPid,bPid=t.aPid,t.bPid;clear(t,"settled","settled")
    for _,p in ipairs({aPid,bPid}) do NcmComms.send(p,{id="trade.settled:"..t.id,category="transaction",priority="actionable",title="EXCHANGE COMPLETE",
        message="Every asset and payment moved together. The receipt is recorded under "..t.id:sub(1,8)..".",reference="trade",surface="toast",repeatPolicy={mode="once"},durationMs=9000}) end
    return true,"settled"
end

function NcmTrade.cancel(pid,reason)
    local d=driver(pid);local t=d and active[byPlayer[d.ncmDriverId] or ""] or nil;if not t then return nil,"no_trade" end
    local other=pidFor(t,otherKey(keyFor(t,d.ncmDriverId)));clear(t,"cancelled",reason or "cancelled");tell(other,"The Exchange was cancelled.");return true
end

local function answer(pid,ok,why)
    TriggerClientEvent("ncm:trade.result",pid,{ok=ok==true,reason=ok and nil or tostring(why),state=ok and tostring(why or "ok") or "refused"})
    if not ok then tell(pid,"Exchange refused: "..tostring(why)) end
end
RegisterNetEvent("ncm:trade.request",function() NcmTrade.push(tonumber(source) or 0,false) end)
RegisterNetEvent("ncm:trade.invite",function(target) local pid=tonumber(source) or 0;CreateThread(function()answer(pid,NcmTrade.invite(pid,target))end) end)
RegisterNetEvent("ncm:trade.respond",function(accept)local pid=tonumber(source) or 0;CreateThread(function()answer(pid,NcmTrade.respond(pid,accept==true))end)end)
RegisterNetEvent("ncm:trade.edit",function(edit)local pid=tonumber(source) or 0;CreateThread(function()answer(pid,NcmTrade.edit(pid,type(edit)=="table" and edit or {}))end)end)
RegisterNetEvent("ncm:trade.confirm",function(revision)local pid=tonumber(source) or 0;CreateThread(function()answer(pid,NcmTrade.confirm(pid,revision))end)end)
RegisterNetEvent("ncm:trade.cancel",function()local pid=tonumber(source) or 0;answer(pid,NcmTrade.cancel(pid,"player"))end)

RegisterCommand("ncm.exchange",function(source,args)
    local pid=tonumber(source) or 0;if pid<=0 then return end
    local target=tonumber(args and args[1]);if target then CreateThread(function()answer(pid,NcmTrade.invite(pid,target))end) else NcmTrade.push(pid,true) end
end,false)
RegisterCommand("ncm.trade",function(source,args)
    local pid=tonumber(source) or 0;if pid<=0 then return end
    local target=tonumber(args and args[1]);if target then CreateThread(function()answer(pid,NcmTrade.invite(pid,target))end) else NcmTrade.push(pid,true) end
end,false)
RegisterCommand("ncm.trade.accept",function(source)local pid=tonumber(source) or 0;CreateThread(function()answer(pid,NcmTrade.respond(pid,true))end)end,false)
RegisterCommand("ncm.trade.decline",function(source)local pid=tonumber(source) or 0;CreateThread(function()answer(pid,NcmTrade.respond(pid,false))end)end,false)
RegisterCommand("ncm.trade.confirm",function(source)
    local pid=tonumber(source) or 0;local d=driver(pid);local t=d and active[byPlayer[d.ncmDriverId] or ""] or nil
    if t then CreateThread(function()answer(pid,NcmTrade.confirm(pid,t.revision))end) else answer(pid,nil,"no_trade") end
end,false)
RegisterCommand("ncm.trade.cancel",function(source)answer(tonumber(source) or 0,NcmTrade.cancel(tonumber(source) or 0,"player"))end,false)

AddEventHandler("onPlayerDisconnected",function(playerId)
    -- The calendar may already have dropped its player-to-Driver cache by the time this handler runs,
    -- so disconnect cleanup uses the server-id snapshot held by the envelope rather than re-resolving.
    local pid=tonumber(playerId) or tonumber(source) or 0;local t,key=tradeForPlayer(pid)
    if t then local other=pidFor(t,otherKey(key));clear(t,"cancelled","disconnect");tell(other,"Exchange cancelled: the other Driver disconnected.") end
end)
AddEventHandler("ncm:trade:requestReservationSnapshot",function()
    for _,t in pairs(active) do syncReservations(t) end
end)
AddEventHandler("onResourceStop",function(resourceName)
    if resourceName==GetCurrentResourceName() then for _,t in pairs(active) do releaseReservations(t) end end
end)
CreateThread(function()
    Wait(0);TriggerEvent("ncm:trade:requestActiveSnapshot")
    while true do Wait(10000);local tnow=now();local expired={} for _,t in pairs(active) do if tnow>=t.expiresAt then expired[#expired+1]=t end end for _,t in ipairs(expired) do clear(t,"expired","expired");tell(t.aPid,"Exchange expired.");tell(t.bPid,"Exchange expired.") end end
end)

log("player Exchange ready (synchronous, atomic heterogeneous barter)")
