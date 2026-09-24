local VehicleSlotProfiles = {}

local SLOT_ORDER = {
    "engine",
    "drivetrain",
    "brakes",
    "handling",
    "stability",
    "antiCrawl",
}

local BUDGET_BY_PRESTIGE = {
    [1] = { min = 4, max = 6 },
    [2] = { min = 6, max = 8 },
    [3] = { min = 8, max = 10 },
    [4] = { min = 10, max = 12 },
    [5] = { min = 12, max = 14 },
}

local TEMPLATES = {
    {
        id = "rayfield_hyper_gt",
        prestige = 5,
        kind = "car",
        match = { "caliburn", "aerondight" },
        minCounts = { engine = 2, drivetrain = 1, brakes = 1, handling = 2, stability = 2, antiCrawl = 1 },
        maxCounts = { engine = 5, drivetrain = 3, brakes = 3, handling = 4, stability = 5, antiCrawl = 1 },
        weights = { engine = 1.55, drivetrain = 0.90, brakes = 0.75, handling = 1.10, stability = 1.40, antiCrawl = 0.10 },
    },
    {
        id = "quadra_type66",
        prestige = 4,
        kind = "car",
        match = { "type66", "javelina", "cthulhu", "avenger" },
        minCounts = { engine = 2, drivetrain = 1, brakes = 1, handling = 1, stability = 1, antiCrawl = 0 },
        maxCounts = { engine = 5, drivetrain = 4, brakes = 3, handling = 3, stability = 3, antiCrawl = 1 },
        weights = { engine = 1.45, drivetrain = 1.20, brakes = 0.80, handling = 0.75, stability = 0.70, antiCrawl = 0.20 },
    },
    {
        id = "mizutani_tuner",
        prestige = 3,
        kind = "car",
        match = { "shion", "mizutani", "maimai" },
        minCounts = { engine = 1, drivetrain = 1, brakes = 1, handling = 2, stability = 1, antiCrawl = 0 },
        maxCounts = { engine = 4, drivetrain = 3, brakes = 3, handling = 5, stability = 3, antiCrawl = 1 },
        weights = { engine = 1.00, drivetrain = 0.95, brakes = 1.10, handling = 1.45, stability = 0.70, antiCrawl = 0.15 },
    },
    {
        id = "outlaw_grand_tourer",
        prestige = 4,
        kind = "car",
        match = { "outlaw", "murkmobile", "thrax" },
        minCounts = { engine = 1, drivetrain = 1, brakes = 2, handling = 1, stability = 2, antiCrawl = 0 },
        maxCounts = { engine = 4, drivetrain = 3, brakes = 5, handling = 3, stability = 4, antiCrawl = 1 },
        weights = { engine = 0.95, drivetrain = 0.95, brakes = 1.40, handling = 0.90, stability = 1.20, antiCrawl = 0.12 },
    },
    {
        id = "thorton_nomad",
        prestige = 2,
        kind = "car",
        match = { "thorton", "mackinaw", "colby", "vulture", "beast" },
        minCounts = { engine = 1, drivetrain = 1, brakes = 0, handling = 1, stability = 1, antiCrawl = 1 },
        maxCounts = { engine = 3, drivetrain = 3, brakes = 2, handling = 2, stability = 3, antiCrawl = 2 },
        weights = { engine = 1.10, drivetrain = 1.10, brakes = 0.60, handling = 0.70, stability = 1.05, antiCrawl = 0.85 },
    },
    {
        id = "compact_street",
        prestige = 2,
        kind = "car",
        match = { "galena", "archer", "villefort", "supron", "hatch" },
        minCounts = { engine = 1, drivetrain = 0, brakes = 1, handling = 1, stability = 0, antiCrawl = 1 },
        maxCounts = { engine = 3, drivetrain = 2, brakes = 3, handling = 3, stability = 2, antiCrawl = 2 },
        weights = { engine = 0.95, drivetrain = 0.70, brakes = 1.00, handling = 1.20, stability = 0.60, antiCrawl = 0.80 },
    },
    {
        id = "sport_bike",
        prestige = 3,
        kind = "bike",
        match = { "kusanagi", "arch", "nazare", "apollo", "bike", "yaiba" },
        minCounts = { engine = 1, drivetrain = 1, brakes = 1, handling = 2, stability = 0, antiCrawl = 1 },
        maxCounts = { engine = 4, drivetrain = 3, brakes = 4, handling = 5, stability = 2, antiCrawl = 2 },
        weights = { engine = 1.15, drivetrain = 1.00, brakes = 1.20, handling = 1.50, stability = 0.45, antiCrawl = 0.70 },
    },
    {
        id = "default_car",
        prestige = 3,
        kind = "car",
        match = {},
        minCounts = { engine = 1, drivetrain = 1, brakes = 1, handling = 1, stability = 1, antiCrawl = 0 },
        maxCounts = { engine = 4, drivetrain = 4, brakes = 4, handling = 4, stability = 4, antiCrawl = 2 },
        weights = { engine = 1.00, drivetrain = 0.95, brakes = 0.95, handling = 1.00, stability = 0.95, antiCrawl = 0.25 },
    },
    {
        id = "default_bike",
        prestige = 2,
        kind = "bike",
        match = {},
        minCounts = { engine = 1, drivetrain = 1, brakes = 1, handling = 2, stability = 0, antiCrawl = 1 },
        maxCounts = { engine = 3, drivetrain = 3, brakes = 3, handling = 4, stability = 2, antiCrawl = 2 },
        weights = { engine = 1.00, drivetrain = 0.90, brakes = 1.10, handling = 1.40, stability = 0.40, antiCrawl = 0.65 },
    },
}

