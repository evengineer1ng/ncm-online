-- ============================================================
-- MT_Ecosystem: modules/metrics.lua
-- Mod 2: Session analytics + event emission.
-- Reads Telemetry.state each frame.
-- Emits events via MTE.Events.emit().
-- Persists completed sessions to save/sessions.json.
-- ============================================================

local Metrics = {}
local Telemetry = require("modules/telemetry")
local Persist = require("modules/persistence")

local function resolveTelemetry()
    if not Telemetry then
        Telemetry = (MTE and MTE.Telemetry) or require("modules/telemetry")
    end
    return Telemetry
end

-- ── Constants ─────────────────────────────────────────────────
local SESSION_FILE      = "sessions.json"
local MAX_SESSIONS      = 50       -- rolling history cap
local SPEED_100         = 100.0    -- km/h threshold for 0-100 timing
local IMPACT_DELTA_V    = 6.0      -- m/s speed drop in one frame = meaningful race contact/impact
local CRASH_DELTA_V     = 20.0     -- m/s velocity drop in one frame = crash
local HARDBRAKE_G       = 0.6      -- longG magnitude threshold
local HARDBRAKE_SUSTAIN = 0.3      -- seconds sustained
local ACCEL_G           = 0.5      -- accelG threshold for AggressiveAccel
local ACCEL_SUSTAIN     = 0.3
local HIGHSPEED_KPH     = 150.0    -- km/h
local HIGHSPEED_SUSTAIN = 3.0      -- seconds
local CORNER_LAT_G      = 0.4
local CORNER_SUSTAIN    = 2.0
local PULL_WINDOW_START = 80.0
local PULL_WINDOW_END   = 150.0

-- ── State ──────────────────────────────────────────────────────

--- Current session: reset on VehicleEnter/SessionStart.
Metrics.session = {
    active          = false,
    startTime       = 0,
    duration        = 0,

    -- 0–100 / 100–0 timing
    zeroToHundred   = nil,    -- elapsed seconds, nil until crossed
    hundredToZero   = nil,
    pullEightyToOneFifty = nil,
    _timing100      = false,  -- currently timing 0–100?
    _timing100start = 0,
    _at100          = false,  -- flag: have we crossed 100?
    _timing100stop  = false,  -- currently timing 100–0 braking?
    _timing100stopStart = 0,
    _timingPullWindow = false,
    _timingPullWindowStart = 0,
    launchSlipPeak = 0.0,
    launchSlipAvg = 0.0,
    _launchSlipAccum = 0.0,
    _launchSlipSamples = 0,

    -- Speed
    peakSpeed       = 0,
    avgSpeed        = 0,
    _speedSamples   = 0,
    _speedAccum     = 0,

    -- G-forces
    maxLongG        = 0,
    maxLatG         = 0,
    maxBrakeG       = 0,

    -- Crash
    crashCount      = 0,
    cleanStreak     = 0,   -- consecutive crash-free exits
    _lastSpeedMs    = 0,

    -- Driver activity
    distanceTraveled = 0,
    timeFullThrottle = 0,
    timeBraking      = 0,

    -- Event log (last 20 events)
    events          = {},
}

--- Cross-session history loaded from disk.
Metrics.history = {}

-- ── Sustained event helpers ────────────────────────────────────
-- Each entry: { timer = 0, active = false }
local _sustain = {
    hardBrake = { timer = 0, active = false },
    accel     = { timer = 0, active = false },
    highSpeed = { timer = 0, active = false },
    corner    = { timer = 0, active = false },
}

-- ── Internal helpers ──────────────────────────────────────────

local function logEvent(name, data)
    local s = Metrics.session
    local entry = { name = name, t = s.duration, data = data }
    table.insert(s.events, 1, entry)   -- prepend so [1] is newest
    if #s.events > 20 then
        table.remove(s.events, 21)
    end
    MTE.Events.emit(name, { session = s, data = data })
    print(string.format("[NCM/Metrics] Event: %s (t=%.1fs)", name, s.duration))
end

--- Update a sustained-event tracker. Returns true on first fire.
local function checkSustain(key, condition, threshold, dt)
    local sv = _sustain[key]
    if condition then
        sv.timer = sv.timer + dt
        if sv.timer >= threshold and not sv.active then
            sv.active = true
            return true   -- first crossing
        end
    else
        sv.timer  = 0
        sv.active = false
    end
    return false
end

local function resetSustain()
    for k, _ in pairs(_sustain) do
        _sustain[k].timer  = 0
        _sustain[k].active = false
    end
end

