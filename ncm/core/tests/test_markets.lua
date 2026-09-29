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
    ["twenty physical autofixers are distinct interaction-only markets"] = function(T)
        local M=T.Core.get("economy.markets");local coords,ids,models={}, {},0
        T.eq(#M.MARKETS,21,"base plus twenty physical markets")
        for _,m in ipairs(M.MARKETS) do if not m.universallyKnown then
            ids[m.marketId]=(ids[m.marketId] or 0)+1;coords[m.x..":"..m.y]=(coords[m.x..":"..m.y] or 0)+1
            T.eq(#m.vehicles>=1 and #m.vehicles<=3,true,m.marketId.." model count")
            T.eq(#m.partFamilies,2,m.marketId.." unique supply specialties")
            models=models+#m.vehicles
        end end
        for id,n in pairs(ids) do T.eq(n,1,id) end
        for xy,n in pairs(coords) do T.eq(n,1,xy) end
        T.eq(models>=40,true,"catalogue breadth")
        local fact=M.discovery({driverId="d1",serverId="ncm-dev",marketId="autofixer_badlands_01",
            firstKnownAt=1000,sourceKind="physical_terminal",sourceRef="autofixer_badlands_01",accessState="open"})
        T.eq(fact.marketId,"autofixer_badlands_01")
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
    ["market discovery records a first sight and refuses unwritable vocabulary"] = function(T)
        local M = T.Core.get("economy.markets")
        local ok = M.discovery({ driverId = "d1", serverId = "ncm-dev", marketId = M.BASE_ID,
            firstKnownAt = 1000, sourceKind = "universal", accessState = "open" })
        T.eq(ok.marketId, M.BASE_ID)
        T.eq(ok.sourceRef, nil)
        T.eq(M.accessible(ok.accessState), true)
        -- One value per table until IDEA-298 brings its own producer (L127).
        local _, why = M.discovery({ driverId = "d1", serverId = "ncm-dev", marketId = M.BASE_ID,
            firstKnownAt = 1000, sourceKind = "granted", accessState = "open" })
        T.eq(why, "unknown_source:granted")
        local _, why2 = M.discovery({ driverId = "d1", serverId = "ncm-dev", marketId = M.BASE_ID,
            firstKnownAt = 1000, sourceKind = "universal", accessState = "restricted" })
        T.eq(why2, "unknown_access:restricted")
        T.eq(M.accessible("restricted"), false)
        T.eq(M.accessible(nil), false)
    end,
    ["market discovery refuses a market that does not exist and a bad timestamp"] = function(T)
        local M = T.Core.get("economy.markets")
        local base = { driverId = "d1", serverId = "ncm-dev", marketId = M.BASE_ID,
            firstKnownAt = 1000, sourceKind = "universal", accessState = "open" }
        local function with(k, v)
            local f = {}; for a,b in pairs(base) do f[a]=b end; f[k]=v
            local _, why = M.discovery(f); return why
        end
        T.eq(with("marketId", "ncx_channel"), "unknown_market:ncx_channel")
        T.eq(with("driverId", ""), "no_driver")
        T.eq(with("serverId", nil), "no_server")
        T.eq(with("firstKnownAt", 1000.5), "bad_first_known_at")
        T.eq(with("sourceRef", string.rep("x", 161)), "bad_source_ref")
    end,
}
