-- ncm-core module: space.pilot
--
-- An NPC racing in Snowglobe (L322; doc 54 §N). MACHINE + DRIVER + RACE -> a desired THRUST ACCELERATION (world
-- frame); `engineering.allocate` turns it into throttles through the machine's real mounts and
-- `engineering.dynamics` decides what actually happens. The planner reasons only about the machine it has: its
-- acceleration, its delta-v left, its heat -- never a magic envelope.
--
-- Who is flying shows in the choices, through `npc.behavior` (risk, margins, provocation, clutch) and
-- `npc.competency` (reaction, execution noise, how late traffic is read):
--   SPRINT    reaction at the lights (launch_reaction, clutch), then everything along the lane; lane keeping; heat
--             pacing on long classes by risk. Deliberately simple -- the sport is.
--   FIREBALL  a preferred radius in the shell (an aggressive driver hugs the inner wall: shorter, contested), a target
--             speed bought from the propellant budget for the distance left (faster than circular costs continuous
--             inward thrust; heat throttles it), radius and speed held by a damped controller, and TRAFFIC: for every
--             rival, relative position and velocity, time and distance of closest approach; inside my margin I give
--             way (cautious), hold my line (aggressive) or escalate (provoked); closing on a rival ahead, I attack.
-- Pure; randomness arrives as a per-step `vocabulary.hash` stream from the caller (resumable).
local Core = NcmCore

