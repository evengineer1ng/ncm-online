-- ncm-core module: course.gates
-- A course is an ordered list of gates: a start line, optional authored intermediate gates, and a
-- finish line. Gates are lines (a point plus a direction of travel) crossed by a sign flip of the
-- signed distance along that direction, with a lateral half-width and an arm distance -- the same
-- finish-line geometry SP racing uses (modules/racing.lua _checkFinishLineCrossing).
-- Pure: hosts supply positions; nothing here reads the game.
local Core = NcmCore

Core.define("course.gates", function(C)
    local M = { version = "0.0.1" }
    local routes = C.get("course.routes")

    M.DEFAULT_HALF_WIDTH_M = 20.0   -- lateral tolerance either side of the line
    M.DEFAULT_ARM_M = 60.0          -- line crossings only count this close to the gate point
    M.DEFAULT_CAPTURE_M = 25.0      -- PRIMARY rule: reaching the gate point (any approach angle). SP checkpoints use 50 m.
    M.DEFAULT_LEAVE_M = 30.0        -- start only: driving this far from where you sat at lights-out counts as starting
    M.DEFAULT_RADIUS_M = 100.0      -- host-side sanity radius for authoritative (up to ~1 s stale) positions
    M.START_RADIUS_M = 160.0

    --- Unit forward vector for a heading in degrees (SP convention: x = cos, y = sin).
    function M.forwardFromHeading(deg)
        local r = math.rad(deg or 0)
        return { x = math.cos(r), y = math.sin(r) }
    end

    local function unit(dx, dy)
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1e-6 then return nil end
        return { x = dx / len, y = dy / len }
    end

    local function gate(index, kind, p, dir, name, opts)
        return {
            index = index, kind = kind, name = name or kind,
            x = p.x, y = p.y, z = p.z or 0,
            dir = dir,
            halfWidthM = (opts and opts.halfWidthM) or M.DEFAULT_HALF_WIDTH_M,
            armM = (opts and opts.armM) or M.DEFAULT_ARM_M,
            captureM = (opts and opts.captureM) or M.DEFAULT_CAPTURE_M,
            leaveM = kind == "start" and ((opts and opts.leaveM) or M.DEFAULT_LEAVE_M) or nil,
            radiusM = (opts and opts.radiusM) or (kind == "start" and M.START_RADIUS_M or M.DEFAULT_RADIUS_M),
        }
    end

    --- Build the gate list for a route. opts = { intermediate = { {x,y,z,heading?,name?}, ... }, halfWidthM, armM }
    --- Every line faces the straight direction along the course: start -> next point, previous point ->
    --- finish, previous -> next for an intermediate gate (its own heading wins if authored). Node
    --- headings are NOT used: SP recorded them as "where the author faced", and on B-line the start
    --- node's heading is 90 degrees off the route (live 2026-09-20), which made the start uncrossable.
    function M.build(route, opts)
        if type(route) ~= "table" or not route.start or not route.finish then return nil, "invalid_route" end
        opts = opts or {}
        local points = {}
        points[#points + 1] = { kind = "start", p = route.start, name = route.start.name }
        for _, g in ipairs(opts.intermediate or {}) do
            points[#points + 1] = { kind = "gate", p = g, heading = g.heading, name = g.name }
        end
        points[#points + 1] = { kind = "finish", p = route.finish, name = route.finish.name }
        local list = {}
        for i, pt in ipairs(points) do
            local dir
            if pt.heading ~= nil then
                dir = M.forwardFromHeading(pt.heading)
            elseif i > 1 then
                dir = unit(pt.p.x - points[i - 1].p.x, pt.p.y - points[i - 1].p.y)
            end
            if not dir and i < #points then
                dir = unit(points[i + 1].p.x - pt.p.x, points[i + 1].p.y - pt.p.y)
            end
            dir = dir or { x = 1, y = 0 }
            list[i] = gate(i, pt.kind, pt.p, dir, pt.name, opts)
        end
        return list
    end

    --- Signed distance along the approach (positive = still approaching, <= 0 = past the line) and
    --- the lateral offset from the gate point.
    function M.signedDistance(g, pos)
        local rx, ry = (pos.x or 0) - g.x, (pos.y or 0) - g.y
        local along = rx * (-g.dir.x) + ry * (-g.dir.y)
        local perp = math.abs(rx * g.dir.y - ry * g.dir.x)
        return along, perp
    end

    --- Did the move prev -> pos cross gate g? True when (a) the line was crossed: within arm distance,
    --- previous sample on the approach side, current sample on or past the line, lateral offset within
    --- the half width; or (b) the gate point itself was reached (captureM), whatever the approach angle;
    --- or (c) for the start line only, the driver has left the grid (leaveM from the mark) -- open-route
    --- courses may head away from the straight line at first.
    function M.crossed(g, prev, pos)
        if type(prev) ~= "table" or type(pos) ~= "table" then return false end
        local d = routes.planarDistance(pos, g)
        if d <= (g.captureM or 0) then return true end
        if g.leaveM and d > g.leaveM and routes.planarDistance(prev, g) <= g.leaveM then return true end
        if d > g.armM then return false end
        local before = M.signedDistance(g, prev)
        local after, perp = M.signedDistance(g, pos)
        return before > 0 and after <= 0 and perp <= g.halfWidthM
    end

    --- Where between prev and pos the gate plane was actually crossed, as a fraction 0..1 of that move, so a
    --- host can date the crossing instead of dating the packet that reported it (KB-23). Only the sign-flip case
    --- has a real answer: the captureM and leaveM rules say "somewhere in here", so they return 1 (the later
    --- sample) rather than inventing a precision they do not have. nil when the move did not cross at all.
    function M.crossFraction(g, prev, pos)
        if not M.crossed(g, prev, pos) then return nil end
        local before = M.signedDistance(g, prev)
        local after = M.signedDistance(g, pos)
        if not (before > 0 and after <= 0) then return 1 end
        local span = before - after
        if span <= 0 then return 1 end
        local f = before / span
        if f < 0 then return 0 elseif f > 1 then return 1 end
        return f
    end

    --- Start rule without any geometry: the driver has moved leaveM from where they sat at lights-out.
    function M.startedFrom(origin, pos, leaveM)
        if type(origin) ~= "table" or type(pos) ~= "table" then return false end
        return routes.planarDistance(origin, pos) >= (leaveM or M.DEFAULT_LEAVE_M)
    end

    --- Host-side sanity: is an authoritative position close enough to the gate to accept a report?
    function M.nearGate(g, pos, toleranceM)
        if type(pos) ~= "table" then return false, "position_unknown" end
        local d = routes.planarDistance(pos, g)
        if d > (toleranceM or g.radiusM) then return false, "too_far", d end
        return true, nil, d
    end

    return M
end)
