-- ncm-core module: competition.teams
-- Teams, seats and the sorting hat (L18 Driver != Seat != Entry != Team; L45 variety-first assignment).
-- The NCX pack's ten teams are data here so both hosts share them; rosters are per event.
-- Pure: hosts persist rosters and deliver offers.
local Core = NcmCore

Core.define("competition.teams", function(C)
    local M = { version = "0.0.1" }

    --- NCX pack #2 teams (L45). `livery` is the RB15 livery key: record `Vehicle.v_sport1_rb15_f1_<livery>`
    --- (ncm_rb15_liveries, M7-lite). Team ids equal the livery keys so the two never drift.
    M.NCX = {
        { teamId = "rayfield",     name = "Rayfield",      short = "RAY", colour = "#C9A227", livery = "rayfield" },
        { teamId = "herrera",      name = "Herrera",       short = "HER", colour = "#8B1E2D", livery = "herrera" },
        { teamId = "thorton",      name = "Thorton",       short = "THO", colour = "#2F6F9F", livery = "thorton" },
        { teamId = "archer",       name = "Archer",        short = "ARC", colour = "#4E6E58", livery = "archer" },
        { teamId = "mizutani",     name = "Mizutani",      short = "MIZ", colour = "#E0E0E0", livery = "mizutani" },
        { teamId = "yorinobu",     name = "Yorinobu",      short = "YOR", colour = "#111111", livery = "yorinobu" },
        { teamId = "kimiko",       name = "Kimiko",        short = "KIM", colour = "#1F3A93", livery = "kimiko" },
        { teamId = "raven",        name = "Raven",         short = "RVN", colour = "#5B2C6F", livery = "raven" },
        { teamId = "spunky_monkey", name = "Spunky Monkey", short = "SPM", colour = "#FF6F00", livery = "spunky_monkey" },
        { teamId = "quadra",       name = "Quadra",        short = "QDR", colour = "#D32F2F", livery = "quadra" },
    }
    M.SEATS_PER_TEAM = 2

    local byId = nil
    --- TweakXL record of a team's RB15 livery (nil for an unknown team).
    function M.liveryRecord(teamId)
        local t = M.byId(teamId)
        return t and ("Vehicle.v_sport1_rb15_f1_" .. t.livery) or nil
    end

    --- Race numbers per team, car 1 and car 2 (NCX pack; memorable pairs, unique across the field).
    M.NUMBERS = {
        rayfield = { 1, 11 }, herrera = { 2, 22 }, thorton = { 3, 33 }, archer = { 4, 44 }, mizutani = { 5, 55 },
        yorinobu = { 6, 66 }, kimiko = { 7, 77 }, raven = { 8, 88 }, spunky_monkey = { 9, 99 }, quadra = { 10, 20 },
    }

    --- A team's cars: { { teamId, carIndex, number, record, livery }, ... } (one per seat). Hosts persist them
    --- as `team_car` and spawn them at grid slots for organized events (M7-lite).
    function M.cars(teamId)
        local t = M.byId(teamId)
        if not t then return {} end
        local out = {}
        for i = 1, M.SEATS_PER_TEAM do
            out[i] = { teamId = t.teamId, carIndex = i, number = (M.NUMBERS[t.teamId] or {})[i] or i,
                       record = M.liveryRecord(t.teamId), livery = t.livery }
        end
        return out
    end

    --- The car a seat drives: seat n -> car n.
    function M.carForSeat(teamId, seatIndex)
        return M.cars(teamId)[tonumber(seatIndex) or 0]
    end

    function M.byId(teamId)
        if not byId then
            byId = {}
            for _, t in ipairs(M.NCX) do byId[t.teamId] = t end
        end
        return byId[teamId]
    end

    --- A fresh roster for an event: every team's seats, unoccupied. seatsPerTeam defaults to 2.
    function M.newRoster(eventId, teams, seatsPerTeam)
        teams = teams or M.NCX
        local roster = { eventId = eventId, seats = {}, capacity = 0 }
        for _, t in ipairs(teams) do
            for i = 1, (seatsPerTeam or M.SEATS_PER_TEAM) do
                roster.seats[#roster.seats + 1] = { teamId = t.teamId, seatIndex = i, driverId = nil, entryId = nil }
                roster.capacity = roster.capacity + 1
            end
        end
        return roster
    end

    local function occupancy(roster)
        local count, seatOf = {}, {}
        for _, s in ipairs(roster.seats) do
            count[s.teamId] = count[s.teamId] or 0
            if s.driverId then
                count[s.teamId] = count[s.teamId] + 1
                seatOf[s.driverId] = s
            end
        end
        return count, seatOf
    end

    function M.seatOf(roster, driverId)
        local _, seatOf = occupancy(roster)
        return seatOf[driverId]
    end

    function M.occupied(roster)
        local n = 0
        for _, s in ipairs(roster.seats) do if s.driverId then n = n + 1 end end
        return n
    end

    --- The sorting hat (L45, L48): variety first. Among teams with the fewest occupied seats, pick the
    --- one the driver's affinity favours (`opts.affinity = { teamId = score }`, from the onboarding
    --- questionnaire); without affinities, or among equal scores, pick at random (rng in [0,1)).
    --- `opts.teamId` forces a team. Then take that team's lowest free seat.
    --- Returns seat or nil, reason ("already_seated" | "roster_full" | "team_full").
    function M.assignSeat(roster, driverId, opts)
        opts = opts or {}
        local count, seatOf = occupancy(roster)
        if seatOf[driverId] then return nil, "already_seated" end
        local teamOrder = {}
        for _, s in ipairs(roster.seats) do
            if not teamOrder[s.teamId] then teamOrder[s.teamId] = true; teamOrder[#teamOrder + 1] = s.teamId end
        end
        local candidates = {}
        if opts.teamId then
            candidates = { opts.teamId }
        else
            local best = math.huge
            for _, tid in ipairs(teamOrder) do
                local c = count[tid] or 0
                if c < best then best = c; candidates = { tid } elseif c == best then candidates[#candidates + 1] = tid end
            end
        end
        if #candidates == 0 then return nil, "roster_full" end
        if type(opts.affinity) == "table" and #candidates > 1 then
            local best, keep = -math.huge, {}
            for _, tid in ipairs(candidates) do
                local a = tonumber(opts.affinity[tid]) or 0
                if a > best then best = a; keep = { tid } elseif a == best then keep[#keep + 1] = tid end
            end
            candidates = keep
        end
        local pick
        if #candidates == 1 then
            pick = candidates[1]
        else
            local r = type(opts.rng) == "function" and opts.rng() or 0
            pick = candidates[math.floor(r * #candidates) + 1] or candidates[1]
        end
        for _, s in ipairs(roster.seats) do
            if s.teamId == pick and not s.driverId then
                s.driverId = driverId
                s.entryId = opts.entryId
                return s
            end
        end
        return nil, opts.teamId and "team_full" or "roster_full"
    end

    function M.releaseSeat(roster, driverId)
        for _, s in ipairs(roster.seats) do
            if s.driverId == driverId then s.driverId = nil; s.entryId = nil; return true end
        end
        return false
    end

    --- Grid order for an organized event: team order, then seat index (v0; qualifying arrives in M4 proper).
    function M.gridOrder(roster)
        local out = {}
        for _, s in ipairs(roster.seats) do
            if s.driverId then out[#out + 1] = s end
        end
        return out
    end

    return M
end)
