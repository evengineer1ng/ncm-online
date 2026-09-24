-- session.race / session.grid / course.gates tests (M3.2 completion criterion 1).
local function route(T)
    return T.Core.get("course.routes").resolve("root_tip_1035_3652__to__trench_2899_2711", "Tip-to-Trench")
end

local function course(T, intermediate)
    local G = T.Core.get("course.gates")
    local g = G.build(route(T), { intermediate = intermediate })
    return g
end

GATES = nil
local function session(T, opts)
    local Race = T.Core.get("session.race")
    opts = opts or {}
    local g = course(T, opts.intermediate)
    GATES = g
    local entrants = opts.entrants or {
        { driverId = "d1", entryId = "e1", slot = 1, display = "One" },
        { driverId = "d2", entryId = "e2", slot = 2, display = "Two" },
    }
    return Race.new({ sessionId = "s1", eventId = "ev", startsAt = 1000, gates = g, entrants = entrants, rules = opts.rules }), g
end

local function types(events)
    local out = {}
    for _, e in ipairs(events) do out[#out + 1] = e.type end
    return table.concat(out, ",")
end

-- Reports carry an authoritative position; "at" is a position on the gate point.
local function at(g) return { x = g.x, y = g.y, z = g.z } end

-- A position just before / just after a gate along its direction of travel.
local function before(g, m) return { x = g.x - g.dir.x * (m or 5), y = g.y - g.dir.y * (m or 5), z = g.z } end
local function after(g, m) return { x = g.x + g.dir.x * (m or 5), y = g.y + g.dir.y * (m or 5), z = g.z } end

return {
    kb23_crossings_and_green_are_dated_not_sampled = function(T)
        -- KB-23. Race times came back on round 100 ms boundaries while qualifying on the same route returned
        -- 1:04.964, so the same act -- crossing a line -- was being measured two different ways. Two causes,
        -- both of them "we recorded when we noticed, not when it happened":
        --   (a) green was stamped with the tick that observed startsAt, up to raceTickMs late;
        --   (b) a stream crossing was stamped with the arrival of the batch carrying it, one value for all five
        --       samples in it. The swept segment knows better: it says where between two samples the line was
        --       cut, and therefore when.
        local Gates = T.Core.get("course.gates")
        local Race = T.Core.get("session.race")
        local g = Gates.build({ name = "r", start = { x = 0, y = 0, z = 0, name = "s" }, finish = { x = 0, y = 1000, z = 0, name = "f" } })
        local fin = g[#g]

        local half = Gates.crossFraction(fin, { x = 0, y = 995 }, { x = 0, y = 1005 })
        T.ok(half and math.abs(half - 0.5) < 1e-9, "cut halfway between the samples")
        local late = Gates.crossFraction(fin, { x = 0, y = 999 }, { x = 0, y = 1009 })
        T.ok(late and math.abs(late - 0.1) < 1e-9, "a car already on the line crossed early in the move")
        T.eq(Gates.crossFraction(fin, { x = 0, y = 900 }, { x = 0, y = 950 }), nil, "no crossing, no fraction")
        -- and that fraction is what dates the crossing
        local a, b = { t = 100.0 }, { t = 100.2 }
        T.ok(math.abs((a.t + (b.t - a.t) * half) - 100.1) < 1e-9, "halfway through a 200 ms sample gap")

        local s2 = Race.new({ sessionId = "kb23", startsAt = 1000, gates = g,
            entrants = { { driverId = "a", slot = 1 }, { driverId = "b", slot = 2 } } })
        Race.mark(s2, "a", true); Race.mark(s2, "b", true)
        Race.step(s2, 995)
        Race.step(s2, 1000.73)          -- the tick that happens to notice, three quarters of a second late
        T.eq(s2.greenAt, 1000, "green is dated from startsAt, not from the tick that saw it")
        T.eq(s2.phase, "running")
    end,

    rolling_start_green_at_the_leader_and_formation_faults = function(T)
        -- Batch 2 rolling start: lights release the roll-out; the clock starts when the leader takes the green gate;
        -- passing before green and speeding in formation are incident bands, never restarts.
        local R = T.Core.get("session.race"); local D = T.Core.get("competition.discipline")
        local route = { name = "r", start = { x = 0, y = 0, z = 0, name = "s" }, finish = { x = 0, y = 2000, z = 0, name = "f" } }
        local course = D.buildCourse("street_sprint", route, { start = "rolling", formationM = 300 })
        T.eq(#course.gates, 3); T.eq(course.gates[2].kind, "green"); T.eq(course.gates[2].y, 300); T.eq(course.gates[3].kind, "finish"); T.eq(course.greenIndex, 2)
        local s = R.new({ sessionId = "rs", eventId = "e", startsAt = 100, gates = course.gates,
            entrants = { { driverId = "pole", slot = 1 }, { driverId = "second", slot = 2 }, { driverId = "third", slot = 3 } }, rules = { start = "rolling", gridHoldBeforeSec = 30 } })
        for _, id in ipairs({ "pole", "second", "third" }) do R.mark(s, id, true) end
        R.step(s, 70); R.step(s, 95); R.step(s, 100)
        T.eq(s.phase, "running"); T.eq(s.greenAt, 100, "the lights release the roll-out")
        local at = function(g) return { x = g.x, y = g.y } end
        for _, id in ipairs({ "pole", "second", "third" }) do R.report(s, { driverId = id, gateIndex = 1, now = 105, position = at(course.gates[1]) }) end
        -- formation: 100 km/h is over an 80 km/h cap (+10 %)
        T.eq(#R.pace(s, "third", 100 / 3.6, 110), 1, "over the pace cap: one incident")
        T.eq(#R.pace(s, "third", 100 / 3.6, 111), 0, "only once per driver")
        T.eq(#R.pace(s, "second", 85 / 3.6, 110), 0, "inside the slack")
        -- second takes the green before the pole car: green for everyone (clock starts), second gets a formation fault
        local res = R.report(s, { driverId = "second", gateIndex = 2, now = 120, position = at(course.gates[2]) })
        T.eq(res.rollingGreen.leader, "second"); T.eq(s.greenAt, 120, "race clock starts at the leader's green"); T.eq(res.formationFault, "passed_before_green"); T.eq(res.formationSec, 2)
        local res2 = R.report(s, { driverId = "pole", gateIndex = 2, now = 121, position = at(course.gates[2]) })
        T.eq(res2.rollingGreen, nil); T.eq(res2.formationFault, nil, "the pole car passed nobody")
        T.eq(#R.pace(s, "pole", 200 / 3.6, 122), 0, "after the green the cap is gone")
        R.report(s, { driverId = "second", gateIndex = 3, now = 180, position = at(course.gates[3]) })
        R.report(s, { driverId = "pole", gateIndex = 3, now = 181, position = at(course.gates[3]) })
        T.eq(s.entrants.second.totalSec, 60, "timed from the green flag, not the lights")
        T.eq(s.entrants.second.correctedSec, 62, "the formation fault sits on the corrected time")
        T.eq(s.entrants.pole.correctedSec, 61)
        local c = R.classify(s)
        T.eq(c[1].driverId, "pole", "clean pole car wins on corrected time"); T.eq(R.publicView(s).start, "rolling"); T.eq(R.publicView(s).rollingLeader, "second")
    end,
    gates_build_start_and_finish = function(T)
        local G = T.Core.get("course.gates")
        local g = course(T)
        T.eq(#g, 2); T.eq(g[1].kind, "start"); T.eq(g[2].kind, "finish")
        T.eq(g[1].name, "Tip"); T.eq(g[2].name, "Trench")
        local len = math.sqrt(g[1].dir.x ^ 2 + g[1].dir.y ^ 2); T.ok(math.abs(len - 1) < 1e-6, "unit dir")
        local g3 = course(T, { { x = -2000, y = 500, z = 10, name = "Mid" } })
        T.eq(#g3, 3); T.eq(g3[2].kind, "gate"); T.eq(g3[2].name, "Mid")
        -- lines face along the course, never the recorded node heading
        local r = route(T)
        local dx, dy = r.finish.x - r.start.x, r.finish.y - r.start.y
        local L = math.sqrt(dx * dx + dy * dy)
        T.ok(math.abs(g[1].dir.x - dx / L) < 1e-6 and math.abs(g[1].dir.y - dy / L) < 1e-6, "start faces the finish")
        T.ok(math.abs(g[2].dir.x - dx / L) < 1e-6, "finish faces along the course")
        T.eq(g[1].leaveM, 30); T.eq(g[2].leaveM, nil); T.eq(g[1].radiusM, 160)
        T.ok(G.startedFrom({ x = 0, y = 0 }, { x = 31, y = 0 }), "moved off the mark")
        T.ok(not G.startedFrom({ x = 0, y = 0 }, { x = 10, y = 10 }), "still on the mark")
    end,

    gates_capture_and_leave = function(T)
        local G = T.Core.get("course.gates")
        local g = course(T)
        local lx, ly = -g[2].dir.y, g[2].dir.x
        -- arriving at the finish node sideways (perpendicular to the line) still counts
        T.ok(G.crossed(g[2], { x = g[2].x + lx * 30, y = g[2].y + ly * 30 }, { x = g[2].x + lx * 5, y = g[2].y + ly * 5 }), "captured at the point")
        -- driving 45 m away from the start mark in ANY direction counts as leaving the grid
        T.ok(G.crossed(g[1], { x = g[1].x + lx * 20, y = g[1].y + ly * 20 }, { x = g[1].x + lx * 45, y = g[1].y + ly * 45 }), "left the grid sideways")
        T.ok(not G.crossed(g[2], { x = g[2].x + lx * 20, y = g[2].y + ly * 20 }, { x = g[2].x + lx * 45, y = g[2].y + ly * 45 }), "finish has no leave rule")
    end,

    gates_crossing_is_a_sign_flip_within_width_and_arm = function(T)
        local G = T.Core.get("course.gates")
        local g = course(T)[2]
        T.ok(G.crossed(g, before(g, 3), after(g, 3)), "straight through")
        T.ok(not G.crossed(g, after(g, 30), before(g, 30)), "wrong way (outside the capture radius)")
        T.ok(not G.crossed(g, before(g, 100), after(g, 100)), "outside the arm distance")
        local lx, ly = -g.dir.y, g.dir.x
        local wide1 = { x = g.x - g.dir.x * 3 + lx * 40, y = g.y - g.dir.y * 3 + ly * 40 }
        local wide2 = { x = g.x + g.dir.x * 3 + lx * 40, y = g.y + g.dir.y * 3 + ly * 40 }
        T.ok(not G.crossed(g, wide1, wide2), "too far laterally")
        local ok, why = G.nearGate(g, { x = g.x + 500, y = g.y }); T.eq(ok, false); T.eq(why, "too_far")
        T.ok(G.nearGate(g, { x = g.x + 90, y = g.y }), "within the host tolerance")
    end,

    grid_slots_form_behind_the_line_in_check_in_order = function(T)
        local Grid = T.Core.get("session.grid")
        local G = T.Core.get("course.gates")
        local start = course(T)[1]
        local slots = Grid.assign({
            { driverId = "late", entryId = "b", checkedInAt = 50 },
            { driverId = "early", entryId = "a", checkedInAt = 10 },
            { driverId = "third", entryId = "c", checkedInAt = 60 },
        }, start)
        T.eq(#slots, 3); T.eq(slots[1].driverId, "early"); T.eq(slots[2].driverId, "late"); T.eq(slots[3].driverId, "third")
        for _, s in ipairs(slots) do
            local along = G.signedDistance(start, s)
            T.ok(along > 0, "slot " .. s.slot .. " is on the approach side of the start line")
        end
        local d12 = T.Core.get("course.routes").planarDistance(slots[1], slots[2])
        T.ok(d12 > 5 and d12 < 6, "columns are side by side: " .. d12)
        local d13 = T.Core.get("course.routes").planarDistance(slots[1], slots[3])
        T.ok(d13 > 6.9 and d13 < 7.1, "rows are 7 m apart: " .. d13)
    end,

    full_race_two_entrants_classified = function(T)
        local Race = T.Core.get("session.race")
        local s, g = session(T)
        T.eq(s.phase, "forming")
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        T.eq(types(Race.step(s, 900)), "")
        T.eq(types(Race.step(s, 970)), "phase"); T.eq(s.phase, "gridded")
        local e = Race.step(s, 995); T.eq(types(e), "phase,light"); T.eq(s.phase, "countdown")
        T.eq(types(Race.step(s, 996)), "light"); T.eq(types(Race.step(s, 997)), "light")
        e = Race.step(s, 1000); T.match(types(e), "light,light,phase,green"); T.eq(s.phase, "running"); T.eq(s.greenAt, 1000)
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001, position = at(GATES[1]) }).ok, true)
        T.eq(Race.report(s, { driverId = "d2", gateIndex = 1, now = 1002, position = at(GATES[1]) }).ok, true)
        local r1 = Race.report(s, { driverId = "d1", gateIndex = 2, now = 1200, position = { x = g[2].x + 3, y = g[2].y } })
        T.eq(r1.ok, true); T.eq(r1.finished, true); T.eq(r1.totalSec, 200)
        T.eq(types(Race.step(s, 1201)), "phase"); T.eq(s.phase, "finishing")
        local r2 = Race.report(s, { driverId = "d2", gateIndex = 2, now = 1210, position = at(GATES[2]) })
        T.eq(r2.ok, true); T.eq(r2.totalSec, 210)
        e = Race.step(s, 1211); T.eq(types(e), "phase,complete"); T.eq(s.phase, "complete")
        local res = e[#e].results
        T.eq(res[1].driverId, "d1"); T.eq(res[1].position, 1); T.eq(res[1].gapSec, nil)
        T.eq(res[2].driverId, "d2"); T.eq(res[2].gapSec, 10); T.eq(res[2].state, "finished")
    end,

    jump_start_is_penalised = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995)
        local r = Race.report(s, { driverId = "d1", gateIndex = 1, now = 998, position = at(GATES[1]) })
        T.eq(r.ok, true); T.eq(r.penalty, true); T.eq(s.entrants.d1.jumpStart, true)
        Race.step(s, 1000)
        T.eq(Race.report(s, { driverId = "d2", gateIndex = 1, now = 1001, position = at(GATES[1]) }).ok, true)
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 2, now = 1100, position = at(GATES[2]) }).totalSec, 105, "100 s + 5 s penalty")
        T.eq(Race.report(s, { driverId = "d2", gateIndex = 2, now = 1102, position = at(GATES[2]) }).totalSec, 102)
        local e = Race.step(s, 1103)
        local res = e[#e].results
        T.eq(res[1].driverId, "d2", "the clean starter wins despite crossing later"); T.eq(res[2].jumpStart, true)
    end,

    out_of_order_and_far_reports_are_refused = function(T)
        local Race = T.Core.get("session.race")
        local s, g = session(T, { intermediate = { { x = -2000, y = 500, z = 10, name = "Mid" } } })
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 2, now = 1001, position = at(GATES[2]) }).reason, "out_of_order")
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001, position = at(GATES[1]) }).ok, true)
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 3, now = 1002, position = at(GATES[3]) }).reason, "out_of_order", "finish before the mid gate")
        local far = Race.report(s, { driverId = "d1", gateIndex = 2, now = 1003, position = { x = g[2].x + 300, y = g[2].y } })
        T.eq(far.reason, "too_far")
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 2, now = 1004, position = { x = g[2].x + 10, y = g[2].y } }).ok, true)
        T.eq(Race.report(s, { driverId = "nobody", gateIndex = 1, now = 1004, position = at(GATES[1]) }).reason, "unknown_entrant")
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 9, now = 1004, position = at(GATES[1]) }).reason, "unknown_gate")
        T.eq(s.entrants.d1.progress, 2)
    end,

    report_without_position_is_refused = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001 }).reason, "position_unknown")
    end,

    nobody_started_closes_the_session_with_dns = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        T.eq(types(Race.step(s, 1089)), "")
        local e = Race.step(s, 1090)
        T.eq(s.phase, "complete"); T.eq(e[1].reason, "nobody_started")
        local res = e[#e].results
        T.eq(res[1].state, "dns"); T.eq(res[2].state, "dns"); T.eq(res[1].dnfReason, "nobody_started")
    end,

    abort_is_dns_for_unstarted_and_dnf_for_started = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001, position = at(GATES[1]) })
        local e = Race.abort(s, 1050, "aborted")
        T.eq(s.phase, "complete"); T.eq(e[#e].reason, "aborted")
        T.eq(s.entrants.d1.state, "dnf"); T.eq(s.entrants.d2.state, "dns")
        T.eq(select(2, Race.abort(s, 1051)), "already_complete")
    end,

    start_before_gridded_does_not_count = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true)
        T.eq(Race.report(s, { driverId = "d1", gateIndex = 1, now = 900, position = at(GATES[1]) }).reason, "not_started")
    end,

    absent_at_grid_is_dns_and_the_others_race = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true)
        local e = Race.step(s, 970)
        T.eq(types(e), "dns,phase"); T.eq(e[1].driverId, "d2"); T.eq(s.entrants.d2.state, "dns")
        Race.step(s, 995); Race.step(s, 1000); T.eq(s.phase, "running")
        Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001, position = at(GATES[1]) })
        Race.report(s, { driverId = "d1", gateIndex = 2, now = 1100, position = at(GATES[2]) })
        e = Race.step(s, 1101)
        T.eq(s.phase, "complete", "one finisher and no one else running completes at once")
        local res = e[#e].results
        T.eq(res[1].driverId, "d1"); T.eq(res[2].state, "dns"); T.eq(res[2].dnfReason, "absent")
    end,

    nobody_at_grid_completes_with_no_starters = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.step(s, 970)
        local e = Race.step(s, 995)
        T.eq(s.phase, "complete"); T.eq(e[#e - 1].reason, "no_starters")
    end,

    disconnect_mid_race_is_dnf_race_continues = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001, position = at(GATES[1]) })
        Race.report(s, { driverId = "d2", gateIndex = 1, now = 1001, position = at(GATES[1]) })
        local e = Race.leave(s, "d2", 1050, "disconnected")
        T.eq(e[1].type, "dnf"); T.eq(s.entrants.d2.state, "dnf")
        T.eq(types(Race.step(s, 1051)), "", "race continues for d1")
        Race.report(s, { driverId = "d1", gateIndex = 2, now = 1200, position = at(GATES[2]) })
        e = Race.step(s, 1201)
        T.eq(s.phase, "complete")
        local res = e[#e].results
        T.eq(res[1].driverId, "d1"); T.eq(res[2].driverId, "d2"); T.eq(res[2].state, "dnf"); T.eq(res[2].dnfReason, "disconnected")
        T.eq(Race.report(s, { driverId = "d2", gateIndex = 2, now = 1300, position = at(GATES[2]) }).reason, "not_racing")
    end,

    disconnect_then_reconnect_within_grace_resumes = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001, position = at(GATES[1]) })
        Race.report(s, { driverId = "d2", gateIndex = 1, now = 1001, position = at(GATES[1]) })
        local e = Race.suspend(s, "d2", 1050, "disconnected")
        T.eq(e[1].type, "suspended"); T.eq(e[1].until_, 1230); T.eq(s.entrants.d2.state, "suspended")
        T.eq(types(Race.step(s, 1200)), "", "still within grace")
        T.eq(Race.report(s, { driverId = "d2", gateIndex = 2, now = 1085, position = at(GATES[2]) }).reason, "not_racing", "cannot report while suspended")
        e = Race.resume(s, "d2", 1090); T.eq(e[1].type, "resumed"); T.eq(e[1].progress, 1); T.eq(s.entrants.d2.state, "racing")
        Race.report(s, { driverId = "d1", gateIndex = 2, now = 1100, position = at(GATES[2]) })
        Race.step(s, 1101); T.eq(s.phase, "finishing")
        T.eq(Race.report(s, { driverId = "d2", gateIndex = 2, now = 1120, position = at(GATES[2]) }).totalSec, 120)
        e = Race.step(s, 1121); T.eq(s.phase, "complete")
        T.eq(e[#e].results[2].driverId, "d2"); T.eq(e[#e].results[2].state, "finished"); T.eq(e[#e].results[2].gapSec, 20)
    end,

    disconnect_beyond_grace_is_dnf = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        Race.mark(s, "d1", true); Race.mark(s, "d2", true)
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        Race.report(s, { driverId = "d1", gateIndex = 1, now = 1001, position = at(GATES[1]) })
        Race.suspend(s, "d2", 1050)
        T.eq(types(Race.step(s, 1229)), "", "still within the 180 s grace")
        local e = Race.step(s, 1230)
        T.eq(types(e), "dnf"); T.eq(s.entrants.d2.state, "dnf"); T.eq(s.entrants.d2.dnfReason, "disconnected")
        T.eq(select(2, Race.resume(s, "d2", 1111)), "not_suspended")
        local fresh = session(T); Race.mark(fresh, "d1", true)
        T.eq(select(2, Race.suspend(fresh, "d1", 900)), "not_racing", "cannot suspend before green")
    end,

    finish_window_classifies_stragglers_by_progress = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T, {
            intermediate = { { x = -2000, y = 500, z = 10, name = "Mid" } },
            entrants = {
                { driverId = "a", entryId = "ea", slot = 1 }, { driverId = "b", entryId = "eb", slot = 2 }, { driverId = "c", entryId = "ec", slot = 3 },
            },
        })
        for _, id in ipairs({ "a", "b", "c" }) do Race.mark(s, id, true) end
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        for _, id in ipairs({ "a", "b", "c" }) do Race.report(s, { driverId = id, gateIndex = 1, now = 1001, position = at(GATES[1]) }) end
        Race.report(s, { driverId = "a", gateIndex = 2, now = 1050, position = at(GATES[2]) })
        Race.report(s, { driverId = "b", gateIndex = 2, now = 1060, position = at(GATES[2]) })
        Race.report(s, { driverId = "a", gateIndex = 3, now = 1100, position = at(GATES[3]) })
        local e = Race.step(s, 1101); T.eq(s.phase, "finishing"); T.eq(e[1].closesAt, 1160)
        T.eq(types(Race.step(s, 1159)), "")
        e = Race.step(s, 1160); T.eq(s.phase, "complete"); T.eq(e[1].reason, "finish_window")
        local res = e[#e].results
        T.eq(res[1].driverId, "a"); T.eq(res[1].state, "finished")
        T.eq(res[2].driverId, "b"); T.eq(res[2].state, "dnf"); T.eq(res[2].progress, 2)
        T.eq(res[3].driverId, "c"); T.eq(res[3].state, "dnf"); T.eq(res[3].progress, 1)
    end,

    public_view_is_json_safe_and_ordered = function(T)
        local Race = T.Core.get("session.race")
        local s = session(T)
        local v = Race.publicView(s)
        T.eq(v.phase, "forming"); T.eq(#v.entrants, 2); T.eq(v.entrants[1].driverId, "d1"); T.eq(#v.gates, 2)
        T.eq(v.gates[2].kind, "finish"); T.ok(v.gates[1].dir.x ~= nil)
        local function jsonSafe(t, depth)
            for k, x in pairs(t) do
                T.ok(type(k) == "string" or type(k) == "number", "key type " .. type(k))
                local tx = type(x)
                T.ok(tx == "string" or tx == "number" or tx == "boolean" or tx == "table", "value type " .. tx)
                if tx == "table" and depth < 6 then jsonSafe(x, depth + 1) end
            end
        end
        jsonSafe(v, 0)
    end,

    dropoff_sits_behind_the_grid_off_the_line = function(T)
        local Grid = T.Core.get("session.grid")
        local gate = { x = 0, y = 0, z = 5, dir = { x = 0, y = 1 } }   -- course runs +Y
        local d2 = Grid.dropoffPosition(gate, 2)
        local d20 = Grid.dropoffPosition(gate, 20)
        T.ok(d2.y < -Grid.FIRST_ROW_BEHIND_M - 20, "behind the first row: " .. d2.y)
        T.ok(d20.y < d2.y - 8 * Grid.ROW_SPACING_M, "ten rows push it further back")
        T.ok(d2.x > 10, "off the line to the right of travel: " .. d2.x)
        T.eq(d2.z, 5); T.eq(math.floor(d2.heading + 0.5), 90)
        local last = Grid.slotPosition(gate, 20)
        T.ok(math.abs(last.x - d2.x) > 5, "clear of the slot columns")
    end,
}
