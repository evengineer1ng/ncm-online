// NCM Pace -- DEV-ONLY DIAGNOSTIC (KB-249). Needs Codeware; never part of the Pace package (Pace itself must not
// depend on Codeware). Installed by hand into r6/scripts/ncm_pace_diag/ on the dev machine only.
//
// What the engine itself says, every 15 s for 10 rounds after the player loads in:
//   1. HASH   -- the engine's own path->NodeRef (Codeware CreateNodeRef) against Pace's FNV-1a 64 (NcmPace_NodeRef).
//   2. BLOCKS -- every streaming block in the live streaming world: is ours (race_splines.streamingblock) among them?
//   3. SECTOR -- our legs_000 sector and the vanilla cleaning-machine sector (exterior_-2_0_0_4), loaded through the
//                engine: the NodeRef the engine holds for each spline node, beside the hash Pace sends.

public class NcmPaceDiagTick extends DelayCallback {
  public let system: wref<NcmPaceDiagSystem>;
  public func Call() -> Void {
    let s: ref<NcmPaceDiagSystem> = this.system;
    if IsDefined(s) { s.Round(); }
  }
}

public class NcmPaceDiagSystem extends ScriptableSystem {
  private let m_player: wref<PlayerPuppet>;
  private let m_rounds: Int32;
  private let m_ours: ref<ResourceToken>;
  private let m_vanilla: ref<ResourceToken>;
  private let m_oursDone: Bool;
  private let m_vanillaDone: Bool;
  private let m_blocksDone: Bool;

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let player: ref<PlayerPuppet> = request.owner as PlayerPuppet;
    if !IsDefined(player) || !player.IsControlledByLocalPeer() { return; }
    this.m_player = player;
    this.m_rounds = 10;
    NcmPace_Log("diag: Codeware diagnostic attached; first round in 15 s");
    this.Next();
  }

  private func Next() -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) || this.m_rounds <= 0 { return; }
    let cb: ref<NcmPaceDiagTick> = new NcmPaceDiagTick();
    cb.system = this;
    GameInstance.GetDelaySystem(player.GetGame()).DelayCallback(cb, 15.0, false);
  }

  private func U(x: Uint64) -> String { return ToString(Cast<Int64>(x)); }

  private func Hash(label: String, path: String) -> Void {
    let engine: Uint64 = NodeRefToHash(CreateNodeRef(path));
    let pace: Uint64 = NodeRefToHash(NcmPace_NodeRef(path));
    NcmPace_Log("diag HASH " + label + ": engine=" + this.U(engine) + " pace=" + this.U(pace)
      + (Equals(engine, pace) ? " MATCH" : " DIFFERENT"));
  }

  private func Sector(label: String, token: ref<ResourceToken>, wantPath: String) -> Bool {
    if !IsDefined(token) { return true; }
    if !token.IsFinished() { NcmPace_Log("diag SECTOR " + label + ": still loading"); return false; }
    if token.IsFailed() { NcmPace_Log("diag SECTOR " + label + ": FAILED to load"); return true; }
    let sector: ref<worldStreamingSector> = token.GetResource() as worldStreamingSector;
    if !IsDefined(sector) { NcmPace_Log("diag SECTOR " + label + ": loaded but not a worldStreamingSector"); return true; }
    let n: Int32 = sector.GetNodeSetupCount();
    NcmPace_Log("diag SECTOR " + label + ": category=" + ToString(EnumInt(sector.category)) + " level=" + ToString(Cast<Int32>(sector.level))
      + " nodes=" + ToString(sector.GetNodeCount()) + " setups=" + ToString(n) + " refs=" + ToString(sector.GetNodeRefCount()));
    let want: Uint64 = NodeRefToHash(NcmPace_NodeRef(wantPath));
    let i: Int32 = 0;
    let shown: Int32 = 0;
    while i < n {
      let setup: ref<WorldNodeSetupWrapper> = sector.GetNodeSetup(i);
      if IsDefined(setup) {
        let node: ref<worldNode> = setup.GetNode();
        let kind: String = IsDefined(node) ? NameToString(node.GetClassName()) : "?";
        let ref: Uint64 = NodeRefToHash(setup.GetNodeRef());
        if StrContains(kind, "Spline") && shown < 3 {
          shown += 1;
          NcmPace_Log("diag SECTOR " + label + " node " + ToString(i) + " " + kind + ": engine ref=" + this.U(ref)
            + (Equals(ref, want) ? " == Pace's hash of " + wantPath : " (Pace's hash of " + wantPath + " is " + this.U(want) + ")"));
        }
      }
      i += 1;
    }
    return true;
  }

  public func Round() -> Void {
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) { return; }
    let game: GameInstance = player.GetGame();
    this.m_rounds -= 1;
    let me: Vector4 = player.GetWorldPosition();
    NcmPace_Log("diag round (player " + FloatToStringPrec(me.X, 0) + "," + FloatToStringPrec(me.Y, 0) + ")");
    if this.m_rounds == 9 {
      this.Hash("ours", "$/mod/ncm_pace/#leg_a_bit_-2832_-2675__allfoods_intersection_-558_2522");
      this.Hash("vanilla cleaning machine",
        "$/03_night_city/#c_city_center/corpo_plaza/corpo_plaza_openworld_prefabKKRD5RI/corpo_plaza_openworld_community_prefabMBEYQOY/#cct_cpz_roundabout_cleaning_machine_spl");
      let depot: ref<ResourceDepot> = GameInstance.GetResourceDepot();
      this.m_ours = depot.LoadResource(r"mod\\ncm_pace\\race_splines\\legs_000.streamingsector");
      this.m_vanilla = depot.LoadResource(r"base\\worlds\\03_night_city\\_compiled\\default\\exterior_-2_0_0_4.streamingsector");
      NcmPace_Log("diag: depot says our sector exists=" + ToString(depot.ResourceExists(r"mod\\ncm_pace\\race_splines\\legs_000.streamingsector"))
        + " our block exists=" + ToString(depot.ResourceExists(r"mod\\ncm_pace\\race_splines\\race_splines.streamingblock")));
    }
    if !this.m_blocksDone {
      let wss: ref<WorldStateSystem> = GameInstance.GetWorldStateSystem();
      let world: ref<worldStreamingWorld> = IsDefined(wss) ? wss.GetStreamingWorld() : null;
      if IsDefined(world) {
        this.m_blocksDone = true;
        let count: Int32 = ArraySize(world.blockRefs);
        NcmPace_Log("diag BLOCKS: the live streaming world lists " + ToString(count) + " block(s)");
        let b: Int32 = 0;
        while b < count {
          let r: ResourceRef = world.blockRefs[b];
          NcmPace_Log("diag BLOCKS " + ToString(b) + ": " + ResRef.ToString(ResourceRef.GetPath(r)) + " loaded=" + ToString(ResourceRef.IsLoaded(r)));
          b += 1;
        }
      } else {
        NcmPace_Log("diag BLOCKS: no streaming world yet");
      }
    }
    if !this.m_oursDone { this.m_oursDone = this.Sector("OURS legs_000", this.m_ours, "$/mod/ncm_pace/#leg_a_bit_-2832_-2675__allfoods_intersection_-558_2522"); }
    if !this.m_vanillaDone { this.m_vanillaDone = this.Sector("VANILLA exterior_-2_0_0_4", this.m_vanilla,
      "$/03_night_city/#c_city_center/corpo_plaza/corpo_plaza_openworld_prefabKKRD5RI/corpo_plaza_openworld_community_prefabMBEYQOY/#cct_cpz_roundabout_cleaning_machine_spl"); }
    this.Next();
  }
}
