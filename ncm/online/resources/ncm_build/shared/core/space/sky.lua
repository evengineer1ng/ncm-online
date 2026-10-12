-- ncm-core module: space.sky
--
-- The NCWE space render (L351 / IDEA-1263, L358): what NCM Sky draws around the held Machine in the Deep stage. The
-- bodies are NCWE-authored meshes (`ncm_world_layer`: the J2000 star dome from ESO's Milky Way + the Bright Star
-- Catalogue, a Blue Marble Earth, the LROC Moon), each a template in the `ncm-sky` package that redscript can turn on
-- every axis. This module says where each one goes and how it is turned, from `space.deep`'s state alone.
--
-- THE COCKPIT FRAME. REDengine shows the held car upright with a yaw ψ only. Every body is therefore placed so that, seen
-- from that upright car, it sits where it really is relative to the MACHINE's true attitude: a direction d (Earth-fixed)
-- appears in the game at  G d,  G = Rz(ψ) · [right; forward; up]  (the Machine's axes as rows). A level Machine sees the
-- old picture (Earth below, the sky turning overhead); a pitched or rolled one sees the universe swing -- the stated
-- L352 loss ("pitch and roll are not shown") is gone.
--
-- SIZES. A template has a fixed radius (REDengine cannot rescale a live entity). Each body takes the largest template
-- whose true angular size fits inside the dome, at the distance that angular size demands, and never closer to the
-- car than MIN_CLEAR_M from its surface.
-- Pure: no runtime reads.
local Core = NcmCore

Core.define("space.sky", function(C)
    local M = { version = "0.1.0" }
    local Deep = C.get("space.deep")
    local Stage = C.get("space.stage")
    local ATAN2 = math.atan2 or math.atan

    M.R = Deep.R
    M.MOON_R = 1737400.0
    M.DOME_HALF_M = 2500          -- the dome template's half-size (a cube: corners at 4.3 km)
    M.BODY_MAX_M = 2000           -- no body centre beyond this (inside the dome, well clear of its faces)
    M.MIN_CLEAR_M = 3.0           -- the car's floor never closer than this to a body's surface

    -- the `ncm-sky` package's templates (NcmSky.reds KINDS), by radius
    M.KIND = { proof_earth = 1, dome = 2 }
    M.EARTH = { { r = 1000, kind = 3 }, { r = 100, kind = 4 }, { r = 10, kind = 5 }, { r = 1, kind = 6 } }
    M.MOON = { { r = 100, kind = 7 }, { r = 10, kind = 8 }, { r = 1, kind = 9 } }

    -- --------------------------------------------------------------------------------------------- linear algebra
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function sc(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function unit(a) local l = len(a); return l > 0 and sc(a, 1 / l) or { 0, 0, 1 } end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function mv(m, v) return { dot(m[1], v), dot(m[2], v), dot(m[3], v) } end
    local function mm(a, b)
        local o = {}
        for i = 1, 3 do
            o[i] = {}
            for j = 1, 3 do o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end
        end
        return o
    end
    local function cols(x, y, z) return { { x[1], y[1], z[1] }, { x[2], y[2], z[2] }, { x[3], y[3], z[3] } } end
    local function rz(a) local c, s = math.cos(a), math.sin(a); return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } } end
    M.mv, M.mm, M.rz = mv, mm, rz

    --- A rotation matrix as a unit quaternion { i, j, k, r } (REDengine's Quaternion fields).
    function M.quat(m)
        local tr = m[1][1] + m[2][2] + m[3][3]
        local w, x, y, z
        if tr > 0 then
            local s = math.sqrt(tr + 1) * 2
            w, x, y, z = 0.25 * s, (m[3][2] - m[2][3]) / s, (m[1][3] - m[3][1]) / s, (m[2][1] - m[1][2]) / s
        elseif m[1][1] > m[2][2] and m[1][1] > m[3][3] then
            local s = math.sqrt(1 + m[1][1] - m[2][2] - m[3][3]) * 2
            w, x, y, z = (m[3][2] - m[2][3]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s, (m[1][3] + m[3][1]) / s
        elseif m[2][2] > m[3][3] then
            local s = math.sqrt(1 + m[2][2] - m[1][1] - m[3][3]) * 2
            w, x, y, z = (m[1][3] - m[3][1]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s, (m[2][3] + m[3][2]) / s
        else
            local s = math.sqrt(1 + m[3][3] - m[1][1] - m[2][2]) * 2
            w, x, y, z = (m[2][1] - m[1][2]) / s, (m[1][3] + m[3][1]) / s, (m[2][3] + m[3][2]) / s, 0.25 * s
        end
        local n = math.sqrt(w * w + x * x + y * y + z * z)
        return { x / n, y / n, z / n, w / n }
    end

    --- Greenwich mean sidereal angle (rad) at UTC seconds (the same series as space.stage's Moon).
    function M.gmst(utc)
        local d = (tonumber(utc) or 0) / 86400 - 10957.5
        return math.rad((280.46061837 + 360.98564736629 * d) % 360)
    end

    --- The game heading of the held car and the Earth-fixed -> game rotation G for a Deep state. `heldYaw` (deg, optional):
    --- the car is held at that game heading whatever the Machine does, and its yaw goes into G instead -- the universe
    --- turns around a car that never moves (KB-438: re-teleporting the held car on every turn flickered it).
    function M.frame(s, heldYaw)
        local b = s.basis or {}
        local lat, lon = Deep.ecefToLla(s.p)
        local r, f, u = b.right, b.forward, b.up
        if not (r and f and u) then   -- no attitude yet: level, facing north
            local e, n, up = Deep.enu(lat, lon)
            r, f, u = e, n, up
        end
        -- the car's yaw: the heading of the Machine's forward in local east/north (space.stage's convention)
        local fe = Deep.ecefToEnu(f, lat, lon)
        local psi = ATAN2(-fe[1], fe[2])
        if heldYaw ~= nil then psi = math.rad(tonumber(heldYaw) or 0) end
        local G = mm(rz(psi), { r, f, u })
        return G, math.deg(psi)
    end

    local function pick(list, R, dist)
        local ratio = dist / R
        for _, t in ipairs(list) do
            local d = t.r * ratio
            if d <= M.BODY_MAX_M then return t, math.max(d, t.r + M.MIN_CLEAR_M) end
        end
        return nil
    end

    --- The Moon's Earth-fixed position (m) from space.catalogue, or nil when the substrate is not loaded on this host.
    function M.catalogueMoon(utc)
        local ok, p = pcall(function()
            local A, Cat = C.get("space.astro"), C.get("space.catalogue")
            Cat.load()
            local home
            for _, r in ipairs(Cat.list()) do if r.home then home = r end end
            return A.eciToEcefVec(A.delta(Cat.stateAt("moon", utc), Cat.stateAt(home, utc)), utc)
        end)
        return ok and p or nil
    end

    --- The scene for a Deep state `s` at `utc`, the held car at game point `centre` (default: the NEAR stage centre) and,
    --- when given, held at game heading `heldYaw` (deg).
    --- Returns { car = {x,y,z}, yaw = deg, bodies = { { id, kind, p = {x,y,z}, q = {i,j,k,r} } }, notes }.
    function M.view(s, utc, centre, heldYaw)
        centre = centre or Stage.STAGES.near.center
        local G, yaw = M.frame(s, heldYaw)
        local out = { car = { centre[1], centre[2], centre[3] }, yaw = yaw, bodies = {}, notes = {} }
        local theta = M.gmst(utc)
        -- the sky: J2000 -> Earth-fixed is Rz(-θ), then into the cockpit
        out.bodies[#out.bodies + 1] = { id = "sky_dome", kind = M.KIND.dome, p = out.car, q = M.quat(mm(G, rz(-theta))) }
        -- the Earth: its mesh frame IS Earth-fixed (longitude 0 on +X, the pole on +Z)
        local toEarth = sc(s.p, -1)
        local dist = len(s.p)
        local t, d = pick(M.EARTH, M.R, dist)
        if t then
            local dir = mv(G, unit(toEarth))
            out.bodies[#out.bodies + 1] = { id = "earth", kind = t.kind, p = add(out.car, sc(dir, d)), q = M.quat(G), r = t.r, d = d }
        end
        -- the Moon: near side (+X of its mesh) to the Earth, its pole near the Earth's. doc 57 §5.4: where the catalogue
        -- says (the same Moon NCM's gravity pulls with); space.stage's own series only when the catalogue is absent
        local m = M.catalogueMoon and M.catalogueMoon(utc) or Stage.moonEcef(utc)
        local rel = sub(m, s.p)
        local dm = len(rel)
        local u = sc(rel, 1 / dm)
        local down = unit(toEarth)
        local b = dot(u, down)
        local hidden = b > 0 and dist * dist * (1 - b * b) < M.R * M.R and dist * b < dm
        if not hidden then
            local tm, dmoon = pick(M.MOON, M.MOON_R, dm)
            if tm then
                local x = unit(sc(m, -1))
                local z = unit(sub({ 0, 0, 1 }, sc(x, x[3])))
                local y = cross(z, x)
                out.bodies[#out.bodies + 1] = { id = "moon", kind = tm.kind, p = add(out.car, sc(mv(G, u), dmoon)),
                    q = M.quat(mm(G, cols(x, y, z))), r = tm.r, d = dmoon }
            end
        else
            out.notes[#out.notes + 1] = "moon behind the Earth"
        end
        return out
    end

    return M
end)
