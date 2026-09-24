local Routes = {}

local Persist = require("modules/persistence")
local Tracks = require("data/tracks")

local ROUTES_FILE = "telemetry\\routes.json"
local STORE_VERSION = 1

Routes._store = {
    version = STORE_VERSION,
    routes = {},
    directedIndex = {},
    canonicalIndex = {},
}

local function clone(value)
    return Persist.clone and Persist.clone(value) or value
end

local function now()
    return os.time()
end

local function sanitizeToken(text)
    local token = tostring(text or "route"):lower():gsub("%s+", "_")
    token = token:gsub("[^%w_]", "_"):gsub("_+", "_")
    token = token:gsub("^_+", ""):gsub("_+$", "")
    if token == "" then token = "route" end
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

local function dist3d(a, b)
    if not a or not b then return 0.0 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function sortPair(a, b)
    a = tostring(a or "?")
    b = tostring(b or "?")
    if a <= b then return a, b end
    return b, a
end

local function canonicalPairKey(startNodeId, finishNodeId)
    local left, right = sortPair(startNodeId, finishNodeId)
    return left .. "|" .. right
end

local function directedKey(startNodeId, finishNodeId)
    return tostring(startNodeId or "?") .. "->" .. tostring(finishNodeId or "?")
end

local function routeTypeFromConfig(cfg)
    local raceType = cfg and cfg.raceType or "sprint"
    if raceType == "drag" then return "drag" end
    return "point_to_point"
end

local function nodeSnapshot(node)
    node = node or {}
    return {
        id = node.id,
        name = node.name,
        x = node.x or 0,
        y = node.y or 0,
        z = node.z or 0,
        heading = node.heading,
        finishHeading = node.finishHeading,
        region = node.region,
        road = node.road ~= false,
        urban = node.urban ~= false,
    }
end

local function buildPolyline(nodeA, nodeB, cfg)
    local totalDistance = tonumber(cfg and cfg.distance) or dist3d(nodeA, nodeB)
    if totalDistance < 0.1 then totalDistance = 0.1 end
    return {
        totalDistance = totalDistance,
        points = {
            { x = nodeA.x or 0, y = nodeA.y or 0, z = nodeA.z or 0, distance = 0.0 },
            { x = nodeB.x or 0, y = nodeB.y or 0, z = nodeB.z or 0, distance = totalDistance },
        },
        sectorBoundaries = {
            totalDistance / 3.0,
            (totalDistance * 2.0) / 3.0,
            totalDistance,
        },
    }
end

local function inferTags(nodeA, nodeB, cfg)
    local tags = {}
    local seen = {}

    local function add(tag)
        if not tag or tag == "" or seen[tag] then return end
        seen[tag] = true
        table.insert(tags, tag)
    end

    add(routeTypeFromConfig(cfg))
    add(cfg and cfg.routeMode or nil)
    add(cfg and cfg.startType and ("start_" .. tostring(cfg.startType)) or nil)
    add((nodeA and nodeA.region or nodeB and nodeB.region or "unknown"):lower():gsub("%s+", "_"))

    if (nodeA and nodeA.urban ~= false) and (nodeB and nodeB.urban ~= false) then
        add("urban")
    end
    if (nodeA and nodeA.road ~= false) and (nodeB and nodeB.road ~= false) then
        add("road")
    end
    if cfg and cfg.allowCombat == false then
        add("no_combat")
    end

    return tags
end

local function buildPathSignature(nodeA, nodeB, cfg, polyline)
    local parts = {
        routeTypeFromConfig(cfg),
        tostring(nodeA.id or nodeA.name or "?"),
        tostring(nodeB.id or nodeB.name or "?"),
        string.format("%.1f", nodeA.x or 0),
        string.format("%.1f", nodeA.y or 0),
        string.format("%.1f", nodeA.z or 0),
        string.format("%.1f", nodeB.x or 0),
        string.format("%.1f", nodeB.y or 0),
        string.format("%.1f", nodeB.z or 0),
        string.format("%.1f", polyline and polyline.totalDistance or 0),
    }
    return table.concat(parts, "|")
end

local function buildRouteId(startNodeId, finishNodeId, pathSignature)
    return "route_"
        .. sanitizeToken(startNodeId)
        .. "__to__"
        .. sanitizeToken(finishNodeId)
        .. "__"
        .. stableHash(pathSignature)
end

local function defaultStore()
    return {
        version = STORE_VERSION,
        routes = {},
        directedIndex = {},
        canonicalIndex = {},
    }
end

