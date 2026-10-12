// NCM Snowglobe -- SEAM-1 (L317): can the game move the occupied car in mid-air, and keep its velocity and its driver?
//
// While the local player drives, this keeps the car's position each frame and derives its velocity from the frames
// themselves (no engine field is trusted). When `ncm_snowglobe.dll` reports a press of the seam key, and the car is
// above `minZ`, it moves the car by the configured offset with the game's own TeleportationFacility -- the same call
// NCM's single-player racing uses for grid starts -- keeping its orientation. It then watches `watchFrames` frames
// and logs one verdict: where the car landed against where it was sent, velocity before against after, and whether
// the player is still in the driver's seat. Nothing else is touched.
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only;
//   * the local player's car only;
//   * no work out of a car beyond a 2 Hz check.
module NcmSnowglobe

public class NcmSnowglobeTick extends DelayCallback {
  public let system: wref<NcmSnowglobeSystem>;
  public let generation: Int32;
  public func Call() -> Void {
    let system: ref<NcmSnowglobeSystem> = this.system;
    if IsDefined(system) {
      system.Tick(this.generation);
    }
  }
}

public class NcmSnowglobeSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_generation: Int32;
  private let m_inCar: Bool;
  // the previous frame, for a velocity from positions
  private let m_havePrev: Bool;
  private let m_prev: Vector4;
  private let m_prevT: Float;
  private let m_vel: Vector4;
  private let m_haveVel: Bool;
  // the move under watch
  private let m_watching: Int32;          // frames left to watch; 0 = idle
  private let m_watchTotal: Int32;
  private let m_moves: Int32;
  private let m_vehicle: wref<VehicleObject>;
  private let m_from: Vector4;
  private let m_sent: Vector4;
  private let m_movedAt: Float;
  private let m_velBefore: Vector4;
  private let m_velAfterSum: Vector4;
  private let m_velAfterN: Int32;
  private let m_seatLost: Int32;
  // SEAM-1c: a move this client did not make (the server's setTransform), and the velocity to give back
  private let m_awaiting: Bool;
  private let m_awaitFrames: Int32;
  private let m_jumps: Int32;
  private let m_saved: Vector4;
  private let m_kickWatch: Int32;
  private let m_kickSeq: Int32;
  private let m_kickAt: Vector4;
  // Snowglobe 0: the altitude the game is no longer showing (server/snowglobe.lua's per-car offset), learned from the
  // server's own vertical rebases -- no new transport. Universe altitude = game z + offset.
  private let m_offset: Float;
  // the altimeter (owner, 2026-10-05: "need an altitude meter as well")
  private let m_hud: ref<NcmSnowglobeAltimeter>;

  public func SetHud(hud: ref<NcmSnowglobeAltimeter>) -> Void {
    this.m_hud = hud;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.m_player = player;
    this.m_generation += 1;
    NcmSnowglobe_Log("attached");
    this.Schedule(0.5);
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.m_generation += 1;
    this.m_player = null;
  }

  private func Schedule(delay: Float) -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let tick: ref<NcmSnowglobeTick> = new NcmSnowglobeTick();
    tick.system = this;
    tick.generation = this.m_generation;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(tick, delay, false);
  }

  private func V(v: Vector4) -> String {
    return "(" + FloatToStringPrec(v.X, 2) + ", " + FloatToStringPrec(v.Y, 2) + ", " + FloatToStringPrec(v.Z, 2) + ")";
  }

  private func Len(v: Vector4) -> Float {
    return SqrtF(v.X * v.X + v.Y * v.Y + v.Z * v.Z);
  }

  private func Sub(a: Vector4, b: Vector4) -> Vector4 {
    return new Vector4(a.X - b.X, a.Y - b.Y, a.Z - b.Z, 1.0);
  }

  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation {
      return;
    }
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let game: GameInstance = player.GetGame();
    let vehicle: ref<VehicleObject> = player.GetMountedVehicle() as VehicleObject;
    if this.m_watching > 0 {
      this.Watch(player, vehicle);
    }
    if !IsDefined(vehicle) || !VehicleComponent.IsDriver(game, player) {
      if IsDefined(this.m_hud) {
        this.m_hud.Hide();
      }
      if this.m_inCar {
        this.m_inCar = false;
        this.m_havePrev = false;
        this.m_haveVel = false;
        NcmSnowglobe_Log("out of the driver's seat");
      }
      NcmSnowglobe_Poll();   // a press out of a car is dropped, not saved for later
      if this.m_watching > 0 {
        this.Schedule(0.0);
      } else {
        this.Schedule(0.5);
      }
      return;
    }
    this.m_inCar = true;

    let pos: Vector4 = vehicle.GetWorldPosition();
    let t: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
    // SEAM-1c: a jump of more than 200 m in one frame that this file did not ask for is the server moving the car.
    // Remember the velocity from before it; the move erases it (§SG4: 83.6 -> 0 m/s).
    if this.m_havePrev && this.m_watching == 0 && this.Len(this.Sub(pos, this.m_prev)) > 200.0 {
      this.m_jumps += 1;
      this.m_awaiting = true;
      this.m_awaitFrames = 0;
      this.m_saved = this.m_vel;
      // Snowglobe 0 (owner, 2026-10-05): speed is NOT carried through a move -- "we control the perspective of speed".
      // The SEAM-1c kick is no longer sent. A VERTICAL server jump is a snowglobe rebase: it moves the offset.
      let j: Vector4 = this.Sub(pos, this.m_prev);
      let flat: Float = SqrtF(j.X * j.X + j.Y * j.Y);
      if AbsF(j.Z) > 1000.0 && flat < 50.0 {
        this.m_offset -= j.Z;
        if this.m_offset < 1.0 {
          this.m_offset = 0.0;
        }
      }
      NcmSnowglobe_Log("snowglobe jump #" + IntToString(this.m_jumps) + ": the server moved the car " + this.V(j)
        + " | offset now " + FloatToStringPrec(this.m_offset, 0) + " m | universe altitude " + FloatToStringPrec(pos.Z + this.m_offset, 0)
        + " m | speed before " + FloatToStringPrec(this.Len(this.m_saved), 2) + " m/s (not carried)");
      this.m_prev = pos;
      this.m_prevT = t;
      this.Schedule(0.0);
      return;
    }
    let step: Float = 0.0;
    if this.m_havePrev {
      step = this.Len(this.Sub(pos, this.m_prev));
    }
    if this.m_havePrev && t > this.m_prevT {
      let dt: Float = t - this.m_prevT;
      this.m_vel = new Vector4((pos.X - this.m_prev.X) / dt, (pos.Y - this.m_prev.Y) / dt, (pos.Z - this.m_prev.Z) / dt, 0.0);
      this.m_haveVel = true;
      if this.m_watching > 0 && this.m_watching <= this.m_watchTotal - 3 {
        // the jump frame and the two after it are skipped: the delta across the move is the offset, not a velocity
        this.m_velAfterSum = new Vector4(this.m_velAfterSum.X + this.m_vel.X, this.m_velAfterSum.Y + this.m_vel.Y,
                                         this.m_velAfterSum.Z + this.m_vel.Z, 0.0);
        this.m_velAfterN += 1;
      }
    }
    this.m_prev = pos;
    this.m_prevT = t;
    this.m_havePrev = true;

    if this.m_awaiting {
      this.m_awaitFrames += 1;
      if step > 0.005 && this.m_awaitFrames > 3 {
        // moving again: from here the log follows the velocity, to see Carrier's kick land (or not)
        this.m_kickAt = this.m_vel;
        this.m_awaiting = false;
        this.m_kickWatch = 600;
        NcmSnowglobe_Log("SEAM-1c moving again after " + IntToString(this.m_awaitFrames) + " frame(s) frozen: velocity now " + this.V(this.m_vel));
      } else {
        if this.m_awaitFrames > 2400 {
          this.m_awaiting = false;
          NcmSnowglobe_Log("SEAM-1c gave up: the car never moved again after the jump (2400 frames)");
        }
      }
    } else {
      if this.m_kickWatch > 0 {
        let k: Int32 = 601 - this.m_kickWatch;
        if k == 1 || k == 5 || k == 10 || k == 30 || k == 60 || k == 120 || k == 240 || k == 600 {
          NcmSnowglobe_Log("  kick frame " + IntToString(k) + ": v " + this.V(this.m_vel) + " = " + FloatToStringPrec(this.Len(this.m_vel), 2) + " m/s");
        }
        if k == 240 {
          let before: Float = this.Len(this.m_saved);
          let kept: Float = 0.0;
          if before > 0.5 {
            kept = this.Len(this.m_vel) / before;
          }
          NcmSnowglobe_Log("SEAM-1c RESULT jump #" + IntToString(this.m_jumps) + ": before the jump " + this.V(this.m_saved) + " | moving again at "
            + this.V(this.m_kickAt) + " | 240 frames after " + this.V(this.m_vel) + " | speed kept x" + FloatToStringPrec(kept, 2));
        }
        this.m_kickWatch -= 1;
      }
    }

    if IsDefined(this.m_hud) {
      this.m_hud.Show(pos.Z, this.m_vel.Z, this.m_offset);
    }

    if NcmSnowglobe_Poll() > 0 && this.m_watching == 0 {
      this.Move(game, vehicle, pos, t);
    }
    this.Schedule(0.0);
  }

  private func Move(game: GameInstance, vehicle: ref<VehicleObject>, pos: Vector4, t: Float) -> Void {
    if pos.Z < NcmSnowglobe_MinZ() {
      NcmSnowglobe_Log("SEAM-1 refused: car at z=" + FloatToStringPrec(pos.Z, 1) + ", below minZ " + FloatToStringPrec(NcmSnowglobe_MinZ(), 0));
      return;
    }
    if !this.m_haveVel {
      NcmSnowglobe_Log("SEAM-1 refused: no velocity measured yet (one more frame)");
      return;
    }
    let target: Vector4 = new Vector4(pos.X + NcmSnowglobe_Offset(0), pos.Y + NcmSnowglobe_Offset(1), pos.Z + NcmSnowglobe_Offset(2), 1.0);
    let angles: EulerAngles = Quaternion.ToEulerAngles(vehicle.GetWorldOrientation());
    this.m_moves += 1;
    this.m_vehicle = vehicle;
    this.m_from = pos;
    this.m_sent = target;
    this.m_movedAt = t;
    this.m_velBefore = this.m_vel;
    this.m_velAfterSum = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_velAfterN = 0;
    this.m_seatLost = 0;
    this.m_watchTotal = NcmSnowglobe_WatchFrames();
    this.m_watching = this.m_watchTotal;
    NcmSnowglobe_Log("SEAM-1 move #" + IntToString(this.m_moves) + ": from " + this.V(pos) + " to " + this.V(target)
      + " | velocity " + this.V(this.m_vel) + " = " + FloatToStringPrec(this.Len(this.m_vel), 2) + " m/s | yaw "
      + FloatToStringPrec(angles.Yaw, 1));
    GameInstance.GetTeleportationFacility(game).Teleport(vehicle, target, angles);
  }

  private func Watch(player: ref<PlayerPuppet>, vehicle: ref<VehicleObject>) -> Void {
    let moved: ref<VehicleObject> = this.m_vehicle;
    let seated: Bool = IsDefined(vehicle) && IsDefined(moved) && vehicle == moved && VehicleComponent.IsDriver(player.GetGame(), player);
    if !seated {
      this.m_seatLost += 1;
    }
    let frame: Int32 = this.m_watchTotal - this.m_watching + 1;
    if IsDefined(moved) && (frame == 1 || frame == 2 || frame == 3 || frame == 5 || frame == 10 || frame == 30 || frame == 60) {
      let p: Vector4 = moved.GetWorldPosition();
      NcmSnowglobe_Log("  frame " + IntToString(frame) + ": at " + this.V(p) + " | from the sent point " + this.V(this.Sub(p, this.m_sent))
        + " | seated=" + ToString(seated) + " | v " + this.V(this.m_vel));
    }
    this.m_watching -= 1;
    if this.m_watching > 0 {
      return;
    }
    // the verdict
    let landed: Vector4 = this.m_sent;
    if IsDefined(moved) {
      landed = moved.GetWorldPosition();
    }
    let after: Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0);
    if this.m_velAfterN > 0 {
      let n: Float = Cast<Float>(this.m_velAfterN);
      after = new Vector4(this.m_velAfterSum.X / n, this.m_velAfterSum.Y / n, this.m_velAfterSum.Z / n, 0.0);
    }
    let dv: Vector4 = this.Sub(after, this.m_velBefore);
    let before: Float = this.Len(this.m_velBefore);
    let kept: Float = 0.0;
    if before > 0.5 {
      kept = this.Len(after) / before;
    }
    NcmSnowglobe_Log("SEAM-1 RESULT move #" + IntToString(this.m_moves) + ": velocity before " + this.V(this.m_velBefore)
      + " after " + this.V(after) + " (mean of " + IntToString(this.m_velAfterN) + " frames) | |dv| "
      + FloatToStringPrec(this.Len(dv), 2) + " m/s, speed kept x" + FloatToStringPrec(kept, 2)
      + " | seat lost in " + IntToString(this.m_seatLost) + " of " + IntToString(this.m_watchTotal) + " frames"
      + " | now at " + this.V(landed));
  }
}

