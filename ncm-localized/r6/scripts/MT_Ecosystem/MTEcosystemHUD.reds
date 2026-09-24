// ============================================================
// Night City Motorsports: Native HUD + Mappin System via RedScript
//
// Three subsystems:
//   1) Telemetry panel — anchored bottom-right near minimap
//   2) Race overlay    — top-center countdown/position/timer
//   3) Map markers     — race start/finish mappins on world map
//
// Communication from CET Lua → RedScript:
//   Game.GetUISystem():QueueEvent(evt)
// ============================================================

// ── Events ────────────────────────────────────────────────────

public class MTEHudUpdateEvent extends Event {
  // Vehicle telemetry
  public let speedKph: Float;
  public let gear: Int32;
  public let rpm: Float;
  public let inVehicle: Bool;

  // Inputs (0.0–1.0 unless noted)
  public let throttle: Float;
  public let brake: Float;
  public let clutch: Float;
  public let steering: Float;      // -1.0 left … +1.0 right
  public let handbrake: Bool;

  // Derived
  public let longG: Float;
  public let latG: Float;
  public let accelRate: Float;
  public let decelRate: Float;
  public let vehicleHealth: Float;  // 0.0–1.0

  // Display toggles (from settings)
  public let showInputs: Bool;
  public let showGForces: Bool;
  public let showHealth: Bool;
  public let hudEnabled: Bool;

  // HUD layout overrides (from settings)
  public let telemetryScale: Float;    // 0.5–2.0 (1.0 = 100%)
  public let telemetryOpacity: Float;  // 0.0–1.0
  public let telemetryOffsetX: Float;  // pixels
  public let telemetryOffsetY: Float;  // pixels
  public let raceHudScale: Float;      // 0.5–2.0
  public let raceHudOpacity: Float;    // 0.0–1.0
  public let raceHudOffsetX: Float;    // pixels
  public let raceHudOffsetY: Float;    // pixels

  // Race state
  public let raceActive: Bool;
  public let raceCountdown: Bool;
  public let preraceActive: Bool;
  public let qualiActive: Bool;
  public let countdownValue: Int32;
  public let racePosition: Int32;
  public let raceFieldSize: Int32;
  public let raceTime: Float;
  public let trackName: String;
  public let standingsText: String;  // pre-formatted multi-line standings
  public let distToFinish: Float;    // metres to finish, -1 if N/A
  public let countdownPhase: Int32;  // 5=all red, 4..1 = lights going out, 0=all green
  public let gapText: String;        // e.g. "+1.3s" or "-0.5s"
  public let gapBehindText: String;  // gap to car behind, e.g. "-0.8s"
  public let startType: String;      // "grid", "rolling", "sidebyside"
  public let phaseLabel: String;
  public let objectiveText: String;
  public let statusText: String;
  public let qualiRequired: Bool;
  public let qualiCompleted: Bool;
  public let qualiGridPos: Int32;
  public let stageReadyCount: Int32;
  public let stageTotalCount: Int32;
  public let stageSpawning: Bool;
  public let playerStartReady: Bool;
  public let playerStartReason: String;
  public let finishLabel: String;

  // Knockout mode
  public let knockoutActive: Bool;
  public let eliminationCountdown: Float;  // seconds until next elimination
  public let remainingDrivers: Int32;
  public let isInDangerZone: Bool;
  public let lastEliminatedName: String;
  public let knockoutPhase: String;        // "early", "mid", "late", "final"

  // Rival callout (nearest rival driver ahead / behind)
  public let rivalAheadName: String;   // empty = no rival nearby
  public let rivalIsAhead: Bool;       // true = rival is ahead of player
}

public class MTEHudHideEvent extends Event {}

public class MTEPrestigeRevealEvent extends Event {
  public let direction: String;
  public let fromTier: String;
  public let toTier: String;
  public let title: String;
  public let body: String;
}

public class MTESeasonLadderEvent extends Event {
  public let direction: String;
  public let title: String;
  public let summary: String;
  public let movementText: String;
  public let ladderText: String;
  public let footerText: String;
}

// Mappin events (CET → RedScript bridge)
public class MTEPlaceMappinEvent extends Event {
  public let posX: Float;
  public let posY: Float;
  public let posZ: Float;
  public let isStart: Bool;    // true = start marker, false = finish marker
  public let trackAsNav: Bool; // if true, track this mappin as the GPS nav target
  public let markerRole: String; // "center", "left", "right"
  public let markerTitle: String;
  public let markerCaption: String;
}

public class MTEClearMappinsEvent extends Event {}

public class MTEClearRacerMappinsEvent extends Event {}

// Switch active GPS nav target between start/finish mappins
public class MTETrackMappinEvent extends Event {
  public let trackFinish: Bool; // true = track finish, false = track start
}

// Race result card — fired once when a race ends
public class MTERaceResultEvent extends Event {
  public let position: Int32;
  public let fieldSize: Int32;
  public let timeStr: String;
  public let payout: Int32;
  public let repGain: Int32;
  public let isClean: Bool;
  public let isDNF: Bool;
  public let wagerResult: String;   // "", "WON", "LOST"
  public let bountyText: String;
  public let dragPenaltyText: String; // e.g. "STR 85 | PEN +0.42s"
}

// ── Widget references ─────────────────────────────────────────

// Telemetry panel (bottom-right near minimap)
@addField(inkGameController)
private let mteHudContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteSpeedText: wref<inkText>;

@addField(inkGameController)
private let mteKphLabel: wref<inkText>;

@addField(inkGameController)
private let mteGearText: wref<inkText>;

@addField(inkGameController)
private let mteRpmBar: wref<inkRectangle>;

@addField(inkGameController)
private let mteRpmBarBg: wref<inkRectangle>;

@addField(inkGameController)
private let mteThrottleBar: wref<inkRectangle>;

@addField(inkGameController)
private let mteThrottleBarBg: wref<inkRectangle>;

@addField(inkGameController)
private let mteBrakeBar: wref<inkRectangle>;

@addField(inkGameController)
private let mteBrakeBarBg: wref<inkRectangle>;

@addField(inkGameController)
private let mteClutchBar: wref<inkRectangle>;

@addField(inkGameController)
private let mteClutchBarBg: wref<inkRectangle>;

@addField(inkGameController)
private let mteSteeringText: wref<inkText>;

@addField(inkGameController)
private let mteHandbrakeText: wref<inkText>;

@addField(inkGameController)
private let mteLongGText: wref<inkText>;

@addField(inkGameController)
private let mteLatGText: wref<inkText>;

@addField(inkGameController)
private let mteHealthBar: wref<inkRectangle>;

@addField(inkGameController)
private let mteHealthBarBg: wref<inkRectangle>;

// Container refs for conditional rows
@addField(inkGameController)
private let mteInputsContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteGContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteHealthContainer: wref<inkCompoundWidget>;

// Race overlay (top center)
@addField(inkGameController)
private let mteRaceContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteTrackText: wref<inkText>;

@addField(inkGameController)
private let mteCountdownText: wref<inkText>;

@addField(inkGameController)
private let mtePosText: wref<inkText>;

@addField(inkGameController)
private let mteTimeText: wref<inkText>;

@addField(inkGameController)
private let mteStandingsText: wref<inkText>;

@addField(inkGameController)
private let mteDistText: wref<inkText>;

@addField(inkGameController)
private let mtePhaseText: wref<inkText>;

@addField(inkGameController)
private let mteObjectiveText: wref<inkText>;

@addField(inkGameController)
private let mteStatusText: wref<inkText>;

// Mappin IDs
@addField(inkGameController)
private let mteStartMappinID: NewMappinID;

@addField(inkGameController)
private let mteFinishMappinID: NewMappinID;

@addField(inkGameController)
private let mteHasStartMappin: Bool;

@addField(inkGameController)
private let mteHasFinishMappin: Bool;

@addField(inkGameController)
private let mteStartLeftMappinID: NewMappinID;

@addField(inkGameController)
private let mteHasStartLeftMappin: Bool;

@addField(inkGameController)
private let mteStartRightMappinID: NewMappinID;

@addField(inkGameController)
private let mteHasStartRightMappin: Bool;

@addField(inkGameController)
private let mteFinishLeftMappinID: NewMappinID;

@addField(inkGameController)
private let mteHasFinishLeftMappin: Bool;

@addField(inkGameController)
private let mteFinishRightMappinID: NewMappinID;

@addField(inkGameController)
private let mteHasFinishRightMappin: Bool;

@addField(inkGameController)
private let mteRacer1MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer1Mappin: Bool;

@addField(inkGameController)
private let mteRacer2MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer2Mappin: Bool;

@addField(inkGameController)
private let mteRacer3MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer3Mappin: Bool;

@addField(inkGameController)
private let mteRacer4MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer4Mappin: Bool;

@addField(inkGameController)
private let mteRacer5MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer5Mappin: Bool;

@addField(inkGameController)
private let mteRacer6MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer6Mappin: Bool;

@addField(inkGameController)
private let mteRacer7MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer7Mappin: Bool;

@addField(inkGameController)
private let mteRacer8MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer8Mappin: Bool;

@addField(inkGameController)
private let mteRacer9MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer9Mappin: Bool;

@addField(inkGameController)
private let mteRacer10MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer10Mappin: Bool;

@addField(inkGameController)
private let mteRacer11MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer11Mappin: Bool;

@addField(inkGameController)
private let mteRacer12MappinID: NewMappinID;

@addField(inkGameController)
private let mteHasRacer12Mappin: Bool;

@addField(inkGameController)
private let mteTrackedIsFinish: Bool; // which mappin is the active nav target

// Grid lights (5 rectangles)
@addField(inkGameController)
private let mteGridLight1: wref<inkRectangle>;

@addField(inkGameController)
private let mteGridLight2: wref<inkRectangle>;

@addField(inkGameController)
private let mteGridLight3: wref<inkRectangle>;

@addField(inkGameController)
private let mteGridLight4: wref<inkRectangle>;

@addField(inkGameController)
private let mteGridLight5: wref<inkRectangle>;

@addField(inkGameController)
private let mteGridLightsContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteGapText: wref<inkText>;

@addField(inkGameController)
private let mteGapBehindText: wref<inkText>;

// Rival callout (inside race overlay)
@addField(inkGameController)
private let mteRivalText: wref<inkText>;

// Race result card (full-centre overlay, auto-dismissed)
@addField(inkGameController)
private let mteResultContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteResultPos: wref<inkText>;

@addField(inkGameController)
private let mteResultTime: wref<inkText>;

@addField(inkGameController)
private let mteResultPayout: wref<inkText>;

@addField(inkGameController)
private let mteResultRep: wref<inkText>;

@addField(inkGameController)
private let mteResultExtra: wref<inkText>;

@addField(inkGameController)
private let mteResultDismissTimer: Float;

@addField(inkGameController)
private let mteTierRevealContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteTierRevealTitle: wref<inkText>;

@addField(inkGameController)
private let mteTierRevealSubtitle: wref<inkText>;

@addField(inkGameController)
private let mteTierRevealBody: wref<inkText>;

@addField(inkGameController)
private let mteTierRevealDismissTimer: Float;

@addField(inkGameController)
private let mteSeasonLadderContainer: wref<inkCompoundWidget>;

@addField(inkGameController)
private let mteSeasonLadderTitle: wref<inkText>;

@addField(inkGameController)
private let mteSeasonLadderSummary: wref<inkText>;

@addField(inkGameController)
private let mteSeasonLadderMovement: wref<inkText>;

@addField(inkGameController)
private let mteSeasonLadderTable: wref<inkText>;

@addField(inkGameController)
private let mteSeasonLadderFooter: wref<inkText>;

@addField(inkGameController)
private let mteSeasonLadderDismissTimer: Float;

@addField(inkGameController)
private let mteSeasonLadderQueuedEvent: ref<MTESeasonLadderEvent>;

@addField(inkGameController)
private let mteSeasonLadderQueueDelay: Float;


// Knockout overlay widgets
@addField(inkGameController)
private let mteElimText: wref<inkText>;

@addField(inkGameController)
private let mteElimFlashText: wref<inkText>;

// ── Create HUD ────────────────────────────────────────────────

@addMethod(inkGameController)
private func MTEIsGameplayHudRoot() -> Bool {
  return this.IsA(n"gameuiRootHudGameController");
}

