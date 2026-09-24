local function utc(T, year, month, day)
    return T.Core.get("competition.seasons").forDate(year, month, day).startUtc
end

return {
    ["stable identity and exact quarter bounds"] = function(T)
        local S = T.Core.get("competition.seasons")
        local cases = {
            {2027,1,15,"2027-S1",1,1,4,1}, {2027,4,15,"2027-S2",2,4,7,1},
            {2027,7,15,"2027-S3",3,7,10,1}, {2027,10,15,"2027-S4",4,10,1,1},
        }
        for _, c in ipairs(cases) do
            local s = S.forDate(c[1], c[2], c[3])
            T.eq(s.id, c[4]); T.eq(s.number, c[5]); T.eq(s.timezone, "UTC")
            T.eq(S.atUtc(s.startUtc).id, s.id)
            T.ok(S.contains(s, s.startUtc)); T.ok(S.contains(s, s.endUtc - 1)); T.eq(S.contains(s, s.endUtc), false)
        end
    end,

    ["december to january changes year and season"] = function(T)
        local S = T.Core.get("competition.seasons")
        local edge = S.forDate(2027, 12, 31).endUtc
        T.eq(S.atUtc(edge - 1).id, "2027-S4"); T.eq(S.atUtc(edge).id, "2028-S1")
        T.eq(S.next(S.forDate(2027, 12, 31)).id, "2028-S1")
    end,

    ["march to april boundary"] = function(T)
        local S = T.Core.get("competition.seasons"); local edge = S.forDate(2027,3,31).endUtc
        T.eq(S.atUtc(edge-1).id, "2027-S1"); T.eq(S.atUtc(edge).id, "2027-S2")
    end,

    ["june to july boundary"] = function(T)
        local S = T.Core.get("competition.seasons"); local edge = S.forDate(2027,6,30).endUtc
        T.eq(S.atUtc(edge-1).id, "2027-S2"); T.eq(S.atUtc(edge).id, "2027-S3")
    end,

    ["september to october boundary"] = function(T)
        local S = T.Core.get("competition.seasons"); local edge = S.forDate(2027,9,30).endUtc
        T.eq(S.atUtc(edge-1).id, "2027-S3"); T.eq(S.atUtc(edge).id, "2027-S4")
    end,

    ["leap day remains in first quarter without duration balancing"] = function(T)
        local S = T.Core.get("competition.seasons")
        T.eq(S.forDate(2028,2,29).id, "2028-S1")
        T.eq(S.atUtc(utc(T,2028,1,1) + 59*86400).id, "2028-S1")
        T.errors(function() S.forDate(2027,2,29) end, "invalid_date")
    end,

    ["UTC midnight is authoritative independent of local timezone"] = function(T)
        local S = T.Core.get("competition.seasons")
        local edge = S.forDate(2027,1,1).endUtc
        T.eq(S.atUtc(edge-1).id, "2027-S1")
        T.eq(S.atUtc(edge).id, "2027-S2")
        T.eq(S.boundary, "00:00:00")
    end,

    ["ids parse strictly"] = function(T)
        local S = T.Core.get("competition.seasons")
        T.eq(S.parse("2027-S2").startUtc, S.forDate(2027,4,1).startUtc)
        local value, why = S.parse("S2-2027"); T.eq(value,nil); T.eq(why,"invalid_season_id")
        value, why = S.parse("0000-S1"); T.eq(value,nil); T.eq(why,"invalid_season_id")
    end,
}
