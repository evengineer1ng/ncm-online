-- ============================================================
-- MT_Ecosystem: modules/ui_championships.lua
-- Championship standings, schedule, and team assignment UI.
-- Called from ui_racing.lua when the "Season" sub-tab is active.
-- ============================================================

local UICH = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end

-- Sub-tab state
local _tab       = 1
local _tabLabels = { "Season", "Drivers", "Factions", "Schedule", "Box Scores", "Team" }
local _boxTierFilter = "all"
local _boxPlayerOnly = false
local _boxPage = 1
local _boxSelectedId = nil
local _driverSelectedId = "player"

-- Scratch buffers for custom team entry
local _customNameBuf = { "" }

-- â”€â”€ Colour helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function rankColor(rank)
    if rank == 1 then return 1.0, 0.85, 0.10, 1 end
    if rank == 2 then return 0.80, 0.80, 0.80, 1 end
    if rank == 3 then return 0.80, 0.50, 0.20, 1 end
    return 0.70, 0.70, 0.70, 1
end

local function pushFactionColor(color)
    local c = color or { 0.75, 0.75, 0.75 }
    ImGui.PushStyleColor(ImGuiCol.Text, c[1], c[2], c[3], 1.0)
end

local function fmtPts(n)
    return tostring(n or 0)
end

local function fmtPos(n)
    return (n and n ~= 999) and tostring(n) or "--"
end

local function fmtDelta(n)
    local value = tonumber(n) or 0
    if value > 0 then
        return string.format("+%d", value)
    end
    return tostring(value)
end

local function fmtTime(seconds)
    local value = tonumber(seconds)
    if not value then return "--:--.--" end
    local minutes = math.floor(value / 60)
    local remaining = value - (minutes * 60)
    return string.format("%d:%04.1f", minutes, remaining)
end

local function fmtGap(seconds)
    local value = tonumber(seconds)
    if not value or value <= 0 then
        return "-"
    end
    return string.format("+%.1f", value)
end

local function fmtRelativeAge(timestamp)
    local age = math.max(0, (tonumber(os.time()) or 0) - (tonumber(timestamp) or 0))
    if age < 3600 then
        return string.format("%dm ago", math.max(1, math.floor(age / 60)))
    end
    if age < 86400 then
        return string.format("%dh ago", math.floor(age / 3600))
    end
    if age < 172800 then
        return "Yesterday"
    end
    return string.format("%dd ago", math.floor(age / 86400))
end

local function boxStateColor(label)
    if label == "Clean" then return 0.35, 0.85, 0.35, 1.0 end
    if label == "Volatile" then return 1.0, 0.55, 0.20, 1.0 end
    return 0.80, 0.80, 0.80, 1.0
end

local function participantFlagText(participant)
    local flags = participant and participant.flags or nil
    if type(flags) ~= "table" or #flags <= 0 then
        return nil
    end
    return table.concat(flags, ", ")
end

