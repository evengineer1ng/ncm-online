-- ============================================================
-- MT_Ecosystem: modules/parts.lua
-- Career-scoped garage inventory and per-vehicle loadouts.
-- Installed parts feed the existing tuning multipliers.
-- ============================================================

local Parts = {}

local PartsData = require("data/parts")
local VehicleSlotProfiles = require("data/vehicle_slot_profiles")

local GARAGE_VERSION = 2
local RIVAL_BUILD_VERSION = 3
local LCG_A = 1664525
local LCG_C = 1013904223
local LCG_M = 4294967296

local TIER_RANK = {
    Gonk = 1,
    Streetkid = 2,
    Solo = 3,
    Fixer = 4,
    Edgerunner = 5,
}

local RIVAL_RARITY_WEIGHTS = {
    Gonk = { Common = 62, Street = 33, Pro = 5, Elite = 0 },
    Streetkid = { Common = 28, Street = 43, Pro = 22, Elite = 7 },
    Solo = { Common = 15, Street = 35, Pro = 34, Elite = 16 },
    Fixer = { Common = 4, Street = 19, Pro = 46, Elite = 31 },
    Edgerunner = { Common = 0, Street = 8, Pro = 41, Elite = 51 },
}

local SHOP_STOCK_SIZE = {
    Gonk = 6,
    Streetkid = 7,
    Solo = 8,
    Fixer = 9,
    Edgerunner = 10,
}

local SHOP_REFRESH_RACE_GAP = 2
local RACE_OFFER_COOLDOWN = 2
local OFFER_EXPIRY_RACES = 3

local SHOP_RARITY_WEIGHTS = {
    Gonk = { Common = 58, Street = 30, Pro = 10, Elite = 2 },
    Streetkid = { Common = 34, Street = 42, Pro = 18, Elite = 6 },
    Solo = { Common = 18, Street = 36, Pro = 31, Elite = 15 },
    Fixer = { Common = 8, Street = 23, Pro = 42, Elite = 27 },
    Edgerunner = { Common = 2, Street = 12, Pro = 38, Elite = 48 },
}

local CATEGORY_STACK_SCALARS = { 1.00, 0.78, 0.62, 0.50, 0.42 }

local PROFILE_AXIS_LABELS = {
    topSpeed = "Top Speed",
    launch = "Launch",
    lowSpeedPull = "Low-Speed Pull",
    midSpeedPull = "Mid-Speed Pull",
    highSpeedPull = "High-Speed Pull",
    brakingStrength = "Braking Power",
    brakingStability = "Braking Stability",
    turnIn = "Turn-In Response",
    midCornerGrip = "Mid-Corner Grip",
    rotation = "Rotation Tendency",
    straightLineStability = "Straight-Line Stability",
    recoveryControl = "Recovery Control",
    crawlResistance = "Crawl Resistance",
}

local CANONICAL_EFFECT_ORDER = {
    "launch",
    "pull",
    "topEnd",
    "brakingBite",
    "rotation",
    "grip",
    "stability",
    "recovery",
}

local CANONICAL_EFFECT_LABELS = {
    launch = "Launch",
    pull = "Pull",
    topEnd = "Top-End",
    brakingBite = "Braking Bite",
    rotation = "Rotation",
    grip = "Grip",
    stability = "Stability",
    recovery = "Recovery",
}

local PRIMARY_PROFILE_AXES = {
    "topSpeed",
    "launch",
    "lowSpeedPull",
    "midSpeedPull",
    "highSpeedPull",
    "brakingStrength",
    "brakingStability",
    "turnIn",
    "midCornerGrip",
    "rotation",
    "straightLineStability",
    "recoveryControl",
    "crawlResistance",
}

local OFFER_RARITY_WEIGHTS = {
    hookup = {
        Gonk = { Common = 40, Street = 42, Pro = 15, Elite = 3 },
        Streetkid = { Common = 22, Street = 44, Pro = 24, Elite = 10 },
        Solo = { Common = 10, Street = 35, Pro = 36, Elite = 19 },
        Fixer = { Common = 4, Street = 22, Pro = 43, Elite = 31 },
        Edgerunner = { Common = 0, Street = 14, Pro = 39, Elite = 47 },
    },
    promotion = {
        Gonk = { Common = 20, Street = 50, Pro = 24, Elite = 6 },
        Streetkid = { Common = 8, Street = 42, Pro = 34, Elite = 16 },
        Solo = { Common = 2, Street = 28, Pro = 43, Elite = 27 },
        Fixer = { Common = 0, Street = 16, Pro = 42, Elite = 42 },
        Edgerunner = { Common = 0, Street = 8, Pro = 34, Elite = 58 },
    },
}

