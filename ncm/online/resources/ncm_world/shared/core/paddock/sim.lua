-- ncm-core module: paddock.sim
-- The Paddock race simulator (doc 44 §6): FTB1 `_simulate_race_lap_by_lap` adapted to NCM's sprints.
--
-- NCM races are one-lap point-to-point sprints, so the unit is a SEGMENT (~400 m) rather than a lap. What carries
-- over from FTB1: a driver/car pace blend, noise scaled by consistency, dirty air near the car ahead, overtakes
-- GATED by a racecraft-adjusted margin (FTB's calm bubble pass, at most a few swaps a segment), incidents, and
-- classification by cumulative time. What changes:
--   * DNFs. FTB1's `(mistake + 0.5*aggression - discipline)/700` per LAP is ~3.6% a lap at stat 50: nearly every
--     driver crashed in a 50-lap race. Here the target is a per-RACE rate (~2.5% at stat 50 in the dry), turned
--     into a per-segment hazard, so race length does not change how often people crash.
--   * Weather and light, which FTB1 never used although it had `wet_weather_skill`. Conditions come from the
--     world (`world.conditions`); the sim never chooses them (L222).
--   * Event-keyed randomness: the caller passes a `vocabulary.hash` stream seeded by (race seed, race id), so the
--     same race replays identically (tested) and a result can be committed before the window opens.
local Core = NcmCore

Core.define("paddock.sim", function(C)
    local M = { version = "0.2.0", SIM_VERSION = 2 }

    -- L236 (owner: "simulated times in races are wildly too close together ... the real race showed a p1 to p12 gap
    -- of 40 seconds, a sim race showed 5.58 seconds. reality is more variable and dnfs exist"). Version 2 widens the
    -- field the way the street does: more pace spread, noisier segments, a held-up car sits a real gap behind rather
    -- than glued 0.02 s to the bumper, the grid leaves in rows, and mistakes include the big one -- into the wall,
    -- reverse out, carry on. `CHAOS` scales the incident terms by tier: street is wild, the premier is not.
    M.DNF_BASE = 0.05           -- per race, stat 50, dry, day, street chaos
    M.MISTAKE_BASE = 0.40       -- per race: errors that cost time
    M.MAJOR_SHARE = 0.25        -- of mistakes, the ones that cost 8-40 s (a wall, a spin, a reverse out)
    M.PACE_SPREAD = 0.12        -- +-12% of segment time across the 0..100 performance range
    M.HELD_UP_GAP = 0.25        -- seconds behind a car it could not pass
    M.GRID_GAP = 0.35           -- seconds per grid slot off the line
    M.CHAOS = { street = 1.0, regional = 0.85, pro = 0.7, premier = 0.6 }
    M.CAR_WEIGHT = 0.4          -- FTB phase weights: driver 0.6 / car 0.4
    M.DIRTY_AIR_GAP = 0.6       -- seconds
    M.DIRTY_AIR_COST = 0.0015   -- fraction of a segment
    M.MAX_SWAPS = 3             -- FTB's bubble passes per step

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
    local function st(a, k) return (a and a[k]) or 50 end

    function M.segments(distanceM, laps)
        local n = clamp(math.floor((tonumber(distanceM) or 3000) / 400 + 0.5), 6, 24)
        return n * math.max(1, tonumber(laps) or 1)
    end

    --- Driver pace 0..100 (race blend) and the combined performance with the car.
    function M.performance(attrs, carPerf, form)
        local drv = 0.45 * st(attrs, "pace") + 0.35 * st(attrs, "race_pace") + 0.20 * st(attrs, "consistency")
        local perf = (1 - M.CAR_WEIGHT) * drv + M.CAR_WEIGHT * (carPerf or 50)
        return perf + (form or 0) * 3
    end

    --- Per-race hazard multiplier from character (FTB's mistake/aggression/discipline terms).
    function M.riskFactor(attrs)
        local f = 1 + (st(attrs, "mistake_rate") - 50) / 50 * 0.8 + (st(attrs, "aggression") - 50) / 50 * 0.4
            - (st(attrs, "discipline") - 50) / 50 * 0.5 - (st(attrs, "vehicle_sympathy") - 50) / 50 * 0.2
        return clamp(f, 0.2, 3.0)
    end

    function M.conditionRisk(cond)
        cond = cond or {}
        local w = tonumber(cond.roadWetness) or 0
        local r = 1.8 ^ w
        if cond.light == "night" then r = r * 1.15 elseif cond.light == "dusk" then r = r * 1.07 end
        if cond.family == "hazardous" then r = r * 1.2 end
        return r
    end

    --- Convert a per-race probability into a per-segment hazard.
    function M.hazard(pRace, segments)
        pRace = clamp(pRace, 0, 0.95)
        return 1 - (1 - pRace) ^ (1 / math.max(1, segments))
    end

    --- The condition multiplier on a driver's segment time (>1 is slower).
    function M.conditionFactor(attrs, cond)
        cond = cond or {}
        local w = tonumber(cond.roadWetness) or 0
        local f = 1 + 0.08 * w * clamp(1 - 0.6 * (st(attrs, "wet_weather_skill") - 50) / 50, 0.3, 1.7)
        if cond.light == "night" then
            f = f * (1 + 0.015 * clamp(1 - (st(attrs, "night_skill") - 50) / 50, 0, 2))
        elseif cond.light == "dusk" then
            f = f * (1 + 0.007 * clamp(1 - (st(attrs, "night_skill") - 50) / 50, 0, 2))
        end
        return f
    end

    --- Simulate one race.
    ---   field  { { id, orgId, attrs, carPerf, form (-1..1), morale } } in GRID order
    ---   course { distanceM, laps }
    ---   cond   world.conditions.at(...) result (roadWetness, light, family)
    ---   rng    a vocabulary.hash stream; the only randomness
    ---   opts   { baseSec (a stat-50 car's time for the course in the dry by day), light = true skips splits/events }
    --- Returns { order, entrants, events, simVersion, segments }. Entrants carry position, grid, state, finishMs,
    --- gapMs, dnfReason and (unless light) cumulative `splits` in ms per segment.
    function M.simulate(field, course, cond, rng, opts)
        opts = opts or {}
        cond = cond or {}
        local light = opts.light == true
        local n = M.segments(course and course.distanceM, course and course.laps)
        local baseSeg = (tonumber(opts.baseSec) or 180) / n
        local wet = tonumber(cond.roadWetness) or 0
        local condRisk = M.conditionRisk(cond)
        local noiseCond = (1 + 0.5 * wet) * ((cond.family == "hazardous") and 1.3 or 1)
        local chaos = tonumber(opts.chaos) or M.CHAOS[opts.tier or "street"] or 1

        local cars = {}
        for i, e in ipairs(field) do
            local a = e.attrs or {}
            local perf = M.performance(a, e.carPerf, e.form)
            local mult = 1 - (perf - 50) / 50 * M.PACE_SPREAD
            local risk = M.riskFactor(a)
            cars[i] = {
                id = e.id, orgId = e.orgId, attrs = a, grid = i,
                seg = baseSeg * mult * M.conditionFactor(a, cond),
                sigma = (0.010 + (100 - st(a, "consistency")) / 100 * 0.030) * noiseCond * (0.6 + 0.4 * chaos),
                pDnf = M.hazard(M.DNF_BASE * chaos * risk * condRisk, n),
                pMistake = M.hazard(M.MISTAKE_BASE * chaos * risk * condRisk, n),
                t = (i - 1) * M.GRID_GAP,  -- the grid leaves in rows, not all at once
                dnf = false, splits = (not light) and {} or nil,
            }
        end
        local order = {}
        for i = 1, #cars do order[i] = i end
        local events = {}
        local function event(kind, segIdx, ids, detail)
            if not light then events[#events + 1] = { kind = kind, segment = segIdx, ids = ids, detail = detail } end
        end

        for s = 1, n do
            local late = s > (n * 2 / 3)
            -- raw segment times
            for pos = 1, #order do
                local c = cars[order[pos]]
                if not c.dnf then
                    local a = c.attrs
                    local sigma = c.sigma
                    if late then
                        sigma = sigma * clamp(1 + (st(a, "confidence_volatility") - 50) / 200 - (st(a, "pressure_handling") - 50) / 200, 0.6, 1.5)
                    end
                    local dt = c.seg * (1 + rng:normal(0, sigma))
                    if s == 1 then dt = dt + (50 - st(a, "launch")) / 50 * 0.8 * rng() end
                    if pos > 1 then
                        local ahead = cars[order[pos - 1]]
                        if not ahead.dnf and (c.t - ahead.t) < M.DIRTY_AIR_GAP then
                            dt = dt + c.seg * M.DIRTY_AIR_COST * (1 - st(a, "racecraft") / 200)
                        end
                    end
                    if rng() < c.pDnf then
                        c.dnf, c.dnfSeg = true, s
                        c.dnfReason = (rng() < 0.3) and "mechanical" or "crash"
                        event(c.dnfReason == "mechanical" and "retirement" or "crash_out", s, { c.id })
                    elseif rng() < c.pMistake then
                        -- most are a lift or a wide line; a quarter are the wall-and-reverse kind
                        local loss = (rng() < M.MAJOR_SHARE) and (8 + rng() * 32) or (1.5 + rng() * 4.5)
                        dt = dt + loss
                        event("mistake", s, { c.id }, { lossSec = math.floor(loss * 10 + 0.5) / 10 })
                    end
                    c.t = c.t + dt
                end
            end
            -- gated overtakes: start from last segment's order; a car behind takes the place ahead only when it is
            -- clearly faster AND wins the duel (FTB's calm bubble). A lost duel leaves it held up behind.
            for _ = 1, M.MAX_SWAPS do
                local swapped = false
                for pos = #order, 2, -1 do
                    local att, def = cars[order[pos]], cars[order[pos - 1]]
                    if not att.dnf and not def.dnf and att.t < def.t then
                        -- sprint-scaled: FTB's 0.35 s margin was for 50-lap races and froze a 12-segment sprint
                        local margin = math.max(0.02, 0.08 - (st(att.attrs, "overtaking") - 50) / 600)
                        local duel = clamp(0.55 + (st(att.attrs, "overtaking") - st(def.attrs, "defending")) / 150, 0.2, 0.9)
                        if (def.t - att.t) > margin and rng() < duel then
                            order[pos], order[pos - 1] = order[pos - 1], order[pos]
                            swapped = true
                            event("overtake", s, { att.id, def.id })
                            -- an aggressive pass can end in contact
                            local contact = 0.012 * (st(att.attrs, "aggression") / 50) * condRisk
                            if rng() < contact then
                                local who = (rng() < 0.5) and att or def
                                event("contact", s, { att.id, def.id })
                                if rng() < 0.25 then
                                    who.dnf, who.dnfSeg, who.dnfReason = true, s, "contact"
                                    event("crash_out", s, { who.id }, { cause = "contact", with = (who == att) and def.id or att.id })
                                else
                                    who.t = who.t + 1 + rng() * 3
                                end
                            end
                        else
                            att.t = def.t + M.HELD_UP_GAP      -- held up: a real gap behind, not glued to the bumper
                        end
                    end
                end
                if not swapped then break end
            end
            if not light then
                for _, c in ipairs(cars) do
                    if not c.dnf then c.splits[s] = math.floor(c.t * 1000 + 0.5) end
                end
            end
        end

        -- classification: finishers by cumulative time within the gated order, then DNFs by distance covered
        local finishers, dnfs = {}, {}
        for _, idx in ipairs(order) do
            local c = cars[idx]
            if c.dnf then dnfs[#dnfs + 1] = c else finishers[#finishers + 1] = c end
        end
        table.sort(dnfs, function(a, b) if a.dnfSeg ~= b.dnfSeg then return a.dnfSeg > b.dnfSeg end return a.grid < b.grid end)
        local out, ids = {}, {}
        local leader = finishers[1] and finishers[1].t or 0
        for i, c in ipairs(finishers) do
            -- a finisher can never be classified ahead of a car it finished behind in time: enforce monotonic times
            if i > 1 and c.t <= finishers[i - 1].t then c.t = finishers[i - 1].t + 0.05 end
            out[#out + 1] = { id = c.id, orgId = c.orgId, position = i, grid = c.grid, state = "finished",
                finishMs = math.floor(c.t * 1000 + 0.5), gapMs = math.floor((c.t - leader) * 1000 + 0.5), splits = c.splits }
            ids[#ids + 1] = c.id
        end
        for _, c in ipairs(dnfs) do
            out[#out + 1] = { id = c.id, orgId = c.orgId, position = #out + 1, grid = c.grid, state = "dnf",
                dnfReason = c.dnfReason, dnfSegment = c.dnfSeg, splits = c.splits }
            ids[#ids + 1] = c.id
        end
        return { order = ids, entrants = out, events = events, simVersion = M.SIM_VERSION, segments = n }
    end

    --- A qualifying order (Pro/Premier): one flying run on quali pace with noise. Returns ids fastest first.
    function M.qualify(field, rng)
        local runs = {}
        for i, e in ipairs(field) do
            local a = e.attrs or {}
            local q = 0.7 * st(a, "quali_pace") + 0.3 * st(a, "pace")
            local perf = (1 - M.CAR_WEIGHT) * q + M.CAR_WEIGHT * (e.carPerf or 50)
            runs[i] = { e = e, score = perf + rng:normal(0, (100 - st(a, "consistency")) / 20) }
        end
        table.sort(runs, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.e.id < b.e.id end)
        local out = {}
        for i, r in ipairs(runs) do out[i] = r.e end
        return out
    end

    return M
end)
