-- ============================================================
-- MT_Ecosystem: modules/settings.lua
-- NativeSettings integration. Adds a "MT Ecosystem" tab to
-- the pause-menu Mods section and owns the shared race/grid
-- tuning registry used by runtime code and root profiles.
-- ============================================================

local Settings = {}
local Persist = require("modules/persistence")
local i18n = require("modules/i18n")

local CONFIG_FILE = "config.json"
local SETTINGS_PATH = "/NightCityMotorsports"
local TUNING_STORE_KEY = "raceTuning"
local LOCALE_OPTIONS = { "auto", "en-us", "de-de", "es-es", "fr-fr", "it-it", "ja-jp", "ko-kr", "pl-pl", "pt-br", "ru-ru", "zh-cn", "zh-tw" }

local DEFAULTS = {
    locale = "auto",
    hudEnabled = true,
    showInputs = true,
    showGForces = true,
    showHealth = true,
    raceMappins = true,
    countdownBeeps = true,
    debugTelemetry = true,
    hudScale = 100,
    hudOpacity = 75,
    suppressTrafficDuringRace = true,
    phoneRaceManagement = true,
    phoneIntroPingSent = false,
    manualGridMode = false,
    playerGridSnapEnabled = false,
    -- CET panel
    panelScale = 100,
    -- Telemetry HUD (native ink, bottom-right)
    telemetryScale = 100,
    telemetryOpacity = 100,
    telemetryOffsetX = 0,
    telemetryOffsetY = 0,
    -- Race HUD (native ink, top-center)
    raceHudScale = 100,
    raceHudOpacity = 100,
    raceHudOffsetX = 0,
    raceHudOffsetY = 0,
    -- Vehicle pool user overrides
    vehiclePoolOverrides = {},
    ambientRacesEnabled = true,
    ambientRaceFrequency = 100,
    ambientRaceMaxConcurrent = 3,
    ambientRaceObservationRadiusM = 250,
    ambientRacePromotionRadiusM = 120,
    ambientRaceDistrictWeights = {
        ["Watson"] = 1.0,
        ["Westbrook"] = 0.9,
        ["Heywood"] = 1.0,
        ["Pacifica"] = 0.75,
        ["Santo Domingo"] = 1.1,
        ["City Center"] = 0.7,
        ["Badlands"] = 0.85,
    },
    ambientRaceTypeWeights = {
        sprint = 60,
        drag = 25,
        knockout = 15,
    },
    ambientRaceAggressionBias = 1.0,
    ambientRaceCrashBias = 1.0,
    ambientRaceWindowVarianceHours = 2,
}

local TUNING_SECTIONS = {
    gridSolver = {
        id = "gridSolver",
        path = "grid_solver",
        label = "Grid Solver",
    },
    raceSettings = {
        id = "raceSettings",
        path = "race_settings",
        label = "Race Settings",
    },
}