@addMethod(inkGameController)
private func MTECreateHUD() -> Void {
  if !this.MTEIsGameplayHudRoot() {
    return;
  }

  if IsDefined(this.mteHudContainer) {
    return;
  }

  // CP2077 signature colours
  let cCyan: HDRColor    = new HDRColor(0.37, 0.96, 1.0, 1.0);
  let cRed: HDRColor     = new HDRColor(1.18, 0.38, 0.35, 1.0);
  let cYellow: HDRColor  = new HDRColor(1.0, 0.93, 0.33, 1.0);
  let cWhite: HDRColor   = new HDRColor(0.87, 0.93, 0.93, 1.0);
  let cDim: HDRColor     = new HDRColor(0.40, 0.50, 0.50, 0.70);
  let cBg: HDRColor      = new HDRColor(0.04, 0.06, 0.08, 0.75);
  let cGreen: HDRColor   = new HDRColor(0.33, 1.0, 0.42, 1.0);

  let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();

  // ────────────────────────────────────────────────────────────
  // TELEMETRY PANEL — bottom-right, near minimap
  // ────────────────────────────────────────────────────────────
  let container: ref<inkCanvas> = new inkCanvas();
  container.SetName(n"mte_hud_root");
  container.SetAnchor(inkEAnchor.BottomRight);
  container.SetAnchorPoint(new Vector2(1.0, 1.0));
  container.SetMargin(new inkMargin(0.0, 0.0, 60.0, 260.0));
  container.SetSize(new Vector2(300.0, 200.0));
  container.SetVisible(false);
  container.Reparent(root);
  this.mteHudContainer = container;

  // Background
  let bg: ref<inkRectangle> = new inkRectangle();
  bg.SetName(n"mte_bg");
  bg.SetAnchor(inkEAnchor.Fill);
  bg.SetTintColor(cBg);
  bg.Reparent(container);

  // Left accent line (cyan)
  let accentLine: ref<inkRectangle> = new inkRectangle();
  accentLine.SetName(n"mte_accent");
  accentLine.SetAnchor(inkEAnchor.TopLeft);
  accentLine.SetSize(new Vector2(2.0, 200.0));
  accentLine.SetTintColor(cCyan);
  accentLine.Reparent(container);

  // ── Row 1: Speed + Gear (y=6) ──────────────────────────────
  let speed: ref<inkText> = new inkText();
  speed.SetName(n"mte_speed");
  speed.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  speed.SetFontStyle(n"Bold");
  speed.SetFontSize(48);
  speed.SetTintColor(cWhite);
  speed.SetAnchor(inkEAnchor.TopLeft);
  speed.SetMargin(new inkMargin(14.0, 6.0, 0.0, 0.0));
  speed.SetText("0");
  speed.SetLetterCase(textLetterCase.OriginalCase);
  speed.Reparent(container);
  this.mteSpeedText = speed;

  let kph: ref<inkText> = new inkText();
  kph.SetName(n"mte_kph");
  kph.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  kph.SetFontStyle(n"Medium");
  kph.SetFontSize(16);
  kph.SetTintColor(cDim);
  kph.SetAnchor(inkEAnchor.TopLeft);
  kph.SetMargin(new inkMargin(155.0, 32.0, 0.0, 0.0));
  kph.SetText("KPH");
  kph.Reparent(container);
  this.mteKphLabel = kph;

  let gear: ref<inkText> = new inkText();
  gear.SetName(n"mte_gear");
  gear.SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily");
  gear.SetFontStyle(n"Regular");
  gear.SetFontSize(56);
  gear.SetTintColor(cCyan);
  gear.SetAnchor(inkEAnchor.TopRight);
  gear.SetAnchorPoint(new Vector2(1.0, 0.0));
  gear.SetMargin(new inkMargin(0.0, 2.0, 14.0, 0.0));
  gear.SetText("N");
  gear.Reparent(container);
  this.mteGearText = gear;

  // ── Row 2: RPM bar (y=62) ──────────────────────────────────
  let rpmBg: ref<inkRectangle> = new inkRectangle();
  rpmBg.SetName(n"mte_rpm_bg");
  rpmBg.SetAnchor(inkEAnchor.TopLeft);
  rpmBg.SetMargin(new inkMargin(14.0, 62.0, 0.0, 0.0));
  rpmBg.SetSize(new Vector2(272.0, 8.0));
  rpmBg.SetTintColor(cDim);
  rpmBg.SetOpacity(0.4);
  rpmBg.Reparent(container);
  this.mteRpmBarBg = rpmBg;

  let rpmFill: ref<inkRectangle> = new inkRectangle();
  rpmFill.SetName(n"mte_rpm_fill");
  rpmFill.SetAnchor(inkEAnchor.TopLeft);
  rpmFill.SetMargin(new inkMargin(14.0, 62.0, 0.0, 0.0));
  rpmFill.SetSize(new Vector2(1.0, 8.0));
  rpmFill.SetTintColor(cCyan);
  rpmFill.Reparent(container);
  this.mteRpmBar = rpmFill;

  // ── Row 3: Input bars — THR / BRK / CLT (y=80) ─────────────
  let inputsCanvas: ref<inkCanvas> = new inkCanvas();
  inputsCanvas.SetName(n"mte_inputs");
  inputsCanvas.SetAnchor(inkEAnchor.TopLeft);
  inputsCanvas.SetMargin(new inkMargin(14.0, 80.0, 0.0, 0.0));
  inputsCanvas.SetSize(new Vector2(272.0, 30.0));
  inputsCanvas.Reparent(container);
  this.mteInputsContainer = inputsCanvas;

  // THR label + bar
  let thrLabel: ref<inkText> = new inkText();
  thrLabel.SetName(n"mte_thr_lbl");
  thrLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  thrLabel.SetFontStyle(n"Medium");
  thrLabel.SetFontSize(13);
  thrLabel.SetTintColor(cDim);
  thrLabel.SetAnchor(inkEAnchor.TopLeft);
  thrLabel.SetMargin(new inkMargin(0.0, 0.0, 0.0, 0.0));
  thrLabel.SetText("THR");
  thrLabel.Reparent(inputsCanvas);

  let thrBg: ref<inkRectangle> = new inkRectangle();
  thrBg.SetName(n"mte_thr_bg");
  thrBg.SetAnchor(inkEAnchor.TopLeft);
  thrBg.SetMargin(new inkMargin(30.0, 4.0, 0.0, 0.0));
  thrBg.SetSize(new Vector2(55.0, 6.0));
  thrBg.SetTintColor(cDim);
  thrBg.SetOpacity(0.3);
  thrBg.Reparent(inputsCanvas);
  this.mteThrottleBarBg = thrBg;

  let thrFill: ref<inkRectangle> = new inkRectangle();
  thrFill.SetName(n"mte_thr_fill");
  thrFill.SetAnchor(inkEAnchor.TopLeft);
  thrFill.SetMargin(new inkMargin(30.0, 4.0, 0.0, 0.0));
  thrFill.SetSize(new Vector2(1.0, 6.0));
  thrFill.SetTintColor(cGreen);
  thrFill.Reparent(inputsCanvas);
  this.mteThrottleBar = thrFill;

  // BRK label + bar
  let brkLabel: ref<inkText> = new inkText();
  brkLabel.SetName(n"mte_brk_lbl");
  brkLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  brkLabel.SetFontStyle(n"Medium");
  brkLabel.SetFontSize(13);
  brkLabel.SetTintColor(cDim);
  brkLabel.SetAnchor(inkEAnchor.TopLeft);
  brkLabel.SetMargin(new inkMargin(95.0, 0.0, 0.0, 0.0));
  brkLabel.SetText("BRK");
  brkLabel.Reparent(inputsCanvas);

  let brkBg: ref<inkRectangle> = new inkRectangle();
  brkBg.SetName(n"mte_brk_bg");
  brkBg.SetAnchor(inkEAnchor.TopLeft);
  brkBg.SetMargin(new inkMargin(125.0, 4.0, 0.0, 0.0));
  brkBg.SetSize(new Vector2(55.0, 6.0));
  brkBg.SetTintColor(cDim);
  brkBg.SetOpacity(0.3);
  brkBg.Reparent(inputsCanvas);
  this.mteBrakeBarBg = brkBg;

  let brkFill: ref<inkRectangle> = new inkRectangle();
  brkFill.SetName(n"mte_brk_fill");
  brkFill.SetAnchor(inkEAnchor.TopLeft);
  brkFill.SetMargin(new inkMargin(125.0, 4.0, 0.0, 0.0));
  brkFill.SetSize(new Vector2(1.0, 6.0));
  brkFill.SetTintColor(cRed);
  brkFill.Reparent(inputsCanvas);
  this.mteBrakeBar = brkFill;

  // CLT label + bar
  let cltLabel: ref<inkText> = new inkText();
  cltLabel.SetName(n"mte_clt_lbl");
  cltLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  cltLabel.SetFontStyle(n"Medium");
  cltLabel.SetFontSize(13);
  cltLabel.SetTintColor(cDim);
  cltLabel.SetAnchor(inkEAnchor.TopLeft);
  cltLabel.SetMargin(new inkMargin(190.0, 0.0, 0.0, 0.0));
  cltLabel.SetText("CLT");
  cltLabel.Reparent(inputsCanvas);

  let cltBg: ref<inkRectangle> = new inkRectangle();
  cltBg.SetName(n"mte_clt_bg");
  cltBg.SetAnchor(inkEAnchor.TopLeft);
  cltBg.SetMargin(new inkMargin(218.0, 4.0, 0.0, 0.0));
  cltBg.SetSize(new Vector2(55.0, 6.0));
  cltBg.SetTintColor(cDim);
  cltBg.SetOpacity(0.3);
  cltBg.Reparent(inputsCanvas);
  this.mteClutchBarBg = cltBg;

  let cltFill: ref<inkRectangle> = new inkRectangle();
  cltFill.SetName(n"mte_clt_fill");
  cltFill.SetAnchor(inkEAnchor.TopLeft);
  cltFill.SetMargin(new inkMargin(218.0, 4.0, 0.0, 0.0));
  cltFill.SetSize(new Vector2(1.0, 6.0));
  cltFill.SetTintColor(cCyan);
  cltFill.Reparent(inputsCanvas);
  this.mteClutchBar = cltFill;

  // ── Row 3b: Steering + Handbrake (y=98) ─────────────────────
  let steerText: ref<inkText> = new inkText();
  steerText.SetName(n"mte_steer");
  steerText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  steerText.SetFontStyle(n"Medium");
  steerText.SetFontSize(14);
  steerText.SetTintColor(cDim);
  steerText.SetAnchor(inkEAnchor.TopLeft);
  steerText.SetMargin(new inkMargin(14.0, 100.0, 0.0, 0.0));
  steerText.SetText("STR  0.00");
  steerText.Reparent(container);
  this.mteSteeringText = steerText;

  let hbText: ref<inkText> = new inkText();
  hbText.SetName(n"mte_hb");
  hbText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  hbText.SetFontStyle(n"Bold");
  hbText.SetFontSize(14);
  hbText.SetTintColor(cDim);
  hbText.SetAnchor(inkEAnchor.TopRight);
  hbText.SetAnchorPoint(new Vector2(1.0, 0.0));
  hbText.SetMargin(new inkMargin(0.0, 100.0, 14.0, 0.0));
  hbText.SetText("HB");
  hbText.Reparent(container);
  this.mteHandbrakeText = hbText;

  // ── Row 4: G-forces (y=124) ─────────────────────────────────
  let gCanvas: ref<inkCanvas> = new inkCanvas();
  gCanvas.SetName(n"mte_gforces");
  gCanvas.SetAnchor(inkEAnchor.TopLeft);
  gCanvas.SetMargin(new inkMargin(14.0, 122.0, 0.0, 0.0));
  gCanvas.SetSize(new Vector2(272.0, 26.0));
  gCanvas.Reparent(container);
  this.mteGContainer = gCanvas;

  // Separator line
  let gSep: ref<inkRectangle> = new inkRectangle();
  gSep.SetName(n"mte_gsep");
  gSep.SetAnchor(inkEAnchor.TopLeft);
  gSep.SetSize(new Vector2(272.0, 1.0));
  gSep.SetTintColor(cDim);
  gSep.SetOpacity(0.3);
  gSep.Reparent(gCanvas);

  let longGLabel: ref<inkText> = new inkText();
  longGLabel.SetName(n"mte_longg_lbl");
  longGLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  longGLabel.SetFontStyle(n"Medium");
  longGLabel.SetFontSize(14);
  longGLabel.SetTintColor(cDim);
  longGLabel.SetAnchor(inkEAnchor.TopLeft);
  longGLabel.SetMargin(new inkMargin(0.0, 4.0, 0.0, 0.0));
  longGLabel.SetText("LON");
  longGLabel.Reparent(gCanvas);

  let longGVal: ref<inkText> = new inkText();
  longGVal.SetName(n"mte_longg");
  longGVal.SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily");
  longGVal.SetFontStyle(n"Regular");
  longGVal.SetFontSize(20);
  longGVal.SetTintColor(cWhite);
  longGVal.SetAnchor(inkEAnchor.TopLeft);
  longGVal.SetMargin(new inkMargin(34.0, 2.0, 0.0, 0.0));
  longGVal.SetText("0.00G");
  longGVal.Reparent(gCanvas);
  this.mteLongGText = longGVal;

  let latGLabel: ref<inkText> = new inkText();
  latGLabel.SetName(n"mte_latg_lbl");
  latGLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  latGLabel.SetFontStyle(n"Medium");
  latGLabel.SetFontSize(14);
  latGLabel.SetTintColor(cDim);
  latGLabel.SetAnchor(inkEAnchor.TopLeft);
  latGLabel.SetMargin(new inkMargin(140.0, 4.0, 0.0, 0.0));
  latGLabel.SetText("LAT");
  latGLabel.Reparent(gCanvas);

  let latGVal: ref<inkText> = new inkText();
  latGVal.SetName(n"mte_latg");
  latGVal.SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily");
  latGVal.SetFontStyle(n"Regular");
  latGVal.SetFontSize(20);
  latGVal.SetTintColor(cWhite);
  latGVal.SetAnchor(inkEAnchor.TopLeft);
  latGVal.SetMargin(new inkMargin(174.0, 2.0, 0.0, 0.0));
  latGVal.SetText("0.00G");
  latGVal.Reparent(gCanvas);
  this.mteLatGText = latGVal;

  // ── Row 5: Vehicle health (y=152) ───────────────────────────
  let healthCanvas: ref<inkCanvas> = new inkCanvas();
  healthCanvas.SetName(n"mte_health");
  healthCanvas.SetAnchor(inkEAnchor.TopLeft);
  healthCanvas.SetMargin(new inkMargin(14.0, 154.0, 0.0, 0.0));
  healthCanvas.SetSize(new Vector2(272.0, 20.0));
  healthCanvas.Reparent(container);
  this.mteHealthContainer = healthCanvas;

  let hpLabel: ref<inkText> = new inkText();
  hpLabel.SetName(n"mte_hp_lbl");
  hpLabel.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  hpLabel.SetFontStyle(n"Medium");
  hpLabel.SetFontSize(13);
  hpLabel.SetTintColor(cDim);
  hpLabel.SetAnchor(inkEAnchor.TopLeft);
  hpLabel.SetText("VEH");
  hpLabel.Reparent(healthCanvas);

  let hpBg: ref<inkRectangle> = new inkRectangle();
  hpBg.SetName(n"mte_hp_bg");
  hpBg.SetAnchor(inkEAnchor.TopLeft);
  hpBg.SetMargin(new inkMargin(30.0, 4.0, 0.0, 0.0));
  hpBg.SetSize(new Vector2(242.0, 6.0));
  hpBg.SetTintColor(cDim);
  hpBg.SetOpacity(0.3);
  hpBg.Reparent(healthCanvas);
  this.mteHealthBarBg = hpBg;

  let hpFill: ref<inkRectangle> = new inkRectangle();
  hpFill.SetName(n"mte_hp_fill");
  hpFill.SetAnchor(inkEAnchor.TopLeft);
  hpFill.SetMargin(new inkMargin(30.0, 4.0, 0.0, 0.0));
  hpFill.SetSize(new Vector2(242.0, 6.0));
  hpFill.SetTintColor(cGreen);
  hpFill.Reparent(healthCanvas);
  this.mteHealthBar = hpFill;

  // ────────────────────────────────────────────────────────────
  // RACE OVERLAY — top center
  // ────────────────────────────────────────────────────────────
  let raceRoot: ref<inkCanvas> = new inkCanvas();
  raceRoot.SetName(n"mte_race_root");
  raceRoot.SetAnchor(inkEAnchor.TopCenter);
  raceRoot.SetAnchorPoint(new Vector2(0.5, 0.0));
  raceRoot.SetMargin(new inkMargin(0.0, 60.0, 0.0, 0.0));
  raceRoot.SetSize(new Vector2(460.0, 340.0));
  raceRoot.SetVisible(false);
  raceRoot.Reparent(root);
  this.mteRaceContainer = raceRoot;

  let raceBg: ref<inkRectangle> = new inkRectangle();
  raceBg.SetName(n"mte_race_bg");
  raceBg.SetAnchor(inkEAnchor.Fill);
  raceBg.SetTintColor(cBg);
  raceBg.Reparent(raceRoot);

  let raceLine: ref<inkRectangle> = new inkRectangle();
  raceLine.SetName(n"mte_race_line");
  raceLine.SetAnchor(inkEAnchor.TopFillHorizontaly);
  raceLine.SetSize(new Vector2(460.0, 2.0));
  raceLine.SetTintColor(cYellow);
  raceLine.Reparent(raceRoot);

  let trackText: ref<inkText> = new inkText();
  trackText.SetName(n"mte_track");
  trackText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  trackText.SetFontStyle(n"Medium");
  trackText.SetFontSize(22);
  trackText.SetTintColor(cCyan);
  trackText.SetAnchor(inkEAnchor.TopCenter);
  trackText.SetAnchorPoint(new Vector2(0.5, 0.0));
  trackText.SetMargin(new inkMargin(0.0, 8.0, 0.0, 0.0));
  trackText.SetHAlign(inkEHorizontalAlign.Center);
  trackText.SetText("");
  trackText.SetLetterCase(textLetterCase.UpperCase);
  trackText.Reparent(raceRoot);
  this.mteTrackText = trackText;

  let cdText: ref<inkText> = new inkText();
  cdText.SetName(n"mte_countdown");
  cdText.SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily");
  cdText.SetFontStyle(n"Regular");
  cdText.SetFontSize(90);
  cdText.SetTintColor(cYellow);
  cdText.SetAnchor(inkEAnchor.TopCenter);
  cdText.SetAnchorPoint(new Vector2(0.5, 0.0));
  cdText.SetMargin(new inkMargin(0.0, 35.0, 0.0, 0.0));
  cdText.SetHAlign(inkEHorizontalAlign.Center);
  cdText.SetText("");
  cdText.Reparent(raceRoot);
  this.mteCountdownText = cdText;

  // ── Grid Lights (5 circles simulated as small squares) ──────
  let lightsRow: ref<inkCanvas> = new inkCanvas();
  lightsRow.SetName(n"mte_grid_lights");
  lightsRow.SetAnchor(inkEAnchor.TopCenter);
  lightsRow.SetAnchorPoint(new Vector2(0.5, 0.0));
  lightsRow.SetMargin(new inkMargin(0.0, 130.0, 0.0, 0.0));
  lightsRow.SetSize(new Vector2(200.0, 24.0));
  lightsRow.SetVisible(false);
  lightsRow.Reparent(raceRoot);
  this.mteGridLightsContainer = lightsRow;

  let i: Int32 = 0;
  while i < 5 {
    let light: ref<inkRectangle> = new inkRectangle();
    light.SetName(StringToName("mte_gl_" + ToString(i)));
    light.SetAnchor(inkEAnchor.TopLeft);
    light.SetMargin(new inkMargin(Cast<Float>(i) * 40.0, 0.0, 0.0, 0.0));
    light.SetSize(new Vector2(24.0, 24.0));
    light.SetTintColor(cDim);
    light.SetOpacity(0.4);
    light.Reparent(lightsRow);
    if i == 0 { this.mteGridLight1 = light; }
    else if i == 1 { this.mteGridLight2 = light; }
    else if i == 2 { this.mteGridLight3 = light; }
    else if i == 3 { this.mteGridLight4 = light; }
    else { this.mteGridLight5 = light; }
    i += 1;
  }

  let posText: ref<inkText> = new inkText();
  posText.SetName(n"mte_racepos");
  posText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  posText.SetFontStyle(n"Bold");
  posText.SetFontSize(52);
  posText.SetTintColor(cYellow);
  posText.SetAnchor(inkEAnchor.TopLeft);
  posText.SetAnchorPoint(new Vector2(0.0, 0.0));
  posText.SetMargin(new inkMargin(16.0, 32.0, 0.0, 0.0));
  posText.SetHAlign(inkEHorizontalAlign.Left);
  posText.SetText("");
  posText.SetVisible(false);
  posText.Reparent(raceRoot);
  this.mtePosText = posText;

  let timeText: ref<inkText> = new inkText();
  timeText.SetName(n"mte_racetime");
  timeText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  timeText.SetFontStyle(n"Medium");
  timeText.SetFontSize(28);
  timeText.SetTintColor(cDim);
  timeText.SetAnchor(inkEAnchor.BottomCenter);
  timeText.SetAnchorPoint(new Vector2(0.5, 1.0));
  timeText.SetMargin(new inkMargin(0.0, 0.0, 0.0, 12.0));
  timeText.SetHAlign(inkEHorizontalAlign.Center);
  timeText.SetText("");
  timeText.Reparent(raceRoot);
  this.mteTimeText = timeText;

  // Standings text (multi-line, below time display)
  let standingsText: ref<inkText> = new inkText();
  standingsText.SetName(n"mte_standings");
  standingsText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  standingsText.SetFontStyle(n"Medium");
  standingsText.SetFontSize(16);
  standingsText.SetTintColor(cDim);
  standingsText.SetAnchor(inkEAnchor.TopLeft);
  standingsText.SetMargin(new inkMargin(16.0, 195.0, 0.0, 0.0));
  standingsText.SetText("");
  standingsText.SetVisible(false);
  standingsText.Reparent(raceRoot);
  this.mteStandingsText = standingsText;

  // Distance to finish (right side of race overlay)
  let distText: ref<inkText> = new inkText();
  distText.SetName(n"mte_dist");
  distText.SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily");
  distText.SetFontStyle(n"Regular");
  distText.SetFontSize(22);
  distText.SetTintColor(cDim);
  distText.SetAnchor(inkEAnchor.TopRight);
  distText.SetAnchorPoint(new Vector2(1.0, 0.0));
  distText.SetMargin(new inkMargin(0.0, 195.0, 16.0, 0.0));
  distText.SetText("");
  distText.SetVisible(false);
  distText.Reparent(raceRoot);
  this.mteDistText = distText;

  let phaseText: ref<inkText> = new inkText();
  phaseText.SetName(n"mte_phase");
  phaseText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  phaseText.SetFontStyle(n"Bold");
  phaseText.SetFontSize(28);
  phaseText.SetTintColor(cYellow);
  phaseText.SetAnchor(inkEAnchor.TopCenter);
  phaseText.SetAnchorPoint(new Vector2(0.5, 0.0));
  phaseText.SetMargin(new inkMargin(0.0, 85.0, 0.0, 0.0));
  phaseText.SetHAlign(inkEHorizontalAlign.Center);
  phaseText.SetText("");
  phaseText.SetVisible(false);
  phaseText.Reparent(raceRoot);
  this.mtePhaseText = phaseText;

  let objectiveText: ref<inkText> = new inkText();
  objectiveText.SetName(n"mte_objective");
  objectiveText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  objectiveText.SetFontStyle(n"Medium");
  objectiveText.SetFontSize(20);
  objectiveText.SetTintColor(cWhite);
  objectiveText.SetAnchor(inkEAnchor.TopCenter);
  objectiveText.SetAnchorPoint(new Vector2(0.5, 0.0));
  objectiveText.SetMargin(new inkMargin(0.0, 120.0, 0.0, 0.0));
  objectiveText.SetHAlign(inkEHorizontalAlign.Center);
  objectiveText.SetText("");
  objectiveText.SetVisible(false);
  objectiveText.Reparent(raceRoot);
  this.mteObjectiveText = objectiveText;

  let statusText: ref<inkText> = new inkText();
  statusText.SetName(n"mte_status");
  statusText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  statusText.SetFontStyle(n"Medium");
  statusText.SetFontSize(16);
  statusText.SetTintColor(cDim);
  statusText.SetAnchor(inkEAnchor.TopCenter);
  statusText.SetAnchorPoint(new Vector2(0.5, 0.0));
  statusText.SetMargin(new inkMargin(0.0, 148.0, 0.0, 0.0));
  statusText.SetHAlign(inkEHorizontalAlign.Center);
  statusText.SetText("");
  statusText.SetVisible(false);
  statusText.Reparent(raceRoot);
  this.mteStatusText = statusText;

  // Gap to car ahead/behind
  let gapText: ref<inkText> = new inkText();
  gapText.SetName(n"mte_gap");
  gapText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  gapText.SetFontStyle(n"Bold");
  gapText.SetFontSize(28);
  gapText.SetTintColor(cCyan);
  gapText.SetAnchor(inkEAnchor.TopCenter);
  gapText.SetAnchorPoint(new Vector2(0.5, 0.0));
  gapText.SetMargin(new inkMargin(0.0, 160.0, 0.0, 0.0));
  gapText.SetHAlign(inkEHorizontalAlign.Center);
  gapText.SetText("");
  gapText.SetVisible(false);
  gapText.Reparent(raceRoot);
  this.mteGapText = gapText;

  // Gap to car behind
  let gapBehind: ref<inkText> = new inkText();
  gapBehind.SetName(n"mte_gap_behind");
  gapBehind.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  gapBehind.SetFontStyle(n"Medium");
  gapBehind.SetFontSize(20);
  gapBehind.SetTintColor(cDim);
  gapBehind.SetAnchor(inkEAnchor.TopCenter);
  gapBehind.SetAnchorPoint(new Vector2(0.5, 0.0));
  gapBehind.SetMargin(new inkMargin(0.0, 185.0, 0.0, 0.0));
  gapBehind.SetHAlign(inkEHorizontalAlign.Center);
  gapBehind.SetText("");
  gapBehind.SetVisible(false);
  gapBehind.Reparent(raceRoot);
  this.mteGapBehindText = gapBehind;

  // Rival callout — bottom-right of race overlay, above elim flash
  let rivalText: ref<inkText> = new inkText();
  rivalText.SetName(n"mte_rival");
  rivalText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  rivalText.SetFontStyle(n"Bold");
  rivalText.SetFontSize(18);
  rivalText.SetTintColor(new HDRColor(1.0, 0.55, 0.0, 1.0));
  rivalText.SetAnchor(inkEAnchor.BottomRight);
  rivalText.SetAnchorPoint(new Vector2(1.0, 1.0));
  rivalText.SetMargin(new inkMargin(0.0, 0.0, 16.0, 55.0));
  rivalText.SetHAlign(inkEHorizontalAlign.Right);
  rivalText.SetText("");
  rivalText.SetVisible(false);
  rivalText.Reparent(raceRoot);
  this.mteRivalText = rivalText;

  // Knockout: elimination countdown text (below gap text position)
  let elimText: ref<inkText> = new inkText();
  elimText.SetName(n"mte_elim");
  elimText.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  elimText.SetFontStyle(n"Bold");
  elimText.SetFontSize(20);
  elimText.SetTintColor(cDim);
  elimText.SetAnchor(inkEAnchor.TopCenter);
  elimText.SetAnchorPoint(new Vector2(0.5, 0.0));
  elimText.SetMargin(new inkMargin(0.0, 115.0, 0.0, 0.0));
  elimText.SetHAlign(inkEHorizontalAlign.Center);
  elimText.SetText("");
  elimText.SetVisible(false);
  elimText.Reparent(raceRoot);
  this.mteElimText = elimText;

  // Knockout: eliminated driver flash text (bottom of race overlay)
  let elimFlash: ref<inkText> = new inkText();
  elimFlash.SetName(n"mte_elim_flash");
  elimFlash.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  elimFlash.SetFontStyle(n"Bold");
  elimFlash.SetFontSize(18);
  elimFlash.SetTintColor(cRed);
  elimFlash.SetAnchor(inkEAnchor.BottomCenter);
  elimFlash.SetAnchorPoint(new Vector2(0.5, 1.0));
  elimFlash.SetMargin(new inkMargin(0.0, 0.0, 0.0, 32.0));
  elimFlash.SetHAlign(inkEHorizontalAlign.Center);
  elimFlash.SetText("");
  elimFlash.SetVisible(false);
  elimFlash.Reparent(raceRoot);
  this.mteElimFlashText = elimFlash;

  // ────────────────────────────────────────────────────────────
  // RESULTS CARD — centre screen, auto-dismissed after 7 s
  // ────────────────────────────────────────────────────────────
  let resultRoot: ref<inkCanvas> = new inkCanvas();
  resultRoot.SetName(n"mte_result_root");
  resultRoot.SetAnchor(inkEAnchor.Centered);
  resultRoot.SetAnchorPoint(new Vector2(0.5, 0.5));
  resultRoot.SetSize(new Vector2(420.0, 220.0));
  resultRoot.SetVisible(false);
  resultRoot.Reparent(root);
  this.mteResultContainer = resultRoot;

  // Background + border lines
  let rBg: ref<inkRectangle> = new inkRectangle();
  rBg.SetName(n"mte_res_bg");
  rBg.SetAnchor(inkEAnchor.Fill);
  rBg.SetTintColor(new HDRColor(0.04, 0.06, 0.08, 0.92));
  rBg.Reparent(resultRoot);

  let rTopLine: ref<inkRectangle> = new inkRectangle();
  rTopLine.SetName(n"mte_res_topline");
  rTopLine.SetAnchor(inkEAnchor.TopFillHorizontaly);
  rTopLine.SetSize(new Vector2(420.0, 3.0));
  rTopLine.SetTintColor(cYellow);
  rTopLine.Reparent(resultRoot);

  let rBotLine: ref<inkRectangle> = new inkRectangle();
  rBotLine.SetName(n"mte_res_botline");
  rBotLine.SetAnchor(inkEAnchor.BottomFillHorizontaly);
  rBotLine.SetSize(new Vector2(420.0, 3.0));
  rBotLine.SetTintColor(cYellow);
  rBotLine.Reparent(resultRoot);

  // Header label
  let rHeader: ref<inkText> = new inkText();
  rHeader.SetName(n"mte_res_hdr");
  rHeader.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  rHeader.SetFontStyle(n"Bold");
  rHeader.SetFontSize(18);
  rHeader.SetTintColor(cDim);
  rHeader.SetAnchor(inkEAnchor.TopCenter);
  rHeader.SetAnchorPoint(new Vector2(0.5, 0.0));
  rHeader.SetMargin(new inkMargin(0.0, 10.0, 0.0, 0.0));
  rHeader.SetHAlign(inkEHorizontalAlign.Center);
  rHeader.SetText("RACE RESULT");
  rHeader.SetLetterCase(textLetterCase.UpperCase);
  rHeader.Reparent(resultRoot);

  // Large position text (P1 / DNF)
  let rPos: ref<inkText> = new inkText();
  rPos.SetName(n"mte_res_pos");
  rPos.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  rPos.SetFontStyle(n"Bold");
  rPos.SetFontSize(80);
  rPos.SetTintColor(cYellow);
  rPos.SetAnchor(inkEAnchor.TopCenter);
  rPos.SetAnchorPoint(new Vector2(0.5, 0.0));
  rPos.SetMargin(new inkMargin(0.0, 30.0, 0.0, 0.0));
  rPos.SetHAlign(inkEHorizontalAlign.Center);
  rPos.SetText("P1");
  rPos.Reparent(resultRoot);
  this.mteResultPos = rPos;

  // Race time
  let rTime: ref<inkText> = new inkText();
  rTime.SetName(n"mte_res_time");
  rTime.SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily");
  rTime.SetFontStyle(n"Regular");
  rTime.SetFontSize(26);
  rTime.SetTintColor(cCyan);
  rTime.SetAnchor(inkEAnchor.TopCenter);
  rTime.SetAnchorPoint(new Vector2(0.5, 0.0));
  rTime.SetMargin(new inkMargin(0.0, 118.0, 0.0, 0.0));
  rTime.SetHAlign(inkEHorizontalAlign.Center);
  rTime.SetText("--:--.---");
  rTime.Reparent(resultRoot);
  this.mteResultTime = rTime;

  // Payout (bottom-left)
  let rPayout: ref<inkText> = new inkText();
  rPayout.SetName(n"mte_res_pay");
  rPayout.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  rPayout.SetFontStyle(n"Medium");
  rPayout.SetFontSize(20);
  rPayout.SetTintColor(cGreen);
  rPayout.SetAnchor(inkEAnchor.TopLeft);
  rPayout.SetMargin(new inkMargin(20.0, 155.0, 0.0, 0.0));
  rPayout.SetText("+ 0 ¥");
  rPayout.Reparent(resultRoot);
  this.mteResultPayout = rPayout;

  // Rep gain (bottom-right)
  let rRep: ref<inkText> = new inkText();
  rRep.SetName(n"mte_res_rep");
  rRep.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  rRep.SetFontStyle(n"Medium");
  rRep.SetFontSize(20);
  rRep.SetTintColor(cCyan);
  rRep.SetAnchor(inkEAnchor.TopRight);
  rRep.SetAnchorPoint(new Vector2(1.0, 0.0));
  rRep.SetMargin(new inkMargin(0.0, 155.0, 20.0, 0.0));
  rRep.SetText("+0 REP");
  rRep.Reparent(resultRoot);
  this.mteResultRep = rRep;

  // Extra info: clean run / wager / bounty (bottom center)
  let rExtra: ref<inkText> = new inkText();
  rExtra.SetName(n"mte_res_extra");
  rExtra.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  rExtra.SetFontStyle(n"Medium");
  rExtra.SetFontSize(16);
  rExtra.SetTintColor(cDim);
  rExtra.SetAnchor(inkEAnchor.BottomCenter);
  rExtra.SetAnchorPoint(new Vector2(0.5, 1.0));
  rExtra.SetMargin(new inkMargin(0.0, 0.0, 0.0, 12.0));
  rExtra.SetHAlign(inkEHorizontalAlign.Center);
  rExtra.SetText("");
  rExtra.Reparent(resultRoot);
  this.mteResultExtra = rExtra;

  this.mteResultDismissTimer = 0.0;

  // ────────────────────────────────────────────────────────────
  // TIER REVEAL — top-center status card for promotion/relegation
  // ────────────────────────────────────────────────────────────
  let revealRoot: ref<inkCanvas> = new inkCanvas();
  revealRoot.SetName(n"mte_tier_reveal_root");
  revealRoot.SetAnchor(inkEAnchor.TopCenter);
  revealRoot.SetAnchorPoint(new Vector2(0.5, 0.0));
  revealRoot.SetMargin(new inkMargin(0.0, 120.0, 0.0, 0.0));
  revealRoot.SetSize(new Vector2(560.0, 190.0));
  revealRoot.SetVisible(false);
  revealRoot.Reparent(root);
  this.mteTierRevealContainer = revealRoot;

  let revealBg: ref<inkRectangle> = new inkRectangle();
  revealBg.SetName(n"mte_tier_reveal_bg");
  revealBg.SetAnchor(inkEAnchor.Fill);
  revealBg.SetTintColor(new HDRColor(0.04, 0.06, 0.08, 0.92));
  revealBg.Reparent(revealRoot);

  let revealTopLine: ref<inkRectangle> = new inkRectangle();
  revealTopLine.SetName(n"mte_tier_reveal_topline");
  revealTopLine.SetAnchor(inkEAnchor.TopFillHorizontaly);
  revealTopLine.SetSize(new Vector2(560.0, 3.0));
  revealTopLine.SetTintColor(cCyan);
  revealTopLine.Reparent(revealRoot);

  let revealBotLine: ref<inkRectangle> = new inkRectangle();
  revealBotLine.SetName(n"mte_tier_reveal_botline");
  revealBotLine.SetAnchor(inkEAnchor.BottomFillHorizontaly);
  revealBotLine.SetSize(new Vector2(560.0, 3.0));
  revealBotLine.SetTintColor(cCyan);
  revealBotLine.Reparent(revealRoot);

  let revealTitle: ref<inkText> = new inkText();
  revealTitle.SetName(n"mte_tier_reveal_title");
  revealTitle.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  revealTitle.SetFontStyle(n"Bold");
  revealTitle.SetFontSize(34);
  revealTitle.SetTintColor(cCyan);
  revealTitle.SetAnchor(inkEAnchor.TopCenter);
  revealTitle.SetAnchorPoint(new Vector2(0.5, 0.0));
  revealTitle.SetMargin(new inkMargin(0.0, 18.0, 0.0, 0.0));
  revealTitle.SetHAlign(inkEHorizontalAlign.Center);
  revealTitle.SetText("PROMOTED");
  revealTitle.SetLetterCase(textLetterCase.UpperCase);
  revealTitle.Reparent(revealRoot);
  this.mteTierRevealTitle = revealTitle;

  let revealSubtitle: ref<inkText> = new inkText();
  revealSubtitle.SetName(n"mte_tier_reveal_subtitle");
  revealSubtitle.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  revealSubtitle.SetFontStyle(n"Medium");
  revealSubtitle.SetFontSize(18);
  revealSubtitle.SetTintColor(cYellow);
  revealSubtitle.SetAnchor(inkEAnchor.TopCenter);
  revealSubtitle.SetAnchorPoint(new Vector2(0.5, 0.0));
  revealSubtitle.SetMargin(new inkMargin(0.0, 62.0, 0.0, 0.0));
  revealSubtitle.SetHAlign(inkEHorizontalAlign.Center);
  revealSubtitle.SetText("STREETKID -> SOLO");
  revealSubtitle.SetLetterCase(textLetterCase.UpperCase);
  revealSubtitle.Reparent(revealRoot);
  this.mteTierRevealSubtitle = revealSubtitle;

  let revealBody: ref<inkText> = new inkText();
  revealBody.SetName(n"mte_tier_reveal_body");
  revealBody.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  revealBody.SetFontStyle(n"Medium");
  revealBody.SetFontSize(18);
  revealBody.SetTintColor(cWhite);
  revealBody.SetAnchor(inkEAnchor.TopCenter);
  revealBody.SetAnchorPoint(new Vector2(0.5, 0.0));
  revealBody.SetMargin(new inkMargin(28.0, 98.0, 28.0, 0.0));
  revealBody.SetHAlign(inkEHorizontalAlign.Center);
  revealBody.SetWrapping(true, 504.0);
  revealBody.SetText("");
  revealBody.Reparent(revealRoot);
  this.mteTierRevealBody = revealBody;

  this.mteTierRevealDismissTimer = 0.0;

  // ────────────────────────────────────────────────────────────
  // SEASON LADDER ACCOUNT — post-race standings movement card
  // ────────────────────────────────────────────────────────────
  let ladderRoot: ref<inkCanvas> = new inkCanvas();
  ladderRoot.SetName(n"mte_season_ladder_root");
  ladderRoot.SetAnchor(inkEAnchor.Centered);
  ladderRoot.SetAnchorPoint(new Vector2(0.5, 0.5));
  ladderRoot.SetSize(new Vector2(620.0, 320.0));
  ladderRoot.SetVisible(false);
  ladderRoot.Reparent(root);
  this.mteSeasonLadderContainer = ladderRoot;

  let ladderBg: ref<inkRectangle> = new inkRectangle();
  ladderBg.SetName(n"mte_season_ladder_bg");
  ladderBg.SetAnchor(inkEAnchor.Fill);
  ladderBg.SetTintColor(new HDRColor(0.04, 0.06, 0.08, 0.94));
  ladderBg.Reparent(ladderRoot);

  let ladderTopLine: ref<inkRectangle> = new inkRectangle();
  ladderTopLine.SetName(n"mte_season_ladder_topline");
  ladderTopLine.SetAnchor(inkEAnchor.TopFillHorizontaly);
  ladderTopLine.SetSize(new Vector2(620.0, 3.0));
  ladderTopLine.SetTintColor(cCyan);
  ladderTopLine.Reparent(ladderRoot);

  let ladderBotLine: ref<inkRectangle> = new inkRectangle();
  ladderBotLine.SetName(n"mte_season_ladder_botline");
  ladderBotLine.SetAnchor(inkEAnchor.BottomFillHorizontaly);
  ladderBotLine.SetSize(new Vector2(620.0, 3.0));
  ladderBotLine.SetTintColor(cCyan);
  ladderBotLine.Reparent(ladderRoot);

  let ladderTitle: ref<inkText> = new inkText();
  ladderTitle.SetName(n"mte_season_ladder_title");
  ladderTitle.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  ladderTitle.SetFontStyle(n"Bold");
  ladderTitle.SetFontSize(26);
  ladderTitle.SetTintColor(cCyan);
  ladderTitle.SetAnchor(inkEAnchor.TopCenter);
  ladderTitle.SetAnchorPoint(new Vector2(0.5, 0.0));
  ladderTitle.SetMargin(new inkMargin(0.0, 16.0, 0.0, 0.0));
  ladderTitle.SetHAlign(inkEHorizontalAlign.Center);
  ladderTitle.SetLetterCase(textLetterCase.UpperCase);
  ladderTitle.SetText("SEASON ACCOUNT");
  ladderTitle.Reparent(ladderRoot);
  this.mteSeasonLadderTitle = ladderTitle;

  let ladderSummary: ref<inkText> = new inkText();
  ladderSummary.SetName(n"mte_season_ladder_summary");
  ladderSummary.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  ladderSummary.SetFontStyle(n"Bold");
  ladderSummary.SetFontSize(22);
  ladderSummary.SetTintColor(cYellow);
  ladderSummary.SetAnchor(inkEAnchor.TopCenter);
  ladderSummary.SetAnchorPoint(new Vector2(0.5, 0.0));
  ladderSummary.SetMargin(new inkMargin(24.0, 54.0, 24.0, 0.0));
  ladderSummary.SetHAlign(inkEHorizontalAlign.Center);
  ladderSummary.SetWrapping(true, 560.0);
  ladderSummary.SetText("");
  ladderSummary.Reparent(ladderRoot);
  this.mteSeasonLadderSummary = ladderSummary;

  let ladderMovement: ref<inkText> = new inkText();
  ladderMovement.SetName(n"mte_season_ladder_movement");
  ladderMovement.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  ladderMovement.SetFontStyle(n"Medium");
  ladderMovement.SetFontSize(18);
  ladderMovement.SetTintColor(cWhite);
  ladderMovement.SetAnchor(inkEAnchor.TopCenter);
  ladderMovement.SetAnchorPoint(new Vector2(0.5, 0.0));
  ladderMovement.SetMargin(new inkMargin(30.0, 92.0, 30.0, 0.0));
  ladderMovement.SetHAlign(inkEHorizontalAlign.Center);
  ladderMovement.SetWrapping(true, 548.0);
  ladderMovement.SetText("");
  ladderMovement.Reparent(ladderRoot);
  this.mteSeasonLadderMovement = ladderMovement;

  let ladderTable: ref<inkText> = new inkText();
  ladderTable.SetName(n"mte_season_ladder_table");
  ladderTable.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  ladderTable.SetFontStyle(n"Medium");
  ladderTable.SetFontSize(18);
  ladderTable.SetTintColor(cCyan);
  ladderTable.SetAnchor(inkEAnchor.TopLeft);
  ladderTable.SetMargin(new inkMargin(34.0, 136.0, 34.0, 0.0));
  ladderTable.SetHAlign(inkEHorizontalAlign.Left);
  ladderTable.SetWrapping(true, 552.0);
  ladderTable.SetText("");
  ladderTable.Reparent(ladderRoot);
  this.mteSeasonLadderTable = ladderTable;

  let ladderFooter: ref<inkText> = new inkText();
  ladderFooter.SetName(n"mte_season_ladder_footer");
  ladderFooter.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
  ladderFooter.SetFontStyle(n"Medium");
  ladderFooter.SetFontSize(16);
  ladderFooter.SetTintColor(cDim);
  ladderFooter.SetAnchor(inkEAnchor.BottomCenter);
  ladderFooter.SetAnchorPoint(new Vector2(0.5, 1.0));
  ladderFooter.SetMargin(new inkMargin(24.0, 0.0, 24.0, 18.0));
  ladderFooter.SetHAlign(inkEHorizontalAlign.Center);
  ladderFooter.SetWrapping(true, 560.0);
  ladderFooter.SetText("");
  ladderFooter.Reparent(ladderRoot);
  this.mteSeasonLadderFooter = ladderFooter;

  this.mteSeasonLadderDismissTimer = 0.0;
  this.mteSeasonLadderQueueDelay = 0.0;
}

