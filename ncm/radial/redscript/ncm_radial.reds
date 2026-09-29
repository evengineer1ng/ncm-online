// NCM Radial -- the quick menu, drawn natively.
//
// **This file draws and nothing else.** Which slot is highlighted, whether the wheel is open, and what each slot
// does are decided in resource Lua (`ncm_radial/client/radial.lua`), which reads the pad and the keyboard
// physically and owns every action. Lua hands that state to `ncm_radial.dll` over a loopback socket, and this
// script reads it back through string natives. Native code cannot call a scripted function (doing so without a
// script frame terminates the process), so the direction is always script -> native, polled.
//
// **The host is the vanilla weapon wheel's controller.** `RadialWheelController` is a full-screen, centred HUD
// module that exists on foot and in vehicles and already knows how to blur the world behind itself. OPEN//77
// claims the weapon wheel, so the vanilla wheel never opens in a session and its root is otherwise idle. While
// NCM's wheel is up, the vanilla children are hidden and restored on close.
//
// **Two lessons from the first live wheel (2026-09-28), both now structural:**
//   * The tick is ALWAYS `DelayCallback`. `DelayCallbackNextFrame` was used while the wheel was open and its chain
//     never fired again, so the wheel froze on its first frame: stuck open, highlight never moving.
//   * Every wire field is non-empty (`~` means empty). An open slot's empty fields collapsed in `StrSplit`, the
//     count came up short and every layout was refused, so all eight cards were blank. A refused layout is now
//     logged to the plugin log (`NcmRadial_Log`) instead of failing silently.
//
// Coordinates are the HUD's 3840x2160 space.

public static native func NcmRadial_Frame() -> String
public static native func NcmRadial_Layout() -> String
public static native func NcmRadial_ReportHost(host: String, drawn: Int32) -> Bool
public static native func NcmRadial_Log(text: String) -> Bool

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

public static func NcmRadialField(value: String) -> String {
  return Equals(value, "~") ? "" : value;
}

public static func NcmRadialAccent() -> HDRColor {
  return new HDRColor(0.133, 0.847, 0.886, 1.0);
}

public static func NcmRadialInk() -> HDRColor {
  return new HDRColor(0.94, 0.96, 0.98, 1.0);
}

public static func NcmRadialDim() -> HDRColor {
  return new HDRColor(0.553, 0.6, 0.659, 1.0);
}

public static func NcmRadialPanel() -> HDRColor {
  return new HDRColor(0.016, 0.03, 0.045, 1.0);
}

public class NcmRadialView extends IScriptable {
  private let host: wref<RadialWheelController>;
  private let root: ref<inkCanvas>;
  private let arm: ref<inkCanvas>;
  private let title: ref<inkText>;
  private let chosen: ref<inkText>;
  private let detail: ref<inkText>;
  private let hint: ref<inkText>;
  private let cards: array<ref<inkCanvas>>;
  private let cardFill: array<ref<inkRectangle>>;
  private let cardEdges: array<ref<inkCanvas>>;
  private let cardLabel: array<ref<inkText>>;
  private let cardKey: array<ref<inkText>>;
  private let dots: array<ref<inkRectangle>>;
  private let slotState: array<Int32>;
  private let slotName: array<String>;
  private let slotDetail: array<String>;
  private let layoutRevision: String;
  private let lastFrame: String;
  private let shown: Bool;
  private let generation: Int32;
  private let drawn: Int32;
  private let refusedLayouts: Int32;

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
    // ~every frame while open so the highlight follows the stick; 20 Hz while closed. Not affected by time
    // dilation: a frozen clock must not freeze the one way out of the wheel.
    GameInstance.GetDelaySystem(game).DelayCallback(tick, open ? 0.01 : 0.05, false);
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
    label.SetTintColor(NcmRadialInk());
    label.SetFitToContent(false);
    label.SetMargin(x, y, 0.0, 0.0);
    label.SetSize(w, h);
    label.SetHorizontalAlignment(textHorizontalAlignment.Center);
    label.SetVerticalAlignment(textVerticalAlignment.Center);
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

