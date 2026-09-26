-- ncm-core module: machine.expression
--
-- **One mechanical fact, one carrier. Asserted statically, at load, across every composer.**
--
-- `machine.projection` has said since it shipped that *"the same mechanical fact may not be expressed
-- twice. A contribution declares its carrier and is refused if it tries both."* It enforces that with
-- `claim()`, and `claim()` is not enough -- not because it is wrong, but because of where it lives:
--
--   * **It is PER-DRAFT.** `draft._claimed` is created by `newDraft()` inside `projection.compose`.
--     `parts.handling.compose` is a different function, in a different module, called from a different
--     file, at a different cadence. The two never share a draft, so neither guard can see the other.
--   * **Weather never claims at all.** `applyWeather` calls `contribute()` in a loop and skips `claim()`,
--     so the one layer whose carrier is about to move was never being watched.
--
-- ---------------------------------------------------------------------------------------------------
-- THE COLLISION THIS EXISTS TO PREVENT, WHICH IS ALREADY SCHEDULED
-- ---------------------------------------------------------------------------------------------------
--
-- `KB-145` found that seven of the twenty-one drive-model flats do not resolve on this build. Two of them
-- are `machine.projection`'s two LARGEST weather effects:
--
--   `M.WET.lateral_grip`   0.18  -> `.frictionMulLateral`   DEAD
--   `M.WET.brake_friction` 0.15  -> `.brakingFriction`      DEAD
--
-- So more than half of wet weather is a silent no-op today, which is independent justification for moving
-- wet grip to the instance channel where it demonstrably works. **But `IDEA-508` exists specifically to
-- make those two flats resolve again.** The day it lands, wet grip and wet braking would be applied twice
-- -- once on record, once on instance -- and nothing in the codebase would catch it, because the two
-- applications happen in different modules on different drafts.
--
-- A static table catches that in the test suite instead of on a live drive, years before it fires. That is
-- the entire justification for this module: it is cheap, it is boring, and it is checkable in CI.
local Core = NcmCore

