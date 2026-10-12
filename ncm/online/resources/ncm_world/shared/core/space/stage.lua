-- ncm-core module: space.stage
--
-- L352 (owner, 2026-10-08: "let me fly there myself. it should be a full representation"): NCM Deep in the game's own
-- world. Past the seam the Machine is HELD in one of two stages of the world layer package (`ncm_world_layer`, built in
-- NCWE), inside REDengine's bounds (|x|, |y|, z < 16,384: the 2026-10-08 lab at -25 km was clamped to the corner and
-- dropped), each enclosed in the game's own starfield shell. The player keeps the native cameras; the universe is placed
-- around the held car so every body has its TRUE DIRECTION and ANGULAR SIZE from where the Machine really is
-- (space.deep's state). The simulation never changes: this only decides what REDengine is shown.
--
--   NEAR (altitude below SWITCH_M): the game's Earth, a 1,900 m static globe below the car. The car rides the radial
--        above it at r_s (R + h) / R from its centre, so the Earth fills exactly the angle the real one does.
--   FAR: no static Earth. Earth and Moon are client props on the line of sight at the distance that keeps them inside
--        the shell, scaled to their angular size (a prop scales at most PROP_MAX_SCALE).
--
-- Stated losses (v1): the car can only yaw in REDengine, so its pitch and roll are not shown; the static Earth shows a
-- fixed face (calibrated by FACE, not turned to the ground track); the Sun is the game's own light, not placed.
-- Pure: no runtime reads here; the client and the server call it.
local Core = NcmCore

Core.define("space.stage", function(C)
    local M = { version = "0.1.0" }
    local Deep = C.get("space.deep")

    M.R = 6371000.0
    M.MOON_R = 1737400.0
    M.SWITCH_M = 6.0e6           -- near -> far above this altitude ...
    M.SWITCH_BACK_M = 5.6e6      -- ... and back below this one (hysteresis: no flicker at the seam)
    M.PROP_MESH_R = 0.49         -- the q201 globe/moon meshes are ~0.98 m across
    M.PROP_MAX_SCALE = 100       -- Open77.props scale cap per axis
    M.SHELL_MARGIN = 150         -- props stay this far inside the shell

    M.STAGES = {
        near = { center = { -12000, 12000, 8000 }, shellR = 4000, earth = { -12000, 12000, 6300 }, earthR = 1900 },
        far = { center = { 12000, 12000, 8000 }, shellR = 4000 },
    }
    M.MODELS = {
        earth = "base\\environment\\decoration\\unique\\quest\\q201_q203\\q201_q203_earth_globe.mesh",
        moon = "base\\environment\\decoration\\unique\\quest\\q201_q203\\q201_q203_moon.mesh",
    }
    M.APPEARANCE = { earth = "q201_earth", moon = "default" }
    M.MIN_CLEAR_M = 3.0          -- the car's floor never closer than this to the static Earth

    local function v3(a) return { a[1], a[2], a[3] } end
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function sc(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function len(a) return math.sqrt(dot(a, a)) end
    local ATAN2 = math.atan2 or math.atan

    --- Which stage for altitude h (m), given the stage the Machine is in now (hysteresis).
    function M.which(h, current)
        if current == "far" then return h < M.SWITCH_BACK_M and "near" or "far" end
        return h >= M.SWITCH_M and "far" or "near"
    end

    --- Where the held car goes (game metres) for altitude h in stage `name`.
    function M.carAt(name, h)
        local st = M.STAGES[name]
        if name == "near" then
            local d = st.earthR * (M.R + math.max(0, h)) / M.R
            d = math.max(d, st.earthR + M.MIN_CLEAR_M)
            return add(st.earth, { 0, 0, d })
        end
        return v3(st.center)
    end

    --- How far from `eye` along unit `dir` before the shell (minus a margin): the ray-sphere exit distance.
    function M.inside(name, eye, dir)
        local st = M.STAGES[name]
        local rel = sub(eye, st.center)
        local r = st.shellR - M.SHELL_MARGIN
        local b = dot(rel, dir)
        local c = dot(rel, rel) - r * r
        local disc = b * b - c
        if disc <= 0 then return 0 end
        return -b + math.sqrt(disc)
    end

    --- A prop for a body of radius R at true distance d along game-frame unit `dir` from the car at `eye`: same direction,
    --- same angular size. Placed as far out as the shell allows, nearer when the scale cap demands it.
    function M.prop(name, eye, dir, R, d)
        local ang = math.asin(math.min(1, R / d))
        local s = math.sin(ang)
        local far = M.inside(name, eye, dir)
        local maxR = M.PROP_MESH_R * M.PROP_MAX_SCALE
        local dist = math.min(far, maxR / math.max(1e-9, s))
        local r = dist * s
        if r < 0.01 then return nil end   -- below a centimetre at its distance: sub-pixel, nothing to draw
        return { position = add(eye, sc(dir, dist)), scale = r / M.PROP_MESH_R, angularDeg = math.deg(ang), distance = dist }
    end

    -- ------------------------------------------------------------------------------------------------ the Moon
    --- The Moon's geocentric position in ECEF (m) at UTC seconds: a low-precision lunar theory (the six largest terms of
    --- the ecliptic longitude, ~0.3 deg), rotated to Earth-fixed by Greenwich sidereal time. Enough for where it hangs.
    function M.moonEcef(utc)
        local d = (tonumber(utc) or 0) / 86400 - 10957.5              -- days from J2000.0
        local r = math.rad
        local L = r((218.316 + 13.176396 * d) % 360)                 -- mean longitude
        local Mm = r((134.963 + 13.064993 * d) % 360)                -- mean anomaly
        local F = r((93.272 + 13.229350 * d) % 360)                  -- argument of latitude
        local D = r((297.850 + 12.190749 * d) % 360)                 -- mean elongation
        local Ms = r((357.529 + 0.98560028 * d) % 360)               -- the Sun's mean anomaly
        local lon = L + r(6.289) * math.sin(Mm) + r(1.274) * math.sin(2 * D - Mm) + r(0.658) * math.sin(2 * D)
            + r(0.214) * math.sin(2 * Mm) - r(0.186) * math.sin(Ms) - r(0.114) * math.sin(2 * F)
        local lat = r(5.128) * math.sin(F)
        local dist = (385001 - 20905 * math.cos(Mm)) * 1000
        local eps = r(23.439)
        local x = dist * math.cos(lat) * math.cos(lon)
        local y = dist * math.cos(lat) * math.sin(lon)
        local z = dist * math.sin(lat)
        local yq, zq = y * math.cos(eps) - z * math.sin(eps), y * math.sin(eps) + z * math.cos(eps)
        local gmst = r((280.46061837 + 360.98564736629 * d) % 360)
        local cg, sg = math.cos(gmst), math.sin(gmst)
        return { x * cg + yq * sg, -x * sg + yq * cg, zq }
    end

    -- ------------------------------------------------------------------------------------------------ the frame
    --- The view from a Deep state `s` (ECEF p, basis) at `utc`, in the stage: where the car goes, its yaw, and the props.
    --- Game axes at the car are its local east / north / up (Night City's own convention), so Earth is always straight down.
    function M.view(s, utc, current)
        local lat, lon, h = Deep.ecefToLla(s.p)
        local name = M.which(h, current)
        local eye = M.carAt(name, h)
        local f = s.basis and Deep.ecefToEnu(s.basis.forward, lat, lon) or { 0, 1, 0 }
        local yaw = math.deg(ATAN2(-f[1], f[2]))
        local out = { stage = name, car = eye, yaw = yaw, altitude = h, lat = lat, lon = lon, props = {} }
        if name == "far" then
            local r = len(s.p)
            local p = M.prop(name, eye, { 0, 0, -1 }, M.R, r)
            if p then p.id = "earth"; out.props[#out.props + 1] = p end
        end
        local m = M.moonEcef(utc)
        local rel = sub(m, s.p)
        local dm = len(rel)
        local dir = Deep.ecefToEnu(sc(rel, 1 / dm), lat, lon)
        -- the Moon hidden behind the Earth is not drawn
        local down = Deep.vec.unit(sc(s.p, -1))
        local b = dot(sc(rel, 1 / dm), down)
        local hidden = b > 0 and (len(s.p) ^ 2 - (b * len(s.p)) ^ 2) < M.R * M.R and len(s.p) * b < dm
        if not hidden then
            local p = M.prop(name, eye, dir, M.MOON_R, dm)
            if p then p.id = "moon"; out.props[#out.props + 1] = p end
        end
        return out
    end

    return M
end)
