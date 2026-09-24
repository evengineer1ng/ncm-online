-- ============================================================
-- MT_Ecosystem: modules/telemetry.lua
-- Mod 1: Raw signal extraction + derived G-force calculations.
-- Reads from:
--   • Vehicle blackboard  (speed, gear)
--   • Input board system  (throttle, brake, clutch, steering, handbrake)
--   • TweakDB             (engine RPM range for approximation)
-- Exposes: Telemetry.state  (read every frame by Metrics, Racing, UI)
-- ============================================================

local Telemetry = {}
local FALLBACK_MODULE_DIR = "D:\\SteamLibrary\\steamapps\\common\\Cyberpunk 2077\\bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\MT_Ecosystem\\modules"

local function getModuleDir()
    local dbg = debug
    if dbg and type(dbg.getinfo) == "function" then
        local src = dbg.getinfo(1, "S").source or ""
        if src:sub(1, 1) == "@" then
            src = src:sub(2)
        end
        return src:match("^(.*)[/\\][^/\\]+$") or FALLBACK_MODULE_DIR
    end
    return FALLBACK_MODULE_DIR
end

-- ── Constants ─────────────────────────────────────────────────
local G_CONSTANT      = 9.81    -- m/s² per G
local SMOOTH_FACTOR   = 0.15    -- EMA alpha for G smoothing
local LAT_G_SCALE     = 0.25    -- empirical: latG ≈ steering * speed * k

-- Input action names (CET / Cyberpunk action enum)
local INPUT = {
    throttle  = "Accelerate",
    brake     = "Decelerate",
    clutch    = "Clutch",
    steerLeft = "SteerLeft",
    steerRight= "SteerRight",
    handbrake = "Jump",           -- handbrake shares the "Jump" action in vehicles
}

local AXIS = {
    throttle = "IK_Pad_RightTrigger",
    brake    = "IK_Pad_LeftTrigger",
    rightY   = "IK_Pad_RightAxisY",
    leftY    = "IK_Pad_LeftAxisY",
    rightThumbY = "IK_Pad_RightThumbY",
    leftThumbY  = "IK_Pad_LeftThumbY",
}

-- ── State ─────────────────────────────────────────────────────

--- Public state table — all other modules read from this.
Telemetry.state = {
    -- Inputs (0–1 scalars unless noted)
    throttle    = 0.0,
    brake       = 0.0,
    clutch      = 0.0,
    steering    = 0.0,   -- -1 (full left) to +1 (full right)
    handbrake   = false,

    -- Vehicle state
    speed       = 0.0,   -- m/s (multiply by 3.6 for km/h)
    gear        = 0,     -- -1 = reverse, 0 = neutral/park, 1–N = forward
    rpm         = 0.0,   -- 0–1 normalised (0 = idle, 1 = redline)
    rpmMin      = 600.0,
    rpmMax      = 8000.0,
    rpmActual   = 600.0, -- estimated absolute RPM for external dashboards
    vehicleHealth = 1.0, -- 0–1

    -- Derived signals
    longG       = 0.0,   -- positive = acceleration, negative = braking
    latG        = 0.0,   -- positive = right, negative = left
    accelRate   = 0.0,   -- smoothed positive longG
    decelRate   = 0.0,   -- smoothed magnitude of negative longG
    yawRateProxy = 0.0,
    wheelSlipProxy = 0.0,

    -- Meta
    inVehicle   = false,
    vehicleKey  = "",
}

-- ── Private ────────────────────────────────────────────────────
local _vehicle        = nil
local _blackboard     = nil
local _bbVehicleDef   = nil
local _inputListener  = nil
local _axisCallbackID = nil
local _keyCallbackID  = nil
local _axisValues     = {}
local _activeKeys     = {}
local _mtCfgTimer     = 999.0

local MODULE_DIR      = getModuleDir()
local MOD_ROOT        = MODULE_DIR:gsub("[/\\]modules$", "")
local MT_CONFIG_PATH  = MOD_ROOT:gsub("MT_Ecosystem$", "MANUAL TRANSMISSION V10") .. "\\config.json"
local _mtConfig       = {
    clutchAxis = AXIS.rightY,
    clutchPad  = "",
    clutchPad2 = "",
}

