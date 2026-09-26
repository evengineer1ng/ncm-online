-- ncm-core module: parts.handling
--
-- **The per-machine half of Parts.** `machine.projection` composes the RECORD channel -- drive-model flats,
-- per-record, spawn-cached, shared by every instance of that model on a client. This module composes the
-- INSTANCE channel: the live force interception proved in MASTER_TEST sections AU and AW and authorised by
-- `L148` / `L151`.
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
-- The price is width. The record channel reaches eight families through twenty flats; this one reaches
-- THREE, because three is how many quantities have been proven to move a car:
--
--   `gripScale`   tyre grip, across travel        -- MASTER_TEST section AU5
--   `driveScale`  power delivery, along travel    -- MASTER_TEST section AW1
--   `brakeScale`  braking, along travel           -- MASTER_TEST section AW2
--
-- **Three is the whole list, and a family outside it is refused rather than approximated.** Suspension,
-- steering, aerodynamics and mass have no instance expression: anti-roll and yaw balance are MOMENTS, and
-- section AW3 refuted the per-corner load entries with a mechanism (the force accumulator at `+0x00` carries
-- no position, so a zero-sum redistribution is byte-identical in net force and cannot produce one). A
-- suspension part asking for a live effect here gets a named refusal, not a silent nothing and not a
-- plausible-looking number. That refusal is 18_PARTS_ECOSYSTEM section 8.1's warning made executable.
--
-- ---------------------------------------------------------------------------------------------------
-- BALANCE IS NOT DECIDED HERE
-- ---------------------------------------------------------------------------------------------------
--
-- 18_PARTS_ECOSYSTEM puts "component balance, rarity tiers, loot tiers" explicitly out of scope, so this
-- module invents no numbers. **Each fitted part states its own effect** and this module's job is the part
-- that is not a balance judgement: validating the family can express what it claims, combining parts that
-- share a lever, clamping to the carrier's proven bounds, and reporting when it clamped.
--
-- Combination is MULTIPLICATIVE within a lever. Two parts at 1.05 give 1.1025, not 1.10. That is the right
-- arithmetic for independent multipliers on one physical quantity, and -- the reason it is not a taste
-- choice -- multiplication is commutative, so the composed setup does not depend on the order parts happen
-- to arrive in. An additive rule would make the result depend on iteration order over a Lua table.
local Core = NcmCore

