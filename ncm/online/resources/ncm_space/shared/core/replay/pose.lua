-- ncm-core module: replay.pose
-- The pose stream a ghost is replayed from. A pose is a positional array { t, x, y, z, yaw } where `t` is
-- SECONDS FROM THE START OF THE RUN, not the server clock: a ghost is replayed against my own start line
-- crossing, so a stored lap must not carry the wall clock of the day it was set.
--
-- **This is deliberately not `telemetry.SAMPLE_FIELDS`.** That sample is the incident/progress stream: it
-- comes from the driver's body rather than the car, carries no rotation, is quantised to 10 cm when it is
-- persisted, and its stored format has no version column. Bolting a heading onto it would change a
-- persisted format nobody can identify after the fact, in three vendored copies, to serve a second
-- consumer with different needs. So ghosts get their own schema and their own `FORMAT`, and a reader that
-- meets a format it does not know refuses by name instead of guessing (L166).
--
-- Pure: poses in, poses out. Hosts own recording, storage and drawing.
local Core = NcmCore

Core.define("replay.pose", function(C)
    local M = { version = "0.0.1" }

    --- Bump when the meaning or order of POSE_FIELDS changes. Stored beside every lap.
    M.FORMAT = 1
    M.POSE_FIELDS = { "t", "x", "y", "z", "yaw" }

    --- 300 s at the 10 Hz recording rate. A run longer than this is not refused as invalid -- it is refused
    --- as a GHOST, because an unbounded pose list is an unbounded packet and an unbounded row.
    M.MAX_POSES = 3000

    --- Recording rate the client uses. Playback interpolates every frame regardless; this only sets how much
    --- curvature of the real line survives into the stored lap.
    M.DEFAULT_HZ = 10

    --- Decimation tolerances. A pose is dropped when replaying WITHOUT it would put the ghost within this
    --- distance and this heading of where the pose said it actually was.
    M.DEFAULT_TOLERANCE_M = 0.15
    M.DEFAULT_YAW_TOLERANCE_DEG = 1.5

    local floor, sqrt, abs = math.floor, math.sqrt, math.abs

    -- Round half away from zero, so a rounded value never depends on the platform's float-to-int mode.
    local function round(v, places)
        local mul = 10 ^ (places or 0)
        if v >= 0 then return floor(v * mul + 0.5) / mul end
        return -floor(-v * mul + 0.5) / mul
    end

    --- Yaw in [0, 360). The native prop layer takes degrees; normalising here means a stored lap never
    --- carries a negative heading that reads as a bug in a log line.
    function M.normalizeYaw(a)
        a = tonumber(a) or 0
        a = a % 360
        if a < 0 then a = a + 360 end
        return a
    end

    --- The SIGNED SHORTEST ARC from a to b, in (-180, 180].
    ---
    --- The whole of the 359 -> 1 problem is here. A plain linear interpolation between those two headings
    --- travels 358 degrees the long way round, so a ghost crossing north spins a full turn on the spot.
    --- Lua's `%` takes the sign of its divisor, which is what makes this one line correct for negatives.
    function M.yawDelta(a, b)
        local d = ((tonumber(b) or 0) - (tonumber(a) or 0) + 180) % 360 - 180
        -- `% 360` maps exactly-180 to -180; prefer the positive turn so the result is stable under swapping.
        if d <= -180 then d = d + 360 end
        return d
    end

    --- Shortest-arc interpolation between two headings.
    function M.yawLerp(a, b, f)
        return M.normalizeYaw((tonumber(a) or 0) + M.yawDelta(a, b) * (tonumber(f) or 0))
    end

    --- Encode poses for storage or the wire: an array of positional arrays of plain numbers.
    ---
    --- Numbers, not a JSON string: core does no JSON (COMPAT), and the host that writes the row already owns
    --- an encoder. Centimetre on position -- one order finer than the telemetry chunk's 10 cm, because this
    --- one is drawn rather than scored, and 10 cm of lateral error is visible on a car half a lane away.
    function M.encode(poses)
        if type(poses) ~= "table" then return nil, "not_a_table" end
        local out = {}
        for i = 1, #poses do
            local p = poses[i]
            if type(p) ~= "table" then return nil, "pose_not_a_table:" .. i end
            if type(p.t) ~= "number" or type(p.x) ~= "number" or type(p.y) ~= "number" then
                return nil, "missing_fields:" .. i
            end
            out[i] = {
                round(p.t, 3),
                round(p.x, 2), round(p.y, 2), round(p.z or 0, 2),
                round(M.normalizeYaw(p.yaw), 1),
            }
        end
        return out
    end

    --- Decode a stored or received pose list. `format` must be one this build understands.
    ---
    --- Validates on the way in rather than trusting the row: a lap read back from the database has survived
    --- a schema change, a client upload and a JSON round trip since it was written.
    function M.decode(raw, format)
        if format ~= nil and format ~= M.FORMAT then return nil, "unknown_format:" .. tostring(format) end
        if type(raw) ~= "table" then return nil, "not_a_table" end
        if #raw == 0 then return nil, "empty" end
        if #raw > M.MAX_POSES then return nil, "too_many_poses:" .. #raw end
        local out, prevT = {}, nil
        for i = 1, #raw do
            local r = raw[i]
            if type(r) ~= "table" then return nil, "pose_not_a_table:" .. i end
            local p = {}
            for j, name in ipairs(M.POSE_FIELDS) do
                local v = r[j]
                if v ~= nil and type(v) ~= "number" then return nil, "field_type:" .. name .. ":" .. i end
                p[name] = v
            end
            if type(p.t) ~= "number" or type(p.x) ~= "number" or type(p.y) ~= "number" then
                return nil, "missing_fields:" .. i
            end
            p.z = p.z or 0
            p.yaw = M.normalizeYaw(p.yaw)
            -- Time must advance. A ghost whose clock steps backwards would be replayed by `poseAt` picking
            -- whichever bracket it met first, which is a silently wrong line rather than a refusal.
            if prevT and p.t < prevT then return nil, "time_not_monotonic:" .. i end
            prevT = p.t
            out[i] = p
        end
        return out
    end

    --- The pose at `t` seconds into the run, interpolated between the two poses that bracket it.
    ---
    --- Returns nil outside the span, never extrapolated -- the same rule `telemetry.sampleAt` follows and for
    --- the same reason. For a ghost the consequence is concrete: before its start there is no ghost to draw,
    --- and after its finish it must disappear rather than coast on forever in the last direction it was
    --- pointing.
    function M.poseAt(poses, t)
        if type(poses) ~= "table" or #poses == 0 or type(t) ~= "number" then return nil end
        local prev = nil
        for i = 1, #poses do
            local p = poses[i]
            local pt = p and p.t
            if pt then
                if pt == t then
                    return { t = t, x = p.x, y = p.y, z = p.z or 0, yaw = M.normalizeYaw(p.yaw) }
                end
                if pt > t then
                    if not prev then return nil end
                    local span = pt - prev.t
                    if span <= 0 then return nil end
                    local f = (t - prev.t) / span
                    return {
                        t = t,
                        x = (prev.x or 0) + ((p.x or 0) - (prev.x or 0)) * f,
                        y = (prev.y or 0) + ((p.y or 0) - (prev.y or 0)) * f,
                        z = (prev.z or 0) + ((p.z or 0) - (prev.z or 0)) * f,
                        yaw = M.yawLerp(prev.yaw, p.yaw, f),
                    }
                end
                prev = p
            end
        end
        return nil
    end

    --- Run length in milliseconds, from the first pose to the last.
    function M.durationMs(poses)
        if type(poses) ~= "table" or #poses < 2 then return 0 end
        return floor(((poses[#poses].t or 0) - (poses[1].t or 0)) * 1000 + 0.5)
    end

    --- How wrong the replay would be at pose `i` if the stream jumped straight from `a` to `b`.
    ---
    --- Measured the way playback actually works -- interpolated BY TIME, not by distance along the segment --
    --- so the number decimation minimises is the number a viewer would see. Returned as a ratio of the two
    --- tolerances, so position error and heading error can be compared on one scale.
    local function replayError(poses, i, ai, bi, tolM, tolYaw)
        local p, a, b = poses[i], poses[ai], poses[bi]
        local span = (b.t or 0) - (a.t or 0)
        if span <= 0 then return math.huge end
        local f = ((p.t or 0) - (a.t or 0)) / span
        local dx = (a.x or 0) + ((b.x or 0) - (a.x or 0)) * f - (p.x or 0)
        local dy = (a.y or 0) + ((b.y or 0) - (a.y or 0)) * f - (p.y or 0)
        local dz = (a.z or 0) + ((b.z or 0) - (a.z or 0)) * f - (p.z or 0)
        local distErr = sqrt(dx * dx + dy * dy + dz * dz) / tolM
        local yawErr = abs(M.yawDelta(M.yawLerp(a.yaw, b.yaw, f), p.yaw)) / tolYaw
        if yawErr > distErr then return yawErr end
        return distErr
    end

    --- Drop poses the replay does not need. Keeps the first and last always.
    ---
    --- Douglas-Peucker, with an EXPLICIT STACK rather than recursion: the worst case for a 3,000-pose lap is
    --- 3,000 deep, and a core module may not assume the host's stack survives that.
    ---
    --- This is what makes a lap storable. A 100-second lap at 10 Hz is a thousand poses; on a course whose
    --- straights are genuinely straight, most of them say nothing the interpolation would not have said.
    function M.decimate(poses, toleranceM, yawToleranceDeg)
        if type(poses) ~= "table" then return nil, "not_a_table" end
        local n = #poses
        if n <= 2 then
            local copy = {}
            for i = 1, n do copy[i] = poses[i] end
            return copy
        end
        local tolM = tonumber(toleranceM) or M.DEFAULT_TOLERANCE_M
        local tolYaw = tonumber(yawToleranceDeg) or M.DEFAULT_YAW_TOLERANCE_DEG
        if tolM <= 0 then tolM = M.DEFAULT_TOLERANCE_M end
        if tolYaw <= 0 then tolYaw = M.DEFAULT_YAW_TOLERANCE_DEG end

        local keep = {}
        keep[1] = true
        keep[n] = true
        local stack = { { 1, n } }
        while #stack > 0 do
            local seg = stack[#stack]
            stack[#stack] = nil
            local ai, bi = seg[1], seg[2]
            if bi - ai > 1 then
                local worst, worstErr = nil, 1.0
                for i = ai + 1, bi - 1 do
                    local e = replayError(poses, i, ai, bi, tolM, tolYaw)
                    if e > worstErr then worst, worstErr = i, e end
                end
                if worst then
                    keep[worst] = true
                    stack[#stack + 1] = { ai, worst }
                    stack[#stack + 1] = { worst, bi }
                end
            end
        end

        local out = {}
        for i = 1, n do
            if keep[i] then out[#out + 1] = poses[i] end
        end
        return out
    end

    --- Rebase a recorded stream so its first pose sits at t = 0.
    ---
    --- The client records on the server clock it already has; a stored lap must be relative. Done in core so
    --- the recorder and any later importer cannot disagree about which end is zero.
    function M.rebase(poses)
        if type(poses) ~= "table" then return nil, "not_a_table" end
        if #poses == 0 then return nil, "empty" end
        local zero = poses[1].t or 0
        local out = {}
        for i = 1, #poses do
            local p = poses[i]
            out[i] = { t = (p.t or 0) - zero, x = p.x, y = p.y, z = p.z or 0, yaw = M.normalizeYaw(p.yaw) }
        end
        return out
    end

    return M
end)
