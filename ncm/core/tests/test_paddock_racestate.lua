-- paddock.racestate: the continuous race -- where every car is at every moment, and how a physical stretch writes back.
local function field(T, n, over)
    local out = {}
    for i = 1, n do
        local a = {}
        for _, k in ipairs(T.Core.get("paddock.attributes").SKILLS) do a[k] = 50 end
        for _, k in ipairs(T.Core.get("paddock.attributes").TRAITS) do a[k] = 50 end
        if over and over[i] then for k, v in pairs(over[i]) do a[k] = v end end
        out[i] = { id = "d" .. i, orgId = "o" .. i, attrs = a, carPerf = 50, form = 0 }
    end
    return out
end
local DRY = { roadWetness = 0, light = "day", family = "dry" }

-- a straight 4.8 km line east with a bend, and a real sim run over it
local function race(T, seedKey)
    local Sim = T.Core.get("paddock.sim")
    local H = T.Core.get("vocabulary.hash")
    local pts = {}
    for i = 0, 30 do pts[#pts + 1] = { x = i * 100, y = 0, z = 10 } end
    for i = 1, 18 do pts[#pts + 1] = { x = 3000, y = i * 100, z = 10 } end
    local path = { points = pts, lengthM = 4800 }
    local r = Sim.simulate(field(T, 10, { { pace = 80 }, { pace = 70 }, {}, {}, {}, {}, {}, {}, {}, { pace = 30 } }),
        { distanceM = 4800 }, DRY, H.stream("racestate", seedKey or 1), { baseSec = 160 })
    local M = T.Core.get("paddock.racestate")
    return M, M.new(path, r.entrants, r.segments), r, path
end

return {
    with_no_physical_stretch_the_model_is_the_sim = function(T)
        local M, model, r = race(T)
        local res = M.result(model)
        T.eq(#res, #r.entrants)
        for i, e in ipairs(r.entrants) do
            T.eq(res[i].id, e.id, "same order as the sim at " .. i)
            T.eq(res[i].state, e.state)
            if e.state == "finished" then T.ok(math.abs(res[i].finishMs - e.finishMs) <= 1, "same finish time for " .. e.id) end
        end
        T.eq(res[1].physicalShare, 0)
    end,

    cars_move_along_the_line_and_finish_when_the_sim_says = function(T)
        local M, model, r = race(T)
        local e = r.entrants[1]
        local prev = -1
        for t = 0, e.finishMs, 5000 do
            local d = M.distanceAt(model, e.id, t)
            T.ok(d >= prev, "never backwards"); prev = d
        end
        T.ok(math.abs(M.distanceAt(model, e.id, e.finishMs) - 4800) < 1, "at the line at its finish time")
        local mid = M.carAt(model, e.id, e.finishMs / 2)
        T.eq(mid.state, "racing")
        T.ok(mid.speed > 5, "moving mid-race (" .. mid.speed .. " m/s)")
        T.eq(M.carAt(model, e.id, e.finishMs + 1000).state, "finished")
        -- on the bend the car is on the second leg, facing +Y (yaw 0)
        local p = M.pointAt(model, 3900)
        T.ok(math.abs(p.x - 3000) < 0.01 and math.abs(p.y - 900) < 0.01, "3.9 km is 900 m up the second leg")
        T.ok(math.abs(p.yaw - 0) < 0.01, "facing along the line")
        T.ok(math.abs(M.project(model, { x = 1234, y = 7 }) - 1234) < 0.5, "a world position projects back onto the line")
    end,

    standings_lead_with_the_leader_and_gaps_are_time = function(T)
        local M, model, r = race(T)
        local t = math.floor(r.entrants[1].finishMs * 0.6)
        local rows = M.standings(model, t)
        T.eq(rows[1].gapMs, 0)
        for i = 2, #rows do
            if rows[i].state == "racing" then T.ok(rows[i].d <= rows[i - 1].d + 0.01, "ordered by distance"); T.ok((rows[i].gapMs or 0) >= 0) end
        end
        local near = M.near(model, t, M.carAt(model, rows[1].id, t), 1)
        local found = false
        for _, id in ipairs(near) do if id == rows[1].id then found = true end end
        T.ok(found, "a car is near its own position")
    end,

    a_physical_stretch_writes_back_and_keeps_its_consequences = function(T)
        local M, model, r = race(T)
        local winner, second = r.entrants[1], r.entrants[2]
        local t = math.floor(winner.finishMs * 0.5)
        local dReal = M.distanceAt(model, winner.id, t) - 400        -- it lost 400 m in a crash we watched
        M.anchor(model, winner.id, t, dReal)
        M.markPhysical(model, winner.id, 1000, dReal, 20000, t)
        local fin = M.finishAt(model, winner.id)
        T.ok(fin > winner.finishMs + 5000, "the lost ground is still lost at the flag")
        T.ok(math.abs(M.distanceAt(model, winner.id, t) - dReal) < 0.5, "it continues from where it really was")
        local res = M.result(model)
        T.neq(res[1].id, winner.id, "the sim winner no longer wins")
        local share
        for _, e in ipairs(res) do if e.id == winner.id then share = e.physicalShare end end
        T.ok(share > 0.2 and share < 0.6, "its physical share is recorded (" .. share .. ")")
        -- a car physically stopped for good is out, not finished
        M.anchor(model, second.id, t, M.distanceAt(model, second.id, t), true)
        T.eq(M.finishAt(model, second.id), nil)
        local out
        for _, e in ipairs(M.result(model)) do if e.id == second.id then out = e end end
        T.eq(out.state, "dnf"); T.eq(out.dnfReason, "stopped")
    end,

    a_car_can_gain_ground_physically_too = function(T)
        local M, model, r = race(T)
        local last
        for _, e in ipairs(r.entrants) do if e.state == "finished" then last = e end end
        local t = math.floor(last.finishMs * 0.5)
        M.anchor(model, last.id, t, M.distanceAt(model, last.id, t) + 600)
        T.ok(M.finishAt(model, last.id) < last.finishMs - 5000, "a car that drove faster than its sim keeps the gain")
    end,

    overlapping_physical_stretches_count_once = function(T)
        local M, model, r = race(T)
        local id = r.entrants[3].id
        M.markPhysical(model, id, 0, 1200, 0, 1)
        M.markPhysical(model, id, 1000, 2400, 1, 2)
        T.ok(math.abs(M.physicalShare(model, id) - 0.5) < 0.001, "0-2400 of 4800 is half")
    end,
}
