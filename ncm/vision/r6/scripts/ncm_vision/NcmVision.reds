// NCM Scanner -- the scanner's look and its eye, without the scanner (`L196`, `L197`, `IDEA-679`).
//
// Hold Tab (VisionHold) or tap Caps Lock (VisionToggle) and the world takes the vanilla scanner's green
// render, a reticle appears, and whatever the player looks at is reported to NCM so the Scanner can identify
// it. Nothing else about the vanilla scanner comes with it: no scan HUD, no walk-only restriction, no slow
// motion.
//
// WHY THE GREEN WORKS UNDER OPEN//77 (live PASS 2026-09-28). Vanilla `PlayerVisionModeController` makes three
// independent calls: the scanning controller's Heavy mode, `VisionModeSystem.EnterMode(owner, Focus)` (the
// render), and the FocusModeLocomotion status effect. OPEN//77 refuses the CONTROLLER for the whole session. It
// does not touch the system underneath, so this file makes the render call alone. Scanner time dilation is a
// player-state-machine state this file never enters, and OPEN//77 refuses it separately besides.
//
// WHO DECIDES WHAT. This file sees and draws; it decides nothing about knowledge. Each tick while vision is on
// it reports the look-at object (EntityID hash, record, kind, distance) to `ncm_vision.dll`; resource Lua
// (`ncm_scanner`) reads that over loopback, asks the server, runs the lock, and sends back what the reticle
// should say. If the DLL's feed is absent the green and a bare reticle still work -- they are the player's own
// key -- and nothing is identified.
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only -- nothing from OPEN//77, NCM Lua or any other mod;
//   * work only while vision is on: two input listeners, and a 20 Hz tick that exists only while the render
//     does;
//   * never consume the input -- OPEN//77 WebUI and resource key mappings still receive Tab.
//
// A separate package from the Carrier, the Rig Bridge and the Radial: it shares nothing with them.
module NcmVision

// The natives are declared in `NcmScannerNatives.reds`, which has NO module on purpose: a native declared inside
// a module is looked up as `NcmVision.NcmScanner_*`, the DLL registers `NcmScanner_*`, and RED4ext refuses to
// start the game (live, 2026-09-28, `KB-182`).

public class NcmVisionTick extends DelayCallback {
  public let system: wref<NcmVisionSystem>;
  public let generation: Int32;

  public func Call() -> Void {
    let system: ref<NcmVisionSystem> = this.system;
    if IsDefined(system) {
      system.Tick(this.generation);
    }
  }
}

// 0.4.0: the pad's scanner hold, polled ten times a second while a player is attached (the ncm_scanner resource reads
// LB through OPEN//77 -- owner, 2026-10-03: LB did nothing for them while driving).
public class NcmVisionPadTick extends DelayCallback {
  public let system: wref<NcmVisionSystem>;
  public let generation: Int32;

  public func Call() -> Void {
    let system: ref<NcmVisionSystem> = this.system;
    if IsDefined(system) {
      system.PadTick(this.generation);
    }
  }
}

