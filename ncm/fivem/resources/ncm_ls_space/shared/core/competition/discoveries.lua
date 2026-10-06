-- ncm-core module: competition.discoveries
-- Discovery-source credit and the "Discoveries Inspired" standings (spec 1 §A/§B; IDEA-135..138).
--
-- WHO caused another Driver to discover a machine. The host owns the discovery rows and the database; this
-- module owns two decisions: whether an encounter credits a source at all, and how a set of discovery rows
-- becomes standings.
--
-- The anti-farm rule (IDEA-137) is NOT enforced here. It is a property of the host's primary key
-- `(driver, server, vehicleKey)`: a discovery happens once, so there is nowhere to write a second credit. This
-- module only refuses the cases the key cannot see -- no source, or crediting yourself.
local Core = NcmCore

Core.define("competition.discoveries", function()
    local M = { version = "0.1.0" }

    --- How the source Driver held the machine when it was encountered.
    --- Recorded on every credit; NOT filtered here. Whether a freely issued car should count towards the
    --- leaderboard is an open policy question (IDEA-138), and deciding it at write time would destroy the data
    --- needed to change our mind. It is therefore applied at QUERY time, by `inspired`.
    M.HOLDINGS = { owned = true, team = true, issued = true, authored = true, unknown = true }

    --- Every holding counts unless the caller says otherwise: the honest default while the policy is undecided.
    M.DEFAULT_POLICY = nil

    --- Should this encounter credit a source Driver?
    --- `facts`: { discovererId, sourceDriverId, sourceHolding, alreadyDiscovered }
    --- Returns true, or false plus the reason (reasons are distinct on purpose -- L83: never present one
    --- refusal as another, because "nobody showed you this" and "you showed it to yourself" are different facts).
    function M.credit(facts)
        if type(facts) ~= "table" then return false, "no_facts" end
        if facts.alreadyDiscovered then return false, "not_a_new_discovery" end
        local source = facts.sourceDriverId
        if type(source) ~= "string" or source == "" then return false, "no_source" end
        if source == facts.discovererId then return false, "self" end
        if facts.sourceHolding ~= nil and not M.HOLDINGS[facts.sourceHolding] then
            return false, "unknown_holding:" .. tostring(facts.sourceHolding)
        end
        return true
    end

    local function inWindow(row, fromUtc, toUtc)
        local at = tonumber(row.firstDiscoveredAt)
        if at == nil then return false end
        if fromUtc and at < fromUtc then return false end
        if toUtc and at >= toUtc then return false end
        return true
    end

    --- "Discoveries Inspired" standings from discovery rows.
    ---
    --- `rows`: { { discovererId, vehicleKey, sourceDriverId, sourceHolding, firstDiscoveredAt }, ... }
    --- `opts`: { fromUtc, toUtc, holdings = { issued = false } }
    ---
    --- `holdings` is the deferred policy made concrete: the SAME rows produce different standings under
    --- different rulings, which is the whole reason `sourceHolding` is recorded rather than filtered at write
    --- time. Omitting it counts everything.
    ---
    --- Returns a sorted array (highest first, then driver id so ties are stable and not iteration-order noise):
    ---   { { driverId, credits, driversReached, keysIntroduced }, ... }
    --- Every figure spec 1 §B asks for is derived here; none is stored, so none can drift from the events.
    function M.inspired(rows, opts)
        opts = opts or {}
        local holdings = opts.holdings
        local acc = {}
        for _, r in ipairs(rows or {}) do
            local source = r.sourceDriverId
            local holdingOk = true
            if holdings ~= nil and r.sourceHolding ~= nil then holdingOk = holdings[r.sourceHolding] == true end
            if type(source) == "string" and source ~= "" and source ~= r.discovererId
                and holdingOk and inWindow(r, opts.fromUtc, opts.toUtc) then
                local a = acc[source]
                if not a then
                    a = { driverId = source, credits = 0, drivers = {}, keys = {} }
                    acc[source] = a
                end
                a.credits = a.credits + 1
                a.drivers[r.discovererId] = true
                a.keys[r.vehicleKey] = true
            end
        end

        local out = {}
        for _, a in pairs(acc) do
            local nd, nk = 0, 0
            for _ in pairs(a.drivers) do nd = nd + 1 end
            for _ in pairs(a.keys) do nk = nk + 1 end
            out[#out + 1] = { driverId = a.driverId, credits = a.credits, driversReached = nd, keysIntroduced = nk }
        end
        table.sort(out, function(x, y)
            if x.credits ~= y.credits then return x.credits > y.credits end
            return x.driverId < y.driverId
        end)
        return out
    end

    --- One Driver's line, or nil when they have inspired nothing in this window.
    function M.standingFor(rows, driverId, opts)
        for place, row in ipairs(M.inspired(rows, opts)) do
            if row.driverId == driverId then row.place = place; return row end
        end
        return nil
    end

    return M
end)
