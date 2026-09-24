-- Vehicle Collection: durable driver discovery of NCM-registered canonical machines (IDEA-134/L89).
-- Authority boundary: registry metadata comes from the server resource that created the vehicle; the polling
-- decision re-checks the authoritative OPEN//77 vehicle snapshot, player snapshot, bucket and dwell.
NcmCollection = {}

local Catalogue = NcmCore.get("data.vehicle_catalogue")
local Discoveries = NcmCore.get("competition.discoveries")
local Knowledge = NcmCore.get("competition.machine_knowledge")
local ids = NcmCore.get("vocabulary.ids")
local Seasons = NcmCore.get("competition.seasons")
local registered, dwell, cache = {}, {}, {}
local running = false
local RADIUS_M, DWELL_S, POLL_MS = 18.0, 3, 1000
local function now() return math.floor(Open77.time.unix()) end
local function serverId() return NcmCalendar.serverId() end
local hostRng = function() return math.random() end
local function log(fmt, ...) print(("[ncm_league/collection] " .. fmt):format(...)) end

--- The authoritative vehicle snapshot, resolved exactly ONCE and used by both the polling loop and the probe.
--- OPEN//77 returns flat coordinates on the snapshot (`vehicle.x/.y/.z`, as the platform's own `/vehicle.list`
--- prints); there is no `vehicles.getPosition`. A diagnostic that resolves position differently from the live
--- path is worse than no diagnostic, because it reports "candidate" for encounters that can never be awarded.
local function snapshot(liveId)
    local ok, v = pcall(Open77.vehicles.get, liveId)
    if not ok or type(v) ~= "table" then return nil end
    local pos = v.position
    if type(pos) ~= "table" then
        if type(v.x) ~= "number" or type(v.y) ~= "number" or type(v.z) ~= "number" then return nil end
        pos = { x = v.x, y = v.y, z = v.z }
    end
    return { record = v.record, bucket = v.bucket, resource = v.resource, pos = pos }
end

local function distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

--- Returns nil (NOT an empty table) when the read fails, and does not cache the failure.
--- An unreadable collection and an empty one are different facts: caching the failure would make every car the
--- driver has already discovered announce itself as new again for the rest of the session, and would report
--- their collection as 0 discovered.
local function load(driverId)
    if cache[driverId] then return cache[driverId] end
    local ok, rows = pcall(MySQL.query.await, "SELECT vehicle_key, first_discovered_at, last_encounter_at, encounter_count, discovery_method FROM vehicle_discovery WHERE ncm_driver_id = ? AND server_id = ?", { driverId, serverId() })
    if not ok or type(rows) ~= "table" then
        log("discovery read FAILED driver=%s: %s", driverId:sub(1, 8), tostring(rows))
        return nil
    end
    local found = {}
    for _, r in ipairs(rows) do found[r.vehicle_key] = r end
    cache[driverId] = found
    return found
end

--- The vehicleKeys this driver owns. Since IDEA-157 the ledger answers this directly and answers it better:
--- it prefers each asset's STORED key over re-resolving the record, so a machine whose record a mod update
--- renamed is still counted as the machine it is. Three examples of one car remain one completed slot.
local function ownedKeys(driverId)
    if not (NcmOwnership and NcmOwnership.keys) then return {} end
    return NcmOwnership.keys(driverId) or {}
end

