local KnockoutCircuits = {}

local Persist = require("modules/persistence")
local BuiltInCircuits = require("data/circuits")

local SAVE_FILE = "knockout_circuits.json"
local STORE_VERSION = 1
local MIN_CHECKPOINTS = 3
local MAX_CHECKPOINTS = 13

KnockoutCircuits._store = {
    version = STORE_VERSION,
    userCircuits = {},
}

KnockoutCircuits._runtimeById = {}
KnockoutCircuits._runtimeList = {}

local function clone(value)
    return Persist.clone and Persist.clone(value) or value
end

local function trim(text)
    if type(text) ~= "string" then return nil end
    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function slugify(text)
    local token = tostring(text or "circuit"):lower():gsub("%s+", "_")
    token = token:gsub("[^%w_]", "_"):gsub("_+", "_")
    token = token:gsub("^_+", ""):gsub("_+$", "")
    if token == "" then token = "circuit" end
    return token
end

local function stableHash(text)
    local hash = 5381
    local input = tostring(text or "")
    for i = 1, #input do
        hash = ((hash * 33) + input:byte(i)) % 4294967296
    end
    return string.format("%08x", hash)
end

local function defaultStore()
    return {
        version = STORE_VERSION,
        userCircuits = {},
    }
end

local function ensureStoreShape()
    local store = KnockoutCircuits._store or defaultStore()
    if type(store.userCircuits) ~= "table" then
        store.userCircuits = {}
    end
    store.version = STORE_VERSION
    KnockoutCircuits._store = store
end

local function getNodeLookup()
    local lookup = {}
    for _, node in ipairs((MTE and MTE.Nodes) or {}) do
        if type(node) == "table" and node.id then
            lookup[node.id] = node
        end
    end
    return lookup
end

