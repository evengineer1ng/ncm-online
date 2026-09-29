-- ncm-core module: paddock.pricing
-- Billie's board (doc 44 §9, L224.4): prices on NPC races from a Monte Carlo of the sim, and slip rules.
--
-- Markets: WIN, PODIUM (top three) and HEAD-TO-HEAD (which of two drivers in the SAME race finishes ahead; L226).
-- Prices carry an overround (10% by default). Refusals are absolute and apply to everyone: never a position on a
-- human (there are none in an NPC race, and there never will be), never on a driver of a HUMAN-MANAGED org, and a
-- manager is never served in a series their own org races in. The Monte Carlo is accumulated incrementally
-- (`newPricer`) so the server can run it a few simulations per yield under OPEN//77's instruction quota (KB-211).
local Core = NcmCore

Core.define("paddock.pricing", function(C)
    local M = { version = "0.1.0", OVERROUND = 0.10, MIN_PRICE = 1.10, MAX_PRICE = 30.0, MAX_PROB = 0.90 }

    --- An accumulator over simulated finishing orders. `ids` are the entrants.
    function M.newPricer(ids)
        local p = { ids = ids, n = 0, win = {}, podium = {}, ahead = {} }
        for _, id in ipairs(ids) do p.win[id] = 0; p.podium[id] = 0; p.ahead[id] = {} end
        --- One simulated result: `order` = ids best first, `finished` = id -> true for classified finishers.
        function p.add(order, finished)
            p.n = p.n + 1
            local rank = {}
            for i, id in ipairs(order) do rank[id] = i end
            if order[1] and finished[order[1]] then p.win[order[1]] = p.win[order[1]] + 1 end
            for i = 1, math.min(3, #order) do
                if finished[order[i]] then p.podium[order[i]] = p.podium[order[i]] + 1 end
            end
            for _, a in ipairs(ids) do
                for _, b in ipairs(ids) do
                    if a ~= b and rank[a] and rank[b] and rank[a] < rank[b] and finished[a] then
                        p.ahead[a][b] = (p.ahead[a][b] or 0) + 1
                    end
                end
            end
        end
        --- Smoothed probabilities: { win = id->p, podium = id->p, h2h = function(a, b) -> p(a ahead of b) }.
        function p.probs()
            local n = math.max(1, p.n)
            local k = #ids
            local out = { win = {}, podium = {}, n = p.n }
            for _, id in ipairs(ids) do
                out.win[id] = (p.win[id] + 0.5) / (n + 0.5 * k)
                out.podium[id] = math.min(0.999, (p.podium[id] + 0.5) / (n + 0.5 * k / 3))
            end
            function out.h2h(a, b)
                local ab, ba = p.ahead[a][b] or 0, p.ahead[b][a] or 0
                return (ab + 0.5) / (ab + ba + 1)
            end
            return out
        end
        return p
    end

    --- A decimal price for probability `p` in a market whose probabilities sum to `book` (1 for win and h2h,
    --- 3 for podium). Returns nil when the line is too short to offer.
    function M.price(p, opts)
        opts = opts or {}
        local over = opts.overround or M.OVERROUND
        if p >= (opts.maxProb or M.MAX_PROB) then return nil end
        local price = 1 / (p * (1 + over))
        price = math.floor(price * 100 + 0.5) / 100
        if price < (opts.minPrice or M.MIN_PRICE) then return nil end
        if price > (opts.maxPrice or M.MAX_PRICE) then price = opts.maxPrice or M.MAX_PRICE end
        return price
    end

    --- The board for a race. `entrants` = { { id, orgId, humanManaged } } in grid order; `probs` from a pricer.
    --- Returns lines { market, a, b, prob, price, refused }. Refused subjects still appear (Billie says why).
    --- H2H pairs: teammates, then grid neighbours, at most `maxH2h`.
    function M.lines(entrants, probs, opts)
        opts = opts or {}
        local lines = {}
        local refusedOrg = {}
        for _, e in ipairs(entrants) do if e.humanManaged then refusedOrg[e.orgId] = true end end
        local function refused(id, orgId) return refusedOrg[orgId] == true end
        for _, e in ipairs(entrants) do
            local r = refused(e.id, e.orgId)
            lines[#lines + 1] = { market = "win", a = e.id, prob = probs.win[e.id], refused = r or nil,
                price = (not r) and M.price(probs.win[e.id], opts) or nil }
            lines[#lines + 1] = { market = "podium", a = e.id, prob = probs.podium[e.id], refused = r or nil,
                price = (not r) and M.price(probs.podium[e.id], opts) or nil }
        end
        local pairs_, seen = {}, {}
        local function addPair(x, y)
            local key = x.id < y.id and (x.id .. "|" .. y.id) or (y.id .. "|" .. x.id)
            if seen[key] then return end
            seen[key] = true
            pairs_[#pairs_ + 1] = { x, y }
        end
        for i = 1, #entrants do
            for j = i + 1, #entrants do
                if entrants[i].orgId == entrants[j].orgId then addPair(entrants[i], entrants[j]) end
            end
        end
        for i = 1, #entrants - 1 do addPair(entrants[i], entrants[i + 1]) end
        local maxH2h = opts.maxH2h or 6
        for k = 1, math.min(maxH2h, #pairs_) do
            local x, y = pairs_[k][1], pairs_[k][2]
            local r = refused(x.id, x.orgId) or refused(y.id, y.orgId)
            local p = probs.h2h(x.id, y.id)
            lines[#lines + 1] = { market = "h2h", a = x.id, b = y.id, prob = p, refused = r or nil,
                price = (not r) and M.price(p, opts) or nil }
        end
        return lines
    end

    --- Validate a slip against the line and the player's limits. `ctx`:
    ---   line { state, version, price, refused, market }, slip { stake, version }, caps { perSlip, daily, maxPayout },
    ---   stakedToday, balance, knowsBillie, managesInSeries, now, closesAt.
    --- Returns true, potential or false, reason.
    function M.validateSlip(ctx)
        local line, slip, caps = ctx.line, ctx.slip, ctx.caps or {}
        if not ctx.knowsBillie then return false, "not_introduced" end
        if not line then return false, "no_line" end
        if line.refused then return false, "refused" end
        if ctx.managesInSeries then return false, "own_series" end
        if line.state ~= "open" then return false, "closed" end
        if ctx.closesAt and ctx.now and ctx.now >= ctx.closesAt then return false, "closed" end
        if tonumber(slip.version) ~= tonumber(line.version) then return false, "price_moved" end
        local stake = tonumber(slip.stake)
        if not stake or stake ~= math.floor(stake) or stake < 1 then return false, "invalid_stake" end
        if caps.perSlip and stake > caps.perSlip then return false, "over_slip_cap" end
        if caps.daily and (ctx.stakedToday or 0) + stake > caps.daily then return false, "over_daily_cap" end
        if (ctx.balance or 0) < stake then return false, "insufficient_funds" end
        local potential = math.floor(stake * line.price)
        if caps.maxPayout and potential > caps.maxPayout then return false, "over_max_payout" end
        return true, potential
    end

    --- Settle a slip on a race result. `result` = { byId = id -> { position, state } }, `void` = true when the race
    --- was voided. Returns state ("won" | "lost" | "void"), payout (eddies returned to the player, 0 when lost).
    function M.settle(slip, result)
        if not result or result.void then return "void", slip.stake end
        local a = result.byId[slip.a]
        if not a then return "void", slip.stake end
        local won
        if slip.market == "win" then
            won = a.state == "finished" and a.position == 1
        elseif slip.market == "podium" then
            won = a.state == "finished" and a.position <= 3
        elseif slip.market == "h2h" then
            local b = result.byId[slip.b]
            if not b then return "void", slip.stake end
            if a.state ~= "finished" and b.state ~= "finished" then return "void", slip.stake end
            won = a.state == "finished" and (b.state ~= "finished" or a.position < b.position)
        else
            return "void", slip.stake
        end
        if won then return "won", math.floor(slip.stake * slip.price) end
        return "lost", 0
    end

    --- The book's implied total for a set of prices (sum of 1/price). A test holds it to 1 + overround.
    function M.implied(prices)
        local s = 0
        for _, p in ipairs(prices) do if p then s = s + 1 / p end end
        return s
    end

    return M
end)
