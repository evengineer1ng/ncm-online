-- ncm-core data: data.ovals
-- Oval races round the city's roundabouts (L236). The owner authors each one: four points around the roundabout,
-- by its poles, captured in game with `/pos`. Like drag races, ovals are never generated.
--
-- From the four points this derives everything a race needs:
--   * the loop: points ordered round their centre in the driving direction (Night City drives on the right, so a
--     roundabout runs anticlockwise seen from above); the author's FIRST point is the start/finish line;
--   * size: the mean radius and a loop length of 2*pi*r;
--   * laps (to about `targetM` of racing, 5-15 -- the drive plan carries at most 64 points) and the field size the
--     roundabout can grid (half the loop, two abreast, 9 m rows, 4-16 cars), both overridable per oval;
--   * gates at each point on every lap, sized to the roundabout so a small one cannot be "passed" twice at once;
--   * a root (`oval_<id>`) that course.routes resolves directly, with the whole race as its intermediate points.
--
-- Entry shape: { id = "corpo_plaza", name = "Corpo Plaza Oval", region = "City Center",
--   points = { {x=,y=,z=}, {x=,y=,z=}, {x=,y=,z=}, {x=,y=,z=} },
--   laps = nil, fieldMax = nil, targetM = 2400, clockwise = false }
local Core = NcmCore

Core.define("data.ovals", function(C)
    local M = { version = "0.1.0", PREFIX = "oval_" }

    -- Authored ovals. Add the owner's roundabouts here.
    M.LIST = {}

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
        local laps = def.laps or clamp(math.floor((def.targetM or 2400) / circ + 0.5), 5, 15)
        laps = clamp(laps, 1, math.floor(63 / n))
        local fieldMax = def.fieldMax or clamp(2 * math.floor(circ * 0.5 / 9), 4, 16)
        -- travel direction at the line: the radius turned a quarter in the driving direction
        local rx, ry = (first.x - cx) / radius, (first.y - cy) / radius
        local tx, ty = -ry * sign, rx * sign
        return { id = def.id, cx = cx, cy = cy, cz = cz, radius = radius, circumference = circ, laps = laps, fieldMax = fieldMax,
            loop = loop, sign = sign, startAngle = a0, heading = math.deg(atan2(ty, tx)),
            tangent = { x = tx, y = ty } }
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
