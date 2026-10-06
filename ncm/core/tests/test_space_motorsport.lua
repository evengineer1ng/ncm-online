-- Snowglobe motorsport (L321; doc 54 §G): 3D gates, seeded courses and worlds, NPC races through paddock.sim and
-- paddock.racestate with the machine's physics as the car term, provenance, and sport that forms from what exists.
local function get(T, n) return T.Core.get(n) end

local function withWorld(T, fn)
    local U = get(T, "space.universe")
    U.setWorld({ earthRadius = 5000, surfaceG = 9.81 })
    local ok, err = pcall(fn)
    U.setWorld({})
    if not ok then error(err, 0) end
end

local function fixtureMachines(T, names)
    local Mach, F = get(T, "engineering.machine"), get(T, "engineering.fixtures")
    local out = {}
    for i, n in ipairs(names) do
        out[i] = { id = n .. "#" .. i, orgId = "org" .. i, model = Mach.assemble(F.MACHINES[n]),
                   pilot = { attrs = {} } }
    end
    return out
end

return {
    a_gate_is_passed_through_its_face_within_its_radius = function(T)
        local Course = get(T, "space.course")
        local g = Course.gate("G1", { 0, 0, 100 }, { 0, 1, 0 }, 20)
        T.truthy(Course.crossed(g, { 5, -10, 105 }, { 5, 10, 105 }), "through the middle, the right way")
        T.falsy(Course.crossed(g, { 5, 10, 105 }, { 5, -10, 105 }), "the wrong way is not a pass")
        local ok, f, miss = Course.crossed(g, { 30, -10, 100 }, { 30, 10, 100 })
        T.falsy(ok, "30 m off a 20 m gate misses")
        T.ok(f and math.abs(miss - 30) < 1e-9, "and says by how much")
        T.falsy(Course.crossed(g, { 0, 1, 100 }, { 0, 5, 100 }), "already past the plane: nothing")
    end,

    a_seeded_ring_is_stable_and_can_be_flown_and_timed = function(T)
        local Seed, Course = get(T, "world.seed"), get(T, "space.course")
        withWorld(T, function()
            local node = Seed.root("ring-test"):child("snowglobe", "station", 1, "ring")
            local a = Course.ring(node)
            local _ = Seed.root("ring-test"):child("snowglobe", "station", 2, "ring"):stream()()
            local b = Course.ring(node)
            T.eq(#a.gates, #b.gates, "same node, same ring")
            T.eq(a.gates[3].centre[3], b.gates[3].centre[3], "gate for gate")
            T.ok(a.lengthM > 1000, "a real course")
            local frame = Course.anchorFrame("los_santos", 1500)
            local world = Course.place(a, frame)
            local back = Course.toLocal(frame, world[1].centre)
            T.ok(math.abs(back[3] - a.gates[1].centre[3]) < 1e-6 and math.abs(back[1] - a.gates[1].centre[1]) < 1e-6,
                "placed over Los Santos at 1,500 m, and back")
            -- fly gate centre to gate centre, `laps` times, and back through gate 1
            local timer = Course.timer(world, a.laps)
            local n = #world
            local t, prev = 0, nil
            local function fly(to)
                if prev then
                    local steps = 20
                    for k = 1, steps do
                        local p0 = { prev[1] + (to[1] - prev[1]) * (k - 1) / steps, prev[2] + (to[2] - prev[2]) * (k - 1) / steps, prev[3] + (to[3] - prev[3]) * (k - 1) / steps }
                        local p1 = { prev[1] + (to[1] - prev[1]) * k / steps, prev[2] + (to[2] - prev[2]) * k / steps, prev[3] + (to[3] - prev[3]) * k / steps }
                        timer:update(p0, p1, t, t + 0.5)
                        t = t + 0.5
                    end
                end
                prev = to
            end
            -- approach gate 1 from behind its plane
            local g1 = world[1]
            prev = { g1.centre[1] - g1.normal[1] * 50, g1.centre[2] - g1.normal[2] * 50, g1.centre[3] - g1.normal[3] * 50 }
            for _ = 1, a.laps do
                for i = 1, n do
                    local g = world[i]
                    fly({ g.centre[1] - g.normal[1] * 5, g.centre[2] - g.normal[2] * 5, g.centre[3] - g.normal[3] * 5 })
                    fly({ g.centre[1] + g.normal[1] * 5, g.centre[2] + g.normal[2] * 5, g.centre[3] + g.normal[3] * 5 })
                end
            end
            fly({ g1.centre[1] - g1.normal[1] * 5, g1.centre[2] - g1.normal[2] * 5, g1.centre[3] - g1.normal[3] * 5 })
            fly({ g1.centre[1] + g1.normal[1] * 5, g1.centre[2] + g1.normal[2] * 5, g1.centre[3] + g1.normal[3] * 5 })
            T.truthy(timer.finished, "the ring is finished after its laps")
            T.eq(#timer.splits, a.laps * n, "every gate of every lap has a split")
            T.eq(timer.misses, 0, "and nothing was missed")
        end)
    end,

    snowglobe_genesis_is_the_seed_and_only_the_seed = function(T)
        local Seed, Gen = get(T, "world.seed"), get(T, "space.genesis")
        withWorld(T, function()
            local a = Gen.generate(Seed.root(77):child("snowglobe"))
            local b = Gen.generate(Seed.root(77):child("snowglobe"))
            local c = Gen.generate(Seed.root(78):child("snowglobe"))
            T.ok(#a.stations >= 1 and #a.orgs >= 8, "stations and a field of organisations exist before any player")
            T.eq(a.stations[1].orbit.radiusM, b.stations[1].orbit.radiusM, "same seed, same orbit")
            T.eq(a.orgs[3].name, b.orgs[3].name, "same organisations")
            T.eq(a.machines[2].id, b.machines[2].id, "same machines")
            T.eq(#a.lineage.order, #b.lineage.order, "same technology history")
            T.ok(a.stations[1].orbit.radiusM ~= c.stations[1].orbit.radiusM, "another seed is another world")
            local pos, _, period = Gen.orbitAt(a.stations[1].orbit, 0)
            local U = get(T, "space.universe")
            T.ok(math.abs(U.altitude(pos) - a.stations[1].altitudeM) < 1e-6, "the station is on its orbit")
            T.ok(period > 60 and period < 2000, "a compressed-Earth orbit takes minutes")
            local p1 = Gen.anomalyAt(a.anomaly, 100)
            local p2 = Gen.anomalyAt(b.anomaly, 100)
            T.eq(p1[1], p2[1], "the anomaly's motion is deterministic")
        end)
    end,

    machine_physics_decides_who_can_race_and_how_fast = function(T)
        local Race, Seed, Course = get(T, "space.racesim"), get(T, "world.seed"), get(T, "space.course")
        withWorld(T, function()
            local venue = { id = "ring", kind = "station_ring", course = Course.ring(Seed.root(5):child("ring"), { laps = 2 }) }
            local ms = fixtureMachines(T, { "ls_orbiter", "ram_hopper", "corner_quad", "fan_car" })
            local est = {}
            for i, m in ipairs(ms) do est[i] = Race.estimate(m.model, venue) end
            T.truthy(est[1].eligible, "the orbiter flies the station ring")
            T.falsy(est[2].eligible, "the hopper cannot")
            T.match(est[2].reason, "no reaction push", "because a ram pushes on ground, not vacuum")
            T.falsy(est[3].eligible, "the corner quad cannot")
            T.match(est[3].reason, "attitude", "two axes are not control")
            T.falsy(est[4].eligible, "a fan car cannot fly in vacuum")
            local sky = { id = "sky", kind = "sky_ring", altitudeM = 300, course = Course.ring(Seed.root(5):child("sky"), { laps = 1 }) }
            T.truthy(Race.estimate(ms[4].model, sky).eligible, "but it can fly the low sky ring")
            local high = { id = "sky2", kind = "sky_ring", altitudeM = 6000, course = sky.course }
            T.match(Race.estimate(ms[4].model, high).reason or "", "cannot hold altitude", "and not one in thin air")
        end)
    end,

    a_station_race_is_a_paddock_race_with_provenance = function(T)
        local Race, Seed, Course, Hash = get(T, "space.racesim"), get(T, "world.seed"), get(T, "space.course"), get(T, "vocabulary.hash")
        local RS = get(T, "paddock.racestate")
        withWorld(T, function()
            local venue = { id = "ring", kind = "station_ring", course = Course.ring(Seed.root(9):child("ring"), { laps = 2 }) }
            local ms = fixtureMachines(T, { "ls_orbiter", "ls_orbiter", "ls_orbiter", "ram_hopper" })
            local r1 = Race.race(venue, ms, Hash.stream("race", 1))
            local r2 = Race.race(venue, ms, Hash.stream("race", 1))
            T.eq(#r1.field, 3, "three can fly it")
            T.eq(#r1.refused, 1, "one is refused, with a reason")
            T.eq(table.concat(r1.sim.order, ","), table.concat(r2.sim.order, ","), "the same seed replays the same race")
            local rows = Race.result(r1)
            T.eq(#rows, 3, "a classification")
            for _, row in ipairs(rows) do T.eq(row.mode, "simulated", "nobody watched: simulated, and it says so") end
            local first = r1.sim.order[1]
            RS.markPhysical(r1.model, first, 0, venue.course.lengthM, 0, 1)
            local rows2 = Race.result(r1)
            local mode
            for _, row in ipairs(rows2) do if row.id == first then mode = row.mode end end
            T.eq(mode, "physical", "a car flown the whole way physically is physical")
            local p = Race.pointAt(venue.course, venue.course.lapM * 1.0)
            local g1 = venue.course.gates[1].centre
            T.ok(math.abs(p[1] - g1[1]) < 1e-6 and math.abs(p[3] - g1[3]) < 1e-6, "a lap brings a car back to gate 1")
        end)
    end,

    car_perf_reproduces_the_physical_pace_ratio = function(T)
        local Race, Sim = get(T, "space.racesim"), get(T, "paddock.sim")
        local perfFast = Sim.performance({}, Race.carPerf(90, 100))
        local perfMed = Sim.performance({}, Race.carPerf(100, 100))
        local mult = function(p) return 1 - (p - 50) / 50 * Sim.PACE_SPREAD end
        T.ok(math.abs(mult(perfFast) / mult(perfMed) - (1 - Sim.CAR_WEIGHT * (100 / 90 - 1) * Sim.PACE_SPREAD * 50 / Sim.PACE_SPREAD / Sim.CAR_WEIGHT / 50)) < 1e-9,
            "a machine 1/0.9 quicker gets exactly that much sim pace")
    end,

    sport_forms_from_the_capability_distribution = function(T)
        local Sport, Seed, Course, Gen = get(T, "space.sport"), get(T, "world.seed"), get(T, "space.course"), get(T, "space.genesis")
        withWorld(T, function()
            local venue = { id = "ring", kind = "station_ring", course = Course.ring(Seed.root(3):child("ring"), { laps = 2 }) }
            local few = fixtureMachines(T, { "ls_orbiter", "ram_hopper", "fan_car" })
            T.eq(Sport.formEvents({ venue }, few)[1].status, "none", "one machine that can fly it: no race")
            local some = fixtureMachines(T, { "ls_orbiter", "ls_orbiter", "ram_hopper" })
            T.eq(Sport.formEvents({ venue }, some)[1].status, "exhibition", "two: an exhibition")
            local many = fixtureMachines(T, { "ls_orbiter", "ls_orbiter", "ls_orbiter", "ls_orbiter", "ls_orbiter", "ls_orbiter" })
            local ev = Sport.formEvents({ venue }, many)[1]
            T.eq(ev.status, "class", "six: a class, with a regulation envelope")
            T.eq(ev.envelope.metric, "deltaVms", "set in delta-v for vacuum racing")
            -- across generated worlds, history decides: not every seed has the same sport
            local Mach = get(T, "engineering.machine")
            local seen = {}
            for seed = 1, 12 do
                local w = Gen.generate(Seed.root(seed):child("snowglobe"))
                local machines = {}
                for i, m in ipairs(w.machines) do machines[i] = { id = m.id, model = Mach.assemble(m) } end
                for _, e in ipairs(Sport.formEvents(w.venues, machines)) do
                    if e.kind == "station_ring" then seen[e.status] = true end
                end
                local evid = Sport.weekEvidence(w, Sport.formEvents(w.venues, machines), {})
                T.eq(evid.domain, "snowglobe", "Snowglobe evidence")
                T.eq(evid.visibility, "hidden", "is never shown to players")
            end
            local kinds = 0
            for _ in pairs(seen) do kinds = kinds + 1 end
            T.ok(kinds >= 2, "different seeds' histories give different station sport")
        end)
    end,
}
