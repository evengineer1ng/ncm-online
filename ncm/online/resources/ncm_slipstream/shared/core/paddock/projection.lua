-- ncm-core module: paddock.projection
-- The only way Paddock data leaves the server (doc 44 §4.3, §14.2).
--
-- Every payload row is built here from a WHITELIST of fields, and `assertNoHidden` walks the finished payload and
-- refuses it if any key names a hidden attribute (`paddock.attributes.HIDDEN`). The builders make leaking hard;
-- the assertion makes it impossible to ship silently. Numbers players may see: positions, points, gaps, times,
-- counts, prices, eddies. Never a stat, a trait, a personality axis or a morale value.
local Core = NcmCore

Core.define("paddock.projection", function(C)
    local M = { version = "0.1.0" }
    local Attr = C.get("paddock.attributes")

    --- Walk a payload; return false and the offending path when any key is hidden.
    function M.findHidden(value, path, depth)
        depth = depth or 0
        if depth > 12 or type(value) ~= "table" then return nil end
        for k, v in pairs(value) do
            if type(k) == "string" and Attr.HIDDEN[k] then return (path or "") .. "." .. k end
            local found = M.findHidden(v, (path or "") .. "." .. tostring(k), depth + 1)
            if found then return found end
        end
        return nil
    end

    function M.assertNoHidden(payload)
        local found = M.findHidden(payload, "payload")
        if found then error("paddock.projection: hidden key leaked at " .. found, 2) end
        return payload
    end

    local function secs(ms)
        if not ms then return nil end
        return math.floor(ms / 10 + 0.5) / 100
    end
    M.secs = secs

    function M.gapText(ms)
        if not ms then return nil end
        if ms <= 0 then return "leader" end
        return string.format("+%.2fs", ms / 1000)
    end

    function M.wireRow(story)
        return { id = story.storyId, at = story.at, kind = story.kind, headline = story.headline, body = story.body,
            prominence = story.prominence }
    end

    function M.standingRow(s, name, orgName, tags)
        return { pos = s.pos, id = s.id, name = name, org = orgName, pts = s.points, wins = s.wins, pod = s.podiums,
            starts = s.starts, dnfs = s.dnfs, tags = tags }
    end

    function M.raceRow(r, routeName, seriesName, winnerName, winnerOrg)
        return { raceId = r.raceId, at = r.at, series = seriesName, route = routeName, state = r.state,
            weather = r.weather, light = r.light, wet = r.roadWetness, provenance = r.provenance,
            winner = winnerName, winnerOrg = winnerOrg, commit = r.commit }
    end

    function M.boxRow(res, driverName, orgName, qualiMs)
        return { pos = res.position, grid = res.grid, driver = driverName, driverId = res.personId, org = orgName,
            time = res.state == "finished" and secs(res.finishMs) or nil, gap = M.gapText(res.gapMs),
            state = res.state, note = res.dnfReason, points = res.points, quali = secs(qualiMs) }
    end

    --- The qualifying sheet of a frozen grid (L250 step 2): grid order, each with their time in seconds (nil = no time).
    function M.qualiSheet(frozen, nameOf)
        local out = {}
        if type(frozen) ~= "table" or type(frozen.grid) ~= "table" then return out end
        local q = frozen.quali or {}
        for i, id in ipairs(frozen.grid) do
            out[i] = { grid = i, id = id, name = nameOf and nameOf(id) or id, quali = secs(tonumber(q[id])) }
        end
        return out
    end

    function M.directoryRow(kind, circuit, id, name, tier, role, org, tags)
        return { kind = kind, circuit = circuit, id = id, name = name, tier = tier, role = role, org = org, tags = tags }
    end

    function M.personProfile(p, ctx)
        ctx = ctx or {}
        return { id = p.id, name = p.display, role = p.role, org = ctx.orgName, orgId = p.orgId, region = ctx.regionLabel,
            ageBand = ctx.ageBand, tags = ctx.tags, state = p.state, wins = ctx.wins, starts = ctx.starts,
            podiums = ctx.podiums, titles = ctx.titles }
    end

    function M.orgProfile(o, ctx)
        ctx = ctx or {}
        return { id = o.id, name = o.name, short = o.short, colour = o.colour, tier = o.tier, series = ctx.seriesName,
            owner = ctx.ownerName, manager = ctx.managerName, humanManaged = o.humanManagerDriverId ~= nil,
            tags = ctx.tags, sponsors = ctx.sponsors, founded = o.foundedSeason }
    end

    function M.lineRow(line, label, refused)
        return { lineId = line.lineId, version = line.version, market = line.market, label = label,
            price = (not refused) and line.price or nil, refused = refused or nil }
    end

    local AGE_BANDS = { { 21, "teens-early 20s" }, { 26, "early 20s" }, { 30, "late 20s" }, { 35, "early 30s" },
        { 40, "late 30s" }, { 200, "veteran" } }
    function M.ageBand(age)
        for _, b in ipairs(AGE_BANDS) do if (age or 25) < b[1] then return b[2] end end
        return "veteran"
    end

    M.REGION_LABELS = {
        british = "British Isles", italian = "Italy", latin = "Latin America", german = "Central Europe",
        french = "France", scandinavian = "Scandinavia", dutch = "Low Countries", eastern_european = "Eastern Europe",
        japanese = "Japan", chinese = "China", brazilian = "Brazil", american = "North America",
        australian = "Oceania", indian = "South Asia", middle_eastern = "Middle East", african = "Africa",
        korean = "Korea", southeast_asian = "Southeast Asia",
    }

    return M
end)
