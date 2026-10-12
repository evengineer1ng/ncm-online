-- paddock.scouting: simulated careers, impressions, knowledge (doc 44 §4.3).
local function roll(T, n, tier, seed)
    local Attr, Hash = T.Core.get("paddock.attributes"), T.Core.get("vocabulary.hash")
    local rng = Hash.stream(seed or "scout-test", tier)
    local out = {}
    for i = 1, n do
        local age = rng:int(18, 36)
        out[i] = { person = { id = ("d%03d"):format(i), attrs = Attr.rollDriver(rng, tier, age), morale = 50, evidence = {} }, age = age }
    end
    return out
end

local function has(list, label) for _, l in ipairs(list) do if l == label then return true end end return false end

return {
    reports_replay_identically = function(T)
        local S = T.Core.get("paddock.scouting")
        local d = roll(T, 1, "regional")[1]
        local a = S.report(d.person, { age = d.age, seed = "w1" })
        local copy = { id = d.person.id, attrs = d.person.attrs, morale = 50, evidence = {} }
        local b = S.report(copy, { age = d.age, seed = "w1" })
        T.eq(table.concat(a.tags, "|"), table.concat(b.tags, "|"))
        T.eq(a.record.starts, b.record.starts); T.eq(a.record.podiums, b.record.podiums); T.eq(a.record.dnfs, b.record.dnfs)
        T.ok(S.history(d.person, { age = d.age, seed = "w1" }).simulated, "a career is marked simulated")
    end,

    no_driver_goes_unread = function(T)
        -- the 2026-10-09 defect: 74% of Online's drivers showed no tag at all
        local S = T.Core.get("paddock.scouting")
        for _, tier in ipairs({ "street", "regional", "pro", "premier" }) do
            for _, d in ipairs(roll(T, 60, tier)) do
                local r = S.report(d.person, { age = d.age, seed = "w1" })
                T.ok(#r.tags >= 3, d.person.id .. " " .. tier .. " has a readable report: " .. table.concat(r.tags, ","))
            end
        end
    end,

    reports_carry_no_hidden_keys = function(T)
        local S, P = T.Core.get("paddock.scouting"), T.Core.get("paddock.projection")
        for _, d in ipairs(roll(T, 20, "pro")) do
            T.ok(P.assertNoHidden({ rows = { S.report(d.person, { age = d.age, seed = "w1", own = true }) } }))
        end
    end,

    knowledge_grows_and_own_drivers_are_best_known = function(T)
        local S = T.Core.get("paddock.scouting")
        T.eq(S.knowledge(0, 0, false).label, "Scouting report")
        T.eq(S.knowledge(0, 0, false).shown, 3)
        T.ok(S.knowledge(12, 0, false).shown > S.knowledge(0, 0, false).shown)
        T.eq(S.knowledge(0, 0, true).label, "Well known")
        -- a fresh 18-year-old has no career: a thin report; the same driver on your team reads fully
        local d = roll(T, 1, "street")[1]
        d.age = 18
        local thin = S.report(d.person, { age = 18, seed = "w1" })
        local full = S.report(d.person, { age = 18, seed = "w1", own = true })
        T.eq(thin.knowledge, "Scouting report")
        T.ok(#full.tags >= #thin.tags)
    end,

    pace_reads_against_the_viewing_tier = function(T)
        local S = T.Core.get("paddock.scouting")
        local a = { pace = 66, race_pace = 66, consistency = 66 }
        local function paceWord(level)
            for _, i in ipairs(S.impressions(a, { age = 26, level = level })) do if i.pace then return i.label end end
        end
        T.eq(paceWord("street"), "Rapid")
        T.ok(paceWord("premier") == "Workmanlike" or paceWord("premier") == "Limited", "the same driver is ordinary in the premier: " .. tostring(paceWord("premier")))
    end,

    the_words_predict_results = function(T)
        -- the point of the report: a manager reading the words picks better than chance. A career is raced against
        -- peers of the driver's own level, so the words are read against that level too: among peers, the drivers
        -- called quick podium more than the drivers called limited, and the drivers called incident-prone retire
        -- more than the ones called conservative.
        local S = T.Core.get("paddock.scouting")
        local fast, slow, risky, safe = { p = 0, s = 0 }, { p = 0, s = 0 }, { d = 0, s = 0 }, { d = 0, s = 0 }
        local pool = roll(T, 120, "regional", "predict")
        for _, d in ipairs(roll(T, 120, "street", "predict")) do pool[#pool + 1] = d end
        for _, d in ipairs(pool) do
            d.age = 30
            local h = S.history(d.person, { age = 30, seed = "w1" })
            local words = {}
            for _, i in ipairs(S.impressions(d.person.attrs, { age = 30, level = h.level })) do words[#words + 1] = i.label end
            if has(words, "Quick") or has(words, "Rapid") then fast.p, fast.s = fast.p + h.podiums, fast.s + h.starts end
            if has(words, "Limited") or has(words, "Struggling for pace") then slow.p, slow.s = slow.p + h.podiums, slow.s + h.starts end
            if has(words, "Incident-prone") or has(words, "Trouble magnet") then risky.d, risky.s = risky.d + h.dnfs, risky.s + h.starts end
            if has(words, "Conservative") or has(words, "Safe pair of hands") then safe.d, safe.s = safe.d + h.dnfs, safe.s + h.starts end
        end
        T.ok(fast.s > 0 and slow.s > 0 and risky.s > 0 and safe.s > 0, "every group is populated")
        T.ok(fast.p / fast.s > 2 * (slow.p / slow.s), ("quick podium rate %.3f vs limited %.3f"):format(fast.p / fast.s, slow.p / slow.s))
        T.ok(risky.d / risky.s > safe.d / safe.s, ("incident-prone DNF rate %.3f vs conservative %.3f"):format(risky.d / risky.s, safe.d / safe.s))
    end,

    a_simulated_career_earns_tags = function(T)
        -- evidence was the gate: with a career behind them, a veteran with real wet skill can be a proven rain driver
        local S = T.Core.get("paddock.scouting")
        local merged = S.mergedEvidence({ starts = 2, wetTop3 = 1, recent = { 4 } }, { starts = 50, wetTop3 = 3 })
        T.eq(merged.starts, 52); T.eq(merged.wetTop3, 4); T.eq(merged.recent[1], 4)
        local person = { id = "x", attrs = { wet_weather_skill = 85 }, morale = 50, evidence = {} }
        local Tags = T.Core.get("paddock.tags")
        local labels = Tags.labels(Tags.driver(person, merged, { age = 30 }))
        T.ok(has(labels, "Rain specialist"))
    end,
}
