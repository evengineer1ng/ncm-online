-- ============================================================
-- MT_Ecosystem: init.lua
-- Orchestrator: loads all modules, registers CET lifecycle events.
-- Four systems:
--   Telemetry  (Mod 1) → raw signals + derived G-forces
--   Metrics    (Mod 2) → session analytics + events
--   Tuning     (Mod 3) → per-vehicle TweakDB sliders
--   Racing     (Mod 4) → procedural race system
-- ============================================================

local version = "0.1.0"

-- ── Module loading ────────────────────────────────────────────
local Events      = require("modules/events")
local I18N        = require("modules/i18n")
local Persist     = require("modules/persistence")
local Telemetry   = require("modules/telemetry")
local Metrics     = require("modules/metrics")
local SafetyRating = require("modules/safety_rating")
local Tuning      = require("modules/tuning")
local Racing      = require("modules/racing")
local Roster      = require("modules/roster")
local Careers     = require("modules/careers")
local Management  = require("modules/management")
local AmbientRaces = require("modules/ambient_races")
local Parts       = require("modules/parts")
local Heat        = require("modules/heat")
local Hype        = require("modules/hype")
local Betting     = require("modules/betting")
local Records     = require("modules/records")
local FanEngine   = require("modules/fan_engine")
local ContactEvents = require("modules/contact_events")
local VoiceHarness = require("modules/voice_harness")
local Roots       = require("modules/roots")
local Routes      = require("modules/routes")
local RaceTelemetry = require("modules/race_telemetry")
local RaceCommands = require("modules/race_commands")
local PhoneBridge = require("modules/phone_bridge")
local Onboarding = require("modules/onboarding")
local UI          = require("modules/ui")
local UIRacing    = require("modules/ui_racing")
local UIRoutes    = require("modules/ui_routes")
local UITuning    = require("modules/ui_tuning")
local InkHUD      = require("modules/ink_hud")
local Mappins     = require("modules/mappins")
local Settings    = require("modules/settings")
local FastTravelNodes = require("modules/fast_travel_nodes")
local ManualNodes = require("modules/manual_nodes")
local UserNodes   = require("modules/user_nodes")
local KnockoutCircuits = require("modules/knockout_circuits")
local AIVehicles  = require("modules/ai_vehicles")
local Liveries    = require("modules/liveries")
local Knockout    = require("modules/knockout")
local UIKnockout  = require("modules/ui_knockout")
local UIKnockoutCircuits = require("modules/ui_knockout_circuits")
local UIGarage    = require("modules/ui_garage")
local UIVehiclePool = require("modules/ui_vehicle_pool")
local EventListeners = require("modules/event_listeners")
local Championships  = require("modules/championships")
local UIChampionships = require("modules/ui_championships")
local NamedRivals    = require("modules/named_rivals")
local Factions       = require("data/factions")
local RadioOSBridge = nil
do
    local ok, mod = pcall(require, "modules/radioos_bridge")
    if ok then
        RadioOSBridge = mod
    else
        print("[NCM/INIT] RadioOS bridge module load failed (non-fatal): " .. tostring(mod))
    end
end

-- Node pool (populated by data/nodes.lua)
local Nodes       = require("data/nodes")
local Tracks      = require("data/tracks")

local function _resolveModule(name, current)
    if current then return current end
    if MTE and MTE[name] then return MTE[name] end
    local ok, mod = pcall(require, "modules/" .. string.lower(name))
    if ok then
        return mod
    end
    print(string.format("[NCM/INIT] Failed to resolve module %s: %s", tostring(name), tostring(mod)))
    return nil
end

