-- paddock.names, paddock.attributes, paddock.world, paddock.season (doc 44 §4, §5).
local SEASON = "2026-S4"

local worldCache
local function world(T)
    if not worldCache then worldCache = T.Core.get("paddock.world").genesis(4242, SEASON) end
    return worldCache
end

return {
    names_are_unique_real_free_and_regional = function(T)
        local Names = T.Core.get("paddock.names")
        local Data = T.Core.get("paddock.names_data")
        local taken, count = {}, 0
        for i = 1, 5000 do
            local n = Names.person(99, "driver", i, { taken = taken })
            count = count + 1
            T.falsy(Names.denied(n.display), "denylisted name generated: " .. n.display)
            T.ok(n.first:sub(1, 1):match("%u"), "capitalised first name: " .. n.first)
        end
        local unique = 0
        for _ in pairs(taken) do unique = unique + 1 end
        T.eq(unique, count, "5000 unique display names")
        T.ok(Names.denied("Lewis Hamilton")); T.ok(Names.denied("george russell"))
        -- cleaning: no leaked surnames among first names, "Ida" capitalised, real-driver blocks gone
        for _, id in ipairs(Data.regionIds()) do
            local r = Data.region(id)
            T.ok(#r.male > 20 and #r.female > 20 and #r.surnames > 20, "region " .. id .. " populated")
            for _, f in ipairs(r.male) do T.ok(f ~= "Vandoorne" and f ~= "Daruvala", "leaked surname in " .. id) end
            for _, f in ipairs(r.female) do T.ok(f ~= "ida" and f ~= "Chadwick" and f ~= "De Silvestro") end
            for _, s in ipairs(r.surnames) do T.ok(s ~= "Verstappen" and s ~= "Senna" and s ~= "Raikkonen" and s ~= "Fittipaldi", s) end
        end
        T.ok(#Data.region("african").surnames >= 30, "authored African surnames")
    end,

    names_are_deterministic = function(T)
        local Names = T.Core.get("paddock.names")
        T.eq(Names.person(7, "driver", "p1").display, Names.person(7, "driver", "p1").display)
        local a = Names.teamName(7, "street", 1); local b = Names.teamName(7, "street", 1)
        T.eq(a, b)
        local c = Names.companyName(7, "s1"); T.eq(c, (Names.companyName(7, "s1")))
        T.eq(Names.short("Summit Capital Motorsport"), "SCM")
    end,

    genesis_counts_match_doc_44 = function(T)
        local W = T.Core.get("paddock.world")
        local w = world(T)
        local byTier, drivers, fa, owners = {}, 0, 0, 0
        for _, oid in ipairs(w.orgOrder) do
            local o = w.orgs[oid]
            byTier[o.tier] = (byTier[o.tier] or 0) + 1
        end
        T.eq(byTier.street, 24); T.eq(byTier.regional, 16); T.eq(byTier.pro, 12); T.eq(byTier.premier, 8)
        for _, pid in ipairs(w.personOrder) do
            local p = w.people[pid]
            if p.role == "driver" and p.state == "active" then drivers = drivers + 1 end
            if p.role == "driver" and p.state == "free_agent" then fa = fa + 1 end
            if p.role == "owner" then owners = owners + 1 end
        end
        T.eq(drivers, 140, "contracted drivers"); T.eq(fa, 40, "free agents"); T.eq(owners, 60)
        T.eq(#W.field(w, "street_a"), 12); T.eq(#W.field(w, "premier"), 16); T.eq(#W.field(w, "regional_b"), 8)
        local seriesCount = 0
        for _ in pairs(w.series) do seriesCount = seriesCount + 1 end
        T.eq(seriesCount, 6)
    end,

    genesis_is_deterministic_and_unique = function(T)
        local W = T.Core.get("paddock.world")
        local a = world(T)
        local b = W.genesis(4242, SEASON)
        T.eq(a.orgs.o001.name, b.orgs.o001.name)
        T.eq(a.people.p00100.display, b.people.p00100.display)
        local names = {}
        for _, pid in ipairs(a.personOrder) do
            local d = a.people[pid].display
            T.falsy(names[d], "duplicate person " .. d); names[d] = true
        end
        local orgNames = {}
        for _, oid in ipairs(a.orgOrder) do
            T.falsy(orgNames[a.orgs[oid].name], "duplicate org"); orgNames[a.orgs[oid].name] = true
        end
        T.neq(W.genesis(4243, SEASON).orgs.o001.name .. W.genesis(4243, SEASON).people.p00010.display,
            a.orgs.o001.name .. a.people.p00010.display, "a different seed is a different world")
    end,

    tiers_are_ordered_by_ability = function(T)
        local Attr = T.Core.get("paddock.attributes")
        local W = T.Core.get("paddock.world")
        local w = world(T)
        local mean = {}
        for _, tier in ipairs({ "street", "regional", "pro", "premier" }) do
            local s, n = 0, 0
            for _, oid in ipairs(w.orgOrder) do
                if w.orgs[oid].tier == tier then
                    for _, d in ipairs(W.drivers(w, oid)) do s = s + Attr.rating(d.attrs); n = n + 1 end
                end
            end
            mean[tier] = s / n
        end
        T.ok(mean.street < mean.regional and mean.regional < mean.pro and mean.pro < mean.premier, "tier means rise")
    end,

    growth_is_daily_and_decline_follows_the_peak = function(T)
        local Attr = T.Core.get("paddock.attributes")
        local young = { pace = 50, potential = 80, peak_start = 27, peak_end = 31, decay_rate = 1 }
        local old = { pace = 70, potential = 80, peak_start = 27, peak_end = 31, decay_rate = 1 }
        for _ = 1, Attr.DAYS_PER_YEAR do Attr.growDay(young, {}, 24, {}); Attr.growDay(old, {}, 38, {}) end
        T.ok(young.pace > 50.5 and young.pace < 55, "a year of growth is a visible step, not a leap: " .. young.pace)
        T.ok(old.pace < 70, "a veteran declines: " .. old.pace)
        T.ok(old.pace > 60, "but not in one season: " .. old.pace)
        T.eq(young.aggression, nil, "traits never grow on their own")
    end,

    daily_rhythm_is_45_races_including_dst_days = function(T)
        local Season = T.Core.get("paddock.season")
        local Clock = T.Core.get("world.clock")
        for _, date in ipairs({ { 2026, 9, 29 }, { 2026, 3, 8 }, { 2026, 11, 1 }, { 2027, 1, 12 } }) do
            local day = Clock.daysFromCivil(date[1], date[2], date[3])
            local races = Season.dayRhythm(day)
            T.eq(#races, 45, "45 races on " .. table.concat(date, "-"))
            local ids = {}
            for _, r in ipairs(races) do
                local id = Season.raceId(r.seriesId, r.utc)
                T.falsy(ids[id], "unique race id " .. id); ids[id] = true
            end
        end
        local day = Clock.daysFromCivil(2026, 9, 29)
        local street, premier = 0, nil
        for _, r in ipairs(Season.dayRhythm(day)) do
            local h = Clock.eastern(r.utc).hour
            if r.tier == "street" then
                street = street + 1
                T.ok(h >= 20 or h < 4, "street races at night, got " .. h)
            elseif r.tier == "premier" then premier = h
            else T.ok(h >= 10 and h < 20, "sanctioned by day, got " .. h) end
        end
        T.eq(street, 24); T.eq(premier, 15)
    end,

    window_covers_days_without_duplicates = function(T)
        local Season = T.Core.get("paddock.season")
        local Clock = T.Core.get("world.clock")
        local from = Clock.utcAt(Clock.daysFromCivil(2026, 9, 29), 0)
        local list = Season.window(from, from + 3 * 86400)
        T.eq(#list, 135, "three Eastern days, 45 each")
        local seen = {}
        for _, r in ipairs(list) do
            local id = Season.raceId(r.seriesId, r.utc)
            T.falsy(seen[id]); seen[id] = true
        end
    end,

    cups_and_standings = function(T)
        local Season = T.Core.get("paddock.season")
        local Seasons = T.Core.get("competition.seasons")
        local s = Seasons.parse("2026-S4")
        T.eq(Season.cupOf(s.startUtc).cupId, "2026-S4-C01")
        T.eq(Season.cupOf(s.startUtc + 7 * 86400).cup, 2)
        T.eq(Season.cupOf(s.endUtc - 1).cup, 13, "the tail of a quarter folds into Cup 13")
        local rows = {
            { entityId = "a", position = 1, state = "finished" }, { entityId = "b", position = 2, state = "finished" },
            { entityId = "b", position = 1, state = "finished" }, { entityId = "a", position = 2, state = "finished" },
            { entityId = "c", position = 3, state = "dnf" },
        }
        local st = Season.standings(rows)
        T.eq(st[1].points, 43); T.eq(st[1].wins, 1)
        T.eq(st[3].id, "c"); T.eq(st[3].points, 0); T.eq(st[3].dnfs, 1)
        T.eq(Season.paddockYear("2026-S4", "2027-S2"), 2079)
        local plan = Season.rollover({ street = { { id = "s1" }, { id = "s2" }, { id = "s3" } },
            regional = { { id = "r1" }, { id = "r2" }, { id = "r3" } }, pro = { { id = "p1" }, { id = "p2" } },
            premier = { { id = "x1" }, { id = "x2" } } })
        local moved = {}
        for _, m in ipairs(plan) do moved[m.orgId] = m.kind end
        T.eq(moved.s1, "promoted"); T.eq(moved.r3, "relegated"); T.eq(moved.p1, "promoted"); T.eq(moved.x2, "relegated")
    end,
}
