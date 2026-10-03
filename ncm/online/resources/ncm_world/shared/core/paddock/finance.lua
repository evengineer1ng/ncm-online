-- ncm-core module: paddock.finance
-- Organization money (doc 44 §4.4): wages and upkeep out, sponsors and prize money in, folds when it runs dry.
--
-- Paddock money is its own closed economy for NPC orgs: nothing here touches the player ledger. A HUMAN-managed
-- org's treasury is append-only in its own table (`paddock_treasury`, migration 050) and connects to a wallet only
-- through a deposit or a capped, taxed withdrawal (`paddock.manager`).
--
-- The numbers are first numbers, set so an average org roughly breaks even and the bottom of a tier bleeds slowly:
-- multiplied by the cadence (45 races a day), a purse that looked small per race is most of an org's income.
local Core = NcmCore

Core.define("paddock.finance", function(C)
    local M = { version = "0.1.0", FOLD_DAYS = 7, UPKEEP_PER_FACILITY = 2 }
    local Season = C.get("paddock.season")

    -- Total purse per race by tier, shared by finishing position.
    -- L298: purses an independent can live on (street: about €$200 a car on average, the winner €$528), paid for
    -- by entry fees (`economy.npc_garage.ENTRY_FEE`). Before, a street race paid €$190 in all and independents
    -- raced at a loss on their one-time seed money (audit L297, KB-316).
    M.PURSE = { street = 2400, regional = 4800, pro = 9000, premier = 24000 }
    M.SHARES = { 0.22, 0.16, 0.12, 0.10, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03, 0.025, 0.02, 0.015, 0.01, 0.0075, 0.005 }

    --- Prize money for each classified position in a race of `fieldSize`. Returns a list indexed by position.
    function M.purse(tier, fieldSize)
        local total = M.PURSE[tier] or 0
        local shares, sum = {}, 0
        for i = 1, fieldSize do shares[i] = M.SHARES[i] or 0.005; sum = sum + shares[i] end
        local out = {}
        for i = 1, fieldSize do out[i] = math.floor(total * shares[i] / sum + 0.5) end
        return out
    end

    --- One day's regular lines for an NPC org: { { kind, amount } }, amounts signed.
    function M.dayLines(world, org)
        local lines = {}
        local wages = 0
        for _, p in ipairs(C.get("paddock.world").members(world, org.id)) do
            if p.orgId == org.id and p.state == "active" and (p.wage or 0) > 0 then wages = wages + p.wage end
        end
        if wages > 0 then lines[#lines + 1] = { kind = "wages", amount = -wages } end
        local sponsor = 0
        for _, sid in ipairs(org.sponsorIds or {}) do
            local s = world.sponsors[sid]
            if s then sponsor = sponsor + (s.perDay or 0) end
        end
        if sponsor > 0 then lines[#lines + 1] = { kind = "sponsors", amount = sponsor } end
        local rank = (Season.TIERS[org.tier] and Season.TIERS[org.tier].rank) or 1
        local upkeep = math.floor((org.facility or 50) * M.UPKEEP_PER_FACILITY * rank)
        lines[#lines + 1] = { kind = "upkeep", amount = -upkeep }
        return lines
    end

    function M.sum(lines)
        local s = 0
        for _, l in ipairs(lines or {}) do s = s + (l.amount or 0) end
        return s
    end

    --- Advance the org's low-cash counter after a day. Returns true when it should fold (FOLD_DAYS in the red).
    function M.tickSolvency(org)
        if (org.cash or 0) < 0 then org.redDays = (org.redDays or 0) + 1 else org.redDays = 0 end
        local tierMin = ((C.get("paddock.world").TIER_CASH[org.tier] or { 20000 })[1]) * 0.2
        if (org.cash or 0) < tierMin then org.lowCashDays = (org.lowCashDays or 0) + 1 else org.lowCashDays = 0 end
        return (org.redDays or 0) >= M.FOLD_DAYS
    end

    return M
end)