-- Share globals so modules can reference each other via MTE table.
MTE = {
    version   = version,
    overlayOpen = false,
    shuttingDown = false,
    Events    = Events,
    I18N      = I18N,
    Persist   = Persist,
    Telemetry = Telemetry,
    Metrics   = Metrics,
    SafetyRating = SafetyRating,
    Tuning    = Tuning,
    Racing    = Racing,
    Roster    = Roster,
    Careers   = Careers,
    Management = Management,
    AmbientRaces = AmbientRaces,
    Parts     = Parts,
    Heat      = Heat,
    Hype      = Hype,
    Betting   = Betting,
    Records   = Records,
    FanEngine = FanEngine,
    ContactEvents = ContactEvents,
    VoiceHarness = VoiceHarness,
    Roots     = Roots,
    Routes    = Routes,
    RaceTelemetry = RaceTelemetry,
    RaceCommands = RaceCommands,
    PhoneBridge = PhoneBridge,
    Onboarding = Onboarding,
    UI        = UI,
    UIRacing  = UIRacing,
    UIRoutes  = UIRoutes,
    UITuning  = UITuning,
    InkHUD    = InkHUD,
    Mappins   = Mappins,
    Settings  = Settings,
    Liveries  = Liveries,
    FastTravelNodes = FastTravelNodes,
    ManualNodes = ManualNodes,
    UserNodes   = UserNodes,
    KnockoutCircuits = KnockoutCircuits,
    AIVehicles = AIVehicles,
    Knockout   = Knockout,
    UIKnockout = UIKnockout,
    UIKnockoutCircuits = UIKnockoutCircuits,
    UIGarage  = UIGarage,
    UIVehiclePool = UIVehiclePool,
    Nodes     = Nodes.all(),
    Tracks    = Tracks,
    Championships  = Championships,
    UIChampionships = UIChampionships,
    NamedRivals   = NamedRivals,
    RadioOSBridge = RadioOSBridge,
    Factions       = Factions,
    -- Console helpers (call via GetMod("MT_Ecosystem").AddNode etc.)
    AddNode    = function(name, region) return UserNodes.add(name, region) end,
    ListNodes  = function() UserNodes.list() end,
    RemoveNode = function(idOrName) return UserNodes.remove(idOrName) end,
    ClearNodes = function() UserNodes.clear() end,
    VoiceMatrix = function()
        return VoiceHarness.matrixText()
    end,
    VoiceScenario = function(id)
        return VoiceHarness.scenarioText(id)
    end,
    VoiceExample = function(id)
        return VoiceHarness.runExample(id)
    end,
    VoiceValidate = function(id, bundle)
        local report, err = VoiceHarness.validateBundle(id, bundle)
        if not report then
            return err or "voice_validation_failed"
        end
        return VoiceHarness.reportText(report)
    end,
    AmbientStatus = function()
        local career = Careers and Careers.active and Careers.active() or nil
        if AmbientRaces and AmbientRaces.statusText then
            return AmbientRaces.statusText(career)
        end
        return "ambient_unavailable"
    end,
    AmbientRefresh = function()
        local career = Careers and Careers.active and Careers.active() or nil
        if AmbientRaces and AmbientRaces.forceRefresh then
            return AmbientRaces.forceRefresh(career)
        end
        return false, "ambient_unavailable"
    end,
    AmbientResolveNext = function()
        local career = Careers and Careers.active and Careers.active() or nil
        if AmbientRaces and AmbientRaces.forceResolveNext then
            return AmbientRaces.forceResolveNext(career)
        end
        return false, "ambient_unavailable"
    end,
    ManagementStatus = function()
        local career = Careers and Careers.active and Careers.active() or nil
        if Management and Management.statusText then
            return Management.statusText(career)
        end
        return "management_unavailable"
    end,
    ManagementCandidates = function(count)
        local career = Careers and Careers.active and Careers.active() or nil
        if Management and Management.candidateText then
            return Management.candidateText(career, count)
        end
        return "management_unavailable"
    end,
    ManagementSignDriver = function(driverId)
        local career = Careers and Careers.active and Careers.active() or nil
        if Management and Management.signDriver then
            return Management.signDriver(career, driverId)
        end
        return false, "management_unavailable"
    end,
    ManagementQueueNext = function(mode)
        local career = Careers and Careers.active and Careers.active() or nil
        if Management and Management.queueSignedDriverForNextEvent then
            return Management.queueSignedDriverForNextEvent(career, 1, mode)
        end
        return false, "management_unavailable"
    end,
    ManagementResolveQueued = function()
        local career = Careers and Careers.active and Careers.active() or nil
        if Management and Management.forceResolveQueuedEvent then
            return Management.forceResolveQueuedEvent(career)
        end
        return false, "management_unavailable"
    end,
    GenerateNamedRivals = function(includeUncached)
        local career = Careers and Careers.active and Careers.active() or nil
        if NamedRivals and NamedRivals.ensureForCareer then
            return NamedRivals.ensureForCareer(career, { includeUncached = includeUncached ~= false })
        end
        return false, "named_rivals_unavailable", 0
    end,
    ManualGridSpawnAhead = function(count)
        if Racing and Racing.manualGridSpawnAhead then
            return Racing.manualGridSpawnAhead(count)
        end
        return false, "manual_grid_unavailable"
    end,
    ManualGridSpawnOne = function()
        if Racing and Racing.manualGridSpawnAhead then
            return Racing.manualGridSpawnAhead(1)
        end
        return false, "manual_grid_unavailable"
    end,
    ManualGridSpawnPair = function()
        if Racing and Racing.manualGridSpawnAhead then
            return Racing.manualGridSpawnAhead(2)
        end
        return false, "manual_grid_unavailable"
    end,
}

