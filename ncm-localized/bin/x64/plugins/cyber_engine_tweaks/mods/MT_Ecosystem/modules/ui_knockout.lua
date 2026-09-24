-- ============================================================
-- MT_Ecosystem: modules/ui_knockout.lua
-- Knockout tab UI: circuit picker, config, lobby, live standings,
-- elimination countdown, results.
-- Drawn as a sub-tab inside ui_racing.lua's tab bar.
-- ============================================================

local UIK = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end

-- â”€â”€ Scratch state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local _selectedCircuit  = 1        -- index into circuits list
local _fieldSizeBuf     = { "12" }
local _elimIntervalBuf  = { "60" }
local _trafficMode      = 1        -- 1=normal, 2=none, 3=heavy
local _combatMode       = 1        -- 1=allowed, 2=disallowed
local _lastResultCache  = nil
local _lastEliminatedFlash = nil   -- { name, timer }

local TRAFFIC_LABELS = { "normal", "none", "heavy" }
local COMBAT_LABELS  = { "allowed", "disallowed" }
local DEFAULT_FIELD_SIZE           = 12
local DEFAULT_ELIMINATION_INTERVAL = 60

-- â”€â”€ Colour helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function dangerColor()   return 1.0, 0.2, 0.2, 1.0 end
local function safeColor()     return 0.3, 0.9, 0.3, 1.0 end
local function warningColor()  return 1.0, 0.7, 0.1, 1.0 end
local function headerColor()   return 0.4, 0.7, 1.0, 1.0 end
local function dimColor()      return 0.5, 0.5, 0.5, 1.0 end

local function posColor(pos)
    if pos == 1 then return 1.0, 0.85, 0.1, 1 end
    if pos == 2 then return 0.8, 0.8, 0.8, 1 end
    if pos == 3 then return 0.8, 0.5, 0.2, 1 end
    return 0.8, 0.8, 0.8, 1
end

local function fmtTime(secs)
    if not secs then return "--:--.--" end
    local m = math.floor(secs / 60)
    local s = secs - m * 60
    return string.format("%d:%05.2f", m, s)
end

-- â”€â”€ Main draw entry (called from ui_racing.lua) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK.draw()
    local K = MTE.Knockout
    if not K then
        ImGui.TextColored(0.9, 0.3, 0.3, 1, "Knockout module not loaded.")
        return
    end

    local state = K.getState()

    if state == K.STATE.IDLE then
        UIK._drawIdlePanel()
    elseif state == K.STATE.CONFIG then
        UIK._drawConfigPanel()
    elseif state == K.STATE.LOBBY then
        UIK._drawLobbyPanel()
    elseif state == K.STATE.COUNTDOWN then
        UIK._drawCountdownPanel()
    elseif state == K.STATE.RACING then
        UIK._drawRacingPanel()
    elseif state == K.STATE.FINISHED then
        UIK._drawResultsPanel()
    end
end

-- â”€â”€ IDLE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK._drawIdlePanel()
    ImGui.TextColored(headerColor())
    ImGui.Text("NIGHT CITY KNOCKOUT")
    ImGui.Separator()
    ImGui.TextWrapped("Circuit-based elimination racing. Last driver standing wins!")
    ImGui.Spacing()

    local career = MTE.Careers and MTE.Careers.active()
    if not career then
        ImGui.TextColored(warningColor())
        ImGui.Text("Create or activate a career first.")
        return
    end

    -- Check mutual exclusion with sprint racing
    if MTE.Racing and MTE.Racing.getState() ~= MTE.Racing.STATE.IDLE then
        ImGui.TextColored(warningColor())
        ImGui.Text("Finish or abort the current sprint race first.")
        return
    end

    if ImGui.Button("Start Knockout Setup", s(200), s(28)) then
        local ok, err = MTE.Knockout.openConfig()
        if not ok then
            print("[NCM/UIKnockout] " .. (err or "Failed to open config."))
        end
    end
end

