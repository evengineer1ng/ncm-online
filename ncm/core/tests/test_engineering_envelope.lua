-- engineering.body / envelope / fit / drivetrain / actuate (doc 50; L314): the physical grammar, the car site,
-- the fitting rule, the four ruled drivetrain relationships, and mass as canonical state.
local function mods(T)
    local C = T.Core
    return C.get("engineering.body"), C.get("engineering.envelope"), C.get("engineering.fit"),
        C.get("engineering.drivetrain"), C.get("engineering.actuate"), C.get("engineering.fixtures")
end

local function site(T, name)
    local _, Envelope, _, _, _, F = mods(T)
    -- a fresh copy each time: compile() annotates the table
    local function deep(t)
        if type(t) ~= "table" then return t end
        local o = {}
        for k, v in pairs(t) do o[k] = deep(v) end
        return o
    end
    local s, why = Envelope.compile(deep(F.SITES[name]))
    T.ok(s, name .. " compiles: " .. table.concat(why or {}, "; "))
    return s
end

local function codes(entry)
    local out = {}
    for _, r in ipairs((entry and entry.reasons) or {}) do out[r.code] = true end
    return out
end

local HELLA_IN = { a = { "site", "engine_out" } }

return {
    every_fixture_design_is_a_valid_body = function(T)
        local Body, _, _, _, _, F = mods(T)
        for id, d in pairs(F.DESIGNS) do
            local ok, why = Body.validate(d)
            T.ok(ok, id .. ": " .. table.concat(why or {}, "; "))
        end
    end,

    family_is_open_taxonomy_and_3d_fields_are_canonical = function(T)
        local Body = mods(T)
        local thruster = {
            id = "test_force_body", family = "something_new", massKg = 9,
            shape = { bounds = { 0.3, 0.3, 0.6 }, ref = "fixture/none" },
            com = { 0.15, 0.15, 0.2 },
            ports = { { id = "p", kind = "power", flow = "in", pos = { 0, 0, 0 }, dir = { 0, 0, -1 } } },
            loads = { { kind = "force", pos = { 0.15, 0.15, 0.6 }, dir = { 0, 0, 1 }, magnitudeN = 100 } },
        }
        T.ok(Body.validate(thruster), "a family outside the twelve is still a body (R5); 3D fields validate (R2)")
        T.falsy(Body.knownFamily("something_new"), "and it is reported as not one of the twelve")
        T.ok(Body.knownFamily("transmission"), "the twelve are recognised")
        local ok = Body.validate({ id = "x", family = "transmission", massKg = 0 })
        T.falsy(ok, "a body has mass (conservation)")
    end,

    rotation_moves_cells_ports_and_sides_together = function(T)
        local Body, _, _, _, _, F = mods(T)
        local p = Body.place(F.DESIGNS.street6, { at = { 0, 0 }, rot = 90 })
        local maxI, maxJ = 0, 0
        for _, c in ipairs(p.cells) do maxI = math.max(maxI, c[1]); maxJ = math.max(maxJ, c[2]) end
        T.eq(maxI, 5, "a 3x6 box turned 90 degrees is 6 wide")
        T.eq(maxJ, 2, "and 3 long")
        local sides = {}
        for _, port in ipairs(p.ports) do sides[port.id] = port.side end
        T.eq(sides["in"], "E", "N turns to E")
        T.eq(sides.out, "W", "S turns to W")
        T.eq(p.transform.yawDeg, 90, "the projection names the canonical transform it stands for")
    end,

    the_stock_layout_fits_green_and_keeps_the_record_mass = function(T)
        local _, _, Fit, _, _, F = mods(T)
        local s = site(T, "archer_hella")
        local r = Fit.check(s, {
            placements = { { key = "box", design = "hella_stock_box", at = { 7, 12 } } },
            connections = { { a = { "site", "engine_out" }, b = { "box", "in" } }, { a = { "box", "out" }, b = { "site", "diff_in" } } },
        }, F.DESIGNS)
        T.eq(r.verdict, "green", "the factory car fits its own envelope")
        T.eq(r.state.massKg, 1800, "and weighs what its record says")
        T.eq(r.state.deltaKg, 0, "no delta")
    end,

    the_double_street_box_fits_and_is_heavy = function(T)
        local _, _, Fit, DT, _, F = mods(T)
        local s = site(T, "archer_hella")
        local r = Fit.check(s, {
            placements = { { key = "a", design = "street6", at = { 7, 12 } }, { key = "b", design = "street6", at = { 7, 18 } } },
            connections = { { a = { "site", "engine_out" }, b = { "a", "in" } }, { a = { "a", "out" }, b = { "b", "in" } },
                            { a = { "b", "out" }, b = { "site", "diff_in" } } },
        }, F.DESIGNS)
        T.eq(r.verdict, "green", "it fits (doc 48: 'It fits.')")
        T.eq(r.state.bodiesKg, 164, "164 kg of transmission")
        T.eq(r.state.massKg, 1800 - 70 + 164, "the car carries all of it")
        T.eq(#r.drivetrain.paths, 1, "one path: series")
        T.eq(r.drivetrain.paths[1].combinations, 36, "two 6-speeds in series multiply")
        T.eq(#DT.combinations(r.drivetrain.paths[1]), 36, "and the spec keeps every combination")
    end,

    the_ghost_box_fits_where_no_other_gearbox_can = function(T)
        local _, _, Fit, _, _, F = mods(T)
        local s = site(T, "archer_hella")
        for _, id in ipairs({ "street6", "comp6", "race6", "kimiko_rangebox_mk1" }) do
            local r = Fit.check(s, { placements = { { key = "x", design = id, at = { 15, 30 } } } }, F.DESIGNS)
            T.eq(r.placements.x.colour, "red", id .. " does not fit the rear pocket")
        end
        local r = Fit.check(s, { placements = { { key = "x", design = "ghost_rangebox", at = { 15, 30 } } } }, F.DESIGNS)
        T.eq(r.placements.x.colour, "green", "the 14 kg ghost box does: geometry is a stat")
        T.ok(codes(r.driveline).dangling, "though unconnected it drives nothing, and says so")
    end,

    series_with_a_range_box_carries_its_own_shift_procedure = function(T)
        local _, _, Fit, DT, _, F = mods(T)
        local s = site(T, "archer_hella")
        local r = Fit.check(s, {
            placements = { { key = "main", design = "street6", at = { 7, 12 } }, { key = "range", design = "ghost_rangebox", at = { 8, 18 } } },
            connections = { { a = { "site", "engine_out" }, b = { "main", "in" } }, { a = { "main", "out" }, b = { "range", "in" } },
                            { a = { "range", "out" }, b = { "site", "diff_in" } } },
        }, F.DESIGNS)
        T.ok(r.verdict ~= "red", "a 6-speed into a range box fits")
        local path = r.drivetrain.paths[1]
        T.eq(path.combinations, 12, "6 x 2 range = 12")
        T.eq(path.stages[2].kind, "range", "the range stage is a range, not a second gearbox")
        T.eq(path.stages[2].procedure.ms, 180, "with its own shift time")
        T.eq(path.stages[1].procedure.ms, 320, "separate from the main box's")
        T.ok(codes(r.placements.range).bracket, "no tunnel mount under it: a fabricated bracket (yellow)")
    end,

    selectable_boxes_stay_separate_and_overlap_is_kept = function(T)
        local _, _, Fit, DT, _, F = mods(T)
        local s = site(T, "archer_hella")
        local r = Fit.check(s, {
            placements = {
                { key = "sel", design = "transfer_selector", at = { 7, 12 } },
                { key = "A", design = "race6", at = { 7, 14 } },
                { key = "B", design = "race6", at = { 9, 14 } },
                { key = "join", design = "transfer_combiner", at = { 7, 19 } },
            },
            connections = {
                { a = { "site", "engine_out" }, b = { "sel", "in" } },
                { a = { "sel", "out_a" }, b = { "A", "in" } }, { a = { "sel", "out_b" }, b = { "B", "in" } },
                { a = { "A", "out" }, b = { "join", "in_a" } }, { a = { "B", "out" }, b = { "join", "in_b" } },
                { a = { "join", "out" }, b = { "site", "diff_in" } },
            },
        }, F.DESIGNS)
        T.ok(r.drivetrain.ok, "a selector may split power and a selector may rejoin it")
        T.eq(r.drivetrain.selection, "selectable", "two paths: the driver or controller picks one")
        T.eq(#r.drivetrain.paths, 2, "two separate ratio sets")
        local a, b = DT.ladder(r.drivetrain.paths[1]), DT.ladder(r.drivetrain.paths[2])
        T.eq(#a, 6, "path one keeps its six")
        T.eq(#b, 6, "path two keeps its six, though they are identical (R4.3: overlap is intentional)")
        T.eq(r.drivetrain.paths[1].stages[1].procedure.when, "stationary", "the selector's own procedure")
        T.ok(r.state.heatKw > s.capacity.coolingKw, "this build runs hotter than the car can cool")
        local hot = false
        for _, c in ipairs(r.consequences) do if c.capacity == "coolingKw" then hot = true end end
        T.ok(hot, "which is a consequence")
        T.ok(r.verdict ~= "red", "and never a refusal")
    end,

    power_cannot_split_without_a_selector = function(T)
        local _, _, Fit, _, _, F = mods(T)
        local s = site(T, "archer_hella")
        local r = Fit.check(s, {
            placements = { { key = "A", design = "race6", at = { 7, 12 } }, { key = "B", design = "race6", at = { 9, 12 } } },
            connections = { { a = { "site", "engine_out" }, b = { "A", "in" } }, { a = { "site", "engine_out" }, b = { "B", "in" } },
                            { a = { "A", "out" }, b = { "site", "diff_in" } }, { a = { "B", "out" }, b = { "site", "diff_in" } } },
        }, F.DESIGNS)
        T.eq(r.verdict, "red", "topology is red")
        T.ok(codes(r.driveline).split_without_selector, "with the reason")
    end,

    an_adapter_is_a_summarised_consequence_or_a_real_body = function(T)
        local _, _, Fit, _, _, F = mods(T)
        local s = site(T, "quadra_turbo")
        local implicit = Fit.check(s, {
            placements = { { key = "box", design = "street6", at = { 8, 13 } } },
            connections = { { a = { "site", "engine_out" }, b = { "box", "in" } }, { a = { "box", "out" }, b = { "site", "diff_in" } } },
        }, F.DESIGNS)
        T.eq(implicit.verdict, "yellow", "an Archer box in a Quadra fits through adaptation")
        local n = 0
        for _, a in ipairs(implicit.adaptations) do if a.kind == "adapter" then n = n + 1; T.ok(a.massKg > 0, "an adapter weighs something") end end
        T.eq(n, 2, "one at each spline")
        T.ok(implicit.drivetrain.paths[1].efficiency < 0.96, "and costs efficiency")

        local explicit = Fit.check(s, {
            placements = { { key = "ad1", design = "adapter_q2a", at = { 9, 12 } }, { key = "box", design = "street6", at = { 8, 13 } },
                           { key = "ad2", design = "adapter_a2q", at = { 9, 19 } } },
            connections = { { a = { "site", "engine_out" }, b = { "ad1", "in" } }, { a = { "ad1", "out" }, b = { "box", "in" } },
                            { a = { "box", "out" }, b = { "ad2", "in" } }, { a = { "ad2", "out" }, b = { "site", "diff_in" } } },
        }, F.DESIGNS)
        T.eq(explicit.verdict, "green", "with the adapters as bodies, every port meets (R4.4)")
        T.eq(explicit.drivetrain.paths[1].stages[1].kind, "adapter", "and the adapter is a stage of the drivetrain")
        T.eq(explicit.state.bodiesKg, 82 + 3 + 3, "with its own mass")
    end,

    red_is_geometry_and_topology_only = function(T)
        local _, _, Fit, _, _, F = mods(T)
        local s = site(T, "archer_hella")
        local r = Fit.check(s, { placements = { { key = "a", design = "street6", at = { 7, 12 } }, { key = "b", design = "street6", at = { 7, 12 } } } }, F.DESIGNS)
        T.ok(codes(r.placements.b).overlap, "an overlap is red")
        r = Fit.check(s, { placements = { { key = "a", design = "street6", at = { 7, 12 }, rot = 90 } } }, F.DESIGNS)
        T.ok(codes(r.placements.a).reserved, "turned sideways it reaches the driver's seat: red")
        T.ok(codes(r.placements.a).cut, "and the footwell cells it reaches are a cut (yellow) on the way")
        r = Fit.check(s, { placements = { { key = "a", design = "street6", at = { 16, 40 } } } }, F.DESIGNS)
        T.ok(codes(r.placements.a).outside, "off the car is red")
        local designs = { street6 = F.DESIGNS.street6, rad = { id = "rad", family = "cooling", massKg = 6,
            footprint = { cells = { { 0, 0 } } }, ports = { { id = "core", kind = "coolant", flow = "in", cell = { 0, 0 } } } } }
        r = Fit.check(s, { placements = { { key = "box", design = "street6", at = { 7, 12 } }, { key = "rad", design = "rad", at = { 8, 3 } } },
                           connections = { { a = { "box", "out" }, b = { "rad", "core" } } } }, designs)
        T.ok(codes(r.connections[1]).kind_mismatch, "a driveline cannot feed a radiator")
    end,

    an_unsurveyed_site_fails_closed = function(T)
        local _, Envelope, Fit, _, _, F = mods(T)
        local s = Envelope.compile({ kind = "car", provenance = "unknown", grid = { cell = 0.1, w = 4, l = 4 }, zones = {} })
        local r = Fit.check(s, { placements = { { key = "a", design = "ghost_rangebox", at = { 0, 0 } } } }, F.DESIGNS)
        T.eq(r.verdict, "red", "unknown is red")
        T.eq(r.reasons[1].code, "not_surveyed", "and says why: never a guess")
    end,

    competency_improves_adaptation_but_never_erases_it = function(T)
        local _, _, Fit, _, _, F = mods(T)
        local s = site(T, "quadra_turbo")
        local layout = {
            placements = { { key = "box", design = "street6", at = { 8, 13 } } },
            connections = { { a = { "site", "engine_out" }, b = { "box", "in" } }, { a = { "box", "out" }, b = { "site", "diff_in" } } },
        }
        local novice = Fit.check(s, layout, F.DESIGNS, { competency = 0 })
        local expert = Fit.check(s, layout, F.DESIGNS, { competency = 1 })
        T.ok(expert.state.adaptationKg < novice.state.adaptationKg, "an expert's adapter is lighter")
        T.ok(expert.state.adaptationKg > 0, "but still weighs something (conservation)")
        T.ok(expert.adaptations[1].minutes < novice.adaptations[1].minutes and expert.adaptations[1].minutes > 0,
            "and takes less time, never none")
        T.eq(expert.state.bodiesKg, novice.state.bodiesKg, "skill never touches what the bodies weigh")
    end,

    a_transmission_never_creates_power = function(T)
        local _, _, Fit, DT, _, F = mods(T)
        local s = site(T, "archer_hella")
        local r = Fit.check(s, {
            placements = { { key = "a", design = "street6", at = { 7, 12 } }, { key = "b", design = "street6", at = { 7, 18 } } },
            connections = { { a = { "site", "engine_out" }, b = { "a", "in" } }, { a = { "a", "out" }, b = { "b", "in" } },
                            { a = { "b", "out" }, b = { "site", "diff_in" } } },
        }, F.DESIGNS)
        local path = r.drivetrain.paths[1]
        T.ok(path.efficiency < 1, "every stage loses something")
        local gears = DT.virtualGears(DT.ladder(path), s.ref, path.efficiency)
        for _, g in ipairs(gears) do
            T.ok(g.share <= 1, "no gear asks the actuator for more than full drive")
            -- force x speed: share x ceiling never beats the stock first gear's
            T.ok(g.share * g.ceilingMps <= 1.0001 * (s.ref.topMps * s.ref.topRatio / s.ref.firstRatio) * path.efficiency,
                "power out never exceeds power in")
        end
        T.ok(gears[1].capped, "a 13:1 crawler would ask for more force than the actuator can give, and says it was capped")
        local bad = { street6 = F.DESIGNS.street6, cheat = { id = "cheat", family = "transmission", massKg = 5,
            footprint = { cells = { { 0, 0 } } }, perf = { kind = "gearbox", ratios = { 1 }, powerKw = 50 },
            ports = { { id = "in", kind = "driveline", flow = "in", cell = { 0, 0 } }, { id = "out", kind = "driveline", flow = "out", cell = { 0, 0 } } } } }
        r = Fit.check(s, { placements = { { key = "c", design = "cheat", at = { 8, 12 } } },
            connections = { { a = { "site", "engine_out" }, b = { "c", "in" } }, { a = { "c", "out" }, b = { "site", "diff_in" } } } }, bad)
        T.ok(codes(r.driveline).creates_power, "a transmission that declares power is refused")
    end,

    the_state_keeps_the_modelled_mass_whatever_the_actuator = function(T)
        local _, _, _, _, Act = mods(T)
        local state = { stockMassKg = 1800, massKg = 1947 }
        local rec = Act.mass(state, "record")
        T.eq(state.massKg, 1947, "the canonical state is untouched (R3)")
        T.eq(rec.stateKg, 1947, "the actuator reports the truth it is expressing")
        T.ok(math.abs(rec.flats[1].multiplier - 1947 / 1800) < 1e-9, "the record channel scales total_mass")
        local inst = Act.mass(state, "instance")
        T.ok(math.abs(inst.driveScale - 1800 / 1947) < 1e-9, "the approximation scales drive by m0/m")
        T.eq(inst.brakeScale, inst.driveScale, "and brakes the same")
        T.ok(#inst.losses >= 3, "and lists what it cannot express")
        local light = Act.mass({ stockMassKg = 1800, massKg = 1700 }, "instance")
        T.eq(light.unexpressedKg, -100, "lighter than stock is stored, and shown as not expressed")
        T.eq(light.driveScale, 1, "rather than faked")
        local huge = Act.mass({ stockMassKg = 1800, massKg = 3000 }, "record")
        T.eq(huge.flats[1].multiplier, 1.40, "the record channel has its machine.flats bound")
        T.eq(huge.stateKg, 3000, "and the state still says 3000")
    end,

    a_lift_rig_is_a_load_not_a_capability = function(T)
        local Body, _, _, _, Act, F = mods(T)
        local rig = F.DESIGNS.f0_lift_rig
        T.ok(Body.validate(rig), "the F0 lift rig is a valid body")
        T.eq(rig.allowsFlight, nil, "it grants nothing (L314)")
        T.eq(Act.liftN(rig), 36100, "its lift is the vertical part of its thrust load")
        local tilted = { loads = { { kind = "thrust", pos = { 0, 0, 0 }, dir = { 1, 0, 1 }, magnitudeN = 1000 } } }
        T.ok(math.abs(Act.liftN(tilted) - 1000 / math.sqrt(2)) < 1e-9, "a tilted thruster lifts by its vertical share")
    end,

    the_state_keeps_the_modelled_lift_whatever_the_lever = function(T)
        local _, _, _, _, Act, F = mods(T)
        local hella = 1800 + F.DESIGNS.f0_lift_rig.massKg
        local l = Act.lift(Act.liftN(F.DESIGNS.f0_lift_rig), hella)
        T.ok(math.abs(l.stateTwr - 36100 / (hella * 9.81)) < 1e-9, "thrust-to-weight from newtons and the car's mass")
        T.eq(l.expressedTwr, l.stateTwr, "under the lever's clamp it is expressed whole")
        local big = Act.lift(200000, 1800)
        T.eq(big.expressedTwr, 3.0, "the lever clamps at 3")
        T.ok(big.stateTwr > 11 and big.unexpressedTwr > 8, "and the state keeps the rest, shown as not expressed")
        T.ok(#big.losses >= 2, "and lists what it cannot express")
        T.eq(Act.lift(1000, 0).channel, "none", "no mass, no lift")
    end,

    the_f0_hop_is_predicted_before_it_is_flown = function(T)
        local _, _, _, _, Act = mods(T)
        local v, h = Act.hopPrediction(2.0, 0.143)
        T.ok(math.abs(v - 1.403) < 0.01, "r=2 for 143 ms peaks at 1.40 m/s")
        T.ok(math.abs(h - 0.20) < 0.005, "and rises 0.20 m (doc 51 §F0)")
        local v1, h1 = Act.hopPrediction(1.0, 0.5)
        T.eq(v1, 0, "r=1 is weightless, not a climb")
        T.eq(h1, 0, "so no rise is predicted")
        local _, h3 = Act.hopPrediction(3.0, 0.143)
        T.ok(math.abs(h3 - 0.60) < 0.01, "r=3 triples the rise: it goes as r(r-1)")
    end,
}
