local RaceTelemetry = {}

local Persist = require("modules/persistence")

local INDEX_FILE = "telemetry\\session_index.json"
local SESSION_DIR = "telemetry\\sessions\\"
local STORE_VERSION = 1
local FLUSH_INTERVAL = 1.0
local TRACE_SAMPLE_INTERVAL = 0.5

RaceTelemetry._index = {
    version = STORE_VERSION,
    sessions = {},
    routeSessions = {},
}
RaceTelemetry._activeSessionId = nil
RaceTelemetry._activeSession = nil
RaceTelemetry._dirty = false
RaceTelemetry._flushTimer = 0.0

local function clone(value)
    return Persist.clone and Persist.clone(value) or value
end

local function resolveSessionClean(session)
    if type(session) ~= "table" then return false end
    local safetyPoints = session.safetyRating and tonumber(session.safetyRating.incidentPoints) or nil
    if safetyPoints == nil then
        safetyPoints = tonumber(session.safetyIncidentPoints)
    end
    if safetyPoints ~= nil then
        return session.finishStatus == "finished" and safetyPoints <= 0
    end
    return session.clean == true
end

local function now()
    return os.time()
end

local function sanitizeToken(text)
    local token = tostring(text or "session"):lower():gsub("%s+", "_")
    token = token:gsub("[^%w_]", "_"):gsub("_+", "_")
    token = token:gsub("^_+", ""):gsub("_+$", "")
    if token == "" then token = "session" end
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

local function defaultIndex()
    return {
        version = STORE_VERSION,
        sessions = {},
        routeSessions = {},
    }
end

local function ensureIndexShape()
    local index = RaceTelemetry._index or defaultIndex()
    if type(index.sessions) ~= "table" then index.sessions = {} end
    if type(index.routeSessions) ~= "table" then index.routeSessions = {} end
    for _, summary in pairs(index.sessions) do
        if type(summary) == "table" then
            summary.clean = resolveSessionClean(summary)
        end
    end
    index.version = STORE_VERSION
    RaceTelemetry._index = index
end

local function sessionFile(sessionId)
    return SESSION_DIR .. tostring(sessionId) .. ".json"
end

local function loadSessionDocument(sessionId)
    local session = Persist.load(sessionFile(sessionId))
    return type(session) == "table" and session or nil
end

local function saveSessionDocument(session)
    if not session or not session.sessionId then return false end
    session.version = STORE_VERSION
    return Persist.save(sessionFile(session.sessionId), session)
end

local function markDirty()
    RaceTelemetry._dirty = true
end

local function routeSnapshot(route)
    route = route or {}
    return {
        routeId = route.routeId,
        displayName = route.displayName,
        rootId = route.rootId,
        rootDisplayName = route.rootDisplayName,
        subtitleLabel = route.subtitleLabel,
        canonicalPairKey = route.canonicalPairKey,
        startNodeId = route.startNodeId,
        finishNodeId = route.finishNodeId,
        totalDistance = route.totalDistance,
        sectorBoundaries = clone(route.sectorBoundaries or {}),
        tags = clone(route.tags or {}),
        pathSignature = route.pathSignature,
    }
end

local function buildStateToken(context)
    local parts = {
        tostring(context.routeId or "route"),
        tostring(context.fieldSize or 0),
        tostring(context.startType or "grid"),
        tostring(context.raceType or "sprint"),
        tostring(context.playerVehicleId or "unknown"),
        tostring(context.seed or now()),
    }
    return stableHash(table.concat(parts, "|"))
end

local function generateSessionId(context)
    local routeToken = sanitizeToken(context.routeId or "route")
    local seed = tostring(now()) .. "|" .. tostring(math.random(1000, 9999)) .. "|" .. tostring(context.routeId or "route")
    return "session_" .. routeToken .. "_" .. stableHash(seed)
end

local function buildPlayerParticipant(context)
    return {
        participantId = "player",
        driverId = "player",
        name = context.playerName or "V",
        isPlayer = true,
        teamId = context.playerTeamId or "independent",
        teamName = context.playerTeamName or "Independent",
        vehicleId = context.playerVehicleId or "unknown",
        startPos = context.startPos or 1,
        finishPos = nil,
        finishStatus = "pending",
        totalTime = nil,
        bestLap = nil,
        bestSector1 = nil,
        bestSector2 = nil,
        bestSector3 = nil,
        averageLap = nil,
        topSpeed = nil,
        averageSpeed = nil,
        offRouteCount = 0,
        majorCollisionCount = 0,
        recoveryCount = 0,
        routeDeviationDistance = 0,
        routeDeviationTime = 0,
        stationaryTime = 0,
        wrongWayTime = 0,
        validForRecords = true,
        standingPos = context.startPos or 1,
        provenance = "live",
        currentLap = 1,
        currentSector = 1,
        currentProgress = 0.0,
        distanceAlong = 0.0,
        remainingDistance = nil,
        _speedAccum = 0.0,
        _speedSamples = 0,
        _sectorStartTime = nil,
        _lapStartTime = nil,
        _sectorCompleted = {},
        _lapSectorTimes = {},
        _progressInitialized = false,
        _lapRecorded = false,
    }
end

local function buildAIParticipants(field)
    local participants = {}
    for index, entry in ipairs(field or {}) do
        local driver = entry.driver or {}
        table.insert(participants, {
            participantId = entry.driverId or entry.id or ("ai_" .. tostring(index)),
            driverId = entry.driverId or entry.id or ("ai_" .. tostring(index)),
            name = entry.displayName or entry.name or entry.id or "?",
            isPlayer = false,
            teamId = driver.factionId or "independent",
            teamName = driver.factionName or driver.teamName or "",
            vehicleId = entry.vehicleRecord or entry.vehRecord or "unknown",
            npcRecord = entry.npcRecord,
            startPos = entry.gridPos or index + 1,
            finishPos = nil,
            finishStatus = "pending",
            totalTime = nil,
            estimatedTotalTime = entry.aiTime,
            bestLap = nil,
            bestSector1 = nil,
            bestSector2 = nil,
            bestSector3 = nil,
            averageLap = nil,
            topSpeed = nil,
            averageSpeed = nil,
            offRouteCount = 0,
            majorCollisionCount = 0,
            recoveryCount = 0,
            routeDeviationDistance = 0,
            routeDeviationTime = 0,
            stationaryTime = 0,
            wrongWayTime = 0,
            validForRecords = true,
            standingPos = entry.gridPos or index + 1,
            provenance = entry.aiTime and "estimated" or "planned",
            isRival = entry.isRival or false,
            vehicleBuild = driver.vehicleBuild or nil,
            currentLap = 1,
            currentSector = 1,
            currentProgress = 0.0,
            distanceAlong = 0.0,
            remainingDistance = nil,
            _speedAccum = 0.0,
            _speedSamples = 0,
            _sectorStartTime = nil,
            _lapStartTime = nil,
            _sectorCompleted = {},
            _lapSectorTimes = {},
            _progressInitialized = false,
            _lapRecorded = false,
        })
    end
    return participants
