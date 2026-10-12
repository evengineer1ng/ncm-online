-- ncm-core module: engineering.machine
--
-- Assemble a machine and understand it from its physical components (L321; doc 54 §D, North Star):
--   What does it weigh? Where is its centre of mass? What produces force, where is that force applied, and in which
--   direction? What does that do to rotation? What stores energy, what carries propellant, what makes heat and what
--   removes it? What can it therefore do -- hop, fly in air, maneuver in vacuum -- for how long? What fails first?
--
-- Machine frame: x right, y forward, z up, metres, origin at the chassis reference point (GTA and REDengine agree).
--
--   design = {
--     chassis = { massKg, com = {x,y,z}, bounds = {x,y,z}, ratedLoadN?, wheels = true|false },
--     parts   = { { key, body = <engineering.body design>, pos = {x,y,z}, dir = {x,y,z}? }, ... },
--   }
--
-- A part's force loads (`body.loads` with kind "thrust") are applied at `pos + load.pos`, along `dir` (the
-- placement's, else the load's own). Its perf block (`engineering.systems`) says what kind of push it is. So the same
-- thruster mounted differently is a different machine, and four thrusters in poor places do NOT give six-axis control
-- -- the wrench table says exactly which axes they can and cannot command.
local Core = NcmCore

Core.define("engineering.machine", function(C)
    local M = { version = "0.1.0" }
    local Sys = C.get("engineering.systems")

    -- ------------------------------------------------------------------------------------------ vectors
    local function v3(t) return { t[1] or t.x or 0, t[2] or t.y or 0, t[3] or t.z or 0 } end
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function scale(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function unit(a) local l = len(a); return l > 0 and scale(a, 1 / l) or { 0, 0, 0 } end
    M.vec = { add = add, sub = sub, scale = scale, dot = dot, cross = cross, len = len, unit = unit }

    M.AXES = { "x", "y", "z" }
    M.CP = 900            -- J/(kg K): an aluminium-and-steel average heat capacity for the whole machine
    M.TEMP_LIMIT_K = 120  -- allowed rise above ambient before thermal failure

    local PUSHING = { reaction_engine = true, jet = true, propeller = true, ground_ram = true, pulse_reaction = true }

    --- Assemble. Returns the machine model (pure data; no state).
    function M.assemble(design)
        local ch = design.chassis or {}
        local m = {
            parts = {}, devices = {}, tanks = {}, stores = {}, radiators = {}, sources = {}, surfaces = {}, attitude = {},
            dryMassKg = 0, propellantKg = {}, energyJ = 0, losses = {},
        }
        -- L360 addendum: a part on a CENTRED hardpoint (`part.centred`, the floor pan) sits directly under the balance
        -- point of everything else -- tanks at their fill included -- so its own mass never moves that point sideways
        -- and a thrust along the vertical through it makes no torque.
        do
            local cm, cmm = ch.massKg or 0, scale(v3(ch.com or {}), ch.massKg or 0)
            local any = false
            for _, part in ipairs(design.parts or {}) do
                if part.centred then any = true else
                    local b = part.body or {}
                    local perf = b.perf or {}
                    local w = b.massKg or 0
                    if perf.kind == "propellant_tank" then w = w + (perf.capacityKg or 0) * (perf.fill == nil and 1 or perf.fill) end
                    cm, cmm = cm + w, add(cmm, scale(add(v3(part.pos or {}), v3(b.com or {})), w))
                end
            end
            if any and cm > 0 then
                local c = scale(cmm, 1 / cm)
                for _, part in ipairs(design.parts or {}) do
                    if part.centred then
                        local p = v3(part.pos or {})
                        part.pos = { c[1], c[2], p[3] }
                    end
                end
            end
        end
        -- mass and centre of mass (dry), with propellant at its tank
        local mass, moment = (ch.massKg or 0), scale(v3(ch.com or {}), ch.massKg or 0)
        local points = { { m = ch.massKg or 0, p = v3(ch.com or {}), box = ch.bounds and v3(ch.bounds) or nil } }
        for _, part in ipairs(design.parts or {}) do
            local b = part.body or {}
            local perf = b.perf or {}
            local ok, errs = Sys.validate(perf)
            if not ok then m.losses[#m.losses + 1] = (part.key or b.id or "?") .. ": " .. table.concat(errs, "; ") end
            local p = add(v3(part.pos or {}), v3(b.com or {}))
            local bm = b.massKg or 0
            mass, moment = mass + bm, add(moment, scale(p, bm))
            points[#points + 1] = { m = bm, p = p }
            m.parts[#m.parts + 1] = { key = part.key or b.id, body = b, pos = v3(part.pos or {}), kind = perf.kind }
            if perf.kind == "propellant_tank" then
                local kg = (perf.capacityKg or 0) * (perf.fill == nil and 1 or perf.fill)
                m.tanks[#m.tanks + 1] = { key = part.key, propellant = perf.propellant, capacityKg = perf.capacityKg or 0, kg = kg, pos = p }
                m.propellantKg[perf.propellant] = (m.propellantKg[perf.propellant] or 0) + kg
            elseif perf.kind == "energy_store" then
                m.stores[#m.stores + 1] = { key = part.key, capacityJ = perf.capacityJ, maxPowerW = perf.maxPowerW }
                m.energyJ = m.energyJ + (perf.capacityJ or 0)
            elseif perf.kind == "radiator" then
                m.radiators[#m.radiators + 1] = perf
            elseif perf.kind == "power_source" then
                m.sources[#m.sources + 1] = perf
            elseif perf.kind == "attitude_control" then
                -- L331: torque about every axis, no net force (`engineering.dynamics`)
                m.attitude[#m.attitude + 1] = { key = part.key or b.id, perf = perf, pos = p, thermal = part.thermal }
            elseif perf.kind == "aero_surface" then
                m.surfaces[#m.surfaces + 1] = { key = part.key, perf = perf, pos = p }
            elseif perf.kind == "pressure_cabin" then
                m.cabin = { key = part.key, crew = perf.crew, volumeM3 = perf.volumeM3, leakPerS = perf.leakPerS or 0 }
            elseif perf.kind == "life_support" then
                m.o2Kg = (m.o2Kg or 0) + (perf.o2Kg or 0)
            end
            if PUSHING[perf.kind] then
                -- every thrust load is a device: application point and direction in the machine frame
                local loads = b.loads or {}
                if #loads == 0 then loads = { { kind = "thrust", pos = { 0, 0, 0 }, dir = { 0, 0, 1 } } } end
                for _, l in ipairs(loads) do
                    if l.kind == "thrust" or perf.kind == "ground_ram" then
                        m.devices[#m.devices + 1] = {
                            key = part.key or b.id, kind = perf.kind, perf = perf, push = Sys.pushMechanism(perf.kind),
                            thermal = part.thermal, componentId = part.componentId,   -- L331: per-device heat (installed parts)
                            at = add(v3(part.pos or {}), v3(l.pos or {})),
                            dir = unit(part.dir and v3(part.dir) or v3(l.dir or { 0, 0, 1 })),
                        }
                    end
                end
            end
        end
        -- propellant carried counts toward the wet mass (at the tanks)
        for _, t in ipairs(m.tanks) do
            mass, moment = mass + t.kg, add(moment, scale(t.pos, t.kg))
            points[#points + 1] = { m = t.kg, p = t.pos }
        end
        m.dryMassKg = mass - (function() local s = 0; for _, t in ipairs(m.tanks) do s = s + t.kg end; return s end)()
        m.wetMassKg = mass
        m.com = mass > 0 and scale(moment, 1 / mass) or { 0, 0, 0 }
        -- inertia about the CoM: point masses, plus the chassis as a box
        local I = { 0, 0, 0 }
        for _, pt in ipairs(points) do
            local r = sub(pt.p, m.com)
            I[1] = I[1] + pt.m * (r[2] ^ 2 + r[3] ^ 2)
            I[2] = I[2] + pt.m * (r[1] ^ 2 + r[3] ^ 2)
            I[3] = I[3] + pt.m * (r[1] ^ 2 + r[2] ^ 2)
            if pt.box then
                local a, b2, c = pt.box[1], pt.box[2], pt.box[3]
                I[1] = I[1] + pt.m * (b2 * b2 + c * c) / 12
                I[2] = I[2] + pt.m * (a * a + c * c) / 12
                I[3] = I[3] + pt.m * (a * a + b2 * b2) / 12
            end
        end
        m.inertia = I
        m.chassis = { wheels = ch.wheels ~= false, ratedLoadN = ch.ratedLoadN, boundsZ = ch.bounds and ch.bounds[3] or 1.4 }
        -- the skin the air heats and the machine radiates through (`engineering.flightbody.skin`); absent = not modelled
        m.skin = ch.skin
        -- structure: the chassis rating plus any structure bodies
        local rated = ch.ratedLoadN or 0
        for _, part in ipairs(m.parts) do
            if part.kind == "structure" then rated = rated + (part.body.perf.ratedLoadN or 0) end
        end
        m.ratedLoadN = rated > 0 and rated or nil
        -- the wrench table: each device's force and torque about the CoM at full output (vacuum and sea level)
        m.wrench = {}
        for i, d in ipairs(m.devices) do
            local full = (d.kind == "ground_ram" or d.kind == "pulse_reaction") and (d.perf.forceN or 0) or (d.perf.thrustN or 0)
            local F = scale(d.dir, full)
            m.wrench[i] = { key = d.key, kind = d.kind, F = F, tau = cross(sub(d.at, m.com), F) }
        end
        return m
    end

    --- Per-axis authority from the wrench table: how much force (N) / torque (N m) the machine can command in each
    --- direction of each axis with the devices it has, each pushing only along its own direction (throttle 0..1).
    --- `kinds` limits it to some push mechanisms (e.g. { reaction = true } for vacuum).
    function M.authority(m, pushes)
        local out = { force = { pos = { 0, 0, 0 }, neg = { 0, 0, 0 } }, torque = { pos = { 0, 0, 0 }, neg = { 0, 0, 0 } } }
        for i, w in ipairs(m.wrench) do
            local d = m.devices[i]
            if not pushes or pushes[d.push] then
                for a = 1, 3 do
                    if w.F[a] > 0 then out.force.pos[a] = out.force.pos[a] + w.F[a] else out.force.neg[a] = out.force.neg[a] - w.F[a] end
                    if w.tau[a] > 0 then out.torque.pos[a] = out.torque.pos[a] + w.tau[a] else out.torque.neg[a] = out.torque.neg[a] - w.tau[a] end
                end
            end
        end
        -- L331: an attitude set turns the machine either way about every axis
        if not pushes or pushes.reaction then
            for _, at in ipairs(m.attitude or {}) do
                local t = at.perf.torqueNm or 0
                for a = 1, 3 do out.torque.pos[a] = out.torque.pos[a] + t; out.torque.neg[a] = out.torque.neg[a] + t end
            end
        end
        local axes, controlled = {}, 0
        local names = { "translate x", "translate y", "translate z", "pitch (about x)", "roll (about y)", "yaw (about z)" }
        for a = 1, 3 do
            local t = out.force.pos[a] > 1e-6 and out.force.neg[a] > 1e-6
            local r = out.torque.pos[a] > 1e-6 and out.torque.neg[a] > 1e-6
            axes[#axes + 1] = { axis = names[a], both = t, pos = out.force.pos[a], neg = out.force.neg[a] }
            if t then controlled = controlled + 1 end
            axes[#axes + 1] = { axis = names[a + 3], both = r, pos = out.torque.pos[a], neg = out.torque.neg[a] }
            if r then controlled = controlled + 1 end
        end
        out.axes, out.controlledAxes = axes, controlled
        return out
    end

    local function sumPushing(m, rho, pushes)
        local F = { 0, 0, 0 }
        for _, d in ipairs(m.devices) do
            if d.kind ~= "ground_ram" and (not pushes or pushes[d.push]) then
                F = add(F, scale(d.dir, Sys.thrustAt(d.perf, rho, 1)))
            end
        end
        return F
    end

    --- What the assembled machine can do, and what limits it. `env` = { g = 9.81, rho = 1.225 }.
    function M.capability(m, env)
        env = env or {}
        local g = env.g or 9.81
        local rhoSea = env.rho or Sys.RHO0
        local weight = m.wetMassKg * g
        local cap = { massKg = m.wetMassKg, dryMassKg = m.dryMassKg, consequences = {} }
        -- ground reaction: the hop
        local ramE = 0
        for _, d in ipairs(m.devices) do
            if d.kind == "ground_ram" then ramE = ramE + math.min(d.perf.energyJ or 0, (d.perf.forceN or 0) * (d.perf.strokeM or 0)) end
        end
        cap.hopHeightM = ramE > 0 and ramE / weight or 0
        -- thrust-to-weight at sea level (all air + reaction) and in vacuum (reaction only), along +z
        cap.twrSea = sumPushing(m, rhoSea)[3] / weight
        cap.twrVacuum = sumPushing(m, 0, { reaction = true })[3] / weight
        cap.atmosphericFlight = sumPushing(m, rhoSea, { atmospheric = true })[3] > weight
        cap.vacuumManeuver = cap.twrVacuum > 0 or M.authority(m, { reaction = true }).controlledAxes > 0
        -- propellant: delta-v (Tsiolkovsky, flow-weighted Isp) and burn time at full thrust
        local flow, thrust = 0, 0
        for _, d in ipairs(m.devices) do
            if d.kind == "reaction_engine" then
                flow, thrust = flow + Sys.massFlow(d.perf), thrust + (d.perf.thrustN or 0)
            end
        end
        local prop = 0
        for _, t in ipairs(m.tanks) do prop = prop + t.kg end   -- fixed order: deterministic sums
        if flow > 0 and prop > 0 then
            local ispEff = thrust / (flow * Sys.G0)
            cap.deltaVms = ispEff * Sys.G0 * math.log(m.wetMassKg / math.max(1e-6, m.wetMassKg - prop))
            cap.burnTimeS = prop / flow
        else
            cap.deltaVms, cap.burnTimeS = 0, 0
        end
        -- heat: generation at full output against rejection at sea level and in vacuum
        local heat = 0
        for _, d in ipairs(m.devices) do heat = heat + (d.perf.heatKw or 0) end
        for _, s in ipairs(m.sources) do heat = heat + (s.heatKw or 0) end
        local rejSea, rejVac = 0, 0
        for _, r in ipairs(m.radiators) do rejSea, rejVac = rejSea + Sys.rejectionKw(r, rhoSea), rejVac + Sys.rejectionKw(r, 0) end
        cap.heatKw, cap.rejectionSeaKw, cap.rejectionVacuumKw = heat, rejSea, rejVac
        local capacity = m.dryMassKg * M.CP * M.TEMP_LIMIT_K / 1000   -- kJ to the thermal limit
        cap.thermalLimitVacuumS = heat > rejVac and capacity / (heat - rejVac) or math.huge
        -- attitude in vacuum
        local auth = M.authority(m, { reaction = true })
        cap.vacuumAxes = auth.controlledAxes
        -- what fails first, as named consequences (L314 R1) -- never a refusal
        local maxF = 0
        for _, w in ipairs(m.wrench) do maxF = maxF + len(w.F) end
        if m.ratedLoadN and maxF > m.ratedLoadN then
            cap.consequences[#cap.consequences + 1] = ("structure: full output %.0f N exceeds the rated load %.0f N -- damage before performance"):format(maxF, m.ratedLoadN)
        end
        if cap.thermalLimitVacuumS < math.huge then
            cap.consequences[#cap.consequences + 1] = ("heat: %.0f kW against %.0f kW of vacuum rejection -- thermal limit after %.0f s at full output"):format(heat, rejVac, cap.thermalLimitVacuumS)
        end
        if cap.burnTimeS > 0 then
            cap.consequences[#cap.consequences + 1] = ("propellant: %.0f s of full thrust, %.0f m/s of delta-v"):format(cap.burnTimeS, cap.deltaVms)
        end
        if cap.twrVacuum > 0 and auth.controlledAxes < 6 then
            cap.consequences[#cap.consequences + 1] = ("attitude: reaction devices command only %d of 6 axes"):format(auth.controlledAxes)
        end
        if cap.hopHeightM > 0 and cap.twrVacuum == 0 and not cap.atmosphericFlight then
            cap.consequences[#cap.consequences + 1] = ("ground reaction only: a %.2f m hop, nothing to push against once airborne"):format(cap.hopHeightM)
        end
        -- first failure, by the soonest time limit
        local first, t = nil, math.huge
        if cap.burnTimeS > 0 and cap.burnTimeS < t then first, t = "propellant", cap.burnTimeS end
        if cap.thermalLimitVacuumS < t then first, t = "heat", cap.thermalLimitVacuumS end
        if m.ratedLoadN and maxF > m.ratedLoadN then first, t = "structure", 0 end
        cap.firstFailure, cap.firstFailureS = first, t
        return cap
    end

    return M
end)
