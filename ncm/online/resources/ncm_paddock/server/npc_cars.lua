-- ncm_paddock / server / npc_cars -- every Paddock racer owns a real car (L298; audit L297, KB-313).
--
-- Owner, 2026-10-02: "If Cesar buys sport brakes, do those brakes enter Cesar's inventory, get installed on a
-- specific car, alter that car's drive/brake/grip/etc. characteristics, and then follow that exact car into
-- physical racing?" -- now yes, link by link:
--
--   the car      a `vehicle_asset` owned by the NPC (an independent's own; a team's, one per driver, assigned through
--                `paddock_person.race_car_id`), with the SAME eleven-family factory configuration a player's car has
--                (`machine_configuration`, `component_asset` 'installed'). Minted here as Paddock stock (origin
--                'paddock_genesis'): it consumes no shelf stock and no production serials.
--   installing   a bought part goes onto THAT car as a new configuration revision; the part it replaces goes to the
--                owner's storage (the Exchange can sell it).
--   the levels   the sim's four development levels are DERIVED from the car (`economy.npc_garage.levels`): model,
--                installed parts, their wear, a bounded workshop tune -- never free-floating eddies again.
--   the racer    the bubble spawns this car's model, in the Pace performance variant its parts compose to.
--   wear         every race's distance goes onto the car's odometer and its installed parts' exposure; worn parts
--                are serviced or replaced through the shopping pass (markets.lua), on the same `parts.wear` model.
--
-- A car is created lazily (the garage pass, a few a tick, so the boot never mints a thousand cars in one slice) and
-- cached; every write invalidates its cache entry.
PaddockCars = { cache = {}, stats = { minted = 0, migrated = 0, installed = 0, serviced = 0, exposure = 0 } }

local U = PaddockUtil
local log = U.logger("cars")
local G = NcmCore.get("economy.npc_garage")
local Cat = NcmCore.get("parts.catalogue")
local Vehicles = NcmCore.get("data.vehicle_catalogue")
local Season = NcmCore.get("paddock.season")
local Wear = NcmCore.get("parts.wear")
local ids = NcmCore.get("vocabulary.ids")
local Gearbox = NcmCore.get("machine.gearbox")
local function set(k, d) return PaddockSettings.get(k, d) end
local function rng() return math.random() end

local function atomic(tx)
    for k, st in ipairs(tx) do
        local bad = U.checkStatement(st, k)
        if bad then return false, bad end
    end
    local called, ok, err = pcall(MySQL.transaction.await, tx)
    if not called then return false, tostring(ok) end
    return ok == true, err
end
PaddockCars.atomic = atomic

--- Who owns a racer's car: a team driver's team, else the person.
local function ownerOf(p)
    if p.orgId and PaddockStore.world.orgs[p.orgId] then return "org", p.orgId end
    return "person", p.id
end
PaddockCars.ownerOf = ownerOf

local function bandOf(p)
    local tier = "street"
    local org = p.orgId and PaddockStore.world.orgs[p.orgId]
    if org then tier = org.tier end
    return (Season.TIERS[tier] or {}).band or {}, tier
end

-- ---------------------------------------------------------------------------------------------------------- load

