-- paddock.mixed (L250 steps 3-4): mixed NPC/human grids, the merged classification, a Paddock race as an event.
return {
    a_human_key_fits_a_paddock_person_id_and_never_looks_like_an_npc = function(T)
        local X = T.Core.get("paddock.mixed")
        local k = X.personKey("0a1b2c3d-4e5f-4061-8a7b-9c0d1e2f3a4b")
        T.eq(#k, 16); T.eq(k:sub(1, 1), "h"); T.eq(k, "h0a1b2c3d4e5f406")
        T.ok(X.isHuman(k)); T.falsy(X.isHuman("p00123"))
        T.eq(X.npcPlaces(12, 2), 10); T.eq(X.npcPlaces(1, 3), 0)
    end,

    the_grid_is_qualifying_times_then_unqualified_humans_in_entry_order = function(T)
        local X = T.Core.get("paddock.mixed")
        local npcs = { { id = "p1", qualiMs = 100000 }, { id = "p2", qualiMs = 101000 }, { id = "p3", qualiMs = 103000 } }
        local humans = { { key = "hA", qualiMs = 102000, enteredAt = 5 }, { key = "hB", enteredAt = 9 }, { key = "hC", enteredAt = 3 },
            { key = "hD", qualiMs = 101000, enteredAt = 1 } }
        local order, quali = X.gridOrder(npcs, humans)
        T.eq(table.concat(order, ","), "p1,hD,p2,hA,p3,hC,hB", "a tie goes to the human; unqualified at the back, first entered first")
        T.eq(quali.hA, 102000); T.eq(quali.hB, nil)
        local lone = X.gridOrder(npcs, { { key = "hZ", enteredAt = 1 } })
        T.eq(lone[#lone], "hZ", "a lone unqualified human starts last")
    end,

    the_classification_merges_by_time_from_the_one_green = function(T)
        local X = T.Core.get("paddock.mixed")
        local npc = {
            { id = "p1", orgId = "o1", state = "finished", finishMs = 150000, grid = 1 },
            { id = "p2", orgId = "o2", state = "finished", finishMs = 152500, grid = 2 },
            { id = "p3", orgId = "o3", state = "dnf", grid = 3, dnfReason = "crash" },
        }
        local m = X.merge(npc, { { key = "hA", state = "finished", finishMs = 151000, grid = 4 },
            { key = "hB", state = "dnf", progressFrac = 0.4, grid = 5 }, { key = "hC", state = "dns", grid = 6 } })
        local ids = {}
        for i, e in ipairs(m) do ids[i] = e.id; T.eq(e.position, i) end
        T.eq(table.concat(ids, ","), "p1,hA,p2,p3,hB,hC")
        T.eq(m[2].gapMs, 1000); T.eq(m[3].gapMs, 2500); T.eq(m[4].gapMs, nil)
        T.eq(m[1].orgId, "o1", "an NPC row keeps its fields"); T.ok(m[2].human)
        local places, n = X.humanPlaces(m)
        T.eq(places.hA, 2); T.eq(places.hC, 6); T.eq(places.p1, nil); T.eq(n, 6)
    end,

    a_paddock_race_becomes_a_calendar_event_that_closes_at_t_minus_11 = function(T)
        local X = T.Core.get("paddock.mixed")
        local route = { name = "Snake", distanceM = 3000, start = { id = "n1", x = 1, y = 2, z = 3, name = "Hill Abode" },
            finish = { id = "n2", x = 9, y = 9, z = 0, name = "Downtown" } }
        local row = { raceId = "pr-street_a-100000", seriesId = "street_a", seriesName = "Kabuki Midnight", tier = "street",
            routeId = "gen:x", startsAt = 100000, field = 12 }
        local e = X.eventFromRow(row, route, 100000 - 3600, nil, { id = "fallback" })
        T.eq(e.eventId, "paddock:pr-street_a-100000"); T.eq(e.class, "paddock"); T.eq(e.entryClosesAt, 100000 - 660)
        T.eq(e.seriesId, "paddock_street_a"); T.eq(e.economy.id, "fallback"); T.eq(e.venue.name, "Hill Abode")
        T.eq(e.practiceCloseLeadSec, 660); T.eq(e.state, "entry_open")
        local G = T.Core.get("competition.guide")
        T.ok(G.practiceOpen(e, 100000 - 700, 60), "qualifying is open at T-11:40")
        T.falsy(G.practiceOpen(e, 100000 - 600, 60), "and closed at T-10")
        local packed = X.eventFromRow(row, route, 100000 - 3600, { seriesId = "city_cup", economy = { id = "city" } })
        T.eq(packed.seriesId, "city_cup"); T.eq(packed.economy.id, "city")
        T.eq(select(2, X.eventFromRow({ raceId = "o", startsAt = 100000, oval = true }, route, 0)), "oval")
        T.eq(select(2, X.eventFromRow(row, route, 100000 - 600)), "entries_closed")
    end,

    the_field_bonus_counts_the_humans_but_the_place_is_the_whole_fields = function(T)
        local S = T.Core.get("economy.settlement")
        local econ = { id = "e", version = 1, entryFee = 50, timeTrialCompletion = 250, raceCompletion = 300, repeatWindowSec = 86400,
            fullRateCompletions = 1, repeatFloor = 50, placement = { [1] = 350, [2] = 150, [3] = 75 },
            fieldBonus = { perEntrant = 50, max = 250 }, targets = {}, tagBounties = {}, maxTagBounty = 0 }
        local r = S.resolve({ economy = econ, fieldSize = 12, fieldBonusCount = 1, result = { state = "finished", position = 2 } })
        T.falsy(r.timeTrial, "one human among eleven NPCs is a race, not a time trial")
        local byKind = {}
        for _, l in ipairs(r.lines) do byKind[l.kind] = l.amount end
        T.eq(byKind.event_placement, 150); T.eq(byKind.event_field_bonus, 50)
    end,
}
