local M=NcmCore.get("economy.trade")
local cases={}

local function offer(over)
    local x={aDriverId="a",bDriverId="b",a={money=100,machines={"m1"},components={}},b={money=0,machines={},components={"p1"}}}
    for k,v in pairs(over or {}) do x[k]=v end
    return x
end

cases.normalizes_and_sorts_exact_assets=function(T)
    local o=M.offer{aDriverId="a",bDriverId="b",a={machines={"m2","m1"}},b={components={"p2","p1"}}}
    T.eq(o.a.machines[1],"m1");T.eq(o.b.components[1],"p1");T.eq(o.assetCount,4)
end

cases.refuses_same_party_and_cross_side_duplicates=function(T)
    T.eq(select(2,M.offer{aDriverId="a",bDriverId="a",a={machines={"m"}},b={money=1}}),"same_party")
    T.eq(select(2,M.offer{aDriverId="a",bDriverId="b",a={machines={"m"}},b={components={"m"}}}),"asset_on_both_sides")
end

cases.refuses_money_only_and_one_sided_gifts=function(T)
    T.eq(select(2,M.offer{aDriverId="a",bDriverId="b",a={money=10},b={}}),"asset_required")
    T.eq(select(2,M.offer{aDriverId="a",bDriverId="b",a={machines={"m"}},b={}}),"both_sides_empty")
    T.eq(select(2,M.offer{aDriverId="a",bDriverId="b",a={money=10,machines={"m"}},b={}}),"both_sides_empty")
end

cases.cash_can_exist_on_only_one_side=function(T)
    T.eq(select(2,M.offer{aDriverId="a",bDriverId="b",a={money=1,machines={"m"}},b={money=2,components={"p"}}}),"cash_on_both_sides")
    T.ok(M.offer(offer()))
end

cases.money_is_bounded_integer=function(T)
    T.eq(select(2,M.side{money=-1}),"invalid_money")
    T.eq(select(2,M.side{money=1.5}),"invalid_money")
    T.eq(select(2,M.side{money=M.MAX_MONEY+1}),"invalid_money")
end

cases.assets_are_unique_and_bounded=function(T)
    T.eq(select(2,M.side{machines={"x","x"}}),"duplicate_asset")
    local many={};for i=1,M.MAX_ASSETS_PER_SIDE+1 do many[i]="p"..i end
    T.eq(select(2,M.side{components=many}),"too_many_assets")
end

cases.side_for_projects_the_two_parties=function(T)
    local o=M.offer(offer())
    local mine,theirs,key=M.sideFor(o,"b")
    T.eq(key,"b");T.eq(mine.components[1],"p1");T.eq(theirs.machines[1],"m1")
    T.eq(select(2,M.sideFor(o,"c")),"not_party")
end

cases.settlement_needs_current_dual_consent=function(T)
    local t=offer{state="active",revision=3,expiresAt=200,aConfirmed=true,bConfirmed=true,aConfirmedRevision=3,bConfirmedRevision=3}
    T.ok(M.canSettle(t,100))
    t.bConfirmedRevision=2;T.eq(select(2,M.canSettle(t,100)),"stale_confirmation")
    t.bConfirmedRevision=3;t.expiresAt=100;T.eq(select(2,M.canSettle(t,100)),"expired")
end

cases.summary_is_safe_for_missing_fields=function(T)
    local s=M.summary(nil);T.eq(s.money,0);T.eq(s.machines,0);T.eq(s.components,0)
end

return cases
