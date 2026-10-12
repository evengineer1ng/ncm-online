-- ncm_paddock / server / markets -- NPCs in the markets (L249 step 4, IDEA-730; owner: "all markets need buyers").
--
-- L298 (audit L297): every Paddock racer owns a real car (npc_cars.lua), and a purchase is a step in looking after it:
--
--   * a racer's turn comes round every `npcShopIntervalSec` (persisted: a restart no longer sends the same
--     independents back to the shelves, KB-312); the car's GOALS decide what they do, most pressing first
--     (`economy.npc_garage.goals`): service a worn part, replace a worn-out one, or upgrade the weakest area;
--   * a part is bought only if it FITS the car's model (the catalogue's fitment contract, the player rule) and is a
--     strict upgrade over what is installed -- never a downgrade, never the same part again;
--   * it is installed on that car as a new configuration revision; the part it replaces goes to storage;
--   * an independent pays with their own money; a team driver's car is paid for by the team (teams now spend, KB-315);
--   * the money row and the transfer carry the reason and the goal.
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
local Garage = NcmCore.get("economy.npc_garage")
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

--- The statements of one NPC part purchase (exposed for tools/npc-sql-gen.lua, which runs them against MariaDB
--- inside a rolled-back transaction). L298: the part goes to the buyer's STORAGE here and is installed on their car
--- in its own transaction (`PaddockCars.install`); the money row and the transfer carry the reason and the goal.
function PaddockMarkets.partPurchaseTx(pr, o, t, reason, goal)
    local key = NM.principal(pr.kind, pr.id)
    local idem = ("npc_part:%s:%s"):format(U.sid(), o.assetId)
    local guard = [[mi.market_id = ? AND mi.asset_id = ? AND mi.state = 'sold' AND mi.sold_to_principal = ? AND mi.sold_at = ?]]
    local gv = { o.marketId, o.assetId, key, t }
    local function with(vals) local out = {} for _, v in ipairs(vals) do out[#out + 1] = v end for _, v in ipairs(gv) do out[#out + 1] = v end return out end
    local tx = {
        { query = [[UPDATE component_market_inventory SET state = 'sold', sold_at = ?, sold_to_principal = ?
            WHERE market_id = ? AND asset_id = ? AND state = 'available']], values = { t, key, o.marketId, o.assetId } },
        { query = [[UPDATE component_asset a JOIN component_market_inventory mi ON mi.asset_id = a.asset_id
            SET a.owner_principal_kind = ?, a.owner_principal_id = ?, a.location_kind = 'npc_storage', a.machine_asset_id = NULL,
                a.acquired_via = 'purchase', a.acquired_at = ?
            WHERE a.ncm_driver_id IS NULL AND ]] .. guard, values = with({ pr.kind, pr.id, t }) },
        { query = [[INSERT IGNORE INTO component_asset_transfer (transfer_id, idem_key, server_id, asset_id, kind, market_id, amount, occurred_at,
            to_principal, reason)
            SELECT ?, ?, ?, mi.asset_id, 'npc_purchase', mi.market_id, mi.price, ?, ?, ? FROM component_market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), idem, U.sid(), t, key, reason or "" }) },
        { query = ([[UPDATE %s p JOIN component_market_inventory mi ON ]] .. guard .. [[ SET p.cash = p.cash - CAST(mi.price AS SIGNED)
            WHERE p.server_id = ? AND p.%s = ?]]):format(moneyTable(pr), moneyKey(pr)), values = { o.marketId, o.assetId, key, t, U.sid(), pr.id } },
        { query = [[INSERT IGNORE INTO npc_money (entry_id, server_id, principal_kind, principal_id, amount, kind, ref, idem_key, created_at, reason, goal)
            SELECT ?, ?, ?, ?, -mi.price, 'part_purchase', mi.asset_id, ?, ?, NULLIF(?, ''), NULLIF(?, '') FROM component_market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), U.sid(), pr.kind, pr.id, idem, t, reason or "", goal or "" }) },
    }
    return tx
end

