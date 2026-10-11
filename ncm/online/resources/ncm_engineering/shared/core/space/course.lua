-- ncm-core module: space.course
--
-- Racing grammar in three dimensions (L321; doc 54 §G). `course.gates` is a planar street line; a Snowglobe course is
-- a sequence of GATES in space -- a centre, a normal (the direction you must pass through it) and a radius. Crossing
-- is a sign change of the distance to the gate's plane, in the normal's direction, within the radius: exact,
-- frame-rate independent, and the same test on every host.
--
-- A course is authored in its own LOCAL frame (metres; x, y, z) and PLACED into the universe by a frame:
--   anchorFrame(anchor, altitude)  a sky course over a city: x east, y north, z up (fixed on Earth)
--   lvlhFrame(pos, vel)            a station course: x radial out, y along-track, z orbit normal (co-moving)
-- so the same ring can hang over Los Santos or circle a station. Generators draw from a `world.seed` node, never from a
-- running stream: the third gate of a station's ring is the same gate whatever else the seed later grows.
local Core = NcmCore

Core.define("space.course", function(C)
    local M = { version = "0.1.0" }
    local U = C.get("space.universe")

    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function scale(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function unit(a) local l = len(a); return l > 0 and scale(a, 1 / l) or { 0, 0, 1 } end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end

    function M.gate(id, centre, normal, radius)
        return { id = id, centre = centre, normal = unit(normal), radius = radius or 25 }
    end

    --- Did the segment p0 -> p1 pass through the gate, in its normal's direction, within its radius?
    --- Returns crossed, fraction along the segment (0..1), miss distance from the centre at the plane.
    function M.crossed(gate, p0, p1)
        local s0 = dot(sub(p0, gate.centre), gate.normal)
        local s1 = dot(sub(p1, gate.centre), gate.normal)
        if not (s0 < 0 and s1 >= 0) then return false end
        local f = s0 / (s0 - s1)
        local hit = add(p0, scale(sub(p1, p0), f))
        local miss = len(sub(hit, gate.centre))
        return miss <= gate.radius, f, miss
    end

    -- ------------------------------------------------------------------------------------------ frames
    --- A frame { origin, x, y, z } maps local course coordinates into the universe.
    function M.anchorFrame(anchor, altitude)
        local f = U.anchorFrame(anchor)
        local R = U.BODIES.earth.radius
        return { origin = scale(f.up, R + (altitude or 0)), x = f.east, y = f.north, z = f.up, kind = "anchor" }
    end

    function M.lvlhFrame(pos, vel)
        local r = unit(pos)
        local h = unit(cross(pos, vel))
        local along = cross(h, r)
        return { origin = pos, x = r, y = along, z = h, kind = "lvlh" }
    end

    function M.toWorld(frame, p)
        return add(frame.origin, add(add(scale(frame.x, p[1]), scale(frame.y, p[2])), scale(frame.z, p[3])))
    end
    function M.dirToWorld(frame, d) return add(add(scale(frame.x, d[1]), scale(frame.y, d[2])), scale(frame.z, d[3])) end
    function M.toLocal(frame, w)
        local r = sub(w, frame.origin)
        return { dot(r, frame.x), dot(r, frame.y), dot(r, frame.z) }
    end

    --- The course's gates in the universe through `frame`.
    function M.place(course, frame)
        local out = {}
        for i, g in ipairs(course.gates) do
            out[i] = M.gate(g.id, M.toWorld(frame, g.centre), M.dirToWorld(frame, g.normal), g.radius)
        end
        return out
    end

    -- ------------------------------------------------------------------------------------------ shape
    --- Legs between consecutive gates (closed loop): length, the turn at the gate it arrives at, the climb.
    function M.legs(course)
        local g, n, out = course.gates, #course.gates, {}
        for i = 1, n do
            local a, b, c = g[i], g[i % n + 1], g[(i + 1) % n + 1]
            local d1, d2 = sub(b.centre, a.centre), sub(c.centre, b.centre)
            local cosT = dot(unit(d1), unit(d2))
            if cosT > 1 then cosT = 1 elseif cosT < -1 then cosT = -1 end
            out[i] = { from = a.id, to = b.id, lengthM = len(d1), turnRad = math.acos(cosT), climbM = d1[3] }
        end
        return out
    end

    function M.lapLength(course)
        local L = 0
        for _, l in ipairs(M.legs(course)) do L = L + l.lengthM end
        return L
    end

    --- A ring of gates from a seed node: `count` gates on a circle of `radiusM` in the local x-y plane, each lifted
    --- or dropped out of the plane by a seeded wobble, each facing along the way round. opts = { count, radiusM,
    --- wobbleM, gateRadiusM, laps }; every value can come from the seed instead.
    function M.ring(node, opts)
        opts = opts or {}
        local s = node:stream("ring")
        local count = opts.count or s:int(6, 10)
        local R = opts.radiusM or (250 + s() * 350)
        local wobble = opts.wobbleM or (40 + s() * 120)
        local gateR = opts.gateRadiusM or 30
        local course = { id = node:tag("course"), node = node:id(), gates = {}, laps = opts.laps or s:int(2, 4),
                         radiusM = R }
        local pts = {}
        for i = 1, count do
            local gs = node:child("gate", i):stream()
            local th = (i - 1) / count * 2 * math.pi + (gs() - 0.5) * (0.6 * math.pi / count)
            local r = R * (0.8 + 0.4 * gs())
            pts[i] = { r * math.cos(th), r * math.sin(th), (gs() * 2 - 1) * wobble }
        end
        for i = 1, count do
            -- face along the chord from the previous gate to the next: the line a racer takes through it
            local prev, nxt = pts[(i - 2) % count + 1], pts[i % count + 1]
            course.gates[i] = M.gate("G" .. i, pts[i], sub(nxt, prev), gateR)
        end
        course.lapM = M.lapLength(course)
        course.lengthM = course.lapM * course.laps
        return course
    end

    -- ------------------------------------------------------------------------------------------ timing
    --- A live timer over placed (world) gates: start by crossing gate 1, then every gate in order, `laps` times,
    --- finishing on gate 1. `update(p0, p1, t0, t1)` advances it; times interpolate to the crossing instant.
    function M.timer(worldGates, laps)
        local T = { gates = worldGates, laps = laps or 1, next = 1, lap = 0, started = nil, splits = {}, finished = nil, misses = 0 }
        function T:update(p0, p1, t0, t1)
            if self.finished then return nil end
            local g = self.gates[self.next]
            local ok, f, miss = M.crossed(g, p0, p1)
            if f and not ok then self.misses = self.misses + 1; return { missed = g.id, missM = miss } end
            if not ok then return nil end
            local t = t0 + (t1 - t0) * f
            if not self.started then
                self.started, self.lap = t, 1
                self.next = (#self.gates > 1) and 2 or 1
                return { started = true, t = t }
            end
            self.splits[#self.splits + 1] = { gate = g.id, lap = self.lap, ms = math.floor((t - self.started) * 1000 + 0.5) }
            if self.next == 1 then
                if self.lap >= self.laps then
                    self.finished = t
                    return { finished = true, ms = math.floor((t - self.started) * 1000 + 0.5) }
                end
                self.lap = self.lap + 1
            end
            self.next = self.next % #self.gates + 1
            return { gate = g.id, lap = self.lap }
        end
        return T
    end

    return M
end)
