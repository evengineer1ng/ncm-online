-- ncm-core module: paddock.attendance
-- Who turns up to a race (owner, 2026-10-01): "its possible that a leagues race may run often, but virtually impossible
-- that all 12/12 drivers from a league show up with 100% attendance to every race in that league. so each league needs
-- 30-100 drivers in a pool, of which some are plucked per race".
--
--   street     a league is a POOL of drivers (independents, and street teams' drivers) -- `person.leagueId`. Each
--              race, every member turns up or not; the field is the first `fieldSize` who do, by eagerness.
--   sanctioned regional / pro / premier keep their TEAMS, with deeper rosters (`ROSTER`); each team fields its best
--              available drivers in its race seats, and a team with nobody available misses the race.
--
-- Whether a driver turns up is deterministic for (world seed, race id, person id): the same race always draws the
-- same field, so a priced or frozen field can be re-derived and audited. Inputs: the driver's reliability (a fixed
-- trait from the seed, never stored), morale, whether they raced recently (a street league runs every 42 minutes;
-- nobody makes all of them), and their state. Every absence has a reason.
local Core = NcmCore

Core.define("paddock.attendance", function(C)
    local M = { version = "0.1.0" }
    local Hash = C.get("vocabulary.hash")
    local Attr = C.get("paddock.attributes")

    -- a street league's members (its teams' drivers count); a sanctioned team's roster is `Season.TIERS[tier].roster`
    -- (L249: regional 4, pro 4, premier 5 -- leagues of 48 / 40 / 40)
    M.STREET_POOL = 56
    -- how likely a fit, keen, rested driver is to turn up: a street racer has a life; a contracted driver is paid to
    M.BASE = { street = 0.42, regional = 0.86, pro = 0.9, premier = 0.94 }
    M.RECENT_SEC = 3 * 3600          -- raced within this: far less likely to turn up again (street nights)
    M.MIN_FIELD = 4                  -- fewer turn up than this: the race still runs with who came

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    --- A well-mixed [0,1) draw. `Hash.unit` is FNV-1a over the joined key, and keys that differ only in their last
    --- characters (p00123 / p00124) barely move the high bits it reads: one race drew all 56 of a pool "no_show".
    --- Hashing again with the first hash's digits at the FRONT spreads the difference through the whole key.
    local function draw(...)
        local k = Hash.key(...)
        return Hash.unit(tostring(Hash.fnv1a32(k)), k)
    end
    M.draw = draw

    --- A driver's reliability, 0.35..0.97: a fixed trait from the world seed and their id (never stored, never shown).
    function M.reliability(seed, personId)
        local u = draw(seed, "reliability", personId)
        local v = draw(seed, "reliability2", personId)
        return clamp(0.35 + 0.62 * ((u + v) / 2), 0.35, 0.97)
    end

    --- The chance `person` turns up to a race at `atUtc` in `tier`, and the reason when it is low.
    function M.chance(seed, person, tier, atUtc)
        if not person or person.role ~= "driver" then return 0, "not_a_driver" end
        if person.state ~= "active" then return 0, person.state or "inactive" end
        local p = (M.BASE[tier] or 0.5) * (0.55 + 0.6 * M.reliability(seed, person.id))
        p = p * (0.75 + (person.morale or 50) / 200)
        local last = person.evidence and tonumber(person.evidence.lastStartAt)
        local why = "no_show"
        if last and atUtc and atUtc - last < M.RECENT_SEC and atUtc >= last then
            p = p * ((tier == "street") and 0.35 or 0.7)
            why = "raced_recently"
        end
        return clamp(p, 0.02, 0.98), why
    end

    --- Does `person` turn up? Returns turnedUp, eagerness (lower = keener), reason-if-not.
    function M.turnsUp(seed, raceId, person, tier, atUtc)
        local p, why = M.chance(seed, person, tier, atUtc)
        local u = draw(seed, "attend", raceId, person.id)
        return u < p, (p > 0) and (u / p) or math.huge, why
    end

    --- A STREET field from the league pool. `pool` = list of persons; returns entrants (list of persons, keenest first,
    --- at most `fieldSize`) and `absent` = { [personId] = reason } for every member who is not in it.
    function M.streetField(seed, raceId, pool, fieldSize, atUtc)
        local came, absent = {}, {}
        for _, p in ipairs(pool) do
            local ok, eager, why = M.turnsUp(seed, raceId, p, "street", atUtc)
            if ok then came[#came + 1] = { p = p, eager = eager } else absent[p.id] = why end
        end
        table.sort(came, function(a, b)
            if a.eager ~= b.eager then return a.eager < b.eager end
            return a.p.id < b.p.id
        end)
        local out = {}
        for i, c in ipairs(came) do
            if i <= fieldSize then out[#out + 1] = c.p else absent[c.p.id] = "field_full" end
        end
        return out, absent
    end

    --- A SANCTIONED field: each team in `teams` ({ org, drivers = persons }) fields up to `cars` of its available
    --- drivers, best rated first (the team's choice). Returns entrants { { driver, org } } and `absent`.
    function M.teamField(seed, raceId, teams, tier, cars, atUtc)
        local out, absent = {}, {}
        for _, t in ipairs(teams) do
            local avail = {}
            for _, d in ipairs(t.drivers) do
                local ok, _, why = M.turnsUp(seed, raceId, d, tier, atUtc)
                if ok then avail[#avail + 1] = d else absent[d.id] = why end
            end
            table.sort(avail, function(a, b)
                local ra, rb = Attr.rating(a.attrs), Attr.rating(b.attrs)
                if ra ~= rb then return ra > rb end
                return a.id < b.id
            end)
            for i, d in ipairs(avail) do
                if i <= cars then out[#out + 1] = { driver = d, org = t.org } else absent[d.id] = "reserve" end
            end
        end
        return out, absent
    end

    --- Absence reasons counted, for the race record and LIVE: { [reason] = n }.
    function M.tally(absent)
        local out = {}
        for _, why in pairs(absent or {}) do out[why] = (out[why] or 0) + 1 end
        return out
    end

    return M
end)
