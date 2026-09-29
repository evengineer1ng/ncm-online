// NCM Pace -- drives a declared live Paddock race's cars on this client (doc 44 §15, Paddock phase 5).
//
// The `ncm_paddock` resource hands `ncm_pace.dll` a plan over loopback: the road line, the timing gates, and each
// car's engine entity with a speed ceiling per leg. This file is the hands. Every tick while a plan is listed it
// finds each car by its EntityID, reports where it is (the DLL times gates and moves its target along the line),
// and dispatches whatever the DLL says the car should hold:
//
//   mode 0  hold     the lights are not out; nothing is issued
//   mode 1  drive    the engine's own AIVehicleDriveToPointAutonomousCommand to the point, at up to the ceiling --
//                    the same command, fields and dispatch OPEN//77 itself uses (Open77VehicleDriving.reds), minus
//                    its 55 m/s server cap. A new target on a held command is an update, not a new command.
//   mode 2  stop     cancel what is held (StopExecutingCommand when executing, else CancelCommand) and brake
//
// P-PACE-2 is the open question this file exists to answer: whether a native command on a car OPEN//77 created,
// with no platform driving job, is left alone by the platform. The DLL log says what happened (`reds:` lines).
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only -- nothing from OPEN//77, NCM Lua or any other mod;
//   * no plan, no work: a 2 Hz idle poll of two integer natives; 20 Hz only while a plan lists cars;
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

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.m_player = player;
    this.m_generation += 1;
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
    let revision: Int32 = NcmPace_Revision();
    if revision != this.m_revision {
      this.ReleaseAll("revision " + ToString(this.m_revision) + " -> " + ToString(revision));
      this.m_revision = revision;
    }
    let count: Int32 = NcmPace_Count();
    if count <= 0 {
      this.Schedule(0.5);
      return;
    }
    while ArraySize(this.m_seq) < count {
      ArrayPush(this.m_seq, "");
      ArrayPush(this.m_commands, null);
      ArrayPush(this.m_vehicles, null);
    }
    let game: GameInstance = player.GetGame();
    let i: Int32 = 0;
    while i < count {
      let vehicle: ref<VehicleObject> = GameInstance.FindEntityByID(game, NcmPace_Entity(i)) as VehicleObject;
      if IsDefined(vehicle) {
        let at: Vector4 = vehicle.GetWorldPosition();
        this.Apply(i, vehicle, NcmPace_Step(i, at.X, at.Y, at.Z));
      }
      i += 1;
    }
    this.Schedule(0.05);
  }

  private func Apply(i: Int32, vehicle: ref<VehicleObject>, command: String) -> Void {
    let f: array<String> = StrSplit(command, "|");
    if ArraySize(f) != 6 {
      return;
    }
    if Equals(f[0], this.m_seq[i]) {
      return;
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
    if mode != 1 {
      return;
    }
    let update: ref<DriveToPointAutonomousUpdate> = new DriveToPointAutonomousUpdate();
    update.targetPosition = new Vector4(StringToFloat(f[2]), StringToFloat(f[3]), StringToFloat(f[4]), 1.0);
    update.maxSpeed = StringToFloat(f[5]);
    update.minSpeed = 0.0;
    update.clearTrafficOnPath = true;
    update.minimumDistanceToTarget = 6.0;
    update.driveDownTheRoadIndefinitely = false;
    let held: ref<AIVehicleCommand> = this.m_commands[i];
    if IsDefined(held) && Equals(agent.GetCommandState(held), AICommandState.Executing) {
      agent.SetDriveToPointAutonomousUpdate(update);
      return;
    }
    let drive: ref<AIVehicleDriveToPointAutonomousCommand> = update.CreateCmd();
    drive.needDriver = false;
    drive.useKinematic = true;
    drive.forcedStartSpeed = -1.0;
    if agent.SendCommand(drive) {
      this.m_commands[i] = drive;
      this.m_vehicles[i] = vehicle;
      if !IsDefined(held) {
        NcmPace_Log("car " + ToString(i) + ": driving (max " + f[5] + " m/s)");
      }
    } else {
      NcmPace_Log("car " + ToString(i) + ": SendCommand refused");
    }
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
    if released > 0 {
      NcmPace_Log("released " + ToString(released) + " car(s): " + why);
    }
  }
}
