-- ncm-core module: space.racesim
--
-- NPC racing in Snowglobe (L321; doc 54 §G). Not a new minigame: a Snowglobe race is a `paddock.sim` race (seeded,
-- incidents, DNFs, replayable) held in a `paddock.racestate` model (every car always somewhere; physical promotion
-- through anchors; per-stretch provenance). What is new is where the CAR term comes from: the machine's physics on
-- this course, not a rating.
--
--   station_ring (vacuum)    pace is bounded by DELTA-V: every turn of angle theta at speed v costs 2 v sin(theta/2),
--                            so a machine with little propellant must fly slowly; acceleration (thrust / mass) sets
--                            how long the turns take; fewer than six controlled axes means rotating the main engine
--                            to every new direction. A machine with no reaction push or no attitude control cannot
--                            enter -- it is refused with its reason, not given a bad time.
--   sky_ring (atmospheric)   at the venue's altitude the air is thin: thrust is re-derived at that density. The
--                            machine must hover (thrust-to-weight > 1 there); spare thrust is lateral acceleration
--                            for the turns; propellers need the battery to last the race.
--
-- The estimated lap time becomes `carPerf` on paddock.sim's scale EXACTLY (a machine 10 % quicker than the field's
-- median gets the sim's 10 % pace), heat and structural overload become hazard, and the result keeps its provenance:
-- `mode` = simulated | mixed | physical per car, from the racestate's physical stretches.
local Core = NcmCore

