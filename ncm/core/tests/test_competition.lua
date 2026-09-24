-- competition.discipline / format / class (Batch 1, L52–L53, P41, P44): vocabulary, adapters, grids, BoP.
local ROUTE = {
    name = "loop", distanceM = 800,
    start = { x = 0, y = 0, z = 5, name = "line" },
    finish = { x = 0, y = 400, z = 5, name = "back straight" },
}

return {
    authored_routes_register_and_carry_their_gates = function(T)
        -- Batch 2 host kit: a route captured in-world (start, gates, finish) becomes a root every discipline can run.
        local Nodes = T.Core.get("data.nodes"); local Roots = T.Core.get("data.roots"); local R = T.Core.get("course.routes"); local D = T.Core.get("competition.discipline")
        -- `custom = true`: these are runtime-registered nodes, not curated catalogue entries, and they outlive
        -- this test in the shared `data.nodes` LIST. Marking them truthfully keeps later tests able to tell the
        -- authored network apart from whatever a test left behind (test_roots asserts curated metadata).
        Nodes.register({ id = "c_ring_s", x = 0, y = 0, z = 5, heading = 0, name = "Ring start", custom = true })
        Nodes.register({ id = "c_ring_e", x = 0, y = 0, z = 5, heading = 0, name = "Ring start", custom = true })
        Roots.register({ rootId = "custom_ring", startNodeId = "c_ring_s", endNodeId = "c_ring_e", displayName = "Test Ring", custom = true,
            intermediate = { { x = 100, y = 0, z = 5, name = "T1" }, { x = 100, y = 100, z = 5, name = "T2" }, { x = 0, y = 100, z = 5, name = "T3" } }, disciplineId = "oval", laps = 2 })
        local route = R.resolve("custom_ring")
        T.eq(route.name, "Test Ring"); T.eq(#route.intermediate, 3); T.eq(route.distanceM, 400, "path length, not crow-flies"); T.eq(route.custom, true)
        local oval = D.buildCourse("oval", route, { laps = 2 })
        T.eq(oval.adapter, "laps"); T.eq(oval.laps, 2); T.eq(oval.gatesPerLap, 4); T.eq(#oval.gates, 1 + 8); T.eq(oval.gates[#oval.gates].kind, "finish")
        Nodes.register({ id = "c_p_s", x = 0, y = 0, z = 5, heading = 0 }); Nodes.register({ id = "c_p_e", x = 0, y = 500, z = 5, heading = 0 })
        Roots.register({ rootId = "custom_p2p", startNodeId = "c_p_s", endNodeId = "c_p_e", displayName = "Stage", custom = true, intermediate = { { x = 50, y = 250, z = 5, name = "mid" } } })
        local stage = D.buildCourse("rally_stage", R.resolve("custom_p2p"))
        T.eq(stage.adapter, "p2p"); T.eq(#stage.gates, 3, "start, authored gate, finish"); T.eq(stage.gates[2].name, "mid")
        T.ok(D.byId("drift").enabled and D.byId("quad").enabled and D.byId("rally_stage").enabled, "TW1 disciplines are enabled")
        T.eq(Roots.unregister("custom_p2p"), true); T.eq(R.resolve("custom_p2p"), nil)
        Roots.unregister("custom_ring")
    end,
    discipline_ids_and_incident_rules = function(T)
        local D = T.Core.get("competition.discipline")
        T.ok(D.byId("oval") and D.byId("drag") and D.byId("ncx_formula"), "core disciplines exist")
        T.eq(D.byId("nope"), nil)
        T.ok(#D.ids(true) >= 5 and #D.ids(false) > #D.ids(true), "disabled disciplines are declared but not enabled")
        local r = D.incidentRules("ncx_formula")
        T.eq(r.bands[1].dv, 1.5); T.eq(r.bands[3].mult, 4); T.eq(r.contactM, 4.0)
        T.eq(next(D.incidentRules("knockout")), nil, "no bands -> no overrides")
    end,

    oval_flattens_laps_into_one_gate_list = function(T)
        local D = T.Core.get("competition.discipline")
        local c = D.ovalCourse(ROUTE, { laps = 3 })
        T.eq(c.adapter, "laps"); T.eq(c.laps, 3); T.eq(c.gatesPerLap, 2)
        T.eq(#c.gates, 1 + 3 * 2, "start + laps x (back straight + line)")
        T.eq(c.gates[1].kind, "start"); T.eq(c.gates[#c.gates].kind, "finish")
        for i = 2, #c.gates - 1 do T.eq(c.gates[i].kind, "gate", "interior gate " .. i) end
        T.eq(c.lapOf(2), 1); T.eq(c.lapOf(3), 1); T.eq(c.lapOf(4), 2); T.eq(c.lapOf(7), 3)
        T.ok(c.gates[3].x == 0 and c.gates[3].y == 0, "the lap line is back at the start")
        T.eq(c.gates[3].leaveM, nil, "only the true start carries the leave rule")
        T.ok(math.abs(c.lengthM - 3 * 800) < 1, "length is laps x ring: " .. c.lengthM)
        local race = T.Core.get("session.race")
        local s = race.new({ sessionId = "o", startsAt = 100, gates = c.gates, entrants = { { driverId = "d1", slot = 1 } } })
        T.eq(#s.gates, 7, "the race kernel runs the flat list unchanged")
    end,

    drag_lanes_straightness_and_deviation = function(T)
        local D = T.Core.get("competition.discipline")
        T.ok(D.straightness({ { x = 0, y = 0 }, { x = 0, y = 100 }, { x = 0, y = 200 } }) == 1.0, "straight line ratio 1")
        T.ok(D.straightness({ { x = 0, y = 0 }, { x = 100, y = 100 }, { x = 0, y = 200 } }) > D.MAX_STRAIGHTNESS_RATIO, "a dog-leg is not a strip")
        local c = D.dragCourse({ name = "strip", start = { x = 0, y = 0, z = 0 }, finish = { x = 0, y = 400, z = 0 } }, { lanes = 4, laneWidthM = 4 })
        T.eq(c.adapter, "lanes"); T.eq(#c.gates, 2); T.eq(#c.lanes, 4); T.eq(c.lanes[1].role, "fast_traffic"); T.eq(c.lanes[4].role, "fast_oncoming")
        T.ok(c.lanes[1].offsetM > c.lanes[4].offsetM, "lane 1 is rightmost (negative lateral = right of travel)")
        local a = D.laneAssignment({ "p1", "p2", "p3", "p4", "p5" })
        T.eq(a.p1, 1); T.eq(a.p2, 2); T.eq(a.p3, 3); T.eq(a.p4, 4); T.eq(a.p5, 1, "wraps for bigger fields")
        local onLine = {}
        for i = 0, 10 do onLine[#onLine + 1] = { x = -c.lanes[1].offsetM * 0 + (c.lanes[1].offsetM) * -1, y = i * 40 } end
        -- lane 1 offset is negative-left => positive x is right of travel (+Y course): x = -offset places the car on lane 1
        local dev = D.laneDeviation(c, 1, onLine)
        T.eq(dev.penaltySec, 0, "on the lane line: no penalty")
        local weave = {}
        for i = 0, 10 do weave[#weave + 1] = { x = -c.lanes[1].offsetM + ((i % 2 == 0) and 6 or -6), y = i * 40 } end
        local dev2 = D.laneDeviation(c, 1, weave)
        T.ok(dev2.penaltySec > 0 and dev2.maxM > 5, "weaving costs time: " .. dev2.penaltySec)
    end,

    format_plans_and_grids = function(T)
        local F = T.Core.get("competition.format")
        T.eq(#F.plan("sprint"), 1); T.eq(#F.plan("weekend"), 2, "practice is on demand, not a plan session (P48)"); T.eq(#F.plan("two_race"), 2); T.eq(#F.plan("tworace"), 2, "alias")
        local w = F.plan("weekend")
        T.eq(w[1].kind, "quali"); T.eq(w[1].maxRuns, 1); T.eq(w[2].gridFrom, "quali"); T.eq(w[2].of, 2)
        T.eq(F.gapFor(0, 90), 90, "gap floor"); T.eq(F.gapFor(550, 90), 120, "Troll Pass finish -> grid: 37 s + 60 s -> 2 min"); T.eq(F.gapFor(6800, 90), 540, "6.8 km: 453 s + 60 s -> 9 min")
        local grid = F.gridFor(w[2], { kind = "quali", results = {
            { driverId = "slow", position = 3, bestSec = 90 }, { driverId = "fast", position = 1, bestSec = 80 }, { driverId = "none", position = 2, bestSec = nil } } })
        T.eq(grid[1], "fast"); T.eq(grid[2], "slow"); T.eq(grid[3], "none", "no time starts last")
        local tr = F.plan("two_race")
        local rev = F.gridFor(tr[2], { kind = "race", results = {
            { driverId = "a", position = 1, state = "finished" }, { driverId = "b", position = 2, state = "finished" },
            { driverId = "c", position = 3, state = "finished" }, { driverId = "d", position = 4, state = "dnf" } } })
        T.eq(rev[1], "c"); T.eq(rev[2], "b"); T.eq(rev[3], "a"); T.eq(rev[4], "d", "n > field: whole finished field reversed, DNF at the back")
        T.eq(F.gridFor(tr[1], nil), nil, "no prior -> host default")
    end,

    pool_record_lookup_is_a_catalogue_not_a_parsed_id = function(T)
        -- IDEA-113/115: ownership and eligibility both need "what is this car?" and neither may answer it by
        -- picking the maker out of a TweakDB id string. The pool is the catalogue; this is how it is asked.
        local P = T.Core.get("data.vehicle_pool")
        local mai = P.byRecord("Vehicle.v_standard2_makigai_maimai")
        T.ok(mai ~= nil, "the MaiMai is in the pool")
        T.eq(#mai.classes, 1); T.eq(mai.classes[1], "Tech"); T.eq(mai.prestige, 1)
        T.eq(P.inClass("Vehicle.v_standard2_makigai_maimai", "Tech"), true)
        T.eq(P.inClass("Vehicle.v_standard2_makigai_maimai", "Sport"), false)

        -- A record may belong to several classes on purpose. The Colby pickup is Muscle AND Nomad, with
        -- different tags in each; a lookup that returned one class would silently make it Nomad-only and a
        -- Muscle championship would reject it for no visible reason.
        local pickup = P.byRecord("Vehicle.v_standard25_thorton_colby_pickup")
        T.eq(#pickup.classes, 2, "the pickup is in two classes")
        T.eq(pickup.classes[1], "Muscle"); T.eq(pickup.classes[2], "Nomad")
        T.eq(P.inClass("Vehicle.v_standard25_thorton_colby_pickup", "Muscle"), true)
        T.eq(P.inClass("Vehicle.v_standard25_thorton_colby_pickup", "Nomad"), true)
        local tags = {}
        for _, x in ipairs(pickup.tags) do tags[x] = true end
        T.ok(tags.utility and tags.offroad, "tags are the union across its classes, not one class's set")
        T.eq(P.byRecord("Vehicle.not_a_real_car"), nil, "an unknown record is unknown, not guessed")
        T.eq(P.byRecord(nil), nil); T.eq(P.byRecord(42), nil)

        local all = P.allRecords()
        T.ok(#all >= 20, "the pool is present")
        local seen = {}
        for _, r in ipairs(all) do
            T.eq(seen[r.id], nil, "allRecords lists each record once, however many classes it is in: " .. r.id)
            seen[r.id] = true
            T.ok(#r.classes >= 1, "every record belongs to at least one class: " .. r.id)
            for _, c in ipairs(r.classes) do
                T.ok(P.isClass(c), "every membership is a real class: " .. c)
                T.eq(P.inClass(r.id, c), true, "inClass agrees with the record's own list: " .. r.id)
            end
        end
        -- every class's records must all be findable, or the two views have drifted apart
        for _, c in ipairs(P.classes()) do
            for _, r in ipairs(P.records(c)) do
                T.ok(seen[r.id], "a class record is in allRecords: " .. r.id)
                T.eq(P.inClass(r.id, c), true, "and knows it is in " .. c)
            end
        end
    end,

    class_performance_and_eligibility = function(T)
        local K = T.Core.get("competition.class")
        T.eq(K.performance("street_open"), nil, "open class has no ceiling")
        local p = K.performance("ncx_rb15")
        -- KB-30 / L77: measured live 2026-09-22, the RB15 collapses at ~360 km/h. 355 is the owner's ceiling and
        -- the upper bound they accepted; if this number ever rises above 355 the car meets the cliff again.
        T.eq(p.topSpeedKph, 355); T.eq(p.accelerationScale, 1.0); T.eq(p.taperKph, 20)
        T.ok(p.topSpeedKph <= 355, "L77: the Formula ceiling never goes above 355")
        T.eq(K.eligible("ncx_rb15", "Vehicle.v_sport1_rb15_f1_kimiko"), true)
        T.eq(K.eligible("ncx_rb15", "Vehicle.v_standard3_chevalier_emperor"), false)
        T.eq(K.eligible("street_open", "Vehicle.anything"), true)
        T.ok(#K.vehicleRows() >= 11, "rows for persistence include the RB15 family")
    end,

    class_ceilings_are_published_per_record = function(T)
        -- D7: the ceiling was data with no caller for months -- `performance()` was right and nothing asked it.
        -- The host applies the governor per vehicle RECORD, so this is the shape it actually needs.
        local K = T.Core.get("competition.class")
        local c = K.recordCeilings()
        T.ok(c["Vehicle.v_sport1_rb15_f1"] ~= nil, "the base RB15 record is capped")
        T.eq(c["Vehicle.v_sport1_rb15_f1"].topSpeedKph, 355)
        T.ok(c["Vehicle.v_sport1_rb15_f1_kimiko"] ~= nil, "and every livery, or a liveried car outruns the field")
        T.eq(c["Vehicle.anything"], nil, "an open class caps nothing: it has no ceiling and no record list")
        local n = 0
        for _ in pairs(c) do n = n + 1 end
        T.ok(n >= 11, "the whole RB15 family is covered, not just the base record")
        for record, prof in pairs(c) do
            T.ok(prof.topSpeedKph > 0, "a published ceiling is always a real cap: " .. record)
            T.ok(prof.accelerationScale <= 1.0, "the governor only ever scales throttle down, never up")
        end
    end,

    calendar_carries_the_vocabulary = function(T)
        local Cal = T.Core.get("competition.calendar")
        local series = { seriesId = "s", name = "S", rulesetId = "r", cadence = { everyMinutes = 20 }, routes = { "root_tip_1035_3652__to__trench_2899_2711" },
                         entryWindow = { opensMinutes = 15, closesMinutes = 1 } }
        local ev = Cal.materialize(series, 0, 3600)[1]
        T.eq(ev.disciplineId, "street_sprint"); T.eq(ev.formatId, "sprint"); T.eq(ev.classId, "street_open"); T.eq(ev.laps, 1)
        series.disciplineId, series.formatId, series.classId, series.laps = "oval", "two_race", "street_sport", 5
        local ev2 = Cal.materialize(series, 0, 3600)[1]
        T.eq(ev2.disciplineId, "oval"); T.eq(ev2.laps, 5)
    end,
}
