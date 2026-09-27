local function facts(over)
  local f={
    ghostId="11111111-1111-4111-8111-111111111111",
    driverId="22222222-2222-4222-9222-222222222222",
    routeId="troll_pass", disciplineId="time_trial", rulesetId="street_open", classId="street_open",
    runStartedAt=1000.0, runFinishedAt=1102.318, elapsedMs=102318, incidentMs=0,
    record="Vehicle.v_sport2_mizutani_shion_player", appearance="mizutani_shion__basic_01",
    assetId="33333333-3333-4333-a333-333333333333",
    configurationRef="44444444-4444-4444-b444-444444444444",
    poseCount=420, poseHz=10, gatesDone=6, gatesTotal=6, tier="personal",
  }
  for k,v in pairs(over or {}) do if v=="\0nil" then f[k]=nil else f[k]=v end end
  return f
end
return {
  manifest_accepts_a_complete_lap_and_normalises_it=function(T)
    local L=T.Core.get("replay.lap");local P=T.Core.get("replay.pose")
    local m=L.manifest(facts())
    T.truthy(m);T.eq(m.format,P.FORMAT);T.eq(m.tier,"personal")
    T.eq(m.elapsedMs,102318);T.eq(m.record,"Vehicle.v_sport2_mizutani_shion_player")
    T.eq(m.laps,1,"a lap count is assumed rather than demanded")
  end,
  manifest_names_every_refusal=function(T)
    local L=T.Core.get("replay.lap")
    local cases={
      {{ghostId="nope"},"ghost_id"},{{driverId="nope"},"driver_id"},{{routeId="\0nil"},"route_id"},
      {{format=99},"unknown_format"},{{runFinishedAt="\0nil"},"run_boundaries"},
      {{runFinishedAt=999.0},"run_not_forward"},{{elapsedMs=10},"elapsed_ms"},
      {{poseCount=2},"pose_count"},{{poseCount=99999},"too_many_poses"},
      {{record="\0nil"},"record"},{{incidentMs=-5},"incident_ms"},{{tier="borrowed"},"unknown_tier"},
    }
    for _,c in ipairs(cases) do
      local m,why=L.manifest(facts(c[1]))
      T.falsy(m,"expected a refusal for "..c[2]);T.match(why,c[2])
    end
    T.falsy(L.manifest("nope"))
  end,
  -- A ghost that is not a complete, clean, attributable lap is refused by NAME. "The ghost did not appear"
  -- is the least diagnosable failure this feature can have, so every rejection says which rule caught it.
  eligibility_refuses_by_name=function(T)
    local L=T.Core.get("replay.lap")
    T.truthy(L.eligible(facts(),"personal"))
    local function no(over,reason)
      local ok,why=L.eligible(facts(over),"personal")
      T.falsy(ok);T.match(why,reason)
    end
    no({gatesDone=5},"gates_incomplete")
    no({gatesTotal="\0nil"},"gates_unknown")
    no({runStartedAt="\0nil"},"run_boundaries")
    no({runFinishedAt=500},"run_not_forward")
    no({poseCount=1},"pose_count")
    no({refusedPoses=3},"poses_refused")
    no({disconnected=true},"disconnected")
    no({dsq=true},"dsq")
    no({record="\0nil"},"record")
  end,
  -- Handing one driver's line to another is a claim about a third party. Until the server corroborates it
  -- from its own observation and the driver has opted in, the public tiers refuse rather than quietly accept.
  public_tiers_demand_corroboration_and_consent=function(T)
    local L=T.Core.get("replay.lap")
    local ok,why=L.eligible(facts(),"route")
    T.falsy(ok);T.match(why,"not_corroborated")
    local ok2,why2=L.eligible(facts({serverCorroborated=true}),"route")
    T.falsy(ok2);T.match(why2,"not_published")
    T.truthy(L.eligible(facts({serverCorroborated=true,published=true}),"route"))
    T.truthy(L.eligible(facts(),"personal"),"a personal ghost needs neither")
  end,
  better_is_defined_once=function(T)
    local L=T.Core.get("replay.lap")
    T.truthy(L.better(1000,nil),"anything beats no incumbent")
    T.truthy(L.better(999,1000));T.falsy(L.better(1000,1000),"a tie is not an improvement")
    T.falsy(L.better(1001,1000));T.falsy(L.better(0,1000));T.falsy(L.better(nil,1000))
  end,
  -- The delta is a comparison at a PLACE, not between two clocks. Both drivers have been going for the same
  -- elapsed time at any given moment, so a clock-to-clock delta is identically zero and says nothing.
  delta_is_measured_by_course_progress=function(T)
    local L=T.Core.get("replay.lap");local tm=T.Core.get("telemetry")
    local course=tm.polyline({{x=0,y=0,z=0},{x=100,y=0,z=0}})
    T.eq(course.lengthM,100)
    -- A ghost that took 10 s to cover 100 m at a steady pace.
    local poses={}
    for i=0,10 do poses[#poses+1]={t=i,x=i*10,y=0,z=0,yaw=90} end
    local idx=L.progressIndex(poses,course)
    T.truthy(idx);T.eq(#idx,11);T.eq(idx[1].m,0);T.eq(idx[11].m,100)
    T.eq(L.timeAtProgress(idx,50),5,"halfway along the course the ghost was five seconds in")
    T.eq(L.timeAtProgress(idx,55),5.5,"and between poses the time is interpolated")
    -- I am at 50 m after 4.8 s: 200 ms ahead, reported negative.
    T.eq(L.delta(idx,50,4.8),-200)
    T.eq(L.delta(idx,50,5.3),300,"and behind is positive")
    -- Off the ends there is no comparison to make, and inventing one would put a number on the HUD that no
    -- lap supports.
    T.falsy(L.timeAtProgress(idx,-1));T.falsy(L.timeAtProgress(idx,101))
    T.falsy(L.delta(idx,101,5))
  end,
  progress_index_is_forced_forward=function(T)
    local L=T.Core.get("replay.lap");local tm=T.Core.get("telemetry")
    local course=tm.polyline({{x=0,y=0,z=0},{x=100,y=0,z=0}})
    -- A real lap wanders backwards by a few centimetres of projection noise. A non-monotonic index makes a
    -- lookup ambiguous -- two different times for one place -- so progress is clamped forward.
    local poses={{t=0,x=0,y=0,z=0,yaw=90},{t=1,x=10,y=0,z=0,yaw=90},{t=2,x=9.9,y=0,z=0,yaw=90},{t=3,x=20,y=0,z=0,yaw=90}}
    local idx=L.progressIndex(poses,course)
    T.eq(idx[3].m,idx[2].m,"a backwards step is clamped, not recorded")
    for i=2,#idx do T.truthy(idx[i].m>=idx[i-1].m) end
    T.falsy(L.progressIndex({},course));T.falsy(L.progressIndex(poses,{pts={}}))
  end,
}
