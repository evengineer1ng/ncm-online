-- ncm_paddock / server / manager -- manager mode (doc 44 §10, L224.8).
--
-- A human founds a Street org for a fee, or accepts an offer from a personality-driven NPC owner who can later fire
-- them. Managing is the human's ONE team affiliation: the row in `team_affiliation` (schema 046) is written FIRST, in
-- the same transaction as the money, so the unique index -- not this file -- decides whether it may exist.
-- Roster moves queue until the next Cup boundary; money moves are immediate and booked in `paddock_treasury`.
-- Withdrawals are capped per Cup week and taxed (the tax is a sink).
PaddockManager = {}

local U = PaddockUtil
local log = U.logger("manager")
local World = NcmCore.get("paddock.world")
local Season = NcmCore.get("paddock.season")
local Car = NcmCore.get("paddock.car")
local Manager = NcmCore.get("paddock.manager")
local Principal = NcmCore.get("paddock.principal")
local Progression = NcmCore.get("paddock.progression")
local Contracts = NcmCore.get("paddock.contracts")
local Attr = NcmCore.get("paddock.attributes")
local Tape = NcmCore.get("paddock.tape")
local Hash = NcmCore.get("vocabulary.hash")

local function w() return PaddockStore.world end

function PaddockManager.affiliationOf(driverId)
    return MySQL.single.await([[SELECT * FROM team_affiliation WHERE server_id = ? AND ncm_driver_id = ? AND effective_to IS NULL]],
        { U.sid(), driverId })
end

