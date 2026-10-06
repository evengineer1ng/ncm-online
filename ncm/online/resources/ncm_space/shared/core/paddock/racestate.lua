-- ncm-core module: paddock.racestate
-- The continuous race: where every car of a Paddock race is, at every moment, whether or not anyone is watching
-- (L228; doc 44 §12). The foundation for the physical bubble (cars materialise from this state near a player and hand
-- back to it when they leave), kinematic playback, and the F6 broadcast.
--
-- A car's timeline comes from its own sim run: `paddock.sim` gives cumulative split times per segment, and segment k
-- ends at k/segments of the route's line. Between knots the car moves linearly in time. A DNF stops halfway into the
-- segment it retired in.
--
-- ANCHORS are how the physical world writes back. When a car that was driven physically leaves a player's range, the
-- host reports where it really was (distance along the line) and when. From then on the car continues from that point
-- at ITS OWN sim pace for the rest of the line: the sim's time from that distance to the finish is kept, only moved to
-- start at the observed moment. A crash that cost 20 s is still 20 s down at the flag; a car that drove faster than its
-- sim keeps the gain. Stretches the car drove physically are recorded, so the result can say which parts were real.
--
-- TRUTH RULES (owner, 2026-10-02: "audit the race lifecycle for truth about who is winning"):
--   * A car driven physically in someone's bubble is LIVE: where it is comes only from the street (`observe`), and it
--     finishes only by crossing the line physically. The model never finishes a car that is still on the road in a
--     player's mirror.
--   * A car handed back continues at the pace it was MEASURED driving (`anchor` rate), not at its sim pace: a sim
--     faster than the street made every hand-back a teleport up the order.
--   * Penalties are part of the RESULT: every car carries `penaltyMs`, applied at classification. The running order
--     is the race as it stands on the road, WITHOUT penalties (owner, 2026-10-02: "reflect the current race state
--     without penalties, then at the end ... a visible shuffle of order based on penalties").
--   * The flag: once the leader crosses, the rest have a window (`paddock.mixed.finishWindowSec`); `result(model,
--     cutoff)` classifies only the cars home by the flag, the others by how far they got.
--
-- Pure: no host calls. Times are ms since the race's go; distances are metres along the line from the start line.
local Core = NcmCore

Core.define("paddock.racestate", function(C)
    local M = { version = "0.2.0" }

    local function dist(a, b)
        local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
        return math.sqrt(dx * dx + dy * dy)
    end

    -- spawn yaw along the line: NCM single player's rule (heading + 90), shared with paddock.live (L232)
    local function yawOf(dx, dy) return C.get("paddock.live").yawFromDir(dx, dy) end

    --- Build the model. path = { points, lengthM } (paddock.live.path); entrants = the sim's entrant list (id, orgId,
    --- grid, state, splits, dnfSegment); segments = the sim's segment count.
    function M.new(path, entrants, segments)
        local L = path.lengthM or 0
        if L <= 0 then
            for i = 2, #path.points do L = L + dist(path.points[i - 1], path.points[i]) end
        end
        local cum = { 0 }
        for i = 2, #path.points do cum[i] = cum[i - 1] + dist(path.points[i - 1], path.points[i]) end
        local scale = (cum[#cum] > 0) and (L / cum[#cum]) or 1
        for i = 1, #cum do cum[i] = cum[i] * scale end
        local model = { path = path, lengthM = L, cum = cum, segments = segments, cars = {}, order = {} }
        segments = math.max(1, segments or 1)
        for _, e in ipairs(entrants) do
            local knots = { { d = 0, t = 0 } }
            local splits = e.splits or {}
            local last = 0
            for k = 1, segments do
                local t = splits[k]
                if not t then break end
                if t > last then knots[#knots + 1] = { d = L * k / segments, t = t }; last = t end
            end
            local stopAt
            if e.state == "dnf" or #knots <= segments then
                -- a retirement: the car stops halfway into the segment after its last split
                local k = #knots - 1
                local segT = (k >= 1) and (knots[#knots].t / k) or 30000
                if #knots < segments + 1 then
                    stopAt = { d = math.min(L, knots[#knots].d + L / segments * 0.5), t = knots[#knots].t + segT * 0.5 }
                    knots[#knots + 1] = stopAt
                end
            end
            local car = { id = e.id, orgId = e.orgId, grid = e.grid, knots = knots, dnf = stopAt ~= nil, anchors = {}, physical = {},
                penaltyMs = 0 }
            model.cars[e.id] = car
            model.order[#model.order + 1] = e.id
        end
        return model
    end

    -- original timeline: distance at time t, and time at distance d (knots are monotonic in both)
    local function origD(car, t)
        local kn = car.knots
        if t <= 0 then return 0 end
        for i = 2, #kn do
            if t <= kn[i].t then
                local a, b = kn[i - 1], kn[i]
                return a.d + (b.d - a.d) * (t - a.t) / (b.t - a.t)
            end
        end
        return kn[#kn].d
    end
    local function origT(car, d)
        local kn = car.knots
        if d <= 0 then return 0 end
        for i = 2, #kn do
            if d <= kn[i].d then
                local a, b = kn[i - 1], kn[i]
                if b.d == a.d then return a.t end
                return a.t + (b.t - a.t) * (d - a.d) / (b.d - a.d)
            end
        end
        return nil                                   -- beyond where this car's run ends (a DNF)
    end

    --- The anchor in force at time t (the latest one at or before it), or nil.
    local function anchorAt(car, t)
        local best
        for _, a in ipairs(car.anchors) do if a.t <= t and (not best or a.t >= best.t) then best = a end end
        return best
    end

    --- Distance along the line of car `id` at time t (ms since the go).
    function M.distanceAt(model, id, t)
        local car = model.cars[id]
        if not car then return nil end
        if car.live then return car.live.d end
        local a = anchorAt(car, t)
        if not a then return origD(car, t) end
        if a.stopped then return a.d end
        local base = origT(car, a.d)
        if not base then return a.d end
        return origD(car, base + (t - a.t) * (a.rate or 1))
    end

    --- Speed of car `id` at time t in m/s (0 when stopped or finished).
    function M.speedAt(model, id, t)
        local d1, d2 = M.distanceAt(model, id, t), M.distanceAt(model, id, t + 500)
        if not d1 or not d2 then return 0 end
        return (d2 - d1) / 0.5
    end

    --- When car `id` passed (or will pass) distance d, in ms since the go, with its anchors applied; nil if it never does.
    function M.timeAt(model, id, d)
        local car = model.cars[id]
        if not car then return nil end
        local a = anchorAt(car, math.huge)
        if a and d >= a.d then
            if a.stopped then return nil end
            local base, target = origT(car, a.d), origT(car, d)
            if not base or not target then return nil end
            return a.t + (target - base) / (a.rate or 1)
        end
        return origT(car, d)
    end

    --- When car `id` crosses the finish, in ms since the go, or nil when its run ends short of it.
    function M.finishAt(model, id)
        local car = model.cars[id]
        if not car then return nil end
        -- A live bubble crossing the finish is authoritative even if the sim had retired this car.
        if car.physicalFinishMs then return car.physicalFinishMs end
        -- a car on the road in someone's bubble finishes only by crossing the line there
        if car.live then return nil end
        local a = anchorAt(car, math.huge)
        local finishT = origT(car, model.lengthM)
        if not a then return finishT end
        if a.stopped or not finishT then return nil end
        local base = origT(car, a.d)
        if not base then return nil end
        return a.t + (finishT - base) / (a.rate or 1)
    end

    --- When car `id` is expected to cross the line from where it is at time t, in ms since the go, WITHOUT penalties;
    --- nil when it is out. A live car is projected from its observed position at its measured pace (else its sim pace).
    function M.expectedFinishAt(model, id, t)
        local car = model.cars[id]
        if not car then return nil end
        if car.physicalFinishMs then return car.physicalFinishMs end
        if car.live then
            local finishT, base = origT(car, model.lengthM), origT(car, car.live.d)
            if not finishT then return nil end                       -- the sim has it retiring: no projection
            base = base or finishT
            return math.max(t, car.live.t) + math.max(0, finishT - base) / (car.live.rate or 1)
        end
        return M.finishAt(model, id)
    end

    --- Projected classification time: expected finish plus every penalty the car carries. nil when it is out.
    function M.projectedMs(model, id, t)
        local f = M.expectedFinishAt(model, id, t)
        local car = model.cars[id]
        return f and (f + (car and car.penaltyMs or 0)) or nil
    end

    --- A penalty on car `id` (an NPC incident, race control): it moves the provisional order and the result alike.
    function M.penalize(model, id, ms)
        local car = model.cars[id]
        if not car or not ms or ms <= 0 then return false end
        car.penaltyMs = (car.penaltyMs or 0) + ms
        return true
    end

    --- Car `id` is on the road in a player's bubble, really at distance d at time t. `rate` = its pace against its own
    --- sim (measured), used to project its finish.
    function M.observe(model, id, t, d, rate)
        local car = model.cars[id]
        if not car then return false end
        car.live = { t = t, d = d, rate = rate or (car.live and car.live.rate) or nil }
        return true
    end

    --- The whole field's measured pace against its sims, pooled over every physical stretch of at least minM metres
    --- (default 150): the fallback for a car seen too briefly to measure on its own. nil without any; clamped like it.
    function M.fieldRate(model, minM)
        local simMs, realMs = 0, 0
        for _, id in ipairs(model.order) do
            local car = model.cars[id]
            for _, sp in ipairs(car.physical) do
                local a, b = origT(car, sp.from), origT(car, sp.to)
                if a and b and sp.tTo and sp.tFrom and sp.tTo > sp.tFrom and (sp.to - sp.from) >= (minM or 150) then
                    simMs, realMs = simMs + (b - a), realMs + (sp.tTo - sp.tFrom)
                end
            end
        end
        if realMs <= 0 or simMs <= 0 then return nil end
        return math.max(0.5, math.min(1.5, simMs / realMs))
    end

    --- How fast car `id` drove physically against its own sim: sim time over the physical stretches / real time.
    --- nil without a usable stretch (under minM metres in all). Clamped to [0.5, 1.5].
    function M.observedRate(model, id, minM)
        local car = model.cars[id]
        if not car then return nil end
        local simMs, realMs, metres = 0, 0, 0
        for _, sp in ipairs(car.physical) do
            local a, b = origT(car, sp.from), origT(car, sp.to)
            if a and b and sp.tTo and sp.tFrom and sp.tTo > sp.tFrom then
                simMs, realMs, metres = simMs + (b - a), realMs + (sp.tTo - sp.tFrom), metres + (sp.to - sp.from)
            end
        end
        if metres < (minM or 300) or realMs <= 0 or simMs <= 0 then return nil end
        return math.max(0.5, math.min(1.5, simMs / realMs))
    end

    --- A point on the line at distance d: { x, y, z, yaw }. Past the finish it continues straight on.
    function M.pointAt(model, d)
        local pts, cum = model.path.points, model.cum
        if d <= 0 then
            local a, b = pts[1], pts[2]
            return { x = a.x, y = a.y, z = a.z or 0, yaw = yawOf(b.x - a.x, b.y - a.y) }
        end
        for i = 2, #pts do
            if d <= cum[i] then
                local a, b = pts[i - 1], pts[i]
                local span = cum[i] - cum[i - 1]
                local f = span > 0 and (d - cum[i - 1]) / span or 0
                return { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = (a.z or 0) + ((b.z or 0) - (a.z or 0)) * f,
                    yaw = yawOf(b.x - a.x, b.y - a.y), index = i }
            end
        end
        local a, b = pts[#pts - 1], pts[#pts]
        local len = math.max(1e-6, dist(a, b))
        local over = d - cum[#cum]
        return { x = b.x + (b.x - a.x) / len * over, y = b.y + (b.y - a.y) / len * over, z = b.z or 0, yaw = yawOf(b.x - a.x, b.y - a.y), index = #pts }
    end

    --- Where car `id` is at time t: { x, y, z, yaw, d, speed, state }. state is racing / finished / out.
    function M.carAt(model, id, t)
        local d = M.distanceAt(model, id, t)
        if not d then return nil end
        local p = M.pointAt(model, d)
        p.d, p.speed = d, M.speedAt(model, id, t)
        local fin = M.finishAt(model, id)
        if fin and t >= fin then p.state = "finished"
        elseif model.cars[id].live then p.state = "racing"
        elseif not fin and p.speed <= 0.01 and t > 0 then p.state = "out"
        else p.state = "racing" end
        return p
    end

    --- The distance along the line nearest a world position (for handing a physical car back).
    --- `lo`/`hi` (optional) bound the answer to where the car is already known to be: a line that passes the same
    --- place more than once -- every lap of an oval (L236, KB-223) -- otherwise snaps a car to the first pass.
    --- With no window found on the line, the whole line is searched.
    function M.project(model, pos, lo, hi)
        local pts, cum = model.path.points, model.cum
        lo, hi = lo or -math.huge, hi or math.huge
        local bestD, bestGap = nil, math.huge
        for i = 2, #pts do
            local c0, c1 = cum[i - 1], cum[i]
            local span = c1 - c0
            if c1 >= lo and c0 <= hi then
                local a, b = pts[i - 1], pts[i]
                local vx, vy = b.x - a.x, b.y - a.y
                local len2 = vx * vx + vy * vy
                local u = len2 > 0 and (((pos.x - a.x) * vx + (pos.y - a.y) * vy) / len2) or 0
                local uLo = span > 0 and math.max(0, (lo - c0) / span) or 0
                local uHi = span > 0 and math.min(1, (hi - c0) / span) or 1
                if u < uLo then u = uLo elseif u > uHi then u = uHi end
                local gap = dist({ x = a.x + vx * u, y = a.y + vy * u }, pos)
                if gap < bestGap then bestGap, bestD = gap, c0 + span * u end
            end
        end
        if not bestD then
            if lo ~= -math.huge or hi ~= math.huge then return M.project(model, pos) end
            return 0, math.huge
        end
        return bestD, bestGap
    end

    --- A physical observation: car `id` was really at distance d at time t. From t on it runs from d at its own pace.
    --- `stopped = true` records a car that is physically out (it stays where it is).
    function M.anchor(model, id, t, d, stopped, physicalFinishMs, rate)
        local car = model.cars[id]
        if not car then return false end
        car.live = nil                                   -- back in the model: no longer on anyone's road
        car.anchors[#car.anchors + 1] = { t = t, d = d, stopped = stopped or nil, rate = rate }
        if physicalFinishMs then
            car.physicalFinishMs = math.min(car.physicalFinishMs or physicalFinishMs, physicalFinishMs)
        end
        return true
    end

    --- Record that car `id` drove [fromD, toD] physically (between tFrom and tTo).
    function M.markPhysical(model, id, fromD, toD, tFrom, tTo)
        local car = model.cars[id]
        if not car or toD <= fromD then return end
        car.physical[#car.physical + 1] = { from = fromD, to = toD, tFrom = tFrom, tTo = tTo }
    end

    --- Share of car `id`'s line (0..1) that was driven physically (overlaps counted once).
    function M.physicalShare(model, id)
        local car = model.cars[id]
        if not car or #car.physical == 0 then return 0 end
        local spans = {}
        for _, s in ipairs(car.physical) do spans[#spans + 1] = { s.from, s.to } end
        table.sort(spans, function(a, b) return a[1] < b[1] end)
        local total, curA, curB = 0, spans[1][1], spans[1][2]
        for i = 2, #spans do
            if spans[i][1] <= curB then curB = math.max(curB, spans[i][2])
            else total = total + (curB - curA); curA, curB = spans[i][1], spans[i][2] end
        end
        total = total + (curB - curA)
        return math.min(1, total / math.max(1, model.lengthM))
    end

    --- Car ids whose position at time t is within `radius` metres of `pos`.
    function M.near(model, t, pos, radius)
        local out = {}
        for _, id in ipairs(model.order) do
            local p = M.carAt(model, id, t)
            if p and p.state == "racing" and dist(p, pos) <= radius then out[#out + 1] = id end
        end
        return out
    end

    --- The running order at time t: rows { id, orgId, pos, d, gapMs, state }, leader first. Finished cars rank by their
    --- finish time; racing cars by distance; cars out by how far they got.
    function M.standings(model, t, refMps)
        local rows = {}
        for _, id in ipairs(model.order) do
            local car = model.cars[id]
            local p = M.carAt(model, id, t)
            local fin = M.finishAt(model, id)
            local state = p and p.state or "out"
            rows[#rows + 1] = { id = id, orgId = car.orgId, grid = car.grid, d = p and p.d or 0, state = state,
                finishMs = (fin and t >= fin) and fin or nil, penaltyMs = car.penaltyMs or 0, live = car.live and true or nil }
        end
        local ref = refMps or M.refSpeed(model, t, rows)
        for _, r in ipairs(rows) do r.projMs = M.provisionalMs(model, r, t, ref) end
        M.sortProvisional(rows)
        local leader = rows[1]
        for i, r in ipairs(rows) do
            r.pos = i
            r.gapMs = (r.projMs and leader and leader.projMs) and math.max(0, math.floor(r.projMs - leader.projMs + 0.5)) or nil
        end
        return rows
    end

    --- The field's reference pace at time t (m/s): the mean average speed of the cars still racing, from the go. ONE
    --- pace for everyone, so the provisional order never reorders cars on the road by guessed pace -- a car behind you is
    --- behind you -- while a penalty moves a car by real seconds and a finisher compares fairly with cars still out.
    function M.refSpeed(model, t, rows)
        local sum, n = 0, 0
        if t > 10000 then
            for _, r in ipairs(rows or {}) do
                if r.state == "racing" and (r.d or 0) > 0 then sum, n = sum + r.d / (t / 1000), n + 1 end
            end
        end
        local v = n > 0 and sum / n or nil
        if not v then
            local best
            for _, id in ipairs(model.order) do
                local f = M.finishAt(model, id)
                if f and (not best or f < best) then best = f end
            end
            v = best and model.lengthM / (best / 1000) or 30
        end
        return math.max(8, math.min(90, v))
    end

    --- A row's provisional classification time (ms since the go, penalties included): a finisher's finish; a car
    --- racing, now plus its remaining distance at the reference pace; nil for a car out. Works for any row with
    --- { state, d, finishMs?, penaltyMs? } -- a human's too.
    function M.provisionalMs(model, r, t, refMps, withPenalties)
        local pen = withPenalties and (r.penaltyMs or 0) or 0
        if r.state == "finished" and r.finishMs then return r.finishMs + pen end
        if r.state ~= "racing" then return nil end
        local left = math.max(0, model.lengthM - (r.d or 0))
        return t + left / math.max(1, refMps) * 1000 + pen
    end

    --- The provisional order, used for model rows and mixed (human) rows alike: everyone with a projected classification
    --- time by it (finished or not -- a finisher carrying penalties can be behind a car still running), then cars out
    --- by how far they got. Rows: { projMs?, d, grid? }.
    function M.sortProvisional(rows)
        table.sort(rows, function(a, b)
            if (a.projMs ~= nil) ~= (b.projMs ~= nil) then return a.projMs ~= nil end
            if a.projMs and b.projMs and a.projMs ~= b.projMs then return a.projMs < b.projMs end
            if (a.d or 0) ~= (b.d or 0) then return (a.d or 0) > (b.d or 0) end
            return (a.grid or 99) < (b.grid or 99)
        end)
        return rows
    end

    --- When the first car crossed (or will cross) the line, raw, in ms since the go; nil when nobody does.
    function M.leaderFinishAt(model)
        local best
        for _, id in ipairs(model.order) do
            local f = M.finishAt(model, id)
            if f and (not best or f < best) then best = f end
        end
        return best
    end

    --- The classification in `paddock.sim`'s entrant shape, from the model with every anchor applied. Each entrant
    --- also carries `physicalShare`. `cutoffMs` (the flag, ms since the go): only cars home by then are finishers; the
    --- rest are classified behind them by how far they had got at the flag (`dnfReason = "flagged"`).
    function M.result(model, cutoffMs)
        local finishers, outs = {}, {}
        for _, id in ipairs(model.order) do
            local car = model.cars[id]
            local fin = M.finishAt(model, id)
            if fin and (not cutoffMs or fin <= cutoffMs) then finishers[#finishers + 1] = { id = id, car = car, t = fin + (car.penaltyMs or 0), raw = fin }
            elseif fin then
                outs[#outs + 1] = { id = id, car = car, reached = M.distanceAt(model, id, cutoffMs) or 0, flagged = true }
            else
                local a = anchorAt(car, math.huge)
                local reached = a and a.d or car.knots[#car.knots].d
                outs[#outs + 1] = { id = id, car = car, reached = reached }
            end
        end
        table.sort(finishers, function(a, b) if a.t ~= b.t then return a.t < b.t end return (a.car.grid or 99) < (b.car.grid or 99) end)
        table.sort(outs, function(a, b) if a.reached ~= b.reached then return a.reached > b.reached end return (a.car.grid or 99) < (b.car.grid or 99) end)
        local out, leader = {}, finishers[1] and finishers[1].t or 0
        for i, f in ipairs(finishers) do
            out[#out + 1] = { id = f.id, orgId = f.car.orgId, position = i, grid = f.car.grid, state = "finished",
                finishMs = math.floor(f.t + 0.5), gapMs = math.floor(f.t - leader + 0.5), physicalShare = M.physicalShare(model, f.id),
                penaltyMs = (f.car.penaltyMs or 0) > 0 and f.car.penaltyMs or nil, rawFinishMs = math.floor(f.raw + 0.5) }
        end
        for _, o in ipairs(outs) do
            out[#out + 1] = { id = o.id, orgId = o.car.orgId, position = #out + 1, grid = o.car.grid, state = "dnf",
                dnfReason = o.flagged and "flagged" or ((#o.car.anchors > 0 and o.car.anchors[#o.car.anchors].stopped) and "stopped" or "retired"),
                reachedM = math.floor(o.reached or 0),
                physicalShare = M.physicalShare(model, o.id) }
        end
        return out
    end

    return M
end)
