-- ncm-core module: engineering.dynamics
--
-- The canonical machine integrator (L321; doc 54 §D, §H). An assembled machine (`engineering.machine`) plus a state
-- (where it is, how it is turned, what is left in its tanks and stores, how hot it is) plus the world (gravity, air
-- density, ground contact) plus commands (throttles, "fire the ram") -> the next state. Hosts only EXPRESS the result
-- (`engineering.hosts`); they never decide what a machine can do.
--
-- THE HOP IS NOT A THRUSTER (doc 54 §D). Each way of pushing has a physical precondition, enforced here, never a flag:
--   ground_ram       acts only with ground contact, and only with energy already stored in its stroke. A press in
--                    free air does nothing -- there is nothing to push against. Recharge comes from an energy store.
--   propeller / jet  thrust scales with air density: full at sea level, nothing in vacuum.
--   reaction_engine  works anywhere, consumes propellant at F / (Isp g0), and stops when its propellant is gone.
--   everything       makes heat; heat above the limit derates output to zero. Off-centre force spins the machine.
--
-- Frames: machine (body) frame x right, y forward, z up; the world frame is whatever the caller integrates in (a
-- local east/north/up patch, or the `space.universe` Earth frame), with `env.g` the gravity vector in it.
--   state = { pos, vel, rot = {r1, r2, r3} (rows; world = rot * body), omega (body rad/s), tanks = {kg...},
--             stores = {J...}, rams = {J...}, heatK, t }
--   env   = { g = {x,y,z}, rho = kg/m^3, contact = bool | nil, groundZ = number | nil }
--   cmd   = { throttle = { [deviceIndex or key] = 0..1 } | number (all non-ram devices), fire = bool,
--             discharge = { [deviceIndex or key] = true } (pulse devices, one stroke per true), torque = {x,y,z} -1..1 }
--
-- L331 (Deep on the full model): pulse_reaction strokes (the IA-10), per-device heat (`d.thermal`: limit -> shutdown,
-- resume), throttle response (`perf.throttleTauS`), attitude sets (`attitude_control`: torque about every axis, paid in
-- propellant at force = torque / arm), and the DEVELOPMENT attitude waiver (`env.attitudeWaiver = { dir, axis, rate }`
-- or `env.attitudeRig = { pitch, yaw, roll }` rad/s) -- turns the body directly, NOT physical, reported in telemetry.
local Core = NcmCore

