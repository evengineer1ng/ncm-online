-- ============================================================
-- MT_Ecosystem: modules/race_commands.lua
-- Shared command surface for CET UI, phone/SMS choices, and
-- console helpers. Keep gameplay mutations here so every front
-- end asks the race system to do the same thing.
-- ============================================================

local Commands = {}
local i18n = require("modules/i18n")
local Betting = require("modules/betting")
local PartsData = require("data/parts")

Commands.ID = {
    STATUS = 1,
    SETUP_SCHEDULED = 10,
    QUICK_RACE = 11,
    KNOCKOUT_SETUP = 12,
    OPEN_CUSTOM_RACE_FLOW = 13,
    QUICK_RACE_REFRESH = 14,
    CONFIRM_PREVIEW = 20,
    CANCEL = 21,
    TRACK_START = 30,
    START_QUALI = 31,
    START_RACE = 32,
    ABORT = 33,
    CLOSE_RESULTS = 34,
    RESTART = 35,
    STANDINGS = 40,
    STATS = 41,
    VIEW_PLAYER_STATS = 42,
    REROLL_FAN_MESSAGE = 43,
    WAGER_MAX = 50,
    WAGER_CLEAR = 51,
    WAGER_EARNINGS = 52,
    WAGER_LOW = 53,
    WAGER_MEDIUM = 54,
    WAGER_HIGH = 55,
    WAGER_STREAK = 56,
    WAGER_STREAK_THREE = 57,
    WAGER_STREAK_FIVE = 58,
    WAGER_BOARD = 59,
    SCOUT_STATUS = 60,
    SCOUT_CURRENT_GRID = 61,
    SCOUT_FIELD_READ = 62,
    SCOUT_WATCHLIST = 63,
    WAGER_FAVORITE = 64,
    WAGER_VALUE = 65,
    WAGER_PICK_SELF = 66,
    WAGER_PICK_FAVORITE = 67,
    WAGER_PICK_VALUE = 68,
    VIEW_CAR_STATUS = 70,
    GET_SETUP_SUGGESTION = 71,
    OPEN_PARTS_SOURCE = 72,
    OPEN_TUNING = 73,
    SETUP_ACCEPT_CONTRACT = 74,
    SETUP_DECLINE_CONTRACT = 75,
    CUSTOM_TYPE_SPRINT = 80,
    CUSTOM_TYPE_DRAG = 81,
    CUSTOM_TYPE_KNOCKOUT = 82,
    CUSTOM_FIELD_FOUR = 83,
    CUSTOM_FIELD_SIX = 84,
    CUSTOM_FIELD_EIGHT = 85,
    CUSTOM_FIELD_TEN = 86,
    CUSTOM_START_GRID = 87,
    CUSTOM_START_ROLLING = 88,
    CUSTOM_START_SIDEBYSIDE = 89,
    CUSTOM_DIFFICULTY_STREET = 90,
    CUSTOM_DIFFICULTY_SERIOUS = 91,
    CUSTOM_DIFFICULTY_ELITE = 92,
    CUSTOM_LOCATION_ANY = 93,
    CUSTOM_LOCATION_WATSON = 94,
    CUSTOM_LOCATION_WESTBROOK = 95,
    CUSTOM_LOCATION_HEYWOOD = 96,
    CUSTOM_LOCATION_PACIFICA = 97,
    CUSTOM_LOCATION_SANTO_DOMINGO = 98,
    CUSTOM_LOCATION_CITY_CENTER = 99,
    CUSTOM_LOCATION_BADLANDS = 100,
    CUSTOM_CONFIRM = 101,
    CUSTOM_SCRAP = 102,
    SCOUT_AMBIENT_HEAT = 103,
    SCOUT_MANAGEMENT_TARGETS = 104,
    SCOUT_SIGN_TARGET_ONE = 105,
    SCOUT_SIGN_TARGET_TWO = 106,
    SCOUT_SIGN_TARGET_THREE = 107,
    CONTROL_AMBIENT_STATUS = 108,
    CONTROL_STAGE_LIVE_AMBIENT = 109,
    CONTROL_QUEUE_MANAGED_SIM = 110,
    CONTROL_QUEUE_MANAGED_SPECTATE = 111,
    CONTROL_SIMULATE_MANAGED_RUN = 112,
    SCOUT_ACCEPT_LEAK = 113,
    SCOUT_DECLINE_LEAK = 114,
}

local ID_TO_COMMAND = {
    [Commands.ID.STATUS] = "status",
    [Commands.ID.SETUP_SCHEDULED] = "start_career_race",
    [Commands.ID.QUICK_RACE] = "quick_race",
    [Commands.ID.KNOCKOUT_SETUP] = "knockout_setup",
    [Commands.ID.OPEN_CUSTOM_RACE_FLOW] = "open_custom_race_flow",
    [Commands.ID.QUICK_RACE_REFRESH] = "refresh_quick_race_offer",
    [Commands.ID.CONFIRM_PREVIEW] = "confirm_preview",
    [Commands.ID.CANCEL] = "cancel",
    [Commands.ID.TRACK_START] = "track_start",
    [Commands.ID.START_QUALI] = "start_quali",
    [Commands.ID.START_RACE] = "start_race",
    [Commands.ID.ABORT] = "abort",
    [Commands.ID.CLOSE_RESULTS] = "close_results",
    [Commands.ID.RESTART] = "restart",
    [Commands.ID.STANDINGS] = "standings",
    [Commands.ID.STATS] = "stats",
    [Commands.ID.VIEW_PLAYER_STATS] = "view_player_stats",
    [Commands.ID.REROLL_FAN_MESSAGE] = "reroll_fan_message",
    [Commands.ID.WAGER_MAX] = "wager_max",
    [Commands.ID.WAGER_CLEAR] = "wager_clear",
    [Commands.ID.WAGER_EARNINGS] = "wager_earnings",
    [Commands.ID.WAGER_LOW] = "wager_low",
    [Commands.ID.WAGER_MEDIUM] = "wager_medium",
    [Commands.ID.WAGER_HIGH] = "wager_high",
    [Commands.ID.WAGER_STREAK] = "wager_streak",
    [Commands.ID.WAGER_STREAK_THREE] = "wager_streak_three",
    [Commands.ID.WAGER_STREAK_FIVE] = "wager_streak_five",
    [Commands.ID.WAGER_BOARD] = "wager_board",
    [Commands.ID.SCOUT_STATUS] = "scout_status",
    [Commands.ID.SCOUT_CURRENT_GRID] = "scout_current_grid",
    [Commands.ID.SCOUT_FIELD_READ] = "scout_field_read",
    [Commands.ID.SCOUT_WATCHLIST] = "scout_watchlist",
    [Commands.ID.WAGER_FAVORITE] = "wager_favorite",
    [Commands.ID.WAGER_VALUE] = "wager_value",
    [Commands.ID.WAGER_PICK_SELF] = "wager_pick_self",
    [Commands.ID.WAGER_PICK_FAVORITE] = "wager_pick_favorite",
    [Commands.ID.WAGER_PICK_VALUE] = "wager_pick_value",
    [Commands.ID.VIEW_CAR_STATUS] = "view_car_status",
    [Commands.ID.GET_SETUP_SUGGESTION] = "get_setup_suggestion",
    [Commands.ID.OPEN_PARTS_SOURCE] = "open_parts_source",
    [Commands.ID.OPEN_TUNING] = "open_tuning",
    [Commands.ID.SETUP_ACCEPT_CONTRACT] = "setup_accept_contract",
    [Commands.ID.SETUP_DECLINE_CONTRACT] = "setup_decline_contract",
    [Commands.ID.CUSTOM_TYPE_SPRINT] = "custom_type_sprint",
    [Commands.ID.CUSTOM_TYPE_DRAG] = "custom_type_drag",
    [Commands.ID.CUSTOM_TYPE_KNOCKOUT] = "custom_type_knockout",
    [Commands.ID.CUSTOM_FIELD_FOUR] = "custom_field_four",
    [Commands.ID.CUSTOM_FIELD_SIX] = "custom_field_six",
    [Commands.ID.CUSTOM_FIELD_EIGHT] = "custom_field_eight",
    [Commands.ID.CUSTOM_FIELD_TEN] = "custom_field_ten",
    [Commands.ID.CUSTOM_START_GRID] = "custom_start_grid",
    [Commands.ID.CUSTOM_START_ROLLING] = "custom_start_rolling",
    [Commands.ID.CUSTOM_START_SIDEBYSIDE] = "custom_start_sidebyside",
    [Commands.ID.CUSTOM_DIFFICULTY_STREET] = "custom_difficulty_street",
    [Commands.ID.CUSTOM_DIFFICULTY_SERIOUS] = "custom_difficulty_serious",
    [Commands.ID.CUSTOM_DIFFICULTY_ELITE] = "custom_difficulty_elite",
    [Commands.ID.CUSTOM_LOCATION_ANY] = "custom_location_any",
    [Commands.ID.CUSTOM_LOCATION_WATSON] = "custom_location_watson",
    [Commands.ID.CUSTOM_LOCATION_WESTBROOK] = "custom_location_westbrook",
    [Commands.ID.CUSTOM_LOCATION_HEYWOOD] = "custom_location_heywood",
    [Commands.ID.CUSTOM_LOCATION_PACIFICA] = "custom_location_pacifica",
    [Commands.ID.CUSTOM_LOCATION_SANTO_DOMINGO] = "custom_location_santo_domingo",
    [Commands.ID.CUSTOM_LOCATION_CITY_CENTER] = "custom_location_city_center",
    [Commands.ID.CUSTOM_LOCATION_BADLANDS] = "custom_location_badlands",
    [Commands.ID.CUSTOM_CONFIRM] = "custom_confirm",
    [Commands.ID.CUSTOM_SCRAP] = "custom_scrap",
    [Commands.ID.SCOUT_AMBIENT_HEAT] = "scout_ambient_heat",
    [Commands.ID.SCOUT_MANAGEMENT_TARGETS] = "scout_management_targets",
    [Commands.ID.SCOUT_SIGN_TARGET_ONE] = "scout_sign_target_one",
    [Commands.ID.SCOUT_SIGN_TARGET_TWO] = "scout_sign_target_two",
    [Commands.ID.SCOUT_SIGN_TARGET_THREE] = "scout_sign_target_three",
    [Commands.ID.CONTROL_AMBIENT_STATUS] = "control_ambient_status",
    [Commands.ID.CONTROL_STAGE_LIVE_AMBIENT] = "control_stage_live_ambient",
    [Commands.ID.CONTROL_QUEUE_MANAGED_SIM] = "control_queue_managed_sim",
    [Commands.ID.CONTROL_QUEUE_MANAGED_SPECTATE] = "control_queue_managed_spectate",
    [Commands.ID.CONTROL_SIMULATE_MANAGED_RUN] = "control_simulate_managed_run",
    [Commands.ID.SCOUT_ACCEPT_LEAK] = "scout_accept_leak",
    [Commands.ID.SCOUT_DECLINE_LEAK] = "scout_decline_leak",
}

local function call(mod, fnName, default, ...)
    if type(mod) ~= "table" or type(mod[fnName]) ~= "function" then
        return default
    end
    local ok, a, b = pcall(mod[fnName], ...)
    if ok then return a, b end
    print(i18n.format("[NCM/RaceCommands] %s failed: %s", tostring(fnName), tostring(a)))
    return default, tostring(a)
end

local function notify(message, duration)
    message = i18n.source(message)
    if not message or message == "" then return end
    pcall(function()
        local uiSys = Game.GetUISystem()
        if uiSys then
            local evt = SimpleScreenMessage.new()
            evt.message = tostring(message)
            evt.duration = duration or 4.0
            evt.isShown = true
            uiSys:QueueEvent(evt)
        end
    end)
end

local function fmtTime(seconds)
    local n = tonumber(seconds)
    if not n or n < 0 then return "--:--.--" end
    local m = math.floor(n / 60)
    local s = n - (m * 60)
    return i18n.format("%d:%05.2f", m, s)
end

local function fmtDistance(meters)
    local n = tonumber(meters) or 0
    if n >= 1000 then
        return i18n.format("%.1f km", n / 1000.0)
    end
    return i18n.format("%d m", math.floor(n + 0.5))
end

local function racingState()
    return MTE and MTE.Racing and MTE.Racing.getState and MTE.Racing.getState() or "idle"
end

local function knockoutState()
    return MTE and MTE.Knockout and MTE.Knockout.getState and MTE.Knockout.getState() or "idle"
end

local function activeCareer()
    return MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active() or nil
end

local function currentVehicleKey()
    local tuning = MTE and MTE.Tuning or nil
    local vehicleKey = tuning and tuning._vehicleKey or nil
    if type(vehicleKey) == "string" and vehicleKey ~= "" then
        return vehicleKey
    end
    return nil
end

local function shortVehicleName(vehicleKey)
    if type(vehicleKey) ~= "string" or vehicleKey == "" then
        return "your ride"
    end
    local trimmed = vehicleKey:gsub("^.*[\\/%.]", "")
    if trimmed == "" then
        return vehicleKey
    end
    return trimmed
end

local function formatEddies(amount)
    return i18n.format("%d eddies", math.floor((tonumber(amount) or 0) + 0.5))
end

