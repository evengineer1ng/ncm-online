// NCM Scanner -- the reticle (`L197`).
//
// Drawn natively inside the vanilla crosshair container: a full-screen HUD layer that exists on foot and in
// vehicles, that OPEN//77 does not manage, and whose own children (the weapon crosshairs) this file never
// touches. The reticle is a child canvas of its own, visible only while vision is on.
//
// It draws what Lua says, read through `NcmScanner_Reticle()` as "revision|state|progress|title|detail" (`~`
// is an empty field, so `StrSplit` can never collapse one). With no feed it is a bare reticle: corner brackets
// and nothing claimed. Coordinates are the HUD's 3840x2160 space.
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
