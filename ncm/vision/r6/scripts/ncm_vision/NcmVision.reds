// NCM Vision -- the scanner's look, without the scanner (`IDEA-679`).
//
// Hold Tab (VisionHold) or tap Caps Lock (VisionToggle) and the world takes the vanilla scanner's green
// render. Nothing else about the scanner comes with it: no scan HUD, no walk-only restriction, no slow
// motion.
//
// WHY THIS WORKS UNDER OPEN//77. Vanilla `PlayerVisionModeController.ActivateVisionMode()` makes three
// independent calls: the scanning controller's Heavy mode (scan-on-look and its HUD), `VisionModeSystem
// .EnterMode(owner, Focus)` (the render), and the FocusModeLocomotion status effect. OPEN//77 refuses the
// CONTROLLER in every multiplayer session (`Open77MultiplayerPolicy.reds`, PlayerVisionModeController
// wraps). It does not touch the system underneath, so this file makes the render call alone.
//
// WHY THERE IS NO SLOW MOTION. Scanner time dilation is a player-state-machine state
// (TimeDilationFocusMode), entered from the vision PSM context, not from the render. This file never enters
// that context, and OPEN//77 refuses the state in multiplayer on its own besides.
//
// THREE RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols only -- nothing from OPEN//77, NCM or any other mod, so no upstream rename can break
//     the compile;
//   * no per-frame work -- two input listeners, and state changes only on a key edge;
//   * never consume the input -- OPEN//77 WebUI and resource key mappings still receive Tab.
//
// It is a separate package from the Carrier and the Rig Bridge on purpose: it shares nothing with them.
module NcmVision

public class NcmVisionSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_listener: ref<NcmVisionListener>;
  private let m_held: Bool;
  private let m_toggled: Bool;
  // What this file last asked the vision system for. Only ever changed by Refresh(), so a release can never
  // switch off a render some other system turned on.
  private let m_on: Bool;

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
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.Release();
  }

  // Drop the render and the listeners together, so a detach or a re-attach never leaves the world green.
  private func Release() -> Void {
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
