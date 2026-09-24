-- ============================================================
-- MT_Ecosystem: modules/ui_racing.lua
-- Racing tab UI: career picker, race config, prerace, results,
-- leaderboard, heat map, race history.
-- Drawn from ui.lua's Racing tab slot via UI.drawRacingTab().
-- ============================================================

local UIR = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end

-- Sub-tab state
local _tab         = 1   -- 1=Race, 2=Career, 3=Leaderboard, 4=Heat, 5=History, 6=Stats, 7=Nodes, 8=Routes
local _tabLabels   = { "Race", "Career", "Leaderboard", "Heat", "History", "Stats", "Nodes", "Routes" }

-- Career creation scratch
local _newCareerName      = "New Career"
local _newCareerBuf       = { _newCareerName }   -- ImGui text buffer
local _newCareerEventMix  = "mixed"
local _newCareerLastRaceKnockout = false
local _profileNameBuf     = { "" }
local _selectedTier       = 1   -- leaderboard tier index
local _stakeInputBuf      = { "0" }
local _stakeParsed        = 0
local _lastResultCache    = nil  -- cached last RaceFinished event data
local _errorMsg           = nil  -- error string to display
local _confirmDelete      = nil  -- career id pending deletion confirm
local _routeModeLabels    = {
    random = "Random",
    picked = "Pick From List",
    manual = "Saved Pair",
    root = "Named Root",
}