Core.define("space.racesim", function(C)
    local M = { version = "0.2.0" }
    local Sim = C.get("paddock.sim")
    local RS = C.get("paddock.racestate")
    local Mach = C.get("engineering.machine")
    local Sys = C.get("engineering.systems")
    local Course = C.get("space.course")
    local U = C.get("space.universe")
    local Pilot = C.get("space.pilot")

    M.G = 9.81
    M.DV_USABLE = 0.8          -- of delta-v a pilot will spend racing (the rest is getting home)
    M.VMAX = 150               -- m/s: gates 30 m wide stop being hittable above this (a sporting, not physical, cap)
    M.AXIS_PENALTY = 0.08      -- lap time per missing controlled axis

    local function zThrust(m, rho, pushes)
        local F = 0
        for _, d in ipairs(m.devices) do
            if d.kind ~= "ground_ram" and (not pushes or pushes[d.push]) then F = F + d.dir[3] * Sys.thrustAt(d.perf, rho, 1) end
        end
        return F
    end

    local function turnFactor(course)
        local K = 0
        for _, l in ipairs(Course.legs(course)) do K = K + 2 * math.sin(l.turnRad / 2) end
        return K
    end

    --- Estimate one machine on one venue. Returns { eligible, reason?, lapSec, raceSec, vMs, risk, burnSec }.
    function M.estimate(model, venue)
        local cap = Mach.capability(model, { g = M.G })
        local course = venue.course
        local laps = course and course.laps or 1
        local K = course and turnFactor(course) or 0
        local mass = model.wetMassKg
        local out = { cap = cap, risk = 1 }
        if venue.kind == "station_ring" then
            if cap.twrVacuum <= 0 then out.eligible, out.reason = false, "no reaction push: nothing to maneuver with in vacuum"; return out end
            if cap.vacuumAxes < 3 then out.eligible, out.reason = false, ("attitude: %d of 6 axes"):format(cap.vacuumAxes); return out end
            local a = zThrust(model, 0, { reaction = true }) / mass
            local v = math.min(M.VMAX, M.DV_USABLE * cap.deltaVms / (1 + laps * K))
            if v < 5 then out.eligible, out.reason = false, ("delta-v: %.0f m/s cannot fly %d laps of this ring"):format(cap.deltaVms, laps); return out end
            local raceSec = course.lengthM / v + (laps * K + 1) * v / a
            raceSec = raceSec * (1 + M.AXIS_PENALTY * (6 - cap.vacuumAxes))
            out.burnSec = (laps * K + 1) * v / a
            if out.burnSec > cap.thermalLimitVacuumS then out.risk = out.risk * 1.8 end
            out.vMs, out.raceSec = v, raceSec
        elseif venue.kind == "sky_ring" then
            local rho = U.densityAt(venue.altitudeM or 0)
            local twr = zThrust(model, rho) / (mass * M.G)
            if twr <= 1.05 then out.eligible, out.reason = false, ("thrust-to-weight %.2f at %.0f m: cannot hold altitude"):format(twr, venue.altitudeM or 0); return out end
            local v = math.min(M.VMAX, 25 + 40 * (twr - 1))
            local aLat = M.G * math.sqrt(twr * twr - 1)
            local raceSec = course.lengthM / v + laps * K * v / aLat
            -- propellers run on the battery; reaction engines on propellant
            local powerW = 0
            for _, d in ipairs(model.devices) do if d.kind == "propeller" then powerW = powerW + (d.perf.powerW or 0) end end
            if powerW > 0 and model.energyJ / powerW < raceSec / 0.8 then
                out.eligible, out.reason = false, ("energy: %.0f s of hover power for a %.0f s race"):format(model.energyJ / powerW, raceSec)
                return out
            end
            local flow = 0
            for _, d in ipairs(model.devices) do if d.kind == "reaction_engine" then flow = flow + Sys.massFlow(d.perf) end end
            local prop = 0
            for _, t in ipairs(model.tanks) do prop = prop + t.kg end
            if powerW == 0 and flow > 0 and prop / (flow / twr) < raceSec then
                out.eligible, out.reason = false, "propellant: cannot hover for the race on reaction thrust"
                return out
            end
            out.vMs, out.raceSec, out.twr = v, raceSec, twr
        elseif venue.kind == "sprint" then
            -- start plane -> finish plane: thrust along the lane against gravity (a vertical sprint) or in free fall
            -- (alongside a station); burn, then coast; the finish is reached or it is not
            local vertical = venue.style == "vertical"
            -- a vertical sprint climbs out of the thick air: judge the thrust at mid-height above the city patch
            local rho = vertical and U.densityAt(((venue.spot and venue.spot[3]) or 0) + venue.distanceM / 2) or 0
            local F = zThrust(model, rho)
            local net = F / mass - (vertical and M.G or 0)
            if net <= 0.3 then out.eligible, out.reason = false, ("thrust-to-weight %.2f: cannot leave the grid"):format(F / (mass * M.G)); return out end
            local flow, prop, power = 0, 0, 0
            for _, d in ipairs(model.devices) do
                if d.kind == "reaction_engine" then flow = flow + Sys.massFlow(d.perf) end
                if d.kind == "propeller" then power = power + (d.perf.powerW or 0) end
            end
            for _, t in ipairs(model.tanks) do prop = prop + t.kg end
            local tb = flow > 0 and prop / flow or (power > 0 and model.energyJ / power or 0)
            local D = venue.distanceM
            local d1 = net * tb * tb / 2
            local raceSec
            if d1 >= D then
                raceSec = math.sqrt(2 * D / net)
            else
                local v = net * tb
                local rest = D - d1
                if vertical then
                    if v * v / (2 * M.G) < rest then out.eligible, out.reason = false, ("propellant: burns out %.0f m short of the line"):format(rest - v * v / (2 * M.G)); return out end
                    raceSec = tb + (v - math.sqrt(v * v - 2 * M.G * rest)) / M.G
                else
                    raceSec = tb + rest / v
                end
            end
            out.raceSec = raceSec + 0.3
            out.twr = F / (mass * M.G)
        elseif venue.kind == "fireball" then
            -- round the centre: the speed the machine can sustain for the distance on its delta-v (faster than circular
            -- costs continuous inward thrust), and it must hold station on the grid before the lights
            if cap.twrVacuum <= 0 then out.eligible, out.reason = false, "no reaction push: cannot fly a Fireball"; return out end
            if cap.vacuumAxes < 3 then out.eligible, out.reason = false, ("attitude: %d of 6 axes"):format(cap.vacuumAxes); return out end
            local aMax = zThrust(model, 0, { reaction = true }) / mass
            local rt = (venue.inner + venue.outer) / 2
            local gr = 0
            if venue.centre == "earth" then
                gr = U.G * U.BODIES.earth.mass / (rt * rt)
                local gGrid = U.G * U.BODIES.earth.mass / (U.BODIES.earth.radius + venue.gridAltM) ^ 2
                if aMax < gGrid * 1.05 then out.eligible, out.reason = false, ("thrust %.2f m/s2 cannot hold the grid against %.2f"):format(aMax, gGrid); return out end
            end
            local refR = (venue.inner + venue.outer) / 2
            local speed = Pilot.fireballSpeed(rt, gr, aMax, cap.deltaVms, venue.distanceM, refR, 0.5)
            local need = math.abs(speed * speed / rt - gr)
            local timeS = venue.distanceM / speed
            if need > aMax or need * timeS + speed > cap.deltaVms then
                out.eligible, out.reason = false, ("delta-v: %.0f m/s cannot sustain %.0f km round"):format(cap.deltaVms, venue.distanceM / 1000)
                return out
            end
            out.raceSec, out.vMs = timeS + speed / aMax, speed
            if cap.heatKw * (need / aMax) > cap.rejectionVacuumKw and cap.thermalLimitVacuumS < timeS then out.risk = out.risk * 1.8 end
        else
            out.eligible, out.reason = false, "unknown venue kind " .. tostring(venue.kind)
            return out
        end
        if cap.firstFailure == "structure" then out.risk = out.risk * 2.5 end
        out.eligible = true
        out.lapSec = out.raceSec / math.max(1, laps)
        return out
    end

    --- carPerf on paddock.sim's scale for a race time against the field's median, so the sim reproduces the ratio.
    function M.carPerf(raceSec, medianSec)
        local k = 50 / Sim.PACE_SPREAD / Sim.CAR_WEIGHT
        return math.max(-150, math.min(250, 50 + (medianSec / raceSec - 1) * k))
    end

    local function median(xs)
        local t = {}
        for i, x in ipairs(xs) do t[i] = x end
        table.sort(t)
        if #t == 0 then return nil end
        if #t % 2 == 1 then return t[(#t + 1) / 2] end
        return (t[#t / 2] + t[#t / 2 + 1]) / 2
    end

    --- Run a race. entrants = { { id, orgId, pilot = {attrs}, machine (or model) = <assembled> } } in grid order.
    --- Returns { venueId, field, refused, sim, model, segments, baseSec }.
    function M.race(venue, entrants, rng, opts)
        opts = opts or {}
        local field, refused, times = {}, {}, {}
        for _, e in ipairs(entrants) do
            local est = M.estimate(e.machine or e.model, venue)
            if est.eligible then
                field[#field + 1] = { id = e.id, orgId = e.orgId, attrs = e.pilot and e.pilot.attrs or {}, est = est,
                                      lureRisk = est.risk, form = e.form }
                times[#times + 1] = est.raceSec
            else
                refused[#refused + 1] = { id = e.id, orgId = e.orgId, reason = est.reason }
            end
        end
        local out = { venueId = venue.id, field = field, refused = refused }
        if #field == 0 then return out end
        local base = median(times)
        for _, f in ipairs(field) do f.carPerf = M.carPerf(f.est.raceSec, base) end
        local length = venue.course and venue.course.lengthM or venue.distanceM
        local course = { distanceM = length, laps = 1 }
        local sim = Sim.simulate(field, course, opts.cond or { light = "night" }, rng, { baseSec = base, tier = opts.tier or "pro" })
        local L = length
        local model = RS.new({ points = { { x = 0, y = 0 }, { x = L, y = 0 } }, lengthM = L }, sim.entrants, sim.segments)
        out.sim, out.model, out.segments, out.baseSec = sim, model, sim.segments, base
        return out
    end

    --- The classification with provenance: each row carries `mode` (simulated / mixed / physical) and the race's
    --- simulation version; physical stretches come from `paddock.racestate.markPhysical` by the host.
    function M.result(raceOut, cutoffMs)
        if not raceOut.model then return {} end
        local rows = RS.result(raceOut.model, cutoffMs)
        for _, r in ipairs(rows) do
            local share = r.physicalShare or 0
            r.mode = share >= 0.999 and "physical" or (share > 0 and "mixed" or "simulated")
            r.simVersion = raceOut.sim.simVersion
        end
        return rows
    end

    --- Where along a course (local frame) a car is at distance d (metres from the start gate, laps unrolled).
    function M.pointAt(course, d)
        local legs = Course.legs(course)
        local lap = course.lapM or Course.lapLength(course)
        local x = d % lap
        local g = course.gates
        for i, l in ipairs(legs) do
            if x <= l.lengthM then
                local a, b = g[i].centre, g[i % #g + 1].centre
                local f = l.lengthM > 0 and x / l.lengthM or 0
                return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
            end
            x = x - l.lengthM
        end
        return g[1].centre
    end

    return M
end)
