local SafetyRating = {}

local Persist = require("modules/persistence")

local STORE_FILE = "safety_rating.json"
local STORE_VERSION = 1

local MIN_SR = 0.00
local MAX_SR = 9.99
local STARTING_SR = 5.00
local INCIDENT_CHAIN_TIMEOUT = 1.75
local CLEAN_SR_PER_KM = 0.03
local CLEAN_RACE_BONUS = 0.04
local INCIDENT_POINT_PENALTY = 0.18
local MAX_SR_GAIN = 0.20
local MAX_SR_LOSS = 0.90

local INCIDENT_BUCKETS = {
    { threshold = 34.0, points = 4, label = "4x" },
    { threshold = 26.0, points = 2, label = "2x" },
    { threshold = 20.0, points = 1, label = "1x" },
}

SafetyRating._store = {
    version = STORE_VERSION,
    quickRace = nil,
    careers = {},
}
SafetyRating._activeRace = nil
SafetyRating._listenerRegistered = false

local function clone(value)
    return Persist.clone and Persist.clone(value) or value
end

local function now()
    return os.time()
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function round2(value)
    return math.floor((tonumber(value) or 0.0) * 100 + 0.5) / 100
end

local function defaultProfile(scopeType, careerId)
    return {
        scopeType = scopeType,
        careerId = careerId,
        currentSR = STARTING_SR,
        totalDistanceM = 0.0,
        totalIncidentPoints = 0,
        raceCount = 0,
        cleanRaceCount = 0,
        bestCleanDistanceM = 0.0,
        lastRace = nil,
        lastSRDelta = 0.0,
        updatedAt = now(),
    }
end

local function defaultStore()
    return {
        version = STORE_VERSION,
        quickRace = defaultProfile("quick_race", nil),
        careers = {},
    }
end

local function ensureStoreShape()
    local store = SafetyRating._store or defaultStore()
    if type(store.quickRace) ~= "table" then
        store.quickRace = defaultProfile("quick_race", nil)
    end
    if type(store.careers) ~= "table" then
        store.careers = {}
    end
    store.version = STORE_VERSION
    SafetyRating._store = store
end

local function migrateStore(document)
    local store = defaultStore()
    if type(document) ~= "table" then
        return store
    end
    if type(document.quickRace) == "table" then
        store.quickRace = document.quickRace
    end
    if type(document.careers) == "table" then
        store.careers = document.careers
    end
    return store
end

local function profileLabel(scopeType)
    if scopeType == "quick_race" then
        return "Quick Race SR"
    end
    return "Career SR"
end

local function incidentCountsTemplate()
    return {
        ["1x"] = 0,
        ["2x"] = 0,
        ["4x"] = 0,
    }
end

local function profileForScope(scopeType, careerId)
    ensureStoreShape()
    if scopeType == "career" and careerId then
        local profile = SafetyRating._store.careers[careerId]
        if type(profile) ~= "table" then
            profile = defaultProfile("career", careerId)
            SafetyRating._store.careers[careerId] = profile
        end
        return profile
    end
    if type(SafetyRating._store.quickRace) ~= "table" then
        SafetyRating._store.quickRace = defaultProfile("quick_race", nil)
    end
    return SafetyRating._store.quickRace
end

local function metricsSession()
    return MTE and MTE.Metrics and MTE.Metrics.session or nil
end

local function currentMetricsDuration()
    local metrics = metricsSession()
    return metrics and tonumber(metrics.duration) or 0.0
end

local function currentMetricsDistance()
    local metrics = metricsSession()
    return metrics and tonumber(metrics.distanceTraveled) or 0.0
end