Core.define("space.pilot", function(C)
    local M = { version = "0.1.0" }

    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function scale(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function unit(a) local l = len(a); return l > 1e-12 and scale(a, 1 / l) or { 0, 0, 0 } end
    M.vec = { add = add, sub = sub, scale = scale, dot = dot, cross = cross, len = len, unit = unit }

    M.BASE_MARGIN_M = 40         -- separation a neutral driver keeps in Fireball traffic
    M.HORIZON_S = 6              -- how far ahead closest approaches are considered
    M.SPEED_GRID = { 20, 400, 5 }

    --- Reaction at the lights (s): a person's reflex (launch_reaction) and nerve (clutch), plus a little luck.
    function M.reaction(comp, prof, rng)
        local skill = (comp.launch_reaction or 8) / 100
        return 0.12 + (1 - skill) * 0.45 + (1 - prof.clutch) * 0.08 + rng() * 0.06
    end

    --- How often the plan is renewed (s): a pilot who reads 3D traffic well reacts sooner.
    function M.decisionPeriod(comp)
        return 0.15 + (1 - (comp.traffic3d or 8) / 100) * 0.6
    end

    local function noise(a, comp, eff, rng)
        local m = len(a)
        if m <= 0 then return a end
        local sd = m * 0.12 * (1 - (comp.piloting or 8) / 100) * eff.noiseScale
        return add(a, { rng:normal(0, sd), rng:normal(0, sd), rng:normal(0, sd) })
    end

    --- SPRINT. ctx = { t, startT, reactS, self = {pos, vel, aMax, heatFrac}, frame, laneX, g, comp, eff, rng }.
    function M.sprint(ctx)
        local s = ctx.self
        if ctx.t < ctx.startT + ctx.reactS then
            -- on the grid: hold position (against gravity if airborne; a grounded car just sits)
            return ctx.grounded and { 0, 0, 0 } or scale(ctx.g, -1)
        end
        local f = ctx.frame
        local lx = dot(sub(s.pos, f.origin), f.x)
        local want = scale(f.y, s.aMax * 4)                                     -- everything along the lane
        want = add(want, scale(f.x, -(lx - ctx.laneX) * 0.8 - dot(s.vel, f.x) * 1.2))  -- stay in lane
        local gperp = sub(ctx.g, scale(f.y, dot(ctx.g, f.y)))
        want = sub(want, gperp)                                                 -- hold the line against gravity
        local hot = 0.55 + 0.4 * ctx.eff.risk
        if s.heatFrac > hot then want = scale(want, 0.5) end                    -- a cautious driver saves the engine
        return noise(want, ctx.comp, ctx.eff, ctx.rng)
    end

    --- The fastest sustainable Fireball speed for the distance left, from the machine's budget (m/s).
    function M.fireballSpeed(rt, gr, aMax, dvLeft, remainM, refR, risk)
        local best, minNeedS, minNeed = nil, nil, math.huge
        local lo, hi, step = M.SPEED_GRID[1], M.SPEED_GRID[2], M.SPEED_GRID[3]
        local budget = dvLeft * (0.70 + 0.25 * risk)
        for s = lo, hi, step do
            local need = math.abs(s * s / rt - gr)                             -- radial thrust to keep the circle
            local timeS = remainM * (rt / refR) / s
            if need < minNeed then minNeed, minNeedS = need, s end
            if need <= 0.85 * aMax and need * timeS + s <= budget then best = s end
        end
        return best or minNeedS
    end

    --- FIREBALL. ctx = { t, self = {pos, vel (relative to the centre's motion), aMax, dvLeft, heatFrac, creditM, axis},
    --- rules, centre, g (gravity RELATIVE to the centre: Earth's pull for an Earth venue, the tidal residue around a
    --- free-falling station), comp, eff, prof, others = { {id, pos, vel, creditM} }, rng }.
    --- Returns the thrust acceleration, a note of what it did, and its targets.
    function M.fireball(ctx)
        local s, rules = ctx.self, ctx.rules
        local r = sub(s.pos, ctx.centre)
        local R = len(r)
        local rh = scale(r, 1 / R)
        local vr = dot(s.vel, rh)
        local vtv = sub(s.vel, scale(rh, vr))
        local vt = len(vtv)
        local th = vt > 2 and scale(vtv, 1 / vt) or unit(cross(s.axis, rh))   -- start along my own plane
        -- where and how fast: the inner wall is shorter and contested; the budget sets the speed
        local risk = ctx.eff.risk
        local rt = rules.inner + (rules.outer - rules.inner) * (0.12 + 0.6 * (1 - risk))
        local gr = len(ctx.g) * (R * R) / (rt * rt)
        local speed = M.fireballSpeed(rt, gr, s.aMax, s.dvLeft, rules.distanceM - s.creditM, rules.refRadius, risk)
        if s.heatFrac > 0.75 + 0.2 * risk then speed = speed * 0.85 end
        local note = "line"
        -- traffic
        local margin = M.BASE_MARGIN_M * ctx.eff.marginScale
        local avoid = { 0, 0, 0 }
        for _, o in ipairs(ctx.others) do
            local rel, vrel = sub(o.pos, s.pos), sub(o.vel, s.vel)
            local d2 = dot(vrel, vrel)
            local tca = d2 > 1e-6 and -dot(rel, vrel) / d2 or 0
            if tca > 0 and tca < M.HORIZON_S then
                local missV = add(rel, scale(vrel, tca))
                local miss = len(missV)
                if miss < margin then
                    local away = unit(scale(missV, -1))
                    if len(away) == 0 then away = unit(cross(rh, th)) end
                    local give = (1 - risk) * 0.6 + 0.1
                    if risk > 0.7 and o.creditM > s.creditM then give = 0.05; note = "holds the line" else note = "gives way" end
                    avoid = add(avoid, scale(away, s.aMax * give * (1 - miss / margin)))
                end
            end
            -- attack: a rival just ahead and within reach -> spend more
            local ahead = o.creditM - s.creditM
            if ahead > 0 and ahead < 300 and len(rel) < 400 then
                speed = speed * (1 + 0.10 * risk)
                if note == "line" then note = "attacks" end
            end
        end
        -- the damped controller: radius and speed, plus the centripetal term the circle needs
        local radial = -vt * vt / R + 0.02 * (rt - R) - 0.4 * vr
        local aTot = add(scale(rh, radial), scale(th, 0.5 * (speed - vt)))
        local thrust = add(sub(aTot, ctx.g), avoid)
        return noise(thrust, ctx.comp, ctx.eff, ctx.rng), note, { rt = rt, speed = speed }
    end

    return M
end)
