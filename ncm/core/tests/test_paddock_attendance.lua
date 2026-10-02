-- paddock.attendance and paddock.world race fields (L249): league pools, who turns up, and why not.
local SEASON = "2026-S4"

local worldCache
local function world(T)
    if not worldCache then worldCache = T.Core.get("paddock.world").genesis(777, SEASON) end
    return worldCache
end

local function race(id, sid, tier, at) return { raceId = id, seriesId = sid, tier = tier, opensAt = at or 1000 } end

return {
    a_street_field_is_drawn_from_its_pool_and_varies_race_to_race = function(T)
        local W = T.Core.get("paddock.world")
        local w = world(T)
        local seen, sizes = {}, {}
        for r = 1, 30 do
            local field, absent = W.raceField(w, race("r" .. r, "street_b", "street"))
            sizes[#sizes + 1] = #field
            local inField = {}
            for _, e in ipairs(field) do
                inField[e.driver.id] = true
                seen[e.driver.id] = true
                T.eq(e.driver.leagueId, "street_b", "only league members race")
                T.falsy(absent[e.driver.id], "an entrant is not also absent")
            end
            local n = 0
            for id in pairs(absent) do n = n + 1; T.falsy(inField[id]) end
            T.eq(n + #field, 56, "every pool member is either in the field or has a reason")
            T.ok(#field <= 12, "never more than the series field")
        end
        local distinct = 0
        for _ in pairs(seen) do distinct = distinct + 1 end
        T.ok(distinct >= 40, "most of the pool races at some point (" .. distinct .. ")")
        local full = 0
        for _, s in ipairs(sizes) do if s == 12 then full = full + 1 end end
        T.ok(full >= 25, "a 56-driver pool fills a 12-car field nearly every time (" .. full .. "/30)")
    end,

    the_same_race_always_draws_the_same_field = function(T)
        local W = T.Core.get("paddock.world")
        local w = world(T)
        local a = W.raceField(w, race("same", "street_c", "street"))
        local b = W.raceField(w, race("same", "street_c", "street"))
        T.eq(#a, #b)
        for i = 1, #a do T.eq(a[i].driver.id, b[i].driver.id) end
    end,

    nobody_makes_every_race = function(T)
        local W = T.Core.get("paddock.world")
        local w = world(T)
        local starts = {}
        for r = 1, 20 do
            for _, e in ipairs(W.raceField(w, race("night" .. r, "street_e", "street"))) do
                starts[e.driver.id] = (starts[e.driver.id] or 0) + 1
            end
        end
        for id, n in pairs(starts) do T.ok(n < 20, id .. " made every one of 20 races") end
    end,

    a_driver_who_just_raced_is_less_likely_to_turn_up = function(T)
        local A = T.Core.get("paddock.attendance")
        local p = { id = "p1", role = "driver", state = "active", morale = 50, evidence = {} }
        local fresh = A.chance(1, p, "street", 10000)
        p.evidence.lastStartAt = 10000 - 600
        local tired, why = A.chance(1, p, "street", 10000)
        T.ok(tired < fresh * 0.5, "raced 10 minutes ago")
        T.eq(why, "raced_recently")
        p.state = "injured"
        T.eq((A.chance(1, p, "street", 10000)), 0)
    end,

    sanctioned_teams_field_their_available_best = function(T)
        local W = T.Core.get("paddock.world")
        local w = world(T)
        local field, absent = W.raceField(w, race("pro1", "pro_a", "pro"))
        local perOrg = {}
        for _, e in ipairs(field) do
            T.ok(e.org ~= nil, "a sanctioned entrant drives for a team")
            perOrg[e.org.id] = (perOrg[e.org.id] or 0) + 1
        end
        for _, n in pairs(perOrg) do T.ok(n <= 1, "one race seat per pro team") end
        local reasons = T.Core.get("paddock.attendance").tally(absent)
        T.ok((reasons.reserve or 0) > 0, "available drivers beyond the race seats sit as reserves")
    end,

    reliability_is_a_spread_trait = function(T)
        local A = T.Core.get("paddock.attendance")
        local lo, hi = 1, 0
        for i = 1, 300 do
            local r = A.reliability(42, ("p%05d"):format(i))
            if r < lo then lo = r end
            if r > hi then hi = r end
            T.ok(r >= 0.35 and r <= 0.97)
        end
        T.ok(hi - lo > 0.35, "drivers differ in reliability (" .. lo .. ".." .. hi .. ")")
    end,
}
