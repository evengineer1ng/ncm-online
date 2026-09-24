-- competition.venue_options (IDEA-095): the short flat list of final acts at a venue.
-- The shape is the point: every option ALWAYS present, each one final, inapplicable ones greyed with a reason.
--
-- This reverses the original rule (absent, not disabled). The owner stood on a start line, was offered nothing
-- but HISTORY, and could not tell a system that had decided against them from one that was broken -- and that
-- time it was broken. `ids()` therefore lists everything; `on()` is what availability now means.
local function ev(over)
    local e = { eventId = "e1", postedAt = 0, startsAt = 2000, entryOpensAt = 1000, entryClosesAt = 1900, state = "entry_open" }
    for k, v in pairs(over or {}) do e[k] = v end
    return e
end

local function ids(result)
    local out = {}
    for _, o in ipairs(result.options) do out[#out + 1] = o.id end
    return table.concat(out, ",")
end

--- Ids of the options a player may actually press.
local function on(result)
    local out = {}
    for _, o in ipairs(result.options) do if o.enabled then out[#out + 1] = o.id end end
    return table.concat(out, ",")
end

local function why(result, id)
    for _, o in ipairs(result.options) do if o.id == id then return o.why end end
end

local ALL = "enter_race,practice,withdraw,leave_list,history"

return {
    the_ordinary_case_offers_enter_practice_history = function(T)
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1500, event = ev() })
        T.eq(on(r), "enter_race,practice,history", "entry open, nothing entered: the three doors, most likely first")
        T.eq(r.options[1].label, "Enter Race")
    end,

    an_entered_driver_is_offered_withdraw_not_enter = function(T)
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1500, event = ev(), entryState = "checked_in" })
        T.eq(on(r), "practice,withdraw,history")
        T.eq(r.reasons.enter_race, "already_entered")
        T.eq(r.reasons.leave_list, "not_listed", "withdrawing an entry and leaving a soft list are different acts")
    end,

    a_listed_driver_can_still_enter_or_leave_the_list = function(T)
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1500, event = ev(), entryState = "interested" })
        T.eq(on(r), "enter_race,practice,leave_list,history", "interest is not entry (P52): entering is still offered")
    end,

    the_list_is_bounded_and_history_is_never_lost = function(T)
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1500, event = ev(), entryState = "interested" })
        -- Five now, not four: every option is always shown, so the cap is the catalogue size rather than a
        -- trim of whatever happened to apply. The bound still exists so the card can never grow unbounded.
        T.ok(#r.options <= V.MAX_OPTIONS, "the cap is the design, not a coincidence")
        T.eq(V.MAX_OPTIONS, 5)
        T.match(ids(r), "history", "history is never lost")
        local capped = V.evaluate({ now = 1500, event = ev(), entryState = "interested" }, { maxOptions = 2 })
        T.eq(#capped.options, 2, "a host may still ask for fewer")
        T.eq(capped.reasons.history, "over_cap", "and what fell off says so")
    end,

    l114_practice_is_explicit_and_has_an_exit = function(T)
        local V = T.Core.get("competition.venue_options")
        local idle = V.evaluate({ now = 1500, event = ev(), entryState = "interested" })
        T.match(on(idle), "practice", "interest leaves practice as a separate explicit action")
        local active = V.evaluate({ now = 1500, event = ev(), entryState = "interested", practiceActive = true })
        T.eq(on(active), "enter_race,leave_practice,leave_list,history", "practice can be left or upgraded to entry")
        T.eq(ids(active), "enter_race,leave_practice,withdraw,leave_list,history", "the practice row changes act without growing the panel")
    end,

    an_inapplicable_option_is_greyed_with_a_reason_never_absent = function(T)
        local V = T.Core.get("competition.venue_options")
        -- before entries open: entering is still SHOWN, disabled, and says why
        local early = V.evaluate({ now = 500, event = ev() })
        T.eq(ids(early), ALL, "every option is present, always")
        T.eq(on(early), "practice,history")
        T.eq(early.reasons.enter_race, "entry_not_open", "the internal slug is unchanged, for the host log")
        T.eq(why(early, "enter_race"), "Entries not open yet", "...and the player gets words, not a slug")
        for _, o in ipairs(early.options) do
            T.eq(type(o.enabled), "boolean", "availability is now explicit on every row")
            if o.enabled then T.eq(o.why, nil, "an available option needs no excuse") end
        end
        local late = V.evaluate({ now = 1950, event = ev() })
        T.eq(late.reasons.enter_race, "entry_closed")
        T.eq(why(late, "enter_race"), "Entries have closed")
        T.eq(ids(late), ALL)
    end,

    -- The failure that caused the reversal: a card showing only HISTORY was indistinguishable from a broken one.
    even_when_nothing_applies_the_player_sees_the_whole_menu = function(T)
        local V = T.Core.get("competition.venue_options")
        local busy = V.evaluate({ now = 1500, event = ev(), busyElsewhere = true })
        T.eq(ids(busy), ALL, "all five rows, even when committed elsewhere")
        T.eq(on(busy), "history")
        T.eq(why(busy, "enter_race"), "You are committed to another session")
        T.eq(why(busy, "practice"), "You are committed to another session")
    end,

    invitation_events_never_offer_entry = function(T)
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1500, event = ev({ invitation = true }) })
        T.eq(r.reasons.enter_race, "invitation_only")
        T.eq(on(r), "practice,history", "a team has to offer the seat; the venue cannot")
    end,

    a_forming_session_closes_the_doors_but_not_history = function(T)
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1950, event = ev(), sessionLive = true })
        T.eq(on(r), "history")
        T.eq(r.reasons.enter_race, "grid_forming")
        T.eq(r.reasons.practice, "session_forming", "practice ends when the session forms (P48), not on a countdown")
    end,

    l83_no_legal_car_means_enter_race_is_not_offered = function(T)
        -- L83 refuses rather than substitutes, and the honest way to refuse is to stop offering. Practice and
        -- history stay: you can still learn the route while you go and earn the car.
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1500, event = ev(), carRefusal = "no_eligible_car" })
        T.eq(on(r), "practice,history")
        T.eq(r.reasons.enter_race, "no_eligible_car", "the reason travels, for the host log and the player's fix")
        -- and with a car it is offered again, unchanged
        T.eq(on(V.evaluate({ now = 1500, event = ev() })), "enter_race,practice,history")
    end,

    kb37_a_driver_racing_elsewhere_is_offered_nothing_that_commits_them = function(T)
        local V = T.Core.get("competition.venue_options")
        local r = V.evaluate({ now = 1500, event = ev(), busyElsewhere = true })
        T.eq(on(r), "history", "one session at a time: refuse by not offering, rather than offering and refusing")
        T.eq(r.reasons.enter_race, "busy_elsewhere")
        T.eq(r.reasons.practice, "busy_elsewhere")
    end,

    kb31_practice_follows_the_window_not_a_registration_deadline = function(T)
        local V = T.Core.get("competition.venue_options")
        -- open from posting right up until the first session forms (startsAt - formLeadSec)
        T.match(on(V.evaluate({ now = 1, event = ev() })), "practice")
        T.match(on(V.evaluate({ now = 1939, event = ev(), formLeadSec = 60 })), "practice")
        local formed = V.evaluate({ now = 1940, event = ev(), formLeadSec = 60 })
        T.eq(formed.reasons.practice, "qualifying_forming")
        local closed = V.evaluate({ now = 1500, event = ev({ state = "cancelled" }) })
        T.eq(closed.reasons.practice, "event_closed")
    end,

    every_catalogue_id_can_be_emitted_and_ids_are_stable = function(T)
        local V = T.Core.get("competition.venue_options")
        local seen = {}
        local cases = {
            { now = 1500, event = ev() },
            { now = 1500, event = ev(), entryState = "checked_in" },
            { now = 1500, event = ev(), entryState = "interested" },
        }
        for _, f in ipairs(cases) do
            for _, o in ipairs(V.evaluate(f, { maxOptions = 9 }).options) do seen[o.id] = true end
        end
        for _, o in ipairs(V.CATALOGUE) do T.ok(seen[o.id], "no catalogue entry is unreachable: " .. o.id) end
        T.eq(#V.PRIORITY, #V.CATALOGUE, "every option has a place in the order")
    end,

    invalid_input_errors_with_the_module_name = function(T)
        local V = T.Core.get("competition.venue_options")
        T.errors(function() V.evaluate(nil) end, "competition%.venue_options%.evaluate:")
        T.errors(function() V.evaluate({ now = 1 }) end, "competition%.venue_options%.evaluate:")
        T.errors(function() V.evaluate({ event = ev() }) end, "competition%.venue_options%.evaluate:")
    end,

    evaluation_does_not_mutate_its_input = function(T)
        local V = T.Core.get("competition.venue_options")
        local facts = { now = 1500, event = ev(), entryState = "interested" }
        local before = T.show(facts)
        V.evaluate(facts)
        T.eq(T.show(facts), before)
    end,
}
