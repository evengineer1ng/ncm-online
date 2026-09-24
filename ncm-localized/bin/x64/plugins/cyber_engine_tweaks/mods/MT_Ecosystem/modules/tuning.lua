-- ============================================================
-- MT_Ecosystem: modules/tuning.lua  (V2 rewrite)
-- 6-category TweakDB tuning suite with named profiles.
--   Categories: Engine, Drivetrain, Brakes, Handling, Stability, Anti-crawl
--   Up to 5 named profiles per vehicle, plus a live "scratch" setup.
--   ManualClutch idle-creep integration via MtSetThrottle().
-- ============================================================

local Tuning = {}
local Persist = require("modules/persistence")
local Parts = nil
local Telemetry = nil

local function resolvePersist()
    if not Persist then
        Persist = (MTE and MTE.Persist) or require("modules/persistence")
    end
    return Persist
end

local function resolveParts()
    if not Parts then
        Parts = (MTE and MTE.Parts) or require("modules/parts")
    end
    return Parts
end

local function resolveTelemetry()
    if not Telemetry then
        Telemetry = (MTE and MTE.Telemetry) or require("modules/telemetry")
    end
    return Telemetry
end

local function clamp(value, minValue, maxValue)
    if type(value) ~= "number" then return minValue end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function safeDriveFlat(drRef, suffix)
    if not drRef or not suffix then return nil end
    local ok, value = pcall(function()
        return TweakDB:GetFlat(TweakDBID.new(drRef, suffix))
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local PROFILE_EXTRA_FLATS = {
    { key = "airResistanceFactor", suffix = ".airResistanceFactor" },
    { key = "turningRollFactor", suffix = ".turningRollFactor" },
    { key = "handbrakeTorque", suffix = ".handbrakeBrakingTorque" },
    { key = "turningMaxAdd", suffix = ".turningMaxAdd" },
    { key = "wheelTurningMax", suffix = ".wheelTurningMax" },
}

-- ── Parameter definitions ─────────────────────────────────────
-- Each param: { key, suffix, min, max, default, label }
-- suffix = TweakDB suffix on the drive model record
-- min/max are the slider range; default = 1.0 unless noted

local PARAMS = {
    -- Engine
    { cat="Engine",     key="powerMult",        suffix=".accelerationBoost",          min=0.5,  max=2.5, default=1.0, label="Power" },
    { cat="Engine",     key="throttleResponse",  suffix=".accelerationInAir",          min=0.5,  max=2.0, default=1.0, label="Throttle Response" },
    { cat="Engine",     key="revLimitBehavior",  suffix=".maxWheelTorque",             min=0.5,  max=2.0, default=1.0, label="Rev Limit" },
    -- Drivetrain
    { cat="Drivetrain", key="engineBraking",     suffix=".engineBrakingFactor",        min=0.0,  max=3.0, default=1.0, label="Engine Braking" },
    { cat="Drivetrain", key="drivelineEffic",    suffix=".driveModelData_sharedFwd",   min=0.5,  max=1.5, default=1.0, label="Driveline Efficiency" },
    { cat="Drivetrain", key="burnoutThresh",     suffix=".burnOutRotationModifier",    min=0.0,  max=3.0, default=1.0, label="Burnout Threshold" },
    -- Brakes
    { cat="Brakes",     key="brakingPower",      suffix=".lowVelStoppingDeceleration", min=0.3,  max=3.0, default=1.0, label="Braking Power" },
    { cat="Brakes",     key="brakeBias",         suffix=".brakingFriction",            min=0.3,  max=2.0, default=1.0, label="Brake Bias" },
    -- Handling
    { cat="Handling",   key="understeerLevel",   suffix=".lateralDampingZeroSpeed",    min=0.3,  max=2.0, default=1.0, label="Understeer" },
    { cat="Handling",   key="oversteerLevel",    suffix=".lateralDampingFullSpeed",    min=0.3,  max=2.0, default=1.0, label="Oversteer" },
    -- Stability
    { cat="Stability",  key="tractionControl",   suffix=".slopeTurnFriction",          min=0.0,  max=2.0, default=1.0, label="Traction Control" },
    { cat="Stability",  key="spinPrevention",    suffix=".slopeCompensationFactor",    min=0.0,  max=2.0, default=1.0, label="Spin Prevention" },
    -- Anti-crawl (no TweakDB suffix – handled via MtSetThrottle)
    { cat="AntiCrawl",  key="idleCreep",         suffix=nil,                           min=0.0,  max=1.0, default=0.0, label="Idle Creep" },
}

local MAX_PROFILES = 5

-- ── Default setup ─────────────────────────────────────────────

local function makeDefaultSetup()
    local s = {}
    for _, p in ipairs(PARAMS) do s[p.key] = p.default end
    return s
end

-- ── State ─────────────────────────────────────────────────────

-- scratch = live values being edited, applied to TweakDB on change
Tuning.scratch   = makeDefaultSetup()
Tuning.dirty     = false   -- apply pending flag

-- profiles[vehicleKey] = { { name="Race", setup={...} }, ... }
Tuning._profiles = {}
Tuning._vehicleKey = nil
Tuning._driveRef   = nil
Tuning._originals  = {}    -- { [suffix] = originalValue }
Tuning._pendingRestore = false
Tuning._categories = { "Engine", "Drivetrain", "Brakes", "Handling", "Stability", "AntiCrawl" }
Tuning.PARAMS      = PARAMS
Tuning._lastRuntimeSignature = ""

-- ── Init / lifecycle ──────────────────────────────────────────

function Tuning.init()
    print("[NCM/Tuning] V2 ready (6 categories, named profiles).")
end

function Tuning.onVehicleEnter(vehicle)
    if not vehicle then return end

    if Tuning._pendingRestore then
        Tuning._restoreOriginals()
        Tuning._pendingRestore = false
        Tuning._driveRef = nil
        Tuning._originals = {}
    end

    pcall(function()
        local rec = vehicle:GetRecord()
        if not rec then return end
        local vid = rec:GetID()
        Tuning._vehicleKey = TDBID.ToStringDEBUG(vid)

        -- Resolve drive model reference (car vs bike)
        local drRef = TweakDB:GetFlat(TweakDBID.new(vid, ".vehDriveModelData"))
                   or TweakDB:GetFlat(TweakDBID.new(vid, ".bikeDriveModelData"))
        Tuning._driveRef = drRef

        Tuning._captureOriginals(drRef)
    end)

    local vk = Tuning._vehicleKey
    if vk and vk ~= "" then
        local saved = Tuning._loadVehicleData(vk)
        Tuning._profiles[vk]  = saved.profiles or {}
        local last = saved.lastProfile
        if last then
            Tuning.scratch = Tuning._findProfile(vk, last) or makeDefaultSetup()
        else
            Tuning.scratch = (saved.scratch and type(saved.scratch) == "table")
                             and saved.scratch or makeDefaultSetup()
        end
    else
        Tuning.scratch = makeDefaultSetup()
    end

    Tuning._lastRuntimeSignature = ""
    Tuning._applyAll()
end

function Tuning.onVehicleExit()
    Tuning._saveVehicleData()

    local player = nil
    pcall(function()
        player = Game.GetPlayer()
    end)

    if player and not (MTE and MTE.shuttingDown) then
        Tuning._restoreOriginals()
        Tuning._pendingRestore = false
        Tuning._driveRef   = nil
        Tuning._originals  = {}
    else
        Tuning._pendingRestore = Tuning._driveRef ~= nil and next(Tuning._originals) ~= nil
    end

    Tuning._vehicleKey = nil
    Tuning._lastRuntimeSignature = ""
    if not Tuning._pendingRestore then
        Tuning._driveRef   = nil
        Tuning._originals  = {}
    end
end

function Tuning.onShutdown()
    Tuning._saveVehicleData()
    Tuning._vehicleKey = nil
    Tuning._driveRef = nil
    Tuning._originals = {}
    Tuning._pendingRestore = false
    Tuning._lastRuntimeSignature = ""
end

function Tuning.update(dt)
    local runtimeSignature = Tuning._runtimeSignature()
    if Tuning.dirty or runtimeSignature ~= Tuning._lastRuntimeSignature then
        Tuning._applyAll()
        Tuning.dirty = false
        Tuning._lastRuntimeSignature = runtimeSignature
    end
end

function Tuning.markDirty()
    Tuning.dirty = true
end

-- ── Public: parameter editing ─────────────────────────────────

--- Set a single parameter value (will apply on next update tick).
--- @param key   string  e.g. "powerMult"
--- @param value number
function Tuning.set(key, value)
    if Tuning.scratch[key] == nil then return end
    Tuning.scratch[key] = value
    Tuning.dirty = true
end

--- Set all parameters to defaults.
function Tuning.resetAll()
    Tuning.scratch = makeDefaultSetup()
    Tuning.dirty   = true
end

-- ── Public: profiles ──────────────────────────────────────────

--- Save current scratch as a named profile.
--- Overwrites if a profile with that name already exists.
--- Returns false if already at MAX_PROFILES and name is new.
function Tuning.saveProfile(name)
    local vk = Tuning._vehicleKey
    if not vk then return false, "No vehicle" end
    Tuning._profiles[vk] = Tuning._profiles[vk] or {}

    for i, p in ipairs(Tuning._profiles[vk]) do
        if p.name == name then
            Tuning._profiles[vk][i].setup = Tuning._copySetup(Tuning.scratch)
            Tuning._saveVehicleData(name)
            return true
        end
    end

    if #Tuning._profiles[vk] >= MAX_PROFILES then
        return false, string.format("Max %d profiles reached. Delete one first.", MAX_PROFILES)
    end

    table.insert(Tuning._profiles[vk], { name = name, setup = Tuning._copySetup(Tuning.scratch) })
    Tuning._saveVehicleData(name)
    return true
end

--- Load a profile into scratch.
function Tuning.loadProfile(name)
    local vk = Tuning._vehicleKey
    if not vk then return false end
    local s = Tuning._findProfile(vk, name)
    if not s then return false end
    Tuning.scratch = s
    Tuning.dirty   = true
    Tuning._saveVehicleData(name)
    return true
end

--- Delete a named profile.
function Tuning.deleteProfile(name)
    local vk = Tuning._vehicleKey
    if not vk then return end
    local profs = Tuning._profiles[vk] or {}
    for i, p in ipairs(profs) do
        if p.name == name then
            table.remove(profs, i)
            Tuning._saveVehicleData(nil)
            return true
        end
    end
    return false
end

--- Get list of profile names for the current vehicle.
function Tuning.profileNames()
    local vk = Tuning._vehicleKey
    if not vk then return {} end
    local out = {}
    for _, p in ipairs(Tuning._profiles[vk] or {}) do
        table.insert(out, p.name)
    end
    return out
end

function Tuning.getCurrentVehicleDriveSnapshot()
    local drRef = Tuning._driveRef
    if not drRef then return nil end
    local driveRefText = string.lower(tostring(drRef or ""))
    local driveKind = string.find(driveRefText, "bike", 1, true) and "bike" or "car"

    local snapshot = {
        vehicleKey = Tuning._vehicleKey,
        driveRef = drRef,
        driveKind = driveKind,
        baseline = {},
        current = {},
        multipliers = {},
        extras = {},
    }

    for _, p in ipairs(PARAMS) do
        if p.suffix then
            local current = safeDriveFlat(drRef, p.suffix)
            local baseline = Tuning._originals[p.suffix]
            if type(current) == "number" then
                snapshot.current[p.key] = current
            end
            if type(baseline) == "number" then
                snapshot.baseline[p.key] = baseline
            elseif type(current) == "number" then
                snapshot.baseline[p.key] = current
            end

            local baseValue = snapshot.baseline[p.key]
            local currentValue = snapshot.current[p.key]
            if type(baseValue) == "number" and type(currentValue) == "number" and math.abs(baseValue) > 0.0001 then
                snapshot.multipliers[p.key] = currentValue / baseValue
            else
                snapshot.multipliers[p.key] = 1.0
            end
        end
    end

    for _, extra in ipairs(PROFILE_EXTRA_FLATS) do
        local value = safeDriveFlat(drRef, extra.suffix)
        if type(value) == "number" then
            snapshot.extras[extra.key] = value
        end
    end

    return snapshot
end

local function logScore(value, anchor, spread)
    if type(value) ~= "number" or value <= 0 or type(anchor) ~= "number" or anchor <= 0 then
        return 0.0
    end
    return clamp((math.log(value) - math.log(anchor)) / (spread or 0.35), -1.5, 1.5)
end

local function centeredScore(value, center, spread)
    if type(value) ~= "number" or type(center) ~= "number" or type(spread) ~= "number" or spread <= 0 then
        return 0.0
    end
    return clamp((value - center) / spread, -1.5, 1.5)
end

local function appendUniqueTag(tags, tag)
    if type(tag) ~= "string" or tag == "" then return end
    for _, existing in ipairs(tags) do
        if existing == tag then
            return
        end
    end
    tags[#tags + 1] = tag
end

function Tuning.getCurrentVehicleNativeProfile()
    local snapshot = Tuning.getCurrentVehicleDriveSnapshot()
    if type(snapshot) ~= "table" then return nil end

    local base = snapshot.baseline or {}
    local extras = snapshot.extras or {}
    local driveKind = tostring(snapshot.driveKind or "car")
    local kindNoun = driveKind == "bike" and "bike" or "car"
    local punch = ((tonumber(base.powerMult) or 1.0)
        + (tonumber(base.throttleResponse) or 1.0)
        + (tonumber(base.drivelineEffic) or 1.0)) / 3.0
    local brakeFeel = ((tonumber(base.brakeBias) or 1.0)
        + (tonumber(base.engineBraking) or 1.0)) / 2.0
    local tractionSupport = ((tonumber(base.tractionControl) or 1.0)
        + (tonumber(base.spinPrevention) or 1.0)) / 2.0
    local frontSettled = tonumber(base.understeerLevel) or 1.0
    local rearRotation = tonumber(base.oversteerLevel) or 1.0
    local launchSlip = tonumber(base.burnoutThresh) or 1.0
    local torqueSignal = logScore(base.revLimitBehavior, 1800.0, 0.30)
    local brakeStrength = centeredScore(base.brakingPower, 4.5, 1.2) * 0.55 + centeredScore(brakeFeel, 1.0, 0.18) * 0.45
    local tractionScore = centeredScore(tractionSupport, 1.0, 0.16)
    local frontScore = centeredScore(frontSettled, 1.0, 0.16)
    local rearScore = centeredScore(rearRotation, 1.0, 0.16)
    local punchScore = centeredScore(punch, 1.0, 0.16)
    local launchScore = punchScore * 0.55 + torqueSignal * 0.35 + centeredScore(launchSlip, 1.0, 0.20) * 0.10
    local dragScore = centeredScore(extras.airResistanceFactor, 1.0, 0.14)
    local rollScore = centeredScore(extras.turningRollFactor, 1.0, 0.16)

    local tags = {}
    local torqueThreshold = driveKind == "bike" and 0.32 or 0.45
    local brakeThreshold = driveKind == "bike" and 0.25 or 0.35
    local rearLivelyThreshold = driveKind == "bike" and 0.22 or 0.30
    local frontStableThreshold = driveKind == "bike" and 0.18 or 0.25
    local plantedThreshold = driveKind == "bike" and 0.28 or 0.40
    local tractionSensitiveThreshold = driveKind == "bike" and 0.18 or 0.30
    local launchThreshold = driveKind == "bike" and 0.24 or 0.35
    if torqueSignal >= torqueThreshold or launchScore >= (launchThreshold + 0.10) then
        appendUniqueTag(tags, "torque-heavy")
    end
    if brakeStrength >= brakeThreshold then
        appendUniqueTag(tags, "brake-strong")
    end
    if rearScore - frontScore >= rearLivelyThreshold and tractionScore <= 0.35 then
        appendUniqueTag(tags, "rear-lively")
    end
    if frontScore >= frontStableThreshold and rearScore <= 0.15 then
        appendUniqueTag(tags, "front-stable")
    end
    if tractionScore >= plantedThreshold and rearScore <= 0.20 then
        appendUniqueTag(tags, "planted")
    end
    if punchScore >= tractionSensitiveThreshold and tractionScore <= -0.10 then
        appendUniqueTag(tags, "traction-sensitive")
    end
    if launchScore >= launchThreshold then
        appendUniqueTag(tags, "launch-friendly")
    end
    if punchScore <= -0.22 and tractionScore >= 0.05 then
        appendUniqueTag(tags, "stable-but-flat")
    end
    if brakeStrength <= -0.30 and punchScore >= 0.18 then
        appendUniqueTag(tags, "fast-approach")
    end
    if frontScore <= -0.24 and rearScore <= 0.10 then
        appendUniqueTag(tags, "nose-light")
    end
    if frontScore >= 0.12 and rearScore >= 0.05 and tractionScore >= 0.10 then
        appendUniqueTag(tags, "tied-down")
    end
    if dragScore >= 0.35 then
        appendUniqueTag(tags, "draggy-at-speed")
    elseif dragScore <= -0.35 then
        appendUniqueTag(tags, "clean-through-the-air")
    end
    if rollScore >= 0.35 and rearScore >= 0.10 then
        appendUniqueTag(tags, "weight-transfer-happy")
    end
    if #tags == 0 then
        appendUniqueTag(tags, "balanced")
    end

    local leadTag = tags[1] or "balanced"
    local summary = string.format("Base %s reads balanced.", kindNoun)
    if leadTag == "torque-heavy" then
        summary = string.format("Base %s reads torque-heavy, with a strong initial shove before the rest of the platform fully settles.", kindNoun)
    elseif leadTag == "brake-strong" then
        summary = string.format("Base %s reads brake-strong, the kind of package that wants you to win time on entry and release.", kindNoun)
    elseif leadTag == "rear-lively" then
        summary = string.format("Base %s reads rear-lively, willing to rotate if you load it up too abruptly.", kindNoun)
    elseif leadTag == "front-stable" then
        summary = string.format("Base %s reads front-stable, happier taking a set than snapping into rotation.", kindNoun)
    elseif leadTag == "planted" then
        summary = string.format("Base %s reads planted, with stability support doing real work for you.", kindNoun)
    elseif leadTag == "traction-sensitive" then
        summary = string.format("Base %s reads traction-sensitive, easy to over-ask on throttle if you get greedy.", kindNoun)
    elseif leadTag == "launch-friendly" then
        summary = string.format("Base %s reads launch-friendly, like it wants to do its best work in the first hit.", kindNoun)
    elseif leadTag == "stable-but-flat" then
        summary = string.format("Base %s reads stable but flat, tidy enough underneath without a lot of authority in the shove.", kindNoun)
    elseif leadTag == "fast-approach" then
        summary = string.format("Base %s reads fast on approach, happier arriving with speed than asking for patience in the stop.", kindNoun)
    elseif leadTag == "nose-light" then
        summary = string.format("Base %s reads nose-light, more willing to skim across entry than really bite into it.", kindNoun)
    elseif leadTag == "tied-down" then
        summary = string.format("Base %s reads tied down, with the whole platform wanting to stay together before it does anything dramatic.", kindNoun)
    elseif leadTag == "draggy-at-speed" then
        summary = string.format("Base %s reads draggy at speed, stronger in the shove than the long pull.", kindNoun)
    elseif leadTag == "clean-through-the-air" then
        summary = string.format("Base %s reads clean through the air, happier the longer the run gets.", kindNoun)
    elseif leadTag == "weight-transfer-happy" then
        summary = string.format("Base %s reads weight-transfer-happy, so direction changes matter more than raw patience.", kindNoun)
    end

    return {
        vehicleKey = snapshot.vehicleKey,
        vehicleKind = driveKind,
        tags = tags,
        leadTag = leadTag,
        summary = summary,
        scores = {
            torque = torqueSignal,
            brakes = brakeStrength,
            traction = tractionScore,
            front = frontScore,
            rear = rearScore,
            launch = launchScore,
            drag = dragScore,
            roll = rollScore,
        },
        baseline = base,
        extras = extras,
    }
end

-- ── Internal: TweakDB apply/restore ──────────────────────────

function Tuning._captureOriginals(drRef)
    Tuning._originals = {}
    if not drRef then return end
    for _, p in ipairs(PARAMS) do
        if p.suffix then
            local val = TweakDB:GetFlat(TweakDBID.new(drRef, p.suffix))
            if type(val) == "number" then
                Tuning._originals[p.suffix] = val
            end
        end
    end
end

function Tuning._activePartEffects()
    local vehicleKey = Tuning._vehicleKey
    if not vehicleKey or vehicleKey == "" then
        return nil
    end
    local parts = resolveParts()
    if not (parts and parts.getActiveVehicleEffects) then
        return nil
    end
    local ok, effects = pcall(function()
        return parts.getActiveVehicleEffects(vehicleKey)
    end)
    if ok and type(effects) == "table" then
        return effects
    end
    return nil
end

function Tuning._runtimeContext()
    local telemetry = resolveTelemetry()
    local ts = telemetry and telemetry.state or nil
    if type(ts) ~= "table" or not ts.inVehicle then
        return nil
    end
    local speedKph = (tonumber(ts.speed) or 0.0) * 3.6
    local latG = math.abs(tonumber(ts.latG) or 0.0)
    local throttle = clamp(tonumber(ts.throttle) or 0.0, 0.0, 1.0)
    local brake = clamp(tonumber(ts.brake) or 0.0, 0.0, 1.0)
    local carryWindow = 0.0
    if speedKph > 135.0 and throttle > 0.58 and brake < 0.15 then
        carryWindow = clamp((speedKph - 135.0) / 70.0, 0.0, 1.0) * clamp((throttle - 0.58) / 0.42, 0.0, 1.0) * (1.0 - clamp(brake * 2.0, 0.0, 1.0))
    end
    local stabilityWindow = 0.0
    if speedKph > 105.0 and latG < 0.22 then
        stabilityWindow = clamp((speedKph - 105.0) / 85.0, 0.0, 1.0) * (1.0 - clamp(latG / 0.22, 0.0, 1.0)) * (1.0 - clamp(brake * 0.9, 0.0, 0.6))
    end
    return {
        speedKph = speedKph,
        latG = latG,
        throttle = throttle,
        brake = brake,
        carryWindow = carryWindow,
        stabilityWindow = stabilityWindow,
    }
end

function Tuning._runtimeSignature()
    local context = Tuning._runtimeContext()
    if not context then
        return "idle"
    end
    local carryBucket = math.floor((context.carryWindow or 0.0) * 5.0 + 0.0001)
    local stabilityBucket = math.floor((context.stabilityWindow or 0.0) * 5.0 + 0.0001)
    local speedBucket = math.floor((tonumber(context.speedKph) or 0.0) / 20.0)
    return table.concat({ speedBucket, carryBucket, stabilityBucket }, ":")
end

function Tuning._runtimeParamMultipliers(baseEffective)
    local multipliers = {}
    local context = Tuning._runtimeContext()
    if not context then
        return multipliers
    end

    local topEndStrength = math.max(0.0,
        (math.max(0.0, (tonumber(baseEffective.revLimitBehavior) or 1.0) - 1.0) * 0.65)
        + (math.max(0.0, (tonumber(baseEffective.drivelineEffic) or 1.0) - 1.0) * 0.22)
        + (math.max(0.0, (tonumber(baseEffective.powerMult) or 1.0) - 1.0) * 0.13))
    if topEndStrength > 0.0 and (context.carryWindow or 0.0) > 0.0 then
        local carryLift = topEndStrength * context.carryWindow
        multipliers.revLimitBehavior = 1.0 + carryLift * 0.28
        multipliers.drivelineEffic = 1.0 + carryLift * 0.12
        multipliers.powerMult = 1.0 + carryLift * 0.05
    end

    local stabilityStrength = math.max(0.0,
        (math.max(0.0, (tonumber(baseEffective.tractionControl) or 1.0) - 1.0) * 0.42)
        + (math.max(0.0, (tonumber(baseEffective.spinPrevention) or 1.0) - 1.0) * 0.58))
    if stabilityStrength > 0.0 and (context.stabilityWindow or 0.0) > 0.0 then
        local calmLift = stabilityStrength * context.stabilityWindow
        multipliers.tractionControl = 1.0 + calmLift * 0.16
        multipliers.spinPrevention = 1.0 + calmLift * 0.22
        multipliers.understeerLevel = 1.0 + calmLift * 0.08
        multipliers.oversteerLevel = math.max(0.82, 1.0 - calmLift * 0.10)
    end

    return multipliers
end

function Tuning._effectiveParamValue(param, scratchValue, partEffects)
    local rawValue = tonumber(scratchValue)
    if param.key == "idleCreep" then
        local partIdleCreep = tonumber(partEffects and partEffects.additives and partEffects.additives.idleCreep) or 0.0
        return clamp((rawValue or param.default or 0.0) + partIdleCreep, param.min or 0.0, param.max or 1.0)
    end

    local partMultiplier = tonumber(partEffects and partEffects.multipliers and partEffects.multipliers[param.key]) or 1.0
    local effectiveValue = (rawValue or param.default or 1.0) * partMultiplier
    return clamp(effectiveValue, param.min or effectiveValue, param.max or effectiveValue)
end

function Tuning.getEffectiveScratch()
    local effective = {}
    local partEffects = Tuning._activePartEffects()
    local baseEffective = {}
    for _, param in ipairs(PARAMS) do
        baseEffective[param.key] = Tuning._effectiveParamValue(param, Tuning.scratch[param.key], partEffects)
    end
    local runtimeMultipliers = Tuning._runtimeParamMultipliers(baseEffective)
    for _, param in ipairs(PARAMS) do
        local value = baseEffective[param.key]
        if param.key ~= "idleCreep" then
            value = clamp((tonumber(value) or param.default or 1.0) * (tonumber(runtimeMultipliers[param.key]) or 1.0), param.min or (value or 1.0), param.max or (value or 1.0))
        end
        effective[param.key] = value
    end
    return effective
end

function Tuning._applyAll()
    local drRef = Tuning._driveRef
    local partEffects = Tuning._activePartEffects()
    local baseEffective = {}
    for _, p in ipairs(PARAMS) do
        baseEffective[p.key] = Tuning._effectiveParamValue(p, Tuning.scratch[p.key], partEffects)
    end
    local runtimeMultipliers = Tuning._runtimeParamMultipliers(baseEffective)
    for _, p in ipairs(PARAMS) do
        local val = baseEffective[p.key]
        if p.key ~= "idleCreep" then
            val = clamp((tonumber(val) or p.default or 1.0) * (tonumber(runtimeMultipliers[p.key]) or 1.0), p.min or (val or 1.0), p.max or (val or 1.0))
        end
        if p.suffix and drRef then
            local orig = Tuning._originals[p.suffix]
            if type(orig) == "number" then
                pcall(function()
                    TweakDB:SetFlat(TweakDBID.new(drRef, p.suffix), orig * val)
                end)
            end
        elseif p.key == "idleCreep" then
            -- MtSetThrottle is a process-global drivetrain/clutch multiplier,
            -- not an idle-creep setting. Manual Transmission owns this hook.
        end
    end
end

function Tuning._restoreOriginals()
    local drRef = Tuning._driveRef
    if not drRef then return end
    for suffix, orig in pairs(Tuning._originals) do
        pcall(function()
            TweakDB:SetFlat(TweakDBID.new(drRef, suffix), orig)
        end)
    end
    -- Do not touch Manual Transmission's process-global throttle hook here.
    print("[NCM/Tuning] Restored TweakDB values.")
end

-- ── Internal: persistence ─────────────────────────────────────

local function vehicleFileName(vk)
    return "tuning_" .. vk:gsub("[^%w]", "_") .. ".json"
end

function Tuning._loadVehicleData(vk)
    if not resolvePersist() then return {} end
    local data = Persist.load(vehicleFileName(vk))
    return type(data) == "table" and data or {}
end

function Tuning._saveVehicleData(lastProfileName)
    if not resolvePersist() then return end
    local vk = Tuning._vehicleKey
    if not vk then return end
    Persist.save(vehicleFileName(vk), {
        scratch     = Tuning._copySetup(Tuning.scratch),
        profiles    = Tuning._profiles[vk] or {},
        lastProfile = lastProfileName,
    })
end

function Tuning._findProfile(vk, name)
    for _, p in ipairs(Tuning._profiles[vk] or {}) do
        if p.name == name then return Tuning._copySetup(p.setup) end
    end
    return nil
end

function Tuning._copySetup(s)
    local c = {}
    for k, v in pairs(s) do c[k] = v end
    return c
end

return Tuning
