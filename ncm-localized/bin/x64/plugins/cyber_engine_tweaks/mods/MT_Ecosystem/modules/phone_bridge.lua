-- ============================================================
-- MT_Ecosystem: modules/phone_bridge.lua
-- Polls Redscript phone-choice facts and routes them through the
-- shared race command surface. The actual SMS contact is supplied
-- by the ArchiveXL journal resource; this module is the Lua half.
-- ============================================================

local PhoneBridge = {}
local i18n = require("modules/i18n")

local RaceCommands = require("modules/race_commands")

local DEBUG_POLL_INTERVAL = 0.25

local state = {
    initialized = false,
    timer = 0.0,
    lastSeq = 0,
    lastCommandId = 0,
    lastContactId = "ncm_motorsports",
    debugSeenSeq = 0,
    debugPressSeq = 0,
    lastMessage = "",
    introTimer = 0.0,
    introRetries = 0,
    introQueued = false,
    introDoneThisSession = false,
    runtimeFactSyncFailed = false,
}

local function enabled()
    local cfg = MTE and MTE.Settings and MTE.Settings.current or {}
    return cfg.phoneRaceManagement ~= false
end

local function quests()
    local qs = nil
    pcall(function() qs = Game.GetQuestsSystem() end)
    return qs
end

local function getFact(name)
    local qs = quests()
    if not qs then return 0 end
    local ok, value = pcall(function()
        return qs:GetFactStr(name)
    end)
    if ok and value ~= nil then
        return tonumber(value) or 0
    end
    ok, value = pcall(function()
        return qs:GetFact(name)
    end)
    if ok and value ~= nil then
        return tonumber(value) or 0
    end
    return 0
end

local function setFact(name, value)
    local qs = quests()
    if not qs then return false end
    local ok = pcall(function()
        qs:SetFactStr(name, tonumber(value) or 0)
    end)
    if ok then return true end
    ok = pcall(function()
        qs:SetFact(name, tonumber(value) or 0)
    end)
    return ok == true
end

local RACE_STATE_NUM = {
    idle = 0,
    config = 1,
    prerace = 2,
    quali = 3,
    countdown = 4,
    racing = 5,
    results = 6,
}

local function activeCareer()
    return MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active() or nil
end

local function activeCareerStats(career)
    local target = career or activeCareer()
    if not target then
        return nil
    end
    if MTE and MTE.Careers and MTE.Careers.getStats then
        local ok, stats = pcall(MTE.Careers.getStats, target)
        if ok and type(stats) == "table" then
            return stats
        end
    end
    return type(target.stats) == "table" and target.stats or nil
end

local function activeChampStanding(career)
    local target = career or activeCareer()
    if not target or not (MTE and MTE.Championships) then
        return nil, nil
    end
    local championships = MTE.Championships
    local season = nil
    local ok, result = pcall(function()
        return championships.activeSeason and championships.activeSeason(target) or nil
    end)
    if ok then
        season = result
    end
    if type(season) ~= "table" or not championships.driverStandings then
        return nil, nil
    end
    ok, result = pcall(function()
        return championships.driverStandings(season) or {}
    end)
    if not ok or type(result) ~= "table" then
        return nil, nil
    end
    local standings = result
    for index, row in ipairs(standings) do
        if tostring(row.driverId or "") == "player" then
            return index, tonumber(row.points or 0) or 0
        end
    end
    return nil, nil
end

local function currentFinishPosition()
    local racing = MTE and MTE.Racing or nil
    if not racing then
        return 0
    end
    local results = nil
    local ok = pcall(function()
        results = racing._results
    end)
    if not ok then
        return 0
    end
    if type(results) ~= "table" then
        return 0
    end
    for index, result in ipairs(results) do
        local driverId = tostring(result and (result.driverId or result.id) or "")
        if driverId == "player" then
            return tonumber(result.position or result.finishPos or index) or 0
        end
    end
    return 0
end

local function syncRuntimeFacts()
    local racing = MTE and MTE.Racing or nil
    local raceState = racing and racing.getState and racing.getState() or (racing and racing._state) or "idle"
    setFact("ncm_race_state", RACE_STATE_NUM[tostring(raceState or "idle")] or 0)
    setFact("ncm_race_active", (raceState ~= "idle" and raceState ~= "config") and 1 or 0)

    local career = activeCareer()
    local stats = activeCareerStats(career)
    local champPos, champPoints = activeChampStanding(career)

    setFact("ncm_finish_pos", currentFinishPosition())
    setFact("ncm_champ_pos", tonumber(champPos or 0) or 0)
    setFact("ncm_total_wins", tonumber(stats and stats.wins or 0) or 0)
    setFact("ncm_total_races", tonumber(stats and stats.racesFinished or stats and stats.racesRun or 0) or 0)
    setFact("ncm_champ_points", tonumber(champPoints or 0) or 0)
    setFact("ncm_phone_dces_contract_active", (MTE and MTE.ContactEvents and MTE.ContactEvents.hasSetupPhoneContract and MTE.ContactEvents.hasSetupPhoneContract(career)) and 1 or 0)
    setFact("ncm_phone_dces_scout_contract_active", (MTE and MTE.ContactEvents and MTE.ContactEvents.hasScoutPhoneContract and MTE.ContactEvents.hasScoutPhoneContract(career)) and 1 or 0)