--- The car as the Paddock knows it: { assetId, vehicleKey, record, prestige, ownerKind, ownerId, parts = { { assetId,
--- designId, family, tier, effect, exposure_m, services, wear, state } }, levels, variant, value }. nil if none.
function PaddockCars.load(assetId)
    if not assetId or assetId == "" then return nil end
    local c = PaddockCars.cache[assetId]
    if c then return c end
    local v = MySQL.single.await([[SELECT asset_id, vehicle_key, record, owner_principal_kind, owner_principal_id, odometer_m, lifecycle
        FROM vehicle_asset WHERE asset_id = ? AND server_id = ?]], { assetId, U.sid() })
    if not v or v.lifecycle ~= "active" then return nil end
    local entry = Vehicles.byKey(v.vehicle_key)
    local rows = MySQL.query.await([[SELECT a.asset_id, a.design_id, a.exposure_m, d.family, d.tier, d.effect, d.price
        FROM machine_configuration_current cc JOIN machine_configuration_item i ON i.configuration_id = cc.configuration_id
        JOIN component_asset a ON a.asset_id = i.component_asset_id JOIN component_design d ON d.design_id = a.design_id
        WHERE cc.machine_asset_id = ? GROUP BY a.asset_id]], { assetId }) or {}
    local parts, idsList = {}, {}
    for _, r in ipairs(rows) do
        parts[#parts + 1] = { assetId = r.asset_id, asset_id = r.asset_id, designId = r.design_id, family = r.family, tier = r.tier,
            effect = tonumber(r.effect) or 1, exposure_m = tonumber(r.exposure_m) or 0, price = tonumber(r.price) or 0, services = {} }
        idsList[#idsList + 1] = r.asset_id
    end
    if #idsList > 0 then
        local marks = {}
        for i = 1, #idsList do marks[i] = "?" end
        local srows = MySQL.query.await(("SELECT component_asset_id, condition_id, relief_m FROM component_service WHERE component_asset_id IN (%s)")
            :format(table.concat(marks, ",")), idsList) or {}
        local byId = {}
        for _, p in ipairs(parts) do byId[p.assetId] = p end
        for _, s in ipairs(srows) do
            local p = byId[s.component_asset_id]
            if p then p.services[#p.services + 1] = { condition_id = s.condition_id, relief_m = tonumber(s.relief_m) or 0 } end
        end
    end
    for _, p in ipairs(parts) do
        p.state = Wear.evaluate(p, p.services)
        p.wear = G.wearFactor(p, p.services)
    end
    local prestige = entry and tonumber(entry.prestige) or 1
    c = { assetId = assetId, vehicleKey = v.vehicle_key, record = v.record, prestige = prestige, odometerM = tonumber(v.odometer_m) or 0,
        ownerKind = v.owner_principal_kind, ownerId = v.owner_principal_id, parts = parts,
        value = 8000 * prestige }
    c.variant = G.variant(parts)
    PaddockCars.cache[assetId] = c
    return c
end

--- The derived levels and racer variant for a car (and the person's tune), written onto the person.
function PaddockCars.derive(p, c)
    c = c or PaddockCars.load(p.raceCarId)
    if not c then return nil end
    local tune = (p.car and p.car.tune) or nil
    local car = G.levels(c.prestige, c.parts, tune)
    c.levels, c.variant = car, G.variant(c.parts)
    p.car = car
    PaddockStore.markPerson(p.id)
    return car
end

function PaddockCars.invalidate(assetId) if assetId then PaddockCars.cache[assetId] = nil end end

-- ---------------------------------------------------------------------------------------------------------- mint

--- Statements that create a racer's car and its factory configuration, owned by (kind, id).
local function mintStatements(model, kind, id, t)
    local assetId = ids.uuid4(rng)
    local entry = Vehicles.byKey(model.vehicleKey)
    -- L306: an NPC's car is born with a factory gearbox too (it drives the model record until AI can drive a clone)
    local gb = Gearbox.factoryRoll(assetId, model.vehicleKey, entry and entry.category)
    local tx = {
        { query = [[INSERT INTO vehicle_asset (asset_id, server_id, ncm_driver_id, vehicle_key, record, class, acquired_via, acquired_at,
            origin, produced_at, owner_principal_kind, owner_principal_id, gearbox_kind, gearbox_spec, gearbox_source, gearbox_at)
            VALUES (?, ?, NULL, ?, ?, ?, 'grant', ?, 'paddock_genesis', ?, ?, ?, ?, ?, ?, ?)]],
          values = { assetId, U.sid(), model.vehicleKey, model.record, (entry and entry.category) or "Sport", t, t, kind, id,
                     gb.kind, gb.spec, gb.source, t } },
        { query = [[INSERT IGNORE INTO vehicle_asset_transfer (transfer_id, idem_key, server_id, asset_id, from_driver_id, to_driver_id, kind,
            market_id, amount, occurred_at, to_principal, reason) VALUES (?, ?, ?, ?, NULL, NULL, 'paddock_genesis', NULL, 0, ?, ?, ?)]],
          values = { ids.uuid4(rng), "paddock_genesis:" .. U.sid() .. ":" .. assetId, U.sid(), assetId, t, kind .. ":" .. id, G.REASON.FIRST_CAR } },
    }
    local configId = ids.uuid4(rng)
    tx[#tx + 1] = { query = [[INSERT INTO machine_configuration (configuration_id, machine_asset_id, revision, created_at) VALUES (?, ?, 1, ?)]],
        values = { configId, assetId, t } }
    for _, family in ipairs(Cat.FAMILIES) do
        local d = Cat.factoryDesign(model.vehicleKey, family)
        if d then
            local aid = ids.uuid4(rng)
            tx[#tx + 1] = { query = [[INSERT INTO component_asset (asset_id, server_id, design_id, ncm_driver_id, manufacturer_key, location_kind,
                machine_asset_id, factory_original, acquired_via, acquired_at, exposure_m, created_at, owner_principal_kind, owner_principal_id)
                VALUES (?, ?, ?, NULL, 'factory', 'installed', ?, 1, 'factory', ?, 0, ?, ?, ?)]],
              values = { aid, U.sid(), d.designId, assetId, t, t, kind, id } }
            for _, interfaceId in ipairs(d.positions) do
                tx[#tx + 1] = { query = "INSERT INTO machine_configuration_item (configuration_id, interface_id, component_asset_id) VALUES (?, ?, ?)",
                    values = { configId, interfaceId, aid } }
            end
        end
    end
    tx[#tx + 1] = { query = "INSERT INTO machine_configuration_current (machine_asset_id, configuration_id) VALUES (?, ?)", values = { assetId, configId } }
    return tx, assetId
end
PaddockCars.mintStatements = mintStatements

--- Make sure a racer has a car (minting one if needed). Returns the loaded car or nil, reason.
function PaddockCars.ensure(p, t)
    if p.raceCarId then
        local c = PaddockCars.load(p.raceCarId)
        if c then return c end
        p.raceCarId = nil
    end
    local kind, id = ownerOf(p)
    local band = bandOf(p)
    -- a team driver takes the team's free car first (one a former driver left behind), before a new one is minted
    if kind == "org" then
        local taken = {}
        for _, q in pairs(PaddockStore.world.people) do if q.raceCarId then taken[q.raceCarId] = true end end
        local rows = MySQL.query.await([[SELECT asset_id FROM vehicle_asset WHERE server_id = ? AND owner_principal_kind = 'org'
            AND owner_principal_id = ? AND lifecycle = 'active' ORDER BY acquired_at]], { U.sid(), id }) or {}
        for _, r in ipairs(rows) do
            if not taken[r.asset_id] then
                p.raceCarId = r.asset_id
                PaddockStore.markPerson(p.id)
                local c = PaddockCars.load(r.asset_id)
                PaddockCars.derive(p, c)
                log("%s takes %s's free car %s", p.id, id, r.asset_id:sub(1, 8))
                return c
            end
        end
    end
    -- a team's cars share one model; an independent's is their own
    local model = G.startingModel(band, PaddockStore.world.seed, kind, kind == "org" and id or p.id)
    if not model then return nil, "no_model" end
    local tx, assetId = mintStatements(model, kind, id, t or U.now())
    local ok, err = atomic(tx)
    if not ok then log("mint FAILED for %s (%s): %s", p.id, model.vehicleKey, tostring(err)) return nil, "mint_failed" end
    p.raceCarId = assetId
    PaddockStore.markPerson(p.id)
    PaddockCars.stats.minted = PaddockCars.stats.minted + 1
    -- an independent's parts bought before L298 were "fitted" to the person, on no car: install the best of each
    -- family on the new car (if it fits), the rest to storage
    if kind == "person" then pcall(PaddockCars.migrateLoose, p, assetId) end
    local c = PaddockCars.load(assetId)
    PaddockCars.derive(p, c)
    log("%s %s now races %s (%s, %s-owned)", p.id, tostring(p.display or ""), model.vehicleKey, assetId:sub(1, 8), kind)
    return c
end

-- ------------------------------------------------------------------------------------------------------ install

--- Install `part` ({ assetId, designId, family }) owned by (kind, id) on car `c`: a new configuration revision with the
--- part in its family's positions; the part it replaces to the owner's storage. Returns the replaced asset id or nil.
function PaddockCars.install(c, part, kind, id, t)
    local cur = MySQL.single.await("SELECT configuration_id FROM machine_configuration_current WHERE machine_asset_id = ?", { c.assetId })
    if not cur then return nil, "no_configuration" end
    local rev = tonumber(MySQL.scalar.await("SELECT MAX(revision) FROM machine_configuration WHERE machine_asset_id = ?", { c.assetId })) or 1
    local items = MySQL.query.await([[SELECT i.interface_id, i.component_asset_id, d.family FROM machine_configuration_item i
        JOIN component_asset a ON a.asset_id = i.component_asset_id JOIN component_design d ON d.design_id = a.design_id
        WHERE i.configuration_id = ?]], { cur.configuration_id }) or {}
    local configId = ids.uuid4(rng)
    local old
    local tx = { { query = "INSERT INTO machine_configuration (configuration_id, machine_asset_id, revision, created_at) VALUES (?, ?, ?, ?)",
        values = { configId, c.assetId, rev + 1, t } } }
    local d = Cat.byId(part.designId)
    local positions = (d and d.positions) or Cat.INTERFACES[part.family] or {}
    local wanted = {}
    for _, pos in ipairs(positions) do wanted[pos] = true end
    for _, it in ipairs(items) do
        if wanted[it.interface_id] or it.family == part.family then
            if it.component_asset_id ~= part.assetId then old = old or it.component_asset_id end
        else
            tx[#tx + 1] = { query = "INSERT INTO machine_configuration_item (configuration_id, interface_id, component_asset_id) VALUES (?, ?, ?)",
                values = { configId, it.interface_id, it.component_asset_id } }
        end
    end
    for _, pos in ipairs(positions) do
        tx[#tx + 1] = { query = "INSERT INTO machine_configuration_item (configuration_id, interface_id, component_asset_id) VALUES (?, ?, ?)",
            values = { configId, pos, part.assetId } }
    end
    tx[#tx + 1] = { query = "UPDATE machine_configuration_current SET configuration_id = ? WHERE machine_asset_id = ?", values = { configId, c.assetId } }
    tx[#tx + 1] = { query = [[UPDATE component_asset SET location_kind = 'installed', machine_asset_id = ? WHERE asset_id = ?
        AND owner_principal_kind = ? AND owner_principal_id = ?]], values = { c.assetId, part.assetId, kind, id } }
    if old then
        tx[#tx + 1] = { query = [[UPDATE component_asset SET location_kind = 'npc_storage', machine_asset_id = NULL,
            owner_principal_kind = ?, owner_principal_id = ? WHERE asset_id = ?]], values = { kind, id, old } }
    end
    local ok, err = atomic(tx)
    if not ok then return nil, "install_failed: " .. tostring(err) end
    PaddockCars.invalidate(c.assetId)
    PaddockCars.stats.installed = PaddockCars.stats.installed + 1
    return old or false
