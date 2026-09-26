-- ncm-core module: machine.projection
--
-- **The one calculation.** Mechanical truth -- what is fitted, what is worn, what the weather is doing, what
-- the class permits, what chrome is running -- goes in. A versioned envelope for the carrier comes out. Pure:
-- no database, no clock, no randomness, no TweakDB. `ncm/carrier` applies what this produces and decides
-- nothing (`L135`).
--
-- TWO CARRIERS, AND A FACT MAY USE ONLY ONE.
--
--   * `record`  -- drive-model flats. Per-RECORD and **spawn-cached**: it reaches a car when the car spawns,
--                  never mid-stint. Honest for factory specification, fitted Parts, setup, class rules and
--                  weather. Dishonest for anything that expires or wears during a race (Report 36 section 4).
--   * `ceiling` -- the platform's own `{topSpeedKph, accelerationScale, taperKph}`. Per-INSTANCE and live, so
--                  it is the only carrier that can express a timed effect or differentiate two drivers of the
--                  same model. Narrow, but live.
--
-- The invariant that makes this safe to extend: **the same mechanical fact may not be expressed twice.** A
-- contribution declares its carrier and is refused if it tries both. Without that rule, a chrome limiter that
-- withdraws acceleration through the ceiling AND detunes the engine through a flat applies itself twice, and
-- nobody can see it in either number.
--
-- Balance is not decided here. `WET`, and the ranges in `machine.flats`, are placeholders awaiting play data.
local Core = NcmCore

