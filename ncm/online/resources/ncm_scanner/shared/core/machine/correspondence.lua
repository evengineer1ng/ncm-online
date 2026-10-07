-- ncm-core module: machine.correspondence
--
-- L336: which of a host's vehicles best EXPRESSES a Machine. One engine for every host (Assetto Corsa today, KSA bodies,
-- GTA next): a host hands a catalogue of its vehicles, each with a passport (machine.passport); this ranks them.
--
--   the chain   exact model -> authored correspondence -> gated nearest -> archetypal fallback (never "no body": no machine
--               is denied geography because a host lacks its exact body)
--   the gates   morphology (kind, wheels, body family, size) and architecture (doors, seats, drive, mass) must pass before
--               a candidate is "gated nearest"; then performance, CHARACTER (weighted heaviest -- recognition beats the spec
--               sheet: "give me the boring sedan") and COLOUR (the nearest skin to the Machine's paint) score it
--   sticky      `decide` keeps the established expression unless a candidate is better by REVISE_BY; a change is an
--               explicit revision with its reason (an embodiment history), never Monday's sedan A / Tuesday's sedan B
local Core = NcmCore

Core.define("machine.correspondence", function(C)
    local M = { version = "0.1.0" }
    local P = C.get("machine.passport")

    M.REVISE_BY = 0.10
    M.WEIGHTS = { morphology = 0.25, architecture = 0.15, performance = 0.10, character = 0.35, colour = 0.15 }
    M.GATE = { morphology = 0.45, architecture = 0.30 }

    -- how near one body family is to another (symmetric; unlisted pairs 0.15)
    local NEAR = {
        sedan = { sedan = 1, wagon = 0.8, hatch = 0.65, coupe = 0.4, suv = 0.4, muscle = 0.3, convertible = 0.3, van = 0.25, pickup = 0.2, microcar = 0.3 },
        hatch = { hatch = 1, microcar = 0.7, wagon = 0.6, coupe = 0.5, convertible = 0.35 },
        wagon = { wagon = 1, suv = 0.5, van = 0.4, hatch = 0.6 },
        coupe = { coupe = 1, muscle = 0.75, convertible = 0.7, supercar = 0.55 },
        convertible = { convertible = 1, coupe = 0.7, supercar = 0.45 },
        supercar = { supercar = 1, coupe = 0.55, prototype = 0.5 },
        muscle = { muscle = 1, coupe = 0.75, convertible = 0.5 },
        suv = { suv = 1, pickup = 0.55, van = 0.45, wagon = 0.5 },
        pickup = { pickup = 1, suv = 0.55, van = 0.4 },
        van = { van = 1, suv = 0.45, pickup = 0.4 },
        microcar = { microcar = 1, hatch = 0.7 },
        formula = { formula = 1, prototype = 0.6 },
        prototype = { prototype = 1, formula = 0.6, supercar = 0.5 },
        bike = { bike = 1 },
    }
    function M.bodyNear(a, b)
        if not a or not b then return 0.5 end
        if a == b then return 1 end
        return (NEAR[a] and NEAR[a][b]) or (NEAR[b] and NEAR[b][a]) or 0.15
    end

    local function ratio(a, b) if not a or not b or a <= 0 or b <= 0 then return nil end return math.min(a, b) / math.max(a, b) end
    -- mean of the values that exist (varargs: a nil in a table constructor would end ipairs early and drop the rest)
    local function avg(...)
        local s, n = 0, 0
        for i = 1, select("#", ...) do local x = select(i, ...); if x then s, n = s + x, n + 1 end end
        return n > 0 and s / n or 0.5
    end

    --- colour distance 0..1 (0 = same) on sRGB 0..255, weighted for the eye ("redmean")
    function M.colourDistance(a, b)
        if not a or not b then return nil end
        local rm = (a[1] + b[1]) / 2
        local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
        local d = math.sqrt((2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db)
        return math.min(1, d / 400)   -- 400 ~ "a different colour"; teal vs grey is far, teal vs dark blue-green is near
    end

    local function get(p, g, k) return (P.get(p, g, k)) end

    --- Score one candidate against the Machine. Returns score 0..1, breakdown { morphology, architecture, performance,
    --- character, colour }, gated (passed both gates), the chosen variant (skin) and a reason.
    function M.score(src, cand)
        local b = {}
        -- morphology
        local kindS = (get(src, "morphology", "kind") or "car") == (get(cand, "morphology", "kind") or "car") and 1 or 0
        local wheelS = (get(src, "morphology", "wheels") or 4) == (get(cand, "morphology", "wheels") or 4) and 1 or 0
        local bodyS = M.bodyNear(get(src, "morphology", "body"), get(cand, "morphology", "body"))
        local lenS = ratio(get(src, "morphology", "lengthM"), get(cand, "morphology", "lengthM"))
        b.morphology = kindS * wheelS * avg(bodyS, bodyS, lenS)
        -- architecture
        local dS = nil
        local d1, d2 = get(src, "morphology", "doors"), get(cand, "morphology", "doors")
        if d1 and d2 then dS = (d1 == d2) and 1 or ((d1 >= 4) ~= (d2 >= 4) and 0.35 or 0.7) end
        local sS = ratio(get(src, "morphology", "seats"), get(cand, "morphology", "seats"))
        local drS = nil
        local dr1, dr2 = get(src, "architecture", "drive"), get(cand, "architecture", "drive")
        if dr1 and dr2 then drS = dr1 == dr2 and 1 or 0.7 end
        local mS = ratio(get(src, "performance", "massKg"), get(cand, "performance", "massKg"))
        b.architecture = avg(dS, dS, sS, drS, mS)
        -- performance
        local pw1 = get(src, "performance", "powerKw") and get(src, "performance", "massKg") and get(src, "performance", "powerKw") / get(src, "performance", "massKg")
        local pw2 = get(cand, "performance", "powerKw") and get(cand, "performance", "massKg") and get(cand, "performance", "powerKw") / get(cand, "performance", "massKg")
        b.performance = avg(ratio(pw1, pw2), ratio(get(src, "performance", "topKph"), get(cand, "performance", "topKph")))
        -- character: mean axis closeness over the axes both know
        local cs = {}
        for axis in pairs(P.AXES) do
            local x, y = get(src, "character", axis), get(cand, "character", axis)
            if x and y then cs[#cs + 1] = 1 - math.abs(x - y) / 2 end
        end
        b.character = #cs > 0 and avg((table.unpack or unpack)(cs)) ^ 2 or 0.5      -- squared: a half-near character is not "near"
        -- colour: the nearest variant (skin) to the Machine's paint
        local paint = get(src, "appearance", "primary")
        local variant, best = nil, nil
        for _, v in ipairs(cand.variants or {}) do
            local dd = M.colourDistance(paint, v.rgb)
            if dd and (not best or dd < best) then best, variant = dd, v end
        end
        b.colour = best and (1 - best) or 0.5
        if not variant and cand.variants and cand.variants[1] then variant = cand.variants[1] end
        local total = 0
        for k, w in pairs(M.WEIGHTS) do total = total + w * (b[k] or 0.5) end
        local gated = b.morphology >= M.GATE.morphology and b.architecture >= M.GATE.architecture
        return total, b, gated, variant
    end

    local function reasonFor(src, cand, b, variant, tier)
        local body = get(cand, "morphology", "body") or "?"
        local doors = get(cand, "morphology", "doors")
        local parts = { ("%s%s"):format(doors and (doors .. "-door ") or "", body) }
        parts[#parts + 1] = ("character %.2f"):format(b.character)
        parts[#parts + 1] = ("shape %.2f"):format(b.morphology)
        if variant then parts[#parts + 1] = ("skin %s (colour %.2f)"):format(tostring(variant.id), b.colour) end
        if tier == "fallback" then parts[#parts + 1] = "no candidate passed the shape gates: the nearest body anyway (expression loss)" end
        return table.concat(parts, ", ")
    end

    --- Rank a host's catalogue for a Machine. catalogue = { { id, passport, variants = { { id, rgb } } } }.
    --- Returns a sorted list of { id, variant, score, tier = exact|gated|fallback, breakdown, reason }.
    function M.rank(src, catalogue, hints)
        local out = {}
        local maker, model = get(src, "identity", "maker"), get(src, "identity", "model")
        for _, cand in ipairs(catalogue or {}) do
            local cp = cand.passport
            cp.variants = cand.variants
            local s, b, gated, variant = M.score(src, cp)
            local tier = gated and "gated" or "fallback"
            if maker and model and get(cp, "identity", "maker") == maker and get(cp, "identity", "model") == model then
                tier, s = "exact", 1
            elseif hints and hints[cand.id] then
                tier = gated and "authored" or tier
            end
            out[#out + 1] = { id = cand.id, variant = variant, score = s, tier = tier, breakdown = b, reason = reasonFor(src, cp, b, variant, tier) }
        end
        local order = { exact = 4, authored = 3, gated = 2, fallback = 1 }
        table.sort(out, function(a, b)
            if order[a.tier] ~= order[b.tier] then return order[a.tier] > order[b.tier] end
            if a.score ~= b.score then return a.score > b.score end
            return tostring(a.id) < tostring(b.id)
        end)
        return out
    end

    --- The expression to use, sticky. prior = the established { id, variant, score, revision } or nil.
    --- Returns choice { id, variant, score, tier, reason, revision }, and a revision record when it changed (else nil).
    function M.decide(src, catalogue, prior, hints, now)
        local ranked = M.rank(src, catalogue, hints)
        local best = ranked[1]
        if not best then return nil end
        if prior and prior.id then
            local still = nil
            for _, r in ipairs(ranked) do if r.id == prior.id then still = r end end
            if still and (best.id == still.id or best.score < still.score + M.REVISE_BY) then
                -- keep the established body (its skin re-picked only if the paint changed what is nearest)
                still.revision = prior.revision or 1
                still.kept = true
                return still, nil
            end
            local rev = { from = prior.id, to = best.id, fromScore = still and still.score or nil, toScore = best.score, utc = now,
                why = still and ("better by %.2f (>= %.2f)"):format(best.score - still.score, M.REVISE_BY) or "the established body is no longer in this host" }
            best.revision = (prior.revision or 1) + 1
            return best, rev
        end
        best.revision = 1
        return best, { from = nil, to = best.id, toScore = best.score, utc = now, why = "first expression in this host" }
    end

    return M
end)