local TIER_LABELS = { "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }
local QUICK_RACE_WEIGHTING_LABELS = {
    mostly_low = "Mostly Low",
    mixed = "Mixed",
    mostly_high = "Mostly High",
}
local QUICK_RACE_MISMATCH_LABELS = {
    off = "Off",
    warn = "Warn",
    strict = "Strict",
}
local CAREER_EVENT_MIX_OPTIONS = {
    { id = "mixed", label = "Sprint + Drag Mix" },
    { id = "sprint_only", label = "Sprint Only" },
    { id = "drag_only", label = "Drag Only" },
}

-- â”€â”€ Colour helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function tierColor(tier)
    local cols = {
        Gonk       = { 0.55, 0.55, 0.55, 1 },
        Streetkid  = { 0.30, 0.75, 0.30, 1 },
        Solo       = { 0.20, 0.60, 1.00, 1 },
        Fixer      = { 0.90, 0.70, 0.10, 1 },
        Edgerunner = { 1.00, 0.20, 0.20, 1 },
    }
    return cols[tier] or { 1, 1, 1, 1 }
end

local function heatColor(heat)
    if heat <= 25 then return 0.3, 0.8, 0.3, 1 end
    if heat <= 50 then return 0.9, 0.8, 0.1, 1 end
    if heat <= 75 then return 1.0, 0.5, 0.1, 1 end
    return 1.0, 0.15, 0.15, 1
end

local function posColor(pos)
    if pos == 1  then return 1.0, 0.85, 0.1, 1 end
    if pos == 2  then return 0.8, 0.8,  0.8, 1 end
    if pos == 3  then return 0.8, 0.5,  0.2, 1 end
    return 0.8, 0.8, 0.8, 1
end

local function fmtTime(secs)
    if not secs then return "--:--.--" end
    local m = math.floor(secs / 60)
    local s = secs - m * 60
    return string.format("%d:%05.2f", m, s)
end

local function fmtResultMetric(entry)
    if not entry then return "--:--.--" end
    if entry.finishStatus == "pending" then
        local remainingDistance = tonumber(entry.remainingDistance)
        if remainingDistance then
            if remainingDistance >= 1000 then
                return string.format("+%.1fkm", remainingDistance / 1000.0)
            end
            return string.format("+%dm", math.floor(remainingDistance + 0.5))
        end
        if entry.estimatedTime then
            return "~" .. fmtTime(entry.estimatedTime)
        end
        return "PENDING"
    end
    if entry.finishStatus == "estimated" and entry.estimatedTime then
        return "~" .. fmtTime(entry.estimatedTime)
    end
    return fmtTime(entry.time)
end

local function fmtSafetyRating(value)
    return string.format("%.2f", tonumber(value) or 0.0)
end

local function fmtDistanceKm(distanceM)
    return string.format("%.1f km", (tonumber(distanceM) or 0.0) / 1000.0)
end

local function routeModeLabel(mode)
    return _routeModeLabels[mode] or "Random"
end

local function quickRaceWeightingLabel(weighting)
    return QUICK_RACE_WEIGHTING_LABELS[weighting] or "Mixed"
end

local function quickRaceMismatchLabel(policy)
    return QUICK_RACE_MISMATCH_LABELS[policy] or "Strict"
end

local function quickRaceModeLabel(mode)
    if mode == "knockout" then
        return "Knockout"
    end
    if mode == "endurance" then
        return "Endurance"
    end
    return "Standard"
end

local function quickRaceKnockoutTrafficLabel(mode)
    if mode == "none" then return "No Traffic" end
    if mode == "heavy" then return "Heavy Traffic" end
    return "Normal Traffic"
end

local function quickRaceKnockoutCombatLabel(mode)
    if mode == "disallowed" then
        return "Combat Off"
    end
    return "Combat Allowed"
end

local function findKnockoutCircuitById(circuitId, circuits)
    if not circuitId or type(circuits) ~= "table" then return nil end
    for _, circuit in ipairs(circuits) do
        if circuit.id == circuitId then
            return circuit
        end
    end
    return nil
end

local function getQuickRaceKnockoutCircuits()
    return MTE and MTE.KnockoutCircuits and MTE.KnockoutCircuits.quickRaceAll
        and MTE.KnockoutCircuits.quickRaceAll()
        or {}
end

local function launchQuickRaceKnockout(draft)
    local knockout = MTE and MTE.Knockout or nil
    local circuits = getQuickRaceKnockoutCircuits()
    local circuit = findKnockoutCircuitById(draft.quickRaceKnockoutCircuitId, circuits) or circuits[1]
    if not knockout or not knockout.openConfig then
        return false, "Knockout module is not loaded."
    end
    if not circuit then
        return false, "No knockout circuits are configured. Use Settings > Knockout Circuits first."
    end

    local maxAiField = MTE and MTE.KnockoutCircuits and MTE.KnockoutCircuits.getMaxAIFieldSize
        and MTE.KnockoutCircuits.getMaxAIFieldSize(circuit)
        or math.max(1, #(circuit.checkpoints or {}) - 1)

    local ok, err = knockout.openConfig({
        circuitId = circuit.id,
        fieldSize = maxAiField,
        trafficMode = draft.quickRaceKnockoutTrafficMode or "normal",
        combatMode = draft.quickRaceKnockoutCombatMode or "allowed",
        autoConfirm = true,
    })
    if ok and MTE and MTE.Racing and MTE.Racing.closeConfig then
        MTE.Racing.closeConfig()
    end
    return ok, err
end

local function nodeLabel(node)
    if not node then return "(none)" end
    local district = node.region or node.district or "Unknown"
    return string.format("%s [%s]", node.name or node.id or "Node", district)
end

local function findNodeById(nodeId, nodes)
    if not nodeId or type(nodes) ~= "table" then return nil end
    for _, node in ipairs(nodes) do
        if node.id == nodeId then
            return node
        end
    end
    return nil
end

local function rootPrimaryLabel(root)
    if not root then return "(none)" end
    return root.primaryLabel or root.displayName or root.autoLabel or root.rootId or "(none)"
end

local function rootSecondaryLabel(root)
    if not root then return nil end
    return root.secondaryLabel or root.subtitleOverride or nil
end

local function rootPathSummary(root, maxNodes)
    if not root then return "" end
    local nodeNames = root.nodeNames or {}
    local limit = math.max(2, tonumber(maxNodes) or #nodeNames)
    local parts = {}
    for index, nodeName in ipairs(nodeNames) do
        if index > limit then
            parts[#parts + 1] = string.format("... (+%d more)", #nodeNames - limit + 1)
            break
        end
        parts[#parts + 1] = tostring(nodeName or "?")
    end
    return table.concat(parts, " -> ")
end

local function findRootById(rootId, roots)
    if not rootId or type(roots) ~= "table" then return nil end
    for _, root in ipairs(roots) do
        if root.rootId == rootId then
            return root
        end
    end
    return nil
end

local function ensurePickedRouteDefaults(draft, nodes)
    if draft.routeMode ~= "picked" then return end
    if type(nodes) ~= "table" or #nodes == 0 then return end
    if not draft.selectedStartNodeId or not findNodeById(draft.selectedStartNodeId, nodes) then
        draft.selectedStartNodeId = nodes[1].id
    end
    if not draft.selectedFinishNodeId or not findNodeById(draft.selectedFinishNodeId, nodes) or draft.selectedFinishNodeId == draft.selectedStartNodeId then
        local fallback = nodes[2] or nodes[1]
        draft.selectedFinishNodeId = fallback and fallback.id or draft.selectedStartNodeId
    end
end

local function ensureRootRouteDefaults(draft, roots)
    if draft.routeMode ~= "root" then return end
    if type(roots) ~= "table" or #roots == 0 then
        draft.selectedRootId = nil
        return
    end
    if not draft.selectedRootId or not findRootById(draft.selectedRootId, roots) then
        draft.selectedRootId = roots[1].rootId
    end
end

local function collectQuickRaceRegions(nodes, roots)
    local options = { "Any" }
    local seen = { ["Any"] = true }

    local function push(region)
        if type(region) ~= "string" then return end
        local trimmed = region:match("^%s*(.-)%s*$")
        if not trimmed or trimmed == "" or seen[trimmed] then return end
        seen[trimmed] = true
        options[#options + 1] = trimmed
    end

    for _, root in ipairs(roots or {}) do
        push(root.districtLabel or root.region)
    end
    for _, node in ipairs(nodes or {}) do
        push(node.region or node.district)
    end

    table.sort(options, function(a, b)
        if a == "Any" then return true end
        if b == "Any" then return false end
        return string.lower(a) < string.lower(b)
    end)
    return options
end

local function getQuickRaceRegionSelection(draft, options)
    local selected = type(draft.preferredRegions) == "table" and draft.preferredRegions[1] or nil
    if selected then
        for _, option in ipairs(options or {}) do
            if option == selected then
                return selected
            end
        end
    end
    return "Any"
end

local function cycleNode(currentId, nodes, step, otherId)
    if type(nodes) ~= "table" or #nodes == 0 then return currentId end
    local idx = 1
    for i, node in ipairs(nodes) do
        if node.id == currentId then
            idx = i
            break
        end
    end
    local attempts = 0
    repeat
        idx = idx + step
        if idx < 1 then idx = #nodes end
        if idx > #nodes then idx = 1 end
        attempts = attempts + 1
        local candidate = nodes[idx]
        if candidate and candidate.id ~= otherId then
            return candidate.id
        end
    until attempts >= #nodes
    return currentId
end

local function normalizeNewCareerChampionshipConfig()
    local raw = {
        eventMix = _newCareerEventMix,
        lastRaceKnockout = _newCareerLastRaceKnockout == true,
    }
    if MTE and MTE.Careers and MTE.Careers.normalizeChampionshipConfig then
        return MTE.Careers.normalizeChampionshipConfig(raw)
    end
    return raw
end

local function resetNewCareerChampionshipConfig()
    local defaults = MTE and MTE.Careers and MTE.Careers.championshipConfigDefaults
        and MTE.Careers.championshipConfigDefaults()
        or { eventMix = "mixed", lastRaceKnockout = false }
    _newCareerEventMix = defaults.eventMix or "mixed"
    _newCareerLastRaceKnockout = defaults.lastRaceKnockout == true
end

local function drawSafetyRatingSummary(title, profile)
    if not profile then return end

    local delta = tonumber(profile.lastSRDelta) or 0.0
    local deltaSign = delta >= 0 and "+" or ""
    local counts = profile.lastRace and profile.lastRace.incidentCounts or {}

    ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.8, 1.0, 1.0)
    ImGui.Text(title)
    ImGui.PopStyleColor()

    ImGui.Text(string.format("Current: %s", fmtSafetyRating(profile.currentSR)))
    ImGui.SameLine()
    ImGui.TextDisabled("Last Delta:")
    ImGui.SameLine()
    if delta >= 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 0.85, 0.3, 1.0)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.45, 0.1, 1.0)
    end
    ImGui.Text(string.format("%s%.2f", deltaSign, delta))
    ImGui.PopStyleColor()

    ImGui.Text(string.format("Distance: %s    Incident Points: %d",
        fmtDistanceKm(profile.totalDistanceM),
        profile.totalIncidentPoints or 0))
    ImGui.Text(string.format("Races: %d    Clean Races: %d    Best Clean: %s",
        profile.raceCount or 0,
        profile.cleanRaceCount or 0,
        fmtDistanceKm(profile.bestCleanDistanceM)))

    if profile.lastRace then
        ImGui.TextDisabled(string.format("Last Race: %s  |  %d pts  |  1x %d  2x %d  4x %d",
            tostring(profile.lastRace.finishStatus or "--"),
            profile.lastRace.incidentPoints or 0,
            counts["1x"] or 0,
            counts["2x"] or 0,
            counts["4x"] or 0))
    end
end

-- â”€â”€ Main draw entry â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR.draw()
    -- Sub-tab bar
    for i, label in ipairs(_tabLabels) do
        if i > 1 then ImGui.SameLine() end
        local active = (_tab == i)
        if active then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1) end
        if ImGui.Button(label .. "##rtab" .. i, s(84), s(22)) then _tab = i end
        if active then ImGui.PopStyleColor() end
    end
    ImGui.Separator()

    if _tab == 1 then UIR._drawRaceTab()
    elseif _tab == 2 then UIR._drawCareerTab()
    elseif _tab == 3 then UIR._drawLeaderboardTab()
    elseif _tab == 4 then UIR._drawHeatTab()
    elseif _tab == 5 then UIR._drawHistoryTab()
    elseif _tab == 6 then UIR._drawStatsTab()
    elseif _tab == 7 then UIR._drawNodesTab()
    elseif _tab == 8 then
        if MTE.UIRoutes then MTE.UIRoutes.draw() end
    end
end

-- â”€â”€ Tab 1: Race â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR._drawRaceTab()
    local mte = MTE
    local knockout = mte and mte.Knockout or nil
    if knockout and knockout.getState and knockout.STATE then
        local knockoutState = knockout.getState()
        if knockoutState and knockoutState ~= knockout.STATE.IDLE then
            if mte and mte.UIKnockout and mte.UIKnockout.draw then
                mte.UIKnockout.draw()
            else
                ImGui.TextDisabled("Knockout UI not loaded.")
            end
            return
        end
    end

    local R = mte and mte.Racing
    if not R or not R.getState or not R.STATE then
        ImGui.TextDisabled("Race system not loaded.")
        return
    end
    local state = R.getState()

    -- Error banner
    if _errorMsg then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.3, 0.3, 1)
        ImGui.TextWrapped("! " .. _errorMsg)
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.SmallButton("x##errclear") then _errorMsg = nil end
        ImGui.Separator()
    end

    if state == R.STATE.IDLE then
        UIR._drawIdlePanel()
    elseif state == R.STATE.CONFIG then
        UIR._drawConfigPanel()
    elseif state == R.STATE.PRERACE then
        UIR._drawPreRacePanel()
    elseif state == R.STATE.QUALI then
        UIR._drawQualiPanel()
    elseif state == R.STATE.COUNTDOWN then
        UIR._drawCountdownPanel()
    elseif state == R.STATE.RACING then
        UIR._drawRacingPanel()
    elseif state == R.STATE.RESULTS then
        UIR._drawResultsPanel()
    end
end

function UIR._drawIdlePanel()
    local mte = MTE
    local careers = mte and mte.Careers
    local racing = mte and mte.Racing
    if not careers or not careers.active then
        ImGui.TextDisabled("Career system not loaded.")
        return
    end

    local career = careers.active()
    if not career then
        ImGui.TextDisabled("No active career. Go to the Career tab to create one.")
        return
    end

    local tc = tierColor(career.tier)
    ImGui.PushStyleColor(ImGuiCol.Text, tc[1], tc[2], tc[3], tc[4])
    ImGui.Text(string.format("[%s]  %s", career.tier, career.name))
    ImGui.PopStyleColor()

    local champSeason  = mte and mte.Championships and mte.Championships.activeSeason(career)
    local champRdStr   = champSeason
        and string.format("  |  Champ Rd %d/%d",
                champSeason.currentRound or 1, champSeason.totalRounds or 1)
        or ""
    ImGui.Text(string.format("Rep: %d  |  Career S%d  |  Races: %d  |  Wins: %d%s",
        career.rep, career.seasonNumber or 1,
        career.stats.racesRun, career.stats.wins, champRdStr))

    local prog = careers.repProgress and careers.repProgress(career) or 0
    local repFloor, repCeil = careers.repThresholds and careers.repThresholds(career)
    local barLabel
    if not repCeil then
        barLabel = string.format("%s  |  Rep %d", career.tier, career.rep)
    else
        barLabel = string.format("%s  |  Rep %d / %d", career.tier, career.rep, repCeil)
    end
    ImGui.ProgressBar(prog, -1, 14, barLabel)

    local scheduledEvent = mte and mte.Championships and mte.Championships.currentEvent
        and mte.Championships.currentEvent(career)
        or nil
    if scheduledEvent then
        ImGui.TextDisabled(string.format(
            "Next Event: %s  |  %s",
            tostring(scheduledEvent.eventType or "sprint"):upper(),
            tostring(scheduledEvent.titleLabel or scheduledEvent.trackName or scheduledEvent.districtLabel or scheduledEvent.district or "Scheduled Event")))
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    if ImGui.Button("Set Up Race", s(140), s(30)) then
        if scheduledEvent and scheduledEvent.eventType == "knockout" then
            local ok, err = mte and mte.Knockout and mte.Knockout.openConfig
                and mte.Knockout.openConfig({ eventDef = scheduledEvent, autoConfirm = true })
            if ok then
                _errorMsg = nil
            else
                _errorMsg = err or "Failed to open scheduled knockout event."
            end
        else
            local ok, err = racing and racing.openConfig and racing.openConfig()
            if not ok then
                _errorMsg = err or "Could not open scheduled race setup."
            else
                _errorMsg = nil
            end
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Sandbox Quick Race", s(160), s(30)) then
        local ok, err = racing and racing.openQuickRaceConfig and racing.openQuickRaceConfig()
        if not ok then
            _errorMsg = err or "Could not open Quick Race config."
        else
            _errorMsg = nil
        end
    end
end

local _specRecordBuf = { "" }
local _specRecordBufDraft = nil

--- Spec Field editor: rows of (livery, count). Persisted with the quick-race draft.
function UIR._drawSpecFieldSection(draft, racing, mte)
    ImGui.Spacing()
    ImGui.Separator()
    local enabled, changed = ImGui.Checkbox("Spec Field (one-make grid)##specfield", draft.specFieldEnabled == true)
    if changed then draft.specFieldEnabled = enabled end
    ImGui.SameLine()
    if ImGui.SmallButton("Preset: RB15 20-car field##specpreset") then
        if racing.applySpecFieldPreset then racing.applySpecFieldPreset(draft) end
        _specRecordBufDraft = nil
        if racing.persistQuickRaceDraft then pcall(racing.persistQuickRaceDraft, draft) end
    end
    ImGui.SameLine()
    if ImGui.SmallButton("Reload liveries##specreload") and mte and mte.Liveries and mte.Liveries.reload then
        mte.Liveries.reload()
    end
    if draft.specFieldEnabled ~= true then
        ImGui.TextDisabled("  Off: rivals drive their own roster cars.")
        return
    end

    -- base record
    if _specRecordBufDraft ~= draft then
        _specRecordBuf[1] = tostring(draft.specFieldRecord or (racing.SPEC_FIELD_DEFAULT_RECORD or ""))
        _specRecordBufDraft = draft
    end
    ImGui.Text("Base record:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(340)
    local buf, bufChanged = ImGui.InputText("##specrecord", _specRecordBuf[1], 96)
    if bufChanged then
        _specRecordBuf[1] = buf
        draft.specFieldRecord = buf
    end

    -- rows
    local liveries = (mte and mte.Liveries and mte.Liveries.list and mte.Liveries.list()) or { "stock" }
    draft.specField = type(draft.specField) == "table" and draft.specField or {}
    local removeIdx = nil
    for i, row in ipairs(draft.specField) do
        ImGui.PushID("specrow" .. i)
        -- livery combo (values not in the manifest are still shown so presets survive a missing manifest)
        local current = tostring(row.appearance or "stock")
        local items = {}
        local found = false
        for _, name in ipairs(liveries) do items[#items + 1] = name; if name == current then found = true end end
        if not found then table.insert(items, 1, current) end
        local curIdx = 0
        for k, name in ipairs(items) do if name == current then curIdx = k - 1 end end
        ImGui.SetNextItemWidth(180)
        local newIdx, comboChanged = ImGui.Combo("##livery", curIdx, items, #items)
        if comboChanged then row.appearance = items[newIdx + 1] end
        ImGui.SameLine()
        ImGui.SetNextItemWidth(90)
        local cnt, cntChanged = ImGui.InputInt("##count", math.floor(tonumber(row.count) or 1), 1, 1)
        if cntChanged then row.count = math.max(0, math.min(24, cnt)) end
        ImGui.SameLine()
        if ImGui.SmallButton("x##rm") then removeIdx = i end
        ImGui.PopID()
    end
    if removeIdx then table.remove(draft.specField, removeIdx) end
    if ImGui.SmallButton("+ row##specadd") then
        draft.specField[#draft.specField + 1] = { appearance = liveries[2] or "stock", count = 2 }
    end
    local total = racing.getSpecFieldTotal and racing.getSpecFieldTotal(draft) or 0
    local cap = 24
    if mte and mte.Settings and mte.Settings.getTuningValue then
        local formula = draft.specFieldFormulaTuning ~= false
        cap = formula and (racing.SPEC_FIELD_FORMULA_TUNING and racing.SPEC_FIELD_FORMULA_TUNING.maxAiCars or 24)
              or math.floor(tonumber(mte.Settings.getTuningValue("maxAiCars", draft)) or 12)
    end
    ImGui.SameLine()
    if total > cap then ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.3, 0.3, 1) end
    ImGui.Text(string.format("Total rivals: %d / %d  (%d cars incl. V, %d grid rows)", total, cap, total + 1, math.ceil((total + 1) / 2)))
    if total > cap then ImGui.PopStyleColor() end

    local ft, ftChanged = ImGui.Checkbox("Formula tuning for this race (AI 100 m/s cap, base 55, 8 m rows, 220 m clear, 24-car cap)##specformula",
        draft.specFieldFormulaTuning ~= false)
    if ftChanged then draft.specFieldFormulaTuning = ft end
    ImGui.TextDisabled("  Vehicle Class is ignored while the lineup is on. Player car is not changed.")
end

function UIR._drawConfigPanel()
    local mte = MTE
    local racing = mte and mte.Racing
    if not racing or not racing.getDraft then
        ImGui.TextDisabled("Race config unavailable.")
        return
    end

    local draft = racing.getDraft()
    local scheduledEvent = draft._scheduledEvent
    local lockedCareerEvent = draft._eventSourceType ~= "quick_race"
        and draft._lockToScheduledEvent == true
        and type(scheduledEvent) == "table"
    local quickRaceMode = draft._eventSourceType == "quick_race"
    local quickRaceKnockoutMode = quickRaceMode and (draft.quickRaceMode == "knockout")
    local quickRaceEnduranceMode = quickRaceMode and (draft.quickRaceMode == "endurance")
    local tierOptions = (mte and mte.Roster and mte.Roster.tierNames and mte.Roster.tierNames()) or TIER_LABELS
    local nodes = (mte and mte.Nodes) or {}
    local roots = (mte and mte.Roots and mte.Roots.all and mte.Roots.all({ includeInvalid = false })) or {}
    local regionOptions = collectQuickRaceRegions(nodes, roots)
    local knockoutCircuits = quickRaceMode and getQuickRaceKnockoutCircuits() or {}
    local selectedKnockoutCircuit = quickRaceKnockoutMode and (findKnockoutCircuitById(draft.quickRaceKnockoutCircuitId, knockoutCircuits) or knockoutCircuits[1]) or nil
    local selectedEnduranceCircuit = quickRaceEnduranceMode and (findKnockoutCircuitById(draft.quickRaceEnduranceCircuitId, knockoutCircuits) or knockoutCircuits[1]) or nil
    if quickRaceKnockoutMode then
        draft.quickRaceKnockoutCircuitId = selectedKnockoutCircuit and selectedKnockoutCircuit.id or nil
        local maxTotal = selectedKnockoutCircuit and mte and mte.KnockoutCircuits and mte.KnockoutCircuits.getMaxTotalGridSize
            and mte.KnockoutCircuits.getMaxTotalGridSize(selectedKnockoutCircuit)
            or nil
        if type(maxTotal) == "number" then
            draft.quickRaceKnockoutGridSize = math.max(2, math.floor(maxTotal))
        else
            draft.quickRaceKnockoutGridSize = nil
        end
    end
    if quickRaceEnduranceMode then
        draft.raceType = "endurance"
        draft.quickRaceEnduranceCircuitId = selectedEnduranceCircuit and selectedEnduranceCircuit.id or nil
        if selectedEnduranceCircuit and selectedEnduranceCircuit.isLoop == false then
            draft.lapCount = 1
        else
            draft.lapCount = math.max(1, math.min(tonumber(draft.lapCount) or 1, 8))
        end
    end
    ImGui.Text("Configure Race")
    ImGui.Separator()

    if lockedCareerEvent then
        ImGui.TextDisabled(string.format(
            "Career Event: Round %d  |  %s",
            tonumber(scheduledEvent.round or 0),
            tostring(scheduledEvent.titleLabel or scheduledEvent.trackName or "Scheduled Event")))
        ImGui.TextDisabled(string.format(
            "Mode: %s  |  Location: %s  |  Start: %s  |  Field: %d",
            tostring(scheduledEvent.eventType or "sprint"),
            tostring(scheduledEvent.districtLabel or scheduledEvent.district or "?"),
            tostring(scheduledEvent.startType or "grid"),
            tonumber(scheduledEvent.fieldSize or 0)))
        ImGui.Spacing()
        ImGui.BeginDisabled()
    end

    if quickRaceMode then
        ImGui.TextDisabled("Sandbox quick races do not advance the championship calendar.")
        ImGui.TextDisabled("Use Set Up Race from Career for the scheduled season round.")
        ImGui.Spacing()
        ImGui.Text("Quick Race Mode:")
        for _, mode in ipairs(racing.QUICK_RACE_MODES or { "standard", "knockout" }) do
            ImGui.SameLine()
            local sel = (draft.quickRaceMode or "standard") == mode
            if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
            if ImGui.SmallButton(quickRaceModeLabel(mode) .. "##qr_mode_" .. mode) then
                draft.quickRaceMode = mode
                quickRaceKnockoutMode = (mode == "knockout")
                quickRaceEnduranceMode = (mode == "endurance")
            end
            if sel then ImGui.PopStyleColor() end
        end
        ImGui.Spacing()
    end

    if quickRaceKnockoutMode then
        ImGui.Text("Knockout Circuit:")
        if #knockoutCircuits <= 0 then
            ImGui.TextDisabled("No checkpoint knockout circuits are configured yet.")
            ImGui.TextDisabled("Open Settings > Knockout Circuits to create one.")
        else
            if ImGui.BeginCombo("Circuit##qr_knockout_circuit", tostring(selectedKnockoutCircuit and selectedKnockoutCircuit.name or "Select circuit")) then
                for _, circuit in ipairs(knockoutCircuits) do
                    local isSelected = draft.quickRaceKnockoutCircuitId == circuit.id
                    if ImGui.Selectable(circuit.name, isSelected) then
                        draft.quickRaceKnockoutCircuitId = circuit.id
                        selectedKnockoutCircuit = circuit
                        local maxTotal = mte and mte.KnockoutCircuits and mte.KnockoutCircuits.getMaxTotalGridSize
                            and mte.KnockoutCircuits.getMaxTotalGridSize(circuit)
                            or #(circuit.checkpoints or {})
                        draft.quickRaceKnockoutGridSize = maxTotal
                    end
                end
                ImGui.EndCombo()
            end

            local maxTotal = selectedKnockoutCircuit and mte and mte.KnockoutCircuits and mte.KnockoutCircuits.getMaxTotalGridSize
                and mte.KnockoutCircuits.getMaxTotalGridSize(selectedKnockoutCircuit)
                or nil
            if selectedKnockoutCircuit then
                ImGui.TextDisabled(string.format(
                    "%s  |  %d nodes  |  %d cars max incl. V",
                    tostring(selectedKnockoutCircuit.region or "Unknown"),
                    tonumber(#(selectedKnockoutCircuit.checkpoints or {}) or 0),
                    tonumber(maxTotal or 0)))
            end
            if type(maxTotal) == "number" then
                draft.quickRaceKnockoutGridSize = math.max(2, math.floor(maxTotal))
                ImGui.TextDisabled(string.format(
                    "Grid Size: %d total cars including V (track-locked)",
                    tonumber(draft.quickRaceKnockoutGridSize or maxTotal)))
                ImGui.TextDisabled(string.format("AI rivals: %d", math.max(1, (draft.quickRaceKnockoutGridSize or maxTotal) - 1)))
            end

            ImGui.Text("Traffic:")
            for _, mode in ipairs({ "normal", "none", "heavy" }) do
                ImGui.SameLine()
                local sel = (draft.quickRaceKnockoutTrafficMode or "normal") == mode
                if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.8, 1) end
                if ImGui.SmallButton(quickRaceKnockoutTrafficLabel(mode) .. "##qr_knockout_traffic_" .. mode) then
                    draft.quickRaceKnockoutTrafficMode = mode
                end
                if sel then ImGui.PopStyleColor() end
            end

            ImGui.Text("Combat:")
            for _, mode in ipairs({ "allowed", "disallowed" }) do
                ImGui.SameLine()
                local sel = (draft.quickRaceKnockoutCombatMode or "allowed") == mode
                if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.8, 1) end
                if ImGui.SmallButton(quickRaceKnockoutCombatLabel(mode) .. "##qr_knockout_combat_" .. mode) then
                    draft.quickRaceKnockoutCombatMode = mode
                end
                if sel then ImGui.PopStyleColor() end
            end
        end
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.TextDisabled("Knockout quick races only use checkpoint knockout circuits from Settings. Standard route, class, and qualifying controls are intentionally hidden here because they do not affect knockout flow.")
    else
        local isEnduranceRace = quickRaceEnduranceMode or ((draft.raceType or "sprint") == "endurance")

        -- Start type
        ImGui.Text("Start Type:")
        for _, st in ipairs(racing.START_TYPES or {}) do
            ImGui.SameLine()
            local sel = (draft.defaultStartType == st)
            if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
            if ImGui.SmallButton(st .. "##st") then draft.defaultStartType = st end
            if sel then ImGui.PopStyleColor() end
        end

        if not quickRaceEnduranceMode then
            ImGui.Text("Race Type:")
            for _, rt in ipairs({ "sprint", "drag" }) do
                ImGui.SameLine()
                local sel = (draft.raceType or "sprint") == rt
                if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
                if ImGui.SmallButton(rt .. "##rt") then draft.raceType = rt end
                if sel then ImGui.PopStyleColor() end
            end
        else
            ImGui.TextDisabled("Race Type: endurance")
        end

        if isEnduranceRace then
            ImGui.Text("Endurance Source:")
            local enduranceSourceType = draft.quickRaceEnduranceSourceType or "circuit"
            for _, srcType in ipairs({ "circuit", "route" }) do
                ImGui.SameLine()
                local srcSel = enduranceSourceType == srcType
                if srcSel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
                if ImGui.SmallButton(srcType .. "##endurance_src") then
                    draft.quickRaceEnduranceSourceType = srcType
                    enduranceSourceType = srcType
                end
                if srcSel then ImGui.PopStyleColor() end
            end

            if enduranceSourceType == "route" then
                local enduranceRoots = {}
                for _, root in ipairs(roots) do
                    if #(root.nodeIds or {}) >= 3 then
                        enduranceRoots[#enduranceRoots + 1] = root
                    end
                end
                if #enduranceRoots == 0 then
                    ImGui.TextDisabled("No routes with 3 or more nodes available.")
                    ImGui.TextDisabled("Use the Routes tab to create one.")
                else
                    local selectedEnduranceRoot = findRootById(draft.quickRaceEnduranceRootId, enduranceRoots) or enduranceRoots[1]
                    draft.quickRaceEnduranceRootId = selectedEnduranceRoot and selectedEnduranceRoot.rootId or nil
                    ImGui.TextDisabled("Choose a route with 3+ nodes for the endurance race.")
                    if ImGui.BeginCombo("Endurance Route##qr_endurance_route", rootPrimaryLabel(selectedEnduranceRoot)) then
                        for _, root in ipairs(enduranceRoots) do
                            local isSelected = root.rootId == draft.quickRaceEnduranceRootId
                            if ImGui.Selectable(rootPrimaryLabel(root), isSelected) then
                                draft.quickRaceEnduranceRootId = root.rootId
                                selectedEnduranceRoot = root
                            end
                        end
                        ImGui.EndCombo()
                    end
                    selectedEnduranceRoot = findRootById(draft.quickRaceEnduranceRootId, enduranceRoots) or selectedEnduranceRoot
                    if selectedEnduranceRoot then
                        local secondary = rootSecondaryLabel(selectedEnduranceRoot)
                        if secondary then
                            ImGui.TextDisabled(secondary)
                        end
                        ImGui.TextDisabled(string.format(
                            "Path nodes: %d  |  %.0f m%s",
                            tonumber(selectedEnduranceRoot.nodeCount or #(selectedEnduranceRoot.nodeIds or {})),
                            tonumber(selectedEnduranceRoot.distanceM or 0),
                            selectedEnduranceRoot.isLoop == true and "  |  loop" or ""))
                    end
                end
            else
                ImGui.Text("Endurance Circuit:")
                if #knockoutCircuits <= 0 then
                    ImGui.TextDisabled("No checkpoint circuits are configured yet.")
                    ImGui.TextDisabled("Open Settings > Knockout Circuits to create one.")
                else
                    if ImGui.BeginCombo("Circuit##qr_endurance_circuit", tostring(selectedEnduranceCircuit and selectedEnduranceCircuit.name or "Select circuit")) then
                        for _, circuit in ipairs(knockoutCircuits) do
                            local isSelected = draft.quickRaceEnduranceCircuitId == circuit.id
                            if ImGui.Selectable(circuit.name, isSelected) then
                                draft.quickRaceEnduranceCircuitId = circuit.id
                                selectedEnduranceCircuit = circuit
                                if circuit.isLoop == false then
                                    draft.lapCount = 1
                                end
                            end
                        end
                        ImGui.EndCombo()
                    end
                    if selectedEnduranceCircuit then
                        local maxAiField = mte and mte.KnockoutCircuits and mte.KnockoutCircuits.getMaxAIFieldSize
                            and mte.KnockoutCircuits.getMaxAIFieldSize(selectedEnduranceCircuit)
                            or math.max(1, #(selectedEnduranceCircuit.checkpoints or {}) - 1)
                        ImGui.TextDisabled(string.format(
                            "%s  |  %d nodes  |  %s  |  up to %d AI rivals",
                            tostring(selectedEnduranceCircuit.region or "Unknown"),
                            tonumber(#(selectedEnduranceCircuit.checkpoints or {}) or 0),
                            selectedEnduranceCircuit.isLoop and "closed loop" or "point-to-point",
                            tonumber(maxAiField or 1)))
                    end
                end
            end
        end

        -- Field size
        local fsz = draft.defaultFieldSize or 8
        local fieldMax = 12
        if mte and mte.Settings and mte.Settings.getTuningValue then
            fieldMax = math.max(2, math.floor(tonumber(mte.Settings.getTuningValue("maxAiCars", draft)) or 12))
        end
        local enduranceSourceType = draft.quickRaceEnduranceSourceType or "circuit"
        if isEnduranceRace and enduranceSourceType == "circuit" and selectedEnduranceCircuit and mte and mte.KnockoutCircuits and mte.KnockoutCircuits.getMaxAIFieldSize then
            fieldMax = math.max(1, tonumber(mte.KnockoutCircuits.getMaxAIFieldSize(selectedEnduranceCircuit)) or 1)
        end
        local fieldMin = 2
        local specFieldActive = quickRaceMode and not isEnduranceRace and (draft.raceType or "sprint") == "sprint"
            and draft.specFieldEnabled == true
        if specFieldActive and racing.getSpecFieldTotal then
            ImGui.TextDisabled(string.format("Field Size: %d AI (locked by Spec Field lineup)", racing.getSpecFieldTotal(draft)))
        else
            local newVal, changed = ImGui.SliderInt("Field Size", fsz, fieldMin, fieldMax)
            if changed then draft.defaultFieldSize = newVal end
        end

        -- Spec Field (one-make lineup): every AI rival drives one record, livery chosen per row.
        if quickRaceMode and not isEnduranceRace and (draft.raceType or "sprint") == "sprint" then
            UIR._drawSpecFieldSection(draft, racing, mte)
        end

        if draft.raceType == "sprint" then
            local lapCount, lapChanged = ImGui.SliderInt("Laps", tonumber(draft.lapCount or 1) or 1, 1, 8)
            if lapChanged then draft.lapCount = lapCount end
            if (tonumber(draft.lapCount or 1) or 1) > 1 then
                ImGui.TextDisabled("Sprint laps alternate automatically: A -> B -> A -> B.")
            end
        elseif isEnduranceRace then
            local enduranceIsLoop = false
            if enduranceSourceType == "route" then
                local selectedEnduranceRoot = findRootById(draft.quickRaceEnduranceRootId, roots)
                enduranceIsLoop = selectedEnduranceRoot and selectedEnduranceRoot.isLoop == true
            else
                enduranceIsLoop = selectedEnduranceCircuit and selectedEnduranceCircuit.isLoop == true
            end
            if not enduranceIsLoop then
                draft.lapCount = 1
                ImGui.TextDisabled("Laps: 1 (point-to-point endurance)")
            else
                local lapCount, lapChanged = ImGui.SliderInt("Laps", tonumber(draft.lapCount or 1) or 1, 1, 8)
                if lapChanged then draft.lapCount = lapCount end
            end
        else
            draft.lapCount = 1
        end

        local gridShift, gridShiftChanged = ImGui.SliderFloat("Grid Shift L/R (m)", tonumber(draft.gridLateralShiftM) or 0.0, -12.0, 12.0)
        if gridShiftChanged then draft.gridLateralShiftM = gridShift end
        ImGui.TextDisabled("Moves V and the whole starting grid left or right relative to the launch direction.")

        ImGui.Spacing()
        ImGui.Text("Sandbox Tuning:")

        if ImGui.BeginCombo("Driver Tier Min##qr_driver_min", tostring(draft.quickRaceDriverTierMin or tierOptions[1])) then
            for _, tier in ipairs(tierOptions) do
                local isSelected = draft.quickRaceDriverTierMin == tier
                if ImGui.Selectable(tier, isSelected) then
                    draft.quickRaceDriverTierMin = tier
                end
            end
            ImGui.EndCombo()
        end

        if ImGui.BeginCombo("Driver Tier Max##qr_driver_max", tostring(draft.quickRaceDriverTierMax or draft.quickRaceDriverTierMin or tierOptions[1])) then
            for _, tier in ipairs(tierOptions) do
                local isSelected = draft.quickRaceDriverTierMax == tier
                if ImGui.Selectable(tier, isSelected) then
                    draft.quickRaceDriverTierMax = tier
                end
            end
            ImGui.EndCombo()
        end

        local prestigeMin, prestigeMinChanged = ImGui.SliderInt("Min Prestige##qr_pmin", draft.quickRacePrestigeMin or 1, 1, 5)
        if prestigeMinChanged then draft.quickRacePrestigeMin = prestigeMin end
        local prestigeMax, prestigeMaxChanged = ImGui.SliderInt("Max Prestige##qr_pmax", draft.quickRacePrestigeMax or 5, 1, 5)
        if prestigeMaxChanged then draft.quickRacePrestigeMax = prestigeMax end

        ImGui.Text("Prestige Weighting:")
        for _, weighting in ipairs(racing.QUICK_RACE_WEIGHTINGS or { "mostly_low", "mixed", "mostly_high" }) do
            ImGui.SameLine()
            local sel = (draft.quickRacePrestigeWeighting or "mixed") == weighting
            if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
            if ImGui.SmallButton(quickRaceWeightingLabel(weighting) .. "##qr_weight_" .. weighting) then
                draft.quickRacePrestigeWeighting = weighting
            end
            if sel then ImGui.PopStyleColor() end
        end

        local bossOutlier, bossChanged = ImGui.Checkbox("Allow boss car outlier", draft.quickRaceAllowBossOutlier == true)
        if bossChanged then draft.quickRaceAllowBossOutlier = bossOutlier end

        ImGui.Text("Player Car Rule:")
        for _, policy in ipairs(racing.QUICK_RACE_MISMATCH_POLICIES or { "off", "warn", "strict" }) do
            ImGui.SameLine()
            local sel = (draft.quickRaceMismatchPolicy or "strict") == policy
            if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.8, 1) end
            if ImGui.SmallButton(quickRaceMismatchLabel(policy) .. "##qr_mismatch_" .. policy) then
                draft.quickRaceMismatchPolicy = policy
            end
            if sel then ImGui.PopStyleColor() end
        end

        -- Vehicle class
        ImGui.Text("Vehicle Class:")
        ImGui.SameLine()
        for _, cl in ipairs({ "Any", "Muscle", "Sport", "Tech", "Nomad", "Bike" }) do
            ImGui.SameLine()
            local sel = (cl == "Any" and draft.vehicleClass == nil) or (draft.vehicleClass == cl)
            if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
            if ImGui.SmallButton(cl .. "##vc") then
                draft.vehicleClass = (cl == "Any") and nil or cl
            end
            if sel then ImGui.PopStyleColor() end
        end

        -- Time of day
        ImGui.Text("Time of Day:")
        for _, tod in ipairs({ "Any", "day", "night" }) do
            ImGui.SameLine()
            local sel = (tod == "Any" and draft.timeOfDay == nil) or (draft.timeOfDay == tod)
            if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.8, 1) end
            if ImGui.SmallButton(tod .. "##tod") then
                draft.timeOfDay = (tod == "Any") and nil or tod
            end
            if sel then ImGui.PopStyleColor() end
        end

        if not isEnduranceRace then
            local dmin = draft.minDistanceM or 1500
            local dmax = draft.maxDistanceM or 8000
            local nd, ndChanged = ImGui.SliderInt("Min Dist (m)", dmin, 500, 5000)
            if ndChanged then draft.minDistanceM = nd end
            local nd2, nd2Changed = ImGui.SliderInt("Max Dist (m)", dmax, 1500, 15000)
            if nd2Changed then draft.maxDistanceM = nd2 end
        end

        if quickRaceMode and not isEnduranceRace then
            local selectedRegion = getQuickRaceRegionSelection(draft, regionOptions)
            if ImGui.BeginCombo("Location Set##qr_location_set", selectedRegion) then
                for _, option in ipairs(regionOptions) do
                    local isSelected = option == selectedRegion
                    if ImGui.Selectable(option, isSelected) then
                        draft.preferredRegions = (option == "Any") and nil or { option }
                        selectedRegion = option
                    end
                end
                ImGui.EndCombo()
            end
            ImGui.TextDisabled("Filters random Quick Race route picks. Picked nodes use explicit endpoints; named roots use their stored root path.")
        end

        -- Quali toggle
        local qe = draft.qualiEnabled or false
        local nq, nqChanged = ImGui.Checkbox("Qualifying Lap", qe)
        if nqChanged then draft.qualiEnabled = nq end

        -- Traffic suppression toggle
        local cfg = MTE and MTE.Settings and MTE.Settings.current or {}
        local suppressTraffic = cfg.suppressTrafficDuringRace ~= false
        local newSuppress, suppressChanged = ImGui.Checkbox("Suppress Traffic During Race", suppressTraffic)
        if suppressChanged then
            cfg.suppressTrafficDuringRace = newSuppress
            if MTE and MTE.Settings and MTE.Settings.save then MTE.Settings.save() end
        end
        if not suppressTraffic then
            ImGui.SameLine()
            ImGui.TextColored(1.0, 0.55, 0.0, 1.0, "(live traffic â€” take your chances)")
        end

        ImGui.Spacing()
        ImGui.Separator()
        if isEnduranceRace then
            ImGui.TextDisabled("Endurance uses the selected checkpoint circuit from Settings instead of A -> B route picking.")
        else
            ImGui.Text("Route Source:")
            draft.routeMode = draft.routeMode or (draft.useManualNodes and "manual" or "random")
            for _, mode in ipairs({ "random", "picked", "manual", "root" }) do
                ImGui.SameLine()
                local sel = draft.routeMode == mode
                if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
                if ImGui.SmallButton(routeModeLabel(mode) .. "##route_mode_" .. mode) then
                    draft.routeMode = mode
                    draft.useManualNodes = (mode == "manual")
                end
                if sel then ImGui.PopStyleColor() end
            end

            local hasManualPair = MTE.ManualNodes and MTE.ManualNodes.hasPair and MTE.ManualNodes.hasPair()
            local manualFallbackMsg = nil
            if draft.routeMode == "manual" and not hasManualPair then
                if #nodes >= 2 then
                    draft.routeMode = "picked"
                    draft.useManualNodes = false
                    ensurePickedRouteDefaults(draft, nodes)
                    manualFallbackMsg = "Saved manual route missing. Using picked route selection instead."
                else
                    draft.routeMode = "random"
                    draft.useManualNodes = false
                    manualFallbackMsg = "Saved manual route missing. Falling back to random route selection."
                end
            elseif draft.routeMode == "root" and #roots == 0 then
                if #nodes >= 2 then
                    draft.routeMode = "picked"
                    draft.useManualNodes = false
                    ensurePickedRouteDefaults(draft, nodes)
                    manualFallbackMsg = "No named roots available. Using picked route selection instead."
                else
                    draft.routeMode = "random"
                    draft.useManualNodes = false
                    manualFallbackMsg = "No named roots available. Falling back to random route selection."
                end
            end
            if manualFallbackMsg then
                ImGui.TextDisabled(manualFallbackMsg)
            end

            if draft.routeMode == "picked" then
            ensurePickedRouteDefaults(draft, nodes)
            if #nodes < 2 then
                ImGui.TextDisabled("No named node list available yet.")
            else
                local startNode = findNodeById(draft.selectedStartNodeId, nodes)
                local finishNode = findNodeById(draft.selectedFinishNodeId, nodes)
                ImGui.TextDisabled("Choose point A and point B from the named city node list.")

                if ImGui.SmallButton("<##start_prev") then
                    draft.selectedStartNodeId = cycleNode(draft.selectedStartNodeId, nodes, -1, draft.selectedFinishNodeId)
                end
                ImGui.SameLine()
                ImGui.Text("Start:")
                ImGui.SameLine()
                ImGui.TextWrapped(nodeLabel(startNode))
                ImGui.SameLine()
                if ImGui.SmallButton(">##start_next") then
                    draft.selectedStartNodeId = cycleNode(draft.selectedStartNodeId, nodes, 1, draft.selectedFinishNodeId)
                end

                if ImGui.SmallButton("<##finish_prev") then
                    draft.selectedFinishNodeId = cycleNode(draft.selectedFinishNodeId, nodes, -1, draft.selectedStartNodeId)
                end
                ImGui.SameLine()
                ImGui.Text("Finish:")
                ImGui.SameLine()
                ImGui.TextWrapped(nodeLabel(finishNode))
                ImGui.SameLine()
                if ImGui.SmallButton(">##finish_next") then
                    draft.selectedFinishNodeId = cycleNode(draft.selectedFinishNodeId, nodes, 1, draft.selectedStartNodeId)
                end
            end
            elseif draft.routeMode == "root" then
            ensureRootRouteDefaults(draft, roots)
            if #roots == 0 then
                ImGui.TextDisabled("No valid named roots are available yet.")
                ImGui.TextDisabled("Use the Routes tab to create one from existing nodes.")
            else
                local selectedRoot = findRootById(draft.selectedRootId, roots) or roots[1]
                draft.selectedRootId = selectedRoot and selectedRoot.rootId or nil
                ImGui.TextDisabled("Choose a curated named route root.")
                if ImGui.BeginCombo("Named Root##route_root", rootPrimaryLabel(selectedRoot)) then
                    for _, root in ipairs(roots) do
                        local isSelected = root.rootId == draft.selectedRootId
                        if ImGui.Selectable(rootPrimaryLabel(root), isSelected) then
                            draft.selectedRootId = root.rootId
                        end
                    end
                    ImGui.EndCombo()
                end
                selectedRoot = findRootById(draft.selectedRootId, roots) or selectedRoot
                if selectedRoot then
                    local secondary = rootSecondaryLabel(selectedRoot)
                    if secondary then
                        ImGui.TextDisabled(secondary)
                    end
                    ImGui.TextDisabled(string.format(
                        "Path nodes: %d  |  %.0f m%s",
                        tonumber(selectedRoot.nodeCount or #(selectedRoot.nodeIds or {})),
                        tonumber(selectedRoot.distanceM or 0),
                        selectedRoot.isLoop == true and "  |  loop" or ""))
                    ImGui.TextWrapped("Path: " .. rootPathSummary(selectedRoot, 6))
                end
            end
            elseif draft.routeMode == "manual" then
            draft.useManualNodes = true
            ImGui.Text("Saved Route:")
            else
            draft.useManualNodes = false
            ImGui.TextDisabled("Random route picks from the named city pool.")
            end

            if draft.routeMode == "manual" then
            if hasManualPair then
                local startNode, finishNode = MTE.ManualNodes.getPair()
                ImGui.TextDisabled(string.format("Start: %s", startNode and startNode.name or "?"))
                ImGui.TextDisabled(string.format("Finish: %s", finishNode and finishNode.name or "?"))
            else
                draft.useManualNodes = false
                ImGui.TextDisabled("No saved manual pair yet.")
                ImGui.TextDisabled("Use CET console: MTE_SaveRaceStart(\"Start\", \"District\") then MTE_SaveRaceFinish(\"Finish\", \"District\")")
            end
            end
        end
    end

    if lockedCareerEvent then
        ImGui.EndDisabled()
        ImGui.Spacing()
        ImGui.TextDisabled("This career round launches from the stored season event definition.")
    end

    local quickRaceReport = quickRaceMode and not quickRaceKnockoutMode and racing.evaluateQuickRaceCompatibility
        and racing.evaluateQuickRaceCompatibility(draft)
        or nil
    if quickRaceMode and quickRaceReport then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.TextDisabled(string.format(
            "Field strength %s-%s suggests player cars around P%d-P%d.",
            tostring(quickRaceReport.tierMin),
            tostring(quickRaceReport.tierMax),
            tonumber(quickRaceReport.fieldPrestigeMin or 1),
            tonumber(quickRaceReport.fieldPrestigeMax or 5)))

        local vehicleToken = quickRaceReport.playerVehicleId and (quickRaceReport.playerVehicleId:match("[^%.]+$") or quickRaceReport.playerVehicleId) or "No mounted vehicle"
        if quickRaceReport.playerVehicleMeta then
            ImGui.TextDisabled(string.format("Current car: %s  |  %s  |  P%d",
                vehicleToken,
                tostring(quickRaceReport.playerVehicleMeta.carClass or quickRaceReport.playerVehicleClass or "Unknown"),
                tonumber(quickRaceReport.playerVehicleMeta.prestige or 0)))
        else
            ImGui.TextDisabled(string.format("Current car: %s", vehicleToken))
        end

        for _, msg in ipairs(quickRaceReport.blockingIssues or {}) do
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.35, 0.35, 1.0)
            ImGui.TextWrapped(msg)
            ImGui.PopStyleColor()
        end
        if not quickRaceReport.isBlocking then
            for _, msg in ipairs(quickRaceReport.warnings or {}) do
                ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.75, 0.25, 1.0)
                ImGui.TextWrapped(msg)
                ImGui.PopStyleColor()
            end
        end
    end

    ImGui.Spacing()
    local confirmBlocked = (quickRaceMode and quickRaceReport and quickRaceReport.isBlocking)
        or (quickRaceKnockoutMode and selectedKnockoutCircuit == nil)
        or (quickRaceEnduranceMode and selectedEnduranceCircuit == nil)
    if confirmBlocked then ImGui.BeginDisabled() end
    if ImGui.Button("Confirm & Preview", s(160), s(28)) then
        local ok, err = nil, nil
        if quickRaceKnockoutMode then
            ok, err = launchQuickRaceKnockout(draft)
        else
            local callOk = nil
            callOk, ok, err = pcall(MTE.Racing.confirmConfig, draft)
            if not callOk then
                _errorMsg = "Confirm failed: " .. tostring(ok)
                ok = false
            end
        end

        if ok then
            if quickRaceMode and racing.persistQuickRaceDraft then
                racing.persistQuickRaceDraft(draft)
            end
            _errorMsg = nil
        elseif err then
            _errorMsg = err
        end
    end
    if confirmBlocked then ImGui.EndDisabled() end
    ImGui.SameLine()
    if ImGui.Button("Cancel", s(80), s(28)) then
        MTE.Racing.abort()
    end
end

function UIR._drawPreRacePanel()
    local cfg   = MTE.Racing.getConfig()
    if cfg ~= UIR._lastCfg then
        UIR._lastCfg = cfg
        _stakeInputBuf = { "0" }
        _stakeParsed = 0
    end
    local field = MTE.Racing.getField()
    local career = MTE.Careers.active()

    ImGui.Text("RACE PREVIEW")
    ImGui.Separator()

    -- Route info
    local nodeA = cfg.nodeA or {}
    local nodeB = cfg.nodeB or {}
    ImGui.Text(string.format("Route:    %s  ->  %s", nodeA.name or "?", nodeB.name or "?"))
    ImGui.Text(string.format("District: %s    Distance: %.0f m    ~%.1f s",
        cfg.district or "?", cfg.distance or 0, cfg.expectedTime or 0))
    ImGui.Text(string.format("Start: %s    Field: %d drivers + YOU",
        cfg.startType or "?", #field))

    -- Heat warning
    if cfg.district and MTE.Heat then
        local hl = MTE.Heat.levelName(cfg.district)
        if hl ~= "Clean" then
            local hr, hg, hb, ha = heatColor(MTE.Heat.get(cfg.district))
            ImGui.PushStyleColor(ImGuiCol.Text, hr, hg, hb, ha)
            ImGui.Text(string.format("! Heat: %s in %s - faction interference possible", hl, cfg.district))
            ImGui.PopStyleColor()
        end
    end

    ImGui.Spacing()

    -- Grid formation display
    ImGui.PushStyleColor(ImGuiCol.Text, 0.37, 0.96, 1.0, 1.0)
    ImGui.Text(string.format("START GRID  (%s)", (cfg.startType or "grid"):upper()))
    ImGui.PopStyleColor()
    ImGui.Separator()

    -- Player grid position should mirror the live staging logic rather than assuming pole by default.
    local playerGridPos = (MTE.Racing.getPlayerGridPosForStart and MTE.Racing.getPlayerGridPosForStart(cfg.startType, #field + 1))
        or MTE.Racing.getQualiGridPos()
        or 1

    -- Build combined grid with player + AI drivers
    local gridSlots = {}
    local aiIdx = 1
    for pos = 1, #field + 1 do
        if pos == playerGridPos then
            gridSlots[pos] = { isPlayer = true }
        else
            gridSlots[pos] = { isPlayer = false, driver = field[aiIdx] }
            aiIdx = aiIdx + 1
        end
    end

    -- Formation slot markers from ai_vehicles
    local formation = aiActive and MTE.AIVehicles.getFormation() or {}

    for pos, slot in ipairs(gridSlots) do
        if slot.isPlayer then
            -- Player row
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.93, 0.33, 1)
            local readyMark = "*"
            ImGui.Text(string.format("  P%d  %s  %-20s  << YOU", pos, readyMark, "V"))
            ImGui.PopStyleColor()
        else
            local driver = slot.driver
            if driver then
                local c = driver.color or { 0.8, 0.8, 0.8 }
                ImGui.PushStyleColor(ImGuiCol.Text, c[1], c[2], c[3], 1)

                -- Check if this AI car is spawned and ready
                local fIdx = pos > playerGridPos and (pos - 1) or pos
                local readyMark = "."
                if formation[fIdx] and formation[fIdx].phase == "ready" then
                    readyMark = "*"
                elseif formation[fIdx] and formation[fIdx].phase == "driving" then
                    readyMark = "*"
                end

                local driverName = driver.displayName or driver.name or driver.id or "?"
                local skull = (career and MTE.Careers.hasBounty(career, driver.driverId or driver.id)) and " [BOUNTY]" or ""
                -- Show faction for all drivers: roster drivers use factionName, heat-injected use driver.faction
                local factionTag = driver.factionName or (driver.isFaction and driver.faction) or ""
                local faction = factionTag ~= "" and string.format(" [%s]", factionTag:sub(1, 12)) or ""
                local rival = ""
                if (driver.rivalScore or 0) > 0 then
                    rival = string.format(" [RIVAL %d]", driver.rivalScore)
                end
                ImGui.Text(string.format("  P%d  %s  %-20s  pace=%.2f  %s%s%s%s",
                    pos, readyMark, driverName, driver.pace or 0,
                    driver.personality or "", skull, faction, rival))
                ImGui.PopStyleColor()
            end
        end
    end

    ImGui.Spacing()
    ImGui.TextDisabled("* = on grid    . = spawning")

    ImGui.Spacing()
    ImGui.Separator()

    -- Stakes
    -- allowStakes is authoritative from Racing._config (set by championship
    -- ruleset via applySeasonConfig); fall back to career setting when no
    -- config is live yet (e.g. career tab viewed while not in pre-race).
    local raceCfg         = MTE.Racing.getConfig()
    local stakesAllowed   = raceCfg and raceCfg.allowStakes
    if stakesAllowed == nil then
        stakesAllowed = career and career.config and career.config.allowStakes
    end
    if career and stakesAllowed then
        local maxStake = MTE.Careers.maxStake(career)
        ImGui.Text(string.format("Stake (max %d eddies):", maxStake))
        ImGui.SameLine()
        ImGui.SetNextItemWidth(100)
        local buf, changed = ImGui.InputText("##stake", _stakeInputBuf[1], 12)
        if changed then
            _stakeInputBuf[1] = buf
            _stakeParsed = tonumber(buf) or 0
        end
        ImGui.SameLine()
        if ImGui.SmallButton("Set##stake") then
            local actual = MTE.Racing.setStake(_stakeParsed)
            _stakeInputBuf[1] = tostring(actual)
        end
        local cur = MTE.Racing.getStake()
        if cur > 0 then
            ImGui.SameLine()
            ImGui.TextDisabled(string.format("  Wagering %d eddies", cur))
        end
    end

    ImGui.Spacing()

    -- Quali
    if cfg.qualiEnabled and not MTE.Racing.getQualiStandings() then
        if ImGui.Button("Go to Quali Start", s(148), s(28)) then
            MTE.Racing.teleportToStart()
        end
        ImGui.SameLine()
        if ImGui.Button("Start Qualifying", s(155), s(28)) then
            MTE.Racing.startQuali()
        end
        ImGui.SameLine()
        ImGui.TextDisabled(" (or drive to start â€” auto-triggers)")
    end

    -- Quali standings (shown after qualifying is completed)
    local qualiStandings = MTE.Racing.getQualiStandings()
    if qualiStandings then
        ImGui.Spacing()
        ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.8, 0.1, 1)
        ImGui.Text("QUALIFYING RESULTS")
        ImGui.PopStyleColor()
        ImGui.Separator()
        for i, qs in ipairs(qualiStandings) do
            local r, g, b, a = posColor(i)
            if qs.isPlayer then r, g, b = 1.0, 0.93, 0.33 end
            ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, 1)
            local mark = qs.isPlayer and "  << YOU" or ""
            ImGui.Text(string.format("  P%d  %-18s  %s%s", i, qs.name, fmtTime(qs.time), mark))
            ImGui.PopStyleColor()
        end
        ImGui.Spacing()
    end

    -- Race-start gating: check spawn readiness before showing start button
    local _launchable   = MTE.AIVehicles and MTE.AIVehicles.launchableCount() or 0
    local _stagedTotal  = MTE.AIVehicles and MTE.AIVehicles.totalCount() or 0
    local _fieldTotal   = #(MTE.Racing.getField() or {})
    local _total        = math.max(_stagedTotal, _fieldTotal)
    local _spawnPending = MTE.Racing.isGridSpawnPending and MTE.Racing.isGridSpawnPending() or false
    local _spawning     = _spawnPending or (MTE.AIVehicles and MTE.AIVehicles.isSpawning() or false)
    local _gridSummary  = MTE.AIVehicles and MTE.AIVehicles.getGridSummary and MTE.AIVehicles.getGridSummary() or nil
    local _startReady, _startReason = MTE.Racing.getStartReadiness()
    local _snapEnabled      = MTE.Racing.isPlayerGridSnapEnabled and MTE.Racing.isPlayerGridSnapEnabled() or true
    local _staged           = MTE.Racing._autoStageTriggered or ((not _snapEnabled) and _startReady)
    local _snapCooldown     = MTE.Racing._postSnapCooldown or 0
    local _stageCountdown   = MTE.Racing._stageCountdown
    local _prelaunch        = MTE.Racing._prelaunchCountdown
    local _qualiPending     = cfg.qualiEnabled and not MTE.Racing.getQualiStandings()

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- â”€â”€ Status line (explains what the mod is doing right now) â”€â”€
    if _qualiPending then
        -- nothing here; handled in buttons below
    elseif _prelaunch then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 1.0, 0.3, 1)
        ImGui.Text(string.format("RACE IN %d...", math.ceil(_prelaunch)))
        ImGui.PopStyleColor()
    elseif _staged and _spawning then
        local ready = MTE.AIVehicles and MTE.AIVehicles.readyCount() or 0
        local total = MTE.AIVehicles and MTE.AIVehicles.totalCount() or _fieldTotal
        ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.7, 0.1, 1)
        ImGui.Text(string.format("Rival cars forming up...  %d / %d", ready, total))
        ImGui.PopStyleColor()
        ImGui.ProgressBar(total > 0 and (ready / total) or 0, -1, 6, "")
        if _gridSummary then
            local gateReason = _gridSummary.gateReason or _gridSummary.reason or ""
            if gateReason ~= "" then
                ImGui.TextDisabled(string.format("Grid phase: %s  (%s)", tostring(_gridSummary.phase or "?"), tostring(gateReason)))
            else
                ImGui.TextDisabled(string.format("Grid phase: %s", tostring(_gridSummary.phase or "?")))
            end
        end
    elseif _staged and _snapCooldown > 0 then
        local secsLeft = math.ceil(_snapCooldown)
        local zoneMsg = secsLeft > 5 and "Clearing zone..." or
                        secsLeft > 3 and "Traffic dispersing..." or
                        secsLeft > 1 and "Almost ready..." or "Stand by..."
        ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.8, 0.6, 1)
        ImGui.Text(string.format("%s  (%ds)", zoneMsg, secsLeft))
        ImGui.PopStyleColor()
        ImGui.ProgressBar(1.0 - (_snapCooldown / 8.0), -1, 5, "")
    elseif _stageCountdown then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 1.0, 0.4, 1)
        ImGui.Text(string.format("STAGING IN %d...", math.ceil(_stageCountdown)))
        ImGui.PopStyleColor()
    elseif not _staged then
        local dist = MTE.Racing._distToNode and MTE.Racing._config and
                     MTE.Racing._distToNode(MTE.Racing._config.nodeA)
        local distStr = dist and string.format("  (%.0f m away)", dist) or ""
        ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.9, 0.4, 1)
        if _snapEnabled then
            ImGui.Text(string.format("Drive to: %s%s", cfg.nodeA and cfg.nodeA.name or "start", distStr))
        else
            ImGui.Text(string.format("Drive into grid: %s%s", cfg.nodeA and cfg.nodeA.name or "start", distStr))
        end
        ImGui.PopStyleColor()
    end

    if not _staged and _total > 0 and _launchable == 0 and not _spawning then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.4, 0.2, 1)
        ImGui.TextWrapped("No AI cars on grid â€” ghost race (time only).")
        ImGui.PopStyleColor()
    elseif not _staged and _total > 0 and _launchable < _total and not _spawning then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.7, 0.2, 1)
        ImGui.Text(string.format("Partial grid: %d / %d launchable", _launchable, _total))
        ImGui.PopStyleColor()
    end

    ImGui.Spacing()

    -- â”€â”€ Buttons â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if _qualiPending then
        ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 1)
        ImGui.Button("QUALIFY FIRST", s(160), s(28))
        ImGui.PopStyleColor()
    elseif _prelaunch then
        -- Pre-launch countdown running â€” no button, but keep Cancel
        ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 1)
        ImGui.Button("Launching...", s(130), s(28))
        ImGui.PopStyleColor()
    elseif _staged and _spawning then
        ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 1)
        ImGui.Button("Forming grid...", s(130), s(28))
        ImGui.PopStyleColor()
    elseif _staged and _snapCooldown > 0 then
        ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 1)
        ImGui.Button(string.format("Zone clear in %ds...", math.ceil(_snapCooldown)), 160, 28)
        ImGui.PopStyleColor()
    elseif _staged and _startReady then
        -- Fully staged and ready â€” manual START (e.g. post-quali)
        ImGui.PushStyleColor(ImGuiCol.Button,        0.1, 0.7, 0.2, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.2, 0.9, 0.3, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive,  0.0, 0.5, 0.1, 1.0)
        if ImGui.Button("START RACE", s(130), s(28)) then
            MTE.Racing.startRace()
        end
        ImGui.PopStyleColor(3)
    else
        -- Not yet staged â€” warp button
    end
    if ImGui.Button("Cancel", s(80), s(28)) then
        MTE.Racing.abort()
    end

    -- Debug telemetry: spawn report (gated behind setting)
    local dbg = MTE.Settings and MTE.Settings.current and MTE.Settings.current.debugTelemetry
    if dbg and MTE.AIVehicles and MTE.AIVehicles.getSpawnReport then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1)
        ImGui.Text("DEBUG: Spawn Report")
        ImGui.PopStyleColor()
        local report = MTE.AIVehicles.getSpawnReport()
        for _, sr in ipairs(report) do
            local clr = sr.launchable and {0.3, 0.8, 0.3} or {0.8, 0.3, 0.3}
            ImGui.PushStyleColor(ImGuiCol.Text, clr[1], clr[2], clr[3], 1)
            local fail = sr.failureReason and (" FAIL:" .. sr.failureReason) or ""
            ImGui.Text(string.format("  [%d] %-16s  %s  veh=%s app=%s%s",
                sr.slotIndex, sr.driverName or "?",
                sr.phase or "?",
                sr.vehRecord and sr.vehRecord:match("[^%.]+$") or "nil",
                sr.appearance or "stock", fail))
            ImGui.PopStyleColor()
        end
    end
