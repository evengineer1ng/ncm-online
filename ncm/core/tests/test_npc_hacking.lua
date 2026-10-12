-- npc.hacking + competition.hackrules (owner brief 2026-10-08): quickhacking is racecraft for the whole field. The
-- invariants: racers are persistently different hackers; a hack is a decision with reasons, not a dice roll; the
-- weakest sufficient tool is chosen and destruction needs a racer willing to destroy; timing is skilled but never
-- perfect; defence exists and can pre-empt an attack; NPCs fight NPCs with no human involved.
local function H(T) return T.Core.get("npc.hacking") end
local function R(T) return T.Core.get("competition.hackrules") end
local function A(T) return T.Core.get("paddock.attributes") end
local function Hash(T) return T.Core.get("vocabulary.hash") end

local function person(T, i)
    local rng = Hash(T).stream("test-hack-people", i)
    return { id = ("p%05d"):format(i), attrs = A(T).rollDriver(rng, "street", 28), personality = A(T).personality("seed-x", ("p%05d"):format(i)) }
end

local function prof(over)
    local p = { aptitude = 0.9, offense = 0.9, defense = 0.6, sabotage = 0.9, maxSeverity = 5, patience = 0.2, timing = 0.95,
                targetQuality = 0.95, risk = 0.7, retaliation = 0.6, conservation = 0.2, regulatoryAwareness = 0.5,
                perceptionMs = 500, hasIce = true, canPurge = true, stealth = 0.5, hackedBy = {} }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end

