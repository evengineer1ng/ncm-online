-- ncm_paddock / server / markets -- NPCs in the markets (L249 step 4, IDEA-730; owner: "all markets need buyers").
--
-- Paddock teams and independent racers buy the SAME serialized parts and machines players do, from the same shelves,
-- and pay real money for them:
--
--   * a team that decides to develop an area (life.lua `invest_dev`) first buys a real part of a family that serves
--     it and fits it; the part's price develops the area by more than workshop hours would (`economy.npc_market`);
--   * an independent street racer (no team) shops on a cadence with their own money (`person.cash`: purses in), for
--     parts for their own car, and now and then a better car.
--
-- Every purchase is ONE guarded transaction, the shape of the player purchase in ncm_league (components.lua,
-- market.lua): claim the shelf row only while it is still available; move the asset to the NPC; write the transfer;
-- take the money from `paddock_org.cash` / `paddock_person.cash` and record it in `npc_money` -- the money steps
-- conditional on the claim having landed, so a lost race for the shelf costs nothing. Nothing is minted.
--
-- Players keep first claim: an NPC never buys a part listed less than `npcExclusivitySec` ago, and each market sells
-- at most `npcPartsPerMarketHour` parts an hour to NPCs. `partsEnabled` (ncm_league) parks the parts economy for
-- everyone, NPCs included -- read here from the same tunable store as `npcMarketsEnabled`.
PaddockMarkets = { stats = { parts = 0, vehicles = 0, refused = 0, lost = 0 } }

local U = PaddockUtil
local log = U.logger("markets")
local NM = NcmCore.get("economy.npc_market")
local Car = NcmCore.get("paddock.car")
local Hash = NcmCore.get("vocabulary.hash")
local ids = NcmCore.get("vocabulary.ids")
local function set(k, d) return PaddockSettings.get(k, d) end
local function rng() return math.random() end

local perMarketHour = {}     -- marketId -> { hour, n }
local function marketAllows(marketId, t)
    local hour = math.floor(t / 3600)
    local m = perMarketHour[marketId]
    if not m or m.hour ~= hour then m = { hour = hour, n = 0 }; perMarketHour[marketId] = m end
    return m.n < set("npcPartsPerMarketHour", 2), m
end

--- The NPC behind a principal: { kind, id, obj, tier, car, cash }.
local function principalOf(kind, id)
    local w = PaddockStore.world
    if kind == "org" then
        local o = w.orgs[id]
        if not o then return nil end
        return { kind = "org", id = id, obj = o, tier = o.tier, car = o.car }
    end
    local p = w.people[id]
    if not p then return nil end
    return { kind = "person", id = id, obj = p, tier = "street", car = p.car }
end
PaddockMarkets.principalOf = principalOf

local function cashOf(pr) return tonumber(pr.obj.cash) or 0 end

--- Run `tx` as ONE database transaction (statements checked for nil values first). Returns ok, err.
function PaddockMarkets.atomic(tx)
    for k, st in ipairs(tx) do
        local bad = U.checkStatement(st, k)
        if bad then return false, bad end
    end
    local called, ok, err = pcall(MySQL.transaction.await, tx)
    if not called then return false, tostring(ok) end
    return ok == true, err
end
local function moneyTable(pr) return pr.kind == "org" and "paddock_org" or "paddock_person" end
local function moneyKey(pr) return pr.kind == "org" and "org_id" or "person_id" end
local function mark(pr) if pr.kind == "org" then PaddockStore.markOrg(pr.id) else PaddockStore.markPerson(pr.id) end end

