-- competition.incidents + race corrected time (L56, P39): zero-fault bands, escalation, dedupe, classification.
local function gatesFor(T)
    local Gates = T.Core.get("course.gates")
    return Gates.build({ name = "r", start = { x = 0, y = 0, z = 0, name = "s" }, finish = { x = 0, y = 1000, z = 0, name = "f" } })
end

return {
    bands_and_escalation = function(T)
        local I = T.Core.get("competition.incidents")
        T.eq(I.band(1.0), 0); T.eq(I.band(2.0), 1); T.eq(I.band(7.5), 2); T.eq(I.band(30), 3)
        T.eq(I.seconds(1, 0), 2); T.eq(I.seconds(2, 0), 4); T.eq(I.seconds(3, 0), 8)
        T.eq(I.seconds(1, 1), 3, "second incident escalates x1.5"); T.eq(I.seconds(1, 10), 6, "capped at maxMult")
        T.eq(I.seconds(0, 0), 0)
        T.eq(I.band(2.0, { bands = { { dv = 3, mult = 1 }, { dv = 6, mult = 2 }, { dv = 12, mult = 4 } } }), 0, "discipline overrides")
    end,

    car_car_is_symmetric_and_deduped = function(T)
        local I = T.Core.get("competition.incidents")
        local a = { driverId = "a", prev = { t = 0, x = 0, y = 0, v = 20 }, cur = { t = 0.2, x = 0, y = 4, v = 20 } }   -- 20 m/s north
        local b = { driverId = "b", prev = { t = 0, x = 3, y = 4, v = 12 }, cur = { t = 0.2, x = 3, y = 6.4, v = 12 } } -- 12 m/s north, 3 m to the side
        local ra, rb = I.carCar(a, b)
        T.ok(ra and rb, "contact within contactM produces two records")
        T.eq(ra.other, "b"); T.eq(rb.other, "a"); T.eq(ra.band, rb.band); T.eq(ra.band, 2, "8 m/s closing = x2")
        T.eq(ra.attributed, "both", "zero-fault")
        local far = { driverId = "c", prev = { t = 0, x = 20, y = 0, v = 0 }, cur = { t = 0.2, x = 20, y = 0, v = 0 } }
        T.eq(I.carCar(a, far), nil, "apart: nothing")
        local slow = { driverId = "d", prev = { t = 0, x = 2, y = 5, v = 19 }, cur = { t = 0.2, x = 2, y = 8.8, v = 19 } }
        T.eq(I.carCar(a, slow), nil, "rubbing at the same speed: below band 1")
        local tp = { driverId = "e", prev = { t = 0, x = 500, y = 500, v = 0 }, cur = { t = 0.2, x = 1, y = 5, v = 0 } }
        T.eq(I.carCar(a, tp), nil, "a teleport next to you is not a contact")
        local L = I.Ledger.new()
        T.ok(L:add("a", ra), "first logged"); T.eq(L:add("b", rb) and true, true, "the pair's second record is the other driver")
        local again = { kind = "car", band = 1, other = "b", t = 1.0 }
        T.eq(L:add("a", again), nil, "same pair within dedupeSec is dropped")
        T.eq(L:count("a"), 1); T.eq(L:sum("a"), 4)
        local later = { kind = "car", band = 1, other = "b", t = 5.0 }
        T.ok(L:add("a", later), "after the window it counts"); T.eq(L:sum("a"), 4 + 3, "escalated second incident")
    end,

    object_contact_needs_no_neighbour = function(T)
        local I = T.Core.get("competition.incidents")
        local prev, cur = { t = 0, x = 0, y = 0, v = 25, h = 1.0 }, { t = 0.4, x = 0, y = 6, v = 5, h = 0.9 }
        local rec = I.object(prev, cur, {})
        T.ok(rec and rec.kind == "object" and rec.band == 3, "25 -> 5 m/s in 0.4 s is a wall")
        T.eq(I.object(prev, cur, { { x = 2, y = 7 } }), nil, "a car beside you: that was car contact, scored elsewhere")
        T.eq(I.object({ t = 0, x = 0, y = 0, v = 25 }, { t = 0.4, x = 0, y = 9, v = 22 }, {}), nil, "gentle braking is not an incident")
        local hp = I.object({ t = 0, x = 0, y = 0, v = 10, h = 1.0 }, { t = 0.3, x = 0, y = 3, v = 9, h = 0.8 }, {})
        T.ok(hp and hp.band == 1, "a health drop alone is a x1 object hit")
    end,

    damage_change_is_canonical_object_evidence = function(T)
        local I = T.Core.get("competition.incidents")
        local before = { health = 1, bodyDamage = { 0, 0 }, brokenGlass = 0, brokenLights = 0, tires = 0 }
        local after = { health = 0.96, bodyDamage = { 0.03, 0 }, brokenGlass = 1, brokenLights = 0, tires = 0 }
        local rec = I.damage(before, after, 15, { x = 4, y = 5, z = 6 }, 10)
        T.ok(rec and rec.kind == "object" and rec.signal == "vehicle_damage", "canonical damage becomes object evidence")
        T.eq(I.damage(after, after, 15, {}, 11), nil, "unchanged snapshot is not another incident")
    end,

    one_crash_episode_is_coalesced_but_a_later_crash_counts = function(T)
        local I = T.Core.get("competition.incidents")
        local L = I.Ledger.new()
        T.ok(L:add("a", { kind = "object", band = 2, t = 10, x = 0, y = 0 }))
        local again, why = L:add("a", { kind = "object", band = 1, t = 11, x = 3, y = 2 })
        T.eq(again, nil); T.eq(why, "coalesced", "sustained barrier callbacks are one episode")
        T.ok(L:add("a", { kind = "object", band = 1, t = 20, x = 3, y = 2 }), "later independent impact counts")
        T.eq(L:count("a"), 2)
    end,

    kb34_unaligned_samples_are_never_compared = function(T)
        local I = T.Core.get("competition.incidents")
        -- the same contact as car_car_is_symmetric_and_deduped, but b was sampled a third of a second later
        local a = { driverId = "a", prev = { t = 0, x = 0, y = 0, v = 20 }, cur = { t = 0.2, x = 0, y = 4, v = 20 } }
        local b = { driverId = "b", prev = { t = 0.33, x = 3, y = 4, v = 12 }, cur = { t = 0.53, x = 3, y = 6.4, v = 12 } }
        local ra, why = I.carCar(a, b)
        T.eq(ra, nil, "samples taken a third of a second apart are not evidence of contact")
        T.eq(why, "unaligned")
        local aligned = { driverId = "b", prev = { t = 0.2, x = 3, y = 4, v = 12 }, cur = { t = 0.4, x = 3, y = 6.4, v = 12 } }
        T.ok(I.carCar(a, aligned) ~= nil, "within alignSec it is judged normally")
    end,

    kb34_unplaceable_neighbour_blocks_an_object_verdict = function(T)
        local I = T.Core.get("competition.incidents")
        local prev, cur = { t = 10.0, x = 0, y = 0, v = 25, h = 1.0 }, { t = 10.4, x = 0, y = 6, v = 5, h = 0.9 }
        T.ok(I.object(prev, cur, {}) ~= nil, "alone on track, a hard stop is scenery")
        -- the other car last seen a second ago and 40 m away proves nothing about where it is now
        local rec, why = I.object(prev, cur, { { t = 9.4, x = 40, y = 0 } })
        T.eq(rec, nil, "a stale neighbour cannot clear this of car contact")
        T.eq(why, "neighbour_unknown")
        T.eq(I.object(prev, cur, { { x = 40, y = 0 } }), nil, "a neighbour with no timestamp cannot either")
        T.ok(I.object(prev, cur, { { t = 10.4, x = 40, y = 0 } }) ~= nil, "a fresh neighbour genuinely elsewhere does clear it")
    end,

    kb34_interpolation_places_two_drivers_at_one_instant = function(T)
        local Tm = T.Core.get("telemetry")
        local w = { { t = 10.0, x = 0, y = 0, v = 20, client = true }, { t = 10.2, x = 0, y = 4, v = 20, client = true } }
        local mid = Tm.sampleAt(w, 10.1)
        T.ok(mid ~= nil); T.eq(mid.y, 2, "halfway between the two samples")
        T.eq(mid.t, 10.1); T.eq(mid.client, true, "interpolating two client samples stays a client sample")
        local rich = Tm.sampleAt({ { t = 1, x = 0, y = 0, v = 1, h = 1, og = true }, { t = 2, x = 1, y = 0, v = 1, h = 0.8, og = true } }, 1.5)
        T.eq(rich.h, 0.9, "health survives interpolation for incident detection"); T.eq(rich.og, true)
        T.eq(Tm.sampleAt(w, 10.2).y, 4, "an exact hit returns that sample's position")
        T.eq(Tm.sampleAt(w, 10.5), nil, "never extrapolated past the newest sample")
        T.eq(Tm.sampleAt(w, 9.5), nil, "never extrapolated before the oldest")
        T.eq(Tm.sampleAt({}, 10.1), nil, "no samples, no position")
    end,

    corrected_time_decides_the_result = function(T)
        local Race = T.Core.get("session.race")
        local g = gatesFor(T)
        local s = Race.new({ sessionId = "c", startsAt = 1000, gates = g, entrants = { { driverId = "fast", slot = 1 }, { driverId = "clean", slot = 2 } } })
        Race.mark(s, "fast", true); Race.mark(s, "clean", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        T.eq(s.phase, "running")
        local at = function(gate) return { x = gate.x, y = gate.y } end
        Race.report(s, { driverId = "fast", gateIndex = 1, now = 1001, position = at(g[1]) })
        Race.report(s, { driverId = "clean", gateIndex = 1, now = 1001, position = at(g[1]) })
        local e = Race.incident(s, "fast", { kind = "car", band = 2, seconds = 8, other = "clean" }, 1050)
        T.eq(e[1].type, "incident"); T.eq(e[1].incidentSec, 8); T.eq(s.entrants.fast.incidentCount, 1)
        Race.report(s, { driverId = "fast", gateIndex = 2, now = 1100, position = at(g[2]) })    -- raw 100 s, corrected 108
        Race.report(s, { driverId = "clean", gateIndex = 2, now = 1105, position = at(g[2]) })   -- raw 105 s, corrected 105
        T.eq(s.entrants.fast.totalSec, 100); T.eq(s.entrants.fast.correctedSec, 108); T.eq(s.entrants.clean.correctedSec, 105)
        local res = Race.classify(s)
        T.eq(res[1].driverId, "clean", "the cleaner slower car wins on corrected time")
        T.eq(res[2].incidentSec, 8); T.eq(res[2].incidentCount, 1); T.eq(res[2].gapSec, 3)
        T.eq(res[1].correctedSec, 105)
        local view = Race.publicView(s)
        T.eq(view.entrants[1].incidentSec, 8); T.eq(view.entrants[1].correctedSec, 108); T.eq(view.kind, "race")
        -- a race-control penalty stacks separately and also moves the corrected time
        Race.penalty(s, "clean", 10, "cut", 1110)
        T.eq(s.entrants.clean.totalSec, 115); T.eq(s.entrants.clean.correctedSec, 115)
        T.eq(Race.classify(s)[1].driverId, "fast")
    end,

    hold_waits_for_the_field_then_releases = function(T)
        local Race = T.Core.get("session.race")
        local g = gatesFor(T)
        local s = Race.new({ sessionId = "h", startsAt = 1000, gates = g, rules = { hold = true, holdReleasePct = 0.75, holdMaxWaitSec = 60 },
            entrants = { { driverId = "a", slot = 1 }, { driverId = "b", slot = 2 }, { driverId = "c", slot = 3 }, { driverId = "d", slot = 4 } } })
        Race.mark(s, "a", true); Race.mark(s, "b", true)
        local e = Race.step(s, 970)
        T.eq(s.phase, "gridded"); T.eq(#e, 1, "no DNS at the grid check while holding")
        e = Race.step(s, 995)
        T.eq(e[1].type, "hold"); T.eq(e[1].ready, 2); T.eq(e[1].total, 4); T.eq(s.phase, "gridded")
        T.ok(s.startsAt > 1000, "the start slides while holding")
        T.eq(#Race.step(s, 1000), 0, "no new hold event while the count is unchanged")
        Race.mark(s, "c", true)
        e = Race.step(s, 1002)
        T.eq(s.phase, "countdown", "3 of 4 = 75%: released")
        local dns = 0
        for _, x in ipairs(e) do if x.type == "dns" then dns = dns + 1 end end
        T.eq(dns, 0, "release is not green: nobody is DNS yet")
        T.ok(s.startsAt >= 1002 + 5, "lights run their full count from release")
        T.eq(s.hold, nil)
        e = Race.step(s, s.startsAt)
        dns = 0
        for _, x in ipairs(e) do if x.type == "dns" then dns = dns + 1 end end
        T.eq(dns, 1, "the absent driver is DNS at green"); T.eq(s.entrants.d.state, "dns")
    end,

    hold_deadline_releases_whoever_is_there = function(T)
        local Race = T.Core.get("session.race")
        local g = gatesFor(T)
        local s = Race.new({ sessionId = "h2", startsAt = 1000, gates = g, rules = { hold = true, holdMaxWaitSec = 60 },
            entrants = { { driverId = "a", slot = 1 }, { driverId = "b", slot = 2 } } })
        Race.mark(s, "a", true)
        Race.step(s, 970); Race.step(s, 995)
        T.eq(s.phase, "gridded")
        Race.step(s, 1030); T.eq(s.phase, "gridded", "still holding before the deadline")
        Race.step(s, 1056); T.eq(s.phase, "countdown", "deadline - countdown: go with who is there")
        T.eq(s.entrants.b.state, "entered", "still time to reach the mark")
        Race.step(s, s.startsAt); T.eq(s.entrants.b.state, "dns", "DNS at green")
        local view = Race.publicView(s)
        T.eq(view.originalStartsAt, 1000)
    end,

    street_races_do_not_hold = function(T)
        local Race = T.Core.get("session.race")
        local g = gatesFor(T)
        local s = Race.new({ sessionId = "n", startsAt = 1000, gates = g, entrants = { { driverId = "a", slot = 1 }, { driverId = "b", slot = 2 } } })
        Race.mark(s, "a", true)
        local e = Race.step(s, 970)
        T.eq(e[1].type, "phase", "the grid check marks nobody DNS (one rule for every race, 2026-10-02)")
        Race.step(s, 995); T.eq(s.phase, "countdown", "a street race does not hold")
        Race.step(s, 1000); T.eq(s.entrants.b.state, "dns", "absent at green is DNS")
    end,
}
