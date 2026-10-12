-- ncm-core module: paddock.manager
-- Manager mode (doc 44 §10, L224.8): a human runs an NPC-circuit org of AI drivers.
--
-- A human founds a Street org for a fee (wallet -> treasury), or accepts an offer from a personality-driven NPC
-- owner who can later fire them. Controls: roster and contracts, car development, staff and sponsors. NO per-race
-- orders: races stay simulated. Roster changes apply at the next Cup boundary, so a manager cannot reshape a field
-- after its lines are priced. Managing is the human's one team affiliation (the One-Team Rule, migration 046).
-- The treasury is append-only; withdrawals are capped weekly and taxed (both tunables).
--
-- This module VALIDATES and PLANS. The server applies the plan in one transaction.
local Core = NcmCore

Core.define("paddock.manager", function(C)
    local M = { version = "0.1.0" }
    local Car = C.get("paddock.car")
    local Contracts = C.get("paddock.contracts")
    local Season = C.get("paddock.season")

    M.ACTIONS = { found = true, accept = true, resign = true, sign = true, release = true, seat = true,
        develop = true, hire_staff = true, sign_sponsor = true, deposit = true, withdraw = true }
    M.DEFAULTS = { foundFee = 5000, foundGrant = 15000, withdrawWeeklyCap = 2000, withdrawTax = 0.30,
        cooldownSeasons = 1, maxNameLength = 32 }

    local function clean(name)
        if type(name) ~= "string" then return nil end
        name = name:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
        return name
    end

    --- Validate a founding. `ctx` = { name, affiliated, cooldownUntilSeason, seasonOrdinal, balance, fee,
    --- takenNames, maxNameLength }. Returns true, cleanName or false, reason.
    function M.validateFound(ctx)
        if ctx.affiliated then return false, "one_team_rule" end
        if ctx.cooldownUntilSeason and (ctx.seasonOrdinal or 0) < ctx.cooldownUntilSeason then return false, "cooldown" end
        local name = clean(ctx.name)
        if not name or #name < 3 then return false, "name_too_short" end
        if #name > (ctx.maxNameLength or M.DEFAULTS.maxNameLength) then return false, "name_too_long" end
        if not name:match("^[%w%s%-'&%.]+$") then return false, "name_characters" end
        if ctx.takenNames and ctx.takenNames[name] then return false, "name_taken" end
        if (ctx.balance or 0) < (ctx.fee or M.DEFAULTS.foundFee) then return false, "insufficient_funds" end
        return true, name
    end

    --- Validate an action on the manager's own org. `ctx` = { org, world, managerDriverId, treasury, args,
    --- withdrawnThisWeek, caps = { weeklyCap, tax } }. Returns true, plan or false, reason.
    function M.validate(action, ctx)
        local org, world, args = ctx.org, ctx.world, ctx.args or {}
        if not M.ACTIONS[action] then return false, "unknown_action" end
        if not org or org.humanManagerDriverId ~= ctx.managerDriverId then return false, "not_your_org" end
        if org.lifecycle ~= "active" then return false, "org_folded" end
        local treasury = tonumber(ctx.treasury) or 0
        if action == "sign" then
            local d = world.people[args.driverId or ""]
            if not d or d.role ~= "driver" then return false, "no_such_driver" end
            if not Contracts.poachable(d, world.seasonOrdinal) then return false, "under_contract" end
            -- the roster the queue will leave, not today's: queued signings take a place, queued releases free one
            local roster = #C.get("paddock.world").drivers(world, org.id)
            for _, p in ipairs(org.pending or {}) do
                if p.kind == "sign" then roster = roster + 1 elseif p.kind == "release" then roster = roster - 1 end
            end
            if roster >= M.limits(org.tier).maxContracted then return false, "roster_full" end
            local wage = math.floor(tonumber(args.wage) or 0)
            local seasons = math.floor(tonumber(args.seasons) or 1)
            if wage < 1 then return false, "invalid_wage" end
            if seasons < 1 or seasons > 3 then return false, "invalid_length" end
            if treasury < wage * 30 then return false, "cannot_afford" end
            local offer = { orgId = org.id, tier = org.tier, wage = wage, seasons = seasons, prestige = org.prestige }
            local current = d.orgId and world.orgs[d.orgId] or nil
            return true, { kind = "sign", driverId = d.id, wage = wage, seasons = seasons,
                willingness = Contracts.willingness(d, offer, current) }
        elseif action == "release" then
            local d = world.people[args.driverId or ""]
            if not d or d.orgId ~= org.id or d.role ~= "driver" then return false, "not_your_driver" end
            local severance = math.max(0, ((d.contractEnds or 0) - (world.seasonOrdinal or 0))) * (d.wage or 0) * 10
            if treasury < severance then return false, "cannot_afford_severance" end
            return true, { kind = "release", driverId = d.id, severance = severance }
        elseif action == "seat" then
            local d = world.people[args.driverId or ""]
            if not d or d.orgId ~= org.id or d.role ~= "driver" then return false, "not_your_driver" end
            local seat = tostring(args.seat or "")
            local cars = Season.TIERS[org.tier].carsPerOrg
            local valid = seat == "reserve"
            for i = 1, cars do if seat == ("race" .. i) then valid = true end end
            if not valid then return false, "invalid_seat" end
            return true, { kind = "seat", driverId = d.id, seat = seat }
        elseif action == "develop" then
            local area, eddies = args.area, math.floor(tonumber(args.eddies) or 0)
            if not Car.WEIGHTS[area or ""] then return false, "unknown_area" end
            if eddies < 1 then return false, "invalid_amount" end
            if eddies > treasury then return false, "cannot_afford" end
            return true, { kind = "develop", area = area, eddies = eddies }
        elseif action == "hire_staff" then
            local role = args.role
            if role ~= "engineer" and role ~= "strategist" then return false, "invalid_role" end
            local fee = (C.get("paddock.world").TIER_WAGE[org.tier] or 90) * 20
            if treasury < fee then return false, "cannot_afford" end
            return true, { kind = "hire_staff", role = role, fee = fee }
        elseif action == "sign_sponsor" then
            local s = world.sponsors[args.sponsorId or ""]
            if not s or s.orgId ~= nil then return false, "sponsor_unavailable" end
            if #(org.sponsorIds or {}) >= 3 then return false, "sponsor_limit" end
            return true, { kind = "sign_sponsor", sponsorId = s.id }
        elseif action == "deposit" then
            local eddies = math.floor(tonumber(args.eddies) or 0)
            if eddies < 1 then return false, "invalid_amount" end
            return true, { kind = "deposit", eddies = eddies }
        elseif action == "withdraw" then
            local eddies = math.floor(tonumber(args.eddies) or 0)
            local caps = ctx.caps or {}
            local cap = caps.weeklyCap or M.DEFAULTS.withdrawWeeklyCap
            if eddies < 1 then return false, "invalid_amount" end
            if eddies > treasury then return false, "cannot_afford" end
            if (ctx.withdrawnThisWeek or 0) + eddies > cap then return false, "over_weekly_cap" end
            local tax = math.floor(eddies * (caps.tax or M.DEFAULTS.withdrawTax) + 0.5)
            return true, { kind = "withdraw", eddies = eddies, tax = tax, net = eddies - tax }
        elseif action == "resign" then
            return true, { kind = "resign" }
        end
        return false, "unsupported"
    end

    -- ---------------------------------------------------------------------------------------------------------
    -- The queue (owner 2026-10-09: "need the ability to cancel pending actions ... should be clear about number of
    -- drivers who can be racers for your team"). Roster moves wait for the Cup boundary; until then they can be
    -- taken back, a second seat move for the same driver REPLACES the first, and the panel shows the roster the
    -- queue will leave behind.
    -- ---------------------------------------------------------------------------------------------------------
    M.MAX_PENDING = 6
    M.ROSTER_MOVES = { sign = true, release = true, seat = true }

    --- The seats a tier gives a team: race seats (cars it fields per race) and how many drivers it may contract.
    function M.limits(tier)
        local spec = Season.TIERS[tier] or Season.TIERS.street
        return { raceSeats = spec.carsPerOrg, squad = spec.roster, maxContracted = spec.roster + 1 }
    end

    --- Add a validated roster `plan` to `pending` (a list, changed in place). A seat move for a driver who already
    --- has one replaces it; a second release or signing of the same driver is refused. Returns true, "added" |
    --- "replaced" or false, reason.
    function M.enqueue(pending, plan)
        for i, p in ipairs(pending) do
            if p.driverId == plan.driverId and p.kind == plan.kind then
                if plan.kind == "seat" then pending[i] = plan; return true, "replaced" end
                return false, "already_pending"
            end
        end
        if #pending >= M.MAX_PENDING then return false, "too_many_pending" end
        pending[#pending + 1] = plan
        return true, "added"
    end

    --- Take back the move at `index`. `expect` = { kind, driverId } must match it, so a stale panel can never cancel
    --- a different move than the one its button showed. Returns true, removedPlan or false, reason.
    function M.cancel(pending, index, expect)
        index = math.floor(tonumber(index) or 0)
        local p = pending[index]
        if not p then return false, "no_such_move" end
        expect = expect or {}
        if (expect.kind and expect.kind ~= p.kind) or (expect.driverId and expect.driverId ~= p.driverId) then
            return false, "queue_changed"
        end
        table.remove(pending, index)
        return true, p
    end

    --- Fill empty race seats from reserves, best rated first. `drivers` = persons (seat changed in place).
    --- Returns the ids moved up.
    function M.fillRaceSeats(drivers, cars, rating)
        rating = rating or function(p) return C.get("paddock.attributes").rating(p.attrs) end
        local taken, moved = {}, {}
        for _, d in ipairs(drivers) do if d.seat then taken[d.seat] = true end end
        local reserves = {}
        for _, d in ipairs(drivers) do if d.seat == "reserve" or not d.seat then reserves[#reserves + 1] = d end end
        local r = {}
        for _, d in ipairs(reserves) do r[d] = rating(d) end
        table.sort(reserves, function(a, b)
            if r[a] ~= r[b] then return r[a] > r[b] end
            return tostring(a.id) < tostring(b.id)
        end)
        local nextR = 1
        for i = 1, cars do
            local seat = "race" .. i
            if not taken[seat] and reserves[nextR] then
                reserves[nextR].seat = seat
                moved[#moved + 1] = reserves[nextR].id
                nextR = nextR + 1
            end
        end
        return moved
    end

    --- Apply one queued seat move to `drivers` (persons or copies; changed in place): the driver takes the seat and
    --- whoever held it takes theirs (a swap). Shared by the boundary and the preview, so they cannot disagree.
    function M.applySeat(drivers, plan)
        local dr
        for _, d in ipairs(drivers) do if d.id == plan.driverId then dr = d end end
        if not dr then return false end
        for _, other in ipairs(drivers) do
            if other.id ~= dr.id and other.seat == plan.seat and plan.seat ~= "reserve" then other.seat = dr.seat end
        end
        dr.seat = plan.seat
        return true
    end

    --- The roster the queue leaves behind, assuming every signing says yes. `drivers` = the org's contracted
    --- persons now; `names` (optional) = { [personId] = display } for signings. Returns
    --- { roster = { { id, name, seat, was, new?, maybe? } }, notes = { text } } -- nothing is changed.
    function M.project(drivers, pending, cars, names, rating)
        local rows, byId = {}, {}
        for _, d in ipairs(drivers) do
            local c = { id = d.id, name = d.display, seat = d.seat, was = d.seat, attrs = d.attrs }
            rows[#rows + 1] = c; byId[d.id] = c
        end
        local notes = {}
        for _, plan in ipairs(pending or {}) do
            if plan.kind == "release" and byId[plan.driverId] then
                local c = byId[plan.driverId]
                for i, x in ipairs(rows) do if x == c then table.remove(rows, i) break end end
                byId[plan.driverId] = nil
                notes[#notes + 1] = c.name .. " leaves"
            elseif plan.kind == "sign" and not byId[plan.driverId] then
                local name = (names and names[plan.driverId]) or plan.driverId
                local c = { id = plan.driverId, name = name, seat = "reserve", new = true, maybe = true,
                    attrs = plan.attrs, chance = plan.willingness }
                rows[#rows + 1] = c; byId[c.id] = c
                notes[#notes + 1] = ("%s joins if they say yes (%d%% likely)"):format(name, math.floor((plan.willingness or 0.5) * 100 + 0.5))
            elseif plan.kind == "seat" then
                M.applySeat(rows, plan)
            end
        end
        local filled = M.fillRaceSeats(rows, cars, rating or function(p)
            return p.attrs and C.get("paddock.attributes").rating(p.attrs) or 0 end)
        for _, id in ipairs(filled) do
            notes[#notes + 1] = (byId[id] and byId[id].name or id) .. " fills the empty race seat"
        end
        local empty = 0
        local taken = {}
        for _, c in ipairs(rows) do if c.seat then taken[c.seat] = true end end
        for i = 1, cars do if not taken["race" .. i] then empty = empty + 1 end end
        if empty > 0 then notes[#notes + 1] = ("%d race seat(s) left empty: sign a driver"):format(empty) end
        table.sort(rows, function(a, b)
            if (a.seat or "z") ~= (b.seat or "z") then return (a.seat or "z") < (b.seat or "z") end
            return tostring(a.id) < tostring(b.id)
        end)
        for _, c in ipairs(rows) do c.attrs = nil end
        return { roster = rows, notes = notes, emptySeats = empty }
    end

    --- How the roster reacts to a manager's move: morale deltas by driver id.
    function M.reactions(plan, world, org)
        local out = {}
        for _, p in ipairs(C.get("paddock.world").drivers(world, org.id)) do
            do
                local a = p.attrs or {}
                local d = 0
                if plan.kind == "release" and p.id ~= plan.driverId then d = -3 * (a.loyalty or 50) / 50 end
                if plan.kind == "sign" then d = -2 * (a.ego or 50) / 50 end
                if plan.kind == "develop" then d = 1.5 end
                if plan.kind == "seat" and p.id == plan.driverId then
                    d = (plan.seat == "reserve") and (-8 * (a.ego or 50) / 50) or 5
                end
                if d ~= 0 then out[p.id] = d end
            end
        end
        return out
    end

    --- A manager's record -1..1: how the org is doing against where its roster says it should finish.
    function M.record(expectedPos, actualPos, fieldSize)
        if not expectedPos or not actualPos then return 0 end
        local r = (expectedPos - actualPos) / math.max(1, (fieldSize or 10) / 2)
        if r > 1 then r = 1 elseif r < -1 then r = -1 end
        return r
    end

    --- Whether an NPC owner would offer a human their manager job: a strong enough record where they manage,
    --- or earned spotlight in sanctioned racing.
    function M.offerEligible(human)
        return (human.spotlight or 0) >= 25 or ((human.managerSeasons or 0) >= 1 and (human.managerRecord or 0) > 0.2)
    end

    return M
end)