// ── Direct update — called from CET via captured controller ref ──

@addMethod(inkGameController)
public func MTEHandleUpdate(evt: ref<MTEHudUpdateEvent>) -> Void {
  if !this.MTEIsGameplayHudRoot() {
    return;
  }

  let runtime: ref<MTERaceRuntime> = MTERaceRuntime.GetInstance();
  if IsDefined(runtime) {
    runtime.UpdateFromHudEvent(evt);
  }

  if !evt.hudEnabled {
    if IsDefined(this.mteHudContainer) {
      this.mteHudContainer.SetVisible(false);
    }
    if IsDefined(this.mteRaceContainer) {
      this.mteRaceContainer.SetVisible(false);
    }
    if IsDefined(this.mteResultContainer) {
      this.mteResultContainer.SetVisible(false);
    }
    if IsDefined(this.mteTierRevealContainer) {
      this.mteTierRevealContainer.SetVisible(false);
    }
    if IsDefined(this.mteSeasonLadderContainer) {
      this.mteSeasonLadderContainer.SetVisible(false);
    }
    this.mteSeasonLadderQueuedEvent = null;
    this.mteSeasonLadderQueueDelay = 0.0;
    return;
  }

  if !IsDefined(this.mteHudContainer) {
    this.MTECreateHUD();
  }

  // Colours for dynamic tinting
  let cCyan: HDRColor   = new HDRColor(0.37, 0.96, 1.0, 1.0);
  let cRed: HDRColor    = new HDRColor(1.18, 0.38, 0.35, 1.0);
  let cYellow: HDRColor = new HDRColor(1.0, 0.93, 0.33, 1.0);
  let cGreen: HDRColor  = new HDRColor(0.33, 1.0, 0.42, 1.0);
  let cWhite: HDRColor  = new HDRColor(0.87, 0.93, 0.93, 1.0);
  let cOrange: HDRColor = new HDRColor(1.0, 0.55, 0.0, 1.0);
  let cDim: HDRColor    = new HDRColor(0.40, 0.50, 0.50, 0.70);

  // ── Apply user layout overrides ─────────────────────────────
  // Telemetry panel (bottom-right)
  if IsDefined(this.mteHudContainer) {
    let tScale: Float = ClampF(evt.telemetryScale, 0.25, 3.0);
    this.mteHudContainer.SetScale(new Vector2(tScale, tScale));
    this.mteHudContainer.SetOpacity(ClampF(evt.telemetryOpacity, 0.05, 1.0));
    // Default margin is (0, 0, 60, 260); user offsets shift from that
    this.mteHudContainer.SetMargin(new inkMargin(
      0.0 + evt.telemetryOffsetX,
      0.0 + evt.telemetryOffsetY,
      60.0 - evt.telemetryOffsetX,
      260.0 - evt.telemetryOffsetY
    ));
  }
  // Race overlay (top-center)
  if IsDefined(this.mteRaceContainer) {
    let rScale: Float = ClampF(evt.raceHudScale, 0.25, 3.0);
    this.mteRaceContainer.SetScale(new Vector2(rScale, rScale));
    this.mteRaceContainer.SetOpacity(ClampF(evt.raceHudOpacity, 0.05, 1.0));
    this.mteRaceContainer.SetMargin(new inkMargin(
      0.0 + evt.raceHudOffsetX,
      60.0 + evt.raceHudOffsetY,
      0.0,
      0.0
    ));
  }

  // ── Telemetry panel visibility ──────────────────────────────
  this.mteHudContainer.SetVisible(evt.inVehicle);

  if evt.inVehicle {
    // Speed
    this.mteSpeedText.SetText(ToString(Cast<Int32>(evt.speedKph)));

    // Gear
    let gearStr: String;
    let gearColor: HDRColor;
    if evt.gear == -1 {
      gearStr = "R";
      gearColor = cRed;
    } else if evt.gear == 0 {
      gearStr = "N";
      gearColor = cYellow;
    } else {
      gearStr = ToString(evt.gear);
      gearColor = cCyan;
    }
    this.mteGearText.SetText(gearStr);
    this.mteGearText.SetTintColor(gearColor);

    // RPM bar (0.0–1.0 → 0–272px)
    let rpmW: Float = evt.rpm * 272.0;
    if rpmW < 1.0 { rpmW = 1.0; }
    this.mteRpmBar.SetSize(new Vector2(rpmW, 8.0));
    let rpmColor: HDRColor;
    if evt.rpm > 0.85 {
      rpmColor = cRed;
    } else if evt.rpm > 0.65 {
      rpmColor = cYellow;
    } else {
      rpmColor = cCyan;
    }
    this.mteRpmBar.SetTintColor(rpmColor);

    // ── Input bars (conditional) ──────────────────────────────
    if IsDefined(this.mteInputsContainer) {
      this.mteInputsContainer.SetVisible(evt.showInputs);
    }
    if IsDefined(this.mteSteeringText) {
      this.mteSteeringText.SetVisible(evt.showInputs);
    }
    if IsDefined(this.mteHandbrakeText) {
      this.mteHandbrakeText.SetVisible(evt.showInputs);
    }

    if evt.showInputs {
      // Throttle (0–55px)
      let thrW: Float = evt.throttle * 55.0;
      if thrW < 1.0 { thrW = 1.0; }
      this.mteThrottleBar.SetSize(new Vector2(thrW, 6.0));

      // Brake (0–55px)
      let brkW: Float = evt.brake * 55.0;
      if brkW < 1.0 { brkW = 1.0; }
      this.mteBrakeBar.SetSize(new Vector2(brkW, 6.0));

      // Clutch (0–55px)
      let cltW: Float = evt.clutch * 55.0;
      if cltW < 1.0 { cltW = 1.0; }
      this.mteClutchBar.SetSize(new Vector2(cltW, 6.0));

      // Steering text
      let steerStr: String;
      if evt.steering < -0.01 {
        steerStr = "STR <" + FloatToStringPrec(AbsF(evt.steering), 2);
      } else if evt.steering > 0.01 {
        steerStr = "STR  " + FloatToStringPrec(evt.steering, 2) + ">";
      } else {
        steerStr = "STR  0.00";
      }
      this.mteSteeringText.SetText(steerStr);

      // Handbrake indicator
      if evt.handbrake {
        this.mteHandbrakeText.SetTintColor(cRed);
      } else {
        this.mteHandbrakeText.SetTintColor(cDim);
      }
    }

    // ── G-forces (conditional) ────────────────────────────────
    if IsDefined(this.mteGContainer) {
      this.mteGContainer.SetVisible(evt.showGForces);
    }
    if evt.showGForces {
      let longGAbs: Float = AbsF(evt.longG);
      let longGColor: HDRColor;
      if longGAbs > 0.5 {
        longGColor = cOrange;
      } else if longGAbs > 0.2 {
        longGColor = cYellow;
      } else {
        longGColor = cWhite;
      }
      let longGPrefix: String;
      if evt.longG >= 0.0 {
        longGPrefix = "+";
      } else {
        longGPrefix = "";
      }
      this.mteLongGText.SetText(longGPrefix + FloatToStringPrec(evt.longG, 2) + "G");
      this.mteLongGText.SetTintColor(longGColor);

      let latGAbs: Float = AbsF(evt.latG);
      let latGColor: HDRColor;
      if latGAbs > 0.5 {
        latGColor = cOrange;
      } else if latGAbs > 0.2 {
        latGColor = cYellow;
      } else {
        latGColor = cWhite;
      }
      let latGPrefix: String;
      if evt.latG >= 0.0 {
        latGPrefix = "+";
      } else {
        latGPrefix = "";
      }
      this.mteLatGText.SetText(latGPrefix + FloatToStringPrec(evt.latG, 2) + "G");
      this.mteLatGText.SetTintColor(latGColor);
    }

    // ── Vehicle health (conditional) ──────────────────────────
    if IsDefined(this.mteHealthContainer) {
      this.mteHealthContainer.SetVisible(evt.showHealth);
    }
    if evt.showHealth {
      let hpW: Float = evt.vehicleHealth * 242.0;
      if hpW < 1.0 { hpW = 1.0; }
      this.mteHealthBar.SetSize(new Vector2(hpW, 6.0));

      let hpColor: HDRColor;
      if evt.vehicleHealth > 0.6 {
        hpColor = cGreen;
      } else if evt.vehicleHealth > 0.3 {
        hpColor = cYellow;
      } else {
        hpColor = cRed;
      }
      this.mteHealthBar.SetTintColor(hpColor);
    }
  }

  // ── Race overlay ────────────────────────────────────────────
  let isPreraceActive: Bool = evt.preraceActive;
  let isQualiActive: Bool = evt.qualiActive;
  let isRaceActive: Bool = evt.raceActive;
  let isRaceCountdownActive: Bool = evt.raceCountdown;
  let isKnockoutActive: Bool = evt.knockoutActive;
  let trackName: String = evt.trackName;
  let phaseLabel: String = evt.phaseLabel;
  let objectiveText: String = evt.objectiveText;
  let statusText: String = evt.statusText;
  let countdownValue: Int32 = evt.countdownValue;
  let countdownPhase: Int32 = evt.countdownPhase;
  let startType: String = evt.startType;
  let racePosition: Int32 = evt.racePosition;
  let raceFieldSize: Int32 = evt.raceFieldSize;
  let raceTime: Float = evt.raceTime;
  let gapText: String = evt.gapText;
  let gapBehindText: String = evt.gapBehindText;
  let rivalName: String = evt.rivalAheadName;
  let rivalIsAhead: Bool = evt.rivalIsAhead;
  let standingsText: String = evt.standingsText;
  let distToFinish: Float = evt.distToFinish;
  let eliminationCountdown: Float = evt.eliminationCountdown;
  let remainingDrivers: Int32 = evt.remainingDrivers;
  let isInDangerZone: Bool = evt.isInDangerZone;
  let lastEliminatedName: String = evt.lastEliminatedName;
  let showRace: Bool = isPreraceActive || isQualiActive || isRaceActive || isRaceCountdownActive || isKnockoutActive;
  let showPhaseBlock: Bool = isPreraceActive || isQualiActive || ((isRaceActive || isKnockoutActive) && (NotEquals(phaseLabel, "") || NotEquals(objectiveText, "") || NotEquals(statusText, "")));
  let showCountdown: Bool = isRaceCountdownActive;
  let showRacePosition: Bool = isRaceActive || isKnockoutActive;
  let showGridLights: Bool = Equals(startType, "grid") || Equals(startType, "sidebyside");
  let showGapText: Bool = (isRaceActive || isKnockoutActive) && NotEquals(gapText, "");
  let showRivalCallout: Bool = (isRaceActive || isKnockoutActive) && NotEquals(rivalName, "");
  let showStandings: Bool = (isRaceActive || isPreraceActive || isQualiActive) && NotEquals(standingsText, "");
  let showDistToFinish: Bool = isRaceActive && distToFinish >= 0.0;
  let showKnockoutBanner: Bool = isKnockoutActive;
  let showEliminationFlash: Bool = isKnockoutActive && NotEquals(lastEliminatedName, "");
  let countdownText: String;
  if countdownValue <= 0 {
    countdownText = "GO!";
  } else {
    countdownText = ToString(countdownValue);
  }
  let positionText: String = "P" + ToString(racePosition) + "/" + ToString(raceFieldSize);
  let raceTimeText: String;
  let baseSeconds: Int32 = Cast<Int32>(raceTime);
  let baseTenths: Int32 = Cast<Int32>((raceTime - Cast<Float>(baseSeconds)) * 10.0);
  raceTimeText = ToString(baseSeconds) + "." + ToString(baseTenths) + "s";
  let qualiTimeText: String = FloatToStringPrec(raceTime, 2) + "s";
  let distanceText: String = "";
  if distToFinish >= 0.0 {
    if distToFinish > 1000.0 {
      distanceText = FloatToStringPrec(distToFinish / 1000.0, 1) + "km";
    } else {
      distanceText = ToString(Cast<Int32>(distToFinish)) + "m";
    }
  }
  let rivalCalloutText: String = "";
  if NotEquals(rivalName, "") {
    let baseArrow: String;
    if rivalIsAhead {
      baseArrow = "▲ ";
    } else {
      baseArrow = "▼ ";
    }
    rivalCalloutText = baseArrow + "RIVAL  " + rivalName;
  }
  let eliminationBannerText: String = "ELIM: " + ToString(Cast<Int32>(eliminationCountdown)) + "s  |  " + ToString(remainingDrivers) + " left";
  let eliminationFlashText: String = "ELIMINATED: " + lastEliminatedName;
  if IsDefined(runtime) {
    isPreraceActive = runtime.IsPreraceActive();
    isQualiActive = runtime.IsQualifyingActive();
    isRaceActive = runtime.IsRaceActive();
    isRaceCountdownActive = runtime.IsRaceCountdownActive();
    isKnockoutActive = runtime.IsKnockoutActive();
    trackName = runtime.GetTrackName();
    phaseLabel = runtime.GetPhaseLabel();
    objectiveText = runtime.GetObjectiveText();
    statusText = runtime.GetStatusText();
    countdownValue = runtime.GetCountdownValue();
    countdownPhase = runtime.GetCountdownPhase();
    startType = runtime.GetStartType();
    racePosition = runtime.GetRacePosition();
    raceFieldSize = runtime.GetRaceFieldSize();
    raceTime = runtime.GetRaceTime();
    gapText = runtime.GetGapText();
    rivalName = runtime.GetRivalName();
    rivalIsAhead = runtime.GetRivalIsAhead();
    standingsText = runtime.GetStandingsText();
    distToFinish = runtime.GetDistanceToFinish();
    eliminationCountdown = runtime.GetEliminationCountdown();
    remainingDrivers = runtime.GetRemainingDrivers();
    isInDangerZone = runtime.IsInDangerZone();
    lastEliminatedName = runtime.GetLastEliminatedName();
    showRace = runtime.ShouldShowRaceOverlay();
    showPhaseBlock = runtime.ShouldShowPhaseBlock();
    showCountdown = runtime.ShouldShowCountdown();
    showRacePosition = runtime.ShouldShowRacePosition();
    showGridLights = runtime.ShouldShowGridLights();
    showGapText = runtime.ShouldShowGapText();
    showRivalCallout = runtime.ShouldShowRivalCallout();
    showStandings = runtime.ShouldShowStandings();
    showDistToFinish = runtime.ShouldShowDistanceToFinish();
    showKnockoutBanner = runtime.ShouldShowKnockoutBanner();
    showEliminationFlash = runtime.ShouldShowEliminationFlash();
    countdownText = runtime.GetCountdownDisplayText();
    positionText = runtime.GetRacePositionText();
    raceTimeText = runtime.GetRaceTimeText();
    qualiTimeText = runtime.GetQualifyingTimeText();
    distanceText = runtime.GetDistanceToFinishText();
    rivalCalloutText = runtime.GetRivalCalloutText();
    eliminationBannerText = runtime.GetEliminationBannerText();
    eliminationFlashText = runtime.GetEliminationFlashText();
  }
  this.mteRaceContainer.SetVisible(showRace);

  if showRace {
    this.mteTrackText.SetText(trackName);

    if IsDefined(this.mtePhaseText) {
      this.mtePhaseText.SetVisible(showPhaseBlock);
      this.mtePhaseText.SetText(phaseLabel);
    }
    if IsDefined(this.mteObjectiveText) {
      this.mteObjectiveText.SetVisible(showPhaseBlock);
      this.mteObjectiveText.SetText(objectiveText);
    }
    if IsDefined(this.mteStatusText) {
      this.mteStatusText.SetVisible(showPhaseBlock);
      this.mteStatusText.SetText(statusText);
    }

    if showCountdown {
      this.mteCountdownText.SetVisible(true);
      this.mtePosText.SetVisible(false);
      if IsDefined(this.mtePhaseText) { this.mtePhaseText.SetVisible(false); }
      if IsDefined(this.mteObjectiveText) { this.mteObjectiveText.SetVisible(false); }
      if IsDefined(this.mteStatusText) { this.mteStatusText.SetVisible(false); }

      if countdownValue <= 0 {
        this.mteCountdownText.SetTintColor(cGreen);
      } else {
        this.mteCountdownText.SetTintColor(cYellow);
      }
      this.mteCountdownText.SetText(countdownText);
      this.mteTimeText.SetText("");

      // ── Grid lights ──────────────────────────────────────
      if IsDefined(this.mteGridLightsContainer) {
        this.mteGridLightsContainer.SetVisible(showGridLights);
      }
      if showGridLights {
        let cOff: HDRColor   = new HDRColor(0.15, 0.15, 0.15, 0.5);
        let cRedLit: HDRColor = new HDRColor(1.18, 0.12, 0.10, 1.0);
        let cGrnLit: HDRColor = new HDRColor(0.10, 1.0, 0.20, 1.0);
        let phase: Int32 = countdownPhase;

        // Phase 5: all red lit. Phase 4..1: lights going out one by one. Phase 0: all green.
        if phase == 0 {
          // All green = GO!
          if IsDefined(this.mteGridLight1) { this.mteGridLight1.SetTintColor(cGrnLit); this.mteGridLight1.SetOpacity(1.0); }
          if IsDefined(this.mteGridLight2) { this.mteGridLight2.SetTintColor(cGrnLit); this.mteGridLight2.SetOpacity(1.0); }
          if IsDefined(this.mteGridLight3) { this.mteGridLight3.SetTintColor(cGrnLit); this.mteGridLight3.SetOpacity(1.0); }
          if IsDefined(this.mteGridLight4) { this.mteGridLight4.SetTintColor(cGrnLit); this.mteGridLight4.SetOpacity(1.0); }
          if IsDefined(this.mteGridLight5) { this.mteGridLight5.SetTintColor(cGrnLit); this.mteGridLight5.SetOpacity(1.0); }
        } else {
          // Red lights: phase 5 = 5 lit, phase 4 = 4 lit, etc.
          if IsDefined(this.mteGridLight1) { if phase >= 5 { this.mteGridLight1.SetTintColor(cRedLit); this.mteGridLight1.SetOpacity(1.0); } else { this.mteGridLight1.SetTintColor(cOff); this.mteGridLight1.SetOpacity(0.4); } }
          if IsDefined(this.mteGridLight2) { if phase >= 4 { this.mteGridLight2.SetTintColor(cRedLit); this.mteGridLight2.SetOpacity(1.0); } else { this.mteGridLight2.SetTintColor(cOff); this.mteGridLight2.SetOpacity(0.4); } }
          if IsDefined(this.mteGridLight3) { if phase >= 3 { this.mteGridLight3.SetTintColor(cRedLit); this.mteGridLight3.SetOpacity(1.0); } else { this.mteGridLight3.SetTintColor(cOff); this.mteGridLight3.SetOpacity(0.4); } }
          if IsDefined(this.mteGridLight4) { if phase >= 2 { this.mteGridLight4.SetTintColor(cRedLit); this.mteGridLight4.SetOpacity(1.0); } else { this.mteGridLight4.SetTintColor(cOff); this.mteGridLight4.SetOpacity(0.4); } }
          if IsDefined(this.mteGridLight5) { if phase >= 1 { this.mteGridLight5.SetTintColor(cRedLit); this.mteGridLight5.SetOpacity(1.0); } else { this.mteGridLight5.SetTintColor(cOff); this.mteGridLight5.SetOpacity(0.4); } }
        }
      }

      // Hide gap during countdown
      if IsDefined(this.mteGapText) { this.mteGapText.SetVisible(false); }
      // Hide rival callout during countdown
      if IsDefined(this.mteRivalText) { this.mteRivalText.SetVisible(false); }

    } else if showRacePosition {
      this.mteCountdownText.SetVisible(false);
      this.mtePosText.SetVisible(true);
      if IsDefined(this.mtePhaseText) { this.mtePhaseText.SetVisible(showPhaseBlock); }
      if IsDefined(this.mteObjectiveText) { this.mteObjectiveText.SetVisible(showPhaseBlock); }
      if IsDefined(this.mteStatusText) { this.mteStatusText.SetVisible(showPhaseBlock); }

      // Hide grid lights during racing
      if IsDefined(this.mteGridLightsContainer) { this.mteGridLightsContainer.SetVisible(false); }

      this.mtePosText.SetText(positionText);

      let posColor: HDRColor;
      if racePosition == 1 {
        posColor = cYellow;
      } else if racePosition <= 3 {
        posColor = cGreen;
      } else {
        posColor = cWhite;
      }
      this.mtePosText.SetTintColor(posColor);

      this.mteTimeText.SetText(raceTimeText);

      // Gap text
      if IsDefined(this.mteGapText) {
        if showGapText {
          this.mteGapText.SetVisible(true);
          this.mteGapText.SetText(gapText);
          // Bright teal if leading, green if gaining, red if losing
          if racePosition == 1 {
            this.mteGapText.SetTintColor(new HDRColor(0.12, 1.0, 0.82, 1.0));
          } else {
            // Check if gap starts with "-" (closing in)
            let firstChar: String = StrLeft(gapText, 1);
            if Equals(firstChar, "-") {
              this.mteGapText.SetTintColor(cGreen);
            } else {
              this.mteGapText.SetTintColor(cRed);
            }
          }
        } else {
          this.mteGapText.SetVisible(false);
        }
      }

      // Gap behind text
      if IsDefined(this.mteGapBehindText) {
        if NotEquals(gapBehindText, "") {
          this.mteGapBehindText.SetText(gapBehindText);
          this.mteGapBehindText.SetVisible(true);
        } else {
          this.mteGapBehindText.SetVisible(false);
        }
      }

      // Rival callout
      if IsDefined(this.mteRivalText) {
        if showRivalCallout {
          let cOrange: HDRColor = new HDRColor(1.0, 0.55, 0.0, 1.0);
          this.mteRivalText.SetText(rivalCalloutText);
          this.mteRivalText.SetTintColor(cOrange);
          this.mteRivalText.SetVisible(true);
        } else {
          this.mteRivalText.SetVisible(false);
        }
      }
    }

    if isQualiActive {
      this.mteCountdownText.SetVisible(false);
      this.mtePosText.SetVisible(false);
      if IsDefined(this.mteGridLightsContainer) { this.mteGridLightsContainer.SetVisible(false); }
      this.mteTimeText.SetText(qualiTimeText);
      if IsDefined(this.mteGapText) { this.mteGapText.SetVisible(false); }
      if IsDefined(this.mteRivalText) { this.mteRivalText.SetVisible(false); }
    }

    if isPreraceActive {
      this.mteCountdownText.SetVisible(false);
      this.mtePosText.SetVisible(false);
      this.mteTimeText.SetText("");
      if IsDefined(this.mteGridLightsContainer) { this.mteGridLightsContainer.SetVisible(false); }
      if IsDefined(this.mteGapText) { this.mteGapText.SetVisible(false); }
      if IsDefined(this.mteRivalText) { this.mteRivalText.SetVisible(false); }
    }

    // Standings text (visible during racing)
    if IsDefined(this.mteStandingsText) {
      if showStandings {
        this.mteStandingsText.SetVisible(true);
        this.mteStandingsText.SetText(standingsText);
      } else {
        this.mteStandingsText.SetVisible(false);
      }
    }

    // Distance to finish
    if IsDefined(this.mteDistText) {
      if showDistToFinish {
        this.mteDistText.SetVisible(true);
        this.mteDistText.SetText(distanceText);
      } else {
        this.mteDistText.SetVisible(false);
      }
    }

    // ── Knockout overlay widgets ──────────────────────────────
    if IsDefined(this.mteElimText) {
      if showKnockoutBanner {
        this.mteElimText.SetVisible(true);
        this.mteElimText.SetText(eliminationBannerText);

        if isInDangerZone {
          let cRedBright: HDRColor = new HDRColor(1.18, 0.20, 0.15, 1.0);
          this.mteElimText.SetTintColor(cRedBright);
        } else {
          let cElimDim: HDRColor = new HDRColor(0.40, 0.50, 0.50, 0.70);
          this.mteElimText.SetTintColor(cElimDim);
        }
      } else {
        this.mteElimText.SetVisible(false);
      }
    }

    if IsDefined(this.mteElimFlashText) {
      if showEliminationFlash {
        this.mteElimFlashText.SetVisible(true);
        this.mteElimFlashText.SetText(eliminationFlashText);
      } else {
        this.mteElimFlashText.SetVisible(false);
      }
    }
  }

  // Result card auto-dismiss (~60 fps assumed; imprecise but good enough)
  if IsDefined(this.mteResultContainer) && this.mteResultContainer.IsVisible() {
    if this.mteResultDismissTimer > 0.0 {
      this.mteResultDismissTimer -= 0.016;
      if this.mteResultDismissTimer <= 0.0 {
        this.mteResultContainer.SetVisible(false);
      }
    }
  }

  if IsDefined(this.mteTierRevealContainer) && this.mteTierRevealContainer.IsVisible() {
    if this.mteTierRevealDismissTimer > 0.0 {
      this.mteTierRevealDismissTimer -= 0.016;
      if this.mteTierRevealDismissTimer <= 0.0 {
        this.mteTierRevealContainer.SetVisible(false);
      }
    }
  }

  if IsDefined(this.mteSeasonLadderQueuedEvent) {
    if this.mteSeasonLadderQueueDelay > 0.0 {
      this.mteSeasonLadderQueueDelay -= 0.016;
    }
    if this.mteSeasonLadderQueueDelay <= 0.0 {
      let queuedLadderEvt: ref<MTESeasonLadderEvent> = this.mteSeasonLadderQueuedEvent;
      this.mteSeasonLadderQueuedEvent = null;
      this.MTEShowSeasonLadderNow(queuedLadderEvt);
    }
  }

  if IsDefined(this.mteSeasonLadderContainer) && this.mteSeasonLadderContainer.IsVisible() {
    if this.mteSeasonLadderDismissTimer > 0.0 {
      this.mteSeasonLadderDismissTimer -= 0.016;
      if this.mteSeasonLadderDismissTimer <= 0.0 {
        this.mteSeasonLadderContainer.SetVisible(false);
      }
    }
  }
}


