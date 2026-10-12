-- ncm-core module: space.sprint
--
-- SPRINT (L322; doc 54 §L): the 100-metre dash of Snowglobe. A start plane, a finish plane D metres ahead, racers side
-- by side in lanes. Five lights. Go. First across the finish plane wins. No orbit, no maze, no trajectory puzzle.
--
-- Geometry lives in a venue FRAME (`space.course`: an anchor frame over a city, or a station's co-moving LVLH frame):
-- local y is the race direction, the start plane is y = 0, the finish plane y = D, lanes are offsets in local x. A
-- `vertical` sprint uses an anchor frame turned so local y is UP: the grid stands on the ground and the finish is a
-- horizontal plane at altitude D.
--
-- TIMING belongs to NCM universe space. Hosts sample universe positions (the Snowglobe frame's `u`, or
-- `cityToUniverse` below the doorway); a floating-origin rebase moves only the local origin, so a sample pair that
-- straddles a rebase is still two universe positions and times correctly.
-- PHOTO FINISH: the crossing instant is solved inside the sample interval by CUBIC HERMITE interpolation from both
-- samples' positions AND velocities (not a straight line between two 60 Hz polls), to well under a millisecond;
-- results keep the solved time and order by it; |dt| below `deadHeatS` is a declared dead heat.
local Core = NcmCore

Core.define("space.sprint", function(C)
    local M = { version = "0.1.0" }
    local Course = C.get("space.course")

    -- reactVelMs: the reaction is the first sample after lights out moving forward faster than this (m/s)
    M.DEFAULTS = { laneSpacingM = 12, jump = "penalty", jumpPenaltyS = 5, deadHeatS = 1e-4, reactVelMs = 0.5 }

    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

    --- rules = { distanceM, lanes, startT (lights out, s), frame = frame or function(t) -> frame, laneSpacingM?, ... }
    function M.rules(r)
        local out = {}
        for k, v in pairs(M.DEFAULTS) do out[k] = v end
        for k, v in pairs(r) do out[k] = v end
        return out
    end

    --- A vertical frame over an anchor: local x east, local y UP (the race direction), local z south (right-handed).
    function M.verticalFrame(anchor, groundAltM)
        local f = Course.anchorFrame(anchor, groundAltM or 0)
        return { origin = f.origin, x = f.x, y = f.z, z = { -f.y[1], -f.y[2], -f.y[3] }, kind = "vertical" }
    end

    --- Lane i's grid spot in the frame's local coordinates (centred lanes).
    function M.laneSpot(rules, i)
        local off = (i - (rules.lanes + 1) / 2) * rules.laneSpacingM
        return { off, 0, 0 }
    end

    local function frameAt(rules, t)
        if type(rules.frame) == "function" then return rules.frame(t) end
        return rules.frame
    end

    function M.newState() return { finishT = nil, jumped = false, reactT = nil, last = nil } end

    --- The time in [t0, t1] where a cubic Hermite through (t0, y0, v0) and (t1, y1, v1) reaches y = target.
    function M.solveCrossing(t0, y0, v0, t1, y1, v1, target)
        local h = t1 - t0
        local function y(s)
            local s2, s3 = s * s, s * s * s
            return (2 * s3 - 3 * s2 + 1) * y0 + (s3 - 2 * s2 + s) * h * v0 + (-2 * s3 + 3 * s2) * y1 + (s3 - s2) * h * v1
        end
        local lo, hi = 0, 1
        for _ = 1, 60 do
            local mid = (lo + hi) / 2
            if y(mid) < target then lo = mid else hi = mid end
        end
        return t0 + h * (lo + hi) / 2
    end

    --- Advance a racer's judge with a universe sample. Returns an event: { jumped }, { reacted = t }, { finished = t }.
    function M.step(rules, st, t, pos, vel)
        if st.finishT then return st, nil end
        local f = frameAt(rules, t)
        local l = Course.toLocal(f, pos)
        local vy = dot(vel, f.y)
        local ev
        if t < rules.startT and l[2] > 0.5 and not st.jumped then
            st.jumped, ev = true, { jumped = true }
        end
        if not st.reactT and t >= rules.startT and vy > rules.reactVelMs then
            st.reactT, ev = t, ev or { reacted = t - rules.startT }
        end
        local last = st.last
        if last and last.y < rules.distanceM and l[2] >= rules.distanceM then
            st.finishT = M.solveCrossing(last.t, last.y, last.vy, t, l[2], vy, rules.distanceM)
            ev = { finished = st.finishT }
        end
        st.last = { t = t, y = l[2], vy = vy, x = l[1] }
        return st, ev
    end

    --- L323 clock sync for a fair photo finish. samples = { {clientSend, serverT, clientRecv} } (seconds): each a ping
    --- answered with the server's race time. The best estimate is the minimum round trip's: offset = serverT + rtt/2 -
    --- clientRecv, so serverTime(clientT) = clientT + offset. Returns offset, rtt (s).
    function M.clockOffset(samples)
        local best
        for _, s in ipairs(samples) do
            local rtt = s.clientRecv - s.clientSend
            if rtt >= 0 and (not best or rtt < best.rtt) then best = { rtt = rtt, s = s } end
        end
        if not best then return nil end
        return best.s.serverT + best.rtt / 2 - best.s.clientRecv, best.rtt
    end

    --- Classification: { {id, state} } -> rows with position, raceS (from lights out, with any jump penalty), deadHeat.
    function M.classify(rules, entries)
        local rows = {}
        for _, e in ipairs(entries) do
            local s = e.state
            local raceS = s.finishT and (s.finishT - rules.startT + ((s.jumped and rules.jump == "penalty") and rules.jumpPenaltyS or 0))
            local dq = s.jumped and rules.jump == "dq"
            rows[#rows + 1] = { id = e.id, raceS = (not dq) and raceS or nil, dq = dq or nil, jumped = s.jumped,
                reactS = s.reactT and (s.reactT - rules.startT) or nil, reachedM = s.last and s.last.y or 0 }
        end
        table.sort(rows, function(a, b)
            if (a.raceS ~= nil) ~= (b.raceS ~= nil) then return a.raceS ~= nil end
            if a.raceS and b.raceS and a.raceS ~= b.raceS then return a.raceS < b.raceS end
            if not a.raceS and a.reachedM ~= b.reachedM then return a.reachedM > b.reachedM end
            return tostring(a.id) < tostring(b.id)
        end)
        for i, r in ipairs(rows) do
            r.position = i
            local prev = rows[i - 1]
            if prev and r.raceS and prev.raceS and math.abs(r.raceS - prev.raceS) < rules.deadHeatS then
                r.deadHeat, prev.deadHeat = true, true
                r.position = prev.position
            end
        end
        return rows
    end

    return M
end)
