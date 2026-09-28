local M=NcmCore.get("player.leads")
local cases={}

-- NONE, because `{sourceRef=nil}` is an empty table in Lua and would silently leave the default in place --
-- which is exactly how the first version of this test passed a case it was not testing.
local NONE={}
local function lead(over)
    local d={subjectKind="market",subjectRef="mk_kabuki_01",sourceKind="character",sourceRef="rico",at=100}
    for k,v in pairs(over or {}) do d[k]=(v~=NONE) and v or nil end
    return d
end

cases.identity_is_the_subject_not_the_telling=function(T)
    T.eq(M.key("market","mk_1"),"market:mk_1")
    local a=M.normalize(lead{sourceRef="rico"})
    local b=M.normalize(lead{sourceRef="billie"})
    T.eq(a.key,b.key)   -- two characters, one mystery
end

cases.bad_subjects_and_sources_are_refused=function(T)
    T.eq(select(2,M.key("nonsense","x")),"invalid_subject_kind")
    T.eq(select(2,M.key("market","")),"invalid_subject_ref")
    T.eq(select(2,M.key("market",nil)),"invalid_subject_ref")
    T.eq(select(2,M.normalize(nil)),"lead_not_table")
    T.eq(select(2,M.normalize(lead{sourceKind="vibes"})),"invalid_source_kind")
end

cases.a_character_source_must_name_the_character=function(T)
    T.eq(select(2,M.normalize(lead{sourceRef=NONE})),"character_source_needs_ref")
    T.ok(M.normalize(lead{sourceKind="provenance",sourceRef=NONE})) -- other sources may be anonymous
end

cases.normalize_opens_the_lead_and_keeps_provenance=function(T)
    local l=M.normalize(lead())
    T.eq(l.state,"open"); T.eq(l.sourceKind,"character"); T.eq(l.sourceRef,"rico")
    T.eq(l.subjectKind,"market"); T.eq(l.subjectRef,"mk_kabuki_01"); T.eq(l.at,100)
end

cases.admit_refuses_for_distinct_reasons=function(T)
    local ok,why=M.admit(lead(),{subjectAlreadyAccessible=true})
    T.ok(not ok); T.eq(why,"already_accessible")
    ok,why=M.admit(lead(),{existing={state="open"}})
    T.ok(not ok); T.eq(why,"already_known")
    ok,why=M.admit(lead(),{existing={state="closed"}})
    T.ok(not ok); T.eq(why,"already_resolved")
    ok,why=M.admit(lead(),{existing={state="cold"}})
    T.ok(not ok); T.eq(why,"already_resolved")
end

cases.admit_returns_the_normalized_lead_on_success=function(T)
    local ok,why,l=M.admit(lead(),{})
    T.ok(ok); T.eq(why,nil); T.eq(l.key,"market:mk_kabuki_01"); T.eq(l.state,"open")
end

cases.admit_validates_before_it_checks_facts=function(T)
    local ok,why=M.admit({subjectKind="market"},{subjectAlreadyAccessible=true})
    T.ok(not ok); T.eq(why,"invalid_subject_ref")
end

cases.resolving_closes_and_records_why=function(T)
    local l=M.normalize(lead())
    M.resolve(l,"walked into it",200)
    T.eq(l.state,"closed"); T.eq(l.resolvedReason,"walked into it"); T.eq(l.resolvedAt,200)
end

cases.resolving_twice_is_a_noop_not_an_error=function(T)
    local l=M.normalize(lead())
    M.resolve(l,"first",200)
    local again,why=M.resolve(l,"second",300)
    T.eq(why,nil); T.eq(again.state,"closed")
    T.eq(l.resolvedReason,"first"); T.eq(l.resolvedAt,200)  -- the first close is the true one
end

cases.expire_is_separate_from_resolve=function(T)
    local l=M.normalize(lead())
    M.expire(l,"the shop burned down",400)
    T.eq(l.state,"cold")
    local r=M.resolve(l,"too late",500)
    T.eq(r.state,"cold")   -- terminal stays terminal
end

cases.open_count_is_glass_trigger=function(T)
    local a=M.normalize(lead{subjectRef="m1"})
    local b=M.normalize(lead{subjectRef="m2"})
    local c=M.normalize(lead{subjectKind="person",subjectRef="needle"})
    M.resolve(b,"found it",1)
    local all={a,b,c}
    T.eq(M.openCount(all),2)
    T.eq(M.openCount(all,"market"),1)
    T.eq(M.openCount(all,"person"),1)
    T.eq(M.openCount(all,"machine"),0)
    T.eq(M.openCount(nil),0)
end

cases.shelf_is_newest_first_and_open_only=function(T)
    local a=M.normalize(lead{subjectRef="m1",at=100})
    local b=M.normalize(lead{subjectRef="m2",at=300})
    local c=M.normalize(lead{subjectRef="m3",at=200})
    M.resolve(c,"done",400)
    local s=M.shelf({a,b,c})
    T.eq(#s,2); T.eq(s[1].subjectRef,"m2"); T.eq(s[2].subjectRef,"m1")
end

cases.shelf_limit_bounds_display_only=function(T)
    local a=M.normalize(lead{subjectRef="m1",at=100})
    local b=M.normalize(lead{subjectRef="m2",at=300})
    T.eq(#M.shelf({a,b},1),1)
    T.eq(#M.shelf({a,b},0),2)     -- 0 means no cap, not "show nothing"
    T.eq(#M.shelf({a,b}),2)
end

cases.shelf_ties_break_deterministically=function(T)
    local a=M.normalize(lead{subjectRef="zzz",at=100})
    local b=M.normalize(lead{subjectRef="aaa",at=100})
    local s1=M.shelf({a,b}); local s2=M.shelf({b,a})
    T.eq(s1[1].key,s2[1].key)
end

return cases
