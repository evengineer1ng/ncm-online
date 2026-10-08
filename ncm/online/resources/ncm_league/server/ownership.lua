-- ncm_league / server / ownership — the garage ledger (L83, IDEA-115, IDEA-157).
--
-- L83: drivers bring their own car, earned through progression, and an entry they do not own is REFUSED rather
-- than substituted. That makes "does this driver own one?" a question somebody has to be able to answer, and
-- until 012 nobody could.
--
-- **IDEA-157 changed what a row means.** `owned_vehicle` was keyed `(driver, server, record)` -- one row per
-- MODEL -- so "two Caliburns" was not merely unsupported, it was unrepresentable: the second write hit the
-- ON DUPLICATE KEY path and quietly became the first one again. Rows now live in `vehicle_asset`, keyed on an
-- `asset_id` that names one PHYSICAL EXAMPLE and survives being traded, re-liveried or renamed upstream.
--
-- Everything this file returns still carries `.record`, which is why the three consumers
-- (`collection.lua`, `competition.lua`, `guide.lua`) crossed this migration without being rewritten.
--
-- This file owns the answer and nothing else. It does not decide what a championship allows (that is
-- `competition.class` eligibility), it does not spawn anything (that is `ncm_world/server/garage.lua`), and it
-- does not grant cars for finishing races yet (progression will, later). Ordering, vocabulary and the
-- examples-vs-models distinction are `data.vehicle_assets`, which is pure and tested offline.
--
-- **There is deliberately no testing bypass.** The owner asked whether they could simply own every car needed
-- instead (2026-09-22) and that is strictly better than a flag: seeding a real garage exercises the real check,
-- where a bypass would only ever exercise the bypass. `ncm.grant` is how a garage gets seeded, it writes real
-- rows, and `acquired_via = 'seed'` keeps a seeded car distinguishable from an earned one forever.
NcmOwnership = {}

local Core = NcmCore
local Pool = Core.get("data.vehicle_pool")
local Assets = Core.get("data.vehicle_assets")
local Catalogue = Core.get("data.vehicle_catalogue")
local Config = Core.get("data.vehicle_config")
local Identity = Core.get("data.vehicle_identity")
local ids = Core.get("vocabulary.ids")
local Gearbox = Core.get("machine.gearbox")

local function log(fmt, ...) print(("[ncm_league/ownership] " .. fmt):format(...)) end
local now = function() return Open77.time.unix() end
local hostRng = function() return math.random() end
local function serverId() return NcmCalendar.serverId() end
local function tell(pid, text) if pid and pid > 0 then pcall(Open77.chat.send, pid, "[NCM] " .. text) end end

--- Ownership is an input to both Race Guide eligibility counts and the venue action list. A ledger mutation
--- must invalidate those projections immediately; otherwise a correctly granted car remains visually
--- ineligible until an unrelated calendar publication happens to refresh them.
local function refreshCompetitionViews(pid)
    if not (pid and pid > 0 and NcmGuide) then return end
    if NcmGuide.push then NcmGuide.push(pid) end
    if NcmGuide.pushVenue then NcmGuide.pushVenue(pid) end
end

-- driverId -> array of asset rows { assetId, record, vehicleKey, class, acquiredVia, acquiredAt }.
-- Entry asks this on every attempt, so it must not be a query each time; the ledger only changes through this
-- file, so the cache is written where the database is.
local cache = {}

function NcmOwnership.invalidate(driverId)
    if type(driverId) == "string" then cache[driverId] = nil end
end

local function loadDriver(driverId)
    if cache[driverId] then return cache[driverId] end
    local rows = {}
    if MySQL.isReady() then
        local ok, res = pcall(function()
            return MySQL.query.await(
                "SELECT asset_id, record, vehicle_key, class, acquired_via, acquired_at, " ..
                "paint_primary, paint_secondary, gearbox_kind, gearbox_spec, gearbox_source " ..
                "FROM vehicle_asset WHERE ncm_driver_id = ? AND server_id = ?",
                { driverId, serverId() }) or {}
        end)
        if ok then
            for _, r in ipairs(res) do
                rows[#rows + 1] = {
                    assetId = r.asset_id, record = r.record, vehicleKey = r.vehicle_key,
                    class = r.class, acquiredVia = r.acquired_via, acquiredAt = tonumber(r.acquired_at),
                    paint = { primary = r.paint_primary, secondary = r.paint_secondary },
                    gearbox = NcmGearbox.remember(r.asset_id, r) or Gearbox.preGearbox(),
                }
            end
        else
            -- A failed read must not read as "owns nothing", because that would refuse a legitimate entry and
            -- look exactly like a progression bug. Refuse to cache and let the caller decide (see M.owns).
            log("ownership read failed for %s: %s", tostring(driverId):sub(1, 8), tostring(res))
            return nil, "db_unavailable"
        end
    end
    cache[driverId] = rows
    return rows
