-- Who the race graph shows. The rule is "immediate local competitive context", not "the grid".
local function field(n, meAt)
    local out = {}
    for i = 1, n do out[i] = { tag = "D" .. i, me = (i == meAt) } end
    return out
end

local function tags(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.tag end
    return table.concat(out, ",")
end

return {
    -- Acceptance M. A field of one draws one driver and never invents company.
    a_solo_driver_is_alone_and_stays_alone = function(T)
        local S = T.Core.get("session.standings")
        local rows, meAt = S.focus(field(1, 1))
        T.eq(#rows, 1, "no fabricated competitors")
        T.eq(meAt, 1)
        T.eq(tags(rows), "D1")
    end,

    -- Acceptance N. Four or fewer participants: show them all, in order.
    a_small_field_is_shown_whole = function(T)
        local S = T.Core.get("session.standings")
        local rows, meAt = S.focus(field(4, 3))
        T.eq(tags(rows), "D1,D2,D3,D4")
        T.eq(meAt, 3, "and the local driver is still identifiable within it")
        T.eq(#S.focus(field(2, 2)), 2)
        T.eq(#S.focus(field(3, 1)), 3)
    end,

    -- Acceptance O. A large field stays bounded; the window slides, it never grows.
    a_large_field_stays_four = function(T)
        local S = T.Core.get("session.standings")
        for _, meAt in ipairs({ 1, 2, 7, 11, 19, 20 }) do
            local rows = S.focus(field(20, meAt))
            T.eq(#rows, 4, "20 drivers, me at " .. meAt .. ": still four rows")
        end
    end,

    -- The positioning rule, in the packet's own three cases.
    the_window_shows_one_ahead_and_two_behind = function(T)
        local S = T.Core.get("session.standings")
        -- Midfield: the car you are chasing, you, and the two chasing you.
        local mid, midMe = S.focus(field(20, 10))
        T.eq(tags(mid), "D9,D10,D11,D12")
        T.eq(midMe, 2, "one ahead of the local driver")
        -- Leading: nothing ahead exists, so the window slides down rather than shrinking.
        local first, firstMe = S.focus(field(20, 1))
        T.eq(tags(first), "D1,D2,D3,D4")
        T.eq(firstMe, 1, "the leader sees the three chasing them")
        -- Last: nothing behind, so it slides the other way.
        local last, lastMe = S.focus(field(20, 20))
        T.eq(tags(last), "D17,D18,D19,D20")
        T.eq(lastMe, 4, "the last driver sees the three they are chasing")
        -- Second place is the first position where a car ahead exists.
        local second, secondMe = S.focus(field(20, 2))
        T.eq(tags(second), "D1,D2,D3,D4")
        T.eq(secondMe, 2)
    end,

    degenerate_input_never_throws_or_fabricates = function(T)
        local S = T.Core.get("session.standings")
        T.eq(#S.focus({}), 0, "an empty field draws nothing")
        T.eq(#S.focus(nil), 0)
        -- A spectator or a retired driver is not in the order. Show the front of the race, not nothing.
        local rows, meAt = S.focus(field(20, nil))
        T.eq(tags(rows), "D1,D2,D3,D4")
        T.eq(meAt, nil, "and do not claim one of them is the viewer")
    end,
}
