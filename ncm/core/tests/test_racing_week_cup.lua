-- paddock.season under Racing Week (L303): the Cup is the run, the calendar ends in finales, spec series.
local function provider(T)
    local W = T.Core.get("week.clock")
    local cfg = { epoch = W.DEFAULT_EPOCH, daySeconds = 86400, boundarySod = 12 * 3600 }
    return function(utc)
        local at = W.now(cfg, utc)
        if not at then return nil end
        local s, e = W.runBounds(cfg, at.runIndex)
        return { run = at.runIndex, startUtc = s, endUtc = e }
    end, cfg
end

local function with(T, fn)
    local S = T.Core.get("paddock.season")
    local p, cfg = provider(T)
    S.setWeek(p)
    local ok, err = pcall(fn, S, cfg)
    S.setWeek(nil)
    if not ok then error(err, 0) end
end

return {
    the_cup_is_the_run = function(T)
        with(T, function(S)
            local start = T.Core.get("week.clock").DEFAULT_EPOCH
            local a, b = S.cupOf(start + 3600), S.cupOf(start + 71 * 3600)
            T.eq(a.cupId, b.cupId, "hour 1 and hour 71 are one Cup")
            T.match(a.cupId, "%-RW001$")
            T.eq(a.run, 1)
            T.eq(a.cupEndUtc, start + 72 * 3600)
            local c = S.cupOf(start + 72 * 3600)
            T.match(c.cupId, "%-RW002$", "hour 72 is the next run")
            T.match(a.cupId, "^%d+%-S%d", "the season prefix the archive reads")
        end)
        -- without a provider: weekly Cups as before
        local S = T.Core.get("paddock.season")
        T.falsy(S.cupOf(1791043200).run)
    end,

    the_calendar_ends_in_finales = function(T)
        with(T, function(S)
            local start = T.Core.get("week.clock").DEFAULT_EPOCH
            local endUtc = start + 72 * 3600
            local slots = S.window(endUtc - 4 * 3600, endUtc)
            local finales, regularLate = {}, 0
            for _, r in ipairs(slots) do
                if r.finale then finales[r.seriesId] = r.utc
                elseif r.utc >= endUtc - S.FINALE_CLEAR_S then regularLate = regularLate + 1 end
            end
            T.eq(regularLate, 0, "nothing but finales in the clear zone")
            local n = 0
            for _, s in ipairs(S.allSeries()) do
                T.truthy(finales[s.id], "a finale for " .. s.id); n = n + 1
                T.ok(finales[s.id] < endUtc - 30 * 60, s.id .. " finale starts at least 30 min before the crown")
            end
            T.ok(finales.premier > finales.pro_a and finales.pro_a > finales.regional_a and finales.regional_a > finales.street_a,
                "tier order: the Hypercar finale last")
            T.truthy(S.isFinale("premier", finales.premier))
            T.falsy(S.isFinale("premier", finales.premier - 60))
            T.eq(S.pointsAt(1, "finished", "premier", finales.premier), 50)
            T.eq(S.pointsAt(1, "finished", "premier", finales.premier - 3600), 25)
            T.eq(S.pointsAt(1, "dnf", "premier", finales.premier), 0)
            -- a race id is the same however the window is cut (no duplicates across passes)
            local again = S.window(finales.premier - 1, finales.premier + 1)
            T.eq(#again, 1); T.eq(S.raceId(again[1].seriesId, again[1].utc), S.raceId("premier", finales.premier))
        end)
    end,

    spec_series_race_the_organisers_car = function(T)
        local S = T.Core.get("paddock.season")
        local spec = S.specFor("regional_b")
        T.eq(spec.record, "Vehicle.v_standard2_makigai_maimai")
        T.eq(S.specFor("regional_a"), nil)
        local Car = T.Core.get("paddock.car")
        T.eq(Car.performance(S.specCar("regional")), Car.performance(S.specCar("regional")), "identical for everyone")
        T.ok(math.abs(Car.performance(S.specCar("regional")) - 40) < 1e-9)
        T.eq(T.Core.get("paddock.names").LEAGUES.regional_b, "MaiMai Cup")
    end,
}