-- â”€â”€ CONFIG â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK._drawConfigPanel()
    local K = MTE.Knockout
    ImGui.TextColored(headerColor())
    ImGui.Text("KNOCKOUT CONFIG")
    ImGui.Separator()

    -- Circuit picker
    local circuits = K.getCircuits()
    local draft = K.getDraft() or {}
    if #circuits == 0 then
        ImGui.Text("No circuits defined.")
        return
    end

    if draft.circuitId then
        for i, c in ipairs(circuits) do
            if c.id == draft.circuitId then
                _selectedCircuit = i
                break
            end
        end
    end

    if not circuits[_selectedCircuit] then
        _selectedCircuit = 1
    end

    ImGui.Text("Circuit:")
    for i, c in ipairs(circuits) do
        local selected = (_selectedCircuit == i)
        if selected then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1)
        end
        if ImGui.Button(c.name .. "##circ" .. i, s(220), s(22)) then
            _selectedCircuit = i
        end
        if selected then ImGui.PopStyleColor() end
        ImGui.SameLine()
        ImGui.TextColored(dimColor())
        ImGui.Text(string.format("(%s, ~%ds/lap)", c.region,
            c.estimatedLapTime or 0))
    end

    ImGui.Spacing()

    local circuit = circuits[_selectedCircuit]
    local knockoutSpec = circuit and circuit.knockout or {}
    local isCheckpointMode = knockoutSpec.eliminationMode == "checkpoint"

    -- Field size
    if isCheckpointMode then
        _fieldSizeBuf[1] = tostring(knockoutSpec.lockedFieldSize or DEFAULT_FIELD_SIZE)
        ImGui.Text(string.format("Field Size: fixed at %s for this circuit.", _fieldSizeBuf[1]))
    else
        ImGui.Text("Field Size (4-24):")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(60)
        ImGui.InputText("##ko_field", _fieldSizeBuf, ImGuiInputTextFlags.CharsDecimal)
    end

    -- Elimination interval
    if isCheckpointMode then
        ImGui.TextColored(warningColor())
        ImGui.Text("Format: Checkpoint Knockout")
        ImGui.TextWrapped("One car is cut at each checkpoint through Little China Freeway. Checkerboard to Parque Del Mar is the final two-driver sprint.")
    else
        ImGui.Text("Elimination Interval (sec):")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(60)
        ImGui.InputText("##ko_elim", _elimIntervalBuf, ImGuiInputTextFlags.CharsDecimal)
    end

    -- Traffic mode
    ImGui.Text("Traffic:")
    ImGui.SameLine()
    for i, label in ipairs(TRAFFIC_LABELS) do
        if i > 1 then ImGui.SameLine() end
        local active = (_trafficMode == i)
        if active then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1)
        end
        if ImGui.Button(label .. "##traf" .. i, s(70), s(22)) then
            _trafficMode = i
        end
        if active then ImGui.PopStyleColor() end
    end

    -- Combat mode
    ImGui.Text("Combat:")
    ImGui.SameLine()
    for i, label in ipairs(COMBAT_LABELS) do
        if i > 1 then ImGui.SameLine() end
        local active = (_combatMode == i)
        if active then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1)
        end
        if ImGui.Button(label .. "##cmbt" .. i, s(90), s(22)) then
            _combatMode = i
        end
        if active then ImGui.PopStyleColor() end
    end

    ImGui.Spacing()
    ImGui.Separator()

    -- Confirm / Cancel
    if ImGui.Button("Confirm##ko_confirm", s(130), s(28)) then
        local fieldSize = tonumber(_fieldSizeBuf[1]) or DEFAULT_FIELD_SIZE
        local elimInt   = tonumber(_elimIntervalBuf[1]) or DEFAULT_ELIMINATION_INTERVAL
        local circuit   = circuits[_selectedCircuit]

        local ok, err = K.confirmConfig({
            circuitId           = circuit and circuit.id or nil,
            fieldSize           = fieldSize,
            eliminationInterval = elimInt,
            trafficMode         = TRAFFIC_LABELS[_trafficMode] or "normal",
            combatMode          = COMBAT_LABELS[_combatMode] or "allowed",
        })
        if not ok then
            print("[NCM/UIKnockout] Config error: " .. (err or "unknown"))
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Cancel##ko_cancel", s(100), s(28)) then
        K.abort()
    end
