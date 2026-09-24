-- ============================================================
-- MT_Ecosystem: modules/ai_vehicles.lua
-- Spawns visible AI race opponents in formation, issues drive
-- commands on race start, and despawns them on race end.
--
-- Flow:
--   1. PRERACE: spawnFormation() queues vehicle+NPC spawns
--   2. update() polls for entity materialization & mounts NPCs
--   3. COUNTDOWN→RACING: launchAll() issues drive commands
--   4. RESULTS/ABORT: despawnAll() cleans up all entities
--
-- AI driving commands (from CP2077 SDK):
--   - AIVehicleDriveToPointAutonomousCommand: road-following
--     pathfinding to coordinates, has maxSpeed/minSpeed,
--     clearTrafficOnPath, driveDownTheRoadIndefinitely.
--   - AIVehicleChaseCommand: aggressive pursuit of the player,
--     used for bounty/aggressive personality drivers.
--   - AIVehicleFollowCommand: traffic-aware road-following
--     pursuit of the player, for pack drivers.
--
-- Uses DynamicEntitySystem + AI mount commands + AI driving commands.
-- Gracefully degrades: if spawning fails, race still works as
-- a ghost race (existing behavior).
-- ============================================================

local AIVehicles = {}

local VehiclePool = require("data/vehicle_pool")
local GridSolver = require("modules/grid_solver")
local SettingsRegistry = require("modules/settings")

local getRaceTierSpeedFloor

-- ── Constants ─────────────────────────────────────────────────

local VERBOSE_GRID_LOGS    = false -- keep only high-signal staging logs unless deeper forensics are needed

local MAX_AI_CARS         = 12      -- full visible field cap
local SPAWN_STAGGER       = 0.15    -- minimum delay before the next slot may begin
local FIRST_SPAWN_ARM_DELAY = 0.50  -- extra delay before the first live spawn attempt after queueing
local FIRST_SPAWN_ARM_TICKS = 2     -- require a couple of clean update ticks before slot 1 may spawn
local MATERIALIZE_TIMEOUT = 5.0     -- seconds to wait for entity
local ASSEMBLY_SETBACK    = 90.0    -- spawn the field well away from the start cell, then place it onto the grid
local ASSEMBLY_LATERAL_SHIFT = 90.0 -- offset assembly volume sideways from the race line
local ASSEMBLY_ROW_SPACING = 18.0   -- wider row spacing in assembly lane to reduce native spawn pressure
local ASSEMBLY_COL_OFFSET  = 6.0    -- wider lane spacing in assembly volume
local SPAWN_Z_OFFSET      = 0.35    -- keep direct-grid spawns just above the road before physics settles them
local FINAL_SLOT_Z_OFFSET = 0.00    -- ready slots should sit on the road, not inherit the spawn lift
local GRID_PLACE_Z_LIFT   = 0.00    -- final placement targets the slot height directly instead of holding cars up
local ROW_Z_CLAMP         = 0.80    -- max absolute per-row Z adjustment from slope estimate
local SLOT_SETTLE_TIME    = 1.00    -- seconds a mounted slot must remain stable before "ready"
local SLOT_SETTLE_SPEED   = 1.50    -- m/s threshold to consider a staged car settled
local POSITION_SETTLE_TIME = 0.75   -- settle time after placement onto the actual grid

local NPC_SETTLE_BEFORE_MOUNT = 0.80  -- let NPC entity fully initialise before mount attempt
local MOUNT_VERIFY_TIMEOUT = 4.0     -- seconds to confirm NPC mount before marking ready
local TOTAL_STAGE_TIMEOUT  = 45.0    -- hard cap so staging cannot hang forever
local WORLD_SESSION_MIN_AGE = 0.75   -- require a briefly warm session before any live race spawns
local WORLD_PLAYER_STABLE_TICKS = 6  -- consecutive update ticks with the same player entity
local WORLD_VEHICLE_STABLE_TICKS = 4 -- consecutive update ticks with the same mounted vehicle
local WORLD_DISRUPTION_QUIET_TICKS = 6 -- consecutive quiet ticks after teleport/config/staging disruptions
local WORLD_DISRUPTION_QUIET_TIME  = 0.20 -- also require a small quiet-time window after disruptions
local GRID_MAX_PLAYER_DISTANCE_M   = 400.0 -- abort grid spawn if player wanders this far from start node
local POST_ARM_SETTLE_TIME      = 1.25 -- additional grace after world-arm before touching pending slots
local POST_ARM_SETTLE_TICKS     = 6    -- require several clean post-arm update ticks before slot processing
local VEHICLE_LOOKUP_GRACE   = 0.35  -- do not query just-born vehicle entities immediately
local NPC_LOOKUP_GRACE       = 0.25  -- do not query just-born NPC entities immediately
local MATERIALIZE_POLL_INTERVAL = 0.15 -- cadence for entity materialization polling
local MOUNT_VERIFY_GRACE     = 0.30  -- let mount requests breathe before verification
local MOUNT_VERIFY_INTERVAL  = 0.15  -- cadence for mount verification polls
local ASSEMBLY_SETTLE_GRACE  = 0.35  -- let assembled cars settle before sampling speed/position
local GRID_POSITION_GRACE    = 0.35  -- let placed cars settle before sampling final grid stability
local SETTLE_SAMPLE_INTERVAL = 0.15  -- cadence for settle-state sampling
local UPDATE_LOG_INTERVAL    = 0.50  -- throttle verbose grid update logging

local READY_LAUNCH_RETRY_INTERVAL = 0.50 -- retry launch dispatch quickly if the first vehicle AI command does not stick

-- ── Mid-race respawn (world-cull recovery) ────────────────────
local RESPAWN_TIME_THRESHOLD   = 15.0  -- seconds of projected remaining race time before respawn triggers
local RESPAWN_RECOVER_POLL     = 0.50  -- poll interval for entity recovery before respawning
local RESPAWN_SPAWN_BEHIND_M   = 50.0  -- spawn behind the player along the route
local RESPAWN_LATERAL_JITTER_M = 4.0   -- small side offset so respawned car isn't on top of player
local RESPAWN_LAUNCH_GRACE_S   = 3.0   -- stall-detection grace after a mid-race respawn

local SlotSafety = {}
SlotSafety.POST_DESPAWN_COOLDOWN_TIME = 0.75
SlotSafety.POST_DESPAWN_COOLDOWN_TICKS = 12

-- ── State ─────────────────────────────────────────────────────

local _slots = {}   -- array of spawn slot state machines
--[[
  Each slot:
  {
    driver       = <driver table from roster>,
    phase        = "pending" | "spawning_veh" | "spawning_npc" | "mounting" | "assembling_settle" | "positioning" | "ready" | "driving" | "done",
    driveMode    = "autonomous" | "chase" | "follow",
    vehRecord    = <TweakDB vehicle record>,
    npcRecord    = <TweakDB NPC record>,
    position     = { x, y, z },
    heading      = <degrees>,
    vehEntityID  = <EntityID>,
    npcEntityID  = <EntityID>,
    vehEntity    = <entity ref>,
    npcEntity    = <entity ref>,
    timer        = 0,
    spawnDelay   = <stagger delay>,
    driveTimer   = 0,      -- time since last drive command
    stallTimer   = 0,      -- time at low speed
  }
]]

local _active       = false
local _finishPos    = nil    -- { x, y, z } for drive destination
local _launched     = false  -- true after AI has been told to drive
local _spawnTimer   = 0      -- elapsed since spawn sequence started
local _raceTimer    = 0      -- elapsed since launch (for re-commands)
local _gridRunSeq   = 0
local _grid = {
    phase = "idle",         -- idle | preparing | arming | spawning | stabilizing | ready | failed
    nextSlotIndex = 1,
    totalSlots = 0,
    lastReason = nil,
    firstSpawnArmDelay = 0,
    firstSpawnArmTicks = 0,
    postArmSettleTime = 0,
    postArmSettleTicks = 0,
    slotsPrepared = false,
    spawnArmed = false,
    spawnOrder = nil,
    spawnCursor = 1,
    postArmWaitBucket = nil,
    postArmWaitTicks = nil,
    lastTickLogAt = nil,
    lastSummaryKey = nil,
    runId = nil,
    context = nil,
    assemblyMode = nil,
    launchOnReady = false,
    solverSummary = nil,
    criticalFailureReason = nil,
    lastSlotFailureReason = nil,
    abortRequested = false,
}
local _rollingStart = {
    active = false,
    warmupActive = false,
    control = nil,
    leaderProgress = 0.0,
    commandTimer = 0.0,
    warmupTimer = 0.0,
    lastReason = nil,
}
local _world = {
    sessionAge = 0,
    quietTime = 999,
    quietTicks = 999,
    playerStableTicks = 0,
    vehicleStableTicks = 0,
    lastDisruptionReason = "boot",
    lastSpawnGateReason = nil,
    despawnCooldownActive = false,
    despawnCooldownTime = 0,
    despawnCooldownTicks = 0,
    despawnCooldownReason = nil,
}
local _queuedFormation = nil

local function resolveTuningContext(context)
    if type(context) == "table" then
        if type(context.rootProfileSettings) == "table" or type(context.profileSettings) == "table" then
            return context
        end
        if type(context.raceContext) == "table" then
            return context.raceContext
        end
    end
    return context or _queuedFormation
end

-- Field cap: tunable (raceTuning.maxAiCars) so a 20-car formula grid is possible; MAX_AI_CARS is the fallback.
local function maxAiCars(context)
    local v = nil
    local settings = (MTE and MTE.Settings) or SettingsRegistry
    if settings and settings.getTuningValue then
        v = settings.getTuningValue("maxAiCars", resolveTuningContext(context))
    end
    v = tonumber(v)
    if not v or v < 1 then return MAX_AI_CARS end
    return math.floor(v)
end

local function tuningDefault(key, fallback)
    local settings = (MTE and MTE.Settings) or SettingsRegistry
    if settings and settings.getTuningDefault then
        local resolved = settings.getTuningDefault(key)
        if resolved ~= nil then
            return resolved
        end
    end
    return fallback
end

local function tuningValue(key, context, fallback)
    local settings = (MTE and MTE.Settings) or SettingsRegistry
    if settings and settings.getTuningValue then
        local resolved = settings.getTuningValue(key, resolveTuningContext(context))
        if resolved ~= nil then
            return resolved
        end
    end
    return tuningDefault(key, fallback)
end

