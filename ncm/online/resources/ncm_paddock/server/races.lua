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
    NcmCore.get("data.ovals").SCHEDULED = PaddockSettings.get("ovalsScheduled", true)
    local rows = MySQL.query.await([[SELECT * FROM paddock_race WHERE server_id = ? AND window_opens_at >= ?
        AND state IN ('scheduled','priced','running') ORDER BY window_opens_at]], { U.sid(), t - 6 * 3600 }) or {}
    for _, r in ipairs(rows) do PaddockRaces.byId[r.race_id] = rowToRace(r) end
    for _, race in pairs(PaddockRaces.byId) do
        if race.frozen and (race.state == "scheduled" or race.state == "priced") and race.opensAt - t > NcmCore.get("paddock.mixed").FREEZE_LEAD_SEC then
            race.frozen = nil
            pcall(MySQL.update.await, "UPDATE paddock_race SET detail_json = '{}' WHERE server_id = ? AND race_id = ?", { U.sid(), race.raceId })
            log("released legacy early grid for %s; entry remains open until T-1", race.raceId)
        end
    end
    -- L254: retire checkpointed courses and restore deterministic oval slots from the earlier oval-off schedule.
    -- Existing humans remain entered; route changes clear course-specific times so untimed entrants line up last.
    local w = PaddockStore.world
    local moved = 0
    for _, race in pairs(PaddockRaces.byId) do
        local route = PaddockWorld.route(race.routeId)
        local badCourse = not route or (not route.oval and route.intermediate and #route.intermediate > 0)
        local future = race.state == "scheduled" or race.state == "priced"
        local desiredId = future and Season.routeFor(w.seed, race.seriesId, race.opensAt) or nil
        local desired = desiredId and PaddockWorld.route(desiredId) or nil
        local restoreOval = future and not badCourse and not (route and route.oval) and desired and desired.oval
        if future and (badCourse or restoreOval) then
            local routeId = desiredId
            local replacement = routeId and PaddockWorld.route(routeId) or nil
            if replacement and (replacement.oval or not (replacement.intermediate and #replacement.intermediate > 0)) then
                local ok = U.transact({
                    { query = "UPDATE paddock_race SET route_id = ?, detail_json = '{}', base_sec = NULL, base_source = NULL WHERE server_id = ? AND race_id = ? AND state IN ('scheduled','priced')",
                      values = { routeId, U.sid(), race.raceId } },
                    { query = "DELETE FROM paddock_quali WHERE server_id = ? AND race_id = ?", values = { U.sid(), race.raceId } },
                    { query = "UPDATE paddock_entry SET quali_ms = NULL WHERE server_id = ? AND race_id = ?", values = { U.sid(), race.raceId } },
                })
                if ok then
                    race.routeId, race.frozen, race.baseSec, race.baseSource = routeId, nil, nil, nil
                    moved = moved + 1
                    pcall(TriggerEvent, "ncm:paddock.routeChanged", race.raceId, routeId)
                    log("rescheduled %s from %s course %s to %s %s (%.0fm)", race.raceId,
                        badCourse and "checkpointed" or "valid", tostring(route and route.name or "unknown"),
                        replacement.oval and "oval" or "point-to-point", routeId, replacement.distanceM or 0)
                else
                    log("could not replace broken course for %s", race.raceId)
                end
            else
                log("no valid replacement course for %s; leaving it unpublished", race.raceId)
            end
        end
    end
    log("loaded %d open races; refreshed %d checkpointed/oval schedule slot(s)", #rows, moved)
end

--- Write rows for every race in the horizon that does not exist yet.
function PaddockRaces.materialise(t)
    -- L254: keep ovals on the calendar; only checkpointed routes are temporarily excluded.
    NcmCore.get("data.ovals").SCHEDULED = PaddockSettings.get("ovalsScheduled", true)
    local w = PaddockStore.world
    local horizon = PaddockSettings.get("horizonMinutes", 120) * 60
    local st = {}
    local made = 0
    for _, slot in ipairs(Season.window(t, t + horizon)) do
        local id = Season.raceId(slot.seriesId, slot.utc)
        if not PaddockRaces.byId[id] then
            made = made + 1
            if made % 6 == 0 then Wait(0) end        -- ~125 races a day (L236): route picks are metered too
            local cup = Season.cupOf(slot.utc)
            local seed = math.random(1, 2147483646)
            local routeId = Season.routeFor(w.seed, slot.seriesId, slot.utc)
            if not routeId then
                log("no point-to-point route passes the distance filter for %s; slot skipped", id)
            else
                local race = { raceId = id, seriesId = slot.seriesId, tier = slot.tier, seasonId = cup.seasonId,
                    cupId = cup.cupId, routeId = routeId, opensAt = slot.utc,
                    state = "scheduled", seed = seed, commit = Hash.commit(seed, id), provenance = "simulated" }
                PaddockRaces.byId[id] = race
                st[#st + 1] = { query = [[INSERT IGNORE INTO paddock_race (server_id, race_id, series_id, tier, season_id, cup_id,
                    route_id, window_opens_at, state, seed, seed_commit) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'scheduled', ?, ?)]],
                    values = { U.sid(), id, race.seriesId, race.tier, race.seasonId, race.cupId, race.routeId, race.opensAt,
                        seed, race.commit } }
            end
        end
    end
    if #st > 0 then
        local ok, err = U.transact(st)
        if not ok then log("materialise FAILED: %s", tostring(err)) end
    end
    return #st
