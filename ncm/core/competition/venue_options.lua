-- ncm-core module: competition.venue_options
-- What a driver standing at a venue can actually do right now (IDEA-095). Pure: the host hands in the event, this
-- driver's entry, the practice window and whether a session is already live; this module returns a SHORT FLAT LIST
-- of final actions, most likely intent first.
--
-- The shape is the design (owner, 2026-09-21): a short list, each one a FINAL ACT and never a branch, no sub-menus
-- and no tree. Every option is always shown; one that cannot apply right now is greyed WITH A REASON (owner,
-- 2026-09-23 -- see `pack`). The host draws the list and holds a key to engage the highlighted one; nothing here
-- knows about keys, cards or pixels.
--
-- The event is the one whose ring the driver is STANDING IN (owner, 2026-09-28). It used to be "the driver's
-- soonest race", decided without looking at where they were, so the card on one ring could act on another race.
local Core = NcmCore

Core.define("competition.venue_options", function(C)
    local M = { version = "0.0.1" }
    local Guide = C.get("competition.guide")
    local Entry = C.get("competition.entry")

    -- Five, because every option is now always present (owner, 2026-09-23). It used to be four, when
    -- inapplicable options were omitted and the list could not exceed the catalogue's applicable subset.
    M.MAX_OPTIONS = 5

    -- Every option this module can emit. `id` is stable forever (it becomes an event name and a log token);
    -- `label` is what the host shows, English, upper case at the point of display, not here.
    M.CATALOGUE = {
        { id = "enter_race", label = "Enter Race" },
        { id = "practice",   label = "Practice" },
        { id = "withdraw",   label = "Withdraw" },
        { id = "leave_list", label = "Leave List" },
        { id = "history",    label = "History" },
    }

    -- Most likely intent first. `history` is last because it is the only one that changes nothing.
    M.PRIORITY = { "enter_race", "practice", "withdraw", "leave_list", "history" }

    local function labelOf(id)
        for _, o in ipairs(M.CATALOGUE) do if o.id == id then return o.label end end
        return nil
    end

    --- The options for one driver at one venue.
    --- facts = {
    ---   now         = server seconds (required)
    ---   event       = { eventId, startsAt, entryOpensAt, entryClosesAt, state, invitation, postedAt } (required)
    ---   entryState  = "interested" | "registered" | "checked_in" | ... | nil  -- this driver's row here, absent = none
    ---   heldElsewhere = { eventId, routeName, releasable } when the driver holds their one entry on ANOTHER
    ---                 event (competition.entry.heldEntry). Entering here then becomes a switch (owner, 2026-09-28).
    ---   switchArmed = true when the driver has pressed SWITCH ENTRY here and the host is waiting for the confirm
    ---   sessionLive = true when a session for this event is already forming or running
    ---   busyElsewhere = true when this driver is in an unfinished session of ANOTHER event (KB-37)
    ---   practiceActive = true when this driver is in this event's practice session (L114)
    ---   formLeadSec = how early the host forms the first session (default 60)
    ---   carRefusal  = a reason slug when this driver cannot field a legal car (L83), absent when they can.
    ---                 The host decides it (it needs the garage ledger); this module only stops offering an
    ---                 entry the server would refuse a second later.
    --- }
    --- Returns { options = { { id, label } ... }, reasons = { [id] = "why it is absent" } }.
    --- `reasons` is diagnostics for the host log only and is never shown to a player.
    function M.evaluate(facts, opts)
        if type(facts) ~= "table" then error("competition.venue_options.evaluate: facts must be a table", 2) end
        local e = facts.event
        if type(e) ~= "table" then error("competition.venue_options.evaluate: facts.event must be a table", 2) end
        local now = tonumber(facts.now)
        if not now then error("competition.venue_options.evaluate: facts.now must be a number", 2) end
        opts = opts or {}
        local maxOptions = tonumber(opts.maxOptions) or M.MAX_OPTIONS

        local reasons = {}
        local on = {}
        local function decline(id, why) reasons[id] = why end

        local entry = facts.entryState
        -- A team seat (`registered`) is an entry too (owner, 2026-09-28). It used to count as neither entered nor
        -- listed, so a seated driver's WITHDRAW was greyed as "You are not entered".
        local entered = Entry.RELEASABLE[tostring(entry or "")] == true
        local listed = entry == "interested"

        -- History changes nothing and is always available: it is the one option that is never a dead end.
        on.history = true

        if facts.busyElsewhere then
            -- KB-37: one session at a time. Everything that would commit them is absent, not refused later.
            decline("enter_race", "busy_elsewhere")
            decline("practice", "busy_elsewhere")
            decline("withdraw", "busy_elsewhere")
            decline("leave_list", "busy_elsewhere")
            return M.pack(on, reasons, maxOptions)
        end

        if e.invitation then
            decline("enter_race", "invitation_only")
        elseif facts.carRefusal then
            -- L83: entry is refused, never substituted. Refusing by NOT OFFERING is the better half of that --
            -- an option that would be rejected on press is a dead end, and the rule here is already "absent,
            -- not greyed". The host still re-checks on entry; this only stops the list lying.
            decline("enter_race", facts.carRefusal)
        elseif entered then
            decline("enter_race", "already_entered")
        elseif facts.sessionLive then
            decline("enter_race", "grid_forming")
        elseif e.state == "cancelled" or e.state == "closed" then
            decline("enter_race", "event_closed")
        elseif e.entryOpensAt and now < e.entryOpensAt then
            decline("enter_race", "entry_not_open")
        elseif e.entryClosesAt and now >= e.entryClosesAt then
            decline("enter_race", "entry_closed")
        else
            on.enter_race = true
        end

        -- One entry at a time. Entering here while holding an entry elsewhere is a SWITCH, and a switch is two
        -- presses: the first arms it and says what it will cost, the second does both halves.
        local held = facts.heldElsewhere
        if on.enter_race and type(held) == "table" then
            on.enter_race = nil
            if held.releasable == false then
                decline("enter_race", "entered_elsewhere")
            else
                on.switch = facts.switchArmed and "confirm_switch" or "switch_entry"
                on.switchFrom = held.routeName
            end
        end

        -- Practice is user-initiated and unlimited while the window stands (L67/IDEA-002); it is never a
        -- registration deadline, which is what KB-31 says the wording currently implies.
        if facts.practiceActive then
            decline("practice", "already_practising")
            on.leave_practice = true
        elseif facts.sessionLive then
            decline("practice", "session_forming")
        else
            local open, why = Guide.practiceOpen(e, now, facts.formLeadSec or 60)
            if open then on.practice = true else decline("practice", type(why) == "string" and why or "practice_closed") end
        end

        -- Leaving: a soft list is left, a real entry is withdrawn. They are different acts on different rows, so
        -- they are different options -- never one row whose meaning depends on state the player cannot see.
        if entered then on.withdraw = true else decline("withdraw", "not_entered") end
        if listed then on.leave_list = true else decline("leave_list", "not_listed") end

        return M.pack(on, reasons, maxOptions)
    end

    --- Order the enabled ids by PRIORITY and cap the list. Separate so tests can drive it directly.
    --- Why an option is unavailable, in words a player can act on. `reasons` remains the internal slug for
    --- the host log; this is the half that reaches a human.
    M.EXPLAIN = {
        busy_elsewhere   = "You are committed to another session",
        invitation_only  = "By invitation",
        already_entered  = "You are already entered",
        grid_forming     = "The grid is forming",
        event_closed     = "This event is closed",
        entry_not_open   = "Entries not open yet",
        entry_closed     = "Entries have closed",
        not_listed       = "Express interest first",
        not_entered      = "You are not entered",
        practice_closed  = "Practice is closed",
        already_practising = "You are already practising",
        entered_elsewhere = "You are committed to another race",
        not_posted       = "Not posted yet",
        qualifying_forming = "Practice has closed",
        session_forming  = "The session is forming",
        no_car           = "You have no eligible car",
        over_cap         = "Not shown here",
    }

    function M.explain(slug)
        if slug == nil then return nil end
        return M.EXPLAIN[tostring(slug)] or "Not available right now"
    end

    --- Build the list. **Every option in the catalogue is returned, every time.**
    ---
    --- This reverses the previous rule ("an inapplicable option is absent, not disabled"). The owner, standing
    --- on a start line and offered nothing but HISTORY, was unable to tell a system that had decided against
    --- them from a system that was broken -- and on that occasion it WAS broken. An absent control teaches a
    --- player nothing; a greyed one with a reason teaches them what to do next.
    ---
    --- `enabled` says whether it may be pressed; `why` says why not. Hosts must still re-check on action: this
    --- list is guidance, never authority.
    function M.pack(on, reasons, maxOptions)
        local limit = maxOptions or M.MAX_OPTIONS
        local options = {}
        for _, id in ipairs(M.PRIORITY) do
            if #options < limit then
                -- Keep the established five-row payload shape. While practising, the PRACTICE slot becomes
                -- the explicit exit rather than adding a sixth row that older clients may not render safely.
                local outId = (id == "practice" and on.leave_practice) and "leave_practice" or id
                local label = outId == "leave_practice" and "Leave Practice" or labelOf(id)
                -- Same trick for the one-entry switch: the ENTER slot becomes the switch, never a sixth row.
                if id == "enter_race" and on.switch then
                    outId = on.switch
                    label = outId == "confirm_switch"
                        and ("Withdraw from %s and enter"):format(tostring(on.switchFrom or "your race"))
                        or "Switch Entry"
                end
                local ok = (outId == "leave_practice") or (outId ~= id) or on[id] == true
                options[#options + 1] = {
                    id = outId, label = label, enabled = ok,
                    why = (not ok) and M.explain(reasons[id]) or nil,
                }
            else
                reasons[id] = reasons[id] or "over_cap"
            end
        end
        return { options = options, reasons = reasons }
    end

    return M
end)
