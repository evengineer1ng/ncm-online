-- parts.handling -- the instance channel, which is the half of Parts that is per-player.
--
-- These test the RULES, not the balance. No number in this suite is a design judgement: 18_PARTS_ECOSYSTEM
-- puts component balance out of scope, so every `effect` here is chosen to exercise arithmetic or a bound.
--
-- The failures being guarded against are specific and all three have already happened in this project:
--
--   1. A family promised a felt effect on a channel that cannot carry it (section AV2, three wasted drives).
--      `leverFor` refuses by name, and `compose` refuses the whole setup rather than dropping the part.
--   2. Two tables that must agree drifting apart -- `ontology.INSTANCE_QUANTITIES` said one family for a
--      day after section AW proved three. Asserted at module load, and asserted again here.
--   3. An audit trail shipped to every client (KB-136, the state bag size limit). `wire()` must not carry
--      `trace`.
local function H(T) return T.Core.get("parts.handling") end
local function O(T) return T.Core.get("parts.ontology") end

local function near(a, b) return math.abs(a - b) < 1e-6 end

return {
    -- ------------------------------------------------------------------ the levers are evidence-backed
    every_lever_names_the_live_pass_that_authorises_it = function(T)
        local M = H(T)
        T.eq(#M.LEVER_IDS, 3, "three proven levers, no more")
        for _, id in ipairs(M.LEVER_IDS) do
            local lever = M.LEVERS[id]
            T.ok(lever, "lever " .. id .. " is declared")
            T.match(lever.evidence, "MASTER_TEST",
                id .. " cites a live MASTER_TEST section rather than a hope")
            T.ok(lever.min < lever.inert and lever.inert < lever.max,
                id .. "'s inert value sits inside its bounds")
        end
    end,

    the_lever_bounds_mirror_the_carriers_own_clamps = function(T)
        local M = H(T)
        -- These are the values in `vehicle/physics_probe.cpp`. If the plugin's clamps move, this fails,
        -- which is the point: the server must not compose a setup the carrier will silently alter.
        T.ok(near(M.LEVERS.gripScale.min, 0.30) and near(M.LEVERS.gripScale.max, 1.50), "gripScale bounds")
        T.ok(near(M.LEVERS.driveScale.min, 0.30) and near(M.LEVERS.driveScale.max, 2.00), "driveScale bounds")
        T.ok(near(M.LEVERS.brakeScale.min, 0.30) and near(M.LEVERS.brakeScale.max, 2.00), "brakeScale bounds")
    end,

    -- ------------------------------------------------------------------ agreement with the ontology
    the_ontology_and_the_levers_describe_the_same_three_families = function(T)
        local M, Ont = H(T), O(T)
        local n = 0
        for family in pairs(Ont.INSTANCE_QUANTITIES) do
            n = n + 1
            T.ok(M.LEVER_OF_FAMILY[family],
                "ontology claims '" .. family .. "' is live; handling must have a lever for it")
        end
        T.eq(n, 3, "ontology declares exactly the three proven families")
    end,

    a_family_the_instance_channel_cannot_reach_is_refused_by_name = function(T)
        local M = H(T)
        for _, family in ipairs({ "suspension", "steering", "aerodynamics", "structure" }) do
            local lever, why = M.leverFor(family)
            T.eq(lever, nil, family .. " has no live lever")
            T.match(why, "instance channel", "the refusal says which channel, not just 'no'")
        end
    end,

    an_unknown_family_is_distinguished_from_an_inexpressible_one = function(T)
        local M = H(T)
        local _, why = M.leverFor("warp_drive")
        T.match(why, "unknown family", "a typo and a real-but-inert family are different answers")
    end,

    -- ------------------------------------------------------------------ composing
    an_empty_setup_is_inert_and_every_lever_sits_at_its_no_op = function(T)
        local M = H(T)
        local setup = M.compose({ vehicle = "v1", parts = {} }, { at = 100 })
        T.ok(setup, "an empty setup composes")
        T.eq(M.isInert(setup), true, "nothing fitted changes nothing")
        for _, id in ipairs(M.LEVER_IDS) do
            T.ok(near(setup.levers[id], M.LEVERS[id].inert), id .. " is inert")
        end
        T.eq(M.explain(setup), "inert")
    end,

    one_part_moves_exactly_its_own_lever_and_no_other = function(T)
        local M = H(T)
        local setup = M.compose({ vehicle = "v1", parts = {
            { id = "eng_stage2", family = "power_unit", effect = 1.15 },
        } }, { at = 100 })
        T.ok(near(setup.levers.driveScale, 1.15), "driveScale took the effect")
        T.ok(near(setup.levers.gripScale, 1.00), "gripScale untouched")
        T.ok(near(setup.levers.brakeScale, 1.00), "brakeScale untouched")
        T.eq(M.isInert(setup), false, "a fitted engine is not inert")
    end,

    two_parts_on_one_lever_multiply_rather_than_add = function(T)
        local M = H(T)
        local setup = M.compose({ parts = {
            { id = "a", family = "power_unit", effect = 1.10 },
            { id = "b", family = "power_unit", effect = 1.10 },
        } })
        T.ok(near(setup.levers.driveScale, 1.21), "1.10 x 1.10 = 1.21, not 1.20")
    end,

    the_order_parts_arrive_in_does_not_change_the_result = function(T)
        local M = H(T)
        local forward = M.compose({ parts = {
            { id = "a", family = "power_unit", effect = 1.20 },
            { id = "b", family = "tires", effect = 1.05 },
            { id = "c", family = "power_unit", effect = 0.90 },
        } })
        local backward = M.compose({ parts = {
            { id = "c", family = "power_unit", effect = 0.90 },
            { id = "b", family = "tires", effect = 1.05 },
            { id = "a", family = "power_unit", effect = 1.20 },
        } })
        T.eq(M.signature(forward), M.signature(backward),
            "multiplicative composition is order-independent, so a table iteration cannot change a car")
    end,

    a_part_that_cannot_be_felt_refuses_the_whole_setup_rather_than_being_dropped = function(T)
        local M = H(T)
        local setup, why = M.compose({ parts = {
            { id = "eng", family = "power_unit", effect = 1.15 },
            { id = "coilovers", family = "suspension", effect = 1.10 },
        } })
        T.eq(setup, nil, "the compose is refused")
        T.match(why, "coilovers", "the refusal names the offending part")
        T.match(why, "suspension", "and its family")
    end,

    a_malformed_effect_is_refused_with_the_value_in_the_message = function(T)
        local M = H(T)
        for _, bad in ipairs({ 0, -1, "1.2" }) do
            local setup, why = M.compose({ parts = { { id = "p", family = "tires", effect = bad } } })
            T.eq(setup, nil, "effect " .. tostring(bad) .. " is refused")
            T.match(why, "finite positive multiplier")
        end
        local setup = M.compose({ parts = { { id = "p", family = "tires", effect = 0 / 0 } } })
        T.eq(setup, nil, "NaN is refused")
    end,

    -- ------------------------------------------------------------------ clamping
    clamping_happens_once_on_the_product_not_per_part = function(T)
        local M = H(T)
        -- Three legal parts, each individually well inside the bound, composing past it. Clamping each
        -- contribution separately would let this through with every step looking fine.
        local setup = M.compose({ parts = {
            { id = "a", family = "power_unit", effect = 1.40 },
            { id = "b", family = "power_unit", effect = 1.40 },
            { id = "c", family = "power_unit", effect = 1.40 },
        } })
        T.ok(near(setup.levers.driveScale, 2.00), "clamped to the carrier's maximum")
        T.eq(#setup.clamped, 1, "exactly one clamp recorded")
        T.eq(setup.clamped[1].lever, "driveScale")
        T.ok(setup.clamped[1].wanted > 2.7, "the value it WANTED is kept, not just the applied one")
    end,

    a_clamp_is_visible_in_the_human_explanation = function(T)
        local M = H(T)
        local setup = M.compose({ parts = { { id = "a", family = "tires", effect = 9.0 } } })
        T.match(M.explain(setup), "CLAMPED", "a silently clamped setup is how a player loses trust")
    end,

    -- ------------------------------------------------------------------ the wire form (KB-136)
    the_wire_form_carries_the_levers_and_not_the_audit_trail = function(T)
        local M = H(T)
        local setup = M.compose({ vehicle = "v1", parts = {
            { id = "a", family = "power_unit", effect = 1.15 },
            { id = "b", family = "tires", effect = 1.05 },
        } }, { at = 100 })
        T.eq(#setup.trace, 2, "the trace exists server-side")
        local wire = M.wire(setup)
        T.eq(wire.trace, nil, "KB-136: the trace does not cross the wire")
        T.eq(wire.clamped, nil, "nor does the clamp record")
        T.eq(wire.vehicle, nil, "nor the server's own handle for the machine")
        T.ok(near(wire.levers.driveScale, 1.15), "the levers do")
        T.eq(wire.v, M.SETUP_VERSION, "and a version, so the carrier can refuse a shape it does not know")
    end,

    the_wire_form_always_carries_all_three_levers = function(T)
        local M = H(T)
        -- A partial payload would leave the carrier holding a stale value for the missing lever, which is
        -- the same class of bug as a record that stops being published and keeps yesterday's rain.
        local wire = M.wire(M.compose({ parts = { { id = "a", family = "tires", effect = 1.05 } } }))
        for _, id in ipairs(M.LEVER_IDS) do
            T.eq(type(wire.levers[id]), "number", id .. " is always present, even when inert")
        end
    end,

    -- ------------------------------------------------------------------ clearing and signatures
    clear_is_every_lever_inert_and_is_not_the_same_as_sending_nothing = function(T)
        local M = H(T)
        local cleared = M.clear("v1", { at = 200 })
        T.eq(M.isInert(cleared), true)
        local wire = M.wire(cleared)
        for _, id in ipairs(M.LEVER_IDS) do
            T.ok(near(wire.levers[id], M.LEVERS[id].inert),
                id .. " is explicitly restored rather than omitted")
        end
    end,

    the_signature_moves_only_when_a_lever_moves = function(T)
        local M = H(T)
        local a = M.compose({ vehicle = "v1", parts = { { id = "x", family = "tires", effect = 1.05 } } },
                            { at = 100 })
        -- Same levers, different clock and a different part id reaching the same value: must not republish.
        local b = M.compose({ vehicle = "v1", parts = { { id = "y", family = "tires", effect = 1.05 } } },
                            { at = 999 })
        T.eq(M.signature(a), M.signature(b), "the signature is the applied truth, not the paperwork")
        local c = M.compose({ vehicle = "v1", parts = { { id = "x", family = "tires", effect = 1.06 } } },
                            { at = 100 })
        T.neq(M.signature(a), M.signature(c), "a moved lever does republish")
        T.eq(M.signature(nil), "none", "and a missing setup has an answer rather than an error")
    end,

    -- ------------------------------------------------------------------ honesty about what is not live
    the_inventory_says_which_families_cannot_be_felt_live_yet = function(T)
        local M = H(T)
        local inv = M.inventory()
        T.eq(#inv.live, 3, "three live families")
        T.eq(#inv.live + #inv.notLive, 12, "every family is accounted for, one way or the other")
        local names = {}
        for _, entry in ipairs(inv.live) do names[entry.family] = true end
        T.ok(names.tires and names.power_unit and names.brakes, "and they are the three that were proven")
    end,
}
