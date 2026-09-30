-- ncm_paddock / server / races -- the life of one Paddock race (doc 44 §6, §12).
--
--   materialise  (horizon ahead)  row written with a SECRET seed and its public commitment
--   freeze       (T-15, pricing)  the field and grid are fixed; later roster moves do not touch this race
--   run          (window opens)   the sim runs; results are stored but the race is `running` and NO view shows them
--   resolve      (window closes)  results become public: points, purse, morale, evidence, tape, WIRE, slips settle
--
-- The result exists before anyone can see it and is fixed by a seed committed before the window opened, so a
-- result cannot be chosen after the fact and cannot leak before the close (tested). Provenance is `simulated`
-- (L222) unless a declared live run (live.lua, phase 5) is corroborated before the close; then `physical`.
PaddockRaces = { byId = {} }

local U = PaddockUtil
local log = U.logger("races")
local Hash = NcmCore.get("vocabulary.hash")
local World = NcmCore.get("paddock.world")
local Season = NcmCore.get("paddock.season")
local Sim = NcmCore.get("paddock.sim")
local Car = NcmCore.get("paddock.car")
local Finance = NcmCore.get("paddock.finance")
local Progression = NcmCore.get("paddock.progression")
local Tape = NcmCore.get("paddock.tape")

local function num(v) return tonumber(v) end

local function rowToRace(r)
    local detail = U.decode(r.detail_json) or {}
    return {
        raceId = r.race_id, seriesId = r.series_id, tier = r.tier, seasonId = r.season_id, cupId = r.cup_id,
        routeId = r.route_id, opensAt = num(r.window_opens_at), closesAt = num(r.window_closes_at), state = r.state,
        seed = num(r.seed), commit = r.seed_commit, weather = r.weather, roadWetness = num(r.road_wetness),
        light = r.light, baseSec = num(r.base_sec), baseSource = r.base_source, frozen = detail.frozen,
        provenance = r.provenance,
    }
end

--- Load recent and upcoming races into memory (boot).
function PaddockRaces.load()
    local t = U.now()
    local rows = MySQL.query.await([[SELECT * FROM paddock_race WHERE server_id = ? AND window_opens_at >= ?
        AND state IN ('scheduled','priced','running') ORDER BY window_opens_at]], { U.sid(), t - 6 * 3600 }) or {}
    for _, r in ipairs(rows) do PaddockRaces.byId[r.race_id] = rowToRace(r) end
    log("loaded %d open races", #rows)
end

--- Write rows for every race in the horizon that does not exist yet.
function PaddockRaces.materialise(t)
    local w = PaddockStore.world
    local horizon = PaddockSettings.get("horizonMinutes", 120) * 60
    local st = {}
    for _, slot in ipairs(Season.window(t, t + horizon)) do
        local id = Season.raceId(slot.seriesId, slot.utc)
        if not PaddockRaces.byId[id] then
            local cup = Season.cupOf(slot.utc)
            local seed = math.random(1, 2147483646)
            local race = { raceId = id, seriesId = slot.seriesId, tier = slot.tier, seasonId = cup.seasonId,
                cupId = cup.cupId, routeId = Season.routeFor(w.seed, slot.seriesId, slot.utc), opensAt = slot.utc,
                state = "scheduled", seed = seed, commit = Hash.commit(seed, id), provenance = "simulated" }
            PaddockRaces.byId[id] = race
            st[#st + 1] = { query = [[INSERT IGNORE INTO paddock_race (server_id, race_id, series_id, tier, season_id, cup_id,
                route_id, window_opens_at, state, seed, seed_commit) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'scheduled', ?, ?)]],
                values = { U.sid(), id, race.seriesId, race.tier, race.seasonId, race.cupId, race.routeId, race.opensAt,
                    seed, race.commit } }
        end
    end
    if #st > 0 then
        local ok, err = U.transact(st)
        if not ok then log("materialise FAILED: %s", tostring(err)) end
    end
    return #st
end

