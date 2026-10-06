-- space.tactical + space.calendar (L322; doc 54 §O-§P): one event, three fidelities; deterministic, resumable,
-- promotable; outcomes are committed history that rebuilds the world.
local function get(T, n) return T.Core.get(n) end

local WORLD
local function world(T)
    local U = get(T, "space.universe")
    U.setWorld({ earthRadius = 5000, surfaceG = 9.81 })
    if not WORLD then
        WORLD = get(T, "space.calendar").index(get(T, "space.genesis").generate(get(T, "world.seed").root("ncm-los-santos-dev-1"):child("snowglobe")))
    end
    return WORLD
end
local function done(T) get(T, "space.universe").setWorld({}) end
local function venueIdx(w, kind, style)
    for i, v in ipairs(w.venues) do if v.kind == kind and (not style or v.style == style) then return i end end
end
local function key(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.id .. ":" .. tostring(r.state) .. ":" .. string.format("%.9f", r.raceS or -1) end
    return table.concat(out, ",")
end

return {
    a_sprint_is_deterministic_and_resumable = function(T)
        local Cal, Tac = get(T, "space.calendar"), get(T, "space.tactical")
        local ok, err = pcall(function()
            local w = world(T)
            local ev = Cal.event(w, venueIdx(w, "sprint", "vertical"), 7, { t0 = 0 })
            T.ok(#ev.entrants >= 2, "a field lines up")
            local a = Tac.run(Tac.new(ev))
            local b = Tac.run(Tac.new(ev))
            T.eq(key(Tac.result(a)), key(Tac.result(b)), "the same event runs the same race")
            local part = Tac.new(ev)
            Tac.run(part, 6.0)
            local snap = Tac.snapshot(part)
            local resumed = Tac.run(Tac.resume(ev, snap))
            T.eq(key(Tac.result(resumed)), key(Tac.result(a)), "snapshot at 6 s and resume: identical to running straight through")
            local rows = Tac.result(a)
            T.eq(rows[1].state, "finished", "somebody wins")
            T.eq(rows[1].mode, "tactical", "nobody watched: tactical, and it says so")
        end)
        done(T)
        if not ok then error(err, 0) end
    end,

    identical_machines_different_drivers_differ = function(T)
        local Cal, Tac, F = get(T, "space.calendar"), get(T, "space.tactical"), get(T, "engineering.fixtures")
        local ok, err = pcall(function()
            local w = world(T)
            local ev = Cal.event(w, venueIdx(w, "sprint", "vertical"), 3, { t0 = 0, maxEntrants = 2 })
            for _, e in ipairs(ev.entrants) do e.design = F.MACHINES.sprint_dragster end
            local rows = Tac.result(Tac.run(Tac.new(ev)))
            T.ok(rows[1].raceS and rows[2].raceS and rows[1].raceS ~= rows[2].raceS, "same dragster, two drivers, two times")
            T.ok(rows[1].reactS ~= rows[2].reactS, "starting with how they react to the lights")
        end)
        done(T)
        if not ok then error(err, 0) end
    end,

    promotion_and_demotion_keep_one_race = function(T)
        local Cal, Tac = get(T, "space.calendar"), get(T, "space.tactical")
        local ok, err = pcall(function()
            local w = world(T)
            local ev = Cal.event(w, venueIdx(w, "sprint", "vertical"), 11, { t0 = 0 })
            local race = Tac.new(ev)
            Tac.run(race, 5.5)
            local id = race.order[1]
            local st = Tac.promote(race, id)
            T.ok(st.pos and st.vel and st.rot and st.tanks, "promotion hands the host a full state")
            -- the host flies it straight up the lane for 2 s and reports what it saw
            local f = ev.venue.frame
            local p = st.pos
            for k = 1, 40 do
                Tac.step(race)
                local y = 30 * (k * 0.05)
                Tac.observe(race, id, race.t, { p[1] + f.y[1] * y, p[2] + f.y[2] * y, p[3] + f.y[3] * y }, { f.y[1] * 30, f.y[2] * 30, f.y[3] * 30 })
            end
            Tac.demote(race, id, { pos = race.entrants[id].s.dyn.pos, vel = race.entrants[id].s.dyn.vel })
            Tac.run(race)
            local rows = Tac.result(race)
            local mine
            for _, r in ipairs(rows) do if r.id == id then mine = r end end
            T.eq(mine.mode, "mixed", "part flown physically, part simulated: mixed provenance")
            T.ok(mine.physicalShare > 0 and mine.physicalShare < 1, "with the share recorded")
        end)
        done(T)
        if not ok then error(err, 0) end
    end,

    abstract_and_tactical_run_the_same_event = function(T)
        local Cal, Tac, Race, Hash, Mach = get(T, "space.calendar"), get(T, "space.tactical"), get(T, "space.racesim"), get(T, "vocabulary.hash"), get(T, "engineering.machine")
        local ok, err = pcall(function()
            local w = world(T)
            local ev = Cal.event(w, venueIdx(w, "fireball"), 2, { t0 = 0 })
            local entrants = {}
            for _, e in ipairs(ev.entrants) do entrants[#entrants + 1] = { id = e.id, orgId = e.orgId, pilot = e.person, machine = Mach.assemble(e.design) } end
            local abstract = Race.race(ev.venueInfo, entrants, Hash.stream(ev.id, "abstract"))
            T.eq(#abstract.refused, 0, "the entrants the calendar chose can all fly it")
            local ids = {}
            for _, r in ipairs(Race.result(abstract)) do ids[r.id] = r.mode end
            for _, e in ipairs(ev.entrants) do T.eq(ids[e.id], "simulated", "abstract fidelity of the same entrant " .. e.id) end
        end)
        done(T)
        if not ok then error(err, 0) end
    end,

    history_rebuilds_learning_and_engineering = function(T)
        local Cal, Tac, Seed = get(T, "space.calendar"), get(T, "space.tactical"), get(T, "world.seed")
        local ok, err = pcall(function()
            local w = world(T)
            local base = Cal.historyBase(w)
            local ev = Cal.event(w, venueIdx(w, "sprint", "vertical"), 5, { t0 = 0 })
            local rows = Tac.result(Tac.run(Tac.new(ev)))
            -- pretend one org's machine cooked, to see the engineering response
            rows[1].reason = "overheated"
            local mods = Cal.outcome(w, ev, rows, "tactical", 100)
            local h1, rep = Seed.compose(base, mods)
            T.eq(#rep.refused, 0, "every mod lands on a real path")
            T.eq(#h1.events, 1, "the event is history")
            T.eq(h1.facts.race, 1, "and Race Week evidence")
            local pid = ev.entrants[1].id
            local before = w.pilotsById[pid].domains.snowglobe.skills.piloting
            Cal.apply(w, h1)
            T.ok(w.pilotsById[pid].domains.snowglobe.skills.piloting > before, "the driver learned")
            local h2 = Seed.compose(base, mods)
            T.eq(h2.drivers["p_" .. pid].piloting, h1.drivers["p_" .. pid].piloting, "seed + history rebuild the same learning")
            local org = rows[1].orgId
            T.eq(h1.orgs["o_" .. org].radiatorBonusKw, 40, "the org that overheated answers with radiator capacity")
            Cal.apply(w, base)
        end)
        done(T)
        if not ok then error(err, 0) end
    end,

    the_calendar_cycles_discipline_venues = function(T)
        local Cal = get(T, "space.calendar")
        local ok, err = pcall(function()
            local w = world(T)
            local seen = {}
            for m = 0, 400, 20 do
                local vi = Cal.due(w, m)
                seen[w.venues[vi].kind] = true
            end
            T.truthy(seen.sprint and seen.fireball, "unseen Snowglobe racing visits both disciplines")
            T.falsy(seen.station_ring or seen.sky_ring, "rings stay on demand")
        end)
        done(T)
        if not ok then error(err, 0) end
    end,
}