end

--- Before L298 a bought part was `npc_fitted` on no car. On a racer's first car: the best fitting one of each family is
--- installed; the rest go to storage.
function PaddockCars.migrateLoose(p, assetId)
    local rows = MySQL.query.await([[SELECT a.asset_id, a.design_id, d.family, d.effect FROM component_asset a
        JOIN component_design d ON d.design_id = a.design_id
        WHERE a.server_id = ? AND a.owner_principal_kind = 'person' AND a.owner_principal_id = ? AND a.location_kind = 'npc_fitted'
        ORDER BY d.effect DESC]], { U.sid(), p.id }) or {}
    if #rows == 0 then return 0 end
    local c = PaddockCars.load(assetId)
    local done, n = {}, 0
    for _, r in ipairs(rows) do
        if not done[r.family] and G.fits(r.design_id, c.vehicleKey) then
            done[r.family] = true
            local ok = PaddockCars.install(c, { assetId = r.asset_id, designId = r.design_id, family = r.family }, "person", p.id, U.now())
            if ok ~= nil then n = n + 1 end
            c = PaddockCars.load(assetId)
        end
    end
    MySQL.update.await([[UPDATE component_asset SET location_kind = 'npc_storage' WHERE server_id = ? AND owner_principal_kind = 'person'
        AND owner_principal_id = ? AND location_kind = 'npc_fitted']], { U.sid(), p.id })
    PaddockCars.stats.migrated = PaddockCars.stats.migrated + n
    log("%s: %d part(s) bought before L298 installed on their new car; the rest to storage", p.id, n)
    return n