Core.define("machine.projection", function(C)
    local Flats = C.get("machine.flats")

    local M = { version = "0.0.1" }

    M.ENVELOPE_VERSION = 1

    -- The platform's hard rule, not a balance choice: acceleration may be withheld and never added. Power
    -- above native comes from the record carrier's `engine_torque`, where it is visible as what it is.
    M.MAX_ACCELERATION_SCALE = 1.0
    M.MIN_TAPER_KPH = 3
    M.DEFAULT_TAPER_KPH = 12

    -- Wet weather, expressed as what water does to a contact patch rather than as a lowered speed limit.
    -- `wetness` is 0..1. Retires IDEA-057's ceiling approximation, which Report 34 section 8 grades
    -- semantically dishonest when presented as grip.
    -- **Two entries left this table on 2026-09-26 (`L158`), and for two reasons at once.**
    --
    --   1. `lateral_grip` (0.18) and `brake_friction` (0.15) write to `.frictionMulLateral` and
    --      `.brakingFriction`, and `KB-145` proved neither resolves on this build. They were the two
    --      LARGEST weather effects and they were silent no-ops -- so more than half of wet weather was
    --      already doing nothing.
    --   2. The instance carrier expresses grip and brake magnitude live, per Machine, on a car that is
    --      already spawned. The record carrier cannot: it is spawn-cached, so rain arriving mid-drive
    --      never reached the car you were sitting in.
    --
    -- What stays is what the instance carrier provably CANNOT do: the SHAPE of the let-go. `slip_curve`
    -- and `turn_friction` are curve geometry, and a scalar force multiplier has no way to express them.
    -- That is the split -- each carrier keeps the half it can actually carry.
    M.WET = {
        slip_curve     = 0.12,   -- wet makes the let-go less progressive
        turn_friction  = 0.12,
    }

    -- **One mechanical fact, one carrier, checked at load (`L158`).** `claim()` below guards against one
    -- contribution expressing the same fact twice inside a single draft; it cannot see the OTHER composer
    -- at all, because `parts.handling` builds its own draft in its own module. This assertion is what
    -- spans them, and it is what will fire the day `IDEA-508` makes the two dead weather flats resolve
    -- again and somebody re-adds them to `M.WET`.
    local Expression = C.get("machine.expression")
    Expression.assertOwns("record", { "slip_progression", "turn_friction", "mass", "steering_geometry" },
        "machine.projection")
    for _, fact in ipairs({ "grip_magnitude", "brake_magnitude" }) do
        assert(not Expression.mayExpress(fact, "record"),
            "machine.projection must not express '" .. fact .. "': it moved to the instance carrier")
    end

    local LAYERS = { "factory", "parts", "wear", "weather", "chrome", "ruleset" }
    local LAYER_ORDER = {}
    for i, name in ipairs(LAYERS) do LAYER_ORDER[name] = i end

    ---------------------------------------------------------------------------------------------------
    -- Building
    ---------------------------------------------------------------------------------------------------

    local function newDraft(recordPath, at)
        return {
            v = M.ENVELOPE_VERSION,
            at = at,
            record = { path = recordPath, flats = {} },
            ceiling = {},
            trace = {},
            _mult = {},          -- flatId -> running multiplier
            _claimed = {},       -- contribution name -> carrier, so nothing is expressed twice
        }
    end

    --- Multiply one flat and write the reason down. Every movement of every number passes through here, which
    --- is why `trace` can never drift out of step with what is applied.
    local function contribute(draft, layer, flatId, multiplier, by)
        local before = draft._mult[flatId] or 1.0
        local after = Flats.clampMultiplier(flatId, before * multiplier)
        if after == before then return end
        draft._mult[flatId] = after
        draft.trace[#draft.trace + 1] = {
            carrier = "record", layer = layer, id = flatId,
            from = before, to = after, by = by,
        }
    end

    local function claim(draft, name, carrier)
        local held = draft._claimed[name]
        if held and held ~= carrier then return false end
        draft._claimed[name] = carrier
        return true
    end

    ---------------------------------------------------------------------------------------------------
    -- The layers
    ---------------------------------------------------------------------------------------------------

    --- `effects` is `{ [flatId] = multiplier }`. Returns nil on success, or a named refusal.
    local function applyEffects(draft, layer, effects, by, family)
        if type(effects) ~= "table" then return nil end
        for flatId, multiplier in pairs(effects) do
            if not Flats.isKnown(flatId) then return "unknown_flat:" .. tostring(flatId) end
            if family then
                local owner = Flats.get(flatId).family
                if owner ~= family then
                    -- A brake part that quietly moves a suspension flat is how a parts economy stops being
                    -- legible. If it genuinely does both, it declares two effects, not one disguised.
                    return "family_mismatch:" .. tostring(flatId)
                end
            end
            contribute(draft, layer, flatId, multiplier, by)
        end
        return nil
    end

    local function applyParts(draft, parts)
        if type(parts) ~= "table" then return nil end
        for _, part in ipairs(parts) do
            local family = part.family
            if family and not Flats.familyIsExpressible(family) then
                -- Not a failure of the part. A failure of the assumption that it could ever be felt.
                return "family_not_expressible:" .. tostring(family)
            end
            if not claim(draft, part.id or "part", "record") then
                return "double_expression:" .. tostring(part.id)
            end
            local err = applyEffects(draft, "parts", part.effects, part.id, family)
            if err then return err end
        end
        return nil
    end

    local function applyWeather(draft, weather)
        if type(weather) ~= "table" then return nil end
        local wetness = tonumber(weather.wetness) or 0
        if wetness ~= wetness then wetness = 0 end
        if wetness < 0 then wetness = 0 elseif wetness > 1 then wetness = 1 end
        if wetness == 0 then return nil end
        for flatId, depth in pairs(M.WET) do
            contribute(draft, "weather", flatId, 1.0 - (depth * wetness), "wet")
        end
        return nil
    end

    local function applyChrome(draft, chrome)
        if type(chrome) ~= "table" then return nil end
        for _, effect in ipairs(chrome) do
            local name = effect.id or "chrome"
            local carrier = effect.carrier or "ceiling"
            if carrier ~= "ceiling" and carrier ~= "record" then
                return "unknown_carrier:" .. tostring(carrier)
            end
            if not claim(draft, name, carrier) then
                return "double_expression:" .. tostring(name)
            end
            if carrier == "record" then
                local err = applyEffects(draft, "chrome", effect.effects, name, nil)
                if err then return err end
            else
                -- A timed effect belongs on the live carrier. Most restrictive writer wins; nothing here can
                -- raise a ceiling, only lower one, so order of application cannot matter.
                local c = effect.ceiling
                if type(c) == "table" then
                    local top = tonumber(c.topSpeedKph)
                    if top and (not draft.ceiling.topSpeedKph or top < draft.ceiling.topSpeedKph) then
                        draft.ceiling.topSpeedKph = top
                        draft.trace[#draft.trace + 1] =
                            { carrier = "ceiling", layer = "chrome", id = "topSpeedKph", to = top, by = name }
                    end
                    local acc = tonumber(c.accelerationScale)
                    if acc and (not draft.ceiling.accelerationScale or acc < draft.ceiling.accelerationScale) then
                        draft.ceiling.accelerationScale = acc
                        draft.trace[#draft.trace + 1] =
                            { carrier = "ceiling", layer = "chrome", id = "accelerationScale", to = acc, by = name }
                    end
                end
            end
        end
        return nil
    end

    --- The ruleset is a LIMIT, not another multiplier. It is applied last and it only ever narrows.
    local function applyRuleset(draft, ruleset)
        if type(ruleset) ~= "table" then return nil end

        if type(ruleset.forbidFlats) == "table" then
            for _, flatId in ipairs(ruleset.forbidFlats) do
                if draft._mult[flatId] then
                    draft._mult[flatId] = nil
                    draft.trace[#draft.trace + 1] =
                        { carrier = "record", layer = "ruleset", id = flatId, to = 1.0, by = "forbidden" }
                end
            end
        end

        local c = ruleset.ceiling
        if type(c) == "table" then
            local top = tonumber(c.topSpeedKph)
            if top and (not draft.ceiling.topSpeedKph or top < draft.ceiling.topSpeedKph) then
                draft.ceiling.topSpeedKph = top
                draft.trace[#draft.trace + 1] =
                    { carrier = "ceiling", layer = "ruleset", id = "topSpeedKph", to = top, by = "class" }
            end
            local acc = tonumber(c.accelerationScale)
            if acc and (not draft.ceiling.accelerationScale or acc < draft.ceiling.accelerationScale) then
                draft.ceiling.accelerationScale = acc
                draft.trace[#draft.trace + 1] =
                    { carrier = "ceiling", layer = "ruleset", id = "accelerationScale", to = acc, by = "class" }
            end
            local taper = tonumber(c.taperKph)
            if taper then draft.ceiling.taperKph = taper end
        end
        return nil
    end

    ---------------------------------------------------------------------------------------------------
    -- Public
    ---------------------------------------------------------------------------------------------------

    --- Compose one projection.
    ---
    --- inputs = {
    ---   record  = "Vehicle.v_standard2_archer_hella",   -- required; the drive-model owner
    ---   parts   = { { id = "brake_kit_mk2", family = "brakes", effects = { brake_power = 1.15 } }, ... },
    ---   wear    = { [flatId] = multiplier },            -- applied like parts, but unattributed
    ---   weather = { wetness = 0..1 },
    ---   chrome  = { { id = "limiter", carrier = "ceiling", ceiling = { accelerationScale = 0.7 } }, ... },
    ---   ruleset = { ceiling = {...}, forbidFlats = { "engine_torque" } },
    --- }
    ---
    --- Returns `envelope, err`. On refusal the envelope is nil and the reason names itself.
    function M.compose(inputs, opts)
        inputs = inputs or {}
        opts = opts or {}

        local recordPath = inputs.record
        if type(recordPath) ~= "string" or recordPath == "" then return nil, "no_record" end

        local draft = newDraft(recordPath, opts.at)

        local err = applyEffects(draft, "factory", inputs.factory, "factory", nil)
        if err then return nil, err end

        err = applyParts(draft, inputs.parts)
        if err then return nil, err end

        err = applyEffects(draft, "wear", inputs.wear, "wear", nil)
        if err then return nil, err end

        err = applyWeather(draft, inputs.weather)
        if err then return nil, err end

        err = applyChrome(draft, inputs.chrome)
        if err then return nil, err end

        err = applyRuleset(draft, inputs.ruleset)
        if err then return nil, err end

        -- Freeze the running multipliers into the wire form the carrier applies.
        for flatId, multiplier in pairs(draft._mult) do
            if multiplier ~= 1.0 then
                local flat = Flats.get(flatId)
                draft.record.flats[#draft.record.flats + 1] = {
                    id = flatId, suffix = flat.suffix, mode = Flats.MULTIPLY, multiplier = multiplier,
                }
            end
        end

        -- The platform's hard rule, enforced after every layer rather than trusted to each of them.
        local acc = draft.ceiling.accelerationScale
        if acc and acc > M.MAX_ACCELERATION_SCALE then
            draft.ceiling.accelerationScale = M.MAX_ACCELERATION_SCALE
        end
        local taper = draft.ceiling.taperKph
        if taper and taper < M.MIN_TAPER_KPH then draft.ceiling.taperKph = M.MIN_TAPER_KPH end

        draft._mult, draft._claimed = nil, nil
        return draft, nil
    end

    --- An envelope that asks the carrier to put everything back. Distinct from an empty projection: "restore
    --- what you captured" and "apply nothing" are different instructions to something holding originals.
    function M.clear(recordPath, opts)
        opts = opts or {}
        return {
            v = M.ENVELOPE_VERSION, at = opts.at,
            record = { path = recordPath, flats = {}, restore = true },
            ceiling = {}, trace = {},
        }
    end

    --- Does this envelope actually ask for anything? Used to avoid waking the carrier for nothing.
    function M.isEmpty(envelope)
        if type(envelope) ~= "table" then return true end
        if envelope.record and envelope.record.restore then return false end
        local flats = envelope.record and envelope.record.flats
        if flats and #flats > 0 then return false end
        return next(envelope.ceiling or {}) == nil
    end

    --- Human-readable account of why a car is the way it is. The trace is the product, not a debug aid:
    --- a driver who cannot see why their car is slower has been given a bug, not a feature.
    function M.explain(envelope)
        local lines = {}
        for _, t in ipairs((envelope or {}).trace or {}) do
            lines[#lines + 1] = ("%s/%s %s -> %s (%s)"):format(
                t.carrier, t.layer, t.id, tostring(t.to), tostring(t.by))
        end
        return lines
    end

    return M
end)
