-- ncm-core data: data.ovals
-- Oval races round the city's roundabouts (L236). The owner authors each one: four points around the roundabout,
-- by its poles, captured in game with `/ncm.mark` (tools/read-marks.py --oval). Like drag races, ovals are never generated.
--
-- From the four points this derives everything a race needs:
--   * the loop: points ordered round their centre in the driving direction (Night City drives on the right, so a
--     roundabout runs anticlockwise seen from above); the author's FIRST point is the start/finish line;
--   * size: the mean radius and a loop length of 2*pi*r;
--   * laps (to about `targetM` of racing -- 8 km, so no oval runs a token 5 laps (L236) -- 5-25; the drive plan reaches Pace
--     as a tape (0.3.1, KB-223), so the old 64-point cap is gone) and the field size the
--     roundabout can grid (half the loop, two abreast, 9 m rows, 4-16 cars), both overridable per oval;
--   * gates at each point on every lap, sized to the roundabout so a small one cannot be "passed" twice at once;
--   * a root (`oval_<id>`) that course.routes resolves directly, with the whole race as its intermediate points.
--
-- Entry shape: { id = "corpo_plaza", name = "Corpo Plaza Oval", region = "City Center",
--   points = { {x=,y=,z=}, {x=,y=,z=}, {x=,y=,z=}, {x=,y=,z=} },
--   laps = nil, fieldMax = nil, targetM = 8000, clockwise = false }
local Core = NcmCore

