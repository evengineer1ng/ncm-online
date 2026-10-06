-- ncm-core module: life.needs
-- What a simulated person runs short of (L237 M1, IDEA-765, L240). Four needs, each a satisfaction in 0..100:
--
--   money   rent, food, the car; work and hustles fill it, spending drains it
--   rest    sleep and downtime
--   social  company: a busy food stall, colleagues, a meet
--   drive   the reason they are in the Paddock at all: seat time, the scene, speed
--
-- Needs are RULES, authored once: how fast each decays per 30-minute block, bent by role, by the person's FTB2
-- personality (`paddock.attributes` axes drive, temperament, authority, valor, warmth, each in [-1, 1]) and by the
-- district's climate (`life.climate.pressures`). Nothing here says what anyone does; `life.schedule` turns urgency
-- into a choice.
local Core = NcmCore

Core.define("life.needs", function(C)
    local M = { version = "0.1.0", BLOCK_SEC = 1800 }
    local Hash = C.get("vocabulary.hash")

    M.NEEDS = { "money", "rest", "social", "drive" }

    -- Points lost per block before modifiers.
    M.DECAY = { money = 1.1, rest = 2.0, social = 1.4, drive = 1.0 }

    -- Role shapes the decay: a driver lives for seat time; an owner never runs short of money the same way.
    M.ROLE = {
        driver     = { money = 1.1, drive = 1.6 },
        engineer   = { drive = 0.8 },
        strategist = { drive = 0.6, social = 0.9 },
        manager    = { social = 1.1, drive = 0.6 },
        owner      = { money = 0.5, drive = 0.5, social = 1.1 },
    }

    local function clamp(v) if v < 0 then return 0 elseif v > 100 then return 100 end return v end
    local function r2(v) return math.floor(v * 100 + 0.5) / 100 end

    --- Per-block decay for one person in one district's climate.
    function M.decayFor(person, pressure)
        local pers = person.personality or {}
        local role = M.ROLE[person.role] or {}
        pressure = pressure or {}
        local out = {}
        for _, n in ipairs(M.NEEDS) do out[n] = M.DECAY[n] * (role[n] or 1) end
        out.money = out.money * (pressure.money or 1)
        out.social = out.social * (1 + 0.4 * (pers.warmth or 0))
        out.drive = out.drive * (1 + 0.5 * (pers.drive or 0))
        return out
    end

    --- Where a person wakes up on an Eastern day: a baseline from temperament plus the day's own noise.
    --- Stateless by design in M1 -- a day does not yet remember yesterday; M3's minds carry that (L237).
    function M.dawn(seed, person, dayIndex)
        local pers = person.personality or {}
        local r = Hash.stream(seed, "dawn", person.id, dayIndex)
        return {
            money = r2(clamp(55 + 10 * (pers.authority or 0) + r:normal(0, 12))),
            rest = r2(clamp(80 + r:normal(0, 8))),
            social = r2(clamp(60 - 10 * (pers.warmth or 0) + r:normal(0, 12))),
            drive = r2(clamp(55 - 10 * (pers.drive or 0) + r:normal(0, 12))),
        }
    end

    --- Urgency of a need at satisfaction v: quadratic, so a need at 20 matters four times one at 60 (Sims-style).
    function M.urgency(v)
        local d = (100 - clamp(v)) / 100
        return d * d
    end

    --- Apply one block: decay, then the activity's gains, less any money it costs. Returns a new table.
    function M.apply(needs, decay, gains, spend)
        local out = {}
        gains = gains or {}
        for _, n in ipairs(M.NEEDS) do
            out[n] = r2(clamp((needs[n] or 50) - (decay[n] or 0) + (gains[n] or 0)))
        end
        if spend then out.money = r2(clamp(out.money - spend)) end
        return out
    end

    --- The need that is worst right now, and its value -- for a line of dialogue, never a number shown.
    function M.worst(needs)
        local w, wv
        for _, n in ipairs(M.NEEDS) do
            if not wv or (needs[n] or 50) < wv then w, wv = n, needs[n] or 50 end
        end
        return w, wv
    end

    return M
end)
