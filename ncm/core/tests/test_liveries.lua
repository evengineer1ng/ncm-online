-- data.liveries + the passport: a livery is an APPEARANCE of one model, and it travels in the passport (L338).
return {
    every_built_livery_is_the_rb15 = function(T)
        local L = T.Core.get("data.liveries")
        local Cat = T.Core.get("data.vehicle_catalogue")
        local recs = L.records("ncx_rb15")
        T.eq(#recs, 10)
        for _, r in ipairs(recs) do
            local e = Cat.resolveRecord(r)
            T.truthy(e and e.vehicleKey == "ncx_rb15", r .. " resolves to the RB15 machine model")
        end
        T.eq(Cat.resolveRecord("Vehicle.v_sport1_rb15_f1_kimiko").vehicleKey, "ncx_rb15")
    end,

    the_record_or_the_live_appearance_names_the_livery = function(T)
        local L = T.Core.get("data.liveries")
        T.eq(L.fromRecord("Vehicle.v_sport1_rb15_f1_kimiko").id, "kimiko")
        T.eq(L.fromRecord("Vehicle.v_sport1_rb15_f1", "kimiko").id, "kimiko", "a base RB15 wearing kimiko is the Kimiko car")
        T.eq(L.fromRecord("Vehicle.v_sport1_rb15_f1").id, "stock")
        T.eq(L.fromRecord("Vehicle.v_sport1_rb15_f1_kimiko_ncm_gbx_m7").id, "kimiko", "a gearbox clone keeps its livery")
        T.eq(L.fromRecord("Vehicle.v_sport2_quadra_type66"), nil, "no registry -> the passport knows only what the host says")
    end,

    the_kimiko_passport_is_a_formula_car_with_its_livery_and_no_spaceflight = function(T)
        local L = T.Core.get("data.liveries")
        local P = T.Core.get("machine.passport")
        local pass = P.forMachine("ncx_rb15", "asset-kimiko", { livery = L.appearance(L.fromRecord("Vehicle.v_sport1_rb15_f1_kimiko")) })
        T.eq(P.get(pass, "appearance", "livery"), "kimiko")
        T.eq(P.get(pass, "appearance", "liveryLabel"), "Kimiko Racing · Orbital Air")
        T.eq(P.get(pass, "appearance", "liveryAuthor"), "owner")
        T.truthy(P.get(pass, "appearance", "wing"):find("EVENRAC1NG", 1, true))
        local primary = P.get(pass, "appearance", "primary")
        T.eq(primary[1], 0x0B); T.eq(primary[3], 0x30)
        T.eq(P.get(pass, "appearance", "sourceNexusId"), 31543)
        T.eq(P.get(pass, "morphology", "body"), "formula")
        -- nothing aerospace is inherited from anything: a passport carries no propulsion it was not built with
        for g, t in pairs(pass.groups) do
            for k in pairs(t) do T.falsy(tostring(k):lower():find("thrust") or tostring(k):lower():find("propell"), g .. "." .. k) end
        end
    end,

    an_unknown_record_still_gets_a_passport = function(T)
        local P = T.Core.get("machine.passport")
        local pass = P.forMachine(nil, "asset-x", { tags = { "sport" }, prestige = 4 })
        T.eq(P.get(pass, "morphology", "kind"), "car")
        local _, f = P.get(pass, "character", "perf")
        T.eq(f.src, "inferred")
    end,
}