-- ── Hotkeys (must be at file scope, NOT inside onInit) ────────

registerHotkey("mte_toggle_panel", "Toggle Night City Motorsports", function()
    UI.panelVisible = not UI.panelVisible
end)

registerHotkey("mte_quick_race", "NCM: Quick Race", function()
    local ok, err = Racing.openQuickRaceConfig and Racing.openQuickRaceConfig()
    if not ok then
        print("[NCM] Quick Race: " .. tostring(err or "Could not open config."))
    end
end)

registerHotkey("mte_stage_now", "NCM: Stage / Warp to Start", function()
    local state = Racing.getState()
    if state ~= Racing.STATE.PRERACE then
        print("[NCM] Stage: no race in PRERACE state.")
        return
    end
    if Racing._autoStageTriggered then
        print("[NCM] Stage: already staged.")
        return
    end
    -- Immediately snap to start (skip approach countdown) and queue launch
    Racing.stageNow()
end)

registerHotkey("mte_lock_grid_heading", "NCM: Lock Grid Heading (aim car first)", function()
    local state = Racing.getState()
    if state == Racing.STATE.COUNTDOWN or state == Racing.STATE.RACING or state == Racing.STATE.RESULTS then
        print("[NCM] Lock Heading: not usable during an active race. Press before or between races.")
        return
    end
    -- Capture the player vehicle's current world-forward as the canonical grid direction.
    local captured = false
    pcall(function()
        local veh = nil
        pcall(function()
            local p = Game.GetPlayer()
            veh = p and Game.GetMountedVehicle(p) or nil
        end)
        local target = veh or Game.GetPlayer()
        if not target or not target.GetWorldForward then return end
        local fwd = target:GetWorldForward()
        local fx = tonumber(fwd and fwd.x or nil)
        local fy = tonumber(fwd and fwd.y or nil)
        if not fx or not fy then return end
        local len = math.sqrt(fx * fx + fy * fy)
        if len < 0.001 then return end
        local nx, ny = fx / len, fy / len
        Racing._lockedGridHeading = math.deg(math.atan2(ny, nx)) % 360.0
        Racing._lockedGridForward = { x = nx, y = ny }
        captured = true
        print(string.format("[NCM] Grid heading locked: %.1f°", Racing._lockedGridHeading))
    end)
    if captured then
        pcall(function()
            local p = Game.GetPlayer()
            if p then
                GameObject.PlaySoundEvent(p, "ui_menu_onpress")
            end
        end)
        if MTE and MTE.Racing then
            -- Surface the locked heading in the UI notify area
            local function _notify(msg, dur)
                pcall(function()
                    if MTE.UI and MTE.UI.notify then MTE.UI.notify(msg, dur) end
                end)
            end
            _notify(string.format("Grid heading locked: %.0f°", Racing._lockedGridHeading), 3.0)
        end
    else
        print("[NCM] Lock Heading: could not read vehicle forward — are you in a car?")
    end
end)