end

function UIR._drawQualiPanel()
    local t    = MTE.Racing.getRaceTimer()
    local cfg  = MTE.Racing.getConfig()
    local dest = (cfg.nodeB or {}).name or "Finish"
    ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.8, 0.1, 1)
    ImGui.Text("QUALIFYING LAP")
    ImGui.PopStyleColor()
    ImGui.Text(string.format("Drive to: %s", dest))
    ImGui.Text(string.format("Time: %s", fmtTime(t)))
    ImGui.Spacing()
    if ImGui.Button("Abort Quali", s(110), s(24)) then
        MTE.Racing.abort()
    end
end

function UIR._drawCountdownPanel()
    local t = MTE.Racing.getRaceTimer()
    local cfg = MTE.Racing.getConfig()

    ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.9, 0.1, 1)
    ImGui.Text(string.format("  GO in  %.1f", math.max(0, t)))
    ImGui.PopStyleColor()

    -- Show grid during countdown
    if MTE.AIVehicles and MTE.AIVehicles.isActive() then
        ImGui.Spacing()
        ImGui.Text(string.format("%s START  |  %d cars on grid",
            (cfg.startType or "grid"):upper(),
            MTE.AIVehicles.readyCount()))
    end

    ImGui.Spacing()
    if ImGui.Button("Abort", s(80), s(22)) then
        MTE.Racing.abort()
    end
