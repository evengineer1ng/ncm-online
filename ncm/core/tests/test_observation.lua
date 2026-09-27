return {
    ["every declared characteristic carries a unit and a kind the evidence row accepts"] = function(T)
        local O = T.Core.get("competition.observation")
        local K = T.Core.get("competition.machine_knowledge")
        local n = 0
        for kind, c in pairs(O.CHARACTERISTICS) do
            n = n + 1
            -- 28 section 39: typed, semantically meaningful, provenance-bearing -- not key/value soup.
            T.eq(type(c.unit), "string", kind)
            T.eq(c.unit ~= "", true, kind)
            T.eq(type(c.label), "string", kind)
            -- The page renders `display`; it must never invent a unit for a value it did not compute.
            T.eq(type(c.display), "string", kind)
            T.eq(c.ceiling > c.floor, true, kind)
            T.eq(c.step > 0, true, kind)
            -- The two vocabularies must not drift apart: a characteristic nobody can write is useless.
            T.eq(K.KINDS[kind], true, kind)
            T.eq(K.OBSERVATION_KINDS[kind], true, kind)
        end
        T.eq(n, 6)
    end,

    ["only the characteristics with a real producer are marked wired"] = function(T)
        local O = T.Core.get("competition.observation")
        -- The odometer's 1 Hz server loop already reads speed and already derives cornering load. The other
        -- four need velocity/angularVelocity fields it does not read yet. Writing one before its producer
        -- exists is the fabrication this subsystem refuses.
        T.eq(table.concat(O.wired(), ","), "observed_lateral_accel,observed_speed_floor")
        T.eq(O.isWired("observed_speed_floor"), true)
        T.eq(O.isWired("observed_yaw_rate"), false)
        T.eq(O.isWired("nonsense"), false)
    end,

    ["a reading of a quantity is stricter than a reading of a field"] = function(T)
        local O = T.Core.get("competition.observation")
        T.eq(O.reading("observed_speed_floor", 156.0), 156.0)
        T.eq(O.reading("observed_speed_floor", "156"), 156)
        -- Zero is a real reading of a quantity even though it will not clear the floor later.
        T.eq(O.reading("observed_speed_floor", 0), 0)
        local v, why = O.reading("observed_speed_floor", -1)
        T.eq(v, nil); T.eq(why, "negative")
        v, why = O.reading("observed_speed_floor", 4000)
        T.eq(v, nil); T.eq(why, "implausible")
        v, why = O.reading("observed_speed_floor", nil)
        T.eq(v, nil); T.eq(why, "unreadable")
        v, why = O.reading("observed_speed_floor", 0 / 0)
        T.eq(v, nil); T.eq(why, "not_a_number")
        v, why = O.reading("observed_speed_floor", math.huge)
        T.eq(v, nil); T.eq(why, "not_finite")
        v, why = O.reading("estimated_top_speed", 100)
        T.eq(v, nil); T.eq(why, "unknown_characteristic:estimated_top_speed")
    end,

    ["a reading becomes a row only when it is a materially better demonstration"] = function(T)
        local O = T.Core.get("competition.observation")
        -- First sight of anything above the floor is worth recording.
        local ok, value = O.promote("observed_speed_floor", 96.0, nil)
        T.eq(ok, true); T.eq(value, 96.0)
        -- Creeping up by 0.4 km/h a second must not write a row a second.
        local no, why = O.promote("observed_speed_floor", 96.4, 96.0)
        T.eq(no, false); T.eq(why, "not_materially_better")
        -- Clearing the step does.
        ok, value = O.promote("observed_speed_floor", 101.0, 96.0)
        T.eq(ok, true); T.eq(value, 101.0)
        -- Slower than the stored best is not evidence of anything new.
        no, why = O.promote("observed_speed_floor", 40.0, 96.0)
        T.eq(no, false); T.eq(why, "not_materially_better")
        -- Real, but too ordinary to spend a row on. Crucially this is NOT an error.
        no, why = O.promote("observed_speed_floor", 12.0, nil)
        T.eq(no, false); T.eq(why, "below_floor")
        -- A parked car reading a genuine zero is refused as evidence here, without ever becoming a row --
        -- which is the other half of 31 section 7's invariant.
        no, why = O.promote("observed_speed_floor", 0, nil)
        T.eq(no, false); T.eq(why, "below_floor")
        -- An unreadable sample is refused by its own name, never defaulted.
        no, why = O.promote("observed_speed_floor", nil, 96.0)
        T.eq(no, false); T.eq(why, "unreadable")
    end,

    ["each characteristic keeps its own step and floor"] = function(T)
        local O = T.Core.get("competition.observation")
        -- 0.6 m/s2 of extra cornering load is a real difference; 0.6 km/h is not. One shared threshold
        -- would have made one of these wrong.
        T.eq(O.promote("observed_lateral_accel", 8.6, 8.0), true)
        T.eq(O.promote("observed_speed_floor", 96.6, 96.0), false)
    end,

    ["the evidence body carries its unit, so a bare number can never be reinterpreted"] = function(T)
        local O = T.Core.get("competition.observation")
        local body = O.body("observed_speed_floor", 156.0)
        T.eq(body.kind, "observed_speed_floor")
        T.eq(body.value, 156.0)
        T.eq(body.unit, "kph")
        T.eq(O.body("observed_lateral_accel", 9.1).unit, "mps2")
        local none, why = O.body("observed_speed_floor", -3)
        T.eq(none, nil); T.eq(why, "negative")
    end,

    ["the inventory reports the vocabulary and which half of it is live"] = function(T)
        local O = T.Core.get("competition.observation")
        local inv, wired = O.inventory(), 0
        T.eq(#inv, 6)
        T.eq(inv[1].kind, "observed_gradient")            -- sorted, so the gate output is stable
        for _, row in ipairs(inv) do if row.wired then wired = wired + 1 end end
        T.eq(wired, 2)
    end,
}
