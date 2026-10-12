// NCM Radio -- Race Week Live in the game's own radio list (doc 59 §6, L348).
//
// The station is one more row in the vanilla radio popup (vehicle radio and pocket radio share it). Choosing it turns
// the engine's radio off and lets `ncm_radio.dll` play the programme the `ncm_radio` resource schedules; choosing any
// other row is plain vanilla. The station is ON by default: the first time a session has the player in a car with no
// choice made, it tunes in -- unless the player has ever picked another station, which is remembered (`prefs.txt`
// beside the DLL) and never overridden (owner, 2026-10-08: "default ... not locked into ours").
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only -- nothing from OPEN//77, NCM Lua or any other mod;
//   * a 10 Hz tick, two settings reads and one native call; nothing allocated per tick;
//   * no new UI layer (KB-389): the station lives inside the vanilla popup the player already uses.
module NcmRadio

public func NcmRadioIndex() -> Int32 = 7700
public func NcmRadioRecord() -> TweakDBID = t"RadioStation.NcmRaceWeekLive"

public class NcmRadioTick extends DelayCallback {
  public let system: wref<NcmRadioSystem>;
  public let generation: Int32;

  public func Call() -> Void {
    let system: ref<NcmRadioSystem> = this.system;
    if IsDefined(system) {
      system.Tick(this.generation);
    }
  }
}

public class NcmRadioSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_generation: Int32;
  private let m_tuned: Bool;        // Race Week Live is the selected station
  private let m_on: Bool;           // ... and the radio is on
  private let m_decided: Bool;      // this session already chose (or defaulted); the default never fires twice
  private let m_wasInVehicle: Bool;
  private let m_lastBeat: String;

  public static func Get(game: GameInstance) -> ref<NcmRadioSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"NcmRadio.NcmRadioSystem") as NcmRadioSystem;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.m_player = player;
    this.m_generation += 1;
    this.m_decided = false;
    this.m_wasInVehicle = false;
    NcmRadio_Log("attached; preference " + NcmRadio_Pref());
    this.Schedule(1.0);
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.m_generation += 1;
    this.m_player = null;
    NcmRadio_Tick(false, 0.0);
  }

  private func Schedule(delay: Float) -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let tick: ref<NcmRadioTick> = new NcmRadioTick();
    tick.system = this;
    tick.generation = this.m_generation;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(tick, delay, false);
  }

  public func IsTuned() -> Bool {
    return this.m_tuned;
  }

  // The player chose Race Week Live (popup) or the default chose it for them.
  public func TuneIn(byPlayer: Bool) -> Void {
    this.m_tuned = true;
    this.m_on = true;
    this.m_decided = true;
    this.SilenceVanilla();
    if byPlayer {
      NcmRadio_SetPref("ncm");
    }
    NcmRadio_Log(byPlayer ? "tuned in by the player" : "tuned in by default");
  }

  // The player chose another station (or turned the radio off): vanilla from here on.
  public func TuneOut(otherStation: Bool) -> Void {
    if this.m_tuned {
      NcmRadio_Log(otherStation ? "player chose another station" : "player turned the radio off");
    }
    this.m_tuned = false;
    this.m_on = false;
    this.m_decided = true;
    if otherStation {
      NcmRadio_SetPref("other");
    }
  }

  // The vehicle radio hotkey while tuned: on/off for Race Week Live, the engine radio stays out of it.
  public func Toggle() -> Void {
    this.m_on = !this.m_on;
    if this.m_on {
      this.SilenceVanilla();
    }
    NcmRadio_Log(this.m_on ? "station on (hotkey)" : "station off (hotkey)");
  }

  private func SilenceVanilla() -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let vehicle: wref<VehicleObject>;
    if VehicleComponent.GetVehicle(player.GetGame(), player, vehicle) && IsDefined(vehicle) && vehicle.IsRadioReceiverActive() {
      vehicle.ToggleRadioReceiver(false);
    }
    let pocket: ref<PocketRadio> = player.GetPocketRadio();
    if IsDefined(pocket) && pocket.IsActive() {
      player.GetQuickSlotsManager().SendRadioEvent(false, false, -1);
    }
  }

  private func Volume(player: ref<PlayerPuppet>, inVehicle: Bool) -> Float {
    let settings: ref<UserSettings> = GameInstance.GetSettingsSystem(player.GetGame());
    if !settings.HasGroup(n"/audio/volume") {
      return 0.8;
    }
    let group: ref<ConfigGroup> = settings.GetGroup(n"/audio/volume");
    let name: CName = inVehicle ? n"CarRadioVolume" : n"RadioportVolume";
    let radio: Float = 80.0;
    let master: Float = 100.0;
    if group.HasVar(name) {
      radio = Cast<Float>((group.GetVar(name) as ConfigVarInt).GetValue());
    }
    if group.HasVar(n"MasterVolume") {
      master = Cast<Float>((group.GetVar(n"MasterVolume") as ConfigVarInt).GetValue());
    }
    return (radio / 100.0) * (master / 100.0);
  }

  public func Tick(generation: Int32) -> Void {
    if generation != this.m_generation {
      return;
    }
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let vehicle: wref<VehicleObject>;
    let inVehicle: Bool = VehicleComponent.GetVehicle(player.GetGame(), player, vehicle) && IsDefined(vehicle);
    // The default: the first car of a session, nothing chosen yet, and the player has never picked another station.
    if inVehicle && !this.m_wasInVehicle && !this.m_decided && NotEquals(NcmRadio_Pref(), "other") {
      this.TuneIn(false);
    }
    this.m_wasInVehicle = inVehicle;
    // While tuned, the engine's own radio stays silent (a car's radio resumes on entry; a pocket radio may be on).
    if this.m_tuned && this.m_on && inVehicle && vehicle.IsRadioReceiverActive() {
      vehicle.ToggleRadioReceiver(false);
    }
    let listening: Bool = this.m_tuned && this.m_on;
    let beat: String = NcmRadio_Tick(listening, listening ? this.Volume(player, inVehicle) : 0.0);
    if NotEquals(beat, this.m_lastBeat) {
      this.m_lastBeat = beat;
    }
    this.Schedule(0.1);
  }
}

