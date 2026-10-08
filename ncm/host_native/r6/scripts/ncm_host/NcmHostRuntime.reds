// NCM Host -- the runtime: the game itself drives NCM (L340 phase 2; no CET).
//
// **This file must never declare a `module`** (KB-182): it calls NcmHost_Call, a native matched by its global name.
//
// What CET's init.lua + game/cet.lua did, done natively:
//   * a save finishes loading (OnPlayerAttach) -> `session`: NCM mounts the tape set in Mod Settings ("Tape in play",
//     NcmHostSettings.reds), or stays off and says where to set one; a change in Mod Settings applies at once
//   * every frame -> `frame`: V's position, heading and car go in; the host's game commands come back as lines
//     (`kind|field|field...`, '~' = empty) and are performed here: toasts, teleport, the GPS waypoint, a car into
//     V's garage, and the Race Week line for the HUD (NcmHostHud.reds)
//   * the session ends (OnPlayerDetach) -> `leave`: the tape is unmounted
// Native code cannot call a scripted function, so the direction is always script -> native, polled (NCM Radial's
// rule), and the tick is always DelayCallback (NCM Radial's lesson: DelayCallbackNextFrame chains stopped firing).

public class NcmHostTick extends DelayCallback {
  public let runtime: wref<NcmHostRuntime>;
  public let generation: Int32;

  public func Call() -> Void {
    if IsDefined(this.runtime) {
      this.runtime.Tick(this.generation);
    }
  }
}

public static func NcmHostField(value: String) -> String {
  return Equals(value, "~") ? "" : value;
}

public class NcmHostRuntime extends ScriptableSystem {
  private let m_generation: Int32;
  private let m_attached: Bool;
  private let m_hasWaypoint: Bool;
  private let m_waypoint: NewMappinID;
  private let m_hudLabel: String;
  private let m_hudRemaining: String;
  private let m_mounted: Bool;
  private let m_settings: ref<NcmHostSettings>;

