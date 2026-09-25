-- ncm-core module: driver.feedback
--
-- What NCM promises a force-feedback companion, and the safety envelope that companion must honour.
--
-- **NCM emits what the car is DOING, never how hard to push.** The companion decides force, because only the
-- companion knows which device is attached. That division is not tidiness -- it is the whole safety argument
-- (see SAFETY below), and it is why every channel here is a normalised physical quantity rather than a
-- magnitude.
--
-- Until `IDEA-387` was answered this could not exist: a bundled WebUI page has no outbound network at all.
-- L129 is the shape that works -- the companion serves a page, NCM creates a surface whose `entry` is that
-- URL, and the Lua bridge reaches it (MASTER_TEST section AJ).
local Core = NcmCore

Core.define("driver.feedback", function(C)
    local Knowledge = C.get("competition.machine_knowledge")
    local M = { version = "0.1.0" }

    --- Bump when the frame's MEANING changes, never for an added optional channel. A companion that does not
    --- recognise the version must refuse the stream rather than guess at it.
    M.FRAME_VERSION = 1

    -- ---------------------------------------------------------------------------------------------
    -- SAFETY. Read this before changing a number in it.
    -- ---------------------------------------------------------------------------------------------
    --
    -- **SDL haptic magnitude is normalised, and normalised is not the same as equal.** A `0.5` constant force
    -- is roughly a newton-metre on a gear-drive G29 and roughly ten on a 20 Nm direct-drive base. **The same
    -- number is a nudge on one device and a wrist injury on another.** A profile that feels right on the only
    -- wheel we own would, shipped unchanged, be genuinely dangerous on hardware we have never touched.
    --
    -- So the ceiling is per device CLASS, the unknown and direct-drive classes are held far below the classes
    -- we can actually test, and **there is no path to raise a ceiling from a profile file** -- `clamp` is the
    -- only way out of this module and it always applies the cap.
    --
    -- Owner, 2026-09-24, setting the method: *"start at the lowest ffb settings, and increment slightly until
    -- further is unnecessary then STOP. An important feature for us should not cost any wrists."* That is a
    -- ladder, not a slider, and `ladder()` below is it: fixed rungs, a fixed small step, a hard last rung.
    M.CLASSES = { gear = true, belt = true, direct_drive = true, unknown = true }

    -- Fractions of the DEVICE's own maximum, not of anything absolute.
    --   * `gear` / `belt` -- what we can test. A G29 is the reference.
    --   * `direct_drive` -- untested by anyone here, and the class where a mistake hurts. Deliberately a
    --     third of the belt ceiling; it is a starting point for recruited testers, not a tuned value.
    --   * `unknown` -- we could not identify the device, so we assume the most dangerous thing it could be.
    --
    -- **MEASURED 2026-09-24, and the numbers moved a long way.** The first set were reasoned, not tested.
    -- Then a G29 ran the full ladder with the constant centring effect in play and the owner reported it
    -- *"fairly strong from first rung to too strong by the end"* -- so the floor was already past useful and
    -- the ceiling was well past comfortable. A directional torque is enormously more forceful than the sine
    -- the first numbers were guessed against, which is exactly the kind of thing measurement catches and
    -- reasoning does not.
    --
    -- The ladder therefore starts LOWER and steps FINER, and the ceilings come down by roughly 60%. Relative
    -- order is unchanged and deliberate: a belt drive is stronger than a gear drive for the same normalised
    -- magnitude, so it is capped lower; direct drive is capped far below both; an unrecognised device is
    -- assumed to be the most powerful thing it could be.
    M.CEILING = { gear = 0.24, belt = 0.20, direct_drive = 0.06, unknown = 0.04 }

    M.FLOOR = 0.02
    M.STEP = 0.02

    --- Every permitted setting for a class, lowest first. **A tuning session starts at `[1]` and stops the
    --- moment another rung adds nothing** -- the owner's method, encoded so it survives being forgotten.
    function M.ladder(class)
        local ceiling = M.CEILING[class]
        if not ceiling then return {} end
        local out = {}
        local v = M.FLOOR
        while v <= ceiling + 1e-9 do
            out[#out + 1] = math.floor(v * 1000 + 0.5) / 1000
            v = v + M.STEP
        end
        return out
    end

    --- The only way a magnitude leaves this module. Unknown class, unreadable value and negative input all
    --- collapse to the safest answer rather than to a default that happens to be loud.
    function M.clamp(class, requested)
        local ceiling = M.CEILING[class] or M.CEILING.unknown
        local v = Knowledge.reading(requested)
        if v == nil or v < 0 then return 0 end
        if v > ceiling then return ceiling end
        return v
    end

    --- **No sudden full-scale step, ever.** A spike is what hurts on a direct-drive base, not a sustained
    --- level, so the rate of change is capped as well as the level. `maxPerSecond` is expressed in units of
    --- magnitude, and the default crosses the belt ceiling in about a third of a second -- fast enough to
    --- feel like an impact, slow enough that nothing arrives as a hammer blow.
    M.MAX_SLEW_PER_SECOND = 1.5

    function M.slew(previous, target, dt, maxPerSecond)
        local prev = Knowledge.reading(previous) or 0
        local want = Knowledge.reading(target)
        if want == nil then return prev end
        local step = (Knowledge.reading(maxPerSecond) or M.MAX_SLEW_PER_SECOND) * (Knowledge.reading(dt) or 0)
        if step <= 0 then return prev end
        local delta = want - prev
        if delta > step then return prev + step end
        if delta < -step then return prev - step end
        return want
    end

    -- ---------------------------------------------------------------------------------------------
    -- The frame NCM emits.
    -- ---------------------------------------------------------------------------------------------
    --
    -- Every channel is 0..1 or -1..1 and describes the CAR. **A channel that could not be read is absent, not
    -- zero** (`IDEA-361`): a companion must be able to tell "the wheels are not slipping" from "we do not
    -- know whether the wheels are slipping", because the first is a reason to stop a rumble and the second is
    -- a reason to leave it where it was.
    --
    -- Sources, all from the client vehicle snapshot and all confirmed live on `.87`
    -- (`31_CAPABILITY_AUDIT.md` section 2.1):
    --   engine  <- rpm / rpmMax        the ratio, not the raw number, so it is comparable across machines
    --   load    <- throttle, brake     what the driver is asking for
    --   road    <- suspension axes     actual deflection, where anyffb had to infer texture from an FFT
    --   grit    <- slip channels       MEASURED slip (IDEA-370), not derived
    function M.frame(snapshot, opts)
        if type(snapshot) ~= "table" then return nil, "no_snapshot" end
        local r = Knowledge.reading
        local f = { v = M.FRAME_VERSION }

        local rpm, rpmMax = r(snapshot.rpm), r(snapshot.rpmMax)
        if rpm ~= nil and rpmMax ~= nil and rpmMax > 0 then
            local ratio = rpm / rpmMax
            f.engine = (ratio < 0 and 0) or (ratio > 1 and 1) or ratio
        end

        local function unit(name, lo, hi)
            local v = r(snapshot[name])
            if v == nil then return nil end
            if v < lo then return lo end
            if v > hi then return hi end
            return v
        end

        f.throttle = unit("throttle", 0, 1)
        f.brake = unit("brake", 0, 1)
        f.steering = unit("steering", -1, 1)
        f.speed = r(snapshot.speed)
        f.gear = r(snapshot.gear)
        f.slipLong = unit("longitudinalSlip", -1, 1)
        f.slipLat = unit("lateralSlip", -1, 1)
        f.slipTotal = unit("totalSlip", 0, 1)
        f.suspLong = r(snapshot.suspensionLongitudinal)
        f.suspLat = r(snapshot.suspensionTransversal)
        if type(snapshot.onGround) == "boolean" then f.onGround = snapshot.onGround end

        -- Nothing readable is not a frame. Sending one would tell the companion the car is at rest, idling,
        -- straight and gripping -- four assertions we did not measure.
        local measured = 0
        for key, value in pairs(f) do
            if key ~= "v" and value ~= nil then measured = measured + 1 end
        end
        if measured == 0 then return nil, "nothing_measured" end

        f.t = r(opts and opts.at)
        return f
    end

    return M
end)