--- Append a treasury line for a human-managed org (idempotent by key).
function PaddockManager.book(org, kind, amount, idem, ref)
    if not org or not org.humanManagerDriverId or (amount or 0) == 0 then return end
    pcall(MySQL.insert.await, [[INSERT IGNORE INTO paddock_treasury (server_id, org_id, kind, amount, idem_key, ref, at)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], { U.sid(), org.id, kind, math.floor(amount), idem:sub(1, 190), ref, U.now() })
end

function PaddockManager.digest(org, net, day)
    PaddockStory.push(org.humanManagerDriverId, ("%s: %s%d today"):format(org.name, net >= 0 and "+" or "", net),
        ("Wages, sponsors and upkeep settled. Treasury: %d eddies."):format(math.floor(org.cash or 0)),
        { solicited = true, thread = "paddock:org", fromId = org.id, refKind = "paddock_org", refId = org.id })
end

local function hireNpcManager(org)
    local nm = World.newPerson(w(), "manager", org.tier, { orgId = org.id, seat = "manager" })
    org.managerId = nm.id
    PaddockStore.markPerson(nm.id)
end

--- End a human's tenure (resign, fired, fold). The org carries on under an NPC manager unless it folded.
function PaddockManager.endTenure(org, reason, t)
    local driverId = org.humanManagerDriverId
    if not driverId then return end
    pcall(MySQL.update.await, [[UPDATE team_affiliation SET effective_to = ?, end_reason = ? WHERE server_id = ? AND ncm_driver_id = ?
        AND paddock_org_id = ? AND effective_to IS NULL]], { t, reason, U.sid(), driverId, org.id })
    if reason == "fold" then
        pcall(MySQL.update.await, [[INSERT INTO paddock_manager (server_id, ncm_driver_id, cooldown_until_season) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE cooldown_until_season = VALUES(cooldown_until_season)]],
            { U.sid(), driverId, (w().seasonOrdinal or 0) + 1 })
    end
    org.humanManagerDriverId = nil
    org.pending = {}
    if org.lifecycle == "active" then hireNpcManager(org) end
    PaddockStore.markOrg(org.id)
    PaddockStory.push(driverId, reason == "fired" and ("You are out at " .. org.name) or (org.name .. ": your tenure ends"),
        reason == "fold" and "The team could not pay its bills. You can found or take another team after a season."
            or (reason == "fired" and "The owner has made a change. The Paddock remembers who you were." or "You have stepped down."),
        { solicited = true, thread = "paddock:org", fromId = org.id })
end

local function streetSeriesWithRoom()
    local best, bestN
    for _, sid in ipairs(Season.seriesIds("street")) do
        local n = #World.orgsInSeries(w(), sid)
        if not bestN or n < bestN then best, bestN = sid, n end
    end
    return best
end

--- Found a Street org. Returns true, org or false, reason.
function PaddockManager.found(pid, name)
    local d = PaddockPlayers.driver(pid)
    if not d then return false, "no_driver" end
    local world = w()
    local t = U.now()
    local fee = PaddockSettings.get("managerFoundFee", 5000)
    local grant = PaddockSettings.get("managerFoundGrant", 15000)
    local mgr = MySQL.single.await("SELECT * FROM paddock_manager WHERE server_id = ? AND ncm_driver_id = ?", { U.sid(), d.ncmDriverId })
    local ok, clean = Manager.validateFound({ name = name, affiliated = PaddockManager.affiliationOf(d.ncmDriverId) ~= nil,
        cooldownUntilSeason = mgr and tonumber(mgr.cooldown_until_season), seasonOrdinal = world.seasonOrdinal,
        balance = PaddockWallet.balance(d.ncmDriverId), fee = fee, takenNames = world.takenOrgNames })
    if not ok then return false, clean end
    local orgId = string.format("o%03d", (world.nextOrg or 0) + 1)
    local feeIdem = "paddock:found:" .. d.ncmDriverId .. ":" .. orgId
    local tx = PaddockWallet.withBalanceLocks({
        PaddockWallet.debitStep(d.ncmDriverId, "paddock_found", fee, feeIdem, orgId, "Founded a Paddock team"),
        { query = [[INSERT INTO team_affiliation (affiliation_id, server_id, ncm_driver_id, circuit, paddock_org_id, role, effective_from)
            SELECT ?, ?, ?, 'npc', ?, 'manager', ? FROM DUAL WHERE EXISTS (SELECT 1 FROM ledger WHERE idem_key = ?)]],
          values = { U.uuid(), U.sid(), d.ncmDriverId, orgId, t, feeIdem } },
    }, { d.ncmDriverId })
    local okTx, err = MySQL.transaction.await(tx)
    if not okTx then return false, "one_team_rule_or_" .. tostring(err) end
    if not PaddockWallet.landed(feeIdem) then return false, "insufficient_funds" end
    local org = World.newOrg(world, "street", streetSeriesWithRoom(), { name = clean, origin = "human_founded", noManager = true,
        noDrivers = true, cash = fee + grant, seasonsActive = 0 })
    if org.id ~= orgId then   -- another org was minted in between: point the affiliation at the real one
        pcall(MySQL.update.await, "UPDATE team_affiliation SET paddock_org_id = ? WHERE server_id = ? AND ncm_driver_id = ? AND effective_to IS NULL",
            { org.id, U.sid(), d.ncmDriverId })
    end
    org.humanManagerDriverId = d.ncmDriverId
    org.foundedSeason = world.seasonId
    local events = {}
    for i = 1, 2 do
        local rookie = World.newPerson(world, "driver", "street", { state = "free_agent", ageMean = 19 })
        PaddockLife.sign(rookie, org, Contracts.askingWage(rookie, "street"), 1, t, nil)
        rookie.seat = (i == 1) and "race1" or "reserve"
        PaddockStore.markPerson(rookie.id)
    end
    World.reindex(world)
    PaddockStore.markOrg(org.id)
    for _, p in ipairs(World.members(world, org.id)) do PaddockStore.markPerson(p.id) end
    for _, sid in ipairs(org.sponsorIds) do PaddockStore.markSponsor(sid) end
    PaddockStore.markMeta()
    PaddockStore.flush()
    PaddockManager.book(org, "founding_fee", fee, "found:" .. org.id, d.ncmDriverId)
    PaddockManager.book(org, "founding_grant", grant, "grant:" .. org.id, "backer")
    events[#events + 1] = Tape.event("founded", org.id, t, { entities = { { "org", org.id }, { "human", d.ncmDriverId } },
        facts = { org = org.name, tier = "Street", founder = d.display } })
    PaddockStory.record(events)
    log("FOUNDED %s '%s' by %s", org.id, org.name, d.ncmDriverId:sub(1, 8))
    return true, org
end