end

local function trySyncRuntimeFacts()
    local ok, err = pcall(syncRuntimeFacts)
    if not ok then
        if not state.runtimeFactSyncFailed then
            state.runtimeFactSyncFailed = true
            print("[NCM/PhoneBridge] runtime fact sync failed: " .. tostring(err))
        end
        return false
    end
    state.runtimeFactSyncFailed = false
    return true
end

local function nextResponseSeq()
    local seq = getFact("ncm_phone_response_seq") + 1
    if seq <= 0 then
        seq = 1
    end
    setFact("ncm_phone_response_seq", seq)
    return seq
end

local function pollDebugFacts()
    local seenSeq = getFact("ncm_phone_debug_seen_seq")
    if seenSeq ~= state.debugSeenSeq then
        state.debugSeenSeq = seenSeq
        print(i18n.format(
            "[NCM/PhoneBridge] debug seen seq=%d cmd=%d route=%d",
            tonumber(seenSeq or 0),
            tonumber(getFact("ncm_phone_debug_last_cmd") or 0),
            tonumber(getFact("ncm_phone_debug_last_route") or 0)
        ))
    end

    local pressSeq = getFact("ncm_phone_debug_press_seq")
    if pressSeq ~= state.debugPressSeq then
        state.debugPressSeq = pressSeq
        print(i18n.format(
            "[NCM/PhoneBridge] debug press seq=%d cmd=%d route=%d",
            tonumber(pressSeq or 0),
            tonumber(getFact("ncm_phone_debug_last_cmd") or 0),
            tonumber(getFact("ncm_phone_debug_last_route") or 0)
        ))
    end
end

local function decodeRouteContact(routeCode)
    local code = tonumber(routeCode) or 0
    if code == 1 then return "ncm_motorsports" end
    if code == 2 then return "ncm_quickie" end
    if code == 3 then return "ncm_setup_stu" end
    if code == 4 then return "ncm_control" end
    if code == 5 then return "ncm_ledger" end
    if code == 6 then return "ncm_scout" end
    if code == 7 then return "ncm_bookie" end
    return ""
end

local function queueResponse(seq, result, commandId, explicitContactId)
    local message = i18n.source(result and result.message or "")
    local data = result and result.data or nil
    local responseSeq = nextResponseSeq()
    local contactId = type(explicitContactId) == "string" and explicitContactId or ""
    if contactId == "" then
        contactId = data and tostring(data.contactId or "") or ""
    end
    if contactId == "" then
        contactId = tostring(state.lastContactId or "")
    end
    if contactId == "" and RaceCommands and RaceCommands.responseContactId then
        contactId = tostring(RaceCommands.responseContactId(commandId) or "")
    end
    state.lastMessage = message
    setFact("ncm_phone_last_result", result and result.ok and 1 or 0)
    setFact("ncm_phone_last_processed_seq", seq or 0)

    if data and data.suppressPhoneResponse == true then
        return
    end

    pcall(function()
        local evt = MTEPhoneResponseEvent.new()
        evt.seq = tonumber(responseSeq or 0)
        evt.ok = result and result.ok == true
        evt.message = message
        evt.builderStep = tonumber(data and data.builderStep or -1) or -1
        evt.returnToControlBoard = data and data.returnToControlBoard == true
        evt.contactId = contactId
        Game.GetUISystem():QueueEvent(evt)
    end)
end

local function saveSettings()
    if MTE and MTE.Settings and MTE.Settings.save then
        pcall(MTE.Settings.save)
    end
end

local function queueIntroPing()
    local ok, err = pcall(function()
        local evt = MTESendSMSEvent.new()
        evt.messageType = 1
        Game.GetUISystem():QueueEvent(evt)
    end)
    if not ok then
        print("[NCM/PhoneBridge] intro ping failed: " .. tostring(err))
        return false
    end
    print("[NCM/PhoneBridge] intro ping queued")
    return true
end

local function shouldSendIntroPing()
    local cfg = MTE and MTE.Settings and MTE.Settings.current or {}
    if not enabled() or cfg.phoneIntroPingSent == true or state.introDoneThisSession == true then
        return false
    end

    local player = nil
    pcall(function()
        player = Game.GetPlayer()
    end)
    if not player then
        return false
    end

    if getFact("ncm_phone_contact_loaded") ~= 1 then
        return false
    end

    return true
end

local function markIntroPingAccepted()
    state.introDoneThisSession = true
    state.introQueued = false
    print("[NCM/PhoneBridge] intro ping accepted by Redscript")
end