--- The guarded purchase of one shelf part by an NPC. Returns the offer on success, nil and a reason otherwise.
local function purchasePart(pr, o, t, reason, goal)
    -- KB-328: the SQL below checks the DATABASE's cash, but `seedCash` (and every purse) credits memory and only marks
    -- the person for the next flush -- so a newly seeded independent bought against an unsaved balance, `cash - price`
    -- went below zero in unsigned arithmetic, and MariaDB raised SQL 1690. Save first (as the Exchange's settle does),
    -- then compare: any difference left is real drift, and the database wins.
    PaddockStore.flush()
    if coroutine.isyieldable() then Wait(0) end
    local okC, dbCash = pcall(MySQL.scalar.await, ("SELECT cash FROM %s WHERE server_id = ? AND %s = ?"):format(moneyTable(pr), moneyKey(pr)),
        { U.sid(), pr.id })
    dbCash = okC and tonumber(dbCash) or nil
    if dbCash and dbCash ~= cashOf(pr) then
        log("cash drift %s %s: memory %d, database %d -- memory follows the database", pr.kind, pr.id, cashOf(pr), dbCash)
        pr.obj.cash = dbCash
        mark(pr)
    end
    if dbCash and dbCash < (tonumber(o.price) or 0) then return nil, "unaffordable" end
    local tx = PaddockMarkets.partPurchaseTx(pr, o, t, reason, goal)
    -- ONE transaction (never U.transact, which chunks): the claim and the money move together or not at all
    local ok, err = PaddockMarkets.atomic(tx)
    if not ok then return nil, "transaction_failed: " .. tostring(err) end
    local owner = MySQL.scalar.await("SELECT owner_principal_id FROM component_asset WHERE asset_id = ?", { o.assetId })
    if owner ~= pr.id then PaddockMarkets.stats.lost = PaddockMarkets.stats.lost + 1 return nil, "taken" end
    pr.obj.cash = cashOf(pr) - o.price
    mark(pr)
    return o
end

--- One money movement of an NPC outside a market purchase (a service, a fee, a purse, a scrap value), ledgered.
function PaddockMarkets.moneyStatements(kind, id, amount, what, ref, t, reason, goal)
    local tbl = kind == "org" and "paddock_org" or "paddock_person"
    local col = kind == "org" and "org_id" or "person_id"
    return {
        { query = ("UPDATE %s SET cash = cash + ? WHERE server_id = ? AND %s = ?"):format(tbl, col), values = { amount, U.sid(), id } },
        { query = [[INSERT IGNORE INTO npc_money (entry_id, server_id, principal_kind, principal_id, amount, kind, ref, idem_key, created_at, reason, goal)
            VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, NULLIF(?, ''), NULLIF(?, ''))]],
          values = { ids.uuid4(rng), U.sid(), kind, id, amount, what, ref or "", ("%s:%s:%s:%s:%d"):format(what, kind, id, tostring(ref or ""), t), t,
            reason or "", goal or "" } },
    }
end

-- --------------------------------------------------------------------------------------------- one car, one goal

