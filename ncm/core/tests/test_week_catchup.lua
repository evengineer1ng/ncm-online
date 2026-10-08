-- week.catchup: the present after an absence is calculated, never simulated (L338; L330 (4)).
-- Compressed days (100 s) keep the arithmetic readable; the rules are the real ones.
local function cfg() return { epoch = 1000000, daySeconds = 100, boundarySod = 0 } end
local function seeds(tape) return function(n) return tape .. "|racing-week|" .. n end end

local function sameTimeline(T, a, b, label)
    local n = 0
    for k, v in pairs(a) do
        n = n + 1
        local w = b[k]
        T.truthy(w, label .. ": run " .. k .. " present in both")
        T.eq(v.endUtc, w.endUtc, label .. ": run " .. k .. " end")
        T.eq(v.endKind, w.endKind, label .. ": run " .. k .. " kind")
    end
    for k in pairs(b) do T.truthy(a[k], label .. ": run " .. k .. " present in both") end
    return n
end

return {
    nothing_is_due_before_the_first_possible_end = function(T)
        local C = T.Core.get("week.catchup")
        local s = C.settle(cfg(), {}, 1000000 + 250, seeds("sp-a"))
        T.eq(#s.verdicts, 0)
    end,

    every_boundary_passed_while_away_is_judged_in_order = function(T)
        local C = T.Core.get("week.catchup")
        local s = C.settle(cfg(), {}, 1000000 + 100 * 60, seeds("sp-a"))
        T.truthy(#s.verdicts >= 8, "two months of compressed days produce many verdicts")
        local lastAt = 0
        for i, v in ipairs(s.verdicts) do
            T.truthy(v.atUtc >= lastAt, "verdict " .. i .. " is in time order")
            lastAt = v.atUtc
            T.truthy(v.hours >= 72 and v.hours <= 168, "verdicts only at possible ends")
            T.truthy(v.unattended, "nobody lived these runs")
        end
        -- every ended run ended at a possible end: Day 3 .. Day 7
        for n, r in pairs(s.runs) do
            if r.endUtc then
                local W = T.Core.get("week.clock")
                local start = n == 1 and W.runBounds(cfg(), 1) or s.runs[n - 1].endUtc
                local days = (r.endUtc - start) / 100
                T.truthy(days >= 3 and days <= 7 and days == math.floor(days), "run " .. n .. " lasted " .. days .. " days")
            end
        end
    end,

    catching_up_in_one_step_equals_living_through_it = function(T)
        local C = T.Core.get("week.catchup")
        local target = 1000000 + 100 * 45
        local once = C.settle(cfg(), {}, target, seeds("sp-a"))
        -- the same span visited every 37 s (a running world) and once a fortnight (a returning player)
        for _, stride in ipairs({ 37, 1400 }) do
            local runs = {}
            local t = 1000000
            while t < target do
                t = math.min(target, t + stride)
                runs = C.settle(cfg(), runs, t, seeds("sp-a")).runs
            end
            sameTimeline(T, once.runs, runs, "stride " .. stride)
        end
    end,

    two_tapes_are_two_histories = function(T)
        local C = T.Core.get("week.catchup")
        local t = 1000000 + 100 * 80
        local a = C.settle(cfg(), {}, t, seeds("sp-tape-01"))
        local b = C.settle(cfg(), {}, t, seeds("sp-tape-02"))
        local differs = false
        for n, r in pairs(a.runs) do if not b.runs[n] or b.runs[n].endUtc ~= r.endUtc then differs = true end end
        T.truthy(differs, "different seeds give different timelines")
        -- and settling A never changes B's inputs
        local again = C.settle(cfg(), {}, t, seeds("sp-tape-02"))
        sameTimeline(T, b.runs, again.runs, "B repeated")
    end,

    the_live_run_is_judged_on_the_standing_it_was_left_with = function(T)
        local C = T.Core.get("week.catchup")
        local Cont = T.Core.get("week.continuation")
        local t = 1000000 + 300 + 1          -- just past run 1's first possible end
        local good = C.settle(cfg(), {}, t, seeds("sp-a"), function(n) return n == 1 and { deviation = 10 } or nil end)
        local v = good.verdicts[1]
        T.falsy(v.unattended)
        T.eq(v.p, Cont.probability(72, 1))
        local bare = C.settle(cfg(), {}, t, seeds("sp-a"))
        T.eq(bare.verdicts[1].p, Cont.probability(72, 0))
        T.eq(bare.verdicts[1].u, v.u, "the draw is the same; only the odds moved")
    end,

    history_mode_ends_every_run_at_hour_72 = function(T)
        local C = T.Core.get("week.catchup")
        local s = C.settle(cfg(), {}, 1000000 + 100 * 30, seeds("sp-a"), nil, { mode = "history" })
        T.eq(#s.verdicts, 10)
        for _, v in ipairs(s.verdicts) do T.eq(v.hours, 72); T.eq(v.kind, "collapse") end
    end,

    a_run_never_outlives_day_seven = function(T)
        local C = T.Core.get("week.catchup")
        -- a run that has survived to Day 7 is judged at hour 168 and ends either way
        local s = C.settle(cfg(), { [1] = { survived = 6 } }, 1000000 + 700, seeds("sp-a"))
        T.eq(s.verdicts[1].hours, 168)
        T.truthy(s.runs[1].endUtc == 1000000 + 700, "ended at Day 7's noon")
        T.truthy(s.runs[1].endKind == "complete" or s.runs[1].endKind == "collapse")
    end,

    the_present_after_nineteen_days_is_a_later_week = function(T)
        local C = T.Core.get("week.catchup")
        local now = 1000000 + 100 * 19 + 50
        local p, s = C.present(cfg(), {}, now, seeds("sp-a"))
        T.truthy(p.runIndex >= 3, "19 days later is at least the third Racing Week (got " .. p.runIndex .. ")")
        T.truthy(p.day >= 1 and p.day <= 7)
        T.truthy(not p.beyond, "the present is settled")
        T.truthy(#s.verdicts >= p.runIndex - 1)
    end,
}
