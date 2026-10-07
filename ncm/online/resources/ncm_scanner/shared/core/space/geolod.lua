-- ncm-core module: space.geolod
--
-- L332 (owner, "more actual geography underneath, fewer pixels spent rendering it"): GEOGRAPHIC LEVEL OF DETAIL for
-- NCM Deep. How much real imagery exists under the Machine is decided here, by position, altitude, the view and the
-- predicted path -- never by the renderer's resolution (that is the upscaler's business, and the simulation never sees
-- either). Both Deep renderers (Cyberpunk's WebGL page, Assetto Corsa's CSP pass) and the host bridge's tile cache
-- read the same plan.
--
-- TILES: a geographic (EPSG:4326, plate carree) quadtree -- the same equirectangular mapping the global image already
-- uses. Zoom z has 2^(z+1) columns and 2^z rows of square tiles, each `spanDeg(z) = 180 / 2^z` degrees, TILE_PX pixels.
-- Tile (0, 0) is the north-west corner (lat 90, lon -180).
--
-- CLIPMAP: one window of WINDOW x WINDOW tiles per zoom from ZMIN to the finest useful zoom, centred on the point
-- under the camera and snapped to whole tiles. A renderer samples the finest window that covers a point and whose
-- texels are not smaller than its pixels there; anything outside every window falls back to the global image.
--
-- SOURCES (owner ruling 2026-10-06: public domain only). Every layer says its licence and its credit:
--   bmng  NASA Blue Marble Next Generation (~500 m), global, via NASA GIBS
--   weld  NASA/USGS Landsat WELD true colour, annual 2000 (~30 m), global land, via NASA GIBS
--   naip  USGS The National Map orthoimagery (NAIP-based, ~1 m), the contiguous United States
-- Outside NAIP's coverage the finest zoom is 30 m-class until a better public-domain source is chosen.
local Core = NcmCore

