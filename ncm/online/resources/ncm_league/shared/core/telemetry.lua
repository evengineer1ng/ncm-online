-- ncm-core module: telemetry
-- Telemetry is a first-class stream (L57): clients sample their own car, the server keeps per-session rings and
-- derives progress along the course, average speed and the corrected progress the race graph shows (P40).
-- Pure: samples in, numbers out. A raw sample is a positional array { t, x, y, z, v, g, og, h } to keep batches small.
local Core = NcmCore

Core.define("telemetry", function(C)
    local M = { version = "0.0.1" }

    M.SAMPLE_FIELDS = { "t", "x", "y", "z", "v", "g", "og", "h" }
    M.MAX_BATCH = 10
    M.MAX_JUMP_M = 300
    M.CLOCK_SLACK_S = 1.0    -- a client's estimated server clock may step back a little when it resyncs

    --- Course polyline through the gates: { pts, cum (cumulative metres at each point), lengthM }.
    function M.polyline(gates)
        local pts, cum = {}, {}
        local len = 0
        for i, g in ipairs(gates or {}) do
            pts[i] = { x = g.x, y = g.y, z = g.z or 0 }
            if i > 1 then len = len + math.sqrt((g.x - gates[i - 1].x) ^ 2 + (g.y - gates[i - 1].y) ^ 2) end
            cum[i] = len
        end
        return { pts = pts, cum = cum, lengthM = len }
    end

    --- Project a position onto the polyline. hintSeg narrows the search to neighbouring segments (a car cannot
    --- teleport between ticks); without it every segment is tried. Returns { m, seg, offM }.
    function M.progress(course, pos, hintSeg)
        local pts, cum = course.pts, course.cum
        if #pts < 2 then return { m = 0, seg = 1, offM = 0 } end
        local from, to = 1, #pts - 1
        if hintSeg then from, to = math.max(1, hintSeg - 1), math.min(#pts - 1, hintSeg + 1) end
        local best
        for seg = from, to do
            local a, b = pts[seg], pts[seg + 1]
            local abx, aby = b.x - a.x, b.y - a.y
            local len2 = abx * abx + aby * aby
            local t = 0
            if len2 > 0 then t = ((pos.x - a.x) * abx + (pos.y - a.y) * aby) / len2 end
            t = math.max(0, math.min(1, t))
            local px, py = a.x + abx * t, a.y + aby * t
            local off = math.sqrt((pos.x - px) ^ 2 + (pos.y - py) ^ 2)
            if not best or off < best.offM then
                best = { m = cum[seg] + math.sqrt(len2) * t, seg = seg, offM = off }
            end
        end
        return best
    end

    --- Ring buffer of the last n samples.
    M.Ring = {}
    M.Ring.__index = M.Ring
    function M.Ring.new(n)
        return setmetatable({ n = n or 50, items = {}, head = 0, count = 0 }, M.Ring)
    end
    function M.Ring:push(s)
        self.head = (self.head % self.n) + 1
        self.items[self.head] = s
        if self.count < self.n then self.count = self.count + 1 end
        return s
    end
    function M.Ring:last(k)
        k = k or 1
        if k > self.count then return nil end
        local i = ((self.head - k) % self.n) + 1
        return self.items[i]
    end
    --- Samples newer than (latest.t - sec), oldest first.
    function M.Ring:window(sec)
        local latest = self:last(1)
        if not latest then return {} end
        local out = {}
        for k = self.count, 1, -1 do
            local s = self:last(k)
            if s and (latest.t - (s.t or 0)) <= sec then out[#out + 1] = s end
        end
        return out
    end

    --- The driver's state at time `t`, linearly interpolated between the two samples that bracket it.
    --- Returns nil when `t` is outside the samples' span: a position we did not observe is unknown, never
    --- extrapolated (KB-34 depends on this — an invented position would re-introduce the bug it fixes).
    --- `samples` is oldest-first, as Ring:window returns.
    function M.sampleAt(samples, t)
        if type(samples) ~= "table" or #samples == 0 or type(t) ~= "number" then return nil end
        local prev = nil
        for i = 1, #samples do
            local s = samples[i]
            local st = s and s.t
            if st then
                if st == t then return { t = t, x = s.x, y = s.y, z = s.z or 0, v = s.v or 0,
                    h = s.h, og = s.og, g = s.g, client = s.client } end
                if st > t then
                    if not prev then return nil end            -- t is before anything we saw
                    local span = st - prev.t
                    if span <= 0 then return nil end
                    local f = (t - prev.t) / span
                    return {
                        t = t,
                        x = (prev.x or 0) + ((s.x or 0) - (prev.x or 0)) * f,
                        y = (prev.y or 0) + ((s.y or 0) - (prev.y or 0)) * f,
                        z = (prev.z or 0) + ((s.z or 0) - (prev.z or 0)) * f,
                        v = (prev.v or 0) + ((s.v or 0) - (prev.v or 0)) * f,
                        h = (prev.h and s.h) and (prev.h + (s.h - prev.h) * f) or s.h or prev.h,
                        og = prev.og == s.og and s.og or nil,
                        g = s.g or prev.g,
                        client = prev.client and s.client or nil,
                    }
                end
                prev = s
            end
        end
        return nil                                             -- t is after the newest sample
    end

    --- Average speed (m/s) over the last `sec` seconds from the ring (distance/time of the window).
    function M.avgSpeed(ring, sec)
        local w = ring:window(sec or 10)
        if #w < 2 then return (w[1] and w[1].v) or 0 end
        local dist = 0
        for i = 2, #w do dist = dist + math.sqrt((w[i].x - w[i - 1].x) ^ 2 + (w[i].y - w[i - 1].y) ^ 2) end
        local dt = (w[#w].t or 0) - (w[1].t or 0)
        if dt <= 0 then return 0 end
        return dist / dt
    end

    --- Corrected progress (P40): a penalty moves the dot back by the distance covered in that time at recent pace.
    function M.correctedM(progressM, penaltySec, avgSpeedMps)
        return math.max(0, (progressM or 0) - (penaltySec or 0) * (avgSpeedMps or 0))
    end

    --- Decode and validate a client batch of positional samples. Returns array of sample tables or nil, reason.
    --- `prevSample` must be the same client's last accepted sample: server stand-in samples run on the server's
    --- clock, which the client's estimate lags, and comparing against them refuses every batch (Batch 1 live).
    function M.decodeBatch(raw, prevSample)
        if type(raw) ~= "table" then return nil, "not_a_table" end
        if #raw == 0 or #raw > M.MAX_BATCH then return nil, "batch_size" end
        local out = {}
        local prev = prevSample
        for i, r in ipairs(raw) do
            if type(r) ~= "table" then return nil, "sample_not_a_table" end
            local s = {}
            for j, name in ipairs(M.SAMPLE_FIELDS) do
                local v = r[j]
                if v ~= nil and type(v) ~= "number" and type(v) ~= "boolean" then return nil, "field_type:" .. name end
                s[name] = v
            end
            if type(s.t) ~= "number" or type(s.x) ~= "number" or type(s.y) ~= "number" then return nil, "missing_fields" end
            if prev and s.t < (prev.t or 0) - (prev == prevSample and M.CLOCK_SLACK_S or 0) then return nil, "time_not_monotonic" end
            if prev then
                local jump = math.sqrt((s.x - (prev.x or s.x)) ^ 2 + (s.y - (prev.y or s.y)) ^ 2)
                if jump > M.MAX_JUMP_M then return nil, "jump:" .. math.floor(jump) end
            end
            out[i] = s
            prev = s
        end
        return out
    end

    --- Sector times from gate crossings (seconds between consecutive crossings).
    function M.sectors(crossings, gatesTotal)
        local out = {}
        for i = 2, gatesTotal do
            if crossings[i] and crossings[i - 1] then out[i - 1] = crossings[i] - crossings[i - 1] end
        end
        return out
    end

    return M
end)
