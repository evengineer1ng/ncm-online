-- ncm-core module: space.drive.alcubierre -- XLB-AB1, the Alcubierre bubble (doc 58 §5.4).
--
-- PHYSICAL BASIS: Alcubierre (1994), "The warp drive: hyper-fast travel within general relativity". The metric
--     ds^2 = -c^2 dt^2 + (dx - v_s f(r_s) dt)^2 + dy^2 + dz^2,
--     f(r_s) = [tanh(sigma (r_s + R)) - tanh(sigma (r_s - R))] / [2 tanh(sigma R)]
-- contracts space ahead of a bubble of radius R (wall thickness ~1/sigma) and expands it behind; inside, the ship is in
-- free fall in flat space: it feels no acceleration, its proper time runs with coordinate time, and the bubble's
-- coordinate speed v_s may exceed c. SPECULATIVE, SAID SO: the metric needs negative energy density in the wall --
-- Pfenning & Ford (1997) estimate |E| ~ (c^4/G) v_s^2 R^2 sigma / 4 (v_s in units of c), far beyond anything that
-- exists -- and nobody knows how to make, steer or stop a bubble (Krasnikov's causality problem). NCM's fiction is only
-- that the XLB-AB1 can form one along a PREPARED solution; the energy it reports is the estimate above, labelled.
--
-- So, in play: lock a solution (target or heading + distance) -> the bubble forms (BUBBLE_FORMING, then BUBBLE_STABLE)
-- -> ENGAGED: the Machine is carried along x_s(t), a smooth profile (ramp, cruise at v_s, ramp) from the origin to the
-- solution's emergence point. No steering (the bubble is the vehicle now), no gravity on the car inside (flat interior;
-- the bubble's own interaction with fields en route is not modelled), its own velocity unchanged on emergence.
-- Stability decays with time and with the tidal field the wall crosses; below failBelow the bubble collapses early, at
-- the real intermediate coordinate. Emergence error: a deterministic seeded offset ~ errorFrac x distance x (1 - quality).
-- Collapse: the particles the wall swept up are released ahead (McMonigal, Lewis & O'Byrne 2012) -- NCM's emergence
-- flash.
local Core = NcmCore

Core.define("space.drive.alcubierre", function(C)
    local M = {}
    local Dr = C.get("space.drives")
    local A = C.get("space.astro")
    local V = A.vec
    local Fr, Cat

    local DEF = { vsC = 1e6, accelS = 10, formS = 15, settleS = 2, collapseS = 2.5, cooldownS = 30, R = 6, sigma = 8,
        decayPerS = 0.0015, tidalRef = 1e-3, failBelow = 0.15, errorFrac = 2e-6, quality = 0.8, maxLy = 100,
        formCost = 1500, perLyCost = 60, abortHoldS = 1.0, standoffStarAU = 2, standoffBodyRadii = 10 }
    local function P(d, k) local v = d.perf[k]; if v == nil then v = DEF[k] end; return v end
    local function deps() Fr, Cat = Fr or C.get("space.frames"), Cat or C.get("space.catalogue") end

    -- the profile: smoothstep ramps of accelS at each end, cruise at vs between
    local function I(u) return u * u * u - u * u * u * u / 2 end
    function M.profile(D, vs, ta)
        if D <= vs * ta then vs = D / ta; return { D = D, vs = vs, ta = ta, tc = 0, T = 2 * ta } end
        local tc = (D - vs * ta) / vs
        return { D = D, vs = vs, ta = ta, tc = tc, T = 2 * ta + tc }
    end
    function M.x(pr, t)
        if t <= 0 then return 0 end
        if t >= pr.T then return pr.D end
        local vs, ta, tc = pr.vs, pr.ta, pr.tc
        if t < ta then return vs * ta * I(t / ta) end
        if t < ta + tc then return vs * ta / 2 + vs * (t - ta) end
        local u = (t - ta - tc) / ta
        return vs * ta / 2 + vs * tc + vs * ta * (u - I(u))
    end
    function M.v(pr, t)
        if t <= 0 or t >= pr.T then return 0 end
        local ta, tc = pr.ta, pr.tc
        local function ss(u) return u * u * (3 - 2 * u) end
        if t < ta then return pr.vs * ss(t / ta) end
        if t < ta + tc then return pr.vs end
        return pr.vs * (1 - ss((t - ta - tc) / ta))
    end

    --- Pfenning-Ford order of magnitude of the negative energy the wall needs (J, magnitude).
    function M.energy(vsC, R, sigma) return (A.C ^ 4 / A.G) * vsC * vsC * R * R * sigma / 4 end

    -- lock: the emergence point is what is locked (target short of its standoff, plus the seeded error)
    local function solve(ctx, d, ds)
        local s = ctx.s
        local rec, tp = Dr.target(ds.targetId, s, s.utc)
        if not rec then return nil, "no target" end
        local here = Dr.astro(s)
        local vs = P(d, "vsC") * A.C
        -- a moving body: aim where it will be when the bubble arrives (one refinement is plenty at these speeds)
        local eta = P(d, "formS") + P(d, "settleS") + A.distance(here, tp) / vs + P(d, "accelS")
        local rec2, tp2 = Dr.target(ds.targetId, s, s.utc + eta)
        if rec2 then tp = tp2 end
        local toT = A.delta(tp, here)
        local dist = V.len(toT)
        if dist <= 0 then return nil, "already there" end
        local dir = V.scale(toT, 1 / dist)
        local stand = Dr.standoff(rec, d.perf)
        local D = math.max(0, dist - stand)
        if D <= 0 then return nil, ("inside the standoff of %s"):format(tostring(rec.name or rec.id)) end
        if D > P(d, "maxLy") * A.LY then return nil, ("%.3g ly is beyond this bubble's %.3g ly"):format(D / A.LY, P(d, "maxLy")) end
        local r = Dr.rng(d.componentId .. ":" .. (ds.n or 0) + 1 .. ":" .. ds.targetId)
        -- never more than half the standoff: an error must not put the Machine inside what it was aimed short of
        local errM = math.min(D * P(d, "errorFrac") * (1 - P(d, "quality")) * (0.5 + r()), 0.5 * stand)
        local err = V.scale(Dr.randomUnit(r), errM)
        local E = A.offset(A.offset(here, V.scale(dir, D)), err)
        return { targetId = ds.targetId, name = rec.name or rec.id, emergence = Dr.posTable(E), D = D, errM = V.len(err),
                 standoffM = stand, lockedUtc = s.utc }
    end

    local function charge(d, D) return P(d, "formCost") + P(d, "perLyCost") * D / A.LY end

    function M.step(ctx, d, ds, c, dt)
        deps()
        local s = ctx.s
        if c.abort and c.abort > 0 then ds.holdT = (ds.holdT or 0) + dt else ds.holdT = 0 end
        local abort = (ds.holdT or 0) >= P(d, "abortHoldS")
        local st = ds.state
        if st == "OFF" or st == "DESTINATION_LOCKED" then
            if c.next or c.prev then
                Dr.select(ds, d, c, Dr.inRange(s, P(d, "maxLy") * A.LY + 4 * A.AU))
                if st == "DESTINATION_LOCKED" then ds.sol = nil; Dr.set(ctx, d, ds, "OFF", "target changed") end
                st = ds.state
            end
        end
        if st == "OFF" then
            if c.engage then
                local sol, why = solve(ctx, d, ds)
                if not sol then ds.msg = "no solution: " .. tostring(why); Dr.set(ctx, d, ds, "FAILED", "no_solution"); return end
                if (ds.charge or 0) < charge(d, sol.D) then ds.msg = ("needs %.0f charge, has %.0f"):format(charge(d, sol.D), ds.charge or 0); Dr.set(ctx, d, ds, "FAILED", "no_charge"); return end
                ds.sol, ds.msg = sol, ("solution: %s, %.4g ly, emergence error %.3g km"):format(sol.name, sol.D / A.LY, sol.errM / 1000)
                Dr.set(ctx, d, ds, "DESTINATION_LOCKED", "solution locked")
            end
            return
        end
        if st == "DESTINATION_LOCKED" then
            if abort then ds.sol = nil; Dr.set(ctx, d, ds, "OFF", "unlocked"); return end
            if c.engage then
                Fr.toInertial(s, s.utc)
                Dr.begin(ctx, d, ds, { target = ds.sol.targetId })
                Dr.spend(ds, charge(d, ds.sol.D))
                local R, sigma, vsC = P(d, "R"), P(d, "sigma"), P(d, "vsC")
                ds.act.detail.bubble = { R = R, sigma = sigma, vsC = vsC, energyJ_PF = M.energy(vsC, R, sigma), wall = 1 / sigma,
                    note = "Pfenning-Ford estimate of the negative energy; the drive's supply of it is fiction (doc 58)" }
                ds.act.detail.solution = ds.sol
                ds.stab = 1
                Dr.set(ctx, d, ds, "BUBBLE_FORMING", "forming")
            end
            return
        end
        if st == "BUBBLE_FORMING" then
            if abort then
                Dr.finish(ctx, d, ds, false, "aborted_in_formation")
                ds.sol = nil
                Dr.set(ctx, d, ds, "COOLDOWN", "aborted")
                return
            end
            if ds.t >= P(d, "formS") then Dr.set(ctx, d, ds, "BUBBLE_STABLE", "bubble stable") end
            return
        end
        if st == "BUBBLE_STABLE" and ds.t >= P(d, "settleS") then
            -- the ride: from where the Machine is NOW to the locked emergence point, attitude and velocity held
            local O = Dr.astro(s)
            local _, v0 = Dr.astro(s)
            local E = Dr.fromTable(ds.sol.emergence)
            local toE = A.delta(E, O)
            local D = V.len(toE)
            local pr = M.profile(D, P(d, "vsC") * A.C, P(d, "accelS"))
            ds.ride = { O = Dr.posTable(O), dir = V.scale(toE, 1 / math.max(D, 1e-9)), pr = pr, t = 0, v0 = Dr.cp3(v0), rot = Dr.cpR(s.rot) }
            ds.act.detail.profile = { D = pr.D, vsC = pr.vs / A.C, rampS = pr.ta, cruiseS = pr.tc, T = pr.T }
            Dr.set(ctx, d, ds, "ENGAGED", "carried")
            st = "ENGAGED"
        elseif st == "BUBBLE_STABLE" then
            return
        end
        if st == "ENGAGED" then
            local ride = ds.ride
            local x0 = ride.xDone or 0   -- the distance already counted (a skipped frame never loses path)
            ride.t = ride.t + dt
            local x = M.x(ride.pr, ride.t)
            -- stability: time and the tidal field the wall crosses (sampled twice a second)
            if not ds.tidalAt or math.abs(s.utc - ds.tidalAt) >= 0.5 then
                ds.tidalAt = s.utc
                local g = Fr.accel(s, s.utc)
                ds.tidal = V.len(g) / P(d, "tidalRef")
            end
            ds.stab = math.max(0, (ds.stab or 1) - P(d, "decayPerS") * (1 + (ds.tidal or 0)) * dt)
            local apos = A.offset(Dr.fromTable(ride.O), V.scale(ride.dir, x))
            Fr.place(s, apos, ride.v0, s.utc)
            s.rot, s.omega = Dr.cpR(ride.rot), { 0, 0, 0 }
            if not ds.frameAt or math.abs(s.utc - ds.frameAt) >= 0.25 then
                ds.frameAt = s.utc
                local sw = Fr.update(s, s.utc)
                if sw then s.frameSwitched = { to = sw, utc = s.utc } end
            end
            local dm = math.max(0, x - x0)
            ride.xDone = x
            ds.act.pathM = x
            local reason
            if ride.t >= ride.pr.T then reason = "solution_complete"
            elseif ds.stab < P(d, "failBelow") then reason = "bubble_unstable"
            elseif abort then reason = "aborted" end
            Dr.stream(ctx, d, ds, { stability = ds.stab, x = x, vC = M.v(ride.pr, ride.t) / A.C, D = ride.pr.D })
            if reason then
                ds.collapseReason = reason
                ds.act.detail.stabilityEnd, ds.act.detail.xEnd = ds.stab, x
                Dr.set(ctx, d, ds, "DISENGAGING", reason)
            end
            return { touched = true, driftM = dm, driftCap = ride.pr.vs * dt * 1.01 + 1 }
        end
        if st == "DISENGAGING" then
            -- the collapse: the bubble is gone; the Machine is where it emerged, its own velocity as it went in
            if ds.t >= P(d, "collapseS") then
                local reason = ds.collapseReason or "solution_complete"
                local E = Dr.fromTable(ds.sol.emergence)
                local missM = A.distance(Dr.astro(s), E)
                Dr.finish(ctx, d, ds, reason == "solution_complete", reason, { missM = missM, emergenceErrM = ds.sol.errM })
                ds.sol, ds.ride, ds.collapseReason = nil, nil, nil
                Dr.set(ctx, d, ds, "COOLDOWN", reason)
            end
            return { touched = true }
        end
    end

    function M.lost(ctx, d, ds) ds.ride, ds.sol = nil, nil end

    function M.view(ctx, d, ds)
        local s = ctx.s
        local out = { targetId = ds.targetId, stability = ds.stab, R = P(d, "R"), sigma = P(d, "sigma") }
        if ds.sol then out.solution = { name = ds.sol.name, D = ds.sol.D, errM = ds.sol.errM } end
        local k = 0
        if ds.state == "BUBBLE_FORMING" then k = math.min(1, ds.t / P(d, "formS")) elseif ds.state == "BUBBLE_STABLE" or ds.state == "ENGAGED" then k = 1
        elseif ds.state == "DISENGAGING" then k = 1 - math.min(1, ds.t / P(d, "collapseS")) end
        out.bubble = k
        if ds.ride then
            out.dir, out.x, out.D = ds.ride.dir, M.x(ds.ride.pr, ds.ride.t), ds.ride.pr.D
            out.vC = M.v(ds.ride.pr, ds.ride.t) / A.C
            out.ride = ds.ride.t / math.max(1e-9, ds.ride.pr.T)
        elseif ds.sol then
            -- before the ride: the direction to the locked emergence point (for the lock reticle)
            local here = Dr.astro(s)
            out.dir = Dr.unit(A.delta(Dr.fromTable(ds.sol.emergence), here))
        end
        out.collapse = ds.state == "DISENGAGING" and math.min(1, ds.t / P(d, "collapseS")) or nil
        return out
    end

    return M
end)
