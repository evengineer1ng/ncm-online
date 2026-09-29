-- ncm-core module: paddock.tags
-- Earned tags: the only window players get onto hidden attributes (doc 44 §4.3).
--
-- A tag shows only when its STAT predicate AND its EVIDENCE predicate both hold. A driver with a high wet skill who
-- has never finished well in the rain is not a "Rain specialist" yet; a driver who got lucky twice in the wet with
-- an average wet skill never will be. So tags are earned, and they can be lost when the evidence ages out.
--
-- Evidence (built by the server from results and the tape; all counts):
--   starts, wins, podiums, dnfs, crashes, contacts, wetStarts, wetTop3, nightStarts, nightTop3, upsetWins,
--   placesGained (sum of grid - finish over finishes), finishes, recent (last positions, newest last),
--   seasonAvg (average finish this season), orgsDriven, transfers, seasonsAtOrg
-- Org evidence: firings, seasonsWithoutFiring, lowCashDays, devSpendSeason, seasonsActive.
local Core = NcmCore

Core.define("paddock.tags", function(C)
    local M = { version = "0.1.0" }

    local function st(a, k) return (a and tonumber(a[k])) or 50 end
    local function ev(e, k) return (e and tonumber(e[k])) or 0 end
    local function avg(list, from)
        local n, s = 0, 0
        for i = math.max(1, from or 1), #(list or {}) do s = s + list[i]; n = n + 1 end
        return n > 0 and (s / n) or nil
    end

    -- { id, label, stat(attrs, person, ctx), evidence(e, person, ctx) }
    M.DRIVER = {
        { id = "rain_specialist", label = "Rain specialist",
            stat = function(a) return st(a, "wet_weather_skill") >= 72 end,
            evidence = function(e) return ev(e, "wetTop3") >= 3 end },
        { id = "night_owl", label = "Night owl",
            stat = function(a) return st(a, "night_skill") >= 72 end,
            evidence = function(e) return ev(e, "nightTop3") >= 3 end },
        { id = "surging", label = "Surging",
            stat = function(_, p) return (tonumber(p.morale) or 50) >= 55 end,
            evidence = function(e)
                local r = avg(e.recent, #(e.recent or {}) - 4)
                return #(e.recent or {}) >= 5 and e.seasonAvg ~= nil and r ~= nil and r <= e.seasonAvg - 2
            end },
        { id = "slumping", label = "Slumping",
            stat = function(_, p) return (tonumber(p.morale) or 50) <= 45 end,
            evidence = function(e)
                local r = avg(e.recent, #(e.recent or {}) - 4)
                return #(e.recent or {}) >= 5 and e.seasonAvg ~= nil and r ~= nil and r >= e.seasonAvg + 2
            end },
        { id = "hot_headed", label = "Hot-headed",
            stat = function(a) return st(a, "aggression") >= 68 end,
            evidence = function(e) return ev(e, "contacts") + ev(e, "crashes") >= 3 end },
        { id = "ice_cool", label = "Ice-cool",
            stat = function(a) return st(a, "pressure_handling") >= 68 and st(a, "discipline") >= 60 end,
            evidence = function(e) return ev(e, "starts") >= 12 and ev(e, "dnfs") == 0 end },
        { id = "fast_starter", label = "Fast starter",
            stat = function(a) return st(a, "launch") >= 70 end,
            evidence = function(e) return ev(e, "finishes") >= 6 and ev(e, "placesGained") / ev(e, "finishes") >= 1.2 end },
        { id = "giant_killer", label = "Giant-killer",
            stat = function(a) return st(a, "racecraft") >= 60 end,
            evidence = function(e) return ev(e, "upsetWins") >= 2 end },
        { id = "crash_prone", label = "Crash-prone",
            stat = function(a) return st(a, "mistake_rate") >= 64 end,
            evidence = function(e) return ev(e, "crashes") >= 3 end },
        { id = "clutch", label = "Clutch",
            stat = function(a) return st(a, "mettle") >= 68 end,
            evidence = function(e) return ev(e, "podiums") >= 6 end },
        { id = "veteran", label = "Veteran",
            stat = function(_, _, ctx) return (ctx and ctx.age or 0) >= 33 end,
            evidence = function(e) return ev(e, "starts") >= 60 end },
        { id = "rookie", label = "Rookie",
            stat = function(_, _, ctx) return (ctx and ctx.age or 99) <= 23 end,
            evidence = function(e) return ev(e, "starts") < 10 end },
        { id = "prodigy", label = "Prodigy",
            stat = function(a, _, ctx) return st(a, "potential") >= 85 and (ctx and ctx.age or 99) <= 22 end,
            evidence = function(e) return ev(e, "podiums") >= 1 end },
        { id = "journeyman", label = "Journeyman",
            stat = function() return true end,
            evidence = function(e) return ev(e, "orgsDriven") >= 3 end },
        { id = "loyal", label = "Loyal",
            stat = function(a) return st(a, "loyalty") >= 70 end,
            evidence = function(e) return ev(e, "seasonsAtOrg") >= 3 end },
        { id = "mercenary", label = "Mercenary",
            stat = function(a) return st(a, "loyalty") <= 30 end,
            evidence = function(e) return ev(e, "transfers") >= 2 end },
        { id = "feuding", label = "Feuding",
            stat = function(a) return st(a, "ego") >= 55 end,
            evidence = function(e) return ev(e, "feuds") >= 1 end },
    }

    M.ORG = {
        { id = "ruthless_owner", label = "Ruthless owner",
            stat = function(pr) return st(pr, "ruthlessness") >= 68 end,
            evidence = function(e) return ev(e, "firings") >= 2 end },
        { id = "patient_owner", label = "Patient owner",
            stat = function(pr) return st(pr, "patience") >= 68 end,
            evidence = function(e) return ev(e, "seasonsWithoutFiring") >= 3 end },
        { id = "cash_strapped", label = "Cash-strapped",
            stat = function() return true end,
            evidence = function(e) return ev(e, "lowCashDays") >= 7 end },
        { id = "big_spender", label = "Big spender",
            stat = function(pr) return st(pr, "financial_discipline") <= 35 end,
            evidence = function(e) return ev(e, "devSpendSeason") > 0 and ev(e, "devSpendRank") <= 3 end },
        { id = "new_blood", label = "New team",
            stat = function() return true end,
            evidence = function(e) return ev(e, "seasonsActive") <= 1 end },
    }

    local function derive(list, statArg, person, evidence, ctx)
        local out = {}
        for _, t in ipairs(list) do
            if t.stat(statArg, person, ctx) and t.evidence(evidence or {}, person, ctx) then
                out[#out + 1] = { id = t.id, label = t.label }
            end
        end
        return out
    end

    --- Earned tags for a driver: `person` carries attrs and morale; `ctx` = { age }.
    function M.driver(person, evidence, ctx)
        return derive(M.DRIVER, person.attrs or {}, person, evidence, ctx)
    end

    --- Earned tags for an org, from its owner's principal traits and org evidence.
    function M.org(principal, evidence)
        return derive(M.ORG, principal or {}, nil, evidence, nil)
    end

    --- Labels only, the shape that leaves the server.
    function M.labels(tags)
        local out = {}
        for i, t in ipairs(tags or {}) do out[i] = t.label end
        return out
    end

    return M
end)
