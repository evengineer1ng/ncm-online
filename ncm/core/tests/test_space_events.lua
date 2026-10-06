-- Relay and multi-leg events (L322; doc 54 §L-§M): continuity through every leg; the triathlon in both forms;
-- discovery gates visibility.
local function get(T, n) return T.Core.get(n) end

local Z = { centre = { 0, 0, 0 }, radiusM = 20 }
local function st(x, vx) return { pos = { x, 0, 0 }, vel = { vx or 0, 0, 0 } } end

return {
    a_handoff_needs_both_machines_together = function(T)
        local Relay = get(T, "space.relay")
        local r = Relay.new({ { zone = Z }, { zone = Z }, { zone = Z }, { zone = Z }, { zone = Z }, {} },
            { "m1", "m2", "m3", "m4", "m5", "m6" })
        T.eq(#r.team, 6, "N legs is data: six here")
        local ev
        for k = 1, 30 do ev = Relay.exchange(r, st(5, 10), st(-5, 10.5), k * 0.05, 0.05) or ev end
        T.eq(r.holder, "m2", "matched within the zone for a second: the token moves")
        T.truthy(Relay.counts(r, "m2") and not Relay.counts(r, "m1"), "only the holder's leg counts")
    end,

    too_fast_or_outside_the_zone_is_no_handoff = function(T)
        local Relay = get(T, "space.relay")
        local fast = Relay.new({ { zone = Z }, {} }, { "a", "b" })
        for k = 1, 60 do Relay.exchange(fast, st(5, 20), st(-5, 10), k * 0.05, 0.05) end
        T.eq(fast.holder, "a", "10 m/s apart: no transfer")
        local out = Relay.new({ { zone = Z }, {} }, { "a", "b" })
        for k = 1, 60 do Relay.exchange(out, st(5), st(40), k * 0.05, 0.05) end
        T.eq(out.holder, "a", "the outgoing machine outside the zone: no transfer")
    end,

    leaving_without_the_token_is_a_fault = function(T)
        local Relay = get(T, "space.relay")
        local r = Relay.new({ { zone = Z }, {} }, { "a", "b" })
        Relay.exchange(r, st(30), st(0), 0.05, 0.05)
        local ev = Relay.exchange(r, st(30), st(50), 0.10, 0.05)
        T.eq(ev and ev.fault, "early departure", "the outgoing racer left the zone before the token moved")
        T.eq(#r.faults, 1, "recorded")
    end,

    triathlon_formats_score_differently = function(T)
        local ME = get(T, "space.multievent")
        local legs = { { domain = "night_city", discipline = "street" }, { domain = "los_santos", discipline = "street" },
            { domain = "snowglobe", discipline = "fireball" } }
        local results = {
            { { id = "A", position = 1, state = "finished", raceS = 300, startT = 0 }, { id = "B", position = 2, state = "finished", raceS = 310, startT = 0 } },
            { { id = "B", position = 1, state = "finished", raceS = 280 }, { id = "A", position = 2, state = "finished", raceS = 285 } },
            { { id = "A", position = 1, state = "finished", raceS = 400, finishT = 5000 }, { id = "B", position = 2, state = "finished", raceS = 380, finishT = 4500 } },
        }
        local pts = ME.score({ format = "points", legs = legs }, results)
        T.eq(pts[1].id, "A", "points: two wins beat one")
        local sum = ME.score({ format = "sum", legs = legs }, results)
        T.eq(sum[1].id, "B", "sum of race times: 970 s beats 985 s")
        local nonstop = ME.score({ format = "nonstop", legs = legs }, results)
        T.eq(nonstop[1].id, "B", "nonstop: B's whole day, travel included, was shorter")
        T.eq(nonstop[1].totalS, 4500, "first green to last flag")
        results[2][2].state = "dnf"
        T.eq(ME.score({ format = "sum", legs = legs }, results)[1].id, "B", "a DNF anywhere is out of a sum")
    end,

    the_cross_domain_event_is_invisible_until_discovered = function(T)
        local ME = get(T, "space.multievent")
        local ev = { id = "tri", format = "points", legs = { { domain = "night_city" }, { domain = "los_santos" }, { domain = "snowglobe" } } }
        T.truthy(ME.validate(ev), "a valid three-domain event")
        T.falsy(ME.visibleTo(ev, { discovered = {} }), "a Night City newcomer never sees it")
        T.falsy(ME.visibleTo(ev, { discovered = { los_santos = true } }), "nor someone who found Los Santos but not Snowglobe")
        T.truthy(ME.visibleTo(ev, { discovered = { los_santos = true, snowglobe = true } }), "only someone who has been there")
        T.falsy(ME.validate({ format = "points", legs = { { domain = "mars" }, { domain = "night_city" } } }), "unknown domains are refused")
    end,
}
