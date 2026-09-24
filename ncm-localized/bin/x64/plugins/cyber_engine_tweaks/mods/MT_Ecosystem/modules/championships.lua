-- ============================================================
-- MT_Ecosystem: modules/championships.lua
-- Season / championship layer — entirely separate from the
-- prestige tier (Gonk → Edgerunner) system.
--
-- Responsibilities:
--   • Ruleset definitions per tier
--   • Season creation and persistent schedule generation
--   • Driver championship standings
--   • Faction / constructors championship standings
--   • Points award after each completed race
--   • Season completion detection and event emission
--   • Player faction assignment (Independent / Signed / Custom)
--   • Career migration for existing saves
--
-- Design rule: winning a season does NOT replace prestige rep;
-- the prestige ladder is handled entirely by careers.lua.
-- Championship is a parallel competition layer.
-- ============================================================

local Championships = {}

local Factions = require("data/factions")
local Circuits = require("data/circuits")
local Routes = require("modules/routes")
local EventDefs = require("modules/event_definitions")

-- ── LCG (mirrors roster.lua for schedule seeding) ─────────────
local LCG_A = 1664525
local LCG_C = 1013904223
local LCG_M = 4294967296   -- 2^32

-- ── Points tables ─────────────────────────────────────────────
local POINTS_TABLES = {
    standard = { 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 },
    sprint   = { 12,  9,  7,  6,  5, 4, 3, 2, 1    },
    knockout = { 10,  7,  5,  4,  3, 2, 1           },
}

-- ── Rulesets ──────────────────────────────────────────────────
-- factionScoringMode:
--   "all"      — all team drivers score
--   "best_two" — only best two finishers per team score
--   "best_one" — only highest finisher scores

local RULESETS = {
    gonk_default = {
        id                 = "gonk_default",
        name               = "Gonk Street Series",
        tier               = "Gonk",
        rounds             = 6,
        pointsTable        = POINTS_TABLES.standard,
        fastestLapBonus    = 0,
        poleBonus          = 0,
        dnfPoints          = 0,
        factionScoringMode = "all",
        allowCombat        = true,
        allowStakes        = true,
        eventTypes         = { "sprint", "drag" },
    },
    streetkid_default = {
        id                 = "streetkid_default",
        name               = "Streetkid Pro Circuit",
        tier               = "Streetkid",
        rounds             = 8,
        pointsTable        = POINTS_TABLES.standard,
        fastestLapBonus    = 0,
        poleBonus          = 0,
        dnfPoints          = 0,
        factionScoringMode = "all",
        allowCombat        = false,
        allowStakes        = true,
        eventTypes         = { "sprint", "drag" },
    },
    solo_default = {
        id                 = "solo_default",
        name               = "Solo Championship",
        tier               = "Solo",
        rounds             = 8,
        pointsTable        = POINTS_TABLES.standard,
        fastestLapBonus    = 0,
        poleBonus          = 0,
        dnfPoints          = 0,
        factionScoringMode = "all",
        allowCombat        = false,
        allowStakes        = true,
        eventTypes         = { "sprint", "drag" },
    },
    fixer_default = {
        id                 = "fixer_default",
        name               = "Fixer Grand Prix",
        tier               = "Fixer",
        rounds             = 10,
        pointsTable        = POINTS_TABLES.standard,
        fastestLapBonus    = 1,
        poleBonus          = 1,
        dnfPoints          = 0,
        factionScoringMode = "best_two",
        allowCombat        = false,
        allowStakes        = true,
        eventTypes         = { "sprint", "drag", "knockout" },
    },
    -- Edgerunner: one compact elite championship.
    -- Short schedule; same names and factions recur each season.
    -- This recurrence is a feature — players should recognise the field.
    edgerunner_default = {
        id                 = "edgerunner_default",
        name               = "Edgerunner Elite Series",
        tier               = "Edgerunner",
        rounds             = 6,
        pointsTable        = POINTS_TABLES.standard,
        fastestLapBonus    = 1,
        poleBonus          = 1,
        dnfPoints          = 0,
        factionScoringMode = "best_two",
        allowCombat        = false,
        allowStakes        = true,
        eventTypes         = { "sprint", "knockout" },
    },
}

local RULESET_BY_TIER = {
    Gonk       = RULESETS.gonk_default,
    Streetkid  = RULESETS.streetkid_default,
    Solo       = RULESETS.solo_default,
    Fixer      = RULESETS.fixer_default,
    Edgerunner = RULESETS.edgerunner_default,
}

-- ── District pool for schedule generation ─────────────────────
local DISTRICTS = {
    "Watson", "Westbrook", "Heywood", "Pacifica",
    "City Center", "Santo Domingo", "Badlands",
}

local SUPPORTED_CAREER_EVENT_TYPES = {
    sprint = true,
    drag = true,
    knockout = true,
}

local DEFAULT_KNOCKOUT_ELIMINATION_INTERVAL = 60
local SCHEDULE_VERSION = 2
local BOX_SCORES_MAX_TOTAL = 200
local BOX_SCORES_MAX_PER_TIER = 50
local BOX_SCORES_DEFAULT_PAGE_SIZE = 12

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

local function careerChampionshipConfig(career)
    local normalized = {
        eventMix = "mixed",
        lastRaceKnockout = false,
    }
    local raw = career and career.championshipConfig or nil
    if type(raw) ~= "table" then
        return normalized
    end

    if raw.eventMix == "drag_only" or raw.eventMix == "sprint_only" or raw.eventMix == "mixed" then
        normalized.eventMix = raw.eventMix
    end
    normalized.lastRaceKnockout = raw.lastRaceKnockout == true
    return normalized
end

local function championshipEventTypesForCareer(career)
    local cfg = careerChampionshipConfig(career)
    if cfg.eventMix == "drag_only" then
        return { "drag" }
    end
    if cfg.eventMix == "sprint_only" then
        return { "sprint" }
    end
    return { "sprint", "drag" }
end

local function estimateDistance(a, b)
    if not a or not b then return 0.0 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function isRaceLegalNode(node)
    if MTE and MTE.Racing and MTE.Racing._isRaceLegalNode then
        return MTE.Racing._isRaceLegalNode(node)
    end
    if not node then return false end
    if node.disabled == true then return false end
    if node.raceLegal == false then return false end
    if node.road == false then return false end
    if node.waypointable == false then return false end
    return true
end

local function isUrbanNode(node)
    if MTE and MTE.Racing and MTE.Racing._isUrbanNode then
        return MTE.Racing._isUrbanNode(node)
    end
    if not node then return false end
    return node.urban ~= false
end

local function createRng(seed)
    local state = math.floor((seed or 0) % LCG_M)

    local function nextFloat()
        state = math.floor((state * LCG_A + LCG_C) % LCG_M)
        return state / LCG_M
    end

    local function nextIndex(count)
        if count <= 1 then return 1 end
        return math.max(1, math.min(count, math.floor(nextFloat() * count) + 1))
    end

    local function shuffled(values)
        local out = {}
        for i, value in ipairs(values or {}) do
            out[i] = value
        end
        for i = #out, 2, -1 do
            local j = nextIndex(i)
            out[i], out[j] = out[j], out[i]
        end
        return out
    end

    return {
        nextFloat = nextFloat,
        nextIndex = nextIndex,
        shuffled = shuffled,
    }
end

