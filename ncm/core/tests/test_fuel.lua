return {
  burn_is_distance_based_and_bounded=function(T)
   local F=T.Core.get("economy.fuel")
   local r=F.burn(60000,1000,nil,0);T.eq(r.fuelMl,59650);T.eq(r.burnedMl,350);T.falsy(r.empty)
   local e=F.burn(100,1000,nil,0);T.eq(e.fuelMl,0);T.truthy(e.becameEmpty)
  end,
  fractional_burn_survives_samples=function(T)
   local F=T.Core.get("economy.fuel")
   local a=F.burn(10,1,nil,0);T.eq(a.burnedMl,0)
   local b=F.burn(a.fuelMl,2,nil,a.remainderMl);T.eq(b.burnedMl,1)
  end,
  nearest_station_is_geometric=function(T)
   local F=T.Core.get("economy.fuel")
   local s,d=F.nearest({x=0,y=0},{{id="far",x=10,y=0},{id="near",x=3,y=4}});T.eq(s.id,"near");T.eq(d,5)
  end,
  fill_cost_uses_missing_litres=function(T)
   local F=T.Core.get("economy.fuel")
   local ml,c=F.fillCost(50000,nil,200);T.eq(ml,10000);T.eq(c,2000)
  end,
}