// ── Hide HUD — called from CET on shutdown ────────────────────

@addMethod(inkGameController)
protected cb func OnMTEHudUpdateEvent(evt: ref<MTEHudUpdateEvent>) -> Bool {
  if !this.MTEIsGameplayHudRoot() {
    return false;
  }

  this.MTEHandleUpdate(evt);
  return true;
}

@addMethod(inkGameController)
public func MTEHideHud() -> Void {
  if !this.MTEIsGameplayHudRoot() {
    return;
  }

  let runtime: ref<MTERaceRuntime> = MTERaceRuntime.GetInstance();
  if IsDefined(runtime) {
    runtime.Reset();
  }

  if IsDefined(this.mteHudContainer) {
    this.mteHudContainer.SetVisible(false);
  }
  if IsDefined(this.mteRaceContainer) {
    this.mteRaceContainer.SetVisible(false);
  }
  if IsDefined(this.mteResultContainer) {
    this.mteResultContainer.SetVisible(false);
  }
  if IsDefined(this.mteTierRevealContainer) {
    this.mteTierRevealContainer.SetVisible(false);
  }
  if IsDefined(this.mteSeasonLadderContainer) {
    this.mteSeasonLadderContainer.SetVisible(false);
  }

  this.mteSeasonLadderQueuedEvent = null;
  this.mteSeasonLadderQueueDelay = 0.0;

  this.MTEClearRacerMappins();
}

