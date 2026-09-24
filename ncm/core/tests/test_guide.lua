-- competition.guide, session.practice, entry upgrade (Batch 2: the Race Guide, P47/P48/P52).
local function gatesFor(T)
    local Gates = T.Core.get("course.gates")
    return Gates.build({ name = "r", start = { x = 0, y = 0, z = 0, name = "s" }, finish = { x = 0, y = 1000, z = 0, name = "f" } })
end
local function at(g) return { x = g.x, y = g.y } end
local rng = function() return 0.5 end

local function street(id, startsAt, state)
    return {
        eventId = id, class = "calendar", seriesName = "Street Sprint", routeName = "Troll Pass", routeId = "root_troll",
        startsAt = startsAt, entryOpensAt = startsAt - 900, entryClosesAt = startsAt - 60, postedAt = startsAt - 7200,
        state = state or "posted", entries = {}, distanceM = 550, disciplineId = "street_sprint", formatId = "sprint", classId = "street_open",
        venue = { x = 0, y = 0, z = 0, name = "Hanford Overpass" }, finish = { name = "Stadium" },
    }
end

return {
    guide_rows_tier_counts_and_my_state = function(T)
        local G = T.Core.get("competition.guide")
        local e1 = street("street_sprint@1000", 1000)
        local e2 = street("ncx@2000", 2000); e2.class = "organized"; e2.invitation = true; e2.seatsTotal = 20
        local e3 = street("old@500", 500, "closed")
        e1.entries.a = { entryId = "x", state = "interested" }
        e1.entries.b = { entryId = "y", state = "checked_in" }
        e1.entries.c = { entryId = "z", state = "interested" }
        local rows = G.rows({ e3, e1, e2 }, "a", 100, { formLeadSec = 60, practice = { ["street_sprint@1000"] = { a = 41.7 } } })
        T.eq(#rows, 2, "closed events are not listed")
        T.eq(rows[1].n, 1); T.eq(rows[1].tier, "street"); T.eq(rows[2].tier, "sanctioned")
        T.eq(rows[1].interested, 2); T.eq(rows[1].entered, 1); T.eq(rows[1].myState, "interested")
        T.eq(rows[1].practice, "open"); T.eq(rows[1].myPracticeBest, 41.7)
        T.eq(rows[2].myState, "none"); T.eq(rows[2].invitation, true)
        T.eq(rows[1].region, "Unknown"); T.eq(rows[1].courseAdapter, "p2p"); T.eq(rows[1].startType, "standing")
        T.ok(type(rows[1].description) == "string" and #rows[1].description > 10, "guide derives a compact factual description")
        T.eq(G.rows({ e1 }, nil, 100)[1].myState, "none")
    end,
    practice_window_is_posting_until_qualifying_forms = function(T)
        local G = T.Core.get("competition.guide")
        local e = street("s@1000", 1000)
        local open, w = G.practiceOpen(e, 100, 60)
        T.eq(open, true); T.eq(w.closesAt, 940, "closes when the first session forms (T-60)")
        T.eq(select(2, G.practiceOpen(e, 940, 60)), "qualifying_forming")
        T.eq(select(2, G.practiceOpen(e, -8000, 60)), "not_posted")
        e.state = "closed"
        T.eq(select(2, G.practiceOpen(e, 100, 60)), "event_closed")
    end,
    interest_is_the_ordinary_entry_and_upgrades_at_the_venue = function(T)
        local G = T.Core.get("competition.guide")
        local E = T.Core.get("competition.entry")
        local e = street("s@1000", 1000)
        local d = G.interest({ event = e, now = 100, driverId = "a", rng = rng })
        T.eq(d.ok, true); T.eq(d.entry.state, "interested"); T.eq(d.entry.interestedAt, 100)
        e.entries.a = d.entry
        T.eq(G.interest({ event = e, now = 101, driverId = "a", existingEntry = e.entries.a, rng = rng }).reason, "already_interested")
        -- the physical entry (L48) keeps the same entry id
        local c = E.checkIn({ event = e, now = 200, driverId = "a", position = { x = 1, y = 1 }, existingEntry = e.entries.a, rng = rng })
        T.eq(c.ok, true); T.eq(c.upgraded, true); T.eq(c.entry.entryId, d.entry.entryId); T.eq(c.entry.state, "checked_in"); T.eq(c.entry.interestedAt, 100)
        e.entries.a = c.entry
        T.eq(E.checkIn({ event = e, now = 201, driverId = "a", position = { x = 1, y = 1 }, existingEntry = e.entries.a, rng = rng }).reason, "already_entered")
        T.eq(G.interest({ event = e, now = 202, driverId = "a", existingEntry = e.entries.a, rng = rng }).reason, "already_entered")
        -- A check-in that has not started IS withdrawable, and this is the case the venue panel offers the
        -- control for. The old rule refused it, so WITHDRAW answered "You're already entered." forever
        -- (owner QA, 2026-09-23). What you cannot take back is a race you have STARTED -- that is a forfeit.
        local wd = G.withdraw({ existingEntry = e.entries.a })
        T.eq(wd.ok, true, "an entered driver may withdraw before the start")
        T.eq(wd.entryId, e.entries.a.entryId, "the same row is withdrawn, so a re-entry can reuse it")
        T.eq(wd.wasEntered, true, "and the host can tell a withdrawal from leaving a soft list")
        T.eq(G.withdraw({ existingEntry = e.entries.a, inSession = true }).reason, "in_session",
             "out on track is a forfeit, not a withdrawal")
        T.eq(G.withdraw({ existingEntry = { entryId = "x", state = "racing" } }).reason, "in_session",
             "and the entry state says so even when the host does not")
        for _, st in ipairs({ "finished", "dnf", "dns", "dsq" }) do
            T.eq(G.withdraw({ existingEntry = { entryId = "x", state = st } }).reason, "already_raced",
                 st .. " is sporting history and cannot be withdrawn (L74c)")
        end
        T.eq(G.withdraw({ existingEntry = nil }).reason, "no_entry")
        T.eq(G.withdraw({ existingEntry = { entryId = "x", state = "withdrawn" } }).reason, "no_entry")
        -- withdraw then rejoin keeps the row
        local w = G.interest({ event = e, now = 300, driverId = "w", rng = rng }).entry
        local lw = G.withdraw({ existingEntry = w })
        T.eq(lw.ok, true)
        T.eq(lw.wasEntered, false, "leaving a soft list is not a withdrawal and must not report as one")
        local back = G.interest({ event = e, now = 310, driverId = "w", existingEntry = { entryId = w.entryId, state = "withdrawn" }, rng = rng })
        T.eq(back.ok, true); T.eq(back.rejoined, true); T.eq(back.entry.entryId, w.entryId)
        -- invitationals are entered by a seat offer, never by interest
        local ncx = street("ncx@3000", 3000); ncx.class = "organized"; ncx.invitation = true
        T.eq(G.interest({ event = ncx, now = 100, driverId = "a", rng = rng }).reason, "invitation_only")
        T.eq(G.interest({ event = e, now = 1000, driverId = "b", rng = rng }).reason, "event_started")
    end,
    practice_is_open_now_joinable_and_keeps_a_leaderboard = function(T)
        local P = T.Core.get("session.practice")
        local g = gatesFor(T)
        local s = P.new({ sessionId = "p", eventId = "s@1000", gates = g, closesAt = 940, openAt = 100 })
        T.eq(s.phase, "open"); T.eq(s.practice, true)
        T.eq(P.join(s, { driverId = "a", display = "A" }) ~= nil, true)
        T.eq(select(2, P.join(s, { driverId = "a", display = "A" })), "already_joined")
        P.join(s, { driverId = "b", display = "B" })
        T.eq(P.report(s, { driverId = "a", gateIndex = 1, now = 105, position = at(g[1]) }).runStarted, true)
        T.eq(P.report(s, { driverId = "a", gateIndex = 2, now = 165, position = at(g[2]) }).finished, true)
        T.eq(P.report(s, { driverId = "a", gateIndex = 1, now = 170, position = at(g[1]) }).runStarted, true, "practice runs are unlimited")
        T.eq(P.report(s, { driverId = "a", gateIndex = 2, now = 220, position = at(g[2]) }).bestSec, 50)
        P.report(s, { driverId = "b", gateIndex = 1, now = 300, position = at(g[1]) })
        P.report(s, { driverId = "b", gateIndex = 2, now = 345, position = at(g[2]) })
        local lb = P.leaderboard(s)
        T.eq(lb[1].driverId, "b"); T.eq(lb[1].bestSec, 45); T.eq(lb[2].driverId, "a"); T.eq(lb[2].runs, 2); T.eq(lb[2].gapSec, 5)
        T.eq(#P.step(s, 500), 0, "does not close before closesAt")
        local ev = P.close(s, 940, "qualifying_forming")
        T.eq(s.phase, "complete"); T.eq(ev[#ev].type, "complete"); T.eq(s.completeReason, "qualifying_forming")
        T.eq(select(2, P.join(s, { driverId = "c" })), "already_complete")
        T.eq(P.publicView(s).practice, true); T.eq(#P.publicView(s).leaderboard, 2)
    end,
    practice_closes_by_itself_at_closes_at = function(T)
        local P = T.Core.get("session.practice")
        local s = P.new({ sessionId = "p", eventId = "e", gates = gatesFor(T), closesAt = 940, openAt = 100 })
        P.join(s, { driverId = "a" })
        local ev = P.step(s, 941)
        T.eq(s.phase, "complete"); T.eq(ev[#ev].reason, "window_closed")
    end,
    tier_is_declared_by_the_championship_not_derived = function(T)
        -- L58: street and sanctioned are both first-class. It cannot come from `class`, because every cadence
        -- series materialises as "calendar" -- so before this, City Cup, GT and Hypercar all read "street".
        local G = T.Core.get("competition.guide")
        T.eq(G.tierOf({ class = "calendar" }), "street", "the class default still stands when nothing is declared")
        T.eq(G.tierOf({ class = "organized" }), "sanctioned")
        T.eq(G.tierOf({ class = "calendar", tier = "sanctioned" }), "sanctioned", "a declared tier wins")
        T.eq(G.tierOf({ class = "organized", tier = "street" }), "street", "in both directions")
    end,

    materialize_carries_the_championships_tier = function(T)
        local Cal = T.Core.get("competition.calendar")
        local G = T.Core.get("competition.guide")
        local series = {
            seriesId = "gt_test", name = "GT", rulesetId = "r_v0", tier = "sanctioned",
            cadence = { everyMinutes = 20 }, entryWindow = { opensMinutes = 15, closesMinutes = 1 },
            routes = { { rootId = "root_tip_1035_3652__to__trench_2899_2711" } },
        }
        local out = Cal.materialize(series, 1000, 3600)
        T.ok(#out > 0, "slots materialise")
        T.eq(out[1].tier, "sanctioned", "the tier reaches the event")
        T.eq(G.tierOf(out[1]), "sanctioned", "and survives tierOf, despite class = calendar")
        T.eq(out[1].class, "calendar", "which is exactly why it had to be declared")
    end,
}
