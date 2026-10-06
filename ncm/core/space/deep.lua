-- ncm-core module: space.deep
--
-- L326: NCM's own universe, just out of REDengine's reach. Night City sits on a REAL-SCALE Earth at 35.37 N,
-- 120.85 W (owner ruling, IDEA-1133). Past an altitude NCM chooses, the Machine leaves REDengine (the car is frozen
-- there) and this module integrates it instead; on the way down it is handed back at the same place, moving.
--
-- This is deliberately NOT `space.universe` (L320's compressed 5 km Snowglobe Earth): IDEA-1129 keeps presentation
-- and simulation geometry open, and the owner asked for an OpenSpace-scale universe. Same idea as OpenSpace's
-- reference frames, reduced to what a car needs: one spherical Earth, Earth-centred coordinates, no rotation (v1).
--
-- Frames:
--   ECEF here = Earth-centred, x through (0 N, 0 E), z through the north pole, metres. Earth does not rotate in v1.
--   ENU      = east, north, up at a point.
--   GAME     = Cyberpunk world metres: x east, y north, z up, origin (0, 0) at ORIGIN, z = height above sea level.
--   MACHINE  = engineering.installation's frame: x right, y forward, z up; its basis is carried in ECEF.
local Core = NcmCore

Core.define("space.deep", function(C)
    local M = { version = "0.1.0" }

    M.R = 6371000.0               -- mean Earth radius (m)
    M.GM = 3.986004418e14         -- Earth's gravitational parameter (m^3/s^2)
    M.ORIGIN = { lat = 35.37, lon = -120.85 }   -- Night City (owner ruling 2026-10-06)

    local rad, deg = math.rad, math.deg
    local ATAN2 = math.atan2 or math.atan   -- LuaJIT (5.1) has atan2; Lua 5.4 has a two-argument atan
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function scale(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function unit(a) local l = len(a); return l > 0 and scale(a, 1 / l) or { 0, 0, 0 } end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    M.vec = { dot = dot, len = len, add = add, scale = scale, unit = unit, cross = cross }

    function M.llaToEcef(lat, lon, alt)
        local r, la, lo = M.R + (alt or 0), rad(lat), rad(lon)
        return { r * math.cos(la) * math.cos(lo), r * math.cos(la) * math.sin(lo), r * math.sin(la) }
    end

    function M.ecefToLla(p)
        local r = len(p)
        return deg(math.asin(math.max(-1, math.min(1, p[3] / r)))), deg(ATAN2(p[2], p[1])), r - M.R
    end

    --- East, north, up unit vectors (ECEF) at a latitude/longitude.
    function M.enu(lat, lon)
        local la, lo = rad(lat), rad(lon)
        return { -math.sin(lo), math.cos(lo), 0 },
            { -math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la) },
            { math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la) }
    end

    --- Game metres -> latitude/longitude: x and y are arc lengths east and north of ORIGIN.
    function M.gameToLla(x, y, z)
        local lat = M.ORIGIN.lat + deg((y or 0) / M.R)
        local lon = M.ORIGIN.lon + deg((x or 0) / (M.R * math.cos(rad(M.ORIGIN.lat))))
        return lat, lon, z or 0
    end

    function M.llaToGame(lat, lon, alt)
        return rad(lon - M.ORIGIN.lon) * M.R * math.cos(rad(M.ORIGIN.lat)), rad(lat - M.ORIGIN.lat) * M.R, alt
    end

    --- A vector given in a point's ENU (game axes there) -> ECEF.
    function M.enuToEcef(v, lat, lon)
        local e, n, u = M.enu(lat, lon)
        return { e[1] * v[1] + n[1] * v[2] + u[1] * v[3], e[2] * v[1] + n[2] * v[2] + u[2] * v[3], e[3] * v[1] + n[3] * v[2] + u[3] * v[3] }
    end

    function M.ecefToEnu(v, lat, lon)
        local e, n, u = M.enu(lat, lon)
        return { dot(v, e), dot(v, n), dot(v, u) }
    end

    --- The car leaving REDengine: game position, game velocity and the car's game-frame axes -> a deep state.
    --- `axes` = { right = {x,y,z}, forward = ..., up = ... } in game coordinates (Open77.character.frame).
    function M.enter(pos, vel, axes)
        local lat, lon, alt = M.gameToLla(pos[1], pos[2], pos[3])
        local s = { p = M.llaToEcef(lat, lon, alt), v = M.enuToEcef(vel, lat, lon), t = 0 }
        local function g(a, fallback) return a and { a.x or a[1] or 0, a.y or a[2] or 0, a.z or a[3] or 0 } or fallback end
        local f = g(axes and axes.forward, { 0, 1, 0 })
        local u = g(axes and axes.up, { 0, 0, 1 })
        local r = g(axes and axes.right, cross(f, u))
        s.basis = { right = unit(M.enuToEcef(r, lat, lon)), forward = unit(M.enuToEcef(f, lat, lon)), up = unit(M.enuToEcef(u, lat, lon)) }
        return s
    end

    function M.gravity(p)
        local r = len(p)
        return scale(p, -M.GM / (r * r * r))
    end

    --- One semi-implicit Euler step. `accEcef` = extra acceleration (thrust / mass), m/s^2.
    function M.step(s, dt, accEcef)
        local a = add(M.gravity(s.p), accEcef or { 0, 0, 0 })
        s.v = add(s.v, scale(a, dt))
        s.p = add(s.p, scale(s.v, dt))
        s.t = s.t + dt
        return s
    end

    --- Machine frame -> ECEF with the deep basis.
    function M.machineToEcef(v, b)
        return {
            b.right[1] * v[1] + b.forward[1] * v[2] + b.up[1] * v[3],
            b.right[2] * v[1] + b.forward[2] * v[2] + b.up[2] * v[3],
            b.right[3] * v[1] + b.forward[3] * v[2] + b.up[3] * v[3],
        }
    end

    --- Rotate a vector about a unit axis (Rodrigues).
    local function rot(v, k, a)
        local c, s = math.cos(a), math.sin(a)
        local kv = cross(k, v)
        local kd = dot(k, v) * (1 - c)
        return { v[1] * c + kv[1] * s + k[1] * kd, v[2] * c + kv[2] * s + k[2] * kd, v[3] * c + kv[3] * s + k[3] * kd }
    end

    --- The DEV ATTITUDE RIG (not physical: no component on the Machine makes torque). pitch/yaw/roll in rad.
    function M.turn(b, pitch, yaw, roll)
        local r, f, u = b.right, b.forward, b.up
        if pitch ~= 0 then f, u = rot(f, r, pitch), rot(u, r, pitch) end
        if yaw ~= 0 then r, f = rot(r, u, -yaw), rot(f, u, -yaw) end
        if roll ~= 0 then r, u = rot(r, f, roll), rot(u, f, roll) end
        -- re-orthonormalise so a long flight does not shear the axes
        f = unit(f); r = unit(cross(f, u)); u = unit(cross(r, f))
        b.right, b.forward, b.up = r, f, u
        return b
    end

    --- Where a ballistic trajectory meets the ground, in CLOSED FORM (two-body conic): one evaluation, no loop -- the
    --- stepped version blew OPEN//77's per-call script budget on the first frame (KB-348). Returns lat, lon, seconds
    --- (nil for the degenerate straight-up case), or nil + "orbit" / "escape".
    function M.impact(p, v)
        local r, vv = len(p), len(v)
        if r <= M.R then local la, lo = M.ecefToLla(p); return la, lo, 0 end
        local h = cross(p, v)
        local hl = len(h)
        if hl < 1e-6 * r * math.max(vv, 1e-9) then
            -- radial: straight up and down the same line (Earth does not rotate in v1)
            if dot(p, v) > 0 and vv * vv / 2 - M.GM / r >= 0 then return nil, "escape" end
            local la, lo = M.ecefToLla(p)
            return la, lo, nil
        end
        local evec = add(scale(cross(v, h), 1 / M.GM), scale(p, -1 / r))
        local e = len(evec)
        local pp = hl * hl / M.GM
        if e < 1e-9 then return nil, "orbit" end
        local c = (pp / M.R - 1) / e
        if c > 1 then return nil, "orbit" end            -- periapsis above the ground
        if c < -1 then c = -1 end
        local P = scale(evec, 1 / e)
        local Q = unit(cross(unit(h), P))
        local nuD = -math.acos(c)                         -- the descending crossing
        local nu0 = ATAN2(dot(p, Q), dot(p, P))
        if e >= 1 then
            if dot(p, v) > 0 then return nil, "escape" end
        end
        local pos = add(scale(P, M.R * math.cos(nuD)), scale(Q, M.R * math.sin(nuD)))
        local la, lo = M.ecefToLla(pos)
        local t = nil
        if e < 1 then
            local a = pp / (1 - e * e)
            local n = math.sqrt(M.GM / (a * a * a))
            local function meanAnom(nu)
                local E = 2 * ATAN2(math.sqrt(1 - e) * math.sin(nu / 2), math.sqrt(1 + e) * math.cos(nu / 2))
                return E - e * math.sin(E)
            end
            local dM = meanAnom(nuD) - meanAnom(nu0)
            while dM < 0 do dM = dM + 2 * math.pi end
            t = dM / n
        end
        return la, lo, t
    end

    --- The stepped version, kept for the offline tests that cross-check the closed form. NEVER call it per frame.
    function M.impactNumeric(p, v, horizonS, dt)
        dt, horizonS = dt or 1.0, horizonS or 10800
        local s = { p = { p[1], p[2], p[3] }, v = { v[1], v[2], v[3] }, t = 0 }
        local _, _, alt0 = M.ecefToLla(s.p)
        if alt0 <= 0 then local la, lo = M.ecefToLla(s.p); return la, lo, 0 end
        while s.t < horizonS do
            local h = dt
            local _, _, alt = M.ecefToLla(s.p)
            if alt < 20000 then h = math.min(dt, 0.25) end
            M.step(s, h)
            local la, lo, a2 = M.ecefToLla(s.p)
            if a2 <= 0 then return la, lo, s.t end
        end
        return nil, "orbit"
    end

    --- Great-circle distance (m).
    function M.distance(lat1, lon1, lat2, lon2)
        local p1, p2 = rad(lat1), rad(lat2)
        local h = math.sin((p2 - p1) / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(rad(lon2 - lon1) / 2) ^ 2
        return 2 * M.R * math.asin(math.min(1, math.sqrt(h)))
    end

    --- The Sun's direction (ECEF unit) for a local hour at Night City (equinox, v1): noon puts it overhead the meridian.
    function M.sun(hour)
        local lon = M.ORIGIN.lon + (12 - (hour or 13)) * 15
        local _, _, u = M.enu(0, lon)
        return u
    end

    --- The Sun's direction (ECEF unit) at a real UTC instant -- NCM's one clock (owner, 2026-10-06: "night = night"). The
    --- subsolar point: latitude = the declination for the day of the year, longitude = where it is solar noon now. The
    --- equation of time (+-16 min) is left out, said so. Night City's sun, Deep's sun and every host's sun are this one.
    function M.sunAt(utc)
        utc = tonumber(utc) or 0
        local days = utc / 86400
        local doy = (days - 10957 + 0.5) % 365.2422            -- 10957 = days from 1970-01-01 to 2000-01-01
        local decl = math.rad(23.44) * math.sin(2 * math.pi * (doy - 80) / 365.2422)
        local utcHour = (utc % 86400) / 3600
        local lon = math.rad(-(utcHour - 12) * 15)
        return { math.cos(decl) * math.cos(lon), math.cos(decl) * math.sin(lon), math.sin(decl) }
    end

    --- Local SOLAR hour at a longitude for a UTC instant (what the sun is doing there).
    function M.solarHour(utc, lon) return ((tonumber(utc) or 0) % 86400 / 3600 + (lon or 0) / 15) % 24 end

    --- Speed of a circular orbit at altitude (m/s), for the HUD.
    function M.orbitSpeed(alt) return math.sqrt(M.GM / (M.R + alt)) end

    return M
end)
