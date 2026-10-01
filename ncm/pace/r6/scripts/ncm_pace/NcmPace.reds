// NCM Pace -- drives a declared live Paddock race's cars on this client (doc 44 §15, Paddock phase 5).
//
// The `ncm_paddock` resource hands `ncm_pace.dll` a plan over loopback: the road line, the timing gates, and each
// car's engine entity with a speed ceiling per leg. This file is the hands. Every tick while a plan is listed it
// finds each car by its EntityID, reports where it is (the DLL times gates and moves its target along the line),
// and dispatches whatever the DLL says the car should hold:
//
//   mode 0  hold     the lights are not out; nothing is issued
//   mode 1  drive    the engine's own AIVehicleDriveToPointAutonomousCommand to the point -- sent the way NCM single
//                    player's issueAutonomousCommand sends it (ai_vehicles.lua, L234): a fresh command every time the
//                    DLL bumps `seq` (a new target, the launch release ending, SP's recommand cadence, a stall),
//                    with SP's fields -- min/max speed, forced start speed, target distance, clearTrafficOnPath, and useKinematic = false (0.2.0 drove kinematic and the cars parked).
//   mode 2  stop     cancel what is held (StopExecutingCommand when executing, else CancelCommand) and brake
//
// P-PACE-2 is the open question this file exists to answer: whether a native command on a car OPEN//77 created,
// with no platform driving job, is left alone by the platform. The DLL log says what happened (`reds:` lines).
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only -- nothing from OPEN//77, NCM Lua or any other mod;
//   * no plan, no work: a 2 Hz idle poll of four natives (banner and area included); 20 Hz only while a plan lists cars;
//   * the local player's game only; a remote body is never ours to drive from.
module NcmPace

public class NcmPaceTick extends DelayCallback {
  public let system: wref<NcmPaceSystem>;
  public let generation: Int32;

  public func Call() -> Void {
    let system: ref<NcmPaceSystem> = this.system;
    if IsDefined(system) {
      system.Tick(this.generation);
    }
  }
}

