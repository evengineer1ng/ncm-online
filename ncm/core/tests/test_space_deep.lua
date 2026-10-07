-- space.deep (L326): Night City on a real-scale Earth, the Machine handed out of REDengine and back.
local function D(T) return T.Core.get("space.deep") end
local function near(T, a, b, tol, msg) T.ok(math.abs(a - b) <= tol, (msg or "") .. (" (%s vs %s)"):format(tostring(a), tostring(b))) end

return {
    night_city_is_where_the_owner_put_it = function(T)
        local M = D(T)
        local lat, lon, alt = M.gameToLla(0, 0, 12000)
        near(T, lat, 35.37, 1e-9, "")
        near(T, lon, -120.85, 1e-9, "")
        near(T, alt, 12000, 1e-9, "")
    end,

    game_and_earth_coordinates_round_trip = function(T)
        local M = D(T)
        for _, g in ipairs({ { 0, 0, 0 }, { 3000, -4500, 12000 }, { -2400, -4300, 75 } }) do
            local la, lo, al = M.gameToLla(g[1], g[2], g[3])
            local p = M.llaToEcef(la, lo, al)
            local la2, lo2, al2 = M.ecefToLla(p)
            local x, y, z = M.llaToGame(la2, lo2, al2)
            near(T, x, g[1], 1e-3, "x"); near(T, y, g[2], 1e-3, "y"); near(T, z, g[3], 1e-3, "z")
        end
    end,

    up_in_the_game_is_up_on_earth = function(T)
        local M = D(T)
        local s = M.enter({ 0, 0, 12000 }, { 0, 0, 90 }, nil)
        local _, _, u = M.enu(35.37, -120.85)
        near(T, M.vec.dot(M.vec.unit(s.v), u), 1, 1e-9, "a vertical climb leaves vertically")
        near(T, M.vec.dot(s.basis.up, u), 1, 1e-9, "the car's up is local up")
    end,

    surface_gravity_is_one_g = function(T)
        local M = D(T)
        near(T, M.vec.len(M.gravity(M.llaToEcef(35.37, -120.85, 0))), 9.82, 0.01, "")
    end,

    a_vertical_climb_comes_back_down_near_night_city = function(T)
        local M = D(T)
        local s = M.enter({ 0, 0, 12000 }, { 0, 0, 300 }, nil)
        local lat, lon = M.impact(s.p, s.v)
        T.ok(lat, "it comes down")
        T.ok(M.distance(lat, lon, 35.37, -120.85) < 100, "straight up, straight down (no rotation in v1)")
        local _, _, t = M.impactNumeric(s.p, s.v)
        T.ok(t > 60 and t < 120, "about a minute of flight from 300 m/s (" .. tostring(t) .. " s)")
    end,

    sideways_speed_moves_the_landing = function(T)
        local M = D(T)
        local s = M.enter({ 0, 0, 12000 }, { 300, 0, 300 }, nil)
        local lat, lon = M.impact(s.p, s.v)
        local d = M.distance(lat, lon, 35.37, -120.85)
        T.ok(d > 15000, "300 m/s east for a minute lands tens of km east (" .. math.floor(d) .. " m)")
        T.ok(lon > -120.85, "and it is east")
    end,

    orbit_speed_never_comes_down = function(T)
        local M = D(T)
        local alt = 400000
        local s = M.enter({ 0, 0, alt }, { M.orbitSpeed(alt), 0, 0 }, nil)
        local lat, why = M.impact(s.p, s.v)
        T.eq(lat, nil, "a circular orbit does not hit the ground")
        T.eq(why, "orbit", "")
    end,

    thrust_follows_the_machine_basis = function(T)
        local M = D(T)
        local s = M.enter({ 0, 0, 12000 }, { 0, 0, 0 }, { forward = { x = 1, y = 0, z = 0 }, up = { x = 0, y = 0, z = 1 }, right = { x = 0, y = -1, z = 0 } })
        local f = M.machineToEcef({ 0, 1000, 0 }, s.basis)
        local e = M.enu(35.37, -120.85)
        near(T, M.vec.dot(M.vec.unit(f), e), 1, 1e-9, "forward thrust on an east-facing car pushes east")
    end,

    the_rig_keeps_the_axes_orthonormal = function(T)
        local M = D(T)
        local s = M.enter({ 0, 0, 12000 }, { 0, 0, 0 }, nil)
        for _ = 1, 5000 do M.turn(s.basis, 0.013, -0.007, 0.011) end
        local b = s.basis
        near(T, M.vec.len(b.forward), 1, 1e-9, ""); near(T, M.vec.len(b.up), 1, 1e-9, "")
        near(T, M.vec.dot(b.forward, b.up), 0, 1e-9, ""); near(T, M.vec.dot(b.right, b.forward), 0, 1e-9, "")
    end,

    the_closed_form_agrees_with_stepping = function(T)
        local M = D(T)
        for _, c in ipairs({ { 300, 0, 300 }, { -800, 400, 600 }, { 2500, 0, 1500 }, { 0, 5000, 200 } }) do
            local s = M.enter({ 0, 0, 12000 }, c, nil)
            local la1, lo1, t1 = M.impact(s.p, s.v)
            local la2, lo2, t2 = M.impactNumeric(s.p, s.v, 20000, 0.25)
            T.ok(la1 and la2, "both come down")
            T.ok(M.distance(la1, lo1, la2, lo2) < 2000, ("same landing within 2 km (%.0f m)"):format(M.distance(la1, lo1, la2, lo2)))
            T.ok(math.abs(t1 - t2) < 5, ("same flight time (%.1f vs %.1f s)"):format(t1, t2))
        end
    end,

    -- L334: the Earth rotates; Deep's frame turns with it
    a_body_at_rest_on_the_equator_feels_the_spin = function(T)
        local M = D(T)
        local p = M.llaToEcef(0, 0, 0)
        local f = M.fictitious(p, { 0, 0, 0 })
        near(T, M.vec.len(f), M.OMEGA ^ 2 * M.R, 1e-6, "centrifugal = W^2 R (~0.034 m/s^2)")
        T.ok(M.vec.dot(f, M.vec.unit(p)) > 0, "outward")
        local vi = M.inertialVel(p, { 0, 0, 0 })
        near(T, M.vec.len(vi), M.OMEGA * M.R, 1e-6, "the ground at the equator moves W R (~465 m/s) inertially")
    end,

    a_dropped_body_lands_east_of_its_start = function(T)
        local M = D(T)
        -- dropped from rest (Earth-fixed) 100 km up over the equator: Coriolis carries it east
        local s = { p = M.llaToEcef(0, 0, 100000), v = { 0, 0, 0 }, t = 0 }
        while true do
            local _, _, alt = M.ecefToLla(s.p)
            if alt <= 0 then break end
            M.step(s, 0.05, nil)
        end
        local _, lon = M.ecefToLla(s.p)
        T.ok(lon > 0, ("lands east of the drop point (%.4f deg)"):format(lon))
    end,

    a_circular_orbit_reads_as_one = function(T)
        local M = D(T)
        local alt = 400000
        local p = M.llaToEcef(0, 0, alt)
        local vInertial = math.sqrt(M.GM / (M.R + alt))
        -- prograde (east) at circular speed, expressed Earth-fixed: subtract the frame's own motion
        local vFixed = { 0, vInertial - M.OMEGA * (M.R + alt), 0 }
        local o = M.orbit(p, vFixed)
        T.ok(not o.escape, "bound")
        near(T, o.apoM, alt, 50, "apoapsis at 400 km")
        near(T, o.periM, alt, 50, "periapsis at 400 km")
        local esc = M.orbit(p, { 0, 12000, 0 })
        T.ok(esc.escape, "12 km/s at 400 km escapes")
    end,

    the_closed_form_is_one_evaluation = function(T)
        local M = D(T)
        local s = M.enter({ 0, 0, 400000 }, { 7000, 0, 0 }, nil)
        local t0 = os.clock()
        for _ = 1, 1000 do M.impact(s.p, s.v) end
        T.ok(os.clock() - t0 < 0.5, "a thousand predictions in well under half a second")
    end,

    -- owner, 2026-10-06: "night = night": one sun on NCM's clock
    the_sun_follows_the_real_clock = function(T)
        local D = T.Core.get("space.deep")
        local function above(utc, lat, lon) local _, _, u = D.enu(lat, lon); return D.vec.dot(D.sunAt(utc), u) end
        -- 2026-06-21 20:00 UTC = ~12:00 solar at Night City (120.85 W): high summer sun
        local noonJune = 1782072000
        T.ok(above(noonJune, D.ORIGIN.lat, D.ORIGIN.lon) > 0.95, "summer solar noon: the sun is nearly overhead Night City")
        -- 12 hours later: midnight there, and daylight in Italy
        T.ok(above(noonJune + 12 * 3600, D.ORIGIN.lat, D.ORIGIN.lon) < -0.3, "solar midnight: night in Night City")
        T.ok(above(noonJune + 12 * 3600, 45.6156, 9.2811) > 0.5, "while it is day at Monza")
        -- the December sun is lower at noon than the June one
        T.ok(above(noonJune + 183 * 86400, D.ORIGIN.lat, D.ORIGIN.lon) < above(noonJune, D.ORIGIN.lat, D.ORIGIN.lon) - 0.25, "winter noon is lower")
        T.ok(math.abs(D.solarHour(noonJune, D.ORIGIN.lon) - 12) < 0.1, "solar hour at Night City")
    end,
}
