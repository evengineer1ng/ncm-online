-- ============================================================
-- MT_Ecosystem: modules/ui.lua
-- ImGui overlay shell for the CET-facing NCM experience.
-- Layout:
--   ï¿½ Collapsed HUD strip (always visible in vehicle)
--   ï¿½ Hotkey registered via CET (rebindable in CET Settings > Bindings)
--   ï¿½ Full panel surfaces overview, racing, routes, championship,
--     telemetry, metrics, and tuning in one place
-- ============================================================

local UI = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local Telemetry = require("modules/telemetry")
local Metrics = require("modules/metrics")
local Tuning = require("modules/tuning")

local function resolveModules()
    if not Telemetry then Telemetry = (MTE and MTE.Telemetry) or require("modules/telemetry") end
    if not Metrics then Metrics = (MTE and MTE.Metrics) or require("modules/metrics") end
    if not Tuning then Tuning = (MTE and MTE.Tuning) or require("modules/tuning") end
    return Telemetry and Metrics and Tuning
end

-- -- DPI scale (1.0 at 1080p, 2.0 at 4K) ---------------------
-- Computed once; used by all ui_*.lua modules via the global.
local _dpiScale = 1.0
local _dpiDetected = false
local function _computeDpiScale()
    -- Method 1: CET global GetDisplayResolution() returns w, h as two numbers
    local ok1, w1, h1 = pcall(GetDisplayResolution)
    if ok1 and type(h1) == "number" and h1 > 100 then
        _dpiScale = h1 / 1080.0
        _dpiDetected = true
        print(string.format("[NCM/UI] DPI scale=%.2f (GetDisplayResolution %dx%d)", _dpiScale, w1 or 0, h1))
        return
    end
    -- GetDisplayResolution might return a single value (width) or a table
    if ok1 and type(w1) == "table" then
        local rh = w1.height or w1.y or w1[2]
        if type(rh) == "number" and rh > 100 then
            _dpiScale = rh / 1080.0
            _dpiDetected = true
            print(string.format("[NCM/UI] DPI scale=%.2f (GetDisplayResolution table h=%d)", _dpiScale, rh))
            return
        end
    end

    -- Method 2: ImGui display size (may not be reliable at init)
    local ok2, w2, h2 = pcall(ImGui.GetDisplaySize)
    if ok2 and type(w2) == "number" and type(h2) == "number" and h2 > 100 then
        _dpiScale = h2 / 1080.0
        _dpiDetected = true
        print(string.format("[NCM/UI] DPI scale=%.2f (ImGui.GetDisplaySize %dx%d)", _dpiScale, w2, h2))
        return
    end

    print("[NCM/UI] DPI scale: deferred to first draw frame")
end

local function _tryDpiFromViewport()
    if _dpiDetected then return end
    -- Try ImGui display size during draw (more reliable than at init)
    local ok, w, h = pcall(ImGui.GetDisplaySize)
    if ok and type(w) == "number" and type(h) == "number" and h > 100 then
        _dpiScale = h / 1080.0
        _dpiDetected = true
        print(string.format("[NCM/UI] DPI scale=%.2f (deferred GetDisplaySize %dx%d)", _dpiScale, w, h))
        return
    end
    -- Fallback: peek at the current window size (the CET overlay is usually fullscreen)
    local ok2, wx, wy = pcall(ImGui.GetWindowSize)
    if ok2 and type(wy) == "number" and wy > 800 then
        _dpiScale = wy / 1080.0
        _dpiDetected = true
        print(string.format("[NCM/UI] DPI scale=%.2f (window size %dx%d)", _dpiScale, wx or 0, wy))
    end
end

--- Scale a pixel value by the current DPI factor.
--- All ui modules should call this for hardcoded sizes.
local function s(px)
    -- panelScale from user settings (100 = no extra scaling)
    local panelPct = 100
    if MTE and MTE.Settings and MTE.Settings.get then
        panelPct = MTE.Settings.get("panelScale") or 100
    end
    return math.floor(px * _dpiScale * panelPct / 100)
end
UI.s = s

--- Returns the raw DPI+panelScale multiplier (for font scaling).
local function dpiMul()
    local panelPct = 100
    if MTE and MTE.Settings and MTE.Settings.get then
        panelPct = MTE.Settings.get("panelScale") or 100
    end
    return _dpiScale * panelPct / 100
end
UI.dpiMul = dpiMul

-- -- Config ----------------------------------------------------
local WINDOW_FLAGS    = ImGuiWindowFlags.NoTitleBar
                      + ImGuiWindowFlags.NoResize
                      + ImGuiWindowFlags.NoScrollbar
                      + ImGuiWindowFlags.AlwaysAutoResize

local HUD_W           = 220
local HUD_H_COLLAPSED = 72  -- approximate, auto-resize overrides

