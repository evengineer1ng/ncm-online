-- engineering.lineage (L321; doc 54 §E; doc 33 §11.3): technology crosses worlds as history. Reverse engineering
-- makes a NEW design point within an error band set by knowledge and competency, bounded by physics, and can fail.
local function mods(T)
    return T.Core.get("engineering.lineage"), T.Core.get("engineering.fixtures"), T.Core.get("vocabulary.hash")
end

local function attempt(reg, src, opts, seed)
    local Hash = opts.Hash
    for i = 1, 50 do
        local o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.rng = Hash.stream("lineage-test", seed, i)
        local r = reg:reverseEngineer(src, o)
        if r then return r end
    end
end

return {
    history_is_a_chain_of_named_relations_across_worlds = function(T)
        local L, F, Hash = mods(T)
        local reg = L.newRegistry()
        local orb = reg:newLineage(F.DESIGNS.main_hydrazine_30k, "snowglobe", "Halo Works")
        T.eq(orb.id, "ORB-THR-01", "a Snowglobe thruster family")
        local nc = attempt(reg, orb.id, { Hash = Hash, knowledge = "specimen", competency = 700, origin = "night_city",
            principal = "Kestrel Garage", intent = "reconstruct" }, "chain")
        T.ok(nc, "a specimen and a good engineer reconstruct it")
        T.eq(nc.id, "NC-THR-01", "a Night City design record, attributed to its reconstructor")
        T.eq(nc.parents[1].relation, "reconstructed_from", "and it says so")
        local nc2 = reg:successor(nc.id, { heatKw = 450 }, "Kestrel Garage")
        T.eq(nc2.lineage, nc.lineage, "a successor stays in its lineage")
        local ls = attempt(reg, nc2.id, { Hash = Hash, knowledge = "observed", competency = 500, origin = "los_santos",
            principal = "Vespucci Aero", intent = "adapt", adaptFor = "rage_sedan" }, "chain-ls")
        T.eq(reg:renderAncestry(ls.id),
            "ORB-THR-01 -> NC-THR-01 (reconstructed_from) -> NC-THR-02 (successor) -> LS-THR-01 (adapted_for)",
            "the ancestry is readable end to end")
        T.eq(reg:get("ORB-THR-01").principal, "Halo Works", "no record is ever rewritten")
        T.falsy(reg:get(ls.id).firstInventor, "there is no first-inventor field")
    end,

    knowledge_and_competency_set_the_error_band_and_failure_is_real = function(T)
        local L, F, Hash = mods(T)
        local reg = L.newRegistry()
        local src = reg:newLineage(F.DESIGNS.main_hydrazine_30k, "snowglobe", "Halo Works")
        local function survey(knowledge, competency)
            local fails, errSum, n = 0, 0, 0
            for i = 1, 200 do
                local r = reg:reverseEngineer(src.id, { knowledge = knowledge, competency = competency,
                    rng = Hash.stream("survey", knowledge, competency, i), origin = "night_city" })
                if r then
                    n = n + 1
                    errSum = errSum + math.abs(r.design.perf.thrustN / 30000 - 1)
                    T.ok(r.design.perf.ispS <= L.ISP_CEILING.hydrazine, "no copy beats chemistry")
                else fails = fails + 1 end
            end
            return fails / 200, n > 0 and errSum / n or 1
        end
        local fGood, eGood = survey("documents", 900)
        local fBad, eBad = survey("rumour", 100)
        T.ok(eGood < 0.05, "drawings and a master engineer: within a few percent")
        T.ok(eBad > 3 * eGood, "a rumour and a novice: far off")
        T.ok(fBad > 0.4, "and usually nothing usable at all")
        T.ok(fGood < 0.1, "while the master rarely fails")
    end,

    the_same_seed_gives_the_same_copy = function(T)
        local L, F, Hash = mods(T)
        local function run()
            local reg = L.newRegistry()
            local src = reg:newLineage(F.DESIGNS.rcs_n2_400, "los_santos", "Vespucci Aero")
            local r, why = reg:reverseEngineer(src.id, { knowledge = "measured", competency = 600,
                rng = Hash.stream("same", 1), origin = "snowglobe" })
            return r and r.design.perf.thrustN or why.reason
        end
        T.eq(run(), run(), "reverse engineering is seeded, not random")
    end,

    unknown_relations_and_parents_are_refused = function(T)
        local L, F = mods(T)
        local reg = L.newRegistry()
        T.errors(function() reg:add({ design = F.DESIGNS.rcs_n2_400, origin = "night_city", parents = { { id = "nope", relation = "derived_from" } } }) end,
            "unknown parent", "a parent must exist")
        local a = reg:newLineage(F.DESIGNS.rcs_n2_400, "night_city", "x")
        T.errors(function() reg:add({ design = F.DESIGNS.rcs_n2_400, origin = "night_city", parents = { { id = a.id, relation = "stolen" } } }) end,
            "unknown relation", "relations are declared")
    end,
}
