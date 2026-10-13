-- NCM Parts economy: immutable Designs, serialized assets, primary stock, inventory and manufacturer R&D.
NcmComponents={}
local Cat=NcmCore.get("parts.catalogue")
local VehicleCatalogue=NcmCore.get("data.vehicle_catalogue")
local Rnd=NcmCore.get("parts.rnd")
local Handling=NcmCore.get("parts.handling")
local Wear=NcmCore.get("parts.wear")
local Markets=NcmCore.get("economy.markets")
local Json=NcmCore.get("vocabulary.json")
local Install=NcmCore.get("engineering.installation")   -- add-ons (a propulsor on a mount) fit by mount + facing
local ids=NcmCore.get("vocabulary.ids")
local hostRng=function() return math.random() end
local function now() return math.floor(Open77.time.unix()) end
local function serverId() return NcmCalendar.serverId() end
local function log(fmt,...) print(("[ncm_league/components] "..fmt):format(...)) end
-- **Read, never declare.** `Open77.tunables.declare` is per-RESOURCE and a second call REPLACES the first
-- rather than merging with it (`calendar.lua` has said so since 2026-09-20). Declaring here wiped the
-- calendar's `serverId` and `environment` the moment this file loaded after it, and `serverId` is the key
-- every canonical row in the persistent world is stored under. The parts tunables are declared alongside
-- every other one in `calendar.lua`; this reads them from there.
--
-- `partsEnabled` stays live-tunable, which was the original intent: an emergency park for the economy
-- without a restart.
local settings=setmetatable({},{__index=function(_,k)
    local s=NcmCalendar and NcmCalendar.settings
    return s and s[k] or nil
end})
local function enabled() return settings.partsEnabled==true end
NcmComponents.enabled=enabled
local function enc(v) local ok,s=pcall(Json.encode,v); return ok and s or "[]" end
local function dec(v) if type(v)=="table" then return v end local ok,x=pcall(Json.decode,tostring(v or "")); return ok and x or nil end
local function driver(pid) return NcmCalendar.resolveDriver(tonumber(pid) or 0) end
-- h*16777619 is split (0x01000193 = 256*65536 + 403) so every intermediate stays below 2^42: exact in Lua 5.4 integers
-- AND in LuaJIT doubles, so a design id is the same on OPEN//77 and in the single-player host (KB-380, L338)
local function hash(s) local h=2166136261 for i=1,#s do h=(h*403+(h*256%65536)*65536+s:byte(i))%4294967296 end return h end
local function stableId(s) return ids.uuid4(ids.seededRng(hash(s))) end

