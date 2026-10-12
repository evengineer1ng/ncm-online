-- Week-bound chassis repair. Component conditions continue to use parts.wear and its service records.
local Core = NcmCore
Core.define("engineering.vehicle_service", function()
    local M = { version = "0.1.0" }
    local function clamp(x) return math.max(0, math.min(1, tonumber(x) or 0)) end
    local function q3(x) return math.floor(x * 1000 + 0.5) / 1000 end
    local function bits(n)
        n = math.max(0, math.floor(tonumber(n) or 0))
        local count = 0
        while n > 0 do count = count + n % 2; n = math.floor(n / 2) end
        return count
    end
    -- How much work the car needs, 0..1, weighted by what each kind of damage costs to put right. The chassis
    -- (health) and the body carry it; glass, lamps, tyres and a lost panel are small jobs. (Owner 2026-10-09: it
    -- used to take the WORST of chassis, the single worst panel and broken bits / 8, so seven cracked windows and a
    -- tyre read "100%" on a car at 55% health after one race.)
    M.WEIGHTS = { chassis = 0.60, body = 0.25, glass = 0.06, lights = 0.04, tires = 0.03, detached = 0.02 }
    function M.severity(d)
        if type(d) ~= "table" then return 0 end
        local body, maxBody, sumBody = type(d.body) == "table" and d.body or {}, 0, 0
        for _, x in ipairs(body) do maxBody = math.max(maxBody, clamp(x)); sumBody = sumBody + clamp(x) end
        local meanBody = #body > 0 and sumBody / #body or 0
        local W = M.WEIGHTS
        local s = W.chassis * (1 - clamp(d.health == nil and 1 or d.health))
            + W.body * (0.5 * meanBody + 0.5 * maxBody)
            + W.glass * math.min(1, bits(d.glass) / 7)
            + W.lights * math.min(1, bits(d.lights) / 8)
            + W.tires * math.min(1, bits(d.tires) / 4)
            + W.detached * math.min(1, bits(d.detachedParts) / 4)
        return clamp(s)
    end
    --- Each area's own damage, 0..1, for the Engineering panel: what the work is, not just how much.
    function M.breakdown(d)
        if type(d) ~= "table" then return nil end
        local body, maxBody, sumBody = type(d.body) == "table" and d.body or {}, 0, 0
        for _, x in ipairs(body) do maxBody = math.max(maxBody, clamp(x)); sumBody = sumBody + clamp(x) end
        local meanBody = #body > 0 and sumBody / #body or 0
        return {
            { area = "chassis", label = "Chassis", value = 1 - clamp(d.health == nil and 1 or d.health) },
            { area = "body", label = "Bodywork", value = 0.5 * meanBody + 0.5 * maxBody },
            { area = "glass", label = "Glass", value = math.min(1, bits(d.glass) / 7), count = bits(d.glass) },
            { area = "lights", label = "Lamps", value = math.min(1, bits(d.lights) / 8), count = bits(d.lights) },
            { area = "tires", label = "Tyres", value = math.min(1, bits(d.tires) / 4), count = bits(d.tires) },
            { area = "detached", label = "Panels off", value = math.min(1, bits(d.detachedParts) / 4), count = bits(d.detachedParts) },
        }
    end
    function M.quote(d, provider, value)
        local severity = M.severity(d)
        if severity <= 0 then return nil, "already_healthy" end
        if provider ~= "self" and provider ~= "shop" then return nil, "unknown_provider" end
        if provider == "self" and severity > 0 and (1 - clamp(d.health == nil and 1 or d.health)) == 0
            and bits(d.glass) == 0 and bits(d.lights) == 0 and bits(d.tires) == 0
            and bits(d.detachedParts) > 0 then
            local bodyDamaged = false
            for _, v in ipairs(type(d.body) == "table" and d.body or {}) do if clamp(v) > 0 then bodyDamaged = true; break end end
            if not bodyDamaged then return nil, "detached_parts_need_shop" end
        end
        local base = math.max(8000, tonumber(value) or 10000)
        local materials = math.ceil(base * severity * (provider == "self" and 0.055 or 0.11) / 10) * 10
        -- your own hands cost nothing: self work pays for materials only (owner 2026-10-09: "who are you paying
        -- labour for, yourself?"); a shop bills its mechanics' time
        local labour = provider == "self" and 0 or 300 + math.ceil(base * severity * 0.045 / 10) * 10
        local cost = materials + labour
        -- Bench work takes seconds; access to a lift, parts, and a shop booking can take longer.
        local benchSeconds = math.ceil(12 + 48 * severity)
        local leadSeconds = provider == "self" and math.ceil(5 * 60 + 30 * 60 * severity)
            or math.ceil(20 * 60 + 75 * 60 * severity)
        return { provider = provider, cost = cost, materials = materials, labour = labour,
            benchSeconds = benchSeconds, leadSeconds = leadSeconds, severity = severity }
    end
    function M.resolve(d, provider, skill, roll, value)
        local quote, why = M.quote(d, provider, value)
        if not quote then return nil, why end
        local out = {}
        for k, v in pairs(d) do out[k] = v end
        local skillFactor = clamp((tonumber(skill) or 0) / 1000)
        local relief = 1 -- paid work restores the physical chassis; workmanship affects handling
        out.health = clamp((tonumber(d.health) or 1) + (1 - (tonumber(d.health) or 1)) * relief)
        if type(d.body) == "table" then
            out.body = {}
            for i, v in ipairs(d.body) do out.body[i] = clamp(v) * (1 - relief) end
        end
        out.tires = 0; out.glass = 0; out.lights = 0; out.detachedParts = 0
        -- The car is stored for service. A later call creates a fresh runtime instance, so the shop's
        -- replacement panels do not attempt unsafe reattachment on a live REDengine vehicle.
        -- Workmanship is rolled PER SECTION -- grip, drive, brakes, drag -- each its own roll, each able to come out
        -- better or worse (owner 2026-10-09: one flat nerf for every self repair was "diabolically lazy"). Skill
        -- moves every section's odds toward the good side and makes a botch rarer; a shop's mechanics are steadier.
        -- `roll` is a function returning 0..1 (one call per section), or a number used for every section (tests).
        local sections, total, anyBotch = {}, 0, false
        local scalars = {}
        for i, name in ipairs(M.SECTIONS) do
            local r = type(roll) == "function" and clamp(roll()) or clamp(roll)
            local delta, botch = M.sectionDelta(r, provider, skillFactor)
            anyBotch = anyBotch or botch
            sections[i] = { section = name, roll = math.floor(r * 1000 + 0.5) / 1000, delta = delta,
                grade = M.gradeOf(delta, botch) }
            total = total + delta
            scalars[M.SCALAR[name]] = name == "drag" and q3(1 - delta) or q3(1 + delta)
        end
        local setup = total / #M.SECTIONS
        return out, { provider = provider, relief = relief, botch = anyBotch, setup = setup, sections = sections,
            scalars = scalars, grade = M.gradeOf(setup, false),
            cost = quote.cost, materials = quote.materials, labour = quote.labour,
            benchSeconds = quote.benchSeconds, leadSeconds = quote.leadSeconds, severity = quote.severity }
    end
    M.SECTIONS = { "grip", "drive", "brake", "drag" }
    M.SCALAR = { grip = "gripScale", drive = "driveScale", brake = "brakeScale", drag = "dragScale" }
    --- One section's result: the change to its handling multiplier (+ better, - worse; drag is applied inverted).
    --- Without skill a roll is a little more likely to cost than to gain; at full skill most rolls gain. Bounded
    --- to -8%..+3.5% so a car is never ruined or made unbeatable by a wrench.
    function M.sectionDelta(r, provider, skillFactor)
        local shop = provider == "shop"
        local botchAt = shop and (0.06 - 0.05 * skillFactor) or (0.14 - 0.11 * skillFactor)
        if r < botchAt then return -(0.04 + 0.04 * (1 - skillFactor)), true end
        local x = r - 0.5 + (shop and 0.08 or -0.10) + 0.28 * skillFactor
        local d = x < 0 and x * 0.08 or x * 0.05
        return q3(math.max(-0.08, math.min(0.035, d))), false
    end
    function M.gradeOf(delta, botch)
        if botch then return "botched" end
        if delta >= 0.015 then return "excellent" end
        if delta > 0.001 then return "good" end
        if delta >= -0.012 then return "fair" end
        return "rough"
    end
    function M.scalarsFromSetup(setup)
        local s = math.max(-0.1, math.min(0.02, tonumber(setup) or 0))
        local function q(x) return math.floor(x * 100 + 0.5) / 100 end
        -- Drag is inverted: more drag is worse. Each value is the actual handling multiplier.
        return { gripScale = q(1 + s), driveScale = q(1 + s * 0.8),
            brakeScale = q(1 + s * 0.6), dragScale = q(1 - s * 0.5) }
    end
    function M.restored(d)
        local out = {}
        for k, v in pairs(d or {}) do out[k] = v end
        out.health, out.tires, out.glass, out.lights, out.detachedParts = 1, 0, 0, 0, 0
        if type(out.body) == "table" then
            out.body = {}
            for i = 1, #d.body do out.body[i] = 0 end
        end
        return out
    end
    function M.noWorse(current, paidAfter)
        if type(current) ~= "table" or type(paidAfter) ~= "table" then return false end
        if clamp(current.health) + 0.005 < clamp(paidAfter.health) then return false end
        for i, old in ipairs(type(paidAfter.body) == "table" and paidAfter.body or {}) do
            if clamp(current.body and current.body[i]) > clamp(old) + 0.005 then return false end
        end
        for _, key in ipairs({ "tires", "glass", "lights", "detachedParts" }) do
            local a = math.max(0, math.floor(tonumber(current[key]) or 0))
            local b = math.max(0, math.floor(tonumber(paidAfter[key]) or 0))
            while a > 0 or b > 0 do
                if a % 2 > b % 2 then return false end
                a, b = math.floor(a / 2), math.floor(b / 2)
            end
        end
        return true
    end
    function M.correctPaidResidual(current, paidAfter)
        if type(current) ~= "table" or type(paidAfter) ~= "table" then return nil end
        local out = {}
        for k, v in pairs(current) do out[k] = v end
        local paidHealth = clamp(paidAfter.health == nil and 1 or paidAfter.health)
        if paidHealth > 0 then out.health = clamp(clamp(current.health) / paidHealth) end
        if type(current.body) == "table" then
            out.body = {}
            for i, v in ipairs(current.body) do
                out.body[i] = math.max(0, clamp(v) - clamp(paidAfter.body and paidAfter.body[i]))
            end
        end
        for _, key in ipairs({ "tires", "glass", "lights", "detachedParts" }) do
            local a = math.max(0, math.floor(tonumber(current[key]) or 0))
            local b = math.max(0, math.floor(tonumber(paidAfter[key]) or 0))
            local keep, place = 0, 1
            while a > 0 or b > 0 do
                if a % 2 == 1 and b % 2 == 0 then keep = keep + place end
                a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
            end
            out[key] = keep
        end
        return out
    end
    function M.raceDamage(result, physical)
        if physical then return clamp(physical.wrecked and 1 or physical.frac) end
        if not result then return 0 end
        if result.dnfReason == "crash" or result.dnfReason == "contact" then return 0.45 end
        if result.dnfReason == "mechanical" then return 0.25 end
        return 0
    end
    function M.accumulate(d, fraction)
        local out = {}
        for k, v in pairs(d or {}) do out[k] = v end
        out.health = clamp((tonumber(out.health) or 1) * (1 - clamp(fraction)))
        return out
    end
    function M.paceFactor(d, setup)
        local severity = M.severity(d)
        return math.max(0.55, math.min(1.02, 1 - 0.32 * severity + (tonumber(setup) or 0)))
    end
    function M.npcPlan(d, carValue, cash, tier, skill)
        local severity = M.severity(d)
        if severity <= 0 then return nil end
        local selfQuote = M.quote(d, "self", carValue)
        local shopQuote = M.quote(d, "shop", carValue)
        local professional = tier == "pro" or tier == "premier"
        local selected = professional and shopQuote or selfQuote
        if not selected or (tonumber(cash) or 0) < selected.cost then
            selected = (tonumber(cash) or 0) >= (selfQuote and selfQuote.cost or math.huge) and selfQuote or nil
        end
        if not selected then return { action = "wait", severity = severity, shortfall = (selfQuote and selfQuote.cost or 0) - (tonumber(cash) or 0) } end
        local team = tier and tier ~= "street"
        local access = team and (tier == "premier" and 0 or 10 * 60) or 30 * 60
        return { action = "repair", provider = selected.provider, cost = selected.cost,
            materials = selected.materials, labour = selected.labour, severity = severity,
            readySeconds = access + selected.leadSeconds + selected.benchSeconds,
            skill = tonumber(skill) or 0 }
    end
    return M
end)