local function boxScoreTierOptions()
    return { "all", "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }
end

local function findStandingEntry(drivers, driverId)
    for index, driver in ipairs(drivers or {}) do
        if tostring(driver.driverId or "") == tostring(driverId or "") then
            return driver, index
        end
    end
    return nil, nil
end

local function recentFormText(driver)
    local finishes = driver and driver.recentFinishes or nil
    if type(finishes) ~= "table" or #finishes <= 0 then
        return "No recent race tape"
    end
    local parts = {}
    for _, finish in ipairs(finishes) do
        local pos = tonumber(finish) or 99
        parts[#parts + 1] = pos >= 99 and "DNF" or tostring(pos)
    end
    return table.concat(parts, ", ")
end

local function availabilityColor(status)
    if status == "active" then return 0.35, 0.85, 0.35, 1.0 end
    if status == "sidelined" then return 1.0, 0.60, 0.20, 1.0 end
    if status == "retired" then return 0.65, 0.65, 0.65, 1.0 end
    return 0.80, 0.80, 0.80, 1.0
end

local function openDriverProfile(driverId)
    if not driverId then
        return
    end
    _driverSelectedId = tostring(driverId)
    _tab = 2
end

local function drawDriverProfilePane(career, drivers)
    local selectedId = tostring(_driverSelectedId or "player")
    local standing, standingRank = findStandingEntry(drivers, selectedId)
    local rosterDriver = nil
    local displayName = "V"
    local factionName = career.playerFactionName or "Independent"
    local currentTier = career.tier or "?"
    local availability = "active"
    local worldEvent = nil

    if selectedId ~= "player" and MTE and MTE.Roster and MTE.Roster.findById then
        rosterDriver = MTE.Roster.findById(career, selectedId)
        if rosterDriver then
            displayName = rosterDriver.name or selectedId
            factionName = rosterDriver.factionName or rosterDriver.factionId or "Independent"
            currentTier = rosterDriver.currentTier or rosterDriver.tier or "?"
            availability = rosterDriver.availability or "active"
            worldEvent = rosterDriver.lastWorldEvent
        else
            displayName = selectedId
            availability = "unknown"
        end
    end

    ImGui.Text(displayName)
    ImGui.TextDisabled(string.format("Team: %s", tostring(factionName)))
    if standingRank then
        ImGui.Text(string.format("Championship rank: P%d", standingRank))
    else
        ImGui.TextDisabled("Outside the active championship standings")
    end

    local ar, ag, ab, aa = availabilityColor(tostring(availability))
    ImGui.PushStyleColor(ImGuiCol.Text, ar, ag, ab, aa)
    ImGui.Text(string.format("Availability: %s", tostring(availability)))
    ImGui.PopStyleColor()
    ImGui.Text(string.format("Current tier: %s", tostring(currentTier)))

    if selectedId == "player" then
        ImGui.Text(string.format("Career rep: %d", tonumber(career.rep or 0) or 0))
        if standing then
            ImGui.Text(string.format("Season points: %s  |  Wins: %d  |  Podiums: %d",
                fmtPts(standing.points),
                tonumber(standing.wins or 0) or 0,
                tonumber(standing.podiums or 0) or 0))
        end
        ImGui.Text(string.format("Mode: %s", tostring(career.playerFactionMode or "independent")))
        return
    end

    if not rosterDriver then
        ImGui.Spacing()
        ImGui.TextDisabled("Driver profile data unavailable.")
        return
    end

    ImGui.Text(string.format("Rep: %d  |  Wins: %d  |  Races: %d",
        tonumber(rosterDriver.rep or 0) or 0,
        tonumber(rosterDriver.wins or 0) or 0,
        tonumber(rosterDriver.racesRun or 0) or 0))
    if standing then
        ImGui.Text(string.format("Season points: %s  |  Podiums: %d  |  Best: %s",
            fmtPts(standing.points),
            tonumber(standing.podiums or 0) or 0,
            fmtPos(standing.bestFinish)))
    end
    ImGui.Text(string.format("Style: %s  |  Home: %s",
        tostring(rosterDriver.personality or "unknown"),
        tostring(rosterDriver.homeRegion or "?")))
    ImGui.Text(string.format("Vehicle: %s  |  Prestige P%d",
        tostring(rosterDriver.carClass or "unknown"),
        tonumber(rosterDriver.vehiclePrestige or 0) or 0))
    ImGui.Text(string.format("Pace %.2f  |  Precision %.2f  |  Consistency %.2f  |  Aggression %.2f",
        tonumber(rosterDriver.pace or 0.0) or 0.0,
        tonumber(rosterDriver.precision or 0.0) or 0.0,
        tonumber(rosterDriver.consistency or 0.0) or 0.0,
        tonumber(rosterDriver.aggression or 0.0) or 0.0))
    ImGui.Text(string.format("Recent form: %s", recentFormText(rosterDriver)))
    if rosterDriver.formTag and rosterDriver.formTag ~= "" then
        ImGui.Text(string.format("Trend: %s", tostring(rosterDriver.formTag)))
    end
    if worldEvent and worldEvent ~= "" then
        ImGui.Spacing()
        ImGui.TextWrapped(string.format("Latest note: %s", tostring(worldEvent)))
    end
end

-- â”€â”€ Public API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UICH.init()
    print("[NCM/UIChampionships] Initialised.")
end

function UICH.draw()
    local career = MTE.Careers and MTE.Careers.active()
    if not career then
        ImGui.TextDisabled("No active career.")
        return
    end

    if not MTE.Championships then
        ImGui.TextDisabled("Championship module not available.")
        return
    end

    -- Sub-tab bar
    for i, label in ipairs(_tabLabels) do
        if i > 1 then ImGui.SameLine() end
        local active = (_tab == i)
        if active then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1) end
        if ImGui.Button(label .. "##chtab" .. i, s(75), s(22)) then _tab = i end
        if active then ImGui.PopStyleColor() end
    end
    ImGui.Separator()

    if     _tab == 1 then UICH._drawSeasonTab(career)
    elseif _tab == 2 then UICH._drawDriversTab(career)
    elseif _tab == 3 then UICH._drawFactionsTab(career)
    elseif _tab == 4 then UICH._drawScheduleTab(career)
    elseif _tab == 5 then UICH._drawBoxScoresTab(career)
    elseif _tab == 6 then UICH._drawTeamTab(career)
    end
end

-- â”€â”€ Tab 1: Season overview â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UICH._drawSeasonTab(career)
    local season = MTE.Championships.activeSeason(career)
    if not season then
        ImGui.TextDisabled("No active season.")
        if ImGui.Button("Start New Season", s(160), s(24)) then
            MTE.Championships.startNewSeason(career)
        end
        return
    end

    local ruleset = season._ruleset or MTE.Championships.rulesetForTier(season.leagueTier)

    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.85, 0.10, 1.0)
    ImGui.Text(ruleset and ruleset.name or season.id)
    ImGui.PopStyleColor()
    ImGui.SameLine()
    ImGui.TextDisabled(string.format("  Season %d", season.seasonNumber))
    ImGui.Separator()

    ImGui.Text(string.format("Tier:    %s", season.leagueTier or "?"))
    ImGui.Text(string.format("Round:   %d / %d", season.currentRound, season.totalRounds))
    ImGui.Text(string.format("Status:  %s", season.completed and "Completed" or "In Progress"))
    ImGui.Spacing()

    -- V's current standings position
    local drivers    = MTE.Championships.driverStandings(season)
    local playerPos  = "--"
    local playerPts  = 0
    for _, ds in ipairs(drivers) do
        if ds.driverId == "player" then
            playerPos = tostring(ds._rank)
            playerPts = ds.points
            break
        end
    end

    -- V team coloured strip
    local fc = career.playerFactionColor or { 1, 1, 1 }
    ImGui.PushStyleColor(ImGuiCol.Text, fc[1], fc[2], fc[3], 1.0)
    ImGui.Text(string.format("Team:    %s  [%s]",
        career.playerFactionName or "Independent",
        career.playerFactionMode or "independent"))
    ImGui.PopStyleColor()
    ImGui.Text(string.format("Champ:   P%s  |  %s pts", playerPos, fmtPts(playerPts)))

    -- Top-5 driver mini-table
    if #drivers > 0 then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.TextDisabled("Standings (top 5):")
        for i = 1, math.min(5, #drivers) do
            local ds   = drivers[i]
            local r, g, b, a = rankColor(i)
            ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
            ImGui.Text(string.format("  P%-2d  %-20s  %s pts",
                i, (ds.driverName or ds.driverId):sub(1, 19), fmtPts(ds.points)))
            ImGui.PopStyleColor()
        end
    end
end

-- â”€â”€ Tab 2: Driver standings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UICH._drawDriversTab(career)
    local season = MTE.Championships.activeSeason(career)
    if not season then ImGui.TextDisabled("No active season."); return end

    local drivers = MTE.Championships.driverStandings(season)
    if #drivers == 0 then
        ImGui.TextDisabled("No race results yet this season.")
        return
    end

    local playerRank = nil
    local playerEntry = nil
    for i, ds in ipairs(drivers) do
        if ds.driverId == "player" then
            playerRank = i
            playerEntry = ds
            break
        end
    end

    if playerEntry then
        local fc = career.playerFactionColor or { 1.0, 0.93, 0.33 }
        ImGui.PushStyleColor(ImGuiCol.Text, fc[1], fc[2], fc[3], 1.0)
        ImGui.Text(string.format("V is P%d / %d   |   %s pts   |   %d wins   |   %d podiums",
            playerRank or 0,
            #drivers,
            fmtPts(playerEntry.points),
            playerEntry.wins or 0,
            playerEntry.podiums or 0))
        ImGui.PopStyleColor()
        ImGui.Separator()
    end

    if not _driverSelectedId then
        _driverSelectedId = playerEntry and "player" or (drivers[1] and drivers[1].driverId or "player")
    end

    local listWidth = s(480)
    if ImGui.BeginChild("##champDriverStandings", listWidth, s(320), true) then
        ImGui.TextDisabled(string.format("%-4s  %-20s  %-20s  %5s  %4s  %4s  %5s  %5s",
            "Pos", "Driver", "Team", "Pts", "W", "Pod", "Best", "Races"))
        ImGui.Separator()
        for i, ds in ipairs(drivers) do
            local isPlayer = (ds.driverId == "player")
            local fdef = MTE.Championships
                and MTE.Championships._resolveDisplayFaction(career, ds.factionId or "")
                or { name = ds.factionId or "?", color = { 0.70, 0.70, 0.70 } }
            local selectedRow = tostring(_driverSelectedId or "") == tostring(ds.driverId or "")
            if isPlayer then
                ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.93, 0.33, 1.0)
            else
                local fc = fdef.color or { 0.70, 0.70, 0.70 }
                ImGui.PushStyleColor(ImGuiCol.Text, fc[1], fc[2], fc[3], 1.0)
            end
            local marker = isPlayer and " >>" or ""
            local fShort = fdef.name or (ds.factionId or "?")
            if ImGui.Selectable(string.format("P%-3d  %-20s  %-20s  %5s  %4s  %4s  %5s  %5s##drv_%s",
                i,
                ((ds.driverName or ds.driverId) .. marker):sub(1, 20),
                fShort:sub(1, 20),
                fmtPts(ds.points),
                tostring(ds.wins    or 0),
                tostring(ds.podiums or 0),
                fmtPos(ds.bestFinish),
                tostring(ds.races   or 0),
                tostring(ds.driverId or i)), selectedRow) then
                _driverSelectedId = ds.driverId
            end
            ImGui.PopStyleColor()
        end
        ImGui.EndChild()
    end

    ImGui.SameLine()

    if ImGui.BeginChild("##champDriverProfile", 0, s(320), true) then
        drawDriverProfilePane(career, drivers)
        ImGui.EndChild()
    end
