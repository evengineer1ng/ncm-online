-- space.sky (L351 / IDEA-1263, L358): the NCWE space render's placement, checked against the real sky.
local function near(a, b, e) return math.abs(a - b) <= (e or 1e-6) end

-- a Deep state at Night City, `alt` m up, level, facing north (or with the axes given)
local function state(T, alt, axes)
    local D = T.Core.get("space.deep")
    local s = D.enter({ 0, 0, alt }, { 0, 0, 0 }, axes)
    return s
end

local function qrot(q, v)          -- rotate v by quaternion {i, j, k, r}
    local x, y, z, w = q[1], q[2], q[3], q[4]
    local m = { { 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w) },
        { 2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w) },
        { 2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y) } }
    return { m[1][1] * v[1] + m[1][2] * v[2] + m[1][3] * v[3], m[2][1] * v[1] + m[2][2] * v[2] + m[2][3] * v[3],
        m[3][1] * v[1] + m[3][2] * v[2] + m[3][3] * v[3] }
end

local function body(view, id) for _, b in ipairs(view.bodies) do if b.id == id then return b end end end

return {
    polaris_stands_over_the_north_at_night_citys_latitude = function(T)
        local K = T.Core.get("space.sky")
        local v = K.view(state(T, 20000), 1790000000)
        local pole = qrot(body(v, "sky_dome").q, { 0, 0, 1 })          -- the north celestial pole, in the game
        local elev = math.deg(math.asin(pole[3]))
        T.ok(near(elev, 35.37, 0.6), ("the celestial pole is %.2f deg up at 35.37 N"):format(elev))
        T.ok(pole[2] > 0.75 and math.abs(pole[1]) < 0.02, "and due north, ahead of a car facing north")
    end,

    the_sky_turns_with_the_earth = function(T)
        local K = T.Core.get("space.sky")
        local s = state(T, 20000)
        local a = qrot(body(K.view(s, 1790000000), "sky_dome").q, { 1, 0, 0 })
        local b = qrot(body(K.view(s, 1790000000 + 3600), "sky_dome").q, { 1, 0, 0 })
        local ang = math.deg(math.acos(math.max(-1, math.min(1, a[1] * b[1] + a[2] * b[2] + a[3] * b[3]))))
        T.ok(ang > 5 and ang < 16, ("an equatorial star moves %.1f deg in an hour (15 at most, less off the meridian)"):format(ang))
    end,

    a_level_machine_has_the_earth_below_and_night_city_under_it = function(T)
        local K = T.Core.get("space.sky")
        local D = T.Core.get("space.deep")
        local s = state(T, 12000)
        local v = K.view(s, 1790000000)
        local e = body(v, "earth")
        T.eq(e.kind, 3, "just past the seam the 1 km Earth fills the view")
        T.ok(near(e.p[1], v.car[1], 1e-6) and near(e.p[2], v.car[2], 1e-6) and e.p[3] < v.car[3], "straight down")
        T.ok(v.car[3] - e.p[3] - e.r >= K.MIN_CLEAR_M - 1e-9, "never closer than the clearance")
        -- the Earth-fixed point under the Machine faces the car: the mesh's local direction to it, turned, points up
        local lat, lon = D.ecefToLla(s.p)
        local here = { math.cos(math.rad(lat)) * math.cos(math.rad(lon)), math.cos(math.rad(lat)) * math.sin(math.rad(lon)), math.sin(math.rad(lat)) }
        local g = qrot(e.q, here)
        T.ok(g[3] > 0.999, "Night City is on the top of the globe, under the car")
    end,

    pitching_up_puts_the_earth_behind = function(T)
        local K = T.Core.get("space.sky")
        local s = state(T, 30000, { forward = { 0, 0, 1 }, up = { 0, -1, 0 }, right = { 1, 0, 0 } })   -- nose straight up
        local e = body(K.view(s, 1790000000), "earth")
        local v = K.view(s, 1790000000)
        local dir = { e.p[1] - v.car[1], e.p[2] - v.car[2], e.p[3] - v.car[3] }
        local l = math.sqrt(dir[1] ^ 2 + dir[2] ^ 2 + dir[3] ^ 2)
        local fwd = { -math.sin(math.rad(v.yaw)), math.cos(math.rad(v.yaw)), 0 }
        T.ok((dir[1] * fwd[1] + dir[2] * fwd[2]) / l < -0.99, "the Earth is behind the car, where the Machine's tail points")
    end,

    sizes_fit_the_dome_and_keep_the_true_angle = function(T)
        local K = T.Core.get("space.sky")
        for _, alt in ipairs({ 12000, 400000, 36000000, 380000000 }) do
            local s = state(T, alt)
            local v = K.view(s, 1790000000)
            local e = body(v, "earth")
            T.ok(e, "Earth is drawn at " .. alt)
            T.ok(e.d <= K.BODY_MAX_M and e.d + e.r < K.DOME_HALF_M, "inside the dome at " .. alt)
            local trueAng = math.asin(K.R / (K.R + alt))
            local drawn = math.asin(math.min(1, e.r / e.d))
            if alt > 100000 then T.ok(near(drawn, trueAng, 1e-6), ("true angular size at %d m"):format(alt)) end
        end
    end,

    the_moon_is_where_the_ephemeris_puts_it = function(T)
        local K = T.Core.get("space.sky")
        local Stage = T.Core.get("space.stage")
        local D = T.Core.get("space.deep")
        local utc = 1790000000
        local s = state(T, 400000)
        local v = K.view(s, utc)
        local m = body(v, "moon")
        if not m then T.ok(v.notes[1] == "moon behind the Earth"); return end
        local G = K.frame(s)
        local rel = Stage.moonEcef(utc)
        rel = { rel[1] - s.p[1], rel[2] - s.p[2], rel[3] - s.p[3] }
        local l = math.sqrt(rel[1] ^ 2 + rel[2] ^ 2 + rel[3] ^ 2)
        local want = K.mv(G, { rel[1] / l, rel[2] / l, rel[3] / l })
        local got = { m.p[1] - v.car[1], m.p[2] - v.car[2], m.p[3] - v.car[3] }
        local gl = math.sqrt(got[1] ^ 2 + got[2] ^ 2 + got[3] ^ 2)
        T.ok(near(got[1] / gl, want[1], 1e-9) and near(got[3] / gl, want[3], 1e-9), "the Moon on its true line of sight")
        T.ok(near(math.asin(m.r / m.d), math.asin(K.MOON_R / l), 1e-6), "at its true angular size")
        -- its near side (+X of the mesh) faces the Earth's centre
        local Gm = K.frame(s)
        local mpos = Stage.moonEcef(utc)
        local ml = math.sqrt(mpos[1] ^ 2 + mpos[2] ^ 2 + mpos[3] ^ 2)
        local wantNear = K.mv(Gm, { -mpos[1] / ml, -mpos[2] / ml, -mpos[3] / ml })
        local nearSide = qrot(m.q, { 1, 0, 0 })
        T.ok(nearSide[1] * wantNear[1] + nearSide[2] * wantNear[2] + nearSide[3] * wantNear[3] > 0.9999, "its near side faces the Earth")
    end,

    -- KB-438: the car is held at its entry heading; the Machine's own yaw goes into the universe instead
    a_held_car_sees_the_universe_turn_instead = function(T)
        local K = T.Core.get("space.sky")
        local s = state(T, 20000)                                   -- facing north
        local free = K.view(s, 1790000000)
        local held = K.view(s, 1790000000, nil, 90)                  -- held facing game west (yaw +90)
        T.ok(near(held.yaw, 90, 1e-9), "the held heading is the one asked for")
        T.ok(near(free.yaw, 0, 1e-6), "unheld, the heading follows the Machine")
        -- the celestial pole sat dead ahead of the free car (north); a car held at yaw 90 still has it dead ahead
        local fp = qrot(body(free, "sky_dome").q, { 0, 0, 1 })
        local hp = qrot(body(held, "sky_dome").q, { 0, 0, 1 })
        local fwdHeld = { -math.sin(math.rad(90)), math.cos(math.rad(90)), 0 }
        T.ok(fp[2] > 0.75, "free: the pole is ahead (+Y)")
        T.ok(hp[1] * fwdHeld[1] + hp[2] * fwdHeld[2] > 0.75 and near(hp[3], fp[3], 1e-9), "held: the pole is still ahead of the car, at the same elevation")
    end,

    quaternions_are_unit_and_match_their_matrix = function(T)
        local K = T.Core.get("space.sky")
        local m = K.mm(K.rz(0.7), { { 1, 0, 0 }, { 0, math.cos(0.3), -math.sin(0.3) }, { 0, math.sin(0.3), math.cos(0.3) } })
        local q = K.quat(m)
        T.ok(near(q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2, 1, 1e-12))
        local v = qrot(q, { 0.2, -0.5, 0.8 })
        local w = K.mv(m, { 0.2, -0.5, 0.8 })
        T.ok(near(v[1], w[1], 1e-9) and near(v[2], w[2], 1e-9) and near(v[3], w[3], 1e-9))
    end,
}