end

-- â”€â”€ LOBBY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK._drawLobbyPanel()
    local K    = MTE.Knockout
    local cfg  = K.getConfig()

    ImGui.TextColored(headerColor())
    ImGui.Text("KNOCKOUT LOBBY")
    ImGui.Separator()

    ImGui.Text("Circuit: " .. (cfg.circuitName or "?"))
    if cfg.eliminationMode == "checkpoint" then
        ImGui.Text(string.format("Drivers: %d  |  Checkpoint eliminations to final two",
            (cfg.fieldSize or 0) + 1))
        local fromCheckpoint = cfg.finalSprintCheckpoint
        local finishCheckpoint = cfg.finishCheckpoint
        ImGui.Text(string.format("Final sprint: %s -> %s",
            fromCheckpoint and fromCheckpoint.checkpointName or "Checkerboard",
            finishCheckpoint and finishCheckpoint.checkpointName or "Finish"))
    else
        ImGui.Text(string.format("Drivers: %d  |  Elimination every %ds",
            (cfg.fieldSize or 0) + 1, cfg.eliminationInterval or 60))
    end

    ImGui.Spacing()

    -- Spawn progress
    if MTE.AIVehicles then
        local ready = MTE.AIVehicles.readyCount()
        local total = MTE.AIVehicles.totalCount()
        local spawning = MTE.AIVehicles.isSpawning()

        if spawning then
            ImGui.Text(string.format("Spawning AI: %d/%d ...", ready, total))
            ImGui.ProgressBar(total > 0 and ready / total or 0, s(200), s(16))
        else
            ImGui.TextColored(safeColor())
            ImGui.Text(string.format("All %d AI vehicles ready.", ready))
        end
    end

    ImGui.Spacing()

    -- Field preview
    local field = K.getField()
    if #field > 0 then
        ImGui.Text("Grid:")
        ImGui.Columns(3, "##ko_grid", true)
        ImGui.Text("Pos"); ImGui.NextColumn()
        ImGui.Text("Driver"); ImGui.NextColumn()
        ImGui.Text("Class"); ImGui.NextColumn()
        ImGui.Separator()

        -- Player at P1 (front of grid)
        ImGui.Text("P1"); ImGui.NextColumn()
        ImGui.TextColored(1, 0.85, 0.1, 1, "V (You)"); ImGui.NextColumn()
        ImGui.Text("--"); ImGui.NextColumn()

        for i, d in ipairs(field) do
            local name = d.name or d.displayName or d.id or "?"
            if #name > 18 then name = name:sub(1, 18) end
            ImGui.Text("P" .. (i + 1)); ImGui.NextColumn()
            ImGui.Text(name); ImGui.NextColumn()
            ImGui.Text(d.carClass or "?"); ImGui.NextColumn()
            if i >= 15 then
                ImGui.Text("..."); ImGui.NextColumn()
                ImGui.Text(string.format("+%d more", #field - 15)); ImGui.NextColumn()
                ImGui.Text(""); ImGui.NextColumn()
                break
            end
        end
        ImGui.Columns(1)
    end

    ImGui.Spacing()
    ImGui.Separator()

    -- Start / Cancel
    local canStart = MTE.AIVehicles and not MTE.AIVehicles.isSpawning()
    if canStart then
        if ImGui.Button("START KNOCKOUT", s(180), s(30)) then
            K.startRace()
        end
    else
        ImGui.TextColored(dimColor())
        ImGui.Text("Waiting for AI spawn...")
    end
    ImGui.SameLine()
    if ImGui.Button("Cancel##ko_lobby_cancel", s(100), s(30)) then
        K.abort()
    end
end

-- â”€â”€ COUNTDOWN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK._drawCountdownPanel()
    local K = MTE.Knockout
    local val = K.getCountdownValue()

    ImGui.TextColored(headerColor())
    ImGui.Text("KNOCKOUT")
    ImGui.Separator()

    -- Big countdown number
    ImGui.SetCursorPosX((ImGui.GetWindowWidth() - s(80)) / 2)
    if val > 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.85, 0.1, 1)
        ImGui.SetWindowFontScale(3.0 * (MTE and MTE.UI and MTE.UI.dpiMul and MTE.UI.dpiMul() or 1))
        ImGui.Text(tostring(val))
        ImGui.SetWindowFontScale(1.0 * (MTE and MTE.UI and MTE.UI.dpiMul and MTE.UI.dpiMul() or 1))
        ImGui.PopStyleColor()
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1, 0.3, 1)
        ImGui.SetWindowFontScale(3.0 * (MTE and MTE.UI and MTE.UI.dpiMul and MTE.UI.dpiMul() or 1))
        ImGui.Text("GO!")
        ImGui.SetWindowFontScale(1.0 * (MTE and MTE.UI and MTE.UI.dpiMul and MTE.UI.dpiMul() or 1))
        ImGui.PopStyleColor()
    end
