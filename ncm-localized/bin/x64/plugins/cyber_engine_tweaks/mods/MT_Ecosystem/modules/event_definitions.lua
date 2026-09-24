local EventDefinitions = {}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = deepCopy(entry)
    end
    return copy
end

local function sanitizeToken(text)
    local token = tostring(text or "event"):lower():gsub("%s+", "_")
    token = token:gsub("[^%w_]", "_"):gsub("_+", "_")
    token = token:gsub("^_+", ""):gsub("_+$", "")
    if token == "" then token = "event" end
    return token
end

local function defaultTitleLabel(nodeA, nodeB)
    local startLabel = nodeA and (nodeA.name or nodeA.id) or "?"
    local finishLabel = nodeB and (nodeB.name or nodeB.id) or "?"
    return startLabel .. " -> " .. finishLabel
end

function EventDefinitions.clone(value)
    return deepCopy(value)
end

function EventDefinitions.snapshotNode(node)
    if type(node) ~= "table" then
        return nil
    end

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

function EventDefinitions.deriveDistrictLabel(nodeA, nodeB)
    local startRegion = nodeA and nodeA.region or nil
    local finishRegion = nodeB and nodeB.region or nil

    if startRegion and startRegion ~= "" and finishRegion and finishRegion ~= "" then
        if startRegion == finishRegion then
            return startRegion
        end
        return startRegion .. " -> " .. finishRegion
    end

    return startRegion or finishRegion or "Unknown"
end

function EventDefinitions.buildEventId(sourceType, seasonId, roundNumber, eventType, startNodeId, finishNodeId)
    local roundToken = tostring(roundNumber or 0)
    return table.concat({
        sanitizeToken(sourceType or "event"),
        sanitizeToken(seasonId or "standalone"),
        "r" .. roundToken,
        sanitizeToken(eventType or "race"),
        sanitizeToken(startNodeId or "start"),
        sanitizeToken(finishNodeId or "finish"),
    }, "_")
end

function EventDefinitions.buildPointToPoint(params)
    local nodeA = EventDefinitions.snapshotNode(params and params.nodeA)
    local nodeB = EventDefinitions.snapshotNode(params and params.nodeB)
    local route = params and params.route or nil
    local errors = deepCopy(params and params.validationErrors or {})
    local districtLabel = params and params.districtLabel or EventDefinitions.deriveDistrictLabel(nodeA, nodeB)
    local titleLabel = params and params.titleLabel
        or (params and params.trackName)
        or (route and route.displayName)
        or defaultTitleLabel(nodeA, nodeB)
    local completed = params and params.completed == true or false
    local explicitValidity = params and params.isValid
    local isValid = explicitValidity
    if isValid == nil then
        isValid = nodeA ~= nil and nodeB ~= nil and #errors == 0
    end

    return {
        eventId = (params and params.eventId)
            or EventDefinitions.buildEventId(
                params and params.sourceType,
                params and params.seasonId,
                params and params.round,
                params and (params.eventType or params.raceType),
                nodeA and nodeA.id,
                nodeB and nodeB.id),
        sourceType = params and params.sourceType or "career_schedule",
        seasonId = params and params.seasonId or nil,
        round = params and params.round or nil,
        leagueTier = params and params.leagueTier or nil,
        rulesetId = params and params.rulesetId or nil,
        eventType = params and (params.eventType or params.raceType) or "sprint",
        raceType = params and (params.raceType or params.eventType) or "sprint",
        startType = params and params.startType or "grid",
        fieldSize = params and params.fieldSize or 8,
        allowStakes = params and params.allowStakes,
        allowCombat = params and params.allowCombat,
        qualiEnabled = params and params.qualiEnabled,
        vehicleClass = params and params.vehicleClass,
        timeOfDay = params and params.timeOfDay,
        routeMode = params and params.routeMode or "scheduled",
        selectedRootId = params and params.selectedRootId or nil,
        selectedStartNodeId = params and params.selectedStartNodeId or (nodeA and nodeA.id or nil),
        selectedFinishNodeId = params and params.selectedFinishNodeId or (nodeB and nodeB.id or nil),
        quickRaceDriverTierMin = params and params.quickRaceDriverTierMin or nil,
        quickRaceDriverTierMax = params and params.quickRaceDriverTierMax or nil,
        quickRacePrestigeMin = params and params.quickRacePrestigeMin or nil,
        quickRacePrestigeMax = params and params.quickRacePrestigeMax or nil,
        quickRacePrestigeWeighting = params and params.quickRacePrestigeWeighting or nil,
        quickRaceAllowBossOutlier = params and params.quickRaceAllowBossOutlier == true or false,
        quickRaceMismatchPolicy = params and params.quickRaceMismatchPolicy or nil,
        nodeA = nodeA,
        nodeB = nodeB,
        district = districtLabel,
        districtLabel = districtLabel,
        distance = params and params.distance or (route and route.totalDistance) or 0,
        rootId = params and params.rootId or (route and route.rootId) or nil,
        rootDisplayName = params and params.rootDisplayName or (route and route.rootDisplayName) or nil,
        subtitleLabel = params and params.subtitleLabel or (route and route.subtitleLabel) or nil,
        routeId = params and params.routeId or (route and route.routeId) or nil,
        trackName = params and params.trackName or (route and route.displayName) or titleLabel,
        titleLabel = titleLabel,
        completed = completed,
        results = deepCopy(params and params.results or nil),
        isValid = isValid,
        validationErrors = errors,
        legacySnapshot = params and params.legacySnapshot == true or false,
    }