registerHotkey("mte_manual_grid_spawn_one", "NCM: Manual Grid Spawn 1 Rival", function()
    if not (Racing and Racing.manualGridSpawnAhead) then
        print("[NCM] Manual Grid: racing module unavailable.")
        return
    end
    local ok, err = Racing.manualGridSpawnAhead(1)
    if not ok then
        print("[NCM] Manual Grid (1): " .. tostring(err or "spawn failed"))
    end
end)

registerHotkey("mte_manual_grid_spawn_pair", "NCM: Manual Grid Spawn 2 Rivals", function()
    if not (Racing and Racing.manualGridSpawnAhead) then
        print("[NCM] Manual Grid: racing module unavailable.")
        return
    end
    local ok, err = Racing.manualGridSpawnAhead(2)
    if not ok then
        print("[NCM] Manual Grid (2): " .. tostring(err or "spawn failed"))
    end
end)

-- ── Lifecycle ─────────────────────────────────────────────────

registerForEvent("onInit", function()
    print("[Night City Motorsports] v" .. version .. " initialising…")
    print("[NCM/INIT] onInit callback ENTERED")

    Racing = _resolveModule("Racing", Racing)
    if MTE then MTE.Racing = Racing end
    AIVehicles = _resolveModule("AIVehicles", AIVehicles)
    if MTE then MTE.AIVehicles = AIVehicles end
    print("[NCM/INIT] Racing module handle = " .. tostring(Racing))
    print("[NCM/INIT] AIVehicles module handle = " .. tostring(AIVehicles))

    -- Vehicle enter/exit and session start are detected by polling in onUpdate.
    -- (CP2077 method names for Observe vary by patch; polling is always reliable.)

    -- Module-level init
    print("[NCM/INIT] Starting module inits...")
    Persist.init()
    print("[NCM/INIT] Persist OK")
    local localeConfig = Persist.load("config.json") or {}
    I18N.init(localeConfig.locale or "auto")
    Telemetry.init()
    print("[NCM/INIT] Telemetry OK")
    Metrics.init()
    SafetyRating.init()
    Tuning.init()
    Careers.init()
    print("[NCM/INIT] Careers OK")
    Heat.init()
    ManualNodes.init()
    UserNodes.init()
    KnockoutCircuits.init()
    Roots.init()
    Records.init()
    if FanEngine and FanEngine.init then
        FanEngine.init()
    end
    if ContactEvents and ContactEvents.init then
        ContactEvents.init()
    end
    Routes.init()
    RaceTelemetry.init()
    Roster.init()
    NamedRivals.init()
    Management.init()
    -- Auto-load roster (with history seed + catch-up sim) for active career
    do
        local activeCar = Careers.active()
        if activeCar then
            Roster.loadForCareer(activeCar)
            print("[NCM/INIT] Roster loaded for active career: " .. (activeCar.name or "?"))
            local syncOk, syncStatus, syncCount = NamedRivals.ensureForCareer(activeCar, { includeUncached = true })
            print(string.format(
                "[NCM/INIT] Named rival sync: ok=%s status=%s count=%s",
                tostring(syncOk),
                tostring(syncStatus),
                tostring(syncCount)))
        end
    end
    Racing.init()
    print("[NCM/INIT] Racing OK")
    UI.init()
    UIRacing.init()
    UITuning.init()
    InkHUD.init()
    local obsOk, obsErr = pcall(InkHUD.setupObserver)
    if not obsOk then print("[NCM/INIT] InkHUD.setupObserver FAILED (non-fatal): " .. tostring(obsErr)) end
    Mappins.init()
    print("[NCM/INIT] Mappins OK")
    Settings.init()
    do
        local lvOk, lvErr = pcall(Liveries.init)
        if not lvOk then print("[NCM/INIT] Liveries.init FAILED (non-fatal): " .. tostring(lvErr)) end
    end
    Onboarding.init(Settings.current, Careers)
    AmbientRaces.init()
    do
        local vp = require("data/vehicle_pool")
        vp.getUserOverrides = function(tier)
            local overrides = Settings.get("vehiclePoolOverrides")
            return type(overrides) == "table" and overrides[tier] or nil
        end
    end
    FastTravelNodes.init()
    if AIVehicles and AIVehicles.init then
        AIVehicles.init()
        print("[NCM/INIT] AIVehicles OK")
    else
        print("[NCM/INIT] AIVehicles unavailable - skipping init")
    end
    Knockout.init()
    UIKnockout.init()
    EventListeners.init()
    Championships.init()
    UIChampionships.init()
    UIRoutes.init()
    if PhoneBridge and PhoneBridge.init then
        PhoneBridge.init()
    end
    local radioOk, radioErr = pcall(function()
        if RadioOSBridge and RadioOSBridge.init then
            RadioOSBridge.init(MTE)
        end
    end)
    if not radioOk then
        print("[NCM/INIT] RadioOS bridge unavailable (non-fatal): " .. tostring(radioErr))
    end
    print("[NCM/INIT] ALL modules initialised")

    -- The experimental quest/SMS bridge is disabled in the live CET build.
    -- Do not probe those event types here because the race system no longer
    -- depends on them and stale quest plumbing can surface phantom journal UI.
    if Racing and Racing.questBridgeEnabled and Racing.questBridgeEnabled() then
        local rsOk = pcall(function()
            local t = MTERaceQuestEvent.new()
            print("[NCM/INIT] MTERaceQuestEvent.new() = " .. tostring(t))
        end)
        if not rsOk then print("[NCM/INIT] *** MTERaceQuestEvent NOT AVAILABLE — RedScript failed ***") end

        local rsOk2 = pcall(function()
            local t = MTESendSMSEvent.new()
            print("[NCM/INIT] MTESendSMSEvent.new() = " .. tostring(t))
        end)
        if not rsOk2 then print("[NCM/INIT] *** MTESendSMSEvent NOT AVAILABLE — RedScript failed ***") end
    else
        print("[NCM/INIT] Quest/SMS bridge disabled in CET build.")
    end

    local rsOk3 = pcall(function()
        local sys = Game.GetMappinSystem()
        print("[NCM/INIT] MappinSystem = " .. tostring(sys))
    end)
    if not rsOk3 then print("[NCM/INIT] *** MappinSystem NOT AVAILABLE ***") end

    -- Onboarding: welcome message for new players
    if #Careers.list() == 0 then
        print("[Night City Motorsports] Welcome! Open the panel (keybind above) and create a Career to start racing.")
    end

    print("[Night City Motorsports] Ready. Use F6 (or rebind in CET Settings > Bindings) to toggle panel.")
end)

