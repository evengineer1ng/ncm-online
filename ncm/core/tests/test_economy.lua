local M = NcmCore.get("economy.settlement")

local function economy()
    return {
        entryFee=50, timeTrialCompletion=250, raceCompletion=300, repeatFloor=50,
        placement={[1]=350,[2]=150,[3]=75}, fieldBonus={perEntrant=50,max=250},
        targets={{id="i",label="Target I",sec=120,amount=100},{id="ii",label="Target II",sec=100,amount=250},{id="iii",label="Target III",sec=80,amount=500}},
        tagBounties={clean_run=50,clean_race=75,personal_best=100}, maxTagBounty=150,
    }
end
local function amount(out,kind)
    for _,x in ipairs(out.lines) do if x.kind==kind then return x.amount end end
end
local cases={}
cases.solo_is_paid_time_trial_not_p1=function(T)
    local out=M.resolve({economy=economy(),fieldSize=1,result={state="finished",position=1,totalSec=110},tags={{id="clean_run",label="Clean Run"}}})
    T.ok(out.timeTrial); T.eq(amount(out,"event_completion"),250); T.eq(amount(out,"event_placement"),nil); T.eq(out.gross,400); T.eq(out.net,350)
end
cases.contested_pays_completion_place_and_capped_field=function(T)
    local out=M.resolve({economy=economy(),fieldSize=20,result={state="finished",position=1,totalSec=130}})
    T.eq(amount(out,"event_completion"),300); T.eq(amount(out,"event_placement"),350); T.eq(amount(out,"event_field_bonus"),250)
end
cases.highest_target_only=function(T)
    local out=M.resolve({economy=economy(),fieldSize=1,result={state="finished",position=1,totalSec=79}})
    T.eq(amount(out,"event_target"),500)
    local n=0; for _,x in ipairs(out.lines) do if x.kind=="event_target" then n=n+1 end end; T.eq(n,1)
end
cases.dnf_dns_dsq_pay_nothing=function(T)
    for _,state in ipairs({"dnf","dns","dsq"}) do
        local out=M.resolve({economy=economy(),fieldSize=2,result={state=state,position=1,totalSec=79},tags={{id="clean_race"}}})
        T.eq(out.gross,0); T.eq(#out.lines,0)
    end
end
cases.repeat_uses_recovery_floor=function(T)
    local out=M.resolve({economy=economy(),fieldSize=1,repeatCompletion=true,result={state="finished",position=1,totalSec=130}})
    T.eq(amount(out,"event_completion"),50)
end
cases.tag_allow_list_and_cap=function(T)
    local out=M.resolve({economy=economy(),fieldSize=2,result={state="finished",position=2,totalSec=130},tags={
        {id="clean_race",label="Clean Race"},{id="personal_best",label="Personal Best"},{id="jump_start",label="Jump Start"}}})
    local total=0; for _,x in ipairs(out.lines) do if x.kind=="tag_bonus" then total=total+x.amount end end
    T.eq(total,150)
end
cases.invalid_config_fails_closed=function(T)
    local e=economy(); e.entryFee=-1
    local out,why=M.resolve({economy=e,fieldSize=1,result={state="finished"}})
    T.eq(out,nil); T.eq(why,"invalid_entry_fee")
end
return cases
