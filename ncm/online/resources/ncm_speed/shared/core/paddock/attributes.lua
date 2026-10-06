-- ncm-core module: paddock.attributes
-- Hidden stats and personality for Paddock people (doc 44 §4.3). NOTHING here ever reaches a client: players see
-- earned tags (`paddock.tags`), and `paddock.projection.assertNoHidden` rejects any payload carrying these keys.
--
-- Sources: FTB1 `STATS_SCHEMAS` (the driver and AIPrincipal stat sets, 0-100, centred on 50), FTB1
-- `Entity.update_growth`/`apply_decay` (growth toward a potential ceiling, decline past a peak age), and FTB2
-- `personality.py` (five bipolar axes that bend growth). Reinterpreted, not transcribed:
--   * Growth and decay are stated PER PADDOCK YEAR and applied a day at a time (1/91 per daily tick). FTB applied
--     its per-tick rates every tick, which made veterans collapse within a season.
--   * Only SKILL stats grow toward the ceiling. FTB grew every stat, including mistake_rate and aggression, so
--     drivers got sloppier as they improved. Trait stats here drift only through events (`paddock.progression`).
local Core = NcmCore

Core.define("paddock.attributes", function(C)
    local M = { version = "0.1.0", DAYS_PER_YEAR = 91 }
    local Hash = C.get("vocabulary.hash")

    -- Skill stats: higher is better, and they grow toward `potential`.
    M.SKILLS = {
        "pace", "quali_pace", "race_pace", "consistency", "racecraft", "overtaking", "defending", "launch",
        "wet_weather_skill", "night_skill", "tyre_sympathy", "vehicle_sympathy", "pressure_handling", "adaptability",
        "fitness", "feedback",
    }
    -- Trait stats: character, not ability. `mistake_rate` and `confidence_volatility` are worse when higher.
    M.TRAITS = { "mistake_rate", "confidence_volatility", "aggression", "discipline", "ego", "mettle", "loyalty" }
    -- Meta: ceiling, decline and peak window (FTB1 `Entity` meta-properties).
    M.META = { "potential", "decay_rate", "peak_start", "peak_end" }

    M.AXES = { "drive", "temperament", "authority", "valor", "warmth" }
    M.PRINCIPAL = {
        "aggression", "risk_tolerance", "patience", "long_term_orientation", "financial_discipline",
        "liquidity_conservatism", "ruthlessness", "staff_loyalty_bias", "talent_evaluation", "crisis_management",
        "ambition", "media_savvy",
    }
    M.STAFF = { "skill", "reliability" }

    -- Every key that must never leave the server. `paddock.projection` reads this.
    M.HIDDEN = {}
    for _, list in ipairs({ M.SKILLS, M.TRAITS, M.META, M.AXES, M.PRINCIPAL, M.STAFF }) do
        for _, k in ipairs(list) do M.HIDDEN[k] = true end
    end
    for _, k in ipairs({ "attrs", "personality", "principal", "rating", "morale", "form", "stats" }) do M.HIDDEN[k] = true end

    -- Tier distributions (FTB1 TIER_CONFIG shape: 32/44/56/68/80 +- 7-9, mapped onto four tiers).
    M.TIER_STATS = {
        street = { mean = 40, sd = 10 }, regional = { mean = 52, sd = 9 },
        pro = { mean = 62, sd = 8 }, premier = { mean = 72, sd = 7 },
    }
    M.TIERS = { "street", "regional", "pro", "premier" }

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
    M.clamp = clamp
    local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

    --- A driver's hidden stats for a tier and age. `rng` is a vocabulary.hash stream.
    function M.rollDriver(rng, tier, age)
        local dist = M.TIER_STATS[tier] or M.TIER_STATS.street
        local core = rng:normal(dist.mean, dist.sd)           -- a driver is broadly good or not...
        local s = {}
        for _, k in ipairs(M.SKILLS) do                        -- ...with individual strengths around it
            s[k] = round1(clamp(core + rng:normal(0, 7), 5, 97))
        end
        for _, k in ipairs(M.TRAITS) do s[k] = round1(clamp(rng:normal(50, 15), 5, 95)) end
        -- Younger drivers have more headroom; the ceiling never sits below today's ability.
        local youth = clamp((30 - (age or 25)) / 12, 0, 1)
        s.potential = round1(clamp(core + 4 + youth * rng() * 22, core, 99))
        s.decay_rate = round1(0.5 + rng() * 2.0)
        s.peak_start = 26 + rng:int(0, 3)
        s.peak_end = s.peak_start + 4 + rng:int(0, 3)
        return s
    end

    --- FTB2 personality: five axes in [-1, 1], deterministic per (seed, id).
    function M.personality(seed, id)
        local p = {}
        for _, axis in ipairs(M.AXES) do
            p[axis] = math.floor((Hash.unit(seed, "persona", id, axis) * 2 - 1) * 1000 + 0.5) / 1000
        end
        return p
    end

    --- FTB1 AIPrincipal traits for an owner/principal/manager.
    function M.rollPrincipal(rng)
        local p = {}
        for _, k in ipairs(M.PRINCIPAL) do p[k] = round1(clamp(rng:normal(50, 16), 5, 95)) end
        return p
    end

    --- Staff (engineer/strategist) quality for a tier.
    function M.rollStaff(rng, tier)
        local dist = M.TIER_STATS[tier] or M.TIER_STATS.street
        return { skill = round1(clamp(rng:normal(dist.mean, dist.sd), 5, 97)),
            reliability = round1(clamp(rng:normal(55, 15), 5, 97)) }
    end

    --- The hidden overall rating a principal would "see" (never shown). Pace-led, like FTB's race weights.
    function M.rating(s)
        if type(s) ~= "table" then return 50 end
        return 0.30 * (s.pace or 50) + 0.15 * (s.race_pace or 50) + 0.10 * (s.quali_pace or 50)
            + 0.12 * (s.consistency or 50) + 0.10 * (s.racecraft or 50) + 0.06 * (s.overtaking or 50)
            + 0.05 * (s.defending or 50) + 0.05 * (s.wet_weather_skill or 50) + 0.07 * (100 - (s.mistake_rate or 50))
    end

    -- FTB2 coupling sets over OUR stat names.
    local STABILITY = { consistency = true, discipline = true, tyre_sympathy = true, vehicle_sympathy = true }
    local CLUTCH = { pressure_handling = true, racecraft = true, launch = true, mettle = true }
    local CHEMISTRY = { feedback = true, adaptability = true }

    --- FTB2 `modulated_growth` for one stat.
    function M.modulate(p, stat, g, pressure)
        p = p or {}
        g = g * (1 + 0.5 * (p.drive or 0))
        if stat == "confidence_volatility" then g = g * (1 - 0.4 * (p.temperament or 0))
        elseif STABILITY[stat] then g = g * (1 + 0.4 * (p.temperament or 0)) end
        if CHEMISTRY[stat] then g = g * (1 + 0.3 * (p.warmth or 0)) end
        if (pressure or 0) > 0 and CLUTCH[stat] then g = g * (1 + 0.6 * pressure * (p.valor or 0)) end
        return g
    end

    --- One DAY of growth or decline for a driver of `age` (paddock years). Mutates and returns `s`.
    --- `ctx.facility` 0..100 (FTB infrastructure: 0.8-1.2 on growth, 1.4-0.6 on decay), `ctx.pressure` 0..1
    --- (a title fight), `ctx.momentum` -1..1 (recent form).
    function M.growDay(s, p, age, ctx)
        ctx = ctx or {}
        local facility = tonumber(ctx.facility) or 50
        local peakMid = ((s.peak_start or 27) + (s.peak_end or 32)) / 2
        local ageFactor = clamp(1 - math.abs(age - peakMid) / 20, 0.1, 1)
        local infraGrow = clamp(1 + (facility - 50) / 100 * 0.4, 0.8, 1.2)
        -- ~3 points a year at the peak with half the headroom left: a slow, visible arc over seasons.
        local yearly = 6.0 * ageFactor * infraGrow + (tonumber(ctx.momentum) or 0) * 0.8
        local ceiling = s.potential or 99
        for _, k in ipairs(M.SKILLS) do
            local v = s[k] or 50
            if v < ceiling then
                local g = M.modulate(p, k, yearly * (ceiling - v) / 100, ctx.pressure)
                s[k] = clamp(v + g / M.DAYS_PER_YEAR, 1, 99)
            end
        end
        if age > (s.peak_end or 32) then
            local infraDecay = clamp(1 - (facility - 50) / 100 * 0.8, 0.6, 1.4)
            local perYear = (s.decay_rate or 1) * (age - (s.peak_end or 32)) * 0.8 * infraDecay
            for _, k in ipairs(M.SKILLS) do
                s[k] = clamp((s[k] or 50) - perYear / M.DAYS_PER_YEAR, 1, 99)
            end
        end
        return s
    end

    --- FTB1 morale baseline (40-60) from mettle, discipline and pressure handling.
    function M.moraleBaseline(s)
        local b = 40 + ((s.mettle or 55) / 10) * 0.5 + ((s.discipline or 50) / 20) * 0.25
            + ((s.pressure_handling or 50) / 20) * 0.25
        return clamp(b, 40, 60)
    end

    return M
end)
