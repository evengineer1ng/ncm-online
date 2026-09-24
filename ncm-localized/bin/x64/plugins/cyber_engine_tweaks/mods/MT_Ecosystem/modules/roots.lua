local Roots = {}

local Persist = require("modules/persistence")
local Nodes = require("data/nodes")
local DefaultPack = require("data/default_roots_pack")

local ROOTS_FILE = "roots.json"
local STORE_VERSION = 1

Roots._store = {
    version = STORE_VERSION,
    activePack = nil,
    roots = {},
}
Roots._initialized = false
Roots._index = {
    directed = {},
    canonical = {},
}

local function clone(value)
    return Persist.clone and Persist.clone(value) or value
end

local function now()
    return os.time()
end

local function trim(text)
    if type(text) ~= "string" then return nil end
    local value = text:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

local function sanitizeToken(text)
    local token = tostring(text or "root"):lower():gsub("%s+", "_")
    token = token:gsub("[^%w_]", "_"):gsub("_+", "_")
    token = token:gsub("^_+", ""):gsub("_+$", "")
    if token == "" then token = "root" end
    return token
end

local function stableHash(text)
    local hash = 5381
    local input = tostring(text or "")
    for index = 1, #input do
        hash = ((hash * 33) + input:byte(index)) % 4294967296
    end
    return string.format("%08x", hash)
end

local function sortPair(left, right)
    left = tostring(left or "?")
    right = tostring(right or "?")
    if left <= right then return left, right end
    return right, left
end

local function canonicalPairKey(startNodeId, finishNodeId)
    local left, right = sortPair(startNodeId, finishNodeId)
    return left .. "|" .. right
end

local function directedKey(startNodeId, finishNodeId)
    return tostring(startNodeId or "?") .. "->" .. tostring(finishNodeId or "?")
end