function MTE_SaveRaceStart(label, region)
    return ManualNodes.captureStart(label, region)
end

-- Manual, default-off native quest proof. These helpers are intentionally
-- separate from the race and phone bridges until the NCPD regression gate passes.
local function _queueQuestSpikeOperation(operation)
    local ok, err = pcall(function()
        local evt = MTEQuestSpikeEvent.new()
        evt.operation = tonumber(operation) or 4
        Game.GetUISystem():QueueEvent(evt)
    end)
    if not ok then
        print("[NCM/QuestSpike] operation failed: " .. tostring(err))
        return false
    end
    print("[NCM/QuestSpike] queued operation " .. tostring(operation))
    return true
end

function NCM_QuestSpikeEnable()
    return _queueQuestSpikeOperation(1)
end

function NCM_QuestSpikeActivate()
    return _queueQuestSpikeOperation(2)
end

function NCM_QuestSpikeComplete()
    return _queueQuestSpikeOperation(3)
end

function NCM_QuestSpikeDisable()
    return _queueQuestSpikeOperation(0)
end

function MTE_SaveRaceFinish(label, region)
    return ManualNodes.captureFinish(label, region)
end

function MTE_ClearManualRaceNodes()
    ManualNodes.clear()
end

-- ── User-defined race node console helpers ────────────────────
-- Park on the road, then run these in the CET console.