end

local function buildSessionDocument(context)
    local startedAt = now()
    local sessionId = context.sessionId or generateSessionId(context)
    local sectorCount = math.max(1, #((context.route and context.route.sectorBoundaries) or {}))
    local session = {
        version = STORE_VERSION,
        sessionId = sessionId,
        routeId = context.routeId,
        routeDisplayName = context.routeDisplayName or context.trackName or "Unknown Route",
        rootId = context.rootId or nil,
        rootDisplayName = context.rootDisplayName or nil,
        subtitleLabel = context.subtitleLabel or nil,
        canonicalPairKey = context.canonicalPairKey,
        routeSnapshot = routeSnapshot(context.route),
        startedAt = startedAt,
        endedAt = nil,
        mode = context.mode or "career",
        lapCount = tonumber(context.lapCount) or 1,
        fieldSize = tonumber(context.fieldSize) or 1,
        startType = context.startType or "grid",
        raceType = context.raceType or "sprint",
        playerVehicleId = context.playerVehicleId or "unknown",
        playerDriverId = context.playerDriverId or "player",
        playerTeamId = context.playerTeamId or "independent",
        playerTeamName = context.playerTeamName or "Independent",
        careerId = context.careerId,
        careerName = context.careerName,
        tier = context.tier,
        seasonId = context.seasonId,
        seasonNumber = context.seasonNumber,
        championshipRound = context.championshipRound,
        deterministicToken = context.stateToken or buildStateToken(context),
        conditions = {
            district = context.district,
            region = context.region,
            timeOfDay = context.timeOfDay,
            allowCombat = context.allowCombat ~= false,
            allowStakes = context.allowStakes == true,
            routeMode = context.routeMode,
        },
        finishStatus = "pending",
        finishingPosition = nil,
        totalRaceTime = nil,
        bestLap = nil,
        bestSector1 = nil,
        bestSector2 = nil,
        bestSector3 = nil,
        benchmarks = {
            bestTotalRaceTime = nil,
            bestLap = nil,
            bestSector1 = nil,
            bestSector2 = nil,
            bestSector3 = nil,
        },
        averageLap = nil,
        marginToWinner = nil,
        repDelta = 0,
        pointsAwarded = 0,
        payout = 0,
        clean = false,
        crashHeavy = false,
        invalidated = false,
        abandoned = false,
        dnfCause = nil,
        validForRecords = true,
        recordFlags = {},
        safetyRating = nil,
        participants = {},
        laps = {},
        sectors = {},
        incidents = {
            counts = {
                offRoute = 0,
                majorCollisions = 0,
                recoveries = 0,
                overtakes = 0,
                positionsGainedLap1 = 0,
            },
            events = {},
        },
        traces = {
            sampleRateHz = 1.0 / TRACE_SAMPLE_INTERVAL,
            progressSamples = {},
        },
        liveState = {
            raceTime = 0.0,
            routeId = context.routeId,
            routeDisplayName = context.routeDisplayName or context.trackName or "Unknown Route",
            totalLaps = tonumber(context.lapCount) or 1,
            totalSectors = sectorCount,
            currentLap = 1,
            currentSector = 1,
            playerProgress = 0.0,
            playerDistanceAlong = 0.0,
            playerRemainingDistance = context.route and context.route.totalDistance or nil,
            currentLapTime = 0.0,
            currentSectorTime = 0.0,
            sessionBestLap = nil,
            sessionBestSector1 = nil,
            sessionBestSector2 = nil,
            sessionBestSector3 = nil,
            routeBestRaceTime = nil,
            routeBestLap = nil,
            routeBestSector1 = nil,
            routeBestSector2 = nil,
            routeBestSector3 = nil,
            currentDeltaToRouteBest = nil,
            currentSectorDeltaToRouteBest = nil,
            lastSectorNumber = nil,
            lastSectorTime = nil,
            lastSectorDelta = nil,
            lastSectorWasSessionBest = false,
            lastSectorWasRouteBest = false,
            lastSectorLabel = "",
            lastLapNumber = nil,
            lastLapTime = nil,
            lastLapDelta = nil,
            lastLapWasSessionBest = false,
            lastLapWasRouteBest = false,
            lastLapLabel = "",
            validForRecords = true,
            playerValidForRecords = true,
            finishStatus = "pending",
        },
        _lastTraceRaceTime = nil,
        _playerSignals = {
            startStandingPos = context.startPos or 1,
            lastStandingPos = context.startPos or 1,
            bestStandingPos = context.startPos or 1,
            worstStandingPos = context.startPos or 1,
            lastCollisionCount = 0,
            recoveryArmed = false,
            recoveryAnchorPos = context.startPos or 1,
        },
    }

    table.insert(session.participants, buildPlayerParticipant(context))
    for _, participant in ipairs(buildAIParticipants(context.field)) do
        table.insert(session.participants, participant)
    end

    return session
end

local function buildIndexEntry(session)
    return {
        sessionId = session.sessionId,
        routeId = session.routeId,
        routeDisplayName = session.routeDisplayName,
        rootId = session.rootId,
        rootDisplayName = session.rootDisplayName,
        subtitleLabel = session.subtitleLabel,
        startedAt = session.startedAt,
        endedAt = session.endedAt,
        mode = session.mode,
        fieldSize = session.fieldSize,
        lapCount = session.lapCount,
        startType = session.startType,
        raceType = session.raceType,
        finishStatus = session.finishStatus,
        position = session.finishingPosition,
        totalRaceTime = session.totalRaceTime,
        payout = session.payout,
        repDelta = session.repDelta,
        safetyRatingAfter = session.safetyRating and session.safetyRating.afterSR or nil,
        safetyRatingDelta = session.safetyRating and session.safetyRating.deltaSR or nil,
        safetyIncidentPoints = session.safetyRating and session.safetyRating.incidentPoints or nil,
        clean = resolveSessionClean(session),
        invalidated = session.invalidated,
        abandoned = session.abandoned,
    }
end

local function touchRouteSessionIndex(routeId, sessionId)
    if not routeId then return end
    local bucket = RaceTelemetry._index.routeSessions[routeId]
    if type(bucket) ~= "table" then
        bucket = {}
        RaceTelemetry._index.routeSessions[routeId] = bucket
    end
    for i = #bucket, 1, -1 do
        if bucket[i] == sessionId then
            table.remove(bucket, i)
        end
    end
    table.insert(bucket, 1, sessionId)
end

local function touchIndex(session)
    ensureIndexShape()
    RaceTelemetry._index.sessions[session.sessionId] = buildIndexEntry(session)
    touchRouteSessionIndex(session.routeId, session.sessionId)
    Persist.save(INDEX_FILE, RaceTelemetry._index)
end

local function findParticipant(session, participantId)
    for _, participant in ipairs(session.participants or {}) do
        if participant.participantId == participantId then
            return participant
        end
    end
    return nil
end

local function upsertParticipant(session, participantId, fallback)
    local participant = findParticipant(session, participantId)
    if participant then return participant end
    participant = clone(fallback or { participantId = participantId, driverId = participantId, name = participantId })
    table.insert(session.participants, participant)
    return participant
end

local function applyMetricsToPlayer(session, metrics)
    if not metrics then return end
    local player = findParticipant(session, "player")
    if not player then return end
    player.topSpeed = metrics.peakSpeed or player.topSpeed
    player.averageSpeed = metrics.avgSpeed or player.averageSpeed
    player.majorCollisionCount = metrics.crashCount or player.majorCollisionCount
    session.incidents.counts.majorCollisions = metrics.crashCount or session.incidents.counts.majorCollisions
end

local function ensureTimingState(participant, raceTime)
    participant.currentLap = participant.currentLap or 1
    participant.currentSector = participant.currentSector or 1
    participant.currentProgress = participant.currentProgress or 0.0
    participant.distanceAlong = participant.distanceAlong or 0.0
    participant._speedAccum = participant._speedAccum or 0.0
    participant._speedSamples = participant._speedSamples or 0
    participant._sectorCompleted = participant._sectorCompleted or {}
    participant._lapSectorTimes = participant._lapSectorTimes or {}
    participant._lapRecorded = participant._lapRecorded == true
    if not participant._progressInitialized then
        participant._progressInitialized = true
        participant._sectorStartTime = raceTime or 0.0
        participant._lapStartTime = raceTime or 0.0
    end
end

local function sectorFieldName(sectorNumber)
    return "bestSector" .. tostring(sectorNumber)
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0.0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function defaultBenchmarks()
    return {
        bestTotalRaceTime = nil,
        bestLap = nil,
        bestSector1 = nil,
        bestSector2 = nil,
        bestSector3 = nil,
    }
end

local function updateBest(current, candidate)
    if candidate == nil then return current end
    if current == nil or candidate < current then return candidate end
    return current
end

local function summarizeRouteBenchmarks(routeId)
    ensureIndexShape()
    local benchmarks = defaultBenchmarks()
    if not routeId then return benchmarks end

    local bucket = RaceTelemetry._index.routeSessions[routeId] or {}
    for _, sessionId in ipairs(bucket) do
        local session = loadSessionDocument(sessionId)
        if session and session.finishStatus == "finished" and session.validForRecords ~= false then
            benchmarks.bestTotalRaceTime = updateBest(benchmarks.bestTotalRaceTime, session.totalRaceTime)
            benchmarks.bestLap = updateBest(benchmarks.bestLap, session.bestLap)
            benchmarks.bestSector1 = updateBest(benchmarks.bestSector1, session.bestSector1)
            benchmarks.bestSector2 = updateBest(benchmarks.bestSector2, session.bestSector2)
            benchmarks.bestSector3 = updateBest(benchmarks.bestSector3, session.bestSector3)
        end
    end

    return benchmarks
end

local function ensureLiveState(session)
    session.liveState = session.liveState or {}
    local liveState = session.liveState
    local totalDistance = session.routeDistance or (session.routeSnapshot and session.routeSnapshot.totalDistance) or nil
    local totalSectors = math.max(1, #((session.routeSnapshot and session.routeSnapshot.sectorBoundaries) or {}))

    liveState.raceTime = liveState.raceTime or 0.0
    liveState.totalLaps = liveState.totalLaps or session.lapCount or 1
    liveState.totalSectors = liveState.totalSectors or totalSectors
    liveState.currentLap = liveState.currentLap or 1
    liveState.currentSector = liveState.currentSector or 1
    liveState.playerProgress = liveState.playerProgress or 0.0
    liveState.playerDistanceAlong = liveState.playerDistanceAlong or 0.0
    if liveState.playerRemainingDistance == nil then
        liveState.playerRemainingDistance = totalDistance
    end
    liveState.currentLapTime = liveState.currentLapTime or 0.0
    liveState.currentSectorTime = liveState.currentSectorTime or 0.0
    liveState.routeId = session.routeId
    liveState.routeDisplayName = session.routeDisplayName
    liveState.finishStatus = session.finishStatus
    liveState.validForRecords = session.validForRecords ~= false
    return liveState
end

local function syncBenchmarksToLiveState(session)
    session.benchmarks = session.benchmarks or defaultBenchmarks()
    local liveState = ensureLiveState(session)
    liveState.sessionBestLap = session.bestLap
    liveState.sessionBestSector1 = session.bestSector1
    liveState.sessionBestSector2 = session.bestSector2
    liveState.sessionBestSector3 = session.bestSector3
    liveState.routeBestRaceTime = session.benchmarks.bestTotalRaceTime
    liveState.routeBestLap = session.benchmarks.bestLap or session.benchmarks.bestTotalRaceTime
    liveState.routeBestSector1 = session.benchmarks.bestSector1
    liveState.routeBestSector2 = session.benchmarks.bestSector2
    liveState.routeBestSector3 = session.benchmarks.bestSector3
end

local function getSectorWindow(session, sectorNumber)
    local boundaries = (session.routeSnapshot and session.routeSnapshot.sectorBoundaries) or {}
    local totalDistance = session.routeDistance or (session.routeSnapshot and session.routeSnapshot.totalDistance) or 0.0
    local startDistance = sectorNumber > 1 and (boundaries[sectorNumber - 1] or 0.0) or 0.0
    local endDistance = boundaries[sectorNumber] or totalDistance
    if endDistance <= startDistance then
        endDistance = startDistance + 1.0
    end
    return startDistance, endDistance
end

local function emitTimingEvent(name, payload)
    if MTE and MTE.Events then
        MTE.Events.emit(name, payload)
    end
end

local function refreshLivePlayerTiming(session, participant, raceTime)
    if not participant or not participant.isPlayer then return end
    local liveState = ensureLiveState(session)
    syncBenchmarksToLiveState(session)

    liveState.raceTime = raceTime or liveState.raceTime or 0.0
    liveState.currentLap = participant.currentLap or 1
    liveState.currentSector = participant.currentSector or 1
    liveState.playerProgress = participant.currentProgress or 0.0
    liveState.playerDistanceAlong = participant.distanceAlong or 0.0
    liveState.playerRemainingDistance = participant.remainingDistance
    liveState.currentLapTime = math.max(0.0, (raceTime or 0.0) - (participant._lapStartTime or 0.0))
    liveState.currentSectorTime = math.max(0.0, (raceTime or 0.0) - (participant._sectorStartTime or 0.0))
    liveState.playerValidForRecords = participant.validForRecords ~= false
    liveState.finishStatus = session.finishStatus
    liveState.validForRecords = session.validForRecords ~= false and participant.validForRecords ~= false

    if liveState.routeBestLap and liveState.routeBestLap > 0 then
        liveState.currentDeltaToRouteBest = liveState.currentLapTime -
            (liveState.routeBestLap * clamp(participant.currentProgress or 0.0, 0.0, 1.0))
    else
        liveState.currentDeltaToRouteBest = nil
    end

    local sectorNumber = math.max(1, math.min(liveState.totalSectors or 1, participant.currentSector or 1))
    local sectorField = sectorFieldName(sectorNumber)
    local sectorBest = session.benchmarks and session.benchmarks[sectorField] or nil
    local startDistance, endDistance = getSectorWindow(session, sectorNumber)
    local sectorSpan = math.max(1.0, endDistance - startDistance)
    local sectorProgress = clamp(((participant.distanceAlong or 0.0) - startDistance) / sectorSpan, 0.0, 1.0)
    liveState.currentSectorDeltaToRouteBest = sectorBest and
        (liveState.currentSectorTime - (sectorBest * sectorProgress)) or nil
end

local function updateAverageSpeed(participant, speed)
    if type(speed) ~= "number" then return end
    participant._speedAccum = (participant._speedAccum or 0.0) + speed
    participant._speedSamples = (participant._speedSamples or 0) + 1
    if (participant._speedSamples or 0) > 0 then
        participant.averageSpeed = participant._speedAccum / participant._speedSamples
    end
    participant.topSpeed = math.max(participant.topSpeed or 0.0, speed)
end

local function currentMetricsCrashCount()
    return tonumber(MTE and MTE.Metrics and MTE.Metrics.session and MTE.Metrics.session.crashCount or 0) or 0
end

local function updatePlayerSignalCounters(session, participant, snapshot)
    if not (session and participant and participant.isPlayer) then return end

    session._playerSignals = session._playerSignals or {
        startStandingPos = participant.startPos or 1,
        lastStandingPos = participant.startPos or 1,
        bestStandingPos = participant.startPos or 1,
        worstStandingPos = participant.startPos or 1,
        lastCollisionCount = 0,
        recoveryArmed = false,
        recoveryAnchorPos = participant.startPos or 1,
    }

    local signals = session._playerSignals
    local standingPos = tonumber(snapshot and snapshot.standingPos or participant.standingPos or signals.lastStandingPos or participant.startPos or 1) or 1
    local previousStandingPos = tonumber(signals.lastStandingPos or standingPos) or standingPos

    signals.startStandingPos = tonumber(signals.startStandingPos or participant.startPos or standingPos) or standingPos
    signals.bestStandingPos = math.min(tonumber(signals.bestStandingPos or standingPos) or standingPos, standingPos)
    signals.worstStandingPos = math.max(tonumber(signals.worstStandingPos or standingPos) or standingPos, standingPos)
    participant.standingPos = standingPos

    if standingPos < previousStandingPos then
        local gained = previousStandingPos - standingPos
        session.incidents.counts.overtakes = (tonumber(session.incidents.counts.overtakes or 0) or 0) + gained
    end

    local currentLap = tonumber(snapshot and snapshot.currentLap or participant.currentLap or 1) or 1
    if currentLap <= 1 then
        local lapOneNetGain = math.max(0, (tonumber(signals.startStandingPos or standingPos) or standingPos) - standingPos)
        session.incidents.counts.positionsGainedLap1 = math.max(tonumber(session.incidents.counts.positionsGainedLap1 or 0) or 0, lapOneNetGain)
    end

    local crashCount = currentMetricsCrashCount()
    participant.majorCollisionCount = crashCount
    session.incidents.counts.majorCollisions = crashCount
    if crashCount > (tonumber(signals.lastCollisionCount or 0) or 0) then
        signals.recoveryArmed = true
        signals.recoveryAnchorPos = math.max(tonumber(signals.recoveryAnchorPos or standingPos) or standingPos, standingPos)
        signals.lastCollisionCount = crashCount
    end

    if signals.recoveryArmed then
        signals.recoveryAnchorPos = math.max(tonumber(signals.recoveryAnchorPos or standingPos) or standingPos, standingPos)
        if standingPos <= math.max(1, (tonumber(signals.recoveryAnchorPos or standingPos) or standingPos) - 2) then
            participant.recoveryCount = (tonumber(participant.recoveryCount or 0) or 0) + 1
            session.incidents.counts.recoveries = (tonumber(session.incidents.counts.recoveries or 0) or 0) + 1
            signals.recoveryArmed = false
            signals.recoveryAnchorPos = standingPos
        end
    end

    signals.lastStandingPos = standingPos
    participant._bestStandingPos = math.min(tonumber(participant._bestStandingPos or standingPos) or standingPos, standingPos)
    participant._worstStandingPos = math.max(tonumber(participant._worstStandingPos or standingPos) or standingPos, standingPos)
end

local function recordSectorSplit(session, participant, sectorNumber, lapNumber, sectorTime, raceTime, provenance)
    sectorTime = math.max(0.0, sectorTime or 0.0)
    local fieldName = sectorFieldName(sectorNumber)
    local routeBest = session.benchmarks and session.benchmarks[fieldName] or nil
    local sessionBest = participant.isPlayer and session[fieldName] or nil
    local validForRecords = participant.validForRecords ~= false and session.validForRecords ~= false
    local isSessionBest = participant.isPlayer and validForRecords and (sessionBest == nil or sectorTime < sessionBest)
    local isRouteBest = participant.isPlayer and validForRecords and (routeBest == nil or sectorTime < routeBest)

    if participant[fieldName] == nil or sectorTime < participant[fieldName] then
        participant[fieldName] = sectorTime
    end
    if participant.isPlayer and (session[fieldName] == nil or sectorTime < session[fieldName]) then
        session[fieldName] = sectorTime
    end
    if participant.isPlayer and isRouteBest then
        session.benchmarks = session.benchmarks or defaultBenchmarks()
        session.benchmarks[fieldName] = sectorTime
    end
    if participant.isPlayer then
        session.recordFlags = session.recordFlags or {}
        if isSessionBest then
            session.recordFlags["sessionBestSector" .. tostring(sectorNumber)] = true
        end
        if isRouteBest then
            session.recordFlags["routeBestSector" .. tostring(sectorNumber)] = true
        end
    end

    participant._lapSectorTimes[sectorNumber] = sectorTime
    table.insert(session.sectors, {
        participantId = participant.participantId,
        driverId = participant.driverId,
        isPlayer = participant.isPlayer == true,
        lapNumber = lapNumber or 1,
        sectorNumber = sectorNumber,
        sectorTime = sectorTime,
        completedAt = raceTime,
        valid = participant.validForRecords ~= false,
        provenance = provenance or participant.provenance,
    })

    if participant.isPlayer then
        local liveState = ensureLiveState(session)
        syncBenchmarksToLiveState(session)
        liveState.lastSectorNumber = sectorNumber
        liveState.lastSectorTime = sectorTime
        liveState.lastSectorDelta = routeBest and (sectorTime - routeBest) or nil
        liveState.lastSectorWasSessionBest = isSessionBest
        liveState.lastSectorWasRouteBest = isRouteBest
        liveState.lastSectorLabel = isRouteBest and "PURPLE" or (isSessionBest and "BEST" or "SPLIT")
        if validForRecords then
            local payload = {
                sessionId = session.sessionId,
                routeId = session.routeId,
                routeDisplayName = session.routeDisplayName,
                lapNumber = lapNumber or 1,
                sectorNumber = sectorNumber,
                sectorTime = sectorTime,
                deltaToRouteBest = routeBest and (sectorTime - routeBest) or nil,
            }
            if isRouteBest then
                emitTimingEvent("RouteBestSector", payload)
            elseif isSessionBest then
                emitTimingEvent("SessionBestSector", payload)
            end
        end
    end
end

local function completeSectorBoundaries(session, participant, raceTime, distanceAlong, provenance)
    local boundaries = (session.routeSnapshot and session.routeSnapshot.sectorBoundaries) or {}
    if #boundaries == 0 then return end
    ensureTimingState(participant, raceTime)

    local nextSector = 1
    while participant._sectorCompleted[nextSector] do
        nextSector = nextSector + 1
    end

    while boundaries[nextSector] and distanceAlong >= boundaries[nextSector] do
        local sectorTime = (raceTime or 0.0) - (participant._sectorStartTime or 0.0)
        recordSectorSplit(session, participant, nextSector, participant.currentLap or 1, sectorTime, raceTime, provenance)
        participant._sectorCompleted[nextSector] = true
        participant._sectorStartTime = raceTime or 0.0
        participant.currentSector = math.min(nextSector + 1, math.max(1, #boundaries))
        nextSector = nextSector + 1
    end
end

local function synthesizeSectorsIfNeeded(session, participant, totalTime)
    local boundaries = (session.routeSnapshot and session.routeSnapshot.sectorBoundaries) or {}
    if #boundaries == 0 or not totalTime then return end
    if #session.sectors > 0 then
        local hasAny = false
        for _, sector in ipairs(session.sectors) do
            if sector.participantId == participant.participantId then
                hasAny = true
                break
            end
        end
        if hasAny then return end
    end

    local previousEnd = 0.0
    for sectorNumber = 1, #boundaries do
        local sectorEnd = totalTime * (sectorNumber / #boundaries)
        recordSectorSplit(session, participant, sectorNumber, participant.currentLap or 1,
            sectorEnd - previousEnd, sectorEnd, participant.provenance)
        participant._sectorCompleted[sectorNumber] = true
        previousEnd = sectorEnd
    end
    participant.currentSector = #boundaries
end

local function finalizeLapRecord(session, participant, totalTime)
    if participant._lapRecorded or not totalTime then return end
    if not participant._progressInitialized then
        participant._lapStartTime = 0.0
        participant._sectorStartTime = 0.0
        participant._progressInitialized = true
    end

    synthesizeSectorsIfNeeded(session, participant, totalTime)
    completeSectorBoundaries(session, participant, totalTime, session.routeSnapshot and session.routeSnapshot.totalDistance or participant.distanceAlong or 0.0, participant.provenance)

    local lapTime = math.max(0.0, totalTime - (participant._lapStartTime or 0.0))
    local routeBestLap = session.benchmarks and (session.benchmarks.bestLap or session.benchmarks.bestTotalRaceTime) or nil
    local routeBestRaceTime = session.benchmarks and session.benchmarks.bestTotalRaceTime or nil
    local sessionBestLap = participant.isPlayer and session.bestLap or nil
    local validForRecords = participant.validForRecords ~= false and session.validForRecords ~= false
    local isSessionBest = participant.isPlayer and validForRecords and (sessionBestLap == nil or lapTime < sessionBestLap)
    local isRouteBest = participant.isPlayer and validForRecords and (routeBestLap == nil or lapTime < routeBestLap)
    local isRouteRaceBest = participant.isPlayer and validForRecords and
        (routeBestRaceTime == nil or totalTime < routeBestRaceTime)
    local lap = {
        participantId = participant.participantId,
        driverId = participant.driverId,
        isPlayer = participant.isPlayer == true,
        lapNumber = participant.currentLap or 1,
        lapStartTime = participant._lapStartTime or 0.0,
        lapEndTime = totalTime,
        lapTime = lapTime,
        sector1Time = participant._lapSectorTimes[1],
        sector2Time = participant._lapSectorTimes[2],
        sector3Time = participant._lapSectorTimes[3],
        valid = participant.validForRecords ~= false,
        topSpeed = participant.topSpeed,
        averageSpeed = participant.averageSpeed,
        offRouteCount = participant.offRouteCount or 0,
        majorCollisionCount = participant.majorCollisionCount or 0,
        recoveryCount = participant.recoveryCount or 0,
        provenance = participant.provenance,
    }
    table.insert(session.laps, lap)
    participant._lapRecorded = true
    participant.bestLap = participant.bestLap and math.min(participant.bestLap, lapTime) or lapTime
    if participant.isPlayer then
        session.bestLap = session.bestLap and math.min(session.bestLap, lapTime) or lapTime
        session.averageLap = lapTime
        session.benchmarks = session.benchmarks or defaultBenchmarks()
        if isRouteBest then
            session.benchmarks.bestLap = lapTime
        end
        if isRouteRaceBest then
            session.benchmarks.bestTotalRaceTime = totalTime
        end
        session.recordFlags = session.recordFlags or {}
        if isSessionBest then
            session.recordFlags.sessionBestLap = true
        end
        if isRouteBest then
            session.recordFlags.routeBestLap = true
        end
        if isRouteRaceBest then
            session.recordFlags.routeBestRaceTime = true
        end

        local liveState = ensureLiveState(session)
        syncBenchmarksToLiveState(session)
        liveState.lastLapNumber = participant.currentLap or 1
        liveState.lastLapTime = lapTime
        liveState.lastLapDelta = routeBestLap and (lapTime - routeBestLap) or nil
        liveState.lastLapWasSessionBest = isSessionBest
        liveState.lastLapWasRouteBest = isRouteBest
        liveState.lastLapLabel = isRouteBest and "PURPLE" or (isSessionBest and "BEST" or "LAP")

        if validForRecords then
            local payload = {
                sessionId = session.sessionId,
                routeId = session.routeId,
                routeDisplayName = session.routeDisplayName,
                lapNumber = participant.currentLap or 1,
                lapTime = lapTime,
                deltaToRouteBest = routeBestLap and (lapTime - routeBestLap) or nil,
            }
            if isRouteBest then
                emitTimingEvent("RouteBestLap", payload)
            elseif isSessionBest then
                emitTimingEvent("SessionBestLap", payload)
            end
        end
    end
end

local function captureTraceSample(session, snapshot)
    local raceTime = snapshot.raceTime or 0.0
    if session._lastTraceRaceTime and (raceTime - session._lastTraceRaceTime) < TRACE_SAMPLE_INTERVAL then
        return
    end
    session._lastTraceRaceTime = raceTime
    local player = snapshot.player or {}
    table.insert(session.traces.progressSamples, {
        t = raceTime,
        playerProgress = player.completion,
        playerDistanceAlong = player.distanceAlong,
        playerSector = player.sectorIndex,
        playerRemainingDistance = player.remainingDistance,
    })
    if #session.traces.progressSamples > 512 then
        table.remove(session.traces.progressSamples, 1)
    end
end

local function applyProgressToParticipant(session, snapshot)
    local participantId = snapshot.isPlayer and "player" or snapshot.participantId or snapshot.driverId
    if not participantId then return nil end
    local participant = upsertParticipant(session, participantId, {
        participantId = participantId,
        driverId = snapshot.driverId or participantId,
        name = snapshot.name or participantId,
        isPlayer = snapshot.isPlayer == true,
        provenance = snapshot.provenance or "live",
    })

    ensureTimingState(participant, snapshot.raceTime or 0.0)
    participant.name = snapshot.name or participant.name
    participant.driverId = snapshot.driverId or participant.driverId
    participant.finishStatus = snapshot.finishStatus or participant.finishStatus
    participant.provenance = snapshot.provenance or participant.provenance
    participant.currentLap = snapshot.currentLap or snapshot.lapNumber or participant.currentLap
    participant.standingPos = snapshot.standingPos or participant.standingPos
    participant.currentProgress = snapshot.completion or participant.currentProgress
    participant.distanceAlong = snapshot.distanceAlong or participant.distanceAlong
    participant.remainingDistance = snapshot.remainingDistance or participant.remainingDistance
    participant.currentSector = snapshot.sectorIndex or participant.currentSector
    participant.lateralDistance = snapshot.lateralDistance
    if snapshot.validForRecords == false then
        participant.validForRecords = false
        if participant.isPlayer then
            session.validForRecords = false
        end
    end
    updateAverageSpeed(participant, snapshot.speed)
    completeSectorBoundaries(session, participant, snapshot.raceTime or 0.0, snapshot.distanceAlong or 0.0, participant.provenance)
    if participant.isPlayer then
        updatePlayerSignalCounters(session, participant, snapshot)
    end
    return participant
end

local function applyResultsToParticipants(session, results, playerFinishStatus)
    for _, result in ipairs(results or {}) do
        local participantId = result.isPlayer and "player" or (result.driverId or result.id or result.name)
        local participant = upsertParticipant(session, participantId, {
            participantId = participantId,
            driverId = result.driverId or result.id or participantId,
            name = result.name or participantId,
            isPlayer = result.isPlayer == true,
            provenance = "runtime",
        })

        participant.name = result.name or participant.name
        participant.finishPos = result.position or participant.finishPos
        participant.standingPos = result.position or participant.standingPos
        participant.teamName = participant.teamName or result.factionName
        participant.estimatedTotalTime = result.estimatedTime or participant.estimatedTotalTime
        participant.distanceAlong = result.distanceAlong ~= nil and result.distanceAlong or participant.distanceAlong
        participant.remainingDistance = result.remainingDistance ~= nil and result.remainingDistance or participant.remainingDistance
        participant.currentProgress = result.progress ~= nil and result.progress or participant.currentProgress

        local finishStatus = result.finishStatus
        if not finishStatus then
            if result.isPlayer then
                finishStatus = playerFinishStatus
            elseif result.time ~= nil then
                finishStatus = "classified"
            else
                finishStatus = "pending"
            end
        end

        participant.finishStatus = finishStatus
        if finishStatus == "classified" or finishStatus == "finished" then
            participant.totalTime = result.time or participant.totalTime
        else
            participant.totalTime = nil
        end
    end
end

local function migrateIndex(document)
    local index = defaultIndex()
    if type(document) ~= "table" then return index end
    if type(document.sessions) == "table" then index.sessions = document.sessions end
    if type(document.routeSessions) == "table" then index.routeSessions = document.routeSessions end
    return index
end

function RaceTelemetry.init()
    local index = Persist.loadVersioned(INDEX_FILE, STORE_VERSION, defaultIndex(), function(document)
        return migrateIndex(document)
    end)
    RaceTelemetry._index = index
    ensureIndexShape()
    RaceTelemetry._activeSessionId = nil
    RaceTelemetry._activeSession = nil
    RaceTelemetry._dirty = false
    RaceTelemetry._flushTimer = 0.0
end

function RaceTelemetry.save()
    ensureIndexShape()
    Persist.save(INDEX_FILE, RaceTelemetry._index)
    if RaceTelemetry._activeSession then
        saveSessionDocument(RaceTelemetry._activeSession)
    end
    RaceTelemetry._dirty = false
    RaceTelemetry._flushTimer = 0.0
end

function RaceTelemetry.beginSession(context)
    context = context or {}
    ensureIndexShape()

    if RaceTelemetry._activeSession then
        RaceTelemetry.abandonActive("superseded", true)
    end

    local session = buildSessionDocument(context)
    session.benchmarks = summarizeRouteBenchmarks(session.routeId)
    syncBenchmarksToLiveState(session)
    RaceTelemetry._activeSessionId = session.sessionId
    RaceTelemetry._activeSession = session
    RaceTelemetry._dirty = false
    RaceTelemetry._flushTimer = 0.0
    saveSessionDocument(session)
    touchIndex(session)

    if MTE and MTE.Routes and MTE.Routes.noteSessionStart then
        MTE.Routes.noteSessionStart(session.routeId, {
            sessionId = session.sessionId,
            timestamp = session.startedAt,
        })
    end

    if MTE and MTE.Events then
        MTE.Events.emit("TelemetrySessionStarted", {
            sessionId = session.sessionId,
            routeId = session.routeId,
        })
    end

    return session.sessionId
end

function RaceTelemetry.recordIncident(name, data)
    local session = RaceTelemetry._activeSession
    if not session then return false end
    local events = session.incidents.events or {}
    table.insert(events, {
        name = name,
        t = data and data.time or nil,
        data = clone(data or {}),
    })
    session.incidents.events = events
    markDirty()
    return true
end

function RaceTelemetry.recordTraceSample(sample)
    local session = RaceTelemetry._activeSession
    if not session then return false end
    local samples = session.traces.progressSamples or {}
    table.insert(samples, clone(sample or {}))
    if #samples > 512 then
        table.remove(samples, 1)
    end
    session.traces.progressSamples = samples
    markDirty()
    return true
end

function RaceTelemetry.updateProgress(snapshot)
    local session = RaceTelemetry._activeSession
    if not session then return false end

    snapshot = snapshot or {}
    session.liveState = session.liveState or {}
    session.liveState.raceTime = snapshot.raceTime or session.liveState.raceTime or 0.0
    session.routeDistance = snapshot.totalDistance or session.routeDistance or (session.routeSnapshot and session.routeSnapshot.totalDistance)

    local playerParticipant = nil
    if snapshot.player then
        local player = applyProgressToParticipant(session, snapshot.player)
        if player then
            playerParticipant = player
            session.liveState.currentLap = player.currentLap or 1
            session.liveState.currentSector = player.currentSector or 1
            session.liveState.playerProgress = player.currentProgress or 0.0
            session.liveState.playerDistanceAlong = player.distanceAlong or 0.0
            session.liveState.playerRemainingDistance = player.remainingDistance
        end
    end

    for _, participantSnapshot in ipairs(snapshot.participants or {}) do
        applyProgressToParticipant(session, participantSnapshot)
    end

    if playerParticipant then
        refreshLivePlayerTiming(session, playerParticipant, session.liveState.raceTime)
    else
        syncBenchmarksToLiveState(session)
    end

    captureTraceSample(session, snapshot)
    markDirty()
    return true
end

function RaceTelemetry.update(dt)
    if not RaceTelemetry._activeSession or not RaceTelemetry._dirty then return end
    RaceTelemetry._flushTimer = (RaceTelemetry._flushTimer or 0.0) + (dt or 0.0)
    if RaceTelemetry._flushTimer < FLUSH_INTERVAL then return end
    saveSessionDocument(RaceTelemetry._activeSession)
    touchIndex(RaceTelemetry._activeSession)
    RaceTelemetry._flushTimer = 0.0
    RaceTelemetry._dirty = false
end

function RaceTelemetry.finalizeActive(result)
    local session = RaceTelemetry._activeSession
    if not session then return nil end

    local metrics = MTE and MTE.Metrics and MTE.Metrics.session or nil
    session.endedAt = now()
    session.finishingPosition = result and result.position or session.finishingPosition
    session.totalRaceTime = result and result.playerTime or session.totalRaceTime
    session.finishStatus = (result and result.isDNF) and "dnf" or "finished"
    session.payout = result and result.payout or 0
    session.repDelta = result and result.repGain or 0
    session.pointsAwarded = result and result.pointsAwarded or 0
    session.clean = resolveSessionClean({
        finishStatus = session.finishStatus,
        clean = result and result.isClean or false,
        safetyRating = clone(result and result.safetyRating or nil),
    })
    session.crashHeavy = metrics and (metrics.crashCount or 0) >= 3 or false
    session.invalidated = result and result.invalidated == true or false
    session.abandoned = false
    session.dnfCause = (result and result.isDNF) and (result.dnfCause or "race_dnf") or nil
    session.validForRecords = not session.invalidated and session.finishStatus == "finished"
    local mergedRecordFlags = clone(session.recordFlags or {})
    for key, value in pairs(result and result.recordFlags or {}) do
        mergedRecordFlags[key] = value
    end
    session.recordFlags = mergedRecordFlags
    session.wagerWon = result and result.wagerWon == true or false
    session.wagerLost = result and result.wagerLost == true or false
    session.wagerAmount = result and result.wagerAmount or 0
    session.safetyRating = clone(result and result.safetyRating or nil)
    session.hype = clone(result and result.hype or nil)

    if result and result.results and result.playerTime then
        local winnerTime = result.results[1] and result.results[1].time or nil
        if winnerTime then
            session.marginToWinner = math.max(0.0, result.playerTime - winnerTime)
        end
    end

    applyMetricsToPlayer(session, metrics)
    applyResultsToParticipants(session, result and result.results or {}, session.finishStatus)

    local player = findParticipant(session, "player")
    if player then
        player.finishPos = session.finishingPosition
        player.finishStatus = session.finishStatus
        player.totalTime = session.totalRaceTime
        player.validForRecords = session.validForRecords
        finalizeLapRecord(session, player, session.totalRaceTime)
    end

    for _, participant in ipairs(session.participants or {}) do
        if not participant.isPlayer and participant.totalTime then
            finalizeLapRecord(session, participant, participant.totalTime)
        end
    end

    syncBenchmarksToLiveState(session)

    saveSessionDocument(session)
    touchIndex(session)

    if MTE and MTE.Routes and MTE.Routes.noteSessionEnd then
        MTE.Routes.noteSessionEnd(session.routeId, {
            sessionId = session.sessionId,
            timestamp = session.endedAt,
            finishStatus = session.finishStatus,
            position = session.finishingPosition,
        })
    end

    if MTE and MTE.Events then
        MTE.Events.emit("TelemetrySessionFinished", {
            sessionId = session.sessionId,
            routeId = session.routeId,
            finishStatus = session.finishStatus,
        })
    end

    local completed = clone(session)
    RaceTelemetry._activeSessionId = nil
    RaceTelemetry._activeSession = nil
    RaceTelemetry._dirty = false
    RaceTelemetry._flushTimer = 0.0
    return completed
end

function RaceTelemetry.abandonActive(reason, invalidated)
    local session = RaceTelemetry._activeSession
    if not session then return nil end

    session.endedAt = now()
    session.finishStatus = invalidated and "invalid" or "abandoned"
    session.abandoned = not invalidated
    session.invalidated = invalidated == true
    session.validForRecords = false
    session.dnfCause = reason or session.finishStatus

    local player = findParticipant(session, "player")
    if player then
        player.finishStatus = session.finishStatus
        player.validForRecords = false
    end

    syncBenchmarksToLiveState(session)

    saveSessionDocument(session)
    touchIndex(session)

    if MTE and MTE.Routes and MTE.Routes.noteSessionEnd then
        MTE.Routes.noteSessionEnd(session.routeId, {
            sessionId = session.sessionId,
            timestamp = session.endedAt,
            finishStatus = session.finishStatus,
            position = session.finishingPosition,
        })
    end

    local abandoned = clone(session)
    RaceTelemetry._activeSessionId = nil
    RaceTelemetry._activeSession = nil
    RaceTelemetry._dirty = false
    RaceTelemetry._flushTimer = 0.0
    return abandoned
end

function RaceTelemetry.getActiveSessionId()
    return RaceTelemetry._activeSessionId
end

function RaceTelemetry.getActiveSession()
    return RaceTelemetry._activeSession and clone(RaceTelemetry._activeSession) or nil
end

function RaceTelemetry.getActiveTimingStack()
    local session = RaceTelemetry._activeSession
    if not session then return nil end
    return session.liveState and clone(session.liveState) or nil
end

function RaceTelemetry.getSession(sessionId)
    if RaceTelemetry._activeSessionId == sessionId and RaceTelemetry._activeSession then
        return clone(RaceTelemetry._activeSession)
    end
    local session = loadSessionDocument(sessionId)
    return session and clone(session) or nil
end

function RaceTelemetry.getLastCompletedSession()
    ensureIndexShape()
    local latestId = nil
    local latestStartedAt = nil
    for sessionId, summary in pairs(RaceTelemetry._index.sessions or {}) do
        if type(summary) == "table" and (summary.finishStatus == "finished" or summary.finishStatus == "dnf") then
            local startedAt = tonumber(summary.startedAt or 0) or 0
            if not latestId or startedAt > latestStartedAt then
                latestId = sessionId
                latestStartedAt = startedAt
            end
        end
    end
    return latestId and RaceTelemetry.getSession(latestId) or nil
end

function RaceTelemetry.getRouteSessions(routeId, limit)
    ensureIndexShape()
    local results = {}
    local bucket = RaceTelemetry._index.routeSessions[routeId] or {}
    local maxResults = tonumber(limit) or #bucket
    for index, sessionId in ipairs(bucket) do
        if index > maxResults then break end
        local summary = RaceTelemetry._index.sessions[sessionId]
        if summary then
            table.insert(results, clone(summary))
        end
    end
    return results
end

function RaceTelemetry.getRouteSummary(routeId, limit)
    ensureIndexShape()
    local bucket = RaceTelemetry._index.routeSessions[routeId] or {}
    if #bucket == 0 then return nil end

    local summary = {
        routeId = routeId,
        routeDisplayName = nil,
        attempts = #bucket,
        finishes = 0,
        dnfs = 0,
        invalidated = 0,
        bestTotalRaceTime = nil,
        bestLap = nil,
        bestSector1 = nil,
        bestSector2 = nil,
        bestSector3 = nil,
        bestFinish = nil,
        averageFinish = nil,
        averageRaceTime = nil,
        averageLapTime = nil,
        recentAttempts = {},
    }

    local maxResults = tonumber(limit) or math.min(#bucket, 10)
    local finishTotal = 0.0
    local finishCount = 0
    local raceTimeTotal = 0.0
    local raceTimeCount = 0
    local lapTimeTotal = 0.0
    local lapTimeCount = 0

    for index, sessionId in ipairs(bucket) do
        if index > maxResults then break end
        local session = loadSessionDocument(sessionId)
        local indexEntry = RaceTelemetry._index.sessions[sessionId]
        if indexEntry and not summary.routeDisplayName then
            summary.routeDisplayName = indexEntry.routeDisplayName
        end
        if not session then
            goto continue
        end

        summary.routeDisplayName = summary.routeDisplayName or session.routeDisplayName

        if session.finishStatus == "finished" then
            summary.finishes = summary.finishes + 1
            if session.finishingPosition then
                finishTotal = finishTotal + session.finishingPosition
                finishCount = finishCount + 1
                summary.bestFinish = updateBest(summary.bestFinish, session.finishingPosition)
            end
            if session.totalRaceTime then
                raceTimeTotal = raceTimeTotal + session.totalRaceTime
                raceTimeCount = raceTimeCount + 1
                summary.bestTotalRaceTime = updateBest(summary.bestTotalRaceTime, session.totalRaceTime)
            end
        elseif session.finishStatus == "dnf" then
            summary.dnfs = summary.dnfs + 1
        elseif session.finishStatus == "invalid" then
            summary.invalidated = summary.invalidated + 1
        end

        summary.bestLap = updateBest(summary.bestLap, session.bestLap)
        summary.bestSector1 = updateBest(summary.bestSector1, session.bestSector1)
        summary.bestSector2 = updateBest(summary.bestSector2, session.bestSector2)
        summary.bestSector3 = updateBest(summary.bestSector3, session.bestSector3)

        for _, lap in ipairs(session.laps or {}) do
            if lap.isPlayer and lap.lapTime then
                lapTimeTotal = lapTimeTotal + lap.lapTime
                lapTimeCount = lapTimeCount + 1
            end
        end

        table.insert(summary.recentAttempts, {
            sessionId = session.sessionId,
            startedAt = session.startedAt,
            finishStatus = session.finishStatus,
            position = session.finishingPosition,
            totalRaceTime = session.totalRaceTime,
            payout = session.payout,
            repDelta = session.repDelta,
            clean = resolveSessionClean(session),
        })

        ::continue::
    end

    if finishCount > 0 then
        summary.averageFinish = finishTotal / finishCount
    end
    if raceTimeCount > 0 then
        summary.averageRaceTime = raceTimeTotal / raceTimeCount
    end
    if lapTimeCount > 0 then
        summary.averageLapTime = lapTimeTotal / lapTimeCount
    end

    return summary
end

function RaceTelemetry.getRecentRouteSummaries(limit)
    local routes = MTE and MTE.Routes and MTE.Routes.all and MTE.Routes.all() or {}
    local results = {}
    local maxRoutes = tonumber(limit) or math.min(#routes, 5)

    for _, route in ipairs(routes) do
        if route.attemptCount and route.attemptCount > 0 then
            local summary = RaceTelemetry.getRouteSummary(route.routeId, 10)
            if summary then
                summary.routeDisplayName = summary.routeDisplayName or route.displayName
                summary.lastRunAt = route.lastRunAt or route.createdAt
                table.insert(results, summary)
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.lastRunAt or 0) > (b.lastRunAt or 0)
    end)

    while #results > maxRoutes do
        table.remove(results)
    end
    return results
end

function RaceTelemetry.onSessionStart()
    if RaceTelemetry._activeSession and not RaceTelemetry._activeSession.endedAt then
        RaceTelemetry.abandonActive("session_reset", true)
    end
end

function RaceTelemetry.onShutdown()
    if RaceTelemetry._activeSession and not RaceTelemetry._activeSession.endedAt then
        RaceTelemetry.abandonActive("shutdown", true)
    end
end

return RaceTelemetry