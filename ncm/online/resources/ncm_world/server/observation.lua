-- ncm_world / server / observation -- what this machine has been SEEN doing.
--
-- `31_CAPABILITY_AUDIT.md` section 9's first typed observation vocabulary, wired to the one loop that
-- already has authoritative readings in hand. Ruled on 2026-09-26.
--
-- ---------------------------------------------------------------------------------------------
-- Why this lives here, and why it adds no sampling
-- ---------------------------------------------------------------------------------------------
--
-- The odometer already calls `Open77.vehicles.get(vehicleId)` on the SERVER at 1 Hz for every materialised
-- machine, already reads speed through an availability check, and already derives cornering load for the
-- thermal model -- then throws all of it away once the tyre has warmed. That is the same shape as the
-- argument that justified migration 028 one level up: the measurement is in hand and discarded, and a
-- measurement not taken cannot be taken later.
--
-- So this file opens no loop, reads no snapshot and costs no native call per sample. `odometer.step` hands
-- it the facts it has already gathered, exactly as it already hands them to `thermalStep`.
--
-- `ncm_world` is the right resource for it even though `ncm_league` owns the table: only this side has the
-- live vehicle id, the physics owner and the configuration head, and both resources share one database.
--
-- ---------------------------------------------------------------------------------------------
-- What it refuses to write, which is most of what it sees
-- ---------------------------------------------------------------------------------------------
--
--   * A reading below the characteristic's floor. A car doing 12 km/h has demonstrated nothing.
--   * A reading that is not materially better than the stored best (`competition.observation.promote`).
--     At 1 Hz, without this, a single drive would write hundreds of near-identical rows and bury the few
--     that a player could actually go and investigate.
--   * Anything measured while nothing was simulating the machine. Section 7: the server motion half is
--     *"all of it zeroed when the vehicle has no owner"*, so an unowned car reads a confident 0. The floor
--     already rejects that zero; the owner check makes it a stated rule rather than a lucky consequence.
--   * Anything about a machine whose model or owner could not be resolved. Unknown stays absent.
--
-- What every surviving row carries: the knowledge owner, the world, the model, **the serialised machine**,
-- the characteristic and its unit, the value, `server_measured` basis, whether an NPC was driving, the
-- configuration the machine was in, WHERE it happened, and when. That list is `28` section 22's minimum
-- provenance, and the parts of it that are irrecoverable are the reason this is worth doing before the
-- estimator rather than after it.
--
-- There is no estimator here and no envelope. Evidence first.
NcmObservation = {}

local Knowledge = NcmCore.get("competition.machine_knowledge")
local Obs = NcmCore.get("competition.observation")
local ids = NcmCore.get("vocabulary.ids")
local Json = NcmCore.get("vocabulary.json")
local hostRng = function() return math.random() end
local function log(fmt, ...) print(("[ncm_world/observation] " .. fmt):format(...)) end
local function serverId()
    local ok, v = pcall(function() return GlobalState.ncmIdentity end)
    return ok and v and v.serverId or "ncm-dev"
end

local NO_POS = -999999

-- The running best per (knowledge owner, machine, characteristic). `false` means "looked, found none",
-- which is cached as deliberately as a hit: without it every sample of a machine nobody has an observation
-- for would re-query.
local best = {}
local vehicleKeys = {}          -- assetId -> vehicleKey | false. Immutable for the life of the asset.
local counters = { promoted = 0, written = 0, refused = 0 }

local function bestKey(driverId, assetId, kind) return driverId .. "|" .. assetId .. "|" .. kind end

--- The model this machine is an example of. Cached because `vehicle_asset.vehicle_key` never changes for a
--- given asset, and this would otherwise be read once per sample.
local function vehicleKeyOf(assetId)
    local hit = vehicleKeys[assetId]
    if hit ~= nil then return hit or nil end
    local ok, key = pcall(MySQL.scalar.await,
        "SELECT vehicle_key FROM vehicle_asset WHERE asset_id = ? AND server_id = ?", { assetId, serverId() })
    vehicleKeys[assetId] = (ok and type(key) == "string" and key ~= "") and key or false
    return vehicleKeys[assetId] or nil
end

