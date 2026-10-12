-- ncm-core module: space.frames
--
-- The frame a Deep vehicle is INTEGRATED in (doc 57 §5.3), and the exact conversions between frames. A frame is:
--   nil / { kind = "earth_fixed" }            space.deep's rotating ECEF (x through 0 N 0 E). Near home: atmosphere,
--                                             guidance, landing and every Earth-relative display live here.
--   { kind = "inertial", body = id }          ICRF axes, centred on a catalogue body, NOT rotating. The centre falls
--                                             freely, so the field felt is the third-body form (space.gravity.relative).
--   { kind = "inertial", anchor = astropos,   ICRF axes, centred on a fixed astronomical position (cell + offset) --
--     body = id }                             between the stars, where no body is a sensible origin. `body` names the
--                                             system for display only.
-- A switch between frames changes coordinates, never the physical state: position, velocity and attitude are carried
-- over exactly (to double rounding). Every host keeps reading Earth-fixed p/v/basis through `mirror` (an exact
-- conversion), so a frame change is invisible to HUDs, the Deep page and guidance.
--
-- POLICY (`update`, called by engineering.flightmodel every few simulated seconds):
--   earth_fixed -> inertial(home)  beyond SWITCH_OUT from home's centre (the rotating frame's fictitious terms grow
--                                  with distance: wr is 58 km/s at 800,000 km and 11,000 km/s at 1 AU)
--   inertial(home) -> earth_fixed  back inside SWITCH_IN (hysteresis), or whenever the host asks (`opts.earthFixed`:
--                                  guidance, landing)
--   inertial(A) -> inertial(B)     when the sphere of influence (space.catalogue.soi) changes body
--   -> anchor                      more than ANCHOR_M from the centre of a ROOT body (a star, a black hole): positions
--                                  relative to a body light-years away would lose metres; an anchor keeps them small
local Core = NcmCore