end

--- The entrant list as the sim wants it, in GRID order.
function PaddockRaces.buildField(race, humanCount)
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
        -- L249: who turned up -- a street league's pool, a sanctioned team's available drivers
        local absent
        list, absent = World.raceField(w, race)
        race.absent = NcmCore.get("paddock.attendance").tally(absent)
        -- L250: each entered human takes the place of the last NPC who turned up (the field size is attendance's)
        local keep = NcmCore.get("paddock.mixed").npcPlaces(#list, humanCount or 0)
        for i = #list, keep + 1, -1 do list[i] = nil end
        -- a whole league's attendance, then qualifying: give the slice back in between (KB-211)
        if coroutine.isyieldable() then Wait(0) end
    end
    local n = #list
    for _, e in ipairs(list) do
        local org = e.org or {}
        -- an independent races their own car (L249)
        field[#field + 1] = { id = e.driver.id, orgId = org.id or (race.frozen and race.frozen.orgOf and race.frozen.orgOf[e.driver.id]),
            -- L298: the car this driver races (derived from its parts) when they have one; else the team's abstract car
            attrs = e.driver.attrs, carPerf = Car.performance((e.driver.raceCarId and e.driver.car) or org.car or e.driver.car), morale = e.driver.morale,
            form = Progression.form((e.driver.evidence or {}).recent or {}, n),
            humanManaged = org.humanManagerDriverId ~= nil }
    end
    if not ids then
        -- L250 step 2: with times, against the route's base -- shown, and set beside human qualifying times
        local okS, _, _, base = pcall(PaddockRaces.setup, race)
        field = Sim.qualify(field, Hash.stream(race.seed, "quali", race.raceId), okS and base or nil)
    end
    -- an oval grids only what its roundabout can hold (L236): the qualifying order decides who starts
    local route = PaddockWorld.route(race.routeId)
    local cap = route and route.oval and route.oval.fieldMax
    if cap and #field > cap then
        for i = #field, cap + 1, -1 do field[i] = nil end
    end
    return field
end

--- Fix the field and grid (pricing time, or run time when Billie is off).
function PaddockRaces.freeze(race)
    if race.frozen then return race.frozen end
    local humans = PaddockHumans and PaddockHumans.entered(race) or {}
    local field = PaddockRaces.buildField(race, #humans)
    local grid, orgOf, quali = {}, {}, {}
    local w = PaddockStore.world
    for i, e in ipairs(field) do
        grid[i] = e.id; orgOf[e.id] = e.orgId
        quali[e.id] = e.qualiMs
        -- they turned up: a street racer is far less likely to make the next one (paddock.attendance RECENT_SEC)
        local p = w.people[e.id]
        if p then p.evidence = p.evidence or {}; p.evidence.lastStartAt = race.opensAt; PaddockStore.markPerson(p.id) end
    end
    race.frozen = { grid = grid, orgOf = orgOf, absent = race.absent, quali = quali }
    -- L250: a mixed grid -- everyone by qualifying time, entered-but-unqualified humans at the back
    if #humans > 0 then
        local Mixed = NcmCore.get("paddock.mixed")
        local npcs = {}
        for i, e in ipairs(field) do npcs[i] = { id = e.id, qualiMs = e.qualiMs } end
        local order, q = Mixed.gridOrder(npcs, humans)
        race.frozen.grid, race.frozen.quali, race.frozen.humans = order, q, {}
        for _, h in ipairs(humans) do race.frozen.humans[h.key] = { driverId = h.driverId, display = h.display } end
        log("%s: mixed grid -- %d human(s) and %d NPC(s): %s", race.raceId, #humans, #field, table.concat(order, " "))
    end
    pcall(MySQL.update.await, "UPDATE paddock_race SET detail_json = ? WHERE server_id = ? AND race_id = ?",
        { U.encode({ frozen = race.frozen }), U.sid(), race.raceId })
    if race.frozen.humans then pcall(PaddockHumans.sendGrid, race) end
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
    local r = Sim.simulate(field, route, cond, Hash.stream(race.seed, race.raceId), { baseSec = base, tier = race.tier })
    Wait(0)                                           -- the sim and the result's encode each want a slice of their own
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
    -- L250: a mixed grid's humans, timed by the league, merged with the NPCs by time from the one green
    if PaddockHumans and PaddockHumans.mixed(race) then
        local okM, merged = pcall(PaddockHumans.merge, race, entrants)
        if okM and merged then entrants = merged else log("%s: merge failed: %s", race.raceId, tostring(merged)) end
    end
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
    -- L298: the money of the race, ledgered -- entry fees out, purses in, crash repairs out -- for the team that runs
    -- the car or the independent who owns it (`npc_money`; the balances are the Paddock's, flushed by the store)
    local Garage = NcmCore.get("economy.npc_garage")
    local ledger, raced, half = {}, {}, {}
    local function book(kind, id, amount, what, reason, ref)
        if amount == 0 then return end
        ledger[#ledger + 1] = { query = [[INSERT IGNORE INTO npc_money (entry_id, server_id, principal_kind, principal_id, amount, kind, ref,
            idem_key, created_at, reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''))]],
            values = { U.uuid(), U.sid(), kind, id, amount, what, ref, ("%s:%s:%s"):format(what, race.raceId, ref), t, reason or "" } }
    end
    local fee = Garage.entryFee(race.tier)
    for _, res in ipairs(entrants) do
        byId[res.id] = res
        local p = w.people[res.id]
        if p then applyEvidence(p, res, n, cond, contacts) end
        local org = w.orgs[res.orgId or ""]
        if p and org then
            org.cash = (org.cash or 0) + (res.purse or 0) - fee
            PaddockStore.markOrg(org.id)
            book("org", org.id, -fee, "entry_fee", "race_entry", res.id)
            book("org", org.id, res.purse or 0, "purse", "race_result", res.id)
            if org.humanManagerDriverId and (res.purse or 0) > 0 then PaddockManager.book(org, "purse", res.purse, "purse:" .. race.raceId .. ":" .. res.id, race.raceId) end
        elseif p then
            -- L249: an independent races for themselves -- the purse is theirs (person.cash), and so is the entry fee
            p.cash = (tonumber(p.cash) or 0) + (res.purse or 0) - fee
            PaddockStore.markPerson(p.id)
            book("person", p.id, -fee, "entry_fee", "race_entry", p.id)
            book("person", p.id, res.purse or 0, "purse", "race_result", p.id)
        end
        if p and p.raceCarId then
            if res.state == "finished" then raced[#raced + 1] = p.id else half[#half + 1] = p.id end
            -- a crash in a player's bubble is a repair bill (bubble.lua records the damage a physical car took)
            local dmg = race.carDamage and race.carDamage[p.id]
            if dmg and PaddockCars then
                local c = PaddockCars.load(p.raceCarId)
                local cost = Garage.repairCost(c and c.value or 10000, dmg.frac, dmg.wrecked)
                if cost > 0 then
                    if org then org.cash = (org.cash or 0) - cost; PaddockStore.markOrg(org.id); book("org", org.id, -cost, "repair", dmg.wrecked and "wreck" or "crash_damage", p.id)
                    else p.cash = (tonumber(p.cash) or 0) - cost; PaddockStore.markPerson(p.id); book("person", p.id, -cost, "repair", dmg.wrecked and "wreck" or "crash_damage", p.id) end
                end
            end
        end
    end
    if #ledger > 0 then pcall(U.transact, ledger) end
    -- the race's distance onto every car that ran it: the odometer and every installed part's wear clock
    if PaddockCars then
        local lengthM = (race.model and race.model.lengthM) or (PaddockWorld.route(race.routeId) or {}).distanceM or 3000
        pcall(PaddockCars.raced, raced, lengthM)
        pcall(PaddockCars.raced, half, lengthM / 2)
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
            oneTwo = (second and first.orgId and second.orgId == first.orgId and second.state == "finished") and "one-two" or nil,
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
    -- the district's climate hears of it (L240): a street race grows the scene, crashes raise the heat
    if PaddockDays then
        local district = PaddockDays.raceDistrict(race)
        if district then
            PaddockDays.fact(district, race.tier == "street" and "street_race" or "sanctioned_race", 1)
            local crashes = 0
            for _, res in ipairs(entrants) do
                if res.state == "dnf" and (res.dnfReason == "crash" or res.dnfReason == "contact") then crashes = crashes + 1 end
            end
            if crashes > 0 then PaddockDays.fact(district, "race_crash", crashes) end
        end
    end
    PaddockBillie.settle(race, byId)
    race.state = "resolved"
    pcall(MySQL.update.await, "UPDATE paddock_race SET state = 'resolved', resolved_at = ? WHERE server_id = ? AND race_id = ?",
        { t, U.sid(), race.raceId })
    race.result = nil
    PaddockStore.flush()
end

--- One scheduler pass over the races in memory. Bounded work per call: at most one run and one resolve, so a
--- backlog after downtime drains across ticks instead of inside one metered handler.
--- L249: the next Paddock events, for the Race Guide (ncm_league reads GlobalState.ncmPaddockGuide; it cannot call
--- this VM). Bounded (16 rows), rebuilt at most every 10 s, and written only when something changed.
local guideAt, guideSig = 0, nil
local guideEventAt, guideEventSig = 0, nil
function PaddockRaces.publishGuide(t)
    if t - guideAt < 10 then return end
    guideAt = t
    local list = {}
    for _, race in pairs(PaddockRaces.byId) do
        if (race.state == "scheduled" or race.state == "priced" or race.state == "running") and race.opensAt >= t - 1800
            and race.opensAt <= t + 3 * 3600 then
            local route = PaddockWorld.route(race.routeId)
            if route and (route.oval or not (route.intermediate and #route.intermediate > 0)) then
                list[#list + 1] = race
            end
        end
    end
    table.sort(list, function(a, b) if a.opensAt ~= b.opensAt then return a.opensAt < b.opensAt end return a.raceId < b.raceId end)
    local spec = NcmCore.get("paddock.season").TIERS
    local out, sig = {}, {}
    for i = 1, math.min(40, #list) do
        local race = list[i]
        local route = PaddockWorld.route(race.routeId)
        local s = spec[race.tier] or {}
        local field = race.frozen and #race.frozen.grid or math.floor((s.orgs or 12) / (s.divisions or 1)) * (s.carsPerOrg or 1)
        local function pt(n) return n and { x = math.floor(n.x), y = math.floor(n.y), z = math.floor(n.z or 0), name = n.name } or nil end
        out[#out + 1] = { raceId = race.raceId, seriesId = race.seriesId, seriesName = PaddockWorld.seriesName(race.seriesId),
            tier = race.tier, routeId = race.routeId, routeName = PaddockWorld.routeName(race.routeId),
            distanceM = route and math.floor(route.distanceM or 0) or nil, venue = route and pt(route.start), finish = route and pt(route.finish),
            startsAt = race.opensAt, state = race.state, field = field, oval = route and route.oval and true or nil,
            laps = route and route.oval and route.oval.laps or nil,
            -- the qualifying sheet once the grid is frozen (L250 step 2): { name, quali seconds } in grid order
            quali = race.frozen and NcmCore.get("paddock.projection").qualiSheet(race.frozen, function(id)
                local p = PaddockStore.world.people[id]; return p and p.display or "?" end) or nil }
        if race.frozen and race.frozen.humans then
            local nh = 0
            for _ in pairs(race.frozen.humans) do nh = nh + 1 end
            out[#out].humans = nh
        end
            sig[#sig + 1] = race.raceId .. race.state .. field .. tostring(race.routeId)
    end
    local key = table.concat(sig, ",")
    if key ~= guideSig then
        guideSig = key
        GlobalState.ncmPaddockGuide = out
    end
    -- L250: and as a server event, which is proven between resources (GlobalState read across resources is not):
    -- on every change, and once a minute so a restarted ncm_league has it within a minute
    if key ~= guideEventSig or t - guideEventAt >= 60 then
        guideEventSig, guideEventAt = key, t
        TriggerEvent("ncm:paddock.guide", out)
    end
end

--- THE FLAG (owner, 2026-10-02): when the first car of the whole field -- model, bubble or human -- is home, the rest
--- have `paddock.mixed.finishWindowSec(length)`; the race closes then, whoever is still out. Replaces closing at the
--- sim's slowest finisher + 30 s and waiting for every physical car (a 4-minute wait after the owner's finish at 16:02).
local Mixed = NcmCore.get("paddock.mixed")
local RS = NcmCore.get("paddock.racestate")
local function flagCheck(race, t)
    if race.state ~= "running" or race.flagAt or not race.model or t < race.opensAt then return end
    local lead
    local leadMs = RS.leaderFinishAt(race.model)
    if leadMs and race.modelGoAt and race.modelGoAt + leadMs / 1000 <= t then lead = race.modelGoAt + leadMs / 1000 end
    local h = PaddockHumans and PaddockHumans.firstFinishAt and PaddockHumans.firstFinishAt(race)
    if h and (not lead or h < lead) then lead = h end
    if not lead then return end
    local window = Mixed.finishWindowSec(race.model.lengthM)
    race.flagAt = math.floor(lead + window + 0.5)
    -- whichever comes first: everyone home (the existing close, still held while cars are on the road), or the flag
    race.closesAt = math.min(race.closesAt or race.flagAt, race.flagAt)
    TriggerEvent("ncm:paddock.flag", race.raceId, race.flagAt)
    log("%s: leader home at %d; FLAG in %d s (%.0f m x %.3f s/m) at %d", race.raceId, math.floor(lead), window,
        race.model.lengthM, Mixed.FLAG_SEC_PER_M, race.flagAt)
end
PaddockRaces.flagCheck = flagCheck

function PaddockRaces.tick(t)
    pcall(PaddockRaces.publishGuide, t)
    local runNext, resolveNext, priceNext
    for _, race in pairs(PaddockRaces.byId) do
        pcall(flagCheck, race, t)
        -- a declared live race holds its close until the street run has a verdict (live.lua); Billie settles after
        -- at the flag nothing else holds a race open but a human result still on its way (a few seconds: the league
        -- closes its session at the same flag)
        local flagged = race.flagAt and t >= race.flagAt
        if race.state == "running" and race.closesAt and t >= race.closesAt and not (PaddockLive and PaddockLive.holds(race.raceId))
            and (flagged or not (PaddockBubble and PaddockBubble.holds(race, t)))
            and not (PaddockHumans and PaddockHumans.holds(race, t)) then
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
