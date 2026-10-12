-- ncm-core module: space.gravity
--
-- Multi-body gravity from catalogue data (doc 57 §2). No body is named here: a record pulls because it has `gm`.
--
-- THE FIELD at a point is   a = SUM_i w_i * GM_i * (R_i - r) / |R_i - r|^3
-- over the RELEVANT records. Relevance is the acceleration a body would exert there, ACC_i = GM_i / d_i^2, against a
-- floor EPS (default 1e-11 m/s^2 -- one micrometre per second squared over a day). A body is only *evaluated* when it
-- could reach EPS: d <= sqrt(GM/EPS) (pruning), and its weight w ramps smoothly from 0 at EPS to 1 at 2*EPS, so the
-- field is continuous everywhere -- there is no Earth-to-Sun boundary, no sphere-of-influence switch, no step.
-- Candidates are hierarchical so the work stays small at any scale: the registered records (Solar System today,
-- moons only near their parent), plus catalogue stars from the spatial grid within the widest radius any star could
-- reach EPS from.
--
-- A FRAME CENTRED ON A BODY B (the way vehicles fly: Earth-fixed today) feels the same field minus the field at B's
-- centre -- the classic third-body ("tidal") form -- with B's own pull kept whole:
--     a_rel = GM_B (R_B - r)/|R_B - r|^3 + SUM_{i != B} w_i GM_i [ (R_i - r)/|R_i - r|^3 - (R_i - R_B)/|R_i - R_B|^3 ]
-- `ecefPerturbation` returns exactly the SUM (Earth-fixed axes) for space.deep's frame, whose own Earth term and
-- rotating-frame terms it already applies: that is the one-line seam in engineering.flightmodel (doc 57 §5).
local Core = NcmCore