Core.define("space.frames", function(C)
    local A = C.get("space.astro")
    local Cat = C.get("space.catalogue")
    local V = A.vec
    local M = { version = "0.1.0", SWITCH_OUT = 1.0e9, SWITCH_IN = 0.8e9, ANCHOR_M = 1.0e13 }

    -- doc 58: a frame centred on a star the host's catalogue does not hold (the client has no star catalogue; the server
    -- flew the Machine there) resolves through the drives' nav set
    local function rec(id)
        local r = Cat.get(id)
        if r then return r end
        local ok, Dm = pcall(C.get, "space.drives")
        return ok and Dm and Dm.record and Dm.record(id) or nil
    end
    M.rec = rec

    local homeRec
    local function home()
        if homeRec then return homeRec end
        for _, r in ipairs(Cat.list()) do if r.home then homeRec = r end end
        return homeRec
    end
    M.home = home

    function M.kind(frame) return (type(frame) == "table" and frame.kind) or "earth_fixed" end
    function M.isEarthFixed(frame) return M.kind(frame) == "earth_fixed" end
    function M.key(frame)
        if M.isEarthFixed(frame) then return "earth_fixed" end
        if frame.anchor then local a = frame.anchor; return ("anchor:%d:%d:%d:%.3f:%.3f:%.3f"):format(a.c[1], a.c[2], a.c[3], a.o[1], a.o[2], a.o[3]) end
        return "inertial:" .. tostring(frame.body)
    end

    --- The frame's centre at utc: astro position, velocity (heliocentric inertial, ICRF).
    function M.centre(frame, utc)
        Cat.load()
        if M.isEarthFixed(frame) then return Cat.stateAt(home(), utc) end
        if frame.anchor then return frame.anchor, { 0, 0, 0 } end
        return Cat.stateAt(rec(frame.body) or frame.body, utc)
    end

    local function rotRows(R, th)
        -- columns are the basis vectors: turn each column about z by th
        local c, s = math.cos(th), math.sin(th)
        local out = { {}, {}, {} }
        for j = 1, 3 do
            local x, y, z = R[1][j], R[2][j], R[3][j]
            out[1][j], out[2][j], out[3][j] = c * x - s * y, s * x + c * y, z
        end
        return out
    end

    --- Astronomical state of a dynamics state (pos/vel in `s.frame`) at utc: astro pos, velocity (ICRF, heliocentric).
    function M.toAstro(s, utc)
        if M.isEarthFixed(s.frame) then
            local Rh, Vh = Cat.stateAt(home(), utc)
            local pi, vi = A.ecefToEci(s.pos, s.vel, utc)
            return A.offset(Rh, pi), V.add(Vh, vi)
        end
        local Rc, Vc = M.centre(s.frame, utc)
        return A.offset(Rc, s.pos), V.add(Vc, s.vel)
    end

    --- Put a dynamics state into `frame` (exact). Mutates s.pos, s.vel, s.rot, s.frame.
    function M.convert(s, frame, utc)
        if M.key(s.frame) == M.key(frame) then return s end
        local apos, avel = M.toAstro(s, utc)
        local R = s.rot
        if M.isEarthFixed(s.frame) then R = rotRows(R, A.gmst(utc)) end          -- basis: Earth-fixed -> ICRF axes
        if M.isEarthFixed(frame) then
            local Rh, Vh = Cat.stateAt(home(), utc)
            local pe, ve = A.eciToEcef(A.delta(apos, Rh), V.sub(avel, Vh), utc)
            s.pos, s.vel, s.rot, s.frame = pe, ve, rotRows(R, -A.gmst(utc)), nil
        else
            local Rc, Vc = M.centre(frame, utc)
            s.pos, s.vel, s.rot, s.frame = A.delta(apos, Rc), V.sub(avel, Vc), R, frame
        end
        s.gcache = nil
        return s
    end

    --- Earth-fixed p, v, basis of a dynamics state: what every Earth-relative reader keeps using.
    function M.mirror(s, utc)
        if M.isEarthFixed(s.frame) then return s.pos, s.vel, s.rot end
        local apos, avel = M.toAstro(s, utc)
        local Rh, Vh = Cat.stateAt(home(), utc)
        local pe, ve = A.eciToEcef(A.delta(apos, Rh), V.sub(avel, Vh), utc)
        return pe, ve, rotRows(s.rot, -A.gmst(utc))
    end

    --- The switching policy (see header). opts = { earthFixed = true } forces the home Earth-fixed frame.
    --- Returns the new frame key when it switched.
    function M.update(s, utc, opts)
        Cat.load()
        local h = home()
        if opts and opts.earthFixed then
            if not M.isEarthFixed(s.frame) then M.convert(s, nil, utc); return "earth_fixed" end
            return nil
        end
        local apos = M.toAstro(s, utc)
        local soi = Cat.soi(apos, utc)
        if M.isEarthFixed(s.frame) then
            -- leave the rotating frame when far from home, or on entering another body's sphere (the Moon's ~66,000 km)
            if V.len(s.pos) > M.SWITCH_OUT or soi.id ~= h.id then
                M.convert(s, { kind = "inertial", body = soi.id }, utc); return M.key(s.frame)
            end
            return nil
        end
        local fb = s.frame.body
        if not s.frame.anchor and fb == h.id and soi.id == h.id and V.len(s.pos) < M.SWITCH_IN then
            M.convert(s, nil, utc); return "earth_fixed"
        end
        local rootBody = soi.parent == nil
        if rootBody then
            -- a star / black hole: centred on it while close, anchored once far from it
            local Rs = Cat.stateAt(soi, utc)
            local d = A.distance(apos, Rs)
            if d > M.ANCHOR_M then
                local need = not s.frame.anchor or V.len(s.pos) > M.ANCHOR_M or s.frame.body ~= soi.id
                if need then M.convert(s, { kind = "inertial", anchor = A.copy(apos), body = soi.id }, utc); return M.key(s.frame) end
                return nil
            end
        end
        if s.frame.anchor or fb ~= soi.id then
            M.convert(s, { kind = "inertial", body = soi.id }, utc); return M.key(s.frame)
        end
        return nil
    end

    -- ------------------------------------------------------------------------------------------------ drives (doc 58)
    -- The experimental drives move a state by something other than its own velocity: a warp field's drift, an
    -- Alcubierre bubble's x_s(t), a jump, a wormhole crossing. Each goes through one of these, never by writing
    -- s.pos directly, so a state stays exactly where the substrate says it is in whichever frame it is integrated.

    --- Leave the rotating Earth-fixed frame (exact): an inertial frame on home, or `frame` when given. A drive that moves
    --- a state faster than the rotating frame's fictitious terms make sense calls this first.
    function M.toInertial(s, utc, frame)
        if not M.isEarthFixed(s.frame) and not frame then return s end
        M.convert(s, frame or { kind = "inertial", body = home().id }, utc)
        s.altAt = nil
        return s
    end

    --- Put a state at astro position `apos` with ICRF velocity `avel` WITHOUT changing its frame (the frame must be
    --- inertial: its axes are ICRF). The drift of a continuous drive. Attitude is untouched.
    function M.place(s, apos, avel, utc)
        if M.isEarthFixed(s.frame) then M.toInertial(s, utc) end
        local Rc, Vc = M.centre(s.frame, utc)
        s.pos = A.delta(apos, Rc)
        if avel then s.vel = V.sub(avel, Vc) end
        s.gcache, s.altAt = nil, nil
        return s
    end

    --- Discontinuous translation (a jump, a wormhole crossing): the state is at `apos` moving at ICRF `avel`, attitude
    --- `rot` (ICRF axes; default: kept), in whatever frame the policy picks THERE. Returns the new frame key.
    function M.translate(s, apos, avel, utc, rot)
        Cat.load()
        M.toInertial(s, utc, { kind = "inertial", anchor = A.copy((M.toAstro(s, utc))), body = "translate" })   -- rot -> ICRF axes
        local sys = Cat.system(apos, utc)
        s.frame = { kind = "inertial", anchor = A.copy(apos), body = sys and sys.id or "sun" }
        s.pos, s.vel = { 0, 0, 0 }, { avel[1], avel[2], avel[3] }
        if rot then s.rot = { { rot[1][1], rot[1][2], rot[1][3] }, { rot[2][1], rot[2][2], rot[2][3] }, { rot[3][1], rot[3][2], rot[3][3] } } end
        s.gcache, s.altAt = nil, nil
        M.update(s, utc)
        return M.key(s.frame)
    end

    -- ------------------------------------------------------------------------------------------------ gravity in a frame
    -- The field felt by a state in its own frame, split in two: the frame's own body (or, anchored, the strongest
    -- contributor) EXACT every step, everything else from a cache refreshed every `refresh` simulated seconds -- short
    -- near a perturber (2 % of the time to cross its distance), at most MAX_REFRESH. The cache keeps a host's
    -- per-call instruction budget (OPEN//77) safe without approximating the term that dominates.
    M.MAX_REFRESH, M.MIN_REFRESH = 120, 0.5
    local G = nil
    local function grav() G = G or C.get("space.gravity"); return G end

    local function refreshRest(s, utc)
        local Gr = grav()
        local h = home()
        local apos = M.toAstro(s, utc)
        local list = Gr.contributors(apos, utc)
        local rest, exactId, exactR, dmin = { 0, 0, 0 }, nil, nil, math.huge
        local earthFixed = M.isEarthFixed(s.frame)
        local centreId = earthFixed and h.id or (not s.frame.anchor and s.frame.body or nil)
        if not centreId and list[1] then exactId, exactR = list[1].rec.id, list[1].R end   -- anchored: strongest is exact
        local Rc = centreId and Cat.stateAt(rec(centreId) or centreId, utc) or nil
        for _, c in ipairs(list) do
            if c.rec.id ~= centreId and c.rec.id ~= exactId then
                local a = Gr.pull(c.rec.gm, apos, c.R)
                if Rc then a = V.sub(a, Gr.pull(c.rec.gm, Rc, c.R)) end              -- third-body form for body frames
                rest = V.add(rest, V.scale(a, c.w))
                if c.d < dmin then dmin = c.d end
            elseif c.rec.id == exactId then
                exactR = c.R
            end
        end
        if earthFixed then rest = A.eciToEcefVec(rest, utc) end
        local speed = V.len(s.vel or { 0, 0, 0 })
        local refresh = math.max(M.MIN_REFRESH, math.min(M.MAX_REFRESH, 0.02 * dmin / math.max(speed, 1)))
        s.gcache = { key = M.key(s.frame), at = utc, refresh = refresh, rest = rest, exactId = exactId, exactR = exactR,
                     exactGm = exactId and rec(exactId).gm or nil, centreGm = centreId and (rec(centreId) or {}).gm or nil }
        return s.gcache
    end

    --- Gravity felt by dynamics state s at utc, in s.frame's axes (Earth-fixed: WITHOUT the rotating-frame terms,
    --- which engineering.flightmodel adds as before).
    function M.accel(s, utc)
        local gc = s.gcache
        if not gc or gc.key ~= M.key(s.frame) or math.abs(utc - gc.at) >= gc.refresh then gc = refreshRest(s, utc) end
        local p = s.pos
        local r = V.len(p)
        if gc.centreGm then
            -- the frame's own body, exact: -GM p / r^3 (Earth-fixed: the same term space.deep.gravity always applied)
            return V.add(V.scale(p, -gc.centreGm / (r * r * r)), gc.rest)
        end
        -- anchored: the strongest contributor exact, at its (fixed for a star) position relative to the anchor
        local a = gc.rest
        if gc.exactId then
            local d = V.sub(A.delta(gc.exactR, s.frame.anchor), p)
            local d2 = V.dot(d, d)
            a = V.add(a, V.scale(d, gc.exactGm / (d2 * math.sqrt(d2))))
        end
        return a
    end

    --- JSON-safe copy of a frame for a record.
    function M.save(frame)
        if M.isEarthFixed(frame) then return nil end
        local out = { kind = "inertial", body = frame.body }
        if frame.anchor then out.anchor = { c = { frame.anchor.c[1], frame.anchor.c[2], frame.anchor.c[3] }, o = { frame.anchor.o[1], frame.anchor.o[2], frame.anchor.o[3] } } end
        return out
    end
    function M.load_(t)
        if type(t) ~= "table" or t.kind ~= "inertial" then return nil end
        local f = { kind = "inertial", body = t.body }
        if type(t.anchor) == "table" and t.anchor.c and t.anchor.o then f.anchor = A.fromParts(t.anchor.c, t.anchor.o) end
        return f
    end

    return M
end)
