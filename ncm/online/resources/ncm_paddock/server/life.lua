-- ncm_paddock / server / life -- the Paddock over days, weeks and seasons (doc 44 §4.4, §5.3).
--
--   daily   (Eastern day change)  growth/decay once, morale drift, money, solvency, manager digests
--   cup     (weekly boundary)     archive Cup standings and titles, apply queued manager moves, NPC owners decide,
--                                 human managers of inherited orgs face their owner, folded slots are refilled
--   season  (UTC quarter)         titles, promotion/relegation, a paddock year of age, retirements, contracts,
--                                 free-agent pool top-up
-- Each pass is idempotent by its key (day index, Cup id, season id) stored on `paddock_world`, and yields as it
-- goes: a pass can run after downtime without doing anything twice and without nearing the quota.
PaddockLife = {}

local U = PaddockUtil
local log = U.logger("life")
local Hash = NcmCore.get("vocabulary.hash")
local Clock = NcmCore.get("world.clock")
local World = NcmCore.get("paddock.world")
local Season = NcmCore.get("paddock.season")
local Attr = NcmCore.get("paddock.attributes")
local Car = NcmCore.get("paddock.car")
local Finance = NcmCore.get("paddock.finance")
local Progression = NcmCore.get("paddock.progression")
local Contracts = NcmCore.get("paddock.contracts")
local Principal = NcmCore.get("paddock.principal")
local Tape = NcmCore.get("paddock.tape")

local function w() return PaddockStore.world end

-- ---------------------------------------------------------------------------------------------------------------
-- Roster helpers
-- ---------------------------------------------------------------------------------------------------------------

--- Race seats go to the best-rated contracted drivers; the rest are reserves. Human managers choose their own.
function PaddockLife.reseat(org)
    if org.humanManagerDriverId then return end
    local drivers = World.drivers(w(), org.id)
    table.sort(drivers, function(a, b)
        local ra, rb = Attr.rating(a.attrs), Attr.rating(b.attrs)
        if ra ~= rb then return ra > rb end
        return a.id < b.id
    end)
    local cars = Season.TIERS[org.tier].carsPerOrg
    for i, d in ipairs(drivers) do
        local seat = (i <= cars) and ("race" .. i) or "reserve"
        if d.seat ~= seat then d.seat = seat; PaddockStore.markPerson(d.id) end
    end
end