end

function UIR._drawRacingPanel()
    local t   = MTE.Racing.getRaceTimer()
    local cfg = MTE.Racing.getConfig()
    local dest = (cfg.nodeB or {}).name or "Finish"

    ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 1.0, 0.4, 1)
    ImGui.Text("  RACING")
    ImGui.PopStyleColor()
    ImGui.Text(string.format("Target: %s", dest))
    ImGui.Text(string.format("Time:   %s", fmtTime(t)))

    -- Distance to finish
    local dist = MTE.Racing.getDistanceToFinish()
    if dist then
        if dist > 1000 then
            ImGui.SameLine()
            ImGui.TextDisabled(string.format("  %.1f km to go", dist / 1000))
        else
            ImGui.SameLine()
            ImGui.TextDisabled(string.format("  %d m to go", math.floor(dist)))
        end
    end

    if cfg.expectedTime and cfg.expectedTime > 0 then
        ImGui.ProgressBar(math.min(1, t / cfg.expectedTime), -1, 10, "")
    end

    ImGui.Spacing()

    -- Live standings
    ImGui.PushStyleColor(ImGuiCol.Text, 0.37, 0.96, 1.0, 1.0)
    ImGui.Text("STANDINGS")
    ImGui.PopStyleColor()
    ImGui.Separator()

    local standings = MTE.Racing.getLiveStandings()
    for i, entry in ipairs(standings) do
        local r, g, b, a = posColor(i)
        if entry.isPlayer then
            r, g, b = 1.0, 0.93, 0.33
        end
        ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, 1)

        local driverName = entry.name or "?"
        if #driverName > 16 then driverName = driverName:sub(1, 16) end
        local finMark = entry.finished and " FIN" or ""
        local youMark = entry.isPlayer and "  << YOU" or ""

        ImGui.Text(string.format("  P%d  %-18s  %s%s%s",
            i, driverName, fmtTime(entry.time), finMark, youMark))
        ImGui.PopStyleColor()
    end

    ImGui.Spacing()
    if ImGui.Button("DNF / Abort", s(110), s(22)) then
        MTE.Racing.abort()
    end

    -- Debug telemetry: live slot status during race
    local dbg = MTE.Settings and MTE.Settings.current and MTE.Settings.current.debugTelemetry
    if dbg and MTE.AIVehicles and MTE.AIVehicles.getSpawnReport then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1)
        ImGui.Text(string.format("DEBUG: Slots  (launchable %d / %d)",
            MTE.AIVehicles.launchableCount(), MTE.AIVehicles.totalCount()))
        ImGui.PopStyleColor()
        if _gridSummary then
            ImGui.TextDisabled(string.format(
                "Grid: phase=%s next=%s reason=%s gate=%s",
                tostring(_gridSummary.phase or "?"),
                tostring(_gridSummary.nextSlotIndex or "?"),
                tostring(_gridSummary.reason or ""),
                tostring(_gridSummary.gateReason or "")))
        end
        local report = MTE.AIVehicles.getSpawnReport()
        for _, sr in ipairs(report) do
            local clr = sr.launchable and {0.3, 0.7, 0.3} or {0.6, 0.3, 0.3}
            ImGui.PushStyleColor(ImGuiCol.Text, clr[1], clr[2], clr[3], 1)
            local fail = sr.failureReason and (" FAIL:" .. sr.failureReason) or ""
            ImGui.Text(string.format("  [%d] %-14s %s%s",
                sr.slotIndex, sr.driverName or "?", sr.phase or "?", fail))
            ImGui.PopStyleColor()
        end
    end
