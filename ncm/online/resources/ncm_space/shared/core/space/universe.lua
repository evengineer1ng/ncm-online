-- ncm-core module: space.universe
--
-- Universe Authority v0 (L317; doc 51 §6): where things ARE, independent of where REDengine can put them. Night City
-- has a hard ceiling at z = 16,384 m (2^14, §AX4), so above a transition altitude NCM owns position and REDengine only
-- simulates a local BUBBLE recentred under the car -- a floating origin. Pure: no runtime reads this yet.
--
-- Frames and units. Metres, seconds, Lua doubles (53-bit mantissa: 1.5e11 m resolves to ~0.03 mm, so no special
-- arithmetic). One inertial frame for v0, Earth-centred (`earth`): Earth at the origin, the Moon and the Sun at fixed
-- positions (no orbits yet; `t` is carried for when they move). Night City is an ANCHOR on Earth's surface whose local
-- axes are taken as east / north / up at that point, so a REDengine coordinate (x, y, z) is the anchor plus x east,
-- y north, z up. The curvature this ignores is 21 m of drop over Night City's ~16 km: invisible at v0.
--
-- The bubble. A bubble is an origin in universe coordinates plus the anchor basis; local = universe - origin, in that
-- basis. **Rebasing moves the origin and nothing else**: every universe position is unchanged, every local one shifts
-- by the same vector. That is the seam's invariant (L317 constraint 1): it is invisible only when everything in view
-- is NCM's (the car and proxies), so the native city must leave view before the first rebase.
--
-- Proxies. A body of radius R at distance d, drawn at distance d' (inside the camera's far plane), gets radius
-- R * d'/d: the same angular size, the same direction. Nothing REDengine draws is ever astronomically far or large.
local Core = NcmCore

