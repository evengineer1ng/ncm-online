-- ncm-core module: competition.entry
-- Venue check-in decision (L35, P21) and ping schedule (P19). Pure: hosts supply positions and time.
local Core = NcmCore

Core.define("competition.entry", function(C)
    local M = { version = "0.0.1" }
    local routes = C.get("course.routes")
    local ids = C.get("vocabulary.ids")

    --- The ring a player sees IS the rule (owner, 2026-09-28: "inside the drawn ring"). The client draws a ring of
    --- exactly this radius and the server accepts an entry inside it. The tolerance covers position staleness and
    --- nothing more; it used to be a 30 m allowance around a 6 m ring, so what you saw was not what was checked.
    M.RING_RADIUS_M = 6.0
    M.RING_TOLERANCE_M = 1.5
    M.DEFAULT_VENUE_RADIUS_M = M.RING_RADIUS_M + M.RING_TOLERANCE_M
    --- Every race gets its own ring at its own venue from this long before its start (owner, 2026-09-28), and the
    --- ring is visible from far enough away to spot it and head over. The server publishes every race inside the
    --- lead so the client can draw them all; RING_MAX bounds that against the platform's 64-marker ceiling.
    M.RING_LEAD_S = 20 * 60
    M.RING_VISIBLE_M = 500      -- the platform's marker draw-distance ceiling (open77_worldui clamps to 500)
    M.RING_MAX = 16

    --- The states that make an entry YOUR entry. A driver holds at most one of these at a time (owner,
    --- 2026-09-28: "one entry at a time", and a team seat counts). `interested` is a bookmark, not an entry;
    --- `finished`/`dnf`/`dns`/`dsq`/`withdrawn` are over.
    M.HELD = { registered = true, checked_in = true, provisioned = true, gridded = true, racing = true,
               suspended = true, substituted = true }
    --- The subset of HELD that may still be given up without it being a forfeit.
    M.RELEASABLE = { registered = true, checked_in = true, provisioned = true }

    --- The one entry this driver holds, other than on `exceptEventId`. events = array of events with .entries;
    --- `live(e)` is the host's answer to "is this event still happening" (not closed, or a session still running
    --- for it) -- an entry on an event that ended without classifying it must never block the driver forever.
    --- Returns event, entry or nil.
    function M.heldEntry(events, driverId, exceptEventId, live)
        if not driverId then return nil end
        for _, e in ipairs(events or {}) do
            local en = e.entries and e.entries[driverId]
            if en and M.HELD[tostring(en.state or "")] and e.eventId ~= exceptEventId and (not live or live(e)) then
                return e, en
            end
        end
        return nil
    end

    M.PINGS = {
        { key = "t15", beforeSec = 15 * 60 },
        { key = "t5", beforeSec = 5 * 60 },
        { key = "t1", beforeSec = 60 },
    }

    --- Decide a check-in. req = { event, now, driverId, position={x,y,z}, existingEntry?, heldElsewhere?, radiusM?, rng }
    --- `heldElsewhere` is the driver's entry on ANOTHER event (see `heldEntry`); the host must release it first.
    --- Returns { ok=true, entry } or { ok=false, reason, ... }.
    function M.checkIn(req)
        local e = req.event
        if type(e) ~= "table" then return { ok = false, reason = "no_event" } end
        local ex = req.existingEntry
        if ex and ex.state ~= "interested" and ex.state ~= "withdrawn" then return { ok = false, reason = "already_entered" } end
        if req.heldElsewhere then return { ok = false, reason = "entered_elsewhere" } end
        if req.now < e.entryOpensAt then
            return { ok = false, reason = "window_not_open", opensIn = e.entryOpensAt - req.now }
        end
        if req.now > e.entryClosesAt then return { ok = false, reason = "window_closed" } end
        if type(req.position) ~= "table" then return { ok = false, reason = "position_unknown" } end
        local d = routes.planarDistance(req.position, e.venue)
        local radius = req.radiusM or M.DEFAULT_VENUE_RADIUS_M
        if d > radius then return { ok = false, reason = "not_at_venue", distanceM = d, radiusM = radius } end
        if not ex and type(req.rng) ~= "function" then return { ok = false, reason = "rng_required" } end
        return {
            ok = true,
            upgraded = ex ~= nil,   -- interest (Race Guide, P52) became the physical entry (L48); same entry id
            entry = {
                entryId = ex and ex.entryId or ids.uuid4(req.rng),
                eventId = e.eventId,
                driverId = req.driverId,
                state = "checked_in",
                checkedInAt = req.now,
                interestedAt = ex and ex.interestedAt or nil,
                fee = math.max(0, math.floor(tonumber(req.fee) or 0)),
                distanceM = d,
            },
        }
    end

    --- Advance registration for organized events (P21 `registered`): no venue, no window check beyond
    --- "before the start". req = { event, now, driverId, existingEntry?, heldElsewhere?, seat?, rng }
    --- A seat is an entry like any other, so it too is refused while the driver holds one elsewhere.
    function M.register(req)
        local e = req.event
        if type(e) ~= "table" then return { ok = false, reason = "no_event" } end
        if req.existingEntry then return { ok = false, reason = "already_entered" } end
        if req.heldElsewhere then return { ok = false, reason = "entered_elsewhere" } end
        if req.now >= e.startsAt then return { ok = false, reason = "event_started" } end
        if type(req.rng) ~= "function" then return { ok = false, reason = "rng_required" } end
        return {
            ok = true,
            entry = {
                entryId = ids.uuid4(req.rng),
                eventId = e.eventId,
                driverId = req.driverId,
                state = "registered",
                registeredAt = req.now,
                teamId = req.seat and req.seat.teamId or nil,
                seatIndex = req.seat and req.seat.seatIndex or nil,
                fee = 0,
            },
        }
    end

    --- Pings due for an event at `now` that are not in `sent` (set of keys). Returns array of keys.
    function M.pingsDue(event, now, sent)
        local out = {}
        for _, p in ipairs(M.PINGS) do
            local at = event.startsAt - p.beforeSec
            if now >= at and now < event.startsAt and not (sent and sent[p.key]) then
                out[#out + 1] = p.key
            end
        end
        return out
    end

    --- Countdown text "m:ss".
    function M.countdown(seconds)
        local s = math.max(0, math.floor(seconds + 0.5))
        local m = math.floor(s / 60)
        return string.format("%d:%02d", m, s - m * 60)
    end

    return M
end)
