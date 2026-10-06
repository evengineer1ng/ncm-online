-- ncm-core module: space.fireball
--
-- FIREBALL (L322; doc 54 §L): an oval translated into unconstrained 3D space. One central object, a legal SHELL
-- around it (inner < |r| < outer), a required distance, five lights. No lanes, no prescribed plane, no track: a
-- racer may circle the equator, cross the poles, or keep changing plane. Who accumulates the required VALID
-- distance around the object first?
--
-- VALID DISTANCE. An odometer is exploitable (oscillate in one patch of sky for 100 km). Fireball credits ANGLE SWEPT
-- ABOUT THE CENTRE, ABOUT THE RACER'S OWN LAGGED AXIS OF ROTATION:
--   r = racer - centre, v = relative velocity
--   omega = (r x v) / |r|^2                    instantaneous angular velocity about the centre (rad/s, a vector)
--   m                                          the CREDITED AXIS: a unit vector that turns toward unit(omega) at
--                                              no more than `axisTurnRate` rad/s
--   dtheta = (omega . m) dt                    credited angle (negative when going backwards)
-- Steady motion around the object in ANY plane: m = unit(omega), full credit. A plane that keeps turning slower than
-- axisTurnRate: m follows, near-full credit -- change plane as much as you like, just not instantly. Reversing:
-- omega flips but m needs pi / axisTurnRate seconds to follow, so the way back is debited first; oscillating in a
-- patch smaller than that earns ~0, and a long out-and-back always earns less than simply carrying on round. Small
-- loops in one patch: omega sweeps the whole tangent plane while m barely moves, ~0 credit. Radial motion: omega
-- ignores it (r x v has no radial part). (L322 test finding: a LAGGED MEAN axis, the first design, flips after one
-- time constant and then pays for a long out-and-back; a turn-rate limit does not.)
--
-- The credit unit is the rule's: `angle` (default) -- metres = theta x R_ref, R_ref the shell's mid-radius, so an
-- inside line is shorter, like an oval, and the inner wall is the contested place -- or `arc` (metres = theta x |r|,
-- radius-neutral). Outside the shell nothing is credited and an out-of-bounds clock runs; past `oobMaxS` in total
-- the racer is black-flagged. The finish is timed by interpolating within the step that crosses the distance.
local Core = NcmCore

Core.define("space.fireball", function(C)
    local M = { version = "0.1.0" }

    M.DEFAULTS = { axisTurnRate = 0.02, credit = "angle", oobMaxS = 10 }

    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function len(a) return math.sqrt(dot(a, a)) end

    --- Rules: { inner, outer (m from the centre), distanceM, axisTurnRate?, credit?, oobMaxS?, centre = {x,y,z} or
    --- function(t) -> pos, vel }.
    function M.rules(r)
        local out = {}
        for k, v in pairs(M.DEFAULTS) do out[k] = v end
        for k, v in pairs(r) do out[k] = v end
        out.refRadius = out.refRadius or (out.inner + out.outer) / 2
        return out
    end

    function M.newState() return { m = { 0, 0, 0 }, theta = 0, creditM = 0, oobS = 0, t = nil, finishT = nil, dq = nil, coherence = 0 } end

    local function centreAt(rules, t)
        if type(rules.centre) == "function" then return rules.centre(t) end
        return rules.centre or { 0, 0, 0 }, { 0, 0, 0 }
    end

    --- Relative decomposition: radius, radial speed, tangential speed, angular velocity vector.
    function M.decompose(r, v)
        local R = len(r)
        if R <= 0 then return 0, 0, 0, { 0, 0, 0 } end
        local vr = dot(v, r) / R
        local w = cross(r, v)
        local k = 1 / (R * R)
        local omega = { w[1] * k, w[2] * k, w[3] * k }
        return R, vr, len(w) / R, omega
    end

    --- Advance one racer's judge by a sample (universe position and velocity at time t, dt since the last).
    --- Returns the state and an event: nil | { finished = t } | { dq = "out of bounds" } | { oob = true }.
    function M.step(rules, st, pos, vel, t, dt)
        if st.finishT or st.dq then return st, nil end
        local c, cv = centreAt(rules, t)
        local r, v = sub(pos, c), sub(vel, cv)
        local R, vr, vt, omega = M.decompose(r, v)
        st.radius, st.radialMs, st.tangentialMs = R, vr, vt
        local inside = R > rules.inner and R < rules.outer
        local wl = len(omega)
        if wl > 1e-12 then
            local u = { omega[1] / wl, omega[2] / wl, omega[3] / wl }
            if len(st.m) < 1e-9 then
                st.m = u                                     -- the first motion sets the axis: no start-up penalty
            else
                local c = math.max(-1, math.min(1, dot(st.m, u)))
                local ang = math.acos(c)
                local turn = math.min(ang, rules.axisTurnRate * dt)
                if turn > 1e-12 then
                    local ax = cross(st.m, u)
                    local al = len(ax)
                    if al < 1e-9 then ax, al = r, len(r) end    -- exactly reversed: any axis in the tangent plane
                    ax = { ax[1] / al, ax[2] / al, ax[3] / al }
                    -- Rodrigues: rotate m about ax by `turn` (m is perpendicular to ax)
                    local k = cross(ax, st.m)
                    local cs, sn = math.cos(turn), math.sin(turn)
                    st.m = { st.m[1] * cs + k[1] * sn, st.m[2] * cs + k[2] * sn, st.m[3] * cs + k[3] * sn }
                end
            end
            st.coherence = dot(st.m, u)                      -- 1 = flying exactly round the credited axis
        end
        st.t = t
        if not inside then
            st.oobS = st.oobS + dt
            if st.oobS > rules.oobMaxS then st.dq = "out of bounds"; return st, { dq = st.dq } end
            return st, { oob = true }
        end
        local dtheta = dot(omega, st.m) * dt
        local before = st.creditM
        st.theta = st.theta + dtheta
        local scale = rules.credit == "arc" and R or rules.refRadius
        st.creditM = st.creditM + dtheta * scale
        if st.creditM >= rules.distanceM and before < rules.distanceM then
            local f = (rules.distanceM - before) / (st.creditM - before)
            st.finishT = t - dt + dt * f
            return st, { finished = st.finishT }
        end
        return st, nil
    end

    --- Classification: finishers by time; the rest by credited distance; DQs last.
    function M.classify(entries)
        local rows = {}
        for _, e in ipairs(entries) do rows[#rows + 1] = e end
        table.sort(rows, function(a, b)
            local sa, sb = a.state, b.state
            if (sa.dq ~= nil) ~= (sb.dq ~= nil) then return sb.dq ~= nil end
            if (sa.finishT ~= nil) ~= (sb.finishT ~= nil) then return sa.finishT ~= nil end
            if sa.finishT and sb.finishT and sa.finishT ~= sb.finishT then return sa.finishT < sb.finishT end
            if sa.creditM ~= sb.creditM then return sa.creditM > sb.creditM end
            return tostring(a.id) < tostring(b.id)
        end)
        return rows
    end

    return M
end)
