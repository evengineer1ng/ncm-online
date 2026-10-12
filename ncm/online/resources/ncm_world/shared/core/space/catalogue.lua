-- ncm-core module: space.catalogue
--
-- Every astronomical object NCM knows, as DATA (doc 57 §2): the Solar System records (`space.data.solar`), the star
-- catalogue (`space.data.stars`, Hipparcos; optional -- a host that does not load it simply has no stars), and any
-- record a host registers at runtime. Nothing here names a body in code: Earth is the record with `home = true`.
--
-- A record: { id, name, kind, parent, gm (m^3/s^2), radius (m), ephem (see space.ephemeris), pole, provenance,
--             gravity (false = carries no gravity of its own, e.g. a barycentre) }.
--
-- Queries (all at a UTC instant; positions are space.astro positions, velocities m/s in ICRF axes):
--   get(id) / list(filter)                     what exists
--   stateAt(id, utc) -> pos, vel               where it is (composed up the parent chain, memoised per instant)
--   near(pos, radius, utc, opts) -> {{rec, d}}  what is around a point, nearest first
--   nearest(pos, utc, filter)                  the nearest record
--   system(pos, utc)                           the star whose pull is strongest there (the system you are in)
--   soi(pos, utc)                              the deepest body whose sphere of influence contains the point
-- Tiers (doc 57 §2): a record is CATALOGUED by existing; the other tiers are query results (space.gravity says who
-- is gravitational at a point, telemetry/rendering ask `near`), never flags set by hand.
local Core = NcmCore

