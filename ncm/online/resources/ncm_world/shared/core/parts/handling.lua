-- ncm-core module: parts.handling
--
-- **The per-machine half of Parts.** `machine.projection` composes the RECORD channel -- drive-model flats,
-- per-record, spawn-cached, shared by every instance of that model on a client. This module composes the
-- INSTANCE channel: the live force interception proved in MASTER_TEST sections AU and AW and authorised by
-- `L148` / `L151` / `L152`.
--
-- `ncm_world/server/machine.lua` has said since it shipped that "when Parts arrive, their per-machine half
-- goes on the command carrier or it waits; it does not quietly get averaged into a record." This is that
-- half, and it no longer waits.
--
-- ---------------------------------------------------------------------------------------------------
-- WHY THIS IS THE CHANNEL THAT MAKES PARTS PERSONAL
-- ---------------------------------------------------------------------------------------------------
--
-- The instance channel writes to ONE BODY: the latched player vehicle, in that client's own physics step.
-- It is per-player by construction rather than by convention -- there is no shared record to collide over,
-- so two drivers in the same model with different engines feel different, which is the thing the record
-- channel cannot do at all.
--
-- Exactly three quantities have been driven and confirmed, and they are the whole vocabulary:
--
--   `gripScale`   force across travel             -- MASTER_TEST AU5
--   `driveScale`  force along travel, pushing     -- MASTER_TEST AW1
--   `brakeScale`  force along travel, retarding   -- MASTER_TEST AW2
--
-- ---------------------------------------------------------------------------------------------------
-- APPROXIMATION IS ALLOWED. CLAIMING A MECHANISM YOU DO NOT HAVE IS NOT. (`L154`)
-- ---------------------------------------------------------------------------------------------------
--
-- **The first version of this module refused nine of the twelve families outright, and that was wrong.**
-- It conflated two rules. The one worth keeping is *do not promise a felt effect a channel cannot carry*
-- (`IDEA-505`, 18_PARTS_ECOSYSTEM section 8.1). The one actually enforced was *do not express a family at
-- all unless a lever literally IS its quantity*, which is far stricter and defends nothing.
--
-- A stiffer suspension genuinely raises usable mechanical grip. A wing genuinely adds grip and genuinely
-- costs straight-line speed. A lighter shell genuinely accelerates, stops and turns better. Expressing
-- those through `gripScale` and `driveScale` is a **coarse model of a real effect**, not a fabrication.
-- The fabrication would be calling a suspension part "roll balance" when roll balance is a MOMENT and
-- section AW3 refuted the per-corner load entries with a mechanism.
--
-- So fidelity is a **property of an expression, not a gate on one**:
--
--   `direct`        the lever IS the family's quantity. Three families.
--   `approximated`  the family's real effect is modelled onto levers it does not literally own. Eight
--                   families. Every one carries a `rationale` (why it is physically defensible) and a
--                   `losses` list (what it provably cannot express). **`losses` is where the honesty went.**
--   (refused)       one family, `steering`, and for a mechanism rather than for squeamishness -- see below.
--
-- ---------------------------------------------------------------------------------------------------
-- HOW AN EFFECT REACHES A LEVER: `effect ^ weight`
-- ---------------------------------------------------------------------------------------------------
--
-- A family declares TERMS, each a lever and an exponent, and a part's `effect` is raised to that exponent:
--
--   weight  1.0   full coupling -- the direct families
--   weight  0.5   a real but partial coupling; a 1.44 gearbox delivers 1.20 to the road
--   weight -0.25  an INVERSE coupling; a 1.20 wing costs about 4.7% of drive force to drag
--
-- Exponents rather than multipliers, for one reason that matters: `a^w * b^w == (a*b)^w`, so two parts in
-- a family compose to the same place regardless of the order a Lua table iterates in, exactly as the direct
-- case does. An additive or blended rule would lose that and make a car depend on hash ordering.
--
-- **The topology is physics; the weights are a first pass.** Which lever a family touches, and in which
-- direction, is not a taste question -- drag opposes drive whatever anyone prefers. The exponents are
-- honest starting values awaiting play data, in the same spirit as `machine.projection`'s `WET` table, and
-- 18_PARTS_ECOSYSTEM puts component balance out of scope so no number here is a design judgement.
local Core = NcmCore

