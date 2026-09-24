-- ============================================================
-- MT_Ecosystem: modules/racing.lua  (V2 rewrite)
-- Full race system: A→B ghost-time racing, career integration,
-- heat injection, bounties, stakes, quali, all config options.
--
-- STATE MACHINE:
--   IDLE → CONFIG → PRERACE → QUALI? → COUNTDOWN → RACING → RESULTS
-- ============================================================

local Racing = {}
local i18n = require("modules/i18n")

local VehiclePool = require("data/vehicle_pool")
local Checkpoint = require("modules/checkpoint")
local KnockoutCircuits = require("modules/knockout_circuits")
local SettingsRegistry = require("modules/settings")
local Betting = require("modules/betting")

-- ── Constants ─────────────────────────────────────────────────

local PAYOUT_BY_POS = { 2500, 1400, 700, 350, 150, 75, 40, 20 }

local START_DELAYS = {   -- seconds added to AI reaction window by type
    grid        = 0.5,
    sidebyside  = 0.3,
    rolling     = 0.0,
}

-- Vehicle classes for restriction check (TweakDB tag substrings)
local CLASS_TAGS = {
    Muscle = { "muscle", "heavy" },
    Sport  = { "sport", "hypercar", "supercar" },
    Tech   = { "tech", "electric", "remote" },
    Nomad  = { "offroad", "nomad", "van", "truck" },
    Bike   = { "bike", "motorcycle", "mbike", "kusanagi", "nazare", "apollo", "yaiba", "arch", "brennan" },
}

Racing.RACE_TYPES  = { "sprint", "drag", "endurance" }
Racing.START_TYPES = { "grid", "rolling", "sidebyside" }

local ZONE_CLEAR_TIME    = 12.0  -- seconds post-snap before grid spawn is allowed
local WARP_SETTLE_TIME   = 18.0  -- extra settle time after manual warp/loading before grid spawn
local LIVE_RIVALS_POST_START = false -- prerace grid should materialize before countdown; post-start birth stays available only as a fallback path
local LIVE_RIVALS_POST_START_DELAY = 5.0 -- seconds after race start before visible rivals may spawn when deferred mode is enabled
local LIVE_RIVALS_POST_START_PLAYER_BACK_BLOCK_M = 8.0 -- only block deferred rivals if V has reversed back into the grid volume
local RACE_FLOW_BUILD = "2026-04-01.1945-road-aligned-direct-grid"
local TRAFFIC_CLEAR_VERTICAL_TOLERANCE = 18.0 -- only clear vehicles near the race's vertical slice
local MANUAL_GRID_FORWARD_DISTANCE_M = 3.0
local MANUAL_GRID_FINISH_DISTANCE_M = 110.0
local NIGHT_CITY_X_MIN = -2200.0
local NIGHT_CITY_X_MAX = 1700.0
local NIGHT_CITY_Y_MIN = -1650.0
local NIGHT_CITY_Y_MAX = 2850.0
local ENABLE_QUEST_UI_BRIDGE = true -- keep phone/quest state in sync with live race state so SMS contacts can manage any active run

local resetSequenceRaceState

local function _resolveTuningContext(context)
    if context ~= nil then
        return context
    end
    return Racing._config or Racing._draft or nil
end

local function _tuningDefault(key, fallback)
    local settings = (MTE and MTE.Settings) or SettingsRegistry
    if settings and settings.getTuningDefault then
        local value = settings.getTuningDefault(key)
        if value ~= nil then
            return value
        end
    end
    return fallback
end

local function _tuningValue(key, context, fallback)
    local settings = (MTE and MTE.Settings) or SettingsRegistry
    if settings and settings.getTuningValue then
        local value = settings.getTuningValue(key, _resolveTuningContext(context))
        if value ~= nil then
            return value
        end
    end
    return _tuningDefault(key, fallback)
end

local function _manualGridModeEnabled()
    local settings = (MTE and MTE.Settings and MTE.Settings.current) or SettingsRegistry.current
    return type(settings) == "table" and settings.manualGridMode == true
end

local function _playerGridSnapEnabled()
    local settings = (MTE and MTE.Settings and MTE.Settings.current) or SettingsRegistry.current
    if type(settings) == "table" and settings.playerGridSnapEnabled ~= nil then
        return settings.playerGridSnapEnabled == true
    end
    return true
end

local function _applyGridHeadingOffset(heading, context)
    local normalized = tonumber(heading)
    if type(normalized) ~= "number" or normalized ~= normalized or normalized == math.huge or normalized == -math.huge then
        return heading
    end
    normalized = normalized % 360.0
    if normalized < 0 then
        normalized = normalized + 360.0
    end

    local shifted = normalized + _tuningValue("gridHeadingOffsetDeg", context)
    shifted = shifted % 360.0
    if shifted < 0 then
        shifted = shifted + 360.0
    end
    return shifted
end

local function _getResolvedGridHeading(nodeA, nodeB, context)
    return _applyGridHeadingOffset(Racing._getStartHeading(nodeA, nodeB), context)
end

local function _applyGridLateralShift(position, nodeA, nodeB, context)
    local lateralShiftM = _tuningValue("gridLateralShiftM", context, 0.0)
    if math.abs(tonumber(lateralShiftM) or 0.0) < 0.001 or type(position) ~= "table" then
        return position
    end

    local gridHeading = _getResolvedGridHeading(nodeA, nodeB, context)
    local headingRad = math.rad(gridHeading or 0.0)
    local rightX = -math.sin(headingRad)
    local rightY = math.cos(headingRad)
    return {
        x = (position.x or 0.0) + lateralShiftM * rightX,
        y = (position.y or 0.0) + lateralShiftM * rightY,
        z = position.z,
        heading = position.heading,
    }
end

-- ── Pre-race zone seizure ─────────────────────────────────────
-- Suppresses ambient traffic/crowd density for the duration of PRERACE.
-- Uses pcall guards so unknown API paths fail silently without crashing.

local _zoneSuppressed = false

local function _suppressZone()
    if _zoneSuppressed then return end
    _zoneSuppressed = true
    -- Attempt TrafficSystem density suppression (may or may not be available)
    pcall(function()
        local ts = Game.GetScriptableSystemsContainer():Get("TrafficSystem")
        if ts then
            if ts.SetDensityMultiplier      then ts:SetDensityMultiplier(0.0)
            elseif ts.SetTrafficDensityMultiplier then ts:SetTrafficDensityMultiplier(0.0)
            elseif ts.SetDefaultTrafficDensity    then ts:SetDefaultTrafficDensity(0.0) end
        end
    end)
    pcall(function()
        local vs = Game.GetScriptableSystemsContainer():Get("VehicleSystem")
        if vs and vs.SetShouldRespawnVehicles then vs:SetShouldRespawnVehicles(false) end
    end)
    print("[NCM/Zone] Area seized — ambient spawns suppressed.")
end

local function _restoreZone()
    if not _zoneSuppressed then return end
    _zoneSuppressed = false
    pcall(function()
        local ts = Game.GetScriptableSystemsContainer():Get("TrafficSystem")
        if ts then
            if ts.SetDensityMultiplier           then ts:SetDensityMultiplier(1.0)
            elseif ts.SetTrafficDensityMultiplier then ts:SetTrafficDensityMultiplier(1.0)
            elseif ts.SetDefaultTrafficDensity    then ts:SetDefaultTrafficDensity(1.0) end
        end
    end)
    pcall(function()
        local vs = Game.GetScriptableSystemsContainer():Get("VehicleSystem")
        if vs and vs.SetShouldRespawnVehicles then vs:SetShouldRespawnVehicles(true) end
    end)
    print("[NCM/Zone] Zone released — ambient spawns restored.")
end

--- Safe teleport: brief time-dilation pause wraps the teleport to soften the
--- physics event (avoids CTD from high-speed vehicle teleport into dense traffic).
local function _safeTeleport(target, pos, heading)
    local snapped = false
    pcall(function()
        local hdg = heading or pos.heading or 0
        local rad = math.rad(hdg)
        local dx = math.cos(rad)
        local dy = math.sin(rad)
        local tx = (pos.x or 0) - dx * _tuningValue("startTeleportBackoffM", Racing._config)
        local ty = (pos.y or 0) - dy * _tuningValue("startTeleportBackoffM", Racing._config)
        local tz = (pos.z or 0) + _tuningValue("startTeleportZLiftM", Racing._config)
        local v4  = Vector4.new(tx, ty, tz, 1.0)
        local rot = EulerAngles.new(0, 0, hdg)
        print(i18n.format(
            "[NCM/Racing] Teleporting target=%s to (%.2f, %.2f, %.2f) hdg=%.1f",
            tostring(target), tx, ty, tz, hdg))
        Game.GetTeleportationFacility():Teleport(target, v4, rot)
        snapped = true
    end)
    return snapped
end

local function _nextSpawnRunId()
    Racing._spawnRunSeq = (Racing._spawnRunSeq or 0) + 1
    return i18n.format("race_%04d", tonumber(Racing._spawnRunSeq or 0))
end

function Racing._ensureSpawnRunId()
    if type(Racing._spawnRunId) ~= "string" or Racing._spawnRunId == "" then
        Racing._spawnRunId = _nextSpawnRunId()
    end
    return Racing._spawnRunId
end

function Racing._logSpawnRunMarker(stage, pathContext, extras)
    local cfg = Racing._config or {}
    local nodeA = extras and extras.nodeA or cfg.nodeA
    local nodeB = extras and extras.nodeB or cfg.nodeB
    local fieldCount = extras and extras.fieldCount or #(Racing._field or {})
    print(i18n.format(
        "[NCM/Racing] SpawnRun stage=%s run=%s path=%s route=%s start=%s finish=%s startType=%s livePostStart=%s field=%d source=%s",
        tostring(stage or "?"),
        tostring(Racing._ensureSpawnRunId()),
        tostring(pathContext or "?"),
        tostring(cfg.routeMode or "?"),
        tostring(nodeA and nodeA.name or "?"),
        tostring(nodeB and nodeB.name or "?"),
        tostring(cfg.startType or "grid"),
        tostring(LIVE_RIVALS_POST_START),
        tonumber(fieldCount or 0),
        tostring(extras and extras.source or "default")))
end

-- ── State machine ─────────────────────────────────────────────

Racing.STATE = {
    IDLE      = "idle",
    CONFIG    = "config",
    PRERACE   = "prerace",
    QUALI     = "quali",
    COUNTDOWN = "countdown",
    RACING    = "racing",
    RESULTS   = "results",
}

-- Numeric state codes for quest fact sync (mirrors RedScript ncm_race_state)
local STATE_NUM = {
    idle = 0, config = 1, prerace = 2, quali = 3,
    countdown = 4, racing = 5, results = 6,
}

local SMS_EVENT_SEQ = 0

-- ── Quest / SMS bridge helpers ────────────────────────────────

local function _queueQuestEvent(active, trackName)
    if not ENABLE_QUEST_UI_BRIDGE then
        return false
    end
    print(i18n.format("[NCM/Quest] _queueQuestEvent: active=%s trackName=%s", tostring(active), tostring(trackName)))
    local ok, err = pcall(function()
        print("[NCM/Quest] Creating MTERaceQuestEvent...")
        local evt = MTERaceQuestEvent.new()
        print("[NCM/Quest] MTERaceQuestEvent created: " .. tostring(evt))
        evt.active = active
        evt.trackName = trackName or ""
        print("[NCM/Quest] Queueing event via UISystem...")
        Game.GetUISystem():QueueEvent(evt)
        print("[NCM/Quest] QueueEvent OK")
    end)
    if not ok then print("[NCM/Quest] _queueQuestEvent FAILED: " .. tostring(err)) end
    return ok
end

local function _syncRaceState(stateStr, extras)
    if not ENABLE_QUEST_UI_BRIDGE then
        return false
    end
    print("[NCM/Quest] _syncRaceState: " .. tostring(stateStr))
    local ok, err = pcall(function()
        local evt = MTERaceStateSyncEvent.new()
        print("[NCM/Quest] MTERaceStateSyncEvent created: " .. tostring(evt))
        evt.raceState = STATE_NUM[stateStr] or 0
        evt.trackId   = (extras and extras.trackId)   or -1
        evt.finishPos = (extras and extras.finishPos)  or -1
        evt.champPos  = (extras and extras.champPos)   or -1
        evt.totalWins = (extras and extras.totalWins)  or -1
        evt.totalRaces = (extras and extras.totalRaces) or -1
        Game.GetUISystem():QueueEvent(evt)
        print("[NCM/Quest] _syncRaceState QueueEvent OK")
    end)
    if not ok then print("[NCM/Quest] _syncRaceState FAILED: " .. tostring(err)) end
    return ok
end

local function _sendSMS(messageType)
    if not ENABLE_QUEST_UI_BRIDGE then
        return false
    end
    print("[NCM/Quest] _sendSMS: type=" .. tostring(messageType))
    local ok, err = pcall(function()
        SMS_EVENT_SEQ = SMS_EVENT_SEQ + 1
        local evt = MTESendSMSEvent.new()
        print("[NCM/Quest] MTESendSMSEvent created: " .. tostring(evt))
        evt.messageType = messageType
        evt.seq = SMS_EVENT_SEQ
        Game.GetUISystem():QueueEvent(evt)
        print("[NCM/Quest] _sendSMS QueueEvent OK")
    end)
    if not ok then print("[NCM/Quest] _sendSMS FAILED: " .. tostring(err)) end
    return ok
end

function Racing.questBridgeEnabled()
    return ENABLE_QUEST_UI_BRIDGE
end

-- ── Mutable state ─────────────────────────────────────────────

Racing._state       = Racing.STATE.IDLE
Racing._career      = nil
Racing._config      = {}
Racing._field       = {}
Racing._finishNode  = nil
Racing._startNode   = nil
Racing._raceTimer   = 0.0
Racing._stakeAmount = 0
Racing._stakeEscrowed = false
Racing._qualiTime    = nil
Racing._qualiGridPos = nil
Racing._results      = {}
Racing._bgSimTimer  = 0.0
Racing._draft       = {}
Racing._finishDir   = nil   -- {x,y} normalised direction A→B (2D, for finish line)
Racing._prevFinishDot = nil -- previous frame's signed distance along _finishDir
Racing._aiPrevDot   = {}   -- per-driverId previous dot for AI finish-line crossing
Racing._aiFinished  = {}   -- per-driverId authoritative finish flag
Racing._aiFinishTime = {} -- per-driverId authoritative finish time
Racing._lastKnownStandingByDriverId = {}
Racing._telemetrySessionId = nil
Racing._lastCountdownPhase = nil  -- last grid-light phase played (for sound de-dup)
Racing._countdownDuration = 3.0   -- active countdown duration for the current race start
Racing._countdownUseLights = true -- whether the current countdown should drive the grid-light phases
Racing._quickRacePending          = false -- deferred start for Quick Race hotkey
Racing._qualiProximityTriggered   = false -- in-world countdown already armed this session
Racing._qualiCountdown            = nil   -- seconds remaining on approach countdown
Racing._qualiLastTickSec          = nil   -- last whole-second shown in countdown
Racing._gridSpawnPending          = false -- AI grid is queued but waiting for spawn window
Racing._autoStageTriggered        = false -- V has been snapped to the current start node
Racing._gridFormingTriggered      = false -- AI grid spawn has been queued before V stages
Racing._stageCountdown            = nil   -- seconds remaining on auto-stage approach countdown
Racing._prelaunchCountdown        = nil   -- seconds remaining on pre-launch countdown (post grid-ready)
Racing._postSnapCooldown          = 0.0   -- seconds to wait after snap before grid spawns (traffic clear)
Racing._postSnapNotifyTimer       = 0.0   -- throttle for "clearing traffic" repeat notify
Racing._trafficClearRetryTimer    = 0.0   -- repeated ambient traffic scrub during the post-snap cooldown
Racing._stageSource               = nil   -- "approach" | "warp" | "quali" | "quick"
Racing._gridSpawnStableTicks      = 0     -- consecutive clean ticks in the live-spawn window
Racing._gridSpawnStableTime       = 0.0   -- accumulated clean time in the live-spawn window
Racing._gridSpawnGateReason       = nil   -- last blocker / gate state for debug logging
Racing._gridReadyBlockerReason    = nil   -- last reason GridReady/countdown was blocked after spawn finished
Racing._postStartLiveSpawnPending = false -- visible rivals are armed to spawn after the race start
Racing._postStartLiveSpawnTimer   = 0.0   -- elapsed racing time since visible rivals were armed
Racing._postStartLiveSpawnReason  = nil   -- last gate / state reason for post-start visible spawn
Racing._postStartSpawnRequested   = false -- live rival spawnFormation has been requested this race
Racing._ghostFallbackActive       = false -- explicit ghost scoring fallback is active
Racing._ghostFallbackReason       = nil   -- last reason ghost fallback was enabled
Racing._nearFinishDNFGraceArmed   = false -- one-shot DNF grace has been armed because the player is near the line
Racing._nearFinishDNFGraceUntil   = nil   -- race time until which the near-finish DNF grace remains active
Racing._finishResolver            = nil   -- post-player-finish classification window for live trailing rivals
Racing._sequenceRaceState         = nil   -- multi-target race state for sprint laps / endurance circuits
Racing._rollingZoneActive         = false -- rolling-start order/pace discipline is currently active
Racing._rollingZoneReason         = nil   -- last rolling-start state transition reason
Racing._rollingZoneStartProgress  = nil   -- route progress at the moment the rolling zone began
Racing._rollingZoneLength         = _tuningValue("rollingZoneLengthM", Racing._config)
Racing._rollingLeaderProgress     = 0.0
Racing._rollingTargetPaceMin      = nil
Racing._rollingTargetPaceMax      = nil
Racing._rollingTargetPace         = nil
Racing._rollingLeaderIsPlayer     = false
Racing._rollingWarmupArmed        = false
Racing._rollingPlayerViolation    = nil   -- active rolling-start violation code for V
Racing._rollingPlayerViolationAt  = nil   -- race time when the current player violation began
Racing._rollingPlayerWarningTimer = 0.0

local ROUTE_MODE_RANDOM = "random"
local ROUTE_MODE_PICKED = "picked"
local ROUTE_MODE_MANUAL = "manual"
local ROUTE_MODE_ROOT = "root"

local QUICK_RACE_MODE_STANDARD = "standard"
local QUICK_RACE_MODE_ENDURANCE = "endurance"
local QUICK_RACE_MODE_KNOCKOUT = "knockout"
local QUICK_RACE_KNOCKOUT_TRAFFIC_NORMAL = "normal"
local QUICK_RACE_KNOCKOUT_TRAFFIC_NONE = "none"
local QUICK_RACE_KNOCKOUT_TRAFFIC_HEAVY = "heavy"
local QUICK_RACE_KNOCKOUT_COMBAT_ALLOWED = "allowed"
local QUICK_RACE_KNOCKOUT_COMBAT_DISALLOWED = "disallowed"
local QUICK_RACE_WEIGHTING_OPTIONS = { "mostly_low", "mixed", "mostly_high" }
local QUICK_RACE_MISMATCH_OFF = "off"
local QUICK_RACE_MISMATCH_WARN = "warn"
local QUICK_RACE_MISMATCH_STRICT = "strict"
local QUICK_RACE_SETTING_MAP = {
    quickRaceMode = "quickRaceMode",
    gridLateralShiftM = "gridLateralShiftM",
    defaultStartType = "quickRaceStartType",
    defaultFieldSize = "quickRaceFieldSize",
    allowStakes = "quickRaceAllowStakes",
    allowCombat = "quickRaceAllowCombat",
    qualiEnabled = "quickRaceQualifying",
    vehicleClass = "quickRaceVehicleClass",
    timeOfDay = "quickRaceTimeOfDay",
    minDistanceM = "quickRaceMinDistanceM",
    maxDistanceM = "quickRaceMaxDistanceM",
    preferredRegions = "quickRacePreferredRegions",
    routeMode = "quickRaceRouteMode",
    raceType = "quickRaceRaceType",
    selectedRootId = "quickRaceSelectedRootId",
    selectedStartNodeId = "quickRaceSelectedStartNodeId",
    selectedFinishNodeId = "quickRaceSelectedFinishNodeId",
    quickRaceDriverTierMin = "quickRaceDriverTierMin",
    quickRaceDriverTierMax = "quickRaceDriverTierMax",
    quickRacePrestigeMin = "quickRacePrestigeMin",
    quickRacePrestigeMax = "quickRacePrestigeMax",
    quickRacePrestigeWeighting = "quickRacePrestigeWeighting",
    quickRaceAllowBossOutlier = "quickRaceAllowBossOutlier",
    quickRaceMismatchPolicy = "quickRaceMismatchPolicy",
    lapCount = "quickRaceLapCount",
    quickRaceEnduranceCircuitId = "quickRaceEnduranceCircuitId",
    quickRaceKnockoutCircuitId = "quickRaceKnockoutCircuitId",
    quickRaceKnockoutGridSize = "quickRaceKnockoutGridSize",
    quickRaceKnockoutTrafficMode = "quickRaceKnockoutTrafficMode",
    quickRaceKnockoutCombatMode = "quickRaceKnockoutCombatMode",
    specFieldEnabled = "quickRaceSpecFieldEnabled",
    specFieldRecord = "quickRaceSpecFieldRecord",
    specField = "quickRaceSpecField",
    specFieldFormulaTuning = "quickRaceSpecFieldFormulaTuning",
}

Racing.QUICK_RACE_MODES = {
    QUICK_RACE_MODE_STANDARD,
    QUICK_RACE_MODE_ENDURANCE,
    QUICK_RACE_MODE_KNOCKOUT,
}
Racing.QUICK_RACE_WEIGHTINGS = QUICK_RACE_WEIGHTING_OPTIONS
Racing.QUICK_RACE_MISMATCH_POLICIES = {
    QUICK_RACE_MISMATCH_OFF,
    QUICK_RACE_MISMATCH_WARN,
    QUICK_RACE_MISMATCH_STRICT,
}

local function _clearRacerMarkers()
    if MTE and MTE.Mappins and MTE.Mappins.clearRacerMarkers then
        MTE.Mappins.clearRacerMarkers()
    end
end

local function _getNamedRouteNodes()
    local nodes = {}
    for _, node in ipairs((MTE and MTE.Nodes) or {}) do
        if type(node) == "table" and node.id then
            table.insert(nodes, node)
        end
    end
    return nodes
end

local function _getNamedRoots()
    if MTE and MTE.Roots and MTE.Roots.all then
        return MTE.Roots.all({ includeInvalid = false }) or {}
    end
    return {}
end

local function _findDraftNodeById(nodeId, nodes)
    if not nodeId then return nil end
    for _, node in ipairs(nodes or {}) do
        if node.id == nodeId then
            return node
        end
    end
    return nil
end

local function _findDraftRootById(rootId, roots)
    if not rootId then return nil end
    for _, root in ipairs(roots or {}) do
        if root.rootId == rootId then
            return root
        end
    end
    return nil
end