Core.define("data.ovals", function(C)
    local M = { version = "0.2.0", PREFIX = "oval_", MAX_LAPS = 25 }
    -- OFF THE SCHEDULE (owner, 2026-09-30 07:05: "take ovals off the roster of races coming up, they can't be trusted
    -- yet"; KB-223). The ovals stay defined and resolvable -- a race already on one still runs and resolves -- but no
    -- new slot picks one while this is false. ncm_paddock sets it from its `ovalsScheduled` tunable.
    M.SCHEDULED = false

    -- Authored ovals. Add the owner's roundabouts here.
    -- Marked in game with /ncm.mark on 2026-09-30; the first point is the start/finish line.
    M.LIST = {
        { id = "corpo_circle", name = "Corpo Circle", region = "City Center", laps = 12, lineInsetM = 9, entryPoint = 1, points = {
            { x = -1271.74, y = -100.34, z = 7.94 }, { x = -1397.69, y = 77.45, z = 8.44 },
            { x = -1578.54, y = -58.86, z = 8.44 }, { x = -1467.70, y = -222.26, z = 8.36 } } },
        { id = "westbrook_short_ring", name = "Westbrook Short Ring", region = "Westbrook", entryPoint = 1, points = {
            { x = -266.69, y = 756.37, z = 77.83 }, { x = -164.12, y = 719.05, z = 78.59 },
            { x = -141.41, y = 815.57, z = 81.63 }, { x = -251.74, y = 821.58, z = 77.73 } } },
        { id = "ncx_octagon", name = "NCX Octagon", region = "Badlands", points = {
            { x = -3384.75, y = 404.00, z = 31.85 }, { x = -3478.19, y = 456.66, z = 31.88 },
            { x = -3530.72, y = 356.15, z = 31.88 }, { x = -3420.55, y = 321.26, z = 31.87 } } },
    }

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
    local function atan2(y, x)
        if math.atan2 then return math.atan2(y, x) end
        return math.atan(y, x)
    end

    --- The geometry of one authored oval. Returns geom or nil, reason.
    function M.geometry(def)
        if type(def) ~= "table" or type(def.id) ~= "string" or type(def.points) ~= "table" or #def.points < 3 then
            return nil, "needs an id and at least three points"
        end
        local cx, cy, cz = 0, 0, 0
        for _, p in ipairs(def.points) do
            if type(p.x) ~= "number" or type(p.y) ~= "number" then return nil, "a point without x/y" end
            cx, cy, cz = cx + p.x, cy + p.y, cz + (p.z or 0)
        end
        local n = #def.points
        cx, cy, cz = cx / n, cy / n, cz / n
        local sign = def.clockwise and -1 or 1
        local function ang(p) return atan2(p.y - cy, p.x - cx) end
        -- driving order from the author's first point: increasing angle anticlockwise (decreasing if clockwise)
        local first = def.points[1]
        local a0 = ang(first)
        local rest = {}
        for i = 2, n do
            local p = def.points[i]
            local d = (ang(p) - a0) * sign
            while d <= 0 do d = d + 2 * math.pi end
            rest[#rest + 1] = { p = p, d = d }
        end
        table.sort(rest, function(a, b) return a.d < b.d end)
        local loop = { { x = first.x, y = first.y, z = first.z or cz } }
        for _, r in ipairs(rest) do loop[#loop + 1] = { x = r.p.x, y = r.p.y, z = r.p.z or cz } end
        local rsum = 0
        for _, p in ipairs(loop) do rsum = rsum + math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2) end
        local radius = rsum / n
        if radius < 8 then return nil, "too small to race round (radius " .. math.floor(radius) .. " m)" end
        local circ = 2 * math.pi * radius
        local laps = def.laps or clamp(math.floor((def.targetM or 8000) / circ + 0.5), 5, M.MAX_LAPS)
        laps = clamp(laps, 1, M.MAX_LAPS)
        local fieldMax = def.fieldMax or clamp(2 * math.floor(circ * 0.5 / 9), 4, 16)
        -- travel direction at the line: the radius turned a quarter in the driving direction
        local rx, ry = (first.x - cx) / radius, (first.y - cy) / radius
        local tx, ty = -ry * sign, rx * sign
        -- lineInsetM: the race LINE runs this far inside the marked ring (the grid stays on it). Measured, not guessed:
        -- Corpo's three survivors of 05:22 drove 7-13 m inside the marks, and the line on the marks aimed the rest at
        -- the outer walls round checkpoint 2 (KB-223)
        local entryPoint = clamp(math.floor(tonumber(def.entryPoint) or 1), 1, #loop)
        local entry = loop[entryPoint]
        return { id = def.id, cx = cx, cy = cy, cz = cz, radius = radius, circumference = circ, laps = laps, fieldMax = fieldMax, inset = def.lineInsetM or 0,
            loop = loop, entry = { id = "oval_" .. def.id .. "_entry_" .. entryPoint, point = entryPoint,
                x = entry.x, y = entry.y, z = entry.z, name = (def.name or def.id) .. " Entry" },
            sign = sign, startAngle = a0, heading = math.deg(atan2(ty, tx)),
            tangent = { x = tx, y = ty } }
    end

    --- The race LINE round the ring for the continuous model (L230; KB-223): the author's poles joined by the ring
    --- itself, not by chords across the island. Between two poles the radius and height move linearly with the angle,
    --- so the line passes through every pole the owner stood on. Sampled every `stepM` metres of arc, lap after lap,
    --- ending on the line. Returns { points, lengthM }.
    function M.ringLine(g, laps, stepM)
        stepM = stepM or 15
        local loop, n = g.loop, #g.loop
        local polar = {}
        for i, p in ipairs(loop) do
            local a = atan2(p.y - g.cy, p.x - g.cx)
            local d = (a - g.startAngle) * g.sign
            while d < 0 do d = d + 2 * math.pi end
            if i == 1 then d = 0 end
            polar[i] = { t = d, r = math.sqrt((p.x - g.cx) ^ 2 + (p.y - g.cy) ^ 2), z = p.z or g.cz }
        end
        polar[n + 1] = { t = 2 * math.pi, r = polar[1].r, z = polar[1].z }
        local per = math.max(8, math.floor(2 * math.pi * g.radius / stepM + 0.5))
        local pts, j = {}, 1
        local function at(t)
            while j < n and t > polar[j + 1].t do j = j + 1 end
            local a, b = polar[j], polar[j + 1]
            local f = (b.t > a.t) and (t - a.t) / (b.t - a.t) or 0
            local r, z = a.r + (b.r - a.r) * f - (g.inset or 0), a.z + (b.z - a.z) * f
            local ang = g.startAngle + g.sign * t
            return { x = g.cx + r * math.cos(ang), y = g.cy + r * math.sin(ang), z = z }
        end
        for lap = 1, laps do
            j = 1
            for k = 0, per - 1 do pts[#pts + 1] = at(2 * math.pi * k / per) end
        end
        j = 1
        pts[#pts + 1] = at(0)                -- ends on the line, inset like every other point
        local len = 0
        for i = 2, #pts do len = len + math.sqrt((pts[i].x - pts[i - 1].x) ^ 2 + (pts[i].y - pts[i - 1].y) ^ 2) end
        return { points = pts, lengthM = len }
    end

    local byId = nil
    local function index()
        if byId then return byId end
        byId = {}
        for _, def in ipairs(M.LIST) do byId[M.PREFIX .. def.id] = def end
        return byId
    end

    function M.register(def)
        local ok, why = M.geometry(def)
        if not ok then return nil, why end
        index()[M.PREFIX .. def.id] = def
        for i, x in ipairs(M.LIST) do if x.id == def.id then M.LIST[i] = def; return def end end
        M.LIST[#M.LIST + 1] = def
        return def
    end

    function M.isOval(rootId) return type(rootId) == "string" and rootId:sub(1, #M.PREFIX) == M.PREFIX end

    --- The root for an oval id (the shape data.roots holds, plus embedded nodes and the oval's geometry), or nil.
    function M.root(rootId)
        local def = index()[rootId]
        if not def then return nil end
        local g = M.geometry(def)
        if not g then return nil end
        local line = g.loop[1]
        local start = { id = rootId .. "_line", name = def.name or def.id, region = def.region or "Night City", x = line.x, y = line.y,
            z = line.z, heading = g.heading, oval = true, road = true, urban = true }
        local mids = {}
        for lap = 1, g.laps do
            for i = 2, #g.loop do
                local p = g.loop[i]
                mids[#mids + 1] = { x = p.x, y = p.y, z = p.z, name = ("L%d-%d"):format(lap, i) }
            end
            if lap < g.laps then mids[#mids + 1] = { x = line.x, y = line.y, z = line.z, name = ("L%d"):format(lap) } end
        end
        return { rootId = rootId, startNodeId = start.id, endNodeId = start.id, startNode = start, endNode = start,
            displayName = def.name or def.id, intermediate = mids, custom = true, oval = g,
            description = ("%d laps of %s (%d m a lap), up to %d cars"):format(g.laps, def.name or def.id, math.floor(g.circumference), g.fieldMax) }
    end

    --- The ovals in a region (or all), as root ids.
    function M.ids(region)
        local out = {}
        for _, def in ipairs(M.LIST) do
            if not region or def.region == region then out[#out + 1] = M.PREFIX .. def.id end
        end
        return out
    end

    return M
end)
