-- course.generator (L236): every eligible race from the owner's hand-picked nodes, ids that resolve anywhere, and the
-- authored-only kinds (drag, ovals) kept out.
return {
    codes_are_unique_and_ids_round_trip = function(T)
        local G = T.Core.get("course.generator")
        local Routes = T.Core.get("course.routes")
        local pool = G.pool()
        T.ok(#pool >= 30, "the authored nodes are the pool (" .. #pool .. ")")
        local id = G.encode({ "hanford_overpass_-1281_-1107", "chapel_-1829_-2030", "stadium_-1326_-1656" })
        T.ok(G.isGenerated(id) and #id <= 32, "a generated id is short and marked: " .. id)
        local r = Routes.resolve(id)
        T.ok(r ~= nil, "a generated id resolves with nothing registered")
        T.eq(r.name, "Hanford Overpass to Stadium via Chapel", "unnamed routes read as their places")
        T.eq(r.checkpoints, 1, "one checkpoint")
        T.ok(r.generated == true and r.intermediate[1].heading == nil, "a checkpoint gate faces the way the race arrives")
        T.ok(r.distanceM > 0, "summed legs")
        T.eq(Routes.resolve("gen-zzzz-zzzy"), nil, "an unknown code does not resolve")
    end,

    the_filter_holds = function(T)
        local G = T.Core.get("course.generator")
        local opts = { minM = 1200, maxM = 4000, legMinM = 450, detourMax = 1.9, checkpoints = 2, checkpointShare = 1 }
        local sprints = G.sprints(opts)
        T.ok(#sprints > 100, "far more than ten races (" .. #sprints .. " sprints)")
        for _, s in ipairs(sprints) do T.ok(s.lengthM >= 1200 and s.lengthM <= 4000, "sprint length within the filter") end
        local cps, seen = 0, {}
        for k = 1, 200 do
            local id, root = G.pick(opts, "test", k)
            T.ok(id ~= nil, "a pick")
            local Routes = T.Core.get("course.routes")
            local r = Routes.resolve(id)
            T.ok(r.distanceM >= 1200 and r.distanceM <= 4000, "picked route within the filter: " .. id)
            T.ok(r.disciplineId == nil and r.recommendedMode == nil, "the generator never tags a discipline (drag is authored)")
            if (root.checkpoints or 0) > 0 then cps = cps + 1 end
            seen[id] = true
        end
        T.ok(cps > 100, "checkpointed races come out (" .. cps .. " of 200)")
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        T.ok(n > 150, "picks are varied (" .. n .. " distinct of 200)")
        T.eq(G.pick(opts, "test", 7), (G.pick(opts, "test", 7)), "a pick is deterministic")
    end,

    ovals_and_temporaries_stay_out = function(T)
        local G = T.Core.get("course.generator")
        local Nodes = T.Core.get("data.nodes")
        for _, n in ipairs(G.pool()) do T.ok(not n.oval, "no oval node in the pool: " .. n.id) end
        T.ok(Nodes.byId("hanford_overpass_-1281_-1107").raceLegal, "authored nodes are race-legal")
    end,

    the_paddock_races_everywhere = function(T)
        local Season = T.Core.get("paddock.season")
        local Routes = T.Core.get("course.routes")
        local Clock = T.Core.get("world.clock")
        local day = Clock.daysFromCivil(2026, 9, 29)
        local seen, gen, watson, watsonHome = {}, 0, 0, 0
        for _, r in ipairs(Season.dayRhythm(day)) do
            local rid = Season.routeFor(4242, r.seriesId, r.utc)
            local route = Routes.resolve(rid)
            T.ok(route ~= nil, "every scheduled route resolves: " .. tostring(rid))
            seen[rid] = true
            if route.generated then gen = gen + 1 end
            -- an oval night races the league's own district's roundabout, else any (L236): only its street routes must start at home
            if r.seriesId == "street_a" and not route.oval then
                watson = watson + 1
                if route.start.region == "Watson" then watsonHome = watsonHome + 1 end
            end
        end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        T.ok(n >= 80, "a day of 125 races is not a rotation of ten routes (" .. n .. " distinct)")
        T.ok(gen >= 70, "most are generated (" .. gen .. ")")
        T.eq(Season.regionOf("street_a"), "Watson", "street A is the Watson league")
        T.eq(Season.regionOf("street_f"), nil, "street F races the whole city")
        T.eq(watsonHome, watson, "the Watson league starts in Watson")
    end,

    -- L296 (owner, 2026-10-02: "why arent there any ovals on the calendar? they should be semi regular")
    ovals_are_on_the_calendar_semi_regularly = function(T)
        local Season = T.Core.get("paddock.season")
        local Ovals = T.Core.get("data.ovals")
        local Clock = T.Core.get("world.clock")
        local was = Ovals.SCHEDULED
        local function count(on)
            Ovals.SCHEDULED = on
            local ovals, total = 0, 0
            for d = 0, 6 do
                for _, r in ipairs(Season.dayRhythm(Clock.daysFromCivil(2026, 10, 1 + d))) do
                    total = total + 1
                    if Ovals.isOval(Season.routeFor(4242, r.seriesId, r.utc)) then ovals = ovals + 1 end
                end
            end
            return ovals, total
        end
        local on, total = count(true)
        local off = count(false)
        Ovals.SCHEDULED = was
        T.ok(on >= total * 0.05 and on <= total * 0.2, ("a week has ovals, a minority (%d of %d)"):format(on, total))
        T.ok(on / 7 >= 6, ("every day has several (%.1f a day)"):format(on / 7))
        T.eq(off, 0, "switched off (ovalsScheduled = false), none")
    end,

    multiplayer_series_race_generated_routes = function(T)
        local Cal = T.Core.get("competition.calendar")
        local Routes = T.Core.get("course.routes")
        local series = { seriesId = "city_cup", name = "NCM City Cup", rulesetId = "street_sprint_v0",
            cadence = { everyMinutes = 20, offsetMinutes = 0 },
            generator = { minM = 1200, maxM = 4500, checkpoints = 2, checkpointShare = 0.5, share = 0.75 },
            routes = { { rootId = "root_hanford_overpass_1281_1107__to__stadium_1326_1656" } } }
        T.ok(Cal.validateSeries(series), "a series with a generator validates")
        local a = Cal.materialize(series, 1790000000, 24 * 3600)
        local b = Cal.materialize(series, 1790000000, 24 * 3600)
        local gen, cps, distinct = 0, 0, {}
        for i, e in ipairs(a) do
            T.eq(e.routeId, b[i].routeId, "re-materialising picks the same route")
            local r = Routes.resolve(e.routeId)
            T.ok(r ~= nil, "every event's route resolves")
            if e.generated then
                gen = gen + 1
                T.ok(r.distanceM >= 1200 and r.distanceM <= 4500, "within the series filter")
                if e.via and #e.via > 0 then cps = cps + 1 end
            end
            distinct[e.routeId] = true
        end
        local n = 0
        for _ in pairs(distinct) do n = n + 1 end
        T.ok(gen > #a * 0.6, "most slots are generated (" .. gen .. " of " .. #a .. ")")
        T.ok(cps > 10, "checkpointed races reach the event, carried as `via` (" .. cps .. ")")
        T.ok(n > 40, "a day of City Cup is not ten routes (" .. n .. " distinct)")
        T.falsy(Cal.validateSeries({ seriesId = "x", name = "x", rulesetId = "street_sprint_v0", cadence = { everyMinutes = 20 },
            routes = {}, generator = { minM = 5000, maxM = 1000 } }), "a backwards filter is refused")
    end,
}
