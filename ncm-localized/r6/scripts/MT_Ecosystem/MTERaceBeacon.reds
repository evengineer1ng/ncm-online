// MT_Ecosystem: MTERaceBeacon.reds
// Race start/finish map pins + GPS waypoint, owned by a ScriptableSystem so CET Lua can call it
// directly (Game.GetScriptableSystemsContainer():Get("NcmRaceBeaconSystem")). No UI-event bridge,
// no per-controller state, and every call returns a result Lua can log.
//
// Pins use the Custom Map Markers recipe (Mappins.CustomMapMarkersMappinDefinition +
// CPO_PingGoHereVariant + GameplayRoleMappinData.m_isMappinCustom), i.e. exactly what CMM's own
// map markers use, so they render on the world map, the minimap and as an in-world floating icon.
// The GPS waypoint is the game's own custom-position mappin (what the map's "set waypoint" makes),
// which gives the minimap route and the In-World Navigation POI line.

public class NcmRaceBeaconSystem extends ScriptableSystem {
  private let m_startId: NewMappinID;
  private let m_finishId: NewMappinID;
  private let m_waypointId: NewMappinID;
  private let m_hasStart: Bool;
  private let m_hasFinish: Bool;
  private let m_hasWaypoint: Bool;
  private let m_lastError: String;

  public final static func Get(game: GameInstance) -> ref<NcmRaceBeaconSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"NcmRaceBeaconSystem") as NcmRaceBeaconSystem;
  }

  private final func Mappins() -> ref<MappinSystem> {
    return GameInstance.GetMappinSystem(this.GetGameInstance());
  }

  private final func MakePinData(title: String, caption: String, icon: CName) -> MappinData {
    let role: ref<GameplayRoleMappinData> = new GameplayRoleMappinData();
    role.m_isQuest = true;
    role.m_visibleThroughWalls = true;
    role.m_range = 250.0;
    role.m_gameplayRole = EGameplayRole.FastTravel;
    role.m_textureID = t"MappinIcons.GenericDeviceMappin";
    role.m_showOnMiniMap = true;
    role.m_isMappinCustom = true;
    role.m_isMappinExternal = false;
    role.m_customMappinTitle = title;
    role.m_customMappinDescription = caption;
    role.m_customMappinTexturePart = icon;

    let data: MappinData;
    data.mappinType = t"Mappins.CustomMapMarkersMappinDefinition";
    data.variant = gamedataMappinVariant.CPO_PingGoHereVariant;
    data.active = true;
    data.visibleThroughWalls = true;
    data.debugCaption = title;
    data.scriptData = role;
    return data;
  }

  // Start pin (green, stopwatch icon)
  public final func PlaceStart(x: Float, y: Float, z: Float, title: String) -> Bool {
    let sys: ref<MappinSystem> = this.Mappins();
    if !IsDefined(sys) { this.m_lastError = "no MappinSystem"; return false; }
    if this.m_hasStart { sys.UnregisterMappin(this.m_startId); this.m_hasStart = false; }
    let label: String = Equals(title, "") ? "Race Start" : title;
    this.m_startId = sys.RegisterMappin(this.MakePinData(label, "MT_Ecosystem|0.20|1.00|0.35|1.00", n"stopwatch"), new Vector4(x, y, z + 0.5, 1.0));
    this.m_hasStart = true;
    return true;
  }

  // Finish pin (red, checkered-flag "racing" icon)
  public final func PlaceFinish(x: Float, y: Float, z: Float, title: String) -> Bool {
    let sys: ref<MappinSystem> = this.Mappins();
    if !IsDefined(sys) { this.m_lastError = "no MappinSystem"; return false; }
    if this.m_hasFinish { sys.UnregisterMappin(this.m_finishId); this.m_hasFinish = false; }
    let label: String = Equals(title, "") ? "Race Finish" : title;
    this.m_finishId = sys.RegisterMappin(this.MakePinData(label, "MT_Ecosystem|1.00|0.25|0.15|1.00", n"racing"), new Vector4(x, y, z + 0.5, 1.0));
    this.m_hasFinish = true;
    return true;
  }

  // GPS waypoint: the game's custom-position mappin -> minimap route + In-World Navigation POI line.
  public final func PlaceWaypoint(x: Float, y: Float, z: Float) -> Bool {
    let sys: ref<MappinSystem> = this.Mappins();
    if !IsDefined(sys) { this.m_lastError = "no MappinSystem"; return false; }
    if this.m_hasWaypoint { sys.UnregisterMappin(this.m_waypointId); this.m_hasWaypoint = false; }
    let data: MappinData;
    data.mappinType = t"Mappins.DefaultStaticMappin";
    data.variant = gamedataMappinVariant.CustomPositionVariant;
    data.active = true;
    data.debugCaption = "NCM race waypoint";
    this.m_waypointId = sys.RegisterMappin(data, new Vector4(x, y, z + 0.5, 1.0));
    this.m_hasWaypoint = true;
    return true;
  }

  public final func ClearWaypoint() -> Void {
    let sys: ref<MappinSystem> = this.Mappins();
    if this.m_hasWaypoint && IsDefined(sys) { sys.UnregisterMappin(this.m_waypointId); }
    this.m_hasWaypoint = false;
  }

  public final func ClearPins() -> Void {
    let sys: ref<MappinSystem> = this.Mappins();
    if IsDefined(sys) {
      if this.m_hasStart { sys.UnregisterMappin(this.m_startId); }
      if this.m_hasFinish { sys.UnregisterMappin(this.m_finishId); }
    }
    this.m_hasStart = false;
    this.m_hasFinish = false;
  }

  public final func Clear() -> Void {
    this.ClearPins();
    this.ClearWaypoint();
  }

  public final func Status() -> String {
    return s"start=\(this.m_hasStart) finish=\(this.m_hasFinish) waypoint=\(this.m_hasWaypoint) lastError=\(this.m_lastError)";
  }

  // Called by the game when the player detaches (load/menu): drop stale pins.
  private final func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.Clear();
  }
}
