-- ncm_league / server / provenance -- production ordinals: allocation, and the one-time backfill.
--
-- Three independent append-only sequences per world: NCM's whole production history, each manufacturer's, and
-- each model's. They are facts about the past, so nothing here ever recomputes, compacts or renumbers one.
NcmProvenance = {}

local Identity = NcmCore.get("data.vehicle_identity")
local Catalogue = NcmCore.get("data.vehicle_catalogue")
local ids = NcmCore.get("vocabulary.ids")
local hostRng = function() return math.random() end
local function now() return math.floor(Open77.time.unix()) end
local function serverId() return NcmCalendar.serverId() end
local function log(fmt, ...) print(("[ncm_league/provenance] " .. fmt):format(...)) end

local RESERVE_ATTEMPTS = 8

--- Take the next `n` numbers out of one sequence, atomically, and return the first of them.
---
--- **Not `SELECT MAX(x) + 1`.** Production mints whole batches and a console command can interleave with the
--- scheduler at any `await`, so two callers really can read the same value. This is an optimistic claim: move
--- the counter only if it is still where we saw it, stamp our nonce while doing so, then read the nonce back
--- to find out whether we were the one who moved it. Exactly the pattern the production tick claim uses, and
--- chosen for the same reason -- it never has to trust an affected-rows count, which varies by driver.
---
--- A loser retries against the new value. A whole batch reserves ONE contiguous range in ONE claim, so five
--- Hellas cannot straddle another manufacturer's allocation.
---
--- Returns the first reserved value, or nil + reason.
local function reserve(scope, scopeKey, n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    local sid = serverId()
    for _ = 1, RESERVE_ATTEMPTS do
        local ok, err = pcall(function()
            MySQL.insert.await([[INSERT IGNORE INTO production_sequence
                (server_id, scope, scope_key, next_value, updated_at) VALUES (?, ?, ?, 1, ?)]],
                { sid, scope, scopeKey, now() })
        end)
        if not ok then return nil, "sequence_unavailable:" .. tostring(err) end
        local cur = tonumber(MySQL.scalar.await(
            "SELECT next_value FROM production_sequence WHERE server_id=? AND scope=? AND scope_key=?",
            { sid, scope, scopeKey }))
        if not cur then return nil, "sequence_missing" end
        local nonce = ids.uuid4(hostRng)
        MySQL.update.await([[UPDATE production_sequence
            SET next_value = next_value + ?, holder = ?, updated_at = ?
            WHERE server_id=? AND scope=? AND scope_key=? AND next_value = ?]],
            { n, nonce, now(), sid, scope, scopeKey, cur })
        local held = MySQL.scalar.await(
            "SELECT holder FROM production_sequence WHERE server_id=? AND scope=? AND scope_key=?",
            { sid, scope, scopeKey })
        if held == nonce then return cur end
        -- Somebody else moved it between our read and our write. Read again and try for the new range.
    end
    return nil, "sequence_contended"
end
NcmProvenance.reserve = reserve

--- Set a sequence to at least `value`, never backwards. Used by the backfill to park each sequence after the
--- history it just established.
local function raiseTo(scope, scopeKey, value)
    local sid = serverId()
    pcall(function()
        MySQL.insert.await([[INSERT IGNORE INTO production_sequence
            (server_id, scope, scope_key, next_value, updated_at) VALUES (?, ?, ?, 1, ?)]],
            { sid, scope, scopeKey, now() })
        MySQL.update.await([[UPDATE production_sequence SET next_value = GREATEST(next_value, ?), updated_at = ?
            WHERE server_id=? AND scope=? AND scope_key=?]], { value, now(), sid, scope, scopeKey })
    end)
end

--- Reserve one contiguous ordinal range per sequence for a batch of `n` machines of one model.
---
--- Returns a list of `n` triples { global, maker, model }, or nil + reason. A partial reservation is not
--- unwound: numbers already taken stay taken and simply leave a gap. That is the deliberate trade in the
--- addendum -- unique, immutable and auditable beats cosmetically gapless, and rewinding a shared sequence
--- would reintroduce exactly the duplicate-serial risk the whole design exists to prevent.
function NcmProvenance.allocate(vehicleKey, n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    local entry = Catalogue.byKey(vehicleKey)
    if not entry then return nil, "unknown_vehicle_key" end
    local makerKey = entry.manufacturerKey
    if not makerKey then return nil, "no_manufacturer_key" end
    local g, gWhy = reserve(Identity.SCOPES.GLOBAL, "", n)
    if not g then return nil, "global:" .. tostring(gWhy) end
    local mk, mkWhy = reserve(Identity.SCOPES.MAKER, makerKey, n)
    if not mk then return nil, "maker:" .. tostring(mkWhy) end
    local md, mdWhy = reserve(Identity.SCOPES.MODEL, vehicleKey, n)
    if not md then return nil, "model:" .. tostring(mdWhy) end
    local out = {}
    for i = 0, n - 1 do
        out[#out + 1] = { global = g + i, maker = mk + i, model = md + i, manufacturerKey = makerKey }
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Backfill
-- ---------------------------------------------------------------------------------------------

--- Give existing assets the provenance they always had but never recorded. Runs once; a second run finds
--- nothing to do.
---
--- **The ordering evidence is `vehicle_asset_transfer.kind = 'production'`, not `vehicle_asset.acquired_at`.**
--- That distinction is the whole reason this is Lua and not SQL in a migration. `acquired_at` is REWRITTEN by
--- a purchase -- it means "when the current owner got it", not "when it was made" -- so ordering by it puts
--- MaiMai `10000000-...-0001`, the first persistent asset NCM ever had, THIRD, behind two cars that were
--- manufactured in the same second and simply never sold. The production transfer row is written once at
--- manufacture and never touched again.
---
--- Total order: production instant, then allocation id, then allocation slot, then asset id. The last is a
--- primary key, so ties are impossible and the result is fully deterministic.
---
--- **If any asset has no production evidence, this refuses and changes nothing.** Inventing a plausible
--- position in NCM's history would be worse than having none (addendum section 7).
function NcmProvenance.backfill()
    local pending = tonumber(MySQL.scalar.await(
        "SELECT COUNT(*) FROM vehicle_asset WHERE server_id=? AND production_ordinal IS NULL", { serverId() })) or 0
    if pending == 0 then return 0 end
    local orphans = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM vehicle_asset a
        WHERE a.server_id=? AND a.production_ordinal IS NULL
          AND NOT EXISTS (SELECT 1 FROM vehicle_asset_transfer t
                          WHERE t.asset_id = a.asset_id AND t.kind = 'production')]], { serverId() })) or 0
    if orphans > 0 then
        log("BACKFILL REFUSED: %d of %d asset(s) have no production evidence. Their place in NCM's history " ..
            "cannot be established and will NOT be guessed. No ordinals were assigned.", orphans, pending)
        return nil, "ambiguous_history"
    end
    local rows = MySQL.query.await([[SELECT a.asset_id, a.vehicle_key, t.occurred_at
        FROM vehicle_asset a
        JOIN vehicle_asset_transfer t ON t.asset_id = a.asset_id AND t.kind = 'production'
        WHERE a.server_id = ? AND a.production_ordinal IS NULL
        ORDER BY t.occurred_at, a.allocation_id, a.allocation_slot, a.asset_id]], { serverId() }) or {}
    if #rows == 0 then return 0 end

    -- Continue from whatever already exists rather than assuming an empty world.
    local maxGlobal = tonumber(MySQL.scalar.await(
        "SELECT MAX(production_ordinal) FROM vehicle_asset WHERE server_id=?", { serverId() })) or 0
    local nextGlobal = maxGlobal + 1
    local nextMaker, nextModel = {}, {}
    local assigned, skipped = 0, 0
    for _, r in ipairs(rows) do
        local entry = Catalogue.byKey(r.vehicle_key)
        local makerKey = entry and entry.manufacturerKey or nil
        if not makerKey then
            skipped = skipped + 1
            log("BACKFILL SKIP asset=%s key=%s: no stable manufacturer identity", tostring(r.asset_id):sub(1, 8), tostring(r.vehicle_key))
        else
            if not nextMaker[makerKey] then
                nextMaker[makerKey] = (tonumber(MySQL.scalar.await(
                    "SELECT MAX(maker_ordinal) FROM vehicle_asset WHERE server_id=? AND manufacturer_key=?",
                    { serverId(), makerKey })) or 0) + 1
            end
            if not nextModel[r.vehicle_key] then
                nextModel[r.vehicle_key] = (tonumber(MySQL.scalar.await(
                    "SELECT MAX(model_ordinal) FROM vehicle_asset WHERE server_id=? AND vehicle_key=?",
                    { serverId(), r.vehicle_key })) or 0) + 1
            end
            local g, mk, md = nextGlobal, nextMaker[makerKey], nextModel[r.vehicle_key]
            local ok, err = pcall(function()
                MySQL.update.await([[UPDATE vehicle_asset
                    SET origin = 'production', manufacturer_key = ?, production_ordinal = ?,
                        maker_ordinal = ?, model_ordinal = ?, produced_at = ?
                    WHERE asset_id = ? AND production_ordinal IS NULL]],
                    { makerKey, g, mk, md, math.floor(tonumber(r.occurred_at) or 0), r.asset_id })
            end)
            if ok then
                nextGlobal = nextGlobal + 1
                nextMaker[makerKey] = mk + 1
                nextModel[r.vehicle_key] = md + 1
                assigned = assigned + 1
                log("backfill NCM %s | %s %s | %s %s | asset=%s",
                    Identity.formatOrdinal(g), makerKey, Identity.formatOrdinal(mk, 4),
                    r.vehicle_key, Identity.formatOrdinal(md, 4), tostring(r.asset_id):sub(1, 8))
            else
                skipped = skipped + 1
                log("BACKFILL FAILED asset=%s: %s", tostring(r.asset_id):sub(1, 8), tostring(err))
            end
        end
    end
    -- Park every sequence past the history just written, so the next real production continues it.
    raiseTo(Identity.SCOPES.GLOBAL, "", nextGlobal)
    for k, v in pairs(nextMaker) do raiseTo(Identity.SCOPES.MAKER, k, v) end
    for k, v in pairs(nextModel) do raiseTo(Identity.SCOPES.MODEL, k, v) end
    log("backfill complete: %d assigned, %d skipped", assigned, skipped)
    return assigned