local function buildSummary(s)
    return {
        startTime        = s.startTime,
        duration         = s.duration,
        zeroToHundred    = s.zeroToHundred,
        hundredToZero    = s.hundredToZero,
        pullEightyToOneFifty = s.pullEightyToOneFifty,
        launchSlipPeak   = s.launchSlipPeak,
        launchSlipAvg    = s.launchSlipAvg,
        peakSpeed        = s.peakSpeed,
        avgSpeed         = s.avgSpeed,
        maxLongG         = s.maxLongG,
        maxLatG          = s.maxLatG,
        maxBrakeG        = s.maxBrakeG,
        crashCount       = s.crashCount,
        distanceTraveled = s.distanceTraveled,
        timeFullThrottle = s.timeFullThrottle,
        timeBraking      = s.timeBraking,
        eventCount       = #s.events,
    }
end

function Metrics.currentSummary()
    if not Metrics.session.active then
        return nil
    end
    local summary = buildSummary(Metrics.session)
    summary.active = true
    return summary
end

function Metrics.latestSummary()
    if Metrics.session.active then
        return Metrics.currentSummary()
    end
    local latest = Metrics.history and Metrics.history[1] or nil
    if type(latest) ~= "table" then
        return nil
    end
    local copy = {}
    for key, value in pairs(latest) do
        copy[key] = value
    end
    copy.active = false
    return copy
end

-- ── Session management ────────────────────────────────────────

local function startSession()
    local s = Metrics.session
    s.active          = true
    s.startTime       = os.time()
    s.duration        = 0
    s.zeroToHundred   = nil
    s.hundredToZero   = nil
    s.pullEightyToOneFifty = nil
    s._timing100      = false
    s._timing100start = 0
    s._at100          = false
    s._timing100stop  = false
    s._timing100stopStart = 0
    s._timingPullWindow = false
    s._timingPullWindowStart = 0
    s.launchSlipPeak  = 0
    s.launchSlipAvg   = 0
    s._launchSlipAccum = 0
    s._launchSlipSamples = 0
    s.peakSpeed       = 0
    s.avgSpeed        = 0
    s._speedSamples   = 0
    s._speedAccum     = 0
    s.maxLongG        = 0
    s.maxLatG         = 0
    s.maxBrakeG       = 0
    s.crashCount      = 0
    s.distanceTraveled = 0
    s.timeFullThrottle = 0
    s.timeBraking     = 0
    s.events          = {}
    s._lastSpeedMs    = 0
    resetSustain()
    print("[NCM/Metrics] Session started.")
end

local function endSession()
    local s = Metrics.session
    if not s.active then return end
    s.active = false

    local summary = buildSummary(s)

    -- Update clean streak
    if s.crashCount == 0 then
        s.cleanStreak = s.cleanStreak + 1
        logEvent("CleanRun", { streak = s.cleanStreak })
    else
        s.cleanStreak = 0
    end

    -- Persist
    local history = Metrics.history
    table.insert(history, 1, summary)
    if #history > MAX_SESSIONS then
        table.remove(history, MAX_SESSIONS + 1)
    end
    Metrics.history = history
    Persist.save(SESSION_FILE, history)

    print(string.format("[NCM/Metrics] Session ended. Duration=%.1fs Peak=%.0fkph Crashes=%d",
        summary.duration, summary.peakSpeed, summary.crashCount))
end

-- ── Public API ────────────────────────────────────────────────

