-- ncm-core module: paddock.live
-- Physical-authoritative Paddock races (doc 44 §12, phase 5, L222). The pure half: nothing here touches a vehicle.
--
-- A live race is an EXPLICITLY DECLARED activity: a player asks for an upcoming NPC race to be run on the street,
-- goes to its start, and the field is spawned there and driven. The sim still runs at the window's opening, sealed
-- as always; the physical run happens in the same window. When it ends:
--   * every classified car must have crossed every timing gate in order, observed by the SERVER from canonical
--     positions (the platform backend), or reported by the Pace DLL AND matched by the server within `TOL_MS`;
--   * enough of the field must finish (`MIN_FINISH_SHARE`, and at least two cars);
-- and then the physical classification REPLACES the sim's result, with provenance `physical`. Anything short of
-- that is `fallback`: the sim's sealed result stands, provenance stays `simulated`, and the tape says why. Billie
-- settles at the close, after this, so a physical result settles slips once and nothing is ever re-settled.
--
-- The pieces:
--   path        a road line from a human ghost of the route (<= 64 points, OPEN//77's followRoute limit), or the
--               bare start -> finish when no ghost exists yet (the native planner then chooses the roads)
--   checkpoints timing gates spaced along that path, one per sim segment, so a physical split means what a sim
--               split means
--   speedPlan   each car's ceiling per path leg, from ITS OWN sim splits, so the order the sim believed in is the
--               order the cars try to drive; physics, traffic and contact then do what they do
--   timing      gate crossings in strict order, dated by interpolation between two samples (course.gates)
--   verdict     physical / fallback, and the classification in the sim's own result shape
local Core = NcmCore

Core.define("paddock.live", function(C)
    local M = { version = "0.1.0" }
    local Gates = C.get("course.gates")
    local Grid = C.get("session.grid")
    local Routes = C.get("course.routes")

    M.MAX_POINTS = 64            -- Open77.vehicles.ai.followRoute accepts 1..64 points
    M.PLATFORM_MAX_MPS = 55      -- Open77.vehicles.ai.setSpeed hard cap (build .78, L8)
    M.MIN_MPS = 8
    M.TOL_MS = 1500              -- server vs Pace DLL gate time agreement
    M.MIN_FINISH_SHARE = 0.5
    M.GATE_HALF_WIDTH_M = 28     -- a race line is wider than a practice gate: cars run side by side
    M.GATE_CAPTURE_M = 35        -- a gate spaced along a curving road is also passed by reaching its point
    M.STALL_SEC = 30             -- no progress this long is a DNF ("stalled")

    local function dist(a, b)
        local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
        return math.sqrt(dx * dx + dy * dy)
    end
    M.dist = dist

    --- REDengine yaw for a travel direction: forward = (-sin yaw, cos yaw), so +Y is 0 and +X is -90 (270).
    function M.yawFromDir(dx, dy)
        return (math.deg(math.atan(-dx, dy)) + 360) % 360
    end
    -- Lua 5.1/LuaJIT math.atan takes one argument; 5.4 takes two. atan2 semantics either way.
    if math.atan2 then
        function M.yawFromDir(dx, dy) return (math.deg(math.atan2(-dx, dy)) + 360) % 360 end
    end

    --- Resample a polyline to `n` points evenly spaced by distance (first and last kept). Points are { x, y, z }.
    function M.resample(points, n)
        if type(points) ~= "table" or #points < 2 then return points end
        n = math.max(2, math.min(n or M.MAX_POINTS, M.MAX_POINTS))
        local cum = { 0 }
        for i = 2, #points do cum[i] = cum[i - 1] + dist(points[i - 1], points[i]) end
        local total = cum[#points]
        if total <= 0 then return { points[1], points[#points] } end
        local out, j = {}, 2
        for k = 0, n - 1 do
            local target = total * k / (n - 1)
            while j < #points and cum[j] < target do j = j + 1 end
            local a, b = points[j - 1], points[j]
            local span = cum[j] - cum[j - 1]
            local f = span > 0 and (target - cum[j - 1]) / span or 0
            out[#out + 1] = { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = (a.z or 0) + ((b.z or 0) - (a.z or 0)) * f }
        end
        return out, total
    end

    --- The road line: from a decoded ghost (replay.pose poses) when one exists, else start -> finish.
    --- Returns { points, lengthM, source = "ghost" | "direct" }.
    function M.path(route, poses, n)
        if type(poses) == "table" and #poses >= 8 then
            local pts = {}
            for i, p in ipairs(poses) do pts[i] = { x = p.x, y = p.y, z = p.z or 0 } end
            local out, total = M.resample(pts, n or 48)
            if out and total and total > 200 then return { points = out, lengthM = total, source = "ghost" } end
        end
        local s, f = route.start, route.finish
        return { points = { { x = s.x, y = s.y, z = s.z or 0 }, { x = f.x, y = f.y, z = f.z or 0 } },
            lengthM = route.distanceM or dist(s, f), source = "direct" }
    end

    --- The point `f` (0..1) of the way along a path by distance.
    function M.along(points, f)
        local total = 0
        for i = 2, #points do total = total + dist(points[i - 1], points[i]) end
        local target, acc = total * f, 0
        for i = 2, #points do
            local d = dist(points[i - 1], points[i])
            if acc + d >= target and d > 0 then
                local u = (target - acc) / d
                local a, b = points[i - 1], points[i]
                return { x = a.x + (b.x - a.x) * u, y = a.y + (b.y - a.y) * u, z = (a.z or 0) + ((b.z or 0) - (a.z or 0)) * u }
            end
            acc = acc + d
        end
        return points[#points]
    end

    --- Timing gates: the route's own start and finish, and `segments - 1` intermediate gates spaced along the path
    --- (only when the path is a real road line; a direct path gets start/finish only). Each gate's line faces the
    --- straight between its neighbours (course.gates.build).
    function M.checkpoints(route, path, segments)
        local mids = {}
        if path.source == "ghost" and (segments or 0) >= 2 then
            for k = 1, segments - 1 do
                local p = M.along(path.points, k / segments)
                mids[#mids + 1] = { x = p.x, y = p.y, z = p.z, name = "S" .. k }
            end
        end
        return Gates.build(route, { intermediate = mids, halfWidthM = M.GATE_HALF_WIDTH_M, captureM = M.GATE_CAPTURE_M })
    end

    --- Grid slots behind the start gate, pole first, with REDengine yaw.
    function M.gridSlots(startGate, n)
        local out = {}
        for i = 1, n do
            local p = Grid.slotPosition(startGate, i)
            out[i] = { x = p.x, y = p.y, z = p.z, yaw = M.yawFromDir(startGate.dir.x, startGate.dir.y) }
        end
        return out
    end

    --- One car's speed ceiling for each leg of the path (leg i ends at point i+1), from its own sim splits.
    --- `splits` are cumulative ms per sim segment; `lengthM` the path length. Legs map to the sim segment their
    --- midpoint falls in. Clamped to [MIN_MPS, cap]. A DNF in the sim still drives: its missing splits reuse the
    --- last known pace, because the physical race decides for itself whether it finishes.
    function M.speedPlan(points, lengthM, splits, segments, cap)
        cap = cap or M.PLATFORM_MAX_MPS
        segments = math.max(1, segments or 1)
        local segLen = (lengthM or 1) / segments
        local segSpeed = {}
        local prev, last = 0, nil
        for s = 1, segments do
            local t = splits and splits[s]
            local mps
            if t and t > prev then mps = segLen / ((t - prev) / 1000); prev = t end
            mps = mps or last or (cap * 0.8)
            segSpeed[s] = mps; last = mps
        end
        local out, acc = {}, 0
        for i = 2, #points do
            local d = dist(points[i - 1], points[i])
            local mid = acc + d / 2
            acc = acc + d
            local s = math.min(segments, math.max(1, math.floor(mid / segLen) + 1))
            local v = segSpeed[s] * 1.08      -- a ceiling, not a target: the planner brakes for corners on its own
            if v > cap then v = cap elseif v < M.MIN_MPS then v = M.MIN_MPS end
            out[i - 1] = math.floor(v * 10 + 0.5) / 10
        end
        return out
    end

    -- ---------------------------------------------------------------------------------------------------- timing

    --- A timing sheet over timing gates (every gate after the start). ids = entrant ids in grid order.
    function M.newTiming(gates, ids)
        local timing = { gates = gates, cars = {}, order = {} }
        for i, id in ipairs(ids) do
            timing.order[i] = id
            timing.cars[id] = { next = 2, times = {}, lastPos = nil, lastMs = nil, progressMs = 0, done = false }
        end
        return timing
    end

    --- Feed one sample for one car (tMs = ms since the go). Records every gate the move crossed, in order.
    --- Returns the list of gate indexes newly crossed.
    function M.observe(timing, id, pos, tMs)
        local c = timing.cars[id]
        if not c or c.done or type(pos) ~= "table" then return {} end
        local crossed = {}
        local prev, prevMs = c.lastPos, c.lastMs
        if prev then
            local moved = dist(prev, pos)
            if moved > 3 then c.progressMs = tMs end
            local guard = 0
            while c.next <= #timing.gates and guard < #timing.gates do
                guard = guard + 1
                local g = timing.gates[c.next]
                local f = Gates.crossFraction(g, prev, pos)
                if not f then break end
                local at = math.floor(prevMs + (tMs - prevMs) * f + 0.5)
                c.times[c.next] = at
                crossed[#crossed + 1] = c.next
                c.next = c.next + 1
            end
            if c.next > #timing.gates then c.done = true; c.finishMs = c.times[#timing.gates] end
        else
            c.progressMs = tMs
        end
        c.lastPos, c.lastMs = { x = pos.x, y = pos.y, z = pos.z }, tMs
        return crossed
    end

    --- Has a car stopped making progress?
    function M.stalled(timing, id, tMs, stallSec)
        local c = timing.cars[id]
        if not c or c.done then return false end
        return (tMs - (c.progressMs or 0)) > (stallSec or M.STALL_SEC) * 1000
    end

    function M.allDone(timing, out)
        for _, id in ipairs(timing.order) do
            local c = timing.cars[id]
            if not c.done and not (out and out[id]) then return false end
        end
        return true
    end

    --- Compare the server's gate times with the Pace DLL's. `client` = id -> { gateIndex -> ms }. Returns
    --- ok, detail: ok only when every gate the server timed for every finisher has a client time within tol.
    function M.corroborate(timing, client, tol)
        tol = tol or M.TOL_MS
        local worst, checked = 0, 0
        for _, id in ipairs(timing.order) do
            local c = timing.cars[id]
            if c.done then
                local ct = client and client[id]
                if not ct then return false, { reason = "no_client_times", id = id } end
                for g = 2, #timing.gates do
                    local a, b = c.times[g], ct[g] or ct[tostring(g)]
                    if not (a and b) then return false, { reason = "missing_gate", id = id, gate = g } end
                    local d = math.abs(a - b)
                    if d > worst then worst = d end
                    if d > tol then return false, { reason = "disagree", id = id, gate = g, deltaMs = d } end
                    checked = checked + 1
                end
            end
        end
        return true, { worstMs = worst, checked = checked }
    end

    --- The verdict and the classification in `paddock.sim`'s entrant shape. field = { { id, orgId }, ... } in GRID
    --- order; out = id -> dnfReason for cars the host retired (stalled, destroyed, lost). opts.clientOk = the
    --- corroboration result when the Pace backend drove (nil for the platform backend).
    function M.classify(timing, field, out, opts)
        opts = opts or {}
        local finishers, dnfs = {}, {}
        for gi, e in ipairs(field) do
            local c = timing.cars[e.id]
            if c and c.done then
                finishers[#finishers + 1] = { id = e.id, orgId = e.orgId, grid = gi, t = c.finishMs, splits = c.times }
            else
                local reached = c and (c.next - 1) or 1
                dnfs[#dnfs + 1] = { id = e.id, orgId = e.orgId, grid = gi, reached = reached,
                    reason = (out and out[e.id]) or "stalled", splits = c and c.times or {} }
            end
        end
        table.sort(finishers, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.grid < b.grid end)
        table.sort(dnfs, function(a, b) if a.reached ~= b.reached then return a.reached > b.reached end return a.grid < b.grid end)
        local entrants, leader = {}, finishers[1] and finishers[1].t or 0
        for i, f in ipairs(finishers) do
            entrants[#entrants + 1] = { id = f.id, orgId = f.orgId, position = i, grid = f.grid, state = "finished",
                finishMs = f.t, gapMs = f.t - leader, splits = f.splits }
        end
        for _, d in ipairs(dnfs) do
            entrants[#entrants + 1] = { id = d.id, orgId = d.orgId, position = #entrants + 1, grid = d.grid, state = "dnf",
                dnfReason = d.reason, splits = d.splits }
        end
        local need = math.max(2, math.ceil(#field * (opts.minFinishShare or M.MIN_FINISH_SHARE)))
        local verdict, why = "physical", nil
        if #finishers < need then verdict, why = "fallback", ("only %d of %d finished (need %d)"):format(#finishers, #field, need) end
        if verdict == "physical" and opts.clientOk == false then verdict, why = "fallback", "pace times not corroborated" end
        return { verdict = verdict, reason = why, entrants = entrants, finishers = #finishers }
    end

    return M
end)
