-- space.places (L329): host locations resolved generically, never invented.
local function P(T) return T.Core.get("space.places") end

return {
    kunos_placeholders_are_not_coordinates = function(T)
        local la, why = P(T).parseGeotags({ "lat", "lon" })
        T.eq(la, nil, "the stock ['lat','lon'] is not a place")
        T.ok(why and why:find("placeholder"), "and says so")
        T.eq((P(T).parseGeotags({ "0", "0" })), nil, "(0, 0) is unknown, not the Gulf of Guinea")
    end,

    mod_geotags_resolve_in_any_common_form = function(T)
        local la, lo = P(T).parseGeotags({ "43.9975 N", "11.3719 E" })
        T.ok(math.abs(la - 43.9975) < 1e-9 and math.abs(lo - 11.3719) < 1e-9, "N / E suffixes")
        la, lo = P(T).parseGeotags({ "36.5843", "121.7535 W" })
        T.ok(math.abs(lo + 121.7535) < 1e-9, "W is negative")
        la, lo = P(T).parseGeotags({ -33.86, 151.21 })
        T.ok(la == -33.86 and lo == 151.21, "numbers")
    end,

    a_curated_venue_is_verified_and_a_disagreeing_host_is_flagged = function(T)
        local r = P(T).resolve({ track = "ks_laguna_seca", csp = { lat = 36.584, lon = -121.753 } })
        T.eq(r.status, "verified", "Laguna Seca is authored")
        T.eq(r.id, "laguna_seca", "and keeps its NCM id")
        T.eq(#r.flags, 0, "CSP agrees to within 2 km")
        r = P(T).resolve({ track = "ks_laguna_seca", csp = { lat = 37.5, lon = -121.75 } })
        T.eq(r.status, "verified", "the curated coordinate still wins")
        T.ok(#r.flags == 1, "but the disagreement is flagged")
    end,

    a_mod_track_resolves_from_csp_then_geotags_else_stays_unresolved = function(T)
        local r = P(T).resolve({ track = "rt_mugello", csp = { lat = 43.9975, lon = 11.3719, tzS = 3600 } })
        T.eq(r.status, "resolved", "CSP knows Mugello")
        T.eq(r.provenance, "csp ac.getTrackCoordinatesDeg", "and the record says how")
        T.eq(r.tz, 1, "with CSP's timezone")
        T.ok(P(T).destination(r), "so NCM can fly there")
        r = P(T).resolve({ track = "some_mod", geotags = { "52.07 N", "1.01 W" } })
        T.eq(r.provenance, "ui_track.json geotags", "geotags when CSP is silent")
        r = P(T).resolve({ track = "fantasy_ring", geotags = { "lat", "lon" }, csp = { lat = 0, lon = 0 } })
        T.eq(r.status, "unresolved", "nothing trustworthy")
        T.eq(r.lat, nil, "no invented coordinate")
        T.falsy(P(T).destination(r), "never offered as a destination")
        -- KB-358: the reason survives (parseGeotags returns nil, why -- it was read as three values)
        r = P(T).resolve({ track = "drift", geotags = { "lat", "lon" } })
        T.eq(r.provenance, "placeholder geotags", "a Kunos placeholder says what it is")
        r = P(T).resolve({ track = "fantasy_ring", override = { lat = 10, lon = 20 } })
        T.eq(r.provenance, "override manifest", "a manifest can correct it later")
    end,
}
