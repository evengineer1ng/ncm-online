// NCM Gearbox -- the manual (L306 phase 3, owner design 2026-10-04).
//
// Every frame the local player DRIVES a car, this hands `ncm_gearbox.dll` the car's record, the HUD gear and the
// speed. For a manual clone the DLL runs the virtual gearbox (N, 1..n, the shift keys) and publishes the selected
// gear's torque share and ceiling to NCM Carrier; this file then shows that gear and its rpm on the car's own HUD
// (the Vehicle blackboard's GearValue / RPMValue -- UI only). For any other car the DLL answers -2 and nothing changes.
//
// The S2 instrument below (observe) runs only when `ncm_gearbox_config.json` turns `observe` on.
//
// While the local player sits in a car, every frame this hands `ncm_gearbox.dll` the car and what the HUD shows -- the
// gear, the rpm, the speed -- so the DLL can line the HUD's gear up against the car's own fields and name the one that
// moves with it. If `ncm_gearbox_config.json` names a field, the DLL also writes the configured gear into it every
// frame: the hold experiment. Out of a car it idles at 2 Hz.
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only;
//   * the local player's car only;
//   * no work out of a car beyond a 2 Hz check.
module NcmGearbox

public class NcmGearboxTick extends DelayCallback {
  public let system: wref<NcmGearboxSystem>;
  public let generation: Int32;
  public func Call() -> Void {
    let system: ref<NcmGearboxSystem> = this.system;
    if IsDefined(system) {
      system.Tick(this.generation);
    }
  }
}

public class NcmGearboxSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_generation: Int32;
  private let m_inCar: Bool;
  private let m_frames: Int32;
  private let m_hud: ref<NcmGearboxHud>;

  public func SetHud(hud: ref<NcmGearboxHud>) -> Void {
    this.m_hud = hud;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.m_player = player;
    this.m_generation += 1;
    NcmGearbox_Log("attached; " + NcmGearbox_Status());
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
    let tick: ref<NcmGearboxTick> = new NcmGearboxTick();
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
    let vehicle: ref<VehicleObject> = player.GetMountedVehicle() as VehicleObject;
    if !IsDefined(vehicle) {
      if this.m_inCar {
        this.m_inCar = false;
        if IsDefined(this.m_hud) {
          this.m_hud.Hide();
        }
        NcmGearbox_Left();
        NcmGearbox_Log("out of the car after " + IntToString(this.m_frames) + " frame(s); " + NcmGearbox_Status());
      }
      this.Schedule(0.5);
      return;
    }
    if !this.m_inCar {
      this.m_inCar = true;
      this.m_frames = 0;
      NcmGearbox_Log("in a car: " + TDBID.ToStringDEBUG(vehicle.GetRecordID()));
    }
    let bb: ref<IBlackboard> = vehicle.GetBlackboard();
    let gear: Int32 = 0;
    let rpm: Float = 0.0;
    if IsDefined(bb) {
      gear = bb.GetInt(GetAllBlackboardDefs().Vehicle.GearValue);
      rpm = bb.GetFloat(GetAllBlackboardDefs().Vehicle.RPMValue);
      NcmGearbox_DashSpeed(bb.GetFloat(GetAllBlackboardDefs().Vehicle.SpeedValue));
    }
    let speed: Float = vehicle.GetCurrentSpeed();
    if VehicleComponent.IsDriver(player.GetGame(), player) {
      let virtualGear: Int32 = NcmGearbox_Drive(TDBID.ToNumber(vehicle.GetRecordID()), gear, speed);
      if virtualGear < -1 && IsDefined(this.m_hud) {
        this.m_hud.Hide();
      }
      if virtualGear >= -1 {
        if IsDefined(this.m_hud) {
          this.m_hud.Show(virtualGear, NcmGearbox_RpmFraction());
          this.m_hud.SetMode(NcmGearbox_AudioMode(), NcmGearbox_AudioDetail());
        }
        // 0.2.7 (owner: "let them write the rpm and the actual speed it says on the dash"): the game owns the vehicle
        // blackboard's gear, rpm and speed -- one source of truth, the car's own dash. Our gear and revs live on our HUD.
        // the shift: the car's own gear-change sound (v_car_<maker>_<model>_gear_up / _gear_down, eventsmetadata.json)
        let shift: Int32 = NcmGearbox_ShiftEvent();
        if shift != 0 {
          let prefix: String = NcmGearbox_AudioName();
          if StrLen(prefix) > 0 {
            if shift > 0 {
              GameObject.PlaySoundEvent(vehicle, StringToName(prefix + "_gear_up"));
            } else {
              GameObject.PlaySoundEvent(vehicle, StringToName(prefix + "_gear_down"));
            }
          }
        }
        // the engine note: our revs and gear into the car's own engine audio parameters (config manual.engineAudio)
        let engineValue: Float = NcmGearbox_EngineAudioValue();
        if engineValue >= 0.0 {
          GameObject.SetAudioParameter(vehicle, n"veh_engine_rpm", engineValue);
          GameObject.SetAudioParameter(vehicle, n"veh_gear", Cast<Float>(virtualGear));
        }
      }
    }
    NcmGearbox_Observe(vehicle, gear, rpm, speed);
    this.m_frames += 1;
    this.Schedule(0.0);
  }
}

