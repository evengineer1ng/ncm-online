local Betting = {}
local i18n = require("modules/i18n")

local SINGLE_CONTRACTS = {
    light = {
        key = "light",
        label = "Light contract",
        ratio = 0.25,
        winMultiplier = 1.70,
        podiumMultiplier = 0.55,
        lossPayoutRatio = 0.18,
        repPenalty = 20,
    },
    standard = {
        key = "standard",
        label = "Standard contract",
        ratio = 0.50,
        winMultiplier = 2.05,
        podiumMultiplier = 0.80,
        lossPayoutRatio = 0.30,
        repPenalty = 35,
    },
    heavy = {
        key = "heavy",
        label = "Heavy contract",
        ratio = 1.00,
        winMultiplier = 2.65,
        podiumMultiplier = 1.05,
        lossPayoutRatio = 0.50,
        repPenalty = 60,
    },
}

local WINNER_STAKE_TIERS = {
    light = { key = "light", label = "light", ratio = 0.25 },
    standard = { key = "standard", label = "standard", ratio = 0.40 },
    heavy = { key = "heavy", label = "heavy", ratio = 0.65 },
}

local STREAK_CONTRACTS = {
    [3] = {
        key = "streak3",
        label = "3-race streak",
        length = 3,
        ratio = 0.75,
        completionMultiplier = 4.60,
        failurePayoutRatio = 0.18,
        repPenalty = 45,
        podiumFloor = 3,
    },
    [5] = {
        key = "streak5",
        label = "5-race streak",
        length = 5,
        ratio = 1.25,
        completionMultiplier = 7.90,
        failurePayoutRatio = 0.28,
        repPenalty = 80,
        podiumFloor = 3,
    },
}

local function formatEddies(amount)
    return i18n.format("%d eddies", math.floor((tonumber(amount) or 0) + 0.5))
end

