// NCM Scanner -- the reticle (`L197`).
//
// Drawn natively inside the vanilla crosshair container: a full-screen HUD layer that exists on foot and in
// vehicles, that OPEN//77 does not manage, and whose own children (the weapon crosshairs) this file never
// touches. The reticle is a child canvas of its own, visible only while vision is on.
//
// It draws what Lua says, read through `NcmScanner_Reticle()` as "revision|state|progress|title|detail" (`~`
// is an empty field, so `StrSplit` can never collapse one). With no feed it is a bare reticle: corner brackets
// and nothing claimed. Coordinates are the HUD's 3840x2160 space.
//
// 0.3.0 adds the vanilla scanner's two side panels, read through `NcmScanner_Panel()`:
//   * left, QUICKHACKS -- every chrome hack at once, the selected one highlighted, each row saying whether it
//     can be used on this target (vanilla's quickhack column, without RAM);
//   * right, the DATA panel -- the machine's name and class once this Driver knows it, who is driving it, and
//     what the Scanner knows about it.
module NcmVision

public static func NcmScannerField(value: String) -> String {
  return Equals(value, "~") ? "" : value;
}

public static func NcmScannerInk() -> HDRColor {
  return new HDRColor(0.94, 0.96, 0.98, 1.0);
}

public static func NcmScannerAccent() -> HDRColor {
  return new HDRColor(0.133, 0.847, 0.886, 1.0);   // NCM cyan: known, identified
}

public static func NcmScannerAmber() -> HDRColor {
  return new HDRColor(1.0, 0.72, 0.2, 1.0);        // unidentified, scanning
}

public static func NcmScannerRefused() -> HDRColor {
  return new HDRColor(0.95, 0.35, 0.3, 1.0);
}

public static func NcmScannerShade() -> HDRColor {
  return new HDRColor(0.02, 0.06, 0.07, 1.0);
}

public class NcmScannerReticle extends IScriptable {
  private let root: ref<inkCanvas>;
  private let frame: ref<inkCanvas>;
  private let corners: array<ref<inkRectangle>>;
  private let dot: ref<inkRectangle>;
  private let barBack: ref<inkRectangle>;
  private let barFill: ref<inkRectangle>;
  private let title: ref<inkText>;
  private let detail: ref<inkText>;
  private let revision: String;
  private let refused: Int32;
  // The side panels (0.3.0).
  private let listRoot: ref<inkCanvas>;
  private let rowBack: array<ref<inkRectangle>>;
  private let rowMark: array<ref<inkRectangle>>;
  private let rowLabel: array<ref<inkText>>;
  private let rowRight: array<ref<inkText>>;
  private let infoRoot: ref<inkCanvas>;
  private let infoTitle: ref<inkText>;
  private let infoSub: ref<inkText>;
  private let infoKey: array<ref<inkText>>;
  private let infoValue: array<ref<inkText>>;
  private let panelRefused: Int32;

  public func Build(parent: ref<inkCompoundWidget>) -> Void {
    let stage: ref<inkCanvas>;
    if !IsDefined(parent) {
      NcmScanner_Log("reticle host has no compound root; nothing drawn");
      return;
    }
    this.root = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.root.SetName(n"NcmScannerReticle");
    this.root.SetAnchor(inkEAnchor.Fill);
    this.root.SetVisible(false);

    // A 900x700 stage centred on the screen; the bracket square is centred at (450, 300).
    stage = this.root.AddChild(n"inkCanvasWidget") as inkCanvas;
    stage.SetName(n"stage");
    stage.SetAnchor(inkEAnchor.Centered);
    stage.SetAnchorPoint(new Vector2(0.5, 0.5));
    stage.SetMargin(0.0, 200.0, 0.0, 0.0);
    stage.SetSize(900.0, 700.0);

    this.frame = stage.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.frame.SetName(n"frame");
    this.frame.SetMargin(330.0, 180.0, 0.0, 0.0);
    this.frame.SetSize(240.0, 240.0);
    this.frame.SetRenderTransformPivot(new Vector2(0.5, 0.5));
    this.Corners(240.0, 56.0, 6.0);

    this.dot = this.Rect(stage, n"dot", 445.0, 295.0, 10.0, 10.0);

    this.barBack = this.Rect(stage, n"barBack", 300.0, 452.0, 300.0, 8.0);
    this.barBack.SetOpacity(0.25);
    this.barFill = this.Rect(stage, n"barFill", 300.0, 452.0, 0.0, 8.0);

    this.title = this.Text(stage, n"title", 52, 0.0, 480.0, 900.0, 70.0);
    this.detail = this.Text(stage, n"detail", 34, 0.0, 552.0, 900.0, 50.0);
    this.Paint(0, 0.0, "", "");
    this.BuildPanels();
  }