--- Accept an open offer from an NPC owner.
function PaddockManager.accept(pid, offerId)
    local d = PaddockPlayers.driver(pid)
    if not d then return false, "no_driver" end
    local t = U.now()
    local offer = MySQL.single.await("SELECT * FROM paddock_manager_offer WHERE offer_id = ? AND server_id = ? AND ncm_driver_id = ?",
        { tostring(offerId or ""), U.sid(), d.ncmDriverId })
    if not offer or offer.state ~= "open" then return false, "no_offer" end
    if tonumber(offer.expires_at) < t then return false, "offer_expired" end
    local org = w().orgs[offer.org_id]
    if not org or org.lifecycle ~= "active" or org.humanManagerDriverId then return false, "position_filled" end
    local okTx, err = MySQL.transaction.await({
        { query = [[INSERT INTO team_affiliation (affiliation_id, server_id, ncm_driver_id, circuit, paddock_org_id, role, effective_from)
            VALUES (?, ?, ?, 'npc', ?, 'manager', ?)]], values = { U.uuid(), U.sid(), d.ncmDriverId, org.id, t } },
        { query = "UPDATE paddock_manager_offer SET state = 'accepted' WHERE offer_id = ? AND state = 'open'", values = { offer.offer_id } },
    })
    if not okTx then return false, "one_team_rule" end
    local old = w().people[org.managerId or ""]
    if old then old.state, old.orgId = "retired", nil; PaddockStore.markPerson(old.id) end
    org.managerId = nil
    org.humanManagerDriverId = d.ncmDriverId
    World.invalidate(w())
    PaddockStore.markOrg(org.id)
    PaddockStore.flush()
    PaddockManager.book(org, "opening_balance", org.cash or 0, "opening:" .. org.id .. ":" .. d.ncmDriverId .. ":" .. t, "inherited")
    PaddockStory.record({ Tape.event("manager_hired", org.id .. ":" .. d.ncmDriverId .. ":" .. t, t, {
        entities = { { "org", org.id }, { "human", d.ncmDriverId } }, facts = { tier = org.tier, org = org.name, manager = d.display } }) })
    return true, org
end

local function withdrawnThisWeek(org)
    local cup = Season.cupOf(U.now())
    return -(tonumber(MySQL.scalar.await([[SELECT COALESCE(SUM(amount),0) FROM paddock_treasury WHERE server_id = ? AND org_id = ?
        AND kind = 'withdrawal' AND at >= ?]], { U.sid(), org.id, cup.cupStartUtc })) or 0)
end

