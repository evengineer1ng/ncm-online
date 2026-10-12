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

    -- doc 58: the experimental drives (space.drives) step after the dynamics on every host; a host without the module
    -- (or without a clock) flies exactly as before
    local DrivesMod = false
    local function drives()
        if DrivesMod == false then local ok, Dm = pcall(C.get, "space.drives"); DrivesMod = ok and Dm or nil end
        return DrivesMod
    end
    M.drives = drives

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
                pos = d.pos or { 0, 0, 0.5 }, dir = d.axis, centred = d.centred,
            }
        end
        local m = Mach.assemble({
            chassis = { massKg = ch.massKg, com = ch.com, bounds = ch.bounds, ratedLoadN = 150000, wheels = true, skin = ch.skin },
            parts = parts,
        })
        m.vehicleKey = opts.vehicleKey
        m.flightBody = opts.body and { family = opts.body.family, prov = opts.body.prov } or nil
        -- doc 58: drive parts are mass to the dynamics (no push mechanism); space.drives runs them
        local Dm = drives()
        m.drives = Dm and Dm.fromDevices(devices) or {}
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

    -- doc 57 §5 (2026-10-11): the astronomical substrate. With a UTC on the state, gravity is every relevant catalogue
    -- body (space.frames / space.gravity) and the state is integrated in the frame space.frames chooses (Earth-fixed
    -- near home, inertial beyond); without one (a host that does not pass `utc`) everything is exactly as before.
    local FramesMod = false
    local function frames()
        if FramesMod == false then local ok, F = pcall(C.get, "space.frames"); FramesMod = ok and F or nil end
        return FramesMod
    end
    M.FRAME_CHECK_S = 120         -- how often (simulated seconds) the frame policy is consulted


    --- A dynamics state for a Deep state ({ p, v, basis }) on this machine; `carry` = a previous dynamics state or a
    --- canonical record's `dyn` (omega, per-device heat, throttle, strokes, attitude heat) to continue from. `utc`
    --- (optional) turns on the astronomical substrate; a Deep state in an inertial frame (`frame`, `ip`, `iv`, `ibasis`)
    --- resumes in that frame.
    function M.state(m, deep, carry, utc)
        local Fr = frames()
        local inertial = Fr and type(deep.frame) == "table" and deep.ip and deep.iv and deep.ibasis
        local p, v, b = deep.p, deep.v, deep.basis
        if inertial then p, v, b = deep.ip, deep.iv, deep.ibasis end
        local s = Dyn.init(m, { pos = { p[1], p[2], p[3] }, vel = { v[1], v[2], v[3] }, rot = rotFromBasis(b) })
        if inertial then s.frame = Fr.load_(deep.frame) end
        s.utc = tonumber(utc) or tonumber(deep.utc)
        if type(carry) == "table" then
            if carry.omega then s.omega = { carry.omega[1] or 0, carry.omega[2] or 0, carry.omega[3] or 0 } end
            s.dev, s.thr, s.pulse, s.att = carry.dev or s.dev, carry.thr or s.thr, carry.pulse or s.pulse, carry.att or s.att
            -- L334: every tank's fill (the Machine's fuel and any tank part's own propellant) survives checkpoints
            if type(carry.tanks) == "table" then
                for i in ipairs(m.tanks) do if tonumber(carry.tanks[i]) then s.tanks[i] = tonumber(carry.tanks[i]) end end
            end
        end
        -- doc 58: each drive's state, the travel ledger and an open conventional burn carry on
        local Dm = drives()
        if Dm then
            s.drv = Dm.init(m, type(carry) == "table" and carry.drv or nil)
            s.travel = C.get("space.travel").load(type(carry) == "table" and carry.travel or nil)
            if type(carry) == "table" and type(carry.conv) == "table" then s.conv = carry.conv end
        end
        return s
    end

    --- The Deep view of a dynamics state: Earth-fixed p, v, basis for every reader (an exact mirror when the state flies
    --- in an inertial frame), plus the frame and the authoritative state in it.
    function M.deep(s)
        local Fr = frames()
        if Fr and s.utc and s.frame then
            local p, v, R = Fr.mirror(s, s.utc)
            return { p = p, v = v, basis = basisFromRot(R), t = s.t, utc = s.utc, frame = Fr.save(s.frame),
                     ip = { s.pos[1], s.pos[2], s.pos[3] }, iv = { s.vel[1], s.vel[2], s.vel[3] }, ibasis = basisFromRot(s.rot) }
        end
        return { p = s.pos, v = s.vel, basis = basisFromRot(s.rot), t = s.t, utc = s.utc }
    end

    --- What to carry in a canonical record (JSON-safe).
    --- compact = true for a persisted record (doc 58: drive states without their activation record and checkpoint).
    function M.carry(s, compact)
        local Dm = drives()
        return { omega = s.omega, dev = s.dev, thr = s.thr, pulse = s.pulse, att = s.att, tanks = s.tanks,
                 drv = Dm and Dm.save(s.drv, compact) or nil, travel = s.travel and C.get("space.travel").save(s.travel) or nil,
                 conv = (not compact) and s.conv or nil }
    end

    --- The environment at a state: real gravity plus the rotating Earth's Coriolis and centrifugal terms (L334), air by
    --- altitude.
    function M.env(s, extra)
        local Fr = frames()
        local e, alt
        if Fr and s.utc then
            if Fr.isEarthFixed(s.frame) then
                -- doc 57: the home planet exact plus every other relevant body (third-body form), then the rotating
                -- frame's own terms as before
                alt = select(3, D.ecefToLla(s.pos))
                e = { g = V.add(Fr.accel(s, s.utc), D.fictitious(s.pos, s.vel or { 0, 0, 0 })), rho = M.density(alt) }
            else
                -- an inertial frame: no fictitious terms, no air (frames switch out of Earth-fixed only far from it)
                e = { g = Fr.accel(s, s.utc), rho = 0 }
            end
        else
            alt = select(3, D.ecefToLla(s.pos))
            e = { g = V.add(D.gravity(s.pos), D.fictitious(s.pos, s.vel or { 0, 0, 0 })), rho = M.density(alt) }
        end
        for k, v in pairs(extra or {}) do e[k] = v end
        return e, alt
    end

    --- Put a state back in the Earth-fixed frame now (exact): for code that reads s.pos as Earth-fixed (guidance).
    function M.toEarthFixed(s)
        local Fr = frames()
        if Fr and s.utc and s.frame then Fr.update(s, s.utc, { earthFixed = true }) end
        return s
    end

    --- Altitude above the home planet for any frame (Earth-fixed: as before; inertial: through the exact mirror).
    function M.altitude(s)
        local Fr = frames()
        if Fr and s.utc and s.frame then
            -- centred on home: |p| is the distance from its centre, exactly as in the Earth-fixed frame
            if not s.frame.anchor and s.frame.body == Fr.home().id then return V.len(s.pos) - D.R end
            -- elsewhere (the Sun's frame, between the stars) the mirror costs an ephemeris: refresh it with the frame check
            if not s.altAt or math.abs(s.utc - s.altAt) >= M.FRAME_CHECK_S then
                s.altAt, s.altCache = s.utc, select(3, D.ecefToLla((Fr.mirror(s, s.utc))))
            end
            return s.altCache
        end
        return select(3, D.ecefToLla(s.pos))
    end

    --- One step. opts = { devFuel = bool, devHeat = bool, waiver = { dir, axis, rate } | nil, rig = { pitch, yaw, roll } | nil,
    --- utc = seconds (the step's start: turns on the astronomical substrate), earthFixed = bool (keep / return to the
    --- Earth-fixed frame: guidance, landing) }.
    function M.step(m, s, cmd, dt, opts)
        opts = opts or {}
        if tonumber(opts.utc) then s.utc = tonumber(opts.utc) end
        local Fr = frames()
        if Fr and s.utc and (opts.earthFixed and s.frame or (s.frameCheckAt == nil or math.abs(s.utc - s.frameCheckAt) >= M.FRAME_CHECK_S)) then
            s.frameCheckAt = s.utc
            local switched = Fr.update(s, s.utc, { earthFixed = opts.earthFixed })
            if switched then s.frameSwitched = { to = switched, utc = s.utc } end
        end
        local env = M.env(s, { attitudeWaiver = opts.waiver, attitudeRig = opts.rig })
        if opts.devHeat then
            for _, st in pairs(s.dev or {}) do st.heatK, st.hot = 0, false end
            for _, st in pairs(s.att or {}) do st.heatK, st.hot = 0, false end
            s.heatK = 0
        end
        local s2, tel = Dyn.step(m, s, env, cmd, dt)
        if s2.utc then s2.utc = s2.utc + dt end
        if opts.devFuel then for i, t in ipairs(m.tanks) do s2.tanks[i] = t.kg end end   -- dev fuel: nothing burns
        -- doc 58: the drives (and the activation record of an impulse / fusion burn, and the travel ledger)
        local Dm = drives()
        if Dm and s2.utc then
            local okD, evs = pcall(Dm.step, m, s2, cmd, dt, opts)
            if not okD and tostring(evs):find("budget exceeded", 1, true) then error(evs, 0) end
            if okD then tel.driveEvents = evs else tel.driveEvents = { { type = "error", error = tostring(evs):sub(1, 300), utc = s2.utc } } end
            if s2.frameSwitched and not tel.frameSwitched then tel.frameSwitched = s2.frameSwitched end
        end
        tel.alt, tel.mass = M.altitude(s2), Dyn.mass(m, s2)
        tel.frame = Fr and Fr.key(s2.frame) or "earth_fixed"
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
