-- ncm-core module: competition.eligibility
-- What machinery a championship admits, as a predicate over `data.vehicle_pool` (IDEA-113, L83).
--
-- L83: drivers bring their own car, earned through progression, and an entry they cannot comply with is REFUSED
-- rather than substituted. That makes eligibility load-bearing, so it lives here as data a championship carries
-- rather than as model checks scattered through event code -- reclassifying a car or changing what a series
-- admits must be a data edit, never a rewrite of the race system.
--
-- A spec is a set of filters, ALL of which must hold:
--   records     = { id, ... }   an explicit allow-list. Present = the whole answer; nothing else is consulted.
--   classes     = { "Sport" }   membership in any one of these pool classes
--   prestigeMin = 1             inclusive
--   prestigeMax = 2             inclusive
--   tagsAny     = { "race" }    at least one of these tags
--   tagsAll     = { "offroad" } every one of these tags
--   exclude     = { id, ... }   removed whatever else says
-- An empty spec admits everything in the pool, which is what an open street series wants.
--
-- Deliberately NOT here: manufacturer families. The pool has no `make` field, and deriving one by reading the
-- maker out of a TweakDB id is the "a parsed id is not a catalogue" mistake this module exists to avoid. A
-- championship that needs makes needs `make` authored on the pool records first.
local Core = NcmCore

Core.define("competition.eligibility", function(C)
    local M = { version = "0.0.1" }
    local Pool = C.get("data.vehicle_pool")

    local function has(list, want)
        for _, x in ipairs(list or {}) do if x == want then return true end end
        return false
    end

    --- Does this record satisfy the spec? Returns true, or false plus the filter that rejected it.
    --- The reason is for the host log and for telling a driver what to change -- never a bare "no".
    function M.matches(spec, recordId)
        if type(spec) ~= "table" then error("competition.eligibility.matches: spec must be a table", 2) end
        local meta = Pool.byRecord(recordId)
        if not meta then return false, "unknown_record" end
        if has(spec.exclude, recordId) then return false, "excluded" end
        if spec.records then
            if has(spec.records, recordId) then return true end
            return false, "not_in_list"
        end
        if spec.classes then
            local ok = false
            for _, c in ipairs(spec.classes) do if Pool.inClass(recordId, c) then ok = true; break end end
            if not ok then return false, "wrong_class" end
        end
        if spec.prestigeMin and meta.prestige < spec.prestigeMin then return false, "below_prestige" end
        if spec.prestigeMax and meta.prestige > spec.prestigeMax then return false, "above_prestige" end
        if spec.tagsAll then
            for _, t in ipairs(spec.tagsAll) do if not has(meta.tags, t) then return false, "missing_tag" end end
        end
        if spec.tagsAny then
            local ok = false
            for _, t in ipairs(spec.tagsAny) do if has(meta.tags, t) then ok = true; break end end
            if not ok then return false, "no_matching_tag" end
        end
        return true
    end

    --- Every pool record the spec admits, in pool order. Used to describe a championship and to seed a garage.
    function M.recordsFor(spec)
        local out = {}
        for _, r in ipairs(Pool.allRecords()) do
            if M.matches(spec, r.id) then out[#out + 1] = r.id end
        end
        return out
    end

    --- The first record in `owned` that the spec admits, or nil. `owned` is an array of record ids.
    --- Pool order, not the order the driver acquired them, so the answer is stable across calls.
    function M.firstEligible(spec, owned)
        if type(owned) ~= "table" then return nil end
        local set = {}
        for _, id in ipairs(owned) do set[id] = true end
        for _, r in ipairs(Pool.allRecords()) do
            if set[r.id] and M.matches(spec, r.id) then return r.id end
        end
        return nil
    end

    --- Which of a driver's own records the spec admits, in pool order. The Race Guide needs the COUNT before a
    --- player commits (IDEA-124): "9 eligible, you own 3" is planning information; "you cannot enter" is not.
    function M.eligibleOwned(spec, owned)
        local out = {}
        if type(owned) ~= "table" then return out end
        local set = {}
        for _, id in ipairs(owned) do set[id] = true end
        for _, r in ipairs(Pool.allRecords()) do
            if set[r.id] and M.matches(spec, r.id) then out[#out + 1] = r.id end
        end
        return out
    end

    --- The entry decision for one driver (L83). Two questions, two different answers:
    ---   * does this championship admit anything at all?   -> a broken spec, the operator's problem
    ---   * does this driver own something it admits?       -> the driver's problem, and they can fix it
    --- Returns { ok = true, record = id } or { ok = false, reason = slug, admits = n }.
    function M.check(spec, owned)
        spec = spec or {}
        local admitted = M.recordsFor(spec)
        if #admitted == 0 then return { ok = false, reason = "championship_admits_nothing", admits = 0 } end
        local mine = M.firstEligible(spec, owned)
        if not mine then return { ok = false, reason = "no_eligible_car", admits = #admitted } end
        return { ok = true, record = mine, admits = #admitted }
    end

    --- A short phrase naming what a championship wants, for a refusal a player can act on.
    --- Returns something like "a Makigai MaiMai" or "a Sport car" or "2 eligible cars".
    function M.describe(spec, pool)
        spec = spec or {}
        if spec.records and #spec.records == 1 then
            return "one specific car"
        end
        if spec.classes and #spec.classes == 1 then
            return "a " .. spec.classes[1] .. " car"
        end
        local n = pool or #M.recordsFor(spec)
        return ("one of %d eligible cars"):format(n)
    end

    return M
end)