end

-- â”€â”€ Tab 3: Faction standings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UICH._drawFactionsTab(career)
    local season = MTE.Championships.activeSeason(career)
    if not season then ImGui.TextDisabled("No active season."); return end

    local factions = MTE.Championships.factionStandings(season)
    if #factions == 0 then
        ImGui.TextDisabled("No faction data yet this season.")
        return
    end

    ImGui.TextDisabled(string.format("%-4s  %-26s  %5s  %4s  %4s  %5s",
        "Pos", "Team", "Pts", "W", "Pod", "Races"))
    ImGui.Separator()

    for i, fs in ipairs(factions) do
        local isPlayerTeam = (fs.factionId == (career.playerFactionId or "independent"))
        local fc = fs.factionColor or { 0.70, 0.70, 0.70 }
        if isPlayerTeam then
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.93, 0.33, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Text, fc[1], fc[2], fc[3], 1.0)
        end
        local marker  = isPlayerTeam and " >>" or ""
        local dispName = ((fs.factionName or fs.factionId or "?") .. marker):sub(1, 27)
        ImGui.Text(string.format("P%-3d  %-26s  %5s  %4s  %4s  %5s",
            i, dispName,
            fmtPts(fs.points),
            tostring(fs.wins    or 0),
            tostring(fs.podiums or 0),
            tostring(fs.races   or 0)))
        ImGui.PopStyleColor()
    end
