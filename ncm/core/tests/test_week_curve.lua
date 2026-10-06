-- week.curve (L302): the carrier, the live signal, the band, and the organisers' announced steps.
return {
    carrier_follows_the_keyframes_and_never_rises = function(T)
        local C = T.Core.get("week.curve")
        T.ok(math.abs(C.carrier(0) - 0.95) < 1e-9)
        T.ok(math.abs(C.carrier(24) - 0.62) < 1e-9)
        -- L310 (doc 47): hour 72 is history's usual end, an attractor -- near nothing, not a verdict of zero
        T.ok(C.carrier(72) < 0.06 and C.carrier(72) > 0, "hour 72 " .. C.carrier(72))
        local prev = 1
        for h = 0, 72, 0.25 do
            local v = C.carrier(h)
            T.ok(v <= prev + 1e-9, "monotone at " .. h)
            prev = v
        end
        -- hour 12 is not "16.7% disgusted": still near the honeymoon
        T.ok(C.carrier(12) > 0.85, "hour 12 " .. C.carrier(12))
        -- no stair at midnight: 23.9 and 24.1 are neighbours
        T.ok(math.abs(C.carrier(23.9) - C.carrier(24.1)) < 0.01)
    end,

    behaviour_moves_tolerance_inside_the_band = function(T)
        local C = T.Core.get("week.curve")
        local st = C.newState(0)
        C.step(st, 0, {})
        -- twelve animals on Day 1: huge harm, but opening day can only sour by the band
        C.step(st, 2, { speeding = 200, civilian_contact = 40, wreck = 30 })
        T.ok(math.abs(st.deviation + C.band(2)) < 1e-9, "clamped at -band")
        T.ok(C.tolerance(st, 2) > 0.75, "Day 1 sours, never turns angry")
        -- a clean week cannot make the end anything but over
        local good = C.newState(0)
        C.step(good, 68, { clean_race = 1000 })
        T.ok(C.tolerance(good, 68) < 0.45, "hour 68 clean: fine, but go home")
        -- the deviation leaks back toward the carrier
        local d0 = st.deviation
        C.step(st, 26, {})
        T.ok(math.abs(st.deviation) < math.abs(d0) * 0.2)
    end,

    expected_race_cost_is_already_priced_in = function(T)
        local C = T.Core.get("week.curve")
        T.ok(math.abs(C.impulse({ race = 10, race_crash = 5 })) < 1e-12, "a normal week is the carrier")
        T.ok(C.impulse({ race = 10, race_crash = 12 }) < 0, "a crashy week is worse")
        T.ok(C.impulse({ race = 10, race_crash = 0, clean_race = 5 }) > 0, "a clean week is better")
        -- a server whose normal is 1.04 crashes a race tracks its own carrier
        T.ok(math.abs(C.impulse({ race = 10, race_crash = 10.4 }, { race_crash = 1.04 })) < 1e-9, "a measured normal is the carrier")
        T.ok(C.impulse({ race = 10, race_crash = 10.4 }) < 0, "the dev constant would call it a crashy week")
    end,

    institutions_step_and_a_bad_week_brings_them_early = function(T)
        local C = T.Core.get("week.curve")
        local calm = C.newState(0)
        local _, f0 = C.step(calm, 0, {})
        T.eq(f0[1].id, "opening")
        local _, f1 = C.step(calm, 25, {})
        T.eq(#f1, 0, "a calm week holds the line until the window closes")
        local _, f2 = C.step(calm, 30, {})
        T.eq(f2[1].id, "we_hear_you"); T.falsy(calm.fired.we_hear_you.early)
        T.eq(C.read(calm, 30).limit, 1.60)
        local bad = C.newState(0)
        C.step(bad, 0, {})
        C.step(bad, 20, { civilian_contact = 40 })
        T.truthy(bad.fired.we_hear_you and bad.fired.we_hear_you.early, "a bad week: the organisers answer early")
        -- a server that wakes at hour 66 fires everything owed, in order, and ends on the latest
        local late = C.newState(66)
        local _, all = C.step(late, 66, {})
        T.eq(#all, 3)
        T.eq(late.step, "back_to_sane")
        C.step(late, 68, {})
        T.eq(C.read(late, 68).step, "clampdown")
        T.eq(C.read(late, 68).race, "police")
    end,

    thresholds_sit_under_the_carrier_so_history_fires_on_schedule = function(T)
        local C = T.Core.get("week.curve")
        for _, s in ipairs(C.STEPS) do
            if s.to > 0 then
                T.ok(s.below < C.carrier(s.to), s.id .. " below the carrier at its window's end")
                T.ok(s.below > C.carrier(s.from) - C.band(s.from), s.id .. " reachable early by a bad week")
            end
        end
    end,

    a_noisy_npc_only_week_tracks_the_carrier = function(T)
        local C = T.Core.get("week.curve")
        local st = C.newState(0)
        local worst = 0
        for h = 1, 72 do
            local crashes = (h % 3 == 0) and 7 or ((h % 3 == 1) and 2 or 3)   -- ~4 per 8 races, noisy
            C.step(st, h, { race = 8, race_crash = crashes })
            worst = math.max(worst, math.abs(st.deviation))
        end
        T.ok(worst < 0.03, "NPC-only drift " .. worst)
    end,

    the_money_is_a_flash_craze = function(T)
        local C = T.Core.get("week.curve")
        local st = C.newState(0)
        local open, rush, late = C.read(st, 0).money, C.read(st, 8).money, C.read(st, 70).money
        T.ok(rush > open and open > late, ("rush %.2f open %.2f late %.2f"):format(rush, open, late))
        T.ok(math.abs(C.read(st, 8).money - 1.8) < 1e-9)
        local bad = C.newState(0); C.step(bad, 0, {}); C.step(bad, 10, { civilian_contact = 40 })
        T.ok(C.read(bad, 10).money < C.read(C.newState(0), 10).money, "a reckless week scares sponsors")
        for h = 0, 72 do T.ok(C.read(st, h).money >= C.MONEY_FLOOR) end
    end,

    police_discretion_tightens_with_the_city = function(T)
        local C = T.Core.get("week.curve")
        local st = C.newState(0)
        local early, latest = C.read(st, 1), C.read(st, 71)
        T.eq(early.policeCap, 1)
        T.eq(latest.policeCap, 5)
        T.ok(latest.perLevel < early.perLevel, "a lower bar at the end")
        -- L310: the official labels of an advertised seven-day festival; Day 3 is not called the last
        T.eq(early.chapter, "OPENING DAY"); T.eq(C.read(st, 50).chapter, "DAY THREE"); T.eq(C.read(st, 150).chapter, "FINAL DAY")
    end,

    after_seventy_two_the_pull_eases_and_the_band_widens = function(T)
        local C = T.Core.get("week.curve")
        T.ok(C.carrier(96) > C.carrier(72), "a survivor is off history's map")
        T.ok(C.carrier(168) < 0.35, "but never a honeymoon again")
        T.ok(math.abs(C.band(72) - 0.30) < 1e-9)
        T.ok(math.abs(C.band(168) - 0.45) < 1e-9)
        local d, name = C.chapter(130); T.eq(d, 6); T.eq(name, "DAY SIX")
    end,

    reservoirs_compose_the_deviation_and_scale_together = function(T)
        local C = T.Core.get("week.curve")
        local st = C.newState(0)
        C.step(st, 1, { speeding = 2, wreck = 1 })
        T.ok(st.res.enforcement < 0 and st.res.safety < 0, "each fact feeds its own reservoir")
        T.ok(math.abs(st.deviation - (st.res.safety + st.res.enforcement + st.res.momentum)) < 1e-12, "sentiment is the sum")
        -- saturate: the sum sits on the band, and the parts keep their proportions
        C.step(st, 2, { speeding = 500, wreck = 100 })
        local sum = st.res.safety + st.res.enforcement + st.res.momentum
        T.ok(math.abs(sum + C.band(2)) < 1e-9, "scaled back to the band")
        -- momentum only when the host knows its normal race rate
        local a = C.newState(0); C.step(a, 1, { race = 20 })
        T.eq(a.res.momentum, 0)
        local b = C.newState(0); C.step(b, 1, { race = 20 }, { racesPerHour = 8 })
        T.ok(b.res.momentum > 0, "a fuller calendar than normal is momentum")
        -- an old saved state (one deviation) loads as safety
        local old = { deviation = -0.05, hours = 10, fired = {}, facts = {} }
        C.step(old, 10, {})
        T.ok(math.abs(old.res.safety + 0.05) < 1e-9)
    end,

    moody_effects_change_rules_not_the_city = function(T)
        local C = T.Core.get("week.curve")
        local st = C.newState(0)
        local plain, fx = C.read(st, 30), C.read(st, 30, { limit = 1.2, policeCap = 1, perLevel = 0.5 })
        T.eq(plain.tolerance, fx.tolerance)
        T.ok(math.abs(fx.limit - plain.limit * 1.2) < 1e-9)
        T.eq(fx.policeCap, math.min(5, plain.policeCap + 1))
        T.ok(math.abs(fx.perLevel - plain.perLevel * 0.5) < 1e-9)
    end,
}