end

function EventDefinitions.buildKnockout(params)
    local errors = deepCopy(params and params.validationErrors or {})
    local circuitId = params and params.circuitId or nil
    local circuitName = params and params.circuitName or "Knockout Circuit"
    local districtLabel = params and (params.districtLabel or params.district) or "Unknown"
    local explicitValidity = params and params.isValid
    local isValid = explicitValidity
    if isValid == nil then
        isValid = circuitId ~= nil and #errors == 0
    end

    return {
        eventId = (params and params.eventId)
            or EventDefinitions.buildEventId(
                params and params.sourceType,
                params and params.seasonId,
                params and params.round,
                "knockout",
                params and params.circuitId,
                params and params.circuitId),
        sourceType = params and params.sourceType or "career_schedule",
        seasonId = params and params.seasonId or nil,
        round = params and params.round or nil,
        leagueTier = params and params.leagueTier or nil,
        rulesetId = params and params.rulesetId or nil,
        eventType = "knockout",
        raceType = "knockout",
        startType = params and params.startType or "grid",
        fieldSize = params and params.fieldSize or 8,
        allowStakes = params and params.allowStakes,
        allowCombat = params and params.allowCombat,
        qualiEnabled = false,
        vehicleClass = params and params.vehicleClass,
        timeOfDay = params and params.timeOfDay,
        routeMode = params and params.routeMode or "circuit",
        selectedStartNodeId = nil,
        selectedFinishNodeId = nil,
        nodeA = nil,
        nodeB = nil,
        district = districtLabel,
        districtLabel = districtLabel,
        distance = params and params.distance or 0,
        routeId = params and params.routeId or circuitId,
        trackName = params and params.trackName or circuitName,
        titleLabel = params and params.titleLabel or circuitName,
        circuitId = circuitId,
        circuitName = circuitName,
        circuitRegion = params and params.circuitRegion or districtLabel,
        estimatedLapTime = params and params.estimatedLapTime or nil,
        eliminationInterval = params and params.eliminationInterval or nil,
        trafficMode = params and params.trafficMode or "normal",
        combatMode = params and params.combatMode or nil,
        completed = params and params.completed == true or false,
        results = deepCopy(params and params.results or nil),
        isValid = isValid,
        validationErrors = errors,
        legacySnapshot = params and params.legacySnapshot == true or false,
    }
end

function EventDefinitions.buildLegacyCompleted(params)
    local errors = deepCopy(params and params.validationErrors or {})
    local districtLabel = params and (params.districtLabel or params.district) or "Unknown"
    local titleLabel = params and params.titleLabel or params and params.trackName or districtLabel
    local eventType = params and (params.eventType or params.raceType) or "sprint"
    local explicitValidity = params and params.isValid
    local isValid = explicitValidity
    if isValid == nil then
        isValid = true
    end

    return {
        eventId = (params and params.eventId)
            or EventDefinitions.buildEventId(
                params and params.sourceType,
                params and params.seasonId,
                params and params.round,
                eventType,
                params and params.startNodeId,
                params and params.finishNodeId),
        sourceType = params and params.sourceType or "career_schedule",
        seasonId = params and params.seasonId or nil,
        round = params and params.round or nil,
        leagueTier = params and params.leagueTier or nil,
        rulesetId = params and params.rulesetId or nil,
        eventType = eventType,
        raceType = eventType,
        startType = params and params.startType or "grid",
        fieldSize = params and params.fieldSize or 8,
        allowStakes = params and params.allowStakes,
        allowCombat = params and params.allowCombat,
        qualiEnabled = params and params.qualiEnabled,
        vehicleClass = params and params.vehicleClass,
        timeOfDay = params and params.timeOfDay,
        routeMode = params and params.routeMode or "legacy",
        selectedRootId = params and params.selectedRootId or nil,
        selectedStartNodeId = params and params.startNodeId or nil,
        selectedFinishNodeId = params and params.finishNodeId or nil,
        quickRaceDriverTierMin = params and params.quickRaceDriverTierMin or nil,
        quickRaceDriverTierMax = params and params.quickRaceDriverTierMax or nil,
        quickRacePrestigeMin = params and params.quickRacePrestigeMin or nil,
        quickRacePrestigeMax = params and params.quickRacePrestigeMax or nil,
        quickRacePrestigeWeighting = params and params.quickRacePrestigeWeighting or nil,
        quickRaceAllowBossOutlier = params and params.quickRaceAllowBossOutlier == true or false,
        quickRaceMismatchPolicy = params and params.quickRaceMismatchPolicy or nil,
        nodeA = EventDefinitions.snapshotNode(params and params.nodeA),
        nodeB = EventDefinitions.snapshotNode(params and params.nodeB),
        district = districtLabel,
        districtLabel = districtLabel,
        distance = params and params.distance or 0,
        rootId = params and params.rootId or nil,
        rootDisplayName = params and params.rootDisplayName or nil,
        subtitleLabel = params and params.subtitleLabel or nil,
        routeId = params and params.routeId or nil,
        trackName = params and params.trackName or titleLabel,
        titleLabel = titleLabel,
        completed = params and params.completed ~= false,
        results = deepCopy(params and params.results or nil),
        isValid = isValid,
        validationErrors = errors,
        legacySnapshot = true,
    }
end

return EventDefinitions