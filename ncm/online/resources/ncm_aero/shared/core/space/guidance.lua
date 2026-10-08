-- ncm-core module: space.guidance
--
-- L327: the NCM guidance computer. Given the Machine's canonical deep state and a destination on NCM Earth
-- (`space.venues`), it plans a route and its autopilot FLIES it: every metre is integrated by `space.deep` under real
-- gravity, and the only push is the Machine's own sustained thrust (its installed propulsors, its mass). It never moves
-- the Machine -- it commands a throttle and a pointing direction.
--
-- What is PHYSICAL: position/velocity evolution, gravity, thrust limited by the installed propulsors, propellant use.
-- What is ASSISTED (and said so): attitude. Nothing on a v1 Machine makes torque, so the autopilot turns the car to point
-- its thrust (the same not-physical rig the player has in Deep).
--
-- Route: a straight chord from Night City to Monza runs through the Earth, so the route is a chain of waypoints along the
-- great circle, each raised so the chord between neighbours clears the ground (R (1/cos(step/2) - 1) + margin), then a
-- descending final leg to the ARRIVAL ENVELOPE: a few km above the venue, slow. There guidance lets go -- the landing is
-- the player's.
--
-- 0.2.0 (KB-349): altitude before speed, a floor it never goes below, thrust held to what the propulsors can shed as
-- heat, and a refusal (with the numbers) for a Machine whose sustained thrust cannot hold it up.
local Core = NcmCore

