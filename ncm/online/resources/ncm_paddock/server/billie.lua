-- ncm_paddock / server / billie -- BookQueen Billie's board on NPC races (doc 44 §9, L224.4, L226).
--
-- She takes positions on the NPC circuit and never on a human: not on a person (there are none in these races and
-- never will be), not on any driver of a HUMAN-MANAGED org (refused for everyone -- a manager could throw a race),
-- and never for a manager in a series their own org races in. Lines are priced from a Monte Carlo of the sim run on
-- its OWN random streams: the race's real seed is secret and never touches pricing, so a price cannot leak the
-- result. Stakes, payouts and refunds are ledger rows with idem keys, written under the balance lock.
PaddockBillie = {}

local U = PaddockUtil
local log = U.logger("billie")
local Hash = NcmCore.get("vocabulary.hash")
local Sim = NcmCore.get("paddock.sim")
local Pricing = NcmCore.get("paddock.pricing")
local Clock = NcmCore.get("world.clock")

-- Her voice (CHARACTER_ARCHAEOLOGY IV.7): positions and paper, never a "Cancel Bet" button.
PaddockBillie.VOICE = {
    "I take positions. Sometimes they're yours.",
    "Paper's paper, choom. Read it twice, sign it once.",
    "I don't do sure things. Neither do they.",
    "Rain changes everything except my margins.",
    "Street money moves at night. So do I.",
}
PaddockBillie.REFUSAL = "Not that one. Somebody I can't see is holding the wheel, and I don't write paper on people."

local function lineId(raceId, market, a, b)
    return raceId .. ":" .. market .. ":" .. a .. (b and (":" .. b) or "")
end

local pricing = {}

