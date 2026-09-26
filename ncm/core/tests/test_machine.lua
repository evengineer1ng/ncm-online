-- machine.flats + machine.projection -- the carrier's one calculation.
--
-- These test the RULES, not the balance. Every multiplier here is a placeholder and is expected to change;
-- the invariants are what the design ruled and what the carrier depends on being true.
local function F(T) return T.Core.get("machine.flats") end
local function P(T) return T.Core.get("machine.projection") end

local function envelope(T, inputs)
    local env, err = P(T).compose(inputs)
    T.eq(err, nil, "compose refused unexpectedly: " .. tostring(err))
    return env
end

local function flatOf(env, id)
    for _, f in ipairs(env.record.flats) do
        if f.id == id then return f end
    end
    return nil
end

return {
    -- ------------------------------------------------------------------ the vocabulary
    every_flat_names_a_family_and_a_real_suffix = function(T)
        local M = F(T)
        for _, flat in ipairs(M.FLATS) do
            T.eq(type(flat.suffix) == "string" and flat.suffix:sub(1, 1) == ".", true,
                 flat.id .. " carries a TweakDB suffix")
            T.eq(type(flat.family) == "string", true, flat.id .. " belongs to a mechanical family")
            T.eq(flat.min < flat.max, true, flat.id .. " has a real range")
            T.eq(flat.min <= 1.0 and flat.max >= 1.0, true, flat.id .. " can express no change")
        end
    end,

    the_families_that_cannot_be_felt_say_so = function(T)
        local M = F(T)
        -- The finding, not an omission: four of the twelve have no drive-model expression at all. A design
        -- that needs a radiator to be FELT learns it here rather than after building a component tree.
        T.eq(M.familyIsExpressible("brakes"), true, "brakes reach the car")
        T.eq(M.familyIsExpressible("tires"), true, "so do tyres")
        T.eq(M.familyIsExpressible("cooling"), false, "cooling has no drive-model flat")
        T.eq(M.familyIsExpressible("transmission"), false, "")
        T.eq(M.familyIsExpressible("electrical"), false, "")
        T.eq(M.familyIsExpressible("chassis"), false, "")
    end,

    provenance_is_recorded_because_two_grades_behave_differently = function(T)
        local inv = F(T).inventory()
        -- `ncm_sp` flats are ones NCM's own shipped single-player mod writes today. `documented` ones are
        -- read out of a record schema and have never been written by us. When something misbehaves live,
        -- this is the first list to look at.
        T.eq(#inv.proven > 0, true, "NCM has written some of these itself, for months")
        T.eq(#inv.documented > 0, true, "and some it has only read about")
    end,

    a_multiplier_that_makes_no_sense_becomes_no_change = function(T)
        local M = F(T)
        T.eq(M.clampMultiplier("brake_power", 0 / 0), 1.0, "NaN leaves the flat exactly as the game had it")
        T.eq(M.clampMultiplier("brake_power", math.huge), 1.0, "and so does infinity")
        T.eq(M.clampMultiplier("brake_power", "fast"), 1.0, "and so does nonsense")
        T.eq(M.clampMultiplier("no_such_flat", 2.0), 1.0, "an unknown flat cannot be moved at all")
        T.eq(M.clampMultiplier("brake_power", 99), M.get("brake_power").max, "and a wild value is bounded")
    end,

    -- ------------------------------------------------------------------ the invariant
    a_mechanical_fact_may_not_be_expressed_twice = function(T)
        -- Without this rule a limiter that withdraws acceleration through the ceiling AND detunes the engine
        -- through a flat applies itself twice, and it is invisible in both numbers.
        local _, err = P(T).compose({
            record = "Vehicle.test",
            parts = { { id = "overclock", family = "power_unit", effects = { power = 1.2 } } },
            chrome = { { id = "overclock", carrier = "ceiling", ceiling = { accelerationScale = 0.8 } } },
        })
        T.eq(err, "double_expression:overclock", "the same named fact on two carriers is refused by name")
    end,

    acceleration_can_be_withheld_and_never_added = function(T)
        local env = envelope(T, {
            record = "Vehicle.test",
            chrome = { { id = "surge", carrier = "ceiling", ceiling = { accelerationScale = 1.6 } } },
        })
        T.eq(env.ceiling.accelerationScale, P(T).MAX_ACCELERATION_SCALE,
             "the platform's hard rule, enforced after every layer rather than trusted to each")
    end,

    power_above_native_goes_on_the_carrier_where_it_is_visible = function(T)
        -- `engineMaxTorque` has no `<= 1` ceiling. That is the honest way to add power, and it is a record
        -- flat, so it reads as a change to the machine rather than as a raised speed limit (IDEA-463).
        local env = envelope(T, {
            record = "Vehicle.test",
            parts = { { id = "big_turbo", family = "power_unit", effects = { engine_torque = 1.3 } } },
        })
        T.eq(flatOf(env, "engine_torque").multiplier > 1.0, true, "more torque than the factory gave it")
    end,

    -- ------------------------------------------------------------------ legibility
    every_movement_of_every_number_is_traced = function(T)
        local env = envelope(T, {
            record = "Vehicle.test",
            parts = { { id = "pads", family = "brakes", effects = { brake_power = 1.2 } } },
            weather = { wetness = 1.0 },
        })
        T.eq(#env.trace > 0, true, "")
        local sawPart, sawWeather = false, false
        for _, t in ipairs(env.trace) do
            T.eq(t.id ~= nil and t.by ~= nil, true, "a trace entry names what moved and who moved it")
            if t.by == "pads" then sawPart = true end
            if t.by == "wet" then sawWeather = true end
        end
        T.eq(sawPart and sawWeather, true, "a driver can see why their car is the way it is")
        T.eq(#P(T).explain(env) > 0, true, "and can be told in words")
    end,

    -- ------------------------------------------------------------------ parts
    a_part_may_not_quietly_move_another_familys_flat = function(T)
        local _, err = P(T).compose({
            record = "Vehicle.test",
            parts = { { id = "pads", family = "brakes", effects = { spring = 1.3 } } },
        })
        T.eq(err, "family_mismatch:spring",
             "a brake part that moves a suspension flat is refused; if it does both it declares both")
    end,

    a_part_that_could_never_be_felt_is_named_not_ignored = function(T)
        local _, err = P(T).compose({
            record = "Vehicle.test",
            parts = { { id = "rad", family = "cooling", effects = {} } },
        })
        T.eq(err, "family_not_expressible:cooling",
             "not a failure of the part -- a failure of the assumption it could be felt")
    end,

    an_unknown_flat_is_refused_by_name = function(T)
        local _, err = P(T).compose({
            record = "Vehicle.test",
            parts = { { id = "x", family = "brakes", effects = { turbo_encabulator = 2.0 } } },
        })
        T.eq(err, "unknown_flat:turbo_encabulator", "")
    end,

    parts_compose_multiplicatively_and_stay_inside_the_flats_range = function(T)
        local big = {}
        for i = 1, 20 do
            big[i] = { id = "pads" .. i, family = "brakes", effects = { brake_power = 1.5 } }
        end
        local env = envelope(T, { record = "Vehicle.test", parts = big })
        T.eq(flatOf(env, "brake_power").multiplier, F(T).get("brake_power").max,
             "twenty brake kits do not make an infinitely good brake")
    end,

    -- ------------------------------------------------------------------ weather
    rain_is_expressed_as_grip_not_as_a_speed_limit = function(T)
        local env = envelope(T, { record = "Vehicle.test", weather = { wetness = 1.0 } })
        -- Still the founding claim: rain acts on the contact patch, never as a speed limit. `IDEA-057`'s
        -- ceiling approximation stays retired.
        T.eq(next(env.ceiling), nil,
             "NOT the top-speed ceiling -- IDEA-057's approximation is retired, not reproduced")
        -- What this carrier expresses is the SHAPE of the let-go, which a scalar force write cannot do.
        T.eq(flatOf(env, "slip_curve").multiplier < 1.0, true, "wet makes the let-go less progressive")
        T.eq(flatOf(env, "turn_friction").multiplier < 1.0, true, "")
    end,

    the_record_carrier_no_longer_expresses_wet_grip_MAGNITUDE = function(T)
        local env = envelope(T, { record = "Vehicle.test", weather = { wetness = 1.0 } })
        -- **`L158`.** `lateral_grip` and `brake_friction` left this table for two reasons at once: both
        -- write to flats `KB-145` proved do not resolve, so they were the two LARGEST weather effects and
        -- both were silent no-ops; and the instance carrier expresses magnitude live, per Machine, on a
        -- car that has already spawned -- which the spawn-cached record channel can never do.
        T.eq(flatOf(env, "lateral_grip"), nil, "grip magnitude moved to the instance carrier")
        T.eq(flatOf(env, "brake_friction"), nil, "and so did brake magnitude")
        -- The guard that will catch it coming back the day IDEA-508 revives those flats.
        local X = T.Core.get("machine.expression")
        T.eq(X.mayExpress("grip_magnitude", "record"), false)
        T.eq(X.mayExpress("slip_progression", "record"), true, "curve shape stayed")
    end,

    weather_is_continuous_so_damp_is_not_soaked = function(T)
        local damp = envelope(T, { record = "Vehicle.test", weather = { wetness = 0.25 } })
        local soaked = envelope(T, { record = "Vehicle.test", weather = { wetness = 1.0 } })
        T.eq(flatOf(damp, "slip_curve").multiplier > flatOf(soaked, "slip_curve").multiplier, true, "")
        T.eq(P(T).isEmpty(envelope(T, { record = "Vehicle.test", weather = { wetness = 0 } })), true,
             "a dry road asks the carrier for nothing at all")
    end,

    -- ------------------------------------------------------------------ rules
    the_ruleset_only_ever_narrows = function(T)
        local env = envelope(T, {
            record = "Vehicle.test",
            chrome = { { id = "limiter", carrier = "ceiling", ceiling = { topSpeedKph = 200 } } },
            ruleset = { ceiling = { topSpeedKph = 350 } },
        })
        T.eq(env.ceiling.topSpeedKph, 200, "the most restrictive writer wins, whatever order they arrived in")
    end,

    a_class_can_forbid_a_flat_outright = function(T)
        local env = envelope(T, {
            record = "Vehicle.test",
            parts = { { id = "turbo", family = "power_unit", effects = { engine_torque = 1.4 } } },
            ruleset = { forbidFlats = { "engine_torque" } },
        })
        T.eq(flatOf(env, "engine_torque"), nil, "homologation removes it from the car, not from the record")
        local forbidden = false
        for _, t in ipairs(env.trace) do if t.by == "forbidden" then forbidden = true end end
        T.eq(forbidden, true, "and says so, rather than silently dropping it")
    end,

    taper_never_goes_below_the_platforms_floor = function(T)
        local env = envelope(T, { record = "Vehicle.test", ruleset = { ceiling = { taperKph = 1 } } })
        T.eq(env.ceiling.taperKph, P(T).MIN_TAPER_KPH, "")
    end,

    -- ------------------------------------------------------------------ the envelope
    restoring_is_not_the_same_instruction_as_applying_nothing = function(T)
        local M = P(T)
        local empty = envelope(T, { record = "Vehicle.test" })
        local clear = M.clear("Vehicle.test")
        T.eq(M.isEmpty(empty), true, "nothing to apply")
        T.eq(M.isEmpty(clear), false, "but 'put back what you captured' is a real instruction")
        T.eq(clear.record.restore, true, "")
    end,

    an_envelope_without_a_record_is_refused = function(T)
        local _, err = P(T).compose({})
        T.eq(err, "no_record", "there is no such thing as handling that belongs to no vehicle")
    end,

    the_envelope_is_versioned_because_the_carrier_is_shipped_separately = function(T)
        local env = envelope(T, { record = "Vehicle.test" })
        T.eq(env.v, P(T).ENVELOPE_VERSION, "a player's installed carrier can be older than the server")
        T.eq(env.record.path, "Vehicle.test", "")
    end,
}
