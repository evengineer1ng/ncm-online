-- engineering.projects (L361): the Workshop -- teardown, fabricate, promote, run, and the engineer's competency.
local function mods(T)
    local C = T.Core
    return C.get("engineering.projects"), C.get("engineering.installation"), C.get("engineering.competency"), C.get("vocabulary.hash")
end

local function design(T, code)
    local _, I = mods(T)
    for _, d in ipairs(I.DESIGNS) do if d.code == code then return d end end
end

local function rng(T, ...) local _, _, _, H = mods(T); return H.stream("test-workshop", ...) end

-- an engineer with `rev` reverse-engineering skill and `fab` in every fabrication skill
local function engineer(T, rev, fab, prod)
    local _, _, Comp = mods(T)
    local s = Comp.newState()
    s.skills.reverse_engineering = { value = rev or 0, completed = 1 }
    for _, k in ipairs({ "forming", "process_control", "finishing" }) do s.skills[k] = { value = fab or 0, completed = 1 } end
    s.skills.production = { value = prod or 0, completed = 1 }
    return s
end

return {
    a_new_engineer_only_reaches_the_surface_and_learning_takes_them_deeper = function(T)
        local P, _, Comp = mods(T)
        local s = Comp.newState()
        T.eq(P.depth(s), 1, "untrained: dimensions, mass and materials only")
        local fd = design(T, "ZTC-FD1")
        local stages = {}
        for i = 1, 4 do
            stages[i] = P.depth(s)
            P.applyCredit(s, "teardown", { stages = stages[i], family = fd.family, jobLevel = 300 })
        end
        T.ok(stages[2] >= 2 and stages[3] >= 3 and stages[4] == 4,
            ("each teardown teaches: stages reached %d, %d, %d, %d"):format(stages[1], stages[2], stages[3], stages[4]))
    end,

    a_teardown_reveals_true_numbers_inside_the_band_and_deeper_stages_reveal_more = function(T)
        local P = mods(T)
        local fd = design(T, "ZTC-FD1")
        local shallow = P.reveal(fd, 1, 0, rng(T, "shallow"))
        local deep = P.reveal(fd, 4, 500, rng(T, "deep"))
        T.ok(shallow.massKg and not shallow.thrustN, "stage 1: mass, not thrust")
        T.ok(deep.thrustN and deep.process and deep.principles, "stage 4: ratings, method and principles")
        local err = math.abs(deep.thrustN.value / fd.perf.thrustN - 1)
        T.ok(err < 4 * deep.thrustN.band, ("thrust read within the band (%.3f, band %.3f)"):format(err, deep.thrustN.band))
        T.eq(deep.propellant.value, "fusion", "words come back as they are")
    end,

    fabrication_needs_the_method_and_makes_a_physical_thing_either_way = function(T)
        local P = mods(T)
        local fd = design(T, "ZTC-FD1")
        local none, why = P.fabricate(fd, 2, engineer(T, 100, 0), rng(T, "early"))
        T.ok(not none and why == "knowledge", "stage 2 is not enough to build one")
        local classes = {}
        for i = 1, 60 do
            local r = P.fabricate(fd, 3, engineer(T, 100, 0), rng(T, "fab", i), { makerKey = "p:test" })
            classes[r.class] = (classes[r.class] or 0) + 1
            if r.class ~= "junk" then T.ok(P.valid(r.spec), "a working prototype is valid physics") end
        end
        T.ok((classes.junk or 0) > 0 and (classes.poor or 0) + (classes.neutral or 0) + (classes.good or 0) > 30,
            ("60 attempts: junk %d poor %d neutral %d good %d"):format(classes.junk or 0, classes.poor or 0, classes.neutral or 0, classes.good or 0))
    end,

    skill_makes_fabrication_more_reliable = function(T)
        local P = mods(T)
        local fd = design(T, "ZTC-FD1")
        local function junk(fab)
            local n = 0
            for i = 1, 200 do if P.fabricate(fd, 3, engineer(T, 100, fab), rng(T, "rel", fab, i)).class == "junk" then n = n + 1 end end
            return n
        end
        local novice, master = junk(0), junk(900)
        T.ok(master < novice, ("junk in 200: novice %d, master %d"):format(novice, master))
    end,

    the_same_seed_builds_the_same_prototype = function(T)
        local P = mods(T)
        local fd = design(T, "ZTC-FD1")
        local a = P.fabricate(fd, 4, engineer(T, 300, 200), rng(T, "same"))
        local b = P.fabricate(fd, 4, engineer(T, 300, 200), rng(T, "same"))
        T.eq(a.class, b.class)
        if a.spec then T.eq(a.spec.perf.thrustN, b.spec.perf.thrustN, "deterministic per seed") end
    end,

    promotion_needs_complete_knowledge_and_a_working_prototype = function(T)
        local P = mods(T)
        T.ok(not P.canPromote("junk", 4), "junk cannot become a design")
        T.ok(not P.canPromote("good", 3), "the method is not the principles")
        T.ok(P.canPromote("poor", 4), "a poor but working prototype can be promoted: it is yours to improve")
    end,

    production_skill_cuts_rejects = function(T)
        local P = mods(T)
        local function rejects(prod)
            local n = 0
            for i = 1, 100 do
                local units = P.run(3, engineer(T, 0, 0, prod), rng(T, "run", prod, i))
                for _, u in ipairs(units) do if u == "reject" then n = n + 1 end end
            end
            return n
        end
        local a, b = rejects(0), rejects(900)
        T.ok(b < a and a > 30, ("rejects in 300 units: novice %d, master %d"):format(a, b))
        T.eq(#P.run(9, engineer(T)), P.RUN_MAX, "a run is capped")
    end,

    credit_never_reads_the_outcome = function(T)
        local P = mods(T)
        for _, kind in ipairs({ "teardown", "fabricate", "promote", "run" }) do
            for _, op in ipairs(P.credit(kind, { stages = 2, n = 2, family = "propulsor" })) do
                T.ok(op.outcome == nil and op.completed == true and op.base > 0, kind .. ": credit for completed work only")
            end
        end
    end,

    materials_and_minutes = function(T)
        local P = mods(T)
        local fd = design(T, "ZTC-FD1")
        T.eq(P.cost("fabricate", 48000), 19200, "fabrication materials are 40 % of the source's price")
        T.ok(P.cost("teardown", 100) >= 10, "never free")
        local s = P.duration("teardown", fd.massKg, { stages = 4 })
        T.ok(s >= 5 * 60 and s <= 15 * 60, ("a full FD-1 teardown takes %d min"):format(math.floor(s / 60)))
        local f = P.duration("fabricate", fd.massKg)
        T.ok(f >= 10 * 60 and f <= 30 * 60, ("fabricating an FD-1 takes %d min"):format(math.floor(f / 60)))
        T.ok(P.duration("run", 10, { n = 3 }) > P.duration("run", 10, { n = 1 }), "more units take longer")
        T.eq(P.duration("fabricate", fd.massKg, { timeScale = 0.01 }), math.floor(f * 0.01 + 0.5), "a development time scale")
    end,

    the_engineer_card_is_words_not_numbers = function(T)
        local P = mods(T)
        local card = P.card(engineer(T, 250, 600))
        for _, d in ipairs(card.disciplines) do T.ok(type(d.word) == "string" and not d.word:find("%d"), d.id .. ": " .. d.word) end
        T.eq(card.depth, 4)
    end,
}
