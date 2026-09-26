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

    the_four_unexpressed_families_cannot_be_felt = function(T)
        local M, flats = O(T), F(T)
        for _, family in ipairs(flats.UNEXPRESSED_FAMILIES) do
            local expression = M.expression(family)
            T.eq(expression.felt, false, family .. " cannot be felt through this carrier")
            T.eq(#expression.channels, 1, family .. " has simulation and nothing else")
            T.eq(expression.channels[1], "simulated", "")
        end
    end,

    three_families_are_felt_live_and_per_player = function(T)
        local M = O(T)
        -- **This assertion was inverted on 2026-09-26 and the inversion is the point.** It used to read
        -- "tyres are the ONE family felt live", which was true of the day section AU5 passed. Sections AW1
        -- and AW2 then proved `driveScale` and `brakeScale` on Production, so power_unit and brakes joined
        -- it. The gate caught the stale version, which is what the gate is for.
        local live = { tires = true, power_unit = true, brakes = true }
        for family in pairs(live) do
            local e = M.expression(family)
            T.eq(contains(e.channels, "instance"), true, family .. " has a live quantity")
            T.eq(e.perPlayerFelt, true, family .. " can differ between two drivers of the same model")
        end
        -- Every OTHER family is record-only, so two drivers in the same car cannot differ through it. That
        -- is still the constraint most likely to be forgotten while designing a parts economy, and it is
        -- still true of nine of the twelve.
        for _, family in ipairs(M.FAMILIES) do
            if not live[family] then
                T.eq(M.expression(family).perPlayerFelt, false,
                     family .. " cannot differ between two drivers of the same model")
            end
        end
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

        -- Was `brakes`, which section AW2 made reachable. `suspension` is the durable example: anti-roll
        -- is a MOMENT, and section AW3 refuted the per-corner load entries with a mechanism rather than
        -- leaving them untested, so this one will not quietly become true later.
        local ok2 = M.declarationIsHonest("suspension", "instance")
        T.eq(ok2, false, "suspension has no live quantity -- moments need a torque channel we do not have")
    end,

    honest_declarations_pass = function(T)
        local M = O(T)
        T.eq(M.declarationIsHonest("brakes", "record"), true, "brakes have flats")
        T.eq(M.declarationIsHonest("tires", "instance"), true, "tyres have the live grip write")
        T.eq(M.declarationIsHonest("power_unit", "instance"), true, "and power_unit has driveScale (AW1)")
        T.eq(M.declarationIsHonest("brakes", "instance"), true, "and brakes have brakeScale (AW2)")
        T.eq(M.declarationIsHonest("cooling", "simulated"), true,
             "and anything at all may be simulated -- that is the always-available answer")
    end,

    declaration_refuses_unknown_inputs = function(T)
        local M = O(T)
        T.eq(M.declarationIsHonest("radiator", "record"), false, "")
        T.eq(M.declarationIsHonest("brakes", "telepathy"), false, "")
    end,

    -- ------------------------------------------------------------------ the designer's diagnostic
    inventory_splits_the_twelve_honestly = function(T)
        local M = O(T)
        local inventory = M.inventory()
        T.eq(#inventory.felt + #inventory.modelledOnly, 12, "every family lands on one side")
        T.eq(#inventory.modelledOnly, 4, "four families are modelled-only, which is a finding not a gap")
        T.eq(contains(inventory.modelledOnly, "cooling"), true, "")
        T.eq(contains(inventory.felt, "tires"), true, "")
    end,
}