local function seedDesign(d,t)
    if d.origin=="rnd_physical" then
        MySQL.insert.await([[INSERT IGNORE INTO component_design
          (design_id,lineage_id,revision,manufacturer_key,display_manufacturer,code,subtitle,family,tier,effect,
           price,fidelity,distribution,origin_kind,positions_json,fitment_json,spec_json,created_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],
          {d.designId,d.lineageId,d.revision,d.makerKey,d.manufacturer,d.code,d.subtitle,d.family,d.tier,1,
           d.price,"physical",Markets.homeFor(d)==Markets.BASE_ID and "base" or "autofixer","rnd_physical","[]",enc({standard=d.interface}),enc(d),t})
        return
    end
    MySQL.insert.await([[INSERT IGNORE INTO component_design
      (design_id,lineage_id,revision,manufacturer_key,display_manufacturer,code,subtitle,family,tier,effect,
       price,fidelity,distribution,origin_kind,positions_json,fitment_json,created_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],
      {d.designId,d.lineageId,d.revision,d.makerKey,d.manufacturer or d.makerKey,d.code,d.subtitle,d.family,d.tier,
       d.effect,d.price,d.fidelity,d.distribution,d.origin,enc(d.positions),enc(d.supportedVehicles),t})
end

local function ensureSupply(d,t)
    local s=Cat.SUPPLY[d.tier]; if not s or (d.distribution~="base" and d.distribution~="autofixer") then return end
    local marketId=d.marketId or Markets.BASE_ID
    MySQL.insert.await([[INSERT IGNORE INTO component_supply_state
      (server_id,market_id,design_id,next_tick_index,next_tick_at,batch,interval_sec,initial_done,updated_at)
      VALUES (?,?,?,0,?,?,?,0,?)]],{serverId(),marketId,d.designId,t,s.batch,s.cadenceSec,t})
end

--- Owner, 2026-10-10: "space is a secret in nature yes that does not mean inaccessible ... distribute the space kind of
--- parts around the different autofixer enabled markets, not in base market ... keep slipstream in base market."
--- Every flight-hardware design stocked in the Base Market moves -- its production schedule and its unsold units -- to
--- its line's Autofixer (core `economy.markets.homeFor`). Sold and installed units are untouched. Idempotent.
function NcmComponents.disperseFlightHardware(t)
    local moved,units=0,0
    for _,r in ipairs(MySQL.query.await([[SELECT d.design_id,d.lineage_id,d.code,d.family FROM component_design d
      JOIN component_supply_state s ON s.design_id=d.design_id
      WHERE s.server_id=? AND s.market_id=?]],{serverId(),Markets.BASE_ID}) or {}) do
        local home=Markets.homeFor({family=r.family,lineageId=r.lineage_id,code=r.code})
        if home~=Markets.BASE_ID then
            MySQL.insert.await([[INSERT IGNORE INTO component_supply_state
              (server_id,market_id,design_id,next_tick_index,next_tick_at,batch,interval_sec,initial_done,updated_at)
              SELECT server_id,?,design_id,next_tick_index,next_tick_at,batch,interval_sec,initial_done,? FROM component_supply_state
              WHERE server_id=? AND market_id=? AND design_id=?]],{home,t,serverId(),Markets.BASE_ID,r.design_id})
            MySQL.update.await("DELETE FROM component_supply_state WHERE server_id=? AND market_id=? AND design_id=?",
              {serverId(),Markets.BASE_ID,r.design_id})
            local n=MySQL.update.await([[UPDATE component_market_inventory mi JOIN component_asset a ON a.asset_id=mi.asset_id
              SET mi.market_id=? WHERE mi.market_id=? AND mi.state='available' AND a.server_id=? AND a.design_id=?]],
              {home,Markets.BASE_ID,serverId(),r.design_id})
            MySQL.update.await("UPDATE component_design SET distribution='autofixer' WHERE design_id=?",{r.design_id})
            moved=moved+1; units=units+(tonumber(n) or 0)
            log("flight hardware %s (%s) now sold at %s; %s unsold unit(s) moved",tostring(r.code),tostring(r.family),home,tostring(n or 0))
        end
    end
    if moved>0 then log("dispersed %d flight-hardware design(s) out of the Base Market (%d unit(s))",moved,units) end
    return moved,units
end

function NcmComponents.seed()
    local t=now()
    pcall(function() GlobalState.ncmPartsEnabled=enabled() end)
    for _,d in ipairs(Cat.designs()) do seedDesign(d,t); ensureSupply(d,t) end
    for _,entry in ipairs(VehicleCatalogue.entries()) do
        for _,family in ipairs(Cat.FAMILIES) do seedDesign(Cat.factoryDesign(entry.vehicleKey,family),t) end
    end
    local release=math.floor(tonumber(settings.partsReleaseEpoch) or 0); if release<=0 then release=t end
    -- Physical research begins when this build first boots for the continuity, not at the older scalar launch epoch.
    local physicalRelease=t
    for makerKey,m in pairs(Rnd.MAKERS) do
        MySQL.insert.await([[INSERT IGNORE INTO component_rnd_state
          (server_id,maker_key,release_epoch,next_run_index,next_run_at,logic_version,updated_at)
          VALUES (?,?,?,0,?,?,?)]],{serverId(),makerKey,release,release+m.offsetSec,Rnd.logicVersion,t})
    end
    for programmeKey,m in pairs(Rnd.PHYSICAL) do
        MySQL.insert.await([[INSERT IGNORE INTO component_rnd_state
          (server_id,maker_key,release_epoch,next_run_index,next_run_at,logic_version,updated_at)
          VALUES (?,?,?,0,?,2,?)]],{serverId(),programmeKey,physicalRelease,physicalRelease+m.offsetSec,t})
        MySQL.insert.await([[INSERT IGNORE INTO component_rnd_competency
          (server_id,programme_key,design_score,updated_at) VALUES (?,?,0,?)]],{serverId(),programmeKey,t})
    end
    for _,row in ipairs(MySQL.query.await("SELECT spec_json FROM component_design WHERE origin_kind IN ('rnd_physical','prototype','player_design') AND spec_json IS NOT NULL") or {}) do
        local spec=dec(row.spec_json)
        if spec then Install.register(spec) end
    end
    -- L356: physical add-ons a maker SELLS (`sale` on the design, e.g. the Eddywright SL-1) are ordinary market stock:
    -- a Base Market listing with serialized supply like any part. ncm_world seeds every engineering design as
    -- 'engineering' (not sold); a design with `sale` is upgraded here to its market distribution.
    for _,d in ipairs(Install.DESIGNS) do
        if type(d.sale)=="table" then
            local tier=d.sale.tier or "sport"
            MySQL.insert.await([[INSERT IGNORE INTO component_design
              (design_id,lineage_id,revision,manufacturer_key,display_manufacturer,code,subtitle,family,tier,effect,
               price,fidelity,distribution,origin_kind,positions_json,fitment_json,spec_json,created_at)
              VALUES (?,?,?,?,?,?,?,?,?,1,?,'physical','base','design','[]',?,?,?)]],
              {d.designId,d.lineageId,d.revision,d.makerKey,d.manufacturer,d.code,d.subtitle,d.family,tier,d.price,
               enc({standard=d.interface}),enc(d),t})
            MySQL.update.await("UPDATE component_design SET distribution='base',tier=?,price=?,spec_json=? WHERE design_id=?",
              {tier,d.price,enc(d),d.designId})
            ensureSupply({designId=d.designId,tier=tier,distribution="base",marketId=d.sale.market~="base" and d.sale.market or nil},t)
        end
    end
    NcmComponents.disperseFlightHardware(t)
    local n,why=NcmComponents.ensureFactoryAll()
    log("seeded %d launch Designs; factory configurations=%s; enabled=%s%s",#Cat.designs(),tostring(n),tostring(enabled()),why and (" ("..why..")") or "")
    return true
end

function NcmComponents.factoryStatements(machineAssetId,vehicleKey,ownerId,createdAt,exposureM)
    if not VehicleCatalogue.byKey(vehicleKey) then return nil,"unsupported_machine" end
    local t=createdAt or now(); local configId=stableId("factory-config:"..serverId()..":"..machineAssetId); local tx={
      {query=[[INSERT IGNORE INTO machine_configuration
        (configuration_id,machine_asset_id,revision,created_at,created_by_driver_id) VALUES (?,?,1,?,NULLIF(?,''))]],values={configId,machineAssetId,t,ownerId or ""}},
    }
    for _,family in ipairs(Cat.FAMILIES) do
        local d=Cat.factoryDesign(vehicleKey,family); local aid=stableId("factory-part:"..serverId()..":"..machineAssetId..":"..family)
        tx[#tx+1]={query=[[INSERT IGNORE INTO component_asset
          (asset_id,server_id,design_id,ncm_driver_id,manufacturer_key,location_kind,machine_asset_id,factory_original,acquired_via,acquired_at,exposure_m,created_at)
          VALUES (?,?,?,NULLIF(?,''),?,'installed',?,1,'factory',?,?,?)]],values={aid,serverId(),d.designId,ownerId or "","factory",machineAssetId,t,math.max(0,math.floor(tonumber(exposureM) or 0)),t}}
        for _,interfaceId in ipairs(d.positions) do tx[#tx+1]={query=[[INSERT IGNORE INTO machine_configuration_item
          (configuration_id,interface_id,component_asset_id) VALUES (?,?,?)]],values={configId,interfaceId,aid}} end
    end
    tx[#tx+1]={query="INSERT IGNORE INTO machine_configuration_current (machine_asset_id,configuration_id) VALUES (?,?)",values={machineAssetId,configId}}
    return tx
end

-- The head of a Machine's configuration chain, or nil if it has none yet.
--
-- `machine_configuration` is append-only and `machine_configuration_current` is the single row that says
-- which revision a Machine is running. Every caller that wanted this re-issued the SELECT inline, so the
-- one question "what is this Machine configured as right now" had three spellings and no name.
--
-- It exists chiefly for `configuration_ref`, reserved unwritten on `session_result` (migration 024) and
-- `vehicle_knowledge_evidence` (migration 028) because `31_CAPABILITY_AUDIT.md` section 6 proved there was
-- no engine object to point at. Migration 031 built the NCM-authored record that section predicted; this is
-- how the rest of the codebase reaches it.
--
-- **nil is a real answer** -- an unsupported Machine has no factory configuration -- and every caller must
-- write NULL rather than substituting anything.
function NcmComponents.currentConfiguration(machineAssetId)
    if type(machineAssetId)~="string" or machineAssetId=="" then return nil end
    return MySQL.scalar.await("SELECT configuration_id FROM machine_configuration_current WHERE machine_asset_id=?",{machineAssetId})
end

function NcmComponents.ensureMachine(machineAssetId,vehicleKey,ownerId,exposureM)
    if MySQL.scalar.await("SELECT configuration_id FROM machine_configuration_current WHERE machine_asset_id=?",{machineAssetId}) then return false,"already_configured" end
    if exposureM==nil then exposureM=MySQL.scalar.await("SELECT odometer_m FROM vehicle_asset WHERE asset_id=?",{machineAssetId}) end
    local tx,buildWhy=NcmComponents.factoryStatements(machineAssetId,vehicleKey,ownerId,now(),exposureM)
    if not tx then return nil,buildWhy end
    local ok,why=MySQL.transaction.await(tx); if not ok then return nil,"factory_transaction:"..tostring(why) end
    return true
end

function NcmComponents.ensureFactoryAll()
    local rows=MySQL.query.await([[SELECT asset_id,vehicle_key,ncm_driver_id,odometer_m FROM vehicle_asset
      WHERE server_id=?]],{serverId()}) or {}
    local n=0 for _,r in ipairs(rows) do local made=NcmComponents.ensureMachine(r.asset_id,r.vehicle_key,r.ncm_driver_id,r.odometer_m); if made then n=n+1 end end
    return n
end

local function reserve(scope,key,n)
    n=math.max(1,math.floor(tonumber(n) or 1)); local sid=serverId()
    for _=1,8 do
        MySQL.insert.await([[INSERT IGNORE INTO component_sequence
          (server_id,scope,scope_key,next_value,updated_at) VALUES (?,?,?,1,?)]],{sid,scope,key,now()})
        local cur=tonumber(MySQL.scalar.await("SELECT next_value FROM component_sequence WHERE server_id=? AND scope=? AND scope_key=?",{sid,scope,key}))
        if not cur then return nil,"missing_sequence" end
        local nonce=ids.uuid4(hostRng)
        MySQL.update.await([[UPDATE component_sequence SET next_value=next_value+?,holder=?,updated_at=?
          WHERE server_id=? AND scope=? AND scope_key=? AND next_value=?]],{n,nonce,now(),sid,scope,key,cur})
        local held=MySQL.scalar.await("SELECT holder FROM component_sequence WHERE server_id=? AND scope=? AND scope_key=?",{sid,scope,key})
        if held==nonce then return cur end
    end
    return nil,"sequence_contended"
end

local function allocate(d,n)
    local g,w1=reserve("global","",n); if not g then return nil,w1 end
    local m,w2=reserve("maker",d.makerKey,n); if not m then return nil,w2 end
    local x,w3=reserve("design",d.designId,n); if not x then return nil,w3 end
    local out={} for i=0,n-1 do out[#out+1]={global=g+i,maker=m+i,design=x+i} end return out
end

-- How many unsold units of this Design one market is holding. On the READ path -- this is the
-- "AVAILABLE n / ceiling" the player is shown -- so it takes the market rather than naming one.
local function available(designId,marketId)
    return tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM component_market_inventory mi
      JOIN component_asset a ON a.asset_id=mi.asset_id
      WHERE mi.market_id=? AND mi.state='available' AND a.server_id=? AND a.design_id=?
        AND a.ncm_driver_id IS NULL]],{marketId or Markets.BASE_ID,serverId(),designId})) or 0
