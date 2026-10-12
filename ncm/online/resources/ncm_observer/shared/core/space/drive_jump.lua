-- ncm-core module: space.drive.jump -- XLB-JD1, discrete translation (doc 58 §5.5).
--
-- FICTION, SAID SO: there is no physics of jumping. NCM's smallest extension: the drive accumulates a charge, then the
-- Machine STOPS BEING at one coordinate and IS at another -- it never occupies the space between, takes no time to
-- cross it, and nothing on the way can touch it. What it keeps: its attitude (in the sky's own axes) and its motion
-- RELATIVE TO THE BODY IT WAS ORBITING / FALLING TOWARD, re-expressed relative to the dominant body at the destination
-- (a Machine coasting at 18 km/s away from the Earth arrives coasting at 18 km/s relative to Proxima's system). Without
-- that rule a jump would hand over the Sun's 30 km/s orbital velocity to another star's neighbourhood; with it, the
-- arrival is reproducible.
--
-- Character: a destination is required and locked; the charge time grows with distance (chargeS0 + chargePerLyS per
-- ly); range is finite and configurable (maxRangeLy -- the engineering numbers live on the design, not here); arrival
-- is short of the target by a standoff and off it by a seeded targeting error (errorFrac x distance); then a cooldown.
-- States: OFF -> DESTINATION_LOCKED -> CHARGING -> ENGAGED (the discontinuity has happened: the arrival moment, held
-- briefly so the screen can show it) -> COOLDOWN -> OFF.
local Core = NcmCore

Core.define("space.drive.jump", function(C)
    local M = {}
    local Dr = C.get("space.drives")
    local A = C.get("space.astro")
    local V = A.vec
    local Fr

    local DEF = { maxRangeLy = 10, chargeS0 = 10, chargePerLyS = 1, errorFrac = 1e-6, cooldownS = 60, arriveS = 1.2,
        baseCost = 800, perLyCost = 300, abortHoldS = 1.0, standoffStarAU = 2, standoffBodyRadii = 10 }
    local function P(d, k) local v = d.perf[k]; if v == nil then v = DEF[k] end; return v end

    local function solve(ctx, d, ds)
        local s = ctx.s
        local rec, tp = Dr.target(ds.targetId, s, s.utc)
        if not rec then return nil, "no target" end
        local here = Dr.astro(s)
        local toT = A.delta(tp, here)
        local dist = V.len(toT)
        if dist <= 0 then return nil, "already there" end
        local dir = V.scale(toT, 1 / dist)
        local stand = Dr.standoff(rec, d.perf)
        local D = dist - stand
        if D <= 0 then return nil, ("already inside %s's standoff"):format(tostring(rec.name or rec.id)) end
        if D > P(d, "maxRangeLy") * A.LY then return nil, ("%.3g ly is beyond the %.3g ly range"):format(D / A.LY, P(d, "maxRangeLy")) end
        return { targetId = ds.targetId, name = rec.name or rec.id, D = D, dir = dir, standoffM = stand,
                 chargeS = P(d, "chargeS0") + P(d, "chargePerLyS") * D / A.LY, cost = P(d, "baseCost") + P(d, "perLyCost") * D / A.LY }
    end

    -- the jump itself: where, how fast, and through which frames
    local function jump(ctx, d, ds)
        local s = ctx.s
        local sol = ds.sol
        local rec, tp = Dr.target(sol.targetId, s, s.utc)          -- where the target is NOW (a jump takes no time)
        local here, vel = Dr.astro(s)
        local toT = A.delta(tp, here)
        local dist = V.len(toT)
        local dir = V.scale(toT, 1 / dist)
        local D = dist - sol.standoffM
        if D > P(d, "maxRangeLy") * A.LY * 1.001 then return nil, "out_of_range_at_jump" end
        local r = Dr.rng(d.componentId .. ":" .. ds.n .. ":" .. sol.targetId)
        local err = V.scale(Dr.randomUnit(r), math.min(D * P(d, "errorFrac") * (0.25 + r()), 0.5 * sol.standoffM))
        local dest = A.offset(A.offset(here, V.scale(dir, D)), err)
        local domA, vA = Dr.dominant(here, s.utc)
        local domB, vB = Dr.dominant(dest, s.utc)
        local vnew = V.add(V.sub(vel, vA), vB)
        local key = Fr.translate(s, dest, vnew, s.utc)
        return { from = Dr.posTable(here), to = Dr.posTable(dest), vector = V.scale(dir, D), D = D, errM = V.len(err),
                 domFrom = domA and domA.id, domTo = domB and domB.id, vRel = V.len(V.sub(vel, vA)), frame = key }
    end

    function M.step(ctx, d, ds, c, dt)
        Fr = Fr or C.get("space.frames")
        local s = ctx.s
        if c.abort and c.abort > 0 then ds.holdT = (ds.holdT or 0) + dt else ds.holdT = 0 end
        local abort = (ds.holdT or 0) >= P(d, "abortHoldS")
        local st = ds.state
        if (st == "OFF" or st == "DESTINATION_LOCKED") and (c.next or c.prev) then
            Dr.select(ds, d, c, Dr.inRange(s, P(d, "maxRangeLy") * A.LY + 4 * A.AU))
            if st == "DESTINATION_LOCKED" then ds.sol = nil; Dr.set(ctx, d, ds, "OFF", "target changed") end
            st = ds.state
        end
        if st == "OFF" then
            if c.engage then
                local sol, why = solve(ctx, d, ds)
                if not sol then ds.msg = "no jump solution: " .. tostring(why); Dr.set(ctx, d, ds, "FAILED", "no_solution"); return end
                if (ds.charge or 0) < sol.cost then ds.msg = ("needs %.0f charge, has %.0f"):format(sol.cost, ds.charge or 0); Dr.set(ctx, d, ds, "FAILED", "no_charge"); return end
                ds.sol, ds.msg = sol, ("locked: %s, %.4g ly, charge %.0f s"):format(sol.name, sol.D / A.LY, sol.chargeS)
                Dr.set(ctx, d, ds, "DESTINATION_LOCKED", "navigation lock")
            end
            return
        end
        if st == "DESTINATION_LOCKED" then
            if abort then ds.sol = nil; Dr.set(ctx, d, ds, "OFF", "unlocked"); return end
            if c.engage then
                Dr.begin(ctx, d, ds, { target = ds.sol.targetId })
                Dr.spend(ds, ds.sol.cost)
                ds.act.detail.solution = { name = ds.sol.name, D = ds.sol.D, chargeS = ds.sol.chargeS, standoffM = ds.sol.standoffM }
                Dr.set(ctx, d, ds, "CHARGING", "charging")
            end
            return
        end
        if st == "CHARGING" then
            if abort then
                Dr.finish(ctx, d, ds, false, "aborted_in_charge")
                ds.sol = nil
                Dr.set(ctx, d, ds, "COOLDOWN", "aborted")
                return
            end
            if ds.t >= ds.sol.chargeS then
                local res, why = jump(ctx, d, ds)
                if not res then
                    Dr.finish(ctx, d, ds, false, why)
                    ds.sol = nil
                    Dr.set(ctx, d, ds, "FAILED", why)
                    return
                end
                ds.act.detail.jump = res
                ds.arrived = { D = res.D, errM = res.errM }
                Dr.set(ctx, d, ds, "ENGAGED", "jumped")
                return { touched = true, jumpM = A.distance(Dr.fromTable(res.from), Dr.fromTable(res.to)) }
            end
            return
        end
        if st == "ENGAGED" then
            if ds.t >= P(d, "arriveS") then
                Dr.finish(ctx, d, ds, true, "arrived")
                ds.sol = nil
                Dr.set(ctx, d, ds, "COOLDOWN", "arrived")
            end
            return { touched = true }
        end
    end

    function M.lost(ctx, d, ds) ds.sol = nil end

    function M.view(ctx, d, ds)
        local s = ctx.s
        local out = { targetId = ds.targetId, maxRangeLy = P(d, "maxRangeLy") }
        if ds.sol then
            out.solution = { name = ds.sol.name, D = ds.sol.D, chargeS = ds.sol.chargeS }
            local rec, tp = Dr.target(ds.sol.targetId, s, s.utc)
            if rec then out.dir = Dr.unit(A.delta(tp, Dr.astro(s))) end
        end
        if ds.state == "CHARGING" and ds.sol then out.charge = math.min(1, ds.t / ds.sol.chargeS) end
        if ds.state == "ENGAGED" then out.arrive = math.min(1, ds.t / P(d, "arriveS")) end
        return out
    end

    return M
end)
