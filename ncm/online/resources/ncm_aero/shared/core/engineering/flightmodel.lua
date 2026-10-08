-- ncm-core module: engineering.flightmodel
--
-- L331 (owner, "NCM Deep on the full machine model"): ONE canonical machine whose consequential forces change with the
-- environment -- never a `spaceMode` flag. A Machine's Foundry install (`engineering.installation.resolve`) plus its
-- chassis plus its own tank becomes an `engineering.machine` model (mass, centre of mass, inertia, the wrench table),
-- stepped by `engineering.dynamics` (6-DOF: off-centre thrust spins it, thrust and drag scale with the air, parts heat
-- up and shut down) in the `space.deep` Earth frame. Air thins with altitude (exponential atmosphere); gravity is the
-- real field. Deep in Cyberpunk, Deep in Assetto Corsa and the server's unhosted flight all step THIS.
--
-- What is NOT physical, and says so: the DEVELOPMENT attitude waiver (`env.attitudeWaiver` / `attitudeRig`) turns the
-- body directly for a Machine that has no attitude part yet (owner ruling: dev only; production is fully physical).
local Core = NcmCore

Core.define("engineering.flightmodel", function(C)
    local M = { version = "0.1.0" }
    local Mach = C.get("engineering.machine")
    local Dyn = C.get("engineering.dynamics")
    local D = C.get("space.deep")
    local V = D.vec

    -- Chassis by vehicle key: mass, centre of mass, bounds (for inertia) and body drag. The Hella is the one flown today;
    -- others fall back to its class until they are measured.
    M.CHASSIS = {
        archer_hella = { massKg = 1800, com = { 0, 0, 0.5 }, bounds = { 1.9, 4.6, 1.4 }, cd = 0.32, areaM2 = 2.2 },
        default = { massKg = 1700, com = { 0, 0, 0.5 }, bounds = { 1.9, 4.6, 1.4 }, cd = 0.33, areaM2 = 2.2 },
    }
    M.TANK_POS = { 0, -1.4, 0.4 }          -- behind the rear axle
    M.SCALE_HEIGHT_M = 8500                -- Earth's atmosphere (the same law as space.universe)
    M.RHO0 = 1.225

    --- Air density at an altitude (kg/m^3): full at sea level, nothing worth counting above ~255 km.
    function M.density(alt)
        if alt <= 0 then return M.RHO0 end
        if alt > 30 * M.SCALE_HEIGHT_M then return 0 end
        return M.RHO0 * math.exp(-alt / M.SCALE_HEIGHT_M)
    end

    --- The machine model from a Foundry install. `devices` = resolved installation devices ({ componentId, kind, perf,
    --- thermal, massKg, pos, axis }); opts = { vehicleKey, fuelKg, tankKg, body }. `body` = an `engineering.flightbody`
    --- (the Machine's own mass, bounds, drag, lift and skin, from its passport); without it, `CHASSIS` by key as before.
    --- Returns the `engineering.machine` model.
    function M.build(devices, opts)
        opts = opts or {}
        local ch = opts.body or M.CHASSIS[opts.vehicleKey or ""] or M.CHASSIS.default
        local parts = {
            { key = "body", body = { massKg = 0, perf = { kind = "aero_surface", areaM2 = ch.areaM2, cd = ch.cd, cl = ch.cl or 0 } }, pos = ch.com },
        }
        local fuel = math.max(0, tonumber(opts.fuelKg) or 0)
        local cap = math.max(fuel, tonumber(opts.tankKg) or fuel)
        if cap > 0 then
            parts[#parts + 1] = { key = "tank", body = { massKg = 0, perf = { kind = "propellant_tank", capacityKg = cap,
                propellant = "fuel", fill = cap > 0 and fuel / cap or 0 } }, pos = M.TANK_POS }
        end
        for _, d in ipairs(devices or {}) do
            local perf = {}
            for k, v in pairs(d.perf or {}) do perf[k] = v end
            perf.kind = perf.kind or d.kind
            -- every part on a Machine burns the Machine's own fuel unless its design names another propellant
            if (perf.kind == "reaction_engine" or perf.kind == "pulse_reaction" or perf.kind == "attitude_control") and not perf.propellant then
                perf.propellant = "fuel"
            end
            -- L334: a tank PART carries its own propellant, as the server last recorded it (full when unknown)
            if perf.kind == "propellant_tank" then
                local cap = math.max(1e-9, tonumber(perf.capacityKg) or 0)
                perf.fill = d.fillKg and math.max(0, math.min(1, d.fillKg / cap)) or 1
            end
            parts[#parts + 1] = {
                key = d.componentId or d.code, componentId = d.componentId, thermal = d.thermal,
                body = { massKg = d.massKg or 0, perf = perf, loads = { { kind = "thrust", pos = { 0, 0, 0 }, dir = d.axis or { 0, 1, 0 } } } },
                pos = d.pos or { 0, 0, 0.5 }, dir = d.axis,
            }
        end
        local m = Mach.assemble({
            chassis = { massKg = ch.massKg, com = ch.com, bounds = ch.bounds, ratedLoadN = 150000, wheels = true, skin = ch.skin },
            parts = parts,
        })
        m.vehicleKey = opts.vehicleKey
        m.flightBody = opts.body and { family = opts.body.family, prov = opts.body.prov } or nil
        return m
    end

    --- Can this machine point itself (pitch and yaw, both ways)? With the development waiver, yes -- said so.
    function M.canPoint(m, waiver)
        if waiver then return true, "development attitude waiver (not physical)" end
        local auth = Mach.authority(m, { reaction = true })
        local ok = auth.torque.pos[1] > 1e-6 and auth.torque.neg[1] > 1e-6 and auth.torque.pos[3] > 1e-6 and auth.torque.neg[3] > 1e-6
        if ok then return true, "attitude from its own parts" end
        local function axis(a) return (auth.torque.pos[a] > 1e-6 and auth.torque.neg[a] > 1e-6) and "both ways" or
            ((auth.torque.pos[a] > 1e-6 or auth.torque.neg[a] > 1e-6) and "one way" or "none") end
        return false, ("no attitude authority: pitch %s, yaw %s, roll %s -- nothing on it can turn it (an attitude set, e.g. the AC-6)")
            :format(axis(1), axis(3), axis(2))
    end

    --- A short authority line for a HUD.
    function M.authorityText(m)
        local auth = Mach.authority(m, { reaction = true })
        local function axis(a) return (auth.torque.pos[a] > 1e-6 and auth.torque.neg[a] > 1e-6) and "+/-" or
            ((auth.torque.pos[a] > 1e-6 or auth.torque.neg[a] > 1e-6) and "one way" or "none") end
        return ("pitch %s  yaw %s  roll %s"):format(axis(1), axis(3), axis(2))
    end

    -- ------------------------------------------------------------------------------------------ state
    local function rotFromBasis(b)
        local r, f, u = b.right, b.forward, b.up
        return { { r[1], f[1], u[1] }, { r[2], f[2], u[2] }, { r[3], f[3], u[3] } }
    end
    local function basisFromRot(R)
        return { right = { R[1][1], R[2][1], R[3][1] }, forward = { R[1][2], R[2][2], R[3][2] }, up = { R[1][3], R[2][3], R[3][3] } }
    end
    M.rotFromBasis, M.basisFromRot = rotFromBasis, basisFromRot

    --- A dynamics state for a Deep state ({ p, v, basis }) on this machine; `carry` = a previous dynamics state or a
    --- canonical record's `dyn` (omega, per-device heat, throttle, strokes, attitude heat) to continue from.
    function M.state(m, deep, carry)
        local s = Dyn.init(m, { pos = { deep.p[1], deep.p[2], deep.p[3] }, vel = { deep.v[1], deep.v[2], deep.v[3] }, rot = rotFromBasis(deep.basis) })
        if type(carry) == "table" then
            if carry.omega then s.omega = { carry.omega[1] or 0, carry.omega[2] or 0, carry.omega[3] or 0 } end
            s.dev, s.thr, s.pulse, s.att = carry.dev or s.dev, carry.thr or s.thr, carry.pulse or s.pulse, carry.att or s.att
            -- L334: every tank's fill (the Machine's fuel and any tank part's own propellant) survives checkpoints
            if type(carry.tanks) == "table" then
                for i in ipairs(m.tanks) do if tonumber(carry.tanks[i]) then s.tanks[i] = tonumber(carry.tanks[i]) end end
            end
        end
        return s
    end

    --- The Deep view of a dynamics state.
    function M.deep(s) return { p = s.pos, v = s.vel, basis = basisFromRot(s.rot), t = s.t } end

    --- What to carry in a canonical record (JSON-safe).
    function M.carry(s) return { omega = s.omega, dev = s.dev, thr = s.thr, pulse = s.pulse, att = s.att, tanks = s.tanks } end

    --- The environment at a state: real gravity plus the rotating Earth's Coriolis and centrifugal terms (L334), air by
    --- altitude.
    function M.env(s, extra)
        local _, _, alt = D.ecefToLla(s.pos)
        local e = { g = V.add(D.gravity(s.pos), D.fictitious(s.pos, s.vel or { 0, 0, 0 })), rho = M.density(alt) }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e, alt
    end

    --- One step. opts = { devFuel = bool, devHeat = bool, waiver = { dir, axis, rate } | nil, rig = { pitch, yaw, roll } | nil }.
    function M.step(m, s, cmd, dt, opts)
        opts = opts or {}
        local env = M.env(s, { attitudeWaiver = opts.waiver, attitudeRig = opts.rig })
        if opts.devHeat then
            for _, st in pairs(s.dev or {}) do st.heatK, st.hot = 0, false end
            for _, st in pairs(s.att or {}) do st.heatK, st.hot = 0, false end
            s.heatK = 0
        end
        local s2, tel = Dyn.step(m, s, env, cmd, dt)
        if opts.devFuel then for i, t in ipairs(m.tanks) do s2.tanks[i] = t.kg end end   -- dev fuel: nothing burns
        tel.alt, tel.mass = select(3, D.ecefToLla(s2.pos)), Dyn.mass(m, s2)
        return s2, tel
    end

    --- The canonical FLIGHT TELEMETRY row (aerospace brief §4): one shape for every host, the race log and a diagnosis.
    --- `extra` = { machineId, driver, leg, gate, toGateM, position, gapS } from the race, merged in.
    function M.row(m, s, tel, extra)
        tel = tel or {}
        local Dy = Dyn
        local mass = Dy.mass(m, s)
        local thrust = tel.thrustN or 0
        local _, _, alt = D.ecefToLla(s.pos)
        local up = V.unit(s.pos)
        local vr = V.dot(s.vel, up)
        local vt = V.len(V.add(s.vel, V.scale(up, -vr)))
        local fuel = {}
        for i, t in ipairs(m.tanks) do fuel[t.propellant or ("tank" .. i)] = (fuel[t.propellant or ("tank" .. i)] or 0) + (s.tanks[i] or 0) end
        local r = {
            t = s.t, massKg = mass, thrustN = thrust, accel = thrust / math.max(1, mass),
            pos = { s.pos[1], s.pos[2], s.pos[3] }, vel = { s.vel[1], s.vel[2], s.vel[3] }, speed = V.len(s.vel),
            vRadial = vr, vTangential = vt, altM = alt, omega = { s.omega[1], s.omega[2], s.omega[3] },
            forward = { s.rot[1][2], s.rot[2][2], s.rot[3][2] },
            propellantKg = fuel, heatK = s.heatK, derate = tel.derate, rho = tel.rho or M.density(alt), qPa = tel.qPa or 0,
            aeroHeatKw = tel.aeroHeatKw or 0, skinRejectKw = tel.skinRejectKw or 0, waiver = tel.waiver or nil,
            family = m.flightBody and m.flightBody.family or m.vehicleKey,
        }
        for k, v in pairs(extra or {}) do r[k] = v end
        return r
    end

    --- Fuel left (kg) in the Machine's tank.
    function M.fuelKg(m, s) return Dyn.propellantLeft(m, s, "fuel") end

    --- The thrust axis of the sustained engines (body frame, thrust-weighted), or nil.
    function M.mainAxis(m)
        local a = { 0, 0, 0 }
        for _, d in ipairs(m.devices) do
            if d.kind == "reaction_engine" then a = V.add(a, V.scale(d.dir, d.perf.thrustN or 0)) end
        end
        return V.len(a) > 0 and V.unit(a) or nil
    end

    return M
end)
