local function first(R, programme, continuity)
    for run=0,30 do
        local input={programmeKey=programme,runIndex=run,secret="fixture:"..continuity,serverId=continuity,competency=0}
        local result=assert(R.evaluatePhysical(input))
        if result.outcome=="accepted" then return result,input end
    end
    error("no accepted physical Design in 31 evaluations")
end

return {
    physical_research_replays_and_tapes_do_not_collide=function(T)
        local R=T.Core.get("parts.rnd")
        local a,input=first(R,"zetatech:propulsor","tape-a")
        local repeatRun=R.evaluatePhysical(input)
        T.eq(a.candidate.designId,repeatRun.candidate.designId,"")
        T.eq(a.candidate.perf.ispS,repeatRun.candidate.perf.ispS,"")
        local b=R.evaluatePhysical({programmeKey=input.programmeKey,runIndex=input.runIndex,
            secret="fixture:tape-b",serverId="tape-b",competency=0})
        if b.outcome=="accepted" then T.ok(a.candidate.designId~=b.candidate.designId,"tape Designs need distinct global IDs") end
        T.ok(a.candidate.perf.ispS<=360,"fuel chemistry ceiling")
        T.eq(a.candidate.parentDesignId,"eng:zetatech:rp16:r1","")
    end,
    researched_hardware_registers_and_resolves=function(T)
        local R=T.Core.get("parts.rnd")
        local Install=T.Core.get("engineering.installation")
        local result=first(R,"zetatech:attitude","tape-test")
        local d,why=Install.register(result.candidate)
        T.ok(d~=nil,tostring(why))
        T.eq(Install.design(d.designId).perf.kind,"attitude_control","")
        local devices,refused=Install.resolve({{componentId="test",designId=d.designId,
            mountId="mount.roof",facing="up"}},"archer_hella")
        T.eq(#refused,0,"")
        T.eq(#devices,1,"")
    end,
    first_week_yields_a_plausible_flight_kit=function(T)
        local R=T.Core.get("parts.rnd")
        local complete=0
        for tape=1,100 do
            local ready=true
            for programme in pairs(R.PHYSICAL) do
                local found=false
                for run=0,2 do
                    local result=R.evaluatePhysical({programmeKey=programme,runIndex=run,
                        secret="pace:"..tape,serverId="pace:"..tape,competency=run*4})
                    if result.outcome=="accepted" then found=true;break end
                end
                if not found then ready=false;break end
            end
            if ready then complete=complete+1 end
        end
        T.ok(complete>=80,("only %d/100 continuities have all five families by the third run"):format(complete))
    end,
}
