-- ncm_paddock / server / views -- what the PADDOCK tab shows (doc 44 §14.2).
--
-- Every payload is built from whitelisted fields (`paddock.projection`) and passes `assertNoHidden` before it is
-- sent: a stat, a trait, a personality axis or a morale value can never reach a client. Aggregations run in SQL so
-- the metered VM stays cheap (KB-211). A race that is still `running` is never shown with a result (its outcome
-- exists, sealed, until the window closes).
PaddockViews = {}

local U = PaddockUtil
local P = NcmCore.get("paddock.projection")
local Tags = NcmCore.get("paddock.tags")
local World = NcmCore.get("paddock.world")
local Season = NcmCore.get("paddock.season")
local Contracts = NcmCore.get("paddock.contracts")
local Car = NcmCore.get("paddock.car")
local Clock = NcmCore.get("world.clock")

local function w() return PaddockStore.world end

local function driverTags(p)
    if not p then return {} end
    return Tags.labels(Tags.driver(p, p.evidence or {}, { age = World.age(w(), p) }))
end

local function orgTags(o)
    local owner = w().people[o.ownerId or ""]
    local e = o.evidence or {}
    e.seasonsActive, e.lowCashDays = o.seasonsActive, o.lowCashDays
    return Tags.labels(Tags.org(owner and owner.principal, e))
end
PaddockViews.driverTags, PaddockViews.orgTags = driverTags, orgTags

