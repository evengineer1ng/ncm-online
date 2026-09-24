-- ============================================================
-- MT_Ecosystem: modules/event_listeners.lua
-- Wires gameplay events to in-game notifications & sounds.
-- Called once from init.lua after all modules are loaded.
-- ============================================================

local EL = {}
local RaceCommands = require("modules/race_commands")

local RICO_RESULT_PUSH_CHANCE = 0.55
local FAN_RESULT_PUSH_CHANCE = 0.40
local CONTACT_PUSH_DEDUPE_SECONDS = 180

local ricoPushState = {
    lastPreviewRouteId = nil,
    lastPreviewAt = 0,
    lastResultSessionId = nil,
    lastWorldPushAt = 0,
    lastWorldKey = nil,
    leaderboardTopByTier = {},
}

local contactPushState = {}

-- ── Helper: show a brief on-screen message ────────────────────
local function notify(msg, duration)
    pcall(function()
        local gs = GetGameInstance()
        local uiSys = Game.GetUISystem()
        if uiSys then
            local evt = SimpleScreenMessage.new()
            evt.message     = msg
            evt.duration    = duration or 3.0
            evt.isShown     = true
            uiSys:QueueEvent(evt)
        end
    end)
end

-- ── Helper: play a UI sound event ─────────────────────────────
local function playSound(name)
    pcall(function()
        local p = Game.GetPlayer()
        if p then
            GameObject.PlaySoundEvent(p, name)
        end
    end)
end