function Metrics.init()
    local data = Persist.load(SESSION_FILE)
    if type(data) == "table" then
        Metrics.history = data
        print(string.format("[NCM/Metrics] Loaded %d session(s) from history.", #data))
    end
    print("[NCM/Metrics] Initialised.")
end

function Metrics.onSessionStart()
    -- Game session loaded; don't auto-start metrics, wait for vehicle
end

function Metrics.onVehicleEnter()
    startSession()
end

function Metrics.onVehicleExit()
    endSession()
end

function Metrics.onShutdown()
    endSession()
end

function Metrics.update(dt)
    if not resolveTelemetry() then return end
    local s = Metrics.session
    if not s.active then return end

    local ts = Telemetry.state
    if not ts.inVehicle then return end

    s.duration = s.duration + dt

    -- ── Distance traveled (speed in m/s × dt) ──────────────
    s.distanceTraveled = s.distanceTraveled + ts.speed * dt

    -- ── Throttle / brake time ───────────────────────────────
    if ts.throttle > 0.9 then s.timeFullThrottle = s.timeFullThrottle + dt end
    if ts.brake    > 0.1 then s.timeBraking      = s.timeBraking      + dt end

    -- ── Speed metrics ───────────────────────────────────────
    -- Convert m/s → km/h for display (blackboard SpeedValue is m/s)
    local speedKph = ts.speed * 3.6
    if speedKph > s.peakSpeed then s.peakSpeed = speedKph end
    s._speedAccum   = s._speedAccum + speedKph
    s._speedSamples = s._speedSamples + 1
    s.avgSpeed      = s._speedAccum / s._speedSamples

    -- ── G-force peaks ───────────────────────────────────────
    if ts.longG  > s.maxLongG  then s.maxLongG  = ts.longG        end
    if math.abs(ts.latG) > s.maxLatG then s.maxLatG = math.abs(ts.latG) end
    if ts.longG  < -s.maxBrakeG then s.maxBrakeG = -ts.longG      end

    -- ── 0–100 km/h timing ───────────────────────────────────
    if not s._at100 and not s._timing100 and speedKph < 5 and ts.throttle > 0.5 then
        s._timing100      = true
        s._timing100start = s.duration
    end
    if s._timing100 then
        if speedKph >= SPEED_100 then
            s.zeroToHundred = s.duration - s._timing100start
            s._timing100    = false
            s._at100        = true
            logEvent("ZeroToHundred", { time = s.zeroToHundred })
        elseif ts.throttle < 0.1 then
            -- Aborted
            s._timing100 = false
        end
    end

    -- ── 100–0 braking timing ────────────────────────────────
    if s._at100 and not s._timing100stop and speedKph >= SPEED_100 and ts.brake > 0.5 then
        s._timing100stop      = true
        s._timing100stopStart = s.duration
    end
    if s._timing100stop then
        if speedKph < 2 then
            s.hundredToZero   = s.duration - s._timing100stopStart
            s._timing100stop  = false
            s._at100          = false  -- reset for next run
            logEvent("HundredToZero", { time = s.hundredToZero })
        end
    end

    -- ── Pull window timing (80–150 km/h) ───────────────────
    if not s._timingPullWindow and speedKph <= (PULL_WINDOW_START + 5.0) and ts.throttle > 0.55 and ts.brake < 0.15 then
        s._timingPullWindow = true
        s._timingPullWindowStart = s.duration
    end
    if s._timingPullWindow then
        if speedKph >= PULL_WINDOW_END then
            s.pullEightyToOneFifty = s.duration - s._timingPullWindowStart
            s._timingPullWindow = false
            logEvent("PullWindow", { time = s.pullEightyToOneFifty, from = PULL_WINDOW_START, to = PULL_WINDOW_END })
        elseif ts.throttle < 0.15 or ts.brake > 0.25 or speedKph < (PULL_WINDOW_START - 10.0) then
            s._timingPullWindow = false
        end
    end

    -- ── Launch traction proxy ───────────────────────────────
    if speedKph <= 35.0 and ts.throttle >= 0.75 then
        local slip = math.max(0.0, tonumber(ts.wheelSlipProxy) or 0.0)
        if slip > s.launchSlipPeak then
            s.launchSlipPeak = slip
        end
        s._launchSlipAccum = s._launchSlipAccum + slip
        s._launchSlipSamples = s._launchSlipSamples + 1
        s.launchSlipAvg = s._launchSlipAccum / math.max(1, s._launchSlipSamples)
    end

    -- ── Crash detection ─────────────────────────────────────
    local deltaV = math.abs(ts.speed - s._lastSpeedMs)
    if deltaV > IMPACT_DELTA_V then
        logEvent("ImpactSpike", { deltaV = deltaV, speed = ts.speed * 3.6 })
    end
    if deltaV > CRASH_DELTA_V then
        s.crashCount = s.crashCount + 1
        logEvent("CrashSpike", { deltaV = deltaV, speed = ts.speed * 3.6 })
    end
    s._lastSpeedMs = ts.speed

    -- ── Sustained events ─────────────────────────────────────

    -- HardBrake: brakeG > threshold sustained
    if checkSustain("hardBrake", ts.decelRate > HARDBRAKE_G, HARDBRAKE_SUSTAIN, dt) then
        logEvent("HardBrake", { g = ts.decelRate, speed = speedKph })
    end

    -- AggressiveAccel
    if checkSustain("accel", ts.accelRate > ACCEL_G, ACCEL_SUSTAIN, dt) then
        logEvent("AggressiveAccel", { g = ts.accelRate, speed = speedKph })
    end

    -- HighSpeedRun
    if checkSustain("highSpeed", speedKph > HIGHSPEED_KPH, HIGHSPEED_SUSTAIN, dt) then
        logEvent("HighSpeedRun", { speed = speedKph })
    end

    -- SustainedCorner
    if checkSustain("corner", math.abs(ts.latG) > CORNER_LAT_G, CORNER_SUSTAIN, dt) then
        logEvent("SustainedCorner", { latG = ts.latG, speed = speedKph })
    end
end

return Metrics