end

function UIR._drawResultsPanel()
    local data = _lastResultCache
    if not data then
        -- Poll from last emitted event stored in Racing module
        ImGui.Text("Results loading...")
        if ImGui.Button("Close", s(80), s(24)) then MTE.Racing.closeResults() end
        return
    end

    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.9, 0.2, 1)
    ImGui.Text(string.format("FINISH  --  P%d  --  %s", data.position, fmtTime(data.playerTime)))
    ImGui.PopStyleColor()

    ImGui.Separator()

    -- Results table
    if data.results then
        for i, entry in ipairs(data.results) do
            local r, g, b, a = posColor(i)
            ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
            local mark = entry.isPlayer and "  <- YOU" or ""
            local fTag = entry.factionName and entry.factionName ~= "" and
                string.format(" [%s]", entry.factionName:sub(1, 12)) or ""
            ImGui.Text(string.format("  P%d  %-22s  %s%s%s",
                i, entry.name or "?", fmtResultMetric(entry), fTag, mark))
            ImGui.PopStyleColor()
        end
    end

    ImGui.Spacing()
    ImGui.Separator()

    -- Stat breakdown
    if data.isDNF then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.3, 0.3, 1)
        ImGui.Text("DNF")
        ImGui.PopStyleColor()
    else
        if data.isClean then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 1, 0.4, 1)
            ImGui.Text("  + Clean run bonus")
            ImGui.PopStyleColor()
        end
        if data.wagerWon then
            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.85, 0.1, 1)
            ImGui.Text("  + Wager won!")
            ImGui.PopStyleColor()
        end
        if data.wagerLost then
            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.2, 0.2, 1)
            ImGui.Text(string.format("  - Wager lost: -%d eddies", data.wagerAmount or 0))
            ImGui.PopStyleColor()
        end
        if data.bountyResolved then
            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.4, 0.9, 1)
            ImGui.Text("  + Bounty resolved!")
            ImGui.PopStyleColor()
        end
    end

    local repSign = (data.repGain or 0) >= 0 and "+" or ""
    ImGui.Text(string.format("Rep: %s%d     Payout: %d eddies",
        repSign, data.repGain or 0, data.payout or 0))

    local hype = data.hype
    if type(hype) == "table" and tonumber(hype.index) and tonumber(hype.multiplier) then
        local hypeLabel = (MTE.Hype and MTE.Hype.label and MTE.Hype.label(hype.index)) or "LIVE"
        ImGui.Text(string.format("Hype: %.2f (%s)     Multiplier: x%.2f",
            tonumber(hype.index) or 1.0,
            tostring(hypeLabel),
            tonumber(hype.multiplier) or 1.0))
    end

    if data.safetyRating then
        local sr = data.safetyRating
        local delta = tonumber(sr.deltaSR) or 0.0
        local deltaSign = delta >= 0 and "+" or ""
        local counts = sr.incidentCounts or {}

        ImGui.Spacing()
        if delta >= 0 then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 0.85, 0.3, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.45, 0.1, 1.0)
        end
        ImGui.Text(string.format("%s: %s  (%s%.2f)",
            tostring(sr.scopeLabel or "Safety Rating"),
            fmtSafetyRating(sr.afterSR),
            deltaSign,
            delta))
        ImGui.PopStyleColor()
        ImGui.Text(string.format("Incident Points: %d    1x: %d    2x: %d    4x: %d    Distance: %s",
            sr.incidentPoints or 0,
            counts["1x"] or 0,
            counts["2x"] or 0,
            counts["4x"] or 0,
            fmtDistanceKm(sr.distanceM)))
    end

    -- Career tier progress
    local career = MTE.Careers.active()
    if career then
        local tc = tierColor(career.tier)
        ImGui.PushStyleColor(ImGuiCol.Text, tc[1], tc[2], tc[3], tc[4])
        ImGui.Text(string.format("[%s] %d rep", career.tier, career.rep))
        ImGui.PopStyleColor()
        local _, repCeil2 = MTE.Careers.repThresholds(career)
        local barText2 = repCeil2 and string.format("%d / %d", career.rep, repCeil2) or string.format("%d", career.rep)
        ImGui.ProgressBar(MTE.Careers.repProgress(career), -1, 10, barText2)
    end

    ImGui.Spacing()
    if ImGui.Button("Close", s(100), s(26)) then
        _lastResultCache = nil
        MTE.Racing.closeResults()
    end
    ImGui.SameLine()
    if ImGui.Button("Restart", s(100), s(26)) then
        _lastResultCache = nil
        MTE.Racing.restartRace()
    end