  // A 2800x700 canvas placed exactly like the stage, so the bracket centre is (1400, 300) here too.
  private func BuildPanels() -> Void {
    let wide: ref<inkCanvas> = this.root.AddChild(n"inkCanvasWidget") as inkCanvas;
    let header: ref<inkText>;
    let back: ref<inkRectangle>;
    let rule: ref<inkRectangle>;
    let x: Float;
    let y: Float;
    let i: Int32 = 0;
    wide.SetName(n"panels");
    wide.SetAnchor(inkEAnchor.Centered);
    wide.SetAnchorPoint(new Vector2(0.5, 0.5));
    wide.SetMargin(0.0, 200.0, 0.0, 0.0);
    wide.SetSize(2800.0, 700.0);

    // QUICKHACKS, left of the brackets.
    x = 520.0;
    this.listRoot = wide.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.listRoot.SetName(n"quickhacks");
    this.listRoot.SetMargin(x, 0.0, 0.0, 0.0);
    this.listRoot.SetSize(640.0, 800.0);
    header = this.TextAt(this.listRoot, n"header", 30, 0.0, 110.0, 640.0, 50.0, textHorizontalAlignment.Left);
    header.SetText("QUICKHACKS");
    header.SetTintColor(NcmScannerAccent());
    rule = this.Rect(this.listRoot, n"headerRule", 0.0, 160.0, 640.0, 3.0);
    rule.SetTintColor(NcmScannerAccent());
    rule.SetOpacity(0.6);
    while i < 12 {
      y = 172.0 + Cast<Float>(i) * 50.0;
      back = this.Rect(this.listRoot, n"rowBack", 0.0, y, 640.0, 44.0);
      back.SetTintColor(NcmScannerShade());
      back.SetOpacity(0.6);
      ArrayPush(this.rowBack, back);
      ArrayPush(this.rowMark, this.Rect(this.listRoot, n"rowMark", 0.0, y, 8.0, 44.0));
      ArrayPush(this.rowLabel, this.TextAt(this.listRoot, n"rowLabel", 32, 26.0, y, 400.0, 44.0, textHorizontalAlignment.Left));
      ArrayPush(this.rowRight, this.TextAt(this.listRoot, n"rowRight", 26, 400.0, y, 222.0, 44.0, textHorizontalAlignment.Right));
      i += 1;
    }
    this.listRoot.SetVisible(false);

    // DATA, right of the brackets.
    x = 1660.0;
    this.infoRoot = wide.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.infoRoot.SetName(n"data");
    this.infoRoot.SetMargin(x, 0.0, 0.0, 0.0);
    this.infoRoot.SetSize(660.0, 800.0);
    header = this.TextAt(this.infoRoot, n"header", 30, 0.0, 110.0, 660.0, 50.0, textHorizontalAlignment.Left);
    header.SetText("SCAN DATA");
    header.SetTintColor(NcmScannerAccent());
    rule = this.Rect(this.infoRoot, n"headerRule", 0.0, 160.0, 660.0, 3.0);
    rule.SetTintColor(NcmScannerAccent());
    rule.SetOpacity(0.6);
    back = this.Rect(this.infoRoot, n"back", 0.0, 172.0, 660.0, 400.0);
    back.SetTintColor(NcmScannerShade());
    back.SetOpacity(0.6);
    this.infoTitle = this.TextAt(this.infoRoot, n"title", 44, 24.0, 182.0, 620.0, 60.0, textHorizontalAlignment.Left);
    this.infoSub = this.TextAt(this.infoRoot, n"sub", 26, 24.0, 240.0, 620.0, 40.0, textHorizontalAlignment.Left);
    this.infoSub.SetTintColor(NcmScannerAccent());
    i = 0;
    while i < 6 {
      y = 300.0 + Cast<Float>(i) * 44.0;
      ArrayPush(this.infoKey, this.TextAt(this.infoRoot, n"key", 24, 24.0, y, 220.0, 40.0, textHorizontalAlignment.Left));
      ArrayPush(this.infoValue, this.TextAt(this.infoRoot, n"value", 28, 250.0, y, 390.0, 40.0, textHorizontalAlignment.Left));
      this.infoKey[i].SetOpacity(0.6);
      i += 1;
    }
    this.infoRoot.SetVisible(false);
  }

  private func TextAt(parent: ref<inkCompoundWidget>, name: CName, size: Int32, x: Float, y: Float, w: Float, h: Float, align: textHorizontalAlignment) -> ref<inkText> {
    let label: ref<inkText> = this.Text(parent, name, size, x, y, w, h);
    label.SetHorizontalAlignment(align);
    return label;
  }

