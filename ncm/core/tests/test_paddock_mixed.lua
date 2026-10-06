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

    a_paddock_race_becomes_a_calendar_event_that_closes_at_t_minus_1 = function(T)
        -- entries and qualifying close at T-1 with the freeze (L269; owner 2026-10-02: late entry until T-1)
        local X = T.Core.get("paddock.mixed")
        local route = { name = "Snake", distanceM = 3000, start = { id = "n1", x = 1, y = 2, z = 3, name = "Hill Abode" },
            finish = { id = "n2", x = 9, y = 9, z = 0, name = "Downtown" } }
        local row = { raceId = "pr-street_a-100000", seriesId = "street_a", seriesName = "Kabuki Midnight", tier = "street",
            routeId = "gen:x", startsAt = 100000, field = 12 }
        local e = X.eventFromRow(row, route, 100000 - 3600, nil, { id = "fallback" })
        T.eq(e.eventId, "paddock:pr-street_a-100000"); T.eq(e.class, "paddock"); T.eq(e.entryClosesAt, 100000 - 60)
        T.eq(e.seriesId, "paddock_street_a"); T.eq(e.economy.id, "fallback"); T.eq(e.venue.name, "Hill Abode")
        T.eq(e.practiceCloseLeadSec, 60); T.eq(e.state, "entry_open")
        local G = T.Core.get("competition.guide")
        T.ok(G.practiceOpen(e, 100000 - 600, 60), "qualifying is still open at T-10")
        T.falsy(G.practiceOpen(e, 100000 - 30, 60), "and closed inside T-1")
        local packed = X.eventFromRow(row, route, 100000 - 3600, { seriesId = "city_cup", economy = { id = "city" } })
        T.eq(packed.seriesId, "city_cup"); T.eq(packed.economy.id, "city")
        local oval = X.eventFromRow({ raceId = "o", startsAt = 100000, oval = true }, route, 0)
        T.ok(oval and oval.disciplineId == "oval", "an oval row is adopted as an oval event (L261)")
        T.eq(oval.startType, "standing", "a mixed oval starts standing beside its NPCs, not rolling (L296)")
        T.eq(e.startType, "standing")
        T.ok(X.eventFromRow(row, route, 100000 - 600), "a late entrant can still find it at T-10")
        T.eq(select(2, X.eventFromRow(row, route, 100000 - 30)), "entries_closed")
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

    the_ceremony_shows_the_road_then_the_penalties = function(T)
        local X = T.Core.get("paddock.mixed")
        -- the human crossed first by 3 s but carries 10 s; an NPC carries 2 s
        local npc = { { id = "p1", state = "finished", finishMs = 105000, rawFinishMs = 103000, penaltyMs = 2000 },
                      { id = "p2", state = "finished", finishMs = 108000, rawFinishMs = 108000, penaltyMs = 0 } }
        local humans = { { key = "h0123456789abcde", state = "finished", finishMs = 110000, rawFinishMs = 100000, penaltyMs = 10000 } }
        local merged = X.merge(npc, humans)
        local rows = X.ceremony(merged)
        local by = {}
        for _, r in ipairs(rows) do by[r.id] = r end
        T.eq(by.h0123456789abcde.rawPos, 1, "first on the road"); T.eq(by.h0123456789abcde.pos, 3, "third with penalties")
        T.eq(by.h0123456789abcde.moved, -2, "down two")
        T.eq(by.p1.rawPos, 2); T.eq(by.p1.pos, 1); T.eq(by.p1.moved, 1, "up one")
        T.eq(by.p2.moved, 1)
    end,

    a_simulated_race_flags_whoever_is_not_home = function(T)
        local M = T.Core.get("paddock.mixed")
        -- 2,500 m: the window is 30 s
        local e = {
            { id = "a", state = "finished", finishMs = 100000, position = 1 },
            { id = "b", state = "finished", finishMs = 125000, position = 2 },
            { id = "c", state = "finished", finishMs = 131000, position = 3 },
            { id = "d", state = "finished", finishMs = 160000, position = 4 },
            { id = "x", state = "dnf", dnfReason = "crash", position = 5 },
        }
        T.eq(M.flagEntrants(e, 2500), 2)
        T.eq(e[1].id, "a"); T.eq(e[2].id, "b"); T.eq(e[2].state, "finished")
        T.eq(e[3].id, "c"); T.eq(e[3].state, "dnf"); T.eq(e[3].dnfReason, "flagged"); T.eq(e[3].finishMs, nil)
        T.eq(e[4].id, "d"); T.eq(e[4].position, 4)
        T.eq(e[5].id, "x"); T.eq(e[5].position, 5, "retirements stay behind the flagged")
        local none = { { id = "a", state = "finished", finishMs = 1000, position = 1 } }
        T.eq(M.flagEntrants(none, 2500), 0)
        T.eq(M.flagEntrants({ { id = "x", state = "dnf", position = 1 } }, 2500), 0, "no leader, no flag")
    end,
}