  public static func Get(game: GameInstance) -> ref<NcmHostRuntime> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"NcmHostRuntime") as NcmHostRuntime;
  }

  public func HudLabel() -> String { return this.m_hudLabel; }
  public func HudRemaining() -> String { return this.m_hudRemaining; }
  public func IsMounted() -> Bool { return this.m_mounted; }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    if !NcmHost_Ready() {
      return;
    }
    this.m_generation += 1;
    this.m_attached = true;
    if !IsDefined(this.m_settings) {
      this.m_settings = new NcmHostSettings();
      this.m_settings.runtime = this;
      this.m_settings.Listen();
    }
    NcmHost_Call("boot", "{}");
    this.Perform(NcmHost_Call("session", "{\"select\":" + IntToString(this.m_settings.tape) + "}"));
    this.Schedule();
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.m_generation += 1;
    this.m_attached = false;
    this.ClearWaypoint();
    this.m_hudLabel = "";
    this.m_hudRemaining = "";
    this.m_mounted = false;
    if NcmHost_Ready() {
      NcmHost_Call("leave", "{}");
    }
  }

  //- Mod Settings changed "Tape in play" (Apply): use it now if a session runs; otherwise the next load reads it.
  public func OnSettingsChanged() -> Void {
    if !this.m_attached || !IsDefined(this.m_settings) {
      return;
    }
    let answer: String = NcmHost_Call("select", "{\"select\":" + IntToString(this.m_settings.tape) + "}");
    this.Perform(answer);
    if !this.m_mounted {
      this.ClearWaypoint();
      this.m_hudLabel = "";
      this.m_hudRemaining = "";
    }
  }

  private func Schedule() -> Void {
    let tick: ref<NcmHostTick> = new NcmHostTick();
    tick.runtime = this;
    tick.generation = this.m_generation;
    // ~30 Hz: the host's resources run on their own clock; this only carries V in and the commands out
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(tick, 0.033, false);
  }

  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation || !this.m_attached {
      return;
    }
    if this.m_mounted {
      this.Perform(NcmHost_Call("frame", this.PlayerState()));
    }
    this.Schedule();
  }

  private func PlayerState() -> String {
    let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return "{\"budgetMs\":3}";
    }
    let pos: Vector4 = player.GetWorldPosition();
    let json: String = "{\"budgetMs\":3,\"player\":{\"x\":" + FloatToString(pos.X) + ",\"y\":" + FloatToString(pos.Y) +
      ",\"z\":" + FloatToString(pos.Z) + ",\"heading\":" + FloatToString(player.GetWorldYaw());
    let vehicle: wref<VehicleObject> = GetMountedVehicle(player);
    if IsDefined(vehicle) {
      json += ",\"vehicle\":{\"record\":\"" + TDBID.ToStringDEBUG(vehicle.GetRecordID()) + "\",\"appearance\":\"" +
        NameToString(vehicle.GetCurrentAppearanceName()) + "\"}";
    }
    return json + "}}";
  }

  // -------------------------------------------------------------------------------------------------- commands
  private func Perform(answer: String) -> Void {
    if StrLen(answer) == 0 || StrBeginsWith(answer, "{") {
      return;   // a JSON answer is an error from the dispatcher; nothing to perform
    }
    let lines: array<String> = StrSplit(answer, "\n");
    for line in lines {
      let f: array<String> = StrSplit(line, "|");
      let kind: String = ArraySize(f) > 0 ? f[0] : "";
      if Equals(kind, "state") && ArraySize(f) >= 2 {
        this.m_mounted = Equals(f[1], "mounted");
      } else if Equals(kind, "hud") && ArraySize(f) >= 3 {
        this.m_hudLabel = NcmHostField(f[1]);
        this.m_hudRemaining = NcmHostField(f[2]);
      } else if Equals(kind, "toast") && ArraySize(f) >= 4 {
        this.Toast(NcmHostField(f[1]), NcmHostField(f[2]), StringToFloat(f[3]) / 1000.0);
      } else if Equals(kind, "teleport") && ArraySize(f) >= 5 {
        this.Teleport(StringToFloat(f[1]), StringToFloat(f[2]), StringToFloat(f[3]), StringToFloat(f[4]));
      } else if Equals(kind, "waypoint") && ArraySize(f) >= 2 {
        if Equals(f[1], "clear") || ArraySize(f) < 4 {
          this.ClearWaypoint();
        } else {
          this.SetWaypoint(StringToFloat(f[1]), StringToFloat(f[2]), StringToFloat(f[3]));
        }
      } else if Equals(kind, "givecar") && ArraySize(f) >= 2 {
        GameInstance.GetVehicleSystem(this.GetGameInstance()).EnablePlayerVehicle(NcmHostField(f[1]), true, false);
      }
    }
  }

  private func Toast(title: String, message: String, seconds: Float) -> Void {
    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = seconds > 0.0 ? seconds : 6.0;
    msg.message = Equals(title, "") ? message : title + "  ·  " + message;
    msg.isInstant = true;
    let bb: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_Notifications);
    if IsDefined(bb) {
      bb.SetVariant(GetAllBlackboardDefs().UI_Notifications.OnscreenMessage, ToVariant(msg), true);
    }
  }

  private func Teleport(x: Float, y: Float, z: Float, heading: Float) -> Void {
    let player: ref<PlayerPuppet> = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return;
    }
    let rot: EulerAngles;
    rot.Yaw = heading;
    GameInstance.GetTeleportationFacility(this.GetGameInstance()).Teleport(player, new Vector4(x, y, z, 1.0), rot);
  }

  // The GPS waypoint: the game's own custom-position mappin, what the map's "set waypoint" makes.
  private func SetWaypoint(x: Float, y: Float, z: Float) -> Void {
    this.ClearWaypoint();
    let data: MappinData;
    data.mappinType = t"Mappins.DefaultStaticMappin";
    data.variant = gamedataMappinVariant.CustomPositionVariant;
    data.active = true;
    this.m_waypoint = GameInstance.GetMappinSystem(this.GetGameInstance()).RegisterMappin(data, new Vector4(x, y, z + 0.5, 1.0));
    this.m_hasWaypoint = true;
  }

  private func ClearWaypoint() -> Void {
    if this.m_hasWaypoint {
      GameInstance.GetMappinSystem(this.GetGameInstance()).UnregisterMappin(this.m_waypoint);
      this.m_hasWaypoint = false;
    }
  }
}