--- A manager's action. Roster moves queue; money moves settle now. Returns true, message or false, reason.
function PaddockManager.act(pid, action, args)
    local d = PaddockPlayers.driver(pid)
    if not d then return false, "no_driver" end
    local org = PaddockWorld.orgManagedBy(d.ncmDriverId)
    if action == "found" then return PaddockManager.found(pid, args and args.name) end
    if action == "accept" then return PaddockManager.accept(pid, args and args.offerId) end
    if not org then return false, "not_a_manager" end
    local world = w()
    local t = U.now()
    local ok, plan = Manager.validate(action, { org = org, world = world, managerDriverId = d.ncmDriverId,
        treasury = org.cash or 0, args = args or {}, withdrawnThisWeek = (action == "withdraw") and withdrawnThisWeek(org) or 0,
        caps = { weeklyCap = PaddockSettings.get("managerWithdrawWeeklyCap", 2000), tax = PaddockSettings.get("managerWithdrawTax", 0.30) } })
    if not ok then return false, plan end
    if plan.kind == "sign" or plan.kind == "release" or plan.kind == "seat" then
        org.pending = org.pending or {}
        if #org.pending >= 6 then return false, "too_many_pending" end
        org.pending[#org.pending + 1] = plan
        PaddockStore.markOrg(org.id)
        PaddockStore.flush()
        return true, "queued: takes effect at the next Cup boundary"
    elseif plan.kind == "develop" then
        local _, gained, spent = Car.invest(org.car, plan.area, plan.eddies)
        org.cash = (org.cash or 0) - spent
        PaddockManager.book(org, "development", -spent, "dev:" .. org.id .. ":" .. t .. ":" .. plan.area, plan.area)
        for id, delta in pairs(Manager.reactions(plan, world, org)) do
            local p = world.people[id]
            if p then p.morale = Attr.clamp((p.morale or 50) + delta, 5, 95); PaddockStore.markPerson(id) end
        end
        PaddockStore.markOrg(org.id)
        PaddockStore.flush()
        return true, gained > 0 and ("%s up %d level(s)"):format(plan.area, gained) or "invested; the next level needs more"
    elseif plan.kind == "hire_staff" then
        local old = world.people[plan.role == "engineer" and org.engineerId or org.strategistId]
        if old then old.state, old.orgId = "retired", nil; PaddockStore.markPerson(old.id) end
        local p = World.newPerson(world, plan.role, org.tier, { orgId = org.id, seat = "staff" })
        if plan.role == "engineer" then org.engineerId = p.id else org.strategistId = p.id end
        org.cash = (org.cash or 0) - plan.fee
        PaddockManager.book(org, "staff_fee", -plan.fee, "staff:" .. org.id .. ":" .. t, plan.role)
        PaddockStore.markPerson(p.id)
        PaddockStore.markOrg(org.id)
        PaddockStore.flush()
        return true, ("hired %s as %s"):format(p.display, plan.role)
    elseif plan.kind == "sign_sponsor" then
        local s = world.sponsors[plan.sponsorId]
        s.orgId = org.id
        org.sponsorIds[#org.sponsorIds + 1] = s.id
        PaddockStore.markSponsor(s.id)
        PaddockStore.markOrg(org.id)
        PaddockStore.flush()
        PaddockStory.record({ Tape.event("sponsor_signed", s.id .. ":" .. org.id, t, { entities = { { "org", org.id } },
            facts = { tier = org.tier, sponsor = s.name, org = org.name } }) })
        return true, s.name .. " is on the car"
    elseif plan.kind == "deposit" then
        local idem = "paddock:deposit:" .. org.id .. ":" .. tostring(args and args.idem or t):sub(1, 40)
        local okTx, err = MySQL.transaction.await(PaddockWallet.withBalanceLocks({
            PaddockWallet.debitStep(d.ncmDriverId, "paddock_deposit", plan.eddies, idem, org.id, "Into the team treasury"),
            { query = [[INSERT IGNORE INTO paddock_treasury (server_id, org_id, kind, amount, idem_key, ref, at)
                SELECT ?, ?, 'deposit', ?, ?, ?, ? FROM DUAL WHERE EXISTS (SELECT 1 FROM ledger WHERE idem_key = ?)]],
              values = { U.sid(), org.id, plan.eddies, idem, d.ncmDriverId, t, idem } },
        }, { d.ncmDriverId }))
        if not okTx then return false, "transaction:" .. tostring(err) end
        if not PaddockWallet.landed(idem) then return false, "insufficient_funds" end
        org.cash = (org.cash or 0) + plan.eddies
        PaddockStore.markOrg(org.id)
        PaddockStore.flush()
        return true, ("deposited %d"):format(plan.eddies)
    elseif plan.kind == "withdraw" then
        local idem = "paddock:withdraw:" .. org.id .. ":" .. tostring(args and args.idem or t):sub(1, 40)
        local okTx, err = MySQL.transaction.await({
            { query = [[INSERT IGNORE INTO paddock_treasury (server_id, org_id, kind, amount, idem_key, ref, at) VALUES (?, ?, 'withdrawal', ?, ?, ?, ?)]],
              values = { U.sid(), org.id, -plan.eddies, idem, d.ncmDriverId, t } },
            PaddockWallet.creditStep(d.ncmDriverId, "paddock_withdrawal", plan.net, idem, org.id,
                ("Team treasury, after %d tax"):format(plan.tax)),
        })
        if not okTx then return false, "transaction:" .. tostring(err) end
        org.cash = (org.cash or 0) - plan.eddies
        PaddockStore.markOrg(org.id)
        PaddockStore.flush()
        return true, ("withdrew %d, %d after tax"):format(plan.eddies, plan.net)
    elseif plan.kind == "resign" then
        PaddockManager.endTenure(org, "resigned", t)
        PaddockStore.flush()
        return true, "you have stepped down"
    end
    return false, "unsupported"
end

--- Apply a human org's queued roster moves (Cup boundary). Returns tape events.
function PaddockManager.applyPending(org, t)
    local world = w()
    local events = {}
    local rng = Hash.stream(world.seed, "pending", org.id, t)
    for _, plan in ipairs(org.pending or {}) do
        if plan.kind == "sign" then
            local dr = world.people[plan.driverId]
            if dr and (dr.state == "free_agent" or Contracts.poachable(dr, world.seasonOrdinal)) and dr.orgId ~= org.id then
                local from = dr.orgId and world.orgs[dr.orgId]
                if rng() < (plan.willingness or 0.5) then
                    if from then PaddockLife.release(dr, from, t, "transfer") end
                    events[#events + 1] = PaddockLife.sign(dr, org, plan.wage, plan.seasons, t, from)
                else
                    PaddockStory.push(org.humanManagerDriverId, dr.display .. " said no",
                        "The offer was not enough to move them. Try more money, a longer deal, or a better car.",
                        { solicited = true, thread = "paddock:org", fromId = org.id })
                end
            end
        elseif plan.kind == "release" then
            local dr = world.people[plan.driverId]
            if dr and dr.orgId == org.id then
                org.cash = (org.cash or 0) - (plan.severance or 0)
                PaddockManager.book(org, "severance", -(plan.severance or 0), "sev:" .. dr.id .. ":" .. t, dr.id)
                events[#events + 1] = PaddockLife.release(dr, org, t, "released")
            end
        elseif plan.kind == "seat" then
            local dr = world.people[plan.driverId]
            if dr and dr.orgId == org.id then
                for _, other in ipairs(World.drivers(world, org.id)) do
                    if other.id ~= dr.id and other.seat == plan.seat and plan.seat ~= "reserve" then other.seat = dr.seat; PaddockStore.markPerson(other.id) end
                end
                dr.seat = plan.seat
                PaddockStore.markPerson(dr.id)
            end
        end
        for id, delta in pairs(Manager.reactions(plan, world, org)) do
            local p = world.people[id]
            if p then p.morale = Attr.clamp((p.morale or 50) + delta, 5, 95); PaddockStore.markPerson(id) end
        end
    end
    org.pending = {}
    PaddockStore.markOrg(org.id)
    return events
end

--- An inherited org's owner reviews the human manager at the Cup boundary. Returns a tape event when fired.
function PaddockManager.ownerReview(org, t)
    if org.origin == "human_founded" then return nil end
    local world = w()
    local rows = PaddockLife.standings("org", world.seasonId, org.seriesId, "", 40)
    local pos, n
    for _, r in ipairs(rows) do if r.id == org.id then pos = r.pos end end
    n = #rows
    if not pos or n < 3 then return nil end
    local expected = math.max(1, math.floor(n * (1 - (org.prestige or 50) / 100)) + 1)
    local record = Manager.record(expected, pos, n)
    pcall(MySQL.update.await, [[INSERT INTO paddock_manager (server_id, ncm_driver_id, record) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE record = VALUES(record)]], { U.sid(), org.humanManagerDriverId, record })
    local owner = world.people[org.ownerId]
    if not Principal.firesHumanManager(owner, org, record) then return nil end
    local human = org.humanManagerDriverId
    local name = tostring(MySQL.scalar.await("SELECT display FROM driver_profile WHERE ncm_driver_id = ? AND server_id = ?", { human, U.sid() }) or "their manager")
    PaddockManager.endTenure(org, "fired", t)
    return Tape.event("manager_fired", org.id .. ":" .. human .. ":" .. t, t, { entities = { { "org", org.id }, { "human", human } },
        facts = { tier = org.tier, org = org.name, manager = name, owner = owner and owner.display } })
end

--- NPC owners with struggling teams approach humans the Paddock has noticed (spotlight) or who have managed well.
function PaddockManager.offers(t)
    local world = w()
    local rows = MySQL.query.await([[SELECT s.subject_id AS driver_id, s.score, m.record, m.seasons_managed FROM paddock_spotlight s
        LEFT JOIN paddock_manager m ON m.server_id = s.server_id AND m.ncm_driver_id = s.subject_id
        WHERE s.server_id = ? AND s.subject_kind = 'driver' AND s.score >= 25]], { U.sid() }) or {}
    for _, r in ipairs(rows) do
        local human = { spotlight = tonumber(r.score), managerRecord = tonumber(r.record), managerSeasons = tonumber(r.seasons_managed) }
        if Manager.offerEligible(human) and not PaddockManager.affiliationOf(r.driver_id) then
            local open = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM paddock_manager_offer WHERE server_id = ? AND ncm_driver_id = ?
                AND state = 'open' AND expires_at > ?]], { U.sid(), r.driver_id, t })) or 0
            if open == 0 then
                local pick
                for _, oid in ipairs(world.orgOrder) do
                    local o = world.orgs[oid]
                    local owner = world.people[o.ownerId]
                    if o.lifecycle == "active" and not o.humanManagerDriverId and owner and owner.principal
                        and (owner.principal.ambition or 50) >= 55 and (o.evidence and (o.evidence.firings or 0) > 0 or (o.lowCashDays or 0) > 0) then
                        pick = o
                        break
                    end
                end
                if pick then PaddockManager.makeOffer(r.driver_id, pick, t) end
            end
        end
    end
end

function PaddockManager.makeOffer(driverId, org, t)
    local id = U.uuid()
    pcall(MySQL.insert.await, [[INSERT INTO paddock_manager_offer (offer_id, server_id, ncm_driver_id, org_id, from_person_id, state,
        created_at, expires_at) VALUES (?, ?, ?, ?, ?, 'open', ?, ?)]], { id, U.sid(), driverId, org.id, org.ownerId or "", t, t + 7 * 86400 })
    PaddockStory.push(driverId, PaddockWorld.personName(org.ownerId) .. " wants a word",
        ("%s (%s) is looking for a manager. The offer stands for a week: PADDOCK > MY ORG."):format(org.name, Season.TIERS[org.tier].label),
        { thread = "paddock:offer", fromId = org.ownerId, refKind = "paddock_offer", refId = id })
    return id
end