Core.define("machine.expression", function(C)
    local M = { version = "0.1.0" }

    -- ---------------------------------------------------------------------------------------------
    -- The carriers
    -- ---------------------------------------------------------------------------------------------
    --
    -- Named here rather than in `parts.ontology` because ontology describes CHANNELS -- what a family can
    -- be felt through -- while this describes CARRIERS, the code path that actually writes a value. They
    -- correspond closely and are not the same list: `ceiling` is a carrier with no ontology channel of its
    -- own, because it expresses a limit rather than a quantity.
    M.CARRIERS = {
        record = {
            id = "record",
            note = "TweakDB drive-model flats via machine.flats and effects/tweak.cpp. Spawn-cached, "
                .. "keyed by record, shared by every instance of that model on a client.",
        },
        instance = {
            id = "instance",
            note = "The live per-instance force write proved in MASTER_TEST AU/AW. Live, reversible, "
                .. "per-player, three quantities wide.",
        },
        ceiling = {
            id = "ceiling",
            note = "The platform's own governor: setPerformance/setPerformanceClass "
                .. "{topSpeedKph, accelerationScale, taperKph}. Only ever withholds.",
        },
        simulated = {
            id = "simulated",
            note = "Server-authoritative modelling. Always available, never felt through the wheel.",
        },
    }

    -- ---------------------------------------------------------------------------------------------
    -- The facts
    -- ---------------------------------------------------------------------------------------------
    --
    -- A FACT is a mechanical property of a car that a player could feel. It is deliberately coarser than a
    -- flat and coarser than a lever: `grip_magnitude` is one fact whether it is delivered by
    -- `.frictionMulLateral` on the record or by `gripScale` on the instance channel, and that is precisely
    -- what makes the one-carrier rule meaningful.
    --
    -- `moved` records a fact that changed carriers, with the reason. A migration nobody wrote down is how
    -- the old carrier quietly comes back.
    M.FACTS = {
        grip_magnitude = {
            carrier = "instance",
            note = "How much lateral force the contact patch can carry.",
            moved = "was record/.frictionMulLateral until 2026-09-26; that flat is one of KB-145's seven "
                .. "dead entries, so the record expression was a silent no-op. L158 moved it.",
        },
        brake_magnitude = {
            carrier = "instance",
            note = "How much retarding force is available along travel.",
            moved = "was record/.brakingFriction until 2026-09-26; also one of KB-145's seven.",
        },
        drive_magnitude = {
            carrier = "instance",
            note = "How much driving force is available along travel.",
            moved = "the three record power flats (.accelerationBoost, .maxWheelTorque, .engineMaxTorque) "
                .. "are ALL among KB-145's seven, so the record channel cannot express power at all today.",
        },
        slip_progression = {
            carrier = "record",
            note = "How progressively the tyre lets go -- the SHAPE of the slip curve, not its height. "
                .. "The instance channel writes a scalar and provably cannot express a curve.",
        },
        turn_friction = {
            carrier = "record",
            note = "Slope turn friction. Record-only for the same reason as slip_progression.",
        },
        aerodynamic_drag = {
            carrier = "instance",
            note = "Air resistance. The record flat `.airResistanceFactor` IS alive and is deliberately "
                .. "not used: drag arrives at the instance write site as its own entries, so expressing it "
                .. "there is live and per-Machine rather than spawn-cached and per-record.",
        },
        top_speed_cap = {
            carrier = "ceiling",
            note = "An absolute km/h ceiling. A governor: it withholds and never adds.",
        },
        acceleration_cap = {
            carrier = "ceiling",
            note = "Throttle authority, (0, 1]. NCM does not currently write this.",
        },
        tyre_thermal = {
            carrier = "instance",
            note = "Tyre temperature's effect on grip and braking. Whole-car; per-corner is refused by "
                .. "parts.ontology and by MASTER_TEST AV2.",
        },
        mass = {
            carrier = "record",
            note = "`.total_mass`. Alive on this build and not yet written by anything.",
        },
        steering_geometry = {
            carrier = "record",
            note = "Rack and lock. The instance channel refuses steering entirely (KB-135).",
        },
    }

    -- ---------------------------------------------------------------------------------------------
    -- Load-time integrity
    -- ---------------------------------------------------------------------------------------------

    for fact, entry in pairs(M.FACTS) do
        assert(type(entry) == "table", "fact '" .. fact .. "' must be a table")
        assert(M.CARRIERS[entry.carrier],
            "fact '" .. fact .. "' names unknown carrier " .. tostring(entry.carrier))
        assert(type(entry.note) == "string" and #entry.note > 10,
            "fact '" .. fact .. "' must say what it is")
    end

    --- Which carrier owns this fact? `nil, reason` for an unregistered one -- a typo and a real fact are
    --- different answers, exactly as `parts.handling.expressionFor` distinguishes them.
    function M.carrierFor(fact)
        if type(fact) ~= "string" then return nil, "fact must be a string" end
        local entry = M.FACTS[fact]
        if not entry then return nil, "unregistered mechanical fact: " .. fact end
        return entry.carrier
    end

    --- May `carrier` express `fact`? Returns `true`, or `false, reason`.
    ---
    --- **This is the call a composer makes.** It is deliberately not a silent boolean: a refusal names the
    --- carrier that does own the fact, because the useful question after "no" is always "then who".
    function M.mayExpress(fact, carrier)
        local owner, why = M.carrierFor(fact)
        if not owner then return false, why end
        if owner == carrier then return true end
        return false, ("'%s' is expressed on the %s carrier, not %s"):format(fact, owner, tostring(carrier))
    end

    --- Assert at load that a composer's declared facts are all its own. Called by `machine.projection` and
    --- `parts.handling` with their own carrier id, so a mistake fails the build rather than a drive.
    function M.assertOwns(carrier, facts, who)
        for _, fact in ipairs(facts) do
            local ok, why = M.mayExpress(fact, carrier)
            assert(ok, (who or carrier) .. ": " .. tostring(why))
        end
        return true
    end

    --- Every fact a carrier owns, sorted. For a panel, a test, or an operator asking what moved where.
    function M.factsFor(carrier)
        local out = {}
        for fact, entry in pairs(M.FACTS) do
            if entry.carrier == carrier then out[#out + 1] = fact end
        end
        table.sort(out)
        return out
    end

    --- Facts that have changed carrier, with the reason. Reading this is how the next person understands
    --- why the record channel stopped expressing grip without having to bisect the history.
    function M.migrations()
        local out = {}
        for fact, entry in pairs(M.FACTS) do
            if entry.moved then
                out[#out + 1] = { fact = fact, carrier = entry.carrier, why = entry.moved }
            end
        end
        table.sort(out, function(a, b) return a.fact < b.fact end)
        return out
    end

    return M
end)
