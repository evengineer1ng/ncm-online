return {
    uuid_shape = function(T)
        local ids = T.Core.get("vocabulary.ids")
        local rng = ids.seededRng(42)
        local u = ids.uuid4(rng)
        T.eq(#u, 36, "length")
        T.ok(ids.isUuid(u), "isUuid accepts its own output: " .. u)
        T.match(u, "^%x+%-%x+%-4%x%x%x%-[89ab]", "version 4, variant 10xx")
    end,

    uuid_deterministic_under_seed = function(T)
        local ids = T.Core.get("vocabulary.ids")
        local a = ids.uuid4(ids.seededRng(7))
        local b = ids.uuid4(ids.seededRng(7))
        local c = ids.uuid4(ids.seededRng(8))
        T.eq(a, b, "same seed, same uuid")
        T.neq(a, c, "different seed, different uuid")
        -- Frozen fixture: any change here is a deliberate rng/format change.
        T.eq(a, "3de99ced-0cdb-4c0d-91fb-f988738c9ac7", "seed 7 fixture")
    end,

    uuid_rejects_bad_rng = function(T)
        local ids = T.Core.get("vocabulary.ids")
        T.errors(function() ids.uuid4(nil) end, "rng function required")
        T.errors(function() ids.uuid4(function() return 1.5 end) end, "in %[0,1%)")
    end,

    isUuid_strict = function(T)
        local ids = T.Core.get("vocabulary.ids")
        T.ok(not ids.isUuid("7AA4C8F7-E31C-4AC7-A2FB-FB9F65A4F3EC"), "uppercase rejected")
        T.ok(not ids.isUuid("7aa4c8f7-e31c-1ac7-a2fb-fb9f65a4f3ec"), "version 1 rejected")
        T.ok(not ids.isUuid("7aa4c8f7-e31c-4ac7-c2fb-fb9f65a4f3ec"), "bad variant rejected")
        T.ok(not ids.isUuid(nil) and not ids.isUuid(12), "non-strings rejected")
    end,

    slug_rules = function(T)
        local ids = T.Core.get("vocabulary.ids")
        T.ok(ids.isSlug("tip_to_trench"), "underscore ok")
        T.ok(ids.isSlug("ncx-2077"), "dash ok")
        T.ok(not ids.isSlug("Tip"), "uppercase rejected")
        T.ok(not ids.isSlug("-lead"), "must start alphanumeric")
        T.ok(not ids.isSlug(""), "empty rejected")
    end,

    revisioned_round_trip = function(T)
        local ids = T.Core.get("vocabulary.ids")
        local r = ids.revisioned("tip_to_trench", 3)
        T.eq(r, "tip_to_trench@3")
        local id, rev = ids.parseRevisioned(r)
        T.eq(id, "tip_to_trench"); T.eq(rev, 3)
        T.eq(ids.revisioned("x", 2.0), "x@2", "integral float accepted")
        T.errors(function() ids.revisioned("x", 1.5) end, "non%-negative integer")
        T.errors(function() ids.revisioned("Bad", 1) end, "must be a slug")
        local nid, reason = ids.parseRevisioned("tip@")
        T.eq(nid, nil); T.eq(reason, "malformed")
    end,

    settlement_key = function(T)
        local ids = T.Core.get("vocabulary.ids")
        local sid = ids.uuid4(ids.seededRng(1))
        local key = ids.settlementKey("ncm-ref", sid, 1)
        T.eq(key, "ncm-ref:" .. sid .. ":v1")
        T.errors(function() ids.settlementKey("ncm-ref", "nope", 1) end, "sessionId must be a uuid")
        T.errors(function() ids.settlementKey("ncm-ref", sid, 0) end, "positive integer")
    end,
}