local function ensureStoreShape()
    local store = Routes._store or defaultStore()
    if type(store.routes) ~= "table" then store.routes = {} end
    if type(store.directedIndex) ~= "table" then store.directedIndex = {} end
    if type(store.canonicalIndex) ~= "table" then store.canonicalIndex = {} end
    store.version = STORE_VERSION
    Routes._store = store
end

local function appendUnique(list, value)
    for _, existing in ipairs(list) do
        if existing == value then return end
    end
    table.insert(list, value)
end

local function addCanonicalLink(route)
    local store = Routes._store
    local bucket = store.canonicalIndex[route.canonicalPairKey]
    if type(bucket) ~= "table" then
        bucket = {}
        store.canonicalIndex[route.canonicalPairKey] = bucket
    end
    appendUnique(bucket, route.routeId)
end

local function buildRouteRecord(nodeA, nodeB, cfg)
    local startNodeId = tostring(nodeA.id or nodeA.name or "?")
    local finishNodeId = tostring(nodeB.id or nodeB.name or "?")
    local polyline = buildPolyline(nodeA, nodeB, cfg)
    local pathSignature = buildPathSignature(nodeA, nodeB, cfg, polyline)
    local reversePolyline = buildPolyline(nodeB, nodeA, { distance = polyline.totalDistance, raceType = cfg and cfg.raceType })
    local reverseSignature = buildPathSignature(nodeB, nodeA, cfg, reversePolyline)
    local rootDisplay = MTE and MTE.Roots and MTE.Roots.getDisplayForNodePair
        and MTE.Roots.getDisplayForNodePair(startNodeId, finishNodeId)
        or nil
    local routeName = (rootDisplay and rootDisplay.primaryLabel)
        or (Tracks and Tracks.getRouteName and Tracks.getRouteName(nodeA, nodeB))
        or ((nodeA.name or startNodeId) .. " -> " .. (nodeB.name or finishNodeId))

    return {
        routeId = buildRouteId(startNodeId, finishNodeId, pathSignature),
        directedKey = directedKey(startNodeId, finishNodeId),
        canonicalPairKey = canonicalPairKey(startNodeId, finishNodeId),
        reverseRouteId = buildRouteId(finishNodeId, startNodeId, reverseSignature),
        startNodeId = startNodeId,
        finishNodeId = finishNodeId,
        displayName = routeName,
        rootId = rootDisplay and rootDisplay.rootId or nil,
        rootDisplayName = rootDisplay and rootDisplay.primaryLabel or nil,
        subtitleLabel = rootDisplay and rootDisplay.secondaryLabel or nil,
        district = nodeA.region or nodeB.region or "Unknown",
        region = nodeA.region or nodeB.region or "Unknown",
        routeType = routeTypeFromConfig(cfg),
        lapCapable = false,
        lapCountHint = tonumber(cfg and cfg.lapCount) or 1,
        settings = nil,  -- route-level overrides: { lapCount, fieldSize, raceType, startType, vehicleClass, timeOfDay }
        totalDistance = polyline.totalDistance,
        sectorCount = 3,
        sectorBoundaries = polyline.sectorBoundaries,
        pathModel = "cached_polyline_fallback",
        pathSignature = pathSignature,
        pathPoints = polyline.points,
        tags = inferTags(nodeA, nodeB, cfg),
        createdAt = now(),
        firstRunAt = nil,
        lastRunAt = nil,
        attemptCount = 0,
        finishCount = 0,
        dnfCount = 0,
        playerWinCount = 0,
        invalid = false,
        invalidReason = nil,
        replacedByRouteId = nil,
        nodeSnapshots = {
            start = nodeSnapshot(nodeA),
            finish = nodeSnapshot(nodeB),
        },
    }
end

local function refreshRouteRecord(route, latest)
    route.displayName = latest.displayName
    route.rootId = latest.rootId
    route.rootDisplayName = latest.rootDisplayName
    route.subtitleLabel = latest.subtitleLabel
    route.district = latest.district
    route.region = latest.region
    route.routeType = latest.routeType
    route.lapCapable = latest.lapCapable
    route.lapCountHint = latest.lapCountHint
    route.totalDistance = latest.totalDistance
    route.sectorCount = latest.sectorCount
    route.sectorBoundaries = latest.sectorBoundaries
    route.pathModel = latest.pathModel
    route.pathSignature = latest.pathSignature
    route.pathPoints = latest.pathPoints
    route.reverseRouteId = latest.reverseRouteId
    route.tags = latest.tags
    route.nodeSnapshots = latest.nodeSnapshots
    -- Preserve persisted route-level settings across record refreshes
    -- (latest never carries them; they are written only via Routes.setSettings)
end

