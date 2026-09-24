return {
    mint_requires_rng_and_origin = function(T)
        local D = T.Core.get("competition.driver")
        T.errors(function() D.mint({}) end, "ctx.rng function required")
        T.errors(function() D.mint({ rng = function() return 0.5 end, origin = "lan" }) end, "invalid value")
    end,

    mint_is_uuid_and_deterministic_under_seed = function(T)
        local D = T.Core.get("competition.driver")
        local ids = T.Core.get("vocabulary.ids")
        local a = D.mint({ rng = ids.seededRng(99), origin = "online" })
        local b = D.mint({ rng = ids.seededRng(99), origin = "online" })
        T.ok(ids.isUuid(a.ncmDriverId)); T.eq(a.ncmDriverId, b.ncmDriverId); T.eq(a.origin, "online")
    end,

    profile_shape = function(T)
        local D = T.Core.get("competition.driver")
        local ids = T.Core.get("vocabulary.ids")
        local id = ids.uuid4(ids.seededRng(3))
        local p = D.newProfile(id, "ncm-dev", "baremetaleven")
        T.eq(p.serverId, "ncm-dev"); T.eq(p.display, "baremetaleven"); T.eq(p.number, nil)
        T.eq(p.dimensions.reputation, 0); T.eq(p.sr.sr, 5.0)
        T.errors(function() D.newProfile("nope", "ncm-dev", "x") end, "uuid")
        T.errors(function() D.newProfile(id, "NCM Dev", "x") end, "slug")
        T.errors(function() D.newProfile(id, "ncm-dev", "") end, "display")
        local v = D.publicView(p)
        T.eq(v.driverId, id); T.eq(v.display, "baremetaleven"); T.eq(v.reputation, 0); T.eq(v.sr, 5.0)
    end,
}