local function clamp(value, minValue, maxValue)
    if type(value) ~= "number" then
        return minValue
    end
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function hashString(text)
    local value = 0
    local source = string.lower(tostring(text or ""))
    for index = 1, #source do
        value = (value * 131 + string.byte(source, index)) % 4294967296
    end
    return value
end

local function nextFloat(seed)
    local value = math.floor((tonumber(seed) or 0) % 4294967296)
    value = math.floor((value * 1664525 + 1013904223) % 4294967296)
    return value, value / 4294967296
end

local function sumCounts(counts)
    local total = 0
    for _, slotId in ipairs(SLOT_ORDER) do
        total = total + math.max(0, math.floor(tonumber(counts and counts[slotId]) or 0))
    end
    return total
end

local function copyCounts(counts)
    local copy = {}
    for _, slotId in ipairs(SLOT_ORDER) do
        copy[slotId] = math.max(0, math.floor(tonumber(counts and counts[slotId]) or 0))
    end
    return copy
end

local function copyWeights(weights)
    local copy = {}
    for _, slotId in ipairs(SLOT_ORDER) do
        copy[slotId] = math.max(0.0, tonumber(weights and weights[slotId]) or 0.0)
    end
    return copy
end

local function inferKind(vehicleKey, kindHint)
    local hint = string.lower(tostring(kindHint or ""))
    if hint == "bike" or hint == "car" then
        return hint
    end
    local key = string.lower(tostring(vehicleKey or ""))
    if key:find("bike", 1, true) or key:find("kusanagi", 1, true) or key:find("arch", 1, true) or key:find("nazare", 1, true) or key:find("apollo", 1, true) or key:find("yaiba", 1, true) then
        return "bike"
    end
    return "car"
end

local function findTemplate(vehicleKey, kind)
    local key = string.lower(tostring(vehicleKey or ""))
    local fallback = nil
    for _, template in ipairs(TEMPLATES) do
        if template.id == (kind == "bike" and "default_bike" or "default_car") then
            fallback = template
        end
        if template.kind == kind then
            for _, token in ipairs(template.match or {}) do
                if token ~= "" and key:find(token, 1, true) then
                    return template, token
                end
            end
        end
    end
    return fallback, nil
end

local function pickWeightedSlot(seed, counts, maxCounts, weights)
    local totalWeight = 0
    local available = {}
    for _, slotId in ipairs(SLOT_ORDER) do
        local current = math.max(0, math.floor(tonumber(counts[slotId]) or 0))
        local maxValue = math.max(current, math.floor(tonumber(maxCounts[slotId]) or current))
        if current < maxValue then
            local weight = math.max(0.01, tonumber(weights[slotId]) or 0.01)
            totalWeight = totalWeight + weight
            available[#available + 1] = { slotId = slotId, weight = weight }
        end
    end
    if totalWeight <= 0 or #available == 0 then
        return nil, seed
    end
    local roll
    seed, roll = nextFloat(seed)
    local target = roll * totalWeight
    local acc = 0
    for _, entry in ipairs(available) do
        acc = acc + entry.weight
        if acc >= target then
            return entry.slotId, seed
        end
    end
    return available[#available].slotId, seed
end

function VehicleSlotProfiles.resolve(vehicleKey, opts)
    local options = type(opts) == "table" and opts or {}
    local kind = inferKind(vehicleKey, options.kind)
    local template, matchedToken = findTemplate(vehicleKey, kind)
    local prestige = clamp(math.floor(tonumber(options.prestige or (template and template.prestige) or (kind == "bike" and 2 or 3)) or 3), 1, 5)
    local budgetRange = BUDGET_BY_PRESTIGE[prestige] or BUDGET_BY_PRESTIGE[3]
    local seedBase = hashString(vehicleKey) + hashString(options.seed) + prestige * 977
    local seed = math.floor(seedBase % 4294967296)

    local counts = copyCounts(template and template.minCounts or nil)
    local maxCounts = copyCounts(template and template.maxCounts or nil)
    local weights = copyWeights(template and template.weights or nil)
    for _, slotId in ipairs(SLOT_ORDER) do
        if maxCounts[slotId] <= 0 then
            maxCounts[slotId] = math.max(counts[slotId], 1)
        end
        if weights[slotId] <= 0 then
            weights[slotId] = 1
        end
    end

    local totalMin = sumCounts(counts)
    local totalMax = sumCounts(maxCounts)
    local targetBudget = clamp(budgetRange.min, totalMin, totalMax)
    if budgetRange.max > budgetRange.min then
        local roll
        seed, roll = nextFloat(seed + 17)
        targetBudget = clamp(budgetRange.min + math.floor(roll * (budgetRange.max - budgetRange.min + 1)), totalMin, totalMax)
    end

    while sumCounts(counts) < targetBudget do
        local slotId
        slotId, seed = pickWeightedSlot(seed + sumCounts(counts) * 13, counts, maxCounts, weights)
        if not slotId then
            break
        end
        counts[slotId] = counts[slotId] + 1
    end

    return {
        vehicleKey = vehicleKey,
        vehicleKind = kind,
        prestige = prestige,
        templateId = template and template.id or (kind == "bike" and "default_bike" or "default_car"),
        matchedToken = matchedToken,
        counts = counts,
        totalSlots = sumCounts(counts),
    }
end

return VehicleSlotProfiles