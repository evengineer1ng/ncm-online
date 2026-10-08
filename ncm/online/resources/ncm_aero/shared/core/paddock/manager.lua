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
            local roster = #C.get("paddock.world").drivers(world, org.id)
            if roster >= (Season.TIERS[org.tier].roster + 1) then return false, "roster_full" end
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
