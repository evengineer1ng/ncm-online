return {
  -- A record added to the catalogue without a resolvable template must fail HERE, offline, and not appear
  -- live as a ghost that silently does not draw (KB-14: props.create returns a successful id regardless).
  every_catalogue_record_yields_candidates=function(T)
    local V=T.Core.get("data.vehicle_templates")
    local faults=V.validate()
    T.eq(#faults,0,"template authoring faults: "..table.concat(faults,"; "))
  end,
  records_parse_into_a_template_basename=function(T)
    local V=T.Core.get("data.vehicle_templates")
    local base,token=V.parseRecord("Vehicle.v_sport2_mizutani_shion_player")
    T.eq(base,"v_sport2_mizutani_shion","the _player suffix is a TweakDB variant, not part of the template")
    T.eq(token,"sport2")
    T.eq((V.parseRecord("Vehicle.v_standard25_mahir_supron")),"v_standard25_mahir_supron")
    T.eq(select(2,V.parseRecord("Vehicle.v_sportbike1_yaiba_kusanagi_tyger")),"sportbike1")
    T.falsy(V.parseRecord("Items.SomethingElse"))
    T.falsy(V.parseRecord(nil))
  end,
  candidates_are_ordered_and_always_end_in_the_fallback=function(T)
    local V=T.Core.get("data.vehicle_templates")
    local list=V.candidates("Vehicle.v_sport2_mizutani_shion_player")
    T.truthy(#list>=4)
    T.eq(list[1],"Vehicle.v_sport2_mizutani_shion_player","the record itself is tried first")
    T.eq(list[#list],V.FALLBACK,"and the fallback is always last, so a ghost always draws something")
    T.match(list[2],"base.vehicles.sport.v_sport2_mizutani_shion")
    -- No duplicates: a repeated candidate is a wasted projection and a confusing log.
    local seen={}
    for _,m in ipairs(list) do T.falsy(seen[m],"duplicate candidate "..m);seen[m]=true end
    -- An unparseable record still gets the fallback rather than an empty list.
    local junk=V.candidates("not-a-record")
    T.eq(junk[#junk],V.FALLBACK)
    T.truthy(V.isFallback(V.FALLBACK));T.falsy(V.isFallback("Vehicle.v_sport2_mizutani_shion"))
  end,
  an_override_must_name_a_record_a_machine_claims=function(T)
    local V=T.Core.get("data.vehicle_templates")
    V.OVERRIDE["Vehicle.v_not_a_real_car"]="whatever"
    local faults=V.validate()
    T.truthy(#faults>0,"an override for an unknown record is an authoring fault")
    V.OVERRIDE["Vehicle.v_not_a_real_car"]=nil
    T.eq(#V.validate(),0)
    -- A proven override takes precedence over every guess.
    V.OVERRIDE["Vehicle.v_sport2_mizutani_shion"]="proven.model.string"
    T.eq(V.candidates("Vehicle.v_sport2_mizutani_shion")[1],"proven.model.string")
    T.eq((V.ghostModelFor("Vehicle.v_sport2_mizutani_shion")),"proven.model.string")
    V.OVERRIDE["Vehicle.v_sport2_mizutani_shion"]=nil
  end,
}
