-- world.speed_limits and week.clock (L301): the Day's advertised limits over the game's own lane speeds.
local function realData(T)
    if NcmLaneLimitsData then return NcmLaneLimitsData end
    local path = T.root .. "/../online/resources/ncm_speed/server/lane_limits_data.lua"
    local f = io.open(path, "r")
    if not f then return nil end
    f:close()
    dofile(path)
    return NcmLaneLimitsData
end

local realIdx
local function idx(T)
    if realIdx then return realIdx end
    local data = realData(T)
    if not data then return nil end
    realIdx = T.Core.get("world.speed_limits").build(data)
    return realIdx
end

return {
    signs_round_to_five_kph_per_factor = function(T)
        local S = T.Core.get("world.speed_limits")
        local _, d1 = S.advertised(15, 0.75); T.eq(d1, 40)
        local _, d2 = S.advertised(15, 1.6); T.eq(d2, 85)
        local _, d3 = S.advertised(15, 1.0); T.eq(d3, 55)
        local _, a = S.advertised(17, 0.75); T.eq(a, 45)
        local _, b = S.advertised(17, 1.6); T.eq(b, 100)
        local _, c = S.advertised(10, 0.75); T.eq(c, 25)
        local _, e = S.advertised(15, 0.8); T.eq(e, 45)
    end,

    synthetic_lane_lookup_prefers_aligned_road_and_skips_overpass = function(T)
        local S = T.Core.get("world.speed_limits")
        -- an east-west street at z 0 (15 m/s), a north-south street crossing it (10 m/s), a flyover above (17 m/s)
        local data = { [15] = "-100,0,0;0,0,0;100,0,0", [10] = "0,-100,0;0,0,0;0,100,0", [17] = "-100,2,12;100,2,12" }
        local idx_ = S.build(data)
        local id, mps = S.nearest(idx_, 30, 1, 0, 0)
        T.eq(mps, 15, "driving east on the street")
        local id2, mps2 = S.nearest(idx_, 1, 30, 0, 90)
        T.eq(mps2, 10, "driving north on the cross street")
        local _, up = S.nearest(idx_, 30, 2, 12, 0)
        T.eq(up, 17, "the flyover is its own road")
        T.eq(S.nearest(idx_, 30, 50, 0, 0), nil, "off-road has no sign")
        -- hysteresis: at the junction, the previous lane is kept
        local keep = S.nearest(idx_, 2, 2, 0, 0, id)
        T.eq(keep, id)
        T.neq(id, id2)
    end,

    real_index_reads_the_game_posted_speeds = function(T)
        local S = T.Core.get("world.speed_limits")
        local I = idx(T)
        if not I then return end                                   -- data not generated in this checkout
        T.ok(I.count > 19000, "vehicle lanes loaded: " .. I.count)
        local _, corpo = S.nearest(I, -1103, -19, 8, nil); T.eq(corpo, 17, "Corpo Plaza")
        local _, glen = S.nearest(I, -1776, -1371, 35, nil); T.eq(glen, 15, "Glen Straight")
        local _, hwy = S.nearest(I, -1110, 342, 26, nil); T.eq(hwy, 17, "Central Highway")
    end,

    excess_window_and_wanted_are_proportional_and_capped = function(T)
        local S = T.Core.get("world.speed_limits")
        local st = S.newState()
        local adv = 40 / 3.6
        -- 20 km/h over the sign (15 over the grace) for 60 s
        for t = 1, 60 do S.account(st, adv + 20 / 3.6, adv, 1, t) end
        T.ok(math.abs(st.excess60 - 250) < 1, "excess " .. st.excess60)
        T.eq(S.wanted(st.excess60, 5, 150), 2)
        T.eq(S.wanted(st.excess60, 1, 150), 1, "the cap holds")
        T.eq(S.wanted(st.excess60, 5, 300), 1, "a tolerant city sets a higher bar")
        T.eq(S.wanted(10000, 5, 150), 5)
        -- a minute of clean driving empties the window
        for t = 61, 121 do S.account(st, adv, adv, 1, t) end
        T.eq(st.excess60, 0)
        -- under the grace is not over
        local g = S.newState(); S.account(g, adv + 4 / 3.6, adv, 1, 1); T.eq(g.excess60, 0)
        -- off-road accrues nothing; a gap is clamped
        local o = S.newState(); S.account(o, 50, nil, 1, 1); S.account(o, 50, adv, 30, 31)
        T.ok(o.excess60 <= 2 * 50, "gap clamped")
    end,

    race_costs_follow_the_organisers_rule = function(T)
        local S = T.Core.get("world.speed_limits")
        local adv = 40 / 3.6
        local function run(rule)
            local st = S.newState(); S.raceStart(st)
            local due = {}
            for t = 1, 300 do
                S.account(st, adv + 60 / 3.6, adv, 1, t)            -- 55 km/h over the grace for five minutes
                local d = S.raceDue(st, rule)
                if d then due[#due + 1] = d end
            end
            return st, due
        end
        local st1, d1 = run("penalty")
        T.eq(st1.penaltyS, 30, "Day 1 penalties capped at 30 s")
        T.ok(#d1 >= 2 and d1[1].penaltyS == 5, "issued in 5 s steps")
        local _, d2 = run("warning")
        T.ok(#d2 >= 1 and d2[1].warning == 1 and d2[1].penaltyS == nil, "Day 2 warns")
        local _, d3 = run("police")
        T.eq(#d3, 0, "Day 3 is police only")
    end,

    week_clock_counts_three_days_and_never_four = function(T)
        local W = T.Core.get("week.clock")
        -- compressed: 100 s days
        local epoch = 1790000000
        local a = W.at(epoch, epoch + 5, { daySeconds = 100 }); T.eq(a.runIndex, 1); T.eq(a.day, 1)
        local b = W.at(epoch, epoch + 250, { daySeconds = 100 }); T.eq(b.day, 3); T.eq(b.secondsIntoDay, 50)
        local c = W.at(epoch, epoch + 300, { daySeconds = 100 }); T.eq(c.runIndex, 2); T.eq(c.day, 1)
        T.eq(W.at(epoch, epoch - 1, { daySeconds = 100 }), nil)
        T.ok(math.abs(b.hours - 60) < 1e-9, "compressed hours are run hours")
        T.eq(b.secondsRemaining, 50)
        local o = W.at(epoch, epoch + 5, { daySeconds = 100, hours = 50 }); T.eq(o.day, 3); T.truthy(o.overridden)
        T.ok(math.abs(o.phase - 50 / 72) < 1e-9)
    end,

    week_clock_real_days_turn_at_six_eastern = function(T)
        local W = T.Core.get("week.clock")
        -- 2026-10-03 is EDT (UTC-4): 06:00 ET = 10:00 UTC. Epoch at 12:00 UTC on 10-03 -> Day 1 of run 1.
        local day0 = 1790985600            -- 2026-10-03 00:00:00 UTC
        local epoch = day0 + 12 * 3600
        local six = { boundarySod = 6 * 3600 }
        T.eq(W.at(epoch, day0 + 9 * 3600 + 3599 + 86400, six).day, 1, "05:59 ET on 10-04 is still Day 1")
        T.eq(W.at(epoch, day0 + 10 * 3600 + 86400, six).day, 2, "06:00 ET on 10-04 is Day 2")
        local r = W.at(epoch, day0 + 10 * 3600 + 3 * 86400, six)
        T.eq(r.runIndex, 2); T.eq(r.day, 1)
        T.eq(W.at(epoch, day0 + 9 * 3600, six), nil, "before the epoch's own Day")
    end,

    week_clock_noon_is_the_default_boundary_and_runs_have_bounds = function(T)
        local W = T.Core.get("week.clock")
        local cfg = W.config(function(_, d) return d end)            -- no convars: the defaults
        T.eq(cfg.boundarySod, 12 * 3600)
        T.eq(cfg.epoch, W.DEFAULT_EPOCH)
        local s1, e1 = W.runBounds(cfg, 1)
        T.eq(s1, 1791043200, "run 1 opens 12:00 ET 2026-10-03")
        T.eq(e1, 1791043200 + 3 * 86400, "and ends 72 h later (no DST change inside)")
        T.eq(W.now(cfg, e1 - 1).runIndex, 1)
        local at = W.now(cfg, e1)
        T.eq(at.runIndex, 2); T.eq(at.day, 1); T.ok(at.hours < 1e-9)
        local c = { epoch = 1000, daySeconds = 100 }
        local s, e = W.runBounds(c, 2); T.eq(s, 1300); T.eq(e, 1600)
    end,
}
