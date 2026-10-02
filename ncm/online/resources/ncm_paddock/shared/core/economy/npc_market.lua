-- ncm-core module: economy.npc_market
-- NPCs in the markets (L249 step 4, IDEA-730; owner: "all markets need buyers"). Pure rules; the Paddock host moves
-- the assets and the money (`ncm_paddock/server/markets.lua`).
--
-- A Paddock team's car is four development areas (`paddock.car`); an NCM part belongs to one of eleven families
-- (`parts.catalogue`). A real part, bought and fitted, develops the area its family serves -- worth more than the
-- same eddies spent on workshop hours, and more again for a better tier. The rules here decide which areas need
-- work, which parts fit a buyer and a budget, what a part is worth to a particular NPC (the Exchange's valuation),
-- and which fitted parts a newer one makes surplus.
local Core = NcmCore

Core.define("economy.npc_market", function(C)
    local M = { version = "0.1.0" }
    local Car = C.get("paddock.car")

    -- which development area each part family serves
    M.FAMILY_AREA = {
        power_unit = "power_unit", cooling = "power_unit", transmission = "power_unit", drivetrain = "power_unit",
        electrical = "power_unit", aerodynamics = "aerodynamics", tires = "tires", brakes = "tires",
        suspension = "chassis", structure = "chassis", chassis = "chassis",
    }
    M.AREA_FAMILIES = {}
    for fam, area in pairs(M.FAMILY_AREA) do
        M.AREA_FAMILIES[area] = M.AREA_FAMILIES[area] or {}
        table.insert(M.AREA_FAMILIES[area], fam)
    end
    for _, list in pairs(M.AREA_FAMILIES) do table.sort(list) end

    -- the part tiers a racer of each Paddock tier shops for (a street racer cannot use a premium part's budget)
    M.TIER_PARTS = { street = { street = true, sport = true }, regional = { street = true, sport = true },
        pro = { sport = true, premium = true }, premier = { sport = true, premium = true } }
    -- a fitted part develops its area by its price times this (workshop hours alone count 1.0)
    M.PART_VALUE = { street = 1.15, sport = 1.3, premium = 1.45 }
    M.TIER_RANK = { street = 1, sport = 2, premium = 3 }

    --- Development eddies a part of `partTier` bought for `price` puts into its area.
    function M.devValue(price, partTier)
        return math.floor((tonumber(price) or 0) * (M.PART_VALUE[partTier] or 1) + 0.5)
    end

    --- The car's areas, weakest first (ties by the area's weight, heavier first): where a part does the most good.
    function M.neediest(car)
        local out = {}
        for _, a in ipairs(Car.AREAS) do out[#out + 1] = { area = a, level = tonumber(car and car[a]) or 1 } end
        table.sort(out, function(x, y)
            if x.level ~= y.level then return x.level < y.level end
            if (Car.WEIGHTS[x.area] or 0) ~= (Car.WEIGHTS[y.area] or 0) then return (Car.WEIGHTS[x.area] or 0) > (Car.WEIGHTS[y.area] or 0) end
            return x.area < y.area
        end)
        return out
    end

    --- Of `offers` ({ assetId, marketId, price, family, tier, listedAt }), the one an NPC of `buyerTier` buys for
    --- `area` with `budget`: the best tier it shops for that fits the budget, cheapest within that tier, then the
    --- longest-listed. Offers listed less than `minAgeSec` ago are left to players (first claim). nil when none fit.
    function M.choose(offers, area, budget, buyerTier, now, minAgeSec)
        local fams = {}
        for _, f in ipairs(M.AREA_FAMILIES[area] or {}) do fams[f] = true end
        local allowed = M.TIER_PARTS[buyerTier] or M.TIER_PARTS.street
        local best
        for _, o in ipairs(offers or {}) do
            local price = tonumber(o.price) or math.huge
            local aged = (tonumber(now) or 0) - (tonumber(o.listedAt) or 0) >= (minAgeSec or 0)
            if fams[o.family] and allowed[o.tier] and price <= (budget or 0) and aged then
                if not best then best = o
                else
                    local rb, ro = M.TIER_RANK[best.tier] or 0, M.TIER_RANK[o.tier] or 0
                    if ro > rb or (ro == rb and (price < tonumber(best.price) or (price == tonumber(best.price) and
                        ((tonumber(o.listedAt) or 0) < (tonumber(best.listedAt) or 0) or
                        ((tonumber(o.listedAt) or 0) == (tonumber(best.listedAt) or 0) and tostring(o.assetId) < tostring(best.assetId)))))) then
                        best = o
                    end
                end
            end
        end
        return best
    end

    --- The most an NPC will pay for a part (the Exchange): the list price, scaled by how much the area needs it
    --- (weakest area 1.25x, strongest 0.8x), by tier fit, and by the NPC's appetite (personality risk 0..100).
    --- 0 when the part is no use to them (a tier they do not race, or a family they cannot use).
    function M.reservation(part, car, buyerTier, risk)
        local area = M.FAMILY_AREA[part and part.family or ""]
        if not area then return 0 end
        local allowed = M.TIER_PARTS[buyerTier] or M.TIER_PARTS.street
        if not allowed[part.tier] then return 0 end
        local rank = 1
        for i, n in ipairs(M.neediest(car)) do if n.area == area then rank = i end end
        local need = ({ 1.25, 1.1, 0.95, 0.8 })[rank] or 0.8
        local appetite = 0.9 + 0.2 * math.max(0, math.min(100, tonumber(risk) or 50)) / 100
        return math.floor((tonumber(part.price) or 0) * need * appetite + 0.5)
    end

    --- The least an NPC will sell a surplus part for: its list price less wear and the NPC's patience.
    function M.askFloor(part, risk)
        local patience = 0.95 - 0.25 * math.max(0, math.min(100, tonumber(risk) or 50)) / 100
        return math.floor((tonumber(part and part.price) or 0) * patience + 0.5)
    end

    --- Of `fitted` parts ({ assetId, family, tier }) and a newly fitted part, the fitted one it makes surplus: same
    --- family, lower tier. nil when it replaces nothing.
    function M.displaced(fitted, newPart)
        local worst
        for _, p in ipairs(fitted or {}) do
            if p.family == newPart.family and p.assetId ~= newPart.assetId
                and (M.TIER_RANK[p.tier] or 0) <= (M.TIER_RANK[newPart.tier] or 0) then
                if not worst or (M.TIER_RANK[p.tier] or 0) < (M.TIER_RANK[worst.tier] or 0) then worst = p end
            end
        end
        return worst
    end

    --- A principal key for market/exchange rows: "org:o012", "person:p01234".
    function M.principal(kind, id) return tostring(kind) .. ":" .. tostring(id) end
    function M.parsePrincipal(key)
        local kind, id = tostring(key or ""):match("^(%a+):(.+)$")
        return kind, id
    end

    return M
end)