end

local function designFromRow(r)
    local spec=dec(r.spec_json)
    if (r.origin_kind=="rnd_physical" or r.origin_kind=="prototype" or r.origin_kind=="player_design") and spec then
        local d=Install.design(r.design_id) or Install.register(spec)
        if d then return d end
    end
    return {designId=r.design_id,lineageId=r.lineage_id,revision=tonumber(r.revision),makerKey=r.manufacturer_key,
      manufacturer=r.display_manufacturer,code=r.code,subtitle=r.subtitle,family=r.family,tier=r.tier,
      effect=tonumber(r.effect),price=tonumber(r.price),fidelity=r.fidelity,distribution=r.distribution,
      origin=r.origin_kind,positions=dec(r.positions_json) or {},supportedVehicles=dec(r.fitment_json) or {}}
end
local function fitFor(d,key)
    if Install.isAddOnFamily(d.family) then
        for _, option in ipairs(Install.options(Install.design(d.designId) or d,key)) do
            if option.ok then return {outcome="fits",compatible=true,reason="a rated hardpoint accepts this component"} end
        end
        return {outcome="mismatch",compatible=false,reason="no compatible rated hardpoint"}
    end
    return Cat.resolve(d,key)
end

local function produceLine(d,state,t)
    local marketId=tostring(state.market_id or d.marketId or Markets.BASE_ID)
    if t<(tonumber(state.next_tick_at) or 0) then return 0 end
    local s=Cat.SUPPLY[d.tier] or {ceiling=3,initialAllocation=1,batch=1,cadenceSec=7200}
    local isInitial=not (state.initial_done==true or tonumber(state.initial_done)==1)
    local qty=isInitial and s.initialAllocation or (tonumber(state.batch) or s.batch)
    local before=available(d.designId,marketId); local want=math.min(qty,math.max(0,s.ceiling-before))
    local index=tonumber(state.next_tick_index) or 0; local nonce=ids.uuid4(hostRng)
    MySQL.insert.await([[INSERT IGNORE INTO component_production_run
      (server_id,market_id,design_id,tick_index,tick_at,claim_nonce,available_before,ceiling,requested,minted)
      VALUES (?,?,?,?,?,?,?,?,?,0)]],{serverId(),marketId,d.designId,index,tonumber(state.next_tick_at) or t,nonce,before,s.ceiling,qty})
    local held=MySQL.scalar.await([[SELECT claim_nonce FROM component_production_run
      WHERE server_id=? AND market_id=? AND design_id=? AND tick_index=?]],{serverId(),marketId,d.designId,index})
    local minted=0
    if held==nonce and want>0 then
        local ord,why=allocate(d,want)
        if ord then
            local runId=ids.uuid4(hostRng); local allocation=("component:%s:%s:%d"):format(serverId(),d.designId,index)
            MySQL.insert.await([[INSERT INTO component_manufacturing_run
              (run_id,server_id,design_id,allocation_key,quantity,produced_at) VALUES (?,?,?,?,?,?)]],{runId,serverId(),d.designId,allocation,want,t})
            for slot=1,want do
                local aid=ids.uuid4(hostRng); local o=ord[slot]
                local ok=MySQL.transaction.await({
                  {query=[[INSERT INTO component_asset
                    (asset_id,server_id,design_id,run_id,manufacturer_key,location_kind,global_ordinal,maker_ordinal,design_ordinal,created_at)
                    VALUES (?,?,?,?,?,'market',?,?,?,?)]],values={aid,serverId(),d.designId,runId,d.makerKey,o.global,o.maker,o.design,t}},
                  {query=[[INSERT INTO component_market_inventory
                    (market_id,asset_id,price,state,listed_at) VALUES (?,?,?,'available',?)]],values={marketId,aid,d.price,t}},
                  {query=[[INSERT INTO component_asset_transfer
                    (transfer_id,idem_key,server_id,asset_id,kind,market_id,amount,occurred_at)
                    VALUES (?,?,?,?,'production',?,0,?)]],values={ids.uuid4(hostRng),"production:"..serverId()..":"..aid,serverId(),aid,marketId,t}},
                })
                if ok then minted=minted+1 end
            end
            MySQL.update.await([[UPDATE component_production_run SET minted=?,run_id=?
              WHERE server_id=? AND market_id=? AND design_id=? AND tick_index=?]],{minted,runId,serverId(),marketId,d.designId,index})
        else log("ordinal allocation failed %s: %s",d.designId,tostring(why)) end
    end
    MySQL.update.await([[UPDATE component_supply_state SET next_tick_index=?,next_tick_at=?,initial_done=1,updated_at=?
      WHERE server_id=? AND market_id=? AND design_id=?]],{index+1,t+(tonumber(state.interval_sec) or s.cadenceSec),t,serverId(),marketId,d.designId})
    return minted
