-- paddock.pricing, finance, progression, principal, manager, spotlight; competition.affiliation (doc 44 §9, §10).
local function stats(T, over)
    local a = {}
    for _, k in ipairs(T.Core.get("paddock.attributes").SKILLS) do a[k] = 50 end
    for _, k in ipairs(T.Core.get("paddock.attributes").TRAITS) do a[k] = 50 end
    for k, v in pairs(over or {}) do a[k] = v end
    return a
end

local function priced(T, n, humanOrg)
    local Sim = T.Core.get("paddock.sim")
    local Pricing = T.Core.get("paddock.pricing")
    local H = T.Core.get("vocabulary.hash")
    local field, entrants, ids = {}, {}, {}
    for i = 1, n do
        field[i] = { id = "d" .. i, orgId = "o" .. math.ceil(i / 2), attrs = stats(T, { pace = 70 - i * 3 }), carPerf = 50 }
        entrants[i] = { id = "d" .. i, orgId = field[i].orgId, humanManaged = field[i].orgId == humanOrg }
        ids[i] = "d" .. i
    end
    local pricer = Pricing.newPricer(ids)
    for k = 1, 400 do
        local r = Sim.simulate(field, { distanceM = 4000 }, { roadWetness = 0, light = "day" }, H.stream("mc", k), { baseSec = 140, light = true })
        local finished = {}
        for _, e in ipairs(r.entrants) do if e.state == "finished" then finished[e.id] = true end end
        pricer.add(r.order, finished)
    end
    return Pricing.lines(entrants, pricer.probs(), {}), pricer.probs()
end