  // A hairline frame: four rectangles inside a canvas, so the whole frame can be recoloured through the canvas.
  private func Frame(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, t: Float) -> ref<inkCanvas> {
    let edges: ref<inkCanvas> = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    edges.SetName(n"edges");
    edges.SetMargin(x, y, 0.0, 0.0);
    edges.SetSize(w, h);
    this.Rect(edges, n"top", 0.0, 0.0, w, t, NcmRadialInk());
    this.Rect(edges, n"bottom", 0.0, h - t, w, t, NcmRadialInk());
    this.Rect(edges, n"left", 0.0, 0.0, t, h, NcmRadialInk());
    this.Rect(edges, n"right", w - t, 0.0, t, h, NcmRadialInk());
    return edges;
  }

  private func Build(parent: ref<inkCompoundWidget>) -> Void {
    let stage: ref<inkCanvas>;
    let hub: ref<inkCanvas>;
    let scrim: ref<inkRectangle>;
    let hubFill: ref<inkRectangle>;
    let hubEdges: ref<inkCanvas>;
    let i: Int32;
    let angle: Float;
    let cx: Float;
    let cy: Float;
    let card: ref<inkCanvas>;
    let fill: ref<inkRectangle>;
    let edges: ref<inkCanvas>;
    let label: ref<inkText>;
    let key: ref<inkText>;
    let dot: ref<inkRectangle>;
    if !IsDefined(parent) {
      NcmRadial_Log("host has no compound root; nothing drawn");
      return;
    }
    this.root = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.root.SetName(n"NcmRadial");
    this.root.SetAnchor(inkEAnchor.Fill);
    this.root.SetVisible(false);

    scrim = this.root.AddChild(n"inkRectangleWidget") as inkRectangle;
    scrim.SetName(n"scrim");
    scrim.SetAnchor(inkEAnchor.Fill);
    scrim.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 1.0));
    scrim.SetOpacity(0.28);

    // A 1600x1600 stage, centred; inside it everything is TopLeft + margin, wheel centre at (800, 800).
    stage = this.root.AddChild(n"inkCanvasWidget") as inkCanvas;
    stage.SetName(n"stage");
    stage.SetAnchor(inkEAnchor.Centered);
    stage.SetAnchorPoint(new Vector2(0.5, 0.5));
    stage.SetSize(1600.0, 1600.0);

    // The hub: a diamond (a square turned 45 degrees) with a hairline edge.
    hub = stage.AddChild(n"inkCanvasWidget") as inkCanvas;
    hub.SetName(n"hub");
    hub.SetMargin(680.0, 680.0, 0.0, 0.0);
    hub.SetSize(240.0, 240.0);
    hub.SetRenderTransformPivot(new Vector2(0.5, 0.5));
    hub.SetRotation(45.0);
    hubFill = this.Rect(hub, n"fill", 0.0, 0.0, 240.0, 240.0, NcmRadialPanel());
    hubFill.SetOpacity(0.92);
    hubEdges = this.Frame(hub, 0.0, 0.0, 240.0, 240.0, 3.0);
    hubEdges.SetTintColor(NcmRadialAccent());
    hubEdges.SetOpacity(0.7);

    // The pointer: a canvas the size of the inner disc, rotated about its centre, one bar just outside the hub.
    this.arm = stage.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.arm.SetName(n"arm");
    this.arm.SetMargin(500.0, 500.0, 0.0, 0.0);
    this.arm.SetSize(600.0, 600.0);
    this.arm.SetRenderTransformPivot(new Vector2(0.5, 0.5));
    this.Rect(this.arm, n"needle", 293.0, 36.0, 14.0, 92.0, NcmRadialAccent());
    this.arm.SetVisible(false);

    this.title = this.Text(stage, n"title", 34, 600.0, 718.0, 400.0, 44.0);
    this.title.SetTintColor(NcmRadialAccent());
    this.chosen = this.Text(stage, n"chosen", 50, 560.0, 762.0, 480.0, 76.0);
    this.chosen.SetLetterCase(textLetterCase.UpperCase);
    this.detail = this.Text(stage, n"detail", 36, 200.0, 1390.0, 1200.0, 52.0);
    this.detail.SetTintColor(NcmRadialDim());
    this.hint = this.Text(stage, n"hint", 28, 200.0, 1450.0, 1200.0, 44.0);
    this.hint.SetTintColor(NcmRadialDim());
    this.hint.SetOpacity(0.8);

    // Eight fixed positions, clockwise from the top. A live slot is a card; an open slot is only a faint dot,
    // so the wheel reads as "five things, room for more" rather than eight empty boxes.
    i = 0;
    while i < 8 {
      angle = Cast<Float>(i) * 45.0;
      cx = 800.0 + SinF(Deg2Rad(angle)) * 470.0;
      cy = 800.0 - CosF(Deg2Rad(angle)) * 470.0;

      card = stage.AddChild(n"inkCanvasWidget") as inkCanvas;
      card.SetName(StringToName("slot" + ToString(i)));
      card.SetMargin(cx - 200.0, cy - 60.0, 0.0, 0.0);
      card.SetSize(400.0, 120.0);
      card.SetRenderTransformPivot(new Vector2(0.5, 0.5));
      fill = this.Rect(card, n"fill", 0.0, 0.0, 400.0, 120.0, NcmRadialPanel());
      fill.SetOpacity(0.9);
      edges = this.Frame(card, 0.0, 0.0, 400.0, 120.0, 2.0);
      edges.SetTintColor(NcmRadialAccent());
      edges.SetOpacity(0.35);
      label = this.Text(card, n"label", 44, 0.0, 14.0, 400.0, 56.0);
      label.SetLetterCase(textLetterCase.UpperCase);
      key = this.Text(card, n"key", 26, 0.0, 72.0, 400.0, 34.0);
      key.SetTintColor(NcmRadialDim());
      card.SetVisible(false);

      dot = this.Rect(stage, StringToName("dot" + ToString(i)), cx - 7.0, cy - 7.0, 14.0, 14.0, NcmRadialDim());
      dot.SetOpacity(0.45);

      ArrayPush(this.cards, card);
      ArrayPush(this.cardFill, fill);
      ArrayPush(this.cardEdges, edges);
      ArrayPush(this.cardLabel, label);
      ArrayPush(this.cardKey, key);
      ArrayPush(this.dots, dot);
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
    let raw: String = NcmRadial_Layout();
    let parts: array<String> = StrSplit(raw, "|");
    let i: Int32 = 0;
    let at: Int32;
    let state: Int32;
    if ArraySize(parts) != 3 + 8 * 4 {
      this.refusedLayouts += 1;
      if this.refusedLayouts <= 3 {
        NcmRadial_Log("layout refused: " + ToString(ArraySize(parts)) + " fields, expected 35");
      }
      return;
    }
    this.layoutRevision = revision;
    this.title.SetText(NcmRadialField(parts[1]));
    this.hint.SetText(NcmRadialField(parts[2]));
    while i < 8 {
      at = 3 + i * 4;
      state = StringToInt(parts[at]);
      this.slotState[i] = state;
      this.slotName[i] = NcmRadialField(parts[at + 1]);
      this.slotDetail[i] = NcmRadialField(parts[at + 3]);
      this.cardLabel[i].SetText(this.slotName[i]);
      this.cardKey[i].SetText(NcmRadialField(parts[at + 2]));
      this.cards[i].SetVisible(state != 0);
      this.cards[i].SetOpacity(state == 2 ? 0.45 : 1.0);
      this.dots[i].SetVisible(state == 0);
      i += 1;
    }
    NcmRadial_Log("layout " + revision + " applied");
    this.lastFrame = "";            // redraw the selection against the new text
  }

  private func ApplySelection(selected: Int32, pointer: Float) -> Void {
    let i: Int32 = 0;
    let on: Bool;
    while i < 8 {
      on = i == selected && this.slotState[i] != 0;
      // Selected: a solid accent card with dark text -- unmistakable at a glance, not a tint shift.
      this.cardFill[i].SetTintColor(on ? NcmRadialAccent() : NcmRadialPanel());
      this.cardFill[i].SetOpacity(on ? 1.0 : 0.9);
      this.cardEdges[i].SetOpacity(on ? 1.0 : 0.35);
      this.cardLabel[i].SetTintColor(on ? NcmRadialPanel() : NcmRadialInk());
      this.cardKey[i].SetTintColor(on ? NcmRadialPanel() : NcmRadialDim());
      this.cards[i].SetScale(on ? new Vector2(1.1, 1.1) : new Vector2(1.0, 1.0));
      this.dots[i].SetOpacity(i == selected ? 0.9 : 0.45);
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
      this.detail.SetText(selected >= 0 ? "Open slot" : "Point at an option  ·  release to close");
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