local TUNING_FIELDS = {
    { key = "startReadyRadiusM", section = "gridSolver", label = "Start Ready Radius (m)", description = "How close V must be to count as fully staged.", control = "float", min = 5.0, max = 40.0, step = 0.5, format = "%.1f", default = 15.0 },
    { key = "startCaptureRadiusM", section = "gridSolver", label = "Start Capture Radius (m)", description = "Auto-stage approach radius around the start node.", control = "float", min = 10.0, max = 80.0, step = 1.0, format = "%.1f", default = 35.0 },
    { key = "startSnapMaxSpeedMps", section = "gridSolver", label = "Stage Snap Max Speed (m/s)", description = "Maximum speed allowed before the auto-stage snap can fire.", control = "float", min = 1.0, max = 20.0, step = 0.5, format = "%.1f", default = 8.0 },
    { key = "gridSpawnStableTimeS", section = "gridSolver", label = "Grid Stable Time (s)", description = "Clean staged-window time required before the live grid spawn begins.", control = "float", min = 0.10, max = 3.00, step = 0.05, format = "%.2f", default = 0.50 },
    { key = "gridSpawnStableTicks", section = "gridSolver", label = "Grid Stable Ticks", description = "Consecutive clean update ticks required before live grid spawn begins.", control = "int", min = 1, max = 12, step = 1, default = 3 },
    { key = "maxAiCars", section = "gridSolver", label = "Max AI Cars", description = "Hard cap on AI rivals spawned for one grid (12 = classic NCM field; 19 = 20-car formula grid).", control = "int", min = 2, max = 24, step = 1, default = 12 },
    { key = "gridHeadingOffsetDeg", section = "gridSolver", label = "Grid Heading Offset (deg)", description = "Rotates the resolved grid basis before staged slots are laid out.", control = "float", min = -180.0, max = 180.0, step = 1.0, format = "%.0f", default = 0.0 },
    { key = "gridLateralShiftM", section = "gridSolver", label = "Grid Lateral Shift (m)", description = "Moves V and the whole staged grid left or right relative to the resolved grid heading.", control = "float", min = -12.0, max = 12.0, step = 0.25, format = "%.2f", default = 0.0 },
    { key = "startTeleportZLiftM", section = "gridSolver", label = "Stage Teleport Z Lift (m)", description = "Lift V slightly above the road on stage snap to reduce clipping.", control = "float", min = 0.0, max = 6.0, step = 0.1, format = "%.1f", default = 2.5 },
    { key = "startTeleportBackoffM", section = "gridSolver", label = "Stage Teleport Backoff (m)", description = "Place V slightly behind the node instead of directly on top of it.", control = "float", min = 0.0, max = 12.0, step = 0.25, format = "%.2f", default = 4.0 },
    { key = "startSlotHeadingOffsetDeg", section = "gridSolver", label = "Stage Slot Heading Offset (deg)", description = "Yaw offset used when aligning V to the staged slot orientation.", control = "float", min = -180.0, max = 180.0, step = 1.0, format = "%.0f", default = -90.0 },
    { key = "gridForwardAlignmentDot", section = "gridSolver", label = "Grid Forward Alignment Dot", description = "How closely player forward must match the route heading before it influences the grid basis.", control = "float", min = 0.0, max = 1.0, step = 0.01, format = "%.2f", default = 0.55 },
    { key = "trafficClearRadiusM", section = "gridSolver", label = "Traffic Clear Radius (m)", description = "Radius around the start node scrubbed during staging.", control = "float", min = 40.0, max = 250.0, step = 5.0, format = "%.0f", default = 140.0 },
    { key = "trafficClearRetryIntervalS", section = "gridSolver", label = "Traffic Clear Retry Interval (s)", description = "Cadence for repeated ambient-traffic cleanup during staging cooldown.", control = "float", min = 0.10, max = 3.00, step = 0.05, format = "%.2f", default = 0.75 },
    { key = "aiGridRowSpacingM", section = "gridSolver", label = "AI Grid Row Spacing (m)", description = "Distance between AI rows in a standard standing grid.", control = "float", min = 6.0, max = 30.0, step = 0.5, format = "%.1f", default = 12.0 },
    { key = "aiGridColOffsetM", section = "gridSolver", label = "AI Grid Column Offset (m)", description = "Side offset between left and right grid columns.", control = "float", min = 2.0, max = 12.0, step = 0.25, format = "%.2f", default = 4.0 },
    { key = "aiGridStartSetbackM", section = "gridSolver", label = "AI Grid Start Setback (m)", description = "How far the first visible AI row sits behind the player line.", control = "float", min = 0.0, max = 40.0, step = 0.5, format = "%.1f", default = 12.0 },
    { key = "aiRollingRowSpacingM", section = "gridSolver", label = "AI Rolling Row Spacing (m)", description = "Row spacing used when the field forms a rolling start.", control = "float", min = 6.0, max = 30.0, step = 0.5, format = "%.1f", default = 12.0 },
    { key = "aiSideBySideSpacingM", section = "gridSolver", label = "AI Side-By-Side Spacing (m)", description = "Lateral spacing between cars in side-by-side starts.", control = "float", min = 3.0, max = 12.0, step = 0.25, format = "%.2f", default = 6.0 },
    { key = "aiSideBySideSetbackM", section = "gridSolver", label = "AI Side-By-Side Setback (m)", description = "Fallback setback used when side-by-side starts have no explicit player slot.", control = "float", min = 0.0, max = 40.0, step = 0.5, format = "%.1f", default = 18.0 },
    { key = "aiGridForwardAlignmentDot", section = "gridSolver", label = "AI Grid Forward Alignment Dot", description = "How closely player forward must match route heading before AI grid basis respects it.", control = "float", min = 0.0, max = 1.0, step = 0.01, format = "%.2f", default = 0.55 },
    { key = "aiSlotHeadingOffsetDeg", section = "gridSolver", label = "AI Slot Heading Offset (deg)", description = "Yaw offset applied to AI vehicles after the grid basis is resolved.", control = "float", min = -180.0, max = 180.0, step = 1.0, format = "%.0f", default = 90.0 },

    { key = "finishLineWidthM", section = "raceSettings", label = "Finish Line Width (m)", description = "Default lateral distance from the finish node that counts as a crossing.", control = "float", min = 10.0, max = 80.0, step = 1.0, format = "%.1f", default = 35.0 },
    { key = "genericRoadFinishLineWidthM", section = "raceSettings", label = "Generic Road Finish Width (m)", description = "Fallback finish width for user or generic road nodes.", control = "float", min = 10.0, max = 100.0, step = 1.0, format = "%.1f", default = 45.0 },
    { key = "finishArmDistM", section = "raceSettings", label = "Finish Arm Distance (m)", description = "Distance from the finish at which crossing detection arms.", control = "float", min = 40.0, max = 400.0, step = 5.0, format = "%.0f", default = 180.0 },
    { key = "rollingStartMaxSpeedMps", section = "raceSettings", label = "Rolling Start Max Approach Speed (m/s)", description = "Maximum speed V may carry while entering a rolling start.", control = "float", min = 5.0, max = 35.0, step = 0.5, format = "%.1f", default = 20.0 },
    { key = "rollingCountdownSeconds", section = "raceSettings", label = "Rolling Countdown (s)", description = "Release delay once the rolling field is formed.", control = "float", min = 0.2, max = 3.0, step = 0.05, format = "%.2f", default = 0.8 },
    { key = "rollingZoneLengthM", section = "raceSettings", label = "Rolling Zone Length (m)", description = "Controlled discipline zone before open racing begins.", control = "float", min = 20.0, max = 250.0, step = 5.0, format = "%.0f", default = 100.0 },
    { key = "rollingPaceBaseMps", section = "raceSettings", label = "Rolling Pace Base (m/s)", description = "Baseline pole pace during the controlled rolling zone.", control = "float", min = 6.0, max = 30.0, step = 0.5, format = "%.1f", default = 15.5 },
    { key = "rollingPaceMinFloorMps", section = "raceSettings", label = "Rolling Pace Min Floor (m/s)", description = "Minimum controlled rolling pace.", control = "float", min = 4.0, max = 25.0, step = 0.5, format = "%.1f", default = 12.5 },
    { key = "rollingPaceMaxCeilMps", section = "raceSettings", label = "Rolling Pace Max Ceiling (m/s)", description = "Maximum controlled rolling pace.", control = "float", min = 8.0, max = 35.0, step = 0.5, format = "%.1f", default = 20.5 },
    { key = "rollingPlayerWarningIntervalS", section = "raceSettings", label = "Rolling Warning Interval (s)", description = "Cadence for rolling-start give-back and pace-window warnings.", control = "float", min = 0.2, max = 3.0, step = 0.05, format = "%.2f", default = 1.0 },
    { key = "rollingPlayerProgressGraceM", section = "raceSettings", label = "Rolling Progress Grace (m)", description = "Tolerance before V is treated as materially ahead of allowed order or progress.", control = "float", min = 0.5, max = 20.0, step = 0.5, format = "%.1f", default = 6.0 },
    { key = "dragCountdownSeconds", section = "raceSettings", label = "Drag Countdown (s)", description = "Shorter launch tree duration for drag races.", control = "float", min = 0.2, max = 4.0, step = 0.05, format = "%.2f", default = 1.6 },
    { key = "dragRouteMinDistanceM", section = "raceSettings", label = "Drag Route Min Distance (m)", description = "Minimum strip length accepted for drag mode.", control = "float", min = 100.0, max = 1000.0, step = 10.0, format = "%.0f", default = 400.0 },
    { key = "dragRouteMaxDistanceM", section = "raceSettings", label = "Drag Route Max Distance (m)", description = "Maximum strip length accepted for drag mode.", control = "float", min = 300.0, max = 2500.0, step = 25.0, format = "%.0f", default = 1200.0 },
    { key = "dragRouteMaxGrade", section = "raceSettings", label = "Drag Route Max Grade", description = "Reject drag strips steeper than this grade.", control = "float", min = 0.00, max = 0.20, step = 0.005, format = "%.3f", default = 0.08 },
    { key = "dragRouteMaxPathDeviationM", section = "raceSettings", label = "Drag Max Path Deviation (m)", description = "Reference maximum sampled path deviation used by drag straightness scoring.", control = "float", min = 2.0, max = 30.0, step = 0.5, format = "%.1f", default = 12.0 },
    { key = "dragRouteAvgPathDeviationM", section = "raceSettings", label = "Drag Avg Path Deviation (m)", description = "Reference average sustained bend used by drag straightness scoring.", control = "float", min = 0.5, max = 15.0, step = 0.25, format = "%.2f", default = 4.0 },
    { key = "dragRouteHardRejectLoad", section = "raceSettings", label = "Drag Straightness Reject Load", description = "Weighted straightness load above which a sampled strip is rejected outright instead of only taking the time penalty.", control = "float", min = 1.0, max = 4.0, step = 0.05, format = "%.2f", default = 1.20 },
    { key = "dragStraightnessPenaltyMaxS", section = "raceSettings", label = "Drag Straightness Max Penalty (s)", description = "Maximum time penalty applied to eligible but imperfect drag strips.", control = "float", min = 0.0, max = 15.0, step = 0.05, format = "%.2f", default = 3.25 },
    { key = "dragStraightnessPenaltyExponent", section = "raceSettings", label = "Drag Straightness Penalty Curve", description = "Higher values punish crooked eligible strips more aggressively.", control = "float", min = 1.0, max = 4.0, step = 0.05, format = "%.2f", default = 1.85 },
    { key = "dragMinSupportedLanes", section = "raceSettings", label = "Drag Min Supported Lanes", description = "Minimum number of supported lanes required to allow drag mode.", control = "int", min = 2, max = 4, step = 1, default = 2 },
    { key = "dragMaxAiRivals", section = "raceSettings", label = "Drag Max AI Rivals", description = "Maximum AI rivals allowed in the current drag field.", control = "int", min = 1, max = 8, step = 1, default = 5 },
    { key = "dragDefaultMinRoadWidthM", section = "raceSettings", label = "Drag Default Min Road Width (m)", description = "Fallback minimum width for non-road drag candidates.", control = "float", min = 5.0, max = 20.0, step = 0.5, format = "%.1f", default = 8.0 },
    { key = "dragDefaultUrbanRoadWidthM", section = "raceSettings", label = "Drag Urban Road Width (m)", description = "Fallback road width used for urban drag nodes.", control = "float", min = 6.0, max = 24.0, step = 0.5, format = "%.1f", default = 17.0 },
    { key = "dragDefaultOpenRoadWidthM", section = "raceSettings", label = "Drag Open Road Width (m)", description = "Fallback road width used for open-road drag nodes.", control = "float", min = 8.0, max = 28.0, step = 0.5, format = "%.1f", default = 20.0 },
    { key = "dragGenericVehicleWidthM", section = "raceSettings", label = "Drag Generic Vehicle Width (m)", description = "Nominal vehicle width used for drag lane calculations.", control = "float", min = 1.5, max = 3.5, step = 0.05, format = "%.2f", default = 2.25 },
    { key = "dragLaneCenterSpacingM", section = "raceSettings", label = "Drag Lane Center Spacing (m)", description = "Distance between lane centers in drag mode.", control = "float", min = 3.0, max = 10.0, step = 0.1, format = "%.1f", default = 4.0 },
    { key = "dragLateralMarginM", section = "raceSettings", label = "Drag Lateral Margin (m)", description = "Lane edge buffer used in drag width checks.", control = "float", min = 0.0, max = 2.0, step = 0.05, format = "%.2f", default = 0.60 },
    { key = "dragMinFinishWidthM", section = "raceSettings", label = "Drag Min Finish Width (m)", description = "Minimum finish-line width used for drag traps.", control = "float", min = 5.0, max = 25.0, step = 0.5, format = "%.1f", default = 10.0 },
    { key = "dragFinishWidthPerLaneM", section = "raceSettings", label = "Drag Finish Width Per Lane (m)", description = "Extra finish-line width allocated per active drag lane.", control = "float", min = 2.0, max = 8.0, step = 0.1, format = "%.1f", default = 4.5 },
    { key = "dragDnfMinTimeS", section = "raceSettings", label = "Drag DNF Min Time (s)", description = "Absolute minimum DNF window used for drag races.", control = "float", min = 10.0, max = 180.0, step = 1.0, format = "%.0f", default = 60.0 },
    { key = "expectedPlayerRaceSpeedMps", section = "raceSettings", label = "Expected Player Pace (m/s)", description = "Baseline whole-course player pace used for projected race timing.", control = "float", min = 10.0, max = 80.0, step = 0.5, format = "%.1f", default = 38.0 },
    { key = "aiProjectedBaseSpeedMps", section = "raceSettings", label = "AI Projected Base Pace (m/s)", description = "Baseline whole-course rival pace used for AI finish estimates.", control = "float", min = 10.0, max = 140.0, step = 0.5, format = "%.1f", default = 38.0 },
    { key = "dnfExpectedTimeMult", section = "raceSettings", label = "DNF Expected Time Mult", description = "Grace multiplier applied to the player's projected finish time.", control = "float", min = 1.0, max = 8.0, step = 0.05, format = "%.2f", default = 3.25 },
    { key = "dnfSlowestAiMult", section = "raceSettings", label = "DNF Slowest AI Mult", description = "Grace multiplier applied to the slowest projected AI finish time.", control = "float", min = 1.0, max = 4.0, step = 0.05, format = "%.2f", default = 1.55 },
    { key = "dnfSlowestAiGraceS", section = "raceSettings", label = "DNF Slowest AI Grace (s)", description = "Fixed extra seconds added on top of the slowest projected AI finish.", control = "float", min = 0.0, max = 240.0, step = 5.0, format = "%.0f", default = 90.0 },
    { key = "dnfMinTimeS", section = "raceSettings", label = "DNF Min Time (s)", description = "Absolute minimum sprint DNF window.", control = "float", min = 30.0, max = 600.0, step = 5.0, format = "%.0f", default = 150.0 },
    { key = "dnfMaxTimeS", section = "raceSettings", label = "DNF Max Time (s)", description = "Absolute maximum race DNF window.", control = "float", min = 120.0, max = 2400.0, step = 10.0, format = "%.0f", default = 1200.0 },
    { key = "dnfNearFinishDistanceM", section = "raceSettings", label = "Near-Finish DNF Distance (m)", description = "Distance to the line that arms the one-shot near-finish grace.", control = "float", min = 20.0, max = 400.0, step = 5.0, format = "%.0f", default = 175.0 },
    { key = "dnfNearFinishGraceS", section = "raceSettings", label = "Near-Finish DNF Grace (s)", description = "Extra seconds granted once the player enters the near-finish window.", control = "float", min = 1.0, max = 60.0, step = 1.0, format = "%.0f", default = 20.0 },
    { key = "finishResolveMinWaitS", section = "raceSettings", label = "Finish Resolve Min Wait (s)", description = "Minimum live classification wait after V crosses the finish.", control = "float", min = 0.2, max = 10.0, step = 0.05, format = "%.2f", default = 1.75 },
    { key = "finishResolveMaxWaitS", section = "raceSettings", label = "Finish Resolve Max Wait (s)", description = "Maximum wait before the trailing field is simulated.", control = "float", min = 0.5, max = 12.0, step = 0.05, format = "%.2f", default = 6.50 },
    { key = "finishResolveVisibleGapCapS", section = "raceSettings", label = "Finish Resolve Visible Gap Cap (s)", description = "Maximum projected visible-rival gap that still extends the live finish wait.", control = "float", min = 0.2, max = 10.0, step = 0.05, format = "%.2f", default = 4.50 },
    { key = "finishResolveGapBufferS", section = "raceSettings", label = "Finish Resolve Gap Buffer (s)", description = "Extra cushion applied over the projected trailing visible gap.", control = "float", min = 0.0, max = 3.0, step = 0.05, format = "%.2f", default = 0.90 },
    { key = "finishResolveSimTailStepS", section = "raceSettings", label = "Finish Resolve Sim Tail Step (s)", description = "Tail spacing applied when simulated visible rivals are resolved.", control = "float", min = 0.01, max = 1.0, step = 0.01, format = "%.2f", default = 0.18 },
    { key = "finishResolveUntrackedOffsetS", section = "raceSettings", label = "Finish Resolve Untracked Offset (s)", description = "Base offset applied to untracked rivals behind the scored live field.", control = "float", min = 0.5, max = 15.0, step = 0.1, format = "%.1f", default = 5.0 },
    { key = "aiBaseSpeedMps", section = "raceSettings", label = "AI Base Pace (m/s)", description = "Whole-course pace anchor used before driver tier, personality, urgency, and hardware produce live straight-line command speed.", control = "float", min = 5.0, max = 120.0, step = 0.5, format = "%.1f", default = 38.0 },
    { key = "aiRaceMaxSpeedMps", section = "raceSettings", label = "AI Race Max Speed (m/s)", description = "Maximum live straight-line race command speed after pace, urgency, and hardware modifiers are applied.", control = "float", min = 10.0, max = 160.0, step = 0.5, format = "%.1f", default = 75.0 },
    { key = "aiCruiseMaxSpeedMps", section = "raceSettings", label = "AI Cruise Max Speed (m/s)", description = "Maximum steady-state speed cap used by non-race AI driving outside an active race context.", control = "float", min = 5.0, max = 120.0, step = 0.5, format = "%.1f", default = 45.0 },
    { key = "aiMinSpeedFrac", section = "raceSettings", label = "AI Min Speed Fraction", description = "Minimum AI command speed fraction relative to max speed; lower values leave more room to slow for corners.", control = "float", min = 0.10, max = 0.99, step = 0.01, format = "%.2f", default = 0.55 },
    { key = "aiRecommandIntervalS", section = "raceSettings", label = "AI Recommand Interval (s)", description = "Cadence for re-issuing AI drive commands when a slot is still healthy.", control = "float", min = 0.5, max = 8.0, step = 0.1, format = "%.1f", default = 1.0 },
    { key = "aiStallSpeedThreshMps", section = "raceSettings", label = "AI Stall Speed Threshold (m/s)", description = "Below this speed a launched AI car is treated as stalled.", control = "float", min = 0.1, max = 30.0, step = 0.1, format = "%.1f", default = 8.0 },
    { key = "aiStallTimeThreshS", section = "raceSettings", label = "AI Stall Time Threshold (s)", description = "How long an AI car may remain stalled before a fresh command is issued.", control = "float", min = 0.5, max = 5.0, step = 0.05, format = "%.2f", default = 1.2 },
    { key = "aiLaunchGraceTimeS", section = "raceSettings", label = "AI Launch Grace Time (s)", description = "Delay after the green before stall and recommand logic starts punishing launches.", control = "float", min = 0.0, max = 5.0, step = 0.05, format = "%.2f", default = 1.75 },
    { key = "aiLaunchReleaseMaxSpeedCapMps", section = "raceSettings", label = "AI Launch Release Max Speed (m/s)", description = "Maximum speed cap on the first release command out of the grid.", control = "float", min = 1.0, max = 80.0, step = 0.5, format = "%.1f", default = 35.0 },
    { key = "aiLaunchReleaseMinSpeedCapMps", section = "raceSettings", label = "AI Launch Release Min Speed (m/s)", description = "Minimum speed cap used on the first release command out of the grid.", control = "float", min = 0.5, max = 60.0, step = 0.5, format = "%.1f", default = 18.0 },
    { key = "aiLaunchReleaseForcedSpeedCapMps", section = "raceSettings", label = "AI Launch Release Forced Speed (m/s)", description = "Forced start speed cap used during initial launch release.", control = "float", min = 0.0, max = 40.0, step = 0.5, format = "%.1f", default = 18.0 },
    { key = "aiLaunchReleaseTargetDistanceM", section = "raceSettings", label = "AI Launch Release Target Distance (m)", description = "First-release autonomous target distance used to get the AI cleanly off the line.", control = "float", min = 2.0, max = 20.0, step = 0.5, format = "%.1f", default = 7.5 },
    { key = "aiAutonomousTargetDistanceM", section = "raceSettings", label = "AI Autonomous Target Distance (m)", description = "Baseline autonomous target distance for race AI commands.", control = "float", min = 4.0, max = 30.0, step = 0.5, format = "%.1f", default = 12.0 },
    { key = "aiFinishRunoffDistanceM", section = "raceSettings", label = "AI Finish Runoff Distance (m)", description = "How far sprint and knockout AI continue beyond the finish.", control = "float", min = 20.0, max = 200.0, step = 2.0, format = "%.0f", default = 72.0 },
    { key = "aiDragFinishRunoffDistanceM", section = "raceSettings", label = "AI Drag Finish Runoff Distance (m)", description = "How far drag AI continue beyond the traps before they can settle.", control = "float", min = 40.0, max = 300.0, step = 5.0, format = "%.0f", default = 120.0 },
    { key = "aiChaseDistanceMinM", section = "raceSettings", label = "AI Chase Min Distance (m)", description = "Baseline closest chase gap before aggression and racecraft adjustments.", control = "float", min = 2.0, max = 15.0, step = 0.25, format = "%.2f", default = 6.0 },
    { key = "aiChaseDistanceMaxM", section = "raceSettings", label = "AI Chase Max Distance (m)", description = "Baseline farthest chase gap before aggression and racecraft adjustments.", control = "float", min = 8.0, max = 40.0, step = 0.5, format = "%.1f", default = 28.0 },
    { key = "aiFollowDistanceMinM", section = "raceSettings", label = "AI Follow Min Distance (m)", description = "Baseline minimum follow gap for non-chase AI.", control = "float", min = 2.0, max = 20.0, step = 0.25, format = "%.2f", default = 8.0 },
    { key = "aiFollowDistanceMaxM", section = "raceSettings", label = "AI Follow Max Distance (m)", description = "Baseline maximum follow gap for non-chase AI.", control = "float", min = 8.0, max = 50.0, step = 0.5, format = "%.1f", default = 34.0 },
    { key = "aiRollingControlIntervalS", section = "raceSettings", label = "AI Rolling Control Interval (s)", description = "Cadence for re-issuing rolling-start pace and order commands.", control = "float", min = 0.10, max = 2.0, step = 0.05, format = "%.2f", default = 0.30 },
    { key = "aiRollingWarmupIntervalS", section = "raceSettings", label = "AI Rolling Warmup Interval (s)", description = "Cadence for rolling-start warmup rev theatrics before green.", control = "float", min = 0.10, max = 2.0, step = 0.05, format = "%.2f", default = 0.55 },
    { key = "aiRollingWarmupMaxBlips", section = "raceSettings", label = "AI Rolling Warmup Max Blips", description = "Maximum rev-ready event bursts per warmup tick.", control = "int", min = 1, max = 8, step = 1, default = 3 },
    { key = "aiRollingWeaveSpeedBiasMps", section = "raceSettings", label = "AI Rolling Weave Speed Bias", description = "Maximum speed bias caused by rolling-start weave aggression.", control = "float", min = 0.0, max = 4.0, step = 0.1, format = "%.1f", default = 1.6 },
    { key = "aiRollingCreepMaxMeters", section = "raceSettings", label = "AI Rolling Creep Max (m)", description = "Maximum forward pressure allowed inside the rolling-start formation.", control = "float", min = 0.0, max = 8.0, step = 0.1, format = "%.1f", default = 2.2 },
}