end

local function isNovel(c)
    local rows=MySQL.query.await("SELECT effect,price,fitment_json FROM component_design WHERE family=?",{c.family}) or {}
    local fitCount=#(c.supportedVehicles or {})
    for _,r in ipairs(rows) do local fits=dec(r.fitment_json) or {}
        if tonumber(r.effect)>=c.effect and tonumber(r.price)<=c.price and #fits>=fitCount then return false end
    end
    return true
end
local function isNovelPhysical(c)
    local tag=c.designId:match("^rndp:([^:]+):")
    local rows=MySQL.query.await([[SELECT spec_json FROM component_design
        WHERE origin_kind='rnd_physical' AND design_id LIKE ? AND family=?]],{"rndp:"..tostring(tag)..":%",c.family}) or {}
    local p=c.perf or {}
    local key=p.thrustN and "thrustN" or (p.forceN and "forceN" or (p.torqueNm and "torqueNm" or "capacityKg"))
    for _,row in ipairs(rows) do
        local d=dec(row.spec_json)
        local q=d and d.perf
        if q and q.kind==p.kind and q.propellant==p.propellant and
            (tonumber(q[key]) or 0)>=(tonumber(p[key]) or 0) and
            (tonumber(q.ispS) or 0)>=(tonumber(p.ispS) or 0) and
            (tonumber(q.heatKw) or 0)<=(tonumber(p.heatKw) or 0) and
            (tonumber(d.massKg) or math.huge)<=(tonumber(c.massKg) or 0) and
            (tonumber(d.price) or math.huge)<=(tonumber(c.price) or 0) then return false end
    end
    return true
end
local function announcePhysical(c, at)
    local p=c.perf or {}
    local measure=p.thrustN and ("%.0f kN thrust"):format(p.thrustN/1000)
        or p.forceN and ("%.0f kN pulse"):format(p.forceN/1000)
        or p.torqueNm and ("%.0f N m torque"):format(p.torqueNm)
        or p.capacityKg and ("%.0f kg capacity"):format(p.capacityKg) or "physical hardware"
    local body=("%s: %s%s. Base Market price: €$%d."):format(c.name,measure,
        p.ispS and (", %.0f s specific impulse"):format(p.ispS) or "",c.price)
    local eventId="rnd-release:"..c.designId
    local ok, why=MySQL.transaction.await({
        {query=[[INSERT IGNORE INTO paddock_event
          (server_id,event_id,at,kind,entities,cause_refs,effect_refs,facts,public_summary,salience,retain,provenance)
          VALUES (?,?,?,'rnd_release','[]','[]','[]',?,?,4,0,'simulated')]],
          values={serverId(),eventId,at,enc({designId=c.designId,makerKey=c.makerKey}),body}},
        {query=[[INSERT IGNORE INTO paddock_news
          (server_id,story_id,event_id,at,kind,template_id,headline,body,prominence,subjects)
          VALUES (?,?,?,?,'rnd_release','physical_v1',?,?,4,?)]],
          values={serverId(),eventId,eventId,at,c.manufacturer.." releases "..c.code,body,enc({c.makerKey})}},
    })
    if not ok then log("physical R&D news failed %s: %s",c.designId,tostring(why)) end