Core.define("space.guidance", function(C)
    local M = { version = "0.2.0" }
    local D = C.get("space.deep")
    local V = D.vec

    M.STEP_DEG = 8                 -- great-circle spacing of route waypoints
    M.MARGIN_M = 30000             -- extra clearance above the chord's sagitta
    M.ARRIVE_ABOVE_M = 3000        -- the envelope centre, above the venue
    M.ARRIVE_RADIUS_M = 6000       -- horizontal
    M.ARRIVE_SPEED = 150           -- m/s
    M.CRUISE_MAX = 7000            -- m/s ceiling (just under orbital speed)
    M.WAYPOINT_RADIUS_M = 40000    -- horizontal (surface) distance at which a waypoint counts as passed
    M.FLOOR_M = 2500               -- guidance never takes the Machine below this, above the venue's ground
    -- A venue a high-fidelity HOST will take (Assetto Corsa): the host receives the Machine low and slow, so it drops
    -- onto the circuit instead of falling 3 km (owner, 2026-10-06: "I don't fall out of the sky gracefully").
    M.HOST_ARRIVE_ABOVE_M = 80
    M.HOST_ARRIVE_SPEED = 12
    M.HOST_ARRIVE_RADIUS_M = 600
    M.VZ_MAX = 250                 -- m/s: the steepest climb or descent it asks for
    M.K_ALT, M.K_VZ, M.K_VH = 0.02, 0.5, 0.15   -- altitude -> vertical speed; vertical / horizontal speed -> accel
    M.HEAT_RESERVE = 0.85          -- above this share of a device's thermal limit, run it only at what it can shed
    M.G_SURFACE = 9.81
    M.SUSTAIN_MIN_TW = 1.15        -- sustained thrust / weight guidance needs to hold the Machine up, with a margin

    local function slerpLatLon(la1, lo1, la2, lo2, f)
        local a = D.llaToEcef(la1, lo1, 0)
        local b = D.llaToEcef(la2, lo2, 0)
        local ua, ub = V.unit(a), V.unit(b)
        local om = math.acos(math.max(-1, math.min(1, V.dot(ua, ub))))
        if om < 1e-9 then return la1, lo1 end
        local s1, s2 = math.sin((1 - f) * om) / math.sin(om), math.sin(f * om) / math.sin(om)
        local p = V.add(V.scale(ua, s1), V.scale(ub, s2))
        local la, lo = D.ecefToLla(V.scale(p, D.R))
        return la, lo
    end

    --- A route from the Machine's current position to a venue. Returns { venue, waypoints = { {lat,lon,alt,p}... },
    --- arrival = {lat,lon,alt,p}, distanceM }.
    function M.plan(state, venue)
        local host = venue.host == "assetto_corsa"
        local above = host and M.HOST_ARRIVE_ABOVE_M or M.ARRIVE_ABOVE_M
        local la0, lo0 = D.ecefToLla(state.p)
        local dist = D.distance(la0, lo0, venue.lat, venue.lon)
        local theta = dist / D.R
        local n = math.max(1, math.ceil(math.deg(theta) / M.STEP_DEG))
        local step = theta / n
        local hClear = D.R * (1 / math.cos(step / 2) - 1) + M.MARGIN_M
        local wps = {}
        for i = 1, n - 1 do
            local la, lo = slerpLatLon(la0, lo0, venue.lat, venue.lon, i / n)
            local alt = math.max(hClear, M.ARRIVE_ABOVE_M)
            wps[#wps + 1] = { lat = la, lon = lo, alt = alt, p = D.llaToEcef(la, lo, alt) }
        end
        local aAlt = (venue.alt or 0) + above
        local arrival = { lat = venue.lat, lon = venue.lon, alt = aAlt, p = D.llaToEcef(venue.lat, venue.lon, aAlt) }
        return { venue = venue, waypoints = wps, arrival = arrival, distanceM = dist, next = 1, phase = "cruise",
            arriveAbove = above, arriveSpeed = host and M.HOST_ARRIVE_SPEED or M.ARRIVE_SPEED,
            arriveRadius = host and M.HOST_ARRIVE_RADIUS_M or M.ARRIVE_RADIUS_M }
    end

    -- ------------------------------------------------------------------------------------------ L334: the KSA border
    -- Owner: "simply set the Guidance waypoint to the KSA border". Deep ends at Earth's sphere of influence; past it the
    -- Kitten Space Agency host flies the Machine (its real-scale Sol, its time warp). The route has no waypoints: climb
    -- out of the thick air, then burn along the INERTIAL velocity with an outward bias (energy gained fastest, never
    -- falling back), full throttle, all the way -- the owner's torch profile (~1 g, ~3-4 h). It arrives fast; KSA takes
    -- the Machine at that velocity.
    -- L335: KSA's OWN Earth sphere of influence (measured from KSA 2026.10.10 by NcmKsa: 0.9431 a (m/M)^0.4 = 871,696 km),
    -- and the handoff 2 % inside it: a state outside it is not an Earth orbit in KSA (CreateFromStateCci throws), and inside
    -- it KSA carries the Machine out of Earth's sphere itself
    M.KSA_SOI_M = 871696116
    M.BORDER = { id = "ksa_border", name = "KSA border - Earth's sphere of influence", region = "854,000 km from Earth",
        radiusM = math.floor(0.98 * M.KSA_SOI_M), host = "ksa", border = true }
    M.BORDER_CLIMB_M = 40000       -- straight up until here: no lingering in the air at speed
    M.BORDER_MIN_VR = 300          -- m/s outward: below it the burn leans further outward
    -- KB-373: burn to this inertial speed, then coast. A torch burning all the way spends sqrt(2 d a) of delta-v -- MORE
    -- the stronger the drive (30 kN arrived with 25 kg of 400 in simulation); at 120 km/s the trip takes the same ~3.4 h.
    M.BORDER_CRUISE_V = 120000

    function M.planBorder(state)
        local r = V.len(state.p)
        return { kind = "border", venue = M.BORDER, waypoints = {}, arrival = { radiusM = M.BORDER.radiusM },
            distanceM = math.max(0, M.BORDER.radiusM - r), next = 1, phase = "climb" }
    end

    --- A target by id: the KSA border or an Earth venue (VN). For records and pickers.
    function M.target(id, VN)
        if id == M.BORDER.id then return M.BORDER end
        return VN and VN.get and VN.get(id) or nil
    end

    --- Plan to a target (border or venue).
    function M.planTo(state, target)
        if target and target.border then return M.planBorder(state) end
        return M.plan(state, target)
    end

    local function borderCommand(route, state, aMax)
        local p, v = state.p, state.v
        local r = V.len(p)
        local _, _, alt = D.ecefToLla(p)
        local up = V.unit(p)
        local vi = D.inertialVel(p, v)
        local vr = V.dot(v, up)
        local dir, phase
        if alt < M.BORDER_CLIMB_M then
            dir, phase = up, "climb"
        else
            -- prograde (inertial) plus an outward lean that grows when the climb rate is low
            local lean = math.max(0.3, math.min(2.0, (M.BORDER_MIN_VR - vr) / 200 + 0.5))
            dir, phase = V.unit(V.add(V.unit(vi), V.scale(up, lean))), "escape"
        end
        local d = math.max(0, route.venue.radiusM - r)
        -- cruise reached and climbing out fast: coast, pointing along the way (the drive idles; nothing is spent)
        if phase == "escape" and V.len(vi) >= M.BORDER_CRUISE_V and vr > 0 then
            route.phase = "coast"
            return { dir = dir, throttle = 0, phase = "coast", target = route.venue.name, distanceM = d, etaS = d / math.max(1, vr), vWant = nil }
        end
        local a = math.max(0.1, aMax - D.GM / (r * r) * math.max(0, V.dot(dir, up)))
        local eta = (-vr + math.sqrt(math.max(0, vr * vr + 2 * a * d))) / a
        route.phase = phase
        return { dir = dir, throttle = 1, phase = phase, target = route.venue.name, distanceM = d, etaS = eta, vWant = nil }
    end

    --- Can this Machine reach the border on what it carries? The torch profile at its sustained acceleration needs about
    --- a*t of delta-v (with sqrt(2d/a) for t) plus escaping Earth's well from here; the rocket equation gives what the
    --- propellant of its main drive buys. Returns ok, needMps, haveMps.
    function M.borderBudget(state, massKg, thrustN, ispS, propKg)
        local r = V.len(state.p)
        local d = math.max(0, M.BORDER.radiusM - r)
        local a = math.max(0.1, thrustN / math.max(1, massKg))
        local t = math.sqrt(2 * d / a)
        local need = math.min(a * t, M.BORDER_CRUISE_V) + math.sqrt(2 * D.GM / r) * 0.3     -- burn to cruise (KB-373); gravity losses rough, stated
        local mDry = math.max(1, massKg - propKg)
        local have = ispS * M.G_SURFACE * math.log(massKg / mDry)
        return have >= need, need, have
    end

    --- KB-376: put Guidance's command onto the pilot's: its throttles, and its attitude -- `torque` (normalised, attitude
    --- sets only) or `torqueNm` (absolute, when an engine gimbals: L334). Live, only `torque` was copied, so a gimballed
    --- Machine was never steered and fell; the simulation passed the whole command and flew. One function for both now.
    function M.apply(cmd, gc)
        cmd.throttle = cmd.throttle or {}
        for id, th in pairs(gc.throttle or {}) do cmd.throttle[id] = th end
        if gc.torqueNm then cmd.torqueNm, cmd.torque = gc.torqueNm, nil
        elseif gc.torque then cmd.torque, cmd.torqueNm = gc.torque, nil end
        return cmd
    end

    --- Is the Machine inside the arrival envelope?
    function M.arrived(route, state)
        if route.kind == "border" then return V.len(state.p) >= route.venue.radiusM end
        local la, lo, alt = D.ecefToLla(state.p)
        local d = D.distance(la, lo, route.arrival.lat, route.arrival.lon)
        local v = route.venue
        local above, speed = route.arriveAbove or M.ARRIVE_ABOVE_M, route.arriveSpeed or M.ARRIVE_SPEED
        return d <= (route.arriveRadius or M.ARRIVE_RADIUS_M) and alt >= (v.alt or 0) + above / 3 and alt <= (v.alt or 0) + above * 2.7
            and V.len(state.v) <= speed
    end

    --- What the installed sustained devices can push (N), honestly: `sustainedN` is what they hold without overheating
    --- (throttle = heat rejection / heat made), `nowN` what they may give this instant, and `caps` the per-device throttle
    --- ceiling that keeps them below their thermal shutdown (KB-349: the 06:37 flight commanded 96 % on an RP-16 that
    --- sheds a third of its heat; it cut out at 30 km and again on the way down, and the Machine fell into the Earth).
    ---
    --- `noHeat` (the DEVELOPMENT heat waiver, owner 2026-10-06): heat is not modelled, so every propulsor gives all of it.
    function M.thrustBudget(devices, state, noHeat)
        local sustained, now, caps = 0, 0, {}
        for _, d in ipairs(devices or {}) do
            if d.kind == "reaction_engine" then
                local T, heat, th = d.perf.thrustN or 0, d.perf.heatKw or 0, d.thermal
                if noHeat then th = nil end
                local frac = (th and heat > 0) and math.min(1, (th.rejectKw or 0) / heat) or 1
                local st = state and state.dev and state.dev[d.componentId]
                local cap = 1
                if st and th and th.limitK then
                    if st.hot then cap = 0
                    elseif st.heatK >= M.HEAT_RESERVE * th.limitK then cap = frac end
                end
                sustained, now, caps[d.componentId] = sustained + T * frac, now + T * cap, cap
            end
        end
        return sustained, now, caps
    end

    --- Can guidance fly this Machine at all? It has to hold the Machine up on thrust it can keep making.
    function M.feasible(sustainedN, massKg)
        local tw = sustainedN / (math.max(1, massKg) * M.G_SURFACE)
        if tw >= M.SUSTAIN_MIN_TW then return true, tw end
        return false, tw, ("its propulsors hold %.0f kN without overheating and it weighs %.0f kN (thrust/weight %.2f; guidance needs %.2f)")
            :format(sustainedN / 1000, massKg * M.G_SURFACE / 1000, tw, M.SUSTAIN_MIN_TW)
    end

    --- One autopilot decision. `aMax` = what the Machine's thrust can do right now (m/s^2, thrust / mass). Returns
    --- { dir (ECEF unit: where to point the thrust), throttle 0..1 (of aMax), phase, target, distanceM, etaS }.
    ---
    --- ALTITUDE FIRST (KB-349): the vertical channel gets the thrust it needs before the horizontal one sees any. The old
    --- single velocity error was dominated by a 7 km/s cruise demand, so once clipped it carried almost nothing upward:
    --- engaged at 21 km falling 409 m/s, the Hella went down at a constant ~405 m/s on full thrust into the ground. The
    --- descent rate is also bounded by what the spare thrust can still stop above the floor.
    function M.command(route, state, aMax)
        if route.kind == "border" then return borderCommand(route, state, aMax) end
        local p, v = state.p, state.v
        local la, lo, alt = D.ecefToLla(p)
        local target, final = nil, false
        while route.next <= #route.waypoints do
            local w = route.waypoints[route.next]
            if D.distance(la, lo, w.lat, w.lon) < M.WAYPOINT_RADIUS_M then route.next = route.next + 1 else break end
        end
        if route.next <= #route.waypoints then target = route.waypoints[route.next] else target, final = route.arrival, true end
        local hT = D.distance(la, lo, target.lat, target.lon)
        -- remaining surface path: to the current target, then along the rest of the chain
        local rest, pla, plo = 0, target.lat, target.lon
        if not final then
            for i = route.next + 1, #route.waypoints do
                local w = route.waypoints[i]
                rest = rest + D.distance(pla, plo, w.lat, w.lon); pla, plo = w.lat, w.lon
            end
            rest = rest + D.distance(pla, plo, route.arrival.lat, route.arrival.lon)
        end
        local remaining = hT + rest

        local up = V.unit(p)
        local g = V.len(D.gravity(p))
        local vv = V.dot(v, up)
        local vhV = V.add(v, V.scale(up, -vv))
        local vh = V.len(vhV)
        -- the part of gravity the orbital motion already carries (v_h^2 / r) is not compensated twice
        local gNet = math.max(0, g - vh * vh / V.len(p))

        -- vertical: toward the target's altitude, never down faster than the spare thrust can stop above the floor
        -- the floor keeps the Machine high on the way; on the final leg it may come down to the envelope
        -- L331: hold the cruise floor until the venue is close (terrain lies between places); only then come down low
        local near = final and hT < M.LOW_APPROACH_M
        local floor = (route.venue.alt or 0) + (near and math.min(M.FLOOR_M, (route.arriveAbove or M.ARRIVE_ABOVE_M) * 0.6) or M.FLOOR_M)
        local altT = math.max(target.alt, floor)
        local aUp = math.max(0.1, aMax - gNet)
        local vzWant = math.max(-M.VZ_MAX, math.min(M.VZ_MAX, M.K_ALT * (altT - alt)))
        vzWant = math.max(vzWant, -math.sqrt(2 * 0.6 * aUp * math.max(0, alt - floor)))
        if alt < floor then vzWant = math.max(vzWant, 30) end
        local az = math.max(0, math.min(aMax, gNet + M.K_VZ * (vzWant - vv)))

        -- horizontal, with what is left: a speed that can still be braked to the envelope over the distance left
        local remA = math.sqrt(math.max(0, aMax * aMax - az * az))
        local aBrakeH = math.max(0.3, 0.6 * math.sqrt(math.max(0, aMax * aMax - gNet * gNet)))
        local aSpeed = route.arriveSpeed or M.ARRIVE_SPEED
        local vhWant = math.min(M.CRUISE_MAX, math.sqrt(aSpeed * aSpeed + 2 * aBrakeH * remaining))
        if final and hT < 2000 then vhWant = math.min(vhWant, aSpeed * 0.5, hT / 20) end
        local toT = V.add(target.p, V.scale(p, -1))
        local toH = V.add(toT, V.scale(up, -V.dot(toT, up)))
        local dirH = V.len(toH) > 1 and V.unit(toH) or { 0, 0, 0 }
        local errH = V.scale(V.add(V.scale(dirH, vhWant), V.scale(vhV, -1)), M.K_VH)
        local el = V.len(errH)
        if el > remA and el > 0 then errH = V.scale(errH, remA / el) end

        local aCmd = V.add(V.scale(up, az), errH)
        local mag = V.len(aCmd)
        local throttle = aMax > 0 and math.min(1, mag / aMax) or 0
        local eta = remaining / math.max(50, (vh + vhWant) / 2)
        route.phase = final and (hT < 20000 and "arriving" or "descent") or "cruise"
        return { dir = mag > 0 and V.unit(aCmd) or up, throttle = throttle, phase = route.phase, target = target,
            distanceM = remaining, etaS = eta, vWant = vhWant, altTarget = altT }
    end

    --- L331: GUIDANCE ON THE FULL MACHINE MODEL. One decision for an `engineering.flightmodel` machine `m` in dynamics
    --- state `s`: the same altitude-first command as above, then the Machine's REAL thrust axis is turned toward it --
    --- by its attitude parts (a PD law on its own inertia, torque within what the parts make) or, on the development
    --- server only, by the labelled waiver -- and the engines are throttled down while the axis is off target.
    --- Returns cmd (for engineering.dynamics), waiver ({ dir, axis, rate } or nil), info { phase, distanceM, etaS, vWant, align }.
    function M.fly(route, m, s, opts)
        opts = opts or {}
        local Dyn = C.get("engineering.dynamics")
        local F = C.get("engineering.flightmodel")
        local mass = Dyn.mass(m, s)
        local nowN, caps = 0, {}
        for i, d in ipairs(m.devices) do
            if d.kind == "reaction_engine" then
                local th, heat, st = d.thermal, d.perf.heatKw or 0, s.dev and s.dev[i]
                local frac = (th and heat > 0) and math.min(1, (th.rejectKw or 0) / heat) or 1
                local cap = 1
                if not opts.devHeat and st and th and th.limitK then
                    if st.hot then cap = 0 elseif st.heatK >= M.HEAT_RESERVE * th.limitK then cap = frac end
                end
                caps[i] = cap
                nowN = nowN + (d.perf.thrustN or 0) * cap
            end
        end
        local cmd0 = M.command(route, { p = s.pos, v = s.vel }, nowN / math.max(1, mass))
        local axisB = F.mainAxis(m) or { 0, 1, 0 }
        local R = s.rot
        local curW = { R[1][1] * axisB[1] + R[1][2] * axisB[2] + R[1][3] * axisB[3], R[2][1] * axisB[1] + R[2][2] * axisB[2] + R[2][3] * axisB[3],
            R[3][1] * axisB[1] + R[3][2] * axisB[2] + R[3][3] * axisB[3] }
        local align = math.max(0, V.dot(V.unit(curW), cmd0.dir))
        local cmd = { throttle = {} }
        local waiver = nil
        if opts.waiver then
            waiver = { dir = cmd0.dir, axis = axisB, rate = 1.0 }
        else
            -- turn about the axis that takes the thrust axis onto the wanted direction, damped by the spin it already has
            local errW = V.cross(V.unit(curW), cmd0.dir)
            local errB = { R[1][1] * errW[1] + R[2][1] * errW[2] + R[3][1] * errW[3], R[1][2] * errW[1] + R[2][2] * errW[2] + R[3][2] * errW[3],
                R[1][3] * errW[1] + R[2][3] * errW[2] + R[3][3] * errW[3] }
            local tmax, gimballed = 0, false
            for _, at in ipairs(m.attitude or {}) do tmax = tmax + (at.perf.torqueNm or 0) end
            for _, d in ipairs(m.devices) do if d.kind == "reaction_engine" and (d.perf.gimbalDeg or 0) > 0 then gimballed = true end end
            if gimballed then
                -- L334: an absolute torque request; the gimbals trim the engines and steer first, the attitude sets take
                -- the rest (engineering.dynamics)
                cmd.torqueNm = {}
                for a = 1, 3 do cmd.torqueNm[a] = m.inertia[a] * (M.K_ATT * errB[a] - M.K_RATE * (s.omega[a] or 0)) end
            elseif tmax > 0 then
                -- feed-forward: cancel the torque the engines themselves will make (an engine off the CoM line pitches it)
                local ff = { 0, 0, 0 }
                for i, d in ipairs(m.devices) do
                    if d.kind == "reaction_engine" then
                        local f = V.scale(d.dir, (d.perf.thrustN or 0) * cmd0.throttle * (caps[i] or 1))
                        local r = V.add(d.at, V.scale(m.com, -1))
                        ff = V.add(ff, V.cross(r, f))
                    end
                end
                cmd.torque = {}
                for a = 1, 3 do
                    local want = m.inertia[a] * (M.K_ATT * errB[a] - M.K_RATE * (s.omega[a] or 0)) - ff[a]
                    cmd.torque[a] = math.max(-1, math.min(1, want / tmax))
                end
            end
            align = align ^ 4    -- do not burn sideways
        end
        for i, d in ipairs(m.devices) do
            if d.kind == "reaction_engine" then cmd.throttle[i] = cmd0.throttle * (caps[i] or 1) * (opts.waiver and 1 or align) end
        end
        return cmd, waiver, { phase = cmd0.phase, distanceM = cmd0.distanceM, etaS = cmd0.etaS, vWant = cmd0.vWant, align = align,
            target = cmd0.target }
    end
    M.K_ATT, M.K_RATE = 1.2, 2.2
    M.LOW_APPROACH_M = 15000      -- the low envelope is flown only this close to the venue

    --- The ground under the Machine for a "came down" test: a venue's own ground when it is close, else sea level.
    function M.groundBelow(route, lat, lon)
        local v = route and route.venue
        if v and v.border then return 0 end
        if v and D.distance(lat, lon, v.lat, v.lon) < 10000 then return v.alt or 0 end
        return 0
    end

    --- Point the Machine's sustained thrust along `dir`: the ATTITUDE ASSIST. Turns the basis so that the summed thrust
    --- axis of the installed sustained devices (machine frame) lies along `dir`, at most `maxRad` this step.
    function M.point(basis, axisLocal, dir, maxRad)
        local cur = D.machineToEcef(axisLocal, basis)
        cur = V.unit(cur)
        local c = math.max(-1, math.min(1, V.dot(cur, dir)))
        local ang = math.acos(c)
        if ang < 1e-6 then return basis end
        local k = V.cross(cur, dir)
        if V.len(k) < 1e-9 then k = basis.up end
        k = V.unit(k)
        local a = math.min(ang, maxRad or ang)
        local function rot(x)
            local cc, s = math.cos(a), math.sin(a)
            local kv = V.cross(k, x)
            local kd = V.dot(k, x) * (1 - cc)
            return { x[1] * cc + kv[1] * s + k[1] * kd, x[2] * cc + kv[2] * s + k[2] * kd, x[3] * cc + kv[3] * s + k[3] * kd }
        end
        basis.right, basis.forward, basis.up = V.unit(rot(basis.right)), V.unit(rot(basis.forward)), V.unit(rot(basis.up))
        return basis
    end

    return M
end)
