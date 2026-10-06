-- ncm-core module: parts.architecture
--
-- The mechanical architecture profile: what a vehicle IS, mechanically, so that components can declare
-- constraints against it and compatibility can be **derived rather than listed**. 18_PARTS_ECOSYSTEM's
-- scaling requirement is the whole reason this module exists:
--
--   > when NCM adds vehicle model #83, nobody should have to edit thousands of historical component
--   > definitions. The new vehicle states its architecture, existing components state their requirements,
--   > and compatibility falls out.
--
-- ---------------------------------------------------------------------------------------------------
-- THE HONESTY PROBLEM, AND HOW THIS MODULE HANDLES IT
-- ---------------------------------------------------------------------------------------------------
--
-- The spec calls this *"new authoring against 27 existing catalogue entries"* (conflict 4), and it is right.
-- But most of it cannot be authored from here without inventing facts. **Cyberpunk does not tell us, from
-- anything in this repository, whether a Thorton Galena is front- or rear-wheel drive.** That lives in
-- `vehDriveModelData` in TweakDB, which only a running game can read. There is no dump in the workspace.
--
-- So this module does not guess. **Every facet value carries a provenance**, and there are exactly three:
--
--   * `derived`  -- computed from `data.vehicle_catalogue`, and true by construction. A Bike has two wheels
--                   and handlebars because it is a Bike; nothing was invented.
--   * `authored` -- a human stated it. None yet.
--   * `unknown`  -- **we do not know, and the module says so.** This is the common case today.
--
-- `M.authoringGaps()` turns that into the owner's worklist: exactly which vehicle needs exactly which facet
-- stated. That is a more useful deliverable than 27 rows of plausible fiction, and it is the difference
-- between a compatibility system that is empty and one that is wrong.
--
-- **Unknown fails closed.** `parts.compat` refuses a component whose constraint touches an unknown facet,
-- and reports it as `unknown_facet` rather than as a mismatch, so "we have not authored this yet" is never
-- silently indistinguishable from "this part does not fit". The codebase already works this way -- the
-- vehicle-access placement probe refuses on unavailable geometry rather than assuming clear ground.
local Core = NcmCore