local DEFAULT_DRIVER_HARDWARE = {
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

Parts.SLOT_ORDER = PartsData.SLOT_ORDER
Parts.SLOTS = PartsData.SLOTS
Parts.RARITY_ORDER = PartsData.RARITY_ORDER

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function clamp(value, minValue, maxValue)
    if type(value) ~= "number" then return minValue end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function clamp01(value)
    return clamp(value, 0.0, 1.0)
end

local function resolveCareers()
    return MTE and MTE.Careers or nil
end

local function notifyGarageChanged(vehicleKey)
    local tuning = MTE and MTE.Tuning or nil
    if not tuning then return end
    if tuning._vehicleKey and vehicleKey and tuning._vehicleKey ~= vehicleKey then
        return
    end
    if tuning.markDirty then
        tuning.markDirty()
    else
        tuning.dirty = true
    end
end

local function nextFloat(seed)
    local s = math.floor((seed or 0) % LCG_M)
    s = math.floor((s * LCG_A + LCG_C) % LCG_M)
    return s, (s / LCG_M)
end

local function hashString(text)
    local s = tostring(text or "")
    local hash = 0
    for i = 1, #s do
        hash = math.floor((hash * 131 + string.byte(s, i)) % LCG_M)
    end
    return hash
end

local function deterministicShuffle(list, seed)
    local out = {}
    for i, value in ipairs(list or {}) do
        out[i] = value
    end
    for i = #out, 2, -1 do
        local roll
        seed, roll = nextFloat(seed + i)
        local j = math.max(1, math.min(i, math.floor(roll * i) + 1))
        out[i], out[j] = out[j], out[i]
    end
    return seed, out
end

local function normalizeSlotProfileCounts(counts)
    local normalized = {}
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        normalized[slotId] = math.max(0, math.floor(tonumber(counts and counts[slotId]) or 0))
    end
    return normalized
end

local function totalSlotCount(slotProfile)
    local total = 0
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        total = total + math.max(0, math.floor(tonumber(slotProfile and slotProfile[slotId]) or 0))
    end
    return total
end

local function totalInstalledCount(installedByCategory)
    local total = 0
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        total = total + #(installedByCategory and installedByCategory[slotId] or {})
    end
    return total
end

local function buildInstalledPrimaryMap(installedByCategory)
    local installed = {}
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        local entries = installedByCategory and installedByCategory[slotId] or nil
        if type(entries) == "table" and entries[1] then
            installed[slotId] = entries[1]
        end
    end
    return installed
end

local function eachInstalledEntry(installedCollection, visitor)
    if type(installedCollection) ~= "table" or type(visitor) ~= "function" then
        return
    end
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        local value = installedCollection[slotId]
        if type(value) == "table" and (value.partId or value.instanceId or value.name) then
            visitor(slotId, 1, value)
        elseif type(value) == "table" then
            for index, entry in ipairs(value) do
                if entry then
                    visitor(slotId, index, entry)
                end
            end
        end
    end
end

local function buildVehicleSlotProfile(career, vehicleKey, opts)
    local options = type(opts) == "table" and deepCopy(opts) or {}
    local seed = hashString(vehicleKey) + math.floor(tonumber(career and career.seed) or 0)
    options.seed = math.floor((tonumber(options.seed) or 0) + seed)
    return VehicleSlotProfiles.resolve(vehicleKey, options)
end

local function buildNeutralEffects()
    local effects = {
        multipliers = {},
        additives = {},
    }
    for _, key in ipairs(PartsData.EFFECT_KEYS) do
        if key == "idleCreep" then
            effects.additives[key] = 0.0
        else
            effects.multipliers[key] = 1.0
            effects.additives[key] = 0.0
        end
    end
    return effects
end

local function metricGain(mult, key)
    return (tonumber(mult and mult[key]) or 1.0) - 1.0
end

local function makeWeightCopy(weights)
    local copy = {}
    for _, rarity in ipairs(PartsData.RARITY_ORDER) do
        copy[rarity] = math.max(0, tonumber(weights and weights[rarity]) or 0)
    end
    return copy
end

local function buildVirtualEntry(definition, condition)
    if type(definition) ~= "table" then return nil end
    return {
        partId = definition.id,
        slot = definition.slot,
        slotLabel = (PartsData.SLOTS[definition.slot] and PartsData.SLOTS[definition.slot].label) or definition.slot,
        family = definition.family,
        familyLabel = PartsData.familyLabel(definition),
        focus = definition.focus,
        tradeoff = definition.tradeoff,
        name = definition.name,
        rarity = definition.rarity,
        price = definition.price or 0,
        description = definition.description or "",
        condition = clamp(condition or 1.0, 0.55, 1.0),
        source = "rival_build",
        modifiers = deepCopy(definition.modifiers or {}),
        additives = deepCopy(definition.additives or {}),
    }
end

local function categoryStackScalar(index)
    local base = CATEGORY_STACK_SCALARS[index]
    if base then
        return base
    end
    local tail = CATEGORY_STACK_SCALARS[#CATEGORY_STACK_SCALARS] or 0.42
    return math.max(0.34, tail - ((index - #CATEGORY_STACK_SCALARS) * 0.04))
end

local function composeEffectsFromInstalled(installed)
    local effects = buildNeutralEffects()
    local familyCountsBySlot = {}
    eachInstalledEntry(installed, function(slotId, index, item)
        if item then
            familyCountsBySlot[slotId] = familyCountsBySlot[slotId] or {}
            local familyCounts = familyCountsBySlot[slotId]
            local familyKey = tostring(item.family or item.partId or "")
            local familyRepeats = familyKey ~= "" and math.max(0, tonumber(familyCounts[familyKey]) or 0) or 0
            local stackScalar = categoryStackScalar(index) * math.max(0.60, 1.0 - (familyRepeats * 0.16))
            local condition = clamp(item.condition or 1.0, 0.55, 1.0)
            for key, value in pairs(item.modifiers or {}) do
                local scaled = 1.0 + (((value or 1.0) - 1.0) * condition * stackScalar)
                effects.multipliers[key] = (effects.multipliers[key] or 1.0) * scaled
            end
            for key, value in pairs(item.additives or {}) do
                effects.additives[key] = (effects.additives[key] or 0.0) + ((value or 0.0) * condition * stackScalar)
            end
            if familyKey ~= "" then
                familyCounts[familyKey] = familyRepeats + 1
            end
        end
    end)
    return effects
end

local function summarizePerformance(effects)
    local mult = effects and effects.multipliers or {}
    local add = effects and effects.additives or {}

    local function gain(key)
        return (tonumber(mult[key]) or 1.0) - 1.0
    end

    local powerGain = gain("powerMult") * 1.35
        + gain("throttleResponse") * 0.76
        + gain("revLimitBehavior") * 0.55
        + gain("drivelineEffic") * 0.88
    local launchGain = gain("throttleResponse") * 1.14
        + gain("drivelineEffic") * 0.72
        + gain("burnoutThresh") * 0.54
        + (tonumber(add.idleCreep) or 0.0) * 2.30
    local brakeGain = gain("brakingPower") * 0.96 + gain("brakeBias") * 0.46
    local agilityGain = (1.0 - (tonumber(mult.understeerLevel) or 1.0)) * 0.82
        + gain("oversteerLevel") * 0.38
        + gain("engineBraking") * 0.18
    local stabilityGain = gain("tractionControl") * 0.48
        + gain("spinPrevention") * 0.72
        + gain("engineBraking") * 0.16
        + brakeGain * 0.10
    local controlGain = agilityGain * 0.55 + brakeGain * 0.25 + stabilityGain * 0.35
    local reliabilityGain = stabilityGain * 0.55 + brakeGain * 0.18 + gain("tractionControl") * 0.15

    return {
        sprintScale = clamp(1.0 + powerGain * 0.50 + brakeGain * 0.20 + agilityGain * 0.18 + stabilityGain * 0.16, 0.85, 1.25),
        dragScale = clamp(1.0 + powerGain * 0.60 + launchGain * 0.30 + stabilityGain * 0.08, 0.85, 1.28),
        knockoutScale = clamp(1.0 + powerGain * 0.18 + brakeGain * 0.28 + agilityGain * 0.28 + stabilityGain * 0.26, 0.85, 1.25),
        liveSpeedScale = clamp(1.0 + powerGain * 0.46 + launchGain * 0.12 + agilityGain * 0.08 + stabilityGain * 0.06, 0.82, 1.22),
        launchScale = clamp(1.0 + launchGain * 0.55 + powerGain * 0.16 + stabilityGain * 0.10, 0.92, 1.20),
        controlScale = clamp(1.0 + controlGain * 0.50, 0.92, 1.16),
        reliabilityScale = clamp(1.0 + reliabilityGain * 0.42, 0.93, 1.14),
        confidence = clamp(1.0 + powerGain * 0.12 + launchGain * 0.05 + controlGain * 0.08 + stabilityGain * 0.07, 0.95, 1.10),
    }
end

local function summarizeBuildProfile(effects, performance)
    local mult = effects and effects.multipliers or {}
    local add = effects and effects.additives or {}
    local perf = performance or summarizePerformance(effects)

    local profile = {
        topSpeed = clamp(1.0 + metricGain(mult, "powerMult") * 0.20 + metricGain(mult, "revLimitBehavior") * 0.65 + metricGain(mult, "drivelineEffic") * 0.12, 0.86, 1.30),
        launch = clamp(1.0 + metricGain(mult, "throttleResponse") * 0.44 + metricGain(mult, "drivelineEffic") * 0.22 + metricGain(mult, "burnoutThresh") * 0.32 + (tonumber(add.idleCreep) or 0.0) * 2.20, 0.88, 1.35),
        lowSpeedPull = clamp(1.0 + metricGain(mult, "powerMult") * 0.38 + metricGain(mult, "throttleResponse") * 0.28 + metricGain(mult, "drivelineEffic") * 0.22, 0.88, 1.30),
        midSpeedPull = clamp(1.0 + metricGain(mult, "powerMult") * 0.30 + metricGain(mult, "throttleResponse") * 0.18 + metricGain(mult, "drivelineEffic") * 0.28 + metricGain(mult, "revLimitBehavior") * 0.12, 0.88, 1.30),
        highSpeedPull = clamp(1.0 + metricGain(mult, "powerMult") * 0.34 + metricGain(mult, "revLimitBehavior") * 0.42 + metricGain(mult, "drivelineEffic") * 0.18, 0.88, 1.30),
        brakingStrength = clamp(1.0 + metricGain(mult, "brakingPower") * 0.80 + metricGain(mult, "brakeBias") * 0.20, 0.88, 1.28),
        brakingStability = clamp(1.0 + metricGain(mult, "brakeBias") * 0.40 + metricGain(mult, "engineBraking") * 0.22 + metricGain(mult, "spinPrevention") * 0.16, 0.88, 1.22),
        turnIn = clamp(1.0 + ((1.0 - (tonumber(mult.understeerLevel) or 1.0)) * 0.90) + metricGain(mult, "brakeBias") * 0.08, 0.84, 1.26),
        midCornerGrip = clamp(1.0 + metricGain(mult, "tractionControl") * 0.14 + metricGain(mult, "spinPrevention") * 0.28 + ((1.0 - (tonumber(mult.understeerLevel) or 1.0)) * 0.28) - math.max(0.0, metricGain(mult, "oversteerLevel")) * 0.10, 0.84, 1.28),
        rotation = clamp(1.0 + metricGain(mult, "oversteerLevel") * 0.62 + ((1.0 - (tonumber(mult.understeerLevel) or 1.0)) * 0.24) - metricGain(mult, "tractionControl") * 0.08, 0.82, 1.28),
        straightLineStability = clamp(1.0 + metricGain(mult, "tractionControl") * 0.34 + metricGain(mult, "spinPrevention") * 0.56 + metricGain(mult, "drivelineEffic") * 0.05 - math.max(0.0, metricGain(mult, "oversteerLevel")) * 0.14, 0.84, 1.28),
        recoveryControl = clamp(1.0 + metricGain(mult, "spinPrevention") * 0.42 + metricGain(mult, "tractionControl") * 0.24 + metricGain(mult, "engineBraking") * 0.18 + (tonumber(add.idleCreep) or 0.0) * 1.40, 0.88, 1.26),
        crawlResistance = clamp(1.0 + (tonumber(add.idleCreep) or 0.0) * 4.60 + metricGain(mult, "burnoutThresh") * 0.18 + metricGain(mult, "drivelineEffic") * 0.10, 0.88, 1.36),
        sprintScale = tonumber(perf.sprintScale) or 1.0,
        dragScale = tonumber(perf.dragScale) or 1.0,
        controlScale = tonumber(perf.controlScale) or 1.0,
        reliabilityScale = tonumber(perf.reliabilityScale) or 1.0,
    }
    return profile
end

local function summarizeCanonicalEffects(profile)
    local data = profile or {}
    local values = {
        launch = clamp(1.0 + ((tonumber(data.launch) or 1.0) - 1.0) * 0.78 + ((tonumber(data.crawlResistance) or 1.0) - 1.0) * 0.22, 0.88, 1.34),
        pull = clamp(1.0 + ((tonumber(data.lowSpeedPull) or 1.0) - 1.0) * 0.28 + ((tonumber(data.midSpeedPull) or 1.0) - 1.0) * 0.48 + ((tonumber(data.highSpeedPull) or 1.0) - 1.0) * 0.24, 0.88, 1.30),
        topEnd = clamp(1.0 + ((tonumber(data.topSpeed) or 1.0) - 1.0) * 0.58 + ((tonumber(data.highSpeedPull) or 1.0) - 1.0) * 0.42, 0.86, 1.30),
        brakingBite = clamp(1.0 + ((tonumber(data.brakingStrength) or 1.0) - 1.0) * 0.84 + ((tonumber(data.brakingStability) or 1.0) - 1.0) * 0.16, 0.88, 1.28),
        rotation = clamp(1.0 + ((tonumber(data.turnIn) or 1.0) - 1.0) * 0.52 + ((tonumber(data.rotation) or 1.0) - 1.0) * 0.48, 0.84, 1.28),
        grip = clamp(1.0 + ((tonumber(data.midCornerGrip) or 1.0) - 1.0) * 0.82 + ((tonumber(data.turnIn) or 1.0) - 1.0) * 0.08 + ((tonumber(data.straightLineStability) or 1.0) - 1.0) * 0.10, 0.84, 1.28),
        stability = clamp(1.0 + ((tonumber(data.straightLineStability) or 1.0) - 1.0) * 0.58 + ((tonumber(data.brakingStability) or 1.0) - 1.0) * 0.24 + ((tonumber(data.recoveryControl) or 1.0) - 1.0) * 0.18, 0.84, 1.28),
        recovery = clamp(1.0 + ((tonumber(data.recoveryControl) or 1.0) - 1.0) * 0.80 + ((tonumber(data.crawlResistance) or 1.0) - 1.0) * 0.20, 0.88, 1.28),
    }

    local effects = {}
    local ordered = {}
    for _, effectId in ipairs(CANONICAL_EFFECT_ORDER) do
        local value = tonumber(values[effectId]) or 1.0
        local entry = {
            axis = effectId,
            label = CANONICAL_EFFECT_LABELS[effectId] or effectId,
            value = value,
            delta = value - 1.0,
        }
        effects[effectId] = entry
        ordered[#ordered + 1] = entry
    end

    local ranked = {}
    for _, entry in ipairs(ordered) do
        ranked[#ranked + 1] = entry
    end
    table.sort(ranked, function(a, b)
        if a.delta ~= b.delta then
            return a.delta > b.delta
        end
        return tostring(a.axis or "") < tostring(b.axis or "")
    end)

    local strengths = {}
    for _, entry in ipairs(ranked) do
        if entry.delta >= 0.02 then
            strengths[#strengths + 1] = entry
        end
        if #strengths >= 3 then
            break
        end
    end

    local weaknesses = {}
    for index = #ranked, 1, -1 do
        local entry = ranked[index]
        if entry.delta <= -0.015 then
            weaknesses[#weaknesses + 1] = entry
        end
        if #weaknesses >= 2 then
            break
        end
    end

    return {
        effects = effects,
        ordered = ordered,
        strengths = strengths,
        weaknesses = weaknesses,
    }
end

local function weightedProfileFit(profile, weights, minValue, maxValue)
    local sum = 0.0
    local totalWeight = 0.0
    for axis, weight in pairs(weights or {}) do
        local delta = (tonumber(profile and profile[axis]) or 1.0) - 1.0
        sum = sum + (delta * weight)
        totalWeight = totalWeight + weight
    end
    if totalWeight <= 0 then
        return 1.0
    end
    return clamp(1.0 + (sum / totalWeight), minValue or 0.88, maxValue or 1.24)
end

local function summarizeRaceFits(profile)
    return {
        drag = weightedProfileFit(profile, {
            launch = 0.26,
            lowSpeedPull = 0.18,
            midSpeedPull = 0.14,
            straightLineStability = 0.16,
            crawlResistance = 0.14,
            highSpeedPull = 0.12,
        }, 0.88, 1.24),
        sprint = weightedProfileFit(profile, {
            launch = 0.10,
            midSpeedPull = 0.14,
            brakingStrength = 0.18,
            brakingStability = 0.15,
            turnIn = 0.12,
            midCornerGrip = 0.16,
            rotation = 0.06,
            recoveryControl = 0.09,
        }, 0.88, 1.22),
        knockout = weightedProfileFit(profile, {
            brakingStrength = 0.18,
            brakingStability = 0.16,
            turnIn = 0.14,
            midCornerGrip = 0.18,
            straightLineStability = 0.10,
            recoveryControl = 0.14,
            crawlResistance = 0.10,
        }, 0.88, 1.22),
        longRoute = weightedProfileFit(profile, {
            topSpeed = 0.18,
            highSpeedPull = 0.22,
            brakingStability = 0.12,
            straightLineStability = 0.20,
            recoveryControl = 0.12,
            midCornerGrip = 0.08,
            brakingStrength = 0.08,
        }, 0.88, 1.23),
    }
end

local function summarizeAxisTradeoffs(profile)
    local scored = {}
    for _, axis in ipairs(PRIMARY_PROFILE_AXES) do
        scored[#scored + 1] = {
            axis = axis,
            label = PROFILE_AXIS_LABELS[axis] or axis,
            value = tonumber(profile and profile[axis]) or 1.0,
            delta = (tonumber(profile and profile[axis]) or 1.0) - 1.0,
        }
    end
    table.sort(scored, function(a, b)
        if a.delta ~= b.delta then
            return a.delta > b.delta
        end
        return tostring(a.axis or "") < tostring(b.axis or "")
    end)

    local strengths = {}
    for _, entry in ipairs(scored) do
        if entry.delta >= 0.025 then
            strengths[#strengths + 1] = entry
        end
        if #strengths >= 3 then
            break
        end
    end

    local weaknesses = {}
    for index = #scored, 1, -1 do
        local entry = scored[index]
        if entry.delta <= -0.015 then
            weaknesses[#weaknesses + 1] = entry
        end
        if #weaknesses >= 2 then
            break
        end
    end

    return strengths, weaknesses
end

local function summarizeBuildIdentity(profile)
    local tags = {}
    local function add(tag)
        if type(tag) ~= "string" or tag == "" then
            return
        end
        for _, existing in ipairs(tags) do
            if existing == tag then
                return
            end
        end
        tags[#tags + 1] = tag
    end

    if (profile.highSpeedPull or 1.0) >= 1.08 or (profile.topSpeed or 1.0) >= 1.08 then
        add("High-Speed")
    end
    if (profile.launch or 1.0) >= 1.08 and (profile.lowSpeedPull or 1.0) >= 1.05 then
        add("Burst")
    end
    if (profile.brakingStrength or 1.0) >= 1.07 and (profile.brakingStability or 1.0) >= 1.04 then
        add("Brake-Heavy")
    end
    if (profile.midCornerGrip or 1.0) >= 1.06 and (profile.turnIn or 1.0) >= 1.04 then
        add("Grip Car")
    end
    if (profile.turnIn or 1.0) >= 1.05 and (profile.rotation or 1.0) >= 1.07 then
        add("Rotation")
    end
    if (profile.straightLineStability or 1.0) >= 1.07 and (profile.recoveryControl or 1.0) >= 1.05 then
        add("Planted")
    end
    if (profile.crawlResistance or 1.0) >= 1.08 or (profile.recoveryControl or 1.0) >= 1.08 then
        add("Recovery-Safe")
    end
    if (profile.rotation or 1.0) >= 1.10 and (profile.straightLineStability or 1.0) <= 0.99 then
        add("Unstable")
    end
    if (profile.launch or 1.0) >= 1.08 and (profile.highSpeedPull or 1.0) >= 1.04 and (profile.straightLineStability or 1.0) <= 1.00 then
        add("Volatile")
    end
    if (profile.launch or 1.0) >= 1.09 and (profile.highSpeedPull or 1.0) <= 1.01 then
        add("Launch Specialist")
    end
    if (profile.highSpeedPull or 1.0) >= 1.09 and (profile.launch or 1.0) <= 1.01 then
        add("Highway")
    end

    if #tags == 0 then
        add("Balanced")
    end

    local headline = tags[1]
    if tags[2] then
        headline = string.format("%s / %s", tags[1], tags[2])
    end

    return {
        headline = headline,
        tags = tags,
    }
end

local function pickWeightedRarity(weights, seed)
    local total = 0
    for _, rarity in ipairs(PartsData.RARITY_ORDER) do
        total = total + (weights[rarity] or 0)
    end
    if total <= 0 then return "Common" end
    local roll
    seed, roll = nextFloat(seed)
    local target = roll * total
    local acc = 0
    for _, rarity in ipairs(PartsData.RARITY_ORDER) do
        acc = acc + (weights[rarity] or 0)
        if acc >= target then
            return rarity, seed
        end
    end
    return PartsData.RARITY_ORDER[#PartsData.RARITY_ORDER], seed
end

local function rarityWeightsForRival(tier, prestige, quality)
    local weights = makeWeightCopy(RIVAL_RARITY_WEIGHTS[tier] or RIVAL_RARITY_WEIGHTS.Gonk)
    if prestige >= 4 then
        weights.Pro = weights.Pro + 6
        weights.Elite = weights.Elite + 8
        weights.Common = math.max(0, weights.Common - 8)
    elseif prestige <= 2 then
        weights.Common = weights.Common + 8
        weights.Elite = math.max(0, weights.Elite - 4)
    end
    if quality >= 0.72 then
        weights.Pro = weights.Pro + 4
        weights.Elite = weights.Elite + 4
        weights.Common = math.max(0, weights.Common - 4)
    elseif quality <= 0.45 then
        weights.Common = weights.Common + 6
        weights.Elite = math.max(0, weights.Elite - 3)
    end
    return weights
end

local function pickRivalSlotDefinition(slotId, tier, prestige, quality, seed)
    local targetRarity
    targetRarity, seed = pickWeightedRarity(rarityWeightsForRival(tier, prestige, quality), seed)

    local targetRank = PartsData.rarityRank(targetRarity)
    local bestDistance = math.huge
    local shortlist = {}
    for _, definition in ipairs(PartsData.bySlot(slotId)) do
        local distance = math.abs(PartsData.rarityRank(definition.rarity) - targetRank)
        if distance < bestDistance then
            bestDistance = distance
            shortlist = { definition }
        elseif distance == bestDistance then
            shortlist[#shortlist + 1] = definition
        end
    end
    if #shortlist == 0 then
        shortlist = PartsData.bySlot(slotId)
    end
    if #shortlist == 0 then
        return nil, seed
    end

    local shuffled
    seed, shuffled = deterministicShuffle(shortlist, seed + targetRank + #shortlist)
    return shuffled[1], seed
end

local function getDriverBuildSeed(driver, careerSeed)
    local base = math.floor((careerSeed or 0) % LCG_M)
    base = math.floor((base + hashString(driver and driver.id)) % LCG_M)
    base = math.floor((base + hashString(driver and driver.vehicleSignature)) % LCG_M)
    base = math.floor((base + ((tonumber(driver and driver.vehiclePrestige) or 0) * 977)) % LCG_M)
    return base
end

local function buildRivalInstalledParts(driver, careerSeed)
    local tier = tostring(driver and (driver.currentTier or driver.tier) or "Gonk")
    local tierRank = TIER_RANK[tier] or 1
    local prestige = math.max(1, math.min(5, math.floor(tonumber(driver and driver.vehiclePrestige) or 2)))
    local pace = clamp(tonumber(driver and driver.pace) or 1.0, 0.65, 1.45)
    local quality = clamp01((pace - 0.72) / 0.68)
    local sympathy = clamp01(driver and driver.driverStats and driver.driverStats.vehicle_sympathy or 0.5)
    local control = clamp01(driver and driver.driverStats and driver.driverStats.control_balance or 0.5)
    local vehicleKey = tostring(driver and (driver.vehicleSignature or driver.vehicleId or driver.vehicleKey or driver.id) or "rival_vehicle")
    local seed = getDriverBuildSeed(driver, careerSeed)
    local profile = buildVehicleSlotProfile(nil, vehicleKey, {
        prestige = prestige,
        seed = seed,
        kind = tostring(driver and driver.vehicleKind or ""),
    })

    local installed = {}
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        installed[slotId] = {}
        local capacity = math.max(0, math.floor(tonumber(profile and profile.counts and profile.counts[slotId]) or 0))
        for index = 1, capacity do
            local definition
            definition, seed = pickRivalSlotDefinition(slotId, tier, prestige, quality, seed + (index * 17) + hashString(slotId))
            if definition then
                local roll
                seed, roll = nextFloat(seed + index * 29)
                local condition = clamp(0.70 + tierRank * 0.04 + (prestige - 1) * 0.025 + sympathy * 0.05 + control * 0.03 + roll * 0.10, 0.68, 1.0)
                installed[slotId][#installed[slotId] + 1] = buildVirtualEntry(definition, condition)
            end
        end
    end

    return installed, profile
end

local function ensureStats(career)
    local changed = false
    career.stats = type(career.stats) == "table" and career.stats or {}
    local statDefaults = {
        partsCollected = 0,
        partRewards = 0,
        installActions = 0,
    }
    for key, value in pairs(statDefaults) do
        if type(career.stats[key]) ~= "number" then
            career.stats[key] = value
            changed = true
        end
    end
    return changed
end

local function ensureGarage(career)
    local changed = false
    if type(career.garage) ~= "table" then
        career.garage = {}
        changed = true
    end
    local garage = career.garage
    if garage.version ~= GARAGE_VERSION then
        garage.version = GARAGE_VERSION
        changed = true
    end
    if type(garage.inventory) ~= "table" then
        garage.inventory = {}
        changed = true
    end
    if type(garage.vehicles) ~= "table" then
        garage.vehicles = {}
        changed = true
    end
    if type(garage.meta) ~= "table" then
        garage.meta = {}
        changed = true
    end
    if type(garage.meta.nextPartInstanceId) ~= "number" then
        garage.meta.nextPartInstanceId = 1
        changed = true
    end
    if type(garage.meta.shopState) ~= "table" then
        garage.meta.shopState = { refreshAtRace = 0, items = {} }
        changed = true
    end
    if type(garage.meta.offerState) ~= "table" then
        garage.meta.offerState = {
            nextOfferId = 1,
            pending = {},
            lastRaceOfferAtRace = -99,
            lastRaceOfferSessionId = "",
            lastPromotionTier = "",
        }
        changed = true
    end
    return garage, changed
end

local function ensureVehicleState(career, vehicleKey)
    local garage = career.garage
    local vehicleState = garage.vehicles[vehicleKey]
    if type(vehicleState) ~= "table" then
        vehicleState = { installedByCategory = {}, slotProfile = nil, lastTouchedAt = 0 }
        garage.vehicles[vehicleKey] = vehicleState
    end

    if type(vehicleState.installedByCategory) ~= "table" then
        vehicleState.installedByCategory = {}
    end
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        if type(vehicleState.installedByCategory[slotId]) ~= "table" then
            vehicleState.installedByCategory[slotId] = {}
        end
    end

    if type(vehicleState.installed) == "table" then
        for _, slotId in ipairs(PartsData.SLOT_ORDER) do
            local legacyInstanceId = vehicleState.installed[slotId]
            if legacyInstanceId and #vehicleState.installedByCategory[slotId] == 0 then
                vehicleState.installedByCategory[slotId][1] = legacyInstanceId
            end
        end
        vehicleState.installed = nil
    end

    local resolvedProfile = buildVehicleSlotProfile(career, vehicleKey, vehicleState.slotProfileMeta)
    local slotProfile = normalizeSlotProfileCounts(vehicleState.slotProfile)
    if totalSlotCount(slotProfile) <= 0 then
        slotProfile = normalizeSlotProfileCounts(resolvedProfile and resolvedProfile.counts or nil)
    end
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        local occupied = #(vehicleState.installedByCategory[slotId] or {})
        if slotProfile[slotId] < occupied then
            slotProfile[slotId] = occupied
        end
    end

    vehicleState.slotProfile = slotProfile
    vehicleState.slotProfileMeta = {
        templateId = resolvedProfile and resolvedProfile.templateId or nil,
        prestige = resolvedProfile and resolvedProfile.prestige or nil,
        vehicleKind = resolvedProfile and resolvedProfile.vehicleKind or nil,
        totalSlots = totalSlotCount(slotProfile),
    }
    vehicleState.lastTouchedAt = os.time()
    return vehicleState
end

local function ownsPartId(career, partId)
    for _, instance in pairs(career.garage.inventory or {}) do
        if instance.partId == partId then
            return true
        end
    end
    return false
end

local function createInstance(career, definition, opts)
    local garage = career.garage
    local meta = garage.meta
    local nextId = math.max(1, math.floor(meta.nextPartInstanceId or 1))
    meta.nextPartInstanceId = nextId + 1

    local instanceId = string.format("prt_%s_%04d", tostring(career.seed or 0), nextId)
    local instance = {
        instanceId = instanceId,
        partId = definition.id,
        acquiredAt = os.time(),
        condition = clamp((opts and opts.condition) or 1.0, 0.55, 1.0),
        source = (opts and opts.source) or "unknown",
        installedVehicleKey = nil,
        installedCategory = nil,
        installedIndex = nil,
    }
    garage.inventory[instanceId] = instance
    career.stats.partsCollected = (career.stats.partsCollected or 0) + 1
    if instance.source == "race_reward" then
        career.stats.partRewards = (career.stats.partRewards or 0) + 1
    end
    return instance
end

local function buildEntry(instance)
    if type(instance) ~= "table" then return nil end
    local definition = PartsData.get(instance.partId)
    if not definition then return nil end
    return {
        instanceId = instance.instanceId,
        partId = instance.partId,
        slot = definition.slot,
        slotLabel = (PartsData.SLOTS[definition.slot] and PartsData.SLOTS[definition.slot].label) or definition.slot,
        family = definition.family,
        familyLabel = PartsData.familyLabel(definition),
        focus = definition.focus,
        tradeoff = definition.tradeoff,
        name = definition.name,
        rarity = definition.rarity,
        price = definition.price or 0,
        description = definition.description or "",
        condition = clamp(instance.condition or 1.0, 0.55, 1.0),
        source = instance.source,
        installedVehicleKey = instance.installedVehicleKey,
        installedCategory = instance.installedCategory,
        installedIndex = instance.installedIndex,
        modifiers = deepCopy(definition.modifiers or {}),
        additives = deepCopy(definition.additives or {}),
    }
end

local function seedStarterInventory(career)
    local garage = career.garage
    local seed = math.floor((career.seed or os.time()) % LCG_M)
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        local shuffled
        seed, shuffled = deterministicShuffle(PartsData.bySlot(slotId), seed)
        local count = math.min(2, #shuffled)
        for i = 1, count do
            local roll
            seed, roll = nextFloat(seed + i)
            createInstance(career, shuffled[i], {
                source = "starter_pack",
                condition = 0.90 + (roll * 0.10),
            })
        end
    end
    garage.meta.seededStarter = true
    garage.meta.lastReward = {
        kind = "starter_pack",
        name = "Career starter stash",
        acquiredAt = os.time(),
    }
end

local function countEntries(list)
    local n = 0
    for _ in pairs(list or {}) do n = n + 1 end
    return n
end

local function currentRaceCount(career)
    local stats = career and career.stats or {}
    return math.max(0, math.floor(tonumber(stats.racesFinished or stats.racesRun or 0) or 0))
end

local function computeLegacyRating(installed)
    local rating = 0
    eachInstalledEntry(installed, function(_, _, item)
        if item then
            rating = rating + (PartsData.rarityRank(item.rarity) * 24)
            for _, value in pairs(item.modifiers or {}) do
                rating = rating + (math.abs((value or 1.0) - 1.0) * 260)
            end
            for _, value in pairs(item.additives or {}) do
                rating = rating + (math.abs(value or 0.0) * 200)
            end
        end
    end)
    return math.floor(rating + 0.5)
end

local function raceFitForConfig(summary, config)
    local fits = summary and summary.raceFits or nil
    local cfg = type(config) == "table" and config or {}
    local raceType = tostring(cfg.raceType or "sprint")
    if raceType == "drag" then
        return tonumber(fits and fits.drag) or 1.0
    end
    if raceType == "knockout" then
        return tonumber(fits and fits.knockout) or 1.0
    end
    if raceType == "endurance" or (tonumber(cfg.lapCount) or 1) > 1 then
        return tonumber(fits and fits.longRoute) or tonumber(fits and fits.sprint) or 1.0
    end
    return weightedProfileFit(fits, { sprint = 0.60, longRoute = 0.40 }, 0.88, 1.22)
end

local function sortInventory(a, b)
    local rarA = PartsData.rarityRank(a.rarity)
    local rarB = PartsData.rarityRank(b.rarity)
    if rarA ~= rarB then return rarA > rarB end
    if (a.condition or 0) ~= (b.condition or 0) then return (a.condition or 0) > (b.condition or 0) end
    if a.slot ~= b.slot then return a.slot < b.slot end
    return (a.name or "") < (b.name or "")
end

local function saveCareers()
    local careers = resolveCareers()
    if careers and careers.save then
        careers.save()
    end
end

local function shopSlotWeights(career, vehicleKey)
    local weights = {}
    local profile = vehicleKey and Parts.getVehicleSlotProfile and Parts.getVehicleSlotProfile(career, vehicleKey) or nil
    local counts = profile and profile.counts or nil
    local total = profile and tonumber(profile.totalSlots or 0) or 0
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        local base = counts and tonumber(counts[slotId]) or 0
        weights[slotId] = total > 0 and ((base + 1) / (total + #PartsData.SLOT_ORDER)) or 1.0
    end
    return weights
end

local function generateShopStock(career, vehicleKey)
    local tier = tostring(career and career.tier or "Streetkid")
    local stockSize = SHOP_STOCK_SIZE[tier] or 8
    local rarityWeights = SHOP_RARITY_WEIGHTS[tier] or SHOP_RARITY_WEIGHTS.Streetkid
    local raceWindow = math.floor(currentRaceCount(career) / SHOP_REFRESH_RACE_GAP)
    local slotWeights = shopSlotWeights(career, vehicleKey)
    local candidates = {}
    local seed = hashString(vehicleKey) + math.floor(tonumber(career and career.seed) or 0) + raceWindow * 4099

    for _, definition in ipairs(PartsData.all()) do
        local roll
        seed, roll = nextFloat(seed + hashString(definition.id))
        local rarityBias = (tonumber(rarityWeights[definition.rarity]) or 0) / 100.0
        local slotBias = tonumber(slotWeights[definition.slot]) or 1.0
        local novelty = ownsPartId(career, definition.id) and 0.0 or 0.12
        candidates[#candidates + 1] = {
            definition = definition,
            score = rarityBias * 0.55 + slotBias * 0.30 + novelty + roll * 0.35,
        }
    end

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return tostring(a.definition.id or "") < tostring(b.definition.id or "")
    end)

    local chosen = {}
    local perSlotCount = {}
    for _, entry in ipairs(candidates) do
        local definition = entry.definition
        local slotId = tostring(definition.slot or "")
        local slotLimit = slotId == "antiCrawl" and 1 or 2
        if (perSlotCount[slotId] or 0) < slotLimit then
            chosen[#chosen + 1] = definition.id
            perSlotCount[slotId] = (perSlotCount[slotId] or 0) + 1
        end
        if #chosen >= stockSize then
            break
        end
    end

    return {
        seed = seed,
        raceWindow = raceWindow,
        refreshAtRace = currentRaceCount(career) + SHOP_REFRESH_RACE_GAP,
        vehicleKey = vehicleKey,
        items = chosen,
    }
end

local function ensureShopState(career, vehicleKey, forceRefresh)
    local garage = career and career.garage or nil
    local meta = garage and garage.meta or nil
    local shopState = meta and meta.shopState or nil
    if type(shopState) ~= "table" then
        shopState = { refreshAtRace = 0, items = {} }
        meta.shopState = shopState
    end

    local raceCount = currentRaceCount(career)
    local shouldRefresh = forceRefresh == true
        or type(shopState.items) ~= "table"
        or #shopState.items == 0
        or raceCount >= math.max(0, tonumber(shopState.refreshAtRace) or 0)
        or tostring(shopState.vehicleKey or "") ~= tostring(vehicleKey or "")

    if shouldRefresh then
        shopState = generateShopStock(career, vehicleKey)
        meta.shopState = shopState
        saveCareers()
    end
    return shopState
end

local function currentOfferState(career)
    Parts.ensureCareerState(career)
    return career.garage.meta.offerState
end

local function pruneExpiredOffers(career)
    local offerState = currentOfferState(career)
    local raceCount = currentRaceCount(career)
    local kept = {}
    local expired = {}
    for _, offer in ipairs(offerState.pending or {}) do
        local expiresAtRace = tonumber(offer and offer.expiresAtRace)
        if not expiresAtRace or raceCount <= expiresAtRace then
            kept[#kept + 1] = offer
        else
            expired[#expired + 1] = deepCopy(offer)
        end
    end
    offerState.pending = kept
    if #expired > 0 and MTE and MTE.Events then
        for _, offer in ipairs(expired) do
            MTE.Events.emit("PartOfferExpired", offer)
        end
    end
    return kept
end

local function nextOfferId(career)
    local offerState = currentOfferState(career)
    local nextId = math.max(1, math.floor(tonumber(offerState.nextOfferId) or 1))
    offerState.nextOfferId = nextId + 1
    return string.format("offer_%s_%03d", tostring(career.seed or 0), nextId)
end

local function tierOfferWeights(kind, tier)
    local group = OFFER_RARITY_WEIGHTS[tostring(kind or "hookup")] or OFFER_RARITY_WEIGHTS.hookup
    return makeWeightCopy(group[tostring(tier or "Streetkid")] or group.Streetkid)
end

local function chooseOfferSlot(career, vehicleKey, data, seed)
    local slotWeights = shopSlotWeights(career, vehicleKey)
    local raceType = tostring(data and data.raceType or data and data.config and data.config.raceType or "")
    if raceType == "drag" then
        slotWeights.engine = (slotWeights.engine or 1.0) + 0.35
        slotWeights.drivetrain = (slotWeights.drivetrain or 1.0) + 0.35
    elseif raceType == "knockout" then
        slotWeights.brakes = (slotWeights.brakes or 1.0) + 0.30
        slotWeights.handling = (slotWeights.handling or 1.0) + 0.25
        slotWeights.stability = (slotWeights.stability or 1.0) + 0.20
    else
        slotWeights.handling = (slotWeights.handling or 1.0) + 0.10
        slotWeights.stability = (slotWeights.stability or 1.0) + 0.10
    end
    local total = 0
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        total = total + math.max(0.01, tonumber(slotWeights[slotId]) or 0.01)
    end
    local roll
    seed, roll = nextFloat(seed + 123)
    local target = roll * total
    local acc = 0
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        acc = acc + math.max(0.01, tonumber(slotWeights[slotId]) or 0.01)
        if acc >= target then
            return slotId, seed
        end
    end
    return PartsData.SLOT_ORDER[1], seed
end

local function buildOfferDefinitions(career, vehicleKey, kind, data)
    local tier = tostring(career and career.tier or "Streetkid")
    local seed = hashString(vehicleKey) + hashString(kind) + math.floor(tonumber(career and career.seed) or 0) + currentRaceCount(career) * 211
    local primarySlot
    primarySlot, seed = chooseOfferSlot(career, vehicleKey, data, seed)
    local weights = tierOfferWeights(kind, tier)
    local targetCount = kind == "promotion" and 3 or 2
    local chosen = {}
    local chosenIds = {}

    for pickIndex = 1, targetCount do
        local slotId = pickIndex == 1 and primarySlot or nil
        local rarity, raritySeed = pickWeightedRarity(weights, seed + pickIndex * 17)
        local candidates = {}
        for _, definition in ipairs(slotId and PartsData.bySlot(slotId) or PartsData.all()) do
            if not chosenIds[definition.id] then
                local rarityDistance = math.abs(PartsData.rarityRank(definition.rarity) - PartsData.rarityRank(rarity))
                candidates[#candidates + 1] = { definition = definition, distance = rarityDistance }
            end
        end
        table.sort(candidates, function(a, b)
            if a.distance ~= b.distance then
                return a.distance < b.distance
            end
            return tostring(a.definition.id or "") < tostring(b.definition.id or "")
        end)
        if candidates[1] then
            local shortlist = {}
            local bestDistance = candidates[1].distance
            for _, candidate in ipairs(candidates) do
                if candidate.distance == bestDistance then
                    shortlist[#shortlist + 1] = candidate.definition
                end
            end
            local shuffled
            raritySeed, shuffled = deterministicShuffle(shortlist, raritySeed + pickIndex * 31)
            local definition = shuffled[1]
            if definition then
                chosen[#chosen + 1] = definition
                chosenIds[definition.id] = true
            end
            seed = raritySeed
        end
    end

    return chosen, primarySlot
end

local function createOffer(career, vehicleKey, kind, data)
    local offerState = currentOfferState(career)
    pruneExpiredOffers(career)
    local definitions, primarySlot = buildOfferDefinitions(career, vehicleKey, kind, data)
    if #definitions == 0 then
        return nil
    end

    local slotLabel = tostring(PartsData.SLOTS[primarySlot] and PartsData.SLOTS[primarySlot].label or primarySlot or "Parts")
    local title = kind == "promotion"
        and string.format("Promotion Crate: %s", tostring(data and data.to or career.tier or "Next Tier"))
        or string.format("Hookup Offer: %s", slotLabel)
    local subtitle = kind == "promotion"
        and string.format("Tier move reward with %d curated parts.", #definitions)
        or string.format("A short-run offer built around %s hardware.", string.lower(slotLabel))
    local totalPrice = 0
    local itemIds = {}
    for _, definition in ipairs(definitions) do
        totalPrice = totalPrice + math.floor((tonumber(definition.price) or 0) * (kind == "promotion" and 0.0 or 0.75))
        itemIds[#itemIds + 1] = definition.id
    end

    local offer = {
        offerId = nextOfferId(career),
        kind = kind,
        title = title,
        subtitle = subtitle,
        slot = primarySlot,
        slotLabel = slotLabel,
        price = kind == "promotion" and 0 or totalPrice,
        createdAtRace = currentRaceCount(career),
        expiresAtRace = kind == "promotion" and (currentRaceCount(career) + OFFER_EXPIRY_RACES + 1) or (currentRaceCount(career) + OFFER_EXPIRY_RACES),
        itemIds = itemIds,
    }
    offerState.pending[#offerState.pending + 1] = offer
    return offer
end

local function rarityWeightsForReward(career, summary)
    local position = tonumber(summary and summary.position) or 99
    local fieldSize = math.max(1, tonumber(summary and summary.fieldSize) or position)
    local weights
    if position <= 1 then
        weights = { Common = 18, Street = 40, Pro = 28, Elite = 14 }
    elseif position <= 3 then
        weights = { Common = 28, Street = 40, Pro = 24, Elite = 8 }
    elseif position <= math.ceil(fieldSize * 0.5) then
        weights = { Common = 42, Street = 36, Pro = 17, Elite = 5 }
    else
        weights = { Common = 56, Street = 30, Pro = 11, Elite = 3 }
    end

    local tier = career and career.tier or "Gonk"
    if tier == "Solo" then
        weights.Pro = weights.Pro + 3
    elseif tier == "Fixer" then
        weights.Pro = weights.Pro + 5
        weights.Elite = weights.Elite + 3
    elseif tier == "Edgerunner" then
        weights.Pro = weights.Pro + 6
        weights.Elite = weights.Elite + 6
    end
    return weights
end

local function pickRewardDefinition(career, summary)
    local baseSeed = (career.seed or 1)
        + ((career.stats.racesRun or 0) * 97)
        + ((summary and summary.position or 1) * 131)
        + ((summary and summary.fieldSize or 1) * 29)
    local seed = math.floor(baseSeed % LCG_M)
    local weights = rarityWeightsForReward(career, summary)
    local targetRarity
    targetRarity, seed = pickWeightedRarity(weights, seed)

    local candidates = {}
    for _, def in ipairs(PartsData.all()) do
        if def.rarity == targetRarity and not ownsPartId(career, def.id) then
            table.insert(candidates, def)
        end
    end

    if #candidates == 0 then
        for _, def in ipairs(PartsData.all()) do
            if not ownsPartId(career, def.id) then
                table.insert(candidates, def)
            end
        end
    end

    if #candidates == 0 then
        for _, def in ipairs(PartsData.all()) do
            table.insert(candidates, def)
        end
    end

    if #candidates == 0 then return nil end

    local roll
    seed, roll = nextFloat(seed + #candidates)
    local idx = math.max(1, math.min(#candidates, math.floor(roll * #candidates) + 1))
    return candidates[idx], seed
end

function Parts.init()
    local careers = resolveCareers()
    local changed = false
    if careers and careers.list then
        for _, career in ipairs(careers.list()) do
            if Parts.ensureCareerState(career) then
                changed = true
            end
        end
    end
    if changed then
        saveCareers()
    end
    print("[NCM/Parts] Garage system ready.")
end

function Parts.ensureCareerState(career)
    if type(career) ~= "table" then return false end
    local changed = false
    if ensureStats(career) then changed = true end
    local _, garageChanged = ensureGarage(career)
    if garageChanged then changed = true end
    if not career.garage.meta.seededStarter then
        seedStarterInventory(career)
        changed = true
    end
    return changed
end

function Parts.onCareerSelected(career)
    if Parts.ensureCareerState(career) then
        saveCareers()
    end
    notifyGarageChanged(nil)
end

function Parts.getAvailableInventory(career, vehicleKey, slotId)
    if type(career) ~= "table" or type(slotId) ~= "string" then return {} end
    Parts.ensureCareerState(career)
    if vehicleKey then
        ensureVehicleState(career, vehicleKey)
    end

    local out = {}
    for _, instance in pairs(career.garage.inventory or {}) do
        local entry = buildEntry(instance)
        if entry and entry.slot == slotId and not entry.installedVehicleKey then
            table.insert(out, entry)
        end
    end
    table.sort(out, sortInventory)
    return out
end

function Parts.getVehicleSlotProfile(career, vehicleKey)
    if type(career) ~= "table" or not vehicleKey then
        return nil
    end
    Parts.ensureCareerState(career)
    local vehicleState = ensureVehicleState(career, vehicleKey)
    return {
        counts = normalizeSlotProfileCounts(vehicleState.slotProfile),
        totalSlots = totalSlotCount(vehicleState.slotProfile),
        templateId = vehicleState.slotProfileMeta and vehicleState.slotProfileMeta.templateId or nil,
        prestige = vehicleState.slotProfileMeta and vehicleState.slotProfileMeta.prestige or nil,
        vehicleKind = vehicleState.slotProfileMeta and vehicleState.slotProfileMeta.vehicleKind or nil,
    }
end

function Parts.getInstalledParts(career, vehicleKey)
    local installedByCategory = {}
    if type(career) ~= "table" or not vehicleKey then return installedByCategory end
    Parts.ensureCareerState(career)
    local vehicleState = ensureVehicleState(career, vehicleKey)
    for _, slotId in ipairs(PartsData.SLOT_ORDER) do
        installedByCategory[slotId] = {}
        local stored = vehicleState.installedByCategory[slotId] or {}
        local compact = {}
        for _, instanceId in ipairs(stored) do
            local instance = instanceId and career.garage.inventory[instanceId] or nil
            local entry = buildEntry(instance)
            if entry then
                compact[#compact + 1] = instanceId
                installedByCategory[slotId][#installedByCategory[slotId] + 1] = entry
            end
        end
        vehicleState.installedByCategory[slotId] = compact
    end
    return installedByCategory
end

function Parts.getVehicleEffects(career, vehicleKey)
    if type(career) ~= "table" or not vehicleKey then return buildNeutralEffects() end

    local installed = Parts.getInstalledParts(career, vehicleKey)
    return composeEffectsFromInstalled(installed)
end

function Parts.getActiveVehicleEffects(vehicleKey)
    local careers = resolveCareers()
    local career = careers and careers.active and careers.active() or nil
    return Parts.getVehicleEffects(career, vehicleKey)
end

function Parts.getVehicleSummary(career, vehicleKey)
    if type(career) ~= "table" or not vehicleKey then return nil end
    Parts.ensureCareerState(career)
    local installedByCategory = Parts.getInstalledParts(career, vehicleKey)
    local slotProfile = Parts.getVehicleSlotProfile(career, vehicleKey)
    local effects = Parts.getVehicleEffects(career, vehicleKey)
    local installedCount = totalInstalledCount(installedByCategory)
    local performance = summarizePerformance(effects)
    local buildProfile = summarizeBuildProfile(effects, performance)
    local canonical = summarizeCanonicalEffects(buildProfile)
    local buildIdentity = summarizeBuildIdentity(buildProfile)
    local raceFits = summarizeRaceFits(buildProfile)
    local strengths, weaknesses = summarizeAxisTradeoffs(buildProfile)
    local legacyRating = computeLegacyRating(installedByCategory)
    local summary = {
        vehicleKey = vehicleKey,
        installed = buildInstalledPrimaryMap(installedByCategory),
        installedByCategory = installedByCategory,
        installedCount = installedCount,
        slotProfile = slotProfile and slotProfile.counts or normalizeSlotProfileCounts(nil),
        slotProfileMeta = slotProfile,
        slotCount = slotProfile and slotProfile.totalSlots or 0,
        inventoryCount = countEntries(career.garage.inventory),
        effects = deepCopy(effects),
        rating = legacyRating,
        legacyRating = legacyRating,
        performance = performance,
        perf = performance,
        buildProfile = buildProfile,
        canonicalEffects = canonical.effects,
        canonicalEffectEntries = canonical.ordered,
        canonicalStrengths = canonical.strengths,
        canonicalWeaknesses = canonical.weaknesses,
        buildIdentity = buildIdentity,
        raceFits = raceFits,
        strengths = strengths,
        weaknesses = weaknesses,
        lastReward = deepCopy(career.garage.meta.lastReward),
    }
    return summary
end

function Parts.getVehicleSnapshot(career, vehicleKey)
    local summary = Parts.getVehicleSummary(career, vehicleKey)
    if not summary then return nil end
    local installed = {}
    eachInstalledEntry(summary.installedByCategory, function(slotId, index, item)
        table.insert(installed, {
            slot = slotId,
            slotIndex = index,
            slotLabel = item.slotLabel,
            partId = item.partId,
            name = item.name,
            rarity = item.rarity,
            condition = item.condition,
        })
    end)
    return {
        vehicleKey = summary.vehicleKey,
        rating = summary.rating,
        slotProfile = summary.slotProfile,
        slotCount = summary.slotCount,
        installedCount = summary.installedCount,
        installed = installed,
        effects = summary.effects,
        performance = summary.performance,
        buildProfile = summary.buildProfile,
        canonicalEffects = summary.canonicalEffects,
        canonicalEffectEntries = summary.canonicalEffectEntries,
        canonicalStrengths = summary.canonicalStrengths,
        canonicalWeaknesses = summary.canonicalWeaknesses,
        buildIdentity = summary.buildIdentity,
        raceFits = summary.raceFits,
        strengths = summary.strengths,
        weaknesses = summary.weaknesses,
    }
end

function Parts.getRaceFitForConfig(career, vehicleKey, config)
    local summary = Parts.getVehicleSummary(career, vehicleKey)
    if not summary then
        return 1.0
    end
    return raceFitForConfig(summary, config)
end

function Parts.getLastReward(career)
    if type(career) ~= "table" then return nil end
    Parts.ensureCareerState(career)
    return deepCopy(career.garage.meta.lastReward)
end

function Parts.getShopInventory(career, vehicleKey, slotId, forceRefresh)
    if type(career) ~= "table" then
        return {}
    end
    Parts.ensureCareerState(career)
    local shopState = ensureShopState(career, vehicleKey, forceRefresh)
    local out = {}
    for index, partId in ipairs(shopState.items or {}) do
        local definition = PartsData.get(partId)
        if definition and (not slotId or definition.slot == slotId) then
            out[#out + 1] = {
                stockIndex = index,
                refreshAtRace = shopState.refreshAtRace,
                family = definition.family,
                familyLabel = PartsData.familyLabel(definition),
                focus = definition.focus,
                tradeoff = definition.tradeoff,
                id = definition.id,
                slot = definition.slot,
                rarity = definition.rarity,
                price = definition.price,
                name = definition.name,
                description = definition.description,
                modifiers = deepCopy(definition.modifiers or {}),
                additives = deepCopy(definition.additives or {}),
            }
        end
    end
    return out
end

function Parts.getPendingOffers(career)
    if type(career) ~= "table" then
        return {}
    end
    local pending = pruneExpiredOffers(career)
    local out = {}
    for _, offer in ipairs(pending) do
        local itemEntries = {}
        for _, partId in ipairs(offer.itemIds or {}) do
            local definition = PartsData.get(partId)
            if definition then
                itemEntries[#itemEntries + 1] = {
                    id = definition.id,
                    slot = definition.slot,
                    rarity = definition.rarity,
                    name = definition.name,
                    family = definition.family,
                    familyLabel = PartsData.familyLabel(definition),
                    focus = definition.focus,
                    tradeoff = definition.tradeoff,
                }
            end
        end
        out[#out + 1] = {
            offerId = offer.offerId,
            kind = offer.kind,
            title = offer.title,
            subtitle = offer.subtitle,
            slot = offer.slot,
            slotLabel = offer.slotLabel,
            price = offer.price,
            createdAtRace = offer.createdAtRace,
            expiresAtRace = offer.expiresAtRace,
            sourceContactId = offer.sourceContactId,
            contractId = offer.contractId,
            sourceArchetype = offer.sourceArchetype,
            items = itemEntries,
        }
    end
    return out
end

function Parts.enqueueContactOffer(career, spec)
    if type(career) ~= "table" or type(spec) ~= "table" then
        return nil, "Missing career or spec"
    end
    local offerState = currentOfferState(career)
    pruneExpiredOffers(career)
    if #(offerState.pending or {}) >= 3 then
        return nil, "Too many pending offers"
    end

    local itemIds = {}
    for _, partId in ipairs(spec.itemIds or {}) do
        local definition = PartsData.get(partId)
        if definition then
            itemIds[#itemIds + 1] = definition.id
        end
    end
    if #itemIds == 0 then
        return nil, "Offer must include at least one valid part"
    end

    local primaryDefinition = PartsData.get(itemIds[1])
    local slotId = tostring(spec.slot or primaryDefinition and primaryDefinition.slot or "")
    local slotLabel = tostring(PartsData.SLOTS[slotId] and PartsData.SLOTS[slotId].label or slotId or "Parts")
    local totalPrice = 0
    for _, partId in ipairs(itemIds) do
        local definition = PartsData.get(partId)
        totalPrice = totalPrice + math.floor((tonumber(definition and definition.price) or 0) * 0.72)
    end

    local offer = {
        offerId = nextOfferId(career),
        kind = tostring(spec.kind or "contact_offer"),
        title = tostring(spec.title or string.format("Contact Deal: %s", slotLabel)),
        subtitle = tostring(spec.subtitle or "A contact put together a focused pack around your current run."),
        slot = slotId,
        slotLabel = slotLabel,
        price = math.max(0, math.floor(tonumber(spec.price) or totalPrice)),
        createdAtRace = currentRaceCount(career),
        expiresAtRace = math.max(currentRaceCount(career) + 1, math.floor(tonumber(spec.expiresAtRace) or (currentRaceCount(career) + OFFER_EXPIRY_RACES))),
        itemIds = itemIds,
        sourceContactId = tostring(spec.sourceContactId or ""),
        contractId = tostring(spec.contractId or spec.eventId or ""),
        sourceArchetype = tostring(spec.sourceArchetype or ""),
    }
    offerState.pending[#offerState.pending + 1] = offer
    saveCareers()
    if MTE and MTE.Events then
        MTE.Events.emit("PartOfferCreated", deepCopy(offer))
    end
    return deepCopy(offer), nil
end

function Parts.claimOffer(career, offerId)
    if type(career) ~= "table" or not offerId then
        return nil, "Missing career or offerId"
    end
    local offerState = currentOfferState(career)
    pruneExpiredOffers(career)
    local offerIndex = nil
    local offer = nil
    for index, pending in ipairs(offerState.pending or {}) do
        if tostring(pending.offerId or "") == tostring(offerId) then
            offerIndex = index
            offer = pending
            break
        end
    end
    if not offer then
        return nil, "Offer not found"
    end

    local acquired = {}
    for itemIndex, partId in ipairs(offer.itemIds or {}) do
        local definition = PartsData.get(partId)
        if definition then
            local conditionFloor = offer.kind == "promotion" and 0.94 or 0.90
            local instance = createInstance(career, definition, {
                source = offer.kind == "promotion" and "promotion_crate"
                    or (offer.kind == "contact_offer" and "contact_offer" or "hookup_offer"),
                condition = clamp(conditionFloor + (itemIndex * 0.02), conditionFloor, 1.0),
            })
            local entry = buildEntry(instance)
            if entry then
                acquired[#acquired + 1] = entry
            end
        end
    end

    table.remove(offerState.pending, offerIndex)
    career.garage.meta.lastReward = {
        kind = offer.kind == "promotion" and "promotion_crate"
            or (offer.kind == "contact_offer" and "contact_offer" or "hookup_offer"),
        name = offer.title,
        slot = offer.slot,
        itemCount = #acquired,
        acquiredAt = os.time(),
    }
    saveCareers()
    notifyGarageChanged(nil)
    if MTE and MTE.Events then
        MTE.Events.emit("PartOfferClaimed", {
            offerId = offer.offerId,
            kind = offer.kind,
            title = offer.title,
            itemCount = #acquired,
            sourceContactId = offer.sourceContactId,
            contractId = offer.contractId,
            sourceArchetype = offer.sourceArchetype,
        })
    end
    return acquired, nil
end

function Parts.onPrestigeChange(career, data)
    if type(career) ~= "table" or type(data) ~= "table" then
        return nil
    end
    if tostring(data.dir or "") ~= "up" then
        return nil
    end
    local offerState = currentOfferState(career)
    local targetTier = tostring(data.to or career.tier or "")
    if targetTier ~= "" and tostring(offerState.lastPromotionTier or "") == targetTier then
        return nil
    end
    local vehicleKey = tostring(career and career.garage and career.garage.meta and career.garage.meta.lastVehicleKey or "")
    if vehicleKey == "" then
        vehicleKey = tostring(MTE and MTE.Tuning and MTE.Tuning._vehicleKey or "player_vehicle")
    end
    local offer = createOffer(career, vehicleKey, "promotion", data)
    if offer then
        offerState.lastPromotionTier = targetTier
        saveCareers()
        if MTE and MTE.Events then
            MTE.Events.emit("PartOfferCreated", deepCopy(offer))
        end
    end
    return offer
end

function Parts.onRaceFinished(career, data)
    if type(career) ~= "table" or type(data) ~= "table" then
        return nil
    end
    local offerState = currentOfferState(career)
    pruneExpiredOffers(career)
    local raceCount = currentRaceCount(career)
    local sessionId = tostring(data.sessionId or data.eventId or data.routeId or data.trackName or "")
    if sessionId ~= "" and sessionId == tostring(offerState.lastRaceOfferSessionId or "") then
        return nil
    end
    if raceCount - math.floor(tonumber(offerState.lastRaceOfferAtRace) or -99) < RACE_OFFER_COOLDOWN then
        return nil
    end
    if #(offerState.pending or {}) >= 3 then
        return nil
    end

    local position = math.max(1, math.floor(tonumber(data.position) or 99))
    local fieldSize = math.max(1, math.floor(tonumber(data.fieldSize) or position))
    local upperHalf = position <= math.max(1, math.ceil(fieldSize * 0.5))
    if data.dnf or not upperHalf then
        return nil
    end

    local vehicleKey = tostring(career and career.garage and career.garage.meta and career.garage.meta.lastVehicleKey or "")
    if vehicleKey == "" then
        vehicleKey = tostring(MTE and MTE.Tuning and MTE.Tuning._vehicleKey or "player_vehicle")
    end
    local offer = createOffer(career, vehicleKey, "hookup", data)
    if offer then
        offerState.lastRaceOfferAtRace = raceCount
        offerState.lastRaceOfferSessionId = sessionId
        saveCareers()
        if MTE and MTE.Events then
            MTE.Events.emit("PartOfferCreated", deepCopy(offer))
        end
    end
    return offer
end

function Parts.ensureRivalVehicleBuild(driver, careerSeed)
    if type(driver) ~= "table" then return nil, false end

    local tier = tostring(driver.currentTier or driver.tier or "Gonk")
    local vehicleSignature = tostring(driver.vehicleSignature or "")
    local vehiclePrestige = math.max(1, math.min(5, math.floor(tonumber(driver.vehiclePrestige) or 2)))
    local build = driver.vehicleBuild
    local isCurrent = type(build) == "table"
        and tonumber(build.buildVersion) == RIVAL_BUILD_VERSION
        and tostring(build.tier or "") == tier
        and tostring(build.vehicleSignature or "") == vehicleSignature
        and math.floor(tonumber(build.vehiclePrestige) or 0) == vehiclePrestige

    if isCurrent then
        return build, false
    end

    local installed, slotProfile = buildRivalInstalledParts(driver, careerSeed)
    local effects = composeEffectsFromInstalled(installed)
    local performance = summarizePerformance(effects)

    local buildProfile = summarizeBuildProfile(effects, performance)
    driver.vehicleBuild = {
        buildVersion = RIVAL_BUILD_VERSION,
        tier = tier,
        vehicleSignature = vehicleSignature,
        vehiclePrestige = vehiclePrestige,
        installed = installed,
        slotProfile = slotProfile and slotProfile.counts or normalizeSlotProfileCounts(nil),
        slotCount = slotProfile and slotProfile.totalSlots or totalInstalledCount(installed),
        installedCount = totalInstalledCount(installed),
        rating = computeLegacyRating(installed),
        effects = effects,
        performance = performance,
        buildProfile = buildProfile,
        buildIdentity = summarizeBuildIdentity(buildProfile),
        raceFits = summarizeRaceFits(buildProfile),
    }
    return driver.vehicleBuild, true
end

function Parts.getDriverVehicleBuild(driver)
    if type(driver) == "table" and type(driver.vehicleBuild) == "table" then
        return driver.vehicleBuild
    end
    if type(driver) == "table" and type(driver.driver) == "table" and type(driver.driver.vehicleBuild) == "table" then
        return driver.driver.vehicleBuild
    end
    return nil
end

function Parts.getDriverHardwareSummary(driver)
    local build = Parts.getDriverVehicleBuild(driver)
    local perf = build and build.performance or nil
    if type(build) ~= "table" or type(perf) ~= "table" then
        return DEFAULT_DRIVER_HARDWARE
    end
    return {
        rating = math.max(0, math.floor(tonumber(build.rating) or 0)),
        slotCount = math.max(0, math.floor(tonumber(build.slotCount) or totalInstalledCount(build.installed) or 0)),
        buildHeadline = build.buildIdentity and build.buildIdentity.headline or nil,
        bestRaceFit = math.max(
            tonumber(build.raceFits and build.raceFits.drag) or 1.0,
            tonumber(build.raceFits and build.raceFits.sprint) or 1.0,
            tonumber(build.raceFits and build.raceFits.knockout) or 1.0,
            tonumber(build.raceFits and build.raceFits.longRoute) or 1.0),
        sprintScale = clamp(tonumber(perf.sprintScale) or 1.0, 0.82, 1.30),
        dragScale = clamp(tonumber(perf.dragScale) or 1.0, 0.82, 1.30),
        knockoutScale = clamp(tonumber(perf.knockoutScale) or 1.0, 0.82, 1.30),
        liveSpeedScale = clamp(tonumber(perf.liveSpeedScale) or 1.0, 0.80, 1.25),
        launchScale = clamp(tonumber(perf.launchScale) or 1.0, 0.90, 1.25),
        controlScale = clamp(tonumber(perf.controlScale) or 1.0, 0.90, 1.20),
        reliabilityScale = clamp(tonumber(perf.reliabilityScale) or 1.0, 0.90, 1.20),
        confidence = clamp(tonumber(perf.confidence) or 1.0, 0.90, 1.12),
    }
end

local function resolveInstallIndex(vehicleState, slotId, requestedIndex)
    local installed = vehicleState.installedByCategory[slotId] or {}
    local capacity = math.max(#installed, math.floor(tonumber(vehicleState.slotProfile and vehicleState.slotProfile[slotId]) or 0))
    local index = tonumber(requestedIndex)
    if index and index >= 1 and index <= capacity then
        return math.floor(index), capacity
    end
    if #installed < capacity then
        return (#installed + 1), capacity
    end
    return nil, capacity
end

local function syncInstalledIndexes(career, vehicleState, vehicleKey, slotId)
    local installed = vehicleState.installedByCategory[slotId] or {}
    for index, listedInstanceId in ipairs(installed) do
        local listedInstance = career.garage.inventory[listedInstanceId]
        if listedInstance then
            listedInstance.installedVehicleKey = vehicleKey
            listedInstance.installedCategory = slotId
            listedInstance.installedIndex = index
        end
    end
end

function Parts.installPart(career, vehicleKey, instanceId, slotIdOverride, targetIndex)
    if type(career) ~= "table" or not vehicleKey or not instanceId then
        return false, "Missing vehicle or part instance"
    end

    Parts.ensureCareerState(career)
    local instance = career.garage.inventory[instanceId]
    if not instance then return false, "Part instance not found" end

    local definition = PartsData.get(instance.partId)
    if not definition then return false, "Part definition missing" end
    local vehicleState = ensureVehicleState(career, vehicleKey)
    local slotId = slotIdOverride or definition.slot
    if slotId ~= definition.slot then
        return false, "Part category mismatch"
    end
    local installIndex, capacity = resolveInstallIndex(vehicleState, slotId, targetIndex)
    if not installIndex then
        return false, string.format("No open %s slots", tostring(slotId))
    end

    local installed = vehicleState.installedByCategory[slotId] or {}
    local currentInstanceId = installed[installIndex]
    if currentInstanceId == instanceId then return true end

    if instance.installedVehicleKey and instance.installedVehicleKey == vehicleKey and instance.installedCategory == slotId and tonumber(instance.installedIndex) == installIndex then
        return true
    end

    if instance.installedVehicleKey and instance.installedVehicleKey ~= vehicleKey then
        return false, "Part is already installed on another vehicle"
    end

    if instance.installedVehicleKey and instance.installedVehicleKey == vehicleKey and instance.installedCategory then
        local previousState = ensureVehicleState(career, vehicleKey)
        local previousList = previousState.installedByCategory[instance.installedCategory] or {}
        local previousIndex = tonumber(instance.installedIndex)
        if previousIndex and previousList[previousIndex] == instanceId then
            table.remove(previousList, previousIndex)
        else
            for index, value in ipairs(previousList) do
                if value == instanceId then
                    table.remove(previousList, index)
                    break
                end
            end
        end
        syncInstalledIndexes(career, previousState, vehicleKey, instance.installedCategory)
    end

    if currentInstanceId then
        local current = career.garage.inventory[currentInstanceId]
        if current then
            current.installedVehicleKey = nil
            current.installedCategory = nil
            current.installedIndex = nil
        end
    elseif installIndex > capacity then
        return false, string.format("No open %s slots", tostring(slotId))
    end

    installed[installIndex] = instanceId
    vehicleState.installedByCategory[slotId] = installed
    instance.installedVehicleKey = vehicleKey
    instance.installedCategory = slotId
    instance.installedIndex = installIndex
    career.garage.meta.lastVehicleKey = vehicleKey
    career.garage.meta.lastInstall = {
        vehicleKey = vehicleKey,
        slot = slotId,
        slotIndex = installIndex,
        name = definition.name,
        installedAt = os.time(),
    }
    career.stats.installActions = (career.stats.installActions or 0) + 1
    syncInstalledIndexes(career, vehicleState, vehicleKey, slotId)

    saveCareers()
    notifyGarageChanged(vehicleKey)
    return true
end

function Parts.uninstallPart(career, vehicleKey, slotId, targetIndex)
    if type(career) ~= "table" or not vehicleKey or not slotId then
        return false, "Missing vehicle or slot"
    end

    Parts.ensureCareerState(career)
    local vehicleState = ensureVehicleState(career, vehicleKey)
    local installed = vehicleState.installedByCategory[slotId] or {}
    local index = tonumber(targetIndex)
    if not index or index < 1 or index > #installed then
        index = #installed
    end
    local instanceId = installed[index]
    if not instanceId then return false, "Slot is already empty" end

    local instance = career.garage.inventory[instanceId]
    if instance then
        instance.installedVehicleKey = nil
        instance.installedCategory = nil
        instance.installedIndex = nil
    end
    table.remove(installed, index)
    vehicleState.installedByCategory[slotId] = installed
    career.garage.meta.lastVehicleKey = vehicleKey
    syncInstalledIndexes(career, vehicleState, vehicleKey, slotId)

    saveCareers()
    notifyGarageChanged(vehicleKey)
    return true
end

function Parts.awardRaceLoot(career, summary)
    if type(career) ~= "table" or type(summary) ~= "table" then return nil end
    if summary.dnf then return nil end

    Parts.ensureCareerState(career)
    local definition, seed = pickRewardDefinition(career, summary)
    if not definition then return nil end

    local roll
    seed, roll = nextFloat(seed + 17)
    local instance = createInstance(career, definition, {
        source = "race_reward",
        condition = 0.88 + (roll * 0.12),
    })
    local reward = buildEntry(instance)
    if not reward then return nil end

    career.garage.meta.lastReward = {
        kind = "race_reward",
        instanceId = reward.instanceId,
        partId = reward.partId,
        slot = reward.slot,
        family = reward.family,
        familyLabel = reward.familyLabel,
        name = reward.name,
        rarity = reward.rarity,
        condition = reward.condition,
        acquiredAt = os.time(),
    }

    saveCareers()
    if MTE and MTE.Events then
        MTE.Events.emit("PartAwarded", reward)
    end
    return deepCopy(career.garage.meta.lastReward)
end

function Parts.purchasePart(career, partId, vehicleKey, slotId, targetIndex)
    if type(career) ~= "table" or not partId then
        return nil, "Missing career or partId"
    end
    local definition = PartsData.get(partId)
    if not definition then return nil, "Unknown part: " .. tostring(partId) end
    Parts.ensureCareerState(career)
    local instance = createInstance(career, definition, { source = "shop", condition = 1.0 })
    if not instance then return nil, "Failed to create instance" end
    local shopState = career.garage and career.garage.meta and career.garage.meta.shopState or nil
    if type(shopState) == "table" and type(shopState.items) == "table" then
        for index, stockedPartId in ipairs(shopState.items) do
            if stockedPartId == partId then
                table.remove(shopState.items, index)
                break
            end
        end
    end
    if vehicleKey then
        local ok, err = Parts.installPart(career, vehicleKey, instance.instanceId, slotId or definition.slot, targetIndex)
        if not ok then
            saveCareers()
            return instance.instanceId, err
        end
    end
    saveCareers()
    return instance.instanceId, nil
end

return Parts