local function migrateStore(document)
    local store = defaultStore()
    if type(document) ~= "table" then
        return store
    end
    if type(document.routes) == "table" then store.routes = document.routes end
    if type(document.directedIndex) == "table" then store.directedIndex = document.directedIndex end
    if type(document.canonicalIndex) == "table" then store.canonicalIndex = document.canonicalIndex end
    return store
end

function Routes.init()
    local store = Persist.loadVersioned(ROUTES_FILE, STORE_VERSION, defaultStore(), function(document)
        return migrateStore(document)
    end)
    Routes._store = store
    ensureStoreShape()
end

function Routes.save()
    ensureStoreShape()
    Persist.save(ROUTES_FILE, Routes._store)
end

function Routes.resolve(nodeA, nodeB, cfg)
    if not nodeA or not nodeB then return nil end
    ensureStoreShape()

    local latest = buildRouteRecord(nodeA, nodeB, cfg or {})
    local store = Routes._store
    local priorRouteId = store.directedIndex[latest.directedKey]
    if priorRouteId and priorRouteId ~= latest.routeId and store.routes[priorRouteId] then
        local prior = store.routes[priorRouteId]
        prior.invalid = true
        prior.invalidReason = "route_signature_changed"
        prior.replacedByRouteId = latest.routeId
    end

    local route = store.routes[latest.routeId]
    if route then
        refreshRouteRecord(route, latest)
    else
        route = latest
        store.routes[route.routeId] = route
    end

    store.directedIndex[route.directedKey] = route.routeId
    addCanonicalLink(route)
    Routes.save()
    return clone(route)
end

function Routes.get(routeId)
    ensureStoreShape()
    local route = Routes._store.routes[routeId]
    return route and clone(route) or nil
end

function Routes.noteSessionStart(routeId, meta)
    ensureStoreShape()
    local route = Routes._store.routes[routeId]
    if not route then return false end
    local ts = meta and meta.timestamp or now()
    route.attemptCount = (route.attemptCount or 0) + 1
    route.firstRunAt = route.firstRunAt or ts
    route.lastRunAt = ts
    route.lastSessionId = meta and meta.sessionId or route.lastSessionId
    Routes.save()
    return true
end

function Routes.noteSessionEnd(routeId, summary)
    ensureStoreShape()
    local route = Routes._store.routes[routeId]
    if not route then return false end

    local finishStatus = summary and summary.finishStatus or "pending"
    route.lastRunAt = summary and summary.timestamp or now()
    route.lastSessionId = summary and summary.sessionId or route.lastSessionId
    route.lastFinishStatus = finishStatus

    if finishStatus == "finished" then
        route.finishCount = (route.finishCount or 0) + 1
        if summary and tonumber(summary.position) == 1 then
            route.playerWinCount = (route.playerWinCount or 0) + 1
        end
    elseif finishStatus == "dnf" then
        route.dnfCount = (route.dnfCount or 0) + 1
    end

    Routes.save()
    return true
end

function Routes.all()
    ensureStoreShape()
    local result = {}
    for _, route in pairs(Routes._store.routes) do
        table.insert(result, clone(route))
    end
    table.sort(result, function(a, b)
        return (a.lastRunAt or a.createdAt or 0) > (b.lastRunAt or b.createdAt or 0)
    end)
    return result
end

local function resolveRoute(routeOrId)
    ensureStoreShape()
    if type(routeOrId) == "table" then
        if routeOrId.routeId and Routes._store.routes[routeOrId.routeId] then
            return Routes._store.routes[routeOrId.routeId]
        end
        return routeOrId
    end
    if routeOrId == nil then return nil end
    return Routes._store.routes[routeOrId]
end

local function clamp01(value)
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

--- Persist route-level settings that override career/global config when this route is used.
--- @param routeId string
--- @param settings table  keys: lapCount, fieldSize, raceType, startType, vehicleClass, timeOfDay (nil clears)
function Routes.setSettings(routeId, settings)
    ensureStoreShape()
    local route = Routes._store.routes[routeId]
    if not route then return false end
    if type(settings) == "table" and next(settings) ~= nil then
        route.settings = settings
    else
        route.settings = nil
    end
    Routes.save()
    return true
end

--- Return the route-level settings table, or nil if none are set.
--- @param routeId string
function Routes.getSettings(routeId)
    ensureStoreShape()
    local route = Routes._store.routes[routeId]
    return route and route.settings or nil
end