Core.define("space.universe", function(C)
    local M = { version = "0.4.0" }

    M.G = 6.674e-11
    -- v0 bodies. Positions in the Earth-centred frame; the Moon at its mean distance, the Sun at 1 AU, in fixed
    -- illustrative directions (no ephemeris). Radii and masses are real.
    M.BODIES = {
        earth = { id = "earth", radius = 6371000, mass = 5.972e24, pos = { 0, 0, 0 } },
        moon  = { id = "moon",  radius = 1737400, mass = 7.342e22, pos = { 384400000, 0, 0 } },
        sun   = { id = "sun",   radius = 696340000, mass = 1.989e30, pos = { 0, 149597870700, 0 } },
    }

    -- City anchors: points on Earth's surface, latitude/longitude in degrees, illustrative (the seed may move them).
    -- Local axes for every city: x east, y north, z up -- true of REDengine and of GTA V alike. Two cities on ONE Earth
    -- frame is the cross-world premise (L318, doc 52): Night City and Los Santos share a universe, not a server.
    M.ANCHORS = {
        night_city = { lat = 37.0, lon = -122.0 },
        los_santos = { lat = 34.05, lon = -118.24 },
    }
    M.ANCHOR = M.ANCHORS.night_city

    local function anchorOf(a)
        if type(a) == "string" then return M.ANCHORS[a] or error("space.universe: unknown anchor " .. a) end
        return a or M.ANCHOR
    end

    -- The seam (L317 Q2 placeholders until SEAM-2): the bubble wakes at `wakeAt` and owns position from `ownAt`; both
    -- below the hard ceiling.
    M.CEILING = 16384
    M.PHASES = { wakeAt = 12000, ownAt = 14000 }

    -- ---------------------------------------------------------------------------------------- vectors
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function scale(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function len(a) return math.sqrt(dot(a, a)) end
    M.vec = { add = add, sub = sub, scale = scale, dot = dot, len = len }

    --- The anchor's east / north / up unit vectors and its surface point, in the Earth frame.
    function M.anchorFrame(anchor)
        anchor = anchorOf(anchor)
        local la, lo = math.rad(anchor.lat), math.rad(anchor.lon)
        local up = { math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la) }
        local east = { -math.sin(lo), math.cos(lo), 0 }
        local north = { -math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la) }
        local R = M.BODIES.earth.radius
        return { east = east, north = north, up = up, surface = scale(up, R) }
    end

    local function fromBasis(f, v) return add(add(scale(f.east, v[1]), scale(f.north, v[2])), scale(f.up, v[3])) end
    local function toBasis(f, v) return { dot(v, f.east), dot(v, f.north), dot(v, f.up) } end

    --- A REDengine (Night City) coordinate to the universe, and back.
    function M.cityToUniverse(p, anchor)
        local f = M.anchorFrame(anchor)
        return add(f.surface, fromBasis(f, p))
    end
    function M.universeToCity(u, anchor)
        local f = M.anchorFrame(anchor)
        return toBasis(f, sub(u, f.surface))
    end

    --- Height above Earth's surface (the sphere), for a universe position.
    function M.altitude(u) return len(sub(u, M.BODIES.earth.pos)) - M.BODIES.earth.radius end

    --- Which regime a universe position is in: `native` (REDengine owns it), `transition`, `space` (NCM owns it).
    function M.phase(u, phases)
        phases = phases or M.PHASES
        local h = M.altitude(u)
        if h < phases.wakeAt then return "native", h end
        if h < phases.ownAt then return "transition", h end
        return "space", h
    end

    -- ---------------------------------------------------------------------------------------- the bubble
    --- A bubble whose local coordinates coincide with Night City's (origin = the anchor's surface point).
    function M.cityBubble(anchor)
        local f = M.anchorFrame(anchor)
        return { origin = f.surface, frame = f, rebases = 0 }
    end

    --- Great-circle distance between two anchors over Earth's surface (metres).
    function M.surfaceDistance(a, b)
        local fa, fb = M.anchorFrame(a), M.anchorFrame(b)
        local c = dot(fa.up, fb.up)
        if c > 1 then c = 1 elseif c < -1 then c = -1 end
        return M.BODIES.earth.radius * math.acos(c)
    end

    function M.toLocal(bubble, u) return toBasis(bubble.frame, sub(u, bubble.origin)) end
    function M.toUniverse(bubble, l) return add(bubble.origin, fromBasis(bubble.frame, l)) end

    --- Recentre the bubble so that universe point `u` sits at local `target` (default {0, 0, 0}). Returns the local
    --- shift every bubble object must receive (new local = old local + shift). Universe positions do not change.
    function M.rebase(bubble, u, target)
        target = target or { 0, 0, 0 }
        local before = M.toLocal(bubble, u)
        bubble.origin = sub(u, fromBasis(bubble.frame, target))
        bubble.rebases = bubble.rebases + 1
        return sub(target, before)
    end

    --- True when a local position is safely inside REDengine's bounds (|each axis| below the ceiling with margin).
    function M.localSafe(l, margin)
        local lim = M.CEILING - (margin or 1000)
        return math.abs(l[1]) < lim and math.abs(l[2]) < lim and math.abs(l[3]) < lim
    end

    -- ---------------------------------------------------------------------------------------- proxies
    --- Where and how big to draw `body` from universe point `eye`, at render distance `drawAt` (metres, inside the
    --- far plane). Returns the local-direction unit vector, the proxy radius, the true distance and the angular radius.
    function M.proxy(body, eye, drawAt, frame)
        local rel = sub(body.pos, eye)
        local d = len(rel)
        local dir = scale(rel, 1 / d)
        local local_dir = frame and toBasis(frame, dir) or dir
        local r = body.radius * drawAt / d
        return { dir = local_dir, radius = r, distance = d, angular = math.asin(math.min(1, body.radius / d)) }
    end

    -- ------------------------------------------------------------------------------------- the world
    --- Snowglobe Earth (owner, 2026-10-05, L320): "Give Snowglobe Earth a deliberately compressed physical radius while
    --- retaining approximately 1 g at the surface ... Gravity should be radial toward the NCM Earth center ... Allow
    --- ballistic trajectories and real orbit within the compressed system ... The exact Earth radius is a tunable
    --- world/seed constant. 5 km is a reasonable first experiment, not yet canon."
    --- A host calls this once; it sets Earth's radius and its mass from GM = g * R^2. The default stays real Earth.
    M.EARTH_REAL = { radius = 6371000, mass = 5.972e24 }
    function M.setWorld(opts)
        opts = opts or {}
        local R = tonumber(opts.earthRadius) or M.EARTH_REAL.radius
        local g = tonumber(opts.surfaceG)
        M.BODIES.earth.radius = R
        M.BODIES.earth.mass = g and (g * R * R / M.G) or M.EARTH_REAL.mass
        -- the atmosphere is a world constant too (L321): an exponential with a scale height. Real Earth's is 8.5 km;
        -- a compressed Earth gets a compressed default so propellers and wings die within reach of a car, not at 40 km.
        M.ATMOSPHERE.scaleHeightM = tonumber(opts.scaleHeightM) or (R < M.EARTH_REAL.radius and 1200 or 8500)
        M.ATMOSPHERE.seaLevelRho = tonumber(opts.seaLevelRho) or 1.225
        return M.BODIES.earth
    end

    --- The atmosphere (L321; doc 54 §D): density falls exponentially with altitude. It decides whether an
    --- atmospheric push (propeller, jet, wing, convective radiator) does anything -- physically, not by a flag.
    M.ATMOSPHERE = { seaLevelRho = 1.225, scaleHeightM = 8500 }
    --- Air density (kg/m^3) at altitude h (metres above the surface); 0 above 30 scale heights.
    function M.densityAt(h)
        local A = M.ATMOSPHERE
        if h < 0 then h = 0 end
        if h > 30 * A.scaleHeightM then return 0 end
        return A.seaLevelRho * math.exp(-h / A.scaleHeightM)
    end
    --- Air density at universe point u.
    function M.density(u) return M.densityAt(M.altitude(u)) end

    --- Speed of a circular orbit around Earth at universe point `u` (m/s).
    function M.circularSpeed(u)
        local r = len(sub(u, M.BODIES.earth.pos))
        return math.sqrt(M.G * M.BODIES.earth.mass / r)
    end

    --- One semi-implicit Euler step of a universe state { u = pos, w = vel } under acceleration `a` (Earth frame).
    --- Symplectic enough that a circular orbit keeps its radius over many periods at frame-sized steps.
    function M.integrate(state, a, dt)
        state.w = add(state.w, scale(a, dt))
        state.u = add(state.u, scale(state.w, dt))
        return state
    end

    --- A local (east, north, up) vector into the Earth frame, and back.
    function M.localToEarth(frame, v) return fromBasis(frame, v) end
    function M.earthToLocal(frame, v) return toBasis(frame, v) end

    local BODY_ORDER = { "earth", "moon", "sun" }   -- a fixed summation order: the same bits on every machine
    --- Gravitational acceleration at universe point `u` from every v0 body (m/s^2, a vector).
    function M.gravity(u)
        local g = { 0, 0, 0 }
        for _, id in ipairs(BODY_ORDER) do
            local b = M.BODIES[id]
            local r = sub(b.pos, u)
            local d = len(r)
            if d > b.radius * 0.5 then g = add(g, scale(r, M.G * b.mass / (d * d * d))) end
        end
        return g
    end

    return M
end)