Core.define("space.gravity", function(C)
    local A = C.get("space.astro")
    local Cat = C.get("space.catalogue")
    local V = A.vec
    local M = { version = "0.1.0", EPS = 1e-11 }

    local function weight(acc, eps)
        if acc >= 2 * eps then return 1 end
        if acc <= eps then return 0 end
        local x = (acc - eps) / eps
        return x * x * (3 - 2 * x)
    end
    M.weight = weight

    --- The relevant contributors at pos: { { rec, R (astro pos), d, acc (magnitude), w }, ... }, strongest first.
    --- opts: { eps, exclude = { [id] = true } }
    function M.contributors(pos, utc, opts)
        Cat.load()
        opts = opts or {}
        local eps = opts.eps or M.EPS
        local out = {}
        local function consider(rec, R)
            if (opts.exclude and opts.exclude[rec.id]) or not rec.gravity or (rec.gm or 0) <= 0 then return end
            local d = A.distance(R, pos)
            if d <= 0 then return end
            local acc = rec.gm / (d * d)
            local w = weight(acc, eps)
            if w > 0 then out[#out + 1] = { rec = rec, R = R, d = d, acc = acc, w = w } end
        end
        -- how far from its parent a record can be (aphelion for elements, radius for circular orbits)
        local function orbitR(rec)
            local e = rec.ephem or {}
            if e.kind == "kepler" then return e.el[1] * A.AU * (1 + e.el[2]) * 1.05 end
            return e.a or 0
        end
        -- registered records, hierarchically: a body's children are only looked at when the point is close enough to
        -- the body that a child could matter (the widest child orbit plus the child's own reach)
        local function visit(rec)
            local R = Cat.stateAt(rec, utc)
            consider(rec, R)
            local kids = Cat.children(rec.id)
            if #kids > 0 then
                local reach = 0
                for _, ch in ipairs(kids) do
                    local r = math.sqrt((ch.gm or 0) / eps) + orbitR(ch)
                    for _, g in ipairs(Cat.children(ch.id)) do
                        r = math.max(r, orbitR(ch) + orbitR(g) + math.sqrt((g.gm or 0) / eps))
                    end
                    if r > reach then reach = r end
                end
                if A.distance(R, pos) <= reach + 1e9 then
                    for _, ch in ipairs(kids) do visit(ch) end
                end
            end
        end
        for _, rec in ipairs(Cat.list(function(r) return r.parent == nil end)) do
            -- a root record is only evaluated when it (or its system) could reach EPS here
            local R = Cat.stateAt(rec, utc)
            local d = A.distance(R, pos)
            local sysReach = math.sqrt((rec.gm or 0) / eps)
            if rec.kind == "star" or rec.id == "sun" then sysReach = math.max(sysReach, 1e14) end
            if d <= sysReach then visit(rec) end
        end
        -- catalogue stars near enough to matter
        local starReach = math.sqrt(math.max(Cat.maxStarGm(), 0) / eps)
        -- skip the grid when no catalogued star can be that close (every refresh inside the Solar System)
        local nearest = Cat.nearestStarM()
        if not (nearest and A.distance(pos, A.ORIGIN) + starReach < nearest) then
            for _, s in ipairs(Cat.starsNear(pos, starReach)) do consider(s.rec, Cat.stateAt(s.rec, utc)) end
        end
        table.sort(out, function(a, b) return a.acc > b.acc end)
        return out
    end

    local function pull(gm, from, to)
        -- GM * (to - from) / |to - from|^3, from/to astro positions
        local d = A.delta(to, from)
        local r2 = V.dot(d, d)
        if r2 <= 0 then return { 0, 0, 0 } end
        return V.scale(d, gm / (r2 * math.sqrt(r2)))
    end
    M.pull = pull

    --- The absolute field at pos (root-frame axes): acceleration, contributors (each with its vector `a`).
    function M.field(pos, utc, opts)
        local list = M.contributors(pos, utc, opts)
        local total = { 0, 0, 0 }
        for _, c in ipairs(list) do
            c.a = V.scale(pull(c.rec.gm, pos, c.R), c.w)
            total = V.add(total, c.a)
        end
        return total, list
    end

    --- The field felt in a frame centred on record `centreId` (third-body form; the centre's own pull kept whole).
    --- Returns acceleration (root-frame axes), contributors with their RELATIVE vectors `a`.
    function M.relative(pos, utc, centreId, opts)
        local list = M.contributors(pos, utc, opts)
        local centre = Cat.get(centreId)
        local Rc = Cat.stateAt(centre, utc)
        local total = { 0, 0, 0 }
        for _, c in ipairs(list) do
            local a = pull(c.rec.gm, pos, c.R)
            if c.rec.id ~= centreId then a = V.sub(a, pull(c.rec.gm, Rc, c.R)) end
            c.a = V.scale(a, c.w)
            total = V.add(total, c.a)
        end
        return total, list
    end

    --- space.deep's seam: the acceleration from every relevant body EXCEPT the home planet, in the home planet's
    --- frame (third-body form), returned in Earth-fixed axes. p: Earth-fixed metres (space.deep), utc: seconds.
    function M.ecefPerturbation(p, utc, opts)
        Cat.load()
        local home = M.home()
        local Rh = Cat.stateAt(home, utc)
        local pe = A.ecefToEci(p, nil, utc)
        local pos = A.offset(Rh, pe)
        local o = { eps = opts and opts.eps, exclude = { [home.id] = true } }
        local list = M.contributors(pos, utc, o)
        local total = { 0, 0, 0 }
        for _, c in ipairs(list) do
            local a = V.sub(pull(c.rec.gm, pos, c.R), pull(c.rec.gm, Rh, c.R))
            c.a = V.scale(a, c.w)
            total = V.add(total, c.a)
        end
        return A.eciToEcefVec(total, utc), list
    end

    local homeRec
    --- The home planet: the record marked `home` (Earth -- because Night City is there, not because it is special).
    function M.home()
        if homeRec then return homeRec end
        for _, r in ipairs(Cat.list()) do if r.home then homeRec = r end end
        return homeRec
    end

    return M
end)
