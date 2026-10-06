-- ncm-core module: machine.flats
--
-- The flat vocabulary: every drive-model field NCM is prepared to write, what it means, which mechanical
-- family owns it, and how far it may move. **This is data, not code.** The carrier plugin receives
-- `{record, suffix, value}` triples and applies them; it never learns what a brake pad is.
--
-- PROVENANCE. Two grades, and the difference matters when something misbehaves:
--
--   * `ncm_sp`     -- NCM's own single-player mod writes this flat today and has for months
--                     (`ncm-localized/.../MT_Ecosystem/modules/tuning.lua`). Proven writable, by us.
--   * `documented` -- named in the `vehDriveModelData` record schema (Report 36 section 3.3) but NCM has
--                     never written it. Inventory, not experience. Expect surprises.
--
-- HONESTY ABOUT LABELS. The single-player mod's slider labels were chosen for a tuning menu, not for a
-- simulation, and two of them are loose: `.accelerationInAir` is air control and was labelled "Throttle
-- Response", and `.driveModelData_sharedFwd` does not resolve as a numeric flat on 2.31 in our own reading.
-- Neither is carried here. Report 34 section 8's rule -- do not present a field as something it is not --
-- applies to what NCM inherits from itself as much as to what it borrows.
--
-- FOUR FAMILIES HAVE NO ENTRY HERE, and that is a finding rather than an omission: **cooling, transmission,
-- electrical and chassis have no drive-model flat**. A part in those families cannot be felt through this
-- carrier. It can still be real -- owned, fitted, worn, required for eligibility -- but if its whole design
-- depends on being felt, it needs a different carrier or it needs to wait.
local Core = NcmCore

