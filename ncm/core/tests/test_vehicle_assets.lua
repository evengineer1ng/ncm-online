-- IDEA-157: a garage is physical examples, not titles. The cases that matter are the ones the old
-- record-keyed table could not express at all.
local CALIBURN = "Vehicle.v_sport1_rayfield_caliburn"

local function assets(...)
    local out = {}
    for _, r in ipairs({ ... }) do out[#out + 1] = r end
    return out
end

return {
    two_examples_of_one_car_are_two_rows = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local rows = assets(
            { assetId = "a2", record = CALIBURN, acquiredAt = 200 },
            { assetId = "a1", record = CALIBURN, acquiredAt = 100 })
        local shaped = A.shape(rows)
        T.eq(#shaped, 2, "the thing owned_vehicle could not represent")
        T.eq(shaped[1].assetId, "a1"); T.eq(shaped[2].assetId, "a2")
        T.eq(shaped[1].record, CALIBURN, "record survives on every row, so eligibility keeps working")
        T.eq(A.countByRecord(rows)[CALIBURN], 2)
    end,

    -- The defect this migration would otherwise have introduced.
    a_second_example_is_not_a_second_option = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local rows = assets(
            { assetId = "a1", record = CALIBURN },
            { assetId = "a2", record = CALIBURN },
            { assetId = "a3", record = CALIBURN })
        T.eq(#A.shape(rows), 3, "three machines")
        T.eq(#A.records(rows), 1, "one option, as far as a championship is concerned")
        local keys = A.keys(rows)
        local n = 0
        for _ in pairs(keys) do n = n + 1 end
        T.eq(n, 1, "and one Collection slot, not three")
    end,

    eligibility_still_sees_plain_record_ids = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local E = T.Core.get("competition.eligibility")
        local P = T.Core.get("data.vehicle_pool")
        local sport = P.records("Sport")
        T.ok(#sport >= 2, "need two sport records for this test")
        local rows = assets(
            { assetId = "a1", record = sport[1].id },
            { assetId = "a2", record = sport[1].id },
            { assetId = "a3", record = sport[2].id })
        local ids = A.records(rows)
        T.eq(#ids, 2, "duplicates collapsed before eligibility ever sees them")
        local spec = { classes = { "Sport" } }
        T.eq(#E.eligibleOwned(spec, ids), 2, "owning a spare must not inflate the eligible count")
    end,

    stored_vehicle_key_wins_over_the_live_catalogue = function(T)
        local A = T.Core.get("data.vehicle_assets")
        -- A mod update renamed the record; the asset still knows what machine it is. This is the whole reason
        -- vehicleKey is stored on the row instead of being derived on every read.
        local row = { assetId = "a1", record = "Vehicle.v_renamed_by_a_mod_update", vehicleKey = "ncx_rb15" }
        T.eq(A.keyFor(row), "ncx_rb15")
        T.eq(A.shape({ row })[1].vehicleKey, "ncx_rb15")
    end,

    an_unknown_record_still_resolves_its_key_when_it_can = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local C = T.Core.get("data.vehicle_catalogue")
        local known = C.entries()[1]
        local record = known.runtimeRecords[1]
        record = type(record) == "table" and record.record or record
        T.eq(A.keyFor({ record = record }), known.vehicleKey, "no stored key: fall back to the catalogue")
        T.eq(A.keyFor({ record = "Vehicle.v_not_a_real_thing" }), nil, "and nil rather than a guess")
    end,

    ordering_is_pool_order_then_sorted_leftovers = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local P = T.Core.get("data.vehicle_pool")
        local first = P.allRecords()[1].id
        local rows = assets(
            { assetId = "z", record = "Vehicle.v_zzz_authored" },
            { assetId = "m", record = "Vehicle.v_mmm_authored" },
            { assetId = "p", record = first })
        local shaped = A.shape(rows)
        T.eq(shaped[1].record, first, "pool records lead, in pool order")
        T.eq(shaped[2].record, "Vehicle.v_mmm_authored", "then leftovers, sorted")
        T.eq(shaped[3].record, "Vehicle.v_zzz_authored")
        T.eq(shaped[2].class, "Other", "a record the pool does not know is not given a class it has not got")
    end,

    -- Provenance is countable per route. Not decoration: supply observability (IDEA-155) needs it, and it is
    -- what would let every host-seeded car be swept the day real supply lands without touching an earned or
    -- purchased one. L102: nothing a PLAYER can type may create an asset, so `seed` should only ever appear
    -- against an operator console grant.
    provenance_is_countable_per_route = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local rows = assets(
            { assetId = "s1", record = "Vehicle.v_a", acquiredVia = "seed" },
            { assetId = "s2", record = "Vehicle.v_b", acquiredVia = "seed" },
            { assetId = "p1", record = "Vehicle.v_c", acquiredVia = "purchase" },
            { assetId = "w1", record = "Vehicle.v_d", acquiredVia = "prize" })
        T.eq(A.countVia(rows, "seed"), 2)
        T.eq(A.countVia(rows, "purchase"), 1)
        T.eq(A.countVia(rows, "prize"), 1)
        T.eq(A.countVia(rows, "progression"), 0, "a route nobody has used counts zero, never nil")
        T.eq(A.countVia(nil, "seed"), 0)
        T.eq(A.countVia(rows, nil), 0, "rows with a via are not matched by no via")
    end,

    an_empty_garage_is_empty_tables_never_nil = function(T)
        local A = T.Core.get("data.vehicle_assets")
        T.eq(#A.shape(nil), 0); T.eq(#A.shape({}), 0); T.eq(#A.records({}), 0)
        local keys, counts = A.keys(nil), A.countByRecord(nil)
        for _ in pairs(keys) do T.ok(false, "expected no keys") end
        for _ in pairs(counts) do T.ok(false, "expected no counts") end
        T.eq(A.describe({}), "Garage: empty.")
    end,

    junk_rows_are_dropped_not_rendered = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local rows = assets({ assetId = "a" }, "nonsense", { record = "" }, { assetId = "b", record = CALIBURN })
        T.eq(#A.shape(rows), 1, "a row with no record is not an asset")
        T.eq(A.shape(rows)[1].assetId, "b")
    end,

    describe_distinguishes_examples_from_models = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local one = assets({ assetId = "a1", record = CALIBURN })
        T.eq(A.describe(one), "Garage: 1 vehicle(s).")
        local two = assets({ assetId = "a1", record = CALIBURN }, { assetId = "a2", record = CALIBURN })
        T.match(A.describe(two), "2 vehicle%(s%) across 1 model%(s%)",
            "after this migration those are different numbers and both belong in the readout")
    end,

    shape_does_not_mutate_its_input = function(T)
        local A = T.Core.get("data.vehicle_assets")
        local row = { assetId = "a1", record = CALIBURN, acquiredAt = 7 }
        local rows = { row }
        A.shape(rows); A.records(rows); A.keys(rows)
        T.eq(#rows, 1); T.eq(row.assetId, "a1"); T.eq(row.vehicleKey, nil)
        T.eq(row.class, nil, "enrichment belongs on the returned view, not on the caller's row")
    end,
}
