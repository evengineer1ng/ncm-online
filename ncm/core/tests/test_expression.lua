-- machine.expression -- one mechanical fact, one carrier.
--
-- This suite exists because of a hazard that is already scheduled rather than hypothetical. `KB-145` found
-- that `machine.projection`'s two largest weather effects write to flats that do not resolve on this build,
-- so most of wet weather is a silent no-op; `IDEA-508` exists to make exactly those flats resolve again.
-- On the day it lands, wet grip would be applied on both carriers at once, and `claim()` could not catch it
-- because it is per-draft and the two composers never share a draft.
--
-- So the property under test is not "does the table parse". It is: **can two carriers ever claim the same
-- mechanical fact, and does a composer that tries get a refusal naming the owner.**
local function X(T) return T.Core.get("machine.expression") end

return {
    every_fact_has_exactly_one_carrier = function(T)
        local M = X(T)
        local n = 0
        for fact, entry in pairs(M.FACTS) do
            n = n + 1
            T.ok(M.CARRIERS[entry.carrier], fact .. " names a real carrier")
            -- The whole point: the table is a map, so a second carrier for the same fact is not
            -- expressible. This asserts the shape that makes it unexpressible rather than a value.
            T.eq(type(entry.carrier), "string", fact .. " has a single scalar carrier, not a list")
        end
        T.ok(n >= 8, "the registry covers the facts both composers actually write")
    end,

    a_refusal_names_the_carrier_that_does_own_the_fact = function(T)
        local M = X(T)
        -- "No" is not a useful answer on its own; the next question is always "then who".
        local ok, why = M.mayExpress("grip_magnitude", "record")
        T.eq(ok, false, "the record carrier may not express grip magnitude any more")
        T.match(why, "instance", "and the refusal says who does")

        T.eq(M.mayExpress("grip_magnitude", "instance"), true)
        T.eq(M.mayExpress("slip_progression", "record"), true, "curve shape stays on the record")

        local ok2, why2 = M.mayExpress("slip_progression", "instance")
        T.eq(ok2, false, "a scalar cannot express a curve, and the registry says so")
        T.match(why2, "record")
    end,

    a_typo_and_a_real_fact_are_different_answers = function(T)
        local M = X(T)
        local carrier, why = M.carrierFor("grip_magnitdue")
        T.eq(carrier, nil)
        T.match(why, "unregistered", "a misspelling is not silently allowed through")
        T.eq(M.carrierFor("grip_magnitude"), "instance")
    end,

    -- ------------------------------------------------------------------ the KB-145 / IDEA-508 hazard
    the_facts_weather_moved_are_recorded_with_their_reason = function(T)
        local M = X(T)
        local moved = M.migrations()
        T.ok(#moved >= 2, "grip and brake magnitude both changed carrier")
        local byFact = {}
        for _, m in ipairs(moved) do byFact[m.fact] = m end

        T.ok(byFact.grip_magnitude, "grip magnitude is recorded as a migration")
        T.match(byFact.grip_magnitude.why, "KB%-145",
            "and it cites the evidence, because a migration nobody wrote down is how the old carrier "
            .. "quietly comes back")
        T.ok(byFact.brake_magnitude, "brake magnitude too")
    end,

    the_record_carrier_can_no_longer_claim_the_dead_weather_flats = function(T)
        local M = X(T)
        -- This is the `IDEA-508` guard stated as a test. If someone re-adds `lateral_grip` to
        -- `machine.projection`'s WET table once the flat resolves again, the record composer's
        -- `assertOwns` call fails at load -- here, in CI, rather than on a live drive with two
        -- weather effects stacking invisibly.
        for _, fact in ipairs({ "grip_magnitude", "brake_magnitude" }) do
            local ok = M.mayExpress(fact, "record")
            T.eq(ok, false, fact .. " must not be expressible on the record carrier")
        end
    end,

    assert_owns_refuses_a_composer_that_reaches_outside_its_carrier = function(T)
        local M = X(T)
        T.ok(pcall(M.assertOwns, "instance", { "grip_magnitude", "brake_magnitude" }, "test"),
            "a composer staying inside its carrier loads")
        T.eq(pcall(M.assertOwns, "instance", { "top_speed_cap" }, "test"), false,
            "a composer reaching for the governor does not")
        T.eq(pcall(M.assertOwns, "record", { "grip_magnitude" }, "test"), false,
            "and neither does the record carrier reaching for grip")
    end,

    top_speed_is_a_ceiling_fact_and_never_an_instance_one = function(T)
        local M = X(T)
        -- `parts.handling` composes a top speed number but must not deliver it as force. The separation
        -- only means anything if it is checkable.
        T.eq(M.carrierFor("top_speed_cap"), "ceiling")
        T.eq(M.carrierFor("acceleration_cap"), "ceiling")
        T.eq(M.mayExpress("top_speed_cap", "instance"), false)
    end,

    every_carrier_says_what_it_is = function(T)
        local M = X(T)
        for id, carrier in pairs(M.CARRIERS) do
            T.eq(carrier.id, id, "a carrier's key and id agree")
            T.ok(#carrier.note > 20, id .. " explains its own guarantees")
        end
        -- The four the codebase actually has. A fifth would be a design change, not a typo.
        T.ok(M.CARRIERS.record and M.CARRIERS.instance and M.CARRIERS.ceiling and M.CARRIERS.simulated)
    end,

    facts_for_a_carrier_are_sorted_and_complete = function(T)
        local M = X(T)
        local instance = M.factsFor("instance")
        T.ok(#instance >= 4, "the instance carrier owns the force facts")
        for i = 2, #instance do
            T.ok(instance[i - 1] < instance[i], "sorted, so two runs produce the same list")
        end
        local seen = {}
        for _, f in ipairs(instance) do seen[f] = true end
        T.ok(seen.grip_magnitude and seen.brake_magnitude and seen.drive_magnitude)
        T.eq(seen.top_speed_cap, nil, "and not the governor's")
    end,
}
