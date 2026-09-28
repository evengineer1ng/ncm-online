// NCM Radial -- the quick menu, drawn natively.
//
// **This file draws and nothing else.** Which slot is highlighted, whether the wheel is open, and what each slot
// does are decided in resource Lua (`ncm_radial/client/radial.lua`), which reads the pad and the keyboard
// physically and owns every action. Lua hands that state to `ncm_radial.dll` over a loopback socket, and this
// script reads it back through two string natives. Native code cannot call a scripted function (doing so without
// a script frame terminates the process), so the direction is always script -> native, polled.
//
// **The host is the vanilla weapon wheel's controller.** `RadialWheelController` is a full-screen, centred HUD
// module that exists on foot and in vehicles and already knows how to blur the world behind itself. OPEN//77
// claims the weapon wheel (`setNativeActionBlocked("WeaponWheel")`), so the vanilla wheel never opens in a
// session and its root is otherwise idle. While NCM's wheel is up, the vanilla children are hidden and restored
// on close, so the two can never be on screen together. If the host is never constructed, `NcmRadial_ReportHost`
// is never called and `/ncm.radial` says `host=none` -- a missing host is a reported state, not a silent one.
//
// Coordinates are the HUD's 3840x2160 space.

public static native func NcmRadial_Frame() -> String
public static native func NcmRadial_Layout() -> String
public static native func NcmRadial_ReportHost(host: String, drawn: Int32) -> Bool

public class NcmRadialTick extends DelayCallback {
  public let view: wref<NcmRadialView>;
  public let game: GameInstance;
  public let generation: Int32;

  public func Call() -> Void {
    if IsDefined(this.view) {
      this.view.Tick(this.game, this.generation);
    }
  }
}

public class NcmRadialView extends IScriptable {
  private let host: wref<RadialWheelController>;
  private let root: ref<inkCanvas>;
  private let arm: ref<inkCanvas>;
  private let title: ref<inkText>;
  private let chosen: ref<inkText>;
  private let detail: ref<inkText>;
  private let hint: ref<inkText>;
  private let slots: array<ref<inkCanvas>>;
  private let slotFill: array<ref<inkRectangle>>;
  private let slotBar: array<ref<inkRectangle>>;
  private let slotLabel: array<ref<inkText>>;
  private let slotKey: array<ref<inkText>>;
  private let slotEmpty: array<ref<inkRectangle>>;
  private let slotState: array<Int32>;
  private let slotName: array<String>;
  private let slotDetail: array<String>;
  private let layoutRevision: String;
  private let lastFrame: String;
  private let shown: Bool;
  private let generation: Int32;
  private let drawn: Int32;

  public func Attach(host: ref<RadialWheelController>, game: GameInstance) -> Void {
    this.host = host;
    this.generation += 1;
    this.Build(host.GetRootCompoundWidget());
    NcmRadial_ReportHost("RadialWheelController", this.drawn);
    this.Schedule(game, false);
  }

  public func Detach() -> Void {
    this.generation += 1;          // any tick still queued dies on its next call
    if this.shown && IsDefined(this.host) {
      this.host.NcmRadialPresent(false, this.root);
    }
    this.shown = false;
    NcmRadial_ReportHost("none", this.drawn);
  }

  private func Schedule(game: GameInstance, open: Bool) -> Void {
    let tick: ref<NcmRadialTick> = new NcmRadialTick();
    tick.view = this;
    tick.game = game;
    tick.generation = this.generation;
    // Every frame while the wheel is up, so the highlight follows the stick; 20 Hz while it is down, which costs
    // two native string reads and nothing else. Not affected by time dilation: a frozen clock must not freeze
    // the one way out of the wheel.
    if open {
      GameInstance.GetDelaySystem(game).DelayCallbackNextFrame(tick);
    } else {
      GameInstance.GetDelaySystem(game).DelayCallback(tick, 0.05, false);
    }
  }

  public func Tick(game: GameInstance, generation: Int32) -> Void {
    if generation != this.generation || !IsDefined(this.host) || !IsDefined(this.root) {
      return;
    }
    this.Apply();
    this.Schedule(game, this.shown);
  }