local function estimateCircuitTime(checkpoints, nodeLookup)
    local distance = 0.0
    for index = 1, (#checkpoints - 1) do
        local left = nodeLookup[checkpoints[index]]
        local right = nodeLookup[checkpoints[index + 1]]
        if left and right then
            local dx = (right.x or 0) - (left.x or 0)
            local dy = (right.y or 0) - (left.y or 0)
            local dz = (right.z or 0) - (left.z or 0)
            distance = distance + math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
        end
    end
    local seconds = distance / 22.5
    return math.max(45, math.floor(seconds + 0.5))
end

local function buildCheckpointKnockoutSpec(checkpoints)
    local eliminationIds = {}
    for index = 2, (#checkpoints - 1) do
        eliminationIds[#eliminationIds + 1] = checkpoints[index]
    end
    return {
        eliminationMode = "checkpoint",
        maxFieldSize = math.max(2, #checkpoints - 1),
        eliminationCheckpointIds = eliminationIds,
        finalSprintStartCheckpointId = checkpoints[#checkpoints - 1],
        finishCheckpointId = checkpoints[#checkpoints],
    }
end

local function runtimeCircuitFromUser(entry, nodeLookup)
    local checkpoints = clone(entry.checkpoints) or {}
    local runtime = {
        id = entry.id,
        name = entry.name,
        region = entry.region,
        checkpoints = checkpoints,
        isLoop = false,
        estimatedLapTime = tonumber(entry.estimatedLapTime) or estimateCircuitTime(checkpoints, nodeLookup),
        knockout = buildCheckpointKnockoutSpec(checkpoints),
        source = "user",
        editable = true,
        createdAt = entry.createdAt,
        updatedAt = entry.updatedAt,
    }
    return runtime
end

local function runtimeCircuitFromBuiltIn(entry)
    local runtime = clone(entry) or {}
    runtime.source = "builtin"
    runtime.editable = false
    if type(runtime.knockout) == "table" and runtime.knockout.eliminationMode == "checkpoint" then
        runtime.knockout.maxFieldSize = math.min(
            tonumber(runtime.knockout.maxFieldSize) or math.max(2, #(runtime.checkpoints or {}) - 1),
            math.max(2, #(runtime.checkpoints or {}) - 1))
    end
    return runtime
end

local function rebuildRuntimeCache()
    ensureStoreShape()

    local byId = {}
    local list = {}
    for _, circuit in ipairs(BuiltInCircuits.all() or {}) do
        local runtime = runtimeCircuitFromBuiltIn(circuit)
        byId[runtime.id] = runtime
        list[#list + 1] = runtime
    end

    local nodeLookup = getNodeLookup()
    for _, circuit in ipairs(KnockoutCircuits._store.userCircuits or {}) do
        local runtime = runtimeCircuitFromUser(circuit, nodeLookup)
        byId[runtime.id] = runtime
        list[#list + 1] = runtime
    end

    table.sort(list, function(left, right)
        if left.source ~= right.source then
            return left.source == "user"
        end
        return string.lower(tostring(left.name or left.id or "")) < string.lower(tostring(right.name or right.id or ""))
    end)

    KnockoutCircuits._runtimeById = byId
    KnockoutCircuits._runtimeList = list
end

local function migrateStore(document)
    local store = defaultStore()
    if type(document) ~= "table" then
        return store
    end
    if type(document.userCircuits) == "table" then
        store.userCircuits = document.userCircuits
    end
    return store
end

local function getUserCircuitIndex(circuitId)
    for index, circuit in ipairs(KnockoutCircuits._store.userCircuits or {}) do
        if circuit.id == circuitId then
            return index
        end
    end
    return nil
end

local function sanitizeCheckpointIds(checkpoints, nodeLookup)
    local sanitized = {}
    local seen = {}
    for _, checkpointId in ipairs(checkpoints or {}) do
        if type(checkpointId) == "string" then
            local trimmed = trim(checkpointId)
            if trimmed then
                if seen[trimmed] then
                    return nil, string.format("Checkpoint '%s' is duplicated.", trimmed)
                end
                if not nodeLookup[trimmed] then
                    return nil, string.format("Checkpoint '%s' is not in the live node pool.", trimmed)
                end
                seen[trimmed] = true
                sanitized[#sanitized + 1] = trimmed
            end
        end
    end
    if #sanitized < MIN_CHECKPOINTS then
        return nil, string.format("Knockout circuits need at least %d nodes.", MIN_CHECKPOINTS)
    end
    if #sanitized > MAX_CHECKPOINTS then
        return nil, string.format("Knockout circuits are capped at %d nodes.", MAX_CHECKPOINTS)
    end
    return sanitized, nil
end

local function buildUserCircuitRecord(input, existingId)
    local nodeLookup = getNodeLookup()
    local name = trim(input and input.name)
    if not name then
        return nil, "Circuit name is required."
    end

    local checkpoints, err = sanitizeCheckpointIds(input and input.checkpoints or nil, nodeLookup)
    if not checkpoints then
        return nil, err
    end

    local now = os.time()
    local region = trim(input and input.region) or (nodeLookup[checkpoints[1]] and nodeLookup[checkpoints[1]].region) or "Night City"
    local record = {
        id = existingId,
        name = name,
        region = region,
        checkpoints = checkpoints,
        estimatedLapTime = estimateCircuitTime(checkpoints, nodeLookup),
        updatedAt = now,
    }

    if not record.id then
        record.id = string.format(
            "user_knockout_%s_%s",
            slugify(name),
            stableHash(table.concat(checkpoints, "|") .. "|" .. tostring(now)))
        record.createdAt = now
    else
        local existing = KnockoutCircuits.get(record.id)
        record.createdAt = existing and existing.createdAt or now
    end

    return record, nil
end

local function saveStore()
    ensureStoreShape()
    Persist.save(SAVE_FILE, KnockoutCircuits._store)
end

function KnockoutCircuits.init()
    local store = Persist.loadVersioned(SAVE_FILE, STORE_VERSION, defaultStore(), function(document)
        return migrateStore(document)
    end)
    KnockoutCircuits._store = store
    ensureStoreShape()
    rebuildRuntimeCache()
end

function KnockoutCircuits.save()
    saveStore()
    rebuildRuntimeCache()
    return true
end

function KnockoutCircuits.all()
    return clone(KnockoutCircuits._runtimeList)
end

function KnockoutCircuits.quickRaceAll()
    local circuits = {}
    for _, circuit in ipairs(KnockoutCircuits._runtimeList or {}) do
        if type(circuit.knockout) == "table" and circuit.knockout.eliminationMode == "checkpoint" then
            circuits[#circuits + 1] = clone(circuit)
        end
    end
    return circuits
end

function KnockoutCircuits.get(circuitId)
    local circuit = KnockoutCircuits._runtimeById and KnockoutCircuits._runtimeById[circuitId] or nil
    return circuit and clone(circuit) or nil
end

function KnockoutCircuits.getUserCircuits()
    local circuits = {}
    for _, circuit in ipairs(KnockoutCircuits._runtimeList or {}) do
        if circuit.source == "user" then
            circuits[#circuits + 1] = clone(circuit)
        end
    end
    return circuits
end

function KnockoutCircuits.getMaxTotalGridSize(circuit)
    local resolved = type(circuit) == "table" and circuit or KnockoutCircuits.get(circuit)
    if type(resolved) ~= "table" then
        return nil
    end
    if type(resolved.knockout) == "table" and resolved.knockout.eliminationMode == "checkpoint" then
        local checkpoints = #(resolved.checkpoints or {})
        if checkpoints <= 0 then return nil end
        local maxFieldSize = tonumber(resolved.knockout.maxFieldSize) or math.max(2, checkpoints - 1)
        return math.min(checkpoints, maxFieldSize + 1)
    end
    local checkpoints = #(resolved.checkpoints or {})
    return checkpoints > 0 and checkpoints or nil
end

function KnockoutCircuits.getMaxAIFieldSize(circuit)
    local total = KnockoutCircuits.getMaxTotalGridSize(circuit)
    if not total then return nil end
    return math.max(1, total - 1)
end

function KnockoutCircuits.upsertUserCircuit(input)
    ensureStoreShape()
    local existingId = trim(input and input.id)
    if existingId and not getUserCircuitIndex(existingId) then
        existingId = nil
    end

    local record, err = buildUserCircuitRecord(input, existingId)
    if not record then
        return nil, err
    end

    local index = getUserCircuitIndex(record.id)
    if index then
        KnockoutCircuits._store.userCircuits[index] = record
    else
        KnockoutCircuits._store.userCircuits[#KnockoutCircuits._store.userCircuits + 1] = record
    end

    saveStore()
    rebuildRuntimeCache()
    return KnockoutCircuits.get(record.id), nil
end

function KnockoutCircuits.deleteUserCircuit(circuitId)
    ensureStoreShape()
    local index = getUserCircuitIndex(circuitId)
    if not index then
        return false, "Circuit is not editable."
    end
    table.remove(KnockoutCircuits._store.userCircuits, index)
    saveStore()
    rebuildRuntimeCache()
    return true, nil
end

return KnockoutCircuits