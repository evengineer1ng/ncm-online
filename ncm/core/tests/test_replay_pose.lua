return {
  -- The 359 -> 1 case, which is the whole reason a ghost needs its own interpolation. A linear blend
  -- travels 358 degrees the long way round and the car spins a full turn on the spot while crossing north.
  yaw_takes_the_shortest_arc_across_north=function(T)
    local P=T.Core.get("replay.pose")
    T.eq(P.yawDelta(359,1),2,"359 to 1 is two degrees, not -358")
    T.eq(P.yawDelta(1,359),-2,"and the reverse is -2, not 358")
    T.eq(P.yawLerp(359,1,0.5),0,"halfway between 359 and 1 is exactly north")
    T.eq(P.yawLerp(350,10,0.5),0,"and the same holds for a wider arc across the seam")
    T.eq(P.yawLerp(10,350,0.5),0)
    -- Away from the seam it must behave like an ordinary blend.
    T.eq(P.yawLerp(90,180,0.5),135)
    T.eq(P.yawDelta(0,90),90)
  end,
  yaw_is_normalised_into_zero_to_threesixty=function(T)
    local P=T.Core.get("replay.pose")
    T.eq(P.normalizeYaw(-90),270);T.eq(P.normalizeYaw(450),90);T.eq(P.normalizeYaw(360),0);T.eq(P.normalizeYaw(0),0)
    T.eq(P.yawLerp(10,-10,0.5),0,"a negative input still lands on a normalised output")
  end,
  poses_round_trip_through_encode_and_decode=function(T)
    local P=T.Core.get("replay.pose")
    local poses={{t=0,x=1.234,y=2.345,z=3.456,yaw=12.34},{t=0.1,x=2,y=3,z=4,yaw=-5}}
    local wire=P.encode(poses)
    T.eq(#wire,2);T.eq(#wire[1],5,"a pose on the wire is a positional array of five numbers")
    T.eq(wire[1][1],0);T.eq(wire[1][2],1.23);T.eq(wire[1][5],12.3)
    T.eq(wire[2][5],355,"a negative heading is normalised before it is stored")
    local back=P.decode(wire,P.FORMAT)
    T.truthy(back);T.eq(#back,2);T.eq(back[1].x,1.23);T.eq(back[1].yaw,12.3);T.eq(back[2].yaw,355)
  end,
  decode_refuses_rather_than_guesses=function(T)
    local P=T.Core.get("replay.pose")
    local ok,why=P.decode({{0,1,2,3,4}},99)
    T.falsy(ok);T.match(why,"unknown_format")
    T.falsy(P.decode({},P.FORMAT),"an empty lap is not a lap")
    T.falsy(P.decode("nope",P.FORMAT))
    local _,w2=P.decode({{0,1,2,3,4},{"x",1,2,3,4}},P.FORMAT)
    T.match(w2,"field_type")
    local _,w3=P.decode({{0,1,2,3,4},{-1,1,2,3,4}},P.FORMAT)
    T.match(w3,"time_not_monotonic","a ghost clock that steps back would be replayed off the wrong bracket")
    local big={} for i=1,P.MAX_POSES+1 do big[i]={i*0.1,0,0,0,0} end
    local _,w4=P.decode(big,P.FORMAT)
    T.match(w4,"too_many_poses")
  end,
  poseAt_interpolates_and_never_extrapolates=function(T)
    local P=T.Core.get("replay.pose")
    local poses={{t=0,x=0,y=0,z=0,yaw=350},{t=1,x=10,y=0,z=2,yaw=10}}
    local mid=P.poseAt(poses,0.5)
    T.truthy(mid);T.eq(mid.x,5);T.eq(mid.z,1);T.eq(mid.yaw,0,"the seam is crossed correctly mid-playback")
    T.eq(P.poseAt(poses,0).x,0);T.eq(P.poseAt(poses,1).x,10)
    -- Outside the span there is no ghost. Before its start nothing is drawn; after its finish it must
    -- disappear rather than coast forever in the direction it was last pointing.
    T.falsy(P.poseAt(poses,-0.01),"a ghost has no position before its lap began")
    T.falsy(P.poseAt(poses,1.01),"nor after it finished")
    T.falsy(P.poseAt({},0.5))
  end,
  decimation_keeps_the_ends_and_drops_only_what_playback_reproduces=function(T)
    local P=T.Core.get("replay.pose")
    -- A dead-straight run at constant speed and constant heading: every interior pose is exactly what the
    -- interpolation would have produced, so all of them are redundant.
    local straight={}
    for i=0,50 do straight[#straight+1]={t=i*0.1,x=i*2,y=0,z=0,yaw=90} end
    local thin=P.decimate(straight,0.15,1.5)
    T.eq(#thin,2,"a straight line needs only its endpoints")
    T.eq(thin[1].t,0);T.eq(thin[2].t,5)
    -- A corner must survive. Displace the middle well beyond tolerance and it has to be kept.
    local bent={{t=0,x=0,y=0,z=0,yaw=0},{t=1,x=10,y=10,z=0,yaw=45},{t=2,x=20,y=0,z=0,yaw=315}}
    T.eq(#P.decimate(bent,0.15,1.5),3,"a corner is not redundant")
    -- Heading is a reason to keep a pose ON ITS OWN, independently of position. A straight line travelled
    -- with a sudden flick of opposite lock is the case: every position is exactly on the interpolation, so
    -- only the heading argues for keeping the pose. Note the flick has to be NON-LINEAR in time -- a car
    -- rotating at a constant rate is precisely what interpolation already reproduces.
    local flick={}
    for i=0,10 do flick[#flick+1]={t=i*0.1,x=i*2,y=0,z=0,yaw=(i==5) and 40 or 0} end
    T.truthy(#P.decimate(flick,0.15,1.5)>2,"a heading change is a reason to keep a pose on its own")
    T.eq(#P.decimate(flick,0.15,90),2,"and a tolerance wide enough to cover it drops it again")
    T.eq(#P.decimate({{t=0,x=0,y=0,z=0,yaw=0}},0.15,1.5),1,"one pose survives decimation unchanged")
  end,
  rebase_puts_the_first_pose_at_zero=function(T)
    local P=T.Core.get("replay.pose")
    local out=P.rebase({{t=1758000000.5,x=1,y=2,z=3,yaw=10},{t=1758000001.5,x=4,y=5,z=6,yaw=20}})
    T.eq(out[1].t,0,"a stored lap is relative to its own start, not to the day it was set")
    T.eq(out[2].t,1);T.eq(out[2].x,4)
    T.eq(P.durationMs(out),1000)
    T.eq(P.durationMs({{t=0}}),0,"a single pose has no duration")
  end,
}
