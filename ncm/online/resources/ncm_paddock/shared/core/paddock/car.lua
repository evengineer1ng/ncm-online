-- ncm-core module: paddock.car
-- An organization's car as development levels in NCM Part-family terms (doc 44 §4.4, `engineering.competency`).
--
-- Four of the twelve canonical families carry the Paddock's car model: power unit, aerodynamics, tyres, chassis.
-- Levels run 1..10. `performance` maps them onto the 0..100 scale the sim blends with the driver. Development is
-- money in, level out, with rising cost per level so a rich org cannot buy the top instantly.
local Core = NcmCore

Core.define("paddock.car", function(C)
    local M = { version = "0.1.0", MAX_LEVEL = 10 }
    M.AREAS = { "power_unit", "aerodynamics", "tires", "chassis" }
    M.WEIGHTS = { power_unit = 0.30, aerodynamics = 0.25, tires = 0.25, chassis = 0.20 }
    -- Where each tier's cars start (mean level), before per-org variation.
    M.TIER_BASE = { street = 2.5, regional = 4, pro = 6, premier = 8 }
    -- Eddies per level step at level L: BASE * L^1.6. Street money buys street levels.
    M.COST_BASE = 900

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    --- A starting car for a tier. `rng` is a vocabulary.hash stream.
    function M.roll(rng, tier)
        local base = M.TIER_BASE[tier] or 3
        local car = { progress = {} }
        for _, a in ipairs(M.AREAS) do
            car[a] = clamp(math.floor(base + rng:normal(0, 0.9) + 0.5), 1, M.MAX_LEVEL)
            car.progress[a] = 0
        end
        return car
    end

    --- 0..100 from the weighted levels.
    function M.performance(car)
        if type(car) ~= "table" then return 50 end
        local p = 0
        for _, a in ipairs(M.AREAS) do p = p + (M.WEIGHTS[a] or 0) * (tonumber(car[a]) or 1) end
        return clamp(p * 10, 0, 100)
    end

    --- Cost of the next level in an area.
    function M.stepCost(level)
        return math.floor(M.COST_BASE * (level ^ 1.6) + 0.5)
    end

    --- Spend `eddies` on `area`. Money accumulates as progress until a level is bought. Returns the new car,
    --- the levels gained and the eddies actually consumed (never more than given).
    function M.invest(car, area, eddies)
        if not M.WEIGHTS[area] then return nil, "unknown_area" end
        eddies = math.max(0, math.floor(tonumber(eddies) or 0))
        car.progress = car.progress or {}
        local pool = (car.progress[area] or 0) + eddies
        local gained = 0
        while (car[area] or 1) < M.MAX_LEVEL do
            local cost = M.stepCost(car[area] or 1)
            if pool < cost then break end
            pool = pool - cost
            car[area] = (car[area] or 1) + 1
            gained = gained + 1
        end
        if (car[area] or 1) >= M.MAX_LEVEL then
            local refund = pool
            car.progress[area] = 0
            return car, gained, eddies - refund
        end
        car.progress[area] = pool
        return car, gained, eddies
    end

    --- Wear: a season of racing costs a fraction of a level in every area unless it is maintained.
    function M.depreciate(car, fraction)
        for _, a in ipairs(M.AREAS) do
            car.progress = car.progress or {}
            local loss = math.floor(M.stepCost(math.max(1, (car[a] or 1) - 1)) * (fraction or 0))
            car.progress[a] = (car.progress[a] or 0) - loss
            if car.progress[a] < 0 and (car[a] or 1) > 1 then
                car[a] = car[a] - 1
                car.progress[a] = car.progress[a] + M.stepCost(car[a])
            end
            if car.progress[a] < 0 then car.progress[a] = 0 end
        end
        return car
    end

    return M
end)