local TUNING_FIELDS_BY_KEY = {}

for _, field in ipairs(TUNING_FIELDS) do
    TUNING_FIELDS_BY_KEY[field.key] = field
end

Settings.current = {}

local function clone(value)
    return Persist.clone and Persist.clone(value) or value
end

local function getTuningStore(tbl)
    if type(tbl[TUNING_STORE_KEY]) ~= "table" then
        tbl[TUNING_STORE_KEY] = {}
    end
    return tbl[TUNING_STORE_KEY]
end

local function clampValue(field, value)
    if field == nil then
        return value
    end

    local number = tonumber(value)
    if number == nil then
        number = field.default
    end
    if field.control == "int" then
        number = math.floor(number + 0.00001)
    end
    if field.min ~= nil and number < field.min then
        number = field.min
    end
    if field.max ~= nil and number > field.max then
        number = field.max
    end
    return number
end

local function applyDefaults(tbl)
    for key, value in pairs(DEFAULTS) do
        if tbl[key] == nil then
            tbl[key] = value
        end
    end

    local tuning = getTuningStore(tbl)
    for _, field in ipairs(TUNING_FIELDS) do
        tuning[field.key] = clampValue(field, tuning[field.key])
    end
end

local function save()
    Persist.save(CONFIG_FILE, Settings.current)
