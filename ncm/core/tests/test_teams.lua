-- competition.teams (sorting hat), entry.register, seat-ordered grids, race control (M4-lite).
local function rngFrom(seq)
    local i = 0
    return function() i = i + 1; return seq[((i - 1) % #seq) + 1] end
end

return {
    roster_has_twenty_seats_over_ten_teams = function(T)
        local Teams = T.Core.get("competition.teams")
        local r = Teams.newRoster("ev")
        T.eq(r.capacity, 20); T.eq(#r.seats, 20); T.eq(r.seats[1].teamId, "rayfield"); T.eq(r.seats[2].seatIndex, 2)
        T.eq(Teams.byId("spunky_monkey").short, "SPM"); T.eq(Teams.byId("nope"), nil)
    end,

    sorting_hat_is_variety_first_then_second_seats_then_full = function(T)
        local Teams = T.Core.get("competition.teams")
        local r = Teams.newRoster("ev")
        local rng = rngFrom({ 0 })  -- always the first candidate: deterministic team order
        local seen = {}
        for i = 1, 10 do
            local s = Teams.assignSeat(r, "d" .. i, { rng = rng })
            T.ok(s ~= nil, "seat " .. i); T.eq(s.seatIndex, 1, "first ten fill first seats")
            T.ok(not seen[s.teamId], "team " .. s.teamId .. " used twice in the first ten"); seen[s.teamId] = true
        end
        for i = 11, 20 do
            local s = Teams.assignSeat(r, "d" .. i, { rng = rng })
            T.eq(s.seatIndex, 2, "eleven to twenty take second seats")
        end
        local _, why = Teams.assignSeat(r, "d21", { rng = rng }); T.eq(why, "roster_full")
        T.eq(select(2, Teams.assignSeat(r, "d1", { rng = rng })), "already_seated")
        T.eq(Teams.occupied(r), 20)
        T.ok(Teams.releaseSeat(r, "d3")); T.eq(Teams.occupied(r), 19)
        local s = Teams.assignSeat(r, "d22", { rng = rng }); T.eq(s.teamId, "thorton", "the released seat is the only one with fewer occupants")
    end,

    sorting_hat_is_random_but_deterministic_under_a_seed = function(T)
        local Teams = T.Core.get("competition.teams")
        local ids = T.Core.get("vocabulary.ids")
        local function run(seed)
            local r = Teams.newRoster("ev")
            local rng = ids.seededRng(seed)
            local out = {}
            for i = 1, 6 do out[#out + 1] = Teams.assignSeat(r, "d" .. i, { rng = rng }).teamId end
            return table.concat(out, ",")
        end
        T.eq(run(7), run(7), "same seed, same hat")
        T.neq(run(7), run(8), "different seed, different hat")
        local r = Teams.newRoster("ev")
        T.eq(Teams.assignSeat(r, "x", { teamId = "kimiko" }).teamId, "kimiko", "an explicit team is honoured")
        Teams.assignSeat(r, "y", { teamId = "kimiko" })
        T.eq(select(2, Teams.assignSeat(r, "z", { teamId = "kimiko" })), "team_full")
    end,

    sorting_hat_honours_affinity_within_the_variety_rule = function(T)
        local Teams = T.Core.get("competition.teams")
        local r = Teams.newRoster("ev")
        local rng = rngFrom({ 0 })
        local loves = { rayfield = 0.82, herrera = 0.76, raven = 0.61 }
        T.eq(Teams.assignSeat(r, "a", { affinity = loves, rng = rng }).teamId, "rayfield", "best fit among empty teams")
        -- the next Rayfield fan lands on their second-best team while Rayfield already has a driver (variety first)
        T.eq(Teams.assignSeat(r, "b", { affinity = loves, rng = rng }).teamId, "herrera")
        T.eq(Teams.assignSeat(r, "c", { affinity = loves, rng = rng }).teamId, "raven")
        -- with every team at one driver, the second seat goes to the best fit again
        for i = 1, 7 do Teams.assignSeat(r, "filler" .. i, { rng = rng }) end
        T.eq(Teams.occupied(r), 10)
        T.eq(Teams.assignSeat(r, "d", { affinity = loves, rng = rng }).teamId, "rayfield")
        T.eq(select(2, Teams.assignSeat(r, "d")), "already_seated")
    end,

    register_is_advance_entry_without_a_venue = function(T)
        local Entry = T.Core.get("competition.entry")
        local ev = { eventId = "e", startsAt = 1000, entryOpensAt = 100, entryClosesAt = 940, venue = { x = 0, y = 0 } }
        local rng = function() return 0.5 end
        local d = Entry.register({ event = ev, now = 50, driverId = "d1", seat = { teamId = "raven", seatIndex = 2 }, rng = rng })
        T.eq(d.ok, true); T.eq(d.entry.state, "registered"); T.eq(d.entry.teamId, "raven"); T.eq(d.entry.seatIndex, 2)
        T.eq(Entry.register({ event = ev, now = 1000, driverId = "d2", rng = rng }).reason, "event_started")
        T.eq(Entry.register({ event = ev, now = 50, driverId = "d1", existingEntry = d.entry, rng = rng }).reason, "already_entered")
    end,

    organized_grid_orders_by_seat = function(T)
        local Grid = T.Core.get("session.grid")
        local G = T.Core.get("course.gates")
        local R = T.Core.get("course.routes")
        local gates = G.build(R.resolve("root_tip_1035_3652__to__trench_2899_2711"))
        local slots = Grid.assign({
            { driverId = "late", entryId = "b", registeredAt = 50, seatOrder = 3, teamId = "thorton", seatIndex = 1 },
            { driverId = "early", entryId = "a", registeredAt = 10, seatOrder = 7, teamId = "raven", seatIndex = 1 },
            { driverId = "pole", entryId = "c", registeredAt = 60, seatOrder = 1, teamId = "rayfield", seatIndex = 1 },
        }, gates[1], { by = "seat" })
        T.eq(slots[1].driverId, "pole"); T.eq(slots[2].driverId, "late"); T.eq(slots[3].driverId, "early")
        T.eq(slots[1].teamId, "rayfield")
    end,

    race_control_penalty_and_dsq_classify = function(T)
        local Race = T.Core.get("session.race")
        local G = T.Core.get("course.gates")
        local R = T.Core.get("course.routes")
        local gates = G.build(R.resolve("root_tip_1035_3652__to__trench_2899_2711"))
        local at = function(g) return { x = g.x, y = g.y } end
        local s = Race.new({ sessionId = "s", eventId = "e", startsAt = 1000, gates = gates, entrants = {
            { driverId = "a", entryId = "ea", slot = 1, teamId = "kimiko", seatIndex = 1 },
            { driverId = "b", entryId = "eb", slot = 2, teamId = "quadra", seatIndex = 1 },
            { driverId = "c", entryId = "ec", slot = 3, teamId = "raven", seatIndex = 1 },
        } })
        for _, id in ipairs({ "a", "b", "c" }) do Race.mark(s, id, true) end
        Race.step(s, 970); Race.step(s, 995); Race.step(s, 1000)
        for _, id in ipairs({ "a", "b", "c" }) do Race.report(s, { driverId = id, gateIndex = 1, now = 1001, position = at(gates[1]) }) end
        local e = Race.penalty(s, "a", 10, "corner cutting", 1050); T.eq(e[1].type, "penalty"); T.eq(s.entrants.a.penaltySec, 10)
        T.eq(select(2, Race.penalty(s, "a", -1)), "invalid_penalty")
        e = Race.disqualify(s, "c", "contact", 1060); T.eq(e[1].type, "dsq"); T.eq(s.entrants.c.state, "dsq")
        T.eq(Race.report(s, { driverId = "c", gateIndex = 2, now = 1070, position = at(gates[2]) }).reason, "not_racing")
        Race.report(s, { driverId = "a", gateIndex = 2, now = 1100, position = at(gates[2]) })
        Race.report(s, { driverId = "b", gateIndex = 2, now = 1105, position = at(gates[2]) })
        T.eq(s.entrants.a.totalSec, 110, "penalty added to the finished time")
        e = Race.step(s, 1106)
        T.eq(s.phase, "complete")
        local res = e[#e].results
        T.eq(res[1].driverId, "b", "the clean driver wins despite finishing later"); T.eq(res[2].driverId, "a"); T.eq(res[2].penaltySec, 10)
        T.eq(res[3].driverId, "c"); T.eq(res[3].state, "dsq"); T.eq(res[3].teamId, "raven")
        -- a post-finish penalty re-orders too
        local s2 = Race.new({ sessionId = "s2", eventId = "e", startsAt = 1000, gates = gates, entrants = { { driverId = "a", entryId = "x", slot = 1 }, { driverId = "b", entryId = "y", slot = 2 } } })
        Race.mark(s2, "a", true); Race.mark(s2, "b", true); Race.step(s2, 970); Race.step(s2, 995); Race.step(s2, 1000)
        Race.report(s2, { driverId = "a", gateIndex = 1, now = 1001, position = at(gates[1]) }); Race.report(s2, { driverId = "b", gateIndex = 1, now = 1001, position = at(gates[1]) })
        Race.report(s2, { driverId = "a", gateIndex = 2, now = 1100, position = at(gates[2]) }); Race.report(s2, { driverId = "b", gateIndex = 2, now = 1102, position = at(gates[2]) })
        Race.penalty(s2, "a", 5, "jump", 1103)
        T.eq(s2.entrants.a.totalSec, 105)
        T.eq(Race.classify(s2)[1].driverId, "b")
        T.eq(select(2, Race.disqualify(s2, "zz")), "unknown_entrant")
    end,

    team_ids_are_the_rb15_livery_keys = function(T)
        local Teams = T.Core.get("competition.teams")
        for _, team in ipairs(Teams.NCX) do
            T.eq(team.livery, team.teamId, "livery key drifted for " .. team.teamId)
            T.eq(Teams.liveryRecord(team.teamId), "Vehicle.v_sport1_rb15_f1_" .. team.teamId)
        end
        T.eq(Teams.liveryRecord("nope"), nil)
    end,

    team_cars_are_numbered_and_liveried = function(T)
        local Teams = T.Core.get("competition.teams")
        local seen = {}
        for _, team in ipairs(Teams.NCX) do
            local cars = Teams.cars(team.teamId)
            T.eq(#cars, Teams.SEATS_PER_TEAM)
            for i, car in ipairs(cars) do
                T.eq(car.carIndex, i); T.eq(car.record, Teams.liveryRecord(team.teamId))
                T.ok(not seen[car.number], "duplicate race number " .. tostring(car.number)); seen[car.number] = true
            end
        end
        T.eq(Teams.carForSeat("kimiko", 1).number, 7); T.eq(Teams.carForSeat("kimiko", 2).number, 77)
        T.eq(Teams.carForSeat("kimiko", 3), nil); T.eq(#Teams.cars("nope"), 0)
    end,
}
