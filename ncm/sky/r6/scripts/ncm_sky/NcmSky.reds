// NCM Sky (KB-430) -- the bodies NCM draws in REDengine, with FULL orientation.
//
// Open77 props take a position and a yaw only, so an Earth that turns under the Machine, or a sky that turns with
// the clock, cannot be a prop. This system draws them itself: the `ncm_sky` resource sends a SCENE through
// `ncm_sky.dll` (each body: id, kind, appearance, world position, a unit quaternion), and each tick this reads it
// and makes the world match -- spawning a body from its template through `NcmSky_Spawn` (Codeware's DynamicEntitySystem when loaded, else exEntitySpawner -- KB-440; vanilla scripts cannot reach either), turning and
// moving it with the game's own TeleportationFacility (the call NCM's racing already uses), removing what the scene
// no longer names. Every spawned body is reported back to Lua.
//
// RULES THIS FILE KEEPS, BECAUSE A REDSCRIPT COMPILE ERROR TAKES EVERY SCRIPT MOD DOWN WITH IT:
//   * vanilla symbols and this package's own natives only;
//   * only templates from this package's own archive (the KINDS table below);
//   * nothing outlives the feed: an empty scene (the DLL empties it when the socket drops or goes stale) removes
//     every body, and so does the player detaching.
module NcmSky

public func NcmSkyHash(id: EntityID) -> Uint64 {
  return Cast<Uint64>(EntityID.GetHash(id));
}

public class NcmSkyTick extends DelayCallback {
  public let system: wref<NcmSkySystem>;
  public let generation: Int32;
  public func Call() -> Void {
    let system: ref<NcmSkySystem> = this.system;
    if IsDefined(system) {
      system.Tick(this.generation);
    }
  }
}