local function buildGridLogLine(fmt, ...)
    local prefix = "[NCM/Grid]"
    if _grid and _grid.runId then
        prefix = prefix .. string.format("[run=%s]", tostring(_grid.runId))
    end
    local ok, line = pcall(string.format, prefix .. " " .. tostring(fmt), ...)
    if ok then
        return line
    end
    local parts = {
        prefix .. " format_error",
        " fmt=", tostring(fmt),
        " err=", tostring(line),
    }
    local argc = select("#", ...)
    for i = 1, argc do
        parts[#parts + 1] = " arg"
        parts[#parts + 1] = tostring(i)
        parts[#parts + 1] = "="
        parts[#parts + 1] = tostring(select(i, ...))
    end
    return table.concat(parts)
end

local function shouldEmitGridLog(fmt)
    if VERBOSE_GRID_LOGS then
        return true
    end

    local text = tostring(fmt or "")
    return text:find("^phase=") ~= nil
        or text:find("^grid_solver") ~= nil
        or text:find("^world_") ~= nil
        or text:find("^despawn_") ~= nil
        or text:find("^heading_offset") ~= nil
        or text:find("^spawn_arm") ~= nil
        or text:find("^post_arm_wait") ~= nil
        or text:find("^post_arm_cleared") ~= nil
        or text:find("^slot_safety") ~= nil
        or text:find("^----- grid_session") ~= nil
        or text:find("^slots_prepare_begin") ~= nil
        or text:find("pending_gate_open") ~= nil
        or text:find("pending_gate_") ~= nil
        or text:find("vehicle_spawn") ~= nil
        or text:find("npc_spawn") ~= nil
        or text:find("materialized") ~= nil
        or text:find("mounted_confirmed") ~= nil
        or text:find("assembly_settled") ~= nil
        or text:find("phase_change") ~= nil
        or text:find("phase=done") ~= nil
        or text:find("ready speed=") ~= nil
        or text:find("slots_queued") ~= nil
        or text:find("slots_prepared") ~= nil
        or text:find("slots_prepare_failed") ~= nil
        or text:find("spawn_cursor_advanced") ~= nil
        or text:find("update_summary") ~= nil
        or text:find("template_lookup") ~= nil
        or text:find("spawnVehicleEntity") ~= nil
        or text:find("slot_spawn_") ~= nil
        or text:find("slot_driver_resolve_ok") ~= nil
        or text:find("slot_vehicle_record_ok") ~= nil
        or text:find("slot_bind_driver_ok") ~= nil
        or text:find("buildSlotState") ~= nil
        or text:find("hot_join_launch") ~= nil
        or text:find("session_marker") ~= nil
        or text:find("slot_preflight") ~= nil
        or text:find("direct_fallback") ~= nil
        or text:find("formation_failed") ~= nil
        or text:find("spawning_veh_") ~= nil
        or text:find("spawning_npc_") ~= nil
        or text:find("mount_") ~= nil
end

local function gridLog(fmt, ...)
    if not shouldEmitGridLog(fmt) then
        return
    end
    local line = buildGridLogLine(fmt, ...)
    pcall(print, line)
end

local function setGridPhase(phase, reason)
    if _grid.phase ~= phase or reason ~= _grid.lastReason then
        _grid.phase = phase
        _grid.lastReason = reason
        if reason then
            gridLog("phase=%s reason=%s", tostring(phase), tostring(reason))
        else
            gridLog("phase=%s", tostring(phase))
        end
    end
end

local function shouldLogUpdateTick(now)
    local last = _grid.lastTickLogAt
    if last == nil or (now - last) >= UPDATE_LOG_INTERVAL then
        _grid.lastTickLogAt = now
        return true
    end
    return false
end

local function getActiveSpawnIndex()
    local order = _grid.spawnOrder
    local cursor = _grid.spawnCursor or 1
    if type(order) == "table" then
        local activeIndex = order[cursor]
        if activeIndex ~= nil then
            return activeIndex
        end
    end
    return _grid.nextSlotIndex or 1
end

local function logUpdateSummaryIfChanged(ready, failed, unfinished)
    local activeSpawnIndex = getActiveSpawnIndex()
    local summaryKey = table.concat({
        tostring(ready),
        tostring(failed),
        tostring(unfinished),
        tostring(activeSpawnIndex),
        tostring(_grid.spawnCursor),
        tostring(_grid.phase),
        tostring(_grid.spawnArmed),
    }, "|")
    if _grid.lastSummaryKey ~= summaryKey then
        _grid.lastSummaryKey = summaryKey
        gridLog(
            "update_summary ready=%d failed=%d unfinished=%d activeSpawnIndex=%s cursor=%s",
            tonumber(ready),
            tonumber(failed),
            tonumber(unfinished),
            tostring(activeSpawnIndex),
            tostring(_grid.spawnCursor))
    end
end

local function advanceSpawnCursor(completedIndex)
    local order = _grid.spawnOrder
    if type(order) ~= "table" then
        _grid.nextSlotIndex = math.max(_grid.nextSlotIndex or 1, completedIndex + 1)
        return
    end
    local cursor = _grid.spawnCursor or 1
    if order[cursor] == completedIndex then
        _grid.spawnCursor = cursor + 1
        _grid.nextSlotIndex = order[_grid.spawnCursor] or ((_grid.totalSlots or 0) + 1)
        gridLog(
            "slot=%d spawn_cursor_advanced cursor=%d next_slot=%s",
            completedIndex,
            tonumber(_grid.spawnCursor or 0),
            tostring(_grid.nextSlotIndex))
    end
end

local function logSlotPhaseChange(slot, newPhase, reason)
    if not slot then return end
    local slotIndex = slot.driver and (slot.driver.slotIndex or "?") or "?"
    local oldPhase = slot.phase
    if oldPhase ~= newPhase then
        gridLog(
            "slot=%s phase_change %s -> %s reason=%s",
            tostring(slotIndex),
            tostring(oldPhase),
            tostring(newPhase),
            tostring(reason or ""))
    end
    slot.phase = newPhase
end

local function resetWorldState(reason)
    _world = {
        sessionAge = 0,
        quietTime = 0,
        quietTicks = 0,
        playerStableTicks = 0,
        vehicleStableTicks = 0,
        lastDisruptionReason = reason or "reset",
        lastSpawnGateReason = nil,
        despawnCooldownActive = false,
        despawnCooldownTime = 0,
        despawnCooldownTicks = 0,
        despawnCooldownReason = nil,
    }
end

local function markWorldDisruption(reason)
    _world.quietTime = 0
    _world.quietTicks = 0
    _world.lastDisruptionReason = reason or "unknown"
    _world.lastSpawnGateReason = nil
    gridLog("world_disruption reason=%s", tostring(_world.lastDisruptionReason))
end

local function updateWorldState(dt)
    _world.sessionAge = (_world.sessionAge or 0) + (dt or 0)
    _world.quietTime = (_world.quietTime or 0) + (dt or 0)
    _world.quietTicks = (_world.quietTicks or 0) + 1
    if _world.despawnCooldownActive then
        _world.despawnCooldownTime = math.max(0, (_world.despawnCooldownTime or 0) - (dt or 0))
        if (_world.despawnCooldownTicks or 0) > 0 then
            _world.despawnCooldownTicks = math.max(0, (_world.despawnCooldownTicks or 0) - 1)
        end
        if (_world.despawnCooldownTime or 0) <= 0 and (_world.despawnCooldownTicks or 0) <= 0 then
            _world.despawnCooldownActive = false
            gridLog(
                "despawn_cooldown_cleared reason=%s sessionAge=%.3f quiet=%.3f quietTicks=%d playerTicks=%d vehicleTicks=%d",
                tostring(_world.despawnCooldownReason or "despawn_all"),
                tonumber(_world.sessionAge or 0),
                tonumber(_world.quietTime or 0),
                tonumber(_world.quietTicks or 0),
                tonumber(_world.playerStableTicks or 0),
                tonumber(_world.vehicleStableTicks or 0))
            _world.despawnCooldownReason = nil
        end
    end

    local player = nil
    local vehicle = nil
    pcall(function()
        player = Game.GetPlayer()
        if player then
            vehicle = Game.GetMountedVehicle(player)
        end
    end)

    -- Presence-based stability is more reliable here than comparing wrapped
    -- EntityID userdata, which can appear "different" every frame.
    if player then
        _world.playerStableTicks = (_world.playerStableTicks or 0) + 1
    else
        _world.playerStableTicks = 0
    end

    if vehicle then
        _world.vehicleStableTicks = (_world.vehicleStableTicks or 0) + 1
    else
        _world.vehicleStableTicks = 0
    end
end

local function normalizeTemplatePathValue(path)
    if not path then
        return nil
    end
    if type(path) == "string" then
        return path ~= "" and path or nil
    end

    local normalized = nil

    pcall(function()
        if path.ToString then
            local candidate = path:ToString()
            if type(candidate) == "string" and candidate ~= "" then
                normalized = candidate
            end
        end
    end)

    if not normalized then
        pcall(function()
            local hash = nil
            if path.GetHash then
                hash = path:GetHash()
            elseif path.hash then
                hash = path.hash
            end
            if hash and ResRef and ResRef.FromHash then
                local ref = ResRef.FromHash(hash)
                if ref then
                    if ref.ToString then
                        local candidate = ref:ToString()
                        if type(candidate) == "string" and candidate ~= "" then
                            normalized = candidate
                        end
                    elseif type(ref.resource) == "string" and ref.resource ~= "" then
                        normalized = ref.resource
                    end
                end
            end
        end)
    end

    if not normalized then
        pcall(function()
            local resource = path.resource
            if type(resource) == "string" and resource ~= "" then
                normalized = resource
            elseif resource and resource.ToString then
                local candidate = resource:ToString()
                if type(candidate) == "string" and candidate ~= "" then
                    normalized = candidate
                end
            end
        end)
    end

    if not normalized then
        local fallback = tostring(path)
        if type(fallback) == "string"
           and fallback ~= ""
           and not fallback:match("^userdata:")
           and not fallback:match("^cdata") then
            normalized = fallback
        end
    end

    return normalized
end

local function getTemplatePathFromFlat(recordID, flatName)
    local path = nil
    pcall(function()
        path = TweakDB:GetFlat(TweakDBID.new(tostring(recordID) .. "." .. tostring(flatName)))
    end)
    return normalizeTemplatePathValue(path)
end

local _vehicleTemplatePathCache = {}
local _npcTemplatePathCache = {}

local function shouldRequireStablePlayerVehicle()
    local requireVehicle = false
    pcall(function()
        local racing = MTE and MTE.Racing or nil
        local state = racing and racing.getState and racing.getState() or nil
        local states = racing and racing.STATE or nil
        requireVehicle = states and (
            state == states.PRERACE or
            state == states.QUALI or
            state == states.COUNTDOWN or
            state == states.RACING)
    end)
    return requireVehicle
end

local function getSpawnGateReason()
    if _world.despawnCooldownActive then
        return string.format(
            "post_despawn_cooldown:%s:%.2f:%d",
            tostring(_world.despawnCooldownReason or "despawn_all"),
            tonumber(_world.despawnCooldownTime or 0),
            tonumber(_world.despawnCooldownTicks or 0))
    end
    if (_world.sessionAge or 0) < WORLD_SESSION_MIN_AGE then
        return "session_warmup"
    end
    if (_world.playerStableTicks or 0) < WORLD_PLAYER_STABLE_TICKS then
        return "player_not_stable"
    end
    if shouldRequireStablePlayerVehicle() and (_world.vehicleStableTicks or 0) < WORLD_VEHICLE_STABLE_TICKS then
        return "player_vehicle_not_stable"
    end
    if (_world.quietTicks or 0) < WORLD_DISRUPTION_QUIET_TICKS or
       (_world.quietTime or 0) < WORLD_DISRUPTION_QUIET_TIME then
        return "world_not_quiet:" .. tostring(_world.lastDisruptionReason or "unknown")
    end
    -- Abort if the player has wandered too far from the grid start node.
    -- Spawning into an unstreamed sector hard-crashes the engine.
    local startNode = _queuedFormation and _queuedFormation.startNode
    if startNode then
        local playerPos = nil
        pcall(function()
            local p = Game.GetPlayer()
            if p then
                local v = Game.GetMountedVehicle(p)
                local src = v or p
                local wt = src and src.GetWorldTransform and src:GetWorldTransform()
                if wt then playerPos = wt.position end
            end
        end)
        if playerPos then
            local dx = (playerPos.x or 0) - (startNode.x or 0)
            local dy = (playerPos.y or 0) - (startNode.y or 0)
            local distSq = dx * dx + dy * dy
            if distSq > (GRID_MAX_PLAYER_DISTANCE_M * GRID_MAX_PLAYER_DISTANCE_M) then
                return string.format("player_too_far_from_grid:%.0fm", math.sqrt(distSq))
            end
        end
    end
    return nil
end

local function beginAsyncWait(slot, grace, interval)
    if not slot then return end
    slot.pollGrace = grace or 0
    slot.pollInterval = interval or MATERIALIZE_POLL_INTERVAL
    slot.nextPollAt = slot.pollGrace
    slot.lastGraceLogBucket = nil
end

local function shouldPollAsync(slot, slotIndex, label)
    local timer = slot.timer or 0
    local grace = slot.pollGrace or 0
    if timer < grace then
        local remaining = grace - timer
        local bucket = math.floor((remaining * 10.0) + 0.0001)
        if slot.lastGraceLogBucket ~= bucket then
            slot.lastGraceLogBucket = bucket
            gridLog(
                "slot=%d %s_grace_wait remaining=%.3f timer=%.3f",
                tonumber(slotIndex or 0),
                tostring(label or "async"),
                tonumber(remaining or 0),
                tonumber(timer or 0))
        end
        return false
    end
    if timer + 0.0001 < (slot.nextPollAt or 0) then
        return false
    end
    slot.lastGraceLogBucket = nil
    slot.nextPollAt = timer + (slot.pollInterval or MATERIALIZE_POLL_INTERVAL)
    return true
end

local getVehicleEntPath
local getNPCEntPath
local pickDriveMode
local calculateFormation
local calculateAssemblyFormation
local clearQueuedFormation
local countSlotPhases
local extractEntityID

local function despawnEntity(entity)
    pcall(function()
        local entityID = extractEntityID and extractEntityID(entity)
        local entitySystem = nil
        pcall(function()
            entitySystem = Game.GetDynamicEntitySystem()
        end)
        if entitySystem and entityID then
            local ok = pcall(function()
                entitySystem:DespawnEntity(entityID)
            end)
            if ok then
                return
            end

            ok = pcall(function()
                entitySystem:DeleteEntity(entityID)
            end)
            if ok then
                return
            end
        end
        if entity and exEntitySpawner and exEntitySpawner.Despawn then
            exEntitySpawner.Despawn(entity)
        end
    end)
end

local function safeTableCount(tbl)
    if type(tbl) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function safeFieldEntrySummary(entry)
    if type(entry) ~= "table" then
        return string.format("type=%s", type(entry))
    end
    return string.format(
        "id=%s driverId=%s carClass=%s vehicleRecord=%s npcRecord=%s pace=%s personality=%s gridPos=%s",
        tostring(entry.id),
        tostring(entry.driverId),
        tostring(entry.carClass),
        tostring(entry.vehicleRecord),
        tostring(VehiclePool.describeNPC(entry.npcRecord)),
        tostring(entry.pace),
        tostring(entry.personality),
        tostring(entry.gridPos))
end

local function safePositionSummary(pos)
    if type(pos) ~= "table" then
        return string.format("type=%s", type(pos))
    end
    return string.format(
        "x=%s y=%s z=%s heading=%s long=%s",
        tostring(pos.x),
        tostring(pos.y),
        tostring(pos.z),
        tostring(pos.heading),
        tostring(pos.longitudinalOffset))
end

local function nextGridRunId(explicitRunId)
    if type(explicitRunId) == "string" and explicitRunId ~= "" then
        return explicitRunId
    end
    _gridRunSeq = (_gridRunSeq or 0) + 1
    return string.format("grid_%04d", tonumber(_gridRunSeq or 0))
end

local function isFiniteNumber(value)
    return type(value) == "number"
       and value == value
       and value ~= math.huge
       and value ~= -math.huge
end

local function normalizeHeadingDeg(heading)
    if not isFiniteNumber(heading) then
        return nil
    end
    local normalized = heading % 360.0
    if normalized < 0 then
        normalized = normalized + 360.0
    end
    return normalized
end

local function headingFromVector(dx, dy)
    if not isFiniteNumber(dx) or not isFiniteNumber(dy) then
        return nil
    end
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
        return nil
    end
    return normalizeHeadingDeg(math.deg(math.atan2(dy, dx)))
end

local function headingToUnitVector(heading)
    local rad = math.rad(heading or 0)
    return math.cos(rad), math.sin(rad)
end

local _headingOffsetMismatchLogged = false

local function resolveUnifiedSlotHeadingOffsetDeg(context)
    local stageOffset = tonumber(tuningValue("startSlotHeadingOffsetDeg", context))
    local aiOffset = tonumber(tuningValue("aiSlotHeadingOffsetDeg", context))
    local resolved = stageOffset

    if resolved == nil then
        resolved = aiOffset
    end
    if resolved == nil then
        resolved = 0.0
    end

    if stageOffset ~= nil and aiOffset ~= nil and math.abs(stageOffset - aiOffset) > 0.01 and not _headingOffsetMismatchLogged then
        _headingOffsetMismatchLogged = true
        gridLog(
            "heading_offset_mismatch stage=%.2f ai=%.2f using=%.2f",
            tonumber(stageOffset or 0.0),
            tonumber(aiOffset or 0.0),
            tonumber(resolved or 0.0))
    end

    gridLog(
        "heading_offset_resolved stage=%.2f ai=%.2f resolved=%.2f startType=%s raceType=%s",
        tonumber(stageOffset or 0.0),
        tonumber(aiOffset or 0.0),
        tonumber(resolved or 0.0),
        tostring(context and context.startType or "grid"),
        tostring(context and context.raceType or "sprint"))

    return resolved
end

local function rotateSlotHeading(heading, context)
    local normalized = normalizeHeadingDeg(heading)
    if not normalized then
        return heading
    end
    return normalizeHeadingDeg(normalized + resolveUnifiedSlotHeadingOffsetDeg(context)) or normalized
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0.0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function smoothScale(value, factor, minValue, maxValue)
    local scale = tonumber(value) or 1.0
    local blend = clamp(tonumber(factor) or 1.0, 0.0, 1.0)
    local smoothed = 1.0 + ((scale - 1.0) * blend)
    if minValue ~= nil and maxValue ~= nil then
        return clamp(smoothed, minValue, maxValue)
    end
    return smoothed
end

local function personalityContains(driver, needle)
    local personality = string.lower(tostring(driver and driver.personality or ""))
    return string.find(personality, needle, 1, true) ~= nil
end

local function isBountyDriver(driver)
    if not (driver and driver.id and MTE and MTE.Careers) then
        return false
    end
    local career = MTE.Careers.active and MTE.Careers.active() or nil
    return career and MTE.Careers.hasBounty and MTE.Careers.hasBounty(career, driver.id) or false
end

local COMPETITIVE_TIER_STAT_FLOORS = {
    Gonk = {
        base_pace = 0.96,
        max_attack_pace = 1.04,
        aggression = 0.50,
        precision = 0.56,
        consistency = 0.58,
        racecraft = 0.56,
        launch_skill = 0.54,
        composure = 0.55,
        awareness = 0.54,
        throttle_control = 0.55,
        braking_control = 0.55,
        cornering_confidence = 0.55,
        lane_discipline = 0.54,
    },
}

local function getCompetitiveTierStatFloor(driver, key)
    if type(driver) ~= "table" or type(key) ~= "string" then
        return nil
    end
    local tier = driver.currentTier or driver.tier or (type(driver.driver) == "table" and (driver.driver.currentTier or driver.driver.tier)) or nil
    local tierFloors = COMPETITIVE_TIER_STAT_FLOORS[tostring(tier or "")]
    return tierFloors and tierFloors[key] or nil
end

local function getDriverStatValue(driver, key, fallback)
    if type(driver) ~= "table" then
        return fallback
    end

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
    local floor = getCompetitiveTierStatFloor(driver, key)
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

local function getDriverSignedValue(driver, key, fallback)
    local value = getDriverStatValue(driver, key, fallback or 0.0)
    return clamp(value, -1.0, 1.0)
end

local function getDriverHardwareSummary(driver)
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

local function buildRollingTheatreProfile(driver, driveProfile, raceContext)
    local aggression = clamp(getDriverStatValue(driver, "aggression", driver and driver.aggression or 0.5), 0.0, 1.0)
    local precision = clamp(getDriverStatValue(driver, "precision", driver and driver.precision or 0.5), 0.0, 1.0)
    local consistency = clamp(getDriverStatValue(driver, "consistency", driver and driver.consistency or 0.5), 0.0, 1.0)
    local launchSkill = clamp(getDriverStatValue(driver, "launch_skill", 0.5), 0.0, 1.0)
    local pathVariation = clamp(getDriverStatValue(driver, "path_variation", 0.5), 0.0, 1.0)
    local laneDiscipline = clamp(getDriverStatValue(driver, "lane_discipline", 0.5), 0.0, 1.0)
    local racecraft = clamp(getDriverStatValue(driver, "racecraft", 0.5), 0.0, 1.0)
    local instability = clamp((1.0 - consistency) * 0.45 + pathVariation * 0.35 + (personalityContains(driver, "inconsistent") and 0.20 or 0.0), 0.0, 1.0)
    local intimidation = clamp(aggression * 0.45 + launchSkill * 0.25 + (personalityContains(driver, "risk") and 0.20 or 0.0) + (personalityContains(driver, "dirty") and 0.15 or 0.0), 0.0, 1.0)
    local discipline = clamp(precision * 0.30 + consistency * 0.25 + laneDiscipline * 0.30 + racecraft * 0.15, 0.0, 1.0)

    local label = "balanced"
    if discipline >= 0.78 and intimidation <= 0.45 then
        label = "professional_killer"
    elseif intimidation >= 0.78 and instability <= 0.45 then
        label = "street_showoff"
    elseif instability >= 0.72 then
        label = "unstable_rookie"
    elseif aggression >= 0.72 and discipline >= 0.58 then
        label = "predator"
    elseif intimidation >= 0.82 and instability >= 0.60 then
        label = "psycho_edgerunner"
    end

    local revAggression = clamp(0.22 + intimidation * 0.55 + (personalityContains(driver, "aggressive") and 0.12 or 0.0), 0.15, 1.0)
    local weaveAmplitude = clamp(0.10 + instability * 0.85 + (1.0 - discipline) * 0.35, 0.0, 1.0)
    local creepPressure = clamp(0.10 + intimidation * 0.55 + (1.0 - discipline) * 0.25, 0.0, 1.0)

    return {
        label = label,
        revAggression = revAggression,
        weaveAmplitude = weaveAmplitude,
        formationDiscipline = discipline,
        intimidationLevel = intimidation,
        creepPressure = creepPressure,
        warmupInterval = clamp(tuningValue("aiRollingWarmupIntervalS", raceContext) - revAggression * 0.15, 0.28, 0.60),
        revBlips = math.max(1, math.min(tuningValue("aiRollingWarmupMaxBlips", raceContext), math.floor(1 + revAggression * 3))),
        creepMeters = clamp(creepPressure * tuningValue("aiRollingCreepMaxMeters", raceContext), 0.0, tuningValue("aiRollingCreepMaxMeters", raceContext)),
        weaveMeters = clamp(weaveAmplitude * (tuningValue("aiGridColOffsetM", raceContext) * 0.24), 0.0, tuningValue("aiGridColOffsetM", raceContext) * 0.24),
        rollingSpeedBias = clamp((intimidation - 0.5) * tuningValue("aiRollingWeaveSpeedBiasMps", raceContext), -0.8, 0.8),
    }
end

local function normalizeRaceContext(raceContext)
    local ctx = raceContext or {}
    local raceActive = ctx.raceActive == true or ctx.competitiveMode == true
    return {
        raceActive = raceActive,
        discipline = tostring(ctx.discipline or ctx.raceType or "sprint"),
        startType = tostring(ctx.startType or "grid"),
        ignoreTraffic = raceActive and ctx.ignoreTraffic ~= false,
        competitiveBoost = clamp(tonumber(ctx.competitiveBoost) or 1.0, 0.80, 1.40),
        playerFocus = clamp(tonumber(ctx.playerFocus) or 0.0, 0.0, 1.0),
    }
end

local function buildDriveProfile(driver, driveMode, raceContext)
    local ctx = normalizeRaceContext(raceContext)
    local hardware = getDriverHardwareSummary(driver)
    local aggression = clamp(getDriverStatValue(driver, "aggression", driver and driver.aggression or 0.5), 0.0, 1.0)
    local basePace = math.max(0.65, tonumber(getDriverStatValue(driver, "base_pace", driver and driver.pace or 1.0)) or 1.0)
    local attackPace = math.max(basePace, tonumber(getDriverStatValue(driver, "max_attack_pace", basePace)) or basePace)
    local racePaceBias = clamp(tonumber(getDriverStatValue(driver, "race_pace_bias", 0.0)) or 0.0, -0.25, 0.25)
    local racecraft = clamp(getDriverStatValue(driver, "racecraft", 0.5), 0.0, 1.0)
    local riskTolerance = clamp(getDriverStatValue(driver, "risk_tolerance", 0.5), 0.0, 1.0)
    local awareness = clamp(getDriverStatValue(driver, "awareness", 0.5), 0.0, 1.0)
    local throttleControl = clamp(getDriverStatValue(driver, "throttle_control", 0.5), 0.0, 1.0)
    local brakingControl = clamp(getDriverStatValue(driver, "braking_control", 0.5), 0.0, 1.0)
    local corneringConfidence = clamp(getDriverStatValue(driver, "cornering_confidence", 0.5), 0.0, 1.0)
    local composure = clamp(getDriverStatValue(driver, "composure", 0.5), 0.0, 1.0)
    local fear = clamp(getDriverStatValue(driver, "fear", 0.5), 0.0, 1.0)
    local laneDiscipline = clamp(getDriverStatValue(driver, "lane_discipline", 0.5), 0.0, 1.0)
    local pathVariation = clamp(getDriverStatValue(driver, "path_variation", 0.5), 0.0, 1.0)
    local playerBias = clamp(getDriverStatValue(driver, "player_bias", 0.0), 0.0, 1.0)
    local launchSkill = clamp(getDriverStatValue(driver, "launch_skill", 0.5), 0.0, 1.0)
    local disciplineAffinity = ctx.discipline == "drag"
        and clamp(getDriverStatValue(driver, "discipline_drag", 0.5), 0.0, 1.0)
        or (ctx.discipline == "knockout"
            and clamp(getDriverStatValue(driver, "discipline_knockout", 0.5), 0.0, 1.0)
            or clamp(getDriverStatValue(driver, "discipline_sprint", 0.5), 0.0, 1.0))
    local momentum = math.max(0.0, getDriverSignedValue(driver, "momentum", 0.0))
    local form = math.max(0.0, getDriverSignedValue(driver, "form", 0.0))
    local liveSpeedScale = smoothScale(hardware.liveSpeedScale or 1.0, 0.58, 0.95, 1.12)
    local launchScale = smoothScale(hardware.launchScale or 1.0, 0.55, 0.95, 1.14)
    local controlScale = smoothScale(hardware.controlScale or 1.0, 0.55, 0.95, 1.12)
    local reliabilityScale = smoothScale(hardware.reliabilityScale or 1.0, 0.55, 0.95, 1.12)
    local vehicleConfidence = smoothScale(hardware.confidence or 1.0, 0.50, 0.95, 1.06)
    local attackBlend = ctx.raceActive and (0.42 + racecraft * 0.12) or 0.0
    local effectivePace = (basePace + ((attackPace - basePace) * attackBlend)) * liveSpeedScale
    local urgency = 0.94
        + aggression * 0.18
        + racecraft * 0.10
        + riskTolerance * 0.08
        + throttleControl * 0.05
        + corneringConfidence * 0.05
        + disciplineAffinity * 0.04
        + momentum * 0.08
        + form * 0.06
        + ((vehicleConfidence - 1.0) * 0.24)
        + racePaceBias

    if personalityContains(driver, "aggressive") or personalityContains(driver, "closer") then
        urgency = urgency + 0.12
    end
    if personalityContains(driver, "risk") or personalityContains(driver, "dirty") then
        urgency = urgency + 0.08
    end
    if personalityContains(driver, "street smart") or personalityContains(driver, "ice cold") then
        urgency = urgency + 0.04
    end
    if personalityContains(driver, "slow starter") then
        urgency = urgency - 0.04
    end
    if driver and ((driver.rivalScore or 0) > 0 or driver.isRival) then
        urgency = urgency + 0.08
    end
    if isBountyDriver(driver) then
        urgency = urgency + 0.10
    end

    if ctx.raceActive then
        urgency = urgency
            + 0.12
            + ((ctx.competitiveBoost - 1.0) * 0.34)
            + awareness * 0.03
            + launchSkill * 0.03
            + (ctx.playerFocus * playerBias * 0.10)
            - fear * 0.03
    end

    urgency = smoothScale(urgency, 0.58, ctx.raceActive and 1.03 or 0.97, ctx.raceActive and 1.40 or 1.18)

    local baseSpeedTarget = tuningValue("aiBaseSpeedMps", raceContext)
    local maxSpeed = baseSpeedTarget * effectivePace * urgency
    if ctx.raceActive then
        maxSpeed = maxSpeed * (1.05 + racecraft * 0.06 + throttleControl * 0.04 + brakingControl * 0.03)
    end
    if ctx.raceActive and ctx.discipline == "drag" then
        maxSpeed = maxSpeed * (1.05 + throttleControl * 0.03 + disciplineAffinity * 0.03)
    end
    maxSpeed = maxSpeed * clamp(0.96 + (controlScale - 1.0) * 0.14 + (reliabilityScale - 1.0) * 0.10, 0.92, 1.08)
    local maxSpeedCap = ctx.raceActive and tuningValue("aiRaceMaxSpeedMps", raceContext) or tuningValue("aiCruiseMaxSpeedMps", raceContext)
    local liveSpeedFloor = ctx.raceActive and math.max(20.0, baseSpeedTarget * 0.72) or 8.0
    liveSpeedFloor = math.min(liveSpeedFloor, maxSpeedCap)
    maxSpeed = clamp(maxSpeed, liveSpeedFloor, maxSpeedCap)
    local tierSpeedFloor = nil
    if ctx.raceActive then
        tierSpeedFloor = math.min(getRaceTierSpeedFloor(driver, raceContext), maxSpeedCap)
        maxSpeed = math.max(maxSpeed, tierSpeedFloor)
    end

    local minSpeedFrac = tuningValue("aiMinSpeedFrac", raceContext)
        + (aggression * 0.08)
        + ((urgency - 1.0) * 0.16)
        + throttleControl * 0.04
        + racecraft * 0.04
    if ctx.raceActive then
        minSpeedFrac = minSpeedFrac + 0.02 + awareness * 0.02 - laneDiscipline * 0.02
    end
    if ctx.raceActive and ctx.discipline == "drag" then
        minSpeedFrac = minSpeedFrac + 0.12 + throttleControl * 0.03 + disciplineAffinity * 0.03
    end
    minSpeedFrac = clamp(minSpeedFrac, ctx.raceActive and 0.50 or 0.72, ctx.raceActive and 0.82 or 0.90)
    if ctx.raceActive and ctx.discipline == "drag" then
        minSpeedFrac = clamp(minSpeedFrac, 0.90, 0.98)
    end

    local targetDistance = tuningValue("aiAutonomousTargetDistanceM", raceContext)
    if ctx.raceActive then
        if ctx.discipline == "drag" then
            targetDistance = 30.0
        elseif ctx.discipline == "knockout" then
            targetDistance = 10.0
        else
            targetDistance = 8.0 + ((1.0 - pathVariation) * 4.0)
        end
    end

    local chaseDistanceMin = clamp(tuningValue("aiChaseDistanceMinM", raceContext) - aggression * 1.4 - playerBias * 1.5, 3.5, 8.0)
    local chaseDistanceMax = clamp(tuningValue("aiChaseDistanceMaxM", raceContext) - racecraft * 4.0 - ctx.playerFocus * 6.0, 16.0, 28.0)
    local followDistanceMin = clamp(tuningValue("aiFollowDistanceMinM", raceContext) - (ctx.raceActive and 2.0 or 0.0), 4.0, 10.0)
    local followDistanceMax = clamp(tuningValue("aiFollowDistanceMaxM", raceContext) - (ctx.raceActive and 6.0 or 0.0), 16.0, 34.0)
    local boostDrivingStats = ctx.raceActive
        or driveMode == "chase"
        or urgency >= 1.12
        or personalityContains(driver, "risk")
        or personalityContains(driver, "dirty")

    local forcedStartSpeed = 0.0
    if ctx.raceActive then
        forcedStartSpeed = maxSpeed * clamp((0.18 + launchSkill * 0.18 + momentum * 0.05) * launchScale, 0.16, 0.46)
    end
    if ctx.raceActive and ctx.discipline == "drag" then
        forcedStartSpeed = math.max(forcedStartSpeed, maxSpeed * (0.38 + launchSkill * 0.08))
    end

    local minSpeed = maxSpeed * minSpeedFrac
    if ctx.raceActive then
        tierSpeedFloor = tierSpeedFloor or math.min(getRaceTierSpeedFloor(driver, raceContext), maxSpeedCap)
        minSpeed = math.max(minSpeed, tierSpeedFloor * 0.86)
        forcedStartSpeed = math.max(forcedStartSpeed, tierSpeedFloor * 0.30)
        if ctx.discipline == "drag" then
            minSpeed = math.max(minSpeed, maxSpeed * 0.93)
            forcedStartSpeed = math.max(forcedStartSpeed, tierSpeedFloor * 0.42)
        end
    end

    return {
        raceActive = ctx.raceActive,
        discipline = ctx.discipline,
        hardwareRating = hardware.rating,
        hardwareSlots = hardware.slotCount,
        urgency = urgency,
        baseSpeedTarget = baseSpeedTarget,
        projectedAverageSpeed = tuningValue("aiProjectedBaseSpeedMps", raceContext),
        straightSpeedFloor = tierSpeedFloor,
        maxSpeed = maxSpeed,
        minSpeed = minSpeed,
        forcedStartSpeed = forcedStartSpeed,
        recommandInterval = clamp(tuningValue("aiRecommandIntervalS", raceContext) - (aggression * 1.1) - (racecraft * 0.8) - ((urgency - 1.0) * 2.2) - (ctx.raceActive and 0.9 or 0.0) - ((controlScale - 1.0) * 1.0) - ((ctx.raceActive and ctx.discipline == "drag") and 0.5 or 0.0), 0.6, 4.0),
        stallSpeedThreshold = tuningValue("aiStallSpeedThreshMps", raceContext) + (aggression * 1.4) + math.max(0.0, urgency - 1.0) * 3.0 + (ctx.raceActive and 2.0 or 0.0) + ((controlScale - 1.0) * 1.6),
        stallTimeThreshold = clamp(tuningValue("aiStallTimeThreshS", raceContext) - (aggression * 0.9) - (racecraft * 0.5) - ((urgency - 1.0) * 1.2) - (ctx.raceActive and 0.5 or 0.0) - ((reliabilityScale - 1.0) * 1.0), 0.9, 2.6),
        targetDistance = targetDistance,
        chaseDistanceMin = chaseDistanceMin,
        chaseDistanceMax = chaseDistanceMax,
        followDistanceMin = followDistanceMin,
        followDistanceMax = followDistanceMax,
        useTraffic = not ctx.ignoreTraffic,
        boostDrivingStats = boostDrivingStats,
    }
end

local function resolveGridForwardHeading(startNode, finishNode, explicitHeading)
    local rawRoadHeading = normalizeHeadingDeg(explicitHeading)
    if not rawRoadHeading and type(startNode) == "table" then
        rawRoadHeading = normalizeHeadingDeg(startNode.heading)
    end

    local routeHeading = nil
    if type(startNode) == "table" and type(finishNode) == "table" then
        routeHeading = headingFromVector(
            (finishNode.x or 0) - (startNode.x or 0),
            (finishNode.y or 0) - (startNode.y or 0))
    end

    local roadHeading = rawRoadHeading
    if rawRoadHeading then
        local plusNinety = normalizeHeadingDeg(rawRoadHeading + 90.0)
        local minusNinety = normalizeHeadingDeg(rawRoadHeading - 90.0)
        if routeHeading then
            local routeX, routeY = headingToUnitVector(routeHeading)
            local plusX, plusY = headingToUnitVector(plusNinety)
            local minusX, minusY = headingToUnitVector(minusNinety)
            local plusDot = (plusX * routeX) + (plusY * routeY)
            local minusDot = (minusX * routeX) + (minusY * routeY)
            roadHeading = (plusDot >= minusDot) and plusNinety or minusNinety
        else
            roadHeading = plusNinety
        end
    end

    if roadHeading and routeHeading then
        local roadX, roadY = headingToUnitVector(roadHeading)
        local routeX, routeY = headingToUnitVector(routeHeading)
        local dot = (roadX * routeX) + (roadY * routeY)
        if dot < 0 then
            return normalizeHeadingDeg(roadHeading + 180.0), "road_heading_axis_corrected_flipped_to_route"
        end
        return roadHeading, "road_heading_axis_corrected"
    end

    if roadHeading then
        return roadHeading, "road_heading_axis_corrected_only"
    end

    if routeHeading then
        return routeHeading, "route_vector"
    end

    return 0.0, "fallback_zero"
end

local function normalizePlanarVector(x, y)
    if not isFiniteNumber(x) or not isFiniteNumber(y) then
        return nil, nil
    end
    local len = math.sqrt(x * x + y * y)
    if len < 0.001 then
        return nil, nil
    end
    return x / len, y / len
end

local function resolveGridBasis(startNode, finishNode, options)
    local forwardX, forwardY = nil, nil
    local vectorSource = nil
    local stackHeadingDeg, headingSource = resolveGridForwardHeading(startNode, finishNode, options and options.gridHeading)
    local gridHeadingSupplied = options and options.gridHeading ~= nil
    if not gridHeadingSupplied and stackHeadingDeg ~= nil then
        stackHeadingDeg = normalizeHeadingDeg((stackHeadingDeg or 0.0) + tuningValue("gridHeadingOffsetDeg", options)) or stackHeadingDeg
    end
    local slotHeadingDeg = rotateSlotHeading(stackHeadingDeg, options)
    local headingRad = math.rad(stackHeadingDeg or 0)
    local headingX, headingY = normalizePlanarVector(math.cos(headingRad), math.sin(headingRad))

    local gridForward = options and options.gridForward or nil
    if type(gridForward) == "table" then
        local candidateX, candidateY = normalizePlanarVector(gridForward.x, gridForward.y)
        if candidateX and candidateY then
            local dot = headingX and headingY and ((candidateX * headingX) + (candidateY * headingY)) or nil
            if dot and dot < 0 then
                stackHeadingDeg = normalizeHeadingDeg((stackHeadingDeg or 0.0) + 180.0) or stackHeadingDeg
                slotHeadingDeg = rotateSlotHeading(stackHeadingDeg, options)
                headingRad = math.rad(stackHeadingDeg or 0)
                headingX, headingY = normalizePlanarVector(math.cos(headingRad), math.sin(headingRad))
                vectorSource = "node_heading_flipped_to_grid_forward"
            elseif dot and dot >= tuningValue("aiGridForwardAlignmentDot", options) then
                vectorSource = "node_heading_aligned_to_grid_forward"
            end
        end
    end

    if not forwardX or not forwardY then
        local fallbackRad = math.rad(stackHeadingDeg or 0)
        forwardX, forwardY = normalizePlanarVector(math.cos(fallbackRad), math.sin(fallbackRad))
        if not vectorSource then
            vectorSource = headingSource
        end
    end

    local rightX, rightY = -forwardY, forwardX
    return {
        forwardX = forwardX or 1.0,
        forwardY = forwardY or 0.0,
        rightX = rightX or 0.0,
        rightY = rightY or 1.0,
        heading = stackHeadingDeg or 0.0,
        slotHeading = slotHeadingDeg or stackHeadingDeg or 0.0,
        headingSource = headingSource,
        vectorSource = vectorSource,
    }
end

local RACE_TIER_STRAIGHT_SPEED_MIN_MULT = {
    Gonk = 0.80,
    Streetkid = 0.95,
    Solo = 1.12,
    Fixer = 1.30,
    Edgerunner = 1.48,
}

getRaceTierSpeedFloor = function(driver, raceContext)
    local baseSpeedTarget = tuningValue("aiBaseSpeedMps", raceContext)
    if type(driver) ~= "table" then
        return baseSpeedTarget * RACE_TIER_STRAIGHT_SPEED_MIN_MULT.Gonk
    end
    local tier = driver.currentTier or driver.tier or (type(driver.driver) == "table" and (driver.driver.currentTier or driver.driver.tier)) or "Gonk"
    local mult = RACE_TIER_STRAIGHT_SPEED_MIN_MULT[tostring(tier)] or RACE_TIER_STRAIGHT_SPEED_MIN_MULT.Gonk
    return baseSpeedTarget * mult
end

local function getWholeGridSlotOrdinal(entry, fallbackIndex, playerGridPos)
    local slotOrdinal = tonumber(entry and entry.gridPos or fallbackIndex) or fallbackIndex or 1
    if playerGridPos and slotOrdinal >= playerGridPos then
        slotOrdinal = slotOrdinal + 1
    end
    return math.max(1, math.floor(slotOrdinal))
end

local function getSideBySideLaneIndex(entry, fallbackIndex, playerGridPos, options)
    local dragStrip = options and options.dragStrip or nil
    local laneIndexByGridPos = dragStrip and dragStrip.laneIndexByGridPos or nil
    if type(laneIndexByGridPos) == "table" then
        local gridPos = tonumber(entry and entry.gridPos or fallbackIndex) or fallbackIndex or 1
        local laneIndex = tonumber(laneIndexByGridPos[math.max(1, math.floor(gridPos))] or nil)
        local playerLaneIndex = playerGridPos and tonumber(laneIndexByGridPos[math.max(1, math.floor(playerGridPos))] or nil) or nil
        if laneIndex and playerLaneIndex then
            return laneIndex, playerLaneIndex
        end
    end
    return getWholeGridSlotOrdinal(entry, fallbackIndex, playerGridPos), playerGridPos
end

local function getGridRowCol(slotOrdinal)
    local ordinal = math.max(1, math.floor(slotOrdinal or 1))
    local row = math.ceil(ordinal / 2) - 1
    local col = (ordinal % 2 == 0) and 1 or -1
    return row, col
end

local function getSlotIndex(slot, fallback)
    if not slot then return fallback or "?" end
    local driver = slot.driver
    return driver and (driver.slotIndex or driver.driverId or driver.id) or fallback or "?"
end

local function resolveSlotVehiclePath(slot)
    if type(slot) ~= "table" then
        return nil
    end
    local path = normalizeTemplatePathValue(slot.vehEntPath)
    if not path then
        path = normalizeTemplatePathValue(getVehicleEntPath(slot.vehRecord))
    end
    slot.vehEntPath = path
    return path
end

local function resolveSlotNPCPath(slot)
    if type(slot) ~= "table" then
        return nil
    end
    local path = normalizeTemplatePathValue(slot.npcEntPath)
    if not path then
        path = normalizeTemplatePathValue(getNPCEntPath(slot.npcRecord))
    end
    slot.npcEntPath = path
    return path
end

local function validatePositionTable(pos, label)
    if type(pos) ~= "table" then
        return false, tostring(label) .. "_missing"
    end
    if not isFiniteNumber(pos.x) then
        return false, tostring(label) .. "_x_invalid"
    end
    if not isFiniteNumber(pos.y) then
        return false, tostring(label) .. "_y_invalid"
    end
    if not isFiniteNumber(pos.z) then
        return false, tostring(label) .. "_z_invalid"
    end
    if pos.heading ~= nil and not isFiniteNumber(pos.heading) then
        return false, tostring(label) .. "_heading_invalid"
    end
    return true
end

local function applyDirectSpawnFallback(slot, reason)
    if type(slot) ~= "table" then
        return false
    end
    if slot.spawnMode ~= "assembly" or slot.usedDirectFallback then
        return false
    end
    local ok = validatePositionTable(slot.position, "direct_fallback_position")
    if not ok then
        return false
    end
    slot.spawnPosition = slot.position
    slot.spawnMode = "direct"
    slot.usedDirectFallback = true
    slot.directFallbackReason = reason
    gridLog(
        "direct_fallback slot=%s reason=%s spawn=%s final=%s",
        tostring(getSlotIndex(slot)),
        tostring(reason),
        safePositionSummary(slot.spawnPosition),
        safePositionSummary(slot.position))
    return true
end

local function validateSlotPreflight(slot, phaseLabel)
    local slotIndex = getSlotIndex(slot)
    if type(slot) ~= "table" then
        gridLog("slot_preflight_fail slot=%s phase=%s reason=slot_not_table",
            tostring(slotIndex),
            tostring(phaseLabel or "?"))
        return false, "slot_not_table"
    end

    local ok, reason = validatePositionTable(slot.position, "final_position")
    if not ok then
        gridLog("slot_preflight_fail slot=%s phase=%s reason=%s spawn=%s final=%s",
            tostring(slotIndex),
            tostring(phaseLabel or "?"),
            tostring(reason),
            safePositionSummary(slot.spawnPosition),
            safePositionSummary(slot.position))
        return false, reason
    end

    if slot.requestedSpawnMode == "assembly" and not slot.usedDirectFallback then
        ok, reason = validatePositionTable(slot.assemblyPosition, "assembly_position")
        if not ok and not applyDirectSpawnFallback(slot, reason) then
            gridLog("slot_preflight_fail slot=%s phase=%s reason=%s spawn=%s final=%s",
                tostring(slotIndex),
                tostring(phaseLabel or "?"),
                tostring(reason),
                safePositionSummary(slot.spawnPosition),
                safePositionSummary(slot.position))
            return false, reason
        end
    end

    local spawnPosition = slot.spawnPosition or slot.position
    ok, reason = validatePositionTable(spawnPosition, "spawn_position")
    if not ok and not applyDirectSpawnFallback(slot, reason) then
        gridLog("slot_preflight_fail slot=%s phase=%s reason=%s spawn=%s final=%s",
            tostring(slotIndex),
            tostring(phaseLabel or "?"),
            tostring(reason),
            safePositionSummary(spawnPosition),
            safePositionSummary(slot.position))
        return false, reason
    end

    spawnPosition = slot.spawnPosition or slot.position
    ok, reason = validatePositionTable(spawnPosition, "spawn_position")
    if not ok then
        gridLog("slot_preflight_fail slot=%s phase=%s reason=%s spawn=%s final=%s",
            tostring(slotIndex),
            tostring(phaseLabel or "?"),
            tostring(reason),
            safePositionSummary(spawnPosition),
            safePositionSummary(slot.position))
        return false, reason
    end

    if not isFiniteNumber(slot.heading) then
        local fallbackHeading = (spawnPosition and spawnPosition.heading) or (slot.position and slot.position.heading)
        if isFiniteNumber(fallbackHeading) then
            slot.heading = fallbackHeading
        else
            gridLog("slot_preflight_fail slot=%s phase=%s reason=heading_invalid spawn=%s final=%s",
                tostring(slotIndex),
                tostring(phaseLabel or "?"),
                safePositionSummary(spawnPosition),
                safePositionSummary(slot.position))
            return false, "heading_invalid"
        end
    end

    local vehPath = resolveSlotVehiclePath(slot)
    if not vehPath then
        local vehicleRecordKey = slot.vehRecord
        local vehicleRecordValid = false
        if type(vehicleRecordKey) == "table" then
            vehicleRecordKey = vehicleRecordKey.id or vehicleRecordKey.record or vehicleRecordKey.vehicleRecord
        end
        pcall(function()
            if type(vehicleRecordKey) == "string" and vehicleRecordKey ~= "" then
                vehicleRecordValid = TweakDB:GetRecord(TweakDBID.new(vehicleRecordKey)) ~= nil
            end
        end)
        if vehicleRecordValid then
            gridLog(
                "slot_preflight_vehicle_record_ok slot=%s phase=%s vehicle=%s spawn=%s final=%s",
                tostring(slotIndex),
                tostring(phaseLabel or "?"),
                tostring(vehicleRecordKey),
                safePositionSummary(spawnPosition),
                safePositionSummary(slot.position))
        else
            gridLog("slot_preflight_fail slot=%s phase=%s reason=vehicle_template_missing spawn=%s final=%s",
                tostring(slotIndex),
                tostring(phaseLabel or "?"),
                safePositionSummary(spawnPosition),
                safePositionSummary(slot.position))
            return false, "vehicle_template_missing"
        end
    end

    local npcPath = resolveSlotNPCPath(slot)
    if not npcPath then
        gridLog("slot_preflight_fail slot=%s phase=%s reason=npc_template_missing spawn=%s final=%s",
            tostring(slotIndex),
            tostring(phaseLabel or "?"),
            safePositionSummary(spawnPosition),
            safePositionSummary(slot.position))
        return false, "npc_template_missing"
    end

    gridLog(
        "slot_preflight_ok slot=%s phase=%s spawnMode=%s vehPath=%s npcPath=%s spawn=%s final=%s",
        tostring(slotIndex),
        tostring(phaseLabel or "?"),
        tostring(slot.usedDirectFallback and "direct_fallback" or slot.spawnMode or slot.requestedSpawnMode or "unknown"),
        tostring(vehPath),
        tostring(npcPath),
        safePositionSummary(spawnPosition),
        safePositionSummary(slot.position))
    return true
end

local function buildSlotState(i, entry, position, assemblyPosition, options, solveInfo)
    gridLog("slot=%d buildSlotState: begin", i)
    local vehRecord = entry.vehicleRecord or VehiclePool.pickVehicle(entry.carClass or "Muscle")
    gridLog("slot=%d buildSlotState: vehRecord=%s", i, tostring(vehRecord))
    local npcRecord = VehiclePool.normalizeNPCRecord(entry.npcRecord, entry.factionId, entry.driverId or entry.id)
                      or VehiclePool.pickNPCForDriver(entry.driverId or entry.id, entry.factionId)
    gridLog("slot=%d buildSlotState: npcRecord=%s", i, tostring(VehiclePool.describeNPC(npcRecord)))
    local vehEntPath = VehiclePool.getVehicleEntityTemplate(vehRecord)
    local npcEntPath = getNPCEntPath(npcRecord)
    gridLog("slot=%d buildSlotState: vehicle_template=%s npc_template=%s",
        i,
        vehEntPath and "static" or "deferred",
        npcEntPath and "resolved" or "deferred")
    local raceContext = options and options.raceContext or nil
    local driveMode = pickDriveMode(entry, raceContext)
    local driveProfile = buildDriveProfile(entry, driveMode, raceContext)
    local playerGridPos = tonumber(options and options.playerGridPos or nil)
    local gridOrdinal = getWholeGridSlotOrdinal(entry, i, playerGridPos)
    local gridRow, gridCol = getGridRowCol(gridOrdinal)
    local theatreProfile = buildRollingTheatreProfile(entry, driveProfile, raceContext)
    local useDirectSpawn = options and options.assemblyMode == "direct"
    local requestedSpawnMode = useDirectSpawn and "direct" or "assembly"
    local spawnMode = useDirectSpawn and "direct" or (assemblyPosition and "assembly" or "direct")
    local assemblyPlacement = useDirectSpawn and "direct" or tostring(options and options.assemblyPlacement or "node_grid")
    gridLog("slot=%d buildSlotState: driveMode=%s", i, tostring(driveMode))
    gridLog(
        "slot_vehicle_record_ok slot=%d vehicle=%s class=%s assembly=%s launchOnReady=%s",
        tonumber(i or 0),
        tostring(vehRecord),
        tostring(entry and entry.carClass or "unknown"),
        tostring(useDirectSpawn and "direct" or "assembly"),
        tostring(options and options.launchOnReady == true))
    gridLog(
        "slot_driver_resolve_ok slot=%d driver=%s npc=%s faction=%s",
        tonumber(i or 0),
        tostring(entry and (entry.driverId or entry.id) or "?"),
        tostring(VehiclePool.describeNPC(npcRecord)),
        tostring(entry and entry.factionId or "nil"))
    return {
        driver      = entry,
        phase       = "pending",
        driveMode   = driveMode,
        driveProfile = driveProfile,
        theatreProfile = theatreProfile,
        raceContext = raceContext,
        vehRecord   = vehRecord,
        appearance  = entry.vehicleAppearance,   -- optional per-rival appearance name (spec field / liveries)
        npcRecord   = npcRecord,
        vehEntPath  = vehEntPath,
        npcEntPath  = npcEntPath,
        position    = position,
        assemblyPosition = assemblyPosition,
        assemblyPlacement = assemblyPlacement,
        spawnPosition = useDirectSpawn and clonePositionWithZLift(position, SPAWN_Z_OFFSET) or (assemblyPosition or position),
        requestedSpawnMode = requestedSpawnMode,
        spawnMode   = spawnMode,
        usedDirectFallback = false,
        directFallbackReason = nil,
        driverlessLaunch = false,
        driverlessReadyReason = nil,
        heading     = position and position.heading or 0,
        vehEntityID = nil,
        npcEntityID = nil,
        vehEntity   = nil,
        npcEntity   = nil,
        timer       = 0,
        spawnDelay  = (i - 1) * SPAWN_STAGGER,
        spawnRank   = nil,
        driveTimer  = 0,
        stallTimer  = 0,
        settleTimer = 0,
        mountSeatName = nil,
        mountBackend = nil,
        mountVerifyReason = nil,
        firstSpawnWaitBucket = nil,
        firstSpawnWaitTicks = nil,
        solveInfo = solveInfo,
        failureReason = nil,
        spawnRiskScore = 0,
        spawnRiskLabel = "unclassified",
        isThinFaction = false,
        deferLiveSpawn = false,
        launchOnReady = options and options.launchOnReady == true,
        gridOrdinal = gridOrdinal,
        gridRow = gridRow,
        gridCol = gridCol,
    }
end

local function entryDriverKey(entry)
    if type(entry) ~= "table" then
        return "?"
    end
    return tostring(entry.driverId or entry.id or "?")
end

local function getSlotDriverKey(slot)
    return entryDriverKey(slot and slot.driver or nil)
end

local function getSlotLongitudinalOffset(slot)
    local pos = slot and (slot.position or slot.spawnPosition or slot.assemblyPosition) or nil
    local offset = pos and pos.longitudinalOffset or nil
    return tonumber(offset or 0) or 0
end

local function isThinFactionEntry(entry)
    if type(entry) ~= "table" then
        return false
    end
    local driverKey = entryDriverKey(entry)
    local factionLike = entry.isFaction == true or string.find(driverKey, "^faction_") ~= nil
    if not factionLike then
        return false
    end
    local factionId = tostring(entry.factionId or "")
    local carClass = tostring(entry.carClass or "")
    local hasFactionMeta = factionId ~= ""
    local hasKnownClass = carClass ~= "" and carClass ~= "unknown"
    return (not hasFactionMeta) or (not hasKnownClass)
end

local function classifySlotSpawnRisk(slot)
    if type(slot) ~= "table" then
        return 0, "invalid"
    end

    local entry = slot.driver or {}
    local carClass = tostring(entry.carClass or "")
    local factionId = tostring(entry.factionId or "")
    local isFaction = entry.isFaction == true
    local thinFaction = isThinFactionEntry(entry)
    local risk = 0
    local label = "stable"

    if thinFaction then
        risk = risk + 1000
        label = "thin_faction"
    elseif isFaction then
        risk = risk + 100
        label = "faction"
    elseif carClass == "" or carClass == "unknown" then
        risk = risk + 30
        label = "unknown_class"
    end

    if factionId == "" then
        risk = risk + 10
    end

    slot.isThinFaction = thinFaction
    slot.spawnRiskScore = risk
    slot.spawnRiskLabel = label
    return risk, label
end

local function shouldDeferPreraceSlot(slot)
    if type(slot) ~= "table" then
        return false, nil
    end
    local context = tostring(_grid and _grid.context or "")
    if not string.find(context, "^queued_grid_prerace") then
        return false, nil
    end
    if slot.isThinFaction then
        return true, "prerace_deferred_thin_faction"
    end
    return false, nil
end

local function shouldRejectSlotForCrashGuard(slot)
    if type(slot) ~= "table" then
        return true, "crash_guard_invalid_slot"
    end

    local driver = slot.driver or {}
    local npcProfile = VehiclePool and VehiclePool.getNPCProfile and VehiclePool.getNPCProfile(slot.npcRecord) or nil
    local npcSpawnKey = VehiclePool and VehiclePool.getNPCSpawnKey and VehiclePool.getNPCSpawnKey(slot.npcRecord, slot.driver) or nil
    local npcNeedsMigration = VehiclePool and VehiclePool.npcNeedsMigration and VehiclePool.npcNeedsMigration(slot.npcRecord) or false
    local vehicleTemplate = slot.vehEntPath or (VehiclePool and VehiclePool.getVehicleEntityTemplate and VehiclePool.getVehicleEntityTemplate(slot.vehRecord)) or nil
    local npcTemplate = slot.npcEntPath or (VehiclePool and VehiclePool.getNPCEntityTemplate and VehiclePool.getNPCEntityTemplate(slot.npcRecord)) or nil
    local vehicleRecordKey = slot.vehRecord
    local vehicleRecordValid = false

    if type(vehicleRecordKey) == "table" then
        vehicleRecordKey = vehicleRecordKey.id or vehicleRecordKey.record or vehicleRecordKey.vehicleRecord
    end
    pcall(function()
        if type(vehicleRecordKey) == "string" and vehicleRecordKey ~= "" then
            vehicleRecordValid = TweakDB:GetRecord(TweakDBID.new(vehicleRecordKey)) ~= nil
        end
    end)

    if slot.isThinFaction then
        return true, "crash_guard_thin_faction"
    end
    if type(npcProfile) ~= "table" then
        return true, "crash_guard_npc_profile_missing"
    end
    if npcNeedsMigration then
        return true, "crash_guard_npc_needs_migration"
    end
    if type(npcSpawnKey) ~= "string" or npcSpawnKey == "" then
        return true, "crash_guard_npc_spawn_key_missing"
    end
    if string.find(npcSpawnKey, "Character.intrasys_", 1, true) == 1 then
        return true, "crash_guard_legacy_npc_spawn_key"
    end
    if type(npcProfile.record) ~= "string" or npcProfile.record == "" then
        return true, "crash_guard_npc_record_missing"
    end
    if type(npcTemplate) ~= "string" or npcTemplate == "" then
        return true, "crash_guard_npc_template_missing"
    end
    if type(vehicleTemplate) ~= "string" or vehicleTemplate == "" then
        if vehicleRecordValid then
            gridLog(
                "slot_crash_guard_vehicle_record_ok slot=%s driver=%s vehicle=%s",
                tostring(getSlotIndex(slot)),
                tostring(getSlotDriverKey(slot)),
                tostring(vehicleRecordKey))
        else
            return true, "crash_guard_vehicle_template_missing"
        end
    end

    local factionId = tostring(driver.factionId or "")
    local carClass = tostring(driver.carClass or "")
    if factionId == "" and carClass == "" then
        return true, "crash_guard_driver_identity_thin"
    end

    return false, nil
end

local function noteSlotFailure(slot, reason, phase)
    if type(slot) ~= "table" then
        return
    end
    slot.failureReason = reason or slot.failureReason or "failed"
    _grid.lastSlotFailureReason = slot.failureReason
    gridLog(
        "slot_spawn_note slot=%s driver=%s reason=%s phase=%s risk=%s",
        tostring(getSlotIndex(slot)),
        tostring(getSlotDriverKey(slot)),
        tostring(slot.failureReason),
        tostring(phase or slot.phase or "?"),
        tostring(slot.spawnRiskLabel or "unknown"))
end

local function buildFinishRunoffTarget(startNode, finishNode, raceType)
    if type(finishNode) ~= "table" then
        return nil
    end

    local dx, dy
    if type(finishNode.finishHeading) == "number" then
        local finishRad = math.rad(finishNode.finishHeading)
        dx = math.cos(finishRad)
        dy = math.sin(finishRad)
    else
        local sx = (startNode and startNode.x) or (finishNode.x or 0)
        local sy = (startNode and startNode.y) or (finishNode.y or 0)
        dx = (finishNode.x or 0) - sx
        dy = (finishNode.y or 0) - sy
        local planarLen = math.sqrt(dx * dx + dy * dy)
        if planarLen < 1.0 and type(finishNode.heading) == "number" then
            local finishRad = math.rad(finishNode.heading)
            dx = math.cos(finishRad)
            dy = math.sin(finishRad)
        end
    end

    local len = math.sqrt((dx or 0) * (dx or 0) + (dy or 0) * (dy or 0))
    if len < 0.001 then
        dx = 1.0
        dy = 0.0
        len = 1.0
    end

    local runoffDistance = (raceType == "drag")
        and tuningValue("aiDragFinishRunoffDistanceM", _queuedFormation)
        or tuningValue("aiFinishRunoffDistanceM", _queuedFormation)
    local nx = dx / len
    local ny = dy / len
    return {
        x = (finishNode.x or 0) + nx * runoffDistance,
        y = (finishNode.y or 0) + ny * runoffDistance,
        z = finishNode.z or 0,
    }
end

local function rebuildSpawnPlan()
    local ordered = {}
    local deferred = {}

    for i, slot in ipairs(_slots) do
        if slot.phase ~= "done" then
            ordered[#ordered + 1] = i
        elseif slot.deferLiveSpawn then
            deferred[#deferred + 1] = i
        end
    end

    table.sort(ordered, function(a, b)
        local slotA = _slots[a]
        local slotB = _slots[b]
        local riskA = tonumber(slotA and slotA.spawnRiskScore or 0) or 0
        local riskB = tonumber(slotB and slotB.spawnRiskScore or 0) or 0
        if riskA ~= riskB then
            return riskA < riskB
        end

        local longA = getSlotLongitudinalOffset(slotA)
        local longB = getSlotLongitudinalOffset(slotB)
        local aheadA = longA > 0 and 1 or 0
        local aheadB = longB > 0 and 1 or 0
        if aheadA ~= aheadB then
            return aheadA < aheadB
        end

        if longA ~= longB then
            if aheadA == 0 then
                return longA > longB
            end
            return longA < longB
        end

        return a < b
    end)

    _grid.spawnOrder = ordered
    _grid.spawnCursor = 1
    _grid.nextSlotIndex = ordered[1] or ((_grid.totalSlots or 0) + 1)

    local orderParts = {}
    for rank, slotIndex in ipairs(ordered) do
        local slot = _slots[slotIndex]
        if slot then
            slot.spawnRank = rank
            slot.spawnDelay = (rank - 1) * SPAWN_STAGGER
            orderParts[#orderParts + 1] = string.format(
                "%d:%s:%s:%.1f",
                tonumber(slotIndex or 0),
                tostring(getSlotDriverKey(slot)),
                tostring(slot.spawnRiskLabel or "stable"),
                tonumber(getSlotLongitudinalOffset(slot) or 0))
        end
    end

    local deferredParts = {}
    for _, slotIndex in ipairs(deferred) do
        local slot = _slots[slotIndex]
        deferredParts[#deferredParts + 1] = string.format(
            "%d:%s:%s",
            tonumber(slotIndex or 0),
            tostring(getSlotDriverKey(slot)),
            tostring(slot and slot.failureReason or "deferred"))
    end

    gridLog(
        "slot_spawn_plan total=%d active=%d deferred=%d first=%s order=%s",
        tonumber(#_slots or 0),
        tonumber(#ordered or 0),
        tonumber(#deferred or 0),
        tostring(_grid.nextSlotIndex),
        tostring(table.concat(orderParts, " | ")))
    if #deferredParts > 0 then
        gridLog(
            "slot_spawn_plan_deferred count=%d slots=%s",
            tonumber(#deferredParts),
            tostring(table.concat(deferredParts, " | ")))
    end
end

local function failSlot(slot, reason)
    if type(slot) ~= "table" then
        return
    end
    if slot.phase == "done" then
        return
    end

    local slotIndex = slot.driver and (slot.driver.slotIndex or slot.driver.driverId or slot.driver.id) or "?"
    local phase = slot.phase or "nil"
    local npcEntity = slot.npcEntity
    local vehEntity = slot.vehEntity
    local npcEntityID = slot.npcEntityID
    local vehEntityID = slot.vehEntityID

    -- Commit failure state before cleanup so a despawn-side problem cannot strand the slot in mounting.
    slot.phase = "done"
    slot.failureReason = reason or slot.failureReason or "failed"
    slot.npcEntity = nil
    slot.vehEntity = nil
    noteSlotFailure(slot, slot.failureReason, phase)

    gridLog(
        "slot_spawn_fail_detail slot=%s reason=%s phase=%s vehEntityID=%s npcEntityID=%s vehAttempts=%s vehRetries=%s vehBackend=%s vehKey=%s npcBackend=%s npcKey=%s spawnPos=%s finalPos=%s",
        tostring(slotIndex),
        tostring(slot.failureReason),
        tostring(phase),
        tostring(vehEntityID),
        tostring(npcEntityID),
        tostring(slot.vehicleSpawnAttemptCount),
        tostring(slot.vehicleMaterializeRetryCount),
        tostring(slot.vehicleSpawnBackend),
        tostring(slot.vehicleSpawnResolvedKey),
        tostring(slot.npcSpawnBackend),
        tostring(slot.npcSpawnResolvedKey),
        safePositionSummary(slot.spawnPosition),
        safePositionSummary(slot.position))

    if npcEntity then
        despawnEntity(npcEntity)
    elseif npcEntityID then
        despawnEntity(npcEntityID)
    end
    if vehEntity then
        despawnEntity(vehEntity)
    elseif vehEntityID then
        despawnEntity(vehEntityID)
    end

    slot.npcEntityID = nil
    slot.vehEntityID = nil
    slot.vehicleSpawnBackend = nil
    slot.vehicleSpawnResolvedKey = nil
    slot.npcSpawnBackend = nil
    slot.npcSpawnResolvedKey = nil
    slot.vehicleFindMissCount = nil
    slot.npcFindMissCount = nil
    slot.lastVehicleSpawnPosition = nil
    slot.lastVehicleSpawnHeading = nil
    slot.lastVehicleSpawnStage = nil

    if slot.deferLiveSpawn then
        gridLog("slot_spawn_deferred slot=%s reason=%s phase=%s",
            tostring(slotIndex),
            tostring(slot.failureReason),
            tostring(phase))
    else
        gridLog("slot_spawn_fail slot=%s reason=%s phase=%s",
            tostring(slotIndex),
            tostring(slot.failureReason),
            tostring(phase))
    end
    gridLog("slot=%s phase=done reason=%s",
        tostring(slot.driver and (slot.driver.driverId or slot.driver.id) or "?"),
        tostring(slot.failureReason))
end

countSlotPhases = function()
    local ready, failed, unfinished = 0, 0, 0
    for _, slot in ipairs(_slots) do
        if slot.phase == "ready" or slot.phase == "driving" then
            ready = ready + 1
        elseif slot.phase == "done" then
            failed = failed + 1
        else
            unfinished = unfinished + 1
        end
    end
    return ready, failed, unfinished
end

local function abortGridSession(reason)
    if _grid.abortRequested and _grid.phase == "failed" then
        return
    end
    _grid.abortRequested = true
    _grid.criticalFailureReason = reason or _grid.criticalFailureReason or "formation_failed"
    setGridPhase("failed", _grid.criticalFailureReason)
    local ready, failed, unfinished = countSlotPhases()
    gridLog(
        "formation_failed reason=%s ready=%d failed=%d unfinished=%d activeSpawnIndex=%s",
        tostring(_grid.criticalFailureReason),
        tonumber(ready),
        tonumber(failed),
        tonumber(unfinished),
        tostring(getActiveSpawnIndex()))
end

do
local SLOT_VEHICLE_WIDTH_M       = 2.25  -- conservative footprint width for slot safety checks
local SLOT_VEHICLE_LENGTH_M      = 5.20  -- conservative footprint length for slot safety checks
local SLOT_GROUND_TRACE_UP_M     = 4.0   -- downcast start height for slot ground sampling
local SLOT_GROUND_TRACE_DOWN_M   = 8.0   -- downcast depth for slot ground sampling
local SLOT_CLEARANCE_TRACE_Z_M   = 1.2   -- horizontal blocker probes ride above the sampled surface
local SLOT_PROBE_EPSILON_M       = 0.35  -- ignore hits essentially at the ray endpoint
local SLOT_PLAYER_CLEARANCE_M    = 5.5   -- keep final slots away from V's staged cell
local SLOT_ASSEMBLY_PLAYER_CLEARANCE_M = 12.0 -- keep offsite assembly well clear of the player bubble
local SLOT_RIVAL_CLEARANCE_M     = 4.0   -- minimum center-to-center live rival separation
local SLOT_TRAFFIC_CLEARANCE_M   = 6.0   -- reject slots still occupied by ambient vehicles
local SLOT_VERTICAL_CLEARANCE_M  = 5.0   -- proximity checks should only consider the local road slice
local SLOT_ASSEMBLY_Z_DELTA_M    = 1.25  -- allow only modest ground drift from the synthetic assembly plane
local SLOT_FINAL_Z_DELTA_M       = ROW_Z_CLAMP -- final grid slots must stay close to the solved row height
local SLOT_GROUND_SPREAD_MAX_M   = ROW_Z_CLAMP -- reject slots whose footprint spans too much vertical variance
local _slotSafetyFilterCache = {}
local _slotSafetyFilterNameCache = {}

local function clonePositionTable(pos)
    if type(pos) ~= "table" then
        return nil
    end
    local copy = {}
    for key, value in pairs(pos) do
        copy[key] = value
    end
    return copy
end

local function positionDistanceSquared(a, b, includeVertical)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = includeVertical and ((a.z or 0) - (b.z or 0)) or 0.0
    return (dx * dx) + (dy * dy) + (dz * dz)
end

local function withinVerticalClearance(a, b, maxDelta)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    return math.abs((a.z or 0) - (b.z or 0)) <= (tonumber(maxDelta) or SLOT_VERTICAL_CLEARANCE_M)
end

local function readEntityWorldPosition(entity)
    if not entity then
        return nil
    end
    local pos = nil
    pcall(function()
        local worldPos = entity:GetWorldPosition()
        if worldPos then
            pos = {
                x = worldPos.x,
                y = worldPos.y,
                z = worldPos.z,
            }
        end
    end)
    return pos
end

local function getEntityIdentity(entity)
    if not entity then
        return nil
    end
    local identity = nil
    pcall(function()
        if entity.GetEntityID then
            identity = tostring(entity:GetEntityID())
        end
    end)
    return identity or tostring(entity)
end

local function getPlayerWorldPosition()
    local player = nil
    local playerVehicle = nil
    pcall(function()
        player = Game.GetPlayer()
        if player then
            playerVehicle = Game.GetMountedVehicle(player)
        end
    end)
    local resolved = readEntityWorldPosition(playerVehicle) or readEntityWorldPosition(player)
    gridLog(
        "slot_safety_player_pos source=%s pos=%s",
        playerVehicle and "vehicle" or (player and "player" or "missing"),
        safePositionSummary(resolved))
    return resolved
end

local function collectSystemVehicleLists(system)
    local lists = {}
    if not system then
        gridLog("slot_safety_traffic_system system=nil lists=0")
        return lists
    end

    for _, methodName in ipairs({ "GetActiveVehicles", "GetSpawnedVehicles", "GetVehicles", "GetAllVehicles" }) do
        local method = system[methodName]
        if method then
            local ok, result = pcall(function()
                return method(system)
            end)
            if ok and type(result) == "table" then
                lists[#lists + 1] = result
                gridLog(
                    "slot_safety_traffic_system system=%s method=%s count=%d",
                    tostring(system),
                    tostring(methodName),
                    tonumber(#result or 0))
            else
                gridLog(
                    "slot_safety_traffic_system_miss system=%s method=%s ok=%s resultType=%s",
                    tostring(system),
                    tostring(methodName),
                    tostring(ok),
                    tostring(type(result)))
            end
        else
            gridLog(
                "slot_safety_traffic_system_miss system=%s method=%s ok=false resultType=missing_method",
                tostring(system),
                tostring(methodName))
        end
    end

    return lists
end

local function rememberIgnoredTrafficEntity(ignored, sourceLabel, entity)
    if type(ignored) ~= "table" then
        return false
    end

    local identity = getEntityIdentity(entity)
    if not identity then
        gridLog(
            "slot_safety_traffic_ignore_skip source=%s reason=identity_missing",
            tostring(sourceLabel or "?"))
        return false
    end

    ignored[identity] = true
    gridLog(
        "slot_safety_traffic_ignore source=%s identity=%s",
        tostring(sourceLabel or "?"),
        tostring(identity))
    return true
end

local function resolveTrafficSystem(systemName)
    local ok, systemOrErr = pcall(function()
        local container = Game.GetScriptableSystemsContainer()
        if not container then
            return nil
        end
        return container:Get(systemName)
    end)

    if not ok then
        gridLog(
            "slot_safety_traffic_system_error name=%s err=%s",
            tostring(systemName or "?"),
            tostring(systemOrErr))
        return nil
    end

    gridLog(
        "slot_safety_traffic_system_resolved name=%s present=%s type=%s",
        tostring(systemName or "?"),
        tostring(systemOrErr ~= nil),
        tostring(type(systemOrErr)))
    return systemOrErr
end

local function findNearbyAmbientVehicle(slot, position, clearanceRadius)
    if type(position) ~= "table" then
        gridLog("slot_safety_traffic_fail slot=%s reason=position_missing", tostring(getSlotIndex(slot)))
        return nil
    end

    gridLog(
        "slot_safety_traffic_begin slot=%s clearance=%.2f pos=%s",
        tostring(getSlotIndex(slot)),
        tonumber(clearanceRadius or SLOT_TRAFFIC_CLEARANCE_M),
        safePositionSummary(position))

    local systems = {}
    local vehicleSystem = resolveTrafficSystem("VehicleSystem")
    if vehicleSystem then
        systems[#systems + 1] = vehicleSystem
    end
    local trafficSystem = resolveTrafficSystem("TrafficSystem")
    if trafficSystem then
        systems[#systems + 1] = trafficSystem
    end
    if #systems == 0 then
        gridLog(
            "slot_safety_traffic_skip slot=%s reason=systems_unavailable_clear pos=%s",
            tostring(getSlotIndex(slot)),
            safePositionSummary(position))
        return nil, nil, nil
    end

    local ignored = {}
    local player = nil
    local playerVehicle = nil
    pcall(function()
        player = Game.GetPlayer()
        if player then
            playerVehicle = Game.GetMountedVehicle(player)
        end
    end)
    rememberIgnoredTrafficEntity(ignored, "player_vehicle", playerVehicle)
    rememberIgnoredTrafficEntity(ignored, "slot_vehicle", slot and slot.vehEntity or nil)
    for _, other in ipairs(_slots) do
        rememberIgnoredTrafficEntity(
            ignored,
            string.format("slot_vehicle_%s", tostring(getSlotIndex(other))),
            other and other.vehEntity or nil)
    end

    local clearanceSq = (tonumber(clearanceRadius) or SLOT_TRAFFIC_CLEARANCE_M)
    clearanceSq = clearanceSq * clearanceSq
    local scannedSystems = 0
    local scannedLists = 0
    local scannedCandidates = 0
    local systemErrors = 0
    for _, system in ipairs(systems) do
        scannedSystems = scannedSystems + 1
        local scanOk, hitPosOrErr, hitIdentity, listCount, candidateCount = pcall(function()
            local localLists = 0
            local localCandidates = 0
            for _, list in ipairs(collectSystemVehicleLists(system)) do
                localLists = localLists + 1
                for _, candidate in ipairs(list) do
                    localCandidates = localCandidates + 1
                    local candidateIdentity = getEntityIdentity(candidate)
                    if candidateIdentity and not ignored[candidateIdentity] then
                        local candidatePos = readEntityWorldPosition(candidate)
                        if candidatePos
                            and withinVerticalClearance(position, candidatePos, SLOT_VERTICAL_CLEARANCE_M)
                            and positionDistanceSquared(position, candidatePos, false) <= clearanceSq then
                            return candidatePos, candidateIdentity, localLists, localCandidates
                        end
                    end
                end
            end
            return nil, nil, localLists, localCandidates
        end)
        if not scanOk then
            systemErrors = systemErrors + 1
            gridLog(
                "slot_safety_traffic_system_error slot=%s system=%s err=%s pos=%s",
                tostring(getSlotIndex(slot)),
                tostring(system),
                tostring(hitPosOrErr),
                safePositionSummary(position))
        else
            scannedLists = scannedLists + (tonumber(listCount) or 0)
            scannedCandidates = scannedCandidates + (tonumber(candidateCount) or 0)
            if hitPosOrErr then
                gridLog(
                    "slot_safety_traffic_hit slot=%s vehicle=%s systems=%d lists=%d scanned=%d pos=%s other=%s errors=%d",
                    tostring(getSlotIndex(slot)),
                    tostring(hitIdentity),
                    tonumber(scannedSystems or 0),
                    tonumber(scannedLists or 0),
                    tonumber(scannedCandidates or 0),
                    safePositionSummary(position),
                    safePositionSummary(hitPosOrErr),
                    tonumber(systemErrors or 0))
                return hitPosOrErr, hitIdentity
            end
        end
    end

    gridLog(
        "slot_safety_traffic_clear slot=%s systems=%d lists=%d scanned=%d errors=%d pos=%s",
        tostring(getSlotIndex(slot)),
        tonumber(scannedSystems or 0),
        tonumber(scannedLists or 0),
        tonumber(scannedCandidates or 0),
        tonumber(systemErrors or 0),
        safePositionSummary(position))
    return nil
end

local function findNearbyLiveSlot(slot, position, clearanceRadius)
    if type(position) ~= "table" then
        gridLog("slot_safety_rival_fail slot=%s reason=position_missing", tostring(getSlotIndex(slot)))
        return nil
    end
    local clearanceSq = (tonumber(clearanceRadius) or SLOT_RIVAL_CLEARANCE_M)
    clearanceSq = clearanceSq * clearanceSq
    local scanned = 0
    gridLog(
        "slot_safety_rival_begin slot=%s clearance=%.2f pos=%s",
        tostring(getSlotIndex(slot)),
        tonumber(clearanceRadius or SLOT_RIVAL_CLEARANCE_M),
        safePositionSummary(position))

    for _, other in ipairs(_slots) do
        if other ~= slot and other and other.phase ~= "done" and other.phase ~= "pending" then
            scanned = scanned + 1
            local otherPos = other.livePos
                or readEntityWorldPosition(other.vehEntity)
                or other.position
                or other.spawnPosition
                or other.assemblyPosition
            if otherPos
                and withinVerticalClearance(position, otherPos, SLOT_VERTICAL_CLEARANCE_M)
                and positionDistanceSquared(position, otherPos, false) <= clearanceSq then
                gridLog(
                    "slot_safety_rival_hit slot=%s other=%s scanned=%d pos=%s otherPos=%s",
                    tostring(getSlotIndex(slot)),
                    tostring(getSlotIndex(other)),
                    tonumber(scanned or 0),
                    safePositionSummary(position),
                    safePositionSummary(otherPos))
                return other
            end
        end
    end

    gridLog(
        "slot_safety_rival_clear slot=%s scanned=%d pos=%s",
        tostring(getSlotIndex(slot)),
        tonumber(scanned or 0),
        safePositionSummary(position))
    return nil
end

local function getMinimumSafeVisibleRivals()
    local total = type(_grid.spawnOrder) == "table" and #_grid.spawnOrder or tonumber(_grid.totalSlots or #_slots or 0) or 0
    total = math.max(1, total)
    local minimum = math.min(2, total)
    gridLog(
        "slot_safety_minimum total=%d minimum=%d",
        tonumber(total or 0),
        tonumber(minimum or 0))
    return minimum
end

local function countRemainingActiveSlots(excludeSlot)
    local count = 0
    for _, slot in ipairs(_slots) do
        if slot ~= excludeSlot and slot and slot.phase ~= "done" then
            count = count + 1
        end
    end
    gridLog(
        "slot_safety_remaining exclude=%s count=%d",
        tostring(getSlotIndex(excludeSlot)),
        tonumber(count or 0))
    return count
end

local function getSlotSafetyFilters(kind)
    if type(_slotSafetyFilterCache[kind]) == "table" then
        gridLog(
            "slot_safety_filter_cache kind=%s count=%d",
            tostring(kind),
            tonumber(#_slotSafetyFilterCache[kind] or 0))
        return _slotSafetyFilterCache[kind]
    end

    local source = (kind == "blocker") and { "Static", "PlayerBlocker" } or { "Terrain", "Static", "PlayerBlocker" }
    local compiled = {}
    for _, name in ipairs(source) do
        local value = name
        pcall(function()
            if CName and CName.new then
                value = CName.new(name)
            end
        end)
        compiled[#compiled + 1] = value
    end

    _slotSafetyFilterCache[kind] = compiled
    gridLog(
        "slot_safety_filter_build kind=%s source=%s count=%d",
        tostring(kind),
        tostring(table.concat(source, ",")),
        tonumber(#compiled or 0))
    return compiled
end

local function getSlotSafetyFilterNames(kind)
    if type(_slotSafetyFilterNameCache[kind]) == "table" then
        return _slotSafetyFilterNameCache[kind]
    end

    local source = (kind == "blocker") and { "Static", "PlayerBlocker" } or { "Terrain", "Static", "PlayerBlocker" }
    _slotSafetyFilterNameCache[kind] = source
    return source
end

local function extractRaycastHit(filter, result)
    if not result or not result.position then
        return nil
    end
    return {
        x = result.position.x or 0,
        y = result.position.y or 0,
        z = result.position.z or 0,
        filter = filter,
    }
end

local function raycastNearestCollision(fromPos, toPos, filterKind, staticOnly)
    if type(fromPos) ~= "table" or type(toPos) ~= "table" then
        gridLog(
            "slot_safety_raycast_fail kind=%s reason=position_missing from=%s to=%s",
            tostring(filterKind),
            safePositionSummary(fromPos),
            safePositionSummary(toPos))
        return nil, "raycast_position_missing"
    end

    gridLog(
        "slot_safety_raycast_begin kind=%s staticOnly=%s from=%s to=%s",
        tostring(filterKind),
        tostring(staticOnly == true),
        safePositionSummary(fromPos),
        safePositionSummary(toPos))

    local spatial = nil
    pcall(function()
        spatial = Game.GetSpatialQueriesSystem()
    end)
    if not spatial or not spatial.SyncRaycastByCollisionGroup then
        gridLog(
            "slot_safety_raycast_fail kind=%s reason=spatial_queries_unavailable",
            tostring(filterKind))
        return nil, "spatial_queries_unavailable"
    end

    local from = Vector4.new(fromPos.x or 0, fromPos.y or 0, fromPos.z or 0, 1.0)
    local to = Vector4.new(toPos.x or 0, toPos.y or 0, toPos.z or 0, 1.0)
    local nearest = nil
    local nearestDistSq = nil
    local hitSource = nil

    for _, filter in ipairs(getSlotSafetyFilters(filterKind)) do
        local ok, success, result = pcall(function()
            return spatial:SyncRaycastByCollisionGroup(from, to, filter, staticOnly == true, false)
        end)
        local hit = ok and success and extractRaycastHit(filter, result) or nil
        if hit then
            local distSq = positionDistanceSquared(fromPos, hit, true)
            if nearestDistSq == nil or distSq < nearestDistSq then
                nearest = hit
                nearestDistSq = distSq
                hitSource = "five_arg"
            end
            gridLog(
                "slot_safety_raycast_hit kind=%s filter=%s source=%s distSq=%.3f hit=%s",
                tostring(filterKind),
                tostring(filter),
                "five_arg",
                tonumber(distSq or 0.0),
                safePositionSummary(hit))
        else
            gridLog(
                "slot_safety_raycast_probe kind=%s filter=%s ok=%s success=%s result=%s",
                tostring(filterKind),
                tostring(filter),
                tostring(ok),
                tostring(success),
                tostring(result ~= nil))
        end
    end

    if not nearest and physicsTraceResult and physicsTraceResult.new then
        for _, filterName in ipairs(getSlotSafetyFilterNames(filterKind)) do
            local trace = physicsTraceResult.new()
            local ok, success, result = pcall(function()
                return spatial:SyncRaycastByCollisionGroup(from, to, filterName, trace)
            end)
            local traceResult = result or trace
            local hit = ok and success and extractRaycastHit(filterName, traceResult) or nil
            if hit then
                local distSq = positionDistanceSquared(fromPos, hit, true)
                if nearestDistSq == nil or distSq < nearestDistSq then
                    nearest = hit
                    nearestDistSq = distSq
                    hitSource = "trace_result"
                end
                gridLog(
                    "slot_safety_raycast_hit kind=%s filter=%s source=%s distSq=%.3f hit=%s",
                    tostring(filterKind),
                    tostring(filterName),
                    "trace_result",
                    tonumber(distSq or 0.0),
                    safePositionSummary(hit))
            else
                gridLog(
                    "slot_safety_raycast_probe kind=%s filter=%s source=%s ok=%s success=%s result=%s",
                    tostring(filterKind),
                    tostring(filterName),
                    "trace_result",
                    tostring(ok),
                    tostring(success),
                    tostring(traceResult ~= nil))
            end
        end
    end

    if nearest then
        gridLog(
            "slot_safety_raycast_result kind=%s result=hit source=%s hit=%s distSq=%.3f",
            tostring(filterKind),
            tostring(hitSource or "unknown"),
            safePositionSummary(nearest),
            tonumber(nearestDistSq or 0.0))
    else
        gridLog(
            "slot_safety_raycast_result kind=%s result=miss reason=raycast_miss",
            tostring(filterKind))
    end
    return nearest, nearest and nil or "raycast_miss"
end

local function sampleGroundAtPosition(position)
    local expectedZ = tonumber(position and position.z or 0) or 0
    gridLog(
        "slot_safety_ground_probe pos=%s expectedZ=%.2f",
        safePositionSummary(position),
        tonumber(expectedZ or 0.0))
    local hit, reason = raycastNearestCollision(
        {
            x = position.x or 0,
            y = position.y or 0,
            z = expectedZ + SLOT_GROUND_TRACE_UP_M,
        },
        {
            x = position.x or 0,
            y = position.y or 0,
            z = expectedZ - SLOT_GROUND_TRACE_DOWN_M,
        },
        "ground",
        false)
    if hit then
        gridLog(
            "slot_safety_ground_hit pos=%s hit=%s",
            safePositionSummary(position),
            safePositionSummary(hit))
    else
        gridLog(
            "slot_safety_ground_miss pos=%s reason=%s",
            safePositionSummary(position),
            tostring(reason))
    end
    return hit, reason
end

local function buildSlotFootprintPoints(position, headingDeg, baseZ)
    local heading = normalizeHeadingDeg(headingDeg or position and position.heading or 0) or 0.0
    local forwardX, forwardY = headingToUnitVector(heading)
    local rightX, rightY = -forwardY, forwardX
    local centerZ = tonumber(baseZ or position and position.z or 0) or 0.0
    local halfLength = SLOT_VEHICLE_LENGTH_M * 0.45
    local halfWidth = SLOT_VEHICLE_WIDTH_M * 0.65

    local function point(label, longOffset, lateralOffset)
        return {
            label = label,
            x = (position.x or 0) + (forwardX * longOffset) + (rightX * lateralOffset),
            y = (position.y or 0) + (forwardY * longOffset) + (rightY * lateralOffset),
            z = centerZ,
        }
    end

    local points = {
        point("center", 0.0, 0.0),
        point("front", halfLength, 0.0),
        point("rear", -halfLength, 0.0),
        point("left", 0.0, -halfWidth),
        point("right", 0.0, halfWidth),
        point("front_left", halfLength * 0.8, -halfWidth * 0.8),
        point("front_right", halfLength * 0.8, halfWidth * 0.8),
        point("rear_left", -halfLength * 0.8, -halfWidth * 0.8),
        point("rear_right", -halfLength * 0.8, halfWidth * 0.8),
    }
    gridLog(
        "slot_safety_footprint heading=%.2f baseZ=%.2f center=%s front=%s rear=%s points=%d",
        tonumber(heading or 0.0),
        tonumber(centerZ or 0.0),
        safePositionSummary(points[1]),
        safePositionSummary(points[2]),
        safePositionSummary(points[3]),
        tonumber(#points or 0))
    return points
end

local function evaluateFootprintGround(points, expectedZ, centerDeltaMax)
    local samples = {}
    local centerSample = nil
    local minZ = nil
    local maxZ = nil
    gridLog(
        "slot_safety_ground_begin expectedZ=%.2f centerDeltaMax=%.2f points=%d",
        tonumber(expectedZ or 0.0),
        tonumber(centerDeltaMax or SLOT_FINAL_Z_DELTA_M),
        tonumber(#(points or {}) or 0))

    for _, point in ipairs(points or {}) do
        local hit, reason = sampleGroundAtPosition(point)
        if not hit then
            gridLog(
                "slot_safety_ground_fail point=%s reason=%s trace=%s",
                tostring(point and point.label or "?"),
                "ground_missing:" .. tostring(point and point.label or "?"),
                tostring(reason))
            return nil, "ground_missing:" .. tostring(point and point.label or "?"), reason
        end

        local sample = {
            label = point.label,
            x = hit.x,
            y = hit.y,
            z = hit.z,
        }
        samples[point.label] = sample
        minZ = (minZ == nil) and sample.z or math.min(minZ, sample.z)
        maxZ = (maxZ == nil) and sample.z or math.max(maxZ, sample.z)
        if point.label == "center" then
            centerSample = sample
        end
        gridLog(
            "slot_safety_ground_sample point=%s sample=%s",
            tostring(point.label),
            safePositionSummary(sample))
    end

    if not centerSample then
        gridLog("slot_safety_ground_fail point=center reason=ground_missing:center")
        return nil, "ground_missing:center"
    end

    local spread = math.max(0.0, (maxZ or centerSample.z) - (minZ or centerSample.z))
    if spread > SLOT_GROUND_SPREAD_MAX_M then
        gridLog(
            "slot_safety_ground_fail point=footprint reason=ground_spread_exceeded spread=%.2f max=%.2f",
            tonumber(spread or 0.0),
            tonumber(SLOT_GROUND_SPREAD_MAX_M or 0.0))
        return nil, "ground_spread_exceeded"
    end

    if isFiniteNumber(expectedZ) and math.abs((centerSample.z or 0) - expectedZ) > (tonumber(centerDeltaMax) or SLOT_FINAL_Z_DELTA_M) then
        gridLog(
            "slot_safety_ground_fail point=center reason=ground_center_delta_exceeded centerZ=%.2f expectedZ=%.2f maxDelta=%.2f",
            tonumber(centerSample.z or 0.0),
            tonumber(expectedZ or 0.0),
            tonumber(centerDeltaMax or SLOT_FINAL_Z_DELTA_M))
        return nil, "ground_center_delta_exceeded"
    end

    local result = {
        centerZ = centerSample.z,
        spread = spread,
        samples = samples,
    }
    gridLog(
        "slot_safety_ground_ok centerZ=%.2f spread=%.2f",
        tonumber(result.centerZ or 0.0),
        tonumber(result.spread or 0.0))
    return result
end

local function hasBlockerBetweenPoints(fromPoint, toPoint)
    if type(fromPoint) ~= "table" or type(toPoint) ~= "table" then
        gridLog(
            "slot_safety_blocker_fail reason=position_missing from=%s to=%s",
            safePositionSummary(fromPoint),
            safePositionSummary(toPoint))
        return true, "blocker_position_missing"
    end

    local from = {
        x = fromPoint.x or 0,
        y = fromPoint.y or 0,
        z = (fromPoint.z or 0) + SLOT_CLEARANCE_TRACE_Z_M,
    }
    local to = {
        x = toPoint.x or 0,
        y = toPoint.y or 0,
        z = (toPoint.z or 0) + SLOT_CLEARANCE_TRACE_Z_M,
    }
    gridLog(
        "slot_safety_blocker_begin from=%s to=%s",
        safePositionSummary(from),
        safePositionSummary(to))
    local hit, reason = raycastNearestCollision(from, to, "blocker", true)
    if not hit then
        gridLog(
            "slot_safety_blocker_clear from=%s to=%s reason=%s",
            safePositionSummary(from),
            safePositionSummary(to),
            tostring(reason))
        return false, reason
    end

    local totalDistSq = positionDistanceSquared(from, to, true)
    local hitDistSq = positionDistanceSquared(from, hit, true)
    local epsilonSq = SLOT_PROBE_EPSILON_M * SLOT_PROBE_EPSILON_M
    if hitDistSq + epsilonSq < totalDistSq then
        gridLog(
            "slot_safety_blocker_hit from=%s to=%s hit=%s hitDistSq=%.3f totalDistSq=%.3f",
            safePositionSummary(from),
            safePositionSummary(to),
            safePositionSummary(hit),
            tonumber(hitDistSq or 0.0),
            tonumber(totalDistSq or 0.0))
        return true, "static_blocker_detected"
    end

    gridLog(
        "slot_safety_blocker_clear from=%s to=%s reason=endpoint_or_epsilon hit=%s",
        safePositionSummary(from),
        safePositionSummary(to),
        safePositionSummary(hit))
    return false
end

local function validateSlotPlacementSafety(slot, candidatePos, headingDeg, stageLabel, options)
    options = options or {}
    if type(slot) ~= "table" or type(candidatePos) ~= "table" then
        gridLog(
            "slot_safety_fail slot=%s stage=%s reason=slot_position_missing pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(candidatePos))
        return false, "slot_position_missing"
    end

    gridLog(
        "slot_safety_begin slot=%s stage=%s heading=%.2f expectedZ=%.2f playerClearance=%.2f rivalClearance=%.2f trafficClearance=%.2f checkTraffic=%s skipGroundProbe=%s pos=%s",
        tostring(getSlotIndex(slot)),
        tostring(stageLabel),
        tonumber(headingDeg or candidatePos.heading or 0.0),
        tonumber(options.expectedZ or candidatePos.z or 0.0),
        tonumber(options.playerClearance or SLOT_PLAYER_CLEARANCE_M),
        tonumber(options.rivalClearance or SLOT_RIVAL_CLEARANCE_M),
        tonumber(options.trafficClearance or SLOT_TRAFFIC_CLEARANCE_M),
        tostring(options.checkTraffic ~= false),
        tostring(options.skipGroundProbe == true),
        safePositionSummary(candidatePos))

    local footprint = buildSlotFootprintPoints(candidatePos, headingDeg, candidatePos.z)
    local expectedZ = tonumber(options.expectedZ or candidatePos.z)
    local ground = nil
    local groundReason = nil
    if options.skipGroundProbe == true then
        local trustedCenterZ = expectedZ
        if not isFiniteNumber(trustedCenterZ) then
            trustedCenterZ = tonumber(candidatePos.z)
        end
        if not isFiniteNumber(trustedCenterZ) then
            gridLog(
                "slot_safety_ground_skip_fail slot=%s stage=%s reason=missing_expected_z pos=%s",
                tostring(getSlotIndex(slot)),
                tostring(stageLabel),
                safePositionSummary(candidatePos))
            return false, tostring(stageLabel) .. "_ground_expected_z_missing"
        end

        ground = {
            centerZ = trustedCenterZ,
            spread = 0.0,
            samples = {
                center = {
                    label = "center",
                    x = candidatePos.x or 0,
                    y = candidatePos.y or 0,
                    z = trustedCenterZ,
                    trusted = true,
                },
            },
            trusted = true,
        }
        gridLog(
            "slot_safety_ground_skip slot=%s stage=%s reason=trust_solved_node_grid centerZ=%.2f pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            tonumber(trustedCenterZ or 0.0),
            safePositionSummary(candidatePos))
    else
        ground, groundReason = evaluateFootprintGround(
            footprint,
            expectedZ,
            options.centerDeltaMax or SLOT_FINAL_Z_DELTA_M)
    end
    if not ground then
        gridLog(
            "slot_safety_fail slot=%s stage=%s reason=%s pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            tostring(groundReason),
            safePositionSummary(candidatePos))
        return false, tostring(stageLabel) .. "_" .. tostring(groundReason)
    end

    local playerPos = getPlayerWorldPosition()
    local playerClearance = tonumber(options.playerClearance or SLOT_PLAYER_CLEARANCE_M) or SLOT_PLAYER_CLEARANCE_M
    if playerPos
        and withinVerticalClearance(candidatePos, playerPos, SLOT_VERTICAL_CLEARANCE_M)
        and positionDistanceSquared(candidatePos, playerPos, false) <= (playerClearance * playerClearance) then
        gridLog(
            "slot_safety_fail slot=%s stage=%s reason=player_clearance pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(candidatePos))
        return false, tostring(stageLabel) .. "_player_clearance"
    elseif not playerPos then
        gridLog(
            "slot_safety_player_clear slot=%s stage=%s reason=player_missing pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(candidatePos))
    else
        gridLog(
            "slot_safety_player_clear slot=%s stage=%s player=%s pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(playerPos),
            safePositionSummary(candidatePos))
    end

    local nearbySlot = findNearbyLiveSlot(slot, candidatePos, options.rivalClearance or SLOT_RIVAL_CLEARANCE_M)
    if nearbySlot then
        gridLog(
            "slot_safety_fail slot=%s stage=%s reason=live_rival_clearance other=%s pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            tostring(getSlotIndex(nearbySlot)),
            safePositionSummary(candidatePos))
        return false, tostring(stageLabel) .. "_live_rival_clearance"
    else
        gridLog(
            "slot_safety_rival_clear slot=%s stage=%s pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(candidatePos))
    end

    if options.checkTraffic ~= false then
        local trafficPos, trafficIdentity, trafficReason = findNearbyAmbientVehicle(slot, candidatePos, options.trafficClearance or SLOT_TRAFFIC_CLEARANCE_M)
        if trafficPos then
            gridLog(
                "slot_safety_fail slot=%s stage=%s reason=ambient_vehicle_clearance vehicle=%s pos=%s",
                tostring(getSlotIndex(slot)),
                tostring(stageLabel),
                tostring(trafficIdentity or "?"),
                safePositionSummary(candidatePos))
            return false, tostring(stageLabel) .. "_ambient_vehicle_clearance"
        end
        gridLog(
                "slot_safety_traffic_clear slot=%s stage=%s pos=%s",
                tostring(getSlotIndex(slot)),
                tostring(stageLabel),
                safePositionSummary(candidatePos))
    else
        gridLog(
            "slot_safety_traffic_skip slot=%s stage=%s pos=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(candidatePos))
    end

    local centerSample = ground.samples and ground.samples.center or nil
    if centerSample then
        for label, sample in pairs(ground.samples or {}) do
            if label ~= "center" then
                local blocked, blockerReason = hasBlockerBetweenPoints(centerSample, sample)
                if blocked then
                    gridLog(
                        "slot_safety_fail slot=%s stage=%s reason=%s probe=%s pos=%s",
                        tostring(getSlotIndex(slot)),
                        tostring(stageLabel),
                        tostring(blockerReason),
                        tostring(label),
                        safePositionSummary(candidatePos))
                    return false, tostring(stageLabel) .. "_" .. tostring(blockerReason)
                end
            end
        end
        gridLog(
            "slot_safety_blocker_clear slot=%s stage=%s center=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(centerSample))
    end

    gridLog(
        "slot_safety_ok slot=%s stage=%s centerZ=%.2f spread=%.2f pos=%s",
        tostring(getSlotIndex(slot)),
        tostring(stageLabel),
        tonumber(ground.centerZ or 0.0),
        tonumber(ground.spread or 0.0),
        safePositionSummary(candidatePos))
    return true, ground
end

local function guardedValidateSlotPlacementSafety(slot, candidatePos, headingDeg, stageLabel, options)
    local ok, safetyOk, safetyResult = pcall(
        validateSlotPlacementSafety,
        slot,
        candidatePos,
        headingDeg,
        stageLabel,
        options)

    if not ok then
        gridLog(
            "slot_safety_exception slot=%s stage=%s pos=%s err=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            safePositionSummary(candidatePos),
            tostring(safetyOk))
        return false, tostring(stageLabel) .. "_validation_exception"
    end

    return safetyOk, safetyResult
end

local function applyValidatedSlotPositionZ(slot, fieldName, centerZ, lift)
    if type(slot) ~= "table" or type(slot[fieldName]) ~= "table" or not isFiniteNumber(centerZ) then
        gridLog(
            "slot_safety_adjust_skip slot=%s field=%s centerZ=%s lift=%s",
            tostring(getSlotIndex(slot)),
            tostring(fieldName),
            tostring(centerZ),
            tostring(lift))
        return
    end
    slot[fieldName].z = centerZ + (tonumber(lift) or 0.0)
    gridLog(
        "slot_safety_adjust slot=%s field=%s centerZ=%.2f lift=%.2f finalZ=%.2f",
        tostring(getSlotIndex(slot)),
        tostring(fieldName),
        tonumber(centerZ or 0.0),
        tonumber(lift or 0.0),
        tonumber(slot[fieldName].z or 0.0))
end

local function cancelFormationForSafety(reason)
    gridLog(
        "slot_safety_cancel reason=%s slots=%d",
        tostring(reason),
        tonumber(#_slots or 0))
    for _, slot in ipairs(_slots) do
        if slot and slot.phase ~= "done" then
            failSlot(slot, reason)
        end
    end
    _grid.nextSlotIndex = (_grid.totalSlots or #_slots or 0) + 1
    _grid.spawnCursor = type(_grid.spawnOrder) == "table" and (#_grid.spawnOrder + 1) or _grid.nextSlotIndex
    abortGridSession(reason)
end

local function handleUnsafeSlot(slot, slotArrayIndex, reason, stageLabel)
    local remaining = countRemainingActiveSlots(slot)
    local minimum = getMinimumSafeVisibleRivals()
    local criticalFinalSlot = tostring(stageLabel) == "final" and tonumber(slot and slot.gridRow or 99) <= 0

    gridLog(
        "slot_safety_handle slot=%s stage=%s reason=%s remaining=%d minimum=%d critical=%s",
        tostring(getSlotIndex(slot)),
        tostring(stageLabel),
        tostring(reason),
        tonumber(remaining or 0),
        tonumber(minimum or 0),
        tostring(criticalFinalSlot))

    failSlot(slot, reason)
    advanceSpawnCursor(slotArrayIndex)

    if criticalFinalSlot or remaining < minimum then
        local abortReason = criticalFinalSlot and ("critical_" .. tostring(reason)) or "insufficient_safe_rivals"
        gridLog(
            "slot_safety_abort slot=%s stage=%s reason=%s remaining=%d minimum=%d critical=%s",
            tostring(getSlotIndex(slot)),
            tostring(stageLabel),
            tostring(abortReason),
            tonumber(remaining or 0),
            tonumber(minimum or 0),
            tostring(criticalFinalSlot))
        cancelFormationForSafety(abortReason)
        return true
    end

    gridLog(
        "slot_safety_skip_continue slot=%s stage=%s reason=%s remaining=%d minimum=%d",
        tostring(getSlotIndex(slot)),
        tostring(stageLabel),
        tostring(reason),
        tonumber(remaining or 0),
        tonumber(minimum or 0))
    return false
end

SlotSafety.clonePositionTable = clonePositionTable
SlotSafety.positionDistanceSquared = positionDistanceSquared
SlotSafety.withinVerticalClearance = withinVerticalClearance
SlotSafety.readEntityWorldPosition = readEntityWorldPosition
SlotSafety.getEntityIdentity = getEntityIdentity
SlotSafety.getPlayerWorldPosition = getPlayerWorldPosition
SlotSafety.collectSystemVehicleLists = collectSystemVehicleLists
SlotSafety.findNearbyAmbientVehicle = findNearbyAmbientVehicle
SlotSafety.findNearbyLiveSlot = findNearbyLiveSlot
SlotSafety.getMinimumSafeVisibleRivals = getMinimumSafeVisibleRivals
SlotSafety.countRemainingActiveSlots = countRemainingActiveSlots
SlotSafety.getSlotSafetyFilters = getSlotSafetyFilters
SlotSafety.raycastNearestCollision = raycastNearestCollision
SlotSafety.sampleGroundAtPosition = sampleGroundAtPosition
SlotSafety.buildSlotFootprintPoints = buildSlotFootprintPoints
SlotSafety.evaluateFootprintGround = evaluateFootprintGround
SlotSafety.hasBlockerBetweenPoints = hasBlockerBetweenPoints
SlotSafety.validateSlotPlacementSafety = validateSlotPlacementSafety
SlotSafety.guardedValidateSlotPlacementSafety = guardedValidateSlotPlacementSafety
SlotSafety.applyValidatedSlotPositionZ = applyValidatedSlotPositionZ
SlotSafety.cancelFormationForSafety = cancelFormationForSafety
SlotSafety.handleUnsafeSlot = handleUnsafeSlot
SlotSafety.SLOT_PLAYER_CLEARANCE_M = SLOT_PLAYER_CLEARANCE_M
SlotSafety.SLOT_ASSEMBLY_PLAYER_CLEARANCE_M = SLOT_ASSEMBLY_PLAYER_CLEARANCE_M
SlotSafety.SLOT_RIVAL_CLEARANCE_M = SLOT_RIVAL_CLEARANCE_M
SlotSafety.SLOT_TRAFFIC_CLEARANCE_M = SLOT_TRAFFIC_CLEARANCE_M
SlotSafety.SLOT_ASSEMBLY_Z_DELTA_M = SLOT_ASSEMBLY_Z_DELTA_M
SlotSafety.SLOT_FINAL_Z_DELTA_M = SLOT_FINAL_Z_DELTA_M

end

local function buildSolverContext(queued, count)
    local basis = resolveGridBasis(queued.startNode, queued.finishNode, queued)
    local context = {
        startNode = queued.startNode,
        finishNode = queued.finishNode,
        field = queued.field,
        count = count,
        raceType = queued.raceType,
        startType = queued.startType,
        playerGridPos = queued.playerGridPos,
        dragStrip = queued.dragStrip,
        heading = basis and basis.heading or 0.0,
        slotHeading = basis and (basis.slotHeading or basis.heading) or 0.0,
        forwardX = basis and basis.forwardX or 1.0,
        forwardY = basis and basis.forwardY or 0.0,
        rightX = basis and basis.rightX or 0.0,
        rightY = basis and basis.rightY or 1.0,
        baseZ = (queued.startNode and queued.startNode.z or 0) + FINAL_SLOT_Z_OFFSET,
        spacing = {
            gridRowSpacing = tuningValue("aiGridRowSpacingM", queued),
            gridColOffset = tuningValue("aiGridColOffsetM", queued),
            gridStartSetback = tuningValue("aiGridStartSetbackM", queued),
            rollingRowSpacing = tuningValue("aiRollingRowSpacingM", queued),
            sideBySideSpacing = tuningValue("aiSideBySideSpacingM", queued),
            sideBySideSetback = tuningValue("aiSideBySideSetbackM", queued),
        },
        trafficPrepared = queued.trafficPrepared == true,
        trafficClearRadius = queued.trafficClearRadius,
        trafficVerticalTolerance = queued.trafficVerticalTolerance,
        stageSource = queued.stageSource,
        routeId = queued.routeId,
        routeMode = queued.routeMode,
    }
    gridLog(
        "grid_solver_context count=%d startType=%s raceType=%s heading=%.2f slotHeading=%.2f start=%s finish=%s trafficPrepared=%s clearRadius=%s",
        tonumber(count or 0),
        tostring(queued.startType or "grid"),
        tostring(queued.raceType or "sprint"),
        tonumber(context.heading or 0.0),
        tonumber(context.slotHeading or 0.0),
        safePositionSummary(context.startNode),
        safePositionSummary(context.finishNode),
        tostring(context.trafficPrepared == true),
        tostring(context.trafficClearRadius))
    if context.spacing then
        gridLog(
            "grid_solver_context_spacing gridRow=%.2f gridCol=%.2f setback=%.2f rollingRow=%.2f sideBySide=%.2f sideSetback=%.2f",
            tonumber(context.spacing.gridRowSpacing or 0.0),
            tonumber(context.spacing.gridColOffset or 0.0),
            tonumber(context.spacing.gridStartSetback or 0.0),
            tonumber(context.spacing.rollingRowSpacing or 0.0),
            tonumber(context.spacing.sideBySideSpacing or 0.0),
            tonumber(context.spacing.sideBySideSetback or 0.0))
    end
    return context
end

local function summarizeSolveResult(result, queued, count)
    local requestedFormation = queued and queued.startType == "sidebyside"
        and GridSolver.FORMATION.SIDEBYSIDE
        or GridSolver.FORMATION.DOUBLE_FILE
    local requestedStartType = tostring(queued and queued.startType or "grid")

    if type(result) ~= "table" then
        local summary = {
            status = GridSolver.STATUS.FAILURE,
            valid = false,
            requestedStartType = requestedStartType,
            requestedFormation = requestedFormation,
            finalFormation = requestedFormation,
            reason = "solver_missing",
            probeMode = "none",
            trafficPrepared = queued and queued.trafficPrepared == true,
            legacyFallback = false,
            validSlots = 0,
            estimatedRoadWidthM = nil,
            routeGrade = nil,
            corridorLengthM = nil,
        }
        gridLog(
            "grid_solver_summary status=%s valid=%s requested=%s final=%s reason=%s validSlots=%d expectedCount=%d",
            tostring(summary.status or "?"),
            tostring(summary.valid == true),
            tostring(summary.requestedFormation or "?"),
            tostring(summary.finalFormation or "?"),
            tostring(summary.reason or ""),
            tonumber(summary.validSlots or 0),
            tonumber(count or 0))
        return summary
    end

    local summary = {
        status = result.status,
        valid = result.valid == true,
        requestedStartType = result.requestedStartType or requestedStartType,
        requestedFormation = result.requestedFormation,
        finalFormation = result.finalFormation,
        reason = result.reason,
        probeMode = result.probeMode,
        trafficPrepared = result.trafficPrepared == true,
        legacyFallback = result.legacyFallback == true,
        validSlots = #(result.positions or {}),
        estimatedRoadWidthM = result.estimatedRoadWidthM,
        routeGrade = result.routeGrade,
        corridorLengthM = result.corridorLengthM,
        supportedLaneCount = result.supportedLaneCount,
        effectiveLaneCount = result.effectiveLaneCount,
        fieldSizeReduced = result.fieldSizeReduced == true,
    }
    gridLog(
        "grid_solver_summary status=%s valid=%s requested=%s final=%s reason=%s validSlots=%d expectedCount=%d probe=%s legacy=%s",
        tostring(summary.status or "?"),
        tostring(summary.valid == true),
        tostring(summary.requestedFormation or "?"),
        tostring(summary.finalFormation or "?"),
        tostring(summary.reason or ""),
        tonumber(summary.validSlots or 0),
        tonumber(count or 0),
        tostring(summary.probeMode or "none"),
        tostring(summary.legacyFallback == true))
    return summary
end

local function prepareQueuedSlots()
    if _grid.slotsPrepared then
        return true
    end

    local queued = _queuedFormation
    if type(queued) ~= "table" or type(queued.field) ~= "table" or not queued.startNode or not queued.finishNode then
        gridLog("slots_prepare_failed reason=queued_formation_missing")
        return false
    end

    local field = queued.field
    local count = math.min(#field, maxAiCars(queued))
    local deferredPreraceSlots = 0
    gridLog("slots_prepare_begin total=%d startType=%s assembly=%s context=%s",
        tonumber(count or 0),
        tostring(queued.startType or "grid"),
        tostring(queued.assemblyMode or "assembly"),
        tostring(queued.context or "default"))
    local solveResult = nil
    local solveContext = buildSolverContext(queued, count)
    if GridSolver and GridSolver.solveFormation then
        local ok, resultOrErr = pcall(GridSolver.solveFormation, solveContext)
        if ok and type(resultOrErr) == "table" then
            solveResult = resultOrErr
            gridLog(
                "grid_solver_raw status=%s valid=%s degraded=%s legacy=%s reason=%s positions=%d slots=%d attempts=%d",
                tostring(solveResult.status or "?"),
                tostring(solveResult.valid == true),
                tostring(solveResult.degraded == true),
                tostring(solveResult.legacyFallback == true),
                tostring(solveResult.reason or ""),
                tonumber(#(solveResult.positions or {}) or 0),
                tonumber(#(solveResult.slots or {}) or 0),
                tonumber(#(solveResult.attempts or {}) or 0))
            for attemptIndex, attempt in ipairs(solveResult.attempts or {}) do
                gridLog(
                    "grid_solver_attempt index=%d tag=%s formation=%s valid=%s reason=%s",
                    tonumber(attemptIndex or 0),
                    tostring(attempt and attempt.tag or "?"),
                    tostring(attempt and attempt.formation or "?"),
                    tostring(attempt and attempt.valid == true),
                    tostring(attempt and attempt.reason or ""))
            end
        else
            gridLog("grid_solver_failed err=%s", tostring(resultOrErr or "unknown"))
        end
    end
    _grid.solverSummary = summarizeSolveResult(solveResult, queued, count)
    local solverValid = type(solveResult) == "table"
        and solveResult.status == GridSolver.STATUS.SUCCESS
        and solveResult.valid == true
        and type(solveResult.positions) == "table"
        and #solveResult.positions >= count
        and type(solveResult.slots) == "table"
        and #solveResult.slots >= count
    if not solverValid then
        local solveReason = solveResult and solveResult.reason or (_grid.solverSummary and _grid.solverSummary.reason) or "solver_invalid"
        _grid.criticalFailureReason = "grid_rejected_no_safe_layout:" .. tostring(solveReason)
        gridLog("grid_solver_rejected reason=%s startType=%s raceType=%s status=%s valid=%s",
            tostring(solveReason),
            tostring(queued.startType or "grid"),
            tostring(queued.raceType or "sprint"),
            tostring(solveResult and solveResult.status or _grid.solverSummary and _grid.solverSummary.status or "missing"),
            tostring(solveResult and solveResult.valid == true))
        return false
    end
    if _grid.solverSummary then
        gridLog(
            "grid_solver status=%s valid=%s requested=%s final=%s legacy=%s trafficPrepared=%s probe=%s reason=%s width=%.1f grade=%.3f",
            tostring(_grid.solverSummary.status or "?"),
            tostring(_grid.solverSummary.valid == true),
            tostring(_grid.solverSummary.requestedFormation or "?"),
            tostring(_grid.solverSummary.finalFormation or "?"),
            tostring(_grid.solverSummary.legacyFallback),
            tostring(_grid.solverSummary.trafficPrepared),
            tostring(_grid.solverSummary.probeMode or "none"),
            tostring(_grid.solverSummary.reason or ""),
            tonumber(_grid.solverSummary.estimatedRoadWidthM or 0.0),
            tonumber(_grid.solverSummary.routeGrade or 0.0))
    end
    local positions = solveResult.positions
    local assemblyPositions = nil
    if queued.assemblyMode ~= "direct" then
        assemblyPositions = calculateAssemblyFormation(queued.startNode, queued.finishNode, count, queued, positions)
        gridLog(
            "grid_solver_assembly_positions mode=%s placement=%s count=%d",
            tostring(queued.assemblyMode or "assembly"),
            tostring(queued.assemblyPlacement or "node_grid"),
            tonumber(#(assemblyPositions or {}) or 0))
    end

    _slots = {}
    for i = 1, count do
        local entry = field[i]
        local position = positions[i]
        local assemblyPosition = assemblyPositions and assemblyPositions[i] or nil
        local solveSlot = solveResult and solveResult.slots and solveResult.slots[i] or nil
        gridLog(
            "grid_solver_slot_assignment slot=%d driver=%s final=%s assembly=%s solveValid=%s solveReason=%s",
            tonumber(i or 0),
            tostring(entry and (entry.driverId or entry.id) or "?"),
            safePositionSummary(position),
            safePositionSummary(assemblyPosition),
            tostring(solveSlot and solveSlot.valid == true),
            tostring(solveSlot and solveSlot.reason or ""))
        if type(entry) ~= "table" then
            _slots[i] = {
                driver = nil,
                phase = "done",
                failureReason = "entry_not_table",
            }
            gridLog("slot_spawn_fail slot=%d reason=entry_not_table", tonumber(i or 0))
        elseif type(position) ~= "table" then
            _slots[i] = {
                driver = entry,
                phase = "done",
                failureReason = "position_not_table",
            }
            gridLog("slot_spawn_fail slot=%d reason=position_not_table", tonumber(i or 0))
        else
            local ok, slotOrErr = pcall(buildSlotState, i, entry, position, assemblyPosition, queued, solveSlot)
            if ok and type(slotOrErr) == "table" then
                _slots[i] = slotOrErr
                entry.slotIndex = i
                gridLog(
                    "grid_solver_slot_built slot=%d phase=%s spawn=%s assembly=%s final=%s heading=%.2f",
                    tonumber(i or 0),
                    tostring(_slots[i].phase or "?"),
                    safePositionSummary(_slots[i].spawnPosition),
                    safePositionSummary(_slots[i].assemblyPosition),
                    safePositionSummary(_slots[i].position),
                    tonumber(_slots[i].heading or 0.0))
                classifySlotSpawnRisk(_slots[i])
                local shouldDefer, deferReason = shouldDeferPreraceSlot(_slots[i])
                if shouldDefer then
                    _slots[i].deferLiveSpawn = true
                    deferredPreraceSlots = deferredPreraceSlots + 1
                    gridLog(
                        "grid_solver_slot_deferred slot=%d reason=%s",
                        tonumber(i or 0),
                        tostring(deferReason))
                    failSlot(_slots[i], deferReason)
                else
                    local rejectForCrashGuard, crashGuardReason = shouldRejectSlotForCrashGuard(_slots[i])
                    if rejectForCrashGuard then
                        _slots[i].deferLiveSpawn = true
                        deferredPreraceSlots = deferredPreraceSlots + 1
                        gridLog(
                            "slot_crash_guard_reject slot=%s driver=%s reason=%s npc=%s vehicle=%s risk=%s",
                            tostring(getSlotIndex(_slots[i])),
                            tostring(getSlotDriverKey(_slots[i])),
                            tostring(crashGuardReason),
                            tostring(VehiclePool.describeNPC(_slots[i].npcRecord)),
                            tostring(_slots[i].vehRecord),
                            tostring(_slots[i].spawnRiskLabel or "unknown"))
                        failSlot(_slots[i], crashGuardReason)
                    else
                        local preflightOk, preflightReason = validateSlotPreflight(_slots[i], "prepare")
                        if not preflightOk then
                            gridLog(
                                "grid_solver_slot_preflight_fail slot=%d reason=%s",
                                tonumber(i or 0),
                                tostring(preflightReason))
                            failSlot(_slots[i], preflightReason)
                        else
                            gridLog(
                                "grid_solver_slot_preflight_ok slot=%d",
                                tonumber(i or 0))
                        end
                    end
                end
            else
                _slots[i] = {
                    driver = entry,
                    phase = "done",
                    failureReason = tostring(slotOrErr or "slot_build_failed"),
                }
                gridLog("slot_spawn_fail slot=%d reason=slot_build_failed err=%s",
                    tonumber(i or 0),
                    tostring(slotOrErr or "slot_build_failed"))
            end
        end
    end

    rebuildSpawnPlan()
    _grid.slotsPrepared = true
    clearQueuedFormation()
    local ready, failed, unfinished = countSlotPhases()
    gridLog(
        "slots_prepared total=%d active=%d deferred=%d ready=%d failed=%d unfinished=%d firstLive=%s",
        tonumber(count or 0),
        tonumber(_grid.spawnOrder and #_grid.spawnOrder or 0),
        tonumber(deferredPreraceSlots or 0),
        tonumber(ready or 0),
        tonumber(failed or 0),
        tonumber(unfinished or 0),
        tostring(getActiveSpawnIndex()))
    return true
end

-- ── Formation calculation ─────────────────────────────────────

--- Calculate grid/rolling/sidebyside positions relative to start→finish heading.
--- @param startNode  table  { x, y, z }
--- @param finishNode table  { x, y, z }
--- @param count      number number of positions to generate
--- @param startType  string "grid" | "rolling" | "sidebyside"
--- @return table[] positions  array of { x, y, z, heading }
calculateFormation = function(startNode, finishNode, count, startType, options)
    local basis = resolveGridBasis(startNode, finishNode, options)
    local stackHeadingDeg = basis.heading
    local slotHeadingDeg = basis.slotHeading or stackHeadingDeg
    local forwardX = basis.forwardX
    local forwardY = basis.forwardY
    local rightX = basis.rightX
    local rightY = basis.rightY
    local baseZ = (startNode and startNode.z or 0) + FINAL_SLOT_Z_OFFSET
    local playerGridPos = tonumber(options and options.playerGridPos or nil)
    local baseLateralShift = tuningValue("gridLateralShiftM", options, 0.0)

    local positions = {}
    gridLog("formation_heading source=%s vector=%s heading=%.2f startType=%s start=%s finish=%s playerGrid=%s",
        tostring(basis.headingSource),
        tostring(basis.vectorSource),
        tonumber(stackHeadingDeg or 0),
        tostring(startType or "grid"),
        tostring(startNode and startNode.name or "?"),
        tostring(finishNode and finishNode.name or "?"),
        tostring(playerGridPos))

    local function offsetPosition(longitudinalOffset, lateralOffset)
        local resolvedLateralOffset = (tonumber(lateralOffset) or 0.0) + baseLateralShift
        return {
            x = (startNode.x or 0) + longitudinalOffset * forwardX + resolvedLateralOffset * rightX,
            y = (startNode.y or 0) + longitudinalOffset * forwardY + resolvedLateralOffset * rightY,
            z = baseZ,
            heading = slotHeadingDeg,
            longitudinalOffset = longitudinalOffset,
            lateralOffset = resolvedLateralOffset,
        }
    end

    if startType == "sidebyside" then
        -- Single row, spread laterally
        local playerOrdinal = playerGridPos and math.max(1, math.floor(playerGridPos)) or nil
        for i = 1, count do
            local entry = options and options.field and options.field[i] or nil
            if playerOrdinal then
                local laneIndex, playerLaneIndex = getSideBySideLaneIndex(entry, i, playerOrdinal, options)
                local lateralDelta = (laneIndex - playerLaneIndex) * tuningValue("aiSideBySideSpacingM", options)
                positions[i] = offsetPosition(0.0, lateralDelta)
            else
                local lateralOffset = (i - (count + 1) / 2) * tuningValue("aiSideBySideSpacingM", options)
                positions[i] = offsetPosition(-tuningValue("aiSideBySideSetbackM", options), lateralOffset)
            end
        end
    elseif startType == "rolling" then
        -- 2-column grid, wider spacing
        local playerRow, playerCol = nil, nil
        if playerGridPos then
            playerRow, playerCol = getGridRowCol(playerGridPos)
        end
        for i = 1, count do
            local entry = options and options.field and options.field[i] or nil
            if playerRow ~= nil then
                local wholeOrdinal = getWholeGridSlotOrdinal(entry, i, playerGridPos)
                local row, col = getGridRowCol(wholeOrdinal)
                local longitudinalOffset = -(row - playerRow) * tuningValue("aiRollingRowSpacingM", options)
                local lateralOffset = (col - playerCol) * tuningValue("aiGridColOffsetM", options)
                positions[i] = offsetPosition(longitudinalOffset, lateralOffset)
            else
                local row = math.ceil(i / 2) - 1
                local col = (i % 2 == 0) and 1 or -1
                local backOffset = -(tuningValue("aiGridStartSetbackM", options) + tuningValue("aiRollingRowSpacingM", options) * row)
                local sideOffset = col * tuningValue("aiGridColOffsetM", options)
                positions[i] = offsetPosition(backOffset, sideOffset)
            end
        end
    else
        -- "grid" (default): 2-column staggered grid
        local playerRow, playerCol = nil, nil
        if playerGridPos then
            playerRow, playerCol = getGridRowCol(playerGridPos)
        end
        for i = 1, count do
            local entry = options and options.field and options.field[i] or nil
            if playerRow ~= nil then
                local wholeOrdinal = getWholeGridSlotOrdinal(entry, i, playerGridPos)
                local row, col = getGridRowCol(wholeOrdinal)
                local longitudinalOffset = -(row - playerRow) * tuningValue("aiGridRowSpacingM", options)
                local lateralOffset = (col - playerCol) * tuningValue("aiGridColOffsetM", options)
                positions[i] = offsetPosition(longitudinalOffset, lateralOffset)
            else
                local row = math.ceil(i / 2) - 1
                local col = (i % 2 == 0) and 1 or -1
                local backOffset = -(tuningValue("aiGridStartSetbackM", options) + tuningValue("aiGridRowSpacingM", options) * row)
                local sideOffset = col * tuningValue("aiGridColOffsetM", options)
                positions[i] = offsetPosition(backOffset, sideOffset)
            end
        end
    end

    return positions
end

local function clonePositionWithZLift(pos, zLift)
    if type(pos) ~= "table" then
        return nil
    end
    return {
        x = pos.x,
        y = pos.y,
        z = (pos.z or 0) + (zLift or 0),
        heading = pos.heading,
        longitudinalOffset = pos.longitudinalOffset,
        lateralOffset = pos.lateralOffset,
        row = pos.row,
        col = pos.col,
        formationTag = pos.formationTag,
    }
end

calculateAssemblyFormation = function(startNode, finishNode, count, options, finalPositions)
    if type(finalPositions) == "table" and #finalPositions >= count then
        local positions = {}
        for i = 1, count do
            local finalPos = finalPositions[i]
            local lifted = clonePositionWithZLift(finalPos, SPAWN_Z_OFFSET + 0.35)
            if lifted then
                positions[i] = lifted
            else
                positions[i] = finalPos
            end
        end
        return positions
    end

    local basis = resolveGridBasis(startNode, finishNode, options)
    local stackHeadingDeg = basis.heading
    local slotHeadingDeg = basis.slotHeading or stackHeadingDeg
    local headingRad = math.rad(stackHeadingDeg)
    local cosH = math.cos(headingRad)
    local sinH = math.sin(headingRad)
    local originX = (startNode.x or 0) - ASSEMBLY_SETBACK * cosH - ASSEMBLY_LATERAL_SHIFT * sinH
    local originY = (startNode.y or 0) - ASSEMBLY_SETBACK * sinH + ASSEMBLY_LATERAL_SHIFT * cosH
    local originZ = (startNode.z or 0) + SPAWN_Z_OFFSET + 0.35
    local positions = {}

    for i = 1, count do
        local row = math.ceil(i / 2) - 1
        local col = (i % 2 == 0) and 1 or -1
        local backOffset = -(ASSEMBLY_ROW_SPACING * row)
        local sideOffset = col * ASSEMBLY_COL_OFFSET
        local px = originX + backOffset * cosH - sideOffset * sinH
        local py = originY + backOffset * sinH + sideOffset * cosH
        positions[i] = {
            x = px, y = py, z = originZ,
            heading = slotHeadingDeg,
            longitudinalOffset = backOffset,
        }
    end

    return positions
end

-- ── Spawn helpers ─────────────────────────────────────────────

--- Create a WorldTransform from position + heading.
local function makeTransform(pos, headingDeg)
    local transform = WorldTransform.new()
    WorldTransform.SetPosition(transform,
        Vector4.new(pos.x or 0, pos.y or 0, pos.z or 0, 1.0))
    local quat = GetSingleton('EulerAngles'):ToQuat(
        EulerAngles.new(0.0, 0.0, headingDeg or 0.0))
    WorldTransform.SetOrientation(transform, quat)
    return transform
end

local function resolveEntityTemplatePath(entPath)
    return normalizeTemplatePathValue(entPath)
end

local function newDynamicEntitySpec()
    local spec = nil
    pcall(function()
        if DynamicEntitySpec and DynamicEntitySpec.new then
            spec = DynamicEntitySpec.new()
        else
            spec = NewObject("DynamicEntitySpec")
        end
    end)
    return spec
end

local function isValidTweakRecord(recordKey)
    if type(recordKey) ~= "string" or recordKey == "" then
        return false
    end
    local record = nil
    pcall(function()
        record = TweakDB:GetRecord(TweakDBID.new(recordKey))
    end)
    return record ~= nil
end

local function buildDynamicEntitySpec(spawnKey, pos, headingDeg, appearance)
    if type(pos) ~= "table" then
        return nil, nil, nil
    end

    local spec = newDynamicEntitySpec()
    if not spec then
        return nil, nil, nil
    end

    local resolvedKey = nil
    local mode = nil
    if isValidTweakRecord(spawnKey) then
        local recordID = nil
        pcall(function()
            recordID = TweakDBID.new(spawnKey)
        end)
        if not recordID then
            return nil, nil, nil
        end
        spec.recordID = recordID
        resolvedKey = spawnKey
        mode = "record"
    else
        local templatePath = resolveEntityTemplatePath(spawnKey)
        if type(templatePath) ~= "string" or templatePath == "" or not string.match(templatePath, "%.ent$") then
            return nil, nil, nil
        end
        spec.templatePath = templatePath
        resolvedKey = templatePath
        mode = "template"
    end

    if type(appearance) == "string" and appearance ~= "" then
        spec.appearanceName = appearance
    end

    spec.position = Vector4.new(pos.x or 0, pos.y or 0, pos.z or 0, 1.0)
    spec.orientation = GetSingleton('EulerAngles'):ToQuat(EulerAngles.new(0.0, 0.0, headingDeg or pos.heading or 0.0))
    spec.alwaysSpawned = true
    spec.spawnInView = true
    spec.active = true

    return spec, mode, resolvedKey
end

local function createDynamicEntity(spawnKey, pos, headingDeg, appearance)
    local entitySystem = nil
    pcall(function()
        entitySystem = Game.GetDynamicEntitySystem()
    end)
    if not entitySystem then
        return nil, "dynamic_entity_system_missing", nil
    end

    local spec, mode, resolvedKey = buildDynamicEntitySpec(spawnKey, pos, headingDeg, appearance)
    if not spec then
        return nil, "dynamic_entity_spec_invalid", nil
    end

    local entityID = nil
    pcall(function()
        entityID = entitySystem:CreateEntity(spec)
    end)

    if entityID then
        return entityID, mode or "dynamic", resolvedKey
    end
    return nil, "dynamic_create_failed", resolvedKey
end

extractEntityID = function(entityOrId)
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

--- Look up the entity template path for a TweakDB vehicle record.
getVehicleEntPath = function(recordID)
    local lookupKey = recordID
    if type(recordID) == "table" then
        lookupKey = recordID.id or recordID.record or recordID.vehicleRecord
    end
    lookupKey = lookupKey and tostring(lookupKey) or nil
    if not lookupKey or lookupKey == "" then
        gridLog("vehicle_template_lookup_failed record=%s", tostring(lookupKey))
        return nil
    end
    local cachedPath = _vehicleTemplatePathCache[lookupKey]
    if cachedPath then
        return cachedPath
    end

    local mappedPath = nil
    pcall(function()
        mappedPath = VehiclePool.getVehicleEntityTemplate(recordID)
    end)
    mappedPath = normalizeTemplatePathValue(mappedPath)
    if mappedPath then
        _vehicleTemplatePathCache[lookupKey] = mappedPath
        return mappedPath
    end

    local path = getTemplatePathFromFlat(lookupKey, "entityTemplatePath")
    local source = path and "flat_entityTemplatePath" or nil
    if not path then
        path = getTemplatePathFromFlat(lookupKey, "entityTemplate")
        if path then source = "flat_entityTemplate" end
    end
    if not path then
        gridLog("vehicle_template_lookup_failed record=%s", tostring(lookupKey))
        return nil
    end
    if source and source ~= "record_method" then
        gridLog(
            "vehicle_template_lookup_fallback record=%s source=%s",
            tostring(lookupKey),
            tostring(source))
    end
    _vehicleTemplatePathCache[lookupKey] = path
    return path
end

--- Look up the entity template path for a TweakDB character record.
getNPCEntPath = function(recordID)
    local mappedPath = nil
    pcall(function()
        mappedPath = VehiclePool.getNPCEntityTemplate(recordID)
    end)
    mappedPath = normalizeTemplatePathValue(mappedPath)
    if mappedPath then
        return mappedPath
    end

    local lookupKey = nil
    pcall(function()
        lookupKey = VehiclePool.getNPCSpawnKey(recordID)
    end)
    if not lookupKey then
        lookupKey = recordID
        if type(recordID) == "table" then
            lookupKey = recordID.record or recordID.legacyRecord or recordID.id
        end
    end
    lookupKey = lookupKey and tostring(lookupKey) or nil
    if not lookupKey or lookupKey == "" then
        gridLog("npc_template_lookup_failed record=%s", tostring(VehiclePool.describeNPC(recordID)))
        return nil
    end
    local cachedPath = _npcTemplatePathCache[lookupKey]
    if cachedPath then
        return cachedPath
    end
    local path = getTemplatePathFromFlat(lookupKey, "entityTemplatePath")
    local source = path and "flat_entityTemplatePath" or nil
    if not path then
        path = getTemplatePathFromFlat(lookupKey, "entityTemplate")
        if path then source = "flat_entityTemplate" end
    end
    if not path then
        gridLog("npc_template_lookup_failed record=%s", tostring(VehiclePool.describeNPC(recordID)))
        return nil
    end
    if source and source ~= "record_method" then
        gridLog(
            "npc_template_lookup_fallback record=%s source=%s path=%s",
            tostring(VehiclePool.describeNPC(recordID)),
            tostring(source),
            tostring(path))
    end
    _npcTemplatePathCache[lookupKey] = path
    return path
end

--- Spawn a vehicle entity at the given transform.
--- Returns EntityID, backend label, resolved key.
local function spawnVehicleEntity(vehicleRecord, entPath, pos, headingDeg, appearance)
    local entityID = nil
    local recordKey = vehicleRecord
    if type(vehicleRecord) == "table" then
        recordKey = vehicleRecord.id or vehicleRecord.record or vehicleRecord.vehicleRecord
    end
    local spawnPath = resolveEntityTemplatePath(entPath)
    gridLog(
        "spawnVehicleEntity: begin record=%s path=%s appearance=%s pos=%s heading=%.2f",
        tostring(recordKey),
        tostring(spawnPath),
        tostring(appearance or ''),
        safePositionSummary(pos),
        tonumber(headingDeg or (pos and pos.heading or 0) or 0))
    if (type(recordKey) ~= "string" or recordKey == "") and (not spawnPath or type(spawnPath) ~= "string" or spawnPath == "") then
        gridLog("slot_spawn_fail slot=%s reason=vehicle_spawn_key_invalid record=%s path=%s", "?", tostring(recordKey), tostring(spawnPath))
        return nil
    end

    local backend = nil
    local resolvedKey = nil
    entityID, backend, resolvedKey = createDynamicEntity(
        isValidTweakRecord(recordKey) and recordKey or spawnPath,
        pos,
        headingDeg,
        appearance)

    if not entityID and isValidTweakRecord(recordKey) and spawnPath then
        gridLog("spawnVehicleEntity: dynamic_record_failed record=%s fallback=template path=%s", tostring(recordKey), tostring(spawnPath))
        entityID, backend, resolvedKey = createDynamicEntity(
            spawnPath,
            pos,
            headingDeg,
            appearance)
    end

    gridLog(
        "spawnVehicleEntity: returned entityID=%s backend=%s key=%s pos=%s heading=%.2f",
        tostring(entityID),
        tostring(backend),
        tostring(resolvedKey),
        safePositionSummary(pos),
        tonumber(headingDeg or (pos and pos.heading or 0) or 0))
    return entityID, backend, resolvedKey
end

--- Spawn an NPC entity at the given transform.
local function spawnNPCEntity(npcRecord, entPath, pos, headingDeg, driver)
    local spawnPath = resolveEntityTemplatePath(entPath)
    if not spawnPath or type(spawnPath) ~= "string" or spawnPath == "" then
        return nil
    end

    local recordKey = nil
    pcall(function()
        recordKey = VehiclePool.getNPCSpawnKey(npcRecord, driver)
    end)
    if not recordKey then
        recordKey = npcRecord
        if type(npcRecord) == "table" then
            recordKey = npcRecord.record or npcRecord.legacyRecord or npcRecord.id
        end
    end

    gridLog(
        "spawnNPCEntity: begin npc=%s path=%s pos=%s heading=%.2f",
        tostring(VehiclePool.describeNPC(npcRecord)),
        tostring(spawnPath),
        safePositionSummary(pos),
        tonumber(headingDeg or (pos and pos.heading or 0) or 0))

    local entityID = nil
    local backend = nil
    local resolvedKey = nil
    entityID, backend, resolvedKey = createDynamicEntity(
        isValidTweakRecord(recordKey) and recordKey or spawnPath,
        pos,
        headingDeg,
        nil)
    if not entityID and isValidTweakRecord(recordKey) and spawnPath then
        gridLog(
            "npc_spawn_record_failed record=%s fallback=template path=%s",
            tostring(recordKey),
            tostring(spawnPath))
        entityID, backend, resolvedKey = createDynamicEntity(
            spawnPath,
            pos,
            headingDeg,
            nil)
    end
    if not entityID then
        gridLog(
            "npc_spawn_fail record=%s path=%s backend=%s key=%s",
            tostring(recordKey),
            tostring(spawnPath),
            tostring(backend),
            tostring(resolvedKey))
    else
        gridLog(
            "spawnNPCEntity: returned entityID=%s backend=%s key=%s pos=%s heading=%.2f",
            tostring(entityID),
            tostring(backend),
            tostring(resolvedKey),
            safePositionSummary(pos),
            tonumber(headingDeg or (pos and pos.heading or 0) or 0))
    end
    return entityID, backend, resolvedKey
end

local function teleportEntityToSlot(entity, pos, headingDeg, zLift)
    if not entity or not pos then return false end
    local ok = false
    pcall(function()
        local v4 = Vector4.new(
            pos.x or 0,
            pos.y or 0,
            (pos.z or 0) + (zLift or 0),
            1.0)
        local rot = EulerAngles.new(0, 0, headingDeg or pos.heading or 0)
        Game.GetTeleportationFacility():Teleport(entity, v4, rot)
        ok = true
    end)
    return ok
end

local function hasOperationalDriver(slot)
    return type(slot) == "table" and slot.vehEntity ~= nil and (slot.npcEntity ~= nil or slot.driverlessLaunch == true)
end

local function ensureSlotRuntimeState(slot)
    if type(slot) ~= "table" then
        return nil
    end

    local repaired = false
    if slot.timer == nil then
        slot.timer = 0
        repaired = true
    end
    if slot.spawnDelay == nil then
        slot.spawnDelay = 0
        repaired = true
    end
    if slot.driveTimer == nil then
        slot.driveTimer = 0
        repaired = true
    end
    if slot.stallTimer == nil then
        slot.stallTimer = 0
        repaired = true
    end
    if slot.settleTimer == nil then
        slot.settleTimer = 0
        repaired = true
    end
    if slot.settleHoldTimer == nil then
        slot.settleHoldTimer = 0
        repaired = true
    end
    if slot.launchGraceTimer == nil then
        slot.launchGraceTimer = 0
        repaired = true
    end
    if slot.mountTimer == nil then
        slot.mountTimer = 0
        repaired = true
    end

    if repaired and slot.runtimeStateRepairLogged ~= true then
        slot.runtimeStateRepairLogged = true
        gridLog(
            "slot=%s runtime_state_repaired phase=%s",
            tostring(getSlotIndex(slot)),
            tostring(slot.phase or "nil"))
    end

    return slot
end

local function canUseDriverlessPreraceFallback(slot)
    if type(slot) ~= "table" or not slot.vehEntity or not slot.position then
        return false
    end
    local context = tostring(_grid and _grid.context or "")
    return string.find(context, "^queued_grid_prerace") ~= nil
end

local function placeDriverlessPreraceFallback(slot, reason)
    if not canUseDriverlessPreraceFallback(slot) then
        gridLog(
            "slot_safety_driverless_skip slot=%s reason=context_not_allowed",
            tostring(getSlotIndex(slot)))
        return false
    end

    gridLog(
        "slot_safety_driverless_begin slot=%s reason=%s pos=%s",
        tostring(getSlotIndex(slot)),
        tostring(reason),
        safePositionSummary(slot and slot.position))

    local finalSafetyOk, finalSafety = SlotSafety.guardedValidateSlotPlacementSafety(
        slot,
        slot.position,
        slot.heading,
        "final_driverless",
        {
            expectedZ = slot.position and slot.position.z or nil,
            centerDeltaMax = SlotSafety.SLOT_FINAL_Z_DELTA_M,
            playerClearance = SlotSafety.SLOT_PLAYER_CLEARANCE_M,
            rivalClearance = SlotSafety.SLOT_RIVAL_CLEARANCE_M,
            trafficClearance = SlotSafety.SLOT_TRAFFIC_CLEARANCE_M,
            checkTraffic = true,
            skipGroundProbe = tostring(slot and slot.assemblyPlacement or "") == "node_grid",
        })
    if not finalSafetyOk then
        gridLog(
            "slot_safety_driverless_fail slot=%s reason=%s",
            tostring(getSlotIndex(slot)),
            tostring(finalSafety))
        return false
    end

    SlotSafety.applyValidatedSlotPositionZ(slot, "position", finalSafety.centerZ, FINAL_SLOT_Z_OFFSET)
    local placed = teleportEntityToSlot(slot.vehEntity, slot.position, slot.heading, GRID_PLACE_Z_LIFT)
    if not placed then
        gridLog(
            "slot_safety_driverless_fail slot=%s reason=teleport_failed pos=%s",
            tostring(getSlotIndex(slot)),
            safePositionSummary(slot and slot.position))
        return false
    end

    if slot.npcEntity then
        despawnEntity(slot.npcEntity)
    end

    slot.npcEntity = nil
    slot.npcEntityID = nil
    slot.driverlessLaunch = true
    slot.driverlessReadyReason = reason or "driverless_prerace_fallback"
    slot.failureReason = nil
    slot.livePos = nil
    slot.liveSpeed = 0
    slot.timer = 0
    slot.settleTimer = 0
    if slot.driver then
        slot.driver.launchable = true
    end

    logSlotPhaseChange(slot, "ready", "driverless_prerace_fallback")
    gridLog(
        "slot_safety_driverless_ready slot=%d reason=%s pos=%s",
        tonumber(getSlotIndex(slot) or 0),
        tostring(slot.driverlessReadyReason),
        safePositionSummary(slot and slot.position))
    return true
end

--- Try to find a spawned entity by its EntityID.
local function findEntity(entityID)
    if not entityID then
        return nil, "missing_entity_id"
    end
    local entity = nil
    local ok, err = pcall(function()
        entity = Game.FindEntityByID(entityID)
    end)
    if not ok then
        gridLog("find_entity_exception entityID=%s err=%s", tostring(entityID), tostring(err))
        return nil, "find_exception:" .. tostring(err)
    end
    if not entity then
        return nil, "not_found"
    end
    return entity, "found"
end

local function toCName(value)
    local cname = value
    pcall(function()
        if type(value) == "string" and value ~= "" and CName and CName.new then
            cname = CName.new(value)
        end
    end)
    return cname
end

local function getEntityIDHash(entityOrId)
    local entityID = extractEntityID(entityOrId)
    if not entityID then
        return nil
    end
    local hash = nil
    pcall(function()
        if entityID.hash ~= nil then
            hash = entityID.hash
        elseif entityID.GetHash then
            hash = entityID:GetHash()
        end
    end)
    return hash
end

local function entitiesMatch(left, right)
    local leftHash = getEntityIDHash(left)
    local rightHash = getEntityIDHash(right)
    return leftHash ~= nil and rightHash ~= nil and leftHash == rightHash
end

local function getVehicleDriverEntity(vehicle)
    if not vehicle then
        return nil
    end
    local driver = nil
    pcall(function()
        driver = VehicleComponent.GetDriverMounted(vehicle:GetGame(), vehicle:GetEntityID())
    end)
    if not driver then
        pcall(function()
            driver = VehicleComponent.GetDriver(vehicle:GetGame(), vehicle, vehicle:GetEntityID())
        end)
    end
    return driver
end

local function queueVehicleAIEvent(vehicle, eventName)
    if not vehicle or not eventName then
        return false
    end
    local queued = false
    pcall(function()
        local evt = nil
        pcall(function()
            evt = NewObject('AIEvent')
        end)
        if not evt then
            pcall(function()
                evt = NewObject('handle:AIEvent')
            end)
        end
        if not evt then
            return
        end
        evt.name = toCName(eventName)
        evt.timeToLive = 0.0
        vehicle:QueueEvent(evt)
        queued = true
    end)
    return queued
end

local function nudgeVehicleDriverReady(vehicle)
    return queueVehicleAIEvent(vehicle, 'DriverReady')
end

local function nudgeVehicleNoDriver(vehicle)
    return queueVehicleAIEvent(vehicle, 'NoDriver')
end

local function stringifySeatName(seatName)
    if type(seatName) == "string" and seatName ~= "" then
        return seatName
    end

    local value = nil
    pcall(function()
        if seatName and seatName.value then
            value = tostring(seatName.value)
        elseif seatName and seatName.ToString then
            value = seatName:ToString()
        end
    end)

    if not value and seatName ~= nil then
        local raw = tostring(seatName)
        if type(raw) == "string" and raw ~= "" and not raw:match("^userdata:") then
            value = raw
        end
    end

    return value
end

local function confirmMountedDriver(npc, vehicle, seatName)
    if not npc or not vehicle then
        return false, "mount_entity_missing"
    end

    -- Strategy 1: VehicleComponent driver entity query
    local actualDriver = getVehicleDriverEntity(vehicle)
    if actualDriver then
        if entitiesMatch(actualDriver, npc) then
            return true, "vehicle_driver_bound"
        end
        return false, "vehicle_driver_mismatch"
    end

    -- Strategy 2: MountingFacility filter-based query
    local expectedParentHash = getEntityIDHash(vehicle)
    local expectedSeat = stringifySeatName(seatName)
    local confirmed = false
    local reason = "mount_info_missing"

    local verifyOk, verifyErr = pcall(function()
        local facility = Game.GetMountingFacility()
        if not facility then
            reason = "mounting_facility_missing"
            return
        end

        local filter = nil
        local filterNames = {
            'gamemountingMountingInfoFilter',
            'handle:gamemountingMountingInfoFilter',
            'MountingInfoFilter',
        }
        for _, fName in ipairs(filterNames) do
            if filter then break end
            pcall(function() filter = NewObject(fName) end)
        end
        if not filter then
            pcall(function() filter = MountingInfoFilter.new() end)
        end

        if filter then
            filter.childId = npc:GetEntityID()
            local info = facility:GetMountingInfo(filter)
            if not info then
                reason = "mount_info_nil"
                return
            end

            local parentHash = getEntityIDHash(info.parentId)
            if not parentHash or parentHash == 0 then
                reason = "mount_parent_missing"
                return
            end
            if expectedParentHash and parentHash ~= expectedParentHash then
                reason = "mount_parent_mismatch"
                return
            end

            local mountedSeat = nil
            if info.slotId then
                mountedSeat = stringifySeatName(info.slotId.id)
            end
            if expectedSeat and mountedSeat then
                local mountedText = tostring(mountedSeat)
                local expectedText = tostring(expectedSeat)
                if mountedText ~= expectedText and not string.find(mountedText, expectedText, 1, true) then
                    reason = "mount_seat_mismatch:" .. tostring(mountedSeat)
                    return
                end
            end

            confirmed = true
            reason = mountedSeat and ("mount_confirmed:" .. tostring(mountedSeat)) or "mount_confirmed"
            return
        end

        reason = "mount_filter_construct_failed"
    end)
    if not verifyOk then
        reason = "mount_verify_pcall_error:" .. tostring(verifyErr or "unknown")
    end

    -- Strategy 3: NPC proximity to vehicle — if NPC is within 3m of vehicle
    -- after a mount request, the engine accepted it.
    if not confirmed then
        pcall(function()
            local npcPos = npc:GetWorldPosition()
            local vehPos = vehicle:GetWorldPosition()
            if npcPos and vehPos then
                local dx = (npcPos.x or 0) - (vehPos.x or 0)
                local dy = (npcPos.y or 0) - (vehPos.y or 0)
                local dz = (npcPos.z or 0) - (vehPos.z or 0)
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < 3.0 then
                    confirmed = true
                    reason = "mount_proximity_confirmed"
                end
            end
        end)
    end

    return confirmed, reason
end

local function mountNPCToVehicleViaAICommand(npc, vehicle, seatName)
    local ok = false
    pcall(function()
        local aiComp = npc:GetAIControllerComponent()
        if not aiComp then
            return
        end

        local seatKey = toCName(seatName)
        local cmd = NewObject('AIMountCommand')
        local mountData = MountEventData.new()
        mountData.mountParentEntityId = vehicle:GetEntityID()
        mountData.slotName = seatKey
        mountData.isInstant = true
        mountData.setEntityVisibleWhenMountFinish = true
        mountData.removePitchRollRotationOnDismount = false
        mountData.ignoreHLS = true
        mountData.mountEventOptions = NewObject('handle:gameMountEventOptions')
        if mountData.mountEventOptions then
            mountData.mountEventOptions.silentUnmount = false
            mountData.mountEventOptions.entityID = vehicle:GetEntityID()
            mountData.mountEventOptions.alive = true
            mountData.mountEventOptions.occupiedByNeutral = true
        end
        cmd.mountData = mountData
        if cmd.Copy then
            cmd = cmd:Copy()
        end

        aiComp:SendCommand(cmd)
        ok = true
    end)
    return ok, "ai_command"
end

local function mountNPCToVehicleViaEvent(npc, vehicle, seatName)
    local ok = false
    pcall(function()
        local seatKey = toCName(seatName)
        local mountData = MountEventData.new()
        mountData.slotName = seatKey
        mountData.mountParentEntityId = vehicle:GetEntityID()
        mountData.isInstant = true
        mountData.ignoreHLS = true

        local evt = NewObject('handle:MountAIEvent')
        evt.name = CName.new("Mount")
        evt.data = mountData
        npc:QueueEvent(evt)
        ok = true
    end)
    return ok, "ai_event"
end

local function mountNPCToVehicleViaFacility(npc, vehicle, seatName)
    local ok = false
    pcall(function()
        local entID = vehicle:GetEntityID()
        local seatKey = toCName(seatName)

        local data = NewObject('handle:gameMountEventData')
        data.isInstant = true
        data.slotName = seatKey
        data.mountParentEntityId = entID
        data.entryAnimName = "forcedTransition"
        data.setEntityVisibleWhenMountFinish = true
        data.removePitchRollRotationOnDismount = false
        data.ignoreHLS = true

        local slotID = NewObject('gamemountingMountingSlotId')
        slotID.id = seatKey

        local mountingInfo = NewObject('gamemountingMountingInfo')
        mountingInfo.childId = npc:GetEntityID()
        mountingInfo.parentId = entID
        mountingInfo.slotId = slotID

        local mountEvent = NewObject('handle:gamemountingMountingRequest')
        mountEvent.lowLevelMountingInfo = mountingInfo
        mountEvent.mountData = data

        Game.GetMountingFacility():Mount(mountEvent)
        ok = true
    end)
    return ok, "mounting_facility"
end

local function requestMountBackend(npc, vehicle, seatName, backendName)
    if backendName == "ai_command" then
        return mountNPCToVehicleViaAICommand(npc, vehicle, seatName)
    end
    if backendName == "ai_event" then
        return mountNPCToVehicleViaEvent(npc, vehicle, seatName)
    end
    if backendName == "mounting_facility" then
        return mountNPCToVehicleViaFacility(npc, vehicle, seatName)
    end
    return false, "unknown_backend"
end

--- Mount an NPC into a vehicle's driver seat.
local function mountNPCToVehicle(npc, vehicle)
    if not npc or not vehicle then
        return false, "missing_entity"
    end

    local seatName = "seat_front_left"
    -- Teleport NPC to vehicle position so engine doesn't reject mount due to distance
    pcall(function()
        local vehiclePos = vehicle:GetWorldPosition()
        if vehiclePos then
            Game.GetTeleportationFacility():Teleport(npc, vehiclePos, EulerAngles.new(0, 0, 0))
        end
    end)
    -- mounting_facility first (lowest-level, most direct); then AI backends as fallbacks
    local backends = { "mounting_facility", "ai_command", "ai_event" }
    for _, backendName in ipairs(backends) do
        local ok, backend = requestMountBackend(npc, vehicle, seatName, backendName)
        if ok then
            nudgeVehicleDriverReady(vehicle)
            return true, backend
        end
    end
    return false, "all_mount_backends_failed"
end

--- Determine which AI drive mode to use for a driver.
--- Aggressive personality + bounty drivers chase the player.
--- Others use autonomous road-following pathfinding.
pickDriveMode = function(driver, raceContext)
    local ctx = normalizeRaceContext(raceContext)
    local personality = driver.personality or ""
    local isBounty    = isBountyDriver(driver)
    local isRival     = driver and ((driver.rivalScore or 0) > 0 or driver.isRival)
    local personalityLower = string.lower(tostring(personality or ""))
    local aggression = clamp(getDriverStatValue(driver, "aggression", driver and driver.aggression or 0.5), 0.0, 1.0)
    local racecraft = clamp(getDriverStatValue(driver, "racecraft", 0.5), 0.0, 1.0)
    local playerBias = clamp(getDriverStatValue(driver, "player_bias", 0.0), 0.0, 1.0)
    local riskTolerance = clamp(getDriverStatValue(driver, "risk_tolerance", 0.5), 0.0, 1.0)

    if ctx.raceActive then
        return "autonomous"
    end

    if string.find(personalityLower, "aggressive", 1, true)
        or string.find(personalityLower, "closer", 1, true)
        or string.find(personalityLower, "dirty", 1, true)
        or string.find(personalityLower, "risk", 1, true)
        or string.find(personalityLower, "crash", 1, true)
        or isBounty or isRival then
        return "chase"
    end
    if string.find(personalityLower, "street smart", 1, true)
        or string.find(personalityLower, "ice cold", 1, true)
        or string.find(personalityLower, "clean", 1, true)
        or string.find(personalityLower, "steady", 1, true) then
        return "follow"
    end
    return "autonomous"
end

--- Get the player entity for chase/follow targets.
local function getPlayerEntity()
    local entity = nil
    pcall(function()
        entity = Game.GetPlayer()
    end)
    return entity
end

--- Get a vehicle entity's current world position.
local function getEntityPosition(entity)
    if not entity then return nil end
    local pos = nil
    pcall(function()
        local wp = entity:GetWorldPosition()
        if wp then
            pos = { x = wp.x, y = wp.y, z = wp.z }
        end
    end)
    return pos
end

--- Get a vehicle entity's current speed (m/s).
local function getEntitySpeed(entity)
    if not entity then return 0 end
    local speed = 0
    pcall(function()
        -- Try to get speed from the vehicle component
        local veh = entity
        if veh.GetCurrentSpeed then
            speed = math.abs(veh:GetCurrentSpeed())
        end
    end)
    return speed
end

local function cloneAICommand(cmd)
    if not cmd then
        return nil
    end
    local cloned = cmd
    pcall(function()
        if cmd.Copy then
            cloned = cmd:Copy()
        end
    end)
    return cloned
end

local function appendCommandBackend(slot, backend)
    if type(slot) ~= "table" or not backend or backend == "" then
        return
    end

    if slot.lastCommandBackend and slot.lastCommandBackend ~= "" then
        slot.lastCommandBackend = slot.lastCommandBackend .. "+" .. backend
    else
        slot.lastCommandBackend = backend
    end
end

local function dispatchVehicleCommand(slot, cmd)
    if not slot or not cmd then
        return false
    end

    local vehicle = slot.vehEntity
    local npc = slot.npcEntity
    local isDrvless = slot.driverlessLaunch == true
    local sent = false
    slot.lastCommandBackend = nil

    -- Driven vehicles can accept an NPC-routed event, but the vehicle AI
    -- component still needs the init command for speed changes to stick.
    if vehicle and not isDrvless then
        pcall(function()
            local evt = NewObject("handle:AINPCCommandEvent")
            evt.command = cloneAICommand(cmd)
            vehicle:QueueEvent(evt)
            sent = true
            appendCommandBackend(slot, "vehicle_ainpc_event")
        end)
    end

    if vehicle then
        pcall(function()
            local evt = NewObject("handle:AICommandEvent")
            evt.command = cloneAICommand(cmd)
            vehicle:QueueEvent(evt)
            sent = true
            appendCommandBackend(slot, "vehicle_ai_event")
        end)
    end

    if vehicle then
        pcall(function()
            local aiComp = vehicle:GetAIComponent()
            if aiComp and aiComp.SetInitCmd then
                aiComp:SetInitCmd(cloneAICommand(cmd))
                sent = true
                appendCommandBackend(slot, "vehicle_init_cmd")
            end
        end)
    end

    if npc and not sent then
        pcall(function()
            local aiComp = npc:GetAIControllerComponent()
            if aiComp then
                aiComp:SendCommand(cloneAICommand(cmd))
                sent = true
                appendCommandBackend(slot, "npc_controller")
            end
        end)
    end

    return sent
end

--- Issue an autonomous road-following drive command.
--- Uses AIVehicleDriveToPointAutonomousCommand for real pathfinding.
local function issueAutonomousCommand(slot, targetPos, profile, options)
    local sent = false
    pcall(function()
        local cmd = NewObject('handle:AIVehicleDriveToPointAutonomousCommand')
        local commandMaxSpeed = (options and options.maxSpeed) or (profile and profile.maxSpeed) or 25.0
        local commandMinSpeed = (options and options.minSpeed)
            or (profile and math.min(profile.minSpeed or 15.0, profile.maxSpeed or 25.0))
            or 15.0
        local commandTargetDistance = (options and options.targetDistance)
            or (profile and profile.targetDistance)
            or tuningValue("aiAutonomousTargetDistanceM", _queuedFormation)
        local commandForcedStartSpeed = (options and options.forcedStartSpeed)
            or (profile and profile.forcedStartSpeed)
            or 0.0
        local commandDriveIndefinitely = options and options.driveIndefinitely == true or false

        cmd.targetPosition = Vector3.new(
            targetPos.x or 0, targetPos.y or 0, targetPos.z or 0)
        cmd.maxSpeed              = commandMaxSpeed
        cmd.minSpeed              = commandMinSpeed
        cmd.clearTrafficOnPath    = options and options.clearTrafficOnPath ~= false or true
        cmd.minimumDistanceToTarget = commandTargetDistance
        cmd.forcedStartSpeed      = commandForcedStartSpeed
        cmd.driveDownTheRoadIndefinitely = commandDriveIndefinitely
        cmd.useKinematic          = false
        cmd.needDriver            = not (slot and slot.driverlessLaunch)
        pcall(function()
            cmd.boostDrivingStats = profile and profile.boostDrivingStats or false
        end)
        sent = dispatchVehicleCommand(slot, cmd)
        if type(slot) == "table" then
            slot.lastCommandedMaxSpeed = commandMaxSpeed
            slot.lastCommandedMinSpeed = commandMinSpeed
            slot.lastCommandedForcedStartSpeed = commandForcedStartSpeed
            slot.lastCommandedTargetDistance = commandTargetDistance
            slot.lastCommandedDriveIndefinitely = commandDriveIndefinitely
            slot.driveCommandSeq = (slot.driveCommandSeq or 0) + 1

            local launchRelease = options and options.launchRelease == true
            local postLaunch = options and options.postLaunch == true
            local raceActive = slot.raceContext and slot.raceContext.raceActive == true
            local fullRaceCommand = raceActive and not launchRelease
            local shouldLog = slot.driveCommandSeq <= 2
                or (fullRaceCommand and slot._loggedFullRaceDriveCommand ~= true)
                or postLaunch
                or (not sent and slot._loggedDriveCommandFailure ~= true)
            if fullRaceCommand then
                slot._loggedFullRaceDriveCommand = true
            end
            if not sent then
                slot._loggedDriveCommandFailure = true
            end
            if shouldLog then
                print(string.format(
                    "[NCM/AIVehicles] drive_cmd slot=%s sent=%s backend=%s race=%s launch=%s postLaunch=%s avgTarget=%.1f base=%.1f straightFloor=%.1f max=%.1f min=%.1f forced=%.1f dist=%.1f indef=%s",
                    tostring(getSlotIndex(slot)),
                    tostring(sent == true),
                    tostring(slot.lastCommandBackend or "?"),
                    tostring(raceActive == true),
                    tostring(launchRelease == true),
                    tostring(postLaunch == true),
                    tonumber(profile and profile.projectedAverageSpeed) or 0.0,
                    tonumber(profile and profile.baseSpeedTarget) or 0.0,
                    tonumber(profile and profile.straightSpeedFloor) or 0.0,
                    tonumber(commandMaxSpeed) or 0.0,
                    tonumber(commandMinSpeed) or 0.0,
                    tonumber(commandForcedStartSpeed) or 0.0,
                    tonumber(commandTargetDistance) or 0.0,
                    tostring(commandDriveIndefinitely == true)))
            end
        end
    end)
    return sent
end

local function resetRollingStartState(reason)
    _rollingStart.active = false
    _rollingStart.warmupActive = false
    _rollingStart.control = nil
    _rollingStart.leaderProgress = 0.0
    _rollingStart.commandTimer = 0.0
    _rollingStart.warmupTimer = 0.0
    _rollingStart.lastReason = reason
end

local function buildRollingBasis(control)
    local startNode = control and control.startNode or (_queuedFormation and _queuedFormation.startNode) or nil
    local finishNode = control and control.finishNode or (_queuedFormation and _queuedFormation.finishNode) or nil
    if not startNode or not finishNode then
        return nil
    end

    local basis = resolveGridBasis(startNode, finishNode, {
        gridHeading = control and control.gridHeading or nil,
        gridForward = control and control.gridForward or nil,
    })

    return {
        startNode = startNode,
        finishNode = finishNode,
        forwardX = basis.forwardX,
        forwardY = basis.forwardY,
        rightX = basis.rightX,
        rightY = basis.rightY,
        heading = basis.heading,
        baseZ = (startNode.z or 0) + SPAWN_Z_OFFSET,
        lateralShift = tuningValue("gridLateralShiftM", control, 0.0),
    }
end

local function buildRollingTargetPosition(slot, control)
    local basis = buildRollingBasis(control)
    if not basis then
        return nil
    end

    local profile = slot and slot.theatreProfile or nil
    local gridRow = tonumber(slot and slot.gridRow or 0) or 0
    local gridCol = tonumber(slot and slot.gridCol or 0) or 0
    local leaderProgress = clamp(tonumber(control and control.leaderProgress or 0.0) or 0.0, 0.0, tonumber(control and control.zoneLength or 100.0) or 100.0)
    local creepMeters = profile and profile.creepMeters or 0.0
    local discipline = profile and profile.formationDiscipline or 0.5
    local weaveMeters = profile and profile.weaveMeters or 0.0
    local elapsed = tonumber(control and control.elapsed or 0.0) or 0.0
    local weavePhase = (elapsed * 1.7) + (gridRow * 0.6) + (gridCol > 0 and 0.8 or -0.8)
    local weaveOffset = math.sin(weavePhase) * weaveMeters * clamp(1.0 - discipline * 0.55, 0.25, 1.0)
    local longitudinal = math.max(6.0, leaderProgress - (gridRow * tuningValue("aiRollingRowSpacingM", control)) + creepMeters)
    local lateral = (gridCol * tuningValue("aiGridColOffsetM", control)) + weaveOffset + (basis.lateralShift or 0.0)

    return {
        x = (basis.startNode.x or 0) + longitudinal * basis.forwardX + lateral * basis.rightX,
        y = (basis.startNode.y or 0) + longitudinal * basis.forwardY + lateral * basis.rightY,
        z = basis.baseZ,
        heading = basis.heading,
    }
end

local function issueRollingZoneCommand(slot, control)
    if not hasOperationalDriver(slot) then
        return false
    end

    local target = buildRollingTargetPosition(slot, control)
    if not target then
        return false
    end

    local profile = slot.driveProfile or buildDriveProfile(slot.driver or {}, slot.driveMode, slot.raceContext)
    slot.driveProfile = profile
    local theatreProfile = slot.theatreProfile or {}
    local paceTarget = clamp((tonumber(control and control.targetPaceMps or 16.0) or 16.0) + (theatreProfile.rollingSpeedBias or 0.0), 10.0, 24.0)
    local maxSpeed = paceTarget + 1.25
    local minSpeed = math.max(6.0, paceTarget - 1.25)

    local sent = issueAutonomousCommand(slot, target, profile, {
        maxSpeed = maxSpeed,
        minSpeed = math.min(minSpeed, maxSpeed),
        forcedStartSpeed = math.max(5.0, paceTarget * 0.60),
        targetDistance = 4.0,
        clearTrafficOnPath = true,
        driveIndefinitely = false,
    })

    if sent then
        slot.driveTimer = 0
        slot.stallTimer = 0
        slot.rollingTarget = target
        slot.liveTargetSpeed = paceTarget
    end
    return sent
end

local function buildLaunchReleaseProfile(profile)
    if type(profile) ~= "table" then
        return profile
    end

    local launchProfile = {}
    for key, value in pairs(profile) do
        launchProfile[key] = value
    end

    local cappedMax = math.min(
        tonumber(profile.maxSpeed) or tuningValue("aiLaunchReleaseMaxSpeedCapMps", _queuedFormation),
        tuningValue("aiLaunchReleaseMaxSpeedCapMps", _queuedFormation))
    local cappedMin = math.min(
        tonumber(profile.minSpeed) or tuningValue("aiLaunchReleaseMinSpeedCapMps", _queuedFormation),
        cappedMax,
        tuningValue("aiLaunchReleaseMinSpeedCapMps", _queuedFormation))

    launchProfile.maxSpeed = cappedMax
    launchProfile.minSpeed = cappedMin
    launchProfile.forcedStartSpeed = math.min(
        tonumber(profile.forcedStartSpeed) or 0.0,
        tuningValue("aiLaunchReleaseForcedSpeedCapMps", _queuedFormation))
    launchProfile.targetDistance = math.max(
        4.0,
        math.min(tonumber(profile.targetDistance) or tuningValue("aiLaunchReleaseTargetDistanceM", _queuedFormation),
            tuningValue("aiLaunchReleaseTargetDistanceM", _queuedFormation)))
    launchProfile.boostDrivingStats = false
    return launchProfile
end

local function markLaunchGrace(slot)
    if type(slot) ~= "table" then return end
    slot.launchGraceTimer = tuningValue("aiLaunchGraceTimeS", slot and slot.raceContext or _queuedFormation)
    slot.needsPostLaunchRaceCommand = true
end

local function tickRollingWarmup(dt)
    if not _rollingStart.warmupActive or _launched then
        return
    end

    _rollingStart.warmupTimer = (_rollingStart.warmupTimer or 0.0) + (dt or 0.0)
    if (_rollingStart.warmupTimer or 0.0) < tuningValue("aiRollingWarmupIntervalS", _rollingStart.control or _queuedFormation) then
        return
    end
    _rollingStart.warmupTimer = 0.0

    for _, slot in ipairs(_slots) do
        if slot.phase == "ready" and slot.vehEntity then
            local profile = slot.theatreProfile or {}
            local blips = tonumber(profile.revBlips or 1) or 1
            for _ = 1, blips do
                nudgeVehicleDriverReady(slot.vehEntity)
            end
            gridLog("slot=%s rolling_warmup label=%s blips=%d",
                tostring(getSlotIndex(slot)),
                tostring(profile.label or "balanced"),
                tonumber(blips or 0))
        end
    end
end

--- Issue a chase command — aggressive pursuit of the player.
--- Used for bounty drivers and aggressive personalities.
local function issueChaseCommand(slot, playerEntity, profile)
    local sent = false
    pcall(function()
        local cmd = NewObject('handle:AIVehicleChaseCommand')
        cmd.target           = playerEntity
        cmd.distanceMin      = profile and profile.chaseDistanceMin or tuningValue("aiChaseDistanceMinM", _queuedFormation)
        cmd.distanceMax      = profile and profile.chaseDistanceMax or tuningValue("aiChaseDistanceMaxM", _queuedFormation)
        cmd.forcedStartSpeed = profile and profile.forcedStartSpeed or 0.0
        cmd.aggressiveRamming = false
        cmd.ignoreChaseVehiclesLimit = true
        cmd.boostDrivingStats = profile and profile.boostDrivingStats or false
        cmd.useKinematic      = false
        cmd.needDriver        = not (slot and slot.driverlessLaunch)
        sent = dispatchVehicleCommand(slot, cmd)
    end)
    return sent
end

--- Issue a follow command — traffic-aware road pursuit.
--- Used as fallback when chase fails or for moderate drivers.
local function issueFollowCommand(slot, playerEntity, profile)
    local sent = false
    pcall(function()
        local cmd = NewObject('handle:AIVehicleFollowCommand')
        cmd.target         = playerEntity
        cmd.secureTimeOut  = 300.0
        cmd.distanceMin    = profile and profile.followDistanceMin or tuningValue("aiFollowDistanceMinM", _queuedFormation)
        cmd.distanceMax    = profile and profile.followDistanceMax or tuningValue("aiFollowDistanceMaxM", _queuedFormation)
        cmd.stopWhenTargetReached = false
        cmd.useTraffic     = profile and profile.useTraffic or false
        cmd.useKinematic   = false
        cmd.needDriver     = not (slot and slot.driverlessLaunch)
        sent = dispatchVehicleCommand(slot, cmd)
    end)
    return sent
end

--- Issue the appropriate drive command based on drive mode.
local function issueDriveCommand(slot, options)
    if not hasOperationalDriver(slot) then return false end

    local mode = slot.driveMode or "autonomous"
    local driver = slot.driver or {}
    local profile = slot.driveProfile or buildDriveProfile(driver, mode, slot.raceContext)
    slot.driveProfile = profile
    local launchRelease = type(options) == "table" and options.launchRelease == true
    local commandProfile = launchRelease and buildLaunchReleaseProfile(profile) or profile

    -- Determine target: current waypoint if set, else finish line
    local target = _finishPos
    local targetOptions = nil
    if slot.waypoints and slot.waypointIndex then
        local wp = slot.waypoints[slot.waypointIndex]
        if wp then target = wp end
    elseif target then
        targetOptions = {
            targetDistance = math.max(8.0, math.min(commandProfile.targetDistance or tuningValue("aiAutonomousTargetDistanceM", _queuedFormation), 18.0)),
        }
    end
    if launchRelease then
        targetOptions = targetOptions or {}
        targetOptions.maxSpeed = commandProfile.maxSpeed
        targetOptions.minSpeed = math.min(commandProfile.minSpeed or commandProfile.maxSpeed, commandProfile.maxSpeed)
        targetOptions.forcedStartSpeed = commandProfile.forcedStartSpeed
        targetOptions.targetDistance = commandProfile.targetDistance
        targetOptions.launchRelease = true
    end
    if slot.raceContext and slot.raceContext.raceActive then
        targetOptions = targetOptions or {}
        targetOptions.maxSpeed = math.max(targetOptions.maxSpeed or 0.0, commandProfile.maxSpeed)
        targetOptions.minSpeed = math.max(targetOptions.minSpeed or 0.0, math.min(commandProfile.minSpeed or commandProfile.maxSpeed, commandProfile.maxSpeed))
        targetOptions.forcedStartSpeed = math.max(targetOptions.forcedStartSpeed or 0.0, commandProfile.forcedStartSpeed or 0.0)
        targetOptions.targetDistance = math.max(targetOptions.targetDistance or 0.0, commandProfile.targetDistance or 12.0)
        -- Race targets already point beyond the finish line via buildFinishRunoffTarget().
        -- Do not switch into indefinite road cruising here: that mode behaves like
        -- traffic autopilot and can ignore the configured race speed floor.
        targetOptions.driveIndefinitely = false
    end
    if not target then
        return false
    end

    local sent = false

    if mode == "chase" then
        local player = getPlayerEntity()
        if player then
            if issueChaseCommand(slot, player, commandProfile) then
                sent = true
            else
                sent = issueAutonomousCommand(slot, target, commandProfile, targetOptions)
            end
        else
            sent = issueAutonomousCommand(slot, target, commandProfile, targetOptions)
        end
    elseif mode == "follow" then
        local player = getPlayerEntity()
        if player and issueFollowCommand(slot, player, commandProfile) then
            sent = true
        else
            sent = issueAutonomousCommand(slot, target, commandProfile, targetOptions)
        end
    else
        sent = issueAutonomousCommand(slot, target, commandProfile, targetOptions)
    end

    if sent then
        slot.driveTimer = 0
        slot.stallTimer = 0
        if launchRelease then
            markLaunchGrace(slot)
        end
    end
    return sent
end

-- ── Public API ────────────────────────────────────────────────

function AIVehicles.init()
    _slots      = {}
    _active     = false
    _finishPos  = nil
    _launched   = false
    _spawnTimer = 0
    _raceTimer  = 0
    _queuedFormation = nil
    resetWorldState("init")
    _grid       = {
        phase = "idle",
        nextSlotIndex = 1,
        totalSlots = 0,
        lastReason = nil,
        firstSpawnArmDelay = 0,
        firstSpawnArmTicks = 0,
        postArmSettleTime = 0,
        postArmSettleTicks = 0,
        slotsPrepared = false,
        spawnArmed = false,
        spawnOrder = nil,
        spawnCursor = 1,
        postArmWaitBucket = nil,
        postArmWaitTicks = nil,
        lastTickLogAt = nil,
        lastSummaryKey = nil,
        runId = nil,
        context = nil,
        assemblyMode = nil,
        launchOnReady = false,
        criticalFailureReason = nil,
        abortRequested = false,
    }

    -- Check API availability at init and log clearly
    local hasSpawner = (type(exEntitySpawner) == "table" or type(exEntitySpawner) == "userdata")
    local hasMount   = false
    pcall(function()
        hasMount = GameInstance.GetMountingFacility ~= nil
    end)
    if hasSpawner then
        print("[NCM/AIVehicles] exEntitySpawner: available")
    else
        print("[NCM/AIVehicles] WARNING: exEntitySpawner not found — AI cars will NOT be visible. Races will still work as ghost races.")
    end
    if hasMount then
        print("[NCM/AIVehicles] MountingFacility: available")
    else
        print("[NCM/AIVehicles] WARNING: MountingFacility not found — NPCs cannot mount vehicles.")
    end
end

function AIVehicles.onSessionStart()
    resetWorldState("session_start")
    gridLog("world_session_start")
end

function AIVehicles.noteWorldDisruption(reason)
    markWorldDisruption(reason or "external")
end

clearQueuedFormation = function()
    _queuedFormation = nil
end

--- Begin spawning AI vehicles in formation.
--- Call during PRERACE after field is built.
--- @param field     table[]  array of raceEntry objects from Racing
--- @param startNode table    { x, y, z }
--- @param finishNode table   { x, y, z }
--- @param startType string   "grid" | "rolling" | "sidebyside"
--- @param options table|nil { assemblyMode = "assembly"|"direct", launchOnReady = bool, context = string|nil, gridHeading = number|nil }
function AIVehicles.spawnFormation(field, startNode, finishNode, startType, options)
    AIVehicles.despawnAll()  -- clean up any previous race
    local count = math.min(#field, maxAiCars(options))
    local runId = nextGridRunId(options and options.runId or nil)
    markWorldDisruption("spawn_formation_queued")
    gridLog("----- grid_session_begin startType=%s field=%d visible=%d -----",
        tostring(startType),
        tonumber(#field or 0),
        tonumber(count))

    _queuedFormation = {
        field = field,
        startNode = startNode,
        finishNode = finishNode,
        raceType = options and options.raceType or nil,
        startType = startType,
        assemblyMode = options and options.assemblyMode or "assembly",
        gridHeading = options and options.gridHeading or nil,
        gridForward = options and options.gridForward or nil,
        playerGridPos = options and options.playerGridPos or nil,
        launchOnReady = options and options.launchOnReady == true,
        context = options and options.context or "default",
        trafficPrepared = options and options.trafficPrepared == true,
        trafficClearRadius = options and options.trafficClearRadius or nil,
        trafficVerticalTolerance = options and options.trafficVerticalTolerance or nil,
        stageSource = options and options.stageSource or nil,
        routeId = options and options.routeId or nil,
        routeMode = options and options.routeMode or nil,
        assemblyPlacement = options and options.assemblyPlacement or "node_grid",
        dragStrip = options and options.dragStrip or nil,
        raceContext = options and options.raceContext or nil,
        rootProfileSettings = options and options.rootProfileSettings or nil,
        runId = runId,
    }

    _finishPos = buildFinishRunoffTarget(startNode, finishNode, _queuedFormation.raceType)
        or { x = finishNode.x, y = finishNode.y, z = finishNode.z }
    _launched  = false
    _spawnTimer = 0
    _grid = {
        phase = "preparing",
        nextSlotIndex = 1,
        totalSlots = count,
        lastReason = nil,
        firstSpawnArmDelay = FIRST_SPAWN_ARM_DELAY,
        firstSpawnArmTicks = FIRST_SPAWN_ARM_TICKS,
        postArmSettleTime = POST_ARM_SETTLE_TIME,
        postArmSettleTicks = POST_ARM_SETTLE_TICKS,
        slotsPrepared = false,
        spawnArmed = false,
        spawnOrder = {},
        spawnCursor = 1,
        postArmWaitBucket = nil,
        postArmWaitTicks = nil,
        lastTickLogAt = nil,
        lastSummaryKey = nil,
        runId = runId,
        context = _queuedFormation.context,
        assemblyMode = _queuedFormation.assemblyMode,
        launchOnReady = _queuedFormation.launchOnReady,
        solverSummary = nil,
        criticalFailureReason = nil,
        lastSlotFailureReason = nil,
        abortRequested = false,
    }
    gridLog(
        "session_marker context=%s assembly=%s launchOnReady=%s startType=%s start=(%.1f, %.1f, %.1f) finish=(%.1f, %.1f, %.1f)",
        tostring(_queuedFormation.context),
        tostring(_queuedFormation.assemblyMode),
        tostring(_queuedFormation.launchOnReady),
        tostring(startType),
        tonumber(startNode.x or 0),
        tonumber(startNode.y or 0),
        tonumber(startNode.z or 0),
        tonumber(finishNode.x or 0),
        tonumber(finishNode.y or 0),
        tonumber(finishNode.z or 0))
    -- Actual slot order is rebuilt after preflight so safer rear-row/stable
    -- slots go first and thin faction placeholders can be deferred.
    setGridPhase("preparing", "queued_slots")
    gridLog(
        "spawn_arm delay=%.3f ticks=%d postArmSettle=%.3f postArmTicks=%d first_live_slot=%s",
        tonumber(_grid.firstSpawnArmDelay or 0),
        tonumber(_grid.firstSpawnArmTicks or 0),
        tonumber(_grid.postArmSettleTime or 0),
        tonumber(_grid.postArmSettleTicks or 0),
        tostring(getActiveSpawnIndex()))

    print(string.format(
        "[NCM/AIVehicles] spawnFormation: run=%s field=%d visible=%d startType=%s assembly=%s placement=%s launchOnReady=%s context=%s start=(%.1f, %.1f, %.1f) finish=(%.1f, %.1f, %.1f)",
        tostring(runId),
        #field, count, tostring(startType),
        tostring(_queuedFormation.assemblyMode),
        tostring(_queuedFormation.assemblyPlacement),
        tostring(_queuedFormation.launchOnReady),
        tostring(_queuedFormation.context),
        startNode.x or 0, startNode.y or 0, startNode.z or 0,
        finishNode.x or 0, finishNode.y or 0, finishNode.z or 0))
    gridLog("slots_queued total=%d", tonumber(count or 0))

    _active = true
    setGridPhase("arming", "await_world_stability")
    print(string.format("[NCM/AIVehicles] Queued %d AI vehicles for %s start.", count, startType))
end

--- Per-frame update: handles async spawn→materialize→mount pipeline
--- and stall detection / re-commanding for driving AI.
--- Call from Racing.update().
function AIVehicles.update(dt)
    updateWorldState(dt)
    tickRollingWarmup(dt)
    if not _active then return end
    if _grid.abortRequested or _grid.phase == "failed" then return end

    if not _grid.spawnArmed then
        local gateReason = getSpawnGateReason()
        if gateReason then
            setGridPhase("arming", gateReason)
            if _world.lastSpawnGateReason ~= gateReason then
                _world.lastSpawnGateReason = gateReason
                gridLog(
                    "spawn_arm_wait reason=%s sessionAge=%.3f quiet=%.3f quietTicks=%d playerTicks=%d vehicleTicks=%d",
                    tostring(gateReason),
                    tonumber(_world.sessionAge or 0),
                    tonumber(_world.quietTime or 0),
                    tonumber(_world.quietTicks or 0),
                    tonumber(_world.playerStableTicks or 0),
                    tonumber(_world.vehicleStableTicks or 0))
            end
            return
        end
        _grid.spawnArmed = true
        _spawnTimer = 0
        _world.lastSpawnGateReason = nil
        setGridPhase("spawning", "world_armed")
        gridLog(
            "spawn_arm_cleared sessionAge=%.3f quiet=%.3f quietTicks=%d playerTicks=%d vehicleTicks=%d",
            tonumber(_world.sessionAge or 0),
            tonumber(_world.quietTime or 0),
            tonumber(_world.quietTicks or 0),
            tonumber(_world.playerStableTicks or 0),
            tonumber(_world.vehicleStableTicks or 0))
    end

    _spawnTimer = _spawnTimer + dt
    local activeSpawnIndexBefore = getActiveSpawnIndex()
    if shouldLogUpdateTick(_spawnTimer or 0) then
        gridLog(
            "update_tick dt=%.3f spawnTimer=%.3f activeSpawnIndex=%s nextSlot=%s cursor=%s phase=%s armed=%s",
            tonumber(dt or 0),
            tonumber(_spawnTimer or 0),
            tostring(activeSpawnIndexBefore),
            tostring(_grid.nextSlotIndex),
            tostring(_grid.spawnCursor),
            tostring(_grid.phase),
            tostring(_grid.spawnArmed))
    end
    if (_grid.firstSpawnArmTicks or 0) > 0 then
        _grid.firstSpawnArmTicks = math.max(0, (_grid.firstSpawnArmTicks or 0) - 1)
        if (_grid.firstSpawnArmTicks or 0) == 0 then
            gridLog(
                "spawn_arm ticks_cleared spawnTimer=%.3f",
                tonumber(_spawnTimer or 0))
        end
    end
    if (_grid.postArmSettleTime or 0) > 0 then
        _grid.postArmSettleTime = math.max(0, (_grid.postArmSettleTime or 0) - dt)
    end
    if (_grid.postArmSettleTicks or 0) > 0 then
        _grid.postArmSettleTicks = math.max(0, (_grid.postArmSettleTicks or 0) - 1)
    end
    if (_grid.postArmSettleTime or 0) > 0 or (_grid.postArmSettleTicks or 0) > 0 then
        local remaining = math.max((_grid.postArmSettleTime or 0), 0)
        local bucket = math.floor((remaining * 10.0) + 0.0001)
        local ticksLeft = tonumber(_grid.postArmSettleTicks or 0)
        if _grid.postArmWaitBucket ~= bucket or _grid.postArmWaitTicks ~= ticksLeft then
            _grid.postArmWaitBucket = bucket
            _grid.postArmWaitTicks = ticksLeft
            gridLog(
                "post_arm_wait spawnTimer=%.3f settle=%.3f ticks=%d",
                tonumber(_spawnTimer or 0),
                tonumber(remaining),
                ticksLeft)
        end
        setGridPhase("spawning", "post_arm_grace")
        return
    elseif _grid.postArmWaitBucket ~= nil or _grid.postArmWaitTicks ~= nil then
        _grid.postArmWaitBucket = nil
        _grid.postArmWaitTicks = nil
        gridLog(
            "post_arm_cleared spawnTimer=%.3f",
            tonumber(_spawnTimer or 0))
    end
    -- Hold if player wandered too far from the grid; recheck at most once every 2s.
    do
        local _tooFarCheckBucket = math.floor((_spawnTimer or 0) * 0.5)
        if _tooFarCheckBucket ~= _grid.playerTooFarCheckBucket then
            _grid.playerTooFarCheckBucket = _tooFarCheckBucket
            local _distReason = getSpawnGateReason()
            if _distReason and _distReason:find("player_too_far", 1, true) then
                if not _grid.playerTooFarHolding then
                    gridLog("spawn_hold_player_too_far reason=%s", tostring(_distReason))
                end
                _grid.playerTooFarHolding = true
            else
                if _grid.playerTooFarHolding then
                    _grid.playerTooFarHolding = nil
                    gridLog("spawn_hold_player_too_far_cleared spawnTimer=%.3f", tonumber(_spawnTimer or 0))
                end
            end
        end
        if _grid.playerTooFarHolding then
            return
        end
    end
    if not _grid.slotsPrepared then
        if not prepareQueuedSlots() then
            setGridPhase("failed", _grid.criticalFailureReason or "slots_prepare_failed")
            return
        end
    end
    if _launched then
        _raceTimer = _raceTimer + dt
    elseif _spawnTimer > math.max(TOTAL_STAGE_TIMEOUT, #_slots * 3.5) then   -- large (formula) grids get proportionally longer to stage
        local timedOut = 0
        for _, slot in ipairs(_slots) do
            if slot.phase == "pending" or
               slot.phase == "spawning_veh" or
               slot.phase == "spawning_npc" or
               slot.phase == "mounting" or
               slot.phase == "assembling_settle" or
               slot.phase == "positioning" then
                failSlot(slot, "global_stage_timeout")
                timedOut = timedOut + 1
            end
        end
        if timedOut > 0 then
            print(string.format(
                "[NCM/AIVehicles] Staging timeout after %.1fs - skipped %d unfinished rivals.",
                _spawnTimer, timedOut))
        end
    end

    local spawningInProgress = false

    for i, slot in ipairs(_slots) do

        ensureSlotRuntimeState(slot)
        slot.timer = slot.timer + dt

        -- Phase: pending → wait for stagger delay, then spawn vehicle
        if slot.phase == "pending" then
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            -- Hold if player has wandered too far; piggyback on the post-arm grid-level
            -- flag (refreshed at most once every 2s) so we don't call getSpawnGateReason
            -- per slot per frame.
            if _grid.playerTooFarHolding then
                if not slot.playerTooFarHoldLogged then
                    gridLog("slot_hold_player_too_far slot=%d", slotIndex)
                    slot.playerTooFarHoldLogged = true
                end
                spawningInProgress = true
                goto continue
            elseif slot.playerTooFarHoldLogged then
                slot.playerTooFarHoldLogged = nil
                gridLog("slot_hold_player_too_far_cleared slot=%d spawnTimer=%.3f", slotIndex, tonumber(_spawnTimer or 0))
            end
            local activeSpawnIndex = getActiveSpawnIndex()
            local firstSpawnBlocked = (activeSpawnIndex == i) and (slotIndex == (_grid.spawnOrder and _grid.spawnOrder[1] or 1)) and (
                (_spawnTimer < (_grid.firstSpawnArmDelay or 0)) or
                ((_grid.firstSpawnArmTicks or 0) > 0))
            if activeSpawnIndex == i and firstSpawnBlocked then
                spawningInProgress = true
                local remaining = math.max(((_grid.firstSpawnArmDelay or 0) - (_spawnTimer or 0)), 0)
                local bucket = math.floor((remaining * 10.0) + 0.0001)
                local ticksLeft = tonumber(_grid.firstSpawnArmTicks or 0)
                if slot.firstSpawnWaitBucket ~= bucket or slot.firstSpawnWaitTicks ~= ticksLeft then
                    slot.firstSpawnWaitBucket = bucket
                    slot.firstSpawnWaitTicks = ticksLeft
                    gridLog(
                        "slot=%d pending_gate_wait first_spawn_arm spawnTimer=%.3f delay=%.3f ticks=%d",
                        slotIndex,
                        tonumber(_spawnTimer or 0),
                        tonumber(_grid.firstSpawnArmDelay or 0),
                        ticksLeft)
                end
            elseif i == activeSpawnIndex and _spawnTimer >= slot.spawnDelay then
                spawningInProgress = true
                slot.firstSpawnWaitBucket = nil
                slot.firstSpawnWaitTicks = nil
                gridLog("slot_spawn_begin slot=%d driver=%s spawnTimer=%.3f spawnDelay=%.3f rank=%s risk=%s",
                    tonumber(slotIndex or i or 0),
                    tostring(slot.driver and (slot.driver.driverId or slot.driver.id) or "?"),
                    tonumber(_spawnTimer or 0),
                    tonumber(slot.spawnDelay or 0),
                    tostring(slot.spawnRank or "?"),
                    tostring(slot.spawnRiskLabel or "unknown"))
                gridLog(
                    "slot=%d pending_gate_open spawnTimer=%.3f spawnDelay=%.3f nextSlot=%s",
                    slotIndex,
                    tonumber(_spawnTimer or 0),
                    tonumber(slot.spawnDelay or 0),
                    tostring(activeSpawnIndex))
                gridLog("slot=%d pending_gate_state_enter", slotIndex)
                gridLog("slot=%d pending_gate_state cachedVehPathPresent=%s phase=%s",
                    slotIndex,
                    tostring(slot.vehEntPath ~= nil),
                    tostring(slot.phase))
                local preflightOk, preflightReason = validateSlotPreflight(slot, "pending")
                if not preflightOk then
                    failSlot(slot, preflightReason)
                    advanceSpawnCursor(i)
                else
                gridLog("slot=%d pending_gate_before_entpath", slotIndex)
                local entPath = slot.vehEntPath or getVehicleEntPath(slot.vehRecord)
                gridLog("slot=%d pending_gate_after_entpath entPath=%s",
                    slotIndex,
                    tostring(entPath))
                if entPath then
                    gridLog("slot=%d vehicle_spawn path=%s",
                        slot.driver and (slot.driver.slotIndex or "?") or "?",
                        tostring(entPath))
                    gridLog("slot=%d pending_gate_after_path_log", slotIndex)
                    local pos = slot.spawnPosition or slot.position
                    local spawnStage = (slot.spawnMode == "assembly") and "assembly" or "spawn"
                    local assemblyOnNodeGrid = slot.spawnMode == "assembly" and tostring(slot.assemblyPlacement or "") == "node_grid"
                    local safetyOk, safetyResult = SlotSafety.guardedValidateSlotPlacementSafety(
                        slot,
                        pos,
                        slot.heading,
                        spawnStage,
                        {
                            expectedZ = (slot.spawnMode == "assembly" and slot.assemblyPosition and slot.assemblyPosition.z)
                                or (slot.position and slot.position.z)
                                or (pos and pos.z),
                            centerDeltaMax = (slot.spawnMode == "assembly" and not assemblyOnNodeGrid) and SlotSafety.SLOT_ASSEMBLY_Z_DELTA_M or SlotSafety.SLOT_FINAL_Z_DELTA_M,
                            playerClearance = (slot.spawnMode == "assembly" and not assemblyOnNodeGrid) and SlotSafety.SLOT_ASSEMBLY_PLAYER_CLEARANCE_M or SlotSafety.SLOT_PLAYER_CLEARANCE_M,
                            rivalClearance = SlotSafety.SLOT_RIVAL_CLEARANCE_M,
                            trafficClearance = SlotSafety.SLOT_TRAFFIC_CLEARANCE_M,
                            checkTraffic = true,
                            skipGroundProbe = assemblyOnNodeGrid,
                        })
                    if not safetyOk then
                        SlotSafety.handleUnsafeSlot(slot, i, safetyResult, spawnStage)
                    else
                    if slot.spawnMode == "assembly" then
                        SlotSafety.applyValidatedSlotPositionZ(slot, "assemblyPosition", safetyResult.centerZ, SPAWN_Z_OFFSET + 0.35)
                        SlotSafety.applyValidatedSlotPositionZ(slot, "spawnPosition", safetyResult.centerZ, SPAWN_Z_OFFSET + 0.35)
                    else
                        SlotSafety.applyValidatedSlotPositionZ(slot, "position", safetyResult.centerZ, FINAL_SLOT_Z_OFFSET)
                        SlotSafety.applyValidatedSlotPositionZ(slot, "spawnPosition", safetyResult.centerZ, SPAWN_Z_OFFSET)
                    end
                    pos = slot.spawnPosition or slot.position
                    gridLog(
                        "slot=%d pending_gate_transform_inputs posPresent=%s x=%.2f y=%.2f z=%.2f heading=%.2f",
                        slotIndex,
                        tostring(pos ~= nil),
                        pos and (pos.x or 0) or 0,
                        pos and (pos.y or 0) or 0,
                        pos and (pos.z or 0) or 0,
                        slot.heading or 0)
                    gridLog("slot=%d pending_gate_before_transform", slotIndex)
                    local spawnCallOk, spawnCallErr = pcall(function()
                    local transform = makeTransform(pos, slot.heading)
                    gridLog("slot=%d pending_gate_after_transform", slotIndex)
                    gridLog(
                        "slot=%d vehicle_spawn transform pos=(%.2f, %.2f, %.2f) hdg=%.2f",
                        slot.driver and (slot.driver.slotIndex or "?") or 0,
                        pos and (pos.x or 0) or 0,
                        pos and (pos.y or 0) or 0,
                        pos and (pos.z or 0) or 0,
                        slot.heading or 0)
                    gridLog(
                        "slot_spawn_call slot=%d vehicle=%s pos=(%.2f, %.2f, %.2f) hdg=%.2f",
                        tonumber(slotIndex or 0),
                        tostring(slot.vehRecord),
                        pos and (pos.x or 0) or 0,
                        pos and (pos.y or 0) or 0,
                        pos and (pos.z or 0) or 0,
                        slot.heading or 0)
                    slot.vehicleSpawnAttemptCount = (tonumber(slot.vehicleSpawnAttemptCount or 0) or 0) + 1
                    slot.vehicleMaterializeRetryCount = 0
                    slot.vehicleFindMissCount = 0
                    slot.lastVehicleSpawnPosition = SlotSafety.clonePositionTable(pos) or pos
                    slot.lastVehicleSpawnHeading = slot.heading
                    slot.lastVehicleSpawnEntPath = entPath
                    slot.lastVehicleSpawnAppearance = slot.appearance
                    slot.lastVehicleSpawnRecord = slot.vehRecord
                    slot.lastVehicleSpawnStage = spawnStage
                    gridLog(
                        "slot_spawn_request slot=%d attempt=%s stage=%s vehicle=%s path=%s pos=%s hdg=%.2f",
                        tonumber(slotIndex or 0),
                        tostring(slot.vehicleSpawnAttemptCount),
                        tostring(spawnStage),
                        tostring(slot.vehRecord),
                        tostring(entPath),
                        safePositionSummary(pos),
                        tonumber(slot.heading or 0))
                    gridLog("slot=%d pending_gate_before_spawn_call", slotIndex)
                    slot.vehEntityID, slot.vehicleSpawnBackend, slot.vehicleSpawnResolvedKey =
                        spawnVehicleEntity(slot.vehRecord, entPath, pos, slot.heading, slot.appearance)
                    gridLog(
                        "slot=%d pending_gate_after_spawn_call entityID=%s backend=%s key=%s attempt=%s",
                        slotIndex,
                        tostring(slot.vehEntityID),
                        tostring(slot.vehicleSpawnBackend),
                        tostring(slot.vehicleSpawnResolvedKey),
                        tostring(slot.vehicleSpawnAttemptCount))
                    end) -- end pcall
                    if not spawnCallOk then
                        gridLog(
                            "slot_spawn_exception slot=%d err=%s",
                            tonumber(slotIndex or 0),
                            tostring(spawnCallErr))
                        slot.vehEntityID = nil
                    end
                    if slot.vehEntityID then
                        gridLog("slot_vehicle_entity_created slot=%d entityId=%s backend=%s key=%s attempt=%s",
                            tonumber(slotIndex or 0),
                            tostring(slot.vehEntityID),
                            tostring(slot.vehicleSpawnBackend),
                            tostring(slot.vehicleSpawnResolvedKey),
                            tostring(slot.vehicleSpawnAttemptCount))
                        logSlotPhaseChange(slot, "spawning_veh", "vehicle_spawn_requested")
                        slot.timer = 0
                        beginAsyncWait(slot, VEHICLE_LOOKUP_GRACE, MATERIALIZE_POLL_INTERVAL)
                    else
                        failSlot(slot, "vehicle_spawn_failed")
                        advanceSpawnCursor(i)
                    end
                    end
                else
                    failSlot(slot, "vehicle_template_missing")
                    advanceSpawnCursor(i)
                end
                end
            end

        -- Phase: spawning_veh → poll for vehicle materialization
        elseif slot.phase == "spawning_veh" then
            spawningInProgress = true
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            if slot.timer > (MATERIALIZE_TIMEOUT + (slot.pollGrace or 0)) then
                gridLog(
                    "slot_vehicle_materialize_timeout slot=%d timer=%.3f entityID=%s attempt=%s retries=%s misses=%s backend=%s key=%s pos=%s",
                    tonumber(slotIndex or 0),
                    tonumber(slot.timer or 0),
                    tostring(slot.vehEntityID),
                    tostring(slot.vehicleSpawnAttemptCount),
                    tostring(slot.vehicleMaterializeRetryCount),
                    tostring(slot.vehicleFindMissCount),
                    tostring(slot.vehicleSpawnBackend),
                    tostring(slot.vehicleSpawnResolvedKey),
                    safePositionSummary(slot.lastVehicleSpawnPosition or slot.spawnPosition or slot.position))
                local retryPos = SlotSafety.clonePositionTable(slot.spawnPosition or slot.lastVehicleSpawnPosition or slot.position)
                if (tonumber(slot.vehicleMaterializeRetryCount or 0) or 0) < 1 and retryPos then
                    retryPos.z = (retryPos.z or 0) + 0.35
                    slot.vehicleMaterializeRetryCount = (tonumber(slot.vehicleMaterializeRetryCount or 0) or 0) + 1
                    slot.vehicleSpawnAttemptCount = (tonumber(slot.vehicleSpawnAttemptCount or 0) or 0) + 1
                    slot.vehicleFindMissCount = 0
                    slot.spawnPosition = SlotSafety.clonePositionTable(retryPos) or retryPos
                    if slot.spawnMode == "assembly" then
                        slot.assemblyPosition = SlotSafety.clonePositionTable(retryPos) or retryPos
                    end
                    slot.lastVehicleSpawnPosition = SlotSafety.clonePositionTable(retryPos) or retryPos
                    slot.lastVehicleSpawnHeading = slot.heading
                    slot.lastVehicleSpawnEntPath = slot.lastVehicleSpawnEntPath or slot.vehEntPath
                    slot.lastVehicleSpawnRecord = slot.vehRecord
                    gridLog(
                        "slot_vehicle_materialize_retry_begin slot=%d retry=%s attempt=%s priorEntityID=%s path=%s record=%s pos=%s hdg=%.2f",
                        tonumber(slotIndex or 0),
                        tostring(slot.vehicleMaterializeRetryCount),
                        tostring(slot.vehicleSpawnAttemptCount),
                        tostring(slot.vehEntityID),
                        tostring(slot.lastVehicleSpawnEntPath),
                        tostring(slot.lastVehicleSpawnRecord),
                        safePositionSummary(retryPos),
                        tonumber(slot.lastVehicleSpawnHeading or slot.heading or 0))
                    despawnEntity(slot.vehEntityID)
                    slot.vehEntity = nil
                    slot.vehEntityID, slot.vehicleSpawnBackend, slot.vehicleSpawnResolvedKey =
                        spawnVehicleEntity(slot.vehRecord, slot.lastVehicleSpawnEntPath, retryPos, slot.lastVehicleSpawnHeading or slot.heading, slot.lastVehicleSpawnAppearance or slot.appearance)
                    gridLog(
                        "slot_vehicle_materialize_retry_result slot=%d retry=%s attempt=%s entityID=%s backend=%s key=%s pos=%s",
                        tonumber(slotIndex or 0),
                        tostring(slot.vehicleMaterializeRetryCount),
                        tostring(slot.vehicleSpawnAttemptCount),
                        tostring(slot.vehEntityID),
                        tostring(slot.vehicleSpawnBackend),
                        tostring(slot.vehicleSpawnResolvedKey),
                        safePositionSummary(retryPos))
                    if slot.vehEntityID then
                        slot.timer = 0
                        beginAsyncWait(slot, VEHICLE_LOOKUP_GRACE, MATERIALIZE_POLL_INTERVAL)
                    else
                        failSlot(slot, "vehicle_spawn_retry_failed")
                        advanceSpawnCursor(i)
                    end
                else
                    if not retryPos then
                        gridLog("slot_vehicle_materialize_retry_skip slot=%d reason=missing_retry_position", tonumber(slotIndex or 0))
                    end
                    failSlot(slot, "vehicle_materialize_timeout")
                    advanceSpawnCursor(i)
                end
            elseif shouldPollAsync(slot, slotIndex, "spawning_veh") then
                gridLog("slot=%d spawning_veh_tick timer=%.3f entityID=%s",
                    slotIndex,
                    tonumber(slot.timer or 0),
                    tostring(slot.vehEntityID))
                gridLog("slot=%d spawning_veh_before_findEntity", slotIndex)
                local veh, vehFindReason = findEntity(slot.vehEntityID)
                if not veh then
                    slot.vehicleFindMissCount = (tonumber(slot.vehicleFindMissCount or 0) or 0) + 1
                end
                gridLog("slot=%d spawning_veh_after_findEntity found=%s reason=%s misses=%s attempt=%s backend=%s key=%s",
                    slotIndex,
                    tostring(veh ~= nil),
                    tostring(vehFindReason),
                    tostring(slot.vehicleFindMissCount or 0),
                    tostring(slot.vehicleSpawnAttemptCount),
                    tostring(slot.vehicleSpawnBackend),
                    tostring(slot.vehicleSpawnResolvedKey))
                if veh then
                    gridLog("slot=%d vehicle_materialized entityID=%s attempt=%s misses=%s backend=%s key=%s",
                        slot.driver and (slot.driver.slotIndex or "?") or "?",
                        tostring(slot.vehEntityID),
                        tostring(slot.vehicleSpawnAttemptCount),
                        tostring(slot.vehicleFindMissCount or 0),
                        tostring(slot.vehicleSpawnBackend),
                        tostring(slot.vehicleSpawnResolvedKey))
                    slot.vehEntity = veh
                    -- Now spawn NPC driver at same location
                    gridLog("slot=%d spawning_veh_before_npc_entpath", slotIndex)
                    local npcEntPath = slot.npcEntPath or getNPCEntPath(slot.npcRecord)
                    gridLog("slot=%d spawning_veh_after_npc_entpath hasPath=%s path=%s",
                        slotIndex,
                        tostring(npcEntPath ~= nil),
                        tostring(npcEntPath))
                    if npcEntPath then
                        gridLog("slot=%d npc_spawn path=%s",
                            slot.driver and (slot.driver.slotIndex or "?") or "?",
                            tostring(npcEntPath))
                        gridLog("slot=%d spawning_veh_before_npc_transform", slotIndex)
                        local npcSpawnPos = slot.spawnPosition or slot.position
                        local transform = makeTransform(npcSpawnPos, slot.heading)
                        gridLog("slot=%d spawning_veh_after_npc_transform", slotIndex)
                        gridLog("slot=%d spawning_veh_before_npc_spawn", slotIndex)
                        slot.npcFindMissCount = 0
                        slot.npcEntityID, slot.npcSpawnBackend, slot.npcSpawnResolvedKey =
                            spawnNPCEntity(slot.npcRecord, npcEntPath, npcSpawnPos, slot.heading, slot.driver)
                        gridLog("slot=%d spawning_veh_after_npc_spawn entityID=%s backend=%s key=%s",
                            slotIndex,
                            tostring(slot.npcEntityID),
                            tostring(slot.npcSpawnBackend),
                            tostring(slot.npcSpawnResolvedKey))
                        if slot.npcEntityID then
                            gridLog("slot_driver_entity_created slot=%d entityId=%s npc=%s backend=%s key=%s",
                                tonumber(slotIndex or 0),
                                tostring(slot.npcEntityID),
                                tostring(VehiclePool.describeNPC(slot.npcRecord)),
                                tostring(slot.npcSpawnBackend),
                                tostring(slot.npcSpawnResolvedKey))
                            logSlotPhaseChange(slot, "spawning_npc", "npc_spawn_requested")
                            slot.timer = 0
                            beginAsyncWait(slot, NPC_LOOKUP_GRACE, MATERIALIZE_POLL_INTERVAL)
                        else
                            gridLog("slot_spawn_fail slot=%d reason=npc_spawn_failed npc=%s",
                                tonumber(slotIndex or 0),
                                tostring(VehiclePool.describeNPC(slot.npcRecord)))
                            -- NPC spawn failed: despawn orphaned vehicle
                            failSlot(slot, "npc_spawn_failed")
                            advanceSpawnCursor(i)
                        end
                    else
                        gridLog("slot_spawn_fail slot=%d reason=npc_template_missing npc=%s",
                            tonumber(slotIndex or 0),
                            tostring(VehiclePool.describeNPC(slot.npcRecord)))
                        -- No NPC ent path: despawn orphaned vehicle
                        failSlot(slot, "npc_template_missing")
                        advanceSpawnCursor(i)
                    end
                end
            end

        -- Phase: spawning_npc → poll for NPC materialization
        elseif slot.phase == "spawning_npc" then
            spawningInProgress = true
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            if slot.timer > (MATERIALIZE_TIMEOUT + (slot.pollGrace or 0)) then
                gridLog(
                    "slot_npc_materialize_timeout slot=%d timer=%.3f entityID=%s misses=%s backend=%s key=%s",
                    tonumber(slotIndex or 0),
                    tonumber(slot.timer or 0),
                    tostring(slot.npcEntityID),
                    tostring(slot.npcFindMissCount),
                    tostring(slot.npcSpawnBackend),
                    tostring(slot.npcSpawnResolvedKey))
                -- NPC timed out: despawn orphaned vehicle
                failSlot(slot, "npc_materialize_timeout")
                advanceSpawnCursor(i)
            elseif shouldPollAsync(slot, slotIndex, "spawning_npc") then
                gridLog("slot=%d spawning_npc_before_findEntity", slotIndex)
                local npc, npcFindReason = findEntity(slot.npcEntityID)
                if not npc then
                    slot.npcFindMissCount = (tonumber(slot.npcFindMissCount or 0) or 0) + 1
                end
                gridLog("slot=%d spawning_npc_after_findEntity found=%s reason=%s misses=%s backend=%s key=%s",
                    slotIndex,
                    tostring(npc ~= nil),
                    tostring(npcFindReason),
                    tostring(slot.npcFindMissCount or 0),
                    tostring(slot.npcSpawnBackend),
                    tostring(slot.npcSpawnResolvedKey))
                if npc then
                    gridLog("slot=%d npc_materialized entityID=%s misses=%s backend=%s key=%s",
                        slot.driver and (slot.driver.slotIndex or "?") or "?",
                        tostring(slot.npcEntityID),
                        tostring(slot.npcFindMissCount or 0),
                        tostring(slot.npcSpawnBackend),
                        tostring(slot.npcSpawnResolvedKey))
                    slot.npcEntity = npc
                    -- Settle: let the engine finish component init before mount
                    if not slot.npcSettleStart then
                        slot.npcSettleStart = slot.timer
                        gridLog("slot=%d npc_settle_begin settleStart=%.3f", slotIndex, slot.npcSettleStart)
                    end
                    local settleAge = (slot.timer or 0) - (slot.npcSettleStart or slot.timer)
                    if settleAge < NPC_SETTLE_BEFORE_MOUNT then
                        -- still settling – will be re-polled next tick
                    else
                        -- Submit mount request; transition to mounting for engine confirmation
                        gridLog("slot=%d mount_before_request npc=%s vehicle=%s settleAge=%.3f",
                            slotIndex,
                            tostring(slot.npcEntityID),
                            tostring(slot.vehEntityID),
                            settleAge)
                        local mounted, mountBackend = mountNPCToVehicle(npc, slot.vehEntity)
                        gridLog("slot=%d mount_after_request ok=%s backend=%s",
                            slotIndex,
                            tostring(mounted == true),
                            tostring(mountBackend))
                        if mounted then
                            logSlotPhaseChange(slot, "mounting", "mount_requested")
                            slot.timer = 0
                            slot.mountTimer  = 0
                            slot.mountSeatName = "seat_front_left"
                            slot.mountBackend = mountBackend
                            slot.mountRetryStage = 0
                            slot.mountVerifyReason = "mount_requested:" .. tostring(mountBackend or "unknown")
                            beginAsyncWait(slot, MOUNT_VERIFY_GRACE, MOUNT_VERIFY_INTERVAL)
                            gridLog("slot=%d mount_requested", slot.driver and (slot.driver.slotIndex or "?") or "?")
                        else
                            -- Mount request itself failed (pcall threw): despawn both
                            failSlot(slot, "mount_failed")
                            advanceSpawnCursor(i)
                        end
                    end
                end
            end

        -- Phase: mounting → wait for engine to confirm NPC is seated
        elseif slot.phase == "mounting" then
            spawningInProgress = true
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            slot.mountTimer = (slot.mountTimer or 0) + dt
            if slot.mountTimer > (MOUNT_VERIFY_TIMEOUT + (slot.pollGrace or 0)) then
                print("[NCM/AIV] Mount unconfirmed for driver " .. tostring(slot.driver and slot.driver.id) .. " — despawning.")
                local fallbackReason = "mount_unconfirmed:" .. tostring(slot.mountVerifyReason or "timeout")
                if not placeDriverlessPreraceFallback(slot, fallbackReason) then
                    failSlot(slot, fallbackReason)
                end
                advanceSpawnCursor(i)
            elseif shouldPollAsync(slot, slotIndex, "mounting") then
                local npc = slot.npcEntity
                local veh = slot.vehEntity
                local confirmed, verifyReason = confirmMountedDriver(npc, veh, slot.mountSeatName or "seat_front_left")
                if slot.mountVerifyReason ~= verifyReason then
                    slot.mountVerifyReason = verifyReason
                    gridLog("slot=%d mount_verify reason=%s", slotIndex, tostring(verifyReason))
                end

                if confirmed then
                    gridLog("slot_bind_driver_ok slot=%d npc=%s vehicle=%s",
                        tonumber(slotIndex or 0),
                        tostring(slot.npcEntityID),
                        tostring(slot.vehEntityID))
                    logSlotPhaseChange(slot, "assembling_settle", "mount_confirmed")
                    slot.timer = 0
                    slot.settleTimer = 0
                    beginAsyncWait(slot, ASSEMBLY_SETTLE_GRACE, SETTLE_SAMPLE_INTERVAL)
                    gridLog("slot=%d mounted_confirmed -> assembling_settle", slot.driver and (slot.driver.slotIndex or "?") or "?")
                else
                    local nextBackend = nil
                    local retryReason = nil
                    if (slot.mountRetryStage or 0) == 0 and slot.mountTimer >= 0.55 then
                        -- Primary was mounting_facility; retry with ai_command
                        nextBackend = "ai_command"
                        retryReason = "mount_retry_stage1"
                        slot.mountRetryStage = 1
                    elseif (slot.mountRetryStage or 0) == 1 and slot.mountTimer >= 1.10 then
                        nextBackend = "ai_event"
                        retryReason = "mount_retry_stage2"
                        slot.mountRetryStage = 2
                    elseif (slot.mountRetryStage or 0) == 2 and slot.mountTimer >= 1.60 then
                        -- Re-try mounting_facility after a nudge cycle
                        nudgeVehicleNoDriver(veh)
                        gridLog("slot=%d mount_retry no_driver_nudge", slotIndex)
                        slot.mountRetryStage = 3
                    elseif (slot.mountRetryStage or 0) == 3 and slot.mountTimer >= 2.00 then
                        nextBackend = "mounting_facility"
                        retryReason = "mount_retry_stage3_facility"
                        nudgeVehicleDriverReady(veh)
                        gridLog("slot=%d mount_retry driver_ready_nudge", slotIndex)
                        slot.mountRetryStage = 4
                    elseif (slot.mountRetryStage or 0) == 4 and slot.mountTimer >= 2.50 then
                        nextBackend = "ai_command"
                        retryReason = "mount_retry_stage4_final"
                        slot.mountRetryStage = 5
                    end

                    if nextBackend then
                        local retried, backend = requestMountBackend(npc, veh, slot.mountSeatName or "seat_front_left", nextBackend)
                        if retried then
                            slot.mountBackend = backend
                            slot.mountVerifyReason = retryReason .. ":" .. tostring(backend)
                            nudgeVehicleDriverReady(veh)
                            gridLog("slot=%d mount_retry backend=%s reason=%s", slotIndex, tostring(backend), tostring(retryReason))
                        end
                    end
                end
            end

        elseif slot.phase == "assembling_settle" then
            spawningInProgress = true
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            if slot.timer > (MATERIALIZE_TIMEOUT + SLOT_SETTLE_TIME + 2.0 + (slot.pollGrace or 0)) then
                failSlot(slot, "assembly_settle_timeout")
                advanceSpawnCursor(i)
            elseif shouldPollAsync(slot, slotIndex, "assembling_settle") then
                local speed = getEntitySpeed(slot.vehEntity)
                local sampleDt = slot.pollInterval or dt or 0
                slot.livePos = getEntityPosition(slot.vehEntity)
                slot.liveSpeed = speed
                if speed <= SLOT_SETTLE_SPEED then
                    slot.settleTimer = (slot.settleTimer or 0) + sampleDt
                else
                    slot.settleTimer = 0
                end

                if (slot.settleTimer or 0) >= SLOT_SETTLE_TIME then
                    gridLog("slot=%s assembly_settled speed=%.2f -> positioning", tostring(slotIndex), speed or 0)
                    local trustSolvedNodeGrid = tostring(slot.assemblyPlacement or "") == "node_grid"
                    local finalSafetyOk, finalSafety = SlotSafety.guardedValidateSlotPlacementSafety(
                        slot,
                        slot.position,
                        slot.heading,
                        "final",
                        {
                            expectedZ = slot.position and slot.position.z or nil,
                            centerDeltaMax = SlotSafety.SLOT_FINAL_Z_DELTA_M,
                            playerClearance = SlotSafety.SLOT_PLAYER_CLEARANCE_M,
                            rivalClearance = SlotSafety.SLOT_RIVAL_CLEARANCE_M,
                            trafficClearance = SlotSafety.SLOT_TRAFFIC_CLEARANCE_M,
                            checkTraffic = true,
                            skipGroundProbe = trustSolvedNodeGrid,
                        })
                    if not finalSafetyOk then
                        SlotSafety.handleUnsafeSlot(slot, i, finalSafety, "final")
                    else
                    SlotSafety.applyValidatedSlotPositionZ(slot, "position", finalSafety.centerZ, FINAL_SLOT_Z_OFFSET)
                    local finalPos = SlotSafety.clonePositionTable(slot.position) or slot.position
                    local placed = teleportEntityToSlot(slot.vehEntity, finalPos, slot.heading, GRID_PLACE_Z_LIFT)
                    if placed then
                        slot.timer = 0
                        slot.settleTimer = 0
                        slot.livePos = nil
                        slot.liveSpeed = 0
                        logSlotPhaseChange(slot, "positioning", "assembled_and_placed")
                        beginAsyncWait(slot, GRID_POSITION_GRACE, SETTLE_SAMPLE_INTERVAL)
                    else
                        failSlot(slot, "grid_placement_failed")
                        advanceSpawnCursor(i)
                    end
                    end
                end
            end

        elseif slot.phase == "positioning" then
            spawningInProgress = true
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            if slot.timer > (MATERIALIZE_TIMEOUT + POSITION_SETTLE_TIME + 2.0 + (slot.pollGrace or 0)) then
                failSlot(slot, "grid_position_settle_timeout")
                advanceSpawnCursor(i)
            elseif shouldPollAsync(slot, slotIndex, "positioning") then
                local speed = getEntitySpeed(slot.vehEntity)
                local sampleDt = slot.pollInterval or dt or 0
                slot.livePos = getEntityPosition(slot.vehEntity)
                slot.liveSpeed = speed
                if speed <= SLOT_SETTLE_SPEED then
                    slot.settleTimer = (slot.settleTimer or 0) + sampleDt
                else
                    slot.settleTimer = 0
                end

                if (slot.settleTimer or 0) >= POSITION_SETTLE_TIME then
                    if slot.driver then slot.driver.launchable = true end
                    if slot.launchOnReady and hasOperationalDriver(slot) then
                        if issueDriveCommand(slot, { launchRelease = true }) then
                            logSlotPhaseChange(slot, "driving", "hot_join_launch")
                            _launched = true
                            gridLog("slot_spawn_ready slot=%d phase=driving speed=%.2f",
                                tonumber(slotIndex or 0),
                                speed or 0)
                            gridLog("slot=%d hot_join_launch speed=%.2f next_slot=%d",
                                slot.driver and (slot.driver.slotIndex or "?") or "?",
                                speed or 0,
                                tonumber(_grid.nextSlotIndex or -1))
                        else
                            slot.driveTimer = 0
                            logSlotPhaseChange(slot, "ready", "hot_join_launch_pending")
                            gridLog("slot=%d hot_join_launch_pending speed=%.2f", slotIndex, speed or 0)
                        end
                    else
                        logSlotPhaseChange(slot, "ready", "grid_position_settled")
                        gridLog("slot_spawn_ready slot=%d phase=ready speed=%.2f",
                            tonumber(slotIndex or 0),
                            speed or 0)
                    end
                    advanceSpawnCursor(i)
                    gridLog("slot=%d ready speed=%.2f next_slot=%d",
                        slot.driver and (slot.driver.slotIndex or "?") or "?",
                        speed or 0,
                        tonumber(_grid.nextSlotIndex or -1))
                end
            end

        elseif slot.phase == "ready" and hasOperationalDriver(slot) and (_launched or slot.launchOnReady) then
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            slot.driveTimer = (slot.driveTimer or 0) + dt
            if slot.driveTimer >= READY_LAUNCH_RETRY_INTERVAL then
                local speed = getEntitySpeed(slot.vehEntity)
                local issued = _rollingStart.active and issueRollingZoneCommand(slot, _rollingStart.control) or issueDriveCommand(slot)
                if issued then
                    logSlotPhaseChange(slot, "driving", _rollingStart.active and "rolling_ready_retry" or (slot.launchOnReady and "ready_retry_launch" or "race_launch_retry"))
                    _launched = true
                    gridLog("slot=%d ready_retry_launch speed=%.2f", slotIndex, speed or 0)
                else
                    slot.driveTimer = 0
                end
            end

        -- Phase: driving → monitor for stalls and re-command
        elseif slot.phase == "driving" and hasOperationalDriver(slot) then
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            local profile = slot.driveProfile or buildDriveProfile(slot.driver or {}, slot.driveMode, slot.raceContext)
            slot.driveProfile = profile
            slot.driveTimer = (slot.driveTimer or 0) + dt
            local wasInLaunchGrace = (slot.launchGraceTimer or 0.0) > 0.0
            slot.launchGraceTimer = math.max(0.0, (slot.launchGraceTimer or 0.0) - dt)

            -- Check vehicle speed for stall detection
            local speed = getEntitySpeed(slot.vehEntity)

            -- Cache live telemetry for standings / knockout
            slot.livePos   = getEntityPosition(slot.vehEntity)
            slot.liveSpeed = speed

            local inLaunchGrace = (slot.launchGraceTimer or 0.0) > 0.0
            if wasInLaunchGrace and not inLaunchGrace and slot.needsPostLaunchRaceCommand and not _rollingStart.active then
                slot.needsPostLaunchRaceCommand = false
                if issueDriveCommand(slot, { postLaunch = true }) then
                    gridLog("slot=%d post_launch_race_command speed=%.2f", slotIndex, speed or 0)
                else
                    slot.driveTimer = 0
                    gridLog("slot=%d post_launch_race_command_pending speed=%.2f", slotIndex, speed or 0)
                end
            end

            if not inLaunchGrace then
                if speed < (profile.stallSpeedThreshold or tuningValue("aiStallSpeedThreshMps", slot and slot.raceContext or _queuedFormation)) then
                    slot.stallTimer = (slot.stallTimer or 0) + dt
                else
                    slot.stallTimer = 0
                end
            else
                slot.stallTimer = 0
            end

            -- Re-issue command if stalled or on regular interval
            local needRecommand = false
            if not inLaunchGrace then
                if slot.stallTimer > (profile.stallTimeThreshold or tuningValue("aiStallTimeThreshS", slot and slot.raceContext or _queuedFormation)) then
                    needRecommand = true
                elseif slot.driveTimer > (profile.recommandInterval or tuningValue("aiRecommandIntervalS", slot and slot.raceContext or _queuedFormation)) then
                    needRecommand = true
                end
            end

            if _rollingStart.active and slot.driveTimer > tuningValue("aiRollingControlIntervalS", _rollingStart.control or _queuedFormation) then
                needRecommand = true
            end

            if needRecommand then
                local issued = _rollingStart.active and issueRollingZoneCommand(slot, _rollingStart.control) or issueDriveCommand(slot)
                if not issued then
                    slot.driveTimer = 0
                    gridLog("slot=%d drive_recommand_pending speed=%.2f", slotIndex, speed or 0)
                end
            end

        -- Phase: driving but entity world-culled → attempt recovery or mid-race respawn
        elseif slot.phase == "driving" and not hasOperationalDriver(slot) then
            local slotIndex = slot.driver and (slot.driver.slotIndex or i) or i
            slot.culledTimer = (slot.culledTimer or 0) + dt

            -- Sub-state: not yet respawning → try entity recovery first
            if not slot.respawnState then
                slot.respawnRecoverPoll = (slot.respawnRecoverPoll or 0) + dt
                if slot.respawnRecoverPoll >= RESPAWN_RECOVER_POLL then
                    slot.respawnRecoverPoll = 0
                    local veh = slot.vehEntityID and findEntity(slot.vehEntityID) or nil
                    local npc = slot.npcEntityID and findEntity(slot.npcEntityID) or nil
                    if veh then
                        slot.vehEntity = veh
                        if npc then slot.npcEntity = npc end
                        if hasOperationalDriver(slot) then
                            issueDriveCommand(slot)
                            slot.culledTimer = 0
                            slot.respawnRecoverPoll = nil
                            gridLog("slot=%d world_cull_recovered culledFor=%.2f", slotIndex, slot.culledTimer)
                            goto continue
                        end
                    end
                    -- Check respawn trigger: projected remaining time
                    local racing = MTE and MTE.Racing or nil
                    local raceTimer = racing and racing.getRaceTimer and racing.getRaceTimer() or 0
                    local raceState = racing and racing.getState and racing.getState() or nil
                    local racingStates = racing and racing.STATE or nil
                    local inRace = raceState and racingStates and raceState == racingStates.RACING
                    if inRace and raceTimer > 0 then
                        local field = racing.getField and racing.getField() or {}
                        local driverId = slot.driver and (slot.driver.driverId or slot.driver.id) or nil
                        local aiTime = nil
                        if driverId then
                            for _, e in ipairs(field) do
                                if (e.driverId or e.id) == driverId then
                                    aiTime = tonumber(e.aiTime)
                                    break
                                end
                            end
                        end
                        local timeToFinish = (aiTime or (raceTimer + 999)) - raceTimer
                        if timeToFinish < RESPAWN_TIME_THRESHOLD then
                            slot.respawnState = "spawning_veh"
                            slot.respawnTimer = 0
                            -- Clean up old entities via DES
                            pcall(function() despawnEntity(slot.vehEntityID) end)
                            pcall(function() despawnEntity(slot.npcEntityID) end)
                            slot.vehEntity = nil
                            slot.npcEntity = nil
                            slot.vehEntityID = nil
                            slot.npcEntityID = nil
                            -- Spawn new vehicle near the player
                            local playerPos = getPlayerWorldPosition()
                            if playerPos then
                                local angle = math.random() * 2 * math.pi
                                local spawnPos = {
                                    x = playerPos.x - (RESPAWN_SPAWN_BEHIND_M * 0.7) + math.cos(angle) * RESPAWN_LATERAL_JITTER_M,
                                    y = playerPos.y - (RESPAWN_SPAWN_BEHIND_M * 0.7) + math.sin(angle) * RESPAWN_LATERAL_JITTER_M,
                                    z = (playerPos.z or 0) + 0.35,
                                }
                                local entPath = slot.vehEntPath or getVehicleEntPath(slot.vehRecord)
                                slot.vehEntityID = spawnVehicleEntity(slot.vehRecord, entPath, spawnPos, slot.heading, slot.appearance)
                                if slot.vehEntityID then
                                    gridLog("slot=%d respawn_veh_requested entityID=%s behind=%.0fm timeToFinish=%.1f",
                                        slotIndex, tostring(slot.vehEntityID), RESPAWN_SPAWN_BEHIND_M, timeToFinish)
                                else
                                    slot.respawnState = nil
                                    gridLog("slot=%d respawn_veh_spawn_failed", slotIndex)
                                end
                            else
                                slot.respawnState = nil
                                gridLog("slot=%d respawn_no_player_pos", slotIndex)
                            end
                        end
                    end
                end

            -- Sub-state: waiting for respawned vehicle to materialize
            elseif slot.respawnState == "spawning_veh" then
                slot.respawnTimer = (slot.respawnTimer or 0) + dt
                if slot.respawnTimer > MATERIALIZE_TIMEOUT then
                    slot.respawnState = nil
                    slot.culledTimer = 0
                    gridLog("slot=%d respawn_veh_materialize_timeout", slotIndex)
                else
                    local veh = slot.vehEntityID and findEntity(slot.vehEntityID) or nil
                    if veh then
                        slot.vehEntity = veh
                        if slot.driverlessLaunch then
                            slot.respawnState = "commanding"
                        else
                            local npcEntPath = slot.npcEntPath or getNPCEntPath(slot.npcRecord)
                            if npcEntPath then
                                local vehPos = getEntityPosition(veh)
                                local spawnPos = vehPos or getPlayerWorldPosition()
                                slot.npcEntityID, slot.npcSpawnBackend, slot.npcSpawnResolvedKey = spawnNPCEntity(slot.npcRecord, npcEntPath, spawnPos, slot.heading, slot.driver)
                                if slot.npcEntityID then
                                    slot.respawnState = "spawning_npc"
                                    slot.respawnTimer = 0
                                    gridLog("slot=%d respawn_npc_requested entityID=%s", slotIndex, tostring(slot.npcEntityID))
                                else
                                    slot.driverlessLaunch = true
                                    slot.respawnState = "commanding"
                                    gridLog("slot=%d respawn_npc_spawn_failed fallback=driverless", slotIndex)
                                end
                            else
                                slot.driverlessLaunch = true
                                slot.respawnState = "commanding"
                                gridLog("slot=%d respawn_npc_path_missing fallback=driverless", slotIndex)
                            end
                        end
                    end
                end

            -- Sub-state: waiting for respawned NPC to materialize
            elseif slot.respawnState == "spawning_npc" then
                slot.respawnTimer = (slot.respawnTimer or 0) + dt
                if slot.respawnTimer > MATERIALIZE_TIMEOUT then
                    slot.driverlessLaunch = true
                    slot.respawnState = "commanding"
                    gridLog("slot=%d respawn_npc_materialize_timeout fallback=driverless", slotIndex)
                else
                    local npc = slot.npcEntityID and findEntity(slot.npcEntityID) or nil
                    if npc then
                        slot.npcEntity = npc
                        local mounted = mountNPCToVehicle(npc, slot.vehEntity)
                        if mounted then
                            slot.respawnState = "commanding"
                            gridLog("slot=%d respawn_npc_mounted", slotIndex)
                        else
                            slot.driverlessLaunch = true
                            slot.respawnState = "commanding"
                            gridLog("slot=%d respawn_mount_failed fallback=driverless", slotIndex)
                        end
                    end
                end

            -- Sub-state: issue drive command to respawned vehicle
            elseif slot.respawnState == "commanding" then
                if hasOperationalDriver(slot) then
                    local issued = issueDriveCommand(slot)
                    slot.respawnState = nil
                    slot.culledTimer = 0
                    slot.respawnRecoverPoll = nil
                    slot.respawnTimer = nil
                    slot.driveTimer = 0
                    slot.stallTimer = 0
                    slot.launchGraceTimer = RESPAWN_LAUNCH_GRACE_S
                    if issued then
                        gridLog("slot=%d respawn_complete driverless=%s", slotIndex, tostring(slot.driverlessLaunch == true))
                    else
                        gridLog("slot=%d respawn_drive_cmd_failed", slotIndex)
                    end
                else
                    slot.respawnState = nil
                    slot.culledTimer = 0
                    gridLog("slot=%d respawn_no_operational_driver", slotIndex)
                end
            end
        end

        if slot.phase == "done" and getActiveSpawnIndex() == i then
            advanceSpawnCursor(i)
            gridLog("slot=%d skipped -> next_slot=%d", i, tonumber(_grid.nextSlotIndex or -1))
        end
        ::continue::
    end

    local ready, failed, unfinished = countSlotPhases()
    logUpdateSummaryIfChanged(ready, failed, unfinished)

    if _grid.criticalFailureReason and ready == 0 and unfinished == 0 then
        abortGridSession(_grid.criticalFailureReason)
        return
    end

    if unfinished == 0 then
        if ready > 0 then
            setGridPhase("ready", string.format("ready=%d failed=%d", ready, failed))
        else
            setGridPhase("failed", tostring(_grid.lastSlotFailureReason or "no_slots_ready"))
        end
    elseif spawningInProgress and ready > 0 then
        setGridPhase("stabilizing", string.format("ready=%d pending=%d failed=%d", ready, unfinished, failed))
    else
        setGridPhase("spawning", string.format("ready=%d pending=%d failed=%d", ready, unfinished, failed))
    end
end

--- Helper: summarize drive modes for logging.
local function describeModes()
    local counts = {}
    for _, slot in ipairs(_slots) do
        if slot.phase == "driving" then
            local m = slot.driveMode or "autonomous"
            counts[m] = (counts[m] or 0) + 1
        end
    end
    local parts = {}
    for mode, n in pairs(counts) do
        table.insert(parts, string.format("%d %s", n, mode))
    end
    return table.concat(parts, ", ")
end

--- Tell all spawned AI to start driving toward the finish.
--- Call when race transitions from COUNTDOWN to RACING.
function AIVehicles.launchAll()
    if not _active or _launched then return end
    _launched   = true
    _raceTimer  = 0

    local target = _finishPos
    if not target then return end

    local launchCount = 0
    for _, slot in ipairs(_slots) do
        if slot.phase == "ready" and hasOperationalDriver(slot) then
            local issued = _rollingStart.active and issueRollingZoneCommand(slot, _rollingStart.control) or issueDriveCommand(slot, { launchRelease = true })
            if issued then
                logSlotPhaseChange(slot, "driving", _rollingStart.active and "rolling_launch" or "launch_all")
                launchCount = launchCount + 1
            else
                slot.driveTimer = 0
                gridLog("slot=%s launch_pending reason=drive_command_not_sent",
                    tostring(getSlotIndex(slot)))
            end
        end
    end

    print(string.format("[NCM/AIVehicles] Launched %d AI drivers (%s).",
        launchCount, describeModes()))
end

--- Despawn all AI vehicles and NPCs. Call on race end/abort.
function AIVehicles.despawnAll()
    local slotCount = tonumber(#_slots or 0) or 0
    local hadQueuedFormation = _queuedFormation ~= nil
    local hadActiveState = _active
        or hadQueuedFormation
        or slotCount > 0
        or ((_grid and _grid.phase or "idle") ~= "idle" and (_grid and _grid.phase or "idle") ~= "failed")
    local entityRequests = 0
    gridLog(
        "despawn_begin slots=%d active=%s phase=%s queued=%s hadState=%s cooldownActive=%s",
        slotCount,
        tostring(_active),
        tostring(_grid and _grid.phase or "nil"),
        tostring(hadQueuedFormation),
        tostring(hadActiveState),
        tostring(_world and _world.despawnCooldownActive or false))
    gridLog("----- grid_session_end slots=%d active=%s phase=%s -----",
        slotCount,
        tostring(_active),
        tostring(_grid and _grid.phase or "nil"))
    for _, slot in ipairs(_slots) do
        if slot.npcEntity then
            entityRequests = entityRequests + 1
            despawnEntity(slot.npcEntity)
        end
        if slot.vehEntity then
            entityRequests = entityRequests + 1
            despawnEntity(slot.vehEntity)
        end
    end
    _slots      = {}
    _active     = false
    _launched   = false
    _finishPos  = nil
    _spawnTimer = 0
    _raceTimer  = 0
    clearQueuedFormation()
    resetRollingStartState("despawn_all")
    resetWorldState("despawn_all")
    _world.sessionAge = WORLD_SESSION_MIN_AGE
    if hadActiveState or entityRequests > 0 then
        _world.despawnCooldownActive = true
        _world.despawnCooldownTime = tonumber(SlotSafety.POST_DESPAWN_COOLDOWN_TIME or 0.75) or 0.75
        _world.despawnCooldownTicks = tonumber(SlotSafety.POST_DESPAWN_COOLDOWN_TICKS or 12) or 12
        _world.despawnCooldownReason = "despawn_all"
    end
    _grid       = {
        phase = "idle",
        nextSlotIndex = 1,
        totalSlots = 0,
        lastReason = nil,
        firstSpawnArmDelay = 0,
        firstSpawnArmTicks = 0,
        postArmSettleTime = 0,
        postArmSettleTicks = 0,
        slotsPrepared = false,
        spawnArmed = false,
        spawnOrder = nil,
        spawnCursor = 1,
        postArmWaitBucket = nil,
        postArmWaitTicks = nil,
        lastTickLogAt = nil,
        lastSummaryKey = nil,
        runId = nil,
        context = nil,
        assemblyMode = nil,
        launchOnReady = false,
        criticalFailureReason = nil,
        lastSlotFailureReason = nil,
        abortRequested = false,
    }
    gridLog(
        "despawn_complete slots=%d entities=%d hadState=%s cooldownActive=%s cooldown=%.2f ticks=%d",
        tonumber(#_slots or 0),
        tonumber(entityRequests or 0),
        tostring(hadActiveState),
        tostring(_world.despawnCooldownActive),
        tonumber(_world.despawnCooldownTime or 0),
        tonumber(_world.despawnCooldownTicks or 0))
end

--- Returns true if the spawn formation is still in progress.
function AIVehicles.isSpawning()
    if _queuedFormation and (_grid.phase == "idle" or not _active) then
        return true
    end
    if not AIVehicles.isActive() then return false end
    return _grid.phase ~= "ready" and _grid.phase ~= "failed"
end

--- Returns count of vehicles that successfully spawned (phase >= "ready").
function AIVehicles.readyCount()
    local n = 0
    for _, slot in ipairs(_slots) do
        if slot.phase == "ready" or slot.phase == "driving" then
            n = n + 1
        end
    end
    return n
end

--- Returns total queued slots.
function AIVehicles.totalCount()
    return math.max(#_slots, tonumber(_grid.totalSlots or 0))
end

local function readForwardVector(entity)
    if not entity then
        return nil
    end
    local forward = nil
    pcall(function()
        if entity.GetWorldForward then
            local value = entity:GetWorldForward()
            if value then
                local x = tonumber(value.x or 0.0) or 0.0
                local y = tonumber(value.y or 0.0) or 0.0
                local z = tonumber(value.z or 0.0) or 0.0
                local len = math.sqrt((x * x) + (y * y) + (z * z))
                if len > 0.001 then
                    forward = { x = x / len, y = y / len, z = z / len }
                end
            end
        end
    end)
    return forward
end

local function tryGetFocusedEntity(player)
    local focused = nil

    local ok = pcall(function()
        local targetingSystem = Game.GetTargetingSystem and Game.GetTargetingSystem() or nil
        if targetingSystem and targetingSystem.GetLookAtObject then
            focused = targetingSystem:GetLookAtObject(player, false, false)
        end
    end)
    if ok and focused then
        return focused
    end

    ok = pcall(function()
        local targetingSystem = Game.GetTargetingSystem and Game.GetTargetingSystem() or nil
        if targetingSystem and targetingSystem.GetLookAtObject then
            focused = targetingSystem:GetLookAtObject(player)
        end
    end)
    if ok and focused then
        return focused
    end

    ok = pcall(function()
        local targetingSystem = Game.GetTargetingSystem and Game.GetTargetingSystem() or nil
        if targetingSystem and targetingSystem.GetDefaultCrosshairTarget then
            focused = targetingSystem:GetDefaultCrosshairTarget()
        end
    end)
    if ok and focused then
        return focused
    end

    return nil
end

local function getSlotDisplayName(slot)
    local driver = slot and slot.driver or nil
    if type(driver) ~= "table" then
        return nil
    end
    return tostring(driver.displayName or driver.name or driver.driverName or driver.driverId or driver.id or "")
end

local function buildSlotFocusData(slot, entityType, entity)
    if type(slot) ~= "table" then
        return nil
    end
    local name = getSlotDisplayName(slot)
    if not name or name == "" then
        return nil
    end
    return {
        driverId = slot.driver and (slot.driver.driverId or slot.driver.id) or nil,
        name = name,
        entityType = entityType,
        entity = entity,
        distance = nil,
        alignment = nil,
    }
end

function AIVehicles.findSlotByEntity(entityOrId)
    if not entityOrId then
        return nil
    end
    for _, slot in ipairs(_slots) do
        if slot and slot.phase ~= "done" then
            if slot.npcEntity and entitiesMatch(slot.npcEntity, entityOrId) then
                return buildSlotFocusData(slot, "driver", slot.npcEntity)
            end
            if slot.vehEntity and entitiesMatch(slot.vehEntity, entityOrId) then
                return buildSlotFocusData(slot, "vehicle", slot.vehEntity)
            end
            if slot.npcEntityID and entitiesMatch(slot.npcEntityID, entityOrId) then
                return buildSlotFocusData(slot, "driver", slot.npcEntity)
            end
            if slot.vehEntityID and entitiesMatch(slot.vehEntityID, entityOrId) then
                return buildSlotFocusData(slot, "vehicle", slot.vehEntity)
            end
        end
    end
    return nil
end

function AIVehicles.getFocusedRivalLabel(options)
    options = options or {}
    if not AIVehicles.isActive() then
        return nil
    end

    local player = options.player or Game.GetPlayer and Game.GetPlayer() or nil
    if not player then
        return nil
    end

    local focusedEntity = tryGetFocusedEntity(player)
    local directMatch = AIVehicles.findSlotByEntity(focusedEntity)
    if directMatch then
        return directMatch
    end

    local originEntity = nil
    pcall(function()
        originEntity = Game.GetMountedVehicle(player)
    end)
    originEntity = originEntity or player

    local origin = readEntityWorldPosition(originEntity)
    local forward = readForwardVector(player) or readForwardVector(originEntity)
    if not origin or not forward then
        return nil
    end

    local maxDistance = tonumber(options.maxDistance or 65.0) or 65.0
    local maxDistanceSq = maxDistance * maxDistance
    local minDot = tonumber(options.minDot or 0.965) or 0.965
    local best = nil

    for _, slot in ipairs(_slots) do
        if slot and slot.phase ~= "done" then
            local candidateEntity = slot.npcEntity or slot.vehEntity
            local candidateType = slot.npcEntity and "driver" or (slot.vehEntity and "vehicle" or nil)
            local candidatePos = candidateEntity and readEntityWorldPosition(candidateEntity) or slot.livePos or slot.position
            local candidateName = getSlotDisplayName(slot)
            if candidateType and candidatePos and candidateName and candidateName ~= "" then
                local dx = (candidatePos.x or 0.0) - (origin.x or 0.0)
                local dy = (candidatePos.y or 0.0) - (origin.y or 0.0)
                local dz = (candidatePos.z or 0.0) - (origin.z or 0.0)
                local distSq = (dx * dx) + (dy * dy) + (dz * dz)
                if distSq <= maxDistanceSq then
                    local dist = math.sqrt(distSq)
                    if dist > 0.001 then
                        local vx = dx / dist
                        local vy = dy / dist
                        local vz = dz / dist
                        local dot = (vx * (forward.x or 0.0)) + (vy * (forward.y or 0.0)) + (vz * (forward.z or 0.0))
                        if dot >= minDot then
                            if not best or dot > best.alignment or (math.abs(dot - best.alignment) < 0.005 and dist < best.distance) then
                                best = {
                                    driverId = slot.driver and (slot.driver.driverId or slot.driver.id) or nil,
                                    name = candidateName,
                                    entityType = candidateType,
                                    entity = candidateEntity,
                                    distance = dist,
                                    alignment = dot,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

--- Returns whether the system is active (has spawned or is spawning).
function AIVehicles.isActive()
    if _active then
        return true
    end
    if _queuedFormation then
        return true
    end
    return _grid.phase ~= "idle" and _grid.phase ~= "failed"
end

function AIVehicles.getGridPhase()
    return _grid.phase
end

function AIVehicles.isDespawnCoolingDown()
    return _world and _world.despawnCooldownActive == true
end

function AIVehicles.getGridSummary()
    local solver = _grid.solverSummary or {}
    return {
        phase = _grid.phase,
        rollingActive = _rollingStart.active,
        rollingWarmupActive = _rollingStart.warmupActive,
        nextSlotIndex = _grid.nextSlotIndex,
        totalSlots = _grid.totalSlots,
        reason = _grid.lastReason,
        spawnArmed = _grid.spawnArmed,
        gateReason = _world.lastSpawnGateReason,
        ready = AIVehicles.readyCount(),
        launchable = AIVehicles.launchableCount(),
        total = AIVehicles.totalCount(),
        runId = _grid.runId,
        context = _grid.context,
        assemblyMode = _grid.assemblyMode,
        launchOnReady = _grid.launchOnReady,
        solveStatus = solver.status,
        solveValid = solver.valid == true,
        solveRequestedStartType = solver.requestedStartType,
        solveRequestedFormation = solver.requestedFormation,
        solveFinalFormation = solver.finalFormation,
        solveReason = solver.reason,
        solveProbeMode = solver.probeMode,
        solveTrafficPrepared = solver.trafficPrepared,
        solveLegacyFallback = solver.legacyFallback,
        solveEstimatedRoadWidthM = solver.estimatedRoadWidthM,
        solveRouteGrade = solver.routeGrade,
        solveCorridorLengthM = solver.corridorLengthM,
        solveSupportedLaneCount = solver.supportedLaneCount,
        solveEffectiveLaneCount = solver.effectiveLaneCount,
        solveFieldSizeReduced = solver.fieldSizeReduced,
    }
end

--- Returns the formation slots for UI display.
--- Each entry: { driver, position, heading, phase, ready, driveMode, failureReason, launchable, vehRecord, npcRecord }
function AIVehicles.getFormation()
    local result = {}
    for _, slot in ipairs(_slots) do
        table.insert(result, {
            driver        = slot.driver,
            position      = slot.position,
            heading       = slot.heading,
            phase         = slot.phase,
            ready         = (slot.phase == "ready" or slot.phase == "driving"),
            driveMode     = slot.driveMode,
            failureReason = slot.failureReason,
            launchable    = (slot.phase == "ready" or slot.phase == "driving") and hasOperationalDriver(slot),
            vehRecord     = slot.vehRecord,
            appearance    = slot.appearance,
            npcRecord     = slot.npcRecord,
        })
    end
    return result
end

--- Returns live telemetry for all active AI drivers.
--- Each entry: { id, name, position, speed, phase, isActive, driver }
function AIVehicles.getLiveDrivers()
    local result = {}
    for _, slot in ipairs(_slots) do
        if slot.phase ~= "done" then
            table.insert(result, {
                id       = slot.driver and (slot.driver.driverId or slot.driver.id) or nil,
                name     = slot.driver and (slot.driver.displayName or slot.driver.name or slot.driver.id) or "?",
                position = slot.livePos,
                speed    = slot.liveSpeed or 0,
                phase    = slot.phase,
                isActive = (slot.phase == "driving"),
                isWorldCulled = (slot.phase == "driving") and not hasOperationalDriver(slot),
                respawnState = slot.respawnState,
                urgency  = slot.driveProfile and slot.driveProfile.urgency or nil,
                targetSpeed = slot.driveProfile and slot.driveProfile.maxSpeed or nil,
                averageTargetSpeed = slot.driveProfile and slot.driveProfile.projectedAverageSpeed or nil,
                baseSpeedTarget = slot.driveProfile and slot.driveProfile.baseSpeedTarget or nil,
                straightSpeedFloor = slot.driveProfile and slot.driveProfile.straightSpeedFloor or nil,
                commandedMaxSpeed = slot.lastCommandedMaxSpeed,
                commandedMinSpeed = slot.lastCommandedMinSpeed,
                commandBackend = slot.lastCommandBackend,
                driveCommandSeq = slot.driveCommandSeq,
                hardwareRating = slot.driveProfile and slot.driveProfile.hardwareRating or nil,
                driveMode = slot.driveMode,
                gridOrdinal = slot.gridOrdinal,
                theatreProfile = slot.theatreProfile,
                driver   = slot.driver,
            })
        end
    end
    return result
end

--- Despawn a single AI vehicle + NPC by slot index.
--- Used by knockout mode to remove eliminated drivers.
function AIVehicles.despawnSlot(slotIndex)
    local slot = _slots[slotIndex]
    if not slot then return false end
    if slot.npcEntity then despawnEntity(slot.npcEntity) end
    if slot.vehEntity then despawnEntity(slot.vehEntity) end
    slot.npcEntity   = nil
    slot.vehEntity   = nil
    slot.npcEntityID = nil
    slot.vehEntityID = nil
    slot.phase       = "done"
    slot.livePos     = nil
    slot.liveSpeed   = 0
    return true
end

--- Set an ordered list of waypoint positions for a slot.
--- Used by knockout/circuit modes for multi-waypoint driving.
--- @param slotIndex number  1-based index into _slots
--- @param waypoints table[] array of { x, y, z } positions
--- @param loopWaypoints boolean|nil true to wrap at the end, false for a terminal path
function AIVehicles.setWaypoints(slotIndex, waypoints, loopWaypoints)
    local slot = _slots[slotIndex]
    if not slot then return false end
    slot.waypoints     = waypoints
    slot.waypointIndex = 1
    slot.waypointLoop  = (loopWaypoints ~= false)
    return true
end

--- Advance to the next waypoint and re-issue the drive command.
--- Returns true if advanced, false if already at the last non-looping waypoint.
function AIVehicles.advanceWaypoint(slotIndex)
    local slot = _slots[slotIndex]
    if not slot or not slot.waypoints then return false end
    if slot.waypointIndex >= #slot.waypoints then
        if slot.waypointLoop == false then
            if slot.phase == "driving" and hasOperationalDriver(slot) then
                issueDriveCommand(slot)
            end
            return false
        end
        -- Loop back to first waypoint (circuit)
        slot.waypointIndex = 1
    else
        slot.waypointIndex = slot.waypointIndex + 1
    end
    if slot.phase == "driving" and hasOperationalDriver(slot) then
        issueDriveCommand(slot)
    end
    return true
end

--- Returns the slot index for a given driver ID, or nil.
function AIVehicles.findSlotByDriverId(driverId)
    for i, slot in ipairs(_slots) do
        if slot.driver and (slot.driver.driverId or slot.driver.id) == driverId then
            return i
        end
    end
    return nil
end

function AIVehicles.armRollingWarmup(control)
    _rollingStart.warmupActive = control and control.active == true
    _rollingStart.control = control or _rollingStart.control
    _rollingStart.warmupTimer = 0.0
    _rollingStart.lastReason = control and control.reason or "warmup_armed"
end

function AIVehicles.beginRollingStart(control)
    _rollingStart.active = control and control.active == true
    _rollingStart.warmupActive = false
    _rollingStart.control = control
    _rollingStart.leaderProgress = tonumber(control and control.leaderProgress or 0.0) or 0.0
    _rollingStart.commandTimer = 0.0
    _rollingStart.lastReason = control and control.reason or "rolling_zone_begin"
end

function AIVehicles.updateRollingStart(control)
    if not _rollingStart.active then
        return false
    end
    _rollingStart.control = control or _rollingStart.control
    _rollingStart.leaderProgress = tonumber(_rollingStart.control and _rollingStart.control.leaderProgress or _rollingStart.leaderProgress or 0.0) or 0.0
    for _, slot in ipairs(_slots) do
        if (slot.phase == "ready" or slot.phase == "driving") and hasOperationalDriver(slot) then
            issueRollingZoneCommand(slot, _rollingStart.control)
        end
    end
    return true
end

function AIVehicles.releaseRollingStart(reason)
    local wasActive = _rollingStart.active
    resetRollingStartState(reason or "rolling_zone_end")
    if not wasActive or not _launched then
        return false
    end
    for _, slot in ipairs(_slots) do
        if slot.phase == "ready" or slot.phase == "driving" then
            issueDriveCommand(slot)
        end
    end
    return true
end

--- Returns count of slots that are fully operational (ready/driving + both entities).
function AIVehicles.launchableCount()
    local n = 0
    for _, slot in ipairs(_slots) do
        if (slot.phase == "ready" or slot.phase == "driving")
           and hasOperationalDriver(slot) then
            n = n + 1
        end
    end
    return n
end

--- Returns a per-slot spawn report for the debug telemetry panel.
--- Each entry: { slotIndex, driverId, driverName, phase, vehRecord, npcRecord, launchable, failureReason }
function AIVehicles.getSpawnReport()
    local report = {}
    for i, slot in ipairs(_slots) do
        table.insert(report, {
            slotIndex     = i,
            driverId      = slot.driver and (slot.driver.driverId or slot.driver.id) or nil,
            driverName    = slot.driver and (slot.driver.displayName or slot.driver.name or slot.driver.id) or "?",
            phase         = slot.phase,
            vehRecord     = slot.vehRecord,
            appearance    = slot.appearance,
            npcRecord     = slot.npcRecord,
            launchable    = (slot.phase == "ready" or slot.phase == "driving") and hasOperationalDriver(slot),
            failureReason = slot.failureReason,
            solveReason   = slot.solveInfo and slot.solveInfo.reason or nil,
            solveTag      = slot.solveInfo and slot.solveInfo.tag or nil,
            solveValid    = slot.solveInfo and slot.solveInfo.valid or nil,
        })
    end
    return report
end

return AIVehicles
