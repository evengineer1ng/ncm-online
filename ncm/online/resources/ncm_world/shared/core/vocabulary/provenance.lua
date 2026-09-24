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
