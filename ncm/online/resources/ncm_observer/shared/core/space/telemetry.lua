-- ncm-core module: space.telemetry
--
-- What a Deep vehicle IS, astronomically (doc 57 §2, owner brief §9): one report built from the catalogue, the
-- ephemerides and the gravity field. Nothing here assumes Earth: "home" is the record marked home, the orbit is told
-- about whichever body's sphere of influence holds the vehicle, and a vehicle between the stars simply has no conic.
--
--   M.fromDeep(rec)          a space.deep / ncm_presence record (Earth-fixed p, vel; utc) -> astronomical state
--   M.report(state, opts)    the full report (see the table built at the end)
--   M.conic(gm, r, v)        two-body elements about any body (bound or not)
--   M.accumulate(acc, st)    running totals a host keeps per vehicle: distance travelled, max distance from home
local Core = NcmCore

Core.define("space.telemetry", function(C)
    local A = C.get("space.astro")
    local Cat = C.get("space.catalogue")
    local G = C.get("space.gravity")
    local V = A.vec
    local M = { version = "0.1.0" }

    --- An astronomical state: { utc, pos (astro), vel (m/s, ICRF, heliocentric inertial), frame, source }.
    function M.fromDeep(rec)
        Cat.load()
        local utc = tonumber(rec.utc) or 0
        local home = G.home()
        -- doc 57 §5.3: a record flying in an inertial frame carries its authoritative state there (ip / iv at futc)
        if type(rec.frame) == "table" and rec.frame.kind == "inertial" and rec.ip and rec.iv then
            local futc = tonumber(rec.futc) or utc
            local Rc, Vc
            if type(rec.frame.anchor) == "table" and rec.frame.anchor.c then
                Rc, Vc = A.fromParts(rec.frame.anchor.c, rec.frame.anchor.o), { 0, 0, 0 }
            else
                Rc, Vc = Cat.stateAt(rec.frame.body, futc)
            end
            if Rc then
                return { utc = futc, pos = A.offset(Rc, rec.ip), vel = V.add(Vc, rec.iv),
                         frame = { kind = "inertial", body = rec.frame.body }, source = rec }
            end
        end
        local Rh, Vh = Cat.stateAt(home, utc)
        local pi, vi = A.ecefToEci(rec.p, rec.vel or rec.v or { 0, 0, 0 }, utc)
        return { utc = utc, pos = A.offset(Rh, pi), vel = V.add(Vh, vi), frame = { kind = "body_fixed", body = home.id },
                 source = rec, homeRel = { p = pi, v = vi } }
    end

    --- Two-body conic of a state relative to a body of parameter gm. r, v: relative position/velocity (m, m/s).
    function M.conic(gm, r, v)
        local rr, vv = V.len(r), V.dot(v, v)
        local energy = vv / 2 - gm / rr
        local h = V.cross(r, v)
        local hl = V.len(h)
        local evec = V.sub(V.scale(V.cross(v, h), 1 / gm), V.scale(r, 1 / rr))
        local e = V.len(evec)
        local incl = hl > 0 and math.deg(math.acos(math.max(-1, math.min(1, h[3] / hl)))) or 0
        local radial = V.dot(r, v) / rr
        local out = { energy = energy, e = e, iDeg = incl, radialV = radial, speed = math.sqrt(vv),
                      escapeV = math.sqrt(2 * gm / rr), bound = energy < 0, periM = (hl * hl / gm) / (1 + e) }
        if energy < 0 then
            local a = -gm / (2 * energy)
            out.a, out.apoM, out.periodS = a, a * (1 + e), 2 * math.pi * math.sqrt(a * a * a / gm)
        else
            out.vInf = math.sqrt(2 * energy)               -- the speed it keeps forever (hyperbolic excess)
        end
        return out
    end

    local function bodyRel(st, rec)
        local R, Vb = Cat.stateAt(rec, st.utc)
        local dp = A.delta(st.pos, R)
        local dv = V.sub(st.vel, Vb)
        local d = V.len(dp)
        return { id = rec.id, name = rec.name, kind = rec.kind, distanceM = d,
                 altitudeM = rec.radius and (d - rec.radius) or nil,
                 relSpeed = V.len(dv), radialV = d > 0 and V.dot(dp, dv) / d or 0, r = dp, v = dv }
    end

    --- The report. opts: { nearestN = 8, contributorsN = 8, eps }
    function M.report(st, opts)
        opts = opts or {}
        local utc = st.utc
        local home = G.home()
        local sun = Cat.get("sun")
        local m = A.metres(st.pos)

        -- where: at every scale
        local helioD = A.distance(st.pos, A.ORIGIN)
        local ra, dec = A.toRadec(m)
        local gal = A.icrfToGalactic(m)
        local l = math.deg((math.atan2 or math.atan)(gal[2], gal[1])) % 360
        local b = math.deg(math.asin(math.max(-1, math.min(1, gal[3] / math.max(helioD, 1)))))
        local where = { helioM = helioD, helioAU = helioD / A.AU, helioLY = helioD / A.LY,
                        cell = { st.pos.c[1], st.pos.c[2], st.pos.c[3] }, offset = { st.pos.o[1], st.pos.o[2], st.pos.o[3] },
                        raDeg = ra, decDeg = dec, galLDeg = l, galBDeg = b }

        -- what pulls on it (absolute field) and what it feels in its own frame
        local total, contrib = G.field(st.pos, utc, { eps = opts.eps })
        local pulls = {}
        for i, c in ipairs(contrib) do
            if i > (opts.contributorsN or 8) then break end
            pulls[#pulls + 1] = { id = c.rec.id, name = c.rec.name, kind = c.rec.kind, acc = c.acc * c.w, distanceM = c.d,
                                  share = c.acc * c.w / math.max(V.len(total), 1e-300) }
        end
        -- the system and the dominant body (sphere of influence); its conic
        local sys = Cat.system(st.pos, utc)
        local soi = Cat.soi(st.pos, utc)
        local soiRel = bodyRel(st, soi)
        local orbit = M.conic(soi.gm, soiRel.r, soiRel.v)
        -- a trajectory whose low point is inside the body comes back down: say it in words, not "periapsis 15 km"
        if orbit.bound and soi.radius and orbit.periM < soi.radius then orbit.impacts = true end

        -- the frame a vehicle flies in (Earth-fixed today); a free (virtual / inertial) state feels its dominant body's frame
        local frameBody = st.frame and st.frame.body and Cat.get(st.frame.body) or soi
        local relA = G.relative(st.pos, utc, frameBody.id, { eps = opts.eps })

        -- near things
        local nearest = {}
        local radius = math.max(helioD * 2, 1e12)
        if radius > 10 * A.PC then radius = 10 * A.PC end
        local hits = Cat.near(st.pos, radius, utc)
        if #hits == 0 then
            local rec = Cat.nearest(st.pos, utc)                 -- deep between the stars: search outward
            if rec then hits = { { rec = rec } } end
        end
        for i, h in ipairs(hits) do
            if i > (opts.nearestN or 8) then break end
            local r = bodyRel(st, h.rec)
            nearest[#nearest + 1] = { id = r.id, name = r.name, kind = r.kind, distanceM = r.distanceM, altitudeM = r.altitudeM,
                                      relSpeed = r.relSpeed, radialV = r.radialV }
        end

        local homeRel = bodyRel(st, home)
        local homeOrbit = M.conic(home.gm, homeRel.r, homeRel.v)
        local src = st.source or {}
        local tanks = src.dyn and src.dyn.tanks or {}
        return {
            utc = utc,
            vehicle = { asset = src.asset, vehicleKey = src.vehicleKey, driver = src.driver, host = src.host, provenance = src.provenance },
            where = where,
            velocity = { icrf = st.vel, speed = V.len(st.vel), frame = "heliocentric inertial (ICRF axes)" },
            frame = st.frame,
            system = { id = sys.id, name = sys.name },
            soi = { id = soi.id, name = soi.name, distanceM = soiRel.distanceM, relSpeed = soiRel.relSpeed, radialV = soiRel.radialV, orbit = orbit },
            home = { id = home.id, name = home.name, distanceM = homeRel.distanceM, altitudeM = homeRel.altitudeM,
                     relSpeed = homeRel.relSpeed, radialV = homeRel.radialV, orbit = homeOrbit },
            pulls = pulls,
            totalAcc = V.len(total),
            frameAcc = { body = frameBody.id, acc = V.len(relA) },
            nearest = nearest,
            propulsion = { fuelKg = tonumber(src.fuelKg), tanksKg = tanks, throttle = src.dyn and src.dyn.thr or nil, massKg = tonumber(src.massKg) },
        }
    end

    --- Running totals for one vehicle: acc = { travelledM, maxFromHomeM, lastPos, lastUtc } (create with {}).
    function M.accumulate(acc, st, rep)
        if acc.lastPos then acc.travelledM = (acc.travelledM or 0) + A.distance(st.pos, acc.lastPos) end
        acc.lastPos, acc.lastUtc = A.copy(st.pos), st.utc
        local dh = rep and rep.home.distanceM or nil
        if dh and dh > (acc.maxFromHomeM or 0) then acc.maxFromHomeM, acc.maxFromHomeUtc = dh, st.utc end
        return acc
    end

    return M
end)
