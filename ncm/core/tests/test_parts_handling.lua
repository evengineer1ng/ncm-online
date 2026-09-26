-- parts.handling -- the instance channel, which is the half of Parts that is per-player.
--
-- These test the RULES, not the balance. No number in this suite is a design judgement: 18_PARTS_ECOSYSTEM
-- puts component balance out of scope, so every `effect` here is chosen to exercise arithmetic or a bound,
-- and the suite deliberately asserts NOTHING about the size of any weight in `EXPRESSION`. Weights are a
-- first pass awaiting play data; a test that pinned them would turn tuning into a test failure.
--
-- What it does assert is the shape that keeps the system honest once approximation is allowed (`L154`):
--
--   1. Every family has exactly one answer -- an expression or a stated refusal. A family that is neither
--      is a gap nobody notices, which is how the ontology drifted twice in one day.
--   2. Every expression enumerates its LOSSES. Approximation is permitted; promising a mechanism you do
--      not have is not, and `losses` is where that line is kept.
--   3. Composition stays commutative, because exponents compose and a car must not depend on Lua's table
--      iteration order.
--   4. An inverse coupling really is inverse -- a wing that adds grip must cost drive force, or the part
--      is a free lunch.
--   5. The wire form carries no audit trail (`KB-136`, the state bag size limit).
local function H(T) return T.Core.get("parts.handling") end
local function O(T) return T.Core.get("parts.ontology") end

local function near(a, b) return math.abs(a - b) < 1e-6 end