-- Colours (RGBA 0ï¿½1)
local COL = {
    green    = { 0.20, 0.85, 0.30, 1.0 },
    red      = { 0.90, 0.20, 0.20, 1.0 },
    blue     = { 0.30, 0.60, 1.00, 1.0 },
    yellow   = { 0.95, 0.90, 0.10, 1.0 },
    orange   = { 1.00, 0.55, 0.00, 1.0 },
    white    = { 1.00, 1.00, 1.00, 1.0 },
    dimwhite = { 0.75, 0.75, 0.75, 1.0 },
    panel_bg = { 0.05, 0.05, 0.07, 0.82 },
}

-- -- State -----------------------------------------------------
UI.overlayOpen  = false   -- CET overlay open
UI.panelVisible = false   -- full multi-system panel toggle

local _activeTab    = 1        -- 1=Overview, 2=Racing, 3=Routes, 4=Championship, 5=Telemetry, 6=Metrics, 7=Tuning, 8=Garage, 9=Settings
local _settingsSubtab = 1      -- 1=Grid Solver, 2=Race Settings, 3=Knockout Circuits, 4=Display, 5=Vehicle Pools
local _hudX, _hudY  = 10, 10   -- HUD anchor (top-left)
local _fullX, _fullY = 10, 90  -- full panel anchor

-- -- Snapshot cache (avoid recalculating expensive data every frame) --
local _snapshotCache   = {}     -- keyed by section name
local _snapshotAge     = {}     -- os.clock() of last refresh
local SNAPSHOT_TTL     = 1.0    -- seconds between refreshes

local function cachedSnapshot(key, ttl, buildFn)
    local now = os.clock()
    if _snapshotCache[key] and (now - (_snapshotAge[key] or 0)) < (ttl or SNAPSHOT_TTL) then
        return _snapshotCache[key]
    end
    _snapshotCache[key] = buildFn()
    _snapshotAge[key]   = now
    return _snapshotCache[key]
end

local function invalidateSnapshot(key)
    _snapshotCache[key] = nil
    _snapshotAge[key]   = nil
end

-- -- Helpers ---------------------------------------------------

local function coloredBar(val, r, g, b, a, w, h)
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, a)
    ImGui.ProgressBar(val, w, h, "")
    ImGui.PopStyleColor()
end

local function labeledBar(label, val, col, w)
    ImGui.Text(label)
    ImGui.SameLine()
    coloredBar(math.max(0, math.min(1, val)), col[1], col[2], col[3], col[4], w, s(14))
end

local function fmt1(n) return string.format("%.1f", n or 0) end

local function fmtDistanceM(distanceM)
    local meters = tonumber(distanceM) or 0.0
    if meters >= 1000.0 then
        return string.format("%.1f km", meters / 1000.0)
    end
    return string.format("%.0f m", meters)
end

local function fmtSafetyRating(value)
    return string.format("%.2f", tonumber(value) or 0.0)
end

local function titleCaseEnum(value)
    local text = tostring(value or "unknown")
    text = text:gsub("_", " "):lower()
    return (text:gsub("(%a)([%w']*)", function(first, rest)
        return string.upper(first) .. rest
    end))
end

local function gColor(g)
    if math.abs(g) < 0.2 then return COL.white
    elseif math.abs(g) < 0.5 then return COL.yellow
    else return COL.orange end
end