  // ---------------------------------------------------------------------------------------------------------
  // Construction. Everything is made once; a new layout only changes text and visibility.
  // ---------------------------------------------------------------------------------------------------------

  private func Text(parent: ref<inkCompoundWidget>, name: CName, size: Int32, x: Float, y: Float, w: Float, h: Float) -> ref<inkText> {
    let label: ref<inkText> = parent.AddChild(n"inkTextWidget") as inkText;
    label.SetName(name);
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    label.SetFontSize(size);
    label.SetTintColor(new HDRColor(0.94, 0.96, 0.98, 1.0));
    label.SetFitToContent(false);
    label.SetMargin(x, y, 0.0, 0.0);
    label.SetSize(w, h);
    return label;
  }

  private func Rect(parent: ref<inkCompoundWidget>, name: CName, x: Float, y: Float, w: Float, h: Float, color: HDRColor) -> ref<inkRectangle> {
    let rect: ref<inkRectangle> = parent.AddChild(n"inkRectangleWidget") as inkRectangle;
    rect.SetName(name);
    rect.SetMargin(x, y, 0.0, 0.0);
    rect.SetSize(w, h);
    rect.SetTintColor(color);
    return rect;
  }

  private func Build(parent: ref<inkCompoundWidget>) -> Void {
    let center: ref<inkCanvas>;
    let dim: ref<inkRectangle>;
    let i: Int32;
    let angle: Float;
    let x: Float;
    let y: Float;
    let slot: ref<inkCanvas>;
    let fill: ref<inkRectangle>;
    let label: ref<inkText>;
    let key: ref<inkText>;
    if !IsDefined(parent) {
      return;
    }
    this.root = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.root.SetName(n"NcmRadial");
    this.root.SetAnchor(inkEAnchor.Fill);
    this.root.SetVisible(false);

    // A light scrim under the vanilla blur, so white labels hold against a bright sky.
    dim = this.root.AddChild(n"inkRectangleWidget") as inkRectangle;
    dim.SetName(n"scrim");
    dim.SetAnchor(inkEAnchor.Fill);
    dim.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 1.0));
    dim.SetOpacity(0.35);

    // A 1600x1600 stage, centred. Inside it everything is TopLeft + margin, with the wheel's centre at (800, 800).
    center = this.root.AddChild(n"inkCanvasWidget") as inkCanvas;
    center.SetName(n"stage");
    center.SetAnchor(inkEAnchor.Centered);
    center.SetAnchorPoint(new Vector2(0.5, 0.5));
    center.SetSize(1600.0, 1600.0);

    // The pointer: a canvas the size of the inner disc, rotated about its own centre, carrying one bar at the top.
    this.arm = center.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.arm.SetName(n"arm");
    this.arm.SetMargin(500.0, 500.0, 0.0, 0.0);
    this.arm.SetSize(600.0, 600.0);
    this.arm.SetRenderTransformPivot(new Vector2(0.5, 0.5));
    this.Rect(this.arm, n"needle", 294.0, 20.0, 12.0, 120.0, new HDRColor(0.133, 0.847, 0.886, 1.0));
    this.arm.SetVisible(false);

    this.title = this.Text(center, n"title", 40, 350.0, 700.0, 900.0, 56.0);
    this.title.SetHorizontalAlignment(textHorizontalAlignment.Center);
    this.title.SetTintColor(new HDRColor(0.133, 0.847, 0.886, 1.0));
    this.chosen = this.Text(center, n"chosen", 72, 250.0, 752.0, 1100.0, 96.0);
    this.chosen.SetHorizontalAlignment(textHorizontalAlignment.Center);
    this.chosen.SetLetterCase(textLetterCase.UpperCase);
    this.detail = this.Text(center, n"detail", 36, 350.0, 850.0, 900.0, 52.0);
    this.detail.SetHorizontalAlignment(textHorizontalAlignment.Center);
    this.detail.SetTintColor(new HDRColor(0.553, 0.6, 0.659, 1.0));
    this.hint = this.Text(center, n"hint", 30, 200.0, 1500.0, 1200.0, 48.0);
    this.hint.SetHorizontalAlignment(textHorizontalAlignment.Center);
    this.hint.SetTintColor(new HDRColor(0.553, 0.6, 0.659, 1.0));

    // Eight fixed positions, clockwise from the top. Fixed so a driver's thumb learns them: a slot is greyed or
    // left open, never moved, and an empty slot keeps its mark so the wheel reads as having room to grow.
    i = 0;
    while i < 8 {
      angle = Cast<Float>(i) * 45.0;
      x = 800.0 + SinF(Deg2Rad(angle)) * 540.0 - 230.0;
      y = 800.0 - CosF(Deg2Rad(angle)) * 540.0 - 64.0;
      slot = center.AddChild(n"inkCanvasWidget") as inkCanvas;
      slot.SetName(StringToName("slot" + ToString(i)));
      slot.SetMargin(x, y, 0.0, 0.0);
      slot.SetSize(460.0, 128.0);
      slot.SetRenderTransformPivot(new Vector2(0.5, 0.5));
      fill = this.Rect(slot, n"fill", 0.0, 0.0, 460.0, 128.0, new HDRColor(0.025, 0.045, 0.06, 0.94));
      ArrayPush(this.slotFill, fill);
      ArrayPush(this.slotBar, this.Rect(slot, n"bar", 0.0, 0.0, 10.0, 128.0, new HDRColor(0.553, 0.6, 0.659, 1.0)));
      label = this.Text(slot, n"label", 46, 36.0, 18.0, 400.0, 60.0);
      label.SetLetterCase(textLetterCase.UpperCase);
      ArrayPush(this.slotLabel, label);
      key = this.Text(slot, n"key", 30, 36.0, 78.0, 400.0, 40.0);
      key.SetTintColor(new HDRColor(0.553, 0.6, 0.659, 1.0));
      ArrayPush(this.slotKey, key);
      ArrayPush(this.slotEmpty, this.Rect(slot, n"open", 190.0, 60.0, 80.0, 8.0, new HDRColor(0.553, 0.6, 0.659, 1.0)));
      ArrayPush(this.slots, slot);
      ArrayPush(this.slotState, 0);
      ArrayPush(this.slotName, "");
      ArrayPush(this.slotDetail, "");
      i += 1;
    }
    this.drawn += 1;
  }

  // ---------------------------------------------------------------------------------------------------------
  // Per tick
  // ---------------------------------------------------------------------------------------------------------

  private func Apply() -> Void {
    let frame: String = NcmRadial_Frame();
    let parts: array<String>;
    let open: Bool;
    let selected: Int32;
    let pointer: Float;
    if Equals(frame, this.lastFrame) {
      return;
    }
    this.lastFrame = frame;
    // "open|selected|pointerDegrees|layoutRevision"; selected is -1 and pointer negative when nothing is aimed at.
    parts = StrSplit(frame, "|");
    if ArraySize(parts) < 4 {
      return;
    }
    open = Equals(parts[0], "1");
    selected = StringToInt(parts[1]);
    pointer = StringToFloat(parts[2]);
    if NotEquals(parts[3], this.layoutRevision) {
      this.ApplyLayout(parts[3]);
    }
    if NotEquals(open, this.shown) {
      this.shown = open;
      this.host.NcmRadialPresent(open, this.root);
    }
    if !open {
      return;
    }
    this.ApplySelection(selected, pointer);
  }

  private func ApplyLayout(revision: String) -> Void {
    // "revision|title|hint" then eight "state|label|key|detail" groups. state: 0 open, 1 live, 2 greyed.
    let parts: array<String> = StrSplit(NcmRadial_Layout(), "|");
    let i: Int32 = 0;
    let at: Int32;
    let state: Int32;
    if ArraySize(parts) < 3 + 8 * 4 {
      return;
    }
    this.layoutRevision = revision;
    this.title.SetText(parts[1]);
    this.hint.SetText(parts[2]);
    while i < 8 {
      at = 3 + i * 4;
      state = StringToInt(parts[at]);
      this.slotState[i] = state;
      this.slotName[i] = parts[at + 1];
      this.slotDetail[i] = parts[at + 3];
      this.slotLabel[i].SetText(parts[at + 1]);
      this.slotKey[i].SetText(parts[at + 2]);
      this.slotLabel[i].SetVisible(state != 0);
      this.slotKey[i].SetVisible(state != 0);
      this.slotBar[i].SetVisible(state != 0);
      this.slotEmpty[i].SetVisible(state == 0);
      this.slotFill[i].SetOpacity(state == 0 ? 0.35 : 1.0);
      this.slots[i].SetOpacity(state == 2 ? 0.45 : 1.0);
      i += 1;
    }
    this.lastFrame = "";            // redraw the selection against the new text
  }

  private func ApplySelection(selected: Int32, pointer: Float) -> Void {
    let i: Int32 = 0;
    let on: Bool;
    while i < 8 {
      on = i == selected && this.slotState[i] != 0;
      this.slotFill[i].SetTintColor(on ? new HDRColor(0.05, 0.2, 0.235, 0.97) : new HDRColor(0.025, 0.045, 0.06, 0.94));
      this.slotBar[i].SetTintColor(on ? new HDRColor(0.133, 0.847, 0.886, 1.0) : new HDRColor(0.553, 0.6, 0.659, 1.0));
      this.slots[i].SetScale(on ? new Vector2(1.08, 1.08) : new Vector2(1.0, 1.0));
      i += 1;
    }
    if pointer >= 0.0 {
      this.arm.SetRotation(pointer);
      this.arm.SetVisible(true);
    } else {
      this.arm.SetVisible(false);
    }
    if selected >= 0 && selected < 8 && this.slotState[selected] != 0 {
      this.chosen.SetText(this.slotName[selected]);
      this.detail.SetText(this.slotState[selected] == 2 ? "Not available right now" : this.slotDetail[selected]);
    } else {
      this.chosen.SetText("");
      this.detail.SetText(selected >= 0 ? "Open slot" : "Point at an option · release to close");
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The host
// ---------------------------------------------------------------------------------------------------------------

@addField(RadialWheelController)
private let ncmRadial: ref<NcmRadialView>;

@addField(RadialWheelController)
private let ncmRadialHidden: array<wref<inkWidget>>;

@wrapMethod(RadialWheelController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let owner: ref<GameObject>;
  if !IsDefined(this.ncmRadial) {
    owner = this.GetPlayerControlledObject();
    if IsDefined(owner) {
      this.ncmRadial = new NcmRadialView();
      this.ncmRadial.Attach(this, owner.GetGame());
    }
  }
  return result;
}

@wrapMethod(RadialWheelController)
protected cb func OnUninitialize() -> Bool {
  if IsDefined(this.ncmRadial) {
    this.ncmRadial.Detach();
    this.ncmRadial = null;
  }
  return wrappedMethod();
}

// Called from inside the class so the protected presentation helpers are reachable. Opening hides every vanilla
// child and remembers exactly which ones were visible; closing puts back those and only those.
@addMethod(RadialWheelController)
public func NcmRadialPresent(open: Bool, mine: ref<inkCanvas>) -> Void {
  let root: ref<inkCompoundWidget> = this.GetRootCompoundWidget();
  let i: Int32;
  let child: wref<inkWidget>;
  if !IsDefined(root) || !IsDefined(mine) {
    return;
  }
  if open {
    ArrayClear(this.ncmRadialHidden);
    i = 0;
    while i < root.GetNumChildren() {
      child = root.GetWidgetByIndex(i);
      if IsDefined(child) && NotEquals(child.GetName(), n"NcmRadial") && child.IsVisible() {
        child.SetVisible(false);
        ArrayPush(this.ncmRadialHidden, child);
      }
      i += 1;
    }
    mine.SetVisible(true);
    root.SetVisible(true);
    PopupStateUtils.SetBackgroundBlur(this, true);
    this.PlaySound(n"RadialMenu", n"OnOpen");
  } else {
    mine.SetVisible(false);
    for child in this.ncmRadialHidden {
      if IsDefined(child) {
        child.SetVisible(true);
      }
    }
    ArrayClear(this.ncmRadialHidden);
    root.SetVisible(false);
    PopupStateUtils.SetBackgroundBlur(this, false);
    this.PlaySound(n"RadialMenu", n"OnClose");
  }
}