public class NcmSkySystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_generation: Int32;
  private let m_rev: String;
  // the bodies in the world, parallel arrays (id, kind, appearance, entity, last placement, placed yet)
  private let m_ids: array<String>;
  private let m_kinds: array<Int32>;
  private let m_apps: array<String>;
  private let m_ents: array<EntityID>;
  private let m_pos: array<Vector4>;
  private let m_rot: array<EulerAngles>;
  private let m_placed: array<Bool>;
  private let m_waits: array<Int32>;

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() {
      return;
    }
    this.m_player = player;
    this.m_generation += 1;
    this.m_rev = "";
    NcmSky_Log("attached");
    this.Schedule(0.5);
  }

  private func OnPlayerDetach(request: ref<PlayerDetachRequest>) -> Void {
    this.RemoveAll();
    this.m_generation += 1;
    this.m_player = null;
  }

  private func Schedule(delay: Float) -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) {
      return;
    }
    let tick: ref<NcmSkyTick> = new NcmSkyTick();
    tick.system = this;
    tick.generation = this.m_generation;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(tick, delay, false);
  }

  // The templates this package ships. A kind Lua names that is not here is refused, never guessed.
  // 1 the q201 Earth (SKY-1); 2 the star dome; 3-6 the Earth at 1000 / 100 / 10 / 1 m; 7-9 the Moon at 100 / 10 / 1 m
  // (core space.sky's KIND / EARTH / MOON tables name the same numbers); 10-14 the ascent ring at k 0.04 .. 0.01.
  private func Template(kind: Int32) -> String {
    switch kind {
      case 1: return "ncm\\sky\\bodies\\earth_1km.ent";
      case 2: return "ncm\\sky\\bodies\\dome.ent";
      case 3: return "ncm\\sky\\bodies\\earth_r1000.ent";
      case 4: return "ncm\\sky\\bodies\\earth_r100.ent";
      case 5: return "ncm\\sky\\bodies\\earth_r10.ent";
      case 6: return "ncm\\sky\\bodies\\earth_r1.ent";
      case 7: return "ncm\\sky\\bodies\\moon_r100.ent";
      case 8: return "ncm\\sky\\bodies\\moon_r10.ent";
      case 9: return "ncm\\sky\\bodies\\moon_r1.ent";
      case 10: return "ncm\\sky\\bodies\\ring_k040.ent";
      case 11: return "ncm\\sky\\bodies\\ring_k028.ent";
      case 12: return "ncm\\sky\\bodies\\ring_k020.ent";
      case 13: return "ncm\\sky\\bodies\\ring_k014.ent";
      case 14: return "ncm\\sky\\bodies\\ring_k010.ent";
    }
    return "";
  }

  private func Known(kind: Int32) -> Bool {
    return kind >= 1 && kind <= 14;
  }

  // The ascent rings (kinds 10-14): the Earth Underlay mesh at scale k. The scene names the ring's TRUE anchor (its
  // pivot over the map); each tick it is placed at  eye + k * (anchor - eye),  the true Earth shrunk about the game's own
  // camera: the same picture, k times nearer, inside the draw distance. Moved every tick, so it never lags the climb.
  private func RingScale(kind: Int32) -> Float {
    switch kind {
      case 10: return 0.04;
      case 11: return 0.028;
      case 12: return 0.02;
      case 13: return 0.014;
      case 14: return 0.01;
    }
    return 0.0;
  }

  private func Where(i: Int32, game: GameInstance) -> Vector4 {
    let k: Float = this.RingScale(this.m_kinds[i]);
    if k <= 0.0 {
      return this.m_pos[i];
    }
    let eye: Transform;
    GameInstance.GetCameraSystem(game).GetActiveCameraWorldTransform(eye);
    let e: Vector4 = eye.position;
    let a: Vector4 = this.m_pos[i];
    return new Vector4(e.X + k * (a.X - e.X), e.Y + k * (a.Y - e.Y), e.Z + k * (a.Z - e.Z), 1.0);
  }

  private func IndexOf(id: String) -> Int32 {
    let i: Int32 = 0;
    while i < ArraySize(this.m_ids) {
      if Equals(this.m_ids[i], id) {
        return i;
      }
      i += 1;
    }
    return -1;
  }

  private func Despawn(i: Int32) -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if IsDefined(player) {
      let e: ref<Entity> = GameInstance.FindEntityByID(player.GetGame(), this.m_ents[i]);
      if IsDefined(e) {
        NcmSky_Despawn(e);
      }
    }
    NcmSky_Report(this.m_ids[i], 4, 0ul, "");
    ArrayErase(this.m_ids, i);
    ArrayErase(this.m_kinds, i);
    ArrayErase(this.m_apps, i);
    ArrayErase(this.m_ents, i);
    ArrayErase(this.m_pos, i);
    ArrayErase(this.m_rot, i);
    ArrayErase(this.m_placed, i);
    ArrayErase(this.m_waits, i);
  }

  private func RemoveAll() -> Void {
    while ArraySize(this.m_ids) > 0 {
      this.Despawn(ArraySize(this.m_ids) - 1);
    }
  }

  private func Spawn(id: String, kind: Int32, app: String, pos: Vector4, rot: EulerAngles) -> Void {
    let eid: EntityID = NcmSky_Spawn(this.Template(kind), app, pos.X, pos.Y, pos.Z);
    ArrayPush(this.m_ids, id);
    ArrayPush(this.m_kinds, kind);
    ArrayPush(this.m_apps, app);
    ArrayPush(this.m_ents, eid);
    ArrayPush(this.m_pos, pos);
    ArrayPush(this.m_rot, rot);
    ArrayPush(this.m_placed, false);
    ArrayPush(this.m_waits, 0);
    NcmSky_Log("spawn " + id + " kind " + IntToString(kind) + " entity " + ToString(NcmSkyHash(eid)));
  }

  // One body this tick: once the spawned entity exists, put it where the scene says, every axis.
  private func Place(i: Int32) -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    let game: GameInstance = player.GetGame();
    let e: ref<Entity> = GameInstance.FindEntityByID(game, this.m_ents[i]);
    if !IsDefined(e) {
      this.m_waits[i] += 1;
      if this.m_waits[i] == 1400 {
        NcmSky_Report(this.m_ids[i], 3, NcmSkyHash(this.m_ents[i]), "not streamed in after 1400 ticks (~10 s)");
      }
      return;
    }
    let o: ref<GameObject> = e as GameObject;
    if !IsDefined(o) {
      if !this.m_placed[i] {
        this.m_placed[i] = true;
        NcmSky_Report(this.m_ids[i], 3, NcmSkyHash(this.m_ents[i]), "spawned, but not a GameObject: cannot turn it");
      }
      return;
    }
    GameInstance.GetTeleportationFacility(game).Teleport(o, this.Where(i, game), this.m_rot[i]);
    if !this.m_placed[i] {
      this.m_placed[i] = true;
      NcmSky_Report(this.m_ids[i], 1, NcmSkyHash(this.m_ents[i]), "");
    } else {
      if this.RingScale(this.m_kinds[i]) <= 0.0 {   // a ring moves every tick: not reported each time
        NcmSky_Report(this.m_ids[i], 2, NcmSkyHash(this.m_ents[i]), "");
      }
    }
  }

  // "rev|id`kind`app`x`y`z`qi`qj`qk`qr^..." (state.hpp)
  private func Apply(scene: String) -> Void {
    let bar: Int32 = StrFindFirst(scene, "|");
    if bar < 0 {
      return;
    }
    let rev: String = StrLeft(scene, bar);
    if Equals(rev, this.m_rev) {
      return;
    }
    this.m_rev = rev;
    let body: String = StrMid(scene, bar + 1);
    let wanted: array<String>;
    if StrLen(body) > 0 {
      let parts: array<String> = StrSplit(body, "^");
      for p in parts {
        let f: array<String> = StrSplit(p, "`");
        if ArraySize(f) == 10 {
          let id: String = f[0];
          let kind: Int32 = StringToInt(f[1]);
          let app: String = Equals(f[2], "~") ? "" : f[2];
          let pos: Vector4 = new Vector4(StringToFloat(f[3]), StringToFloat(f[4]), StringToFloat(f[5]), 1.0);
          // a unit quaternion from the scene, turned into the game's own EulerAngles by the game's own conversion
          let q: Quaternion;
          q.i = StringToFloat(f[6]);
          q.j = StringToFloat(f[7]);
          q.k = StringToFloat(f[8]);
          q.r = StringToFloat(f[9]);
          let rot: EulerAngles = Quaternion.ToEulerAngles(q);
          ArrayPush(wanted, id);
          if !this.Known(kind) {
            NcmSky_Report(id, 3, 0ul, "unknown kind " + IntToString(kind));
          } else {
            let i: Int32 = this.IndexOf(id);
            if i >= 0 && (this.m_kinds[i] != kind || !Equals(this.m_apps[i], app)) {
              this.Despawn(i);
              i = -1;
            }
            if i < 0 {
              this.Spawn(id, kind, app, pos, rot);
            } else {
              this.m_pos[i] = pos;
              this.m_rot[i] = rot;
              this.Place(i);
            }
          }
        }
      }
    }
    let k: Int32 = ArraySize(this.m_ids) - 1;
    while k >= 0 {
      if !ArrayContains(wanted, this.m_ids[k]) {
        this.Despawn(k);
      }
      k -= 1;
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
    this.Apply(NcmSky_Scene());
    // a body spawned this tick (or one still streaming in) is placed as soon as it exists; a ring follows the eye
    let i: Int32 = 0;
    while i < ArraySize(this.m_ids) {
      if !this.m_placed[i] || this.RingScale(this.m_kinds[i]) > 0.0 {
        this.Place(i);
      }
      i += 1;
    }
    if ArraySize(this.m_ids) > 0 {
      this.Schedule(0.0);
    } else {
      this.Schedule(0.25);
    }
  }
}
