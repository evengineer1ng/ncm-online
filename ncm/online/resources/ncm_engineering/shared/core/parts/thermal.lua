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
-- THE WINDOW IS A PENALTY, NEVER A BOOST -- for `gripMultiplier`. See `levers` for what reaches the car.
-- ---------------------------------------------------------------------------------------------------
--
-- **`L208` (owner, 2026-09-29) changes what the CAR receives, not this multiplier.** Live evidence `E26`:
-- on this engine `gripScale` above 1.0 loosens the rear (oversteer) and below 1.0 pushes (understeer),
-- because the Carrier scales lateral force and never the yaw moment. So "more grip" is not a reward here;
-- it is a balance. `levers()` therefore maps COLD to a push (grip and brake down, as before) and
-- OVERHEATED to a loose rear with weak brakes (grip up, brake down). `gripMultiplier` keeps its symmetric
-- <= 1.0 meaning for the gauge and the explain line.
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

    -- **`AMBIENT_DEFAULT` is a TRACK temperature, not an air temperature**, because the road is what the
    -- tyre actually exchanges heat with. It is the reading used when the clock and the sky are both
    -- unknown, which is the only case where the two bodies collapse back into one number.
    M.AMBIENT_DEFAULT = 20.0    -- degrees C, a mild Night City afternoon

    -- ---- air
    M.AIR_SWING_C = 8.0         -- +/- this over a day. Night City, not a desert.
    M.PEAK_HOUR = 15.0          -- the daily maximum, mid-afternoon rather than noon
    M.AIR_WET_COOLING_C = 4.0   -- rain cools the air a little

    -- ---- the road, which is NOT the air
    --
    -- Asphalt is not a thermometer for the sky. In sun it absorbs and runs far hotter than the air above
    -- it -- 15 to 25 degrees is ordinary -- and under a clear night sky it RADIATES to space and runs
    -- COLDER than the air, which is why road frost forms on nights when the air never reaches zero. Both
    -- directions are real and the model carries both rather than treating night as "less day".
    --
    -- Rain removes the solar term entirely rather than reducing it: a wet road is not a sunlit road, and
    -- standing water is a far better heat sink than moving air. **This is the whole of the owner's point
    -- -- a warm track and a cold track are different places, and the tyre only learns about them through
    -- how hard it has to work to stay warm.**
    M.SOLAR_GAIN_C = 16.0       -- peak sun-on-asphalt gain over air, dry
    M.NIGHT_RADIATION_C = 5.0   -- clear-sky radiative loss below air, dry
    M.TRACK_WET_COOLING_C = 8.0 -- standing water on the surface

    -- ---------------------------------------------------------------------------------------------
    -- `L209`: every weather is a road of its own (owner, 2026-09-29: "all weather conditions have their
    -- uniquely tuned logical properties, should combine nicely with time of day").
    -- ---------------------------------------------------------------------------------------------
    --
    --   sun   share of the daytime solar gain that reaches the asphalt (1 = clear sky)
    --   sky   share of the night-time radiative loss (a clear sky pulls heat off the road; cloud blankets it)
    --   airC  air temperature offset for this weather
    --   wet   road wetness this weather drives toward (rain soaks it; fog leaves a damp film)
    --   grip / drag  surface contamination, applied by `parts.handling.weatherContributor`
    --
    -- Time of day multiplies through `sun` and `sky`, so a sunny afternoon is the hottest road and a
    -- sunny night the coldest, while heavy cloud keeps both mild. First-pass values to tune on the wheel.
    M.WEATHER = {
        sunny       = { sun = 1.00, sky = 1.00, airC =  1.0, wet = 0.00 },
        lightclouds = { sun = 0.80, sky = 0.80, airC =  0.0, wet = 0.00 },
        cloudy      = { sun = 0.50, sky = 0.50, airC = -1.0, wet = 0.00 },
        heavyclouds = { sun = 0.25, sky = 0.25, airC = -2.0, wet = 0.00 },
        rain        = { sun = 0.00, sky = 0.00, airC =  0.0, wet = 1.00 },  -- rain cooling is AIR_WET_COOLING_C
        fog         = { sun = 0.30, sky = 0.20, airC = -3.0, wet = 0.15 },  -- cool, damp film, little sun
        pollution   = { sun = 0.60, sky = 0.40, airC =  2.0, wet = 0.00, grip = 0.97 },  -- smog traps heat; grime
        sandstorm   = { sun = 0.40, sky = 0.30, airC =  4.0, wet = 0.00, grip = 0.95, drag = 1.05 },  -- hot, gritty
    }
    -- An unknown or absent weather is the old model exactly: full sun, full sky, no offset, dry.
    M.WEATHER_NEUTRAL = { sun = 1.00, sky = 1.00, airC = 0.0, wet = 0.00 }
    function M.weatherProfile(weatherId)
        return M.WEATHER[tostring(weatherId or "")] or M.WEATHER_NEUTRAL
    end

    -- ---- the road's own grip
    --
    -- **A warm road is grippier than a cold one, and that is independent of the tyre on it.** A tyre
    -- perfectly in its own window on a freezing road still has a freezing road. Expressed the same way as
    -- the tyre window and for the same reason: an optimum that costs NOTHING, with a penalty either side.
    -- "A warm track is better" and "a warm track is where you stop being charged" are the same statement
    -- under `L156` point 3, and only the second one is a ceiling we are allowed to write.
    --
    -- Asymmetric on purpose. Cold asphalt is a real and large grip loss; hot asphalt goes slightly greasy
    -- as the binder softens, which is a smaller effect and a much rarer one on these streets.
    M.SURFACE_OPTIMUM = 32.0
    M.SURFACE_COLD_SPAN = 32.0  -- 0C is fully cold
    M.SURFACE_HOT_SPAN = 28.0   -- 60C is fully hot
    M.SURFACE_COLD_DEPTH = 0.10
    M.SURFACE_HOT_DEPTH = 0.04
    -- `L208`: a hot road makes the car livelier rather than slower -- grip up to x1.03 (a little looser).
    M.SURFACE_HOT_LOOSE = 0.03

    M.OPTIMUM = 85.0            -- the centre of the window
    M.HALF_WINDOW = 35.0        -- +/- this from OPTIMUM is "fully cold" / "fully hot"
    M.PENALTY = 0.15            -- grip and brake cost at either extreme, so x0.85
    -- `L208`: an overheated tyre goes LOOSE with weak brakes. Fully hot: grip x1.12 (rear steps out),
    -- brake x0.88. First-pass values to tune on the wheel.
    M.HOT_LOOSE = 0.12
    M.HOT_BRAKE = 0.12

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
        "the road's THERMAL INERTIA: track temperature here responds to rain and to the clock instantly, "
            .. "where real asphalt carries hours of stored heat and stays warm through a short shower",
        "one road everywhere -- no shade, no tunnels, no bridge deck, and no difference between a "
            .. "sunlit straight and the same corner under an overpass",
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

    local function wetnessOf(conditions)
        return clamp(tonumber(conditions.wetness) or 0, 0, 1)
    end

    --- Where in the day we are, as `cos(phase - peak)`: +1 at `PEAK_HOUR`, -1 twelve hours later.
    ---
    --- **Returns nil when the clock is unknown**, and every caller then omits its daily term rather than
    --- assuming noon. A model that guesses the time of day would hand a server with no environment feed a
    --- confident, wrong track temperature -- which is exactly the shape of `KB-151`, where weather read
    --- as permanently dry and nothing said so.
    local function daylight(conditions)
        local seconds = tonumber(conditions.secondsOfDay)
        if not seconds or seconds ~= seconds then return nil end
        local phase = ((seconds % 86400) / 86400) * 2 * math.pi
        return math.cos(phase - (M.PEAK_HOUR / 24) * 2 * math.pi)
    end

    --- Air temperature. The sky's number.
    ---
    --- Nothing in the mechanical model reads this directly -- it exists because the track is defined
    --- RELATIVE to it, and because a difference between two numbers is only meaningful if both are named.
    function M.airTemperature(conditions)
        conditions = conditions or {}
        local out = (tonumber(conditions.baseC) or M.AMBIENT_DEFAULT) + M.weatherProfile(conditions.weather).airC
        local daily = daylight(conditions)
        if daily then out = out + M.AIR_SWING_C * daily end
        return out - M.AIR_WET_COOLING_C * wetnessOf(conditions)
    end

    --- **Track temperature: the road's own number, and the one the tyre actually feels.**
    ---
    --- Air plus solar gain by day, minus radiative loss by night, minus the heat standing water carries
    --- away. Rain scales the radiative terms to zero because a wet road is neither sunlit nor radiating to
    --- a clear sky -- it is under cloud, wet, and pinned near the air.
    ---
    --- The spread this produces is the point. Dry mid-afternoon reaches the low forties while a wet
    --- pre-dawn sits near freezing, so the SAME driving warms a tyre into the window on one and leaves it
    --- cold on the other, without the tyre model knowing anything about weather at all.
    function M.trackTemperature(conditions)
        conditions = conditions or {}
        local w = wetnessOf(conditions)
        local out = M.airTemperature(conditions)
        local daily = daylight(conditions)
        if daily then
            local p = M.weatherProfile(conditions.weather)
            local solar = M.SOLAR_GAIN_C * p.sun * math.max(0, daily)
            local radiated = M.NIGHT_RADIATION_C * p.sky * math.max(0, -daily)
            out = out + (solar - radiated) * (1 - w)
        end
        return out - M.TRACK_WET_COOLING_C * w
    end

    --- What the tyre exchanges heat with. **This is the track, not the air**, and the alias exists so that
    --- every call site reads as the thermal statement it is rather than having to know which body it meant.
    ---
    --- Day, night and weather reach the tyre through here and nowhere else. None of them gets a lever on
    --- the tyre: a cold night acts by making a tyre harder to warm, which is the real mechanism, rather
    --- than by docking grip for driving after dark.
    function M.ambient(conditions)
        return M.trackTemperature(conditions)
    end

    --- Where the ROAD is against its own optimum: -1 fully cold, 0 best, +1 fully hot.
    function M.surfacePosition(trackC)
        local T = tonumber(trackC)
        if not T or T ~= T then return nil end
        if T < M.SURFACE_OPTIMUM then
            return clamp((T - M.SURFACE_OPTIMUM) / M.SURFACE_COLD_SPAN, -1, 0)
        end
        return clamp((T - M.SURFACE_OPTIMUM) / M.SURFACE_HOT_SPAN, 0, 1)
    end

    --- The road's grip and brake multiplier. **Never above 1.0**, the same promise the tyre window makes.
    ---
    --- **This must not read wetness, and that is load-bearing.** Rain is already charged directly by
    --- `parts.handling.weatherContributor`. If the road ALSO charged for being wet, a wet night would be
    --- billed three times for one weather state and the model would collapse into "rain is everything".
    --- What this charges for is TEMPERATURE, which a dry winter morning has too.
    function M.surfaceMultiplier(trackC)
        local x = M.surfacePosition(trackC)
        if not x then return 1.0 end
        local depth = (x < 0) and M.SURFACE_COLD_DEPTH or M.SURFACE_HOT_DEPTH
        return 1.0 - depth * (x * x)
    end

    --- One human line about the road, matching `explain`'s register.
    function M.explainSurface(trackC)
        local x = M.surfacePosition(trackC)
        if not x then return "track temperature unknown" end
        local band
        if x <= -0.66 then band = "FREEZING"
        elseif x < -0.2 then band = "cold"
        elseif x <= 0.2 then band = "warm"
        elseif x < 0.66 then band = "hot"
        else band = "GREASY" end
        return ("%.0fC %s track (x%.3f grip)"):format(trackC, band, M.surfaceMultiplier(trackC))
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

    --- What the CAR receives from tyre temperature (`L208`, `E26`). Cold: grip and brake down together
    --- (a push). In the window: nothing. Overheated: grip UP (a loose rear) and brake DOWN.
    function M.levers(temperatureC)
        local x = M.position(temperatureC)
        if not x then return { grip = 1.0, brake = 1.0 } end
        if x <= 0 then
            local m = 1.0 - M.PENALTY * (x * x)
            return { grip = m, brake = m }
        end
        return { grip = 1.0 + M.HOT_LOOSE * (x * x), brake = 1.0 - M.HOT_BRAKE * (x * x) }
    end

    --- What the CAR receives from the road's temperature (`L208`). A cold road pushes (grip and brake
    --- down, as `surfaceMultiplier`); a hot road is livelier (grip up slightly, brake untouched).
    function M.surfaceLevers(trackC)
        local x = M.surfacePosition(trackC)
        if not x then return { grip = 1.0, brake = 1.0 } end
        if x < 0 then
            local m = 1.0 - M.SURFACE_COLD_DEPTH * (x * x)
            return { grip = m, brake = m }
        end
        return { grip = 1.0 + M.SURFACE_HOT_LOOSE * (x * x), brake = 1.0 }
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
        local l = M.levers(temperatureC)
        return ("%.0fC %s (grip x%.3f, brake x%.3f)"):format(temperatureC, band, l.grip, l.brake)
    end

    -- The promise the rest of the system relies on, checked at load rather than trusted.
    assert(math.abs(M.gripMultiplier(M.OPTIMUM) - 1.0) < 1e-9, "the window must cost nothing")
    assert(math.abs(M.gripMultiplier(M.OPTIMUM + M.HALF_WINDOW) - (1.0 - M.PENALTY)) < 1e-9,
        "fully hot must cost exactly PENALTY")
    assert(math.abs(M.gripMultiplier(M.OPTIMUM - M.HALF_WINDOW) - (1.0 - M.PENALTY)) < 1e-9,
        "fully cold must cost exactly PENALTY")
    -- The road makes the same promise the tyre does: an optimum is the absence of a charge, never a boost.
    for T = -40, 120, 2 do
        assert(M.surfaceMultiplier(T) <= 1.0, "a warm track must not be a boost")
    end
    assert(math.abs(M.surfaceMultiplier(M.SURFACE_OPTIMUM) - 1.0) < 1e-9, "the best road costs nothing")
    -- Cold must cost more than hot, or the asymmetry that motivated two spans is decorative.
    assert(M.surfaceMultiplier(M.SURFACE_OPTIMUM - M.SURFACE_COLD_SPAN)
        < M.surfaceMultiplier(M.SURFACE_OPTIMUM + M.SURFACE_HOT_SPAN),
        "freezing asphalt must cost more than greasy asphalt")
    -- A wet road can never be a hot road, whatever the hour.
    for hour = 0, 23 do
        local c = { secondsOfDay = hour * 3600 }
        local dry = M.trackTemperature(c)
        c.wetness = 1
        assert(M.trackTemperature(c) < dry, "rain must cool the road at every hour of the day")
    end
    -- With no clock and no sky the two bodies collapse to one number, and it is the declared default.
    assert(math.abs(M.trackTemperature({}) - M.AMBIENT_DEFAULT) < 1e-9,
        "unknown conditions must not invent a daily term")
    assert(#M.LOSSES > 0, "a thermal model with no stated losses is the dishonest kind")

    return M
end)
