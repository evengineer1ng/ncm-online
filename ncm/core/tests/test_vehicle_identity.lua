-- Production provenance, the odometer's discontinuity filter, and the lifecycle door that is currently
-- locked. Addendum section 31's lettered cases are named in the comments.
--
-- The sequence allocator itself is host code (it needs a database), so the ordinal cases here drive a small
-- in-memory allocator built to the SAME rules. What that proves is the rules; what proves the host is the
-- live backfill and the three unique indexes.

--- Three independent append-only sequences, exactly as `NcmProvenance` maintains them.
local function allocator()
    local A = { global = 0, maker = {}, model = {}, issued = {} }
    --- Reserve a contiguous range for `n` machines of one model, as one batch does.
    function A.allocate(makerKey, vehicleKey, n)
        n = n or 1
        local out = {}
        for _ = 1, n do
            A.global = A.global + 1
            A.maker[makerKey] = (A.maker[makerKey] or 0) + 1
            A.model[vehicleKey] = (A.model[vehicleKey] or 0) + 1
            local triple = { global = A.global, maker = A.maker[makerKey], model = A.model[vehicleKey] }
            -- Uniqueness is what the database enforces; assert it here too so a rule change cannot pass.
            local gk = "g:" .. triple.global
            local mk = "m:" .. makerKey .. ":" .. triple.maker
            local dk = "d:" .. vehicleKey .. ":" .. triple.model
            assert(not A.issued[gk] and not A.issued[mk] and not A.issued[dk], "ordinal reused")
            A.issued[gk], A.issued[mk], A.issued[dk] = true, true, true
            out[#out + 1] = triple
        end
        return out
    end
    return A
end

return {
    -- A / B / C / D: the four ordinal cases from the addendum, in its own Ferrari example.
    the_three_sequences_are_independent = function(T)
        local A = allocator()
        -- Some history exists first, so Ferrari is not starting from a conveniently empty world.
        for _ = 1, 9 do A.allocate("ferrari", "ferrari_testarossa", 1) end
        -- A/B: the first Enzo is Ferrari #10 and Enzo #1.
        local enzo1 = A.allocate("ferrari", "ferrari_enzo", 1)[1]
        T.eq(enzo1.maker, 10, "manufacturer sequence continues across models")
        T.eq(enzo1.model, 1, "but the model's own sequence starts at 1")
        T.eq(enzo1.global, 10)
        -- C: a second model continues the manufacturer while starting its own.
        local f40 = A.allocate("ferrari", "ferrari_f40", 1)[1]
        T.eq(f40.maker, 11, "Ferrari #11")
        T.eq(f40.model, 1, "F40 #1")
        -- D: the global sequence runs across manufacturers; a maker's first car is not global #1.
        local maki = A.allocate("makigai", "makigai_maimai", 1)[1]
        T.eq(maki.maker, 1, "Makigai #1")
        T.eq(maki.global, 12, "and global keeps counting everything")
        T.neq(maki.global, 1, "the first car of a marque need not be the first car of NCM")
    end,

    -- E / F: a batch takes contiguous, unique numbers from each sequence, and interleaving cannot duplicate.
    a_batch_takes_unique_contiguous_numbers = function(T)
        local A = allocator()
        local five = A.allocate("archer", "archer_hella", 5)
        T.eq(#five, 5)
        for i = 2, 5 do
            T.eq(five[i].global, five[i - 1].global + 1, "global range is contiguous")
            T.eq(five[i].maker, five[i - 1].maker + 1)
            T.eq(five[i].model, five[i - 1].model + 1)
        end
        -- Another manufacturer allocating next cannot land inside that range; the assert in the allocator
        -- fires if any number is ever reissued.
        local other = A.allocate("makigai", "makigai_maimai", 3)
        T.eq(other[1].global, five[5].global + 1, "the global sequence continues past the batch")
        T.eq(other[1].maker, 1, "while that manufacturer starts its own history")
        T.eq(other[1].model, 1)
    end,

    -- Section 3: ordinals are history, never an array index.
    ordinals_are_never_reused_after_a_retirement = function(T)
        local A = allocator()
        local made = A.allocate("ferrari", "ferrari_enzo", 20)
        T.eq(made[13].maker, 13)
        -- Ferrari #13 is retired. The number stays consumed: the next car is #21, not #13.
        local next1 = A.allocate("ferrari", "ferrari_enzo", 1)[1]
        T.eq(next1.maker, 21, "a retired car does not release its place in history")
        T.eq(next1.model, 21)
    end,

    -- Section 8: only manufacture consumes production numbers.
    only_production_consumes_ordinals = function(T)
        local V = T.Core.get("data.vehicle_identity")
        T.eq(V.consumesOrdinals(V.ORIGIN.PRODUCTION), true)
        T.eq(V.consumesOrdinals(V.ORIGIN.GRANT), false, "an admin or progression car burns no serial")
        T.eq(V.consumesOrdinals(nil), false)
        T.eq(V.consumesOrdinals("anything_else"), false, "unknown origins are not production")
    end,

    -- Section 6: the manufacturer identity behind a sequence must be stable, not a display label.
    every_manufacturer_has_a_stable_key = function(T)
        local Cat = T.Core.get("data.vehicle_catalogue")
        local seen = {}
        for _, e in ipairs(Cat.entries()) do
            T.ok(type(e.manufacturerKey) == "string" and e.manufacturerKey ~= "",
                 (e.displayName or "?") .. " has no stable manufacturer key")
            -- One display name must not map to two keys, or its history would fork.
            if seen[e.manufacturer] then T.eq(seen[e.manufacturer], e.manufacturerKey, "one badge, one key") end
            seen[e.manufacturer] = e.manufacturerKey
        end
        -- The key is not derived from the vehicleKey prefix, which is not reliable: the RB15's key starts
        -- "ncx" while its manufacturer is Red Bull Racing.
        local rb15 = Cat.byKey("ncx_rb15")
        if rb15 then T.neq(rb15.manufacturerKey, "ncx", "the maker key is authored, not parsed from the model key") end
    end,

    -- O / P: reconstruction and teleports must not invent kilometres.
    reconstruction_never_creates_distance = function(T)
        local V = T.Core.get("data.vehicle_identity")
        local a = { assetId = "A", x = 0, y = 0, z = 0, at = 100 }
        -- Ordinary driving: ~25 m/s for a second.
        local drive = V.segment(a, { assetId = "A", x = 25, y = 0, z = 0, at = 101 })
        T.eq(drive.accept, true)
        T.ok(math.abs(drive.metres - 25) < 0.001, "real travel is counted in full")
        -- P: a CALL rebuilds the car two kilometres away, one second later. Not a journey.
        local teleport = V.segment(a, { assetId = "A", x = 2000, y = 0, z = 0, at = 101 })
        T.eq(teleport.accept, false)
        T.eq(teleport.reason, "discontinuity")
        T.eq(teleport.metres, 0)
        -- A gap in observation is not a straight-line drive across it either.
        local gap = V.segment(a, { assetId = "A", x = 60, y = 0, z = 0, at = 100 + 600 })
        T.eq(gap.accept, false); T.eq(gap.reason, "gap")
        -- Q / O: two different machines are never joined, so a driver swapping cars adds nothing to either.
        local swap = V.segment(a, { assetId = "B", x = 5, y = 0, z = 0, at = 101 })
        T.eq(swap.accept, false); T.eq(swap.reason, "asset_changed")
        -- An unidentified vehicle (no assetId) contributes nothing at all.
        T.eq(V.segment({ x = 0, y = 0, at = 100 }, { x = 5, y = 0, at = 101 }).accept, false)
        -- Standing still is not travel, and neither is jitter.
        T.eq(V.segment(a, { assetId = "A", x = 0.05, y = 0, z = 0, at = 101 }).accept, false)
        -- Climbing counts: vertical movement is real distance.
        local hill = V.segment(a, { assetId = "A", x = 0, y = 0, z = 10, at = 101 })
        T.eq(hill.accept, true); T.ok(math.abs(hill.metres - 10) < 0.001)
        -- Time never runs backwards into mileage.
        T.eq(V.segment(a, { assetId = "A", x = 25, y = 0, z = 0, at = 99 }).accept, false)
    end,

    -- The squirming case. Owner, 2026-09-23: the odometer ticked up while a parked MaiMai moved slightly.
    -- Speed is an independent witness -- a parked car's coordinates drift while its speedometer reads zero --
    -- so it separates jitter from creeping without a crude minimum-speed rule on real driving.
    stationary_jitter_does_not_accumulate_when_speed_says_parked = function(T)
        local V = T.Core.get("data.vehicle_identity")
        local base = { assetId = "A", x = 0, y = 0, z = 0, at = 100, speedMps = 0 }
        -- Coordinates move half a metre a second; the car reports standing still. That is squirming.
        local jitter = V.segment(base, { assetId = "A", x = 0.5, y = 0.2, z = 0, at = 101, speedMps = 0.05 })
        T.eq(jitter.accept, false)
        T.eq(jitter.reason, "stationary_by_speed")
        -- Unfiltered, that is 0.54 m per second: about 1.9 km for every hour parked.
        T.ok(math.sqrt(0.5 ^ 2 + 0.2 ^ 2) * 3600 / 1000 > 1.5, "which is why it mattered")
        -- **Legitimate slow movement still counts.** A car creeping at 4 km/h is far above the parked
        -- threshold and must not be filtered away.
        local creep = V.segment({ assetId = "A", x = 0, y = 0, z = 0, at = 100, speedMps = 1.1 },
                                { assetId = "A", x = 1.1, y = 0, z = 0, at = 101, speedMps = 1.1 })
        T.eq(creep.accept, true)
        T.ok(math.abs(creep.metres - 1.1) < 0.001, "and counts in full, not clipped")
    end,

    -- A glitch inside a real journey loses its excess, not the whole second of travel.
    a_positional_glitch_is_capped_by_the_reported_speed = function(T)
        local V = T.Core.get("data.vehicle_identity")
        local prev = { assetId = "A", x = 0, y = 0, z = 0, at = 100, speedMps = 10 }
        -- Speed says ~10 m/s; position claims 60 m in one second.
        local capped = V.segment(prev, { assetId = "A", x = 60, y = 0, z = 0, at = 101, speedMps = 10 })
        T.eq(capped.accept, true, "the second still contained real travel")
        T.eq(capped.reason, "capped_to_speed")
        T.ok(capped.metres < 60, "but not sixty metres of it")
        T.ok(capped.metres >= 10, "and not less than the speed actually justified")
        -- Ordinary driving is never capped: the tolerance is generous enough for acceleration between samples.
        local normal = V.segment(prev, { assetId = "A", x = 12, y = 0, z = 0, at = 101, speedMps = 14 })
        T.eq(normal.reason, "travelled")
        T.ok(math.abs(normal.metres - 12) < 0.001)
    end,

    -- A build with no speed reading must still work, just with the older positional floor.
    without_a_speed_reading_the_positional_floor_still_applies = function(T)
        local V = T.Core.get("data.vehicle_identity")
        local a = { assetId = "A", x = 0, y = 0, z = 0, at = 100 }
        T.eq(V.segment(a, { assetId = "A", x = 0.05, y = 0, z = 0, at = 101 }).reason, "stationary")
        T.eq(V.segment(a, { assetId = "A", x = 25, y = 0, z = 0, at = 101 }).accept, true)
        -- and the discontinuity filter outranks everything, speed or no speed
        T.eq(V.segment(a, { assetId = "A", x = 2000, y = 0, z = 0, at = 101 }).reason, "discontinuity")
        T.eq(V.segment({ assetId = "A", x = 0, y = 0, z = 0, at = 100, speedMps = 0 },
                       { assetId = "A", x = 2000, y = 0, z = 0, at = 101, speedMps = 0 }).reason, "discontinuity")
    end,

    -- R / S: the lifecycle can describe a dead car, and nothing can kill one today.
    terminal_failure_is_representable_and_switched_off = function(T)
        local V = T.Core.get("data.vehicle_identity")
        -- R: the state exists and is distinct from active.
        T.ok(V.LIFECYCLE.RETIRED_TERMINAL_FAILURE and V.LIFECYCLE.RETIRED_TERMINAL_FAILURE ~= V.LIFECYCLE.ACTIVE)
        T.eq(V.isActive(V.LIFECYCLE.ACTIVE), true)
        T.eq(V.isActive(V.LIFECYCLE.RETIRED_TERMINAL_FAILURE), false)
        T.eq(V.isActive(nil), true, "an asset with no recorded lifecycle is active, not dead")
        -- S: the door is locked, whatever is asked of it.
        T.eq(V.TERMINAL_FAILURE_ENABLED, false, "no vehicle may die yet")
        local ok, why = V.canRetire({ from = V.LIFECYCLE.ACTIVE, cause = "mileage" })
        T.eq(ok, false)
        T.eq(why, "terminal_failure_disabled")
        T.eq((V.canRetire({ from = V.LIFECYCLE.ACTIVE })), false, "not even without a cause")
        T.eq((V.canRetire({})), false)
    end,

    -- Section 9: display width is presentation and never a limit on identity.
    ordinal_formatting_does_not_cap_identity = function(T)
        local V = T.Core.get("data.vehicle_identity")
        T.eq(V.formatOrdinal(1), "#0000001")
        T.eq(V.formatOrdinal(1, 4), "#0001")
        -- Ten million is representable and simply renders wider, rather than wrapping or truncating.
        T.eq(V.formatOrdinal(10000000), "#10000000")
        T.eq(V.formatOrdinal(0), nil, "there is no vehicle zero")
        T.eq(V.formatOrdinal(nil), nil, "and an unserialled asset formats as nothing, not as #0000000")
    end,

    the_odometer_reads_like_an_odometer = function(T)
        local V = T.Core.get("data.vehicle_identity")
        T.eq(V.formatOdometer(0), "0.0 km")
        T.eq(V.formatOdometer(1500), "1.5 km")
        T.eq(V.formatOdometer(12483700), "12,484 km", "past 10 000 km the decimal is noise")
        T.eq(V.formatOdometer(212481000), "212,481 km")
        T.eq(V.formatOdometer(-5), "0.0 km", "distance is never negative")
    end,
}
