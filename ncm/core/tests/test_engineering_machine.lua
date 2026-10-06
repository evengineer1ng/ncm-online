-- Engineering II (L321; doc 54 §C, §D): a machine is assembled from physical systems, and what it can do follows from
-- them -- mass, centre of mass, where force acts, what it stores and burns, what heat it makes. The hop is not a
-- thruster: ground reaction needs contact and stored energy; air pushes need air; reaction engines need propellant.
local function near(T, a, b, tol, msg)
    T.ok(math.abs(a - b) <= tol, ("%s (got %.6g, want %.6g +- %.3g)"):format(msg, a, b, tol))
end

local function mods(T)
    return T.Core.get("engineering.machine"), T.Core.get("engineering.dynamics"), T.Core.get("engineering.fixtures"),
        T.Core.get("engineering.systems")
end

-- one main engine and one tank on a light frame, mounted at `x` across from the chassis centre
local function rocket(F, x)
    return {
        chassis = { massKg = 1000, com = { 0, 0, 0.5 }, bounds = { 1.8, 4.0, 1.2 } },
        parts = {
            { key = "main", body = F.DESIGNS.main_hydrazine_30k, pos = { x or 0, 0, 0.5 }, dir = { 0, 0, 1 } },
            { key = "tank", body = F.DESIGNS.tank_hydrazine_400, pos = { 0, 0, 0.5 } },
        },
    }
end

local VACUUM = { g = { 0, 0, 0 }, rho = 0 }

local function count(events, what)
    local n = 0
    for _, e in ipairs(events) do if e.what == what then n = n + 1 end end
    return n
end