end

-- â”€â”€ Tab 4: Schedule â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UICH._drawScheduleTab(career)
    local season = MTE.Championships.activeSeason(career)
    if not season then ImGui.TextDisabled("No active season."); return end

    local schedule = season.schedule or {}
    ImGui.TextDisabled(string.format("%-5s  %-11s  %-20s  %-26s  %s",
        "Round", "Type", "Location", "Event", "Status"))
    ImGui.Separator()

    for _, rd in ipairs(schedule) do
        local isCurrent = (rd.round == season.currentRound) and not season.completed
        local eventType = rd.eventType or rd.raceType or "sprint"
        local locationLabel = rd.districtLabel or rd.district or "?"
        local titleLabel = rd.titleLabel or rd.trackName or locationLabel
        local subtitleLabel = rd.subtitleLabel
        local statusLabel = ""
        if rd.completed then
            statusLabel = "Done"
        elseif rd.isValid == false then
            statusLabel = "INVALID"
        elseif isCurrent then
            statusLabel = "<< Next"
        end

        if rd.completed then
            ImGui.TextDisabled(string.format("  %2d   %-11s  %-20s  %-26s  %s",
                rd.round, eventType, locationLabel, titleLabel:sub(1, 26), statusLabel))
        elseif rd.isValid == false then
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.35, 0.25, 1.0)
            ImGui.Text(string.format("  %2d   %-11s  %-20s  %-26s  %s",
                rd.round, eventType, locationLabel, titleLabel:sub(1, 26), statusLabel))
            ImGui.PopStyleColor()
            local errors = rd.validationErrors or {}
            if #errors > 0 then
                ImGui.TextDisabled("       " .. tostring(errors[1]))
            end
        elseif isCurrent then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.40, 1.0, 0.40, 1.0)
            ImGui.Text(string.format("  %2d   %-11s  %-20s  %-26s  %s",
                rd.round, eventType, locationLabel, titleLabel:sub(1, 26), statusLabel))
            ImGui.PopStyleColor()
        else
            ImGui.Text(string.format("  %2d   %-11s  %-20s  %-26s",
                rd.round, eventType, locationLabel, titleLabel:sub(1, 26)))
        end
        if subtitleLabel and subtitleLabel ~= "" then
            ImGui.TextDisabled("       " .. tostring(subtitleLabel):sub(1, 64))
        end
    end
