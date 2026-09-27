-- session.quali, telemetry, driver.progression, onboarding.questionnaire (Batch 1).
local function gatesFor(T)
    local Gates = T.Core.get("course.gates")
    return Gates.build({ name = "r", start = { x = 0, y = 0, z = 0, name = "s" }, finish = { x = 0, y = 1000, z = 0, name = "f" } })
end
local function at(g) return { x = g.x, y = g.y } end

return {
    -- `rawSec` is the pure gate-to-gate duration and `runSec` is the official time. A caller that has to
    -- subtract one from the other is a caller that will eventually subtract the wrong thing -- and for a time
    -- trial on the race kernel the official time folds in a PENALTY as well, so the arithmetic differs by
    -- session kind. Both are returned so nothing has to know which kind it is looking at.
    raw_and_official_durations_are_both_reported = function(T)
        local Q = T.Core.get("session.quali")
        local g = gatesFor(T)
        local s = Q.new({ sessionId = "p2", kind = "practice", startsAt = 100, windowSec = 400, gates = g,
            entrants = { { driverId = "a", slot = 1 } } })
        Q.step(s, 100)
        Q.report(s, { driverId = "a", gateIndex = 1, now = 105, position = at(g[1]) })
        Q.incident(s, "a", { kind = "car", band = 1, seconds = 3 }, 120)
        local r = Q.report(s, { driverId = "a", gateIndex = 2, now = 165, position = at(g[2]) })
        T.eq(r.rawSec, 60, "sixty seconds of driving")
        T.eq(r.runSec, 63, "and a sixty-three second lap once the incident is paid")
        T.eq(r.incidentSec, 3)
        T.eq(r.finishedAt - r.startedAt, r.rawSec, "the interval and the raw duration agree")
    end,
    -- The run boundaries and the latched machine leave the kernel (L165). `r.run` is discarded at the finish
    -- and it held the only record of WHEN the lap happened; without these a stored lap is a duration with no
    -- place in time, which is why no practice run could be located against the telemetry it was driven
    -- through. The machine is latched at the START line, not read when the session closes.
    a_finished_run_reports_its_interval_and_its_machine = function(T)
        local Q = T.Core.get("session.quali")
        local g = gatesFor(T)
        local s = Q.new({ sessionId = "p", kind = "practice", startsAt = 100, windowSec = 400, gates = g,
            entrants = { { driverId = "a", slot = 1 } } })
        Q.step(s, 100)
        local shion = { assetId = "33333333-3333-4333-a333-333333333333", record = "Vehicle.v_sport2_mizutani_shion_player" }
        T.eq(Q.report(s, { driverId = "a", gateIndex = 1, now = 105, position = at(g[1]), machine = shion }).runStarted, true)
        local r = Q.report(s, { driverId = "a", gateIndex = 2, now = 165, position = at(g[2]) })
        T.eq(r.finished, true)
        T.eq(r.startedAt, 105, "the interval the lap occupies")
        T.eq(r.finishedAt, 165)
        T.eq(r.runSec, 60)
        T.eq(r.incidentSec, 0)
        T.eq(r.improved, true, "the kernel says whether this is a new best, so nobody recomputes it")
        T.truthy(r.machine); T.eq(r.machine.record, "Vehicle.v_sport2_mizutani_shion_player")

        -- A slower second run carries its own interval and is NOT an improvement.
        local caliburn = { assetId = "55555555-5555-4555-8555-555555555555", record = "Vehicle.v_sport1_rayfield_caliburn_player" }
        Q.report(s, { driverId = "a", gateIndex = 1, now = 200, position = at(g[1]), machine = caliburn })
        local r2 = Q.report(s, { driverId = "a", gateIndex = 2, now = 290, position = at(g[2]) })
        T.eq(r2.runSec, 90); T.eq(r2.startedAt, 200); T.eq(r2.finishedAt, 290)
        T.eq(r2.improved, false, "a slower lap is not a new best")
        T.eq(r2.bestSec, 60, "and the best is unchanged")
        T.eq(r2.machine.record, "Vehicle.v_sport1_rayfield_caliburn_player",
            "the car the driver refitted to between runs, latched at that run's own start")

        -- An incident inside the run is reported separately from the raw duration, so a stored lap can say
        -- what it was penalised for rather than only what it totalled.
        Q.report(s, { driverId = "a", gateIndex = 1, now = 300, position = at(g[1]), machine = shion })
        Q.incident(s, "a", { kind = "car", band = 1, seconds = 2 }, 310)
        local r3 = Q.report(s, { driverId = "a", gateIndex = 2, now = 350, position = at(g[2]) })
        T.eq(r3.runSec, 52); T.eq(r3.incidentSec, 2); T.eq(r3.improved, true)
    end,
    windows_scale_with_the_route = function(T)
        -- Windows come from the route length, generous, rounded up to whole minutes (owner, 2026-09-21).
        local F = T.Core.get("competition.format")
        T.eq(F.windowFor(550, 240), 240, "Troll Pass (550 m): the 4-min floor")
        T.eq(F.windowFor(2000, 240), 360, "2 km: 2×133 s + 60 s = 5.4 min → 6 min")
        T.eq(F.windowFor(6800, 240), 1200, "6.8 km: 2×453 s + 60 s = 16.1 min → 17 → rounded up to 20 min")
        local plan = F.plan("weekend", { lengthM = 6800 })
        T.eq(plan[1].kind, "quali"); T.eq(plan[1].windowSec, 1200); T.eq(plan[2].windowSec, nil)
        T.eq(F.plan("weekend")[1].windowSec, 240, "no length: the format's fixed window stands")
    end,
    quali_one_run_closes_when_every_run_is_in = function(T)
        -- Weekend qualifying is one run per driver (owner, 2026-09-21): a second start is refused and the
        -- window closes as soon as every entrant's run is in, without waiting for the clock.
        local Q = T.Core.get("session.quali")
        local F = T.Core.get("competition.format")
        local plan = F.plan("weekend")
        T.eq(plan[1].kind, "quali"); T.eq(plan[1].maxRuns, 1); T.eq(plan[2].maxRuns, nil)
        local g = gatesFor(T)
        local s = Q.new({ sessionId = "q1", kind = "quali", startsAt = 100, windowSec = 240, maxRuns = 1, gates = g,
            entrants = { { driverId = "a", slot = 1 }, { driverId = "b", slot = 2 } } })
        Q.step(s, 100)
        T.eq(Q.report(s, { driverId = "a", gateIndex = 1, now = 105, position = at(g[1]) }).runStarted, true)
        T.eq(Q.report(s, { driverId = "a", gateIndex = 1, now = 110, position = at(g[1]) }).runStarted, true, "a restart during the run is still the same run")
        T.eq(Q.report(s, { driverId = "a", gateIndex = 2, now = 160, position = at(g[2]) }).finished, true)
        T.eq(Q.report(s, { driverId = "a", gateIndex = 1, now = 170, position = at(g[1]) }).reason, "no_runs_left")
        T.eq(Q.step(s, 175)[1], nil, "b has not run yet: stays open")
        T.eq(s.phase, "open")
        Q.report(s, { driverId = "b", gateIndex = 1, now = 180, position = at(g[1]) })
        T.eq(Q.step(s, 185)[1], nil, "b is on the road: stays open")
        Q.report(s, { driverId = "b", gateIndex = 2, now = 230, position = at(g[2]) })
        local e = Q.step(s, 231)
        T.eq(s.phase, "complete"); T.eq(e[#e].type, "complete"); T.eq(e[#e].reason, "all_runs_done")
        T.eq(Q.publicView(s).maxRuns, 1)
    end,
    quali_best_of_runs_and_window = function(T)
        local Q = T.Core.get("session.quali")
        local g = gatesFor(T)
        local s = Q.new({ sessionId = "q", kind = "quali", startsAt = 100, windowSec = 200, gates = g,
            entrants = { { driverId = "a", slot = 1 }, { driverId = "b", slot = 2 } } })
        T.eq(s.phase, "forming")
        T.eq(Q.report(s, { driverId = "a", gateIndex = 1, now = 90, position = at(g[1]) }).reason, "not_open")
        local e = Q.step(s, 100); T.eq(e[1].type, "phase"); T.eq(s.phase, "open")
        T.eq(Q.report(s, { driverId = "a", gateIndex = 2, now = 101, position = at(g[2]) }).reason, "no_run")
        T.eq(Q.report(s, { driverId = "a", gateIndex = 1, now = 105, position = at(g[1]) }).runStarted, true)
        T.eq(Q.report(s, { driverId = "a", gateIndex = 1, now = 106, position = at(g[1]) }).reason, "run_just_started")
        local r = Q.report(s, { driverId = "a", gateIndex = 2, now = 165, position = at(g[2]) })
        T.eq(r.finished, true); T.eq(r.runSec, 60); T.eq(s.entrants.a.bestSec, 60); T.eq(s.entrants.a.runs, 1)
        Q.report(s, { driverId = "a", gateIndex = 1, now = 170, position = at(g[1]) })
        Q.incident(s, "a", { kind = "car", band = 1, seconds = 2 }, 180)
        Q.report(s, { driverId = "a", gateIndex = 2, now = 225, position = at(g[2]) })   -- 55 s + 2 s incident = 57
        T.eq(s.entrants.a.bestSec, 57, "best run counts, incidents add to the run")
        Q.report(s, { driverId = "b", gateIndex = 1, now = 200, position = at(g[1]) })
        Q.report(s, { driverId = "b", gateIndex = 1, now = 210, position = at(g[1]) })   -- restart: aborts the first run
        T.eq(s.entrants.b.runs, 2); T.eq(s.entrants.b.bestSec, nil)
        e = Q.step(s, 300)
        T.eq(s.phase, "complete"); T.eq(e[#e].type, "complete")
        local res = e[#e].results
        T.eq(res[1].driverId, "a"); T.eq(res[1].bestSec, 57); T.eq(res[2].state, "no_time")
        local v = Q.publicView(s)
        T.eq(v.kind, "quali"); T.eq(v.closesAt, 300); T.eq(v.entrants[1].bestSec, 57)
    end,

    telemetry_progress_ring_and_batches = function(T)
        local Tm = T.Core.get("telemetry")
        local g = gatesFor(T)
        local course = Tm.polyline(g)
        T.eq(course.lengthM, 1000)
        local p = Tm.progress(course, { x = 5, y = 250 })
        T.eq(p.m, 250); T.eq(p.seg, 1); T.eq(p.offM, 5)
        local ring = Tm.Ring.new(4)
        for i = 1, 6 do ring:push({ t = i, x = 0, y = i * 10, v = 10 }) end
        T.eq(ring.count, 4); T.eq(ring:last(1).t, 6); T.eq(ring:last(4).t, 3); T.eq(ring:last(5), nil)
        T.eq(#ring:window(2), 3)
        T.eq(Tm.avgSpeed(ring, 10), 10)
        T.eq(Tm.correctedM(500, 4, 10), 460); T.eq(Tm.correctedM(10, 4, 10), 0)
        local batch = Tm.decodeBatch({ { 1, 0, 0, 0, 5, 1, true, 1.0 }, { 1.2, 0, 4, 0, 6, 1, true, 1.0 } })
        T.eq(#batch, 2); T.eq(batch[2].v, 6); T.eq(batch[2].og, true)
        local _, why = Tm.decodeBatch({ { 1, 0, 0, 0 }, { 0.5, 0, 1, 0 } }); T.eq(why, "time_not_monotonic")
        _, why = Tm.decodeBatch({ { 1, 0, 0, 0 }, { 2, 5000, 0, 0 } }); T.match(why, "^jump")
        _, why = Tm.decodeBatch({}); T.eq(why, "batch_size")
        _, why = Tm.decodeBatch({ { "x", 0, 0 } }); T.eq(why, "field_type:t")
        T.eq(Tm.sectors({ [1] = 10, [2] = 25, [3] = 45 }, 3)[2], 20)
    end,

    progression_licence_sr_rating = function(T)
        local P = T.Core.get("driver.progression")
        local st = P.newState()
        local ctx = { disciplineId = "street_sprint", classId = "street_open", sessionKind = "race", fieldSize = 4, sessionId = "s1" }
        st = P.apply(st, { state = "finished", position = 1, incidentCount = 0 }, ctx)
        T.eq(st.licences.street_sprint.clean, 1); T.eq(st.licences.street_sprint.level, "rookie")
        T.ok(math.abs(st.sr.sr - 5.05) < 1e-9); T.eq(st.ratings.street_open.rating, 1006)
        T.eq(#st.accomplishments, 3, "first_finish, first_win, clean_race")
        for i = 2, 3 do st = P.apply(st, { state = "finished", position = 2, incidentCount = 0 }, { disciplineId = "street_sprint", classId = "street_open", sessionKind = "race", fieldSize = 4, sessionId = "s" .. i }) end
        T.eq(st.licences.street_sprint.level, "licensed", "three clean sessions")
        local before = st.sr.sr
        st = P.apply(st, { state = "finished", position = 4, incidentCount = 2, incidents = { { band = 2 }, { band = 1 } } }, ctx)
        T.ok(st.sr.sr < before, "incidents cost SR"); T.eq(st.sr.incidents, 2)
        T.eq(st.licences.street_sprint.clean, 3, "a dirty finish does not add a clean session")
        local n = #st.accomplishments
        st = P.apply(st, { state = "finished", position = 1, incidentCount = 0 }, { disciplineId = "street_sprint", classId = "street_open", sessionKind = "quali", fieldSize = 4 })
        T.eq(#st.accomplishments, n, "quali sessions do not progress anything")
        T.match(P.describe(st), "Licence: street_sprint licensed")
    end,

    kb38_once_only_accomplishments_are_granted_once = function(T)
        -- KB-38. `grant(kind, refId, once)` guarded with `once and nil or refId`, which in Lua always yields
        -- refId -- so "have I ever earned this?" was asked as "have I earned this in THIS session?", which no
        -- earlier session can answer yes to. Every race re-granted first_finish and first_win. The live tell was
        -- `accomplishments +2` on a three-incident race by a driver who already held both, and a profile reading
        -- `first_finish x2, first_win x2`. The accomplishment table's unique key includes ref_id, so INSERT
        -- IGNORE did not catch the duplicates either -- they are real rows.
        local P = T.Core.get("driver.progression")
        local function race(st, n, incidents)
            return P.apply(st, { state = "finished", position = 1, incidentCount = incidents or 0 },
                { disciplineId = "street_sprint", classId = "street_open", sessionKind = "race", fieldSize = 4, sessionId = "s" .. n })
        end
        local st = race(P.newState(), 1)
        local _, _, newAcc = P.apply(st, { state = "finished", position = 1, incidentCount = 3, incidents = { { band = 3 }, { band = 3 }, { band = 2 } } },
            { disciplineId = "street_sprint", classId = "street_open", sessionKind = "race", fieldSize = 4, sessionId = "s2" })
        T.eq(#newAcc, 0, "a dirty win by a driver who already finished and won grants nothing")

        st = race(race(race(st, 2), 3), 4)
        local kinds = {}
        for _, a in ipairs(st.accomplishments) do kinds[a.kind] = (kinds[a.kind] or 0) + 1 end
        T.eq(kinds.first_finish, 1, "first_finish is once in a lifetime, not once a race")
        T.eq(kinds.first_win, 1, "so is first_win")
        T.eq(kinds.clean_race, 4, "clean_race is repeatable: one per clean session")
    end,

    solo_entry_is_a_time_trial_not_a_win = function(T)
        -- L67 / IDEA-001. This case was live for two races before anyone noticed: a driver alone on the server
        -- finished P1 of 1 and was granted `first_win`. A field of one is a TIME TRIAL -- real, recorded and
        -- classified, earning the finish, the clean-race credit and SR -- but it cannot be *won*, because
        -- nobody was beaten. Anything derived from finishing position needs an opponent.
        local P = T.Core.get("driver.progression")
        T.eq(P.isTimeTrial({ fieldSize = 1 }), true, "one entrant is a time trial")
        T.eq(P.isTimeTrial({ fieldSize = 0 }), true, "no field at all is a time trial")
        T.eq(P.isTimeTrial({}), true, "an unknown field size is not a contest")
        T.eq(P.isTimeTrial({ fieldSize = 2 }), false, "two entrants is a race")

        local solo = { disciplineId = "street_sprint", classId = "street_open", sessionKind = "race", fieldSize = 1, sessionId = "tt1" }
        local st = P.apply(P.newState(), { state = "finished", position = 1, incidentCount = 0 }, solo)
        local kinds = {}
        for _, a in ipairs(st.accomplishments) do kinds[a.kind] = (kinds[a.kind] or 0) + 1 end
        T.eq(kinds.first_win, nil, "a field of one grants no win")
        T.eq(kinds.first_finish, 1, "the finish still counts")
        T.eq(kinds.clean_race, 1, "the clean run still counts")
        T.eq(kinds.first_time_trial, 1, "the run is acknowledged as a time trial")
        T.eq(st.ratings.street_open, nil, "no rating movement without an opponent")
        T.eq(st.licences.street_sprint.clean, 1, "a time trial is still a clean session")
        T.ok(st.sr.sr > 5.0, "SR still moves on a clean time trial")

        -- the same result in a contested field is a win
        local duel = { disciplineId = "street_sprint", classId = "street_open", sessionKind = "race", fieldSize = 2, sessionId = "r1" }
        local st2 = P.apply(P.newState(), { state = "finished", position = 1, incidentCount = 0 }, duel)
        local kinds2 = {}
        for _, a in ipairs(st2.accomplishments) do kinds2[a.kind] = (kinds2[a.kind] or 0) + 1 end
        T.eq(kinds2.first_win, 1, "beating someone is a win")
        T.eq(kinds2.first_time_trial, nil, "a contested race is not a time trial")
        T.ok(st2.ratings.street_open ~= nil, "rating moves in a contested field")
    end,

    questionnaire_validate_affinity_prompt = function(T)
        local Q = T.Core.get("onboarding.questionnaire")
        local Teams = T.Core.get("competition.teams")
        for _, q in ipairs(Q.QUESTIONS) do
            for _, o in ipairs(q.options) do
                for teamId in pairs(o.weights) do T.ok(Teams.byId(teamId), "weight team exists: " .. teamId) end
            end
        end
        T.eq(Q.validate(1, { "a", "a", "a", "a", "a", "a" }), true)
        T.eq(select(2, Q.validate(2, { "a", "a", "a", "a", "a", "a" })), "version_mismatch")
        T.eq(select(2, Q.validate(1, { "a", "a" })), "answer_count")
        T.match(select(2, Q.validate(1, { "a", "z", "a", "a", "a", "a" })), "unknown_option")
        local aff = Q.affinity({ "d", "c", "a", "d", "b", "b" })   -- raven-heavy answers
        T.eq(Q.top(aff), "raven")
        T.eq(aff.raven, 1.0, "normalised to the max")
        T.ok(aff.kimiko < 1.0)
        local doc = Q.document({ "a", "a", "a", "a", "a", "a" }, 123)
        T.eq(doc.version, 1); T.eq(doc.completedAt, 123); T.ok(doc.affinity.rayfield)
        T.match(Q.prompt(1), "^Q1/6"); T.eq(Q.prompt(9), nil)
    end,

    json_round_trip = function(T)
        local J = T.Core.get("vocabulary.json")
        local doc = { version = 1, answers = { "a", "b" }, affinity = { raven = 1, kimiko = 0.5 }, completedAt = 123, nested = { ok = true, none = false }, text = "q\"uote" .. "\\" .. "n" }
        local s = J.encode(doc)
        T.match(s, '"version":1'); T.match(s, '"answers":%["a","b"%]'); T.match(s, '"kimiko":0.5')
        local back = J.decode(s)
        T.eq(back.version, 1); T.eq(back.answers[2], "b"); T.eq(back.affinity.raven, 1); T.eq(back.nested.none, false); T.eq(back.text, "q\"uote" .. "\\" .. "n")
        T.eq(J.encode({}), "{}"); T.eq(J.decode("[1,2,3]")[3], 3); T.eq(J.decode("null"), nil)
        local _, why = J.decode("{bad"); T.ok(why ~= nil, "bad json reports a reason")
        T.eq(J.decode(' { "a" : [ { "b" : -2.5e1 } ] } ').a[1].b, -25)
    end,
}
