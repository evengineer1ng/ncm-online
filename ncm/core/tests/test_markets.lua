return {
    ["base market is one stable market and starter stock is valid"] = function(T)
        local M = T.Core.get("economy.markets")
        T.eq(M.validate(), true)
        T.eq(M.BASE_ID, "base_market")
        T.eq(#M.known(), 1)
        T.eq(#M.STARTER_STOCK, 3)
    end,
    ["known markets expose no undiscovered placeholders or total"] = function(T)
        local M = T.Core.get("economy.markets")
        local known = M.known(M.MARKETS, { "not_a_market" })
        T.eq(#known, 1)
        T.eq(known[1].marketId, "base_market")
        T.eq(known.total, nil)
    end,
    ["visible eligible and affordable are independent gates"] = function(T)
        local M = T.Core.get("economy.markets")
        local base = { marketKnown=true, marketAccessible=true, visible=true, available=true,
            eligible=true, balance=10000, price=2500 }
        T.eq(M.purchaseDecision(base).ok, true)
        for field, reason in pairs({ marketKnown="market_unknown", marketAccessible="market_inaccessible",
                visible="stock_not_visible", available="stock_unavailable", eligible="not_eligible" }) do
            local f = {}; for k,v in pairs(base) do f[k]=v end; f[field]=false
            T.eq(M.purchaseDecision(f).reason, reason)
        end
        base.balance=2499
        T.eq(M.purchaseDecision(base).reason, "unaffordable")
    end,
}