-- TweakDB engine data for RPM approximation
local _engineMinRPM = 600.0
local _engineMaxRPM = 8000.0
local _gearTable    = {}         -- { {minSpeed, maxSpeed, minRPM}, ... }

-- Previous-frame values for derivative calculations
local _lastSpeed      = 0.0
local _lastSpeedMs    = 0.0      -- in m/s for G calc
local _lastSteering   = 0.0

-- ── Helpers ───────────────────────────────────────────────────

--- Read a float input action value safely (returns 0 on error).
local function getInput(actionName)
    local ok, val = pcall(function()
        return Game.GetInputBoardSystem():GetActionValue(CName.new(actionName))
    end)
    return (ok and type(val) == "number") and val or 0.0
end

--- Read a bool input action value safely.
local function getInputBool(actionName)
    local ok, val = pcall(function()
        return Game.GetInputBoardSystem():GetActionValue(CName.new(actionName))
    end)
    return (ok and val ~= nil) and (val > 0.5) or false
end

local function clamp01(v)
    if type(v) ~= "number" then return 0.0 end
    if v < 0.0 then return 0.0 end
    if v > 1.0 then return 1.0 end
    return v
end

local function normaliseTrigger(raw)
    if type(raw) ~= "number" then return nil end
    if raw < 0.0 then
        return clamp01((raw + 1.0) * 0.5)
    end
    return clamp01(raw)
end

local function isHeld(keyName)
    return keyName and keyName ~= "" and _activeKeys[keyName] ~= nil
end

local function getAxisValue(keyName)
    if not keyName or keyName == "" then return nil end
    return _axisValues[keyName]
end

local function normaliseClutchAxisKey(axisKey)
    if axisKey == AXIS.leftThumbY then
        return AXIS.leftY
    end
    if axisKey == AXIS.rightThumbY then
        return AXIS.rightY
    end
    if axisKey == AXIS.leftY or axisKey == AXIS.rightY or axisKey == "" then
        return axisKey
    end
    return AXIS.rightY
end

local function loadManualTransmissionConfig()
    local f = io.open(MT_CONFIG_PATH, "r")
    if not f then return end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" or not json or not json.decode then return end
    local ok, cfg = pcall(json.decode, raw)
    if not ok or type(cfg) ~= "table" then return end
    _mtConfig.clutchAxis = normaliseClutchAxisKey(cfg.mt_clutch_axis or _mtConfig.clutchAxis or AXIS.rightY)
    _mtConfig.clutchPad  = cfg.mt_clutch_pad or ""
    _mtConfig.clutchPad2 = cfg.mt_clutch_pad2 or ""
end

local function refreshManualTransmissionConfig(dt)
    _mtCfgTimer = (_mtCfgTimer or 0.0) + (dt or 0.0)
    if _mtCfgTimer < 2.0 then return end
    _mtCfgTimer = 0.0
    loadManualTransmissionConfig()
end

local function ensureInputHook()
    if _inputListener or not Game then return end
    local hasCallbackSystem = false
    pcall(function() hasCallbackSystem = Game.GetCallbackSystem ~= nil end)
    if not hasCallbackSystem then return end
    local ok = pcall(function()
        _inputListener = NewProxy({
            OnKeyInput = {
                args = {'handle:KeyInputEvent'},
                callback = function(event)
                    local key = event:GetKey().value
                    local action = event:GetAction().value
                    if action == "IACT_Press" then
                        _activeKeys[key] = true
                    elseif action == "IACT_Release" then
                        _activeKeys[key] = nil
                    end
                end
            },
            OnAxisInput = {
                args = {'handle:AxisInputEvent'},
                callback = function(event)
                    local key = event:GetKey().value
                    local value = event:GetValue()
                    if math.abs(value) > 0.01 then
                        _axisValues[key] = value
                    else
                        _axisValues[key] = nil
                    end
                end
            }
        })

        local cb = Game.GetCallbackSystem()
        _keyCallbackID  = cb:RegisterCallback('Input/Key', _inputListener:Target(), _inputListener:Function("OnKeyInput"), true)
        _axisCallbackID = cb:RegisterCallback('Input/Axis', _inputListener:Target(), _inputListener:Function("OnAxisInput"), true)
    end)
    if not ok then
        _inputListener = nil
    end