Core.define("machine.flats", function(C)
    local M = { version = "0.0.1" }

    -- Applied against the value captured before NCM's first write, never against whatever is there now.
    -- Re-applying a multiplier to an already-multiplied value is how tuning mods drift to zero.
    M.MULTIPLY = "multiply"

    --- id       stable NCM name; what the projection and the trace speak in
    --- suffix   the TweakDB flat on the drive-model record
    --- family   one of engineering.competency's twelve; ties a part to a felt consequence
    --- min/max  bounds on the MULTIPLIER, not on the field. The clamp is data.
    --- grade    "ncm_sp" | "documented" (see above)
    --- note     what the field actually does, in plain words
    M.FLATS = {
        -- ---------------------------------------------------------------- power_unit
        { id = "power",            suffix = ".accelerationBoost",          family = "power_unit",
          min = 0.50, max = 2.50, grade = "ncm_sp",
          note = "Acceleration multiplier. The engine's headline number." },
        { id = "wheel_torque",     suffix = ".maxWheelTorque",             family = "power_unit",
          min = 0.50, max = 2.00, grade = "ncm_sp",
          note = "Peak torque delivered at the wheel." },
        { id = "engine_torque",    suffix = ".engineMaxTorque",            family = "power_unit",
          min = 0.50, max = 2.00, grade = "documented",
          note = "Engine torque at source. Has NO `accelerationScale <= 1` ceiling -- unlike the platform "
              .. "API, this can add power as well as withhold it (IDEA-463)." },

        -- ---------------------------------------------------------------- drivetrain
        { id = "engine_braking",   suffix = ".engineBrakingFactor",        family = "drivetrain",
          min = 0.00, max = 3.00, grade = "ncm_sp",
          note = "Deceleration off-throttle." },
        { id = "burnout",          suffix = ".burnOutRotationModifier",    family = "drivetrain",
          min = 0.00, max = 3.00, grade = "ncm_sp",
          note = "How readily the driven wheels break traction under power." },

        -- ---------------------------------------------------------------- brakes
        { id = "brake_power",      suffix = ".lowVelStoppingDeceleration", family = "brakes",
          min = 0.30, max = 3.00, grade = "ncm_sp",
          note = "Stopping deceleration at low speed." },
        { id = "brake_friction",   suffix = ".brakingFriction",            family = "brakes",
          min = 0.30, max = 2.00, grade = "ncm_sp",
          note = "Braking friction coefficient." },
        { id = "handbrake",        suffix = ".handbrakeBrakingTorque",     family = "brakes",
          min = 0.30, max = 2.00, grade = "ncm_sp",
          note = "Handbrake torque." },

        -- ---------------------------------------------------------------- tires
        { id = "lateral_grip",     suffix = ".frictionMulLateral",         family = "tires",
          min = 0.50, max = 1.50, grade = "documented",
          note = "Lateral tyre friction. **The grip field.** Report 33 section 6.4 called this BLOCKED; that "
              .. "was true of the platform API and false of the engine (IDEA-463)." },
        { id = "slip_curve",       suffix = ".slipAngleCurveScale",        family = "tires",
          min = 0.50, max = 1.50, grade = "documented",
          note = "Scales the slip-angle curve -- how progressively the tyre lets go." },
        { id = "turn_friction",    suffix = ".slopeTurnFriction",          family = "tires",
          min = 0.00, max = 2.00, grade = "ncm_sp",
          note = "Cornering friction against slope." },
        { id = "slope_comp",       suffix = ".slopeCompensationFactor",    family = "tires",
          min = 0.00, max = 2.00, grade = "ncm_sp",
          note = "Compensation for gradient under power." },

        -- ---------------------------------------------------------------- suspension
        { id = "damping_low",      suffix = ".lateralDampingZeroSpeed",    family = "suspension",
          min = 0.30, max = 2.00, grade = "ncm_sp",
          note = "Lateral damping at rest. Reads as understeer." },
        { id = "damping_high",     suffix = ".lateralDampingFullSpeed",    family = "suspension",
          min = 0.30, max = 2.00, grade = "ncm_sp",
          note = "Lateral damping at speed. Reads as oversteer." },
        { id = "roll",             suffix = ".turningRollFactor",          family = "suspension",
          min = 0.30, max = 2.00, grade = "ncm_sp",
          note = "Body roll through a turn." },
        { id = "spring",           suffix = ".springStiffness",            family = "suspension",
          min = 0.50, max = 1.80, grade = "documented",
          note = "Spring rate." },
        { id = "antiroll",         suffix = ".antiSwaybarDampingScalor",   family = "suspension",
          min = 0.50, max = 1.80, grade = "documented",
          note = "Anti-roll bar damping." },

        -- ---------------------------------------------------------------- steering
        { id = "steer_lock",       suffix = ".wheelTurningMax",            family = "steering",
          min = 0.60, max = 1.40, grade = "ncm_sp",
          note = "Maximum wheel deflection." },
        { id = "steer_add",        suffix = ".turningMaxAdd",              family = "steering",
          min = 0.60, max = 1.40, grade = "ncm_sp",
          note = "Additional turn authority at speed." },

        -- ---------------------------------------------------------------- aerodynamics
        { id = "drag",             suffix = ".airResistanceFactor",        family = "aerodynamics",
          min = 0.50, max = 2.00, grade = "ncm_sp",
          note = "Air resistance." },

        -- ---------------------------------------------------------------- structure
        { id = "mass",             suffix = ".total_mass",                 family = "structure",
          min = 0.70, max = 1.40, grade = "documented",
          note = "Total mass. Touches everything else, so it moves last and least." },
    }

    -- Families that exist in the parts ontology but have no drive-model expression. Named explicitly so a
    -- designer meets the limit here rather than discovering it after building a component tree on it.
    M.UNEXPRESSED_FAMILIES = { "cooling", "transmission", "electrical", "chassis" }

    M.BY_ID = {}
    for _, f in ipairs(M.FLATS) do M.BY_ID[f.id] = f end

    M.BY_FAMILY = {}
    for _, f in ipairs(M.FLATS) do
        local list = M.BY_FAMILY[f.family]
        if not list then list = {}; M.BY_FAMILY[f.family] = list end
        list[#list + 1] = f.id
    end

    local UNEXPRESSED = {}
    for _, name in ipairs(M.UNEXPRESSED_FAMILIES) do UNEXPRESSED[name] = true end

    function M.get(id) return M.BY_ID[id] end
    function M.isKnown(id) return M.BY_ID[id] ~= nil end

    --- Can a part in this family ever be FELT through this carrier? Answering honestly is the whole point
    --- of `UNEXPRESSED_FAMILIES`; a caller that asks gets told before it designs around a wrong assumption.
    function M.familyIsExpressible(family)
        if UNEXPRESSED[family] then return false end
        return (M.BY_FAMILY[family] ~= nil)
    end

    --- Bound a multiplier to the flat's declared range. Nonsense -- nil, NaN, infinity, a string -- collapses
    --- to 1.0, the identity, because a flat NCM cannot reason about must be left exactly as the game had it.
    function M.clampMultiplier(id, value)
        local flat = M.BY_ID[id]
        if not flat then return 1.0 end
        local v = tonumber(value)
        if not v or v ~= v or v == math.huge or v == -math.huge then return 1.0 end
        if v < flat.min then return flat.min end
        if v > flat.max then return flat.max end
        return v
    end

    --- Every flat NCM will write, lowest-risk grade first, for a diagnostic listing.
    function M.inventory()
        local proven, inventory = {}, {}
        for _, f in ipairs(M.FLATS) do
            local into = (f.grade == "ncm_sp") and proven or inventory
            into[#into + 1] = f.id
        end
        return { proven = proven, documented = inventory }
    end

    return M
end)
