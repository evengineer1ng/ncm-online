return {
    pool_has_sp_classes = function(T)
        local P = T.Core.get("data.vehicle_pool")
        T.eq(#P.classes(), 6); T.ok(P.isClass("Sport") and P.isClass("Bike") and P.isClass("Formula") and not P.isClass("Kart"))
        T.eq(P.records("Formula")[1].id, "Vehicle.v_sport1_rb15_f1", "Formula is the RB15 (mod content, M7-lite)")
        T.ok(#P.records("Sport") >= 3, "sport records present")
        for _, r in ipairs(P.records("Sport")) do T.match(r.id, "^Vehicle%.v_") end
        T.ok(#P.records("Sport", 2) < #P.records("Sport"), "prestige filter narrows")
    end,

    issue_is_deterministic_and_validated = function(T)
        local Pr = T.Core.get("world.provisioning")
        local ids = T.Core.get("vocabulary.ids")
        local a = Pr.issue({ class = "Muscle", rng = ids.seededRng(5) })
        local b = Pr.issue({ class = "Muscle", rng = ids.seededRng(5) })
        T.eq(a.record, b.record); T.eq(a.model, "issued"); T.eq(a.cost, 0); T.ok(ids.isUuid(a.issueId))
        local _, why = Pr.issue({ class = "Hover", rng = ids.seededRng(1) }); T.eq(why, "unknown_class")
        _, why = Pr.issue({ class = "Sport" }); T.eq(why, "rng_required")
        _, why = Pr.issue({ class = "Sport", maxPrestige = 0, rng = ids.seededRng(1) }); T.eq(why, "no_eligible_record")
    end,

    spawn_candidates = function(T)
        local Pr = T.Core.get("world.provisioning")
        local c = Pr.spawnCandidates("Vehicle.v_sport2_quadra_type66")
        T.eq(c[1], "Vehicle.v_sport2_quadra_type66_player"); T.eq(c[2], "Vehicle.v_sport2_quadra_type66")
        T.eq(#Pr.spawnCandidates("Vehicle.v_x_player"), 1)
        T.eq(#Pr.spawnCandidates("Vehicle.v_sport1_rb15_f1"), 1, "mod records spawn exactly as named")
        T.eq(Pr.spawnCandidates("Vehicle.v_sport1_rb15_f1_raven")[1], "Vehicle.v_sport1_rb15_f1_raven")
    end,
}
