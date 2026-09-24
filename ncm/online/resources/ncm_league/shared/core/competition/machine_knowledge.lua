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

    -- ---------------------------------------------------------------------------------------------
    -- How an observation reached us (IDEA-362, 31_CAPABILITY_AUDIT.md sections 3 and 7).
    -- ---------------------------------------------------------------------------------------------
    --
    -- `observed` is not one thing. The capability audit established that the observation surface is split and
    -- the halves do not overlap: the authoritative server snapshot carries `velocity` and `angularVelocity`
    -- and **no drivetrain**, while the client snapshot carries `rpm`/`throttle`/`brake`/`steering` and **no
    -- velocity vectors**. There is no `getThrottle` among the 138 server natives.
    --
    -- So a whole permanent class of future evidence can only ever be **attested by a client**, and the server
    -- cannot check it the way it checks an owner's motion report. Recording both under `observed` would make
    -- a measurement and a claim indistinguishable forever after.
    --
    -- Three values, because three things can actually happen, and no more:
    --   * `server_measured`  -- read from the authoritative server snapshot.
    --   * `client_attested`  -- read from a client snapshot and reported. Validated as far as it can be
    --                           (bucket, distance, plausibility), believed no further.
    --   * `derived_mixed`    -- computed from both, which understeer<->oversteer will require and nothing
    --                           does yet.
    --
    -- **Nil is legitimate and means unknown.** Every row written before this existed has an unknown basis, and
    -- inventing one retroactively is the fabrication section 12 forbids.
    M.BASIS = { server_measured = true, client_attested = true, derived_mixed = true }

    -- ---------------------------------------------------------------------------------------------
    -- Zero is a measurement. Absence is not (IDEA-361).
    -- ---------------------------------------------------------------------------------------------
    --
    -- The server motion half is *"all of it zeroed when the vehicle has no owner, because nobody is
    -- simulating it then"*, and `owner()` reports `physicsOwner = 0` for a parked car. The idiom
    -- `tonumber(v.speed) or 0` -- which this codebase uses today -- therefore turns *"I could not read it"*
    -- into *"it was stationary"*, and persists a fabricated observation that looks exactly like a real one.
    --
    -- **A parked car genuinely reading 0 km/h is valid evidence and must stay valid.** The distinction is not
    -- between zero and non-zero; it is between a value that was read and a value that was not. So: nil in,
    -- nil out, and zero survives untouched. Callers omit what came back nil rather than defaulting it.
    function M.reading(raw)
        if raw == nil then return nil end
        local n = tonumber(raw)
        if n == nil then return nil end
        if n ~= n then return nil end                       -- NaN
        if n == math.huge or n == -math.huge then return nil end
        return n
    end

    --- Every readable value of a candidate measurement table, and how many survived. A field that could not
    --- be read is **absent from the result**, never zero. An empty result is a legitimate answer and means
    --- this sample measured nothing -- callers write no numeric observation at all in that case.
    function M.measurements(candidate)
        if type(candidate) ~= "table" then return {}, 0 end
        local out, n = {}, 0
        for key, raw in pairs(candidate) do
            local v = M.reading(raw)
            if v ~= nil then out[key], n = v, n + 1 end
        end
        return out, n
    end

    -- ---------------------------------------------------------------------------------------------
    -- Configuration reference (31_CAPABILITY_AUDIT.md section 6).
    -- ---------------------------------------------------------------------------------------------
    --
    -- **There is no engine object for this to point at.** Build 2.31's entire vehicle customisation is one
    -- struct -- primary RGB, secondary RGB, a lights hue -- plus the entity appearance variant. `modEngine`,
    -- `modBrakes`, `modTransmission`, `modSuspension`, `modTurbo`, `wheels`, `wheelType`, `windowTint`,
    -- `neonEnabled`, `livery` and `extras` are not unimplemented; they are absent, with no RTTI type.
    --
    -- So `configuration_ref` can only ever reference an **NCM-authored configuration record**. That is now a
    -- settled question rather than an open one -- and the record does not exist yet, so nothing may write it.
    -- This function exists to say so at the boundary: it refuses every value, by name, until the substrate
    -- lands. A reserved column that silently accepts a guess is how a placeholder becomes ontology (L127).
    function M.configurationRef(value)
        if value == nil then return nil end
        return nil, "configuration_substrate_absent"
    end

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
        -- Optional, and nil means unknown rather than assumed: every row written before `BASIS` existed has
        -- an unknown basis and must keep it.
        if fact.basis ~= nil and not M.BASIS[fact.basis] then
            return nil, "unknown_basis:" .. tostring(fact.basis)
        end
        if fact.configurationRef ~= nil then
            local _, refWhy = M.configurationRef(fact.configurationRef)
            return nil, refWhy or "bad_configuration_ref"
        end
        local at = tonumber(fact.observedAt)
        if at == nil or at < 0 or math.floor(at) ~= at then return nil, "bad_observed_at" end
        if fact.assetId ~= nil and (type(fact.assetId) ~= "string" or fact.assetId == "") then
            return nil, "bad_asset_id"
        end
        return {
            driverId = fact.driverId, vehicleKey = fact.vehicleKey, assetId = fact.assetId,
            evidenceKey = fact.evidenceKey, kind = fact.kind, source = fact.source,
            epistemic = fact.epistemic, basis = fact.basis, observedAt = at,
            payloadJson = fact.payloadJson,
        }
    end

    --- Human prestige is deliberately narrower than knowledge acquisition. Only a physical world encounter
    --- may nominate another Driver; markets/listings/publications can reveal identity but never farm credit.
    function M.allowsHumanDiscoveryCredit(source)
        return source == "world_encounter"
    end

    return M
end)
