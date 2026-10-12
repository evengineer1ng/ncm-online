-- ncm-core module: paddock.tape
-- The Paddock's causal fact tape (doc 44 §8; FTB2 `event_tape.py`). Every consequential thing is one event, and
-- news, tags, spotlight and Billie's line suspensions all read the tape rather than each keeping their own memory.
--
-- An event: { id, at, day, kind, entities = { {kind, id} }, causeRefs = {eventId}, effectRefs = {eventId},
--             facts = {...}, publicSummary, seed, salience (0..100), retain (bool), provenance }.
-- `facts` is the ONLY thing a news template may read (`paddock.news`), so every sentence traces to a fact.
-- Provenance is `simulated` for the sim (L222); a report stays `reported` and never becomes a result.
local Core = NcmCore

Core.define("paddock.tape", function(C)
    local M = { version = "0.1.0" }

    -- Base salience by kind (doc 44 §8: Premier results, upsets, streaks, signings, firings, folds, retirements
    -- and title swings rank high; a mid-table street result ranks low and stays in RESULTS).
    M.KINDS = {
        race_result = 20, upset = 60, streak = 55, first_win = 58, crash_out = 25, feud = 50, transfer = 50,
        release = 40, retirement = 65, fold = 80, founded = 55, promotion = 70, relegation = 65, cup_title = 70,
        season_title = 95, human_mention = 50, callout = 75, manager_hired = 55, manager_fired = 70,
        sponsor_signed = 30, sponsor_left = 35, rookie_debut = 30,
        -- a race car destroyed (any cause, physical), and a quickhack attributed to its source (2026-10-08)
        vehicle_destroyed = 45, chrome_attack = 35,
    }
    -- Kinds kept forever (doc 44 §14.1 pruning: titles, folds and retirements).
    M.RETAIN = { season_title = true, cup_title = true, fold = true, retirement = true, founded = true,
        promotion = true, relegation = true }
    M.TIER_WEIGHT = { street = 0, regional = 5, pro = 12, premier = 25 }

    --- Build an event. `key` makes the id stable and unique (a race id, a person id and season, ...), so writing the
    --- same fact twice is idempotent at the database's primary key.
    function M.event(kind, key, at, fields)
        if not M.KINDS[kind] then error("paddock.tape: unknown kind " .. tostring(kind), 2) end
        fields = fields or {}
        local tier = fields.tier or (fields.facts and fields.facts.tier)
        local salience = (fields.salience or M.KINDS[kind]) + (M.TIER_WEIGHT[tier] or 0) + (fields.salienceBonus or 0)
        if salience > 100 then salience = 100 elseif salience < 0 then salience = 0 end
        local id = kind .. ":" .. tostring(key)
        if #id > 150 then id = id:sub(1, 150) end
        return {
            id = id, at = math.floor(at or 0), day = fields.day, kind = kind,
            entities = fields.entities or {}, causeRefs = fields.causeRefs or {}, effectRefs = fields.effectRefs or {},
            facts = fields.facts or {}, publicSummary = fields.publicSummary, seed = fields.seed,
            salience = math.floor(salience + 0.5), retain = M.RETAIN[kind] == true or fields.retain == true,
            provenance = fields.provenance or "simulated",
        }
    end

    function M.validate(e)
        if type(e) ~= "table" then return false, "not_a_table" end
        if not M.KINDS[e.kind] then return false, "unknown_kind" end
        if type(e.id) ~= "string" or e.id == "" then return false, "id_required" end
        if type(e.facts) ~= "table" then return false, "facts_required" end
        if e.provenance ~= "simulated" and e.provenance ~= "physical" and e.provenance ~= "reported" then
            return false, "invalid_provenance"
        end
        return true
    end

    --- Does this event touch entity (kind, id)?
    function M.touches(e, kind, id)
        for _, ent in ipairs(e.entities or {}) do
            if ent[1] == kind and ent[2] == id then return true end
        end
        return false
    end

    --- Walk cause references back from `id` over a lookup (id -> event), oldest first. Bounded.
    function M.explain(lookup, id, depth)
        local chain, seen = {}, {}
        local function walk(eid, d)
            if d > (depth or 6) or seen[eid] then return end
            seen[eid] = true
            local e = lookup[eid]
            if not e then return end
            for _, c in ipairs(e.causeRefs or {}) do walk(c, d + 1) end
            chain[#chain + 1] = e
        end
        walk(id, 0)
        return chain
    end

    return M
end)