end

-- â”€â”€ Tab 2: Career management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR._drawCareerTab()
    local careers = MTE.Careers.list()
    local active  = MTE.Careers.active()

    ImGui.Text("Careers")
    ImGui.Separator()
    ImGui.Spacing()

    -- Create new career
    ImGui.Text("New career name:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(160)
    local buf, ch = ImGui.InputText("##newcareer", _newCareerBuf[1], 40)
    if ch then _newCareerBuf[1] = buf end
    ImGui.Spacing()
    ImGui.Text("Season event mix:")
    for _, option in ipairs(CAREER_EVENT_MIX_OPTIONS) do
        ImGui.SameLine()
        local selected = _newCareerEventMix == option.id
        if selected then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.6, 0.2, 1) end
        if ImGui.SmallButton(option.label .. "##career_mix_" .. option.id) then
            _newCareerEventMix = option.id
        end
        if selected then ImGui.PopStyleColor() end
    end
    local knockoutFinale, knockoutChanged = ImGui.Checkbox("Last race is knockout", _newCareerLastRaceKnockout)
    if knockoutChanged then _newCareerLastRaceKnockout = knockoutFinale end
    ImGui.TextDisabled("Applies to newly created careers only.")
    ImGui.Spacing()
    if ImGui.SmallButton("Create") then
        if _newCareerBuf[1] ~= "" then
            local c = MTE.Careers.create(_newCareerBuf[1], nil, normalizeNewCareerChampionshipConfig())
            MTE.Careers.select(c.id)
            _newCareerBuf[1] = _newCareerName
            resetNewCareerChampionshipConfig()
        end
    end

    ImGui.Spacing()
    ImGui.Separator()

    -- List existing careers
    for _, c in ipairs(careers) do
        local isActive = (active and active.id == c.id)
        local tc = tierColor(c.tier)
        local careerSR = MTE.SafetyRating and MTE.SafetyRating.getCareerProfile and MTE.SafetyRating.getCareerProfile(c) or nil
        local srText = careerSR and fmtSafetyRating(careerSR.currentSR) or "--"

        ImGui.PushStyleColor(ImGuiCol.Text, tc[1], tc[2], tc[3], tc[4])
        ImGui.Text(string.format("[%s]", c.tier))
        ImGui.PopStyleColor()
        ImGui.SameLine()
        ImGui.Text(string.format("%-22s  Rep: %-6d  Races: %d  SR: %s",
            c.name, c.rep, c.stats.racesRun, srText))

        ImGui.SameLine()
        if isActive then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.1, 0.5, 0.1, 1)
            ImGui.SmallButton("ACTIVE##" .. c.id)
            ImGui.PopStyleColor()
        else
            if ImGui.SmallButton("Select##" .. c.id) then
                MTE.Careers.select(c.id)
            end
        end

        ImGui.SameLine()
        if ImGui.SmallButton("Del##" .. c.id) then
            _confirmDelete = c.id
        end

        -- Confirm delete modal
        if _confirmDelete == c.id then
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.3, 0.3, 1)
            ImGui.Text("Sure?")
            ImGui.PopStyleColor()
            ImGui.SameLine()
            if ImGui.SmallButton("Yes##dely") then
                MTE.Careers.delete(c.id)
                _confirmDelete = nil
            end
            ImGui.SameLine()
            if ImGui.SmallButton("No##deln") then
                _confirmDelete = nil
            end
        end
    end

    if #careers == 0 then
        ImGui.TextDisabled("No careers yet. Create one above.")
        return
    end

    if active and MTE.SafetyRating and MTE.SafetyRating.getCareerProfile then
        ImGui.Spacing()
        ImGui.Separator()
        drawSafetyRatingSummary("Active Career Safety Rating", MTE.SafetyRating.getCareerProfile(active))
    end