return {
    -- ------------------------------------------------------------------ the levers are evidence-backed
    every_lever_names_the_live_pass_that_authorises_it = function(T)
        local M = H(T)
        T.eq(#M.LEVER_IDS, 3, "three proven levers -- the vocabulary is still three wide")
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

    -- ------------------------------------------------------------------ every family has ONE answer
    every_family_is_either_expressed_or_refused_with_a_reason = function(T)
        local M, Ont = H(T), O(T)
        for _, family in ipairs(Ont.FAMILIES) do
            local expression = M.EXPRESSION[family]
            local refusal = M.REFUSED[family]
            T.ok((expression ~= nil) ~= (refusal ~= nil),
                family .. " must have exactly one of an expression and a refusal, never both or neither")
            if refusal then
                T.ok(#refusal > 20, family .. "'s refusal states a mechanism, not just 'no'")
            end
        end
    end,

    eleven_of_twelve_families_reach_a_force = function(T)
        local M, Ont = H(T), O(T)
        local expressed, refused = 0, 0
        for _, family in ipairs(Ont.FAMILIES) do
            if M.EXPRESSION[family] then expressed = expressed + 1 else refused = refused + 1 end
        end
        T.eq(expressed, 11, "approximation is allowed, so most families are reachable")
        T.eq(refused, 1, "and exactly one is not")
        T.ok(M.REFUSED.steering, "steering, because response is not force magnitude (KB-135)")
    end,

    -- ------------------------------------------------------------------ honesty lives in `losses`
    every_expression_enumerates_what_it_cannot_do = function(T)
        local M, Ont = H(T), O(T)
        for _, family in ipairs(Ont.FAMILIES) do
            local e = M.EXPRESSION[family]
            if e then
                T.ok(#e.rationale > 20, family .. " says why its expression is defensible")
                T.ok(#e.losses > 0, family .. " enumerates what it cannot express")
                -- Even a DIRECT expression loses something. "Direct" means the lever is the quantity, not
                -- that a part in that family is fully modelled -- tyres still cannot do per-corner or wear.
                for _, loss in ipairs(e.losses) do
                    T.ok(type(loss) == "string" and #loss > 5, family .. " has a substantive loss entry")
                end
            end
        end
    end,

    the_three_direct_families_are_the_three_that_were_driven = function(T)
        local M = H(T)
        local direct = {}
        for family, e in pairs(M.EXPRESSION) do
            if e.fidelity == M.DIRECT then direct[family] = true end
        end
        T.ok(direct.tires and direct.power_unit and direct.brakes, "AU5, AW1 and AW2")
        local n = 0
        for _ in pairs(direct) do n = n + 1 end
        T.eq(n, 3, "and nothing else claims to be direct")
    end,

    a_moment_is_never_claimed_by_any_expression = function(T)
        local M = H(T)
        -- Section AW3 refuted the per-corner load entries with a mechanism: the force accumulator carries
        -- no position, so a zero-sum redistribution cannot produce a moment. Anything moment-shaped must
        -- therefore appear in `losses` and never in a rationale as a promise.
        for _, family in ipairs({ "suspension", "brakes", "drivetrain", "aerodynamics" }) do
            local e = M.EXPRESSION[family]
            local mentioned = false
            for _, loss in ipairs(e.losses) do
                if loss:lower():match("moment") or loss:lower():match("bias")
                    or loss:lower():match("balance") or loss:lower():match("lock")
                    or loss:lower():match("split") then
                    mentioned = true
                end
            end
            T.eq(mentioned, true, family .. " must name the moment-shaped thing it cannot do")
        end
    end,

    -- ------------------------------------------------------------------ agreement with the ontology
    the_ontology_and_the_expressions_describe_the_same_families = function(T)
        local M, Ont = H(T), O(T)
        -- The module asserts this at load, so reaching here at all is most of the test. This pins the
        -- count so a silent narrowing -- the failure that has now happened twice -- fails loudly.
        local n = 0
        for family in pairs(Ont.INSTANCE_QUANTITIES) do
            n = n + 1
            T.ok(M.EXPRESSION[family], "ontology claims '" .. family .. "' is live; handling expresses it")
            T.ok(Ont.INSTANCE_FIDELITY[family], family .. " declares its fidelity")
        end
        T.eq(n, 11, "eleven families reach the instance channel")
        T.eq(Ont.INSTANCE_REFUSED.steering, true, "and steering is recorded as refused, not absent")
    end,

    an_unknown_family_is_distinguished_from_a_refused_one = function(T)
        local M = H(T)
        local _, typo = M.expressionFor("warp_drive")
        T.match(typo, "unknown family", "a typo and a real-but-refused family are different answers")
        local _, refused = M.expressionFor("steering")
        T.match(refused, "KB%-135", "the refusal cites the decision that reserves input authority")
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

    a_direct_part_moves_its_lever_by_exactly_its_effect = function(T)
        local M = H(T)
        local setup = M.compose({ vehicle = "v1", parts = {
            { id = "eng_stage2", family = "power_unit", effect = 1.15 },
        } }, { at = 100 })
        T.ok(near(setup.levers.driveScale, 1.15), "direct means the number arrives unchanged")
        T.ok(near(setup.levers.gripScale, 1.00), "gripScale untouched")
        T.ok(near(setup.levers.brakeScale, 1.00), "brakeScale untouched")
        T.eq(setup.approximated, 0, "nothing was modelled")
    end,

    an_approximated_part_moves_its_lever_by_effect_to_the_weight = function(T)
        local M = H(T)
        local weight = M.EXPRESSION.suspension.terms[1].weight
        local setup = M.compose({ parts = {
            { id = "coilovers", family = "suspension", effect = 1.30 },
        } })
        T.ok(near(setup.levers.gripScale, 1.30 ^ weight),
            "the effect reaches the lever as effect^weight, whatever the weight currently is")
        T.eq(setup.approximated, 1, "and the setup reports that it is a model, not a measurement")
        T.match(M.explain(setup), "approximated", "which a human-readable line must say out loud")
    end,

    -- ------------------------------------------------------------------ the inverse coupling
    a_wing_adds_grip_and_costs_drive_force = function(T)
        local M = H(T)
        -- The single most important property of the approximation model: a part that gives must also take
        -- where physics says it takes. A wing that added grip for free would make the whole system a joke.
        local setup = M.compose({ parts = {
            { id = "wing_gt", family = "aerodynamics", effect = 1.40 },
        } })
        T.ok(setup.levers.gripScale > 1.0, "downforce raises grip")
        T.ok(setup.levers.driveScale < 1.0, "and drag costs drive force")
        -- And the trade reverses for a part that REMOVES aero.
        local stripped = M.compose({ parts = {
            { id = "wing_off", family = "aerodynamics", effect = 0.80 },
        } })
        T.ok(stripped.levers.gripScale < 1.0, "less downforce, less grip")
        T.ok(stripped.levers.driveScale > 1.0, "less drag, more drive -- the trade runs both ways")
    end,

    a_mass_part_moves_all_three_levers_together = function(T)
        local M = H(T)
        local setup = M.compose({ parts = {
            { id = "lightweight_shell", family = "chassis", effect = 1.25 },
        } })
        for _, id in ipairs(M.LEVER_IDS) do
            T.ok(setup.levers[id] > 1.0, id .. " improves -- a lighter car is better everywhere")
        end
        T.match(table.concat(M.EXPRESSION.chassis.losses, " "), "MASS",
            "and it says plainly that it is not actually changing mass")
    end,

    -- ------------------------------------------------------------------ composition arithmetic
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
        -- With mixed fidelities and an inverse coupling in the mix, which is the case that would break if
        -- anything in the pipeline were additive or order-sensitive.
        local list = {
            { id = "a", family = "power_unit", effect = 1.20 },
            { id = "b", family = "aerodynamics", effect = 1.30 },
            { id = "c", family = "suspension", effect = 1.10 },
            { id = "d", family = "chassis", effect = 0.95 },
        }
        local reversed = {}
        for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
        T.eq(M.signature(M.compose({ parts = list })), M.signature(M.compose({ parts = reversed })),
            "exponents compose, so a car cannot depend on table iteration order")
    end,

    a_refused_family_refuses_the_whole_setup_rather_than_being_dropped = function(T)
        local M = H(T)
        local setup, why = M.compose({ parts = {
            { id = "eng", family = "power_unit", effect = 1.15 },
            { id = "quickrack", family = "steering", effect = 1.10 },
        } })
        T.eq(setup, nil, "the compose is refused")
        T.match(why, "quickrack", "the refusal names the offending part")
        T.match(why, "steering", "and its family")
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
            { id = "b", family = "aerodynamics", effect = 1.05 },
        } }, { at = 100 })
        T.eq(#setup.trace, 2, "the trace exists server-side")
        local wire = M.wire(setup)
        T.eq(wire.trace, nil, "KB-136: the trace does not cross the wire")
        T.eq(wire.clamped, nil, "nor does the clamp record")
        T.eq(wire.vehicle, nil, "nor the server's own handle for the machine")
        T.ok(near(wire.levers.driveScale, setup.levers.driveScale), "the levers do")
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

    -- ------------------------------------------------------------------ describing, for a panel
    describe_tells_a_panel_what_to_promise_and_what_not_to = function(T)
        local M = H(T)
        local d = M.describe("aerodynamics")
        T.eq(d.expressible, true)
        T.eq(d.fidelity, M.APPROXIMATED, "a wing is modelled, and a panel must be able to say so")
        T.eq(#d.levers, 2, "grip and drive")
        local directions = {}
        for _, l in ipairs(d.levers) do directions[l.lever] = l.direction end
        T.eq(directions.gripScale, "increases")
        T.eq(directions.driveScale, "decreases", "the trade is legible without reading the weights")
        T.ok(#d.losses > 0, "and what it cannot do is part of the same answer")

        local refused = M.describe("steering")
        T.eq(refused.expressible, false, "a refusal is describable too, rather than nil")
        T.ok(#refused.reason > 20, "with its mechanism")
    end,

    the_inventory_splits_by_fidelity_rather_than_by_whether_it_works = function(T)
        local M, Ont = H(T), O(T)
        local inv = M.inventory()
        T.eq(#inv.direct, 3)
        T.eq(#inv.approximated, 8)
        T.eq(#inv.refused, 1)
        T.eq(#inv.direct + #inv.approximated + #inv.refused, #Ont.FAMILIES,
            "every family is accounted for, one way or another")
    end,
}
