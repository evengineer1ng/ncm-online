-- ncm-core module: engineering.competency
--
-- What an engineer can DO. Fifteen skills across five disciplines plus twelve mechanical families -- 27 numbers
-- per engineer, forever (L120). Pure: (state, operation, ctx) -> new state + deltas. No database, no clock, no
-- randomness. It follows `driver.progression` deliberately, because that shape is already proven.
--
-- WHAT THIS IS NOT. Competency is bounded and is not knowledge. Knowledge -- what you know about a particular
-- design -- grows one row per driver x design, has no ceiling, and lives in `competition.machine_knowledge`
-- which already separates source, epistemic status, model identity and asset identity. They are separate
-- tables because one is bounded and one is not (21_ENGINEERING_PROPOSAL section 4). Conflating them is how you
-- end up storing `Makigai KX-17 Pump Skill`.
--
--   **Capability requires BOTH.** The knowledge rung AND the skill level. Neither alone. That is what stops
--   money buying mastery and stops a master fabricating something they have never seen.
--
-- THE INVARIANT THAT MATTERS MOST (21 section 6): **outcome does not gate credit.** A poor result still
-- completed the work. It is satisfied here by simply never passing the outcome into the gain calculation --
-- there is no parameter for it. If a later change adds one, this module has been broken.
--
-- Balance is not decided here. `CEILING`, the headroom exponent and the base rates are placeholders that need
-- play data; they are named constants so a balance pass is one edit and not an archaeology exercise.
local Core = NcmCore