end

function UICH._drawBoxScoresTab(career)
    local championships = MTE.Championships
    if not championships or not championships.getBoxScoresPage then
        ImGui.TextDisabled("Box score ledger unavailable.")
        return
    end

    local tierOptions = boxScoreTierOptions()
    for index, tier in ipairs(tierOptions) do
        if index > 1 then ImGui.SameLine() end
        local label = (tier == "all") and "All" or tier
        local active = _boxTierFilter == tier
        if active then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1) end
        if ImGui.Button(label .. "##boxfilter" .. tier, s(78), s(22)) then
            _boxTierFilter = tier
            _boxPage = 1
            _boxSelectedId = nil
        end
        if active then ImGui.PopStyleColor() end
    end
    ImGui.SameLine()
    if _boxPlayerOnly then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1) end
    if ImGui.Button("Player Only##boxplayer", s(110), s(22)) then
        _boxPlayerOnly = not _boxPlayerOnly
        _boxPage = 1
        _boxSelectedId = nil
    end
    if _boxPlayerOnly then ImGui.PopStyleColor() end
    ImGui.Separator()

    local pageData = championships.getBoxScoresPage(career, {
        tier = _boxTierFilter,
        playerOnly = _boxPlayerOnly,
        page = _boxPage,
        pageSize = 12,
    })
    _boxPage = tonumber(pageData.page or 1) or 1

    if ImGui.Button("Prev##boxpage", s(64), s(22)) and _boxPage > 1 then
        _boxPage = _boxPage - 1
        _boxSelectedId = nil
    end
    ImGui.SameLine()
    if ImGui.Button("Next##boxpage", s(64), s(22)) and _boxPage < (tonumber(pageData.pageCount or 1) or 1) then
        _boxPage = _boxPage + 1
        _boxSelectedId = nil
    end
    ImGui.SameLine()
    ImGui.TextDisabled(string.format("Page %d / %d  |  %d races",
        tonumber(pageData.page or 1) or 1,
        tonumber(pageData.pageCount or 1) or 1,
        tonumber(pageData.totalMatches or 0) or 0))

    local records = pageData.records or {}
    if #records <= 0 then
        ImGui.Spacing()
        ImGui.TextDisabled("No races match this filter yet.")
        return
    end

    if not _boxSelectedId then
        _boxSelectedId = records[1].recordId
    end

    local selected = nil
    for _, record in ipairs(records) do
        if tostring(record.recordId or "") == tostring(_boxSelectedId or "") then
            selected = record
            break
        end
    end
    if not selected then
        selected = records[1]
        _boxSelectedId = selected and selected.recordId or nil
    end

    local leftWidth = s(320)
    if ImGui.BeginChild("##boxscorelist", leftWidth, s(420), true) then
        for _, record in ipairs(records) do
            local selectedRow = tostring(record.recordId or "") == tostring(_boxSelectedId or "")
            local prefix = record.playerInvolved and "[YOU] " or ""
            local winner = record.winnerName and (" - " .. tostring(record.winnerName)) or ""
            local label = string.format("%s%s (%s) - %s%s##%s",
                prefix,
                tostring(record.routeName or record.district or "Race"),
                tostring(record.tier or "?"),
                fmtRelativeAge(record.timestamp),
                winner,
                tostring(record.recordId or "box"))
            if ImGui.Selectable(label, selectedRow) then
                _boxSelectedId = record.recordId
                selected = record
            end
        end
        ImGui.EndChild()
    end

    ImGui.SameLine()

    if ImGui.BeginChild("##boxscoredetail", 0, s(420), true) then
        if not selected then
            ImGui.TextDisabled("Select a race.")
        else
            local sr, sg, sb, sa = boxStateColor(selected.stateLabel)
            ImGui.Text(string.format("ROUTE: %s", tostring(selected.routeName or "Unknown Route")))
            ImGui.Text(string.format("TIER: %s", tostring(selected.tier or "?")))
            ImGui.Text(string.format("FIELD: %d drivers", tonumber(selected.fieldSize or 0) or 0))
            ImGui.Text(string.format("TYPE: %s", tostring(selected.raceType or "race")))
            ImGui.PushStyleColor(ImGuiCol.Text, sr, sg, sb, sa)
            ImGui.Text(string.format("STATE: %s", tostring(selected.stateLabel or "Mixed")))
            ImGui.PopStyleColor()
            ImGui.TextDisabled(string.format("Logged %s  |  Source: %s", fmtRelativeAge(selected.timestamp), tostring(selected.sourceType or "unknown")))
            ImGui.Separator()

            ImGui.TextDisabled(string.format("%-4s %-18s %-5s %-10s %-8s %-4s", "Pos", "Driver", "Start", "Time", "Gap", "Delta"))
            ImGui.Separator()
            if ImGui.BeginChild("##boxscoretable", 0, s(230), true) then
                for _, participant in ipairs(selected.participants or {}) do
                    local line = string.format("%-4s %-18s %-5s %-10s %-8s %-4s",
                        tostring(participant.finishPos or "--"),
                        tostring(participant.displayName or "Driver"):sub(1, 18),
                        fmtPos(participant.startPos),
                        participant.finishPos == 1 and fmtTime(participant.finishTime) or fmtGap(participant.gapToLeader),
                        fmtGap(participant.gapToLeader),
                        fmtDelta(participant.deltaPos))
                    if participant.isPlayer then
                        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.93, 0.33, 1.0)
                        ImGui.Text(line)
                        ImGui.PopStyleColor()
                    else
                        ImGui.Text(line)
                    end
                    ImGui.SameLine()
                    if ImGui.SmallButton(string.format("Inspect##box_%s_%s",
                        tostring(selected.recordId or "box"),
                        tostring(participant.driverId or (participant.isPlayer and "player" or "driver")))) then
                        openDriverProfile(participant.isPlayer and "player" or participant.driverId)
                    end
                    local flagText = participantFlagText(participant)
                    if flagText then
                        ImGui.TextDisabled("      " .. flagText)
                    end
                end
                ImGui.EndChild()
            end

            if type(selected.summaryBullets) == "table" and #selected.summaryBullets > 0 then
                ImGui.Separator()
                ImGui.Text("Summary")
                for _, bullet in ipairs(selected.summaryBullets) do
                    ImGui.BulletText(tostring(bullet))
                end
            end
        end
        ImGui.EndChild()
    end