function NcmCollection.payload(playerId)
    local driver = NcmCalendar.resolveDriver(tonumber(playerId) or 0)
    if not driver then return nil, "no_driver" end
    local found, owned = load(driver.ncmDriverId), ownedKeys(driver.ncmDriverId)
    if not found then return nil, "collection_unavailable" end
    local examples = {}
    for _, asset in ipairs(NcmOwnership.list(driver.ncmDriverId)) do
        if asset.vehicleKey then
            examples[asset.vehicleKey] = examples[asset.vehicleKey] or {}
            table.insert(examples[asset.vehicleKey], { assetId = asset.assetId })
        end
    end
    local slots, discovered, ownedCount = {}, 0, 0
    for _, e in ipairs(Catalogue.entries()) do
        local d, isOwned = found[e.vehicleKey], owned[e.vehicleKey] == true
        if d then discovered = discovered + 1 end
        if isOwned then ownedCount = ownedCount + 1 end
        local slot = { slot = Catalogue.slot(e), discovered = d ~= nil or isOwned, owned = isOwned,
            assets = examples[e.vehicleKey] }
        if d or isOwned then
            slot.vehicleKey, slot.displayName, slot.manufacturer = e.vehicleKey, e.displayName, e.manufacturer
            slot.category, slot.categories, slot.tags, slot.source = e.category, e.categories, e.tags, e.source
            if d then
                slot.firstDiscoveredAt, slot.lastEncounterAt, slot.encounterCount = tonumber(d.first_discovered_at), tonumber(d.last_encounter_at), tonumber(d.encounter_count)
            else discovered = discovered + 1 end
        end
        slots[#slots + 1] = slot
    end
    return { label = "Machine Index", generation = Catalogue.generation, discovered = discovered,
        total = Catalogue.count(), owned = ownedCount, slots = slots }
end

local function sendPayload(pid)
    local ok, payload = pcall(NcmCollection.payload, pid)
    if ok and payload then TriggerClientEvent("ncm:collection.payload", pid, payload) end
end

local function legacyRecordEncounter(pid, driver, entry, runtimeRecord, liveId, reg)
    local found = load(driver.ncmDriverId)
    -- unreadable history is not a first discovery: write the encounter, but stay silent rather than announce
    local first = found ~= nil and found[entry.vehicleKey] == nil
    local t = now()

    -- Who gets credit for showing this machine (spec 1 §A). The anti-farm rule is the primary key's job, not
    -- ours: one row per (driver, server, vehicleKey) means there is nowhere to write a second credit.
    local credit, why = Discoveries.credit({
        discovererId = driver.ncmDriverId,
        sourceDriverId = reg and reg.sourceDriverId or nil,
        sourceHolding = reg and reg.sourceHolding or nil,
        alreadyDiscovered = not first,
    })
    local srcId = credit and reg.sourceDriverId or ""
    local srcHolding = credit and (reg.sourceHolding or "unknown") or ""

    local ok, err = pcall(function()
        -- Source is written on INSERT ONLY and is deliberately absent from the UPDATE clause: driving past
        -- someone's car again months later must never rewrite who first showed it to you.
        --
        -- NULLIF(?, '') rather than a nil in the values array -- a nil mid-constructor truncates Lua's `#` and
        -- the statement arrives with fewer parameters than placeholders (the weather `invalid_parameters`
        -- defect, KB weather/saveMeta). Passing "" keeps the array dense and lets SQL produce the NULL.
        MySQL.insert.await([[INSERT INTO vehicle_discovery
            (ncm_driver_id, server_id, vehicle_key, first_discovered_at, last_encounter_at, encounter_count, discovery_method, first_runtime_record, source_driver_id, source_holding)
            VALUES (?, ?, ?, ?, ?, 1, 'proximity_dwell', ?, NULLIF(?, ''), NULLIF(?, ''))
            ON DUPLICATE KEY UPDATE last_encounter_at = VALUES(last_encounter_at), encounter_count = encounter_count + 1]],
            { driver.ncmDriverId, serverId(), entry.vehicleKey, t, t, runtimeRecord, srcId, srcHolding })
    end)
    if not ok then log("encounter write failed driver=%s key=%s: %s", driver.ncmDriverId:sub(1, 8), entry.vehicleKey, tostring(err)); return end
    if first then
        found[entry.vehicleKey] = { first_discovered_at = t, last_encounter_at = t, encounter_count = 1, discovery_method = "proximity_dwell" }
        local payload = NcmCollection.payload(pid)
        if payload then
            TriggerClientEvent("ncm:collection.payload", pid, payload)
            pcall(Open77.notifications.send, pid, { type = "success", title = "NEW VEHICLE DISCOVERED",
                message = ((entry.manufacturer or "") .. " " .. (entry.displayName or "")) ..
                    ("  ·  COLLECTION %d / %d"):format(payload.discovered, payload.total), icon = "NCM", durationMs = 6500 })
        end
        log("DISCOVERED driver=%s key=%s record=%s live_vehicle=%s source=%s holding=%s%s",
            driver.ncmDriverId:sub(1, 8), entry.vehicleKey, runtimeRecord, tostring(liveId),
            credit and srcId:sub(1, 8) or "none", credit and srcHolding or "-",
            credit and "" or (" (" .. tostring(why) .. ")"))
    -- QA T2/T3/T4: provenance is the one fact that cannot be reconstructed later (IDEA-137).
    -- `previousSource` is deliberately nil: this path does not load the stored source, so T3 (credit not
    -- rewritten) cannot be judged from here and is not claimed. The anti-farm property is enforced structurally
    -- anyway -- source is written on INSERT only, never in the ON DUPLICATE KEY UPDATE clause.
    pcall(TriggerEvent, "ncm:qa.discovery", driver.ncmDriverId,
        reg and reg.sourceDriverId or nil, nil, reg and reg.sourceHolding or nil)
    elseif found then
        local d = found[entry.vehicleKey]
        if d then d.last_encounter_at, d.encounter_count = t, (tonumber(d.encounter_count) or 0) + 1 end
    end
end

--- Record a legitimate identity reveal from a trusted NCM surface. This stays server-side: Market must first
--- prove that identifiable stock was actually exposed. The summary key and evidence key make retries safe.
function NcmCollection.revealIdentity(pid, vehicleKey, opts)
    opts = opts or {}
    local driver = NcmCalendar.resolveDriver(tonumber(pid) or 0)
    local entry = Catalogue.byKey(vehicleKey)
    if not driver then return nil, "no_driver" end
    if not entry then return nil, "unknown_vehicle_key" end

    local found = load(driver.ncmDriverId)
    local first = found ~= nil and found[entry.vehicleKey] == nil
    local t, source = tonumber(opts.observedAt) or now(), tostring(opts.source or "")
    local physical = source == "world_encounter"
    local evidence, evidenceWhy = Knowledge.evidence({
        driverId = driver.ncmDriverId, vehicleKey = entry.vehicleKey, assetId = opts.assetId,
        evidenceKey = "identity:" .. entry.vehicleKey, kind = "identity_reveal", source = source,
        epistemic = opts.epistemic or (physical and "observed" or "published"), observedAt = t,
    })
    if not evidence then return nil, evidenceWhy end

    local credit, why = Discoveries.credit({
        discovererId = driver.ncmDriverId, sourceDriverId = opts.sourceDriverId,
        sourceHolding = opts.sourceHolding, alreadyDiscovered = not first,
    })
    if not Knowledge.allowsHumanDiscoveryCredit(source) then credit, why = false, "source_has_no_human_credit" end
    local srcId = credit and opts.sourceDriverId or ""
    local srcHolding = credit and (opts.sourceHolding or "unknown") or ""
    local assetId = type(opts.assetId) == "string" and opts.assetId or ""
    -- **SQL 1292, live 2026-09-23.** `last_encounter_at` is a BIGINT, and the empty-string sentinel used for
    -- "no value" is a string: MariaDB rejects it with *truncated incorrect INTEGER value* and the whole
    -- transaction rolls back, so every identity reveal was silently lost. An empty string is a fine sentinel
    -- for a CHAR column and never for a numeric one -- so this one is 0, matched by `NULLIF(?, 0)` below.
    local lastEncounter, encounterCount = physical and t or 0, physical and 1 or 0

    local ok, err = pcall(function()
        local committed = MySQL.transaction.await({
            { query = [[INSERT IGNORE INTO vehicle_knowledge_evidence
                (evidence_id, evidence_key, ncm_driver_id, server_id, vehicle_key, asset_id,
                 knowledge_kind, source_kind, epistemic_kind, observed_at)
                VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?)]],
              values = { ids.uuid4(hostRng), evidence.evidenceKey, evidence.driverId, serverId(), evidence.vehicleKey,
                  assetId, evidence.kind, evidence.source, evidence.epistemic or "", evidence.observedAt } },
            { query = [[INSERT INTO vehicle_discovery
                (ncm_driver_id, server_id, vehicle_key, first_discovered_at, last_encounter_at, encounter_count,
                 discovery_method, first_runtime_record, source_driver_id, source_holding, source_asset_id)
                VALUES (?, ?, ?, ?, NULLIF(?, 0), ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''))
                ON DUPLICATE KEY UPDATE
                  last_encounter_at = IF(VALUES(last_encounter_at) IS NULL, last_encounter_at, VALUES(last_encounter_at)),
                  encounter_count = encounter_count + VALUES(encounter_count)]],
              values = { driver.ncmDriverId, serverId(), entry.vehicleKey, t, lastEncounter, encounterCount,
                  source, opts.runtimeRecord or "", srcId, srcHolding, assetId } },
        })
        if not committed then error("transaction_refused") end
    end)
    if not ok then
        log("identity reveal write failed driver=%s key=%s source=%s: %s",
            driver.ncmDriverId:sub(1, 8), entry.vehicleKey, source, tostring(err))
        return nil, "write_failed"
    end

    if first then
        found[entry.vehicleKey] = { first_discovered_at = t, last_encounter_at = physical and t or nil,
            encounter_count = encounterCount, discovery_method = source }
        local payload = NcmCollection.payload(pid)
        if payload then
            TriggerClientEvent("ncm:collection.payload", pid, payload)
            pcall(Open77.notifications.send, pid, { type = "success", title = "NEW VEHICLE DISCOVERED",
                message = ((entry.manufacturer or "") .. " " .. (entry.displayName or "")) ..
                    ("  ·  MACHINE INDEX %d / %d"):format(payload.discovered, payload.total), icon = "NCM", durationMs = 6500 })
        end
        log("DISCOVERED driver=%s key=%s method=%s record=%s live_vehicle=%s source=%s holding=%s%s",
            driver.ncmDriverId:sub(1, 8), entry.vehicleKey, source, tostring(opts.runtimeRecord), tostring(opts.liveId),
            credit and srcId:sub(1, 8) or "none", credit and srcHolding or "-",
            credit and "" or (" (" .. tostring(why) .. ")"))
    elseif found and physical then
        local d = found[entry.vehicleKey]
        if d then d.last_encounter_at, d.encounter_count = t, (tonumber(d.encounter_count) or 0) + 1 end
    end
    return first == true
