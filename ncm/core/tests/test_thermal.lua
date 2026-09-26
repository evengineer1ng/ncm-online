-- parts.thermal -- tyre temperature as a model with the right shape.
--
-- The constants are deliberately NOT pinned. They are a first pass awaiting play data, exactly like
-- `machine.projection`'s `WET` table and `parts.handling`'s exponents, and a test that froze them would
-- turn tuning into a build failure. What is pinned is the shape, the bounds, and the two promises the rest
-- of the system relies on:
--
--   1. **The multiplier never exceeds 1.0.** The window is a penalty, not a boost -- the owner's rule, and
--      what lets this inherit `L156` point 3 instead of needing authorisation to add force.
--   2. **Heating carries a speed term**, because `integral F dt` is momentum and heating is work. Without
--      it a 30 km/h hairpin heats a tyre as much as a 200 km/h sweeper.
local function TH(T) return T.Core.get("parts.thermal") end
local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end

return {
    -- ------------------------------------------------------------------ the window is a penalty
    the_multiplier_is_never_above_one_for_any_input = function(T)
        local M = TH(T)
        -- Swept well outside the legal range on purpose: a boost must be unreachable, not merely absent
        -- from the values we happen to produce.
        for t = -100, 300, 5 do
            T.ok(M.gripMultiplier(t) <= 1.0,
                ("%dC must not be a boost; being in the window is the absence of a penalty"):format(t))
        end
        T.ok(M.gripMultiplier(0 / 0) <= 1.0, "and NaN is not a loophole")
    end,

    the_optimum_costs_nothing_and_the_extremes_cost_exactly_the_penalty = function(T)
        local M = TH(T)
        T.ok(near(M.gripMultiplier(M.OPTIMUM), 1.0), "in the window, no charge")
        T.ok(near(M.gripMultiplier(M.OPTIMUM + M.HALF_WINDOW), 1.0 - M.PENALTY), "fully hot")
        T.ok(near(M.gripMultiplier(M.OPTIMUM - M.HALF_WINDOW), 1.0 - M.PENALTY), "fully cold")
        -- Symmetric: overheating and freezing cost the same, which is a design choice worth stating.
        T.ok(near(M.gripMultiplier(M.OPTIMUM + 20), M.gripMultiplier(M.OPTIMUM - 20)))
    end,

    the_penalty_is_quadratic_so_the_window_has_width = function(T)
        local M = TH(T)
        -- A plateau would make the edge of the window a knife edge. A parabola means the middle third
        -- costs almost nothing, which is what makes it feel like a window a driver aims for.
        local middle = M.gripMultiplier(M.OPTIMUM + M.HALF_WINDOW * 0.33)
        T.ok(middle > 1.0 - (M.PENALTY * 0.2),
            "a third of the way out still costs under a fifth of the penalty")
        local edge = M.gripMultiplier(M.OPTIMUM + M.HALF_WINDOW * 0.9)
        T.ok(edge < 1.0 - (M.PENALTY * 0.7), "and near the edge most of it is being paid")
    end,

    position_is_normalised_and_bounded = function(T)
        local M = TH(T)
        T.ok(near(M.position(M.OPTIMUM), 0), "the window centre is zero")
        T.ok(near(M.position(M.OPTIMUM + M.HALF_WINDOW), 1), "fully hot is +1")
        T.ok(near(M.position(M.OPTIMUM - M.HALF_WINDOW), -1), "fully cold is -1")
        T.ok(near(M.position(1000), 1), "and it clamps rather than running away")
        T.ok(near(M.position(-1000), -1))
        T.eq(M.position(nil), nil, "absent is not a position -- IDEA-361, a dash not a resting value")
    end,

    -- ------------------------------------------------------------------ heat is work, not momentum
    load_rises_with_speed_at_the_same_cornering_force = function(T)
        local M = TH(T)
        -- **The correction this model was rebuilt for.** Same lateral acceleration, different speed: the
        -- faster corner must deposit more heat, because work is force times distance.
        local slow = M.load(10, 8)
        local fast = M.load(40, 8)
        T.ok(fast > slow * 2,
            "a fast corner does far more work than a slow one at the same g -- force alone would tie them")
    end,

    cornering_heats_more_than_cruising = function(T)
        local M = TH(T)
        local cruise = M.load(30, 0)
        local corner = M.load(30, 8)
        T.ok(corner > cruise, "at the same speed, cornering is what cooks a tyre")
    end,

    load_is_zero_at_rest_and_never_negative = function(T)
        local M = TH(T)
        T.ok(near(M.load(0, 0), 0), "a parked car does no work on its tyres")
        T.ok(M.load(-10, -8) >= 0, "reversing and turning right are still work, not refrigeration")
        T.ok(M.load(0 / 0, 0 / 0) >= 0, "NaN cannot produce negative heat")
    end,

    -- ------------------------------------------------------------------ the integration
    a_tyre_warms_to_the_window_in_about_a_minute_under_load = function(T)
        local M = TH(T)
        -- The owner's stated intent: roughly a lap, not a drag run and not a stint. Tolerance is wide
        -- because the constant is tunable; what must hold is the ORDER OF MAGNITUDE.
        local t = M.initial({})
        local load = M.load(35, 7)              -- sustained hard driving
        for _ = 1, 60 do t = M.step(t, load, M.AMBIENT_DEFAULT, 1.0, 35) end
        T.ok(M.position(t) > -0.35,
            ("after 60s of hard driving a tyre should be at or near the window, got %.0fC"):format(t))
        T.ok(t <= M.MAX_C)
    end,

    a_parked_tyre_returns_to_ambient_and_stops_there = function(T)
        local M = TH(T)
        local t = 140
        for _ = 1, 600 do t = M.step(t, 0, 20, 1.0, 0) end
        T.ok(near(t, 20, 1.0), "it settles AT ambient rather than overshooting below it")
        -- And it keeps cooling while the player is out of the car, which is the whole reason this state
        -- lives with the asset rather than with the driver.
        local warm = M.step(85, 0, 20, 30, 0)
        T.ok(warm < 85 and warm > 20, "half a minute parked sheds heat without dumping all of it")
    end,

    a_hitched_step_cannot_teleport_the_temperature = function(T)
        local M = TH(T)
        -- The host's 1 Hz loop is a MINIMUM wait, not a period, and a resumed session could hand this a
        -- single enormous dt. Clamping the step is what stops a paused game from freezing a tyre solid.
        local huge = M.step(120, 0, 20, 100000, 0)
        local bounded = M.step(120, 0, 20, M.MAX_STEP_SECONDS, 0)
        T.ok(near(huge, bounded), "a 100000-second step is treated as the longest legal one")
        T.ok(near(M.step(85, 5, 20, 0, 0), 85), "a zero step changes nothing")
        T.ok(near(M.step(85, 5, 20, -5, 0), 85), "and a negative one is not a time machine")
    end,

    temperature_stays_inside_its_bounds_under_abuse = function(T)
        local M = TH(T)
        local t = 85
        for _ = 1, 5000 do t = M.step(t, 20, 200, M.MAX_STEP_SECONDS, 200) end
        T.ok(t <= M.MAX_C, "sustained maximum load cannot melt through the ceiling")
        local c = 85
        for _ = 1, 5000 do c = M.step(c, 0, -100, M.MAX_STEP_SECONDS, 200) end
        T.ok(c >= M.MIN_C, "nor freeze through the floor")
    end,

    airflow_makes_a_moving_car_cool_faster_than_a_parked_one = function(T)
        local M = TH(T)
        local parked = M.step(120, 0, 20, 5, 0)
        local moving = M.step(120, 0, 20, 5, 60)
        T.ok(moving < parked, "a cooldown lap is a real thing")
    end,

    -- ------------------------------------------------------------------ ambient, and day/night
    night_is_colder_than_afternoon = function(T)
        local M = TH(T)
        -- **Day/night reaches the car through ambient and through nothing else.** It gets no lever: a cold
        -- night genuinely acts by making tyres harder to warm, not by making grip worse directly.
        local afternoon = M.ambient({ secondsOfDay = 15 * 3600 })
        local predawn = M.ambient({ secondsOfDay = 4 * 3600 })
        T.ok(afternoon > predawn, "mid-afternoon is the peak, before dawn the trough")
        T.ok(afternoon - predawn > 5, "and the swing is big enough to change a warm-up")
    end,

    rain_pulls_heat_out_faster_than_cold_air = function(T)
        local M = TH(T)
        local dry = M.ambient({ wetness = 0 })
        local wet = M.ambient({ wetness = 1 })
        T.ok(wet < dry - 5, "standing water is a heat sink, which is why wet tyres struggle to switch on")
        T.ok(M.ambient({ wetness = 5 }) >= M.ambient({ wetness = 1 }) - 1e-9, "wetness clamps at 1")
    end,

    a_tyre_that_has_never_been_driven_is_at_ambient = function(T)
        local M = TH(T)
        T.ok(near(M.initial({ baseC = 12 }), 12), "cold, not conveniently in the window")
        T.ok(M.initial({}) < M.OPTIMUM, "a fresh car starts outside the window and has to earn it")
    end,

    -- ------------------------------------------------------------------ honesty
    the_model_enumerates_what_it_cannot_do = function(T)
        local M = TH(T)
        T.ok(#M.LOSSES >= 4, "a thermal model with no stated losses is the dishonest kind")
        local all = table.concat(M.LOSSES, " "):lower()
        T.match(all, "per%-corner", "per-corner is refused and says so")
        T.match(all, "slip", "and slip velocity, which is the real heat source it proxies")
    end,

    explain_names_the_band_a_driver_is_in = function(T)
        local M = TH(T)
        T.match(M.explain(M.OPTIMUM), "WINDOW")
        T.match(M.explain(M.OPTIMUM - M.HALF_WINDOW), "COLD")
        T.match(M.explain(M.OPTIMUM + M.HALF_WINDOW), "OVERHEAT")
        T.match(M.explain(nil), "unknown", "and absent is unknown, never a plausible number")
    end,
}