// ── Show race result card ─────────────────────────────────────

@addMethod(inkGameController)
protected cb func OnMTEHudHideEvent(evt: ref<MTEHudHideEvent>) -> Bool {
  if !this.MTEIsGameplayHudRoot() {
    return false;
  }

  this.MTEHideHud();
  return true;
}

@addMethod(inkGameController)
public func MTEShowResult(evt: ref<MTERaceResultEvent>) -> Void {
  if !this.MTEIsGameplayHudRoot() {
    return;
  }

  if !IsDefined(this.mteResultContainer) {
    return;
  }

  let cYellow: HDRColor = new HDRColor(1.0, 0.93, 0.33, 1.0);
  let cGreen: HDRColor  = new HDRColor(0.33, 1.0, 0.42, 1.0);
  let cRed: HDRColor    = new HDRColor(1.18, 0.38, 0.35, 1.0);
  let cCyan: HDRColor   = new HDRColor(0.37, 0.96, 1.0, 1.0);
  let cDim: HDRColor    = new HDRColor(0.40, 0.50, 0.50, 0.70);

  // Position
  let posStr: String;
  let posColor: HDRColor;
  if evt.isDNF {
    posStr = "DNF";
    posColor = cRed;
  } else {
    posStr = "P" + ToString(evt.position);
    if evt.position == 1 {
      posColor = cYellow;
    } else if evt.position <= 3 {
      posColor = cGreen;
    } else {
      posColor = cCyan;
    }
  }
  if IsDefined(this.mteResultPos) {
    this.mteResultPos.SetText(posStr);
    this.mteResultPos.SetTintColor(posColor);
  }

  // Time
  if IsDefined(this.mteResultTime) {
    this.mteResultTime.SetText(evt.timeStr);
  }

  // Payout
  if IsDefined(this.mteResultPayout) {
    this.mteResultPayout.SetText("+ " + ToString(evt.payout) + " ¥");
    this.mteResultPayout.SetTintColor(evt.isDNF ? cRed : cGreen);
  }

  // Rep
  if IsDefined(this.mteResultRep) {
    let repStr: String;
    if evt.repGain >= 0 {
      repStr = "+" + ToString(evt.repGain) + " REP";
    } else {
      repStr = ToString(evt.repGain) + " REP";
    }
    this.mteResultRep.SetText(repStr);
    this.mteResultRep.SetTintColor(evt.repGain > 0 ? cCyan : cRed);
  }

  // Extra info (clean, wager, bounty)
  if IsDefined(this.mteResultExtra) {
    let extraStr: String = "";
    if evt.isClean {
      extraStr = "CLEAN RUN";
    }
    if NotEquals(evt.wagerResult, "") {
      if NotEquals(extraStr, "") { extraStr += "  |  "; }
      extraStr += "WAGER " + evt.wagerResult;
    }
    if NotEquals(evt.bountyText, "") {
      if NotEquals(extraStr, "") { extraStr += "  |  "; }
      extraStr += evt.bountyText;
    }
    if NotEquals(evt.dragPenaltyText, "") {
      if NotEquals(extraStr, "") { extraStr += "  |  "; }
      extraStr += evt.dragPenaltyText;
    }
    this.mteResultExtra.SetText(extraStr);
    this.mteResultExtra.SetTintColor(cDim);
  }

  this.mteResultContainer.SetVisible(true);
  this.mteResultDismissTimer = 7.0;
}