Core.define("parts.architecture", function(C)
    local M = { version = "0.0.1" }

    local catalogue = C.get("data.vehicle_catalogue")
    local ontology = C.get("parts.ontology")

    M.UNKNOWN = "unknown"
    M.DERIVED, M.AUTHORED = "derived", "authored"

    -- ---------------------------------------------------------------------------------------------
    -- The facet vocabulary
    -- ---------------------------------------------------------------------------------------------
    --
    -- Taken from 18_PARTS_ECOSYSTEM's own list. Each facet names the family that cares about it, so a
    -- component in that family has an obvious facet to constrain against and the resolver can explain
    -- itself in mechanical terms. `platform` belongs to `chassis` because chassis is the compatibility root.
    --
    -- Values are CLOSED sets. An open vocabulary would let a typo become a new architecture that silently
    -- matches nothing, which is the failure mode this whole module exists to avoid.
    M.FACETS = {
        { id = "propulsion",      family = "power_unit",
          values = { "combustion", "electric", "hybrid" } },
        { id = "power_interface", family = "power_unit",
          values = { "compact", "standard", "large", "competition", "motorcycle" } },
        { id = "thermal",         family = "cooling",
          values = { "liquid", "air", "battery_thermal" } },
        { id = "transmission",    family = "transmission",
          values = { "manual", "automatic", "sequential", "direct_drive" } },
        { id = "drivetrain",      family = "drivetrain",
          values = { "fwd", "rwd", "awd", "chain" } },
        { id = "axle_config",     family = "drivetrain",
          values = { "2x2", "1x1" } },
        { id = "wheel_fitment",   family = "tires",
          values = { "compact", "standard", "large", "competition", "motorcycle" } },
        { id = "brake_interface", family = "brakes",
          values = { "standard", "performance", "competition", "motorcycle" } },
        { id = "suspension",      family = "suspension",
          values = { "road_independent", "utility", "performance", "competition", "motorcycle_fork" } },
        { id = "steering",        family = "steering",
          values = { "rack", "handlebar" } },
        { id = "electrical",      family = "electrical",
          values = { "standard", "high_voltage", "competition" } },
        { id = "aero_mounting",   family = "aerodynamics",
          values = { "none", "light", "full" } },
        { id = "structure",       family = "structure",
          values = { "unibody", "body_on_frame", "monocoque", "motorcycle_frame" } },
        { id = "platform",        family = "chassis",
          values = nil },   -- open by nature: a platform id is an identity, not a category
    }

    M.FACET_IDS = {}
    M.FACET = {}
    for _, facet in ipairs(M.FACETS) do
        M.FACET_IDS[#M.FACET_IDS + 1] = facet.id
        M.FACET[facet.id] = facet
        if not ontology.isFamily(facet.family) then
            error("parts.architecture: facet '" .. facet.id .. "' names unknown family " .. facet.family)
        end
    end

    function M.isFacet(id) return M.FACET[id] ~= nil end

    --- Is this a legal value for this facet? `platform` accepts any non-empty string, because a platform id
    --- is an identity rather than one of a fixed set.
    function M.isFacetValue(facetId, value)
        local facet = M.FACET[facetId]
        if not facet or type(value) ~= "string" or value == "" then return false end
        if not facet.values then return true end
        for _, v in ipairs(facet.values) do if v == value then return true end end
        return false
    end

    -- ---------------------------------------------------------------------------------------------
    -- Platform derivation -- the one piece of real compatibility structure the catalogue already carries
    -- ---------------------------------------------------------------------------------------------
    --
    -- Variants of one machine share a platform, and NCM's own `vehicleKey`s say which are variants. This is
    -- derivation, not authoring: `quadra_type66` and `quadra_type66_nomad` are the same car underneath, and
    -- a component that fits one fits the other. Collapsing them is what stops the component catalogue
    -- growing linearly with cosmetic variants.
    --
    -- A suffix only collapses when the result is real: either the base is itself a catalogue key, or at
    -- least two keys reduce to it. `thorton_colby_pickup` therefore stays its own platform -- `_pickup` is
    -- not in the list, and a pickup is not a trim level of a coupe.
    local VARIANT_SUFFIXES = { "_nomad", "_sport", "_tyger", "_animal" }

    local function baseOf(key)
        for _, suffix in ipairs(VARIANT_SUFFIXES) do
            if #key > #suffix and key:sub(-#suffix) == suffix then
                return key:sub(1, #key - #suffix)
            end
        end
        return key
    end

    local platformOf = {}
    do
        local baseCount, keys = {}, {}
        for _, entry in ipairs(catalogue.entries()) do
            keys[#keys + 1] = entry.vehicleKey
        end
        for _, key in ipairs(keys) do
            local base = baseOf(key)
            baseCount[base] = (baseCount[base] or 0) + 1
        end
        for _, key in ipairs(keys) do
            local base = baseOf(key)
            -- `base ~= key` means a suffix was stripped; accept it only if the base is a real machine or is
            -- shared by siblings. Otherwise the vehicle is its own platform.
            if base ~= key and (catalogue.byKey(base) or (baseCount[base] or 0) > 1) then
                platformOf[key] = base
            else
                platformOf[key] = key
            end
        end
    end

    --- The platform a vehicle sits on. Several vehicles may share one; most do not.
    function M.platform(vehicleKey) return platformOf[vehicleKey] end

    --- Every platform, with the vehicles on it. The shape the compatibility resolver reasons in.
    function M.platforms()
        local out, order = {}, {}
        for _, entry in ipairs(catalogue.entries()) do
            local platform = platformOf[entry.vehicleKey]
            if not out[platform] then out[platform] = {}; order[#order + 1] = platform end
            local list = out[platform]
            list[#list + 1] = entry.vehicleKey
        end
        return out, order
    end

    -- ---------------------------------------------------------------------------------------------
    -- Derivation from the catalogue -- only what is true by construction
    -- ---------------------------------------------------------------------------------------------
    --
    -- A Bike has two wheels, handlebars, a fork, a chain and a frame. That is not a guess about a particular
    -- motorcycle; it is what being a motorcycle means. Formula is the same: the RB15 is a single-seat
    -- competition car, so monocoque, full aero and competition brakes follow from the category NCM already
    -- assigns it. **Nothing else is derived**, because nothing else is safe to derive. Drivetrain layout,
    -- propulsion, transmission and thermal architecture are per-model facts that live in TweakDB.
    local function derive(entry)
        local facets, provenance = {}, {}

        local function set(facetId, value)
            facets[facetId] = value
            provenance[facetId] = M.DERIVED
        end

        set("platform", platformOf[entry.vehicleKey])

        local category = entry.category
        if category == "Bike" then
            set("axle_config", "1x1")
            set("steering", "handlebar")
            set("suspension", "motorcycle_fork")
            set("structure", "motorcycle_frame")
            set("drivetrain", "chain")
            set("wheel_fitment", "motorcycle")
            set("brake_interface", "motorcycle")
            set("power_interface", "motorcycle")
            set("aero_mounting", "none")
        else
            set("axle_config", "2x2")
            set("steering", "rack")
            if category == "Formula" then
                set("structure", "monocoque")
                set("aero_mounting", "full")
                set("brake_interface", "competition")
                set("suspension", "competition")
                set("wheel_fitment", "competition")
                set("power_interface", "competition")
                set("electrical", "competition")
                set("transmission", "sequential")
            end
        end

        return facets, provenance
    end

    -- Authored overrides. Empty on purpose: nothing here has been stated by a human yet, and an invented
    -- row would be indistinguishable from a real one the moment it was written. Adding a vehicle's facets
    -- to `M.AUTHORED_PROFILES` is the entire authoring task, and `M.authoringGaps()` lists what is outstanding.
    M.AUTHORED_PROFILES = {}

    local profiles = {}
    for _, entry in ipairs(catalogue.entries()) do
        local facets, provenance = derive(entry)
        local authored = M.AUTHORED_PROFILES[entry.vehicleKey]
        if authored then
            for facetId, value in pairs(authored) do
                if M.isFacetValue(facetId, value) then
                    facets[facetId] = value
                    provenance[facetId] = M.AUTHORED
                end
            end
        end
        profiles[entry.vehicleKey] = {
            vehicleKey = entry.vehicleKey,
            platform = facets.platform,
            category = entry.category,
            facets = facets,
            provenance = provenance,
        }
    end

    --- A vehicle's architecture profile, or nil if NCM does not know the vehicle at all.
    function M.profile(vehicleKey)
        return type(vehicleKey) == "string" and profiles[vehicleKey] or nil
    end

    --- One facet's value, or `M.UNKNOWN`. Never nil for a known vehicle and a known facet, because a caller
    --- that has to distinguish "no such facet" from "not authored yet" would get it wrong.
    function M.facet(vehicleKey, facetId)
        local profile = profiles[vehicleKey]
        if not profile or not M.FACET[facetId] then return nil end
        return profile.facets[facetId] or M.UNKNOWN
    end

    function M.facetProvenance(vehicleKey, facetId)
        local profile = profiles[vehicleKey]
        if not profile or not M.FACET[facetId] then return nil end
        return profile.provenance[facetId] or M.UNKNOWN
    end

    --- The authoring worklist: every (vehicle, facet) pair nobody has stated. This is the deliverable of
    --- this module until someone sits down with the game and fills it in.
    function M.authoringGaps()
        local gaps = {}
        for _, entry in ipairs(catalogue.entries()) do
            local profile = profiles[entry.vehicleKey]
            for _, facetId in ipairs(M.FACET_IDS) do
                if not profile.facets[facetId] then
                    gaps[#gaps + 1] = { vehicleKey = entry.vehicleKey, facet = facetId }
                end
            end
        end
        return gaps
    end

    --- How complete is the authoring, as counts rather than a percentage nobody can act on.
    function M.coverage()
        local known, total = 0, 0
        for _, entry in ipairs(catalogue.entries()) do
            local profile = profiles[entry.vehicleKey]
            for _, facetId in ipairs(M.FACET_IDS) do
                total = total + 1
                if profile.facets[facetId] then known = known + 1 end
            end
        end
        return { known = known, total = total, vehicles = catalogue.count(), facets = #M.FACET_IDS }
    end

    return M
end)
