-- ncm-core module: space.wormholes
--
-- Doc 58 §5.6: a wormhole is a CONNECTION, not a fast trip. Two mouths -- each a place in the universe with its own
-- motion and orientation -- joined by a throat. Crossing one mouth's threshold puts you at the other, moving the way you
-- were moving relative to the mouth you entered, out of the other mouth's face. Distance between the mouths is not a
-- parameter of anything here: the topology is the point.
--
-- Physical basis: the Morris-Thorne traversable wormhole (Morris & Thorne 1988) -- a real solution of general relativity
-- that needs "exotic" matter (negative energy density) at the throat to stay open. Nothing is known to supply that; the
-- generator that does is NCM's fiction (doc 58 §3). What is modelled: a throat radius, mouths that move (each comoving
-- with something: the vehicle that opened it, a body), a lifetime, stability, and a crossing that maps position,
-- velocity and attitude through the mouth pair exactly (a proper rotation; the throat turns you round so you leave mouth
-- B through its face).
--
-- Reusable infrastructure: the F-I-S-H-I-N-G / Nessie mechanics will place NATURAL wormholes with the same records
-- (`origin = "natural"`, no lifetime). This module is pure; hosts persist records (`save` / `load`) and keep the list.
--
-- A mouth: { p0 = astro pos at utc0, utc0, v = ICRF m/s (linear motion), e1, e2, n = right-handed ICRF unit frame
-- (n = the face's outward normal: you ENTER moving against n, you LEAVE moving along it), body = id it comoves with }.
local Core = NcmCore

Core.define("space.wormholes", function(C)
    local A = C.get("space.astro")
    local V = A.vec
    local M = { version = "0.1.0", OPEN_S = 6.0, COLLAPSE_S = 4.0 }

    local function unit(a) local l = V.len(a); return l > 0 and V.scale(a, 1 / l) or { 0, 0, 1 } end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

    --- A right-handed frame {e1, e2, n} around a face normal n.
    function M.frameFor(n)
        n = unit(n)
        local ref = math.abs(n[3]) < 0.9 and { 0, 0, 1 } or { 1, 0, 0 }
        local e1 = unit(cross(ref, n))
        local e2 = cross(n, e1)
        return e1, e2, n
    end

    --- A mouth at `apos`, moving at `v`, facing `n`, at utc.
    function M.mouth(apos, v, n, utc, body)
        local e1, e2, nn = M.frameFor(n)
        return { p0 = A.copy(apos), utc0 = utc, v = { v[1], v[2], v[3] }, e1 = e1, e2 = e2, n = nn, body = body }
    end

    --- A wormhole record. opts = { id, a = mouth, b = mouth, throatR, openedUtc, lifetimeS (nil: permanent), origin,
    --- owner, stability, returnable, dest, tag }
    function M.create(opts)
        return {
            id = opts.id, a = opts.a, b = opts.b, throatR = opts.throatR or 15, openedUtc = opts.openedUtc,
            lifetimeS = opts.lifetimeS, openS = opts.openS or M.OPEN_S, collapseS = opts.collapseS or M.COLLAPSE_S,
            origin = opts.origin or "artificial", owner = opts.owner, stability = opts.stability or 1,
            returnable = opts.returnable ~= false, dest = opts.dest, tag = opts.tag, transits = 0,
        }
    end

    --- Where mouth `side` ("a" | "b") is at utc: astro pos, velocity, normal.
    function M.where(w, side, utc)
        local m = w[side]
        return A.offset(m.p0, V.scale(m.v, utc - m.utc0)), m.v, m.n
    end

    --- The wormhole's phase at utc: "opening" | "open" | "collapsing" | "closed", aperture radius (m), 0..1 progress of
    --- the phase.
    function M.phase(w, utc)
        local age = utc - (w.openedUtc or utc)
        if age < 0 then return "closed", 0, 0 end
        if w.closedUtc and utc >= w.closedUtc then return "closed", 0, 1 end
        if age < w.openS then
            local k = age / w.openS
            return "opening", w.throatR * k * k * (3 - 2 * k), k
        end
        local life = w.lifetimeS
        if w.collapseUtc then life = math.min(life or math.huge, w.collapseUtc - (w.openedUtc or 0)) end
        if life then
            if age >= life + w.collapseS then return "closed", 0, 1 end
            if age >= life then
                local k = (age - life) / w.collapseS
                return "collapsing", w.throatR * (1 - k) ^ 2, k
            end
        end
        return "open", w.throatR, 1
    end

    function M.alive(w, utc) return (M.phase(w, utc)) ~= "closed" end

    --- Did a point moving from apos0 (utc0) to apos1 (utc1) cross a mouth's threshold (against its face normal, inside
    --- the aperture)? Returns side, fraction of the step, offset in the mouth's plane (m) -- or nil.
    function M.crossing(w, apos0, apos1, utc0, utc1)
        local _, r1 = M.phase(w, utc1)
        if r1 <= 0 then return nil end
        for _, side in ipairs({ "a", "b" }) do
            if side == "a" or w.returnable then
                local m = w[side]
                local h0 = dot(A.delta(apos0, (M.where(w, side, utc0))), m.n)
                local d1 = A.delta(apos1, (M.where(w, side, utc1)))
                local h1 = dot(d1, m.n)
                if h0 >= 0 and h1 < 0 then
                    local d0 = A.delta(apos0, (M.where(w, side, utc0)))
                    local f = h0 / (h0 - h1)
                    local rc = V.add(d0, V.scale(V.sub(d1, d0), f))
                    local perp = V.sub(rc, V.scale(m.n, dot(rc, m.n)))
                    local off = V.len(perp)
                    if off <= r1 then return side, f, off end
                end
            end
        end
        return nil
    end

    --- The proper rotation taking mouth X's frame to mouth Y's, turned round: e1 -> e1', e2 -> -e2', n -> -n'.
    local function mapping(x, y)
        local cols = { y.e1, V.scale(y.e2, -1), V.scale(y.n, -1) }   -- images of x.e1, x.e2, x.n
        local rows = { x.e1, x.e2, x.n }
        local R = { {}, {}, {} }
        for i = 1, 3 do for j = 1, 3 do
            R[i][j] = cols[1][i] * rows[1][j] + cols[2][i] * rows[2][j] + cols[3][i] * rows[3][j]
        end end
        return R
    end
    M.mapping = mapping
    local function mv(R, v) return { R[1][1] * v[1] + R[1][2] * v[2] + R[1][3] * v[3], R[2][1] * v[1] + R[2][2] * v[2] + R[2][3] * v[3], R[3][1] * v[1] + R[3][2] * v[2] + R[3][3] * v[3] } end
    local function mm(P, Q)
        local o = { {}, {}, {} }
        for i = 1, 3 do for j = 1, 3 do o[i][j] = P[i][1] * Q[1][j] + P[i][2] * Q[2][j] + P[i][3] * Q[3][j] end end
        return o
    end

    --- Through the throat from `side`: astro pos, ICRF velocity and attitude (rows matrix, ICRF axes) of something that
    --- has just crossed mouth `side` at utc -> the same on the other side.
    function M.transit(w, side, apos, avel, rot, utc)
        local other = side == "a" and "b" or "a"
        local x, y = w[side], w[other]
        local px, vx = M.where(w, side, utc)
        local py, vy = M.where(w, other, utc)
        local R = mapping(x, y)
        local r = mv(R, A.delta(apos, px))
        local v = V.add(vy, mv(R, V.sub(avel, vx)))
        w.transits = (w.transits or 0) + 1
        return A.offset(py, r), v, rot and mm(R, rot) or nil, other
    end

    --- JSON-safe copy and back.
    local function saveMouth(m)
        return { p0 = { c = { m.p0.c[1], m.p0.c[2], m.p0.c[3] }, o = { m.p0.o[1], m.p0.o[2], m.p0.o[3] } }, utc0 = m.utc0,
                 v = { m.v[1], m.v[2], m.v[3] }, e1 = m.e1, e2 = m.e2, n = m.n, body = m.body }
    end
    function M.save(w)
        local out = {}
        for k, v in pairs(w) do if k ~= "a" and k ~= "b" then out[k] = v end end
        out.a, out.b = saveMouth(w.a), saveMouth(w.b)
        return out
    end
    function M.load(t)
        if type(t) ~= "table" or type(t.a) ~= "table" or type(t.b) ~= "table" then return nil end
        local w = {}
        for k, v in pairs(t) do w[k] = v end
        for _, s in ipairs({ "a", "b" }) do
            local m = t[s]
            w[s] = { p0 = A.fromParts(m.p0.c, m.p0.o), utc0 = m.utc0, v = m.v, e1 = m.e1, e2 = m.e2, n = m.n, body = m.body }
        end
        return w
    end

    -- ------------------------------------------------------------------------------------------- the registry
    -- Hosts keep the list (and persist it); every wormhole in it can be crossed by anything that flies.
    local list = {}
    function M.add(w) list[w.id] = w; return w end
    function M.get(id) return list[id] end
    function M.remove(id) list[id] = nil end
    function M.active(utc)
        local out = {}
        for _, w in pairs(list) do if not utc or M.alive(w, utc) then out[#out + 1] = w end end
        table.sort(out, function(p, q) return tostring(p.id) < tostring(q.id) end)
        return out
    end
    function M.prune(utc) for id, w in pairs(list) do if not M.alive(w, utc) then list[id] = nil end end end

    return M
end)