// ---------------------------------------------------------------------------------------------------- the altimeter
// Height, climb rate and what is left to Night City's hard ceiling (z = 16,384 m, §AX4). Drawn on the crosshair
// container beside NCM Gearbox's indicator (same 3840x2160 canvas), and only when it matters: above 250 m, or climbing
// or falling faster than 8 m/s. On the ground and in a race it stays out of the way.
public class NcmSnowglobeAltimeter {
  private let root: ref<inkCanvas>;
  private let label: ref<inkText>;
  private let alt: ref<inkText>;
  private let rate: ref<inkText>;
  private let ceiling: ref<inkText>;

  public func Build(parent: ref<inkCompoundWidget>) -> Void {
    if !IsDefined(parent) {
      NcmSnowglobe_Log("altimeter: no compound root");
      return;
    }
    this.root = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.root.SetName(n"NcmSnowglobeAltimeter");
    this.root.SetAnchor(inkEAnchor.TopLeft);
    this.root.SetMargin(2150.0, 790.0, 0.0, 0.0);
    this.root.SetSize(520.0, 215.0);
    this.label = this.Text(n"label", 24, 4.0, 0.0, 400.0, 30.0);
    this.label.SetText("ALTITUDE");
    this.label.SetTintColor(new HDRColor(0.6, 0.85, 1.0, 1.0));
    this.alt = this.Text(n"alt", 84, 0.0, 30.0, 520.0, 100.0);
    this.rate = this.Text(n"rate", 34, 4.0, 128.0, 500.0, 40.0);
    this.ceiling = this.Text(n"ceiling", 20, 4.0, 172.0, 500.0, 28.0);
    this.root.SetVisible(false);
    NcmSnowglobe_Log("altimeter: attached");
  }