local function formatTime(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return "--:--.--" end
    local minutes = math.floor(seconds / 60)
    local remaining = seconds - (minutes * 60)
    return string.format("%d:%05.2f", minutes, remaining)
end

local function quests()
    local qs = nil
    pcall(function()
        qs = Game.GetQuestsSystem()
    end)
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

local function nextPhoneResponseSeq()
    local seq = getFact("ncm_phone_response_seq") + 1
    if seq <= 0 then
        seq = 1
    end
    setFact("ncm_phone_response_seq", seq)
    return seq
end

local function queueContactMessage(contactId, message)
    if type(contactId) ~= "string" or contactId == "" or type(message) ~= "string" or message == "" then
        return false
    end

    local now = tonumber(os.time() or 0) or 0
    local last = contactPushState[contactId]
    if type(last) == "table"
        and last.message == message
        and (now - (tonumber(last.at) or 0)) < CONTACT_PUSH_DEDUPE_SECONDS then
        return false
    end

    local ok = pcall(function()
        local uiSys = Game.GetUISystem()
        if not uiSys then
            return
        end
        local evt = MTEPhoneResponseEvent.new()
        evt.seq = nextPhoneResponseSeq()
        evt.ok = true
        evt.message = message
        evt.builderStep = -1
        evt.returnToControlBoard = false
        evt.contactId = contactId
        uiSys:QueueEvent(evt)
    end)
    if ok == true then
        contactPushState[contactId] = {
            message = message,
            at = now,
        }
    end
    return ok == true
end

local function queueRicoScoutMessage(message)
    return queueContactMessage("ncm_scout", message)
end

local function queueFanLedgerMessage(message)
    return queueContactMessage("ncm_ledger", message)
end

local function queueSetupMessage(message)
    return queueContactMessage("ncm_setup_stu", message)
end

local function shouldSendRacePush(chance)
    local value = tonumber(chance)
    if not value or value <= 0 then
        return false
    end
    if value >= 1 then
        return true
    end
    return math.random() <= value
end

local function ricoTierKey(career)
    return tostring(career and career.tier or "")
end

local function updateRicoLeaderboardSnapshot(career)
    local tierKey = ricoTierKey(career)
    if tierKey == "" or not (RaceCommands and RaceCommands.scoutLeaderboardTopIds) then
        return {}
    end
    local ids = RaceCommands.scoutLeaderboardTopIds(career, 3) or {}
    ricoPushState.leaderboardTopByTier[tierKey] = ids
    return ids
end

local function queueRicoWorldMessage(message, worldKey, minInterval)
    if type(message) ~= "string" or message == "" then
        return false
    end

    local now = tonumber(os.time() or 0) or 0
    local interval = tonumber(minInterval) or 240
    if (now - (ricoPushState.lastWorldPushAt or 0)) < interval then
        return false
    end
    if type(worldKey) == "string" and worldKey ~= "" and ricoPushState.lastWorldKey == worldKey then
        return false
    end
    if queueRicoScoutMessage(message) then
        ricoPushState.lastWorldPushAt = now
        ricoPushState.lastWorldKey = worldKey
        return true
    end
    return false
end

-- ── Init: register all listeners ──────────────────────────────
function EL.init()
    local E = MTE.Events

    -- ── Race lifecycle ──────────────────────────────────────

    E.on("RacePreview", function(data)
        local cfg    = data.config or {}
        local dist   = cfg.distance or 0
        local nField = #(data.field or {})
        local career = MTE.Careers and MTE.Careers.active()
        local season = career and MTE.Championships and
                       MTE.Championships.activeSeason(career)

        -- Build an in-world event card shown on screen when the grid forms.
        local lines = {}

        if season and not season.completed then
            -- Championship header: round + district
            local district = (cfg.district or "?"):upper()
            lines[1] = string.format("ROUND %d / %d  --  %s",
                season.currentRound, season.totalRounds, district)
            -- V's team
            local teamName = (career.playerFactionName or "Independent"):sub(1, 20)
            lines[2] = string.format("Team: %s", teamName)
            -- V's current standings position
            local sTable = MTE.Championships.driverStandings(season)
            local champPos = nil
            for i, ds in ipairs(sTable) do
                if ds.driverId == "player" then champPos = i; break end
            end
            if champPos then
                lines[3] = string.format("Standings: P%d of %d  |  %d drivers",
                    champPos, #sTable, nField)
            else
                lines[3] = string.format("%d rivals  /  %.0fm", nField, dist)
            end
        else
            -- No active championship: basic grid forming message
            local district = (cfg.district or "?"):upper()
            lines[1] = string.format("RACE STAGING  --  %s", district)
            lines[2] = string.format("%d rivals  /  %.0fm", nField, dist)
        end

        -- Stakes flag (from race config or draft)
        if cfg.allowStakes then
            lines[#lines + 1] = "Stakes: enabled"
        end

        -- Nearest rival in the field (highest rivalScore)
        local topRival = nil
        for _, d in ipairs(data.field or {}) do
            if (d.rivalScore or 0) > 0 then
                if not topRival or d.rivalScore > topRival.rivalScore then
                    topRival = d
                end
            end
        end
        if topRival then
            lines[#lines + 1] = string.format("Rival: %s",
                topRival.displayName or topRival.name or "?")
        end

        local msg = table.concat(lines, "\n")
        notify(msg, 5.0)
        print(string.format("[NCM] Race preview: %s start, %.0fm, %d drivers",
            cfg.startType or "?", dist, nField))

        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            local routeId = tostring(cfg.routeId or cfg.trackName or "")
            local now = os.time()
            if routeId ~= "" and ricoPushState.lastPreviewRouteId == routeId and (now - (ricoPushState.lastPreviewAt or 0)) < 180 then
                return
            end
            local ricoMsg = RaceCommands and RaceCommands.scoutPreviewPushText and RaceCommands.scoutPreviewPushText(career, data) or nil
            if ricoMsg and ricoMsg ~= "" and queueRicoScoutMessage(ricoMsg) then
                ricoPushState.lastPreviewRouteId = routeId ~= "" and routeId or ricoPushState.lastPreviewRouteId
                ricoPushState.lastPreviewAt = now
            end
        end)
    end)

    E.on("RaceStart", function(data)
        -- Avoid forcing quest-like GPS tracking/UI state on race start.
        print("[NCM] Race started!")
        playSound("ui_menu_onpress")
    end)

    E.on("GridReady", function(data)
        if data and data.liveRivalsDeferred then
            print("[NCM] Start set - visible rivals deferred until after launch.")
            return
        end
        notify("GRID READY  --  TAKE YOUR POSITION", 4.0)
        playSound("ui_menu_onpress")
        print("[NCM] Grid ready.")
    end)

    E.on("RaceCountdown", function(data)
        print(string.format("[NCM] Countdown: %ds", data.seconds or 3))
    end)

    E.on("QualiStart", function(data)
        notify("QUALIFYING - SET YOUR FASTEST LAP", 4.0)
        print("[NCM] Qualifying started.")
    end)

    E.on("QualiEnd", function(data)
        local msg = string.format("QUALI: %.2fs  Grid P%d",
            data.playerTime or 0, data.gridPos or 1)
        notify(msg, 5.0)
        playSound("ui_jingle_quest_success")
        print("[NCM] " .. msg)
    end)

    -- RaceFinished: sound + native result card
    E.on("RaceFinished", function(data)
        if data.isDNF then
            playSound("ui_jingle_quest_failed")
        else
            playSound("ui_jingle_quest_success")
        end

        -- Fire native result card via InkHUD controller (or UISystem fallback)
        pcall(function()
            local uiSys = Game.GetUISystem()
            if not uiSys then return end

            local evt = MTERaceResultEvent.new()
            evt.position   = data.position or 1
            evt.fieldSize  = data.results and #data.results or 1
            evt.isDNF      = data.isDNF or false
            evt.payout     = data.payout or 0
            evt.repGain    = data.repGain or 0
            evt.isClean    = data.isClean or false

            -- Format race time as M:SS.mmm
            if data.playerTime and not data.isDNF then
                local s  = math.floor(data.playerTime)
                local ms = math.floor((data.playerTime - s) * 1000)
                evt.timeStr = string.format("%d:%02d.%03d",
                    math.floor(s / 60), s % 60, ms)
            else
                evt.timeStr = "DNF"
            end

            -- Wager outcome
            if data.wagerWon then
                evt.wagerResult = "WON"
            elseif data.wagerLost then
                evt.wagerResult = "LOST"
            else
                evt.wagerResult = ""
            end

            evt.bountyText = ""

            -- Drag straightness penalty
            evt.dragPenaltyText = ""
            pcall(function()
                local ds = data.dragStrip
                if ds and ds.straightnessSummary and ds.straightnessSummary ~= "" then
                    evt.dragPenaltyText = ds.straightnessSummary
                end
            end)

            -- Championship context on result card (replaces empty bountyText).
            -- By the time RaceFinished fires, recordResult has already updated
            -- standings, so we read the current (post-race) position.
            pcall(function()
                local career = MTE.Careers and MTE.Careers.active()
                local season = career and MTE.Championships and
                               MTE.Championships.activeSeason(career)
                if season then
                    local sTable = MTE.Championships.driverStandings(season)
                    local champPos = nil
                    local champPts = 0
                    for i, ds in ipairs(sTable) do
                        if ds.driverId == "player" then
                            champPos = i; champPts = ds.points or 0; break
                        end
                    end
                    if champPos then
                        evt.bountyText = string.format(
                            "Champ: P%d  |  %d pts  |  Rd %d/%d",
                            champPos, champPts,
                            season.currentRound, season.totalRounds)
                    end
                end
            end)

            -- Prefer direct controller call; fall back to QueueEvent
            local ctrl = MTE.InkHUD and MTE.InkHUD.controller
            if ctrl then
                ctrl:MTEShowResult(evt)
            else
                uiSys:QueueEvent(evt)
            end
        end)

        pcall(function()
            local ladder = data.seasonAccount
            if type(ladder) ~= "table" then return end

            local uiSys = Game.GetUISystem()
            if not uiSys then return end

            local evt = MTESeasonLadderEvent.new()
            evt.direction = tostring(ladder.direction or "flat")
            evt.title = tostring(ladder.title or "SEASON ACCOUNT")
            evt.summary = tostring(ladder.summary or "")
            evt.movementText = tostring(ladder.movementText or "")
            evt.ladderText = tostring(ladder.ladderText or "")
            evt.footerText = tostring(ladder.footerText or "")

            local ctrl = MTE.InkHUD and MTE.InkHUD.controller
            if ctrl and ctrl.MTEQueueSeasonLadder then
                ctrl:MTEQueueSeasonLadder(evt)
            else
                uiSys:QueueEvent(evt)
            end
        end)

        -- Post-race championship toast chain.
        -- Queue these AFTER the result card so they appear as follow-ups.
        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            local season = career and MTE.Championships and
                           MTE.Championships.activeSeason(career)
            if not season then return end

            local sTable = MTE.Championships.driverStandings(season)
            local champPos = nil
            local champPts = 0
            for i, ds in ipairs(sTable) do
                if ds.driverId == "player" then
                    champPos = i; champPts = ds.points or 0; break
                end
            end
            if not champPos then return end

            -- Standings line
            notify(string.format("CHAMPIONSHIP: P%d  |  %d pts  |  Rd %d/%d",
                champPos, champPts,
                season.currentRound, season.totalRounds), 4.0)

            -- Team / faction standings
            local teamName = career.playerFactionName or "Independent"
            if career.playerFactionMode ~= "independent" then
                local fTable = MTE.Championships.factionStandings(season)
                for i, fs in ipairs(fTable) do
                    if fs.factionId == career.playerFactionId then
                        notify(string.format("Team %s: P%d  |  %d pts",
                            teamName:sub(1, 18), i, fs.points or 0), 4.0)
                        break
                    end
                end
            end

            -- Championship rival callout when V is close to P1
            if champPos <= 3 and champPos > 1 then
                local leader = sTable[1]
                if leader and leader.driverId ~= "player" then
                    local gap = (leader.points or 0) - champPts
                    notify(string.format("%s leads by %d pts",
                        (leader.driverName or "?"):sub(1, 20), gap), 4.0)
                end
            end
        end)

        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            local sessionId = tostring(data.sessionId or "")
            if sessionId ~= "" and ricoPushState.lastResultSessionId == sessionId then
                return
            end
            if sessionId ~= "" then
                ricoPushState.lastResultSessionId = sessionId
            end
            local ricoMsg = RaceCommands and RaceCommands.scoutResultPushText and RaceCommands.scoutResultPushText(career, data) or nil
            if ricoMsg and ricoMsg ~= "" and shouldSendRacePush(RICO_RESULT_PUSH_CHANCE) then
                queueRicoScoutMessage(ricoMsg)
            end
            local fanMsg = MTE and MTE.FanEngine and MTE.FanEngine.onRaceFinished and MTE.FanEngine.onRaceFinished(career, data) or nil
            if fanMsg and fanMsg ~= "" and shouldSendRacePush(FAN_RESULT_PUSH_CHANCE) then
                queueFanLedgerMessage(fanMsg)
            end
            local offer = MTE and MTE.Parts and MTE.Parts.onRaceFinished and MTE.Parts.onRaceFinished(career, {
                position = data.position,
                fieldSize = data.results and #data.results or data.fieldSize,
                dnf = data.isDNF == true,
                raceType = data.raceType,
                routeId = data.routeId,
                trackName = data.trackName,
                sessionId = sessionId,
            }) or nil
            if offer and offer.title then
                notify(string.format("NEW OFFER  --  %s", tostring(offer.title)), 5.0)
            end
            local contactEvent = MTE and MTE.ContactEvents and MTE.ContactEvents.onRaceFinished and MTE.ContactEvents.onRaceFinished(career, data) or nil
            if contactEvent and contactEvent.archetype then
                notify("NEW LEAD  --  Check your phone.", 4.0)
            end
            updateRicoLeaderboardSnapshot(career)
        end)
    end)

    E.on("WagerLost", function(data)
        local msg = string.format("WAGER LOST: -%d eddies", data.amount or 0)
        notify(msg, 5.0)
        playSound("ui_jingle_quest_failed")
        print("[NCM] " .. msg)
    end)

    -- ── Championship / season ──────────────────────────────

    -- Fired by Championships.applySeasonConfig when a new round is opened
    -- for the first time in a session.  Gives a dispatcher-style callout.
    E.on("RoundReady", function(data)
        local round  = data.round  or 1
        local total  = data.total  or 1
        local dist   = (data.district or "?"):upper()
        local etype  = data.eventType or "sprint"
        local team   = (data.teamName or "Independent"):sub(1, 20)
        local msg    = string.format(
            "ROUND %d / %d  --  %s  --  %s\nTeam: %s",
            round, total, dist, etype:upper(), team)
        notify(msg, 6.0)
        playSound("ui_menu_onpress")
        print(string.format("[NCM/Championship] Round %d/%d ready: %s (%s)",
            round, total, dist, etype))

        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            local tierKey = ricoTierKey(career)
            local previousTop = ricoPushState.leaderboardTopByTier[tierKey] or {}
            local ricoMsg, ricoKey = nil, nil
            if RaceCommands and RaceCommands.scoutTrendPushText then
                ricoMsg, ricoKey = RaceCommands.scoutTrendPushText(career, previousTop)
            end
            queueRicoWorldMessage(ricoMsg, ricoKey, 240)
            updateRicoLeaderboardSnapshot(career)
        end)
    end)

    -- ── Career progression ──────────────────────────────────

    E.on("PrestigeChange", function(data)
        local dir = data.dir == "up" and "PROMOTED" or "RELEGATED"
        local msg = string.format("%s  --  %s -> %s", dir, data.from or "?", data.to or "?")
        notify(msg, 6.0)
        if data.dir == "up" then
            playSound("ui_jingle_quest_success")
        else
            playSound("ui_jingle_quest_failed")
        end
        print("[NCM/Career] " .. msg)

        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            local revealMsg = MTE and MTE.Careers and MTE.Careers.prestigeRevealText and MTE.Careers.prestigeRevealText(career, data) or nil
            if MTE and MTE.FanEngine and MTE.FanEngine.onPrestigeChange then
                MTE.FanEngine.onPrestigeChange(career, data)
            end
            local promotionOffer = MTE and MTE.Parts and MTE.Parts.onPrestigeChange and MTE.Parts.onPrestigeChange(career, data) or nil
            local ricoMsg = RaceCommands and RaceCommands.scoutTierChangePushText and RaceCommands.scoutTierChangePushText(career, data) or nil
            local uiSys = Game.GetUISystem and Game.GetUISystem() or nil
            if uiSys then
                local evt = MTEPrestigeRevealEvent.new()
                evt.direction = tostring(data.dir or "")
                evt.fromTier = tostring(data.from or "?")
                evt.toTier = tostring(data.to or "?")
                evt.title = string.format("%s TO %s", dir, tostring(data.to or "?"))
                evt.body = revealMsg and revealMsg ~= "" and revealMsg
                    or string.format("You crossed from %s into %s. The room changes with you immediately.", tostring(data.from or "the last tier"), tostring(data.to or "the next tier"))

                local ctrl = MTE.InkHUD and MTE.InkHUD.controller
                if ctrl and ctrl.MTEShowPrestigeReveal then
                    ctrl:MTEShowPrestigeReveal(evt)
                else
                    uiSys:QueueEvent(evt)
                end
            end
            local worldKey = string.format("tier:%s:%s", tostring(data.to or "?"), tostring(data.dir or "?"))
            if promotionOffer and promotionOffer.title then
                notify(string.format("CRATE READY  --  %s", tostring(promotionOffer.title)), 5.0)
            end
            local contactEvent = MTE and MTE.ContactEvents and MTE.ContactEvents.onPrestigeChange and MTE.ContactEvents.onPrestigeChange(career, data) or nil
            if contactEvent and contactEvent.archetype then
                notify("NEW LEAD  --  Check your phone.", 4.0)
            end
            queueRicoWorldMessage(ricoMsg, worldKey, 180)
            updateRicoLeaderboardSnapshot(career)
        end)
    end)

    E.on("ContactEventMessage", function(data)
        local contactId = tostring(data and data.contactId or "")
        local message = tostring(data and data.message or "")
        local delivered = false
        if contactId == "ncm_setup_stu" then
            delivered = queueSetupMessage(message)
        elseif contactId == "ncm_ledger" then
            delivered = queueFanLedgerMessage(message)
        else
            delivered = queueRicoScoutMessage(message)
        end
        if delivered and data and data.title then
            print(string.format("[NCM/DCES] Delivered contact event via %s: %s", contactId, tostring(data.title)))
        end
    end)

    E.on("PartOfferClaimed", function(data)
        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            if MTE and MTE.ContactEvents and MTE.ContactEvents.onOfferClaimed then
                MTE.ContactEvents.onOfferClaimed(career, data or {})
            end
        end)
    end)

    E.on("PartOfferExpired", function(data)
        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            if MTE and MTE.ContactEvents and MTE.ContactEvents.onOfferExpired then
                MTE.ContactEvents.onOfferExpired(career, data or {})
            end
        end)
    end)

    E.on("CatchUpBonus", function(data)
        local msg = string.format("CATCH-UP: +%d rep", data.amount or 0)
        notify(msg, 3.0)
        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            if MTE and MTE.FanEngine and MTE.FanEngine.onCatchUpBonus then
                MTE.FanEngine.onCatchUpBonus(career, data)
            end
        end)
    end)

    E.on("SeasonComplete", function(data)
        local repBonus = data.repBonus or 0
        local eddies   = data.eddies   or 0
        local msg = string.format("SEASON %d COMPLETE -- +%d rep, +%d eddies",
            data.season or 0, repBonus, eddies)
        notify(msg, 5.0)
        playSound("ui_jingle_quest_success")
        print("[NCM/Career] " .. msg)
    end)

    E.on("ChampionshipComplete", function(data)
        local pos    = data.champPos or 0
        local tier   = data.tier     or "?"
        local posStr = pos > 0 and string.format("P%d", pos) or "?"
        local msg    = string.format("CHAMPIONSHIP COMPLETE  --  %s  --  %s", tier, posStr)
        notify(msg, 8.0)
        if pos <= 3 then
            playSound("ui_jingle_quest_success")
        else
            playSound("ui_menu_onpress")
        end
        print("[NCM/Championship] " .. msg)
    end)

    -- ── Records ─────────────────────────────────────────────

    E.on("NewRecord", function(data)
        local msg = string.format("NEW RECORD! %.2fs", data.time or 0)
        notify(msg, 5.0)
        playSound("ui_jingle_quest_success")
        print("[NCM/Records] " .. msg)
        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            if MTE and MTE.FanEngine and MTE.FanEngine.onNewRecord then
                MTE.FanEngine.onNewRecord(career, data)
            end
        end)
    end)

    E.on("SessionBestSector", function(data)
        local msg = string.format("BEST S%d  %s",
            data.sectorNumber or 1,
            formatTime(data.sectorTime))
        notify(msg, 2.5)
        playSound("ui_menu_onpress")
        print("[NCM/Telemetry] " .. msg)
    end)

    E.on("RouteBestSector", function(data)
        local msg = string.format("PURPLE S%d  %s",
            data.sectorNumber or 1,
            formatTime(data.sectorTime))
        notify(msg, 3.0)
        playSound("ui_jingle_quest_success")
        print("[NCM/Telemetry] " .. msg)
    end)

    E.on("SessionBestLap", function(data)
        local msg = string.format("BEST LAP  %s", formatTime(data.lapTime))
        notify(msg, 3.0)
        playSound("ui_menu_onpress")
        print("[NCM/Telemetry] " .. msg)
    end)

    E.on("RouteBestLap", function(data)
        local msg = string.format("PURPLE LAP  %s", formatTime(data.lapTime))
        notify(msg, 4.0)
        playSound("ui_jingle_quest_success")
        print("[NCM/Telemetry] " .. msg)
    end)

    -- ── Driving events (metrics) ────────────────────────────
    -- These fire from metrics.lua logEvent → Events.emit.
    -- Light-touch: just log for now; could feed a notification ticker.

    E.on("ZeroToHundred", function(data)
        local d = data.data or {}
        print(string.format("[NCM/Metrics] 0-100: %.2fs", d.time or 0))
    end)

    E.on("HundredToZero", function(data)
        local d = data.data or {}
        print(string.format("[NCM/Metrics] 100-0: %.2fs", d.time or 0))
    end)

    E.on("HardBrake", function(data)
        -- silent; just consumed so the bus isn't empty
    end)

    E.on("AggressiveAccel", function(data)
        -- silent
    end)

    E.on("HighSpeedRun", function(data)
        -- silent
    end)

    E.on("SustainedCorner", function(data)
        -- silent
    end)

    E.on("CrashSpike", function(data)
        -- silent
    end)

    E.on("CleanRun", function(data)
        print("[NCM/Metrics] Clean run completed!")
        pcall(function()
            local career = MTE.Careers and MTE.Careers.active()
            if MTE and MTE.FanEngine and MTE.FanEngine.onCleanRun then
                MTE.FanEngine.onCleanRun(career, data)
            end
        end)
    end)

    print("[NCM/EventListeners] All event listeners registered.")
end

return EL
