local function Cat(T) return T.Core.get("parts.catalogue") end
return {
  launch_catalogue_is_exact=function(T)
    local C=Cat(T); T.eq(#C.designs(),25,"11 street + 11 sport + 3 premium")
    local counts={street=0,sport=0,premium=0}
    for _,d in ipairs(C.designs()) do counts[d.tier]=counts[d.tier]+1; T.eq(#d.positions>0,true,d.designId) end
    T.eq(counts.street,11,"");T.eq(counts.sport,11,"");T.eq(counts.premium,3,"")
    T.eq(C.byId("launch:power_unit:premium").price,4000,"")
    T.eq(C.byId("launch:tires:premium").effect,1.30,"")
  end,
  launch_fitment_is_balanced=function(T)
    local C=Cat(T); local n={makigai_maimai=0,thorton_galena=0,archer_hella=0}
    for _,d in ipairs(C.designs()) do if d.tier=="sport" then for k in pairs(n) do if C.resolve(d,k).compatible then n[k]=n[k]+1 end end end end
    T.eq(n.makigai_maimai,7,"");T.eq(n.thorton_galena,8,"");T.eq(n.archer_hella,7,"")
    for _,d in ipairs(C.designs()) do if d.tier~="sport" then for k in pairs(n) do T.eq(C.resolve(d,k).compatible,true,d.designId.." fits "..k) end end end
  end,
  unresolved_fitment_blocks_primary_admission=function(T)
    local C=Cat(T); local ok,why=C.marketAdmissible({supportedVehicles={"makigai_maimai"}}, {"makigai_maimai","future_car"})
    T.eq(ok,false,"");T.match(why,"unresolved","")
  end,
  kits_cover_nineteen_positions_once=function(T)
    local C=Cat(T); local n=0 for _,f in ipairs(C.FAMILIES) do n=n+#C.INTERFACES[f] end
    T.eq(n,19,"")
  end,
  rnd_is_repeatable_and_bounded=function(T)
    local R=T.Core.get("parts.rnd")
    for i=0,80 do local a=R.evaluate({makerKey="makigai",runIndex=i,secret="fixture"}); local b=R.evaluate({makerKey="makigai",runIndex=i,secret="fixture"})
      T.eq(a.outcome,b.outcome,"");T.eq(a.reason,b.reason,"")
      if a.candidate then T.eq(a.candidate.effect>=.90 and a.candidate.effect<=1.40,true,"") end
    end
  end,
}
