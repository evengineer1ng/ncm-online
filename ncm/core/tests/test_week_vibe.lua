-- week.vibe (doc 47 §1.7, L310): the city's mood is composed from the state, never skinned by Day, never a number.
local function read(tol, dev, res, money)
    return { tolerance = tol, deviation = dev or 0, reservoirs = res or { safety = 0, enforcement = 0, momentum = 0 }, money = money or 1 }
end

return {
    an_ordinary_day_three_and_an_exceptional_one_sound_different = function(T)
        local V = T.Core.get("week.vibe")
        local ordinary = V.classify(read(0.10, 0), {}, 62)
        local exceptional = V.classify(read(0.52, 0.28, { safety = 0.25, enforcement = 0, momentum = 0.03 }), {}, 62)
        T.eq(ordinary.mood, "hostile")
        T.eq(exceptional.mood, "uneasy")
        T.eq(exceptional.cause, "safety_good")
        T.eq(exceptional.surprise, "better")
        T.ok(V.line("s", 1, 62, ordinary) ~= V.line("s", 1, 62, exceptional))
    end,

    two_day_fours_kept_alive_differently_sound_different = function(T)
        local V = T.Core.get("week.vibe")
        local beloved = V.classify(read(0.6, 0.35, { safety = 0.3, enforcement = 0, momentum = 0.05 }), {}, 80)
        local bought = V.classify(read(0.15, -0.05, { safety = -0.05, enforcement = 0, momentum = 0 }, 1.0), { purse = { street = 2.5 } }, 80)
        T.truthy(beloved.offMap); T.truthy(bought.offMap)
        T.eq(bought.cause, "money")
        T.ok(beloved.mood ~= bought.mood)
        local lb, lm = V.line("s", 4, 80, beloved), V.line("s", 4, 80, bought)
        T.ok(lb ~= lm)
    end,

    lines_are_deterministic_and_never_name_a_number = function(T)
        local V = T.Core.get("week.vibe")
        for h = 0, 168, 2 do
            for _, tol in ipairs({ 0.9, 0.6, 0.45, 0.3, 0.05 }) do
                local v = V.classify(read(tol, (tol - 0.5) / 4), { purse = { street = 2.5 } }, h)
                local a, b = V.line("seed", 2, h, v), V.line("seed", 2, h, v)
                T.eq(a, b)
                T.falsy(a:find("%d"), "no numbers in a proxy: " .. a)
                T.falsy(a:lower():find("percent") or a:lower():find("chance") or a:lower():find("probab"), a)
            end
        end
    end,
}
