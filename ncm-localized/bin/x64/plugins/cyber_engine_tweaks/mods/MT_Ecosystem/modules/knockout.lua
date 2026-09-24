-- ============================================================
-- MT_Ecosystem: modules/knockout.lua
-- Night City Knockout: circuit-based battle royale elimination
-- racing mode.
--
-- STATE MACHINE:
--   IDLE → CONFIG → LOBBY → COUNTDOWN → RACING → FINISHED
--
-- Every eliminationInterval seconds during RACING, the last-place
-- driver (by checkpoint progress) is eliminated and despawned.
-- Race ends when only 1 driver remains or the player is eliminated.
--
-- Depends on:
--   data/circuits.lua       — circuit definitions
--   modules/checkpoint.lua  — checkpoint detection helpers
--   modules/ai_vehicles.lua — spawn/drive/despawn + live tracking
--   modules/racing.lua      — NOT used during knockout (mutual exclusion)
-- ============================================================

local Knockout = {}

local Circuits   = require("modules/knockout_circuits")
local Checkpoint = require("modules/checkpoint")
local EventDefs  = require("modules/event_definitions")

-- ── States ────────────────────────────────────────────────────

Knockout.STATE = {
    IDLE      = "idle",
    CONFIG    = "config",
    LOBBY     = "lobby",
    COUNTDOWN = "countdown",
    RACING    = "racing",
    FINISHED  = "finished",
}

-- ── Constants ─────────────────────────────────────────────────

local DEFAULT_ELIMINATION_INTERVAL = 60    -- seconds between eliminations
local DEFAULT_FIELD_SIZE           = 12
local DANGER_ZONE_COUNT            = 3     -- bottom N shown in danger zone
local COUNTDOWN_SECONDS            = 3
local CHECKPOINT_RADIUS            = 50    -- metres to capture a checkpoint
local MAX_RACE_DURATION            = 1200  -- 20 min absolute cap
local PHONE_KNOCKOUT_STATE_FACT    = "ncm_foreman_knockout_state"
local PHONE_KNOCKOUT_STATE_NUM = {
    idle = 0,
    config = 1,
    lobby = 2,
    countdown = 3,
    racing = 4,
    finished = 5,
}

local function setPhoneFact(name, value)
    pcall(function()
        local qs = Game.GetQuestsSystem()
        if qs then
            if qs.SetFactStr then
                qs:SetFactStr(name, tonumber(value) or 0)
            else
                qs:SetFact(name, tonumber(value) or 0)
            end
        end
    end)
end

local function syncPhoneKnockoutState(state)
    setPhoneFact(PHONE_KNOCKOUT_STATE_FACT, PHONE_KNOCKOUT_STATE_NUM[tostring(state or "idle")] or 0)
end

-- Knockout payouts (position-based)
local PAYOUT_BY_POS = {
    10000, 6000, 3000, 1500, 800, 400, 200, 100, 50, 50,
    50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50, 50,
}

-- ── Mutable state ─────────────────────────────────────────────

Knockout._state              = "idle"
Knockout._config             = {}
Knockout._career             = nil
Knockout._circuit            = nil
Knockout._resolvedCheckpoints = {}
Knockout._field              = {}        -- roster driver objects
Knockout._drivers            = {}        -- { [driverId] = tracking state }
Knockout._playerProgress     = {}        -- player checkpoint tracking
Knockout._eliminationTimer   = 0
Knockout._raceTimer          = 0
Knockout._eliminationCount   = 0
Knockout._eliminationOrder   = {}        -- { { id, name, time, position } }
Knockout._lastLeaderId       = nil
Knockout._results            = {}
Knockout._draft              = {}
Knockout._lobbyTimer         = 0
Knockout._activeEvent        = nil
Knockout._checkpointEliminationCursor = 1
Knockout._finalSprintAnnounced = false

-- ── Init ──────────────────────────────────────────────────────

function Knockout.init()
    Knockout._state = Knockout.STATE.IDLE
    syncPhoneKnockoutState(Knockout.STATE.IDLE)
    print("[NCM/Knockout] Ready.")
end

function Knockout.onSessionStart()
    if Knockout._state ~= Knockout.STATE.IDLE and
       Knockout._state ~= Knockout.STATE.FINISHED then
        if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
        if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end
    end
    Knockout._resetState()
    print("[NCM/Knockout] Session started — state reset.")
end

function Knockout._resetState()
    Knockout._state              = Knockout.STATE.IDLE
    Knockout._config             = {}
    Knockout._career             = nil
    Knockout._circuit            = nil
    Knockout._resolvedCheckpoints = {}
    Knockout._field              = {}
    Knockout._drivers            = {}
    Knockout._playerProgress     = {}
    Knockout._eliminationTimer   = 0
    Knockout._raceTimer          = 0
    Knockout._eliminationCount   = 0
    Knockout._eliminationOrder   = {}
    Knockout._lastLeaderId       = nil
    Knockout._results            = {}
    Knockout._draft              = {}
    Knockout._lobbyTimer         = 0
    Knockout._activeEvent        = nil
    Knockout._checkpointEliminationCursor = 1
    Knockout._finalSprintAnnounced = false
    syncPhoneKnockoutState(Knockout.STATE.IDLE)