end

local function resolveProfileTable(context)
    if type(context) == "table" then
        if type(context.rootProfileSettings) == "table" then
            return context.rootProfileSettings
        end
        if type(context.profileSettings) == "table" then
            return context.profileSettings
        end
        local rootId = context.selectedRootId or context.rootId
        if rootId and MTE and MTE.Roots and MTE.Roots.get then
            local root = MTE.Roots.get(rootId)
            if root and type(root.profileSettings) == "table" then
                return root.profileSettings
            end
        end
        return nil
    end

    if type(context) == "string" and MTE and MTE.Roots and MTE.Roots.get then
        local root = MTE.Roots.get(context)
        if root and type(root.profileSettings) == "table" then
            return root.profileSettings
        end
    end
    return nil
end

local function copyResolvedProfile(sourceTable)
    local resolved = {}
    for _, field in ipairs(TUNING_FIELDS) do
        resolved[field.key] = clampValue(field, sourceTable and sourceTable[field.key])
    end
    return resolved
end

local function registerBaseSettings(ns, path, cfg)
    ns.addSubcategory(path .. "/localization", "Language")
    local localeIndex = 1
    for index, locale in ipairs(LOCALE_OPTIONS) do if locale == cfg.locale then localeIndex = index break end end
    ns.addSelectorString(path .. "/localization", "NCM Language", "Auto follows Cyberpunk's On-Screen language. Changes apply after reloading the mod or restarting the game.", LOCALE_OPTIONS, localeIndex, 1, function(index)
        cfg.locale = LOCALE_OPTIONS[index] or "auto"
        save()
    end)

    ns.addSubcategory(path .. "/display", "Display")
    ns.addSwitch(path .. "/display", "Enable HUD", "Show the telemetry panel while driving.", cfg.hudEnabled, DEFAULTS.hudEnabled, function(v)
        cfg.hudEnabled = v
        save()
    end)
    ns.addSwitch(path .. "/display", "Show Inputs (THR/BRK/CLT)", "Show throttle, brake, and clutch input bars.", cfg.showInputs, DEFAULTS.showInputs, function(v)
        cfg.showInputs = v
        save()
    end)
    ns.addSwitch(path .. "/display", "Show G-Forces", "Show longitudinal and lateral G readouts.", cfg.showGForces, DEFAULTS.showGForces, function(v)
        cfg.showGForces = v
        save()
    end)
    ns.addSwitch(path .. "/display", "Show Vehicle Health", "Show a vehicle health bar.", cfg.showHealth, DEFAULTS.showHealth, function(v)
        cfg.showHealth = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Telemetry Scale (%)", "Scale of the in-game telemetry panel (25-300).", 25, 300, 5, cfg.telemetryScale, DEFAULTS.telemetryScale, function(v)
        cfg.telemetryScale = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Telemetry Opacity (%)", "Opacity of the in-game telemetry panel.", 5, 100, 5, cfg.telemetryOpacity, DEFAULTS.telemetryOpacity, function(v)
        cfg.telemetryOpacity = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Telemetry Offset X", "Horizontal offset of the telemetry panel (px).", -800, 800, 10, cfg.telemetryOffsetX, DEFAULTS.telemetryOffsetX, function(v)
        cfg.telemetryOffsetX = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Telemetry Offset Y", "Vertical offset of the telemetry panel (px).", -600, 600, 10, cfg.telemetryOffsetY, DEFAULTS.telemetryOffsetY, function(v)
        cfg.telemetryOffsetY = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Race HUD Scale (%)", "Scale of the in-game race overlay (25-300).", 25, 300, 5, cfg.raceHudScale, DEFAULTS.raceHudScale, function(v)
        cfg.raceHudScale = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Race HUD Opacity (%)", "Opacity of the in-game race overlay.", 5, 100, 5, cfg.raceHudOpacity, DEFAULTS.raceHudOpacity, function(v)
        cfg.raceHudOpacity = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Race HUD Offset X", "Horizontal offset of the race overlay (px).", -800, 800, 10, cfg.raceHudOffsetX, DEFAULTS.raceHudOffsetX, function(v)
        cfg.raceHudOffsetX = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "Race HUD Offset Y", "Vertical offset of the race overlay (px).", -600, 600, 10, cfg.raceHudOffsetY, DEFAULTS.raceHudOffsetY, function(v)
        cfg.raceHudOffsetY = v
        save()
    end)
    ns.addRangeInt(path .. "/display", "CET Panel Scale (%)", "Scale of the CET ImGui overlay window.", 50, 400, 5, cfg.panelScale, DEFAULTS.panelScale, function(v)
        cfg.panelScale = v
        save()
    end)

    ns.addSubcategory(path .. "/racing", "Racing")
    ns.addSwitch(path .. "/racing", "Race Map Markers", "Place start/finish markers on the map when a race is configured.", cfg.raceMappins, DEFAULTS.raceMappins, function(v)
        cfg.raceMappins = v
        save()
    end)
    ns.addSwitch(path .. "/racing", "Countdown Beeps", "Play a sound during the race countdown (requires in-game audio events).", cfg.countdownBeeps, DEFAULTS.countdownBeeps, function(v)
        cfg.countdownBeeps = v
        save()
    end)
    ns.addSwitch(path .. "/racing", "Debug Telemetry", "Show spawn report and slot diagnostics in the prerace and racing panels.", cfg.debugTelemetry, DEFAULTS.debugTelemetry, function(v)
        cfg.debugTelemetry = v
        save()
    end)
    ns.addSwitch(path .. "/racing", "Suppress Traffic During Races", "Clears ambient traffic and pedestrians when a race starts. Disable to race in live traffic.", cfg.suppressTrafficDuringRace, DEFAULTS.suppressTrafficDuringRace, function(v)
        cfg.suppressTrafficDuringRace = v
        save()
    end)
    ns.addSwitch(path .. "/racing", "Phone Race Management", "Allow the Night City Motorsports phone contact to run race commands from text-message choices.", cfg.phoneRaceManagement, DEFAULTS.phoneRaceManagement, function(v)
        cfg.phoneRaceManagement = v
        save()
    end)
    ns.addSwitch(path .. "/racing", "Player Grid Snap", "When enabled, V can be auto-snapped or warped onto the start grid. Disable to drive into the grid spot manually.", cfg.playerGridSnapEnabled, DEFAULTS.playerGridSnapEnabled, function(v)
        cfg.playerGridSnapEnabled = v
        save()
    end)
    ns.addSwitch(path .. "/racing", "Manual Grid Mode", "Disables automatic prerace AI grid dispatch. Use the manual grid hotkeys or CET console helpers to spawn 1 or 2 rivals directly ahead of V.", cfg.manualGridMode, DEFAULTS.manualGridMode, function(v)
        cfg.manualGridMode = v
        save()
    end)

    ns.addSubcategory(path .. "/world", "Ambient World")
    ns.addSwitch(path .. "/world", "Ambient Races", "Run the background ambient race scheduler for the active career.", cfg.ambientRacesEnabled, DEFAULTS.ambientRacesEnabled, function(v)
        cfg.ambientRacesEnabled = v
        save()
    end)
    ns.addRangeInt(path .. "/world", "Ambient Frequency (%)", "Controls how densely the scheduler keeps upcoming ambient race windows filled.", 25, 200, 5, cfg.ambientRaceFrequency, DEFAULTS.ambientRaceFrequency, function(v)
        cfg.ambientRaceFrequency = v
        save()
    end)
    ns.addRangeInt(path .. "/world", "Ambient Max Concurrent", "Maximum number of simultaneous scheduled ambient race windows kept alive for the active career.", 1, 8, 1, cfg.ambientRaceMaxConcurrent, DEFAULTS.ambientRaceMaxConcurrent, function(v)
        cfg.ambientRaceMaxConcurrent = v
        save()
    end)
    ns.addRangeInt(path .. "/world", "Ambient Observation Radius (m)", "Reserved for in-world surfacing and discovery checks as ambient events get promoted into the live world.", 50, 1200, 25, cfg.ambientRaceObservationRadiusM, DEFAULTS.ambientRaceObservationRadiusM, function(v)
        cfg.ambientRaceObservationRadiusM = v
        save()
    end)
    ns.addRangeInt(path .. "/world", "Ambient Promotion Radius (m)", "Reserved radius for selecting the small number of ambient races that can become visible candidates.", 50, 1000, 25, cfg.ambientRacePromotionRadiusM, DEFAULTS.ambientRacePromotionRadiusM, function(v)
        cfg.ambientRacePromotionRadiusM = v
        save()
    end)
    ns.addRangeFloat(path .. "/world", "Ambient Aggression Bias", "Scales how much driver aggression influences off-screen ambient results.", 0.4, 2.0, 0.05, "%.2f", cfg.ambientRaceAggressionBias, DEFAULTS.ambientRaceAggressionBias, function(v)
        cfg.ambientRaceAggressionBias = v
        save()
    end)
    ns.addRangeFloat(path .. "/world", "Ambient Crash Bias", "Scales crash and washout risk during ambient off-screen resolution.", 0.2, 2.0, 0.05, "%.2f", cfg.ambientRaceCrashBias, DEFAULTS.ambientRaceCrashBias, function(v)
        cfg.ambientRaceCrashBias = v
        save()
    end)
    ns.addRangeInt(path .. "/world", "Ambient Window Variance (h)", "How much random drift each scheduled ambient race window gets around its baseline start time.", 0, 6, 1, cfg.ambientRaceWindowVarianceHours, DEFAULTS.ambientRaceWindowVarianceHours, function(v)
        cfg.ambientRaceWindowVarianceHours = v
        save()
    end)
