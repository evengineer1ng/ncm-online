-- L323 (doc 54 §S): the boundaries cleared in core -- contact with host-flown cars, clock sync, life support, the
-- cross-server link and the Three Cities triathlon.
local function get(T, n) return T.Core.get(n) end

local WORLD
local function world(T)
    get(T, "space.universe").setWorld({ earthRadius = 5000, surfaceG = 9.81 })
    if not WORLD then
        WORLD = get(T, "space.calendar").index(get(T, "space.genesis").generate(get(T, "world.seed").root("ncm-los-santos-dev-1"):child("snowglobe")))
    end
    return WORLD
end
local function done(T) get(T, "space.universe").setWorld({}) end
local function guarded(T, fn)
    local ok, err = pcall(fn)
    done(T)
    if not ok then error(err, 0) end
end

return {
    a_player_hitting_an_npc_moves_it_by_momentum = function(T)
        guarded(T, function()
            local Cal, Tac, F = get(T, "space.calendar"), get(T, "space.tactical"), get(T, "engineering.fixtures")
            local w = world(T)
            local vi
            for i, v in ipairs(w.venues) do if v.name == "LSIA Sky Sprint" then vi = i end end
            local player = { id = "player:1", attrs = {}, personality = {} }
            local ev = Cal.event(w, vi, 1, { t0 = 0, external = { { id = "player:1", person = player, design = F.MACHINES.sprint_dragster, external = true } } })
            local race = Tac.new(ev)
            Tac.run(race, 6.0)
            local npc = race.order[2]
            local before = race.entrants[npc].s.dyn.vel
            local v0 = { before[1], before[2], before[3] }
            local r = Tac.contactExternal(race, npc, "player:1", { v0[1] + 20, v0[2], v0[3] }, 2000)
            T.ok(r and r.vRelMs > 19.9, "the closing speed is the relative velocity")
            local after = race.entrants[npc].s.dyn.vel
            local mN = get(T, "engineering.dynamics").mass(race.entrants[npc].model, race.entrants[npc].s.dyn)
            local want = (1 + Tac.RESTITUTION) * (mN * 2000 / (mN + 2000)) * 20 / mN
            T.ok(math.abs((after[1] - v0[1]) - want) < 1e-9, "momentum exchange with both real masses")
            T.ok(race.entrants[npc].s.mood.provocation > 0, "the NPC was provoked")
            T.eq(race.log[#race.log].external, true, "an incident with the player's id")
            Tac.run(race)
            local mine
            for _, row in ipairs(Tac.result(race)) do if row.id == "player:1" then mine = row end end
            T.eq(mine.contacts, 1, "the player's row counts the contact")
        end)
    end,

    the_clock_offset_uses_the_fastest_round_trip = function(T)
        local SP = get(T, "space.sprint")
        -- true offset +3.25 s; round trips of 80, 20 and 140 ms with asymmetric delays
        local samples = {
            { clientSend = 10.00, serverT = 13.25 + 0.05, clientRecv = 10.08 },
            { clientSend = 11.00, serverT = 14.25 + 0.01, clientRecv = 11.02 },
            { clientSend = 12.00, serverT = 15.25 + 0.10, clientRecv = 12.14 },
        }
        local off, rtt = SP.clockOffset(samples)
        T.ok(math.abs(rtt - 0.02) < 1e-12, "the 20 ms round trip is the one trusted")
        T.ok(math.abs(off - 3.25) <= 0.01, ("offset within half its round trip (%.4f)"):format(off))
    end,

    breathing_needs_air_a_sealed_cabin_or_a_suit = function(T)
        local B = get(T, "life.breath")
        T.eq(B.air(1.0, {}), "outside", "sea level: breathe outside")
        T.eq(B.air(0.05, {}), nil, "thin air with nothing: nothing")
        local cab = { sealed = true, o2 = { kg = 0.01 } }
        T.eq(B.air(0.0, { cabin = cab }), "cabin", "a sealed cabin with oxygen")
        T.eq(B.air(0.0, { cabin = { sealed = false, o2 = { kg = 1 } } }), nil, "an unsealed one is no cabin")
        local st = B.newState(0.012)
        local secs = 0
        while st.status ~= "blackout" and secs < 2000 do B.step(st, { rho = 0, suit = true, exertion = 2 }, 1); secs = secs + 1 end
        T.ok(secs > 590 and secs < 640, ("working in EVA, the emergency suit lasts about 10 minutes, then %d s to blackout"):format(secs - 600))
        local naked = B.newState(0)
        local t = 0
        while naked.status ~= "blackout" do B.step(naked, { rho = 0 }, 0.5); t = t + 0.5 end
        T.ok(math.abs(t - B.VACUUM_TUC_S) < 1, "vacuum: about 15 s of useful consciousness")
        for _ = 1, 300 do B.step(naked, { rho = 0 }, 0.5) end
        T.eq(naked.status, "dead", "then death")
        local fit = get(T, "engineering.machine").assemble(get(T, "engineering.fixtures").MACHINES.ls_orbiter)
        T.truthy(fit.cabin and fit.o2Kg > 0, "the orbiter is sealed and carries oxygen")
        T.ok(B.endurance(fit.o2Kg, 2, 2) > 6 * 3600, "about 7 hours for two working hard")
    end,

    a_link_code_joins_one_driver_across_worlds = function(T)
        local L, Seed = get(T, "world.link"), get(T, "world.seed")
        local base = L.base()
        local codes = {}
        local code = L.issue(codes, "uuid-1", "night_city", "op77:42", 1000)
        T.eq(#code, 6, "a six-character code")
        local bad = { L.claim(codes, base, code, "night_city", "op77:42", 1001, 1001) }
        T.eq(bad[2], "a code must be claimed in the OTHER world", "not in the world it came from")
        code = L.issue(codes, "uuid-1", "night_city", "op77:42", 1000, "again")
        local mods, driver = L.claim(codes, base, code, "los_santos", "license:abc", 1100, 1100)
        T.eq(driver, "uuid-1", "claimed for the right driver")
        local state = Seed.compose(base, mods)
        T.eq(state.links["d_uuid-1"].night_city, "op77:42", "both identities linked")
        T.eq(state.links["d_uuid-1"].los_santos, "license:abc", "")
        T.eq(L.driverOf(state, "los_santos", "license:abc"), "uuid-1", "a FiveM player resolves to the NCM driver")
        T.truthy(state.discovered["d_uuid-1"].los_santos, "claiming in Los Santos discovers it")
        T.falsy(L.claim(codes, base, code, "los_santos", "license:abc", 1101, 1101), "single use")
        local expired = L.issue(codes, "uuid-2", "night_city", "op77:7", 0)
        T.eq(select(2, L.claim(codes, base, expired, "los_santos", "license:x", 10000, 10000)), "expired code", "codes expire")
    end,

    three_cities_is_scored_from_linked_legs_and_hidden_until_discovered = function(T)
        local L, Seed = get(T, "world.link"), get(T, "world.seed")
        local state = L.base()
        local mods = {}
        local function leg(id, domain, pos, raceS, at)
            local m = L.legMod(state, id, { domain = domain, week = 7, venue = domain .. "-v", position = pos, raceS = raceS, state = "finished" }, at)
            mods[#mods + 1] = m
            state = Seed.compose(L.base(), mods)
        end
        leg("A", "night_city", 1, 300, 1); leg("A", "los_santos", 3, 200, 2); leg("A", "snowglobe", 1, 7, 3)
        leg("B", "night_city", 2, 310, 4); leg("B", "los_santos", 1, 190, 5); leg("B", "snowglobe", 2, 8, 6)
        leg("B", "los_santos", 2, 205, 7)
        local ev = L.threeCities(7)
        local rows = L.scoreThreeCities(state, ev, 7)
        T.eq(rows[1].id, "A", "points: 25+15+25 beats 18+25+18")
        T.eq(rows[2].legs, 3, "each driver's best result per domain counts once")
        T.falsy(L.visible(state, "A", ev), "no one sees it before discovering Los Santos and Snowglobe")
        local m1 = L.discover(state, "A", "los_santos", 10)
        local all = {}
        for _, m in ipairs(mods) do all[#all + 1] = m end
        all[#all + 1] = m1
        state = Seed.compose(L.base(), all)
        all[#all + 1] = L.discover(state, "A", "snowglobe", 11)
        state = Seed.compose(L.base(), all)
        T.truthy(L.visible(state, "A", ev), "after both, the Three Cities event is visible to A")
        T.falsy(L.visible(state, "B", ev), "and still not to B")
    end,
}
