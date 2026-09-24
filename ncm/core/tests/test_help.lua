-- The Help surface exists so a stranger can understand NCM and report a problem without leaving the game.
-- These are the rules that keep it honest: derived controls, bounded reports, and no empty sections.
return {
    controls_are_derived_and_never_advertise_a_dead_surface = function(T)
        local H = T.Core.get("player.help")
        local without = H.controls({})
        local with = H.controls({ market = true })
        T.ok(#with > #without, "the Market row appears only when the host says the Market is live")
        for _, c in ipairs(without) do
            T.neq(c.id, "market", "a surface that is not running must not be advertised (section 11)")
        end
        -- every row a player sees must tell them how to reach it
        for _, c in ipairs(with) do
            T.ok(c.key or c.cmd, c.id .. " has no key and no command")
            T.ok(type(c.title) == "string" and c.title ~= "")
            T.ok(type(c.text) == "string" and c.text ~= "")
        end
        -- Forfeit is gated on the racing capability for the same reason the Market is gated: a server whose
        -- race control is not loaded must not tell a player to type a command that will refuse them.
        for _, c in ipairs(without) do
            T.neq(c.id, "forfeit", "retiring from a race is not advertised without race control")
        end
        local racing = H.controls({ racing = true })
        local hasForfeit = false
        for _, c in ipairs(racing) do if c.id == "forfeit" then hasForfeit = true; T.match(c.cmd, "ncm.forfeit") end end
        T.ok(hasForfeit, "a driver who can start a race must be told how to leave one")
        -- ids are unique, so a host capability cannot silently map to two rows
        local seen = {}
        for _, id in ipairs(H.catalogueIds()) do
            T.eq(seen[id], nil, "duplicate catalogue id " .. id)
            seen[id] = true
        end
    end,

    help_always_documents_itself = function(T)
        local H = T.Core.get("player.help")
        local found
        for _, c in ipairs(H.controls({})) do if c.id == "help" then found = c end end
        T.ok(found, "a recovery surface that does not say how to get back to it is not a recovery surface")
        T.match(found.cmd, "ncm help")
    end,

    a_report_is_cleaned_and_bounded = function(T)
        local H = T.Core.get("player.help")
        local ok = H.cleanReport("   I bought a car   but   cannot enter the race  ")
        T.eq(ok, "I bought a car but cannot enter the race", "trimmed and collapsed, not mangled")

        local _, why = H.cleanReport("")
        T.eq(why, "empty")
        _, why = H.cleanReport("   \n\t  ")
        T.eq(why, "empty", "whitespace is not a report")
        _, why = H.cleanReport("car")
        T.eq(why, "too_short")
        _, why = H.cleanReport(nil)
        T.eq(why, "invalid")
        _, why = H.cleanReport({})
        T.eq(why, "invalid")

        local long = H.cleanReport(string.rep("a", H.TEXT_MAX + 500))
        T.eq(#long, H.TEXT_MAX, "bounded before it ever reaches a database")
    end,

    control_characters_are_stripped_so_a_report_cannot_lie = function(T)
        local H = T.Core.get("player.help")
        local s = H.cleanReport("race broke\27[2Jnothing here\0 really")
        T.ok(s and not s:find("\27"), "escape sequences out: this string is read in a console")
        T.ok(s and not s:find("%z"), "nulls out")
        T.match(s, "race broke")
        T.match(s, "really")
        -- newlines survive, because a player describing steps will use them
        local multi = H.cleanReport("first I did this\nthen that")
        T.match(multi, "first I did this\nthen that")
    end,

    disclosure_describes_what_is_actually_attached = function(T)
        local H = T.Core.get("player.help")
        local bare = H.disclosure({})
        T.match(bare, "build version")
        T.ok(not bare:find("where you were standing"), "do not promise context we did not gather")

        local full = H.disclosure({ driverId = "d", position = {}, readiness = {}, garage = {}, eligibility = {}, panel = "guide" })
        T.match(full, "where you were standing")
        T.match(full, "what you own")
        T.match(full, "which NCM screen was open")
        T.match(full, "Nothing else")
    end,

    -- The owner's warning: "authorship sounds small until it isnt."
    absent_authored_content_renders_nothing = function(T)
        local H = T.Core.get("player.help")
        local page = H.page({ build = "x" })
        T.eq(page.notices, nil, "no known-issues section rather than an empty one")
        T.eq(page.changes, nil, "no changelog section rather than an empty one")
        T.eq(H.page({ notices = {}, changes = {} }).notices, nil, "an empty list is still nothing to show")
        T.eq(H.page({ notices = { { text = "no title" } } }).notices, nil, "a malformed entry is not a section")

        local withNotice = H.page({ notices = { { title = "Guide may not open", workaround = "Press F6 again." } } })
        T.eq(#withNotice.notices, 1)
        T.eq(withNotice.notices[1].workaround, "Press F6 again.")
    end,

    page_is_self_contained_for_the_client = function(T)
        local H = T.Core.get("player.help")
        local page = H.page({ build = "world 0.5.0", live = { market = true }, serverName = "NCM" })
        T.eq(page.build, "world 0.5.0")
        T.eq(page.canReport, true, "reporting is on unless the host explicitly turns it off")
        T.eq(H.page({ canReport = false }).canReport, false)
        T.eq(page.textMax, H.TEXT_MAX, "the page must know the limit it has to enforce in the textarea")
        T.ok(#page.controls > 0)
    end,
}