end

local function checkpointSequenceForIndex(checkpointIndex, startIndex, totalCheckpoints, isLoop)
    if not checkpointIndex or checkpointIndex < 1 then return 0 end
    if not isLoop or (startIndex or 1) <= 1 then
        return checkpointIndex
    end
    if checkpointIndex >= startIndex then
        return checkpointIndex
    end
    return totalCheckpoints + checkpointIndex
end

local function buildCheckpointModeMetadata(circuit, resolved, startIndex)
    local knockoutSpec = circuit and circuit.knockout or nil
    if not knockoutSpec or knockoutSpec.eliminationMode ~= "checkpoint" then
        return nil, nil
    end

    local byId = {}
    for index, checkpoint in ipairs(resolved or {}) do
        byId[checkpoint.id] = {
            checkpoint = checkpoint,
            index = index,
        }
    end

    local totalCheckpoints = #resolved
    local plan = {}
    for _, checkpointId in ipairs(knockoutSpec.eliminationCheckpointIds or {}) do
        local entry = byId[checkpointId]
        if not entry then
            return nil, string.format(
                "Checkpoint elimination node missing from circuit: %s",
                tostring(checkpointId))
        end
        plan[#plan + 1] = {
            checkpointId = checkpointId,
            checkpointIndex = entry.index,
            checkpointName = entry.checkpoint.name or checkpointId,
            sequence = checkpointSequenceForIndex(
                entry.index, startIndex, totalCheckpoints, circuit.isLoop),
        }
    end

    local finish = nil
    if knockoutSpec.finishCheckpointId then
        local entry = byId[knockoutSpec.finishCheckpointId]
        if not entry then
            return nil, string.format(
                "Checkpoint finish node missing from circuit: %s",
                tostring(knockoutSpec.finishCheckpointId))
        end
        finish = {
            checkpointId = knockoutSpec.finishCheckpointId,
            checkpointIndex = entry.index,
            checkpointName = entry.checkpoint.name or knockoutSpec.finishCheckpointId,
            sequence = checkpointSequenceForIndex(
                entry.index, startIndex, totalCheckpoints, circuit.isLoop),
        }
    end

    local finalSprint = nil
    if knockoutSpec.finalSprintStartCheckpointId then
        local entry = byId[knockoutSpec.finalSprintStartCheckpointId]
        if not entry then
            return nil, string.format(
                "Checkpoint final sprint node missing from circuit: %s",
                tostring(knockoutSpec.finalSprintStartCheckpointId))
        end
        finalSprint = {
            checkpointId = knockoutSpec.finalSprintStartCheckpointId,
            checkpointIndex = entry.index,
            checkpointName = entry.checkpoint.name or knockoutSpec.finalSprintStartCheckpointId,
            sequence = checkpointSequenceForIndex(
                entry.index, startIndex, totalCheckpoints, circuit.isLoop),
        }
    end

    return {
        eliminationPlan = plan,
        finishCheckpoint = finish,
        finalSprintCheckpoint = finalSprint,
    }, nil
end

function Knockout._getTrackingState(driverId)
    if driverId == "player" then
        return Knockout._playerProgress
    end
    return Knockout._drivers[driverId]
end

function Knockout._markCheckpointReached(track, reachedIndex, totalCheckpoints)
    if not track or not reachedIndex then return end
    track.lastReachedCheckpointIndex = reachedIndex
    track.lastReachedLap = track.lap or 1
    track.lastReachedSequence = ((track.lap or 1) - 1) * totalCheckpoints + reachedIndex
end

function Knockout._getNextCheckpointElimination()
    local plan = Knockout._config and Knockout._config.eliminationPlan or nil
    if type(plan) ~= "table" then return nil end
    return plan[Knockout._checkpointEliminationCursor]
end

function Knockout._announceFinalSprintIfNeeded()
    if Knockout._config.eliminationMode ~= "checkpoint" then return end
    if Knockout._finalSprintAnnounced then return end
    if Knockout.getRemainingDrivers() > 2 then return end

    Knockout._finalSprintAnnounced = true
    local fromCheckpoint = Knockout._config.finalSprintCheckpoint
    local finishCheckpoint = Knockout._config.finishCheckpoint

    print(string.format(
        "[NCM/Knockout] Final sprint active: %s -> %s.",
        fromCheckpoint and fromCheckpoint.checkpointName or "Final sprint",
        finishCheckpoint and finishCheckpoint.checkpointName or "Finish"))

    MTE.Events.emit("KnockoutFinalSprint", {
        remaining = Knockout.getRemainingDrivers(),
        fromCheckpoint = fromCheckpoint,
        toCheckpoint = finishCheckpoint,
    })
end

-- ── Config / Lobby ────────────────────────────────────────────

