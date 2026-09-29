-- ncm-core module: competition.race_tags
-- Pure post-event facts. Presentation selects a bounded subset; economy consumes `qualified`.
local Core = NcmCore

Core.define("competition.race_tags", function()
    local M = { version = "1.1.0" }

    M.CATALOGUE = {
        { id="clean_race", label="Clean Race" }, { id="clean_run", label="Clean Run" },
        { id="close_finish", label="Close Finish" }, { id="clear_win", label="Clear Win" },
        { id="gained_positions", label="Gained Positions" }, { id="lost_positions", label="Lost Positions" },
        { id="good_start", label="Good Start" }, { id="led_every_gate", label="Led Every Gate" },
        { id="came_through", label="Came Through" }, { id="heavy_contact", label="Heavy Contact" },
        { id="tough_one", label="Tough One" }, { id="jump_start", label="Jump Start" },
        { id="penalised", label="Penalised" }, { id="did_not_finish", label="Did Not Finish" },
        { id="personal_best", label="Personal Best" }, { id="route_record", label="Route Record" },
    }
    M.PRIORITY = { "route_record","personal_best","clean_race","clean_run","clear_win","close_finish",
        "led_every_gate","came_through","good_start","gained_positions","lost_positions","heavy_contact",
        "tough_one","jump_start","penalised","did_not_finish" }
    local labels = {}; for _, x in ipairs(M.CATALOGUE) do labels[x.id] = x.label end

    local function count(t) return type(t)=="table" and #t or 0 end
    local function finished(r) return r.state == "finished" end
    local function clean(r)
        return finished(r) and (tonumber(r.incidentCount) or count(r.incidents)) == 0
            and count(r.penalties) == 0 and r.jumpStart ~= true
    end
    local function timeOf(r, kind)
        if kind == "race" then return finished(r) and tonumber(r.correctedSec or r.totalSec) or nil end
        return tonumber(r.bestSec)
    end
    local function crossing(r, gate)
        return type(r.crossings)=="table" and tonumber(r.crossings[gate]) or nil
    end
    local function earliest(results, row, gate)
        local t=crossing(row,gate); if not t then return false end
        for _,o in ipairs(results) do if o~=row then local x=crossing(o,gate); if x and x<=t then return false end end end
        return true
    end
    local function knownEarlier(results,row,gate)
        local t=crossing(row,gate); if not t then return false end
        for _,o in ipairs(results) do if o~=row then local x=crossing(o,gate); if x and x<t then return true end end end
        return false
    end
    local function gateOrder(results,row,gate)
        local t=crossing(row,gate); if not t then return nil end
        local before,missing=0,0
        for _,o in ipairs(results) do if o~=row then
            local x=crossing(o,gate); if not x then missing=missing+1 elseif x==t then return nil elseif x<t then before=before+1 end
        end end
        return 1+before+missing
    end
    local function heavy(r)
        for _,i in ipairs(r.incidents or {}) do if tonumber(i.band)==3 then return true end end
        return false
    end
    local function add(set,id) set[id]=true end
    local function ordered(set)
        local out={}; for _,id in ipairs(M.PRIORITY) do if set[id] then out[#out+1]={id=id,label=labels[id]} end end
        return out
    end

    function M.evaluate(facts, opts)
        if type(facts)~="table" or type(facts.session)~="table" or type(facts.results)~="table" then
            error("competition.race_tags.evaluate: facts/session/results required",2)
        end
        opts=opts or {}; local s=facts.session; local kind=s.kind
        if kind~="race" and kind~="quali" and kind~="practice" then return nil,"unknown_session_kind" end
        local field=tonumber(s.fieldSize) or #facts.results
        local tt=kind=="race" and (s.timeTrial==true or (s.timeTrial==nil and field<=1))
        local positionMode=kind=="race" and not tt and field>=2
        local maxTags=math.max(0,math.floor(tonumber(opts.maxTags) or 4))
        local closeSec=tonumber(opts.closeFinishSec) or 0.5
        local out={drivers={}}
        for idx,r in ipairs(facts.results) do
            if type(r.driverId)~="string" or r.driverId=="" or type(r.state)~="string" then
                error("competition.race_tags.evaluate: result identity/state required",2)
            end
            local set={}
            if r.state~="dns" and r.state~="dsq" then
                if clean(r) then add(set,tt and "clean_run" or (kind=="race" and "clean_race" or "clean_run")) end
                if heavy(r) then add(set,"heavy_contact") end
                if finished(r) and (tonumber(r.incidentCount) or 0)>=(tonumber(opts.toughIncidents) or 3) then add(set,"tough_one") end
                if kind=="race" then
                    if r.jumpStart==true then add(set,"jump_start") end
                    if count(r.penalties)>0 then add(set,"penalised") end
                    if r.state=="dnf" then add(set,"did_not_finish") end
                end
                local tm=timeOf(r,kind)
                if tm and tonumber(r.previousBestSec) and tm<tonumber(r.previousBestSec) then add(set,"personal_best") end
                if tm and tonumber(facts.routeRecordSec) and tm<tonumber(facts.routeRecordSec) then set.personal_best=nil; add(set,"route_record") end
                if positionMode and finished(r) then
                    local rt=timeOf(r,kind)
                    for j,o in ipairs(facts.results) do if j~=idx and finished(o) then
                        local ot=timeOf(o,kind); if rt and ot and math.abs(rt-ot)<=closeSec then add(set,"close_finish") end
                    end end
                    if r.position==1 then
                        local p2; for _,o in ipairs(facts.results) do if o.position==2 and finished(o) then p2=o end end
                        if p2 and rt and timeOf(p2,kind) and timeOf(p2,kind)-rt>=(tonumber(opts.clearWinSec) or 5) then add(set,"clear_win") end
                    end
                    if tonumber(r.slot) and tonumber(r.position) then
                        if r.slot-r.position >= (tonumber(opts.gainedMin) or 2) then add(set,"gained_positions") end
                        if r.position-r.slot >= (tonumber(opts.lostMin) or 2) then add(set,"lost_positions") end
                        local ord=gateOrder(facts.results,r,1)
                        if ord and r.slot-ord >= (tonumber(opts.goodStartMin) or 2) and r.jumpStart~=true then add(set,"good_start") end
                    end
                    if r.position==1 then
                        local led=tonumber(s.gatesTotal) and s.gatesTotal>0
                        for g=1,tonumber(s.gatesTotal) or 0 do if not earliest(facts.results,r,g) then led=false;break end end
                        if led then add(set,"led_every_gate") elseif knownEarlier(facts.results,r,1) then add(set,"came_through") end
                    end
                end
            end
            local qualified=ordered(set); local tags={}
            for i=1,math.min(maxTags,#qualified) do tags[i]=qualified[i] end
            out.drivers[idx]={driverId=r.driverId,position=r.position,state=r.state,qualified=qualified,tags=tags}
        end
        return out
    end
    return M
end)