end

--- Does this driver own at least one example of this record? Returns true/false, or nil + reason when the
--- ledger cannot be read. A nil answer is NOT a no: the caller must decide, and refusing entry on a database
--- hiccup is the wrong call.
function NcmOwnership.owns(driverId, record)
    if type(driverId) ~= "string" or type(record) ~= "string" then return false end
    local rows, why = loadDriver(driverId)
    if not rows then return nil, why end
    for _, r in ipairs(rows) do
        if r.record == record then return true end
    end
    return false
end

--- Everything this driver holds: ONE ROW PER PHYSICAL EXAMPLE, class-ordered, each carrying
--- `{ assetId, record, vehicleKey, class, prestige, displayName, manufacturer, acquiredVia, acquiredAt }`.
---
--- Returns `{}` when the ledger cannot be read. That is a weaker answer than `owns` gives, and it is
--- deliberately unchanged from before this migration: the callers cannot yet tell "empty" from "unknown", and
--- teaching them to is its own change, not a rider on this one.
function NcmOwnership.list(driverId)
    local rows = loadDriver(driverId)
    if not rows then return {} end
    local out = Assets.shape(rows)
    -- L306: two Galenas in one garage are told apart by their gearbox
    for _, r in ipairs(out) do
        if r.displayName and r.gearbox then
            r.gearboxKind, r.gearboxSpec = r.gearbox.kind, r.gearbox.spec
            r.displayName = Gearbox.label(r.displayName, r.gearbox)
        end
    end
    return out
end

--- Distinct runtime record ids. Every eligibility caller wants THIS, not `list`: `Eligibility.eligibleOwned`
--- counts what it is handed, so two examples of one legal car would otherwise report two eligible options
--- where a championship sees one.
function NcmOwnership.records(driverId)
    local rows = loadDriver(driverId)
    if not rows then return {} end
    return Assets.records(rows)
end

--- The set of vehicleKeys this driver owns. What the Collection means by OWNED: three of one machine is one
--- completed slot, not three.
function NcmOwnership.keys(driverId)
    local rows = loadDriver(driverId)
    if not rows then return {} end
    return Assets.keys(rows)
end

--- How many examples of each record. `{}` for an empty garage, never nil.
function NcmOwnership.counts(driverId)
    local rows = loadDriver(driverId)
    if not rows then return {} end
    return Assets.countByRecord(rows)
end

