-- week.moody, week.continuation, the seven-day timeline and the unattended harness (doc 47, L309-L310).
local function cfg(T) return { epoch = 1000000, daySeconds = 100, boundarySod = 0 } end

return {
    -- ----------------------------------------------------------------------------------------- the timeline

    an_open_run_has_a_provisional_end_at_the_next_noon_it_has_not_survived = function(T)
        local W = T.Core.get("week.clock")
        local c = cfg(T)
        local a = W.locate(c, {}, 1000000 + 150)
        T.eq(a.run, 1); T.truthy(a.open); T.eq(a.provisionalEnd, 1000000 + 300); T.falsy(a.beyond)
        local at = W.inRun(c, a, 1000000 + 150)
        T.eq(at.day, 2); T.ok(math.abs(at.hours - 36) < 1e-9); T.eq(at.secondsRemaining, 150); T.eq(at.possibleEnd, 3)
        -- past the provisional end and not yet judged: the same run, beyond (the Paddock posts nothing there)
        local b = W.locate(c, {}, 1000000 + 320)
        T.eq(b.run, 1); T.truthy(b.beyond)
    end,

    a_survived_run_reaches_day_four_and_its_next_end_moves = function(T)
        local W = T.Core.get("week.clock")
        local c = cfg(T)
        local runs = { [1] = { survived = 3 } }
        local a = W.locate(c, runs, 1000000 + 330)
        T.falsy(a.beyond); T.eq(a.provisionalEnd, 1000000 + 400)
        local at = W.inRun(c, a, 1000000 + 330)
        T.eq(at.day, 4); T.ok(math.abs(at.hours - 79.2) < 1e-9)
    end,

    a_recorded_end_opens_the_next_run_there = function(T)
        local W = T.Core.get("week.clock")
        local c = cfg(T)
        local runs = { [1] = { endUtc = 1000000 + 400, endKind = "collapse", survived = 3 } }
        local a = W.locate(c, runs, 1000000 + 399); T.eq(a.run, 1); T.falsy(a.open)
        local b = W.locate(c, runs, 1000000 + 400); T.eq(b.run, 2); T.eq(b.startUtc, 1000000 + 400); T.eq(b.provisionalEnd, 1000000 + 700)
        -- a run never outlives Day 7, recorded or not
        local far = W.locate(c, { [1] = { survived = 6 } }, 1000000 + 700 + 5)
        T.eq(far.run, 2); T.eq(far.startUtc, 1000000 + 700)
    end,

    real_time_boundaries_are_eastern_noons = function(T)
        local W = T.Core.get("week.clock")
        local c = W.config(function(_, d) return d end)
        local s = W.runBounds(c, 1)
        local a = W.locate(c, {}, s + 3600)
        T.eq(a.provisionalEnd, select(2, W.runBounds(c, 1)), "the historical end is the first possible end")
        T.eq(W.boundary(c, s, 7) - W.boundary(c, s, 6) >= 82800, true)
    end,

    -- ----------------------------------------------------------------------------------------- Moody

    the_dice_are_deterministic_and_have_twenty_faces = function(T)
        local M = T.Core.get("week.moody")
        T.eq(#M.FACES, 20)
        local seen = {}
        for n = 1, 400 do
            local d = M.d20("s", 1, n)
            T.ok(d >= 1 and d <= 20); seen[d] = true
            T.eq(d, M.d20("s", 1, n))
        end
        local count = 0
        for _ in pairs(seen) do count = count + 1 end
        T.eq(count, 20, "every face comes up")
    end,

    rolls_come_every_four_hours_from_hour_four = function(T)
        local M = T.Core.get("week.moody")
        local st = M.newState()
        T.eq(#M.step(st, "x", 1, 3.9), 0)
        local made = M.step(st, "x", 1, 4)
        T.ok(#made >= 1)
        T.ok(st.nextRollH >= 6, "next roll scheduled")
        -- a downtime: missed rolls are made late, in order, never twice
        local st2 = M.newState()
        local late = M.step(st2, "x", 1, 30)
        T.ok(#late >= 6)
        T.eq(#M.step(st2, "x", 1, 30), 0)
    end,

    faces_act_on_cadence_conditions_and_each_other = function(T)
        local M = T.Core.get("week.moody")
        -- force faces by id through the internal state: a condition, then the tide turning it
        local st = M.newState()
        st.active = { { id = "packed_calendar", name = "PACKED CALENDAR", fromH = 4, untilH = 8, n = 1 } }
        local fx = M.effects(st, 5)
        T.ok(fx.calendar.street < 1, "packed: more races")
        st.active[1].id = M.face("packed_calendar").opposite
        T.ok(M.effects(st, 5).calendar.street > 1, "the opposite thins them")
        -- effects never include the reservoirs or a survival term
        for k in pairs(fx) do T.ok(k ~= "collapse" and k ~= "safety" and k ~= "survive", "no outcome key " .. k) end
        T.ok(M.effects(st, 9).calendar.street == 1, "expired conditions do nothing")
    end,

    restless_halves_the_cadence = function(T)
        local M = T.Core.get("week.moody")
        local st = M.newState()
        st.restlessUntilH = 20
        st.nextRollH = 8
        local made = M.step(st, "r", 1, 8)
        local delayed = false
        for _, r in ipairs(made) do if r.id == "stable_weather" then delayed = true end end
        T.eq(st.nextRollH, delayed and 8 + 2 + M.CADENCE_H or 10, "restless: two hours (plus any STABLE WEATHER)")
    end,

    the_same_purse_pulls_different_people_differently = function(T)
        local M = T.Core.get("week.moody")
        local rich, riskR = M.pull(1.0, 2.5, { aggression = 30, discipline = 85, need = 0.05 })
        local broke, riskB = M.pull(1.0, 2.5, { aggression = 70, discipline = 35, need = 0.95 })
        local shaken = M.pull(1.0, 2.5, { aggression = 70, discipline = 35, need = 0.95, shaken = 1 })
        T.ok(rich < 1, "the cautious, wealthy driver says no thanks " .. rich)
        T.ok(broke > 1.3, "life-changing money " .. broke)
        T.ok(shaken < broke, "a bad crash yesterday: less keen")
        T.ok(riskB > riskR, "the bait is driven harder by those it caught")
        local a, r = M.pull(0, 2.5, {})
        T.eq(a, 1); T.eq(r, 1)
    end,

    -- ----------------------------------------------------------------------------------------- continuation

    the_state_not_the_dice_decides = function(T)
        local K = T.Core.get("week.continuation")
        local Curve = T.Core.get("week.curve")
        local horrible = { deviation = -Curve.band(72) }
        local middling = { deviation = 0 }
        local great = { deviation = Curve.band(72) }
        local ph, pm, pg = K.probability(72, K.z(horrible, 72)), K.probability(72, K.z(middling, 72)), K.probability(72, K.z(great, 72))
        T.ok(ph < 0.06, "a horrible run: a few per cent " .. ph)
        T.ok(pm > 0.2 and pm < 0.3, "a middling run: 20-30 % " .. pm)
        T.ok(pg > 0.6 and pg < 0.75, "an extraordinary run: 60-70 % " .. pg)
        T.ok(K.probability(72, 5) <= K.PMAX, "never 100 %")
        T.falsy(K.probability(80, 0), "only at a possible end")
    end,

    a_verdict_is_reproducible_and_names_its_kind = function(T)
        local K = T.Core.get("week.continuation")
        local st = { deviation = 0 }
        local a, b = K.judge("seed", 3, 72, st), K.judge("seed", 3, 72, st)
        T.eq(a.u, b.u); T.eq(a.survive, b.survive)
        T.eq(a.kind, a.survive and "continue" or "collapse")
        local last = K.judge("seed", 3, 168, { deviation = 0.45 })
        T.eq(last.kind, last.survive and "complete" or "collapse")
    end,

    -- ----------------------------------------------------------------------------------------- the harness (the gate)

    an_empty_server_mostly_dies_on_day_three = function(T)
        local H = T.Core.get("week.harness")
        local d = H.distribution("gate", 1500)
        T.ok(math.abs(d.conditional[72] - 0.25) < 0.04, "reach Day 4 ~1/4: " .. d.conditional[72])
        T.ok(math.abs(d.conditional[96] - 1 / 3) < 0.08, "Day 4 -> 5 ~1/3: " .. tostring(d.conditional[96]))
        T.ok(math.abs(d.meanZ[72]) < 0.05, "an NPC-only week tracks history: z " .. d.meanZ[72])
    end,
}