Core.define("parts.handling", function(C)
    local Ontology = C.get("parts.ontology")

    local M = { version = "0.0.1" }

    M.SETUP_VERSION = 1

    -- ---------------------------------------------------------------------------------------------
    -- The three levers
    -- ---------------------------------------------------------------------------------------------
    --
    -- `min` and `max` MIRROR THE CARRIER'S OWN CLAMPS (`vehicle/physics_probe.cpp`: `kGripScaleMin/Max`,
    -- `kDriveScaleMin/Max`, `kBrakeScaleMin/Max`). They are duplicated here on purpose rather than sent
    -- down from the plugin: the server must be able to tell a player "that setup would have been clamped"
    -- while composing, and a value that arrives already inside the bound is one the carrier will apply
    -- unchanged. The carrier clamps again regardless -- it does not trust the wire, and should not.
    --
    -- `evidence` is the live PASS that authorises the lever. A lever with no section here has no business
    -- in this table; that is the rule section AV2 cost three drives to learn.
    M.LEVERS = {
        gripScale = {
            id = "gripScale", family = "tires", quantity = "lateral_grip_vehicle",
            min = 0.30, max = 1.50, inert = 1.00,
            evidence = "MASTER_TEST AU5",
            note = "Force across travel. Below 1.0 is a wet road, not a slow car.",
        },
        driveScale = {
            id = "driveScale", family = "power_unit", quantity = "longitudinal_force_driving",
            min = 0.30, max = 2.00, inert = 1.00,
            evidence = "MASTER_TEST AW1",
            note = "Force along travel while it is PUSHING. Power delivery.",
        },
        brakeScale = {
            id = "brakeScale", family = "brakes", quantity = "longitudinal_force_braking",
            min = 0.30, max = 2.00, inert = 1.00,
            evidence = "MASTER_TEST AW2",
            note = "Force along travel while it is RETARDING. Stopping ability.",
        },
    }

    -- Declared order, so a composed setup serialises identically every time. `pairs` over M.LEVERS would
    -- not, and a signature that changes without the value changing republishes for nothing.
    M.LEVER_IDS = { "gripScale", "driveScale", "brakeScale" }

    M.LEVER_OF_FAMILY = {}
    for _, id in ipairs(M.LEVER_IDS) do
        M.LEVER_OF_FAMILY[M.LEVERS[id].family] = id
    end

    -- ---------------------------------------------------------------------------------------------
    -- Agreement with the ontology, asserted at load
    -- ---------------------------------------------------------------------------------------------
    --
    -- `parts.ontology.INSTANCE_QUANTITIES` is the periodic table's claim about what the live channel can
    -- do; this table is what actually gets written. **If they ever disagree, the ontology is lying to a
    -- designer**, which is precisely the failure IDEA-505 exists to prevent -- so they are checked against
    -- each other here rather than kept in sync by hand.
    for family, quantities in pairs(Ontology.INSTANCE_QUANTITIES) do
        local lever = M.LEVER_OF_FAMILY[family]
        assert(lever, "parts.ontology claims an instance quantity for '" .. family
            .. "' but parts.handling has no lever for it")
        local found = false
        for _, q in ipairs(quantities) do
            if q == M.LEVERS[lever].quantity then found = true end
        end
        assert(found, "parts.ontology's instance quantity for '" .. family
            .. "' does not name '" .. M.LEVERS[lever].quantity .. "'")
    end
    for family, lever in pairs(M.LEVER_OF_FAMILY) do
        assert(Ontology.INSTANCE_QUANTITIES[family],
            "parts.handling has lever '" .. lever .. "' for family '" .. family
            .. "' but parts.ontology does not declare it expressible")
    end

    -- ---------------------------------------------------------------------------------------------
    -- Composing
    -- ---------------------------------------------------------------------------------------------

    local function clampLever(lever, value)
        if value < lever.min then return lever.min, true end
        if value > lever.max then return lever.max, true end
        return value, false
    end

    --- Is this family expressible live at all? A plain question with a plain answer, so a caller never has
    --- to infer it from a nil.
    --- Returns `lever id` or `nil, reason`.
    function M.leverFor(family)
        if type(family) ~= "string" then return nil, "family must be a string" end
        if not Ontology.isFamily(family) then return nil, "unknown family: " .. family end
        local lever = M.LEVER_OF_FAMILY[family]
        if not lever then
            return nil, "family '" .. family
                .. "' has no live quantity on the instance channel; it can only be felt through the record "
                .. "channel (machine.projection), if at all"
        end
        return lever
    end

    --- Compose one driver's fitted parts into a setup for the carrier.
    ---
    --- `input` = {
    ---   vehicle = "<entity or record key>",     -- opaque here; the caller's own handle for the machine
    ---   parts = {
    ---     { id = "eng_stage2", family = "power_unit", effect = 1.15 },
    ---     { id = "tyre_soft",  family = "tires",      effect = 1.08 },
    ---   },
    --- }
    ---
    --- `opts` = { at = <unix seconds> }
    ---
    --- Returns `setup` or `nil, reason`. A part naming a family with no live quantity is a REFUSAL of the
    --- whole compose rather than a skipped row: silently dropping it is how a player pays for an engine
    --- that does nothing and nobody finds out for a month.
    function M.compose(input, opts)
        opts = opts or {}
        if type(input) ~= "table" then return nil, "input must be a table" end
        local parts = input.parts
        if parts ~= nil and type(parts) ~= "table" then return nil, "parts must be a table" end
        parts = parts or {}

        local values, trace = {}, {}
        for _, id in ipairs(M.LEVER_IDS) do values[id] = M.LEVERS[id].inert end

        for index, part in ipairs(parts) do
            local where = "parts[" .. index .. "]"
            if type(part) ~= "table" then return nil, where .. " must be a table" end

            local lever, why = M.leverFor(part.family)
            if not lever then
                return nil, where .. " (" .. tostring(part.id) .. "): " .. why
            end

            local effect = part.effect
            if type(effect) ~= "number" or effect ~= effect or effect <= 0
                or effect == math.huge then
                return nil, where .. " (" .. tostring(part.id)
                    .. "): effect must be a finite positive multiplier, got " .. tostring(effect)
            end

            values[lever] = values[lever] * effect
            trace[#trace + 1] = {
                part = part.id, family = part.family, lever = lever, by = effect,
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
            -- Server-side only. **`trace` is exactly what pushed `ncmProjections` over the state bag's size
            -- limit in KB-136**, so it exists for the log and the `wire()` form drops it.
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
            levers = levers, trace = {}, clamped = {},
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

    --- One human line, for the log and for a panel. Says what is being applied and what was clamped.
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
        if setup.clamped and #setup.clamped > 0 then
            local c = {}
            for _, entry in ipairs(setup.clamped) do
                c[#c + 1] = ("%s wanted %.3f"):format(entry.lever, entry.wanted)
            end
            line = line .. " (CLAMPED: " .. table.concat(c, ", ") .. ")"
        end
        return line
    end

    --- What can and cannot be felt live, as data rather than as prose. A panel that wants to grey out
    --- "this part has no effect yet" reads this instead of hard-coding three family names.
    function M.inventory()
        local live, inert = {}, {}
        for _, family in ipairs(Ontology.FAMILIES) do
            if M.LEVER_OF_FAMILY[family] then
                live[#live + 1] = { family = family, lever = M.LEVER_OF_FAMILY[family],
                                    evidence = M.LEVERS[M.LEVER_OF_FAMILY[family]].evidence }
            else
                inert[#inert + 1] = family
            end
        end
        return { live = live, notLive = inert }
    end

    return M
end)