local function insertAsset(driverId, record, via, grantedBy)
    -- L306: a grant names its gearbox by record. `<model>_ncm_gbx_<spec>` is a manual of that spec; the model record
    -- itself is an automatic. The asset stores the MODEL record (eligibility reads it); the clone is a spawn detail.
    local specId
    record, specId = Gearbox.baseOf(record)
    local meta = Pool.byRecord(record)
    -- the `class` column is a convenience for reading the table by hand; membership is the pool's to answer,
    -- and a record in two classes stores its first (CLASS_ORDER) one here. Never query eligibility off it.
    local primaryClass = meta and meta.classes and meta.classes[1] or nil
    local entry = Catalogue.resolveRecord(record)
    -- Resolved once, at mint time, and then left alone: if a mod update later renames this record, the stored
    -- key is the only thing that still knows what the machine was.
    local vehicleKey = entry and entry.vehicleKey or nil
    local assetId = ids.uuid4(hostRng)
    local acquiredAt = math.floor(now())
    -- L111: the finish is decided when the machine is made, and never re-rolled. Deterministic from the
    -- assetId and constrained to the range this model is actually produced in -- so it is stable forever and
    -- is never a colour no factory made. Allocation will later be the author and simply write these columns.
    local paint = Config.paintFor(vehicleKey, assetId, nil)
    local paintPrimary, paintSecondary = Config.toHex(paint.primary), Config.toHex(paint.secondary)

    if MySQL.isReady() then
        local ok = pcall(function()
            -- `origin = grant`: a real, permanent, fully owned machine that is NOT primary-market
            -- manufacture, so it consumes no production ordinal. A test car or a progression prize must not
            -- silently take a number out of a manufacturer's history (addendum section 8).
            MySQL.insert.await(
                "INSERT INTO vehicle_asset (asset_id, server_id, ncm_driver_id, vehicle_key, record, class, " ..
                "acquired_via, granted_by, acquired_at, paint_primary, paint_secondary, origin, produced_at, " ..
                "gearbox_kind, gearbox_spec, gearbox_source, gearbox_at) " ..
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                { assetId, serverId(), driverId, vehicleKey, record, primaryClass, via or "grant", grantedBy,
                  acquiredAt, paintPrimary, paintSecondary, Identity.ORIGIN.GRANT, acquiredAt,
                  NcmGearbox.columns(NcmGearbox.birth(assetId, vehicleKey, specId or "a")) })
        end)
        if not ok then return nil, "db" end
    end

    if cache[driverId] then
        cache[driverId][#cache[driverId] + 1] = {
            assetId = assetId, record = record, vehicleKey = vehicleKey,
            class = primaryClass, acquiredVia = via or "grant", acquiredAt = acquiredAt,
            paint = { primary = paintPrimary, secondary = paintSecondary },
        }
    end
    if NcmComponents and NcmComponents.ensureMachine then
        local ok, why = NcmComponents.ensureMachine(assetId, vehicleKey, driverId)
        if not ok and why ~= "unsupported_machine" and why ~= "already_configured" then
            log("factory configuration failed asset=%s: %s", assetId:sub(1, 8), tostring(why))
        end
    end
    return assetId
end

--- Mint a NEW physical example, always. Supply may use this; Market purchases transfer existing stock instead.
--- Calling it twice means
--- two cars, which is the entire point of IDEA-157 and would have been impossible before it.
--- Returns assetId, or nil + reason.
function NcmOwnership.mint(driverId, record, via, grantedBy)
    if type(driverId) ~= "string" or type(record) ~= "string" or record == "" then return nil, "invalid" end
    if not loadDriver(driverId) then return nil, "db_unavailable" end
    return insertAsset(driverId, record, via, grantedBy)
end

