local function series()
    return {
        seriesId = "street_sprint", name = "Street Sprint", rulesetId = "street_sprint_v0",
        cadence = { everyMinutes = 20, offsetMinutes = 0 },
        routes = {
            { rootId = "root_tip_1035_3652__to__trench_2899_2711", label = "Tip-to-Trench" },
            "root_hill_abode_505_1229__to__downtown_2362_117",
        },
        entryWindow = { opensMinutes = 15, closesMinutes = 1 },
    }
end

return {
    routes_resolve = function(T)
        local R = T.Core.get("course.routes")
        local r = R.resolve("root_tip_1035_3652__to__trench_2899_2711", "Tip-to-Trench")
        T.eq(r.name, "Tip-to-Trench"); T.eq(r.start.id, "tip_-1035_3652"); T.eq(r.finish.id, "trench_-2899_-2711")
        T.ok(r.distanceM > 6000 and r.distanceM < 7000, "Tip to Trench is ~6.6 km planar: " .. r.distanceM)
        T.match(r.description, "6%.6 km cross%-city run")
        T.eq(R.resolve("root_vista_del_drag_900_751__to__japantown_crossway_373_0").recommendedMode, "drag")
        T.eq(R.resolve("root_deep_dive_2350_2446__to__trench_2899_2711").recommendedMode, "drag")
        local _, why = R.resolve("nope"); T.eq(why, "unknown_root")
    end,

    materialize_is_deterministic_and_on_grid = function(T)
        local Cal = T.Core.get("competition.calendar")
        local now = 1800000000 + 7 * 60 -- 7 minutes past a 20-minute boundary
        local a = Cal.materialize(series(), now, 2 * 3600)
        local b = Cal.materialize(series(), now, 2 * 3600)
        T.eq(#a, 6, "six 20-minute slots in two hours"); T.eq(a[1].eventId, b[1].eventId)
        T.eq(a[1].startsAt % 1200, 0, "on the cadence grid"); T.ok(a[1].startsAt > now)
        T.eq(a[1].entryOpensAt, a[1].startsAt - 900); T.eq(a[1].entryClosesAt, a[1].startsAt - 60)
        T.neq(a[1].routeId, a[2].routeId, "routes rotate"); T.ok(a[1].venue.nodeId ~= nil)
        T.ok(type(a[1].description) == "string" and #a[1].description > 0, "route description reaches event")
        T.match(a[1].eventId, "^street_sprint@%d+$")
        T.eq(a[1].seasonId, "2027-S1", "posted occurrence carries the global competitive period")
    end,

    validate_series = function(T)
        local Cal = T.Core.get("competition.calendar")
        local s = series(); s.routes = { "root_missing" }
        local ok, why = Cal.validateSeries(s); T.eq(ok, false); T.match(why, "^unknown_route")
        s = series(); s.entryWindow = { opensMinutes = 1, closesMinutes = 5 }
        ok, why = Cal.validateSeries(s); T.eq(why, "invalid_entry_window")
    end,

    check_in_rules = function(T)
        local Cal = T.Core.get("competition.calendar")
        local E = T.Core.get("competition.entry")
        local ids = T.Core.get("vocabulary.ids")
        local e = Cal.materialize(series(), 1800000000, 3600)[1]
        local at = { x = e.venue.x + 5, y = e.venue.y - 5, z = e.venue.z }
        local rng = ids.seededRng(1)
        T.eq(E.checkIn({ event = e, now = e.entryOpensAt - 10, driverId = "d", position = at, rng = rng }).reason, "window_not_open")
        T.eq(E.checkIn({ event = e, now = e.entryClosesAt + 1, driverId = "d", position = at, rng = rng }).reason, "window_closed")
        T.eq(E.checkIn({ event = e, now = e.entryOpensAt + 60, driverId = "d", position = { x = e.venue.x + 100, y = e.venue.y, z = 0 }, rng = rng }).reason, "not_at_venue")
        T.eq(E.checkIn({ event = e, now = e.entryOpensAt + 60, driverId = "d", position = at, existingEntry = {}, rng = rng }).reason, "already_entered")
        local d = E.checkIn({ event = e, now = e.entryOpensAt + 60, driverId = "d", position = at, rng = rng })
        T.eq(d.ok, true); T.eq(d.entry.state, "checked_in"); T.eq(d.entry.fee, 0); T.ok(ids.isUuid(d.entry.entryId))
    end,

    one_entry_at_a_time_and_the_ring_is_the_rule = function(T)
        local Cal = T.Core.get("competition.calendar")
        local E = T.Core.get("competition.entry")
        local ids = T.Core.get("vocabulary.ids")
        local e = Cal.materialize(series(), 1800000000, 3600)[1]
        local rng = ids.seededRng(2)
        local now = e.entryOpensAt + 60
        -- The drawn ring is the rule (owner, 2026-09-28): the old 30 m allowance around a 6 m ring is gone.
        local justOutside = { x = e.venue.x + E.RING_RADIUS_M + E.RING_TOLERANCE_M + 1, y = e.venue.y, z = e.venue.z }
        T.eq(E.checkIn({ event = e, now = now, driverId = "d", position = justOutside, rng = rng }).reason, "not_at_venue")
        local inside = { x = e.venue.x + E.RING_RADIUS_M, y = e.venue.y, z = e.venue.z }
        T.eq(E.checkIn({ event = e, now = now, driverId = "d", position = inside, rng = rng }).ok, true)
        -- An entry held elsewhere refuses; a bookmark does not count as one.
        local other = { eventId = "other", state = "entry_open", entries = { d = { state = "checked_in" } } }
        local held = E.heldEntry({ other, e }, "d", e.eventId)
        T.eq(held and held.eventId, "other")
        T.eq(E.checkIn({ event = e, now = now, driverId = "d", position = inside, heldElsewhere = held, rng = rng }).reason, "entered_elsewhere")
        other.entries.d.state = "interested"
        T.eq(E.heldEntry({ other, e }, "d", e.eventId), nil, "interest is a bookmark, not an entry")
        other.entries.d.state = "registered"
        T.eq(E.heldEntry({ other, e }, "d", e.eventId).eventId, "other", "a team seat is an entry")
        T.eq(E.heldEntry({ other, e }, "d", e.eventId, function() return false end), nil,
            "an entry on an event that is over never holds the driver")
        T.eq(E.register({ event = e, now = now, driverId = "d", heldElsewhere = other, rng = rng }).reason, "entered_elsewhere")
    end,

    pings_due = function(T)
        local Cal = T.Core.get("competition.calendar")
        local E = T.Core.get("competition.entry")
        local e = Cal.materialize(series(), 1800000000, 3600)[1]
        T.eq(#E.pingsDue(e, e.startsAt - 16 * 60, {}), 0)
        local due = E.pingsDue(e, e.startsAt - 4 * 60, {}); T.eq(#due, 2); T.eq(due[1], "t15"); T.eq(due[2], "t5")
        T.eq(#E.pingsDue(e, e.startsAt - 4 * 60, { t15 = true, t5 = true }), 0)
        T.eq(#E.pingsDue(e, e.startsAt + 1, {}), 0, "nothing after start")
        T.eq(E.countdown(754), "12:34")
    end,
}
