-- paddock.sim, paddock.calibration (doc 44 §6, §7).
local function field(T, n, over)
    local out = {}
    for i = 1, n do
        local a = {}
        for _, k in ipairs(T.Core.get("paddock.attributes").SKILLS) do a[k] = 50 end
        for _, k in ipairs(T.Core.get("paddock.attributes").TRAITS) do a[k] = 50 end
        if over and over[i] then for k, v in pairs(over[i]) do a[k] = v end end
        out[i] = { id = "d" .. i, orgId = "o" .. i, attrs = a, carPerf = 50, form = 0 }
    end
    return out
end
local COURSE = { distanceM = 4800 }
local DRY = { roadWetness = 0, light = "day", family = "dry" }
local WET = { roadWetness = 1, light = "day", family = "wet" }

local function fingerprint(r)
    local parts = {}
    for _, e in ipairs(r.entrants) do parts[#parts + 1] = e.id .. "=" .. tostring(e.finishMs or e.state) end
    return table.concat(parts, ";")
end

return {
    qualifying_gives_times_in_order_and_consistency_narrows_them = function(T)
        -- L250 step 2: a time per entrant against the route base, fastest first, deterministic per seed
        local Sim = T.Core.get("paddock.sim")
        local H = T.Core.get("vocabulary.hash")
        local f = field(T, 12, { [5] = { quali_pace = 90, pace = 85 } })
        local q = Sim.qualify(f, H.stream("seed", "quali", "r1"), 160)
        T.eq(#q, 12)
        for i = 2, #q do T.ok(q[i].qualiMs >= q[i - 1].qualiMs, "times in grid order") end
        T.ok(q[1].qualiMs > 160000 * 0.85 and q[#q].qualiMs < 160000 * 1.3, "times near the base")
        local again = Sim.qualify(field(T, 12, { [5] = { quali_pace = 90, pace = 85 } }), H.stream("seed", "quali", "r1"), 160)
        T.eq(again[1].id, q[1].id); T.eq(again[1].qualiMs, q[1].qualiMs)
        -- the same driver over many sessions: a consistent one varies less
        local function spread(cons)
            local lo, hi = math.huge, -math.huge
            for k = 1, 60 do
                local one = Sim.qualify(field(T, 1, { [1] = { consistency = cons } }), H.stream("spread", k), 160)[1].qualiMs
                lo, hi = math.min(lo, one), math.max(hi, one)
            end
            return hi - lo
        end
        T.ok(spread(95) < spread(20), "consistency narrows the spread")
        local none = Sim.qualify(field(T, 3), H.stream("seed", "x"))
        T.eq(none[1].qualiMs, nil, "no base, no times (order only)")
    end,

    replay_is_identical = function(T)
        local Sim = T.Core.get("paddock.sim")
        local H = T.Core.get("vocabulary.hash")
        local f = field(T, 12)
        local a = Sim.simulate(f, COURSE, DRY, H.stream("seed", "race-1"), { baseSec = 160 })
        local b = Sim.simulate(f, COURSE, DRY, H.stream("seed", "race-1"), { baseSec = 160 })
        T.eq(fingerprint(a), fingerprint(b), "same seed and race, same result")
        local c = Sim.simulate(f, COURSE, DRY, H.stream("seed", "race-2"), { baseSec = 160 })
        T.neq(fingerprint(a), fingerprint(c))
        T.eq(#a.entrants, 12); T.eq(a.simVersion, Sim.SIM_VERSION)
    end,

    golden_result_is_stable = function(T)
        -- A change to the sim that alters outcomes must bump SIM_VERSION and this fingerprint together.
        local Sim = T.Core.get("paddock.sim")
        local H = T.Core.get("vocabulary.hash")
        local f = field(T, 6, { { pace = 70 }, { pace = 60 }, {}, { consistency = 20 }, {}, { pace = 30 } })
        local r = Sim.simulate(f, COURSE, DRY, H.stream("golden", 1), { baseSec = 160 })
        T.eq(H.fnv1a32(fingerprint(r)), 1865222589, "golden fingerprint (Lua 5.4 and LuaJIT must agree)")
        T.eq(Sim.SIM_VERSION, 2)
    end,

    finishers_are_ordered_and_gaps_consistent = function(T)
        local Sim = T.Core.get("paddock.sim")
        local H = T.Core.get("vocabulary.hash")
        for k = 1, 30 do
            local r = Sim.simulate(field(T, 12), COURSE, WET, H.stream("order", k), { baseSec = 160 })
            local prev = -1
            for _, e in ipairs(r.entrants) do
                if e.state == "finished" then
                    T.ok(e.finishMs > prev, "monotonic finishing times"); prev = e.finishMs
                    T.ok(e.gapMs >= 0)
                    T.eq(#e.splits, r.segments, "every segment split recorded")
                end
            end
            for i, e in ipairs(r.entrants) do T.eq(e.position, i) end
        end
    end,

    dnf_rate_near_target_at_stat_50 = function(T)
        local Sim = T.Core.get("paddock.sim")
        local H = T.Core.get("vocabulary.hash")
        local dnf, total = 0, 0
        for k = 1, 2000 do
            local r = Sim.simulate(field(T, 1), COURSE, DRY, H.stream("dnf", k), { baseSec = 160, light = true })
            total = total + 1
            if r.entrants[1].state == "dnf" then dnf = dnf + 1 end
        end
        local rate = dnf / total
        T.ok(rate >= 0.035 and rate <= 0.065, "DNF rate " .. rate .. " within 3.5-6.5% at street chaos (sim v2, L236)")
    end,

    faster_drivers_win_more = function(T)
        local Sim = T.Core.get("paddock.sim")
        local H = T.Core.get("vocabulary.hash")
        local wins = 0
        for k = 1, 300 do
            local r = Sim.simulate(field(T, 8, { [4] = { pace = 80, race_pace = 80 } }), COURSE, DRY, H.stream("fast", k), { baseSec = 160, light = true })
            if r.order[1] == "d4" then wins = wins + 1 end
        end
        -- street chaos (sim v2): talent shows at well over twice parity (37.5 of 300), but the street still bites
        T.ok(wins > 95, "a clearly faster driver from mid-grid wins far above parity: " .. wins .. "/300")
        T.ok(wins < 300, "but not all of them")
    end,

    wet_effect_is_monotonic_and_rewards_wet_skill = function(T)
        local Sim = T.Core.get("paddock.sim")
        local mid = { wet_weather_skill = 50 }
        local f0 = Sim.conditionFactor(mid, { roadWetness = 0 })
        local f5 = Sim.conditionFactor(mid, { roadWetness = 0.5 })
        local f1 = Sim.conditionFactor(mid, { roadWetness = 1 })
        T.ok(f0 < f5 and f5 < f1, "wetter is slower")
        T.ok(Sim.conditionFactor({ wet_weather_skill = 90 }, { roadWetness = 1 }) < f1, "a wet specialist loses less")
        T.ok(Sim.conditionRisk(WET) > Sim.conditionRisk(DRY), "wet is riskier")
        local H = T.Core.get("vocabulary.hash")
        local wins = 0
        for k = 1, 300 do
            local r = Sim.simulate(field(T, 8, { [4] = { wet_weather_skill = 95 } }), COURSE, WET, H.stream("rain", k), { baseSec = 160, light = true })
            if r.order[1] == "d4" then wins = wins + 1 end
        end
        T.ok(wins > 300 / 8 * 1.5, "a rain specialist wins well above parity in the wet: " .. wins)
    end,

    calibration_baseline_and_human_override = function(T)
        local Cal = T.Core.get("paddock.calibration")
        local route = { routeId = "r", distanceM = 3000 }
        local base, src = Cal.basePace(1, route, "street", DRY, nil)
        T.eq(src, "baseline"); T.ok(base > 120 and base < 160, "about 140 s for 3 km crow-flies (~4.2 km of road) at street pace: " .. base)
        local _, src2 = Cal.basePace(1, route, "street", DRY, { n = 5, drivers = 2, median = 90000 })
        T.eq(src2, "baseline", "too little human data keeps the declared baseline")
        local s = Cal.summarise({ { ms = 90000, driverId = "a" }, { ms = 92000, driverId = "b" }, { ms = 91000, driverId = "c" },
            { ms = 95000, driverId = "a" }, { ms = 89000, driverId = "b" }, { ms = 93000, driverId = "c" },
            { ms = 94000, driverId = "a" }, { ms = 96000, driverId = "b" } })
        T.eq(s.n, 8); T.eq(s.drivers, 3); T.eq(s.median, 92500)
        local hb, hsrc = Cal.basePace(1, route, "street", DRY, s)
        T.eq(hsrc, "human"); T.eq(hb, 92.5)
        local wb = Cal.basePace(1, route, "street", WET, { n = 8, drivers = 3, median = 100000, cond = WET })
        T.ok(wb < 100, "a wet human median has the rain backed out")
        T.ok(Cal.basePace(1, route, "premier", DRY) < Cal.basePace(1, route, "street", DRY), "premier is faster")
    end,
}
