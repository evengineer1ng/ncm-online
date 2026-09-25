-- engineering.competency -- the first Engineering vertical slice (L120, 21_ENGINEERING_PROPOSAL section 16).
-- The tests that matter here are the invariants, not the arithmetic: the arithmetic is placeholder balance and
-- is expected to change, while the invariants are what the design ruled.
local function E(T) return T.Core.get("engineering.competency") end

return {
    -- ------------------------------------------------------------------ ontology
    the_ontology_is_27_numbers_and_not_a_matrix = function(T)
        local M = E(T)
        T.eq(#M.SKILL_IDS, 15, "fifteen skills a player can hold in their head")
        T.eq(#M.FAMILIES, 12, "twelve mechanical families")
        T.eq(#M.DISCIPLINE_IDS, 5, "five disciplines")
        -- 15 + 12 = 27 bounded values per engineer, forever. A 5x12 matrix would be 180 cells and would make
        -- every new family a schema change.
        T.eq(#M.SKILL_IDS + #M.FAMILIES, 27, "27 numbers, forever")
    end,

    diagnostics_is_allowed_to_break_the_symmetry = function(T)
        local M = E(T)
        -- The owner's condition, 2026-09-23: do not force Diagnostics into workmanship semantics merely to
        -- preserve symmetry. Its axes are information axes.
        T.eq(M.SKILL_AXIS.inspection, "breadth", "")
        T.eq(M.SKILL_AXIS.characterisation, "precision", "")
        T.eq(M.SKILL_AXIS.reverse_engineering, "depth", "")
        -- while a workmanship discipline keeps floor/spread/ceiling
        T.eq(M.SKILL_AXIS.servicing, "floor", "")
        T.eq(M.SKILL_AXIS.fault_correction, "ceiling", "")
        T.eq(M.SKILL_AXIS.restoration, "spread", "")
    end,

    discipline_level_is_derived_and_never_stored = function(T)
        local M = E(T)
        local s = M.newState()
        T.eq(M.disciplineLevel(s, "diagnostics"), 0, "an untouched discipline reads zero, not nil")
        s.skills.inspection = { value = 300, completed = 1 }
        s.skills.characterisation = { value = 150, completed = 1 }
        T.eq(M.disciplineLevel(s, "diagnostics"), 150, "mean of its three skills, computed on demand")
        T.eq(s.disciplines, nil, "and nothing about it is stored")
    end,

    -- ------------------------------------------------------------------ the invariant
    outcome_does_not_gate_credit = function(T)
        local M = E(T)
        -- 21 section 6 calls this the spec's most important invariant. It is satisfied structurally: apply()
        -- has no outcome parameter at all, so a caller CANNOT make credit depend on how well the job went.
        local good = M.newState()
        local bad = M.newState()
        local op = { skillId = "inspection", familyId = "brakes", base = 20, jobLevel = 400, completed = true }
        M.apply(good, op)
        -- the same operation, with every "this went badly" field a caller might invent
        local badOp = { skillId = "inspection", familyId = "brakes", base = 20, jobLevel = 400, completed = true,
                        outcome = "botched", quality = 0, success = false, failed = true }
        M.apply(bad, badOp)
        T.eq(M.valueOf(bad, "inspection"), M.valueOf(good, "inspection"),
             "a poor result still completed the work")
    end,

    credit_accrues_on_completion_never_on_initiation = function(T)
        local M = E(T)
        local s = M.newState()
        local _, deltas, err = M.apply(s, { skillId = "inspection", base = 20, completed = false })
        T.eq(err, "not_completed", "an abandoned operation is named, not silently ignored")
        T.eq(#deltas, 0, "and pays nothing")
        T.eq(M.valueOf(s, "inspection"), 0, "")
    end,

    zero_cost_repeatable_operations_teach_nothing = function(T)
        local M = E(T)
        local s = M.newState()
        local _, _, err = M.apply(s, { skillId = "inspection", base = 0, completed = true })
        T.eq(err, "no_credit", "legitimacy is committed resources plus reaching completion")
        T.eq(M.valueOf(s, "inspection"), 0, "")
    end,

    -- ------------------------------------------------------------------ the curves
    the_ceiling_is_approached_and_never_reached_by_grinding = function(T)
        local M = E(T)
        local s = M.newState()
        -- a thousand generous, always-demanding operations
        for _ = 1, 1000 do
            M.apply(s, { skillId = "inspection", base = 50, jobLevel = M.CEILING, completed = true })
        end
        local v = M.valueOf(s, "inspection")
        T.eq(v < M.CEILING, true, "there is a real summit and grinding does not stand on it")
        T.eq(v > M.CEILING * 0.8, true, "but persistence gets genuinely close")
    end,

    trivial_work_stops_paying_without_anyone_being_told_off = function(T)
        local M = E(T)
        -- The anti-grind mechanism is a CURVE, not a rule. Same operation, same base, different demand.
        local skilled = 600
        local hard = M.difficulty(skilled + 100, skilled)
        local matched = M.difficulty(skilled, skilled)
        local trivial = M.difficulty(0, skilled)
        T.eq(hard, 1.0, "work above your level pays in full")
        T.eq(matched, 1.0, "work at your level pays in full")
        T.eq(trivial <= M.DIFFICULTY_FLOOR, true, "work far below it collapses to the floor")
        T.eq(trivial > 0, true, "but never to exactly nothing -- no cliff, no scolding")
    end,

    headroom_is_monotonic_and_bounded = function(T)
        local M = E(T)
        T.eq(M.headroom(0), 1.0, "a beginner learns fastest")
        T.eq(M.headroom(M.CEILING), 0.0, "at the ceiling there is nothing left to gain")
        T.eq(M.headroom(200) > M.headroom(800), true, "and it only ever decreases")
        T.eq(M.headroom(-50), 1.0, "a nonsense value below zero cannot exceed the maximum")
        T.eq(M.headroom(M.CEILING * 4), 0.0, "nor can one above the ceiling go negative")
    end,

    -- ------------------------------------------------------------------ relevance
    an_operation_credits_its_own_skill_its_siblings_marginally_and_its_family = function(T)
        local M = E(T)
        local s = M.newState()
        M.apply(s, { skillId = "inspection", familyId = "brakes", base = 100, jobLevel = 500, completed = true })

        local own = M.valueOf(s, "inspection")
        local sibling = M.valueOf(s, "characterisation")
        local family = M.valueOf(s, "brakes")
        local unrelated = M.valueOf(s, "forming")
        local otherFamily = M.valueOf(s, "power_unit")

        T.eq(own > 0, true, "the skill the work exercised")
        T.eq(sibling > 0 and sibling < own, true, "its discipline's siblings, marginally")
        T.eq(family > 0, true, "and the mechanical family it was in")
        T.eq(unrelated, 0, "a different discipline learns nothing")
        T.eq(otherFamily, 0, "and so does a family that was not touched")
    end,

    family_experience_is_orthogonal_to_skill = function(T)
        local M = E(T)
        -- The interesting statement "highly developed in Diagnostics -> Reverse Engineering -> Power Unit" is
        -- the COMPOSITION of two stored numbers, never a stored cell.
        local s = M.newState()
        M.apply(s, { skillId = "reverse_engineering", familyId = "power_unit", base = 80, jobLevel = 500, completed = true })
        M.apply(s, { skillId = "servicing", familyId = "power_unit", base = 80, jobLevel = 500, completed = true })
        T.eq(M.valueOf(s, "power_unit") > 0, true, "one family value, fed by any discipline's work in it")
        T.eq(M.valueOf(s, "reverse_engineering") > 0, true, "")
        T.eq(M.valueOf(s, "servicing") > 0, true, "")
        T.eq(s.families.power_unit.completed, 2, "both operations counted toward the same family")
    end,

    -- ------------------------------------------------------------------ gating
    capability_requires_both_knowledge_and_competency = function(T)
        local M = E(T)
        local s = M.newState()
        s.skills.forming = { value = 900, completed = 40 }

        local ok, why = M.canPerform(s, "forming", 500, false)
        T.eq(ok, false, "a master cannot fabricate something they have never seen")
        T.eq(why, "knowledge", "")

        local novice = M.newState()
        ok, why = M.canPerform(novice, "forming", 500, true)
        T.eq(ok, false, "and knowing the design does not confer the hands to build it")
        T.eq(why, "competency", "money cannot buy mastery")

        ok, why = M.canPerform(s, "forming", 500, true)
        T.eq(ok, true, "both halves, or neither")
        T.eq(why, nil, "")
    end,

    -- ------------------------------------------------------------------ refusals
    every_refusal_is_named = function(T)
        local M = E(T)
        local s = M.newState()
        local cases = {
            { { skillId = "carburettor_float_adjustment", base = 10, completed = true }, "unknown_skill" },
            { { skillId = "inspection", familyId = "flux_capacitor", base = 10, completed = true }, "unknown_family" },
            { { skillId = "inspection", base = 0, completed = true }, "no_credit" },
            { { skillId = "inspection", base = 10, completed = false }, "not_completed" },
        }
        for _, c in ipairs(cases) do
            local _, deltas, err = M.apply(s, c[1])
            T.eq(err, c[2], "refusal names itself: " .. c[2])
            T.eq(#deltas, 0, "and changes nothing")
        end
        T.eq(next(s.skills), nil, "a refused operation leaves no partial state behind")
    end,

    deltas_describe_what_changed = function(T)
        local M = E(T)
        local s = M.newState()
        local _, deltas = M.apply(s, { skillId = "inspection", familyId = "brakes", base = 60, jobLevel = 400, completed = true })
        local sawSkill, sawFamily = false, false
        for _, d in ipairs(deltas) do
            T.eq(d.delta > 0, true, "a reported delta actually moved something")
            T.eq(d.value, M.valueOf(s, d.id), "and reports the value the state now holds")
            if d.kind == "skill" then sawSkill = true end
            if d.kind == "family" then sawFamily = true end
        end
        T.eq(sawSkill, true, "hosts get told about skills")
        T.eq(sawFamily, true, "and families, separately, because they persist to different tables")
    end,

    state_is_empty_until_work_happens = function(T)
        local M = E(T)
        local s = M.newState()
        T.eq(next(s.skills), nil, "no pre-seeded rows")
        T.eq(next(s.families), nil, "at most 27 rows per engineer, and zero to start")
        T.eq(M.valueOf(s, "inspection"), 0, "reading an untouched skill is 0, never nil")
        T.eq(M.valueOf(s, "brakes"), 0, "")
    end,
}