end

local function runRnd(t)
    for makerKey in pairs(Rnd.MAKERS) do
        local st=MySQL.single.await("SELECT * FROM component_rnd_state WHERE server_id=? AND maker_key=?",{serverId(),makerKey})
        if st and t>=(tonumber(st.next_run_at) or 0) then
            local index=tonumber(st.next_run_index) or 0; local nonce=ids.uuid4(hostRng)
            MySQL.insert.await([[INSERT IGNORE INTO component_rnd_run
              (server_id,maker_key,run_index,evaluated_at,claim_nonce,logic_version,outcome,reason)
              VALUES (?,?,?,?,?,?,'pending','pending')]],{serverId(),makerKey,index,t,nonce,Rnd.logicVersion})
            local held=MySQL.scalar.await("SELECT claim_nonce FROM component_rnd_run WHERE server_id=? AND maker_key=? AND run_index=?",{serverId(),makerKey,index})
            if held==nonce then
                local result=Rnd.evaluate({makerKey=makerKey,runIndex=index,secret=tostring(settings.partsRndSecret or "")})
                if result.outcome=="accepted" and not isNovel(result.candidate) then result.outcome="no_design";result.reason="dominated" end
                if result.outcome=="accepted" then
                    local c=result.candidate; c.manufacturer=makerKey:sub(1,1):upper()..makerKey:sub(2)
                    seedDesign(c,t); if c.distribution=="base" then
                        local tier=c.effect<=1.12 and "street" or (c.effect<=1.25 and "sport" or "premium")
                        local s=Cat.SUPPLY[tier]; MySQL.insert.await([[INSERT IGNORE INTO component_supply_state
                          (server_id,market_id,design_id,next_tick_index,next_tick_at,batch,interval_sec,initial_done,updated_at)
                          VALUES (?,'base_market',?,0,?,?,?,1,?)]],{serverId(),c.designId,t+s.cadenceSec,s.batch,s.cadenceSec,t})
                    end
                end
                MySQL.update.await([[UPDATE component_rnd_run SET outcome=?,reason=?,design_id=NULLIF(?,''),result_json=?
                  WHERE server_id=? AND maker_key=? AND run_index=?]],{result.outcome,result.reason,result.candidate and result.candidate.designId or "",enc(result),serverId(),makerKey,index})
            end
            -- No catch-up burst: one evaluation, then a new full cadence from now.
            MySQL.update.await([[UPDATE component_rnd_state SET next_run_index=?,next_run_at=?,updated_at=?
              WHERE server_id=? AND maker_key=?]],{index+1,t+Rnd.CADENCE_SEC,t,serverId(),makerKey})
        end
    end
    for programmeKey in pairs(Rnd.PHYSICAL) do
        local st=MySQL.single.await("SELECT * FROM component_rnd_state WHERE server_id=? AND maker_key=?",{serverId(),programmeKey})
        local singlePlayer=tostring(settings.environment or "")=="single_player"
        while st and t>=(tonumber(st.next_run_at) or 0) do
            local index=tonumber(st.next_run_index) or 0; local nonce=ids.uuid4(hostRng)
            local evaluatedAt=singlePlayer and tonumber(st.next_run_at) or t
            MySQL.insert.await([[INSERT IGNORE INTO component_rnd_run
              (server_id,maker_key,run_index,evaluated_at,claim_nonce,logic_version,outcome,reason)
              VALUES (?,?,?,?,?,2,'pending','pending')]],{serverId(),programmeKey,index,evaluatedAt,nonce})
            local held=MySQL.scalar.await("SELECT claim_nonce FROM component_rnd_run WHERE server_id=? AND maker_key=? AND run_index=?",{serverId(),programmeKey,index})
            if held==nonce then
                local score=tonumber(MySQL.scalar.await("SELECT design_score FROM component_rnd_competency WHERE server_id=? AND programme_key=?",{serverId(),programmeKey})) or 0
                local result=Rnd.evaluatePhysical({programmeKey=programmeKey,runIndex=index,competency=score,serverId=serverId(),
                    secret=tostring(settings.partsRndSecret or "")..":"..serverId()})
                if result and result.outcome=="accepted" and not isNovelPhysical(result.candidate) then
                    result.outcome="no_design"; result.reason="dominated"
                end
                if result and result.outcome=="accepted" then
                    local c=result.candidate
                    seedDesign(c,evaluatedAt)
                    Install.register(c)
                    TriggerEvent("ncm:rnd:design",c)
                    announcePhysical(c,evaluatedAt)
                    local s=Cat.SUPPLY[c.tier]
                    -- flight hardware is sold at its line's Autofixer, never the Base Market (owner 2026-10-10)
                    MySQL.insert.await([[INSERT IGNORE INTO component_supply_state
                      (server_id,market_id,design_id,next_tick_index,next_tick_at,batch,interval_sec,initial_done,updated_at)
                      VALUES (?,?,?,0,?,?,?,0,?)]],{serverId(),Markets.homeFor(c),c.designId,evaluatedAt,s.batch,s.cadenceSec,t})
                end
                if result then
                    MySQL.update.await([[UPDATE component_rnd_run SET outcome=?,reason=?,design_id=NULLIF(?,''),result_json=?
                      WHERE server_id=? AND maker_key=? AND run_index=?]],{result.outcome,result.reason,
                        result.candidate and result.candidate.designId or "",enc({result=result,competency=score}),serverId(),programmeKey,index})
                    MySQL.update.await("UPDATE component_rnd_competency SET design_score=LEAST(1000,design_score+?),updated_at=? WHERE server_id=? AND programme_key=?",
                        {result.outcome=="accepted" and 16 or 4,t,serverId(),programmeKey})
                end
            end
            local nextAt=singlePlayer and (tonumber(st.next_run_at)+Rnd.PHYSICAL_CADENCE_SEC) or (t+Rnd.PHYSICAL_CADENCE_SEC)
            MySQL.update.await([[UPDATE component_rnd_state SET next_run_index=?,next_run_at=?,updated_at=?
              WHERE server_id=? AND maker_key=?]],{index+1,nextAt,t,serverId(),programmeKey})
            st.next_run_index=index+1; st.next_run_at=nextAt
            if not singlePlayer then break end
        end
    end