function Knockout.openConfig(options)
    -- Guard: can't open knockout while a sprint race is actively running
    if MTE.Racing then
        local rs = MTE.Racing.getState()
        if rs == MTE.Racing.STATE.COUNTDOWN
            or rs == MTE.Racing.STATE.RACING
            or rs == MTE.Racing.STATE.RESULTS then
            return false, "A sprint race is already in progress"
        end
        -- If Racing was left in config/prerace/quali, force it back to idle
        if rs ~= MTE.Racing.STATE.IDLE then
            if MTE.Racing.abort then MTE.Racing.abort() end
        end
    end

    local career = MTE.Careers and MTE.Careers.active()
    if not career then return false, "No active career" end

    local eventDef = options and options.eventDef or nil
    local draftDefaults = {
        circuitId = eventDef and eventDef.circuitId or nil,
        fieldSize = eventDef and eventDef.fieldSize or DEFAULT_FIELD_SIZE,
        eliminationInterval = eventDef and eventDef.eliminationInterval or DEFAULT_ELIMINATION_INTERVAL,
        trafficMode = eventDef and eventDef.trafficMode or "normal",
        combatMode = eventDef and eventDef.combatMode or ((eventDef and eventDef.allowCombat == false) and "disabled" or "allowed"),
    }
    if type(options) == "table" then
        for key, value in pairs(options) do
            if key ~= "eventDef" and key ~= "autoConfirm" then
                draftDefaults[key] = value
            end
        end
    end

    if draftDefaults.circuitId and Circuits.getMaxAIFieldSize then
        local maxAiFieldSize = Circuits.getMaxAIFieldSize(draftDefaults.circuitId)
        if type(maxAiFieldSize) == "number" then
            draftDefaults.fieldSize = maxAiFieldSize
        end
    end

    Knockout._career = career
    Knockout._activeEvent = type(eventDef) == "table" and EventDefs.clone(eventDef) or nil
    Knockout._draft = draftDefaults
    Knockout._state = Knockout.STATE.CONFIG
    syncPhoneKnockoutState(Knockout.STATE.CONFIG)
    if options and options.autoConfirm then
        return Knockout.confirmConfig()
    end
    return true
end

