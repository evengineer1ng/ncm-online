-- ncm-core module: session.standings
--
-- Who the race graph should actually show you. Pure: entries in, a short window out.
--
-- **The graph's job is local competitive context, not a grid listing** (owner, 2026-09-23). The first version
-- drew every driver across a 1240 px bar at the bottom of the screen: it covered the speedometer, said
-- nothing at all in a field of one, and would have become unreadable the moment a real field turned up. The
-- fix is not a smaller bar -- it is showing fewer people. Four, including you.
--
-- The window is positioned so you normally see one car ahead and two behind, because the car ahead is the one
-- you are chasing and the ones behind are the threat. At the front and the back there is nothing on one side,
-- so the window slides rather than shrinks: a leader sees the three chasing them, a last-placed driver sees
-- the three they are chasing. Nothing is ever invented to fill a slot.
local Core = NcmCore

Core.define("session.standings", function(C)
    local M = { version = "0.0.1" }

    M.LIMIT = 4          -- including the local driver
    M.AHEAD = 1          -- how many to show ahead of you when there are that many

    --- Pick the window to draw.
    ---
    --- `entries` must already be in running order, leader first -- ordering is the session's decision and not
    --- this module's. Each entry is opaque except for `me`, which marks the local driver.
    ---
    --- Returns the slice, plus the index of the local driver within it (nil when they are not in the list,
    --- which is what a spectator or a retired driver looks like).
    function M.focus(entries, opts)
        opts = type(opts) == "table" and opts or {}
        local limit = math.max(1, math.floor(tonumber(opts.limit) or M.LIMIT))
        local ahead = math.max(0, math.floor(tonumber(opts.ahead) or M.AHEAD))
        if type(entries) ~= "table" then return {}, nil end
        local n = #entries
        if n == 0 then return {}, nil end
        -- Fewer participants than slots is not a problem to solve. Show who is there (packet section 18C:
        -- "Do not fabricate competitors").
        if n <= limit then
            local meAt = nil
            for i, e in ipairs(entries) do if e.me then meAt = i end end
            local out = {}
            for i = 1, n do out[i] = entries[i] end
            return out, meAt
        end
        local meIndex = nil
        for i, e in ipairs(entries) do if e.me then meIndex = i; break end end
        -- No local driver in the order: show the front of the race rather than nothing.
        if not meIndex then
            local out = {}
            for i = 1, limit do out[i] = entries[i] end
            return out, nil
        end
        -- Slide, never shrink. `first` is clamped so the window always holds `limit` entries.
        local first = meIndex - ahead
        if first < 1 then first = 1 end
        if first > n - limit + 1 then first = n - limit + 1 end
        local out, meAt = {}, nil
        for i = first, first + limit - 1 do
            out[#out + 1] = entries[i]
            if i == meIndex then meAt = #out end
        end
        return out, meAt
    end

    return M
end)