end

-- â”€â”€ Tab 5: Team assignment for V â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UICH._drawTeamTab(career)
    local mode = career.playerFactionMode or "independent"
    local fc   = career.playerFactionColor or { 1, 1, 1 }

    ImGui.Text("V  -  Your Racing Team")
    ImGui.PushStyleColor(ImGuiCol.Text, fc[1], fc[2], fc[3], 1.0)
    ImGui.Text(string.format("  %s  [%s]",
        career.playerFactionName or "Independent", mode))
    ImGui.PopStyleColor()
    ImGui.Separator()

    -- Mid-season lock check
    local activeSeason = MTE.Championships and MTE.Championships.activeSeason(career)
    local midSeasonLock = activeSeason
        and not activeSeason.completed
        and (activeSeason.currentRound or 1) > 1
    if midSeasonLock then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.4, 0.2, 1.0)
        ImGui.TextWrapped("Team locked for this season. Changes take effect next season.")
        ImGui.PopStyleColor()
        ImGui.Spacing()
        ImGui.BeginDisabled()
    end

    -- Independent
    if ImGui.Button("Go Independent##fi", s(148), s(24)) then
        MTE.Championships.setPlayerFaction(career, "independent")
    end
    ImGui.SameLine()
    ImGui.TextDisabled("Privateer - no allegiance")

    ImGui.Spacing()
    ImGui.TextDisabled("--- Sign to a Team ---")
    ImGui.Spacing()

    local assignable = MTE.Factions and MTE.Factions.assignable() or {}
    for i, fdef in ipairs(assignable) do
        local c        = fdef.color or { 0.75, 0.75, 0.75 }
        local isCurr   = (career.playerFactionId == fdef.id)
        ImGui.PushStyleColor(ImGuiCol.Text, c[1], c[2], c[3], 1.0)
        local label    = (isCurr and "* " or "  ") .. fdef.name
        if ImGui.Button(label .. "##fsign" .. i, s(230), s(22)) then
            MTE.Championships.setPlayerFaction(career, "signed", { factionId = fdef.id })
        end
        ImGui.PopStyleColor()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.TextDisabled("--- Custom Team ---")
    ImGui.Spacing()

    local newVal, changed = ImGui.InputText("Name##fncustname", _customNameBuf[1], 64)
    if changed then _customNameBuf[1] = newVal end
    if ImGui.Button("Create Custom Team##fncreate", s(180), s(24)) then
        local n = _customNameBuf[1]
        if #n > 0 then
            MTE.Championships.setPlayerFaction(career, "custom", {
                factionName  = n,
                factionColor = { 0.50, 0.80, 1.0 },
            })
        end
    end

    if midSeasonLock then
        ImGui.EndDisabled()
    end
end

return UICH

