-- space.fireball (L322; doc 54 §L): valid distance is angle swept about the centre, about the racer's own lagged axis.
-- Any plane earns; changing plane earns; oscillating, looping in one patch and going backwards do not.
local function FB(T) return T.Core.get("space.fireball") end

local R = 1000
local function rules(T, extra)
    local r = { inner = 900, outer = 1100, distanceM = 1e9, centre = { 0, 0, 0 } }
    for k, v in pairs(extra or {}) do r[k] = v end
    return FB(T).rules(r)
end

-- fly a path p(t) (universe) at 20 Hz for `dur` seconds through a judge; velocity by central difference
local function fly(T, rl, path, dur)
    local st = FB(T).newState()
    local dt = 0.05
    local travelled, prev = 0, nil
    for k = 0, math.floor(dur / dt) do
        local t = k * dt
        local p = path(t)
        local a, b = path(t - 1e-4), path(t + 1e-4)
        local v = { (b[1] - a[1]) / 2e-4, (b[2] - a[2]) / 2e-4, (b[3] - a[3]) / 2e-4 }
        if prev then travelled = travelled + math.sqrt((p[1] - prev[1]) ^ 2 + (p[2] - prev[2]) ^ 2 + (p[3] - prev[3]) ^ 2) end
        prev = p
        FB(T).step(rl, st, p, v, t, k == 0 and 0 or dt)
    end
    return st, travelled
end

local function great(e1, e2, w)
    return function(t) return { R * (math.cos(w * t) * e1[1] + math.sin(w * t) * e2[1]),
        R * (math.cos(w * t) * e1[2] + math.sin(w * t) * e2[2]), R * (math.cos(w * t) * e1[3] + math.sin(w * t) * e2[3]) } end
end

return {
    any_plane_earns_full_credit = function(T)
        local s3 = math.sqrt(0.5)
        local planes = {
            { "equatorial", { 1, 0, 0 }, { 0, 1, 0 } },
            { "polar", { 0, 1, 0 }, { 0, 0, 1 } },
            { "inclined", { 1, 0, 0 }, { 0, s3, s3 } },
        }
        for _, pl in ipairs(planes) do
            local st, travelled = fly(T, rules(T), great(pl[2], pl[3], 0.1), 60)
            T.ok(math.abs(st.creditM - travelled) / travelled < 0.01, pl[1] .. ": credit equals the arc flown")
            T.ok(st.coherence > 0.99, pl[1] .. ": a steady plane is fully coherent")
        end
    end,

    changing_plane_continuously_still_earns = function(T)
        -- a great circle whose plane turns about x by 90 degrees over 100 s (slower than axisTurnRate)
        local Om, w = (math.pi / 2) / 100, 0.15
        local path = function(t)
            local c, s = math.cos(Om * t), math.sin(Om * t)
            local b = { 0, c, s }
            return { R * math.cos(w * t), R * math.sin(w * t) * b[2], R * math.sin(w * t) * b[3] }
        end
        local st, travelled = fly(T, rules(T), path, 100)
        T.ok(st.creditM / travelled > 0.9, ("a turning plane keeps >= 90 %% (got %.3f)"):format(st.creditM / travelled))
    end,

    oscillating_in_one_patch_earns_nothing = function(T)
        local path = function(t)
            local th = 0.2 * math.sin(2 * math.pi * t / 20)
            return { R * math.cos(th), R * math.sin(th), 0 }
        end
        local st, travelled = fly(T, rules(T), path, 600)
        T.ok(travelled > 20000, "more than 20 km flown back and forth")
        T.ok(math.abs(st.creditM) < 0.03 * travelled, ("credit ~0 (got %.0f m of %.0f)"):format(st.creditM, travelled))
    end,

    small_loops_in_one_patch_earn_nothing = function(T)
        local rho = 0.05
        local path = function(t)
            local a = 2 * math.pi * t / 10
            local y, z = rho * math.cos(a), rho * math.sin(a)
            local n = math.sqrt(1 + y * y + z * z)
            return { R / n, R * y / n, R * z / n }
        end
        local st, travelled = fly(T, rules(T), path, 300)
        T.ok(math.abs(st.creditM) < 0.06 * travelled, ("loops earn ~0 (got %.0f m of %.0f)"):format(st.creditM, travelled))
    end,

    going_backwards_debits = function(T)
        local path = function(t)
            local th = t < 20 and 0.05 * t or 0.05 * (40 - t)
            return { R * math.cos(th), R * math.sin(th), 0 }
        end
        local st = fly(T, rules(T), path, 40)
        T.ok(math.abs(st.creditM) < 0.1 * R, "out and back is roughly nothing")
        -- a long out-and-back always earns less than simply carrying on round
        local long = function(t)
            local th = t < 300 and 0.05 * t or 0.05 * (600 - t)
            return { R * math.cos(th), R * math.sin(th), 0 }
        end
        local stl, travelled = fly(T, rules(T), long, 600)
        T.ok(stl.creditM < 0.75 * travelled, ("15 km out, 15 back: %.0f m of %.0f"):format(stl.creditM, travelled))
    end,

    outside_the_shell_earns_nothing_then_black_flag = function(T)
        local out = function(t) return { 1300 * math.cos(0.1 * t), 1300 * math.sin(0.1 * t), 0 } end
        local st = fly(T, rules(T, { oobMaxS = 10 }), out, 20)
        T.eq(st.creditM, 0, "nothing credited outside the shell")
        T.eq(st.dq, "out of bounds", "black-flagged after 10 s outside")
    end,

    the_finish_is_interpolated_and_arc_rule_is_radius_neutral = function(T)
        local st = fly(T, rules(T, { distanceM = 500 }), great({ 1, 0, 0 }, { 0, 1, 0 }, 0.1), 10)
        T.ok(st.finishT and math.abs(st.finishT - 5) < 1e-3, "500 m at 100 m/s: finished at 5.000 s")
        local wide = function(t) return { 1050 * math.cos(0.1 * t), 1050 * math.sin(0.1 * t), 0 } end
        local a = fly(T, rules(T), wide, 10)
        local b = fly(T, rules(T, { credit = "arc" }), wide, 10)
        T.ok(a.creditM < b.creditM, "angle credit: the outside line earns per radian, like an oval")
    end,
}