local function listText(items, maxCount)
    local out = {}
    local limit = math.max(1, tonumber(maxCount) or #items)
    for i = 1, math.min(limit, #(items or {})) do
        out[#out + 1] = tostring(items[i])
    end
    return i18n.concat(out, ", ")
end

local function tradeoffText(summary)
    local strengths = summary and (summary.canonicalStrengths or summary.strengths) or {}
    local weaknesses = summary and (summary.canonicalWeaknesses or summary.weaknesses) or {}
    local strongLabels = {}
    local weakLabels = {}
    for _, entry in ipairs(strengths) do
        strongLabels[#strongLabels + 1] = tostring(entry.label or entry.axis or "")
    end
    for _, entry in ipairs(weaknesses) do
        weakLabels[#weakLabels + 1] = tostring(entry.label or entry.axis or "")
    end
    local gain = #strongLabels > 0 and listText(strongLabels, 2) or nil
    local loss = #weakLabels > 0 and listText(weakLabels, 2) or nil
    if gain and loss then
        return i18n.format("Gains time in %s, bleeds it in %s.", gain, loss)
    end
    if gain then
        return i18n.format("Best phase edge right now: %s.", gain)
    end
    if loss then
        return i18n.format("Softest phase right now: %s.", loss)
    end
    return nil
end

local function effectMetricsText()
    local metrics = MTE and MTE.Metrics or nil
    if not metrics then
        return nil
    end
    local summary = metrics.currentSummary and metrics.currentSummary() or nil
    if type(summary) ~= "table" and metrics.latestSummary then
        summary = metrics.latestSummary()
    end
    if type(summary) ~= "table" then
        return nil
    end

    local launchTime = tonumber(summary.zeroToHundred)
    local pullTime = tonumber(summary.pullEightyToOneFifty)
    local launchSlipAvg = tonumber(summary.launchSlipAvg)
    local launchSlipPeak = tonumber(summary.launchSlipPeak)
    local parts = {}
    if launchTime and launchTime > 0 then
        parts[#parts + 1] = i18n.format("0-100 %s", fmtTime(launchTime))
    end
    if pullTime and pullTime > 0 then
        parts[#parts + 1] = i18n.format("80-150 %s", fmtTime(pullTime))
    end
    if launchSlipAvg and launchSlipPeak then
        parts[#parts + 1] = i18n.format("launch slip %.2f avg / %.2f peak", launchSlipAvg, launchSlipPeak)
    end
    if #parts == 0 then
        return nil
    end
    return (summary.active and "Measured this session: " or "Last measured: ") .. i18n.concat(parts, " | ") .. "."
end

local function contactIntelText(career)
    if not (MTE and MTE.ContactEvents and MTE.ContactEvents.getScoutIntelText) then
        return nil
    end
    return MTE.ContactEvents.getScoutIntelText(career)
end

local function installedPartHighlights(installed)
    local parts = {}
    local order = MTE and MTE.Parts and MTE.Parts.SLOT_ORDER or {}
    for _, slotId in ipairs(order) do
        local entries = installed and installed[slotId] or {}
        if type(entries) == "table" and (entries.name or entries.partId) then
            entries = { entries }
        end
        for _, item in ipairs(entries or {}) do
            if item and item.name then
                parts[#parts + 1] = i18n.format("%s %s", tostring(item.rarity or ""), tostring(item.name))
            end
        end
    end
    return parts
end

local function installedEntriesForSlot(summary, slotId)
    local grouped = summary and summary.installedByCategory and summary.installedByCategory[slotId] or nil
    if type(grouped) == "table" and (#grouped > 0 or next(grouped) ~= nil) then
        return grouped
    end
    local single = summary and summary.installed and summary.installed[slotId] or nil
    if single then
        return { single }
    end
    return {}
end

local function weakestInstalledInfo(entries)
    local weakest = nil
    local weakestIndex = nil
    for index, item in ipairs(entries or {}) do
        if not weakest then
            weakest = item
            weakestIndex = index
        else
            local itemRank = rarityRank(item and item.rarity)
            local weakestRank = rarityRank(weakest and weakest.rarity)
            local itemCondition = tonumber(item and item.condition or 0) or 0
            local weakestCondition = tonumber(weakest and weakest.condition or 0) or 0
            if itemRank < weakestRank
                or (itemRank == weakestRank and itemCondition < weakestCondition)
                or (itemRank == weakestRank and itemCondition == weakestCondition and tostring(item and item.name or "") > tostring(weakest and weakest.name or "")) then
                weakest = item
                weakestIndex = index
            end
        end
    end
    return weakest, weakestIndex
end

local function slotUsage(summary, slotId)
    local entries = installedEntriesForSlot(summary, slotId)
    local capacity = math.max(#entries, tonumber(summary and summary.slotProfile and summary.slotProfile[slotId] or 0) or 0)
    return entries, capacity, #entries, math.max(0, capacity - #entries)
end

local function slotLabel(slotId)
    return tostring((MTE and MTE.Parts and MTE.Parts.SLOTS and MTE.Parts.SLOTS[slotId] and MTE.Parts.SLOTS[slotId].label)
        or (PartsData and PartsData.SLOTS and PartsData.SLOTS[slotId] and PartsData.SLOTS[slotId].label)
        or slotId
        or "slot")
end

local function activeVehicleSummary()
    local career = activeCareer()
    if not career then
        return nil, nil, "No career, no car to work on. Get that sorted first."
    end
    local vehicleKey = currentVehicleKey()
    if not vehicleKey then
        return career, nil, "Hop in the car you want me looking at, then we'll talk."
    end
    if not (MTE and MTE.Parts and MTE.Parts.getVehicleSummary) then
        return career, vehicleKey, "I can't reach the parts line right now. Something's in the way"
    end
    local summary = MTE.Parts.getVehicleSummary(career, vehicleKey)
    if type(summary) ~= "table" then
        return career, vehicleKey, "Can't pull that build right now. Try again in a sec."
    end
    return career, vehicleKey, summary, nil
end

local function rarityRank(rarity)
    if PartsData and PartsData.rarityRank then
        return tonumber(PartsData.rarityRank(rarity) or 0) or 0
    end
    local map = { Common = 1, Street = 2, Pro = 3, Elite = 4 }
    return tonumber(map[tostring(rarity or "")] or 0) or 0
end

local function sortPartsDescending(a, b)
    local ar = rarityRank(a and a.rarity)
    local br = rarityRank(b and b.rarity)
    if ar ~= br then
        return ar > br
    end
    local ac = tonumber(a and a.condition or 0) or 0
    local bc = tonumber(b and b.condition or 0) or 0
    if ac ~= bc then
        return ac > bc
    end
    return tostring(a and a.name or "") < tostring(b and b.name or "")
end

local function bestInventoryPartForSlot(career, vehicleKey, slotId)
    local items = MTE and MTE.Parts and MTE.Parts.getAvailableInventory
        and MTE.Parts.getAvailableInventory(career, vehicleKey, slotId)
        or {}
    table.sort(items, sortPartsDescending)
    return items[1]
end

local function bestCatalogPartForSlot(slotId, installedPartId)
    local defs = PartsData and PartsData.bySlot and PartsData.bySlot(slotId) or {}
    local chosen = nil
    for _, def in ipairs(defs or {}) do
        if def and def.id ~= installedPartId then
            if not chosen or rarityRank(def.rarity) > rarityRank(chosen.rarity) then
                chosen = def
            end
        end
    end
    return chosen
end

local function pickStuUpgrade(career, vehicleKey, summary)
    local best = nil

    for _, slotId in ipairs(MTE and MTE.Parts and MTE.Parts.SLOT_ORDER or {}) do
        local entries, capacity, used, openCount = slotUsage(summary, slotId)
        local current, currentIndex = weakestInstalledInfo(entries)
        local currentRank = rarityRank(current and current.rarity)
        local inventoryItem = bestInventoryPartForSlot(career, vehicleKey, slotId)
        local inventoryRank = inventoryItem and rarityRank(inventoryItem.rarity) or 0
        local catalogItem = bestCatalogPartForSlot(slotId, openCount > 0 and nil or (current and current.partId or nil))
        local catalogRank = catalogItem and rarityRank(catalogItem.rarity) or 0
        local candidate = nil

        if inventoryItem and (openCount > 0 or inventoryRank > currentRank) then
            candidate = {
                kind = "inventory",
                slotId = slotId,
                targetIndex = openCount > 0 and (used + 1) or currentIndex,
                item = inventoryItem,
                score = (openCount > 0 and 10 or 0) + (inventoryRank * 4) - currentRank,
            }
        elseif catalogItem and (openCount > 0 or catalogRank > currentRank) then
            candidate = {
                kind = "purchase",
                slotId = slotId,
                targetIndex = openCount > 0 and (used + 1) or currentIndex,
                item = catalogItem,
                score = (openCount > 0 and 10 or 0) + (catalogRank * 4) - currentRank,
            }
        end

        if candidate and (not best or candidate.score > best.score) then
            best = candidate
        end
    end

    return best
end

local function applyStuTunePreset(summary, tuning)
    local effects = summary and summary.effects and summary.effects.multipliers or {}
    local profileName = "Stu SMS"
    local label = "balanced"

    tuning.resetAll()

    local power = ((tonumber(effects.powerMult) or 1.0)
        + (tonumber(effects.throttleResponse) or 1.0)
        + (tonumber(effects.drivelineEffic) or 1.0)) / 3.0
    local control = ((tonumber(effects.brakingPower) or 1.0)
        + (tonumber(effects.brakeBias) or 1.0)
        + (tonumber(effects.tractionControl) or 1.0)
        + (tonumber(effects.spinPrevention) or 1.0)) / 4.0
    local rotation = ((2.0 - (tonumber(effects.understeerLevel) or 1.0))
        + (tonumber(effects.oversteerLevel) or 1.0)) / 2.0

    if power < 1.02 and power < control then
        label = "attack"
        tuning.set("powerMult", 1.12)
        tuning.set("throttleResponse", 1.10)
        tuning.set("drivelineEffic", 1.08)
        tuning.set("revLimitBehavior", 1.05)
        tuning.set("brakingPower", 0.98)
        tuning.set("tractionControl", 0.96)
        tuning.set("spinPrevention", 0.96)
        profileName = "Stu SMS Attack"
    elseif control < 0.99 or rotation > 1.08 then
        label = "control"
        tuning.set("brakingPower", 1.14)
        tuning.set("brakeBias", 1.10)
        tuning.set("tractionControl", 1.12)
        tuning.set("spinPrevention", 1.10)
        tuning.set("understeerLevel", 1.06)
        tuning.set("oversteerLevel", 0.94)
        tuning.set("powerMult", 1.03)
        tuning.set("throttleResponse", 1.02)
        profileName = "Stu SMS Control"
    else
        tuning.set("powerMult", 1.06)
        tuning.set("throttleResponse", 1.05)
        tuning.set("drivelineEffic", 1.04)
        tuning.set("brakingPower", 1.05)
        tuning.set("brakeBias", 1.03)
        tuning.set("tractionControl", 1.04)
        tuning.set("spinPrevention", 1.04)
        profileName = "Stu SMS Balance"
    end

    tuning.saveProfile(profileName)
    return label, profileName
end

local function tuningBiasText(scratch)
    local setup = type(scratch) == "table" and scratch or {}
    local power = ((tonumber(setup.powerMult) or 1.0)
        + (tonumber(setup.throttleResponse) or 1.0)
        + (tonumber(setup.drivelineEffic) or 1.0)) / 3.0
    local control = ((tonumber(setup.brakingPower) or 1.0)
        + (tonumber(setup.brakeBias) or 1.0)
        + (tonumber(setup.tractionControl) or 1.0)
        + (tonumber(setup.spinPrevention) or 1.0)) / 4.0
    local rotation = ((2.0 - (tonumber(setup.understeerLevel) or 1.0))
        + (tonumber(setup.oversteerLevel) or 1.0)) / 2.0

    if power > control + 0.10 then
        return "power-forward"
    end
    if control > power + 0.10 then
        return "safety-first"
    end
    if rotation > 1.08 then
        return "rotation-heavy"
    end
    return "balanced"
end

local function stuBiasLabel(bias)
    local labels = {
        ["power-forward"] = "power-forward",
        ["safety-first"] = "safety-first",
        ["rotation-heavy"] = "rotation-heavy",
        balanced = "balanced",
    }
    return labels[tostring(bias or "")] or "balanced"
end

local function nativeDriveSnapshot()
    return MTE and MTE.Tuning and MTE.Tuning.getCurrentVehicleDriveSnapshot and MTE.Tuning.getCurrentVehicleDriveSnapshot() or nil
end

local function nativeVehicleProfile()
    return MTE and MTE.Tuning and MTE.Tuning.getCurrentVehicleNativeProfile and MTE.Tuning.getCurrentVehicleNativeProfile() or nil
end

local function stuVehicleDescriptor(vehicleKey, profile)
    local kind = type(profile) == "table" and tostring(profile.vehicleKind or "") or ""
    if kind ~= "bike" and kind ~= "car" then
        local vehicleText = string.lower(tostring(vehicleKey or ""))
        kind = string.find(vehicleText, "bike", 1, true) and "bike" or "car"
    end
    if kind == "bike" then
        return {
            kind = "bike",
            noun = "bike",
            subject = "this bike",
            platform = "the chassis and rider support package",
        }
    end
    return {
        kind = "car",
        noun = "car",
        subject = "this car",
        platform = "the chassis",
    }
end

local function stuHasProfileTag(profile, wanted)
    if type(profile) ~= "table" or type(profile.tags) ~= "table" then
        return false
    end
    for _, tag in ipairs(profile.tags) do
        if tag == wanted then
            return true
        end
    end
    return false
end

local function formatSignedPercent(multiplier)
    local delta = ((tonumber(multiplier) or 1.0) - 1.0) * 100.0
    if math.abs(delta) < 0.5 then
        return "stock"
    end
    return i18n.format("%+d%%", math.floor(delta + (delta >= 0 and 0.5 or -0.5)))
end

local function nativeDriveDeltaLine(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.multipliers) ~= "table" then
        return nil
    end

    local mult = snapshot.multipliers
    local power = ((tonumber(mult.powerMult) or 1.0)
        + (tonumber(mult.throttleResponse) or 1.0)
        + (tonumber(mult.revLimitBehavior) or 1.0)) / 3.0
    local brakes = ((tonumber(mult.brakingPower) or 1.0)
        + (tonumber(mult.brakeBias) or 1.0)
        + (tonumber(mult.engineBraking) or 1.0)) / 3.0
    local stability = ((tonumber(mult.tractionControl) or 1.0)
        + (tonumber(mult.spinPrevention) or 1.0)
        + (tonumber(mult.drivelineEffic) or 1.0)) / 3.0
    local noun = tostring(snapshot.driveKind or "car") == "bike" and "bike" or "car"

    return i18n.format(
        "Native drive map from this %s's record: power %s, brakes %s, stability %s versus stock.",
        noun,
        formatSignedPercent(power),
        formatSignedPercent(brakes),
        formatSignedPercent(stability))
end

local function nativeProfileLine(profile)
    if type(profile) ~= "table" then
        return nil
    end
    local descriptor = stuVehicleDescriptor(profile.vehicleKey, profile)
    local tags = type(profile.tags) == "table" and #profile.tags > 0 and listText(profile.tags, 3) or "balanced"
    return i18n.format("Base %s profile from native drive flats: %s. %s", descriptor.noun, tags, tostring(profile.summary or ""))
end

local function vehicleTemperament(mult, profile, descriptor)
    local power = ((tonumber(mult.powerMult) or 1.0)
        + (tonumber(mult.throttleResponse) or 1.0)
        + (tonumber(mult.drivelineEffic) or 1.0)) / 3.0
    local braking = ((tonumber(mult.brakingPower) or 1.0)
        + (tonumber(mult.brakeBias) or 1.0)) / 2.0
    local stability = ((tonumber(mult.tractionControl) or 1.0)
        + (tonumber(mult.spinPrevention) or 1.0)) / 2.0
    local control = ((tonumber(mult.brakingPower) or 1.0)
        + (tonumber(mult.brakeBias) or 1.0)
        + (tonumber(mult.tractionControl) or 1.0)
        + (tonumber(mult.spinPrevention) or 1.0)) / 4.0
    local rotation = ((2.0 - (tonumber(mult.understeerLevel) or 1.0))
        + (tonumber(mult.oversteerLevel) or 1.0)) / 2.0
    local leadTag = type(profile) == "table" and tostring(profile.leadTag or "balanced") or "balanced"

    local balanceSpread = power - stability
    local brakeSpread = braking - stability
    local headline = nil
    local notes = {}

    local function add(note)
        if type(note) == "string" and note ~= "" and #notes < 3 then
            notes[#notes + 1] = note
        end
    end

    if descriptor.kind == "bike" then
        if leadTag == "rear-lively" or (stuHasProfileTag(profile, "weight-transfer-happy") and rotation >= 1.08) then
            headline = "This bike reacts quickly to load changes. It should turn eagerly, but it will ask the rider to stay ahead of the rear"
        elseif leadTag == "planted" or leadTag == "tied-down" then
            headline = "This bike looks settled through the middle of the corner. It wants confidence more than rescue"
        elseif leadTag == "torque-heavy" or leadTag == "launch-friendly" then
            headline = "This bike is about the first punch. It wants to crack the tire into the asphalt and leave before the run goes long"
        elseif leadTag == "brake-strong" then
            headline = "This bike looks happiest winning time in the stop-and-turn phase, then standing up and driving clean"
        elseif leadTag == "clean-through-the-air" then
            headline = "This bike should make more sense the longer the pull gets. It looks cleaner at speed than most"
        elseif leadTag == "draggy-at-speed" then
            headline = "This bike gives you its best work early, then starts paying a tax once the speed keeps climbing"
        elseif leadTag == "stable-but-flat" then
            headline = "It is a tidy bike underneath, just not delivering enough authority when you ask it to go"
        elseif leadTag == "nose-light" then
            headline = "This bike looks a little light at the nose. It may skim into the corner before it really commits"
        elseif power >= 1.08 and control >= 1.04 then
            headline = "There is a serious bike in this. The pace is real, and the support under it mostly makes sense"
        elseif balanceSpread >= 0.10 then
            headline = "It feels quick before it feels calm. Drive is getting ahead of the support around it"
        elseif balanceSpread <= -0.10 then
            headline = "The support package is ahead of the motor. It should be trustworthy, but it is still leaving speed on the table"
        else
            headline = "It is workable, but this bike still wants a clearer identity"
        end
    elseif power >= 1.10 and braking >= 1.05 and stability >= 1.05 then
        headline = "This is a properly sorted fast car. There is real pace in it, and the platform is mostly strong enough to use it"
    elseif leadTag == "rear-lively" or (stuHasProfileTag(profile, "weight-transfer-happy") and rotation >= 1.08) then
        headline = "This car wants to rotate off load. It should be alive on entry, but the rear is doing more of the conversation than ideal"
    elseif leadTag == "planted" or leadTag == "tied-down" then
        headline = "This car looks planted and coherent. It wants a confident driver more than a rescue job"
    elseif leadTag == "torque-heavy" or leadTag == "launch-friendly" then
        headline = "This car is built around initial shove. The first hit matters more than a glamorous top-end number"
    elseif leadTag == "brake-strong" then
        headline = "This car looks like it wants to win time on entry and brake release, then cash that in on exit"
    elseif leadTag == "clean-through-the-air" then
        headline = "This car should get happier the longer the run gets. It looks cleaner at speed than the average street build"
    elseif leadTag == "draggy-at-speed" then
        headline = "This car is punchy early, but the long pull is paying an aero and drag tax upstairs"
    elseif leadTag == "stable-but-flat" then
        headline = "It is composed and easy to trust, just not getting paid back enough once you ask it to accelerate hard"
    elseif leadTag == "fast-approach" then
        headline = "This car likes arriving with speed. It reads better on approach than it does once you ask it to really stop"
    elseif leadTag == "nose-light" then
        headline = "The front end looks a little light. It may wash into the corner before it ever truly bites"
    elseif power >= 1.10 and stability < 1.00 then
        headline = "Big motor in it, no question, but the rear support is trailing the pace"
    elseif control >= 1.08 and power < 1.02 then
        headline = "It is composed and easy to trust, just not getting paid back enough on exit"
    elseif power <= 0.98 and braking <= 0.98 and stability <= 0.98 then
        headline = "Nothing about it is truly bad, but it is not bringing much authority to the fight yet"
    elseif power >= 1.05 and control >= 1.04 then
        headline = "There is a good, coherent car in this. Nothing feels badly out of line"
    elseif balanceSpread >= 0.10 then
        headline = "It feels fast before it feels settled. Power is starting to outrun the platform"
    elseif balanceSpread <= -0.10 then
        headline = "The chassis is ahead of the motor. It will behave itself, but it is still leaving pace on the table"
    else
        headline = i18n.format("It is serviceable, but %s still wants a clearer direction", descriptor.subject)
    end

    if rotation >= 1.14 then
        add("Turn-in is very sharp, enough that the rear may feel like it is doing extra work to stay with the nose")
    elseif rotation >= 1.08 then
        add("It wants to rotate on entry, which is useful right up until you get greedy with it")
    elseif rotation <= 0.94 then
        add("The nose sounds a little lazy, like it would rather push than commit early")
    end

    if braking >= 1.08 then
        add("It should take a braking zone well and let you lean on that phase of the run")
    elseif braking <= 0.96 then
        add("It may ask for more braking distance than you really want once the speed is up")
    end

    if stability >= 1.08 then
        add("Rear support looks solid, so it should take throttle without feeling too dramatic")
    elseif stability <= 0.96 then
        add("Traction looks like the weak point, so you may have to treat throttle with a little respect")
    end

    if stuHasProfileTag(profile, "clean-through-the-air") and not stuHasProfileTag(profile, "draggy-at-speed") then
        add("Native profile says the long pull should flatter it more than a stop-start fight")
    elseif stuHasProfileTag(profile, "draggy-at-speed") then
        add("Native profile says the first shove matters more than the long top-end run")
    end

    if descriptor.kind == "bike" and stuHasProfileTag(profile, "rear-lively") then
        add("On a bike like this, body timing will matter almost as much as the map")
    end

    if balanceSpread >= 0.12 then
        add(i18n.format("The powertrain is getting ahead of the grip, so %s may feel exciting before it feels clean", descriptor.subject))
    elseif balanceSpread <= -0.12 then
        add("Grip is ahead of power, so it should be tidy but a little too polite")
    elseif braking - power >= 0.08 then
        add("It stops better than it accelerates, which usually means the entry phase will flatter it more than the exit")
    elseif power - braking >= 0.08 then
        add("It has enough shove to matter, but the braking side may not back all of it up")
    end

    if brakeSpread >= 0.10 and stability <= 1.00 then
        add("It should be fine on the way into the corner, then ask a harder question once you are trying to leave it")
    elseif stability - braking >= 0.10 and power >= 1.04 then
        add("It ought to put power down cleanly, but it may still want a calmer hand on initial brake release")
    end

    if #notes > 0 then
        return headline .. ". " .. i18n.concat(notes, ". ")
    end
    return headline
end

local function collectStuOpenSlots(summary)
    local missing = {}
    for _, slotId in ipairs(MTE and MTE.Parts and MTE.Parts.SLOT_ORDER or {}) do
        local _, _, _, openCount = slotUsage(summary, slotId)
        if openCount > 0 then
            missing[#missing + 1] = openCount > 1
                and i18n.format("%s x%d", slotLabel(slotId), openCount)
                or slotLabel(slotId)
        end
    end
    return missing
end

local function collectStuUpgradeLeads(career, vehicleKey, summary)
    local leads = {
        inventory = {},
        catalog = {},
    }

    for _, slotId in ipairs(MTE and MTE.Parts and MTE.Parts.SLOT_ORDER or {}) do
        local entries, _, used, openCount = slotUsage(summary, slotId)
        local current, currentIndex = weakestInstalledInfo(entries)
        local currentRank = rarityRank(current and current.rarity)
        local inventoryItem = bestInventoryPartForSlot(career, vehicleKey, slotId)
        if inventoryItem and (openCount > 0 or rarityRank(inventoryItem.rarity) > currentRank) then
            leads.inventory[#leads.inventory + 1] = {
                slotId = slotId,
                slotName = slotLabel(slotId),
                targetIndex = openCount > 0 and (used + 1) or currentIndex,
                item = inventoryItem,
                current = current,
                isEmpty = openCount > 0,
            }
        else
            local catalogItem = bestCatalogPartForSlot(slotId, openCount > 0 and nil or (current and current.partId or nil))
            if catalogItem and (openCount > 0 or rarityRank(catalogItem.rarity) > currentRank) then
                leads.catalog[#leads.catalog + 1] = {
                    slotId = slotId,
                    slotName = slotLabel(slotId),
                    targetIndex = openCount > 0 and (used + 1) or currentIndex,
                    item = catalogItem,
                    current = current,
                    isEmpty = openCount > 0,
                }
            end
        end
    end

    table.sort(leads.inventory, function(a, b)
        return rarityRank(a and a.item and a.item.rarity) > rarityRank(b and b.item and b.item.rarity)
    end)
    table.sort(leads.catalog, function(a, b)
        return rarityRank(a and a.item and a.item.rarity) > rarityRank(b and b.item and b.item.rarity)
    end)

    return leads
end

local function buildStuAssessment(career, vehicleKey, summary, profile)
    local mult = summary and summary.effects and summary.effects.multipliers or {}
    local installedCount = tonumber(summary and summary.installedCount or 0) or 0
    local ride = shortVehicleName(vehicleKey)
    local descriptor = stuVehicleDescriptor(vehicleKey, profile)
    local temperament = vehicleTemperament(mult, profile, descriptor)
    local missing = collectStuOpenSlots(summary)
    local leads = collectStuUpgradeLeads(career, vehicleKey, summary)
    local tuning = MTE and MTE.Tuning or nil
    local currentBias = stuBiasLabel(tuning and tuning.scratch and tuningBiasText(tuning.scratch) or "balanced")

    local power = ((tonumber(mult.powerMult) or 1.0)
        + (tonumber(mult.throttleResponse) or 1.0)
        + (tonumber(mult.drivelineEffic) or 1.0)) / 3.0
    local control = ((tonumber(mult.brakingPower) or 1.0)
        + (tonumber(mult.brakeBias) or 1.0)
        + (tonumber(mult.tractionControl) or 1.0)
        + (tonumber(mult.spinPrevention) or 1.0)) / 4.0
    local rotation = ((2.0 - (tonumber(mult.understeerLevel) or 1.0))
        + (tonumber(mult.oversteerLevel) or 1.0)) / 2.0

    local totalSlots = tonumber(summary and summary.slotCount or 0) or 0
    local identity = summary and summary.buildIdentity and summary.buildIdentity.headline or "Balanced"
    local fitText = tradeoffText(summary)
    local state = i18n.format("All right... %s is up on the lift. %s build, %d/%d slots filled. %s.", ride, tostring(identity), installedCount, totalSlots, temperament)
    if fitText then
        state = state .. " " .. fitText
    end
    local problem = nil
    local suggestion = nil
    local tunePlan = "balanced"

    if #missing >= 2 then
        problem = i18n.format("First thing jumping out? Too much hardware is still missing. You've got %s sitting empty.", listText(missing, 3))
        if leads.inventory[1] then
            suggestion = i18n.format("I'd start by bolting %s into %s before we pretend setup is the issue.", tostring(leads.inventory[1].item.name or "that part"), tostring(leads.inventory[1].slotName or "the open slot"))
        elseif leads.catalog[1] then
            suggestion = i18n.format("I'd start by sourcing %s for %s. Car's too bare for setup work to mean much yet.", tostring(leads.catalog[1].item.name or "fresh hardware"), tostring(leads.catalog[1].slotName or "that slot"))
        else
            suggestion = "I'd start with engine, brakes, or handling hardware before you go chasing setup detail."
        end
        tunePlan = "attack"
    elseif leads.inventory[1] and leads.inventory[1].isEmpty then
        problem = i18n.format("Thing is, you've already got usable hardware on the shelf while %s is still empty.", tostring(leads.inventory[1].slotName or "a slot"))
        suggestion = i18n.format("I'd bolt on %s first. That's pace you already paid for.", tostring(leads.inventory[1].item.name or "that part"))
    elseif leads.inventory[1] then
        problem = i18n.format("Thing dragging it down? %s. The rest of the build is already ahead of it.", tostring(leads.inventory[1].slotName or "one slot"))
        suggestion = i18n.format("I'd swap in %s from inventory. No point leaving better metal in the box.", tostring(leads.inventory[1].item.name or "the better part"))
    elseif stuHasProfileTag(profile, "rear-lively") and (rotation > 1.08 or control < 1.03) then
        problem = descriptor.kind == "bike"
            and "The rear of the bike is trying to finish the corner for you. It will feel fun right up until it starts asking for too much trust."
            or "The rear of the car is trying to finish the corner for you. It will feel alive right up until it starts asking for too much trust."
        suggestion = "I'd calm the map down. More brake support, more stability, less snap on release."
        tunePlan = "control"
    elseif stuHasProfileTag(profile, "draggy-at-speed") and not stuHasProfileTag(profile, "clean-through-the-air") and power >= 1.04 then
        problem = descriptor.kind == "bike"
            and "The bike gives you a strong first shove, then starts leaning on drag once the run gets long."
            or "The car gives you a strong first shove, then starts leaning on drag once the run gets long."
        suggestion = leads.catalog[1]
            and i18n.format("I'd source %s for %s, then keep the setup tidy instead of just begging it for more power.", tostring(leads.catalog[1].item.name or "a cleaner part"), tostring(leads.catalog[1].slotName or "the weak slot"))
            or "I'd keep the setup clean and stable first. This one wants preserved speed more than blind extra shove."
    elseif (stuHasProfileTag(profile, "planted") or stuHasProfileTag(profile, "tied-down") or stuHasProfileTag(profile, "front-stable") or stuHasProfileTag(profile, "stable-but-flat")) and power < 1.02 and power < control then
        problem = descriptor.kind == "bike"
            and "The bike is calmer than it is urgent. The support package is ready for more than the engine is currently giving back."
            or "The car is calmer than it is urgent. The chassis is ready for more than the engine is currently giving back."
        suggestion = leads.catalog[1]
            and i18n.format("I'd source %s for %s, then lean the map forward.", tostring(leads.catalog[1].item.name or "a stronger part"), tostring(leads.catalog[1].slotName or "the weak slot"))
            or "I'd lean the setup toward attack. This platform can carry more drive than it currently has."
        tunePlan = "attack"
    elseif (stuHasProfileTag(profile, "torque-heavy") or stuHasProfileTag(profile, "launch-friendly") or stuHasProfileTag(profile, "traction-sensitive")) and stability < 1.00 then
        problem = descriptor.kind == "bike"
            and "The first hit is stronger than the support behind it. The bike wants throttle, but the rear is not always ready to cash the check."
            or "The first hit is stronger than the support behind it. The car wants throttle, but the rear is not always ready to cash the check."
        suggestion = "I'd give it more support before I ask for more shove. Stability first, then power."
        tunePlan = "control"
    elseif control < 0.98 then
        problem = i18n.format("It's a little too nervous right now. Under brake and in rotation, %s is asking for more than the stability package can hold.", descriptor.subject)
        suggestion = "I'd lean the map toward control and stop asking the rear axle to save the whole conversation."
        tunePlan = "control"
    elseif power < 1.02 and power < control then
        problem = "It's neat enough, but it falls flat on exit. You're carrying speed in and not getting paid back out."
        suggestion = leads.catalog[1]
            and i18n.format("I'd source %s for %s, then nudge the map forward.", tostring(leads.catalog[1].item.name or "a stronger part"), tostring(leads.catalog[1].slotName or "the weak slot"))
            or "I'd push the setup toward attack. Engine and driveline are the cleanest gains."
        tunePlan = "attack"
    elseif rotation > 1.10 and control < 1.03 then
        problem = "You can feel where the snap comes from. Rotation is coming in harder than the support around it."
        suggestion = "I'd calm the map down. More brake support, more stability, less drama."
        tunePlan = "control"
    elseif leads.catalog[1] then
        problem = i18n.format("Honestly, it's sound. But %s is still a half-step behind the rest of the %s.", tostring(leads.catalog[1].slotName or "one slot"), descriptor.noun)
        suggestion = i18n.format("I'd source %s if you want the cleanest gain without reinventing the build.", tostring(leads.catalog[1].item.name or "the next part"))
    else
        problem = i18n.format("Nothing terminal. The %s is in a workable window, just leaning %s right now.", descriptor.noun, currentBias)
        suggestion = "I'd trim it, not tear it all the way back down."
    end

    return {
        state = state,
        problem = problem,
        suggestion = suggestion,
        currentBias = currentBias,
        tunePlan = tunePlan,
        highlights = installedPartHighlights(summary and summary.installed or {}),
        leads = leads,
        missing = missing,
    }
end

local function currentEventSummary(career)
    local event = MTE and MTE.Championships and MTE.Championships.currentEvent
        and MTE.Championships.currentEvent(career)
        or nil
    if type(event) ~= "table" then
        return nil, "No career heat is scheduled right now."
    end

    local eventType = tostring(event.eventType or "race")
    local label = tostring(event.trackName or event.titleLabel or event.districtLabel or event.district or "Night City")
    local round = tonumber(event.round or 0)
    local fieldSize = tonumber(event.fieldSize or 0)
    local pieces = {}

    if round > 0 then
        pieces[#pieces + 1] = i18n.format("Rd %d", round)
    end
    pieces[#pieces + 1] = label
    pieces[#pieces + 1] = eventType == "knockout" and "knockout" or (eventType == "drag" and "drag" or "race")
    if fieldSize > 0 then
        pieces[#pieces + 1] = i18n.format("%d-car field", fieldSize)
    end

    return event, i18n.concat(pieces, " | ")
end

local function wagerAmountForTier(career, ratio)
    if not (career and MTE and MTE.Careers and MTE.Careers.maxStake) then
        return 0
    end
    local maxStake = tonumber(MTE.Careers.maxStake(career) or 0)
    if maxStake <= 0 then
        return 0
    end
    local amount = math.floor((maxStake * math.max(0.0, math.min(1.0, tonumber(ratio) or 0.0))) / 100.0 + 0.5) * 100
    return math.max(100, amount)
end

local function ensureActiveCareer()
    local career = activeCareer()
    if career then return career, nil end
    if not (MTE and MTE.Careers and MTE.Careers.create and MTE.Careers.select) then
        return nil, nil
    end

    local created = MTE.Careers.create("NCM Rookie")
    if created and created.id then
        MTE.Careers.select(created.id)
    end
    return activeCareer() or created, "Created NCM Rookie career profile."
end

local function isIdle()
    return racingState() == "idle" and knockoutState() == "idle"
end

local function setPhoneFact(name, value)
    local ok = pcall(function()
        local qs = Game.GetQuestsSystem()
        if qs then
            if qs.SetFactStr then
                qs:SetFactStr(name, tonumber(value) or 0)
            else
                qs:SetFact(name, tonumber(value) or 0)
            end
        end
    end)
    return ok == true
end

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, innerValue in pairs(value) do
        result[key] = copyValue(innerValue)
    end
    return result
end

local FOREMAN_BUILDER_STEP_FACT = "ncm_foreman_builder_step"
local FOREMAN_BUILDER_TYPE_FACT = "ncm_foreman_builder_type"
local CUSTOM_RACE_BUILDER_STEP = {
    INACTIVE = 0,
    RACE_TYPE = 1,
    FIELD_SIZE = 2,
    START_TYPE = 3,
    DIFFICULTY = 4,
    LOCATION = 5,
    SUMMARY = 6,
}

local CUSTOM_FIELD_OPTIONS = {
    four = { totalCars = 4, aiRivals = 3, label = "4-car field" },
    six = { totalCars = 6, aiRivals = 5, label = "6-car field" },
    eight = { totalCars = 8, aiRivals = 7, label = "8-car field" },
    ten = { totalCars = 10, aiRivals = 9, label = "10-car field" },
}

local CUSTOM_DIFFICULTY_OPTIONS = {
    street = {
        label = "Street",
        tierMin = 1,
        tierMax = 2,
        prestigeMin = 1,
        prestigeMax = 2,
        prestigeWeighting = "mostly_low",
        knockout = { eliminationInterval = 90, trafficMode = "none", combatMode = "disabled" },
    },
    serious = {
        label = "Serious",
        tierMin = 2,
        tierMax = 4,
        prestigeMin = 2,
        prestigeMax = 4,
        prestigeWeighting = "mixed",
        knockout = { eliminationInterval = 60, trafficMode = "normal", combatMode = "allowed" },
    },
    elite = {
        label = "Elite",
        tierMin = 4,
        tierMax = 5,
        prestigeMin = 4,
        prestigeMax = 5,
        prestigeWeighting = "mostly_high",
        knockout = { eliminationInterval = 40, trafficMode = "heavy", combatMode = "allowed" },
    },
}

local CUSTOM_LOCATION_OPTIONS = {
    any = { label = "Anywhere", regions = {} },
    watson = { label = "Watson", regions = { "Watson" } },
    westbrook = { label = "Westbrook", regions = { "Westbrook" } },
    heywood = { label = "Heywood", regions = { "Heywood" } },
    pacifica = { label = "Pacifica", regions = { "Pacifica" } },
    santo_domingo = { label = "Santo Domingo", regions = { "Santo Domingo" } },
    city_center = { label = "City Center", regions = { "City Center" } },
    badlands = { label = "Badlands", regions = { "Badlands" } },
}

local customRaceBuilder = nil
local deferredPhoneAction = nil
local response

local function scheduleDeferredPhoneAction(run)
    if deferredPhoneAction then
        return false
    end
    deferredPhoneAction = {
        frames = 0,
        seq = nil,
        run = run,
    }
    return true
end

local function queueDeferredCommand(run, pendingMessage, busyMessage, queueErrorMessage)
    if deferredPhoneAction then
        return response(false, busyMessage or "Still locking the last board.")
    end

    local queued = scheduleDeferredPhoneAction(run)
    if not queued then
        return response(false, queueErrorMessage or "Could not queue that command.")
    end

    return response(true, pendingMessage or "Working it.", {
        silent = true,
        suppressPhoneResponse = true,
        deferPhoneResponse = true,
    })
end

local function setBuilderStep(step)
    if customRaceBuilder then
        customRaceBuilder.step = step
    end
    setPhoneFact(FOREMAN_BUILDER_STEP_FACT, step)
end

local function clearCustomRaceBuilder()
    customRaceBuilder = nil
    setBuilderStep(CUSTOM_RACE_BUILDER_STEP.INACTIVE)
    setPhoneFact(FOREMAN_BUILDER_TYPE_FACT, 0)
end

local function activeCustomRaceBuilder(career)
    if not customRaceBuilder then
        return nil
    end
    if not career or customRaceBuilder.careerId ~= career.id then
        clearCustomRaceBuilder()
        return nil
    end
    return customRaceBuilder
end

local function beginCustomRaceBuilder(career)
    customRaceBuilder = {
        careerId = career and career.id or nil,
        step = CUSTOM_RACE_BUILDER_STEP.RACE_TYPE,
    }
    setBuilderStep(CUSTOM_RACE_BUILDER_STEP.RACE_TYPE)
    setPhoneFact(FOREMAN_BUILDER_TYPE_FACT, 0)
    return "Let's build it clean. What kind of race are you calling?\nSprint, drag, or knockout?"
end

local function customFieldPrompt()
    return "How many cars total?\n4-car, 6-car, 8-car, or 10-car field?"
end

local function customStartPrompt()
    return "How do you want them launched?\nGrid, rolling, or side-by-side?"
end

local function customDifficultyPrompt(isKnockout)
    if isKnockout then
        return "How vicious do you want the knockout?\nStreet, serious, or elite?"
    end
    return "How hard do you want the field?\nStreet, serious, or elite?"
end

local function customLocationPrompt()
    return "Where do you want it?\nAnywhere, Watson, Westbrook, Heywood, Pacifica, Santo Domingo, City Center, or Badlands?"
end

local function customBuilderPrompt(builder)
    if not builder then
        return "Let's build it clean. What kind of race are you calling?\nSprint, drag, or knockout?"
    end

    local step = tonumber(builder.step or CUSTOM_RACE_BUILDER_STEP.INACTIVE) or CUSTOM_RACE_BUILDER_STEP.INACTIVE
    if step == CUSTOM_RACE_BUILDER_STEP.RACE_TYPE then
        return "Let's build it clean. What kind of race are you calling?\nSprint, drag, or knockout?"
    end
    if step == CUSTOM_RACE_BUILDER_STEP.FIELD_SIZE then
        return customFieldPrompt()
    end
    if step == CUSTOM_RACE_BUILDER_STEP.START_TYPE then
        return customStartPrompt()
    end
    if step == CUSTOM_RACE_BUILDER_STEP.DIFFICULTY then
        return customDifficultyPrompt(builder.raceType == "knockout")
    end
    if step == CUSTOM_RACE_BUILDER_STEP.LOCATION then
        return customLocationPrompt()
    end
    if step == CUSTOM_RACE_BUILDER_STEP.SUMMARY then
        return customSummaryText(builder)
    end
    return "Let's build it clean. What kind of race are you calling?\nSprint, drag, or knockout?"
end

local function customBuilderPreferredRegion(builder)
    local regions = builder and builder.preferredRegions or nil
    if type(regions) ~= "table" or #regions == 0 then
        return nil
    end
    return regions[1]
end

local function pickCustomRaceRoot(builder)
    if not builder or builder.raceType == "knockout" then
        return nil
    end
    if not (MTE and MTE.Roots and MTE.Roots.pickForCareer) then
        return nil
    end

    local ok, root = pcall(MTE.Roots.pickForCareer, {
        eventType = builder.raceType == "drag" and "drag" or "sprint",
        preferredRegion = customBuilderPreferredRegion(builder),
    })
    if not ok or type(root) ~= "table" or type(root.rootId) ~= "string" or root.rootId == "" then
        return nil
    end
    return root
end

local function customSummaryText(builder)
    local lines = {
        builder.raceType == "knockout" and "Knockout draft" or "Custom race draft",
        i18n.format("Type: %s", tostring(builder.raceLabel or builder.raceType or "Race")),
        i18n.format("Field: %s", tostring(builder.fieldLabel or "Unspecified")),
    }

    if builder.startLabel then
        lines[#lines + 1] = i18n.format("Start: %s", tostring(builder.startLabel))
    end
    lines[#lines + 1] = i18n.format("Difficulty: %s", tostring(builder.difficultyLabel or "Unspecified"))

    if builder.raceType == "knockout" then
        lines[#lines + 1] = i18n.format("Circuit: %s", tostring(builder.locationLabel or "Night City loop"))
    else
        lines[#lines + 1] = i18n.format("Where: %s", tostring(builder.locationLabel or "Anywhere"))
    end

    lines[#lines + 1] = "Confirm it or scrap it."
    return i18n.concat(lines, "\n")
end

local function applyCustomDifficulty(builder, key)
    local def = CUSTOM_DIFFICULTY_OPTIONS[key]
    if not def then
        return false
    end
    builder.difficultyKey = key
    builder.difficultyLabel = def.label
    return true
end

local function applyCustomLocation(builder, key)
    local def = CUSTOM_LOCATION_OPTIONS[key]
    if not def then
        return false
    end
    builder.locationKey = key
    builder.locationLabel = def.label
    builder.preferredRegions = copyValue(def.regions or {})
    return true
end

local function customRaceDraftOverrides(builder)
    local difficulty = CUSTOM_DIFFICULTY_OPTIONS[builder.difficultyKey or "serious"] or CUSTOM_DIFFICULTY_OPTIONS.serious
    local preferredRoot = pickCustomRaceRoot(builder)
    local overrides = {
        raceType = builder.raceType,
        quickRaceMode = "standard",
        defaultFieldSize = builder.aiRivals,
        defaultStartType = builder.startType,
        quickRaceDriverTierMin = difficulty.tierMin,
        quickRaceDriverTierMax = difficulty.tierMax,
        quickRacePrestigeMin = difficulty.prestigeMin,
        quickRacePrestigeMax = difficulty.prestigeMax,
        quickRacePrestigeWeighting = difficulty.prestigeWeighting,
        preferredRegions = copyValue(builder.preferredRegions or {}),
        lapCount = 1,
        routeMode = preferredRoot and "root" or "random",
        selectedRootId = preferredRoot and preferredRoot.rootId or nil,
        selectedStartNodeId = preferredRoot and preferredRoot.startNodeId or nil,
        selectedFinishNodeId = preferredRoot and preferredRoot.endNodeId or nil,
    }
    if builder.raceType == "drag" then
        overrides.defaultStartType = "sidebyside"
        overrides.qualiEnabled = false
    end
    return overrides
end

local function confirmCustomRaceBuilder(R, K, career, builderOverride)
    local builder = builderOverride or activeCustomRaceBuilder(career)
    if not builder or builder.step ~= CUSTOM_RACE_BUILDER_STEP.SUMMARY then
        return false, "No custom race draft is ready to confirm."
    end

    if builder.raceType == "knockout" then
        local difficulty = CUSTOM_DIFFICULTY_OPTIONS[builder.difficultyKey or "serious"] or CUSTOM_DIFFICULTY_OPTIONS.serious
        local ok, err = call(K, "openConfig", false, {
            autoConfirm = true,
            circuitId = builder.circuitId,
            fieldSize = builder.aiRivals,
            eliminationInterval = difficulty.knockout.eliminationInterval,
            trafficMode = difficulty.knockout.trafficMode,
            combatMode = difficulty.knockout.combatMode,
        })
        if ok == true then
            clearCustomRaceBuilder()
        end
        return ok == true, ok and "Knockout grid is set. Route in or call it off." or (err or "Couldn't stage the knockout card, sorry.")
    end

    local opened, openErr = call(R, "openConfig", false, { sourceType = "quick_race" })
    if opened ~= true then
        return false, openErr or "Can't access the quick race setup right now."
    end

    local ok, err = call(R, "confirmConfig", false, customRaceDraftOverrides(builder))
    if ok == true then
        clearCustomRaceBuilder()
    end
    return ok == true, ok and "Your custom race is locked. Route in, qualify, or cancel." or (err or "That custom setup didnâ€™t go through. Run it again.")
end

local function scrapCustomRaceBuilder(career)
    if not activeCustomRaceBuilder(career) then
        clearCustomRaceBuilder()
        return true, "No custom draft is open."
    end
    clearCustomRaceBuilder()
    return true, "Custom draft scrubbed clear."
end

response = function(ok, message, data)
    message = i18n.source(message)
    local payload = data or {}
    if payload.builderStep == nil then
        payload.builderStep = customRaceBuilder and tonumber(customRaceBuilder.step or CUSTOM_RACE_BUILDER_STEP.INACTIVE) or CUSTOM_RACE_BUILDER_STEP.INACTIVE
    end
    local silent = payload.silent == true
    if ok then
        print("[NCM/RaceCommands] " .. tostring(message or "OK"))
    else
        print("[NCM/RaceCommands] " .. tostring(message or "Command failed"))
    end
    if not silent then
        notify(message, ok and 4.0 or 5.0)
    end
    return {
        ok = ok == true,
        message = tostring(message or (ok and "OK" or "Command failed")),
        data = payload,
    }
end

function Commands.responseContactId(commandOrId)
    local commandId = tonumber(commandOrId) or 0
    if commandId == Commands.ID.QUICK_RACE
        or commandId == Commands.ID.KNOCKOUT_SETUP
        or commandId == Commands.ID.QUICK_RACE_REFRESH then
        return "ncm_quickie"
    end
    if commandId >= Commands.ID.VIEW_CAR_STATUS and commandId <= Commands.ID.OPEN_TUNING then
        return "ncm_setup_stu"
    end
    if commandId == Commands.ID.SETUP_ACCEPT_CONTRACT or commandId == Commands.ID.SETUP_DECLINE_CONTRACT then
        return "ncm_setup_stu"
    end
    if commandId == Commands.ID.STATUS
        or commandId == Commands.ID.STANDINGS
        or commandId == Commands.ID.STATS
        or commandId == Commands.ID.VIEW_PLAYER_STATS
        or commandId == Commands.ID.REROLL_FAN_MESSAGE then
        return "ncm_ledger"
    end
    if (commandId >= Commands.ID.SCOUT_STATUS and commandId <= Commands.ID.SCOUT_WATCHLIST)
        or (commandId >= Commands.ID.SCOUT_AMBIENT_HEAT and commandId <= Commands.ID.SCOUT_SIGN_TARGET_THREE)
        or commandId == Commands.ID.SCOUT_ACCEPT_LEAK
        or commandId == Commands.ID.SCOUT_DECLINE_LEAK then
        return "ncm_scout"
    end
    if commandId == Commands.ID.WAGER_MAX
        or (commandId >= Commands.ID.WAGER_CLEAR and commandId <= Commands.ID.WAGER_STREAK_FIVE)
        or commandId == Commands.ID.WAGER_BOARD
        or (commandId >= Commands.ID.WAGER_FAVORITE and commandId <= Commands.ID.WAGER_PICK_VALUE) then
        return "ncm_bookie"
    end
    if commandId == Commands.ID.SETUP_SCHEDULED
        or commandId == Commands.ID.OPEN_CUSTOM_RACE_FLOW
        or commandId == Commands.ID.CONFIRM_PREVIEW
        or commandId == Commands.ID.CANCEL
        or (commandId >= Commands.ID.TRACK_START and commandId <= Commands.ID.RESTART)
        or (commandId >= Commands.ID.CUSTOM_TYPE_SPRINT and commandId <= Commands.ID.CUSTOM_SCRAP)
        or (commandId >= Commands.ID.CONTROL_AMBIENT_STATUS and commandId <= Commands.ID.CONTROL_SIMULATE_MANAGED_RUN) then
        return "ncm_control"
    end
    return "ncm_motorsports"
end

local function controlBoardResponse(ok, message, data)
    local payload = data or {}
    if ok == true then
        payload.returnToControlBoard = true
    end
    return response(ok, message, payload)
end

local function firstQuickRaceKnockoutCircuit()
    local circuits = MTE and MTE.KnockoutCircuits and MTE.KnockoutCircuits.quickRaceAll
        and MTE.KnockoutCircuits.quickRaceAll()
        or {}
    return circuits[1], circuits
end

local function findCircuitById(circuitId, circuits)
    if not circuitId or type(circuits) ~= "table" then return nil end
    for _, circuit in ipairs(circuits) do
        if circuit.id == circuitId then
            return circuit
        end
    end
    return nil
end

local function launchQuickRaceKnockout(draft)
    if not (MTE and MTE.Knockout and MTE.Knockout.openConfig) then
        return false, "Knockout module is not loaded."
    end

    local fallback, circuits = firstQuickRaceKnockoutCircuit()
    local circuit = findCircuitById(draft and draft.quickRaceKnockoutCircuitId, circuits) or fallback
    if not circuit then
        return false, "No knockout circuits are configured."
    end

    local maxAiField = MTE.KnockoutCircuits and MTE.KnockoutCircuits.getMaxAIFieldSize
        and MTE.KnockoutCircuits.getMaxAIFieldSize(circuit)
        or math.max(1, #(circuit.checkpoints or {}) - 1)

    local ok, err = MTE.Knockout.openConfig({
        circuitId = circuit.id,
        fieldSize = maxAiField,
        trafficMode = draft and draft.quickRaceKnockoutTrafficMode or "normal",
        combatMode = draft and draft.quickRaceKnockoutCombatMode or "allowed",
        autoConfirm = true,
    })
    if ok and MTE.Racing and MTE.Racing.closeConfig then
        MTE.Racing.closeConfig()
    end
    return ok, err
end

local activePhoneOffer = nil

local function clearActivePhoneOffer()
    activePhoneOffer = nil
    setPhoneFact("ncm_phone_quickie_offer_active", 0)
end

local function lockQuickRacePreviewDraft(preview)
    local draft = copyValue(preview and preview.draft or {})
    local cfg = preview and preview.config or {}

    draft.lapCount = cfg.lapCount or draft.lapCount
    draft.raceType = cfg.raceType or draft.raceType
    draft.defaultStartType = cfg.startType or draft.defaultStartType
    draft.defaultFieldSize = cfg.fieldSize or draft.defaultFieldSize
    draft.vehicleClass = cfg.vehicleClass or draft.vehicleClass

    if cfg.routeMode == "root" and cfg.rootId then
        draft.routeMode = "root"
        draft.selectedRootId = cfg.rootId
    elseif cfg.nodeA and cfg.nodeA.id and cfg.nodeB and cfg.nodeB.id then
        draft.routeMode = "picked"
        draft.selectedStartNodeId = cfg.nodeA.id
        draft.selectedFinishNodeId = cfg.nodeB.id
    end

    if cfg.quickRaceEnduranceCircuitId then
        draft.quickRaceEnduranceCircuitId = cfg.quickRaceEnduranceCircuitId
    end

    return draft
end

local function formatTierBand(tierMin, tierMax)
    if tierMin and tierMax and tierMin ~= tierMax then
        return i18n.format("%s-%s", tostring(tierMin), tostring(tierMax))
    end
    return tostring(tierMin or tierMax or "Mixed")
end

local function formatPrestigeBand(prestigeMin, prestigeMax)
    local minValue = tonumber(prestigeMin)
    local maxValue = tonumber(prestigeMax)
    if not minValue and not maxValue then
        return nil
    end
    minValue = minValue or maxValue or 1
    maxValue = maxValue or minValue
    if minValue == maxValue then
        return i18n.format("P%d", minValue)
    end
    return i18n.format("P%d-P%d", minValue, maxValue)
end

local function vehicleRestrictionText(vehicleClass)
    if type(vehicleClass) ~= "string" or vehicleClass == "" then
        return "Open class"
    end

    local labels = {
        Bike = "Bikes only",
        Muscle = "Muscle only",
        Sport = "Sport only",
        Tech = "Tech only",
        Nomad = "Nomads only",
    }
    return labels[vehicleClass] or (tostring(vehicleClass) .. " only")
end

local function buildQuickRaceOfferText(preview, report)
    local cfg = preview and preview.config or {}
    local draft = preview and preview.draft or {}
    local startName = cfg.nodeA and (cfg.nodeA.name or cfg.nodeA.id) or "somewhere hot"
    local finishName = cfg.nodeB and (cfg.nodeB.name or cfg.nodeB.id) or "somewhere louder"
    local routeText = startName == finishName
        and i18n.format("around %s", tostring(startName))
        or i18n.format("from %s to %s", tostring(startName), tostring(finishName))

    local raceType = tostring(cfg.raceType or "sprint")
    local typeText = raceType == "drag" and "drag"
        or (raceType == "endurance" and "endurance run" or "race")
    local distanceText = fmtDistance(cfg.distance)
    local lapCount = math.max(1, math.floor(tonumber(cfg.lapCount) or 1))
    local lapText = lapCount == 1 and "1 lap" or i18n.format("%d laps", lapCount)
    local tierText = formatTierBand(draft.quickRaceDriverTierMin, draft.quickRaceDriverTierMax)
    local prestigeText = formatPrestigeBand(draft.quickRacePrestigeMin, draft.quickRacePrestigeMax)
    local fieldText = prestigeText and i18n.format("%s, %s", tierText, prestigeText) or tierText
    local rivals = math.max(0, #(preview and preview.field or {}))
    local rivalText = i18n.format("%d rival%s", rivals, rivals == 1 and "" or "s")
    local restrictionText = vehicleRestrictionText(cfg.vehicleClass)

    local offer = i18n.format(
        "Got one. %s %s. %s. %s. %s, %s.",
        tostring(distanceText),
        tostring(typeText),
        tostring(routeText),
        tostring(restrictionText),
        tostring(rivalText),
        tostring(fieldText))

    if lapCount > 1 then
        offer = offer .. " " .. tostring(lapText) .. "."
    end

    if report and report.summary and report.summary ~= "" and report.isBlocking ~= true then
        offer = offer .. " Heads up: " .. tostring(report.summary) .. "."
    end

    return offer .. " You in?"
end

local function routeDisplayText(cfg)
    local config = type(cfg) == "table" and cfg or {}
    if type(config.trackName) == "string" and config.trackName ~= "" then
        return tostring(config.trackName)
    end
    local startName = config.nodeA and (config.nodeA.name or config.nodeA.id) or "Unknown"
    local finishName = config.nodeB and (config.nodeB.name or config.nodeB.id) or "Unknown"
    if startName == finishName then
        return tostring(startName)
    end
    return i18n.format("%s -> %s", tostring(startName), tostring(finishName))
end

local function activeRaceBoardText(stateOverride)
    local state = tostring(stateOverride or racingState())
    local cfg = MTE and MTE.Racing and MTE.Racing.getConfig and MTE.Racing.getConfig() or {}
    local route = routeDisplayText(cfg)
    local raceType = tostring(cfg.raceType or "sprint")
    local typeText = raceType == "drag" and "drag"
        or (raceType == "endurance" and "endurance" or "race")
    local distanceText = fmtDistance(cfg.distance)
    local fieldSize = math.max(1, tonumber(cfg.fieldSize or 0))
    local lapCount = math.max(1, math.floor(tonumber(cfg.lapCount) or 1))
    local startType = tostring(cfg.startType or "grid")
    local lines = {
        i18n.format("Current race: %s", route),
        i18n.format("%s | %s | %s | %d-car field", distanceText, typeText, startType, fieldSize),
    }

    if lapCount > 1 then
        lines[#lines + 1] = i18n.format("Laps: %d", lapCount)
    end
    if cfg.vehicleClass and tostring(cfg.vehicleClass) ~= "" then
        lines[#lines + 1] = vehicleRestrictionText(cfg.vehicleClass)
    end

    if cfg.spectatorMode == true then
        if state == "prerace" then
            lines[#lines + 1] = "Live ambient grid is staged. Route in, start the countdown, or tell Foreman to scrub the sim."
        elseif state == "countdown" or state == "racing" then
            lines[#lines + 1] = "Ambient spectate is live. Stay on the board or tell Foreman to resolve it now."
        else
            lines[#lines + 1] = "Ambient spectate is staged through the normal race board."
        end
    elseif state == "prerace" then
        lines[#lines + 1] = "Grid is staged. Route to the race, run quali, or cancel it."
    elseif state == "quali" then
        lines[#lines + 1] = "Qualifying is live. Route to the next target or call a forfeit / DNF."
    elseif state == "countdown" or state == "racing" then
        lines[#lines + 1] = "Current race is live. Route to the next target or log a forfeit / DNF."
    elseif state == "results" then
        lines[#lines + 1] = "Results are posted. Clear them or run it back."
    else
        lines[#lines + 1] = "Review the race, confirm it, or scrub it from here."
    end

    return i18n.concat(lines, "\n")
end

local function createQuickRacePhoneOffer(career, createdMsg)
    local ok, err = call(MTE and MTE.Racing, "openQuickRaceConfig", false)
    if ok ~= true then
        clearActivePhoneOffer()
        return false, err or "Couldn't line up a quick race."
    end

    local draft = MTE and MTE.Racing and MTE.Racing.getDraft and MTE.Racing.getDraft() or {}
    local report = MTE and MTE.Racing and MTE.Racing.evaluateQuickRaceCompatibility and MTE.Racing.evaluateQuickRaceCompatibility(draft) or nil
    if report and report.isBlocking then
        if MTE and MTE.Racing and MTE.Racing.closeConfig then
            pcall(MTE.Racing.closeConfig)
        end
        clearActivePhoneOffer()
        return false, report.summary or (report.blockingIssues and report.blockingIssues[1]) or "Current setup does not fit the Quick Race rules."
    end

    local previewOk, preview = call(MTE and MTE.Racing, "previewDraft", false)
    if previewOk ~= true then
        if MTE and MTE.Racing and MTE.Racing.closeConfig then
            pcall(MTE.Racing.closeConfig)
        end
        clearActivePhoneOffer()
        return false, preview or "Could not build you a quick race offer,"
    end

    activePhoneOffer = {
        kind = "quick_race",
        preview = preview,
        report = report,
        careerId = career and career.id or nil,
        confirmDraft = lockQuickRacePreviewDraft(preview),
    }
    setPhoneFact("ncm_phone_quickie_offer_active", 1)

    local offerText = buildQuickRaceOfferText(preview, report)
    if createdMsg and createdMsg ~= "" then
        offerText = tostring(createdMsg) .. " " .. offerText
    end
    return true, offerText
end

local function playerChampPosition(career)
    local season = career and MTE and MTE.Championships and MTE.Championships.activeSeason
        and MTE.Championships.activeSeason(career)
        or nil
    if not season or not MTE.Championships.driverStandings then return nil, nil, nil end
    local standings = MTE.Championships.driverStandings(season)
    for i, row in ipairs(standings or {}) do
        if row.driverId == "player" then
            return i, row.points or 0, standings
        end
    end
    return nil, nil, standings
end

function Commands.statusText()
    local career = activeCareer()
    local rs = racingState()
    local ks = knockoutState()
    local lines = {}

    lines[#lines + 1] = "Night City Motorsports"
    if career then
        lines[#lines + 1] = i18n.format("%s [%s]  Rep %d",
            tostring(career.name or "Career"),
            tostring(career.tier or "?"),
            tonumber(career.rep or 0))
        local pos, pts = playerChampPosition(career)
        if pos then
            lines[#lines + 1] = i18n.format("Championship: P%d, %d pts", pos, tonumber(pts or 0))
        end
    else
        lines[#lines + 1] = "No active career."
    end

    if career and MTE and MTE.AmbientRaces and MTE.AmbientRaces.statusSummaryLine then
        local ambientLine = MTE.AmbientRaces.statusSummaryLine(career)
        if ambientLine and ambientLine ~= "" then
            lines[#lines + 1] = ambientLine
        end
    end
    if career and MTE and MTE.Management and MTE.Management.statusSummaryLine then
        local managementLine = MTE.Management.statusSummaryLine(career)
        if managementLine and managementLine ~= "" then
            lines[#lines + 1] = managementLine
        end
    end

    if rs ~= "idle" then
        local cfg = MTE.Racing and MTE.Racing.getConfig and MTE.Racing.getConfig() or {}
        lines[#lines + 1] = i18n.format("Race state: %s", rs)
        if cfg and (cfg.trackName or cfg.nodeA or cfg.nodeB) then
            local route = cfg.trackName
                or i18n.format("%s -> %s",
                    cfg.nodeA and cfg.nodeA.name or "?",
                    cfg.nodeB and cfg.nodeB.name or "?")
            lines[#lines + 1] = tostring(route)
        end
        if rs == "racing" then
            local pos = call(MTE.Racing, "getEstimatedPosition", 0) or 0
            local dist = call(MTE.Racing, "getDistanceToFinish", nil)
            lines[#lines + 1] = i18n.format("Live: P%d  %s remaining",
                tonumber(pos or 0),
                dist and fmtDistance(dist) or "?")
        end
    elseif ks ~= "idle" then
        lines[#lines + 1] = i18n.format("Knockout state: %s", ks)
        if MTE.Knockout and MTE.Knockout.getPlayerPosition then
            lines[#lines + 1] = i18n.format("Live: P%d, %d left",
                tonumber(MTE.Knockout.getPlayerPosition() or 0),
                tonumber(MTE.Knockout.getRemainingDrivers and MTE.Knockout.getRemainingDrivers() or 0))
        end
    else
        lines[#lines + 1] = "Race state: idle"
    end

    return i18n.concat(lines, "\n")
end

function Commands.standingsText()
    local career = activeCareer()
    if not career then
        return "No active career."
    end
    local season = MTE.Championships and MTE.Championships.activeSeason and MTE.Championships.activeSeason(career) or nil
    if not season then
        return i18n.format("%s has no active season.", tostring(career.name or "Career"))
    end
    local standings = MTE.Championships.driverStandings and MTE.Championships.driverStandings(season) or {}
    local lines = {
        i18n.format("Championship Rd %d/%d", tonumber(season.currentRound or 1), tonumber(season.totalRounds or 1)),
    }
    for i = 1, math.min(5, #standings) do
        local row = standings[i]
        lines[#lines + 1] = i18n.format("P%d %s  %d pts",
            i,
            tostring(row.driverName or row.driverId or "?"),
            tonumber(row.points or 0))
    end
    local pos, pts = playerChampPosition(career)
    if pos then
        lines[#lines + 1] = i18n.format("V: P%d, %d pts", pos, tonumber(pts or 0))
    end
    return i18n.concat(lines, "\n")
end

function Commands.statsText()
    local career = activeCareer()
    if not career then return "No active career." end
    local st = MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
    return i18n.format(
        "%s stats\nRaces: %d  Finished: %d  Wins: %d\nPodiums: %d  Rep: %d",
        tostring(career.name or "Career"),
        tonumber(st.racesRun or 0),
        tonumber(st.racesFinished or 0),
        tonumber(st.wins or 0),
        tonumber(st.podiums or 0),
        tonumber(career.rep or 0))
end

function Commands.earningsText()
    local active = activeCareer()
    if active and Betting and Betting.getBooksText then
        return Betting.getBooksText(active)
    end

    local careers = MTE and MTE.Careers and MTE.Careers.all or {}
    local totalEddies, totalCred, totalRaces = 0, 0, 0
    for _, career in pairs(careers) do
        local st = MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
        totalEddies = totalEddies + tonumber(st.eddiesEarned or 0)
        totalCred = totalCred + tonumber((career and career.stats and career.stats.credAwarded) or 0)
        totalRaces = totalRaces + tonumber(st.racesFinished or st.racesRun or 0)
    end

    if totalEddies <= 0 and totalCred <= 0 and totalRaces <= 0 then
        return "Book's clean. You haven't given me anything to write up yet."
    end
    return i18n.format(
        "Iâ€™ve got you down for this.\nEddies pulled: %d\nCred built: %d\nFinishes logged: %d",
        math.floor(totalEddies + 0.5),
        math.floor(totalCred + 0.5),
        math.floor(totalRaces + 0.5))
end

function Commands.controlBoardText(career)
    local rs = racingState()
    if rs ~= "idle" then
        return activeRaceBoardText(rs)
    end

    local ks = knockoutState()
    if ks ~= "idle" then
        return i18n.format("Control board\nKnockout status: %s\nConfirm it or scrub it.", ks)
    end

    local active = career or activeCareer()
    if not active then
        return "No career on the board. Set one first."
    end

    local lines = { "Control board" }
    local scheduled, eventSummary = currentEventSummary(active)
    if scheduled then
        lines[#lines + 1] = i18n.format("Heat on deck: %s", tostring(eventSummary or "Career heat ready"))
    else
        lines[#lines + 1] = tostring(eventSummary or "No career heat is up right now.")
    end
    if MTE and MTE.AmbientRaces and MTE.AmbientRaces.promotableStatusText then
        lines[#lines + 1] = tostring(MTE.AmbientRaces.promotableStatusText(active))
    end
    if MTE and MTE.Management and MTE.Management.pendingEntryText then
        local pending = MTE.Management.pendingEntryText(active)
        if pending and pending ~= "" then
            lines[#lines + 1] = pending
        elseif MTE.Management.statusSummaryLine then
            lines[#lines + 1] = tostring(MTE.Management.statusSummaryLine(active) or "")
        end
    end
    lines[#lines + 1] = "Stage the next heat, queue a management run, or pull a live ambient board."
    return i18n.concat(lines, "\n")
end

local function currentRaceConfig()
    return MTE and MTE.Racing and MTE.Racing.getConfig and MTE.Racing.getConfig() or {}
end

local function currentActiveEvent()
    return MTE and MTE.Racing and MTE.Racing._activeEvent or nil
end

function Commands.carStatusText()
    local career, vehicleKey, summaryOrErr, maybeErr = activeVehicleSummary()
    if maybeErr then return maybeErr end
    if type(summaryOrErr) ~= "table" then
        return tostring(summaryOrErr or "Canâ€™t get a proper read on it right now.")
    end

    local summary = summaryOrErr
    local profile = nativeVehicleProfile()
    local driveSnapshot = nativeDriveSnapshot()
    local assessment = buildStuAssessment(career, vehicleKey, summary, profile)
    local profileLine = nativeProfileLine(profile)
    local nativeLine = nativeDriveDeltaLine(driveSnapshot)
    local line1 = assessment.state
    local line2 = #assessment.highlights > 0
        and ("What's bolted on now: " .. listText(assessment.highlights, 2) .. ".")
        or "What's bolted on now: mostly stock hardware."
    if summary.buildIdentity and summary.buildIdentity.headline then
        line2 = line2 .. " Build identity: " .. tostring(summary.buildIdentity.headline) .. "."
    end
    local tradeoffLine = tradeoffText(summary)
    if tradeoffLine then
        line2 = line2 .. " " .. tradeoffLine
    end
    local metricsLine = effectMetricsText()
    if metricsLine then
        line2 = line2 .. " " .. metricsLine
    end
    if #assessment.missing > 0 then
        line2 = line2 .. " Still open: " .. listText(assessment.missing, 2) .. "."
    end
    local reward = summary.lastReward
    if type(reward) == "table" and reward.name then
        line2 = line2 .. " Last crate was " .. tostring(reward.name) .. "."
    end
    return line1
        .. "\n" .. line2
        .. (profileLine and ("\n" .. profileLine) or "")
        .. (nativeLine and ("\n" .. nativeLine) or "")
        .. "\n" .. tostring(assessment.problem or "Nothing urgent. It's workable as-is.")
end

function Commands.setupSuggestionText()
    local career, vehicleKey, summaryOrErr, maybeErr = activeVehicleSummary()
    if maybeErr then return maybeErr end
    if type(summaryOrErr) ~= "table" then
        return tostring(summaryOrErr or "Stu's not getting a clean read yet.")
    end

    local profile = nativeVehicleProfile()
    local driveSnapshot = nativeDriveSnapshot()
    local assessment = buildStuAssessment(career, vehicleKey, summaryOrErr, profile)
    local profileLine = nativeProfileLine(profile)
    local nativeLine = nativeDriveDeltaLine(driveSnapshot)
    return tostring(assessment.state or "Stu needs a minute with a clean pull first.")
        .. (summaryOrErr.buildIdentity and summaryOrErr.buildIdentity.headline and ("\nCurrent build identity: " .. tostring(summaryOrErr.buildIdentity.headline)) or "")
        .. (tradeoffText(summaryOrErr) and ("\n" .. tostring(tradeoffText(summaryOrErr))) or "")
        .. (profileLine and ("\n" .. profileLine) or "")
        .. (nativeLine and ("\n" .. nativeLine) or "")
        .. "\n" .. tostring(assessment.problem or "Nothing obvious is biting it.")
        .. "\n" .. tostring(assessment.suggestion or "I'd leave the build alone for now.")
end

function Commands.partsSourceText()
    local career, vehicleKey, summaryOrErr, maybeErr = activeVehicleSummary()
    if maybeErr then return maybeErr end
    if type(summaryOrErr) ~= "table" then
        return tostring(summaryOrErr or "Can't source clean hardware right now.")
    end

    local pick = pickStuUpgrade(career, vehicleKey, summaryOrErr)
    if not pick then
        return i18n.format("%s is already stacked. I don't have cleaner metal for it right now.", shortVehicleName(vehicleKey))
    end

    local ok, err
    local partName = tostring((pick.item and pick.item.name) or "fresh hardware")
    local slotName = slotLabel(pick.slotId)
    if pick.kind == "inventory" then
        ok, err = MTE.Parts.installPart(career, vehicleKey, pick.item.instanceId, pick.slotId, pick.targetIndex)
    else
        local instanceId
        instanceId, err = MTE.Parts.purchasePart(career, pick.item.id, vehicleKey, pick.slotId, pick.targetIndex)
        ok = instanceId ~= nil
    end
    if not ok then
        return err or "Couldn't get that part seated yet."
    end

    local updated = MTE.Parts.getVehicleSummary(career, vehicleKey) or summaryOrErr
    local updatedIdentity = updated and updated.buildIdentity and updated.buildIdentity.headline or "Balanced"
    local updatedTradeoff = tradeoffText(updated)
    return i18n.format(
        "All right, I %s %s in the %s slot on %s. It's reading %s now%s",
        pick.kind == "inventory" and "bolted on" or "sourced and bolted on",
        partName,
        slotName,
        shortVehicleName(vehicleKey),
        tostring(updatedIdentity),
        updatedTradeoff and (". " .. updatedTradeoff .. ".") or ".")
end

function Commands.tuningText()
    local tuning = MTE and MTE.Tuning or nil
    local vehicleKey = currentVehicleKey()
    if not tuning or not vehicleKey then
        return "Put me in the car you want tuned and I'll read it from the seat."
    end

    local career, _, summaryOrErr, maybeErr = activeVehicleSummary()
    if maybeErr then return maybeErr end
    if type(summaryOrErr) ~= "table" then
        return tostring(summaryOrErr or "Gonna need a clean read on the chassis before I write a map.")
    end

    local beforeBias = stuBiasLabel(tuning.scratch and tuningBiasText(tuning.scratch) or "balanced")
    local existingProfiles = tuning.profileNames and tuning.profileNames() or {}
    local label, profileName = applyStuTunePreset(summaryOrErr, tuning)
    local profiles = tuning.profileNames and tuning.profileNames() or {}
    local line1 = i18n.format("All right... I walked %s off a %s map and into a %s map.", shortVehicleName(vehicleKey), beforeBias, tostring(label))
    local line2 = i18n.format("Burned it live and filed it as %s.", tostring(profileName))
    local line3 = #profiles > 0 and ("Map rack now: " .. listText(profiles, 3) .. ".") or "No other shop maps are saved yet."
    if #existingProfiles > 0 then
        line3 = line3 .. " If you want an old map back, pull it from the tuning suite. The phone line only burns shop maps right now."
    end
    return line1 .. "\n" .. line2 .. "\n" .. line3
end

function Commands.playerStatsText()
    local career = activeCareer()
    if not career then
        return "I need a career before I start making posters!"
    end

    local st = MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
    local pos, pts = playerChampPosition(career)
    local headline = i18n.format(
        "%s %d wins, %d podiums, %d starts.",
        (tonumber(st.winStreak or 0) >= 2 and "You are unreal!") or "You're turning into a whole event!",
        tonumber(st.wins or 0),
        tonumber(st.podiums or 0),
        tonumber(st.racesRun or 0))
    local follow = i18n.format(
        "You've banked %s so far%s%s. Tell me the city isn't obsessed.",
        formatEddies(st.eddiesEarned or 0),
        pos and i18n.format(", sitting P%d on %d pts", pos, tonumber(pts or 0)) or "",
        tonumber(st.winStreak or 0) > 0 and i18n.format(", with a %d-race heater", tonumber(st.winStreak or 0)) or "")
    return headline .. "\n" .. follow
end

local function pickRandom(list)
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    return list[math.random(1, #list)]
end

local function addAll(out, list)
    if type(list) ~= "table" then return end
    for index = 1, #list do
        out[#out + 1] = list[index]
    end
end

local function weightedPool(...)
    local pool = {}
    local groups = { ... }
    for _, group in ipairs(groups) do
        local list = type(group) == "table" and group.list or {}
        local weight = math.max(0, tonumber(type(group) == "table" and group.weight or 0) or 0)
        if weight > 0 and type(list) == "table" and #list > 0 then
            for _ = 1, weight do
                addAll(pool, list)
            end
        end
    end
    return pool
end

function Commands.fanRerollText()
    local career = activeCareer()
    if not career then
        return "Pick a career and I'll build the shrine myself!"
    end

    if MTE and MTE.FanEngine and MTE.FanEngine.pullText then
        local ok, text = pcall(MTE.FanEngine.pullText, career)
        if ok and type(text) == "string" and text ~= "" then
            return text
        end
    end

    local st = MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
    local pos, pts = playerChampPosition(career)
    local wins = tonumber(st.wins or 0) or 0
    local podiums = tonumber(st.podiums or 0) or 0
    local racesRun = tonumber(st.racesRun or 0) or 0
    local racesFinished = tonumber(st.racesFinished or 0) or 0
    local streak = tonumber(st.winStreak or 0) or 0
    local eddies = tonumber(st.eddiesEarned or 0) or 0
    local lossStreak = tonumber(st.lossStreak or 0) or 0

    local earningsText = formatEddies(eddies)
    local posText = pos and ("P" .. tostring(pos)) or "that climb"

    local generalMessages = {
        "No lie, the fan file is getting thick. You keep handing me new material.",
        "I keep rerolling the hype and it keeps landing on the same thing: you're becoming a real problem out here.",
        "You know what I like? You don't feel accidental anymore.",
        "At this point I'm not even forcing the hype. The numbers keep doing it for me.",
        "You keep giving this city reasons to remember you.",
        "There are quieter ways to exist in Night City. You clearly aren't interested.",
        "You're building the kind of run people swear they saw coming after the fact.",
        "I don't know if you feel it yet, but this is starting to look real from out here.",
    }

    local streakMessages = {
        i18n.format("A %d-race heater? Come on. That's how people start sounding inevitable.", streak),
        i18n.format("%d straight. That's not a run anymore. That's pressure.", streak),
        i18n.format("%d in a row. That's the kind of stretch that gets in people's heads before the lights even go green.", streak),
        i18n.format("A %d-race streak will do that, yeah. The whole room tightens up when someone gets this hot.", streak),
        i18n.format("%d straight. At a certain point it stops looking lucky and starts looking like a warning.", streak),
        i18n.format("You know what %d straight does? It makes people drive your race instead of theirs.", streak),
    }

    local hugeStreakMessages = {
        i18n.format("%d straight? Be serious. That's bigger than a hot streak. That's a phase of your career now.", streak),
        i18n.format("%d in a row and people are still acting calm about it? Please.", streak),
        i18n.format("%d straight. That kind of heater changes how the whole city talks about you.", streak),
    }

    local standingsMessages = {
        i18n.format("%s in the standings? Yeah, they're watching you now.", posText),
        i18n.format("%s in the standings and suddenly everybody remembers your name right.", posText),
        i18n.format("%s on the ladder. That's not background noise anymore.", posText),
        i18n.format("%s. That's the kind of ranking people pretend not to care about while they absolutely care about it.", posText),
        pos and pts and i18n.format("%s on %d points. That's real weight on the board now.", posText, pts) or i18n.format("%s in the standings. That's real weight now.", posText),
    }

    local topStandingsMessages = {
        i18n.format("%s in the standings. Top-end pressure looks good on you.", posText),
        i18n.format("%s. That's where the city stops treating you like a maybe.", posText),
        pos and pts and i18n.format("%s on %d points? Yeah, that's contender behavior.", posText, pts) or i18n.format("%s? That's contender behavior.", posText),
        i18n.format("%s. You're not chasing the story anymore. You're in it.", posText),
    }

    local moneyMessages = {
        i18n.format("%s earned already. That's not side-hustle money anymore.", earningsText),
        i18n.format("You've stacked %s so far. That's the kind of money that gets remembered.", earningsText),
        i18n.format("%s banked. That's not subtle money.", earningsText),
        i18n.format("%s on the books already? Oh, you're really doing this.", earningsText),
        i18n.format("That %s didn't come from being forgettable.", earningsText),
    }

    local bigMoneyMessages = {
        i18n.format("%s? That's real pressure money now.", earningsText),
        i18n.format("You've pulled %s already. People have started careers with less than that.", earningsText),
        i18n.format("%s on your ledger and still climbing. That is not quiet work.", earningsText),
    }

    local podiumMessages = {
        i18n.format("%d podiums already. People are starting to say your name like they knew you first.", podiums),
        i18n.format("%d podiums and still climbing. You're not background noise anymore.", podiums),
        i18n.format("%d podiums in and the city still wants more. That's how you know it's working.", podiums),
        i18n.format("%d podiums. That's enough for people to start taking sides.", podiums),
        i18n.format("%d podiums already? Yeah, no, this is becoming a thing.", podiums),
    }

    local bigPodiumMessages = {
        i18n.format("%d podiums. At that point it's not momentum, it's identity.", podiums),
        i18n.format("%d podiums on record. That's how a name gets heavier.", podiums),
        i18n.format("%d podiums and people still want to act surprised? Please.", podiums),
    }

    local winMessages = {
        i18n.format("%d wins on the board already. That stops being luck real fast.", wins),
        i18n.format("%d wins. That's the kind of number people argue with until they can't.", wins),
        i18n.format("%d wins and it still feels like you haven't peaked yet. That's the scary part.", wins),
        i18n.format("%d wins. You know how bitter that makes the rest of the ladder?", wins),
        i18n.format("%d wins already. That's real authority.", wins),
    }

    local bigWinMessages = {
        i18n.format("%d wins. That's the kind of total people build whole reputations around.", wins),
        i18n.format("%d wins on record. Nobody accidentally gets there.", wins),
        i18n.format("%d wins. At that point even the haters have to get creative.", wins),
    }

    local startMessages = {
        i18n.format("%d starts in and you've already got people paying attention. That's how this starts.", racesRun),
        i18n.format("%d starts, %d wins, %d podiums. You know how stupid that looks to everyone chasing you?", racesRun, wins, podiums),
        i18n.format("%d starts in and you're already making this feel bigger than a side lane.", racesRun),
        i18n.format("%d starts is enough for a pattern. You are definitely a pattern now.", racesRun),
    }

    local finishMessages = {
        i18n.format("%d finishes in and the city still wants more of you. That's a sign.", racesFinished),
        i18n.format("%d finishes on file and you still don't feel settled. That's dangerous in a good way.", racesFinished),
        i18n.format("%d finishes. You keep showing up, and that matters more than people admit.", racesFinished),
    }

    local coldMessages = {
        i18n.format("Yeah, %d rough one%s in a row stings. Doesn't erase what you've already built.", lossStreak, lossStreak == 1 and "" or "s"),
        "Everybody hits a flat patch. The city only remembers if you stay there.",
        "I'm still here. Get one clean result and the whole mood changes.",
    }

    local zeroWinMessages = {
        i18n.format("%d starts in and no win yet? Fine. That only makes the first one hit harder.", racesRun),
        "You haven't broken through yet. Good. That means the payoff's still coming.",
        "No win on paper yet. Doesn't mean nobody sees what you're building.",
    }

    local zeroPodiumMessages = {
        "No podium yet, sure. But it already feels like you're circling something.",
        "Not on the box yet. Doesn't matter. The shape of it is there.",
    }

    local pool = {}

    if streak >= 4 then
        pool = weightedPool(
            { list = hugeStreakMessages, weight = 5 },
            { list = streakMessages, weight = 4 },
            { list = standingsMessages, weight = 2 },
            { list = generalMessages, weight = 1 }
        )
    elseif streak >= 2 then
        pool = weightedPool(
            { list = streakMessages, weight = 5 },
            { list = winMessages, weight = 3 },
            { list = standingsMessages, weight = 2 },
            { list = generalMessages, weight = 1 }
        )
    elseif pos and pos <= 3 then
        pool = weightedPool(
            { list = topStandingsMessages, weight = 5 },
            { list = standingsMessages, weight = 3 },
            { list = podiumMessages, weight = 2 },
            { list = generalMessages, weight = 1 }
        )
    elseif wins >= 8 then
        pool = weightedPool(
            { list = bigWinMessages, weight = 5 },
            { list = winMessages, weight = 3 },
            { list = podiumMessages, weight = 2 },
            { list = generalMessages, weight = 1 }
        )
    elseif podiums >= 10 then
        pool = weightedPool(
            { list = bigPodiumMessages, weight = 5 },
            { list = podiumMessages, weight = 3 },
            { list = standingsMessages, weight = 2 },
            { list = generalMessages, weight = 1 }
        )
    elseif eddies >= 50000 then
        pool = weightedPool(
            { list = bigMoneyMessages, weight = 5 },
            { list = moneyMessages, weight = 3 },
            { list = generalMessages, weight = 2 }
        )
    elseif wins > 0 then
        pool = weightedPool(
            { list = winMessages, weight = 4 },
            { list = podiumMessages, weight = 3 },
            { list = standingsMessages, weight = 2 },
            { list = moneyMessages, weight = 1 },
            { list = generalMessages, weight = 1 }
        )
    elseif podiums > 0 then
        pool = weightedPool(
            { list = podiumMessages, weight = 4 },
            { list = standingsMessages, weight = 2 },
            { list = moneyMessages, weight = 1 },
            { list = generalMessages, weight = 2 }
        )
    elseif lossStreak >= 2 then
        pool = weightedPool(
            { list = coldMessages, weight = 5 },
            { list = startMessages, weight = 2 },
            { list = generalMessages, weight = 2 }
        )
    elseif racesRun >= 10 then
        pool = weightedPool(
            { list = startMessages, weight = 4 },
            { list = finishMessages, weight = 3 },
            { list = zeroWinMessages, weight = wins == 0 and 2 or 0 },
            { list = zeroPodiumMessages, weight = podiums == 0 and 2 or 0 },
            { list = generalMessages, weight = 2 }
        )
    else
        pool = weightedPool(
            { list = zeroWinMessages, weight = wins == 0 and 3 or 0 },
            { list = zeroPodiumMessages, weight = podiums == 0 and 2 or 0 },
            { list = startMessages, weight = 2 },
            { list = generalMessages, weight = 4 }
        )
    end

    if #pool == 0 then
        pool = generalMessages
    end

    return tostring(pickRandom(pool) or "I don't know how else to say it - you've got something going.")
end

local function firstName(name)
    local text = tostring(name or "")
    local found = text:match("^%s*([^%s]+)")
    if found and found ~= "" then
        return found
    end
    return text ~= "" and text or "Rico"
end

local function averageRecentFinish(driver)
    local finishes = driver and driver.recentFinishes or nil
    if type(finishes) ~= "table" or #finishes == 0 then
        return nil
    end

    local total = 0
    local count = 0
    for _, pos in ipairs(finishes) do
        local value = tonumber(pos)
        if value then
            total = total + value
            count = count + 1
        end
    end

    if count <= 0 then
        return nil
    end
    return total / count
end

local function driverThreatScore(driver)
    local pace = tonumber(driver and driver.pace or 0) or 0
    local consistency = tonumber(driver and driver.consistency or 0) or 0
    local aggression = tonumber(driver and driver.aggression or 0) or 0
    local wins = tonumber(driver and driver.wins or 0) or 0
    local rivalScore = tonumber(driver and driver.rivalScore or 0) or 0
    local headToHeadWins = tonumber(driver and driver.headToHeadWins or 0) or 0
    local form = averageRecentFinish(driver)
    local formScore = form and math.max(-12, 34 - ((form - 1) * 7)) or 0

    return pace * 100
        + consistency * 34
        + aggression * 12
        + wins * 4
        + rivalScore * 0.45
        + headToHeadWins * 8
        + formScore
end

local function driverReason(driver)
    local pace = tonumber(driver and driver.pace or 0) or 0
    local consistency = tonumber(driver and driver.consistency or 0) or 0
    local aggression = tonumber(driver and driver.aggression or 0) or 0
    local wins = tonumber(driver and driver.wins or 0) or 0
    local rivalScore = tonumber(driver and driver.rivalScore or 0) or 0
    local headToHeadWins = tonumber(driver and driver.headToHeadWins or 0) or 0
    local form = averageRecentFinish(driver)
    local personality = tostring(driver and driver.personality or "")

    if headToHeadWins >= 2 then
        return i18n.format("already has %d clean beats on you and knows exactly how to turn this into a personal race", headToHeadWins)
    end

    if pace >= 1.12 and consistency >= 0.72 then
        return "has the cleanest outright pace in this field and usually does not waste it with mistakes"
    end

    if aggression >= 0.78 and consistency <= 0.48 then
        return "forces the issue early, then starts leaking time the second the race gets untidy"
    end

    if aggression >= 0.78 then
        return "will throw the first punch on the launch and make every overlap feel expensive"
    end

    if form and form <= 2.5 then
        return "is coming in hot off front-running form and will expect this race to bend toward them"
    end

    if wins >= 3 then
        return i18n.format("already has %d wins banked and usually knows how to close once they smell the front", wins)
    end

    if rivalScore >= 12 then
        return "keeps turning up as your direct problem in this tier, which is not something I ignore anymore"
    end

    if personality == "crash magnet" then
        return "has real speed, but the line gets risky the moment the race stops behaving"
    end

    if personality == "clean runner" or consistency >= 0.75 then
        return "won't donate free mistakes once they get clean air, so you need to take the race away from them yourself"
    end

    if personality == "slow starter" then
        return "usually gives away the first phase, then gets stronger once the field stretches and the noise drops out"
    end

    if consistency <= 0.40 then
        return "has enough pace to matter, but pressure usually opens the cracks sooner or later"
    end

    return "is steady enough to stay in the conversation if you let them settle into their own rhythm"
end

local function fieldStateLabel(state)
    if state == "prerace" then return "staged grid" end
    if state == "quali" then return "qualifying board" end
    if state == "countdown" or state == "racing" then return "live run" end
    if state == "results" then return "posted result" end
    return "field"
end

local function activeFieldEntries()
    local racing = MTE and MTE.Racing or nil
    local field = racing and racing._field or nil
    if type(field) ~= "table" then
        return {}
    end

    local entries = {}
    for _, entry in ipairs(field) do
        if type(entry) == "table" and entry.isPlayer ~= true then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

local function sortedFieldEntries(field)
    local entries = {}
    for _, entry in ipairs(field or activeFieldEntries()) do
        if type(entry) == "table" and entry.isPlayer ~= true then
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, function(left, right)
        return driverThreatScore(left) > driverThreatScore(right)
    end)
    return entries
end

local function currentFieldFocus(limit)
    local entries = sortedFieldEntries()
    local focus = {}
    for index = 1, math.min(tonumber(limit) or 3, #entries) do
        focus[#focus + 1] = entries[index]
    end
    return entries, focus
end

local function averageFieldValue(entries, key, maxCount)
    local total = 0
    local count = 0
    for index = 1, math.min(tonumber(maxCount) or #entries, #entries) do
        total = total + (tonumber(entries[index] and entries[index][key] or 0) or 0)
        count = count + 1
    end
    if count <= 0 then
        return 0
    end
    return total / count
end

local function listWithRemainder(items, totalCount)
    if type(items) ~= "table" or #items == 0 then
        return "nobody you know yet"
    end
    local label = listText(items, #items)
    local total = tonumber(totalCount) or #items
    if total > #items then
        label = i18n.format("%s, and %d more", label, total - #items)
    end
    return label
end

local function fieldTone(entries)
    if type(entries) ~= "table" or #entries == 0 then
        return "unreadable"
    end
    local topThreat = averageFieldValue(entries, "pace", math.min(3, #entries))
    local aggression = averageFieldValue(entries, "aggression", math.min(4, #entries))
    local consistency = averageFieldValue(entries, "consistency", math.min(4, #entries))

    if topThreat >= 88 and consistency >= 0.68 then
        return "sharp"
    end
    if aggression >= 0.70 then
        return "volatile"
    end
    if consistency >= 0.72 then
        return "clean"
    end
    return "mixed"
end

local function topLeaderboardEntries(career, count)
    local active = career or activeCareer()
    local roster = MTE and MTE.Roster or nil
    local leaders = roster and roster.getLeaderboard and roster.getLeaderboard(active, active and active.tier, count or 5) or {}
    if type(leaders) ~= "table" then
        return {}
    end
    return leaders
end

local function consecutiveRecentWins(driver)
    local streak = 0
    local recent = type(driver and driver.recentFinishes) == "table" and driver.recentFinishes or {}
    for _, finish in ipairs(recent) do
        if tonumber(finish) == 1 then
            streak = streak + 1
        else
            break
        end
    end
    return streak
end

local function buildCurrentFieldScoutBrief(career)
    local state = racingState()
    if state == "idle" or state == "config" then
        return nil
    end

    local entries, focus = currentFieldFocus(3)
    if #entries == 0 or #focus == 0 then
        return nil
    end

    local focusNames = {}
    for _, driver in ipairs(focus) do
        focusNames[#focusNames + 1] = firstName(driver.displayName or driver.name or driver.id)
    end

    local leader = focus[1]
    local aggressor = nil
    local rival = nil
    for _, driver in ipairs(focus) do
        if not aggressor or (tonumber(driver.aggression or 0) or 0) > (tonumber(aggressor.aggression or 0) or 0) then
            aggressor = driver
        end
        if (tonumber(driver.headToHeadWins or 0) or 0) > 0 or (tonumber(driver.rivalScore or 0) or 0) >= 10 then
            rival = driver
        end
    end

    local topBand = 0
    for _, driver in ipairs(focus) do
        topBand = topBand + driverThreatScore(driver)
    end
    topBand = topBand / math.max(1, #focus)

    local lines = {
        i18n.format("This %s goes through %s.", fieldStateLabel(state), listText(focusNames, 3)),
        i18n.format("%s is the pace reference here. %s.", firstName(leader.displayName or leader.name or leader.id), driverReason(leader)),
    }

    if aggressor and aggressor ~= leader then
        lines[#lines + 1] = i18n.format("%s is the one who can turn the first phase ugly. %s.", firstName(aggressor.displayName or aggressor.name or aggressor.id), driverReason(aggressor))
    end

    if rival and rival ~= leader and rival ~= aggressor then
        lines[#lines + 1] = i18n.format("%s is tied closest to your lane in this one. %s.", firstName(rival.displayName or rival.name or rival.id), driverReason(rival))
    elseif focus[2] and focus[2] ~= aggressor then
        lines[#lines + 1] = i18n.format("%s is the other live name on this board. %s.", firstName(focus[2].displayName or focus[2].name or focus[2].id), driverReason(focus[2]))
    end

    if topBand >= 165 then
        lines[#lines + 1] = i18n.format("Read: sharp top end. If %s gets clean air, you're chasing their pace instead of shaping your own race.", firstName(leader.displayName or leader.name or leader.id))
    elseif aggressor then
        lines[#lines + 1] = i18n.format("Read: the launch is where this can go wrong. Keep %s from turning the first phase into noise, then the race should open up.", firstName(aggressor.displayName or aggressor.name or aggressor.id))
    else
        lines[#lines + 1] = "Read: beatable field, but the front pair won't hand you anything clean for free."
    end

    return i18n.concat(lines, "\n")
end

local function buildFieldRosterScoutBrief(career)
    local state = racingState()
    if state == "idle" or state == "config" then
        return nil
    end

    local entries, focus = currentFieldFocus(4)
    if #entries == 0 or #focus == 0 then
        return nil
    end

    local names = {}
    for _, driver in ipairs(focus) do
        names[#names + 1] = firstName(driver.displayName or driver.name or driver.id)
    end

    local leader = focus[1]
    local second = focus[2]
    local tone = fieldTone(entries)
    local lines = {
        i18n.format("On this %s, you're lined up with %s.", fieldStateLabel(state), listWithRemainder(names, #entries)),
        i18n.format("%s is the pace anchor here. %s.", firstName(leader.displayName or leader.name or leader.id), driverReason(leader)),
    }

    if second then
        lines[#lines + 1] = i18n.format("%s is the other name you do not get to ignore. %s.", firstName(second.displayName or second.name or second.id), driverReason(second))
    end

    if tone == "volatile" and focus[3] then
        lines[#lines + 1] = i18n.format("%s gives the field its bad habit. Enough aggression there to make the launch messy if nobody keeps shape.", firstName(focus[3].displayName or focus[3].name or focus[3].id))
    elseif tone == "sharp" then
        lines[#lines + 1] = "This is not filler traffic. The front of this grid has real pace, and it will punish any lazy first phase."
    elseif tone == "clean" then
        lines[#lines + 1] = "This field is cleaner than it is wild. You will need to take places on pace, not wait for them to shake loose."
    else
        lines[#lines + 1] = "The shape is mixed. The front can run, but the rest of the pack can still twist the race if you let it bunch up."
    end

    return i18n.concat(lines, "\n")
end

local function buildFieldReadScoutBrief(career)
    local state = racingState()
    if state == "idle" or state == "config" then
        return nil
    end

    local entries, focus = currentFieldFocus(3)
    if #entries == 0 or #focus == 0 then
        return nil
    end

    local leader = focus[1]
    local aggression = averageFieldValue(entries, "aggression", math.min(4, #entries))
    local consistency = averageFieldValue(entries, "consistency", math.min(4, #entries))

    local threatBand = 0
    for _, driver in ipairs(focus) do
        threatBand = threatBand + driverThreatScore(driver)
    end
    threatBand = threatBand / math.max(1, #focus)

    local lines = {
        i18n.format("This %s looks %s.", fieldStateLabel(state), fieldTone(entries)),
        i18n.format("%s sets the reference here because %s.", firstName(leader.displayName or leader.name or leader.id), driverReason(leader)),
    }

    if threatBand >= 165 then
        lines[#lines + 1] = "Top end is heavy enough that clean air matters more than survival mode. If the front gets organized, the race starts closing on you fast."
    elseif aggression >= 0.70 then
        lines[#lines + 1] = "The danger here is not just pace. It is how quickly this field can turn one bad launch into traffic and bodywork."
    elseif consistency >= 0.72 then
        lines[#lines + 1] = "This is a patient field. Miss the first clean chance to pass, and they will keep the order neat enough to make you earn the next one properly."
    else
        lines[#lines + 1] = "Beatable field, but it will not sort itself for you. You still have to go take the race."
    end

    if focus[2] then
        lines[#lines + 1] = i18n.format("Read: clear %s early or you spend the whole run reacting instead of dictating.", firstName(focus[2].displayName or focus[2].name or focus[2].id))
    else
        lines[#lines + 1] = i18n.format("Read: if %s gets clean air, you stop racing the field and start racing their shape.", firstName(leader.displayName or leader.name or leader.id))
    end

    return i18n.concat(lines, "\n")
end

local function buildWatchlistScoutBrief(career)
    local state = racingState()
    if state == "idle" or state == "config" then
        return nil
    end

    local entries, focus = currentFieldFocus(3)
    if #entries == 0 or #focus == 0 then
        return nil
    end

    local leader = focus[1]
    local chaos = focus[1]
    local rival = nil

    for _, driver in ipairs(focus) do
        if (tonumber(driver.aggression or 0) or 0) > (tonumber(chaos.aggression or 0) or 0) then
            chaos = driver
        end
        if not rival and ((tonumber(driver.rivalScore or 0) or 0) >= 10 or (tonumber(driver.headToHeadWins or 0) or 0) > 0) then
            rival = driver
        end
    end

    local leaderName = firstName(leader.displayName or leader.name or leader.id)
    local chaosName = firstName((chaos or leader).displayName or (chaos or leader).name or (chaos or leader).id)

    local lines = {
        i18n.format("%s is your reference. %s.", leaderName, driverReason(leader)),
    }

    if chaos and chaos ~= leader then
        lines[#lines + 1] = i18n.format("%s is the unstable piece. %s.", chaosName, driverReason(chaos))
    end

    if rival and rival ~= leader and rival ~= chaos then
        lines[#lines + 1] = i18n.format("%s is tied to you whether you like it or not. %s.", firstName(rival.displayName or rival.name or rival.id), driverReason(rival))
    elseif focus[2] and focus[2] ~= leader and focus[2] ~= chaos then
        lines[#lines + 1] = i18n.format("%s is the other name that will show up if you hesitate. %s.", firstName(focus[2].displayName or focus[2].name or focus[2].id), driverReason(focus[2]))
    end

    if state == "prerace" or state == "quali" then
        lines[#lines + 1] = i18n.format("Read: if %s gets clean off the line, you are immediately on the back foot. And if %s turns the launch messy, you're dealing with damage before the race even settles.", leaderName, chaosName)
    else
        lines[#lines + 1] = i18n.format("Read: %s is shaping the pace, but %s is the one that can break the order if this run gets impatient.", leaderName, chaosName)
    end

    return i18n.concat(lines, "\n")
end

local function buildLastOutcomeScoutBrief(career)
    local history = career and career.raceHistory or nil
    local lastRace = type(history) == "table" and history[1] or nil
    if type(lastRace) ~= "table" then
        return nil
    end

    local district = tostring(lastRace.district or lastRace.trackName or lastRace.routeName or "the last run")
    if lastRace.dnf then
        if lastRace.clean == false then
            return i18n.format("At %s, the run died in the noise before the flag. That was chaos, not a pace problem.", district)
        end
        return i18n.format("At %s, it ended in a DNF. The race never settled long enough to pay back what pace you had.", district)
    end

    local position = tonumber(lastRace.position)
    if not position then
        return nil
    end
    local startPos = tonumber(lastRace.startPos)

    if startPos and position < startPos then
        local gained = startPos - position
        if lastRace.clean == true then
            return i18n.format("At %s, you came from P%d to P%d and took back %d spot%s on clean race pace.", district, startPos, position, gained, gained == 1 and "" or "s")
        end
        return i18n.format("At %s, you still dragged it from P%d to P%d through a messy run. Recovery pace held up.", district, startPos, position, gained)
    end
    if startPos and position > startPos then
        local lost = position - startPos
        if lastRace.clean == false then
            return i18n.format("At %s, you slipped from P%d to P%d once the race got dirty. That cost you %d place%s.", district, startPos, position, lost, lost == 1 and "" or "s")
        end
        return i18n.format("At %s, you faded from P%d to P%d. Read: the pace bled off deeper into the run.", district, startPos, position)
    end

    if lastRace.clean == true then
        return i18n.format("At %s, you held P%d because the run stayed clean enough not to leak anything for free.", district, position)
    end
    return i18n.format("At %s, you came home P%d, but the race got loose enough to cap what was really available.", district, position)
end

local function buildWorldScoutBrief(career)
    local leaders = topLeaderboardEntries(career, 5)
    if type(leaders) ~= "table" or #leaders == 0 then
        return "I don't have a clean ladder read yet. Give it a few more results."
    end

    local leader = leaders[1]
    local mover = leader
    local rival = nil
    local bestForm = averageRecentFinish(leader) or 99

    for _, driver in ipairs(leaders) do
        local form = averageRecentFinish(driver) or 99
        if form < bestForm then
            mover = driver
            bestForm = form
        end
        if not rival and ((tonumber(driver.headToHeadWins or 0) or 0) > 0 or (tonumber(driver.rivalScore or 0) or 0) >= 10) then
            rival = driver
        end
    end

    local lines = {}
    local outcome = buildLastOutcomeScoutBrief(career)
    if outcome then
        lines[#lines + 1] = outcome
    end

    lines[#lines + 1] = i18n.format(
        "Right now %s belongs to %s. %d win%s, %d rep, and the cleanest claim on the tier so far.",
        tostring(career.tier or "the scene"),
        firstName(leader.name or leader.id),
        tonumber(leader.wins or 0),
        tonumber(leader.wins or 0) == 1 and "" or "s",
        tonumber(leader.rep or 0))

    if mover and mover ~= leader then
        lines[#lines + 1] = i18n.format("%s is the mover in the file right now. %s.", firstName(mover.name or mover.id), driverReason(mover))
    end

    if rival and rival ~= leader and rival ~= mover then
        lines[#lines + 1] = i18n.format("%s is the name that keeps leaning into your lane. %s.", firstName(rival.name or rival.id), driverReason(rival))
    end

    local stats = MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
    if tonumber(stats.winStreak or 0) >= 2 then
        lines[#lines + 1] = "Read: the ladder knows you're hot. The next clean result carries more weight now than a routine mid-pack finish ever would."
    elseif tonumber(stats.lossStreak or 0) >= 2 then
        lines[#lines + 1] = "Read: the room is impatient. A clean rebound matters more right now than trying to force something theatrical."
    else
        lines[#lines + 1] = i18n.format("Read: %s has the cleanest hold on the tier right now, but the order behind them is still soft enough to move if you hit it clean.", firstName(leader.name or leader.id))
    end

    return i18n.concat(lines, "\n")
end

local function findFieldDriverById(driverId)
    if type(driverId) ~= "string" or driverId == "" then
        return nil
    end
    for _, entry in ipairs(activeFieldEntries()) do
        if tostring(entry.driverId or entry.id or "") == driverId then
            return entry
        end
    end
    return nil
end

function Commands.scoutPreviewPushText(career, data)
    local active = career or activeCareer()
    local field = data and data.field or nil
    if not active or type(field) ~= "table" or #field <= 0 then
        return nil
    end

    local entries = {}
    for _, entry in ipairs(field) do
        if type(entry) == "table" and entry.isPlayer ~= true then
            entries[#entries + 1] = entry
        end
    end
    if #entries < 2 then
        return nil
    end

    table.sort(entries, function(left, right)
        return driverThreatScore(left) > driverThreatScore(right)
    end)

    local lead = entries[1]
    local second = entries[2]
    local hasRivalSignal = (tonumber(lead.rivalScore or 0) or 0) >= 10
        or (tonumber(lead.headToHeadWins or 0) or 0) > 0
        or (tonumber(second.rivalScore or 0) or 0) >= 10
        or (tonumber(second.headToHeadWins or 0) or 0) > 0
    local sharpField = driverThreatScore(lead) >= 150 or driverThreatScore(second) >= 138

    if not hasRivalSignal and not sharpField then
        return nil
    end

    return i18n.format(
        "%s and %s are the live names here. %s. If %s gets clean air, the race closes on you fast.",
        firstName(lead.displayName or lead.name or lead.id),
        firstName(second.displayName or second.name or second.id),
        i18n.format("%s %s", firstName(lead.displayName or lead.name or lead.id), driverReason(lead)),
        firstName(lead.displayName or lead.name or lead.id))
end

function Commands.scoutTrendPushText(career, previousTopIds)
    local active = career or activeCareer()
    if not active then
        return nil, nil
    end

    local leaders = topLeaderboardEntries(active, 5)
    if #leaders == 0 then
        return nil, nil
    end

    local previous = {}
    for _, driverId in ipairs(previousTopIds or {}) do
        previous[tostring(driverId)] = true
    end

    for _, driver in ipairs(leaders) do
        local streak = consecutiveRecentWins(driver)
        if streak >= 3 then
            local driverId = tostring(driver.id or driver.driverId or driver.name or "")
            return i18n.format(
                "%s just made it %d straight in %s. %s. The top of the tier is starting to lock around that form.",
                firstName(driver.name or driver.id),
                streak,
                tostring(active.tier or "this tier"),
                driverReason(driver)
            ), i18n.format("streak:%s:%d", driverId, streak)
        end
    end

    for index = 1, math.min(3, #leaders) do
        local driver = leaders[index]
        local driverId = tostring(driver.id or driver.driverId or driver.name or "")
        local hotForm = (averageRecentFinish(driver) or 99) <= 3.0
        local rivalSignal = (tonumber(driver.rivalScore or 0) or 0) >= 10 or (tonumber(driver.headToHeadWins or 0) or 0) > 0
        if driverId ~= "" and not previous[driverId] and (hotForm or rivalSignal) then
            return i18n.format(
                "%s just forced their way into the front of %s. %s. Treat them like a live mover now.",
                firstName(driver.name or driver.id),
                tostring(active.tier or "this tier"),
                driverReason(driver)
            ), i18n.format("riser:%s:%d", driverId, index)
        end
    end

    return nil, nil
end

function Commands.scoutTierChangePushText(career, data)
    local active = career or activeCareer()
    if not active then
        return nil
    end

    local leaders = topLeaderboardEntries(active, 3)
    if #leaders == 0 then
        return nil
    end

    local lead = leaders[1]
    local second = leaders[2]
    local dir = data and tostring(data.dir or "") or ""
    local opener = dir == "up"
        and "New tier. Pressure changes immediately."
        or "The ladder just tightened around you."
    local lines = {
        i18n.format("%s %s sets the pace in %s.", opener, firstName(lead.name or lead.id), tostring(active.tier or "this tier")),
    }

    if second then
        lines[#lines + 1] = i18n.format("%s is right there too. This tier is not a one-name problem.", firstName(second.name or second.id))
    end

    lines[#lines + 1] = i18n.format("%s.", driverReason(lead))
    return i18n.concat(lines, "\n")
end

function Commands.scoutLeaderboardTopIds(career, count)
    local leaders = topLeaderboardEntries(career or activeCareer(), count or 3)
    local ids = {}
    for index = 1, math.min(count or 3, #leaders) do
        ids[#ids + 1] = tostring(leaders[index].id or leaders[index].driverId or leaders[index].name or "")
    end
    return ids
end

function Commands.scoutResultPushText(career, data)
    local active = career or activeCareer()
    if not active or type(data) ~= "table" then
        return nil
    end

    local results = type(data.results) == "table" and data.results or {}
    local topNonPlayer = nil
    for _, result in ipairs(results) do
        if not result.isPlayer then
            topNonPlayer = result
            break
        end
    end

    if data.isDNF then
        if data.isClean == false then
            if topNonPlayer then
                local driver = findFieldDriverById(topNonPlayer.driverId)
                local cause = driver and driverReason(driver) or "kept the run cleaner when it broke up"
                return i18n.format("%s took it because %s. Your run died in the noise before the flag.", firstName(topNonPlayer.name or topNonPlayer.driverId), cause)
            end
            return "That one fell apart in the noise before it ever settled. Chaos beat pace there."
        end
        return "That DNF reads like a run that never stabilized. Next clean finish matters more than anything flashy."
    end

    local position = tonumber(data.position)
    if not position then
        return nil
    end

    if position == 1 then
        if topNonPlayer then
            local gapName = firstName(topNonPlayer.name or topNonPlayer.driverId)
            if data.isClean == true then
                return i18n.format("You took this one because the race stayed clean enough to let your pace decide it. %s never got the mess they needed.", gapName)
            end
            return i18n.format("You still took it through the noise. That is control over %s and the rest of the field.", gapName)
        end
        return "You won because the run stayed in your hands. Control, not luck."
    end

    if topNonPlayer then
        local driver = findFieldDriverById(topNonPlayer.driverId)
        local favorite = sortedFieldEntries()[1]
        local cause = driver and driverReason(driver) or "kept the cleaner race together"
        local streak = driver and consecutiveRecentWins(driver) or 0
        local favoriteId = favorite and tostring(favorite.driverId or favorite.id or "") or ""
        if driver and favorite and favoriteId ~= tostring(topNonPlayer.driverId or "") and (driverThreatScore(favorite) - driverThreatScore(driver)) >= 12 then
            return i18n.format(
                "%s just flipped the expected order over %s. %s. The tier just got less predictable.",
                firstName(topNonPlayer.name or topNonPlayer.driverId),
                firstName(favorite.displayName or favorite.name or favorite.id),
                cause)
        end
        if streak >= 3 then
            return i18n.format(
                "%s just made it %d straight. %s. You are chasing form now, not one result.",
                firstName(topNonPlayer.name or topNonPlayer.driverId),
                streak,
                cause)
        end
        if data.isClean == true then
            return i18n.format("%s got you here because %s. That was race shape, not randomness.", firstName(topNonPlayer.name or topNonPlayer.driverId), cause)
        end
        return i18n.format("%s got the better of this one because %s, then the race broke up and locked the order in.", firstName(topNonPlayer.name or topNonPlayer.driverId), cause)
    end

    return nil
end

function Commands.scoutStatusText()
    local career = activeCareer()
    if not career then
        return "No file yet. Get a career running and I'll start building names for you."
    end

    local brief = buildWorldScoutBrief(career)
    local heatRead = MTE and MTE.AmbientRaces and MTE.AmbientRaces.ricoDistrictHeatText and MTE.AmbientRaces.ricoDistrictHeatText(career) or nil
    local intelRead = contactIntelText(career)
    if heatRead and heatRead ~= "" then
        brief = brief .. " " .. heatRead
    end
    if intelRead and intelRead ~= "" then
        brief = brief .. " " .. intelRead
    end
    return brief
end

function Commands.scoutCurrentGridText()
    local career = activeCareer()
    if not career then
        return "No file yet. Get a career running first."
    end

    local fieldBrief = buildFieldRosterScoutBrief(career)
    if fieldBrief and fieldBrief ~= "" then
        return fieldBrief
    end

    return "No grid staged. Put a heat on the board and I'll tell you who matters."
end

function Commands.scoutFieldReadText()
    local career = activeCareer()
    if not career then
        return "No file yet. Get a career running first."
    end

    local fieldBrief = buildFieldReadScoutBrief(career)
    if fieldBrief and fieldBrief ~= "" then
        local intelRead = contactIntelText(career)
        if intelRead and intelRead ~= "" then
            return fieldBrief .. "\n" .. intelRead
        end
        return fieldBrief
    end

    return "No live read yet. Stage a heat and I'll tell you what this field actually looks like."
end

function Commands.scoutWatchlistText()
    local career = activeCareer()
    if not career then
        return "No file yet. Get a career running first."
    end

    local fieldBrief = buildWatchlistScoutBrief(career)
    if fieldBrief and fieldBrief ~= "" then
        return fieldBrief
    end

    local currentBrief = buildCurrentFieldScoutBrief(career)
    if currentBrief and currentBrief ~= "" then
        return currentBrief
    end

    return "No watchlist yet. Stage a grid and I'll give you the names that matter."
end

function Commands.scoutAmbientHeatText()
    local career = activeCareer()
    if not career then
        return "No file yet. Get a career running first."
    end
    local heatRead = MTE and MTE.AmbientRaces and MTE.AmbientRaces.ricoDistrictHeatText and MTE.AmbientRaces.ricoDistrictHeatText(career) or nil
    return heatRead or "The city is quiet right now. Nothing is stacking hard enough to call hot."
end

function Commands.scoutManagementTargetsText()
    local career = activeCareer()
    if not career then
        return "No file yet. Get a career running first."
    end
    if not (MTE and MTE.Management and MTE.Management.candidateText) then
        return "Rico's board is dark right now."
    end
    return MTE.Management.candidateText(career, 3)
end

function Commands.signManagementCandidate(career, index)
    local active = career or activeCareer()
    if not active then
        return false, "Create or select a career first."
    end
    if not (MTE and MTE.Management and MTE.Management.signCandidate) then
        return false, "I can't file that signing right now."
    end
    local ok, message = MTE.Management.signCandidate(active, index)
    if ok == true then
        return true, message
    end
    if message == "slot_occupied" then
        return false, "Management slot 1 is already full."
    end
    if message == "driver_not_found" then
        return false, "I lost that target. Pull a fresh board first."
    end
    return false, message or "I could not lock that driver in."
end

function Commands.controlAmbientStatusText(career)
    local active = career or activeCareer()
    if not active then
        return "Create or select a career first."
    end
    local ambient = MTE and MTE.AmbientRaces and MTE.AmbientRaces.promotableStatusText and MTE.AmbientRaces.promotableStatusText(active) or "Ambient board unavailable."
    local management = MTE and MTE.Management and MTE.Management.statusText and MTE.Management.statusText(active) or nil
    if management and management ~= "" then
        return ambient .. "\n" .. management
    end
    return ambient
end

function Commands.queueManagedEntry(career, mode)
    local active = career or activeCareer()
    if not active then
        return false, "Create or select a career first."
    end
    if not (MTE and MTE.AmbientRaces and MTE.AmbientRaces.isEnabled and MTE.AmbientRaces.isEnabled()) then
        return false, "Ambient races are disabled in CET settings."
    end
    if not (MTE and MTE.Management and MTE.Management.queueSignedDriverForNextEvent) then
        return false, "Management queue is offline right now."
    end
    local ok, message = MTE.Management.queueSignedDriverForNextEvent(active, 1, mode)
    if ok == true then
        return true, message
    end
    if message == "slot_empty" then
        return false, "You need a signed driver before you can queue a managed run."
    end
    return false, message or "Couldn't queue that managed run."
end

function Commands.stageLiveAmbientHeat(career)
    local active = career or activeCareer()
    if not active then
        return false, "Create or select a career first."
    end
    if not (MTE and MTE.AmbientRaces and MTE.AmbientRaces.stagePromotedEvent) then
        return false, "Ambient board is offline right now."
    end
    return MTE.AmbientRaces.stagePromotedEvent(active, {
        spectator = true,
        preferManaged = true,
    })
end

function Commands.simulateManagedRun(career)
    local active = career or activeCareer()
    if not active then
        return false, "Create or select a career first."
    end
    local cfg = currentRaceConfig()
    local activeEvent = currentActiveEvent()
    if cfg and cfg.spectatorMode == true and activeEvent and activeEvent.sourceType == "ambient_schedule" then
        if not (MTE and MTE.Racing and MTE.Racing.finalizeSpectatorAmbientEvent) then
            return false, "Can't close that live ambient board right now."
        end
        return MTE.Racing.finalizeSpectatorAmbientEvent()
    end
    if not (MTE and MTE.Management and MTE.Management.simulateManagedRun) then
        return false, "Can't reach the management sim right now."
    end
    return MTE.Management.simulateManagedRun(active)
end

function Commands.setNamedStake(career, tierKey)
    if racingState() ~= "prerace" then
        return false, "I only write slips when a race is on the board. Stage one first, honey."
    end
    if not career or not Betting or not Betting.armSingle then
        return false, "Book's closed. Come back when you've got money to move."
    end
    return Betting.armSingle(career, currentRaceConfig(), nil, currentActiveEvent(), tierKey)
end

function Commands.winnerBoardText(career)
    local active = career or activeCareer()
    if not active or not Betting or not Betting.describeWinnerBoard then
        return "Winner board's dark right now. No action up."
    end
    local ok, msg = Betting.describeWinnerBoard(active, currentRaceConfig(), nil, currentActiveEvent())
    return msg or "Winner board's dark right now. No action up."
end

function Commands.winnerFavoriteText(career)
    local active = career or activeCareer()
    if not active or not Betting or not Betting.describeFavorite then
        return "No favorite on the sheet yet. Line's not up."
    end
    local ok, msg = Betting.describeFavorite(active, currentRaceConfig(), nil, currentActiveEvent())
    return msg or "No favorite on the sheet yet. Line's not up."
end

function Commands.winnerValueText(career)
    local active = career or activeCareer()
    if not active or not Betting or not Betting.describeValue then
        return "No value on the sheet right now. Nothing worth a play."
    end
    local ok, msg = Betting.describeValue(active, currentRaceConfig(), nil, currentActiveEvent())
    return msg or "No value on the sheet right now. Nothing worth a play."
end

function Commands.selectWinnerPick(career, pickKey)
    local active = career or activeCareer()
    if not active or not Betting or not Betting.selectWinnerPick then
        return false, "Not taking that action off a dead board, honey."
    end
    return Betting.selectWinnerPick(active, currentRaceConfig(), nil, currentActiveEvent(), pickKey)
end

function Commands.placeWinnerBet(career, sizeKey)
    local active = career or activeCareer()
    if not active or not Betting or not Betting.armWinnerBet then
        return false, "Can't ink that ticket right now."
    end
    return Betting.armWinnerBet(active, currentRaceConfig(), nil, currentActiveEvent(), sizeKey)
end

function Commands.clearBookieSlip(career)
    local active = career or activeCareer()
    if not active or not Betting then
        return false, "Book's closed. Come back when there's real money to move."
    end
    if Betting.clearWinner then
        local ok, msg = Betting.clearWinner(active, "Winner ticket's dead before lock.")
        if ok then
            return ok, msg
        end
    end
    if Betting.clearSingle then
        return Betting.clearSingle(active, "Single-race slip is off the sheet.")
    end
    return false, "Honey, there's no live paper on my side right now."
end

function Commands.execute(commandOrId, args)
    local command = ID_TO_COMMAND[tonumber(commandOrId)] or tostring(commandOrId or "")
    local R = MTE and MTE.Racing or nil
    local K = MTE and MTE.Knockout or nil
    local career = activeCareer()

    if command == "status" then
        return response(true, Commands.statusText())
    end

    if command == "view_car_status" then
        return response(true, Commands.carStatusText())
    end

    if command == "get_setup_suggestion" then
        return response(true, Commands.setupSuggestionText())
    end

    if command == "open_parts_source" then
        return response(true, Commands.partsSourceText())
    end

    if command == "open_tuning" then
        return response(true, Commands.tuningText())
    end

    if command == "setup_accept_contract" then
        local result = MTE and MTE.ContactEvents and MTE.ContactEvents.acceptPhoneContract and MTE.ContactEvents.acceptPhoneContract(career) or nil
        return response(result and result.ok == true, result and result.message or "No live setup contract on deck.", result and result.data or nil)
    end

    if command == "setup_decline_contract" then
        local result = MTE and MTE.ContactEvents and MTE.ContactEvents.declinePhoneContract and MTE.ContactEvents.declinePhoneContract(career) or nil
        return response(result and result.ok == true, result and result.message or "No live setup contract on deck.", result and result.data or nil)
    end

    if command == "standings" then
        return response(true, Commands.standingsText())
    end

    if command == "stats" then
        return response(true, Commands.statsText())
    end

    if command == "view_player_stats" then
        return response(true, Commands.playerStatsText())
    end

    if command == "reroll_fan_message" then
        return response(true, Commands.fanRerollText())
    end

    if command == "wager_earnings" then
        return response(true, Commands.earningsText())
    end

    if command == "wager_board" then
        return response(true, Commands.winnerBoardText(career))
    end

    if command == "wager_favorite" then
        return response(true, Commands.winnerFavoriteText(career))
    end

    if command == "wager_value" then
        return response(true, Commands.winnerValueText(career))
    end

    if command == "wager_pick_self" then
        local ok, msg = Commands.selectWinnerPick(career, "self")
        return response(ok == true, msg)
    end

    if command == "wager_pick_favorite" then
        local ok, msg = Commands.selectWinnerPick(career, "favorite")
        return response(ok == true, msg)
    end

    if command == "wager_pick_value" then
        local ok, msg = Commands.selectWinnerPick(career, "value")
        return response(ok == true, msg)
    end

    if command == "wager_low" then
        local ok, msg
        if Betting and Betting.hasPendingWinnerPick and Betting.hasPendingWinnerPick(career) then
            ok, msg = Commands.placeWinnerBet(career, "light")
        else
            ok, msg = Commands.setNamedStake(career, "light")
        end
        return response(ok == true, msg)
    end

    if command == "wager_medium" then
        local ok, msg
        if Betting and Betting.hasPendingWinnerPick and Betting.hasPendingWinnerPick(career) then
            ok, msg = Commands.placeWinnerBet(career, "standard")
        else
            ok, msg = Commands.setNamedStake(career, "standard")
        end
        return response(ok == true, msg)
    end

    if command == "wager_high" then
        local ok, msg
        if Betting and Betting.hasPendingWinnerPick and Betting.hasPendingWinnerPick(career) then
            ok, msg = Commands.placeWinnerBet(career, "heavy")
        else
            ok, msg = Commands.setNamedStake(career, "heavy")
        end
        return response(ok == true, msg)
    end

    if command == "wager_streak" then
        return response(true, Commands.earningsText())
    end

    if command == "wager_streak_three" then
        if racingState() == "countdown" or racingState() == "racing" or racingState() == "quali" then
            return response(false, "Once that race goes live, the long book is mine. You're too late.")
        end
        local ok, msg = Betting.armStreak(career, 3)
        return response(ok == true, msg)
    end

    if command == "wager_streak_five" then
        if racingState() == "countdown" or racingState() == "racing" or racingState() == "quali" then
            return response(false, "Race goes live, the long book is sealed. No rewrites, no favors.")
        end
        local ok, msg = Betting.armStreak(career, 5)
        return response(ok == true, msg)
    end

    if command == "scout_status" then
        return response(true, Commands.scoutStatusText())
    end

    if command == "scout_current_grid" then
        return response(true, Commands.scoutCurrentGridText())
    end

    if command == "scout_field_read" then
        return response(true, Commands.scoutFieldReadText())
    end

    if command == "scout_watchlist" then
        return response(true, Commands.scoutWatchlistText())
    end

    if command == "scout_accept_leak" then
        local result = MTE and MTE.ContactEvents and MTE.ContactEvents.acceptScoutContract and MTE.ContactEvents.acceptScoutContract(career) or nil
        return response(result and result.ok == true, result and result.message or "No live leak on the line.", result and result.data or nil)
    end

    if command == "scout_decline_leak" then
        local result = MTE and MTE.ContactEvents and MTE.ContactEvents.declineScoutContract and MTE.ContactEvents.declineScoutContract(career) or nil
        return response(result and result.ok == true, result and result.message or "No live leak on the line.", result and result.data or nil)
    end

    if command == "scout_ambient_heat" then
        return response(true, Commands.scoutAmbientHeatText())
    end

    if command == "scout_management_targets" then
        return response(true, Commands.scoutManagementTargetsText())
    end

    if command == "scout_sign_target_one" then
        local ok, msg = Commands.signManagementCandidate(career, 1)
        return response(ok == true, msg)
    end

    if command == "scout_sign_target_two" then
        local ok, msg = Commands.signManagementCandidate(career, 2)
        return response(ok == true, msg)
    end

    if command == "scout_sign_target_three" then
        local ok, msg = Commands.signManagementCandidate(career, 3)
        return response(ok == true, msg)
    end

    if command == "control_ambient_status" then
        return response(true, Commands.controlAmbientStatusText(career), { returnToControlBoard = true })
    end

    if command == "control_queue_managed_sim" then
        local ok, msg = Commands.queueManagedEntry(career, "simulate")
        return response(ok == true, msg, ok and { returnToControlBoard = true } or nil)
    end

    if command == "control_queue_managed_spectate" then
        local ok, msg = Commands.queueManagedEntry(career, "spectate")
        return response(ok == true, msg, ok and { returnToControlBoard = true } or nil)
    end

    if command == "control_stage_live_ambient" then
        local ok, msg = Commands.stageLiveAmbientHeat(career)
        return response(ok == true, msg, ok and { returnToControlBoard = true } or nil)
    end

    if command == "control_simulate_managed_run" then
        local ok, msg = Commands.simulateManagedRun(career)
        return response(ok == true, msg, ok and { returnToControlBoard = true } or nil)
    end

    if command == "custom_type_sprint" or command == "custom_type_drag" or command == "custom_type_knockout"
        or command == "custom_field_four" or command == "custom_field_six" or command == "custom_field_eight" or command == "custom_field_ten"
        or command == "custom_start_grid" or command == "custom_start_rolling" or command == "custom_start_sidebyside"
        or command == "custom_difficulty_street" or command == "custom_difficulty_serious" or command == "custom_difficulty_elite"
        or command == "custom_location_any" or command == "custom_location_watson" or command == "custom_location_westbrook"
        or command == "custom_location_heywood" or command == "custom_location_pacifica" or command == "custom_location_santo_domingo"
        or command == "custom_location_city_center" or command == "custom_location_badlands"
        or command == "custom_confirm" or command == "custom_scrap" then
        career = activeCareer() or career
        local builder = activeCustomRaceBuilder(career)
        if command ~= "custom_scrap" and not builder then
            return response(false, "No custom draft open. Start one from the board.")
        end

        if command == "custom_type_sprint" then
            builder.raceType = "sprint"
            builder.raceLabel = "Sprint"
            setBuilderStep(CUSTOM_RACE_BUILDER_STEP.FIELD_SIZE)
            setPhoneFact(FOREMAN_BUILDER_TYPE_FACT, 1)
            return response(true, customFieldPrompt(), { silent = true, suppressPhoneResponse = true })
        end
        if command == "custom_type_drag" then
            builder.raceType = "drag"
            builder.raceLabel = "Drag"
            setBuilderStep(CUSTOM_RACE_BUILDER_STEP.FIELD_SIZE)
            setPhoneFact(FOREMAN_BUILDER_TYPE_FACT, 2)
            return response(true, customFieldPrompt(), { silent = true, suppressPhoneResponse = true })
        end
        if command == "custom_type_knockout" then
            builder.raceType = "knockout"
            builder.raceLabel = "Knockout"
            builder.circuitId = "night_city_nurburgring"
            builder.locationLabel = "Night City loop"
            setBuilderStep(CUSTOM_RACE_BUILDER_STEP.FIELD_SIZE)
            setPhoneFact(FOREMAN_BUILDER_TYPE_FACT, 3)
            return response(true, customFieldPrompt(), { silent = true, suppressPhoneResponse = true })
        end

        if command == "custom_field_four" or command == "custom_field_six" or command == "custom_field_eight" or command == "custom_field_ten" then
            local fieldKey = command:gsub("^custom_field_", "")
            local field = CUSTOM_FIELD_OPTIONS[fieldKey]
            if not field then
                return response(false, "Can't do that field size.")
            end
            builder.fieldKey = fieldKey
            builder.totalCars = field.totalCars
            builder.aiRivals = field.aiRivals
            builder.fieldLabel = field.label
            if builder.raceType ~= "knockout" then
                setBuilderStep(CUSTOM_RACE_BUILDER_STEP.START_TYPE)
                return response(true, customStartPrompt(), { silent = true, suppressPhoneResponse = true })
            end
            setBuilderStep(CUSTOM_RACE_BUILDER_STEP.DIFFICULTY)
            return response(true, customDifficultyPrompt(builder.raceType == "knockout"), { silent = true, suppressPhoneResponse = true })
        end

        if command == "custom_start_grid" or command == "custom_start_rolling" or command == "custom_start_sidebyside" then
            if command == "custom_start_grid" then
                builder.startType = "grid"
                builder.startLabel = "Grid"
            elseif command == "custom_start_rolling" then
                builder.startType = "rolling"
                builder.startLabel = "Rolling"
            else
                builder.startType = "sidebyside"
                builder.startLabel = "Side-by-side"
            end
            setBuilderStep(CUSTOM_RACE_BUILDER_STEP.DIFFICULTY)
            return response(true, customDifficultyPrompt(false), { silent = true, suppressPhoneResponse = true })
        end

        if command == "custom_difficulty_street" or command == "custom_difficulty_serious" or command == "custom_difficulty_elite" then
            local difficultyKey = command:gsub("^custom_difficulty_", "")
            if not applyCustomDifficulty(builder, difficultyKey) then
                return response(false, "Couldn't do that field pressure.")
            end
            if builder.raceType == "knockout" then
                setBuilderStep(CUSTOM_RACE_BUILDER_STEP.SUMMARY)
                return response(true, customSummaryText(builder), { silent = true, suppressPhoneResponse = true })
            end
            setBuilderStep(CUSTOM_RACE_BUILDER_STEP.LOCATION)
            return response(true, customLocationPrompt(), { silent = true, suppressPhoneResponse = true })
        end

        if command == "custom_location_any" or command == "custom_location_watson" or command == "custom_location_westbrook"
            or command == "custom_location_heywood" or command == "custom_location_pacifica" or command == "custom_location_santo_domingo"
            or command == "custom_location_city_center" or command == "custom_location_badlands" then
            local locationKey = command:gsub("^custom_location_", "")
            if not applyCustomLocation(builder, locationKey) then
                return response(false, "Couldn't do that district.")
            end
            setBuilderStep(CUSTOM_RACE_BUILDER_STEP.SUMMARY)
            return response(true, customSummaryText(builder), { silent = true, suppressPhoneResponse = true })
        end

        if command == "custom_confirm" then
            if deferredPhoneAction then
                return response(false, "Still locking the last draft.")
            end

            local builderSnapshot = copyValue(builder)
            local queued = scheduleDeferredPhoneAction(function()
                local ok, msg = confirmCustomRaceBuilder(R, K, career, builderSnapshot)
                return response(ok == true, msg, ok and { returnToControlBoard = true } or nil)
            end)

            if not queued then
                return response(false, "Could not queue that confirm.")
            end

            return response(true, "Locking the draft.", {
                silent = true,
                suppressPhoneResponse = true,
                deferPhoneResponse = true,
            })
        end

        if command == "custom_scrap" then
            local ok, msg = scrapCustomRaceBuilder(career)
            return response(ok == true, msg)
        end
    end

    if command == "start_career_race" or command == "setup_scheduled" then
        local createdMsg
        career, createdMsg = ensureActiveCareer()
        if not career then return response(false, "Create or select a career first.") end
        if not isIdle() then return response(false, "Finish or cancel the current race first.") end
        local scheduled, eventSummary = currentEventSummary(career)
        if not scheduled then
            return response(false, eventSummary or "No career heat is scheduled right now.")
        end
        if deferredPhoneAction then
            return response(false, "Still locking the last board. Give me a second.")
        end

        local activeCareerNow = activeCareer() or career
        if not activeCareerNow then
            return response(false, "Create or select a career first.")
        end
        if not isIdle() then
            return response(false, "Finish or cancel the current race first.")
        end

        local scheduledNow, eventSummaryNow = currentEventSummary(activeCareerNow)
        if not scheduledNow then
            return response(false, eventSummaryNow or "No career heat is scheduled right now.")
        end

        if scheduledNow.eventType == "knockout" then
            local ok, err = call(K, "openConfig", false, { eventDef = scheduledNow, autoConfirm = true })
            local message = ok and i18n.format("%s%s\nKnockout card staged", createdMsg and (createdMsg .. " ") or "", tostring(eventSummaryNow or eventSummary or "Career heat ready"))
                or (err or "Could not open knockout event.")
            return response(ok == true, message)
        end

        local ok, err = call(R, "stageCareerEvent", false)
        local message = ok and i18n.format("%s%s\nHeat staged. Check with me to route, qualify, or scrub.", createdMsg and (createdMsg .. " ") or "", tostring(eventSummaryNow or eventSummary or "Career heat ready"))
            or (err or "Could not stage race.")
        return response(ok == true, message)
    end

    if command == "open_custom_race_flow" then
        local createdMsg
        career, createdMsg = ensureActiveCareer()
        if not career then return response(false, "Create or select a career first.") end
        if not isIdle() then return response(false, "Finish or cancel the current race first.") end
        local builder = activeCustomRaceBuilder(career)
        if builder then
            return response(true, customBuilderPrompt(builder))
        end
        local message = beginCustomRaceBuilder(career)
        if createdMsg and createdMsg ~= "" then
            message = createdMsg .. " " .. message
        end
        return response(true, message, { silent = true })
    end

    if command == "quick_race" then
        local createdMsg
        career, createdMsg = ensureActiveCareer()
        if not career then return response(false, "Create or select a career first.") end
        if not isIdle() then return response(false, "Finish or cancel the current race first.") end
        local ok, offerOrErr = createQuickRacePhoneOffer(career, createdMsg)
        if ok == true then
            offerOrErr = tostring(offerOrErr or "Got one.") .. " Say go and I'll lock it."
        end
        return response(ok == true, offerOrErr or (ok and "Quick race offer ready." or "Could not line up a quick race."))
    end

    if command == "refresh_quick_race_offer" then
        local refreshedCareer = activeCareer() or career
        if racingState() == "config" and R and R.getDraft then
            local draft = R.getDraft() or {}
            if draft._eventSourceType ~= "quick_race" then
                return response(false, "Only Quickie's live offer refreshes from here.")
            end
            if R.closeConfig then
                R.closeConfig()
            end
            clearActivePhoneOffer()
        elseif not isIdle() then
            return response(false, "Finish the live one first. Then I'll line another up.")
        end
        local ok, offerOrErr = createQuickRacePhoneOffer(refreshedCareer, nil)
        return response(ok == true, offerOrErr or (ok and "Got another one." or "Couldn't line another one up."))
    end

    if command == "knockout_setup" then
        local createdMsg
        career, createdMsg = ensureActiveCareer()
        if not career then return response(false, "Create or select a career first.") end
        if racingState() ~= "idle" then return response(false, "Finish or cancel the sprint race first.") end
        local ok, err = call(K, "openConfig", false)
        return response(ok == true, ok and ((createdMsg and createdMsg .. " " or "") .. "Knockout setup opened.") or (err or "Could not open knockout setup."))
    end

    if command == "confirm_preview" then
        if racingState() == "config" and R and R.getDraft then
            return queueDeferredCommand(function()
                local draft = R.getDraft() or {}
                local ok, err
                if activePhoneOffer and activePhoneOffer.kind == "quick_race" and activePhoneOffer.confirmDraft then
                    draft = activePhoneOffer.confirmDraft
                end
                if draft._eventSourceType == "quick_race" and draft.quickRaceMode == "knockout" then
                    ok, err = launchQuickRaceKnockout(draft)
                else
                    ok, err = call(R, "confirmConfig", false, draft)
                end
                if ok == true then
                    clearActivePhoneOffer()
                end
                return response(ok == true, ok and (activeRaceBoardText("prerace") .. "\nHead to staging.") or (err or "Could not confirm race."))
            end, "Locking the race.", "Still locking the last board. Give me a second.", "Could not queue that race confirm.")
        end
        if knockoutState() == "config" and K then
            return queueDeferredCommand(function()
                local ok, err = call(K, "confirmConfig", false, K.getDraft and K.getDraft() or nil)
                return response(ok == true, ok and "Knockout lobby ready." or (err or "Could not confirm knockout."))
            end, "Locking the knockout.", "Still locking the last board. Give me a second.", "Could not queue that knockout confirm.")
        end
        return response(false, "No race setup is open.")
    end

    if command == "track_start" then
        local state = racingState()
        if state == "prerace" or state == "quali" or state == "countdown" or state == "racing" then
            local ok, routedTarget = call(R, "routePlayerToObjective", false)
            if ok ~= false then
                local ready = false
                if state == "prerace" and R and R.getStartReadiness then
                    ready = select(1, R.getStartReadiness()) == true
                end
                if state == "prerace" and not ready then
                    return controlBoardResponse(true, i18n.format("GPS set to your grid spot: %s.", tostring(routedTarget or "start line")))
                end
                return controlBoardResponse(true, i18n.format("GPS set to the next race objective: %s.", tostring(routedTarget or "target")))
            end
            return response(false, routedTarget or "Could not route you to the race.")
        end
        return response(false, "No race target is ready to route.")
    end

    if command == "start_quali" then
        if racingState() ~= "prerace" then return response(false, "Qualifying is only available from race preview.") end
        local cfg = R and R.getConfig and R.getConfig() or {}
        if not cfg.qualiEnabled then return response(false, "Qualifying is not enabled for this race.") end
        local ok, err = call(R, "startQuali", false)
        return controlBoardResponse(ok ~= false, ok ~= false and "Qualifying started." or (err or "Could not start qualifying."))
    end

    if command == "start_race" then
        if racingState() == "prerace" and R then
            local ready, reason = true, nil
            if R.getStartReadiness then
                ready, reason = R.getStartReadiness()
            end
            if ready == false then
                return response(false, reason or "Race start is not ready yet.")
            end
            local ok, err = call(R, "startRace", false)
            return controlBoardResponse(ok ~= false, ok ~= false and "Race start armed." or (err or "Could not start race."))
        end
        if knockoutState() == "lobby" and K then
            if MTE.AIVehicles and MTE.AIVehicles.isSpawning and MTE.AIVehicles.isSpawning() then
                return response(false, "Knockout grid is still forming.")
            end
            local ok, err = call(K, "startRace", false)
            return controlBoardResponse(ok ~= false, ok ~= false and "Knockout countdown started." or (err or "Could not start knockout."))
        end
        return response(false, "No race is ready to launch.")
    end

    if command == "wager_max" then
        if racingState() ~= "prerace" then return response(false, "Wagers are only available in race preview.") end
        if not career or not MTE.Careers or not MTE.Careers.maxStake then
            return response(false, "Career wagers are unavailable.")
        end
        local actual = R and R.setStake and R.setStake(MTE.Careers.maxStake(career)) or 0
        return response(true, i18n.format("Stake set to %d eddies.", tonumber(actual or 0)))
    end

    if command == "wager_clear" then
        if racingState() ~= "prerace" then return response(false, "No prerace wager to clear.") end
        local ok, msg = Commands.clearBookieSlip(career)
        if ok then
            return response(true, msg)
        end
        local actual = R and R.setStake and R.setStake(0) or 0
        return response(true, i18n.format("Stake set to %d eddies.", tonumber(actual or 0)))
    end

    if command == "close_results" then
        if racingState() == "results" and R and R.closeResults then
            R.closeResults()
            return controlBoardResponse(true, "Race results closed.")
        end
        if knockoutState() == "finished" and K and K.closeResults then
            K.closeResults()
            return controlBoardResponse(true, "Knockout results closed.")
        end
        return response(false, "No results are open.")
    end

    if command == "restart" then
        if racingState() == "results" and R and R.restartRace then
            R.restartRace()
            return controlBoardResponse(true, "Race restarted.")
        end
        return response(false, "Restart is only available from race results.")
    end

    if command == "cancel" or command == "abort" then
        if racingState() == "config" and R and R.getDraft then
            local draft = R.getDraft() or {}
            if draft._eventSourceType == "quick_race" then
                if R.closeConfig then
                    R.closeConfig()
                end
                clearActivePhoneOffer()
                return response(true, "Offer's dead. Ping Quickie when you want another.")
            end
            if R.closeConfig then
                R.closeConfig()
                clearActivePhoneOffer()
                return controlBoardResponse(true, "Race setup cancelled.")
            end
        end
        if racingState() ~= "idle" and R and R.abort then
            clearActivePhoneOffer()
            R.abort()
            return controlBoardResponse(true, "Race cancelled.")
        end
        if knockoutState() ~= "idle" and K and K.abort then
            clearActivePhoneOffer()
            K.abort()
            return controlBoardResponse(true, "Knockout cancelled.")
        end
        return response(false, "No active race to cancel.")
    end

    return response(false, "Unknown NCM command: " .. tostring(commandOrId))
end

function Commands.commandName(id)
    return ID_TO_COMMAND[tonumber(id)] or tostring(id or "")
end

function Commands.resetPhoneState()
    deferredPhoneAction = nil
    clearActivePhoneOffer()
    clearCustomRaceBuilder()
end

function Commands.bindDeferredPhoneSeq(seq)
    if deferredPhoneAction and deferredPhoneAction.seq == nil then
        deferredPhoneAction.seq = tonumber(seq or 0) or 0
    end
end

function Commands.update()
    if not deferredPhoneAction or deferredPhoneAction.seq == nil then
        return nil
    end

    if tonumber(deferredPhoneAction.frames or 0) > 0 then
        deferredPhoneAction.frames = tonumber(deferredPhoneAction.frames or 0) - 1
        return nil
    end

    local action = deferredPhoneAction
    deferredPhoneAction = nil

    local ok, result = pcall(action.run)
    if not ok then
        result = response(false, "Phone command failed: " .. tostring(result))
    end

    return {
        seq = tonumber(action.seq or 0) or 0,
        result = result,
    }
end

function Commands.notify(message, duration)
    notify(message, duration)
end

return Commands