--- The stored best for this characteristic, or nil if there is none.
---
--- Read as the LATEST row rather than the maximum, which is equivalent here and cheaper: a row is only ever
--- written when it beats the stored best, so the newest is the highest by construction. Uses the
--- `ix_evidence_running_best` index added by migration 033.
local function priorOf(driverId, assetId, kind)
    local k = bestKey(driverId, assetId, kind)
    local cached = best[k]
    if cached ~= nil then return cached or nil end
    local ok, row = pcall(MySQL.single.await, [[SELECT evidence_json FROM vehicle_knowledge_evidence
        WHERE ncm_driver_id = ? AND asset_id = ? AND knowledge_kind = ?
        ORDER BY observed_at DESC LIMIT 1]], { driverId, assetId, kind })
    local value
    if ok and row and row.evidence_json then
        local okDec, decoded = pcall(Json.decode, tostring(row.evidence_json))
        value = okDec and type(decoded) == "table" and tonumber(decoded.value) or nil
    end
    best[k] = value or false
    return value
end

--- Who, if anyone, is actually simulating this machine -- and whether it was platform AI at the wheel.
---
--- Returns `present, aiDriven`. `aiDriven` is **tri-state**: nil means the build did not say, and that is
--- written as unknown rather than as `false`. A read that fails is not evidence that a human drove.
local function authority(vehicleId)
    local ok, owner = pcall(Open77.vehicles.owner, vehicleId)
    if not ok or type(owner) ~= "table" then return false, nil end
    local physicsOwner = tonumber(owner.physicsOwner or owner.authorityPlayerId) or 0
    local ai
    if type(owner.aiDriven) == "boolean" then ai = owner.aiDriven end
    return physicsOwner > 0, ai
end

--- Persist one promoted observation. Returns true when a row was written.
local function write(driverId, assetId, vehicleKey, kind, value, aiDriven, pos, t)
    local body, bodyWhy = Obs.body(kind, value)
    if not body then counters.refused = counters.refused + 1; return false, bodyWhy end

    -- The retry key encodes the VALUE, not just the characteristic. An identity reveal happens once per
    -- model and its key says so; an observation legitimately happens again whenever the machine does
    -- better, so a fixed key would silently keep only the first. Bucketing to the integer makes a retried
    -- write of the same promotion a no-op through `INSERT IGNORE`, which is what idempotency needs here.
    local evidenceKey = ("obs:%s:%s:%d"):format(kind, assetId, math.floor(value))

    local configurationRef
    if NcmComponentInstall and NcmComponentInstall.currentConfiguration then
        local okCfg, cfg = pcall(NcmComponentInstall.currentConfiguration, assetId)
        -- A machine with no configuration, or an unreadable one, writes NULL. It never borrows another's.
        if okCfg then configurationRef = cfg end
    end

    local fact, why = Knowledge.evidence({
        driverId = driverId, vehicleKey = vehicleKey, assetId = assetId, evidenceKey = evidenceKey,
        kind = kind, source = "world_encounter", epistemic = "observed",
        -- Read from the authoritative server snapshot, so it is a measurement and says so. The
        -- `client_attested` half of `BASIS` stays unused until there is a design for believing an observer
        -- about somebody else's car.
        basis = "server_measured", physicsOwnerPresent = true, aiDriven = aiDriven,
        configurationRef = configurationRef, observedAt = t,
    })
    if not fact then
        counters.refused = counters.refused + 1
        log("refused %s asset=%s: %s", kind, tostring(assetId):sub(-6), tostring(why))
        return false, why
    end

    local okIns, err = pcall(MySQL.insert.await, [[INSERT IGNORE INTO vehicle_knowledge_evidence
        (evidence_id, evidence_key, ncm_driver_id, server_id, vehicle_key, asset_id,
         knowledge_kind, source_kind, epistemic_kind, observation_basis, evidence_json, observed_at,
         obs_x, obs_y, obs_z, configuration_ref, ai_driven)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                NULLIF(?, -999999), NULLIF(?, -999999), NULLIF(?, -999999), NULLIF(?, ''), NULLIF(?, -1))]],
        -- Sentinels, not nils: a nil in a MySQL params array truncates the sequence and fails the whole
        -- insert -- the trap that cost `collection.lua` a live identity-reveal outage (SQL 1292). -999999 is
        -- outside Night City, and -1 cannot be confused with `ai_driven = 0`, which is a real claim.
        { ids.uuid4(hostRng), fact.evidenceKey, fact.driverId, serverId(), fact.vehicleKey, fact.assetId,
          fact.kind, fact.source, fact.epistemic, fact.basis, Json.encode(body), fact.observedAt,
          pos and pos.x or NO_POS, pos and pos.y or NO_POS, pos and pos.z or NO_POS,
          fact.configurationRef or "",
          fact.aiDriven == nil and -1 or (fact.aiDriven and 1 or 0) })
    if not okIns then
        counters.refused = counters.refused + 1
        log("write failed %s asset=%s: %s", kind, tostring(assetId):sub(-6), tostring(err))
        return false, "insert_failed"
    end
    counters.written = counters.written + 1
    log("%s asset=%s %.1f %s at (%.0f, %.0f) cfg=%s ai=%s", kind, tostring(assetId):sub(-6), value,
        Obs.CHARACTERISTICS[kind].unit, pos and pos.x or 0, pos and pos.y or 0,
        configurationRef and configurationRef:sub(1, 8) or "none",
        aiDriven == nil and "unknown" or tostring(aiDriven))
    return true