--- The shelf parts of `family` that fit `vehicleKey`, cost at most `budget`, and beat `installedEffect`.
local function upgradeOffers(families, vehicleKey, budget, installedEffect, tierAllowed, t)
    local marks, vals = {}, { U.sid() }
    for i, f in ipairs(families) do marks[i] = "?"; vals[#vals + 1] = f end
    vals[#vals + 1] = math.floor(budget)
    vals[#vals + 1] = t - set("npcExclusivitySec", 1200)
    local rows = MySQL.query.await(([[SELECT mi.market_id, mi.asset_id, mi.price, mi.listed_at, d.family, d.tier, d.design_id, d.effect
        FROM component_market_inventory mi JOIN component_asset a ON a.asset_id = mi.asset_id
        JOIN component_design d ON d.design_id = a.design_id
        WHERE mi.state = 'available' AND a.server_id = ? AND d.family IN (%s) AND mi.price <= ? AND mi.listed_at <= ?
        ORDER BY d.effect DESC, mi.price, mi.listed_at LIMIT 60]]):format(table.concat(marks, ",")), vals) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local o = { marketId = r.market_id, assetId = r.asset_id, price = tonumber(r.price), listedAt = tonumber(r.listed_at),
            family = r.family, tier = r.tier, designId = r.design_id, effect = tonumber(r.effect) or 1 }
        if (not tierAllowed or tierAllowed[o.tier]) and Garage.fits(o.designId, vehicleKey)
            and Garage.isUpgrade(installedEffect[o.family] or 1, o) and marketAllows(o.marketId, t) then
            out[#out + 1] = o
        end
    end
    return out
end

--- Buy and install one part for a car, for a goal. Returns the part or nil, why.
local function buyFor(pr, p, c, families, budget, reason, goal, t)
    local installedEffect = {}
    for _, part in ipairs(c.parts) do
        local eff = (tonumber(part.effect) or 1) * (tonumber(part.wear) or 1)
        installedEffect[part.family] = math.min(installedEffect[part.family] or math.huge, eff)
    end
    budget = math.min(math.floor(budget or 0), cashOf(pr))
    if budget <= 0 then return nil, "no_money" end
    local list = upgradeOffers(families, c.vehicleKey, budget, installedEffect, NM.TIER_PARTS[pr.tier] or NM.TIER_PARTS.street, t)
    local o = list[1]
    if not o then return nil, "nothing_suitable" end
    local bought, why = purchasePart(pr, o, t, reason, goal)
    if not bought then PaddockMarkets.stats.refused = PaddockMarkets.stats.refused + 1 return nil, why end
    local _, m = marketAllows(o.marketId, t)
    m.n = m.n + 1
    PaddockMarkets.stats.parts = PaddockMarkets.stats.parts + 1
    local old = PaddockCars.install(c, { assetId = o.assetId, designId = o.designId, family = o.family }, pr.kind, pr.id, t)
    local before = p.car and p.car[NM.FAMILY_AREA[o.family] or ""] or 0
    local car = PaddockCars.derive(p, PaddockCars.load(c.assetId))
    log("%s %s (%s) bought %s %s %s at %s for %d (%s: %s) -> installed on %s %s; %s %.1f -> %.1f%s", pr.kind, pr.id, p.id, o.tier, o.family,
        o.assetId:sub(1, 8), o.marketId, o.price, reason, goal or "", c.vehicleKey, c.assetId:sub(1, 8), NM.FAMILY_AREA[o.family] or "?",
        before, car and car[NM.FAMILY_AREA[o.family] or ""] or 0, old and (", old part " .. old:sub(1, 8) .. " to storage") or "")
    return o
end

--- Service a worn part on a car. Returns true or nil, why.
local function service(pr, p, c, goal, t)
    local part
    for _, x in ipairs(c.parts) do if x.assetId == goal.assetId then part = x end end
    if not part or not goal.quote then return nil, "no_quote" end
    if cashOf(pr) < goal.quote.cost then return nil, "no_money" end
    local tx = { PaddockCars.serviceStatements(part, goal.quote, pr.kind, pr.id, t) }
    for _, st in ipairs(PaddockMarkets.moneyStatements(pr.kind, pr.id, -goal.quote.cost, "service", part.assetId, t, Garage.REASON.SERVICE,
        part.family .. ":" .. tostring(goal.quote.conditionId))) do tx[#tx + 1] = st end
    local ok, err = PaddockMarkets.atomic(tx)
    if not ok then return nil, "service_failed: " .. tostring(err) end
    pr.obj.cash = cashOf(pr) - goal.quote.cost
    mark(pr)
    PaddockCars.invalidate(c.assetId)
    PaddockCars.derive(p, PaddockCars.load(c.assetId))
    PaddockCars.stats.serviced = PaddockCars.stats.serviced + 1
    log("%s %s (%s) serviced %s %s on %s for %d (%s)", pr.kind, pr.id, p.id, part.family, part.assetId:sub(1, 8), c.vehicleKey,
        goal.quote.cost, goal.quote.conditionId)
    return true
end

-- ------------------------------------------------------------------------------------------------ a better car
local Production = NcmCore.get("economy.production")
local Vehicles = NcmCore.get("data.vehicle_catalogue")
local Season = NcmCore.get("paddock.season")

--- The old car leaves the racer's garage -- but never back to a manufacturer (2026-10-12, owner: NPC resales "should
--- never have been able to sell back to manufacturer to begin with"). It stays its owner's as a SPARE (lifecycle
--- 'npc_spare', its parts with it) and the Exchange pass offers it to players and NPCs at a used price
--- (`economy.exchange_posts.usedAsk`); the owner is paid when it sells. Returns 0: nothing is paid now.
local function tradeIn(pr, old, t)
    local tx = {
        { query = [[UPDATE vehicle_asset SET lifecycle = 'npc_spare', lifecycle_at = ?, lifecycle_cause = 'npc_replaced' WHERE asset_id = ?]],
          values = { t, old.assetId } },
        { query = [[INSERT IGNORE INTO vehicle_asset_transfer (transfer_id, idem_key, server_id, asset_id, from_driver_id, to_driver_id, kind,
            market_id, amount, occurred_at, from_principal, reason) VALUES (?, ?, ?, ?, NULL, NULL, 'retired_spare', '', 0, ?, ?, 'replace_car')]],
          values = { ids.uuid4(rng), ("npc_spare:%s:%s:%d"):format(U.sid(), old.assetId, t), U.sid(), old.assetId, t, NM.principal(pr.kind, pr.id) } },
    }
    local ok, err = PaddockMarkets.atomic(tx)
    if not ok then log("retiring %s FAILED: %s", old.assetId:sub(1, 8), tostring(err)) return 0 end
    PaddockCars.invalidate(old.assetId)
    log("%s %s's old %s %s kept as a spare for the Exchange", pr.kind, pr.id, old.vehicleKey, old.assetId:sub(1, 8))
    return 0
end

--- An independent racer bought a used car on the Exchange (2026-10-12): it races it from now on, and the car it raced
--- becomes a spare the Exchange offers in turn. Returns true when adopted.
function PaddockMarkets.adoptCar(personId, assetId, t)
    local p = PaddockStore.world.people[personId]
    if not p or p.orgId then return false end
    local okU = MySQL.update.await([[UPDATE vehicle_asset SET lifecycle = 'active', lifecycle_at = ?, lifecycle_cause = 'exchange_bought'
        WHERE asset_id = ? AND owner_principal_kind = 'person' AND owner_principal_id = ?]], { t, assetId, personId })
    if (tonumber(okU) or 0) < 1 then return false end
    local old = p.raceCarId and PaddockCars.load(p.raceCarId) or nil
    p.raceCarId = assetId
    PaddockStore.markPerson(p.id)
    PaddockCars.invalidate(assetId)
    local c = PaddockCars.load(assetId)
    if c then PaddockCars.derive(p, c) end
    if old and old.assetId ~= assetId then tradeIn({ kind = "person", id = personId, obj = p }, old, t) end
    log("person %s now races %s bought on the Exchange%s", personId, assetId:sub(1, 8), old and (" (old " .. old.vehicleKey .. " to the Exchange)") or "")
    return true
end

--- A better car off a market shelf: a model of the racer's band of higher class than the one they race, affordable,
--- listed long enough for players to have had first claim. The aftermarket parts move across where they fit; the old
--- car is traded in. Returns the new car or nil, why.
function PaddockMarkets.replaceCar(pr, p, c, budget, t)
    if not set("npcMarketsEnabled", true) then return nil, "disabled" end
    local tier = (p.orgId and PaddockStore.world.orgs[p.orgId] and PaddockStore.world.orgs[p.orgId].tier) or "street"
    local band = (Season.TIERS[tier] or {}).band or {}
    if c.prestige >= (band.prestigeMax or 5) then return nil, "already_top_of_band" end
    budget = math.min(math.floor(budget or 0), cashOf(pr))
    if budget <= 0 then return nil, "no_money" end
    local classes = {}
    for _, cl in ipairs(band.classes or {}) do classes[cl] = true end
    local rows = MySQL.query.await([[SELECT mi.market_id, mi.asset_id, mi.price, a.vehicle_key, a.record FROM market_inventory mi
        JOIN vehicle_asset a ON a.asset_id = mi.asset_id
        WHERE mi.state = 'available' AND a.server_id = ? AND a.ncm_driver_id IS NULL AND a.owner_principal_id IS NULL
          AND mi.price <= ? AND mi.listed_at <= ? ORDER BY mi.price DESC LIMIT 40]],
        { U.sid(), budget, t - set("npcExclusivitySec", 1200) }) or {}
    local pick, entry
    for _, r in ipairs(rows) do
        local e = Vehicles.byKey(r.vehicle_key)
        local pres = e and tonumber(e.prestige) or 0
        if e and classes[e.category or ""] and pres > c.prestige and pres <= (band.prestigeMax or 5) and pres >= (band.prestigeMin or 0)
            and marketAllows(r.market_id, t) then pick, entry = r, e break end
    end
    if not pick then return nil, "nothing_suitable" end
    local key = NM.principal(pr.kind, pr.id)
    local idem = ("npc_vehicle:%s:%s"):format(U.sid(), pick.asset_id)
    local guard = [[mi.market_id = ? AND mi.asset_id = ? AND mi.state = 'sold' AND mi.sold_to_principal = ? AND mi.sold_at = ?]]
    local gv = { pick.market_id, pick.asset_id, key, t }
    local function with(vals) local out = {} for _, v in ipairs(vals) do out[#out + 1] = v end for _, v in ipairs(gv) do out[#out + 1] = v end return out end
    local tx = {
        { query = [[UPDATE market_inventory SET state = 'sold', sold_at = ?, sold_to_principal = ?
            WHERE market_id = ? AND asset_id = ? AND state = 'available']], values = { t, key, pick.market_id, pick.asset_id } },
        { query = [[UPDATE vehicle_asset a JOIN market_inventory mi ON mi.asset_id = a.asset_id
            SET a.owner_principal_kind = ?, a.owner_principal_id = ?, a.acquired_via = 'purchase', a.acquired_at = ?
            WHERE a.ncm_driver_id IS NULL AND ]] .. guard, values = with({ pr.kind, pr.id, t }) },
        { query = [[UPDATE component_asset a JOIN market_inventory mi ON mi.asset_id = a.machine_asset_id
            SET a.owner_principal_kind = ?, a.owner_principal_id = ? WHERE a.ncm_driver_id IS NULL AND ]] .. guard, values = with({ pr.kind, pr.id }) },
        { query = [[INSERT IGNORE INTO vehicle_asset_transfer (transfer_id, idem_key, server_id, asset_id, from_driver_id, to_driver_id, kind, market_id,
            amount, occurred_at, to_principal, reason)
            SELECT ?, ?, ?, mi.asset_id, NULL, NULL, 'npc_purchase', mi.market_id, mi.price, ?, ?, 'replace_car' FROM market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), idem, U.sid(), t, key }) },
        { query = ([[UPDATE %s p JOIN market_inventory mi ON ]] .. guard .. [[ SET p.cash = p.cash - CAST(mi.price AS SIGNED)
            WHERE p.server_id = ? AND p.%s = ?]]):format(moneyTable(pr), moneyKey(pr)), values = { pick.market_id, pick.asset_id, key, t, U.sid(), pr.id } },
        { query = [[INSERT IGNORE INTO npc_money (entry_id, server_id, principal_kind, principal_id, amount, kind, ref, idem_key, created_at, reason, goal)
            SELECT ?, ?, ?, ?, -mi.price, 'vehicle_purchase', mi.asset_id, ?, ?, 'replace_car', ? FROM market_inventory mi WHERE ]] .. guard,
          values = with({ ids.uuid4(rng), U.sid(), pr.kind, pr.id, idem, t, ("%s -> %s"):format(c.vehicleKey, pick.vehicle_key) }) },
    }
    local ok, err = PaddockMarkets.atomic(tx)
    if not ok then return nil, "transaction_failed: " .. tostring(err) end
    local owner = MySQL.scalar.await("SELECT owner_principal_id FROM vehicle_asset WHERE asset_id = ?", { pick.asset_id })
    if owner ~= pr.id then PaddockMarkets.stats.lost = PaddockMarkets.stats.lost + 1 return nil, "taken" end
    pr.obj.cash = cashOf(pr) - (tonumber(pick.price) or 0)
    mark(pr)
    local _, m = marketAllows(pick.market_id, t)
    m.n = m.n + 1
    PaddockMarkets.stats.vehicles = PaddockMarkets.stats.vehicles + 1
    -- the new car is the one they race; the old one's aftermarket parts come across where they fit
    local newCar = PaddockCars.load(pick.asset_id)
    if newCar then
        for _, part in ipairs(c.parts) do
            if part.tier ~= "factory" then
                if Garage.fits(part.designId, newCar.vehicleKey) then
                    PaddockCars.install(newCar, part, pr.kind, pr.id, t)
                    newCar = PaddockCars.load(pick.asset_id)
                else
                    MySQL.update.await([[UPDATE component_asset SET location_kind = 'npc_storage', machine_asset_id = NULL WHERE asset_id = ?]], { part.assetId })
                end
            end
        end
    end
    p.raceCarId = pick.asset_id
    PaddockStore.markPerson(p.id)
    tradeIn(pr, c, t)
    PaddockCars.derive(p, PaddockCars.load(pick.asset_id))
    log("%s %s (%s) bought a %s (%s) at %s for %d to replace their %s", pr.kind, pr.id, p.id, tostring(entry.displayName or pick.vehicle_key),
        pick.asset_id:sub(1, 8), pick.market_id, pick.price, c.vehicleKey)
    return pick
end

--- L305: what a team can put into a car. It was 4 % of cash -- EUR$1.5 k for a street team, 5.5 k regional, 22 k pro,
--- against 16-50 k cars -- and no team bought one in a day on Online with EUR$49.6 M banked. Now: cash above a runway of
--- `npcTeamRunwayDays` days of the team's wage bill, capped at `npcTeamCarShare` of cash.
function PaddockMarkets.teamCarBudget(pr)
    local cash = cashOf(pr)
    local wages = 0
    for _, pid in ipairs(PaddockStore.world.personOrder) do
        local q = PaddockStore.world.people[pid]
        if q.orgId == pr.id and q.state == "active" then wages = wages + (tonumber(q.wage) or 0) end
    end
    local spendable = cash - wages * set("npcTeamRunwayDays", 14)
    return math.max(0, math.floor(math.min(spendable, cash * set("npcTeamCarShare", 0.5))))
end

--- One racer's car gets one action, the most pressing affordable goal first. `budget` caps a purchase.
function PaddockMarkets.tend(pr, p, budget, t)
    local c = PaddockCars.ensure(p, t)
    if not c then return nil, "no_car" end
    local car = PaddockCars.derive(p, c) or p.car
    -- a racer flush enough looks at a better car first (an independent at `npcCarUpgradeMinCash`; a team when a car
    -- costs it a small share of its cash) -- the worn parts of the old one go with it
    local carBudget = pr.kind == "person" and (cashOf(pr) >= set("npcCarUpgradeMinCash", 12000) and math.floor(cashOf(pr) * 0.7) or 0)
        or PaddockMarkets.teamCarBudget(pr)
    if carBudget > 0 then
        local okR, newCar = pcall(PaddockMarkets.replaceCar, pr, p, c, carBudget, t)
        if okR and newCar then return Garage.REASON.CAR end
    end
    for _, goal in ipairs(Garage.goals(c.parts, car)) do
        if goal.kind == Garage.REASON.SERVICE then
            if service(pr, p, c, goal, t) then return goal.kind end
        elseif goal.kind == Garage.REASON.REPLACE then
            if buyFor(pr, p, c, { goal.family }, budget, goal.kind, goal.family .. " worn out", t) then return goal.kind end
        elseif goal.kind == Garage.REASON.UPGRADE then
            for _, need in ipairs(NM.neediest(car)) do
                if buyFor(pr, p, c, NM.AREA_FAMILIES[need.area] or {}, budget, goal.kind, need.area .. " at " .. tostring(need.level), t) then
                    return goal.kind
                end
            end
        end
    end
    return nil, "nothing_to_do"
end

--- A team's development decision for one area (life.lua `invest_dev`): a fitting upgrade for that area on one of its
--- drivers' cars. Returns what it spent.
function PaddockMarkets.tendArea(orgId, p, area, budget, t)
    local pr = principalOf("org", orgId)
    if not pr then return 0 end
    local c = PaddockCars.ensure(p, t)
    if not c then return 0 end
    local before = cashOf(pr)
    buyFor(pr, p, c, NM.AREA_FAMILIES[area] or {}, budget, Garage.REASON.UPGRADE, "team development: " .. area, t)
    return math.max(0, before - cashOf(pr))
end

--- Would this part go onto one of (kind, id)'s racers' cars -- does it fit the model and improve on what is installed?
--- (the Exchange asks before an NPC bids: an NPC buys what it can use, not what is cheap)
function PaddockMarkets.wouldFit(kind, id, part)
    if not part or not part.designId then return false end
    local w = PaddockStore.world
    for _, pid in ipairs(w.personOrder) do
        local p = w.people[pid]
        if p.raceCarId and ((kind == "person" and p.id == id) or (kind == "org" and p.orgId == id)) then
            local c = PaddockCars.load(p.raceCarId)
            local installed = 1
            for _, x in ipairs(c and c.parts or {}) do if x.family == part.family then installed = (x.effect or 1) * (x.wear or 1) end end
            if c and Garage.fits(part.designId, c.vehicleKey) and Garage.isUpgrade(installed, part) then return true end
        end
    end
    return false
end

--- A part an NPC got on the Exchange goes onto the first of their racers' cars it fits and improves.
function PaddockMarkets.fitOwned(kind, id, part)
    if not part or not part.assetId then return nil end
    local w = PaddockStore.world
    for _, pid in ipairs(w.personOrder) do
        local p = w.people[pid]
        local ok = p.raceCarId and ((kind == "person" and p.id == id) or (kind == "org" and p.orgId == id))
        if ok then
            local c = PaddockCars.load(p.raceCarId)
            local installed = 1
            for _, x in ipairs(c and c.parts or {}) do if x.family == part.family then installed = (x.effect or 1) * (x.wear or 1) end end
            if c and Garage.fits(part.designId, c.vehicleKey) and Garage.isUpgrade(installed, part) then
                PaddockCars.install(c, { assetId = part.assetId, designId = part.designId, family = part.family }, kind, id, U.now())
                PaddockCars.derive(p, PaddockCars.load(c.assetId))
                return p.id
            end
        end
    end
    return nil
end

-- ------------------------------------------------------------------------------------------------- the cadence

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

--- Racers whose turn it is: they last shopped at least `npcShopIntervalSec` ago (persisted -- a restart no longer
--- sends the same independents back to the shelves, KB-312), oldest first.
local function due(t)
    local w = PaddockStore.world
    local list = {}
    local gap = set("npcShopIntervalSec", 3 * 3600)
    for _, pid in ipairs(w.personOrder) do
        local p = w.people[pid]
        if p.role == "driver" and p.state == "active" and p.raceCarId and (p.orgId or p.leagueId)
            and t - (tonumber(p.lastShopAt) or 0) >= gap then
            list[#list + 1] = p
        end
    end
    table.sort(list, function(a, b)
        if (a.lastShopAt or 0) ~= (b.lastShopAt or 0) then return (a.lastShopAt or 0) < (b.lastShopAt or 0) end
        return a.id < b.id
    end)
    return list
end

--- A shopping pass: a few racers whose turn it is look after their car -- an independent with their own money, a team
--- driver's car with the team's (L298: teams now spend through the shelves, KB-315).
function PaddockMarkets.shop(t)
    if not set("npcMarketsEnabled", true) then return end
    local list = due(t)
    local y = U.yielder(2)
    for i = 1, math.min(#list, set("npcShoppersPerPass", 4)) do
        local p = list[i]
        local kind, id = PaddockCars.ownerOf(p)
        local pr = principalOf(kind, id)
        if pr then
            if kind == "person" then seedCash(p) end
            local cash = cashOf(pr)
            -- an independent spends at most 60 % of what they have; a team a share of its cash per car, capped
            local budget = kind == "person" and math.floor(cash * 0.6)
                or math.min(set("npcTeamCarBudget", 6000), math.floor(cash * 0.05))
            local okT, did, why = pcall(PaddockMarkets.tend, pr, p, budget, t)
            if not okT then log("tend %s FAILED: %s", p.id, tostring(did)) end
            p.lastShopAt = t
            PaddockStore.markPerson(p.id)
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