end

local function registerTuningSettings(ns, path, cfg)
    local tuning = getTuningStore(cfg)
    for _, section in pairs(TUNING_SECTIONS) do
        ns.addSubcategory(path .. "/" .. section.path, section.label)
        for _, field in ipairs(TUNING_FIELDS) do
            if field.section == section.id then
                local fieldPath = path .. "/" .. section.path
                if field.control == "int" then
                    ns.addRangeInt(fieldPath, field.label, field.description, field.min, field.max, field.step, tuning[field.key], field.default, function(v)
                        tuning[field.key] = clampValue(field, v)
                        save()
                    end)
                else
                    ns.addRangeFloat(fieldPath, field.label, field.description, field.min, field.max, field.step, field.format or "%.2f", tuning[field.key], field.default, function(v)
                        tuning[field.key] = clampValue(field, v)
                        save()
                    end)
                end
            end
        end
    end
end

function Settings.init()
    local loaded = Persist.load(CONFIG_FILE)
    Settings.current = loaded or {}
    applyDefaults(Settings.current)

    local ns = i18n.wrapNativeSettings(GetMod("nativeSettings"))
    if not ns then
        print("[NCM/Settings] NativeSettings not found - config only via config.json")
        return
    end

    local cfg = Settings.current
    local path = SETTINGS_PATH

    ns.addTab(path, "NIGHT CITY MOTORSPORTS")
    registerBaseSettings(ns, path, cfg)
    registerTuningSettings(ns, path, cfg)
