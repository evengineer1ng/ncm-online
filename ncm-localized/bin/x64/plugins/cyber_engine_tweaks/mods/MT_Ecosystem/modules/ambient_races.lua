local AmbientRaces = {}

local Persist = require("modules/persistence")

local STORE_FILE = "ambient_races.json"
local STORE_VERSION = 1
local UPDATE_INTERVAL_S = 5.0
local STAGING_LEAD_MINUTES = 15
local MIN_EVENT_SPACING_MINUTES = 35

local DISTRICTS = {
    "Watson",
    "Westbrook",
    "Heywood",
    "Pacifica",
    "Santo Domingo",
    "City Center",
    "Badlands",
}

local TIER_ORDER = {
    "Gonk",
    "Streetkid",
    "Solo",
    "Fixer",
    "Edgerunner",
}

local DEFAULT_DISTRICT_WEIGHTS = {
    ["Watson"] = 1.0,
    ["Westbrook"] = 0.9,
    ["Heywood"] = 1.0,
    ["Pacifica"] = 0.75,
    ["Santo Domingo"] = 1.1,
    ["City Center"] = 0.7,
    ["Badlands"] = 0.85,
}

local DEFAULT_TYPE_WEIGHTS = {
    sprint = 60,
    drag = 25,
    knockout = 15,
}

AmbientRaces._store = {
    version = STORE_VERSION,
    byCareer = {},
}
AmbientRaces._updateAccum = 0.0

local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = clone(entry)
    end
    return copy
end

