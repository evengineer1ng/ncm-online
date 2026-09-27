local L = NcmCore.get("player.landing")

local function release(date, title, seq)
    return { date = date, title = title, seq = seq, items = { { heading = "Economy", text = "Payouts." } } }
end

return {
    ["the contract says progression is temporary, not that cheating is punished"] = function(T)
        T.eq(L.CONTRACT.headline, "PROGRESSION IS TEMPORARY")
        T.ok(L.CONTRACT.body:find("resets for NCM 1.0") ~= nil)
        -- The framing matters: a player must read this as provisional, not as a threat.
        T.eq(L.CONTRACT.body:lower():find("cheat"), nil)
        T.eq(L.CONTRACT.body:lower():find("ban"), nil)
    end,
    ["a release needs a real date and at least one item"] = function(T)
        T.eq(L.normalizeRelease({ date = "2026-9-27", title = "X", items = { "a" } }), nil)
        T.eq(L.normalizeRelease({ date = "2026-13-01", title = "X", items = { "a" } }), nil)
        local _, why = L.normalizeRelease({ date = "2026-09-27", title = "X", items = {} })
        T.eq(why, "release_needs_at_least_one_item")
        T.ok(L.normalizeRelease({ date = "2026-09-27", title = "X", items = { "a" } }) ~= nil)
    end,
    ["items accept a bare string or a headed entry"] = function(T)
        local r = assert(L.normalizeRelease({ date = "2026-09-27", title = "X",
            items = { "plain", { heading = "Practice", text = "Ghosts." } } }))
        T.eq(#r.items, 2)
        T.eq(r.items[1].heading, nil)
        T.eq(r.items[2].heading, "Practice")
    end,
    ["a partial capability must state its limit"] = function(T)
        local _, why = L.normalizeCapability({ id = "ghosts", label = "Lap ghosts", state = "partial" })
        T.eq(why, "partial_capability_needs_a_limit")
        T.ok(L.normalizeCapability({ id = "ghosts", label = "Lap ghosts", state = "partial",
            limit = "Personal best only." }) ~= nil)
    end,
    ["only live and partial capabilities count as things to do today"] = function(T)
        local p = L.payload({ capabilities = {
            { id = "race", label = "Enter races", state = "live" },
            { id = "ghost", label = "Lap ghosts", state = "partial", limit = "Personal best only." },
            { id = "fuel", label = "Fuel", state = "soon" },
        } })
        T.eq(#p.capabilities, 3)
        T.eq(p.offeredCount, 2)
        -- live sorts above partial sorts above soon
        T.eq(p.capabilities[1].state, "live")
        T.eq(p.capabilities[3].state, "soon")
    end,
    ["releases come back newest first, with a stable tiebreak on one date"] = function(T)
        local p = L.payload({ releases = {
            release("2026-09-01", "Older"), release("2026-09-27", "Same day A", 1),
            release("2026-09-27", "Same day B", 2), release("2026-09-14", "Middle"),
        } })
        T.eq(#p.releases, 4)
        T.eq(p.releases[1].title, "Same day B")
        T.eq(p.releases[2].title, "Same day A")
        T.eq(p.releases[3].title, "Middle")
        T.eq(p.releases[4].title, "Older")
    end,
    ["only the newest release opens, so the panel is never a vertical wall"] = function(T)
        local p = L.payload({ releases = { release("2026-09-01", "A"), release("2026-09-27", "B") } })
        T.eq(p.releases[1].expanded, true)
        T.eq(p.releases[2].expanded, false)
    end,
    ["new is relative to what the driver last saw, not to the clock"] = function(T)
        local config = { releases = { release("2026-09-01", "A"), release("2026-09-14", "B"),
            release("2026-09-27", "C") } }
        local p = L.payload(config, { lastReleaseDate = "2026-09-01" })
        T.eq(p.newReleaseCount, 2)
        T.eq(p.firstSession, false)
        local caught = L.payload(config, { lastReleaseDate = "2026-09-27" })
        T.eq(caught.newReleaseCount, 0)
    end,
    ["a first-ever session is not the same as nothing having changed"] = function(T)
        local p = L.payload({ releases = { release("2026-09-27", "C") } })
        T.eq(p.firstSession, true)
        T.eq(p.newReleaseCount, 0)   -- nothing is marked NEW to somebody who has seen nothing
    end,
    ["the seen watermark only ever moves forward"] = function(T)
        local p = L.payload({ releases = { release("2026-09-14", "B") } })
        T.eq(L.advance({ lastReleaseDate = "2026-09-27" }, p).lastReleaseDate, "2026-09-27")
        T.eq(L.advance({ lastReleaseDate = "2026-09-01" }, p).lastReleaseDate, "2026-09-14")
        T.eq(L.advance(nil, p).lastReleaseDate, "2026-09-14")
    end,
    ["an empty configuration still produces a renderable payload"] = function(T)
        local p = L.payload(nil, nil)
        T.eq(p.currentRelease, nil)
        T.eq(#p.releases, 0)
        T.eq(p.offeredCount, 0)
        T.ok(p.contract ~= nil)   -- the contract is never absent; it is the point of the panel
    end,
}
