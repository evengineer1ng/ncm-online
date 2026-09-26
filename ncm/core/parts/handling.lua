-- ncm-core module: parts.handling
--
-- **The per-machine half of Parts.** `machine.projection` composes the RECORD channel -- drive-model flats,
-- per-record, spawn-cached, shared by every instance of that model on a client. This module composes the
-- INSTANCE channel: the live force interception proved in MASTER_TEST sections AU and AW and authorised by
-- `L148` / `L151` / `L152`.
--
-- ---------------------------------------------------------------------------------------------------
-- THREE LEVERS IS A SPACE, NOT THREE SLOTS (`L156`)
-- ---------------------------------------------------------------------------------------------------
--
-- **The previous table gave four families the identical direction and varied only its length.**
-- `transmission`, `drivetrain`, `cooling` and `electrical` were all `driveScale` alone at 0.5, 0.5, 0.3 and
-- 0.3. A player fitting one could not possibly tell it from another, because there was nothing to tell
-- apart -- they were one dial with four labels. The word "approximated" was doing work the arithmetic was
-- not.
--
-- The error was treating the three levers as three SLOTS, one per family, so that a family's only freedom
-- was how hard it pushed. Three levers is a three-dimensional SPACE. A family is a **direction** in it, and
-- directions differ without needing any new channel, any new field, or any change to the carrier:
--
--   `transmission`  (0, +0.50, +0.20)   shorter ratios multiply torque BOTH ways -- engine braking is real
--   `drivetrain`    (-0.15, +0.55, 0)   a tighter diff puts power down and costs you turn-in
--
-- Same lever, same magnitude, opposite character: one helps you stop, the other costs you grip. That is a
-- difference a driver feels in a corner, and it costs nothing to ship.
--
-- Two couplings that had simply been missed, both ordinary vehicle dynamics:
--
--   * **Braking force is grip-limited.** The old table had `tires` not touching `brakeScale` at all, which
--     is not a simplification, it is wrong. Tyres are most of a stopping distance.
--   * **Drag helps you stop.** `aerodynamics` took drive force and gave grip; it should also give brake,
--     because the same drag that costs top end is retarding the car under braking.
--
-- ---------------------------------------------------------------------------------------------------
-- HOW AN EFFECT REACHES A LEVER: `effect ^ weight`
-- ---------------------------------------------------------------------------------------------------
--
-- A family declares TERMS, each a lever and an exponent, and a part's `effect` is raised to that exponent:
--
--   weight  1.0   full coupling -- the family's own quantity
--   weight  0.5   a real but partial coupling; a 1.44 gearbox delivers 1.20 to the road
--   weight -0.25  an INVERSE coupling; a 1.20 wing costs about 4.7% of drive force to drag
--
-- Exponents rather than multipliers, for one reason that matters: `a^w * b^w == (a*b)^w`, so two parts in
-- a family compose to the same place regardless of the order a Lua table iterates in. An additive or
-- blended rule would lose that and make a car depend on hash ordering.
--
-- `fidelity` describes the family's FIRST term -- its own quantity. Secondary terms are couplings and are
-- always modelled, whatever the primary fidelity says. `tires` is direct because the lateral force write
-- IS the contact patch; its `brakeScale` term is a model of grip-limited braking.
--
-- ---------------------------------------------------------------------------------------------------
-- COUPLINGS: the levers constrain each other (`L156`)
-- ---------------------------------------------------------------------------------------------------
--
-- The second half of the same idea, and the half that makes a car a car rather than a menu. After parts
-- compose, the levers are not independent: **drive force the tyres cannot carry is not delivered, and a
-- car cannot out-brake its grip.** So `M.COUPLINGS` caps drive and brake against the composed grip.
--
-- The consequence is emergent and is the point: fit a 2.0 engine to stock rubber and it delivers 1.30, not
-- 2.00, reported and named. Fit tyres and the same engine delivers more. Parts stop being independent
-- scalars and start being a build, out of three floats and no new plumbing.
--
-- A ceiling only ever REDUCES. Fitting tyres never invents drive force nobody asked for -- the cap rises,
-- but the value still comes from the parts. A rule that could push a lever up would be a buff wearing a
-- physics costume.
--
-- **The topology is physics; the coefficients are a first pass.** Which lever a family touches, and in
-- which direction, is not a taste question -- drag opposes drive whatever anyone prefers. The exponents
-- and the ceiling coefficients are honest starting values awaiting play data, in the same spirit as
-- `machine.projection`'s `WET` table, and 18_PARTS_ECOSYSTEM puts component balance out of scope so no
-- number here is a design judgement.
local Core = NcmCore

