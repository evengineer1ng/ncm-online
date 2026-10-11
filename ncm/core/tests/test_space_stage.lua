-- space.stage (L352): NCM Deep shown in REDengine -- the held car and the bodies at their true angular size.
local function near(a, b, tol) return math.abs(a - b) <= tol end
local function angRadius(eye, centre, r)
    local dx, dy, dz = centre[1] - eye[1], centre[2] - eye[2], centre[3] - eye[3]
    return math.deg(math.asin(r / math.sqrt(dx * dx + dy * dy + dz * dz)))
end

return {
    stages_live_inside_redengine = function(T)
        local S = T.Core.get("space.stage")
        for name, st in pairs(S.STAGES) do
            for axis = 1, 3 do
                local lo, hi = st.center[axis] - st.shellR, st.center[axis] + st.shellR
                T.ok(lo > -16384 and hi < 16384, name .. " shell inside the world box on axis " .. axis)
            end
            T.ok(st.center[3] - st.shellR > 500, name .. " shell above the ocean")
        end
        local st = S.STAGES.near
        local top = S.carAt("near", S.SWITCH_M)
        local dx, dy, dz = top[1] - st.center[1], top[2] - st.center[2], top[3] - st.center[3]
        T.ok(math.sqrt(dx * dx + dy * dy + dz * dz) < st.shellR - 100, "the highest near position is still inside the shell")
    end,

    near_earth_has_the_true_angle = function(T)
        local S = T.Core.get("space.stage")
        local st = S.STAGES.near
        for _, h in ipairs({ 20000, 400000, 2000000, 5900000 }) do
            local car = S.carAt("near", h)
            local want = math.deg(math.asin(S.R / (S.R + h)))
            T.ok(near(angRadius(car, st.earth, st.earthR), want, 1e-6), ("Earth's angular radius at %d km"):format(h / 1000))
        end
        local low = S.carAt("near", 100)
        T.ok(low[3] - st.earth[3] - st.earthR >= S.MIN_CLEAR_M - 1e-9, "never into the globe")
    end,

    switch_has_hysteresis = function(T)
        local S = T.Core.get("space.stage")
        T.eq(S.which(1e6, nil), "near")
        T.eq(S.which(S.SWITCH_M + 1, "near"), "far")
        T.eq(S.which(S.SWITCH_M - 1, "far"), "far", "no flicker just under the seam")
        T.eq(S.which(S.SWITCH_BACK_M - 1, "far"), "near")
    end,

    far_props_keep_angle_and_stay_inside = function(T)
        local S = T.Core.get("space.stage")
        local eye = S.carAt("far", 1e8)
        for _, d in ipairs({ 1.3e7, 3.84e8, 1e9 }) do
            local p = S.prop("far", eye, { 0, 0, -1 }, S.R, d)
            T.ok(p ~= nil, "Earth drawn at " .. d)
            T.ok(near(angRadius(eye, p.position, p.scale * S.PROP_MESH_R), math.deg(math.asin(S.R / d)), 1e-6), "true angular size")
            T.ok(p.scale <= S.PROP_MAX_SCALE + 1e-9, "within the prop scale cap")
            T.ok(p.distance <= S.STAGES.far.shellR - S.SHELL_MARGIN + 1e-6, "inside the shell")
        end
    end,

    the_moon_is_where_it_is = function(T)
        local S = T.Core.get("space.stage")
        local m = S.moonEcef(1791504000)   -- 2026-10-08 12:00 UTC
        local r = math.sqrt(m[1] ^ 2 + m[2] ^ 2 + m[3] ^ 2)
        T.ok(r > 3.56e8 and r < 4.07e8, "lunar distance in range")
        T.ok(math.abs(m[3] / r) < math.sin(math.rad(29)), "declination within the Moon's +-28.6 deg")
    end,

    view_from_orbit = function(T)
        local S = T.Core.get("space.stage")
        local Deep = T.Core.get("space.deep")
        local s = { p = Deep.llaToEcef(35, -121, 400000), basis = { forward = Deep.enuToEcef({ 0, 1, 0 }, 35, -121) } }
        local v = S.view(s, 1791504000, nil)
        T.eq(v.stage, "near")
        T.ok(near(v.yaw, 0, 1e-6), "heading north is yaw 0")
        for _, p in ipairs(v.props) do T.ok(p.id ~= "earth", "the near stage's Earth is the static globe") end
        local far = S.view({ p = Deep.llaToEcef(35, -121, 2e8) }, 1791504000, "far")
        T.eq(far.stage, "far")
        T.eq(far.props[1].id, "earth")
    end,
}