  private func Text(name: CName, size: Int32, x: Float, y: Float, w: Float, h: Float) -> ref<inkText> {
    let t: ref<inkText> = this.root.AddChild(n"inkTextWidget") as inkText;
    t.SetName(name);
    t.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    t.SetFontSize(size);
    t.SetFitToContent(false);
    t.SetMargin(x, y, 0.0, 0.0);
    t.SetSize(w, h);
    t.SetHorizontalAlignment(textHorizontalAlignment.Left);
    t.SetVerticalAlignment(textVerticalAlignment.Center);
    t.SetTintColor(new HDRColor(0.95, 0.97, 1.0, 1.0));
    return t;
  }

  public func Show(z: Float, vz: Float, offset: Float) -> Void {
    if !IsDefined(this.root) {
      return;
    }
    let u: Float = z + offset;
    if u < 250.0 && AbsF(vz) < 8.0 {
      this.root.SetVisible(false);
      return;
    }
    this.alt.SetText(IntToString(Cast<Int32>(u)) + " m");
    if vz >= 0.0 {
      this.rate.SetText("CLIMB +" + FloatToStringPrec(vz, 1) + " m/s");
      this.rate.SetTintColor(new HDRColor(0.3, 1.0, 0.55, 1.0));
    } else {
      this.rate.SetText("FALL " + FloatToStringPrec(vz, 1) + " m/s");
      this.rate.SetTintColor(new HDRColor(1.0, 0.75, 0.2, 1.0));
    }
    if offset > 0.0 {
      this.label.SetText("ALTITUDE - IN SPACE (NCM owns it)");
      this.ceiling.SetText("game z " + IntToString(Cast<Int32>(z)) + " m | rebase at 14000 | home below 3000");
      this.alt.SetTintColor(new HDRColor(0.45, 0.85, 1.0, 1.0));
    } else {
      this.label.SetText("ALTITUDE");
      this.ceiling.SetText("doorway at 14000 m: " + IntToString(Cast<Int32>(14000.0 - z)) + " m to go");
      if z > 12000.0 {
        this.alt.SetTintColor(new HDRColor(1.0, 0.75, 0.2, 1.0));
      } else {
        this.alt.SetTintColor(new HDRColor(0.95, 0.97, 1.0, 1.0));
      }
    }
    this.root.SetVisible(true);
  }

  public func Hide() -> Void {
    if IsDefined(this.root) {
      this.root.SetVisible(false);
    }
  }
}

@addField(gameuiCrosshairContainerController)
private let ncmSnowglobeAltimeter: ref<NcmSnowglobeAltimeter>;

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmSnowglobeSystem>;
  if !IsDefined(this.ncmSnowglobeAltimeter) && IsDefined(owner) {
    this.ncmSnowglobeAltimeter = new NcmSnowglobeAltimeter();
    this.ncmSnowglobeAltimeter.Build(this.GetRootCompoundWidget());
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmSnowglobe.NcmSnowglobeSystem") as NcmSnowglobeSystem;
    if IsDefined(system) {
      system.SetHud(this.ncmSnowglobeAltimeter);
    }
  }
  return result;
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnUninitialize() -> Bool {
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmSnowglobeSystem>;
  if IsDefined(owner) {
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmSnowglobe.NcmSnowglobeSystem") as NcmSnowglobeSystem;
    if IsDefined(system) {
      system.SetHud(null);
    }
  }
  this.ncmSnowglobeAltimeter = null;
  return wrappedMethod();
}
