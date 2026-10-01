// NCM Pace (0.7.8, KB-249): ask the ENGINE whether a spline exists, instead of inferring it from failed commands.
// AIScriptUtils.GetStartPointOfSpline / GetEndPointOfSpline take the same NodeRef the racing command takes; the node's
// own transform comes from GameInstance.GetNodeTransform. Run for our race splines and for vanilla open-world
// splines (controls), 30 s after the player loads in and at each race's first racing command. Read-only, logs only.

public func NcmPace_ProbeSpline(game: GameInstance, label: String, path: String) -> Void {
  let ref: NodeRef = NcmPace_NodeRef(path);
  let start: Vector4;
  let end: Vector4;
  let xf: Transform;
  let hasStart: Bool = AIScriptUtils.GetStartPointOfSpline(game, ref, start);
  let hasEnd: Bool = AIScriptUtils.GetEndPointOfSpline(game, ref, end);
  let global: GlobalNodeRef = ResolveNodeRef(ref, Cast<GlobalNodeRef>(GlobalNodeID.GetRoot()));
  let hasNode: Bool = GameInstance.GetNodeTransform(game, global, xf);
  let at: Vector4 = Transform.GetPosition(xf);
  NcmPace_Log("splineprobe " + label + ": start=" + ToString(hasStart)
    + (hasStart ? " (" + FloatToStringPrec(start.X, 0) + "," + FloatToStringPrec(start.Y, 0) + ")" : "")
    + " end=" + ToString(hasEnd)
    + (hasEnd ? " (" + FloatToStringPrec(end.X, 0) + "," + FloatToStringPrec(end.Y, 0) + ")" : "")
    + " node=" + ToString(hasNode)
    + (hasNode ? " (" + FloatToStringPrec(at.X, 0) + "," + FloatToStringPrec(at.Y, 0) + ")" : "")
    + " path=" + path);
}

public func NcmPace_ProbeSplines(game: GameInstance) -> Void {
  NcmPace_ProbeSpline(game, "OURS corpo_plaza->waterfront", "$/mod/ncm_pace/#leg_corpo_plaza_-1103_-19__waterfront_-569_2648");
  NcmPace_ProbeSpline(game, "OURS hanford->stadium", "$/mod/ncm_pace/#leg_hanford_overpass_-1281_-1107__stadium_-1326_-1656");
  NcmPace_ProbeSpline(game, "VANILLA sq024 open-world (level 6)", "$/03_night_city/#c_city_center/corpo_plaza/loc_sq024_citycenter_racetrack_prefabK3D7W4Y/loc_sq024_citycenter_racetrack_openworld_prefabPMPERBY/#test_nc_sq024_city_center");
  NcmPace_ProbeSpline(game, "VANILLA cleaning machine (level 4, near Corpo Plaza)", "$/03_night_city/#c_city_center/corpo_plaza/corpo_plaza_openworld_prefabKKRD5RI/corpo_plaza_openworld_community_prefabMBEYQOY/#cct_cpz_roundabout_cleaning_machine_spl");
}