end

function NcmComponents.produce()
    -- The tunable is live. Republish it on every scheduler pass so ncm_world and
    -- connected panels see an operator's change without a resource restart.
    pcall(function() GlobalState.ncmPartsEnabled=enabled() end)
    local t=now(); local rows=MySQL.query.await([[SELECT d.*,s.market_id,s.next_tick_index,s.next_tick_at,s.batch,s.interval_sec,s.initial_done
      FROM component_supply_state s JOIN component_design d ON d.design_id=s.design_id
      WHERE s.server_id=?]],{serverId()}) or {}
    local n=0 for _,r in ipairs(rows) do n=n+produceLine(designFromRow(r),r,t) end
    runRnd(t); return n
end

function NcmComponents.start()
    CreateThread(function() Wait(12000) while true do local ok,e=pcall(NcmComponents.produce);if not ok then log("scheduler failed: %s",tostring(e)) end Wait(60000) end end)
end

-- The components one MARKET is currently offering this driver.
--
-- `marketId` is a parameter and not a literal, which it used to be in both queries below. The vehicle half
-- of this payload has always resolved stock through the driver's known-market set; the component half
-- asked `base_market` by name, so the two halves of one screen disagreed about what a market is.
--
-- `17_MARKET_NETWORK.md` states the rule the literal broke: *"All query code must nevertheless accept a set
-- of known/available marketIds; it must never call a singleton theShop or query all stock without market
-- scope."* Nothing changes today -- Base Market is universally known, so every driver sees exactly what they
-- saw before -- and that is the point: the second component market becomes authored data rather than a
-- rewrite of this function and its caller.
function NcmComponents.marketOfferings(driverId,marketId,vehicleKeys)
    marketId=type(marketId)=="string" and marketId~="" and marketId or Markets.BASE_ID
    local rows=MySQL.query.await([[SELECT d.*,s.next_tick_at,s.batch,s.interval_sec
      FROM component_design d JOIN component_supply_state s ON s.design_id=d.design_id
      WHERE s.server_id=? AND s.market_id=? AND d.distribution IN ('base','autofixer') ORDER BY d.family,d.effect]],{serverId(),marketId}) or {}
    local ownedKeys={}; for _,r in ipairs(MySQL.query.await("SELECT DISTINCT vehicle_key FROM vehicle_asset WHERE server_id=? AND ncm_driver_id=?",{serverId(),driverId}) or {}) do ownedKeys[#ownedKeys+1]=r.vehicle_key end
    local out={}
    for i,r in ipairs(rows) do Wait(0) -- KB-464: one slice per design (the instruction quota is per slice)
        if NcmMarket then NcmMarket.stage=("components %s %d/%d %s"):format(marketId,i,#rows,tostring(r.design_id)) end
        local d=designFromRow(r); local s=Cat.SUPPLY[d.tier] or {ceiling=3}
        local nextAsset=MySQL.single.await([[SELECT a.asset_id,a.global_ordinal,a.maker_ordinal,a.design_ordinal,run.produced_at
          FROM component_market_inventory mi JOIN component_asset a ON a.asset_id=mi.asset_id
          LEFT JOIN component_manufacturing_run run ON run.run_id=a.run_id
          WHERE mi.market_id=? AND mi.state='available' AND a.server_id=? AND a.design_id=?
          ORDER BY mi.listed_at,a.design_ordinal LIMIT 1]],{marketId,serverId(),d.designId})
        local fit,ownedFit={},false
        for _,key in ipairs(vehicleKeys or Cat.STARTER_VEHICLES) do local x=fitFor(d,key);fit[key]={compatible=x.compatible,reason=x.reason} end
        for _,key in ipairs(ownedKeys) do if fitFor(d,key).compatible then ownedFit=true end end
        d.available=available(d.designId,marketId);d.ceiling=s.ceiling;d.soldOut=d.available==0;d.nextBatch=tonumber(r.batch) or 0
        d.cadenceSec=tonumber(r.interval_sec);d.nextProductionAt=tonumber(r.next_tick_at);d.nextAsset=nextAsset
        d.fitment=fit;d.ownedCompatible=ownedFit;d.marketId=marketId;out[#out+1]=d
        -- a physical add-on is a product with a name (L356: "Slipstream SL-1", not only "EDW-SL1")
        local inst=Install.isAddOnFamily(d.family) and Install.design(d.designId)
        if inst then d.name=inst.name;d.subtitle=inst.subtitle end
        if not Install.isAddOnFamily(d.family) then
            Wait(0)
            local setup=Handling.compose({vehicle="market-preview",parts={{id=d.designId,family=d.family,effect=d.effect}}},{at=now()})
            if setup then d.projection={levers=setup.levers,topSpeedScale=setup.topSpeedScale,limited=setup.limited} end
        end
    end
    return out
end

function NcmComponents.inventory(pid)
    local d=driver(pid);if not d then return nil,"no_driver" end
    local parts=MySQL.query.await([[SELECT a.asset_id,a.design_id,a.location_kind,a.machine_asset_id,a.global_ordinal,
      a.maker_ordinal,a.design_ordinal,a.factory_original,a.acquired_via,a.acquired_at,a.exposure_m,
      d.display_manufacturer,d.code,d.subtitle,d.family,d.tier,d.effect,d.fidelity,d.positions_json,d.fitment_json
      FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
      WHERE a.server_id=? AND a.ncm_driver_id=? ORDER BY d.family,d.effect,a.design_ordinal,a.asset_id]],{serverId(),d.ncmDriverId}) or {}
    local serviceRows=MySQL.query.await([[SELECT s.component_asset_id,s.condition_id,s.relief_m,s.amount,s.occurred_at
      FROM component_service s JOIN component_asset a ON a.asset_id=s.component_asset_id
      WHERE a.server_id=? AND a.ncm_driver_id=? ORDER BY s.occurred_at,s.service_id]],{serverId(),d.ncmDriverId}) or {}
    local services={} for _,s in ipairs(serviceRows) do local k=tostring(s.component_asset_id);services[k]=services[k] or {};services[k][#services[k]+1]=s end
    local bindingRows=MySQL.query.await([[SELECT b.component_asset_id,b.control_key,b.gesture,b.command
      FROM machine_control_binding b JOIN component_asset a ON a.asset_id=b.component_asset_id
      WHERE a.server_id=? AND a.ncm_driver_id=? AND a.location_kind='installed' AND a.machine_asset_id=b.machine_asset_id
      ORDER BY b.control_key,b.gesture]],{serverId(),d.ncmDriverId}) or {}
    local bindings={} for _,b in ipairs(bindingRows) do
        local k=tostring(b.component_asset_id);bindings[k]=bindings[k] or {}
        bindings[k][#bindings[k]+1]={control=b.control_key,gesture=b.gesture,command=b.command}
    end
    local mountRows=MySQL.query.await([[SELECT i.component_asset_id,i.interface_id,i.install_json
      FROM machine_configuration_current x JOIN vehicle_asset v ON v.asset_id=x.machine_asset_id
      JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id
      WHERE v.server_id=? AND v.ncm_driver_id=?]],{serverId(),d.ncmDriverId}) or {}
    local mounted={} for _,i in ipairs(mountRows) do mounted[tostring(i.component_asset_id)]=i end
    for _,p in ipairs(parts) do
        p.effect=tonumber(p.effect);p.exposure_m=tonumber(p.exposure_m) or 0;p.positions=dec(p.positions_json) or {};p.supportedVehicles=dec(p.fitment_json) or {};p.positions_json=nil;p.fitment_json=nil
        p.bindings=bindings[tostring(p.asset_id)] or {}
        local installed=mounted[tostring(p.asset_id)]
        if installed and p.location_kind=='installed' then
            p.mountId=installed.interface_id;p.facing=(dec(installed.install_json) or {}).facing
        end
        local history=services[tostring(p.asset_id)] or {};local state=Wear.evaluate(p,history)
        p.wear=Wear.publicState(state);p.service_count=#history
        if state and state.conditions[1] then
            local quote=Wear.serviceQuote(p,history,state.conditions[1].id)
            if quote then p.service_quote={condition_id=quote.conditionId,cost=quote.cost,relief_m=quote.reliefM} end
        end
    end
    local machines=MySQL.query.await([[SELECT asset_id,vehicle_key,record,production_ordinal,maker_ordinal,model_ordinal,odometer_m
      FROM vehicle_asset WHERE server_id=? AND ncm_driver_id=? ORDER BY acquired_at,asset_id]],{serverId(),d.ncmDriverId}) or {}
    for _,m in ipairs(machines) do m.fitment={};for _,p in ipairs(parts) do
        m.fitment[p.asset_id]=Install.isAddOnFamily(p.family) and fitFor(Install.design(p.design_id) or {family=p.family},m.vehicle_key)
            or Cat.resolve({supportedVehicles=p.supportedVehicles},m.vehicle_key)
    end end
    -- the pad's engineering bench: where each add-on can go on each Machine (only the fits that mate), and on
    -- DEVELOPMENT the designs that can be fabricated (the one acquisition shortcut; Online buys them)
    -- L356: a Slipstream unit's switch (its own runtime state, not configuration)
    local units={}
    for _,u in ipairs(MySQL.query.await([[SELECT u.component_asset_id,u.machine_asset_id,u.enabled FROM slipstream_unit u
      JOIN component_asset a ON a.asset_id=u.component_asset_id WHERE a.server_id=? AND a.ncm_driver_id=?]],{serverId(),d.ncmDriverId}) or {}) do
        units[tostring(u.component_asset_id):lower()..":"..tostring(u.machine_asset_id):lower()]=tonumber(u.enabled)~=0
    end
    for _,p in ipairs(parts) do
        if p.family=="slipstream" and p.location_kind=="installed" and p.machine_asset_id then
            local on=units[tostring(p.asset_id):lower()..":"..tostring(p.machine_asset_id):lower()]
            p.unitEnabled=on~=false        -- a unit with no row yet is on (it boots on first drive)
        end
        if Install.isAddOnFamily(p.family) then
            p.addOn=true
            local design=Install.design(p.design_id)
            p.mounts={}
            for _,m in ipairs(machines) do
                local list={}
                if design then for _,o in ipairs(Install.options(design,m.vehicle_key)) do if o.ok then list[#list+1]={mountId=o.mountId,facing=o.facing} end end end
                p.mounts[m.asset_id]=list
            end
        end
    end
    local fabricable=nil
    local okId,ident=pcall(function() return GlobalState.ncmIdentity end)
    local dev=false
    if okId and type(ident)=="table" then dev=tostring(ident.environment or "development")=="development" end
    if dev then
        fabricable={}
        for _,x in ipairs(Install.DESIGNS) do fabricable[#fabricable+1]={key=x.code:lower():gsub("^%w+%-",""),code=x.code,name=x.name,family=x.family} end
    end
    local balance=tonumber(MySQL.scalar.await("SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?",{d.ncmDriverId,serverId()})) or 0
    return {partsEnabled=enabled(),parts=parts,machines=machines,balance=balance,serverNow=now(),fabricable=fabricable}
end
-- IDEA-595: serialized Parts are per-asset rows that only ever accumulate, so this list grows without bound by
-- design. Bounded through `NcmStream` rather than waiting for the deploy on which it stops arriving.
function NcmComponents.pushInventory(pid) local ok,p=pcall(NcmComponents.inventory,pid);if ok and p then NcmStream.send(pid,"ncm:component.inventory",p,"parts") end end

function NcmComponents.purchase(pid,marketId,assetId,idemKey)
    if not enabled() then return nil,"Parts economy is awaiting live QA." end
    local d=driver(pid);if not d then return nil,"no_driver" end
    -- Knowledge and access, asked the same way the vehicle purchase asks them (`market.lua`), instead of
    -- comparing the id to a literal. Identical behaviour while Base Market is the only market and everyone
    -- knows it -- and it means restricted component distribution (`IDEA-298`) lands as authored data rather
    -- than as a new branch here.
    local access=NcmMarketKnowledge and NcmMarketKnowledge.state(d.ncmDriverId,marketId) or nil
    if not access then return nil,"market_unknown" end
    if not Markets.accessible(access.accessState) then return nil,"market_inaccessible" end
    local requestKey=tostring(idemKey or "");if requestKey=="" then requestKey=assetId end
    local t=now();local idem="component_purchase:"..serverId()..":"..requestKey
    local tx={
      {query=[[UPDATE component_market_inventory mi SET state='sold',sold_at=?,sold_to_driver_id=?
        WHERE market_id=? AND asset_id=? AND state='available' AND
        (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?)>=mi.price]],values={t,d.ncmDriverId,marketId,assetId,d.ncmDriverId,serverId()}},
      {query=[[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,market_id,asset_id)
        SELECT ?,?,'component_purchase',-price,'eddies',asset_id,'Base Market component purchase',?,market_id,asset_id
        FROM component_market_inventory WHERE market_id=? AND asset_id=? AND state='sold' AND sold_to_driver_id=?]],values={d.ncmDriverId,serverId(),idem,marketId,assetId,d.ncmDriverId}},
      {query=[[UPDATE component_asset a JOIN component_market_inventory mi ON mi.asset_id=a.asset_id
        SET a.ncm_driver_id=?,a.location_kind='storage',a.machine_asset_id=NULL,a.acquired_via='purchase',a.acquired_at=?
        WHERE a.asset_id=? AND mi.market_id=? AND mi.state='sold' AND mi.sold_to_driver_id=? AND a.ncm_driver_id IS NULL]],values={d.ncmDriverId,t,assetId,marketId,d.ncmDriverId}},
      {query=[[INSERT IGNORE INTO component_asset_transfer
        (transfer_id,idem_key,server_id,asset_id,to_driver_id,kind,market_id,amount,occurred_at)
        SELECT ?,?,?,asset_id,?,'primary_purchase',market_id,price,? FROM component_market_inventory
        WHERE market_id=? AND asset_id=? AND state='sold' AND sold_to_driver_id=?]],values={ids.uuid4(hostRng),idem,serverId(),d.ncmDriverId,t,marketId,assetId,d.ncmDriverId}},
      -- L361: a unit an engineer listed pays its seller, in the same transaction as the buyer's debit
      {query=[[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key,market_id,asset_id)
        SELECT seller_driver_id,?,'component_sale',price,'eddies',asset_id,'Workshop unit sold',?,market_id,asset_id
        FROM component_market_inventory WHERE market_id=? AND asset_id=? AND state='sold' AND sold_to_driver_id=?
        AND seller_driver_id IS NOT NULL]],values={serverId(),"sale:"..idem,marketId,assetId,d.ncmDriverId}},
    }
    local ok=MySQL.transaction.await(NcmEconomy.withBalanceLocks(tx,{d.ncmDriverId}))
    if not ok then return nil,"transaction_failed" end
    local owner=MySQL.scalar.await("SELECT ncm_driver_id FROM component_asset WHERE asset_id=?",{assetId});if owner~=d.ncmDriverId then return nil,"unavailable_or_unaffordable" end
    NcmComponents.pushInventory(pid);if NcmMarket then NcmMarket.push(pid) end;return true
end

RegisterNetEvent("ncm:component.inventory.request",function() local pid=tonumber(source) or 0;CreateThread(function() NcmComponents.pushInventory(pid) end) end)
RegisterNetEvent("ncm:component.purchase",function(marketId,assetId,idemKey) local pid=tonumber(source) or 0;CreateThread(function()
    local ok,why=NcmComponents.purchase(pid,tostring(marketId or ""),tostring(assetId or ""),tostring(idemKey or ""))
    TriggerClientEvent("ncm:component.purchase.result",pid,{ok=ok==true,reason=ok and nil or tostring(why)})
    NcmComms.send(pid,{id=(ok and "component.purchase:" or "component.purchase.refused:")..tostring(assetId),
        category=ok and "transaction" or "warning",priority="actionable",title=ok and "PART ACQUIRED" or "PURCHASE REFUSED",
        message=ok and "The serialized component is in Parts Inventory. Choose a compatible owned Machine to fit it." or tostring(why),
        reference=ok and "collection" or "market",surface="toast",repeatPolicy={mode=ok and "once" or "cooldown",cooldownSec=2}})
end) end)
-- KB-364: a change with no player behind it (a server-side grant, pid 0) has nobody to push to -- and a host call
-- with id 0 throws "id must be positive", which stops the WHOLE resource (racing went with it, 2026-10-06 19:00).
AddEventHandler("ncm:component.changed",function(pid) pid=tonumber(pid) or 0;if pid<=0 then return end;NcmComponents.pushInventory(pid);if NcmMarket then pcall(NcmMarket.push,pid) end end)