--- Save current position as a named race node (persists permanently).
--- Usage: MTE_AddNode("My Spot", "Watson")
function MTE_AddNode(name, region)
    return UserNodes.add(name, region)
end

--- List all user-saved nodes.
function MTE_ListNodes()
    UserNodes.list()
end

--- Remove a user node by name or id.
--- Usage: MTE_RemoveNode("My Spot")
function MTE_RemoveNode(idOrName)
    return UserNodes.remove(idOrName)
end

--- Wipe all user-saved nodes.
function MTE_ClearUserNodes()
    UserNodes.clear()
end

function MTE_ManualGridSpawnAhead(count)
    if Racing and Racing.manualGridSpawnAhead then
        return Racing.manualGridSpawnAhead(count)
    end
    return false, "manual_grid_unavailable"
end

function MTE_ManualGridSpawnOne()
    if Racing and Racing.manualGridSpawnAhead then
        return Racing.manualGridSpawnAhead(1)
    end
    return false, "manual_grid_unavailable"
end

function MTE_ManualGridSpawnPair()
    if Racing and Racing.manualGridSpawnAhead then
        return Racing.manualGridSpawnAhead(2)
    end
    return false, "manual_grid_unavailable"
end

-- ── Poll state (for vehicle enter/exit and session detection) ──────

local _pollInVehicle  = false
local _pollInSession  = false

local function _safeCall(mod, moduleName, fnName, ...)
    local fn = mod and mod[fnName]
    if type(fn) ~= "function" then
        return false
    end
    local ok, err = pcall(fn, ...)
    if not ok then
        print(string.format("[NCM] %s.%s failed: %s", moduleName, fnName, tostring(err)))
    end
    return ok
end

local function _pollLifecycle()
    local player    = Game.GetPlayer()
    local inSession = player ~= nil

    -- Session start / end
    if inSession and not _pollInSession then
        _safeCall(Telemetry, "Telemetry", "onSessionStart")
        _safeCall(Metrics, "Metrics", "onSessionStart")
        _safeCall(Racing, "Racing", "onSessionStart")
        _safeCall(AIVehicles, "AIVehicles", "onSessionStart")
        _safeCall(Knockout, "Knockout", "onSessionStart")
        _safeCall(RaceTelemetry, "RaceTelemetry", "onSessionStart")
        -- One native confirmation per loaded gameplay session. This points players
        -- toward the existing Journal/phone surfaces without making CET part of
        -- the normal onboarding path.
        pcall(function()
            local uiSys = Game.GetUISystem()
            if uiSys then
                local evt = SimpleScreenMessage.new()
                evt.message  = "NCM network online. Check your Journal or Messages."
                evt.duration = 5.0
                evt.isShown  = true
                uiSys:QueueEvent(evt)
            end
        end)
    end
    _pollInSession = inSession

    if not inSession then
        if _pollInVehicle then
            _safeCall(Telemetry, "Telemetry", "onVehicleExit")
            _safeCall(Metrics, "Metrics", "onVehicleExit")
            _safeCall(Tuning, "Tuning", "onVehicleExit")
            _pollInVehicle = false
        end
        return
    end

    -- Vehicle enter / exit
    local vehicle   = nil
    local inVehicle = false
    pcall(function()
        vehicle   = Game.GetMountedVehicle(player)
        inVehicle = vehicle ~= nil
    end)

    if inVehicle and not _pollInVehicle then
        _safeCall(Telemetry, "Telemetry", "onVehicleEnter", vehicle)
        _safeCall(Metrics, "Metrics", "onVehicleEnter")
        _safeCall(Tuning, "Tuning", "onVehicleEnter", vehicle)
    elseif not inVehicle and _pollInVehicle then
        _safeCall(Telemetry, "Telemetry", "onVehicleExit")
        _safeCall(Metrics, "Metrics", "onVehicleExit")
        _safeCall(Tuning, "Tuning", "onVehicleExit")
    end
    _pollInVehicle = inVehicle
