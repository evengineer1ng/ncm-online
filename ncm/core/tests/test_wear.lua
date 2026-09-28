local function W(T) return T.Core.get("parts.wear") end

return {
    same_asset_and_history_are_deterministic = function(T)
        local Wm=W(T);local a={assetId="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",family="brakes"}
        a.exposureM=Wm.baseThreshold(Wm.profile("brakes"),a.assetId)+1000000
        local x,y=Wm.evaluate(a,{}),Wm.evaluate(a,{})
        T.eq(x.baseThresholdM,y.baseThresholdM);T.eq(x.status,y.status);T.eq(x.conditions[1].severity,y.conditions[1].severity)
    end,
    asset_identity_varies_threshold_inside_bounds = function(T)
        local Wm=W(T);local p=Wm.profile("tires")
        local a=Wm.baseThreshold(p,"asset-a");local b=Wm.baseThreshold(p,"asset-b")
        T.neq(a,b);T.ok(a>=p.onsetMinM and a<=p.onsetMaxM);T.ok(b>=p.onsetMinM and b<=p.onsetMaxM)
    end,
    onset_envelopes_are_broad_overlapping_and_leave_150km_fresh = function(T)
        local Wm=W(T)
        for family,p in pairs(Wm.PROFILES) do
            T.ok(p.onsetMaxM/p.onsetMinM>=8,family.." envelope is not broad")
            T.ok(p.onsetMinM>150000,family.." can demand service at 150 km")
        end
        T.ok(Wm.profile("brakes").onsetMinM<Wm.profile("tires").onsetMaxM)
        T.ok(Wm.profile("cooling").onsetMinM<Wm.profile("suspension").onsetMaxM)
    end,
    exposure_is_never_mutated_and_condition_is_derived = function(T)
        local Wm=W(T);local a={assetId="x",family="tires"}
        a.exposureM=Wm.baseThreshold(Wm.profile("tires"),a.assetId)*3;local before=a.exposureM
        local s=Wm.evaluate(a,{});T.eq(a.exposureM,before);T.eq(s.status,"critical");T.ok(s.conditions[1].severity<=1)
    end,
    families_without_meaningful_mileage_wear_stay_normal = function(T)
        local Wm=W(T)
        for _,f in ipairs({"aerodynamics","structure","chassis"}) do T.eq(Wm.evaluate({assetId=f,family=f,exposureM=99999999},{}).status,"normal") end
    end,
    service_advances_only_the_named_threshold = function(T)
        local Wm=W(T);local a={assetId="service-me",family="brakes"}
        a.exposureM=Wm.baseThreshold(Wm.profile("brakes"),a.assetId)+45000
        local before=Wm.evaluate(a,{});local q=Wm.serviceQuote(a,{},"brake_fade_early");T.ok(q and q.reliefM>0 and q.cost>0)
        local after=Wm.evaluate(a,{{conditionId=q.conditionId,reliefM=q.reliefM}})
        T.eq(after.exposureM,before.exposureM);T.ok(after.effectiveThresholdM>before.effectiveThresholdM)
        T.ok(after.status=="normal" or after.conditions[1].severity<before.conditions[1].severity)
    end,
    relief_is_capped_so_service_cannot_make_a_part_immortal = function(T)
        local Wm=W(T);local a={assetId="cap",family="power_unit",exposureM=9999999};local p=Wm.profile("power_unit")
        local s=Wm.evaluate(a,{{conditionId=p.id,reliefM=999999999}});T.eq(s.serviceReliefM,s.serviceIntervalM*2)
    end,
    wear_is_downward_only_and_system_warnings_are_compact = function(T)
        local Wm=W(T);local tp=Wm.profile("tires");local bp=Wm.profile("brakes");local m=Wm.machine({
            {assetId="t",family="tires",exposureM=Wm.baseThreshold(tp,"t")*3},
            {assetId="b",family="brakes",exposureM=Wm.baseThreshold(bp,"b")*3},
            {assetId="a",family="aerodynamics",exposureM=999999}}, {})
        T.ok(m.contributor.gripScale<=1 and m.contributor.driveScale<=1 and m.contributor.brakeScale<=1 and m.contributor.dragScale<=1)
        T.eq(m.warnings[1].system,"service");T.eq(#m.warnings,3,"master plus tyre and brake")
    end,
    public_state_does_not_leak_threshold_or_severity = function(T)
        local Wm=W(T);local profile=Wm.profile("tires")
        local s=Wm.evaluate({assetId="private",family="tires",exposureM=Wm.baseThreshold(profile,"private")*3},{})
        local p=Wm.publicState(s);T.eq(p.status,"critical");T.eq(p.conditions[1].id,"tire_peak_loss");T.eq(p.conditions[1].severity,nil);T.eq(p.effectiveThresholdM,nil)
    end,
}