// ---------------------------------------------------------------------------------------------------- the indicator
// The gear you are in and how close you are to its limiter (owner QA 2026-10-04: "never saw the dash ... not knowing
// what gear im in is hard"). Drawn on the crosshair container, which stays on screen in every vehicle camera (the
// way NCM Broadcast draws its tower), and only while a manual is driven: a big R / N / 1..n and a rev bar that turns
// amber, then red, as the gear runs out.
public class NcmGearboxHud {
  private let root: ref<inkCanvas>;
  private let label: ref<inkText>;
  private let gear: ref<inkText>;
  private let bar: ref<inkRectangle>;
  private let detail: ref<inkText>;

  public func Build(parent: ref<inkCompoundWidget>) -> Void {
    if !IsDefined(parent) {
      NcmGearbox_Log("hud: no compound root; no indicator");
      return;
    }
    this.root = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.root.SetName(n"NcmGearboxHud");
    this.root.SetAnchor(inkEAnchor.TopLeft);
    this.root.SetMargin(1610.0, 790.0, 0.0, 0.0);
    this.root.SetSize(420.0, 215.0);
    this.label = this.Text(n"label", 24, 4.0, 0.0, 250.0, 30.0);
    this.label.SetText("MANUAL");
    this.label.SetTintColor(new HDRColor(0.6, 0.85, 1.0, 1.0));
    this.gear = this.Text(n"gear", 120, 0.0, 22.0, 250.0, 130.0);
    this.Rect(n"barBg", 4.0, 160.0, 240.0, 14.0, new HDRColor(0.1, 0.12, 0.15, 1.0), 0.7);
    this.bar = this.Rect(n"bar", 4.0, 160.0, 0.0, 14.0, new HDRColor(0.3, 1.0, 0.55, 1.0), 0.95);
    this.detail = this.Text(n"detail", 18, 4.0, 180.0, 410.0, 26.0);
    this.detail.SetText("");
    this.root.SetVisible(false);
    NcmGearbox_Log("hud: indicator attached");
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

  private func Rect(name: CName, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
    let r: ref<inkRectangle> = this.root.AddChild(n"inkRectangleWidget") as inkRectangle;
    r.SetName(name);
    r.SetMargin(x, y, 0.0, 0.0);
    r.SetSize(w, h);
    r.SetTintColor(color);
    r.SetOpacity(opacity);
    return r;
  }

  public func Show(gear: Int32, fraction: Float) -> Void {
    if !IsDefined(this.root) {
      return;
    }
    if gear < 0 {
      this.gear.SetText("R");
    } else {
      if gear == 0 {
        this.gear.SetText("N");
      } else {
        this.gear.SetText(IntToString(gear));
      }
    }
    let f: Float = ClampF(fraction, 0.0, 1.0);
    this.bar.SetSize(240.0 * f, 14.0);
    if f > 0.93 {
      this.bar.SetTintColor(new HDRColor(1.0, 0.25, 0.2, 1.0));
    } else {
      if f > 0.75 {
        this.bar.SetTintColor(new HDRColor(1.0, 0.75, 0.2, 1.0));
      } else {
        this.bar.SetTintColor(new HDRColor(0.3, 1.0, 0.55, 1.0));
      }
    }
    this.root.SetVisible(true);
  }

  // 0.2.6: which engine-sound scale is live (PAGEUP cycles it) -- "MANUAL - SOUND rpm"
  public func SetMode(mode: String, detail: String) -> Void {
    if IsDefined(this.label) {
      this.label.SetText("MANUAL - SOUND " + mode);
    }
    if IsDefined(this.detail) {
      this.detail.SetText(detail);
      if StrBeginsWith(detail, "CONFIG") || StrContains(detail, "FOLLOW 100") {
        this.detail.SetTintColor(new HDRColor(1.0, 0.3, 0.25, 1.0));
      } else {
        this.detail.SetTintColor(new HDRColor(0.6, 0.85, 1.0, 1.0));
      }
    }
  }

  public func Hide() -> Void {
    if IsDefined(this.root) {
      this.root.SetVisible(false);
    }
  }
}

@addField(gameuiCrosshairContainerController)
private let ncmGearboxHud: ref<NcmGearboxHud>;

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmGearboxSystem>;
  if !IsDefined(this.ncmGearboxHud) && IsDefined(owner) {
    this.ncmGearboxHud = new NcmGearboxHud();
    this.ncmGearboxHud.Build(this.GetRootCompoundWidget());
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmGearbox.NcmGearboxSystem") as NcmGearboxSystem;
    if IsDefined(system) {
      system.SetHud(this.ncmGearboxHud);
    }
  }
  return result;
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnUninitialize() -> Bool {
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmGearboxSystem>;
  if IsDefined(owner) {
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmGearbox.NcmGearboxSystem") as NcmGearboxSystem;
    if IsDefined(system) {
      system.SetHud(null);
    }
  }
  this.ncmGearboxHud = null;
  return wrappedMethod();
}
