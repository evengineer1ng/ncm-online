return {
    ["an untested device class is held far below one we can test"] = function(T)
        local M = T.Core.get("driver.feedback")
        -- The whole safety argument: normalised magnitude is device-relative, so the SAME number is a nudge
        -- on a G29 and a wrist injury on a 20 Nm direct-drive base.
        T.eq(M.CEILING.direct_drive < M.CEILING.belt, true)
        T.eq(M.CEILING.unknown <= M.CEILING.direct_drive, true)
        T.eq(M.CEILING.unknown < M.CEILING.gear, true)
    end,

    ["clamp is the only way out and it always caps"] = function(T)
        local M = T.Core.get("driver.feedback")
        T.eq(M.clamp("belt", 0.2), 0.2)
        T.eq(M.clamp("belt", 1.0), M.CEILING.belt)
        T.eq(M.clamp("direct_drive", 1.0), M.CEILING.direct_drive)
        T.eq(M.clamp("direct_drive", 0.9), M.CEILING.direct_drive)
        -- An unrecognised class is treated as the most dangerous thing it could be, never as permissive.
        T.eq(M.clamp("moza_r21", 1.0), M.CEILING.unknown)
        T.eq(M.clamp(nil, 1.0), M.CEILING.unknown)
        -- Garbage and negatives collapse to silence, not to a default that happens to be loud.
        T.eq(M.clamp("belt", nil), 0)
        T.eq(M.clamp("belt", -3), 0)
        T.eq(M.clamp("belt", 0 / 0), 0)
    end,

    ["the ladder starts at the floor and stops at the ceiling"] = function(T)
        local M = T.Core.get("driver.feedback")
        local belt = M.ladder("belt")
        T.eq(belt[1], M.FLOOR)
        T.eq(belt[#belt] <= M.CEILING.belt, true)
        T.eq(belt[#belt] + M.STEP > M.CEILING.belt, true)
        -- Owner's method: increment slightly, stop when another rung adds nothing. Fixed rungs, not a slider.
        T.eq(math.floor((belt[2] - belt[1]) * 1000 + 0.5) / 1000, M.STEP)
        -- A direct-drive ladder is short on purpose.
        T.eq(#M.ladder("direct_drive") < #belt, true)
        T.eq(#M.ladder("not_a_class"), 0)
    end,

    ["no sudden full-scale step, ever"] = function(T)
        local M = T.Core.get("driver.feedback")
        -- A spike is what hurts on a direct-drive base, so rate is capped as well as level.
        local first = M.slew(0, 1.0, 0.033, 1.5)
        T.eq(first < 0.06, true)
        T.eq(first > 0, true)
        -- It still arrives, just not all at once.
        local v, steps = 0, 0
        while v < 0.5 and steps < 100 do v = M.slew(v, 0.5, 0.033, 1.5); steps = steps + 1 end
        T.eq(v, 0.5)
        T.eq(steps > 5, true)
        -- Falling is rate-limited too, and an unreadable target holds the previous value rather than dropping.
        T.eq(M.slew(0.5, 0.0, 0.033, 1.5) > 0, true)
        T.eq(M.slew(0.4, nil, 0.033, 1.5), 0.4)
        T.eq(M.slew(0.4, 1.0, 0, 1.5), 0.4)
    end,

    ["a frame describes the car and never fabricates a channel"] = function(T)
        local M = T.Core.get("driver.feedback")
        local f = M.frame({
            rpm = 2650, rpmMax = 5300, throttle = 0.5, brake = 0, steering = -0.25,
            totalSlip = 0.2, onGround = true,
        }, { at = 123 })
        T.eq(f.v, M.FRAME_VERSION)
        T.eq(f.engine, 0.5)
        T.eq(f.throttle, 0.5)
        T.eq(f.brake, 0)              -- a real zero survives
        T.eq(f.steering, -0.25)
        T.eq(f.onGround, true)
        T.eq(f.t, 123)
        -- Absent is absent. A companion must be able to tell "not slipping" from "we do not know".
        T.eq(f.slipLat, nil)
        T.eq(f.suspLong, nil)
        T.eq(f.gear, nil)
    end,

    ["engine is a ratio, and an impossible one is clamped rather than trusted"] = function(T)
        local M = T.Core.get("driver.feedback")
        T.eq(M.frame({ rpm = 8000, rpmMax = 5300 }).engine, 1)
        T.eq(M.frame({ rpm = -20, rpmMax = 5300 }).engine, 0)
        -- No max means no ratio, not a guess at one. `throttle` is present only so a frame exists at all:
        -- rpm WITHOUT rpmMax contributes no channel, so on its own it is correctly "nothing measured".
        T.eq(M.frame({ rpm = 3000, throttle = 0 }).engine, nil)
        T.eq(M.frame({ rpm = 3000, rpmMax = 0, throttle = 0 }).engine, nil)
        T.eq(M.frame({ rpm = 3000 }), nil)
    end,

    ["a frame with nothing measured is refused"] = function(T)
        local M = T.Core.get("driver.feedback")
        -- Sending one would assert the car is at rest, idling, straight and gripping -- four things we did
        -- not measure.
        local f, why = M.frame({ rpm = "n/a", throttle = nil, onGround = "maybe" })
        T.eq(f, nil); T.eq(why, "nothing_measured")
        local f2, why2 = M.frame(nil)
        T.eq(f2, nil); T.eq(why2, "no_snapshot")
    end,
}