local function drawOverviewTab()
    local snap = cachedSnapshot("overview", 2.0, function()
        local mte = MTE or {}
        local careers = mte.Careers
        local career = careers and careers.active and careers.active() or nil
        local careerList = careers and careers.list and careers.list() or {}
        local racing = mte.Racing
        local roots = mte.Roots
        local rootStats = roots and roots.getStats and roots.getStats() or {
            total = 0, valid = 0, invalid = 0, defaults = 0, user = 0,
        }
        local activePack = roots and roots.exportPackDocument and roots.exportPackDocument() or nil
        local userNodes = mte.UserNodes and mte.UserNodes.getAll and mte.UserNodes.getAll() or {}
        local hasManualPair = mte.ManualNodes and mte.ManualNodes.hasPair and mte.ManualNodes.hasPair() or false
        local routeSummaries = mte.RaceTelemetry and mte.RaceTelemetry.getRecentRouteSummaries
            and mte.RaceTelemetry.getRecentRouteSummaries(4) or {}
        local careerSR = career and mte.SafetyRating and mte.SafetyRating.getCareerProfile
            and mte.SafetyRating.getCareerProfile(career) or nil
        local quickRaceSR = mte.SafetyRating and mte.SafetyRating.getQuickRaceProfile
            and mte.SafetyRating.getQuickRaceProfile() or nil
        local scheduledEvent = career and mte.Championships and mte.Championships.currentEvent
            and mte.Championships.currentEvent(career) or nil
        local raceState = racing and racing.getState and titleCaseEnum(racing.getState()) or "Offline"
        return {
            career = career,
            careerCount = #careerList,
            rootStats = rootStats,
            activePack = activePack,
            userNodeCount = #userNodes,
            hasManualPair = hasManualPair,
            routeSummaries = routeSummaries,
            careerSR = careerSR,
            quickRaceSR = quickRaceSR,
            scheduledEvent = scheduledEvent,
            raceState = raceState,
        }
    end)

    local career = snap.career
    local scheduledEvent = snap.scheduledEvent

    ImGui.Text("Career & Session")
    ImGui.Separator()
    if career then
        ImGui.Text(string.format("Active Career: %s [%s]", tostring(career.name or "Unnamed"), tostring(career.tier or "?")))
        ImGui.TextDisabled(string.format("Careers: %d  |  Rep: %d  |  Race State: %s",
            snap.careerCount,
            tonumber(career.rep or 0),
            snap.raceState))
    else
        ImGui.TextDisabled("No active career selected.")
        ImGui.TextDisabled(string.format("Stored Careers: %d  |  Race State: %s", snap.careerCount, snap.raceState))
    end
    if scheduledEvent then
        ImGui.Text(string.format("Next Event: %s", tostring(scheduledEvent.titleLabel or scheduledEvent.trackName or scheduledEvent.districtLabel or "Scheduled Event")))
        ImGui.TextDisabled(string.format("Type: %s  |  Location: %s  |  Grid: %d",
            titleCaseEnum(scheduledEvent.eventType or "sprint"),
            tostring(scheduledEvent.districtLabel or scheduledEvent.district or "?"),
            tonumber(scheduledEvent.fieldSize or 0)))
    else
        ImGui.TextDisabled("No championship event is currently queued.")
    end

    ImGui.Spacing()
    ImGui.Text("Safety Rating")
    ImGui.Separator()
    if career and snap.careerSR then
        ImGui.Text(string.format("Career SR: %s", fmtSafetyRating(snap.careerSR.currentSR)))
        ImGui.SameLine()
        ImGui.TextDisabled(string.format("Distance: %s  |  Incident Points: %d",
            fmtDistanceM(snap.careerSR.totalDistanceM),
            tonumber(snap.careerSR.totalIncidentPoints or 0)))
    else
        ImGui.TextDisabled("Career SR: no active career profile.")
    end
    if snap.quickRaceSR then
        ImGui.Text(string.format("Quick Race SR: %s", fmtSafetyRating(snap.quickRaceSR.currentSR)))
        ImGui.SameLine()
        ImGui.TextDisabled(string.format("Clean Races: %d", tonumber(snap.quickRaceSR.cleanRaceCount or 0)))
    end

    ImGui.Spacing()
    ImGui.Text("Roots, Nodes & Pack")
    ImGui.Separator()
    ImGui.Text(string.format("Active Pack: %s  (v%s)",
        tostring(snap.activePack and snap.activePack.packName or "No active pack"),
        tostring(snap.activePack and snap.activePack.version or "?")))
    if snap.activePack and snap.activePack.description then
        ImGui.TextDisabled(tostring(snap.activePack.description))
    end
    ImGui.Text(string.format("Roots: %d total  |  %d valid  |  %d invalid  |  %d default  |  %d user",
        tonumber(snap.rootStats.total or 0),
        tonumber(snap.rootStats.valid or 0),
        tonumber(snap.rootStats.invalid or 0),
        tonumber(snap.rootStats.defaults or 0),
        tonumber(snap.rootStats.user or 0)))
    ImGui.Text(string.format("User Nodes: %d  |  Manual Pair: %s", snap.userNodeCount, snap.hasManualPair and "Saved" or "Missing"))
    if tonumber(snap.rootStats.defaults or 0) == 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, COL.orange[1], COL.orange[2], COL.orange[3], 1.0)
        ImGui.TextWrapped("The bundled roots pack is still empty. The roots system is live, but curated default roots have not been authored yet, so current route selection is being driven by user-created roots.")
        ImGui.PopStyleColor()
    end

    ImGui.Spacing()
    ImGui.Text("Recent Route Activity")
    ImGui.Separator()
    if #snap.routeSummaries == 0 then
        ImGui.TextDisabled("No route telemetry yet. Finish a race to seed route summaries and route records.")
        return
    end

    for _, summary in ipairs(snap.routeSummaries) do
        ImGui.Text(tostring(summary.routeDisplayName or summary.routeId or "Route"))
        ImGui.TextDisabled(string.format("Attempts: %d  |  Finishes: %d  |  DNFs: %d  |  Best Finish: %s",
            tonumber(summary.attempts or 0),
            tonumber(summary.finishes or 0),
            tonumber(summary.dnfs or 0),
            summary.bestFinish and ("P" .. tostring(summary.bestFinish)) or "--"))
        if summary.bestTotalRaceTime or summary.averageRaceTime then
            ImGui.TextDisabled(string.format("Best Race: %s  |  Avg Race: %s",
                summary.bestTotalRaceTime and (fmt1(summary.bestTotalRaceTime) .. " s") or "--",
                summary.averageRaceTime and (fmt1(summary.averageRaceTime) .. " s") or "--"))
        end
        ImGui.Spacing()
    end
end

-- -- Tab: Telemetry --------------------------------------------

