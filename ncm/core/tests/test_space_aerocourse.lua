-- space.aerocourse + the `course` discipline in space.tactical (aerospace racing brief, 2026-10-07): one race from Night
-- City into Deep and home -- one field, one clock, one tower -- flown by NPCs on their machines' real physics.
local function get(T, n) return T.Core.get(n) end
local function real(T) get(T, "space.universe").setWorld({}) end

local function key(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.id .. ":" .. tostring(r.state) .. ":" .. string.format("%.6f", r.raceS or -1) end
    return table.concat(out, ",")
end

local SHORT = { turnAltM = 120000 }

return {
    the_route_goes_up_and_comes_home = function(T)
        real(T)
        local A, U = get(T, "space.aerocourse"), get(T, "space.universe")
        local r = A.route(SHORT)
        local legs = {}
        for _, g in ipairs(r.gates) do legs[#legs + 1] = g.leg end
        T.eq(table.concat(legs, ","), "ground,ascent,ascent,deep,return,reentry,landing,landing", "Pothole, up, Deep, home, Hill Abode")
        T.ok(U.altitude(r.gates[4].centre) > 100000, "the turnaround is in Deep")
        local fin = r.gates[#r.gates]
        T.ok(get(T, "space.universe").vec.dot(fin.normal, fin.centre) < 0, "the finish is crossed coming DOWN onto Hill Abode")
        T.eq(#r.grid, 12, "a twelve-car grid")
        T.ok(math.abs(U.altitude(r.grid[1].pos) - r.groundAltM) < 0.5, "standing on the road (the tangent plane rises a centimetre over 400 m)")
    end,

    a_field_races_into_deep_and_home = function(T)
        real(T)
        local A, Tac, U = get(T, "space.aerocourse"), get(T, "space.tactical"), get(T, "space.universe")
        local ev = A.event({ vehicleKey = "rayfield_caliburn", size = 4, route = SHORT })
        local race = Tac.new(ev)
        local maxAlt, legsSeen, lastPos, jump = 0, {}, {}, 0
        while not Tac.over(race) do
            Tac.step(race)
            for _, o in ipairs(Tac.standings(race)) do legsSeen[o.leg] = true end
            for id, E in pairs(race.entrants) do
                local p = E.s.dyn.pos
                maxAlt = math.max(maxAlt, U.altitude(p))
                if lastPos[id] then
                    local dx = U.vec.len(U.vec.sub(p, lastPos[id]))
                    jump = math.max(jump, dx / Tac.DT)
                end
                lastPos[id] = p
            end
        end
        local rows = Tac.result(race)
        local finished = 0
        for _, r in ipairs(rows) do if r.state == "finished" then finished = finished + 1 end end
        T.ok(finished >= 3, ("most of the field gets home (%d of 4)"):format(finished))
        T.ok(maxAlt > 115000, ("it really went to Deep (%.0f km)"):format(maxAlt / 1000))
        for _, leg in ipairs({ "ground", "ascent", "deep", "return", "reentry", "landing", "finished" }) do
            T.ok(legsSeen[leg], "the tower saw a car on the " .. leg .. " leg")
        end
        T.ok(jump < 3000, ("nobody teleports: fastest motion %.0f m/s"):format(jump))
        T.eq(rows[1].state, "finished", "a winner")
        T.ok(rows[2].gapS and rows[2].gapS > 0, "the gap is a time")
        T.eq(rows[1].mode, "tactical", "provenance: nobody watched")
    end,

    the_race_is_deterministic_and_resumable = function(T)
        real(T)
        local A, Tac = get(T, "space.aerocourse"), get(T, "space.tactical")
        local ev = A.event({ vehicleKey = "rayfield_caliburn", size = 3, route = SHORT })
        local a = Tac.run(Tac.new(ev))
        local part = Tac.run(Tac.new(ev), 200)
        local resumed = Tac.run(Tac.resume(ev, Tac.snapshot(part)))
        T.eq(key(Tac.result(resumed)), key(Tac.result(a)), "snapshot in Deep and resume: the same race")
    end,

    the_same_kit_on_different_machines_races_differently = function(T)
        real(T)
        local A, Tac = get(T, "space.aerocourse"), get(T, "space.tactical")
        local ev = A.event({ size = 2, route = SHORT, machines = { "arch_nazare", "rayfield_caliburn" } })
        local rows = Tac.result(Tac.run(Tac.new(ev)))
        local by = {}
        for _, r in ipairs(rows) do by[r.family] = r end
        T.ok(by.bike and by.supercar, "a bike and a supercar")
        T.ok(by.bike.raceS and by.supercar.raceS and by.bike.raceS < by.supercar.raceS,
            ("same FD-1: the lighter, slimmer bike is home first (%.0f s vs %.0f s)"):format(by.bike.raceS or -1, by.supercar.raceS or -1))
    end,

    core_names_no_machine = function(T)
        real(T)
        local A = get(T, "space.aerocourse")
        local ok = pcall(A.event, { size = 2, route = SHORT })
        T.falsy(ok, "no machine given, no race: core never picks a car for you")
    end,

    the_grid_wears_whatever_liveries_the_machine_has = function(T)
        real(T)
        local A, Liv = get(T, "space.aerocourse"), get(T, "data.liveries")
        -- a livery set plugged onto a vanilla record for the test (as a player's install may plug in any car's)
        local key = "rayfield_caliburn"
        local before = Liv.MODELS[key]
        Liv.MODELS[key] = { order = { "a", "b", "c", "d" }, liveries = {} }
        local ok, err = pcall(function()
            local ev = A.event({ vehicleKey = key, size = 6, route = SHORT, player = { id = "player:1", livery = "b" } })
            T.eq(ev.entrants[1].livery, "b", "the player keeps their livery")
            T.ok(ev.entrants[1].external, "and is flown by the host")
            local seq = {}
            for i = 2, #ev.entrants do seq[#seq + 1] = ev.entrants[i].livery end
            T.eq(table.concat(seq, ","), "a,c,d,a,c", "the field takes the others in order, repeating to fill the grid")
            local plain = A.event({ vehicleKey = "archer_hella", size = 2, route = SHORT })
            T.eq(plain.entrants[2].livery, nil, "a machine with no liveries races in its own paint")
        end)
        Liv.MODELS[key] = before
        if not ok then error(err, 0) end
    end,

    the_city_hears_what_happens_in_it = function(T)
        real(T)
        local A, U = get(T, "space.aerocourse"), get(T, "space.universe")
        local hill = A.cityPoint(A.node("Hill Abode"), 0)
        local deep = U.vec.scale(U.vec.unit and U.vec.unit(hill) or hill, (U.BODIES.earth.radius + 300000) / U.vec.len(hill))
        local facts = A.facts({
            { kind = "impact", ids = { "npc:oscar" }, pos = hill, band = 4, dnf = true },
            { kind = "landing", ids = { "npc:justina" }, pos = hill, band = 1 },
            { kind = "contact", ids = { "npc:a", "npc:b" }, pos = deep, band = 4, dnf = true },
        })
        local kinds = {}
        for _, f in ipairs(facts) do kinds[#kinds + 1] = f.kind .. ":" .. f.incident.ids[1] end
        T.eq(table.concat(kinds, ","), "race_crash:npc:oscar,wreck:npc:oscar",
            "a crash at Hill Abode is the city's; a scrape is not; a wreck 300 km up is a DNF, not the city's problem")
    end,
}