local function pick(options)
    if type(options) ~= "table" or #options == 0 then
        return nil
    end
    return tostring(options[math.random(1, #options)])
end

local function roundStake(amount)
    if (tonumber(amount) or 0) <= 0 then
        return 0
    end
    return math.max(100, math.floor(((tonumber(amount) or 0) / 100.0) + 0.5) * 100)
end

local function roundMoney(amount)
    return math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
end

local function clamp(value, minValue, maxValue)
    local n = tonumber(value)
    if n == nil then
        return minValue
    end
    if n < minValue then
        return minValue
    end
    if n > maxValue then
        return maxValue
    end
    return n
end

local function getMaxStake(career)
    if not (career and MTE and MTE.Careers and MTE.Careers.maxStake) then
        return 0
    end
    return tonumber(MTE.Careers.maxStake(career) or 0)
end

local function getTransactionSystem()
    local ts = nil
    pcall(function()
        ts = Game.GetTransactionSystem()
    end)
    if ts then
        return ts
    end
    pcall(function()
        local container = Game.GetScriptableSystemsContainer()
        if container then
            ts = container:Get("TransactionSystem")
        end
    end)
    return ts
end

local function getMoneyItemID()
    local itemId = nil
    pcall(function()
        itemId = ItemID.FromTDBID(TweakDBID.new("Items.money"))
    end)
    return itemId
end

local function getPlayerEddies()
    local qty = nil
    pcall(function()
        local ts = getTransactionSystem()
        local player = Game.GetPlayer()
        local itemId = getMoneyItemID()
        if not ts or not player then
            return
        end
        if itemId then
            local ok, value = pcall(function()
                return ts:GetItemQuantity(player, itemId, false)
            end)
            if ok and value ~= nil then
                qty = value
                return
            end
            ok, value = pcall(function()
                return ts:GetItemQuantity(player, itemId)
            end)
            if ok and value ~= nil then
                qty = value
                return
            end
            ok, value = pcall(function()
                return ts:GetItemQuantity(player, itemId, true)
            end)
            if ok and value ~= nil then
                qty = value
                return
            end
        end
    end)
    local numericQty = tonumber(qty)
    if numericQty == nil then
        return nil
    end
    return math.max(0, numericQty)
end

local function removeEddies(amount)
    local target = math.max(0, math.floor(tonumber(amount) or 0))
    if target <= 0 then
        return true
    end
    local ok = false
    local removed = nil
    local callOk = pcall(function()
        local player = Game.GetPlayer()
        local ts = getTransactionSystem()
        local itemId = getMoneyItemID()
        if ts and player and itemId then
            removed = ts:RemoveItem(
                player,
                itemId,
                target)
        end
    end)
    if not callOk then
        return false
    end
    if removed == nil then
        ok = true
    else
        ok = removed == true
    end
    return ok == true
end

local function addEddies(amount)
    local target = math.floor(tonumber(amount) or 0)
    if target == 0 then
        return
    end
    pcall(function()
        Game.AddToInventory("Items.money", target)
    end)
end

local function saveCareer()
    if MTE and MTE.Careers and MTE.Careers.save then
        MTE.Careers.save()
    end
end

local function syncRaceStake(amount, escrowed)
    if MTE and MTE.Racing and MTE.Racing.setStakeEscrowed then
        MTE.Racing.setStakeEscrowed(amount or 0, escrowed == true)
    elseif MTE and MTE.Racing and MTE.Racing.setStake then
        MTE.Racing.setStake(amount or 0)
    end
end

local function ensureState(career)
    if type(career.betting) ~= "table" then
        career.betting = {}
    end
    if career.betting.single ~= nil and type(career.betting.single) ~= "table" then
        career.betting.single = nil
    end
    if career.betting.streak ~= nil and type(career.betting.streak) ~= "table" then
        career.betting.streak = nil
    end
    if career.betting.lastOutcome ~= nil and type(career.betting.lastOutcome) ~= "table" then
        career.betting.lastOutcome = nil
    end
    if career.betting.winner ~= nil and type(career.betting.winner) ~= "table" then
        career.betting.winner = nil
    end
    if type(career.betting.winner) ~= "table" then
        career.betting.winner = {
            pending = nil,
            slip = nil,
        }
    end
    if career.betting.winner.pending ~= nil and type(career.betting.winner.pending) ~= "table" then
        career.betting.winner.pending = nil
    end
    if career.betting.winner.slip ~= nil and type(career.betting.winner.slip) ~= "table" then
        career.betting.winner.slip = nil
    end
    return career.betting
end

local function routeSummary(config)
    local cfg = type(config) == "table" and config or {}
    if type(cfg.trackName) == "string" and cfg.trackName ~= "" then
        return cfg.trackName
    end
    local startName = cfg.nodeA and (cfg.nodeA.name or cfg.nodeA.id) or "unknown"
    local finishName = cfg.nodeB and (cfg.nodeB.name or cfg.nodeB.id) or "unknown"
    if startName == finishName then
        return tostring(startName)
    end
    return i18n.format("%s -> %s", tostring(startName), tostring(finishName))
end

local function tierRiskBonus(career)
    local byTier = {
        Gonk = -0.04,
        Street = 0.00,
        Amateur = 0.04,
        SemiPro = 0.08,
        Pro = 0.12,
        Legend = 0.16,
    }
    if not career then
        return 0.0
    end
    return tonumber(byTier[tostring(career.tier or "")] or 0.0)
end

local function riskLabel(modifier)
    if modifier < 1.00 then
        return "safe"
    end
    if modifier < 1.15 then
        return "steady"
    end
    if modifier < 1.30 then
        return "live"
    end
    return "chaotic"
end

function Betting.getRaceRisk(career, config, field, activeEvent)
    local cfg = type(config) == "table" and config or {}
    local currentField = type(field) == "table" and #field or math.max(0, tonumber(cfg.fieldSize or 0) - 1)
    local driverCount = math.max(1, currentField + 1)
    local distance = tonumber(cfg.distance) or 0
    local raceType = tostring((activeEvent and activeEvent.eventType) or cfg.raceType or "sprint")
    local modifier = 0.92

    modifier = modifier + math.min(0.20, math.max(0.0, (distance - 2800.0) / 10000.0))
    modifier = modifier + math.min(0.18, math.max(0.0, (driverCount - 4) * 0.035))
    modifier = modifier + tierRiskBonus(career)

    if raceType == "endurance" then
        modifier = modifier + 0.14
    elseif raceType == "drag" then
        modifier = modifier - 0.05
    elseif raceType == "knockout" then
        modifier = modifier + 0.18
    end

    if tostring(cfg.startType or "grid") == "rolling" then
        modifier = modifier + 0.04
    end
    if cfg.allowCombat == true then
        modifier = modifier + 0.06
    end
    if cfg.qualiEnabled == true then
        modifier = modifier + 0.03
    end

    local stats = career and career.stats or {}
    modifier = modifier + math.min(0.10, (tonumber(stats.winStreak) or 0) * 0.02)
    modifier = modifier + math.min(0.12, (tonumber(stats.lossStreak) or 0) * 0.03)

    modifier = math.max(0.85, math.min(1.60, modifier))
    return {
        modifier = modifier,
        label = riskLabel(modifier),
        route = routeSummary(cfg),
        distance = distance,
        fieldSize = driverCount,
        raceType = raceType,
    }
end

local function setLastOutcome(state, text)
    state.lastOutcome = {
        text = tostring(text or ""),
        at = os.time(),
    }
end

local function singleContractPreview(contract)
    return pick({
        i18n.format(
            "%s hung on %s. Stake %s, risk %s x%.2f. Win pays %s, podium still kicks %s.",
            tostring(contract.label or "Contract"),
            tostring(contract.route or "the board"),
            formatEddies(contract.stake or 0),
            tostring(contract.riskLabel or "steady"),
            tonumber(contract.riskModifier or 1.0),
            formatEddies(contract.projectedWin or 0),
            formatEddies(contract.projectedPodium or 0)),
        i18n.format(
            "%s is hanging on %s. Stake %s. Risk %s x%.2f. First pays %s, podium keeps %s alive.",
            tostring(contract.label or "Contract"),
            tostring(contract.route or "the board"),
            formatEddies(contract.stake or 0),
            tostring(contract.riskLabel or "steady"),
            tonumber(contract.riskModifier or 1.0),
            formatEddies(contract.projectedWin or 0),
            formatEddies(contract.projectedPodium or 0)),
    })
end

local function streakContractPreview(contract)
    return pick({
        i18n.format(
            "%s live: %d/%d legs cleared. Stake %s. Cashout pacing %s if you keep feeding me podiums.",
            tostring(contract.label or "Streak contract"),
            tonumber(contract.progress or 0),
            tonumber(contract.length or 0),
            formatEddies(contract.stake or 0),
            formatEddies(contract.projectedPayout or 0)),
        i18n.format(
            "%s is still breathing: %d/%d legs cleared. Stake %s. Keep the podiums coming and the paper grows to %s.",
            tostring(contract.label or "Streak contract"),
            tonumber(contract.progress or 0),
            tonumber(contract.length or 0),
            formatEddies(contract.stake or 0),
            formatEddies(contract.projectedPayout or 0)),
    })
end

local function averageRecentFinish(driver)
    local total = 0
    local count = 0
    for _, finish in ipairs(driver and driver.recentFinishes or {}) do
        local position = tonumber(finish)
        if position and position > 0 then
            total = total + position
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

local function currentVehicleRaceFit(career, config)
    local vehicleKey = MTE and MTE.Tuning and MTE.Tuning._vehicleKey or nil
    if not (career and vehicleKey and MTE and MTE.Parts and MTE.Parts.getRaceFitForConfig) then
        return 1.0
    end
    return tonumber(MTE.Parts.getRaceFitForConfig(career, vehicleKey, config)) or 1.0
end

local function playerWinnerEntry(career, fieldEntries, config)
    local stats = career and career.stats or {}
    local racesFinished = math.max(1, tonumber(stats.racesFinished or 0) or 0)
    local wins = tonumber(stats.wins or 0) or 0
    local podiums = tonumber(stats.podiums or 0) or 0
    local fit = currentVehicleRaceFit(career, config)

    local totalFieldThreat = 0
    for _, entry in ipairs(fieldEntries or {}) do
        totalFieldThreat = totalFieldThreat + driverThreatScore(entry)
    end
    local avgFieldThreat = (#(fieldEntries or {}) > 0) and (totalFieldThreat / #fieldEntries) or 120

    local pace = 0.96
        + clamp((fit - 1.0) * 0.80, -0.05, 0.16)
        + clamp((tonumber(career and career.rep or 0) or 0) / 2500.0, 0.0, 0.12)
        + clamp((tonumber(stats.winStreak or 0) or 0) * 0.01, 0.0, 0.04)
        + ((clamp(avgFieldThreat, 90, 160) - 120) / 40.0) * 0.03

    return {
        driverId = "player",
        id = "player",
        name = "V",
        displayName = "V",
        isPlayer = true,
        pace = clamp(pace, 0.88, 1.20),
        consistency = clamp((podiums / racesFinished) * 0.9 + 0.32, 0.35, 0.92),
        aggression = clamp(0.42 + ((tonumber(stats.winStreak or 0) or 0) * 0.03), 0.40, 0.82),
        wins = wins,
        rivalScore = 0,
        headToHeadWins = 0,
        recentFinishes = {},
        carFit = fit,
    }
end

local function routeMarketId(config, fieldEntries)
    local cfg = type(config) == "table" and config or {}
    return i18n.format(
        "%s|%s|%d",
        tostring(cfg.routeId or cfg.trackName or routeSummary(cfg) or "route"),
        tostring(cfg.startType or "grid"),
        #(fieldEntries or {}))
end

local function buildWinnerBoard(career, config, field, activeEvent)
    if not career then
        return nil, "I only price races for a live career."
    end

    local fieldEntries = {}
    for _, entry in ipairs(type(field) == "table" and field or activeFieldEntries()) do
        if type(entry) == "table" and entry.isPlayer ~= true then
            fieldEntries[#fieldEntries + 1] = entry
        end
    end
    if #fieldEntries == 0 then
        return nil, "Stage me a field first, then I'll hang the winner board."
    end

    local entries = { playerWinnerEntry(career, fieldEntries, config) }
    for _, entry in ipairs(fieldEntries) do
        entries[#entries + 1] = entry
    end

    local maxScore = nil
    local scored = {}
    for _, entry in ipairs(entries) do
        local score = driverThreatScore(entry)
        scored[#scored + 1] = { entry = entry, score = score }
        maxScore = maxScore and math.max(maxScore, score) or score
    end
    maxScore = maxScore or 100

    local weights = {}
    local totalWeight = 0
    for _, item in ipairs(scored) do
        local driverId = tostring(item.entry.driverId or item.entry.id or item.entry.name or "")
        local weight = math.exp((item.score - maxScore) / 26.0)
        weights[driverId] = weight
        totalWeight = totalWeight + weight
    end
    totalWeight = math.max(0.001, totalWeight)

    local boardEntries = {}
    for _, item in ipairs(scored) do
        local driverId = tostring(item.entry.driverId or item.entry.id or item.entry.name or "")
        local probability = clamp((weights[driverId] or 0.0) / totalWeight, 0.06, 0.72)
        local odds = clamp(math.floor(((0.92 / probability) * 10.0) + 0.5) / 10.0, 1.5, 9.5)
        boardEntries[#boardEntries + 1] = {
            driverId = driverId,
            name = tostring(item.entry.displayName or item.entry.name or item.entry.id or driverId),
            isPlayer = item.entry.isPlayer == true,
            score = item.score,
            probability = probability,
            odds = odds,
        }
    end

    table.sort(boardEntries, function(left, right)
        return (left.probability or 0) > (right.probability or 0)
    end)

    local favorite = boardEntries[1]
    local playerEntry = nil
    local value = nil
    for index, entry in ipairs(boardEntries) do
        if entry.isPlayer == true then
            playerEntry = entry
        end
        local edge = (entry.probability or 0) * (entry.odds or 0)
        if index > 1 and (entry.probability or 0) >= 0.12 and (value == nil or edge > ((value.probability or 0) * (value.odds or 0))) then
            value = entry
        end
    end
    value = value or boardEntries[math.min(#boardEntries, 2)] or favorite
    local dog = boardEntries[#boardEntries]

    return {
        route = routeSummary(config),
        raceType = tostring((activeEvent and activeEvent.eventType) or (config and config.raceType) or "race"),
        marketId = routeMarketId(config, fieldEntries),
        favorite = favorite,
        value = value,
        dog = dog,
        player = playerEntry,
        entries = boardEntries,
    }, nil
end

local function boardRunnerLine(prefix, entry)
    if type(entry) ~= "table" then
        return nil
    end
    return i18n.format("%s %s at %.1fx", tostring(prefix or "Board:"), tostring(entry.name or "runner"), tonumber(entry.odds or 0))
end

local function winnerSlipPreview(slip)
    return pick({
        i18n.format(
            "Winner paper's live on %s: %s for %s at %.1fx. Land it and I pay %s.",
            tostring(slip.route or "the board"),
            tostring(slip.runnerName or "runner"),
            formatEddies(slip.stake or 0),
            tonumber(slip.odds or 0),
            formatEddies(slip.projectedPayout or 0)),
        i18n.format(
            "I've got winner paper hanging on %s: %s for %s at %.1fx. Hit it and I open the purse for %s.",
            tostring(slip.route or "the board"),
            tostring(slip.runnerName or "runner"),
            formatEddies(slip.stake or 0),
            tonumber(slip.odds or 0),
            formatEddies(slip.projectedPayout or 0)),
    })
end

local function pendingWinnerPreview(pending)
    return pick({
        i18n.format(
            "Mmm. %s at %.1fx. Bring me light, standard, or heavy and I'll make it real.",
            tostring(pending.runnerName or "runner"),
            tonumber(pending.odds or 0)),
        i18n.format(
            "%s is sitting at %.1fx. Give me light, standard, or heavy and I'll ink it.",
            tostring(pending.runnerName or "runner"),
            tonumber(pending.odds or 0)),
    })
end

function Betting.getBooksText(career)
    if not career then
        return "My book stays shut until you've got a live career."
    end

    local state = ensureState(career)
    local stats = MTE and MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
    local lines = {
        "My sheet",
        i18n.format("Career earnings: %s", formatEddies(stats.eddiesEarned or 0)),
        i18n.format("Wins %d | Podiums %d | Heater %d", tonumber(stats.wins or 0), tonumber(stats.podiums or 0), tonumber(stats.winStreak or 0)),
    }

    if state.single then
        lines[#lines + 1] = singleContractPreview(state.single)
    else
        lines[#lines + 1] = pick({
            "No single-race paper live right now.",
            "No single-race paper hanging right now.",
        })
    end

    if state.winner and state.winner.slip then
        lines[#lines + 1] = winnerSlipPreview(state.winner.slip)
    elseif state.winner and state.winner.pending then
        lines[#lines + 1] = pendingWinnerPreview(state.winner.pending)
    else
        local board = buildWinnerBoard(career, MTE and MTE.Racing and MTE.Racing.getConfig and MTE.Racing.getConfig() or {}, nil, MTE and MTE.Racing and MTE.Racing._activeEvent or nil)
        if type(board) == "table" then
            lines[#lines + 1] = i18n.format("Winner board | %s", tostring(board.route or "current race"))
            if board.favorite then lines[#lines + 1] = boardRunnerLine("Favorite:", board.favorite) end
            if board.player then lines[#lines + 1] = boardRunnerLine("You:", board.player) end
            if board.value and board.value.driverId ~= (board.favorite and board.favorite.driverId or "") then
                lines[#lines + 1] = boardRunnerLine("Value:", board.value)
            end
        end
    end

    if state.streak then
        lines[#lines + 1] = streakContractPreview(state.streak)
    else
        lines[#lines + 1] = pick({
            "No long paper live right now.",
            "No long paper breathing right now.",
        })
    end

    if state.lastOutcome and state.lastOutcome.text and state.lastOutcome.text ~= "" then
        lines[#lines + 1] = "Last whisper: " .. tostring(state.lastOutcome.text)
    end

    return i18n.concat(lines, "\n")
end

function Betting.clearSingle(career, reason)
    if not career then
        return false, pick({
            "No sheet, no void. Bring me a live career first.",
            "No live sheet, no void. Bring me a real career first.",
        })
    end

    local state = ensureState(career)
    local contract = state.single
    if not contract then
        syncRaceStake(0, false)
        return false, pick({
            "No single-race paper live right now.",
            "No single-race paper on my sheet right now.",
        })
    end

    if tonumber(contract.stake or 0) > 0 then
        addEddies(contract.stake)
    end
    state.single = nil
    setLastOutcome(state, reason or "Single-race paper burned off the sheet.")
    syncRaceStake(0, false)
    saveCareer()
    return true, pick({
        "Paper's burned. Stake walked back to you.",
        "Paper's off the sheet. Stake walked back to you.",
    })
end

function Betting.clearWinner(career, reason)
    if not career then
        return false, pick({
            "No sheet, no void. Bring me a live career first.",
            "No live sheet, no void. Bring me a real career first.",
        })
    end

    local state = ensureState(career)
    if state.winner and state.winner.pending then
        state.winner.pending = nil
        setLastOutcome(state, reason or "Winner name scratched before the money landed.")
        saveCareer()
        return true, "Name scratched. No money was down."
    end

    local slip = state.winner and state.winner.slip or nil
    if not slip then
        return false, pick({
            "No winner paper live right now.",
            "No winner paper hanging right now.",
        })
    end

    if tonumber(slip.stake or 0) > 0 then
        addEddies(slip.stake)
    end
    state.winner.slip = nil
    setLastOutcome(state, reason or "Winner paper burned off the board.")
    saveCareer()
    return true, pick({
        "Winner paper's burned. Stake walked back to you.",
        "Winner paper's off the board. Stake walked back to you.",
    })
end

function Betting.hasPendingWinnerPick(career)
    local state = career and ensureState(career) or nil
    return state ~= nil and state.winner ~= nil and type(state.winner.pending) == "table"
end

function Betting.getWinnerBoard(career, config, field, activeEvent)
    return buildWinnerBoard(career, config, field, activeEvent)
end

function Betting.describeFavorite(career, config, field, activeEvent)
    local board, err = buildWinnerBoard(career, config, field, activeEvent)
    if not board then
        return false, err
    end
    local favorite = board.favorite
    if not favorite then
        return false, "No chalk is hanging on this board yet."
    end
    return true, i18n.format("Chalk is %s at %.1fx. Short price, mean return, still enough teeth to bite.", tostring(favorite.name or "runner"), tonumber(favorite.odds or 0))
end

function Betting.describeValue(career, config, field, activeEvent)
    local board, err = buildWinnerBoard(career, config, field, activeEvent)
    if not board then
        return false, err
    end
    local value = board.value
    if not value then
        return false, "I'm not seeing clean value on this one yet."
    end
    return true, i18n.format("Value is %s at %.1fx. Not safe. Just hanging softer than it should.", tostring(value.name or "runner"), tonumber(value.odds or 0))
end

function Betting.describeWinnerBoard(career, config, field, activeEvent)
    local board, err = buildWinnerBoard(career, config, field, activeEvent)
    if not board then
        return false, err
    end

    local lines = {
        i18n.format("Winner board | %s", tostring(board.route or "current race")),
    }
    if board.favorite then lines[#lines + 1] = boardRunnerLine("Favorite:", board.favorite) end
    if board.player then lines[#lines + 1] = boardRunnerLine("You:", board.player) end
    if board.value then lines[#lines + 1] = boardRunnerLine("Value:", board.value) end
    if board.dog and board.dog.driverId ~= (board.value and board.value.driverId or "") then
        lines[#lines + 1] = boardRunnerLine("Live dog:", board.dog)
    end
    lines[#lines + 1] = "If you want winner paper, point at yourself, the chalk, or the value price. Bring me light, standard, or heavy and I ink it."
    return true, i18n.concat(lines, "\n")
end

local function selectedBoardEntry(board, pickKey)
    if type(board) ~= "table" then return nil end
    if pickKey == "self" then
        return board.player
    end
    if pickKey == "favorite" then
        return board.favorite
    end
    if pickKey == "value" then
        return board.value
    end
    return nil
end

function Betting.selectWinnerPick(career, config, field, activeEvent, pickKey)
    if not career then
        return false, "I only hang winner prices for live careers."
    end

    local board, err = buildWinnerBoard(career, config, field, activeEvent)
    if not board then
        return false, err
    end

    local state = ensureState(career)
    local selected = selectedBoardEntry(board, pickKey)
    if not selected then
        return false, "That name isn't hanging clean on my board."
    end

    state.winner.pending = {
        marketId = board.marketId,
        route = board.route,
        driverId = tostring(selected.driverId or ""),
        runnerName = tostring(selected.name or "runner"),
        odds = tonumber(selected.odds or 0) or 0,
        pickKey = tostring(pickKey or ""),
    }
    setLastOutcome(state, i18n.format("Winner board is leaning %s at %.1fx.", state.winner.pending.runnerName, state.winner.pending.odds))
    saveCareer()
    return true, pick({
        i18n.format("Mmm. I can hang %s at %.1fx. Bring me light, standard, or heavy and I'll ink it.", tostring(state.winner.pending.runnerName), tonumber(state.winner.pending.odds or 0)),
        i18n.format("I've got %s at %.1fx clean on the board. Bring me light, standard, or heavy and I'll write it.", tostring(state.winner.pending.runnerName), tonumber(state.winner.pending.odds or 0)),
    })
end

function Betting.armWinnerBet(career, config, field, activeEvent, sizeKey)
    if not career then
        return false, "I only write winner paper for live careers."
    end

    local tier = WINNER_STAKE_TIERS[tostring(sizeKey or "")]
    if not tier then
        return false, "That size isn't on my sheet."
    end

    local state = ensureState(career)
    local pending = state.winner and state.winner.pending or nil
    if type(pending) ~= "table" then
        return false, "Pick the name first. I don't ink blank paper."
    end
    if state.winner and state.winner.slip then
        return false, winnerSlipPreview(state.winner.slip)
    end

    local board, err = buildWinnerBoard(career, config, field, activeEvent)
    if not board then
        return false, err
    end
    if tostring(board.marketId or "") ~= tostring(pending.marketId or "") then
        state.winner.pending = nil
        saveCareer()
        return false, "Board moved. Pull me fresh odds before I ink anything."
    end

    local selected = selectedBoardEntry(board, pending.pickKey)
    if not selected or tostring(selected.driverId or "") ~= tostring(pending.driverId or "") then
        state.winner.pending = nil
        saveCareer()
        return false, "That price moved under your hand. Pull the board again."
    end

    local stake = roundStake(getMaxStake(career) * tier.ratio)
    if stake <= 0 then
        return false, "I can't size that winner paper for this career yet."
    end
    local availableEddies = getPlayerEddies()
    if availableEddies ~= nil and availableEddies < stake then
        return false, i18n.format("You need %s free before I ink that winner paper.", formatEddies(stake))
    end
    if not removeEddies(stake) then
        return false, "Couldn't float the stake. Let the account settle and try me again."
    end

    local payout = roundMoney(stake * (tonumber(selected.odds or 0) or 0))
    state.winner.slip = {
        marketId = board.marketId,
        route = board.route,
        targetId = tostring(selected.driverId or ""),
        runnerName = tostring(selected.name or "runner"),
        odds = tonumber(selected.odds or 0) or 0,
        stake = stake,
        projectedPayout = payout,
        sizeKey = tier.key,
        armedAt = os.time(),
    }
    state.winner.pending = nil
    setLastOutcome(state, i18n.format("Winner paper written on %s for %s at %.1fx.", state.winner.slip.runnerName, formatEddies(stake), state.winner.slip.odds))
    saveCareer()
    return true, pick({
        i18n.format("You're in for %s on %s at %.1fx. Hit it and I pay %s.", formatEddies(stake), tostring(state.winner.slip.runnerName), tonumber(state.winner.slip.odds or 0), formatEddies(payout)),
        i18n.format("Paper's written: %s on %s at %.1fx. Land it and I open the purse for %s.", formatEddies(stake), tostring(state.winner.slip.runnerName), tonumber(state.winner.slip.odds or 0), formatEddies(payout)),
    })
end

function Betting.armSingle(career, config, field, activeEvent, tierKey)
    if not career then
        return false, "No bankroll, no paper. Bring me a live career."
    end

    local profile = SINGLE_CONTRACTS[tostring(tierKey or "")]
    if not profile then
        return false, "That paper tier isn't on my sheet."
    end

    local state = ensureState(career)
    if state.single then
        local _, clearMessage = Betting.clearSingle(career, "Slip rewritten before launch.")
        if clearMessage and clearMessage ~= "" then
            setLastOutcome(state, clearMessage)
        end
    end

    local maxStake = getMaxStake(career)
    local stake = roundStake(maxStake * profile.ratio)
    if stake <= 0 then
        return false, "I can't hang a clean size for you yet."
    end
    local availableEddies = getPlayerEddies()
    if availableEddies ~= nil and availableEddies < stake then
        return false, i18n.format("You need %s free before I ink that slip.", formatEddies(stake))
    end
    if not removeEddies(stake) then
        return false, "Couldn't float that stake. Let your account settle, then come tempt me again."
    end

    local risk = Betting.getRaceRisk(career, config, field, activeEvent)
    local winAward = roundMoney(stake * profile.winMultiplier * risk.modifier)
    local podiumAward = roundMoney(stake * profile.podiumMultiplier * risk.modifier)

    state.single = {
        key = profile.key,
        label = profile.label,
        stake = stake,
        route = risk.route,
        routeId = config and config.routeId or nil,
        trackName = config and config.trackName or nil,
        riskModifier = risk.modifier,
        riskLabel = risk.label,
        projectedWin = winAward,
        projectedPodium = podiumAward,
        winMultiplier = profile.winMultiplier,
        podiumMultiplier = profile.podiumMultiplier,
        lossPayoutRatio = profile.lossPayoutRatio,
        repPenalty = profile.repPenalty,
        podiumFloor = 3,
        armedAt = os.time(),
    }

    setLastOutcome(state, i18n.format("%s wrote for %s.", profile.label, formatEddies(stake)))
    syncRaceStake(stake, true)
    saveCareer()

    return true, pick({
        i18n.format(
            "%s is live on %s. Stake %s. Risk %s x%.2f. First pays %s, podium still keeps you warm at %s.",
            profile.label,
            tostring(risk.route),
            formatEddies(stake),
            tostring(risk.label),
            tonumber(risk.modifier or 1.0),
            formatEddies(winAward),
            formatEddies(podiumAward)),
        i18n.format(
            "%s is hanging on %s. Stake %s. Risk %s x%.2f. Win pays %s, podium still returns %s.",
            profile.label,
            tostring(risk.route),
            formatEddies(stake),
            tostring(risk.label),
            tonumber(risk.modifier or 1.0),
            formatEddies(winAward),
            formatEddies(podiumAward)),
    })
end

function Betting.armStreak(career, races)
    if not career then
        return false, "No live career, no long paper. Bring me a real file first."
    end

    local profile = STREAK_CONTRACTS[tonumber(races) or 0]
    if not profile then
        return false, "That long line isn't on my board."
    end

    local state = ensureState(career)
    if state.streak then
        return false, streakContractPreview(state.streak)
    end

    local stake = roundStake(getMaxStake(career) * profile.ratio)
    if stake <= 0 then
        return false, "I can't shade that long paper for this career yet."
    end
    local availableEddies = getPlayerEddies()
    if availableEddies ~= nil and availableEddies < stake then
        return false, i18n.format("You need %s free before I front a %d-race ticket.", formatEddies(stake), profile.length)
    end
    if not removeEddies(stake) then
        return false, "Couldn't float the long ticket. Let your account settle and ask again."
    end

    state.streak = {
        key = profile.key,
        label = profile.label,
        length = profile.length,
        progress = 0,
        stake = stake,
        completionMultiplier = profile.completionMultiplier,
        failurePayoutRatio = profile.failurePayoutRatio,
        repPenalty = profile.repPenalty,
        podiumFloor = profile.podiumFloor,
        projectedPayout = roundMoney(stake * profile.completionMultiplier),
        riskSum = 0.0,
        armedAt = os.time(),
        results = {},
    }

    setLastOutcome(state, i18n.format("%s opened for %s.", profile.label, formatEddies(stake)))
    saveCareer()
    return true, i18n.format(
        "%s is live. I fronted %s and I want %d straight podiums. Opening cashout pace is %s.",
        profile.label,
        formatEddies(stake),
        profile.length,
        formatEddies(state.streak.projectedPayout or 0))
end

function Betting.onRaceCancelled(career, raceState)
    if not career then
        return nil
    end
    local state = ensureState(career)
    local currentState = tostring(raceState or "")
    if state.winner and state.winner.slip and currentState ~= "countdown" and currentState ~= "racing" then
        local ok = Betting.clearWinner(career, "Winner paper voided when the board got scrubbed.")
        if ok then
            return "Winner paper's burned. Stake walked back to you."
        end
    end
    if not state.single then
        return nil
    end
    if currentState == "countdown" or currentState == "racing" then
        return nil
    end
    local ok = Betting.clearSingle(career, "Single-race paper voided when the board got scrubbed.")
    if ok then
        return "Single-race paper's burned. Stake walked back to you."
    end
    return nil
end

function Betting.resolveRace(career, config, context)
    if not career then
        return nil
    end

    local state = ensureState(career)
    local currentPayout = math.max(0, math.floor(tonumber(context and context.payout) or 0))
    local position = tonumber(context and context.position) or 99
    local isDNF = context and context.isDNF == true
    local field = context and context.field or nil
    local activeEvent = context and context.activeEvent or nil
    local updates = nil
    local messages = {}

    if state.winner and state.winner.slip then
        local slip = state.winner.slip
        local winningDriverId = nil
        local results = type(context and context.results) == "table" and context.results or {}
        local bestPosition = math.huge
        for _, result in ipairs(results) do
            local resultPos = tonumber(result and result.position or 99) or 99
            if resultPos < bestPosition then
                bestPosition = resultPos
                winningDriverId = tostring(result and (result.driverId or result.id or (result.isPlayer and "player")) or "")
            end
        end
        if (winningDriverId == nil or winningDriverId == "") and not isDNF and position == 1 then
            winningDriverId = "player"
        end

        updates = updates or {
            payout = currentPayout,
            wagerWon = false,
            wagerLost = false,
            wagerAmount = tonumber(slip.stake or 0),
            repPenalty = 0,
        }

        if tostring(winningDriverId or "") == tostring(slip.targetId or "") then
            local award = roundMoney(slip.projectedPayout or (tonumber(slip.stake or 0) * tonumber(slip.odds or 0)))
            addEddies(award)
            updates.payout = updates.payout + award
            updates.wagerWon = true
            messages[#messages + 1] = i18n.format("Winner paper landed on %s. I paid %s.", tostring(slip.runnerName or "runner"), formatEddies(award))
        else
            updates.wagerLost = true
            messages[#messages + 1] = i18n.format("Winner paper missed. %s never got there, so I kept the full %s.", tostring(slip.runnerName or "runner"), formatEddies(slip.stake or 0))
        end
        state.winner.slip = nil
        currentPayout = updates.payout
    end

    if state.single then
        local contract = state.single
        updates = updates or {
            payout = currentPayout,
            wagerWon = false,
            wagerLost = false,
            wagerAmount = tonumber(contract.stake or 0),
            repPenalty = 0,
        }

        if not isDNF and position == 1 then
            local award = roundMoney(contract.stake * contract.winMultiplier * (contract.riskModifier or 1.0))
            addEddies(award)
            updates.payout = updates.payout + award
            updates.wagerWon = true
            messages[#messages + 1] = i18n.format("%s cleared. I paid %s.", contract.label, formatEddies(award))
        elseif not isDNF and position <= (contract.podiumFloor or 3) then
            local award = roundMoney(contract.stake * contract.podiumMultiplier * (contract.riskModifier or 1.0))
            addEddies(award)
            updates.payout = updates.payout + award
            messages[#messages + 1] = i18n.format("%s clipped a podium return of %s.", contract.label, formatEddies(award))
        else
            local payoutPenalty = math.min(updates.payout, roundMoney(contract.stake * (contract.lossPayoutRatio or 0.0)))
            if payoutPenalty > 0 then
                addEddies(-payoutPenalty)
            end
            updates.payout = math.max(0, updates.payout - payoutPenalty)
            updates.wagerLost = true
            updates.repPenalty = updates.repPenalty + math.max(0, math.floor(tonumber(contract.repPenalty) or 0))
            messages[#messages + 1] = i18n.format(
                "%s burned. I clipped %s off the purse and tagged you for %d rep.",
                contract.label,
                formatEddies(payoutPenalty),
                math.floor(tonumber(contract.repPenalty) or 0))
        end

        state.single = nil
        syncRaceStake(0, false)
        currentPayout = updates.payout
    end

    if state.streak then
        local contract = state.streak
        updates = updates or {
            payout = currentPayout,
            wagerWon = false,
            wagerLost = false,
            wagerAmount = 0,
            repPenalty = 0,
        }
        local risk = Betting.getRaceRisk(career, config, field, activeEvent)
        local success = not isDNF and position <= (contract.podiumFloor or 3)
        contract.results[#contract.results + 1] = {
            position = position,
            dnf = isDNF,
            route = routeSummary(config),
            risk = risk.modifier,
        }

        if success then
            contract.progress = math.min(contract.length, (tonumber(contract.progress) or 0) + 1)
            contract.riskSum = (tonumber(contract.riskSum) or 0.0) + (tonumber(risk.modifier) or 1.0)
            local averageRisk = contract.riskSum / math.max(1, contract.progress)
            contract.projectedPayout = roundMoney(contract.stake * contract.completionMultiplier * averageRisk)
            if contract.progress >= contract.length then
                local award = roundMoney(contract.stake * contract.completionMultiplier * averageRisk)
                addEddies(award)
                updates.payout = updates.payout + award
                updates.wagerWon = true
                updates.wagerAmount = math.max(updates.wagerAmount or 0, tonumber(contract.stake or 0))
                messages[#messages + 1] = i18n.format("%s cashed. I paid %s.", contract.label, formatEddies(award))
                state.streak = nil
            else
                messages[#messages + 1] = i18n.format(
                    "%s still breathing: %d/%d podium legs cleared.",
                    contract.label,
                    tonumber(contract.progress or 0),
                    tonumber(contract.length or 0))
            end
        else
            local payoutPenalty = math.min(updates.payout, roundMoney(contract.stake * (contract.failurePayoutRatio or 0.0)))
            if payoutPenalty > 0 then
                addEddies(-payoutPenalty)
            end
            updates.payout = math.max(0, updates.payout - payoutPenalty)
            updates.wagerLost = true
            updates.wagerAmount = math.max(updates.wagerAmount or 0, tonumber(contract.stake or 0))
            updates.repPenalty = updates.repPenalty + math.max(0, math.floor(tonumber(contract.repPenalty) or 0))
            messages[#messages + 1] = i18n.format(
                "%s snapped. I clipped %s off the purse and tagged you for %d rep.",
                contract.label,
                formatEddies(payoutPenalty),
                math.floor(tonumber(contract.repPenalty) or 0))
            state.streak = nil
        end
        currentPayout = updates.payout
    end

    if not updates then
        return nil
    end

    if #messages > 0 then
        setLastOutcome(state, i18n.concat(messages, " "))
    end
    saveCareer()
    return updates
end

return Betting