Core.define("engineering.competency", function(C)
    local M = { version = "0.0.1" }

    -- ---------------------------------------------------------------------------------------------
    -- Ontology. Fifteen skills, five disciplines, twelve families (L120, accepted as a shape).
    -- ---------------------------------------------------------------------------------------------

    -- Diagnostics is deliberately NOT floor/spread/ceiling like the workmanship disciplines. It produces
    -- information, not workmanship, so its axes are breadth / precision / depth. The owner's condition,
    -- 2026-09-23: "we should not force Diagnostics into workmanship semantics merely to preserve symmetry."
    M.DISCIPLINES = {
        diagnostics  = { "inspection", "characterisation", "reverse_engineering" },
        repair       = { "servicing", "fault_correction", "restoration" },
        installation = { "fitment", "setup", "validation" },
        fabrication  = { "forming", "process_control", "finishing" },
        design       = { "specification", "tooling", "production" },
    }
    M.DISCIPLINE_IDS = { "diagnostics", "repair", "installation", "fabrication", "design" }

    M.SKILL_AXIS = {
        inspection = "breadth", characterisation = "precision", reverse_engineering = "depth",
        servicing = "floor", fault_correction = "ceiling", restoration = "spread",
        fitment = "floor", setup = "ceiling", validation = "spread",
        forming = "floor", process_control = "spread", finishing = "ceiling",
        specification = "ceiling", tooling = "spread", production = "floor",
    }

    -- The twelve mechanical families, verbatim from 18_PARTS_ECOSYSTEM. Family experience is ORTHOGONAL to
    -- skill: it modifies any discipline's work in that family. Deliberately NOT a 5x12 matrix -- that would be
    -- 180 brittle cells and would make every new family a schema change.
    M.FAMILIES = {
        "power_unit", "cooling", "transmission", "drivetrain", "tires", "brakes",
        "suspension", "steering", "electrical", "aerodynamics", "structure", "chassis",
    }

    M.SKILL_IDS = {}
    for _, d in ipairs(M.DISCIPLINE_IDS) do
        for _, s in ipairs(M.DISCIPLINES[d]) do M.SKILL_IDS[#M.SKILL_IDS + 1] = s end
    end

    M.DISCIPLINE_OF = {}
    for d, skills in pairs(M.DISCIPLINES) do
        for _, s in ipairs(skills) do M.DISCIPLINE_OF[s] = d end
    end

    local FAMILY_SET = {}
    for _, f in ipairs(M.FAMILIES) do FAMILY_SET[f] = true end

    function M.isSkill(id) return M.DISCIPLINE_OF[id] ~= nil end
    function M.isFamily(id) return FAMILY_SET[id] == true end

    -- ---------------------------------------------------------------------------------------------
    -- Balance placeholders. Every one of these needs play data (21 section 7). Named, not scattered.
    -- ---------------------------------------------------------------------------------------------
    M.CEILING = 1000          -- one internal scale, 0..CEILING, NEVER shown raw
    M.HEADROOM_K = 2.0        -- (1 - value/ceiling)^k: asymptotic, so grinding never reaches the summit
    M.RELEVANCE = {
        own = 1.0,            -- the operation's own skill
        sibling = 0.15,       -- its discipline's other skills, marginally
        family = 1.0,         -- the mechanical family the work was in
    }
    -- Work far below current skill pays near nothing. The anti-grind mechanism, and it is a CURVE, not a rule:
    -- repeating trivial operations stops paying without anyone being told off.
    M.DIFFICULTY_SPAN = 250   -- how far below current skill a job may sit before credit collapses
    M.DIFFICULTY_FLOOR = 0.02

    function M.newState()
        return { skills = {}, families = {} }
    end

    local function cell(tbl, id)
        local c = tbl[id]
        if not c then c = { value = 0, completed = 0 }; tbl[id] = c end
        return c
    end

    --- Current value, 0..CEILING. Reading an untouched skill is 0, never nil.
    function M.valueOf(state, id)
        local t = M.isFamily(id) and (state and state.families) or (state and state.skills)
        local c = t and t[id]
        return c and c.value or 0
    end

    --- Asymptotic approach to the ceiling. Never returns above 1, never below 0.
    function M.headroom(value)
        local frac = 1 - (math.max(0, math.min(M.CEILING, value)) / M.CEILING)
        return frac ^ M.HEADROOM_K
    end

    --- How much a job of this difficulty still teaches someone at this skill. `jobLevel` is on the same
    --- internal scale. Above your level pays full; far below pays the floor.
    function M.difficulty(jobLevel, value)
        local gap = (tonumber(jobLevel) or 0) - (tonumber(value) or 0)
        if gap >= 0 then return 1.0 end
        local t = 1 + (gap / M.DIFFICULTY_SPAN)          -- gap is negative
        if t <= 0 then return M.DIFFICULTY_FLOOR end
        return math.max(M.DIFFICULTY_FLOOR, t)
    end

    --- Relevance of one credited id to the operation that was performed.
    function M.relevance(operationSkillId, creditedId)
        if creditedId == operationSkillId then return M.RELEVANCE.own end
        if M.isFamily(creditedId) then return M.RELEVANCE.family end
        local a, b = M.DISCIPLINE_OF[operationSkillId], M.DISCIPLINE_OF[creditedId]
        if a and a == b then return M.RELEVANCE.sibling end
        return 0
    end

    --- Discipline level is DERIVED and never stored (21 section 2). Presentation and coarse gating only.
    function M.disciplineLevel(state, disciplineId)
        local skills = M.DISCIPLINES[disciplineId]
        if not skills then return nil end
        local total = 0
        for _, s in ipairs(skills) do total = total + M.valueOf(state, s) end
        return total / #skills
    end

    --- Apply one COMPLETED operation.
    ---
    --- operation = {
    ---   skillId  = "inspection",        -- required; the skill the work exercised
    ---   familyId = "brakes",            -- optional; the mechanical family it was in
    ---   base     = 12,                  -- required; credit before any modifier. Zero-cost repeatable
    ---                                   -- operations get base = 0 and therefore teach nothing.
    ---   jobLevel = 300,                 -- optional; how demanding the work was, same internal scale
    ---   completed = true,               -- credit accrues ON COMPLETION, never on initiation
    --- }
    ---
    --- There is deliberately NO outcome parameter. A poor result still completed the work.
    function M.apply(state, operation, ctx)
        state = state or M.newState()
        operation = operation or {}
        local deltas = {}

        local skillId = operation.skillId
        if not M.isSkill(skillId) then return state, deltas, "unknown_skill" end
        if operation.completed == false then return state, deltas, "not_completed" end

        local base = tonumber(operation.base) or 0
        if base <= 0 then return state, deltas, "no_credit" end

        local familyId = operation.familyId
        if familyId ~= nil and not M.isFamily(familyId) then return state, deltas, "unknown_family" end

        local jobLevel = tonumber(operation.jobLevel) or 0

        -- Everything this operation could credit: its own skill, its discipline siblings, and its family.
        local credited = { skillId }
        for _, s in ipairs(M.DISCIPLINES[M.DISCIPLINE_OF[skillId]]) do
            if s ~= skillId then credited[#credited + 1] = s end
        end
        if familyId then credited[#credited + 1] = familyId end

        for _, id in ipairs(credited) do
            local rel = M.relevance(skillId, id)
            if rel > 0 then
                local isFam = M.isFamily(id)
                local c = cell(isFam and state.families or state.skills, id)
                local gain = base * rel * M.headroom(c.value) * M.difficulty(jobLevel, c.value)
                if gain > 0 then
                    local before = c.value
                    c.value = math.min(M.CEILING, c.value + gain)
                    c.completed = c.completed + 1
                    deltas[#deltas + 1] = {
                        kind = isFam and "family" or "skill",
                        id = id, delta = c.value - before, value = c.value, completed = c.completed,
                    }
                end
            end
        end

        return state, deltas, nil
    end

    --- Both halves of the gating rule in one place, so no caller can accidentally check only one.
    --- `knowledgeRungMet` is supplied by the knowledge side; this module never reads knowledge itself.
    function M.canPerform(state, skillId, requiredValue, knowledgeRungMet)
        if not M.isSkill(skillId) then return false, "unknown_skill" end
        if knowledgeRungMet == false then return false, "knowledge" end
        if M.valueOf(state, skillId) < (tonumber(requiredValue) or 0) then return false, "competency" end
        return true, nil
    end

    return M
end)
