local M=NcmCore.get("competition.race_tags")
local cases={}
local function ids(xs) local t={} for _,x in ipairs(xs or {}) do t[x.id]=true end return t end
cases.solo_clean_is_run_and_qualified_survives_display_cap=function(T)
    local out=M.evaluate({session={kind="race",timeTrial=true,fieldSize=1,gatesTotal=2},results={{driverId="a",state="finished",position=1,totalSec=80,incidentCount=0,incidents={},penalties={},jumpStart=false,previousBestSec=90}}},{maxTags=1})
    local q=ids(out.drivers[1].qualified); T.ok(q.clean_run); T.ok(q.personal_best); T.eq(#out.drivers[1].tags,1); T.ok(not q.clean_race)
end
cases.contested_clean_is_race=function(T)
    local out=M.evaluate({session={kind="race",timeTrial=false,fieldSize=2,gatesTotal=0},results={
        {driverId="a",state="finished",position=1,totalSec=80,incidentCount=0,incidents={},penalties={},jumpStart=false},
        {driverId="b",state="finished",position=2,totalSec=81,incidentCount=0,incidents={},penalties={},jumpStart=false}}})
    T.ok(ids(out.drivers[1].qualified).clean_race); T.ok(ids(out.drivers[1].qualified).close_finish==nil)
end
cases.negative_tags_are_facts_not_suppressed=function(T)
    local out=M.evaluate({session={kind="race",timeTrial=false,fieldSize=2,gatesTotal=0},results={
        {driverId="a",state="dnf",position=2,incidentCount=3,incidents={{band=3}},penalties={{seconds=5}},jumpStart=true},
        {driverId="b",state="finished",position=1,incidentCount=0,incidents={},penalties={},jumpStart=false}}},{maxTags=20})
    local q=ids(out.drivers[1].qualified); T.ok(q.did_not_finish); T.ok(q.heavy_contact); T.ok(q.jump_start); T.ok(not q.clean_race)
end
return cases
