-- ncm-core module: paddock.season
-- The Paddock's structure in time: tiers, series, the daily rhythm, weekly Cups, points and rollover (doc 44 §4.1, §5).
--
-- The rhythm keys to US Eastern (`world.clock`, L221/L222): street racing at night, sanctioned racing by day
-- (L224.3). A season is the UTC quarter (L100) and is split into 13 weekly Cups. First numbers are tunables in
-- `ncm_paddock/server/settings.lua`; the defaults below give 129 races a day (L236; doc 44's first 45), and a test
-- holds that.
local Core = NcmCore

Core.define("paddock.season", function(C)
    local M = { version = "0.1.0", CUPS_PER_SEASON = 13, PADDOCK_EPOCH_YEAR = 2077 }
    local Clock = C.get("world.clock")
    local Seasons = C.get("competition.seasons")
    local Hash = C.get("vocabulary.hash")

    -- Shared human routes (L226: NPCs race the same routes humans race). The eight city sprint roots every street
    -- championship already consumes (`packs/street.lua`); drag roots are left out on purpose.
    local R = {
        ukulele = "root_tip_1035_3652__to__trench_2899_2711",
        snake = "root_hill_abode_505_1229__to__downtown_2362_117",
        cut = "root_parque_del_mar_2326_1125__to__gold_niwaki_plaza_264_304",
        troll = "root_hanford_overpass_1281_1107__to__stadium_1326_1656",
        sewer = "root_north_tunnel_1450_2467__to__japantown_crossway_373_0",
        overbridge = "root_glenview_lofts_1489_964__to__corpo_plaza_1103_19",
        reverse = "root_gold_niwaki_plaza_264_304__to__parque_del_mar_2326_1125",
        hook = "root_central_highway_1110_342__to__pothole_1354_476",
    }
    M.ROUTES = R

    -- tier -> { orgs, divisions, carsPerOrg (race seats), roster (contracted drivers), vehicle band, routes, gen }.
    -- L236 (owner: "a much wider breadth and cast"; ~3x): seven street leagues -- five of them district leagues that
    -- race out of their own district -- four regional, three pro and the premier. `routes` are the named roots a tier
    -- still races on part of its slots; `gen` is the course.generator filter for the rest; `regions[d]` pins
    -- division d's starts to a district (nil = anywhere in the city).
    M.TIERS = {
        street = { rank = 1, orgs = 84, divisions = 7, carsPerOrg = 1, roster = 2, label = "Street",
            band = { classes = { "Muscle", "Sport", "Tech" }, prestigeMax = 2 },
            routes = { R.snake, R.troll, R.overbridge, R.hook, R.sewer, R.cut },
            regions = { "Watson", "Westbrook", "City Center", "Heywood", "Pacifica" },
            gen = { minM = 900, maxM = 3500, checkpoints = 2, checkpointShare = 0.45, share = 0.75 }, ovalShare = 0.15 },
        regional = { rank = 2, orgs = 48, divisions = 4, carsPerOrg = 1, roster = 4, label = "Regional",
            band = { classes = { "Muscle", "Sport", "Tech" }, prestigeMin = 2, prestigeMax = 3 },
            routes = { R.hook, R.overbridge, R.snake, R.cut, R.reverse, R.troll },
            gen = { minM = 1500, maxM = 4500, checkpoints = 2, checkpointShare = 0.5, share = 0.7 }, ovalShare = 0.1 },
        pro = { rank = 3, orgs = 30, divisions = 3, carsPerOrg = 1, roster = 4, label = "Pro",
            band = { classes = { "Sport", "Muscle" }, prestigeMin = 3, prestigeMax = 4 },
            routes = { R.cut, R.reverse, R.sewer, R.snake, R.ukulele },
            gen = { minM = 2000, maxM = 6000, checkpoints = 2, checkpointShare = 0.5, share = 0.65 }, ovalShare = 0.05 },
        premier = { rank = 4, orgs = 8, divisions = 1, carsPerOrg = 2, roster = 5, label = "Night City Premier",
            band = { classes = { "Sport" }, prestigeMin = 5 },
            routes = { R.ukulele, R.cut, R.sewer, R.reverse },
            gen = { minM = 3000, maxM = 7000, checkpoints = 2, checkpointShare = 0.4, share = 0.5 } },
    }
    M.TIER_ORDER = { "street", "regional", "pro", "premier" }

    -- The daily rhythm (doc 44 §5.2), Eastern seconds-of-day. `untilSec` may pass 86400: the night runs on.
    local H = 3600
    -- L249 (owner: "yes widen the windows" -- a race always on, for a solo player at any hour): ~214 races a day.
    -- Street every 6 minutes from 18:00 to 06:00 (seven leagues, each every 42 min: ~120); regional four an hour
    -- from 06:00 to midnight (72); pro every 40 minutes from 08:00 to 22:00 (21); the premier at 15:00. Never more
    -- than 15 minutes without a race. (L236 was 20-04 / 12-20 / 10-18, ~129 a day.)
    M.RHYTHM = {
        street = { fromSec = 18 * H, untilSec = 30 * H, everySec = 42 * 60, staggerSec = 6 * 60 },
        regional = { fromSec = 6 * H, untilSec = 24 * H, everySec = 60 * 60, staggerSec = 15 * 60 },
        pro = { fromSec = 8 * H, untilSec = 22 * H, everySec = 2 * H, staggerSec = 40 * 60 },
        premier = { fromSec = 15 * H, untilSec = 15 * H + 1, everySec = 24 * H, staggerSec = 0 },
    }

    M.POINTS = { 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 }   -- SP championships.lua POINTS_TABLES.standard

    --- Series ids for a tier: "street_a", "street_b", "pro", ...
    function M.seriesIds(tier)
        local spec = M.TIERS[tier]
        if spec.divisions == 1 then return { tier } end
        local out = {}
        for d = 1, spec.divisions do out[d] = tier .. "_" .. string.char(96 + d) end
        return out
    end

    --- Every series as { id, tier, division, index } in a stable order.
    function M.allSeries()
        local out = {}
        for _, tier in ipairs(M.TIER_ORDER) do
            for d, id in ipairs(M.seriesIds(tier)) do out[#out + 1] = { id = id, tier = tier, division = d } end
        end
        return out
    end

    function M.tierOfSeries(seriesId)
        return (tostring(seriesId):match("^(%a+)"))
    end

    --- The races that START on Eastern day `dayIndex`'s rhythm (a street night that runs past midnight belongs
    --- to the evening it began). Returns { seriesId, tier, utc, sessionDay } sorted by utc.
    function M.dayRhythm(dayIndex, rhythm)
        rhythm = rhythm or M.RHYTHM
        local out = {}
        for _, s in ipairs(M.allSeries()) do
            local r = rhythm[s.tier]
            if r then
                local seen = {}
                local sod = r.fromSec + (s.division - 1) * (r.staggerSec or 0)
                while sod < r.untilSec do
                    local utc = Clock.utcAt(dayIndex, sod)
                    if not seen[utc] then
                        seen[utc] = true
                        out[#out + 1] = { seriesId = s.id, tier = s.tier, utc = utc, sessionDay = dayIndex }
                    end
                    sod = sod + r.everySec
                end
            end
        end
        table.sort(out, function(a, b) if a.utc ~= b.utc then return a.utc < b.utc end return a.seriesId < b.seriesId end)
        return out
    end

    --- All races starting in [fromUtc, toUtc), across the rhythm days that can contribute.
    function M.window(fromUtc, toUtc, rhythm)
        local first = Clock.eastern(fromUtc).dayIndex - 1
        local last = Clock.eastern(toUtc).dayIndex
        local out = {}
        for day = first, last do
            for _, r in ipairs(M.dayRhythm(day, rhythm)) do
                if r.utc >= fromUtc and r.utc < toUtc then out[#out + 1] = r end
            end
        end
        table.sort(out, function(a, b) if a.utc ~= b.utc then return a.utc < b.utc end return a.seriesId < b.seriesId end)
        return out
    end

    --- The stable race id for a series slot.
    function M.raceId(seriesId, utc) return "pr-" .. seriesId .. "-" .. tostring(math.floor(utc)) end

    --- The division letter of a series id ("street_c" -> 3; a single-division tier -> 1).
    function M.divisionOf(seriesId)
        local l = tostring(seriesId):match("_(%a)$")
        return l and (l:byte() - 96) or 1
    end

    --- The district a series races out of, or nil for the whole city.
    function M.regionOf(seriesId)
        local spec = M.TIERS[M.tierOfSeries(seriesId)]
        return spec and spec.regions and spec.regions[M.divisionOf(seriesId)] or nil
    end

    --- Temporary point-to-point-only schedule while checkpointed splines are unavailable (L253).
    --- Keep each tier's normal minimum/maximum distance filter and district start rule; generated routes need no named root.
    --- L296 (owner, 2026-10-02: "why arent there any ovals on the calendar? they should be semi regular"): the oval
    --- night is back. L253's temporary point-to-point-only schedule had dropped L236's oval branch, so `ovalShare` and
    --- the `ovalsScheduled` tunable (L254) did nothing. A share of each tier's slots races an authored roundabout --
    --- the league's own district's first, else any -- whenever `data.ovals.SCHEDULED` is on.
    function M.routeFor(seed, seriesId, utc)
        local tier = M.tierOfSeries(seriesId)
        local spec = M.TIERS[tier]
        local region = M.regionOf(seriesId)
        local k = math.floor(utc / 60)
        local ovals = C.get("data.ovals")
        if ovals.SCHEDULED and (spec.ovalShare or 0) > 0 and #ovals.LIST > 0
            and Hash.unit(seed, "route-oval", seriesId, k) < spec.ovalShare then
            local list = region and ovals.ids(region) or {}
            if #list == 0 then list = ovals.ids() end
            if #list > 0 then return list[1 + Hash.fnv1a32(Hash.key(seed, "oval", seriesId, k)) % #list] end
        end
        local opts = {}
        for key, value in pairs(spec.gen or {}) do opts[key] = value end
        opts.startRegion = region
        opts.checkpoints = 0
        opts.checkpointShare = 0
        return C.get("course.generator").pick(opts, seed, "paddock", seriesId, k)
    end
    --- Season and Cup for an instant: { seasonId, cup (1..13), cupId, startUtc, endUtc, cupStartUtc, cupEndUtc }.
    function M.cupOf(utc)
        local season = Seasons.atUtc(math.floor(utc))
        local week = math.floor((utc - season.startUtc) / (7 * 86400)) + 1
        if week > M.CUPS_PER_SEASON then week = M.CUPS_PER_SEASON end
        local cupStart = season.startUtc + (week - 1) * 7 * 86400
        local cupEnd = (week == M.CUPS_PER_SEASON) and season.endUtc or (cupStart + 7 * 86400)
        return { seasonId = season.id, cup = week, cupId = string.format("%s-C%02d", season.id, week),
            startUtc = season.startUtc, endUtc = season.endUtc, cupStartUtc = cupStart, cupEndUtc = cupEnd }
    end

    --- Paddock years since genesis: one per season (L224: NPCs age one "paddock year" per season, doc 44 §5.3).
    function M.paddockYear(genesisSeasonId, seasonId)
        local g, s = Seasons.parse(genesisSeasonId), Seasons.parse(seasonId)
        if not g or not s then return M.PADDOCK_EPOCH_YEAR end
        return M.PADDOCK_EPOCH_YEAR + (s.year - g.year) * 4 + (s.number - g.number)
    end

    function M.pointsFor(position, state)
        if state ~= "finished" then return 0 end
        return M.POINTS[position] or 0
    end

    --- Standings from result rows { entityId, position, state, points? }. Keyed by ID (FTB keyed by name and merged
    --- namesakes). Returns sorted { id, points, wins, podiums, starts, dnfs, best } with ties broken by wins, then
    --- podiums, then best finish, then id.
    function M.standings(rows, keyField)
        keyField = keyField or "entityId"
        local by, list = {}, {}
        for _, r in ipairs(rows or {}) do
            local id = r[keyField]
            if id ~= nil then
                local s = by[id]
                if not s then s = { id = id, points = 0, wins = 0, podiums = 0, starts = 0, dnfs = 0, best = 99 }; by[id] = s; list[#list + 1] = s end
                local pts = r.points or M.pointsFor(r.position, r.state)
                s.points = s.points + pts
                s.starts = s.starts + 1
                if r.state == "finished" then
                    if r.position == 1 then s.wins = s.wins + 1 end
                    if r.position <= 3 then s.podiums = s.podiums + 1 end
                    if r.position < s.best then s.best = r.position end
                else
                    s.dnfs = s.dnfs + 1
                end
            end
        end
        table.sort(list, function(a, b)
            if a.points ~= b.points then return a.points > b.points end
            if a.wins ~= b.wins then return a.wins > b.wins end
            if a.podiums ~= b.podiums then return a.podiums > b.podiums end
            if a.best ~= b.best then return a.best < b.best end
            return tostring(a.id) < tostring(b.id)
        end)
        for i, s in ipairs(list) do s.pos = i end
        return list
    end

    -- Moves between adjacent tiers at rollover: top N of the lower tier swap with the bottom N of the upper.
    M.MOVES = { { lower = "street", upper = "regional", n = 2 }, { lower = "regional", upper = "pro", n = 2 },
        { lower = "pro", upper = "premier", n = 1 } }

    --- The promotion/relegation plan from season org standings per tier ({ [tier] = sorted standings }).
    --- Returns { { orgId, from, to, kind = "promoted"|"relegated" } }. Street has no relegation: its bottom orgs
    --- face the money instead (`paddock.finance`).
    function M.rollover(orgStandingsByTier)
        local plan = {}
        for _, mv in ipairs(M.MOVES) do
            local low, up = orgStandingsByTier[mv.lower] or {}, orgStandingsByTier[mv.upper] or {}
            local n = math.min(mv.n, #low, #up)
            for i = 1, n do
                plan[#plan + 1] = { orgId = low[i].id, from = mv.lower, to = mv.upper, kind = "promoted" }
                plan[#plan + 1] = { orgId = up[#up - i + 1].id, from = mv.upper, to = mv.lower, kind = "relegated" }
            end
        end
        return plan
    end

    return M
end)