end

-- ----------------------------------------------------------------------------------------------------- the race

--- A race's distance onto every racer's car: the odometer and every installed part's exposure (the wear clock).
function PaddockCars.raced(personIds, metres)
    metres = math.floor(tonumber(metres) or 0)
    if metres <= 0 then return 0 end
    local st = {}
    for _, pid in ipairs(personIds) do
        local p = PaddockStore.world.people[pid]
        if p and p.raceCarId then
            st[#st + 1] = { query = "UPDATE vehicle_asset SET odometer_m = odometer_m + ?, odometer_at = ? WHERE asset_id = ?",
                values = { metres, U.now(), p.raceCarId } }
            st[#st + 1] = { query = "UPDATE component_asset SET exposure_m = exposure_m + ? WHERE machine_asset_id = ? AND location_kind = 'installed'",
                values = { metres, p.raceCarId } }
            PaddockCars.invalidate(p.raceCarId)
        end
    end
    if #st == 0 then return 0 end
    local ok = U.transact(st)
    if ok then PaddockCars.stats.exposure = PaddockCars.stats.exposure + #st / 2 end
    return #st / 2
end

--- Service a worn part (the player path's history row, by an NPC principal). `quote` = parts.wear serviceQuote.
function PaddockCars.serviceStatements(part, quote, kind, id, t)
    return { query = [[INSERT INTO component_service (service_id, idem_key, server_id, component_asset_id, condition_id, at_exposure_m,
        by_driver_id, provider_kind, workmanship_json, relief_m, amount, occurred_at, by_principal_kind, by_principal_id)
        VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?)]],
        values = { ids.uuid4(rng), ("npc_service:%s:%s:%d"):format(U.sid(), part.assetId, t), U.sid(), part.assetId, quote.conditionId,
            math.floor(part.exposure_m or 0), quote.providerKind or "network_service", U.encode(quote.workmanship or {}) or "{}",
            quote.reliefM, quote.cost, t, kind, id } }
