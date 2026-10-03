-- ncm-core module: paddock.calibration
-- Base pace for the sim: a declared seeded baseline, refined by the server's human times (doc 44 §7).
--
-- `baseSec` is what a stat-50 NPC in a stat-50 car does on a route, dry and by day, at a tier. It starts from a
-- DECLARED baseline (distance over a tier's typical average speed, with a small seeded per-route character) that
-- is a first-class value, not an error fallback: the dev server has two humans (L223) and most buckets will never
-- reach the minimums. When a bucket does (>= minN samples from >= minDrivers drivers), the human median becomes the
-- base, with the conditions' own effect backed out so the sim does not count the rain twice.
--
-- Human series map to NPC tiers by machinery band. Regional has no human counterpart and interpolates.
local Core = NcmCore

Core.define("paddock.calibration", function(C)
    local M = { version = "0.1.0", MIN_N = 8, MIN_DRIVERS = 3 }
    local Hash = C.get("vocabulary.hash")
    local Sim = C.get("paddock.sim")

    -- Typical average speed (m/s) along the ROAD for a stat-50 car in the tier's band, over the route's real line.
    -- L296 (owner, 2026-10-02: "qualify and sim results are too fast, we have data now on average pace lets use it"):
    -- seeded from the physical NCM Pace field of 41 races that evening (street ~29 m/s, the sim's own per-route pace
    -- having ranged 22.7-40.7 m/s because it raced a planar estimate of the road, not the road), and refined from then
    -- on by every race's measured physical pace (`learned`, below).
    M.TIER_SPEED = { street = 29.0, regional = 31.0, pro = 34.0, premier = 37.0 }
    -- Ovals keep their own numbers (owner ruling: sim oval pace ~35-40 m/s; test_ovals), not the street's.
    M.OVAL_TIER_SPEED = { street = 30.5, regional = 32.5, pro = 34.5, premier = 37.5 }
    -- Which human championships measure which NPC tier (`packs/street.lua` eligibility bands).
    M.HUMAN_SERIES_TIER = { city_cup = "street", maimai_cup = "street", night_city_gt = "pro", hypercar = "premier" }

    --- The declared baseline for (route, tier): road length / tier speed, +-3% seeded route character. A street route
    --- with `route.lineM` (the baked road line the race actually runs, L296) uses it as is; without one, the planar
    --- distance stands in through `roadM`. `learned` = { [tier] = m/s } measured from physical races, else the seeds.
    function M.baseline(seed, routeId, distanceM, tier, route, learned)
        local character = 0.97 + 0.06 * Hash.unit(seed, "route_character", routeId)
        -- an oval's length is exact (laps x the loop) and its average speed a roundabout's, not a street's
        if route and route.oval then
            local ov = M.OVAL_TIER_SPEED[tier] or M.OVAL_TIER_SPEED.street
            return (tonumber(distanceM) or 2400) / (ov * M.OVAL_SPEED_FACTOR) * character
        end
        local v = (type(learned) == "table" and tonumber(learned[tier])) or M.TIER_SPEED[tier] or M.TIER_SPEED.street
        local lineM = route and tonumber(route.lineM)
        if lineM and lineM > 0 then return lineM / v * character end
        return M.roadM(distanceM) / v * character
    end
    M.OVAL_SPEED_FACTOR = 1.20

    --- L296: fold one race's measured physical pace (m/s along the line, a field of physical stretches) into a tier's
    --- learned speed. A slow average (a crash-strewn race) moves it a little; a wild sample is refused.
    M.LEARN_WEIGHT, M.LEARN_MIN_MPS, M.LEARN_MAX_MPS = 0.2, 15, 60
    function M.learn(prev, sampleMps)
        local s = tonumber(sampleMps)
        if not s or s < M.LEARN_MIN_MPS or s > M.LEARN_MAX_MPS then return prev, false end
        if not tonumber(prev) then return s, true end
        return prev + (s - prev) * M.LEARN_WEIGHT, true
    end

    --- The road distance a route's crow-flies (or summed-leg) distance stands for (L236). A route's `distanceM` is
    --- planar; the road between two city nodes is longer, and relatively longer the shorter the hop (Troll Pass is
    --- 550 m crow-flies and a minute-plus of driving; the v1 sim raced it in 18 s). First numbers, replaced by the
    --- human median wherever one qualifies.
    M.ROAD_FACTOR, M.ROAD_SHORT_EXTRA, M.ROAD_SHORT_M = 1.35, 0.9, 1000
    function M.roadM(distanceM)
        local d = tonumber(distanceM) or 3000
        return d * (M.ROAD_FACTOR + M.ROAD_SHORT_EXTRA * math.exp(-d / M.ROAD_SHORT_M))
    end

    --- Median and quartile of a list of milliseconds, with the distinct-driver count.
    --- `samples` = { { ms, driverId } }.
    function M.summarise(samples)
        local ms, drivers, nd = {}, {}, 0
        for _, s in ipairs(samples or {}) do
            if tonumber(s.ms) and s.ms > 0 then
                ms[#ms + 1] = s.ms
                if s.driverId and not drivers[s.driverId] then drivers[s.driverId] = true; nd = nd + 1 end
            end
        end
        table.sort(ms)
        local n = #ms
        if n == 0 then return { n = 0, drivers = 0 } end
        local function q(p)
            local i = 1 + (n - 1) * p
            local lo = math.floor(i)
            local frac = i - lo
            return ms[lo] + ((ms[lo + 1] or ms[lo]) - ms[lo]) * frac
        end
        return { n = n, drivers = nd, median = q(0.5), p25 = q(0.25) }
    end

    --- True when a human summary is strong enough to replace the baseline.
    function M.qualifies(summary, minN, minDrivers)
        return type(summary) == "table" and (summary.n or 0) >= (minN or M.MIN_N)
            and (summary.drivers or 0) >= (minDrivers or M.MIN_DRIVERS) and summary.median ~= nil
    end

    --- The base (seconds) for a race. `human` is the summary for (route, tier, condition bucket) or nil; `cond`
    --- are the race conditions. Returns baseSec, source ("baseline" | "human").
    function M.basePace(seed, route, tier, cond, human, minN, minDrivers, learned)
        local base = M.baseline(seed, route.routeId, route.distanceM, tier, route, learned)
        if M.qualifies(human, minN, minDrivers) then
            -- back out what the conditions cost a stat-50 driver, so the sim's own condition model is not doubled
            local f = Sim.conditionFactor({}, human.cond or cond or {})
            return (human.median / 1000) / f, "human"
        end
        return base, "baseline"
    end

    --- The regional tier's base, interpolated between street and pro where both have human bases.
    function M.interpolate(streetSec, proSec)
        if not streetSec or not proSec then return nil end
        return (streetSec + proSec) / 2
    end

    return M
end)