function Knockout.confirmConfig(draftOverrides)
    if Knockout._state ~= Knockout.STATE.CONFIG then
        return false, "Not in config state"
    end
    local career = Knockout._career
    if not career then return false, "No active career" end

    if type(draftOverrides) == "table" then
        for k, v in pairs(draftOverrides) do Knockout._draft[k] = v end
    end

    -- Validate circuit
    local circuitId = Knockout._draft.circuitId
    if not circuitId then return false, "No circuit selected" end

    local circuit = Circuits.get(circuitId)
    if not circuit then
        return false, "Circuit not found: " .. tostring(circuitId)
    end

    -- Resolve checkpoint node IDs → positions
    local resolved, err = Checkpoint.resolveCircuit(circuit, MTE.Nodes)
    if not resolved then return false, err end

    local knockoutSpec = circuit.knockout or {}
    local eliminationMode = knockoutSpec.eliminationMode or "timer"
    local startCheckpointIndex = 1
    if eliminationMode == "checkpoint" and circuit.isLoop and #resolved > 1 then
        startCheckpointIndex = 2
    end

    local checkpointMode, checkpointErr = buildCheckpointModeMetadata(
        circuit, resolved, startCheckpointIndex)
    if checkpointErr then return false, checkpointErr end

    Knockout._circuit            = circuit
    Knockout._resolvedCheckpoints = resolved

    -- Clamp field size
    local requestedFieldSize = math.max(1, tonumber(Knockout._draft.fieldSize) or DEFAULT_FIELD_SIZE)
    local maxFieldSize = tonumber(knockoutSpec.maxFieldSize)
    if eliminationMode == "checkpoint" then
        if #resolved < 3 then
            return false, "Checkpoint knockout circuits need at least 3 nodes."
        end
        maxFieldSize = math.min(maxFieldSize or math.max(2, #resolved - 1), math.max(2, #resolved - 1))
        requestedFieldSize = maxFieldSize
    end

    local fieldSize = (eliminationMode == "checkpoint" and maxFieldSize)
        or (maxFieldSize and math.max(1, math.min(maxFieldSize, requestedFieldSize)))
        or math.max(4, math.min(24, requestedFieldSize))

    Knockout._config = {
        circuitId           = circuitId,
        circuitName         = circuit.name,
        fieldSize           = fieldSize,
        requestedFieldSize  = requestedFieldSize,
        maxFieldSize        = maxFieldSize,
        eliminationInterval = Knockout._draft.eliminationInterval
                              or DEFAULT_ELIMINATION_INTERVAL,
        trafficMode         = Knockout._draft.trafficMode or "normal",
        combatMode          = Knockout._draft.combatMode or "allowed",
        totalCheckpoints    = #resolved,
        isLoop              = circuit.isLoop,
        eliminationMode     = eliminationMode,
        startCheckpointIndex = startCheckpointIndex,
        eliminationPlan     = checkpointMode and checkpointMode.eliminationPlan or nil,
        finishCheckpoint    = checkpointMode and checkpointMode.finishCheckpoint or nil,
        finalSprintCheckpoint = checkpointMode and checkpointMode.finalSprintCheckpoint or nil,
    }

    -- Build AI field from roster
    Knockout._field = {}
    if MTE.Roster then
        Knockout._field = MTE.Roster.pickForRace(
            career, fieldSize, circuit.region)
        while #Knockout._field > fieldSize do
            table.remove(Knockout._field)
        end
    end

    -- Initialise per-driver tracking
    Knockout._drivers = {}
    local initialReachedIndex = startCheckpointIndex > 1 and (startCheckpointIndex - 1) or 0
    local initialSequence = initialReachedIndex
    for i, driver in ipairs(Knockout._field) do
        Knockout._drivers[driver.id] = {
            driver          = driver,
            slotIndex       = i,
            checkpointIndex = startCheckpointIndex,
            lap             = 1,
            progress        = initialSequence * 1000,
            eliminated      = false,
            eliminatedAt    = nil,
            lastReachedCheckpointIndex = initialReachedIndex,
            lastReachedLap  = 1,
            lastReachedSequence = initialSequence,
        }
    end

    -- Player tracking
    Knockout._playerProgress = {
        checkpointIndex = startCheckpointIndex,
        lap             = 1,
        progress        = initialSequence * 1000,
        eliminated      = false,
        lastReachedCheckpointIndex = initialReachedIndex,
        lastReachedLap  = 1,
        lastReachedSequence = initialSequence,
    }

    Knockout._eliminationTimer  = 0
    Knockout._eliminationCount  = 0
    Knockout._eliminationOrder  = {}
    Knockout._raceTimer         = 0
    Knockout._lastLeaderId      = nil
    Knockout._results           = {}
    Knockout._lobbyTimer        = 0
    Knockout._checkpointEliminationCursor = 1
    Knockout._finalSprintAnnounced = false

    -- Spawn AI at the start/finish checkpoint (first in the list)
    local startNode  = resolved[1]
    local secondNode = resolved[2] or resolved[1]

    if MTE.AIVehicles then
        MTE.AIVehicles.spawnFormation(
            Knockout._field, startNode, secondNode, "grid", {
                context = "queued_grid_prerace_knockout",
                assemblyMode = "assembly",
            })

        -- Build waypoints: full circuit starting from checkpoint 2
        local waypointStartIndex = eliminationMode == "checkpoint"
            and startCheckpointIndex or 2
        local waypoints = Checkpoint.buildWaypoints(
            resolved, waypointStartIndex, circuit.isLoop)
        for i = 1, math.min(#Knockout._field,
                            MTE.AIVehicles.totalCount()) do
            MTE.AIVehicles.setWaypoints(i, waypoints)
        end
    end

    -- Place start/finish mappin + GPS to start
    if MTE.Mappins then
        MTE.Mappins.showRaceMarkers(startNode, startNode)
        MTE.Mappins.setFinishWaypoint(startNode)
    end

    Knockout._state = Knockout.STATE.LOBBY
    syncPhoneKnockoutState(Knockout.STATE.LOBBY)
    MTE.Events.emit("KnockoutLobby", {
        config  = Knockout._config,
        circuit = circuit,
        field   = Knockout._field,
    })
    if eliminationMode == "checkpoint" then
        print(string.format(
            "[NCM/Knockout] Lobby: %s — %d drivers, checkpoint eliminations to final two.",
            circuit.name, fieldSize))
    else
        print(string.format("[NCM/Knockout] Lobby: %s — %d drivers, elim every %ds.",
            circuit.name, fieldSize, Knockout._config.eliminationInterval))
    end
    return true, nil
end

function Knockout.startRace()
    if Knockout._state ~= Knockout.STATE.LOBBY then return false end

    -- Block start while AI grid is still spawning
    if MTE.AIVehicles and MTE.AIVehicles.isSpawning() then
        return false
    end

    Knockout._raceTimer = COUNTDOWN_SECONDS
    Knockout._state = Knockout.STATE.COUNTDOWN
    syncPhoneKnockoutState(Knockout.STATE.COUNTDOWN)
    MTE.Events.emit("KnockoutCountdown", { seconds = COUNTDOWN_SECONDS })
    return true
end

function Knockout.abort()
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end
    Knockout._resetState()
end

function Knockout.closeResults()
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end
    Knockout._resetState()
end

-- ── Update (called every frame from init.lua) ─────────────────

function Knockout.update(dt)
    local s = Knockout._state
    if s == Knockout.STATE.IDLE or s == Knockout.STATE.FINISHED then
        return
    end

    -- LOBBY: auto-timeout after 10 minutes
    if s == Knockout.STATE.LOBBY then
        Knockout._lobbyTimer = Knockout._lobbyTimer + dt
        if Knockout._lobbyTimer > 600 then
            print("[NCM/Knockout] Lobby timeout (10 min) — auto-aborting.")
            Knockout.abort()
        end
        return
    end

    -- COUNTDOWN
    if s == Knockout.STATE.COUNTDOWN then
        Knockout._raceTimer = Knockout._raceTimer - dt
        if Knockout._raceTimer <= 0 then
            Knockout._raceTimer = 0
            Knockout._state = Knockout.STATE.RACING
            syncPhoneKnockoutState(Knockout.STATE.RACING)
            Knockout._eliminationTimer = 0

            if MTE.AIVehicles then MTE.AIVehicles.launchAll() end
            MTE.Events.emit("KnockoutStart", { config = Knockout._config })
            Knockout._updateNextCheckpointWaypoint()
            print("[NCM/Knockout] Race started!")
        end
        return
    end

    -- RACING
    if s == Knockout.STATE.RACING then
        Knockout._raceTimer = Knockout._raceTimer + dt
        Knockout._eliminationTimer = Knockout._eliminationTimer + dt

        -- Update checkpoint progress
        Knockout._updatePlayerCheckpoints()
        Knockout._updateAICheckpoints()

        -- Lead change detection
        Knockout._checkLeadChange()

        -- Danger zone warnings (every frame, UI can poll)
        -- (PlayerInDangerZone event emitted after eliminations)

        if Knockout._config.eliminationMode == "checkpoint" then
            Knockout._processCheckpointElimination()
            if Knockout._checkCheckpointFinish() then
                return
            end
        else
            -- Time-based elimination
            local interval = Knockout._config.eliminationInterval
                             or DEFAULT_ELIMINATION_INTERVAL
            if Knockout._eliminationTimer >= interval then
                Knockout._eliminationTimer = 0
                Knockout._performElimination()
            end
        end

        -- End conditions
        Knockout._checkEndConditions()

        -- Absolute timeout
        if Knockout._raceTimer > MAX_RACE_DURATION then
            print("[NCM/Knockout] Max duration reached — finishing race.")
            local ranked = Knockout._getRankedDrivers()
            local playerWon = ranked[1] and ranked[1].isPlayer or false
            Knockout._finishRace(ranked, playerWon)
        end
    end
end

-- ── Internal: checkpoint tracking ─────────────────────────────

function Knockout._updatePlayerCheckpoints()
    if Knockout._playerProgress.eliminated then return end

    local pos = nil
    pcall(function()
        local p = Game.GetPlayer()
        if p then
            local wp = p:GetWorldPosition()
            if wp then pos = { x = wp.x, y = wp.y, z = wp.z } end
        end
    end)
    if not pos then return end

    local pp       = Knockout._playerProgress
    local cpIdx    = pp.checkpointIndex
    local resolved = Knockout._resolvedCheckpoints
    local nextCP   = resolved[cpIdx]

    if nextCP and Checkpoint.isNear(pos, nextCP, CHECKPOINT_RADIUS) then
        Knockout._markCheckpointReached(pp, cpIdx, #resolved)
        if cpIdx >= #resolved and Knockout._circuit.isLoop then
            pp.checkpointIndex = 1
            pp.lap = pp.lap + 1
        elseif cpIdx < #resolved then
            pp.checkpointIndex = cpIdx + 1
        end
        Knockout._updateNextCheckpointWaypoint()
    end

    -- Recompute progress
    local nextNode = resolved[pp.checkpointIndex]
    if nextNode then
        pp.progress = Checkpoint.computeProgress(
            pp.checkpointIndex, #resolved, pos, nextNode, pp.lap)
    end
end

function Knockout._updateNextCheckpointWaypoint()
    if not MTE.Mappins then return end
    local pp = Knockout._playerProgress
    if not pp or pp.eliminated then return end
    local resolved = Knockout._resolvedCheckpoints
    local nextCP = resolved[pp.checkpointIndex]
    if nextCP then
        MTE.Mappins.setFinishWaypoint(nextCP)
    end
end

function Knockout._updateAICheckpoints()
    if not MTE.AIVehicles or not MTE.AIVehicles.getLiveDrivers then return end

    local liveDrivers = MTE.AIVehicles.getLiveDrivers()
    local resolved    = Knockout._resolvedCheckpoints
    local totalCPs    = #resolved

    for _, ld in ipairs(liveDrivers) do
        if not ld.id then goto continue end
        local dt = Knockout._drivers[ld.id]
        if not dt or dt.eliminated then goto continue end

        local pos = ld.position
        if not pos then goto continue end

        local cpIdx = dt.checkpointIndex
        local nextCP = resolved[cpIdx]

        if nextCP and Checkpoint.isNear(pos, nextCP, CHECKPOINT_RADIUS) then
            Knockout._markCheckpointReached(dt, cpIdx, totalCPs)
            if cpIdx >= totalCPs and Knockout._circuit.isLoop then
                dt.checkpointIndex = 1
                dt.lap = dt.lap + 1
            elseif cpIdx < totalCPs then
                dt.checkpointIndex = cpIdx + 1
            end

            -- Advance AI waypoint in vehicle system
            local slotIdx = MTE.AIVehicles.findSlotByDriverId(ld.id)
            if slotIdx then
                MTE.AIVehicles.advanceWaypoint(slotIdx)
            end
        end

        -- Recompute progress
        local nextNode = resolved[dt.checkpointIndex]
        if nextNode then
            dt.progress = Checkpoint.computeProgress(
                dt.checkpointIndex, totalCPs, pos, nextNode, dt.lap)
        end

        ::continue::
    end
end

-- ── Internal: ranking ─────────────────────────────────────────

--- Build a ranked list of all active (non-eliminated) drivers.
--- Sorted descending by progress (highest = leading).
function Knockout._getRankedDrivers()
    local ranked = {}

    for id, dt in pairs(Knockout._drivers) do
        if not dt.eliminated then
            table.insert(ranked, {
                id       = id,
                name     = dt.driver and
                           (dt.driver.name or dt.driver.displayName or id) or "?",
                progress = dt.progress,
                isPlayer = false,
                driver   = dt.driver,
                lap      = dt.lap,
                cpIndex  = dt.checkpointIndex,
            })
        end
    end

    if not Knockout._playerProgress.eliminated then
        table.insert(ranked, {
            id       = "player",
            name     = "V",
            progress = Knockout._playerProgress.progress,
            isPlayer = true,
            lap      = Knockout._playerProgress.lap,
            cpIndex  = Knockout._playerProgress.checkpointIndex,
        })
    end

    table.sort(ranked, function(a, b) return a.progress > b.progress end)
    return ranked
end

-- ── Internal: elimination ─────────────────────────────────────

function Knockout._processCheckpointElimination()
    if Knockout._config.eliminationMode ~= "checkpoint" then return end

    local nextElimination = Knockout._getNextCheckpointElimination()
    if not nextElimination then
        Knockout._announceFinalSprintIfNeeded()
        return
    end

    local ranked = Knockout._getRankedDrivers()
    if #ranked <= 2 then
        Knockout._announceFinalSprintIfNeeded()
        return
    end

    local leader = ranked[1]
    local leaderState = leader and Knockout._getTrackingState(leader.id) or nil
    if not leaderState then return end

    while nextElimination and #ranked > 2 and
        (leaderState.lastReachedSequence or 0) >= nextElimination.sequence do
        Knockout._performElimination(nextElimination)
        Knockout._checkpointEliminationCursor = Knockout._checkpointEliminationCursor + 1
        nextElimination = Knockout._getNextCheckpointElimination()
        ranked = Knockout._getRankedDrivers()
        leader = ranked[1]
        leaderState = leader and Knockout._getTrackingState(leader.id) or nil
        if not leaderState then break end
    end

    Knockout._announceFinalSprintIfNeeded()
end

function Knockout._checkCheckpointFinish()
    if Knockout._config.eliminationMode ~= "checkpoint" then return false end
    if Knockout.getRemainingDrivers() > 2 then return false end

    local finishCheckpoint = Knockout._config.finishCheckpoint
    if not finishCheckpoint then return false end

    local ranked = Knockout._getRankedDrivers()
    if #ranked == 0 then return false end

    local leader = ranked[1]
    local leaderState = leader and Knockout._getTrackingState(leader.id) or nil
    if not leaderState then return false end
    if (leaderState.lastReachedSequence or 0) < finishCheckpoint.sequence then
        return false
    end

    print(string.format(
        "[NCM/Knockout] Finish triggered at %s by %s.",
        finishCheckpoint.checkpointName or "finish",
        leader.name or leader.id or "leader"))
    Knockout._finishRace(ranked, leader.isPlayer == true)
    return true
end

function Knockout._performElimination(trigger)
    local ranked = Knockout._getRankedDrivers()
    if #ranked <= 2 then return end   -- don't eliminate below 2

    local last = ranked[#ranked]
    if not last then return end

    local triggerName = trigger and trigger.checkpointName or nil

    Knockout._eliminationCount = Knockout._eliminationCount + 1

    if last.isPlayer then
        -- Player eliminated
        Knockout._playerProgress.eliminated = true
        table.insert(Knockout._eliminationOrder, {
            id       = "player",
            name     = "V",
            time     = Knockout._raceTimer,
            position = #ranked,
        })
        MTE.Events.emit("DriverEliminated", {
            id        = "player",
            name      = "V",
            isPlayer  = true,
            time      = Knockout._raceTimer,
            remaining = #ranked - 1,
            eliminationMode = Knockout._config.eliminationMode or "timer",
            checkpointId = trigger and trigger.checkpointId or nil,
            checkpointIndex = trigger and trigger.checkpointIndex or nil,
            checkpointName = triggerName,
        })
        if triggerName then
            print(string.format(
                "[NCM/Knockout] PLAYER ELIMINATED at %s! %d remaining.",
                triggerName, #ranked - 1))
        else
            print("[NCM/Knockout] PLAYER ELIMINATED!")
        end
    else
        -- AI eliminated
        local dt = Knockout._drivers[last.id]
        if dt then
            dt.eliminated   = true
            dt.eliminatedAt = Knockout._raceTimer
        end
        table.insert(Knockout._eliminationOrder, {
            id       = last.id,
            name     = last.name,
            time     = Knockout._raceTimer,
            position = #ranked,
        })

        -- Despawn the eliminated AI's vehicle
        local slotIdx = MTE.AIVehicles
                        and MTE.AIVehicles.findSlotByDriverId(last.id)
        if slotIdx then
            MTE.AIVehicles.despawnSlot(slotIdx)
        end

        MTE.Events.emit("DriverEliminated", {
            id        = last.id,
            name      = last.name,
            isPlayer  = false,
            time      = Knockout._raceTimer,
            remaining = #ranked - 1,
            eliminationMode = Knockout._config.eliminationMode or "timer",
            checkpointId = trigger and trigger.checkpointId or nil,
            checkpointIndex = trigger and trigger.checkpointIndex or nil,
            checkpointName = triggerName,
        })
        if triggerName then
            print(string.format(
                "[NCM/Knockout] Checkpoint elimination at %s: %s (P%d) — %d remaining.",
                triggerName, last.name, #ranked, #ranked - 1))
        else
            print(string.format("[NCM/Knockout] Eliminated: %s (P%d) — %d remaining.",
                last.name, #ranked, #ranked - 1))
        end
    end

    -- Danger zone warning after elimination
    Knockout._emitDangerZoneWarning()
    Knockout._announceFinalSprintIfNeeded()
end

function Knockout._emitDangerZoneWarning()
    local ranked = Knockout._getRankedDrivers()
    local dangerStart = math.max(1, #ranked - DANGER_ZONE_COUNT + 1)
    local nextCheckpoint = Knockout._getNextCheckpointElimination()
    for i = dangerStart, #ranked do
        local d = ranked[i]
        if d and d.isPlayer then
            local payload = {
                position  = i,
                total     = #ranked,
                eliminationMode = Knockout._config.eliminationMode or "timer",
            }
            if Knockout._config.eliminationMode == "checkpoint" then
                payload.nextCheckpoint = nextCheckpoint and nextCheckpoint.checkpointName or nil
            else
                payload.timeToElim = Knockout._config.eliminationInterval
                    or DEFAULT_ELIMINATION_INTERVAL
            end
            MTE.Events.emit("PlayerInDangerZone", payload)
        end
    end
end

-- ── Internal: lead changes ────────────────────────────────────

function Knockout._checkLeadChange()
    local ranked = Knockout._getRankedDrivers()
    if #ranked == 0 then return end

    local leader = ranked[1]
    if leader and leader.id ~= Knockout._lastLeaderId then
        if Knockout._lastLeaderId then
            MTE.Events.emit("LeadChange", {
                newLeader   = leader.name,
                newLeaderId = leader.id,
            })
        end
        Knockout._lastLeaderId = leader.id
    end
end

-- ── Internal: end conditions ──────────────────────────────────

function Knockout._checkEndConditions()
    local ranked = Knockout._getRankedDrivers()

    -- Player was eliminated
    if Knockout._playerProgress.eliminated then
        Knockout._finishRace(ranked, false)
        return
    end

    -- Only 1 driver left — they win
    if #ranked <= 1 then
        local playerWon = ranked[1] and ranked[1].isPlayer or false
        Knockout._finishRace(ranked, playerWon)
        return
    end
end

local function buildChampionshipResults(career, results)
    local byDriverId = {}
    for _, driver in ipairs(Knockout._field or {}) do
        byDriverId[driver.id] = driver
    end

    local championshipResults = {}
    for _, entry in ipairs(results or {}) do
        local driver = byDriverId[entry.id]
        championshipResults[#championshipResults + 1] = {
            driverId = entry.id,
            position = entry.position,
            factionId = entry.isPlayer
                and (career and career.playerFactionId or "independent")
                or (driver and driver.factionId or "independent"),
            driverName = entry.name or (driver and driver.name) or entry.id,
            isPlayer = entry.isPlayer == true,
            dnf = entry.survived ~= true,
        }
    end

    return championshipResults
end

-- ── Internal: finish race ─────────────────────────────────────

function Knockout._finishRace(ranked, playerWon)
    -- Build final results: survivors first, then eliminated in reverse
    local results = {}
    for i, r in ipairs(ranked) do
        table.insert(results, {
            position     = i,
            id           = r.id,
            name         = r.name,
            isPlayer     = r.isPlayer,
            survived     = true,
            eliminatedAt = nil,
        })
    end
    for i = #Knockout._eliminationOrder, 1, -1 do
        local e = Knockout._eliminationOrder[i]
        table.insert(results, {
            position     = #results + 1,
            id           = e.id,
            name         = e.name,
            isPlayer     = (e.id == "player"),
            survived     = false,
            eliminatedAt = e.time,
        })
    end

    Knockout._results = results

    -- Determine player's final position
    local playerPos = #results
    for i, r in ipairs(results) do
        if r.isPlayer then playerPos = i; break end
    end
    local fieldSize = #Knockout._field + 1

    -- Payout
    local payout = PAYOUT_BY_POS[playerPos] or 50
    pcall(function() Game.AddToInventory("Items.money", payout) end)

    -- Rep (career integration)
    local repGain = 0
    local career  = Knockout._career
    if career and MTE.Careers then
        repGain = MTE.Careers.awardRep(career, playerPos, fieldSize, {
            distance = (#Knockout._resolvedCheckpoints) * 500,
            clean    = false,
            dnf      = Knockout._playerProgress.eliminated,
        })
    end

    -- Race history
    if career and MTE.Careers then
        MTE.Careers.recordRace(career, {
            position  = playerPos,
            fieldSize = fieldSize,
            payout    = payout,
            dnf       = Knockout._playerProgress.eliminated,
        })
    end

    local activeEvent = Knockout._activeEvent
    if career and activeEvent and activeEvent.sourceType == "career_schedule"
        and MTE.Championships and MTE.Championships.recordResult then
        local season = MTE.Championships.activeSeason and MTE.Championships.activeSeason(career) or nil
        MTE.Championships.recordResult(career, {
            seasonId = activeEvent.seasonId or season and season.id or nil,
            round = activeEvent.round or season and season.currentRound or nil,
            tier = career.tier,
            results = buildChampionshipResults(career, results),
            eventId = activeEvent.eventId,
            executedEvent = activeEvent,
        })
    end

    -- Despawn remaining AI
    if MTE.AIVehicles then MTE.AIVehicles.despawnAll() end
    if MTE.Mappins then MTE.Mappins.clearRaceMarkers() end

    Knockout._state = Knockout.STATE.FINISHED
    syncPhoneKnockoutState(Knockout.STATE.FINISHED)
    MTE.Events.emit("KnockoutFinished", {
        eventId          = activeEvent and activeEvent.eventId or nil,
        seasonId         = activeEvent and activeEvent.seasonId or nil,
        round            = activeEvent and activeEvent.round or nil,
        playerWon        = playerWon,
        playerPosition   = playerPos,
        payout           = payout,
        repGain          = repGain,
        raceTime         = Knockout._raceTimer,
        eliminationOrder = Knockout._eliminationOrder,
        results          = results,
        activeEvent      = activeEvent and EventDefs.clone(activeEvent) or nil,
    })
    print(string.format("[NCM/Knockout] Finished! P%d | Rep %+d | %d eddies | %s",
        playerPos, repGain, payout, playerWon and "WIN" or "ELIMINATED"))
end

-- ── Accessors for UI / HUD ───────────────────────────────────

function Knockout.getState()
    return Knockout._state
end

function Knockout.getConfig()
    return Knockout._config
end

function Knockout.getField()
    return Knockout._field
end

function Knockout.getResults()
    return Knockout._results
end

function Knockout.getRaceTimer()
    return Knockout._raceTimer
end

function Knockout.getEliminationOrder()
    return Knockout._eliminationOrder
end

function Knockout.getDraft()
    return Knockout._draft
end

function Knockout.getActiveEvent()
    return Knockout._activeEvent
end

--- Returns all available circuit definitions for the config UI.
function Knockout.getCircuits()
    return Circuits.all()
end

--- Countdown value (ceiling of remaining countdown seconds).
function Knockout.getCountdownValue()
    if Knockout._state ~= Knockout.STATE.COUNTDOWN then return 0 end
    return math.max(0, math.ceil(Knockout._raceTimer))
end

--- Number of drivers still in the race (including player).
function Knockout.getRemainingDrivers()
    local count = 0
    if not Knockout._playerProgress.eliminated then count = count + 1 end
    for _, dt in pairs(Knockout._drivers) do
        if not dt.eliminated then count = count + 1 end
    end
    return count
end

--- Seconds until the next elimination.
function Knockout.getEliminationCountdown()
    if Knockout._state ~= Knockout.STATE.RACING then return 0 end
    if Knockout._config.eliminationMode == "checkpoint" then return nil end
    local interval = Knockout._config.eliminationInterval
                     or DEFAULT_ELIMINATION_INTERVAL
    return math.max(0, interval - Knockout._eliminationTimer)
end

function Knockout.getNextEliminationCheckpoint()
    return Knockout._getNextCheckpointElimination()
end

--- Whether the player is currently in the danger zone.
function Knockout.isPlayerInDangerZone()
    if Knockout._playerProgress.eliminated then return false end
    if Knockout._state ~= Knockout.STATE.RACING then return false end
    local ranked = Knockout._getRankedDrivers()
    local playerIdx = nil
    for i, r in ipairs(ranked) do
        if r.isPlayer then playerIdx = i; break end
    end
    if not playerIdx then return false end
    local dangerStart = math.max(1, #ranked - DANGER_ZONE_COUNT + 1)
    return playerIdx >= dangerStart
end

--- Live standings sorted by position (1 = leader).
--- Each: { id, name, progress, isPlayer, lap, cpIndex }
function Knockout.getLiveStandings()
    return Knockout._getRankedDrivers()
end

--- Player's current race position (1 = leading).
function Knockout.getPlayerPosition()
    if Knockout._state ~= Knockout.STATE.RACING then return nil end
    local ranked = Knockout._getRankedDrivers()
    for i, r in ipairs(ranked) do
        if r.isPlayer then return i end
    end
    return #ranked + 1
end

--- Name of the last eliminated driver (for HUD flash).
function Knockout.getLastEliminatedName()
    if #Knockout._eliminationOrder == 0 then return nil end
    return Knockout._eliminationOrder[#Knockout._eliminationOrder].name
end

--- Race phase descriptor based on remaining drivers.
function Knockout.getRacePhase()
    local total     = #Knockout._field + 1
    local remaining = Knockout.getRemainingDrivers()
    local ratio     = remaining / total

    if ratio > 0.75 then return "early"
    elseif ratio > 0.5 then return "mid"
    elseif ratio > 0.25 then return "late"
    else return "final" end
end

return Knockout