local function trimEvents(record)
    local active = {}
    local completed = {}
    for _, event in ipairs(record.events or {}) do
        if event.ambientState == "completed" or event.ambientState == "expired" then
            completed[#completed + 1] = event
        else
            active[#active + 1] = event
        end
    end
    table.sort(completed, function(left, right)
        return tonumber(left.resolvedAt or left.createdAt or 0) > tonumber(right.resolvedAt or right.createdAt or 0)
    end)
    for index = 1, math.min(10, #completed) do
        active[#active + 1] = completed[index]
    end
    table.sort(active, function(left, right)
        return tonumber(left.windowStartTotalMinutes or 0) < tonumber(right.windowStartTotalMinutes or 0)
    end)
    record.events = active
end

local function trimArchive(record)
    if type(record.archivedResults) ~= "table" then
        record.archivedResults = {}
        return
    end
    while #record.archivedResults > 25 do
        table.remove(record.archivedResults)
    end
end

local function defaultStore()
    return {
        version = STORE_VERSION,
        byCareer = {},
    }
end

local function ensureStoreShape()
    local store = AmbientRaces._store or defaultStore()
    if type(store.byCareer) ~= "table" then
        store.byCareer = {}
    end
    store.version = STORE_VERSION
    AmbientRaces._store = store
end

local function ensureCareerRecord(career)
    ensureStoreShape()
    local key = tostring(career and career.id or "")
    if key == "" then
        return nil
    end
    local record = AmbientRaces._store.byCareer[key]
    if type(record) ~= "table" then
        record = {
            careerId = key,
            seed = tonumber(career.seed) or 0,
            nextEventOrdinal = 1,
            events = {},
            archivedResults = {},
            lastClock = nil,
            lastResolved = nil,
        }
        AmbientRaces._store.byCareer[key] = record
    end
    if type(record.events) ~= "table" then
        record.events = {}
    end
    if type(record.archivedResults) ~= "table" then
        record.archivedResults = {}
    end
    if record.nextEventOrdinal == nil then
        record.nextEventOrdinal = 1
    end
    record.seed = tonumber(career.seed) or record.seed or 0
    trimEvents(record)
    trimArchive(record)
    return record
end

local function readGameClock()
    local function fallback()
        local stamp = os.date("*t")
        local day = tonumber(stamp.yday or stamp.day or 1) or 1
        local hour = tonumber(stamp.hour or 0) or 0
        local minute = tonumber(stamp.min or 0) or 0
        local minuteOfDay = (hour * 60) + minute
        return {
            source = "real",
            day = day,
            hour = hour,
            minute = minute,
            minuteOfDay = minuteOfDay,
            totalMinutes = (day * 1440) + minuteOfDay,
        }
    end

    local ok, result = pcall(function()
        local ts = Game.GetTimeSystem and Game.GetTimeSystem() or nil
        if not ts then
            return fallback()
        end

        local gameTime = nil
        if ts.GetGameTime then
            gameTime = ts:GetGameTime()
        end

        local hour = nil
        local minute = nil
        local day = nil
        local extracted = false
        local function takeNumber(value)
            local numeric = tonumber(value)
            if numeric ~= nil then
                extracted = true
            end
            return numeric
        end
        if gameTime then
            hour = takeNumber(gameTime.hour or gameTime.Hour or gameTime.hours or gameTime.Hours)
            minute = takeNumber(gameTime.minute or gameTime.Minute or gameTime.minutes or gameTime.Minutes)
            day = takeNumber(gameTime.day or gameTime.Day or gameTime.days or gameTime.Days)
            if not hour and gameTime.GetHour then hour = takeNumber(gameTime:GetHour()) end
            if not minute and gameTime.GetMinute then minute = takeNumber(gameTime:GetMinute()) end
            if not day and gameTime.GetDay then day = takeNumber(gameTime:GetDay()) end
            if not hour and gameTime.GetHours then hour = takeNumber(gameTime:GetHours()) end
            if not minute and gameTime.GetMinutes then minute = takeNumber(gameTime:GetMinutes()) end
            if not day and gameTime.GetDays then day = takeNumber(gameTime:GetDays()) end
        end

        -- Some CET gameTime objects expose fields as nil/function placeholders. Treat
        -- that as an unreadable clock instead of freezing the ambient scheduler at day 1 00:00.
        if not extracted then
            return fallback()
        end

        hour = math.max(0, math.min(23, tonumber(hour) or 0))
        minute = math.max(0, math.min(59, tonumber(minute) or 0))
        day = math.max(1, tonumber(day) or 1)

        local minuteOfDay = (hour * 60) + minute
        return {
            source = "game",
            day = day,
            hour = hour,
            minute = minute,
            minuteOfDay = minuteOfDay,
            totalMinutes = (day * 1440) + minuteOfDay,
        }
    end)

    if ok and type(result) == "table" then
        return result
    end
    return fallback()
end

local function settingsValue(key, fallback)
    if MTE and MTE.Settings and MTE.Settings.get then
        local value = MTE.Settings.get(key)
        if value ~= nil then
            return value
        end
    end
    return fallback
end

local function getConfig()
    return {
        enabled = settingsValue("ambientRacesEnabled", true) == true,
        frequency = math.max(25, math.min(200, tonumber(settingsValue("ambientRaceFrequency", 100)) or 100)),
        maxConcurrent = math.max(1, math.min(8, tonumber(settingsValue("ambientRaceMaxConcurrent", 3)) or 3)),
        observationRadiusM = math.max(50, tonumber(settingsValue("ambientRaceObservationRadiusM", 250)) or 250),
        promotionRadiusM = math.max(50, tonumber(settingsValue("ambientRacePromotionRadiusM", 120)) or 120),
        aggressionBias = math.max(0.4, math.min(2.0, tonumber(settingsValue("ambientRaceAggressionBias", 1.0)) or 1.0)),
        crashBias = math.max(0.2, math.min(2.0, tonumber(settingsValue("ambientRaceCrashBias", 1.0)) or 1.0)),
        windowVarianceHours = math.max(0, math.min(6, tonumber(settingsValue("ambientRaceWindowVarianceHours", 2)) or 2)),
        districtWeights = clone(settingsValue("ambientRaceDistrictWeights", DEFAULT_DISTRICT_WEIGHTS)),
        typeWeights = clone(settingsValue("ambientRaceTypeWeights", DEFAULT_TYPE_WEIGHTS)),
    }
end

function AmbientRaces.isEnabled()
    return getConfig().enabled == true
end

local function chooseWeighted(weights, candidates)
    local total = 0
    local ordered = {}
    for _, key in ipairs(candidates) do
        local weight = math.max(0, tonumber(weights[key]) or 0)
        if weight > 0 then
            total = total + weight
            ordered[#ordered + 1] = { key = key, weight = weight }
        end
    end

    if total <= 0 then
        return candidates[math.random(1, #candidates)]
    end

    local roll = math.random() * total
    local running = 0
    for _, entry in ipairs(ordered) do
        running = running + entry.weight
        if roll <= running then
            return entry.key
        end
    end
    return ordered[#ordered].key
end

local function chooseDistrict(career, cfg)
    local weights = clone(cfg.districtWeights or DEFAULT_DISTRICT_WEIGHTS)
    local preferred = career and career.config and career.config.preferredRegions or nil
    if type(preferred) == "table" then
        for _, district in ipairs(preferred) do
            if weights[district] ~= nil then
                weights[district] = tonumber(weights[district] or 0) + 0.45
            end
        end
    end
    return chooseWeighted(weights, DISTRICTS)
end

local function chooseRaceType(cfg)
    return chooseWeighted(cfg.typeWeights or DEFAULT_TYPE_WEIGHTS, { "sprint", "drag", "knockout" })
end

local function chooseFieldSize()
    local fieldWeights = {
        [4] = 46,
        [6] = 34,
        [8] = 16,
        [10] = 4,
    }
    local fieldSizes = { 4, 6, 8, 10 }
    local total = 0
    for _, size in ipairs(fieldSizes) do
        total = total + fieldWeights[size]
    end
    local roll = math.random(1, total)
    local running = 0
    for _, size in ipairs(fieldSizes) do
        running = running + fieldWeights[size]
        if roll <= running then
            return size
        end
    end
    return 4
end

local function estimateDurationMinutes(fieldSize, raceType)
    local duration = 22 + (math.max(4, tonumber(fieldSize) or 4) * 4)
    if raceType == "drag" then
        duration = duration - 6
    elseif raceType == "knockout" then
        duration = duration + 8
    end
    return math.max(16, duration)
end

local function ambientTierList()
    if MTE and MTE.Roster and MTE.Roster.tierNames then
        local tiers = MTE.Roster.tierNames() or {}
        if #tiers > 0 then
            return tiers
        end
    end
    return TIER_ORDER
end

local function buildEntrantDriverIds(career, tier, fieldSize, district)
    if MTE and MTE.Roster and MTE.Roster.pickQuickRaceField then
        local field = MTE.Roster.pickQuickRaceField(career, fieldSize, district, {
            minTier = tier,
            maxTier = tier,
        }) or {}
        local ids = {}
        local seen = {}
        for _, driver in ipairs(field) do
            if driver and driver.id and not seen[driver.id] then
                ids[#ids + 1] = driver.id
                seen[driver.id] = true
            end
        end
        return ids
    end

    if not (MTE and MTE.Roster and MTE.Roster.pickForRace) or tostring(tier or "") ~= tostring(career and career.tier or "") then
        return {}
    end
    local field = MTE.Roster.pickForRace(career, fieldSize, district) or {}
    local ids = {}
    local seen = {}
    for _, driver in ipairs(field) do
        if driver and driver.id and not seen[driver.id] then
            ids[#ids + 1] = driver.id
            seen[driver.id] = true
        end
    end
    return ids
end

local function combinedEntrantDriverIds(event)
    local ids = {}
    local seen = {}
    for _, driverId in ipairs(event and event.entrantDriverIds or {}) do
        if driverId and not seen[driverId] then
            ids[#ids + 1] = driverId
            seen[driverId] = true
        end
    end
    if type(event and event.managementEntry) == "table" then
        local driverId = event.managementEntry.driverId
        if driverId and not seen[driverId] then
            ids[#ids + 1] = driverId
        end
    end
    return ids
end

local function countScheduledEvents(record, tier)
    local count = 0
    for _, event in ipairs(record.events or {}) do
        local tierMatch = tier == nil or tostring(event.tier or "") == tostring(tier)
        if tierMatch and event.ambientState ~= "completed" and event.ambientState ~= "expired" then
            count = count + 1
        end
    end
    return count
end

local function canAttachManagedEntry(event)
    if not event then
        return false
    end
    if event.ambientState == "completed" or event.ambientState == "expired" then
        return false
    end
    if type(event.managementEntry) == "table" then
        return false
    end
    if event.promotedLive == true then
        return false
    end
    return true
end

local function attachPendingManagementEntry(career, record)
    if not (MTE and MTE.Management and MTE.Management.claimQueuedDriverForEvent) then
        return false
    end

    for _, event in ipairs(record.events or {}) do
        if tostring(event.tier or "") == tostring(career and career.tier or "")
            and canAttachManagedEntry(event)
            and MTE.Management.claimQueuedDriverForEvent(career, event) then
            if event.raceType ~= "knockout" then
                event.promotionEligible = true
            end
            return true
        end
    end
    return false
end

local function desiredConcurrentCount(cfg)
    local scaled = math.floor((cfg.maxConcurrent * math.max(0.40, cfg.frequency / 100.0)) + 0.5)
    return math.max(1, math.min(cfg.maxConcurrent, scaled))
end

local function desiredConcurrentByTier(career, cfg)
    local targets = {}
    local focusTier = tostring(career and career.tier or "")
    local baseFocusCount = desiredConcurrentCount(cfg)
    for _, tier in ipairs(ambientTierList()) do
        targets[tier] = 1
    end
    if focusTier ~= "" then
        targets[focusTier] = math.max(1, tonumber(targets[focusTier] or 1) + math.max(0, baseFocusCount - 1))
    end
    return targets
end

local function nextSpacingAnchor(record, nowTotalMinutes, tier)
    local latest = nowTotalMinutes
    for _, event in ipairs(record.events or {}) do
        if tostring(event.tier or "") == tostring(tier or "")
            and event.ambientState ~= "completed"
            and event.ambientState ~= "expired" then
            latest = math.max(latest, tonumber(event.windowStartTotalMinutes or 0))
        end
    end
    return latest
end

local function buildEvent(career, record, clock, cfg, tier)
    local eventIndex = tonumber(record.nextEventOrdinal or 1) or 1
    local eventTier = tostring(tier or career and career.tier or "Gonk")
    record.nextEventOrdinal = eventIndex + 1

    local spacingAnchor = nextSpacingAnchor(record, clock.totalMinutes, eventTier)
    local maxLead = math.max(110, math.floor(720 / math.max(0.35, cfg.frequency / 100.0)))
    local baseStart = math.max(clock.totalMinutes + 20, spacingAnchor + MIN_EVENT_SPACING_MINUTES)
    local varianceMinutes = math.floor(math.max(0, cfg.windowVarianceHours) * 60)
    local scheduledStart = baseStart + math.random(0, maxLead)
    if varianceMinutes > 0 then
        scheduledStart = scheduledStart + math.random(-varianceMinutes, varianceMinutes)
    end
    scheduledStart = math.max(clock.totalMinutes + 10, scheduledStart)

    local fieldSize = chooseFieldSize()
    local district = chooseDistrict(career, cfg)
    local raceType = chooseRaceType(cfg)
    local duration = estimateDurationMinutes(fieldSize, raceType)
    local day = math.floor(scheduledStart / 1440)
    local minuteOfDay = scheduledStart % 1440

    local event = {
        eventId = string.format("ambient_%s_%04d_%03d", tostring(career.id or "career"), tonumber(day or 0), eventIndex),
        sourceType = "ambient_schedule",
        careerId = career.id,
        tier = eventTier,
        district = district,
        raceType = raceType,
        fieldSize = fieldSize,
        entrantDriverIds = buildEntrantDriverIds(career, eventTier, fieldSize, district),
        windowDay = day,
        scheduledHour = math.floor(minuteOfDay / 60),
        scheduledMinute = minuteOfDay % 60,
        windowOpenTotalMinutes = scheduledStart - STAGING_LEAD_MINUTES,
        windowStartTotalMinutes = scheduledStart,
        windowCloseTotalMinutes = scheduledStart + duration,
        ambientState = "scheduled",
        visibility = "background",
        promotionEligible = eventTier == tostring(career.tier or "")
            and raceType ~= "knockout"
            and fieldSize <= 6
            and math.random() < 0.35,
        promotedLive = false,
        createdAt = os.time(),
        resolvedAt = nil,
        result = nil,
    }

    if eventTier == tostring(career.tier or "")
        and MTE and MTE.Management and MTE.Management.claimQueuedDriverForEvent then
        MTE.Management.claimQueuedDriverForEvent(career, event)
    end
    return event
end

local function findDriver(career, driverId)
    if not (MTE and MTE.Roster and MTE.Roster.findById) then
        return nil
    end
    return MTE.Roster.findById(career, driverId)
end

local function clamp(value, minValue, maxValue)
    local num = tonumber(value) or minValue
    if num < minValue then
        return minValue
    end
    if num > maxValue then
        return maxValue
    end
    return num
end

local function entrantHardwareProfile(career, driver, event)
    local parts = MTE and MTE.Parts or nil
    if type(driver) ~= "table" or not parts then
        return nil
    end

    if parts.ensureRivalVehicleBuild then
        pcall(parts.ensureRivalVehicleBuild, driver, tonumber(career and career.seed) or 0)
    end

    local hardware = nil
    if parts.getDriverHardwareSummary then
        local ok, summary = pcall(parts.getDriverHardwareSummary, driver)
        hardware = ok and summary or nil
    end

    local build = nil
    if parts.getDriverVehicleBuild then
        local ok, vehicleBuild = pcall(parts.getDriverVehicleBuild, driver)
        build = ok and vehicleBuild or nil
    end

    if type(hardware) ~= "table" and type(build) ~= "table" then
        return nil
    end

    local raceType = tostring(event and event.raceType or "sprint")
    local raceFits = build and build.raceFits or nil
    local fitScale = 1.0
    if raceType == "drag" then
        fitScale = tonumber(raceFits and raceFits.drag) or tonumber(hardware and hardware.dragScale) or 1.0
    elseif raceType == "knockout" then
        fitScale = tonumber(raceFits and raceFits.knockout) or tonumber(hardware and hardware.knockoutScale) or 1.0
    elseif raceType == "endurance" or (tonumber(event and event.lapCount) or 1) > 1 then
        fitScale = tonumber(raceFits and raceFits.longRoute) or tonumber(hardware and hardware.sprintScale) or 1.0
    else
        fitScale = tonumber(raceFits and raceFits.sprint) or tonumber(hardware and hardware.sprintScale) or 1.0
    end

    local liveSpeedScale = clamp(hardware and hardware.liveSpeedScale or 1.0, 0.80, 1.25)
    local launchScale = clamp(hardware and hardware.launchScale or 1.0, 0.90, 1.25)
    local controlScale = clamp(hardware and hardware.controlScale or 1.0, 0.90, 1.20)
    local reliabilityScale = clamp(hardware and hardware.reliabilityScale or 1.0, 0.90, 1.20)
    local confidence = clamp(hardware and hardware.confidence or 1.0, 0.90, 1.12)
    fitScale = clamp(fitScale, 0.88, 1.22)

    local paceScale = clamp(1.0 + ((fitScale - 1.0) * 0.55) + ((liveSpeedScale - 1.0) * 0.35) + ((confidence - 1.0) * 0.10), 0.84, 1.20)
    if raceType == "drag" then
        paceScale = clamp(paceScale + ((launchScale - 1.0) * 0.18), 0.84, 1.24)
    end

    return {
        paceScale = paceScale,
        precisionScale = clamp(1.0 + ((controlScale - 1.0) * 0.75) + ((confidence - 1.0) * 0.20), 0.88, 1.16),
        consistencyScale = clamp(1.0 + ((reliabilityScale - 1.0) * 0.65) + ((controlScale - 1.0) * 0.25) + ((confidence - 1.0) * 0.15), 0.88, 1.18),
        varianceScale = clamp(1.0 - ((controlScale - 1.0) * 0.45) - ((confidence - 1.0) * 0.20), 0.78, 1.15),
        crashScale = clamp(1.0 - ((reliabilityScale - 1.0) * 0.85) - ((controlScale - 1.0) * 0.25) - ((raceType == "drag" and (launchScale - 1.0) * 0.20) or 0.0), 0.72, 1.25),
        formBiasBonus = (confidence - 1.0) * 0.18,
    }
end

local function entrantScore(career, driver, event, cfg)
    local pace = tonumber(driver.pace) or 1.0
    local aggression = tonumber(driver.aggression) or 0.5
    local precision = tonumber(driver.precision) or 0.5
    local consistency = tonumber(driver.consistency) or 0.5
    local formBias = tonumber(driver.formBias) or 0.0
    local hardware = entrantHardwareProfile(career, driver, event)

    if hardware then
        pace = pace * hardware.paceScale
        precision = precision * hardware.precisionScale
        consistency = consistency * hardware.consistencyScale
        formBias = formBias + hardware.formBiasBonus
    end

    local score = (pace * 0.58) + (precision * 0.22) + (consistency * 0.20)
    if event.raceType == "drag" then
        score = (pace * 0.68) + (precision * 0.14) + (consistency * 0.18)
    elseif event.raceType == "knockout" then
        score = (pace * 0.52) + (precision * 0.20) + (consistency * 0.28)
    end
    score = score + (formBias * 0.35)

    local aggressionPush = (aggression - 0.5) * (0.12 * cfg.aggressionBias)
    local varianceBand = (1.0 - consistency) * 0.34
    if hardware then
        varianceBand = varianceBand * hardware.varianceScale
    end
    local variance = (math.random() - 0.5) * varianceBand
    local crashChance = math.max(0.0, ((aggression - 0.52) * 0.06 * cfg.crashBias) + ((0.55 - consistency) * 0.03))
    if hardware then
        crashChance = crashChance * hardware.crashScale
    end
    local crashed = math.random() < crashChance
    return score + aggressionPush + variance, crashed
end

local function syntheticRaceBaseTime(event)
    local fieldSize = math.max(4, tonumber(event and event.fieldSize or 4) or 4)
    local raceType = tostring(event and event.raceType or "sprint")
    if raceType == "drag" then
        return 28.0 + (fieldSize * 0.35)
    end
    if raceType == "knockout" then
        return 205.0 + (fieldSize * 4.0)
    end
    return 118.0 + (fieldSize * 3.5)
end

local function archiveResolvedEvent(record, event)
    if type(record) ~= "table" or type(event) ~= "table" or type(event.result) ~= "table" then
        return
    end
    if type(record.archivedResults) ~= "table" then
        record.archivedResults = {}
    end

    local podium = {}
    for index = 1, math.min(3, #(event.result.order or {})) do
        local row = event.result.order[index]
        podium[#podium + 1] = {
            driverId = row and row.driverId or nil,
            name = row and row.name or nil,
            position = row and row.position or index,
        }
    end

    table.insert(record.archivedResults, 1, {
        eventId = event.eventId,
        district = event.district,
        tier = event.tier,
        raceType = event.raceType,
        winnerId = event.result.winnerId,
        winnerName = event.result.winnerName,
        podium = podium,
        managedEntry = clone(event.managementEntry),
        resolvedAt = event.resolvedAt,
    })
    trimArchive(record)
end

local function resolveEvent(career, record, event)
    local cfg = getConfig()
    local entrants = {}
    local seen = {}
    local startPosByDriverId = {}
    local startCursor = 1

    for _, driverId in ipairs(event.entrantDriverIds or {}) do
        local driver = findDriver(career, driverId)
        if driver and tostring(driver.availability or "active") == "active" and not seen[driver.id] then
            entrants[#entrants + 1] = driver
            seen[driver.id] = true
            startPosByDriverId[driver.id] = startCursor
            startCursor = startCursor + 1
        end
    end

    if type(event.managementEntry) == "table" then
        local managedDriver = findDriver(career, event.managementEntry.driverId)
        if managedDriver and tostring(managedDriver.availability or "active") == "active" and not seen[managedDriver.id] then
            entrants[#entrants + 1] = managedDriver
            seen[managedDriver.id] = true
            startPosByDriverId[managedDriver.id] = startCursor
            startCursor = startCursor + 1
        end
    end

    if #entrants <= 0 then
        event.ambientState = "expired"
        event.visibility = "background"
        event.resolvedAt = os.time()
        return false
    end

    local scored = {}
    for _, driver in ipairs(entrants) do
        local score, crashed = entrantScore(career, driver, event, cfg)
        scored[#scored + 1] = {
            driver = driver,
            score = score,
            crashed = crashed == true,
        }
    end

    table.sort(scored, function(left, right)
        if left.crashed ~= right.crashed then
            return right.crashed == true
        end
        return left.score > right.score
    end)

    local results = {}
    local finishByDriverId = {}
    local leaderTime = syntheticRaceBaseTime(event)
    local bestScore = scored[1] and tonumber(scored[1].score or 0.0) or 0.0
    for position, entry in ipairs(scored) do
        local scoreGap = math.max(0.0, bestScore - (tonumber(entry.score) or 0.0))
        local finishTime = leaderTime + ((position - 1) * 1.15) + (scoreGap * 10.0)
        if entry.crashed == true then
            finishTime = finishTime + 7.5
        end
        local row = {
            driverId = entry.driver.id,
            name = entry.driver.name,
            position = position,
            dnf = entry.crashed == true,
            isManaged = type(event.managementEntry) == "table" and event.managementEntry.driverId == entry.driver.id,
            startPos = startPosByDriverId[entry.driver.id] or position,
            finishTime = finishTime,
            gapToLeader = math.max(0.0, finishTime - leaderTime),
            deltaPos = (startPosByDriverId[entry.driver.id] or position) - position,
        }
        results[#results + 1] = row
        finishByDriverId[row.driverId] = row
    end

    if MTE and MTE.Roster and MTE.Roster.applyRaceResult then
        MTE.Roster.applyRaceResult(career, results)
        if MTE.Roster.saveForCareer then
            MTE.Roster.saveForCareer(career)
        end
    end

    event.result = {
        winnerId = results[1] and results[1].driverId or nil,
        winnerName = results[1] and results[1].name or nil,
        order = results,
        finishByDriverId = finishByDriverId,
    }
    event.ambientState = "completed"
    event.visibility = "background"
    event.promotedLive = false
    event.promotedState = nil
    event.resolvedAt = os.time()
    record.lastResolved = {
        eventId = event.eventId,
        district = event.district,
        raceType = event.raceType,
        winnerName = event.result.winnerName,
        resolvedAt = event.resolvedAt,
    }
    archiveResolvedEvent(record, event)

    if MTE and MTE.Management and MTE.Management.onAmbientEventResolved then
        MTE.Management.onAmbientEventResolved(career, event, event.result)
    end

    if MTE and MTE.Championships and MTE.Championships.recordBoxScore then
        local participants = {}
        for _, row in ipairs(results) do
            local driver = findDriver(career, row.driverId)
            participants[#participants + 1] = {
                driverId = row.driverId,
                displayName = row.name,
                startPos = row.startPos,
                finishPos = row.position,
                finishTime = row.finishTime,
                gapToLeader = row.gapToLeader,
                deltaPos = row.deltaPos,
                dnf = row.dnf == true,
                isPlayer = false,
                factionId = driver and driver.factionId or nil,
                factionName = driver and driver.factionName or nil,
            }
        end
        MTE.Championships.recordBoxScore(career, {
            sourceType = event.sourceType or "ambient_schedule",
            eventId = event.eventId,
            tier = event.tier or career.tier,
            raceType = event.raceType,
            trackName = event.trackName or event.district,
            district = event.district,
            timestamp = event.resolvedAt,
            fieldSize = #participants,
            playerInvolved = false,
            participants = participants,
        })
    end

    return true
end

local function updateEventState(career, record, event, clock, promotionBudget)
    if event.ambientState == "completed" or event.ambientState == "expired" then
        event.visibility = "background"
        return promotionBudget, false
    end

    if event.promotedLive == true then
        local dirty = event.visibility ~= "live"
        event.visibility = "live"
        if event.ambientState == "scheduled" then
            event.ambientState = "staging"
            dirty = true
        end
        return promotionBudget, dirty
    end

    local dirty = false
    local previousState = event.ambientState
    if clock.totalMinutes >= tonumber(event.windowCloseTotalMinutes or 0) then
        dirty = resolveEvent(career, record, event) or dirty
    elseif clock.totalMinutes >= tonumber(event.windowStartTotalMinutes or 0) then
        event.ambientState = "active"
    elseif clock.totalMinutes >= tonumber(event.windowOpenTotalMinutes or 0) then
        event.ambientState = "staging"
    else
        event.ambientState = "scheduled"
    end

    if event.ambientState ~= previousState then
        dirty = true
    end

    if promotionBudget > 0 and event.promotionEligible and (event.ambientState == "staging" or event.ambientState == "active") then
        if event.visibility ~= "promotable" then
            dirty = true
        end
        event.visibility = "promotable"
        promotionBudget = promotionBudget - 1
    else
        if event.visibility ~= "background" then
            dirty = true
        end
        event.visibility = "background"
    end

    return promotionBudget, dirty
end

local function maintainSchedule(career, record, clock)
    local cfg = getConfig()
    local dirty = false
    local targets = desiredConcurrentByTier(career, cfg)
    for _, tier in ipairs(ambientTierList()) do
        local target = math.max(0, tonumber(targets[tier] or 0) or 0)
        while countScheduledEvents(record, tier) < target do
            record.events[#record.events + 1] = buildEvent(career, record, clock, cfg, tier)
            dirty = true
        end
    end
    table.sort(record.events, function(left, right)
        return tonumber(left.windowStartTotalMinutes or 0) < tonumber(right.windowStartTotalMinutes or 0)
    end)
    trimEvents(record)
    return dirty
end

local function updateCareer(career)
    if not career then
        return false
    end
    local record = ensureCareerRecord(career)
    if not record then
        return false
    end

    local clock = readGameClock()
    local dirty = maintainSchedule(career, record, clock)
    dirty = attachPendingManagementEntry(career, record) or dirty
    local promotionBudget = 1
    for _, event in ipairs(record.events or {}) do
        local nextBudget, eventDirty = updateEventState(career, record, event, clock, promotionBudget)
        promotionBudget = nextBudget or promotionBudget
        dirty = dirty or eventDirty
    end
    trimEvents(record)
    dirty = maintainSchedule(career, record, clock) or dirty
    record.lastClock = clock
    trimEvents(record)
    return dirty
end

local function formatTime(event)
    return string.format("%02d:%02d", tonumber(event.scheduledHour or 0) or 0, tonumber(event.scheduledMinute or 0) or 0)
end

local function heatSummary(career)
    local record = ensureCareerRecord(career)
    if not record then
        return nil
    end
    local scores = {}
    for _, district in ipairs(DISTRICTS) do
        scores[district] = 0
    end
    for _, event in ipairs(record.events or {}) do
        if event.ambientState ~= "completed" and event.ambientState ~= "expired" then
            local weight = 1
            if event.ambientState == "staging" then
                weight = 2
            elseif event.ambientState == "active" then
                weight = 3
            end
            scores[event.district] = (scores[event.district] or 0) + weight
        end
    end
    local ordered = {}
    for district, score in pairs(scores) do
        ordered[#ordered + 1] = { district = district, score = score }
    end
    table.sort(ordered, function(left, right)
        if left.score == right.score then
            return tostring(left.district) < tostring(right.district)
        end
        return left.score > right.score
    end)
    return ordered
end

function AmbientRaces.init()
    local store = Persist.loadVersioned(STORE_FILE, STORE_VERSION, defaultStore(), function(document)
        if type(document) ~= "table" then
            return defaultStore()
        end
        if type(document.byCareer) ~= "table" then
            document.byCareer = {}
        end
        document.version = STORE_VERSION
        return document
    end)
    AmbientRaces._store = store
    ensureStoreShape()
end

function AmbientRaces.save()
    ensureStoreShape()
    Persist.save(STORE_FILE, AmbientRaces._store)
end

function AmbientRaces.update(dt)
    local cfg = getConfig()
    if not cfg.enabled then
        return
    end

    AmbientRaces._updateAccum = AmbientRaces._updateAccum + math.max(0.0, tonumber(dt) or 0.0)
    if AmbientRaces._updateAccum < UPDATE_INTERVAL_S then
        return
    end
    AmbientRaces._updateAccum = 0.0

    local career = MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active() or nil
    if not career then
        return
    end

    if updateCareer(career) then
        AmbientRaces.save()
    end
end

function AmbientRaces.forceRefresh(career)
    career = career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    if not career then
        return false, "no_active_career"
    end
    local dirty = updateCareer(career)
    if dirty then
        AmbientRaces.save()
    end
    return true, AmbientRaces.statusText(career)
end

function AmbientRaces.getCareerEvents(career)
    local record = ensureCareerRecord(career)
    if not record then
        return {}
    end
    return clone(record.events)
end

function AmbientRaces.getEventById(career, eventId)
    local record = ensureCareerRecord(career)
    if not record or not eventId then
        return nil
    end
    for _, event in ipairs(record.events or {}) do
        if event.eventId == eventId then
            return event
        end
    end
    return nil
end

function AmbientRaces.currentLiveEvent(career)
    local record = ensureCareerRecord(career)
    if not record then
        return nil
    end
    for _, event in ipairs(record.events or {}) do
        if event.promotedLive == true and event.ambientState ~= "completed" and event.ambientState ~= "expired" then
            return event
        end
    end
    return nil
end

function AmbientRaces.getPromotableEvent(career, options)
    options = options or {}
    local record = ensureCareerRecord(career)
    if not record then
        return nil
    end

    local bestManaged = nil
    local bestOpen = nil
    for _, event in ipairs(record.events or {}) do
        if event.ambientState ~= "completed"
            and event.ambientState ~= "expired"
            and event.promotedLive ~= true
            and tostring(event.tier or "") == tostring(career and career.tier or "")
            and event.promotionEligible == true
            and (event.ambientState == "staging" or event.ambientState == "active") then
            local isManaged = type(event.managementEntry) == "table"
            if options.requireManaged and not isManaged then
            elseif isManaged and not bestManaged then
                bestManaged = event
            elseif not bestOpen then
                bestOpen = event
            end
        end
    end

    if options.requireManaged then
        return bestManaged
    end
    if options.preferManaged and bestManaged then
        return bestManaged
    end
    return bestManaged or bestOpen
end

local function isManualStageCandidate(career, event)
    return type(event) == "table"
        and event.ambientState ~= "completed"
        and event.ambientState ~= "expired"
        and event.promotedLive ~= true
        and tostring(event.tier or "") == tostring(career and career.tier or "")
        and tostring(event.raceType or "") ~= "knockout"
        and math.max(0, tonumber(event.fieldSize or 0) or 0) > 0
        and math.max(0, tonumber(event.fieldSize or 0) or 0) <= 6
end

local function prepareManualStageEvent(event, clock)
    if type(event) ~= "table" then
        return nil
    end
    local nowTotalMinutes = tonumber(clock and clock.totalMinutes or 0) or 0
    local startTotalMinutes = nowTotalMinutes + 2
    local durationMinutes = estimateDurationMinutes(event.fieldSize, event.raceType)
    local eventDay = math.floor(startTotalMinutes / 1440)
    local minuteOfDay = startTotalMinutes % 1440

    event.windowDay = eventDay
    event.scheduledHour = math.floor(minuteOfDay / 60)
    event.scheduledMinute = minuteOfDay % 60
    event.windowOpenTotalMinutes = math.max(0, nowTotalMinutes - 1)
    event.windowStartTotalMinutes = startTotalMinutes
    event.windowCloseTotalMinutes = startTotalMinutes + durationMinutes
    event.promotionEligible = true
    event.ambientState = "staging"
    event.visibility = "promotable"
    return event
end

function AmbientRaces.getManualStageCandidate(career, options)
    options = options or {}
    local record = ensureCareerRecord(career)
    if not record then
        return nil
    end

    local bestManaged = nil
    local bestOpen = nil
    for _, event in ipairs(record.events or {}) do
        if isManualStageCandidate(career, event) then
            local isManaged = type(event.managementEntry) == "table"
            if options.requireManaged and not isManaged then
            elseif isManaged and not bestManaged then
                bestManaged = event
            elseif not bestOpen then
                bestOpen = event
            end
        end
    end

    if options.requireManaged then
        return bestManaged
    end
    if options.preferManaged and bestManaged then
        return bestManaged
    end
    return bestManaged or bestOpen
end

function AmbientRaces.promotableStatusText(career)
    if not career then
        return "Ambient board only runs inside a live career."
    end

    local live = AmbientRaces.currentLiveEvent(career)
    if live then
        return string.format(
            "Ambient board: live heat staged in %s, %s at %s, %d-car field%s.",
            tostring(live.district or "Unknown"),
            tostring(live.raceType or "race"),
            formatTime(live),
            tonumber(live.fieldSize or 0) or 0,
            live.managementEntry and string.format(" with %s attached", tostring(live.managementEntry.driverName or live.managementEntry.driverId or "management")) or "")
    end

    local event = AmbientRaces.getPromotableEvent(career, { preferManaged = true })
    if not event then
        return "Ambient board: nothing promotable is stacking right now."
    end

    return string.format(
        "Ambient board: %s %s at %s, %d-car field, state %s%s.",
        tostring(event.district or "Unknown"),
        tostring(event.raceType or "race"),
        formatTime(event),
        tonumber(event.fieldSize or 0) or 0,
        tostring(event.ambientState or "scheduled"),
        event.managementEntry and string.format(", %s attached", tostring(event.managementEntry.driverName or event.managementEntry.driverId or "management")) or "")
end

function AmbientRaces.stagePromotedEvent(career, options)
    options = options or {}
    career = career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    if not career then
        return false, "no_active_career"
    end
    if not AmbientRaces.isEnabled() then
        return false, "Ambient races are disabled in CET settings."
    end

    local live = AmbientRaces.currentLiveEvent(career)
    if live then
        return true, string.format("Live ambient heat already staged in %s.", tostring(live.district or "Unknown"))
    end

    AmbientRaces.forceRefresh(career)
    local event = AmbientRaces.getPromotableEvent(career, {
        preferManaged = options.preferManaged == true,
        requireManaged = options.requireManaged == true,
    })
    if not event then
        event = AmbientRaces.getManualStageCandidate(career, {
            preferManaged = options.preferManaged == true,
            requireManaged = options.requireManaged == true,
        })
        if event then
            prepareManualStageEvent(event, readGameClock())
        end
    end
    if not event then
        return false, options.requireManaged and "No managed ambient heat is promotable yet." or "No promotable ambient heat is ready."
    end
    if not (MTE and MTE.Racing and MTE.Racing.stageAmbientEvent) then
        return false, "ambient_bridge_unavailable"
    end

    local ok, message = MTE.Racing.stageAmbientEvent(event, {
        spectator = options.spectator == true,
    })
    if not ok then
        return false, message
    end

    event.promotedLive = true
    event.promotedState = options.spectator == true and "spectator_prerace" or "live_prerace"
    event.visibility = "live"
    event.promotedAt = os.time()
    AmbientRaces.save()
    return true, message
end

function AmbientRaces.onLiveRaceClosed(career, eventId, wasResolved)
    local event = AmbientRaces.getEventById(career, eventId)
    if not event then
        return false
    end
    if wasResolved then
        event.promotedLive = false
        event.promotedState = nil
        event.visibility = "background"
    else
        event.promotedLive = false
        event.promotedState = nil
        event.visibility = event.promotionEligible and "promotable" or "background"
    end
    AmbientRaces.save()
    return true
end

function AmbientRaces.resolveLivePromotedEvent(career, eventId)
    career = career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    if not career then
        return false, "no_active_career"
    end
    local record = ensureCareerRecord(career)
    local event = AmbientRaces.getEventById(career, eventId)
    if not record or not event then
        return false, "event_not_found"
    end

    event.windowCloseTotalMinutes = (readGameClock().totalMinutes or 0) - 1
    local ok = resolveEvent(career, record, event)
    AmbientRaces.save()
    if ok then
        return true, string.format("Resolved live ambient heat in %s.", tostring(event.district or "Unknown")), event
    end
    return false, "resolve_failed"
end

function AmbientRaces.statusSummaryLine(career)
    if not career then
        return nil
    end
    local record = ensureCareerRecord(career)
    if not record then
        return nil
    end

    local liveCount = 0
    local promotable = 0
    local nextEvent = nil
    for _, event in ipairs(record.events or {}) do
        if event.ambientState ~= "completed" and event.ambientState ~= "expired" then
            liveCount = liveCount + 1
            if not nextEvent then
                nextEvent = event
            end
            if event.visibility == "promotable" then
                promotable = promotable + 1
            end
        end
    end
    if not nextEvent then
        return "Ambient: no scheduled windows."
    end
    local line = string.format("Ambient: %d window%s, next %s %s at %s", liveCount, liveCount == 1 and "" or "s", tostring(nextEvent.district or "?"), tostring(nextEvent.raceType or "race"), formatTime(nextEvent))
    if promotable > 0 then
        line = line .. string.format(", %d promotable", promotable)
    end
    return line
end

function AmbientRaces.statusText(career)
    if not career then
        return "Ambient races only run inside a live career."
    end

    local record = ensureCareerRecord(career)
    if not record then
        return "Ambient scheduler unavailable."
    end

    local lines = {}
    local summary = AmbientRaces.statusSummaryLine(career)
    if summary then
        lines[#lines + 1] = summary .. "."
    end

    local shown = 0
    for _, event in ipairs(record.events or {}) do
        if event.ambientState ~= "completed" and event.ambientState ~= "expired" then
            lines[#lines + 1] = string.format(
                "%s: %s %s, %d-car field, state %s%s.",
                tostring(event.district or "Unknown"),
                tostring(event.raceType or "race"),
                formatTime(event),
                tonumber(event.fieldSize or 0) or 0,
                tostring(event.ambientState or "scheduled"),
                event.managementEntry and ", managed slot attached" or "")
            shown = shown + 1
            if shown >= 3 then
                break
            end
        end
    end

    if record.lastResolved and record.lastResolved.winnerName then
        lines[#lines + 1] = string.format(
            "Last resolve: %s took %s in %s.",
            tostring(record.lastResolved.winnerName),
            tostring(record.lastResolved.raceType or "a race"),
            tostring(record.lastResolved.district or "Unknown"))
    end

    if type(record.archivedResults) == "table" and #record.archivedResults > 0 then
        lines[#lines + 1] = string.format("Archive: %d resolved ambient result%s on file.", #record.archivedResults, #record.archivedResults == 1 and "" or "s")
    end

    return table.concat(lines, " ")
end

function AmbientRaces.ricoDistrictHeatText(career)
    if not career then
        return nil
    end
    local ordered = heatSummary(career)
    if not ordered or #ordered <= 0 then
        return nil
    end

    local hot = ordered[1]
    local second = ordered[2]
    local cold = ordered[#ordered]
    if not hot or (tonumber(hot.score) or 0) <= 0 then
        return "Read: the city is quiet right now. Nothing is stacking hard enough to call hot."
    end
    return string.format(
        "Read: %s is carrying the most heat. %s is next. %s is the quiet lane.",
        tostring(hot.district),
        second and tostring(second.district) or tostring(hot.district),
        cold and tostring(cold.district) or tostring(hot.district))
end

function AmbientRaces.forceResolveNext(career)
    career = career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    if not career then
        return false, "no_active_career"
    end
    local record = ensureCareerRecord(career)
    if not record then
        return false, "ambient_unavailable"
    end

    for _, event in ipairs(record.events or {}) do
        if event.ambientState ~= "completed" and event.ambientState ~= "expired" then
            event.windowCloseTotalMinutes = (readGameClock().totalMinutes or 0) - 1
            local ok = resolveEvent(career, record, event)
            AmbientRaces.save()
            if ok then
                return true, string.format("Resolved %s.", tostring(event.eventId))
            end
            return false, "resolve_failed"
        end
    end
    return false, "no_pending_events"
end

function AmbientRaces.forceResolveManagedEvent(career)
    career = career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    if not career then
        return false, "no_active_career"
    end
    AmbientRaces.forceRefresh(career)
    local live = AmbientRaces.currentLiveEvent(career)
    if live and type(live.managementEntry) == "table" then
        return AmbientRaces.resolveLivePromotedEvent(career, live.eventId)
    end
    local record = ensureCareerRecord(career)
    for _, event in ipairs(record.events or {}) do
        if type(event.managementEntry) == "table" and event.ambientState ~= "completed" and event.ambientState ~= "expired" then
            event.windowCloseTotalMinutes = (readGameClock().totalMinutes or 0) - 1
            local ok = resolveEvent(career, record, event)
            AmbientRaces.save()
            if ok then
                return true, string.format("Resolved managed run in %s.", tostring(event.district or "Unknown"))
            end
            return false, "resolve_failed"
        end
    end
    return false, "no_managed_event"
end

return AmbientRaces