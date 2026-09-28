local M=NcmCore.get("competition.overtakes")
local cases={}

-- crossings shorthand: e{driver=[gate]=time}
local function E(t) local out={} for id,cr in pairs(t) do out[id]={crossings=cr} end return out end

cases.order_at_a_gate_is_by_crossing_time=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]=11,[2]=19}}
    T.eq(table.concat(M.orderAt(e,1),","),"a,b")
    T.eq(table.concat(M.orderAt(e,2),","),"b,a")
end

cases.a_driver_who_never_crossed_is_absent_not_last=function(T)
    local e=E{a={[1]=10},b={}}
    local o=M.orderAt(e,1)
    T.eq(#o,1); T.eq(o[1],"a")
end

cases.one_clean_pass_is_counted_both_ways=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]=11,[2]=19}}
    local r=M.analyse({entrants=e,gateCount=2})
    T.eq(r.drivers.b.passes,1); T.eq(r.drivers.b.clean,1); T.eq(r.drivers.b.contested,0)
    T.eq(r.drivers.a.passedBy,1); T.eq(r.drivers.a.passes,0)
    T.eq(r.drivers.b.net,1); T.eq(r.drivers.a.net,-1)
    T.eq(#r.events,1); T.eq(r.events[1].driverId,"b"); T.eq(r.events[1].overtookId,"a")
end

cases.holding_position_is_not_a_pass=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]=11,[2]=21}}
    local r=M.analyse({entrants=e,gateCount=2})
    T.eq(r.drivers.a.passes,0); T.eq(r.drivers.b.passes,0); T.eq(#r.events,0)
end

cases.repeated_swaps_count_each_time=function(T)
    -- b passes a, a takes it back, b passes again
    local e=E{a={[1]=10,[2]=21,[3]=30,[4]=41},b={[1]=11,[2]=20,[3]=31,[4]=40}}
    local r=M.analyse({entrants=e,gateCount=4})
    T.eq(r.drivers.b.passes,2); T.eq(r.drivers.a.passes,1)
    T.eq(r.drivers.b.net,1)
end

cases.a_retirement_is_not_a_pass_on_everyone=function(T)
    -- a leads gate 1 then retires; b and c must not be credited with passing a
    local e=E{a={[1]=10},b={[1]=11,[2]=20},c={[1]=12,[2]=21}}
    local r=M.analyse({entrants=e,gateCount=2})
    T.eq(r.drivers.b.passes,0); T.eq(r.drivers.c.passes,0); T.eq(r.drivers.a.passedBy,0)
end

cases.a_driver_joining_late_is_not_credited_for_the_segment=function(T)
    -- c has no gate-1 crossing, so the 1->2 segment cannot rank them
    local e=E{a={[1]=10,[2]=20},c={[2]=19}}
    local r=M.analyse({entrants=e,gateCount=2})
    T.eq(r.drivers.c.passes,0); T.eq(r.drivers.a.passedBy,0)
end

cases.contact_in_the_window_makes_the_pass_contested=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]=11,[2]=19}}
    local r=M.analyse({entrants=e,gateCount=2,contacts={{a="a",b="b",at=18}}})
    T.eq(r.drivers.b.passes,1); T.eq(r.drivers.b.contested,1); T.eq(r.drivers.b.clean,0)
    T.ok(r.events[1].contested)
end

cases.contact_far_away_in_time_leaves_the_pass_clean=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]=11,[2]=19}}
    local r=M.analyse({entrants=e,gateCount=2,contacts={{a="a",b="b",at=2}}})
    T.eq(r.drivers.b.clean,1); T.eq(r.drivers.b.contested,0)
end

cases.contact_between_other_drivers_does_not_taint_this_pass=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]=11,[2]=19},c={[1]=30,[2]=40}}
    local r=M.analyse({entrants=e,gateCount=2,contacts={{a="a",b="c",at=19}}})
    T.eq(r.drivers.b.clean,1); T.eq(r.drivers.b.contested,0)
end

cases.contact_pair_is_symmetric=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]=11,[2]=19}}
    local r=M.analyse({entrants=e,gateCount=2,contacts={{a="b",b="a",at=19}}})
    T.eq(r.drivers.b.contested,1)
end

cases.a_three_car_sweep_counts_two_passes=function(T)
    local e=E{a={[1]=10,[2]=30},b={[1]=11,[2]=31},c={[1]=12,[2]=20}}
    local r=M.analyse({entrants=e,gateCount=2})
    T.eq(r.drivers.c.passes,2); T.eq(r.drivers.a.passedBy,1); T.eq(r.drivers.b.passedBy,1)
    T.eq(#r.events,2)
end

cases.from_gate_skips_the_start=function(T)
    -- the swap happens on 1->2; counting from gate 2 must not see it
    local e=E{a={[1]=10,[2]=21,[3]=30},b={[1]=11,[2]=20,[3]=31}}
    local all=M.analyse({entrants=e,gateCount=3})
    local late=M.analyse({entrants=e,gateCount=3,fromGate=2})
    T.eq(all.drivers.b.passes,1); T.eq(all.drivers.a.passes,1)
    T.eq(late.drivers.b.passes,0); T.eq(late.drivers.a.passes,1)
    T.eq(late.segments,1)
end

cases.events_are_time_ordered_and_deterministic=function(T)
    local e=E{a={[1]=10,[2]=30},b={[1]=11,[2]=31},c={[1]=12,[2]=20}}
    local r1=M.analyse({entrants=e,gateCount=2})
    local r2=M.analyse({entrants=e,gateCount=2})
    T.eq(#r1.events,#r2.events)
    for i=1,#r1.events do
        T.eq(r1.events[i].driverId..">"..r1.events[i].overtookId, r2.events[i].driverId..">"..r2.events[i].overtookId)
    end
    for i=2,#r1.events do T.ok(r1.events[i].at>=r1.events[i-1].at) end
end

cases.bad_input_is_refused_not_guessed=function(T)
    T.eq(select(2,M.analyse(nil)),"facts_not_table")
    T.eq(select(2,M.analyse({})),"entrants_required")
    T.eq(select(2,M.analyse({entrants={}})),"gate_count_required")
    T.eq(select(2,M.analyse({entrants={},gateCount=1})),"gate_count_required")
end

cases.nan_and_junk_crossings_are_ignored=function(T)
    local e=E{a={[1]=10,[2]=20},b={[1]="x",[2]=19}}
    local r=M.analyse({entrants=e,gateCount=2})
    T.eq(r.drivers.b.passes,0)   -- b had no rankable gate-1 crossing
    T.eq(r.drivers.a.passedBy,0)
end

cases.for_session_reads_a_race_state=function(T)
    local s={gates={{},{}},entrants={a={crossings={[1]=10,[2]=20}},b={crossings={[1]=11,[2]=19}}}}
    local line=M.forSession(s,"b")
    T.eq(line.passes,1); T.eq(line.net,1)
    local missing=M.forSession(s,"nobody")
    T.eq(missing.passes,0)
    T.eq(select(2,M.forSession({},"a")),"session_required")
end

return cases