Core.define("space.geolod", function(C)
    local M = { version = "0.1.0" }
    local D = C.get("space.deep")

    M.TILE_PX = 256
    M.WINDOW = 4                 -- tiles per side of one clipmap window (1024 px)
    M.ZMIN = 5                   -- coarser than this the global image is enough
    M.ZMAX = 16                  -- ~1.2 m per pixel (NAIP)
    M.M_PER_DEG = 111319.49      -- one degree of latitude on space.deep's sphere (R = 6371 km)

    M.LAYERS = {
        bmng = { zmin = 0, zmax = 8, licence = "public domain (NASA)", credit = "NASA Blue Marble NG (GIBS)" },
        weld = { zmin = 9, zmax = 12, licence = "public domain (NASA/USGS)", credit = "NASA/USGS Landsat WELD 2000 (GIBS)" },
        naip = { zmin = 11, zmax = 16, licence = "public domain (USDA/USGS)", credit = "USGS The National Map orthoimagery (NAIP)" },
    }
    -- NAIP covers the contiguous United States (a box is enough: outside the coast it returns nothing and the renderer
    -- keeps the coarser level)
    M.CONUS = { latS = 24.4, latN = 49.5, lonW = -125.0, lonE = -66.8 }

    function M.spanDeg(z) return 180 / 2 ^ z end
    --- metres per pixel (north-south) at zoom z
    function M.gsd(z) return M.spanDeg(z) * M.M_PER_DEG / M.TILE_PX end
    function M.cols(z) return 2 ^ (z + 1) end
    function M.rows(z) return 2 ^ z end

    --- fractional tile coordinates of a point at zoom z (x east from lon -180, y south from lat 90)
    function M.tileXY(lat, lon, z)
        local s = M.spanDeg(z)
        return (lon + 180) / s, (90 - lat) / s
    end

    --- the box of tile (z, x, y) in degrees
    function M.bounds(z, x, y)
        local s = M.spanDeg(z)
        local lonW = -180 + x * s
        local latN = 90 - y * s
        return { latS = latN - s, latN = latN, lonW = lonW, lonE = lonW + s }
    end

    local function inConus(lat, lon)
        local b = M.CONUS
        return lat >= b.latS and lat <= b.latN and lon >= b.lonW and lon <= b.lonE
    end

    --- the finest zoom any public-domain source has at a place
    function M.maxZoom(lat, lon)
        if inConus(lat, lon) then return M.LAYERS.naip.zmax end
        return M.LAYERS.weld.zmax
    end

    --- the layer that serves zoom z at a place, or nil (no source that fine there)
    function M.source(z, lat, lon)
        if z > M.maxZoom(lat, lon) then return nil end
        if z >= M.LAYERS.naip.zmin and inConus(lat, lon) then return "naip" end
        if z >= M.LAYERS.weld.zmin then return "weld" end
        return "bmng"
    end

    --- the ground spacing one pixel spans straight down from `alt` metres with a vertical field of view `fovY` (rad)
    --- over `heightPx` pixels -- the WORLD layer's internal height, not the display's
    function M.pixelGround(alt, fovY, heightPx)
        return math.max(1, alt) * 2 * math.tan((fovY or 1.0) / 2) / math.max(1, heightPx or 1080)
    end

    --- the finest zoom worth holding: its texels no smaller than the pixels straight below, clamped to what exists
    function M.fineZoom(lat, lon, alt, view)
        view = view or {}
        local need = M.pixelGround(alt, view.fovY, view.heightPx)
        local z = math.ceil(math.log(M.gsd(0) / need) / math.log(2))
        z = math.max(M.ZMIN, math.min(z, M.maxZoom(lat, lon), M.ZMAX))
        return z
    end

    --- the window (origin tile) of zoom z centred on a point: the point sits in its middle tile pair
    function M.window(lat, lon, z)
        local tx, ty = M.tileXY(lat, lon, z)
        local ox = math.floor(tx - M.WINDOW / 2 + 0.5)
        local oy = math.floor(ty - M.WINDOW / 2 + 0.5)
        oy = math.max(0, math.min(M.rows(z) - M.WINDOW, oy))
        return ox, oy
    end

    local function wrapX(x, z) local n = M.cols(z); return ((x % n) + n) % n end

    --- The clipmap for a camera over (lat, lon) at `alt`: { zFine, levels = { { z, ox, oy, gsd, layer } ... } }, coarse
    --- to fine. view = { fovY, heightPx }.
    function M.plan(lat, lon, alt, view)
        local zFine = M.fineZoom(lat, lon, alt, view)
        local levels = {}
        for z = M.ZMIN, zFine do
            local ox, oy = M.window(lat, lon, z)
            levels[#levels + 1] = { z = z, ox = ox, oy = oy, gsd = M.gsd(z), layer = M.source(z, lat, lon) }
        end
        return { zFine = zFine, lat = lat, lon = lon, alt = alt, levels = levels }
    end

    --- The tiles a plan needs, coarse first (so something is always on screen), each { layer, z, x, y } with x wrapped.
    function M.tiles(plan)
        local out = {}
        for _, l in ipairs(plan.levels) do
            if l.layer then
                for j = 0, M.WINDOW - 1 do
                    for i = 0, M.WINDOW - 1 do
                        local x, y = wrapX(l.ox + i, l.z), l.oy + j
                        local b = M.bounds(l.z, x, y)
                        -- a tile's own layer (a window may straddle NAIP's edge)
                        local layer = M.source(l.z, (b.latS + b.latN) / 2, (b.lonW + b.lonE) / 2)
                        if layer then out[#out + 1] = { layer = layer, z = l.z, x = x, y = y } end
                    end
                end
            end
        end
        return out
    end

    function M.key(t) return ("%s/%d/%d/%d"):format(t.layer, t.z, t.x, t.y) end

    --- What to fetch BEFORE it is needed: the plans at the ground track ahead (now + each horizon, dead reckoning on the
    --- real gravity-free line, good for tens of seconds) and, when Guidance has a destination, at its arrival height over
    --- it. state = { p, v } (ECEF metres); dest = { lat, lon, alt } | nil. Returns de-duplicated tiles, soonest first.
    M.HORIZONS_S = { 10, 30, 60, 120 }
    M.ARRIVAL_ALT_M = 3000
    function M.prefetch(state, dest, view, horizons)
        local out, seen = {}, {}
        local function add(plan)
            for _, t in ipairs(M.tiles(plan)) do
                local k = M.key(t)
                if not seen[k] then seen[k] = true; out[#out + 1] = t end
            end
        end
        for _, h in ipairs(horizons or M.HORIZONS_S) do
            local p = { state.p[1] + state.v[1] * h, state.p[2] + state.v[2] * h, state.p[3] + state.v[3] * h }
            local lat, lon, alt = D.ecefToLla(p)
            if alt > 0 then add(M.plan(lat, lon, alt, view)) end
        end
        if dest and dest.lat and dest.lon then
            add(M.plan(dest.lat, dest.lon, dest.alt or M.ARRIVAL_ALT_M, view))
        end
        return out
    end

    --- The on-screen credit for the layers a plan uses (finest first)
    function M.credit(plan)
        local seen, parts = {}, {}
        for i = #plan.levels, 1, -1 do
            local layer = plan.levels[i].layer
            if layer and not seen[layer] then seen[layer] = true; parts[#parts + 1] = M.LAYERS[layer].credit end
        end
        parts[#parts + 1] = "NASA Blue Marble (global)"
        return "Imagery: " .. table.concat(parts, "; ")
    end

    return M
end)