  private func Rect(parent: ref<inkCompoundWidget>, name: CName, x: Float, y: Float, w: Float, h: Float) -> ref<inkRectangle> {
    let rect: ref<inkRectangle> = parent.AddChild(n"inkRectangleWidget") as inkRectangle;
    rect.SetName(name);
    rect.SetMargin(x, y, 0.0, 0.0);
    rect.SetSize(w, h);
    rect.SetTintColor(NcmScannerInk());
    return rect;
  }

  private func Text(parent: ref<inkCompoundWidget>, name: CName, size: Int32, x: Float, y: Float, w: Float, h: Float) -> ref<inkText> {
    let label: ref<inkText> = parent.AddChild(n"inkTextWidget") as inkText;
    label.SetName(name);
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    label.SetFontSize(size);
    label.SetTintColor(NcmScannerInk());
    label.SetFitToContent(false);
    label.SetMargin(x, y, 0.0, 0.0);
    label.SetSize(w, h);
    label.SetHorizontalAlignment(textHorizontalAlignment.Center);
    label.SetVerticalAlignment(textVerticalAlignment.Center);
    return label;
  }

  // Four L-shaped corners, two bars each, inside `frame` so the whole bracket scales and recolours as one.
  private func Corners(size: Float, arm: Float, t: Float) -> Void {
    let far: Float = size - arm;
    let edge: Float = size - t;
    ArrayPush(this.corners, this.Rect(this.frame, n"tlH", 0.0, 0.0, arm, t));
    ArrayPush(this.corners, this.Rect(this.frame, n"tlV", 0.0, 0.0, t, arm));
    ArrayPush(this.corners, this.Rect(this.frame, n"trH", far, 0.0, arm, t));
    ArrayPush(this.corners, this.Rect(this.frame, n"trV", edge, 0.0, t, arm));
    ArrayPush(this.corners, this.Rect(this.frame, n"blH", 0.0, edge, arm, t));
    ArrayPush(this.corners, this.Rect(this.frame, n"blV", 0.0, far, t, arm));
    ArrayPush(this.corners, this.Rect(this.frame, n"brH", far, edge, arm, t));
    ArrayPush(this.corners, this.Rect(this.frame, n"brV", edge, far, t, arm));
  }

  public func Show(on: Bool) -> Void {
    if !IsDefined(this.root) {
      return;
    }
    this.root.SetVisible(on);
    if on {
      this.revision = "";
      this.Apply();
    }
  }

  // Called from the vision tick, 20 Hz, only while vision is on.
  public func Apply() -> Void {
    if !IsDefined(this.root) {
      return;
    }
    let raw: String = NcmScanner_Reticle();
    let parts: array<String> = StrSplit(raw, "|");
    if ArraySize(parts) != 5 {
      this.refused += 1;
      if this.refused <= 3 {
        NcmScanner_Log("reticle frame refused: " + ToString(ArraySize(parts)) + " fields, expected 5");
      }
      return;
    }
    if Equals(parts[0], this.revision) {
      return;
    }
    this.revision = parts[0];
    this.Paint(StringToInt(parts[1]), StringToFloat(parts[2]), NcmScannerField(parts[3]), NcmScannerField(parts[4]));
    this.ApplyPanels();
  }