@addMethod(inkGameController)
public func MTEShowPrestigeReveal(evt: ref<MTEPrestigeRevealEvent>) -> Void {
  if !this.MTEIsGameplayHudRoot() {
    return;
  }

  if !IsDefined(this.mteTierRevealContainer) {
    return;
  }

  let cCyan: HDRColor = new HDRColor(0.37, 0.96, 1.0, 1.0);
  let cRed: HDRColor = new HDRColor(1.18, 0.38, 0.35, 1.0);
  let cYellow: HDRColor = new HDRColor(1.0, 0.93, 0.33, 1.0);
  let accent: HDRColor;
  let directionUp: Bool = Equals(evt.direction, "up");
  let titleText: String = evt.title;
  let subtitleText: String = evt.fromTier + " -> " + evt.toTier;

  if directionUp {
    accent = cCyan;
    if Equals(titleText, "") {
      titleText = "PROMOTED";
    }
  } else {
    accent = cRed;
    if Equals(titleText, "") {
      titleText = "RELEGATED";
    }
  }

  if IsDefined(this.mteTierRevealTitle) {
    this.mteTierRevealTitle.SetText(titleText);
    this.mteTierRevealTitle.SetTintColor(accent);
  }
  if IsDefined(this.mteTierRevealSubtitle) {
    this.mteTierRevealSubtitle.SetText(subtitleText);
    this.mteTierRevealSubtitle.SetTintColor(cYellow);
  }
  if IsDefined(this.mteTierRevealBody) {
    this.mteTierRevealBody.SetText(evt.body);
  }

  this.mteTierRevealContainer.SetVisible(true);
  this.mteTierRevealDismissTimer = 8.0;
}