Core.define("engineering.dynamics", function(C)
    local M = { version = "0.1.0" }
    local Sys = C.get("engineering.systems")
    local Mach = C.get("engineering.machine")
    local V = Mach.vec
    local add, sub, scale, dot, cross, len = V.add, V.sub, V.scale, V.dot, V.cross, V.len
    local function unit(a) local l = len(a); return l > 0 and scale(a, 1 / l) or { 0, 0, 0 } end

    local function rotate(R, v) return { dot(R[1], v), dot(R[2], v), dot(R[3], v) } end
    local function transpose(R) return { { R[1][1], R[2][1], R[3][1] }, { R[1][2], R[2][2], R[3][2] }, { R[1][3], R[2][3], R[3][3] } } end
    local function mul(A, B)
        local Bt = transpose(B)
        local o = {}
        for i = 1, 3 do o[i] = { dot(A[i], Bt[1]), dot(A[i], Bt[2]), dot(A[i], Bt[3]) } end
        return o
    end
    local function orthonormal(R)
        -- Gram-Schmidt on the columns, so long integrations stay a rotation
        local Rt = transpose(R)
        local c1 = V.unit(Rt[1])
        local c2 = V.unit(sub(Rt[2], scale(c1, dot(Rt[2], c1))))
        local c3 = cross(c1, c2)
        return transpose({ c1, c2, c3 })
    end
    local function axisAngle(axis, a)
        local x, y, z = axis[1], axis[2], axis[3]
        local c, s = math.cos(a), math.sin(a)
        local k = 1 - c
        return { { c + x * x * k, x * y * k - z * s, x * z * k + y * s },
                 { y * x * k + z * s, c + y * y * k, y * z * k - x * s },
                 { z * x * k - y * s, z * y * k + x * s, c + z * z * k } }
    end
    M.rotate = rotate

    --- A fresh state for an assembled machine: tanks as filled, stores and rams charged, cold, at rest.
    function M.init(m, opts)
        opts = opts or {}
        local s = {
            pos = opts.pos or { 0, 0, 0 }, vel = opts.vel or { 0, 0, 0 },
            rot = opts.rot or { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }, omega = opts.omega or { 0, 0, 0 },
            tanks = {}, stores = {}, rams = {}, heatK = 0, t = 0, fired = false,
            thr = {}, pulse = {}, dev = {},   -- L331: throttle lag, stroke left, per-device { heatK, hot }
        }
        for i, t in ipairs(m.tanks) do s.tanks[i] = t.kg end
        for i, st in ipairs(m.stores) do s.stores[i] = st.capacityJ or 0 end
        for i, d in ipairs(m.devices) do
            if d.kind == "ground_ram" then s.rams[i] = math.min(d.perf.energyJ or 0, (d.perf.forceN or 0) * (d.perf.strokeM or 0)) end
        end
        return s
    end

    --- Current mass: dry plus what is left in the tanks.
    function M.mass(m, s)
        local kg = m.dryMassKg
        for i in ipairs(m.tanks) do kg = kg + (s.tanks[i] or 0) end
        return kg
    end

    function M.propellantLeft(m, s, kind)
        local kg = 0
        for i, t in ipairs(m.tanks) do if not kind or t.propellant == kind then kg = kg + (s.tanks[i] or 0) end end
        return kg
    end

    local function draw(m, s, kind, want)
        -- take `want` kg of a propellant from the tanks that carry it; returns what was taken
        local got = 0
        for i, t in ipairs(m.tanks) do
            if t.propellant == kind and got < want then
                local take = math.min(s.tanks[i] or 0, want - got)
                s.tanks[i] = (s.tanks[i] or 0) - take
                got = got + take
            end
        end
        return got
    end

    local function drawEnergy(m, s, want)
        local got = 0
        for i in ipairs(m.stores) do
            if got < want then
                local take = math.min(s.stores[i] or 0, want - got)
                s.stores[i] = s.stores[i] - take
                got = got + take
            end
        end
        return got
    end

    M.SUTTON_GRAVES = 1.7415e-4   -- Earth air, SI (W m^-2 with rho in kg/m^3, Rn in m, v in m/s)
    M.AMBIENT_K = 288

    --- Thermal derate: full output below 80 % of the limit, falling linearly to nothing at the limit.
    function M.derate(s)
        local lim = Mach.TEMP_LIMIT_K
        if s.heatK <= 0.8 * lim then return 1 end
        return math.max(0, (lim - s.heatK) / (0.2 * lim))
    end

    local function devState(s, i)
        s.dev = s.dev or {}
        s.dev[i] = s.dev[i] or { heatK = 0, hot = false }
        return s.dev[i]
    end

    --- One device's own heat (installed parts carry `thermal`): heat in, rejection out, shutdown at the limit until cool.
    local function deviceHeat(d, st, inKj, dt)
        local th = d.thermal
        if not th or not th.capacityKjK or th.capacityKjK <= 0 then return false end
        st.heatK = math.max(0, st.heatK + (inKj - (th.rejectKw or 0) * dt) / th.capacityKjK)
        if not st.hot and st.heatK >= (th.limitK or 1e9) then st.hot = true end
        if st.hot and st.heatK <= (th.resumeK or 0) then st.hot = false end
        return true
    end

    local function wanted(tbl, i, d)
        if type(tbl) ~= "table" then return nil end
        return tbl[i] or (d.key and tbl[d.key]) or (d.componentId and tbl[d.componentId])
    end

    local function throttleFor(cmd, i, d)
        local th = cmd and cmd.throttle
        if type(th) == "number" then return th end
        if type(th) == "table" then return th[i] or th[d.key] or (d.componentId and th[d.componentId]) or 0 end
        return 0
    end

    --- One step. Returns the state (mutated) and telemetry { forceN (world), thrustN, rho, contact, derate, events }.
    function M.step(m, s, env, cmd, dt)
        env = env or {}
        local rho = env.rho or 0
        local g = env.g or { 0, 0, -9.81 }
        local contact = env.contact
        if contact == nil and env.groundZ then contact = s.pos[3] <= env.groundZ + 0.05 end
        local mass = M.mass(m, s)
        local com = m.com
        local der = M.derate(s)
        local Fb, Tb = { 0, 0, 0 }, { 0, 0, 0 }
        local heatKj, thrustTotal = 0, 0
        local tel = { rho = rho, contact = contact and true or false, derate = der, events = {} }
        local fireEdge = cmd and cmd.fire and not s.fired
        s.fired = cmd and cmd.fire and true or false

        -- 2026-10-12 (the AV's four swivelling pods): a torque request is SHARED among the gimballed engines in proportion
        -- to their thrust, so N engines make the asked torque once, not N times. The share is fixed from the commanded
        -- throttles (the lagged value is what each engine actually makes next).
        local gimbalShareN = 0
        if cmd and type(cmd.torqueNm) == "table" then
            for i, d in ipairs(m.devices) do
                local p = d.perf
                if (p.gimbalDeg or 0) > 0 and d.kind ~= "ground_ram" and d.kind ~= "pulse_reaction" then
                    gimbalShareN = gimbalShareN + (p.thrustN or 0) * math.max(0, math.min(1, (s.thr and s.thr[i]) or throttleFor(cmd, i, d)))
                end
            end
        end
        for i, d in ipairs(m.devices) do
            local p = d.perf
            if d.kind == "ground_ram" then
                local stored = s.rams[i] or 0
                local full = math.min(p.energyJ or 0, (p.forceN or 0) * (p.strokeM or 0))
                if fireEdge then
                    if not contact then
                        tel.events[#tel.events + 1] = { device = d.key, what = "no_contact" }
                    elseif stored <= 0 then
                        tel.events[#tel.events + 1] = { device = d.key, what = "not_charged" }
                    else
                        -- the stroke turns stored energy into the machine's kinetic energy along the ram's axis
                        local dv = math.sqrt(2 * stored * der / mass)
                        local J = scale(d.dir, mass * dv)                       -- body-frame impulse
                        s.vel = add(s.vel, rotate(s.rot, scale(d.dir, dv)))
                        local L = cross(sub(d.at, com), J)                    -- angular impulse about the CoM
                        for a = 1, 3 do s.omega[a] = s.omega[a] + L[a] / math.max(1e-6, m.inertia[a]) end
                        s.rams[i] = 0
                        heatKj = heatKj + (p.heatKw or 0)
                        tel.events[#tel.events + 1] = { device = d.key, what = "fired", dv = dv, energyJ = stored * der }
                    end
                elseif stored < full and p.chargeW then
                    s.rams[i] = stored + drawEnergy(m, s, math.min(full - stored, p.chargeW * dt))
                end
            elseif d.kind == "pulse_reaction" then
                -- one stroke per discharge: forceN for pulseS at the mount, propellant per stroke, a fresh press restarts it
                local st = devState(s, i)
                local inKj = 0
                if cmd and wanted(cmd.discharge, i, d) and not st.hot then
                    local kg = Sys.pulseMass(p)
                    if draw(m, s, p.propellant, kg) >= kg - 1e-9 then
                        s.pulse[i] = p.pulseS or 0.2
                        inKj = p.heatKj or 0
                        tel.events[#tel.events + 1] = { device = d.key, what = "discharge" }
                    else
                        tel.events[#tel.events + 1] = { device = d.key, what = "starved" }
                    end
                end
                local left = s.pulse[i] or 0
                if left > 0 then
                    local active = math.min(dt, left)
                    local f = scale(d.dir, (p.forceN or 0) * active / dt * der)
                    Fb = add(Fb, f)
                    Tb = add(Tb, cross(sub(d.at, com), f))
                    thrustTotal = thrustTotal + (p.forceN or 0) * active / dt
                    s.pulse[i] = left - active
                end
                if not deviceHeat(d, st, inKj, dt) then heatKj = heatKj + inKj end
            else
                local st = devState(s, i)
                -- the COMMAND lags (throttle response); heat acts on the output at once (derate, shutdown)
                local want = math.max(0, math.min(1, throttleFor(cmd, i, d)))
                if st.hot then want = 0 end
                local tau = p.throttleTauS or 0
                s.thr = s.thr or {}
                local lagged = tau > 0 and ((s.thr[i] or 0) + (want - (s.thr[i] or 0)) * math.min(1, dt / tau)) or want
                if lagged < 1e-3 then lagged = 0 end
                s.thr[i] = lagged
                local t = st.hot and 0 or lagged * der
                if t > 0 and p.minThrottle and t < p.minThrottle then t = 0 end
                local F = 0
                if t > 0 then
                    if d.kind == "reaction_engine" or d.kind == "jet" then
                        local want = Sys.massFlow(p) * t * dt
                        local got = want > 0 and draw(m, s, p.propellant, want) or 0
                        local frac = want > 0 and got / want or 0
                        if frac < 1 then tel.events[#tel.events + 1] = { device = d.key, what = "starved" } end
                        F = Sys.thrustAt(p, rho, t * frac)
                    elseif d.kind == "propeller" then
                        local want = (p.powerW or 0) * t * dt
                        local got = drawEnergy(m, s, want)
                        local frac = want > 0 and got / want or 0
                        if frac < 1 then tel.events[#tel.events + 1] = { device = d.key, what = "no_energy" } end
                        F = Sys.thrustAt(p, rho, t * frac)
                    end
                    if not d.thermal then heatKj = heatKj + (p.heatKw or 0) * t * dt end
                end
                deviceHeat(d, st, (p.heatKw or 0) * t * dt, dt)
                if F > 0 then
                    local dir = d.dir
                    -- L334: a GIMBALLED engine (perf.gimbalDeg) steers its own thrust line: first through the centre of
                    -- mass (no torque from a mount that sits off it -- the drive's own trim), then tilted for the torque
                    -- the pilot or Guidance asks for (cmd.torqueNm, body N m), all within its gimbal range.
                    local gmax = math.rad(p.gimbalDeg or 0)
                    if gmax > 0 then
                        local lever = sub(com, d.at)
                        local L = len(lever)
                        if L > 1e-6 then
                            -- the trim through the centre of mass is only a TRIM: an engine whose line already runs
                            -- (nearly) through it leans onto it; one far off it (an AV's splayed pods) keeps its own axis
                            local w = scale(lever, 1 / L)
                            if dot(w, d.dir) < math.cos(gmax) then w = d.dir end
                            local tw = cmd and cmd.torqueNm
                            if type(tw) == "table" then
                                local share = gimbalShareN > 0 and math.min(1, (p.thrustN or 0) * math.max(0, math.min(1, s.thr[i] or 0)) / gimbalShareN) or 1
                                local want = { (tonumber(tw[1]) or 0) * share, (tonumber(tw[2]) or 0) * share, (tonumber(tw[3]) or 0) * share }
                                w = add(w, scale(cross(lever, want), 1 / (F * L * L)))
                            end
                            w = unit(w)
                            local c = dot(w, d.dir)
                            if c < math.cos(gmax) then
                                -- beyond the gimbal: the furthest it can lean toward w
                                local perp = sub(w, scale(d.dir, c))
                                local pl = len(perp)
                                w = pl > 1e-9 and add(scale(d.dir, math.cos(gmax)), scale(perp, math.sin(gmax) / pl)) or d.dir
                            end
                            dir = w
                        end
                    end
                    local f = scale(dir, F)
                    Fb = add(Fb, f)
                    Tb = add(Tb, cross(sub(d.at, com), f))
                    thrustTotal = thrustTotal + F
                end
            end
        end
        for _, src in ipairs(m.sources) do heatKj = heatKj + (src.heatKw or 0) * dt end

        -- attitude sets: torque on command about every axis, paid for in propellant (force = torque / arm)
        local tq = cmd and cmd.torque
        -- L334: an ABSOLUTE torque request (N m) is what is left after the engines' own torque (gimbals, offsets);
        -- each attitude set takes what it can of that remainder, per axis
        local rest = nil
        if cmd and type(cmd.torqueNm) == "table" then
            rest = { (tonumber(cmd.torqueNm[1]) or 0) - Tb[1], (tonumber(cmd.torqueNm[2]) or 0) - Tb[2], (tonumber(cmd.torqueNm[3]) or 0) - Tb[3] }
        end
        s.att = s.att or {}
        for j, at in ipairs(m.attitude or {}) do
            local p = at.perf
            s.att[j] = s.att[j] or { heatK = 0, hot = false }
            local st = s.att[j]
            local inKj = 0
            if (type(tq) == "table" or rest) and not st.hot then
                local want = { 0, 0, 0 }
                local mag = 0
                local lim = (p.torqueNm or 0) * der
                for a = 1, 3 do
                    if rest then
                        want[a] = math.max(-lim, math.min(lim, rest[a]))
                        rest[a] = rest[a] - want[a]
                    else
                        want[a] = math.max(-1, math.min(1, tonumber(tq[a]) or 0)) * lim
                    end
                    if math.abs(want[a]) < 1e-3 * math.max(1, lim) then want[a] = 0 end
                    mag = mag + math.abs(want[a])
                end
                if mag > 0 then
                    local kg = (mag / math.max(0.05, p.armM or 0.5)) / ((p.ispS or 70) * Sys.G0) * dt
                    local got = draw(m, s, p.propellant, kg)
                    local frac = kg > 0 and got / kg or 0
                    if frac < 1 then tel.events[#tel.events + 1] = { device = at.key, what = "starved" } end
                    for a = 1, 3 do Tb[a] = Tb[a] + want[a] * frac end
                    inKj = (p.heatKw or 0) * math.min(1, mag / (3 * math.max(1, p.torqueNm or 1))) * dt
                    tel.attitudeNm = mag * frac
                end
            end
            if not deviceHeat({ thermal = at.thermal }, st, inKj, dt) then heatKj = heatKj + inKj end
        end

        -- air: drag on every aero surface against the velocity, lift along the body's up from forward speed
        local Fw = rotate(s.rot, Fb)
        if rho > 0 then
            local v = len(s.vel)
            tel.qPa = 0.5 * rho * v * v
            -- aerodynamic heating (aerospace brief, 2026-10-07): Sutton-Graves stagnation-point flux k sqrt(rho / Rn) v^3,
            -- averaged at half that over the frontal area. Nothing at road speed, a few kW climbing out, megawatts coming
            -- home at orbital speed. Only a machine with a described skin (`engineering.flightbody`) heats.
            if m.skin and v > 0 then
                local sk = m.skin
                local kw = 0.5 * M.SUTTON_GRAVES * math.sqrt(rho / sk.noseRadiusM) * v ^ 3 * sk.frontalM2 / 1000
                heatKj = heatKj + kw * dt
                tel.aeroHeatKw = kw
            end
            if v > 0 then
                local fwd = dot(s.vel, { s.rot[1][2], s.rot[2][2], s.rot[3][2] })
                for _, surf in ipairs(m.surfaces) do
                    local q = 0.5 * rho * surf.perf.areaM2
                    Fw = add(Fw, scale(s.vel, -q * surf.perf.cd * v))
                    Fw = add(Fw, scale({ s.rot[1][3], s.rot[2][3], s.rot[3][3] }, q * surf.perf.cl * fwd * math.abs(fwd)))
                end
            end
        end

        -- translation (semi-implicit), with a flat ground when the caller gives one
        local a = add(scale(Fw, 1 / mass), g)
        s.vel = add(s.vel, scale(a, dt))
        if env.groundZ and s.pos[3] <= env.groundZ + 1e-9 and s.vel[3] < 0 then s.vel = { s.vel[1] * 0.98, s.vel[2] * 0.98, 0 } end
        s.pos = add(s.pos, scale(s.vel, dt))
        if env.groundZ and s.pos[3] < env.groundZ then s.pos[3] = env.groundZ end

        -- rotation: body torque over the principal inertia (gyroscopic terms neglected at v0)
        for k = 1, 3 do s.omega[k] = s.omega[k] + Tb[k] / math.max(1e-6, m.inertia[k]) * dt end
        local w = len(s.omega)
        if w > 0 then
            s.rot = orthonormal(mul(s.rot, axisAngle(scale(s.omega, 1 / w), w * dt)))
        end

        -- the DEVELOPMENT attitude waiver: turns the body directly (not physical; telemetry says so)
        local wv = env.attitudeWaiver
        if type(wv) == "table" and wv.dir and wv.axis then
            local cur = V.unit(rotate(s.rot, wv.axis))
            local want = V.unit(wv.dir)
            local c = math.max(-1, math.min(1, dot(cur, want)))
            local ang = math.acos(c)
            if ang > 1e-6 then
                local k = cross(cur, want)
                if len(k) < 1e-9 then k = { s.rot[1][3], s.rot[2][3], s.rot[3][3] } end
                k = V.unit(k)
                local a = math.min(ang, (wv.rate or 1) * dt)
                s.rot = orthonormal(mul(axisAngle(k, a), s.rot))
            end
            s.omega = { 0, 0, 0 }
            tel.waiver = true
        elseif type(env.attitudeRig) == "table" then
            local r = env.attitudeRig
            local w = { (r.pitch or 0), (r.roll or 0), -(r.yaw or 0) }
            local wl = len(w)
            if wl > 0 then s.rot = orthonormal(mul(s.rot, axisAngle(scale(w, 1 / wl), wl * dt))) end
            tel.waiver = wl > 0 or tel.waiver
        end

        -- heat: generated against rejected at this density, into the machine's heat capacity
        local rej = 0
        for _, r in ipairs(m.radiators) do rej = rej + Sys.rejectionKw(r, rho) end
        -- a described skin radiates what it holds (grey body, against a 288 K surround): zero when cool, ~20 kW for a car
        -- at its derate threshold -- the most heat it can take in steadily
        if m.skin and s.heatK > 0 then
            local T, T0 = M.AMBIENT_K + s.heatK, M.AMBIENT_K
            local kw = m.skin.emissivity * 5.670374e-8 * m.skin.wettedM2 * (T ^ 4 - T0 ^ 4) / 1000
            rej = rej + kw
            tel.skinRejectKw = kw
        end
        local capKjPerK = math.max(1e-6, m.dryMassKg * Mach.CP / 1000)
        s.heatK = math.max(0, s.heatK + (heatKj - rej * dt) / capKjPerK)

        s.t = s.t + dt
        tel.forceN, tel.thrustN, tel.torque = Fw, thrustTotal, Tb
        return s, tel
    end

    return M
end)