  // "revision|selected|rows|infoTitle|infoSub|info"; rows "state`label`right" joined by '^', info "key`value".
  private func ApplyPanels() -> Void {
    let parts: array<String>;
    let rows: array<String>;
    let cells: array<String>;
    let selected: Int32;
    let state: Int32;
    let color: HDRColor;
    let dim: Float;
    let i: Int32 = 0;
    if !IsDefined(this.listRoot) || !IsDefined(this.infoRoot) {
      return;
    }
    parts = StrSplit(NcmScanner_Panel(), "|");
    if ArraySize(parts) != 6 {
      this.panelRefused += 1;
      if this.panelRefused <= 3 {
        NcmScanner_Log("panel frame refused: " + ToString(ArraySize(parts)) + " fields, expected 6");
      }
      return;
    }
    selected = StringToInt(parts[1]);
    if Equals(parts[2], "~") {
      ArrayClear(rows);
    } else {
      rows = StrSplit(parts[2], "^");
    }
    this.listRoot.SetVisible(ArraySize(rows) > 0);
    while i < ArraySize(this.rowBack) {
      if i < ArraySize(rows) {
        cells = StrSplit(rows[i], "`");
        state = ArraySize(cells) > 0 ? StringToInt(cells[0]) : 0;
        color = NcmScannerInk();
        dim = 1.0;
        if state == 1 || state == 4 {
          dim = 0.4;
        } else {
          if state == 2 || state == 3 {
            color = NcmScannerAmber();
          } else {
            if state == 5 {
              color = NcmScannerRefused();
            }
          }
        }
        if i == selected {
          this.rowBack[i].SetTintColor(NcmScannerAccent());
          this.rowBack[i].SetOpacity(0.3);
          this.rowMark[i].SetVisible(true);
          this.rowMark[i].SetTintColor(state == 0 ? NcmScannerAccent() : color);
          if state == 0 {
            color = NcmScannerAccent();
          }
        } else {
          this.rowBack[i].SetTintColor(NcmScannerShade());
          this.rowBack[i].SetOpacity(0.6);
          this.rowMark[i].SetVisible(state == 3 || state == 5);
          this.rowMark[i].SetTintColor(color);
        }
        this.rowLabel[i].SetText(ArraySize(cells) > 1 ? cells[1] : "");
        this.rowLabel[i].SetTintColor(color);
        this.rowLabel[i].SetOpacity(dim);
        this.rowRight[i].SetText(ArraySize(cells) > 2 ? cells[2] : "");
        this.rowRight[i].SetTintColor(color);
        this.rowRight[i].SetOpacity(dim * 0.85);
        this.rowBack[i].SetVisible(true);
        this.rowLabel[i].SetVisible(true);
        this.rowRight[i].SetVisible(true);
      } else {
        this.rowBack[i].SetVisible(false);
        this.rowMark[i].SetVisible(false);
        this.rowLabel[i].SetVisible(false);
        this.rowRight[i].SetVisible(false);
      }
      i += 1;
    }

    this.infoRoot.SetVisible(!Equals(parts[3], "~"));
    this.infoTitle.SetText(NcmScannerField(parts[3]));
    this.infoSub.SetText(NcmScannerField(parts[4]));
    if Equals(parts[5], "~") {
      ArrayClear(rows);
    } else {
      rows = StrSplit(parts[5], "^");
    }
    i = 0;
    while i < ArraySize(this.infoKey) {
      if i < ArraySize(rows) {
        cells = StrSplit(rows[i], "`");
        this.infoKey[i].SetText(ArraySize(cells) > 0 ? cells[0] : "");
        this.infoValue[i].SetText(ArraySize(cells) > 1 ? cells[1] : "");
        this.infoKey[i].SetVisible(true);
        this.infoValue[i].SetVisible(true);
      } else {
        this.infoKey[i].SetVisible(false);
        this.infoValue[i].SetVisible(false);
      }
      i += 1;
    }
  }

  // States (the DLL's `Reticle` enum): 0 bare, 1 searching, 2 unknown, 3 known, 4 scanning, 5 identified,
  // 6 refused.
  private func Paint(state: Int32, progress: Float, title: String, detail: String) -> Void {
    let color: HDRColor = NcmScannerInk();
    let scale: Float = 1.0;
    let opacity: Float = 0.55;
    let i: Int32 = 0;
    if state == 2 || state == 4 {
      color = NcmScannerAmber();
      scale = 0.8;
      opacity = 1.0;
    } else {
      if state == 3 || state == 5 {
        color = NcmScannerAccent();
        scale = 0.8;
        opacity = 1.0;
      } else {
        if state == 6 {
          color = NcmScannerRefused();
          opacity = 0.9;
        }
      }
    }
    while i < ArraySize(this.corners) {
      this.corners[i].SetTintColor(color);
      i += 1;
    }
    this.frame.SetScale(new Vector2(scale, scale));
    this.frame.SetOpacity(opacity);
    this.dot.SetTintColor(color);
    this.dot.SetOpacity(opacity);
    this.barFill.SetTintColor(color);
    this.barBack.SetTintColor(color);
    this.barFill.SetSize(300.0 * ClampF(progress, 0.0, 1.0), 8.0);
    this.barFill.SetVisible(state == 4 || state == 5);
    this.barBack.SetVisible(state == 4);
    this.title.SetText(title);
    this.title.SetTintColor(color);
    this.detail.SetText(detail);
    this.detail.SetTintColor(NcmScannerInk());
    this.detail.SetOpacity(0.8);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The host
// ---------------------------------------------------------------------------------------------------------------

@addField(gameuiCrosshairContainerController)
private let ncmScannerReticle: ref<NcmScannerReticle>;

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmVisionSystem>;
  if !IsDefined(this.ncmScannerReticle) && IsDefined(owner) {
    this.ncmScannerReticle = new NcmScannerReticle();
    this.ncmScannerReticle.Build(this.GetRootCompoundWidget());
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmVision.NcmVisionSystem") as NcmVisionSystem;
    if IsDefined(system) {
      system.SetReticle(this.ncmScannerReticle);
      NcmScanner_Log("reticle attached to gameuiCrosshairContainerController");
    } else {
      NcmScanner_Log("reticle built but NcmVisionSystem not found; it will not show");
    }
  }
  return result;
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnUninitialize() -> Bool {
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmVisionSystem>;
  if IsDefined(owner) {
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmVision.NcmVisionSystem") as NcmVisionSystem;
    if IsDefined(system) {
      system.SetReticle(null);
    }
  }
  this.ncmScannerReticle = null;
  return wrappedMethod();
}
