-- tools/npc-sql-gen.lua -- the NPC market and posted-Exchange SQL, run against REAL MariaDB and rolled back (L249 4-5).
--
-- The Paddock harness's database is a double that matches query text; it cannot prove a guarded multi-table
-- transaction does what it claims. This file builds the EXACT statements the code sends (PaddockMarkets.partPurchaseTx,
-- PaddockExchange.settlementTx) and writes one SQL script that runs them inside START TRANSACTION ... ROLLBACK, with
-- fixture rows under a throwaway server id, printing labelled checks. `tools/test-npc-sql.ps1` runs it and asserts.
--
--   lua tools/npc-sql-gen.lua <designId> <makerKey> <marketId> <driverId> <out.sql>
local DESIGN, MAKER, MARKET, DRIVER, OUT = arg[1], arg[2], arg[3], arg[4], arg[5]
assert(DESIGN and MAKER and MARKET and DRIVER and OUT, "usage: lua tools/npc-sql-gen.lua <designId> <makerKey> <marketId> <driverId> <out.sql>")
local ROOT = (arg[0]:gsub("[\\/]tools[\\/]npc%-sql%-gen%.lua$", ""))
if ROOT == arg[0] then ROOT = "." end
local CORE = ROOT .. "/ncm/core/"
local RES = ROOT .. "/ncm/online/resources/ncm_paddock/server/"

-- core, the way tests/run.lua loads it
local Core = dofile(CORE .. "init.lua")
for _, f in ipairs(dofile(CORE .. "MANIFEST.lua")) do dofile(CORE .. f) end
local Json = NcmCore.get("vocabulary.json")

-- the host the Paddock files expect, as far as these statements need it
local SID = "ncm-test-npc"
PaddockUtil = { sid = function() return SID end, checkStatement = function() return nil end, encode = function(v) return Json.encode(v) end,
    logger = function() return function() end end, now = function() return 1800000000 end, yielder = function() return function() end end }
PaddockSettings = { get = function(_, d) return d end }
PaddockStore = { world = { seed = 7, orgs = {}, people = {}, personOrder = {}, orgOrder = {} }, flush = function() end,
    markOrg = function() end, markPerson = function() end }
PaddockPlayers = { pidOf = function() return nil end }
Open77 = { notifications = { send = function() end } }
function CreateThread() end
function Wait() end
dofile(RES .. "wallet.lua")
PaddockLive = nil
dofile(RES .. "npc_cars.lua")
dofile(RES .. "markets.lua")
dofile(RES .. "exchange.lua")

local function lit(v)
    if v == nil then return "NULL" end
    if type(v) == "number" then return (v == math.floor(v)) and string.format("%d", v) or tostring(v) end
    if type(v) == "boolean" then return v and "1" or "0" end
    return "'" .. tostring(v):gsub("\\", "\\\\"):gsub("'", "''") .. "'"
end
local function render(st)
    local i = 0
    local sql = st.query:gsub("%?", function() i = i + 1 return lit(st.values[i]) end)
    return (sql:gsub("%s+", " ")) .. ";"
