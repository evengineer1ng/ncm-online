-- ncm-core module: space.genesis
--
-- Snowglobe exists in every seed (L321; doc 54 §F, §G). From one `world.seed` node this generates the BASE state of
-- the space above both cities: stations on orbits of the (compressed) Earth, the anomaly's deterministic ephemeris,
-- venues, the organisations and pilots who race there, the technology history that got them there, and the machines
-- they race -- before any player arrives. Pure and re-derivable: nothing here is stored; committed history is
-- applied on top by `world.seed.compose`.
--
-- SEEDS DIFFER IN HISTORY, NOT ARITHMETIC. A seed does not roll "tech level 3". It plants root designs in different
-- worlds and runs a seeded history of reverse engineering between them (`engineering.lineage`): in one seed Los
-- Santos aero work reached orbit through a Snowglobe reconstruction; in another, nobody ever copied the good engine
-- and the field is fans and hoppers. The machines are assembled from what each organisation's history gave it, so
-- the capability distribution -- and therefore what sport can exist (`space.sport`) -- falls out of the history.
local Core = NcmCore

Core.define("space.genesis", function(C)
    local M = { version = "0.2.0" }
    local U = C.get("space.universe")
    local Course = C.get("space.course")
    local Lineage = C.get("engineering.lineage")
    local Fx = C.get("engineering.fixtures")
    local Names = C.get("paddock.names")
    local Attr = C.get("paddock.attributes")
    local Seed = C.get("world.seed")
    local Comp = C.get("npc.competency")

    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function scale(a, k) return { a[1] * k, a[2] * k, a[3] * k } end

    -- ------------------------------------------------------------------------------------------ orbits
    --- A circular orbit whose plane passes over an anchor city: phase 0 is directly above it, inclination tilts the
    --- along-track direction from east toward north. orbit = { radiusM, inclinationRad, phase0, anchor }.
    function M.orbitAt(orbit, t)
        local f = U.anchorFrame(orbit.anchor or "los_santos")
        local e1 = f.up
        local i = orbit.inclinationRad or 0
        local e2 = add(scale(f.east, math.cos(i)), scale(f.north, math.sin(i)))
        local r = orbit.radiusM
        local n = math.sqrt(U.G * U.BODIES.earth.mass / (r * r * r))
        local th = (orbit.phase0 or 0) + n * (t or 0)
        local pos = add(scale(e1, r * math.cos(th)), scale(e2, r * math.sin(th)))
        local vel = add(scale(e1, -r * n * math.sin(th)), scale(e2, r * n * math.cos(th)))
        return pos, vel, 2 * math.pi / n
    end

    -- ------------------------------------------------------------------------------------------ technology
    -- The root families a seed can plant, and the world each is most at home in.
    local ROOTS = {
        { key = "fan", design = "lift_fan_12k", homes = { "los_santos", "night_city" } },
        { key = "ram", design = "ground_ram_30kj", homes = { "night_city", "los_santos" } },
        { key = "rcs", design = "rcs_n2_400", homes = { "snowglobe", "los_santos" } },
        { key = "engine", design = "main_hydrazine_30k", homes = { "snowglobe", "night_city" } },
    }
    local DOMAINS = { "night_city", "los_santos", "snowglobe" }

    local function history(node, steps)
        local reg = Lineage.newRegistry()
        local s = node:stream("roots")
        local roots = {}
        for _, r in ipairs(ROOTS) do
            -- some seeds never discover a family at all
            if s() < 0.85 then
                local origin = r.homes[s:int(1, #r.homes)]
                roots[r.key] = reg:newLineage(Fx.DESIGNS[r.design], origin, "seed:" .. origin, { at = 0 }).id
            end
        end
        -- a seeded sequence of reverse-engineering attempts, each keyed by its own step node
        local log = {}
        for k = 1, steps do
            local ks = node:child("step", k):stream()
            local ids = reg.order
            local src = ids[ks:int(1, #ids)]
            local to = DOMAINS[ks:int(1, #DOMAINS)]
            if reg:get(src).origin ~= to then
                local know = ks:pick({ "rumour", "observed", "observed", "measured", "specimen", "documents" })
                local rec, why = reg:reverseEngineer(src, { knowledge = know, competency = ks:int(150, 950), rng = ks,
                    origin = to, principal = "seed:" .. to, intent = ks:pick({ "reconstruct", "derive", "adapt" }), at = k })
                log[#log + 1] = { step = k, source = src, to = to, knowledge = know, result = rec and rec.id or nil,
                    failed = why and why.reason or nil }
            end
        end
        return reg, roots, log
    end

    --- The best design of a perf kind an organisation can build from its domain's records (by its benefit field).
    local function best(reg, domain, kind, field)
        local pick
        for _, id in ipairs(reg.order) do
            local r = reg:get(id)
            if r.origin == domain and r.design.perf.kind == kind then
                if not pick or (r.design.perf[field] or 0) > (pick.design.perf[field] or 0) then pick = r end
            end
        end
        return pick
    end

    -- ------------------------------------------------------------------------------------------ machines
    local function rcsPairs(design, count)
        -- opposed pairs at the four extremities, in an order that gives full control only with all eight pairs
        local P = {
            { { 0, 2.2, 0.55 }, { 1, 0, 0 } }, { { 0, -2.2, 0.55 }, { 1, 0, 0 } },
            { { 0, 2.2, 0.55 }, { 0, 0, 1 } }, { { 0, -2.2, 0.55 }, { 0, 0, 1 } },
            { { -0.95, 0, 0.55 }, { 0, 1, 0 } }, { { 0.95, 0, 0.55 }, { 0, 1, 0 } },
            { { -0.95, 0, 0.55 }, { 0, 0, 1 } }, { { 0.95, 0, 0.55 }, { 0, 0, 1 } },
        }
        local parts = {}
        for i = 1, math.min(count, #P) do
            local pos, dir = P[i][1], P[i][2]
            parts[#parts + 1] = { key = "rcs" .. i .. "p", body = design, pos = pos, dir = dir }
            parts[#parts + 1] = { key = "rcs" .. i .. "n", body = design, pos = pos, dir = scale(dir, -1) }
        end
        return parts
    end

    local function buildMachine(node, reg, domain)
        local s = node:stream("machine")
        local chassis = { massKg = s:int(1100, 1700), com = { 0, 0, 0.5 }, bounds = { 1.9, 4.5, 1.35 },
                          ratedLoadN = s:int(40, 90) * 1000, wheels = true }
        local parts, used = {}, {}
        local engine = best(reg, domain, "reaction_engine", "thrustN")
        local rcs, fan, ram
        -- a big engine and a small one are both reaction engines: the biggest is the main, the best small is RCS
        for _, id in ipairs(reg.order) do
            local r = reg:get(id)
            if r.origin == domain and r.design.perf.kind == "reaction_engine" and r.design.perf.thrustN < 5000 then
                if not rcs or r.design.perf.ispS > rcs.design.perf.ispS then rcs = r end
            end
        end
        if engine and engine.design.perf.thrustN < 5000 then engine = nil end
        fan = best(reg, domain, "propeller", "thrustN")
        ram = best(reg, domain, "ground_ram", "energyJ")
        if engine then
            parts[#parts + 1] = { key = "main", body = engine.design, pos = { 0, 0, 0.05 }, dir = { 0, 0, 1 } }
            parts[#parts + 1] = { key = "tank_main", body = Seed.deepCopy(Fx.DESIGNS.tank_hydrazine_400), pos = { 0, -0.2, 0.6 } }
            parts[#parts].body.perf.capacityKg = s:int(150, 450)
            parts[#parts].body.perf.propellant = engine.design.perf.propellant
            used[#used + 1] = engine.id
        end
        if rcs then
            for _, p in ipairs(rcsPairs(rcs.design, s:int(2, 8))) do parts[#parts + 1] = p end
            parts[#parts + 1] = { key = "tank_rcs", body = Fx.DESIGNS.tank_n2_30, pos = { 0, 0.2, 0.6 } }
            used[#used + 1] = rcs.id
        end
        if fan then
            parts[#parts + 1] = { key = "fan_f", body = fan.design, pos = { 0, 1.5, 0.5 } }
            parts[#parts + 1] = { key = "fan_r", body = fan.design, pos = { 0, -1.5, 0.5 } }
            used[#used + 1] = fan.id
        end
        if ram then
            parts[#parts + 1] = { key = "ram", body = ram.design, pos = { 0, 0, 0 }, dir = { 0, 0, 1 } }
            used[#used + 1] = ram.id
        end
        parts[#parts + 1] = { key = "battery", body = Fx.DESIGNS.battery_100mj, pos = { 0, 0.9, 0.2 } }
        if s() < 0.7 then parts[#parts + 1] = { key = "radiator", body = Fx.DESIGNS.radiator_panel_40, pos = { 0, -1.8, 1.3 } } end
        return { id = node:tag("machine"), origin = domain, chassis = chassis, parts = parts, designs = used }
    end

    --- L322: a machine BUILT FOR a discipline from the same history -- a sprint build is all thrust for seconds, a
    --- Fireball build carries propellant, attitude control and cooling for minutes. Drawn from its own seed node, so
    --- the general machine above is unchanged. Returns nil when the history gave this world nothing that can do it.
    local function buildFor(node, reg, domain, purpose)
        local s = node:stream("machine", purpose)
        local engine = best(reg, domain, "reaction_engine", "thrustN")
        if engine and engine.design.perf.thrustN < 5000 then engine = nil end
        local fan = best(reg, domain, "propeller", "thrustN")
        local rcs
        for _, id in ipairs(reg.order) do
            local r = reg:get(id)
            if r.origin == domain and r.design.perf.kind == "reaction_engine" and r.design.perf.thrustN < 5000 then
                if not rcs or r.design.perf.ispS > rcs.design.perf.ispS then rcs = r end
            end
        end
        local chassis = { massKg = s:int(1000, 1400), com = { 0, 0, 0.5 }, bounds = { 1.9, 4.5, 1.35 },
                          ratedLoadN = s:int(120, 200) * 1000, wheels = true }
        local parts, used = {}, {}
        local function tank(key, kg, pos, prop)
            local b = Seed.deepCopy(Fx.DESIGNS.tank_hydrazine_400)
            b.perf.capacityKg, b.perf.propellant = kg, prop
            parts[#parts + 1] = { key = key, body = b, pos = pos }
        end
        if purpose == "sprint" then
            if engine then
                -- two mains side by side, symmetric about the CoM: thrust without torque
                parts[#parts + 1] = { key = "main_l", body = engine.design, pos = { -0.4, 0, 0.05 }, dir = { 0, 0, 1 } }
                parts[#parts + 1] = { key = "main_r", body = engine.design, pos = { 0.4, 0, 0.05 }, dir = { 0, 0, 1 } }
                tank("tank", s:int(150, 350), { 0, 0, 0.6 }, engine.design.perf.propellant)
                used[#used + 1] = engine.id
            elseif fan then
                for k, y in ipairs({ 1.6, 0.55, -0.55, -1.6 }) do
                    parts[#parts + 1] = { key = "fan" .. k, body = fan.design, pos = { 0, y, 0.5 } }
                end
                used[#used + 1] = fan.id
            else
                return nil
            end
            parts[#parts + 1] = { key = "radiator", body = Fx.DESIGNS.radiator_panel_40, pos = { 0, -1.8, 1.3 } }
        elseif purpose == "fireball" then
            if not engine then return nil end
            parts[#parts + 1] = { key = "main", body = engine.design, pos = { 0, 0, 0.05 }, dir = { 0, 0, 1 } }
            local kg = s:int(350, 700)
            tank("tank_a", kg, { 0, -0.7, 0.65 }, engine.design.perf.propellant)
            tank("tank_b", kg, { 0, 0.7, 0.65 }, engine.design.perf.propellant)
            used[#used + 1] = engine.id
            if rcs then
                for _, p in ipairs(rcsPairs(rcs.design, s:int(4, 8))) do parts[#parts + 1] = p end
                parts[#parts + 1] = { key = "tank_rcs", body = Fx.DESIGNS.tank_n2_60, pos = { 0, 0, 1.0 } }
                used[#used + 1] = rcs.id
            end
            for k = 1, s:int(1, 3) do
                parts[#parts + 1] = { key = "rad" .. k, body = Fx.DESIGNS.radiator_panel_40, pos = { (k - 2) * 0.9, 0, 1.3 } }
            end
        end
        parts[#parts + 1] = { key = "battery", body = Fx.DESIGNS.battery_100mj, pos = { 0, 0, 0.2 } }
        return { id = node:tag("machine", purpose), origin = domain, chassis = chassis, parts = parts, designs = used, purpose = purpose }
    end

    --- L322 venues for the Snowglobe disciplines (parameters only; `space.calendar` turns them into events).
    local function disciplineVenues(node, world, R, opts)
        local v = world.venues
        local spot = opts.sprintSpot or { -1336.0, -3044.0, 13.9 }      -- LSIA: open tarmac at the airport
        v[#v + 1] = { id = node:child("sprint", "lsia"):tag("venue"), kind = "sprint", style = "vertical", anchor = "los_santos",
            spot = spot, distanceM = 1000, lanes = 6, gravity = "flat", name = "LSIA Sky Sprint", domain = "los_santos" }
        local fb = node:child("fireball", "earth")
        v[#v + 1] = { id = fb:tag("venue"), kind = "fireball", centre = "earth", anchor = "los_santos",
            inner = R + 2600, outer = R + 6000, gridAltM = 3800, distanceM = 60000,
            name = "Earth Fireball", domain = "snowglobe" }
        for i, st in ipairs(world.stations) do
            local sn = node:child("station", i)
            v[#v + 1] = { id = sn:tag("venue", "sprint"), kind = "sprint", style = "orbital", stationId = st.id,
                distanceM = 2000, lanes = 6, gravity = "radial", name = st.name .. " Sprint", domain = "snowglobe" }
            v[#v + 1] = { id = sn:tag("venue", "fireball"), kind = "fireball", centre = "station", stationId = st.id,
                inner = 150, outer = 900, gridAltM = 400, distanceM = 20000, name = st.name .. " Fireball", domain = "snowglobe" }
        end
        -- L323: the Night City Sky Sprint -- open Badlands desert; the OPEN//77 host snaps the start plane to the ground.
        -- Appended last so every earlier venue keeps its number.
        local nc = opts.ncSprintSpot or { -2400.0, -4300.0, 75.0 }
        v[#v + 1] = { id = node:child("sprint", "badlands"):tag("venue"), kind = "sprint", style = "vertical", anchor = "night_city",
            spot = nc, distanceM = 1000, lanes = 6, gravity = "flat", name = "Badlands Sky Sprint", domain = "night_city" }
    end

    -- ------------------------------------------------------------------------------------------ the world
    --- Generate Snowglobe's base state from a seed node (e.g. `Seed.root(u):child("snowglobe")`).
    --- opts = { stations = n, orgs = n, historySteps = n }.
    function M.generate(node, opts)
        opts = opts or {}
        local R = U.BODIES.earth.radius
        local s = node:stream("shape")
        local world = { node = node:id(), earthRadiusM = R, stations = {}, venues = {}, orgs = {}, pilots = {}, machines = {}, fleet = {} }

        -- stations: orbits a seeded fraction of an Earth radius up, over Los Santos or Night City
        local nStations = opts.stations or s:int(1, 3)
        for i = 1, nStations do
            local sn = node:child("station", i)
            local ss = sn:stream()
            local alt = R * (0.55 + 0.35 * ss())      -- above the GTA doorway on a 5 km Earth; thin air
            world.stations[i] = {
                id = sn:tag("station"), name = Names.companyName(sn:id(), i, "industrial"),
                orbit = { radiusM = R + alt, inclinationRad = (ss() - 0.5) * 0.6, phase0 = ss() * 2 * math.pi,
                          anchor = ss:pick({ "los_santos", "night_city" }) },
                altitudeM = alt,
            }
            world.venues[#world.venues + 1] = { id = sn:tag("venue"), kind = "station_ring", stationId = world.stations[i].id,
                name = world.stations[i].name .. " Ring", course = Course.ring(sn:child("ring")), domain = "snowglobe" }
        end
        -- a sky ring over each city at 350-650 m: thick enough air for fans and wings to race in, reachable without orbit
        for _, city in ipairs({ "los_santos", "night_city" }) do
            local cn = node:child("sky", city)
            world.venues[#world.venues + 1] = { id = cn:tag("venue"), kind = "sky_ring", anchor = city,
                altitudeM = math.floor(350 + 300 * cn:unit("alt")), name = (city == "los_santos" and "Vinewood" or "Pacifica") .. " Sky Ring",
                course = Course.ring(cn:child("ring"), { radiusM = 200 + 200 * cn:unit("r") }), domain = city }
        end

        -- the anomaly: small, dark, moving, deterministic -- an orbit nobody has to be told about
        local an = node:child("anomaly")
        world.anomaly = { id = an:tag("anomaly"),
            orbit = { radiusM = R * (2.2 + 1.5 * an:unit("r")), inclinationRad = (an:unit("i") - 0.5) * 2.4,
                      phase0 = an:unit("p") * 2 * math.pi, anchor = "los_santos" },
            radiusM = 8 + 10 * an:unit("size") }

        -- technology history, then organisations that build from it
        local reg, roots, log = history(node:child("history"), opts.historySteps or 24)
        world.lineage, world.roots, world.historyLog = reg, roots, log

        disciplineVenues(node, world, R, opts)

        local nOrgs = opts.orgs or s:int(8, 12)
        local takenTeams, takenPeople = {}, {}
        for i = 1, nOrgs do
            local on = node:child("org", i)
            local ost = on:stream()
            local domain = ost:pick(DOMAINS)
            local name, short = Names.teamName(on:id(), "regional", i, takenTeams)
            local org = { id = on:tag("org"), name = name, short = short, origin = domain }
            world.orgs[i] = org
            local person = Names.person(on:id(), "driver", 1, { taken = takenPeople })
            local attrs = Attr.rollDriver(on:child("pilot"):stream(), "regional", ost:int(20, 38))
            local pid = on:tag("pilot")
            -- an NCM driver like any Paddock person (L322): attrs, FTB2 personality, and per-domain competency. A pilot
            -- who grew up in Snowglobe starts with native skill there; everyone else starts as a terrestrial driver.
            local pilot = { id = pid, name = person.display, display = person.display, orgId = org.id, attrs = attrs,
                personality = Attr.personality(node:id(), pid), origin = domain }
            local native = domain == "snowglobe" and (30 + 25 * on:unit("native")) or nil
            Comp.enter(pilot, "snowglobe", { native = native })
            world.pilots[i] = pilot
            local m = buildMachine(on, reg, domain)
            m.orgId = org.id
            world.machines[i] = m
            world.fleet[i] = { general = m, sprint = buildFor(on, reg, domain, "sprint"), fireball = buildFor(on, reg, domain, "fireball") }
            for _, k in ipairs({ "sprint", "fireball" }) do if world.fleet[i][k] then world.fleet[i][k].orgId = org.id end end
        end
        return world
    end

    --- The anomaly's position at time t, and whether a pilot at `pos` is within `rangeM` of it.
    function M.anomalyAt(anomaly, t, pos, rangeM)
        local p = M.orbitAt(anomaly.orbit, t)
        if not pos then return p end
        local d = math.sqrt((p[1] - pos[1]) ^ 2 + (p[2] - pos[2]) ^ 2 + (p[3] - pos[3]) ^ 2)
        return p, d <= (rangeM or 200), d
    end

    return M
end)
