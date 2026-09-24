local Management = {}
local i18n = require("modules/i18n")

local SLOT_COUNT = 1

local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = clone(entry)
    end
    return copy
end

local function tierBasePurse(tier)
    local purse = {
        Gonk = 1800,
        Streetkid = 4200,
        Solo = 9000,
        Fixer = 18000,
        Edgerunner = 36000,
    }
    return purse[tier] or purse.Gonk
end

local function tierSalary(tier)
    return math.floor(tierBasePurse(tier) * 0.28)
end

local function purseForFinish(tier, position)
    local base = tierBasePurse(tier)
    local payoutScale = {
        1.00,
        0.58,
        0.35,
        0.22,
        0.14,
        0.08,
        0.05,
        0.03,
        0.02,
        0.01,
    }
    local scale = payoutScale[math.max(1, tonumber(position) or 1)] or 0.0
    return math.floor(base * scale)
end

local function fmtMoney(amount)
    local value = math.floor(tonumber(amount) or 0)
    if value >= 0 then
        return i18n.format("%d eddies", value)
    end
    return i18n.format("-%d eddies", math.abs(value))
end

local function defaultSlot(slotIndex)
    return {
        slot = tonumber(slotIndex) or 1,
        driverId = nil,
        signedAt = 0,
        contractTier = nil,
        contractLabel = "",
        salaryPerEvent = 0,
        queuedForNextEvent = false,
        activeEventId = nil,
        lastResult = nil,
    }
end

function Management.defaultState()
    local slots = {}
    for index = 1, SLOT_COUNT do
        slots[index] = defaultSlot(index)
    end
    return {
        enabled = false,
        signedSlots = slots,
        pendingEntry = nil,
        candidateBoard = {
            refreshedAt = 0,
            driverIds = {},
        },
        ledger = {
            eventsEntered = 0,
            salaryPaid = 0,
            winnings = 0,
            net = 0,
            lastEntries = {},
        },
    }
end

local function saveCareers()
    if MTE and MTE.Careers and MTE.Careers.save then
        MTE.Careers.save()
    end
end

local function ensureStateShape(career)
    local dirty = false
    if type(career.management) ~= "table" then
        career.management = Management.defaultState()
        dirty = true
    end

    local state = career.management
    if type(state.signedSlots) ~= "table" then
        state.signedSlots = {}
        dirty = true
    end
    for index = 1, SLOT_COUNT do
        if type(state.signedSlots[index]) ~= "table" then
            state.signedSlots[index] = defaultSlot(index)
            dirty = true
        else
            local slot = state.signedSlots[index]
            if slot.slot ~= index then
                slot.slot = index
                dirty = true
            end
            if slot.salaryPerEvent == nil then
                slot.salaryPerEvent = 0
                dirty = true
            end
            if slot.queuedForNextEvent == nil then
                slot.queuedForNextEvent = false
                dirty = true
            end
        end
    end

    if type(state.ledger) ~= "table" then
        state.ledger = {
            eventsEntered = 0,
            salaryPaid = 0,
            winnings = 0,
            net = 0,
            lastEntries = {},
        }
        dirty = true
    else
        local ledger = state.ledger
        if type(ledger.lastEntries) ~= "table" then
            ledger.lastEntries = {}
            dirty = true
        end
        for _, key in ipairs({ "eventsEntered", "salaryPaid", "winnings", "net" }) do
            if ledger[key] == nil then
                ledger[key] = 0
                dirty = true
            end
        end
    end

    if type(state.candidateBoard) ~= "table" then
        state.candidateBoard = {
            refreshedAt = 0,
            driverIds = {},
        }
        dirty = true
    else
        if type(state.candidateBoard.driverIds) ~= "table" then
            state.candidateBoard.driverIds = {}
            dirty = true
        end
        if state.candidateBoard.refreshedAt == nil then
            state.candidateBoard.refreshedAt = 0
            dirty = true
        end
    end

    if state.enabled == nil then
        state.enabled = false
        dirty = true
    end

    return state, dirty
end

local function resolveDriver(career, driverId)
    if not career or not driverId then
        return nil, "driver_not_found"
    end
    if not (MTE and MTE.Roster and MTE.Roster.findById) then
        return nil, "roster_lookup_unavailable"
    end
    local driver = MTE.Roster.findById(career, driverId)
    if not driver then
        return nil, "driver_not_found"
    end
    return driver, nil
end

local function getSlot(career, slotIndex)
    local state = ensureStateShape(career)
    return state.signedSlots[tonumber(slotIndex) or 1], state
end