function Routes.getSectorInfo(routeOrId, distanceAlong)
    local route = resolveRoute(routeOrId)
    if not route then return nil end

    local totalDistance = math.max(0.1, tonumber(route.totalDistance) or 0.1)
    local d = math.max(0.0, math.min(totalDistance, tonumber(distanceAlong) or 0.0))
    local boundaries = route.sectorBoundaries or {}
    local sectorIndex = 1
    local sectorStart = 0.0
    local sectorEnd = totalDistance

    for index, boundary in ipairs(boundaries) do
        sectorEnd = tonumber(boundary) or sectorEnd
        if d <= sectorEnd or index == #boundaries then
            sectorIndex = index
            break
        end
        sectorStart = sectorEnd
    end

    return {
        sectorIndex = sectorIndex,
        sectorStartDistance = sectorStart,
        sectorEndDistance = sectorEnd,
        sectorProgress = clamp01((d - sectorStart) / math.max(0.1, sectorEnd - sectorStart)),
    }
end

function Routes.computeProgress(routeOrId, position)
    local route = resolveRoute(routeOrId)
    if not route or not position then return nil end

    local points = route.pathPoints or {}
    if #points < 2 then return nil end

    local bestDistanceAlong = 0.0
    local bestLateral = math.huge
    local bestPoint = nil
    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local sx = (b.x or 0) - (a.x or 0)
        local sy = (b.y or 0) - (a.y or 0)
        local sz = (b.z or 0) - (a.z or 0)
        local segLenSq = sx * sx + sy * sy + sz * sz
        local startDistance = tonumber(a.distance) or 0.0
        local endDistance = tonumber(b.distance) or (startDistance + math.sqrt(segLenSq))

        local t = 0.0
        if segLenSq > 0.0001 then
            local px = (position.x or 0) - (a.x or 0)
            local py = (position.y or 0) - (a.y or 0)
            local pz = (position.z or 0) - (a.z or 0)
            t = (px * sx + py * sy + pz * sz) / segLenSq
            if t < 0.0 then t = 0.0 end
            if t > 1.0 then t = 1.0 end
        end

        local proj = {
            x = (a.x or 0) + sx * t,
            y = (a.y or 0) + sy * t,
            z = (a.z or 0) + sz * t,
        }
        local dx = (position.x or 0) - proj.x
        local dy = (position.y or 0) - proj.y
        local dz = (position.z or 0) - proj.z
        local lateral = math.sqrt(dx * dx + dy * dy + dz * dz)
        local distanceAlong = startDistance + (endDistance - startDistance) * t

        if lateral < bestLateral - 0.01 or (math.abs(lateral - bestLateral) <= 0.01 and distanceAlong > bestDistanceAlong) then
            bestLateral = lateral
            bestDistanceAlong = distanceAlong
            bestPoint = proj
        end
    end

    local totalDistance = math.max(0.1, tonumber(route.totalDistance) or bestDistanceAlong or 0.1)
    local distanceAlong = math.max(0.0, math.min(totalDistance, bestDistanceAlong))
    local sector = Routes.getSectorInfo(route, distanceAlong) or {}
    return {
        routeId = route.routeId,
        totalDistance = totalDistance,
        distanceAlong = distanceAlong,
        remainingDistance = math.max(0.0, totalDistance - distanceAlong),
        completion = clamp01(distanceAlong / totalDistance),
        lateralDistance = bestLateral,
        projectedPoint = bestPoint,
        sectorIndex = sector.sectorIndex or 1,
        sectorStartDistance = sector.sectorStartDistance or 0.0,
        sectorEndDistance = sector.sectorEndDistance or totalDistance,
        sectorProgress = sector.sectorProgress or 0.0,
    }
end

function Routes.estimateProgressFromTime(routeOrId, raceTime, finishTime)
    local route = resolveRoute(routeOrId)
    if not route or not finishTime or finishTime <= 0 then return nil end
    local totalDistance = math.max(0.1, tonumber(route.totalDistance) or 0.1)
    local completion = clamp01((tonumber(raceTime) or 0.0) / finishTime)
    local distanceAlong = totalDistance * completion
    local sector = Routes.getSectorInfo(route, distanceAlong) or {}
    return {
        routeId = route.routeId,
        totalDistance = totalDistance,
        distanceAlong = distanceAlong,
        remainingDistance = math.max(0.0, totalDistance - distanceAlong),
        completion = completion,
        lateralDistance = nil,
        projectedPoint = nil,
        sectorIndex = sector.sectorIndex or 1,
        sectorStartDistance = sector.sectorStartDistance or 0.0,
        sectorEndDistance = sector.sectorEndDistance or totalDistance,
        sectorProgress = sector.sectorProgress or 0.0,
    }
end

function Routes.getTotalDistance(routeOrId)
    local route = resolveRoute(routeOrId)
    return route and route.totalDistance or nil
end

return Routes
