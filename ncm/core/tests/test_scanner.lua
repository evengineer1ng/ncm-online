return {
    ["the fast XOR and the table XOR agree, and a sliced index equals the whole one"] = function(T)
        local S = T.Core.get("competition.scanner")
        T.eq(S._bxorTable(0xEDB88320, 0xFFFFFFFF), 0x12477CDF)
        T.eq(S._bxorTable(0, 0), 0); T.eq(S._bxorTable(0xFFFFFFFF, 0xFFFFFFFF), 0)
        local records = {}
        for i = 1, 23 do records[i] = "Vehicle.v_test_record_" .. i end
        local whole, sliced, from = S.recordIndex(records), {}, 1
        while from do from = S.recordIndexStep(records, sliced, from, 5) end
        local n = 0
        for k, v in pairs(whole) do T.eq(sliced[k], v, k); n = n + 1 end
        T.eq(n, 23)
    end,

    ["record keys match the TweakDBID identity layout the DLL reports"] = function(T)
        local S = T.Core.get("competition.scanner")
        T.eq(S.crc32("123456789"), 0xCBF43926, "CRC32-B check value")
        T.eq(S.recordKey("123456789"), string.format("%.0f", 0xCBF43926 + 9 * 4294967296))
        local idx = S.recordIndex({ "Vehicle.v_sport2_quadra_type66", "Vehicle.v_standard2_makigai_maimai" })
        T.eq(idx[S.recordKey("Vehicle.v_sport2_quadra_type66")], "Vehicle.v_sport2_quadra_type66")
        T.eq(S.recordKey(""), nil)
    end,

    ["a lock needs the full hold on one machine, and completes exactly once"] = function(T)
        local S = T.Core.get("competition.scanner")
        local obs = { active = true, entity = "42", kind = "networked", distance = 20 }
        local l = S.step(nil, obs, 1000)
        T.eq(l.progress, 0); T.eq(l.complete, false); T.eq(l.reason, "scanning")
        l = S.step(l, obs, 1000 + S.LOCK_MS - 1)
        T.eq(l.complete, false)
        l = S.step(l, obs, 1000 + S.LOCK_MS)
        T.eq(l.complete, true); T.eq(l.progress, 1); T.eq(l.reason, "scanned")
        l = S.step(l, obs, 1000 + S.LOCK_MS + 500)
        T.eq(l.complete, false, "a held lock must not complete twice")
        T.eq(l.reason, "scanned")
    end,

    ["switching target restarts the lock"] = function(T)
        local S = T.Core.get("competition.scanner")
        local l = S.step(nil, { active = true, entity = "1", kind = "vanilla", distance = 10 }, 0)
        l = S.step(l, { active = true, entity = "1", kind = "vanilla", distance = 10 }, 1000)
        l = S.step(l, { active = true, entity = "2", kind = "vanilla", distance = 10 }, 1200)
        T.eq(l.entity, "2"); T.eq(l.progress, 0); T.eq(l.startedAt, 1200)
    end,

    ["out of range, no target and not-a-machine are said out loud, not scanned"] = function(T)
        local S = T.Core.get("competition.scanner")
        T.eq(S.step(nil, { active = true, entity = "1", kind = "networked", distance = S.RANGE_M + 1 }, 0).reason, "out_of_range")
        T.eq(S.step(nil, { active = true, entity = "1", kind = "networked" }, 0).reason, "out_of_range")
        T.eq(S.step(nil, { active = true }, 0).reason, "no_target")
        T.eq(S.step(nil, { active = true, entity = "1", kind = "npc", distance = 5 }, 0).reason, "not_a_machine")
        T.eq(S.step(nil, nil, 0).reason, "idle")
        T.eq(S.step(nil, { active = false, entity = "1", kind = "networked", distance = 5 }, 0).reason, "idle")
    end,

    ["breaking range resets progress"] = function(T)
        local S = T.Core.get("competition.scanner")
        local near = { active = true, entity = "7", kind = "networked", distance = 30 }
        local l = S.step(nil, near, 0)
        l = S.step(l, near, 1000)
        l = S.step(l, { active = true, entity = "7", kind = "networked", distance = 90 }, 1100)
        T.eq(l.progress, 0)
        l = S.step(l, near, 1200)
        T.eq(l.startedAt, 1200, "coming back into range starts over")
    end,

    ["a networked scan is server-measured and checked against the server's own geometry"] = function(T)
        local S = T.Core.get("competition.scanner")
        T.eq(S.admit({ kind = "networked", recordKnown = true, sameBucket = true, serverDistance = 40 }), "server_measured")
        T.eq(select(2, S.admit({ kind = "networked", recordKnown = true, sameBucket = false, serverDistance = 5 })), "other_bucket")
        T.eq(select(2, S.admit({ kind = "networked", recordKnown = true, sameBucket = true, serverDistance = 200 })), "out_of_range")
        T.eq(select(2, S.admit({ kind = "networked", recordKnown = true, sameBucket = true })), "no_server_position")
        T.eq(select(2, S.admit({ kind = "networked", recordKnown = false, sameBucket = true, serverDistance = 5 })), "no_ncm_record")
    end,

    ["a vanilla scan is client-attested and rate-limited"] = function(T)
        local S = T.Core.get("competition.scanner")
        local now = 10 * 3600000
        T.eq(S.admit({ kind = "vanilla", recordKnown = true, claimedDistance = 20, now = now }), "client_attested")
        T.eq(select(2, S.admit({ kind = "vanilla", recordKnown = true, claimedDistance = 20, now = now,
            recentAttested = { now - 5000 } })), "attested_too_soon")
        local many = {}
        for i = 1, S.ATTESTED_PER_HOUR do many[i] = now - 60000 * i end
        T.eq(select(2, S.admit({ kind = "vanilla", recordKnown = true, claimedDistance = 20, now = now,
            recentAttested = many })), "attested_hourly_limit")
        T.eq(select(2, S.admit({ kind = "vanilla", recordKnown = true, claimedDistance = 200, now = now })), "out_of_range")
        T.eq(select(2, S.admit({ kind = "martian", recordKnown = true })), "unknown_kind:martian")
    end,

    ["the scanner is a legitimate knowledge source that may credit a human"] = function(T)
        local K = T.Core.get("competition.machine_knowledge")
        local row, why = K.evidence({ driverId = "d", vehicleKey = "makigai_maimai", evidenceKey = "identity:makigai_maimai",
            kind = "identity_reveal", source = "scanner", epistemic = "observed", basis = "client_attested", observedAt = 1 })
        T.eq(row ~= nil, true, why)
        T.eq(K.allowsHumanDiscoveryCredit("scanner"), true)
    end,
}
