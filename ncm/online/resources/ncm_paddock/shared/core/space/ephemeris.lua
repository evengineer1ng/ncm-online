-- ncm-core module: space.ephemeris
--
-- Ephemeris PROVIDERS (doc 57 §2). A catalogue record says how it moves (`ephem.kind`); a provider turns that into a
-- state RELATIVE TO THE RECORD'S PARENT, ICRF axes, metres and m/s, at a UTC instant. The catalogue composes states
-- up the parent chain; nothing here knows any body by name. A new source of motion (a SPICE SPK reader, a fitted
-- trajectory, a rogue planet) is a new provider, not a change to the catalogue.
--
--   fixed        { pos = {x,y,z} }                       never moves (metres, root frame)
--   fixed_radec  { ra, dec, distPc }                      a fixed point given in sky coordinates
--   kepler       { el = {a,e,I,L,peri,node}, rate = {...} }  JPL heliocentric J2000-ecliptic elements, per century
--   emb_member   { role = "earth" | "moon" }              a member of the Earth-Moon barycentre (needs gm of both)
--   satellite    { a, periodD, phase0 }                   circular about the parent's pole (record.parent's `pole`)
--   star         { pc = {x,y,z} }                         a catalogued star, parsecs, ICRF (static: no proper motion yet)
local Core = NcmCore