end

-- Replace the legacy proximity-only adapter with the generalized identity seam above. The old function remains
-- immediately above as readable migration history until this foundation receives live QA.
local function recordEncounter(pid, driver, entry, runtimeRecord, liveId, reg)
    return NcmCollection.revealIdentity(pid, entry.vehicleKey, {
        source = "world_encounter", runtimeRecord = runtimeRecord, liveId = liveId,
        assetId = reg and reg.assetId or nil, sourceDriverId = reg and reg.sourceDriverId or nil,
        sourceHolding = reg and reg.sourceHolding or nil,
    })
end

-- Cross-resource host event emitted only by NCM's world vehicle owner. vehicleId is ephemeral registry key.
AddEventHandler("ncm:collection:registerVehicle", function(vehicleId, runtimeRecord, context, sourceDriverId, holding, assetId)
    local e = Catalogue.resolveRecord(runtimeRecord)
    if not e then log("ignored unrecognised record=%s vehicle=%s", tostring(runtimeRecord), tostring(vehicleId)); return end
    registered[tonumber(vehicleId) or vehicleId] = {
        vehicleKey = e.vehicleKey, runtimeRecord = runtimeRecord, context = tostring(context or "ncm"),
        sourceDriverId = type(sourceDriverId) == "string" and sourceDriverId ~= "" and sourceDriverId or nil,
        sourceHolding = Discoveries.HOLDINGS[holding] and holding or nil,
        assetId = type(assetId) == "string" and assetId ~= "" and assetId or nil,
    }
end)
AddEventHandler("ncm:collection:unregisterVehicle", function(vehicleId) registered[tonumber(vehicleId) or vehicleId] = nil end)

