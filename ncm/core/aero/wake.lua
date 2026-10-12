-- ncm-core module: aero.wake
-- The aerodynamic wake: a PHENOMENON, not a product (L356).
--
-- A moving car leaves a pocket of slow, low-pressure air behind it. A car that drives inside that pocket meets less
-- air and so less aerodynamic drag. That is all this file knows. It does not know about the Slipstream Module, about
-- HUDs, players or NPCs: removing every module in Night City must not make the universe forget that wakes exist.
-- `aero.slipstream` (the technology that detects and exploits a wake) is built on top of this.
--
-- Geometry (one convention for every host, the same as the old carrier_bridge check and `Open77.vehicles` headings):
--   heading in degrees, forward = (cos h, sin h) in the x/y plane; positions in metres; speeds in m/s.
--
-- The wake's QUALITY q in [0, 1] is a product of continuous terms -- there is no "is behind -> +10%" step anywhere:
--   speed  : no wake worth having below `minSpeed`, full by `fullSpeed` (the leader's speed makes the wake)
--   length : rises from bumper-overlap to a peak a few metres back, then decays; the wake is longer at speed
--   lateral: a Gaussian across the leader's centreline that widens with distance (the wake spreads as it decays)
--   align  : both cars must be travelling the same way (the wake trails the leader's velocity, not its position)
-- Drag relief is a fraction of the follower's aerodynamic drag, and drag is computed from a drag area (CdA), so the
-- relief FORCE is mass-free and grows with v^2 exactly as drag does: a strong high-speed wake is worth far more than
-- a slow one, and leaving the wake removes it continuously.
local Core = NcmCore

Core.define("aero.wake", function(C)
    local M = { version = "0.1.0" }

    --- Every tunable in one place (doc: DECISION_RECORD L356). Hosts may override per server; tests pin them.
    M.CONFIG = {
        minSpeed = 14,          -- m/s (~50 km/h): below this a wake is not worth having
        fullSpeed = 32,         -- m/s (~115 km/h): the speed term is 1 from here
        carLengthM = 4.6,       -- closer than this (centre to centre) the cars overlap: no wake to sit in
        peakM = 8,              -- centre-to-centre gap where the pocket is strongest
        baseLengthM = 20,       -- the wake's 1/e decay length at minSpeed...
        lengthPerMps = 0.55,    -- ...growing with the leader's speed (a 50 m/s leader trails a ~40 m decay)
        maxLengthM = 90,        -- nothing beyond this is a wake
        halfWidthM = 0.8,       -- lateral sigma right behind the leader (a ~1.9 m car: its core)...
        spreadPerM = 0.035,     -- ...widening with distance (1.15 m at 10 m, 1.85 m at 30 m)
        alignFullDeg = 6,       -- heading difference with full alignment...
        alignZeroDeg = 32,      -- ...and with none
        rho = 1.2,              -- air density, kg/m^3
        cdA = 0.75,             -- the follower's drag area, m^2 (a sports car; per-vehicle data may replace it)
        naturalReliefMax = 0.15 -- the share of drag a perfectly placed car sheds with NO technology
    }

    local atan2 = math.atan2 or math.atan   -- LuaJIT has atan2; Lua 5.4's atan takes (y, x)
    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
    local function smooth(e0, e1, x)
        if e1 == e0 then return x >= e1 and 1 or 0 end
        local t = clamp((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)
    end
    M._smooth = smooth

    local function cfg(o) return o or M.CONFIG end

    --- Relative geometry of `follower` to `leader`. Each is { x, y, heading (deg), speed (m/s) }.
    --- Returns { ahead (m, + = leader is ahead along the follower's heading), lateral (m, signed, + = leader to the
    --- left), headingDiff (deg, 0..180), leaderSpeed, followerSpeed } or nil when a field is missing.
    function M.geometry(follower, leader)
        local fx, fy, fh = tonumber(follower and follower.x), tonumber(follower and follower.y), tonumber(follower and follower.heading)
        local lx, ly, lh = tonumber(leader and leader.x), tonumber(leader and leader.y), tonumber(leader and leader.heading)
        if not (fx and fy and fh and lx and ly and lh) then return nil end
        -- the wake trails the LEADER: measure the follower in the leader's frame (its centreline is the wake's)
        local r = math.rad(lh)
        local ux, uy = math.cos(r), math.sin(r)
        local dx, dy = lx - fx, ly - fy
        local ahead = dx * ux + dy * uy
        local lateral = -dx * uy + dy * ux
        local diff = math.abs(((fh - lh) + 180) % 360 - 180)
        return { ahead = ahead, lateral = lateral, headingDiff = diff,
            leaderSpeed = tonumber(leader.speed) or 0, followerSpeed = tonumber(follower.speed) or 0 }
    end

    --- The wake's length scale (m) behind a leader at `speed`.
    function M.lengthM(speed, o)
        o = cfg(o)
        return math.min(o.maxLengthM, o.baseLengthM + o.lengthPerMps * math.max(0, (speed or 0) - o.minSpeed))
    end

    --- Quality of the wake at a relative geometry: q in [0, 1] plus its terms (for instrumentation and the HUD).
    function M.quality(g, o)
        o = cfg(o)
        if not g then return 0, nil end
        local terms = {}
        terms.speed = smooth(o.minSpeed, o.fullSpeed, math.min(g.leaderSpeed or 0, g.followerSpeed or 0))
        local d = g.ahead or -1
        local L = M.lengthM(g.leaderSpeed, o)
        if d <= o.carLengthM or d > o.maxLengthM then
            terms.length = 0
        elseif d <= o.peakM then
            terms.length = smooth(o.carLengthM, o.peakM, d)
        else
            -- decays, and fades to nothing over the last quarter of its reach (a hard end would be a step)
            terms.length = math.exp(-(d - o.peakM) / L) * (1 - smooth(o.maxLengthM * 0.75, o.maxLengthM, d))
        end
        local sigma = o.halfWidthM + o.spreadPerM * math.max(0, d)
        local lat = (g.lateral or 0) / sigma
        terms.lateral = math.abs(lat) > 3 and 0 or math.exp(-0.5 * lat * lat)
        terms.align = 1 - smooth(o.alignFullDeg, o.alignZeroDeg, g.headingDiff or 180)
        local q = terms.speed * terms.length * terms.lateral * terms.align
        if q < 1e-4 then q = 0 end
        return q, terms
    end

    --- Aerodynamic drag (N) on the follower at `speed` (m/s): 0.5 rho CdA v^2.
    function M.dragN(speed, o, cdA)
        o = cfg(o)
        local v = math.max(0, speed or 0)
        return 0.5 * o.rho * (cdA or o.cdA) * v * v
    end

    --- The natural (no technology) share of drag shed at quality q.
    function M.naturalRelief(q, o)
        return cfg(o).naturalReliefMax * clamp(q or 0, 0, 1)
    end

    --- Pick the best wake for `follower` among `others` (each { id, x, y, heading, speed }). Returns
    --- { id, q, terms, geometry } of the strongest, or nil. Ties break on id so the choice never flickers.
    function M.best(follower, others, o)
        local best
        for _, other in ipairs(others or {}) do
            local g = M.geometry(follower, other)
            local q, terms = M.quality(g, o)
            if q > 0 and (not best or q > best.q or (q == best.q and tostring(other.id) < tostring(best.id))) then
                best = { id = other.id, q = q, terms = terms, geometry = g }
            end
        end
        return best
    end

    --- A vehicle snapshot in this file's shape from an `Open77.vehicles.get` table. The direction of travel comes
    --- from the VELOCITY whenever the car is moving: the wake trails where a car goes, not where its nose points,
    --- and a velocity needs no heading convention (the old carrier_bridge check assumed one and was never verified
    --- live). The snapshot's heading is used only below `MIN_VEL_SPEED`.
    M.MIN_VEL_SPEED = 2
    function M.fromSnapshot(id, s)
        if type(s) ~= "table" then return nil end
        local p = s.position or s
        local x, y = tonumber(p.x), tonumber(p.y)
        if not (x and y) then return nil end
        local v = s.velocity
        local vx, vy = type(v) == "table" and tonumber(v.x or v[1]) or nil, type(v) == "table" and tonumber(v.y or v[2]) or nil
        local speed = tonumber(s.speed)
        local h
        if vx and vy and math.sqrt(vx * vx + vy * vy) >= M.MIN_VEL_SPEED then
            h = math.deg(atan2(vy, vx))
            speed = speed or math.sqrt(vx * vx + vy * vy)
        else
            h = tonumber(s.heading or s.yaw)
        end
        if not h then return nil end
        return { id = id, x = x, y = y, heading = h, speed = speed or 0 }
    end

    --- The same shape from two positions `dt` seconds apart (a host that only has positions, e.g. a 250 ms sample).
    function M.fromPositions(id, prev, cur, dt)
        if type(prev) ~= "table" or type(cur) ~= "table" or not dt or dt <= 0 then return nil end
        local vx, vy = (cur.x - prev.x) / dt, (cur.y - prev.y) / dt
        return M.fromSnapshot(id, { position = cur, velocity = { x = vx, y = vy }, speed = math.sqrt(vx * vx + vy * vy) })
    end

    return M
end)