local function deriveRootId(startNodeId, finishNodeId, nodeIds)
    if type(nodeIds) == "table" and #nodeIds > 2 then
        return "root_"
            .. sanitizeToken(nodeIds[1])
            .. "__to__"
            .. sanitizeToken(nodeIds[#nodeIds])
            .. "__"
            .. stableHash(table.concat(nodeIds, "|"))
    end
    return "root_" .. sanitizeToken(startNodeId) .. "__to__" .. sanitizeToken(finishNodeId)
end

local function copyPackMeta(pack)
    return {
        packId = pack and pack.packId or DefaultPack.packId,
        packName = pack and pack.packName or DefaultPack.packName,
        version = pack and pack.version or DefaultPack.version,
        description = pack and pack.description or DefaultPack.description,
    }
end

local function defaultStore()
    return {
        version = STORE_VERSION,
        activePack = copyPackMeta(DefaultPack),
        roots = {},
    }
end

local function ensureStoreShape()
    local store = Roots._store or defaultStore()
    if type(store.roots) ~= "table" then store.roots = {} end
    if type(store.activePack) ~= "table" then
        store.activePack = copyPackMeta(DefaultPack)
    end
    store.version = STORE_VERSION
    Roots._store = store
end

local function snapshotNode(node)
    if type(node) ~= "table" then return nil end
    return {
        id = node.id,
        name = node.name,
        region = node.region,
        x = node.x,
        y = node.y,
        z = node.z,
        heading = node.heading,
        finishHeading = node.finishHeading,
        finishWidthM = node.finishWidthM,
        finishArmDistM = node.finishArmDistM,
        road = node.road,
        urban = node.urban,
        waypointable = node.waypointable,
        raceLegal = node.raceLegal,
    }
end

local getNode
local dist3d

local function normalizeNodeIdList(nodeIds, startNodeId, finishNodeId)
    local normalized = {}
    local source = type(nodeIds) == "table" and nodeIds or { startNodeId, finishNodeId }
    local previousId = nil

    for _, rawNodeId in ipairs(source) do
        local nodeId = trim(rawNodeId)
        if nodeId and nodeId ~= previousId then
            normalized[#normalized + 1] = nodeId
            previousId = nodeId
        end
    end

    if #normalized <= 0 then
        return nil
    end
    return normalized
end

local function resolveNodeList(nodeIds)
    local resolved = {}
    local errors = {}
    for index, nodeId in ipairs(nodeIds or {}) do
        local node = getNode(nodeId)
        if node then
            resolved[#resolved + 1] = node
        else
            errors[#errors + 1] = string.format("Missing route node #%d: %s", index, tostring(nodeId))
        end
    end
    return resolved, errors
end

local function pathDistance(nodes)
    local totalDistance = 0.0
    for index = 2, #(nodes or {}) do
        totalDistance = totalDistance + dist3d(nodes[index - 1], nodes[index])
    end
    return totalDistance
end

local function hasAtLeastTwoDistinctNodeIds(nodeIds)
    local firstId = nil
    for _, nodeId in ipairs(nodeIds or {}) do
        if not firstId then
            firstId = nodeId
        elseif nodeId ~= firstId then
            return true
        end
    end
    return false
end

getNode = function(nodeId)
    if not nodeId or not Nodes or not Nodes.findById then return nil end
    return Nodes.findById(nodeId)
end

dist3d = function(nodeA, nodeB)
    if not nodeA or not nodeB then return 0.0 end
    local dx = (nodeA.x or 0) - (nodeB.x or 0)
    local dy = (nodeA.y or 0) - (nodeB.y or 0)
    local dz = (nodeA.z or 0) - (nodeB.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function deriveAutoLabel(root, nodeA, nodeB)
    local startLabel = nodeA and nodeA.name or root.startNodeName or root.startNodeId or "?"
    local finishLabel = nodeB and nodeB.name or root.finishNodeName or root.endNodeId or "?"
    if root.isLoop == true then
        return tostring(startLabel) .. " Loop"
    end
    return tostring(startLabel) .. " -> " .. tostring(finishLabel)
end

local function deriveDistrictLabel(root, nodeA, nodeB)
    local startRegion = nodeA and nodeA.region or nil
    local finishRegion = nodeB and nodeB.region or nil
    if startRegion and startRegion ~= "" and finishRegion and finishRegion ~= "" then
        if startRegion == finishRegion then
            return startRegion
        end
        return startRegion .. " -> " .. finishRegion
    end
    return startRegion or finishRegion or root.districtLabel or "Unknown"
end

local function normalizeRecommendedMode(mode)
    local value = trim(mode)
    if value == "sprint" or value == "drag" or value == "knockout" then
        return value
    end
    return nil
end

local function primaryLabel(root)
    return root.displayName or root.autoLabel or "[Invalid Root]"
end

local function secondaryLabel(root)
    local subtitle = trim(root.subtitleOverride)
    if subtitle then return subtitle end
    if root.displayName and root.autoLabel and root.autoLabel ~= root.displayName then
        return root.autoLabel
    end
    return nil
end

local function normalizeRoot(root)
    local normalized = clone(root or {})
    normalized.nodeIds = normalizeNodeIdList(normalized.nodeIds, normalized.startNodeId, normalized.endNodeId)
    normalized.startNodeId = normalized.nodeIds and normalized.nodeIds[1] or trim(normalized.startNodeId)
    normalized.endNodeId = normalized.nodeIds and normalized.nodeIds[#normalized.nodeIds] or trim(normalized.endNodeId)
    normalized.rootId = trim(normalized.rootId)
        or deriveRootId(normalized.startNodeId or "start", normalized.endNodeId or "finish", normalized.nodeIds)
    normalized.displayName = trim(normalized.displayName)
    normalized.subtitleOverride = trim(normalized.subtitleOverride)
    normalized.recommendedMode = normalizeRecommendedMode(normalized.recommendedMode)
    normalized.tags = type(normalized.tags) == "table" and clone(normalized.tags) or {}
    normalized.profileSettings = type(normalized.profileSettings) == "table" and clone(normalized.profileSettings) or nil
    normalized.isDefaultPackRoot = normalized.isDefaultPackRoot == true
    if normalized.createdByUser == nil then
        normalized.createdByUser = not normalized.isDefaultPackRoot
    else
        normalized.createdByUser = normalized.createdByUser == true
    end
    if normalized.isDefaultPackRoot then
        normalized.sourcePackId = trim(normalized.sourcePackId) or DefaultPack.packId
    else
        normalized.sourcePackId = trim(normalized.sourcePackId)
    end
    normalized.createdAt = normalized.createdAt or now()
    normalized.updatedAt = normalized.updatedAt or normalized.createdAt

    local resolvedNodes, nodeErrors = resolveNodeList(normalized.nodeIds)
    local nodeA = normalized.startNodeId and getNode(normalized.startNodeId) or nil
    local nodeB = normalized.endNodeId and getNode(normalized.endNodeId) or nil
    local validationErrors = {}

    if not normalized.nodeIds or #normalized.nodeIds < 2 then
        validationErrors[#validationErrors + 1] = "Roots need at least two ordered nodes."
    elseif not hasAtLeastTwoDistinctNodeIds(normalized.nodeIds) then
        validationErrors[#validationErrors + 1] = "Roots need at least two distinct nodes."
    end

    for _, err in ipairs(nodeErrors) do
        validationErrors[#validationErrors + 1] = err
    end

    normalized.nodeCount = normalized.nodeIds and #normalized.nodeIds or 0
    normalized.isLoop = normalized.nodeCount > 2 and normalized.startNodeId ~= nil and normalized.startNodeId == normalized.endNodeId
    normalized.nodeNames = {}
    for index, nodeId in ipairs(normalized.nodeIds or {}) do
        local node = getNode(nodeId)
        normalized.nodeNames[index] = node and node.name or nodeId
    end

    normalized.startNodeName = nodeA and nodeA.name or normalized.startNodeName or normalized.startNodeId
    normalized.finishNodeName = nodeB and nodeB.name or normalized.finishNodeName or normalized.endNodeId
    normalized.autoLabel = deriveAutoLabel(normalized, nodeA, nodeB)
    normalized.districtLabel = deriveDistrictLabel(normalized, nodeA, nodeB)
    if #resolvedNodes >= 2 and #nodeErrors <= 0 then
        normalized.distanceM = pathDistance(resolvedNodes)
    else
        normalized.distanceM = tonumber(normalized.distanceM) or 0.0
    end
    normalized.directedKey = directedKey(normalized.startNodeId, normalized.endNodeId)
    normalized.canonicalPairKey = canonicalPairKey(normalized.startNodeId, normalized.endNodeId)
    normalized.isValid = #validationErrors == 0
    normalized.validationErrors = validationErrors
    return normalized
end

local function rebuildIndex()
    ensureStoreShape()
    local directed = {}
    local canonical = {}
    local roots = {}

    for _, root in pairs(Roots._store.roots) do
        local normalized = normalizeRoot(root)
        roots[normalized.rootId] = normalized
        directed[normalized.directedKey] = normalized.rootId
        local bucket = canonical[normalized.canonicalPairKey]
        if type(bucket) ~= "table" then
            bucket = {}
            canonical[normalized.canonicalPairKey] = bucket
        end
        bucket[#bucket + 1] = normalized.rootId
    end

    for _, bucket in pairs(canonical) do
        table.sort(bucket)
    end

    Roots._store.roots = roots
    Roots._index = {
        directed = directed,
        canonical = canonical,
    }
end

local function importPackIntoStore(store, pack)
    local roots = pack and pack.roots or {}
    for _, root in ipairs(roots) do
        local imported = clone(root)
        imported.isDefaultPackRoot = true
        imported.createdByUser = false
        imported.sourcePackId = pack.packId
        local normalized = normalizeRoot(imported)
        local existing = store.roots[normalized.rootId]
        if type(existing) == "table" then
            normalized.displayName = trim(existing.displayName) or normalized.displayName
            normalized.subtitleOverride = trim(existing.subtitleOverride) or normalized.subtitleOverride
            normalized.tags = type(existing.tags) == "table" and clone(existing.tags) or normalized.tags
            normalized.recommendedMode = normalizeRecommendedMode(existing.recommendedMode) or normalized.recommendedMode
            normalized.profileSettings = type(existing.profileSettings) == "table" and clone(existing.profileSettings) or normalized.profileSettings
            normalized.createdAt = existing.createdAt or normalized.createdAt
            normalized.updatedAt = existing.updatedAt or normalized.updatedAt
        end
        store.roots[normalized.rootId] = normalizeRoot(normalized)
    end
end

local function migrateStore(document)
    local store = defaultStore()
    if type(document) ~= "table" then
        return store
    end
    if type(document.activePack) == "table" then
        store.activePack = document.activePack
    end
    if type(document.roots) == "table" then
        store.roots = document.roots
    end
    return store
end

function Roots.init()
    local store, createdFresh = Persist.loadVersioned(
        ROOTS_FILE,
        STORE_VERSION,
        defaultStore(),
        function(document)
            return migrateStore(document)
        end)

    if type(store) ~= "table" then
        store = defaultStore()
        createdFresh = true
    end
    if createdFresh then
        store = defaultStore()
    end
    importPackIntoStore(store, DefaultPack)
    store.activePack = copyPackMeta(DefaultPack)
    Roots._store = store
    rebuildIndex()
    Roots.save()
    Roots._initialized = true
    print(string.format("[NCM/Roots] Loaded %d root(s).", tonumber(Roots.getStats().total or 0)))
end

function Roots.save()
    ensureStoreShape()
    Persist.save(ROOTS_FILE, Roots._store)
end

function Roots.refresh(persistChanges)
    rebuildIndex()
    if persistChanges ~= false then
        Roots.save()
    end
    return true
end

function Roots.get(rootId)
    ensureStoreShape()
    local root = Roots._store.roots[rootId]
    return root and clone(root) or nil
end

function Roots.resolveRoot(rootId)
    local stored = Roots.get(rootId)
    if not stored then return nil end
    local resolved = normalizeRoot(stored)
    resolved.nodes = {}
    for _, nodeId in ipairs(resolved.nodeIds or {}) do
        resolved.nodes[#resolved.nodes + 1] = snapshotNode(getNode(nodeId)) or { id = nodeId, name = nodeId }
    end
    resolved.nodeA = resolved.nodes[1] or snapshotNode(getNode(resolved.startNodeId))
    resolved.nodeB = resolved.nodes[#resolved.nodes] or snapshotNode(getNode(resolved.endNodeId))
    resolved.primaryLabel = primaryLabel(resolved)
    resolved.secondaryLabel = secondaryLabel(resolved)
    return resolved
end

function Roots.all(options)
    ensureStoreShape()
    local includeInvalid = type(options) == "table" and options.includeInvalid == true
    local out = {}
    for rootId in pairs(Roots._store.roots) do
        local resolved = Roots.resolveRoot(rootId)
        if resolved and (includeInvalid or resolved.isValid ~= false) then
            out[#out + 1] = resolved
        end
    end
    table.sort(out, function(left, right)
        local leftKey = string.lower(primaryLabel(left))
        local rightKey = string.lower(primaryLabel(right))
        if leftKey == rightKey then
            return tostring(left.rootId) < tostring(right.rootId)
        end
        return leftKey < rightKey
    end)
    return out
end

function Roots.getStats()
    ensureStoreShape()
    local stats = {
        total = 0,
        valid = 0,
        invalid = 0,
        defaults = 0,
        user = 0,
    }
    for _, root in pairs(Roots._store.roots) do
        stats.total = stats.total + 1
        if root.isValid == false then
            stats.invalid = stats.invalid + 1
        else
            stats.valid = stats.valid + 1
        end
        if root.isDefaultPackRoot then
            stats.defaults = stats.defaults + 1
        else
            stats.user = stats.user + 1
        end
    end
    return stats
end

function Roots.hasValidRoots()
    for _, root in pairs(Roots._store.roots or {}) do
        if root.isValid ~= false then
            return true
        end
    end
    return false
end

function Roots.findByNodePair(startNodeId, finishNodeId, options)
    ensureStoreShape()
    local exactRootId = Roots._index.directed[directedKey(startNodeId, finishNodeId)]
    if exactRootId then
        return Roots.resolveRoot(exactRootId)
    end
    if type(options) == "table" and options.canonicalFallback then
        local bucket = Roots._index.canonical[canonicalPairKey(startNodeId, finishNodeId)] or {}
        if #bucket == 1 then
            return Roots.resolveRoot(bucket[1])
        end
    end
    return nil
end

function Roots.getDisplayForNodePair(startNodeId, finishNodeId, options)
    local root = Roots.findByNodePair(startNodeId, finishNodeId, options)
    if not root or root.isValid == false then return nil end
    return {
        rootId = root.rootId,
        displayName = root.displayName,
        autoLabel = root.autoLabel,
        primaryLabel = root.primaryLabel,
        secondaryLabel = root.secondaryLabel,
    }
end

function Roots.create(startNodeId, finishNodeId, opts)
    ensureStoreShape()
    local nodeIds = nil
    if type(startNodeId) == "table" then
        nodeIds = clone(startNodeId)
        opts = finishNodeId
        startNodeId = nodeIds[1]
        finishNodeId = nodeIds[#nodeIds]
    end
    local root = normalizeRoot({
        nodeIds = nodeIds,
        startNodeId = startNodeId,
        endNodeId = finishNodeId,
        displayName = opts and opts.displayName or nil,
        subtitleOverride = opts and opts.subtitleOverride or nil,
        tags = opts and opts.tags or nil,
        recommendedMode = opts and opts.recommendedMode or nil,
        profileSettings = opts and opts.profileSettings or nil,
        isDefaultPackRoot = false,
        sourcePackId = nil,
        createdByUser = true,
        createdAt = now(),
        updatedAt = now(),
    })

    if not root.nodeIds or #root.nodeIds < 2 then
        return nil, "Select at least two ordered route nodes."
    end
    if Roots._store.roots[root.rootId] then
        return nil, "A root already exists for that start and finish."
    end

    Roots._store.roots[root.rootId] = root
    rebuildIndex()
    Roots.save()
    return Roots.resolveRoot(root.rootId), nil
end

function Roots.rename(rootId, displayName)
    ensureStoreShape()
    local root = Roots._store.roots[rootId]
    if not root then return nil, "Root not found." end
    root.displayName = trim(displayName)
    root.updatedAt = now()
    Roots._store.roots[rootId] = normalizeRoot(root)
    rebuildIndex()
    Roots.save()
    return Roots.resolveRoot(rootId), nil
end

function Roots.clearCustomName(rootId)
    return Roots.rename(rootId, nil)
end

function Roots.setProfileSettings(rootId, profileSettings)
    ensureStoreShape()
    local root = Roots._store.roots[rootId]
    if not root then return nil, "Root not found." end
    local settings = MTE and MTE.Settings or nil
    if type(profileSettings) == "table" and settings and settings.sanitizeProfileSettings then
        root.profileSettings = settings.sanitizeProfileSettings(profileSettings)
    else
        root.profileSettings = type(profileSettings) == "table" and clone(profileSettings) or nil
    end
    root.updatedAt = now()
    Roots._store.roots[rootId] = normalizeRoot(root)
    rebuildIndex()
    Roots.save()
    return Roots.resolveRoot(rootId), nil
end

function Roots.setProfileSetting(rootId, key, value)
    ensureStoreShape()
    local root = Roots._store.roots[rootId]
    if not root then return nil, "Root not found." end

    local settings = MTE and MTE.Settings or nil
    local field = settings and settings.getTuningField and settings.getTuningField(key) or nil
    if not field then
        return nil, "Unknown tuning field."
    end

    local profile = type(root.profileSettings) == "table" and clone(root.profileSettings) or {}
    local normalized = settings and settings.normalizeTuningValue and settings.normalizeTuningValue(key, value) or value
    if normalized == nil then
        return nil, "Invalid tuning value."
    end
    profile[key] = normalized
    return Roots.setProfileSettings(rootId, profile)
end

function Roots.clearProfileSetting(rootId, key)
    ensureStoreShape()
    local root = Roots._store.roots[rootId]
    if not root then return nil, "Root not found." end
    if type(root.profileSettings) ~= "table" or root.profileSettings[key] == nil then
        return Roots.resolveRoot(rootId), nil
    end

    local profile = clone(root.profileSettings)
    profile[key] = nil
    return Roots.setProfileSettings(rootId, profile)
end

function Roots.clearProfileSettings(rootId)
    return Roots.setProfileSettings(rootId, nil)
end

function Roots.captureCurrentTuning(rootId)
    local settings = MTE and MTE.Settings or nil
    if not (settings and settings.captureGlobalTuningProfile) then
        return nil, "Settings module not available."
    end
    return Roots.setProfileSettings(rootId, settings.captureGlobalTuningProfile())
end

function Roots.delete(rootId)
    ensureStoreShape()
    if not Roots._store.roots[rootId] then
        return false, "Root not found."
    end
    Roots._store.roots[rootId] = nil
    rebuildIndex()
    Roots.save()
    return true
end

function Roots.restoreDefaults()
    local store = defaultStore()
    importPackIntoStore(store, DefaultPack)
    Roots._store = store
    rebuildIndex()
    Roots.save()
    return true
end

function Roots.pickForCareer(options)
    local eventType = type(options) == "table" and options.eventType or "sprint"
    local preferredRegion = type(options) == "table" and options.preferredRegion or nil
    local minDistanceM = type(options) == "table" and tonumber(options.minDistanceM) or 0.0
    local maxDistanceM = type(options) == "table" and tonumber(options.maxDistanceM) or math.huge
    local rng = type(options) == "table" and options.rng or nil
    local candidates = {}

    for _, root in ipairs(Roots.all({ includeInvalid = false })) do
        local regionOk = not preferredRegion
            or root.districtLabel == preferredRegion
            or (root.nodeA and root.nodeA.region == preferredRegion)
            or (root.nodeB and root.nodeB.region == preferredRegion)
        local distance = tonumber(root.distanceM) or 0.0
        local distanceOk = distance >= minDistanceM and distance <= maxDistanceM
        local modeOk = not root.recommendedMode or root.recommendedMode == eventType
        if regionOk and distanceOk and modeOk then
            candidates[#candidates + 1] = root
        end
    end

    if #candidates == 0 then return nil end
    table.sort(candidates, function(left, right)
        return tostring(left.rootId) < tostring(right.rootId)
    end)

    if rng and rng.nextIndex then
        return candidates[rng.nextIndex(#candidates)]
    end
    return candidates[1]
end

function Roots.exportPackDocument()
    local exportRoots = {}
    for _, root in ipairs(Roots.all({ includeInvalid = true })) do
        exportRoots[#exportRoots + 1] = {
            rootId = root.rootId,
            nodeIds = clone(root.nodeIds or {}),
            startNodeId = root.startNodeId,
            endNodeId = root.endNodeId,
            displayName = root.displayName,
            subtitleOverride = root.subtitleOverride,
            tags = clone(root.tags or {}),
            recommendedMode = root.recommendedMode,
            profileSettings = clone(root.profileSettings),
        }
    end
    return {
        packId = Roots._store.activePack and Roots._store.activePack.packId or DefaultPack.packId,
        packName = Roots._store.activePack and Roots._store.activePack.packName or DefaultPack.packName,
        version = Roots._store.activePack and Roots._store.activePack.version or DefaultPack.version,
        description = Roots._store.activePack and Roots._store.activePack.description or DefaultPack.description,
        roots = exportRoots,
    }
end

return Roots