--- Read-only identity metadata for another NCM league subsystem. Runtime vehicle IDs are ephemeral; this is
--- observability only and never substitutes for the entrant/session authority checks.
function NcmCollection.vehicleInfo(vehicleId)
    return registered[tonumber(vehicleId) or vehicleId]
end

RegisterNetEvent("ncm:collection", function() sendPayload(tonumber(source) or 0) end)
RegisterCommand("ncm.collection", function(source) if (tonumber(source) or 0) > 0 then CreateThread(function() sendPayload(source) end) end end, false)
RegisterCommand("ncm.collection.probe", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.collection.probe <playerId>"); return end
    local p = Open77.players.get(pid)
    log("PROBE player=%d bucket=%s position=%s registered=%d", pid, tostring(p and p.bucket),
        p and p.position and ("%.1f,%.1f,%.1f"):format(p.position.x,p.position.y,p.position.z) or "unknown",
        (function() local n=0; for _ in pairs(registered) do n=n+1 end; return n end)())
    local unmapped, conflicts = Catalogue.unmapped(), Catalogue.conflicts()
    if #unmapped > 0 then log("PROBE catalogue UNMAPPED (%d): %s", #unmapped, table.concat(unmapped, ", ")) end
    if #conflicts > 0 then log("PROBE catalogue CONFLICTS (%d): %s", #conflicts, table.concat(conflicts, "; ")) end
    if not p or not p.position then return end
    for liveId, reg in pairs(registered) do
        local v = snapshot(liveId)
        local dist = v and distance(p.position, v.pos) or nil
        local verdict
        if not v then verdict = "reject:no_snapshot"
        elseif v.record ~= reg.runtimeRecord then verdict = "reject:record_mismatch"
        elseif tonumber(v.bucket) ~= tonumber(p.bucket or 0) then verdict = "reject:bucket"
        elseif dist > RADIUS_M then verdict = "reject:distance"
        else verdict = "candidate" end
        log("PROBE vehicle=%s key=%s registered_record=%s snapshot_record=%s player_bucket=%s vehicle_bucket=%s distance=%s verdict=%s",
            tostring(liveId), reg.vehicleKey, reg.runtimeRecord, tostring(v and v.record), tostring(p.bucket), tostring(v and v.bucket),
            dist and ("%.1fm"):format(dist) or "unknown", verdict)
    end
end, false)

