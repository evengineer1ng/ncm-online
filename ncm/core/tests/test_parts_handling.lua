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
--   6. **No two families point in the same DIRECTION** (`L156`). This is the one that would have caught
--      the failure it was written for: four families were `driveScale` alone, differing only in how hard
--      they pushed, which is one part wearing four names. Magnitudes are still deliberately untested --
--      a direction is a design claim, a magnitude is a tuning value, and only one of those should fail a
--      build.
--   7. A coupling only ever REDUCES a lever. A rule that could raise one would be inventing force that
--      no part paid for.
local function H(T) return T.Core.get("parts.handling") end
local function O(T) return T.Core.get("parts.ontology") end

local function near(a, b) return math.abs(a - b) < 1e-6 end

return {
    -- ------------------------------------------------------------------ the levers are evidence-backed
    every_lever_names_the_live_pass_that_authorises_it = function(T)
        local M = H(T)
        -- Four since 2026-09-26. `dragScale` split out of `brakeScale`, which had been scaling
        -- aerodynamic drag as well as braking and therefore letting a brake part move top speed.
        T.eq(#M.LEVER_IDS, 4, "four proven levers -- grip, drive, brake and drag")
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

    a_direct_part_moves_its_primary_lever_by_exactly_its_effect = function(T)
        local M = H(T)
        local setup = M.compose({ vehicle = "v1", parts = {
            { id = "eng_stage2", family = "power_unit", effect = 1.15 },
        } }, { at = 100 })
        T.ok(near(setup.levers.driveScale, 1.15),
            "direct means the number arrives unchanged on the family's OWN quantity")
        -- `L156`: a family reaches more than its own quantity. An engine is mass over an axle, so it
        -- costs a little cornering -- power is a trade rather than a gift.
        T.ok(setup.levers.gripScale < 1.00, "and a bigger engine costs a little grip")
        T.ok(near(setup.levers.brakeScale, 1.00), "but a brake is not an engine's business")
        T.eq(setup.approximated, 0, "the PRIMARY term was direct, so nothing counts as modelled")
        T.eq(#setup.limited, 0, "and 1.15 is inside the stock traction ceiling of 1.30")
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
    a_wing_adds_grip_and_costs_top_speed = function(T)
        local M = H(T)
        -- The single most important property of the approximation model: a part that gives must also take
        -- where physics says it takes. A wing that added grip for free would make the whole system a joke.
        local setup = M.compose({ parts = {
            { id = "wing_gt", family = "aerodynamics", effect = 1.40 },
        } })
        T.ok(setup.levers.gripScale > 1.0, "downforce raises grip")
        -- **Booked against DRAG, not against the engine.** A wing does not reduce engine power, and
        -- expressing its cost as `driveScale` said exactly that -- a car that read slower on a dyno.
        T.ok(setup.levers.dragScale > 1.0, "and the same wing costs top speed, as drag")
        T.eq(setup.levers.driveScale, 1.0, "a wing leaves engine output alone")
        -- And the trade reverses for a part that REMOVES aero.
        local stripped = M.compose({ parts = {
            { id = "wing_off", family = "aerodynamics", effect = 0.80 },
        } })
        T.ok(stripped.levers.gripScale < 1.0, "less downforce, less grip")
        T.ok(stripped.levers.dragScale < 1.0, "less drag, more top end -- the trade runs both ways")
    end,

    a_mass_part_moves_every_lever_together = function(T)
        local M = H(T)
        local setup = M.compose({ parts = {
            { id = "lightweight_shell", family = "chassis", effect = 1.25 },
        } })
        -- **"Improves" is not "goes up".** Three levers are forces the car wants more of and one is a
        -- force it wants less of, so a single `> 1.0` loop would assert that more drag is an upgrade.
        for _, id in ipairs(M.LEVER_IDS) do
            local better = (id == "dragScale") and (setup.levers[id] < 1.0) or (setup.levers[id] > 1.0)
            T.ok(better, id .. " improves -- a lighter car is better everywhere, drag included")
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
        -- On `gripScale`, which takes no coupling ceiling -- so this tests the clamp and only the clamp.
        -- Doing it on `driveScale` would now measure `traction_ceiling` instead, a different rule.
        local setup = M.compose({ parts = {
            { id = "a", family = "tires", effect = 1.20 },
            { id = "b", family = "tires", effect = 1.20 },
            { id = "c", family = "tires", effect = 1.20 },
        } })
        T.ok(near(setup.levers.gripScale, 1.50), "clamped to the carrier's maximum")
        T.eq(#setup.clamped, 1, "exactly one clamp recorded")
        T.eq(setup.clamped[1].lever, "gripScale")
        T.ok(setup.clamped[1].wanted > 1.70, "the value it WANTED is kept, not just the applied one")
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
        T.eq(wire.limited, nil, "nor the coupling record (`L156`) -- KB-136 applies to it too")
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
        T.eq(#d.levers, 3, "grip, drag and brake -- drag shortens a stop as well as costing top end")
        local directions = {}
        for _, l in ipairs(d.levers) do directions[l.lever] = l.direction end
        T.eq(directions.gripScale, "increases")
        T.eq(directions.dragScale, "increases", "the trade is legible without reading the weights")
        T.eq(directions.brakeScale, "increases", "and the same drag that costs top end helps it stop")
        T.eq(d.levers[1].role, "primary", "the family's own quantity is first")
        T.eq(d.levers[2].role, "coupling", "and the rest are couplings, always modelled")
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

    -- ------------------------------------------------------------------ `L156`: directions, not lengths
    no_two_families_point_in_the_same_direction = function(T)
        local M, Ont = H(T), O(T)
        -- **The test written for the bug it would have caught.** Before `L156`, `transmission`,
        -- `drivetrain`, `cooling` and `electrical` were all `{ driveScale }` at 0.5, 0.5, 0.3 and 0.3 --
        -- the same direction at four lengths, which is one part wearing four names. A player fitting one
        -- could not tell it from another, because there was nothing to tell apart.
        --
        -- Direction is normalised so magnitude cannot disguise a duplicate. This fails on the OLD table
        -- and passes on the new one, which is the only property worth having here.
        local seen = {}
        for _, family in ipairs(Ont.FAMILIES) do
            if M.EXPRESSION[family] then
                local key = M.directionKey(family)
                T.ok(key, family .. " has a direction")
                T.ok(not seen[key], family .. " points somewhere no other family already points"
                    .. (seen[key] and " (collides with " .. seen[key] .. ")" or ""))
                seen[key] = family
            end
        end
    end,

    the_two_families_that_used_to_be_copies_now_trade_differently = function(T)
        local M = H(T)
        -- `transmission` and `drivetrain` are both drive-primary at almost the same magnitude. What
        -- separates them is the SIGN of their second term, and that is a difference felt in a corner.
        local gears = M.compose({ parts = { { id = "g", family = "transmission", effect = 1.40 } } })
        local diff  = M.compose({ parts = { { id = "d", family = "drivetrain",   effect = 1.40 } } })
        T.ok(gears.levers.driveScale > 1.0 and diff.levers.driveScale > 1.0, "both deliver more drive")
        T.ok(gears.levers.brakeScale > 1.0, "shorter gearing brakes the engine on the overrun")
        T.ok(near(gears.levers.gripScale, 1.0), "and costs no grip")
        T.ok(diff.levers.gripScale < 1.0, "a tighter driveline costs turn-in")
        T.ok(near(diff.levers.brakeScale, 1.0), "and does nothing for stopping")
    end,

    a_tyre_shortens_a_stop_because_braking_is_grip_limited = function(T)
        local M = H(T)
        -- The old table had `tires` not touching `brakeScale` at all. That is not a simplification, it is
        -- wrong: tyres are most of a stopping distance.
        local setup = M.compose({ parts = { { id = "t", family = "tires", effect = 1.30 } } })
        T.ok(setup.levers.brakeScale > 1.0, "better tyres stop the car sooner")
        T.ok(setup.levers.driveScale > 1.0, "and put power down better")
        T.ok(setup.levers.gripScale > setup.levers.brakeScale,
            "but cornering is still where a tyre does most of its work")
    end,

    -- ------------------------------------------------------------------ `L156`: the couplings
    a_big_engine_on_stock_tyres_is_traction_limited = function(T)
        local M = H(T)
        local setup = M.compose({ parts = { { id = "big", family = "power_unit", effect = 2.00 } } })
        T.eq(#setup.limited, 1, "the ceiling bit exactly once")
        local entry = setup.limited[1]
        T.eq(entry.coupling, "traction_ceiling")
        T.eq(entry.lever, "driveScale")
        T.eq(entry.from, "gripScale", "and it names the lever that set the ceiling")
        T.ok(entry.wanted > entry.applied, "it reduced, and kept what the parts asked for")
        T.ok(near(setup.levers.driveScale, entry.applied), "the applied value is the ceiling")
        T.ok(setup.levers.driveScale < 1.35, "a 2.0 engine on stock rubber is worth far less than 2.0")
        T.ok(#entry.headline > 10 and #entry.advice > 10,
            "and says what happened and what to do about it, not just that a number moved")
    end,

    fitting_tyres_lifts_the_ceiling_the_engine_was_hitting = function(T)
        local M = H(T)
        -- **The emergent build, which is the whole point of the couplings.** The engine is unchanged; what
        -- changes is whether the car can use it.
        local alone = M.compose({ parts = { { id = "big", family = "power_unit", effect = 2.00 } } })
        local shod  = M.compose({ parts = {
            { id = "big", family = "power_unit", effect = 2.00 },
            { id = "t",   family = "tires",      effect = 1.40 },
        } })
        T.ok(shod.levers.driveScale > alone.levers.driveScale,
            "the same engine delivers more once the tyres can carry it")
        T.ok(shod.levers.gripScale > alone.levers.gripScale, "and the car corners better too")
    end,

    a_ceiling_only_ever_reduces_and_never_invents_force = function(T)
        local M = H(T)
        -- Tyres raise the drive ceiling well above what is fitted. If a coupling could push UP,
        -- `driveScale` would arrive there having bought no engine at all -- a buff in a physics costume.
        local setup = M.compose({ parts = { { id = "t", family = "tires", effect = 1.40 } } })
        T.eq(#setup.limited, 0, "nothing was limited")
        T.ok(setup.levers.driveScale < 1.10,
            "drive force still comes only from what was fitted, never from the headroom")
        local ceilings = M.ceilings(setup.levers)
        T.ok(ceilings.driveScale > setup.levers.driveScale,
            "the headroom is real and unused, which is exactly the state a panel should show")
    end,

    a_brake_cannot_beat_the_tyre_it_acts_through = function(T)
        local M = H(T)
        local setup = M.compose({ parts = { { id = "b", family = "brakes", effect = 2.00 } } })
        T.eq(#setup.limited, 1)
        T.eq(setup.limited[1].coupling, "brake_grip_limit")
        T.ok(setup.levers.brakeScale < 1.25, "past the tyre, a bigger disc locks up rather than stops")
        local shod = M.compose({ parts = {
            { id = "b", family = "brakes", effect = 2.00 },
            { id = "t", family = "tires",  effect = 1.40 },
        } })
        T.ok(shod.levers.brakeScale > setup.levers.brakeScale, "and tyres are what lift it")
    end,

    a_coupling_can_never_push_a_lever_below_its_own_floor = function(T)
        local M = H(T)
        -- Asserted at load too, but stated here because the failure mode would be silent: a ceiling under
        -- the clamp floor leaves a value neither rule asked for.
        for _, coupling in ipairs(M.COUPLINGS) do
            local worst = coupling.base + coupling.slope * M.LEVERS[coupling.from].min
            T.ok(worst >= M.LEVERS[coupling.lever].min,
                coupling.id .. " stays above " .. coupling.lever .. "'s floor even at minimum grip")
        end
    end,

    the_ceilings_helper_answers_before_the_money_is_spent = function(T)
        local M = H(T)
        local stock = M.ceilings(M.clear("v1").levers)
        T.ok(near(stock.driveScale, 1.30), "a stock-tyred car can absorb a modest engine and no more")
        T.ok(near(stock.brakeScale, 1.20), "and a modest brake")
        local grippy = M.ceilings({ gripScale = 1.50, driveScale = 1.0, brakeScale = 1.0 })
        T.ok(grippy.driveScale > stock.driveScale and grippy.brakeScale > stock.brakeScale,
            "every further increment of power has to be bought with grip")
    end,

    a_limit_is_visible_in_the_human_explanation = function(T)
        local M = H(T)
        local setup = M.compose({ parts = { { id = "big", family = "power_unit", effect = 2.00 } } })
        T.match(M.explain(setup), "LIMITED",
            "a silently limited setup is the same betrayal as a silently clamped one")
        T.match(M.explain(setup), "traction_ceiling", "and it names which rule did it")
    end,

    describe_warns_which_ceiling_can_bite_this_family = function(T)
        local M = H(T)
        local engine = M.describe("power_unit")
        T.eq(#engine.constrainedBy, 1, "an engine is traction-limited")
        T.eq(engine.constrainedBy[1].coupling, "traction_ceiling")
        T.ok(#engine.constrainedBy[1].advice > 10, "with the remedy, stated before the purchase")
        local brakes = M.describe("brakes")
        T.eq(brakes.constrainedBy[1].coupling, "brake_grip_limit")
        T.eq(#M.describe("structure").constrainedBy, 1, "structure reaches brake, so it can be limited")
    end,

    the_couplings_do_not_depend_on_the_order_parts_arrive_in = function(T)
        local M = H(T)
        -- A build where a ceiling actually bites, which is the case that would break if the couplings
        -- were folded into the per-part loop rather than applied once at the end.
        local list = {
            { id = "a", family = "power_unit", effect = 1.80 },
            { id = "b", family = "tires", effect = 1.20 },
            { id = "c", family = "aerodynamics", effect = 1.30 },
            { id = "d", family = "drivetrain", effect = 1.15 },
        }
        local reversed = {}
        for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
        local forward, backward = M.compose({ parts = list }), M.compose({ parts = reversed })
        T.ok(#forward.limited > 0, "the ceiling really does bite in this build")
        T.eq(M.signature(forward), M.signature(backward),
            "so the couplings must be applied once on the product, not while walking the parts")
        T.eq(#forward.limited, #backward.limited, "and report identically")
    end,

    -- ------------------------------------------------------------------ `L158`: contributors
    parts_only_composition_is_unchanged_by_the_contributor_pipeline = function(T)
        local M = H(T)
        -- **The regression gate for the whole refactor.** Adding named contributors must not move a single
        -- number for a car that has only parts fitted, or every earlier MASTER_TEST result is invalidated.
        local setup = M.compose({ parts = {
            { id = "e", family = "power_unit", effect = 1.40 },
            { id = "t", family = "tires", effect = 1.20 },
        } })
        T.ok(near(setup.levers.gripScale, (1.40 ^ -0.10) * 1.20), "grip is exactly what L156 composed")
        T.eq(#setup.limited, 1, "and the traction ceiling still bites in the same place")
    end,

    a_contributor_multiplies_the_levers_and_is_traced = function(T)
        local M = H(T)
        local setup = M.compose({
            parts = { { id = "t", family = "tires", effect = 1.20 } },
            weather = { source = "weather", gripScale = 0.90 },
        })
        T.ok(near(setup.levers.gripScale, 1.20 * 0.90), "the contributor composes onto the parts")
        local found
        for _, row in ipairs(setup.trace) do
            if row.layer == "weather" then found = row end
        end
        T.ok(found, "and it appears in the trace")
        T.eq(found.lever, "gripScale")
        T.ok(near(found.multiplier, 0.90))
    end,

    an_inert_contributor_is_traced_rather_than_omitted = function(T)
        local M = H(T)
        -- **The `IDEA-516` failure class, guarded.** A contributor returning exactly 1.0 is otherwise
        -- indistinguishable from a contributor nobody wired up -- and would be silently broken on the day
        -- it is switched on. The weather seam ships neutral, so this is the property that makes it real.
        local setup = M.compose({
            parts = {},
            weather = M.weatherContributor(0),
        })
        T.eq(M.isInert(setup), true, "a dry road changes nothing")
        local seen = false
        for _, row in ipairs(setup.trace) do
            if row.layer == "weather" then
                seen = true
                T.eq(row.inert, true, "and it says out loud that it was inert")
            end
        end
        T.eq(seen, true, "the neutral contribution is VISIBLE, not absent")
    end,

    contributors_compose_in_any_order = function(T)
        local M = H(T)
        local a = M.compose({ parts = { { id = "t", family = "tires", effect = 1.1 } },
                              weather = { gripScale = 0.9 }, thermal = { gripScale = 0.95 } })
        local b = M.compose({ thermal = { gripScale = 0.95 }, weather = { gripScale = 0.9 },
                              parts = { { id = "t", family = "tires", effect = 1.1 } } })
        T.eq(M.signature(a), M.signature(b), "multiplication is commutative and the pipeline must stay so")
    end,

    a_malformed_contributor_is_refused_by_name = function(T)
        local M = H(T)
        local setup, why = M.compose({ parts = {}, weather = { gripScale = -1 } })
        T.eq(setup, nil)
        T.match(why, "weather", "the refusal names the layer")
        local s2, w2 = M.compose({ parts = {}, thermal = "hot" })
        T.eq(s2, nil)
        T.match(w2, "thermal")
    end,

    contributor_values_are_quantised_so_a_drifting_term_does_not_republish = function(T)
        local M = H(T)
        -- `signature()` formats at %.4f and `server/handling.lua` suppresses an unchanged payload on it.
        -- A continuously varying thermal value would otherwise write the state bag twice a second per
        -- driver forever -- a defect the server file records as having already happened once.
        local a = M.compose({ parts = {}, thermal = { gripScale = 0.9412 } })
        local b = M.compose({ parts = {}, thermal = { gripScale = 0.9433 } })
        T.eq(M.signature(a), M.signature(b), "two values inside one quantum are one value")
        local c = M.compose({ parts = {}, thermal = { gripScale = 0.92 } })
        T.neq(M.signature(a), M.signature(c), "a real move still republishes")
    end,

    -- ------------------------------------------------------------------ `L159`: the thermal contributor
    the_thermal_contributor_touches_grip_AND_brake = function(T)
        local M, Th = H(T), T.Core.get("parts.thermal")
        -- **A correction.** An earlier draft assumed a reduced gripScale would propagate into braking and
        -- power through the L156 couplings. It does not: at grip 0.85 the ceilings are 1.18 and 1.08, and
        -- a stock car sits at 1.00 on both, so neither bites.
        local cold = M.thermalContributor(Th.OPTIMUM - Th.HALF_WINDOW)
        T.ok(cold.gripScale < 1.0, "cold tyres cost grip")
        T.ok(cold.brakeScale < 1.0, "AND braking, directly, because the couplings would not carry it")

        local stock = M.compose({ parts = {}, thermal = cold })
        T.ok(stock.levers.brakeScale < 1.0,
            "so a stock car with cold tyres really does brake worse")
        T.eq(#stock.limited, 0, "and no coupling was involved in delivering that")
    end,

    -- `L208`/`E26`: grip above 1.0 loosens the rear on this engine, so an overheated tyre is authored as a
    -- LOOSE car with weak brakes, while a cold one still pushes. Braking is never a boost.
    the_thermal_contributor_pushes_cold_and_goes_loose_hot = function(T)
        local M, Th = H(T), T.Core.get("parts.thermal")
        local window = M.thermalContributor(Th.OPTIMUM)
        T.ok(near(window.gripScale, 1.0) and near(window.brakeScale, 1.0), "in the window there is no charge")
        local cold = M.thermalContributor(Th.OPTIMUM - Th.HALF_WINDOW)
        T.ok(cold.gripScale < 1.0, "cold pushes")
        local hot = M.thermalContributor(Th.OPTIMUM + Th.HALF_WINDOW)
        T.ok(near(hot.gripScale, 1.0 + Th.HOT_LOOSE), "fully hot is loose by exactly HOT_LOOSE")
        T.ok(near(hot.brakeScale, 1.0 - Th.HOT_BRAKE), "and brakes weaker by exactly HOT_BRAKE")
        for t = -50, 250, 10 do
            local c = M.thermalContributor(t)
            T.ok(c.brakeScale <= 1.0, ("%dC must never add braking"):format(t))
            T.ok(c.gripScale <= 1.0 + Th.HOT_LOOSE + 1e-9, ("%dC grip stays inside the hot bound"):format(t))
        end
    end,

    -- ------------------------------------------------------------------ `L157`: top speed
    top_speed_is_composed_but_is_not_a_lever = function(T)
        local M = H(T)
        T.eq(M.LEVERS.topSpeedScale, nil, "it is not in the lever table")
        local isLever = false
        for _, id in ipairs(M.LEVER_IDS) do if id == "topSpeedScale" then isLever = true end end
        T.eq(isLever, false, "nor in the declared lever order")
        local setup = M.compose({ parts = { { id = "w", family = "aerodynamics", effect = 0.80 } } })
        T.ok(setup.topSpeedScale > 1.0, "but stripping drag does raise it")
        T.eq(M.wire(setup).topSpeedScale, nil,
            "and it does NOT cross the wire -- the Carrier has no business with a governor")
    end,

    a_low_drag_part_raises_top_speed_and_a_wing_lowers_it = function(T)
        local M = H(T)
        local stripped = M.compose({ parts = { { id = "s", family = "aerodynamics", effect = 0.70 } } })
        local winged = M.compose({ parts = { { id = "w", family = "aerodynamics", effect = 1.40 } } })
        T.ok(stripped.topSpeedScale > 1.0, "less drag, more top end")
        T.ok(winged.topSpeedScale < 1.0, "more downforce, less top end -- the same trade as the levers")
        T.ok(winged.levers.gripScale > 1.0, "and the wing still buys grip, which is the point of fitting it")
    end,

    top_speed_is_clamped_to_a_governor_sized_range = function(T)
        local M = H(T)
        local absurd = M.compose({ parts = {
            { id = "a", family = "aerodynamics", effect = 0.30 },
            { id = "b", family = "power_unit", effect = 3.00 },
            { id = "c", family = "transmission", effect = 2.00 },
        } })
        T.ok(absurd.topSpeedScale <= M.TOP_SPEED.max, "a governor that doubles top speed is not a governor")
        T.ok(absurd.topSpeedScale >= M.TOP_SPEED.min)
    end,

    the_class_ruleset_always_beats_a_parts_ceiling = function(T)
        local M = H(T)
        local fast = M.compose({ parts = { { id = "s", family = "aerodynamics", effect = 0.70 } } })
        local open = M.topSpeedKph(fast, 200, nil)
        T.ok(open > 200, "with no class cap, parts raise the ceiling above the authored baseline")

        local capped, why = M.topSpeedKph(fast, 200, 150)
        T.eq(capped, 150, "a class cap wins whenever it is lower -- a part may not buy past a ruleset")
        T.eq(why, "class", "and the answer says which rule decided")

        local generous = M.topSpeedKph(fast, 200, 400)
        T.ok(generous < 400, "a class cap that is higher than the machine does not RAISE it")
    end,

    top_speed_needs_an_authored_baseline_and_says_so_when_it_has_none = function(T)
        local M = H(T)
        -- The baseline is a SPECIFICATION from the catalogue, never a measurement. IDEA-328/331 draw that
        -- line explicitly, and a governor driven by an observation would cross it silently.
        T.eq(M.topSpeedKph(M.clear("v1"), nil, nil), nil, "no baseline, no ceiling -- not a guess")
        T.eq(M.topSpeedKph(nil, 200, nil), 200, "and a missing setup is inert rather than an error")
    end,

    a_family_that_cannot_be_felt_cannot_move_the_governor_either = function(T)
        local M = H(T)
        -- Asserted at load; stated here because the failure would be silent. A refused family quietly
        -- moving top speed would be a part that "does nothing" and secretly does something.
        for family in pairs(M.TOP_SPEED_TERMS) do
            T.ok(M.EXPRESSION[family], family .. " moves top speed and is also expressible")
            T.eq(M.REFUSED[family], nil, family .. " is not a refused family")
        end
    end,

    -- ------------------------------------------------------------------ the surface layer (L160)

    surface_is_a_named_layer_between_weather_and_thermal = function(T)
        local M = T.Core.get("parts.handling")
        local seen = {}
        for index, layer in ipairs(M.LAYERS) do seen[layer] = index end
        T.ok(seen.surface, "the road needs a layer of its own or it cannot be traced")
        T.ok(seen.weather < seen.surface, "the sky decides what the road is")
        T.ok(seen.surface < seen.thermal, "and the road decides what the tyre is working against")
    end,

    the_surface_contributor_pushes_cold_and_is_livelier_hot = function(T)
        local M, Th = T.Core.get("parts.handling"), T.Core.get("parts.thermal")
        for temp = -40, 120, 5 do
            local c = M.surfaceContributor(temp)
            T.ok(c.brakeScale <= 1.0, ("a %dC road must not add braking"):format(temp))
            T.ok(c.gripScale <= 1.0 + Th.SURFACE_HOT_LOOSE + 1e-9, ("a %dC road stays inside its bound"):format(temp))
        end
        T.ok(M.surfaceContributor(-10).gripScale < 1.0, "a freezing road pushes")
        T.ok(M.surfaceContributor(70).gripScale > 1.0, "a hot road is a little looser (L208)")
        T.ok(M.surfaceContributor(nil).gripScale == 1.0, "an unknown road is inert, not a penalty")
        T.ok(M.surfaceContributor(0 / 0).gripScale == 1.0, "and NaN is not a loophole")
    end,

    surface_and_thermal_are_separate_facts_on_one_carrier = function(T)
        local E = T.Core.get("machine.expression")
        T.ok(E.carrierFor("surface_grip") == "instance", "the road expresses through the live write")
        T.ok(E.carrierFor("tyre_thermal") == "instance", "so does the tyre")
        T.ok(E.carrierFor("surface_grip") == E.carrierFor("tyre_thermal"),
            "same carrier, because both are a live force scale")
        -- Two facts, not one. They are separate because they can disagree: a tyre in its window on a
        -- freezing road is a state the model must be able to represent.
        T.ok(E.FACTS.surface_grip ~= E.FACTS.tyre_thermal, "and they are distinct entries")
    end,

    -- ------------------------------------------------------------------ the governor (L162)

    the_target_rides_the_wire_only_when_it_exists = function(T)
        local M = T.Core.get("parts.handling")
        local setup = M.clear("v")
        local bare = M.wire(setup)
        T.ok(bare.levers.topSpeedKph == nil,
            "no target means UNGOVERNED -- absent, never a top speed of zero")
        setup.governedTopSpeedKph = 151.4
        local governed = M.wire(setup)
        T.ok(governed.levers.topSpeedKph == 151,
            "and a target is quantised to a whole km/h so it cannot republish on drift")
    end,

    a_governor_change_alone_must_republish = function(T)
        local M = T.Core.get("parts.handling")
        local a, b = M.clear("v"), M.clear("v")
        b.governedTopSpeedKph = 200
        -- `write()` suppresses an unchanged payload on this signature. If the target were missing from it,
        -- a car whose levers held still while its top speed moved would never be told.
        T.ok(M.signature(a) ~= M.signature(b), "the target belongs in the signature")
        local c = M.clear("v"); c.governedTopSpeedKph = 200
        T.ok(M.signature(b) == M.signature(c), "and equal targets still compare equal")
    end,

    every_authored_top_speed_is_a_plausible_car = function(T)
        local C = T.Core.get("data.vehicle_catalogue")
        local n = 0
        for _, record in ipairs(C.allRecords()) do
            local kph = C.topSpeedKph(record)
            if kph then
                n = n + 1
                T.ok(kph >= 120 and kph <= 400,
                    ("%s = %s km/h is outside anything a Night City car does"):format(record, tostring(kph)))
            end
        end
        T.ok(n >= 40, "the authored table covers the cars, not a handful of them")
        -- Base and `_player` are separate TweakDB records and must not disagree about the same car.
        for _, record in ipairs(C.allRecords()) do
            if record:find("_player$") then
                local base = record:gsub("_player$", "")
                local a, b = C.topSpeedKph(record), C.topSpeedKph(base)
                if a or b then
                    T.ok(a == b, ("%s and its base disagree (%s vs %s)"):format(record, tostring(a), tostring(b)))
                end
            end
        end
    end,

    an_unauthored_record_is_ungoverned_rather_than_capped = function(T)
        local C = T.Core.get("data.vehicle_catalogue")
        -- The bikes are deliberately absent. A guessed figure would be indistinguishable from a real one.
        T.ok(C.topSpeedKph("Vehicle.v_sportbike1_yaiba_kusanagi_tyger") == nil,
            "bikes are unconfirmed and must stay absent")
        T.ok(C.topSpeedKph("Vehicle.not_a_real_record") == nil, "and an unknown record is absent, not zero")
    end,

    -- ------------------------------------------------------------------ `L208`: weather, wet power, fuel
    full_wet_pushes_stops_long_and_loses_traction = function(T)
        local M = T.Core.get("parts.handling")
        local wet = M.weatherContributor(1.0, "rain")
        T.ok(near(wet.gripScale, 0.80) and near(wet.brakeScale, 0.82) and near(wet.driveScale, 0.90),
            "owner's 'noticeable': grip 0.80, brake 0.82, drive 0.90")
        local half = M.weatherContributor(0.5, "rain")
        T.ok(half.gripScale > wet.gripScale and half.gripScale < 1.0, "a drying road sits in between")
        T.ok(M.isInert(M.compose({ parts = {}, weather = M.weatherContributor(0, "sunny") })), "dry is inert")
    end,

    sandstorm_pushes_and_drags_fog_does_nothing = function(T)
        local M = T.Core.get("parts.handling")
        local sand = M.weatherContributor(0, "sandstorm")
        T.ok(near(sand.gripScale, 0.95) and near(sand.dragScale, 1.05), "sand: small push, more drag")
        local fog = M.weatherContributor(0, "fog")
        T.ok(near(fog.gripScale, 1.0) and fog.dragScale == nil, "fog is grip-neutral")
    end,

    wet_power_only_loosens_under_heavy_throttle_on_a_wet_road = function(T)
        local M = T.Core.get("parts.handling")
        T.eq(M.wetPowerGrip(0, 1.0), 1.0, "dry road: throttle changes nothing")
        T.eq(M.wetPowerGrip(1.0, 0.5), 1.0, "wet but part throttle: still the wet push")
        local full = M.wetPowerGrip(1.0, 1.0)
        T.ok(near(full, 1.0 + M.WET_POWER_LOOSE), "full wet, full throttle: lifted by WET_POWER_LOOSE")
        T.ok(M.weatherContributor(1.0).gripScale * full > 1.0, "which carries the wet car past 1.0: loose on power")
        T.eq(M.wetPowerGrip(0 / 0, 1.0), 1.0, "NaN is not a loophole")
    end,

    fuel_load_weighs_on_the_car_and_empty_is_inert = function(T)
        local M = T.Core.get("parts.handling")
        local empty = M.fuelContributor(0)
        T.ok(near(empty.driveScale, 1.0) and near(empty.gripScale, 1.0), "an empty tank changes nothing")
        local full = M.fuelContributor(60000, 1500)
        T.ok(full.driveScale < 0.93 and full.driveScale > 0.90, "full tank on 1,500 kg: ~8% less drive")
        T.ok(full.brakeScale < 0.93, "and ~8% less braking")
        T.ok(full.gripScale < 1.0 and full.gripScale > 0.96, "a slight push")
        T.ok(full.topSpeedScale < 1.0 and full.topSpeedScale > 0.98, "about 1% top speed")
        local setup = M.compose({ parts = {}, fuel = full })
        local seen = false
        for _, row in ipairs(setup.trace) do if row.layer == "fuel" then seen = true end end
        T.ok(seen, "fuel is a traced layer of its own")
    end,

    fuel_heats_and_wears_tyres_in_proportion_to_the_tank = function(T)
        local F = T.Core.get("economy.fuel")
        T.eq(F.heatFactor(0, 60000), 1.0, "empty: today's heating")
        T.ok(near(F.heatFactor(60000, 60000), 1.0 + F.HEAT_AT_FULL), "full: faster heating")
        T.ok(near(F.tyreWearFactor(30000, 60000), 1.0 + F.TYRE_WEAR_AT_FULL * 0.5), "half: half the extra wear")
    end,

    -- ------------------------------------------------------------------ `L209`: every weather is its own road
    every_weather_state_has_a_road_profile = function(T)
        local Th = T.Core.get("parts.thermal")
        for _, id in ipairs({ "sunny", "lightclouds", "cloudy", "heavyclouds", "rain", "fog", "pollution", "sandstorm" }) do
            T.ok(Th.WEATHER[id] ~= nil, id .. " must have its own profile, not fall to the default")
        end
    end,

    weather_combines_with_time_of_day = function(T)
        local Th = T.Core.get("parts.thermal")
        local afternoon, night = 15 * 3600, 3 * 3600
        local function track(w, s) return Th.trackTemperature({ weather = w, secondsOfDay = s }) end
        T.ok(track("sunny", afternoon) > track("heavyclouds", afternoon), "sun heats the road; cloud shades it")
        T.ok(track("heavyclouds", night) > track("sunny", night), "a clear night is colder than a clouded one")
        T.ok(track("sandstorm", afternoon) > track("fog", afternoon), "a hot dusty day beats a cold fog")
        T.ok(math.abs(track(nil, afternoon) - Th.trackTemperature({ secondsOfDay = afternoon })) < 1e-9,
            "no weather is the old model exactly")
    end,

    contamination_comes_from_the_weather_profile = function(T)
        local M = T.Core.get("parts.handling")
        local smog = M.weatherContributor(0, "pollution")
        T.ok(smog.gripScale < 1.0 and smog.gripScale > 0.95, "smog grime is a slight push")
        T.ok(M.weatherContributor(0, "sunny").gripScale == 1.0, "a clean dry road is untouched")
    end,
}
