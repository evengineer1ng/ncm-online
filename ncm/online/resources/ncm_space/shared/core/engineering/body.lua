-- ncm-core module: engineering.body
--
-- The shared physical grammar (doc 50 §2; L314). A Body is a physical thing that can be assembled: a gearbox,
-- a radiator, an adapter shaft, a concrete barrier. **It describes what the thing IS, never what it grants.**
-- A capability is derived from what has been assembled (L314: "describe physical things, how they connect,
-- and what they cause"), so there is no `allowsX` field here and there must never be one.
--
-- ---------------------------------------------------------------------------------------------------
-- CANONICAL vs PROJECTION (L314 R2)
-- ---------------------------------------------------------------------------------------------------
--
-- The canonical description is physical and three-dimensional, and every 3D field is optional today:
--   shape    = { bounds = {x, y, z} (metres), ref = "<mesh or shape reference>" }
--   com      = {x, y, z}              centre of mass in the body's own frame (metres)
--   ports    = { {id, kind, spec, flow, pos = {x,y,z}, dir = {x,y,z}, ...} }   connection position + orientation
--   mounts   = { {id, kind, loadKg, pos = {x,y,z}, ...} }
--   loads    = { {kind, pos = {x,y,z}, dir = {x,y,z}, magnitudeN} }           where a force or load is applied
--
-- The **v1 cell footprint** (`footprint.cells`, `heightClass`, and the `cell` / `side` on ports and mounts)
-- is a PROJECTION of that body onto a site's plan grid. It is how v1 authors and fits; it is not what the body
-- is. A later site can read `shape`, `pos` and `dir` instead, without migrating a single design.
--
-- `family` is TAXONOMY (L314 R5): competency and UI read it; physics never does. It is an open string. The twelve
-- `engineering.competency` families are recognised and reported as such, and anything else is still a valid
-- body.
--
-- `perf` is the body's behaviour block, opaque to this module and read by whichever system owns that kind
-- (`engineering.drivetrain` reads `perf.kind` = gearbox / range / selector / adapter).
--
-- Design vs instance (L314, provenance): a design is this table. An asset is `{assetId, design, wear,
-- exposure, observed}` and points at a design; the two are never merged.
local Core = NcmCore

Core.define("engineering.body", function(C)
    local M = { version = "0.1.0" }

    local competency = C.get("engineering.competency")

    M.SIDES = { "N", "E", "S", "W" }
    local SIDE_INDEX = { N = 1, E = 2, S = 3, W = 4 }
    M.ROTATIONS = { [0] = true, [90] = true, [180] = true, [270] = true }
    M.HEIGHT_CLASSES = 3

    function M.knownFamily(family) return competency.isFamily(family) end

    local function isVec(v)
        return type(v) == "table" and type(v[1] or v.x) == "number"
    end

    local function isCell(c)
        return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number"
    end

    --- Validate a design. Returns true, or false and a list of reasons. Unknown families are fine (R5).
    function M.validate(b)
        local errs = {}
        local function bad(fmt, ...) errs[#errs + 1] = fmt:format(...) end
        if type(b) ~= "table" then return false, { "a body is a table" } end
        if type(b.id) ~= "string" or b.id == "" then bad("id must be a non-empty string") end
        if type(b.family) ~= "string" or b.family == "" then bad("family must be a non-empty string (taxonomy, open)") end
        if type(b.massKg) ~= "number" or b.massKg <= 0 then bad("%s: massKg must be > 0 (conservation)", tostring(b.id)) end
        if b.shape ~= nil and type(b.shape) ~= "table" then bad("%s: shape must be a table", tostring(b.id)) end
        if b.shape and b.shape.bounds ~= nil and not isVec(b.shape.bounds) then bad("%s: shape.bounds is a vector", tostring(b.id)) end
        if b.com ~= nil and not isVec(b.com) then bad("%s: com is a vector", tostring(b.id)) end
        local fp = b.footprint
        if fp ~= nil then
            if type(fp.cells) ~= "table" or #fp.cells == 0 then bad("%s: footprint.cells is a non-empty list", tostring(b.id))
            else
                for _, c in ipairs(fp.cells) do
                    if not isCell(c) then bad("%s: footprint cell is {i, j}", tostring(b.id)) break end
                end
            end
            local h = fp.heightClass or 1
            if type(h) ~= "number" or h < 1 or h > M.HEIGHT_CLASSES then bad("%s: heightClass 1..%d", tostring(b.id), M.HEIGHT_CLASSES) end
        end
        local seen = {}
        for _, p in ipairs(b.ports or {}) do
            if type(p.id) ~= "string" then bad("%s: a port needs an id", tostring(b.id)) end
            if seen[p.id] then bad("%s: duplicate port %s", tostring(b.id), tostring(p.id)) end
            seen[p.id] = true
            if type(p.kind) ~= "string" then bad("%s: port %s needs a kind", tostring(b.id), tostring(p.id)) end
            if p.flow ~= nil and p.flow ~= "in" and p.flow ~= "out" and p.flow ~= "both" then
                bad("%s: port %s flow is in / out / both", tostring(b.id), tostring(p.id))
            end
            if p.side ~= nil and not SIDE_INDEX[p.side] then bad("%s: port %s side is N/E/S/W", tostring(b.id), tostring(p.id)) end
            if p.dir ~= nil and not isVec(p.dir) then bad("%s: port %s dir is a vector", tostring(b.id), tostring(p.id)) end
        end
        for _, m in ipairs(b.mounts or {}) do
            if type(m.kind) ~= "string" then bad("%s: a mount needs a kind", tostring(b.id)) end
        end
        for _, l in ipairs(b.loads or {}) do
            if not isVec(l.pos) or not isVec(l.dir) then bad("%s: a load has pos and dir vectors", tostring(b.id)) end
        end
        for _, k in ipairs({ "heatKw", "powerKw", "controlChannels" }) do
            if b[k] ~= nil and (type(b[k]) ~= "number" or b[k] < 0) then bad("%s: %s must be >= 0", tostring(b.id), k) end
        end
        if #errs > 0 then return false, errs end
        return true
    end

    function M.port(b, id)
        for _, p in ipairs(b.ports or {}) do if p.id == id then return p end end
        return nil
    end

    -- ---------------------------------------------------------------------------------------------
    -- The v1 projection onto a plan grid
    -- ---------------------------------------------------------------------------------------------
    --
    -- Rotation is clockwise in 90-degree steps about the footprint's origin, then re-normalised so the
    -- footprint's minimum corner sits on the placement's `at`. Ports and mounts rotate with it, and so do
    -- their sides. i runs across the site (west to east), j along it (north = front to south = rear).

    local function rotCell(i, j, rot)
        if rot == 90 then return -j, i
        elseif rot == 180 then return -i, -j
        elseif rot == 270 then return j, -i end
        return i, j
    end

    function M.rotateSide(side, rot)
        if not side then return nil end
        local k = (SIDE_INDEX[side] - 1 + math.floor(rot / 90)) % 4
        return M.SIDES[k + 1]
    end

    --- Project a design at a placement `{at = {i, j}, rot = 0|90|180|270}`. Returns absolute cells, ports and
    --- mounts, plus the canonical transform the projection stands for (metres and yaw on that grid).
    function M.place(b, placement, cellSize)
        local rot = placement.rot or 0
        assert(M.ROTATIONS[rot], "rotation must be 0, 90, 180 or 270")
        local at = placement.at or { 0, 0 }
        local cells = (b.footprint and b.footprint.cells) or { { 0, 0 } }
        local minI, minJ = math.huge, math.huge
        for _, c in ipairs(cells) do
            local i, j = rotCell(c[1], c[2], rot)
            if i < minI then minI = i end
            if j < minJ then minJ = j end
        end
        local function abs(c)
            local i, j = rotCell(c[1], c[2], rot)
            return { at[1] + i - minI, at[2] + j - minJ }
        end
        local out = { cells = {}, ports = {}, mounts = {}, heightClass = (b.footprint and b.footprint.heightClass) or 1 }
        for _, c in ipairs(cells) do out.cells[#out.cells + 1] = abs(c) end
        for _, p in ipairs(b.ports or {}) do
            out.ports[#out.ports + 1] = { id = p.id, kind = p.kind, spec = p.spec, flow = p.flow,
                cell = abs(p.cell or { 0, 0 }), side = M.rotateSide(p.side, rot) }
        end
        for _, m in ipairs(b.mounts or {}) do
            out.mounts[#out.mounts + 1] = { id = m.id, kind = m.kind, loadKg = m.loadKg or b.massKg,
                cell = abs(m.cell or { 0, 0 }) }
        end
        local cs = cellSize or 0.10
        out.transform = { pos = { at[1] * cs, at[2] * cs, 0 }, yawDeg = rot }
        return out
    end

    --- An asset: one physical instance of a design. Wear, exposure and observed performance live here and
    --- never on the design (L314 provenance: design, instance, lineage, configuration, wear and observation
    --- stay separable).
    function M.asset(assetId, design, extra)
        local a = { assetId = assetId, design = design.id, wear = 0, exposureM = 0, observed = {} }
        for k, v in pairs(extra or {}) do a[k] = v end
        return a
    end

    return M
end)
