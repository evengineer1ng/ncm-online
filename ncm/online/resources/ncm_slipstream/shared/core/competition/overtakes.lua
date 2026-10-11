-- ncm-core module: competition.overtakes
-- Who passed whom, derived from gate crossings the session already holds (L173).
--
-- NCM Online had no overtake count. Single player did, from a telemetry stream that does not exist here -- but it
-- turns out none is needed: `session.race` already stores `crossings[gateIndex] = now` for every entrant, so the
-- running order at a gate is that gate's crossing times sorted ascending, and a pass is a pair whose relative
-- rank inverted between two consecutive gates. This module is that derivation and nothing else. It is pure: the
-- host hands in crossings (and, optionally, contact incidents) and gets back counts and events.
--
-- Deliberately NOT a Race Tag. `gained_positions` and `came_through` already answer "where did you start and
-- where did you finish"; this answers "how many cars did you actually go past", which is a different fact and
-- the one a character can be impressed by.
local Core = NcmCore

Core.define("competition.overtakes", function()
    local M = { version = "0.1.0" }

    --- Default window, in seconds, around a pass within which a contact between the same pair makes the pass
    --- CONTESTED rather than clean. It is deliberately generous: a pass that follows a hit is the interesting
    --- case, and calling a clean pass contested is a smaller error than the reverse.
    M.CONTACT_WINDOW_SEC = 6.0

    local function numberOrNil(v)
        local n = tonumber(v)
        if n ~= nil and n == n then return n end   -- rejects NaN
        return nil
    end

    --- The running order at one gate: driverIds that crossed it, earliest first.
    --- Drivers who never crossed are absent, not placed last -- "behind" and "not there" are different facts.
    --- Ties break on driverId so the order is deterministic for a given set of crossings.
    function M.orderAt(entrants, gateIndex)
        local rows = {}
        for driverId, r in pairs(type(entrants) == "table" and entrants or {}) do
            local at = numberOrNil(type(r) == "table" and r.crossings and r.crossings[gateIndex])
            if at then rows[#rows + 1] = { driverId = driverId, at = at } end
        end
        table.sort(rows, function(a, b)
            if a.at ~= b.at then return a.at < b.at end
            return tostring(a.driverId) < tostring(b.driverId)
        end)
        local out = {}
        for i, row in ipairs(rows) do out[i] = row.driverId end
        return out
    end

    local function rankMap(order)
        local m = {}
        for i, id in ipairs(order) do m[id] = i end
        return m
    end

    --- Was there contact between this pair near this time?
    --- `contacts` is an array of { a, b, at } -- symmetric, order of a/b irrelevant.
    local function contested(contacts, x, y, at, windowSec)
        for _, c in ipairs(contacts or {}) do
            local ca, cb = tostring(c.a or ""), tostring(c.b or "")
            local pairMatch = (ca == x and cb == y) or (ca == y and cb == x)
            if pairMatch then
                local t = numberOrNil(c.at)
                if t and math.abs(t - at) <= windowSec then return true end
            end
        end
        return false
    end

    --- Analyse a whole race.
    --- facts = {
    ---   entrants  = driverId -> { crossings = { [gateIndex] = unixSeconds }, ... }   (required)
    ---   gateCount = number of gates (required; segments are 1->2 .. (n-1)->n)
    ---   contacts  = { { a, b, at }, ... }      optional; marks passes as contested
    ---   fromGate  = first gate to count from (default 1)
    ---   contactWindowSec = override M.CONTACT_WINDOW_SEC
    --- }
    --- Returns { drivers = driverId -> { passes, passedBy, clean, contested, net },
    ---           events = { { atGate, driverId, overtookId, at, contested }, ... },
    ---           segments = n }
    ---
    --- A pass is counted only where BOTH drivers crossed BOTH gates of the segment: a driver who retires has not
    --- been "passed" by everyone still running, and counting that would make the biggest numbers belong to the
    --- luckiest rather than the fastest.
    function M.analyse(facts)
        if type(facts) ~= "table" then return nil, "facts_not_table" end
        local entrants = facts.entrants
        if type(entrants) ~= "table" then return nil, "entrants_required" end
        local gateCount = math.floor(tonumber(facts.gateCount) or 0)
        if gateCount < 2 then return nil, "gate_count_required" end
        local fromGate = math.max(1, math.floor(tonumber(facts.fromGate) or 1))
        local window = tonumber(facts.contactWindowSec) or M.CONTACT_WINDOW_SEC

        local drivers, events = {}, {}
        for driverId in pairs(entrants) do
            drivers[driverId] = { passes = 0, passedBy = 0, clean = 0, contested = 0, net = 0 }
        end

        local prevOrder = M.orderAt(entrants, fromGate)
        local prevRank = rankMap(prevOrder)

        for gate = fromGate + 1, gateCount do
            local order = M.orderAt(entrants, gate)
            local rank = rankMap(order)
            for i = 1, #order do
                local mover = order[i]
                for j = i + 1, #order do
                    local passed = order[j]
                    -- both must have been in the previous order too, and the mover must have been BEHIND
                    local pm, pp = prevRank[mover], prevRank[passed]
                    if pm and pp and pm > pp then
                        local at = numberOrNil(entrants[mover].crossings[gate]) or 0
                        local isContested = contested(facts.contacts, mover, passed, at, window)
                        local dm, dp = drivers[mover], drivers[passed]
                        dm.passes = dm.passes + 1
                        if isContested then dm.contested = dm.contested + 1 else dm.clean = dm.clean + 1 end
                        dp.passedBy = dp.passedBy + 1
                        events[#events + 1] = {
                            atGate = gate, driverId = mover, overtookId = passed, at = at, contested = isContested,
                        }
                    end
                end
            end
            prevOrder, prevRank = order, rank
        end

        for _, d in pairs(drivers) do d.net = d.passes - d.passedBy end
        table.sort(events, function(a, b)
            if a.at ~= b.at then return a.at < b.at end
            if a.driverId ~= b.driverId then return tostring(a.driverId) < tostring(b.driverId) end
            return tostring(a.overtookId) < tostring(b.overtookId)
        end)
        return { drivers = drivers, events = events, segments = math.max(0, gateCount - fromGate) }
    end

    --- Convenience: one driver's line from a `session.race` state, for hosts that have the session in hand.
    function M.forSession(s, driverId, contacts)
        if type(s) ~= "table" or type(s.entrants) ~= "table" or type(s.gates) ~= "table" then
            return nil, "session_required"
        end
        local out, why = M.analyse({ entrants = s.entrants, gateCount = #s.gates, contacts = contacts })
        if not out then return nil, why end
        if driverId == nil then return out end
        return out.drivers[driverId] or { passes = 0, passedBy = 0, clean = 0, contested = 0, net = 0 }
    end

    return M
end)