local function drawTelemetryTab()
    local ts = Telemetry.state

    if not ts.inVehicle then
        ImGui.TextDisabled("Not in vehicle")
        return
    end

    -- Speed + Gear (big display)
    local speedKph = ts.speed * 3.6
    ImGui.SetWindowFontScale(1.4 * dpiMul())
    ImGui.Text(string.format("%.0f kph", speedKph))
    ImGui.SameLine()
    ImGui.SetWindowFontScale(1.8 * dpiMul())
    local gearStr = ts.gear == -1 and "R" or ts.gear == 0 and "N" or tostring(ts.gear)
    ImGui.Text(gearStr)
    ImGui.SetWindowFontScale(1.0 * dpiMul())

    ImGui.Separator()

    -- RPM bar (white?yellow?red based on value)
    local rpmCol = ts.rpm > 0.8 and COL.red or ts.rpm > 0.6 and COL.yellow or COL.white
    labeledBar("RPM ", ts.rpm, rpmCol, 140)

    -- Input bars (full width of panel)
    labeledBar("THR ", ts.throttle, COL.green,  140)
    labeledBar("BRK ", ts.brake,    COL.red,    140)
    labeledBar("CLU ", ts.clutch,   COL.blue,   140)

    -- Steering indicator: centre-zero bar
    ImGui.Text("STR ")
    ImGui.SameLine()
    local steerDisplay = (ts.steering + 1.0) * 0.5  -- remap -1..+1 ? 0..1
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, 0.7, 0.7, 0.7, 1.0)
    ImGui.ProgressBar(steerDisplay, s(140), s(14), "")
    ImGui.PopStyleColor()

    -- Handbrake
    if ts.handbrake then
        ImGui.SameLine()
        ImGui.TextColored(COL.red[1], COL.red[2], COL.red[3], 1.0, "HB")
    end

    ImGui.Separator()

    -- G-forces
    local lc = gColor(ts.longG)
    local ac = gColor(ts.latG)
    ImGui.TextColored(lc[1], lc[2], lc[3], 1.0,
        string.format("LongG: %+.2f  LatG: %+.2f", ts.longG, ts.latG))
    ImGui.Text(string.format("Accel: %.2fG  Decel: %.2fG", ts.accelRate, ts.decelRate))

    -- Vehicle health
    local hpCol = ts.vehicleHealth > 0.6 and COL.green
               or ts.vehicleHealth > 0.3 and COL.yellow
               or COL.red
    labeledBar("HP  ", ts.vehicleHealth, hpCol, 140)
end

-- -- Tab: Metrics ----------------------------------------------