local function supportedCareerEventTypes(ruleset)
    local supported = {}
    for _, eventType in ipairs(ruleset and ruleset.eventTypes or { "sprint" }) do
        if SUPPORTED_CAREER_EVENT_TYPES[eventType] then
            supported[#supported + 1] = eventType
        end
    end
    if #supported == 0 then
        supported[1] = "sprint"
    end
    return supported
end

local function fieldSizeForEvent(career, eventType)
    local base = career and career.config and career.config.defaultFieldSize or 8
    if eventType == "drag" then
        return math.min(base or 8, 4)
    end
    if eventType == "knockout" then
        return math.max(4, math.min(base or 8, 24))
    end
    return base or 8
end

local function routeDistanceConfig(career, eventType)
    if eventType == "drag" then
        return 400, 1200
    end

    local cfg = career and career.config or {}
    return cfg.minDistanceM or 1500, cfg.maxDistanceM or 8000
end

local function availableRegions(nodes)
    local seen = {}
    local regions = {}
    for _, node in ipairs(nodes or {}) do
        local region = node and node.region or nil
        if region and region ~= "" and not seen[region] then
            seen[region] = true
            regions[#regions + 1] = region
        end
    end
    if #regions == 0 then
        for _, region in ipairs(DISTRICTS) do
            regions[#regions + 1] = region
        end
    end
    return regions
end

local function collectRouteCandidates(nodes, preferredRegion, requireUrban)
    local out = {}
    for _, node in ipairs(nodes or {}) do
        local regionOk = not preferredRegion or (node.region == preferredRegion)
        if regionOk and isRaceLegalNode(node) then
            if not requireUrban or isUrbanNode(node) then
                out[#out + 1] = node
            end
        end
    end
    return out
end

local function chooseRoutePair(nodes, preferredRegion, minDistanceM, maxDistanceM, rng, opts)
    local maxDistanceRatio = opts and opts.maxDistanceRatio or nil
    local function chooseFromCandidates(candidates)
        if not candidates or #candidates < 2 then return nil, nil end
        local starts = rng.shuffled(candidates)
        local startLimit = math.min(#starts, 24)
        for i = 1, startLimit do
            local nodeA = starts[i]
            local finishes = {}
            for _, nodeB in ipairs(candidates) do
                if nodeB ~= nodeA then
                    local distance = estimateDistance(nodeA, nodeB)
                    if distance >= minDistanceM and distance <= maxDistanceM then
                        if maxDistanceRatio then
                            local dx = (nodeB.x or 0) - (nodeA.x or 0)
                            local dy = (nodeB.y or 0) - (nodeA.y or 0)
                            local straightLine = math.sqrt(dx * dx + dy * dy)
                            if straightLine > 0.1 and (distance / straightLine) <= maxDistanceRatio then
                                finishes[#finishes + 1] = nodeB
                            end
                        else
                            finishes[#finishes + 1] = nodeB
                        end
                    end
                end
            end
            if #finishes > 0 then
                local shuffled = rng.shuffled(finishes)
                return nodeA, shuffled[1]
            end
        end
        return nil, nil
    end

    local attempts = {
        { preferredRegion = preferredRegion, requireUrban = true },
        { preferredRegion = preferredRegion, requireUrban = false },
        { preferredRegion = nil, requireUrban = true },
        { preferredRegion = nil, requireUrban = false },
    }

    for _, attempt in ipairs(attempts) do
        local candidates = collectRouteCandidates(nodes, attempt.preferredRegion, attempt.requireUrban)
        local nodeA, nodeB = chooseFromCandidates(candidates)
        if nodeA and nodeB then
            return nodeA, nodeB
        end
    end

    return nil, nil
end

local function chooseKnockoutCircuit(preferredRegion, rng)
    local candidates = {}
    local allCircuits = Circuits.all and Circuits.all() or {}
    for _, circuit in ipairs(allCircuits) do
        if not preferredRegion or circuit.region == preferredRegion then
            candidates[#candidates + 1] = circuit
        end
    end
    if #candidates == 0 then
        candidates = allCircuits
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[rng.nextIndex(#candidates)]
end

local function buildCareerKnockoutEvent(career, seasonId, ruleset, seasonSeed, roundNumber, opts)
    local rng = createRng((seasonSeed or 0) + (roundNumber * 977) + ((opts and opts.seedOffset or 0) * 131))
    local preferredRegion = opts and opts.preferredRegion or nil
    local forcedCircuitId = opts and opts.circuitId or nil
    local circuit = forcedCircuitId and Circuits.get(forcedCircuitId) or chooseKnockoutCircuit(preferredRegion, rng)
    local validationErrors = {}
    if not circuit then
        validationErrors[#validationErrors + 1] = "No valid knockout circuit found in the active circuit pool."
    end

    return EventDefs.buildKnockout({
        sourceType = "career_schedule",
        seasonId = seasonId,
        round = roundNumber,
        leagueTier = career and career.tier or ruleset and ruleset.tier or nil,
        rulesetId = ruleset and ruleset.id or nil,
        startType = "grid",
        fieldSize = fieldSizeForEvent(career, "knockout"),
        allowStakes = false,
        allowCombat = ruleset and ruleset.allowCombat,
        vehicleClass = career and career.config and career.config.vehicleClass or nil,
        timeOfDay = career and career.config and career.config.timeOfDay or nil,
        routeMode = "circuit",
        circuitId = circuit and circuit.id or forcedCircuitId,
        circuitName = circuit and circuit.name or "Knockout Circuit",
        circuitRegion = circuit and circuit.region or preferredRegion,
        districtLabel = circuit and circuit.region or preferredRegion or "Unknown",
        trackName = circuit and circuit.name or "Knockout Circuit",
        titleLabel = circuit and circuit.name or "Knockout Circuit",
        distance = 0,
        estimatedLapTime = circuit and circuit.estimatedLapTime or nil,
        eliminationInterval = opts and opts.eliminationInterval or DEFAULT_KNOCKOUT_ELIMINATION_INTERVAL,
        trafficMode = opts and opts.trafficMode or "normal",
        combatMode = opts and opts.combatMode or ((ruleset and ruleset.allowCombat == false) and "disabled" or "allowed"),
        validationErrors = validationErrors,
    })
end

local function buildCareerEvent(career, seasonId, ruleset, seasonSeed, roundNumber, opts)
    local rng = createRng((seasonSeed or 0) + (roundNumber * 977) + ((opts and opts.seedOffset or 0) * 131))
    local eventTypes = supportedCareerEventTypes(ruleset)
    local forcedType = opts and opts.forceEventType or nil
    local eventType = forcedType
    local routeSource = opts and opts.routeSource or "auto"
    if not SUPPORTED_CAREER_EVENT_TYPES[eventType] then
        eventType = eventTypes[rng.nextIndex(#eventTypes)]
    end
    if not forcedType and ruleset and ruleset.lastRaceKnockout == true and roundNumber == (ruleset.rounds or 0) then
        eventType = "knockout"
    end

    if eventType == "knockout" then
        return buildCareerKnockoutEvent(career, seasonId, ruleset, seasonSeed, roundNumber, opts)
    end

    local legalNodes = {}
    for _, node in ipairs((MTE and MTE.Nodes) or {}) do
        if isRaceLegalNode(node) then
            legalNodes[#legalNodes + 1] = node
        end
    end

    local regions = availableRegions(legalNodes)
    local preferredRegion = opts and opts.preferredRegion or nil
    if not preferredRegion and #regions > 0 then
        preferredRegion = regions[rng.nextIndex(#regions)]
    end

    local minDistanceM, maxDistanceM = routeDistanceConfig(career, eventType)
    local selectedRoot = nil
    if routeSource ~= "random" then
        selectedRoot = MTE and MTE.Roots and MTE.Roots.pickForCareer and MTE.Roots.pickForCareer({
            eventType = eventType,
            preferredRegion = preferredRegion,
            minDistanceM = minDistanceM,
            maxDistanceM = maxDistanceM,
            rng = rng,
        }) or nil
    end
    local nodeA = selectedRoot and selectedRoot.nodeA or nil
    local nodeB = selectedRoot and selectedRoot.nodeB or nil
    if not nodeA or not nodeB then
        local routePairOpts = nil
        if eventType == "drag" then
            -- Reject routes with road-distance/straight-line ratio > 1.15 (too curvy for drag)
            routePairOpts = { maxDistanceRatio = 1.15 }
        end
        nodeA, nodeB = chooseRoutePair(legalNodes, preferredRegion, minDistanceM, maxDistanceM, rng, routePairOpts)
    end
    local startType = career and career.config and career.config.defaultStartType or "grid"
    local routeCfg = {
        raceType = eventType,
        routeMode = selectedRoot and "root" or "scheduled",
        startType = startType,
        allowCombat = ruleset and ruleset.allowCombat,
        distance = selectedRoot and selectedRoot.distanceM or (nodeA and nodeB and estimateDistance(nodeA, nodeB) or 0),
    }
    local route = (nodeA and nodeB) and Routes.resolve(nodeA, nodeB, routeCfg) or nil
    local validationErrors = {}
    if not nodeA or not nodeB then
        validationErrors[#validationErrors + 1] = string.format("No valid %s route found in the active node pool.", tostring(eventType))
    end

    return EventDefs.buildPointToPoint({
        sourceType = "career_schedule",
        seasonId = seasonId,
        round = roundNumber,
        leagueTier = career and career.tier or ruleset and ruleset.tier or nil,
        rulesetId = ruleset and ruleset.id or nil,
        eventType = eventType,
        startType = startType,
        fieldSize = fieldSizeForEvent(career, eventType),
        allowStakes = ruleset and ruleset.allowStakes,
        allowCombat = ruleset and ruleset.allowCombat,
        qualiEnabled = career and career.config and career.config.qualiEnabled or false,
        vehicleClass = career and career.config and career.config.vehicleClass or nil,
        timeOfDay = career and career.config and career.config.timeOfDay or nil,
        routeMode = selectedRoot and "root" or "scheduled",
        selectedRootId = selectedRoot and selectedRoot.rootId or nil,
        nodeA = nodeA,
        nodeB = nodeB,
        route = route,
        rootId = selectedRoot and selectedRoot.rootId or route and route.rootId or nil,
        rootDisplayName = selectedRoot and selectedRoot.primaryLabel or route and route.rootDisplayName or nil,
        subtitleLabel = selectedRoot and selectedRoot.secondaryLabel or route and route.subtitleLabel or nil,
        trackName = selectedRoot and selectedRoot.primaryLabel or route and route.displayName or nil,
        titleLabel = selectedRoot and selectedRoot.primaryLabel or route and route.displayName or nil,
        distance = route and route.totalDistance or routeCfg.distance,
        validationErrors = validationErrors,
    })
end

local function migrateLegacyCompletedEvent(career, season, row)
    return EventDefs.buildLegacyCompleted({
        sourceType = "career_schedule",
        seasonId = season and season.id or nil,
        round = row and row.round or nil,
        leagueTier = season and season.leagueTier or career and career.tier or nil,
        rulesetId = season and season.rulesetId or nil,
        eventType = row and row.eventType or "sprint",
        startType = career and career.config and career.config.defaultStartType or "grid",
        fieldSize = fieldSizeForEvent(career, row and row.eventType or "sprint"),
        allowStakes = season and season._ruleset and season._ruleset.allowStakes or nil,
        allowCombat = season and season._ruleset and season._ruleset.allowCombat or nil,
        qualiEnabled = career and career.config and career.config.qualiEnabled or false,
        vehicleClass = career and career.config and career.config.vehicleClass or nil,
        timeOfDay = career and career.config and career.config.timeOfDay or nil,
        districtLabel = row and row.district or nil,
        titleLabel = row and (row.trackName or row.district) or nil,
        routeId = row and row.routeId or nil,
        distance = row and row.distance or 0,
        completed = row and row.completed ~= false,
        results = row and row.results or nil,
        nodeA = row and row.nodeA or nil,
        nodeB = row and row.nodeB or nil,
    })
end

local function buildSchedulePlan(career, ruleset, seasonSeed)
    local rounds = math.max(1, tonumber(ruleset and ruleset.rounds) or 1)
    local rng = createRng((seasonSeed or 0) + 404)
    local plan = {}
    local legalNodes = {}

    for _, node in ipairs((MTE and MTE.Nodes) or {}) do
        if isRaceLegalNode(node) then
            legalNodes[#legalNodes + 1] = node
        end
    end

    local regions = rng.shuffled(availableRegions(legalNodes))
    if #regions == 0 then
        regions = { "Unknown" }
    end

    local nonKnockoutRounds = rounds
    if ruleset and ruleset.lastRaceKnockout == true and rounds > 1 then
        nonKnockoutRounds = rounds - 1
    end

    local routeSources = {}
    local firstSource = rng.nextIndex(2) == 1 and "root" or "random"
    local rootBudget = math.ceil(nonKnockoutRounds / 2)
    local randomBudget = nonKnockoutRounds - rootBudget
    for i = 1, nonKnockoutRounds do
        local preferred = (i % 2 == 1) and firstSource or (firstSource == "root" and "random" or "root")
        local selected = preferred
        if selected == "root" and rootBudget <= 0 then
            selected = "random"
        elseif selected == "random" and randomBudget <= 0 then
            selected = "root"
        end
        if selected == "root" then
            rootBudget = rootBudget - 1
        else
            randomBudget = randomBudget - 1
        end
        routeSources[i] = selected
    end

    local eventCycle = rng.shuffled(supportedCareerEventTypes(ruleset))
    if #eventCycle == 0 then
        eventCycle = { "sprint" }
    end

    local routeIndex = 1
    local eventIndex = 1
    for roundNumber = 1, rounds do
        local preferredRegion = regions[((roundNumber - 1) % #regions) + 1]
        if ruleset and ruleset.lastRaceKnockout == true and roundNumber == rounds then
            plan[roundNumber] = {
                preferredRegion = preferredRegion,
                eventType = "knockout",
                routeSource = nil,
            }
        else
            plan[roundNumber] = {
                preferredRegion = preferredRegion,
                eventType = eventCycle[eventIndex],
                routeSource = routeSources[routeIndex] or "random",
            }
            routeIndex = routeIndex + 1
            eventIndex = (eventIndex % #eventCycle) + 1
        end
    end

    return plan
end

local function eventDiversityKey(event)
    if type(event) ~= "table" then
        return nil
    end
    if event.eventType == "knockout" then
        return "knockout:" .. tostring(event.circuitId or event.eventId or "unknown")
    end
    if event.rootId then
        return "root:" .. tostring(event.rootId)
    end
    if event.selectedStartNodeId and event.selectedFinishNodeId then
        return "route:" .. tostring(event.selectedStartNodeId) .. "->" .. tostring(event.selectedFinishNodeId)
    end
    return event.eventId
end

function Championships._ensureSeasonSchedule(career, season)
    if not season then return nil end

    if not season._ruleset then
        season._ruleset = Championships.rulesetForCareer(career, season.leagueTier or career and career.tier)
    end
    if not season.seasonSeed then
        season.seasonSeed = (career and career.seed or 0) + ((season.seasonNumber or 1) * 1337)
    end

    local ruleset = season._ruleset or Championships.rulesetForCareer(career, season.leagueTier or career and career.tier)
    local dirty = false
    local completedRounds = 0
    for _, row in ipairs(season.schedule or {}) do
        if type(row) == "table" and row.completed == true then
            completedRounds = completedRounds + 1
        end
    end

    if (season.scheduleVersion or 0) < SCHEDULE_VERSION and completedRounds == 0 then
        season.schedule = generateSchedule(career, season.id, ruleset, season.seasonSeed)
        season.totalRounds = ruleset.rounds
        season.scheduleVersion = SCHEDULE_VERSION
        dirty = true
    end

    if type(season.schedule) ~= "table" then
        season.schedule = {}
        dirty = true
    end

    for roundNumber = 1, season.totalRounds or #season.schedule do
        local row = season.schedule[roundNumber]
        if type(row) ~= "table" then
            season.schedule[roundNumber] = buildCareerEvent(career, season.id, ruleset, season.seasonSeed, roundNumber)
            dirty = true
        elseif row.sourceType == "career_schedule" or row.eventId or row.nodeA or row.nodeB then
            local upgraded = EventDefs.clone(row)
            upgraded.sourceType = "career_schedule"
            upgraded.seasonId = season.id
            upgraded.round = upgraded.round or roundNumber
            upgraded.leagueTier = upgraded.leagueTier or season.leagueTier or career and career.tier
            upgraded.rulesetId = upgraded.rulesetId or season.rulesetId or ruleset and ruleset.id
            upgraded.eventType = upgraded.eventType or upgraded.raceType or "sprint"
            upgraded.raceType = upgraded.raceType or upgraded.eventType or "sprint"
            upgraded.trackName = upgraded.trackName or upgraded.titleLabel or upgraded.circuitName
            upgraded.titleLabel = upgraded.titleLabel or upgraded.trackName or upgraded.circuitName or upgraded.districtLabel or upgraded.district
            upgraded.districtLabel = upgraded.districtLabel or upgraded.district or upgraded.circuitRegion or EventDefs.deriveDistrictLabel(upgraded.nodeA, upgraded.nodeB)
            upgraded.district = upgraded.districtLabel
            upgraded.routeId = upgraded.routeId or upgraded.circuitId or nil
            upgraded.fieldSize = upgraded.fieldSize or fieldSizeForEvent(career, upgraded.eventType)
            upgraded.startType = upgraded.startType or career and career.config and career.config.defaultStartType or "grid"
            upgraded.selectedStartNodeId = upgraded.eventType == "knockout" and nil or upgraded.selectedStartNodeId or upgraded.nodeA and upgraded.nodeA.id or nil
            upgraded.selectedFinishNodeId = upgraded.eventType == "knockout" and nil or upgraded.selectedFinishNodeId or upgraded.nodeB and upgraded.nodeB.id or nil
            upgraded.isValid = upgraded.isValid ~= false and #(upgraded.validationErrors or {}) == 0

            local missingRuntimeContext = (upgraded.eventType == "knockout" and not upgraded.circuitId)
                or (upgraded.eventType ~= "knockout" and (not upgraded.nodeA or not upgraded.nodeB))
            if upgraded.completed ~= true and (missingRuntimeContext or upgraded.isValid == false) then
                upgraded = buildCareerEvent(career, season.id, ruleset, season.seasonSeed, roundNumber, {
                    forceEventType = row.eventType or row.raceType,
                    preferredRegion = row.district or row.districtLabel or row.circuitRegion,
                    circuitId = row.circuitId,
                })
            end

            season.schedule[roundNumber] = upgraded
            if row.eventId ~= upgraded.eventId or row.sourceType ~= upgraded.sourceType then
                dirty = true
            end
        elseif row.completed == true then
            season.schedule[roundNumber] = migrateLegacyCompletedEvent(career, season, row)
            dirty = true
        else
            season.schedule[roundNumber] = buildCareerEvent(career, season.id, ruleset, season.seasonSeed, roundNumber, {
                forceEventType = row.eventType,
                preferredRegion = row.district,
                circuitId = row.circuitId,
            })
            dirty = true
        end
    end

    if dirty and MTE and MTE.Careers and MTE.Careers.save then
        MTE.Careers.save()
    end

    return season.schedule
end

-- ── Schedule generation ───────────────────────────────────────
-- Deterministic from a season seed; never regenerated mid-season.

local function generateSchedule(career, seasonId, ruleset, seasonSeed)
    local schedule = {}
    local plan = buildSchedulePlan(career, ruleset, seasonSeed)
    local usedKeys = {}
    for i = 1, ruleset.rounds do
        local roundPlan = plan[i] or {}
        local selectedEvent = nil
        for attempt = 0, 7 do
            local candidate = buildCareerEvent(career, seasonId, ruleset, seasonSeed, i, {
                forceEventType = roundPlan.eventType,
                preferredRegion = roundPlan.preferredRegion,
                routeSource = roundPlan.routeSource,
                seedOffset = attempt,
            })
            local key = eventDiversityKey(candidate)
            if key == nil or not usedKeys[key] or attempt == 7 then
                selectedEvent = candidate
                if key then usedKeys[key] = true end
                break
            end
        end
        schedule[i] = selectedEvent
    end
    return schedule
end

-- ── Points award (internal) ───────────────────────────────────

local function ensureStandings(season)
    if not season.standings then
        season.standings = { drivers = {}, factions = {} }
    end
    if not season.standings.drivers  then season.standings.drivers  = {} end
    if not season.standings.factions then season.standings.factions = {} end
end

local function ensureBoxScores(career)
    if type(career.boxScores) ~= "table" then
        career.boxScores = {
            nextOrdinal = 1,
            records = {},
        }
    end
    if type(career.boxScores.records) ~= "table" then
        career.boxScores.records = {}
    end
    if career.boxScores.nextOrdinal == nil then
        career.boxScores.nextOrdinal = (#career.boxScores.records or 0) + 1
    end
    return career.boxScores
end

local function formatFallbackRouteName(payload)
    local trackName = payload and payload.trackName or nil
    if type(trackName) == "string" and trackName ~= "" then
        return trackName
    end
    local district = payload and payload.district or nil
    if type(district) == "string" and district ~= "" then
        return district
    end
    return "Unknown Route"
end

local function normaliseFinishTime(value)
    local n = tonumber(value)
    if not n or n <= 0 then
        return nil
    end
    return n
end

local function normaliseFlagList(flags)
    if type(flags) ~= "table" then
        return {}
    end
    local out = {}
    for _, flag in ipairs(flags) do
        if type(flag) == "string" and flag ~= "" then
            out[#out + 1] = flag
        end
    end
    return out
end

local function buildParticipantFlags(participant, leaderTime, nextGap, dnfCount)
    local flags = normaliseFlagList(participant and participant.flags)
    local hasFlag = {}
    for _, flag in ipairs(flags) do
        hasFlag[flag] = true
    end

    local delta = tonumber(participant and participant.deltaPos or 0) or 0
    local finishPos = tonumber(participant and participant.finishPos or 99) or 99
    local finishTime = normaliseFinishTime(participant and participant.finishTime)
    local gap = tonumber(participant and participant.gapToLeader or 0) or 0
    if participant and participant.dnf == true and not hasFlag.chaos then
        flags[#flags + 1] = "chaos"
        hasFlag.chaos = true
    end
    if delta >= 3 and not hasFlag.recovery then
        flags[#flags + 1] = "recovery"
        hasFlag.recovery = true
    elseif delta <= -3 and not hasFlag.collapse then
        flags[#flags + 1] = "collapse"
        hasFlag.collapse = true
    end
    if finishPos == 1 and finishTime and leaderTime and math.abs(finishTime - leaderTime) < 0.001 and (tonumber(nextGap) or 0) >= 1.2 and not hasFlag.dominant then
        flags[#flags + 1] = "dominant"
        hasFlag.dominant = true
    end
    if participant and participant.dnf ~= true and dnfCount <= 0 and math.abs(delta) <= 1 and finishPos <= 3 and not hasFlag.clean then
        flags[#flags + 1] = "clean"
        hasFlag.clean = true
    end
    return flags
end

local function buildRaceStateLabel(participants)
    local dnfCount = 0
    local bigSwings = 0
    for _, participant in ipairs(participants or {}) do
        if participant.dnf == true then
            dnfCount = dnfCount + 1
        end
        if math.abs(tonumber(participant.deltaPos or 0) or 0) >= 3 then
            bigSwings = bigSwings + 1
        end
    end
    if dnfCount >= 2 or bigSwings >= 3 then
        return "Volatile"
    end
    if dnfCount == 0 and bigSwings <= 1 then
        return "Clean"
    end
    return "Mixed"
end

local function buildSummaryBullets(record)
    local participants = record and record.participants or {}
    local bullets = {}
    local winner = participants[1]
    if winner then
        if winner.flags and winner.flags[1] == "dominant" then
            bullets[#bullets + 1] = string.format("%s controlled the race from the front.", tostring(winner.displayName or winner.driverId or "Winner"))
        elseif tonumber(winner.deltaPos or 0) > 0 then
            bullets[#bullets + 1] = string.format("%s won after gaining %d places.", tostring(winner.displayName or winner.driverId or "Winner"), tonumber(winner.deltaPos or 0) or 0)
        else
            bullets[#bullets + 1] = string.format("%s converted P%d into the win.", tostring(winner.displayName or winner.driverId or "Winner"), tonumber(winner.startPos or 1) or 1)
        end
    end

    local bestRecovery = nil
    local worstCollapse = nil
    for _, participant in ipairs(participants) do
        local delta = tonumber(participant.deltaPos or 0) or 0
        if delta >= 3 and (not bestRecovery or delta > (tonumber(bestRecovery.deltaPos or 0) or 0)) then
            bestRecovery = participant
        end
        if delta <= -3 and (not worstCollapse or delta < (tonumber(worstCollapse.deltaPos or 0) or 0)) then
            worstCollapse = participant
        end
    end
    if bestRecovery then
        bullets[#bullets + 1] = string.format("%s recovered from P%d to P%d.", tostring(bestRecovery.displayName or bestRecovery.driverId or "Driver"), tonumber(bestRecovery.startPos or 0) or 0, tonumber(bestRecovery.finishPos or 0) or 0)
    end
    if worstCollapse then
        bullets[#bullets + 1] = string.format("%s fell from P%d to P%d.", tostring(worstCollapse.displayName or worstCollapse.driverId or "Driver"), tonumber(worstCollapse.startPos or 0) or 0, tonumber(worstCollapse.finishPos or 0) or 0)
    end

    while #bullets > 3 do
        table.remove(bullets)
    end
    return bullets
end

local function trimBoxScores(boxScores)
    local perTierCounts = {}
    local trimmed = {}
    for _, record in ipairs(boxScores.records or {}) do
        local tier = tostring(record and record.tier or "Unknown")
        perTierCounts[tier] = perTierCounts[tier] or 0
        if perTierCounts[tier] < BOX_SCORES_MAX_PER_TIER and #trimmed < BOX_SCORES_MAX_TOTAL then
            trimmed[#trimmed + 1] = record
            perTierCounts[tier] = perTierCounts[tier] + 1
        end
    end
    boxScores.records = trimmed
end

local function cloneBoxScoreParticipants(participants)
    local out = {}
    for _, participant in ipairs(participants or {}) do
        out[#out + 1] = deepCopy(participant)
    end
    return out
end

--- Resolve display name and colour for any faction ID, including custom teams.
--- Falls back to career data when the ID is not in the Factions catalog.
--- @param career table|nil
--- @param fid    string
--- @return table  { name, color }
function Championships._resolveDisplayFaction(career, fid)
    local fdef = Factions.get(fid)
    if fdef then return fdef end
    -- Custom team: ID is "custom_<careerId>", data is on career
    if career and career.playerFactionId == fid then
        return {
            name  = career.playerFactionName  or fid,
            color = career.playerFactionColor or { 1, 1, 1 },
        }
    end
    return { name = fid, color = { 1, 1, 1 } }
end

local function awardPoints(season, result, career)
    local ruleset = season._ruleset
    if not ruleset then return end
    ensureStandings(season)

    local pts  = ruleset.pointsTable        or POINTS_TABLES.standard
    local mode = ruleset.factionScoringMode or "all"
    local cfg  = Championships._config
    local countIndependent = cfg.countIndependentInFactionChampionship ~= false

    -- Per-faction score accumulator for this race: { pts=n, pos=n } lists
    local factionRacePts = {}

    for _, entry in ipairs(result.results or {}) do
        local driverId  = entry.driverId  or "unknown"
        local factionId = entry.factionId or "independent"
        local pos       = entry.position  or 99
        local p         = (not entry.dnf) and (pts[pos] or 0) or 0

        -- Driver standings
        local ds = season.standings.drivers[driverId]
        if not ds then
            ds = {
                points         = 0, wins       = 0, podiums  = 0,
                top5s          = 0, dnfs        = 0, races    = 0,
                bestFinish     = 999,
                recentFinishes = {},
                factionId      = factionId,
                driverName     = entry.driverName or driverId,
            }
            season.standings.drivers[driverId] = ds
        end
        ds.races  = ds.races  + 1
        ds.points = ds.points + p
        if pos == 1          then ds.wins    = ds.wins    + 1 end
        if pos <= 3          then ds.podiums = ds.podiums + 1 end
        if pos <= 5          then ds.top5s   = ds.top5s   + 1 end
        if entry.dnf         then ds.dnfs    = ds.dnfs    + 1 end
        if pos < ds.bestFinish then ds.bestFinish = pos end
        table.insert(ds.recentFinishes, pos)
        if #ds.recentFinishes > 5 then table.remove(ds.recentFinishes, 1) end

        -- Accumulate faction race scores
        if factionId ~= "independent" or countIndependent then
            if not factionRacePts[factionId] then factionRacePts[factionId] = {} end
            table.insert(factionRacePts[factionId], { pts = p, pos = pos })
        end
    end

    -- Faction / constructors standings
    for fid, scores in pairs(factionRacePts) do
        table.sort(scores, function(a, b) return a.pts > b.pts end)
        local countScoring
        if mode == "best_two" then
            countScoring = math.min(2, #scores)
        elseif mode == "best_one" then
            countScoring = 1
        else
            countScoring = #scores  -- "all"
        end

        local factPts  = 0
        local factWins = 0
        local factPods = 0
        local bestPos  = 999
        for i = 1, countScoring do
            local sc = scores[i]
            factPts  = factPts  + sc.pts
            if sc.pos == 1  then factWins = factWins + 1 end
            if sc.pos <= 3  then factPods = factPods  + 1 end
            if sc.pos < bestPos then bestPos = sc.pos end
        end

        local fs = season.standings.factions[fid]
        if not fs then
            local fdef = Championships._resolveDisplayFaction(career, fid)
            fs = {
                points        = 0, wins         = 0, podiums      = 0,
                races         = 0, bestFinish    = 999,
                factionName   = fdef.name  or fid,
                factionColor  = fdef.color or { 1, 1, 1 },
                recentResults = {},
            }
            season.standings.factions[fid] = fs
        end
        fs.points  = fs.points  + factPts
        fs.wins    = fs.wins    + factWins
        fs.podiums = fs.podiums + factPods
        fs.races   = fs.races   + 1
        if bestPos < fs.bestFinish then fs.bestFinish = bestPos end
        table.insert(fs.recentResults, bestPos)
        if #fs.recentResults > 5 then table.remove(fs.recentResults, 1) end
    end
end

-- ── Standings sort (internal) ─────────────────────────────────
-- Tiebreak order for drivers:
--   points → wins → podiums → best single finish → most recent finish

local function sortedDriverStandings(drivers)
    local out = {}
    for id, ds in pairs(drivers) do
        local entry = { driverId = id }
        for k, v in pairs(ds) do entry[k] = v end
        table.insert(out, entry)
    end
    table.sort(out, function(a, b)
        if a.points    ~= b.points    then return a.points    > b.points    end
        if a.wins      ~= b.wins      then return a.wins      > b.wins      end
        if a.podiums   ~= b.podiums   then return a.podiums   > b.podiums   end
        if a.bestFinish ~= b.bestFinish then return a.bestFinish < b.bestFinish end
        local ar = a.recentFinishes and a.recentFinishes[#a.recentFinishes] or 999
        local br = b.recentFinishes and b.recentFinishes[#b.recentFinishes] or 999
        return ar < br
    end)
    return out
end

-- Tiebreak order for factions:
--   points → wins → podiums → best single finish → most recent faction result

local function sortedFactionStandings(factions)
    local out = {}
    for id, fs in pairs(factions) do
        local entry = { factionId = id }
        for k, v in pairs(fs) do entry[k] = v end
        table.insert(out, entry)
    end
    table.sort(out, function(a, b)
        if a.points    ~= b.points    then return a.points    > b.points    end
        if a.wins      ~= b.wins      then return a.wins      > b.wins      end
        if a.podiums   ~= b.podiums   then return a.podiums   > b.podiums   end
        if a.bestFinish ~= b.bestFinish then return a.bestFinish < b.bestFinish end
        local ar = a.recentResults and a.recentResults[#a.recentResults] or 999
        local br = b.recentResults and b.recentResults[#b.recentResults] or 999
        return ar < br
    end)
    return out
end

-- ── Module config ─────────────────────────────────────────────
Championships._config = {
    enabled = true,
    defaultRulesetByTier = {
        Gonk       = "gonk_default",
        Streetkid  = "streetkid_default",
        Solo       = "solo_default",
        Fixer      = "fixer_default",
        Edgerunner = "edgerunner_default",
    },
    -- Whether "Independent" appears in faction/constructors standings.
    countIndependentInFactionChampionship = true,
}

-- ── Public API ────────────────────────────────────────────────

function Championships.init()
    print("[NCM/Championships] Initialised.")
end

--- Return the ruleset for a given tier name.
--- @param tier string
--- @return table  ruleset
function Championships.rulesetForTier(tier)
    return RULESET_BY_TIER[tier] or RULESETS.solo_default
end

function Championships.rulesetForCareer(career, tier)
    local baseRuleset = Championships.rulesetForTier(tier)
    local ruleset = deepCopy(baseRuleset)
    ruleset.eventTypes = championshipEventTypesForCareer(career)
    ruleset.lastRaceKnockout = careerChampionshipConfig(career).lastRaceKnockout
    return ruleset
end

--- Apply the active season's ruleset constraints to a Racing draft config.
--- Overwrites eventType -> raceType, preferredRegions, and allowCombat when
--- the season schedule specifies them.  The player can still change other
--- settings (field size, start type, stakes) in the config panel.
--- @param career  table  active career
--- @param draft   table  Racing._draft table (mutated in place)
function Championships.applySeasonConfig(career, draft)
    if not Championships._config.enabled then return end
    local season = Championships.activeSeason(career)
    if not season or season.completed then return end

    local rd      = Championships.currentEvent(career)
    local ruleset = season._ruleset or Championships.rulesetForCareer(career, season.leagueTier)

    if rd then
        draft._eventSourceType = "career_schedule"
        draft._lockToScheduledEvent = true
        draft._scheduledEventId = rd.eventId
        draft._scheduledEvent = EventDefs.clone(rd)
        draft._scheduledRaceType = rd.eventType
        draft._scheduledDistrict = rd.districtLabel or rd.district
        draft.raceType = rd.eventType
        draft.defaultStartType = rd.startType or draft.defaultStartType
        draft.defaultFieldSize = rd.fieldSize or draft.defaultFieldSize
        draft.allowCombat = rd.allowCombat
        draft.allowStakes = rd.allowStakes
        draft.qualiEnabled = rd.qualiEnabled
        draft.vehicleClass = rd.vehicleClass
        draft.timeOfDay = rd.timeOfDay
        draft.routeMode = rd.eventType == "knockout" and "circuit" or (rd.rootId and "root" or "picked")
        draft.useManualNodes = false
        draft.selectedRootId = rd.selectedRootId or rd.rootId or nil
        draft.selectedStartNodeId = rd.nodeA and rd.nodeA.id or nil
        draft.selectedFinishNodeId = rd.nodeB and rd.nodeB.id or nil
        if rd.districtLabel then
            draft.preferredRegions = { rd.districtLabel }
        elseif rd.district then
            draft.preferredRegions = { rd.district }
        end
    end

    -- Apply ruleset-level constraints
    if ruleset then
        if ruleset.allowCombat ~= nil then
            draft.allowCombat = ruleset.allowCombat
        end
        if ruleset.allowStakes ~= nil then
            draft.allowStakes = ruleset.allowStakes
        end
        -- Store ruleset id on draft for display / debug
        draft._rulesetId   = ruleset.id
        draft._rulesetName = ruleset.name
        draft._seasonId    = season.id
        draft._roundNum    = season.currentRound
    end

    -- Announce this round once: fire RoundReady only the first time the player
    -- opens race config for this round number in the current session.
    -- career._lastAnnouncedRound is a transient (non-saved) field — resets each load.
    if career._lastAnnouncedRound ~= season.currentRound then
        career._lastAnnouncedRound = season.currentRound
        if MTE.Events then
            MTE.Events.emit("RoundReady", {
                round      = season.currentRound,
                total      = season.totalRounds,
                district   = rd and (rd.districtLabel or rd.district) or "?",
                eventType  = rd and rd.eventType or "sprint",
                tier       = season.leagueTier or career.tier,
                teamName   = career.playerFactionName or "Independent",
            })
        end
    end
end

--- Return the active (non-completed) season for a career.
--- Creates a new one automatically if no active season exists.
--- @param career table
--- @return table  season object
function Championships.activeSeason(career)
    if not career then return nil end
    if not career.seasons then career.seasons = {} end

    if career.activeSeasonId then
        local s = career.seasons[career.activeSeasonId]
        if s and not s.completed then
            -- Re-attach ephemeral ruleset reference (lost across save/load)
            if not s._ruleset then
                s._ruleset = Championships.rulesetForCareer(career, s.leagueTier or career.tier)
            end
            Championships._ensureSeasonSchedule(career, s)
            return s
        end
    end

    return Championships.startNewSeason(career)
end

--- Create and activate a new season for the career's current tier.
--- @param career table
--- @return table  season object
function Championships.startNewSeason(career)
    if not career then return nil end
    if not career.seasons then career.seasons = {} end

    local ruleset     = Championships.rulesetForCareer(career, career.tier)
    local seasonCount = 0
    for _, s in pairs(career.seasons) do
        if s.leagueTier == career.tier then seasonCount = seasonCount + 1 end
    end
    local seasonNum = seasonCount + 1

    -- Season seed: mix career seed with an ordinal so each season differs
    local seedBase = (career.seed or 0) + seasonCount * 1337 + (os.time() % 10000)
    local seasonId = string.format("season_%s_%d", career.tier:lower(), seasonNum)
    local schedule = generateSchedule(career, seasonId, ruleset, seedBase)

    local season = {
        id           = seasonId,
        leagueTier   = career.tier,
        seasonNumber = seasonNum,
        seasonSeed   = seedBase,
        scheduleVersion = SCHEDULE_VERSION,
        rulesetId    = ruleset.id,
        totalRounds  = ruleset.rounds,
        currentRound = 1,
        completed    = false,
        schedule     = schedule,
        standings    = { drivers = {}, factions = {} },
        -- _ruleset is ephemeral: lost on save/load, re-attached in activeSeason()
        _ruleset     = ruleset,
    }

    career.seasons[seasonId]  = season
    career.activeSeasonId     = seasonId
    career.seasonNumber       = seasonNum
    Championships._ensureSeasonSchedule(career, season)
    if MTE.Careers then MTE.Careers.save() end

    print(string.format("[NCM/Championships] New season: %s  |  %d rounds  |  tier=%s.",
        seasonId, ruleset.rounds, career.tier))
    return season
end

function Championships.currentEvent(career)
    local season = Championships.activeSeason(career)
    if not season or season.completed then return nil end
    Championships._ensureSeasonSchedule(career, season)
    return season.schedule and season.schedule[season.currentRound] or nil
end

function Championships.recordBoxScore(career, payload)
    if not career or type(payload) ~= "table" then
        return nil
    end

    local boxScores = ensureBoxScores(career)
    local participants = {}
    local leaderTime = nil
    for _, participant in ipairs(payload.participants or {}) do
        local copied = {
            driverId = tostring(participant.driverId or participant.id or "unknown"),
            displayName = tostring(participant.displayName or participant.name or participant.driverId or participant.id or "Driver"),
            isPlayer = participant.isPlayer == true,
            startPos = tonumber(participant.startPos or participant.gridPos or participant.position or 99) or 99,
            finishPos = tonumber(participant.finishPos or participant.position or 99) or 99,
            finishTime = normaliseFinishTime(participant.finishTime or participant.time),
            gapToLeader = tonumber(participant.gapToLeader or 0) or 0,
            deltaPos = tonumber(participant.deltaPos or 0) or 0,
            dnf = participant.dnf == true,
            payout = math.max(0, math.floor(tonumber(participant.payout or participant.playerPayout or participant.purseAwarded or 0) or 0)),
            factionId = participant.factionId,
            factionName = participant.factionName,
            finishMode = participant.finishMode,
            flags = normaliseFlagList(participant.flags),
        }
        if copied.finishPos == 1 and copied.finishTime then
            leaderTime = copied.finishTime
        end
        participants[#participants + 1] = copied
    end

    table.sort(participants, function(left, right)
        local lp = tonumber(left.finishPos or 99) or 99
        local rp = tonumber(right.finishPos or 99) or 99
        if lp ~= rp then
            return lp < rp
        end
        return tostring(left.displayName or "") < tostring(right.displayName or "")
    end)

    if not leaderTime and participants[1] then
        leaderTime = participants[1].finishTime
    end
    for index, participant in ipairs(participants) do
        participant.finishPos = tonumber(participant.finishPos or index) or index
        if participant.startPos <= 0 then
            participant.startPos = participant.finishPos
        end
        if participant.deltaPos == 0 then
            participant.deltaPos = participant.startPos - participant.finishPos
        end
        if index == 1 then
            participant.gapToLeader = 0
        elseif participant.finishTime and leaderTime then
            participant.gapToLeader = math.max(0, participant.finishTime - leaderTime)
        end
    end

    for index, participant in ipairs(participants) do
        local dnfCount = 0
        for _, row in ipairs(participants) do
            if row.dnf == true then
                dnfCount = dnfCount + 1
            end
        end
        local nextGap = nil
        local nextParticipant = participants[index + 1]
        if nextParticipant then
            nextGap = tonumber(nextParticipant.gapToLeader or 0) - tonumber(participant.gapToLeader or 0)
        end
        participant.flags = buildParticipantFlags(participant, leaderTime, nextGap, dnfCount)
    end

    local timestamp = tonumber(payload.timestamp or payload.resolvedAt or os.time()) or os.time()
    local routeName = formatFallbackRouteName(payload)
    local record = {
        recordId = string.format("box_%06d", tonumber(boxScores.nextOrdinal or 1) or 1),
        ordinal = tonumber(boxScores.nextOrdinal or 1) or 1,
        sourceType = tostring(payload.sourceType or "unknown"),
        eventId = payload.eventId,
        seasonId = payload.seasonId,
        round = tonumber(payload.round or 0) or 0,
        tier = tostring(payload.tier or career.tier or "Unknown"),
        raceType = tostring(payload.raceType or payload.eventType or "race"),
        routeName = routeName,
        district = payload.district,
        timestamp = timestamp,
        fieldSize = math.max(0, tonumber(payload.fieldSize or #participants) or #participants),
        playerInvolved = payload.playerInvolved == true,
        payout = math.max(0, math.floor(tonumber(payload.payout or payload.playerPayout or payload.purseAwarded or 0) or 0)),
        playerPayout = math.max(0, math.floor(tonumber(payload.playerPayout or payload.payout or payload.purseAwarded or 0) or 0)),
        winnerName = participants[1] and participants[1].displayName or nil,
        stateLabel = buildRaceStateLabel(participants),
        participants = participants,
        summaryBullets = {},
    }
    record.summaryBullets = buildSummaryBullets(record)

    boxScores.nextOrdinal = record.ordinal + 1
    table.insert(boxScores.records, 1, record)
    trimBoxScores(boxScores)
    if MTE and MTE.Careers and MTE.Careers.save then
        MTE.Careers.save()
    end
    return record
end

function Championships.getBoxScoreById(career, recordId)
    if not career or not recordId then
        return nil
    end
    local boxScores = ensureBoxScores(career)
    for _, record in ipairs(boxScores.records or {}) do
        if tostring(record.recordId or "") == tostring(recordId) then
            return deepCopy(record)
        end
    end
    return nil
end

function Championships.getBoxScoresPage(career, options)
    if not career then
        return {
            records = {},
            totalMatches = 0,
            page = 1,
            pageCount = 1,
            pageSize = BOX_SCORES_DEFAULT_PAGE_SIZE,
        }
    end

    local opts = options or {}
    local tierFilter = tostring(opts.tier or "all")
    local playerOnly = opts.playerOnly == true
    local pageSize = math.max(5, math.min(25, tonumber(opts.pageSize) or BOX_SCORES_DEFAULT_PAGE_SIZE))
    local requestedPage = math.max(1, tonumber(opts.page) or 1)
    local boxScores = ensureBoxScores(career)
    local matches = {}
    for _, record in ipairs(boxScores.records or {}) do
        if (tierFilter == "all" or tostring(record.tier or "") == tierFilter)
            and (not playerOnly or record.playerInvolved == true) then
            matches[#matches + 1] = record
        end
    end

    local totalMatches = #matches
    local pageCount = math.max(1, math.ceil(totalMatches / pageSize))
    local page = math.min(requestedPage, pageCount)
    local startIndex = ((page - 1) * pageSize) + 1
    local finishIndex = math.min(totalMatches, startIndex + pageSize - 1)
    local pageRecords = {}
    for index = startIndex, finishIndex do
        pageRecords[#pageRecords + 1] = deepCopy(matches[index])
    end

    return {
        records = pageRecords,
        totalMatches = totalMatches,
        page = page,
        pageCount = pageCount,
        pageSize = pageSize,
    }
end

--- Record a completed race result into the active season.
--- Must be called AFTER existing rep/prestige and roster update logic.
--- @param career table
--- @param result table
---   result.seasonId   string
---   result.round      number
---   result.tier       string
---   result.results    table[]  {driverId, position, factionId, driverName, isPlayer, dnf?}
function Championships.recordResult(career, result)
    if not Championships._config.enabled then return end
    if not career then return end

    local season = Championships.activeSeason(career)
    if not season then return end

    -- Ensure _ruleset is attached (may be missing after load)
    if not season._ruleset then
        season._ruleset = Championships.rulesetForTier(season.leagueTier or career.tier)
    end

    awardPoints(season, result, career)

    -- Mark round as completed; store results for history
    local round = result.round or season.currentRound
    if season.schedule and season.schedule[round] then
        local scheduled = season.schedule[round]
        if result.eventId and scheduled.eventId and result.eventId ~= scheduled.eventId then
            print(string.format(
                "[NCM/Championships] Event mismatch while recording result. scheduled=%s actual=%s",
                tostring(scheduled.eventId),
                tostring(result.eventId)))
        end
        if result.executedEvent then
            local executed = EventDefs.clone(result.executedEvent)
            for key, value in pairs(executed) do
                if key ~= "completed" and key ~= "results" then
                    scheduled[key] = value
                end
            end
        end
        scheduled.completed = true
        scheduled.results   = result.results
    end

    if season.currentRound < season.totalRounds then
        season.currentRound = season.currentRound + 1
    else
        Championships._closeSeason(career, season)
    end

    if MTE.Careers then MTE.Careers.save() end
    print(string.format("[NCM/Championships] Round %d / %d recorded  |  season %s.",
        round, season.totalRounds, season.id))
end

--- Internal: finalise a completed season.
function Championships._closeSeason(career, season)
    season.completed = true

    -- Find player's final championship position for the event payload
    local driverRows = Championships.driverStandings(season)
    local champPos   = nil
    for i, ds in ipairs(driverRows) do
        if ds.driverId == "player" then champPos = i; break end
    end

    local seasonReward = MTE.Careers and MTE.Careers.applySeasonLifecycle and MTE.Careers.applySeasonLifecycle(career, {
        seasonId = season.id,
        seasonNumber = season.seasonNumber,
        tier = season.leagueTier,
        finalPosition = champPos or #driverRows,
        fieldSize = math.max(1, #driverRows),
    }) or nil

    career.activeSeasonId = nil

    if MTE.Events and seasonReward then
        MTE.Events.emit("SeasonComplete", {
            career = career,
            season = season.seasonNumber,
            repBonus = seasonReward.repBonus,
            eddies = seasonReward.eddies,
            finalPosition = seasonReward.finalPosition,
            fieldSize = seasonReward.fieldSize,
            direction = seasonReward.direction,
            fromTier = seasonReward.fromTier,
            toTier = seasonReward.toTier,
        })
    end

    if MTE.Events then
        MTE.Events.emit("ChampionshipComplete", {
            seasonId = season.id,
            tier     = season.leagueTier,
            champPos = champPos,
            careerId = career.id,
            season   = season.seasonNumber,
        })
    end

    print(string.format("[NCM/Championships] Season %s complete. Player final position: %s.",
        season.id, tostring(champPos)))
end

--- Return sorted driver standings for a season, with _rank populated.
--- @param season table
--- @return table[]  sorted entries (each has driverId, points, wins, …, _rank)
function Championships.driverStandings(season)
    if not season or not season.standings then return {} end
    local sorted = sortedDriverStandings(season.standings.drivers)
    for i, e in ipairs(sorted) do e._rank = i end
    return sorted
end

--- Return sorted faction standings for a season, with _rank populated.
--- @param season table
--- @return table[]  sorted entries (each has factionId, points, wins, …, _rank)
function Championships.factionStandings(season)
    if not season or not season.standings then return {} end
    local sorted = sortedFactionStandings(season.standings.factions)
    for i, e in ipairs(sorted) do e._rank = i end
    return sorted
end

--- Convenience: get the active season for the currently active career.
--- @return table|nil
function Championships.currentSeason()
    local career = MTE.Careers and MTE.Careers.active()
    if not career then return nil end
    return Championships.activeSeason(career)
end

--- Migrate a career loaded from disk to ensure all faction/season fields exist.
--- Safe to call unconditionally on every load; skips fields already present.
--- @param career table
function Championships.migrateCareer(career)
    if not career then return end
    if MTE.Careers and MTE.Careers.normalizeChampionshipConfig then
        career.championshipConfig = MTE.Careers.normalizeChampionshipConfig(career.championshipConfig)
    elseif type(career.championshipConfig) ~= "table" then
        career.championshipConfig = { eventMix = "mixed", lastRaceKnockout = false }
    end
    if not career.playerFactionMode then
        career.playerFactionMode  = "independent"
        career.playerFactionId    = "independent"
        career.playerFactionName  = "Independent"
        career.playerFactionColor = { 1.0, 0.93, 0.33 }
    end
    if not career.seasons        then career.seasons        = {} end
    ensureBoxScores(career)
    if career.activeSeasonId == nil then career.activeSeasonId = nil end
    -- Re-attach ephemeral ruleset references to any in-progress seasons
    for _, s in pairs(career.seasons) do
        if not s._ruleset then
            s._ruleset = Championships.rulesetForCareer(career, s.leagueTier or career.tier)
        end
    end
end

--- Set V's team / faction affiliation for championship scoring.
--- mode  "independent" — privateer, no team allegiance
--- mode  "signed"      — opts.factionId must match a catalog entry
--- mode  "custom"      — opts.factionName + opts.factionColor (RGB table)
--- Returns true on success, or false + reason string on failure.
--- @param career table
--- @param mode   string
--- @param opts   table|nil
function Championships.setPlayerFaction(career, mode, opts)
    opts = opts or {}
    -- Lock: cannot change faction once a season has started (round > 1)
    if career.activeSeasonId then
        local s = career.seasons and career.seasons[career.activeSeasonId]
        if s and not s.completed and (s.currentRound or 1) > 1 then
            print("[NCM/Championships] Cannot change team mid-season.")
            return false, "mid_season_lock"
        end
    end

    if mode == "independent" then
        career.playerFactionMode  = "independent"
        career.playerFactionId    = "independent"
        career.playerFactionName  = "Independent"
        career.playerFactionColor = { 1.0, 0.93, 0.33 }

    elseif mode == "signed" then
        local fdef = Factions.get(opts.factionId or "")
        if not fdef then
            print("[NCM/Championships] setPlayerFaction: unknown faction: " .. tostring(opts.factionId))
            return
        end
        career.playerFactionMode  = "signed"
        career.playerFactionId    = fdef.id
        career.playerFactionName  = fdef.name
        career.playerFactionColor = fdef.color

    elseif mode == "custom" then
        career.playerFactionMode  = "custom"
        career.playerFactionId    = "custom_" .. (career.id or "unknown")
        career.playerFactionName  = opts.factionName  or "Custom Team"
        career.playerFactionColor = opts.factionColor or { 0.5, 0.8, 1.0 }
    end

    if MTE.Careers then MTE.Careers.save() end
    print(string.format("[NCM/Championships] V faction -> '%s'  (%s).",
        career.playerFactionName, career.playerFactionMode))
end

return Championships
