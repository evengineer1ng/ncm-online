-- space.raceworld + space.embodiment (L327): one event, one clock; deterministic bodies.
local function RW(T) return T.Core.get("space.raceworld") end
local function VN(T) return T.Core.get("space.venues") end
local function EM(T) return T.Core.get("space.embodiment") end

local DRIVERS = {}
for i = 1, 20 do DRIVERS[i] = { id = "d" .. i, name = "Driver " .. i, pace = (i % 10) / 10, consistency = 0.3 + (i % 7) / 10, aggression = (i % 5) / 5 } end

local function firstEvent(T, id)
    local v = VN(T).get(id)
    for k = 1000, 1100 do local e = RW(T).event(v, k); if e then return e end end
end

return {
    unlit_venues_race_in_daylight_only = function(T)
        local V, R = VN(T), RW(T)
        for _, v in ipairs(V.VENUES) do
            for k = 2000, 2080 do
                local e = R.event(v, k)
                if e then T.ok(V.daylight(v, e.startUtc), v.id .. " race starts in daylight") end
            end
        end
    end,

    the_same_instant_is_the_same_race = function(T)
        local R = RW(T)
        local e = firstEvent(T, "monza")
        local f1, f2 = R.field(e, DRIVERS), R.field(e, DRIVERS)
        T.eq(#f1, R.FIELD_MAX, "a full field")
        for i = 1, #f1 do T.eq(f1[i].driver.id, f2[i].driver.id, "same grid"); T.eq(f1[i].car, f2[i].car, "same cars") end
        local t = e.startUtc + 600
        local a, b = R.state(e, f1, t), R.state(e, f2, t)
        for i = 1, #a.cars do T.eq(a.cars[i].driver.id, b.cars[i].driver.id, "same order at the same instant") end
    end,

    the_race_runs_without_anyone_watching = function(T)
        local R = RW(T)
        local e = firstEvent(T, "monza")
        local f = R.field(e, DRIVERS)
        T.eq(R.state(e, f, e.practiceUtc - 10).phase, "scheduled", "")
        T.eq(R.state(e, f, e.startUtc - 10).phase, "grid", "the grid forms before the start (L330 timetable)")
        T.eq(R.state(e, f, e.practiceUtc + 60).phase, "practice", "")
        local mid = R.state(e, f, e.startUtc + e.laps * e.baseLapS * 0.5)
        T.eq(mid.phase, "racing", "")
        T.ok(mid.leaderLap > 1 and mid.leaderLap < e.laps, "mid-race the leader is mid-distance (lap " .. mid.leaderLap .. "/" .. e.laps .. ")")
        local done = R.result(e, f, e.startUtc + e.laps * e.baseLapS * 2)
        T.ok(done and #done == #f, "and it finishes on its own")
        T.eq(done[1].provenance, "simulated", "unobserved results say so")
    end,

    arriving_late_finds_the_race_where_it_is = function(T)
        local R = RW(T)
        local e = firstEvent(T, "spa")
        local f = R.field(e, DRIVERS)
        local early = R.state(e, f, e.startUtc + 300)
        local later = R.state(e, f, e.startUtc + 1200)
        T.ok(later.leaderLap > early.leaderLap, "the race moved on while we were away")
        for _, c in ipairs(later.cars) do T.ok(c.progress >= 0 and c.progress <= 1, "a track position to place each car at") end
    end,

    a_machine_is_always_the_same_body = function(T)
        local E = EM(T)
        T.eq(E.forMachine("archer_hella").car, "ks_maserati_quattroporte", "the Hella's body")
        T.eq(E.forMachine("unlisted_car").car, E.forMachine("unlisted_car").car, "unlisted keys are stable")
        T.ok(E.forMachine("unlisted_car").why:find("pool"), "and say they are a pool pick")
    end,

    -- L330: the calendar is the Racing Week's: a posted timetable on the real clock, seeded by the run
    a_slot_is_a_posted_timetable = function(T)
        local R, v = RW(T), VN(T).get("monza")
        local e = firstEvent(T, "monza")
        local kinds = {}
        for _, t in ipairs({ e.practiceUtc + 60, e.qualiUtc + 60, e.gridUtc + 60, e.startUtc + 60, e.raceEndUtc + 60 }) do
            kinds[#kinds + 1] = R.session(v, t).kind
        end
        T.eq(table.concat(kinds, ","), "practice,qualifying,grid,race,trackday", "practice, qualifying, the grid, the race, a track day")
        local sch = R.schedule(v, e.practiceUtc + 60, nil, 4)
        T.eq(#sch, 5, "the running session and the next four")
        for i = 2, #sch do T.ok(sch[i].startUtc >= sch[i - 1].endUtc, "in order, posted ahead") end
    end,

    a_new_racing_week_posts_a_new_calendar = function(T)
        local R, v = RW(T), VN(T).get("spa")
        local diffFam, diffGrid, k = 0, 0, nil
        for kk = 1000, 1200 do
            local a, b = R.event(v, kk, "run-7-seed"), R.event(v, kk, "run-8-seed")
            if a and b then
                k = kk
                if a.family ~= b.family then diffFam = diffFam + 1 end
                local fa, fb = R.field(a, DRIVERS), R.field(b, DRIVERS)
                if fa[1].driver.id ~= fb[1].driver.id then diffGrid = diffGrid + 1 end
            end
        end
        T.ok(k ~= nil, "Spa races")
        T.ok(diffGrid > 0, "another run's seed makes other grids")
        local a1, a2 = R.event(v, k, "run-7-seed"), R.event(v, k, "run-7-seed")
        T.eq(a1.eventId, a2.eventId, "the same run is the same calendar")
        T.ok(a1.eventId ~= R.event(v, k, "run-8-seed").eventId, "and a reset rewinds it")
    end,

    an_unlit_venue_is_closed_in_the_dark = function(T)
        local R, V = RW(T), VN(T)
        local v = V.get("laguna_seca")
        local found = false
        for h = 0, 47 do
            local t = 1791300000 + h * 3600
            local s = R.session(v, t)
            if s.kind == "closed" then found = true; T.falsy(s.event, "no event behind a closed track") end
        end
        T.ok(found, "night at an unlit circuit: closed, not a convenient race")
    end,
}
