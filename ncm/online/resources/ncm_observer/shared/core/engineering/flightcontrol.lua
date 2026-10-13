-- ncm-core module: engineering.flightcontrol
--
-- 2026-10-12 (owner: "make it fly ... aren't we using our engineering parts and vfx"): the FLY-BY-WIRE of a lift-engine
-- Machine -- what an installed flight computer (`flight_computer`, the ZTC-FC1) does. It pushes nothing. Every frame it
-- reads the stick and the Machine's real state (attitude, spin, vertical speed, mass) and turns them into the commands
-- `engineering.dynamics` already understands:
--
--   * a THROTTLE per lift device (every installed thrust device whose line points up through the body): air-breathing
--     engines first, rockets only for what the air can no longer give (a fusion drive is for the thin air, not the hover);
--   * a body TORQUE request (`cmd.torqueNm`), which the dynamics meets with what the parts physically have -- the
--     engines' swivel (gimbal) first, then any attitude set. No torque is invented here.
--
-- The stick asks for ATTITUDE and CLIMB, the way every AV in Night City flies: pitch tilts the Machine (and its lift)
-- toward where you want to go, roll banks it sideways, yaw turns it at a rate, lift asks for a vertical speed. Let go
-- and it levels itself and holds its height. On the ground with no lift asked it sits idle.
--
-- Frames as engineering.dynamics: body x right, y forward, z up; `s.rot` rows (world = rot * body); `s.omega` body rad/s
-- (x = pitch up, y = roll right, z = yaw LEFT).
local Core = NcmCore

