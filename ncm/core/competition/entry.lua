-- ncm-core module: competition.entry
-- Venue check-in decision (L35, P21) and ping schedule (P19). Pure: hosts supply positions and time.
local Core = NcmCore

Core.define("competition.entry", function(C)
    local M = { version = "0.0.1" }
    local routes = C.get("course.routes")
    local ids = C.get("vocabulary.ids")

    M.DEFAULT_VENUE_RADIUS_M = 30
    M.PINGS = {
        { key = "t15", beforeSec = 15 * 60 },
        { key = "t5", beforeSec = 5 * 60 },
        { key = "t1", beforeSec = 60 },
    }

    --- Decide a check-in. req = { event, now, driverId, position={x,y,z}, existingEntry?, radiusM?, rng }
    --- Returns { ok=true, entry } or { ok=false, reason, ... }.
    function M.checkIn(req)
        local e = req.event
        if type(e) ~= "table" then return { ok = false, reason = "no_event" } end
        local ex = req.existingEntry
        if ex and ex.state ~= "interested" and ex.state ~= "withdrawn" then return { ok = false, reason = "already_entered" } end
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
                fee = 0, -- L21: money-free first world
                distanceM = d,
            },
        }
    end

    --- Advance registration for organized events (P21 `registered`): no venue, no window check beyond
    --- "before the start". req = { event, now, driverId, existingEntry?, seat?, rng }
    function M.register(req)
        local e = req.event
        if type(e) ~= "table" then return { ok = false, reason = "no_event" } end
        if req.existingEntry then return { ok = false, reason = "already_entered" } end
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