public class NcmVisionSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_listener: ref<NcmVisionListener>;
  private let m_reticle: wref<NcmScannerReticle>;
  private let m_held: Bool;
  private let m_toggled: Bool;
  // What this file last asked the vision system for. Only ever changed by Refresh(), so a release can never
  // switch off a render some other system turned on.
  private let m_on: Bool;
  // Bumped on every on/off edge and detach, so a tick scheduled before the edge dies on its next call.
  private let m_generation: Int32;
  private let m_padHeld: Bool;
  private let m_padGeneration: Int32;

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    // Local player only. A remote body is never ours to listen on.
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.Release();
    this.m_player = player;
    this.m_listener = new NcmVisionListener();
    this.m_listener.m_system = this;
    player.RegisterInputListener(this.m_listener, n"VisionHold");
    player.RegisterInputListener(this.m_listener, n"VisionToggle");
    this.m_padGeneration += 1;
    this.SchedulePad();
  }

  private func SchedulePad() -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let tick: ref<NcmVisionPadTick> = new NcmVisionPadTick();
    tick.system = this;
    tick.generation = this.m_padGeneration;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(tick, 0.1, false);
  }

  public func PadTick(generation: Int32) -> Void {
    if generation != this.m_padGeneration || !IsDefined(this.m_player) {
      return;
    }
    let held: Bool = NcmScanner_PadHold();
    if NotEquals(held, this.m_padHeld) {
      this.m_padHeld = held;
      this.SetHeld(held);
    }
    this.SchedulePad();
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.Release();
  }

  // Drop the render and the listeners together, so a detach or a re-attach never leaves the world green.
  private func Release() -> Void {
    this.m_padGeneration += 1;
    this.m_padHeld = false;
    this.m_held = false;
    this.m_toggled = false;
    this.Refresh();
    let player: ref<PlayerPuppet> = this.m_player;
    if IsDefined(player) && IsDefined(this.m_listener) {
      player.UnregisterInputListener(this.m_listener);
    }
    this.m_listener = null;
    this.m_player = null;
  }

  public func SetReticle(reticle: ref<NcmScannerReticle>) -> Void {
    this.m_reticle = reticle;
    if IsDefined(reticle) {
      reticle.Show(this.m_on);
    }
  }

  public func IsOn() -> Bool {
    return this.m_on;
  }

  public func SetHeld(held: Bool) -> Void {
    this.m_held = held;
    // A hold always ends in plain vision, even when a toggle was also on. That way a stuck toggle (a key-up
    // lost to alt-tab) is cleared by one press and release of either key.
    if !held {
      this.m_toggled = false;
    }
    this.Refresh();
  }

  public func Toggle() -> Void {
    this.m_toggled = !this.m_toggled;
    this.Refresh();
  }

  private func Refresh() -> Void {
    let want: Bool = this.m_held || this.m_toggled;
    if Equals(want, this.m_on) {
      return;
    }
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      this.m_on = false;
      return;
    }
    let vision: ref<VisionModeSystem> = GameInstance.GetVisionModeSystem(player.GetGame());
    if !IsDefined(vision) {
      return;
    }
    if want {
      vision.EnterMode(player, gameVisionModeType.Focus);
    } else {
      vision.EnterMode(player, gameVisionModeType.Default);
    }
    this.m_on = want;
    this.m_generation += 1;
    let reticle: ref<NcmScannerReticle> = this.m_reticle;
    if IsDefined(reticle) {
      reticle.Show(want);
    }
    if want {
      this.Schedule();
    } else {
      NcmScanner_Report(false, 0ul, 0ul, 0, -1.0, 0.0, 0.0, 0.0);
    }
  }

  private func Schedule() -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let tick: ref<NcmVisionTick> = new NcmVisionTick();
    tick.system = this;
    tick.generation = this.m_generation;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(tick, 0.05, false);
  }

  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation || !this.m_on {
      return;
    }
    this.Look();
    let reticle: ref<NcmScannerReticle> = this.m_reticle;
    if IsDefined(reticle) {
      reticle.Apply();
    }
    this.Schedule();
  }

  // What is the player looking at? The engine's own look-at target first -- the one the vanilla scanner uses --
  // then the object nearest the crosshair within a few degrees, because look-at is not guaranteed from a
  // driver's seat. The player's own car is never a target.
  private func Look() -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let game: GameInstance = player.GetGame();
    let targeting: ref<TargetingSystem> = GameInstance.GetTargetingSystem(game);
    let mounted: wref<VehicleObject>;
    let angle: EulerAngles;
    let target: ref<GameObject>;
    let vehicle: ref<VehicleObject>;
    let kind: Int32 = 0;
    let record: Uint64 = 0ul;
    let entity: Uint64 = 0ul;
    let distance: Float = -1.0;
    let at: Vector4;
    VehicleComponent.GetVehicle(game, player, mounted);
    if IsDefined(targeting) {
      target = targeting.GetLookAtObject(player, false, false);
      if !IsDefined(target) || target == mounted {
        target = targeting.GetObjectClosestToCrosshair(player, angle, TSQ_ALL());
        if IsDefined(target) && (AbsF(angle.Yaw) > 6.0 || AbsF(angle.Pitch) > 6.0) {
          target = null;
        }
      }
    }
    if IsDefined(target) && target != mounted && target != player {
      entity = Cast<Uint64>(EntityID.GetHash(target.GetEntityID()));
      at = target.GetWorldPosition();
      distance = Vector4.Distance(player.GetWorldPosition(), at);
      vehicle = target as VehicleObject;
      if IsDefined(vehicle) {
        kind = 1;
        record = TDBID.ToNumber(vehicle.GetRecordID());
      } else {
        kind = 2;
      }
    }
    NcmScanner_Report(true, entity, record, kind, distance, at.X, at.Y, at.Z);
  }
}

public class NcmVisionListener extends IScriptable {
  public let m_system: wref<NcmVisionSystem>;

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    let system: ref<NcmVisionSystem> = this.m_system;
    if !IsDefined(system) {
      return false;
    }
    let name: CName = ListenerAction.GetName(action);
    if Equals(name, n"VisionHold") {
      if ListenerAction.IsButtonJustPressed(action) {
        system.SetHeld(true);
      } else {
        if ListenerAction.IsButtonJustReleased(action) {
          system.SetHeld(false);
        }
      }
    } else {
      if Equals(name, n"VisionToggle") && ListenerAction.IsButtonJustPressed(action) {
        system.Toggle();
      }
    }
    // Never consume: OPEN//77 and other listeners must still see the key.
    return false;
  }
}
