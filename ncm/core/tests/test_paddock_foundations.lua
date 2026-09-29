-- vocabulary.hash, world.clock, world.conditions (doc 44 §5, §6, §7).
return {
    hash_matches_published_fnv1a_vectors = function(T)
        local H = T.Core.get("vocabulary.hash")
        T.eq(H.fnv1a32(""), 0x811c9dc5)
        T.eq(H.fnv1a32("a"), 0xe40c292c)
        T.eq(H.fnv1a32("foobar"), 0xbf9cf968)
    end,

    hash_table_xor_path_agrees_with_the_native_path = function(T)
        local H = T.Core.get("vocabulary.hash")
        for _, h in ipairs({ 0, 1, 255, 256, 0x811c9dc5, 4294967295, 123456789 }) do
            for _, b in ipairs({ 0, 1, 97, 128, 255 }) do
                local expected = h - (h % 256) + (function(x, y)
                    local r, bit = 0, 1
                    for _ = 1, 8 do
                        if (x % 2) ~= (y % 2) then r = r + bit end
                        x, y, bit = math.floor(x / 2), math.floor(y / 2), bit * 2
                    end
                    return r
                end)(h % 256, b)
                T.eq(H._xorByteTable(h, b), expected, "xor " .. h .. "^" .. b)
            end
        end
    end,

    streams_replay_and_differ_by_key = function(T)
        local H = T.Core.get("vocabulary.hash")
        local a, b, c = H.stream("s", 1), H.stream("s", 1), H.stream("s", 2)
        local sa, sb, sc = {}, {}, {}
        for i = 1, 20 do sa[i] = a(); sb[i] = b(); sc[i] = c() end
        T.eq(table.concat(sa, ","), table.concat(sb, ","), "same key, same stream")
        T.neq(table.concat(sa, ","), table.concat(sc, ","), "different key, different stream")
        for i = 1, 200 do local x = a(); T.ok(x >= 0 and x < 1, "unit range") end
        local r = H.stream("ints")
        for _ = 1, 200 do local v = r:int(1, 6); T.ok(v >= 1 and v <= 6 and v == math.floor(v)) end
        T.neq(H.key("a", 1), H.key("a1"), "keys are delimited")
    end,

    clock_eastern_follows_dst = function(T)
        local Clock = T.Core.get("world.clock")
        -- 2026-01-15 17:00 UTC = 12:00 EST (winter, -5)
        local winter = Clock.daysFromCivil(2026, 1, 15) * 86400 + 17 * 3600
        local e = Clock.eastern(winter)
        T.eq(e.hour, 12); T.eq(e.dst, false); T.eq(e.d, 15)
        -- 2026-07-04 16:00 UTC = 12:00 EDT (summer, -4)
        local summer = Clock.daysFromCivil(2026, 7, 4) * 86400 + 16 * 3600
        T.eq(Clock.eastern(summer).hour, 12); T.eq(Clock.eastern(summer).dst, true)
        -- 2026 DST: starts Sunday March 8, ends Sunday November 1
        local s, en = Clock.dstBounds(2026)
        T.eq(s, Clock.daysFromCivil(2026, 3, 8) * 86400 + 7 * 3600)
        T.eq(en, Clock.daysFromCivil(2026, 11, 1) * 86400 + 6 * 3600)
        T.eq(Clock.eastern(s - 1).hour, 1, "01:59:59 EST just before the jump")
        T.eq(Clock.eastern(s).hour, 3, "03:00 EDT at the jump")
        T.eq(Clock.eastern(en - 1).hour, 1, "01:59:59 EDT before falling back")
        T.eq(Clock.eastern(en).hour, 1, "01:00 EST again after")
    end,

    clock_utcAt_round_trips = function(T)
        local Clock = T.Core.get("world.clock")
        local day = Clock.daysFromCivil(2026, 9, 29)
        local utc = Clock.utcAt(day, 20 * 3600)
        local e = Clock.eastern(utc)
        T.eq(e.hour, 20); T.eq(e.dayIndex, day)
        T.eq(Clock.eastern(Clock.utcAt(day, 26 * 3600)).hour, 2, "a night past midnight lands on the next day at 02:00")
        local civ = { Clock.civilFromDays(Clock.daysFromCivil(2028, 2, 29)) }
        T.eq(civ[1], 2028); T.eq(civ[2], 2); T.eq(civ[3], 29)
    end,

    conditions_road_wetness_matches_machine_lua = function(T)
        local W = T.Core.get("world.conditions")
        T.eq(W.ROAD_SOAK_S, 120); T.eq(W.ROAD_DRY_S, 360); T.eq(W.ROAD_STEP, 0.05)
        local rows = { { startsAtUtc = 0, weather = "sunny" }, { startsAtUtc = 1000, weather = "rain" },
            { startsAtUtc = 2000, weather = "sunny" } }
        T.eq(W.roadWetnessAt(rows, 999), 0, "dry before the rain")
        T.eq(W.roadWetnessAt(rows, 1060), 0.5, "a minute of rain soaks halfway")
        T.eq(W.roadWetnessAt(rows, 1500), 1, "fully wet")
        T.eq(W.roadWetnessAt(rows, 2180), 0.5, "three minutes of drying halves it")
        T.eq(W.roadWetnessAt(rows, 3000), 0, "dry again")
        local c = W.at(rows, 1500, 22 * 3600)
        T.eq(c.weather, "rain"); T.eq(c.family, "wet"); T.eq(c.light, "night"); T.eq(c.bucket, "wet:night")
        T.eq(W.lightOf(12 * 3600), "day"); T.eq(W.lightOf(19 * 3600), "dusk"); T.eq(W.lightOf(2 * 3600), "night")
    end,
}