return {
    win_book_carries_the_overround = function(T)
        local Pricing = T.Core.get("paddock.pricing")
        local lines = priced(T, 8)
        local prices, sumP = {}, 0
        for _, l in ipairs(lines) do
            if l.market == "win" then sumP = sumP + l.prob; if l.price then prices[#prices + 1] = l.price end end
        end
        T.ok(math.abs(sumP - 1) < 0.02, "win probabilities sum to one: " .. sumP)
        -- every price below the long-shot cap is exactly the fair price with a 10% overround (to rounding);
        -- capped long shots are shaded shorter than fair on purpose (small samples misprice them)
        local checked = 0
        for _, l in ipairs(lines) do
            if l.price and l.price < Pricing.MAX_PRICE then
                checked = checked + 1
                T.ok(math.abs(1 / l.price - l.prob * 1.10) < 0.005, "overround on " .. l.market .. " " .. l.a)
            end
        end
        T.ok(checked >= 4, "a real board has unclamped lines: " .. checked)
        T.ok(#prices >= 2)
        for _, l in ipairs(lines) do
            if l.price then T.ok(l.price >= 1.10 and l.price <= 30, "prices clamped") end
        end
        local fav, long
        for _, l in ipairs(lines) do
            if l.market == "win" and l.a == "d1" then fav = l.price end
            if l.market == "win" and l.a == "d8" then long = l.price end
        end
        T.ok(fav < long, "the quickest driver, on pole as a qualifying grid puts them, is the shortest price")
    end,

    overround_is_exact_on_a_clean_book = function(T)
        local Pricing = T.Core.get("paddock.pricing")
        local ps = { 0.25, 0.25, 0.25, 0.25 }
        local prices = {}
        for i, p in ipairs(ps) do prices[i] = Pricing.price(p) end
        local implied = Pricing.implied(prices)
        T.ok(math.abs(implied - 1.10) < 0.005, "within 0.5% of 1.10: " .. implied)
        T.eq(Pricing.price(0.95), nil, "no line on a near-certainty")
    end,

    human_managed_drivers_are_refused_for_everyone = function(T)
        local lines = priced(T, 6, "o2")
        for _, l in ipairs(lines) do
            local touches = (l.a == "d3" or l.a == "d4" or l.b == "d3" or l.b == "d4")
            if touches then T.ok(l.refused and l.price == nil, "refused line " .. l.market .. " " .. tostring(l.a)) end
            if not touches and l.market == "win" then T.falsy(l.refused, "NPC-run drivers stay on the board") end
        end
        local h2h = 0
        for _, l in ipairs(lines) do if l.market == "h2h" then h2h = h2h + 1; T.ok(l.b ~= nil) end end
        T.ok(h2h > 0, "head-to-heads offered within the race")
    end,

    slips_validate_and_settle = function(T)
        local Pricing = T.Core.get("paddock.pricing")
        local line = { state = "open", version = 2, price = 3.5, market = "win" }
        local ctx = { line = line, slip = { stake = 100, version = 2 }, caps = { perSlip = 250, daily = 500, maxPayout = 5000 },
            stakedToday = 0, balance = 1000, knowsBillie = true, now = 1, closesAt = 100 }
        local ok, potential = Pricing.validateSlip(ctx)
        T.ok(ok); T.eq(potential, 350)
        ctx.knowsBillie = false; T.eq(select(2, Pricing.validateSlip(ctx)), "not_introduced"); ctx.knowsBillie = true
        ctx.managesInSeries = true; T.eq(select(2, Pricing.validateSlip(ctx)), "own_series"); ctx.managesInSeries = nil
        ctx.slip.version = 1; T.eq(select(2, Pricing.validateSlip(ctx)), "price_moved"); ctx.slip.version = 2
        ctx.slip.stake = 300; T.eq(select(2, Pricing.validateSlip(ctx)), "over_slip_cap"); ctx.slip.stake = 100
        ctx.stakedToday = 450; T.eq(select(2, Pricing.validateSlip(ctx)), "over_daily_cap"); ctx.stakedToday = 0
        ctx.now = 100; T.eq(select(2, Pricing.validateSlip(ctx)), "closed"); ctx.now = 1
        line.refused = true; T.eq(select(2, Pricing.validateSlip(ctx)), "refused")
        local result = { byId = { a = { position = 1, state = "finished" }, b = { position = 2, state = "finished" },
            c = { position = 9, state = "dnf" } } }
        T.eq(select(1, Pricing.settle({ market = "win", a = "a", stake = 10, price = 3 }, result)), "won")
        T.eq(select(2, Pricing.settle({ market = "win", a = "a", stake = 10, price = 3 }, result)), 30)
        T.eq(select(1, Pricing.settle({ market = "podium", a = "c", stake = 10, price = 2 }, result)), "lost")
        T.eq(select(1, Pricing.settle({ market = "h2h", a = "b", b = "c", stake = 10, price = 2 }, result)), "won")
        T.eq(select(1, Pricing.settle({ market = "win", a = "a", stake = 10, price = 3 }, { void = true })), "void")
    end,

    purse_and_solvency = function(T)
        local Finance = T.Core.get("paddock.finance")
        local p = Finance.purse("street", 12)
        local sum = 0
        for _, v in ipairs(p) do sum = sum + v end
        T.ok(math.abs(sum - Finance.PURSE.street) <= 12, "the purse is distributed")
        T.ok(p[1] > p[2] and p[2] > p[12])
        local org = { tier = "street", cash = -5 }
        for _ = 1, Finance.FOLD_DAYS - 1 do T.falsy(Finance.tickSolvency(org)) end
        T.ok(Finance.tickSolvency(org), "a week in the red folds the org")
        org.cash = 10; T.falsy(Finance.tickSolvency(org)); T.eq(org.redDays, 0)
    end,

    world_economy_does_not_collapse_in_a_simulated_month = function(T)
        -- Genesis, then 30 days of wages, sponsors and average purse: the tier averages should not all fold.
        local W = T.Core.get("paddock.world")
        local Finance = T.Core.get("paddock.finance")
        local Season = T.Core.get("paddock.season")
        local w = W.genesis(77, "2026-S4")
        local racesPerDay = { street = 12, regional = 8, pro = 4, premier = 1 }
        local folds = 0
        for _ = 1, 30 do
            for _, oid in ipairs(w.orgOrder) do
                local o = w.orgs[oid]
                local spec = Season.TIERS[o.tier]
                local field = spec.orgs / spec.divisions * spec.carsPerOrg
                local avgPurse = Finance.PURSE[o.tier] / field * spec.carsPerOrg
                o.cash = o.cash + Finance.sum(Finance.dayLines(w, o)) + math.floor(avgPurse * racesPerDay[o.tier])
                if Finance.tickSolvency(o) then folds = folds + 1 end
            end
        end
        T.ok(folds <= 6, "an average month folds few orgs: " .. folds)
    end,

    progression_moves_morale_and_retires_veterans = function(T)
        local P = T.Core.get("paddock.progression")
        local d = { attrs = stats(T, { mettle = 80 }), morale = 50 }
        P.moraleAfterRace(d, 1, 6, 12, "finished")
        T.ok(d.morale > 50, "a win from sixth lifts morale")
        local before = d.morale
        P.moraleAfterRace(d, 12, 1, 12, "finished")
        T.ok(d.morale < before and before - d.morale <= P.MORALE_CAP, "a bad result costs, capped and softened by mettle")
        T.ok(P.form({ 8, 7, 5, 3, 2 }, 12) > 0.2, "improving form is positive")
        T.ok(P.form({ 1, 2, 4, 6, 9 }, 12) < -0.2)
        T.eq(P.retireChance({ attrs = stats(T) }, 25), 0)
        T.ok(P.retireChance({ attrs = stats(T) }, 38) > 0.4)
        T.ok(P.retireChance({ attrs = stats(T) }, 42) > 0.9)
    end,

    principals_decide_by_their_traits = function(T)
        local Principal = T.Core.get("paddock.principal")
        local W = T.Core.get("paddock.world")
        local w = W.genesis(88, "2026-S4")
        local org = w.orgs.o001
        local owner = w.people[org.ownerId]
        org.cash = 500000
        local ctx = { drivers = W.drivers(w, org.id), freeAgents = {}, standing = 8, tierMedianRating = 50, seasonOrdinal = 0 }
        owner.principal = { patience = 95, long_term_orientation = 95, liquidity_conservatism = 5, risk_tolerance = 80 }
        local patient = Principal.decide(w, org, ctx)[1].kind
        owner.principal = { patience = 5, long_term_orientation = 5, liquidity_conservatism = 95, risk_tolerance = 5 }
        local miser = Principal.decide(w, org, ctx)[1].kind
        T.eq(patient, "invest_dev", "a patient, long-term owner develops the car")
        T.eq(miser, "hold", "a cash-hoarding owner sits on it")
        org.origin = "human_founded"; org.humanManagerDriverId = "h1"
        T.falsy(Principal.firesHumanManager(owner, org, -1), "founders cannot be fired")
        org.origin = "genesis"
        owner.principal = { patience = 10, ruthlessness = 90 }
        T.ok(Principal.firesHumanManager(owner, org, -0.5), "a ruthless owner fires a failing manager")
        owner.principal = { patience = 90, ruthlessness = 10 }
        T.falsy(Principal.firesHumanManager(owner, org, -0.5), "a patient owner gives them time")
    end,

    manager_actions_validate = function(T)
        local M = T.Core.get("paddock.manager")
        local W = T.Core.get("paddock.world")
        T.eq(select(2, M.validateFound({ name = "Kabuki Heat", affiliated = true, balance = 99999 })), "one_team_rule")
        T.eq(select(2, M.validateFound({ name = "x", balance = 99999 })), "name_too_short")
        T.eq(select(2, M.validateFound({ name = "Kabuki Heat", balance = 10 })), "insufficient_funds")
        T.eq(select(2, M.validateFound({ name = "Kabuki <b>", balance = 99999 })), "name_characters")
        local ok, name = M.validateFound({ name = "  Kabuki   Heat ", balance = 99999 })
        T.ok(ok); T.eq(name, "Kabuki Heat")
        local w = W.genesis(55, "2026-S4")
        local org = w.orgs.o001
        org.humanManagerDriverId = "h1"
        local base = { org = org, world = w, managerDriverId = "h1", treasury = 10000, caps = { weeklyCap = 2000, tax = 0.3 } }
        base.args = { eddies = 1500 }
        local okW, plan = M.validate("withdraw", base)
        T.ok(okW); T.eq(plan.tax, 450); T.eq(plan.net, 1050)
        base.withdrawnThisWeek = 1000
        T.eq(select(2, M.validate("withdraw", base)), "over_weekly_cap")
        base.withdrawnThisWeek = 0
        base.args = { area = "aerodynamics", eddies = 3000 }
        T.ok(M.validate("develop", base))
        base.managerDriverId = "someone_else"
        T.eq(select(2, M.validate("develop", base)), "not_your_org")
        base.managerDriverId = "h1"
        local fa = W.freeAgents(w)[1]
        base.args = { driverId = fa.id, wage = 100, seasons = 2 }
        local okS, sign = M.validate("sign", base)
        T.ok(okS); T.ok(sign.willingness > 0 and sign.willingness <= 1)
    end,

    spotlight_decays_and_arcs_resolve = function(T)
        local S = T.Core.get("paddock.spotlight")
        local g = S.earned({ position = 1, state = "finished", fieldSize = 6, gridPos = 4, streak = 2 })
        T.ok(g > 10)
        T.eq(S.earned({ position = 9, state = "finished", fieldSize = 6 }), 0)
        T.ok(S.update(20, 10, 0) < 20)
        local arc = S.openArc("a1", "p1", "h1", 0)
        local _, changed = S.resolveArc(arc, nil, 100)
        T.falsy(changed)
        S.resolveArc(arc, { state = "finished", position = 2 }, 200)
        T.eq(arc.state, "won")
        local arc2 = S.openArc("a2", "p1", "h1", 0)
        S.resolveArc(arc2, nil, 8 * 86400)
        T.eq(arc2.state, "expired")
    end,

    affiliation_rules = function(T)
        local A = T.Core.get("competition.affiliation")
        T.ok(A.canAffiliate(nil, { circuit = "npc", role = "manager", driverId = "d", paddockOrgId = "o1" }))
        T.eq(select(2, A.canAffiliate(nil, { circuit = "npc", role = "owner", driverId = "d", paddockOrgId = "o1" })), "npc_circuit_manager_only")
        T.eq(select(2, A.canAffiliate({ role = "manager" }, { circuit = "sanctioned", role = "driver", driverId = "d", organizationId = "g" })), "one_team_rule")
        T.eq(select(2, A.canDrive({ role = "owner" })), "owner_cannot_drive")
        T.eq(select(2, A.canAppointManager({ role = "owner", driverId = "d" }, "d")), "self_appointment")
        T.ok(A.canAppointManager({ role = "owner", driverId = "d" }, "e", nil))
    end,
}
