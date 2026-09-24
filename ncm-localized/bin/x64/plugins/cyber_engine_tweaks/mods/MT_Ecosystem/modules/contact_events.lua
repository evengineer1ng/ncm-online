local ContactEvents = {}
local i18n = require("modules/i18n")

local Archetypes = require("data/contact_event_archetypes")
local PartsData = require("data/parts")

local LCG_A = 1664525
local LCG_C = 1013904223
local LCG_M = 4294967296

local AXIS_TO_SLOT = {
    topSpeed = "engine",
    lowSpeedPull = "engine",
    midSpeedPull = "engine",
    highSpeedPull = "engine",
    launch = "drivetrain",
    crawlResistance = "antiCrawl",
    brakingStrength = "brakes",
    brakingStability = "brakes",
    turnIn = "handling",
    midCornerGrip = "handling",
    rotation = "handling",
    straightLineStability = "stability",
    recoveryControl = "stability",
}

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = deepCopy(entry)
    end
    return copy
end

local function clamp(value, minValue, maxValue)
    if type(value) ~= "number" then return minValue end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function hashString(text)
    local source = tostring(text or "")
    local hash = 0
    for index = 1, #source do
        hash = math.floor((hash * 131 + string.byte(source, index)) % LCG_M)
    end
    return hash
end

local function nextFloat(seed)
    local state = math.floor((seed or 0) % LCG_M)
    state = math.floor((state * LCG_A + LCG_C) % LCG_M)
    return state, (state / LCG_M)
end

local function shuffle(list, seed)
    local out = {}
    for index, value in ipairs(list or {}) do
        out[index] = value
    end
    for index = #out, 2, -1 do
        local roll
        seed, roll = nextFloat(seed + index)
        local swapIndex = math.max(1, math.min(index, math.floor(roll * index) + 1))
        out[index], out[swapIndex] = out[swapIndex], out[index]
    end
    return seed, out
end

local function saveCareers()
    if MTE and MTE.Careers and MTE.Careers.save then
        pcall(MTE.Careers.save)
    end
end

local function currentRaceCount(career)
    local stats = MTE and MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career and career.stats or {}
    return math.max(0, math.floor(tonumber(stats and stats.racesFinished or stats and stats.racesRun or 0) or 0))
end

local function ensureState(career)
    if type(career) ~= "table" then return nil end
    local state = career.contactEventState
    local changed = false
    if type(state) ~= "table" then
        state = {}
        career.contactEventState = state
        changed = true
    end
    if type(state.activeEvents) ~= "table" then
        state.activeEvents = {}
        changed = true
    end
    if type(state.sentEventKeys) ~= "table" then
        state.sentEventKeys = {}
        changed = true
    end
    if type(state.cooldowns) ~= "table" then
        state.cooldowns = {}
        changed = true
    end
    if type(state.memoryFlags) ~= "table" then
        state.memoryFlags = {}
        changed = true
    end
    if type(state.pendingIntel) ~= "table" then
        state.pendingIntel = {}
        changed = true
    end
    if type(state.activeContracts) ~= "table" then
        state.activeContracts = {}
        changed = true
    end
    if tonumber(state.lastEventRace) == nil then
        state.lastEventRace = -99
        changed = true
    end
    if tonumber(state.nextEventId) == nil then
        state.nextEventId = 1
        changed = true
    end
    if changed then
        saveCareers()
    end
    return state
end

local function nextEventId(career)
    local state = ensureState(career)
    local nextId = math.max(1, math.floor(tonumber(state and state.nextEventId) or 1))
    state.nextEventId = nextId + 1
    return i18n.format("dces_%s_%03d", tostring(career.seed or 0), nextId)
end