@addMethod(inkGameController)
private func MTEShowSeasonLadderNow(evt: ref<MTESeasonLadderEvent>) -> Void {
  if !this.MTEIsGameplayHudRoot() {
    return;
  }

  if !IsDefined(this.mteSeasonLadderContainer) {
    return;
  }

  let cCyan: HDRColor = new HDRColor(0.37, 0.96, 1.0, 1.0);
  let cGreen: HDRColor = new HDRColor(0.33, 1.0, 0.42, 1.0);
  let cRed: HDRColor = new HDRColor(1.18, 0.38, 0.35, 1.0);
  let cYellow: HDRColor = new HDRColor(1.0, 0.93, 0.33, 1.0);
  let accent: HDRColor = cCyan;

  if Equals(evt.direction, "up") {
    accent = cGreen;
  } else {
    if Equals(evt.direction, "down") {
      accent = cRed;
    }
  }

  if IsDefined(this.mteResultContainer) {
    this.mteResultContainer.SetVisible(false);
    this.mteResultDismissTimer = 0.0;
  }

  if IsDefined(this.mteSeasonLadderTitle) {
    this.mteSeasonLadderTitle.SetText(Equals(evt.title, "") ? "SEASON ACCOUNT" : evt.title);
    this.mteSeasonLadderTitle.SetTintColor(accent);
  }
  if IsDefined(this.mteSeasonLadderSummary) {
    this.mteSeasonLadderSummary.SetText(evt.summary);
    this.mteSeasonLadderSummary.SetTintColor(cYellow);
  }
  if IsDefined(this.mteSeasonLadderMovement) {
    this.mteSeasonLadderMovement.SetText(evt.movementText);
  }
  if IsDefined(this.mteSeasonLadderTable) {
    this.mteSeasonLadderTable.SetText(evt.ladderText);
    this.mteSeasonLadderTable.SetTintColor(accent);
  }
  if IsDefined(this.mteSeasonLadderFooter) {
    this.mteSeasonLadderFooter.SetText(evt.footerText);
  }

  this.mteSeasonLadderContainer.SetVisible(true);
  this.mteSeasonLadderDismissTimer = 8.5;
}

@addMethod(inkGameController)
public func MTEQueueSeasonLadder(evt: ref<MTESeasonLadderEvent>) -> Void {
  if !this.MTEIsGameplayHudRoot() {
    return;
  }

  if !IsDefined(this.mteSeasonLadderContainer) {
    return;
  }

  if IsDefined(this.mteResultContainer) && this.mteResultContainer.IsVisible() {
    this.mteSeasonLadderQueuedEvent = evt;
    this.mteSeasonLadderQueueDelay = 2.4;
    return;
  }

  this.MTEShowSeasonLadderNow(evt);
}