end
local out = {}
local function emit(s) out[#out + 1] = s end
local function check(label, sql) emit(("SELECT '%s' AS label, (%s) AS got;"):format(label, sql)) end
local T = 1800000000

emit("START TRANSACTION;")
emit("SET FOREIGN_KEY_CHECKS = 1;")
-- fixtures: two NPC teams, a market part, an NPC's stored part, and a player with money
local car = Json.encode({ power_unit = 2, aerodynamics = 2, tires = 2, chassis = 2, progress = {} })
for _, org in ipairs({ { "o_t", 50000 }, { "o_u", 50000 } }) do
    emit(("INSERT INTO paddock_org (server_id, org_id, tier, series_id, name, short, colour, prestige, cash, facility, car_json, origin) VALUES (%s, %s, 'street', 'street_a', %s, 'TST', '#ffffff', 40, %d, 50, %s, 'genesis');")
        :format(lit(SID), lit(org[1]), lit("Test " .. org[1]), org[2], lit(car)))
end
for _, a in ipairs({ { "tst-a1", "market" }, { "tst-b1", "npc_storage", "org", "o_t" }, { "tst-c1", "npc_storage", "org", "o_u" } }) do
    emit(("INSERT INTO component_asset (asset_id, server_id, design_id, manufacturer_key, location_kind, created_at, owner_principal_kind, owner_principal_id) VALUES (%s, %s, %s, %s, %s, 0, %s, %s);")
        :format(lit(a[1]), lit(SID), lit(DESIGN), lit(MAKER), lit(a[2]), lit(a[3]), lit(a[4])))
end
emit(("INSERT INTO component_market_inventory (market_id, asset_id, price, state, listed_at) VALUES (%s, 'tst-a1', 1000, 'available', 0);"):format(lit(MARKET)))
emit(("INSERT INTO ledger (ncm_driver_id, server_id, kind, amount, currency, ref, note, idem_key) VALUES (%s, %s, 'test_fixture', 5000, 'eddies', '', '', 'tst-fixture-%d');"):format(lit(DRIVER), lit(SID), T))

-- A. an NPC team buys a shelf part; a second team racing for the same part pays nothing
local W = PaddockStore.world
W.orgs.o_t = { id = "o_t", tier = "street", cash = 50000, car = Json.decode(car) }
W.orgs.o_u = { id = "o_u", tier = "street", cash = 50000, car = Json.decode(car) }
local offer = { marketId = MARKET, assetId = "tst-a1", price = 1000 }
for _, st in ipairs(PaddockMarkets.partPurchaseTx({ kind = "org", id = "o_t", obj = W.orgs.o_t }, offer, T)) do emit(render(st)) end
for _, st in ipairs(PaddockMarkets.partPurchaseTx({ kind = "org", id = "o_u", obj = W.orgs.o_u }, offer, T + 1)) do emit(render(st)) end
check("A.sold_to", ("SELECT sold_to_principal FROM component_market_inventory WHERE asset_id='tst-a1' AND market_id=%s"):format(lit(MARKET)))
check("A.owner", "SELECT CONCAT(owner_principal_kind,':',owner_principal_id,':',location_kind) FROM component_asset WHERE asset_id='tst-a1'")
check("A.cash_t", ("SELECT cash FROM paddock_org WHERE server_id=%s AND org_id='o_t'"):format(lit(SID)))
check("A.cash_u", ("SELECT cash FROM paddock_org WHERE server_id=%s AND org_id='o_u'"):format(lit(SID)))
check("A.money_rows", ("SELECT COUNT(*) FROM npc_money WHERE server_id=%s"):format(lit(SID)))

-- B. a player buys an NPC's posted part: part to the player, money from the ledger to the team, the board closed
emit("INSERT INTO exchange_post (post_id, server_id, kind, principal_kind, principal_id, asset_id, cash, state, revision, created_at, expires_at) VALUES ('tst-post-b', "
    .. lit(SID) .. ", 'offer', 'org', 'o_t', 'tst-b1', 1200, 'open', 1, 0, " .. (T + 86400) .. ");")
emit("INSERT INTO exchange_reservation (asset_id, server_id, holder_kind, holder_id, created_at) VALUES ('tst-b1', " .. lit(SID) .. ", 'post', 'tst-post-b', 0);")
emit("INSERT INTO exchange_bid (bid_id, server_id, post_id, post_revision, principal_kind, principal_id, cash, state, created_at, expires_at) VALUES ('tst-bid-b', "
    .. lit(SID) .. ", 'tst-post-b', 1, 'driver', " .. lit(DRIVER) .. ", 1200, 'open', 0, " .. (T + 7200) .. ");")
local postB = { postId = "tst-post-b", kind = "offer", principal = "org:o_t", assetId = "tst-b1", cash = 1200, revision = 1 }
local bidB = { bidId = "tst-bid-b", postId = "tst-post-b", principal = "driver:" .. DRIVER, cash = 1200 }
local txB = PaddockExchange.settlementTx(postB, bidB, T)
for _, st in ipairs(txB) do emit(render(st)) end
check("B.owner", "SELECT CONCAT(COALESCE(ncm_driver_id,'-'),':',COALESCE(owner_principal_id,'-'),':',location_kind) FROM component_asset WHERE asset_id='tst-b1'")
check("B.ledger", ("SELECT COALESCE(SUM(amount),0) FROM ledger WHERE server_id=%s AND ncm_driver_id=%s"):format(lit(SID), lit(DRIVER)))
check("B.cash_t", ("SELECT cash FROM paddock_org WHERE server_id=%s AND org_id='o_t'"):format(lit(SID)))
check("B.post", "SELECT state FROM exchange_post WHERE post_id='tst-post-b'")
check("B.bid", "SELECT state FROM exchange_bid WHERE bid_id='tst-bid-b'")
check("B.reservations", "SELECT COUNT(*) FROM exchange_reservation WHERE holder_id IN ('tst-post-b','tst-bid-b')")
check("B.settled", ("SELECT COUNT(*) FROM exchange_settlement WHERE server_id=%s AND post_id='tst-post-b'"):format(lit(SID)))

-- C. a player who cannot pay: the gate refuses, the part stays with the team, no money moves, the post stays open
emit("INSERT INTO exchange_post (post_id, server_id, kind, principal_kind, principal_id, asset_id, cash, state, revision, created_at, expires_at) VALUES ('tst-post-c', "
    .. lit(SID) .. ", 'offer', 'org', 'o_u', 'tst-c1', 900000, 'open', 1, 0, " .. (T + 86400) .. ");")
emit("INSERT INTO exchange_bid (bid_id, server_id, post_id, post_revision, principal_kind, principal_id, cash, state, created_at, expires_at) VALUES ('tst-bid-c', "
    .. lit(SID) .. ", 'tst-post-c', 1, 'driver', " .. lit(DRIVER) .. ", 900000, 'open', 0, " .. (T + 7200) .. ");")
local postC = { postId = "tst-post-c", kind = "offer", principal = "org:o_u", assetId = "tst-c1", cash = 900000, revision = 1 }
local bidC = { bidId = "tst-bid-c", postId = "tst-post-c", principal = "driver:" .. DRIVER, cash = 900000 }
for _, st in ipairs(PaddockExchange.settlementTx(postC, bidC, T + 5)) do emit(render(st)) end
check("C.owner", "SELECT CONCAT(COALESCE(ncm_driver_id,'-'),':',COALESCE(owner_principal_id,'-'),':',location_kind) FROM component_asset WHERE asset_id='tst-c1'")
check("C.ledger", ("SELECT COALESCE(SUM(amount),0) FROM ledger WHERE server_id=%s AND ncm_driver_id=%s"):format(lit(SID), lit(DRIVER)))
check("C.cash_u", ("SELECT cash FROM paddock_org WHERE server_id=%s AND org_id='o_u'"):format(lit(SID)))
check("C.post", "SELECT state FROM exchange_post WHERE post_id='tst-post-c'")
check("C.settled", ("SELECT COUNT(*) FROM exchange_settlement WHERE server_id=%s AND post_id='tst-post-c'"):format(lit(SID)))

-- D. L298: an NPC's real car -- minted with its eleven factory parts, a part installed on it as a new configuration
--    revision (the replaced factory part to storage), and a service row by an NPC principal
local G = NcmCore.get("economy.npc_garage")
local model = G.startingModel({ classes = { "Muscle", "Sport", "Tech" }, prestigeMax = 2 }, 7, "org", "o_t")
local mint, carId = PaddockCars.mintStatements(model, "org", "o_t", T)
for _, st in ipairs(mint) do emit(render(st)) end
check("D.factory_parts", ("SELECT COUNT(*) FROM component_asset WHERE machine_asset_id=%s AND location_kind='installed' AND owner_principal_id='o_t'"):format(lit(carId)))
check("D.config_items", ("SELECT COUNT(*) FROM machine_configuration_item i JOIN machine_configuration_current c ON c.configuration_id=i.configuration_id WHERE c.machine_asset_id=%s"):format(lit(carId)))
-- install tst-a1 (team o_t bought it in A) on the car: the statements PaddockCars.install sends, against the rows the mint made
emit(("SET @cfg := (SELECT configuration_id FROM machine_configuration_current WHERE machine_asset_id=%s);"):format(lit(carId)))
emit(("SET @fam := (SELECT d.family FROM component_asset a JOIN component_design d ON d.design_id=a.design_id WHERE a.asset_id='tst-a1');"))
emit(("SET @old := (SELECT i.component_asset_id FROM machine_configuration_item i JOIN component_asset a ON a.asset_id=i.component_asset_id JOIN component_design d ON d.design_id=a.design_id WHERE i.configuration_id=@cfg AND d.family=@fam LIMIT 1);"))
emit(("INSERT INTO machine_configuration (configuration_id, machine_asset_id, revision, created_at) VALUES ('tst-cfg-2', %s, 2, %d);"):format(lit(carId), T))
emit("INSERT INTO machine_configuration_item (configuration_id, interface_id, component_asset_id) SELECT 'tst-cfg-2', i.interface_id, IF(i.component_asset_id=@old, 'tst-a1', i.component_asset_id) FROM machine_configuration_item i WHERE i.configuration_id=@cfg;")
emit(("UPDATE machine_configuration_current SET configuration_id='tst-cfg-2' WHERE machine_asset_id=%s;"):format(lit(carId)))
emit(("UPDATE component_asset SET location_kind='installed', machine_asset_id=%s WHERE asset_id='tst-a1' AND owner_principal_kind='org' AND owner_principal_id='o_t';"):format(lit(carId)))
emit("UPDATE component_asset SET location_kind='npc_storage', machine_asset_id=NULL WHERE asset_id=@old;")
check("D.installed", ("SELECT COUNT(*) FROM machine_configuration_item i JOIN machine_configuration_current c ON c.configuration_id=i.configuration_id WHERE c.machine_asset_id=%s AND i.component_asset_id='tst-a1'"):format(lit(carId)))
check("D.old_stored", "SELECT location_kind FROM component_asset WHERE asset_id=@old")
local svc = PaddockCars.serviceStatements({ assetId = "tst-a1", exposure_m = 1000 }, { conditionId = "tst", reliefM = 500, cost = 350, workmanship = {} }, "org", "o_t", T)
emit(render(svc))
check("D.service", "SELECT CONCAT(by_principal_kind,':',by_principal_id,':',amount) FROM component_service WHERE component_asset_id='tst-a1'")

emit("ROLLBACK;")
check("after.rollback", ("SELECT COUNT(*) FROM paddock_org WHERE server_id=%s"):format(lit(SID)))

local f = assert(io.open(OUT, "w"))
f:write(table.concat(out, "\n"), "\n")
f:close()
print(("wrote %d statements to %s"):format(#out, OUT))
