-- ncm-core module: parts.ontology
--
-- The component periodic table: what kinds of component can exist, and -- separately -- whether a component
-- in that family can ever be FELT by the person driving. 18_PARTS_ECOSYSTEM's first instruction is
-- *"do not make the parts yet; build the periodic table, the grammar, and the factory that can eventually
-- make them"*, and this is the periodic table.
--
-- **This module says what a family IS. It never says what a part DOES.** No buffs, no percentages, no
-- balance, no rarity. Those are out of scope by the spec and stay out. What this module adds beyond a list
-- of twelve names is the honest answer to the question every later system will ask: *if I build a part in
-- this family, can the driver feel it, and through what?*
--
-- THE TWELVE FAMILIES ARE NOT DECLARED HERE. They are `engineering.competency.FAMILIES`, already canonical
-- since L120 and already carrying 12 of every engineer's 27 numbers. Re-listing them would create a second
-- authority that drifts. This module asserts agreement at load and refuses to load if it ever breaks.
--
-- ---------------------------------------------------------------------------------------------------
-- THE FOUR EXPRESSION CHANNELS, and why the distinction is load-bearing
-- ---------------------------------------------------------------------------------------------------
--
-- A part's *truth* is always server-side and always safe (IDEA-458). A part's *feel* has to travel through
-- one of exactly four channels, and they have sharply different guarantees. Getting these confused is how a
-- Brakes family gets designed around brake bias and then discovers brake bias is unreachable.
--
--   * `record`     -- a TweakDB drive-model flat, via `machine.flats` and the carrier's `effects/tweak.cpp`.
--                     **Built and shipping.** Twenty flats across eight families: the broad channel.
--                     BUT: spawn-cached (Report 36 section 4), so a change reaches a car at its next spawn
--                     and never the one you are sitting in; and keyed by RECORD, so on one client every
--                     Galena shares one set of values. Per-outing, not per-lap. Not per-player.
--   * `instance`   -- the live per-instance force write proved in MASTER_TEST section AU (L148).
--                     **Built and shipping.** Live, reversible, per-instance, per-player, no respawn.
--                     THREE quantities -- lateral grip (AU5), drive force (AW1), brake force (AW2) --
--                     but ELEVEN of the twelve families reach them, because a family may be expressed
--                     APPROXIMATELY onto a lever it does not literally own (`L154`). Narrow in vocabulary,
--                     wide in coverage. What it still cannot do is any MOMENT: anti-roll, yaw balance and
--                     brake bias are refuted, not pending -- see `per_corner` below -- and every
--                     approximation enumerates exactly what it loses.
--   * `simulated`  -- NCM's own server-authoritative modelling. Always available, always safe, never felt
--                     through the steering wheel. Lap-time modelling, wear, failure, eligibility, results.
--   * `per_corner` -- **DOES NOT EXIST.** Front/rear balance, brake bias, anti-roll, per-corner tyre
--                     temperature, downforce-as-grip. MASTER_TEST section AV2 tried to reach it by
--                     redistributing per-corner normal load and returned a clean negative: 20 percent of
--                     axle load moved, under 5 percent change in lateral capability. `IDEA-503` bookmarks
--                     the only surviving route (`insert1`) and it is not scheduled.
--
-- **`record` is broad but shared and stale. `instance` is live and personal but three fields wide.** They
-- are complements, not alternatives, and no family is served well by both today.
--
-- IDEA-505 is the rule this module enforces: a Part declares its channel, and nothing may promise a felt
-- effect on `per_corner`. `M.declarationIsHonest` is that rule as an assertion rather than as prose,
-- because 18_PARTS_ECOSYSTEM section 8.1's warning -- design a family around a channel that does not exist --
-- has already come true once this session.
local Core = NcmCore