public class NcmPaceSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_generation: Int32;
  private let m_revision: Int32;
  private let m_seq: array<String>;
  private let m_commands: array<ref<AIVehicleCommand>>;
  private let m_vehicles: array<wref<VehicleObject>>;
  private let m_banner: wref<NcmPaceBanner>;
  private let m_areaRev: Int32;
  private let m_areaId: Uint64;
  private let m_dumped: Bool;
  private let m_ended: array<Bool>;
  private let m_probe: ref<AIVehicleCommand>;
  private let m_probeCar: Int32;
  private let m_probeDone: Bool;
  private let m_probeSaid: Bool;
  private let m_control: ref<AIVehicleCommand>;
  private let m_controlCar: Int32;
  private let m_controlSaid: Bool;
  private let m_probeLast: AICommandState;
  private let m_controlLast: AICommandState;
  private let m_testTicks: Int32;      // 0.7.6: while > 0 the two test cars get no race commands (20 s at 20 Hz)
  private let m_probeAtTicks: Int32;   // 0.7.9: ticks to the next engine spline probe (15 s at 20 Hz)
  private let m_probeRounds: Int32;    // 0.7.9: rounds left (60 = 15 minutes)
  private let m_splineAnswers: array<String>;

  public func SetBanner(banner: ref<NcmPaceBanner>) -> Void {
    this.m_banner = banner;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.m_player = player;
    this.m_generation += 1;
    this.m_probeAtTicks = 300;
    this.m_probeRounds = 60;
    // 0.6.0: the engine's driving profiles as this game build has them, once per game start (L244, IDEA-788)
    if !this.m_dumped {
      this.m_dumped = true;
      NcmPace_DumpDriving();
    }
    this.Schedule(0.5);
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.ReleaseAll("detach");
    this.m_generation += 1;
    this.m_player = null;
  }

  private func Schedule(delay: Float) -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let tick: ref<NcmPaceTick> = new NcmPaceTick();
    tick.system = this;
    tick.generation = this.m_generation;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(tick, delay, false);
  }

  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation {
      return;
    }
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let banner: ref<NcmPaceBanner> = this.m_banner;
    if IsDefined(banner) {
      banner.Apply(NcmPace_Banner());
    }
    this.ApplyArea(player.GetGame(), NcmPace_Area());
    let revision: Int32 = NcmPace_Revision();
    if revision != this.m_revision {
      this.ReleaseAll("revision " + ToString(this.m_revision) + " -> " + ToString(revision));
      this.m_revision = revision;
    }
    // 0.7.8: the engine spline probe, ~30 s after load, race or no race (counts real ticks: 0.5 s idle, 0.05 s racing)
    let count: Int32 = NcmPace_Count();
    if this.m_probeRounds > 0 {
      this.m_probeAtTicks -= count <= 0 ? 10 : 1;
      if this.m_probeAtTicks <= 0 {
        this.m_probeAtTicks = 300;
        this.m_probeRounds -= 1;
        NcmPace_ProbeSplines(player.GetGame(), player, this.m_splineAnswers);
      }
    }
    if count <= 0 {
      this.Schedule(0.5);
      return;
    }
    while ArraySize(this.m_seq) < count {
      ArrayPush(this.m_seq, "");
      ArrayPush(this.m_commands, null);
      ArrayPush(this.m_vehicles, null);
      ArrayPush(this.m_ended, false);
    }
    let game: GameInstance = player.GetGame();
    let i: Int32 = 0;
    while i < count {
      let vehicle: ref<VehicleObject> = GameInstance.FindEntityByID(game, NcmPace_Entity(i)) as VehicleObject;
      if IsDefined(vehicle) {
        let at: Vector4 = vehicle.GetWorldPosition();
        this.Apply(i, vehicle, NcmPace_Step(i, at.X, at.Y, at.Z));
        this.ReportEnd(i, vehicle);
      }
      i += 1;
    }
    if this.m_testTicks > 0 {
      this.m_testTicks -= 1;
      if this.m_testTicks == 0 {
        NcmPace_Log("probe/control: test window over");
      }
    }
    this.Schedule(0.05);
  }

  private func Apply(i: Int32, vehicle: ref<VehicleObject>, command: String) -> Void {
    let f: array<String> = StrSplit(command, "|");
    if ArraySize(f) != 10 {
      return;
    }
    if Equals(f[0], this.m_seq[i]) {
      return;
    }
    if this.m_testTicks > 0 && ((IsDefined(this.m_probe) && i == this.m_probeCar) || (IsDefined(this.m_control) && i == this.m_controlCar)) {
      return;                          // a test car is left alone with its test command (0.7.6)
    }
    this.m_seq[i] = f[0];
    let mode: Int32 = StringToInt(f[1]);
    let agent: ref<AIVehicleAgent> = vehicle.GetAIComponent();
    if !IsDefined(agent) {
      NcmPace_Log("car " + ToString(i) + ": no AI component");
      return;
    }
    if mode == 2 {
      this.Release(i, vehicle, agent);
      vehicle.ForceBrakesUntilStoppedOrFor(4.0);
      return;
    }
    if mode == 3 {
      // 0.7.0 (L246): the engine's own racer on this leg's race spline -- the vehicle's drivingParamsRace profile, no
      // rubber banding, joining the spline wherever the car is. Whatever it held before is released first.
      this.Release(i, vehicle, agent);
      let race: ref<AIVehicleRacingCommand> = new AIVehicleRacingCommand();
      race.splineRef = NcmPace_Spline(i);
      race.startFromClosest = true;
      race.reverseSpline = false;
      race.driveBackwards = false;
      race.rubberBandingBool = false;
      race.secureTimeOut = 60.0;
      race.needDriver = false;
      race.useKinematic = false;
      if agent.SendCommand(race) {
        this.m_commands[i] = race;
        this.m_ended[i] = false;
        this.m_vehicles[i] = vehicle;
        NcmPace_Log("car " + ToString(i) + ": racing leg " + f[2]);
      } else {
        NcmPace_Log("car " + ToString(i) + ": racing command refused on leg " + f[2]);
      }
      return;
    }
    if mode != 1 {
      return;
    }
    let drive: ref<AIVehicleDriveToPointAutonomousCommand> = new AIVehicleDriveToPointAutonomousCommand();
    drive.targetPosition = new Vector3(StringToFloat(f[2]), StringToFloat(f[3]), StringToFloat(f[4]));
    drive.maxSpeed = StringToFloat(f[5]);
    drive.minSpeed = StringToFloat(f[6]);
    drive.forcedStartSpeed = StringToFloat(f[7]);
    drive.minimumDistanceToTarget = StringToFloat(f[8]);
    // f[9] is SP's boostDrivingStats; the drive-to-point command has no such field (SP set it inside a pcall, a
    // silent no-op there too), so it is carried on the wire and not applied.
    drive.clearTrafficOnPath = true;
    drive.driveDownTheRoadIndefinitely = false;
    drive.useKinematic = false;
    drive.needDriver = false;
    let held: ref<AIVehicleCommand> = this.m_commands[i];
    if agent.SendCommand(drive) {
      this.m_commands[i] = drive;
      this.m_vehicles[i] = vehicle;
      if !IsDefined(held) {
        NcmPace_Log("car " + ToString(i) + ": driving (max " + f[5] + ", min " + f[6] + ", forced " + f[7] + " m/s)");
      }
    } else {
      NcmPace_Log("car " + ToString(i) + ": SendCommand refused");
    }
  }

  // The traffic null area over a staging grid (0.3.0, KB-219): the signature the plugin read from the game's own RTTI
  // -- gameCommunitySystem.EnableDynamicCrowdNullArea(areaLocalBBox: Box, areaLocalToWorld: WorldTransform, savable:
  // Bool, duration: Float) -> Uint64. Not savable; the engine expires it by itself after `duration`, and a new plan
  // or a clear takes it down sooner.
  private func ApplyArea(game: GameInstance, feed: String) -> Void {
    let f: array<String> = StrSplit(feed, "|");
    if ArraySize(f) != 8 {
      return;
    }
    let rev: Int32 = StringToInt(f[0]);
    if rev == this.m_areaRev {
      return;
    }
    this.m_areaRev = rev;
    let community: ref<CommunitySystem> = GameInstance.GetCommunitySystem(game);
    if !IsDefined(community) {
      NcmPace_Log("area: no community system");
      return;
    }
    if this.m_areaId != 0ul {
      community.DisableCrowdNullArea(this.m_areaId);
      this.m_areaId = 0ul;
    }
    if !Equals(f[1], "1") {
      NcmPace_Log("area: cleared");
      return;
    }
    let half: Float = StringToFloat(f[5]);
    let halfZ: Float = StringToFloat(f[6]);
    let box: Box;
    box.Min = new Vector4(-half, -half, -halfZ, 1.0);
    box.Max = new Vector4(half, half, halfZ, 1.0);
    let xf: WorldTransform;
    WorldTransform.SetPosition(xf, new Vector4(StringToFloat(f[2]), StringToFloat(f[3]), StringToFloat(f[4]), 1.0));
    this.m_areaId = community.EnableDynamicCrowdNullArea(box, xf, false, Cast<Float>(StringToInt(f[7])));
    NcmPace_Log("area: null area " + ToString(this.m_areaId) + " over " + f[2] + ", " + f[3] + " (+/-" + f[5] + " m) for " + f[7] + " s");
  }

  private func Release(i: Int32, vehicle: ref<VehicleObject>, agent: ref<AIVehicleAgent>) -> Void {
    let held: ref<AIVehicleCommand> = this.m_commands[i];
    if !IsDefined(held) {
      return;
    }
    if Equals(agent.GetCommandState(held), AICommandState.Executing) {
      agent.StopExecutingCommand(held, true);
    } else {
      agent.CancelCommand(held);
    }
    this.m_commands[i] = null;
  }

  // 0.7.0: a racing command the engine ends by itself -- a spline ref it could not resolve fails at once -- is said
  // out loud, once per command, so a bad race spline never looks like a car that simply sat still.
  private func ReportEnd(i: Int32, vehicle: ref<VehicleObject>) -> Void {
    let held: ref<AIVehicleCommand> = this.m_commands[i];
    if !IsDefined(held) || this.m_ended[i] {
      return;
    }
    let agent: ref<AIVehicleAgent> = vehicle.GetAIComponent();
    if !IsDefined(agent) {
      return;
    }
    // 0.7.3 DIAGNOSTIC, once per game: does the engine find the race spline at all? The racing command fails at once
    // on it; the plain spline command on the SAME ref tells a ref that does not resolve (it fails too) from a racer
    // that wants something more (it executes). Logged only -- it never races.
    if IsDefined(this.m_probe) && this.m_probeCar == i && this.m_testTicks > 0 {
      let ps: AICommandState = agent.GetCommandState(this.m_probe);
      if !Equals(ps, this.m_probeLast) {
        this.m_probeLast = ps;
        NcmPace_Log("probe: OUR spline (OnSpline) -> " + ToString(ps) + " at " + IntToString(400 - this.m_testTicks) + " ticks");
      }
    }
    if IsDefined(this.m_control) && this.m_controlCar == i && this.m_testTicks > 0 {
      let cs: AICommandState = agent.GetCommandState(this.m_control);
      if !Equals(cs, this.m_controlLast) {
        this.m_controlLast = cs;
        NcmPace_Log("control: VANILLA spline (OnSpline) -> " + ToString(cs) + " at " + IntToString(400 - this.m_testTicks) + " ticks");
      }
    }
    let st: AICommandState = agent.GetCommandState(held);
    if Equals(st, AICommandState.Failure) || Equals(st, AICommandState.Success) {
      this.m_ended[i] = true;
      NcmPace_Log("car " + ToString(i) + ": command ended " + (Equals(st, AICommandState.Failure) ? "FAILURE" : "success"));
      if Equals(st, AICommandState.Failure) && !this.m_probeDone && IsDefined(held as AIVehicleRacingCommand) {
        this.m_probeDone = true;
        let probe: ref<AIVehicleOnSplineCommand> = new AIVehicleOnSplineCommand();
        probe.splineRef = NcmPace_Spline(i);
        probe.startFromClosest = true;
        probe.stopAtPathEnd = true;
        probe.needDriver = false;
        probe.useKinematic = false;
        probe.secureTimeOut = 60.0;
        this.m_probe = probe;
        this.m_probeCar = i;
        this.m_testTicks = 400;
        this.m_probeLast = AICommandState.NotExecuting;
        this.m_controlLast = AICommandState.NotExecuting;
        NcmPace_Log("probe: sending AIVehicleOnSplineCommand to car " + ToString(i) + ": " + (agent.SendCommand(probe) ? "accepted" : "REFUSED"));
        // the CONTROL (0.7.5): a vanilla open-world speed spline (exterior_-1_-1_0_6), by its full path through Pace's
        // hash, on a second car. If it executes, the hash is right and our sectors are what the engine is not finding.
        let other: Int32 = i == 0 ? 1 : 0;
        let otherVehicle: ref<VehicleObject> = this.m_vehicles[other];
        if IsDefined(otherVehicle) {
          let otherAgent: ref<AIVehicleAgent> = otherVehicle.GetAIComponent();
          if IsDefined(otherAgent) {
            let control: ref<AIVehicleOnSplineCommand> = new AIVehicleOnSplineCommand();
            control.splineRef = NcmPace_NodeRef("$/03_night_city/#c_city_center/corpo_plaza/loc_sq024_citycenter_racetrack_prefabK3D7W4Y/loc_sq024_citycenter_racetrack_openworld_prefabPMPERBY/#test_nc_sq024_city_center");
            control.startFromClosest = true;
            control.stopAtPathEnd = true;
            control.needDriver = false;
            control.useKinematic = false;
            control.secureTimeOut = 60.0;
            this.m_control = control;
            this.m_controlCar = other;
            NcmPace_Log("control: sending the vanilla spline to car " + ToString(other) + ": " + (otherAgent.SendCommand(control) ? "accepted" : "REFUSED"));
          }
        }
      }
    }
  }

  // A new plan, an ended plan or a detach: nothing held from before may keep driving.
  private func ReleaseAll(why: String) -> Void {
    let released: Int32 = 0;
    let i: Int32 = 0;
    while i < ArraySize(this.m_commands) {
      let vehicle: ref<VehicleObject> = this.m_vehicles[i];
      if IsDefined(vehicle) && IsDefined(this.m_commands[i]) {
        let agent: ref<AIVehicleAgent> = vehicle.GetAIComponent();
        if IsDefined(agent) {
          this.Release(i, vehicle, agent);
          vehicle.ForceBrakesUntilStoppedOrFor(4.0);
          released += 1;
        }
      }
      i += 1;
    }
    ArrayClear(this.m_seq);
    ArrayClear(this.m_commands);
    ArrayClear(this.m_vehicles);
    ArrayClear(this.m_ended);
    if released > 0 {
      NcmPace_Log("released " + ToString(released) + " car(s): " + why);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The race-start warning (0.2.0): a native HUD banner in the vanilla crosshair container -- not a WebUI surface, so it
// costs no WebUI page. The server shows it to players near a staging grid ("WARNING: IMPENDING RACE START / CLEAR THE
// AREA") with a countdown; this file only draws what `NcmPace_Banner()` says: "rev|visible|title|detail|secondsLeft".

public class NcmPaceBanner extends IScriptable {
  private let root: ref<inkCanvas>;
  private let band: ref<inkRectangle>;
  private let edge: ref<inkRectangle>;
  private let title: ref<inkText>;
  private let detail: ref<inkText>;

  public func Build(parent: ref<inkCompoundWidget>) -> Void {
    if !IsDefined(parent) {
      NcmPace_Log("banner host has no compound root; nothing drawn");
      return;
    }
    this.root = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.root.SetName(n"NcmPaceBanner");
    this.root.SetAnchor(inkEAnchor.TopCenter);
    this.root.SetAnchorPoint(new Vector2(0.5, 0.0));
    this.root.SetMargin(0.0, 150.0, 0.0, 0.0);
    this.root.SetSize(1500.0, 190.0);
    this.root.SetVisible(false);
    this.band = this.root.AddChild(n"inkRectangleWidget") as inkRectangle;
    this.band.SetName(n"band");
    this.band.SetSize(1500.0, 190.0);
    this.band.SetTintColor(new HDRColor(0.05, 0.02, 0.02, 1.0));
    this.band.SetOpacity(0.78);
    this.edge = this.root.AddChild(n"inkRectangleWidget") as inkRectangle;
    this.edge.SetName(n"edge");
    this.edge.SetSize(1500.0, 8.0);
    this.edge.SetTintColor(new HDRColor(1.0, 0.72, 0.2, 1.0));
    this.title = this.Text(n"title", 62, 20.0, 1500.0, 90.0);
    this.title.SetTintColor(new HDRColor(1.0, 0.72, 0.2, 1.0));
    this.detail = this.Text(n"detail", 38, 110.0, 1500.0, 60.0);
    this.detail.SetTintColor(new HDRColor(0.94, 0.96, 0.98, 1.0));
  }

  private func Text(name: CName, size: Int32, y: Float, w: Float, h: Float) -> ref<inkText> {
    let label: ref<inkText> = this.root.AddChild(n"inkTextWidget") as inkText;
    label.SetName(name);
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    label.SetFontSize(size);
    label.SetFitToContent(false);
    label.SetMargin(0.0, y, 0.0, 0.0);
    label.SetSize(w, h);
    label.SetHorizontalAlignment(textHorizontalAlignment.Center);
    label.SetVerticalAlignment(textVerticalAlignment.Center);
    return label;
  }

  public func Apply(feed: String) -> Void {
    if !IsDefined(this.root) {
      return;
    }
    let f: array<String> = StrSplit(feed, "|");
    if ArraySize(f) != 5 || !Equals(f[1], "1") {
      this.root.SetVisible(false);
      return;
    }
    let title: String = Equals(f[2], "~") ? "" : f[2];
    let detail: String = Equals(f[3], "~") ? "" : f[3];
    let left: Int32 = StringToInt(f[4]);
    if left > 0 {
      detail = detail + "  ·  " + ToString(left / 60) + ":" + (left % 60 < 10 ? "0" : "") + ToString(left % 60);
    }
    this.title.SetText(title);
    this.detail.SetText(detail);
    this.root.SetVisible(true);
  }
}

@addField(gameuiCrosshairContainerController)
private let ncmPaceBanner: ref<NcmPaceBanner>;

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmPaceSystem>;
  if !IsDefined(this.ncmPaceBanner) && IsDefined(owner) {
    this.ncmPaceBanner = new NcmPaceBanner();
    this.ncmPaceBanner.Build(this.GetRootCompoundWidget());
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmPace.NcmPaceSystem") as NcmPaceSystem;
    if IsDefined(system) {
      system.SetBanner(this.ncmPaceBanner);
      NcmPace_Log("banner attached to gameuiCrosshairContainerController");
    }
  }
  return result;
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnUninitialize() -> Bool {
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmPaceSystem>;
  if IsDefined(owner) {
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmPace.NcmPaceSystem") as NcmPaceSystem;
    if IsDefined(system) {
      system.SetBanner(null);
    }
  }
  this.ncmPaceBanner = null;
  return wrappedMethod();
}