@addMethod(inkGameController)
protected cb func OnMTEPrestigeRevealEvent(evt: ref<MTEPrestigeRevealEvent>) -> Bool {
  if !this.MTEIsGameplayHudRoot() {
    return false;
  }

  this.MTEShowPrestigeReveal(evt);
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTESeasonLadderEvent(evt: ref<MTESeasonLadderEvent>) -> Bool {
  if !this.MTEIsGameplayHudRoot() {
    return false;
  }

  this.MTEQueueSeasonLadder(evt);
  return true;
}


// ── Place mappin — called from CET ────────────────────────────

@addMethod(inkGameController)
private func MTETrackRegisteredMappin(id: NewMappinID) -> Void {
  // Disabled: blackboard TrackedMappin triggers quest tracker UI, not GPS.
}

@addMethod(inkGameController)
private func MTEUntrackRaceMappin() -> Void {
  let system: ref<MappinSystem> = GameInstance.GetMappinSystem(GetGameInstance());
  let trackedId: NewMappinID = system.GetManuallyTrackedMappinID();
  if Equals(trackedId, this.mteStartMappinID) || Equals(trackedId, this.mteFinishMappinID) {
    system.UntrackMappin();
  }
}

@addMethod(inkGameController)
private func MTEIsRacerMarkerRole(role: String) -> Bool {
  return Equals(role, "racer1") || Equals(role, "racer2") || Equals(role, "racer3") || Equals(role, "racer4")
    || Equals(role, "racer5") || Equals(role, "racer6") || Equals(role, "racer7") || Equals(role, "racer8")
    || Equals(role, "racer9") || Equals(role, "racer10") || Equals(role, "racer11") || Equals(role, "racer12");
}

@addMethod(inkGameController)
private func MTERegisterRacerMappin(role: String, system: ref<MappinSystem>, mappinData: MappinData, pos: Vector4) -> Bool {
  if Equals(role, "racer1") {
    if this.mteHasRacer1Mappin {
      system.UnregisterMappin(this.mteRacer1MappinID);
    }
    this.mteRacer1MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer1Mappin = true;
    return true;
  }
  if Equals(role, "racer2") {
    if this.mteHasRacer2Mappin {
      system.UnregisterMappin(this.mteRacer2MappinID);
    }
    this.mteRacer2MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer2Mappin = true;
    return true;
  }
  if Equals(role, "racer3") {
    if this.mteHasRacer3Mappin {
      system.UnregisterMappin(this.mteRacer3MappinID);
    }
    this.mteRacer3MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer3Mappin = true;
    return true;
  }
  if Equals(role, "racer4") {
    if this.mteHasRacer4Mappin {
      system.UnregisterMappin(this.mteRacer4MappinID);
    }
    this.mteRacer4MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer4Mappin = true;
    return true;
  }
  if Equals(role, "racer5") {
    if this.mteHasRacer5Mappin {
      system.UnregisterMappin(this.mteRacer5MappinID);
    }
    this.mteRacer5MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer5Mappin = true;
    return true;
  }
  if Equals(role, "racer6") {
    if this.mteHasRacer6Mappin {
      system.UnregisterMappin(this.mteRacer6MappinID);
    }
    this.mteRacer6MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer6Mappin = true;
    return true;
  }
  if Equals(role, "racer7") {
    if this.mteHasRacer7Mappin {
      system.UnregisterMappin(this.mteRacer7MappinID);
    }
    this.mteRacer7MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer7Mappin = true;
    return true;
  }
  if Equals(role, "racer8") {
    if this.mteHasRacer8Mappin {
      system.UnregisterMappin(this.mteRacer8MappinID);
    }
    this.mteRacer8MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer8Mappin = true;
    return true;
  }
  if Equals(role, "racer9") {
    if this.mteHasRacer9Mappin {
      system.UnregisterMappin(this.mteRacer9MappinID);
    }
    this.mteRacer9MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer9Mappin = true;
    return true;
  }
  if Equals(role, "racer10") {
    if this.mteHasRacer10Mappin {
      system.UnregisterMappin(this.mteRacer10MappinID);
    }
    this.mteRacer10MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer10Mappin = true;
    return true;
  }
  if Equals(role, "racer11") {
    if this.mteHasRacer11Mappin {
      system.UnregisterMappin(this.mteRacer11MappinID);
    }
    this.mteRacer11MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer11Mappin = true;
    return true;
  }
  if Equals(role, "racer12") {
    if this.mteHasRacer12Mappin {
      system.UnregisterMappin(this.mteRacer12MappinID);
    }
    this.mteRacer12MappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasRacer12Mappin = true;
    return true;
  }
  return false;
}

@addMethod(inkGameController)
public func MTEPlaceMappin(evt: ref<MTEPlaceMappinEvent>) -> Void {
  let roleMappinData: ref<GameplayRoleMappinData> = new GameplayRoleMappinData();
  let titleText: String;
  let captionText: String;
  let isRacer: Bool;
  isRacer = this.MTEIsRacerMarkerRole(evt.markerRole);
  roleMappinData.m_isQuest = true;
  roleMappinData.m_visibleThroughWalls = isRacer;
  roleMappinData.m_range = isRacer ? 160.0 : 100.0;
  roleMappinData.m_gameplayRole = EGameplayRole.FastTravel;
  roleMappinData.m_textureID = t"MappinIcons.GenericDeviceMappin";
  roleMappinData.m_showOnMiniMap = !isRacer;
  roleMappinData.m_isMappinCustom = true;
  roleMappinData.m_customMappinTexturePart = n"car";
  if NotEquals(evt.markerTitle, "") {
    titleText = evt.markerTitle;
  } else {
    if evt.isStart {
      titleText = "Race Start";
    } else {
      titleText = "Race Finish";
    }
  }
  if NotEquals(evt.markerCaption, "") {
    captionText = evt.markerCaption;
  } else {
    if evt.isStart {
      captionText = "MT_Ecosystem|0.20|1.00|0.20|1.00";
    } else {
      captionText = "MT_Ecosystem|1.00|0.20|0.20|1.00";
    }
  }
  roleMappinData.m_customMappinTitle = titleText;
  roleMappinData.m_customMappinDescription = captionText;

  let mappinData: MappinData = new MappinData();
  mappinData.mappinType = t"Mappins.QuestStaticMappinDefinition";
  mappinData.variant = gamedataMappinVariant.DefaultQuestVariant;
  mappinData.active = true;
  mappinData.visibleThroughWalls = isRacer;
  mappinData.scriptData = roleMappinData;

  let pos: Vector4 = new Vector4(evt.posX, evt.posY, evt.posZ, 1.0);
  let system: ref<MappinSystem> = GameInstance.GetMappinSystem(GetGameInstance());

  if this.MTERegisterRacerMappin(evt.markerRole, system, mappinData, pos) {
    return;
  }

  if evt.isStart && Equals(evt.markerRole, "left") {
    if this.mteHasStartLeftMappin {
      system.UnregisterMappin(this.mteStartLeftMappinID);
    }
    this.mteStartLeftMappinID = system.RegisterMappin(mappinData, pos);
    this.mteHasStartLeftMappin = true;
  } else {
    if evt.isStart && Equals(evt.markerRole, "right") {
      if this.mteHasStartRightMappin {
        system.UnregisterMappin(this.mteStartRightMappinID);
      }
      this.mteStartRightMappinID = system.RegisterMappin(mappinData, pos);
      this.mteHasStartRightMappin = true;
    } else {
      if !evt.isStart && Equals(evt.markerRole, "left") {
        if this.mteHasFinishLeftMappin {
          system.UnregisterMappin(this.mteFinishLeftMappinID);
        }
        this.mteFinishLeftMappinID = system.RegisterMappin(mappinData, pos);
        this.mteHasFinishLeftMappin = true;
      } else {
        if !evt.isStart && Equals(evt.markerRole, "right") {
          if this.mteHasFinishRightMappin {
            system.UnregisterMappin(this.mteFinishRightMappinID);
          }
          this.mteFinishRightMappinID = system.RegisterMappin(mappinData, pos);
          this.mteHasFinishRightMappin = true;
        } else {
          if evt.isStart {
            if this.mteHasStartMappin {
              system.UnregisterMappin(this.mteStartMappinID);
            }
            this.mteStartMappinID = system.RegisterMappin(mappinData, pos);
            this.mteHasStartMappin = true;
          } else {
            if this.mteHasFinishMappin {
              system.UnregisterMappin(this.mteFinishMappinID);
            }
            this.mteFinishMappinID = system.RegisterMappin(mappinData, pos);
            this.mteHasFinishMappin = true;
          }
        }
      }
    }
  }
}

@addMethod(inkGameController)
public func MTEClearRacerMappins() -> Void {
  let system: ref<MappinSystem> = GameInstance.GetMappinSystem(GetGameInstance());

  if this.mteHasRacer1Mappin {
    system.UnregisterMappin(this.mteRacer1MappinID);
    this.mteHasRacer1Mappin = false;
  }
  if this.mteHasRacer2Mappin {
    system.UnregisterMappin(this.mteRacer2MappinID);
    this.mteHasRacer2Mappin = false;
  }
  if this.mteHasRacer3Mappin {
    system.UnregisterMappin(this.mteRacer3MappinID);
    this.mteHasRacer3Mappin = false;
  }
  if this.mteHasRacer4Mappin {
    system.UnregisterMappin(this.mteRacer4MappinID);
    this.mteHasRacer4Mappin = false;
  }
  if this.mteHasRacer5Mappin {
    system.UnregisterMappin(this.mteRacer5MappinID);
    this.mteHasRacer5Mappin = false;
  }
  if this.mteHasRacer6Mappin {
    system.UnregisterMappin(this.mteRacer6MappinID);
    this.mteHasRacer6Mappin = false;
  }
  if this.mteHasRacer7Mappin {
    system.UnregisterMappin(this.mteRacer7MappinID);
    this.mteHasRacer7Mappin = false;
  }
  if this.mteHasRacer8Mappin {
    system.UnregisterMappin(this.mteRacer8MappinID);
    this.mteHasRacer8Mappin = false;
  }
  if this.mteHasRacer9Mappin {
    system.UnregisterMappin(this.mteRacer9MappinID);
    this.mteHasRacer9Mappin = false;
  }
  if this.mteHasRacer10Mappin {
    system.UnregisterMappin(this.mteRacer10MappinID);
    this.mteHasRacer10Mappin = false;
  }
  if this.mteHasRacer11Mappin {
    system.UnregisterMappin(this.mteRacer11MappinID);
    this.mteHasRacer11Mappin = false;
  }
  if this.mteHasRacer12Mappin {
    system.UnregisterMappin(this.mteRacer12MappinID);
    this.mteHasRacer12Mappin = false;
  }
}

// ── Clear mappins — called from CET ───────────────────────────

@addMethod(inkGameController)
public func MTEClearMappins() -> Void {
  let system: ref<MappinSystem> = GameInstance.GetMappinSystem(GetGameInstance());

  this.MTEUntrackRaceMappin();
  this.MTEClearRacerMappins();

  if this.mteHasStartMappin {
    system.UnregisterMappin(this.mteStartMappinID);
    this.mteHasStartMappin = false;
  }
  if this.mteHasFinishMappin {
    system.UnregisterMappin(this.mteFinishMappinID);
    this.mteHasFinishMappin = false;
  }
  if this.mteHasStartLeftMappin {
    system.UnregisterMappin(this.mteStartLeftMappinID);
    this.mteHasStartLeftMappin = false;
  }
  if this.mteHasStartRightMappin {
    system.UnregisterMappin(this.mteStartRightMappinID);
    this.mteHasStartRightMappin = false;
  }
  if this.mteHasFinishLeftMappin {
    system.UnregisterMappin(this.mteFinishLeftMappinID);
    this.mteHasFinishLeftMappin = false;
  }
  if this.mteHasFinishRightMappin {
    system.UnregisterMappin(this.mteFinishRightMappinID);
    this.mteHasFinishRightMappin = false;
  }
}

// ── Track mappin (switch GPS nav target) ────────────────────
// NOTE: MappinSystem has no API to programmatically set GPS tracking state.
// Both quest markers appear on the minimap; the player can track either manually.

@addMethod(inkGameController)
public func MTETrackMappin(evt: ref<MTETrackMappinEvent>) -> Void {
  // Disabled: blackboard approach triggers quest tracker, not GPS.
}

// ── Event callbacks for QueueEvent fallback ───────────────────

@addMethod(inkGameController)
protected cb func OnMTEPlaceMappinEvent(evt: ref<MTEPlaceMappinEvent>) -> Bool {
  this.MTEPlaceMappin(evt);
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTEClearMappinsEvent(evt: ref<MTEClearMappinsEvent>) -> Bool {
  this.MTEClearMappins();
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTEClearRacerMappinsEvent(evt: ref<MTEClearRacerMappinsEvent>) -> Bool {
  this.MTEClearRacerMappins();
  return true;
}

@addMethod(inkGameController)
protected cb func OnMTETrackMappinEvent(evt: ref<MTETrackMappinEvent>) -> Bool {
  this.MTETrackMappin(evt);
  return true;
}

// ── Race result event callback ─────────────────────────────────

@addMethod(inkGameController)
protected cb func OnMTERaceResultEvent(evt: ref<MTERaceResultEvent>) -> Bool {
  if !this.MTEIsGameplayHudRoot() {
    return false;
  }

  this.MTEShowResult(evt);
  return true;
}

@addMethod(BaseMappinBaseController)
protected final func __MTEIsRaceRoutePin() -> Bool {
  let mappin: ref<RuntimeMappin> = this.GetMappin() as RuntimeMappin;
  let runtime: ref<MTERaceRuntime>;
  let parts: array<String>;
  if !IsDefined(mappin) {
    return false;
  }
  runtime = MTERaceRuntime.GetInstance();
  if IsDefined(runtime) && runtime.IsRaceMappin(mappin.GetNewMappinID()) {
    return true;
  }
  parts = StrSplit(mappin.GetDisplayName(), "|");
  return ArraySize(parts) >= 3 && Equals(parts[0], "MT_Ecosystem");
}

@addMethod(BaseMappinBaseController)
protected final func __MTEIsStartRoutePin() -> Bool {
  let mappin: ref<RuntimeMappin> = this.GetMappin() as RuntimeMappin;
  let runtime: ref<MTERaceRuntime>;
  let parts: array<String>;
  if !IsDefined(mappin) {
    return false;
  }
  runtime = MTERaceRuntime.GetInstance();
  if IsDefined(runtime) && runtime.IsStartRaceMappin(mappin.GetNewMappinID()) {
    return true;
  }
  parts = StrSplit(mappin.GetDisplayName(), "|");
  return ArraySize(parts) >= 3 && Equals(parts[0], "MT_Ecosystem") && Equals(parts[1], "Start");
}

@addMethod(BaseMappinBaseController)
protected final func __MTEApplyRaceRouteTint() -> Void {
  let tint: HDRColor;
  let texturePart: CName;
  if !this.__MTEIsRaceRoutePin() {
    return;
  }
  if !inkWidgetRef.IsValid(this.iconWidget) {
    return;
  }
  if this.__MTEIsStartRoutePin() {
    tint = new HDRColor(0.20, 1.00, 0.35, 1.00);
    texturePart = n"minor_quest";
  } else {
    tint = new HDRColor(1.00, 0.40, 0.15, 1.00);
    texturePart = n"minor_quest";
  }
  inkImageRef.SetAtlasResource(this.iconWidget, r"base\\gameplay\\gui\\common\\icons\\mappin_icons.inkatlas");
  inkImageRef.SetTexturePart(this.iconWidget, texturePart);
  inkWidgetRef.SetTintColor(this.iconWidget, tint);
}

@wrapMethod(MinimapPOIMappinController)
protected final func UpdateIcon() -> Void {
  wrappedMethod();
  this.__MTEApplyRaceRouteTint();
}

@wrapMethod(MinimapDeviceMappinController)
protected func Update() -> Void {
  wrappedMethod();
  this.__MTEApplyRaceRouteTint();
}

@wrapMethod(QuestMappinController)
protected func UpdateIcon() -> Void {
  wrappedMethod();
  this.__MTEApplyRaceRouteTint();
}

@wrapMethod(GameplayMappinController)
private func UpdateIcon() -> Void {
  wrappedMethod();
  this.__MTEApplyRaceRouteTint();
}

@wrapMethod(BaseWorldMapMappinController)
protected func UpdateIcon() -> Void {
  wrappedMethod();
  this.__MTEApplyRaceRouteTint();
}

@wrapMethod(WorldMapTooltipController)
public func SetData(const data: script_ref<WorldMapTooltipData>, menu: ref<WorldMapMenuGameController>) -> Void {
  wrappedMethod(data, menu);

  let iMappin: wref<IMappin> = Deref(data).mappin;
  let runtimeMappin: ref<RuntimeMappin>;
  let runtime: ref<MTERaceRuntime>;
  let parts: array<String>;
  if !IsDefined(iMappin) {
    return;
  }

  // Try RuntimeMappin cast for start/finish ID checks
  runtimeMappin = iMappin as RuntimeMappin;
  if IsDefined(runtimeMappin) {
    runtime = MTERaceRuntime.GetInstance();
    if IsDefined(runtime) && runtime.IsStartRaceMappin(runtimeMappin.GetNewMappinID()) {
      inkTextRef.SetText(this.m_titleText, "Start");
      inkTextRef.SetText(this.m_descText, "Race start");
      return;
    };
    if IsDefined(runtime) && runtime.IsFinishRaceMappin(runtimeMappin.GetNewMappinID()) {
      inkTextRef.SetText(this.m_titleText, "Finish");
      inkTextRef.SetText(this.m_descText, "Race finish");
      return;
    };
  };

  // Fallback: parse pipe-delimited debugCaption (works for any mappin type)
  parts = StrSplit(iMappin.GetDisplayName(), "|");
  if ArraySize(parts) >= 3 && Equals(parts[0], "MT_Ecosystem") {
    inkTextRef.SetText(this.m_titleText, parts[1]);
    inkTextRef.SetText(this.m_descText, parts[2]);
  };
}

// MTECreateHUD is called from CET Lua via ObserveAfter on
// gameuiRootHudGameController::OnInitialize (see ink_hud.lua).