local function drawMetricsTab()
    local ms = Metrics.session

    if not ms.active then
        ImGui.TextDisabled("No active session")
        if #Metrics.history > 0 then
            ImGui.Separator()
            ImGui.Text("Last session:")
            local last = Metrics.history[1]
            ImGui.Text(string.format("  Duration:  %.1fs", last.duration or 0))
            ImGui.Text(string.format("  Peak:      %.0f kph", last.peakSpeed or 0))
            ImGui.Text(string.format("  Avg:       %.0f kph", last.avgSpeed or 0))
            ImGui.Text(string.format("  Distance:  %.0f m", last.distanceTraveled or 0))
            ImGui.Text(string.format("  Crashes:   %d", last.crashCount or 0))
            if last.zeroToHundred then
                ImGui.Text(string.format("  0-100:     %.2fs", last.zeroToHundred))
            end
            if last.hundredToZero then
                ImGui.Text(string.format("  100-0:     %.2fs", last.hundredToZero))
            end
        end
        return
    end

    -- Live session
    local speedKph = Telemetry.state.speed * 3.6
    ImGui.Text(string.format("Duration:    %.0fs", ms.duration))
    ImGui.Text(string.format("Distance:    %.0f m", ms.distanceTraveled))
    ImGui.Text(string.format("Peak speed:  %.0f kph", ms.peakSpeed))
    ImGui.Text(string.format("Avg speed:   %.0f kph", ms.avgSpeed))
    ImGui.Text(string.format("Full thr:    %.1fs", ms.timeFullThrottle))
    ImGui.Text(string.format("Braking:     %.1fs", ms.timeBraking))
    ImGui.Separator()
    ImGui.Text(string.format("Max LongG:   %.2f G", ms.maxLongG))
    ImGui.Text(string.format("Max LatG:    %.2f G", ms.maxLatG))
    ImGui.Text(string.format("Max BrakeG:  %.2f G", ms.maxBrakeG))
    ImGui.Separator()

    if ms.zeroToHundred then
        ImGui.Text(string.format("0-100:       %.2f s", ms.zeroToHundred))
    else
        ImGui.TextDisabled("0-100:       ---")
    end
    if ms.hundredToZero then
        ImGui.Text(string.format("100-0:       %.2f s", ms.hundredToZero))
    else
        ImGui.TextDisabled("100-0:       ---")
    end

    local crashCol = ms.crashCount == 0 and COL.green or COL.red
    ImGui.TextColored(crashCol[1], crashCol[2], crashCol[3], 1.0,
        string.format("Crashes:     %d", ms.crashCount))

    local streak = ms.cleanStreak or 0
    if streak > 0 then
        ImGui.TextColored(COL.green[1], COL.green[2], COL.green[3], 1.0,
            string.format("Clean streak: %d", streak))
    else
        ImGui.Text(string.format("Clean streak: %d", streak))
    end

    -- Event log
    ImGui.Separator()
    ImGui.Text("Events (recent):")
    for i = 1, math.min(5, #ms.events) do
        local ev = ms.events[i]
        ImGui.TextDisabled(string.format("  [%.0fs] %s", ev.t, ev.name))
    end
end

-- -- Tab: Tuning (delegated to ui_tuning.lua) -----------------

local function drawTuningTab()
    local mte = MTE
    if mte and mte.UITuning and mte.UITuning.draw then
        mte.UITuning.draw()
    else
        ImGui.TextDisabled("Tuning UI not loaded.")
    end
end

-- -- Tab: Garage (delegated to ui_garage.lua) ----------------

local function drawGarageTab()
    local mte = MTE
    if mte and mte.UIGarage and mte.UIGarage.draw then
        mte.UIGarage.draw()
    else
        ImGui.TextDisabled("Garage UI not loaded.")
    end
end

local function drawSettingsToggle(settings, key, label)
    local cfg = settings.current or {}
    local value, changed = ImGui.Checkbox(label .. "##settings_" .. key, cfg[key] == true)
    if changed then
        cfg[key] = value == true
        settings.save()
    end
end

local function drawSettingsInt(settings, key, label, minValue, maxValue)
    local cfg = settings.current or {}
    local newValue, changed = ImGui.SliderInt(label .. "##settings_" .. key, tonumber(cfg[key]) or minValue, minValue, maxValue)
    if changed then
        cfg[key] = newValue
        settings.save()
    end
end

local function drawTuningField(settings, field)
    local currentValue = settings.getTuningValue and settings.getTuningValue(field.key) or field.default
    if field.control == "int" then
        local newValue, changed = ImGui.SliderInt(field.label .. "##" .. field.key, tonumber(currentValue) or field.default, field.min, field.max)
        if changed and settings.setTuningValue then
            settings.setTuningValue(field.key, newValue)
        end
    else
        local newValue, changed = ImGui.SliderFloat(field.label .. "##" .. field.key, tonumber(currentValue) or field.default, field.min, field.max)
        if changed and settings.setTuningValue then
            settings.setTuningValue(field.key, newValue)
        end
    end
    ImGui.TextDisabled(field.description or "")
end

local function drawSettingsFieldGroup(settings, sectionId)
    local fields = settings.getTuningFields and settings.getTuningFields(sectionId) or {}
    for _, field in ipairs(fields) do
        drawTuningField(settings, field)
    end
end

local function drawSettingsTab()
    local mte = MTE or {}
    local settings = mte.Settings
    if not settings then
        ImGui.TextDisabled("Settings module not loaded.")
        return
    end

    ImGui.Text("Global race and grid tuning")
    ImGui.TextDisabled("These controls write to the same config and root-profile schema used by NativeSettings.")
    if ImGui.SmallButton("Grid Solver##settings_subtab") then _settingsSubtab = 1 end
    ImGui.SameLine()
    if ImGui.SmallButton("Race Settings##settings_subtab") then _settingsSubtab = 2 end
    ImGui.SameLine()
    if ImGui.SmallButton("Knockout Circuits##settings_subtab") then _settingsSubtab = 3 end
    ImGui.SameLine()
    if ImGui.SmallButton("Display##settings_subtab") then _settingsSubtab = 4 end
    ImGui.SameLine()
    if ImGui.SmallButton("Vehicle Pools##settings_subtab") then _settingsSubtab = 5 end
    ImGui.SameLine()
    if ImGui.SmallButton("Reset Current Subtab##settings_reset") and settings.resetTuningSection then
        if _settingsSubtab == 1 then
            settings.resetTuningSection("gridSolver")
        elseif _settingsSubtab == 2 then
            settings.resetTuningSection("raceSettings")
        end
    end
    ImGui.Separator()

    if ImGui.BeginChild("##settingsScroll", 0, 420, true) then
        if _settingsSubtab == 1 then
            ImGui.Text("Grid Solver")
            ImGui.Separator()
            drawSettingsFieldGroup(settings, "gridSolver")
        elseif _settingsSubtab == 2 then
            ImGui.Text("Race Settings")
            ImGui.Separator()
            ImGui.Text("Grid toggles")
            drawSettingsToggle(settings, "playerGridSnapEnabled", "Player Grid Snap")
            drawSettingsToggle(settings, "manualGridMode", "Manual Grid Mode")
            ImGui.Spacing()
            ImGui.Text("Overlay & race toggles")
            drawSettingsToggle(settings, "raceMappins", "Race Map Markers")
            drawSettingsToggle(settings, "countdownBeeps", "Countdown Beeps")
            drawSettingsToggle(settings, "debugTelemetry", "Debug Telemetry")
            drawSettingsToggle(settings, "suppressTrafficDuringRace", "Suppress Traffic During Races")
            drawSettingsToggle(settings, "phoneRaceManagement", "Phone Race Management")
            ImGui.Spacing()
            ImGui.Text("Race tuning")
            ImGui.Separator()
            drawSettingsFieldGroup(settings, "raceSettings")
        elseif _settingsSubtab == 3 then
            local knockoutUi = mte and mte.UIKnockoutCircuits or nil
            if knockoutUi and knockoutUi.draw then
                knockoutUi.draw()
            else
                ImGui.TextDisabled("Knockout circuit configurator not loaded.")
            end
        elseif _settingsSubtab == 4 then
            ImGui.Text("Display & HUD Layout")
            ImGui.Separator()

            ImGui.Text("CET Panel")
            ImGui.TextDisabled("Scale of this ImGui overlay window.")
            drawSettingsInt(settings, "panelScale", string.format("Panel Scale (%%) â€” auto DPI: %.1fx", _dpiScale), 50, 400)

            ImGui.Spacing()
            ImGui.Text("Telemetry HUD (in-game, bottom-right)")
            ImGui.Separator()
            drawSettingsToggle(settings, "hudEnabled", "Enable HUD")
            drawSettingsToggle(settings, "showInputs", "Show Inputs")
            drawSettingsToggle(settings, "showGForces", "Show G-Forces")
            drawSettingsToggle(settings, "showHealth", "Show Vehicle Health")
            drawSettingsInt(settings, "telemetryScale", "Telemetry Scale (%)", 25, 300)
            drawSettingsInt(settings, "telemetryOpacity", "Telemetry Opacity (%)", 5, 100)
            drawSettingsInt(settings, "telemetryOffsetX", "Telemetry Offset X (px)", -800, 800)
            drawSettingsInt(settings, "telemetryOffsetY", "Telemetry Offset Y (px)", -600, 600)

            ImGui.Spacing()
            ImGui.Text("Race HUD (in-game, top-center)")
            ImGui.Separator()
            drawSettingsInt(settings, "raceHudScale", "Race HUD Scale (%)", 25, 300)
            drawSettingsInt(settings, "raceHudOpacity", "Race HUD Opacity (%)", 5, 100)
            drawSettingsInt(settings, "raceHudOffsetX", "Race HUD Offset X (px)", -800, 800)
            drawSettingsInt(settings, "raceHudOffsetY", "Race HUD Offset Y (px)", -600, 600)
        elseif _settingsSubtab == 5 then
            local vehiclePoolUi = mte and mte.UIVehiclePool or nil
            if vehiclePoolUi and vehiclePoolUi.draw then
                vehiclePoolUi.draw()
            else
                ImGui.TextDisabled("Vehicle pool configurator not loaded.")
            end
        end
    end
    ImGui.EndChild()
end

-- -- Tab: Racing (delegated to ui_racing.lua) -----------------

local function drawRacingTab()
    local mte = MTE
    if mte and mte.UIRacing and mte.UIRacing.draw then
        mte.UIRacing.draw()
    else
        ImGui.TextDisabled("Racing UI not loaded.")
    end
end

local function drawRoutesTab()
    local mte = MTE
    if mte and mte.UIRoutes and mte.UIRoutes.draw then
        mte.UIRoutes.draw()
    else
        ImGui.TextDisabled("Routes UI not loaded.")
    end
end

-- -- Tab: Championship (delegated to ui_championships.lua) ----

local function drawChampionshipsTab()
    local mte = MTE
    if mte and mte.UIChampionships and mte.UIChampionships.draw then
        mte.UIChampionships.draw()
    else
        ImGui.TextDisabled("Championship system not loaded.")
    end
end

-- -- Minimal HUD strip ----------------------------------------

local function drawHUD()
    local ts = Telemetry.state
    local mte = MTE
    local racing = mte and mte.Racing

    if not ts.inVehicle then return end

    local hudCfg = mte and mte.Settings and mte.Settings.current or {}
    local hudAlpha = (hudCfg.hudOpacity or 75) / 100.0
    local hudScale = (hudCfg.hudScale or 100) / 100.0
    local dpiHudScale = hudScale * (s(100) / 100)

    ImGui.SetNextWindowBgAlpha(hudAlpha)
    ImGui.SetNextWindowPos(_hudX, _hudY, ImGuiCond.Always)
    ImGui.SetNextWindowSize(s(HUD_W) * hudScale, 0)
    if ImGui.Begin("MTE_HUD", WINDOW_FLAGS) then
        local speedKph = ts.speed * 3.6
        local gearStr  = ts.gear == -1 and "R" or ts.gear == 0 and "N" or tostring(ts.gear)

        ImGui.SetWindowFontScale(1.3 * dpiHudScale)
        ImGui.Text(string.format("%.0f kph  [%s]", speedKph, gearStr))
        ImGui.SetWindowFontScale(1.0 * dpiHudScale)

        -- Inline micro-bars on one line
        coloredBar(ts.throttle, COL.green[1], COL.green[2], COL.green[3], 1.0, s(60), s(8))
        ImGui.SameLine()
        coloredBar(ts.brake,    COL.red[1],   COL.red[2],   COL.red[3],   1.0, s(60), s(8))
        ImGui.SameLine()
        coloredBar(ts.clutch,   COL.blue[1],  COL.blue[2],  COL.blue[3],  1.0, s(60), s(8))

        -- Race state if active
        local rs = racing and racing.getState and racing.getState()
        if racing and rs == racing.STATE.COUNTDOWN then
            ImGui.TextColored(COL.yellow[1], COL.yellow[2], COL.yellow[3], 1.0,
                string.format("GO IN %.0f", math.max(0, racing.getRaceTimer())))
        elseif racing and rs == racing.STATE.RACING then
            ImGui.TextColored(COL.green[1], COL.green[2], COL.green[3], 1.0,
                string.format("RACING  %.1fs", racing.getRaceTimer()))
        elseif racing and rs == racing.STATE.RESULTS then
            ImGui.TextColored(COL.yellow[1], COL.yellow[2], COL.yellow[3], 1.0,
                "RESULTS  [panel]")
        end
    end
    ImGui.End()
end

-- -- Race HUD overlay (floating window during COUNTDOWN / RACING) --

local function raceHudPosColor(pos)
    if pos == 1 then return COL.yellow[1],   COL.yellow[2],   COL.yellow[3],   1.0 end
    if pos <= 3 then return COL.green[1],    COL.green[2],    COL.green[3],    1.0 end
    return              COL.dimwhite[1], COL.dimwhite[2], COL.dimwhite[3], 1.0
end

local function drawRaceHUD()
    local mte = MTE
    local R = mte and mte.Racing
    if not R or not R.getState then return end
    local rs = R.getState()
    if rs ~= R.STATE.COUNTDOWN and rs ~= R.STATE.RACING then return end

    local cfg    = R.getConfig()
    local t      = R.getRaceTimer()
    local field  = R.getField()
    local total  = #field + 1  -- AI count + player

    -- Track name: prefer Tracks module, fall back to node names
    local trackName = "Race"
    if cfg and cfg.nodeA and cfg.nodeB then
        if mte and mte.Tracks then
            trackName = mte.Tracks.getRouteName(cfg.nodeA, cfg.nodeB)
        else
            trackName = (cfg.nodeA.name or "?") .. " ? " .. (cfg.nodeB.name or "?")
        end
    end

    ImGui.SetNextWindowBgAlpha(0.82)
    ImGui.SetNextWindowPos(800, 30, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(s(250), 0)
    if ImGui.Begin("##MTERaceHUD", WINDOW_FLAGS) then

        -- Track name header
        ImGui.PushStyleColor(ImGuiCol.Text, COL.yellow[1], COL.yellow[2], COL.yellow[3], 1.0)
        ImGui.Text(trackName)
        ImGui.PopStyleColor()
        ImGui.Separator()

        if rs == R.STATE.COUNTDOWN then
            -- Big countdown number
            ImGui.SetWindowFontScale(2.4 * dpiMul())
            ImGui.TextColored(COL.yellow[1], COL.yellow[2], COL.yellow[3], 1.0,
                string.format("  %d", math.ceil(math.max(0, t))))
            ImGui.SetWindowFontScale(1.0 * dpiMul())
            local gridPos = R.getQualiGridPos()
            if gridPos then
                ImGui.TextDisabled(string.format("Grid P%d of %d", gridPos, total))
            else
                ImGui.TextDisabled(string.format("%d car field", total))
            end

        else  -- RACING
            local estPos = R.getEstimatedPosition() or 1
            local dist   = R.getDistanceToFinish()
            local standings = R.getLiveStandings()
            local liveTotal = (#standings > 0) and #standings or total

            -- Position + timer on one line
            ImGui.SetWindowFontScale(1.9 * dpiMul())
            local pr, pg, pb = raceHudPosColor(estPos)
            ImGui.TextColored(pr, pg, pb, 1.0, string.format("P%d", estPos))
            ImGui.SetWindowFontScale(1.0 * dpiMul())
            ImGui.SameLine()
            ImGui.Text(string.format("/ %d     %.1fs", liveTotal, t))

            -- Distance to finish
            if dist then
                local distLabel = dist > 80
                    and string.format("%.0f m to finish", dist)
                    or  "  >> Approaching finish! <<"
                ImGui.TextDisabled(distLabel)
            end

            ImGui.Separator()

            -- Live standings (up to 8 entries)
            for rank, entry in ipairs(standings) do
                if rank > 8 then break end
                local doneMarker = entry.finished and "v" or " "
                if entry.isPlayer then
                    ImGui.PushStyleColor(ImGuiCol.Text,
                        COL.yellow[1], COL.yellow[2], COL.yellow[3], 1.0)
                end
                local name12 = (entry.name or "?"):sub(1, 12)
                ImGui.Text(string.format("%s %d  %-12s  %.1fs",
                    doneMarker, rank, name12, entry.time))
                if entry.isPlayer then ImGui.PopStyleColor() end
            end
        end
    end
    ImGui.End()
end

-- -- Full panel ------------------------------------------------

local function drawPanelStatusStrip()
    local snap = cachedSnapshot("status_strip", 1.0, function()
        local mte = MTE or {}
        local career = mte.Careers and mte.Careers.active and mte.Careers.active() or nil
        local roots = mte.Roots and mte.Roots.getStats and mte.Roots.getStats() or { total = 0, valid = 0, defaults = 0 }
        local pack = mte.Roots and mte.Roots.exportPackDocument and mte.Roots.exportPackDocument() or nil
        local careerSR = career and mte.SafetyRating and mte.SafetyRating.getCareerProfile
            and mte.SafetyRating.getCareerProfile(career)
            or nil
        local quickRaceSR = mte.SafetyRating and mte.SafetyRating.getQuickRaceProfile
            and mte.SafetyRating.getQuickRaceProfile()
            or nil
        local raceState = mte.Racing and mte.Racing.getState and titleCaseEnum(mte.Racing.getState()) or "Offline"
        return {
            careerName = career and career.name or "No active career",
            raceState = raceState,
            rootsValid = tonumber(roots.valid or 0),
            rootsTotal = tonumber(roots.total or 0),
            rootsDefaults = tonumber(roots.defaults or 0),
            packName = pack and pack.packName or "No active pack",
            careerSRText = careerSR and fmtSafetyRating(careerSR.currentSR) or "--",
            quickSRText = quickRaceSR and fmtSafetyRating(quickRaceSR.currentSR) or "--",
        }
    end)
    ImGui.Text(string.format("Career: %s  |  Race: %s  |  Roots: %d/%d valid",
        tostring(snap.careerName),
        snap.raceState,
        snap.rootsValid,
        snap.rootsTotal))
    ImGui.TextDisabled(string.format("Pack: %s  |  Career SR: %s  |  Quick SR: %s",
        tostring(snap.packName),
        snap.careerSRText,
        snap.quickSRText))
    if snap.rootsDefaults == 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, COL.orange[1], COL.orange[2], COL.orange[3], 1.0)
        ImGui.TextWrapped("No curated default roots are active yet. Use the Routes tab to work with the user-authored roots that are currently driving route selection.")
        ImGui.PopStyleColor()
    end
    ImGui.Separator()
end

local _tabLabels = { "Overview", "Racing", "Routes", "Championship", "Telemetry", "Metrics", "Tuning", "Garage", "Settings" }
local _tabFns    = { drawOverviewTab, drawRacingTab, drawRoutesTab, drawChampionshipsTab, drawTelemetryTab, drawMetricsTab, drawTuningTab, drawGarageTab, drawSettingsTab }

local function drawFullPanel()
    _tryDpiFromViewport()
    local fontScale = s(100) / 100  -- DPI + panelScale applied to font
    ImGui.SetNextWindowBgAlpha(0.88)
    ImGui.SetNextWindowPos(_fullX, _fullY, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSizeConstraints(s(780), 0, 4096, 4096)
    if ImGui.Begin("Night City Motorsports##main", ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.SetWindowFontScale(fontScale)
        drawPanelStatusStrip()

        -- Tab bar
        for i, label in ipairs(_tabLabels) do
            if i > 1 then ImGui.SameLine() end
            local active = _activeTab == i
            if active then
                ImGui.PushStyleColor(ImGuiCol.Button, 0.25, 0.55, 0.90, 1.0)
            end
            if ImGui.Button(label .. "##tab" .. i) then
                _activeTab = i
            end
            if active then ImGui.PopStyleColor() end
        end
        ImGui.Separator()
        _tabFns[_activeTab]()
    end
    ImGui.End()
end

-- -- Public ----------------------------------------------------

function UI.init()
    _computeDpiScale()
    print(string.format("[NCM/UI] Initialised. DPI scale=%.2f. Rebind 'Toggle MT Ecosystem Panel' in CET Settings > Bindings.", _dpiScale))
end

function UI.onOverlayOpen()
    UI.overlayOpen = true
end

function UI.onOverlayClose()
    UI.overlayOpen = false
    UI.panelVisible = false
end

--- Called from onDraw every frame (only runs when CET overlay is open).
--- The always-on in-game HUD is handled by modules/ink_hud.lua via onUpdate.
function UI.draw()
    if not resolveModules() then return end
    local showOverlayUI = UI.panelVisible or UI.overlayOpen

    -- Keep all modules in sync when the CET overlay is open
    local ts = Telemetry.state
    if showOverlayUI and not ts.inVehicle then
        pcall(function()
            local p = Game.GetPlayer()
            if not p then return end
            local v = Game.GetMountedVehicle(p)
            if v then
                ts.inVehicle = true
                Telemetry.onVehicleEnter(v)
                Metrics.onVehicleEnter()
                Tuning.onVehicleEnter(v)
            end
        end)
    end

    -- Race standings: floating window visible when CET overlay / panel is open
    if showOverlayUI then
        drawRaceHUD()
        drawFullPanel()
    end

end

return UI

