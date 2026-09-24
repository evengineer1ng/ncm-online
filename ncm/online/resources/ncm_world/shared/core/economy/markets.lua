-- Pure Market Network vocabulary and starter authored data (IDEA-198/L104).
local Core = NcmCore

Core.define("economy.markets", function(C)
    local Catalogue = C.get("data.vehicle_catalogue")
    local M = { version = "0.1.0", BASE_ID = "base_market", STARTER_GRANT = 10000 }

    M.MARKETS = {
        { marketId = M.BASE_ID, displayName = "Base Market", universallyKnown = true, kind = "primary" },
    }

    -- Provisional balancing data. Each slot is one real asset in the alpha_launch allocation.
    M.STARTER_STOCK = {
        { slot = 1, assetId = "10000000-0000-4000-8000-000000000001", vehicleKey = "makigai_maimai", price = 2500 },
        { slot = 2, assetId = "10000000-0000-4000-8000-000000000002", vehicleKey = "thorton_galena", price = 4500 },
        { slot = 3, assetId = "10000000-0000-4000-8000-000000000003", vehicleKey = "archer_hella", price = 7500 },
    }

    function M.byId(id)
        for _, market in ipairs(M.MARKETS) do if market.marketId == id then return market end end
        return nil
    end

    function M.known(markets, grants)
        local out, seen = {}, {}
        for _, market in ipairs(markets or M.MARKETS) do
            if market.universallyKnown then out[#out + 1], seen[market.marketId] = market, true end
        end
        for _, id in ipairs(grants or {}) do
            local market = M.byId(id)
            if market and not seen[id] then out[#out + 1], seen[id] = market, true end
        end
        return out
    end

    function M.validate()
        local marketIds, assets, slots = {}, {}, {}
        for _, market in ipairs(M.MARKETS) do
            if marketIds[market.marketId] then return false, "duplicate_market:" .. market.marketId end
            marketIds[market.marketId] = true
        end
        for _, row in ipairs(M.STARTER_STOCK) do
            if assets[row.assetId] then return false, "duplicate_asset:" .. row.assetId end
            if slots[row.slot] then return false, "duplicate_slot:" .. tostring(row.slot) end
            if not Catalogue.byKey(row.vehicleKey) then return false, "unknown_vehicle:" .. row.vehicleKey end
            if type(row.price) ~= "number" or row.price < 0 or math.floor(row.price) ~= row.price then
                return false, "bad_price:" .. tostring(row.slot)
            end
            assets[row.assetId], slots[row.slot] = true, true
        end
        return true
    end

    function M.purchaseDecision(facts)
        if type(facts) ~= "table" then return { ok = false, reason = "invalid" } end
        if not facts.marketKnown then return { ok = false, reason = "market_unknown" } end
        if not facts.marketAccessible then return { ok = false, reason = "market_inaccessible" } end
        if not facts.visible then return { ok = false, reason = "stock_not_visible" } end
        if not facts.available then return { ok = false, reason = "stock_unavailable" } end
        if not facts.eligible then return { ok = false, reason = "not_eligible" } end
        if (tonumber(facts.balance) or 0) < (tonumber(facts.price) or 0) then
            return { ok = false, reason = "unaffordable" }
        end
        return { ok = true }
    end

    return M
end)