local function resetBridgeState()
    state.initialized = true
    state.timer = 0.0
    state.lastSeq = getFact("ncm_phone_cmd_seq")
    state.lastCommandId = getFact("ncm_phone_cmd_id")
    state.lastContactId = decodeRouteContact(getFact("ncm_phone_cmd_route"))
    if state.lastContactId == "" then
        state.lastContactId = "ncm_motorsports"
    end
    state.debugSeenSeq = getFact("ncm_phone_debug_seen_seq")
    state.debugPressSeq = getFact("ncm_phone_debug_press_seq")
    state.lastMessage = ""
    state.introTimer = 1.0
    state.introRetries = 0
    state.introQueued = false
    state.introDoneThisSession = false
    if RaceCommands and RaceCommands.resetPhoneState then
        pcall(RaceCommands.resetPhoneState)
    end
    setFact("ncm_phone_bridge_ready", 1)
end

function PhoneBridge.init()
    resetBridgeState()
    print(i18n.format("[NCM/PhoneBridge] Ready. initialSeq=%d enabled=%s",
        tonumber(state.lastSeq or 0),
        tostring(enabled())))
end

function PhoneBridge.update(dt)
    if not state.initialized then
        PhoneBridge.init()
    end
    if not enabled() then return end

    if getFact("ncm_phone_bridge_ready") == 0 or getFact("ncm_phone_cmd_seq") < (tonumber(state.lastSeq) or 0) then
        resetBridgeState()
        print(i18n.format("[NCM/PhoneBridge] Session reset detected. seq=%d",
            tonumber(state.lastSeq or 0)))
    end

    local delta = tonumber(dt) or 0
    trySyncRuntimeFacts()

    if shouldSendIntroPing() then
        if getFact("ncm_phone_intro_pinged") == 1 then
            markIntroPingAccepted()
        else
            state.introTimer = state.introTimer - delta
            if state.introTimer <= 0.0 then
                state.introRetries = state.introRetries + 1
                if queueIntroPing() then
                    state.introQueued = true
                    state.introTimer = 2.0
                elseif state.introRetries < 8 then
                    state.introTimer = 2.0
                else
                    state.introDoneThisSession = true
                end
            end
        end
    end

    local seq = getFact("ncm_phone_cmd_seq")
    state.timer = state.timer + delta
    if state.timer >= DEBUG_POLL_INTERVAL then
        state.timer = 0.0
        pollDebugFacts()
    end

    if RaceCommands and RaceCommands.update then
        local deferredOk, deferred = pcall(RaceCommands.update)
        if deferredOk and deferred and deferred.result then
            queueResponse(deferred.seq, deferred.result, deferred.commandId or state.lastCommandId, state.lastContactId)
        elseif not deferredOk then
            local message = "Deferred phone command failed: " .. tostring(deferred)
            RaceCommands.notify(message, 5.0)
            queueResponse(seq, {
                ok = false,
                message = message,
            }, state.lastCommandId, state.lastContactId)
        end
    end

    if seq <= 0 or seq == state.lastSeq then return end

    local commandId = getFact("ncm_phone_cmd_id")
    local routeContactId = decodeRouteContact(getFact("ncm_phone_cmd_route"))
    state.lastSeq = seq
    state.lastCommandId = commandId
    if routeContactId ~= "" then
        state.lastContactId = routeContactId
    end
    local cfg = MTE and MTE.Settings and MTE.Settings.current or {}
    if cfg.phoneIntroPingSent ~= true then
        cfg.phoneIntroPingSent = true
        saveSettings()
    end

    print(i18n.format("[NCM/PhoneBridge] command seq=%d id=%d (%s)",
        tonumber(seq or 0),
        tonumber(commandId or 0),
        RaceCommands.commandName(commandId)))

    local ok, result = pcall(RaceCommands.execute, commandId)
    if not ok then
        result = {
            ok = false,
            message = "Phone command failed: " .. tostring(result),
        }
        RaceCommands.notify(result.message, 5.0)
    end
    if result and result.data and result.data.deferPhoneResponse == true and RaceCommands and RaceCommands.bindDeferredPhoneSeq then
        RaceCommands.bindDeferredPhoneSeq(seq)
        return
    end

    queueResponse(seq, result, commandId, state.lastContactId)
end

function PhoneBridge.handleCommand(commandId)
    local result = RaceCommands.execute(commandId)
    queueResponse((state.lastSeq or 0) + 1, result, commandId, state.lastContactId)
    return result
end

function PhoneBridge.requestIntroPing(force)
    if not force and not shouldSendIntroPing() then
        return false
    end
    local ok = queueIntroPing()
    if ok then
        state.introDoneThisSession = true
        state.introQueued = true
    end
    return ok
end

function PhoneBridge.resetIntroPing()
    local cfg = MTE and MTE.Settings and MTE.Settings.current or {}
    cfg.phoneIntroPingSent = false
    state.introDoneThisSession = false
    state.introRetries = 0
    state.introQueued = false
    state.introTimer = 0.1
    saveSettings()
end

function PhoneBridge.lastMessage()
    return state.lastMessage
end

return PhoneBridge



