-- ncm-core module: competition.machine_knowledge
-- Small vocabulary/validation boundary for facts that enrich one Driver's automotive knowledge.
-- Persistence and observation authority stay with the host; this module prevents a market or future Scanner
-- adapter from collapsing source, epistemic status, model identity and persistent asset identity together.
local Core = NcmCore

Core.define("competition.machine_knowledge", function()
    local M = { version = "0.1.0" }

    M.SOURCES = {
        world_encounter = true,
        primary_market = true,
        secondary_listing = true,
        ownership = true,
        authored_display = true,
        manufacturer_publication = true,
    }

    M.KINDS = {
        identity_reveal = true,
        observed_speed_floor = true,
        observed_configuration = true,
        authoritative_specification = true,
    }

    M.EPISTEMIC = { observed = true, published = true, ownership_verified = true }

    --- Validate and normalize one durable item of evidence. Unknown remains absence of a row; callers must not
    --- manufacture facts to fill UI fields. `assetId` is optional because model knowledge and asset knowledge
    --- are distinct. `evidenceKey` is host-authored and makes retries safe.
    function M.evidence(fact)
        if type(fact) ~= "table" then return nil, "no_fact" end
        if type(fact.driverId) ~= "string" or fact.driverId == "" then return nil, "no_driver" end
        if type(fact.vehicleKey) ~= "string" or fact.vehicleKey == "" then return nil, "no_vehicle_key" end
        if type(fact.evidenceKey) ~= "string" or fact.evidenceKey == "" or #fact.evidenceKey > 190 then
            return nil, "bad_evidence_key"
        end
        if not M.KINDS[fact.kind] then return nil, "unknown_kind:" .. tostring(fact.kind) end
        if not M.SOURCES[fact.source] then return nil, "unknown_source:" .. tostring(fact.source) end
        if fact.epistemic ~= nil and not M.EPISTEMIC[fact.epistemic] then
            return nil, "unknown_epistemic:" .. tostring(fact.epistemic)
        end
        local at = tonumber(fact.observedAt)
        if at == nil or at < 0 or math.floor(at) ~= at then return nil, "bad_observed_at" end
        if fact.assetId ~= nil and (type(fact.assetId) ~= "string" or fact.assetId == "") then
            return nil, "bad_asset_id"
        end
        return {
            driverId = fact.driverId, vehicleKey = fact.vehicleKey, assetId = fact.assetId,
            evidenceKey = fact.evidenceKey, kind = fact.kind, source = fact.source,
            epistemic = fact.epistemic, observedAt = at, payloadJson = fact.payloadJson,
        }
    end

    --- Human prestige is deliberately narrower than knowledge acquisition. Only a physical world encounter
    --- may nominate another Driver; markets/listings/publications can reveal identity but never farm credit.
    function M.allowsHumanDiscoveryCredit(source)
        return source == "world_encounter"
    end

    return M
end)