Core.define("parts.handling", function(C)
    local Ontology = C.get("parts.ontology")
    local Expression = C.get("machine.expression")
    local Thermal = C.get("parts.thermal")

    local M = { version = "0.0.3" }

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
    -- CONTRIBUTORS: the same layer vocabulary the record carrier already uses (`L158`)
    -- ---------------------------------------------------------------------------------------------
    --
    -- `machine.projection` has had `LAYERS = { factory, parts, wear, weather, chrome, ruleset }` since it
    -- shipped, with a `contribute()` that writes down every movement of every number. The instance carrier
    -- gets the same vocabulary rather than a parallel one, so a reader who understands one channel
    -- understands both, and so that **`chrome` is a named layer here from the first day** -- which is the
    -- whole of the chrome-hack onramp. A quickhack that degrades a rival's grip is not a new mechanism; it
    -- is a contributor with a different source, and it costs nothing today to leave the socket in.
    --
    -- Order is declared, not iterated, because `pairs` is not deterministic and a setup that serialises
    -- differently on two runs would republish for nothing.
    M.LAYERS = { "parts", "wear", "weather", "thermal", "chrome", "ruleset" }

    --- Contributors other than `parts` supply plain per-lever multipliers. They are quantised before they
    --- reach a lever, and that is load-bearing rather than tidy: `signature()` formats at `%.4f` and
    --- `server/handling.lua` suppresses an unchanged payload on it, so a continuously varying thermal term
    --- would republish the state bag twice a second per driver forever. The comment at
    --- `server/handling.lua` records that exact defect already happening once.
    M.CONTRIBUTOR_QUANTUM = 0.01

    local function quantise(v)
        return math.floor(v / M.CONTRIBUTOR_QUANTUM + 0.5) * M.CONTRIBUTOR_QUANTUM
    end

    -- ---------------------------------------------------------------------------------------------
    -- TOP SPEED: composed here, delivered by a different carrier (`L157`)
    -- ---------------------------------------------------------------------------------------------
    --
    -- **Top speed is not a physics problem on this platform. It is an authored number per car.** It leaves
    -- by the `ceiling` carrier -- `Open77.vehicles.setPerformance` -- not by the force write, so it is not
    -- a lever and deliberately does not live in `M.LEVERS`. Composing it here anyway keeps one place where
    -- a part's consequences are worked out.
    --
    -- The scale multiplies an authored baseline from `data.vehicle_catalogue`. Clamped tight: a governor
    -- that can double a car's top speed is not a governor, and the platform's own rule is that the ceiling
    -- withholds rather than adds -- raising this lifts a cap NCM imposed, it never adds force.
    --
    -- **Unproven live as of 2026-09-26.** MASTER_TEST section BA is the capability spike; nothing in NCM
    -- had ever successfully capped a top speed when this was written.
    M.TOP_SPEED = {
        min = 0.80, max = 1.25, inert = 1.00,
        fact = "top_speed_cap",
        note = "Multiplies the catalogue's authored topSpeedKph. Delivered by the ceiling carrier.",
    }

    --- Which families move top speed, and by how much. Separate from `EXPRESSION` because these do not
    --- reach a lever at all -- conflating them would put a `ceiling` fact in a table of `instance` facts,
    --- which is exactly what `machine.expression` exists to prevent.
    --
    -- **Two of the four are NEGATIVE, and that is the interesting half.** A wing and a short gearbox are
    -- both things a driver fits to go FASTER, and both cost top speed -- the first to drag, the second
    -- because torque multiplication and terminal velocity are the same trade seen from two ends. A table
    -- where every part raised every number would be a menu again.
    M.TOP_SPEED_TERMS = {
        aerodynamics = -0.35,  -- drag sets terminal velocity; the largest single influence, and it opposes
        transmission = -0.10,  -- shorter gearing multiplies torque and brings the rev limit down the road
        power_unit   =  0.20,  -- more power carries a car further up its own drag curve
        chassis      =  0.08,  -- a lighter car sheds a little rolling resistance; smallest of the four
    }

    -- ---------------------------------------------------------------------------------------------
    -- The expression table -- eleven families, eleven DIRECTIONS
    -- ---------------------------------------------------------------------------------------------
    --
    -- `losses` is not documentation. It is the part of `IDEA-505` that survives once approximation is
    -- allowed: a family may be felt coarsely, but what it CANNOT express must be enumerated so that no
    -- design, panel or description promises it.
    --
    -- **Two losses recur and are the honest ceiling of this whole channel**, because a lever is a CONSTANT:
    -- no speed dependence (a wing works identically in a car park and at 200) and no time dependence
    -- (nothing heats, fades or wears). `IDEA-532` records the state-dependent design that would lift them.
    M.EXPRESSION = {
        -- ----------------------------------------------------------------- direct: the lever IS the thing
        tires = {
            fidelity = M.DIRECT,
            terms = { { lever = "gripScale", weight = 1.0 },
                      { lever = "brakeScale", weight = 0.45 },
                      { lever = "driveScale", weight = 0.15 } },
            rationale = "The contact patch is what the lateral force write scales, directly. It also "
                .. "reaches the other two because braking force is GRIP-LIMITED -- tyres are most of a "
                .. "stopping distance -- and because power that cannot be put down is not power. A tyre "
                .. "that changed only cornering would be the wrong model, not a simple one.",
            losses = { "per-corner compound or pressure (no per-corner channel -- AW3)",
                       "temperature and wear over a stint (no time dependence)",
                       "a tyre strong laterally and weak longitudinally, or the reverse -- one `effect` "
                       .. "drives all three terms in fixed proportion" },
        },
        power_unit = {
            fidelity = M.DIRECT,
            terms = { { lever = "driveScale", weight = 1.0 },
                      { lever = "gripScale", weight = -0.10 } },
            rationale = "Drive force along travel is what an engine produces, directly. The small grip "
                .. "penalty is mass over an axle: a bigger engine is heavier and the weight lands where "
                .. "the cornering is done, so power is a trade rather than a gift.",
            losses = { "the torque CURVE -- this is a flat multiplier at every rpm",
                       "peak power versus tractability, which are different parts of the same curve",
                       "where the mass actually sits -- front, mid or rear is a distribution, and this "
                       .. "channel has one number for the whole car" },
        },
        brakes = {
            fidelity = M.DIRECT,
            terms = { { lever = "brakeScale", weight = 1.0 } },
            rationale = "Retarding force along travel is what a brake produces. The one family with a "
                .. "genuinely pure direction -- a brake package does not help a car corner or accelerate.",
            losses = { "front/rear bias -- a MOMENT, refuted for this channel by AW3",
                       "fade over repeated stops (no time dependence)",
                       "the grip ceiling is not a brake property -- a bigger disc cannot beat the tyre, "
                       .. "which is why `brake_grip_limit` exists" },
        },

        -- --------------------------------------------------- approximated: real effect, coarse model
        suspension = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "gripScale", weight = 0.55 },
                      { lever = "brakeScale", weight = 0.25 },
                      { lever = "driveScale", weight = 0.10 } },
            rationale = "Body control determines how much of the tyre's available grip a driver can "
                .. "actually use. It reaches braking more than it reaches power because that is where "
                .. "weight transfer is violent, and a car that dives has stopped using its rear axle.",
            losses = { "roll balance and anti-roll -- MOMENTS, refuted by AW3",
                       "bump versus rebound, and the difference between them",
                       "front/rear distribution -- the axis AV2 tested and closed",
                       "LOAD DEPENDENCE, which is the real mechanism: a soft car gives up progressively "
                       .. "as it is leaned on, and this gives the same number at every cornering load" },
        },
        aerodynamics = {
            fidelity = M.APPROXIMATED,
            -- Three signs at once, and the clearest case for exponents: a wing that adds grip must cost
            -- straight-line speed, or the part is a free lunch and the whole system is a joke. The brake
            -- term is the half originally missed -- drag retards the car whether or not anyone wanted it.
            terms = { { lever = "gripScale", weight = 0.50 },
                      { lever = "driveScale", weight = -0.25 },
                      { lever = "brakeScale", weight = 0.15 } },
            rationale = "Downforce raises grip, drag costs drive force, and the same drag shortens a stop. "
                .. "All three are real, all three are reachable, and the first two pull in opposite "
                .. "directions -- which is the actual trade a wing makes.",
            losses = { "SPEED DEPENDENCE, which is the big one: real downforce and drag scale with v^2 "
                       .. "and this is constant at every speed, so a wing works in a car park",
                       "aero balance front/rear -- a MOMENT",
                       "drag as a function of yaw or slip angle" },
        },
        chassis = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "gripScale", weight = 0.40 },
                      { lever = "driveScale", weight = 0.40 },
                      { lever = "brakeScale", weight = 0.40 } },
            rationale = "Mass is the honest reading of a chassis part, and a lighter car accelerates, "
                .. "stops and corners better in the same proportion. The one family whose direction is "
                .. "legitimately equal on all three, because inertia does not care which way a car goes.",
            losses = { "ACTUAL MASS -- total_mass at +0x1BC is a verified field we have chosen not to "
                       .. "write; this scales forces instead, which is not the same as changing inertia",
                       "centre of gravity and weight distribution",
                       "polar moment -- how willingly the car changes direction" },
        },
        structure = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "gripScale", weight = 0.35 },
                      { lever = "brakeScale", weight = 0.10 } },
            rationale = "Shell and subframe stiffness decide whether the suspension works against the "
                .. "road or against the car. Felt as grip, and as consistency under the heaviest loads, "
                .. "which is why it leans towards braking rather than power.",
            losses = { "the same mass and inertia the chassis family cannot reach",
                       "torsional versus bending stiffness",
                       "crash structure, which is not a handling property at all",
                       "its real mechanism -- stiffness makes the SUSPENSION work, so it should modify "
                       .. "another family rather than the levers directly (`IDEA-533`)" },
        },
        transmission = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.50 },
                      { lever = "brakeScale", weight = 0.20 } },
            rationale = "Ratio choice decides how much of the engine's torque reaches the road -- and it "
                .. "multiplies torque in BOTH directions, so shorter gearing is also engine braking on "
                .. "the overrun. That second term is what makes a gearbox not an engine.",
            losses = { "DISCRETE GEARS -- there is no ratio here, only a multiplier, so nothing steps",
                       "shift time and the interruption it causes",
                       "the per-gear minimum-speed floor the owner's March 2026 work uncovered "
                       .. "(`IDEA-514`), which is a separate engine behaviour" },
        },
        drivetrain = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.55 },
                      { lever = "gripScale", weight = -0.15 } },
            rationale = "Driveline losses and how torque is delivered to the driven wheels. A tighter, "
                .. "more locked driveline puts power down better and costs turn-in -- the classic trade, "
                .. "and what separates this family from `transmission`, which it used to be a copy of.",
            losses = { "differential LOCK as a mechanism -- it acts by yaw and is therefore a MOMENT; "
                       .. "the grip penalty here is its consequence, coarsely, not the thing itself",
                       "front/rear torque split on all-wheel drive",
                       "which wheels are driven at all -- there is no per-corner channel (AW3)",
                       "lock on power versus on overrun, which are separate ramps on a real diff" },
        },
        cooling = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.30 },
                      { lever = "brakeScale", weight = 0.25 } },
            rationale = "Thermal headroom is what lets an engine keep making its power -- and a cooling "
                .. "package is ducting, which feeds the brakes as well as the radiator. The brake term is "
                .. "the only thing distinguishing this from `electrical` on a constant channel, and it is "
                .. "a thin distinction honestly held rather than a strong one.",
            losses = { "TIME DEPENDENCE, which is the entire point of cooling -- real cooling matters on "
                       .. "lap eight and this is a constant from the first metre. This family is the "
                       .. "weakest fit in the table, and `IDEA-532` is what would fix it",
                       "ambient temperature and weather coupling",
                       "derating, limp mode and failure" },
        },
        electrical = {
            fidelity = M.APPROXIMATED,
            terms = { { lever = "driveScale", weight = 0.35 } },
            rationale = "Ignition, engine management and fuelling authority move real power. The one "
                .. "family that is honestly pure drive force, which is why it is the baseline the others "
                .. "are distinguished FROM rather than a fourth copy of it.",
            losses = { "traction and stability control, which are MOMENTS and closed-loop besides",
                       "launch control and anything that acts on input (`KB-135`)",
                       "RESPONSE, which is its real mechanism -- a poor system is slow to deliver rather "
                       .. "than weak, and a constant lever cannot express a delay (`IDEA-532`)",
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
    M.REFUSED = {
        steering = "steering changes response, not force magnitude; the only honest expression is input "
            .. "authority, which `KB-135` reserves to the driver and no decision line has authorised",
    }

    -- ---------------------------------------------------------------------------------------------
    -- Couplings: what one lever does to another (`L156`)
    -- ---------------------------------------------------------------------------------------------
    --
    -- Applied AFTER parts compose and only ever downward. `ceiling = base + slope * <source lever>`, a
    -- straight line because nothing here is calibrated well enough to justify a curve, and a straight line
    -- is legible to a player reading a chat message.
    --
    -- At inert grip (1.00) the ceilings are drive 1.30 and brake 1.20. At the grip clamp (1.50) they are
    -- 1.70 and 1.60. So a stock-tyred car absorbs a modest engine and no more, and every further increment
    -- of power has to be BOUGHT with grip. That is the intended shape of the build; the coefficients
    -- themselves are a first pass and out of scope for balance.
    M.COUPLINGS = {
        {
            id = "traction_ceiling",
            lever = "driveScale", from = "gripScale",
            base = 0.50, slope = 0.80,
            headline = "power that cannot be put down is not power",
            rationale = "Drive force is transmitted through the same contact patch that carries "
                .. "cornering load. A big engine on stock rubber does not accelerate harder, it spins.",
            advice = "fit tyres, or anything that raises grip, to lift this ceiling",
        },
        {
            id = "brake_grip_limit",
            lever = "brakeScale", from = "gripScale",
            base = 0.40, slope = 0.80,
            headline = "a car cannot out-brake its tyres",
            rationale = "Deceleration is grip-limited long before it is brake-limited. Past the tyre's "
                .. "capability a larger brake changes how quickly it locks up, not how quickly it stops.",
            advice = "fit tyres to lift this ceiling; a bigger brake alone will not",
        },
    }

    --- The ceiling a coupling imposes given the levers it reads. Exposed so a panel can show HEADROOM --
    --- "this engine is worth 1.30 of 2.00 until tyres are fitted" -- rather than only reporting the loss
    --- after a player has already spent the money.
    function M.ceilingFor(coupling, levers)
        local source = levers[coupling.from]
        if type(source) ~= "number" then return nil end
        return coupling.base + coupling.slope * source
    end

    --- Every ceiling currently in force, as data. `{ driveScale = 1.30, brakeScale = 1.20 }`.
    function M.ceilings(levers)
        local out = {}
        for _, coupling in ipairs(M.COUPLINGS) do
            local ceiling = M.ceilingFor(coupling, levers or {})
            if ceiling then
                local existing = out[coupling.lever]
                out[coupling.lever] = existing and math.min(existing, ceiling) or ceiling
            end
        end
        return out
    end

    -- ---------------------------------------------------------------------------------------------
    -- Agreement with the ontology, asserted at load
    -- ---------------------------------------------------------------------------------------------
    --
    -- `parts.ontology.INSTANCE_QUANTITIES` is the periodic table's claim about what the live channel can
    -- do; this table is what actually gets written. **If they ever disagree, the ontology is lying to a
    -- designer**, which is precisely the failure `IDEA-505` exists to prevent -- so they are checked
    -- against each other here rather than kept in sync by hand. This assertion has already earned its
    -- keep twice: once when `INSTANCE_QUANTITIES` named one family for a day after section AW proved
    -- three, and again when `L156` widened nine families from one lever to two or three.
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
        local seenLever = {}
        for _, term in ipairs(expression.terms) do
            assert(M.LEVERS[term.lever], family .. " names unknown lever " .. tostring(term.lever))
            assert(not seenLever[term.lever],
                family .. " names " .. term.lever .. " twice; fold them into one weight")
            seenLever[term.lever] = true
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

    -- **Every fact this module expresses belongs to the instance carrier, checked statically (`L158`).**
    -- `machine.projection`'s `claim()` cannot do this job: it is per-draft, and the two composers never
    -- share a draft. This is the guard that catches `IDEA-508` -- the day the two dead weather flats
    -- resolve again, wet grip would otherwise be applied on both carriers at once.
    Expression.assertOwns("instance", {
        "grip_magnitude", "brake_magnitude", "drive_magnitude", "tyre_thermal", "aerodynamic_drag",
    }, "parts.handling")
    -- And top speed is emphatically NOT ours to write as a force. We compose the number; the ceiling
    -- carrier delivers it.
    assert(Expression.carrierFor(M.TOP_SPEED.fact) == "ceiling",
        "parts.handling composes top speed but it must be delivered by the ceiling carrier")

    for family in pairs(M.TOP_SPEED_TERMS) do
        assert(Ontology.isFamily(family),
            "parts.handling gives top speed to '" .. family .. "', which is not a family")
        assert(M.EXPRESSION[family],
            "'" .. family .. "' moves top speed but has no live expression; a family that cannot be felt "
            .. "must not silently move a governor either")
    end

    for _, coupling in ipairs(M.COUPLINGS) do
        assert(M.LEVERS[coupling.lever], "coupling " .. coupling.id .. " caps an unknown lever")
        assert(M.LEVERS[coupling.from], "coupling " .. coupling.id .. " reads an unknown lever")
        assert(coupling.lever ~= coupling.from, coupling.id .. " cannot cap itself")
        -- A ceiling that can fall below the capped lever's own floor would fight the clamp and win,
        -- leaving a value neither rule asked for. Checked at the source lever's minimum: the worst case.
        local worst = coupling.base + coupling.slope * M.LEVERS[coupling.from].min
        assert(worst >= M.LEVERS[coupling.lever].min,
            coupling.id .. " can drive " .. coupling.lever .. " below its own floor")
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
    function M.expressionFor(family)
        if type(family) ~= "string" then return nil, "family must be a string" end
        if not Ontology.isFamily(family) then return nil, "unknown family: " .. family end
        local expression = M.EXPRESSION[family]
        if expression then return expression end
        return nil, "family '" .. family .. "' cannot be expressed live: " .. M.REFUSED[family]
    end

    --- Backwards-compatible convenience: the family's PRIMARY lever -- its own quantity, the first term.
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
        local topSpeedScale = M.TOP_SPEED.inert

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

            -- Top speed rides the same `effect`, on its own exponent, and leaves by a different carrier.
            local topTerm = M.TOP_SPEED_TERMS[part.family]
            if topTerm then topSpeedScale = topSpeedScale * (effect ^ topTerm) end

            trace[#trace + 1] = {
                part = part.id, family = part.family, effect = effect,
                fidelity = expression.fidelity, applied = applied,
                topSpeed = topTerm and (effect ^ topTerm) or nil,
            }
        end

        -- ----------------------------------------------------------------- the other contributors
        --
        -- Applied after parts and before the clamp, multiplicatively, so the whole composition stays
        -- order-independent. Each one is traced even when it is INERT: a contributor that returns exactly
        -- 1.0 is otherwise indistinguishable from a contributor nobody wired up, and that is the
        -- `IDEA-516` failure -- a message composed correctly, pushed correctly, and heard by nobody.
        for _, layer in ipairs(M.LAYERS) do
            if layer ~= "parts" then
                local supplied = input[layer]
                if supplied ~= nil then
                    if type(supplied) ~= "table" then
                        return nil, layer .. " contributor must be a table"
                    end
                    for _, id in ipairs(M.LEVER_IDS) do
                        local raw = supplied[id]
                        if raw ~= nil then
                            if type(raw) ~= "number" or raw ~= raw or raw <= 0 or raw == math.huge then
                                return nil, ("%s.%s must be a finite positive multiplier, got %s")
                                    :format(layer, id, tostring(raw))
                            end
                            local m = quantise(raw)
                            values[id] = values[id] * m
                            trace[#trace + 1] = {
                                layer = layer, lever = id, by = supplied.source or layer,
                                multiplier = m, inert = (math.abs(m - 1.0) < 1e-9),
                            }
                        end
                    end
                    if type(supplied.topSpeedScale) == "number" and supplied.topSpeedScale > 0 then
                        topSpeedScale = topSpeedScale * supplied.topSpeedScale
                    end
                end
            end
        end

        -- Clamp once, on the composed product -- not per part. Clamping each contribution would let three
        -- legal parts compose past the bound while every individual step looked fine.
        --
        -- This runs BEFORE the couplings so a ceiling is computed from the value that will actually be
        -- applied rather than from an unreachable one. `gripScale`, the only source lever, takes no
        -- ceiling itself, so nothing here can be invalidated by what follows.
        local levers, clamped = {}, {}
        for _, id in ipairs(M.LEVER_IDS) do
            local value, wasClamped = clampLever(M.LEVERS[id], values[id])
            levers[id] = value
            if wasClamped then
                clamped[#clamped + 1] = { lever = id, wanted = values[id], applied = value }
            end
        end

        -- ----------------------------------------------------------------- the couplings (`L156`)
        --
        -- Downward only. A coupling that could RAISE a lever would be inventing force no part paid for,
        -- which is a buff in a physics costume -- so `math.min` and never `math.max`.
        local limited = {}
        for _, coupling in ipairs(M.COUPLINGS) do
            local ceiling = M.ceilingFor(coupling, levers)
            if ceiling and levers[coupling.lever] > ceiling then
                limited[#limited + 1] = {
                    coupling = coupling.id, lever = coupling.lever,
                    wanted = levers[coupling.lever], applied = ceiling,
                    from = coupling.from, fromValue = levers[coupling.from],
                    headline = coupling.headline, advice = coupling.advice,
                }
                levers[coupling.lever] = ceiling
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
            limited = limited,
            -- Not a lever. Leaves by the `ceiling` carrier; `wire()` drops it, because the Carrier plugin
            -- has no business with a governor the platform applies.
            topSpeedScale = (function()
                local v = topSpeedScale
                if v < M.TOP_SPEED.min then return M.TOP_SPEED.min end
                if v > M.TOP_SPEED.max then return M.TOP_SPEED.max end
                return v
            end)(),
        }
    end

    --- The absolute ceiling for a Machine, in km/h, or nil when NCM sets none.
    ---
    --- `baselineKph` is the catalogue's AUTHORED number -- a specification. It is never a measurement:
    --- `IDEA-328`/`IDEA-331` draw that line explicitly ("highest observed" is evidence; "top speed" is a
    --- claim), and a governor driven by an observation would convert one into the other silently.
    ---
    --- `classCapKph` wins whenever it is lower. A ruleset is the reason a class exists and a part may not
    --- buy its way past one -- the same most-restrictive-wins rule `machine.projection` already applies.
    function M.topSpeedKph(setup, baselineKph, classCapKph)
        local baseline = tonumber(baselineKph)
        local scale = (type(setup) == "table" and tonumber(setup.topSpeedScale)) or M.TOP_SPEED.inert
        local out = baseline and (baseline * scale) or nil
        local cap = tonumber(classCapKph)
        if cap and cap > 0 and (not out or cap < out) then return cap, "class" end
        if not out then return nil end
        return out, "machine"
    end

    --- The inert setup: every lever at its no-op value. Distinct from "no setup at all", which leaves
    --- whatever was last applied in place. Sending this is how a driver's parts are REMOVED.
    function M.clear(vehicle, opts)
        opts = opts or {}
        local levers = {}
        for _, id in ipairs(M.LEVER_IDS) do levers[id] = M.LEVERS[id].inert end
        return {
            v = M.SETUP_VERSION, at = opts.at, vehicle = vehicle,
            levers = levers, approximated = 0, trace = {}, clamped = {}, limited = {},
            topSpeedScale = M.TOP_SPEED.inert,
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
    --- reads.** `trace`, `clamped` and `limited` stay server-side -- the carrier never looks at them, and
    --- KB-136 is the standing evidence that shipping an audit trail to every client is how a transport dies.
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
    --- rather than direct, what was clamped, and -- the `L156` addition -- what a coupling took back.
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
        if setup.limited and #setup.limited > 0 then
            local l = {}
            for _, entry in ipairs(setup.limited) do
                l[#l + 1] = ("%s %.3f -> %.3f by %s"):format(
                    entry.lever, entry.wanted, entry.applied, entry.coupling)
            end
            line = line .. " (LIMITED: " .. table.concat(l, ", ") .. ")"
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
        for index, term in ipairs(expression.terms) do
            levers[#levers + 1] = {
                lever = term.lever, weight = term.weight,
                direction = term.weight > 0 and "increases" or "decreases",
                role = index == 1 and "primary" or "coupling",
                evidence = M.LEVERS[term.lever].evidence,
            }
        end
        -- Which ceilings can bite a part in this family, so a description can warn BEFORE the purchase
        -- rather than explain afterwards.
        local constrainedBy = {}
        for _, coupling in ipairs(M.COUPLINGS) do
            for _, term in ipairs(expression.terms) do
                if term.lever == coupling.lever and term.weight > 0 then
                    constrainedBy[#constrainedBy + 1] = {
                        coupling = coupling.id, lever = coupling.lever, from = coupling.from,
                        headline = coupling.headline, advice = coupling.advice,
                    }
                    break
                end
            end
        end
        return {
            family = family, expressible = true, fidelity = expression.fidelity,
            levers = levers, rationale = expression.rationale, losses = expression.losses,
            constrainedBy = constrainedBy,
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

    --- The DIRECTION a family points, normalised so its largest term is 1. Two families with the same
    --- direction are the same part wearing two names, whatever their magnitudes -- which is exactly what
    --- `transmission`, `drivetrain`, `cooling` and `electrical` were before `L156`. Exposed rather than
    --- kept in the test so a designer adding a family can check it against the ones already there.
    function M.direction(family)
        local expression = M.EXPRESSION[family]
        if not expression then return nil end
        local largest = 0
        for _, term in ipairs(expression.terms) do
            if math.abs(term.weight) > largest then largest = math.abs(term.weight) end
        end
        if largest == 0 then return nil end
        local out = {}
        for _, id in ipairs(M.LEVER_IDS) do out[id] = 0 end
        for _, term in ipairs(expression.terms) do out[term.lever] = term.weight / largest end
        return out
    end

    --- Build the `thermal` contributor from a tyre temperature (`L159`).
    ---
    --- **It touches grip AND brake directly, and that is a correction.** An earlier draft assumed a reduced
    --- `gripScale` would propagate into braking and power through the `L156` couplings. It does not: at
    --- `gripScale = 0.85` the ceilings are 1.18 and 1.08, and a stock car sits at 1.00 on both, so neither
    --- bites. The couplings are still right; they were simply never the propagation mechanism.
    ---
    --- Downward-only, so it withholds and never adds -- a cold tyre costs grip, a tyre in the window is
    --- merely not being charged for one.
    function M.thermalContributor(temperatureC)
        local m = Thermal.gripMultiplier(temperatureC)
        if type(m) ~= "number" or m ~= m then m = 1.0 end
        if m > 1.0 then m = 1.0 end
        return {
            source = "tyre_thermal",
            gripScale = m,
            brakeScale = m,
        }
    end

    --- Build the `weather` contributor from a wetness in 0..1 (`L158`).
    ---
    --- **Grip magnitude moved here from the record carrier**, because two of `machine.projection`'s four
    --- `WET` entries write to flats `KB-145` proved do not resolve -- including `.frictionMulLateral`,
    --- the largest of them. More than half of wet weather was a silent no-op. What stays on the record is
    --- `slip_curve` and `turn_friction`: the SHAPE of the let-go, which a scalar cannot express.
    ---
    --- Always returns a contributor, even at zero wetness, so the seam is visible in the trace rather than
    --- absent from it.
    function M.weatherContributor(wetness)
        local w = tonumber(wetness) or 0
        if w ~= w or w < 0 then w = 0 elseif w > 1 then w = 1 end
        return {
            source = "weather",
            gripScale = 1.0 - (M.WET_DEPTH.gripScale * w),
            brakeScale = 1.0 - (M.WET_DEPTH.brakeScale * w),
        }
    end

    --- How much of each lever full wet removes. Carried over from `machine.projection`'s `M.WET`, whose
    --- header is explicit that these are placeholders awaiting play data.
    M.WET_DEPTH = { gripScale = 0.18, brakeScale = 0.15 }

    --- `direction` as a comparable string, rounded so floating-point noise cannot make two identical
    --- directions look different.
    function M.directionKey(family)
        local direction = M.direction(family)
        if not direction then return nil end
        local out = {}
        for _, id in ipairs(M.LEVER_IDS) do out[#out + 1] = ("%s:%.3f"):format(id, direction[id]) end
        return table.concat(out, "|")
    end

    return M
end)
