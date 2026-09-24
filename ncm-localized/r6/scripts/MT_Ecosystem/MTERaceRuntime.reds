public class MTERaceRuntime extends ScriptableService {
  private let m_inVehicle: Bool;
  private let m_hudEnabled: Bool;
  private let m_preraceActive: Bool;
  private let m_qualiActive: Bool;
  private let m_raceActive: Bool;
  private let m_raceCountdown: Bool;
  private let m_knockoutActive: Bool;
  private let m_countdownValue: Int32;
  private let m_racePosition: Int32;
  private let m_raceFieldSize: Int32;
  private let m_remainingDrivers: Int32;
  private let m_countdownPhase: Int32;
  private let m_raceTime: Float;
  private let m_distToFinish: Float;
  private let m_eliminationCountdown: Float;
  private let m_isInDangerZone: Bool;
  private let m_rivalIsAhead: Bool;
  private let m_trackName: String;
  private let m_standingsText: String;
  private let m_gapText: String;
  private let m_startType: String;
  private let m_phaseLabel: String;
  private let m_objectiveText: String;
  private let m_statusText: String;
  private let m_qualiRequired: Bool;
  private let m_qualiCompleted: Bool;
  private let m_qualiGridPos: Int32;
  private let m_stageReadyCount: Int32;
  private let m_stageTotalCount: Int32;
  private let m_stageSpawning: Bool;
  private let m_playerStartReady: Bool;
  private let m_playerStartReason: String;
  private let m_finishLabel: String;
  private let m_knockoutPhase: String;
  private let m_lastEliminatedName: String;
  private let m_rivalName: String;
  private let m_startMappinID: NewMappinID;
  private let m_finishMappinID: NewMappinID;

  private cb func OnLoad() {
    this.Reset();
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/Start", this, n"OnSessionEvent");
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/End", this, n"OnSessionEvent");
  }

  private cb func OnSessionEvent(event: ref<GameSessionEvent>) {
    this.Reset();
  }

  public final static func GetInstance() -> ref<MTERaceRuntime> {
    return GameInstance.GetScriptableServiceContainer().GetService(NameOf(MTERaceRuntime)) as MTERaceRuntime;
  }

  public final func Reset() -> Void {
    this.m_inVehicle = false;
    this.m_hudEnabled = false;
    this.m_preraceActive = false;
    this.m_qualiActive = false;
    this.m_raceActive = false;
    this.m_raceCountdown = false;
    this.m_knockoutActive = false;
    this.m_countdownValue = 0;
    this.m_racePosition = 1;
    this.m_raceFieldSize = 1;
    this.m_remainingDrivers = 0;
    this.m_countdownPhase = -1;
    this.m_raceTime = 0.0;
    this.m_distToFinish = -1.0;
    this.m_eliminationCountdown = 0.0;
    this.m_isInDangerZone = false;
    this.m_rivalIsAhead = false;
    this.m_trackName = "";
    this.m_standingsText = "";
    this.m_gapText = "";
    this.m_startType = "";
    this.m_phaseLabel = "";
    this.m_objectiveText = "";
    this.m_statusText = "";
    this.m_qualiRequired = false;
    this.m_qualiCompleted = false;
    this.m_qualiGridPos = 0;
    this.m_stageReadyCount = 0;
    this.m_stageTotalCount = 0;
    this.m_stageSpawning = false;
    this.m_playerStartReady = false;
    this.m_playerStartReason = "";
    this.m_finishLabel = "";
    this.m_knockoutPhase = "";
    this.m_lastEliminatedName = "";
    this.m_rivalName = "";
  }

  public final func UpdateFromHudEvent(evt: ref<MTEHudUpdateEvent>) -> Void {
    this.m_inVehicle = evt.inVehicle;
    this.m_hudEnabled = evt.hudEnabled;
    this.m_preraceActive = evt.preraceActive;
    this.m_qualiActive = evt.qualiActive;
    this.m_raceActive = evt.raceActive;
    this.m_raceCountdown = evt.raceCountdown;
    this.m_knockoutActive = evt.knockoutActive;
    this.m_countdownValue = evt.countdownValue;
    this.m_racePosition = evt.racePosition;
    this.m_raceFieldSize = evt.raceFieldSize;
    this.m_remainingDrivers = evt.remainingDrivers;
    this.m_countdownPhase = evt.countdownPhase;
    this.m_raceTime = evt.raceTime;
    this.m_distToFinish = evt.distToFinish;
    this.m_eliminationCountdown = evt.eliminationCountdown;
    this.m_isInDangerZone = evt.isInDangerZone;
    this.m_rivalIsAhead = evt.rivalIsAhead;
    this.m_trackName = evt.trackName;
    this.m_standingsText = evt.standingsText;
    this.m_gapText = evt.gapText;
    this.m_startType = evt.startType;
    this.m_phaseLabel = evt.phaseLabel;
    this.m_objectiveText = evt.objectiveText;
    this.m_statusText = evt.statusText;
    this.m_qualiRequired = evt.qualiRequired;
    this.m_qualiCompleted = evt.qualiCompleted;
    this.m_qualiGridPos = evt.qualiGridPos;
    this.m_stageReadyCount = evt.stageReadyCount;
    this.m_stageTotalCount = evt.stageTotalCount;
    this.m_stageSpawning = evt.stageSpawning;
    this.m_playerStartReady = evt.playerStartReady;
    this.m_playerStartReason = evt.playerStartReason;
    this.m_finishLabel = evt.finishLabel;
    this.m_knockoutPhase = evt.knockoutPhase;
    this.m_lastEliminatedName = evt.lastEliminatedName;
    this.m_rivalName = evt.rivalAheadName;
  }

  public final func IsHudEnabled() -> Bool {
    return this.m_hudEnabled;
  }

  public final func IsRaceBusy() -> Bool {
    return this.m_preraceActive || this.m_qualiActive || this.m_raceCountdown || this.m_raceActive || this.m_knockoutActive;
  }

  public final func ShouldShowRaceOverlay() -> Bool {
    return this.IsRaceBusy();
  }

  public final func ShouldShowPhaseBlock() -> Bool {
    if this.m_preraceActive || this.m_qualiActive {
      return true;
    }
    if this.m_raceActive || this.m_knockoutActive {
      return NotEquals(this.m_phaseLabel, "") || NotEquals(this.m_objectiveText, "") || NotEquals(this.GetStatusText(), "");
    }
    return false;
  }

  public final func ShouldShowCountdown() -> Bool {
    return this.m_raceCountdown;
  }

  public final func ShouldShowRacePosition() -> Bool {
    return this.m_raceActive || this.m_knockoutActive;
  }

  public final func ShouldShowGridLights() -> Bool {
    if !this.m_raceCountdown {
      return false;
    }
    return Equals(this.m_startType, "grid") || Equals(this.m_startType, "sidebyside");
  }

  public final func ShouldShowGapText() -> Bool {
    return (this.m_raceActive || this.m_knockoutActive) && NotEquals(this.m_gapText, "");
  }

  public final func ShouldShowRivalCallout() -> Bool {
    return (this.m_raceActive || this.m_knockoutActive) && NotEquals(this.m_rivalName, "");
  }

  public final func ShouldShowStandings() -> Bool {
    return (this.m_raceActive || this.m_preraceActive || this.m_qualiActive) && NotEquals(this.m_standingsText, "");
  }

  public final func ShouldShowDistanceToFinish() -> Bool {
    return this.m_raceActive && this.m_distToFinish >= 0.0;
  }

  public final func ShouldShowKnockoutBanner() -> Bool {
    return this.m_knockoutActive;
  }

  public final func ShouldShowEliminationFlash() -> Bool {
    return this.m_knockoutActive && NotEquals(this.m_lastEliminatedName, "");
  }

  public final func GetCountdownDisplayText() -> String {
    if this.m_countdownValue <= 0 {
      return "GO!";
    }
    return ToString(this.m_countdownValue);
  }

  public final func GetRacePositionText() -> String {
    return "P" + ToString(this.m_racePosition) + "/" + ToString(this.m_raceFieldSize);
  }

  public final func GetRaceTimeText() -> String {
    let seconds: Int32 = Cast<Int32>(this.m_raceTime);
    let tenths: Int32 = Cast<Int32>((this.m_raceTime - Cast<Float>(seconds)) * 10.0);
    return ToString(seconds) + "." + ToString(tenths) + "s";
  }

  public final func GetQualifyingTimeText() -> String {
    return FloatToStringPrec(this.m_raceTime, 2) + "s";
  }

  public final func GetDistanceToFinishText() -> String {
    if this.m_distToFinish < 0.0 {
      return "";
    }
    if this.m_distToFinish > 1000.0 {
      return FloatToStringPrec(this.m_distToFinish / 1000.0, 1) + "km";
    }
    return ToString(Cast<Int32>(this.m_distToFinish)) + "m";
  }

  public final func GetRivalCalloutText() -> String {
    let arrow: String;
    if this.m_rivalIsAhead {
      arrow = "â–² ";
    } else {
      arrow = "â–¼ ";
    }
    return arrow + "RIVAL  " + this.m_rivalName;
  }

  public final func GetEliminationBannerText() -> String {
    let elimSec: Int32 = Cast<Int32>(this.m_eliminationCountdown);
    return "ELIM: " + ToString(elimSec) + "s  |  " + ToString(this.m_remainingDrivers) + " left";
  }

  public final func GetEliminationFlashText() -> String {
    return "ELIMINATED: " + this.m_lastEliminatedName;
  }

  public final func IsPreraceActive() -> Bool {
    return this.m_preraceActive;
  }

  public final func IsQualifyingActive() -> Bool {
    return this.m_qualiActive;
  }

  public final func IsRaceCountdownActive() -> Bool {
    return this.m_raceCountdown;
  }

  public final func IsRaceActive() -> Bool {
    return this.m_raceActive;
  }

  public final func IsKnockoutActive() -> Bool {
    return this.m_knockoutActive;
  }

  public final func GetTrackName() -> String {
    return this.m_trackName;
  }

  public final func GetRacePosition() -> Int32 {
    return this.m_racePosition;
  }

  public final func GetRaceFieldSize() -> Int32 {
    return this.m_raceFieldSize;
  }

  public final func GetRaceTime() -> Float {
    return this.m_raceTime;
  }

  public final func GetCountdownValue() -> Int32 {
    return this.m_countdownValue;
  }

  public final func GetCountdownPhase() -> Int32 {
    return this.m_countdownPhase;
  }

  public final func GetDistanceToFinish() -> Float {
    return this.m_distToFinish;
  }

  public final func GetGapText() -> String {
    return this.m_gapText;
  }

  public final func GetStandingsText() -> String {
    return this.m_standingsText;
  }

  public final func GetStartType() -> String {
    return this.m_startType;
  }

  public final func GetPhaseLabel() -> String {
    if this.m_preraceActive {
      return "RACE STAGED";
    }
    if this.m_qualiActive {
      return "QUALIFYING LAP";
    }
    return this.m_phaseLabel;
  }

  public final func GetObjectiveText() -> String {
    if this.m_preraceActive {
      if this.m_qualiRequired && !this.m_qualiCompleted {
        return "Drive to start and begin qualifying";
      }
      if this.m_stageSpawning {
        return "Stay near the line while rivals stage";
      }
      if this.m_stageTotalCount > 0 && this.m_stageReadyCount < this.m_stageTotalCount {
        if this.m_playerStartReady {
          return "Hold position for the launch";
        }
        return "Stage V on the start line";
      }
      if this.m_qualiRequired && this.m_qualiCompleted {
        return "Return to grid and prepare for launch";
      }
      if !this.m_playerStartReady {
        if NotEquals(this.m_playerStartReason, "") {
          return this.m_playerStartReason;
        }
        return "Stage V on the start line";
      }
      return "Hold position for the launch";
    }
    if this.m_qualiActive {
      return "Set your fastest run to the finish";
    }
    return this.m_objectiveText;
  }

  public final func GetStatusText() -> String {
    if this.m_preraceActive {
      if this.m_qualiRequired && !this.m_qualiCompleted {
        return "Qualifying required";
      }
      if this.m_stageSpawning {
        return "Staging rivals: " + ToString(this.m_stageReadyCount) + "/" + ToString(this.m_stageTotalCount) + " ready";
      }
      if this.m_stageTotalCount > 0 && this.m_stageReadyCount < this.m_stageTotalCount {
        return "Grid ready: " + ToString(this.m_stageReadyCount) + "/" + ToString(this.m_stageTotalCount);
      }
      if this.m_qualiRequired && this.m_qualiCompleted {
        return "Qualified P" + ToString(this.m_qualiGridPos);
      }
      if !this.m_playerStartReady {
        return "Waiting on V";
      }
      return "Race ready";
    }
    if this.m_qualiActive {
      return "Finish: " + this.m_finishLabel;
    }
    if this.m_raceActive || this.m_knockoutActive {
      if NotEquals(this.m_finishLabel, "") {
        if NotEquals(this.m_statusText, "") {
          return this.m_statusText + "  |  " + this.m_finishLabel;
        }
        return this.m_finishLabel;
      }
    }
    return this.m_statusText;
  }

  public final func GetRemainingDrivers() -> Int32 {
    return this.m_remainingDrivers;
  }

  public final func GetEliminationCountdown() -> Float {
    return this.m_eliminationCountdown;
  }

  public final func IsInDangerZone() -> Bool {
    return this.m_isInDangerZone;
  }

  public final func GetKnockoutPhase() -> String {
    return this.m_knockoutPhase;
  }

  public final func GetLastEliminatedName() -> String {
    return this.m_lastEliminatedName;
  }

  public final func GetRivalName() -> String {
    return this.m_rivalName;
  }

  public final func GetRivalIsAhead() -> Bool {
    return this.m_rivalIsAhead;
  }

  // ── Race mappin management ──────────────────────────────────

  public final func IsRaceMappin(id: NewMappinID) -> Bool {
    return Equals(id, this.m_startMappinID) || Equals(id, this.m_finishMappinID);
  }

  public final func IsStartRaceMappin(id: NewMappinID) -> Bool {
    return Equals(id, this.m_startMappinID);
  }

  public final func IsFinishRaceMappin(id: NewMappinID) -> Bool {
    return Equals(id, this.m_finishMappinID);
  }

  public final func PlaceRaceMappins(startPos: Vector4, finishPos: Vector4) -> Void {
    return;
  }

  public final func ClearRaceMappins() -> Void {
    return;
  }

  public final func TrackRaceMappin(slot: Int32) -> Void {
    return;
  }
}
