local M=NcmCore.get("competition.race_builder")
local Nodes=NcmCore.get("data.nodes")
local cases={}

-- a real raceLegal node, taken from the data rather than hardcoded, so the test survives the roster changing
local function legal(n)
    local out={}
    for _,x in ipairs(Nodes.LIST) do if x.raceLegal==true then out[#out+1]=x.id end end
    return n and out[n] or out
end
local A,B,Cn,D=legal(1),legal(2),legal(3),legal(4)
local HERE={x=100,y=200,z=15,heading=90}

local NONE={}
local function form(over)
    local f={start=M.START_HERE,checkpoints={},finish=B,classId="street_open",minutes=5,laps=1}
    for k,v in pairs(over or {}) do f[k]=(v~=NONE) and v or nil end
    return f
end
local function facts(over)
    local x={position=HERE,now=1000,creatorId="drv-1"}
    for k,v in pairs(over or {}) do x[k]=(v~=NONE) and v or nil end
    return x
end
local function has(options,id)
    for _,o in ipairs(options or {}) do if o.id==id then return true end end
    return false
end

cases.here_is_the_default_start=function(T)
    local f=M.blank(facts())
    T.eq(f.start,M.START_HERE)
    T.eq(f.finish,nil)          -- the one thing a driver must actually choose
    T.eq(#f.checkpoints,0)
    T.eq(f.minutes,5)
end

cases.the_start_list_offers_here_first_then_every_node=function(T)
    local o=M.startOptions(facts())
    T.eq(o[1].id,M.START_HERE)
    T.ok(o[1].here)
    -- complete, not truncated: one HERE plus every raceLegal node
    T.eq(#o,#legal()+1)
end

cases.the_finish_list_is_every_node_and_no_here=function(T)
    local o=M.finishOptions(facts())
    T.eq(#o,#legal())
    T.ok(not has(o,M.START_HERE))
end

cases.the_whole_node_list_is_exposed_not_a_nearest_few=function(T)
    -- the L179 builder offered four routes; this must offer all 35 places
    T.ok(#M.nodeOptions(facts())>=30)
    T.eq(#M.nodeOptions(facts()),#legal())
end

cases.nodes_are_ordered_nearest_first_but_never_dropped=function(T)
    local near=Nodes.byId(A)
    local o=M.nodeOptions(facts({position=near}))
    T.eq(o[1].id,A)                       -- standing on it puts it first
    T.eq(#o,#legal())                     -- and drops nothing
    T.match(o[1].label,"km")
end

cases.without_a_position_the_order_is_stable_and_complete=function(T)
    local a=M.nodeOptions(facts({position=NONE}))
    local b=M.nodeOptions(facts({position=NONE}))
    T.eq(#a,#legal())
    for i=1,#a do T.eq(a[i].id,b[i].id) end
    T.ok(not a[1].label:find("km",1,true))
end

cases.the_driver_is_never_asked_what_kind_of_race=function(T)
    -- we cannot enforce drag/oval/drift, so the discipline is derived and the schema offers no such field
    T.eq(M.DISCIPLINE,"street_sprint")
    local s=M.schema(facts())
    T.eq(s.discipline,nil)
    T.eq(s.type,nil)
    T.eq(M.spec(form(),facts()).disciplineId,"street_sprint")
end

cases.the_schema_carries_the_whole_form_in_one_pass=function(T)
    local s=M.schema(facts())
    T.ok(#s.start>0); T.ok(#s.finish>0); T.ok(#s.class>0); T.ok(#s.when>0)
    T.eq(s.maxCheckpoints,M.MAX_CHECKPOINTS)
    T.eq(s.hasPosition,true)
    T.eq(M.schema(facts({position=NONE})).hasPosition,false)
end

cases.a_here_start_becomes_the_first_point=function(T)
    local pts=M.points(form(),facts())
    T.eq(#pts,2)
    T.eq(pts[1].x,HERE.x); T.eq(pts[1].y,HERE.y); T.eq(pts[1].heading,HERE.heading)
    T.ok(pts[1].here)
    local fin=Nodes.byId(B)
    T.eq(pts[#pts].x,fin.x)
end

cases.a_here_start_needs_a_position=function(T)
    T.eq(select(2,M.normalize(form(),facts({position=NONE}))),"position_unknown")
    -- but a node start does not
    T.ok(M.normalize(form{start=A},facts({position=NONE})))
end

cases.the_position_is_resolved_at_submit_not_at_open=function(T)
    -- the form carries the INTENT, so the same form yields different points from different places
    local f=form()
    local p1=M.points(f,facts({position={x=0,y=0,z=0}}))
    local p2=M.points(f,facts({position={x=900,y=900,z=0}}))
    T.eq(p1[1].x,0); T.eq(p2[1].x,900)
end

cases.checkpoints_chain_in_order=function(T)
    local pts=M.points(form{start=A,checkpoints={Cn,D},finish=B},facts())
    T.eq(#pts,4)
    T.eq(pts[1].x,Nodes.byId(A).x)
    T.eq(pts[2].x,Nodes.byId(Cn).x)
    T.eq(pts[3].x,Nodes.byId(D).x)
    T.eq(pts[4].x,Nodes.byId(B).x)
end

cases.a_long_chain_is_allowed_up_to_the_bound=function(T)
    local cps={}
    local ids=legal()
    for i=1,M.MAX_CHECKPOINTS do cps[i]=ids[i+2] end
    T.ok(M.normalize(form{start=A,checkpoints=cps,finish=B},facts()))
    cps[#cps+1]=ids[#ids]
    T.eq(select(2,M.normalize(form{start=A,checkpoints=cps,finish=B},facts())),"too_many_checkpoints")
end

cases.a_zero_length_leg_is_refused=function(T)
    T.eq(select(2,M.normalize(form{start=A,checkpoints={A},finish=B},facts())),"repeated_point")
    T.eq(select(2,M.normalize(form{start=A,checkpoints={Cn,Cn},finish=B},facts())),"repeated_point")
    T.eq(select(2,M.normalize(form{start=A,checkpoints={Cn},finish=Cn},facts())),"repeated_point")
end

cases.passing_the_same_point_twice_is_allowed=function(T)
    -- a figure of eight is a legitimate route; only ADJACENT repeats are a zero-length leg
    T.ok(M.normalize(form{start=A,checkpoints={Cn,D,Cn},finish=B},facts()))
end

cases.start_equals_finish_is_a_loop_and_keeps_its_laps=function(T)
    local f=M.normalize(form{start=A,checkpoints={Cn},finish=A,laps=3},facts())
    T.eq(f.laps,3)
    T.eq(M.spec(form{start=A,checkpoints={Cn},finish=A,laps=3},facts()).loop,true)
    T.match(M.routeName(form{start=A,checkpoints={Cn},finish=A},facts()),"loop")
end

cases.laps_are_meaningless_on_a_point_to_point_and_are_flattened=function(T)
    local f=M.normalize(form{start=A,finish=B,laps=4},facts())
    T.eq(f.laps,1)
end

cases.a_finish_must_be_chosen_and_must_be_real=function(T)
    T.eq(select(2,M.normalize(form{finish=NONE},facts())),"finish_required")
    T.eq(select(2,M.normalize(form{finish="nowhere_at_all"},facts())),"invalid_finish")
    T.eq(select(2,M.normalize(form{start="nowhere_at_all"},facts())),"invalid_start")
    T.eq(select(2,M.normalize(form{checkpoints={"nowhere_at_all"}},facts())),"invalid_checkpoint")
    T.eq(select(2,M.normalize(nil,facts())),"form_not_table")
end

cases.a_temporary_start_node_is_not_offered_as_a_destination=function(T)
    -- this is what keeps yesterday's Street Call start lines out of today's list
    Nodes.register({ id="street_call_tmp_x", x=1,y=2,z=3, name="Temp", road=true, custom=true })
    local ok,err=pcall(function()
        T.ok(not has(M.nodeOptions(facts()),"street_call_tmp_x"))
        T.eq(select(2,M.normalize(form{finish="street_call_tmp_x"},facts())),"invalid_finish")
    end)
    Nodes.unregister("street_call_tmp_x")
    if not ok then error(err,0) end
    T.eq(Nodes.byId("street_call_tmp_x"),nil)
end

cases.class_and_when_are_closed_lists=function(T)
    T.eq(select(2,M.normalize(form{classId="ncx_rb15"},facts())),"invalid_class")
    T.eq(select(2,M.normalize(form{classId="nonsense"},facts())),"invalid_class")
    T.eq(select(2,M.normalize(form{minutes=999},facts())),"invalid_minutes")
    T.eq(select(2,M.normalize(form{minutes=NONE},facts())),"invalid_minutes")
    T.ok(M.normalize(form{minutes=M.WHEN_MINUTES[1]},facts()))
end

cases.distance_is_the_sum_of_the_legs=function(T)
    local pts={{x=0,y=0},{x=0,y=300},{x=400,y=300}}
    T.eq(M.distanceM(pts),700)          -- not the 500 m crow-flies between the ends
    T.eq(M.distanceM({}),0)
end

cases.a_race_too_short_to_be_a_race_is_refused=function(T)
    local near={x=Nodes.byId(B).x+10,y=Nodes.byId(B).y+10,z=0,heading=0}
    T.eq(select(2,M.spec(form(),facts({position=near}))),"too_short")
    T.ok(M.MIN_DISTANCE_M>0)
end

cases.the_spec_is_a_description_not_an_event=function(T)
    local spec=M.spec(form{start=A,checkpoints={Cn},finish=B},facts())
    T.eq(spec.class,"impromptu")
    T.eq(spec.formatId,"sprint")
    T.eq(spec.disciplineId,"street_sprint")
    T.eq(spec.classId,"street_open")
    T.eq(spec.minutes,5)
    T.eq(spec.creatorId,nil)            -- the form carries it, and this form was not built by M.blank
    T.eq(#spec.points,3)
    T.ok(spec.distanceM>M.MIN_DISTANCE_M)
    T.eq(spec.startsHere,false)
    -- the host owns identity, state and persistence
    T.eq(spec.eventId,nil); T.eq(spec.state,nil); T.eq(spec.venue,nil); T.eq(spec.routeId,nil)
end

cases.the_spec_reports_whether_the_start_is_improvised=function(T)
    T.eq(M.spec(form(),facts()).startsHere,true)
    T.eq(M.spec(form{start=A},facts()).startsHere,false)
end

cases.blank_carries_the_creator_through=function(T)
    local f=M.blank(facts())
    f.finish=B
    T.eq(M.spec(f,facts()).creatorId,"drv-1")
end

cases.the_summary_reads_back_every_answer=function(T)
    local text=M.summary(form{start=A,checkpoints={Cn,D},finish=B,minutes=20},facts())
    T.match(text,"Street Call")
    T.match(text,"Distance:")
    T.match(text,"Via:")
    T.match(text,"in 20 min")
    T.eq(select(2,M.summary(form{finish=NONE},facts())),"finish_required")
end

cases.the_summary_omits_via_when_there_are_no_checkpoints=function(T)
    T.ok(not M.summary(form{start=A,finish=B},facts()):find("Via:",1,true))
end

cases.the_route_name_says_here_when_it_starts_here=function(T)
    T.match(M.routeName(form(),facts()),"^Here")
    T.match(M.routeName(form{start=A},facts()),tostring(Nodes.byId(A).name))
end

-- ---------------------------------------------------------------------------------------------
-- The wire split (`KB-172`). These assert the PROPERTY that broke, not the code that broke it: the
-- payload must fit a player-sized budget, and the client must get its schema back unchanged.
-- ---------------------------------------------------------------------------------------------

local Json=NcmCore.get("vocabulary.json")

-- `IDEA-509`, measured live: 4,032 bytes accepted, ~5,010 refused. The node list is streamed in packets
-- against `NcmStream.PACKET_BUDGET_BYTES` (6 KiB), but the HEAD cannot be split, so the head is what has
-- to stay small -- and it is the head that will silently grow next.
local HEAD_CEILING=4032

cases.the_wire_head_fits_inside_a_player_sized_budget=function(T)
    local w=M.wire(facts())
    local head={}
    for k,v in pairs(w) do if k~="nodes" then head[k]=v end end
    local bytes=#Json.encode(head)
    T.ok(bytes<HEAD_CEILING,("wire head is %d bytes, ceiling %d"):format(bytes,HEAD_CEILING))
end

cases.the_wire_carries_the_node_list_exactly_once=function(T)
    local w=M.wire(facts())
    T.eq(#w.nodes,#M.nodeOptions(facts()))
    -- the whole bug: `start` and `finish` are one list, and sending both is what doubled the payload
    T.eq(w.start,nil)
    T.eq(w.finish,nil)
end

cases.the_client_rebuilds_the_identical_schema_from_the_wire=function(T)
    local direct=M.schema(facts())
    local rebuilt=M.schemaFromWire(M.wire(facts()))
    T.eq(#rebuilt.start,#direct.start)
    T.eq(#rebuilt.finish,#direct.finish)
    T.eq(rebuilt.start[1].id,M.START_HERE)
    T.eq(rebuilt.finish[1].id,direct.finish[1].id)
    T.eq(rebuilt.maxCheckpoints,direct.maxCheckpoints)
    T.eq(rebuilt.minDistanceM,direct.minDistanceM)
    T.eq(rebuilt.hasPosition,direct.hasPosition)
    T.eq(#rebuilt.class,#direct.class)
    T.eq(#rebuilt.when,#direct.when)
end

cases.a_wire_with_no_rows_still_yields_a_drawable_schema=function(T)
    -- a stream that arrived empty must give the page empty lists, never nil: the page renders a schema
    local s=M.schemaFromWire({})
    T.eq(#s.finish,0)
    T.eq(#s.start,1)             -- HERE survives, because it is not a row
    T.eq(s.maxCheckpoints,M.MAX_CHECKPOINTS)
    T.eq(s.hasPosition,false)
end

cases.the_wire_says_whether_a_position_is_known=function(T)
    T.eq(M.wire(facts()).hasPosition,true)
    T.eq(M.wire(facts({position=NONE})).hasPosition,false)
end

return cases
