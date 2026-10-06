-- Moody in the Paddock (doc 47 §1.8, L310): a lured purse is weighed by each driver -- who turns up, how hard they
-- drive -- and nothing is posted past an open run's possible end.
local SEASON = "2026-S4"
local worldCache
local function world(T)
    if not worldCache then worldCache = T.Core.get("paddock.world").genesis(777, SEASON) end
    return worldCache
end

return {
    a_lure_changes_who_turns_up_person_by_person = function(T)
        local W = T.Core.get("paddock.world")
        local Moody = T.Core.get("week.moody")
        local w = world(T)
        local keen = function(person) return (Moody.pull(1.0, 2.5, { aggression = person.attrs.aggression, discipline = person.attrs.discipline, need = 1 })) end
        local scared = function() return 0.4 end
        local plain, lured, shy = 0, 0, 0
        for r = 1, 40 do
            local race = { raceId = "lure" .. r, seriesId = "street_b", tier = "street", opensAt = 5000 }
            local a = W.raceField(w, race)
            local _, absentLured = W.raceField(w, race, keen)
            local _, absentShy = W.raceField(w, race, scared)
            local _, absentPlain = W.raceField(w, race)
            for _ in pairs(absentPlain) do plain = plain + 1 end
            for _ in pairs(absentLured) do lured = lured + 1 end
            for _ in pairs(absentShy) do shy = shy + 1 end
            T.ok(#a > 0)
        end
        T.ok(lured <= plain, "broke drivers chase the money: fewer stay away")
        T.ok(shy > plain, "a purse that scares people off empties the pool")
        -- deterministic: the same race, the same pull, the same field
        local race = { raceId = "same", seriesId = "street_c", tier = "street", opensAt = 5000 }
        local x, y = W.raceField(w, race, keen), W.raceField(w, race, keen)
        T.eq(#x, #y)
    end,

    the_bait_is_driven_harder = function(T)
        local Sim = T.Core.get("paddock.sim")
        local H = T.Core.get("vocabulary.hash")
        local Attr = T.Core.get("paddock.attributes")
        local function field(risk)
            local out = {}
            for i = 1, 12 do
                local a = {}
                for _, k in ipairs(Attr.SKILLS) do a[k] = 50 end
                for _, k in ipairs(Attr.TRAITS) do a[k] = 50 end
                out[i] = { id = "d" .. i, orgId = "o" .. i, attrs = a, carPerf = 50, form = 0, lureRisk = risk }
            end
            return out
        end
        local calm, baited = 0, 0
        for k = 1, 300 do
            for _, e in ipairs(Sim.simulate(field(nil), { distanceM = 4800 }, { roadWetness = 0, light = "night" }, H.stream("bait", k), { baseSec = 160, light = true, tier = "street" }).entrants) do
                if e.state ~= "finished" then calm = calm + 1 end
            end
            for _, e in ipairs(Sim.simulate(field(1.6), { distanceM = 4800 }, { roadWetness = 0, light = "night" }, H.stream("bait", k), { baseSec = 160, light = true, tier = "street" }).entrants) do
                if e.state ~= "finished" then baited = baited + 1 end
            end
        end
        T.ok(baited > calm, ("more DNFs when the bait is driven hard: %d vs %d"):format(baited, calm))
    end,

    nothing_is_posted_past_an_open_runs_possible_end = function(T)
        local S = T.Core.get("paddock.season")
        local W = T.Core.get("week.clock")
        local cfg = { epoch = W.DEFAULT_EPOCH, daySeconds = 86400, boundarySod = 12 * 3600 }
        local runs = {}
        S.setWeek(function(utc)
            local rec = W.locate(cfg, runs, utc)
            if not rec then return nil end
            return { run = rec.run, startUtc = rec.startUtc, endUtc = rec.endUtc or rec.provisionalEnd, beyond = rec.beyond }
        end)
        local ok, err = pcall(function()
            local start = W.runBounds(cfg, 1)
            local noon3 = W.boundary(cfg, start, 3)
            -- the three hours either side of the first possible end: finales before it, nothing after it
            local slots = S.window(noon3 - 3 * 3600, noon3 + 3 * 3600)
            local before, after, finales = 0, 0, 0
            for _, s in ipairs(slots) do
                if s.utc < noon3 then before = before + 1 else after = after + 1 end
                if s.finale then finales = finales + 1 end
            end
            T.ok(finales > 0, "the finales run before the possible end")
            T.eq(after, 0, "undecided: nothing posted past it")
            -- the run survived noon of Day 3: the next hours are posted, and its finales move to noon of Day 4
            runs[1] = { survived = 3 }
            local later = S.window(noon3, noon3 + 3 * 3600)
            T.ok(#later > 0, "a survivor's Day 4 is on the calendar")
            local noon4 = W.boundary(cfg, start, 4)
            local f4 = 0
            for _, s in ipairs(S.window(noon4 - 3 * 3600, noon4)) do if s.finale then f4 = f4 + 1 end end
            T.ok(f4 > 0, "finales before every possible end (doc 47 Q6 default)")
            -- it collapsed instead: the next run's Cup starts at that noon
            runs[1] = { endUtc = noon3, endKind = "collapse", survived = 2 }
            T.eq(S.cupOf(noon3 + 60).run, 2)
            T.eq(S.cupOf(noon3 - 60).run, 1)
        end)
        S.setWeek(nil)
        if not ok then error(err, 0) end
    end,
}