end

--- Offer one characteristic's reading for this sample. Cheap, and almost always a no-op.
local function offer(driverId, assetId, vehicleKey, kind, raw, entry, cur, t)
    local prior = priorOf(driverId, assetId, kind)
    local ok, valueOrWhy = Obs.promote(kind, raw, prior)
    if not ok then return end
    counters.promoted = counters.promoted + 1

    -- Provenance is paid for ONLY here, at the moment a row is actually going to be written -- which is
    -- rare. Checking the physics owner on every 1 Hz sample would be a native call per machine per second
    -- to answer a question that almost never matters.
    local present, aiDriven = authority(entry.vehicleId)
    if not present then
        -- Section 7's hazard, caught rather than persisted: nothing was simulating this machine, so the
        -- reading describes nobody's driving.
        counters.refused = counters.refused + 1
        return
    end

    local value = valueOrWhy
    if write(driverId, assetId, vehicleKey, kind, value, aiDriven,
             { x = cur.x, y = cur.y, z = cur.z }, t) then
        best[bestKey(driverId, assetId, kind)] = value
    end
end

--- One sample, from the odometer's existing 1 Hz server loop. `lateral` is the cornering load it has
--- already derived for the thermal model, in m/s2; nil when it could not be derived.
---
--- Deliberately silent about everything it cannot honestly say. The four characteristics
--- `competition.observation` declares but does not mark `wired` are absent here on purpose: they need
--- `velocity`/`angularVelocity` fields this loop does not read, and a vocabulary entry with an invented
--- producer is worse than one with none.
function NcmObservation.sample(entry, cur, lateral, t)
    if type(entry) ~= "table" or type(cur) ~= "table" then return end
    local assetId, pid = entry.assetId, tonumber(entry.pid)
    if type(assetId) ~= "string" or assetId == "" or not pid or pid <= 0 then return end

    -- The knowledge owner is whoever WITNESSED this. In a low-population world a driver populates much of
    -- their own evidence, and `28` section 14 says that is expected rather than a degenerate case.
    local profile = NcmIdentity and NcmIdentity.get and NcmIdentity.get(pid) or nil
    local driverId = profile and profile.ncmDriverId
    if type(driverId) ~= "string" or driverId == "" then return end

    local vehicleKey = vehicleKeyOf(assetId)
    if not vehicleKey then return end

    local speedMps = tonumber(cur.speedMps)
    if speedMps then
        offer(driverId, assetId, vehicleKey, "observed_speed_floor", speedMps * 3.6, entry, cur, t)
    end
    if tonumber(lateral) then
        offer(driverId, assetId, vehicleKey, "observed_lateral_accel", lateral, entry, cur, t)
    end
end

--- Drop the cached bests for a machine nobody is sampling any more. Purely a memory concern -- the durable
--- answer is in the table, and the next sample re-reads it.
function NcmObservation.forget(assetId)
    if type(assetId) ~= "string" or assetId == "" then return end
    for k in pairs(best) do
        if k:find(assetId, 1, true) then best[k] = nil end
    end
end

--- What the vocabulary currently declares and which half of it has a producer. Prints rather than returns,
--- because the point is to be readable in a server console next to the odometer's own diagnostics.
RegisterCommand("ncm.observations", function()
    log("wired=%s promoted=%d written=%d refused=%d", table.concat(Obs.wired(), ","),
        counters.promoted, counters.written, counters.refused)
    for _, row in ipairs(Obs.inventory()) do
        print(("  %-26s %-7s %s"):format(row.kind, row.unit, row.wired and "WIRED" or "declared, no producer"))
    end
end, true)