Core.define("engineering.flightcontrol", function(C)
    local M = { version = "0.1.0" }
    local Sys = C.get("engineering.systems")

    M.DEFAULTS = { maxTiltDeg = 22, maxClimbMs = 9, maxYawRateDegS = 45 }
    M.K_ATT = 2.2        -- 1/s: attitude error -> wanted turn rate
    M.K_RATE = 5.0       -- 1/s: turn-rate error -> wanted angular acceleration
    M.K_CLIMB = 1.6      -- 1/s: vertical-speed error -> wanted vertical acceleration
    M.MAX_ANG_ACC = 2.5  -- rad/s^2: the most the computer asks of the airframe about any axis

    local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

    --- The Machine's flight computer perf (the first installed one), or nil: no computer, no fly-by-wire.
    function M.computer(devices)
        for _, d in ipairs(devices or {}) do
            if d.kind == "flight_computer" then
                local p = {}
                for k, v in pairs(M.DEFAULTS) do p[k] = v end
                for k, v in pairs(d.perf or {}) do p[k] = v end
                return p
            end
        end
        return nil
    end

    --- Lift devices of an assembled machine: index, kind, how much of their line points up (body z).
    local LIFT_KINDS = { jet = true, propeller = true, reaction_engine = true }
    function M.liftDevices(m)
        local out = {}
        for i, d in ipairs(m.devices or {}) do
            if LIFT_KINDS[d.kind] and d.dir and d.dir[3] > 0.7 then
                out[#out + 1] = { index = i, device = d, up = d.dir[3], air = d.kind ~= "reaction_engine" }
            end
        end
        return out
    end

    --- Pitch (nose up +) and roll (right wing down +) in radians, from a rotation (rows; world = rot * body).
    function M.attitude(rot)
        local fz = rot[3][2]          -- forward's world z
        local rz = rot[3][1]          -- right's world z
        return math.asin(clamp(fz, -1, 1)), math.asin(clamp(-rz, -1, 1))
    end

    --- One frame. `stick` = { pitch, roll, yaw, lift } each -1..1 (pitch + = fly forward, roll + = bank right, yaw + =
    --- turn right, lift + = climb). `ctx` = { mass (kg), inertia ({x,y,z} kg m^2), rho, g (m/s^2, positive), contact,
    --- perf (M.computer) }. Returns cmd ({ throttle = { [deviceIndex] = 0..1 }, torqueNm = {x,y,z} }) and a report.
    function M.step(m, s, stick, ctx)
        ctx = ctx or {}
        stick = stick or {}
        local p = ctx.perf or M.DEFAULTS
        local g = ctx.g or 9.81
        local mass = math.max(1, ctx.mass or 1000)
        local I = ctx.inertia or m.inertia or { 1000, 1000, 1000 }
        local rho = ctx.rho or Sys.RHO0
        local sp, sr = clamp(tonumber(stick.pitch) or 0, -1, 1), clamp(tonumber(stick.roll) or 0, -1, 1)
        local sy, sl = clamp(tonumber(stick.yaw) or 0, -1, 1), clamp(tonumber(stick.lift) or 0, -1, 1)
        local cmd = { throttle = {}, torqueNm = { 0, 0, 0 } }
        local rep = { idle = false }

        -- parked: on the ground with no climb asked, everything idles (it does not hover a hair above the pad)
        if ctx.contact and sl <= 0 then
            for _, l in ipairs(M.liftDevices(m)) do cmd.throttle[l.index] = 0 end
            rep.idle = true
            return cmd, rep
        end

        -- attitude: the stick asks for a tilt; the computer turns that into a rate, the rate into a torque
        local tilt = math.rad(p.maxTiltDeg or M.DEFAULTS.maxTiltDeg)
        local pitch, roll = M.attitude(s.rot)
        local wantPitch, wantRoll = -sp * tilt, sr * tilt        -- forward = nose DOWN (the lift leans the way you go)
        local w = s.omega or { 0, 0, 0 }
        local wantW = {
            M.K_ATT * (wantPitch - pitch),
            M.K_ATT * (wantRoll - roll),
            -sy * math.rad(p.maxYawRateDegS or M.DEFAULTS.maxYawRateDegS),   -- yaw right = negative about +z
        }
        for a = 1, 3 do
            local acc = clamp(M.K_RATE * (wantW[a] - (w[a] or 0)), -M.MAX_ANG_ACC, M.MAX_ANG_ACC)
            cmd.torqueNm[a] = acc * (I[a] or 1000)
        end
        rep.pitch, rep.roll = pitch, roll

        -- climb: the stick asks for a vertical speed; hold it with the lift along the body's up
        local vz = s.vel and s.vel[3] or 0
        local wantVz = sl * (p.maxClimbMs or M.DEFAULTS.maxClimbMs)
        local az = M.K_CLIMB * (wantVz - vz) + g
        local upZ = math.max(0.5, s.rot[3][3])                  -- body up's world z: lift lost to the tilt comes back here
        local need = math.max(0, mass * az / upZ)

        -- share it out: the air first, rockets for what is left
        local lifts = M.liftDevices(m)
        local airCap, rocketCap = 0, 0
        local air = {}
        for _, l in ipairs(lifts) do
            local cap = Sys.thrustAt(l.device.perf, rho, 1) * l.up
            l.cap = cap
            if l.air then airCap = airCap + cap; air[#air + 1] = l else rocketCap = rocketCap + cap end
        end
        local uAir = airCap > 0 and clamp(need / airCap, 0, 1) or 0
        local left = math.max(0, need - uAir * airCap)
        local uRocket = rocketCap > 0 and clamp(left / rocketCap, 0, 1) or 0
        local com = m.com or { 0, 0, 0 }
        -- the torque the rockets' fixed lines make at that throttle (an off-centre FD-1): the fans balance it out
        local rocketTx, rocketTy = 0, 0
        for _, l in ipairs(lifts) do
            cmd.throttle[l.index] = l.air and uAir or uRocket
            if not l.air then
                local f = uRocket * l.cap
                rocketTx = rocketTx + (l.device.at[2] - com[2]) * f
                rocketTy = rocketTy - (l.device.at[1] - com[1]) * f
            end
        end
        -- pitch and roll by DIFFERENTIAL throttle across the fans (a multi-engine VTOL's own way: no sideways push), the
        -- least change that keeps their total: F = F0 + A^T (A A^T)^-1 (b - A F0), A = rows { 1 ; y ; -x } about the CoM
        local wantTx, wantTy = cmd.torqueNm[1] - rocketTx, cmd.torqueNm[2] - rocketTy
        if #air >= 3 and uAir > 0 then
            local S = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
            local rows = {}
            local have = { 0, 0, 0 }
            for k, l in ipairs(air) do
                local a = { 1, l.device.at[2] - com[2], -(l.device.at[1] - com[1]) }
                rows[k] = a
                local f0 = uAir * l.cap
                for i = 1, 3 do
                    have[i] = have[i] + a[i] * f0
                    for j = 1, 3 do S[i][j] = S[i][j] + a[i] * a[j] end
                end
            end
            local e = { 0, wantTx - have[2], wantTy - have[3] }
            -- solve S y = e (3x3, Cramer)
            local function det(Mx) return Mx[1][1] * (Mx[2][2] * Mx[3][3] - Mx[2][3] * Mx[3][2]) - Mx[1][2] * (Mx[2][1] * Mx[3][3] - Mx[2][3] * Mx[3][1]) + Mx[1][3] * (Mx[2][1] * Mx[3][2] - Mx[2][2] * Mx[3][1]) end
            local D = det(S)
            if math.abs(D) > 1e-9 then
                local y = {}
                for c = 1, 3 do
                    local Mc = { { S[1][1], S[1][2], S[1][3] }, { S[2][1], S[2][2], S[2][3] }, { S[3][1], S[3][2], S[3][3] } }
                    for rr = 1, 3 do Mc[rr][c] = e[rr] end
                    y[c] = det(Mc) / D
                end
                local got = { 0, 0, 0 }
                for k, l in ipairs(air) do
                    local a = rows[k]
                    local f = uAir * l.cap + a[1] * y[1] + a[2] * y[2] + a[3] * y[3]
                    local u = clamp(f / l.cap, 0, 1)
                    cmd.throttle[l.index] = u
                    for i = 2, 3 do got[i] = got[i] + a[i] * u * l.cap end
                end
                -- what the throttles made is no longer asked of the swivel; yaw (and any shortfall) still is
                cmd.torqueNm[1] = wantTx - got[2]
                cmd.torqueNm[2] = wantTy - got[3]
            end
        end
        rep.needN, rep.airCapN, rep.rocketCapN, rep.uAir, rep.uRocket = need, airCap, rocketCap, uAir, uRocket
        rep.short = need > airCap + rocketCap + 1
        return cmd, rep
    end

    --- The body angular velocity between two rotations dt apart (rows; world = rot * body), small-angle.
    function M.omegaFrom(prev, cur, dt)
        if not prev or not cur or not dt or dt <= 0 then return { 0, 0, 0 } end
        -- D = prev^T cur (body-to-body), skew part / dt
        local D = {}
        for i = 1, 3 do
            D[i] = {}
            for j = 1, 3 do D[i][j] = prev[1][i] * cur[1][j] + prev[2][i] * cur[2][j] + prev[3][i] * cur[3][j] end
        end
        return { (D[3][2] - D[2][3]) / (2 * dt), (D[1][3] - D[3][1]) / (2 * dt), (D[2][1] - D[1][2]) / (2 * dt) }
    end

    return M
end)
