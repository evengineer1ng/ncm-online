-- ncm-core module: parts.thermal
--
-- **Tyre temperature as a first-order thermal model.** A model, not a simulation -- but a model with the
-- right shape, so that what a driver learns from it transfers to a real car rather than to this one.
--
-- ---------------------------------------------------------------------------------------------------
-- ONE TEMPERATURE FOR THE WHOLE CAR, AND THAT IS NOT A SIMPLIFICATION
-- ---------------------------------------------------------------------------------------------------
--
-- `parts.ontology` declares the `per_corner` channel **DOES NOT EXIST** and names "per-corner tyre
-- temperature" as one of the things it would have carried. MASTER_TEST section AV2 tried to reach it by
-- redistributing per-corner normal load and returned a clean negative: 20 percent of axle load moved, under
-- 5 percent change in lateral capability. And `SERIALISATION_UNIT = { tires = SET }` already records the
-- consequence -- a tyre asset is a set of four, *because* four objects that can only ever behave as one are
-- a database cost with no expression behind them.
--
-- So a single whole-car temperature is not the cheap version of this model. It is the only ontologically
-- legal one, and inside-shoulder temperature, cross-axle spread and a heating front tyre are `losses`.
--
-- ---------------------------------------------------------------------------------------------------
-- HEAT IN IS WORK, NOT FORCE
-- ---------------------------------------------------------------------------------------------------
--
-- The first draft of this accumulated force and called it heat. That is wrong by a whole dimension: force
-- integrated over time is MOMENTUM (kg m/s), and heating is WORK (J). The difference is not academic --
-- under the force-only model a 30 km/h hairpin at the friction limit heats a tyre exactly as much as a
-- 200 km/h sweeper at the friction limit, because the force is the same. Physically the sweeper does nearly
-- seven times the work.
--
-- So `load` carries a speed term. What this still cannot see is SLIP velocity, which is the true driver of
-- tyre heating -- a locked wheel and a rolling one at the same speed and force are not the same event. This
-- proxies contact-patch work for slip work, and over-heats under pure rolling as a result. That is in
-- `LOSSES`, not in a comment.
--
-- ---------------------------------------------------------------------------------------------------
-- THE WINDOW IS A PENALTY, NEVER A BOOST
-- ---------------------------------------------------------------------------------------------------
--
-- `gripMultiplier` returns **1.00 at the optimum and falls to `PENALTY` at both extremes**. It never
-- exceeds 1.00 for any input, which is asserted rather than assumed.
--
-- That is a design decision and it is the owner's: *"not pure accel for being in the window like an
-- arbitrary stat boost, but inferred grip and braking differences."* Expressing it downward-only also means
-- it inherits `L156` point 3 -- ceilings reduce and never add -- instead of needing its own authorisation
-- to add force. Being in the window is not a reward; being outside it is a cost.
local Core = NcmCore