end

local function readThrottleInput()
    local axis = normaliseTrigger(getAxisValue(AXIS.throttle))
    if axis ~= nil then return axis end
    return clamp01(getInput(INPUT.throttle))
end

local function readBrakeInput()
    local axis = normaliseTrigger(getAxisValue(AXIS.brake))
    if axis ~= nil then return axis end
    return clamp01(getInput(INPUT.brake))
end

local function readClutchInput()
    -- Prefer the authoritative clutch value from Manual Transmission V10
    -- (published as quest fact "mt_v10_clutch_pct", an integer 0–100).
    local bridgeOk, bridgeVal = pcall(function()
        local qs = Game.GetQuestsSystem()
        if not qs then return nil end
        return tonumber(qs:GetFactStr("mt_v10_clutch_pct"))
    end)
    if bridgeOk and type(bridgeVal) == "number" and bridgeVal > 0 then
        return clamp01(bridgeVal / 100.0)
    end

    -- Fallback: read raw inputs directly (no MT v10 or clutch at zero)
    local axisKey = normaliseClutchAxisKey(_mtConfig.clutchAxis or AXIS.rightY)
    local axisRaw = getAxisValue(axisKey)
    local axisClutch = math.max(0.0, -(axisRaw or 0.0))
    local buttonClutch = 0.0
    if _mtConfig.clutchPad ~= "" and isHeld(_mtConfig.clutchPad) and (_mtConfig.clutchPad2 == "" or isHeld(_mtConfig.clutchPad2)) then
        buttonClutch = 1.0
    end
    if buttonClutch > axisClutch then return buttonClutch end
    if axisClutch > 0.0 then return clamp01(axisClutch) end
    return clamp01(getInput(INPUT.clutch))
end

--- Exponential moving average helper.
local function ema(prev, next, alpha)
    return prev + alpha * (next - prev)
end

