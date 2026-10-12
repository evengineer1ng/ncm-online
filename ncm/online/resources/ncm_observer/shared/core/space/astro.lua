-- ncm-core module: space.astro
--
-- The astronomical substrate's units, time, frames and POSITIONS (doc 57). Pure: the host passes UTC seconds.
--
-- WHERE A THING IS. An astronomical position is never one double per axis: a double resolves 1 m only out to ~9e15 m
-- (one light-year) and 100 km at the galactic centre. A position is a CELL (three exact integers) plus an OFFSET
-- (three doubles, metres, inside the cell):
--     pos = { c = { i, j, k }, o = { x, y, z } }      metres = c * CELL + o
-- CELL = 2^40 m (~7.35 AU). Offsets stay inside +-CELL/2, so they keep ~0.1 mm resolution anywhere; cell indices are
-- exact integers up to 2^53, i.e. 1e28 m (a thousand times the observable universe). Arithmetic on positions never
-- forms the full magnitude: differences are taken cell-by-cell first, so two cars a metre apart at Andromeda are a
-- metre apart.
--
-- FRAMES. The root frame is ICRF axes (J2000 equatorial, x to the vernal equinox, z to the celestial north pole) with
-- the origin at the Sun (`helio`); every catalogue position is in it. Converters: ecliptic J2000 <-> ICRF, ICRF <->
-- galactic (IAU), and ICRF <-> Earth-fixed (`space.deep`'s ECEF: x through 0 N 0 E, z to the north pole), turned by
-- the Earth rotation angle at UTC (GMST, IAU 1982 to first order; precession and nutation, ~0.3 deg over 25 years,
-- are not modelled -- said so).
local Core = NcmCore

Core.define("space.astro", function()
    local M = { version = "0.1.0" }

    -- ------------------------------------------------------------------------------------------------- units
    M.AU = 149597870700.0                 -- IAU 2012, exact
    M.LY = 9460730472580800.0             -- IAU, exact (Julian year x c)
    M.PC = 3.0856775814913673e16          -- IAU 2015
    M.C = 299792458.0
    M.G = 6.67430e-11                     -- CODATA 2018
    M.CELL = 1099511627776.0              -- 2^40 m
    local CELL, HALF = 1099511627776.0, 549755813888.0

    local floor, sqrt, sin, cos, rad, deg = math.floor, math.sqrt, math.sin, math.cos, math.rad, math.deg
    local atan2 = math.atan2 or math.atan

    -- ------------------------------------------------------------------------------------------------- vectors
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function len(a) return sqrt(dot(a, a)) end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function unit(a) local l = len(a); if l == 0 then return { 0, 0, 0 } end return scale(a, 1 / l) end
    M.vec = { add = add, sub = sub, scale = scale, dot = dot, len = len, cross = cross, unit = unit }

    -- ------------------------------------------------------------------------------------------------- positions
    local function split(x)
        -- x (a double) -> cell index, offset inside +-HALF
        local i = floor((x + HALF) / CELL)
        return i, x - i * CELL
    end

    --- A position from metres in the root frame (small or large: large values carry only double precision, which is
    --- why catalogue loaders build positions with `fromParts`).
    function M.pos(x, y, z)
        local i, ox = split(x or 0); local j, oy = split(y or 0); local k, oz = split(z or 0)
        return { c = { i, j, k }, o = { ox, oy, oz } }
    end

    --- A position from an exact cell and an offset (the offset may exceed the cell; it is renormalised).
    function M.fromParts(c, o)
        return M.normalize({ c = { c[1], c[2], c[3] }, o = { o[1], o[2], o[3] } })
    end

    function M.normalize(p)
        for a = 1, 3 do
            local o = p.o[a]
            if o >= HALF or o < -HALF then
                local n = floor((o + HALF) / CELL)
                p.c[a], p.o[a] = p.c[a] + n, o - n * CELL
            end
        end
        return p
    end

    --- p + d (d: metres vector). Returns a new position.
    function M.offset(p, d)
        return M.normalize({ c = { p.c[1], p.c[2], p.c[3] }, o = { p.o[1] + d[1], p.o[2] + d[2], p.o[3] + d[3] } })
    end

    --- a - b as a metres vector, cell difference first: exact for nearby positions anywhere in the universe.
    function M.delta(a, b)
        return {
            (a.c[1] - b.c[1]) * CELL + (a.o[1] - b.o[1]),
            (a.c[2] - b.c[2]) * CELL + (a.o[2] - b.o[2]),
            (a.c[3] - b.c[3]) * CELL + (a.o[3] - b.o[3]),
        }
    end

    function M.distance(a, b) return len(M.delta(a, b)) end

    --- The position as plain metres (only meaningful to double precision -- for display, never for physics).
    function M.metres(p) return { p.c[1] * CELL + p.o[1], p.c[2] * CELL + p.o[2], p.c[3] * CELL + p.o[3] } end

    function M.copy(p) return { c = { p.c[1], p.c[2], p.c[3] }, o = { p.o[1], p.o[2], p.o[3] } } end

    M.ORIGIN = M.pos(0, 0, 0)

    -- ------------------------------------------------------------------------------------------------- time
    --- UTC unix seconds -> Julian Date (UTC; TT - UTC = 69.184 s is added where an ephemeris wants TT).
    function M.jd(utc) return (tonumber(utc) or 0) / 86400 + 2440587.5 end
    --- Julian centuries of TT since J2000.0.
    function M.centuries(utc) return (M.jd(utc) + 69.184 / 86400 - 2451545.0) / 36525 end

    -- ------------------------------------------------------------------------------------------------- frames
    M.OBLIQUITY = rad(23.4392811)         -- J2000 mean obliquity (IAU 1976)
    local CE, SE = cos(M.OBLIQUITY), sin(M.OBLIQUITY)
    function M.eclipticToIcrf(v) return { v[1], CE * v[2] - SE * v[3], SE * v[2] + CE * v[3] } end
    function M.icrfToEcliptic(v) return { v[1], CE * v[2] + SE * v[3], -SE * v[2] + CE * v[3] } end

    -- IAU galactic frame (Hipparcos definition): rows are the galactic x (to the centre), y, z (north galactic pole)
    local GAL = {
        { -0.0548755604162154, -0.8734370902348850, -0.4838350155487132 },
        {  0.4941094278755837, -0.4448296299600112,  0.7469822444972189 },
        { -0.8676661490190047, -0.1980763734312015,  0.4559837761750669 },
    }
    function M.icrfToGalactic(v) return { dot(GAL[1], v), dot(GAL[2], v), dot(GAL[3], v) } end
    function M.galacticToIcrf(v)
        return { GAL[1][1] * v[1] + GAL[2][1] * v[2] + GAL[3][1] * v[3],
                 GAL[1][2] * v[1] + GAL[2][2] * v[2] + GAL[3][2] * v[3],
                 GAL[1][3] * v[1] + GAL[2][3] * v[2] + GAL[3][3] * v[3] }
    end

    --- Unit vector from right ascension / declination (degrees), ICRF.
    function M.radec(ra, dec)
        local a, d = rad(ra), rad(dec)
        return { cos(d) * cos(a), cos(d) * sin(a), sin(d) }
    end
    function M.toRadec(v)
        local r = len(v)
        return (deg(atan2(v[2], v[1])) % 360), deg(math.asin(math.max(-1, math.min(1, v[3] / r))))
    end

    -- Earth rotation. space.deep's ECEF turns at OMEGA about +z.
    M.OMEGA_EARTH = 7.2921159e-5
    --- Greenwich mean sidereal angle (radians) at UTC.
    function M.gmst(utc)
        local d = M.jd(utc) - 2451545.0
        return rad((280.46061837 + 360.98564736629 * d) % 360)
    end
    local function rotz(v, a) local c, s = cos(a), sin(a); return { c * v[1] - s * v[2], s * v[1] + c * v[2], v[3] } end
    M.rotz = rotz
    --- Earth-fixed position/velocity (space.deep's p, v) -> ICRF axes, Earth-centred, NON-rotating.
    function M.ecefToEci(p, v, utc)
        local th = M.gmst(utc)
        local vi = v and add(v, cross({ 0, 0, M.OMEGA_EARTH }, p)) or nil
        return rotz(p, th), vi and rotz(vi, th) or nil
    end
    --- ICRF Earth-centred vector -> Earth-fixed axes (a direction or acceleration: no velocity transport).
    function M.eciToEcefVec(v, utc) return rotz(v, -M.gmst(utc)) end
    --- The inverse of ecefToEci for a state.
    function M.eciToEcef(p, v, utc)
        local th = M.gmst(utc)
        local pe = rotz(p, -th)
        local ve = v and sub(rotz(v, -th), cross({ 0, 0, M.OMEGA_EARTH }, pe)) or nil
        return pe, ve
    end

    return M
end)