Core.define("parts.thermal", function(C)
    local M = { version = "0.1.0" }

    -- ---------------------------------------------------------------------------------------------
    -- Constants. Every one of these is a first pass awaiting play data.
    -- ---------------------------------------------------------------------------------------------
    --
    -- Calibrated to the owner's stated intent rather than to a real tyre: **about 60 s from cold to the
    -- window under hard driving, cooling over about two minutes**, and a 15 percent grip cost at the
    -- extremes. 18_PARTS_ECOSYSTEM puts component balance out of scope, so none of these is a balance
    -- judgement -- they are the numbers that produce the requested feel and they are meant to be tuned.

    M.AMBIENT_DEFAULT = 20.0    -- degrees C, a mild Night City afternoon
    M.OPTIMUM = 85.0            -- the centre of the window
    M.HALF_WINDOW = 35.0        -- +/- this from OPTIMUM is "fully cold" / "fully hot"
    M.PENALTY = 0.15            -- grip and brake cost at either extreme, so x0.85

    -- Newtonian cooling toward ambient. `tau` is the time constant: about 3 tau to settle, so 45 s gives
    -- roughly two minutes, which is the requested cooldown.
    M.TAU_SECONDS = 45.0
    -- Airflow makes a moving car cool faster than a parked one. Bounded so that a stationary car still
    -- cools (`1.0`) and a fast one cools about twice as quickly rather than instantly.
    M.AIRFLOW_AT_REF = 1.0
    M.AIRFLOW_REF_SPEED = 40.0  -- m/s

    -- Heat in. `GAIN` is degrees per second at unit load; `load` is dimensionless and normalised below.
    --
    -- **Recalibrated 2026-09-26 from 2.6 after the first live drive, which reported the gauge "stayed flat
    -- cold" through cornering AND donuts.** That was not a plumbing fault -- it was the model. What matters
    -- for a gauge is not the heating rate, it is the EQUILIBRIUM where heating balances cooling, and at 2.6
    -- that equilibrium was:
    --
    --   donuts (8 m/s, 1.1g)        54C   stone cold
    --   city cornering (15 m/s)     55C   stone cold
    --   highway cruise (30 m/s)     42C   stone cold
    --   fast hard corner (30 m/s)   99C   hot
    --
    -- So the window was unreachable by anything except sustained 100 km/h+ cornering, and the needle sat on
    -- the bottom stop in every kind of driving a person actually does. A gauge that only moves in one
    -- regime is decoration.
    --
    -- **Set from the equilibrium, not from the slope**: brisk cornering (20 m/s, 0.75g) should settle just
    -- above the window so the window is somewhere a driver ARRIVES at rather than a peak they graze, and
    -- so that overheating is reachable by pushing harder.
    M.GAIN = 4.6
    M.SPEED_REF = 30.0          -- m/s, the speed at which the longitudinal term reaches 1.0
    M.LATERAL_REF = 8.0         -- m/s^2, about 0.8 g, the lateral accel at which that term reaches 1.0
    M.WEIGHT_LATERAL = 0.75     -- cornering is what cooks a tyre
    M.WEIGHT_LONGITUDINAL = 0.25

    -- A tyre cannot fall below ambient or melt. Bounds exist so a bad `dt` or a hostile input cannot walk
    -- the state anywhere interesting.
    M.MIN_C = -40.0
    M.MAX_C = 200.0
    -- The longest step this will integrate in one go. A server hitch, a paused game or a resumed session
    -- must not deliver a single 400-second step and teleport the temperature.
    M.MAX_STEP_SECONDS = 5.0

    M.LOSSES = {
        "per-corner temperature, inside-shoulder temperature and cross-axle spread -- the `per_corner` "
            .. "channel does not exist (`parts.ontology`, MASTER_TEST AV2)",
        "SLIP velocity, which is the real heat source: this proxies contact-patch work, so it over-heats "
            .. "under pure rolling and under-heats a locked wheel",
        "brake temperature as a separate body -- discs and tyres share one number here",
        "track temperature as distinct from air temperature",
        "pressure, and therefore the pressure/temperature feedback loop that is most of real tyre work",
        "compound differences: there is one curve, and a soft and a hard tyre would need two",
    }

    -- ---------------------------------------------------------------------------------------------
    -- The model
    -- ---------------------------------------------------------------------------------------------

    local function clamp(v, lo, hi)
        if v ~= v then return lo end          -- NaN
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end

    --- Dimensionless thermal load from what a 1 Hz server poll can actually see.
    ---
    --- `speed` in m/s, `lateralAccel` in m/s^2. Both are derived from position/heading samples the odometer
    --- already takes, which is why this model lives where it does -- it asks for nothing new.
    function M.load(speed, lateralAccel)
        local v = clamp(tonumber(speed) or 0, 0, 200)
        local a = math.abs(clamp(tonumber(lateralAccel) or 0, -80, 80))
        -- Longitudinal term is v^2 because work goes as force x distance and rolling losses climb with
        -- speed; lateral term is |a| x v, because cornering work is the lateral force doing work along the
        -- path. Both normalised so that "hard driving" lands near 1.0.
        local longitudinal = (v * v) / (M.SPEED_REF * M.SPEED_REF)
        local lateral = (a / M.LATERAL_REF) * (v / M.SPEED_REF)
        return M.WEIGHT_LONGITUDINAL * longitudinal + M.WEIGHT_LATERAL * lateral
    end

    --- Ambient temperature for a set of world conditions.
    ---
    --- `wetness` 0..1 and `secondsOfDay` 0..86400. **Day/night reaches the car through here and nowhere
    --- else** -- it gets no lever of its own, because a cooler night genuinely acts by making tyres harder
    --- to warm rather than by making grip worse directly. Rain does both: it cools the surface and it
    --- reduces grip, and only the first belongs in this function.
    function M.ambient(conditions)
        conditions = conditions or {}
        local base = tonumber(conditions.baseC) or M.AMBIENT_DEFAULT
        local seconds = tonumber(conditions.secondsOfDay)
        local out = base
        if seconds then
            -- Peak in mid-afternoon, trough before dawn. Amplitude is deliberately modest: this is Night
            -- City, not a desert, and an 8 degree swing is enough to change a warm-up without dominating it.
            local phase = ((seconds % 86400) / 86400) * 2 * math.pi
            local peakPhase = (15 / 24) * 2 * math.pi        -- 15:00
            out = out + 8.0 * math.cos(phase - peakPhase)
        end
        local wetness = clamp(tonumber(conditions.wetness) or 0, 0, 1)
        -- Standing water pulls heat out of a tyre far faster than cool air does.
        out = out - 12.0 * wetness
        return out
    end

    --- Integrate one step. Returns the new temperature.
    ---
    --- `dt` is MEASURED seconds, never an assumed tick. The host's 1 Hz loop is a minimum wait rather than
    --- a period, and a hitched frame that cooled a tyre by a full second when 300 ms had passed would be a
    --- slow, invisible drift.
    function M.step(temperatureC, load, ambientC, dt, speed)
        local T = clamp(tonumber(temperatureC) or M.AMBIENT_DEFAULT, M.MIN_C, M.MAX_C)
        local step = clamp(tonumber(dt) or 0, 0, M.MAX_STEP_SECONDS)
        if step <= 0 then return T end
        local ambient = clamp(tonumber(ambientC) or M.AMBIENT_DEFAULT, M.MIN_C, M.MAX_C)
        local l = clamp(tonumber(load) or 0, 0, 20)

        -- Airflow: a parked car still cools, a moving one cools faster.
        local v = clamp(tonumber(speed) or 0, 0, 200)
        local airflow = M.AIRFLOW_AT_REF + (v / M.AIRFLOW_REF_SPEED)

        local heating = M.GAIN * l
        local cooling = (T - ambient) / M.TAU_SECONDS * airflow
        return clamp(T + step * (heating - cooling), M.MIN_C, M.MAX_C)
    end

    --- Cool for an arbitrary stretch with no load, in CLOSED FORM.
    ---
    --- `step` clamps `dt` so that a hitch or a resumed session cannot teleport a temperature, which is
    --- right for the driving case and wrong for the parked one: a car left for ten minutes must end up at
    --- ambient, not five seconds cooler. Newtonian cooling has an exact solution, so this needs no
    --- iteration and no clamp -- `T_amb + (T - T_amb) * e^(-t/tau)` is correct for any elapsed time and
    --- cannot overshoot below ambient however large it gets.
    ---
    --- **This is what makes "tyre temperature belongs to the Machine" cheap.** A parked asset costs one
    --- exponential when somebody next looks at it, rather than a timer per car.
    function M.cool(temperatureC, ambientC, seconds)
        local T = clamp(tonumber(temperatureC) or M.AMBIENT_DEFAULT, M.MIN_C, M.MAX_C)
        local ambient = clamp(tonumber(ambientC) or M.AMBIENT_DEFAULT, M.MIN_C, M.MAX_C)
        local s = tonumber(seconds) or 0
        if s ~= s or s <= 0 then return T end
        return ambient + (T - ambient) * math.exp(-s / M.TAU_SECONDS)
    end

    --- Where in the window is this temperature? -1 fully cold, 0 optimal, +1 fully hot.
    --- Exposed because a HUD needs the position, not the degrees, and a gauge that rescales itself when
    --- the constants are tuned is one fewer thing to keep in sync.
    function M.position(temperatureC)
        local T = tonumber(temperatureC)
        if not T or T ~= T then return nil end
        return clamp((T - M.OPTIMUM) / M.HALF_WINDOW, -1, 1)
    end

    --- The grip and brake multiplier for a temperature. **Never above 1.0.**
    ---
    --- A parabola rather than a plateau: a real tyre does not switch on at the edge of its window, it comes
    --- to it. The quadratic means the middle third of the window costs almost nothing, which is what makes
    --- the window feel like a window rather than a knife edge.
    function M.gripMultiplier(temperatureC)
        local x = M.position(temperatureC)
        if not x then return 1.0 end
        return 1.0 - M.PENALTY * (x * x)
    end

    --- A tyre that has never been driven is at ambient, not at the optimum. Distinct from "unknown", which
    --- the HUD must render as a dash rather than as a plausible resting value (`IDEA-361`).
    function M.initial(conditions)
        return M.ambient(conditions)
    end

    --- One human line, matching `parts.handling.explain`'s register.
    function M.explain(temperatureC)
        local x = M.position(temperatureC)
        if not x then return "tyre temperature unknown" end
        local band
        if x <= -0.66 then band = "STONE COLD"
        elseif x < -0.2 then band = "cold"
        elseif x <= 0.2 then band = "IN THE WINDOW"
        elseif x < 0.66 then band = "hot"
        else band = "OVERHEATING" end
        return ("%.0fC %s (x%.3f grip)"):format(temperatureC, band, M.gripMultiplier(temperatureC))
    end

    -- The promise the rest of the system relies on, checked at load rather than trusted.
    assert(math.abs(M.gripMultiplier(M.OPTIMUM) - 1.0) < 1e-9, "the window must cost nothing")
    assert(math.abs(M.gripMultiplier(M.OPTIMUM + M.HALF_WINDOW) - (1.0 - M.PENALTY)) < 1e-9,
        "fully hot must cost exactly PENALTY")
    assert(math.abs(M.gripMultiplier(M.OPTIMUM - M.HALF_WINDOW) - (1.0 - M.PENALTY)) < 1e-9,
        "fully cold must cost exactly PENALTY")
    assert(#M.LOSSES > 0, "a thermal model with no stated losses is the dishonest kind")

    return M
end)