end

-- ----------------------------------------------------------------------------------------------------- the pass

--- The racers who need a car: active drivers in a team or a league.
local function racers()
    local w = PaddockStore.world
    local out = {}
    for _, pid in ipairs(w.personOrder) do
        local p = w.people[pid]
        if p.role == "driver" and p.state == "active" and (p.orgId or p.leagueId) then out[#out + 1] = p end
    end
    return out
end
PaddockCars.racers = racers

local cursor = 0
--- A few racers get their car each pass (and every car's levels are re-derived when it is loaded).
function PaddockCars.pass(t)
    if not set("npcCarsEnabled", true) then return end
    local list = racers()
    if #list == 0 then return end
    local y = U.yielder(2)
    local made = 0
    for _ = 1, math.min(#list, set("npcCarsPerPass", 6)) do
        cursor = cursor % #list + 1
        local p = list[cursor]
        if not p.raceCarId then
            local okE, c = pcall(PaddockCars.ensure, p, t)
            if okE and c then made = made + 1 end
        elseif not p.car or not p.car.tune then
            pcall(PaddockCars.derive, p)
        end
        y()
    end
    return made
end

function PaddockCars.start()
    CreateThread(function()
        Wait(20000)
        while true do
            if PaddockSettings.get("paddockEnabled", true) and PaddockWorld.ready then
                local ok, err = pcall(PaddockCars.pass, U.now())
                if not ok then log("pass FAILED: %s", tostring(err)) end
            end
            Wait(set("npcCarsPassSec", 10) * 1000)
        end
    end)
end
