-- Deterministic manufacturer R&D decisions. Persistence owns cadence/run claims; this owns repeatable outcomes.
local Core=NcmCore
Core.define("parts.rnd",function(C)
    local M={version="1.0.0",logicVersion=1}
    local Catalogue=C.get("parts.catalogue")
    local ids=C.get("vocabulary.ids")
    local Install=C.get("engineering.installation")
    local Lineage=C.get("engineering.lineage")
    local Seed=C.get("world.seed")
    local Hash=C.get("vocabulary.hash")
    local Systems=C.get("engineering.systems")
    M.MAKERS={
        makigai={ offsetSec=72*3600, families={"cooling","tires","electrical","aerodynamics"} },
        thorton={ offsetSec=96*3600, families={"power_unit","transmission","drivetrain","suspension","chassis"} },
        archer={ offsetSec=120*3600, families={"brakes","structure"} },
    }
    M.CADENCE_SEC=72*3600
    -- Programme keys occupy the existing maker_key claim namespace; v1 maker keys and rows are untouched.
    M.PHYSICAL={
        ["zetatech:attitude"]={makerKey="zetatech",root="eng:zetatech:ac6:r1",offsetSec=12*3600},
        ["zetatech:propulsor"]={makerKey="zetatech",root="eng:zetatech:rp16:r1",offsetSec=18*3600},
        ["archer:impulse"]={makerKey="archer",root="eng:archer:ia10:r1",offsetSec=24*3600},
        ["zetatech:tank"]={makerKey="zetatech",root="eng:zetatech:pt500:r1",offsetSec=30*3600},
        ["zetatech:fusion"]={makerKey="zetatech",root="eng:zetatech:fd1:r1",offsetSec=36*3600},
    }
    M.PHYSICAL_CADENCE_SEC=48*3600
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
    function M.evaluatePhysical(input)
        input=input or {}
        local programme=M.PHYSICAL[input.programmeKey]
        local run=math.floor(tonumber(input.runIndex) or -1)
        if not programme or run<0 then return nil,"bad_physical_programme" end
        local root=Install.design(programme.root)
        if not root then return nil,"missing_lineage_root" end
        local rng=Seed.root(tostring(input.secret or "")):child("physical-rnd",input.programmeKey,run,2):stream()
        local function no(reason) return {outcome="no_design",reason=reason,programmeKey=input.programmeKey,runIndex=run} end
        -- Parallel programmes preserve real failures while giving the first flight ladder a credible first week.
        if rng()<0.20 then return no("no_candidate") end
        local source=Seed.deepCopy(root)
        local ceiling=Lineage.ISP_CEILING[source.perf.propellant]
        if ceiling and source.perf.ispS then source.perf.ispS=math.min(source.perf.ispS,ceiling) end
        local registry=Lineage.newRegistry()
        registry:newLineage(source,"night_city",programme.makerKey,{id=programme.root})
        local rec,failed=registry:reverseEngineer(programme.root,{knowledge="documents",competency=tonumber(input.competency) or 0,
            rng=rng,origin="night_city",principal=programme.makerKey,intent="derive"})
        if not rec then return no(failed and failed.reason or "research_failed") end
        local spec=rec.design
        local continuity=Hash.commit(tostring(input.serverId or ""))
        spec.designId=("rndp:%s:%s:%06d"):format(continuity,input.programmeKey,run)
        spec.lineageId=root.lineageId
        spec.revision=run+2
        spec.makerKey=programme.makerKey
        spec.manufacturer=root.manufacturer
        spec.code=("%s-%s-R%03d"):format(root.code,continuity,run+2)
        spec.name=("%s R%d"):format(root.name,run+2)
        spec.parentDesignId=programme.root
        spec.origin="rnd_physical"
        spec.distribution="base"
        spec.fidelity="physical"
        spec.effect=1
        spec.price=Catalogue.pricePhysical(spec,root)
        spec.tier=spec.price>=12000 and "premium" or (spec.price>=5000 and "sport" or "street")
        spec.positions={}
        spec.supportedVehicles={}
        local valid,why=Systems.validate(spec.perf)
        if not valid then return no(table.concat(why,"; ")) end
        return {outcome="accepted",reason="derived_physical_design",programmeKey=input.programmeKey,runIndex=run,candidate=spec}
    end
    return M
end)
