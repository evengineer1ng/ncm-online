-- ncm-core module: competition.guide
-- The Race Guide (P47): the spine every event hangs off. Pure: the host hands in the calendar's events, the
-- driver's entries and practice standings; this module derives the rows a driver browses, decides "interest"
-- (P52: the ordinary entry — a soft list, no reservation; the grid is whoever checks in at the venue, L48) and
-- says when on-demand practice is open (P48: from posting until qualifying forms, no window, no countdown).
local Core = NcmCore

Core.define("competition.guide", function(C)
    local M = { version = "0.0.1" }
    local ids = C.get("vocabulary.ids")
    local Routes = C.get("course.routes")
    local Discipline = C.get("competition.discipline")

    M.TIER = { calendar = "street", organized = "sanctioned" }

    --- Tier tag for an event (L58): street cadence vs sanctioned/organized.
    function M.tierOf(e)
        if e.tier then return e.tier end
        return M.TIER[e.class or "calendar"] or "street"
    end

    --- Practice (P48) is open for an event from its posting until qualifying forms — or, for a format with no
    --- qualifying, until the first session forms. `formsAt` is when the host forms that session (startsAt - formLead).
    function M.practiceWindow(e, formLeadSec)
        -- a Paddock race's qualifying closes with its entries at T-11 (L250, paddock.mixed), not when the grid forms
        if e.class == "paddock" and tonumber(e.entryClosesAt) then
            return { opensAt = e.postedAt or 0, closesAt = e.entryClosesAt }
        end
        local formsAt = (e.startsAt or 0) - (e.practiceCloseLeadSec or formLeadSec or 60)
        return { opensAt = e.postedAt or 0, closesAt = formsAt }
    end

    function M.practiceOpen(e, now, formLeadSec)
        if e.state == "closed" or e.state == "cancelled" then return false, "event_closed" end
        local w = M.practiceWindow(e, formLeadSec)
        if now < w.opensAt then return false, "not_posted" end
        if now >= w.closesAt then return false, "qualifying_forming" end
        return true, w
    end

    --- One row per event the driver can browse. events = array (ascending startsAt) of calendar/organized events with
    --- .entries (driverId -> entry); driverId may be nil (anonymous view); practice = { [eventId] = { [driverId] = bestSec } }.
    function M.rows(events, driverId, now, opts)
        opts = opts or {}
        local out = {}
        for i, e in ipairs(events) do
            -- L249: a time trial called from Street Call is its caller's alone -- on nobody else's board
            local private = e.timeTrial and e.calledBy ~= driverId
            if not private and e.state ~= "cancelled" and (opts.includeClosed or e.state ~= "closed") then
                local interested, entered = 0, 0
                for _, en in pairs(e.entries or {}) do
                    if en.state == "interested" then interested = interested + 1
                    elseif en.state ~= "withdrawn" then entered = entered + 1 end
                end
                local mine = driverId and e.entries and e.entries[driverId] or nil
                local pOpen, pWhy = M.practiceOpen(e, now, opts.formLeadSec)
                local pBest = driverId and opts.practice and opts.practice[e.eventId] and opts.practice[e.eventId][driverId] or nil
                local route = Routes.resolve(e.routeId, e.routeName)
                local discipline = Discipline.byId(e.disciplineId)
                local adapter = e.courseAdapter or (discipline and discipline.adapter) or "p2p"
                local region = e.region or (route and route.region) or (e.venue and e.venue.region) or "Unknown"
                local finishRegion = e.finishRegion or (route and route.finishRegion) or region
                local startType = e.startType or (adapter == "laps" and "rolling" or "standing")
                -- The route's AUTHORED description is the one a player should read. It says what the road is
                -- like -- "a long, kinked tunnel toward the finish" -- which is the thing that helps them decide.
                -- This used to generate a line unconditionally and never look at `route.description`, so every
                -- authored description in `data.roots` was written, stored, resolved, and then thrown away at
                -- render time. The generated line is still worth having, so it becomes `summary`: the facts
                -- (discipline, start and finish, start type) beneath the prose, rather than instead of it.
                local summary
                if adapter == "laps" then
                    summary = ("%d-lap %s in %s. %s start."):format(e.laps or 1, (e.disciplineId or "race"):gsub("_", " "), region, startType)
                else
                    summary = ("%s from %s to %s. %s start."):format((e.disciplineId or "race"):gsub("_", " "), e.venue and e.venue.name or "the start", e.finish and e.finish.name or "the finish", startType)
                end
                local description = (route and route.description) or summary
                out[#out + 1] = {
                    n = #out + 1, eventId = e.eventId, tier = M.tierOf(e),
                    seriesName = e.seriesName, routeName = e.routeName, routeId = e.routeId,
                    venueName = e.venue and e.venue.name or "?", finishName = e.finish and e.finish.name or nil,
                    distanceM = e.distanceM, disciplineId = e.disciplineId, formatId = e.formatId, classId = e.classId, laps = e.laps or 1,
                    -- IDEA-125: the regs a player is agreeing to. `rulesetId` names the sporting policy
                    -- (L84(c): ruleset owns rules, championship owns economics); it is a name today and
                    -- the `ruleset` table behind it renders nowhere yet.
                    rulesetId = e.rulesetId, seriesId = e.seriesId,
                    startsAt = e.startsAt, entryOpensAt = e.entryOpensAt, entryClosesAt = e.entryClosesAt, state = e.state,
                    invitation = e.invitation and true or false,
                    interested = interested, entered = entered, seatsTotal = e.seatsTotal or 0,
                    region = region, finishRegion = finishRegion, courseAdapter = adapter, startType = startType, summary = summary,
                    description = description,
                    economy = e.economy,
                    myState = (mine and mine.state ~= "withdrawn") and mine.state or "none",
                    practice = pOpen and "open" or pWhy, myPracticeBest = pBest,
                    venue = e.venue and { x = e.venue.x, y = e.venue.y, z = e.venue.z } or nil,
                }
            end
        end
        return out
    end

    --- Decide "interest". req = { event, now, driverId, existingEntry?, rng }
    --- Returns { ok=true, entry } or { ok=false, reason }.
    function M.interest(req)
        local e = req.event
        if type(e) ~= "table" then return { ok = false, reason = "no_event" } end
        if e.state == "closed" or e.state == "cancelled" then return { ok = false, reason = "event_closed" } end
        if req.now >= e.startsAt then return { ok = false, reason = "event_started" } end
        if e.invitation then return { ok = false, reason = "invitation_only" } end   -- a seat offer is the NCX entry (P52)
        local ex = req.existingEntry
        if ex and ex.state ~= "withdrawn" then
            if ex.state == "interested" then return { ok = false, reason = "already_interested" } end
            return { ok = false, reason = "already_entered" }
        end
        if not ex and type(req.rng) ~= "function" then return { ok = false, reason = "rng_required" } end
        return {
            ok = true,
            rejoined = ex ~= nil,   -- a withdrawn entry comes back under its own id (the row is unique per event+driver)
            entry = {
                entryId = ex and ex.entryId or ids.uuid4(req.rng), eventId = e.eventId, driverId = req.driverId,
                state = "interested", interestedAt = req.now, fee = 0,
            },
        }
    end

    --- An entry that is over. Withdrawing one of these would rewrite sporting history (L74c), so it is refused
    --- however it is asked for.
    local CLASSIFIED = { finished = true, dnf = true, dns = true, dsq = true }
    --- An entry that has not started. These may be withdrawn.
    local WITHDRAWABLE = { interested = true, checked_in = true, registered = true, provisioned = true }

    --- Leave an event you have not started yet.
    ---
    --- **This used to refuse the only case the venue panel offers it for.** The rule was "only an `interested`
    --- entry can be withdrawn; a check-in is a commitment", so a driver who had entered a race and pressed
    --- WITHDRAW was told *"You're already entered."* -- forever, deterministically, with no way out short of
    --- disconnecting (owner QA, 2026-09-23). `venue_options.evaluate` enables WITHDRAW precisely when
    --- `entryState == "checked_in"`; the two halves disagreed and the control was dead from the day it shipped.
    ---
    --- The commitment reading was not wrong, it was misplaced: what you cannot take back is a race you have
    --- STARTED. That is a forfeit and it belongs to the session kernel (`session.race.leave`), which already
    --- classifies it DNS before green and DNF after. Here the split is the one the owner named:
    ---
    ---     WITHDRAWN = entered but did not start        FORFEIT/DNF = started but did not finish
    ---
    --- req = { existingEntry, inSession? } -- `inSession` is the host's answer to "is a live session holding
    --- this driver", which only the host can know. Returns { ok=true, entryId, wasEntered } or { ok=false, reason }.
    function M.withdraw(req)
        local ex = req.existingEntry
        if not ex or ex.state == "withdrawn" then return { ok = false, reason = "no_entry" } end
        if CLASSIFIED[ex.state] then return { ok = false, reason = "already_raced" } end
        -- Gridded or out on track: this is a forfeit, and the session -- not the entry row -- owns it.
        if req.inSession or not WITHDRAWABLE[ex.state] then return { ok = false, reason = "in_session" } end
        return { ok = true, entryId = ex.entryId, wasEntered = ex.state ~= "interested" }
    end

    return M
end)
