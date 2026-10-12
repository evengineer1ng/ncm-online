-- Offline tests for the astronomical substrate (doc 57 §4). Driven by tests/run.py.
local C = NcmCore
local A = C.get("space.astro")
local Cat = C.get("space.catalogue")
local G = C.get("space.gravity")
local T = C.get("space.telemetry")
local Json = C.get("vocabulary.json")
local V = A.vec

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then pass = pass + 1; print(("  PASS  %s%s"):format(name, detail and ("  -- " .. detail) or ""))
    else fail = fail + 1; print(("  FAIL  %s%s"):format(name, detail and ("  -- " .. detail) or "")) end
end
local function km(m) return ("%.0f km"):format(m / 1000) end
local NOW = 1791755777              -- 2026-10-11 20:36:17 UTC (the snapshot's clock)
local NOON_ET = 1791820800          -- 2026-10-12 16:00 UTC

-- ------------------------------------------------------------------------------------------------ 1. ephemerides
local function t1()
    print("1. ephemerides (" .. NOW .. ")")
    local E = Cat.stateAt("earth", NOW)
    local em = A.metres(E)
    local dAU = V.len(em) / A.AU
    check("Earth-Sun distance", dAU > 0.983 and dAU < 1.017, ("%.5f AU"):format(dAU))
    local ecl = A.icrfToEcliptic(em)
    local lon = math.deg((math.atan2 or math.atan)(ecl[2], ecl[1])) % 360
    check("Earth heliocentric longitude (Sun seen at ~198.5 deg on Oct 11)", lon > 16 and lon < 21, ("%.2f deg"):format(lon))
    local Mo = Cat.stateAt("moon", NOW)
    local dm = A.distance(Mo, E)
    check("Moon distance", dm > 356e6 and dm < 407e6, km(dm))
    local _, ve = Cat.stateAt("earth", NOW)
    check("Earth orbital speed", V.len(ve) > 29000 and V.len(ve) < 30500, ("%.0f m/s"):format(V.len(ve)))
    local J = Cat.stateAt("jupiter", NOW)
    local dj = A.distance(J, A.ORIGIN) / A.AU
    check("Jupiter heliocentric distance", dj > 4.9 and dj < 5.5, ("%.3f AU"):format(dj))
    local Io = Cat.stateAt("io", NOW)
    check("Io about Jupiter", math.abs(A.distance(Io, J) - 421800e3) < 1, km(A.distance(Io, J)))
    check("star catalogue loaded", Cat.starCount() > 50000, Cat.starCount() .. " stars")
    local prox = Cat.get("hip:70890")
    local pp = Cat.stateAt(prox, NOW)
    check("Proxima Centauri distance (Gaia DR3 parallax)", math.abs(A.distance(pp, A.ORIGIN) / A.LY - 4.2465) < 0.005, ("%.4f ly"):format(A.distance(pp, A.ORIGIN) / A.LY))
    local ab = A.distance(Cat.stateAt("hip:71683", NOW), Cat.stateAt("hip:71681", NOW)) / A.AU
    check("Alpha Centauri A-B separation is a binary, not 0.2 ly", ab > 5 and ab < 40, ("%.1f AU"):format(ab))
end

-- ------------------------------------------------------------------------------------------------ 2. coordinates
local function t2()
    print("2. hierarchical coordinates")
    for _, case in ipairs({ { "1 AU", A.AU }, { "Alpha Cen (4.37 ly)", 4.37 * A.LY }, { "Galactic Centre (26,700 ly)", 26700 * A.LY },
                            { "Andromeda (2.5 Mly)", 2.5e6 * A.LY }, { "1e26 m", 1e26 } }) do
        local p = A.pos(case[2] * 0.6, -case[2] * 0.64, case[2] * 0.48)
        local q = A.offset(p, { 1.0, 0, 0 })
        local r = A.offset(q, { 0, 0.001, 0 })
        local d1, d2 = A.distance(q, p), A.distance(r, q)
        -- offsets live inside +-2^39 m, where a double's spacing is <= 1.2e-4 m: 0.1 mm resolution at ANY distance
        check("1 m exact and 1 mm to 0.1 mm at " .. case[1], math.abs(d1 - 1) < 1e-6 and math.abs(d2 - 0.001) < 1.3e-4,
            ("%.9f m, %.9f m"):format(d1, d2))
    end
    -- walk a light-year in 1 km steps' worth of offsets and back: exact return
    local p = A.pos(3 * A.LY, 0, 0)
    local q = p
    for _ = 1, 1000 do q = A.offset(q, { 9.46073047258e12, 0, 0 }) end
    for _ = 1, 1000 do q = A.offset(q, { -9.46073047258e12, 0, 0 }) end
    check("round trip of one light-year in 1000 steps returns home", A.distance(p, q) < 1e-2, ("%.6f m"):format(A.distance(p, q)))
end

-- ------------------------------------------------------------------------------------------------ 3. continuity
local function t3()
    print("3. gravity field continuity (Earth outward to 3000 AU, ratio steps 1.002)")
    local E = Cat.stateAt("earth", NOW)
    local dir = V.unit({ 0.3, -0.9, -0.1 })
    local r, prev, worst, worstAt = 7e6, nil, 0, nil
    local sets = 0
    local prevSet = ""
    while r < 3000 * A.AU do
        local pos = A.offset(E, V.scale(dir, r))
        local a, list = G.field(pos, NOW)
        local mag = V.len(a)
        local ids = {}
        for _, c in ipairs(list) do ids[#ids + 1] = c.rec.id end
        local set = table.concat(ids, ",")
        if set ~= prevSet then sets = sets + 1; prevSet = set end
        if prev then
            local rel = math.abs(mag - prev) / prev
            -- a smooth inverse-square field changes by <= ~2 x 0.2 % per step; anything far above that is a step
            local excess = rel / 0.004
            if excess > worst then worst, worstAt = excess, r end
        end
        prev = mag
        r = r * 1.002
    end
    check("no discontinuity anywhere along the ray", worst < 3, ("worst step = %.2f x the smooth bound at %.3g m; contributor set changed %d times"):format(worst, worstAt or 0, sets))
end

-- ------------------------------------------------------------------------------------------------ 4. interstellar
local function t4()
    print("4. interstellar placement (near Alpha Centauri)")
    local a = Cat.get("hip:71683")
    local Ra = Cat.stateAt(a, NOW)
    local pos = A.offset(Ra, { 1.5e11, 2.0e10, -3.0e10 })        -- ~1 AU from Alpha Cen A
    local st = { utc = NOW, pos = pos, vel = { 0, 0, 0 }, frame = { kind = "inertial", body = a.id } }
    local rep = T.report(st)
    check("system is Alpha Centauri A", rep.system.id == a.id, rep.system.name)
    local names = {}
    for _, p in ipairs(rep.pulls) do names[#names + 1] = ("%s %.3g"):format(p.name, p.acc) end
    -- at 1 AU from A, B pulls ~1e-5 m/s^2; the Sun (8e-14) and Proxima (~5e-12) are below EPS and rightly absent
    check("pulls come from the catalogue: A and its companion B", #rep.pulls >= 2 and rep.pulls[2].name == "Alpha Centauri B", table.concat(names, " | "))
    check("distance from home in light-years", math.abs(rep.where.helioLY - 4.37) < 0.05, ("%.4f ly"):format(rep.where.helioLY))
    -- free fall for one day, RK4 in the Alpha Cen A frame, positions as astro positions
    -- precision check: A alone (B, now correctly ~26 AU away, really does change the two-body energy -- that is
    -- physics, not drift), so what is measured is the integrator + coordinates at 4.37 ly
    local onlyA = { exclude = { ["hip:71681"] = true, ["hip:70890"] = true } }
    local function acc(p, t) local g = G.relative(p, t, a.id, onlyA); return g end
    local p, v, t = pos, { 0, 25000, 0 }, NOW
    local dt = 60
    local e0
    local function energy(p, v)
        local d = A.distance(p, Ra)
        return V.dot(v, v) / 2 - a.gm / d
    end
    e0 = energy(p, v)
    for _ = 1, 1440 do
        local k1v = acc(p, t); local k1x = v
        local p2 = A.offset(p, V.scale(k1x, dt / 2)); local k2v = acc(p2, t); local k2x = V.add(v, V.scale(k1v, dt / 2))
        local p3 = A.offset(p, V.scale(k2x, dt / 2)); local k3v = acc(p3, t); local k3x = V.add(v, V.scale(k2v, dt / 2))
        local p4 = A.offset(p, V.scale(k3x, dt)); local k4v = acc(p4, t); local k4x = V.add(v, V.scale(k3v, dt))
        p = A.offset(p, V.scale(V.add(V.add(k1x, V.scale(k2x, 2)), V.add(V.scale(k3x, 2), k4x)), dt / 6))
        v = V.add(v, V.scale(V.add(V.add(k1v, V.scale(k2v, 2)), V.add(V.scale(k3v, 2), k4v)), dt / 6))
        t = t + dt
    end
    local drift = math.abs(energy(p, v) - e0) / math.abs(e0)
    check("a day of orbit around Alpha Cen A conserves energy at 4.37 ly", drift < 1e-6, ("relative energy drift %.2e"):format(drift))
    local near = Cat.near(pos, 0.5 * A.LY, NOW)
    local nn = {}
    for i, h in ipairs(near) do if i <= 4 then nn[#nn + 1] = ("%s %.3f ly"):format(h.rec.name, h.d / A.LY) end end
    check("objects around the coordinate come from the catalogue", #near >= 2, table.concat(nn, ", "))
end

-- ------------------------------------------------------------------------------------------------ 5. Galena / Hella
local function propagate(st0, toUtc, multi)
    -- Earth-centred inertial RK4, dt 60 s: Earth only, or Earth + every relevant body (third-body form)
    local earth = G.home()
    local p, v, t = st0.homeRel.p, st0.homeRel.v, st0.utc
    local function acc(p, t)
        local r = V.len(p)
        local a = V.scale(p, -earth.gm / (r * r * r))
        if multi then
            local Rh = Cat.stateAt(earth, t)
            local pos = A.offset(Rh, p)
            local pert = { 0, 0, 0 }
            for _, c in ipairs(G.contributors(pos, t, { exclude = { [earth.id] = true } })) do
                pert = V.add(pert, V.scale(V.sub(G.pull(c.rec.gm, pos, c.R), G.pull(c.rec.gm, Rh, c.R)), c.w))
            end
            a = V.add(a, pert)
        end
        return a
    end
    while t < toUtc do
        local dt = math.min(60, toUtc - t)
        local k1v = acc(p, t); local k1x = v
        local k2v = acc(V.add(p, V.scale(k1x, dt / 2)), t + dt / 2); local k2x = V.add(v, V.scale(k1v, dt / 2))
        local k3v = acc(V.add(p, V.scale(k2x, dt / 2)), t + dt / 2); local k3x = V.add(v, V.scale(k2v, dt / 2))
        local k4v = acc(V.add(p, V.scale(k3x, dt)), t + dt); local k4x = V.add(v, V.scale(k3v, dt))
        p = V.add(p, V.scale(V.add(V.add(k1x, V.scale(k2x, 2)), V.add(V.scale(k3x, 2), k4x)), dt / 6))
        v = V.add(v, V.scale(V.add(V.add(k1v, V.scale(k2v, 2)), V.add(V.scale(k3v, 2), k4v)), dt / 6))
        t = t + dt
    end
    return p, v
end

local function t5()
    print("5. the live expeditions (read-only snapshot)")
    local any = false
    for key, raw in pairs(SNAP) do
        any = true
        local rec = Json.decode(raw)
        local st = T.fromDeep(rec)
        local rep = T.report(st)
        print(("   %s (%s): %.0f km from %s, %.2f km/s %s; system %s; sphere of influence %s; %s"):format(
            key, tostring(rec.driver):sub(1, 8), rep.home.distanceM / 1000, rep.home.name, rep.home.relSpeed / 1000,
            rep.home.radialV >= 0 and "outward" or "inward", rep.system.name, rep.soi.name,
            rep.soi.orbit.bound and ("bound, apoapsis " .. km(rep.soi.orbit.apoM)) or ("unbound, v_inf " .. ("%.2f km/s"):format(rep.soi.orbit.vInf / 1000))))
        local ps = {}
        for i, p in ipairs(rep.pulls) do if i <= 5 then ps[#ps + 1] = ("%s %.3g m/s^2"):format(p.name, p.acc) end end
        print("      pulled by: " .. table.concat(ps, " | "))
        local p1 = propagate(st, NOON_ET, false)
        local p2 = propagate(st, NOON_ET, true)
        print(("      noon ET tomorrow: Earth-only %s from Earth's centre, multi-body %s (difference %s)"):format(
            km(V.len(p1)), km(V.len(p2)), km(V.len(V.sub(p2, p1)))))
        check(key .. " report built from the universe", rep.pulls[1] ~= nil and rep.soi.id ~= nil)
    end
    if not any then print("   (no snapshot found -- skipped)") end
end

local function t0()
    print("0. incremental loading (one chunk per call, as on OPEN//77)")
    local steps, done = 0, false
    while not done do done = Cat.loadStep(); steps = steps + 1 end
    check("catalogue loads in steps", Cat.loaded() and steps > 10, ("%d steps, %d stars"):format(steps, Cat.starCount()))
end

function RUN_TESTS()
    t0(); t1(); t2(); t3(); t4(); t5()
    print(("\n%d passed, %d failed"):format(pass, fail))
    return fail == 0
end
