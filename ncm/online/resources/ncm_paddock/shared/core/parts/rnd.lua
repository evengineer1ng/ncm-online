-- Deterministic manufacturer R&D decisions. Persistence owns cadence/run claims; this owns repeatable outcomes.
local Core=NcmCore
Core.define("parts.rnd",function(C)
    local M={version="1.0.0",logicVersion=1}
    local Catalogue=C.get("parts.catalogue")
    local ids=C.get("vocabulary.ids")
    M.MAKERS={
        makigai={ offsetSec=72*3600, families={"cooling","tires","electrical","aerodynamics"} },
        thorton={ offsetSec=96*3600, families={"power_unit","transmission","drivetrain","suspension","chassis"} },
        archer={ offsetSec=120*3600, families={"brakes","structure"} },
    }
    M.CADENCE_SEC=72*3600
    local function hash(s) local h=2166136261 for i=1,#s do h=(h*16777619+s:byte(i))%4294967296 end return h end
    function M.evaluate(input)
        input=input or {}; local maker=M.MAKERS[input.makerKey]
        if not maker then return nil,"unknown_maker" end
        local run=math.floor(tonumber(input.runIndex) or -1); if run<0 then return nil,"bad_run_index" end
        local rng=ids.seededRng(hash(table.concat({tostring(input.secret or ""),input.makerKey,tostring(run),tostring(M.logicVersion)},":")))
        if rng()>=.50 then return {outcome="no_design",reason="no_candidate",runIndex=run,makerKey=input.makerKey} end
        local family=maker.families[math.floor(rng()*#maker.families)+1]
        local roll=rng(); local lo,hi
        if roll<.10 then lo,hi=.90,.98 elseif roll<.70 then lo,hi=.98,1.18 elseif roll<.95 then lo,hi=1.18,1.30
        elseif roll<.99 then lo,hi=1.30,1.36 else lo,hi=1.36,1.40 end
        local effect=math.floor((lo+(hi-lo)*rng())*100+.5)/100
        local scope=rng(); local distribution=scope<.60 and "base" or (scope<.90 and "specialist" or "experimental")
        local supported={}
        if distribution=="base" then
            for _,v in ipairs(Catalogue.STARTER_VEHICLES) do supported[#supported+1]=v end
        else
            supported[1]=Catalogue.STARTER_VEHICLES[math.floor(rng()*#Catalogue.STARTER_VEHICLES)+1]
        end
        local candidate={ family=family,effect=effect,price=Catalogue.priceFor(family,effect),distribution=distribution,
            supportedVehicles=supported,makerKey=input.makerKey,runIndex=run }
        -- A pure improvement below stock is dominated unless its price creates an actual economy trade-off.
        if effect<1 and candidate.price>=Catalogue.priceFor(family,1.00) then
            return {outcome="no_design",reason="dominated",runIndex=run,makerKey=input.makerKey,candidate=candidate}
        end
        if distribution=="base" then
            local ok,why=Catalogue.marketAdmissible(candidate)
            if not ok then return {outcome="no_design",reason=why,runIndex=run,makerKey=input.makerKey,candidate=candidate} end
        end
        candidate.designId=("rnd:%s:%06d"):format(input.makerKey,run)
        candidate.lineageId=candidate.designId; candidate.revision=1; candidate.tier="rnd"; candidate.origin="rnd"
        candidate.code=("%s-R%06d"):format(input.makerKey:sub(1,3):upper(),run)
        candidate.subtitle="Development System"; candidate.positions=Catalogue.INTERFACES[family]
        candidate.fidelity=Catalogue.FIDELITY[family] or "modelled"
        return {outcome="accepted",reason="novel_tradeoff",runIndex=run,makerKey=input.makerKey,candidate=candidate}
    end
    return M
end)
