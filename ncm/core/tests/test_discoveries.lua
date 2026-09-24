-- The point of these tests is not that the arithmetic adds up. It is to prove that the facts migration 014
-- records are SUFFICIENT to answer every question spec 1 §B asks -- before those columns ship and become
-- impossible to add retroactively.
local function D(discoverer, key, source, holding, at)
    return { discovererId = discoverer, vehicleKey = key, sourceDriverId = source,
             sourceHolding = holding, firstDiscoveredAt = at }
end

return {
    ["credit is refused for distinct, nameable reasons"] = function(T)
        local M = T.Core.get("competition.discoveries")
        T.eq(M.credit({ discovererId = "b", sourceDriverId = "a", sourceHolding = "owned" }), true)

        -- the anti-farm rule: no new discovery, no credit, however many times you circle someone
        local ok, why = M.credit({ discovererId = "b", sourceDriverId = "a", alreadyDiscovered = true })
        T.eq(ok, false); T.eq(why, "not_a_new_discovery")

        -- you cannot inspire yourself by parking next to your own car
        ok, why = M.credit({ discovererId = "a", sourceDriverId = "a" })
        T.eq(ok, false); T.eq(why, "self")

        -- a showroom or an unattributed encounter is a discovery with no source, not a credit to nobody
        ok, why = M.credit({ discovererId = "b" })
        T.eq(ok, false); T.eq(why, "no_source")

        ok, why = M.credit({ discovererId = "b", sourceDriverId = "a", sourceHolding = "borrowed" })
        T.eq(ok, false); T.eq(why:sub(1, 16), "unknown_holding:")
    end,

    ["standings answer all four of spec 1 section B's questions"] = function(T)
        local M = T.Core.get("competition.discoveries")
        local rows = {
            D("b", "quadra_type66", "a", "owned", 100),
            D("c", "quadra_type66", "a", "owned", 110),   -- same car, a second driver reached
            D("c", "ncx_rb15",      "a", "team",  120),   -- same driver, a second key introduced
            D("b", "mizutani_shion","z", "owned", 130),
        }
        local st = M.inspired(rows)
        T.eq(#st, 2)
        T.eq(st[1].driverId, "a")
        T.eq(st[1].credits, 3)           -- career / all-time
        T.eq(st[1].driversReached, 2)    -- unique Drivers reached: b and c
        T.eq(st[1].keysIntroduced, 2)    -- unique vehicleKeys introduced
        T.eq(st[2].driverId, "z")
        T.eq(M.standingFor(rows, "a").place, 1)
        T.eq(M.standingFor(rows, "nobody"), nil)
    end,

    ["a season is a window over the same rows, not a second stored total"] = function(T)
        local M = T.Core.get("competition.discoveries")
        local rows = {
            D("b", "k1", "a", "owned", 100),
            D("c", "k2", "a", "owned", 500),
            D("d", "k3", "z", "owned", 500),
        }
        T.eq(M.inspired(rows)[1].credits, 2)                                  -- all-time: a leads
        local season = M.inspired(rows, { fromUtc = 400, toUtc = 600 })       -- the season: a and z are level
        T.eq(#season, 2)
        T.eq(season[1].credits, 1)
        T.eq(season[2].credits, 1)
        T.eq(season[1].driverId, "a")   -- ties break on id, so standings are stable rather than hash order
        T.eq(#M.inspired(rows, { fromUtc = 600 }), 0)
    end,

    -- This is the test that justifies the extra column. If holding were filtered at write time, these two
    -- calls could not both exist: the rows for the losing policy would never have been recorded (IDEA-138).
    ["the same rows produce different standings under different holding policies"] = function(T)
        local M = T.Core.get("competition.discoveries")
        local rows = {
            D("b", "k1", "a", "issued", 100),   -- a showed off a freely provisioned car
            D("c", "k2", "a", "issued", 110),
            D("d", "k3", "z", "owned",  120),   -- z showed a car they actually own
        }
        T.eq(M.inspired(rows)[1].driverId, "a")   -- count everything: a leads 2-1

        -- rule provisioned cars out later, without having lost anything: z leads 1-0
        local owned = M.inspired(rows, { holdings = { owned = true, team = true } })
        T.eq(#owned, 1)
        T.eq(owned[1].driverId, "z")
        T.eq(owned[1].credits, 1)
    end,

    ["self-credit and sourceless rows never reach the standings"] = function(T)
        local M = T.Core.get("competition.discoveries")
        local rows = {
            D("a", "k1", "a", "owned", 100),    -- self
            D("b", "k2", nil, nil,     110),    -- a showroom / unattributed discovery
            D("b", "k3", "",  "owned", 120),    -- empty is not a driver id
            D("b", "k4", "a", "owned", 130),    -- the only real credit
        }
        local st = M.inspired(rows)
        T.eq(#st, 1)
        T.eq(st[1].driverId, "a")
        T.eq(st[1].credits, 1)
    end,

    ["no rows is an empty table, never nil"] = function(T)
        local M = T.Core.get("competition.discoveries")
        T.eq(#M.inspired({}), 0)
        T.eq(#M.inspired(nil), 0)
    end,
}