--- Parts on the shelves for the families serving `area`, at most `budget`.
local function offers(area, budget)
    local fams = NM.AREA_FAMILIES[area] or {}
    if #fams == 0 then return {} end
    local marks = {}
    for i = 1, #fams do marks[i] = "?" end
    local vals = { U.sid() }
    for _, f in ipairs(fams) do vals[#vals + 1] = f end
    vals[#vals + 1] = math.floor(budget)
    local rows = MySQL.query.await(([[SELECT mi.market_id, mi.asset_id, mi.price, mi.listed_at, d.family, d.tier, d.design_id
        FROM component_market_inventory mi JOIN component_asset a ON a.asset_id = mi.asset_id
        JOIN component_design d ON d.design_id = a.design_id
        WHERE mi.state = 'available' AND a.server_id = ? AND d.family IN (%s) AND mi.price <= ?
        ORDER BY mi.listed_at LIMIT 40]]):format(table.concat(marks, ",")), vals) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { marketId = r.market_id, assetId = r.asset_id, price = tonumber(r.price), listedAt = tonumber(r.listed_at),
            family = r.family, tier = r.tier, designId = r.design_id }
    end
    return out
end

--- The statements of one NPC part purchase (exposed for tools/npc-sql-gen.lua, which runs them against MariaDB
--- inside a rolled-back transaction).
function PaddockMarkets.partPurchaseTx(pr, o, t)
    local key = NM.principal(pr.kind, pr.id)
    local idem = ("npc_part:%s:%s"):format(U.sid(), o.assetId)
    local guard = [[mi.market_id = ? AND mi.asset_id = ? AND mi.state = 'sold' AND mi.sold_to_principal = ? AND mi.sold_at = ?]]
    local gv = { o.marketId, o.assetId, key, t }
    local function with(vals) local out = {} for _, v in ipairs(vals) do out[#out + 1] = v end for _, v in ipairs(gv) do out[#out + 1] = v end return out end
    local tx = {
        { query = [[UPDATE component_market_inventory SET state = 'sold', sold_at = ?, sold_to_principal = ?
            WHERE market_id = ? AND asset_id = ? AND state = 'available']], values = { t, key, o.marketId, o.assetId } },
        { query = [[UPDATE component_asset a JOIN component_market_inventory mi ON mi.asset_id = a.asset_id
            SET a.owner_principal_kind = ?, a.owner_principal_id = ?, a.location_kind = 'npc_fitted', a.machine_asset_id = NULL,
                a.acquired_via = 'purchase', a.acquired_at = ?
            WHERE a.ncm_driver_id IS NULL AND ]] .. guard, values = with({ pr.kind, pr.id, t }) },
        { query = [[INSERT IGNORE INTO component_asset_transfer (transfer_id, idem_key, server_id, asset_id, kind, market_id, amount, occurred_at)
            SELECT ?, ?, ?, mi.asset_id, 'npc_purchase', mi.market_id, mi.price, ? FROM component_market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), idem, U.sid(), t }) },
        { query = ([[UPDATE %s p JOIN component_market_inventory mi ON ]] .. guard .. [[ SET p.cash = p.cash - mi.price
            WHERE p.server_id = ? AND p.%s = ?]]):format(moneyTable(pr), moneyKey(pr)), values = { o.marketId, o.assetId, key, t, U.sid(), pr.id } },
        { query = [[INSERT IGNORE INTO npc_money (entry_id, server_id, principal_kind, principal_id, amount, kind, ref, idem_key, created_at)
            SELECT ?, ?, ?, ?, -mi.price, 'part_purchase', mi.asset_id, ?, ? FROM component_market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), U.sid(), pr.kind, pr.id, idem, t }) },
    }
    return tx
end

--- The guarded purchase of one shelf part by an NPC. Returns the offer on success, nil and a reason otherwise.
local function purchasePart(pr, o, t)
    local tx = PaddockMarkets.partPurchaseTx(pr, o, t)
    -- ONE transaction (never U.transact, which chunks): the claim and the money move together or not at all
    local ok, err = PaddockMarkets.atomic(tx)
    if not ok then return nil, "transaction_failed: " .. tostring(err) end
    local owner = MySQL.scalar.await("SELECT owner_principal_id FROM component_asset WHERE asset_id = ?", { o.assetId })
    if owner ~= pr.id then PaddockMarkets.stats.lost = PaddockMarkets.stats.lost + 1 return nil, "taken" end
    pr.obj.cash = cashOf(pr) - o.price
    mark(pr)
    return o
end

--- A part an NPC fits makes its old one of that family surplus (into storage: the Exchange can sell it, step 5).
local function retireDisplaced(pr, newPart)
    local rows = MySQL.query.await([[SELECT a.asset_id, d.family, d.tier FROM component_asset a JOIN component_design d ON d.design_id = a.design_id
        WHERE a.server_id = ? AND a.owner_principal_kind = ? AND a.owner_principal_id = ? AND a.location_kind = 'npc_fitted' AND d.family = ?]],
        { U.sid(), pr.kind, pr.id, newPart.family }) or {}
    local fitted = {}
    for _, r in ipairs(rows) do fitted[#fitted + 1] = { assetId = r.asset_id, family = r.family, tier = r.tier } end
    local old = NM.displaced(fitted, newPart)
    if old then
        MySQL.update.await("UPDATE component_asset SET location_kind = 'npc_storage' WHERE asset_id = ? AND owner_principal_id = ?", { old.assetId, pr.id })
    end
    return old
end

--- An NPC fits a part it already owns (one it got on the Exchange) when it serves their car: the part goes from storage
--- to fitted, its area develops by `devValue`, and the part it displaces goes to storage. Returns levels gained, or nil.
function PaddockMarkets.fitOwned(kind, id, part)
    local pr = principalOf(kind, id)
    if not pr or not pr.car or not part then return nil end
    local area = NM.FAMILY_AREA[part.family or ""]
    local allowed = NM.TIER_PARTS[pr.tier] or NM.TIER_PARTS.street
    if not area or not allowed[part.tier or ""] then return nil end
    MySQL.update.await([[UPDATE component_asset SET location_kind = 'npc_fitted' WHERE asset_id = ? AND owner_principal_kind = ?
        AND owner_principal_id = ? AND location_kind = 'npc_storage']], { part.assetId, kind, id })
    local _, gained = Car.invest(pr.car, area, NM.devValue(part.price, part.tier))
    mark(pr)
    retireDisplaced(pr, { assetId = part.assetId, family = part.family, tier = part.tier })
    return gained or 0
end

--- An NPC buys and fits a part for `area`, spending at most `budget`. Returns the part bought (with `devValue`) or
--- nil and a reason. The development the part brings is applied to the NPC's car here.
function PaddockMarkets.buyPart(kind, id, area, budget, t)
    if not set("npcMarketsEnabled", true) then return nil, "disabled" end
    local pr = principalOf(kind, id)
    if not pr or not pr.car then return nil, "no_principal" end
    budget = math.min(math.floor(budget or 0), cashOf(pr))
    if budget <= 0 then return nil, "no_money" end
    local list = offers(area, budget)
    local candidates = {}
    for _, o in ipairs(list) do if marketAllows(o.marketId, t) then candidates[#candidates + 1] = o end end
    local o = NM.choose(candidates, area, budget, pr.tier, t, set("npcExclusivitySec", 1200))
    if not o then return nil, "nothing_suitable" end
    local bought, why = purchasePart(pr, o, t)
    if not bought then PaddockMarkets.stats.refused = PaddockMarkets.stats.refused + 1 return nil, why end
    local _, m = marketAllows(o.marketId, t)
    m.n = m.n + 1
    PaddockMarkets.stats.parts = PaddockMarkets.stats.parts + 1
    bought.devValue = NM.devValue(o.price, o.tier)
    local _, gained = Car.invest(pr.car, area, bought.devValue)
    if pr.kind == "person" then PaddockStore.markPerson(pr.id) end
    local old = retireDisplaced(pr, o)
    log("%s %s bought %s %s (%s) at %s for %d: %s +%d level(s)%s", pr.kind, pr.id, o.tier, o.family, o.assetId, o.marketId,
        o.price, area, gained or 0, old and (", old " .. old.tier .. " part to storage") or "")
    return bought
end

-- -------------------------------------------------------------------------------------------------------- vehicles

--- An independent buys a street car off a vehicle market (Muscle / Sport / Tech, prestige 2 or less -- the street
--- band). Their racing car is levels (`paddock.car`); a better machine lifts every area toward its prestige. The
--- machine is theirs: `vehicle_asset.owner_principal` ('person', id), `ncm_driver_id` stays NULL.
function PaddockMarkets.buyVehicle(personId, budget, t)
    if not set("npcMarketsEnabled", true) then return nil, "disabled" end
    local pr = principalOf("person", personId)
    if not pr or not pr.car then return nil, "no_principal" end
    budget = math.min(math.floor(budget or 0), cashOf(pr))
    if budget <= 0 then return nil, "no_money" end
    local Catalogue = NcmCore.get("data.vehicle_catalogue")
    local band = { Muscle = true, Sport = true, Tech = true }
    local rows = MySQL.query.await([[SELECT mi.market_id, mi.asset_id, mi.price, mi.listed_at, a.vehicle_key
        FROM market_inventory mi JOIN vehicle_asset a ON a.asset_id = mi.asset_id
        WHERE mi.state = 'available' AND a.server_id = ? AND mi.price <= ? AND mi.listed_at <= ?
        ORDER BY mi.price DESC, mi.listed_at LIMIT 30]], { U.sid(), budget, t - set("npcExclusivitySec", 1200) }) or {}
    local pick, entry
    for _, r in ipairs(rows) do
        local e = r.vehicle_key and Catalogue.byKey(r.vehicle_key)
        if e and band[e.category or ""] and (tonumber(e.prestige) or 9) <= 2 and marketAllows(r.market_id, t) then pick, entry = r, e break end
    end
    if not pick then return nil, "nothing_suitable" end
    local key = NM.principal("person", personId)
    local idem = ("npc_vehicle:%s:%s"):format(U.sid(), pick.asset_id)
    local guard = [[mi.market_id = ? AND mi.asset_id = ? AND mi.state = 'sold' AND mi.sold_to_principal = ? AND mi.sold_at = ?]]
    local gv = { pick.market_id, pick.asset_id, key, t }
    local function with(vals) local out = {} for _, v in ipairs(vals) do out[#out + 1] = v end for _, v in ipairs(gv) do out[#out + 1] = v end return out end
    local tx = {
        { query = [[UPDATE market_inventory SET state = 'sold', sold_at = ?, sold_to_principal = ?
            WHERE market_id = ? AND asset_id = ? AND state = 'available']], values = { t, key, pick.market_id, pick.asset_id } },
        { query = [[UPDATE vehicle_asset a JOIN market_inventory mi ON mi.asset_id = a.asset_id
            SET a.owner_principal_kind = 'person', a.owner_principal_id = ?, a.acquired_via = 'purchase', a.acquired_at = ?
            WHERE a.ncm_driver_id IS NULL AND ]] .. guard, values = with({ personId, t }) },
        { query = [[INSERT IGNORE INTO vehicle_asset_transfer (transfer_id, idem_key, server_id, asset_id, from_driver_id, to_driver_id, kind, market_id, amount, occurred_at)
            SELECT ?, ?, ?, mi.asset_id, NULL, NULL, 'npc_purchase', mi.market_id, mi.price, ? FROM market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), idem, U.sid(), t }) },
        { query = [[UPDATE paddock_person p JOIN market_inventory mi ON ]] .. guard .. [[ SET p.cash = p.cash - mi.price
            WHERE p.server_id = ? AND p.person_id = ?]], values = { pick.market_id, pick.asset_id, key, t, U.sid(), personId } },
        { query = [[INSERT IGNORE INTO npc_money (entry_id, server_id, principal_kind, principal_id, amount, kind, ref, idem_key, created_at)
            SELECT ?, ?, 'person', ?, -mi.price, 'vehicle_purchase', mi.asset_id, ?, ? FROM market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), U.sid(), personId, idem, t }) },
    }
    local ok, err = PaddockMarkets.atomic(tx)
    if not ok then return nil, "transaction_failed: " .. tostring(err) end
    local owner = MySQL.scalar.await("SELECT owner_principal_id FROM vehicle_asset WHERE asset_id = ?", { pick.asset_id })
    if owner ~= personId then PaddockMarkets.stats.lost = PaddockMarkets.stats.lost + 1 return nil, "taken" end
    local _, m = marketAllows(pick.market_id, t)
    m.n = m.n + 1
    pr.obj.cash = cashOf(pr) - (tonumber(pick.price) or 0)
    local floor = math.min(Car.MAX_LEVEL, 2 + (tonumber(entry.prestige) or 1))
    for _, a in ipairs(Car.AREAS) do if (pr.car[a] or 1) < floor then pr.car[a] = floor end end
    pr.obj.evidence = pr.obj.evidence or {}
    pr.obj.evidence.vehicleAssetId = pick.asset_id
    PaddockStore.markPerson(personId)
    PaddockMarkets.stats.vehicles = PaddockMarkets.stats.vehicles + 1
    log("person %s bought a %s (%s) at %s for %d", personId, tostring(entry.displayName or pick.vehicle_key), pick.asset_id, pick.market_id, pick.price)
    return pick
end

-- ---------------------------------------------------------------------------------------------------- independents

--- Seed an independent's purse once (they arrive with a little money of their own).
local function seedCash(p)
    p.evidence = p.evidence or {}
    if p.evidence.cashSeeded then return end
    p.evidence.cashSeeded = true
    local u = NcmCore.get("paddock.attendance").draw(PaddockStore.world.seed, "indie-cash", p.id)
    p.cash = (tonumber(p.cash) or 0) + 1500 + math.floor(u * 4500)
    PaddockStore.markPerson(p.id)
end
PaddockMarkets.seedCash = seedCash

local shopCursor = 0
--- A shopping pass: a few independents with money look for a part for their weakest area.
function PaddockMarkets.shop(t)
    if not set("npcMarketsEnabled", true) then return end
    local w = PaddockStore.world
    local indies = {}
    for _, pid in ipairs(w.personOrder) do
        local p = w.people[pid]
        if p.role == "driver" and p.state == "active" and p.leagueId and not p.orgId and p.car then indies[#indies + 1] = p end
    end
    if #indies == 0 then return end
    local y = U.yielder(4)
    for _ = 1, math.min(#indies, set("npcShoppersPerPass", 4)) do
        shopCursor = shopCursor % #indies + 1
        local p = indies[shopCursor]
        seedCash(p)
        local cash = tonumber(p.cash) or 0
        local car = nil
        -- a flush independent in a tired car looks at cars first
        if cash >= set("npcVehicleMinCash", 9000) and Car.performance(p.car) < 45 then
            car = PaddockMarkets.buyVehicle(p.id, math.floor(cash * 0.8), t)
        end
        cash = tonumber(p.cash) or 0
        if not car and cash >= set("npcShopMinCash", 800) then
            for _, need in ipairs(NM.neediest(p.car)) do
                local got = PaddockMarkets.buyPart("person", p.id, need.area, math.floor(cash * 0.6), t)
                if got then break end
            end
        end
        y()
    end
end

function PaddockMarkets.start()
    CreateThread(function()
        Wait(30000)
        while true do
            if PaddockSettings.get("paddockEnabled", true) and PaddockWorld.ready then
                local ok, err = pcall(PaddockMarkets.shop, U.now())
                if not ok then log("shop FAILED: %s", tostring(err)) end
            end
            Wait(set("npcShopEverySec", 300) * 1000)
        end
    end)
end
