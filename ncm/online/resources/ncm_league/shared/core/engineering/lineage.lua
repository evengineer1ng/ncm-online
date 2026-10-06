-- ncm-core module: engineering.lineage
--
-- Technology as history, across worlds (L321; doc 54 §E; doc 33 §11.3). A design record is an immutable design point
-- with an ORIGIN domain (night_city / los_santos / snowglobe), a principal, and PARENTS with a declared relation:
--   reconstructed_from   a faithful attempt at a named historical design ("B reconstruction of A/X", never "X by B")
--   derived_from         a changed specification, a different trade-off, or a combination of parents
--   adapted_for          a derived design re-targeted at another site, host or world's interfaces
--   successor            a derived revision kept in the same lineage by its owner (not necessarily better)
--   new_lineage          a distinct technological family (no parents, or parents it deliberately leaves)
-- There is no "first inventor" field: history is the chain, and every link names who made it and where.
--
-- REVERSE ENGINEERING is not copying. `reverseEngineer` estimates every physical property of a source design within
-- an error band set by what the engineer KNOWS of it (a rumour, an observation, measurements, a specimen on the bench,
-- the drawings) and how COMPETENT they are; the result is a NEW design point -- usually a little worse, heavier, now
-- and then better -- bounded by physics (`engineering.systems` validation, chemistry's specific-impulse ceiling).
-- Failure is a real outcome: nothing usable comes out.
local Core = NcmCore

Core.define("engineering.lineage", function(C)
    local M = { version = "0.1.0" }
    local Sys = C.get("engineering.systems")
    local Seed = C.get("world.seed")

    M.RELATIONS = { reconstructed_from = true, derived_from = true, adapted_for = true, successor = true, new_lineage = true }
    M.DOMAINS = { night_city = "NC", los_santos = "LS", snowglobe = "ORB" }
    M.KIND_CODE = {
        reaction_engine = "THR", jet = "JET", propeller = "AERO", ground_ram = "JUMP", energy_store = "BAT",
        propellant_tank = "TNK", power_source = "PWR", radiator = "RAD", aero_surface = "WING", structure = "STR",
    }

    --- What the engineer has of the source, and the error it leaves (fraction, 1 sd) before competency.
    M.KNOWLEDGE = {
        rumour = 0.35,       -- someone said it does X
        observed = 0.20,     -- seen it race, watched it fly
        measured = 0.10,     -- instrumented observation: telemetry, timing, thermal imaging
        specimen = 0.05,     -- one on the bench, taken apart
        documents = 0.02,    -- the drawings
    }
    --- Physical ceilings that no copy can exceed (vacuum specific impulse by propellant, seconds).
    M.ISP_CEILING = { n2 = 75, hydrazine = 240, kerosene = 360, methalox = 380, hydrolox = 465 }

    local COMPETENCY_CEILING = 1000

    --- The 1-sd error fraction for a knowledge rung and a competency (0..1000).
    function M.errorBand(knowledge, competency)
        local base = M.KNOWLEDGE[knowledge] or M.KNOWLEDGE.rumour
        local c = math.max(0, math.min(COMPETENCY_CEILING, competency or 0)) / COMPETENCY_CEILING
        return base * (1.5 - c)
    end

    --- The chance an attempt yields nothing usable.
    function M.failureChance(knowledge, competency)
        local base = M.KNOWLEDGE[knowledge] or M.KNOWLEDGE.rumour
        local c = math.max(0, math.min(COMPETENCY_CEILING, competency or 0)) / COMPETENCY_CEILING
        return math.max(0.02, math.min(0.9, base * 2 - c * 0.25))
    end

    -- ------------------------------------------------------------------------------------- the registry
    local Registry = {}
    Registry.__index = Registry

    function M.newRegistry() return setmetatable({ records = {}, order = {}, counters = {} }, Registry) end

    function Registry:get(id) return self.records[id] end

    local function nextId(self, origin, design)
        local prefix = M.DOMAINS[origin] or "X"
        local code = M.KIND_CODE[design.perf and design.perf.kind] or "PART"
        local key = prefix .. "-" .. code
        self.counters[key] = (self.counters[key] or 0) + 1
        return ("%s-%02d"):format(key, self.counters[key])
    end

    --- Add a record. `rec` = { design, origin, principal, parents = {{id, relation}}, lineage?, id?, at?, note? }.
    function Registry:add(rec)
        assert(rec.design, "lineage: a record needs a design")
        assert(M.DOMAINS[rec.origin], "lineage: origin must be night_city, los_santos or snowglobe")
        for _, p in ipairs(rec.parents or {}) do
            assert(M.RELATIONS[p.relation], "lineage: unknown relation " .. tostring(p.relation))
            assert(self.records[p.id], "lineage: unknown parent " .. tostring(p.id))
        end
        local r = Seed.deepCopy(rec)
        r.id = r.id or nextId(self, r.origin, r.design)
        assert(not self.records[r.id], "lineage: duplicate id " .. r.id)
        r.design.id = r.id
        r.parents = r.parents or {}
        if not r.lineage then
            local first = r.parents[1]
            r.lineage = (first and first.relation == "successor") and self.records[first.id].lineage or r.id
        end
        self.records[r.id] = r
        self.order[#self.order + 1] = r.id
        return r
    end

    --- A new technological family from nothing (a seeded root design, or an engineer's genuinely new idea).
    function Registry:newLineage(design, origin, principal, extra)
        local rec = { design = design, origin = origin, principal = principal, parents = {} }
        for k, v in pairs(extra or {}) do rec[k] = v end
        return self:add(rec)
    end

    --- The owner's next revision in the same lineage: the changes applied to the perf block.
    function Registry:successor(id, changes, principal, extra)
        local parent = assert(self.records[id], "lineage: unknown design " .. tostring(id))
        local d = Seed.deepCopy(parent.design)
        for k, v in pairs(changes or {}) do
            if k == "massKg" then d.massKg = v else d.perf[k] = v end
        end
        local rec = { design = d, origin = (extra and extra.origin) or parent.origin, principal = principal or parent.principal,
                      parents = { { id = id, relation = "successor" } }, lineage = parent.lineage }
        for k, v in pairs(extra or {}) do rec[k] = v end
        return self:add(rec)
    end

    --- The chain back to the root along first parents, oldest first: { record, ... }.
    function Registry:ancestry(id)
        local chain, seen = {}, {}
        local r = self.records[id]
        while r and not seen[r.id] do
            seen[r.id] = true
            table.insert(chain, 1, r)
            local p = r.parents[1]
            r = p and self.records[p.id] or nil
        end
        return chain
    end

    --- "LS-AERO-01 -> ORB-THR-01 (reconstructed_from) -> NC-THR-01 (adapted_for)".
    function Registry:renderAncestry(id)
        local parts = {}
        for i, r in ipairs(self:ancestry(id)) do
            parts[i] = (i == 1 or not r.parents[1]) and r.id or (r.id .. " (" .. r.parents[1].relation .. ")")
        end
        return table.concat(parts, " -> ")
    end

    -- ------------------------------------------------------------------------------------- reverse engineering
    -- Keys in a fixed order: Lua 5.4 randomises `pairs` order per process, and every draw from the seeded stream must
    -- land on the same field on every client and on the server, or one seed would build different worlds.
    local function sortedKeys(t)
        local ks = {}
        for k in pairs(t or {}) do ks[#ks + 1] = k end
        table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
        return ks
    end
    local NUMERIC_IS_BENEFIT = {
        thrustN = true, ispS = true, forceN = true, energyJ = true, capacityKg = true, capacityJ = true, maxPowerW = true,
        outputW = true, radiativeKw = true, convectiveKw = true, ratedLoadN = true, cl = true, chargeW = true,
    }
    local NUMERIC_IS_COST = { heatKw = true, cd = true, powerW = true, consumptionKgPerJ = true }

    --- Attempt to reverse-engineer `sourceId` from the registry.
    ---   opts = { knowledge, competency (0..1000), rng (a vocabulary.hash stream), origin, principal,
    ---            intent = "reconstruct" | "derive" | "adapt", adaptFor = name, combineWith = otherId, at }
    --- Returns the new record, or nil and { failed = true, reason, chance }.
    function Registry:reverseEngineer(sourceId, opts)
        local src = assert(self.records[sourceId], "lineage: unknown design " .. tostring(sourceId))
        local rng = assert(opts.rng, "lineage: reverse engineering needs a seeded rng")
        local knowledge = opts.knowledge or "observed"
        local pFail = M.failureChance(knowledge, opts.competency)
        if rng() < pFail then
            return nil, { failed = true, chance = pFail,
                reason = ("nothing usable: %s knowledge was not enough (%.0f%% failure chance)"):format(knowledge, pFail * 100) }
        end
        local err = M.errorBand(knowledge, opts.competency)
        local d = Seed.deepCopy(src.design)
        local estimates = {}
        -- a copy tends to fall short where the source excelled and to cost a little more: mean bias -err/2 on
        -- benefits, +err/2 on costs and mass; spread err
        for _, k in ipairs(sortedKeys(d.perf)) do
            local v = d.perf[k]
            if type(v) == "number" and (NUMERIC_IS_BENEFIT[k] or NUMERIC_IS_COST[k]) then
                local bias = NUMERIC_IS_BENEFIT[k] and -err / 2 or err / 2
                local f = math.max(0.05, 1 + rng:normal(bias, err))
                d.perf[k] = v * f
                estimates[k] = { source = v, value = d.perf[k], band = err }
            end
        end
        d.massKg = d.massKg * math.max(0.5, 1 + rng:normal(err / 3, err / 2))
        estimates.massKg = { source = src.design.massKg, value = d.massKg, band = err / 2 }
        -- combine: the second parent's best benefit fields carried over at the same error
        local parents = { { id = sourceId, relation = (opts.intent == "reconstruct") and "reconstructed_from" or "derived_from" } }
        if opts.combineWith then
            local other = assert(self.records[opts.combineWith], "lineage: unknown design " .. tostring(opts.combineWith))
            for _, k in ipairs(sortedKeys(other.design.perf)) do
                local v = other.design.perf[k]
                if NUMERIC_IS_BENEFIT[k] and type(v) == "number" and type(d.perf[k]) == "number" and v > d.perf[k] then
                    d.perf[k] = v * math.max(0.05, 1 + rng:normal(-err / 2, err))
                    estimates[k] = { source = v, value = d.perf[k], band = err, from = opts.combineWith }
                end
            end
            parents[#parents + 1] = { id = opts.combineWith, relation = "derived_from" }
        end
        if opts.intent == "adapt" then parents[1].relation = "adapted_for" end
        -- physics bounds: chemistry caps specific impulse; fractions stay fractions
        local cap = d.perf.propellant and M.ISP_CEILING[d.perf.propellant]
        if cap and d.perf.ispS and d.perf.ispS > cap then d.perf.ispS = cap end
        if d.perf.seaLevelFactor then d.perf.seaLevelFactor = math.max(0, math.min(1, d.perf.seaLevelFactor)) end
        local ok, errs = Sys.validate(d.perf)
        if not ok then return nil, { failed = true, reason = table.concat(errs, "; "), chance = pFail } end
        return self:add({
            design = d, origin = opts.origin or src.origin, principal = opts.principal, parents = parents,
            at = opts.at, adaptedFor = opts.adaptFor, knowledge = knowledge, estimates = estimates, errorBand = err,
        })
    end

    return M
end)
