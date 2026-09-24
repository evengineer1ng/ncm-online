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

    -- ---------------------------------------------------------------------------------------------
    -- Market discovery: which markets a Driver has learned of, and on what footing (IDEA-251).
    -- ---------------------------------------------------------------------------------------------
    --
    -- **Exactly one value in each table, because exactly one producer exists.** L127 is the reason: the
    -- `machine_source` enum declared `team_equipment` ahead of any code that wrote it, on a misreading of the
    -- design, and migration 027 had to drop the column. `IDEA-298` introduces restricted and granted access,
    -- and it introduces the vocabulary in the same change as the code that produces it.
    --
    -- `open` is what `purchaseDecision` already calls `marketAccessible`. The two questions stay separate on
    -- purpose: a Driver may know a market exists and still not be able to source from it, which is the whole
    -- mechanism A2 left exclusivity to (`IDEA-298`).
    M.DISCOVERY_SOURCES = { universal = true }
    M.ACCESS_STATES = { open = true }

    function M.accessible(state) return state == "open" end

    --- Validate one durable record of "this Driver knows this market exists". `firstKnownAt` is a first-sight
    --- fact: hosts write it once and never update it, exactly as `vehicle_discovery.first_discovered_at` is
    --- written once. `sourceRef` is optional because a universal market has nothing to point at.
    function M.discovery(fact)
        if type(fact) ~= "table" then return nil, "no_fact" end
        if type(fact.driverId) ~= "string" or fact.driverId == "" then return nil, "no_driver" end
        if type(fact.serverId) ~= "string" or fact.serverId == "" then return nil, "no_server" end
        if type(fact.marketId) ~= "string" or not M.byId(fact.marketId) then
            return nil, "unknown_market:" .. tostring(fact.marketId)
        end
        if not M.DISCOVERY_SOURCES[fact.sourceKind] then
            return nil, "unknown_source:" .. tostring(fact.sourceKind)
        end
        if not M.ACCESS_STATES[fact.accessState] then
            return nil, "unknown_access:" .. tostring(fact.accessState)
        end
        if fact.sourceRef ~= nil and (type(fact.sourceRef) ~= "string" or #fact.sourceRef > 160) then
            return nil, "bad_source_ref"
        end
        local at = tonumber(fact.firstKnownAt)
        if at == nil or at < 0 or math.floor(at) ~= at then return nil, "bad_first_known_at" end
        return { driverId = fact.driverId, serverId = fact.serverId, marketId = fact.marketId,
                 firstKnownAt = at, sourceKind = fact.sourceKind, sourceRef = fact.sourceRef,
                 accessState = fact.accessState }
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