local function classifyIncident(deltaV)
    local speedDelta = tonumber(deltaV) or 0.0
    for _, bucket in ipairs(INCIDENT_BUCKETS) do
        if speedDelta >= bucket.threshold then
            return bucket.points, bucket.label
        end
    end
    return INCIDENT_BUCKETS[#INCIDENT_BUCKETS].points, INCIDENT_BUCKETS[#INCIDENT_BUCKETS].label
end

local function pushTelemetryIncident(incident)
    local active = SafetyRating._activeRace
    if not active then return false end
    if MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.recordIncident and active.telemetrySessionAttached then
        MTE.RaceTelemetry.recordIncident("SafetyIncident", incident)
        return true
    end
    active.pendingTelemetryIncidents[#active.pendingTelemetryIncidents + 1] = clone(incident)
    return false
end

local function updateIncidentSeverity(active, oldLabel, newLabel, oldPoints, newPoints)
    active.incidentCounts[oldLabel] = math.max(0, (active.incidentCounts[oldLabel] or 0) - 1)
    active.incidentCounts[newLabel] = (active.incidentCounts[newLabel] or 0) + 1
    active.incidentPoints = active.incidentPoints + (newPoints - oldPoints)
end

local function computeSRDelta(profile, distanceM, incidentPoints)
    local cleanKm = math.max(0.0, (tonumber(distanceM) or 0.0) / 1000.0)
    local positive = cleanKm * CLEAN_SR_PER_KM
    if incidentPoints <= 0 and cleanKm >= 0.75 then
        positive = positive + CLEAN_RACE_BONUS
    end
    if (profile.currentSR or STARTING_SR) >= 8.0 then
        positive = positive * 0.65
    elseif (profile.currentSR or STARTING_SR) <= 2.0 then
        positive = positive * 1.10
    end
    local negative = (tonumber(incidentPoints) or 0) * INCIDENT_POINT_PENALTY
    local delta = positive - negative
    return clamp(delta, -MAX_SR_LOSS, MAX_SR_GAIN)
end

local function raceScopeLabel(active)
    return profileLabel(active and active.scopeType or "quick_race")
end

local function attachTelemetrySessionToActiveRace()
    local active = SafetyRating._activeRace
    if not active or active.telemetrySessionAttached then return false end
    if not (MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.recordIncident) then return false end
    active.telemetrySessionAttached = true
    for _, incident in ipairs(active.pendingTelemetryIncidents or {}) do
        MTE.RaceTelemetry.recordIncident("SafetyIncident", clone(incident))
    end
    active.pendingTelemetryIncidents = {}
    return true
end

local function buildRaceSummary(active, profile, result, distanceM, beforeSR, afterSR)
    local deltaSR = round2(afterSR - beforeSR)
    return {
        scopeType = active.scopeType,
        scopeLabel = raceScopeLabel(active),
        careerId = active.careerId,
        sessionId = active.telemetrySessionId,
        sourceType = active.sourceType,
        beforeSR = round2(beforeSR),
        afterSR = round2(afterSR),
        deltaSR = deltaSR,
        incidentPoints = active.incidentPoints,
        incidentCounts = clone(active.incidentCounts),
        distanceM = math.max(0.0, tonumber(distanceM) or 0.0),
        finishStatus = result and result.finishStatus or ((result and result.isDNF) and "dnf" or "finished"),
        aborted = result and result.aborted == true or false,
        updatedAt = now(),
        totalIncidentPoints = profile.totalIncidentPoints,
        totalDistanceM = round2(profile.totalDistanceM),
    }
end

function SafetyRating.init()
    local store = Persist.loadVersioned(STORE_FILE, STORE_VERSION, defaultStore(), function(document)
        return migrateStore(document)
    end)
    SafetyRating._store = store
    ensureStoreShape()
    SafetyRating.save()

    if not SafetyRating._listenerRegistered and MTE and MTE.Events and MTE.Events.on then
        MTE.Events.on("ImpactSpike", function(payload)
            SafetyRating.onImpactSpike(payload)
        end)
        SafetyRating._listenerRegistered = true
    end
end

function SafetyRating.save()
    ensureStoreShape()
    Persist.save(STORE_FILE, SafetyRating._store)
end

function SafetyRating.beginRace(context)
    context = context or {}
    local scopeType = context.scopeType == "career" and "career" or "quick_race"
    local careerId = scopeType == "career" and context.careerId or nil

    if SafetyRating._activeRace then
        local active = SafetyRating._activeRace
        if context.telemetrySessionId and not active.telemetrySessionId then
            active.telemetrySessionId = context.telemetrySessionId
            attachTelemetrySessionToActiveRace()
        end
        return clone(active)
    end

    local profile = profileForScope(scopeType, careerId)
    local active = {
        scopeType = scopeType,
        careerId = careerId,
        careerName = context.careerName,
        sourceType = context.sourceType,
        telemetrySessionId = context.telemetrySessionId,
        telemetrySessionAttached = false,
        startedAt = now(),
        startMetricsDistance = currentMetricsDistance(),
        startMetricsDuration = currentMetricsDuration(),
        incidentPoints = 0,
        incidentCounts = incidentCountsTemplate(),
        pendingTelemetryIncidents = {},
        chain = nil,
        beforeSR = tonumber(profile.currentSR) or STARTING_SR,
    }
    SafetyRating._activeRace = active
    attachTelemetrySessionToActiveRace()
    return clone(active)
end

function SafetyRating.attachTelemetrySession(sessionId)
    local active = SafetyRating._activeRace
    if not active then return false end
    active.telemetrySessionId = sessionId
    return attachTelemetrySessionToActiveRace()
end

function SafetyRating.isRaceActive()
    return SafetyRating._activeRace ~= nil
end

function SafetyRating.cancelActiveRace(reason)
    if not SafetyRating._activeRace then return false end
    SafetyRating._activeRace = nil
    return true
end

function SafetyRating.onImpactSpike(payload)
    local active = SafetyRating._activeRace
    if not active or type(payload) ~= "table" then return false end

    local metrics = payload.session or metricsSession()
    if not metrics then return false end

    local metricDuration = tonumber(metrics.duration) or currentMetricsDuration()
    if metricDuration < (active.startMetricsDuration or 0.0) then
        return false
    end

    local deltaV = payload.data and payload.data.deltaV or 0.0
    local speedKph = payload.data and payload.data.speed or 0.0
    local points, label = classifyIncident(deltaV)
    local elapsedRaceTime = math.max(0.0, metricDuration - (active.startMetricsDuration or 0.0))

    if active.chain and metricDuration <= (active.chain.untilMetricTime or 0.0) then
        active.chain.untilMetricTime = metricDuration + INCIDENT_CHAIN_TIMEOUT
        if points > (active.chain.points or 0) then
            local oldPoints = active.chain.points
            local oldLabel = active.chain.label
            updateIncidentSeverity(active, oldLabel, label, oldPoints, points)
            active.chain.points = points
            active.chain.label = label
            pushTelemetryIncident({
                time = elapsedRaceTime,
                label = label,
                points = points,
                deltaV = round2(deltaV),
                speedKph = round2(speedKph),
                upgradeFrom = oldLabel,
            })
        end
        return true
    end

    active.chain = {
        untilMetricTime = metricDuration + INCIDENT_CHAIN_TIMEOUT,
        points = points,
        label = label,
    }
    active.incidentPoints = active.incidentPoints + points
    active.incidentCounts[label] = (active.incidentCounts[label] or 0) + 1
    pushTelemetryIncident({
        time = elapsedRaceTime,
        label = label,
        points = points,
        deltaV = round2(deltaV),
        speedKph = round2(speedKph),
    })

    if MTE and MTE.Events and MTE.Events.emit then
        MTE.Events.emit("SafetyIncidentRecorded", {
            scopeType = active.scopeType,
            careerId = active.careerId,
            label = label,
            points = points,
            totalIncidentPoints = active.incidentPoints,
            time = elapsedRaceTime,
        })
    end
    return true
end

function SafetyRating.finishRace(result)
    local active = SafetyRating._activeRace
    if not active then return nil end

    local profile = profileForScope(active.scopeType, active.careerId)
    local distanceM = math.max(0.0, currentMetricsDistance() - (active.startMetricsDistance or 0.0))
    local beforeSR = tonumber(profile.currentSR) or STARTING_SR
    local delta = computeSRDelta(profile, distanceM, active.incidentPoints)
    local afterSR = clamp(beforeSR + delta, MIN_SR, MAX_SR)

    profile.currentSR = round2(afterSR)
    profile.totalDistanceM = round2((tonumber(profile.totalDistanceM) or 0.0) + distanceM)
    profile.totalIncidentPoints = (tonumber(profile.totalIncidentPoints) or 0) + active.incidentPoints
    profile.lastSRDelta = round2(profile.currentSR - beforeSR)
    profile.updatedAt = now()
    if distanceM > 0.0 or active.incidentPoints > 0 then
        profile.raceCount = (tonumber(profile.raceCount) or 0) + 1
    end
    if active.incidentPoints == 0 and distanceM > 0.0 then
        profile.cleanRaceCount = (tonumber(profile.cleanRaceCount) or 0) + 1
        profile.bestCleanDistanceM = math.max(tonumber(profile.bestCleanDistanceM) or 0.0, distanceM)
    end

    local summary = buildRaceSummary(active, profile, result or {}, distanceM, beforeSR, profile.currentSR)
    profile.lastRace = clone(summary)
    SafetyRating.save()
    SafetyRating._activeRace = nil
    return summary
end

function SafetyRating.getQuickRaceProfile()
    local profile = profileForScope("quick_race", nil)
    return clone(profile)
end

function SafetyRating.getCareerProfile(careerOrId)
    local careerId = type(careerOrId) == "table" and careerOrId.id or careerOrId
    if not careerId then return clone(defaultProfile("career", nil)) end
    local profile = profileForScope("career", careerId)
    return clone(profile)
end

function SafetyRating.removeCareerProfile(careerId)
    ensureStoreShape()
    if not careerId or not SafetyRating._store.careers[careerId] then
        return false
    end
    SafetyRating._store.careers[careerId] = nil
    SafetyRating.save()
    return true
end

return SafetyRating