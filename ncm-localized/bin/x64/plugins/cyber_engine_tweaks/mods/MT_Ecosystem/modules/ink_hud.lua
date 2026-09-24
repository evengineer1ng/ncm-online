-- ============================================================
-- MT_Ecosystem: modules/ink_hud.lua
-- Bridges CET telemetry/racing data to the RedScript native HUD.
-- Every frame we construct an MTEHudUpdateEvent and queue it
-- through the game's UISystem so the .reds code can update
-- native ink widgets that render during normal gameplay.
-- ============================================================

local InkHUD = {}
local i18n = require("modules/i18n")
local Telemetry = require("modules/telemetry")
local Metrics = require("modules/metrics")
local Tuning = require("modules/tuning")

local function resolveModules()
    if not Telemetry then Telemetry = (MTE and MTE.Telemetry) or require("modules/telemetry") end
    if not Metrics then Metrics = (MTE and MTE.Metrics) or require("modules/metrics") end
    if not Tuning then Tuning = (MTE and MTE.Tuning) or require("modules/tuning") end
    return Telemetry and Metrics and Tuning
end

local function formatTime(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return "--:--.--" end
    local minutes = math.floor(seconds / 60)
    local remaining = seconds - (minutes * 60)
    return i18n.format("%d:%05.2f", minutes, remaining)
end

local function formatDelta(seconds)
    if type(seconds) ~= "number" then return "--.--" end
    local sign = seconds < 0 and "-" or "+"
    return i18n.format("%s%.2f", sign, math.abs(seconds))
end

local function sectorBestFor(timing, sectorNumber)
    if not timing then return nil end
    return timing["routeBestSector" .. tostring(sectorNumber)]
end

local function buildTimingCallout(timing)
    if not timing then return "" end
    if timing.lastSectorTime then
        local prefix = timing.lastSectorWasRouteBest and "PURPLE" or
            (timing.lastSectorWasSessionBest and "BEST" or "SECTOR")
        return i18n.format("%s S%d %s",
            prefix,
            timing.lastSectorNumber or 1,
            formatTime(timing.lastSectorTime))
    end
    if timing.lastLapTime then
        local prefix = timing.lastLapWasRouteBest and "PURPLE LAP" or
            (timing.lastLapWasSessionBest and "BEST LAP" or "LAST LAP")
        return i18n.format("%s %s", prefix, formatTime(timing.lastLapTime))
    end
    return ""
end

-- Cached UI system reference
local _uiSystem = nil
local _gridSpawnHudPause = false

-- Cached root HUD controller (captured via ObserveAfter).
-- We only use this to create widgets when the gameplay HUD appears.
InkHUD.controller = nil

-- â”€â”€ Public: called once on mod init â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function InkHUD.init()
    _uiSystem = nil
    _gridSpawnHudPause = false
    InkHUD.controller = nil
end

-- â”€â”€ Public: attach observer to capture the root HUD controller â”€â”€
--- Must be called once during onInit. Uses ObserveAfter to hook
--- gameuiRootHudGameController::OnInitialize, which fires when the
--- game creates the main gameplay HUD. We keep the controller ref
--- only for widget creation; live updates are routed through
--- UISystem events so they survive HUD/controller rebuilds.
function InkHUD.setupObserver()
    pcall(function()
        ObserveAfter("gameuiRootHudGameController", "OnInitialize", function(self)
            InkHUD.controller = self
            print("[NCM/InkHUD] Root HUD controller captured.")
            -- Create our custom widgets inside the game HUD
            pcall(function()
                self:MTECreateHUD()
                print("[NCM/InkHUD] HUD widgets created.")
            end)
        end)
        print("[NCM/InkHUD] Observer registered for gameuiRootHudGameController.")
    end)
end

-- â”€â”€ Public: called every frame from onUpdate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function InkHUD.update()
    if not resolveModules() then return end

    local racing = MTE and MTE.Racing or nil
    local aiVehicles = MTE and MTE.AIVehicles or nil
    local pauseForGridSpawn = racing and racing.getState and racing.STATE
        and racing.getState() == racing.STATE.PRERACE
        and aiVehicles and aiVehicles.isSpawning and aiVehicles.isSpawning()

    if pauseForGridSpawn then
        if not _gridSpawnHudPause then
            _gridSpawnHudPause = true
            print("[NCM/InkHUD] Pausing HUD bridge during prerace grid spawning.")
        end
        return
    elseif _gridSpawnHudPause then
        _gridSpawnHudPause = false
        print("[NCM/InkHUD] Resuming HUD bridge after prerace grid spawning.")
    end

    local ts = Telemetry.state
    local inVehicle = ts.inVehicle

    -- Self-heal: if telemetry thinks we're not in a vehicle, double-check.
    if not inVehicle then
        pcall(function()
            local p = Game.GetPlayer()
            if not p then return end
            local v = Game.GetMountedVehicle(p)
            if v then
                inVehicle    = true
                ts.inVehicle = true
                Telemetry.onVehicleEnter(v)
                Metrics.onVehicleEnter()
                Tuning.onVehicleEnter(v)
            end
        end)
    end

    -- Get UISystem (lazy)
    if not _uiSystem then
        pcall(function()
            _uiSystem = Game.GetUISystem()
        end)
    end
    if not _uiSystem then return end

    -- Build and send the event
    pcall(function()
        local evt = MTEHudUpdateEvent.new()

        -- Vehicle telemetry
        evt.speedKph  = (ts.speed or 0) * 3.6
        evt.gear      = ts.gear or 0
        evt.rpm       = ts.rpm or 0.0
        evt.inVehicle = inVehicle

        -- Inputs
        evt.throttle  = ts.throttle or 0.0
        evt.brake     = ts.brake or 0.0
        evt.clutch    = ts.clutch or 0.0
        evt.steering  = ts.steering or 0.0
        evt.handbrake = ts.handbrake or false

        -- Derived
        evt.longG         = ts.longG or 0.0
        evt.latG          = ts.latG or 0.0
        evt.accelRate     = ts.accelRate or 0.0
        evt.decelRate     = ts.decelRate or 0.0
        evt.vehicleHealth = ts.vehicleHealth or 1.0

        -- Display toggles (from Settings module)
        local cfg = MTE.Settings and MTE.Settings.current or {}
        evt.showInputs  = cfg.showInputs ~= false
        evt.showGForces = cfg.showGForces ~= false
        evt.showHealth  = cfg.showHealth ~= false
        evt.hudEnabled  = cfg.hudEnabled ~= false

        -- HUD layout overrides
        evt.telemetryScale   = (tonumber(cfg.telemetryScale) or 100) / 100.0
        evt.telemetryOpacity = (tonumber(cfg.telemetryOpacity) or 100) / 100.0
        evt.telemetryOffsetX = tonumber(cfg.telemetryOffsetX) or 0.0
        evt.telemetryOffsetY = tonumber(cfg.telemetryOffsetY) or 0.0
        evt.raceHudScale     = (tonumber(cfg.raceHudScale) or 100) / 100.0
        evt.raceHudOpacity   = (tonumber(cfg.raceHudOpacity) or 100) / 100.0
        evt.raceHudOffsetX   = tonumber(cfg.raceHudOffsetX) or 0.0
        evt.raceHudOffsetY   = tonumber(cfg.raceHudOffsetY) or 0.0

        -- Race state
        local R  = MTE.Racing
        local rs = R.getState()
        local isPrerace   = rs == R.STATE.PRERACE
        local isQuali     = rs == R.STATE.QUALI
        local isCountdown = rs == R.STATE.COUNTDOWN
        local isRacing    = rs == R.STATE.RACING

        -- Knockout state
        local K  = MTE.Knockout
        local ks = K and K.getState() or "idle"
        local isKnockoutCountdown = ks == K.STATE.COUNTDOWN
        local isKnockoutRacing    = ks == K.STATE.RACING

        evt.raceActive    = isRacing
        evt.raceCountdown = isCountdown or isKnockoutCountdown
        evt.preraceActive = isPrerace
        evt.qualiActive   = isQuali
        evt.countdownValue = 0
        evt.countdownPhase = -1
        evt.racePosition   = 1
        evt.raceFieldSize  = 1
        evt.raceTime       = 0.0
        evt.trackName      = ""
        evt.standingsText  = ""
        evt.distToFinish   = -1.0
        evt.gapText        = ""
        evt.gapBehindText  = ""
        evt.startType      = ""
        evt.phaseLabel     = ""
        evt.objectiveText  = ""
        evt.statusText     = ""
        evt.qualiRequired  = false
        evt.qualiCompleted = false
        evt.qualiGridPos   = 0
        evt.stageReadyCount = 0
        evt.stageTotalCount = 0
        evt.stageSpawning   = false
        evt.playerStartReady = false
        evt.playerStartReason = ""
        evt.finishLabel = ""
        evt.raceMode = ""
        evt.raceModeLabel = ""
        evt.sequenceActive = false
        evt.currentLap = 0
        evt.totalLaps = 0
        evt.currentTargetIndex = 0
        evt.totalTargets = 0
        evt.targetLabel = ""
        evt.progressLabel = ""
        evt.finishState = ""
        evt.classificationPendingCount = 0
        evt.dragStraightnessScore = 0
        evt.dragPenaltySeconds = 0.0
        evt.dragLaneCount = 0
        evt.dragLaneOrder = ""

        -- Knockout fields
        evt.knockoutActive        = isKnockoutRacing
        evt.eliminationCountdown  = 0.0
        evt.remainingDrivers      = 0
        evt.isInDangerZone        = false
        evt.lastEliminatedName    = ""
        evt.knockoutPhase         = ""

        local hudRaceState = R.getHUDRaceState and R.getHUDRaceState() or nil
        if hudRaceState then
            evt.raceMode = hudRaceState.raceMode or ""
            evt.raceModeLabel = hudRaceState.raceModeLabel or ""
            evt.sequenceActive = hudRaceState.sequenceActive == true
            evt.currentLap = hudRaceState.currentLap or 0
            evt.totalLaps = hudRaceState.totalLaps or 0
            evt.currentTargetIndex = hudRaceState.currentTargetIndex or 0
            evt.totalTargets = hudRaceState.totalTargets or 0
            evt.targetLabel = hudRaceState.targetLabel or ""
            evt.progressLabel = hudRaceState.progressLabel or ""
            evt.finishState = hudRaceState.finishState or ""
            evt.classificationPendingCount = hudRaceState.classificationPendingCount or 0
            evt.dragStraightnessScore = hudRaceState.dragStraightnessScore or 0
            evt.dragPenaltySeconds = hudRaceState.dragPenaltySeconds or 0.0
            evt.dragLaneCount = hudRaceState.dragLaneCount or 0
            evt.dragLaneOrder = hudRaceState.dragLaneOrder or ""
        end

        if isCountdown then
            local t = math.max(0, R.getRaceTimer())
            evt.countdownValue = math.ceil(t)
            evt.countdownPhase = R.getCountdownPhase()

            local rcfg = R.getConfig()
            evt.startType = (rcfg and rcfg.startType) or "grid"
            if rcfg and rcfg.nodeA and rcfg.nodeB and MTE.Tracks then
                evt.trackName = MTE.Tracks.getRouteName(rcfg.nodeA, rcfg.nodeB)
            end
        end

        if isPrerace then
            local rcfg = R.getConfig()
            local field = R.getField() or {}
            local deferredLiveRivals = R.isVisibleFieldDeferred and R.isVisibleFieldDeferred() or false
            local launchable = MTE.AIVehicles and MTE.AIVehicles.launchableCount and MTE.AIVehicles.launchableCount() or 0
            local stagedTotal = MTE.AIVehicles and MTE.AIVehicles.totalCount and MTE.AIVehicles.totalCount() or 0
            local total = math.max(stagedTotal, #field)
            local spawning = (R.isGridSpawnPending and R.isGridSpawnPending()) or
                (MTE.AIVehicles and MTE.AIVehicles.isSpawning and MTE.AIVehicles.isSpawning()) or false
            local startReady, startReason = R.getStartReadiness()
            local qualiDone = R.getQualiStandings() ~= nil

            if deferredLiveRivals then
                launchable = total
                stagedTotal = total
                spawning = false
            end

            evt.qualiRequired = rcfg and rcfg.qualiEnabled or false
            evt.qualiCompleted = qualiDone
            evt.qualiGridPos = R.getQualiGridPos() or 0
            evt.stageReadyCount = launchable
            evt.stageTotalCount = total
            evt.stageSpawning = spawning
            evt.playerStartReady = startReady and true or false
            evt.playerStartReason = startReason or ""

            evt.startType = (rcfg and rcfg.startType) or "grid"
            if rcfg and rcfg.nodeA and rcfg.nodeB and MTE.Tracks then
                evt.trackName = MTE.Tracks.getRouteName(rcfg.nodeA, rcfg.nodeB)
            end

            local champHeader = ""
            local hCareer = MTE.Careers and MTE.Careers.active()
            if hCareer and MTE.Championships then
                local hSeason = MTE.Championships.activeSeason(hCareer)
                if hSeason and not hSeason.completed then
                    local teamShort = (hCareer.playerFactionName or "Indep"):sub(1, 12)
                    champHeader = i18n.format("Rd %d/%d  [%s]",
                        hSeason.currentRound or 1, hSeason.totalRounds or 1, teamShort)
                end
            end
            evt.standingsText = champHeader

            -- Native runtime derives prerace messaging from the raw staging/readiness fields.
        end

        if isQuali then
            local rcfg = R.getConfig()
            local hCareer = MTE.Careers and MTE.Careers.active()
            evt.raceTime = R.getRaceTimer()
            evt.finishLabel = (rcfg and rcfg.nodeB and rcfg.nodeB.name) or "Finish"
            if rcfg and rcfg.nodeA and rcfg.nodeB and MTE.Tracks then
                evt.trackName = MTE.Tracks.getRouteName(rcfg.nodeA, rcfg.nodeB)
            end
            if hCareer and MTE.Championships then
                local hSeason = MTE.Championships.activeSeason(hCareer)
                if hSeason and not hSeason.completed then
                    local teamShort = (hCareer.playerFactionName or "Indep"):sub(1, 12)
                    evt.standingsText = i18n.format("Rd %d/%d  [%s]",
                        hSeason.currentRound or 1, hSeason.totalRounds or 1, teamShort)
                end
            end
        end

        if isKnockoutCountdown then
            local t = math.max(0, K.getRaceTimer())
            evt.countdownValue = math.ceil(t)
            evt.countdownPhase = -1  -- no grid lights for knockout
            local kcfg = K.getConfig()
            evt.trackName = (kcfg and kcfg.circuitName) or "Knockout"
            evt.startType = "grid"
        end

        if isRacing then
            evt.racePosition  = R.getEstimatedPosition() or 1
            local field       = R.getField() or {}
            evt.raceFieldSize = #field + 1
            evt.raceTime      = R.getRaceTimer()

            local rcfg = R.getConfig()
            if rcfg and rcfg.nodeA and rcfg.nodeB and MTE.Tracks then
                evt.trackName = MTE.Tracks.getRouteName(rcfg.nodeA, rcfg.nodeB)
            end

            -- Build standings text: championship context header + top-5 race positions
            local champHeader = ""
            local hCareer = MTE.Careers and MTE.Careers.active()
            if hCareer and MTE.Championships then
                local hSeason = MTE.Championships.activeSeason(hCareer)
                if hSeason and not hSeason.completed then
                    local teamShort = (hCareer.playerFactionName or "Indep"):sub(1, 12)
                    champHeader = i18n.format("Rd %d/%d  [%s]\n",
                        hSeason.currentRound or 1, hSeason.totalRounds or 1, teamShort)
                end
            end
            local standings = R.getLiveStandings()
            local lines = {}
            for i, e in ipairs(standings) do
                local tag = e.isPlayer and " <" or ""
                local driverName = e.name or "?"
                if #driverName > 14 then driverName = driverName:sub(1, 14) end
                table.insert(lines, i18n.format("P%d  %s%s", i, driverName, tag))
                if i >= 5 then break end  -- top 5 only
            end
            evt.standingsText = champHeader .. i18n.concat(lines, "\n")

            -- Distance to finish
            local dist = (hudRaceState and hudRaceState.distanceToTarget) or R.getDistanceToFinish()
            evt.distToFinish = dist or -1.0

            -- Gap to car ahead
            evt.gapText = R.getGapText()

            -- Gap to car behind
            evt.gapBehindText = R.getGapBehindText and R.getGapBehindText() or ""

            local timing = MTE.RaceTelemetry and MTE.RaceTelemetry.getActiveTimingStack and
                MTE.RaceTelemetry.getActiveTimingStack() or nil
            if timing then
                local currentSector = timing.currentSector or 1
                local routeBestSector = sectorBestFor(timing, currentSector)
                evt.phaseLabel = i18n.format("L%d/%d  S%d/%d",
                    timing.currentLap or 1,
                    timing.totalLaps or 1,
                    currentSector,
                    timing.totalSectors or 1)
                evt.statusText = i18n.format("LAP %s | BEST %s | RT %s",
                    formatTime(timing.currentLapTime),
                    formatTime(timing.sessionBestLap),
                    formatTime(timing.routeBestLap))
                evt.objectiveText = i18n.format("S%d %s | RT %s | D %s",
                    currentSector,
                    formatTime(timing.currentSectorTime),
                    formatTime(routeBestSector),
                    formatDelta(timing.currentDeltaToRouteBest))
                evt.finishLabel = buildTimingCallout(timing)
                if timing.playerValidForRecords == false or timing.validForRecords == false then
                    evt.finishLabel = "TIMING INVALID"
                end
            end

            if hudRaceState then
                if hudRaceState.phaseLabel and hudRaceState.phaseLabel ~= "" then
                    evt.phaseLabel = hudRaceState.phaseLabel
                end
                if hudRaceState.objectiveText and hudRaceState.objectiveText ~= "" then
                    evt.objectiveText = hudRaceState.objectiveText
                end
                if hudRaceState.statusText and hudRaceState.statusText ~= "" then
                    evt.statusText = hudRaceState.statusText
                end
                if hudRaceState.finishState == "classifying" then
                    evt.finishLabel = "CLASSIFYING"
                end
            end

            -- Rival callout: find the nearest rival (1-2 positions away)
            local rivalName = ""
            local rivalIsAhead = true
            local standings = R.getLiveStandings()
            local playerStandingPos = nil
            for si, se in ipairs(standings) do
                if se.isPlayer then playerStandingPos = si; break end
            end
            if playerStandingPos then
                -- Look one position ahead and behind for a rival
                for _, offset in ipairs({-1, 1, -2, 2}) do
                    local idx = playerStandingPos + offset
                    if idx >= 1 and idx <= #standings then
                        local se = standings[idx]
                        if not se.isPlayer and se.isRival then
                            rivalName    = se.name or "?"
                            rivalIsAhead = offset < 0  -- negative offset = they are ahead (lower index = better position)
                            break
                        end
                    end
                end
            end
            evt.rivalAheadName = rivalName
            evt.rivalIsAhead   = rivalIsAhead
        end

        -- Knockout racing data
        if isKnockoutRacing then
            evt.raceMode = "knockout"
            evt.raceModeLabel = "KNOCKOUT"
            evt.finishState = "racing"
            evt.knockoutActive       = true
            evt.racePosition         = K.getPlayerPosition() or 1
            evt.raceFieldSize        = K.getRemainingDrivers()
            evt.raceTime             = K.getRaceTimer()
            evt.eliminationCountdown = K.getEliminationCountdown()
            evt.remainingDrivers     = K.getRemainingDrivers()
            evt.isInDangerZone       = K.isPlayerInDangerZone()
            evt.lastEliminatedName   = K.getLastEliminatedName() or ""
            evt.knockoutPhase        = K.getRacePhase()

            local kcfg = K.getConfig()
            evt.trackName = (kcfg and kcfg.circuitName) or "Knockout"
            evt.phaseLabel = i18n.format("KNOCKOUT  %s", string.upper(evt.knockoutPhase ~= "" and evt.knockoutPhase or "RACE"))
            evt.objectiveText = i18n.format("%d drivers remain", evt.remainingDrivers)
            evt.progressLabel = i18n.format("%d remaining", evt.remainingDrivers)
            evt.statusText = evt.isInDangerZone and "Danger zone - survive the next cut" or i18n.format("Next elimination in %.0fs", evt.eliminationCountdown)

            -- Build standings text
            local standings = K.getLiveStandings()
            local lines = {}
            for i, e in ipairs(standings) do
                local tag = e.isPlayer and " <" or ""
                local driverName = e.name or "?"
                if #driverName > 14 then driverName = driverName:sub(1, 14) end
                table.insert(lines, i18n.format("P%d  %s%s", i, driverName, tag))
                if i >= 8 then break end  -- show more standings for knockout
            end
            evt.standingsText = i18n.concat(lines, "\n")
        end

        -- Localize the complete native-HUD string payload at its presentation boundary.
        local textFields = { "trackName", "standingsText", "gapText", "gapBehindText", "startType",
            "phaseLabel", "objectiveText", "statusText", "playerStartReason", "finishLabel",
            "raceModeLabel", "targetLabel", "progressLabel", "dragLaneOrder", "knockoutPhase" }
        for _, field in ipairs(textFields) do evt[field] = i18n.source(evt[field]) end

        -- Route through UISystem so native callbacks handle controller churn.
        _uiSystem:QueueEvent(evt)
    end)
end

-- â”€â”€ Public: hide the HUD on shutdown / vehicle exit â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function InkHUD.destroy()
    pcall(function()
        if not _uiSystem then _uiSystem = Game.GetUISystem() end
        if _uiSystem then
            local evt = MTEHudHideEvent.new()
            _uiSystem:QueueEvent(evt)
        end
    end)
    InkHUD.controller = nil
    _uiSystem = nil
end

return InkHUD



