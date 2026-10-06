-- ncm-core module: data.vehicle_assets
--
-- IDEA-157. A garage is a set of PHYSICAL EXAMPLES, not a set of titles.
--
-- `owned_vehicle` was keyed `(driver, server, record)` -- one row per model -- so a driver could own "a
-- Caliburn" but never "two Caliburns", and the second one would silently overwrite the first. Spec 2's whole
-- individuality model (a machine with its own history, mileage, damage, provenance and eventual sale) needs the
-- opposite: a row per example, each with a durable id that survives being traded, re-liveried or renamed
-- upstream.
--
-- The three identifiers stay separate, exactly as 13_VEHICLE_COLLECTION.md requires and for the reasons it
-- gives:
--
--   assetId     this physical example. Permanent. Survives transfer.
--   vehicleKey  the conceptual machine. Survives a TweakDB record being renamed by a mod update.
--   record      the exact runtime record. Still the spawn / eligibility / performance key.
--
-- Collapsing any two of them loses something that cannot be reconstructed later, so nothing here ever derives
-- one from another destructively: `record` is carried on every row precisely so the existing eligibility
-- consumers keep working unchanged.
--
-- Pure: rows come from the host's database, ordering and vocabulary come from the pool and the catalogue.
local Core = NcmCore

Core.define("data.vehicle_assets", function(C)
    local M = { version = "0.0.1" }
    local pool = C.get("data.vehicle_pool")
    local catalogue = C.get("data.vehicle_catalogue")

    local function isRow(r)
        return type(r) == "table" and type(r.record) == "string" and r.record ~= ""
    end

    --- The durable identity for a runtime record, or nil when the catalogue does not know it (an authored or
    --- team car). A row's STORED key always wins: it was resolved when the asset was minted, and if a mod
    --- update later renames the record out from under us, the stored key is the only thing that still knows
    --- what the machine was.
    function M.keyFor(row)
        if type(row) == "table" and type(row.vehicleKey) == "string" and row.vehicleKey ~= "" then
            return row.vehicleKey
        end
        local record = type(row) == "table" and row.record or row
        local e = catalogue.resolveRecord(record)
        return e and e.vehicleKey or nil
    end

    --- Present a driver's assets: pool order first (so a garage listing reads in the same order as everything
    --- else), then anything the pool does not know, then stable by assetId so two examples of one car never
    --- swap places between reads.
    ---
    --- Every returned row carries `record`, which is what keeps `competition.eligibility` and the Guide working
    --- across this migration without being touched.
    function M.shape(rows)
        local byRecord = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            if isRow(r) then
                local bucket = byRecord[r.record]
                if not bucket then bucket = {}; byRecord[r.record] = bucket end
                bucket[#bucket + 1] = r
            end
        end
        for _, bucket in pairs(byRecord) do
            table.sort(bucket, function(a, b)
                local ka, kb = tostring(a.assetId or ""), tostring(b.assetId or "")
                if ka ~= kb then return ka < kb end
                return tostring(a.acquiredAt or 0) < tostring(b.acquiredAt or 0)
            end)
        end

        local out = {}
        local function emit(record, meta)
            local bucket = byRecord[record]
            if not bucket then return end
            local entry = catalogue.resolveRecord(record)
            for _, r in ipairs(bucket) do
                out[#out + 1] = {
                    assetId     = r.assetId,
                    record      = record,
                    vehicleKey  = M.keyFor(r),
                    class       = meta and table.concat(meta.classes, "/") or "Other",
                    prestige    = meta and meta.prestige or 0,
                    displayName = entry and entry.displayName or nil,
                    manufacturer = entry and entry.manufacturer or nil,
                    acquiredVia = r.acquiredVia,
                    acquiredAt  = r.acquiredAt,
                    gearbox     = r.gearbox,     -- machine.gearbox (L306), when the caller read it
                }
            end
            byRecord[record] = nil
        end

        for _, meta in ipairs(pool.allRecords()) do emit(meta.id, meta) end
        -- Records owned but not in the pool (an authored or team car) still belong in the garage. Sorted, so
        -- the tail of the list is as stable as the head.
        local leftovers = {}
        for record in pairs(byRecord) do leftovers[#leftovers + 1] = record end
        table.sort(leftovers)
        for _, record in ipairs(leftovers) do emit(record, nil) end
        return out
    end

    --- Distinct runtime records, in `shape` order.
    ---
    --- This is the one every eligibility caller wants, and the reason it exists is a defect this migration
    --- would otherwise have introduced: `Eligibility.eligibleOwned` counts the ids it is handed, so passing two
    --- examples of one legal car would report "you own 2 eligible cars" for what is, to a championship, one
    --- entry. Owning a second Caliburn must not look like owning a second option.
    function M.records(rows)
        local seen, out = {}, {}
        for _, r in ipairs(M.shape(rows)) do
            if not seen[r.record] then
                seen[r.record] = true
                out[#out + 1] = r.record
            end
        end
        return out
    end

    --- Distinct vehicleKeys owned, as a set. What the Collection means by OWNED: a driver with three of one
    --- machine has completed one slot, not three.
    function M.keys(rows)
        local set = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            if isRow(r) then
                local key = M.keyFor(r)
                if key then set[key] = true end
            end
        end
        return set
    end

    --- How many physical examples of each record. `{}` for an empty garage, never nil.
    function M.countByRecord(rows)
        local counts = {}
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            if isRow(r) then counts[r.record] = (counts[r.record] or 0) + 1 end
        end
        return counts
    end

    --- How many of a driver's assets came by a given route (`seed`, `purchase`, `prize`...).
    function M.countVia(rows, via)
        local n = 0
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            if isRow(r) and r.acquiredVia == via then n = n + 1 end
        end
        return n
    end

    --- A one-line garage summary that distinguishes examples from models, because after this migration those
    --- are different numbers and a listing that shows only one of them is misleading.
    function M.describe(rows)
        local shaped = M.shape(rows)
        local models = #M.records(rows)
        if #shaped == 0 then return "Garage: empty." end
        if #shaped == models then
            return ("Garage: %d vehicle(s)."):format(#shaped)
        end
        return ("Garage: %d vehicle(s) across %d model(s)."):format(#shaped, models)
    end

    return M
end)