local function normalizeDraftRouteConfig(draft)
    if type(draft) ~= "table" then
        return ROUTE_MODE_RANDOM
    end

    local routeMode = draft.routeMode
    if routeMode ~= ROUTE_MODE_RANDOM and routeMode ~= ROUTE_MODE_PICKED and routeMode ~= ROUTE_MODE_MANUAL and routeMode ~= ROUTE_MODE_ROOT then
        routeMode = draft.useManualNodes and ROUTE_MODE_MANUAL or ROUTE_MODE_RANDOM
    end

    local hasManualPair = MTE and MTE.ManualNodes and MTE.ManualNodes.hasPair and MTE.ManualNodes.hasPair()
    local nodes = _getNamedRouteNodes()
    local roots = _getNamedRoots()

    if routeMode == ROUTE_MODE_MANUAL and not hasManualPair then
        routeMode = (#nodes >= 2) and ROUTE_MODE_PICKED or ROUTE_MODE_RANDOM
    end

    if routeMode == ROUTE_MODE_ROOT then
        if #roots == 0 then
            routeMode = (#nodes >= 2) and ROUTE_MODE_PICKED or (hasManualPair and ROUTE_MODE_MANUAL or ROUTE_MODE_RANDOM)
        else
            local root = _findDraftRootById(draft.selectedRootId, roots) or roots[1]
            draft.selectedRootId = root and root.rootId or nil
            draft.selectedStartNodeId = root and root.startNodeId or draft.selectedStartNodeId
            draft.selectedFinishNodeId = root and root.endNodeId or draft.selectedFinishNodeId
        end
    end

    if routeMode == ROUTE_MODE_PICKED then
        local startNode = _findDraftNodeById(draft.selectedStartNodeId, nodes)
        local finishNode = _findDraftNodeById(draft.selectedFinishNodeId, nodes)

        if not startNode and #nodes > 0 then
            startNode = nodes[1]
        end
        if (not finishNode or (startNode and finishNode.id == startNode.id)) and #nodes > 1 then
            for _, node in ipairs(nodes) do
                if not startNode or node.id ~= startNode.id then
                    finishNode = node
                    break
                end
            end
        end

        if startNode and finishNode and startNode.id ~= finishNode.id then
            draft.selectedStartNodeId = startNode.id
            draft.selectedFinishNodeId = finishNode.id
        else
            routeMode = hasManualPair and ROUTE_MODE_MANUAL or ROUTE_MODE_RANDOM
        end
    end

    draft.routeMode = routeMode
    draft.useManualNodes = (routeMode == ROUTE_MODE_MANUAL)
    return routeMode
end

local function clampInt(value, minValue, maxValue)
    local number = math.floor(tonumber(value) or minValue)
    if number < minValue then return minValue end
    if number > maxValue then return maxValue end
    return number
end

local function clampNumber(value, minValue, maxValue)
    local number = tonumber(value) or tonumber(minValue) or 0.0
    if number < minValue then return minValue end
    if number > maxValue then return maxValue end
    return number
end

local function normalizeQuickRaceMismatchPolicy(policy)
    if policy == QUICK_RACE_MISMATCH_OFF or policy == QUICK_RACE_MISMATCH_WARN or policy == QUICK_RACE_MISMATCH_STRICT then
        return policy
    end
    return QUICK_RACE_MISMATCH_OFF
end

local function normalizeQuickRaceMode(mode)
    if mode == QUICK_RACE_MODE_KNOCKOUT or mode == QUICK_RACE_MODE_ENDURANCE then
        return mode
    end
    return QUICK_RACE_MODE_STANDARD
end

local function normalizeQuickRaceKnockoutTrafficMode(mode)
    if mode == QUICK_RACE_KNOCKOUT_TRAFFIC_NONE or mode == QUICK_RACE_KNOCKOUT_TRAFFIC_HEAVY then
        return mode
    end
    return QUICK_RACE_KNOCKOUT_TRAFFIC_NORMAL
end

local function normalizeQuickRaceKnockoutCombatMode(mode)
    if mode == QUICK_RACE_KNOCKOUT_COMBAT_DISALLOWED then
        return mode
    end
    return QUICK_RACE_KNOCKOUT_COMBAT_ALLOWED
end

local function getQuickRaceKnockoutCircuits()
    if MTE and MTE.KnockoutCircuits and MTE.KnockoutCircuits.quickRaceAll then
        return MTE.KnockoutCircuits.quickRaceAll() or {}
    end
    return {}
end

local function findQuickRaceKnockoutCircuit(circuitId, circuits)
    for _, circuit in ipairs(circuits or {}) do
        if circuit.id == circuitId then
            return circuit
        end
    end
    return nil
end

local function normalizeLapCount(raceType, lapCount, isLoop)
    local normalized = clampInt(lapCount or 1, 1, 8)
    if raceType == "drag" then
        return 1
    end
    if raceType == "endurance" and not isLoop then
        return 1
    end
    return normalized
end

local function findQuickRaceEnduranceCircuit(circuitId, circuits)
    return findQuickRaceKnockoutCircuit(circuitId, circuits)
end

local function normalizeQuickRaceKnockoutConfig(draft)
    if type(draft) ~= "table" then return end

    draft.quickRaceMode = normalizeQuickRaceMode(draft.quickRaceMode)
    draft.quickRaceKnockoutTrafficMode = normalizeQuickRaceKnockoutTrafficMode(draft.quickRaceKnockoutTrafficMode)
    draft.quickRaceKnockoutCombatMode = normalizeQuickRaceKnockoutCombatMode(draft.quickRaceKnockoutCombatMode)

    if draft.quickRaceMode ~= QUICK_RACE_MODE_KNOCKOUT then
        return
    end

    local circuits = getQuickRaceKnockoutCircuits()
    local selectedCircuit = findQuickRaceKnockoutCircuit(draft.quickRaceKnockoutCircuitId, circuits) or circuits[1]
    draft.quickRaceKnockoutCircuitId = selectedCircuit and selectedCircuit.id or nil

    local maxTotalGridSize = selectedCircuit
        and MTE and MTE.KnockoutCircuits
        and MTE.KnockoutCircuits.getMaxTotalGridSize
        and MTE.KnockoutCircuits.getMaxTotalGridSize(selectedCircuit)
        or nil
    if type(maxTotalGridSize) == "number" then
        draft.quickRaceKnockoutGridSize = math.max(2, math.floor(maxTotalGridSize))
    else
        draft.quickRaceKnockoutGridSize = nil
    end
end

local function normalizeQuickRaceEnduranceConfig(draft)
    if type(draft) ~= "table" then return end
    if tostring(draft.raceType or "sprint") ~= "endurance" then
        return
    end

    local sourceType = draft.quickRaceEnduranceSourceType or "circuit"
    if sourceType == "route" then
        local root = MTE and MTE.Roots and MTE.Roots.resolveRoot and draft.quickRaceEnduranceRootId
            and MTE.Roots.resolveRoot(draft.quickRaceEnduranceRootId) or nil
        if not root or #(root.nodeIds or {}) < 3 then
            draft.quickRaceEnduranceRootId = nil
        end
        draft.lapCount = normalizeLapCount("endurance", draft.lapCount, root and root.isLoop == true)
    else
        local circuits = getQuickRaceKnockoutCircuits()
        local selectedCircuit = findQuickRaceEnduranceCircuit(draft.quickRaceEnduranceCircuitId, circuits) or circuits[1]
        draft.quickRaceEnduranceCircuitId = selectedCircuit and selectedCircuit.id or nil
        draft.lapCount = normalizeLapCount("endurance", draft.lapCount, selectedCircuit and selectedCircuit.isLoop == true)
    end
end

local function normalizePreferredRegions(regions)
    if type(regions) ~= "table" then
        return nil
    end
    local normalized = {}
    local seen = {}
    for _, region in ipairs(regions) do
        if type(region) == "string" then
            local trimmed = region:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" and not seen[trimmed] then
                seen[trimmed] = true
                normalized[#normalized + 1] = trimmed
            end
        end
    end
    if #normalized == 0 then
        return nil
    end
    return normalized
end

local function copyShallowValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = v end
    return copy
end

-- ── Spec field (one-make lineup) ─────────────────────────────────
-- draft.specField = { { record = <TweakDB vehicle record or nil>, appearance = <livery name|"stock">, count = n }, ... }
-- Expanded in order into one {record, appearance} per AI rival. Only applies to standard-mode sprint races.
local SPEC_FIELD_DEFAULT_RECORD = "Vehicle.v_sport1_rb15_f1"
Racing.SPEC_FIELD_DEFAULT_RECORD = SPEC_FIELD_DEFAULT_RECORD
Racing.SPEC_FIELD_PRESET_RB15_20 = {
    { appearance = "stock",         count = 1 },
    { appearance = "rayfield",      count = 2 },
    { appearance = "herrera",       count = 2 },
    { appearance = "mizutani",      count = 2 },
    { appearance = "quadra",        count = 2 },
    { appearance = "thorton",       count = 2 },
    { appearance = "archer",        count = 2 },
    { appearance = "spunky_monkey", count = 2 },
    { appearance = "kimiko",        count = 2 },
    { appearance = "yorinobu",      count = 2 },
}
-- Per-race tuning overrides applied through config.rootProfileSettings (the saved user settings are never written).
Racing.SPEC_FIELD_FORMULA_TUNING = {
    maxAiCars = 24,
    aiRaceMaxSpeedMps = 100.0,
    aiBaseSpeedMps = 55.0,
    aiProjectedBaseSpeedMps = 55.0,
    aiGridRowSpacingM = 8.0,
    aiGridStartSetbackM = 10.0,
    trafficClearRadiusM = 220.0,
}

local function normalizeSpecField(draft)
    draft.specFieldEnabled = draft.specFieldEnabled == true
    if type(draft.specFieldRecord) ~= "string" or draft.specFieldRecord == "" then
        draft.specFieldRecord = SPEC_FIELD_DEFAULT_RECORD
    end
    local rows = {}
    for _, row in ipairs(type(draft.specField) == "table" and draft.specField or {}) do
        if type(row) == "table" then
            local count = math.floor(tonumber(row.count) or 0)
            if count > 0 then
                rows[#rows + 1] = {
                    record = (type(row.record) == "string" and row.record ~= "") and row.record or nil,
                    appearance = tostring(row.appearance or "stock"),
                    count = math.min(count, 24),
                }
            end
        end
    end
    draft.specField = rows
    draft.specFieldFormulaTuning = draft.specFieldFormulaTuning ~= false
end

--- Expand the lineup rows into per-rival assignments (record + appearance|nil), capped at maxCount.
function Racing.expandSpecField(draft, maxCount)
    local out = {}
    if type(draft) ~= "table" or type(draft.specField) ~= "table" then return out end
    local baseRecord = (type(draft.specFieldRecord) == "string" and draft.specFieldRecord ~= "") and draft.specFieldRecord or SPEC_FIELD_DEFAULT_RECORD
    local cap = tonumber(maxCount) or 24
    for _, row in ipairs(draft.specField) do
        local count = math.floor(tonumber(row.count) or 0)
        local appearance = row.appearance
        if MTE and MTE.Liveries and MTE.Liveries.appearanceFor then
            appearance = MTE.Liveries.appearanceFor(appearance)
        elseif appearance == "stock" or appearance == "player_01" or appearance == "" then
            appearance = nil
        end
        for _ = 1, count do
            if #out >= cap then return out end
            out[#out + 1] = { record = row.record or baseRecord, appearance = appearance }
        end
    end
    return out
end

function Racing.getSpecFieldTotal(draft)
    local total = 0
    if type(draft) == "table" and type(draft.specField) == "table" then
        for _, row in ipairs(draft.specField) do total = total + math.max(0, math.floor(tonumber(row.count) or 0)) end
    end
    return total
end

function Racing.applySpecFieldPreset(draft)
    if type(draft) ~= "table" then return end
    draft.specFieldEnabled = true
    draft.specFieldRecord = SPEC_FIELD_DEFAULT_RECORD
    draft.specField = {}
    for _, row in ipairs(Racing.SPEC_FIELD_PRESET_RB15_20) do
        draft.specField[#draft.specField + 1] = { appearance = row.appearance, count = row.count }
    end
    draft.specFieldFormulaTuning = true
end

-- Apply the lineup to a provisional race config (both preview builders call this after rootProfileSettings resolve).
local function applySpecFieldToConfig(draft, cfg, raceType)
    if type(draft) ~= "table" or type(cfg) ~= "table" then return end
    if draft.specFieldEnabled ~= true then return end
    if (cfg.eventSourceType or draft._eventSourceType) ~= "quick_race" then return end   -- sandbox quick races only
    if (raceType or cfg.raceType or "sprint") ~= "sprint" then return end
    if draft.quickRaceMode ~= nil and draft.quickRaceMode ~= "standard" then return end
    local maxAi = 24
    if draft.specFieldFormulaTuning == false then
        maxAi = math.floor(tonumber(_tuningValue("maxAiCars", cfg, 12)) or 12)
    end
    local assignments = Racing.expandSpecField(draft, maxAi)
    if #assignments == 0 then return end
    cfg.specField = copyShallowValue(draft.specField)
    cfg.specFieldRecord = draft.specFieldRecord
    cfg.specFieldAssignments = assignments
    cfg.fieldSize = #assignments
    cfg.vehicleClass = nil       -- one-make: bypass the class override/filter paths
    if draft.specFieldFormulaTuning ~= false then
        local merged = {}
        if type(cfg.rootProfileSettings) == "table" then
            for k, v in pairs(cfg.rootProfileSettings) do merged[k] = v end
        end
        for k, v in pairs(Racing.SPEC_FIELD_FORMULA_TUNING) do merged[k] = v end
        if MTE and MTE.Settings and MTE.Settings.sanitizeProfileSettings then
            merged = MTE.Settings.sanitizeProfileSettings(merged) or merged
        end
        cfg.rootProfileSettings = merged
        cfg.specFieldFormulaTuningApplied = true
    end
    print(string.format("[NCM/Racing] spec_field_active record=%s rivals=%d formulaTuning=%s",
        tostring(draft.specFieldRecord), #assignments, tostring(draft.specFieldFormulaTuning ~= false)))
end

local function quickRaceFallbackTier(career)
    return career and career.tier or "Gonk"
end

local function getQuickRaceTierPrestigeBand(minTier, maxTier, fallbackTier)
    local tiers = MTE and MTE.Roster and MTE.Roster.tiersInRange
        and MTE.Roster.tiersInRange(minTier, maxTier, fallbackTier)
        or { fallbackTier or "Gonk" }
    local bandMin, bandMax = nil, nil

    for _, tier in ipairs(tiers or {}) do
        local tierMin, tierMax = VehiclePool.recommendedPrestigeBandForTier(tier)
        if tierMin then
            bandMin = bandMin and math.min(bandMin, tierMin) or tierMin
        end
        if tierMax then
            bandMax = bandMax and math.max(bandMax, tierMax) or tierMax
        end
    end

    return bandMin or 1, bandMax or 5
end

local function normalizeQuickRaceConfig(draft, career)
    if type(draft) ~= "table" then return end

    normalizeQuickRaceKnockoutConfig(draft)
    normalizeQuickRaceEnduranceConfig(draft)
    draft.lapCount = normalizeLapCount(draft.raceType or "sprint", draft.lapCount, true)

    if draft.quickRaceMode == QUICK_RACE_MODE_KNOCKOUT then
        return
    end

    if draft.quickRaceMode == QUICK_RACE_MODE_ENDURANCE then
        draft.raceType = "endurance"
    elseif draft.quickRaceMode == QUICK_RACE_MODE_STANDARD and draft.raceType == "endurance" then
        draft.raceType = "sprint"
    end

    if draft.raceType == "endurance" then
        draft.routeMode = ROUTE_MODE_RANDOM
        draft.selectedRootId = nil
        draft.selectedStartNodeId = nil
        draft.selectedFinishNodeId = nil
        draft.minDistanceM = nil
        draft.maxDistanceM = nil
        normalizeQuickRaceEnduranceConfig(draft)
    elseif draft.raceType == "drag" then
        draft.lapCount = 1
    end

    local fallbackTier = quickRaceFallbackTier(career)
    local minTier, maxTier
    if MTE and MTE.Roster and MTE.Roster.normalizeTierRange then
        minTier, maxTier = MTE.Roster.normalizeTierRange(
            draft.quickRaceDriverTierMin,
            draft.quickRaceDriverTierMax,
            fallbackTier)
    else
        minTier = draft.quickRaceDriverTierMin or fallbackTier
        maxTier = draft.quickRaceDriverTierMax or minTier
    end

    draft.quickRaceDriverTierMin = minTier
    draft.quickRaceDriverTierMax = maxTier

    local recMin, recMax = getQuickRaceTierPrestigeBand(minTier, maxTier, fallbackTier)
    local prestigeMin = clampInt(draft.quickRacePrestigeMin or recMin, 1, 5)
    local prestigeMax = clampInt(draft.quickRacePrestigeMax or recMax, 1, 5)
    if prestigeMin > prestigeMax then prestigeMin, prestigeMax = prestigeMax, prestigeMin end

    draft.quickRacePrestigeMin = prestigeMin
    draft.quickRacePrestigeMax = prestigeMax
    draft.quickRacePrestigeWeighting = VehiclePool.normalizeQuickRaceWeighting(draft.quickRacePrestigeWeighting)
    draft.quickRaceAllowBossOutlier = draft.quickRaceAllowBossOutlier == true
    draft.quickRaceMismatchPolicy = normalizeQuickRaceMismatchPolicy(draft.quickRaceMismatchPolicy)
    draft.preferredRegions = normalizePreferredRegions(draft.preferredRegions)
    normalizeSpecField(draft)
end

local function appendSequenceTarget(targets, node, lapNumber, nodeIndex)
    if type(node) ~= "table" then
        return
    end
    targets[#targets + 1] = {
        id = node.id,
        name = node.name,
        x = node.x,
        y = node.y,
        z = node.z,
        lapNumber = lapNumber,
        nodeIndex = nodeIndex,
    }
end

local function finalizeSequenceTargets(startNode, targets)
    local totalDistance = 0.0
    local previousNode = startNode
    for index, target in ipairs(targets) do
        local segmentDistance = Racing._estimateDistance(previousNode, target)
        totalDistance = totalDistance + segmentDistance
        target.targetIndex = index
        target.segmentDistance = segmentDistance
        target.cumulativeDistance = totalDistance
        previousNode = target
    end
    return {
        targets = targets,
        totalTargets = #targets,
        totalDistance = totalDistance,
        finishNode = targets[#targets] or startNode,
    }
end

local function buildSprintLapSequence(nodeA, nodeB, lapCount)
    local targets = {}
    local normalizedLapCount = normalizeLapCount("sprint", lapCount, false)
    for lap = 1, normalizedLapCount do
        local targetNode = (lap % 2 == 1) and nodeB or nodeA
        appendSequenceTarget(targets, targetNode, lap, lap)
    end

    local sequence = finalizeSequenceTargets(nodeA, targets)
    sequence.kind = "sprint_laps"
    sequence.startNode = nodeA
    sequence.currentLapCount = normalizedLapCount
    return sequence
end

local function buildEnduranceSequence(circuit, resolvedCheckpoints, lapCount)
    if type(circuit) ~= "table" or type(resolvedCheckpoints) ~= "table" or #resolvedCheckpoints < 2 then
        return nil
    end

    local normalizedLapCount = normalizeLapCount("endurance", lapCount, circuit.isLoop == true)
    local targets = {}
    if circuit.isLoop then
        for lap = 1, normalizedLapCount do
            for index = 2, #resolvedCheckpoints do
                appendSequenceTarget(targets, resolvedCheckpoints[index], lap, index)
            end
            appendSequenceTarget(targets, resolvedCheckpoints[1], lap, 1)
        end
    else
        for index = 2, #resolvedCheckpoints do
            appendSequenceTarget(targets, resolvedCheckpoints[index], 1, index)
        end
    end

    local sequence = finalizeSequenceTargets(resolvedCheckpoints[1], targets)
    sequence.kind = "endurance"
    sequence.circuit = circuit
    sequence.resolvedCheckpoints = resolvedCheckpoints
    sequence.startNode = resolvedCheckpoints[1]
    sequence.currentLapCount = normalizedLapCount
    return sequence
end

local function buildRootSequence(root, lapCount)
    local resolvedNodes = root and root.nodes or nil
    if type(resolvedNodes) ~= "table" or #resolvedNodes < 2 then
        return nil
    end

    local isLoop = root.isLoop == true
    local normalizedLapCount = isLoop and normalizeLapCount("sprint", lapCount, true) or 1
    local targets = {}

    for lap = 1, normalizedLapCount do
        for index = 2, #resolvedNodes do
            appendSequenceTarget(targets, resolvedNodes[index], lap, index)
        end
    end

    local sequence = finalizeSequenceTargets(resolvedNodes[1], targets)
    sequence.kind = "root_route"
    sequence.rootId = root.rootId
    sequence.startNode = resolvedNodes[1]
    sequence.resolvedCheckpoints = resolvedNodes
    sequence.currentLapCount = normalizedLapCount
    sequence.isLoop = isLoop
    return sequence
end

local function applySavedQuickRaceDraft(draft, career)
    if type(draft) ~= "table" then return end
    local settings = MTE and MTE.Settings and MTE.Settings.current or nil
    if type(settings) == "table" then
        for configKey, settingKey in pairs(QUICK_RACE_SETTING_MAP) do
            if settings[settingKey] ~= nil then
                draft[configKey] = copyShallowValue(settings[settingKey])
            end
        end
    end
    normalizeDraftRouteConfig(draft)
    normalizeQuickRaceConfig(draft, career)
end

local function detectVehicleClassFromTags(tags)
    for _, className in ipairs({ "Bike", "Muscle", "Sport", "Tech", "Nomad" }) do
        for _, tag in ipairs(tags or {}) do
            local tagText = tostring(tag):lower()
            for _, wanted in ipairs(CLASS_TAGS[className] or {}) do
                if tagText:find(wanted, 1, true) then
                    return className
                end
            end
        end
    end
    return nil
end

local function getPlayerVehicleSnapshot()
    local snapshot = {
        vehicleId = Racing._getVehicleId and Racing._getVehicleId() or nil,
        meta = nil,
        carClass = nil,
    }

    if snapshot.vehicleId then
        snapshot.meta = VehiclePool.getVehicleMeta(snapshot.vehicleId)
        if snapshot.meta then
            snapshot.carClass = snapshot.meta.carClass
        end
    end

    if snapshot.carClass then
        return snapshot
    end

    if snapshot.vehicleId then
        snapshot.carClass = detectVehicleClassFromTags({ snapshot.vehicleId })
        if snapshot.carClass then
            return snapshot
        end
    end

    local tags = {}
    pcall(function()
        local veh = Game.GetMountedVehicle(Game.GetPlayer())
        if not veh then return end
        local rec = veh:GetRecord()
        if rec then
            tags = rec:Tags() or {}
        end
    end)
    snapshot.carClass = detectVehicleClassFromTags(tags)
    return snapshot
end

function Racing.persistQuickRaceDraft(draft)
    local settings = MTE and MTE.Settings and MTE.Settings.current or nil
    local source = type(draft) == "table" and draft or Racing._draft
    local career = Racing._career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    if type(source) ~= "table" or type(settings) ~= "table" then
        return false
    end

    local snapshot = Racing._copyConfig(source)
    normalizeDraftRouteConfig(snapshot)
    normalizeQuickRaceConfig(snapshot, career)

    for configKey, settingKey in pairs(QUICK_RACE_SETTING_MAP) do
        settings[settingKey] = copyShallowValue(snapshot[configKey])
    end

    return MTE and MTE.Settings and MTE.Settings.save and MTE.Settings.save() or false
end

function Racing.evaluateQuickRaceCompatibility(draft)
    if type(draft) ~= "table" then return nil end

    local career = Racing._career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    normalizeQuickRaceConfig(draft, career)

    if draft.quickRaceMode == QUICK_RACE_MODE_KNOCKOUT then
        return nil
    end

    local fieldPrestigeMin, fieldPrestigeMax = getQuickRaceTierPrestigeBand(
        draft.quickRaceDriverTierMin,
        draft.quickRaceDriverTierMax,
        quickRaceFallbackTier(career))

    local report = {
        policy = normalizeQuickRaceMismatchPolicy(draft.quickRaceMismatchPolicy),
        explicitPrestigeMin = draft.quickRacePrestigeMin,
        explicitPrestigeMax = draft.quickRacePrestigeMax,
        fieldPrestigeMin = fieldPrestigeMin,
        fieldPrestigeMax = fieldPrestigeMax,
        tierMin = draft.quickRaceDriverTierMin,
        tierMax = draft.quickRaceDriverTierMax,
        playerVehicleId = nil,
        playerVehicleMeta = nil,
        playerVehicleClass = nil,
        blockingIssues = {},
        warnings = {},
        status = "ok",
        isBlocking = false,
        summary = nil,
    }

    local classOk, classErr = Racing._checkVehicleClass(draft.vehicleClass)
    if not classOk and classErr then
        table.insert(report.blockingIssues, classErr)
    end

    local snapshot = getPlayerVehicleSnapshot()
    report.playerVehicleId = snapshot.vehicleId
    report.playerVehicleMeta = snapshot.meta
    report.playerVehicleClass = snapshot.carClass

    local prestigeIssues = {}
    if snapshot.meta then
        local playerPrestige = snapshot.meta.prestige or 0
        if playerPrestige < report.explicitPrestigeMin or playerPrestige > report.explicitPrestigeMax then
            table.insert(prestigeIssues, i18n.format(
                "Player car prestige P%d is outside the selected Quick Race range P%d-P%d.",
                playerPrestige,
                report.explicitPrestigeMin,
                report.explicitPrestigeMax))
        end
        if playerPrestige < fieldPrestigeMin or playerPrestige > fieldPrestigeMax then
            table.insert(prestigeIssues, i18n.format(
                "Player car prestige P%d is outside the selected field-strength band %s-%s (suggested P%d-P%d).",
                playerPrestige,
                tostring(report.tierMin),
                tostring(report.tierMax),
                fieldPrestigeMin,
                fieldPrestigeMax))
        end
    elseif snapshot.vehicleId then
        table.insert(report.warnings, "Current vehicle is not in the curated prestige catalog; prestige mismatch could not be checked.")
    else
        table.insert(report.warnings, "No mounted vehicle detected; prestige compatibility will be checked once you enter one.")
    end

    if report.policy == QUICK_RACE_MISMATCH_STRICT then
        for _, issue in ipairs(prestigeIssues) do
            table.insert(report.blockingIssues, issue)
        end
    elseif report.policy == QUICK_RACE_MISMATCH_WARN then
        for _, issue in ipairs(prestigeIssues) do
            table.insert(report.warnings, issue)
        end
    end

    if #report.blockingIssues > 0 then
        report.isBlocking = true
        report.status = "block"
        report.summary = report.blockingIssues[1]
    elseif #report.warnings > 0 then
        report.status = "warn"
        report.summary = report.warnings[1]
    end

    return report
end

-- ── Init ──────────────────────────────────────────────────────

local function _notify(msg, dur)
    pcall(function()
        local uiSys = Game.GetUISystem()
        if uiSys then
            local evt    = SimpleScreenMessage.new()
            evt.message  = msg
            evt.duration = dur or 2.0
            evt.isShown  = true
            uiSys:QueueEvent(evt)
        end
    end)
end

local function _timePaused()
    local paused = false
    pcall(function()
        local ts = Game.GetTimeSystem()
        if ts and ts.IsPausedState and ts:IsPausedState() then
            paused = true
        end
    end)
    if not paused then
        pcall(function()
            if MTE and MTE.overlayOpen == true then
                paused = true
            end
        end)
    end
    return paused
end

local function _getPlayerVehicle()
    local veh = nil
    pcall(function()
        veh = Game.GetMountedVehicle(Game.GetPlayer())
    end)
    return veh
end

local function _normalizePlanarVector(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil
    end
    local len = math.sqrt(x * x + y * y)
    if len < 0.001 then
        return nil, nil
    end
    return x / len, y / len
end

local function _buildManualGridSpawnNodes(requestedCount)
    local anchor = _getPlayerVehicle() or Game.GetPlayer()
    local anchorPos = nil
    local forwardX, forwardY = nil, nil

    pcall(function()
        if anchor and anchor.GetWorldPosition then
            anchorPos = anchor:GetWorldPosition()
        end
    end)
    if not anchorPos then
        anchorPos = Racing._getPlayerPos and Racing._getPlayerPos() or nil
    end
    if not anchorPos then
        return nil, nil, nil, nil, "player_position_unavailable"
    end

    pcall(function()
        if anchor and anchor.GetWorldForward then
            local forward = anchor:GetWorldForward()
            forwardX, forwardY = _normalizePlanarVector(
                tonumber(forward and forward.x or nil),
                tonumber(forward and forward.y or nil))
        end
    end)

    if not forwardX or not forwardY then
        local cfg = Racing._config or {}
        local fallbackHeading = _getResolvedGridHeading(cfg.nodeA, cfg.nodeB, cfg)
        if type(fallbackHeading) == "number" then
            local radians = math.rad(fallbackHeading)
            forwardX = math.cos(radians)
            forwardY = math.sin(radians)
        end
    end

    if not forwardX or not forwardY then
        return nil, nil, nil, nil, "forward_vector_unavailable"
    end

    local count = math.max(1, math.min(2, math.floor(tonumber(requestedCount) or 1)))
    local forwardDistance = MANUAL_GRID_FORWARD_DISTANCE_M + ((count > 1) and 1.5 or 0.0)
    local startNode = {
        x = (anchorPos.x or 0.0) + forwardX * forwardDistance,
        y = (anchorPos.y or 0.0) + forwardY * forwardDistance,
        z = anchorPos.z or 0.0,
        name = "Manual Grid Ahead",
    }
    local finishNode = {
        x = startNode.x + forwardX * MANUAL_GRID_FINISH_DISTANCE_M,
        y = startNode.y + forwardY * MANUAL_GRID_FINISH_DISTANCE_M,
        z = startNode.z,
        name = "Manual Grid Runoff",
    }
    local heading = (math.deg(math.atan2(forwardY, forwardX)) + 360.0) % 360.0
    return startNode, finishNode, heading, { x = forwardX, y = forwardY }, nil
end

local function _extractEntityID(entityOrId)
    if not entityOrId then
        return nil
    end
    local entityID = nil
    pcall(function()
        if entityOrId.GetEntityID then
            entityID = entityOrId:GetEntityID()
        end
    end)
    return entityID or entityOrId
end

local function _sameEntityID(left, right)
    local leftID = _extractEntityID(left)
    local rightID = _extractEntityID(right)
    if not leftID or not rightID then
        return false
    end
    return tostring(leftID) == tostring(rightID)
end

local function _despawnAmbientEntity(entityOrId)
    local entityID = _extractEntityID(entityOrId)
    local entity = entityOrId
    if entityID and (not entity or not entity.GetWorldPosition) then
        pcall(function()
            entity = Game.FindEntityByID(entityID)
        end)
    end

    pcall(function()
        local entitySystem = nil
        pcall(function()
            entitySystem = Game.GetDynamicEntitySystem()
        end)
        if entitySystem and entityID then
            local ok = pcall(function()
                entitySystem:DespawnEntity(entityID)
            end)
            if ok then return end

            ok = pcall(function()
                entitySystem:DeleteEntity(entityID)
            end)
            if ok then return end
        end

        if entity and exEntitySpawner and exEntitySpawner.Despawn then
            exEntitySpawner.Despawn(entity)
        end
    end)
end

local function _collectSystemVehicleLists(system)
    local lists = {}
    if not system then
        return lists
    end

    for _, methodName in ipairs({ "GetActiveVehicles", "GetSpawnedVehicles", "GetVehicles", "GetAllVehicles" }) do
        local method = system[methodName]
        if method then
            local ok, result = pcall(function()
                return method(system)
            end)
            if ok and type(result) == "table" then
                table.insert(lists, result)
            end
        end
    end

    return lists
end

local function _tryClearTrafficSystemArea(system, node, radius)
    if not system or not node then
        return false
    end

    local pos3 = Vector3.new(node.x or 0, node.y or 0, node.z or 0)
    local pos4 = Vector4.new(node.x or 0, node.y or 0, node.z or 0, 1.0)
    local cleared = false

    local calls = {
        { "ClearTrafficAroundPoint", { pos3, radius } },
        { "ClearTrafficAroundPoint", { pos4, radius } },
        { "ClearTrafficAroundPosition", { pos3, radius } },
        { "ClearTrafficAroundPosition", { pos4, radius } },
        { "DespawnTrafficAroundPoint", { pos3, radius } },
        { "DespawnTrafficAroundPoint", { pos4, radius } },
        { "DespawnTrafficAroundPosition", { pos3, radius } },
        { "DespawnTrafficAroundPosition", { pos4, radius } },
        { "DespawnVehiclesAroundPoint", { pos3, radius } },
        { "DespawnVehiclesAroundPoint", { pos4, radius } },
        { "DespawnVehiclesAroundPosition", { pos3, radius } },
        { "DespawnVehiclesAroundPosition", { pos4, radius } },
        { "RemoveVehiclesAroundPoint", { pos3, radius } },
        { "RemoveVehiclesAroundPoint", { pos4, radius } },
        { "RemoveVehiclesAroundPosition", { pos3, radius } },
        { "RemoveVehiclesAroundPosition", { pos4, radius } },
    }

    for _, call in ipairs(calls) do
        local method = system[call[1]]
        if method then
            local ok = pcall(function()
                method(system, table.unpack(call[2]))
            end)
            cleared = cleared or ok
        end
    end

    return cleared
end

local function _clearTrafficFromVehicleLists(lists, node, playerVehicle, radiusSq, seen)
    local cleared = 0
    for _, list in ipairs(lists or {}) do
        for _, candidate in ipairs(list) do
            local entityID = _extractEntityID(candidate)
            local candidateKey = entityID and tostring(entityID) or tostring(candidate)
            if not seen[candidateKey] then
                seen[candidateKey] = true

                local entity = candidate
                if entityID and (not entity or not entity.GetWorldPosition) then
                    pcall(function()
                        entity = Game.FindEntityByID(entityID)
                    end)
                end

                if entity and not _sameEntityID(entity, playerVehicle) then
                    local pos = nil
                    pcall(function()
                        pos = entity:GetWorldPosition()
                    end)
                    if pos then
                        local dx = (pos.x or 0) - (node.x or 0)
                        local dy = (pos.y or 0) - (node.y or 0)
                        local dz = (pos.z or 0) - (node.z or 0)
                        local distSq = (dx * dx) + (dy * dy)
                        if distSq <= radiusSq and math.abs(dz) <= TRAFFIC_CLEAR_VERTICAL_TOLERANCE then
                            _despawnAmbientEntity(entity)
                            cleared = cleared + 1
                        end
                    end
                end
            end
        end
    end
    return cleared
end

local function _clearAmbientTrafficAroundNode(node, radius)
    if not node then
        return 0
    end

    radius = tonumber(radius) or _tuningValue("trafficClearRadiusM", Racing._config)
    local radiusSq = radius * radius
    local playerVehicle = _getPlayerVehicle()
    local seen = {}
    local cleared = 0
    local directClearIssued = false
    local systems = {}

    pcall(function()
        table.insert(systems, Game.GetScriptableSystemsContainer():Get("VehicleSystem"))
    end)
    pcall(function()
        table.insert(systems, Game.GetScriptableSystemsContainer():Get("TrafficSystem"))
    end)

    for _, system in ipairs(systems) do
        if system then
            if _tryClearTrafficSystemArea(system, node, radius) then
                directClearIssued = true
            end
            cleared = cleared + _clearTrafficFromVehicleLists(_collectSystemVehicleLists(system), node, playerVehicle, radiusSq, seen)
        end
    end

    if cleared > 0 or directClearIssued then
        print(i18n.format("[NCM/Zone] Traffic clear pass: node=%s radius=%.0fm cleared=%d direct=%s",
            tostring(node.name or node.id or "?"),
            tonumber(radius or 0),
            tonumber(cleared or 0),
            tostring(directClearIssued)))
    end

    return cleared
end

local function _planarDot(ax, ay, bx, by)
    if type(ax) ~= "number" or type(ay) ~= "number" or type(bx) ~= "number" or type(by) ~= "number" then
        return nil
    end
    return (ax * bx) + (ay * by)
end

local function _headingAlignmentDot(heading, axisX, axisY)
    if type(heading) ~= "number" then
        return nil
    end
    local hx, hy = _normalizePlanarVector(math.cos(math.rad(heading)), math.sin(math.rad(heading)))
    if not hx or not hy then
        return nil
    end
    local dot = _planarDot(hx, hy, axisX, axisY)
    return dot and math.abs(dot) or nil
end

local function _measureRoutePathDeviation(route, nodeA, nodeB, routeDistanceM)
    local result = {
        sampleCount = 0,
        maxDeviationM = 0.0,
        avgDeviationM = 0.0,
    }
    if not nodeA or not nodeB then return result end

    local ax, ay = nodeA.x or 0, nodeA.y or 0
    local bx, by = nodeB.x or 0, nodeB.y or 0
    local dx = bx - ax
    local dy = by - ay
    local lenSq = (dx * dx) + (dy * dy)
    if lenSq < 0.001 then
        return result
    end
    local straightLineM = math.sqrt(lenSq)

    local points = route and route.pathPoints or nil
    if type(points) == "table" and #points > 2 then
        -- Use actual sampled path points
        local len = straightLineM
        local deviations = {}
        for index = 2, #points - 1 do
            local point = points[index]
            if point then
                local px = (point.x or 0) - ax
                local py = (point.y or 0) - ay
                local deviation = math.abs((px * dy) - (py * dx)) / len
                deviations[#deviations + 1] = deviation
            end
        end

        result.sampleCount = #deviations
        if result.sampleCount > 0 then
            table.sort(deviations)

            local edgeTrimCount = math.min(math.floor(result.sampleCount * 0.15), math.max(0, math.floor((result.sampleCount - 1) * 0.5)))
            local trimmedFirst = math.min(result.sampleCount, edgeTrimCount + 1)
            local trimmedLast = math.max(trimmedFirst, result.sampleCount - edgeTrimCount)
            local trimmedCount = 0
            local totalDeviation = 0.0

            for index = trimmedFirst, trimmedLast do
                totalDeviation = totalDeviation + (deviations[index] or 0.0)
                trimmedCount = trimmedCount + 1
            end

            if trimmedCount <= 0 then
                trimmedFirst = 1
                trimmedLast = result.sampleCount
                trimmedCount = result.sampleCount
                for _, deviation in ipairs(deviations) do
                    totalDeviation = totalDeviation + deviation
                end
            end

            local representativeMaxIndex = math.max(trimmedFirst, math.min(trimmedLast, math.ceil(result.sampleCount * 0.9)))
            result.maxDeviationM = deviations[representativeMaxIndex] or deviations[#deviations] or 0.0
            result.avgDeviationM = trimmedCount > 0 and (totalDeviation / trimmedCount) or 0.0
        end
    end

    -- Fallback: distance-ratio heuristic when no intermediate path points exist
    if result.sampleCount == 0 and tonumber(routeDistanceM) and routeDistanceM > 0 then
        local ratio = routeDistanceM / straightLineM
        -- ratio of 1.0 = perfectly straight; higher = curvier
        -- Convert to a synthetic deviation: excess distance implies lateral displacement
        -- For a single arc, deviation ≈ straightLine * sqrt(ratio^2 - 1) / 4
        if ratio > 1.001 then
            local syntheticDev = straightLineM * math.sqrt(ratio * ratio - 1) / 4.0
            result.sampleCount = 1       -- signals "estimated, not sampled"
            result.maxDeviationM = syntheticDev
            result.avgDeviationM = syntheticDev * 0.65
            result.estimatedFromDistanceRatio = true
        else
            -- Nearly perfectly straight
            result.sampleCount = 1
            result.maxDeviationM = 0.0
            result.avgDeviationM = 0.0
            result.estimatedFromDistanceRatio = true
        end
    end

    return result
end

local function _buildDragLaneOrder(totalSlots)
    local slotCount = math.max(2, math.floor(tonumber(totalSlots) or 2))
    local order = {}
    for gridPos = 3, slotCount do
        table.insert(order, gridPos)
    end
    table.insert(order, 1)
    table.insert(order, 2)

    local laneIndexByGridPos = {}
    for laneIndex, gridPos in ipairs(order) do
        laneIndexByGridPos[gridPos] = laneIndex
    end

    return order, laneIndexByGridPos
end

local _clamp01

local function _classifyDragStraightness(load)
    if load <= 0.001 then
        return "perfect"
    end
    if load <= 0.15 then
        return "tight"
    end
    if load <= 0.35 then
        return "clean"
    end
    if load <= 0.60 then
        return "bent"
    end
    return "crooked"
end

local function _computeDragStraightness(descriptor, config)
    local pathDeviation = descriptor and descriptor.pathDeviation or nil
    local maxPathDeviation = math.max(0.01, _tuningValue("dragRouteMaxPathDeviationM", config))
    local avgPathDeviation = math.max(0.01, _tuningValue("dragRouteAvgPathDeviationM", config))
    local penaltyMax = math.max(0.0, _tuningValue("dragStraightnessPenaltyMaxS", config))
    local penaltyExponent = math.max(1.0, _tuningValue("dragStraightnessPenaltyExponent", config))
    local maxLoad = 0.0
    local avgLoad = 0.0
    if pathDeviation and tonumber(pathDeviation.sampleCount or 0) > 0 then
        maxLoad = _clamp01((tonumber(pathDeviation.maxDeviationM) or 0.0) / maxPathDeviation)
        avgLoad = _clamp01((tonumber(pathDeviation.avgDeviationM) or 0.0) / avgPathDeviation)
    end

    local straightnessLoad = _clamp01((maxLoad * 0.65) + (avgLoad * 0.35))
    local penaltyLoad = straightnessLoad <= 0.0 and 0.0 or math.pow(straightnessLoad, penaltyExponent)
    local straightnessPenaltyS = penaltyMax * penaltyLoad
    local straightnessScore = math.max(0, math.min(100, math.floor(((1.0 - straightnessLoad) * 100.0) + 0.5)))

    return {
        load = straightnessLoad,
        penaltySeconds = straightnessPenaltyS,
        score = straightnessScore,
        class = _classifyDragStraightness(straightnessLoad),
        summary = i18n.format("STR %d  |  PEN +%.2fs", straightnessScore, straightnessPenaltyS),
    }
end

local function _getDragStripPenaltySeconds(config)
    local dragStrip = config and config.dragStrip or nil
    if tostring(config and config.raceType or "sprint") ~= "drag" or type(dragStrip) ~= "table" then
        return 0.0
    end
    return math.max(0.0, tonumber(dragStrip.straightnessPenaltyS) or 0.0)
end

local function _getDragOfficialTime(rawTime, config)
    local officialTime = tonumber(rawTime)
    if not officialTime then
        return rawTime
    end
    return officialTime + _getDragStripPenaltySeconds(config)
end

local function _estimateDragRoadWidth(config)
    local nodeA = config and config.nodeA or {}
    local explicitWidth = tonumber(config and config.estimatedRoadWidthM or nil)
        or tonumber(nodeA and (nodeA.roadWidthM or nodeA.startWidthM) or nil)
    if explicitWidth and explicitWidth > 0.0 then
        return explicitWidth, "explicit"
    end
    if nodeA and nodeA.road == false then
        return _tuningValue("dragDefaultMinRoadWidthM", config), "non_road_default"
    end
    if nodeA and nodeA.urban == false then
        return _tuningValue("dragDefaultOpenRoadWidthM", config), "open_road_default"
    end
    return _tuningValue("dragDefaultUrbanRoadWidthM", config), "urban_default"
end

local function _estimateSupportedDragLaneCount(estimatedRoadWidthM, laneCenterSpacingM)
    local width = tonumber(estimatedRoadWidthM) or 0.0
    local spacing = math.max(0.1, tonumber(laneCenterSpacingM) or _tuningValue("dragLaneCenterSpacingM", Racing._config))
    local lateralMargin = _tuningValue("dragLateralMarginM", Racing._config)
    local vehicleWidth = _tuningValue("dragGenericVehicleWidthM", Racing._config)
    local usableSpan = width - (lateralMargin * 2.0) - vehicleWidth
    if usableSpan < 0.0 then
        return 0
    end
    return math.max(1, math.floor(usableSpan / spacing) + 1)
end

local function _buildDragStripDescriptor(config, requestedFieldSize)
    local nodeA = config and config.nodeA or nil
    local nodeB = config and config.nodeB or nil
    local descriptor = {
        eligible = false,
        rejectReasonCode = nil,
        rejectReason = nil,
        validationMode = "geometry_only",
        requestedFieldSize = math.max(1, math.floor(tonumber(requestedFieldSize) or 1)),
        requestedLaneCount = math.max(2, math.floor(tonumber(requestedFieldSize) or 1) + 1),
        laneCenterSpacingM = _tuningValue("dragLaneCenterSpacingM", config),
        laneWidthM = _tuningValue("dragGenericVehicleWidthM", config) + (_tuningValue("dragLateralMarginM", config) * 2.0),
        lateralMarginM = _tuningValue("dragLateralMarginM", config),
        maxRouteGrade = _tuningValue("dragRouteMaxGrade", config),
        supportedLaneCount = 0,
        effectiveLaneCount = 0,
        adjustedFieldSize = 0,
        fieldSizeReduced = false,
        straightnessScore = 100,
        straightnessLoad = 0.0,
        straightnessClass = "perfect",
        straightnessPenaltyS = 0.0,
        straightnessSummary = "STR 100  |  PEN +0.00s",
        laneOrder = {},
        laneIndexByGridPos = {},
        laneOrderText = "",
    }

    local function reject(code, message)
        descriptor.eligible = false
        descriptor.rejectReasonCode = code
        descriptor.rejectReason = message
        return descriptor
    end

    if not nodeA or not nodeB then
        return reject("drag_route_missing", "Drag mode needs a valid start and finish strip.")
    end

    local dx = (nodeB.x or 0) - (nodeA.x or 0)
    local dy = (nodeB.y or 0) - (nodeA.y or 0)
    local dz = (nodeB.z or 0) - (nodeA.z or 0)
    local routeX, routeY = _normalizePlanarVector(dx, dy)
    if not routeX or not routeY then
        return reject("drag_strip_too_short", "Drag mode needs more separation between the start and finish nodes.")
    end

    local planarDistance = math.sqrt((dx * dx) + (dy * dy))
    local distanceM = tonumber(config and config.distance) or math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
    descriptor.distanceM = distanceM
    descriptor.routeGrade = planarDistance > 0.1 and math.abs(dz) / planarDistance or 0.0

    local minDistance = _tuningValue("dragRouteMinDistanceM", config)
    local maxDistance = _tuningValue("dragRouteMaxDistanceM", config)
    local maxGrade = _tuningValue("dragRouteMaxGrade", config)
    local maxPathDeviation = _tuningValue("dragRouteMaxPathDeviationM", config)
    local avgPathDeviation = _tuningValue("dragRouteAvgPathDeviationM", config)
    local minSupportedLanes = _tuningValue("dragMinSupportedLanes", config)
    local maxAiRivals = _tuningValue("dragMaxAiRivals", config)
    local minFinishWidth = _tuningValue("dragMinFinishWidthM", config)
    local finishWidthPerLane = _tuningValue("dragFinishWidthPerLaneM", config)

    if distanceM < minDistance then
        return reject("drag_distance_too_short", i18n.format("Drag mode needs at least %.0fm between start and finish.", minDistance))
    end
    if distanceM > maxDistance then
        return reject("drag_distance_too_long", i18n.format("Drag mode is limited to strips up to %.0fm.", maxDistance))
    end
    if nodeA.road == false or nodeB.road == false then
        return reject("drag_requires_road_nodes", "Drag mode requires road-aligned start and finish nodes.")
    end
    if descriptor.routeGrade > maxGrade then
        return reject("drag_strip_too_steep", i18n.format("Selected strip is too steep for drag (grade %.1f%%).", descriptor.routeGrade * 100.0))
    end

    descriptor.startHeadingAlignment = _headingAlignmentDot(nodeA.heading, routeX, routeY)
    descriptor.finishHeadingAlignment = _headingAlignmentDot(nodeB.finishHeading or nodeB.heading, routeX, routeY)

    descriptor.pathDeviation = _measureRoutePathDeviation(config and config.route or nil, nodeA, nodeB, distanceM)
    if descriptor.pathDeviation.sampleCount > 0 then
        descriptor.validationMode = descriptor.pathDeviation.estimatedFromDistanceRatio and "distance_ratio" or "sampled_path"
        local rawMaxLoad = (tonumber(descriptor.pathDeviation.maxDeviationM) or 0.0) / math.max(0.01, maxPathDeviation)
        local rawAvgLoad = (tonumber(descriptor.pathDeviation.avgDeviationM) or 0.0) / math.max(0.01, avgPathDeviation)
        local weightedRejectLoad = (rawMaxLoad * 0.65) + (rawAvgLoad * 0.35)
        local hardRejectLoad = math.max(1.0, _tuningValue("dragRouteHardRejectLoad", config, 1.2))
        if weightedRejectLoad > hardRejectLoad then
            return reject("drag_strip_not_straight", "Selected route bends too much for drag mode.")
        end
    end

    local estimatedRoadWidthM, roadWidthSource = _estimateDragRoadWidth(config)
    descriptor.estimatedRoadWidthM = estimatedRoadWidthM
    descriptor.estimatedRoadWidthSource = roadWidthSource
    descriptor.supportedLaneCount = _estimateSupportedDragLaneCount(estimatedRoadWidthM, descriptor.laneCenterSpacingM)
    if descriptor.supportedLaneCount < minSupportedLanes then
        return reject(
            "drag_strip_too_narrow",
            i18n.format("Estimated road width (%.1fm) only supports %d drag lane%s.",
                tonumber(estimatedRoadWidthM or 0.0),
                tonumber(descriptor.supportedLaneCount or 0),
                descriptor.supportedLaneCount == 1 and "" or "s"))
    end

    local laneCap = math.min(descriptor.supportedLaneCount, maxAiRivals + 1)
    descriptor.effectiveLaneCount = math.min(descriptor.requestedLaneCount, laneCap)
    descriptor.adjustedFieldSize = math.max(1, descriptor.effectiveLaneCount - 1)
    descriptor.fieldSizeReduced = descriptor.adjustedFieldSize < descriptor.requestedFieldSize
    descriptor.laneOrder, descriptor.laneIndexByGridPos = _buildDragLaneOrder(descriptor.effectiveLaneCount)
    descriptor.laneOrderText = i18n.concat(descriptor.laneOrder, "")
    descriptor.corridorWidthM = ((descriptor.effectiveLaneCount - 1) * descriptor.laneCenterSpacingM)
        + _tuningValue("dragGenericVehicleWidthM", config)
        + (descriptor.lateralMarginM * 2.0)
    descriptor.finishWidthM = math.max(minFinishWidth, descriptor.effectiveLaneCount * finishWidthPerLane)
    descriptor.corridorLengthM = distanceM
    descriptor.startSetbackM = 18.0
    local straightness = _computeDragStraightness(descriptor, config)
    descriptor.straightnessLoad = straightness.load
    descriptor.straightnessScore = straightness.score
    descriptor.straightnessClass = straightness.class
    descriptor.straightnessPenaltyS = straightness.penaltySeconds
    descriptor.straightnessSummary = straightness.summary
    descriptor.eligible = true
    return descriptor
end

local function _getGridForwardVector(fallbackHeading)
    local forward = nil
    local fallbackX, fallbackY = nil, nil
    if type(fallbackHeading) == "number" then
        local rad = math.rad(fallbackHeading)
        fallbackX, fallbackY = _normalizePlanarVector(math.cos(rad), math.sin(rad))
    end

    pcall(function()
        local target = _getPlayerVehicle() or Game.GetPlayer()
        if target and target.GetWorldForward then
            forward = target:GetWorldForward()
        end
    end)

    if forward then
        local fx, fy = nil, nil
        pcall(function()
            fx = forward.x or 0
            fy = forward.y or 0
        end)
        local nx, ny = _normalizePlanarVector(fx, fy)
        if nx and ny then
            if fallbackX and fallbackY then
                local dot = _planarDot(nx, ny, fallbackX, fallbackY)
                if dot and dot >= _tuningValue("gridForwardAlignmentDot", Racing._config) then
                    return { x = nx, y = ny }
                end
            else
                return { x = nx, y = ny }
            end
        end
    end

    if type(fallbackHeading) == "number" then
        local rad = math.rad(fallbackHeading)
        return { x = math.cos(rad), y = math.sin(rad) }
    end

    return nil
end

local function _findNodeById(nodeId)
    local pool = MTE and MTE.Nodes or {}
    for _, node in ipairs(pool) do
        if node.id == nodeId then
            return node
        end
    end
    return nil
end

local function _getPlayerVehicleSpeedMps()
    local speed = 0.0
    pcall(function()
        local p = Game.GetPlayer()
        if not p then return end
        speed = VehicleComponent.GetOwnerVehicleSpeed(p:GetGame(), p) or 0.0
    end)
    return speed
end

local function _isPlayerSlowEnoughToStage()
    return _getPlayerVehicleSpeedMps() <= _tuningValue("startSnapMaxSpeedMps", Racing._config)
end

local function _isRollingStart(config)
    local cfg = config or Racing._config or {}
    return tostring(cfg.startType or "grid") == "rolling"
end

local function _isSideBySideStart(config)
    local cfg = config or Racing._config or {}
    return tostring(cfg.startType or "grid") == "sidebyside"
end

local function _getRaceCountdownSeconds(config)
    local cfg = config or Racing._config or {}
    if _isRollingStart(cfg) then
        return _tuningValue("rollingCountdownSeconds", cfg)
    end
    if _isSideBySideStart(cfg) and tostring(cfg.raceType or "sprint") == "drag" then
        return _tuningValue("dragCountdownSeconds", cfg)
    end
    return 3.0
end

local function _countdownUsesLights(config)
    return not _isRollingStart(config)
end

local function _canAdvanceRacePhase()
    return not _timePaused()
end

local function _checkPlayerStartReadiness(mode)
    local cfg = Racing._config or {}
    local nodeA = cfg.nodeA
    local action = mode == "quali" and "qualifying" or "the race"
    local snapEnabled = _playerGridSnapEnabled()
    if not nodeA then
        return false, "No race start is configured."
    end
    if not _getPlayerVehicle() then
        return false, i18n.format("Get in your vehicle before starting %s.", action)
    end
    local dist = Racing._distToNode(nodeA)
    local captureRadius = _tuningValue("startCaptureRadiusM", cfg)
    local readyRadius = _tuningValue("startReadyRadiusM", cfg)
    if dist and dist <= captureRadius and not _isPlayerSlowEnoughToStage() then
        if dist <= readyRadius then
            if mode == "quali" then
                return false, "Slow down and hold the start line before beginning qualifying."
            end
            return false, snapEnabled
                and "Slow down and hold the start line before launching."
                or "Slow down and hold your grid spot before launching."
        end
        if mode == "quali" then
            return false, snapEnabled
                and "Slow down near the start marker and the mod will line V up for qualifying."
                or "Slow down and drive into the qualifying start spot."
        end
        return false, snapEnabled
            and "Slow down near the start marker and the mod will line V up on the grid."
            or "Slow down and drive into your grid spot."
    end
    if not dist or dist > readyRadius then
        if dist and dist <= captureRadius then
            if mode == "quali" then
                return false, snapEnabled
                    and "Get a little closer to the start marker and the mod will line V up for qualifying."
                    or "Drive a little deeper into the qualifying start spot."
            end
            return false, snapEnabled
                and "Get a little closer to the start marker and the mod will line V up on the grid."
                or "Drive a little deeper into your grid spot."
        end
        if mode == "quali" then
            return false, "Drive to the race start before starting qualifying."
        end
        return false, "Drive to the race start before launching."
    end
    if not _canAdvanceRacePhase() then
        return false, i18n.format("Unpause before starting %s.", action)
    end
    return true, nil
end

function Racing._isPlayerReadyForQuali()
    if not Racing._config or not Racing._config.nodeA then
        return false, "No qualifying start is configured."
    end
    return _checkPlayerStartReadiness("quali")
end

function Racing._isPlayerReadyForRaceStart()
    return _checkPlayerStartReadiness("race")
end

function Racing.isPlayerGridSnapEnabled()
    return _playerGridSnapEnabled()
end

function Racing.getStartReadiness()
    return Racing._isPlayerReadyForRaceStart()
end

function Racing.isVisibleFieldDeferred()
    if not LIVE_RIVALS_POST_START then
        return false
    end
    if Racing._state ~= Racing.STATE.PRERACE then
        return false
    end
    if not Racing._postStartLiveSpawnPending or Racing._gridSpawnPending then
        return false
    end
    if MTE.AIVehicles and MTE.AIVehicles.isActive and MTE.AIVehicles.isActive() then
        return false
    end
    return true
end

function Racing.isGridSpawnPending()
    return Racing._gridSpawnPending == true
end

function Racing._queueGridSpawn()
    if LIVE_RIVALS_POST_START then
        Racing._ensureSpawnRunId()
        Racing._gridSpawnPending = false
        Racing._postStartLiveSpawnPending = true
        Racing._postStartLiveSpawnTimer = 0.0
        Racing._postStartLiveSpawnReason = "armed_post_start"
        Racing._resetGridSpawnWindow("post_start_live_spawn")
        Racing._logSpawnRunMarker("armed_post_start", "post_start_live_rivals", { source = "queue_grid" })
        print("[NCM/Racing] Visible rivals armed for post-start spawn.")
        return
    end
    Racing._ensureSpawnRunId()
    Racing._gridSpawnPending = true
    Racing._resetGridSpawnWindow("queued")
    Racing._logSpawnRunMarker("queued_grid", "prerace_grid", { source = "queue_grid" })
end

function Racing._resetGridSpawnWindow(reason)
    Racing._gridSpawnStableTicks = 0
    Racing._gridSpawnStableTime  = 0.0
    Racing._gridSpawnGateReason  = reason
    Racing._gridReadyBlockerReason = nil
end

function Racing._resetPostStartLiveSpawn(reason)
    Racing._postStartLiveSpawnPending = false
    Racing._postStartLiveSpawnTimer = 0.0
    Racing._postStartLiveSpawnReason = reason
end

function Racing._resetGhostFallback(reason)
    Racing._postStartSpawnRequested = false
    Racing._ghostFallbackActive = false
    Racing._ghostFallbackReason = reason
end

function Racing._enableGhostFallback(reason)
    local why = reason or "ghost_fallback"
    if Racing._ghostFallbackActive and Racing._ghostFallbackReason == why then
        return false
    end
    Racing._ghostFallbackActive = true
    Racing._ghostFallbackReason = why
    print(i18n.format("[NCM/Racing] Ghost fallback active: %s", tostring(why)))
    _notify("Visible rivals unavailable - ghost timing fallback active.", 2.6)
    return true
end

function Racing._isGhostFallbackActive()
    return Racing._ghostFallbackActive == true
end

function Racing._getVisibleFieldIdSet()
    local ids = {}
    if not (MTE.AIVehicles and MTE.AIVehicles.getLiveDrivers) then
        return ids
    end
    local liveDrivers = MTE.AIVehicles.getLiveDrivers() or {}
    local requireActive = LIVE_RIVALS_POST_START and not Racing._ghostFallbackActive
    for _, ld in ipairs(liveDrivers) do
        local id = ld and ld.id or nil
        if id and (not requireActive or ld.isActive) then
            ids[id] = true
        end
    end
    return ids
end

function Racing._getScoredField()
    if Racing._ghostFallbackActive then
        return Racing._field or {}, nil
    end
    local ids = Racing._getVisibleFieldIdSet()
    local visible = {}
    for _, entry in ipairs(Racing._field or {}) do
        local id = entry.driverId or entry.id
        if id and ids[id] then
            table.insert(visible, entry)
        end
    end
    if #visible > 0 then
        return visible, ids
    end
    if not LIVE_RIVALS_POST_START then
        return Racing._field or {}, nil
    end
    return Racing._field or {}, nil
end

function Racing._getEntryFinishTime(entry, visibleIds)
    local id = entry and (entry.driverId or entry.id) or nil
    if id and Racing._aiFinishTime[id] then
        return Racing._aiFinishTime[id]
    end
    if visibleIds and id and visibleIds[id] then
        return nil
    end
    return entry and entry.aiTime or nil
end

local function _rememberLiveStanding(standing)
    if type(standing) ~= "table" or standing.isPlayer then
        return
    end
    local id = standing.driverId or standing.id
    if not id then
        return
    end
    Racing._lastKnownStandingByDriverId[id] = {
        driverId = id,
        finished = standing.finished == true,
        time = tonumber(standing.time) or nil,
        progress = tonumber(standing.progress) or nil,
        distanceAlong = tonumber(standing.distanceAlong) or nil,
        remainingDistance = tonumber(standing.remainingDistance or standing.distToFinish) or nil,
        distToFinish = tonumber(standing.distToFinish or standing.remainingDistance) or nil,
        speed = tonumber(standing.speed) or nil,
        provenance = standing.provenance,
    }
end

local function _rememberLiveStandings(standings)
    for _, standing in ipairs(standings or {}) do
        _rememberLiveStanding(standing)
    end
end

_clamp01 = function(value)
    if type(value) ~= "number" then return 0.0 end
    if value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function _clampRange(value, minValue, maxValue)
    value = tonumber(value) or 0.0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function _smoothScale(value, factor, minValue, maxValue)
    local scale = tonumber(value) or 1.0
    local blend = _clampRange(tonumber(factor) or 1.0, 0.0, 1.0)
    local smoothed = 1.0 + ((scale - 1.0) * blend)
    if minValue ~= nil and maxValue ~= nil then
        return _clampRange(smoothed, minValue, maxValue)
    end
    return smoothed
end

local COMPETITIVE_TIER_STAT_FLOORS = {
    Gonk = {
        base_pace = 1.02,
        max_attack_pace = 1.10,
        aggression = 0.56,
        precision = 0.60,
        consistency = 0.61,
        racecraft = 0.60,
        launch_skill = 0.59,
        race_start_composure = 0.59,
        composure = 0.60,
        awareness = 0.59,
        throttle_control = 0.60,
        braking_control = 0.60,
        cornering_confidence = 0.60,
        lane_discipline = 0.58,
    },
    Streetkid = {
        base_pace = 1.08,
        max_attack_pace = 1.18,
        aggression = 0.62,
        precision = 0.66,
        consistency = 0.67,
        racecraft = 0.67,
        launch_skill = 0.65,
        race_start_composure = 0.65,
        composure = 0.66,
        awareness = 0.65,
        throttle_control = 0.66,
        braking_control = 0.66,
        cornering_confidence = 0.66,
        lane_discipline = 0.62,
    },
    Solo = {
        base_pace = 1.14,
        max_attack_pace = 1.26,
        aggression = 0.70,
        precision = 0.73,
        consistency = 0.74,
        racecraft = 0.75,
        launch_skill = 0.73,
        race_start_composure = 0.72,
        composure = 0.73,
        awareness = 0.72,
        throttle_control = 0.73,
        braking_control = 0.73,
        cornering_confidence = 0.74,
        lane_discipline = 0.66,
    },
    Fixer = {
        base_pace = 1.20,
        max_attack_pace = 1.34,
        aggression = 0.78,
        precision = 0.80,
        consistency = 0.81,
        racecraft = 0.82,
        launch_skill = 0.80,
        race_start_composure = 0.79,
        composure = 0.80,
        awareness = 0.79,
        throttle_control = 0.80,
        braking_control = 0.80,
        cornering_confidence = 0.81,
        lane_discipline = 0.72,
    },
    Edgerunner = {
        base_pace = 1.28,
        max_attack_pace = 1.42,
        aggression = 0.86,
        precision = 0.88,
        consistency = 0.89,
        racecraft = 0.90,
        launch_skill = 0.88,
        race_start_composure = 0.87,
        composure = 0.88,
        awareness = 0.87,
        throttle_control = 0.88,
        braking_control = 0.88,
        cornering_confidence = 0.89,
        lane_discipline = 0.78,
    },
}

local function _getCompetitiveTierStatFloor(driver, key)
    if type(driver) ~= "table" or type(key) ~= "string" then
        return nil
    end
    local tier = driver.currentTier or driver.tier or (type(driver.driver) == "table" and (driver.driver.currentTier or driver.driver.tier)) or nil
    local tierFloors = COMPETITIVE_TIER_STAT_FLOORS[tostring(tier or "")]
    return tierFloors and tierFloors[key] or nil
end

local function _getDriverStatValue(driver, key, fallback)
    if type(driver) ~= "table" then return fallback end

    local value = nil
    if type(driver.driverStats) == "table" then
        value = driver.driverStats[key]
    end
    if value == nil and type(driver.driver) == "table" and type(driver.driver.driverStats) == "table" then
        value = driver.driver.driverStats[key]
    end
    if value == nil then
        value = driver[key]
    end
    if value == nil and type(driver.driver) == "table" then
        value = driver.driver[key]
    end
    local floor = _getCompetitiveTierStatFloor(driver, key)
    if value == nil then
        if floor ~= nil then
            local fallbackNumber = tonumber(fallback)
            if fallbackNumber ~= nil then
                return math.max(fallbackNumber, floor)
            end
            return floor
        end
        return fallback
    end
    if floor ~= nil then
        local valueNumber = tonumber(value)
        if valueNumber ~= nil then
            return math.max(valueNumber, floor)
        end
    end
    return value
end

local function _getDriverHardwareSummary(driver)
    local parts = MTE and MTE.Parts or nil
    if parts and parts.getDriverHardwareSummary then
        return parts.getDriverHardwareSummary(driver)
    end
    return {
        rating = 0,
        slotCount = 0,
        sprintScale = 1.0,
        dragScale = 1.0,
        knockoutScale = 1.0,
        liveSpeedScale = 1.0,
        launchScale = 1.0,
        controlScale = 1.0,
        reliabilityScale = 1.0,
        confidence = 1.0,
    }
end

local function _getDriverDisciplineHardwareScale(driver, config)
    local hardware = _getDriverHardwareSummary(driver)
    local discipline = tostring(config and config.raceType or "sprint")
    if discipline == "drag" then
        return _smoothScale(hardware.dragScale or 1.0, 0.62, 0.94, 1.16), hardware
    end
    if discipline == "knockout" then
        return _smoothScale(hardware.knockoutScale or 1.0, 0.62, 0.94, 1.16), hardware
    end
    return _smoothScale(hardware.sprintScale or 1.0, 0.62, 0.94, 1.16), hardware
end

local function _getDriverSignedState(driver, key)
    return _clampRange(_getDriverStatValue(driver, key, 0.0), -1.0, 1.0)
end

local function _hasPersonalityHint(driver, hint)
    local personality = string.lower(tostring(driver and driver.personality or ""))
    return string.find(personality, hint, 1, true) ~= nil
end

local function _getDriverRaceUrgencyScale(driver, config)
    local aggression = _clamp01(_getDriverStatValue(driver, "aggression", driver and driver.aggression or 0.5))
    local racecraft = _clamp01(_getDriverStatValue(driver, "racecraft", 0.5))
    local riskTolerance = _clamp01(_getDriverStatValue(driver, "risk_tolerance", 0.5))
    local awareness = _clamp01(_getDriverStatValue(driver, "awareness", 0.5))
    local corneringConfidence = _clamp01(_getDriverStatValue(driver, "cornering_confidence", 0.5))
    local launchSkill = _clamp01(_getDriverStatValue(driver, "launch_skill", 0.5))
    local fear = _clamp01(_getDriverStatValue(driver, "fear", 0.5))
    local racePaceBias = _clampRange(_getDriverStatValue(driver, "race_pace_bias", 0.0), -0.25, 0.25)
    local momentum = math.max(0.0, _getDriverSignedState(driver, "momentum"))
    local form = math.max(0.0, _getDriverSignedState(driver, "form"))
    local disciplineAffinity = tostring(config and config.raceType or "sprint") == "drag"
        and _clamp01(_getDriverStatValue(driver, "discipline_drag", 0.5))
        or (tostring(config and config.raceType or "sprint") == "knockout"
            and _clamp01(_getDriverStatValue(driver, "discipline_knockout", 0.5))
            or _clamp01(_getDriverStatValue(driver, "discipline_sprint", 0.5)))
    local vehicleConfidence = _clampRange(_getDriverHardwareSummary(driver).confidence or 1.0, 0.90, 1.10)
    local urgency = 0.95
        + aggression * 0.16
        + racecraft * 0.08
        + riskTolerance * 0.06
        + awareness * 0.04
        + corneringConfidence * 0.04
        + launchSkill * 0.03
        + disciplineAffinity * 0.04
        + momentum * 0.08
        + form * 0.06
        + ((vehicleConfidence - 1.0) * 0.22)
        + racePaceBias

    if _hasPersonalityHint(driver, "aggressive") or _hasPersonalityHint(driver, "closer") then
        urgency = urgency + 0.12
    end
    if _hasPersonalityHint(driver, "risk") or _hasPersonalityHint(driver, "dirty") then
        urgency = urgency + 0.08
    end
    if _hasPersonalityHint(driver, "street smart") or _hasPersonalityHint(driver, "ice cold") then
        urgency = urgency + 0.04
    end
    if _hasPersonalityHint(driver, "slow starter") then
        urgency = urgency - 0.04
    end
    if driver and ((driver.rivalScore or 0) > 0 or driver.isRival) then
        urgency = urgency + 0.08
    end
    if Racing._career and MTE and MTE.Careers and MTE.Careers.isBountyEscalated and MTE.Careers.isBountyEscalated(Racing._career, driver and driver.id) then
        urgency = urgency + 0.10
    end

    urgency = urgency - fear * 0.04

    return _smoothScale(urgency, 0.58, 0.97, 1.30)
end

local function _getDriverProjectedPerformanceScale(driver, config)
    local throttleControl = _clamp01(_getDriverStatValue(driver, "throttle_control", 0.5))
    local brakingControl = _clamp01(_getDriverStatValue(driver, "braking_control", 0.5))
    local corneringConfidence = _clamp01(_getDriverStatValue(driver, "cornering_confidence", 0.5))
    local racecraft = _clamp01(_getDriverStatValue(driver, "racecraft", 0.5))
    local adaptability = _clamp01(_getDriverStatValue(driver, "adaptability", 0.5))
    local momentum = math.max(0.0, _getDriverSignedState(driver, "momentum"))
    local form = math.max(0.0, _getDriverSignedState(driver, "form"))
    local disciplineAffinity = tostring(config and config.raceType or "sprint") == "drag"
        and _clamp01(_getDriverStatValue(driver, "discipline_drag", 0.5))
        or (tostring(config and config.raceType or "sprint") == "knockout"
            and _clamp01(_getDriverStatValue(driver, "discipline_knockout", 0.5))
            or _clamp01(_getDriverStatValue(driver, "discipline_sprint", 0.5)))
    local disciplineHardwareScale = _getDriverDisciplineHardwareScale(driver, config)
    local scale = 0.98
        + throttleControl * 0.08
        + brakingControl * 0.06
        + corneringConfidence * 0.08
        + racecraft * 0.10
        + adaptability * 0.04
        + disciplineAffinity * 0.06
        + momentum * 0.06
        + form * 0.05
    scale = scale * disciplineHardwareScale
    return _smoothScale(scale, 0.60, 0.94, 1.20)
end

local function _buildAIRaceContext(config)
    local cfg = config or Racing._config or {}
    local discipline = tostring(cfg.raceType or "sprint")
    local competitiveBoost = 27.6
    local playerFocus = 0.32
    if discipline == "drag" then
        competitiveBoost = 27.7
        playerFocus = 0.12
    elseif discipline == "knockout" then
        competitiveBoost = 27.65
        playerFocus = 0.26
    end
    return {
        raceActive = true,
        competitiveMode = true,
        discipline = discipline,
        startType = tostring(cfg.startType or "grid"),
        ignoreTraffic = true,
        competitiveBoost = competitiveBoost,
        playerFocus = playerFocus,
        rootProfileSettings = cfg.rootProfileSettings,
    }
end

local function _getRollingPlayerGridPos()
    local fieldSize = #(Racing._field or {})
    return _clampRange(tonumber(Racing._qualiGridPos) or 1, 1, math.max(1, fieldSize + 1))
end

local function _getRollingPoleEntry()
    local playerGridPos = _getRollingPlayerGridPos()
    if playerGridPos == 1 then
        return nil, true
    end
    for _, entry in ipairs(Racing._field or {}) do
        if tonumber(entry and entry.gridPos or 0) == 1 then
            return entry, false
        end
    end
    return (Racing._field or {})[1], false
end

function Racing._resetRollingStartState(reason)
    local why = reason or "rolling_reset"
    local wasActive = Racing._rollingZoneActive or Racing._rollingWarmupArmed

    if MTE and MTE.AIVehicles then
        if Racing._rollingZoneActive and MTE.AIVehicles.releaseRollingStart then
            MTE.AIVehicles.releaseRollingStart(why)
        elseif MTE.AIVehicles.armRollingWarmup then
            MTE.AIVehicles.armRollingWarmup({ active = false, reason = why })
        end
    end

    Racing._rollingZoneActive = false
    Racing._rollingZoneReason = why
    Racing._rollingZoneStartProgress = nil
    Racing._rollingZoneLength = _tuningValue("rollingZoneLengthM", Racing._config)
    Racing._rollingLeaderProgress = 0.0
    Racing._rollingTargetPaceMin = nil
    Racing._rollingTargetPaceMax = nil
    Racing._rollingTargetPace = nil
    Racing._rollingLeaderIsPlayer = false
    Racing._rollingWarmupArmed = false
    Racing._rollingPlayerViolation = nil
    Racing._rollingPlayerViolationAt = nil
    Racing._rollingPlayerWarningTimer = 0.0

    if wasActive then
        print(i18n.format("[NCM/Racing] Rolling start reset: %s", tostring(why)))
    end
end

function Racing._computeRollingPaceBand()
    local targetPace = _tuningValue("rollingPaceBaseMps", Racing._config)
    local paceFloor = _tuningValue("rollingPaceMinFloorMps", Racing._config)
    local paceCeil = _tuningValue("rollingPaceMaxCeilMps", Racing._config)
    local poleEntry, playerOnPole = _getRollingPoleEntry()

    if poleEntry and not playerOnPole then
        local urgency = _getDriverRaceUrgencyScale(poleEntry, Racing._config)
        local projected = _getDriverProjectedPerformanceScale(poleEntry, Racing._config)
        local paceScale = _clampRange(
            0.96 + ((urgency - 1.0) * 0.35) + ((projected - 1.0) * 0.45),
            0.88,
            1.16)
        targetPace = _clampRange(targetPace * paceScale, paceFloor, paceCeil)
    end

    local minPace = _clampRange(targetPace - 1.2, paceFloor, paceCeil)
    local maxPace = _clampRange(targetPace + 1.6, minPace, paceCeil)
    return minPace, maxPace, targetPace, playerOnPole
end

function Racing._buildRollingControl(reason, elapsed)
    local cfg = Racing._config or {}
    local gridHeading = _getResolvedGridHeading(cfg.nodeA, cfg.nodeB, cfg)
    return {
        active = true,
        reason = reason or Racing._rollingZoneReason or "rolling_zone",
        startNode = cfg.nodeA,
        finishNode = cfg.nodeB,
        gridHeading = gridHeading,
        gridForward = _getGridForwardVector(gridHeading),
        gridLateralShiftM = _tuningValue("gridLateralShiftM", cfg, 0.0),
        zoneLength = Racing._rollingZoneLength or _tuningValue("rollingZoneLengthM", cfg),
        leaderProgress = Racing._rollingLeaderProgress or 0.0,
        elapsed = elapsed or 0.0,
        targetPaceMps = Racing._rollingTargetPace or _tuningValue("rollingPaceBaseMps", cfg),
        targetPaceMinMps = Racing._rollingTargetPaceMin or _tuningValue("rollingPaceMinFloorMps", cfg),
        targetPaceMaxMps = Racing._rollingTargetPaceMax or _tuningValue("rollingPaceMaxCeilMps", cfg),
        playerGridPos = _getRollingPlayerGridPos(),
        leaderIsPlayer = Racing._rollingLeaderIsPlayer == true,
        startProgress = Racing._rollingZoneStartProgress,
    }
end

function Racing._armRollingStartWarmup(reason)
    if not _isRollingStart(Racing._config) then
        return false
    end
    if Racing._rollingZoneActive or Racing._rollingWarmupArmed then
        return true
    end
    if not (MTE and MTE.AIVehicles and MTE.AIVehicles.armRollingWarmup) then
        return false
    end

    local paceMin, paceMax, targetPace, leaderIsPlayer = Racing._computeRollingPaceBand()
    Racing._rollingTargetPaceMin = paceMin
    Racing._rollingTargetPaceMax = paceMax
    Racing._rollingTargetPace = targetPace
    Racing._rollingLeaderIsPlayer = leaderIsPlayer
    Racing._rollingWarmupArmed = true
    Racing._rollingZoneReason = reason or "rolling_warmup"
    Racing._rollingLeaderProgress = 0.0
    MTE.AIVehicles.armRollingWarmup(Racing._buildRollingControl(reason or "rolling_warmup", 0.0))
    print(i18n.format(
        "[NCM/Racing] Rolling warmup armed: pace=%.1f band=%.1f-%.1f playerPole=%s",
        tonumber(targetPace or 0.0),
        tonumber(paceMin or 0.0),
        tonumber(paceMax or 0.0),
        tostring(leaderIsPlayer)))
    return true
end

function Racing._beginRollingStartZone(reason)
    if not _isRollingStart(Racing._config) then
        return false
    end
    if Racing._rollingZoneActive then
        return true
    end

    local playerProgress = Racing.getPlayerRouteProgress()
    local startProgress = playerProgress and playerProgress.distanceAlong or 0.0
    local paceMin = Racing._rollingTargetPaceMin
    local paceMax = Racing._rollingTargetPaceMax
    local targetPace = Racing._rollingTargetPace
    local leaderIsPlayer = Racing._rollingLeaderIsPlayer
    if not paceMin or not paceMax or not targetPace then
        paceMin, paceMax, targetPace, leaderIsPlayer = Racing._computeRollingPaceBand()
    end

    Racing._rollingZoneActive = true
    Racing._rollingZoneReason = reason or "rolling_zone_begin"
    Racing._rollingZoneStartProgress = startProgress
    Racing._rollingZoneLength = _tuningValue("rollingZoneLengthM", Racing._config)
    Racing._rollingLeaderProgress = 0.0
    Racing._rollingTargetPaceMin = paceMin
    Racing._rollingTargetPaceMax = paceMax
    Racing._rollingTargetPace = targetPace
    Racing._rollingLeaderIsPlayer = leaderIsPlayer == true
    Racing._rollingWarmupArmed = false
    Racing._rollingPlayerViolation = nil
    Racing._rollingPlayerViolationAt = nil
    Racing._rollingPlayerWarningTimer = 0.0

    if MTE and MTE.AIVehicles and MTE.AIVehicles.beginRollingStart then
        MTE.AIVehicles.beginRollingStart(Racing._buildRollingControl(reason or "rolling_zone_begin", 0.0))
    end

    print(i18n.format(
        "[NCM/Racing] Rolling zone begin: startProgress=%.1f length=%.1f pace=%.1f band=%.1f-%.1f leaderIsPlayer=%s",
        tonumber(startProgress or 0.0),
        tonumber(Racing._rollingZoneLength or 0.0),
        tonumber(targetPace or 0.0),
        tonumber(paceMin or 0.0),
        tonumber(paceMax or 0.0),
        tostring(Racing._rollingLeaderIsPlayer)))
    return true
end

function Racing._releaseRollingStartZone(reason)
    if not (Racing._rollingZoneActive or Racing._rollingWarmupArmed) then
        return false
    end

    local elapsed = math.max(0.0, (Racing._raceTimer or 0.0))
    local leaderProgress = tonumber(Racing._rollingLeaderProgress or 0.0) or 0.0
    local violation = Racing._rollingPlayerViolation

    if MTE and MTE.AIVehicles then
        if Racing._rollingZoneActive and MTE.AIVehicles.releaseRollingStart then
            MTE.AIVehicles.releaseRollingStart(reason or "rolling_zone_end")
        elseif MTE.AIVehicles.armRollingWarmup then
            MTE.AIVehicles.armRollingWarmup({ active = false, reason = reason or "rolling_zone_end" })
        end
    end

    Racing._rollingZoneActive = false
    Racing._rollingZoneReason = reason or "rolling_zone_end"
    Racing._rollingWarmupArmed = false
    Racing._rollingZoneStartProgress = nil
    Racing._rollingLeaderProgress = 0.0
    Racing._rollingPlayerViolation = nil
    Racing._rollingPlayerViolationAt = nil
    Racing._rollingPlayerWarningTimer = 0.0

    print(i18n.format(
        "[NCM/Racing] Rolling zone release: reason=%s elapsed=%.2f leaderProgress=%.1f violation=%s",
        tostring(reason or "rolling_zone_end"),
        tonumber(elapsed or 0.0),
        tonumber(leaderProgress or 0.0),
        tostring(violation or "none")))
    return true
end

function Racing._setRollingPlayerViolation(code, message)
    local changed = Racing._rollingPlayerViolation ~= code
    if changed then
        Racing._rollingPlayerViolation = code
        Racing._rollingPlayerViolationAt = Racing._raceTimer or 0.0
        Racing._rollingPlayerWarningTimer = 0.0
        print(i18n.format("[NCM/Racing] Rolling violation: %s", tostring(code)))
    end

    if (Racing._rollingPlayerWarningTimer or 0.0) <= 0.0 then
        _notify(message, 1.2)
        Racing._rollingPlayerWarningTimer = _tuningValue("rollingPlayerWarningIntervalS", Racing._config)
    end
end

function Racing._clearRollingPlayerViolation(reason)
    if Racing._rollingPlayerViolation then
        print(i18n.format(
            "[NCM/Racing] Rolling violation cleared: %s (%s)",
            tostring(Racing._rollingPlayerViolation),
            tostring(reason or "cleared")))
    end
    Racing._rollingPlayerViolation = nil
    Racing._rollingPlayerViolationAt = nil
    Racing._rollingPlayerWarningTimer = 0.0
end

function Racing._updateRollingStartZone(dt)
    if not Racing._rollingZoneActive then
        return false
    end

    local zoneLength = tonumber(Racing._rollingZoneLength or _tuningValue("rollingZoneLengthM", Racing._config)) or _tuningValue("rollingZoneLengthM", Racing._config)
    local startProgress = tonumber(Racing._rollingZoneStartProgress or 0.0) or 0.0
    local elapsed = math.max(0.0, Racing._raceTimer or 0.0)
    local playerProgress = Racing.getPlayerRouteProgress()
    local playerDistance = 0.0
    if playerProgress then
        playerDistance = math.max(0.0, (playerProgress.distanceAlong or 0.0) - startProgress)
    end

    local progressByDriverId = {}
    local poleAIDistance = nil
    if MTE and MTE.AIVehicles and MTE.AIVehicles.getLiveDrivers then
        for _, liveDriver in ipairs(MTE.AIVehicles.getLiveDrivers() or {}) do
            if liveDriver and liveDriver.id and liveDriver.position then
                local progress = computeProgressFromPosition(liveDriver.position)
                if progress then
                    local distanceAlong = math.max(0.0, (progress.distanceAlong or 0.0) - startProgress)
                    progressByDriverId[liveDriver.id] = {
                        progress = progress,
                        gridOrdinal = tonumber(liveDriver.gridOrdinal or 0) or 0,
                        distanceAlong = distanceAlong,
                    }
                    if tonumber(liveDriver.gridOrdinal or 0) == 1 then
                        poleAIDistance = distanceAlong
                    end
                end
            end
        end
    end

    if Racing._rollingLeaderIsPlayer then
        local playerSpeed = _getPlayerVehicleSpeedMps()
        if playerSpeed and playerSpeed > 0.1 then
            Racing._rollingTargetPace = _clampRange(
                playerSpeed,
                Racing._rollingTargetPaceMin or _tuningValue("rollingPaceMinFloorMps", Racing._config),
                Racing._rollingTargetPaceMax or _tuningValue("rollingPaceMaxCeilMps", Racing._config))
        end
    end

    local fallbackProgress = math.min(zoneLength, elapsed * (Racing._rollingTargetPace or _tuningValue("rollingPaceBaseMps", Racing._config)))
    local leaderProgress = Racing._rollingLeaderIsPlayer and playerDistance or poleAIDistance
    if type(leaderProgress) ~= "number" then
        leaderProgress = fallbackProgress
    end
    leaderProgress = math.min(leaderProgress, math.min(zoneLength, elapsed * (Racing._rollingTargetPaceMax or _tuningValue("rollingPaceMaxCeilMps", Racing._config))))
    Racing._rollingLeaderProgress = math.max(Racing._rollingLeaderProgress or 0.0, leaderProgress)

    if (Racing._rollingPlayerWarningTimer or 0.0) > 0.0 then
        Racing._rollingPlayerWarningTimer = math.max(0.0, (Racing._rollingPlayerWarningTimer or 0.0) - (dt or 0.0))
    end

    local playerGridPos = _getRollingPlayerGridPos()
    local progressGrace = _tuningValue("rollingPlayerProgressGraceM", Racing._config)
    local paceViolation = playerDistance > ((Racing._rollingLeaderProgress or 0.0) + progressGrace)
    local orderViolation = false
    if not paceViolation and playerGridPos > 1 then
        for _, driverProgress in pairs(progressByDriverId) do
            if (driverProgress.gridOrdinal or 0) > 0 and (driverProgress.gridOrdinal or 0) < playerGridPos then
                if playerDistance > ((driverProgress.distanceAlong or 0.0) + progressGrace) then
                    orderViolation = true
                    break
                end
            end
        end
    end

    if orderViolation then
        Racing._setRollingPlayerViolation("order_ahead", "No pass before green - give the position back.")
    elseif paceViolation then
        Racing._setRollingPlayerViolation("pace_ahead", "Hold formation - drop back into the rolling pace window.")
    else
        Racing._clearRollingPlayerViolation("player_back_in_window")
    end

    if MTE and MTE.AIVehicles and MTE.AIVehicles.updateRollingStart then
        MTE.AIVehicles.updateRollingStart(Racing._buildRollingControl("rolling_zone_tick", elapsed))
    end

    if (Racing._rollingLeaderProgress or 0.0) >= zoneLength then
        Racing._releaseRollingStartZone("zone_complete")
        return false
    end

    return true
end

local function _armNearFinishDNFGrace()
    if Racing._nearFinishDNFGraceArmed then
        return
    end
    local remainingDistance = Racing.getDistanceToFinish and Racing.getDistanceToFinish() or nil
    local nearFinishDistance = _tuningValue("dnfNearFinishDistanceM", Racing._config)
    if type(remainingDistance) ~= "number" or remainingDistance > nearFinishDistance then
        return
    end
    Racing._nearFinishDNFGraceArmed = true
    Racing._nearFinishDNFGraceUntil = (Racing._raceTimer or 0.0) + _tuningValue("dnfNearFinishGraceS", Racing._config)
    print(i18n.format("[NCM/Racing] Near-finish DNF grace armed: dist=%.1fm until=%.1fs",
        tonumber(remainingDistance or 0.0),
        tonumber(Racing._nearFinishDNFGraceUntil or 0.0)))
end

function Racing._getDNFTimeLimit()
    local limit = 0.0
    local cfg = Racing._config or {}
    local expectedTimeMult = _tuningValue("dnfExpectedTimeMult", cfg)
    local slowestAiMult = _tuningValue("dnfSlowestAiMult", cfg)
    local slowestAiGrace = _tuningValue("dnfSlowestAiGraceS", cfg)
    local dnfMinTime = _tuningValue("dnfMinTimeS", cfg)
    local dnfMaxTime = _tuningValue("dnfMaxTimeS", cfg)
    local dragDnfMinTime = _tuningValue("dragDnfMinTimeS", cfg)
    if Racing._config and Racing._config.expectedTime then
        limit = math.max(limit, Racing._config.expectedTime * expectedTimeMult)
    end

    local slowestProjected = 0.0
    for _, entry in ipairs(Racing._field or {}) do
        slowestProjected = math.max(slowestProjected, entry.aiTime or 0.0)
    end
    if slowestProjected > 0.0 then
        limit = math.max(limit, slowestProjected * slowestAiMult, slowestProjected + slowestAiGrace)
    end

    if Racing._nearFinishDNFGraceUntil then
        limit = math.max(limit, Racing._nearFinishDNFGraceUntil)
    end

    if limit <= 0.0 then
        limit = 600.0
    end
    local minTime = tostring(cfg.raceType or "sprint") == "drag" and dragDnfMinTime or dnfMinTime
    return math.min(dnfMaxTime, math.max(limit, minTime))
end

function Racing._getGridCountdownBlocker()
    if LIVE_RIVALS_POST_START then
        return nil
    end
    if #(Racing._field or {}) <= 0 then
        return nil
    end
    if not (MTE.AIVehicles and MTE.AIVehicles.getGridSummary) then
        return "grid_summary_unavailable"
    end
    local summary = MTE.AIVehicles.getGridSummary()
    if not summary then
        return "grid_summary_unavailable"
    end
    local readyCount = tonumber(summary.ready or 0) or 0
    local launchableCount = tonumber(summary.launchable or 0) or 0
    if summary.phase == "failed" then
        if readyCount > 0 or launchableCount > 0 then
            return nil
        end
        return "grid_failed:" .. tostring(summary.reason or "unknown")
    end
    if readyCount <= 0 then
        return "grid_empty"
    end
    if summary.phase ~= "ready" then
        if readyCount > 0 or launchableCount > 0 then
            return nil
        end
        return "grid_not_ready:" .. tostring(summary.phase or "unknown")
    end
    return nil
end

function Racing._updateGhostFallbackState()
    if not LIVE_RIVALS_POST_START or Racing._ghostFallbackActive then
        return false
    end
    if not Racing._postStartSpawnRequested then
        return false
    end
    if not MTE.AIVehicles then
        return Racing._enableGhostFallback("ai_unavailable")
    end
    local summary = MTE.AIVehicles.getGridSummary and MTE.AIVehicles.getGridSummary() or nil
    if summary and summary.phase == "failed" then
        print(i18n.format(
            "[NCM/Racing] Live rivals formation failed: run=%s aiRun=%s context=%s assembly=%s reason=%s ready=%d total=%d",
            tostring(Racing._ensureSpawnRunId()),
            tostring(summary.runId or "?"),
            tostring(summary.context or "?"),
            tostring(summary.assemblyMode or "?"),
            tostring(summary.reason or "unknown"),
            tonumber(summary.ready or 0),
            tonumber(summary.total or 0)))
        if MTE.AIVehicles.despawnAll then
            MTE.AIVehicles.despawnAll()
        end
        return Racing._enableGhostFallback("spawn_failed:" .. tostring(summary.reason or "unknown"))
    end
    return false
end

function Racing._armPostStartLiveSpawn(reason)
    if not LIVE_RIVALS_POST_START then
        return false
    end
    Racing._postStartLiveSpawnPending = true
    Racing._postStartLiveSpawnTimer = 0.0
    Racing._postStartLiveSpawnReason = reason or "armed_post_start"
    return true
end

function Racing._getPostStartLiveSpawnBlocker()
    if Racing._state ~= Racing.STATE.RACING then
        return "not_racing"
    end
    if not Racing._config or not Racing._config.nodeA or not Racing._config.nodeB then
        return "config_missing"
    end
    if not _getPlayerVehicle() then
        return "player_not_in_vehicle"
    end
    if (Racing._postStartLiveSpawnTimer or 0.0) < LIVE_RIVALS_POST_START_DELAY then
        return "launch_grace"
    end
    local playerPos = Racing._getPlayerPos()
    local startNode = Racing._config.nodeA
    local finishNode = Racing._config.nodeB
    if playerPos and startNode and finishNode then
        local dx = (finishNode.x or 0) - (startNode.x or 0)
        local dy = (finishNode.y or 0) - (startNode.y or 0)
        local planarLen = math.sqrt(dx * dx + dy * dy)
        if planarLen >= 1.0 then
            local ux = dx / planarLen
            local uy = dy / planarLen
            local rx = (playerPos.x or 0) - (startNode.x or 0)
            local ry = (playerPos.y or 0) - (startNode.y or 0)
            local longitudinal = rx * ux + ry * uy
            if longitudinal <= -LIVE_RIVALS_POST_START_PLAYER_BACK_BLOCK_M then
                return "player_in_grid_volume"
            end
        end
    end
    if MTE.AIVehicles and MTE.AIVehicles.isActive and MTE.AIVehicles.isActive() then
        return "grid_already_active"
    end
    if MTE.AIVehicles and MTE.AIVehicles.isDespawnCoolingDown and MTE.AIVehicles.isDespawnCoolingDown() then
        return "ai_despawn_cooldown"
    end
    return nil
end

function Racing._getVisibleSpawnField()
    local fullField = Racing._field or {}
    local visibleField = {}
    local deferredFaction = {}

    for _, entry in ipairs(fullField) do
        if entry and entry.isFaction then
            deferredFaction[#deferredFaction + 1] = entry
        else
            visibleField[#visibleField + 1] = entry
        end
    end

    -- Heat-injected faction enforcers currently use thinner metadata than the
    -- ordinary roster. Keep them out of the first visible birth pass so the
    -- stable race roster gets on-track first.
    if #visibleField > 0 then
        return visibleField, #deferredFaction
    end

    return fullField, 0
end

function Racing._trySpawnPostStartLiveRivals(dt)
    if not Racing._postStartLiveSpawnPending then return false end
    Racing._postStartLiveSpawnTimer = (Racing._postStartLiveSpawnTimer or 0.0) + (dt or 0.0)

    if not MTE.AIVehicles then
        Racing._resetPostStartLiveSpawn("ai_unavailable")
        Racing._enableGhostFallback("ai_unavailable")
        return false
    end

    local blocker = Racing._getPostStartLiveSpawnBlocker()
    if blocker then
        if Racing._postStartLiveSpawnReason ~= blocker then
            print(i18n.format("[NCM/Racing] Live rivals waiting: %s", tostring(blocker)))
        end
        Racing._postStartLiveSpawnReason = blocker
        return false
    end

    local visibleField, deferredFactionCount = Racing._getVisibleSpawnField()
    if #visibleField <= 0 then
        Racing._resetPostStartLiveSpawn("no_visible_field")
        Racing._enableGhostFallback("no_visible_field")
        return false
    end
    Racing._logSpawnRunMarker("post_start_dispatch", "post_start_live_rivals", {
        source = "racing_update",
        fieldCount = #visibleField,
    })
    print(i18n.format(
        "[NCM/Racing] Live rivals spawn begin: field=%d visible=%d deferredFaction=%d startType=%s nodeA=%s timer=%.2fs dist=%.1fm spawnMode=%s",
        tonumber(#Racing._field or 0),
        tonumber(#visibleField or 0),
        tonumber(deferredFactionCount or 0),
        tostring(Racing._config.startType or "grid"),
        tostring(Racing._config.nodeA and Racing._config.nodeA.name or "?"),
        tonumber(Racing._postStartLiveSpawnTimer or 0),
        tonumber(Racing._distToNode(Racing._config.nodeA) or 0),
        tostring("direct_grid")))
    _notify(i18n.format("Rivals joining the race - %d cars", tonumber(#visibleField or 0)), 2.2)
    Racing._postStartSpawnRequested = true
    local gridHeading = _getResolvedGridHeading(Racing._config.nodeA, Racing._config.nodeB, Racing._config)
    local gridForward = _getGridForwardVector(gridHeading)
    MTE.AIVehicles.spawnFormation(
        visibleField,
        Racing._config.nodeA,
        Racing._config.nodeB,
        Racing._config.startType or "grid",
        {
            assemblyMode = "direct",
            launchOnReady = true,
            context = "post_start_live_rivals_direct_grid",
            gridHeading = gridHeading,
            gridForward = gridForward,
            playerGridPos = Racing._qualiGridPos,
            trafficPrepared = false,
            trafficClearRadius = _tuningValue("trafficClearRadiusM", Racing._config),
            trafficVerticalTolerance = TRAFFIC_CLEAR_VERTICAL_TOLERANCE,
            stageSource = Racing._stageSource,
            routeId = Racing._config.routeId,
            routeMode = Racing._config.routeMode,
            raceType = Racing._config.raceType,
            dragStrip = Racing._config.dragStrip,
            raceContext = _buildAIRaceContext(Racing._config),
            rootProfileSettings = Racing._config.rootProfileSettings,
            runId = Racing._ensureSpawnRunId(),
        })
    Racing._postStartLiveSpawnPending = false
    Racing._postStartLiveSpawnReason = "spawn_started"
    return true
end

function Racing._getGridSpawnBlocker()
    if Racing._state ~= Racing.STATE.PRERACE then
        return "not_prerace"
    end
    if not Racing._config or not Racing._config.nodeA or not Racing._config.nodeB then
        return "config_missing"
    end
    if not Racing._gridFormingTriggered then
        return "awaiting_grid_trigger"
    end
    if not _canAdvanceRacePhase() then
        return "game_paused"
    end
    if not _getPlayerVehicle() then
        return "player_not_in_vehicle"
    end
    if MTE.AIVehicles and MTE.AIVehicles.isDespawnCoolingDown and MTE.AIVehicles.isDespawnCoolingDown() then
        return "ai_despawn_cooldown"
    end
    return nil
end

function Racing._getStartHeading(nodeA, nodeB)
    local function normalizeHeadingDeg(heading)
        if type(heading) ~= "number" or heading ~= heading or heading == math.huge or heading == -math.huge then
            return nil
        end
        local normalized = heading % 360.0
        if normalized < 0 then
            normalized = normalized + 360.0
        end
        return normalized
    end

    local function headingToUnitVector(heading)
        local rad = math.rad(heading or 0)
        return math.cos(rad), math.sin(rad)
    end

    local roadHeading = normalizeHeadingDeg(nodeA and nodeA.heading or nil)
    local routeHeading = nil
    if nodeA and nodeB then
        local dx = (nodeB.x or 0) - (nodeA.x or 0)
        local dy = (nodeB.y or 0) - (nodeA.y or 0)
        if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 then
            routeHeading = normalizeHeadingDeg(math.deg(math.atan2(dy, dx)))
        end
    end

    if roadHeading and routeHeading then
        local roadX, roadY = headingToUnitVector(roadHeading)
        local routeX, routeY = headingToUnitVector(routeHeading)
        local dot = (roadX * routeX) + (roadY * routeY)
        if dot < 0 then
            return normalizeHeadingDeg(roadHeading + 180.0)
        end
        return roadHeading
    end

    if roadHeading then
        return roadHeading
    end

    if routeHeading then
        return routeHeading
    end

    return 0
end

local function _normalizeHeadingDeg(heading)
    if type(heading) ~= "number" or heading ~= heading or heading == math.huge or heading == -math.huge then
        return nil
    end
    local normalized = heading % 360.0
    if normalized < 0 then
        normalized = normalized + 360.0
    end
    return normalized
end

local function _headingToUnitVector(heading)
    local rad = math.rad(heading or 0)
    return math.cos(rad), math.sin(rad)
end

local function _resolvePlayerStageHeading(nodeA, nodeB)
    local rawRoadHeading = _normalizeHeadingDeg(nodeA and nodeA.heading or nil)
    local routeHeading = nil
    if nodeA and nodeB then
        local dx = (nodeB.x or 0) - (nodeA.x or 0)
        local dy = (nodeB.y or 0) - (nodeA.y or 0)
        if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 then
            routeHeading = _normalizeHeadingDeg(math.deg(math.atan2(dy, dx)))
        end
    end

    local stackHeading = rawRoadHeading
    if rawRoadHeading then
        local plusNinety = _normalizeHeadingDeg(rawRoadHeading + 90.0)
        local minusNinety = _normalizeHeadingDeg(rawRoadHeading - 90.0)
        if routeHeading then
            local routeX, routeY = _headingToUnitVector(routeHeading)
            local plusX, plusY = _headingToUnitVector(plusNinety)
            local minusX, minusY = _headingToUnitVector(minusNinety)
            local plusDot = (plusX * routeX) + (plusY * routeY)
            local minusDot = (minusX * routeX) + (minusY * routeY)
            stackHeading = (plusDot >= minusDot) and plusNinety or minusNinety
        else
            stackHeading = plusNinety
        end
    end

    if stackHeading and routeHeading then
        local stackX, stackY = _headingToUnitVector(stackHeading)
        local routeX, routeY = _headingToUnitVector(routeHeading)
        local dot = (stackX * routeX) + (stackY * routeY)
        if dot < 0 then
            stackHeading = _normalizeHeadingDeg(stackHeading + 180.0) or stackHeading
        end
    elseif routeHeading then
        stackHeading = routeHeading
    end

    if stackHeading then
        stackHeading = _applyGridHeadingOffset(stackHeading, Racing._config)
    end

    local slotHeading = stackHeading and _normalizeHeadingDeg(stackHeading + _tuningValue("startSlotHeadingOffsetDeg", Racing._config)) or nil
    return slotHeading or stackHeading or rawRoadHeading or routeHeading or 0.0
end

function Racing._getPlayerGridPosForStart(startType, totalSlots)
    local resolvedStartType = tostring(startType or (Racing._config and Racing._config.startType) or "grid")
    if resolvedStartType == "grid" or resolvedStartType == "rolling" then
        local qualiPos = tonumber(Racing._qualiGridPos)
        if qualiPos then
            return math.max(1, math.floor(qualiPos))
        end
        local slotCount = math.max(1, math.floor(tonumber(totalSlots) or (#(Racing._field or {}) + 1)))
        return math.max(1, math.floor((slotCount + 1) * 0.5))
    end
    return tonumber(Racing._qualiGridPos) or 1
end

function Racing.getPlayerGridPosForStart(startType, totalSlots)
    return Racing._getPlayerGridPosForStart(startType, totalSlots)
end

function Racing._trySpawnQueuedGrid(dt)
    if not Racing._gridSpawnPending then return false end
    if not Racing._config or not Racing._config.nodeA or not Racing._config.nodeB then return false end
    if MTE.AIVehicles and MTE.AIVehicles.isActive and MTE.AIVehicles.isActive() then
        Racing._gridSpawnPending = false
        Racing._resetGridSpawnWindow("grid_already_active")
        return false
    end
    if MTE.AIVehicles and MTE.AIVehicles.getGridPhase then
        local gridPhase = MTE.AIVehicles.getGridPhase()
        if gridPhase and gridPhase ~= "idle" and gridPhase ~= "failed" then
            Racing._gridSpawnPending = false
            Racing._resetGridSpawnWindow("grid_phase_" .. tostring(gridPhase))
            return false
        end
    end
    local blocker = Racing._getGridSpawnBlocker()
    if blocker then
        if Racing._gridSpawnGateReason ~= blocker then
            print(i18n.format("[NCM/Racing] Grid spawn waiting: %s", tostring(blocker)))
        end
        Racing._gridSpawnStableTicks = 0
        Racing._gridSpawnStableTime  = 0.0
        Racing._gridSpawnGateReason  = blocker
        return false
    end

    local lastReason = Racing._gridSpawnGateReason
    Racing._gridSpawnStableTicks = (Racing._gridSpawnStableTicks or 0) + 1
    Racing._gridSpawnStableTime  = (Racing._gridSpawnStableTime or 0.0) + (dt or 0.0)
    Racing._gridSpawnGateReason  = "stable_window"
    if lastReason ~= "stable_window" then
        print(i18n.format(
            "[NCM/Racing] Grid spawn window open: ticks=%d/%d time=%.2f/%.2f",
            tonumber(Racing._gridSpawnStableTicks or 0),
            tonumber(_tuningValue("gridSpawnStableTicks", Racing._config)),
            tonumber(Racing._gridSpawnStableTime or 0),
            tonumber(_tuningValue("gridSpawnStableTimeS", Racing._config))))
    end
     if (Racing._gridSpawnStableTicks or 0) < _tuningValue("gridSpawnStableTicks", Racing._config)
         or (Racing._gridSpawnStableTime or 0.0) < _tuningValue("gridSpawnStableTimeS", Racing._config) then
        return false
    end

    if MTE.AIVehicles then
        local visibleField, deferredFactionCount = Racing._getVisibleSpawnField()
        local fieldSize = #Racing._field
        local visibleCount = #visibleField
        local gridHeading = _getResolvedGridHeading(Racing._config.nodeA, Racing._config.nodeB, Racing._config)
        local gridForward = _getGridForwardVector(gridHeading)
        print(i18n.format(
            "[NCM/Racing] Grid spawn field: full=%d visible=%d deferredFaction=%d startType=%s nodeA=%s heading=%.1f",
            tonumber(fieldSize or 0),
            tonumber(visibleCount or 0),
            tonumber(deferredFactionCount or 0),
            tostring(Racing._config.startType or "grid"),
            tostring(Racing._config.nodeA and Racing._config.nodeA.name or "?"),
            tonumber(gridHeading or 0)))
        Racing._logSpawnRunMarker("grid_dispatch", "prerace_grid", {
            source = Racing._stageSource,
            fieldCount = visibleCount,
        })
        print(i18n.format(
            "[NCM/Racing] Grid spawn begin: field=%d visible=%d deferredFaction=%d startType=%s nodeA=%s stageSource=%s heading=%.1f stable=%.2fs ticks=%d",
            fieldSize,
            visibleCount,
            tonumber(deferredFactionCount or 0),
            tostring(Racing._config.startType or "grid"),
            tostring(Racing._config.nodeA and Racing._config.nodeA.name or "?"),
            tostring(Racing._stageSource),
            tonumber(gridHeading or 0),
            tonumber(Racing._gridSpawnStableTime or 0),
            tonumber(Racing._gridSpawnStableTicks or 0)))
        _notify(i18n.format("Rivals incoming — %d cars forming up", visibleCount), 3.0)
        Racing._gridSpawnPending = false
        Racing._resetGridSpawnWindow("spawn_dispatch")
        local ok, err = pcall(MTE.AIVehicles.spawnFormation,
            visibleField,
            Racing._config.nodeA,
            Racing._config.nodeB,
            Racing._config.startType or "grid",
            {
                assemblyMode = "assembly",
                assemblyPlacement = "node_grid",
                launchOnReady = false,
                context = "queued_grid_prerace_assembly_grid_road_aligned",
                gridHeading = gridHeading,
                gridForward = gridForward,
                playerGridPos = Racing._qualiGridPos,
                trafficPrepared = true,
                trafficClearRadius = _tuningValue("trafficClearRadiusM", Racing._config),
                trafficVerticalTolerance = TRAFFIC_CLEAR_VERTICAL_TOLERANCE,
                stageSource = Racing._stageSource,
                routeId = Racing._config.routeId,
                routeMode = Racing._config.routeMode,
                raceType = Racing._config.raceType,
                dragStrip = Racing._config.dragStrip,
                raceContext = _buildAIRaceContext(Racing._config),
                rootProfileSettings = Racing._config.rootProfileSettings,
                runId = Racing._ensureSpawnRunId(),
            })
        if not ok then
            print(i18n.format("[NCM/Racing] Grid spawn dispatch failed: %s", tostring(err)))
            Racing._gridSpawnPending = true
            Racing._resetGridSpawnWindow("spawn_dispatch_failed")
            return false
        end
    end
    Racing._resetGridSpawnWindow("spawn_started")
    return true
end

function Racing.manualGridSpawnAhead(requestedCount)
    local count = math.max(1, math.min(2, math.floor(tonumber(requestedCount) or 1)))
    if not _manualGridModeEnabled() then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=disabled requested=%d", tonumber(count or 0)))
        _notify("Enable Manual Grid Mode in Settings before using manual spawn.", 2.0)
        return false, "manual_grid_mode_disabled"
    end
    if Racing._state ~= Racing.STATE.PRERACE then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=not_prerace state=%s requested=%d", tostring(Racing._state), tonumber(count or 0)))
        _notify("Manual grid spawn only works while the race is staged.", 2.0)
        return false, "not_prerace"
    end
    if not _canAdvanceRacePhase() then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=game_paused requested=%d", tonumber(count or 0)))
        _notify("Unpause before using manual grid spawn.", 2.0)
        return false, "game_paused"
    end
    if not _getPlayerVehicle() then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=player_not_in_vehicle requested=%d", tonumber(count or 0)))
        _notify("Enter your vehicle before using manual grid spawn.", 2.0)
        return false, "player_not_in_vehicle"
    end
    if not (MTE and MTE.AIVehicles and MTE.AIVehicles.spawnFormation) then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=ai_unavailable requested=%d", tonumber(count or 0)))
        _notify("AI vehicle module is unavailable.", 2.0)
        return false, "ai_unavailable"
    end
    if MTE.AIVehicles.isDespawnCoolingDown and MTE.AIVehicles.isDespawnCoolingDown() then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=ai_despawn_cooldown requested=%d", tonumber(count or 0)))
        _notify("AI cleanup is still settling. Try manual spawn again in a moment.", 2.0)
        return false, "ai_despawn_cooldown"
    end

    local visibleField, deferredFactionCount = Racing._getVisibleSpawnField()
    if #visibleField <= 0 then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=no_visible_field requested=%d deferredFaction=%d", tonumber(count or 0), tonumber(deferredFactionCount or 0)))
        _notify("No visible rivals are available for manual grid spawn.", 2.0)
        return false, "no_visible_field"
    end

    local spawnField = {}
    local spawnCount = math.min(count, #visibleField)
    for i = 1, spawnCount do
        local entry = visibleField[i]
        spawnField[#spawnField + 1] = entry
        print(i18n.format(
            "[NCM/Racing] manual_grid_pick index=%d driver=%s name=%s gridPos=%s",
            tonumber(i or 0),
            tostring(entry and (entry.driverId or entry.id) or "?"),
            tostring(entry and (entry.displayName or entry.name) or "?"),
            tostring(entry and entry.gridPos or "?")))
    end

    local startNode, finishNode, heading, gridForward, nodeErr = _buildManualGridSpawnNodes(spawnCount)
    if not startNode or not finishNode then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_blocked reason=%s requested=%d", tostring(nodeErr or "node_build_failed"), tonumber(spawnCount or 0)))
        _notify("Could not build a manual spawn point ahead of V.", 2.0)
        return false, tostring(nodeErr or "node_build_failed")
    end

    local cfg = Racing._config or {}
    if MTE.AIVehicles.noteWorldDisruption then
        MTE.AIVehicles.noteWorldDisruption("manual_grid_dispatch")
    end
    Racing._gridSpawnPending = false
    Racing._resetGridSpawnWindow("manual_grid_dispatch")
    Racing._logSpawnRunMarker("manual_grid_dispatch", "manual_grid_mode", {
        source = "manual_hotkey",
        fieldCount = spawnCount,
        nodeA = startNode,
        nodeB = finishNode,
    })
    print(i18n.format(
        "[NCM/Racing] manual_grid_spawn_begin requested=%d actual=%d deferredFaction=%d heading=%.1f start=(%.1f, %.1f, %.1f) finish=(%.1f, %.1f, %.1f)",
        tonumber(count or 0),
        tonumber(spawnCount or 0),
        tonumber(deferredFactionCount or 0),
        tonumber(heading or 0),
        tonumber(startNode.x or 0),
        tonumber(startNode.y or 0),
        tonumber(startNode.z or 0),
        tonumber(finishNode.x or 0),
        tonumber(finishNode.y or 0),
        tonumber(finishNode.z or 0)))

    local ok, err = pcall(MTE.AIVehicles.spawnFormation,
        spawnField,
        startNode,
        finishNode,
        "sidebyside",
        {
            assemblyMode = "assembly",
            assemblyPlacement = "node_grid",
            launchOnReady = false,
            context = i18n.format("manual_grid_ahead_%d", tonumber(spawnCount or 0)),
            gridHeading = heading,
            gridForward = gridForward,
            playerGridPos = nil,
            trafficPrepared = false,
            trafficClearRadius = _tuningValue("trafficClearRadiusM", cfg),
            trafficVerticalTolerance = TRAFFIC_CLEAR_VERTICAL_TOLERANCE,
            stageSource = "manual_grid_mode",
            routeId = cfg.routeId,
            routeMode = cfg.routeMode,
            raceType = cfg.raceType,
            dragStrip = nil,
            raceContext = _buildAIRaceContext(cfg),
            rootProfileSettings = cfg.rootProfileSettings,
            runId = Racing._ensureSpawnRunId(),
        })

    if not ok then
        print(i18n.format("[NCM/Racing] manual_grid_spawn_failed requested=%d actual=%d err=%s", tonumber(count or 0), tonumber(spawnCount or 0), tostring(err)))
        _notify("Manual grid spawn failed. Check CET for details.", 2.2)
        return false, tostring(err)
    end

    print(i18n.format("[NCM/Racing] manual_grid_spawn_ok actual=%d context=%s", tonumber(spawnCount or 0), i18n.format("manual_grid_ahead_%d", tonumber(spawnCount or 0))))
    _notify(i18n.format("Manual grid spawned: %d rival%s ahead", tonumber(spawnCount or 0), spawnCount == 1 and "" or "s"), 2.2)
    return true, nil
end

function Racing._startGridPrewarm(source)
    if not Racing._config or not Racing._config.nodeA or not Racing._config.nodeB then return false end
    if MTE.AIVehicles and MTE.AIVehicles.isActive and MTE.AIVehicles.isActive() then
        Racing._gridSpawnPending = false
        Racing._resetGridSpawnWindow("grid_already_active")
        return false
    end
    if _manualGridModeEnabled() then
        Racing._gridFormingTriggered = true
        Racing._stageSource = source or Racing._stageSource or "confirm"
        Racing._gridSpawnPending = false
        Racing._resetGridSpawnWindow("manual_grid_mode")
        Racing._logSpawnRunMarker("manual_grid_armed", "manual_grid_mode", {
            source = source or "unknown",
            fieldCount = #(Racing._field or {}),
        })
        print(i18n.format(
            "[NCM/Racing] Manual grid mode armed: field=%d startType=%s nodeA=%s source=%s",
            tonumber(#Racing._field or 0),
            tostring(Racing._config.startType or "grid"),
            tostring(Racing._config.nodeA and Racing._config.nodeA.name or "?"),
            tostring(source or "unknown")))
        _notify("Manual Grid Mode: use the manual spawn hotkey for 1 or 2 rivals ahead.", 3.0)
        return true
    end
    Racing._gridFormingTriggered = true
    Racing._stageSource = source or Racing._stageSource or "confirm"
    Racing._queueGridSpawn()
    print(i18n.format(
        "[NCM/Racing] Grid prewarm armed: field=%d startType=%s nodeA=%s source=%s",
        tonumber(#Racing._field or 0),
        tostring(Racing._config.startType or "grid"),
        tostring(Racing._config.nodeA and Racing._config.nodeA.name or "?"),
        tostring(source or "unknown")))
    return true
end

function Racing._runDeferredPreraceInit(reason)
    local cfg = Racing._config or nil
    local nodeA = cfg and cfg.nodeA or nil
    local nodeB = cfg and cfg.nodeB or nil
    if not cfg or not nodeA or not nodeB then
        return false
    end

    _clearRacerMarkers()

    -- Push the world/UI bridge work out of confirmConfig so staging can finish first.
    _suppressZone()
    _clearAmbientTrafficAroundNode(nodeA, _tuningValue("trafficClearRadiusM", cfg))

    local settings = MTE.Settings and MTE.Settings.current or {}
    print("[NCM/Mappins] GUARD: raceMappins=" .. tostring(settings.raceMappins) .. " MTE.Mappins=" .. tostring(MTE.Mappins))
    if settings.raceMappins ~= false and MTE.Mappins then
        MTE.Mappins.showRaceMarkers(nodeA, nodeB)
        MTE.Mappins.setGpsWaypoint(nodeA)
    else
        print("[NCM/Mappins] GUARD FAILED — skipping showRaceMarkers")
    end

    print("[NCM/Racing] deferred prerace init: syncing quest/UI prerace state")
    _queueQuestEvent(true, cfg.trackName or "")
    _syncRaceState("prerace")
    _sendSMS(2)
    print("[NCM/Racing] deferred prerace init: quest/UI prerace state synced")

    print("[NCM/Racing] deferred prerace init: emitting RacePreview")
    MTE.Events.emit("RacePreview", { config = cfg, field = Racing._field })
    print("[NCM/Racing] deferred prerace init: RacePreview emitted")
    return true
end

function Racing._snapPlayerToNode(node)
    if not node then return false end
    local target = _getPlayerVehicle() or Game.GetPlayer()
    if not target then return false end
    local finishNode = Racing._config and Racing._config.nodeB or nil
    local startHeading = _resolvePlayerStageHeading(node, finishNode)
    return _safeTeleport(target, _applyGridLateralShift(node, node, finishNode, Racing._config), startHeading)
end

--- Arms the auto-stage approach countdown. Called every tick in PRERACE.
--- Countdown arming is speed-gated by the configured start snap max speed.
--- before the auto-snap actually fires to prevent high-speed teleport CTD.
function Racing._tryAutoStagePlayerForStart()
    if Racing._autoStageTriggered then
        Racing._stageCountdown = nil
        return false
    end
    local cfg = Racing._config or {}
    local nodeA = cfg.nodeA
    if not nodeA or not _getPlayerVehicle() or not _canAdvanceRacePhase() then
        Racing._stageCountdown = nil
        return false
    end

    local dist    = Racing._distToNode(nodeA)
    local inRange = dist and dist <= _tuningValue("startCaptureRadiusM", cfg)
    if not inRange then
        Racing._stageCountdown = nil
        return false
    end
    if _isRollingStart(cfg) then
        if _getPlayerVehicleSpeedMps() > _tuningValue("rollingStartMaxSpeedMps", cfg) then
            Racing._stageCountdown = nil
            return false
        end
        Racing._autoStageTriggered = true
        Racing._stageSource = Racing._stageSource or "rolling_approach"
        return true
    end
    if not _isPlayerSlowEnoughToStage() then
        Racing._stageCountdown = nil
        return false
    end

    if not _playerGridSnapEnabled() then
        local readyRadius = _tuningValue("startReadyRadiusM", cfg)
        Racing._stageCountdown = nil
        if dist and dist <= readyRadius then
            Racing._autoStageTriggered = true
            Racing._stageSource = Racing._stageSource or "drive_in"
            print(i18n.format(
                "[NCM/Racing] Stage complete: source=%s cooldown=0.0 snap=false dist=%.2f",
                tostring(Racing._stageSource),
                tonumber(dist or 0)))
            _notify("STAGED - Hold your grid spot.", 1.8)
            return true
        end
        return false
    end

    -- Arm countdown on first entry into capture radius
    if not Racing._stageCountdown then
        Racing._stageCountdown = 3.0
        _notify("STAGING IN 3...", 1.1)
        pcall(function()
            local p = Game.GetPlayer()
            if p then GameObject.PlaySoundEvent(p, "ui_menu_onpress") end
        end)
    end
    return false
end

--- Snap V to the start node. Called by approach countdown (speed-gated), hotkey, or Warp button.
function Racing.stageNow()
    return Racing._stageNowInternal("warp")
end

function Racing._stageNowInternal(source)
    if Racing._autoStageTriggered then return false end
    local cfg   = Racing._config or {}
    local nodeA = cfg.nodeA
    if not nodeA then return false end
    Racing._stageCountdown = nil

    if not _playerGridSnapEnabled() and not _isRollingStart(cfg) then
        local ready, err = _checkPlayerStartReadiness("race")
        if ready then
            Racing._autoStageTriggered = true
            Racing._stageSource = source or "drive_in"
            print(i18n.format(
                "[NCM/Racing] Stage complete: source=%s cooldown=0.0 snap=false manual=true",
                tostring(Racing._stageSource)))
            _notify("Player grid snap disabled - hold your current grid spot.", 1.8)
            return true
        end
        print(i18n.format(
            "[NCM/Racing] Stage request blocked: source=%s reason=snap_disabled not_ready=%s",
            tostring(source or "unknown"),
            tostring(err or "player_not_ready")))
        _notify("Player grid snap is disabled. Drive into the grid spot manually.", 2.0)
        return false
    end

    local snapped = Racing._snapPlayerToNode(nodeA)
    if snapped then
        local stageSource = source or "approach"
        if MTE.AIVehicles and MTE.AIVehicles.noteWorldDisruption then
            MTE.AIVehicles.noteWorldDisruption("stage_" .. tostring(stageSource))
        end
        local cooldown = (stageSource == "warp") and WARP_SETTLE_TIME or ZONE_CLEAR_TIME
        Racing._autoStageTriggered  = true
        Racing._stageSource         = stageSource
        Racing._postSnapCooldown    = cooldown
        Racing._postSnapNotifyTimer = 0.0
        Racing._trafficClearRetryTimer = 0.0
        Racing._resetGridSpawnWindow("stage_complete")
        _clearAmbientTrafficAroundNode(nodeA, _tuningValue("trafficClearRadiusM", cfg))
        print(i18n.format("[NCM/Racing] Stage complete: source=%s cooldown=%.1fs", stageSource, cooldown))
        _notify(stageSource == "warp" and "STAGED - Letting the area stream in..." or "STAGED - Clearing the zone...", 2.5)
    end
    return snapped
end

--- Returns true when the auto-stage approach countdown is active.
function Racing.isStagePromptVisible()
    return Racing._stageCountdown ~= nil
end

local ROUTE_SETTINGS_KEYS = { "lapCount", "fieldSize", "raceType", "startType", "vehicleClass", "timeOfDay" }

local function applyRouteSettings(config, route)
    if not (route and type(route.settings) == "table") then return end
    local s = route.settings
    if tonumber(s.lapCount)   then config.lapCount    = math.max(1, math.floor(tonumber(s.lapCount)))   end
    if tonumber(s.fieldSize)  then config.fieldSize   = math.max(1, math.floor(tonumber(s.fieldSize)))  end
    if type(s.raceType)       == "string" then config.raceType    = s.raceType    end
    if type(s.startType)      == "string" then config.startType   = s.startType   end
    if type(s.vehicleClass)   == "string" then config.vehicleClass = s.vehicleClass end
    if type(s.timeOfDay)      == "string" then config.timeOfDay   = s.timeOfDay   end
end

local function resolveRouteRecord(config)
    if not (config and config.nodeA and config.nodeB and MTE and MTE.Routes and MTE.Routes.resolve) then
        return nil
    end
    local route = MTE.Routes.resolve(config.nodeA, config.nodeB, config)
    if route then
        config.route = route
        config.routeId = route.routeId
        config.rootId = config.rootId or route.rootId
        config.rootDisplayName = config.rootDisplayName or route.rootDisplayName
        config.subtitleLabel = config.subtitleLabel or route.subtitleLabel
        config.selectedRootId = config.selectedRootId or config.rootId or route.rootId
        config.trackName = config.rootDisplayName or route.displayName
        if not config.titleLabel then
            config.titleLabel = config.rootDisplayName or route.rootDisplayName or route.displayName
        end
        applyRouteSettings(config, route)
    end
    return route
end

local function resolveRaceMode()
    if Racing._stageSource == "quick" then
        return "quick_race"
    end
    if Racing._config and Racing._config.raceType == "knockout" then
        return "knockout"
    end
    local career = Racing._career
    if career and MTE and MTE.Championships and MTE.Championships.activeSeason then
        local season = MTE.Championships.activeSeason(career)
        if season and not season.completed then
            return "championship"
        end
    end
    return "career"
end

local function beginTelemetrySession()
    if not (MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.beginSession) then
        return nil
    end
    local config = Racing._config or {}
    local route = config.route or resolveRouteRecord(config)
    local career = Racing._career
    local season = career and MTE.Championships and MTE.Championships.activeSeason and MTE.Championships.activeSeason(career) or nil
    local sessionId = MTE.RaceTelemetry.beginSession({
        route = route,
        routeId = route and route.routeId or config.routeId,
        routeDisplayName = route and route.displayName or config.trackName,
        canonicalPairKey = route and route.canonicalPairKey or nil,
        mode = resolveRaceMode(),
        lapCount = config.lapCount or 1,
        fieldSize = (#(Racing._field or {})) + 1,
        startType = config.startType,
        raceType = config.raceType,
        playerVehicleId = Racing._getVehicleId(),
        playerDriverId = "player",
        playerTeamId = career and career.playerFactionId or nil,
        playerTeamName = career and career.playerFactionName or nil,
        playerName = "V",
        careerId = career and career.id or nil,
        careerName = career and career.name or nil,
        tier = career and career.tier or nil,
        seasonId = season and season.id or nil,
        seasonNumber = career and career.seasonNumber or nil,
        championshipRound = season and season.currentRound or nil,
        district = config.district,
        region = config.district,
        timeOfDay = config.timeOfDay,
        allowCombat = config.allowCombat,
        allowStakes = config.allowStakes,
        routeMode = config.routeMode,
        trackName = config.trackName,
        startPos = Racing._qualiGridPos or 1,
        field = Racing._field,
        seed = Racing._spawnRunId,
    })
    Racing._telemetrySessionId = sessionId
    return sessionId
end

local function abandonTelemetrySession(reason, invalidated)
    if MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.abandonActive then
        MTE.RaceTelemetry.abandonActive(reason or "abandoned", invalidated == true)
    end
    Racing._telemetrySessionId = nil
end

function Racing.init()
    Racing._state        = Racing.STATE.IDLE
    Racing._config       = {}
    Racing._activeEvent  = nil
    Racing._field        = {}
    Racing._results      = {}
    Racing._raceTimer    = 0.0
    Racing._stakeAmount  = 0
    Racing._qualiTime    = nil
    Racing._qualiGridPos = nil
    Racing._finishNode   = nil
    Racing._finishDir    = nil
    Racing._prevFinishDot = nil
    Racing._aiPrevDot    = {}
    Racing._aiFinished   = {}
    Racing._aiFinishTime = {}
    Racing._telemetrySessionId = nil
    Racing._lastCountdownPhase = nil
    Racing._countdownDuration = 3.0
    Racing._countdownUseLights = true
    Racing._bgSimTimer   = 0
    Racing._gridReadyEmitted = false
    Racing._quickRacePending = false
    Racing._gridSpawnPending = false
    Racing._autoStageTriggered = false
    Racing._gridFormingTriggered = false
    Racing._stageSource = nil
    Racing._stageCountdown = nil
    Racing._prelaunchCountdown = nil
    Racing._postSnapCooldown = 0.0
    Racing._postSnapNotifyTimer = 0.0
    Racing._finishResolver = nil
    Racing._sequenceRaceState = nil
    Racing._resetPostStartLiveSpawn("init")
    Racing._resetGhostFallback("init")
    Racing._resetGridSpawnWindow("init")
    Racing._resetRollingStartState("init")
    _clearRacerMarkers()
    _restoreZone()
    print("[NCM/Racing] V2 ready.")
end

--- Called when a new game session starts (player object becomes valid).
function Racing.onSessionStart()
    abandonTelemetrySession("session_start", true)
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end
    _queueQuestEvent(false)
    _syncRaceState("idle")
    _restoreZone()
    Racing._state              = Racing.STATE.IDLE
    Racing._config             = {}
    Racing._activeEvent        = nil
    Racing._field              = {}
    Racing._results            = {}
    Racing._raceTimer          = 0.0
    Racing._stakeAmount        = 0
    Racing._qualiTime          = nil
    Racing._qualiGridPos       = nil
    Racing._finishNode         = nil
    Racing._finishDir          = nil
    Racing._prevFinishDot      = nil
    Racing._aiPrevDot          = {}
    Racing._aiFinished         = {}
    Racing._aiFinishTime       = {}
    Racing._telemetrySessionId = nil
    Racing._lastCountdownPhase = nil
    Racing._countdownDuration  = 3.0
    Racing._countdownUseLights = true
    Racing._bgSimTimer         = 0
    Racing._draft              = {}
    Racing._gridReadyEmitted   = false
    Racing._quickRacePending   = false
    Racing._qualiCountdown     = nil
    Racing._qualiLastTickSec   = nil
    Racing._qualiProximityTriggered = false
    Racing._gridSpawnPending        = false
    Racing._finishResolver          = nil
    Racing._sequenceRaceState       = nil
    Racing._resetPostStartLiveSpawn("session_start")
    Racing._resetGhostFallback("session_start")
    Racing._autoStageTriggered      = false
    Racing._gridFormingTriggered    = false
    Racing._stageSource             = nil
    Racing._stageCountdown          = nil
    Racing._prelaunchCountdown      = nil
    Racing._postSnapCooldown        = 0.0
    Racing._postSnapNotifyTimer     = 0.0
    Racing._resetGridSpawnWindow("session_start")
    Racing._resetRollingStartState("session_start")
    Racing._pendingPreraceInit      = nil
    _clearRacerMarkers()
    print(i18n.format(
        "[NCM/Racing] Session started - state reset. build=%s",
        tostring(RACE_FLOW_BUILD)))
end

-- ── Update (called every frame from init.lua) ─────────────────

function Racing.update(dt)
    if not _canAdvanceRacePhase() then
        return
    end

    -- Background roster simulation (~every 5 minutes real time)
    Racing._bgSimTimer = Racing._bgSimTimer + dt
    if Racing._bgSimTimer >= 300 then
        Racing._bgSimTimer = 0
        local career = MTE.Careers and MTE.Careers.active()
        if career and MTE.Roster then
            MTE.Roster.simulate(career, math.random(3, 8))
        end
    end

    -- Heat decay tick
    if MTE.Heat then
        pcall(function()
            local h = Game.GetTimeSystem():GetGameTime():Hours()
            MTE.Heat.tickDecay()
        end)
    end

    -- Update AI vehicle spawning pipeline
    if MTE.AIVehicles then MTE.AIVehicles.update(dt) end

    -- Tick down post-snap cooldown; throttle a repeating "clearing traffic" notify
    if (Racing._postSnapCooldown or 0) > 0 then
        Racing._postSnapCooldown    = Racing._postSnapCooldown - dt
        Racing._postSnapNotifyTimer = (Racing._postSnapNotifyTimer or 0) - dt
        Racing._trafficClearRetryTimer = (Racing._trafficClearRetryTimer or 0) - dt
        if Racing._trafficClearRetryTimer <= 0 and Racing._config and Racing._config.nodeA then
            _clearAmbientTrafficAroundNode(Racing._config.nodeA, _tuningValue("trafficClearRadiusM", Racing._config))
            Racing._trafficClearRetryTimer = _tuningValue("trafficClearRetryIntervalS", Racing._config)
        end
        if Racing._postSnapNotifyTimer <= 0 then
            local secsLeft = math.ceil(Racing._postSnapCooldown)
            if secsLeft > 0 then
                _notify(i18n.format("Clearing traffic... %ds", secsLeft), 1.2)
            end
            Racing._postSnapNotifyTimer = 1.0
        end
    end

    if Racing._state == Racing.STATE.PRERACE and Racing._pendingPreraceInit then
        Racing._pendingPreraceInit.frames = (Racing._pendingPreraceInit.frames or 0) - 1
        if (Racing._pendingPreraceInit.frames or 0) <= 0 then
            local pendingReason = Racing._pendingPreraceInit.reason or "prerace"
            Racing._pendingPreraceInit = nil
            local ok, err = pcall(Racing._runDeferredPreraceInit, pendingReason)
            if not ok then
                print("[NCM/Racing] deferred prerace init failed: " .. tostring(err))
            end
        end
    elseif Racing._pendingPreraceInit then
        Racing._pendingPreraceInit = nil
    end

    if Racing._state == Racing.STATE.PRERACE then
        Racing._tryAutoStagePlayerForStart()
        -- Tick auto-stage approach countdown; fire stageNow when it expires
        if Racing._stageCountdown then
            local prevSec = math.ceil(Racing._stageCountdown)
            Racing._stageCountdown = Racing._stageCountdown - dt
            local curSec = math.ceil(Racing._stageCountdown)
            if curSec < prevSec and curSec >= 1 then
                _notify(i18n.format("STAGING IN %d...", curSec), 1.1)
                pcall(function()
                    local p = Game.GetPlayer()
                    if p then GameObject.PlaySoundEvent(p, "ui_menu_onpress") end
                end)
            end
            if Racing._stageCountdown <= 0 then
                Racing._stageNowInternal("approach")
            end
        end

        -- Tick pre-launch countdown (started when grid is ready and we auto-staged)
        if Racing._prelaunchCountdown then
            local prevSec = math.ceil(Racing._prelaunchCountdown)
            Racing._prelaunchCountdown = Racing._prelaunchCountdown - dt
            local curSec = math.ceil(Racing._prelaunchCountdown)
            if curSec < prevSec and curSec >= 1 then
                _notify(i18n.format("RACE IN %d...", curSec), 1.1)
                pcall(function()
                    local p = Game.GetPlayer()
                    if p then GameObject.PlaySoundEvent(p, "ui_menu_onpress") end
                end)
            end
            if Racing._prelaunchCountdown <= 0 then
                Racing._prelaunchCountdown = nil
                Racing.startRace()
            end
        end

        if Racing._gridSpawnPending then
            Racing._trySpawnQueuedGrid(dt)
        end
        -- Emit GridReady once when spawn pipeline first completes.
        -- For quali races, defer until after qualifying has run (_qualiTime set).
        -- If we auto-staged, start the pre-launch countdown so the race fires automatically.
        if not Racing._gridReadyEmitted then
            local spawnDone = (not Racing._config.qualiEnabled or Racing._qualiTime ~= nil)
                           and not Racing._gridSpawnPending
            local spawning  = MTE.AIVehicles and MTE.AIVehicles.isSpawning()
            local gridSummary = MTE.AIVehicles and MTE.AIVehicles.getGridSummary and MTE.AIVehicles.getGridSummary() or nil
            local stageReadyForGridReady = (not LIVE_RIVALS_POST_START) or Racing._autoStageTriggered
            local gridReadyBlocker = Racing._getGridCountdownBlocker()
            if spawnDone and not spawning and stageReadyForGridReady and not gridReadyBlocker and _isRollingStart(Racing._config) then
                Racing._armRollingStartWarmup("grid_ready")
            end
            if spawnDone and not spawning and stageReadyForGridReady and not gridReadyBlocker then
                Racing._gridReadyEmitted = true
                Racing._gridReadyBlockerReason = nil
                if gridSummary then
                    print(i18n.format(
                        "[NCM/Racing] Grid ready: phase=%s ready=%d launchable=%d total=%d reason=%s",
                        tostring(gridSummary.phase),
                        tonumber(gridSummary.ready or 0),
                        tonumber(gridSummary.launchable or 0),
                        tonumber(gridSummary.total or 0),
                        tostring(gridSummary.reason)))
                end
                MTE.Events.emit("GridReady", {
                    field = Racing._field,
                    autoStaged = Racing._autoStageTriggered == true,
                    liveRivalsDeferred = Racing.isVisibleFieldDeferred(),
                })
                -- Auto-launch countdown: only when player was auto/warp-staged (not manual quali flow)
                if Racing._autoStageTriggered and not (Racing._config.qualiEnabled and not Racing._qualiTime) then
                    if _isRollingStart(Racing._config) then
                        local rollingReady = Racing._isPlayerReadyForRaceStart()
                        if rollingReady then
                            _notify("ROLLING START READY - GO!", 1.0)
                            Racing.startRace()
                        end
                    else
                        local canAutoCountdown = _playerGridSnapEnabled() or Racing._isPlayerReadyForRaceStart()
                        if canAutoCountdown then
                            local countdownSeconds = _getRaceCountdownSeconds(Racing._config)
                            Racing._prelaunchCountdown = countdownSeconds
                            _notify(i18n.format(
                                "%s - RACE IN %d...",
                                LIVE_RIVALS_POST_START and "START SET" or "GRID SET",
                                math.max(1, math.ceil(countdownSeconds))), 1.2)
                            pcall(function()
                                local p = Game.GetPlayer()
                                if p then GameObject.PlaySoundEvent(p, "ui_menu_onpress") end
                            end)
                        end
                    end
                end
            elseif spawnDone and not spawning and stageReadyForGridReady and gridReadyBlocker then
                if Racing._gridReadyBlockerReason ~= gridReadyBlocker then
                    Racing._gridReadyBlockerReason = gridReadyBlocker
                    Racing._prelaunchCountdown = nil
                    print(i18n.format(
                        "[NCM/Racing] Grid ready blocked: %s",
                        tostring(gridReadyBlocker)))
                end
            end
        end
        if Racing._state == Racing.STATE.PRERACE
           and Racing._gridReadyEmitted
           and not _isRollingStart(Racing._config)
           and not Racing._prelaunchCountdown then
            local spawnDone = (not Racing._config.qualiEnabled or Racing._qualiTime ~= nil)
                           and not Racing._gridSpawnPending
            local spawning = MTE.AIVehicles and MTE.AIVehicles.isSpawning()
            local gridReadyBlocker = Racing._getGridCountdownBlocker()
            local playerReady = Racing._isPlayerReadyForRaceStart()
            if spawnDone and not spawning and not gridReadyBlocker and playerReady then
                local countdownSeconds = _getRaceCountdownSeconds(Racing._config)
                Racing._prelaunchCountdown = countdownSeconds
                _notify(i18n.format(
                    "%s - RACE IN %d...",
                    LIVE_RIVALS_POST_START and "START SET" or "GRID SET",
                    math.max(1, math.ceil(countdownSeconds))), 1.2)
                pcall(function()
                    local p = Game.GetPlayer()
                    if p then GameObject.PlaySoundEvent(p, "ui_menu_onpress") end
                end)
            end
        end
          if Racing._state == Racing.STATE.PRERACE
              and Racing._gridReadyEmitted and _isRollingStart(Racing._config)
           and Racing._autoStageTriggered and not Racing._prelaunchCountdown then
            local spawnDone = (not Racing._config.qualiEnabled or Racing._qualiTime ~= nil)
                           and not Racing._gridSpawnPending
            local spawning = MTE.AIVehicles and MTE.AIVehicles.isSpawning()
            local gridReadyBlocker = Racing._getGridCountdownBlocker()
            local rollingReady = Racing._isPlayerReadyForRaceStart()
            if spawnDone and not spawning and not gridReadyBlocker and rollingReady then
                _notify("ROLLING START READY - GO!", 1.0)
                Racing.startRace()
            end
        end
        -- Quick Race: immediately snap player to start; pre-launch countdown starts via GridReady path.
        if Racing._quickRacePending then
            if not Racing._autoStageTriggered then
                Racing._stageNowInternal("quick")  -- teleports to nodeA; grid queued; countdown starts after GridReady
            end
            Racing._quickRacePending = false
        end
        -- In-world quali proximity trigger: auto-start countdown when near nodeA.
        -- Works without CET — player just drives/rides to the start point.
        if Racing._config and Racing._config.qualiEnabled and not Racing._qualiTime then
            if not Racing._qualiProximityTriggered then
                local dist = Racing._distToNode(Racing._config.nodeA)
                if dist and dist < 15.0 then
                    local ok = Racing._isPlayerReadyForQuali()
                    if ok then
                        Racing._qualiProximityTriggered = true
                        Racing._qualiCountdown          = 5.0
                        Racing._qualiLastTickSec        = 5
                        _notify("QUALIFYING STARTS IN  5...", 1.1)
                        pcall(function()
                            local p = Game.GetPlayer()
                            if p then GameObject.PlaySoundEvent(p, "ui_menu_onpress") end
                        end)
                    end
                end
            elseif Racing._qualiCountdown then
                local prevSec = math.ceil(Racing._qualiCountdown)
                Racing._qualiCountdown = Racing._qualiCountdown - dt
                local curSec  = math.ceil(Racing._qualiCountdown)
                if curSec < prevSec and curSec >= 1 then
                    _notify(i18n.format("QUALIFYING STARTS IN  %d...", curSec), 1.1)
                    pcall(function()
                        local p = Game.GetPlayer()
                        if p then GameObject.PlaySoundEvent(p, "ui_menu_onpress") end
                    end)
                end
                if Racing._qualiCountdown <= 0 then
                    Racing._qualiCountdown   = nil
                    Racing._qualiLastTickSec = nil
                    Racing.startQuali()
                end
            end
        end
    elseif Racing._state == Racing.STATE.CONFIG then
        Racing._configTimer = (Racing._configTimer or 0) + dt
        if Racing._configTimer > 600 then
            print("[NCM/Racing] CONFIG timeout (10 min) - auto-closing.")
            Racing._state = Racing.STATE.IDLE
            Racing._configTimer = 0
        end
    else
        Racing._preraceTimer = 0
        Racing._configTimer  = 0
    end

    -- Countdown
    if Racing._state == Racing.STATE.COUNTDOWN then
        Racing._raceTimer = Racing._raceTimer - dt

        -- Grid-light phase & countdown sounds
        local phase = Racing.getCountdownPhase()
        if phase >= 0 and Racing._lastCountdownPhase ~= phase then
            Racing._lastCountdownPhase = phase
            local cfg = MTE.Settings and MTE.Settings.current or {}
            if cfg.countdownBeeps ~= false then
                pcall(function()
                    local p = Game.GetPlayer()
                    if p then
                        if phase == 0 then
                            GameObject.PlaySoundEvent(p, "ui_jingle_quest_new")
                        elseif phase >= 1 then
                            GameObject.PlaySoundEvent(p, "ui_menu_onpress")
                        end
                    end
                end)
            end
        end

        if Racing._raceTimer <= 0 then
            Racing._state     = Racing.STATE.RACING
            Racing._raceTimer = 0.0
            Racing._lastCountdownPhase = nil
            _syncRaceState("racing")
            if MTE and MTE.SafetyRating and MTE.SafetyRating.beginRace then
                local activeEvent = Racing._activeEvent or {}
                local sourceType = activeEvent.sourceType or (Racing._config and Racing._config.eventSourceType)
                local isQuickRace = sourceType == "quick_race"
                MTE.SafetyRating.beginRace({
                    scopeType = isQuickRace and "quick_race" or "career",
                    careerId = (not isQuickRace and Racing._career and Racing._career.id) or nil,
                    careerName = (not isQuickRace and Racing._career and Racing._career.name) or nil,
                    sourceType = sourceType,
                    telemetrySessionId = Racing._telemetrySessionId,
                })
                if Racing._telemetrySessionId and MTE.SafetyRating.attachTelemetrySession then
                    MTE.SafetyRating.attachTelemetrySession(Racing._telemetrySessionId)
                end
            end
            Racing._armPostStartLiveSpawn("race_start")
            if _isRollingStart(Racing._config) then
                Racing._beginRollingStartZone("countdown_complete")
            end
            -- Launch AI vehicles
            if MTE.AIVehicles then MTE.AIVehicles.launchAll() end
            Racing._beginSequenceRace()
            Racing._initDragLiveStraightness()
            MTE.Events.emit("RaceStart", { config = Racing._config })
        end
        return
    end

    -- Active race
    if Racing._state == Racing.STATE.RACING then
        Racing._raceTimer = Racing._raceTimer + dt
        Racing._trySpawnPostStartLiveRivals(dt)
        Racing._updateGhostFallbackState()
        if MTE.AIVehicles and MTE.AIVehicles.isActive and MTE.AIVehicles.isActive() and not MTE.AIVehicles.isSpawning() then
            MTE.AIVehicles.launchAll()
        end
        if Racing._rollingZoneActive then
            Racing._updateRollingStartZone(dt)
        end

        if Racing._sequenceRaceState and Racing._sequenceRaceState.sequence then
            Racing._updateSequenceRaceProgress()
        else
            -- Tick authoritative AI finish-line crossing (sign-change of dot product)
            Racing._tickAIFinishCrossings()
        end
        Racing._publishActiveRaceTelemetry()
        Racing._updateRacerMarkers()
        Racing._updateDragLiveStraightness()

        if Racing._config and Racing._config.spectatorMode == true then
            local resolveTarget = math.max(18.0, tonumber(Racing._config.spectatorResolveTimeS or 0) or 0)
            if resolveTarget > 0 and Racing._raceTimer >= resolveTarget then
                Racing.finalizeSpectatorAmbientEvent()
            end
            return
        end

        if Racing._finishResolver then
            if Racing._tickFinishResolver() then
                return
            end
            return
        end

        if Racing._sequenceRaceState and Racing._sequenceRaceState.player and Racing._sequenceRaceState.player.finished then
            Racing._onPlayerFinish()
            return
        end

        if not (Racing._sequenceRaceState and Racing._sequenceRaceState.sequence) and Racing._checkFinishLineCrossing() then
            Racing._onPlayerFinish()
            return
        end

        _armNearFinishDNFGrace()
        local dnfTimeLimit = Racing._getDNFTimeLimit()
        if Racing._raceTimer > dnfTimeLimit then
            Racing._onPlayerDNF()
        end
        return
    end

    -- Quali timing
    if Racing._state == Racing.STATE.QUALI then
        Racing._raceTimer = Racing._raceTimer + dt

        if Racing._checkFinishLineCrossing() then
            Racing.endQuali()
        end
    end
end


local function buildOpenDraft(career, options)
    if type(career.config) ~= "table" then
        career.config = {}
    end

    local sourceType = type(options) == "table" and options.sourceType or "career_schedule"

    local draft = Racing._copyConfig(career.config)
    draft._eventSourceType = sourceType
    draft._lockToScheduledEvent = false
    draft._scheduledEvent = nil
    draft._scheduledEventId = nil

    if sourceType == "quick_race" then
        applySavedQuickRaceDraft(draft, career)
    end

    if not draft.routeMode then
        draft.routeMode = draft.useManualNodes and ROUTE_MODE_MANUAL or ROUTE_MODE_RANDOM
    end

    if draft.routeMode == ROUTE_MODE_ROOT and not draft.selectedRootId then
        local roots = _getNamedRoots()
        if #roots > 0 then
            draft.selectedRootId = roots[1].rootId
        end
    end

    -- Seed the draft with the current season's scheduled event/district/ruleset
    -- so the race the player sets up matches the championship round they are on.
    if sourceType ~= "quick_race" and MTE.Championships then
        MTE.Championships.applySeasonConfig(career, draft)
    end

    draft._startTypeTouched = false
    if not draft.defaultStartType then
        draft.defaultStartType = ((draft.raceType or "sprint") == "drag") and "sidebyside" or "grid"
    end

    normalizeDraftRouteConfig(draft)
    if sourceType == "quick_race" then
        normalizeQuickRaceConfig(draft, career)
    end

    return draft
end

function Racing.openConfig(options)
    local career = MTE.Careers and MTE.Careers.active()
    if not career then
        print("[NCM/Racing] No active career.")
        return false
    end

    Racing._career = career
    Racing._draft  = buildOpenDraft(career, options)
    Racing._activeEvent = nil
    Racing._pendingPreraceInit = nil

    Racing._state  = Racing.STATE.CONFIG
    return true
end

function Racing.openQuickRaceConfig()
    return Racing.openConfig({ sourceType = "quick_race" })
end

function Racing.closeConfig()
    if Racing._state ~= Racing.STATE.CONFIG then
        return false
    end
    Racing._state = Racing.STATE.IDLE
    Racing._draft = {}
    Racing._activeEvent = nil
    Racing._pendingPreraceInit = nil
    Racing._configTimer = 0
    return true
end

local function resolveRouteNodes(draft, routeCfg)
    local routeMode = normalizeDraftRouteConfig(draft)
    if routeMode == ROUTE_MODE_MANUAL then
        if MTE.ManualNodes and MTE.ManualNodes.hasPair and MTE.ManualNodes.hasPair() then
            local a, b = MTE.ManualNodes.getPair()
            return a, b, routeMode
        end
        return nil, nil, routeMode, "No saved manual route yet."
    end
    if routeMode == ROUTE_MODE_ROOT then
        local root = MTE and MTE.Roots and MTE.Roots.resolveRoot and MTE.Roots.resolveRoot(draft.selectedRootId) or nil
        if not root then
            return nil, nil, routeMode, "Pick a valid named root."
        end
        if root.isValid == false then
            return nil, nil, routeMode, "Selected named root is invalid."
        end
        local resolvedNodes = root.nodes or {}
        local nodeA = resolvedNodes[1] or _findNodeById(root.startNodeId)
        local nodeB = resolvedNodes[#resolvedNodes] or _findNodeById(root.endNodeId)
        if not nodeA or not nodeB then
            return nil, nil, routeMode, "Selected named root references missing nodes."
        end
        local sequenceRace = (#resolvedNodes > 2) and buildRootSequence(root, draft.lapCount) or nil
        draft.selectedRootId = root.rootId
        draft.selectedStartNodeId = nodeA.id
        draft.selectedFinishNodeId = nodeB.id
        return nodeA, nodeB, routeMode, nil, root, sequenceRace
    end
    if routeMode == ROUTE_MODE_PICKED then
        local nodeA = _findNodeById(draft.selectedStartNodeId)
        local nodeB = _findNodeById(draft.selectedFinishNodeId)
        if not nodeA or not nodeB then
            return nil, nil, routeMode, "Pick both a valid start and finish node."
        end
        if nodeA.id == nodeB.id then
            return nil, nil, routeMode, "Start and finish must be different nodes."
        end
        return nodeA, nodeB, routeMode
    end
    local nodeA, nodeB = Racing._pickRoute(routeCfg)
    return nodeA, nodeB, ROUTE_MODE_RANDOM
end

local function resolveEnduranceCircuitConfig(draft)
    local sourceType = draft.quickRaceEnduranceSourceType or "circuit"

    if sourceType == "route" then
        local root = MTE and MTE.Roots and MTE.Roots.resolveRoot
            and MTE.Roots.resolveRoot(draft.quickRaceEnduranceRootId) or nil
        if not root or #(root.nodes or {}) < 3 then
            return nil, nil, nil, "Select a route with at least 3 nodes."
        end
        local syntheticCircuit = {
            id = root.rootId,
            name = root.primaryLabel or root.rootId,
            region = root.districtLabel or root.region or "Unknown",
            checkpoints = root.nodeIds,
            isLoop = root.isLoop == true,
        }
        local resolved = root.nodes
        local sequenceRace = buildEnduranceSequence(syntheticCircuit, resolved, draft.lapCount)
        if not sequenceRace then
            return nil, nil, nil, "Unable to build endurance sequence from route."
        end
        return syntheticCircuit, resolved, sequenceRace, nil, root
    end

    local circuits = getQuickRaceKnockoutCircuits()
    local circuit = findQuickRaceEnduranceCircuit(draft.quickRaceEnduranceCircuitId, circuits) or circuits[1]
    if not circuit then
        return nil, nil, nil, "No endurance circuit is configured."
    end

    local resolved, err = Checkpoint.resolveCircuit(circuit, MTE and MTE.Nodes or {})
    if not resolved then
        return nil, nil, nil, err
    end
    if #resolved < 2 then
        return nil, nil, nil, "Endurance circuits need at least two checkpoints."
    end

    local sequenceRace = buildEnduranceSequence(circuit, resolved, draft.lapCount)
    if not sequenceRace then
        return nil, nil, nil, "Unable to build endurance sequence."
    end

    return circuit, resolved, sequenceRace, nil
end

function Racing.previewDraft(draftOverrides)
    local career = Racing._career or (MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active()) or nil
    if not career then return false, "No active career" end

    local baseDraft = Racing._draft
    if type(baseDraft) ~= "table" or next(baseDraft) == nil then
        baseDraft = Racing._copyConfig(career.config or {})
    end

    local draft = Racing._copyConfig(baseDraft)
    if type(draftOverrides) == "table" then
        for k, v in pairs(draftOverrides) do draft[k] = v end
    end

    local classOk, classErr = Racing._checkVehicleClass(draft.vehicleClass)
    if not classOk then return false, classErr end

    local todOk, todErr = Racing._checkTimeOfDay(draft.timeOfDay)
    if not todOk then return false, todErr end

    local eventSourceType = draft._eventSourceType or "career_schedule"
    local raceType = draft.raceType or "sprint"
    local requestedStartType = draft.defaultStartType
    if raceType == "drag" then
        requestedStartType = "sidebyside"
    end

    local routeCfg = Racing._copyConfig(draft)
    if raceType == "drag" then
        local dragMinDistance = _tuningValue("dragRouteMinDistanceM", draft)
        local dragMaxDistance = _tuningValue("dragRouteMaxDistanceM", draft)
        routeCfg.minDistanceM = math.max(dragMinDistance, math.min(routeCfg.minDistanceM or dragMinDistance, dragMaxDistance))
        routeCfg.maxDistanceM = math.max(routeCfg.minDistanceM, math.min(routeCfg.maxDistanceM or dragMaxDistance, dragMaxDistance))
    end

    local nodeA, nodeB, routeMode, routeErr, selectedRoot = nil, nil, ROUTE_MODE_RANDOM, nil, nil
    local selectedCircuit, resolvedCircuit, sequenceRace = nil, nil, nil
    if raceType == "endurance" then
        local enduranceRoot = nil
        selectedCircuit, resolvedCircuit, sequenceRace, routeErr, enduranceRoot = resolveEnduranceCircuitConfig(draft)
        if not sequenceRace then return false, routeErr or "No suitable endurance circuit found" end
        nodeA = resolvedCircuit[1]
        nodeB = sequenceRace.finishNode or resolvedCircuit[#resolvedCircuit]
        if enduranceRoot then
            selectedRoot = enduranceRoot
            routeMode = "root"
        else
            routeMode = "circuit"
        end
    else
        nodeA, nodeB, routeMode, routeErr, selectedRoot, sequenceRace = resolveRouteNodes(draft, routeCfg)
        if not nodeA or not nodeB then return false, routeErr or "No suitable route found" end
        if not sequenceRace and raceType == "sprint" and (tonumber(draft.lapCount) or 1) > 1 then
            sequenceRace = buildSprintLapSequence(nodeA, nodeB, draft.lapCount)
        end
    end

    local effectiveLapCount = sequenceRace and tonumber(sequenceRace.currentLapCount) or normalizeLapCount(
        raceType,
        draft.lapCount,
        (selectedCircuit and selectedCircuit.isLoop == true) or (selectedRoot and selectedRoot.isLoop == true))

    local requestedFieldSize = raceType == "drag"
        and math.max(1, math.min(draft.defaultFieldSize or _tuningValue("dragMaxAiRivals", draft), _tuningValue("dragMaxAiRivals", draft)))
        or (draft.defaultFieldSize or 8)
    if raceType == "endurance" and selectedCircuit then
        local maxAiFieldSize = KnockoutCircuits and KnockoutCircuits.getMaxAIFieldSize and KnockoutCircuits.getMaxAIFieldSize(selectedCircuit) or nil
        if type(maxAiFieldSize) == "number" then
            requestedFieldSize = math.max(1, math.min(requestedFieldSize, math.floor(maxAiFieldSize)))
        end
    end

    local provisionalConfig = {
        eventSourceType = eventSourceType,
        _scheduledEventId = draft._scheduledEventId,
        gridLateralShiftM = draft.gridLateralShiftM,
        startType    = requestedStartType or "grid",
        fieldSize    = requestedFieldSize,
        allowStakes  = draft.allowStakes,
        allowCombat  = draft.allowCombat,
        qualiEnabled = draft.qualiEnabled,
        spectatorMode = draft.spectatorMode == true,
        vehicleClass = draft.vehicleClass,
        timeOfDay    = draft.timeOfDay,
        raceType     = raceType,
        lapCount     = effectiveLapCount,
        forcedEntrantDriverIds = Racing._copyConfig(draft.forcedEntrantDriverIds or nil),
        quickRacePrestigeMin = draft.quickRacePrestigeMin,
        quickRacePrestigeMax = draft.quickRacePrestigeMax,
        quickRacePrestigeWeighting = draft.quickRacePrestigeWeighting,
        quickRaceAllowBossOutlier = draft.quickRaceAllowBossOutlier,
        useManualNodes = routeMode == ROUTE_MODE_MANUAL,
        routeMode    = routeMode,
        preferredRegions = normalizePreferredRegions(draft.preferredRegions),
        selectedRootId = draft.selectedRootId,
        selectedStartNodeId = draft.selectedStartNodeId,
        selectedFinishNodeId = draft.selectedFinishNodeId,
        quickRaceEnduranceCircuitId = selectedCircuit and selectedCircuit.id or draft.quickRaceEnduranceCircuitId,
        rootId       = selectedRoot and selectedRoot.rootId or nil,
        rootDisplayName = selectedRoot and selectedRoot.primaryLabel or nil,
        subtitleLabel = selectedRoot and selectedRoot.secondaryLabel or nil,
        rootNodeIds  = selectedRoot and Racing._copyConfig(selectedRoot.nodeIds or {}) or nil,
        nodeA        = nodeA,
        nodeB        = nodeB,
        district     = (selectedCircuit and selectedCircuit.region) or (selectedRoot and (selectedRoot.districtLabel or selectedRoot.region)) or nodeA.region,
        distance     = sequenceRace and sequenceRace.totalDistance or Racing._estimateDistance(nodeA, nodeB),
        sequenceRace = sequenceRace,
    }
    local startDelay = START_DELAYS[provisionalConfig.startType or "grid"] or 0.0
    if raceType ~= "endurance" then
        resolveRouteRecord(provisionalConfig)
    else
        provisionalConfig.trackName = selectedCircuit and selectedCircuit.name or (selectedRoot and selectedRoot.primaryLabel) or provisionalConfig.trackName
        provisionalConfig.routeId = selectedCircuit and ("endurance:" .. tostring(selectedCircuit.id)) or provisionalConfig.routeId
        provisionalConfig.titleLabel = provisionalConfig.titleLabel or provisionalConfig.trackName
    end
    if selectedRoot and type(selectedRoot.profileSettings) == "table" then
        provisionalConfig.rootProfileSettings = selectedRoot.profileSettings
    elseif provisionalConfig.rootId and MTE and MTE.Roots and MTE.Roots.resolveRoot then
        local resolvedRoot = MTE.Roots.resolveRoot(provisionalConfig.rootId)
        provisionalConfig.rootProfileSettings = resolvedRoot and resolvedRoot.profileSettings or nil
    end
    applySpecFieldToConfig(draft, provisionalConfig, raceType)
    if raceType == "drag" then
        local dragStrip = _buildDragStripDescriptor(provisionalConfig, requestedFieldSize)
        if not dragStrip.eligible then
            return false, dragStrip.rejectReason or "Selected route is not valid for drag mode."
        end
        provisionalConfig.fieldSize = dragStrip.adjustedFieldSize
        provisionalConfig.dragStrip = dragStrip
    end
    if not provisionalConfig.trackName and MTE.Tracks then
        provisionalConfig.trackName = MTE.Tracks.getRouteName(nodeA, nodeB)
    end

    local drivers = Racing._buildField(career, provisionalConfig)
    local field = Racing._buildRaceEntries(drivers, provisionalConfig)

    Racing._career = career
    Racing._draft = draft
    return true, {
        draft = draft,
        config = provisionalConfig,
        field = field,
        nodeA = nodeA,
        nodeB = nodeB,
        startDelay = startDelay,
    }
end

function Racing.confirmConfig(draftOverrides)
    local career = Racing._career
    if not career then return false, "No active career" end

  local function buildPreviewFromDraft(baseDraft, overrides)
      local draft = Racing._copyConfig(baseDraft or {})

      if type(overrides) == "table" then
          for k, v in pairs(overrides) do draft[k] = v end
      end

      local classOk, classErr = Racing._checkVehicleClass(draft.vehicleClass)
      if not classOk then return false, classErr end

      local todOk, todErr = Racing._checkTimeOfDay(draft.timeOfDay)
      if not todOk then return false, todErr end

      local eventSourceType = draft._eventSourceType or "career_schedule"
      local raceType = draft.raceType or "sprint"
      local requestedStartType = draft.defaultStartType
      if raceType == "drag" then
          requestedStartType = "sidebyside"
      end

      local routeCfg = Racing._copyConfig(draft)
      if raceType == "drag" then
          local dragMinDistance = _tuningValue("dragRouteMinDistanceM", draft)
          local dragMaxDistance = _tuningValue("dragRouteMaxDistanceM", draft)
          routeCfg.minDistanceM = math.max(dragMinDistance, math.min(routeCfg.minDistanceM or dragMinDistance, dragMaxDistance))
          routeCfg.maxDistanceM = math.max(routeCfg.minDistanceM, math.min(routeCfg.maxDistanceM or dragMaxDistance, dragMaxDistance))
      end

      local nodeA, nodeB, routeMode, routeErr, selectedRoot = nil, nil, ROUTE_MODE_RANDOM, nil, nil
      local selectedCircuit, resolvedCircuit, sequenceRace = nil, nil, nil
      if raceType == "endurance" then
          local enduranceRoot = nil
          selectedCircuit, resolvedCircuit, sequenceRace, routeErr, enduranceRoot = resolveEnduranceCircuitConfig(draft)
          if not sequenceRace then return false, routeErr or "No suitable endurance circuit found" end
          nodeA = resolvedCircuit[1]
          nodeB = sequenceRace.finishNode or resolvedCircuit[#resolvedCircuit]
          if enduranceRoot then
              selectedRoot = enduranceRoot
              routeMode = "root"
          else
              routeMode = "circuit"
          end
      else
          nodeA, nodeB, routeMode, routeErr, selectedRoot, sequenceRace = resolveRouteNodes(draft, routeCfg)
          if not nodeA or not nodeB then return false, routeErr or "No suitable route found" end
          if not sequenceRace and raceType == "sprint" and (tonumber(draft.lapCount) or 1) > 1 then
              sequenceRace = buildSprintLapSequence(nodeA, nodeB, draft.lapCount)
          end
      end

      local effectiveLapCount = sequenceRace and tonumber(sequenceRace.currentLapCount) or normalizeLapCount(
          raceType,
          draft.lapCount,
          (selectedCircuit and selectedCircuit.isLoop == true) or (selectedRoot and selectedRoot.isLoop == true))

      local requestedFieldSize = raceType == "drag"
          and math.max(1, math.min(draft.defaultFieldSize or _tuningValue("dragMaxAiRivals", draft), _tuningValue("dragMaxAiRivals", draft)))
          or (draft.defaultFieldSize or 8)
      if raceType == "endurance" and selectedCircuit then
          local maxAiFieldSize = KnockoutCircuits and KnockoutCircuits.getMaxAIFieldSize and KnockoutCircuits.getMaxAIFieldSize(selectedCircuit) or nil
          if type(maxAiFieldSize) == "number" then
              requestedFieldSize = math.max(1, math.min(requestedFieldSize, math.floor(maxAiFieldSize)))
          end
      end

      local provisionalConfig = {
          eventSourceType = eventSourceType,
          _scheduledEventId = draft._scheduledEventId,
          gridLateralShiftM = draft.gridLateralShiftM,
          startType    = requestedStartType or "grid",
          fieldSize    = requestedFieldSize,
          allowStakes  = draft.allowStakes,
          allowCombat  = draft.allowCombat,
          qualiEnabled = draft.qualiEnabled,
          spectatorMode = draft.spectatorMode == true,
          vehicleClass = draft.vehicleClass,
          timeOfDay    = draft.timeOfDay,
          raceType     = raceType,
          lapCount     = effectiveLapCount,
          forcedEntrantDriverIds = Racing._copyConfig(draft.forcedEntrantDriverIds or nil),
          quickRacePrestigeMin = draft.quickRacePrestigeMin,
          quickRacePrestigeMax = draft.quickRacePrestigeMax,
          quickRacePrestigeWeighting = draft.quickRacePrestigeWeighting,
          quickRaceAllowBossOutlier = draft.quickRaceAllowBossOutlier,
          useManualNodes = routeMode == ROUTE_MODE_MANUAL,
          routeMode    = routeMode,
          preferredRegions = normalizePreferredRegions(draft.preferredRegions),
          selectedRootId = draft.selectedRootId,
          selectedStartNodeId = draft.selectedStartNodeId,
          selectedFinishNodeId = draft.selectedFinishNodeId,
          quickRaceEnduranceCircuitId = selectedCircuit and selectedCircuit.id or draft.quickRaceEnduranceCircuitId,
          rootId       = selectedRoot and selectedRoot.rootId or nil,
          rootDisplayName = selectedRoot and selectedRoot.primaryLabel or nil,
          subtitleLabel = selectedRoot and selectedRoot.secondaryLabel or nil,
          rootNodeIds  = selectedRoot and Racing._copyConfig(selectedRoot.nodeIds or {}) or nil,
          nodeA        = nodeA,
          nodeB        = nodeB,
          district     = (selectedCircuit and selectedCircuit.region) or (selectedRoot and (selectedRoot.districtLabel or selectedRoot.region)) or nodeA.region,
          distance     = sequenceRace and sequenceRace.totalDistance or Racing._estimateDistance(nodeA, nodeB),
          sequenceRace = sequenceRace,
      }
      local startDelay = START_DELAYS[provisionalConfig.startType or "grid"] or 0.0
      if raceType ~= "endurance" then
          resolveRouteRecord(provisionalConfig)
      else
          provisionalConfig.trackName = selectedCircuit and selectedCircuit.name or (selectedRoot and selectedRoot.primaryLabel) or provisionalConfig.trackName
          provisionalConfig.routeId = selectedCircuit and ("endurance:" .. tostring(selectedCircuit.id)) or provisionalConfig.routeId
          provisionalConfig.titleLabel = provisionalConfig.titleLabel or provisionalConfig.trackName
      end
      if selectedRoot and type(selectedRoot.profileSettings) == "table" then
          provisionalConfig.rootProfileSettings = selectedRoot.profileSettings
      elseif provisionalConfig.rootId and MTE and MTE.Roots and MTE.Roots.resolveRoot then
          local resolvedRoot = MTE.Roots.resolveRoot(provisionalConfig.rootId)
          provisionalConfig.rootProfileSettings = resolvedRoot and resolvedRoot.profileSettings or nil
      end
      applySpecFieldToConfig(draft, provisionalConfig, raceType)
      if raceType == "drag" then
          local dragStrip = _buildDragStripDescriptor(provisionalConfig, requestedFieldSize)
          if not dragStrip.eligible then
              return false, dragStrip.rejectReason or "Selected route is not valid for drag mode."
          end
          provisionalConfig.fieldSize = dragStrip.adjustedFieldSize
          provisionalConfig.dragStrip = dragStrip
      end
      if not provisionalConfig.trackName and MTE.Tracks then
          provisionalConfig.trackName = MTE.Tracks.getRouteName(nodeA, nodeB)
      end

      local drivers = Racing._buildField(career, provisionalConfig)
      local field = Racing._buildRaceEntries(drivers, provisionalConfig)

      return true, {
          draft = draft,
          config = provisionalConfig,
          field = field,
          nodeA = nodeA,
          nodeB = nodeB,
          startDelay = startDelay,
      }
  end

  local ok, previewOrErr = buildPreviewFromDraft(Racing._draft, draftOverrides)
  if not ok then return false, previewOrErr end
  local preview = previewOrErr

  Racing._draft = preview.draft
  Racing._config = preview.config
  local nodeA = preview.nodeA
  local nodeB = preview.nodeB
  local startDelay = preview.startDelay
  Racing._field = preview.field
    Racing._spawnRunId = _nextSpawnRunId()
    Racing._logSpawnRunMarker("confirm_config", LIVE_RIVALS_POST_START and "post_start_live_rivals" or "prerace_grid", {
        nodeA = nodeA,
        nodeB = nodeB,
        fieldCount = #Racing._field,
        source = "confirm_config",
    })
    print(i18n.format(
        "[NCM/Racing] confirmConfig: route=%s start=%s finish=%s field=%d quali=%s startType=%s",
        tostring(Racing._config.routeMode or "?"),
        tostring(nodeA and nodeA.name or "?"),
        tostring(nodeB and nodeB.name or "?"),
        tonumber(#Racing._field or 0),
        tostring(Racing._draft.qualiEnabled),
        tostring(Racing._config.startType or "grid")))
    Racing._state = Racing.STATE.PRERACE
    Racing._results                 = {}
    Racing._raceTimer               = 0.0
    Racing._stakeAmount             = 0
    Racing._qualiTime               = nil
    Racing._finishNode              = nil
    Racing._finishDir               = nil
    Racing._prevFinishDot           = nil
    Racing._aiPrevDot               = {}
    Racing._aiFinished              = {}
    Racing._aiFinishTime            = {}
    Racing._telemetrySessionId      = nil
    Racing._lastCountdownPhase      = nil
    Racing._countdownDuration       = 3.0
    Racing._countdownUseLights      = true
    Racing._gridReadyEmitted        = false
    Racing._gridSpawnPending        = false
    Racing._resetPostStartLiveSpawn("confirm_config")
    Racing._resetGhostFallback("confirm_config")
    Racing._autoStageTriggered      = false
    Racing._gridFormingTriggered    = false
    Racing._stageSource             = nil
    Racing._stageCountdown          = nil
    Racing._prelaunchCountdown      = nil
    Racing._postSnapCooldown        = 0.0
    Racing._postSnapNotifyTimer     = 0.0
    Racing._trafficClearRetryTimer  = 0.0
    Racing._nearFinishDNFGraceArmed = false
    Racing._nearFinishDNFGraceUntil = nil
    Racing._finishResolver          = nil
    Racing._sequenceRaceState       = nil
    Racing._resetGridSpawnWindow("confirm_config")
    Racing._resetRollingStartState("confirm_config")
    _clearRacerMarkers()

    Racing._config.expectedTime = (Racing._config.distance / _tuningValue("expectedPlayerRaceSpeedMps", Racing._config)) + startDelay
    if Racing._config.spectatorMode == true then
        Racing._config.spectatorResolveTimeS = math.max(18.0, (tonumber(Racing._config.expectedTime or 0) * 1.45) + 6.0)
    end

    -- Defer AI spawn to after quali if enabled; otherwise compute
    -- final grid order now so the single spawn is authoritative.
    if not Racing._draft.qualiEnabled then
        -- Compute AI times and sort for grid order
        print("[NCM/Racing] confirmConfig: computing whole-grid order")
        local hMult = MTE.Careers and MTE.Careers.handicapMult(career) or 1.0
        for _, entry in ipairs(Racing._field) do
            entry.aiTime = Racing._computeAITime(entry, Racing._config, hMult)
        end
        table.sort(Racing._field, function(a, b) return a.aiTime < b.aiTime end)
        for i, entry in ipairs(Racing._field) do entry.gridPos = i end
        -- Assign stable player grid position
        Racing._qualiGridPos = math.random(#Racing._field + 1)
        print(i18n.format(
            "[NCM/Racing] confirmConfig: whole-grid order ready playerGrid=%d",
            tonumber(Racing._qualiGridPos or 0)))

        if MTE.AIVehicles and MTE.AIVehicles.noteWorldDisruption then
            MTE.AIVehicles.noteWorldDisruption("confirm_config")
        end
        Racing._startGridPrewarm("confirm_config")
        print("[NCM/Racing] confirmConfig: whole-grid prewarm armed")
    end

    Racing._pendingPreraceInit = {
        frames = 1,
        reason = "confirm_config",
    }
    return true, nil
end

function Racing.stageCareerEvent()
    local career = MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active() or nil
    if not career then
        return false, "No active career"
    end
    if Racing._state ~= Racing.STATE.IDLE then
        return false, "Finish or cancel the current race first."
    end

    Racing._career = career
    Racing._draft = buildOpenDraft(career, { sourceType = "career_schedule" })
    Racing._activeEvent = nil
    Racing._pendingPreraceInit = nil

    return Racing.confirmConfig()
end

function Racing.setStake(amount)
    local career = Racing._career
    local cfg    = Racing._config
    -- allowStakes from the active race config is authoritative; when no config
    -- exists yet, fall back to the career setting so Career tab works normally.
    local stakesAllowed = cfg and cfg.allowStakes
    if stakesAllowed == nil then
        stakesAllowed = career and career.config and career.config.allowStakes
    end
    if not stakesAllowed then return 0 end
    local maxStake = MTE.Careers.maxStake(career)
    Racing._stakeAmount = math.max(0, math.min(maxStake, math.floor(amount)))
    Racing._stakeEscrowed = false
    return Racing._stakeAmount
end

function Racing.setStakeEscrowed(amount, escrowed)
    local actual = Racing.setStake(amount)
    Racing._stakeEscrowed = escrowed == true and actual > 0
    return actual
end

function Racing.startQuali()
    if Racing._state ~= Racing.STATE.PRERACE then return false, "Race is not staged." end
    local ok, err = Racing._isPlayerReadyForQuali()
    if not ok then
        _notify(err or "Qualifying cannot start yet.", 1.8)
        return false, err
    end
    Racing._qualiTime  = nil
    Racing._raceTimer  = 0.0
    Racing._state                   = Racing.STATE.QUALI
    Racing._autoStageTriggered      = false
    Racing._gridFormingTriggered    = false
    Racing._stageSource             = nil
    Racing._stageCountdown          = nil
    Racing._prelaunchCountdown      = nil
    Racing._postSnapCooldown        = 0.0
    Racing._postSnapNotifyTimer     = 0.0
    Racing._gridSpawnPending        = false
    Racing._finishResolver          = nil
    Racing._resetPostStartLiveSpawn("quali_start")
    Racing._resetGhostFallback("quali_start")
    Racing._resetGridSpawnWindow("quali_start")
    Racing._resetRollingStartState("quali_start")
    _clearRacerMarkers()
    Racing._finishNode = Racing._config.nodeB
    Racing._setupFinishLine()
    Racing._qualiCountdown = nil
    Racing._qualiLastTickSec = nil
    MTE.Events.emit("QualiStart", { config = Racing._config })
    print("[NCM/Racing] Quali started.")
    return true
end

function Racing.endQuali()
    Racing._qualiTime = Racing._raceTimer
    Racing._sortFieldByQuali(Racing._qualiTime)
    -- Count how many AIs beat the player's quali time to determine grid position
    local gridPos = 1
    for _, d in ipairs(Racing._field) do
        if (d._qualiEst or 999) < Racing._qualiTime then gridPos = gridPos + 1 end
    end
    Racing._qualiGridPos = gridPos

    -- Queue AI grid spawn in final qualifying order; actual spawn waits for V on the line.
    if MTE.AIVehicles and MTE.AIVehicles.noteWorldDisruption then
        MTE.AIVehicles.noteWorldDisruption("quali_end")
    end
    Racing._startGridPrewarm("quali_end")

    Racing._state              = Racing.STATE.PRERACE
    Racing._stageCountdown     = nil
    Racing._prelaunchCountdown = nil
    MTE.Events.emit("QualiEnd", { playerTime = Racing._qualiTime, gridPos = gridPos })
    print(i18n.format("[NCM/Racing] Quali: %.2fs  P%d", Racing._qualiTime, gridPos))
end

function Racing.startRace()
    if Racing._state ~= Racing.STATE.PRERACE then return false end
    local spectatorMode = Racing._config and Racing._config.spectatorMode == true

    -- Block if qualifying is required but not yet completed
    if not spectatorMode and Racing._config.qualiEnabled and not Racing._qualiTime then
        _notify("Finish qualifying before starting the race.", 1.8)
        return false
    end

    -- Block start while AI grid is still spawning
    if Racing._gridSpawnPending or (MTE.AIVehicles and MTE.AIVehicles.isSpawning()) then
        _notify("AI rivals are still forming up on the grid.", 1.8)
        return false
    end

    local gridStartBlocker = Racing._getGridCountdownBlocker()
    if gridStartBlocker then
        Racing._prelaunchCountdown = nil
        print(i18n.format(
            "[NCM/Racing] startRace blocked: %s",
            tostring(gridStartBlocker)))
        if string.find(gridStartBlocker, "grid_failed:", 1, true) == 1 then
            _notify("AI grid failed to form. Race start cancelled.", 1.8)
        elseif _manualGridModeEnabled() and gridStartBlocker == "grid_empty" then
            _notify("Manual Grid Mode: spawn 1 or 2 rivals ahead before starting.", 1.8)
        else
            _notify("AI grid is not ready. Countdown cancelled.", 1.8)
        end
        return false
    end

    if not spectatorMode then
        local ready, err = Racing._isPlayerReadyForRaceStart()
        if not ready then
            _notify(err or "Stage on the start line before launching.", 1.8)
            return false
        end
    end

    if not spectatorMode and Racing._stakeAmount > 0 and not Racing._stakeEscrowed then
        pcall(function() Game.AddToInventory("Items.money", -Racing._stakeAmount) end)
    end

    if Racing._qualiTime then
        -- Qualifying ran: anchor race time to quali estimate with small variance
        for _, driver in ipairs(Racing._field) do
            if driver._qualiEst then
                driver.aiTime = driver._qualiEst * (0.97 + math.random() * 0.06)
            end
        end
    end
    -- Non-quali: aiTimes were already computed and field sorted in confirmConfig().
    -- Grid order, gridPos, player position, and spawn are all authoritative from preview.

    Racing._finishNode = Racing._config.nodeB
    Racing._setupFinishLine()
    local countdownSeconds = _getRaceCountdownSeconds(Racing._config)
    Racing._countdownDuration = countdownSeconds
    Racing._countdownUseLights = _countdownUsesLights(Racing._config)
    Racing._raceTimer  = countdownSeconds
    Racing._state      = Racing.STATE.COUNTDOWN
    resetSequenceRaceState()
    beginTelemetrySession()
    _syncRaceState("countdown")
    if MTE.Mappins then MTE.Mappins.setGpsWaypoint(Racing._config.nodeB) end
    MTE.Events.emit("RaceCountdown", {
        seconds = countdownSeconds,
        startType = Racing._config.startType,
        useLights = Racing._countdownUseLights,
    })
    return true
end

function Racing.abort()
    abandonTelemetrySession("race_abort", false)
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end
    -- Quest nav: deactivate quest objective
    _queueQuestEvent(false)
    local s = Racing._state
    local spectatorMode = Racing._config and Racing._config.spectatorMode == true
    local isForfeitState = not spectatorMode and (s == Racing.STATE.QUALI or s == Racing.STATE.COUNTDOWN or s == Racing.STATE.RACING)
    _syncRaceState("idle")
    if not isForfeitState and Betting and Betting.onRaceCancelled and Racing._career then
        local ok, err = pcall(Betting.onRaceCancelled, Racing._career, s)
        if not ok then
            print("[NCM/Racing] Betting.onRaceCancelled failed: " .. tostring(err))
        end
    end
    if isForfeitState then
        -- QUALI, COUNTDOWN, and RACING all count as a live forfeit/DNF.
        Racing._onPlayerDNF()
    else
        -- CONFIG and PRERACE remain clean exits with no DNF.
        Racing._state                   = Racing.STATE.IDLE
        Racing._field                   = {}
        Racing._results                 = {}
        Racing._stakeAmount             = 0
        Racing._stakeEscrowed           = false
        Racing._qualiTime               = nil
        Racing._qualiGridPos            = nil
        Racing._finishNode              = nil
        Racing._finishDir               = nil
        Racing._prevFinishDot           = nil
        Racing._aiPrevDot               = {}
        Racing._aiFinished              = {}
        Racing._aiFinishTime            = {}
        Racing._telemetrySessionId      = nil
        Racing._qualiProximityTriggered = false
        Racing._qualiCountdown          = nil
        Racing._qualiLastTickSec        = nil
        Racing._raceTimer               = 0
        Racing._lastCountdownPhase      = nil
        Racing._countdownDuration       = 3.0
        Racing._countdownUseLights      = true
        Racing._gridSpawnPending        = false
        Racing._resetPostStartLiveSpawn("abort")
        Racing._resetGhostFallback("abort")
        Racing._autoStageTriggered      = false
        Racing._gridFormingTriggered    = false
        Racing._stageSource             = nil
        Racing._stageCountdown          = nil
        Racing._prelaunchCountdown      = nil
        Racing._postSnapCooldown        = 0.0
        Racing._postSnapNotifyTimer     = 0.0
        Racing._finishResolver          = nil
        Racing._resetGridSpawnWindow("abort")
        Racing._resetRollingStartState("abort")
    end
    if spectatorMode and Racing._activeEvent and Racing._activeEvent.sourceType == "ambient_schedule" and MTE and MTE.AmbientRaces and MTE.AmbientRaces.onLiveRaceClosed then
        pcall(MTE.AmbientRaces.onLiveRaceClosed, Racing._career, Racing._activeEvent.eventId, false)
    end
    Racing._activeEvent = nil
    _clearRacerMarkers()
    _restoreZone()
end

function Racing.closeResults()
    abandonTelemetrySession("results_closed", false)
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end
    -- Quest nav: deactivate quest objective
    _queueQuestEvent(false)
    _syncRaceState("idle")
    Racing._state                   = Racing.STATE.IDLE
    Racing._field                   = {}
    Racing._results                 = {}
    Racing._stakeAmount             = 0
    Racing._stakeEscrowed           = false
    Racing._qualiTime               = nil
    Racing._qualiGridPos            = nil
    Racing._finishNode              = nil
    Racing._finishDir               = nil
    Racing._prevFinishDot           = nil
    Racing._aiPrevDot               = {}
    Racing._aiFinished              = {}
    Racing._aiFinishTime            = {}
    Racing._telemetrySessionId      = nil
    Racing._qualiProximityTriggered = false
    Racing._qualiCountdown          = nil
    Racing._qualiLastTickSec        = nil
    Racing._raceTimer               = 0.0
    Racing._lastCountdownPhase      = nil
    Racing._countdownDuration       = 3.0
    Racing._countdownUseLights      = true
    Racing._gridSpawnPending        = false
    Racing._resetPostStartLiveSpawn("close_results")
    Racing._resetGhostFallback("close_results")
    Racing._autoStageTriggered      = false
    Racing._gridFormingTriggered    = false
    Racing._stageSource             = nil
    Racing._stageCountdown          = nil
    Racing._prelaunchCountdown      = nil
    Racing._postSnapCooldown        = 0.0
    Racing._postSnapNotifyTimer     = 0.0
    Racing._finishResolver          = nil
    Racing._resetGridSpawnWindow("close_results")
    Racing._resetRollingStartState("close_results")
    Racing._activeEvent             = nil
    _clearRacerMarkers()
    _restoreZone()
end

local function _ambientPromotionEntrants(event)
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

function Racing.stageAmbientEvent(event, options)
    options = options or {}
    if type(event) ~= "table" then
        return false, "No promotable ambient heat is ready."
    end
    if tostring(event.raceType or "sprint") == "knockout" then
        return false, "Foreman will not promote knockout heats live yet."
    end
    if Racing._state ~= Racing.STATE.IDLE then
        return false, "Finish or cancel the current race flow before staging an ambient heat."
    end

    local forcedEntrants = _ambientPromotionEntrants(event)
    if #forcedEntrants <= 0 then
        return false, "Ambient heat has no eligible entrants to stage live."
    end

    local openOk = Racing.openConfig({ sourceType = "ambient_schedule" })
    if not openOk then
        return false, "Could not open the ambient race bridge."
    end

    local raceType = tostring(event.raceType or "sprint")
    if raceType ~= "drag" then
        raceType = "sprint"
    end

    local confirmOk, confirmErr = Racing.confirmConfig({
        raceType = raceType,
        defaultStartType = raceType == "drag" and "sidebyside" or "grid",
        defaultFieldSize = math.max(#forcedEntrants, tonumber(event.fieldSize) or #forcedEntrants),
        preferredRegions = { event.district },
        allowCombat = false,
        allowStakes = false,
        qualiEnabled = false,
        spectatorMode = options.spectator == true,
        forcedEntrantDriverIds = forcedEntrants,
        _scheduledEventId = event.eventId,
        titleLabel = event.titleLabel or event.district,
        subtitleLabel = event.district,
    })
    if not confirmOk then
        if Racing._state == Racing.STATE.CONFIG then
            Racing.closeConfig()
        end
        return false, confirmErr
    end

    Racing._activeEvent = Racing._copyConfig(event)
    Racing._activeEvent.sourceType = "ambient_schedule"
    Racing._activeEvent.ambientPromotion = true
    Racing._activeEvent.spectatorMode = options.spectator == true
    return true, i18n.format(
        "Live ambient heat staged in %s. Route in and use the Foreman board to start or scrub it.",
        tostring(event.district or "Unknown"))
end

function Racing.finalizeSpectatorAmbientEvent()
    local activeEvent = Racing._activeEvent or nil
    if not activeEvent or activeEvent.sourceType ~= "ambient_schedule" then
        return false, "No live ambient spectate is active."
    end
    if not (MTE and MTE.AmbientRaces and MTE.AmbientRaces.resolveLivePromotedEvent) then
        return false, "ambient_bridge_unavailable"
    end

    local ok, message = MTE.AmbientRaces.resolveLivePromotedEvent(Racing._career, activeEvent.eventId)
    if not ok then
        return false, message
    end

    abandonTelemetrySession("spectator_resolved", false)
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end
    _queueQuestEvent(false)
    _syncRaceState("idle")
    Racing._state                   = Racing.STATE.IDLE
    Racing._field                   = {}
    Racing._results                 = {}
    Racing._stakeAmount             = 0
    Racing._stakeEscrowed           = false
    Racing._qualiTime               = nil
    Racing._qualiGridPos            = nil
    Racing._finishNode              = nil
    Racing._finishDir               = nil
    Racing._prevFinishDot           = nil
    Racing._aiPrevDot               = {}
    Racing._aiFinished              = {}
    Racing._aiFinishTime            = {}
    Racing._telemetrySessionId      = nil
    Racing._qualiProximityTriggered = false
    Racing._qualiCountdown          = nil
    Racing._qualiLastTickSec        = nil
    Racing._raceTimer               = 0.0
    Racing._lastCountdownPhase      = nil
    Racing._countdownDuration       = 3.0
    Racing._countdownUseLights      = true
    Racing._gridSpawnPending        = false
    Racing._resetPostStartLiveSpawn("spectator_finalize")
    Racing._resetGhostFallback("spectator_finalize")
    Racing._autoStageTriggered      = false
    Racing._gridFormingTriggered    = false
    Racing._stageSource             = nil
    Racing._stageCountdown          = nil
    Racing._prelaunchCountdown      = nil
    Racing._postSnapCooldown        = 0.0
    Racing._postSnapNotifyTimer     = 0.0
    Racing._finishResolver          = nil
    Racing._resetGridSpawnWindow("spectator_finalize")
    Racing._resetRollingStartState("spectator_finalize")
    Racing._activeEvent             = nil
    _clearRacerMarkers()
    _restoreZone()
    return true, message
end

--- Restart the same route with fresh AI times. Only valid from RESULTS.
function Racing.restartRace()
    if Racing._state ~= Racing.STATE.RESULTS then return false end
    local career = Racing._career
    local config = Racing._config
    if not career or not config or not config.nodeA or not config.nodeB then
        Racing.closeResults()
        return false
    end

    Racing._telemetrySessionId = nil
    resolveRouteRecord(config)

    -- Clean up previous race
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end

    -- Rebuild field & reset state
    local drivers        = Racing._buildField(career, config)
    Racing._field        = Racing._buildRaceEntries(drivers, Racing._config)
    Racing._results      = {}
    Racing._stakeAmount  = 0
    Racing._stakeEscrowed = false
    Racing._qualiTime               = nil
    Racing._qualiGridPos            = nil
    Racing._finishNode              = nil
    Racing._qualiProximityTriggered = false
    Racing._qualiCountdown          = nil
    Racing._qualiLastTickSec        = nil
    Racing._raceTimer               = 0.0
    Racing._finishDir               = nil
    Racing._prevFinishDot           = nil
    Racing._aiPrevDot               = {}
    Racing._aiFinished              = {}
    Racing._aiFinishTime            = {}
    Racing._telemetrySessionId      = nil
    Racing._lastCountdownPhase      = nil
    Racing._countdownDuration       = 3.0
    Racing._countdownUseLights      = true
    Racing._gridSpawnPending        = false
    Racing._resetPostStartLiveSpawn("restart_race")
    Racing._resetGhostFallback("restart_race")
    Racing._autoStageTriggered      = false
    Racing._gridFormingTriggered    = false
    Racing._stageSource             = nil
    Racing._stageCountdown          = nil
    Racing._prelaunchCountdown      = nil
    Racing._postSnapCooldown        = 0.0
    Racing._postSnapNotifyTimer     = 0.0
    Racing._resetGridSpawnWindow("restart_race")
    Racing._resetRollingStartState("restart_race")
    -- Re-seize zone for the restarted race
    _suppressZone()

    -- Re-place mappins
    local cfg = MTE.Settings and MTE.Settings.current or {}
    if cfg.raceMappins ~= false and MTE.Mappins then
        MTE.Mappins.showRaceMarkers(config.nodeA, config.nodeB)
        MTE.Mappins.setGpsWaypoint(config.nodeA)
    end

    -- Quest nav: re-activate quest objective for restarted race
    _queueQuestEvent(true, config.trackName or "")
    _syncRaceState("prerace")
    _sendSMS(2) -- race_confirmed

    -- Recompute grid order and spawn for non-quali path (mirrors confirmConfig logic).
    -- Quali path: spawn is intentionally deferred until after qualifying runs.
    if not config.qualiEnabled then
        local hMult = MTE.Careers and MTE.Careers.handicapMult(career) or 1.0
        for _, entry in ipairs(Racing._field) do
            entry.aiTime = Racing._computeAITime(entry, Racing._config, hMult)
        end
        table.sort(Racing._field, function(a, b) return a.aiTime < b.aiTime end)
        for i, entry in ipairs(Racing._field) do entry.gridPos = i end
        Racing._qualiGridPos = math.random(#Racing._field + 1)

        if MTE.AIVehicles and MTE.AIVehicles.noteWorldDisruption then
            MTE.AIVehicles.noteWorldDisruption("restart_race")
        end
        Racing._startGridPrewarm("restart_race")
        print("[NCM/Racing] restartRace: whole-grid prewarm armed")
    end

    Racing._state = Racing.STATE.PRERACE
    Racing._gridReadyEmitted = false
    MTE.Events.emit("RacePreview", { config = config, field = Racing._field })
    print("[NCM/Racing] Race restarted - same route, new field.")
    return true
end

-- ── Internal: race resolution ─────────────────────────────────

function Racing._onPlayerFinish()
    if Racing._finishResolver then
        return
    end

    local playerRawTime = Racing._raceTimer
    local playerTime = _getDragOfficialTime(playerRawTime, Racing._config)
    local scoredField, visibleIds = Racing._getScoredField()
    local waitTarget = _tuningValue("finishResolveMinWaitS", Racing._config)

    if visibleIds then
        for _, entry in ipairs(scoredField or {}) do
            local id = entry and (entry.driverId or entry.id) or nil
            if id and visibleIds[id] and not Racing._aiFinishTime[id] then
                local projectedGap = math.max(0.25, (tonumber(entry.aiTime) or playerTime) - playerTime)
                waitTarget = math.max(
                    waitTarget,
                    math.min(projectedGap, _tuningValue("finishResolveVisibleGapCapS", Racing._config))
                        + _tuningValue("finishResolveGapBufferS", Racing._config))
            end
        end
    end

    Racing._finishResolver = {
        playerTime = playerTime,
        rawPlayerTime = playerRawTime,
        startedAt = Racing._raceTimer,
        waitTarget = math.min(_tuningValue("finishResolveMaxWaitS", Racing._config), waitTarget),
        scoredField = scoredField,
        visibleIds = visibleIds,
    }

    local dragPenalty = _getDragStripPenaltySeconds(Racing._config)
    if dragPenalty > 0.01 and tostring(Racing._config and Racing._config.raceType or "sprint") == "drag" then
        _notify(i18n.format("STRAIGHTNESS PENALTY  +%.2fs", dragPenalty), 2.4)
    end

    local pending = Racing._countPendingResolverEntries(Racing._finishResolver)
    if pending > 0 then
        _notify(i18n.format("FINISH - classifying %d trailing rivals...", pending), 2.2)
    else
        Racing._tickFinishResolver()
    end
end

function Racing._countPendingResolverEntries(resolver)
    if type(resolver) ~= "table" or type(resolver.visibleIds) ~= "table" then
        return 0
    end

    local pending = 0
    for _, entry in ipairs(resolver.scoredField or {}) do
        local id = entry and (entry.driverId or entry.id) or nil
        if id and resolver.visibleIds[id] and not Racing._aiFinishTime[id] then
            pending = pending + 1
        end
    end
    return pending
end

local function _buildLiveStandingsByDriverId()
    local byId = {}
    for _, standing in ipairs(Racing.getLiveStandings() or {}) do
        if not standing.isPlayer and standing.driverId then
            byId[standing.driverId] = standing
        end
    end
    return byId
end

local function _appendResolvedFinisher(results, entry, finishTime, finishMode)
    local factionTag = ""
    if entry.driver and entry.driver.factionName then
        factionTag = entry.driver.factionName
    elseif entry.isFaction and entry.faction then
        factionTag = entry.faction
    end

    table.insert(results, {
        id = entry.driverId or entry.id,
        driverId = entry.driverId or entry.id,
        name = entry.displayName or entry.name or "?",
        time = finishTime,
        isPlayer = false,
        position = nil,
        factionName = factionTag,
        driver = entry.driver,
        finishMode = finishMode or "projected",
    })
end

local function _estimateVisibleSimulatedFinishTime(entry, resolver, liveStandingsByDriverId, tailIndex)
    local predicted = tonumber(entry and entry.aiTime) or nil
    local id = entry and (entry.driverId or entry.id) or nil
    local standing = id and liveStandingsByDriverId[id] or nil

    if standing then
        local remaining = tonumber(standing.remainingDistance or standing.distToFinish) or nil
        local progress = tonumber(standing.progress) or nil
        if remaining and remaining > 0 then
            local speed = tonumber(standing.speed) or 0.0
            local pace = math.max(12.0, speed * 0.92)
            local liveEstimate = _getDragOfficialTime(Racing._raceTimer + (remaining / pace), Racing._config)
            predicted = predicted and math.max(predicted, liveEstimate) or liveEstimate
        end
        if progress and progress > 0.05 and progress < 0.999 then
            local progressEstimate = _getDragOfficialTime(Racing._raceTimer / progress, Racing._config)
            predicted = predicted and math.max(predicted, progressEstimate) or progressEstimate
        end
    end

    if type(predicted) ~= "number" then
        predicted = resolver.playerTime + 2.0 + (tailIndex * 0.35)
    end

    local minAllowed = resolver.playerTime + 0.20 + ((math.max(1, tailIndex) - 1) * _tuningValue("finishResolveSimTailStepS", Racing._config))
    if predicted < minAllowed then
        predicted = minAllowed
    end
    return predicted
end

local function _estimateUntrackedFinishTime(entry, resolver, tailIndex)
    local predicted = tonumber(entry and entry.aiTime) or nil
    local id = entry and (entry.driverId or entry.id) or nil
    local cachedStanding = id and Racing._lastKnownStandingByDriverId[id] or nil
    if id and Racing._aiFinishTime[id] then
        return Racing._aiFinishTime[id]
    end
    if cachedStanding and cachedStanding.finished then
        local finishedTime = tonumber(cachedStanding.time) or resolver.playerTime - (0.20 + ((math.max(1, tailIndex) - 1) * 0.02))
        return math.min(finishedTime, resolver.playerTime - 0.05)
    end
    local fallbackFloor = resolver.playerTime + _tuningValue("finishResolveUntrackedOffsetS", Racing._config) + ((math.max(1, tailIndex) - 1) * 0.75)
    if type(predicted) ~= "number" or predicted < fallbackFloor then
        predicted = fallbackFloor
    end
    return predicted
end

local function _boxScoreStartPosByDriverId()
    local byId = {}
    for index, entry in ipairs(Racing._field or {}) do
        local driverId = entry and (entry.driverId or entry.id) or nil
        if driverId then
            byId[driverId] = tonumber(entry.gridPos or entry.slotIndex or index) or index
        end
    end
    byId.player = Racing._getPlayerGridPosForStart and Racing._getPlayerGridPosForStart() or Racing._qualiGridPos or 1
    return byId
end

function Racing._buildResolvedResults(resolver)
    local results = {}
    local scoredIds = {}
    local liveStandingsByDriverId = _buildLiveStandingsByDriverId()
    local simulatedVisibleIndex = 0
    local untrackedIndex = 0

    for _, entry in ipairs(resolver.scoredField or {}) do
        local id = entry and (entry.driverId or entry.id) or nil
        if id then
            scoredIds[id] = true
        end

        local authoritativeTime = Racing._getEntryFinishTime(entry, resolver.visibleIds)
        if authoritativeTime then
            if id and Racing._aiFinishTime[id] then
                authoritativeTime = _getDragOfficialTime(authoritativeTime, Racing._config)
            end
            local finishMode = (id and Racing._aiFinishTime[id]) and "physical" or "projected"
            _appendResolvedFinisher(results, entry, authoritativeTime, finishMode)
        elseif resolver.visibleIds and id and resolver.visibleIds[id] then
            simulatedVisibleIndex = simulatedVisibleIndex + 1
            _appendResolvedFinisher(
                results,
                entry,
                _estimateVisibleSimulatedFinishTime(entry, resolver, liveStandingsByDriverId, simulatedVisibleIndex),
                "simulated")
        end
    end

    local playerFaction = ""
    if Racing._career then
        playerFaction = Racing._career.playerFactionName or ""
    end
    table.insert(results, {
        id = "player",
        driverId = "player",
        name = "V",
        time = resolver.playerTime,
        isPlayer = true,
        position = nil,
        factionName = playerFaction,
        finishMode = "physical",
    })

    if resolver.visibleIds then
        for _, entry in ipairs(Racing._field or {}) do
            local id = entry and (entry.driverId or entry.id) or nil
            if id and not scoredIds[id] then
                untrackedIndex = untrackedIndex + 1
                _appendResolvedFinisher(results, entry, _estimateUntrackedFinishTime(entry, resolver, untrackedIndex), "untracked")
            end
        end
    end

    table.sort(results, function(a, b)
        local at = tonumber(a.time) or 999999.0
        local bt = tonumber(b.time) or 999999.0
        if at ~= bt then
            return at < bt
        end
        if a.isPlayer and not b.isPlayer then return true end
        if not a.isPlayer and b.isPlayer then return false end
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    local playerPosition = #results
    for i, finisher in ipairs(results) do
        finisher.position = i
        if finisher.isPlayer then
            playerPosition = i
        end
    end

    return results, playerPosition
end

function Racing._tickFinishResolver()
    local resolver = Racing._finishResolver
    if not resolver then
        return false
    end

    local pending = Racing._countPendingResolverEntries(resolver)
    if pending > 0 then
        local elapsed = math.max(0.0, Racing._raceTimer - (resolver.startedAt or Racing._raceTimer))
        local minWait = _tuningValue("finishResolveMinWaitS", Racing._config)
        if elapsed < math.max(minWait, resolver.waitTarget or minWait) then
            return false
        end
    end

    local buildOk, results, position = pcall(Racing._buildResolvedResults, resolver)
    if not buildOk then
        print("[NCM/Racing] ERROR in _buildResolvedResults: " .. tostring(results))
        Racing._finishResolver = nil
        return true
    end
    Racing._results = results
    Racing._finishResolver = nil
    _clearRacerMarkers()
    local finalizeOk, finalizeErr = pcall(Racing._finalizeRace, resolver.playerTime, position, false)
    if not finalizeOk then
        print("[NCM/Racing] ERROR in _finalizeRace: " .. tostring(finalizeErr))
    end
    return true
end

function Racing._onPlayerDNF()
    local scoredField = Racing._field
    if LIVE_RIVALS_POST_START and not Racing._isGhostFallbackActive() then
        scoredField = Racing._getScoredField()
    end
    Racing._finalizeRace(nil, #scoredField + 1, true)
end

local function _seasonAccountClipName(name, maxLen)
    local text = tostring(name or "?")
    local limit = math.max(4, math.floor(tonumber(maxLen) or 16))
    if #text <= limit then
        return text
    end
    return string.sub(text, 1, limit - 3) .. "..."
end

local function _seasonAccountDeltaText(value)
    local numeric = math.floor(tonumber(value) or 0)
    if numeric > 0 then
        return "+" .. tostring(numeric)
    end
    return tostring(numeric)
end

local function _seasonAccountRowDelta(preSnapshot, row)
    local preRow = preSnapshot and preSnapshot.byDriverId and preSnapshot.byDriverId[row.driverId] or nil
    return row.points - ((preRow and preRow.points) or 0)
end

local function _seasonAccountNeighborText(label, row, preSnapshot, playerPoints)
    if not row then
        return nil
    end

    local pointsDelta = _seasonAccountRowDelta(preSnapshot, row)
    local pointsGap = math.abs((tonumber(playerPoints) or 0) - (tonumber(row.points) or 0))
    return i18n.format(
        "%s: %s P%d  %d pts (%s)  |  gap %d",
        label,
        _seasonAccountClipName(row.name, 14),
        tonumber(row.rank or 0) or 0,
        tonumber(row.points or 0) or 0,
        _seasonAccountDeltaText(pointsDelta),
        math.max(0, math.floor(pointsGap)))
end

local function _seasonAccountSnapshot(standings)
    local snapshot = {
        list = {},
        byDriverId = {},
    }

    for rank, row in ipairs(standings or {}) do
        local driverId = tostring(row.driverId or "")
        local name = driverId == "player"
            and "V"
            or tostring(row.driverName or row.displayName or row.name or row.driverId or "?")
        local entry = {
            rank = rank,
            driverId = driverId,
            name = name,
            points = math.floor(tonumber(row.points) or 0),
        }
        snapshot.list[#snapshot.list + 1] = entry
        snapshot.byDriverId[driverId] = entry
    end

    return snapshot
end

local function _seasonAccountMovementText(preSnapshot, preRank, postRank)
    local moved = {}
    local movedCount = 0

    if preRank > postRank then
        for rank = postRank, preRank - 1 do
            local row = preSnapshot.list[rank]
            if row and row.driverId ~= "player" then
                movedCount = movedCount + 1
                if #moved < 3 then
                    moved[#moved + 1] = _seasonAccountClipName(row.name, 18)
                end
            end
        end
        if movedCount > 0 then
            local namesText = i18n.concat(moved, ", ")
            if movedCount > #moved then
                namesText = namesText .. i18n.format(", +%d more", movedCount - #moved)
            end
            return "Moved ahead of: " .. namesText
        end
        return i18n.format("Climbed %d place%s in the table.", preRank - postRank, (preRank - postRank) == 1 and "" or "s")
    end

    if postRank > preRank then
        for rank = preRank + 1, postRank do
            local row = preSnapshot.list[rank]
            if row and row.driverId ~= "player" then
                movedCount = movedCount + 1
                if #moved < 3 then
                    moved[#moved + 1] = _seasonAccountClipName(row.name, 18)
                end
            end
        end
        if movedCount > 0 then
            local namesText = i18n.concat(moved, ", ")
            if movedCount > #moved then
                namesText = namesText .. i18n.format(", +%d more", movedCount - #moved)
            end
            return "Moved behind: " .. namesText
        end
        return i18n.format("Dropped %d place%s in the table.", postRank - preRank, (postRank - preRank) == 1 and "" or "s")
    end

    return "Holding position in the table."
end

local function _buildSeasonLadderAccount(season, roundNumber, preStandings, postStandings)
    if type(preStandings) ~= "table" or type(postStandings) ~= "table" then
        return nil
    end

    local preSnapshot = _seasonAccountSnapshot(preStandings)
    local postSnapshot = _seasonAccountSnapshot(postStandings)
    local playerPost = postSnapshot.byDriverId.player
    if not playerPost then
        return nil
    end

    local playerPre = preSnapshot.byDriverId.player or {
        rank = playerPost.rank,
        points = playerPost.points,
        name = "V",
    }

    local pointsDelta = playerPost.points - playerPre.points
    local rankDelta = playerPre.rank - playerPost.rank
    local direction = rankDelta > 0 and "up" or (rankDelta < 0 and "down" or "flat")
    local summary = rankDelta ~= 0
        and i18n.format("V %s pts  |  P%d -> P%d  |  %d total", _seasonAccountDeltaText(pointsDelta), playerPre.rank, playerPost.rank, playerPost.points)
        or i18n.format("V %s pts  |  Holding P%d  |  %d total", _seasonAccountDeltaText(pointsDelta), playerPost.rank, playerPost.points)

    local ladderLines = {}
    local startRank = math.max(1, playerPost.rank - 2)
    local finishRank = math.min(#postSnapshot.list, playerPost.rank + 2)
    for rank = startRank, finishRank do
        local row = postSnapshot.list[rank]
        if row then
            local preRow = preSnapshot.byDriverId[row.driverId]
            local rowPointsDelta = _seasonAccountRowDelta(preSnapshot, row)
            local rowRankDelta = ((preRow and preRow.rank) or rank) - rank
            local moveTag = rowRankDelta > 0 and ("▲" .. tostring(rowRankDelta))
                or (rowRankDelta < 0 and ("▼" .. tostring(math.abs(rowRankDelta))))
                or "·"
            local rowName = row.driverId == "player" and "V" or _seasonAccountClipName(row.name, 16)
            local marker = row.driverId == "player" and "V" or " "
            ladderLines[#ladderLines + 1] = i18n.format("%s %s P%d %s  %d pts (%s)", marker, moveTag, rank, rowName, row.points, _seasonAccountDeltaText(rowPointsDelta))
        end
    end

    local footerParts = {
        i18n.format("Championship Rd %d/%d", tonumber(roundNumber or season.currentRound or 1), tonumber(season.totalRounds or 1)),
    }
    if playerPost.rank > 1 then
        local above = postSnapshot.list[playerPost.rank - 1]
        local aboveText = _seasonAccountNeighborText("Ahead", above, preSnapshot, playerPost.points)
        if aboveText then
            footerParts[#footerParts + 1] = aboveText
        end
    end
    if playerPost.rank < #postSnapshot.list then
        local below = postSnapshot.list[playerPost.rank + 1]
        local belowText = _seasonAccountNeighborText("Behind", below, preSnapshot, playerPost.points)
        if belowText then
            footerParts[#footerParts + 1] = belowText
        end
    end

    return {
        direction = direction,
        title = "SEASON ACCOUNT",
        summary = summary,
        movementText = _seasonAccountMovementText(preSnapshot, playerPre.rank, playerPost.rank),
        ladderText = i18n.concat(ladderLines, "\n"),
        footerText = i18n.concat(footerParts, "  |  "),
    }
end

function Racing._finalizeRace(playerTime, position, isDNF)
    local career    = Racing._career
    local config    = Racing._config
    local activeEvent = Racing._activeEvent or {}
    local isSandboxQuickRace = config and config.eventSourceType == "quick_race"
    local fieldSize = #Racing._field + 1

    local hypeResult = nil
    if MTE and MTE.Hype and MTE.Hype.scoreRace then
        pcall(function()
            hypeResult = MTE.Hype.scoreRace(career, config, Racing._results)
        end)
    end
    local hypeMultiplier = hypeResult and hypeResult.multiplier or 1.0
    local hypeIndex = hypeResult and hypeResult.index or 1.0

    -- Payout
    local basePayout = isDNF and 0 or (PAYOUT_BY_POS[position] or 50)
    local payout   = isDNF and 0 or math.max(1, math.floor(basePayout * hypeMultiplier))
    local wagerWon  = false
    local wagerLost = false
    local wagerAmount = Racing._stakeAmount
    local repPenalty = 0

    -- Always award position-based payout (even if there was a wager)
    if not isDNF then
        pcall(function() Game.AddToInventory("Items.money", payout) end)
    end

    local betResolution = nil
    if Betting and Betting.resolveRace then
        local betOk, resolved = pcall(Betting.resolveRace, career, config, {
            position = position,
            isDNF = isDNF,
            payout = payout,
            playerTime = playerTime,
            activeEvent = activeEvent,
            field = Racing._field,
        })
        if betOk and type(resolved) == "table" then
            betResolution = resolved
        elseif not betOk then
            print("[NCM/Racing] Betting.resolveRace failed: " .. tostring(resolved))
        end
    end

    if betResolution then
        payout = math.max(0, math.floor(tonumber(betResolution.payout) or payout))
        wagerWon = betResolution.wagerWon == true
        wagerLost = betResolution.wagerLost == true
        wagerAmount = math.max(tonumber(wagerAmount or 0) or 0, tonumber(betResolution.wagerAmount or 0) or 0)
        repPenalty = math.max(0, math.floor(tonumber(betResolution.repPenalty) or 0))
        if wagerLost and MTE and MTE.Events then
            MTE.Events.emit("WagerLost", { amount = wagerAmount })
        end
    elseif Racing._stakeAmount > 0 and not isDNF and position == 1 then
        -- Wager won: return stake + winnings on top of base payout
        payout    = payout + Racing._stakeAmount * 2
        wagerWon  = true
        pcall(function() Game.AddToInventory("Items.money", Racing._stakeAmount * 2) end)
    elseif Racing._stakeAmount > 0 and (isDNF or position ~= 1) then
        wagerLost = true
        MTE.Events.emit("WagerLost", { amount = Racing._stakeAmount })
    end

    -- Bounty
    local bountyResolved, bountyEscalated = false, false
    if career and not isSandboxQuickRace then
        local bDriver = Racing._findBountyDriverInField(career)
        if bDriver and not isDNF then
            local won = (position <= bDriver.finishPos)
            bountyResolved, bountyEscalated = MTE.Careers.updateBounty(career, bDriver.id, won)
        end
    end

    local safetySummary = nil
    if MTE and MTE.SafetyRating and MTE.SafetyRating.finishRace then
        safetySummary = MTE.SafetyRating.finishRace({
            position = position,
            playerTime = playerTime,
            isDNF = isDNF,
            finishStatus = isDNF and "dnf" or "finished",
            sourceType = activeEvent.sourceType or config.eventSourceType,
            sessionId = Racing._telemetrySessionId,
        })
    end

    -- Clean race should follow recorded safety incidents when available.
    local incidentPoints = safetySummary and tonumber(safetySummary.incidentPoints) or nil
    local crashCount = tonumber(MTE and MTE.Metrics and MTE.Metrics.session and MTE.Metrics.session.crashCount) or 0
    local isClean = not isDNF
    if incidentPoints ~= nil then
        isClean = isClean and incidentPoints <= 0
    else
        isClean = isClean and crashCount == 0
    end

    local playerStartPosition = math.max(1, tonumber(Racing._qualiGridPos or position) or position)
    local playerDeltaPos = playerStartPosition - position
    local playerGapToLeader = nil
    local playerMarginToNext = nil
    if not isDNF and type(Racing._results) == "table" then
        local leaderTime = Racing._results[1] and tonumber(Racing._results[1].time) or nil
        for index, row in ipairs(Racing._results) do
            if row and row.isPlayer then
                local playerFinishTime = tonumber(row.time) or nil
                if leaderTime and playerFinishTime then
                    playerGapToLeader = math.max(0.0, playerFinishTime - leaderTime)
                end
                local nextRow = Racing._results[index + 1]
                local nextFinishTime = nextRow and tonumber(nextRow.time) or nil
                if nextFinishTime and playerFinishTime then
                    playerMarginToNext = math.max(0.0, nextFinishTime - playerFinishTime)
                end
                break
            end
        end
    end

    -- Rep
    local repGain = 0
    if career and not isSandboxQuickRace then
        repGain = MTE.Careers.awardRep(career, position, fieldSize, {
            distance        = config.distance,
            clean           = isClean,
            wagerWon        = wagerWon,
            bountyResolved  = bountyResolved,
            bountyEscalated = bountyEscalated,
            dnf             = isDNF,
            source          = "race",
            startPosition   = playerStartPosition,
            playerDeltaPos  = playerDeltaPos,
            marginToNext    = playerMarginToNext,
            gapToLeader     = playerGapToLeader,
        })
    end
    if career and repPenalty > 0 then
        career.rep = math.max(0, math.floor((tonumber(career.rep) or 0) - repPenalty))
        repGain = repGain - repPenalty
        if MTE.Careers and MTE.Careers._checkTierChange then
            MTE.Careers._checkTierChange(career)
        end
        if MTE.Careers and MTE.Careers.save then
            MTE.Careers.save()
        end
    end

    -- Records
    if playerTime and not isDNF then
        MTE.Records.submit(career, config.nodeA.id, config.nodeB.id,
            playerTime, "V", Racing._getVehicleId())
    end

    -- Heat
    if config.district then
        MTE.Heat.applyRaceResult(config.district, position == 1)
    end

    -- Update AI driver stats from real race results
    if career and not isSandboxQuickRace and MTE.Roster and Racing._results then
        MTE.Roster.applyRaceResult(career, Racing._results)
        MTE.Roster.saveForCareer(career)
    end

    local seasonAccount = nil

    -- Championship layer: award season points (independent of prestige rep logic)
    if career and not isSandboxQuickRace and MTE.Championships then
        local season = MTE.Championships.activeSeason(career)
        if season then
            local standingsBefore = MTE.Championships.driverStandings and MTE.Championships.driverStandings(season) or nil
            local completedRound = season.currentRound
            local champResults = {}
            -- Player entry
            table.insert(champResults, {
                driverId   = "player",
                position   = position,
                factionId  = career.playerFactionId or "independent",
                driverName = "V",
                isPlayer   = true,
                dnf        = isDNF,
            })
            -- AI entries: pull factionId from the roster driver reference on each entry
            for _, r in ipairs(Racing._results or {}) do
                if not r.isPlayer then
                    local dFaction = "independent"
                    if r.driver and r.driver.factionId then
                        dFaction = r.driver.factionId
                    end
                    table.insert(champResults, {
                        driverId   = r.driverId or r.id or "unknown",
                        position   = r.position,
                        factionId  = dFaction,
                        driverName = r.name or r.displayName or "?",
                    })
                end
            end
            MTE.Championships.recordResult(career, {
                eventId = config and config._scheduledEventId,
                seasonId = season.id,
                round    = completedRound,
                tier     = career.tier,
                results  = champResults,
            })
            local standingsAfter = MTE.Championships.driverStandings and MTE.Championships.driverStandings(season) or nil
            seasonAccount = _buildSeasonLadderAccount(season, completedRound, standingsBefore, standingsAfter)
        end
    end

    if career and MTE and MTE.Championships and MTE.Championships.recordBoxScore then
        local startPosByDriverId = _boxScoreStartPosByDriverId()
        local leaderTime = Racing._results and Racing._results[1] and tonumber(Racing._results[1].time) or nil
        local participants = {}
        for _, row in ipairs(Racing._results or {}) do
            local driverId = tostring(row.driverId or row.id or "unknown")
            local startPos = tonumber(startPosByDriverId[driverId] or row.position or 99) or 99
            local finishPos = tonumber(row.position or 99) or 99
            local finishTime = tonumber(row.time) or nil
            local playerPayout = row.isPlayer == true and math.max(0, math.floor(tonumber(payout) or 0)) or 0
            participants[#participants + 1] = {
                driverId = driverId,
                displayName = tostring(row.name or row.displayName or driverId),
                isPlayer = row.isPlayer == true,
                startPos = startPos,
                finishPos = finishPos,
                finishTime = finishTime,
                gapToLeader = (leaderTime and finishTime) and math.max(0.0, finishTime - leaderTime) or 0.0,
                deltaPos = startPos - finishPos,
                dnf = isDNF == true and row.isPlayer == true,
                payout = playerPayout,
                factionId = row.driver and row.driver.factionId or (row.isPlayer == true and career.playerFactionId or nil),
                factionName = row.factionName or (row.isPlayer == true and career.playerFactionName or nil),
                finishMode = row.finishMode,
            }
        end
        MTE.Championships.recordBoxScore(career, {
            sourceType = activeEvent.sourceType or config.eventSourceType or "career_race",
            eventId = activeEvent.eventId or config._scheduledEventId,
            seasonId = activeEvent.seasonId,
            round = activeEvent.round,
            tier = career.tier,
            raceType = config.raceType,
            trackName = config.trackName,
            district = config.district,
            timestamp = os.time(),
            fieldSize = #participants,
            playerInvolved = true,
            payout = math.max(0, math.floor(tonumber(payout) or 0)),
            playerPayout = math.max(0, math.floor(tonumber(payout) or 0)),
            participants = participants,
        })
    end

    -- Career history
    if career and not isSandboxQuickRace then
        MTE.Careers.recordRace(career, {
            position  = position,            time      = playerTime,
            district  = config.district,     fieldSize = fieldSize,
            distance  = config.distance,     payout    = payout,
            repGain   = repGain,             dnf       = isDNF,
            clean     = isClean,
            startPos  = Racing._qualiGridPos or 1,
            pole      = (Racing._qualiGridPos == 1),
            nodeA     = config.nodeA,
            nodeB     = config.nodeB,
            routeId   = config.routeId,
            sessionId = Racing._telemetrySessionId,
            trackName = config.trackName,
            safetyRating = safetySummary,
            hypeIndex = hypeIndex,
            hypeMultiplier = hypeMultiplier,
        })
    end

    _clearRacerMarkers()

    -- Despawn AI vehicles on finish
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end

    -- Quest/SMS: sync race result stats + send result SMS
    local careerStats = MTE.Careers and career and MTE.Careers.getStats(career) or {}
    _syncRaceState("results", {
        finishPos  = position,
        totalWins  = (careerStats.wins or 0),
        totalRaces = (careerStats.races or 0),
    })
    _sendSMS(3) -- race_result

    Racing._state = Racing.STATE.RESULTS
    if MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.finalizeActive then
        local telOk, telErr = pcall(MTE.RaceTelemetry.finalizeActive, {
            sessionId = Racing._telemetrySessionId,
            routeId = config.routeId,
            position = position,
            playerTime = playerTime,
            payout = payout,
            repGain = repGain,
            isClean = isClean,
            wagerWon = wagerWon,
            wagerLost = wagerLost,
            wagerAmount = wagerAmount,
            bountyResolved = bountyResolved,
            isDNF = isDNF,
            results = Racing._results,
            safetyRating = safetySummary,
            hype = hypeResult,
        })
        if not telOk then
            print("[NCM/Racing] ERROR in RaceTelemetry.finalizeActive: " .. tostring(telErr))
        end
    end
    print(i18n.format("[NCM/Racing] About to emit RaceFinished: P%d time=%s payout=%d", position, tostring(playerTime), payout))
    MTE.Events.emit("RaceFinished", {
        position       = position,      playerTime = playerTime,
        payout         = payout,        repGain    = repGain,
        isClean        = isClean,       wagerWon   = wagerWon,
        wagerLost      = wagerLost,     wagerAmount = wagerAmount,
        bountyResolved = bountyResolved, isDNF     = isDNF,
        results        = Racing._results,
        routeId        = config.routeId,
        sessionId      = Racing._telemetrySessionId,
        trackName      = config.trackName,
        safetyRating   = safetySummary,
        hype           = hypeResult,
        dragStrip      = config.dragStrip,
        seasonAccount  = seasonAccount,
    })
    if hypeResult then
        print(i18n.format("[NCM/Racing] P%d | Rep %+d | %d eddies | Hype: %.2f (%s) x%.2f",
            position,
            repGain,
            payout,
            hypeIndex,
            MTE.Hype and MTE.Hype.label and MTE.Hype.label(hypeIndex) or "?",
            hypeMultiplier))
    else
        print(i18n.format("[NCM/Racing] P%d | Rep %+d | %d eddies",
            position, repGain, payout))
    end
    Racing._telemetrySessionId = nil
end

-- ── Internal: field building ──────────────────────────────────

function Racing._buildField(career, config)
    if not MTE.Roster then return {} end
    local field = {}
    local forcedEntrants = type(config) == "table" and config.forcedEntrantDriverIds or nil
    if type(forcedEntrants) == "table" and #forcedEntrants > 0 and MTE.Roster.findById then
        local seen = {}
        for _, driverId in ipairs(forcedEntrants) do
            local driver = MTE.Roster.findById(career, driverId)
            if driver and not seen[driver.id] then
                field[#field + 1] = driver
                seen[driver.id] = true
            end
        end
    end
    if #field <= 0 then
        field = MTE.Roster.pickForRace(career, config.fieldSize, config.district)
    end
    -- Spec field (one-make lineup): faction/heat enforcers would consume lineup slots and be deferred from spawn.
    if type(config.specFieldAssignments) == "table" then
        local clean = {}
        for _, d in ipairs(field) do
            if not d.isFaction then clean[#clean + 1] = d end
        end
        field = clean
        if #field < #config.specFieldAssignments then
            print(string.format("[NCM/Racing] spec_field_short drivers=%d wanted=%d", #field, #config.specFieldAssignments))
        end
    end
    -- Strip heat-injected faction enforcers when the ruleset forbids combat.
    -- allowCombat defaults to true when nil (absent from career-only config).
    if config.allowCombat == false then
        local clean = {}
        for _, d in ipairs(field) do
            if not d.isFaction then table.insert(clean, d) end
        end
        field = clean
    end
    -- Filter to event vehicle class when specified.
    -- Only applies the filter if it leaves a usable field (≥ 2 drivers);
    -- otherwise the cross-class fill stands so the race is never blocked.
    local useQuickRaceClassOverride = type(config) == "table"
        and config.eventSourceType == "quick_race"
        and config.vehicleClass ~= nil
    if useQuickRaceClassOverride or (type(forcedEntrants) == "table" and #forcedEntrants > 0) then
        print(i18n.format(
            "[NCM/Racing] field_override field=%d requestedClass=%s action=skip_roster_class_filter",
            tonumber(#field or 0),
            tostring(config.vehicleClass)))
    elseif config.vehicleClass then
        local filtered = {}
        for _, d in ipairs(field) do
            if d.carClass == config.vehicleClass then
                table.insert(filtered, d)
            end
        end
        if #filtered >= 2 then
            field = filtered
        end
    end
    while #field > config.fieldSize do
        local removed = false
        for j = #field, 1, -1 do
            if not field[j].isFaction then
                table.remove(field, j)
                removed = true
                break
            end
        end
        if not removed then table.remove(field) end
    end
    return field
end

--- Wrap raw roster drivers into race entry objects.
--- The entry IS the authoritative identity for this race:
--- one object carries through preview → spawn → countdown → results.
local function stableQuickRaceVehicleSeed(driver, entryIndex, config)
    local text = i18n.concat({
        tostring(driver and (driver.id or driver.name) or "?"),
        tostring(entryIndex or 0),
        tostring(config and config.vehicleClass or "Any"),
        tostring(config and (config.routeId or config.trackName) or "?"),
        tostring(config and config.quickRacePrestigeWeighting or "mixed"),
    }, "|")
    local hash = 7
    for i = 1, #text do
        hash = ((hash * 33) + string.byte(text, i)) % 2147483647
    end
    return (hash % 1000000) / 1000000
end

local function resolveQuickRaceClassVehicle(driver, entryIndex, config)
    if type(config) ~= "table" or config.eventSourceType ~= "quick_race" or not config.vehicleClass then
        return nil
    end

    local resolved = VehiclePool.resolveQuickRaceVehicle(
        config.vehicleClass,
        config.quickRacePrestigeMin or 1,
        config.quickRacePrestigeMax or 5,
        config.quickRacePrestigeWeighting or "mixed",
        stableQuickRaceVehicleSeed(driver, entryIndex, config),
        {
            fallbackToAnyClass = false,
            preferHighest = config.quickRaceAllowBossOutlier == true and entryIndex == 1,
        })

    if type(resolved) == "table" and type(resolved.id) == "string" and resolved.id ~= "" then
        print(i18n.format(
            "[NCM/Racing] quick_race_class_override slot=%d driver=%s class=%s vehicle=%s prestige=P%d weighting=%s",
            tonumber(entryIndex or 0),
            tostring(driver and (driver.id or driver.name) or "?"),
            tostring(config.vehicleClass),
            tostring(resolved.id),
            tonumber(resolved.prestige or 0),
            tostring(config.quickRacePrestigeWeighting or "mixed")))
        return resolved
    end

    print(i18n.format(
        "[NCM/Racing] quick_race_class_override_failed slot=%d driver=%s class=%s",
        tonumber(entryIndex or 0),
        tostring(driver and (driver.id or driver.name) or "?"),
        tostring(config.vehicleClass)))
    return nil
end

--- @param drivers  table[]  raw driver objects from Roster
--- @return table[] race entries
function Racing._buildRaceEntries(drivers, config)
    local entries = {}
    local activeConfig = config or Racing._config or {}
    for i, driver in ipairs(drivers) do
        local entry = Racing._shallowCopy(driver)  -- copy all driver fields
        -- Race identity (authoritative)
        entry.driverId      = driver.id
        entry.displayName   = driver.name or driver.displayName or driver.id
        -- Stable cosmetics from roster (or fallback to pool lookup)
        entry.vehicleRecord = driver.vehicleSignature
                              or VehiclePool.resolveVehicle(driver.carClass or "Muscle", i)
        entry.npcRecord     = VehiclePool.normalizeNPCRecord(driver.npcRecord, driver.factionId, driver.id)
                      or VehiclePool.resolveNPC(i, driver.factionId)
        local assignment = type(activeConfig.specFieldAssignments) == "table" and activeConfig.specFieldAssignments[i] or nil
        local quickRaceClassVehicle = (not assignment) and resolveQuickRaceClassVehicle(driver, i, activeConfig) or nil
        if quickRaceClassVehicle then
            entry.vehicleRecord = quickRaceClassVehicle.id
            entry.carClass = quickRaceClassVehicle.carClass or activeConfig.vehicleClass or driver.carClass or "Muscle"
            entry.vehiclePrestige = quickRaceClassVehicle.prestige
            entry.vehicleTags = quickRaceClassVehicle.tags
        end
        if assignment then
            -- Spec field: every rival drives the lineup record; appearance selects the livery (nil = stock).
            entry.vehicleRecord = assignment.record
            entry.vehicleAppearance = assignment.appearance
            entry.carClass = "Sport"
            entry.vehiclePrestige = nil
            entry.vehicleTags = nil
            print(string.format("[NCM/Racing] spec_field_assign entry=%d driver=%s vehicle=%s appearance=%s",
                i, tostring(entry.driverId), tostring(assignment.record), tostring(assignment.appearance or "stock")))
        end
        -- Race-specific state
        entry.gridPos       = i      -- initial position; updated by quali
        entry.aiTime        = nil    -- set in startRace
        entry.slotIndex     = nil    -- set by AIVehicles after spawn
        entry.launchable    = nil    -- set by AIVehicles
        entry.failureReason = nil    -- set by AIVehicles
        entry.driver        = driver -- reference to original roster driver
        entry.isRival       = (driver.rivalScore or 0) > 0
        entries[i] = entry
    end
    return entries
end

function Racing._computeAITime(driver, config, handicapMult)
    local hm = handicapMult or 1.0
    local basePace = math.max(0.65, tonumber(_getDriverStatValue(driver, "base_pace", driver and driver.pace or 1.0)) or 1.0)
    local attackPace = math.max(basePace, tonumber(_getDriverStatValue(driver, "max_attack_pace", basePace)) or basePace)
    local effectivePace = basePace + ((attackPace - basePace) * 0.48)
    local disciplineHardwareScale, hardware = _getDriverDisciplineHardwareScale(driver, config)
    local urgencyScale = _getDriverRaceUrgencyScale(driver, config)
    local projectedScale = _getDriverProjectedPerformanceScale(driver, config)
    local baseSpeed = _tuningValue("aiProjectedBaseSpeedMps", config) * effectivePace * hm * urgencyScale * projectedScale * disciplineHardwareScale
    local ideal     = config.distance / baseSpeed
    local launchSkill = _clamp01(_getDriverStatValue(driver, "launch_skill", 0.5))
    local startComposure = _clamp01(_getDriverStatValue(driver, "race_start_composure", 0.5))
    local consistency = _clamp01(_getDriverStatValue(driver, "consistency", driver and driver.consistency or 0.6))
    local aggression = _clamp01(_getDriverStatValue(driver, "aggression", driver and driver.aggression or 0.5))
    local composure = _clamp01(_getDriverStatValue(driver, "composure", 0.5))
    local precision = _clamp01(driver and driver.precision or 0.5)
    local recoverySkill = _clamp01(_getDriverStatValue(driver, "recovery_skill", 0.5))
    local vehicleSympathy = _clamp01(_getDriverStatValue(driver, "vehicle_sympathy", 0.5))
    local adaptability = _clamp01(_getDriverStatValue(driver, "adaptability", 0.5))
    local riskTolerance = _clamp01(_getDriverStatValue(driver, "risk_tolerance", 0.5))
    local launchScale = _smoothScale(hardware.launchScale or 1.0, 0.55, 0.95, 1.14)
    local controlScale = _smoothScale(hardware.controlScale or 1.0, 0.55, 0.95, 1.12)
    local reliabilityScale = _smoothScale(hardware.reliabilityScale or 1.0, 0.55, 0.95, 1.12)
    local varianceScale = 0.03 + ((1.0 - consistency) * 0.05) + ((1.0 - composure) * 0.04) + (riskTolerance * 0.02)
    local setupComposure = _clampRange(((controlScale - 1.0) * 0.60) + ((reliabilityScale - 1.0) * 0.70), -0.08, 0.10)
    varianceScale = varianceScale * _clampRange(1.0 - setupComposure, 0.82, 1.12)
    local delay = config.startType ~= "rolling"
        and (1.0 - ((launchSkill * 0.55) + (startComposure * 0.45))) * (START_DELAYS[config.startType] or 0.5)
        or 0.0
    delay = delay / launchScale
    local variance = (math.random() * 2 - 1) * ideal * varianceScale
    local crashChance = _clampRange(0.18 - (precision * 0.08) - (recoverySkill * 0.04) - (vehicleSympathy * 0.03) - (adaptability * 0.03) + (aggression * 0.04), 0.02, 0.22)
    crashChance = crashChance * _clampRange(1.0 - (setupComposure * 1.10), 0.78, 1.12)
    local crash = math.random() < crashChance and ideal * math.random() * (0.04 + ((1.0 - composure) * 0.08)) or 0.0
    local bountyPenalty = 0.0
    if Racing._career and MTE.Careers.isBountyEscalated(Racing._career, driver.id) then
        bountyPenalty = -ideal * 0.08
    end
    return math.max(0.1, ideal + delay + variance + crash + bountyPenalty + _getDragStripPenaltySeconds(config))
end

function Racing._sortFieldByQuali(playerTime)
    local hm = MTE.Careers and MTE.Careers.handicapMult(Racing._career) or 1.0
    for _, d in ipairs(Racing._field) do
        d._qualiEst = Racing._computeAITime(d, Racing._config, hm)
    end
    table.sort(Racing._field, function(a, b) return a._qualiEst < b._qualiEst end)
    -- Reassign grid positions to match sorted order
    for i, d in ipairs(Racing._field) do
        d.gridPos = i
    end
end

function Racing._findBountyDriverInField(career)
    for pos, driver in ipairs(Racing._field) do
        if MTE.Careers.hasBounty(career, driver.driverId or driver.id) then
            driver.finishPos = pos
            return driver
        end
    end
    return nil
end

-- ── Internal: route picking ───────────────────────────────────

function Racing._pickRoute(cfg)
    local nodes = MTE.Nodes or {}
    local regions = cfg.preferredRegions
    local minD  = cfg.minDistanceM or 1500
    local maxD  = cfg.maxDistanceM or 8000

    local function collectCandidates(requireUrban, ignoreRegions)
        local out = {}
        for _, n in ipairs(nodes) do
            local regionOk = ignoreRegions or not regions or #regions == 0 or Racing._tableHas(regions, n.region)
            if regionOk and Racing._isRaceLegalNode(n) then
                if not requireUrban or Racing._isUrbanNode(n) then
                    table.insert(out, n)
                end
            end
        end
        return out
    end

    local function choosePair(candidates)
        if not candidates or #candidates < 2 then return nil, nil end

        local starts = {}
        for _, node in ipairs(candidates) do
            starts[#starts + 1] = node
        end
        for i = #starts, 2, -1 do
            local j = math.random(1, i)
            starts[i], starts[j] = starts[j], starts[i]
        end

        local startLimit = math.min(#starts, 24)
        for i = 1, startLimit do
            local a = starts[i]
            local finishes = {}
            for _, b in ipairs(candidates) do
                if b ~= a then
                    local d = Racing._estimateDistance(a, b)
                    if d >= minD and d <= maxD then
                        finishes[#finishes + 1] = b
                    end
                end
            end
            if #finishes > 0 then
                local j = math.random(1, #finishes)
                return a, finishes[j]
            end
        end
        return nil, nil
    end

    local candidates = collectCandidates(true, false)
    if #candidates < 2 then
        candidates = collectCandidates(false, false)
    end
    if #candidates < 2 then
        candidates = collectCandidates(true, true)
    end
    if #candidates < 2 then
        candidates = collectCandidates(false, true)
    end
    if #candidates < 2 then candidates = nodes end

    local a, b = choosePair(candidates)
    if a and b then
        return a, b
    end

    for i = #candidates, 2, -1 do
        local j = math.random(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    local attempts = math.min(40, #candidates * (#candidates - 1) / 2)
    for _ = 1, attempts do
        local i = math.random(1, #candidates)
        local j = math.random(1, #candidates - 1)
        if j >= i then j = j + 1 end
        local fallbackA, fallbackB = candidates[i], candidates[j]
        local d = Racing._estimateDistance(fallbackA, fallbackB)
        if d >= minD and d <= maxD then return fallbackA, fallbackB end
    end
    return candidates[1], candidates[2]
end

function Racing._estimateDistance(a, b)
    if not a or not b then return 3000 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- ── Internal: finish line crossing detection ──────────────────

--- Compute normalised 2D direction from start to finish.
--- Called when a race or quali begins.
function Racing._setupFinishLine()
    local a = Racing._config.nodeA
    local b = Racing._config.nodeB
    if not a or not b then
        Racing._finishDir     = nil
        Racing._prevFinishDot = nil
        return
    end
    local dx, dy
    if b.finishHeading then
        local rad = math.rad(b.finishHeading)
        dx = math.cos(rad)
        dy = math.sin(rad)
    else
        dx = (b.x or 0) - (a.x or 0)
        dy = (b.y or 0) - (a.y or 0)
        local routeLen = math.sqrt(dx*dx + dy*dy)
        if routeLen < 1.0 then
            if b.heading then
                local rad = math.rad(b.heading)
                dx = math.cos(rad)
                dy = math.sin(rad)
            else
                dx = 1.0
                dy = 0.0
            end
        end
    end
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 1.0 then len = 1.0 end
    Racing._finishDir     = { x = dx / len, y = dy / len }
    Racing._prevFinishDot = nil  -- reset; first frame will initialise
    Racing._aiPrevDot     = {}   -- reset per-driver dots
    Racing._aiFinished    = {}   -- reset per-driver finish flags
    Racing._aiFinishTime  = {}   -- reset per-driver finish times
    Racing._lastKnownStandingByDriverId = {}
end

--- Tick per-driver finish-line crossing detection.
--- Uses the same signed-dot / sign-change method as the player check.
--- Stores results in Racing._aiFinished[driverId] = true (latched).
function Racing._tickAIFinishCrossings()
    if not Racing._finishDir or not Racing._finishNode then return end
    local liveDrivers = MTE.AIVehicles and MTE.AIVehicles.getLiveDrivers
                        and MTE.AIVehicles.getLiveDrivers()
    if not liveDrivers then return end

    local finX = Racing._finishNode.x
    local finY = Racing._finishNode.y
    local finZ = Racing._finishNode.z or 0
    local fdx  = Racing._finishDir.x
    local fdy  = Racing._finishDir.y
    local finishWidth, finishArmDist = Racing._getFinishLineSettings()

    for _, ld in ipairs(liveDrivers) do
        local id = ld.id
        if id and ld.position and not Racing._aiFinished[id] then
            local rx = ld.position.x - finX
            local ry = ld.position.y - finY

            -- Signed distance along approach direction (positive = approaching)
            local dot  = rx * (-fdx) + ry * (-fdy)
            -- Lateral distance (must be within finish-line width)
            local perp = math.abs(rx * fdy - ry * fdx)

            local prev = Racing._aiPrevDot[id]
            if prev == nil then
                -- First frame: seed; guard against starting past the line
                Racing._aiPrevDot[id] = (dot <= 0) and 1.0 or dot
            else
                -- Only check when within arm distance
                local dz   = (ld.position.z or 0) - finZ
                local dist = math.sqrt(rx*rx + ry*ry + dz*dz)
                if dist <= finishArmDist then
                    if prev > 0 and dot <= 0 and perp <= finishWidth then
                        Racing._aiFinished[id] = true
                        Racing._aiFinishTime[id] = Racing._raceTimer
                        _rememberLiveStanding({
                            driverId = id,
                            finished = true,
                            time = Racing._raceTimer,
                            progress = 1.0,
                            remainingDistance = 0.0,
                            distToFinish = 0.0,
                            speed = ld.speed or 0.0,
                            provenance = "finish_crossing",
                        })
                    end
                end
                Racing._aiPrevDot[id] = dot
            end
        end
    end
end

--- Returns true the frame the player crosses the finish line.
--- Finish line is an infinite line perpendicular to the A→B direction,
--- passing through the finish node.  Detection checks the sign flip
--- of the signed distance along the approach direction.
function Racing._checkFinishLineCrossing()
    if not Racing._finishDir or not Racing._finishNode then return false end
    local pos = Racing._getPlayerPos()
    if not pos then return false end
    local finishWidth, finishArmDist = Racing._getFinishLineSettings()
    local finZ = Racing._finishNode.z or 0

    -- Vector from finish node to player (2D)
    local rx = pos.x - Racing._finishNode.x
    local ry = pos.y - Racing._finishNode.y

    -- Signed distance along the approach direction
    -- Positive = still approaching, Negative = past the line
    local dot = rx * (-Racing._finishDir.x) + ry * (-Racing._finishDir.y)

    -- Lateral distance (perpendicular to approach)
    local perp = math.abs(rx * Racing._finishDir.y - ry * Racing._finishDir.x)

    -- First frame: just record, don't trigger
    if Racing._prevFinishDot == nil then
        -- Spawn guard: if already past the finish line, force "approaching" state
        Racing._prevFinishDot = (dot <= 0) and 1.0 or dot
        return false
    end

    -- Only trigger within the arm distance (prevents crossing from far away)
    local dz = (pos.z or 0) - finZ
    local dist3d = math.sqrt(rx*rx + ry*ry + dz*dz)
    if dist3d > finishArmDist then
        Racing._prevFinishDot = dot
        return false
    end

    -- Check crossing: previous dot was positive (approaching), now <= 0 (past)
    local crossed = Racing._prevFinishDot > 0 and dot <= 0

    Racing._prevFinishDot = dot

    -- Must be within the finish line width (lateral tolerance)
    if crossed and perp <= finishWidth then
        return true
    end
    return false
end

-- ── Internal: game API helpers ────────────────────────────────

function Racing._getPlayerPos()
    local pos = nil
    pcall(function()
        local p = Game.GetPlayer()
        if p then pos = p:GetWorldPosition() end
    end)
    return pos
end

function Racing._distToNode(node)
    if not node then return nil end
    local d = nil
    pcall(function()
        local pos = Racing._getPlayerPos()
        if pos then
            local dx = pos.x - (node.x or 0)
            local dy = pos.y - (node.y or 0)
            local dz = (pos.z or 0) - (node.z or 0)
            d = math.sqrt(dx*dx + dy*dy + dz*dz)
        end
    end)
    return d
end

function Racing.teleportToStart()
    if Racing._state ~= Racing.STATE.PRERACE then return end
    if not Racing._config or not Racing._config.nodeA then return end
    pcall(function()
        local nodeA = Racing._config.nodeA
        local target = _getPlayerVehicle() or Game.GetPlayer()
        if target then
            local startHeading = _resolvePlayerStageHeading(nodeA, Racing._config.nodeB)
            _safeTeleport(target, nodeA, startHeading)
        end
    end)
        if mode ~= "quali" and _isRollingStart(cfg) then
            local speed = _getPlayerVehicleSpeedMps()
            local captureRadius = _tuningValue("startCaptureRadiusM", cfg)
            local rollingStartMaxSpeed = _tuningValue("rollingStartMaxSpeedMps", cfg)
            if not dist or dist > captureRadius then
                return false, "Drive into the rolling start corridor before launching."
            end
            if speed > rollingStartMaxSpeed then
                return false, i18n.format("Bleed speed below %.0f km/h for the rolling release.", rollingStartMaxSpeed * 3.6)
            end
            if not _canAdvanceRacePhase() then
                return false, i18n.format("Unpause before starting %s.", action)
            end
            return true, nil
        end
    -- Let the normal proximity gate arm qualifying once the player is settled.
    Racing._qualiProximityTriggered = false
    Racing._qualiCountdown          = nil
    Racing._qualiLastTickSec        = nil
    Racing._autoStageTriggered      = true
    Racing._stageSource             = "quali"
    if MTE.AIVehicles and MTE.AIVehicles.noteWorldDisruption then
        MTE.AIVehicles.noteWorldDisruption("teleport_to_start")
    end
    Racing._resetGridSpawnWindow("teleport_to_start")
end

function Racing._getVehicleId()
    local vid = nil
    pcall(function()
        local veh = Game.GetMountedVehicle(Game.GetPlayer())
        if veh then vid = tostring(veh:GetRecord():GetID()) end
    end)
    return vid
end

function Racing._checkVehicleClass(requiredClass)
    return true, nil
end

function Racing._checkTimeOfDay(required)
    if not required then return true, nil end
    local hour = 12
    pcall(function() hour = Game.GetTimeSystem():GetGameTime():Hours() end)
    local isNight = (hour >= 20 or hour < 5)
    if required == "night" and not isNight then
        return false, "This race requires night conditions (20:00–05:00)."
    end
    if required == "day" and isNight then
        return false, "This race requires daytime conditions (05:00–20:00)."
    end
    return true, nil
end

-- ── Utilities ─────────────────────────────────────────────────

function Racing._copyConfig(cfg)
    if type(cfg) ~= "table" then
        return {}
    end
    local copy = {}
    for k, v in pairs(cfg) do
        copy[k] = type(v) == "table" and Racing._shallowCopy(v) or v
    end
    return copy
end

function Racing._shallowCopy(t)
    if type(t) ~= "table" then
        return {}
    end
    local c = {}; for k, v in pairs(t) do c[k] = v end; return c
end

function Racing._tableHas(t, val)
    for _, v in ipairs(t) do if v == val then return true end end
    return false
end

function Racing._isRaceLegalNode(node)
    if not node then return false end
    if node.disabled == true then return false end
    if node.raceLegal == false then return false end
    if node.road == false then return false end
    if node.waypointable == false then return false end
    return true
end

function Racing._isUrbanNode(node)
    if not node then return false end
    if node.urban ~= nil then return node.urban == true end
    local x = node.x or 0
    local y = node.y or 0
    return x >= NIGHT_CITY_X_MIN and x <= NIGHT_CITY_X_MAX
       and y >= NIGHT_CITY_Y_MIN and y <= NIGHT_CITY_Y_MAX
end

function Racing._getFinishLineSettings()
    local cfg = Racing._config or {}
    local nodeB = cfg.nodeB or {}
    local explicitWidth = nodeB.finishWidthM or cfg.finishWidthM or (cfg.dragStrip and cfg.dragStrip.finishWidthM)
    local finishWidth = _tuningValue("finishLineWidthM", cfg)
    local finishArmDist = _tuningValue("finishArmDistM", cfg)
    local genericRoadWidth = _tuningValue("genericRoadFinishLineWidthM", cfg)
    local width = explicitWidth or finishWidth
    local armDist = nodeB.finishArmDistM or cfg.finishArmDistM or finishArmDist
    width = math.max(12.0, tonumber(width) or finishWidth)
    armDist = math.max(30.0, tonumber(armDist) or finishArmDist)
    if explicitWidth == nil and nodeB.road ~= false then
        width = math.max(width, genericRoadWidth)
    end
    return width, armDist
end

local function getActiveRoute()
    local cfg = Racing._config or {}
    if cfg.route then return cfg.route end
    return resolveRouteRecord(cfg)
end

local function findFieldEntryByDriverId(driverId)
    for _, entry in ipairs(Racing._field or {}) do
        if (entry.driverId or entry.id) == driverId then
            return entry
        end
    end
    return nil
end

local function computeProgressFromPosition(position)
    local route = getActiveRoute()
    if not route or not (MTE and MTE.Routes and MTE.Routes.computeProgress) then return nil end
    return MTE.Routes.computeProgress(route, position)
end

local function computeEstimatedProgress(finishTime)
    local route = getActiveRoute()
    if not route or not finishTime or not (MTE and MTE.Routes and MTE.Routes.estimateProgressFromTime) then return nil end
    return MTE.Routes.estimateProgressFromTime(route, Racing._raceTimer, finishTime)
end

resetSequenceRaceState = function()
    Racing._sequenceRaceState = nil
end

local function buildSequenceParticipantState()
    return {
        targetIndex = 1,
        currentLap = 1,
        completedDistance = 0.0,
        progress = 0.0,
        finished = false,
        finishTime = nil,
        checkpointIndex = 1,
    }
end

local function getSequenceTarget(sequenceRace, targetIndex)
    return sequenceRace and sequenceRace.targets and sequenceRace.targets[targetIndex] or nil
end

local function getCurrentSequenceWaypointNode()
    local sequenceState = Racing._sequenceRaceState
    if not (sequenceState and sequenceState.sequence and sequenceState.player) then
        return nil
    end
    return getSequenceTarget(sequenceState.sequence, sequenceState.player.targetIndex)
end

local function computeSequenceProgressSnapshot(sequenceRace, state, position)
    if type(sequenceRace) ~= "table" or type(state) ~= "table" then
        return nil
    end

    local totalDistance = math.max(1.0, tonumber(sequenceRace.totalDistance) or 1.0)
    if state.finished then
        return {
            completion = 1.0,
            distanceAlong = totalDistance,
            remainingDistance = 0.0,
            sectorIndex = math.max(1, tonumber(sequenceRace.totalTargets) or 1),
            currentLap = math.max(1, tonumber(sequenceRace.currentLapCount) or 1),
        }
    end

    local target = getSequenceTarget(sequenceRace, state.targetIndex)
    if not target then
        return {
            completion = 1.0,
            distanceAlong = totalDistance,
            remainingDistance = 0.0,
            sectorIndex = math.max(1, tonumber(sequenceRace.totalTargets) or 1),
            currentLap = state.currentLap or 1,
        }
    end

    local segmentDistance = math.max(1.0, tonumber(target.segmentDistance) or 1.0)
    local remainingToTarget = position and Racing._estimateDistance(position, target) or segmentDistance
    local distanceAlong = math.max(
        tonumber(state.completedDistance) or 0.0,
        (tonumber(target.cumulativeDistance) or 0.0) - math.min(segmentDistance, remainingToTarget))
    local remainingDistance = math.max(0.0, totalDistance - distanceAlong)
    return {
        completion = math.max(0.0, math.min(1.0, distanceAlong / totalDistance)),
        distanceAlong = distanceAlong,
        remainingDistance = remainingDistance,
        sectorIndex = math.max(1, tonumber(state.targetIndex) or 1),
        currentLap = state.currentLap or 1,
    }
end

local function advanceSequenceParticipant(sequenceRace, state, position)
    if type(sequenceRace) ~= "table" or type(state) ~= "table" or state.finished then
        return false
    end

    local target = getSequenceTarget(sequenceRace, state.targetIndex)
    if not target or not position then
        return false
    end
    if not Checkpoint.isNear(position, target, 50.0) then
        return false
    end

    state.completedDistance = tonumber(target.cumulativeDistance) or state.completedDistance or 0.0
    state.progress = (tonumber(state.targetIndex) or 1) * 1000.0
    state.currentLap = target.lapNumber or state.currentLap or 1
    state.checkpointIndex = state.targetIndex
    state.targetIndex = state.targetIndex + 1
    if state.targetIndex > (sequenceRace.totalTargets or 0) then
        state.finished = true
        return true
    end

    local nextTarget = getSequenceTarget(sequenceRace, state.targetIndex)
    if nextTarget and nextTarget.lapNumber and nextTarget.lapNumber > (state.currentLap or 1) then
        state.currentLap = nextTarget.lapNumber
    end
    return true
end

function Racing._beginSequenceRace()
    local sequenceRace = Racing._config and Racing._config.sequenceRace or nil
    if type(sequenceRace) ~= "table" then
        resetSequenceRaceState()
        return false
    end

    Racing._sequenceRaceState = {
        sequence = sequenceRace,
        player = buildSequenceParticipantState(),
        drivers = {},
    }

    for _, entry in ipairs(Racing._field or {}) do
        local driverId = entry.driverId or entry.id
        if driverId then
            Racing._sequenceRaceState.drivers[driverId] = buildSequenceParticipantState()
        end
    end

    if MTE and MTE.AIVehicles and MTE.AIVehicles.totalCount and MTE.AIVehicles.setWaypoints then
        local waypoints = Checkpoint.buildWaypoints(sequenceRace.targets, 1, false)
        for slotIndex = 1, math.min(#(Racing._field or {}), MTE.AIVehicles.totalCount()) do
            MTE.AIVehicles.setWaypoints(slotIndex, waypoints, false)
        end
    end

    -- GPS waypoint to first checkpoint
    if MTE.Mappins then
        local firstTarget = getSequenceTarget(sequenceRace, 1)
        if firstTarget then
            MTE.Mappins.setFinishWaypoint(firstTarget)
        end
    end

    return true
end

function Racing._updateSequenceRaceProgress()
    local sequenceState = Racing._sequenceRaceState
    local sequenceRace = sequenceState and sequenceState.sequence or nil
    if type(sequenceRace) ~= "table" then
        return false
    end

    local playerPosition = Racing._getPlayerPos()
    if playerPosition then
        local reached = advanceSequenceParticipant(sequenceRace, sequenceState.player, playerPosition)
        if reached and MTE.Mappins then
            local nextTarget = getSequenceTarget(sequenceRace, sequenceState.player.targetIndex)
            if nextTarget then
                MTE.Mappins.setFinishWaypoint(nextTarget)
            end
        end
    end

    local liveDrivers = MTE and MTE.AIVehicles and MTE.AIVehicles.getLiveDrivers and MTE.AIVehicles.getLiveDrivers() or {}
    for _, liveDriver in ipairs(liveDrivers or {}) do
        local driverId = liveDriver and liveDriver.id or nil
        local driverState = driverId and sequenceState.drivers[driverId] or nil
        if driverId and driverState and not driverState.finished and liveDriver.position then
            local reached = advanceSequenceParticipant(sequenceRace, driverState, liveDriver.position)
            if reached then
                local slotIndex = MTE and MTE.AIVehicles and MTE.AIVehicles.findSlotByDriverId and MTE.AIVehicles.findSlotByDriverId(driverId) or nil
                if slotIndex and MTE.AIVehicles and MTE.AIVehicles.advanceWaypoint then
                    MTE.AIVehicles.advanceWaypoint(slotIndex)
                end
            end
            if driverState.finished and not Racing._aiFinished[driverId] then
                Racing._aiFinished[driverId] = true
                Racing._aiFinishTime[driverId] = Racing._raceTimer
            end
        end
    end

    return true
end

function Racing.getPlayerRouteProgress()
    if Racing._sequenceRaceState and Racing._sequenceRaceState.sequence then
        return computeSequenceProgressSnapshot(
            Racing._sequenceRaceState.sequence,
            Racing._sequenceRaceState.player,
            Racing._getPlayerPos())
    end
    local pos = Racing._getPlayerPos()
    if not pos then return nil end
    return computeProgressFromPosition(pos)
end

function Racing._publishActiveRaceTelemetry()
    if Racing._state ~= Racing.STATE.RACING then return false end
    if not (MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.updateProgress) then return false end

    if Racing._sequenceRaceState and Racing._sequenceRaceState.sequence then
        local sequenceRace = Racing._sequenceRaceState.sequence
        local playerProgress = Racing.getPlayerRouteProgress()
        local standings = Racing.getLiveStandings() or {}
        local playerSnapshot = nil

        local participants = {}
        for standingPos, entry in ipairs(standings) do
            if entry.isPlayer then
                local playerSpeed = ((MTE.Telemetry and MTE.Telemetry.state and MTE.Telemetry.state.speed) or 0) * 3.6
                local snapshot = playerProgress or entry
                playerSnapshot = {
                    participantId = "player",
                    driverId = "player",
                    name = "V",
                    isPlayer = true,
                    completion = snapshot and (snapshot.completion or snapshot.progress) or 0.0,
                    distanceAlong = snapshot and snapshot.distanceAlong or 0.0,
                    remainingDistance = snapshot and (snapshot.remainingDistance or snapshot.distToFinish) or sequenceRace.totalDistance,
                    sectorIndex = snapshot and snapshot.sectorIndex or 1,
                    currentLap = snapshot and snapshot.currentLap or 1,
                    speed = playerSpeed,
                    raceTime = Racing._raceTimer,
                    provenance = "live",
                    standingPos = standingPos,
                }
            else
                table.insert(participants, {
                    participantId = entry.driverId or entry.id or entry.name,
                    driverId = entry.driverId or entry.id or entry.name,
                    name = entry.name,
                    isPlayer = false,
                    completion = entry.progress or 0.0,
                    distanceAlong = entry.distanceAlong or 0.0,
                    remainingDistance = entry.remainingDistance or entry.distToFinish,
                    sectorIndex = entry.sectorIndex or 1,
                    currentLap = entry.currentLap or 1,
                    speed = (entry.speed or 0) * 3.6,
                    raceTime = Racing._raceTimer,
                    provenance = entry.provenance or "live",
                    finishStatus = entry.finished and "classified" or "pending",
                    standingPos = standingPos,
                })
            end
        end

        if not playerSnapshot and playerProgress then
            local playerSpeed = ((MTE.Telemetry and MTE.Telemetry.state and MTE.Telemetry.state.speed) or 0) * 3.6
            playerSnapshot = {
                participantId = "player",
                driverId = "player",
                name = "V",
                isPlayer = true,
                completion = playerProgress.completion,
                distanceAlong = playerProgress.distanceAlong,
                remainingDistance = playerProgress.remainingDistance,
                sectorIndex = playerProgress.sectorIndex,
                currentLap = playerProgress.currentLap,
                speed = playerSpeed,
                raceTime = Racing._raceTimer,
                provenance = "live",
            }
        end

        return MTE.RaceTelemetry.updateProgress({
            raceTime = Racing._raceTimer,
            totalDistance = sequenceRace.totalDistance,
            player = playerSnapshot,
            participants = participants,
        })
    end

    local route = getActiveRoute()
    if not route then return false end

    local playerProgress = Racing.getPlayerRouteProgress()
    local standings = Racing.getLiveStandings() or {}
    local playerSnapshot = nil

    local participants = {}
    for standingPos, entry in ipairs(standings) do
        if entry.isPlayer then
            local playerSpeed = ((MTE.Telemetry and MTE.Telemetry.state and MTE.Telemetry.state.speed) or 0) * 3.6
            local snapshot = playerProgress or entry
            playerSnapshot = {
                participantId = "player",
                driverId = "player",
                name = "V",
                isPlayer = true,
                completion = snapshot and (snapshot.completion or snapshot.progress) or 0.0,
                distanceAlong = snapshot and snapshot.distanceAlong or 0.0,
                remainingDistance = snapshot and (snapshot.remainingDistance or snapshot.distToFinish) or (route.totalDistance or Racing._config.distance),
                sectorIndex = snapshot and snapshot.sectorIndex or 1,
                currentLap = snapshot and snapshot.currentLap or 1,
                lateralDistance = snapshot and snapshot.lateralDistance or nil,
                speed = playerSpeed,
                raceTime = Racing._raceTimer,
                provenance = "live",
                standingPos = standingPos,
            }
        else
            table.insert(participants, {
                participantId = entry.driverId or entry.id or entry.name,
                driverId = entry.driverId or entry.id or entry.name,
                name = entry.name,
                isPlayer = false,
                completion = entry.progress or 0.0,
                distanceAlong = entry.distanceAlong or 0.0,
                remainingDistance = entry.remainingDistance or entry.distToFinish,
                sectorIndex = entry.sectorIndex or 1,
                lateralDistance = entry.lateralDistance,
                currentLap = entry.currentLap or 1,
                speed = (entry.speed or 0) * 3.6,
                raceTime = Racing._raceTimer,
                provenance = entry.provenance or "estimated",
                finishStatus = entry.finished and "classified" or "pending",
                standingPos = standingPos,
            })
        end
    end

    if not playerSnapshot and playerProgress then
        local playerSpeed = ((MTE.Telemetry and MTE.Telemetry.state and MTE.Telemetry.state.speed) or 0) * 3.6
        playerSnapshot = {
            participantId = "player",
            driverId = "player",
            name = "V",
            isPlayer = true,
            completion = playerProgress.completion,
            distanceAlong = playerProgress.distanceAlong,
            remainingDistance = playerProgress.remainingDistance,
            sectorIndex = playerProgress.sectorIndex,
            currentLap = playerProgress.currentLap,
            lateralDistance = playerProgress.lateralDistance,
            speed = playerSpeed,
            raceTime = Racing._raceTimer,
            provenance = "live",
        }
    end

    return MTE.RaceTelemetry.updateProgress({
        raceTime = Racing._raceTimer,
        totalDistance = route.totalDistance or Racing._config.distance,
        player = playerSnapshot,
        participants = participants,
    })
end

local function _abbreviateMarkerName(name)
    local text = tostring(name or "?")
    if #text > 16 then
        text = text:sub(1, 16)
    end
    return text
end

local function _buildRacerMarkerCaption(title, roleLabel, color)
    return i18n.format(
        "MT_Ecosystem|%s|%s|%.2f|%.2f|%.2f|%.2f|car|racer",
        tostring(title or "Racer"),
        tostring(roleLabel or "Race rival"),
        tonumber(color[1] or 1.0),
        tonumber(color[2] or 1.0),
        tonumber(color[3] or 1.0),
        tonumber(color[4] or 1.0))
end

function Racing._updateRacerMarkers()
    if Racing._state ~= Racing.STATE.RACING then
        _clearRacerMarkers()
        return false
    end
    if Racing._ghostFallbackActive then
        _clearRacerMarkers()
        return false
    end
    if not (MTE and MTE.Mappins and MTE.Mappins.updateRacerMarkers) then
        return false
    end
    if not (MTE.AIVehicles and MTE.AIVehicles.getLiveDrivers) then
        _clearRacerMarkers()
        return false
    end

    local liveById = {}
    for _, driver in ipairs(MTE.AIVehicles.getLiveDrivers() or {}) do
        if driver and driver.id and driver.position then
            liveById[driver.id] = driver
        end
    end

    local standings = Racing.getLiveStandings() or {}
    local playerIndex = nil
    for index, entry in ipairs(standings) do
        if entry.isPlayer then
            playerIndex = index
            break
        end
    end

    if not playerIndex then
        _clearRacerMarkers()
        return false
    end

    local selected = {}
    local markers = {}
    local function addMarker(entry, standingIndex, roleLabel, color)
        if not entry or entry.isPlayer or not entry.driverId or selected[entry.driverId] then
            return false
        end

        local liveDriver = liveById[entry.driverId]
        if not (liveDriver and liveDriver.position) then
            return false
        end

        selected[entry.driverId] = true
        table.insert(markers, {
            driverId = entry.driverId,
            title = i18n.format("P%d %s", standingIndex, _abbreviateMarkerName(entry.name)),
            caption = _buildRacerMarkerCaption(
                i18n.format("P%d %s", standingIndex, _abbreviateMarkerName(entry.name)),
                roleLabel,
                color),
            position = {
                x = liveDriver.position.x,
                y = liveDriver.position.y,
                z = (liveDriver.position.z or 0) + 2.2,
            },
        })
        return #markers < 4
    end

    for _, offset in ipairs({ -1, 1, -2, 2, -3, 3 }) do
        local idx = playerIndex + offset
        local entry = standings[idx]
        if entry and entry.isRival then
            local roleLabel = offset < 0 and "Rival ahead" or "Rival behind"
            addMarker(entry, idx, roleLabel, { 1.00, 0.54, 0.14, 1.00 })
            if #markers >= 4 then
                return MTE.Mappins.updateRacerMarkers(markers)
            end
            break
        end
    end

    addMarker(standings[playerIndex - 1], playerIndex - 1, "Car ahead", { 1.00, 0.32, 0.30, 1.00 })
    if #markers >= 4 then
        return MTE.Mappins.updateRacerMarkers(markers)
    end

    addMarker(standings[playerIndex + 1], playerIndex + 1, "Car behind", { 0.28, 0.88, 1.00, 1.00 })
    if #markers >= 4 then
        return MTE.Mappins.updateRacerMarkers(markers)
    end

    local radius = 2
    while #markers < 4 and radius <= #standings do
        local aheadIdx = playerIndex - radius
        if aheadIdx >= 1 then
            addMarker(standings[aheadIdx], aheadIdx, "Nearby contender", { 1.00, 0.92, 0.32, 1.00 })
        end
        if #markers >= 4 then
            break
        end
        local behindIdx = playerIndex + radius
        if behindIdx <= #standings then
            addMarker(standings[behindIdx], behindIdx, "Nearby contender", { 1.00, 0.92, 0.32, 1.00 })
        end
        radius = radius + 1
    end

    if #markers == 0 then
        _clearRacerMarkers()
        return false
    end

    return MTE.Mappins.updateRacerMarkers(markers)
end

-- ── Accessors for UI ──────────────────────────────────────────

local function _getHUDRaceModeInfo(config)
    local cfg = config or Racing._config or {}
    local raceType = tostring(cfg.raceType or "sprint")
    if raceType == "drag" then
        return "drag", "DRAG"
    end
    if raceType == "endurance" then
        return "endurance", "ENDURANCE"
    end
    if raceType == "knockout" then
        return "knockout", "KNOCKOUT"
    end

    local lapCount = math.max(1, tonumber(cfg.lapCount) or 1)
    local sequenceRace = cfg.sequenceRace
    if lapCount > 1 or (type(sequenceRace) == "table" and sequenceRace.kind == "sprint_laps") then
        return "sprint_laps", "SPRINT LAPS"
    end
    return "sprint", "SPRINT"
end

-- ── Live drag driving-straightness tracking ───────────────────
-- Measures how straight the player actually drives during a drag race,
-- replacing the static route-geometry score with a live driving score.

Racing._dragLive = nil

function Racing._initDragLiveStraightness()
    Racing._dragLive = nil
    local cfg = Racing._config
    if not cfg or tostring(cfg.raceType) ~= "drag" then return end
    local nodeA = cfg.nodeA
    local nodeB = cfg.nodeB
    if not nodeA or not nodeB then return end
    local ax, ay = tonumber(nodeA.x) or 0, tonumber(nodeA.y) or 0
    local bx, by = tonumber(nodeB.x) or 0, tonumber(nodeB.y) or 0
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1.0 then return end
    Racing._dragLive = {
        ax = ax, ay = ay,
        dx = dx, dy = dy,
        len = len,
        maxDev = 0.0,
        totalDev = 0.0,
        sampleCount = 0,
    }
end

function Racing._updateDragLiveStraightness()
    local live = Racing._dragLive
    if not live then return end
    local cfg = Racing._config
    if not cfg or not cfg.dragStrip then return end

    local pos = nil
    pcall(function()
        local anchor = _getPlayerVehicle() or Game.GetPlayer()
        if anchor and anchor.GetWorldPosition then
            pos = anchor:GetWorldPosition()
        end
    end)
    if not pos then return end

    local px = (tonumber(pos.x) or 0) - live.ax
    local py = (tonumber(pos.y) or 0) - live.ay
    local lateralDev = math.abs((px * live.dy) - (py * live.dx)) / live.len

    live.sampleCount = live.sampleCount + 1
    live.totalDev = live.totalDev + lateralDev
    if lateralDev > live.maxDev then
        live.maxDev = lateralDev
    end

    -- Recompute score using the same formula as _computeDragStraightness
    local maxPathDeviation = math.max(0.01, _tuningValue("dragRouteMaxPathDeviationM", cfg))
    local avgPathDeviation = math.max(0.01, _tuningValue("dragRouteAvgPathDeviationM", cfg))
    local penaltyMax = math.max(0.0, _tuningValue("dragStraightnessPenaltyMaxS", cfg))
    local penaltyExponent = math.max(1.0, _tuningValue("dragStraightnessPenaltyExponent", cfg))

    local maxLoad = _clamp01(live.maxDev / maxPathDeviation)
    local avgLoad = _clamp01((live.totalDev / live.sampleCount) / avgPathDeviation)
    local straightnessLoad = _clamp01((maxLoad * 0.65) + (avgLoad * 0.35))
    local penaltyLoad = straightnessLoad <= 0.0 and 0.0 or math.pow(straightnessLoad, penaltyExponent)

    cfg.dragStrip.straightnessScore = math.max(0, math.min(100, math.floor(((1.0 - straightnessLoad) * 100.0) + 0.5)))
    cfg.dragStrip.straightnessPenaltyS = penaltyMax * penaltyLoad
    cfg.dragStrip.straightnessSummary = i18n.format("STR %d  |  PEN +%.2fs", cfg.dragStrip.straightnessScore, cfg.dragStrip.straightnessPenaltyS)
end

function Racing.getHUDRaceState()
    local cfg = Racing._config or {}
    local dragStrip = cfg.dragStrip or {}
    local raceMode, raceModeLabel = _getHUDRaceModeInfo(cfg)
    local state = {
        raceMode = raceMode,
        raceModeLabel = raceModeLabel,
        sequenceActive = false,
        currentLap = 1,
        totalLaps = math.max(1, tonumber(cfg.lapCount) or 1),
        currentTargetIndex = 0,
        totalTargets = 0,
        targetLabel = "",
        progressLabel = "",
        phaseLabel = "",
        objectiveText = "",
        statusText = "",
        finishState = "racing",
        classificationPendingCount = 0,
        distanceToTarget = Racing.getDistanceToFinish(),
        dragStraightnessScore = math.max(0, math.floor(tonumber(dragStrip.straightnessScore) or 0)),
        dragPenaltySeconds = math.max(0.0, tonumber(dragStrip.straightnessPenaltyS) or 0.0),
        dragLaneCount = math.max(0, math.floor(tonumber(dragStrip.effectiveLaneCount) or 0)),
        dragLaneOrder = tostring(dragStrip.laneOrderText or ""),
    }

    if Racing._finishResolver then
        local resolver = Racing.getFinishResolverSummary() or {}
        local pending = math.max(0, tonumber(resolver.pending or 0) or 0)
        local waitLeft = math.max(0.0, (resolver.waitTarget or 0.0) - (resolver.elapsed or 0.0))
        state.finishState = "classifying"
        state.classificationPendingCount = pending
        state.phaseLabel = raceModeLabel .. "  FINISH"
        if pending > 0 then
            state.objectiveText = i18n.format(
                "Classifying %d trailing rival%s",
                pending,
                pending == 1 and "" or "s")
            state.statusText = i18n.format("Hold for official order  %.1fs", waitLeft)
        else
            state.objectiveText = "Sealing final classification"
            state.statusText = "Final order pending"
        end
        return state
    end

    local sequenceRuntime = Racing._sequenceRaceState
    local sequenceRace = (sequenceRuntime and sequenceRuntime.sequence) or cfg.sequenceRace
    if type(sequenceRace) == "table" then
        state.sequenceActive = true
        state.totalTargets = math.max(0, tonumber(sequenceRace.totalTargets) or 0)

        local playerState = sequenceRuntime and sequenceRuntime.player or nil
        local progress = Racing.getPlayerRouteProgress()
        if progress and progress.currentLap then
            state.currentLap = math.max(1, tonumber(progress.currentLap) or 1)
        elseif playerState and playerState.currentLap then
            state.currentLap = math.max(1, tonumber(playerState.currentLap) or 1)
        end

        if playerState and playerState.targetIndex then
            state.currentTargetIndex = math.max(1, tonumber(playerState.targetIndex) or 1)
        elseif state.totalTargets > 0 then
            state.currentTargetIndex = 1
        end

        if state.totalTargets > 0 and state.currentTargetIndex > state.totalTargets then
            state.currentTargetIndex = state.totalTargets
        end

        local target = getSequenceTarget(sequenceRace, state.currentTargetIndex)
        state.targetLabel = target and tostring(target.name or target.id or "") or ""
        if progress and progress.remainingDistance ~= nil then
            state.distanceToTarget = progress.remainingDistance
        end

        if sequenceRace.kind == "endurance" then
            state.phaseLabel = i18n.format("%s  L%d/%d", raceModeLabel, state.currentLap, state.totalLaps)
            if state.totalTargets > 0 then
                state.progressLabel = i18n.format("Checkpoint %d/%d", state.currentTargetIndex, state.totalTargets)
            end
        else
            if state.totalLaps > 1 then
                state.phaseLabel = i18n.format("%s  L%d/%d", raceModeLabel, state.currentLap, state.totalLaps)
            else
                state.phaseLabel = raceModeLabel
            end
            if state.totalTargets > 0 then
                state.progressLabel = i18n.format("Leg %d/%d", state.currentTargetIndex, state.totalTargets)
            end
        end

        if state.progressLabel ~= "" and state.targetLabel ~= "" then
            state.objectiveText = state.progressLabel .. "  " .. state.targetLabel
        else
            state.objectiveText = state.progressLabel ~= "" and state.progressLabel or state.targetLabel
        end

        if playerState and playerState.finished then
            state.finishState = "finished"
            state.phaseLabel = raceModeLabel .. "  FINISH"
            state.statusText = "Awaiting final classification"
        else
            state.statusText = state.progressLabel
        end

        return state
    end

    if raceMode == "drag" then
        local penaltyText = i18n.format("PEN +%.2fs", state.dragPenaltySeconds)
        local laneText = state.dragLaneOrder ~= "" and ("LANES " .. state.dragLaneOrder) or nil
        state.phaseLabel = i18n.format("%s  STR %d", raceModeLabel, state.dragStraightnessScore)
        state.objectiveText = cfg.nodeB and cfg.nodeB.name and ("TRAPS  " .. tostring(cfg.nodeB.name)) or "Straight shot to the finish"
        state.statusText = laneText and (laneText .. "  |  " .. penaltyText) or penaltyText
    elseif raceMode == "endurance" then
        state.phaseLabel = i18n.format("%s  L1/%d", raceModeLabel, state.totalLaps)
    end

    return state
end

--- Returns the current grid-light phase (5 = all red, 0 = GO/green).
--- Lights build up one by one over the 3-second countdown, then all go green.
function Racing.getCountdownPhase()
    if Racing._state ~= Racing.STATE.COUNTDOWN then return -1 end
    if Racing._countdownUseLights == false then return -1 end
    local t = Racing._raceTimer
    local duration = math.max(0.1, tonumber(Racing._countdownDuration) or 3.0)
    local phaseWindow = duration / 5.0
    if t <= 0 then return 0 end  -- GO
    if t <= phaseWindow then return 5 end
    if t <= phaseWindow * 2 then return 4 end
    if t <= phaseWindow * 3 then return 3 end
    if t <= phaseWindow * 4 then return 2 end
    return 1  -- first light only
end

--- Returns formatted gap text to the car immediately ahead.
--- "LEAD" if P1, "+X.Xs" if behind, "" if not racing.
--- In entity mode, gap is expressed as metres; in ghost mode, as time delta.
function Racing.getGapText()
    if Racing._state ~= Racing.STATE.RACING then return "" end
    local standings = Racing.getLiveStandings()
    -- Find player index
    local playerIdx  = nil
    local playerEntry = nil
    for i, e in ipairs(standings) do
        if e.isPlayer then playerIdx = i; playerEntry = e; break end
    end
    if not playerIdx then return "" end
    if playerIdx == 1 then return "LEAD" end
    -- Driver just ahead
    local ahead = standings[playerIdx - 1]
    if not ahead then return "" end

    if ahead.distanceAlong and playerEntry.distanceAlong then
        local gapM = ahead.distanceAlong - playerEntry.distanceAlong
        if gapM < 0 then gapM = 0 end
        if gapM >= 1000 then
            return i18n.format("+%.1fkm", gapM / 1000)
        else
            return i18n.format("+%dm", math.floor(gapM))
        end
    end

    -- Ghost/fallback: time-projection delta
    local gap = Racing._raceTimer - (ahead.time or 0)
    if gap < 0 then gap = 0 end
    return i18n.format("+%.1fs", gap)
end

--- Returns formatted gap text to the car immediately behind.
--- "" if last place or not racing.
function Racing.getGapBehindText()
    if Racing._state ~= Racing.STATE.RACING then return "" end
    local standings = Racing.getLiveStandings()
    local playerIdx = nil
    local playerEntry = nil
    for i, e in ipairs(standings) do
        if e.isPlayer then playerIdx = i; playerEntry = e; break end
    end
    if not playerIdx then return "" end
    if playerIdx >= #standings then return "" end
    local behind = standings[playerIdx + 1]
    if not behind then return "" end

    if behind.distanceAlong and playerEntry.distanceAlong then
        local gapM = playerEntry.distanceAlong - behind.distanceAlong
        if gapM < 0 then gapM = 0 end
        if gapM >= 1000 then
            return i18n.format("↓ %.1fkm", gapM / 1000)
        else
            return i18n.format("↓ %dm", math.floor(gapM))
        end
    end

    local gap = (behind.time or 0) - Racing._raceTimer
    if gap < 0 then gap = 0 end
    return i18n.format("↓ %.1fs", gap)
end

function Racing.getState()        return Racing._state        end
function Racing.getField()        return Racing._field         end
function Racing.getRaceEntries()  return Racing._field         end  -- alias: explicit name
function Racing.getConfig()       return Racing._config        end
function Racing.getResults()      return Racing._results       end
function Racing.getRaceTimer()    return Racing._raceTimer     end
function Racing.getStake()        return Racing._stakeAmount   end
function Racing.getDraft()        return Racing._draft         end
function Racing.getQualiGridPos() return Racing._qualiGridPos  end

function Racing.getCurrentWaypointNode()
    local state = Racing._state
    local config = Racing._config or {}

    if state == Racing.STATE.IDLE or state == Racing.STATE.RESULTS then
        return nil
    end

    if state == Racing.STATE.CONFIG then
        return config.nodeA or config.nodeB or nil
    end

    if state == Racing.STATE.PRERACE then
        local ready = false
        if type(Racing.getStartReadiness) == "function" then
            ready = select(1, Racing.getStartReadiness()) == true
        end
        if ready then
            return getCurrentSequenceWaypointNode() or config.nodeB or config.nodeA or nil
        end
        return config.nodeA or getCurrentSequenceWaypointNode() or config.nodeB or nil
    end

    if state == Racing.STATE.QUALI or state == Racing.STATE.COUNTDOWN or state == Racing.STATE.RACING then
        return getCurrentSequenceWaypointNode() or config.nodeB or config.nodeA or nil
    end

    return config.nodeB or config.nodeA or nil
end

function Racing.routePlayerToObjective()
    local node = Racing.getCurrentWaypointNode()
    if not node then
        return false, "No race target is available right now."
    end
    if not (MTE and MTE.Mappins and MTE.Mappins.setGpsWaypoint) then
        return false, "GPS routing is unavailable right now."
    end
    MTE.Mappins.setGpsWaypoint(node)
    return true, tostring(node.name or node.id or "race objective")
end

function Racing.isFinishResolverActive()
    return Racing._finishResolver ~= nil
end

function Racing.getFinishResolverSummary()
    local resolver = Racing._finishResolver
    if not resolver then
        return nil
    end
    return {
        elapsed = math.max(0.0, Racing._raceTimer - (resolver.startedAt or Racing._raceTimer)),
        waitTarget = resolver.waitTarget or _tuningValue("finishResolveMinWaitS", Racing._config),
        pending = Racing._countPendingResolverEntries(resolver),
    }
end

--- Returns sorted quali standings: { { name, time, isPlayer, driverId }, ... }
--- Only available after qualifying has been completed.
function Racing.getQualiStandings()
    if not Racing._qualiTime then return nil end
    local entries = {}
    for _, d in ipairs(Racing._field) do
        table.insert(entries, {
            name     = d.displayName or d.name or d.id or "?",
            driverId = d.driverId or d.id,
            time     = d._qualiEst or 999,
            isPlayer = false,
        })
    end
    table.insert(entries, {
        name     = "V",
        time     = Racing._qualiTime,
        isPlayer = true,
    })
    table.sort(entries, function(a, b) return a.time < b.time end)
    return entries
end

--- Estimated player position during RACING state.
--- Uses live entity positions when available, falls back to time-projection.
function Racing.getEstimatedPosition()
    if Racing._state ~= Racing.STATE.RACING then return nil end
    for index, entry in ipairs(Racing.getLiveStandings()) do
        if entry.isPlayer then
            return index
        end
    end
    return 1
end

--- Returns a live standings snapshot for the race HUD.
--- Primary truth: entity positions (distance to finish).
--- Fallback: aiTime projection (ghost race / no entities).
--- Each entry: { name, driverId, isPlayer, finished, time, distToFinish, speed, launchable }
function Racing.getLiveStandings()
    local t       = Racing._raceTimer
    local entries = {}

    if Racing._sequenceRaceState and Racing._sequenceRaceState.sequence then
        local sequenceRace = Racing._sequenceRaceState.sequence
        local liveById = {}
        if MTE and MTE.AIVehicles and MTE.AIVehicles.getLiveDrivers then
            for _, driver in ipairs(MTE.AIVehicles.getLiveDrivers() or {}) do
                if driver and driver.id then
                    liveById[driver.id] = driver
                end
            end
        end

        for _, fieldEntry in ipairs(Racing._field or {}) do
            local driverId = fieldEntry.driverId or fieldEntry.id
            local liveDriver = driverId and liveById[driverId] or nil
            local driverState = driverId and Racing._sequenceRaceState.drivers[driverId] or nil
            if driverId and driverState then
                local snapshot = computeSequenceProgressSnapshot(sequenceRace, driverState, liveDriver and liveDriver.position or nil)
                table.insert(entries, {
                    name = fieldEntry.displayName or fieldEntry.name or driverId,
                    driverId = driverId,
                    isPlayer = false,
                    finished = driverState.finished == true,
                    time = Racing._aiFinishTime[driverId] or fieldEntry.aiTime or 999,
                    progress = snapshot and snapshot.completion or 0.0,
                    distanceAlong = snapshot and snapshot.distanceAlong or 0.0,
                    remainingDistance = snapshot and snapshot.remainingDistance or sequenceRace.totalDistance,
                    distToFinish = snapshot and snapshot.remainingDistance or sequenceRace.totalDistance,
                    sectorIndex = snapshot and snapshot.sectorIndex or 1,
                    currentLap = snapshot and snapshot.currentLap or 1,
                    speed = liveDriver and liveDriver.speed or 0,
                    launchable = liveDriver and liveDriver.isActive,
                    isRival = fieldEntry.isRival or false,
                    provenance = liveDriver and liveDriver.position and "live" or "estimated",
                })
            end
        end

        local playerSnapshot = Racing.getPlayerRouteProgress()
        table.insert(entries, {
            name = "V",
            isPlayer = true,
            finished = Racing._sequenceRaceState.player and Racing._sequenceRaceState.player.finished == true,
            time = t,
            progress = playerSnapshot and playerSnapshot.completion or 0.0,
            distanceAlong = playerSnapshot and playerSnapshot.distanceAlong or 0.0,
            remainingDistance = playerSnapshot and playerSnapshot.remainingDistance or sequenceRace.totalDistance,
            distToFinish = playerSnapshot and playerSnapshot.remainingDistance or sequenceRace.totalDistance,
            sectorIndex = playerSnapshot and playerSnapshot.sectorIndex or 1,
            currentLap = playerSnapshot and playerSnapshot.currentLap or 1,
            provenance = "live",
        })

        table.sort(entries, function(a, b)
            if a.finished and not b.finished then return true end
            if not a.finished and b.finished then return false end
            if a.finished and b.finished then return (a.time or 999) < (b.time or 999) end
            if (a.progress or 0.0) ~= (b.progress or 0.0) then
                return (a.progress or 0.0) > (b.progress or 0.0)
            end
            return (a.remainingDistance or 999999) < (b.remainingDistance or 999999)
        end)
        return entries
    end

    local requireActiveEntityPositions = LIVE_RIVALS_POST_START and not Racing._isGhostFallbackActive()
    local route = getActiveRoute()
    local totalDistance = (route and route.totalDistance) or (Racing._config and Racing._config.distance) or 0.0

    -- Try entity-based standings
    local useEntityPositions = false
    local liveDrivers = nil
    if MTE.AIVehicles and MTE.AIVehicles.getLiveDrivers and Racing._finishNode then
        liveDrivers = MTE.AIVehicles.getLiveDrivers()
        if liveDrivers and #liveDrivers > 0 then
            for _, ld in ipairs(liveDrivers) do
                if ld.position and (not requireActiveEntityPositions or ld.isActive) then
                    useEntityPositions = true
                    break
                end
            end
        end
    end

    if useEntityPositions then
        for _, ld in ipairs(liveDrivers) do
            if not requireActiveEntityPositions or ld.isActive then
                local finished = Racing._aiFinished[ld.id] == true
                local progress = ld.position and computeProgressFromPosition(ld.position) or nil
                local fieldEntry = findFieldEntryByDriverId(ld.id)
                if not progress and fieldEntry and fieldEntry.aiTime then
                    progress = computeEstimatedProgress(fieldEntry.aiTime)
                end
                table.insert(entries, {
                    name         = ld.name or "?",
                    driverId     = ld.id,
                    isPlayer     = false,
                    finished     = finished,
                    time         = Racing._aiFinishTime[ld.id] or (ld.driver and ld.driver.aiTime or 999),
                    progress     = finished and 1.0 or (progress and progress.completion or 0.0),
                    distanceAlong = finished and totalDistance or (progress and progress.distanceAlong or 0.0),
                    remainingDistance = finished and 0.0 or (progress and progress.remainingDistance or totalDistance),
                    distToFinish = finished and 0.0 or (progress and progress.remainingDistance or totalDistance),
                    sectorIndex  = progress and progress.sectorIndex or 1,
                    lateralDistance = progress and progress.lateralDistance or nil,
                    speed        = ld.speed or 0,
                    launchable   = ld.isActive,
                    isRival      = fieldEntry and fieldEntry.isRival or false,
                    provenance   = ld.position and "live" or "estimated",
                })
            end
        end

        local playerProgress = Racing.getPlayerRouteProgress()
        table.insert(entries, {
            name         = "V",
            isPlayer     = true,
            finished     = false,
            time         = t,
            progress     = playerProgress and playerProgress.completion or 0.0,
            distanceAlong = playerProgress and playerProgress.distanceAlong or 0.0,
            remainingDistance = playerProgress and playerProgress.remainingDistance or totalDistance,
            distToFinish = playerProgress and playerProgress.remainingDistance or totalDistance,
            sectorIndex  = playerProgress and playerProgress.sectorIndex or 1,
            lateralDistance = playerProgress and playerProgress.lateralDistance or nil,
            provenance   = "live",
        })

        table.sort(entries, function(a, b)
            if a.finished and not b.finished then return true end
            if not a.finished and b.finished then return false end
            if a.finished and b.finished then return (a.time or 999) < (b.time or 999) end
            if (a.progress or 0.0) ~= (b.progress or 0.0) then
                return (a.progress or 0.0) > (b.progress or 0.0)
            end
            return (a.remainingDistance or 999999) < (b.remainingDistance or 999999)
        end)
        _rememberLiveStandings(entries)
    else
        if LIVE_RIVALS_POST_START and not Racing._isGhostFallbackActive() then
            local playerProgress = Racing.getPlayerRouteProgress()
            table.insert(entries, {
                name     = "V",
                isPlayer = true,
                finished = false,
                time     = t,
                progress = playerProgress and playerProgress.completion or 0.0,
                distanceAlong = playerProgress and playerProgress.distanceAlong or 0.0,
                remainingDistance = playerProgress and playerProgress.remainingDistance or totalDistance,
                distToFinish = playerProgress and playerProgress.remainingDistance or totalDistance,
                sectorIndex = playerProgress and playerProgress.sectorIndex or 1,
                provenance = "live",
            })
            return entries
        end
        -- Fallback: time-projection (ghost race / no entities)
        for _, d in ipairs(Racing._field) do
            local progress = computeEstimatedProgress(d.aiTime)
            table.insert(entries, {
                name     = d.displayName or d.name or d.id or "?",
                driverId = d.driverId or d.id,
                isPlayer = false,
                finished = (d.aiTime or 999) <= t,
                time     = d.aiTime or 999,
                isRival  = d.isRival or false,
                progress = progress and progress.completion or 0.0,
                distanceAlong = progress and progress.distanceAlong or 0.0,
                remainingDistance = progress and progress.remainingDistance or totalDistance,
                distToFinish = progress and progress.remainingDistance or totalDistance,
                sectorIndex = progress and progress.sectorIndex or 1,
                provenance = "ghost",
            })
        end
        local playerProgress = Racing.getPlayerRouteProgress()
        table.insert(entries, {
            name     = "V",
            isPlayer = true,
            finished = false,
            time     = t,
            progress = playerProgress and playerProgress.completion or 0.0,
            distanceAlong = playerProgress and playerProgress.distanceAlong or 0.0,
            remainingDistance = playerProgress and playerProgress.remainingDistance or totalDistance,
            distToFinish = playerProgress and playerProgress.remainingDistance or totalDistance,
            sectorIndex = playerProgress and playerProgress.sectorIndex or 1,
            provenance = "live",
        })
        table.sort(entries, function(a, b)
            if a.finished and not b.finished then return true end
            if not a.finished and b.finished then return false end
            if a.finished and b.finished then return (a.time or 999) < (b.time or 999) end
            if (a.progress or 0.0) ~= (b.progress or 0.0) then
                return (a.progress or 0.0) > (b.progress or 0.0)
            end
            return (a.remainingDistance or 999999) < (b.remainingDistance or 999999)
        end)
    end

    return entries
end

--- Distance to finish: projected along the approach direction.
--- Positive = still approaching; negative = past the line.
function Racing.getDistanceToFinish()
    local progress = Racing.getPlayerRouteProgress()
    if progress then
        return progress.remainingDistance
    end
    local pos = Racing._getPlayerPos()
    if not pos or not Racing._finishNode then return nil end
    if not Racing._finishDir then
        local dx = pos.x - Racing._finishNode.x
        local dy = pos.y - Racing._finishNode.y
        local dz = pos.z - Racing._finishNode.z
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end
    local rx = pos.x - Racing._finishNode.x
    local ry = pos.y - Racing._finishNode.y
    return rx * (-Racing._finishDir.x) + ry * (-Racing._finishDir.y)
end

return Racing