end

-- â”€â”€ RACING â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK._drawRacingPanel()
    local K   = MTE.Knockout
    local cfg = K.getConfig()

    ImGui.TextColored(headerColor())
    ImGui.Text("KNOCKOUT â€” " .. (cfg.circuitName or ""))
    ImGui.Separator()

    -- Summary line
    local remaining = K.getRemainingDrivers()
    local phase     = K.getRacePhase()
    local timer     = K.getRaceTimer()

    ImGui.Text(string.format("Time: %s  |  Remaining: %d  |  Phase: %s",
        fmtTime(timer), remaining, phase:upper()))

    -- Elimination countdown
    local elimCD = K.getEliminationCountdown()
    local inDanger = K.isPlayerInDangerZone()

    if cfg.eliminationMode == "checkpoint" then
        local nextCheckpoint = K.getNextEliminationCheckpoint()
        local fromCheckpoint = cfg.finalSprintCheckpoint
        local finishCheckpoint = cfg.finishCheckpoint
        if inDanger then
            ImGui.PushStyleColor(ImGuiCol.Text, dangerColor())
        else
            ImGui.PushStyleColor(ImGuiCol.Text, safeColor())
        end
        if nextCheckpoint then
            ImGui.Text(string.format("Next elimination: %s%s",
                nextCheckpoint.checkpointName or "Checkpoint",
                inDanger and "  *** DANGER ZONE ***" or ""))
        else
            ImGui.Text(string.format("Final sprint: %s -> %s%s",
                fromCheckpoint and fromCheckpoint.checkpointName or "Checkerboard",
                finishCheckpoint and finishCheckpoint.checkpointName or "Finish",
                inDanger and "  *** DANGER ZONE ***" or ""))
        end
        ImGui.PopStyleColor()
    else
        if inDanger then
            ImGui.PushStyleColor(ImGuiCol.Text, dangerColor())
        else
            ImGui.PushStyleColor(ImGuiCol.Text, safeColor())
        end
        ImGui.Text(string.format("Next elimination in: %.0fs%s",
            elimCD, inDanger and "  *** DANGER ZONE ***" or ""))
        ImGui.PopStyleColor()

        -- Elimination countdown bar
        local interval = cfg.eliminationInterval or 60
        local barFrac = interval > 0 and (1.0 - elimCD / interval) or 0
        if inDanger then
            ImGui.PushStyleColor(ImGuiCol.PlotHistogram, dangerColor())
        else
            ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.2, 0.6, 0.9, 1)
        end
        ImGui.ProgressBar(barFrac, s(280), s(14), "")
        ImGui.PopStyleColor()
    end

    ImGui.Spacing()

    -- Live standings
    local standings = K.getLiveStandings()
    if #standings > 0 then
        ImGui.Text("Standings:")
        ImGui.Columns(3, "##ko_standings", true)
        ImGui.Text("Pos"); ImGui.NextColumn()
        ImGui.Text("Driver"); ImGui.NextColumn()
        ImGui.Text("Lap"); ImGui.NextColumn()
        ImGui.Separator()

        local dangerStart = math.max(1, #standings - 2)
        for i, e in ipairs(standings) do
            local isDanger = (i >= dangerStart)

            -- Position
            if e.isPlayer then
                ImGui.TextColored(1, 0.85, 0.1, 1, "P" .. i)
            elseif isDanger then
                ImGui.TextColored(dangerColor())
                ImGui.Text("P" .. i)
            else
                ImGui.Text("P" .. i)
            end
            ImGui.NextColumn()

            -- Name
            local name = e.name or "?"
            if #name > 16 then name = name:sub(1, 16) end
            if e.isPlayer then
                ImGui.TextColored(1, 0.85, 0.1, 1, name .. " <")
            elseif isDanger then
                ImGui.TextColored(dangerColor())
                ImGui.Text(name)
            else
                ImGui.Text(name)
            end
            ImGui.NextColumn()

            -- Lap
            ImGui.Text(tostring(e.lap or 1))
            ImGui.NextColumn()

            if i >= 12 then
                if #standings > 12 then
                    ImGui.TextColored(dimColor())
                    ImGui.Text("..."); ImGui.NextColumn()
                    ImGui.Text(string.format("+%d more", #standings - 12))
                    ImGui.NextColumn()
                    ImGui.Text(""); ImGui.NextColumn()
                end
                break
            end
        end
        ImGui.Columns(1)
    end

    -- Last eliminated flash
    local lastElim = K.getLastEliminatedName()
    if lastElim then
        ImGui.Spacing()
        ImGui.TextColored(dangerColor())
        ImGui.Text("ELIMINATED: " .. lastElim)
    end

    ImGui.Spacing()
    ImGui.Separator()
    if ImGui.Button("Abort Knockout##ko_abort", s(140), s(26)) then
        K.abort()
    end
end

-- â”€â”€ RESULTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK._drawResultsPanel()
    local K       = MTE.Knockout
    local results = K.getResults()

    ImGui.TextColored(headerColor())
    ImGui.Text("KNOCKOUT RESULTS")
    ImGui.Separator()

    if #results == 0 then
        ImGui.Text("No results.")
    else
        ImGui.Columns(4, "##ko_results", true)
        ImGui.Text("Pos"); ImGui.NextColumn()
        ImGui.Text("Driver"); ImGui.NextColumn()
        ImGui.Text("Status"); ImGui.NextColumn()
        ImGui.Text("Time"); ImGui.NextColumn()
        ImGui.Separator()

        for _, r in ipairs(results) do
            -- Position
            if r.isPlayer then
                ImGui.TextColored(posColor(r.position))
                ImGui.Text("P" .. r.position)
            else
                ImGui.Text("P" .. r.position)
            end
            ImGui.NextColumn()

            -- Name
            local name = r.name or "?"
            if #name > 16 then name = name:sub(1, 16) end
            if r.isPlayer then
                ImGui.TextColored(1, 0.85, 0.1, 1, name)
            else
                ImGui.Text(name)
            end
            ImGui.NextColumn()

            -- Status
            if r.survived then
                ImGui.TextColored(safeColor())
                ImGui.Text("SURVIVED")
            else
                ImGui.TextColored(dangerColor())
                ImGui.Text("ELIMINATED")
            end
            ImGui.NextColumn()

            -- Time
            if r.eliminatedAt then
                ImGui.Text(fmtTime(r.eliminatedAt))
            else
                ImGui.Text("--")
            end
            ImGui.NextColumn()
        end
        ImGui.Columns(1)
    end

    -- Payout / rep (from cached event)
    if _lastResultCache then
        ImGui.Spacing()
        ImGui.Text(string.format("Payout: %d eddies  |  Rep: %+d",
            _lastResultCache.payout or 0,
            _lastResultCache.repGain or 0))
        if _lastResultCache.playerWon then
            ImGui.TextColored(1, 0.85, 0.1, 1, "YOU WIN!")
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    if ImGui.Button("Close##ko_close_results", s(120), s(28)) then
        K.closeResults()
        _lastResultCache = nil
    end
end

-- â”€â”€ Init (event listeners) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIK.init()
    MTE.Events.on("KnockoutFinished", function(data)
        _lastResultCache = data
    end)
end

return UIK

