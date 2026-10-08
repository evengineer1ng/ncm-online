// NCM Host -- the Race Week line on the HUD, drawn natively (L340 phase 2; was CET ImGui).
//
// **No `module`** (KB-182). Attached the way NCM Broadcast attaches (live-proven): to the crosshair container, a
// full-screen HUD controller that exists on foot and in vehicles. It reads NcmHostRuntime's last `hud` line four times
// a second and shows nothing while NCM is dormant.

public class NcmHostHudTick extends DelayCallback {
  public let hud: wref<NcmHostHud>;
  public func Call() -> Void {
    if IsDefined(this.hud) {
      this.hud.Tick();
    }
  }
}

public class NcmHostHud extends IScriptable {
  private let game: GameInstance;
  private let panel: ref<inkCanvas>;
  private let label: ref<inkText>;
  private let sub: ref<inkText>;
  private let alive: Bool;

  public func Build(parent: ref<inkCompoundWidget>, game: GameInstance) -> Void {
    if !IsDefined(parent) {
      return;
    }
    this.game = game;
    this.panel = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.panel.SetName(n"NcmHostRaceWeek");
    this.panel.SetAnchor(inkEAnchor.TopRight);
    this.panel.SetAnchorPoint(new Vector2(1.0, 0.0));
    this.panel.SetMargin(0.0, 60.0, 560.0, 0.0);
    this.panel.SetSize(900.0, 110.0);
    this.label = this.Text(n"label", 40, 0.0, new HDRColor(0.94, 0.96, 0.98, 1.0));
    this.sub = this.Text(n"sub", 30, 50.0, new HDRColor(0.553, 0.6, 0.659, 1.0));
    this.panel.SetVisible(false);
    this.alive = true;
    this.Schedule();
  }

  public func Stop() -> Void {
    this.alive = false;
  }

  private func Text(name: CName, size: Int32, y: Float, color: HDRColor) -> ref<inkText> {
    let t: ref<inkText> = this.panel.AddChild(n"inkTextWidget") as inkText;
    t.SetName(name);
    t.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    t.SetFontSize(size);
    t.SetTintColor(color);
    t.SetAnchor(inkEAnchor.TopRight);
    t.SetAnchorPoint(new Vector2(1.0, 0.0));
    t.SetHorizontalAlignment(textHorizontalAlignment.Right);
    t.SetMargin(0.0, y, 0.0, 0.0);
    t.SetSize(900.0, 48.0);
    t.SetFitToContent(true);
    return t;
  }

  private func Schedule() -> Void {
    let tick: ref<NcmHostHudTick> = new NcmHostHudTick();
    tick.hud = this;
    GameInstance.GetDelaySystem(this.game).DelayCallback(tick, 0.25, false);
  }

  public func Tick() -> Void {
    if !this.alive {
      return;
    }
    let runtime: ref<NcmHostRuntime> = NcmHostRuntime.Get(this.game);
    let show: Bool = IsDefined(runtime) && runtime.IsMounted() && StrLen(runtime.HudLabel()) > 0;
    if show {
      this.label.SetText(runtime.HudLabel());
      this.sub.SetText(runtime.HudRemaining());
    }
    this.panel.SetVisible(show);
    this.Schedule();
  }
}

@addField(gameuiCrosshairContainerController)
private let ncmHostHud: ref<NcmHostHud>;

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  if !IsDefined(this.ncmHostHud) && IsDefined(owner) {
    this.ncmHostHud = new NcmHostHud();
    this.ncmHostHud.Build(this.GetRootCompoundWidget(), owner.GetGame());
  }
  return result;
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnUninitialize() -> Bool {
  if IsDefined(this.ncmHostHud) {
    this.ncmHostHud.Stop();
  }
  this.ncmHostHud = null;
  return wrappedMethod();
}