local function ops(actions, op)
    local out = {}
    for _, a in ipairs(actions) do if a.op == op then out[#out + 1] = a end end
    return out
end

local RIVAL = function(over)
    local o = { id = "p00002", vid = 222, human = false, bound = false, dist = 20, gapM = 15, closingMps = 0, pos = 3 }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
end

return {
    racers_are_persistently_different_hackers = function(T)
        local M = H(T)
        local floor, rare, defenders, killers, n = 0, 0, 0, 0, 300
        for i = 1, n do
            local a, b = M.profile(person(T, i), "seed-x"), M.profile(person(T, i), "seed-x")
            T.eq(a.aptitude, b.aptitude, "same racer, same aptitude")
            T.eq(a.maxSeverity, b.maxSeverity, "same racer, same limits")
            if a.aptitude < M.HACKER_FLOOR then floor = floor + 1 end
            if a.aptitude > 0.8 then rare = rare + 1 end
            if a.defense > 0.6 then defenders = defenders + 1 end
            if a.maxSeverity >= 5 then killers = killers + 1 end
        end
        T.ok(floor > n * 0.35, ("many racers essentially never hack (%d/%d)"):format(floor, n))
        T.ok(rare >= 1 and rare < n * 0.12, ("a frighteningly good netrunner is rare (%d/%d)"):format(rare, n))
        T.ok(defenders >= 5, ("some are strong defenders (%d)"):format(defenders))
        T.ok(killers < n * 0.15, ("few are willing to destroy a car (%d/%d)"):format(killers, n))
    end,

    history_bends_the_profile = function(T)
        local M = H(T)
        local base = M.profile(person(T, 7), "seed-x")
        local p = person(T, 7)
        p.evidence = {}
        for _ = 1, 10 do M.remember(p.evidence, "received", "p00042") end
        local bent = M.profile(p, "seed-x")
        T.ok(bent.defense > base.defense, "being hacked repeatedly makes a racer more defensive")
        T.eq(bent.hackedBy["p00042"], 10, "and it remembers who")
    end,

    a_non_hacker_never_starts_an_upload = function(T)
        local M = H(T)
        local ag = M.newAgent("p00001", prof({ aptitude = 0.05 }), { seed = "r1" })
        for t = 0, 60000, 250 do
            local acts = M.step(ag, { nowMs = t, phase = "racing", rules = "allowed", others = { RIVAL() } })
            T.eq(#ops(acts, "start"), 0, "never")
        end
    end,

    the_weakest_sufficient_hack_and_destruction_needs_willingness = function(T)
        local M = H(T)
        local mild = M.newAgent("p00001", prof({ maxSeverity = 2 }), { seed = "r2" })
        local seen = {}
        for t = 0, 120000, 250 do
            for _, a in ipairs(ops(M.step(mild, { nowMs = t, phase = "final", rules = "allowed", others = { RIVAL({ dist = 15, gapM = 10 }) } }), "start")) do
                seen[a.hack] = true
                M.outcome(mild, "impact", t)
            end
        end
        T.falsy(seen.total_failure, "a racer who refuses destruction never uploads TOTAL FAILURE")
        T.falsy(seen.tire_sabotage, "nor anything above their limit")
        T.ok(next(seen) ~= nil, "but does use mild interference")
    end,

    a_decision_has_reasons = function(T)
        local M = H(T)
        local ag = M.newAgent("p00001", prof(), { seed = "r3" })
        local start
        for t = 0, 20000, 250 do
            start = start or ops(M.step(ag, { nowMs = t, phase = "racing", rules = "allowed", others = { RIVAL() } }), "start")[1]
        end
        T.ok(start ~= nil, "a keen hacker attacks the car just ahead")
        T.ok(start.why:find("attacking", 1, true) ~= nil and start.why:find("utility", 1, true) ~= nil, "and says why: " .. tostring(start and start.why))
        T.eq(start.targetVid, 222, "on that car")
    end,

    on_the_grid_a_skilled_hacker_times_the_impact_for_the_green = function(T)
        local M = H(T)
        local green = 30000
        local ag = M.newAgent("p00001", prof({ timing = 1.0, maxSeverity = 5 }), { seed = "r4" })
        local start
        for t = 0, 40000, 100 do
            local a = ops(M.step(ag, { nowMs = t, phase = t < green and "grid" or "racing", greenAtMs = green, rules = "allowed",
                                       others = { RIVAL({ dist = 6, gapM = 3 }) } }), "start")[1]
            if a and not start then start = { t = t, hack = a.hack } end
        end
        T.ok(start ~= nil, "it uploads")
        local up = T.Core.get("competition.chrome").hack(start.hack).uploadMs
        local impact = start.t + up
        T.ok(math.abs(impact - green) <= 1500, ("impact lands near the green (%+d ms)"):format(impact - green))
    end,

    defence_pre_empts_and_aborts_an_own_upload = function(T)
        local M = H(T)
        local ag = M.newAgent("p00002", prof({ perceptionMs = 300 }), { seed = "r5" })
        ag.upload = { hack = "engine_cut", target = "p00001", startedMs = 0 }
        local incoming = { { key = "u1", attacker = "p00001", hack = "total_failure", startedMs = 0, uploadMs = 8000 } }
        local purged, cancelled
        for t = 0, 8000, 100 do
            local acts = M.step(ag, { nowMs = t, phase = "racing", rules = "allowed", others = { RIVAL({ id = "p00001", vid = 111 }) }, incoming = incoming })
            purged = purged or ops(acts, "purge")[1]
            cancelled = cancelled or ops(acts, "cancel")[1]
        end
        T.ok(purged ~= nil, "it purges an incoming TOTAL FAILURE")
        T.ok(cancelled ~= nil and cancelled.why:find("defend", 1, true) ~= nil, "abandoning its own upload to save itself")
    end,

    a_poor_defender_can_miss_it_entirely = function(T)
        local M = H(T)
        local missed = 0
        for i = 1, 40 do
            local ag = M.newAgent("p" .. i, prof({ defense = 0.0, canPurge = true, perceptionMs = 2600 }), { seed = "r6" })
            local any = false
            for t = 0, 8000, 200 do
                if #ops(M.step(ag, { nowMs = t, phase = "racing", rules = "allowed", others = {},
                    incoming = { { key = "u", attacker = "x", hack = "tire_sabotage", startedMs = 0, uploadMs = 3000 } } }), "purge") > 0 then any = true end
            end
            if not any then missed = missed + 1 end
        end
        T.ok(missed >= 20, ("weak defenders mostly fail to respond (%d/40)"):format(missed))
    end,

    npc_against_npc_with_no_human_anywhere = function(T)
        local M = H(T)
        local a = M.newAgent("p00001", prof(), { seed = "duel" })
        local b = M.newAgent("p00002", prof({ offense = 0.95, maxSeverity = 3 }), { seed = "duel" })
        local aStart, bStart
        for t = 0, 30000, 250 do
            aStart = aStart or ops(M.step(a, { nowMs = t, phase = "racing", rules = "allowed", others = { RIVAL({ id = "p00002", gapM = 12 }) } }), "start")[1]
            bStart = bStart or ops(M.step(b, { nowMs = t, phase = "racing", rules = "allowed",
                others = { RIVAL({ id = "p00001", vid = 111, gapM = -12, closingMps = 2 }) } }), "start")[1]
        end
        T.ok(aStart and aStart.target == "p00002", "A attacks B")
        T.ok(bStart and bStart.target == "p00001", "B attacks A (defending its position)")
        local r = T.Core.get("vocabulary.hash").stream("model-duel")
        local res = M.resolveModel(a.prof, b.prof, "tire_sabotage", r)
        T.ok(res.landed ~= nil, "off-bubble exchanges resolve on the model too")
    end,

    rules_separate_offence_from_physics = function(T)
        local Ru = R(T)
        T.eq(Ru.forTier("street"), "allowed", "street racing allows it")
        T.eq(Ru.forTier("pro"), "prohibited", "sanctioned tiers prohibit it")
        T.falsy(Ru.offence("allowed", "total_failure"), "no offence where it is allowed")
        T.ok(Ru.offence("restricted", "tire_sabotage"), "restricted tolerates mild interference only")
        T.falsy(Ru.offence("restricted", "blackout"), "blackout is mild")
        T.eq(Ru.penalty("prohibited", "total_failure").kind, "dsq", "destroying a car in a formal race is a DSQ if attributed")
        T.eq(Ru.penalty("prohibited", "blackout").kind, "time", "a mild offence costs time")
        T.falsy(Ru.offence("prohibited", "purge"), "defending yourself is never an offence")
        local M = H(T)
        local lawful = M.newAgent("p00001", prof({ regulatoryAwareness = 0.9 }), { seed = "r7" })
        for t = 0, 30000, 250 do
            T.eq(#ops(M.step(lawful, { nowMs = t, phase = "racing", rules = "prohibited", others = { RIVAL() } }), "start"), 0, "a law-abiding racer does not hack in a formal race")
        end
    end,
}
