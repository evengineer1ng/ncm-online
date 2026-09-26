-- parts.ontology -- the component periodic table and the four expression channels.
--
-- These test the RULES, not the content. Subfamily names are a first pass and are expected to change; what
-- must not change is that the twelve families have exactly one authority, that a family cannot claim a
-- channel it does not have, and that "you cannot feel this" is answerable rather than silently absent.
--
-- The failure being guarded against is specific and has already happened once: MASTER_TEST section AV2 spent
-- three drives writing a per-corner channel that turned out not to exist. `declarationIsHonest` is that
-- lesson as an assertion.
local function O(T) return T.Core.get("parts.ontology") end
local function F(T) return T.Core.get("machine.flats") end
local function E(T) return T.Core.get("engineering.competency") end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

return {
    -- ------------------------------------------------------------------ one authority for the twelve
    the_families_are_competencys_and_not_a_second_list = function(T)
        local M, C = O(T), E(T)
        T.eq(M.FAMILIES, C.FAMILIES, "parts.ontology reuses the canonical family list, it does not copy it")
        T.eq(#M.FAMILIES, 12, "twelve families")
    end,

    every_family_has_a_periodic_table_entry = function(T)
        local M = O(T)
        for _, family in ipairs(M.FAMILIES) do
            local entry = M.family(family)
            T.eq(type(entry) == "table", true, family .. " has an entry")
            T.eq(type(entry.meaning) == "string" and #entry.meaning > 0, true, family .. " means something")
            T.eq(type(entry.abstracts) == "table", true, family .. " says what it abstracts away")
            T.eq(#entry.subfamilies > 0, true, family .. " has at least one subfamily")
        end
    end,

    subfamilies_are_queryable_and_refuse_nonsense = function(T)
        local M = O(T)
        T.eq(M.isSubfamily("brakes", "friction_material"), true, "a real subfamily is recognised")
        T.eq(M.isSubfamily("brakes", "turbocharger"), false, "a subfamily from another family is refused")
        T.eq(M.isSubfamily("not_a_family", "anything"), false, "an unknown family is refused, not an error")
        T.eq(M.subfamilies("not_a_family"), nil, "")
    end,

    -- ------------------------------------------------------------------ chassis is the compatibility root
    chassis_is_the_root_and_nothing_else_is = function(T)
        local M = O(T)
        T.eq(M.isCompatibilityRoot("chassis"), true, "chassis roots the compatibility tree")
        for _, family in ipairs(M.FAMILIES) do
            if family ~= "chassis" then
                T.eq(M.isCompatibilityRoot(family), false, family .. " is not the root")
            end
        end
    end,

    -- ------------------------------------------------------------------ serialisation unit (spec conflict 5)
    tyres_serialise_as_a_set_and_everything_else_individually = function(T)
        local M = O(T)
        T.eq(M.serialisationUnit("tires"), M.UNIT.SET, "a tyre asset is a set of four")
        T.eq(M.serialisationUnit("brakes"), M.UNIT.COMPONENT, "a brake component is itself")
        T.eq(M.serialisationUnit("power_unit"), M.UNIT.COMPONENT, "")
        T.eq(M.serialisationUnit("not_a_family"), nil, "an unknown family has no unit")
    end,

    -- ------------------------------------------------------------------ the channels
    the_per_corner_channel_is_declared_absent_rather_than_omitted = function(T)
        local M = O(T)
        -- The whole point of naming it: a designer meets the limit here instead of discovering it after
        -- building an anti-roll bar. Section AV2 refuted the force route; IDEA-503 is the only survivor.
        T.eq(M.CHANNELS.per_corner ~= nil, true, "the channel is named")
        T.eq(M.CHANNELS.per_corner.exists, false, "and honestly marked as not existing")
        T.eq(M.CHANNELS.record.exists, true, "the record channel ships")
        T.eq(M.CHANNELS.instance.exists, true, "so does the live one")
    end,

    the_two_felt_channels_have_opposite_strengths = function(T)
        local M = O(T)
        -- This is the fact Parts has to design around, so it is asserted rather than left in a comment.
        T.eq(M.CHANNELS.record.live, false, "the broad channel is spawn-cached")
        T.eq(M.CHANNELS.record.perPlayer, false, "and shared across instances of a model")
        T.eq(M.CHANNELS.instance.live, true, "the personal channel is live")
        T.eq(M.CHANNELS.instance.perPlayer, true, "and per-player")
    end,

    simulated_is_never_felt_but_always_available = function(T)
        local M = O(T)
        T.eq(M.CHANNELS.simulated.exists, true, "")
        T.eq(M.CHANNELS.simulated.felt, false, "simulation is not a feeling through the car")
        for _, family in ipairs(M.FAMILIES) do
            T.eq(contains(M.expression(family).channels, "simulated"), true,
                 family .. " can always be modelled even when it cannot be felt")
        end
    end,

    -- ------------------------------------------------------------------ expression
    expression_agrees_with_flats_rather_than_restating_it = function(T)
        local M, flats = O(T), F(T)
        for _, family in ipairs(M.FAMILIES) do
            local expression = M.expression(family)
            local hasRecord = contains(expression.channels, "record")
            T.eq(hasRecord, flats.familyIsExpressible(family),
                 family .. " agrees with machine.flats about the record channel")
            if hasRecord then
                T.eq(#expression.flats, #(flats.BY_FAMILY[family] or {}),
                     family .. " reports exactly the flats it has")
            else
                T.eq(#expression.flats, 0, family .. " reports no flats")
            end
        end
    end,

    a_family_with_no_drive_model_flat_may_still_be_felt_live = function(T)
        local M, flats = O(T), F(T)
        -- **The point of this test inverted under `L154` and the old name was the giveaway.** It used to
        -- assert that the four families with no drive-model flat "cannot be felt". That was a statement
        -- about the RECORD channel being read as a statement about feel, and it stopped being true when
        -- the instance channel learned to approximate.
        --
        -- What is still true, and worth pinning: having no flat means no RECORD expression, which is a
        -- finding about `machine.flats` rather than a verdict on the family.
        for _, family in ipairs(flats.UNEXPRESSED_FAMILIES) do
            local expression = M.expression(family)
            T.eq(contains(expression.channels, "record"), false,
                 family .. " has no drive-model flat, so no record channel")
            if M.INSTANCE_QUANTITIES[family] then
                T.eq(expression.felt, true, family .. " is still felt, live and per-player")
                T.eq(expression.perPlayerFelt, true, "")
            else
                T.eq(expression.felt, false, family .. " genuinely cannot be felt at all")
                T.eq(expression.channels[1], "simulated", "")
            end
        end
    end,

    eleven_families_are_felt_live_and_per_player = function(T)
        local M = O(T)
        -- **This assertion has now been widened TWICE in one day, and the pattern is the lesson.** It
        -- first read "tyres are the ONE family felt live" (true the day AU5 passed). Sections AW1 and AW2
        -- made it three. `L154` then made it eleven, by allowing a family to be expressed APPROXIMATELY
        -- onto a lever it does not literally own -- a suspension part raising usable grip is a coarse
        -- model of a real effect, not a fabrication.
        --
        -- Both times the table was too NARROW, and both times the cause was a rule rather than a fact.
        -- The gate caught both stale versions, which is what the gate is for.
        local n = 0
        for family in pairs(M.INSTANCE_QUANTITIES) do
            n = n + 1
            local e = M.expression(family)
            T.eq(contains(e.channels, "instance"), true, family .. " has a live quantity")
            T.eq(e.perPlayerFelt, true, family .. " can differ between two drivers of the same model")
            T.ok(M.INSTANCE_FIDELITY[family], family .. " declares whether it is direct or approximated")
        end
        T.eq(n, 11, "eleven of twelve families reach the live channel")

        -- Steering is the one that does not, and it is refused for a MECHANISM rather than for
        -- squeamishness: response is not force magnitude, and the only honest expression would be input
        -- authority, which KB-135 reserves to the driver.
        T.eq(M.INSTANCE_QUANTITIES.steering, nil, "steering has no live quantity")
        T.eq(M.INSTANCE_REFUSED.steering, true, "and it is recorded as refused, not merely absent")
        T.eq(contains(M.expression("steering").channels, "instance"), false, "")
    end,

    unknown_families_return_nil_rather_than_guessing = function(T)
        local M = O(T)
        T.eq(M.expression("radiator"), nil, "")
        T.eq(M.family("radiator"), nil, "")
        T.eq(M.isFamily("radiator"), false, "")
        T.eq(M.isFamily("cooling"), true, "cooling is a family even though it cannot be felt")
    end,

    -- ------------------------------------------------------------------ IDEA-505, as an assertion
    a_part_may_not_declare_a_channel_that_does_not_exist = function(T)
        local M = O(T)
        local ok, why = M.declarationIsHonest("suspension", "per_corner")
        T.eq(ok, false, "an anti-roll bar cannot promise per-corner expression")
        T.eq(type(why) == "string" and why:find("IDEA-503", 1, true) ~= nil, true,
             "and the refusal says where the bookmark is")
    end,

    a_part_may_not_declare_a_channel_its_family_does_not_have = function(T)
        local M = O(T)
        local ok, why = M.declarationIsHonest("cooling", "record")
        T.eq(ok, false, "cooling has no drive-model flat, so it cannot claim the record channel")
        T.eq(type(why) == "string", true, why or "")

        -- Was `brakes` (AW2 made it reachable), then `suspension` (`L154` made it reachable too, as an
        -- approximation). `steering` is the durable example and the only one: it is refused for a
        -- mechanism -- response is not force magnitude, and input authority is the driver's (`KB-135`) --
        -- rather than for want of a proven lever, so it will not quietly become true the way the other
        -- two did.
        local ok2 = M.declarationIsHonest("steering", "instance")
        T.eq(ok2, false, "steering cannot be expressed live at all")
    end,

    honest_declarations_pass = function(T)
        local M = O(T)
        T.eq(M.declarationIsHonest("brakes", "record"), true, "brakes have flats")
        T.eq(M.declarationIsHonest("tires", "instance"), true, "tyres have the live grip write")
        T.eq(M.declarationIsHonest("power_unit", "instance"), true, "and power_unit has driveScale (AW1)")
        T.eq(M.declarationIsHonest("brakes", "instance"), true, "and brakes have brakeScale (AW2)")
        -- An APPROXIMATED expression is an honest declaration. That is the whole of `L154`: the dishonesty
        -- was never coarseness, it was claiming a mechanism you do not have, and `parts.handling.EXPRESSION`
        -- keeps that line by enumerating each family's losses.
        T.eq(M.declarationIsHonest("suspension", "instance"), true,
             "suspension reaches grip approximately, and approximately is allowed")
        T.eq(M.declarationIsHonest("aerodynamics", "instance"), true, "as does a wing, both ways")
        T.eq(M.declarationIsHonest("cooling", "simulated"), true,
             "and anything at all may be simulated -- that is the always-available answer")
    end,

    declaration_refuses_unknown_inputs = function(T)
        local M = O(T)
        T.eq(M.declarationIsHonest("radiator", "record"), false, "")
        T.eq(M.declarationIsHonest("brakes", "telepathy"), false, "")
    end,

    -- ------------------------------------------------------------------ the designer's diagnostic
    every_family_can_now_be_felt_somehow_and_that_is_new = function(T)
        local M, flats = O(T), F(T)
        local inventory = M.inventory()
        T.eq(#inventory.felt + #inventory.modelledOnly, 12, "every family lands on one side")

        -- **Was four modelled-only; `L154` left none, and the arithmetic is worth spelling out because
        -- the result is stronger than anyone set out to achieve.** Four families have no drive-model flat
        -- at all -- cooling, transmission, electrical, chassis -- and that used to mean they could not be
        -- felt. Every one of them now reaches `driveScale` through an approximation. Steering, which
        -- cannot reach the instance channel, turns out to HAVE a flat.
        --
        -- So the two channels cover the periodic table between them, from opposite ends, with no overlap
        -- in the gaps. Nobody planned that; it is worth an assertion precisely because it is a coincidence
        -- of two independent tables and would break silently.
        T.eq(#inventory.modelledOnly, 0, "no family is stuck at simulation-only any more")

        for _, family in ipairs(flats.UNEXPRESSED_FAMILIES) do
            T.eq(M.INSTANCE_QUANTITIES[family] ~= nil, true,
                 family .. " has no flat, so the instance channel is the only thing that can carry it")
            T.eq(M.expression(family).perPlayerFelt, true, family .. " is felt live and per-player")
        end

        -- The converse, and the reason "felt" is not the same as "felt per-player": steering is reachable
        -- only through the record channel, so it is shared by every instance of that model on a client and
        -- two drivers cannot differ through it.
        local steering = M.expression("steering")
        T.eq(steering.felt, true, "steering has a drive-model flat")
        T.eq(steering.perPlayerFelt, false, "but it is record-only, so it cannot be personal")
        T.eq(contains(inventory.felt, "tires"), true, "")
    end,
}