return {
    assembly_gives_mass_centre_of_mass_and_the_wrench = function(T)
        local Mach, _, F = mods(T)
        local m = Mach.assemble(F.MACHINES.ram_hopper)
        -- chassis 1500 kg at z 0.5, ram 45 kg at z 0, battery 120 kg at z 0.5
        near(T, m.wetMassKg, 1665, 1e-9, "mass is the sum of the bodies")
        near(T, m.com[3], (1500 * 0.5 + 120 * 0.5) / 1665, 1e-9, "centre of mass is the mass-weighted mean")
        local off = Mach.assemble(rocket(F, 1.0))
        local w = off.wrench[1]
        local r = off.com
        near(T, w.tau[2], -(1.0 - r[1]) * 30000, 1e-6, "an up-thruster right of the CoM makes a roll torque (r x F)")
        near(T, w.tau[1], 0, 1e-9, "and no pitch")
        local centred = Mach.assemble(rocket(F, 0))
        near(T, centred.wrench[1].tau[2], 0, 1e-9, "the same engine under the CoM makes no torque")
    end,

    four_badly_placed_thrusters_are_not_six_axis_control = function(T)
        local Mach, _, F = mods(T)
        local orbiter = Mach.assemble(F.MACHINES.ls_orbiter)
        T.eq(Mach.authority(orbiter, { reaction = true }).controlledAxes, 6, "opposed RCS pairs at the extremities: six axes")
        local main = orbiter.wrench[1]
        T.ok(math.abs(main.tau[1]) < 1 and math.abs(main.tau[2]) < 1, "the orbiter's main engine sits under its CoM: lift does not spin it")
        local quad = Mach.assemble(F.MACHINES.corner_quad)
        local a = Mach.authority(quad, { reaction = true })
        T.eq(a.controlledAxes, 2, "four up-thrusters at the corners: pitch and roll only")
        local cap = Mach.capability(quad)
        T.eq(cap.firstFailure, "structure", "180 kN on a 150 kN chassis: the structure fails before anything else")
        T.ok(cap.twrVacuum > 5, "even though it has enormous thrust-to-weight")
    end,

    the_hop_is_ground_reaction_and_air_presses_do_nothing = function(T)
        local Mach, Dyn, F = mods(T)
        local m = Mach.assemble(F.MACHINES.ram_hopper)
        local cap = Mach.capability(m, { g = 9.81 })
        T.eq(cap.twrVacuum, 0, "a ram is not a thruster")
        T.falsy(cap.vacuumManeuver, "and cannot maneuver in vacuum")
        local s = Dyn.init(m)
        local env = { g = { 0, 0, -9.81 }, rho = 1.225, groundZ = 0 }
        local _, tel = Dyn.step(m, s, env, { fire = true }, 0.001)
        T.eq(count(tel.events, "fired"), 1, "on the ground with a charged ram: it fires")
        local peak, airPresses, airFired = 0, 0, 0
        for i = 1, 3000 do
            local press = (i % 50 == 0) and s.pos[3] > 0.3       -- mash the button in the air
            local _, t2 = Dyn.step(m, s, env, { fire = press }, 0.001)
            if press then airPresses = airPresses + 1 end
            airFired = airFired + count(t2.events, "fired")
            if s.pos[3] > peak then peak = s.pos[3] end
        end
        T.ok(airPresses >= 10, "the button was pressed in the air")
        T.eq(airFired, 0, "and nothing fired: there is nothing to push against")
        near(T, peak, cap.hopHeightM, 0.02, "the hop height is the stored energy over the weight")
    end,

    rocket_delta_v_is_the_rocket_equation_and_an_empty_tank_stops = function(T)
        local Mach, Dyn, F, Sys = mods(T)
        local m = Mach.assemble(rocket(F, 0))
        local cap = Mach.capability(m)
        local want = 230 * Sys.G0 * math.log(m.wetMassKg / m.dryMassKg)
        near(T, cap.deltaVms, want, 1e-6, "capability uses Tsiolkovsky")
        local s = Dyn.init(m)
        local starved = 0
        for _ = 1, math.ceil(cap.burnTimeS / 0.01) + 200 do
            local _, tel = Dyn.step(m, s, VACUUM, { throttle = 1 }, 0.01)
            starved = starved + count(tel.events, "starved")
        end
        near(T, s.vel[3], want, want * 0.005, "integrating a full burn gives the same delta-v")
        near(T, Dyn.propellantLeft(m, s), 0, 1e-6, "the tank is empty")
        T.ok(starved > 0, "the engine reports starvation")
        local v = s.vel[3]
        local _, tel = Dyn.step(m, s, VACUUM, { throttle = 1 }, 0.1)
        T.eq(tel.thrustN, 0, "an empty tank gives no thrust")
        near(T, s.vel[3], v, 1e-9, "and no more speed")
    end,

    a_propeller_needs_air = function(T)
        local Mach, Dyn, F = mods(T)
        local U = T.Core.get("space.universe")
        U.setWorld({ earthRadius = 5000, surfaceG = 9.81 })
        local m = Mach.assemble(F.MACHINES.fan_car)
        T.ok(Mach.capability(m).atmosphericFlight, "two lift fans fly a light car at sea level")
        local function thrustAt(h)
            local s = Dyn.init(m)
            local _, tel = Dyn.step(m, s, { g = { 0, 0, 0 }, rho = U.densityAt(h) }, { throttle = 1 }, 0.01)
            return tel.thrustN
        end
        local sea, high, space = thrustAt(0), thrustAt(4000), thrustAt(100000)
        U.setWorld({})
        near(T, sea, 24000, 1e-6, "full thrust in sea-level air")
        T.ok(high < 0.05 * sea, "almost nothing four scale heights up")
        T.eq(space, 0, "nothing at all in vacuum")
    end,

    off_centre_thrust_spins_the_machine = function(T)
        local Mach, Dyn, F = mods(T)
        local off = Mach.assemble(rocket(F, 1.0))
        local s = Dyn.init(off)
        for _ = 1, 100 do Dyn.step(off, s, VACUUM, { throttle = 1 }, 0.01) end
        T.ok(s.omega[2] < -0.1, "an engine right of the CoM rolls it")
        T.ok(s.rot[3][3] < 0.999, "and the machine has turned")
        local mid = Mach.assemble(rocket(F, 0))
        local s2 = Dyn.init(mid)
        for _ = 1, 100 do Dyn.step(mid, s2, VACUUM, { throttle = 1 }, 0.01) end
        near(T, s2.omega[2], 0, 1e-9, "the same engine under the CoM does not")
    end,

    heat_accumulates_and_derates = function(T)
        local Mach, Dyn, F = mods(T)
        local m = Mach.assemble(rocket(F, 0))
        local s = Dyn.init(m)
        Dyn.step(m, s, VACUUM, { throttle = 1 }, 1.0)
        near(T, s.heatK, 600 / (m.dryMassKg * Mach.CP / 1000), 1e-6, "600 kW for 1 s into the machine's heat capacity")
        s.heatK = Mach.TEMP_LIMIT_K - 10
        local _, hot = Dyn.step(m, s, VACUUM, { throttle = 1 }, 0.001)
        near(T, hot.derate, 10 / (0.2 * Mach.TEMP_LIMIT_K), 1e-3, "hot: output derated toward the limit")
        T.ok(hot.thrustN < 30000 * 0.5, "and the thrust shows it")
        s.heatK = Mach.TEMP_LIMIT_K
        local _, cooked = Dyn.step(m, s, VACUUM, { throttle = 1 }, 0.001)
        T.eq(cooked.thrustN, 0, "at the limit: nothing")
    end,

    hosts_express_the_truth_and_list_what_they_cannot = function(T)
        local H = T.Core.get("engineering.hosts")
        local truth = { massKg = 2000, forceN = { 500, 0, 80000 }, torqueNm = { 0, 1200, 0 }, velMs = { 0, 180, 0 }, localZ = 20000 }
        local red = H.express("redengine", truth)
        T.eq(red.commands.liftTwr, 3, "the lift lever carries what it can (4.1 asked, 3 given)")
        local q = {}
        for _, l in ipairs(red.losses) do q[l.quantity] = l end
        T.truthy(q.torque and q["lateral force"] and q.speed and q.position and q.lift, "and lists every quantity it cannot carry")
        local rage = H.express("rage", truth)
        T.ok(math.abs(rage.commands.couples[2].forceN * 2 * 1.6 - 1200) < 1e-9, "RAGE carries torque as a couple")
        local speedLoss
        for _, l in ipairs(rage.losses) do if l.quantity == "speed" then speedLoss = l end end
        T.eq(speedLoss.truth, 180, "the truth is kept in the loss")
        T.eq(speedLoss.expressed, 140, "beside what was presented")
        T.eq(truth.velMs[2], 180, "and the machine's own velocity is never touched")
        T.eq(H.HOSTS.rage.limits.worldZ.value, nil, "an unmeasured limit stays unknown")
    end,
}
