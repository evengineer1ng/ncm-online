-- ncm-core module: paddock.principal
-- NPC owners decide (FTB1 `ai_team_decide`, `apply_tendency_weights`, `apply_personality_inflection`).
--
-- At each Cup boundary an NPC org's owner scores the actions open to it and takes the best one or two. The base
-- score is situational (a weak driver, spare cash, a contract running out); the owner's hidden principal traits
-- then weight it (FTB1 normalises a trait as (t - 50) / 100 and multiplies per action type), and four situational
-- inflections switch on in context (cash crisis, title fight, young team, talent gap). So two owners in the same
-- spot make different calls, and the WIRE reports what they did.
local Core = NcmCore

Core.define("paddock.principal", function(C)
    local M = { version = "0.1.0" }
    local Attr = C.get("paddock.attributes")
    local Car = C.get("paddock.car")

    local function n(pr, k) return ((pr and pr[k]) or 50) - 50 end
    local function norm(pr, k) return n(pr, k) / 100 end
    local function sig(x, k) return 1 / (1 + math.exp(-(k or 10) * x)) end

    --- FTB1 tendency weights over our action kinds.
    function M.tendency(score, pr, action, org)
        local s = score
        local cash = math.max(1, org.cash or 1)
        if action.kind == "sign_driver" then
            s = s * (1 + norm(pr, "talent_evaluation") * 0.2)
            if (action.cost or 0) / cash > 0.15 then s = s * (1 - norm(pr, "financial_discipline") * 0.15) end
        elseif action.kind == "release_driver" or action.kind == "fire_manager" then
            s = s * (1 + norm(pr, "ruthlessness") * 0.3) * (1 - norm(pr, "staff_loyalty_bias") * 0.25)
            if (org.cash or 0) < 0 then s = s * (1 + norm(pr, "crisis_management") * 0.15) end
        elseif action.kind == "invest_dev" then
            s = s * (1 + norm(pr, "patience") * 0.25) * (1 + norm(pr, "long_term_orientation") * 0.3)
                * (1 + norm(pr, "risk_tolerance") * 0.15) * (1 - norm(pr, "liquidity_conservatism") * 0.2)
        elseif action.kind == "poach_driver" then
            s = s * (1 + norm(pr, "aggression") * 0.4) * (1 + norm(pr, "risk_tolerance") * 0.3)
                * (1 + norm(pr, "ambition") * 0.2)
        elseif action.kind == "extend_driver" then
            s = s * (1 + norm(pr, "staff_loyalty_bias") * 0.3) * (1 + norm(pr, "patience") * 0.2)
        elseif action.kind == "hold" then
            s = s * (1 + norm(pr, "liquidity_conservatism") * 0.3)
        end
        return s
    end

    --- FTB1 inflections: only in context.
    function M.inflect(score, pr, action, org, ctx)
        ctx = ctx or {}
        local s = score
        local ratio = (org.cash or 0) / math.max(1, ctx.tierCashFloor or 20000)
        if ratio < 0.3 then
            local act = sig(0.3 - ratio, 20)
            if (action.cost or 0) <= 0 then
                s = s * (1 + (n(pr, "financial_discipline") + n(pr, "liquidity_conservatism")) / 50 * 0.5 * act)
            else
                s = s * (1 + (n(pr, "risk_tolerance") + n(pr, "aggression")) / 50 * 0.3 * act)
            end
        end
        if (ctx.standing or 99) <= 3 and (action.kind == "sign_driver" or action.kind == "invest_dev" or action.kind == "poach_driver") then
            s = s * (1 + (n(pr, "risk_tolerance") + n(pr, "aggression")) / 50 * 0.4 * sig(3 - (ctx.standing or 99), 2))
        end
        if (org.seasonsActive or 5) < 3 and action.kind == "invest_dev" then
            s = s * (1 + (n(pr, "patience") + n(pr, "long_term_orientation")) / 50 * 0.5 * sig(3 - org.seasonsActive, 1.5))
        end
        local gap = (ctx.tierMedianRating or 50) - (ctx.rosterRating or 50)
        if gap > 5 and (action.kind == "release_driver" or action.kind == "fire_manager") then
            s = s * (1 + n(pr, "ruthlessness") / 50 * 0.6 * sig(gap - 5, 0.5))
            s = s * math.max(0.1, 1 - n(pr, "staff_loyalty_bias") / 50 * 0.4 * sig(gap - 5, 0.5))
        end
        return s
    end

    --- The candidate actions for an NPC org and their base scores. `ctx` gives the facts the server gathered:
    --- drivers (sorted worst rating first), freeAgents (best first), standing, tierMedianRating, seasonOrdinal,
    --- managerRecord (-1..1 of expectations met).
    function M.candidates(world, org, ctx)
        local out = { { kind = "hold", score = 0.2, cost = 0 } }
        local drivers = ctx.drivers or {}
        local fas = ctx.freeAgents or {}
        local roster = (C.get("paddock.season").TIERS[org.tier] or {}).roster or 2
        local worst = drivers[1]
        local best = fas[1]
        if #drivers < roster and best then
            out[#out + 1] = { kind = "sign_driver", score = 1.0, target = best.id, cost = (best.wage or 0) * 30 }
        end
        if worst and best and Attr.rating(best.attrs) > Attr.rating(worst.attrs) + 4 then
            local gain = (Attr.rating(best.attrs) - Attr.rating(worst.attrs)) / 20
            out[#out + 1] = { kind = "release_driver", score = 0.3 + gain, target = worst.id, then_sign = best.id, cost = 0 }
        end
        for _, d in ipairs(drivers) do
            if (d.contractEnds or 0) <= (ctx.seasonOrdinal or 0) and Attr.rating(d.attrs) >= (ctx.tierMedianRating or 50) then
                out[#out + 1] = { kind = "extend_driver", score = 0.6, target = d.id, cost = 0 }
            end
        end
        if ctx.poachTarget then
            out[#out + 1] = { kind = "poach_driver", score = 0.5, target = ctx.poachTarget.id, cost = (ctx.poachTarget.wage or 0) * 40 }
        end
        local weakest, area = 99, nil
        for _, a in ipairs(Car.AREAS) do
            if (org.car[a] or 1) < weakest then weakest, area = org.car[a] or 1, a end
        end
        if area and weakest < Car.MAX_LEVEL then
            local cost = Car.stepCost(weakest)
            local afford = (org.cash or 0) / math.max(1, cost)
            if afford > 1.5 then
                out[#out + 1] = { kind = "invest_dev", score = math.min(1.2, 0.3 + afford / 10), area = area, cost = cost }
            end
        end
        if org.managerId and not org.humanManagerDriverId and (ctx.managerRecord or 0) < -0.3 then
            out[#out + 1] = { kind = "fire_manager", score = 0.4 - (ctx.managerRecord or 0), target = org.managerId, cost = 0 }
        end
        return out
    end

    --- Score and rank the candidates. Returns the ranked list (best first); the caller takes the top one or two.
    function M.decide(world, org, ctx)
        local owner = world.people[org.ownerId]
        local pr = owner and owner.principal or {}
        local list = M.candidates(world, org, ctx)
        for _, a in ipairs(list) do
            a.weighted = M.inflect(M.tendency(a.score, pr, a, org), pr, a, org, ctx)
        end
        table.sort(list, function(x, y)
            if x.weighted ~= y.weighted then return x.weighted > y.weighted end
            return x.kind < y.kind
        end)
        return list
    end

    --- Whether an NPC owner fires a HUMAN manager of an inherited org this week. Founders cannot be fired.
    function M.firesHumanManager(owner, org, record)
        if org.origin == "human_founded" or not org.humanManagerDriverId then return false end
        local pr = owner and owner.principal or {}
        local patience = n(pr, "patience") / 50
        local ruthless = n(pr, "ruthlessness") / 50
        local threshold = -0.45 - patience * 0.25 + ruthless * 0.2
        return (record or 0) < threshold
    end

    return M
end)
