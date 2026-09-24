-- ============================================================
-- MT_Ecosystem: modules/radioos_bridge.lua
-- Writes a compact live race sidecar for Radio OS.
--
-- This intentionally lives inside MT_Ecosystem instead of the separate
-- RadioOSBridge CET mod. CET mod globals are not reliable across mods, and
-- keeping this writer local avoids extra CP2077 engine probes during load.
-- ============================================================

local Bridge = {}

local VERSION = "2026-04-10-mte-sidecar-v1"
local OUTPUT_FILE = "ncm_race_state.json"

local ACTIVE_TICK = 0.05
local IDLE_TICK = 0.50
local MAX_PENDING_EVENTS = 24
local MAX_STANDINGS = 16

local state = {
    initialized = false,
    seq = 0,
    lastWrite = 0.0,
    lastRaceState = "idle",
    pendingEvents = {},
    lastError = "",
}

local EVENT_NAMES = {
    "RoundReady",
    "RacePreview",
    "GridReady",
    "QualiStart",
    "QualiEnd",
    "RaceCountdown",
    "RaceStart",
    "RaceFinished",
    "KnockoutLobby",
    "KnockoutCountdown",
    "KnockoutStart",
    "DriverEliminated",
    "PlayerInDangerZone",
    "LeadChange",
    "KnockoutFinished",
    "CatchUpBonus",
    "WagerLost",
    "NewRecord",
    "PrestigeChange",
    "SeasonComplete",
    "ChampionshipComplete",
    "ImpactSpike",
    "CrashSpike",
    "HardBrake",
    "AggressiveAccel",
    "HighSpeedRun",
    "SustainedCorner",
    "SafetyIncidentRecorded",
}

local function now()
    local ts = 0
    pcall(function() ts = os.time() end)
    return ts
end

local function safeNumber(value, default)
    local n = tonumber(value)
    if n == nil or n ~= n then return default or 0.0 end
    return n
end

local function safeString(value)
    if value == nil then return "" end
    return tostring(value)
end

local function clamp(value, minValue, maxValue)
    local n = safeNumber(value, minValue)
    if n < minValue then return minValue end
    if n > maxValue then return maxValue end
    return n
end

local function call(mod, fnName, default, ...)
    if type(mod) ~= "table" or type(mod[fnName]) ~= "function" then
        return default
    end
    local ok, result = pcall(mod[fnName], ...)
    if ok then return result end
    state.lastError = tostring(result)
    return default
end

local function jsonString(value)
    local s = safeString(value)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "")
    return '"' .. s .. '"'
end

local function isArray(t)
    local count = 0
    local maxIndex = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        count = count + 1
        if k > maxIndex then maxIndex = k end
    end
    return maxIndex == count
end