Core.define("space.ephemeris", function(C)
    local A = C.get("space.astro")
    local V = A.vec
    local M = { version = "0.1.0", providers = {} }
    local sin, cos, rad, sqrt, abs = math.sin, math.cos, math.rad, math.sqrt, math.abs

    -- ---------------------------------------------------------------------------------------- Keplerian elements
    local function kepler(e, Mrad)
        local E = Mrad + e * sin(Mrad)
        for _ = 1, 30 do
            local d = (E - e * sin(E) - Mrad) / (1 - e * cos(E))
            E = E - d
            if abs(d) < 1e-14 then break end
        end
        return E
    end

    M.providers.kepler = function(rec, utc)
        local T = A.centuries(utc)
        local el, rt = rec.ephem.el, rec.ephem.rate
        local a = (el[1] + rt[1] * T) * A.AU
        local e = el[2] + rt[2] * T
        local I = rad(el[3] + rt[3] * T)
        local L = el[4] + rt[4] * T
        local peri = el[5] + rt[5] * T
        local node = el[6] + rt[6] * T
        local w, O = rad(peri - node), rad(node)
        local Mrad = rad(((L - peri) + 180) % 360 - 180)
        local E = kepler(e, Mrad)
        local n = rad(rt[4]) / (36525 * 86400)                  -- mean motion, rad/s (from the mean-longitude rate)
        local Edot = n / (1 - e * cos(E))
        local b = sqrt(1 - e * e)
        local xp, yp = a * (cos(E) - e), a * b * sin(E)
        local vxp, vyp = -a * sin(E) * Edot, a * b * cos(E) * Edot
        local cw, sw, cO, sO, cI, sI = cos(w), sin(w), cos(O), sin(O), cos(I), sin(I)
        local function rot(x, y)
            return { (cw * cO - sw * sO * cI) * x + (-sw * cO - cw * sO * cI) * y,
                     (cw * sO + sw * cO * cI) * x + (-sw * sO + cw * cO * cI) * y,
                     (sw * sI) * x + (cw * sI) * y }
        end
        return A.eclipticToIcrf(rot(xp, yp)), A.eclipticToIcrf(rot(vxp, vyp))
    end

    -- ---------------------------------------------------------------------------------------- the Moon (Almanac)
    --- Geocentric Moon, ICRF axes, metres (low-precision Almanac series; ecliptic of date taken as J2000 -- the 0.3 deg
    --- precession since 2000 is the size of the series' own error).
    local function moonGeo(utc)
        local T = A.centuries(utc)
        local function sd(x) return sin(rad(x)) end
        local function cd(x) return cos(rad(x)) end
        local lam = 218.32 + 481267.881 * T + 6.29 * sd(135.0 + 477198.87 * T) - 1.27 * sd(259.3 - 413335.36 * T)
            + 0.66 * sd(235.7 + 890534.22 * T) + 0.21 * sd(269.9 + 954397.74 * T) - 0.19 * sd(357.5 + 35999.05 * T)
            - 0.11 * sd(186.5 + 966404.03 * T)
        local bet = 5.13 * sd(93.3 + 483202.02 * T) + 0.28 * sd(228.2 + 960400.89 * T) - 0.28 * sd(318.3 + 6003.15 * T)
            - 0.17 * sd(217.6 - 407332.21 * T)
        local par = 0.9508 + 0.0518 * cd(135.0 + 477198.87 * T) + 0.0095 * cd(259.3 - 413335.36 * T)
            + 0.0078 * cd(235.7 + 890534.22 * T) + 0.0028 * cd(269.9 + 954397.74 * T)
        local r = 6378140.0 / sin(rad(par))
        local cl, sl, cb, sb = cd(lam), sd(lam), cd(bet), sd(bet)
        return A.eclipticToIcrf({ r * cb * cl, r * cb * sl, r * sb })
    end
    M.moonGeo = moonGeo

    local function moonGeoState(utc)
        local h = 30
        local p0, p1, p2 = moonGeo(utc), moonGeo(utc - h), moonGeo(utc + h)
        return p0, V.scale(V.sub(p2, p1), 1 / (2 * h))
    end

    --- needs the catalogue's records for both members (gm) -- passed by the catalogue as `ctx.siblingGm`
    M.providers.emb_member = function(rec, utc, ctx)
        local g, gv = moonGeoState(utc)
        local mu = ctx.moonGm / (ctx.earthGm + ctx.moonGm)
        if rec.ephem.role == "earth" then return V.scale(g, -mu), V.scale(gv, -mu) end
        return V.scale(g, 1 - mu), V.scale(gv, 1 - mu)
    end

    -- ---------------------------------------------------------------------------------------- circular satellites
    M.providers.satellite = function(rec, utc, ctx)
        local pole = ctx.parentPole or { 0, 90 }
        local z = A.radec(pole[1], pole[2])
        local x = V.unit(V.cross({ 0, 0, 1 }, z)); if V.len(x) == 0 then x = { 1, 0, 0 } end
        local y = V.cross(z, x)
        local P = rec.ephem.periodD * 86400
        local days = A.jd(utc) - 2451545.0
        local th = rad(rec.ephem.phase0) + 2 * math.pi * (days * 86400) / P
        local a = rec.ephem.a
        local w = 2 * math.pi / P
        local p = V.add(V.scale(x, a * cos(th)), V.scale(y, a * sin(th)))
        local v = V.add(V.scale(x, -a * w * sin(th)), V.scale(y, a * w * cos(th)))
        return p, v
    end

    -- ---------------------------------------------------------------------------------------- fixed things
    M.providers.fixed = function(rec) return rec.ephem.pos, { 0, 0, 0 } end
    M.providers.fixed_radec = function(rec)
        return V.scale(A.radec(rec.ephem.ra, rec.ephem.dec), rec.ephem.distPc * A.PC), { 0, 0, 0 }
    end
    M.providers.star = function(rec) local p = rec.ephem.pc; return { p[1] * A.PC, p[2] * A.PC, p[3] * A.PC }, { 0, 0, 0 } end

    --- State of `rec` relative to its parent at `utc`: pos, vel (metres, m/s, ICRF axes).
    function M.local_(rec, utc, ctx)
        local f = M.providers[rec.ephem and rec.ephem.kind or "fixed"]
        if not f then error("space.ephemeris: no provider for " .. tostring(rec.ephem and rec.ephem.kind)) end
        return f(rec, utc, ctx or {})
    end

    return M
end)
