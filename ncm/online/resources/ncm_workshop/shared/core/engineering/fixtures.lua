-- ncm-core module: engineering.fixtures
--
-- ILLUSTRATIVE sites and designs for the Engineering Architecture pass (doc 50 §10; L314). Every site here is
-- `provenance = "fixture"`: its zones are a plausible plan view drawn to exercise the grammar, NOT a survey of
-- the real car. The stock masses are real (the drive-model records' `total_mass`, 2026-09-26 architecture dump,
-- which the live body reads at `+0x1BC`). The five gearboxes are the owner's own numbers (doc 48 §0): street
-- 82 kg, competition 65, advanced race 42, the ghost range box 14, Kimiko Mk I 22.
--
-- Grid: 10 cm cells; i across (0 = left), j along (0 = front bumper). Heights: 1 tunnel, 2 rear bay, 3 front bay.
local Core = NcmCore

Core.define("engineering.fixtures", function(C)
    local M = { version = "0.3.0" }

    local function port(id, kind, flow, cell, side, spec, reach)
        return { id = id, kind = kind, flow = flow, cell = cell, side = side, spec = spec, reach = reach }
    end
    local function rectCells(w, l)
        local out = {}
        for j = 0, l - 1 do for i = 0, w - 1 do out[#out + 1] = { i, j } end end
        return out
    end

    -- ---------------------------------------------------------------------------------------- designs
    local function box(id, massKg, w, l, ratios, shiftMs, eff, torqueNm, heatKw, spec, extra)
        local d = {
            id = id, family = "transmission", massKg = massKg, material = "alloy",
            shape = { bounds = { w * 0.10, l * 0.10, 0.25 } },
            footprint = { cells = rectCells(w, l), heightClass = 1 },
            ports = { port("in", "driveline", "in", { math.floor((w - 1) / 2), 0 }, "N", spec),
                      port("out", "driveline", "out", { math.floor((w - 1) / 2), l - 1 }, "S", spec) },
            mounts = { { id = "m", kind = "drivetrain", cell = { math.floor((w - 1) / 2), 2 } } },
            heatKw = heatKw,
            perf = { kind = "gearbox", ratios = ratios, reverse = 3.3, shiftMs = shiftMs, efficiency = eff, torqueNm = torqueNm },
        }
        for k, v in pairs(extra or {}) do d[k] = v end
        return d
    end

    M.DESIGNS = {
        hella_stock_box = box("hella_stock_box", 70, 3, 5, { 3.4, 2.0, 1.35, 1.0, 0.8 }, 350, 0.95, 420, 1.5, "archer_spline"),
        quadra_stock_box = box("quadra_stock_box", 74, 3, 5, { 3.3, 2.0, 1.4, 1.05, 0.82 }, 330, 0.95, 520, 1.6, "quadra_spline"),
        street6 = box("street6", 82, 3, 6, { 3.6, 2.1, 1.45, 1.1, 0.9, 0.75 }, 320, 0.96, 450, 2.0, "archer_spline"),
        comp6 = box("comp6", 65, 3, 5, { 3.2, 2.2, 1.65, 1.3, 1.08, 0.92 }, 120, 0.97, 600, 2.5, "archer_spline"),
        race6 = box("race6", 42, 2, 5, { 3.0, 2.15, 1.7, 1.38, 1.16, 1.0 }, 60, 0.975, 650, 3.0, "archer_spline",
            { powerKw = 0.3, controlChannels = 1, material = "composite" }),
    }

    local function rangeBox(id, massKg, w, l, shiftMs, extra)
        local d = {
            id = id, family = "transmission", massKg = massKg, material = "composite",
            shape = { bounds = { w * 0.10, l * 0.10, 0.15 } },
            footprint = { cells = rectCells(w, l), heightClass = 1 },
            ports = { port("in", "driveline", "in", { 0, 0 }, "N", "archer_spline"),
                      port("out", "driveline", "out", { w - 1, l - 1 }, "S", "archer_spline") },
            mounts = { { id = "m", kind = "drivetrain", cell = { 0, l - 1 } } },
            heatKw = 1.5, powerKw = 0.2, controlChannels = 1,
            perf = { kind = "range", ranges = { 1.0, 1.38 }, rangeShift = { ms = shiftMs, when = "any" },
                     efficiency = 0.98, torqueNm = 600 },
            lineage = "ghost",
        }
        for k, v in pairs(extra or {}) do d[k] = v end
        return d
    end
    M.DESIGNS.ghost_rangebox = rangeBox("ghost_rangebox", 14, 2, 2, 180)
    M.DESIGNS.kimiko_rangebox_mk1 = rangeBox("kimiko_rangebox_mk1", 22, 2, 4, 260,
        { derivedFrom = "ghost_rangebox", maker = "Kimiko" })

    -- a selector routes the input to one of two outputs; a combiner joins two inputs to one output
    M.DESIGNS.transfer_selector = {
        id = "transfer_selector", family = "drivetrain", massKg = 18, material = "steel",
        footprint = { cells = rectCells(3, 2), heightClass = 1 },
        ports = { port("in", "driveline", "in", { 1, 0 }, "N", "archer_spline"),
                  port("out_a", "driveline", "out", { 0, 1 }, "S", "archer_spline"),
                  port("out_b", "driveline", "out", { 2, 1 }, "S", "archer_spline") },
        mounts = { { id = "m", kind = "drivetrain", cell = { 1, 0 } } },
        heatKw = 0.5, controlChannels = 1,
        perf = { kind = "selector", select = { ms = 600, when = "stationary" }, efficiency = 0.985 },
    }
    M.DESIGNS.transfer_combiner = {
        id = "transfer_combiner", family = "drivetrain", massKg = 16, material = "steel",
        footprint = { cells = rectCells(3, 2), heightClass = 1 },
        ports = { port("in_a", "driveline", "in", { 0, 0 }, "N", "archer_spline"),
                  port("in_b", "driveline", "in", { 2, 0 }, "N", "archer_spline"),
                  port("out", "driveline", "out", { 1, 1 }, "S", "archer_spline") },
        mounts = { { id = "m", kind = "drivetrain", cell = { 1, 1 } } },
        heatKw = 0.4,
        perf = { kind = "selector", select = { ms = 600, when = "stationary" }, efficiency = 0.985 },
    }
    -- adapters: a real body whose job is to make two splines meet (L314 R4.4)
    local function adapter(id, inSpec, outSpec)
        return {
            id = id, family = "drivetrain", massKg = 3, material = "steel",
            footprint = { cells = { { 0, 0 } }, heightClass = 1 },
            ports = { port("in", "driveline", "in", { 0, 0 }, "N", inSpec),
                      port("out", "driveline", "out", { 0, 0 }, "S", outSpec) },
            perf = { kind = "adapter", ratio = 1, efficiency = 0.985 },
        }
    end
    M.DESIGNS.adapter_q2a = adapter("adapter_q2a", "quadra_spline", "archer_spline")
    M.DESIGNS.adapter_a2q = adapter("adapter_a2q", "archer_spline", "quadra_spline")

    -- L316 F0: the first body that produces a force. Its thrust is a LOAD (where, which way, how hard), never a
    -- capability (L314: no `allowsFlight`). Applied at the centre of mass, so it has no lever arm and no torque
    -- (attitude is F2). Illustrative: about twice the Hella's 1800 kg weight, the F0 hop's thrust-to-weight of 2.
    M.DESIGNS.f0_lift_rig = {
        id = "f0_lift_rig", family = "propulsion", massKg = 40, material = "alloy",
        shape = { bounds = { 0.6, 0.6, 0.3 } },
        footprint = { cells = rectCells(6, 6), heightClass = 2 },
        loads = { { kind = "thrust", pos = { 0, 0, 0 }, dir = { 0, 0, 1 }, magnitudeN = 36100 } },
        perf = { kind = "lift" },
    }

    -- L321 Engineering II: physical systems (doc 54 §B-§D). ILLUSTRATIVE numbers in real units, chosen to be
    -- plausible for a car-sized machine, not surveyed from any vehicle. Each perf block is an `engineering.systems`
    -- kind; each thrust load says where the force acts, in the body's own frame (nozzle axis +z).
    local function thruster(id, family, massKg, perf)
        return { id = id, family = family, massKg = massKg, material = "alloy",
                 shape = { bounds = { 0.15, 0.15, 0.25 } },
                 loads = { { kind = "thrust", pos = { 0, 0, 0 }, dir = { 0, 0, 1 }, magnitudeN = perf.thrustN or perf.forceN } },
                 perf = perf }
    end
    M.DESIGNS.rcs_n2_400 = thruster("rcs_n2_400", "propulsion", 3,
        { kind = "reaction_engine", thrustN = 400, ispS = 70, propellant = "n2", seaLevelFactor = 0.9, heatKw = 0 })
    M.DESIGNS.main_hydrazine_30k = thruster("main_hydrazine_30k", "propulsion", 60,
        { kind = "reaction_engine", thrustN = 30000, ispS = 230, propellant = "hydrazine", seaLevelFactor = 0.85,
          heatKw = 600, minThrottle = 0.2, throttleTauS = 0.3 })
    M.DESIGNS.main_hydrazine_45k = thruster("main_hydrazine_45k", "propulsion", 80,
        { kind = "reaction_engine", thrustN = 45000, ispS = 230, propellant = "hydrazine", seaLevelFactor = 0.85,
          heatKw = 900, minThrottle = 0.2, throttleTauS = 0.3 })
    M.DESIGNS.lift_fan_12k = thruster("lift_fan_12k", "aerodynamics", 60,
        { kind = "propeller", thrustN = 12000, powerW = 250000, heatKw = 25 })
    M.DESIGNS.ground_ram_30kj = thruster("ground_ram_30kj", "suspension", 45,
        { kind = "ground_ram", energyJ = 30000, forceN = 120000, strokeM = 0.3, chargeW = 20000, heatKw = 5 })
    M.DESIGNS.tank_hydrazine_400 = { id = "tank_hydrazine_400", family = "propulsion", massKg = 35, material = "alloy",
        shape = { bounds = { 0.9, 0.9, 0.6 } }, perf = { kind = "propellant_tank", capacityKg = 400, propellant = "hydrazine" } }
    M.DESIGNS.tank_n2_30 = { id = "tank_n2_30", family = "propulsion", massKg = 12, material = "alloy",
        shape = { bounds = { 0.3, 0.3, 0.8 } }, perf = { kind = "propellant_tank", capacityKg = 30, propellant = "n2" } }
    M.DESIGNS.radiator_panel_40 = { id = "radiator_panel_40", family = "cooling", massKg = 30, material = "alloy",
        shape = { bounds = { 1.2, 0.8, 0.05 } }, perf = { kind = "radiator", radiativeKw = 40, convectiveKw = 200 } }
    M.DESIGNS.battery_100mj = { id = "battery_100mj", family = "energy_storage", massKg = 120, material = "composite",
        shape = { bounds = { 1.0, 0.8, 0.15 } }, perf = { kind = "energy_store", capacityJ = 100e6, maxPowerW = 600000 } }
    M.DESIGNS.spaceframe_60k = { id = "spaceframe_60k", family = "structure", massKg = 80, material = "alloy",
        perf = { kind = "structure", ratedLoadN = 60000 } }

    -- L322: engines and tanks for the Snowglobe disciplines. A sprint engine is all thrust and heat for seconds; a
    -- Fireball engine is efficient and sustainable for minutes. ILLUSTRATIVE numbers in real units.
    M.DESIGNS.main_methalox_150k = thruster("main_methalox_150k", "propulsion", 140,
        { kind = "reaction_engine", thrustN = 150000, ispS = 300, propellant = "methalox", seaLevelFactor = 0.85,
          heatKw = 3500, minThrottle = 0.4 })
    M.DESIGNS.main_kerosene_60k = thruster("main_kerosene_60k", "propulsion", 90,
        { kind = "reaction_engine", thrustN = 60000, ispS = 320, propellant = "kerosene", seaLevelFactor = 0.85,
          heatKw = 1200, minThrottle = 0.1 })
    M.DESIGNS.tank_methalox_400 = { id = "tank_methalox_400", family = "propulsion", massKg = 40, material = "alloy",
        shape = { bounds = { 0.9, 0.9, 0.6 } }, perf = { kind = "propellant_tank", capacityKg = 400, propellant = "methalox" } }
    M.DESIGNS.tank_kerosene_1000 = { id = "tank_kerosene_1000", family = "propulsion", massKg = 60, material = "alloy",
        shape = { bounds = { 1.2, 1.0, 0.7 } }, perf = { kind = "propellant_tank", capacityKg = 1000, propellant = "kerosene" } }
    M.DESIGNS.tank_n2_60 = { id = "tank_n2_60", family = "propulsion", massKg = 20, material = "alloy",
        shape = { bounds = { 0.35, 0.35, 1.0 } }, perf = { kind = "propellant_tank", capacityKg = 60, propellant = "n2" } }

    -- L323 life support: a sealed two-seat cabin and its oxygen; the emergency suit a pilot wears. Breathing ~2e-5 kg
    -- O2/s working hard, so the cabin pack is about 7 hours for two and the emergency suit about 10 minutes.
    M.DESIGNS.pressure_cabin_2 = { id = "pressure_cabin_2", family = "chassis", massKg = 40, material = "composite",
        perf = { kind = "pressure_cabin", crew = 2, volumeM3 = 3, leakPerS = 0.0001 } }
    M.DESIGNS.life_support_1kg = { id = "life_support_1kg", family = "chassis", massKg = 15, material = "alloy",
        perf = { kind = "life_support", o2Kg = 1.0, scrubKgPerS = 1e-4 } }
    M.DESIGNS.eva_suit_emergency = { id = "eva_suit_emergency", family = "chassis", massKg = 18, material = "composite",
        perf = { kind = "eva_suit", o2Kg = 0.012, packThrustN = 120, packN2Kg = 3, packIspS = 70 } }

    -- Machines (a chassis plus placed parts; `engineering.machine.assemble`). Positions in the machine frame:
    -- x right, y forward, z up, metres from the chassis reference point at the floor centre.
    local car = { massKg = 1500, com = { 0, 0, 0.5 }, bounds = { 1.9, 4.6, 1.4 }, ratedLoadN = 150000, wheels = true }
    local function rcs(key, pos, dir) return { key = key, body = M.DESIGNS.rcs_n2_400, pos = pos, dir = dir } end
    M.MACHINES = {}
    --- The Snowglobe orbiter: a main engine under the CoM, sixteen cold-gas RCS thrusters in opposed pairs at the
    --- four extremities (six-axis control), two hydrazine tanks (enough delta-v to reach a station and race), a
    --- nitrogen tank, a radiator, a battery, a spaceframe.
    M.MACHINES.ls_orbiter = {
        id = "ls_orbiter", origin = "los_santos",
        chassis = car,
        parts = {
            { key = "main", body = M.DESIGNS.main_hydrazine_45k, pos = { 0, 0, 0.05 }, dir = { 0, 0, 1 } },
            -- balanced fore and aft over the main engine: tanks drain symmetrically, battery against radiator
            { key = "tank_main", body = M.DESIGNS.tank_hydrazine_400, pos = { 0, -0.6, 0.6 } },
            { key = "tank_main2", body = M.DESIGNS.tank_hydrazine_400, pos = { 0, 0.6, 0.6 } },
            { key = "tank_rcs", body = M.DESIGNS.tank_n2_30, pos = { 0, 0, 0.9 } },
            { key = "radiator", body = M.DESIGNS.radiator_panel_40, pos = { 0, -1.8, 1.3 } },
            { key = "battery", body = M.DESIGNS.battery_100mj, pos = { 0, 0.45, 0.2 } },
            { key = "frame", body = M.DESIGNS.spaceframe_60k, pos = { 0, 0, 0.5 } },
            { key = "cabin", body = M.DESIGNS.pressure_cabin_2, pos = { 0, 0, 0.6 } },
            { key = "o2", body = M.DESIGNS.life_support_1kg, pos = { 0, 0, 0.3 } },
            rcs("rcs_f_px", { 0.0, 2.2, 0.55 }, { 1, 0, 0 }), rcs("rcs_f_nx", { 0.0, 2.2, 0.55 }, { -1, 0, 0 }),
            rcs("rcs_f_pz", { 0.0, 2.2, 0.55 }, { 0, 0, 1 }), rcs("rcs_f_nz", { 0.0, 2.2, 0.55 }, { 0, 0, -1 }),
            rcs("rcs_r_px", { 0.0, -2.2, 0.55 }, { 1, 0, 0 }), rcs("rcs_r_nx", { 0.0, -2.2, 0.55 }, { -1, 0, 0 }),
            rcs("rcs_r_pz", { 0.0, -2.2, 0.55 }, { 0, 0, 1 }), rcs("rcs_r_nz", { 0.0, -2.2, 0.55 }, { 0, 0, -1 }),
            rcs("rcs_l_py", { -0.95, 0.0, 0.55 }, { 0, 1, 0 }), rcs("rcs_l_ny", { -0.95, 0.0, 0.55 }, { 0, -1, 0 }),
            rcs("rcs_l_pz", { -0.95, 0.0, 0.55 }, { 0, 0, 1 }), rcs("rcs_l_nz", { -0.95, 0.0, 0.55 }, { 0, 0, -1 }),
            rcs("rcs_r2_py", { 0.95, 0.0, 0.55 }, { 0, 1, 0 }), rcs("rcs_r2_ny", { 0.95, 0.0, 0.55 }, { 0, -1, 0 }),
            rcs("rcs_r2_pz", { 0.95, 0.0, 0.55 }, { 0, 0, 1 }), rcs("rcs_r2_nz", { 0.95, 0.0, 0.55 }, { 0, 0, -1 }),
        },
    }
    --- Four big thrusters, all pointing up, at the corners: lots of lift, and only pitch and roll -- no yaw, no
    --- sideways, no braking. "Four badly placed thrusters do not give six-axis control" (brief §11).
    M.MACHINES.corner_quad = {
        id = "corner_quad", origin = "night_city",
        chassis = car,
        parts = {
            { key = "fl", body = M.DESIGNS.main_hydrazine_45k, pos = { -0.9, 1.8, 0.3 } },
            { key = "fr", body = M.DESIGNS.main_hydrazine_45k, pos = { 0.9, 1.8, 0.3 } },
            { key = "rl", body = M.DESIGNS.main_hydrazine_45k, pos = { -0.9, -1.8, 0.3 } },
            { key = "rr", body = M.DESIGNS.main_hydrazine_45k, pos = { 0.9, -1.8, 0.3 } },
            { key = "tank", body = M.DESIGNS.tank_hydrazine_400, pos = { 0, 0, 0.6 } },
        },
    }
    --- A street car with a ground ram under the CoM and a battery to recharge it: it hops; in the air it is a car.
    M.MACHINES.ram_hopper = {
        id = "ram_hopper", origin = "night_city",
        chassis = car,
        parts = {
            { key = "ram", body = M.DESIGNS.ground_ram_30kj, pos = { 0, 0, 0.0 }, dir = { 0, 0, 1 } },
            { key = "battery", body = M.DESIGNS.battery_100mj, pos = { 0, 0, 0.5 } },
        },
    }
    --- SPRINT: a dragster. 150 kN of methalox under the CoM, one tank, two pitch-trim RCS pairs and nothing else: a
    --- thrust-to-weight near 7 for about 8 seconds, little attitude authority, a lot of heat. Wins a short sprint;
    --- useless in Fireball.
    M.MACHINES.sprint_dragster = {
        id = "sprint_dragster", origin = "los_santos",
        chassis = { massKg = 1300, com = { 0, 0, 0.5 }, bounds = { 1.9, 4.6, 1.3 }, ratedLoadN = 200000, wheels = true },
        parts = {
            { key = "main", body = M.DESIGNS.main_methalox_150k, pos = { 0, 0, 0.05 }, dir = { 0, 0, 1 } },
            { key = "tank", body = M.DESIGNS.tank_methalox_400, pos = { 0, 0, 0.6 } },
            { key = "tank_rcs", body = M.DESIGNS.tank_n2_30, pos = { 0, 0, 0.9 } },
            { key = "radiator", body = M.DESIGNS.radiator_panel_40, pos = { 0, -1.8, 1.25 } },
            { key = "battery", body = M.DESIGNS.battery_100mj, pos = { 0, 0.45, 0.2 } },
            { key = "cabin", body = M.DESIGNS.pressure_cabin_2, pos = { 0, 0, 0.6 } },
            { key = "o2", body = M.DESIGNS.life_support_1kg, pos = { 0, 0, 0.3 } },
            rcs("rcs_f_pz", { 0.0, 2.2, 0.55 }, { 0, 0, 1 }), rcs("rcs_f_nz", { 0.0, 2.2, 0.55 }, { 0, 0, -1 }),
            rcs("rcs_r_pz", { 0.0, -2.2, 0.55 }, { 0, 0, 1 }), rcs("rcs_r_nz", { 0.0, -2.2, 0.55 }, { 0, 0, -1 }),
        },
    }
    --- FIREBALL: an efficient kerosene engine, two tonnes of propellant, sixteen RCS thrusters and three radiators:
    --- about 2 km/s of delta-v and minutes of sustainable thrust. Slow off the line; built to go round.
    local fireballParts = {
        { key = "main", body = M.DESIGNS.main_kerosene_60k, pos = { 0, 0, 0.05 }, dir = { 0, 0, 1 } },
        { key = "tank_a", body = M.DESIGNS.tank_kerosene_1000, pos = { 0, -0.7, 0.65 } },
        { key = "tank_b", body = M.DESIGNS.tank_kerosene_1000, pos = { 0, 0.7, 0.65 } },
        { key = "tank_rcs", body = M.DESIGNS.tank_n2_60, pos = { 0, 0, 1.0 } },
        { key = "rad_l", body = M.DESIGNS.radiator_panel_40, pos = { -0.95, 0, 1.3 } },
        { key = "rad_r", body = M.DESIGNS.radiator_panel_40, pos = { 0.95, 0, 1.3 } },
        { key = "rad_t", body = M.DESIGNS.radiator_panel_40, pos = { 0, 0, 1.35 } },
        { key = "battery", body = M.DESIGNS.battery_100mj, pos = { 0, 0, 0.2 } },
        { key = "frame", body = M.DESIGNS.spaceframe_60k, pos = { 0, 0, 0.5 } },
        { key = "cabin", body = M.DESIGNS.pressure_cabin_2, pos = { 0, 0, 0.6 } },
        { key = "o2", body = M.DESIGNS.life_support_1kg, pos = { 0, 0, 0.3 } },
    }
    for _, p in ipairs(M.MACHINES.ls_orbiter.parts) do
        if p.key:sub(1, 4) == "rcs_" then fireballParts[#fireballParts + 1] = p end
    end
    M.MACHINES.fireball_racer = {
        id = "fireball_racer", origin = "snowglobe",
        chassis = { massKg = 1400, com = { 0, 0, 0.5 }, bounds = { 1.9, 4.6, 1.4 }, ratedLoadN = 150000, wheels = true },
        parts = fireballParts,
    }
    --- L323: the car a Cyberpunk player flies today -- the Hella's 1,800 kg with the F0 lift rig. Its lift is the Thrust
    --- INSTRUMENT (L321), not a technology: as an entrant it is mass and identity, flown by the host and observed.
    M.MACHINES.instrument_car = {
        id = "instrument_car", origin = "night_city",
        chassis = { massKg = 1760, com = { 0, 0, 0.5 }, bounds = { 1.9, 4.6, 1.4 }, ratedLoadN = 150000, wheels = true },
        parts = { { key = "lift_rig", body = M.DESIGNS.f0_lift_rig, pos = { 0, 0, 0.5 } } },
    }
    --- A lift-fan car: flies in thick air on battery power; nothing above the atmosphere.
    M.MACHINES.fan_car = {
        id = "fan_car", origin = "los_santos",
        chassis = { massKg = 900, com = { 0, 0, 0.5 }, bounds = { 1.8, 4.2, 1.3 }, wheels = true },
        parts = {
            { key = "fan_f", body = M.DESIGNS.lift_fan_12k, pos = { 0, 1.5, 0.5 } },
            { key = "fan_r", body = M.DESIGNS.lift_fan_12k, pos = { 0, -1.5, 0.5 } },
            { key = "battery", body = M.DESIGNS.battery_100mj, pos = { 0, 0, 0.5 } },
            { key = "radiator", body = M.DESIGNS.radiator_panel_40, pos = { 0, 0, 1.2 } },
        },
    }

    -- ------------------------------------------------------------------------------------------ sites
    M.SITES = {}

    M.SITES.archer_hella = {
        kind = "car", model = "archer_hella", provenance = "fixture",
        grid = { cell = 0.10, w = 18, l = 44 },
        zones = {
            { name = "tunnel", rects = { { 7, 12, 10, 27 } }, adaptable = { { 6, 12, 6, 27 }, { 11, 12, 11, 27 } },
              height = 1, coverable = true, fabricable = true },
            { name = "cabin", rects = { { 2, 12, 15, 27 } }, reserved = true },
            { name = "front_bay", rects = { { 2, 1, 15, 11 } }, height = 3, fabricable = true },
            { name = "rear_bay", rects = { { 3, 28, 14, 39 } }, height = 2, fabricable = true },
            { name = "rear_pocket", rects = { { 15, 30, 16, 32 } }, height = 1 },
        },
        mounts = {
            { id = "engine", kind = "engine", cell = { 8, 5 }, ratedKg = 260 },
            { id = "tunnel_front", kind = "drivetrain", cell = { 8, 14 }, ratedKg = 100 },
            { id = "tunnel_rear", kind = "drivetrain", cell = { 8, 20 }, ratedKg = 100 },
            { id = "rear_bay", kind = "drivetrain", cell = { 8, 30 }, ratedKg = 120 },
            { id = "pocket", kind = "drivetrain", cell = { 15, 31 }, ratedKg = 30 },
        },
        ports = {
            port("engine_out", "driveline", "out", { 8, 11 }, "S", "archer_spline"),
            port("diff_in", "driveline", "in", { 8, 36 }, "N", "archer_spline", 20),
        },
        capacity = { massKg = 1950, coolingKw = 4.0, electricalKw = 3.0, controlChannels = 4 },
        stock = {
            massKg = 1800, massProvenance = "record total_mass (Vehicle.v_standard2_archer_hella), live +0x1BC",
            layout = { placements = { { key = "box", design = "hella_stock_box", at = { 7, 12 }, rot = 0 } } },
        },
        ref = { firstRatio = 3.4, topRatio = 0.8, topMps = 115 / 3.6 },
    }

    M.SITES.quadra_turbo = {
        kind = "car", model = "quadra_turbo", provenance = "fixture",
        grid = { cell = 0.10, w = 19, l = 46 },
        zones = {
            { name = "tunnel", rects = { { 8, 13, 10, 28 } }, height = 1, fabricable = true },
            { name = "cabin", rects = { { 2, 13, 16, 28 } }, reserved = true },
            { name = "front_bay", rects = { { 2, 1, 16, 12 } }, height = 3, fabricable = true },
            { name = "rear_bay", rects = { { 3, 29, 15, 40 } }, height = 2, fabricable = true },
        },
        mounts = {
            { id = "engine", kind = "engine", cell = { 9, 6 }, ratedKg = 300 },
            { id = "tunnel_front", kind = "drivetrain", cell = { 9, 15 }, ratedKg = 110 },
            { id = "tunnel_rear", kind = "drivetrain", cell = { 9, 22 }, ratedKg = 110 },
        },
        ports = {
            port("engine_out", "driveline", "out", { 9, 12 }, "S", "quadra_spline"),
            port("diff_in", "driveline", "in", { 9, 38 }, "N", "quadra_spline", 22),
        },
        capacity = { massKg = 1600, coolingKw = 5.0, electricalKw = 3.0, controlChannels = 4 },
        stock = {
            massKg = 1470, massProvenance = "record total_mass (Vehicle.v_sport1_quadra_turbo), live +0x1BC",
            layout = { placements = { { key = "box", design = "quadra_stock_box", at = { 8, 13 }, rot = 0 } } },
        },
        ref = { firstRatio = 3.3, topRatio = 0.82, topMps = 140 / 3.6 },
    }

    return M
end)