--- Approximate normalised RPM from speed + gear using TweakDB gear table.
--- Returns 0–1 where 1 = redline.
local function approxRPM(speedKph, gear)
    if gear <= 0 or #_gearTable == 0 then
        -- Rough global approximation for idle/neutral
        return math.max(0.05, speedKph / 200.0)
    end
    local gearIdx = math.min(gear, #_gearTable)
    local gd = _gearTable[gearIdx]
    if not gd then return 0.1 end
    local maxSpd = gd.maxSpeed > 0 and gd.maxSpeed or 80.0
    local ratio  = math.max(0.05, math.min(1.0, speedKph / maxSpd))
    return ratio
end

--- Attempt to read the vehicle blackboard RPM field.
--- Falls back to approxRPM if unavailable.
local function readRPM(speedKph, gear)
    if _blackboard and _bbVehicleDef then
        local ok, val = pcall(function()
            return _blackboard:GetFloat(_bbVehicleDef.RPM)
        end)
        if ok and type(val) == "number" and val > 0 then
            -- Normalise to 0–1
            local range = _engineMaxRPM - _engineMinRPM
            if range > 0 then
                return math.max(0.0, math.min(1.0, (val - _engineMinRPM) / range))
            end
        end
    end
    return approxRPM(speedKph, gear)
end

--- Read vehicle health (0–1). Returns 1.0 on failure.
local function readVehicleHealth()
    if not _vehicle then return 1.0 end

    -- Method 1: StatPoolsSystem – canonical CP2077 entity health API
    local ok1, pct = pcall(function()
        local sps = Game.GetStatPoolsSystem()
        local eid = _vehicle:GetEntityID()
        if sps and eid then
            return sps:GetStatPoolValue(eid, gamedataStatPoolType.Health, true)
        end
        return nil
    end)
    if ok1 and type(pct) == "number" and pct >= 0 then
        return math.max(0.0, math.min(1.0, pct / 100.0))
    end

    -- Method 2: GameObject health getters
    local ok2, ratio = pcall(function()
        local cur = _vehicle:GetCurrentHealth()
        local max = _vehicle:GetTotalHealth()
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            return cur / max
        end
        return nil
    end)
    if ok2 and type(ratio) == "number" then
        return math.max(0.0, math.min(1.0, ratio))
    end

    return 1.0
end

--- Load TweakDB engine + gear data for the current vehicle.
local function loadVehicleData(vehicle)
    if not vehicle then return end
    local ok, _ = pcall(function()
        local rec = vehicle:GetRecord()
        if not rec then return end
        local vid = rec:GetID()

        local function flat(base, suffix)
            return TweakDB:GetFlat(TweakDBID.new(base, suffix))
        end

        local engineRef = flat(vid, ".vehEngineData")
        if engineRef then
            local minR = flat(engineRef, ".minRPM")
            local maxR = flat(engineRef, ".maxRPM")
            if type(minR) == "number" and minR > 0 then _engineMinRPM = minR end
            if type(maxR) == "number" and maxR > 0 then _engineMaxRPM = maxR end
        end

        local driveRef = flat(vid, ".vehDriveModelData")
            or flat(vid, ".bikeDriveModelData")
        if driveRef then
            local gearsFlat = flat(driveRef, ".gears")
            if type(gearsFlat) == "table" then
                _gearTable = {}
                for _, gRef in ipairs(gearsFlat) do
                    local entry = {
                        minSpeed  = flat(gRef, ".minSpeed") or 0,
                        maxSpeed  = flat(gRef, ".maxSpeed") or 80,
                    }
                    table.insert(_gearTable, entry)
                end
            end
        end
    end)
    if not ok then
        print("[NCM/Telemetry] loadVehicleData error (non-fatal)")
    end
end

-- ── Public API ────────────────────────────────────────────────

function Telemetry.init()
    _bbVehicleDef = Game.GetAllBlackboardDefs().Vehicle
    loadManualTransmissionConfig()
    ensureInputHook()
    print("[NCM/Telemetry] Initialised. bbVehicleDef=" .. tostring(_bbVehicleDef ~= nil))
end

function Telemetry.onSessionStart()
    _bbVehicleDef = Game.GetAllBlackboardDefs().Vehicle
    loadManualTransmissionConfig()
    ensureInputHook()
end

function Telemetry.onVehicleEnter(vehicle)
    _vehicle   = vehicle
    local s    = Telemetry.state

    if vehicle and _bbVehicleDef then
        _blackboard = vehicle:GetBlackboard()
    end

    loadVehicleData(vehicle)

    -- Resolve vehicleKey for persistence
    local ok, key = pcall(function()
        local rec = vehicle:GetRecord()
        if rec then
            return TDBID.ToStringDEBUG(rec:GetID())
        end
        return ""
    end)
    s.vehicleKey = (ok and key) or ""
    s.inVehicle  = true

    _lastSpeed   = 0.0
    _lastSpeedMs = 0.0
    _lastSteering = 0.0
end

function Telemetry.onVehicleExit()
    local s       = Telemetry.state
    s.inVehicle   = false
    s.vehicleKey  = ""
    s.throttle    = 0.0
    s.brake       = 0.0
    s.clutch      = 0.0
    s.steering    = 0.0
    s.handbrake   = false
    s.speed       = 0.0
    s.gear        = 0
    s.rpm         = 0.0
    s.rpmMin      = _engineMinRPM
    s.rpmMax      = _engineMaxRPM
    s.rpmActual   = _engineMinRPM
    s.longG       = 0.0
    s.latG        = 0.0
    s.accelRate   = 0.0
    s.decelRate   = 0.0
    s.yawRateProxy = 0.0
    s.wheelSlipProxy = 0.0
    _vehicle      = nil
    _blackboard   = nil
    _gearTable    = {}
    _lastSteering = 0.0
end

function Telemetry.update(dt)
    local s = Telemetry.state
    if not s.inVehicle then return end
    if dt <= 0 then return end
    ensureInputHook()
    refreshManualTransmissionConfig(dt)

    -- ── Raw inputs ───────────────────────────────────────────
    s.throttle  = readThrottleInput()
    s.brake     = readBrakeInput()
    s.clutch    = readClutchInput()
    -- Steering: left axis gives 0–1, right gives 0–1; combine to -1..+1
    local sl    = getInput(INPUT.steerLeft)
    local sr    = getInput(INPUT.steerRight)
    s.steering  = sr - sl
    s.handbrake = getInputBool(INPUT.handbrake)

    -- ── Blackboard reads ─────────────────────────────────────
    if _blackboard and _bbVehicleDef then
        local ok1, spd  = pcall(function() return _blackboard:GetFloat(_bbVehicleDef.SpeedValue) end)
        local ok2, gear = pcall(function() return _blackboard:GetInt(_bbVehicleDef.GearValue)    end)
        if ok1 and type(spd)  == "number" then s.speed = spd  end
        if ok2 and type(gear) == "number" then s.gear  = gear end
    end

    -- ── RPM ──────────────────────────────────────────────────
    s.rpm = readRPM(s.speed, s.gear)
    s.rpmMin = _engineMinRPM
    s.rpmMax = _engineMaxRPM
    s.rpmActual = _engineMinRPM + (s.rpm * math.max(0.0, _engineMaxRPM - _engineMinRPM))

    -- ── Vehicle health (sampled less frequently for perf) ────
    -- Update every ~0.5s using a simple counter stored in state
    s._healthTimer = (s._healthTimer or 0) + dt
    if s._healthTimer >= 0.5 then
        s._healthTimer   = 0
        s.vehicleHealth  = readVehicleHealth()
    end

    -- ── Longitudinal G ───────────────────────────────────────
    -- speed from blackboard is in m/s (confirmed from MT mod context)
    local speedMs = s.speed
    local deltaV  = speedMs - _lastSpeedMs
    local rawLong = deltaV / dt / G_CONSTANT

    -- Clamp to ±4G (realistic vehicle limits)
    rawLong = math.max(-4.0, math.min(4.0, rawLong))
    s.longG = ema(s.longG, rawLong, SMOOTH_FACTOR)

    -- Accel / decel rates (one-sided smoothing)
    if s.longG > 0 then
        s.accelRate = ema(s.accelRate, s.longG, SMOOTH_FACTOR)
        s.decelRate = ema(s.decelRate, 0,        SMOOTH_FACTOR)
    else
        s.accelRate = ema(s.accelRate, 0,             SMOOTH_FACTOR)
        s.decelRate = ema(s.decelRate, -s.longG,      SMOOTH_FACTOR)
    end

    -- ── Lateral G ────────────────────────────────────────────
    -- Approximation: latG = steering * speed * scale
    -- This is not physically exact but directionally correct for overlays.
    local rawLat = s.steering * speedMs * LAT_G_SCALE / G_CONSTANT
    rawLat  = math.max(-3.0, math.min(3.0, rawLat))
    s.latG  = ema(s.latG, rawLat, SMOOTH_FACTOR)

    local steeringDelta = math.abs(s.steering - (_lastSteering or 0.0))
    s.yawRateProxy = ema(s.yawRateProxy, steeringDelta * speedMs * 0.05, 0.25)
    _lastSteering = s.steering

    local launchSlipTarget = 0.0
    local speedKph = speedMs * 3.6
    if speedKph <= 35.0 and s.throttle >= 0.75 and s.gear >= 1 then
        launchSlipTarget = math.max(0.0, s.throttle - math.min(1.0, (s.accelRate or 0.0) / 1.25))
    end
    s.wheelSlipProxy = ema(s.wheelSlipProxy, launchSlipTarget, 0.20)

    -- ── Store for next frame ─────────────────────────────────
    _lastSpeedMs = speedMs
    _lastSpeed   = s.speed
end

return Telemetry