Core.define("parts.handling", function(C)
    local Ontology = C.get("parts.ontology")

    local M = { version = "0.0.2" }

    M.SETUP_VERSION = 1

    M.DIRECT = "direct"
    M.APPROXIMATED = "approximated"

    -- ---------------------------------------------------------------------------------------------
    -- The three levers
    -- ---------------------------------------------------------------------------------------------
    --
    -- `min` and `max` MIRROR THE CARRIER'S OWN CLAMPS (`vehicle/physics_probe.cpp`: `kGripScaleMin/Max`,
    -- `kDriveScaleMin/Max`, `kBrakeScaleMin/Max`). They are duplicated here on purpose rather than sent
    -- down from the plugin: the server must be able to tell a player "that setup would have been clamped"
    -- while composing. The carrier clamps again regardless -- it does not trust the wire, and should not.
    M.LEVERS = {
        gripScale = {
            id = "gripScale", quantity = "lateral_grip_vehicle",
            min = 0.30, max = 1.50, inert = 1.00,
            evidence = "MASTER_TEST AU5",
            note = "Force across travel. Below 1.0 is a wet road, not a slow car.",
        },
        driveScale = {
            id = "driveScale", quantity = "longitudinal_force_driving",
            min = 0.30, max = 2.00, inert = 1.00,
            evidence = "MASTER_TEST AW1",
            note = "Force along travel while it is PUSHING. Power delivery.",
        },
        brakeScale = {
            id = "brakeScale", quantity = "longitudinal_force_braking",
            min = 0.30, max = 2.00, inert = 1.00,
            evidence = "MASTER_TEST AW2",
            note = "Force along travel while it is RETARDING. Stopping ability.",
        },
    }

    -- Declared order, so a composed setup serialises identically every time. `pairs` over M.LEVERS would
    -- not, and a signature that changes without the value changing republishes for nothing.
    M.LEVER_IDS = { "gripScale", "driveScale", "brakeScale" }

    -- ---------------------------------------------------------------------------------------------
    -- The expression table -- eleven of twelve families reach a force
    -- ---------------------------------------------------------------------------------------------
    --
    -- `losses` is not documentation. It is the part of `IDEA-505` that survives once approximation is
    -- allowed: a family may be felt coarsely, but what it CANNOT express must be enumerated so that no
    -- design, panel or description promises it. Every entry below was written by asking "what would a
    -- player reasonably expect from this part that this will not deliver".
    M.EXPRESSION = {
        -- ----------------------------------------------------------------- direct: the lever IS the thing
        tires = {
            fidelity = M.DIRECT,
            terms = { { lever = "gripScale", weight = 1.0 } },
            rationale = "The contact patch is what the lateral force write scales. Nothing is modelled.",
            losses = { "per-corner compound or pressure (no per-corner channel -- AW3)",
                       "temperature and wear over a stint (no time dependence)",
                       "longitudinal versus lateral grip separately (one scale serves both)" },
        },
        power_unit = {
            fidelity = M.DIRECT,
            terms = { { lever = "driveScale", weight = 1.0 } },
            rationale = "Drive force along travel is what an engine produces. Nothing is modelled.",
            losses = { "the torque CURVE -- this is a flat multiplier at every rpm",
                       "peak power versus tractability, which are different parts of the same curve" },
        },
        brakes = {
            fidelity = M.DIRECT,
            terms = { { lever = "brakeScale", weight = 1.0 } },
            rationale = "Retarding force along travel is what a brake produces. Nothing is modelled.",
            losses = { "front/rear bias -- a MOMENT, refuted for this channel by AW3",
                       "fade over repeated stops (no time dependence)" },
        },

        -- ----------------------------------------------------------- approximated: real effect, coarse model
        suspension = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "gripScale", weight = 0.6 } },
            rationale = "Body control determines how much of the tyre's available grip a driver can "
                .. "actually use. Better damping and rate control is felt as grip, and expressing it as "
                .. "grip is coarse but not false.",
            losses = { "roll balance and anti-roll -- MOMENTS, refuted by AW3",
                       "bump versus rebound, and the difference between them",
                       "front/rear distribution -- the axis AV2 tested and closed",
                       "ride height and its aerodynamic consequences" },
        },
        aerodynamics = {
            fidelity = M.APPROXIMATED,
            -- Both signs at once, and this is the clearest case for exponents: a wing that adds grip must
            -- cost straight-line speed, or the part is a free lunch and the whole system is a joke.
            terms = { { lever = "gripScale", weight = 0.5 }, { lever = "driveScale", weight = -0.25 } },
            rationale = "Downforce raises grip and drag costs drive force. Both are real, both are "
                .. "reachable, and they pull in opposite directions -- which is the actual trade a wing "
                .. "makes.",
            losses = { "SPEED DEPENDENCE, which is the big one: real downforce and drag scale with v^2 "
                       .. "and this is constant at every speed",
                       "aero balance front/rear -- a MOMENT",
                       "drag as a function of yaw or slip angle" },
        },
        chassis = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "gripScale", weight = 0.4 },
                      { lever = "driveScale", weight = 0.4 },
                      { lever = "brakeScale", weight = 0.4 } },
            rationale = "Mass is the honest reading of a chassis part, and a lighter car accelerates, "
                .. "stops and corners better in the same proportion. Three levers because mass genuinely "
                .. "touches all three -- this is the family where the coarse model is closest to right.",
            losses = { "ACTUAL MASS -- total_mass at +0x1BC is a verified field we have chosen not to "
                       .. "write; this scales forces instead, which is not the same as scaring inertia",
                       "centre of gravity and weight distribution",
                       "polar moment -- how willingly the car changes direction" },
        },
        structure = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "gripScale", weight = 0.35 } },
            rationale = "Shell and subframe stiffness decide whether the suspension works against the "
                .. "road or against the car. Felt as grip and consistency.",
            losses = { "the same mass and inertia the chassis family cannot reach",
                       "torsional versus bending stiffness",
                       "crash structure, which is not a handling property at all" },
        },
        transmission = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.5 } },
            rationale = "Ratio choice and shift quality decide how much of the engine's torque reaches "
                .. "the road at a given moment. Felt as drive force.",
            losses = { "DISCRETE GEARS -- there is no ratio here, only a multiplier",
                       "shift time and the interruption it causes",
                       "the per-gear minimum-speed floor the owner's March 2026 work uncovered "
                       .. "(`IDEA-514`), which is a separate engine behaviour" },
        },
        drivetrain = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.5 } },
            rationale = "Driveline losses and how torque is delivered to the driven wheels. Felt as drive "
                .. "force reaching the road.",
            losses = { "differential LOCK, which acts by yaw and is therefore a MOMENT",
                       "front/rear torque split on all-wheel drive",
                       "which wheels are driven at all -- there is no per-corner channel (AW3)" },
        },
        cooling = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.3 } },
            rationale = "Thermal headroom is what lets an engine keep making its power. Felt as drive "
                .. "force, weakly, because on a cold lap it changes nothing.",
            losses = { "TIME DEPENDENCE, which is the entire point of cooling -- real cooling matters on "
                       .. "lap eight and this is a constant from the first metre",
                       "ambient temperature and weather coupling",
                       "derating, limp mode and failure" },
        },
        electrical = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.3 } },
            rationale = "Ignition, engine management and fuelling authority move real power. Felt as "
                .. "drive force.",
            losses = { "traction and stability control, which are MOMENTS and closed-loop besides",
                       "launch control and anything that acts on input (`KB-135`)",
                       "lighting, telemetry and every non-motive electrical system" },
        },
    }

    -- ---------------------------------------------------------------------------------------------
    -- The one refusal, and it is a mechanism rather than a preference
    -- ---------------------------------------------------------------------------------------------
    --
    -- Steering changes RESPONSE -- rack ratio, geometry, assistance -- and not the magnitude of any force
    -- the interception can reach. The nearest honest expression would be input authority, and `KB-135`
    -- records that throttle, brake and steer remain the driver's: `L148` did not authorise it and `L151`
    -- explicitly declined to. Mapping steering onto `gripScale` would be the fabrication this module
    -- exists to prevent -- a part that says "sharper turn-in" and delivers "more grip" is describing a
    -- mechanism it does not have.
    --
    -- Recorded as data rather than as an absence so a caller gets a reason instead of a nil.
    M.REFUSED = {
        steering = "steering changes response, not force magnitude; the only honest expression is input "
            .. "authority, which `KB-135` reserves to the driver and no decision line has authorised",
    }

    -- ---------------------------------------------------------------------------------------------
    -- Agreement with the ontology, asserted at load
    -- ---------------------------------------------------------------------------------------------
    --
    -- `parts.ontology.INSTANCE_QUANTITIES` is the periodic table's claim about what the live channel can
    -- do; this table is what actually gets written. **If they ever disagree, the ontology is lying to a
    -- designer**, which is precisely the failure `IDEA-505` exists to prevent -- so they are checked
    -- against each other here rather than kept in sync by hand. This assertion has already earned its
    -- keep once: `INSTANCE_QUANTITIES` named one family for a day after section AW proved three.
    local function quantitiesOf(family)
        local seen, out = {}, {}
        for _, term in ipairs(M.EXPRESSION[family].terms) do
            local q = M.LEVERS[term.lever].quantity
            if not seen[q] then seen[q] = true; out[#out + 1] = q end
        end
        table.sort(out)
        return out
    end

    for family, expression in pairs(M.EXPRESSION) do
        assert(Ontology.isFamily(family), "parts.handling expresses '" .. family
            .. "', which is not a family")
        assert(#expression.terms > 0, family .. " has no terms")
        assert(type(expression.rationale) == "string" and #expression.rationale > 0,
            family .. " must say why its expression is defensible")
        -- **An approximation with no stated losses is the dishonest kind.** A direct expression still
        -- declares them, because "direct" means the lever is the quantity, not that nothing is lost.
        assert(type(expression.losses) == "table" and #expression.losses > 0,
            family .. " must enumerate what it cannot express")
        for _, term in ipairs(expression.terms) do
            assert(M.LEVERS[term.lever], family .. " names unknown lever " .. tostring(term.lever))
            assert(type(term.weight) == "number" and term.weight == term.weight and term.weight ~= 0,
                family .. " has a malformed or zero weight for " .. term.lever)
        end

        local declared = Ontology.INSTANCE_QUANTITIES[family]
        assert(declared, "parts.handling expresses '" .. family
            .. "' but parts.ontology does not declare it expressible")
        local mine = quantitiesOf(family)
        local theirs = {}
        for _, q in ipairs(declared) do theirs[#theirs + 1] = q end
        table.sort(theirs)
        assert(#mine == #theirs, "parts.ontology and parts.handling disagree on how many quantities '"
            .. family .. "' reaches")
        for i = 1, #mine do
            assert(mine[i] == theirs[i], "parts.ontology and parts.handling disagree on '" .. family
                .. "': " .. theirs[i] .. " vs " .. mine[i])
        end
    end

    for family in pairs(Ontology.INSTANCE_QUANTITIES) do
        assert(M.EXPRESSION[family], "parts.ontology declares '" .. family
            .. "' expressible but parts.handling has no expression for it")
    end

    for family in pairs(M.REFUSED) do
        assert(Ontology.isFamily(family), "parts.handling refuses a non-family: " .. family)
        assert(not M.EXPRESSION[family], family .. " cannot be both expressed and refused")
        assert(not Ontology.INSTANCE_QUANTITIES[family],
            "parts.ontology declares '" .. family .. "' expressible but parts.handling refuses it")
    end

    -- Every family must have exactly one answer: an expression or a refusal. A family that is neither is
    -- a gap nobody would notice, which is how the ontology drifted the first time.
    for _, family in ipairs(Ontology.FAMILIES) do
        assert(M.EXPRESSION[family] or M.REFUSED[family],
            "family '" .. family .. "' has neither an instance expression nor a stated refusal")
    end

    -- ---------------------------------------------------------------------------------------------
    -- Composing
    -- ---------------------------------------------------------------------------------------------

    local function clampLever(lever, value)
        if value < lever.min then return lever.min, true end
        if value > lever.max then return lever.max, true end
        return value, false
    end

    --- How is this family felt live? Returns the expression table, or `nil, reason`.
    ---
    --- A plain question with a plain answer, so a caller never has to infer it from a nil -- and a refusal
    --- carries the mechanism rather than the word "no".
    function M.expressionFor(family)
        if type(family) ~= "string" then return nil, "family must be a string" end
        if not Ontology.isFamily(family) then return nil, "unknown family: " .. family end
        local expression = M.EXPRESSION[family]
        if expression then return expression end
        return nil, "family '" .. family .. "' cannot be expressed live: " .. M.REFUSED[family]
    end

    --- Backwards-compatible convenience: the FIRST lever a family touches, or nil with a reason. Kept
    --- because a caller that only wants to know "which dial does this move" should not have to walk terms.
    function M.leverFor(family)
        local expression, why = M.expressionFor(family)
        if not expression then return nil, why end
        return expression.terms[1].lever
    end

    --- Compose one driver's fitted parts into a setup for the carrier.
    ---
    --- `input` = {
    ---   vehicle = "<entity or record key>",     -- opaque here; the caller's own handle for the machine
    ---   parts = {
    ---     { id = "eng_stage2", family = "power_unit",   effect = 1.15 },
    ---     { id = "wing_gt",    family = "aerodynamics", effect = 1.20 },
    ---   },
    --- }
    ---
    --- Returns `setup` or `nil, reason`. A part naming a family with no live expression is a REFUSAL of
    --- the whole compose rather than a skipped row: silently dropping it is how a player pays for a
    --- component that does nothing and nobody finds out for a month.
    function M.compose(input, opts)
        opts = opts or {}
        if type(input) ~= "table" then return nil, "input must be a table" end
        local parts = input.parts
        if parts ~= nil and type(parts) ~= "table" then return nil, "parts must be a table" end
        parts = parts or {}

        local values, trace = {}, {}
        for _, id in ipairs(M.LEVER_IDS) do values[id] = M.LEVERS[id].inert end

        local approximated = 0
        for index, part in ipairs(parts) do
            local where = "parts[" .. index .. "]"
            if type(part) ~= "table" then return nil, where .. " must be a table" end

            local expression, why = M.expressionFor(part.family)
            if not expression then
                return nil, where .. " (" .. tostring(part.id) .. "): " .. why
            end

            local effect = part.effect
            if type(effect) ~= "number" or effect ~= effect or effect <= 0
                or effect == math.huge then
                return nil, where .. " (" .. tostring(part.id)
                    .. "): effect must be a finite positive multiplier, got " .. tostring(effect)
            end

            if expression.fidelity == M.APPROXIMATED then approximated = approximated + 1 end

            local applied = {}
            for _, term in ipairs(expression.terms) do
                -- `effect ^ weight`. A negative weight is an INVERSE coupling and is how a wing's drag
                -- costs drive force while its downforce adds grip, from the one number a part declares.
                local contribution = effect ^ term.weight
                values[term.lever] = values[term.lever] * contribution
                applied[#applied + 1] = { lever = term.lever, weight = term.weight, by = contribution }
            end

            trace[#trace + 1] = {
                part = part.id, family = part.family, effect = effect,
                fidelity = expression.fidelity, applied = applied,
            }
        end

        -- Clamp last, once, on the composed product -- not per part. Clamping each contribution would let
        -- three legal parts compose past the bound while every individual step looked fine.
        local levers, clamped = {}, {}
        for _, id in ipairs(M.LEVER_IDS) do
            local value, wasClamped = clampLever(M.LEVERS[id], values[id])
            levers[id] = value
            if wasClamped then
                clamped[#clamped + 1] = { lever = id, wanted = values[id], applied = value }
            end
        end

        return {
            v = M.SETUP_VERSION,
            at = opts.at,
            vehicle = input.vehicle,
            levers = levers,
            approximated = approximated,
            -- Server-side only. **`trace` is exactly what pushed `ncmProjections` over the state bag's
            -- size limit in KB-136**, so it exists for the log and the `wire()` form drops it.
            trace = trace,
            clamped = clamped,
        }
    end

    --- The inert setup: every lever at its no-op value. Distinct from "no setup at all", which leaves
    --- whatever was last applied in place. Sending this is how a driver's parts are REMOVED.
    function M.clear(vehicle, opts)
        opts = opts or {}
        local levers = {}
        for _, id in ipairs(M.LEVER_IDS) do levers[id] = M.LEVERS[id].inert end
        return {
            v = M.SETUP_VERSION, at = opts.at, vehicle = vehicle,
            levers = levers, approximated = 0, trace = {}, clamped = {},
        }
    end

    --- Does this setup change anything? Used to skip publishing a setup that would do nothing, and to tell
    --- an honest UI "your parts are fitted but none of them can be felt yet".
    function M.isInert(setup)
        if type(setup) ~= "table" or type(setup.levers) ~= "table" then return true end
        for _, id in ipairs(M.LEVER_IDS) do
            local lever = M.LEVERS[id]
            local value = setup.levers[id]
            if type(value) == "number" and math.abs(value - lever.inert) > 0.001 then return false end
        end
        return true
    end

    --- The wire form: what actually crosses to the client and down to the carrier. **Only what the plugin
    --- reads.** `trace` and `clamped` stay server-side -- the carrier never looks at them, and KB-136 is
    --- the standing evidence that shipping an audit trail to every client is how a transport dies.
    function M.wire(setup)
        if type(setup) ~= "table" or type(setup.levers) ~= "table" then return nil end
        local levers = {}
        for _, id in ipairs(M.LEVER_IDS) do
            local value = setup.levers[id]
            if type(value) == "number" then levers[id] = value end
        end
        return { v = setup.v or M.SETUP_VERSION, at = setup.at, levers = levers }
    end

    --- A stable signature for "has this setup changed". Built from the wire form, so a change to the trace
    --- alone does not republish, and built in declared lever order so it is deterministic.
    function M.signature(setup)
        if type(setup) ~= "table" or type(setup.levers) ~= "table" then return "none" end
        local out = {}
        for _, id in ipairs(M.LEVER_IDS) do
            out[#out + 1] = ("%s=%.4f"):format(id, setup.levers[id] or M.LEVERS[id].inert)
        end
        return table.concat(out, "|")
    end

    --- One human line, for the log and for a panel. Says what is being applied, how much of it is modelled
    --- rather than direct, and what was clamped.
    function M.explain(setup)
        if type(setup) ~= "table" or type(setup.levers) ~= "table" then return "no setup" end
        local out = {}
        for _, id in ipairs(M.LEVER_IDS) do
            local value = setup.levers[id] or M.LEVERS[id].inert
            if math.abs(value - M.LEVERS[id].inert) > 0.001 then
                out[#out + 1] = ("%s x%.3f"):format(id, value)
            end
        end
        if #out == 0 then return "inert" end
        local line = table.concat(out, ", ")
        if (setup.approximated or 0) > 0 then
            line = line .. (" [%d approximated]"):format(setup.approximated)
        end
        if setup.clamped and #setup.clamped > 0 then
            local c = {}
            for _, entry in ipairs(setup.clamped) do
                c[#c + 1] = ("%s wanted %.3f"):format(entry.lever, entry.wanted)
            end
            line = line .. " (CLAMPED: " .. table.concat(c, ", ") .. ")"
        end
        return line
    end

    --- What a part in this family will and will not do, as data rather than prose. **The call a panel or a
    --- component description should make before promising anything**, because `losses` is the list of
    --- things a player might reasonably expect and will not get.
    function M.describe(family)
        local expression, why = M.expressionFor(family)
        if not expression then return { family = family, expressible = false, reason = why } end
        local levers = {}
        for _, term in ipairs(expression.terms) do
            levers[#levers + 1] = {
                lever = term.lever, weight = term.weight,
                direction = term.weight > 0 and "increases" or "decreases",
                evidence = M.LEVERS[term.lever].evidence,
            }
        end
        return {
            family = family, expressible = true, fidelity = expression.fidelity,
            levers = levers, rationale = expression.rationale, losses = expression.losses,
        }
    end

    --- The whole periodic table, split by how honestly each family can be felt. A panel that wants to say
    --- "this part is modelled, not measured" reads this instead of hard-coding family names.
    function M.inventory()
        local direct, approximated, refused = {}, {}, {}
        for _, family in ipairs(Ontology.FAMILIES) do
            local expression = M.EXPRESSION[family]
            if not expression then
                refused[#refused + 1] = { family = family, reason = M.REFUSED[family] }
            elseif expression.fidelity == M.DIRECT then
                direct[#direct + 1] = M.describe(family)
            else
                approximated[#approximated + 1] = M.describe(family)
            end
        end
        return { direct = direct, approximated = approximated, refused = refused }
    end

    return M
end)