--- ncm.inspired [days|season|YYYY-Sn] -- Discoveries Inspired standings (spec 1 §B).
--- Deliberately added with the columns rather than "later": provenance that nothing ever reads is how a
--- recording bug survives for months. This proves end to end that the rows can answer the question, and it is
--- the console form of the leaderboard the Collection will eventually show.
RegisterCommand("ncm.inspired", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local requested = args and args[1]
    local days = tonumber(requested)
    local season, seasonWhy
    if requested == "season" then season = Seasons.atUtc(now())
    elseif requested and not days then season, seasonWhy = Seasons.parse(requested) end
    if requested and not days and not season then
        log("usage: ncm.inspired [days|season|YYYY-Sn] (%s)", tostring(seasonWhy)); return
    end
    local fromUtc = season and season.startUtc or (days and (now() - math.floor(days * 86400)) or nil)
    local toUtc = season and season.endUtc or nil
    CreateThread(function()
        local ok, rows = pcall(MySQL.query.await,
            "SELECT ncm_driver_id, vehicle_key, source_driver_id, source_holding, first_discovered_at " ..
            "FROM vehicle_discovery WHERE server_id = ? AND source_driver_id IS NOT NULL", { serverId() })
        if not ok or type(rows) ~= "table" then log("inspired: read failed: %s", tostring(rows)); return end
        local facts = {}
        for _, r in ipairs(rows) do
            facts[#facts + 1] = { discovererId = r.ncm_driver_id, vehicleKey = r.vehicle_key,
                sourceDriverId = r.source_driver_id, sourceHolding = r.source_holding,
                firstDiscoveredAt = tonumber(r.first_discovered_at) }
        end
        local standings = Discoveries.inspired(facts, { fromUtc = fromUtc, toUtc = toUtc })
        log("DISCOVERIES INSPIRED %s -- %d driver(s) from %d attributed discoveries",
            season and season.id or (days and ("last " .. tostring(days) .. "d") or "all time"), #standings, #facts)
        for place, row in ipairs(standings) do
            log("  %2d. %s  %d inspired  %d driver(s) reached  %d machine(s) introduced",
                place, row.driverId:sub(1, 8), row.credits, row.driversReached, row.keysIntroduced)
        end
        if #standings == 0 then log("  (nobody has shown anyone a new machine yet)") end
    end)
end, false)

function NcmCollection.start()
    if running then return true end
    -- An unnameable machine must not be published into an immutable generation, because the generation can
    -- never be corrected afterwards. Refuse to start rather than freeze an authoring fault into history.
    local unmapped, conflicts = Catalogue.unmapped(), Catalogue.conflicts()
    if #unmapped > 0 then return nil, "catalogue_unmapped_records:" .. table.concat(unmapped, ",") end
    if #conflicts > 0 then return nil, "catalogue_conflicts:" .. table.concat(conflicts, ";") end

    local function readMembers()
        local ok, rows = pcall(MySQL.query.await, "SELECT vehicle_key FROM vehicle_catalogue_member WHERE generation_id = ?", { Catalogue.generation })
        if not ok then return nil, tostring(rows) end
        return rows or {}
    end

    -- Generation membership is immutable, but `vehicle_count` on the generation row is the DECLARED size, and
    -- that is what distinguishes the two cases a bare row count cannot tell apart: a publish that died halfway
    -- (declared == catalogue, rows missing -> finish it) from a catalogue that genuinely changed under a
    -- published generation (declared ~= catalogue -> refuse; bump the generation instead).
    local members, why = readMembers()
    if not members then return nil, "catalogue_membership_unreadable:" .. tostring(why) end

    local genRows = MySQL.query.await("SELECT vehicle_count FROM vehicle_catalogue_generation WHERE generation_id = ?", { Catalogue.generation }) or {}
    local declared = genRows[1] and tonumber(genRows[1].vehicle_count) or nil

    if declared ~= nil and declared ~= Catalogue.count() then
        return nil, ("catalogue_generation_changed_without_bump: generation %d published %d, catalogue now %d")
            :format(Catalogue.generation, declared, Catalogue.count())
    end

    if #members < Catalogue.count() then
        if declared == nil then
            MySQL.insert.await("INSERT INTO vehicle_catalogue_generation (generation_id, vehicle_count, published_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE vehicle_count = VALUES(vehicle_count)", { Catalogue.generation, Catalogue.count(), now() })
        else
            log("completing a partial generation %d publish: %d of %d members present", Catalogue.generation, #members, Catalogue.count())
        end
        -- IGNORE, so finishing an interrupted publish does not collide on the rows that did land
        for _, e in ipairs(Catalogue.entries()) do
            MySQL.insert.await("INSERT IGNORE INTO vehicle_catalogue_member (generation_id, vehicle_key) VALUES (?, ?)", { Catalogue.generation, e.vehicleKey })
        end
        members = readMembers() or {}
    end

    -- Verify what is actually in the table, not what we believe we wrote.
    local seen = {}; for _, r in ipairs(members) do seen[r.vehicle_key] = true end
    if #members ~= Catalogue.count() then
        return nil, ("catalogue_membership_incomplete: %d rows, %d entries"):format(#members, Catalogue.count())
    end
    for _, e in ipairs(Catalogue.entries()) do
        if not seen[e.vehicleKey] then return nil, "catalogue_generation_member_changed:" .. e.vehicleKey end
    end
    running = true
    CreateThread(function()
        while running do
            for _, rawPid in ipairs(Open77.players.all()) do
                local pid = tonumber(rawPid) or 0
                local driver, p = NcmCalendar.resolveDriver(pid), Open77.players.get(pid)
                if driver and p and p.position then
                    dwell[pid] = dwell[pid] or {}
                    for liveId, reg in pairs(registered) do
                        local v = snapshot(liveId)
                        local exact = v and v.record or nil
                        local same = v and v.bucket ~= nil and tonumber(v.bucket) == tonumber(p.bucket or 0)
                        local dist = same and distance(p.position, v.pos) or math.huge
                        local token = tostring(liveId)
                        -- identity is re-derived from the live snapshot's record, never from the registration:
                        -- the registry says which vehicle to watch, the snapshot says what it actually is
                        if same and dist <= RADIUS_M and exact == reg.runtimeRecord and Catalogue.resolveRecord(exact) == Catalogue.byKey(reg.vehicleKey) then
                            local d = dwell[pid][token] or { samples = 0, awarded = false }
                            d.samples = d.samples + 1; dwell[pid][token] = d
                            if d.samples >= DWELL_S and not d.awarded then
                                d.awarded = true
                                recordEncounter(pid, driver, Catalogue.byKey(reg.vehicleKey), exact, liveId, reg)
                            end
                        else dwell[pid][token] = nil end
                    end
                end
            end
            Wait(POLL_MS)
        end
    end)
    log("ready generation=%d vehicles=%d radius=%.1fm dwell=%ds", Catalogue.generation, Catalogue.count(), RADIUS_M, DWELL_S)
    return true
end

AddEventHandler("onPlayerDisconnected", function(pid)
    local id = tonumber(pid) or 0
    dwell[id] = nil
    -- the discovery cache is keyed by driver, not player, and nothing else evicts it: without this it grows
    -- for the life of the process
    local ok, driver = pcall(NcmCalendar.resolveDriver, id)
    if ok and driver and driver.ncmDriverId then cache[driver.ncmDriverId] = nil end
end)