end

--- The provenance card for one asset. Read-only; this is what a Machine Index or a future used-market
--- listing shows.
function NcmProvenance.of(assetId)
    if type(assetId) ~= "string" or assetId == "" then return nil end
    local r = MySQL.single.await([[SELECT asset_id, vehicle_key, manufacturer_key, origin,
        production_ordinal, maker_ordinal, model_ordinal, produced_at, lifecycle, odometer_m
        FROM vehicle_asset WHERE asset_id = ?]], { assetId })
    if not r then return nil end
    local entry = Catalogue.byKey(r.vehicle_key)
    return {
        assetId = r.asset_id, vehicleKey = r.vehicle_key,
        manufacturer = entry and entry.manufacturer or r.manufacturer_key,
        displayName = entry and entry.displayName or r.vehicle_key,
        origin = r.origin,
        globalOrdinal = tonumber(r.production_ordinal),
        makerOrdinal = tonumber(r.maker_ordinal),
        modelOrdinal = tonumber(r.model_ordinal),
        producedAt = tonumber(r.produced_at),
        lifecycle = r.lifecycle or "active",
        odometerM = tonumber(r.odometer_m) or 0,
    }
end

-- Console: the birth certificate, for QA and for answering a player's question about their own car.
RegisterCommand("ncm.provenance", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local assetId = args and args[1]
    CreateThread(function()
        if assetId then
            local p = NcmProvenance.of(tostring(assetId))
            if not p then log("no such asset: %s", tostring(assetId)); return end
            log("%s | NCM %s | %s %s | %s %s | %s | %s | origin=%s",
                p.assetId, Identity.formatOrdinal(p.globalOrdinal) or "-",
                tostring(p.manufacturer), Identity.formatOrdinal(p.makerOrdinal, 4) or "-",
                tostring(p.displayName), Identity.formatOrdinal(p.modelOrdinal, 4) or "-",
                Identity.formatOdometer(p.odometerM), p.lifecycle, p.origin)
            return
        end
        local rows = MySQL.query.await([[SELECT asset_id, vehicle_key, manufacturer_key, production_ordinal,
            maker_ordinal, model_ordinal, odometer_m, lifecycle FROM vehicle_asset
            WHERE server_id=? ORDER BY production_ordinal LIMIT 40]], { serverId() }) or {}
        for _, r in ipairs(rows) do
            log("NCM %-8s %-16s %-6s %-22s %-6s %12s  %s",
                Identity.formatOrdinal(r.production_ordinal) or "-", tostring(r.manufacturer_key),
                Identity.formatOrdinal(r.maker_ordinal, 4) or "-", tostring(r.vehicle_key),
                Identity.formatOrdinal(r.model_ordinal, 4) or "-",
                Identity.formatOdometer(r.odometer_m), tostring(r.lifecycle))
        end
    end)
end, false)
