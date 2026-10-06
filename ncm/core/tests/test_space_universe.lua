-- space.universe (L317; doc 51 §6): Universe Authority v0 -- the anchor, the bubble and its rebase invariant,
-- proxies at true angular size, the transition phases under the 2^14 ceiling, and double precision at solar scale.
local function U(T) return T.Core.get("space.universe") end

local function near(a, b, eps) return math.abs(a - b) <= eps end
local function vnear(a, b, eps) return near(a[1], b[1], eps) and near(a[2], b[2], eps) and near(a[3], b[3], eps) end

return {
    night_city_round_trips_through_the_universe = function(T)
        local S = U(T)
        for _, p in ipairs({ { 0, 0, 0 }, { 111.1, -331.9, 16383.9 }, { -2500, 4000, 30 } }) do
            T.ok(vnear(S.universeToCity(S.cityToUniverse(p)), p, 1e-6), "city -> universe -> city is exact")
        end
    end,

    the_ceiling_is_an_altitude_and_the_seam_sits_under_it = function(T)
        local S = U(T)
        T.ok(near(S.altitude(S.cityToUniverse({ 0, 0, 0 })), 0, 1e-6), "Night City's ground is Earth's surface")
        local h = S.altitude(S.cityToUniverse({ 111.1, -331.9, 16383.9 }))
        T.ok(near(h, 16383.9, 0.01), "the owner's §AX4 mark is 16,384 m up (curvature is millimetres here)")
        T.eq((S.phase(S.cityToUniverse({ 0, 0, 11000 }))), "native", "11 km is still Cyberpunk")
        T.eq((S.phase(S.cityToUniverse({ 0, 0, 13000 }))), "transition", "12-14 km the bubble wakes")
        T.eq((S.phase(S.cityToUniverse({ 0, 0, 15000 }))), "space", "from 14 km NCM owns position")
        T.ok(S.PHASES.ownAt < S.CEILING, "full ownership begins below the hard ceiling")
    end,

    a_rebase_moves_the_origin_and_no_universe_position = function(T)
        local S = U(T)
        local b = S.cityBubble()
        local car = S.cityToUniverse({ 100, 200, 15000 })
        local moon = S.BODIES.moon.pos
        local carBefore, moonBefore = S.toLocal(b, car), S.toLocal(b, moon)
        T.ok(vnear(carBefore, { 100, 200, 15000 }, 1e-6), "before any rebase the bubble IS Night City's frame")
        local shift = S.rebase(b, car, { 0, 0, 2000 })
        T.ok(vnear(S.toLocal(b, car), { 0, 0, 2000 }, 1e-6), "the car lands where the rebase put it")
        T.ok(vnear(S.toLocal(b, moon), S.vec.add(moonBefore, shift), 1e-3), "everything else shifts by the same vector")
        T.ok(vnear(S.toUniverse(b, S.toLocal(b, car)), car, 1e-6), "and the universe position never moved")
        T.ok(S.localSafe(S.toLocal(b, car)), "the recentred car is inside REDengine's bounds")
        T.ok(not S.localSafe({ 0, 0, 16000 }), "16 km local is not")
    end,

    doubles_hold_the_sun = function(T)
        local S = U(T)
        local b = S.cityBubble()
        local near_sun = S.vec.add(S.BODIES.sun.pos, { 0, -S.BODIES.sun.radius - 1e9, 0.25 })
        S.rebase(b, near_sun)
        local l = S.toLocal(b, S.vec.add(near_sun, { 0.001, 0, 0 }))
        T.ok(near(S.vec.len(l), 0.001, 1e-4), "a millimetre is still a millimetre 150 million km from home")
    end,

    a_proxy_keeps_the_angular_size_and_direction = function(T)
        local S = U(T)
        local eye = S.cityToUniverse({ 0, 0, 15000 })
        local p = S.proxy(S.BODIES.moon, eye, 5000)
        T.ok(near(p.radius / 5000, S.BODIES.moon.radius / p.distance, 1e-12), "same angular size at the drawn distance")
        T.ok(p.radius < 30 and p.radius > 15, "the Moon drawn 5 km away is a ~23 m ball")
        T.ok(near(math.deg(p.angular) * 2, 0.518, 0.01), "about half a degree across, as from Earth")
        T.ok(near(S.vec.len(p.dir), 1, 1e-9), "a unit direction")
    end,

    gravity_points_down_and_weakens_with_height = function(T)
        local S = U(T)
        local g0 = S.vec.len(S.gravity(S.cityToUniverse({ 0, 0, 0 })))
        local g16 = S.vec.len(S.gravity(S.cityToUniverse({ 0, 0, 16384 })))
        T.ok(near(g0, 9.82, 0.02), "about 9.82 m/s^2 at Night City (no spin in v0)")
        T.ok(g16 < g0 and near(g0 / g16, ((6371000 + 16384) / 6371000) ^ 2, 1e-3), "inverse square to the ceiling")
        local f = S.anchorFrame()
        local down = S.gravity(S.cityToUniverse({ 0, 0, 100 }))
        T.ok(S.vec.dot(down, f.up) < 0, "down is down")
    end,

    two_cities_share_one_earth = function(T)
        local S = U(T)
        local d = S.surfaceDistance("night_city", "los_santos")
        T.ok(d > 450000 and d < 500000, "Night City and Los Santos are about 473 km apart on one Earth: " .. math.floor(d))
        local ls0 = S.cityToUniverse({ 0, 0, 0 }, "los_santos")
        T.ok(math.abs(S.altitude(ls0)) < 1e-6, "Los Santos' ground is Earth's surface too")
        T.ok(vnear(S.universeToCity(S.cityToUniverse({ 120, -40, 9000 }, "los_santos"), "los_santos"), { 120, -40, 9000 }, 1e-6),
            "Los Santos round-trips through the same universe")
        local nc = S.cityToUniverse({ 0, 0, 0 }, "night_city")
        T.ok(S.vec.len(S.vec.sub(ls0, nc)) > 450000, "and the two cities are different places in it")
    end,

    a_compressed_earth_keeps_1g_and_allows_real_orbits = function(T)
        local S = U(T)
        S.setWorld({ earthRadius = 5000, surfaceG = 9.81 })
        local ground = S.cityToUniverse({ 0, 0, 0 }, "los_santos")
        local g0 = S.vec.len(S.gravity(ground))
        T.ok(math.abs(g0 - 9.81) < 0.05, "about 1 g at the compressed surface: " .. g0)
        local up5 = S.cityToUniverse({ 0, 0, 5000 }, "los_santos")
        T.ok(math.abs(S.vec.len(S.gravity(up5)) - 9.81 / 4) < 0.05, "a quarter g one radius up")
        -- a circular orbit 1 km up: launched sideways at circular speed, the radius holds for one period
        local f = S.anchorFrame("los_santos")
        local st = { u = S.cityToUniverse({ 0, 0, 1000 }, "los_santos") }
        local v = S.circularSpeed(st.u)
        st.w = S.localToEarth(f, { v, 0, 0 })
        local r0 = S.vec.len(st.u)
        local period = 2 * math.pi * r0 / v
        local rmin, rmax = r0, r0
        for _ = 1, math.floor(period / (1 / 60)) do
            S.integrate(st, S.gravity(st.u), 1 / 60)
            local r = S.vec.len(st.u); if r < rmin then rmin = r end; if r > rmax then rmax = r end
        end
        T.ok(rmax - rmin < 0.02 * r0, ("the orbit holds within 2%% (r %.0f..%.0f)"):format(rmin, rmax))
        -- a vertical launch below escape speed comes back down
        local up = { u = S.cityToUniverse({ 0, 0, 100 }, "los_santos") }
        up.w = S.localToEarth(f, { 0, 0, 150 })
        local fell = false
        for _ = 1, 60 * 600 do
            S.integrate(up, S.gravity(up.u), 1 / 60)
            if S.altitude(up.u) < 50 then fell = true; break end
        end
        T.ok(fell, "a vertical launch falls back to the surface")
        S.setWorld()
        T.eq(S.BODIES.earth.radius, 6371000, "and the default world is real Earth again")
    end,
}
