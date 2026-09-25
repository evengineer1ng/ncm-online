-- Host-adapter regression: optional SQL values must never make a hole in OPEN//77's positional parameter
-- array. A universal market has no source_ref; the 2026-09-25 Online promotion passed nil at position 6,
-- causing `invalid_parameters` and preventing every Market payload from reaching the client.
local root = arg[1] or "."
local captured = {}

NcmCalendar = { serverId = function() return "test-world" end }
Open77 = { time = { unix = function() return 123456 end } }
MySQL = {
    insert = { await = function(query, values)
        captured.query, captured.values = query, values
        return 1
    end },
    query = { await = function() return {} end },
    single = { await = function() return nil end },
}

local Markets = {
    MARKETS = { { marketId = "base_market", universallyKnown = true } },
    discovery = function(fact) return fact end,
    byId = function(id) return id == "base_market" and { marketId = id, universallyKnown = true } or nil end,
    accessible = function(state) return state == "open" end,
}
NcmCore = { get = function(name)
    assert(name == "economy.markets", "unexpected core dependency: " .. tostring(name))
    return Markets
end }

dofile(root .. "/ncm/online/resources/ncm_league/server/market_knowledge.lua")
NcmMarketKnowledge.ensureUniversal("driver-1")

local values = assert(captured.values, "universal market knowledge was not written")
assert(captured.query:find("NULLIF%(%?, ''%)"), "source_ref must be converted back to SQL NULL")
assert(#values == 7, "OPEN//77 must receive exactly seven dense positional parameters")
for i = 1, 7 do assert(values[i] ~= nil, "nil SQL parameter at position " .. i) end
assert(values[6] == "", "absent source_ref must use the empty-string transport sentinel")
assert(values[7] == "open", "access_state shifted out of position")

print("market-knowledge: 6 assertion(s), 0 bad")
