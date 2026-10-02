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
-- Pure: no host calls. Times are ms since the race's go; distances are metres along the line from the start line.
local Core = NcmCore

Core.define("paddock.racestate", function(C)
    local M = { version = "0.1.0" }

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
            local car = { id = e.id, orgId = e.orgId, grid = e.grid, knots = knots, dnf = stopAt ~= nil, anchors = {}, physical = {} }
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
        local a = anchorAt(car, t)
        if not a then return origD(car, t) end
        if a.stopped then return a.d end
        local base = origT(car, a.d)
        if not base then return a.d end
        return origD(car, base + (t - a.t))
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
            return a.t + (target - base)
        end
        return origT(car, d)
    end

    --- When car `id` crosses the finish, in ms since the go, or nil when its run ends short of it.
    function M.finishAt(model, id)
        local car = model.cars[id]
        if not car then return nil end
        -- A live bubble crossing the finish is authoritative even if the sim had retired this car.
        if car.physicalFinishMs then return car.physicalFinishMs end
        local a = anchorAt(car, math.huge)
        local finishT = origT(car, model.lengthM)
        if not a then return finishT end
        if a.stopped or not finishT then return nil end
        local base = origT(car, a.d)
        if not base then return nil end
        return a.t + (finishT - base)
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
    function M.anchor(model, id, t, d, stopped, physicalFinishMs)
        local car = model.cars[id]
        if not car then return false end
        car.anchors[#car.anchors + 1] = { t = t, d = d, stopped = stopped or nil }
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
    function M.standings(model, t)
        local rows = {}
        for _, id in ipairs(model.order) do
            local car = model.cars[id]
            local p = M.carAt(model, id, t)
            local fin = M.finishAt(model, id)
            rows[#rows + 1] = { id = id, orgId = car.orgId, grid = car.grid, d = p and p.d or 0, state = p and p.state or "out",
                finishMs = (fin and t >= fin) and fin or nil }
        end
        local rank = { finished = 1, racing = 2, out = 3 }
        table.sort(rows, function(a, b)
            if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
            if a.state == "finished" then return a.finishMs < b.finishMs end
            if a.d ~= b.d then return a.d > b.d end
            return (a.grid or 99) < (b.grid or 99)
        end)
        local leader = rows[1]
        for i, r in ipairs(rows) do
            r.pos = i
            if r.state == "finished" and leader.state == "finished" then r.gapMs = r.finishMs - leader.finishMs
            elseif r.state == "racing" and leader and r ~= leader then
                -- how long ago the leader passed the spot this car is at now
                local lt = M.timeAt(model, leader.id, r.d)
                r.gapMs = lt and math.max(0, math.floor(t - lt + 0.5)) or nil
            elseif r == leader then
                r.gapMs = 0
            end
        end
        return rows
    end

    --- The classification in `paddock.sim`'s entrant shape, from the model with every anchor applied. Each entrant
    --- also carries `physicalShare`.
    function M.result(model)
        local finishers, outs = {}, {}
        for _, id in ipairs(model.order) do
            local car = model.cars[id]
            local fin = M.finishAt(model, id)
            if fin then finishers[#finishers + 1] = { id = id, car = car, t = fin }
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
                finishMs = math.floor(f.t + 0.5), gapMs = math.floor(f.t - leader + 0.5), physicalShare = M.physicalShare(model, f.id) }
        end
        for _, o in ipairs(outs) do
            out[#out + 1] = { id = o.id, orgId = o.car.orgId, position = #out + 1, grid = o.car.grid, state = "dnf",
                dnfReason = (#o.car.anchors > 0 and o.car.anchors[#o.car.anchors].stopped) and "stopped" or "retired",
                physicalShare = M.physicalShare(model, o.id) }
        end
        return out
    end

    return M
end)
