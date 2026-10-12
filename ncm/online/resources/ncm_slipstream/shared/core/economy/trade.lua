-- economy.trade -- pure validation and projection for the synchronous Exchange envelope.
--
-- The host owns presence, persistence and settlement. This module owns the rules that must agree on every
-- surface: exact assets, one cash leg, bounded offers, revision-bound consent, and deterministic summaries.
local M = {}

M.VERSION = 1
M.MAX_ASSETS_PER_SIDE = 32
M.MAX_MONEY = 2000000000

local function nonempty(v)
    return type(v) == "string" and v ~= ""
end

local function copyList(input, label)
    if input == nil then return {} end
    if type(input) ~= "table" then return nil, "invalid_" .. label end
    local out, seen = {}, {}
    for i, value in ipairs(input) do
        if not nonempty(value) then return nil, "invalid_" .. label .. "_asset" end
        if seen[value] then return nil, "duplicate_asset" end
        seen[value] = true
        out[#out + 1] = value
        if #out > M.MAX_ASSETS_PER_SIDE then return nil, "too_many_assets" end
    end
    table.sort(out)
    return out
end

function M.side(input)
    input = type(input) == "table" and input or {}
    local money = tonumber(input.money) or 0
    if money ~= math.floor(money) or money < 0 or money > M.MAX_MONEY then return nil, "invalid_money" end
    local machines, why = copyList(input.machines, "machines")
    if not machines then return nil, why end
    local components
    components, why = copyList(input.components, "components")
    if not components then return nil, why end
    if #machines + #components > M.MAX_ASSETS_PER_SIDE then return nil, "too_many_assets" end
    return { money = money, machines = machines, components = components }
end

function M.offer(input)
    if type(input) ~= "table" then return nil, "offer_not_table" end
    if not nonempty(input.aDriverId) or not nonempty(input.bDriverId) then return nil, "invalid_party" end
    if input.aDriverId == input.bDriverId then return nil, "same_party" end
    local a, why = M.side(input.a)
    if not a then return nil, why end
    local b
    b, why = M.side(input.b)
    if not b then return nil, why end
    if a.money > 0 and b.money > 0 then return nil, "cash_on_both_sides" end

    local seen = {}
    for _, side in ipairs({ a, b }) do
        for _, id in ipairs(side.machines) do
            if seen[id] then return nil, "asset_on_both_sides" end
            seen[id] = "machine"
        end
        for _, id in ipairs(side.components) do
            if seen[id] then return nil, "asset_on_both_sides" end
            seen[id] = "component"
        end
    end
    local assetCount = #a.machines + #a.components + #b.machines + #b.components
    if assetCount == 0 then return nil, "asset_required" end -- money-for-money / gifts are not barter.
    local aValue = #a.machines + #a.components + (a.money > 0 and 1 or 0)
    local bValue = #b.machines + #b.components + (b.money > 0 and 1 or 0)
    if aValue == 0 or bValue == 0 then
        return nil, "both_sides_empty"
    end
    return {
        version = M.VERSION,
        aDriverId = input.aDriverId,
        bDriverId = input.bDriverId,
        a = a,
        b = b,
        assetCount = assetCount,
    }
end

function M.sideFor(offer, driverId)
    if type(offer) ~= "table" then return nil, "no_offer" end
    if driverId == offer.aDriverId then return offer.a, offer.b, "a" end
    if driverId == offer.bDriverId then return offer.b, offer.a, "b" end
    return nil, "not_party"
end

function M.summary(side)
    side = type(side) == "table" and side or {}
    return {
        money = math.max(0, math.floor(tonumber(side.money) or 0)),
        machines = #(side.machines or {}),
        components = #(side.components or {}),
    }
end

function M.canSettle(trade, now)
    if type(trade) ~= "table" then return nil, "no_trade" end
    if trade.state ~= "active" then return nil, "trade_not_active" end
    if tonumber(trade.expiresAt) and tonumber(now) >= tonumber(trade.expiresAt) then return nil, "expired" end
    if not trade.aConfirmed or not trade.bConfirmed then return nil, "both_confirmations_required" end
    if tonumber(trade.aConfirmedRevision) ~= tonumber(trade.revision)
        or tonumber(trade.bConfirmedRevision) ~= tonumber(trade.revision) then
        return nil, "stale_confirmation"
    end
    return M.offer(trade)
end

return NcmCore.define("economy.trade", function() return M end)