end

function Settings.save()
    return save()
end

function Settings.get(key)
    return Settings.current[key]
end

function Settings.getTuningFields(sectionId)
    local fields = {}
    for _, field in ipairs(TUNING_FIELDS) do
        if sectionId == nil or field.section == sectionId then
            fields[#fields + 1] = field
        end
    end
    return fields
end

function Settings.getTuningSections()
    return TUNING_SECTIONS
end

function Settings.getTuningField(key)
    return TUNING_FIELDS_BY_KEY[key]
end

function Settings.getTuningDefault(key)
    local field = TUNING_FIELDS_BY_KEY[key]
    return field and field.default or nil
end

function Settings.resolveTuningProfile(context)
    local globalTuning = getTuningStore(Settings.current)
    local resolved = copyResolvedProfile(globalTuning)
    local profile = resolveProfileTable(context)
    if type(profile) == "table" then
        for _, field in ipairs(TUNING_FIELDS) do
            if profile[field.key] ~= nil then
                resolved[field.key] = clampValue(field, profile[field.key])
            end
        end
    end
    return resolved
end

function Settings.getTuningValue(key, context)
    local field = TUNING_FIELDS_BY_KEY[key]
    if not field then
        return nil
    end
    local resolved = Settings.resolveTuningProfile(context)
    return resolved[key]
end

function Settings.normalizeTuningValue(key, value)
    local field = TUNING_FIELDS_BY_KEY[key]
    if not field then
        return nil
    end
    return clampValue(field, value)
end

function Settings.sanitizeProfileSettings(profile)
    if type(profile) ~= "table" then
        return nil
    end
    local sanitized = {}
    local count = 0
    for _, field in ipairs(TUNING_FIELDS) do
        if profile[field.key] ~= nil then
            sanitized[field.key] = clampValue(field, profile[field.key])
            count = count + 1
        end
    end
    if count <= 0 then
        return nil
    end
    return sanitized
end

function Settings.setTuningValue(key, value)
    local field = TUNING_FIELDS_BY_KEY[key]
    if not field then
        return nil
    end
    local tuning = getTuningStore(Settings.current)
    tuning[key] = clampValue(field, value)
    save()
    return tuning[key]
end

function Settings.resetTuningSection(sectionId)
    local tuning = getTuningStore(Settings.current)
    for _, field in ipairs(TUNING_FIELDS) do
        if sectionId == nil or field.section == sectionId then
            tuning[field.key] = field.default
        end
    end
    save()
end

function Settings.captureGlobalTuningProfile()
    local globalTuning = getTuningStore(Settings.current)
    return clone(copyResolvedProfile(globalTuning))
end

function Settings.countProfileSettings(profile)
    if type(profile) ~= "table" then
        return 0
    end
    local count = 0
    for _, field in ipairs(TUNING_FIELDS) do
        if profile[field.key] ~= nil then
            count = count + 1
        end
    end
    return count
end

return Settings