end

registerForEvent("onUpdate", function(dt)
    _pollLifecycle()

    -- Guard: only run per-frame systems when a session is active
    if not _pollInSession then return end

    if Telemetry and Telemetry.update then Telemetry.update(dt) end
    if Metrics   and Metrics.update   then Metrics.update(dt)   end
    if Tuning    and Tuning.update    then Tuning.update(dt)     end
    if Racing    and Racing.update    then Racing.update(dt)     end
    if RaceTelemetry and RaceTelemetry.update then RaceTelemetry.update(dt) end
    if Knockout  and Knockout.update  then Knockout.update(dt)   end
    if Mappins   and Mappins.update   then Mappins.update(dt)    end
    if AmbientRaces and AmbientRaces.update then AmbientRaces.update(dt) end
    if InkHUD    and InkHUD.update    then InkHUD.update()       end
    if PhoneBridge and PhoneBridge.update then PhoneBridge.update(dt) end
    if RadioOSBridge and RadioOSBridge.update then
        pcall(RadioOSBridge.update, dt, MTE)
    end
end)

-- CET truncates scripting.log on every launch; keep the last session's log next to our saves
-- so a race can still be diagnosed after the next game start (pure file IO, shutdown-safe).
local function snapshotScriptingLog()
    local ok, err = pcall(function()
        local src = io.open("../../scripting.log", "rb")
        if not src then return end
        local data = src:read("*a"); src:close()
        if not data or #data == 0 then return end
        local dst = io.open("save/scripting.last-session.log", "wb")
        if dst then dst:write(data); dst:close() end
    end)
    if not ok then print("[NCM/INIT] scripting.log snapshot failed: " .. tostring(err)) end
end

registerForEvent("onShutdown", function()
    if MTE then MTE.shuttingDown = true end
    snapshotScriptingLog()

    -- Shutdown safety: avoid native UI, entity, mappin, and TweakDB work here.
    -- When the engine is detaching, those calls can crash before Lua reports anything.
    _safeCall(Metrics, "Metrics", "onShutdown")
    _safeCall(Tuning, "Tuning", "_saveVehicleData")
    _safeCall(RaceTelemetry, "RaceTelemetry", "onShutdown")
    if RadioOSBridge and RadioOSBridge.onShutdown then
        pcall(RadioOSBridge.onShutdown, MTE)
    end

    _safeCall(Careers, "Careers", "save")
    _safeCall(Heat, "Heat", "save")
    _safeCall(Records, "Records", "save")
    _safeCall(Roots, "Roots", "save")
    _safeCall(Routes, "Routes", "save")
    _safeCall(SafetyRating, "SafetyRating", "save")
    _safeCall(Settings, "Settings", "save")
    _safeCall(Onboarding, "Onboarding", "save")
    _safeCall(AmbientRaces, "AmbientRaces", "save")
    _safeCall(RaceTelemetry, "RaceTelemetry", "save")
    -- Flush roster cache for active career so rival/stat data is never lost
    if Careers and Careers.active and Roster and Roster.saveForCareer then
        local career = Careers.active()
        if career then Roster.saveForCareer(career) end
    end
    print("[NCM] Shutdown (safe persistence mode).")
end)

registerForEvent("onDraw", function()
    UI = _resolveModule("UI", UI)
    if MTE then MTE.UI = UI end
    if UI and UI.draw then
        UI.draw()
    end
end)

registerForEvent("onOverlayOpen", function()
    if MTE then MTE.overlayOpen = true end
    UI = _resolveModule("UI", UI)
    if MTE then MTE.UI = UI end
    if UI and UI.onOverlayOpen then UI.onOverlayOpen() end
end)

registerForEvent("onOverlayClose", function()
    if MTE then MTE.overlayOpen = false end
    UI = _resolveModule("UI", UI)
    if MTE then MTE.UI = UI end
    if UI and UI.onOverlayClose then UI.onOverlayClose() end
end)

return MTE