// ---- the station in the vanilla list ---------------------------------------------------------------------------

@wrapMethod(VehiclesManagerDataHelper)
public final static func GetRadioStations(player: ref<GameObject>) -> array<ref<IScriptable>> {
  let stations: array<ref<IScriptable>> = wrappedMethod(player);
  let record: ref<RadioStation_Record> = TweakDBInterface.GetRadioStationRecord(NcmRadioRecord());
  if IsDefined(record) {
    let item: ref<RadioListItemData> = new RadioListItemData();
    item.m_record = record;
    // right after "no station": the first real row, where a player finds it without scrolling
    ArrayInsert(stations, 1, item);
  }
  return stations;
}

@wrapMethod(VehicleRadioPopupGameController)
protected func Activate() -> Void {
  let system: ref<NcmRadioSystem> = NcmRadioSystem.Get(this.m_player.GetGame());
  if !IsDefined(this.m_selectedItem) || !IsDefined(system) {
    wrappedMethod();
    return;
  }
  let data: ref<RadioListItemData> = this.m_selectedItem.GetStationData();
  if IsDefined(data) && IsDefined(data.m_record) && data.m_record.Index() == NcmRadioIndex() {
    system.TuneIn(true);
    let changed: ref<RadioStationChangedEvent> = new RadioStationChangedEvent();
    changed.m_radioIndex = NcmRadioIndex();
    this.QueueEvent(changed);
    return;
  }
  system.TuneOut(IsDefined(data) && IsDefined(data.m_record) && data.m_record.Index() != -1);
  wrappedMethod();
}

// Open the popup on Race Week Live while it is playing, with its row marked as the current station.
@wrapMethod(VehicleRadioPopupGameController)
protected func SetupData() -> Void {
  wrappedMethod();
  let system: ref<NcmRadioSystem> = NcmRadioSystem.Get(this.m_player.GetGame());
  if !IsDefined(system) || !system.IsTuned() {
    return;
  }
  let i: Int32 = 0;
  let n: Int32 = Cast<Int32>(this.m_dataSource.GetArraySize());
  while i < n {
    let data: ref<RadioListItemData> = this.m_dataSource.GetItem(Cast<Uint32>(i)) as RadioListItemData;
    if IsDefined(data) && IsDefined(data.m_record) && data.m_record.Index() == NcmRadioIndex() {
      this.m_startupIndex = Cast<Uint32>(i);
      this.m_currentRadioId = NcmRadioIndex();
      return;
    }
    i += 1;
  }
}

// The radio hotkey in a car: while Race Week Live is the station it switches the station on and off.
@wrapMethod(VehicleComponent)
protected cb func OnRadioToggleEvent(evt: ref<RadioToggleEvent>) -> Bool {
  let vehicle: wref<VehicleObject> = this.GetVehicle();
  let system: ref<NcmRadioSystem> = IsDefined(vehicle) ? NcmRadioSystem.Get(vehicle.GetGame()) : null;
  if IsDefined(system) && system.IsTuned() {
    system.Toggle();
    return true;
  }
  return wrappedMethod(evt);
}