--- Manufacture a NEW physical example that **nobody owns yet**: primary-market stock.
---
--- `mint` above always needs an owner, because a garage is the only place a car could be before markets
--- existed. Production puts a car on a shelf, so the owner column is deliberately NULL until somebody buys
--- it -- which is the same state the three alpha bootstrap assets have been sitting in since launch.
---
--- Everything else is identical to minting on purpose (packet section 7): a produced vehicle is not an
--- increment of an abstract count that later becomes a car. It gets its own `assetId`, its own resolved
--- `vehicleKey`, its own class, and its own deterministic factory finish decided once at manufacture and
--- never re-rolled (L111) -- so it can carry an owner, a transfer history, mileage, race results and
--- modifications exactly like any other asset. There is no parallel vehicle identity here.
---
--- `opts.allocationId` / `opts.allocationSlot` carry the production run's identity into
--- `ux_vehicle_asset_allocation_slot`, the UNIQUE key migration 017 already put on
--- `(server_id, allocation_id, allocation_slot)`. That gives idempotency a second, independent line of
--- defence: even if a tick claim were somehow lost, re-running the same tick collides on slot 1 in the
--- database and cannot insert the batch twice. The alpha bootstrap used the same columns with
--- `alpha_launch` slots 1-3, so this is the established shape, not a new one.
---
--- Returns assetId, or nil + reason.
function NcmOwnership.manufacture(record, opts)
    if type(record) ~= "string" or record == "" then return nil, "invalid" end
    opts = type(opts) == "table" and opts or {}
    local meta = Pool.byRecord(record)
    local primaryClass = meta and meta.classes and meta.classes[1] or nil
    local entry = Catalogue.resolveRecord(record)
    local vehicleKey = entry and entry.vehicleKey or opts.vehicleKey
    if not vehicleKey then return nil, "unknown_record" end
    local assetId = ids.uuid4(hostRng)
    local paint = Config.paintFor(vehicleKey, assetId, nil)
    local paintPrimary, paintSecondary = Config.toHex(paint.primary), Config.toHex(paint.secondary)
    if not MySQL.isReady() then return nil, "db_unavailable" end
    -- **The birth certificate.** A manufactured machine gets its place in three histories: NCM's, its
    -- manufacturer's and its model's. `opts.ordinal` is the triple already reserved for this slot by
    -- `NcmProvenance.allocate` -- reserved once for a whole batch, so five Hellas get five contiguous numbers
    -- in one claim and cannot straddle another manufacturer's allocation.
    --
    -- Without a triple the asset is still perfectly real; it simply has no serial. That is the `grant` origin:
    -- an admin or progression car must not burn Ferrari #14 during a debugging session (addendum section 8).
    local ord = type(opts.ordinal) == "table" and opts.ordinal or nil
    local origin = ord and Identity.ORIGIN.PRODUCTION or (opts.origin or Identity.ORIGIN.GRANT)
    local producedAt = math.floor(now())
    local insertQuery = "INSERT INTO vehicle_asset (asset_id, server_id, ncm_driver_id, vehicle_key, record, class, " ..
        "acquired_via, acquired_at, allocation_id, allocation_slot, paint_primary, paint_secondary, " ..
        "origin, manufacturer_key, production_ordinal, maker_ordinal, model_ordinal, produced_at, " ..
        "gearbox_kind, gearbox_spec, gearbox_source, gearbox_at) " ..
        "VALUES (?, ?, NULL, ?, ?, ?, NULL, ?, ?, NULLIF(?, 0), ?, ?, ?, NULLIF(?, ''), " ..
        "NULLIF(?, 0), NULLIF(?, 0), NULLIF(?, 0), ?, ?, ?, ?, ?)"
    -- KB-311: `allocation_slot` is an INT. Its sentinel is 0, never '': under STRICT_TRANS_TABLES `NULLIF(3, '')` is
    -- "Truncated incorrect DECIMAL value" (SQL 1292) inside an INSERT, and it failed every car's birth transaction from
    -- 2026-09-26 -- no vehicle was manufactured anywhere after that (proved against dev MariaDB, rolled back).
    local insertValues = { assetId, serverId(), vehicleKey, record, primaryClass, producedAt,
        opts.allocationId or "production", tonumber(opts.allocationSlot) or 0, paintPrimary, paintSecondary,
        origin, ord and ord.manufacturerKey or "",
        ord and ord.global or 0, ord and ord.maker or 0, ord and ord.model or 0, producedAt }
    -- L306: manufacture rolls the gearbox from the model's factory mix, in the same INSERT as the car
    do
        local gk, gs, gsrc, gat = NcmGearbox.columns(NcmGearbox.birth(assetId, vehicleKey))
        insertValues[#insertValues + 1] = gk; insertValues[#insertValues + 1] = gs
        insertValues[#insertValues + 1] = gsrc; insertValues[#insertValues + 1] = gat
    end
    local ok, err = pcall(function()
        local factory = NcmComponents and NcmComponents.factoryStatements and
            NcmComponents.factoryStatements(assetId, vehicleKey, nil, producedAt, 0) or nil
        if factory then
            table.insert(factory, 1, { query = insertQuery, values = insertValues })
            if not MySQL.transaction.await(factory) then error("vehicle_and_factory_configuration_transaction") end
        else
            MySQL.insert.await(insertQuery, insertValues)
        end
    end)
    if not ok then return nil, "db:" .. tostring(err) end
    if ord then
        log("manufactured NCM %s | %s %s | %s %s | asset=%s",
            Identity.formatOrdinal(ord.global), tostring(ord.manufacturerKey),
            Identity.formatOrdinal(ord.maker, 4), vehicleKey, Identity.formatOrdinal(ord.model, 4),
            assetId:sub(1, 8))
    end
    return assetId, vehicleKey
end

--- Ensure this driver owns AT LEAST ONE example, and mint one only if they own none.
---
--- Idempotent, which `mint` deliberately is not. Seeding a garage twice must not silently double it -- that was
--- free when the primary key was the record and has to be asked for now that it is the asset.
--- Returns assetId, isNew, or nil + reason.
function NcmOwnership.grant(driverId, record, via, grantedBy)
    if type(driverId) ~= "string" or type(record) ~= "string" or record == "" then return nil, "invalid" end
    local rows, why = loadDriver(driverId)
    if not rows then return nil, why or "db_unavailable" end
    for _, r in ipairs(rows) do
        if r.record == record then return r.assetId, false end
    end
    local assetId, reason = insertAsset(driverId, record, via, grantedBy)
    if not assetId then return nil, reason end
    return assetId, true
end

--- CLAIM a car into this world (L338): the single-player way a car the player has -- a Collection mod, a livery, any
--- installed vehicle -- becomes an NCM Machine on this tape. A catalogue model is MANUFACTURED with a birth certificate
--- (global / maker / model serial, a production transfer) and handed to the driver (a `claim` transfer), so it is a
--- serialized machine like any market car. A record NCM has never heard of still becomes a real asset (its own entry,
--- its own observations; the passport infers what it can) -- it simply has no maker history to take a serial from.
--- Idempotent per record and driver: claiming the Kimiko RB15 twice returns the same machine.
--- Returns assetId, isNew, ordinal (or nil + reason).
function NcmOwnership.claim(driverId, record, via)
    if type(driverId) ~= "string" or type(record) ~= "string" or record == "" then return nil, "invalid" end
    local rows, why = loadDriver(driverId)
    if not rows then return nil, why or "db_unavailable" end
    for _, r in ipairs(rows) do if r.record == record then return r.assetId, false end end
    local entry = Catalogue.resolveRecord(record)
    if not entry then
        local assetId, reason = insertAsset(driverId, record, via or "claim", "claim")
        if not assetId then return nil, reason end
        log("CLAIM %s (not in the catalogue: an unserialized machine, passport inferred) -> asset=%s", record, assetId:sub(1, 8))
        return assetId, true, nil
    end
    local ord = nil
    if NcmProvenance and NcmProvenance.allocate then
        local list = NcmProvenance.allocate(entry.vehicleKey, 1)
        ord = list and list[1] or nil
    end
    local assetId, reason = NcmOwnership.manufacture(record, { ordinal = ord, allocationId = "claim", vehicleKey = entry.vehicleKey })
    if not assetId then return nil, reason end
    local t = math.floor(now())
    -- a livery car wears its livery's colours, not a factory roll (data.liveries)
    local pp, ps
    local okL, Liveries = pcall(function() return NcmCore.get("data.liveries") end)
    local l = okL and Liveries and Liveries.fromRecord(record) or nil
    if l and l.spec and l.spec.primary then pp, ps = l.spec.primary:gsub("#", ""), (l.spec.secondary or l.spec.primary):gsub("#", "") end
    local ok, err = MySQL.transaction.await({
        { query = [[UPDATE vehicle_asset SET ncm_driver_id = ?, acquired_via = ?, acquired_at = ?,
            paint_primary = COALESCE(NULLIF(?, ''), paint_primary), paint_secondary = COALESCE(NULLIF(?, ''), paint_secondary)
            WHERE asset_id = ? AND ncm_driver_id IS NULL]], values = { driverId, via or "claim", t, pp or "", ps or "", assetId } },
        { query = [[INSERT IGNORE INTO vehicle_asset_transfer (transfer_id, idem_key, server_id, asset_id, from_driver_id, to_driver_id,
            kind, market_id, amount, occurred_at) VALUES (?, ?, ?, ?, NULL, NULL, 'production', NULL, 0, ?)]],
            values = { ids.uuid4(hostRng), "production:" .. assetId, serverId(), assetId, t } },
        { query = [[INSERT IGNORE INTO vehicle_asset_transfer (transfer_id, idem_key, server_id, asset_id, from_driver_id, to_driver_id,
            kind, market_id, amount, occurred_at) VALUES (?, ?, ?, ?, NULL, ?, 'claim', NULL, 0, ?)]],
            values = { ids.uuid4(hostRng), "claim:" .. assetId, serverId(), assetId, driverId, t } },
    })
    if not ok then return nil, "claim_transaction: " .. tostring(err) end
    NcmOwnership.invalidate(driverId)
    log("CLAIM %s -> %s%s asset=%s", record, entry.vehicleKey,
        ord and (" NCM " .. Identity.formatOrdinal(ord.global) .. " | " .. tostring(ord.manufacturerKey) .. " " ..
            Identity.formatOrdinal(ord.maker, 4) .. " | " .. entry.vehicleKey .. " " .. Identity.formatOrdinal(ord.model, 4)) or "",
        assetId:sub(1, 8))
    return assetId, true, ord
end

-- The single-player host asks for a claim when the player presses CLAIM on the deck (it knows the car they are in, or
-- the livery they picked). Server-local event: `ncm:host:claim`(pid, record). OPEN//77 never sends it.
AddEventHandler("ncm:host:claim", function(pid, record)
    pid = tonumber(pid) or 0
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then log("claim: no NCM driver on player %d", pid); return end
    local assetId, isNew, ord = NcmOwnership.claim(driver.ncmDriverId, tostring(record or ""), "claim")
    if not assetId then
        tell(pid, "Could not claim that car: " .. tostring(isNew))
        TriggerEvent("ncm:host:claimed", pid, record, nil, tostring(isNew))
        return
    end
    local serial = ord and ("NCM " .. Identity.formatOrdinal(ord.global) .. " · " .. tostring(ord.manufacturerKey) .. " " ..
        Identity.formatOrdinal(ord.maker, 4)) or nil
    tell(pid, isNew and ("Claimed: %s%s. It is yours in this Race Week continuity."):format(record, serial and (" (" .. serial .. ")") or "")
        or ("Already yours: %s."):format(record))
    TriggerEvent("ncm:host:claimed", pid, record, assetId, isNew and "new" or "existing", serial)
    pcall(refreshCompetitionViews, pid)
end)

RegisterCommand("ncm.claim", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, record = tonumber(args and args[1]), args and args[2]
    if not pid or not record then log("usage: ncm.claim <playerId> <record>"); return end
    TriggerEvent("ncm:host:claim", pid, record)
end, false)

--- Remove EVERY example of a record from a driver's garage. Matches what `revoke` did before this migration,
--- which is the behaviour the console command and its operators already expect.
function NcmOwnership.revoke(driverId, record)
    if MySQL.isReady() then
        pcall(function()
            MySQL.query.await("DELETE FROM vehicle_asset WHERE ncm_driver_id = ? AND server_id = ? AND record = ?",
                { driverId, serverId(), record })
        end)
    end
    local rows = cache[driverId]
    if rows then
        local kept = {}
        for _, r in ipairs(rows) do
            if r.record ~= record then kept[#kept + 1] = r end
        end
        cache[driverId] = kept
    end
    return true
end

--- Remove ONE physical example. The precise counterpart to `mint`, and the only one that makes sense once a
--- driver can hold several of the same machine.
function NcmOwnership.dispose(assetId)
    if type(assetId) ~= "string" or assetId == "" then return nil, "invalid" end
    if MySQL.isReady() then
        local ok = pcall(function()
            MySQL.query.await("DELETE FROM vehicle_asset WHERE asset_id = ?", { assetId })
        end)
        if not ok then return nil, "db" end
    end
    for driverId, rows in pairs(cache) do
        for i = #rows, 1, -1 do
            if rows[i].assetId == assetId then table.remove(rows, i) end
        end
        cache[driverId] = rows
    end
    return true
end

--- The paint one specific asset must be spawned in. **Every spawn path must call this**, or a machine is one
--- colour when called and another on a grid -- which is the bug L111 exists to close.
---
--- Falls back to the factory finish when the columns are NULL, so an asset minted before 019 is stable from
--- the moment it is first spawned, with no backfill.
function NcmOwnership.paintFor(assetId)
    if type(assetId) ~= "string" or assetId == "" then return nil end
    if not MySQL.isReady() then return nil end
    local ok, row = pcall(function()
        return MySQL.single.await(
            "SELECT vehicle_key, paint_primary, paint_secondary FROM vehicle_asset WHERE asset_id = ?", { assetId })
    end)
    if not ok or type(row) ~= "table" then return nil end
    local paint = Config.paintFor(row.vehicle_key, assetId,
        { primary = row.paint_primary, secondary = row.paint_secondary })
    return { primary = paint.primary, secondary = paint.secondary, source = paint.source, name = paint.name }
end

--- Drop a driver's cached ledger (after an out-of-band write, or on disconnect).
function NcmOwnership.forget(driverId) cache[driverId] = nil end

--- Resolve `vehicle_key` for rows that do not have one.
---
--- Migration 015 could not do this: SQL cannot reach the catalogue. Assets minted since always carry their key,
--- so this is a one-time pass over the migrated rows -- but it stays because it is also the repair path for any
--- asset minted while the catalogue did not yet know its record. It never OVERWRITES a stored key: a key that
--- disagrees with today's catalogue is precisely the history we are trying to keep.
local function backfillKeys()
    if not MySQL.isReady() then return end
    local ok, rows = pcall(function()
        return MySQL.query.await("SELECT asset_id, record FROM vehicle_asset WHERE vehicle_key IS NULL") or {}
    end)
    if not ok or type(rows) ~= "table" or #rows == 0 then return end
    local fixed, unknown = 0, 0
    for _, r in ipairs(rows) do
        local entry = Catalogue.resolveRecord(r.record)
        if entry then
            local okUpd = pcall(function()
                MySQL.query.await("UPDATE vehicle_asset SET vehicle_key = ? WHERE asset_id = ? AND vehicle_key IS NULL",
                    { entry.vehicleKey, r.asset_id })
            end)
            if okUpd then fixed = fixed + 1 end
        else
            unknown = unknown + 1
        end
    end
    if fixed > 0 or unknown > 0 then
        log("vehicleKey backfill: %d resolved, %d left NULL (record not in the catalogue -- authored or team car)",
            fixed, unknown)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Host kit (KB-4: console twins, because a second client has no WebUI)
-- ---------------------------------------------------------------------------------------------

--- Resolve a grant target: an exact record id, a pool class ("Sport"), or "all".
local function resolveTargets(what)
    local want = tostring(what or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if want == "" then return nil, "usage" end
    if want:lower() == "all" then
        local out = {}
        for _, r in ipairs(Pool.allRecords()) do out[#out + 1] = r.id end
        return out
    end
    if Pool.byRecord(want) then return { want } end
    for _, class in ipairs(Pool.classes()) do
        if class:lower() == want:lower() then
            local out = {}
            for _, r in ipairs(Pool.records(class)) do out[#out + 1] = r.id end
            return out
        end
    end
    -- allow a bare TweakDB id we do not know (team liveries, authored cars): grant it, flag it
    if want:find("^Vehicle%.") then return { want }, "unknown_record" end
    return nil, "unknown_target"
end

-- ncm.grant <playerId> <record|class|all>   e.g. ncm.grant 1 all | ncm.grant 1 Sport | ncm.grant 1 Vehicle.v_...
-- Idempotent: a second run adds nothing. Use `ncm.mint` to deliberately hand somebody a second example.
RegisterCommand("ncm.grant", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    local targets, why = resolveTargets(args and args[2])
    if not pid or not targets then
        log("usage: ncm.grant <playerId> <record|class|all>%s", why == "unknown_target" and (" (unknown: " .. tostring(args and args[2]) .. ")") or "")
        return
    end
    CreateThread(function()
        local driver = NcmCalendar.resolveDriver(pid)
        if not driver then log("ncm.grant: no NCM driver on player %d", pid); return end
        local added, already = 0, 0
        for _, record in ipairs(targets) do
            local assetId, isNew = NcmOwnership.grant(driver.ncmDriverId, record, "seed", "console")
            if assetId and isNew then added = added + 1
            elseif assetId then already = already + 1 end
        end
        log("granted %d new, %d already held, to driver=%s%s", added, already, driver.ncmDriverId:sub(1, 8),
            why == "unknown_record" and " (record not in the pool)" or "")
        tell(pid, ("Garage: %d vehicle(s) added%s."):format(added,
            already > 0 and (", %d already owned"):format(already) or ""))
        refreshCompetitionViews(pid)
    end)
end, false)

-- ncm.mint <playerId> <record> [count] -- hand over ANOTHER physical example, even of a car already owned.
-- This is the command that could not exist before IDEA-157, and the one that proves the migration did its job.
RegisterCommand("ncm.mint", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, record = tonumber(args and args[1]), args and args[2]
    local count = math.max(1, math.min(10, math.floor(tonumber(args and args[3]) or 1)))
    if not pid or not record then log("usage: ncm.mint <playerId> <record> [count]"); return end
    CreateThread(function()
        local driver = NcmCalendar.resolveDriver(pid)
        if not driver then log("ncm.mint: no NCM driver on player %d", pid); return end
        local minted = {}
        for _ = 1, count do
            local assetId, reason = NcmOwnership.mint(driver.ncmDriverId, record, "grant", "console")
            if assetId then minted[#minted + 1] = assetId
            else log("ncm.mint failed: %s", tostring(reason)); break end
        end
        log("minted %d example(s) of %s for driver=%s", #minted, record, driver.ncmDriverId:sub(1, 8))
        for _, a in ipairs(minted) do log("  asset %s", a) end
        tell(pid, ("Garage: %d new %s added."):format(#minted, record))
        refreshCompetitionViews(pid)
    end)
end, false)

-- ncm.garage [playerId] — what a driver owns, one line per physical example.
RegisterCommand("ncm.garage", function(source, args)
    local caller = tonumber(source) or 0
    local pid = tonumber(args and args[1]) or (caller > 0 and caller or nil)
    if not pid then log("usage: ncm.garage <playerId>"); return end
    CreateThread(function()
        local driver = NcmCalendar.resolveDriver(pid)
        if not driver then log("ncm.garage: no NCM driver on player %d", pid); return end
        local list = NcmOwnership.list(driver.ncmDriverId)
        local models = #NcmOwnership.records(driver.ncmDriverId)
        log("garage driver=%s: %d example(s) across %d model(s)", driver.ncmDriverId:sub(1, 8), #list, models)
        for _, v in ipairs(list) do
            log("  %s  %s (%s) key=%s via=%s", tostring(v.assetId):sub(1, 8), v.record, v.class,
                tostring(v.vehicleKey or "-"), tostring(v.acquiredVia or "-"))
        end
        -- shaped rows still carry `.record`, so describe reads them directly
        tell(caller, Assets.describe(list))
    end)
end, false)

-- ncm.revoke <playerId> <record> — remove every example of that record.
RegisterCommand("ncm.revoke", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, record = tonumber(args and args[1]), args and args[2]
    if not pid or not record then log("usage: ncm.revoke <playerId> <record>"); return end
    CreateThread(function()
        local driver = NcmCalendar.resolveDriver(pid)
        if not driver then return end
        local before = NcmOwnership.counts(driver.ncmDriverId)[record] or 0
        NcmOwnership.revoke(driver.ncmDriverId, record)
        log("revoked %d example(s) of %s from driver=%s", before, record, driver.ncmDriverId:sub(1, 8))
        refreshCompetitionViews(pid)
    end)
end, false)

-- ncm.dispose <assetId> — remove ONE physical example, by its own id.
RegisterCommand("ncm.dispose", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local assetId = args and args[1]
    if not assetId then log("usage: ncm.dispose <assetId>"); return end
    CreateThread(function()
        local ok, reason = NcmOwnership.dispose(assetId)
        log("dispose %s: %s", assetId, ok and "removed" or tostring(reason))
    end)
end, false)

-- KB-66 / L102. A handler here once granted ownership whenever `/ncm car` issued a car, so a visitor
-- could actually enter a race. It has been REMOVED, and the reason is worth keeping: on a persistent
-- server, a player-invokable command that creates a real, ownable asset is an unmetered faucet, and an
-- economy cannot be built on top of one. Every car must originate in an authorized allocation.
--
-- `ncm.grant` and `ncm.mint` remain, and remain HOST-CONSOLE ONLY (`source == 0`). That is the line:
-- not chat-versus-console, but player-invokable versus operator-invokable. Nothing a player can type
-- may write a row to `vehicle_asset`.
--
-- The onboarding hole this was trying to close is therefore still OPEN, and only the Market closes it.

AddEventHandler("onPlayerDisconnected", function(playerId)
    local driver = NcmCalendar and NcmCalendar.resolveDriver and NcmCalendar.resolveDriver(tonumber(playerId) or 0)
    if driver then NcmOwnership.forget(driver.ncmDriverId) end
end)

AddEventHandler("onResourceStart", function(name)
    if name ~= "ncm_league" then return end
    CreateThread(function()
        -- after migrations have had a chance to run
        for _ = 1, 40 do
            if MySQL.isReady() then break end
            Wait(500)
        end
        pcall(backfillKeys)
    end)
end)

log("ownership ledger ready (asset-keyed, IDEA-157)")
