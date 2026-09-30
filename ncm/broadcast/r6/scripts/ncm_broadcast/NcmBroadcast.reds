// NCM Broadcast -- race presentation drawn natively in the HUD (L235). No WebUI page is drawn.
//
//   * names over race cars that are not players (Paddock drivers): a plate above each car -- position chip, name,
//     team -- projected every frame with the engine's own camera (CameraSystem.ProjectPoint). They are deliberately
//     not player nameplates: no card, no avatar; an amber chip and a name, so a spectator can tell who is who.
//   * the opt-in timing tower: a column top-left, redrawn only when the feed changes.
//
// `ncm_broadcast.dll` holds what to draw (fed by the `ncm_broadcast` resource over loopback); this file only draws.
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only -- nothing from OPEN//77, NCM Lua or any other mod;
//   * no feed, no work: a 4 Hz idle poll of three natives; per-frame only while names are listed.
module NcmBroadcast

public class NcmBroadcastTick extends DelayCallback {
  public let system: wref<NcmBroadcastSystem>;
  public let generation: Int32;

  public func Call() -> Void {
    let system: ref<NcmBroadcastSystem> = this.system;
    if IsDefined(system) {
      system.Tick(this.generation);
    }
  }
}

public class NcmBroadcastSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_generation: Int32;
  private let m_hud: wref<NcmBroadcastHud>;

  public func SetHud(hud: ref<NcmBroadcastHud>) -> Void {
    this.m_hud = hud;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.m_player = player;
    this.m_generation += 1;
    this.Schedule(0.5, false);
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.m_generation += 1;
    this.m_player = null;
  }

  private func Schedule(delay: Float, nextFrame: Bool) -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let tick: ref<NcmBroadcastTick> = new NcmBroadcastTick();
    tick.system = this;
    tick.generation = this.m_generation;
    if nextFrame {
      GameInstance.GetDelaySystem(player.GetGame()).DelayCallbackNextFrame(tick);
    } else {
      GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(tick, delay, false);
    }
  }

  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation {
      return;
    }
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let hud: ref<NcmBroadcastHud> = this.m_hud;
    let count: Int32 = NcmBroadcast_LabelCount();
    if IsDefined(hud) {
      hud.ApplyView(NcmBroadcast_View());
      hud.ApplyTower(NcmBroadcast_Tower());
      hud.UpdateLabels(player.GetGame(), count);
    }
    if count > 0 {
      this.Schedule(0.0, true);
    } else {
      this.Schedule(0.25, false);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------

public class NcmBroadcastPlate extends IScriptable {
  public let root: ref<inkCanvas>;
  public let accent: ref<inkRectangle>;
  public let chip: ref<inkText>;
  public let title: ref<inkText>;
  public let sub: ref<inkText>;
  public let shown: String;
}

public class NcmBroadcastHud extends IScriptable {
  private let root: ref<inkCompoundWidget>;
  private let layer: ref<inkCanvas>;
  private let plates: array<ref<NcmBroadcastPlate>>;
  private let tower: ref<inkCanvas>;
  private let towerTitle: ref<inkText>;
  private let towerSub: ref<inkText>;
  private let rowBands: array<ref<inkRectangle>>;
  private let rowPos: array<ref<inkText>>;
  private let rowName: array<ref<inkText>>;
  private let rowGap: array<ref<inkText>>;
  private let towerRev: String;
  private let viewRev: String;
  private let range: Float;
  private let scale: Float;
  private let projX: Float;
  private let projY: Float;
  private let lift: Float;
  private let calibrated: Bool;

  public func Build(parent: ref<inkCompoundWidget>) -> Void {
    if !IsDefined(parent) {
      NcmBroadcast_Log("hud host has no compound root; nothing drawn");
      return;
    }
    this.root = parent;
    this.range = 250.0;
    this.scale = 1.0;
    this.projX = 1920.0;
    this.projY = 1080.0;
    this.lift = 1.9;
    this.layer = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.layer.SetName(n"NcmBroadcastNames");
    this.layer.SetAnchor(inkEAnchor.Fill);
    this.BuildTower(parent);
  }

  private func Text(host: ref<inkCompoundWidget>, name: CName, size: Int32, x: Float, y: Float, w: Float, h: Float) -> ref<inkText> {
    let label: ref<inkText> = host.AddChild(n"inkTextWidget") as inkText;
    label.SetName(name);
    label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily", n"Medium");
    label.SetFontSize(size);
    label.SetFitToContent(false);
    label.SetMargin(x, y, 0.0, 0.0);
    label.SetSize(w, h);
    label.SetHorizontalAlignment(textHorizontalAlignment.Left);
    label.SetVerticalAlignment(textVerticalAlignment.Center);
    label.SetTintColor(new HDRColor(0.94, 0.96, 0.98, 1.0));
    return label;
  }

  private func Rect(host: ref<inkCompoundWidget>, name: CName, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
    let r: ref<inkRectangle> = host.AddChild(n"inkRectangleWidget") as inkRectangle;
    r.SetName(name);
    r.SetMargin(x, y, 0.0, 0.0);
    r.SetSize(w, h);
    r.SetTintColor(color);
    r.SetOpacity(opacity);
    return r;
  }

  // ------------------------------------------------------------------------------------------------ calibration

  public func ApplyView(feed: String) -> Void {
    let f: array<String> = StrSplit(feed, "|");
    if ArraySize(f) != 8 || Equals(f[0], this.viewRev) {
      return;
    }
    this.viewRev = f[0];
    this.range = StringToFloat(f[1]);
    this.scale = StringToFloat(f[2]);
    this.projX = StringToFloat(f[3]);
    this.projY = StringToFloat(f[4]);
    this.lift = StringToFloat(f[5]);
    if IsDefined(this.tower) {
      this.tower.SetMargin(StringToFloat(f[6]), StringToFloat(f[7]), 0.0, 0.0);
    }
  }

  // ----------------------------------------------------------------------------------------------------- names

  private func Plate(i: Int32) -> ref<NcmBroadcastPlate> {
    while ArraySize(this.plates) <= i {
      let p: ref<NcmBroadcastPlate> = new NcmBroadcastPlate();
      p.root = this.layer.AddChild(n"inkCanvasWidget") as inkCanvas;
      p.root.SetName(n"plate");
      p.root.SetAnchor(inkEAnchor.Centered);
      p.root.SetAnchorPoint(new Vector2(0.5, 1.0));
      p.root.SetSize(470.0, 76.0);
      p.root.SetVisible(false);
      this.Rect(p.root, n"band", 0.0, 0.0, 470.0, 76.0, new HDRColor(0.03, 0.03, 0.05, 1.0), 0.55);
      p.accent = this.Rect(p.root, n"accent", 0.0, 0.0, 6.0, 76.0, new HDRColor(1.0, 0.72, 0.2, 1.0), 1.0);
      p.chip = this.Text(p.root, n"chip", 36, 16.0, 0.0, 86.0, 76.0);
      p.chip.SetTintColor(new HDRColor(1.0, 0.72, 0.2, 1.0));
      p.title = this.Text(p.root, n"title", 34, 104.0, 2.0, 360.0, 42.0);
      p.sub = this.Text(p.root, n"sub", 24, 104.0, 42.0, 360.0, 30.0);
      p.sub.SetTintColor(new HDRColor(0.62, 0.66, 0.72, 1.0));
      ArrayPush(this.plates, p);
    }
    return this.plates[i];
  }

  private func Accent(kind: Int32) -> HDRColor {
    if kind == 1 { return new HDRColor(1.0, 0.84, 0.3, 1.0); }      // leader
    if kind == 2 { return new HDRColor(0.45, 0.9, 0.55, 1.0); }     // finished
    if kind == 3 { return new HDRColor(0.5, 0.5, 0.55, 1.0); }      // out
    return new HDRColor(1.0, 0.72, 0.2, 1.0);
  }

  public func UpdateLabels(game: GameInstance, count: Int32) -> Void {
    if !IsDefined(this.layer) {
      return;
    }
    let i: Int32 = 0;
    if count > 0 {
      let camera: ref<CameraSystem> = GameInstance.GetCameraSystem(game);
      let eye: Transform;
      camera.GetActiveCameraWorldTransform(eye);
      let forward: Vector4 = camera.GetActiveCameraForward();
      while i < count {
        let plate: ref<NcmBroadcastPlate> = this.Plate(i);
        let target: ref<GameObject> = GameInstance.FindEntityByID(game, NcmBroadcast_LabelEntity(i)) as GameObject;
        let shown: Bool = false;
        if IsDefined(target) {
          let at: Vector4 = target.GetWorldPosition();
          at.Z += this.lift;
          let d: Vector4 = at - eye.position;
          let dist: Float = Vector4.Length(d);
          if dist <= this.range && Vector4.Dot(d, forward) > 0.0 {
            let p: Vector4 = camera.ProjectPoint(at);
            if !this.calibrated {
              this.calibrated = true;
              NcmBroadcast_Log("calibration: first projection " + ToString(p.X) + ", " + ToString(p.Y) + " at " + ToString(dist) + " m; hud root "
                + ToString(this.root.GetSize().X) + " x " + ToString(this.root.GetSize().Y));
            }
            let text: String = NcmBroadcast_LabelText(i);
            if !Equals(text, plate.shown) {
              plate.shown = text;
              let f: array<String> = StrSplit(text, "|");
              if ArraySize(f) == 4 {
                plate.title.SetText(Equals(f[0], "~") ? "" : f[0]);
                plate.sub.SetText(Equals(f[1], "~") ? "" : f[1]);
                plate.chip.SetText(Equals(f[2], "~") ? "" : f[2]);
                plate.accent.SetTintColor(this.Accent(StringToInt(f[3])));
              }
            }
            let s: Float = MinF(1.0, MaxF(0.45, 35.0 / MaxF(1.0, dist))) * this.scale;
            plate.root.SetScale(new Vector2(s, s));
            plate.root.SetTranslation(new Vector2(p.X * this.projX, -p.Y * this.projY));
            plate.root.SetOpacity(dist > this.range * 0.8 ? 0.6 : 1.0);
            shown = true;
          }
        }
        plate.root.SetVisible(shown);
        i += 1;
      }
    }
    while i < ArraySize(this.plates) {
      this.plates[i].root.SetVisible(false);
      i += 1;
    }
  }

  // ----------------------------------------------------------------------------------------------------- tower

  private func BuildTower(parent: ref<inkCompoundWidget>) -> Void {
    this.tower = parent.AddChild(n"inkCanvasWidget") as inkCanvas;
    this.tower.SetName(n"NcmBroadcastTower");
    this.tower.SetAnchor(inkEAnchor.TopLeft);
    this.tower.SetMargin(60.0, 330.0, 0.0, 0.0);
    this.tower.SetSize(560.0, 1200.0);
    this.tower.SetVisible(false);
    this.Rect(this.tower, n"head", 0.0, 0.0, 560.0, 92.0, new HDRColor(0.03, 0.03, 0.05, 1.0), 0.8);
    this.Rect(this.tower, n"headEdge", 0.0, 0.0, 560.0, 6.0, new HDRColor(1.0, 0.72, 0.2, 1.0), 1.0);
    this.towerTitle = this.Text(this.tower, n"title", 32, 18.0, 8.0, 530.0, 44.0);
    this.towerTitle.SetTintColor(new HDRColor(1.0, 0.72, 0.2, 1.0));
    this.towerSub = this.Text(this.tower, n"sub", 24, 18.0, 52.0, 530.0, 34.0);
    this.towerSub.SetTintColor(new HDRColor(0.62, 0.66, 0.72, 1.0));
    let i: Int32 = 0;
    while i < 24 {
      let y: Float = 96.0 + Cast<Float>(i) * 44.0;
      ArrayPush(this.rowBands, this.Rect(this.tower, n"band", 0.0, y, 560.0, 42.0, new HDRColor(0.03, 0.03, 0.05, 1.0), 0.62));
      ArrayPush(this.rowPos, this.Text(this.tower, n"pos", 28, 14.0, y, 56.0, 42.0));
      ArrayPush(this.rowName, this.Text(this.tower, n"name", 28, 76.0, y, 320.0, 42.0));
      let gap: ref<inkText> = this.Text(this.tower, n"gap", 26, 390.0, y, 156.0, 42.0);
      gap.SetHorizontalAlignment(textHorizontalAlignment.Right);
      ArrayPush(this.rowGap, gap);
      i += 1;
    }
  }

  public func ApplyTower(feed: String) -> Void {
    if !IsDefined(this.tower) {
      return;
    }
    let f: array<String> = StrSplit(feed, "|");
    if ArraySize(f) != 5 || Equals(f[0], this.towerRev) {
      return;
    }
    this.towerRev = f[0];
    if !Equals(f[1], "1") {
      this.tower.SetVisible(false);
      return;
    }
    this.towerTitle.SetText(Equals(f[2], "~") ? "" : f[2]);
    this.towerSub.SetText(Equals(f[3], "~") ? "" : f[3]);
    let rows: Int32 = StringToInt(f[4]);
    let i: Int32 = 0;
    while i < ArraySize(this.rowPos) {
      let visible: Bool = i < rows;
      this.rowBands[i].SetVisible(visible);
      this.rowPos[i].SetVisible(visible);
      this.rowName[i].SetVisible(visible);
      this.rowGap[i].SetVisible(visible);
      if visible {
        let r: array<String> = StrSplit(NcmBroadcast_TowerRow(i), "|");
        if ArraySize(r) == 4 {
          this.rowPos[i].SetText(Equals(r[0], "~") ? "" : r[0]);
          this.rowName[i].SetText(Equals(r[1], "~") ? "" : r[1]);
          this.rowGap[i].SetText(Equals(r[2], "~") ? "" : r[2]);
          let flag: String = r[3];
          let band: HDRColor = new HDRColor(0.03, 0.03, 0.05, 1.0);
          let ink: HDRColor = new HDRColor(0.94, 0.96, 0.98, 1.0);
          if Equals(flag, "me") { band = new HDRColor(0.45, 0.3, 0.05, 1.0); }
          if Equals(flag, "phys") { band = new HDRColor(0.05, 0.22, 0.28, 1.0); }
          if Equals(flag, "fin") { ink = new HDRColor(0.55, 0.92, 0.6, 1.0); }
          if Equals(flag, "out") { ink = new HDRColor(0.5, 0.5, 0.55, 1.0); }
          this.rowBands[i].SetTintColor(band);
          this.rowName[i].SetTintColor(ink);
          this.rowPos[i].SetTintColor(i == 0 ? new HDRColor(1.0, 0.84, 0.3, 1.0) : ink);
          this.rowGap[i].SetTintColor(ink);
        }
      }
      i += 1;
    }
    this.tower.SetVisible(true);
  }
}

@addField(gameuiCrosshairContainerController)
private let ncmBroadcastHud: ref<NcmBroadcastHud>;

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnInitialize() -> Bool {
  let result: Bool = wrappedMethod();
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmBroadcastSystem>;
  if !IsDefined(this.ncmBroadcastHud) && IsDefined(owner) {
    this.ncmBroadcastHud = new NcmBroadcastHud();
    this.ncmBroadcastHud.Build(this.GetRootCompoundWidget());
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmBroadcast.NcmBroadcastSystem") as NcmBroadcastSystem;
    if IsDefined(system) {
      system.SetHud(this.ncmBroadcastHud);
      NcmBroadcast_Log("hud attached to gameuiCrosshairContainerController");
    }
  }
  return result;
}

@wrapMethod(gameuiCrosshairContainerController)
protected cb func OnUninitialize() -> Bool {
  let owner: ref<GameObject> = this.GetPlayerControlledObject();
  let system: ref<NcmBroadcastSystem>;
  if IsDefined(owner) {
    system = GameInstance.GetScriptableSystemsContainer(owner.GetGame()).Get(n"NcmBroadcast.NcmBroadcastSystem") as NcmBroadcastSystem;
    if IsDefined(system) {
      system.SetHud(null);
    }
  }
  this.ncmBroadcastHud = null;
  return wrappedMethod();
}