--- Price a race: build its likely field, simulate it N times on pricing streams, write versioned lines. (The field is
--- frozen later, at T-1 with entries -- PaddockHumans.tick.)
function PaddockBillie.price(race)
    if race.state ~= "scheduled" or pricing[race.raceId] then return end
    if not PaddockSettings.get("billieEnabled", true) then
        race.state = "priced"
        pcall(MySQL.update.await, "UPDATE paddock_race SET state = 'priced' WHERE server_id = ? AND race_id = ?", { U.sid(), race.raceId })
        return
    end
    pricing[race.raceId] = true
    local field = PaddockRaces.buildField(race)
    local cond, route, base = PaddockRaces.setup(race)
    local ids = {}
    for i, e in ipairs(field) do ids[i] = e.id end
    local pricer = Pricing.newPricer(ids)
    local n = PaddockSettings.get("billieMcSims", 400)
    local per = PaddockSettings.get("billieSimsPerYield", 4)
    local pricingSeed = Hash.seed("billie", race.raceId, race.commit)     -- public inputs only
    local flagM = PaddockRaces.flagLength(route)
    for k = 1, n do
        local r = Sim.simulate(field, route, cond, Hash.stream(pricingSeed, k), { baseSec = base, light = true, tier = race.tier })
        NcmCore.get("paddock.mixed").flagEntrants(r.entrants, flagM)         -- priced on the race's own rule (the flag)
        local finished = {}
        for _, e in ipairs(r.entrants) do if e.state == "finished" then finished[e.id] = true end end
        pricer.add(r.order, finished)
        if k % per == 0 then Wait(0) end
    end
    local entrants = {}
    for i, e in ipairs(field) do entrants[i] = { id = e.id, orgId = e.orgId, humanManaged = e.humanManaged } end
    local lines = Pricing.lines(entrants, pricer.probs(), { overround = PaddockSettings.get("billieOverround", 0.10) })
    local st = {}
    for _, l in ipairs(lines) do
        st[#st + 1] = { query = [[INSERT IGNORE INTO paddock_line (server_id, line_id, race_id, market, subject_a, subject_b, prob,
            price, version, refused, state) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, -1), 1, ?, ?)]],
            -- A refused line has no price by design; -1 travels and NULLIF restores the NULL (a nil is a hole).
            values = { U.sid(), lineId(race.raceId, l.market, l.a, l.b), race.raceId, l.market, l.a, l.b or "",
                math.floor((l.prob or 0) * 1e6) / 1e6, l.price or -1, l.refused and 1 or 0,
                (l.refused or not l.price) and "closed" or "open" } }
    end
    st[#st + 1] = { query = "UPDATE paddock_race SET state = 'priced' WHERE server_id = ? AND race_id = ? AND state = 'scheduled'",
        values = { U.sid(), race.raceId } }
    local ok, err = U.transact(st)
    pricing[race.raceId] = nil
    if not ok then log("price %s FAILED: %s", race.raceId, tostring(err)); return end
    if race.state == "scheduled" then race.state = "priced" end
    log("priced %s: %d entrants, %d lines, %d sims", race.raceId, #field, #lines, n)
end

function PaddockBillie.close(race)
    pcall(MySQL.update.await, "UPDATE paddock_line SET state = 'closed' WHERE server_id = ? AND race_id = ? AND state IN ('open','suspended')",
        { U.sid(), race.raceId })
end

function PaddockBillie.winPrice(raceId, personId)
    return tonumber(MySQL.scalar.await("SELECT price FROM paddock_line WHERE server_id = ? AND line_id = ?",
        { U.sid(), lineId(raceId, "win", personId) }))
end

function PaddockBillie.knows(driverId)
    local row = MySQL.single.await([[SELECT state FROM player_contact WHERE ncm_driver_id = ? AND server_id = ? AND contact_id = 'billie']],
        { driverId, U.sid() })
    return row ~= nil and row.state == "known"
end

local function dayStart(t)
    local e = Clock.eastern(t)
    return Clock.utcAt(e.dayIndex, 0)
end

function PaddockBillie.stakedToday(driverId, t)
    return tonumber(MySQL.scalar.await([[SELECT COALESCE(SUM(stake),0) FROM paddock_slip WHERE server_id = ? AND ncm_driver_id = ?
        AND placed_at >= ? AND state <> 'void']], { U.sid(), driverId, dayStart(t) })) or 0
end

function PaddockBillie.caps()
    return { perSlip = PaddockSettings.get("billieSlipCap", 250), daily = PaddockSettings.get("billieDailyCap", 2000),
        maxPayout = PaddockSettings.get("billieMaxPayout", 10000) }
end

--- Write a slip. Returns true, slip or false, reason.
function PaddockBillie.place(pid, req)
    local d = PaddockPlayers.driver(pid)
    if not d then return false, "no_driver" end
    local t = U.now()
    local lid = tostring(req.lineId or "")
    local line = MySQL.single.await("SELECT * FROM paddock_line WHERE server_id = ? AND line_id = ?", { U.sid(), lid })
    if not line then return false, "no_line" end
    local race = PaddockRaces.byId[line.race_id]
    if not race then return false, "closed" end
    local managed = PaddockWorld.orgManagedBy(d.ncmDriverId)
    local ctx = {
        line = { state = line.state, version = tonumber(line.version), price = tonumber(line.price), refused = tonumber(line.refused) == 1,
            market = line.market },
        slip = { stake = math.floor(tonumber(req.stake) or 0), version = tonumber(req.version) },
        caps = PaddockBillie.caps(), stakedToday = PaddockBillie.stakedToday(d.ncmDriverId, t),
        balance = PaddockWallet.balance(d.ncmDriverId), knowsBillie = PaddockBillie.knows(d.ncmDriverId),
        -- L250: and no paper on a league you are entered in yourself
        managesInSeries = (managed ~= nil and managed.seriesId == race.seriesId)
            or (PaddockHumans ~= nil and PaddockHumans.enteredInSeries(d.ncmDriverId, race.seriesId)), now = t, closesAt = race.opensAt,
    }
    local ok, potential = Pricing.validateSlip(ctx)
    if not ok then return false, potential end
    local idem = "billie:" .. d.ncmDriverId .. ":" .. tostring(req.idem or ""):sub(1, 64)
    local existing = MySQL.single.await("SELECT slip_id, state FROM paddock_slip WHERE idem_key = ?", { idem })
    if existing then return true, { slipId = existing.slip_id, duplicate = true } end
    local slipId = U.uuid()
    local stakeIdem = "billie:stake:" .. slipId
    local tx = PaddockWallet.withBalanceLocks({
        PaddockWallet.debitStep(d.ncmDriverId, "billie_stake", ctx.slip.stake, stakeIdem, line.race_id, "Paper with Billie"),
        { query = [[INSERT INTO paddock_slip (slip_id, idem_key, server_id, ncm_driver_id, race_id, line_id, market, subject_a,
            subject_b, line_version, stake, price, potential, placed_at)
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ? FROM DUAL WHERE EXISTS (SELECT 1 FROM ledger WHERE idem_key = ?)]],
          -- subject_b is NULL for win and podium slips; '' travels and NULLIF restores it (a nil is a hole).
          values = { slipId, idem, U.sid(), d.ncmDriverId, line.race_id, lid, line.market, line.subject_a, line.subject_b or "",
              ctx.line.version, ctx.slip.stake, ctx.line.price, potential, t, stakeIdem } },
    }, { d.ncmDriverId })
    local okTx, err = MySQL.transaction.await(tx)
    if not okTx then return false, "transaction:" .. tostring(err) end
    if not PaddockWallet.landed(stakeIdem) then return false, "insufficient_funds" end
    log("slip %s driver=%s line=%s stake=%d @%.2f", slipId:sub(1, 8), d.ncmDriverId:sub(1, 8), lid, ctx.slip.stake, ctx.line.price)
    return true, { slipId = slipId, stake = ctx.slip.stake, price = ctx.line.price, returns = potential }
end

local function settleSlips(raceId, fn)
    local slips = MySQL.query.await("SELECT * FROM paddock_slip WHERE server_id = ? AND race_id = ? AND state = 'open'",
        { U.sid(), raceId }) or {}
    local perDriver = {}
    for _, s in ipairs(slips) do
        local state, payout = fn(s)
        local kind = state == "void" and "billie_refund" or "billie_payout"
        local tx = { { query = "UPDATE paddock_slip SET state = ?, payout = ?, settled_at = ? WHERE slip_id = ? AND state = 'open'",
            values = { state, payout or 0, U.now(), s.slip_id } } }
        if (payout or 0) > 0 then
            tx[#tx + 1] = PaddockWallet.creditStep(s.ncm_driver_id, kind, payout, "billie:" .. kind .. ":" .. s.slip_id, raceId,
                state == "void" and "Billie returns your paper" or "Billie pays out")
        end
        local ok, err = MySQL.transaction.await(tx)
        if not ok then log("settle slip %s FAILED: %s", s.slip_id, tostring(err)) end
        local agg = perDriver[s.ncm_driver_id] or { won = 0, lost = 0, void = 0, paid = 0 }
        agg[state] = (agg[state] or 0) + 1
        agg.paid = agg.paid + (payout or 0)
        perDriver[s.ncm_driver_id] = agg
    end
    return perDriver, #slips
end

--- Settle every open slip on a resolved race. Idempotent: a slip moves out of `open` once, and its payout's idem
--- key makes a retried credit a no-op.
function PaddockBillie.settle(race, byId)
    local perDriver, count = settleSlips(race.raceId, function(s)
        return Pricing.settle({ market = s.market, a = s.subject_a, b = s.subject_b, stake = tonumber(s.stake),
            price = tonumber(s.price) }, { byId = byId })
    end)
    pcall(MySQL.update.await, "UPDATE paddock_line SET state = 'settled' WHERE server_id = ? AND race_id = ?", { U.sid(), race.raceId })
    for driverId, agg in pairs(perDriver) do
        local subject = agg.paid > 0 and ("Billie paid " .. agg.paid .. " eddies") or "Billie kept your paper"
        PaddockStory.push(driverId, subject, ("%s, %s: %d won, %d lost%s."):format(PaddockWorld.seriesName(race.seriesId),
            PaddockWorld.routeName(race.routeId), agg.won or 0, agg.lost or 0, (agg.void or 0) > 0 and (", " .. agg.void .. " returned") or ""),
            { solicited = true, thread = "paddock:billie", fromId = "billie", refKind = "paddock_race", refId = race.raceId })
    end
    if count > 0 then log("settled %d slips on %s", count, race.raceId) end
end

function PaddockBillie.voidRace(race)
    settleSlips(race.raceId, function(s) return "void", tonumber(s.stake) end)
    pcall(MySQL.update.await, "UPDATE paddock_line SET state = 'settled' WHERE server_id = ? AND race_id = ?", { U.sid(), race.raceId })
end
