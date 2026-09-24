return {
    -- This is the gate the runtime deliberately does NOT enforce with an error: the module collects authoring
    -- faults instead of raising, because raising would take the whole league service down at resource start.
    -- That trade is only safe if the faults fail here, loudly, where they cost nothing to fix.
    ["every pool record is named, and nothing is claimed twice"] = function(T)
        local cat = T.Core.get("data.vehicle_catalogue")
        T.eq(table.concat(cat.unmapped(), ", "), "")
        T.eq(table.concat(cat.conflicts(), "; "), "")
        T.eq(cat.count(), #T.Core.get("data.vehicle_pool").allRecords())
    end,

    ["vehicleKey is unique across the catalogue"] = function(T)
        local cat = T.Core.get("data.vehicle_catalogue")
        local seen = {}
        for _, e in ipairs(cat.entries()) do
            T.eq(seen[e.vehicleKey], nil)
            seen[e.vehicleKey] = true
            T.eq(cat.byKey(e.vehicleKey), e)   -- every entry is reachable by its own key
        end
    end,

    ["every catalogue entry is fully named"] = function(T)
        for _, e in ipairs(T.Core.get("data.vehicle_catalogue").entries()) do
            T.neq(e.displayName, nil)
            T.neq(e.manufacturer, nil)
            T.neq(e.category, nil)
            T.eq(type(e.categories), "table")
        end
    end,

    ["runtime identity and conceptual identity remain separate"] = function(T)
        local cat = T.Core.get("data.vehicle_catalogue")
        local e = cat.resolveRecord("Vehicle.v_sport1_rb15_f1_arasaka")
        T.eq(e.vehicleKey, "ncx_rb15")
        T.neq(e.vehicleKey, e.runtimeRecords[1])
        -- base, _player and every team livery are ONE machine, not eleven
        T.eq(cat.resolveRecord("Vehicle.v_sport1_rb15_f1"), e)
        T.eq(cat.resolveRecord("Vehicle.v_sport1_rb15_f1_player"), e)
        T.eq(cat.resolveRecord("Vehicle.v_sport1_rb15_f1_militech"), e)
        -- a live OPEN//77 vehicle id is not an identity and must never resolve to one
        T.eq(cat.resolveRecord("77"), nil)
        T.eq(cat.resolveRecord(77), nil)
        T.eq(cat.resolveRecord(nil), nil)
    end,

    ["base and _player records agree for every machine"] = function(T)
        local cat, pool = T.Core.get("data.vehicle_catalogue"), T.Core.get("data.vehicle_pool")
        for _, p in ipairs(pool.allRecords()) do
            local base = cat.resolveRecord(p.id)
            T.neq(base, nil)
            T.eq(cat.resolveRecord(p.id .. "_player"), base)
        end
    end,

    -- A multi-class machine (the Colby pickup is Muscle AND Nomad) must not have a headline category that
    -- depends on table iteration order, or the same car reads as a different kind of thing between boots.
    ["a multi-class machine has a stable headline category and keeps every class"] = function(T)
        local cat = T.Core.get("data.vehicle_catalogue")
        local e = cat.resolveRecord("Vehicle.v_standard25_thorton_colby_pickup")
        T.neq(e, nil)
        T.eq(e.category, e.categories[1])
        T.eq(#e.categories > 1, true)
        local again = T.Core.get("data.vehicle_catalogue").resolveRecord("Vehicle.v_standard25_thorton_colby_pickup")
        T.eq(again.category, e.category)
    end,

    ["slots are unique, stable and carry the generation"] = function(T)
        local cat = T.Core.get("data.vehicle_catalogue")
        local seen = {}
        for _, e in ipairs(cat.entries()) do
            local slot = cat.slot(e)
            T.eq(seen[slot], nil)
            seen[slot] = true
            T.eq(slot:sub(1, 2), "g" .. tostring(cat.generation))
            T.eq(cat.slot(e), slot)   -- asking twice gives the same answer
        end
    end,

    ["the modded machine is marked as modded and the native ones are not"] = function(T)
        local cat = T.Core.get("data.vehicle_catalogue")
        T.eq(cat.byKey("ncx_rb15").source, "mod")
        T.eq(cat.byKey("makigai_maimai").source, "native")
    end,
}
