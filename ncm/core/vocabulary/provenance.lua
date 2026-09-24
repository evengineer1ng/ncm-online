-- ncm-core module: vocabulary.provenance
-- Closed vocabularies from the architecture (01_ARCHITECTURE.md §2.2) and validators for the
-- context record every sporting result carries (decision record L6, L11).
local Core = NcmCore

Core.define("vocabulary.provenance", function(C)
    local M = { version = "0.0.1" }

    --- Build an enum: `E.values` (ordered list), `E.is(v)`, and `E.<UPPER>` constants.
    local function enum(name, values)
        local E = { name = name, values = {}, set = {} }
        for i = 1, #values do
            local v = values[i]
            E.values[i] = v
            E.set[v] = true
            E[v:upper():gsub("[^%w]", "_")] = v
        end
        function E.is(v)
            return type(v) == "string" and E.set[v] == true
        end
        function E.assert(v, what)
            if not E.is(v) then
                error((what or name) .. ": invalid value '" .. tostring(v) .. "'", 3)
            end
            return v
        end
        return E
    end
    M.enum = enum

    -- Per-entrant provenance of a result (L6).
    M.Provenance = enum("provenance", { "physical", "simulated", "estimated", "dnf", "disconnected" })
    -- Where a sporting record was produced (L11).
    M.Origin = enum("origin", { "sp", "online" })
    -- World topology of a session (L15).
    M.Topology = enum("topology", { "open_world", "controlled_world", "isolated" })
    -- Entrant backend (P9).
    M.Backend = enum("backend", { "human", "physicalAI", "simulatedAI" })
    -- Event origination class (L16, P12).
    M.EventClass = enum("eventClass", { "calendar", "ambient", "impromptu", "organized" })
    -- Session kinds inside an event (L23).
    M.SessionKind = enum("sessionKind", {
        "practice", "qualifying_solo", "qualifying_shared", "race", "sprint", "feature", "stint", "leg",
    })
    -- Entry lifecycle (L20, P13).
    M.EntryState = enum("entryState", {
        "registered", "checked_in", "provisioned", "gridded", "racing", "suspended", "substituted",
        "finished", "dnf", "dsq", "withdrawn",
    })

    -- ---------------------------------------------------------------------------------------------
    -- Ownership principals (IDEA-297, IDEA-168, IDEA-162; L92/L93)
    -- ---------------------------------------------------------------------------------------------
    --
    -- Who can hold title, money or custody. A team machine is an ORDINARY machine (L123, L124 A2) -- what
    -- differs is the principal on the row, never the species of the object. Deliberately small: every new
    -- kind added here is a new thing that can own property across the whole economy.
    M.PrincipalKind = enum("principalKind", { "driver", "organization" })

    --- Validate an owner principal: { kind, id }. Nil means UNOWNED, which is legitimate and load-bearing --
    --- unsold market stock has no owner, and inventing one for a car on a shelf would be a lie.
    --- Returns true, or false + reason.
    function M.validatePrincipal(p)
        if p == nil then return true end                       -- unowned
        if type(p) ~= "table" then return false, "principal_not_table" end
        if p.kind == nil and p.id == nil then return true end  -- unowned, spelled out
        if not M.PrincipalKind.is(p.kind) then return false, "invalid_principal_kind" end
        if type(p.id) ~= "string" or #p.id == 0 then return false, "principal_without_id" end
        return true
    end

    -- ---------------------------------------------------------------------------------------------
    -- Machine attribution (IDEA-236, L124 A4)
    -- ---------------------------------------------------------------------------------------------
    --
    -- There is deliberately NO "machine source" vocabulary. A team car is simply a car owned by a team, an
    -- NCX car is simply a car, and exclusivity lives in market access rather than in the object (L124 A2,
    -- L126). Classifying machines by who uses them is the species distinction L123 forbids, and an earlier
    -- draft of this file carried it as `team_equipment` until migration 027 removed it.
    --
    -- WHICH machine is `asset_id`. HOW WELL WE KNOW IT is `AttributionBasis`. There is no third fact.

    -- How well we know it. The owner's ruling (A4): a derived attribution must remain permanently
    -- distinguishable from a recorded fact, and must carry the rule that produced it.
    M.AttributionBasis = enum("attributionBasis", { "recorded", "derived", "unknown" })

    --- Validate an attribution: { assetId?, basis?, rule? }.
    --- Returns true, or false + reason. The invariants, in order of how badly each would mislead:
    ---   * `recorded` without an assetId is a lie -- it claims we wrote something down that we did not
    ---   * `derived` without a rule is unfalsifiable -- nobody can later judge or supersede the reasoning
    ---   * `unknown` with an assetId is incoherent -- we either know which machine or we do not
    function M.validateAttribution(a)
        if type(a) ~= "table" then return false, "attribution_not_table" end
        local id, basis = a.assetId, a.basis
        if id ~= nil and type(id) ~= "string" then return false, "asset_id_not_string" end
        if basis ~= nil and not M.AttributionBasis.is(basis) then return false, "invalid_basis" end
        if basis == "recorded" and not id then return false, "recorded_without_asset" end
        if basis == "derived" and not (type(a.rule) == "string" and #a.rule > 0) then return false, "derived_without_rule" end
        if basis == "unknown" and id then return false, "unknown_with_asset" end
        return true
    end

    --- Validate a result context: { origin, serverId?, sessionKind, sanctioned, category? }.
    --- Returns true, or false + reason. Online contexts must name a server; SP contexts must not.
    function M.validateContext(ctx)
        if type(ctx) ~= "table" then
            return false, "context_not_a_table"
        end
        if not M.Origin.is(ctx.origin) then
            return false, "invalid_origin"
        end
        if not M.SessionKind.is(ctx.sessionKind) then
            return false, "invalid_session_kind"
        end
        if type(ctx.sanctioned) ~= "boolean" then
            return false, "sanctioned_not_boolean"
        end
        local ids = C.get("vocabulary.ids")
        if ctx.origin == "online" then
            if not ids.isSlug(ctx.serverId) then
                return false, "online_context_requires_server_id"
            end
        elseif ctx.serverId ~= nil then
            return false, "sp_context_must_not_name_server"
        end
        if ctx.category ~= nil and not ids.isSlug(ctx.category) then
            return false, "invalid_category"
        end
        return true
    end

    --- True when a provenance value represents a physically observed finish.
    function M.isPhysical(provenance)
        return provenance == M.Provenance.PHYSICAL
    end

    return M
end)