--- The entrant list as the sim wants it, in GRID order.
function PaddockRaces.buildField(race)
    local w = PaddockStore.world
    local field = {}
    local ids = race.frozen and race.frozen.grid or nil
    local list
    if ids then
        list = {}
        for _, pid in ipairs(ids) do
            local p = w.people[pid]
            -- the org as it was when the field froze: a Cup-boundary move after pricing does not reach this race
            if p then list[#list + 1] = { driver = p, org = w.orgs[race.frozen.orgOf and race.frozen.orgOf[pid] or ""] or w.orgs[p.orgId or ""] } end
        end
    else
        list = World.field(w, race.seriesId)
    end
    local n = #list
    for _, e in ipairs(list) do
        local org = e.org or {}
        field[#field + 1] = { id = e.driver.id, orgId = org.id or (race.frozen and race.frozen.orgOf and race.frozen.orgOf[e.driver.id]),
            attrs = e.driver.attrs, carPerf = Car.performance(org.car), morale = e.driver.morale,
            form = Progression.form((e.driver.evidence or {}).recent or {}, n),
            humanManaged = org.humanManagerDriverId ~= nil }
    end
    if not ids then
        field = Sim.qualify(field, Hash.stream(race.seed, "quali", race.raceId))
    end
    return field
end

--- Fix the field and grid (pricing time, or run time when Billie is off).
function PaddockRaces.freeze(race)
    if race.frozen then return race.frozen end
    local field = PaddockRaces.buildField(race)
    local grid, orgOf = {}, {}
    for i, e in ipairs(field) do grid[i] = e.id; orgOf[e.id] = e.orgId end
    race.frozen = { grid = grid, orgOf = orgOf }
    pcall(MySQL.update.await, "UPDATE paddock_race SET detail_json = ? WHERE server_id = ? AND race_id = ?",
        { U.encode({ frozen = race.frozen }), U.sid(), race.raceId })
    return race.frozen
end

--- The conditions and base pace for a race.
function PaddockRaces.setup(race)
    local cond = PaddockWorld.conditionsAt(race.opensAt)
    local route = PaddockWorld.route(race.routeId) or { routeId = race.routeId, distanceM = 3000 }
    local base, source = PaddockCalibration.baseFor(PaddockStore.world.seed, route, race.tier, cond)
    return cond, route, base, source
end

--- Run the sim at the window's opening. Results are stored; the race stays `running` (hidden) until it closes.
function PaddockRaces.run(race, t)
    PaddockRaces.freeze(race)
    local field = PaddockRaces.buildField(race)
    if #field == 0 then
        race.state = "void"
        pcall(MySQL.update.await, "UPDATE paddock_race SET state = 'void' WHERE server_id = ? AND race_id = ?", { U.sid(), race.raceId })
        PaddockBillie.voidRace(race)
        return
    end
    local cond, route, base, source = PaddockRaces.setup(race)
    local r = Sim.simulate(field, route, cond, Hash.stream(race.seed, race.raceId), { baseSec = base })
    local purse = Finance.purse(race.tier, #field)
    local lastMs = 0
    local st = {}
    local splits = {}
    for _, e in ipairs(r.entrants) do
        e.points = Season.pointsFor(e.position, e.state)
        e.purse = (e.state == "finished") and (purse[e.position] or 0) or 0
        if e.finishMs and e.finishMs > lastMs then lastMs = e.finishMs end
        splits[e.id] = e.splits
        st[#st + 1] = { query = [[INSERT IGNORE INTO paddock_result (server_id, race_id, person_id, org_id, series_id, season_id,
            cup_id, position, grid, state, finish_ms, gap_ms, points, purse, dnf_reason, at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, -1), ?, ?, NULLIF(?, ''), ?)]],
            values = { U.sid(), race.raceId, e.id, e.orgId or "", race.seriesId, race.seasonId, race.cupId, e.position,
                e.grid, e.state, e.finishMs or -1, e.gapMs or -1, e.points, e.purse, e.dnfReason or "", race.opensAt } }
    end
    race.closesAt = race.opensAt + math.ceil(lastMs / 1000) + 30
    race.cond, race.baseSec, race.baseSource = cond, base, source
    race.result = r
    -- the continuous race (paddock.racestate): where every car is, every moment, watched or not -- LIVE reads it, and
    -- the physical bubble will hand cars in and out of it
    local path = PaddockLive and PaddockLive.pathFor(race.routeId)
    if path then
        local okM, model = pcall(NcmCore.get("paddock.racestate").new, path, r.entrants, r.segments)
        if okM then race.model, race.modelGoAt = model, race.opensAt end
    end
    race.state = "running"
    local detail = { frozen = race.frozen, splits = splits, events = r.events, segments = r.segments }
    st[#st + 1] = { query = [[UPDATE paddock_race SET state = 'running', window_closes_at = ?, weather = NULLIF(?, ''),
        road_wetness = NULLIF(?, -1), seconds_of_day = NULLIF(?, -1), light = NULLIF(?, ''), base_sec = NULLIF(?, -1),
        base_source = NULLIF(?, ''), sim_version = NULLIF(?, -1), detail_json = ?
        WHERE server_id = ? AND race_id = ?]],
        -- Conditions can be missing (no weather plan yet); a DNF has no finish. Sentinels, never nil holes.
        values = { race.closesAt, cond.weather or "", cond.roadWetness or -1, cond.secondsOfDay or -1, cond.light or "",
            base or -1, source or "", r.simVersion or -1, U.encode(detail) or "{}", U.sid(), race.raceId } }
    local ok, err = U.transact(st)
    if not ok then log("run %s store FAILED: %s", race.raceId, tostring(err)) end
    PaddockBillie.close(race)