local function candidateScore(driver)
    local pace = tonumber(driver and driver.pace or 0.0) or 0.0
    local precision = tonumber(driver and driver.precision or 0.0) or 0.0
    local consistency = tonumber(driver and driver.consistency or 0.0) or 0.0
    local aggression = tonumber(driver and driver.aggression or 0.0) or 0.0
    local wins = tonumber(driver and driver.wins or 0) or 0
    local rep = tonumber(driver and driver.rep or 0) or 0
    local form = 0.0
    if type(driver and driver.recentFinishes) == "table" and #(driver.recentFinishes) > 0 then
        local sum = 0
        for _, finish in ipairs(driver.recentFinishes) do
            sum = sum + (tonumber(finish) or 10)
        end
        form = math.max(-0.25, 1.20 - ((sum / #driver.recentFinishes) * 0.12))
    end
    return (pace * 75.0)
        + (precision * 24.0)
        + (consistency * 24.0)
        + (aggression * 10.0)
        + (wins * 2.4)
        + (rep * 0.015)
        + (form * 12.0)
end

local function buildCandidateBoard(career, count)
    if not (MTE and MTE.Roster and MTE.Roster.listByTier) then
        return {}
    end

    local slot, _ = getSlot(career, 1)
    local signedId = slot and slot.driverId or nil
    local ranked = {}
    for _, driver in ipairs(MTE.Roster.listByTier(career, career.tier) or {}) do
        if driver and driver.id and driver.id ~= signedId then
            ranked[#ranked + 1] = {
                driver = driver,
                score = candidateScore(driver),
            }
        end
    end

    table.sort(ranked, function(left, right)
        if left.score == right.score then
            return tostring(left.driver and left.driver.id or "") < tostring(right.driver and right.driver.id or "")
        end
        return left.score > right.score
    end)

    local ids = {}
    local limit = math.max(1, tonumber(count) or 3)
    for index = 1, math.min(limit, #ranked) do
        ids[#ids + 1] = ranked[index].driver.id
    end
    return ids
end

function Management.refreshCandidateBoard(career, count)
    if not career then
        return nil, "no_active_career"
    end

    local state = ensureStateShape(career)
    state.candidateBoard = {
        refreshedAt = os.time(),
        driverIds = buildCandidateBoard(career, math.max(3, tonumber(count) or 3)),
    }
    saveCareers()
    return state.candidateBoard, nil
end

function Management.init()
    local dirty = false
    if MTE and MTE.Careers and MTE.Careers.list then
        for _, career in ipairs(MTE.Careers.list()) do
            local _, changed = Management.migrateCareer(career)
            dirty = dirty or changed
        end
    end
    if dirty then
        saveCareers()
    end
end

function Management.migrateCareer(career)
    if not career then
        return nil, false
    end
    return ensureStateShape(career)
end

function Management.getState(career)
    if not career then
        return nil
    end
    local state = ensureStateShape(career)
    return state
end

function Management.statusSummaryLine(career)
    if not career then
        return nil
    end
    local slot, state = getSlot(career, 1)
    if not slot.driverId then
        return "Management: slot 1 open."
    end

    local driver = resolveDriver(career, slot.driverId)
    local label = driver and driver.name or tostring(slot.driverId)
    local line = i18n.format("Management: %s [%s]", label, tostring(slot.contractTier or "?"))
    if state.pendingEntry then
        line = line .. ", queued for next scheduled event"
    elseif slot.activeEventId then
        line = line .. ", entered in live schedule"
    end
    return line
end

function Management.statusText(career)
    if not career then
        return "Management only runs inside a live career."
    end

    local slot, state = getSlot(career, 1)
    if not slot.driverId then
        return "Management: slot 1 is open. Sign a driver, then queue them for the next eligible scheduled event."
    end

    local driver = resolveDriver(career, slot.driverId)
    local label = driver and driver.name or tostring(slot.driverId)
    local lines = {
        i18n.format("Management: slot 1 holds %s [%s].", label, tostring(slot.contractTier or "?")),
        i18n.format("Event salary: %s.", fmtMoney(slot.salaryPerEvent or 0)),
        i18n.format("Ledger: %s net across %d managed runs.", fmtMoney(state.ledger.net or 0), tonumber(state.ledger.eventsEntered or 0) or 0),
    }
    if state.pendingEntry then
        lines[#lines + 1] = i18n.format("Queued: next eligible scheduled event (%s).", tostring(state.pendingEntry.mode or "simulate"))
    elseif slot.activeEventId then
        lines[#lines + 1] = i18n.format("Active entry: %s.", tostring(slot.activeEventId))
    end
    if type(slot.lastResult) == "table" then
        lines[#lines + 1] = i18n.format(
            "Last result: P%d in %s, net %s.",
            tonumber(slot.lastResult.finishPosition or 0) or 0,
            tostring(slot.lastResult.district or "Unknown"),
            fmtMoney(slot.lastResult.net or 0))
    end
    return i18n.concat(lines, " ")
end

function Management.candidateText(career, count)
    if not career then
        return "Management only runs inside a live career."
    end
    local state = ensureStateShape(career)
    local board = state.candidateBoard
    if type(board) ~= "table" or type(board.driverIds) ~= "table" or #board.driverIds <= 0 then
        board = select(1, Management.refreshCandidateBoard(career, count))
    end
    if type(board) ~= "table" or type(board.driverIds) ~= "table" or #board.driverIds <= 0 then
        return "No management targets available in the live tier pool."
    end

    local lines = { "Management targets:" }
    for index, driverId in ipairs(board.driverIds or {}) do
        local driver = resolveDriver(career, driverId)
        if driver then
            lines[#lines + 1] = i18n.format(
                "%d) %s [%s] pace %.2f precision %.2f consistency %.2f",
                tonumber(index) or 0,
                tostring(driver.name or driver.id),
                tostring(driver.id or "?"),
                tonumber(driver.pace or 0) or 0,
                tonumber(driver.precision or 0) or 0,
                tonumber(driver.consistency or 0) or 0)
        end
    end
    return i18n.concat(lines, " | ")
end

function Management.signCandidate(career, index)
    if not career then
        return false, "no_active_career"
    end

    local state = ensureStateShape(career)
    local board = state.candidateBoard
    if type(board) ~= "table" or type(board.driverIds) ~= "table" or #board.driverIds <= 0 then
        board = select(1, Management.refreshCandidateBoard(career, 3))
    end

    local choice = tonumber(index) or 1
    local driverId = board and board.driverIds and board.driverIds[choice] or nil
    if not driverId then
        return false, i18n.format("Rico doesn't have a live target in slot %d. Pull a fresh board first.", choice)
    end
    return Management.signDriver(career, driverId)
end

function Management.pendingEntryText(career)
    if not career then
        return nil
    end
    local state = ensureStateShape(career)
    if type(state.pendingEntry) ~= "table" then
        return nil
    end
    local driver = resolveDriver(career, state.pendingEntry.driverId)
    return i18n.format(
        "%s is queued for the next eligible scheduled event in %s mode.",
        tostring(driver and driver.name or state.pendingEntry.driverId or "slot 1"),
        tostring(state.pendingEntry.mode or "simulate"))
end

function Management.signDriver(career, driverId)
    if not career then
        return false, "no_active_career"
    end

    local slot, state = getSlot(career, 1)
    if slot.driverId and slot.driverId == driverId then
        return true, "Driver already occupies slot 1."
    end
    if slot.driverId and slot.driverId ~= driverId then
        return false, "slot_occupied"
    end

    local driver, err = resolveDriver(career, driverId)
    if not driver then
        return false, err
    end

    slot.driverId = driver.id
    slot.signedAt = os.time()
    slot.contractTier = driver.currentTier or driver.tier or career.tier
    slot.contractLabel = i18n.format("%s slot deal", tostring(slot.contractTier or career.tier))
    slot.salaryPerEvent = tierSalary(slot.contractTier)
    slot.queuedForNextEvent = false
    slot.activeEventId = nil
    slot.lastResult = nil
    state.enabled = true
    saveCareers()
    return true, i18n.format("Signed %s into management slot 1.", tostring(driver.name or driver.id))
end

function Management.releaseDriver(career, slotIndex)
    if not career then
        return false, "no_active_career"
    end
    local slot, state = getSlot(career, slotIndex)
    if not slot or not slot.driverId then
        return false, "slot_empty"
    end
    slot.driverId = nil
    slot.signedAt = 0
    slot.contractTier = nil
    slot.contractLabel = ""
    slot.salaryPerEvent = 0
    slot.queuedForNextEvent = false
    slot.activeEventId = nil
    slot.lastResult = nil
    state.pendingEntry = nil
    saveCareers()
    return true, "Released slot 1."
end

function Management.queueSignedDriverForNextEvent(career, slotIndex, mode)
    if not career then
        return false, "no_active_career"
    end
    local slot, state = getSlot(career, slotIndex)
    if not slot or not slot.driverId then
        return false, "slot_empty"
    end

    local driver = resolveDriver(career, slot.driverId)
    if driver and tostring(driver.availability or "active") ~= "active" then
        return false, i18n.format("%s is off the grid right now. Queue them after they clear back in.", tostring(driver.name or slot.driverId))
    end

    state.pendingEntry = {
        slot = tonumber(slotIndex) or 1,
        driverId = slot.driverId,
        requestedAt = os.time(),
        mode = mode == "spectate" and "spectate" or "simulate",
    }
    slot.queuedForNextEvent = true
    saveCareers()
    return true, i18n.format(
        "%s is queued for the next eligible scheduled event in %s mode.",
        tostring(driver and driver.name or slot.driverId),
        tostring(state.pendingEntry.mode))
end

function Management.claimQueuedDriverForEvent(career, event)
    if not career or not event then
        return false
    end
    local state = ensureStateShape(career)
    local pending = state.pendingEntry
    if type(pending) ~= "table" then
        return false
    end
    if type(event.managementEntry) == "table" then
        return false
    end

    local slot = state.signedSlots[tonumber(pending.slot) or 1]
    if not slot or slot.driverId ~= pending.driverId then
        state.pendingEntry = nil
        saveCareers()
        return false
    end

    local driver = resolveDriver(career, slot.driverId)
    if not driver then
        slot.queuedForNextEvent = false
        state.pendingEntry = nil
        saveCareers()
        return false
    end

    local driverTier = driver.currentTier or driver.tier or career.tier
    local eventTier = event.tier or career.tier
    if driverTier ~= eventTier then
        return false
    end

    event.managementEntry = {
        slot = tonumber(pending.slot) or 1,
        driverId = driver.id,
        driverName = driver.name,
        mode = pending.mode or "simulate",
    }
    slot.activeEventId = event.eventId
    slot.queuedForNextEvent = false
    state.pendingEntry = nil
    saveCareers()
    return true
end

function Management.onAmbientEventResolved(career, event, result)
    if not career or type(event) ~= "table" or type(event.managementEntry) ~= "table" then
        return false
    end

    local state = ensureStateShape(career)
    local slot = state.signedSlots[tonumber(event.managementEntry.slot) or 1]
    if not slot then
        return false
    end

    local finish = type(result) == "table" and type(result.finishByDriverId) == "table" and result.finishByDriverId[event.managementEntry.driverId] or nil
    if not finish then
        slot.activeEventId = nil
        saveCareers()
        return false
    end

    local tier = event.tier or career.tier
    local payout = purseForFinish(tier, finish.position)
    local salary = math.max(0, math.floor(tonumber(slot.salaryPerEvent) or 0))
    local net = payout - salary
    local driver = resolveDriver(career, event.managementEntry.driverId)
    local liveTier = driver and (driver.currentTier or driver.tier) or tier

    if driver then
        slot.contractTier = liveTier
        slot.contractLabel = i18n.format("%s slot deal", tostring(liveTier or career.tier))
        slot.salaryPerEvent = tierSalary(liveTier)
    end

    local entry = {
        eventId = event.eventId,
        district = event.district,
        raceType = event.raceType,
        tier = liveTier,
        finishPosition = finish.position,
        payout = payout,
        salary = salary,
        net = net,
        resolvedAt = os.time(),
    }

    slot.lastResult = clone(entry)
    slot.activeEventId = nil
    state.ledger.eventsEntered = (state.ledger.eventsEntered or 0) + 1
    state.ledger.salaryPaid = (state.ledger.salaryPaid or 0) + salary
    state.ledger.winnings = (state.ledger.winnings or 0) + payout
    state.ledger.net = (state.ledger.net or 0) + net
    table.insert(state.ledger.lastEntries, 1, entry)
    if #state.ledger.lastEntries > 6 then
        table.remove(state.ledger.lastEntries, 7)
    end
    saveCareers()
    return true
end

function Management.forceResolveQueuedEvent(career)
    if not career then
        return false, "no_active_career"
    end
    if not (MTE and MTE.AmbientRaces and MTE.AmbientRaces.forceResolveManagedEvent) then
        return false, "ambient_unavailable"
    end
    return MTE.AmbientRaces.forceResolveManagedEvent(career)
end

function Management.stageManagedSpectate(career)
    if not career then
        return false, "no_active_career"
    end
    if not (MTE and MTE.AmbientRaces and MTE.AmbientRaces.stagePromotedEvent) then
        return false, "ambient_unavailable"
    end
    return MTE.AmbientRaces.stagePromotedEvent(career, {
        spectator = true,
        requireManaged = true,
        preferManaged = true,
    })
end

function Management.simulateManagedRun(career)
    return Management.forceResolveQueuedEvent(career)
end

return Management


