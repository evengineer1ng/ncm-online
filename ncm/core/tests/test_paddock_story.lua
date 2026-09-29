-- paddock.tape, paddock.news, paddock.tags, paddock.projection (doc 44 §4.3, §8).
return {
    tape_events_are_stable_and_ranked = function(T)
        local Tape = T.Core.get("paddock.tape")
        local e = Tape.event("race_result", "pr-premier-1", 100, { facts = { tier = "premier" } })
        T.eq(e.id, "race_result:pr-premier-1")
        local low = Tape.event("race_result", "pr-street_a-1", 100, { facts = { tier = "street" } })
        T.ok(e.salience > low.salience, "a premier result outranks a street result")
        T.ok(Tape.event("fold", "o1", 1, {}).retain, "folds are kept forever")
        T.falsy(Tape.event("race_result", "x", 1, {}).retain)
        T.ok(Tape.validate(e)); T.eq(e.provenance, "simulated")
        T.errors(function() Tape.event("nonsense", "x", 1, {}) end, "unknown kind")
        local lookup = { a = { id = "a", causeRefs = {} }, b = { id = "b", causeRefs = { "a" } }, c = { id = "c", causeRefs = { "b" } } }
        local chain = Tape.explain(lookup, "c")
        T.eq(#chain, 3); T.eq(chain[1].id, "a"); T.eq(chain[3].id, "c")
    end,

    news_only_uses_templates_whose_slots_resolve = function(T)
        local News = T.Core.get("paddock.news")
        local Tape = T.Core.get("paddock.tape")
        T.ok(News.lint())
        local facts = { winner = "Ana Silva", winnerOrg = "Apex Racing", second = "Kenji Mori", third = "Omar Haddad",
            series = "Pacific Championship", route = "The Cut", margin = "1.20s", fieldSize = 12 }
        local e = Tape.event("race_result", "r1", 1, { facts = facts })
        for _, t in ipairs(News.eligible(e)) do
            T.ok(t.id ~= "rr5" and t.id ~= "rr6" and t.id ~= "rr7" and t.id ~= "rr8", "no rain, night or grid story without the fact: " .. t.id)
        end
        local story = News.write(e, {})
        T.ok(story ~= nil)
        T.falsy(story.headline:find("{", 1, true), "every slot filled")
        T.falsy(story.body:find("{", 1, true))
        facts.wet = "rain-soaked"
        local wetIds = {}
        for _, t in ipairs(News.eligible(Tape.event("race_result", "r2", 1, { facts = facts }))) do wetIds[t.id] = true end
        T.ok(wetIds.rr5 and wetIds.rr6, "rain stories unlock with the fact")
        T.eq(News.write(Tape.event("retirement", "p1", 1, { facts = { driver = "X" } })), nil, "unresolvable slots, no story")
    end,

    news_avoids_recent_templates = function(T)
        local News = T.Core.get("paddock.news")
        local Tape = T.Core.get("paddock.tape")
        local facts = { winner = "A", winnerOrg = "B", second = "C", third = "D", series = "S", route = "R", margin = "1s", fieldSize = 8 }
        local recent = {}
        for i = 1, 4 do
            local s = News.write(Tape.event("race_result", "k" .. i, 1, { facts = facts }), recent)
            for _, r in ipairs(recent) do T.neq(s.templateId, r, "no repeat inside the window") end
            recent[#recent + 1] = s.templateId
        end
    end,

    tags_need_stats_and_evidence = function(T)
        local Tags = T.Core.get("paddock.tags")
        local person = { attrs = { wet_weather_skill = 85 }, morale = 50 }
        local function has(list, id) for _, t in ipairs(list) do if t.id == id then return true end end return false end
        T.falsy(has(Tags.driver(person, { wetTop3 = 1 }, { age = 25 }), "rain_specialist"), "skill without evidence")
        T.ok(has(Tags.driver(person, { wetTop3 = 3 }, { age = 25 }), "rain_specialist"), "skill with evidence")
        T.falsy(has(Tags.driver({ attrs = { wet_weather_skill = 50 } }, { wetTop3 = 9 }, { age = 25 }), "rain_specialist"), "evidence without skill")
        T.ok(has(Tags.driver({ attrs = {} }, { starts = 2 }, { age = 20 }), "rookie"))
        T.eq(Tags.labels({ { id = "x", label = "X" } })[1], "X")
    end,

    projection_refuses_hidden_keys = function(T)
        local P = T.Core.get("paddock.projection")
        T.ok(P.assertNoHidden({ rows = { { name = "A", pts = 10, starts = 3, wins = 1 } } }))
        T.errors(function() P.assertNoHidden({ rows = { { name = "A", attrs = { pace = 90 } } } }) end, "hidden key")
        T.errors(function() P.assertNoHidden({ profile = { pace = 90 } }) end, "hidden key")
        T.errors(function() P.assertNoHidden({ x = { y = { personality = {} } } }) end, "hidden key")
        T.errors(function() P.assertNoHidden({ morale = 55 }) end, "hidden key")
        local row = P.boxRow({ position = 1, grid = 3, personId = "p1", finishMs = 91234, gapMs = 0, state = "finished" }, "A", "B")
        T.ok(P.assertNoHidden(row)); T.eq(row.time, 91.23); T.eq(row.gap, "leader")
        T.eq(P.ageBand(24), "early 20s")
    end,
}