local function pruneState(career)
    local state = ensureState(career)
    if not state then return nil end
    local raceCount = currentRaceCount(career)
    local active = {}
    for _, event in ipairs(state.activeEvents or {}) do
        local expiresAtRace = tonumber(event and event.expiresAtRace)
        local status = tostring(event and event.status or "active")
        if status == "active" and (not expiresAtRace or raceCount <= expiresAtRace) then
            active[#active + 1] = event
        end
    end
    state.activeEvents = active

    local intel = {}
    for _, entry in ipairs(state.pendingIntel or {}) do
        local expiresAtRace = tonumber(entry and entry.expiresAtRace)
        if not expiresAtRace or raceCount <= expiresAtRace then
            intel[#intel + 1] = entry
        end
    end
    state.pendingIntel = intel

    local pendingOfferIds = {}
    if MTE and MTE.Parts and MTE.Parts.getPendingOffers then
        for _, offer in ipairs(MTE.Parts.getPendingOffers(career) or {}) do
            pendingOfferIds[tostring(offer and offer.offerId or "")] = true
        end
    end

    local contracts = {}
    for _, contract in ipairs(state.activeContracts or {}) do
        local status = tostring(contract and contract.status or "pending")
        local expiresAtRace = tonumber(contract and contract.expiresAtRace)
        local offerId = tostring(contract and contract.offerId or "")
        local keep = true
        if status == "pending" and expiresAtRace and raceCount > expiresAtRace then
            keep = false
            for _, event in ipairs(state.activeEvents or {}) do
                if tostring(event and event.eventId or "") == tostring(contract and contract.eventId or "") then
                    event.status = "expired"
                    event.resolvedAtRace = raceCount
                    event.resolution = "contract_expired"
                end
            end
        elseif status == "accepted" and offerId ~= "" and not pendingOfferIds[offerId] then
            keep = false
            for _, event in ipairs(state.activeEvents or {}) do
                if tostring(event and event.eventId or "") == tostring(contract and contract.eventId or "") then
                    event.status = "resolved"
                    event.resolvedAtRace = raceCount
                    event.resolution = "offer_missing"
                end
            end
        elseif status == "declined" or status == "claimed" or status == "expired" then
            keep = false
        end
        if keep then
            contracts[#contracts + 1] = contract
        end
    end
    state.activeContracts = contracts
    return state
end

local function updateEventStatus(state, eventId, status, raceCount, resolution)
    if type(state) ~= "table" or not eventId then
        return nil
    end
    for _, event in ipairs(state.activeEvents or {}) do
        if tostring(event and event.eventId or "") == tostring(eventId) then
            event.status = tostring(status or event.status or "active")
            event.resolvedAtRace = tonumber(raceCount) or event.resolvedAtRace
            if resolution then
                event.resolution = tostring(resolution)
            end
            return event
        end
    end
    return nil
end

local function activeSetupContract(state)
    for _, contract in ipairs(state and state.activeContracts or {}) do
        if tostring(contract and contract.channel or "") == "setup_phone"
            and tostring(contract and contract.status or "") == "pending" then
            return contract
        end
    end
    return nil
end

local function activeScoutContract(state)
    for _, contract in ipairs(state and state.activeContracts or {}) do
        if tostring(contract and contract.channel or "") == "scout_phone"
            and tostring(contract and contract.status or "") == "pending" then
            return contract
        end
    end
    return nil
end

local function activeContractByOfferId(state, offerId)
    if not offerId then return nil end
    for _, contract in ipairs(state and state.activeContracts or {}) do
        if tostring(contract and contract.offerId or "") == tostring(offerId) then
            return contract
        end
    end
    return nil
end

local function currentVehicleKey(career)
    local tuningKey = MTE and MTE.Tuning and MTE.Tuning._vehicleKey or nil
    if type(tuningKey) == "string" and tuningKey ~= "" then
        return tuningKey
    end
    return career and career.garage and career.garage.meta and career.garage.meta.lastVehicleKey or nil
end

local function currentSeasonPosition(career)
    local championships = MTE and MTE.Championships or nil
    if not (career and championships and championships.activeSeason and championships.driverStandings) then
        return nil, nil
    end
    local season = championships.activeSeason(career)
    if type(season) ~= "table" then
        return nil, nil
    end
    for index, row in ipairs(championships.driverStandings(season) or {}) do
        if tostring(row.driverId or "") == "player" then
            return index, tonumber(row.points or 0) or 0
        end
    end
    return nil, nil
end

local function strongestWeakestRaceFit(build)
    local fits = build and build.raceFits or {}
    local order = {
        { key = "drag", label = "launches and straight pulls" },
        { key = "sprint", label = "technical sprints" },
        { key = "knockout", label = "survival laps" },
        { key = "longRoute", label = "long-route runs" },
    }
    local strongest = order[1]
    local weakest = order[1]
    for _, entry in ipairs(order) do
        local value = tonumber(fits[entry.key]) or 1.0
        if value > (tonumber(fits[strongest.key]) or 1.0) then
            strongest = entry
        end
        if value < (tonumber(fits[weakest.key]) or 1.0) then
            weakest = entry
        end
    end
    return strongest, weakest
end

local function findRival(data)
    local field = nil
    if type(data) == "table" and type(data.field) == "table" then
        field = data.field
    else
        field = MTE and MTE.Racing and MTE.Racing._field or nil
    end
    if type(field) ~= "table" then
        return nil
    end
    local pick = nil
    local bestScore = -1
    for _, driver in ipairs(field) do
        if type(driver) == "table" and driver.isPlayer ~= true then
            local score = (tonumber(driver.rivalScore or 0) or 0) * 10 + (tonumber(driver.headToHeadWins or 0) or 0) * 12 + (tonumber(driver.pace or 0) or 0) * 5
            if score > bestScore then
                bestScore = score
                pick = driver
            end
        end
    end
    return pick
end

local function actorName(archetypeId, seed)
    local archetype = Archetypes.get(archetypeId)
    local pool = archetype and Archetypes.actorPool(archetype.sourceActor and archetype.sourceActor.type) or {}
    if #pool == 0 then
        return "Unknown"
    end
    local shuffled
    seed, shuffled = shuffle(pool, seed)
    return tostring(shuffled[1] or pool[1])
end

local function slotForWeakness(summary)
    local weakest = summary and summary.weaknesses and summary.weaknesses[1] or nil
    if weakest and weakest.axis and AXIS_TO_SLOT[weakest.axis] then
        return AXIS_TO_SLOT[weakest.axis], weakest
    end
    return "handling", weakest
end

local function matchesMinimumRarity(definition, minimumRarity)
    if not minimumRarity then
        return true
    end
    return PartsData.rarityRank(definition and definition.rarity) >= PartsData.rarityRank(minimumRarity)
end

local function chooseOfferItems(career, slotId, options, seed)
    local defs = {}
    for _, definition in ipairs(slotId and PartsData.bySlot(slotId) or PartsData.all()) do
        local include = true
        if options and options.requiresTradeoff and not (definition.tradeoff and definition.tradeoff ~= "") then
            include = false
        end
        if include and not matchesMinimumRarity(definition, options and options.minimumRarity) then
            include = false
        end
        if include then
            defs[#defs + 1] = definition
        end
    end
    if #defs == 0 then
        defs = slotId and PartsData.bySlot(slotId) or PartsData.all()
    end
    local shuffled
    seed, shuffled = shuffle(defs, seed + hashString(slotId or "all_parts"))
    local itemIds = {}
    local limit = math.max(1, math.floor(tonumber(options and options.count) or 2))
    for _, definition in ipairs(shuffled) do
        itemIds[#itemIds + 1] = definition.id
        if #itemIds >= limit then
            break
        end
    end
    return itemIds, seed
end

local function buildContext(career, data)
    local vehicleKey = currentVehicleKey(career)
    local summary = MTE and MTE.Parts and MTE.Parts.getVehicleSummary and vehicleKey and MTE.Parts.getVehicleSummary(career, vehicleKey) or nil
    local rival = findRival(data)
    local rivalBuild = MTE and MTE.Parts and MTE.Parts.getDriverVehicleBuild and rival and MTE.Parts.getDriverVehicleBuild(rival) or nil
    local strongFit, weakFit = strongestWeakestRaceFit(rivalBuild)
    local champPos, champPts = currentSeasonPosition(career)
    local stats = MTE and MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career and career.stats or {}
    local weakestSlot, weakestEntry = slotForWeakness(summary)
    local strengths = summary and summary.strengths or {}
    local weakestLabel = weakestEntry and weakestEntry.label or nil
    return {
        vehicleKey = vehicleKey,
        summary = summary,
        buildIdentity = summary and summary.buildIdentity and summary.buildIdentity.headline or "Balanced",
        strongestLabel = strengths[1] and strengths[1].label or nil,
        weakestLabel = weakestLabel,
        weakestAxis = weakestEntry and weakestEntry.axis or nil,
        weakestSlot = weakestSlot,
        stats = stats,
        champPos = champPos,
        champPts = champPts,
        rival = rival,
        rivalName = tostring(rival and (rival.displayName or rival.name or rival.id) or "that driver"),
        rivalStrongFit = strongFit and strongFit.label or nil,
        rivalWeakFit = weakFit and weakFit.label or nil,
        raceCount = currentRaceCount(career),
    }
end

local function canCreateEvent(career, state, eventKey)
    local raceCount = currentRaceCount(career)
    if tostring(state.sentEventKeys[eventKey] or "") ~= "" then
        return false
    end
    if (#(state.activeEvents or {})) >= Archetypes.MAX_ACTIVE_EVENTS then
        return false
    end
    if (raceCount - (tonumber(state.lastEventRace) or -99)) < Archetypes.COOLDOWN_RACE_GAP then
        return false
    end
    return true
end

local function emitMessage(contactId, message, title)
    if not (MTE and MTE.Events and type(message) == "string" and message ~= "") then
        return false
    end
    MTE.Events.emit("ContactEventMessage", {
        contactId = contactId,
        message = message,
        title = title,
    })
    return true
end

local function formatTemplate(text, replacements)
    text = i18n.source(text)
    local out = tostring(text or "")
    for key, value in pairs(replacements or {}) do
        out = out:gsub("{" .. tostring(key) .. "}", tostring(value or ""))
    end
    return out
end

local function storeIntel(career, state, eventId, context, message)
    state.pendingIntel[#state.pendingIntel + 1] = {
        intelId = eventId,
        text = message,
        rivalName = context.rivalName,
        createdAtRace = context.raceCount,
        expiresAtRace = context.raceCount + Archetypes.INTEL_EXPIRY_RACES,
    }
end

local function createActiveEvent(career, state, archetype, eventKey, context, message, payload)
    local eventId = nextEventId(career)
    local expiresAtRace = context.raceCount + math.max(1, math.floor(tonumber(payload and payload.expiresAtRace) or Archetypes.DEFAULT_OFFER_EXPIRY_RACES))
    local event = {
        eventId = eventId,
        archetype = archetype.id,
        status = "active",
        eventKey = eventKey,
        message = message,
        contactId = archetype.deliveryContactId,
        createdAtRace = context.raceCount,
        expiresAtRace = expiresAtRace,
        payloadType = payload and payload.type or "narrative_only",
    }
    state.activeEvents[#state.activeEvents + 1] = event
    state.sentEventKeys[eventKey] = eventId
    state.lastEventRace = context.raceCount
    return event
end

local function pushSetupContract(state, event, spec)
    state.activeContracts[#state.activeContracts + 1] = {
        contractId = tostring(event.eventId),
        eventId = tostring(event.eventId),
        status = "pending",
        channel = "setup_phone",
        archetype = tostring(event.archetype),
        actorName = tostring(spec.actorName or "Stu"),
        title = tostring(spec.title or "Focused Contract"),
        subtitle = tostring(spec.subtitle or ""),
        slot = tostring(spec.slot or ""),
        itemIds = deepCopy(spec.itemIds or {}),
        expiresAtRace = tonumber(spec.expiresAtRace) or tonumber(event.expiresAtRace),
        createdAtRace = tonumber(spec.createdAtRace) or tonumber(event.createdAtRace),
        sourceContactId = tostring(spec.sourceContactId or "ncm_setup_stu"),
    }
end

local function pushScoutContract(state, event, spec)
    state.activeContracts[#state.activeContracts + 1] = {
        contractId = tostring(event.eventId),
        eventId = tostring(event.eventId),
        status = "pending",
        channel = "scout_phone",
        archetype = tostring(event.archetype),
        actorName = tostring(spec.actorName or "Rico"),
        title = tostring(spec.title or "Leak Contract"),
        subtitle = tostring(spec.subtitle or ""),
        intelText = tostring(spec.intelText or ""),
        rivalName = tostring(spec.rivalName or ""),
        createdAtRace = tonumber(spec.createdAtRace) or tonumber(event.createdAtRace),
        expiresAtRace = tonumber(spec.expiresAtRace) or tonumber(event.expiresAtRace),
        sourceContactId = tostring(spec.sourceContactId or "ncm_scout"),
    }
end

local function deliverPartOffer(career, archetype, context, offerSpec)
    if not (MTE and MTE.Parts and MTE.Parts.enqueueContactOffer) then
        return nil, "parts_unavailable"
    end
    return MTE.Parts.enqueueContactOffer(career, {
        kind = "contact_offer",
        title = offerSpec.title,
        subtitle = offerSpec.subtitle,
        slot = offerSpec.slot,
        price = offerSpec.price,
        itemIds = offerSpec.itemIds,
        expiresAtRace = context.raceCount + Archetypes.DEFAULT_OFFER_EXPIRY_RACES,
        sourceContactId = archetype.deliveryContactId,
    })
end

local function buildRivalLeak(career, state, context)
    if not context.rival then
        return nil
    end
    local eventKey = i18n.format("rival_leak:%s:%d", tostring(context.rival.id or context.rivalName), context.raceCount)
    if not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local actor = actorName("rival_mechanic_leak", hashString(eventKey) + tonumber(career.seed or 0))
    local message = i18n.concat({
        formatTemplate("You don't know me. I wrench for {rival_name}.", { rival_name = context.rivalName }),
        "They burned me after the last run.",
        formatTemplate("Build reads heavy in {rival_strong}. Weakest when the race turns into {rival_weak}.", {
            rival_strong = context.rivalStrongFit or "long pulls",
            rival_weak = context.rivalWeakFit or "launch phases",
        }),
        "Do what you want with that.",
    }, "\n")
    local archetype = Archetypes.get("rival_mechanic_leak")
    local event = createActiveEvent(career, state, archetype, eventKey, context, message, { type = "intel", expiresAtRace = Archetypes.INTEL_EXPIRY_RACES })
    storeIntel(career, state, event.eventId, context, message)
    event.actorName = actor
    emitMessage(archetype.deliveryContactId, message, context.rivalName)
    saveCareers()
    return event
end

local function buildScoutIntelContract(career, state, context)
    if not context.rival or activeScoutContract(state) then
        return nil
    end
    local eventKey = i18n.format("scout_intel_contract:%s:%d", tostring(context.rival.id or context.rivalName), context.raceCount)
    if not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local archetype = Archetypes.get("rival_mechanic_leak")
    local actor = actorName("rival_mechanic_leak", hashString(eventKey) + 47 + tonumber(career.seed or 0))
    local intelText = i18n.concat({
        formatTemplate("{rival_name} is strongest in {rival_strong}.", {
            rival_name = context.rivalName,
            rival_strong = string.lower(tostring(context.rivalStrongFit or "straight pulls")),
        }),
        formatTemplate("They start leaking once the race shifts into {rival_weak}.", {
            rival_weak = string.lower(tostring(context.rivalWeakFit or "tight transitions")),
        }),
    }, " ")
    local message = i18n.concat({
        formatTemplate("Source on {rival_name}. Clean line, short window.", { rival_name = context.rivalName }),
        "I can hand you the leak or burn the contact.",
        "Take it and I fold it into your scout read. Pass and it dies here.",
    }, "\n")
    local event = createActiveEvent(career, state, archetype, eventKey, context, message, { type = "intel", expiresAtRace = 2 })
    event.actorName = actor
    pushScoutContract(state, event, {
        actorName = actor,
        title = i18n.format("Live Leak: %s", tostring(context.rivalName)),
        subtitle = "Short-window intel offer.",
        intelText = intelText,
        rivalName = context.rivalName,
        createdAtRace = context.raceCount,
        expiresAtRace = context.raceCount + 2,
        sourceContactId = "ncm_scout",
    })
    emitMessage("ncm_scout", message, context.rivalName)
    saveCareers()
    return event
end

local function buildCounterOffer(career, state, context)
    local archetype = Archetypes.get("tuner_counter_build")
    local eventKey = i18n.format("counter_offer:%s:%s:%d", tostring(context.vehicleKey or "ride"), tostring(context.weakestAxis or context.weakestSlot or "unknown"), context.raceCount)
    if not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local slotId = context.weakestSlot or "handling"
    local itemIds = chooseOfferItems(career, slotId, { minimumRarity = "Street", count = 2 }, hashString(eventKey) + tonumber(career.seed or 0))
    local slotLabel = PartsData.SLOTS[slotId] and PartsData.SLOTS[slotId].label or slotId
    local title = i18n.format("Counter-Build Pitch: %s", tostring(slotLabel))
    local subtitle = context.weakestLabel
        and i18n.format("Built to stop bleeding time in %s.", string.lower(context.weakestLabel))
        or i18n.format("Built to clean up the weakest phase in your %s setup.", string.lower(tostring(context.buildIdentity or "current")))
    local offer, err = deliverPartOffer(career, archetype, context, {
        title = title,
        subtitle = subtitle,
        slot = slotId,
        itemIds = itemIds,
        price = nil,
    })
    if not offer then
        return nil, err
    end
    local actor = actorName("tuner_counter_build", hashString(eventKey) + 17 + tonumber(career.seed or 0))
    local message = i18n.concat({
        formatTemplate("{actor} here. I've been watching your runs.", { actor = actor }),
        formatTemplate("You're quick, but you're bleeding time in {weakness}.", { weakness = string.lower(tostring(context.weakestLabel or slotLabel)) }),
        formatTemplate("I packed two {slot_label} pieces that push the car back toward control.", { slot_label = string.lower(tostring(slotLabel)) }),
        "Check the garage if you want the deal.",
    }, "\n")
    local event = createActiveEvent(career, state, archetype, eventKey, context, message, { type = "part_offer", expiresAtRace = Archetypes.DEFAULT_OFFER_EXPIRY_RACES })
    event.offerId = offer.offerId
    event.actorName = actor
    emitMessage(archetype.deliveryContactId, message, title)
    saveCareers()
    return event
end

local function buildRivalHeatWarning(career, state, context)
    local archetype = Archetypes.get("rival_heat_warning")
    local eventKey = i18n.format("rival_heat_warning:%s:%s:%d", tostring(context.rival and context.rival.id or context.rivalName), tostring(context.champPos or 0), context.raceCount)
    if not context.rival or not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local actor = actorName("rival_heat_warning", hashString(eventKey) + tonumber(career.seed or 0))
    local message = i18n.concat({
        formatTemplate("{actor}. {rival_name}'s side isn't static anymore.", { actor = actor, rival_name = context.rivalName }),
        formatTemplate("They're trimming the next car toward {rival_strong} and protecting the weak side in {rival_weak}.", {
            rival_strong = string.lower(tostring(context.rivalStrongFit or "straight pulls")),
            rival_weak = string.lower(tostring(context.rivalWeakFit or "tight transitions")),
        }),
        "If you're hunting them, do it before they finish the correction.",
    }, "\n")
    local event = createActiveEvent(career, state, archetype, eventKey, context, message, { type = "intel", expiresAtRace = Archetypes.INTEL_EXPIRY_RACES })
    storeIntel(career, state, event.eventId, context, message)
    event.actorName = actor
    emitMessage(archetype.deliveryContactId, message, context.rivalName)
    saveCareers()
    return event
end

local function promotionContractFlavor(targetTier)
    local tier = tostring(targetTier or "Streetkid")
    if tier == "Streetkid" then
        return {
            archetypeId = "tier_streetkid_promotion_contract",
            slot = "handling",
            opener = "Streetkid room means faster corrections and less margin for lazy rotation.",
            closer = "If you want the starter package, hit 'Source me parts'. Hit 'Tune it' and I drop it.",
        }
    end
    if tier == "Solo" then
        return {
            archetypeId = "tier_solo_promotion_contract",
            slot = "engine",
            opener = "Solo-tier grids stop forgiving dead mid-pull and half-committed braking.",
            closer = "I can lock a harder package now. 'Source me parts' commits. 'Tune it' kills it.",
        }
    end
    if tier == "Fixer" then
        return {
            archetypeId = "tier_fixer_promotion_contract",
            slot = "stability",
            opener = "Fixer-tier traffic punishes twitch and rewards cars that stay composed deep into the run.",
            closer = "I put a cleaner control package together. 'Source me parts' takes it. 'Tune it' passes.",
        }
    end
    return {
        archetypeId = "tier_edgerunner_promotion_contract",
        slot = "antiCrawl",
        opener = "Edgerunner room only respects builds with a real edge and a real cost.",
        closer = "I have something volatile and worth the risk. 'Source me parts' locks it. 'Tune it' burns the lead.",
    }
end

local function buildSetupContract(career, state, context, spec)
    local contractSpec = type(spec) == "table" and spec or {}
    local archetype = Archetypes.get(tostring(contractSpec.archetypeId or "tuner_setup_contract"))
    if not archetype or activeSetupContract(state) then
        return nil
    end
    local slotId = tostring(contractSpec.slot or context.weakestSlot or "handling")
    local slotLabel = PartsData.SLOTS[slotId] and PartsData.SLOTS[slotId].label or slotId
    local eventKey = i18n.format("setup_contract:%s:%s:%d", tostring(archetype.id), tostring(context.weakestAxis or slotId), context.raceCount)
    if not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local itemIds = chooseOfferItems(career, slotId, {
        count = 2,
        minimumRarity = contractSpec.minimumRarity,
        requiresTradeoff = contractSpec.requiresTradeoff == true,
    }, hashString(eventKey) + tonumber(career.seed or 0))
    if #itemIds == 0 then
        return nil
    end
    local actor = actorName(archetype.id, hashString(eventKey) + 11 + tonumber(career.seed or 0))
    local title = tostring(contractSpec.title or i18n.format("Focused Contract: %s", tostring(slotLabel)))
    local subtitle = tostring(contractSpec.subtitle or i18n.format("Two %s pieces tuned against your current weak phase.", string.lower(tostring(slotLabel))))
    local lines = deepCopy(contractSpec.lines or {})
    if #lines == 0 then
        lines = {
            formatTemplate("{actor} here. I can clean up {weakness} without flattening the rest of the car.", {
                actor = actor,
                weakness = string.lower(tostring(context.weakestLabel or slotLabel)),
            }),
            formatTemplate("I built it around {slot_label}.", { slot_label = string.lower(tostring(slotLabel)) }),
            "If you want the package, hit 'Source me parts'. If not, hit 'Tune it' and I walk.",
        }
    end
    local message = i18n.concat(lines, "\n")
    local event = createActiveEvent(career, state, archetype, eventKey, context, message, { type = "contract", expiresAtRace = 2 })
    event.actorName = actor
    event.slot = slotId
    pushSetupContract(state, event, {
        actorName = actor,
        title = title,
        subtitle = subtitle,
        slot = slotId,
        itemIds = itemIds,
        createdAtRace = context.raceCount,
        expiresAtRace = context.raceCount + 2,
        sourceContactId = archetype.deliveryContactId,
    })
    emitMessage(archetype.deliveryContactId, message, title)
    saveCareers()
    return event
end

local function buildRiskyDeal(career, state, context)
    local archetype = Archetypes.get("scavenger_experimental_deal")
    local eventKey = i18n.format("risky_deal:%s:%d", tostring(context.vehicleKey or "ride"), context.raceCount)
    if not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local slotId = context.weakestSlot or "engine"
    local itemIds = chooseOfferItems(career, slotId, { requiresTradeoff = true, minimumRarity = "Pro", count = 2 }, hashString(eventKey) + tonumber(career.seed or 0))
    if #itemIds == 0 then
        return nil
    end
    local slotLabel = PartsData.SLOTS[slotId] and PartsData.SLOTS[slotId].label or slotId
    local title = i18n.format("Back-Alley Deal: %s", tostring(slotLabel))
    local subtitle = "Not clean. Not safe. But it will move the car hard if it suits you."
    local offer, err = deliverPartOffer(career, archetype, context, {
        title = title,
        subtitle = subtitle,
        slot = slotId,
        itemIds = itemIds,
        price = nil,
    })
    if not offer then
        return nil, err
    end
    local actor = actorName("scavenger_experimental_deal", hashString(eventKey) + 29 + tonumber(career.seed or 0))
    local message = i18n.concat({
        formatTemplate("{actor}. Pulled something ugly off a wreck near Charter Hill.", { actor = actor }),
        "Still runs. Definitely not clean.",
        formatTemplate("It's aimed at {slot_label}. It'll wake the car up, but you'll feel the cost.", { slot_label = string.lower(tostring(slotLabel)) }),
        "If you want it, check the garage before someone else pays for the mistake.",
    }, "\n")
    local event = createActiveEvent(career, state, archetype, eventKey, context, message, { type = "part_offer", expiresAtRace = Archetypes.DEFAULT_OFFER_EXPIRY_RACES })
    event.offerId = offer.offerId
    event.actorName = actor
    emitMessage(archetype.deliveryContactId, message, title)
    saveCareers()
    return event
end

local function buildFanReflection(career, state, context)
    local archetype = Archetypes.get("fan_build_reflection")
    local eventKey = i18n.format("fan_reflection:%s:%d", tostring(context.buildIdentity or "balanced"), math.max(0, tonumber(context.stats and context.stats.winStreak or 0) or 0))
    if not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local actor = actorName("fan_build_reflection", hashString(eventKey) + tonumber(career.seed or 0))
    local message = i18n.concat({
        formatTemplate("{actor} here. That {build_identity} build is a whole problem.", { actor = actor, build_identity = string.lower(tostring(context.buildIdentity or "balanced")) }),
        context.strongestLabel and formatTemplate("You keep making time in {strength}.", { strength = string.lower(tostring(context.strongestLabel)) }) or "You keep finding time where the race starts to separate.",
        context.weakestLabel and formatTemplate("Just don't let {weakness} be what drags it under.", { weakness = string.lower(tostring(context.weakestLabel)) }) or "Don't let the soft phase ruin the shape.",
    }, "\n")
    state.sentEventKeys[eventKey] = nextEventId(career)
    state.lastEventRace = context.raceCount
    emitMessage(archetype.deliveryContactId, message, tostring(context.buildIdentity or "Build"))
    saveCareers()
    return { archetype = archetype.id, actorName = actor, message = message }
end

local function buildCrewWarning(career, state, context)
    local archetype = Archetypes.get("crew_warning")
    local eventKey = i18n.format("crew_warning:%s:%d", tostring(context.weakestAxis or context.weakestSlot or "unknown"), math.max(0, tonumber(context.stats and context.stats.lossStreak or 0) or 0))
    if not canCreateEvent(career, state, eventKey) then
        return nil
    end
    local actor = actorName("crew_warning", hashString(eventKey) + tonumber(career.seed or 0))
    local slotLabel = PartsData.SLOTS[context.weakestSlot or "handling"] and PartsData.SLOTS[context.weakestSlot or "handling"].label or (context.weakestSlot or "build")
    local message = i18n.concat({
        formatTemplate("{actor}. Stop chasing the wrong edge.", { actor = actor }),
        formatTemplate("You're not losing because the car is slow. You're losing in {weakness}.", { weakness = string.lower(tostring(context.weakestLabel or slotLabel)) }),
        formatTemplate("Next move is {slot_label}, not more of the same.", { slot_label = string.lower(tostring(slotLabel)) }),
    }, "\n")
    state.sentEventKeys[eventKey] = nextEventId(career)
    state.lastEventRace = context.raceCount
    emitMessage(archetype.deliveryContactId, message, tostring(slotLabel))
    saveCareers()
    return { archetype = archetype.id, actorName = actor, message = message }
end

function ContactEvents.init()
    if MTE and MTE.Careers and MTE.Careers.list then
        for _, career in ipairs(MTE.Careers.list()) do
            pruneState(career)
        end
        saveCareers()
    end
    print("[NCM/ContactEvents] Dynamic contact events ready.")
end

function ContactEvents.getPendingIntel(career)
    local state = pruneState(career)
    if not state then return {} end
    return deepCopy(state.pendingIntel or {})
end

function ContactEvents.getScoutIntelText(career)
    local intel = ContactEvents.getPendingIntel(career)
    if not intel[1] or not intel[1].text then
        return nil
    end
    return "Leak on deck: " .. tostring(intel[1].text):gsub("\n", " ")
end

function ContactEvents.hasScoutPhoneContract(career)
    local state = pruneState(career)
    return activeScoutContract(state) ~= nil
end

function ContactEvents.hasSetupPhoneContract(career)
    local state = pruneState(career)
    return activeSetupContract(state) ~= nil
end

function ContactEvents.acceptPhoneContract(career)
    local state = pruneState(career)
    local contract = activeSetupContract(state)
    if not contract then
        return {
            ok = false,
            message = "No live setup contract on deck.",
            data = { contactId = "ncm_setup_stu" },
        }
    end
    local offer, err = deliverPartOffer(career, {
        deliveryContactId = tostring(contract.sourceContactId or "ncm_setup_stu"),
    }, {
        raceCount = currentRaceCount(career),
    }, {
        title = contract.title,
        subtitle = contract.subtitle,
        slot = contract.slot,
        itemIds = contract.itemIds,
        price = nil,
    })
    if not offer then
        return {
            ok = false,
            message = err == "Too many pending offers" and "Garage inbox is full. Clear an offer before I lock this contract." or "Couldn't lock the contract right now.",
            data = { contactId = "ncm_setup_stu" },
        }
    end
    contract.status = "accepted"
    contract.offerId = offer.offerId
    updateEventStatus(state, contract.eventId, "active", currentRaceCount(career), "offer_pending")
    local event = updateEventStatus(state, contract.eventId, "active", currentRaceCount(career), "offer_pending")
    if event then
        event.offerId = offer.offerId
    end
    saveCareers()
    return {
        ok = true,
        message = i18n.format("Locked. %s is waiting in the garage offers tab.", tostring(contract.title or "The package")),
        data = { contactId = "ncm_setup_stu" },
    }
end

function ContactEvents.declinePhoneContract(career)
    local state = pruneState(career)
    local contract = activeSetupContract(state)
    if not contract then
        return {
            ok = false,
            message = "No live setup contract on deck.",
            data = { contactId = "ncm_setup_stu" },
        }
    end
    contract.status = "declined"
    updateEventStatus(state, contract.eventId, "declined", currentRaceCount(career), "player_declined")
    saveCareers()
    pruneState(career)
    saveCareers()
    return {
        ok = true,
        message = "Lead burned. Stu killed the contract and cleared the line.",
        data = { contactId = "ncm_setup_stu" },
    }
end

function ContactEvents.acceptScoutContract(career)
    local state = pruneState(career)
    local contract = activeScoutContract(state)
    if not contract then
        return {
            ok = false,
            message = "No live leak on the line.",
            data = { contactId = "ncm_scout" },
        }
    end
    state.pendingIntel[#state.pendingIntel + 1] = {
        intelId = tostring(contract.eventId),
        text = tostring(contract.intelText or ""),
        rivalName = tostring(contract.rivalName or ""),
        createdAtRace = currentRaceCount(career),
        expiresAtRace = currentRaceCount(career) + Archetypes.INTEL_EXPIRY_RACES,
    }
    contract.status = "accepted"
    updateEventStatus(state, contract.eventId, "resolved", currentRaceCount(career), "intel_accepted")
    saveCareers()
    pruneState(career)
    saveCareers()
    return {
        ok = true,
        message = "Leak locked. Rico will carry it in the scout read until the window closes.",
        data = { contactId = "ncm_scout" },
    }
end

function ContactEvents.declineScoutContract(career)
    local state = pruneState(career)
    local contract = activeScoutContract(state)
    if not contract then
        return {
            ok = false,
            message = "No live leak on the line.",
            data = { contactId = "ncm_scout" },
        }
    end
    contract.status = "declined"
    updateEventStatus(state, contract.eventId, "declined", currentRaceCount(career), "intel_declined")
    saveCareers()
    pruneState(career)
    saveCareers()
    return {
        ok = true,
        message = "Lead burned. Rico killed the source and the trail's cold.",
        data = { contactId = "ncm_scout" },
    }
end

function ContactEvents.onOfferClaimed(career, data)
    if type(career) ~= "table" or type(data) ~= "table" then
        return nil
    end
    local state = pruneState(career)
    local contract = activeContractByOfferId(state, data.offerId)
    if not contract then
        return nil
    end
    contract.status = "claimed"
    updateEventStatus(state, contract.eventId, "claimed", currentRaceCount(career), "offer_claimed")
    saveCareers()
    pruneState(career)
    saveCareers()
    return true
end

function ContactEvents.onOfferExpired(career, data)
    if type(career) ~= "table" or type(data) ~= "table" then
        return nil
    end
    local state = pruneState(career)
    local contract = activeContractByOfferId(state, data.offerId)
    if not contract then
        return nil
    end
    contract.status = "expired"
    updateEventStatus(state, contract.eventId, "expired", currentRaceCount(career), "offer_expired")
    saveCareers()
    pruneState(career)
    saveCareers()
    return true
end

function ContactEvents.onRaceFinished(career, data)
    if type(career) ~= "table" or type(data) ~= "table" then
        return nil
    end
    local state = pruneState(career)
    if not state then return nil end
    local context = buildContext(career, data)
    local lossStreak = math.max(0, tonumber(context.stats and context.stats.lossStreak or 0) or 0)
    local winStreak = math.max(0, tonumber(context.stats and context.stats.winStreak or 0) or 0)
    local topHalf = (data.isDNF ~= true) and ((tonumber(data.position or 99) or 99) <= math.ceil(math.max(1, tonumber(data.results and #data.results or data.fieldSize or 1) or 1) * 0.5))
    if context.champPos and context.champPos <= 3 and context.rival and (tonumber(context.rival.rivalScore or 0) or 0) >= 12 then
        local heatWarning = buildRivalHeatWarning(career, state, context)
        if heatWarning then return heatWarning end
    end
    if context.rival and (((tonumber(context.rival.rivalScore or 0) or 0) >= 10) or ((tonumber(context.rival.headToHeadWins or 0) or 0) > 0)) then
        local intelContract = buildScoutIntelContract(career, state, context)
        if intelContract then return intelContract end
    end
    if context.rival and (((tonumber(context.rival.rivalScore or 0) or 0) >= 10) or ((tonumber(context.rival.headToHeadWins or 0) or 0) > 0)) then
        local leak = buildRivalLeak(career, state, context)
        if leak then return leak end
    end
    if lossStreak >= 2 and context.weakestLabel then
        local warning = buildCrewWarning(career, state, context)
        if warning then return warning end
        local contract = buildSetupContract(career, state, context, {
            archetypeId = "tuner_setup_contract",
            slot = context.weakestSlot,
            minimumRarity = currentSeasonPosition(career) and "Street" or nil,
            lines = {
                formatTemplate("Stu here. You're still quick, but {weakness} is where the race keeps leaking out.", {
                    weakness = string.lower(tostring(context.weakestLabel or context.weakestSlot or "the weak phase")),
                }),
                formatTemplate("I can put together a focused {slot_label} contract and keep the rest of the car honest.", {
                    slot_label = string.lower(tostring(PartsData.SLOTS[context.weakestSlot or "handling"] and PartsData.SLOTS[context.weakestSlot or "handling"].label or context.weakestSlot or "setup")),
                }),
                "Hit 'Source me parts' and I lock it. Hit 'Tune it' and I let it die.",
            },
        })
        if contract then return contract end
        local counter = buildCounterOffer(career, state, context)
        if counter then return counter end
    end
    if topHalf and context.weakestLabel then
        local counter = buildCounterOffer(career, state, context)
        if counter then return counter end
    end
    if topHalf and ((context.raceCount + hashString(context.buildIdentity or "")) % 4 == 0) then
        local risky = buildRiskyDeal(career, state, context)
        if risky then return risky end
    end
    if winStreak >= 2 then
        local reflection = buildFanReflection(career, state, context)
        if reflection then return reflection end
    end
    return nil
end

function ContactEvents.onPrestigeChange(career, data)
    if type(career) ~= "table" or type(data) ~= "table" then
        return nil
    end
    if tostring(data.dir or "") ~= "up" then
        return nil
    end
    local state = pruneState(career)
    if not state then return nil end
    local context = buildContext(career, data)
    local flavor = promotionContractFlavor(tostring(data.to or career.tier or "Streetkid"))
    local contract = buildSetupContract(career, state, context, {
        archetypeId = flavor.archetypeId,
        slot = flavor.slot,
        minimumRarity = tostring(data.to or career.tier or "Streetkid") == "Edgerunner" and "Elite" or "Pro",
        requiresTradeoff = tostring(data.to or career.tier or "") == "Edgerunner",
        title = i18n.format("Promotion Contract: %s", tostring(data.to or career.tier or "Next Tier")),
        subtitle = i18n.format("A setup package tuned for %s-tier pressure.", string.lower(tostring(data.to or career.tier or "next"))),
        lines = {
            "Stu. New tier, new room.",
            tostring(flavor.opener),
            tostring(flavor.closer),
        },
    })
    if contract then
        return contract
    end
    return buildCounterOffer(career, state, context)
end

return ContactEvents



