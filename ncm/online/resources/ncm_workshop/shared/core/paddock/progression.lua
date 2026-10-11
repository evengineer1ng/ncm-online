-- ncm-core module: paddock.progression
-- Lives over time (doc 44 §5.3): morale after results, form, the daily growth tick, ageing at rollover and
-- retirement. Growth and decay run ONCE PER DAY (idempotent by `dayIndex` at the server), fixing FTB1's per-tick
-- decay; people age one paddock year per season.
local Core = NcmCore

Core.define("paddock.progression", function(C)
    local M = { version = "0.1.0", MORALE_REVERSION = 0.06, MORALE_CAP = 12 }
    local Attr = C.get("paddock.attributes")
    local World = C.get("paddock.world")

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    --- Morale after a race (FTB1 shape: finish against expectation, losses softened by mettle, capped).
    --- `expected` is the grid slot (the field's own expectation); `fieldSize` normalises.
    function M.moraleAfterRace(driver, position, expected, fieldSize, state)
        local a = driver.attrs or {}
        local delta
        if state ~= "finished" then
            delta = -6
        else
            delta = (expected - position) / math.max(1, fieldSize) * 20
            if position == 1 then delta = delta + 4 elseif position <= 3 then delta = delta + 1.5 end
        end
        if delta < 0 then delta = delta * (100 - (a.mettle or 50)) / 100 * 1.4 end
        delta = clamp(delta, -M.MORALE_CAP, M.MORALE_CAP)
        driver.morale = clamp((driver.morale or 50) + delta, 5, 95)
        return delta
    end

    --- Form -1..1 from recent positions (newest last) against a field size: a least-squares trend over the last
    --- five, the FTB momentum labels' slope with a sign that reads "improving is positive".
    function M.form(recent, fieldSize)
        local n = math.min(5, #(recent or {}))
        if n < 3 then return 0 end
        local xs, ys = {}, {}
        for i = 1, n do xs[i] = i; ys[i] = recent[#recent - n + i] end
        local mx, my = (n + 1) / 2, 0
        for i = 1, n do my = my + ys[i] end
        my = my / n
        local num, den = 0, 0
        for i = 1, n do num = num + (xs[i] - mx) * (ys[i] - my); den = den + (xs[i] - mx) ^ 2 end
        local slope = den > 0 and num / den or 0      -- positions per race; negative = improving
        return clamp(-slope / math.max(1, (fieldSize or 10) / 5), -1, 1)
    end

    --- The daily tick for one driver: morale reverts toward its baseline, then skills grow or decline.
    function M.dayDriver(world, driver, ctx)
        local base = Attr.moraleBaseline(driver.attrs or {})
        driver.morale = (driver.morale or base) + (base - (driver.morale or base)) * M.MORALE_REVERSION
        Attr.growDay(driver.attrs, driver.personality, World.age(world, driver), ctx)
    end

    --- Retirement chance at a season rollover for a driver of `age` (paddock years).
    function M.retireChance(driver, age)
        if age < 33 then return 0 end
        local p = 0.06 + 0.09 * (age - 33)
        local rating = Attr.rating(driver.attrs)
        if rating < 45 then p = p + 0.10 end
        if (driver.morale or 50) < 35 then p = p + 0.08 end
        if age >= 41 then p = p + 0.3 end
        return clamp(p, 0, 0.95)
    end

    --- Trait drift from a season's events: aggression and ego harden with contact and wins; discipline grows
    --- with clean seasons. Small, bounded steps.
    function M.seasonDrift(driver, evidence)
        local a = driver.attrs
        if not a then return end
        local e = evidence or {}
        if (e.contacts or 0) >= 3 then a.aggression = clamp((a.aggression or 50) + 2, 5, 95) end
        if (e.wins or 0) >= 3 then a.ego = clamp((a.ego or 50) + 2, 5, 95) end
        if (e.starts or 0) >= 10 and (e.dnfs or 0) == 0 then
            a.discipline = clamp((a.discipline or 50) + 1.5, 5, 95)
            a.mistake_rate = clamp((a.mistake_rate or 50) - 1.5, 5, 95)
        end
    end

    return M
end)
