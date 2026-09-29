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
        -- `L197`: the Scanner is how a Driver deliberately identifies a machine in the world. Proximity no
        -- longer reveals identity; a scan does. A scan of a server-owned vehicle is `server_measured`, a scan
        -- of a vanilla per-client car is `client_attested` -- the source is the same act, the basis says how
        -- far the server could check it.
        scanner = true,
    }

    -- The five `observed_*` characteristics below are `31_CAPABILITY_AUDIT.md` section 9's "safe to define
    -- now" list, ruled on by the owner 2026-09-26. `observed_speed_floor` was already here and is REUSED
    -- rather than renamed: section 7 of the spec is that an observed 156 km/h supports *"at least 156"* and
    -- never a top-speed claim, and `floor` says that where `max` would not.
    --
    -- Units, value rules and the promotion decision live in `competition.observation`. This table is only
    -- the evidence vocabulary -- what a row is allowed to BE.
    M.KINDS = {
        identity_reveal = true,
        observed_speed_floor = true,
        observed_lateral_accel = true,
        observed_yaw_rate = true,
        observed_slip_angle = true,
        observed_speed_retention = true,
        observed_gradient = true,
        observed_configuration = true,
        authoritative_specification = true,
    }

    --- The kinds that are EMPIRICAL -- something was measured about a machine that was being simulated.
    --- They carry the extra obligations below (a basis, a live physics owner); `identity_reveal` and
    --- `authoritative_specification` do not, because nothing was measured to produce them.
    M.OBSERVATION_KINDS = {
        observed_speed_floor = true,
        observed_lateral_accel = true,
        observed_yaw_rate = true,
        observed_slip_angle = true,
        observed_speed_retention = true,
        observed_gradient = true,
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
    -- So `configuration_ref` can only ever reference an **NCM-authored configuration record**. That was a
    -- settled question with no answer yet, so for two migrations this function refused every value by name
    -- (`configuration_substrate_absent`) -- a reserved column that silently accepts a guess is how a
    -- placeholder becomes ontology (L127).
    --
    -- **Migration 031 built the record.** `machine_configuration.configuration_id CHAR(36)` is the
    -- NCM-authored configuration the audit predicted, with `machine_configuration_current` as its head
    -- pointer and an append-only revision chain behind it. The refusal has therefore done its job and is
    -- retired: the finding it protected (`IDEA-359` -- there are no engine components, so this can only ever
    -- name something NCM wrote) is unchanged and is exactly WHY the reference is legitimate now.
    --
    -- What replaces it is a shape rule, not trust. Both producers mint a real uuid4 -- `uuid4()` for a fit,
    -- and a deterministic seeded `uuid4` for the factory revision -- so anything that is not one is a caller
    -- bug rather than a configuration. **Nil still means unknown** and always will: a market card view has no
    -- configuration, and a historical row has one nobody recorded.
    local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    function M.configurationRef(value)
        if value == nil then return nil end
        if type(value) ~= "string" or #value ~= 36 or not value:match(UUID) then
            return nil, "bad_configuration_ref"
        end
        return value
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
        local configurationRef
        if fact.configurationRef ~= nil then
            local ref, refWhy = M.configurationRef(fact.configurationRef)
            if not ref then return nil, refWhy or "bad_configuration_ref" end
            configurationRef = ref
        end
        -- -----------------------------------------------------------------------------------------
        -- What an EMPIRICAL claim owes that an identity reveal does not (31_CAPABILITY_AUDIT.md section 7).
        -- -----------------------------------------------------------------------------------------
        --
        -- **A parked car reads zero, not unknown.** The server motion half is *"all of it the last thing the
        -- physics owner reported, and all of it zeroed when the vehicle has no owner, because nobody is
        -- simulating it then"*. A sampler that does not check ownership faithfully persists `0 km/h` as an
        -- observation, and it is indistinguishable from a real one forever after.
        --
        -- So the refusal is here, at the boundary, rather than in each caller's head. An observation must
        -- name how it reached us and must attest that something was actually simulating the machine.
        -- `physicsOwnerPresent` is deliberately NOT a stored column: it is a precondition for the row
        -- existing at all, so a row that exists already answers it.
        if M.OBSERVATION_KINDS[fact.kind] then
            if fact.basis == nil then return nil, "observation_without_basis" end
            if fact.physicsOwnerPresent ~= true then return nil, "observation_without_physics_owner" end
        end
        -- Tri-state and nil is the default. `owner().aiDriven` says whether a machine was under platform AI,
        -- and section 7 is that an NPC-driven car is not a driver's achievement. But a build that does not
        -- report it, or a read that failed, must leave this UNKNOWN rather than quietly claiming `false`.
        if fact.aiDriven ~= nil and type(fact.aiDriven) ~= "boolean" then return nil, "bad_ai_driven" end
        local at = tonumber(fact.observedAt)
        if at == nil or at < 0 or math.floor(at) ~= at then return nil, "bad_observed_at" end
        if fact.assetId ~= nil and (type(fact.assetId) ~= "string" or fact.assetId == "") then
            return nil, "bad_asset_id"
        end
        return {
            driverId = fact.driverId, vehicleKey = fact.vehicleKey, assetId = fact.assetId,
            evidenceKey = fact.evidenceKey, kind = fact.kind, source = fact.source,
            epistemic = fact.epistemic, basis = fact.basis, observedAt = at,
            configurationRef = configurationRef, aiDriven = fact.aiDriven,
            payloadJson = fact.payloadJson,
        }
    end

    --- Human prestige is deliberately narrower than knowledge acquisition. Only a physical world encounter
    --- may nominate another Driver; markets/listings/publications can reveal identity but never farm credit.
    --- A scan is a physical encounter made deliberate (`L197`), so it may credit the Driver whose car was
    --- scanned, exactly as the proximity dwell it replaces did.
    function M.allowsHumanDiscoveryCredit(source)
        return source == "world_encounter" or source == "scanner"
    end

    return M
end)
