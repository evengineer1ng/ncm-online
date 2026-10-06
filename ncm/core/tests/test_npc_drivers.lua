-- NPC drivers across domains (L322; doc 54 §N): one identity; personality transfers, skill does not; decisions are
-- bounded by the machine's real authority.
local function get(T, n) return T.Core.get(n) end

local function person(attrs, personality)
    local a = { pace = 85, racecraft = 88, launch = 90, consistency = 85, overtaking = 80, vehicle_sympathy = 70,
        tyre_sympathy = 70, adaptability = 60, feedback = 60, aggression = 50, discipline = 50, ego = 50, mettle = 50,
        pressure_handling = 50, confidence_volatility = 50, mistake_rate = 50 }
    for k, v in pairs(attrs or {}) do a[k] = v end
    return { id = "drv", attrs = a, personality = personality or { drive = 0, temperament = 0, authority = 0, valor = 0, warmth = 0 } }
end

return {
    personality_is_the_same_driver_in_every_domain = function(T)
        local Beh, Comp = get(T, "npc.behavior"), get(T, "npc.competency")
        local p = person({ aggression = 85 })
        local before = Beh.profile(p)
        local attrsBefore = p.attrs.aggression
        Comp.enter(p, "snowglobe")
        local after = Beh.profile(p)
        T.eq(after.riskTolerance, before.riskTolerance, "entering Snowglobe does not change who they are")
        T.eq(p.attrs.aggression, attrsBefore, "and does not touch their road attributes")
    end,

    a_great_road_racer_starts_as_a_space_novice = function(T)
        local Comp = get(T, "npc.competency")
        local star = person()
        Comp.enter(star, "snowglobe")
        T.ok(Comp.level(star, "snowglobe", "attitude") < 15, "attitude control: nothing carries over")
        local weak = person({ launch = 30, racecraft = 30 })
        Comp.enter(weak, "snowglobe")
        T.ok(Comp.level(star, "snowglobe", "launch_reaction") > Comp.level(weak, "snowglobe", "launch_reaction"), "reflexes carry over a little")
        T.ok(Comp.level(star, "snowglobe", "traffic3d") < 40, "reading 3D traffic is mostly new")
        local native = person({ launch = 30 })
        Comp.enter(native, "snowglobe", { native = 50 })
        T.ok(Comp.level(native, "snowglobe", "attitude") > Comp.level(star, "snowglobe", "attitude"), "a Snowglobe native flies better")
    end,

    exposure_teaches_and_flying_it_teaches_most = function(T)
        local Comp = get(T, "npc.competency")
        local gains = {}
        for _, f in ipairs({ "physical", "tactical", "abstract" }) do
            local p = person()
            Comp.enter(p, "snowglobe")
            local g = Comp.learn(p, "snowglobe", { hours = 2, fidelity = f, discipline = "fireball", machineId = "m1" })
            gains[f] = g.attitude
            T.ok((g.sprint or 0) == 0, f .. ": racing Fireball does not teach Sprint")
            T.ok(Comp.familiarity(p, "snowglobe", "m1") > 0, f .. ": familiarity with the machine flown")
        end
        T.ok(gains.physical > gains.tactical and gains.tactical > gains.abstract, "physical > tactical > abstract")
    end,

    provocation_and_clutch = function(T)
        local Beh = get(T, "npc.behavior")
        local hot = Beh.profile(person({ confidence_volatility = 90, ego = 85 }))
        local calm = Beh.profile(person({ confidence_volatility = 15, ego = 20 }))
        local mh, mc = Beh.newMood(), Beh.newMood()
        Beh.provoke(mh, hot, "passed"); Beh.provoke(mc, calm, "passed")
        T.ok(Beh.effective(hot, mh, 0).risk - hot.riskTolerance > Beh.effective(calm, mc, 0).risk - calm.riskTolerance,
            "being passed bites a hot-head harder")
        for _ = 1, 100 do Beh.decay(mc, calm, 0.5) end
        T.ok(mc.provocation < 0.01, "a calm driver lets it go")
        local clutch = Beh.profile(person({ pressure_handling = 95, mettle = 90 }))
        local brittle = Beh.profile(person({ pressure_handling = 10, mettle = 15 }))
        T.ok(Beh.effective(clutch, nil, 1).noiseScale < 1 and Beh.effective(brittle, nil, 1).noiseScale > 1,
            "under the highest stakes the clutch driver steadies and the brittle one shakes")
    end,

    in_the_same_encounter_the_aggressive_driver_keeps_less_room = function(T)
        local Beh, Pilot, Hash = get(T, "npc.behavior"), get(T, "space.pilot"), get(T, "vocabulary.hash")
        local rules = get(T, "space.fireball").rules({ inner = 7000, outer = 11000, distanceM = 60000, centre = { 0, 0, 0 } })
        local function dodge(attrs)
            local prof = Beh.profile(person(attrs))
            local eff = Beh.effective(prof, Beh.newMood(), 0)
            local base = { t = 10, self = { pos = { 9000, 0, 0 }, vel = { 0, 160, 0 }, aMax = 15, dvLeft = 1500, heatFrac = 0.1, creditM = 100, axis = { 0, 0, 1 } },
                rules = rules, centre = { 0, 0, 0 }, g = { -3, 0, 0 }, comp = { piloting = 99, traffic3d = 99 }, eff = eff, prof = prof }
            local rival = { id = "r", pos = { 9000, 300, 15 }, vel = { 0, 100, 0 }, creditM = 400 }   -- I am closing on it
            local function plan(others) local c = {}; for k, v in pairs(base) do c[k] = v end; c.others = others; c.rng = Hash.stream("same"); return Pilot.fireball(c) end
            local a, note = plan({ rival })
            local b = plan({})
            return math.sqrt((a[1] - b[1]) ^ 2 + (a[3] - b[3]) ^ 2), note
        end
        local cautious, nc = dodge({ aggression = 10, discipline = 90 })
        local aggressive, na = dodge({ aggression = 95, discipline = 10 })
        T.ok(cautious > aggressive, ("the cautious driver swerves harder (%.2f vs %.2f m/s2)"):format(cautious, aggressive))
        T.eq(nc, "gives way", "and says so")
        T.ok(na ~= nil, "the aggressive one has its own call: " .. tostring(na))
    end,

    the_machine_bounds_the_driver = function(T)
        local Mach, F, Alloc = get(T, "engineering.machine"), get(T, "engineering.fixtures"), get(T, "engineering.allocate")
        local I = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
        local quad = Mach.assemble(F.MACHINES.corner_quad)
        local _, side = Alloc.vector(Alloc.prepare(quad), I, { 5, 0, 0 }, quad.wetMassKg, 0)
        T.eq(side, 0, "four up-thrusters cannot dodge sideways, whoever is flying")
        local orb = Mach.assemble(F.MACHINES.ls_orbiter)
        local _, side2 = Alloc.vector(Alloc.prepare(orb), I, { 5, 0, 0 }, orb.wetMassKg, 0)
        T.ok(side2 > 0, "RCS pairs can")
    end,
}
