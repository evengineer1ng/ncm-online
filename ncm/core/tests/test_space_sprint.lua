-- space.sprint (L322; doc 54 §L): start plane -> finish plane, timed in universe space with a Hermite photo finish.
local function SP(T) return T.Core.get("space.sprint") end

local FRAME = { origin = { 0, 0, 0 }, x = { 1, 0, 0 }, y = { 0, 1, 0 }, z = { 0, 0, 1 } }

local function run(T, rl, traj, hz)
    local st = SP(T).newState()
    local dt = 1 / hz
    for k = 0, math.floor(20 / dt) do
        local t = k * dt
        local p, v = traj(t)
        SP(T).step(rl, st, t, p, v)
        if st.finishT then break end
    end
    return st
end

local function accel(a, startT, x, lag)
    return function(t)
        local tt = math.max(0, t - startT)
        local y = 0.5 * a * tt * tt - (lag or 0)
        return { x or 0, y, 0 }, { 0, a * tt, 0 }
    end
end

return {
    the_crossing_is_solved_between_samples = function(T)
        local rl = SP(T).rules({ distanceM = 100, lanes = 2, startT = 0, frame = FRAME })
        local st = run(T, rl, accel(20, 0), 60)
        T.ok(math.abs(st.finishT - math.sqrt(10)) < 1e-6, ("100 m at 20 m/s2: %.9f s (exact %.9f)"):format(st.finishT, math.sqrt(10)))
    end,

    a_photo_finish_two_centimetres_apart = function(T)
        local rl = SP(T).rules({ distanceM = 100, lanes = 2, startT = 0, frame = FRAME })
        local a = run(T, rl, accel(20, 0, -6), 60)
        local b = run(T, rl, accel(20, 0, 6, 0.02), 60)
        local rows = SP(T).classify(rl, { { id = "B", state = b }, { id = "A", state = a } })
        T.eq(rows[1].id, "A", "A, 2 cm ahead all the way, wins")
        T.falsy(rows[1].deadHeat, "and it is not a dead heat")
        local gap, want = rows[2].raceS - rows[1].raceS, 0.02 / (20 * math.sqrt(10))
        T.ok(math.abs(gap - want) < 0.05 * want, ("by 2 cm at 63 m/s: %.6f s (want %.6f)"):format(gap, want))
    end,

    identical_runs_are_a_dead_heat = function(T)
        local rl = SP(T).rules({ distanceM = 100, lanes = 2, startT = 0, frame = FRAME })
        local rows = SP(T).classify(rl, { { id = "A", state = run(T, rl, accel(20, 0, -6), 60) }, { id = "B", state = run(T, rl, accel(20, 0, 6), 60) } })
        T.truthy(rows[1].deadHeat and rows[2].deadHeat, "same time: a dead heat")
        T.eq(rows[2].position, 1, "sharing first place")
    end,

    a_rebase_between_samples_changes_nothing = function(T)
        local U = T.Core.get("space.universe")
        local bubble = U.cityBubble("los_santos")
        local f = T.Core.get("space.course").anchorFrame("los_santos", 3000)
        local rl = SP(T).rules({ distanceM = 100, lanes = 1, startT = 0, frame = { origin = f.origin, x = f.x, y = f.y, z = f.z } })
        local st = SP(T).newState()
        for k = 0, 400 do
            local t = k / 60
            local tt = t
            local u = { f.origin[1] + f.y[1] * 10 * tt * tt, f.origin[2] + f.y[2] * 10 * tt * tt, f.origin[3] + f.y[3] * 10 * tt * tt }
            local w = { f.y[1] * 20 * tt, f.y[2] * 20 * tt, f.y[3] * 20 * tt }
            -- the host keeps LOCAL coordinates in a bubble and rebases it every 7 samples; it reports universe ones
            if k % 7 == 0 then U.rebase(bubble, u, { 0, 0, 1700 }) end
            local back = U.toUniverse(bubble, U.toLocal(bubble, u))
            SP(T).step(rl, st, t, back, w)
            if st.finishT then break end
        end
        T.ok(math.abs(st.finishT - math.sqrt(10)) < 1e-6, "universe timing survives floating-origin rebases")
    end,

    a_jump_start_is_flagged_and_penalised = function(T)
        local rl = SP(T).rules({ distanceM = 100, lanes = 2, startT = 1, frame = FRAME })
        local early = run(T, rl, accel(20, 0.6), 60)
        local fair = run(T, rl, accel(20, 1.0), 60)
        T.truthy(early.jumped, "moving across the start plane before the lights is a jump start")
        local rows = SP(T).classify(rl, { { id = "early", state = early }, { id = "fair", state = fair } })
        T.eq(rows[1].id, "fair", "the 5 s penalty costs the jumper the race")
        T.ok(rows[1].reactS ~= nil, "a reaction time is measured, not assumed")
    end,

    lanes_are_side_by_side_on_the_start_plane = function(T)
        local rl = SP(T).rules({ distanceM = 100, lanes = 6, startT = 0, frame = FRAME })
        local a, b = SP(T).laneSpot(rl, 1), SP(T).laneSpot(rl, 6)
        T.eq(a[2], 0, "on the start plane")
        T.ok(math.abs(a[1] + b[1]) < 1e-9 and b[1] - a[1] == 5 * rl.laneSpacingM, "centred, evenly spaced lanes")
    end,
}