local function jsonValue(value, seen)
    local tv = type(value)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return value and "true" or "false" end
    if tv == "number" then
        if value ~= value then return "null" end
        return tostring(value)
    end
    if tv == "string" then return jsonString(value) end
    if tv ~= "table" then return "null" end

    seen = seen or {}
    if seen[value] then return "null" end
    seen[value] = true

    local parts = {}
    if isArray(value) then
        for i = 1, #value do
            parts[#parts + 1] = jsonValue(value[i], seen)
        end
        seen[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    for k, v in pairs(value) do
        if type(k) == "string" and type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" then
            parts[#parts + 1] = jsonString(k) .. ":" .. jsonValue(v, seen)
        end
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function compactValue(value, depth, seen)
    local tv = type(value)
    if tv == "nil" or tv == "boolean" or tv == "number" or tv == "string" then
        return value
    end
    if tv ~= "table" or depth <= 0 then
        return nil
    end

    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true

    local out = {}
    local count = 0
    if isArray(value) then
        for i = 1, math.min(#value, 16) do
            local item = compactValue(value[i], depth - 1, seen)
            if item ~= nil then out[#out + 1] = item end
        end
    else
        for k, v in pairs(value) do
            if type(k) == "string" then
                local item = compactValue(v, depth - 1, seen)
                if item ~= nil then
                    out[k] = item
                    count = count + 1
                    if count >= 32 then break end
                end
            end
        end
    end

    seen[value] = nil
    return out
end

local function pushEvent(name, payload)
    if #state.pendingEvents >= MAX_PENDING_EVENTS then
        table.remove(state.pendingEvents, 1)
    end
    state.pendingEvents[#state.pendingEvents + 1] = {
        type = name,
        data = compactValue(payload or {}, 3) or {},
        ts = now(),
    }
end

local function telemetrySnapshot(mte)
    local out = {
        throttle = 0.0,
        brake = 0.0,
        clutch = 0.0,
        steering = 0.0,
        handbrake = false,
        speed_mps = 0.0,
        speed_kph = 0.0,
        gear = 0,
        rpm = 0.0,
        rpm_norm = 0.0,
        rpm_min = 600.0,
        rpm_max = 8500.0,
        rpm_est = 600.0,
        steering_deg = 0.0,
        vehicle_health = 1.0,
        vehicle_health_pct = 100.0,
        long_g = 0.0,
        lat_g = 0.0,
        accel_rate = 0.0,
        decel_rate = 0.0,
        in_vehicle = false,
        vehicle_key = "",
    }

    local telemetry = mte and mte.Telemetry
    local s = telemetry and telemetry.state
    if type(s) ~= "table" then return out end

    out.throttle = safeNumber(s.throttle, 0.0)
    out.brake = safeNumber(s.brake, 0.0)
    out.clutch = safeNumber(s.clutch, 0.0)
    out.steering = safeNumber(s.steering, 0.0)
    out.handbrake = s.handbrake == true
    out.speed_mps = safeNumber(s.speed, 0.0)
    out.speed_kph = out.speed_mps * 3.6
    out.gear = math.floor(safeNumber(s.gear, 0))
    out.rpm = clamp(s.rpm, 0.0, 1.25) -- legacy sidecar field: normalised RPM
    out.rpm_norm = clamp(s.rpm, 0.0, 1.25)
    out.rpm_min = safeNumber(s.rpmMin or s.rpm_min, 600.0)
    out.rpm_max = math.max(out.rpm_min + 1.0, safeNumber(s.rpmMax or s.rpm_max, 8500.0))
    out.rpm_est = safeNumber(
        s.rpmActual or s.rpm_actual,
        out.rpm_min + (out.rpm_norm * (out.rpm_max - out.rpm_min))
    )
    out.steering_deg = out.steering * 450.0
    out.vehicle_health = clamp(s.vehicleHealth, 0.0, 1.0)
    out.vehicle_health_pct = out.vehicle_health * 100.0
    out.long_g = safeNumber(s.longG, 0.0)
    out.lat_g = safeNumber(s.latG, 0.0)
    out.accel_rate = safeNumber(s.accelRate, 0.0)
    out.decel_rate = safeNumber(s.decelRate, 0.0)
    out.in_vehicle = s.inVehicle == true
    out.vehicle_key = safeString(s.vehicleKey)
    return out
end

local function compactStanding(entry, position, telemetry)
    if type(entry) ~= "table" then entry = {} end
    local isPlayer = entry.isPlayer == true
    local speedMps = safeNumber(entry.speed, 0.0)
    if isPlayer and speedMps <= 0 and telemetry then
        speedMps = safeNumber(telemetry.speed_mps, 0.0)
    end
    local currentLap = math.floor(safeNumber(entry.currentLap or entry.lap, 0))

    return {
        position = position,
        name = safeString(entry.name or entry.displayName or (isPlayer and "V" or "?")),
        driverId = safeString(entry.driverId or entry.id or (isPlayer and "player" or "")),
        isPlayer = isPlayer,
        finished = entry.finished == true,
        time = safeNumber(entry.time, 0.0),
        progress = safeNumber(entry.progress, 0.0),
        distanceAlong = safeNumber(entry.distanceAlong, 0.0),
        remainingDistance = safeNumber(entry.remainingDistance or entry.distToFinish, 0.0),
        distToFinish = safeNumber(entry.distToFinish or entry.remainingDistance, 0.0),
        sectorIndex = math.floor(safeNumber(entry.sectorIndex, 0)),
        currentLap = currentLap,
        lap = currentLap,
        cpIndex = math.floor(safeNumber(entry.cpIndex, 0)),
        speed = speedMps,
        speedMps = speedMps,
        speedKph = speedMps * 3.6,
        isRival = entry.isRival == true,
        launchable = entry.launchable == true,
        provenance = safeString(entry.provenance),
    }
end

local function attachPlayerPack(live, standings, estimatedPosition)
    local playerIndex = 0
    for i, entry in ipairs(standings) do
        if entry.isPlayer then
            playerIndex = i
            break
        end
    end
    if playerIndex <= 0 and estimatedPosition > 0 and standings[estimatedPosition] then
        playerIndex = estimatedPosition
    end

    if playerIndex > 0 and standings[playerIndex] then
        live.player = standings[playerIndex]
        live.ahead = standings[playerIndex - 1] or {}
        live.behind = standings[playerIndex + 1] or {}
    end
end

local function cfgTrackName(mte, cfg)
    if type(cfg) ~= "table" then return "" end
    local direct = cfg.trackName or cfg.routeName or cfg.circuitName
    if direct and tostring(direct) ~= "" then return tostring(direct) end
    if cfg.nodeA and cfg.nodeB and mte and mte.Tracks then
        return safeString(call(mte.Tracks, "getRouteName", "", cfg.nodeA, cfg.nodeB))
    end
    return ""
end

local function compactTiming(timing)
    if type(timing) ~= "table" then return {} end
    return {
        race_time = safeNumber(timing.raceTime, 0.0),
        current_lap = math.floor(safeNumber(timing.currentLap, 1)),
        total_laps = math.floor(safeNumber(timing.totalLaps, 1)),
        current_sector = math.floor(safeNumber(timing.currentSector, 1)),
        total_sectors = math.floor(safeNumber(timing.totalSectors, 1)),
        player_progress = safeNumber(timing.playerProgress, 0.0),
        player_distance_along = safeNumber(timing.playerDistanceAlong, 0.0),
        player_remaining_distance = safeNumber(timing.playerRemainingDistance, 0.0),
        current_lap_time = safeNumber(timing.currentLapTime, 0.0),
        current_sector_time = safeNumber(timing.currentSectorTime, 0.0),
        session_best_lap = safeNumber(timing.sessionBestLap, 0.0),
        route_best_lap = safeNumber(timing.routeBestLap, 0.0),
        last_lap_number = math.floor(safeNumber(timing.lastLapNumber, 0)),
        last_lap_time = safeNumber(timing.lastLapTime, 0.0),
        last_lap_delta = safeNumber(timing.lastLapDelta, 0.0),
        last_lap_label = safeString(timing.lastLapLabel),
        last_sector_number = math.floor(safeNumber(timing.lastSectorNumber, 0)),
        last_sector_time = safeNumber(timing.lastSectorTime, 0.0),
        last_sector_delta = safeNumber(timing.lastSectorDelta, 0.0),
        last_sector_label = safeString(timing.lastSectorLabel),
        valid_for_records = timing.validForRecords ~= false and timing.playerValidForRecords ~= false,
        finish_status = safeString(timing.finishStatus),
    }
end

local function compactHud(hud)
    if type(hud) ~= "table" then return {} end
    return {
        race_mode = safeString(hud.raceMode),
        race_mode_label = safeString(hud.raceModeLabel),
        objective_text = safeString(hud.objectiveText),
        status_text = safeString(hud.statusText),
        progress_label = safeString(hud.progressLabel),
        target_label = safeString(hud.targetLabel),
        current_lap = math.floor(safeNumber(hud.currentLap, 1)),
        total_laps = math.floor(safeNumber(hud.totalLaps, 1)),
        current_target_index = math.floor(safeNumber(hud.currentTargetIndex, 0)),
        total_targets = math.floor(safeNumber(hud.totalTargets, 0)),
        distance_to_target = safeNumber(hud.distanceToTarget, 0.0),
        countdown_phase = math.floor(safeNumber(hud.countdownPhase, -1)),
    }
end

local function attachTimingAndHud(live, mte, racing)
    local raceTelemetry = mte and mte.RaceTelemetry
    live.timing = compactTiming(call(raceTelemetry, "getActiveTimingStack", nil))
    live.hud = compactHud(call(racing, "getHUDRaceState", nil))
end

local function attachDashSummary(live, raceState)
    local telemetry = live.telemetry or {}
    local player = live.player or {}
    local timing = live.timing or {}
    local hud = live.hud or {}
    local currentLap = timing.current_lap or hud.current_lap or player.currentLap or player.lap or 1
    local totalLaps = timing.total_laps or hud.total_laps or currentLap
    local progress = player.progress or timing.player_progress or 0.0
    local remaining = player.remainingDistance or player.distToFinish or timing.player_remaining_distance or hud.distance_to_target or 0.0

    live.dash = {
        race_state = safeString(raceState),
        mode = safeString(live.mode),
        track_name = safeString(live.track_name),
        speed_kph = safeNumber(telemetry.speed_kph, 0.0),
        speed_mps = safeNumber(telemetry.speed_mps, 0.0),
        gear = math.floor(safeNumber(telemetry.gear, 0)),
        rpm_est = safeNumber(telemetry.rpm_est, 0.0),
        rpm_max = safeNumber(telemetry.rpm_max, 8500.0),
        rpm_norm = safeNumber(telemetry.rpm_norm or telemetry.rpm, 0.0),
        throttle = safeNumber(telemetry.throttle, 0.0),
        brake = safeNumber(telemetry.brake, 0.0),
        clutch = safeNumber(telemetry.clutch, 0.0),
        steering = safeNumber(telemetry.steering, 0.0),
        steering_deg = safeNumber(telemetry.steering_deg, 0.0),
        handbrake = telemetry.handbrake == true,
        vehicle_health_pct = safeNumber(telemetry.vehicle_health_pct, 100.0),
        long_g = safeNumber(telemetry.long_g, 0.0),
        lat_g = safeNumber(telemetry.lat_g, 0.0),
        accel_rate = safeNumber(telemetry.accel_rate, 0.0),
        decel_rate = safeNumber(telemetry.decel_rate, 0.0),
        current_lap = math.max(1, math.floor(safeNumber(currentLap, 1))),
        total_laps = math.max(1, math.floor(safeNumber(totalLaps, 1))),
        position = math.floor(safeNumber(live.estimated_position, 0)),
        field_size = math.max(1, math.floor(safeNumber(live.field_size, 1))),
        race_time_s = safeNumber(live.timer or timing.race_time, 0.0),
        current_lap_time_s = safeNumber(timing.current_lap_time, 0.0),
        best_lap_s = safeNumber(timing.session_best_lap, 0.0) > 0 and timing.session_best_lap or timing.route_best_lap,
        last_lap_s = safeNumber(timing.last_lap_time, 0.0),
        progress_pct = clamp(progress * 100.0, 0.0, 100.0),
        distance_to_finish_m = math.max(0.0, safeNumber(remaining, 0.0)),
        gap_ahead_text = safeString(live.gap_text),
        gap_behind_text = safeString(live.gap_behind_text),
        knockout_danger = live.knockout_danger == true,
        valid_for_records = timing.valid_for_records ~= false,
    }
end

local function buildLiveState(mte)
    local telemetry = telemetrySnapshot(mte)
    local raceState = "idle"
    local live = {
        mode = "",
        timer = 0.0,
        estimated_position = 0,
        gap_text = "",
        gap_behind_text = "",
        field_size = 0,
        track_name = "",
        district = "",
        race_type = "",
        start_type = "",
        distance = 0.0,
        knockout_remaining = 0,
        knockout_danger = false,
        knockout_elim_cd = 0.0,
        knockout_phase = "",
        telemetry = telemetry,
        timing = {},
        hud = {},
        dash = {},
        player = {},
        ahead = {},
        behind = {},
        standings = {},
    }

    local knockout = mte and mte.Knockout
    local knockoutState = safeString(call(knockout, "getState", "idle"))
    if knockout and knockoutState ~= "" and knockoutState ~= "idle" then
        raceState = knockoutState
        live.mode = "knockout"
        live.timer = safeNumber(call(knockout, "getRaceTimer", 0.0), 0.0)
        live.knockout_remaining = math.floor(safeNumber(call(knockout, "getRemainingDrivers", 0), 0))
        live.field_size = live.knockout_remaining
        live.knockout_danger = call(knockout, "isPlayerInDangerZone", false) == true
        live.knockout_elim_cd = safeNumber(call(knockout, "getEliminationCountdown", 0.0), 0.0)
        live.knockout_phase = safeString(call(knockout, "getRacePhase", ""))
        live.estimated_position = math.floor(safeNumber(call(knockout, "getPlayerPosition", 0), 0))

        local cfg = call(knockout, "getConfig", nil)
        live.track_name = cfgTrackName(mte, cfg)
        local rawStandings = call(knockout, "getLiveStandings", {}) or {}
        local compact = {}
        for i, entry in ipairs(rawStandings) do
            if i > MAX_STANDINGS then break end
            compact[#compact + 1] = compactStanding(entry, i, telemetry)
        end
        live.standings = compact
        attachPlayerPack(live, compact, live.estimated_position)
        attachTimingAndHud(live, mte, mte and mte.Racing)
        attachDashSummary(live, raceState)
        return raceState, live
    end

    local racing = mte and mte.Racing
    raceState = safeString(call(racing, "getState", "idle"))
    if not racing or raceState == "" then raceState = "idle" end
    if racing and raceState ~= "idle" then
        live.mode = "sprint"
        live.timer = safeNumber(call(racing, "getRaceTimer", 0.0), 0.0)
        live.gap_text = safeString(call(racing, "getGapText", ""))
        live.gap_behind_text = safeString(call(racing, "getGapBehindText", ""))
        live.estimated_position = math.floor(safeNumber(call(racing, "getEstimatedPosition", 0), 0))

        local field = call(racing, "getField", {}) or {}
        live.field_size = #field + 1
        local cfg = call(racing, "getConfig", nil)
        if type(cfg) == "table" then
            live.track_name = cfgTrackName(mte, cfg)
            live.district = safeString(cfg.district)
            live.race_type = safeString(cfg.raceType)
            live.start_type = safeString(cfg.startType)
            live.distance = safeNumber(cfg.distance, 0.0)
        end

        local rawStandings = call(racing, "getLiveStandings", {}) or {}
        local compact = {}
        for i, entry in ipairs(rawStandings) do
            if i > MAX_STANDINGS then break end
            compact[#compact + 1] = compactStanding(entry, i, telemetry)
        end
        live.standings = compact
        attachPlayerPack(live, compact, live.estimated_position)
    end

    attachTimingAndHud(live, mte, racing)
    attachDashSummary(live, raceState)
    return raceState, live
end

local function writePayload(payload)
    local f, err = io.open(OUTPUT_FILE, "w")
    if not f then
        state.lastError = tostring(err or "open failed")
        return false
    end
    local ok, writeErr = pcall(function()
        f:write(jsonValue(payload))
    end)
    f:close()
    if not ok then
        state.lastError = tostring(writeErr)
        return false
    end
    return true
end

local function shouldWrite(dt, raceState)
    state.lastWrite = (state.lastWrite or 0.0) + safeNumber(dt, 0.0)
    local active = raceState ~= "idle" and raceState ~= ""
    local tick = active and ACTIVE_TICK or IDLE_TICK
    if #state.pendingEvents > 0 then tick = 0.0 end
    if state.lastWrite < tick then return false end
    state.lastWrite = 0.0
    return true
end

function Bridge.init(mte)
    if state.initialized then return true end
    if not (mte and mte.Events and mte.Events.on) then
        state.lastError = "MTE.Events unavailable"
        return false
    end

    for _, name in ipairs(EVENT_NAMES) do
        local ok, err = pcall(function()
            mte.Events.on(name, function(payload)
                pushEvent(name, payload)
            end)
        end)
        if not ok then
            state.lastError = tostring(err)
        end
    end

    state.initialized = true
    print("[NCM/RadioOSBridge] active " .. VERSION .. " -> " .. OUTPUT_FILE)
    return true
end

function Bridge.update(dt, mte)
    local ok, err = pcall(function()
        local raceState, live = buildLiveState(mte)
        if not shouldWrite(dt, raceState) then return end

        state.seq = state.seq + 1
        local pending = state.pendingEvents
        state.pendingEvents = {}
        state.lastRaceState = raceState

        writePayload({
            bridge_version = VERSION,
            seq = state.seq,
            race_state = raceState,
            pending_events = pending,
            live = live,
            ts = now(),
        })
    end)
    if not ok then
        state.lastError = tostring(err)
    end
end

function Bridge.onShutdown(mte)
    state.seq = state.seq + 1
    writePayload({
        bridge_version = VERSION,
        seq = state.seq,
        race_state = state.lastRaceState or "idle",
        pending_events = state.pendingEvents,
        live = {},
        shutdown = true,
        ts = now(),
    })
    state.pendingEvents = {}
end

function Bridge.status()
    return {
        version = VERSION,
        initialized = state.initialized,
        seq = state.seq,
        race_state = state.lastRaceState,
        pending = #state.pendingEvents,
        last_error = state.lastError,
    }
end

return Bridge