end

-- Result rows for a race (memory first, database after a restart).
local function resultsOf(race)
    if race.result then return race.result.entrants, race.result.events or {} end
    local rows = MySQL.query.await([[SELECT person_id, org_id, position, grid, state, finish_ms, gap_ms, points, purse, dnf_reason
        FROM paddock_result WHERE server_id = ? AND race_id = ? ORDER BY position]], { U.sid(), race.raceId }) or {}
    local out = {}
    for i, x in ipairs(rows) do
        out[i] = { id = x.person_id, orgId = x.org_id, position = num(x.position), grid = num(x.grid), state = x.state,
            finishMs = num(x.finish_ms), gapMs = num(x.gap_ms), points = num(x.points), purse = num(x.purse), dnfReason = x.dnf_reason }
    end
    local d = MySQL.scalar.await("SELECT detail_json FROM paddock_race WHERE server_id = ? AND race_id = ?", { U.sid(), race.raceId })
    local detail = U.decode(d) or {}
    return out, detail.events or {}
end

local function marginText(ms)
    if not ms then return nil end
    return string.format("%.2fs", ms / 1000)
end

local function ensure(e) e = e or {} e.recent = e.recent or {} e.rivals = e.rivals or {} return e end

--- Apply one driver's result to their evidence (the facts earned tags read) and morale.
local function applyEvidence(p, res, fieldSize, cond, contacts)
    local e = ensure(p.evidence)
    p.evidence = e
    e.starts = (e.starts or 0) + 1
    e.seasonStarts = (e.seasonStarts or 0) + 1
    local pos = res.state == "finished" and res.position or fieldSize
    e.seasonSum = (e.seasonSum or 0) + pos
    e.seasonAvg = e.seasonSum / e.seasonStarts
    e.recent[#e.recent + 1] = pos
    while #e.recent > 10 do table.remove(e.recent, 1) end
    local wet = (tonumber(cond and cond.roadWetness) or 0) >= 0.5
    local night = cond and cond.light == "night"
    if wet then e.wetStarts = (e.wetStarts or 0) + 1 end
    if night then e.nightStarts = (e.nightStarts or 0) + 1 end
    if res.state == "finished" then
        e.finishes = (e.finishes or 0) + 1
        e.placesGained = (e.placesGained or 0) + ((res.grid or pos) - pos)
        if pos == 1 then
            e.wins = (e.wins or 0) + 1; e.seasonWins = (e.seasonWins or 0) + 1
            e.winStreak = (e.winStreak or 0) + 1
            if (res.grid or 1) >= 5 then e.upsetWins = (e.upsetWins or 0) + 1 end
        else
            e.winStreak = 0
        end
        if pos <= 3 then
            e.podiums = (e.podiums or 0) + 1
            if wet then e.wetTop3 = (e.wetTop3 or 0) + 1 end
            if night then e.nightTop3 = (e.nightTop3 or 0) + 1 end
        end
    else
        e.winStreak = 0
        e.dnfs = (e.dnfs or 0) + 1
        e.seasonDnfs = (e.seasonDnfs or 0) + 1
        if res.dnfReason == "crash" or res.dnfReason == "contact" then e.crashes = (e.crashes or 0) + 1 end
    end
    for other in pairs(contacts[p.id] or {}) do
        e.contacts = (e.contacts or 0) + 1
        e.seasonContacts = (e.seasonContacts or 0) + 1
        e.rivals[other] = (e.rivals[other] or 0) + 1
    end
    Progression.moraleAfterRace(p, pos, res.grid or pos, fieldSize, res.state)
    PaddockStore.markPerson(p.id)
end

--- Make a closed race public and apply everything that follows from it.
function PaddockRaces.resolve(race, t)
    local w = PaddockStore.world
    -- cars that drove physically in a player's bubble: the result is the model's, with their anchors (bubble.lua)
    if PaddockBubble then pcall(PaddockBubble.writeBack, race) end
    local entrants, simEvents = resultsOf(race)
    local cond = race.cond or { roadWetness = race.roadWetness, light = race.light, weather = race.weather }
    local n = #entrants
    -- contacts from the sim's own events
    local contacts = {}
    for _, ev in ipairs(simEvents or {}) do
        if ev.kind == "contact" and ev.ids and ev.ids[2] then
            local a, b = ev.ids[1], ev.ids[2]
            contacts[a] = contacts[a] or {}; contacts[a][b] = true
            contacts[b] = contacts[b] or {}; contacts[b][a] = true
        end
    end
    local byId = {}
    for _, res in ipairs(entrants) do
        byId[res.id] = res
        local p = w.people[res.id]
        if p then applyEvidence(p, res, n, cond, contacts) end
        local org = w.orgs[res.orgId or ""]
        if org and (res.purse or 0) > 0 then
            org.cash = (org.cash or 0) + res.purse
            PaddockStore.markOrg(org.id)
            if org.humanManagerDriverId then PaddockManager.book(org, "purse", res.purse, "purse:" .. race.raceId .. ":" .. res.id, race.raceId) end
        end
    end
    -- the story
    local seriesName = PaddockWorld.seriesName(race.seriesId)
    local routeName = PaddockWorld.routeName(race.routeId)
    local events = {}
    local first, second, third = entrants[1], entrants[2], entrants[3]
    if first and first.state == "finished" then
        local winner = w.people[first.id]
        local facts = {
            tier = race.tier, winner = PaddockWorld.personName(first.id), winnerOrg = PaddockWorld.orgName(first.orgId),
            second = second and second.state == "finished" and PaddockWorld.personName(second.id) or nil,
            third = third and third.state == "finished" and PaddockWorld.personName(third.id) or nil,
            series = seriesName, route = routeName, fieldSize = n,
            margin = second and second.state == "finished" and marginText(second.gapMs) or nil,
            wet = ((cond.roadWetness or 0) >= 0.5) and "rain-soaked" or (((cond.roadWetness or 0) >= 0.2) and "damp" or nil),
            night = cond.light == "night" and "after dark" or nil,
            fromGrid = (first.grid or 1) >= 4 and first.grid or nil,
            closeFinish = (second and second.gapMs and second.gapMs < 150) and "By a whisker" or nil,
            oneTwo = (second and second.orgId == first.orgId and second.state == "finished") and "one-two" or nil,
            raceId = race.raceId,
        }
        local ents = { { "person", first.id }, { "org", first.orgId }, { "race", race.raceId } }
        local rr = Tape.event("race_result", race.raceId, t, { entities = ents, facts = facts,
            salienceBonus = (facts.closeFinish and 5 or 0) + (facts.oneTwo and 5 or 0) })
        events[#events + 1] = rr
        local ev = winner and winner.evidence or {}
        if (first.grid or 1) >= 5 then
            local price = PaddockBillie.winPrice(race.raceId, first.id)
            local f2 = {}
            for k, v in pairs(facts) do f2[k] = v end
            f2.price = price and string.format("%.2f", price) or nil
            events[#events + 1] = Tape.event("upset", race.raceId, t, { entities = ents, facts = f2, causeRefs = { rr.id } })
        end
        if (ev.winStreak or 0) >= 3 then
            events[#events + 1] = Tape.event("streak", first.id .. ":" .. ev.winStreak .. ":" .. race.raceId, t, {
                entities = ents, causeRefs = { rr.id }, salienceBonus = math.min(20, (ev.winStreak - 3) * 5),
                facts = { tier = race.tier, driver = facts.winner, org = facts.winnerOrg, count = ev.winStreak, series = seriesName } })
        end
        if (ev.wins or 0) == 1 and (ev.starts or 0) >= 5 then
            events[#events + 1] = Tape.event("first_win", first.id, t, { entities = ents, causeRefs = { rr.id },
                facts = { tier = race.tier, driver = facts.winner, org = facts.winnerOrg, series = seriesName,
                    route = routeName, starts = ev.starts } })
        end
    end
    -- crash-outs are news in the sanctioned tiers; on the street they are just a night
    if race.tier == "pro" or race.tier == "premier" then
        for _, res in ipairs(entrants) do
            if res.state == "dnf" then
                events[#events + 1] = Tape.event("crash_out", race.raceId .. ":" .. res.id, t, {
                    entities = { { "person", res.id }, { "org", res.orgId } },
                    facts = { tier = race.tier, driver = PaddockWorld.personName(res.id), org = PaddockWorld.orgName(res.orgId),
                        route = routeName, series = seriesName,
                        cause = (res.dnfReason == "mechanical" and "mechanical failure") or (res.dnfReason == "contact" and "contact with another car") or "a crash" } })
            end
        end
    end
    -- feuds: the second, fourth, sixth... contact between the same two drivers this season
    local done = {}
    for a, set in pairs(contacts) do
        for b in pairs(set) do
            local key = a < b and (a .. "|" .. b) or (b .. "|" .. a)
            if not done[key] then
                done[key] = true
                local pa = w.people[a]
                local count = pa and pa.evidence and pa.evidence.rivals and pa.evidence.rivals[b] or 0
                if count >= 2 and count % 2 == 0 then
                    local ra, rb = byId[a] or {}, byId[b] or {}
                    for _, x in ipairs({ a, b }) do
                        local px = w.people[x]
                        if px then px.evidence.feuds = (px.evidence.feuds or 0) + 1; PaddockStore.markPerson(x) end
                    end
                    events[#events + 1] = Tape.event("feud", key .. ":" .. count, t, {
                        entities = { { "person", a }, { "person", b } },
                        facts = { tier = race.tier, driverA = PaddockWorld.personName(a), driverB = PaddockWorld.personName(b),
                            orgA = PaddockWorld.orgName(ra.orgId), orgB = PaddockWorld.orgName(rb.orgId), count = count, route = routeName } })
                end
            end
        end
    end
    PaddockStory.record(events)
    PaddockBillie.settle(race, byId)
    race.state = "resolved"
    pcall(MySQL.update.await, "UPDATE paddock_race SET state = 'resolved', resolved_at = ? WHERE server_id = ? AND race_id = ?",
        { t, U.sid(), race.raceId })
    race.result = nil
    PaddockStore.flush()
