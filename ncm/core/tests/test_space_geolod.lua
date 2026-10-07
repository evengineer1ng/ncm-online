-- space.geolod (L332): geographic level of detail for NCM Deep -- how much real imagery exists under the Machine.
local function G(T) return T.Core.get("space.geolod") end
local LAGUNA = { lat = 36.5843, lon = -121.7535 }
local MONZA = { lat = 45.6156, lon = 9.2811 }
local VIEW = { fovY = 1.0, heightPx = 1080 }

return {
    tiles_round_trip = function(T)
        local g = G(T)
        for _, z in ipairs({ 0, 5, 11, 16 }) do
            local tx, ty = g.tileXY(LAGUNA.lat, LAGUNA.lon, z)
            local b = g.bounds(z, math.floor(tx), math.floor(ty))
            T.ok(LAGUNA.lat <= b.latN and LAGUNA.lat >= b.latS and LAGUNA.lon >= b.lonW and LAGUNA.lon <= b.lonE,
                "Laguna lies inside its own tile at z" .. z)
        end
        T.eq(g.cols(0), 2, "zoom 0 is two square tiles side by side")
        T.ok(math.abs(g.gsd(16) - 1.19) < 0.05, "zoom 16 is ~1.2 m per pixel")
    end,

    the_finest_zoom_follows_altitude = function(T)
        local g = G(T)
        local z3 = g.fineZoom(LAGUNA.lat, LAGUNA.lon, 3000, VIEW)
        T.ok(g.gsd(z3) >= 1 and g.gsd(z3) <= 6, ("3 km over Laguna: %.1f m per texel"):format(g.gsd(z3)))
        T.eq(g.source(z3, LAGUNA.lat, LAGUNA.lon), "naip", "and NAIP serves it")
        local z30 = g.fineZoom(LAGUNA.lat, LAGUNA.lon, 30000, VIEW)
        T.ok(g.gsd(z30) >= 10 and g.gsd(z30) <= 60, ("30 km: %.0f m per texel"):format(g.gsd(z30)))
        local zo = g.fineZoom(LAGUNA.lat, LAGUNA.lon, 4e6, VIEW)
        T.eq(zo, g.ZMIN, "from orbit only the coarsest window (the global image does the rest)")
    end,

    a_smaller_internal_image_needs_less_geography = function(T)
        local g = G(T)
        local full = g.fineZoom(LAGUNA.lat, LAGUNA.lon, 3000, { fovY = 1.0, heightPx = 1080 })
        local half = g.fineZoom(LAGUNA.lat, LAGUNA.lon, 3000, { fovY = 1.0, heightPx = 540 })
        T.eq(half, full - 1, "half the rows, one zoom coarser")
    end,

    outside_naip_it_stops_at_thirty_metres = function(T)
        local g = G(T)
        T.eq(g.maxZoom(MONZA.lat, MONZA.lon), 12, "Monza: WELD's ~30 m is the finest public-domain source")
        T.eq(g.source(14, MONZA.lat, MONZA.lon), nil, "nothing finer is pretended")
        T.eq(g.source(12, MONZA.lat, MONZA.lon), "weld", "30 m class")
        T.eq(g.source(7, MONZA.lat, MONZA.lon), "bmng", "Blue Marble NG for the continent")
        local p = g.plan(MONZA.lat, MONZA.lon, 1000, VIEW)
        T.eq(p.zFine, 12, "a low pass over Monza holds WELD as its finest window")
    end,

    the_window_is_centred_and_stable = function(T)
        local g = G(T)
        local z = 14
        local ox, oy = g.window(LAGUNA.lat, LAGUNA.lon, z)
        local tx, ty = g.tileXY(LAGUNA.lat, LAGUNA.lon, z)
        T.ok(tx - ox >= 1.5 and tx - ox < 2.5 and ty - oy >= 1.5 and ty - oy < 2.5, "at least 1.5 tiles of margin every side")
        -- a few metres of movement does not move the window
        local ox2, oy2 = g.window(LAGUNA.lat + 1e-5, LAGUNA.lon + 1e-5, z)
        T.ok(ox2 == ox and oy2 == oy, "snapped to whole tiles")
    end,

    the_plan_is_coarse_to_fine_with_sixteen_tiles_each = function(T)
        local g = G(T)
        local p = g.plan(LAGUNA.lat, LAGUNA.lon, 3000, VIEW)
        T.eq(p.levels[1].z, g.ZMIN, "coarse first")
        T.eq(p.levels[#p.levels].z, p.zFine, "fine last")
        local tiles = g.tiles(p)
        T.eq(#tiles, 16 * #p.levels, "every level a full window")
        T.eq(tiles[1].layer, "bmng", "the first tile fetched is the coarse one")
        T.eq(tiles[#tiles].layer, "naip", "the last is the finest")
        T.ok(g.credit(p):find("NAIP") and g.credit(p):find("Blue Marble"), "the credit names every source on screen")
    end,

    the_dateline_wraps = function(T)
        local g = G(T)
        local p = g.plan(0, 179.99, 3000, VIEW)
        for _, t in ipairs(g.tiles(p)) do
            T.ok(t.x >= 0 and t.x < g.cols(t.z), "x wrapped into the grid")
        end
    end,

    prefetch_runs_ahead_and_includes_the_destination = function(T)
        local g, D = G(T), T.Core.get("space.deep")
        -- 15 km over the sea west of Laguna, heading east at 300 m/s
        local p = D.llaToEcef(36.58, -122.4, 15000)
        local e = D.enu(36.58, -122.4)
        local state = { p = p, v = { e[1] * 300, e[2] * 300, e[3] * 300 } }
        local list = g.prefetch(state, { lat = LAGUNA.lat, lon = LAGUNA.lon, alt = 3000 }, VIEW)
        local seen, dup = {}, false
        for _, t in ipairs(list) do local k = g.key(t); if seen[k] then dup = true end; seen[k] = true end
        T.ok(not dup, "no tile twice")
        local fineLaguna = false
        for _, t in ipairs(list) do
            if t.layer == "naip" and t.z >= 14 then
                local b = g.bounds(t.z, t.x, t.y)
                if math.abs((b.latS + b.latN) / 2 - LAGUNA.lat) < 0.05 and math.abs((b.lonW + b.lonE) / 2 - LAGUNA.lon) < 0.05 then fineLaguna = true end
            end
        end
        T.ok(fineLaguna, "the destination's fine NAIP tiles are fetched before arrival")
    end,
}