end

-- â”€â”€ Tab 3: Leaderboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR._drawLeaderboardTab()
    local career = MTE.Careers.active()
    if not career then
        ImGui.TextDisabled("No active career.")
        return
    end

    ImGui.Text("Leaderboard")
    ImGui.Separator()

    -- Tier picker
    ImGui.Text("Tier:")
    for i, tl in ipairs(TIER_LABELS) do
        ImGui.SameLine()
        local sel = (_selectedTier == i)
        if sel then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1) end
        if ImGui.SmallButton(tl .. "##lbtab") then _selectedTier = i end
        if sel then ImGui.PopStyleColor() end
    end

    ImGui.Spacing()

    local tier    = TIER_LABELS[_selectedTier]
    local board   = MTE.Roster.getLeaderboard(career, tier, 0)
    ImGui.TextDisabled(string.format("Showing %d drivers in %s", #board, tier))

    -- Player's own entry header
    local tc = tierColor(career.tier)
    if career.tier == tier then
        ImGui.PushStyleColor(ImGuiCol.Text, tc[1], tc[2], tc[3], tc[4])
        ImGui.Text(string.format("  YOU  %-22s  Rep: %d", "V", career.rep))
        ImGui.PopStyleColor()
        ImGui.Separator()
    end

    if #board == 0 then
        ImGui.TextDisabled("No drivers scouted yet in this tier.")
        return
    end

    if ImGui.BeginChild("##fullLeaderboard", 0, 260, true) then
        for i, entry in ipairs(board) do
            local c = entry.color or { 0.8, 0.8, 0.8 }
            ImGui.PushStyleColor(ImGuiCol.Text, c[1], c[2], c[3], 1)
            ImGui.Text(string.format("  %3d. %-22s  Rep: %-6d  Wins: %d",
                i, entry.name or entry.displayName or "?", entry.rep or 0, entry.wins or 0))
            ImGui.PopStyleColor()
        end
        ImGui.EndChild()
    end

    -- â”€â”€ Route Records â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.PushStyleColor(ImGuiCol.Text, 0.37, 0.96, 1.0, 1.0)
    ImGui.Text("ROUTE RECORDS")
    ImGui.PopStyleColor()
    ImGui.Separator()

    local routes = MTE.Records and MTE.Records.allRoutes(career) or {}
    if #routes == 0 then
        ImGui.TextDisabled("No route records yet. Finish races to set times.")
    else
        for _, r in ipairs(routes) do
            local routeName = r.routeKey or "?"
            if MTE.Tracks and MTE.Tracks.getNameByIds then
                local named = MTE.Tracks.getNameByIds(r.nodeA, r.nodeB)
                if named then routeName = named end
            end
            ImGui.Text(string.format("  %-28s  %s  (%d recorded)",
                routeName, fmtTime(r.fastest), r.boardSize or 0))
        end
    end
end

-- â”€â”€ Tab 4: Heat map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR._drawHeatTab()
    ImGui.Text("Faction Heat by District")
    ImGui.Separator()
    ImGui.Spacing()

    local summary = MTE.Heat.summary()
    if #summary == 0 then
        ImGui.TextDisabled("No active heat. Keep racing to build it.")
        return
    end

    for _, row in ipairs(summary) do
        local r, g, b, a = heatColor(row.heat)
        ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, a)
        ImGui.ProgressBar(row.heat / 100.0, s(180), s(14), "")
        ImGui.PopStyleColor()
        ImGui.SameLine()
        ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
        ImGui.Text(string.format("%-14s  %-9s  [%s]",
            row.district, row.faction, row.levelName))
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.SmallButton("Reset##heat_" .. row.district) then
            MTE.Heat.resetDistrict(row.district)
        end
    end

    -- Districts with no heat
    for dist, _ in pairs(MTE.Heat.FACTION_MAP) do
        if MTE.Heat.get(dist) == 0 then
            ImGui.TextDisabled(string.format("  %-14s  Clean", dist))
        end
    end
end

-- â”€â”€ Tab 5: Race history â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR._drawHistoryTab()
    local career = MTE.Careers.active()
    if not career then
        ImGui.TextDisabled("No active career.")
        return
    end

    ImGui.Text(string.format("Recent Races - %s", career.name))
    ImGui.Separator()

    if MTE.RaceTelemetry and MTE.RaceTelemetry.getRecentRouteSummaries then
        local routeBooks = MTE.RaceTelemetry.getRecentRouteSummaries(5)
        ImGui.PushStyleColor(ImGuiCol.Text, 0.37, 0.96, 1.0, 1.0)
        ImGui.Text("ROUTE BOOK")
        ImGui.PopStyleColor()
        ImGui.Separator()

        if #routeBooks == 0 then
            ImGui.TextDisabled("No route history yet. Finish a race to start building route books.")
        else
            for _, book in ipairs(routeBooks) do
                local bestFinish = book.bestFinish and ("P" .. tostring(book.bestFinish)) or "--"
                local avgFinish = book.averageFinish and string.format("P%.1f", book.averageFinish) or "--"
                ImGui.Text(string.format("  %-28s  A:%d  F:%d  D:%d",
                    book.routeDisplayName or book.routeId or "Unknown Route",
                    book.attempts or 0,
                    book.finishes or 0,
                    book.dnfs or 0))
                ImGui.TextDisabled(string.format("     Best %s  Lap %s  S1 %s  S2 %s  S3 %s",
                    fmtTime(book.bestTotalRaceTime),
                    fmtTime(book.bestLap),
                    fmtTime(book.bestSector1),
                    fmtTime(book.bestSector2),
                    fmtTime(book.bestSector3)))
                ImGui.TextDisabled(string.format("     Finish %s avg %s  Race avg %s  Lap avg %s",
                    bestFinish,
                    avgFinish,
                    fmtTime(book.averageRaceTime),
                    fmtTime(book.averageLapTime)))
                local last = book.recentAttempts and book.recentAttempts[1] or nil
                if last then
                    local lastStatus = last.finishStatus == "finished"
                        and ("P" .. tostring(last.position or 0))
                        or string.upper(last.finishStatus or "?")
                    ImGui.TextDisabled(string.format("     Last: %-10s  %s",
                        lastStatus,
                        fmtTime(last.totalRaceTime)))
                end
                ImGui.Spacing()
            end
        end

        ImGui.Separator()
    end

    local history = career.raceHistory or {}
    if #history == 0 then
        ImGui.TextDisabled("No races recorded yet.")
        return
    end

    for _, r in ipairs(history) do
        local posStr = r.dnf and "DNF" or string.format("P%d", r.position or 0)
        local posCol = r.dnf and { 1, 0.3, 0.3, 1 } or
                       (r.position == 1 and { 1, 0.85, 0.1, 1 } or { 0.8, 0.8, 0.8, 1 })
        ImGui.PushStyleColor(ImGuiCol.Text, posCol[1], posCol[2], posCol[3], posCol[4])
        ImGui.Text(string.format("  %-4s", posStr))
        ImGui.PopStyleColor()
        ImGui.SameLine()
        local repSign = (r.repGain or 0) >= 0 and "+" or ""
        ImGui.Text(string.format("%-12s  %s  Rep %s%d  %d \xe2\x82\xac$",
            r.district or "?", fmtTime(r.time),
            repSign, r.repGain or 0, r.payout or 0))
    end
end
-- â”€â”€ Tab 6: Stats â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR._drawStatsTab()
    local career = MTE.Careers.active()
    if not career then
        ImGui.TextDisabled("No active career. Select one on the Career tab.")
        return
    end

    -- Career name + tier header
    local tc = tierColor(career.tier)
    ImGui.PushStyleColor(ImGuiCol.Text, tc[1], tc[2], tc[3], tc[4])
    ImGui.Text(string.format("%s   [%s]   S%d",
        career.name, career.tier, career.seasonNumber or 1))
    ImGui.PopStyleColor()
    ImGui.Separator()

    local st = MTE.Careers.getStats(career)

    -- Helper: two-column row
    local function row(label, val)
        ImGui.TextDisabled(string.format("%-18s", label))
        ImGui.SameLine()
        ImGui.Text(tostring(val))
    end

    -- â”€â”€ Counts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.8, 1.0, 1.0)
    ImGui.Text("  Counts")
    ImGui.PopStyleColor()
    ImGui.Columns(2, "stats_counts", false)
    ImGui.SetColumnWidth(0, 150)

    ImGui.TextDisabled("Races Run")   ; ImGui.NextColumn() ; ImGui.Text(tostring(st.racesRun))      ; ImGui.NextColumn()
    ImGui.TextDisabled("Races Fin.")  ; ImGui.NextColumn() ; ImGui.Text(tostring(st.racesFinished)) ; ImGui.NextColumn()
    ImGui.TextDisabled("DNFs")        ; ImGui.NextColumn() ; ImGui.Text(tostring(st.dnfs))          ; ImGui.NextColumn()
    ImGui.NextColumn() ; ImGui.NextColumn()  -- spacer
    ImGui.TextDisabled("Wins")        ; ImGui.NextColumn() ; ImGui.Text(tostring(st.wins))          ; ImGui.NextColumn()
    ImGui.TextDisabled("Podiums")     ; ImGui.NextColumn() ; ImGui.Text(tostring(st.podiums))       ; ImGui.NextColumn()
    ImGui.TextDisabled("Top 5s")      ; ImGui.NextColumn() ; ImGui.Text(tostring(st.top5s))         ; ImGui.NextColumn()
    ImGui.TextDisabled("Poles")       ; ImGui.NextColumn() ; ImGui.Text(tostring(st.poles))         ; ImGui.NextColumn()

    ImGui.Columns(1)
    ImGui.Separator()

    -- â”€â”€ Rates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.8, 1.0, 1.0)
    ImGui.Text("  Rates")
    ImGui.PopStyleColor()
    ImGui.Columns(2, "stats_rates", false)
    ImGui.SetColumnWidth(0, 150)

    ImGui.TextDisabled("Win Rate")    ; ImGui.NextColumn() ; ImGui.Text(st.winRate)    ; ImGui.NextColumn()
    ImGui.TextDisabled("Podium Rate") ; ImGui.NextColumn() ; ImGui.Text(st.podiumRate) ; ImGui.NextColumn()
    ImGui.TextDisabled("Top 5 Rate")  ; ImGui.NextColumn() ; ImGui.Text(st.top5Rate)   ; ImGui.NextColumn()
    ImGui.TextDisabled("Pole Rate")   ; ImGui.NextColumn() ; ImGui.Text(st.poleRate)   ; ImGui.NextColumn()

    ImGui.Columns(1)
    ImGui.Separator()

    -- â”€â”€ Averages â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.8, 1.0, 1.0)
    ImGui.Text("  Averages")
    ImGui.PopStyleColor()
    ImGui.Columns(2, "stats_avgs", false)
    ImGui.SetColumnWidth(0, 150)

    ImGui.TextDisabled("Avg Finish")  ; ImGui.NextColumn() ; ImGui.Text(st.avgFinishPos) ; ImGui.NextColumn()
    ImGui.TextDisabled("Avg Start")   ; ImGui.NextColumn() ; ImGui.Text(st.avgStartPos)  ; ImGui.NextColumn()

    ImGui.Columns(1)
    ImGui.Separator()

    -- â”€â”€ Streaks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.8, 1.0, 1.0)
    ImGui.Text("  Streaks")
    ImGui.PopStyleColor()
    ImGui.Columns(2, "stats_streaks", false)
    ImGui.SetColumnWidth(0, 150)

    -- Win streak coloured green; loss streak coloured orange
    ImGui.TextDisabled("Win Streak")
    ImGui.NextColumn()
    if st.winStreak > 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 0.85, 0.3, 1.0)
        ImGui.Text(tostring(st.winStreak))
        ImGui.PopStyleColor()
    else
        ImGui.Text("0")
    end
    ImGui.NextColumn()

    ImGui.TextDisabled("Loss Streak")
    ImGui.NextColumn()
    if st.lossStreak > 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.45, 0.1, 1.0)
        ImGui.Text(tostring(st.lossStreak))
        ImGui.PopStyleColor()
    else
        ImGui.Text("0")
    end
    ImGui.NextColumn()

    ImGui.Columns(1)
    ImGui.Separator()

    -- â”€â”€ Economy â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.8, 1.0, 1.0)
    ImGui.Text("  Economy")
    ImGui.PopStyleColor()
    ImGui.Columns(2, "stats_econ", false)
    ImGui.SetColumnWidth(0, 150)

    ImGui.TextDisabled("Eddies Earned")
    ImGui.NextColumn()
    ImGui.Text(string.format("%d cr", st.eddiesEarned))
    ImGui.NextColumn()
    ImGui.TextDisabled("Cred Awarded")
    ImGui.NextColumn()
    ImGui.Text(tostring(career.stats.credAwarded or 0))
    ImGui.NextColumn()

    ImGui.Columns(1)

    if MTE.SafetyRating then
        ImGui.Separator()
        drawSafetyRatingSummary("Career Safety Rating", MTE.SafetyRating.getCareerProfile(career))
        ImGui.Spacing()
        drawSafetyRatingSummary("Quick Race Safety Rating", MTE.SafetyRating.getQuickRaceProfile())
    end