end

--- One scheduler pass over the races in memory. Bounded work per call: at most one run and one resolve, so a
--- backlog after downtime drains across ticks instead of inside one metered handler.
function PaddockRaces.tick(t)
    local runNext, resolveNext, priceNext
    for _, race in pairs(PaddockRaces.byId) do
        -- a declared live race holds its close until the street run has a verdict (live.lua); Billie settles after
        if race.state == "running" and race.closesAt and t >= race.closesAt and not (PaddockLive and PaddockLive.holds(race.raceId))
            and not (PaddockBubble and PaddockBubble.holds(race, t)) then
            if not resolveNext or race.closesAt < resolveNext.closesAt then resolveNext = race end
        elseif (race.state == "scheduled" or race.state == "priced") and t >= race.opensAt then
            if not runNext or race.opensAt < runNext.opensAt then runNext = race end
        elseif race.state == "scheduled" and t >= race.opensAt - PaddockSettings.get("billieLeadMinutes", 15) * 60 then
            if not priceNext or race.opensAt < priceNext.opensAt then priceNext = race end
        end
    end
    if resolveNext then PaddockRaces.resolve(resolveNext, t) end
    if runNext then PaddockRaces.run(runNext, t) end
    if priceNext then PaddockBillie.price(priceNext) end
    -- forget old resolved races
    for id, race in pairs(PaddockRaces.byId) do
        if (race.state == "resolved" or race.state == "void") and race.opensAt < t - 6 * 3600 then PaddockRaces.byId[id] = nil end
    end
end