Core.define("space.catalogue", function(C)
    local A = C.get("space.astro")
    local E = C.get("space.ephemeris")
    local V = A.vec
    local M = { version = "0.1.0" }

    local GM_SUN = 132712440041.279419e9
    local R_SUN = 695700000

    local byId, order, children = {}, {}, {}
    local stars = nil              -- the star module's arrays, or false when not loaded
    local starGrid, STAR_CELL_PC = nil, 1.0
    local starGmMax = 0
    local starNearestM = nil       -- the nearest catalogued star's distance from the Sun (m)

    -- ------------------------------------------------------------------------------------------- registration
    function M.register(rec)
        assert(type(rec) == "table" and type(rec.id) == "string", "space.catalogue: a record needs an id")
        if byId[rec.id] then error("space.catalogue: duplicate id " .. rec.id) end
        rec.tier = "catalogued"
        if rec.gravity == nil then rec.gravity = (rec.gm or 0) > 0 end
        byId[rec.id] = rec
        order[#order + 1] = rec
        if rec.parent then
            children[rec.parent] = children[rec.parent] or {}
            table.insert(children[rec.parent], rec)
        end
        return rec
    end

    -- Loading is incremental: the Solar System at once, then the star catalogue ONE CHUNK PER CALL to `loadStep`, so
    -- a host with a per-call instruction budget (OPEN//77) spreads it over ticks. `load()` finishes it in one go (tests,
    -- hosts without a budget). Until the stars are in, queries simply see fewer stars -- never an error.
    local solarDone, chunkNext, chunkCount = false, 1, 0
    local function addChunk(ch)
        local base = #stars.hip
        for k = 1, #ch.hip do
            local i = base + k
            stars.hip[i], stars.x[i], stars.y[i], stars.z[i] = ch.hip[k], ch.x[k], ch.y[k], ch.z[k]
            stars.hp[i], stars.bv[i], stars.mass[i] = ch.hp[k], ch.bv[k], ch.mass[k]
            local key = math.floor(ch.x[k] / STAR_CELL_PC) .. ":" .. math.floor(ch.y[k] / STAR_CELL_PC) .. ":" .. math.floor(ch.z[k] / STAR_CELL_PC)
            local cell = starGrid[key]
            if not cell then cell = {}; starGrid[key] = cell end
            cell[#cell + 1] = i
            local gm = ch.mass[k] * GM_SUN
            if gm > starGmMax then starGmMax = gm end
            local dpc = math.sqrt(ch.x[k] * ch.x[k] + ch.y[k] * ch.y[k] + ch.z[k] * ch.z[k])
            if not starNearestM or dpc * A.PC < starNearestM then starNearestM = dpc * A.PC end
        end
        stars.count = #stars.hip
    end

    --- One loading step. Returns done (true once everything available is loaded), progress text.
    function M.loadStep()
        if not solarDone then
            solarDone = true
            for _, rec in ipairs(C.get("space.data.solar")) do M.register(rec) end
            local ok, S = pcall(C.get, "space.data.stars")
            if ok and S then
                stars = { source = S.source, named = S.named or {}, count = 0, hip = {}, x = {}, y = {}, z = {}, hp = {}, bv = {}, mass = {} }
                chunkCount = S.chunks or 0
                starGrid = {}
            else
                stars = false
            end
            return not stars or chunkCount == 0, "solar system"
        end
        if not stars or chunkNext > chunkCount then return true, "done" end
        local ok, ch = pcall(C.get, "space.data.stars." .. chunkNext)
        if ok and ch then addChunk(ch) end
        chunkNext = chunkNext + 1
        return chunkNext > chunkCount, ("stars %d/%d chunks, %d stars"):format(chunkNext - 1, chunkCount, stars.count)
    end

    function M.loaded() return solarDone and (not stars or chunkNext > chunkCount) end

    function M.load()
        if not solarDone then M.loadStep() end
        return M
    end

    --- Finish loading now (tests; hosts without an instruction budget).
    function M.loadAll()
        while not M.loadStep() do end
        return M
    end

    --- The record for catalogue star index i (made on first use, then kept).
    local starRecs = {}
    local function starRec(i)
        local r = starRecs[i]
        if r then return r end
        local hip = stars.hip[i]
        local named = stars.named[hip]
        local mass = stars.mass[i]
        r = { id = "hip:" .. hip, name = named and named.name or ("HIP " .. hip), kind = "star", parent = nil,
              gm = mass * GM_SUN, radius = R_SUN * mass ^ 0.8, mass = mass, hp = stars.hp[i], bv = stars.bv[i],
              ephem = { kind = "star", pc = { stars.x[i], stars.y[i], stars.z[i] } }, gravity = true, tier = "catalogued",
              provenance = { stars.source, named and ("mass: " .. named.massSource) or "mass: estimated (main-sequence L~M^3.5)" } }
        starRecs[i] = r
        byId[r.id] = r
        return r
    end

    function M.get(id)
        M.load()
        local r = byId[id]
        if r or not stars then return r end
        local hip = tonumber(tostring(id):match("^hip:(%d+)$"))
        if hip then for i = 1, stars.count do if stars.hip[i] == hip then return starRec(i) end end end
        return nil
    end

    --- Records matching filter(rec) (default: the registered ones; `stars = true` in opts includes every star).
    function M.list(filter, opts)
        M.load()
        local out = {}
        for _, r in ipairs(order) do if not filter or filter(r) then out[#out + 1] = r end end
        if opts and opts.stars and stars then
            for i = 1, stars.count do local r = starRec(i); if not filter or filter(r) then out[#out + 1] = r end end
        end
        return out
    end

    function M.children(id) return children[id] or {} end
    function M.starCount() M.load(); return stars and stars.count or 0 end
    function M.maxStarGm() M.load(); return starGmMax end
    function M.nearestStarM() return stars and starNearestM or nil end

    -- ------------------------------------------------------------------------------------------- states
    local memoUtc, memo = nil, {}
    local function localState(rec, utc)
        local ctx = {}
        if rec.ephem and rec.ephem.kind == "emb_member" then
            for _, r in ipairs(children[rec.parent] or {}) do
                if r.ephem and r.ephem.role == "earth" then ctx.earthGm = r.gm end
                if r.ephem and r.ephem.role == "moon" then ctx.moonGm = r.gm end
            end
        elseif rec.ephem and rec.ephem.kind == "satellite" then
            local p = byId[rec.parent]; ctx.parentPole = p and p.pole
        end
        return E.local_(rec, utc, ctx)
    end

    --- Root-frame metres + velocity of a record (doubles: fine to ~1e15 m; stars come back through `stateAt` as
    --- astro positions built from parsecs).
    -- Every consumer asks for a slightly different instant (a flight step, the frame policy, the Sun on the page, the Moon
    -- in the native view): computing each at its own instant recomputed every ephemeris every call and spent hosts'
    -- per-frame script budget (2026-10-11 session: ~3 skipped Deep frames a minute). States are therefore computed ONCE
    -- PER WHOLE SECOND and extrapolated linearly inside it: p(t) = p(q) + v(q)(t - q). The error is a dt^2/2 -- 3 mm for
    -- the Earth around the Sun, 1 mm for the Moon -- so frame switches stay exact to that.
    local function rootAt(rec, q)
        if memoUtc ~= q then memoUtc, memo = q, {} end
        local m = memo[rec.id]
        if m then return m[1], m[2] end
        local p, v = localState(rec, q)
        if rec.parent then
            local pp, pv = rootAt(byId[rec.parent], q)
            p, v = V.add(p, pp), V.add(v, pv)
        end
        memo[rec.id] = { p, v }
        return p, v
    end
    local function rootMetres(rec, utc)
        local q = math.floor(utc)
        local p, v = rootAt(rec, q)
        local dt = utc - q
        if dt == 0 then return p, v end
        return { p[1] + v[1] * dt, p[2] + v[2] * dt, p[3] + v[3] * dt }, v
    end

    --- Where a record is at utc: astro position, velocity (m/s, ICRF).
    function M.stateAt(idOrRec, utc)
        M.load()
        local rec = type(idOrRec) == "table" and idOrRec or M.get(idOrRec)
        if not rec then return nil, nil end
        if rec.ephem and rec.ephem.kind == "star" then
            local pc = rec.ephem.pc
            -- parsecs -> cell + offset without forming a galactic double: whole cells, then the remainder
            local function part(x)
                local m = x * A.PC
                local c = math.floor(m / A.CELL + 0.5)
                return c, m - c * A.CELL
            end
            local c1, o1 = part(pc[1]); local c2, o2 = part(pc[2]); local c3, o3 = part(pc[3])
            return A.fromParts({ c1, c2, c3 }, { o1, o2, o3 }), { 0, 0, 0 }
        end
        local p, v = rootMetres(rec, utc)
        return A.pos(p[1], p[2], p[3]), v
    end

    -- ------------------------------------------------------------------------------------------- spatial queries
    --- Stars within `radius` metres of pos: { {rec, d}, ... } (unsorted).
    local function starsNear(pos, radius)
        local out = {}
        if not stars then return out end
        local m = A.metres(pos)
        local cx, cy, cz = m[1] / A.PC, m[2] / A.PC, m[3] / A.PC
        local rpc = radius / A.PC
        local n = math.ceil(rpc / STAR_CELL_PC)
        if n > 60 then n = 60 end              -- a query wider than ~60 pc is a catalogue scan, not a neighbourhood
        local i0, j0, k0 = math.floor(cx / STAR_CELL_PC), math.floor(cy / STAR_CELL_PC), math.floor(cz / STAR_CELL_PC)
        for i = i0 - n, i0 + n do for j = j0 - n, j0 + n do for k = k0 - n, k0 + n do
            local cell = starGrid[i .. ":" .. j .. ":" .. k]
            if cell then
                for _, idx in ipairs(cell) do
                    local dx, dy, dz = stars.x[idx] - cx, stars.y[idx] - cy, stars.z[idx] - cz
                    local d = math.sqrt(dx * dx + dy * dy + dz * dz) * A.PC
                    if d <= radius then out[#out + 1] = { rec = starRec(idx), d = d } end
                end
            end
        end end end
        return out
    end
    M.starsNear = starsNear

    --- What is around a point: registered records and stars within radius (m), nearest first.
    --- opts: { stars = true (default true), filter = fn(rec) }
    function M.near(pos, radius, utc, opts)
        M.load()
        opts = opts or {}
        local out = {}
        for _, rec in ipairs(order) do
            if rec.kind ~= "barycentre" and (not opts.filter or opts.filter(rec)) then
                local p = M.stateAt(rec, utc)
                local d = A.distance(p, pos)
                if d <= radius then out[#out + 1] = { rec = rec, d = d } end
            end
        end
        if opts.stars ~= false then
            for _, s in ipairs(starsNear(pos, radius)) do
                if not opts.filter or opts.filter(s.rec) then out[#out + 1] = s end
            end
        end
        table.sort(out, function(a, b) return a.d < b.d end)
        return out
    end

    --- The nearest record to pos (searching outward until something is found).
    function M.nearest(pos, utc, filter)
        local r = 1e9
        for _ = 1, 40 do
            local hits = M.near(pos, r, utc, { filter = filter })
            if hits[1] then return hits[1].rec, hits[1].d end
            r = r * 4
        end
        return nil
    end

    --- The star system a point is in: the star (the Sun included) pulling hardest there. Continuous by construction:
    --- no boundary is drawn, the answer changes where two stars pull equally.
    function M.system(pos, utc)
        M.load()
        -- every root record that pulls (the Sun, a black hole...) competes with the catalogue stars
        local best, bestA, bestD = nil, -1, nil
        for _, rec in ipairs(order) do
            if rec.parent == nil and rec.gravity and (rec.gm or 0) > 0 then
                local d = A.distance(M.stateAt(rec, utc), pos)
                local a = rec.gm / math.max(d * d, 1)
                if a > bestA then best, bestA, bestD = rec, a, d end
            end
        end
        local radius = math.sqrt(math.max(starGmMax, 1) / (bestA * 0.5 + 1e-30))
        if radius > 60 * A.PC then radius = 60 * A.PC end
        -- no catalogued star can be within `radius` when the point is that much closer to the Sun than the nearest
        -- star is (the frame policy asks this every minute from inside the Solar System: skip the grid then)
        if stars and starNearestM and A.distance(pos, A.ORIGIN) + radius < starNearestM then return best, bestD, bestA end
        for _, s in ipairs(starsNear(pos, radius)) do
            local a = s.rec.gm / (s.d * s.d)
            if a > bestA then best, bestA, bestD = s.rec, a, s.d end
        end
        return best, bestD, bestA
    end

    --- The deepest body whose (Laplace) sphere of influence contains pos: r_soi = d_parent * (m / M_parent)^(2/5).
    --- Root bodies (the Sun, stars) have no parent: their sphere is the system itself.
    function M.soi(pos, utc)
        local sys = M.system(pos, utc)
        local best, bestDepth = sys, 0
        -- the gravitational children of a body: a barycentre is transparent -- its heaviest member orbits the
        -- barycentre's parent, the other members orbit that primary (the Moon is inside Earth's sphere, not the Sun's)
        local function kids(rec)
            local out = {}
            for _, ch in ipairs(children[rec.id] or {}) do
                if ch.kind == "barycentre" then
                    local members = {}
                    for _, m in ipairs(children[ch.id] or {}) do if m.gravity then members[#members + 1] = m end end
                    table.sort(members, function(a, b) return a.gm > b.gm end)
                    if members[1] then
                        out[#out + 1] = { body = members[1], parent = rec, sub = { (table.unpack or unpack)(members, 2) } }
                    end
                elseif ch.gravity then
                    out[#out + 1] = { body = ch, parent = rec }
                end
            end
            return out
        end
        local function visit(rec, depth, extra)
            local list = kids(rec)
            for _, s in ipairs(extra or {}) do list[#list + 1] = { body = s, parent = rec } end
            for _, k in ipairs(list) do
                local cp = M.stateAt(k.body, utc)
                local dist = A.distance(cp, M.stateAt(k.parent, utc))
                local soi = dist * (k.body.gm / k.parent.gm) ^ 0.4
                if A.distance(cp, pos) <= soi then
                    if depth + 1 > bestDepth then best, bestDepth = k.body, depth + 1 end
                    visit(k.body, depth + 1, k.sub)
                end
            end
        end
        if sys.id == "sun" then visit(sys, 0) end
        return best
    end

    return M
end)