local function seriesList()
    local out = {}
    for _, s in ipairs(Season.allSeries()) do
        out[#out + 1] = { id = s.id, name = PaddockWorld.seriesName(s.id), tier = Season.TIERS[s.tier].label }
    end
    return out
end

-- ---------------------------------------------------------------------------------------------------------------

function PaddockViews.wire(_, args)
    local min = tonumber(args.all and 0 or PaddockSettings.get("wireMinProminence", 30)) or 30
    local rows = MySQL.query.await([[SELECT story_id, at, kind, headline, body, prominence FROM paddock_news
        WHERE server_id = ? AND prominence >= ? ORDER BY at DESC, prominence DESC LIMIT 60]], { U.sid(), min }) or {}
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = P.wireRow({ storyId = r.story_id, at = tonumber(r.at), kind = r.kind, headline = r.headline, body = r.body,
            prominence = tonumber(r.prominence) })
    end
    return { view = "wire", rows = out }
end

function PaddockViews.standings(_, args)
    local world = w()
    local seriesId = world.series[args.seriesId or ""] and args.seriesId or "premier"
    local cup = Season.cupOf(U.now())
    local scope = args.scope == "cup" and "cup" or "season"
    local kind = args.kind == "org" and "org" or "driver"
    local rows = PaddockLife.standings(kind, world.seasonId, seriesId, scope == "cup" and cup.cupId or "", 40)
    local out = {}
    for i, r in ipairs(rows) do
        if kind == "driver" then
            local p = world.people[r.id]
            out[i] = P.standingRow(r, p and p.display or "?", p and (p.orgId and PaddockWorld.orgName(p.orgId)
                or (p.leagueId and "Independent") or "free agent") or "?", driverTags(p))
        else
            local o = world.orgs[r.id]
            out[i] = P.standingRow(r, o and o.name or "?", nil, o and orgTags(o) or {})
            out[i].colour = o and o.colour
            out[i].human = o and o.humanManagerDriverId ~= nil or nil
        end
    end
    return { view = "standings", seriesId = seriesId, seriesName = PaddockWorld.seriesName(seriesId),
        tier = Season.TIERS[world.series[seriesId].tier].label, seasonId = world.seasonId, cupId = cup.cupId, cup = cup.cup,
        scope = scope, kind = kind, series = seriesList(), rows = out }
end

function PaddockViews.results(_, args)
    local sid = U.sid()
    local filter = w().series[args.seriesId or ""] and args.seriesId or nil
    local rows = MySQL.query.await(([[SELECT r.race_id, r.series_id, r.route_id, r.window_opens_at, r.weather, r.light, r.road_wetness,
            r.provenance, r.seed_commit, x.person_id AS winner, x.org_id AS winner_org
        FROM paddock_race r LEFT JOIN paddock_result x ON x.server_id = r.server_id AND x.race_id = r.race_id AND x.position = 1
        WHERE r.server_id = ? AND r.state = 'resolved' %s ORDER BY r.window_opens_at DESC LIMIT 40]]):format(filter and "AND r.series_id = ?" or ""),
        filter and { sid, filter } or { sid }) or {}
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = P.raceRow({ raceId = r.race_id, at = tonumber(r.window_opens_at), state = "resolved", weather = r.weather,
            light = r.light, roadWetness = tonumber(r.road_wetness), provenance = r.provenance, commit = r.seed_commit },
            PaddockWorld.routeName(r.route_id), PaddockWorld.seriesName(r.series_id), PaddockWorld.personName(r.winner),
            PaddockWorld.orgName(r.winner_org))
    end
    -- what races next (never results: these have not happened)
    local nextRaces = {}
    local t = U.now()
    local list = {}
    for _, race in pairs(PaddockRaces.byId) do
        if race.opensAt >= t - 300 and race.state ~= "resolved" and race.state ~= "void" and (not filter or race.seriesId == filter) then
            list[#list + 1] = race
        end
    end
    table.sort(list, function(a, b) return a.opensAt < b.opensAt end)
    for i = 1, math.min(6, #list) do
        local race = list[i]
        -- phase 5: a race can be declared live (run on the street) inside its window; show that, or its live state
        local live = PaddockLive.statusOf(race.raceId)
        nextRaces[i] = { raceId = race.raceId, at = race.opensAt, series = PaddockWorld.seriesName(race.seriesId),
            route = PaddockWorld.routeName(race.routeId), state = race.state == "running" and "on track" or (race.state == "priced" and "on the board" or "scheduled"),
            eastern = Clock.hhmm(race.opensAt),
            live = live and (live.state .. (live.verdict and (" · " .. live.verdict) or "")) or nil }
    end
    return { view = "results", seriesId = filter, series = seriesList(), next = nextRaces, rows = out }
end

function PaddockViews.box(_, args)
    local sid = U.sid()
    local race = MySQL.single.await("SELECT * FROM paddock_race WHERE server_id = ? AND race_id = ?", { sid, tostring(args.raceId or "") })
    if not race or race.state ~= "resolved" then return { view = "box", error = "not_resolved", rows = {} } end
    local rows = MySQL.query.await([[SELECT person_id, org_id, position, grid, state, finish_ms, gap_ms, points, dnf_reason
        FROM paddock_result WHERE server_id = ? AND race_id = ? ORDER BY position]], { sid, race.race_id }) or {}
    local out = {}
    local detail = U.decode(race.detail_json) or {}
    local quali = (type(detail.frozen) == "table" and type(detail.frozen.quali) == "table") and detail.frozen.quali or {}
    for i, r in ipairs(rows) do
        out[i] = P.boxRow({ position = tonumber(r.position), grid = tonumber(r.grid), personId = r.person_id, state = r.state,
            finishMs = tonumber(r.finish_ms), gapMs = tonumber(r.gap_ms), points = tonumber(r.points), dnfReason = r.dnf_reason },
            PaddockWorld.personName(r.person_id), PaddockWorld.orgName(r.org_id), tonumber(quali[r.person_id]))
    end
    return { view = "box", raceId = race.race_id, series = PaddockWorld.seriesName(race.series_id),
        route = PaddockWorld.routeName(race.route_id), at = tonumber(race.window_opens_at), weather = race.weather,
        light = race.light, wet = tonumber(race.road_wetness), provenance = race.provenance, backend = race.backend,
        commit = race.seed_commit, rows = out }
end

function PaddockViews.pace()
    local sid = U.sid()
    local npc = MySQL.query.await([[SELECT DISTINCT r.route_id, r.tier,
            MEDIAN(x.finish_ms) OVER (PARTITION BY r.route_id, r.tier) AS median_ms,
            COUNT(*) OVER (PARTITION BY r.route_id, r.tier) AS n
        FROM paddock_result x JOIN paddock_race r ON r.server_id = x.server_id AND r.race_id = x.race_id
        WHERE x.server_id = ? AND x.state = 'finished' AND r.state = 'resolved' AND r.window_opens_at > ?
          AND r.road_wetness < 0.1 AND r.light <> 'night']], { sid, U.now() - 14 * 86400 }) or {}
    local out = {}
    for _, r in ipairs(npc) do
        local human = PaddockCalibration.buckets[r.route_id .. "|" .. r.tier .. "|dry:day"]
        out[#out + 1] = { route = PaddockWorld.routeName(r.route_id), tier = Season.TIERS[r.tier] and Season.TIERS[r.tier].label or r.tier,
            npcSec = P.secs(tonumber(r.median_ms)), npcRaces = tonumber(r.n),
            humanSec = human and human.median and P.secs(human.median) or nil, humanRuns = human and human.n or 0,
            humanDrivers = human and human.drivers or 0 }
    end
    table.sort(out, function(a, b) if a.route ~= b.route then return a.route < b.route end return a.tier < b.tier end)
    return { view = "pace", note = "Dry, daylight finishes over the last 14 days.", minN = PaddockSettings.get("calibMinN", 8),
        minDrivers = PaddockSettings.get("calibMinDrivers", 3), rows = out }
end

function PaddockViews.directory()
    local world = w()
    local out = {}
    for _, tier in ipairs({ "premier", "pro", "regional", "street" }) do
        for _, oid in ipairs(world.orgOrder) do
            local o = world.orgs[oid]
            if o.tier == tier and o.lifecycle == "active" then
                local row = P.directoryRow("org", "npc", o.id, o.name, Season.TIERS[tier].label, nil, PaddockWorld.seriesName(o.seriesId), orgTags(o))
                row.colour, row.human = o.colour, o.humanManagerDriverId ~= nil or nil
                local g = PaddockGarages.describe(o)
                if g then row.garage = { label = g.label, hours = g.hours, here = g.here or nil } end
                out[#out + 1] = row
            end
        end
    end
    -- human sanctioned organizations (doc 14), read-only
    local orgs = MySQL.query.await([[SELECT o.organization_id, b.name FROM organization o
        JOIN organization_branding b ON b.organization_id = o.organization_id AND b.effective_to IS NULL
        WHERE o.server_id = ? AND o.lifecycle_state = 'active' ORDER BY b.name LIMIT 60]], { U.sid() }) or {}
    for _, r in ipairs(orgs) do
        out[#out + 1] = P.directoryRow("org", "sanctioned", r.organization_id, r.name, "Sanctioned", nil, nil, {})
    end
    return { view = "directory", rows = out }
end

function PaddockViews.profile(_, args)
    local world = w()
    if args.kind == "org" then
        local o = world.orgs[args.id or ""]
        if not o then return { view = "profile", error = "unknown", rows = {} } end
        local sponsors = {}
        for _, sid in ipairs(o.sponsorIds or {}) do if world.sponsors[sid] then sponsors[#sponsors + 1] = world.sponsors[sid].name end end
        local head = P.orgProfile(o, { seriesName = PaddockWorld.seriesName(o.seriesId), ownerName = PaddockWorld.personName(o.ownerId),
            managerName = o.managerId and PaddockWorld.personName(o.managerId) or (o.humanManagerDriverId and "a human manager" or nil),
            tags = orgTags(o), sponsors = sponsors })
        head.garage = PaddockGarages.describe(o)         -- phase 4: where to find them, and whether they're in now
        local rows = {}
        for _, p in ipairs(World.members(world, o.id)) do
            if p.state == "active" then
                rows[#rows + 1] = { t = "person", id = p.id, name = p.display, role = p.role, seat = p.seat,
                    tags = p.role == "driver" and driverTags(p) or nil, ageBand = P.ageBand(World.age(world, p)) }
            end
        end
        return { view = "profile", kind = "org", profile = head, rows = rows }
    end
    local p = world.people[args.id or ""]
    if not p then return { view = "profile", error = "unknown", rows = {} } end
    local e = p.evidence or {}
    local head = P.personProfile(p, { orgName = p.orgId and PaddockWorld.orgName(p.orgId) or (p.state == "free_agent" and "free agent")
            or (p.leagueId and "Independent") or nil,
        regionLabel = P.REGION_LABELS[p.region], ageBand = P.ageBand(World.age(world, p)),
        tags = p.role == "driver" and driverTags(p) or {}, wins = e.wins or 0, starts = e.starts or 0, podiums = e.podiums or 0 })
    local rows = {}
    for _, r in ipairs(MySQL.query.await([[SELECT x.race_id, x.position, x.state, x.grid, r.series_id, r.route_id, r.window_opens_at
        FROM paddock_result x JOIN paddock_race r ON r.server_id = x.server_id AND r.race_id = x.race_id
        WHERE x.server_id = ? AND x.person_id = ? AND r.state = 'resolved' ORDER BY x.at DESC LIMIT 15]], { U.sid(), p.id }) or {}) do
        rows[#rows + 1] = { t = "result", raceId = r.race_id, pos = tonumber(r.position), grid = tonumber(r.grid), state = r.state,
            series = PaddockWorld.seriesName(r.series_id), route = PaddockWorld.routeName(r.route_id), at = tonumber(r.window_opens_at) }
    end
    return { view = "profile", kind = "person", profile = head, rows = rows }
end

local function lineLabel(l)
    local a = PaddockWorld.personName(l.subject_a)
    if l.market == "win" then return a .. " to win" end
    if l.market == "podium" then return a .. " top three" end
    return a .. " over " .. PaddockWorld.personName(l.subject_b)
end

function PaddockViews.board(pid)
    local d = PaddockPlayers.driver(pid)
    local t = U.now()
    local races = {}
    for _, race in pairs(PaddockRaces.byId) do
        if race.state == "priced" and race.opensAt > t then races[#races + 1] = race end
    end
    table.sort(races, function(a, b) return a.opensAt < b.opensAt end)
    local head, rows = {}, {}
    for i = 1, math.min(3, #races) do
        local race = races[i]
        local cond = PaddockWorld.conditionsAt(race.opensAt)
        head[#head + 1] = { raceId = race.raceId, series = PaddockWorld.seriesName(race.seriesId), route = PaddockWorld.routeName(race.routeId),
            opensAt = race.opensAt, eastern = Clock.hhmm(race.opensAt), weather = cond.weather, light = cond.light }
        for _, l in ipairs(MySQL.query.await([[SELECT * FROM paddock_line WHERE server_id = ? AND race_id = ? ORDER BY market, price]],
            { U.sid(), race.raceId }) or {}) do
            rows[#rows + 1] = { t = "line", raceId = race.raceId, lineId = l.line_id, version = tonumber(l.version), market = l.market,
                label = lineLabel(l), price = (tonumber(l.refused) ~= 1) and tonumber(l.price) or nil,
                refused = tonumber(l.refused) == 1 or nil, open = l.state == "open" or nil }
        end
    end
    local knows, balance, staked = false, 0, 0
    if d then
        knows = PaddockBillie.knows(d.ncmDriverId)
        balance = PaddockWallet.balance(d.ncmDriverId)
        staked = PaddockBillie.stakedToday(d.ncmDriverId, t)
        for _, s in ipairs(MySQL.query.await([[SELECT * FROM paddock_slip WHERE server_id = ? AND ncm_driver_id = ?
            ORDER BY placed_at DESC LIMIT 12]], { U.sid(), d.ncmDriverId }) or {}) do
            rows[#rows + 1] = { t = "slip", slipId = s.slip_id, label = lineLabel(s), stake = tonumber(s.stake), price = tonumber(s.price),
                returns = tonumber(s.potential), state = s.state, payout = tonumber(s.payout), at = tonumber(s.placed_at) }
        end
    end
    local voice = PaddockBillie.VOICE[1 + (math.floor(t / 600) % #PaddockBillie.VOICE)]
    return { view = "board", races = head, knows = knows, balance = balance, stakedToday = staked, caps = PaddockBillie.caps(),
        voice = voice, refusal = PaddockBillie.REFUSAL, rows = rows }
end

function PaddockViews.myorg(pid)
    local d = PaddockPlayers.driver(pid)
    if not d then return { view = "myorg", error = "no_driver", rows = {} } end
    local world = w()
    local org = PaddockWorld.orgManagedBy(d.ncmDriverId)
    local rows = {}
    if not org then
        local aff = PaddockManager.affiliationOf(d.ncmDriverId)
        local mgr = MySQL.single.await("SELECT * FROM paddock_manager WHERE server_id = ? AND ncm_driver_id = ?", { U.sid(), d.ncmDriverId })
        for _, o in ipairs(MySQL.query.await([[SELECT * FROM paddock_manager_offer WHERE server_id = ? AND ncm_driver_id = ? AND state = 'open'
            AND expires_at > ? ORDER BY created_at DESC LIMIT 5]], { U.sid(), d.ncmDriverId, U.now() }) or {}) do
            local oo = world.orgs[o.org_id]
            rows[#rows + 1] = { t = "offer", offerId = o.offer_id, org = oo and oo.name, tier = oo and Season.TIERS[oo.tier].label,
                from = PaddockWorld.personName(o.from_person_id), expiresAt = tonumber(o.expires_at) }
        end
        return { view = "myorg", manager = false, affiliated = aff ~= nil, affiliation = aff and aff.circuit .. ":" .. aff.role or nil,
            fee = PaddockSettings.get("managerFoundFee", 5000), grant = PaddockSettings.get("managerFoundGrant", 15000),
            cooldownUntil = mgr and tonumber(mgr.cooldown_until_season) or nil, seasonOrdinal = world.seasonOrdinal,
            balance = PaddockWallet.balance(d.ncmDriverId), rows = rows }
    end
    for _, p in ipairs(World.drivers(world, org.id)) do
        rows[#rows + 1] = { t = "driver", id = p.id, name = p.display, seat = p.seat, tags = driverTags(p), wage = p.wage,
            contractEnds = p.contractEnds, ageBand = P.ageBand(World.age(world, p)), region = P.REGION_LABELS[p.region],
            starts = (p.evidence or {}).starts or 0, wins = (p.evidence or {}).wins or 0 }
    end
    local fas = World.freeAgents(world)
    table.sort(fas, function(a, b) return a.id < b.id end)
    for i = 1, math.min(25, #fas) do
        local p = fas[i]
        rows[#rows + 1] = { t = "fa", id = p.id, name = p.display, tags = driverTags(p), ask = Contracts.askingWage(p, org.tier),
            ageBand = P.ageBand(World.age(world, p)), region = P.REGION_LABELS[p.region], starts = (p.evidence or {}).starts or 0 }
    end
    local offered = 0
    for _, sid in ipairs(world.sponsorOrder) do
        local s = world.sponsors[sid]
        if not s.orgId and offered < 6 then
            offered = offered + 1
            rows[#rows + 1] = { t = "sponsor", id = s.id, name = s.name, industry = s.industry, perDay = s.perDay }
        end
    end
    for _, b in ipairs(MySQL.query.await([[SELECT kind, amount, at FROM paddock_treasury WHERE server_id = ? AND org_id = ?
        ORDER BY entry_id DESC LIMIT 15]], { U.sid(), org.id }) or {}) do
        rows[#rows + 1] = { t = "book", kind = b.kind, amount = tonumber(b.amount), at = tonumber(b.at) }
    end
    local car = {}
    for _, a in ipairs(Car.AREAS) do car[#car + 1] = { area = a, level = org.car[a], next = Car.stepCost(org.car[a] or 1) } end
    local pending = {}
    for i, pl in ipairs(org.pending or {}) do
        pending[i] = { kind = pl.kind, driver = pl.driverId and PaddockWorld.personName(pl.driverId), seat = pl.seat }
    end
    local cup = Season.cupOf(U.now())
    local withdrawn = -(tonumber(MySQL.scalar.await([[SELECT COALESCE(SUM(amount),0) FROM paddock_treasury WHERE server_id = ? AND org_id = ?
        AND kind = 'withdrawal' AND at >= ?]], { U.sid(), org.id, cup.cupStartUtc })) or 0)
    return { view = "myorg", manager = true, org = P.orgProfile(org, { seriesName = PaddockWorld.seriesName(org.seriesId),
        ownerName = PaddockWorld.personName(org.ownerId), tags = orgTags(org) }), treasury = math.floor(org.cash or 0),
        car = car, pending = pending, cupEndsAt = cup.cupEndUtc, withdrawnThisWeek = withdrawn,
        weeklyCap = PaddockSettings.get("managerWithdrawWeeklyCap", 2000), tax = PaddockSettings.get("managerWithdrawTax", 0.30),
        engineer = PaddockWorld.personName(org.engineerId), strategist = PaddockWorld.personName(org.strategistId),
        balance = PaddockWallet.balance(d.ncmDriverId), rows = rows }
end

--- LIVE: every race on track now, and for the one picked, a track strip and a timing tower. A simulated race reads the
--- continuous model (paddock.racestate); a street race reads its cars' real positions, projected onto the same line.
--- Betting closed when the window opened, so live order is coverage, not a leak.
function PaddockViews.live(_, args)
    local t = U.now()
    local Racestate = NcmCore.get("paddock.racestate")
    local list = {}
    for _, race in pairs(PaddockRaces.byId) do
        if race.state == "running" and race.model and t >= race.opensAt then list[#list + 1] = race end
    end
    table.sort(list, function(a, b) return a.opensAt < b.opensAt end)
    local races = {}
    for i, race in ipairs(list) do
        local lr = PaddockLive.byRace[race.raceId]
        races[i] = { raceId = race.raceId, series = PaddockWorld.seriesName(race.seriesId), route = PaddockWorld.routeName(race.routeId),
            eastern = Clock.hhmm(race.opensAt), street = (lr and lr.state == "running") or nil }
    end
    local pick
    for _, race in ipairs(list) do if race.raceId == args.raceId then pick = race end end
    pick = pick or list[1]
    if not pick then return { view = "live", races = races, rows = {} } end
    local model = pick.model
    local route = PaddockWorld.route(pick.routeId)
    local lr = PaddockLive.byRace[pick.raceId]
    local street = lr and lr.state == "running" and lr.goMs
    local tMs = street and ((Open77.time.unix() or 0) * 1000 - lr.goMs) or (t - pick.modelGoAt) * 1000
    local rows = {}
    if street then
        -- real positions: where each car is on the line, and the gates it has timed
        local w = PaddockStore.world
        -- each gate's distance along the line, in order: a car is between the last gate it timed and the next, which
        -- is what keeps it on its own lap of an oval (L236, KB-223)
        if not lr.gateD and lr.gates then
            lr.gateD = { 0 }
            for i = 2, #lr.gates do lr.gateD[i] = Racestate.project(model, lr.gates[i], lr.gateD[i - 1]) end
        end
        for _, c in ipairs(lr.cars) do
            local okP, pos = pcall(Open77.vehicles.getPosition, c.vehicleId)
            local tc = lr.timing and lr.timing.cars[c.personId]
            local gd, nx = lr.gateD, tc and tc.next or 2
            local lo = gd and gd[math.max(1, nx - 1)] and (gd[math.max(1, nx - 1)] - 25) or nil
            local hi = gd and (gd[nx] and (gd[nx] + 25) or model.lengthM) or nil
            local d = (okP and type(pos) == "table") and Racestate.project(model, pos, lo, hi) or (lo and math.max(0, lo + 25)) or 0
            local state = (tc and tc.done) and "finished" or (lr.out[c.personId] and "out" or "racing")
            -- The timing gate sequence is the race authority for ovals. Distance projection can choose the wrong
            -- copy of the repeated ring (especially near the start/finish line), so publish lap from crossed gates.
            local ovalLap
            if route and route.oval and tc then
                local gatesPerLap = #route.oval.loop
                if gatesPerLap > 0 then
                    ovalLap = math.min(route.oval.laps, math.floor(math.max(0, (tc.next or 2) - 2) / gatesPerLap) + 1)
                    if tc.done then ovalLap = route.oval.laps end
                end
            end
            rows[#rows + 1] = { id = c.personId, d = (tc and tc.done) and model.lengthM or d, state = state, finishMs = tc and tc.finishMs,
                lap = ovalLap,
                vid = c.vehicleId, physical = true }
        end
        table.sort(rows, function(a, b)
            if (a.state == "finished") ~= (b.state == "finished") then return a.state == "finished" end
            if a.state == "finished" then return (a.finishMs or 0) < (b.finishMs or 0) end
            return a.d > b.d
        end)
        -- gaps on the street (L235): finishers by their timed finish, the rest by distance behind the leader at the
        -- sim leader's average speed -- an estimate, and labelled as a time like any other interval
        local leadMps = (lr.simLeaderMs and lr.simLeaderMs > 0) and model.lengthM / (lr.simLeaderMs / 1000) or 30
        local first = rows[1]
        for i, r in ipairs(rows) do
            r.pos = i
            if r.state == "finished" and first and first.state == "finished" then
                r.gapMs = (r.finishMs or 0) - (first.finishMs or 0)
            elseif r.state == "racing" and first then
                r.gapMs = math.max(0, math.floor((((first.state == "finished") and model.lengthM or first.d) - r.d) / leadMps * 1000))
            end
        end
    else
        rows = Racestate.standings(model, tMs)
        -- a car physically in a player's bubble right now: show where it really is
        local bub = PaddockBubble and PaddockBubble.byRace[pick.raceId]
        if bub then
            for _, r in ipairs(rows) do
                local car = bub.cars[r.id]
                if car then
                    local okP, pos = pcall(Open77.vehicles.getPosition, car.vid)
                    -- near its last known distance, so a line that passes the same place twice keeps the right pass
                    local near = car.lastD or r.d or 0
                    if okP and type(pos) == "table" then r.d = Racestate.project(model, pos, near - 300, near + 300); r.physical = true; r.vid = car.vid end
                end
            end
        end
    end
    -- L250: a mixed grid's humans, where their players are on the line, in the same order
    if PaddockHumans and PaddockHumans.mixed(pick) then
        for _, h in ipairs(PaddockHumans.liveRows(pick, model, function(pos, lo, hi) return Racestate.project(model, pos, lo, hi) end)) do rows[#rows + 1] = h end
        table.sort(rows, function(a, b)
            if (a.state == "finished") ~= (b.state == "finished") then return a.state == "finished" end
            if a.state == "finished" then return (a.finishMs or 0) < (b.finishMs or 0) end
            return (a.d or 0) > (b.d or 0)
        end)
        for i, r in ipairs(rows) do r.pos = i end
    end
    local out = {}
    for i, r in ipairs(rows) do
        local p = PaddockStore.world.people[r.id]
        local o = PaddockStore.world.orgs[(p and p.orgId) or r.orgId or ""]
        local ovalLaps = route and route.oval and route.oval.laps
        local lap = r.lap
        if ovalLaps and not lap then lap = math.min(ovalLaps, math.floor((r.d or 0) / math.max(1, model.lengthM / ovalLaps)) + 1) end
        out[i] = { pos = r.pos, id = r.id, name = p and p.display or r.name or "?", org = o and o.name or (r.human and "Independent" or nil), colour = o and o.colour,
            pct = math.floor(math.min(1, math.max(0, (r.d or 0) / math.max(1, model.lengthM))) * 1000) / 10,
            lap = lap,
            gap = r.state == "finished" and (r.gapMs and (r.gapMs == 0 and "winner" or ("+%.1fs"):format(r.gapMs / 1000)) or "finished")
                or (r.state == "out" and "out") or (r.gapMs and (r.gapMs == 0 and "leader" or ("+%.1fs"):format(r.gapMs / 1000)) or ""),
            state = r.state, physical = r.physical or nil, vid = r.vid, human = r.human or nil,
            quali = pick.frozen and pick.frozen.quali and P.secs(tonumber(pick.frozen.quali[r.id])) or nil }
    end
    return { view = "live", races = races, raceId = pick.raceId, series = PaddockWorld.seriesName(pick.seriesId),
        route = PaddockWorld.routeName(pick.routeId), elapsed = math.max(0, math.floor(tMs / 1000)), lengthM = math.floor(model.lengthM),
        street = street and true or nil, rows = out,
        grid = P.qualiSheet(pick.frozen, function(id) local p = PaddockStore.world.people[id]; return p and p.display or "?" end) }
end

--- TODAY: the landing page. What races next (with the live button), what just finished, the top headlines, and
--- where the player stands (Billie, their paper, their team, a live race they declared). One round trip.
function PaddockViews.today(pid)
    local t = U.now()
    local res = PaddockViews.results(pid, {})
    local wire = PaddockViews.wire(pid, {})
    local results, news = {}, {}
    for i = 1, math.min(8, #res.rows) do results[i] = res.rows[i] end
    for i = 1, math.min(6, #wire.rows) do news[i] = wire.rows[i] end
    local me = {}
    local d = PaddockPlayers.driver(pid)
    if d then
        me.knowsBillie = PaddockBillie.knows(d.ncmDriverId) or nil
        me.balance = PaddockWallet.balance(d.ncmDriverId)
        me.openSlips = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM paddock_slip WHERE server_id = ? AND ncm_driver_id = ?
            AND state = 'open']], { U.sid(), d.ncmDriverId })) or 0
        local org = PaddockWorld.orgManagedBy(d.ncmDriverId)
        if org then me.team, me.teamTier = org.name, Season.TIERS[org.tier].label end
        for _, lr in pairs(PaddockLive.byRace) do
            if lr.pid == pid and PaddockLive.holds(lr.raceId) then
                local race = PaddockRaces.byId[lr.raceId]
                me.live = { state = lr.state, route = race and PaddockWorld.routeName(race.routeId), at = race and Clock.hhmm(race.opensAt) }
                break
            end
        end
    end
    return { view = "today", next = res.next, results = results, me = me, rows = news }
end

-- What is on track now, by the daily rhythm (doc 44 §5.2), for the header.
local function phaseNow(t)
    local sod = Clock.eastern(t).secondsOfDay
    local on = {}
    for _, tier in ipairs(Season.TIER_ORDER) do
        local r = Season.RHYTHM[tier]
        local inWindow = (sod >= r.fromSec and sod < r.untilSec) or (sod + 86400 >= r.fromSec and sod + 86400 < r.untilSec)
        if tier == "premier" then inWindow = sod >= r.fromSec - 1800 and sod < r.fromSec + 1800 end
        if inWindow then on[#on + 1] = Season.TIERS[tier].label end
    end
    if #on == 0 then return "Quiet hours" end
    return table.concat(on, " · ") .. " racing"
end


--- THE EXCHANGE (L249 step 5): the open board, your posts with their bids, your bids, and your stored parts (what you
--- can post or offer). Names, never ids, for who posted; no hidden fields.
function PaddockViews.exchange(pid)
    local EX = NcmCore.get("economy.exchange_posts")
    local d = PaddockPlayers.driver(pid)
    local me = d and EX.principal("driver", d.ncmDriverId) or nil
    local rows = {}
    local posts = MySQL.query.await([[SELECT * FROM exchange_post WHERE server_id = ? AND state = 'open' ORDER BY created_at DESC LIMIT 60]], { U.sid() }) or {}
    for _, r in ipairs(posts) do
        local key = EX.principal(r.principal_kind, r.principal_id)
        local part = r.asset_id and PaddockExchange.part(r.asset_id) or nil
        local bids = PaddockExchange.bidsOn(r.post_id)
        local row = { t = "post", id = r.post_id, kind = r.kind, by = PaddockExchange.nameOf(key),
            who = r.principal_kind == "org" and "team" or (r.principal_kind == "person" and "racer" or "driver"),
            item = part and part.name or nil, family = part and part.family or r.want_family, tier = part and part.tier or r.want_tier,
            cash = tonumber(r.cash) or 0, revision = tonumber(r.revision) or 1, expiresAt = tonumber(r.expires_at) or 0,
            bids = #bids, mine = (key == me) or nil, note = r.note }
        if key == me then
            local list = {}
            for _, b in ipairs(bids) do
                local bp = b.assetId and PaddockExchange.part(b.assetId) or nil
                list[#list + 1] = { id = b.bidId, by = PaddockExchange.nameOf(b.principal), cash = b.cash, item = bp and bp.name or nil }
            end
            row.offers = list
        end
        rows[#rows + 1] = row
    end
    if me then
        for _, r in ipairs(MySQL.query.await([[SELECT b.*, p.kind AS post_kind FROM exchange_bid b JOIN exchange_post p ON p.post_id = b.post_id
            WHERE b.server_id = ? AND b.principal_kind = 'driver' AND b.principal_id = ? AND b.state = 'open' ORDER BY b.created_at DESC LIMIT 20]],
            { U.sid(), d.ncmDriverId }) or {}) do
            rows[#rows + 1] = { t = "mybid", id = r.bid_id, postId = r.post_id, cash = tonumber(r.cash) or 0, expiresAt = tonumber(r.expires_at) or 0 }
        end
        for _, r in ipairs(MySQL.query.await([[SELECT a.asset_id, d.family, d.tier, d.code, d.display_manufacturer, d.price FROM component_asset a
            JOIN component_design d ON d.design_id = a.design_id LEFT JOIN exchange_reservation x ON x.asset_id = a.asset_id
            WHERE a.server_id = ? AND a.ncm_driver_id = ? AND a.location_kind = 'storage' AND a.machine_asset_id IS NULL AND x.asset_id IS NULL
            ORDER BY d.family LIMIT 40]], { U.sid(), d.ncmDriverId }) or {}) do
            rows[#rows + 1] = { t = "part", id = r.asset_id, item = ("%s %s"):format(r.display_manufacturer or "", r.code or ""),
                family = r.family, tier = r.tier, list = tonumber(r.price) or 0 }
        end
    end
    return { view = "exchange", rows = rows, balance = d and PaddockWallet.balance(d.ncmDriverId) or 0, signedIn = me ~= nil,
        families = NcmCore.get("parts.catalogue").FAMILIES, tiers = { "street", "sport", "premium" } }
end

PaddockViews.BUILDERS = { today = PaddockViews.today, live = PaddockViews.live, wire = PaddockViews.wire, standings = PaddockViews.standings, results = PaddockViews.results,
    box = PaddockViews.box, pace = PaddockViews.pace, directory = PaddockViews.directory, profile = PaddockViews.profile,
    board = PaddockViews.board, myorg = PaddockViews.myorg, exchange = PaddockViews.exchange }

--- Build and send one view to one player.
function PaddockViews.send(pid, req)
    req = type(req) == "table" and req or {}
    local build = PaddockViews.BUILDERS[tostring(req.view or "today")]
    if not build then return end
    if not PaddockWorld.ready then
        PaddockStream.send(pid, "ncm:paddock", { view = req.view, error = "warming_up", rows = {} }, "rows")
        return
    end
    local ok, payload = pcall(build, pid, req)
    if not ok then
        print("[ncm_paddock/views] " .. tostring(req.view) .. " FAILED: " .. tostring(payload))
        payload = { view = req.view, error = "failed", rows = {} }
    end
    if type(payload) == "table" then
        local t = U.now()
        local world = w()
        payload.meta = { eastern = Clock.hhmm(t), phase = phaseNow(t), seasonId = world and world.seasonId, cup = Season.cupOf(t).cup }
    end
    local clean, why = pcall(P.assertNoHidden, payload)
    if not clean then
        print("[ncm_paddock/views] REFUSED " .. tostring(req.view) .. ": " .. tostring(why))
        payload = { view = req.view, error = "refused", rows = {} }
    end
    PaddockStream.send(pid, "ncm:paddock", payload, "rows")
end