Core.define("parts.ontology", function(C)
    local M = { version = "0.0.1" }

    local competency = C.get("engineering.competency")
    local flats = C.get("machine.flats")

    M.FAMILIES = competency.FAMILIES

    -- ---------------------------------------------------------------------------------------------
    -- Channels
    -- ---------------------------------------------------------------------------------------------

    --- exists      is there a working transport for this today
    --- felt        does the driver experience it through the car, rather than through a screen
    --- live        does it reach a car that already exists, or only one that spawns after the change
    --- scope       what the change is keyed by: "record" is shared by every instance of that model
    --- perPlayer   can two players in the SAME vehicle model differ from each other
    M.CHANNELS = {
        record = {
            id = "record", exists = true, felt = true, live = false,
            scope = "record", perPlayer = false,
            note = "TweakDB drive-model flat. Broad (20 flats, 8 families) but spawn-cached and shared "
                .. "across every instance of that model on a client. Fit in the garage, feel it next outing.",
        },
        instance = {
            id = "instance", exists = true, felt = true, live = true,
            scope = "instance", perPlayer = true,
            note = "Live per-instance force write (L148). Personal, reversible, no respawn -- but exactly "
                .. "one quantity: vehicle-level lateral grip.",
        },
        simulated = {
            id = "simulated", exists = true, felt = false, live = true,
            scope = "asset", perPlayer = true,
            note = "NCM's own server-authoritative modelling. Never felt through the car; always correct.",
        },
        per_corner = {
            id = "per_corner", exists = false, felt = true, live = true,
            scope = "corner", perPlayer = true,
            note = "Does not exist. Refuted for the force channel by MASTER_TEST section AV2; the only "
                .. "surviving route is `insert1` (IDEA-503), which is bookmarked and unscheduled.",
        },
    }

    M.CHANNEL_IDS = { "record", "instance", "simulated", "per_corner" }

    -- Which of the live channel's three quantities each family reaches.
    --
    -- **Eleven of twelve families, not three, since `L154`.** This table has now been wrong twice in one
    -- day in the same direction -- too narrow -- and both times the error was a rule rather than a fact.
    -- It said `tires` only, which was true until section AW proved `driveScale` and `brakeScale`. It then
    -- said three, because `parts.handling` refused to express a family unless a lever literally WAS its
    -- quantity. That rule conflated "cannot be felt" with "cannot be felt exactly", and a suspension part
    -- raising usable grip is a coarse model of a real effect rather than a fabrication.
    --
    -- **Fidelity, not admission, is what separates them.** `INSTANCE_FIDELITY` below says whether a
    -- family's quantity is the lever itself or is modelled onto it, and `parts.handling.EXPRESSION`
    -- carries the physical rationale and -- the part that matters -- the enumerated LOSSES: what a part in
    -- that family provably cannot express. That list is where `IDEA-505`'s honesty requirement now lives.
    --
    -- **Widened a third time by `L156`, and for the opposite reason to the first two.** The earlier errors
    -- were too FEW families. This one was too few QUANTITIES PER FAMILY: nine families named a single
    -- lever, which left `transmission`, `drivetrain`, `cooling` and `electrical` pointing in the identical
    -- direction and differing only in magnitude -- one dial with four labels. Three levers is a space, and
    -- a family is a direction in it, so most families legitimately reach two or three.
    --
    -- `parts.handling` ASSERTS AT LOAD that these tables agree with its own, in both directions, so this
    -- cannot drift again without a test failing.
    local GRIP  = "lateral_grip_vehicle"
    local DRIVE = "longitudinal_force_driving"
    local BRAKE = "longitudinal_force_braking"
    -- Retarding force while NOBODY IS BRAKING -- aerodynamic drag, which sets terminal velocity. Split
    -- from `BRAKE` on 2026-09-26: the carrier discriminated retarding force by sign alone, so a brake
    -- part silently moved top speed and `aerodynamics` had to book its drag against DRIVE, pretending a
    -- wing reduces engine power. The carrier now separates them on the driver's brake pedal.
    local DRAG  = "longitudinal_force_coasting"

    M.INSTANCE_QUANTITIES = {
        -- direct: the lever is the family's own quantity, plus the couplings it genuinely has
        tires        = { GRIP, BRAKE, DRIVE },   -- AU5; braking is grip-limited, traction likewise
        power_unit   = { DRIVE, GRIP },          -- AW1; engine mass costs a little cornering
        brakes       = { BRAKE },                -- AW2; the one genuinely pure direction
        -- approximated: a real effect, coarsely modelled, pointing somewhere of its own
        suspension   = { GRIP, BRAKE, DRIVE },   -- body control, most felt under weight transfer
        structure    = { GRIP, BRAKE },          -- stiffness as grip and as consistency under load
        aerodynamics = { GRIP, DRAG, BRAKE },    -- downforce adds grip, drag costs TOP SPEED and shortens a stop
        transmission = { DRIVE, BRAKE },         -- ratios multiply torque both ways: engine braking
        drivetrain   = { DRIVE, GRIP },          -- a tighter driveline puts power down and costs turn-in
        cooling      = { DRIVE, BRAKE },         -- thermal headroom, and ducting feeds the brakes
        electrical   = { DRIVE },                -- honestly pure drive: the baseline the others differ FROM
        chassis      = { GRIP, DRIVE, BRAKE, DRAG }, -- mass touches all four; drag least, and inversely
    }

    --- Is the quantity the lever itself, or a model of the family mapped onto it? A panel that says
    --- "measured" where it should say "modelled" is the dishonesty this distinction exists to prevent.
    M.INSTANCE_FIDELITY = {
        tires = "direct", power_unit = "direct", brakes = "direct",
        suspension = "approximated", structure = "approximated", aerodynamics = "approximated",
        transmission = "approximated", drivetrain = "approximated", cooling = "approximated",
        electrical = "approximated", chassis = "approximated",
    }

    --- The one family with no live expression, recorded with its mechanism rather than left absent.
    --- Steering changes RESPONSE, not the magnitude of any force this channel reaches; the only honest
    --- expression would be input authority, which `KB-135` reserves to the driver.
    M.INSTANCE_REFUSED = { steering = true }

    -- ---------------------------------------------------------------------------------------------
    -- The periodic table
    -- ---------------------------------------------------------------------------------------------

    --- meaning     what the family is for, verbatim in sense from 18_PARTS_ECOSYSTEM
    --- abstracts   what a component in this family should NOT model (the spec's own list)
    --- subfamilies FIRST PASS. Structural divisions only, never product categories. The spec says room to
    ---             refine and "do not casually collapse them"; it does not enumerate these, so treat them as
    ---             a starting shape that repo or design pressure may change, not as authored content.
    M.FAMILY = {
        power_unit = {
            meaning = "produces motive power",
            abstracts = { "pistons", "bearings", "valves", "seals", "fasteners" },
            subfamilies = { "core_assembly", "induction", "fuel_delivery", "ignition", "exhaust", "lubrication" },
        },
        cooling = {
            meaning = "moves and rejects heat",
            abstracts = { "hoses", "clamps", "coolant quantities", "fittings" },
            subfamilies = { "heat_exchange", "circulation", "airflow_management", "thermal_control" },
        },
        transmission = {
            meaning = "converts and selects output before final drive",
            abstracts = { "bearings", "synchros", "small internals" },
            subfamilies = { "gearset", "coupling", "selection", "housing" },
        },
        drivetrain = {
            meaning = "carries torque to the driven wheels",
            abstracts = { "joints", "boots", "bearings", "fasteners" },
            subfamilies = { "final_drive", "differential", "shafts", "hubs" },
        },
        tires = {
            meaning = "replaceable contact medium",
            abstracts = { "tread blocks", "microscopic simulation", "pressure and temperature detail" },
            subfamilies = { "compound", "construction", "fitment_class" },
        },
        brakes = {
            meaning = "controlled deceleration",
            abstracts = { "lines", "fluid", "individual pistons" },
            subfamilies = { "friction_material", "rotating_element", "actuation", "cooling_duct" },
        },
        suspension = {
            meaning = "controls wheel movement and body motion",
            abstracts = { "bushings", "ball joints", "small mounting hardware" },
            subfamilies = { "spring_medium", "damping", "anti_roll", "linkage", "geometry_adjustment" },
        },
        steering = {
            meaning = "input to road-wheel direction",
            abstracts = { "column bearings", "small linkage hardware" },
            subfamilies = { "rack", "assistance", "column", "geometry" },
        },
        electrical = {
            meaning = "vehicle-wide power, sensing and computation",
            abstracts = { "wires", "fuses", "connectors", "relays" },
            subfamilies = { "power_storage", "generation", "sensing", "control_unit", "network" },
        },
        aerodynamics = {
            meaning = "airflow for stability, drag, cooling and downforce",
            abstracts = { "tiny appendages", "fasteners" },
            subfamilies = { "front_device", "rear_device", "underbody", "bodywork_management" },
        },
        structure = {
            meaning = "load-bearing physical integrity",
            abstracts = { "welds", "cosmetic panels", "fatigue simulation" },
            subfamilies = { "reinforcement", "mounting", "protection", "mass_management" },
        },
        chassis = {
            meaning = "the platform everything else attaches to",
            abstracts = {},
            subfamilies = { "subframe", "mounting_architecture", "platform_hardware" },
        },
    }

    -- **Chassis is deliberately unusual** (spec): partly a family, partly the root of the compatibility
    -- tree. "Replace chassis" must never become equivalent to replacing brake pads, because the
    -- identity-bearing chassis of a persistent vehicle is not a casually swappable part. The ontology keeps
    -- three things apart -- vehicle identity, vehicle architecture, and replaceable chassis-related
    -- assemblies -- and only the third is ever a component.
    M.COMPATIBILITY_ROOT = "chassis"

    -- ---------------------------------------------------------------------------------------------
    -- Serialisation unit -- the spec's conflict 5, resolved here because it asked for it to be
    -- ---------------------------------------------------------------------------------------------
    --
    -- "INSTALLING A COMPONENT CHANGES WHERE IT IS. IT DOES NOT CREATE IT." That rule needs to know what one
    -- component *is*, and tyres are the case that breaks the obvious answer. The spec: *"do not assume
    -- individually serialised physical tires... find the cleanest abstraction (set? axle pair?
    -- specification?)"*.
    --
    -- **Resolved: a tyre asset is a SET of four, not a corner and not an axle pair.** Two reasons, and the
    -- second is new evidence the spec did not have:
    --
    --   1. Motorsport already treats tyres as sets. They are bought, fitted, heat-cycled and scrapped
    --      together; a "set of stickers" is the natural unit a driver already thinks in.
    --   2. **Per-corner identity would be identity without consequence.** MASTER_TEST section AV2 refuted the
    --      per-corner force channel, so a left-front with its own serial and its own history could never
    --      feel different from the right-front. Serialising four objects that can only ever behave as one is
    --      a database cost with no expression behind it.
    --
    -- If `IDEA-503` ever lands, `axle_pair` is the migration step, and `corner` after it -- which is why
    -- they are named here rather than assumed away. A family's unit is data, so changing it later is an
    -- ontology edit and a migration, not a redesign.
    M.UNIT = { COMPONENT = "component", SET = "set", AXLE_PAIR = "axle_pair", CORNER = "corner" }

    -- **A plain table with the default in the accessor, NOT a metatable.** `setmetatable` does not
    -- exist in the Open77 CLIENT Lua sandbox, and this line runs at module load -- so every client
    -- `NcmCore.get("parts.ontology")` threw, which took `parts.handling` down with it (it requires
    -- ontology at its own load), and every client caller of either silently got nil.
    --
    -- That is not hypothetical. It is why the gear headroom never applied: `carrier_bridge` asked for
    -- `parts.handling` to read one constant, got a throw, and pushed zero records with no log to say so.
    --
    -- Only `M.serialisationUnit` reads this table, and it already rejects unknown families, so moving
    -- the default into it is behaviour-identical for every caller.
    M.SERIALISATION_UNIT = { tires = M.UNIT.SET }

    -- ---------------------------------------------------------------------------------------------
    -- Load-time agreement with the authorities this module borrows from
    -- ---------------------------------------------------------------------------------------------

    local FAMILY_SET = {}
    for _, f in ipairs(M.FAMILIES) do FAMILY_SET[f] = true end

    for _, f in ipairs(M.FAMILIES) do
        if not M.FAMILY[f] then
            error("parts.ontology: family '" .. f .. "' has no periodic-table entry")
        end
    end
    for name in pairs(M.FAMILY) do
        if not FAMILY_SET[name] then
            error("parts.ontology: '" .. name .. "' is not one of engineering.competency's twelve")
        end
    end

    function M.isFamily(family) return FAMILY_SET[family] == true end

    function M.family(family) return M.FAMILY[family] end

    function M.subfamilies(family)
        local entry = M.FAMILY[family]
        return entry and entry.subfamilies or nil
    end

    function M.isSubfamily(family, subfamily)
        local subs = M.subfamilies(family)
        if not subs then return false end
        for _, s in ipairs(subs) do if s == subfamily then return true end end
        return false
    end

    function M.serialisationUnit(family)
        if not FAMILY_SET[family] then return nil end
        -- The default a known family gets when the table does not name one. Was an `__index` metamethod.
        return M.SERIALISATION_UNIT[family] or M.UNIT.COMPONENT
    end

    function M.isCompatibilityRoot(family) return family == M.COMPATIBILITY_ROOT end

    -- ---------------------------------------------------------------------------------------------
    -- Expression -- the honest answer, assembled rather than asserted
    -- ---------------------------------------------------------------------------------------------

    --- How can a part in this family be felt? Derived from `machine.flats` for the record channel and from
    --- `INSTANCE_QUANTITIES` for the live one, so it cannot drift from what the carrier actually does.
    ---
    --- Returns `{ family, channels = {id...}, flats = {id...}, felt = bool, perPlayerFelt = bool, note }`.
    --- `felt = false` is a real and common answer: four of the twelve families have no drive-model flat at
    --- all (`machine.flats.UNEXPRESSED_FAMILIES`), and that is a finding rather than an omission.
    function M.expression(family)
        if not FAMILY_SET[family] then return nil end

        local channels, flatIds = {}, {}

        if flats.familyIsExpressible(family) then
            channels[#channels + 1] = "record"
            for _, id in ipairs(flats.BY_FAMILY[family] or {}) do flatIds[#flatIds + 1] = id end
        end

        local live = M.INSTANCE_QUANTITIES[family]
        if live and #live > 0 then channels[#channels + 1] = "instance" end

        -- Always last, and always present. Every family can be modelled even when none of it can be felt.
        channels[#channels + 1] = "simulated"

        local felt, perPlayerFelt = false, false
        for _, id in ipairs(channels) do
            local ch = M.CHANNELS[id]
            if ch.exists and ch.felt then
                felt = true
                if ch.perPlayer then perPlayerFelt = true end
            end
        end

        local note
        if not felt then
            note = "No drive-model flat and no live quantity. A part here is real -- owned, fitted, worn, "
                .. "required for eligibility -- but it cannot be felt through this carrier."
        elseif not perPlayerFelt then
            note = "Felt through the record channel only: spawn-cached and shared by every instance of the "
                .. "model on a client. Two drivers in the same car cannot differ."
        else
            note = "Felt live and per-player, but only through the one quantity the instance channel carries."
        end

        return {
            family = family,
            channels = channels,
            flats = flatIds,
            felt = felt,
            perPlayerFelt = perPlayerFelt,
            note = note,
        }
    end

    --- IDEA-505 as an assertion. A Part declares the channel its felt effect terminates in; this refuses the
    --- declarations that are lies. Returns `true` or `false, reason`.
    ---
    --- The refusals are deliberately blunt, because the failure this prevents is not a crash -- it is a
    --- family of parts shipped with a number that means nothing.
    function M.declarationIsHonest(family, channelId)
        if not FAMILY_SET[family] then return false, "unknown family: " .. tostring(family) end

        local channel = M.CHANNELS[channelId]
        if not channel then return false, "unknown channel: " .. tostring(channelId) end

        if not channel.exists then
            return false, "channel '" .. channelId .. "' does not exist; see IDEA-503"
        end

        if channelId == "simulated" then return true end

        local expression = M.expression(family)
        for _, id in ipairs(expression.channels) do
            if id == channelId then return true end
        end

        if channelId == "record" then
            return false, "family '" .. family .. "' has no drive-model flat"
        end
        return false, "family '" .. family .. "' has no live quantity on the instance channel"
    end

    --- Every family, split by whether it can be felt at all. The diagnostic a designer should read before
    --- choosing what to build first -- the same service `machine.flats.inventory` performs for flats.
    function M.inventory()
        local felt, modelledOnly = {}, {}
        for _, family in ipairs(M.FAMILIES) do
            local into = M.expression(family).felt and felt or modelledOnly
            into[#into + 1] = family
        end
        return { felt = felt, modelledOnly = modelledOnly }
    end

    return M
end)