end

-- â”€â”€ Tab 8: Nodes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local _nodeNameBuf   = { "" }
local _nodeRegionBuf = { "Westbrook" }
local _nodeMsg       = nil
local _nodeMsgColor  = { 0.4, 1.0, 0.4, 1.0 }

local REGION_PRESETS = {
    "Watson", "Westbrook", "Heywood", "Pacifica",
    "City Center", "Santo Domingo", "Badlands",
}

function UIR._drawNodesTab()
    local UN = MTE and MTE.UserNodes
    if not UN then
        ImGui.TextDisabled("UserNodes module not loaded.")
        return
    end

    ImGui.Text("Add Node at Current Position")
    ImGui.Separator()

    ImGui.SetNextItemWidth(220)
    local newName, nameChanged = ImGui.InputText("Name##nodename", _nodeNameBuf[1], 64)
    if nameChanged then _nodeNameBuf[1] = newName end

    ImGui.SetNextItemWidth(160)
    local newRegion, regionChanged = ImGui.InputText("Region##noderegion", _nodeRegionBuf[1], 32)
    if regionChanged then _nodeRegionBuf[1] = newRegion end

    ImGui.SameLine()
    if ImGui.BeginCombo("##regionpreset", "") then
        for _, r in ipairs(REGION_PRESETS) do
            if ImGui.Selectable(r, _nodeRegionBuf[1] == r) then
                _nodeRegionBuf[1] = r
            end
        end
        ImGui.EndCombo()
    end

    ImGui.Spacing()
    if ImGui.Button("+ Add Node", s(120), s(24)) then
        local name   = _nodeNameBuf[1]
        local region = _nodeRegionBuf[1]
        if name == "" then
            _nodeMsg      = "Enter a name first."
            _nodeMsgColor = { 1.0, 0.4, 0.4, 1.0 }
        else
            local ok = UN.add(name, region ~= "" and region or "Night City")
            if ok then
                _nodeMsg        = "Saved: " .. name
                _nodeMsgColor   = { 0.4, 1.0, 0.4, 1.0 }
                _nodeNameBuf[1] = ""
            else
                _nodeMsg      = "Failed â€” are you in a session?"
                _nodeMsgColor = { 1.0, 0.4, 0.4, 1.0 }
            end
        end
    end

    if _nodeMsg then
        ImGui.SameLine()
        ImGui.PushStyleColor(ImGuiCol.Text, _nodeMsgColor[1], _nodeMsgColor[2], _nodeMsgColor[3], _nodeMsgColor[4])
        ImGui.Text(_nodeMsg)
        ImGui.PopStyleColor()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Text("Saved Nodes")
    ImGui.Spacing()

    local nodes = UN.getAll and UN.getAll() or {}
    if #nodes == 0 then
        ImGui.TextDisabled("No nodes saved yet. Drive to a spot and add one.")
    else
        for i, n in ipairs(nodes) do
            ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.9, 0.9, 1)
            ImGui.Text(string.format("[%d] %s", i, n.name))
            ImGui.PopStyleColor()
            ImGui.SameLine()
            ImGui.TextDisabled(string.format("(%s)  %.0f, %.0f, %.0f  hdg=%.0f",
                n.region or "?", n.x or 0, n.y or 0, n.z or 0, n.heading or 0))
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Button,        0.7, 0.15, 0.15, 1)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.25, 0.25, 1)
            if ImGui.Button("X##deln" .. i, s(22), s(18)) then
                UN.remove(n.id or n.name)
                _nodeMsg      = "Removed: " .. n.name
                _nodeMsgColor = { 1.0, 0.6, 0.3, 1.0 }
            end
            ImGui.PopStyleColor(2)
        end
    end
end

-- â”€â”€ Event listener (cache last result) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIR.init()
    resetNewCareerChampionshipConfig()
    MTE.Events.on("RaceFinished", function(data)
        print("[NCM/UIRacing] RaceFinished listener fired, data=" .. tostring(data))
        _lastResultCache = data
        -- Switch to Race tab so results show
        _tab = 1
    end)
    print("[NCM/UIRacing] init complete, RaceFinished listener registered")
end

return UIR