local function tierMedian(tier)
    local ratings = {}
    local world = w()
    for _, oid in ipairs(world.orgOrder) do
        local o = world.orgs[oid]
        if o.tier == tier and o.lifecycle == "active" then
            for _, d in ipairs(World.drivers(world, oid)) do ratings[#ratings + 1] = Attr.rating(d.attrs) end
        end
    end
    table.sort(ratings)
    return ratings[math.max(1, math.floor(#ratings / 2))] or 50
end

local function freeAgentsBest()
    local fas = World.freeAgents(w())
    -- each rating once, not inside the comparator (the KB-214 shape; 120 free agents since L236)
    local r = {}
    for _, p in ipairs(fas) do r[p] = Attr.rating(p.attrs) end
    table.sort(fas, function(a, b)
        if r[a] ~= r[b] then return r[a] > r[b] end
        return a.id < b.id
    end)
    return fas
end

--- Move a driver into an org (signing). Returns the tape event.
function PaddockLife.sign(driver, org, wage, seasons, t, fromOrg)
    local world = w()
    driver.orgId, driver.state, driver.seat = org.id, "active", "reserve"
    driver.wage = wage
    driver.contractEnds = world.seasonOrdinal + (seasons or 1)
    local e = driver.evidence or {}
    e.orgsDriven = (e.orgsDriven or 0) + 1
    if fromOrg then e.transfers = (e.transfers or 0) + 1 end
    e.seasonsAtOrg = 0
    driver.evidence = e
    World.invalidate(world)
    PaddockLife.reseat(org)
    PaddockStore.markPerson(driver.id)
    pcall(MySQL.update.await, [[UPDATE paddock_contract SET ended_at = ?, end_reason = 'transfer' WHERE server_id = ? AND person_id = ?
        AND ended_at IS NULL]], { t, U.sid(), driver.id })
    pcall(MySQL.insert.await, [[INSERT INTO paddock_contract (contract_id, server_id, person_id, org_id, seat, wage, starts_season,
        ends_season, signed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { U.uuid(), U.sid(), driver.id, org.id, driver.seat, wage, world.seasonOrdinal, driver.contractEnds, t })
    return Tape.event("transfer", driver.id .. ":" .. org.id .. ":" .. t, t, {
        entities = { { "person", driver.id }, { "org", org.id } },
        facts = { tier = org.tier, driver = driver.display, toOrg = org.name,
            fromNote = fromOrg and (" from " .. fromOrg.name) or " from the free-agent pool" } })
end

--- Release a driver to the free-agent pool. Returns the tape event.
function PaddockLife.release(driver, org, t, reason)
    driver.orgId, driver.seat, driver.state, driver.wage = nil, nil, "free_agent", 0
    World.invalidate(w())
    PaddockStore.markPerson(driver.id)
    pcall(MySQL.update.await, [[UPDATE paddock_contract SET ended_at = ?, end_reason = ? WHERE server_id = ? AND person_id = ?
        AND ended_at IS NULL]], { t, reason or "release", U.sid(), driver.id })
    if org then PaddockLife.reseat(org) end
    return Tape.event("release", driver.id .. ":" .. (org and org.id or "-") .. ":" .. t, t, {
        entities = { { "person", driver.id }, { "org", org and org.id } },
        facts = { tier = org and org.tier, driver = driver.display, org = org and org.name } })
end

--- Fill empty race seats from the free-agent pool (quietly: it is housekeeping, not news).
function PaddockLife.fillSeats(org, t)
    local spec = Season.TIERS[org.tier]
    local have = #World.drivers(w(), org.id)
    local events = {}
    local fas = freeAgentsBest()
    local i = 1
    while have < spec.carsPerOrg and fas[i] do
        local d = fas[i]
        local ev = PaddockLife.sign(d, org, Contracts.askingWage(d, org.tier), 1, t, nil)
        if org.tier == "pro" or org.tier == "premier" then events[#events + 1] = ev end
        have, i = have + 1, i + 1
    end
    while have < spec.carsPerOrg do        -- the pool ran dry: a rookie walks in
        local d = World.newPerson(w(), "driver", org.tier, { state = "free_agent", ageMean = 20 })
        PaddockLife.sign(d, org, Contracts.askingWage(d, org.tier), 1, t, nil)
        have = have + 1
    end
    return events
end

-- ---------------------------------------------------------------------------------------------------------------
-- Folds
-- ---------------------------------------------------------------------------------------------------------------

function PaddockLife.fold(org, t)
    local world = w()
    org.lifecycle, org.foldedAt = "folded", t
    local events = {}
    for _, p in ipairs(World.members(world, org.id)) do
        if p.state == "active" then
            if p.role == "driver" then PaddockLife.release(p, nil, t, "fold")
            else p.state = "retired"; p.orgId = nil; PaddockStore.markPerson(p.id) end
        end
    end
    for _, sid in ipairs(org.sponsorIds or {}) do
        local s = world.sponsors[sid]
        if s then s.orgId = nil; PaddockStore.markSponsor(sid) end
    end
    org.sponsorIds = {}
    if org.humanManagerDriverId then PaddockManager.endTenure(org, "fold", t) end
    World.invalidate(world)
    PaddockStore.markOrg(org.id)
    events[#events + 1] = Tape.event("fold", org.id, t, { entities = { { "org", org.id } },
        facts = { org = org.name, tier = org.tier, seasons = org.seasonsActive or 1, replacement = "a new team at the next Cup" } })
    log("FOLD %s (%s) after %d days in the red", org.id, org.name, org.redDays or 0)
    return events
end

--- Refill folded slots with new organizations (at a Cup boundary, doc 44 §4.4).
local function replaceFolded(t)
    local world = w()
    local events = {}
    for _, oid in ipairs(world.orgOrder) do
        local o = world.orgs[oid]
        if o.lifecycle == "folded" and not (o.evidence and o.evidence.replacedBy) then
            local n = World.newOrg(world, o.tier, o.seriesId, { origin = "replacement", seasonsActive = 0 })
            n.foundedSeason = world.seasonId
            o.evidence = o.evidence or {}
            o.evidence.replacedBy = n.id
            PaddockStore.markOrg(o.id)
            World.reindex(world)
            PaddockLife.reseat(n)
            PaddockStore.markOrg(n.id)
            for _, p in ipairs(World.members(world, n.id)) do PaddockStore.markPerson(p.id) end
            Wait(0)                                   -- a reindex walks the whole cast
            for _, sid in ipairs(n.sponsorIds) do PaddockStore.markSponsor(sid) end
            events[#events + 1] = Tape.event("founded", n.id, t, { entities = { { "org", n.id } },
                facts = { org = n.name, tier = Season.TIERS[n.tier].label, founder = PaddockWorld.personName(n.ownerId) } })
            Wait(0)
        end
    end
    return events
end

-- ---------------------------------------------------------------------------------------------------------------
-- Daily
-- ---------------------------------------------------------------------------------------------------------------

function PaddockLife.daily(t)
    local world = w()
    local day = Clock.eastern(t).dayIndex
    if world.dayIndexApplied == day then return false end
    local y = U.yielder(4)
    for _, pid in ipairs(world.personOrder) do
        local p = world.people[pid]
        if p.role == "driver" and p.state ~= "retired" and p.attrs then
            local org = p.orgId and world.orgs[p.orgId]
            Progression.dayDriver(world, p, { facility = org and org.facility or 40,
                momentum = Progression.form((p.evidence or {}).recent or {}, 10) })
            PaddockStore.markPerson(pid)
            y()
        end
    end
    local events = {}
    for _, oid in ipairs(world.orgOrder) do
        local o = world.orgs[oid]
        if o.lifecycle == "active" then
            local lines = Finance.dayLines(world, o)
            local net = Finance.sum(lines)
            o.cash = (o.cash or 0) + net
            if o.humanManagerDriverId then
                for _, l in ipairs(lines) do PaddockManager.book(o, l.kind, l.amount, l.kind .. ":" .. o.id .. ":" .. day, tostring(day)) end
                PaddockManager.digest(o, net, day)
            end
            if Finance.tickSolvency(o) then
                for _, e in ipairs(PaddockLife.fold(o, t)) do events[#events + 1] = e end
            end
            PaddockStore.markOrg(oid)
            y()
        end
    end
    world.dayIndexApplied = day
    PaddockStore.markMeta()
    PaddockStory.record(events)
    PaddockStore.flush()
    log("daily tick day=%d applied", day)
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Cup boundary
-- ---------------------------------------------------------------------------------------------------------------

local ARCHIVE_DRIVER = [[INSERT INTO paddock_standing (server_id, season_id, cup_id, series_id, entity_kind, entity_id, pos, points,
    wins, podiums, starts, dnfs)
    SELECT server_id, season_id, ?, series_id, 'driver', person_id, 0, SUM(points), SUM(position = 1 AND state = 'finished'),
        SUM(position <= 3 AND state = 'finished'), COUNT(*), SUM(state <> 'finished')
    FROM paddock_result WHERE server_id = ? AND season_id = ? AND (? = '' OR cup_id = ?)
    GROUP BY server_id, season_id, series_id, person_id
    ON DUPLICATE KEY UPDATE points = VALUES(points), wins = VALUES(wins), podiums = VALUES(podiums), starts = VALUES(starts),
        dnfs = VALUES(dnfs)]]
local ARCHIVE_ORG = ARCHIVE_DRIVER:gsub("'driver', person_id", "'org', org_id"):gsub("series_id, person_id", "series_id, org_id")

--- Standings rows for a series from the database (driver or org), best first.
function PaddockLife.standings(kind, seasonId, seriesId, cupId, limit)
    local col = kind == "org" and "org_id" or "person_id"
    local rows = MySQL.query.await(([[SELECT %s AS id, SUM(points) AS points, SUM(position = 1 AND state = 'finished') AS wins,
            SUM(position <= 3 AND state = 'finished') AS podiums, COUNT(*) AS starts, SUM(state <> 'finished') AS dnfs,
            MIN(IF(state = 'finished', position, 99)) AS best
        FROM paddock_result WHERE server_id = ? AND season_id = ? AND series_id = ? AND (? = '' OR cup_id = ?)
        GROUP BY %s ORDER BY points DESC, wins DESC, podiums DESC, best ASC, id ASC LIMIT ?]]):format(col, col),
        { U.sid(), seasonId, seriesId, cupId or "", cupId or "", limit or 40 }) or {}
    for i, r in ipairs(rows) do
        r.pos = i
        for _, k in ipairs({ "points", "wins", "podiums", "starts", "dnfs", "best" }) do r[k] = tonumber(r[k]) or 0 end
    end
    return rows
end

local function titles(kind, seasonId, cupId, t)
    local events = {}
    local world = w()
    for id, s in pairs(world.series) do
        Wait(0)                                       -- fifteen series (L236)
        local top = PaddockLife.standings("driver", seasonId, id, cupId, 1)[1]
        if top and top.points > 0 then
            local p = world.people[top.id]
            if p then
                if kind == "cup_title" then
                    local cupNo = tonumber(tostring(cupId):match("C(%d+)$")) or 0
                    events[#events + 1] = Tape.event("cup_title", cupId .. ":" .. id, t, {
                        entities = { { "person", p.id }, { "org", p.orgId } },
                        facts = { tier = s.tier, driver = p.display, org = PaddockWorld.orgName(p.orgId), series = s.name,
                            cup = "Cup " .. cupNo, points = top.points } })
                else
                    events[#events + 1] = Tape.event("season_title", seasonId .. ":" .. id, t, {
                        entities = { { "person", p.id }, { "org", p.orgId } },
                        facts = { tier = s.tier, driver = p.display, org = PaddockWorld.orgName(p.orgId), series = s.name,
                            season = seasonId, points = top.points } })
                end
            end
        end
    end
    return events
end

local function orgStanding(org, seasonId)
    local rows = PaddockLife.standings("org", seasonId, org.seriesId, "", 40)
    for _, r in ipairs(rows) do if r.id == org.id then return r.pos, #rows end end
    return nil, #rows
end

--- An NPC owner's week: score the options and act on the best (two, if ambitious).
local function ownerDecides(org, t, medians)
    local world = w()
    local owner = world.people[org.ownerId]
    local drivers = World.drivers(world, org.id)
    table.sort(drivers, function(a, b) return Attr.rating(a.attrs) < Attr.rating(b.attrs) end)
    local fas = freeAgentsBest()
    local standing, fieldSize = orgStanding(org, world.seasonId)
    local expected = 0
    for _, d in ipairs(drivers) do expected = expected + Attr.rating(d.attrs) end
    expected = #drivers > 0 and expected / #drivers or 50
    local record = standing and ((expected - (medians[org.tier] or 50)) / 20 - (standing - (fieldSize or 10) / 2) / math.max(1, (fieldSize or 10) / 2)) or 0
    if record > 1 then record = 1 elseif record < -1 then record = -1 end
    local ctx = { drivers = drivers, freeAgents = fas, standing = standing, tierMedianRating = medians[org.tier],
        seasonOrdinal = world.seasonOrdinal, managerRecord = -record, tierCashFloor = World.TIER_CASH[org.tier][1] }
    local ranked = Principal.decide(world, org, ctx)
    local takes = (owner and owner.principal and (owner.principal.ambition or 50) > 65) and 2 or 1
    local events = {}
    local rng = Hash.stream(world.seed, "decide", org.id, world.cupId)
    for i = 1, math.min(takes, #ranked) do
        local a = ranked[i]
        if a.kind == "sign_driver" and a.target and world.people[a.target] and world.people[a.target].state == "free_agent" then
            local d = world.people[a.target]
            local wage = Contracts.askingWage(d, org.tier)
            if rng() < Contracts.willingness(d, { tier = org.tier, wage = wage, prestige = org.prestige }, nil) then
                events[#events + 1] = PaddockLife.sign(d, org, wage, Contracts.lengthFor(owner and owner.principal, rng), t, nil)
            end
        elseif a.kind == "release_driver" and a.target and world.people[a.target] then
            local d = world.people[a.target]
            events[#events + 1] = PaddockLife.release(d, org, t, "released")
            local fa = a.then_sign and world.people[a.then_sign]
            if fa and fa.state == "free_agent" then
                events[#events + 1] = PaddockLife.sign(fa, org, Contracts.askingWage(fa, org.tier), Contracts.lengthFor(owner and owner.principal, rng), t, nil)
            end
        elseif a.kind == "extend_driver" and a.target and world.people[a.target] then
            local d = world.people[a.target]
            d.contractEnds = world.seasonOrdinal + Contracts.lengthFor(owner and owner.principal, rng)
            PaddockStore.markPerson(d.id)
        elseif a.kind == "invest_dev" and a.area then
            local _, gained, spent = Car.invest(org.car, a.area, a.cost)
            org.cash = (org.cash or 0) - (spent or 0)
            org.evidence = org.evidence or {}
            org.evidence.devSpendSeason = (org.evidence.devSpendSeason or 0) + (spent or 0)
        elseif a.kind == "fire_manager" and org.managerId and not org.humanManagerDriverId then
            local old = world.people[org.managerId]
            if old then old.state = "retired"; old.orgId = nil; PaddockStore.markPerson(old.id) end
            local nm = World.newPerson(world, "manager", org.tier, { orgId = org.id, seat = "manager" })
            org.managerId = nm.id
            PaddockStore.markPerson(nm.id)
            org.evidence = org.evidence or {}
            org.evidence.firings = (org.evidence.firings or 0) + 1
            org.evidence.lastFiringSeason = world.seasonOrdinal
            events[#events + 1] = Tape.event("manager_fired", org.id .. ":" .. (old and old.id or "-"), t, {
                entities = { { "org", org.id }, { "person", old and old.id } },
                facts = { tier = org.tier, org = org.name, manager = old and old.display, owner = owner and owner.display } })
            events[#events + 1] = Tape.event("manager_hired", org.id .. ":" .. nm.id, t, {
                entities = { { "org", org.id }, { "person", nm.id } }, facts = { tier = org.tier, org = org.name, manager = nm.display } })
            World.invalidate(world)
        end
    end
    PaddockStore.markOrg(org.id)
    return events
end

function PaddockLife.cupBoundary(t)
    local world = w()
    local cup = Season.cupOf(t)
    if world.cupId == cup.cupId then return false end
    local previous = world.cupId
    if not previous or previous == "" then
        -- genesis: a world that has just been born does not open with a week of sackings
        world.cupId = cup.cupId
        PaddockStore.markMeta()
        PaddockStore.flush()
        return false
    end
    local events = {}
    do
        local prevSeason = tostring(previous):match("^(%d+%-S%d)") or world.seasonId
        pcall(MySQL.update.await, ARCHIVE_DRIVER, { previous, U.sid(), prevSeason, previous, previous })
        pcall(MySQL.update.await, ARCHIVE_ORG, { previous, U.sid(), prevSeason, previous, previous })
        for _, e in ipairs(titles("cup_title", prevSeason, previous, t)) do events[#events + 1] = e end
    end
    -- queued human-manager roster moves land now (doc 44 §10)
    for i, oid in ipairs(world.orgOrder) do
        if i % 40 == 0 then Wait(0) end
        local o = world.orgs[oid]
        if o.lifecycle == "active" and o.humanManagerDriverId and o.pending and #o.pending > 0 then
            for _, e in ipairs(PaddockManager.applyPending(o, t)) do events[#events + 1] = e end
        end
    end
    local medians = {}
    for _, tier in ipairs(Season.TIER_ORDER) do medians[tier] = tierMedian(tier); Wait(0) end   -- ~1,200 people (L236)
    for _, oid in ipairs(world.orgOrder) do
        local o = world.orgs[oid]
        if o.lifecycle == "active" then
            if o.humanManagerDriverId then
                local fired = PaddockManager.ownerReview(o, t)
                if fired then events[#events + 1] = fired end
            else
                for _, e in ipairs(ownerDecides(o, t, medians)) do events[#events + 1] = e end
            end
            for _, e in ipairs(PaddockLife.fillSeats(o, t)) do events[#events + 1] = e end
            Wait(0)
        end
    end
    for _, e in ipairs(replaceFolded(t)) do events[#events + 1] = e end
    PaddockManager.offers(t)
    world.cupId = cup.cupId
    PaddockStore.markMeta()
    PaddockStory.record(events)
    PaddockStore.flush()
    log("Cup boundary %s -> %s: %d events", tostring(previous), cup.cupId, #events)
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Season rollover
-- ---------------------------------------------------------------------------------------------------------------

function PaddockLife.rollover(t)
    local world = w()
    local cup = Season.cupOf(t)
    if world.seasonId == cup.seasonId then return false end
    local old = world.seasonId
    local events = {}
    pcall(MySQL.update.await, ARCHIVE_DRIVER, { "", U.sid(), old, "", "" })
    pcall(MySQL.update.await, ARCHIVE_ORG, { "", U.sid(), old, "", "" })
    for _, e in ipairs(titles("season_title", old, "", t)) do events[#events + 1] = e end
    -- promotion and relegation from season org standings, divisions merged by points
    local byTier = {}
    for id, s in pairs(world.series) do
        byTier[s.tier] = byTier[s.tier] or {}
        for _, r in ipairs(PaddockLife.standings("org", old, id, "", 40)) do
            local o = world.orgs[r.id]
            if o and o.lifecycle == "active" then byTier[s.tier][#byTier[s.tier] + 1] = r end
        end
    end
    for _, list in pairs(byTier) do
        table.sort(list, function(a, b) if a.points ~= b.points then return a.points > b.points end return a.id < b.id end)
    end
    local plan = Season.rollover(byTier)
    local ups, downs = {}, {}
    for _, m in ipairs(plan) do
        if m.kind == "promoted" then ups[#ups + 1] = m else downs[#downs + 1] = m end
    end
    for i, up in ipairs(ups) do
        local down = downs[i]
        local a, b = world.orgs[up.orgId], down and world.orgs[down.orgId]
        if a and b then
            a.tier, b.tier = up.to, down.to
            a.seriesId, b.seriesId = b.seriesId, a.seriesId
            PaddockStore.markOrg(a.id); PaddockStore.markOrg(b.id)
            events[#events + 1] = Tape.event("promotion", old .. ":" .. a.id, t, { entities = { { "org", a.id } },
                facts = { org = a.name, tier = up.to, fromTier = Season.TIERS[up.from].label, toTier = Season.TIERS[up.to].label } })
            events[#events + 1] = Tape.event("relegation", old .. ":" .. b.id, t, { entities = { { "org", b.id } },
                facts = { org = b.name, tier = down.from, fromTier = Season.TIERS[down.from].label, toTier = Season.TIERS[down.to].label } })
        end
    end
    -- a paddock year passes (doc 44 §5.3)
    world.seasonOrdinal = world.seasonOrdinal + 1
    world.seasonId = cup.seasonId
    world.paddockYear = Season.paddockYear(world.genesisSeasonId, world.seasonId)
    local rng = Hash.stream(world.seed, "rollover", world.seasonId)
    local y = U.yielder(4)
    local medians = {}
    for _, tier in ipairs(Season.TIER_ORDER) do medians[tier] = tierMedian(tier); Wait(0) end
    for _, pid in ipairs(world.personOrder) do
        local p = world.people[pid]
        if p.role == "driver" and p.state ~= "retired" then
            local e = p.evidence or {}
            Progression.seasonDrift(p, { contacts = e.seasonContacts, wins = e.seasonWins, starts = e.seasonStarts, dnfs = e.seasonDnfs })
            e.seasonStarts, e.seasonSum, e.seasonWins, e.seasonAvg, e.seasonDnfs, e.seasonContacts = 0, 0, 0, nil, 0, 0
            e.seasonsAtOrg = (e.seasonsAtOrg or 0) + (p.orgId and 1 or 0)
            e.rivals = {}
            p.evidence = e
            local age = World.age(world, p)
            if rng() < Progression.retireChance(p, age) then
                local org = p.orgId and world.orgs[p.orgId]
                events[#events + 1] = Tape.event("retirement", p.id, t, { entities = { { "person", p.id }, { "org", org and org.id } },
                    facts = { driver = p.display, age = age, starts = e.starts or 0, wins = e.wins or 0, org = org and org.name or "the pool",
                        tier = org and org.tier } })
                if org then PaddockLife.release(p, org, t, "retired") end
                p.state, p.orgId, p.seat = "retired", nil, nil
            elseif p.state == "active" and (p.contractEnds or 0) < world.seasonOrdinal then
                local org = world.orgs[p.orgId or ""]
                local owner = org and world.people[org.ownerId]
                local keep = org and not org.humanManagerDriverId and Attr.rating(p.attrs) >= (medians[org.tier] or 50) - 3
                if keep then
                    p.contractEnds = world.seasonOrdinal + Contracts.lengthFor(owner and owner.principal, rng)
                elseif org and not org.humanManagerDriverId then
                    events[#events + 1] = PaddockLife.release(p, org, t, "contract_expired")
                end
            end
            PaddockStore.markPerson(pid)
            y()
        end
    end
    for _, oid in ipairs(world.orgOrder) do
        local o = world.orgs[oid]
        if o.lifecycle == "active" then
            o.seasonsActive = (o.seasonsActive or 1) + 1
            o.evidence = o.evidence or {}
            if (o.evidence.lastFiringSeason or -1) < world.seasonOrdinal - 1 then
                o.evidence.seasonsWithoutFiring = (o.evidence.seasonsWithoutFiring or 0) + 1
            else
                o.evidence.seasonsWithoutFiring = 0
            end
            o.evidence.devSpendSeason = 0
            Car.depreciate(o.car, 0.25)
            for _, e in ipairs(PaddockLife.fillSeats(o, t)) do events[#events + 1] = e end
            PaddockLife.reseat(o)
            PaddockStore.markOrg(oid)
            y()
        end
    end
    -- keep the free-agent pool alive: rookies arrive every year
    local fa = #World.freeAgents(world)
    for i = fa + 1, World.FREE_AGENTS do
        local p = World.newPerson(world, "driver", (i % 4 == 0) and "regional" or "street", { state = "free_agent", ageMean = 19 })
        PaddockStore.markPerson(p.id)
    end
    World.reindex(world)
    PaddockStore.markMeta()
    PaddockStory.record(events)
    PaddockStore.flush()
    log("SEASON ROLLOVER %s -> %s: year %d, %d events", old, world.seasonId, world.paddockYear, #events)
    return true
end
