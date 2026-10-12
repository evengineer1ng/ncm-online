-- ncm-core module: engineering.envelope
--
-- A SITE: somewhere bodies can be placed and connected (doc 50 §3; L314). The car's engineering envelope is
-- the first kind. The road (civil engineering, doc 49 §7-§8) is the second, after E19, and reuses everything
-- here except the authoring data. Nothing in this module knows what a car is beyond `kind = "car"`.
--
-- A site is a plan grid (the v1 projection, L314 R2: 10 cm cells, three height classes, no elevation editing)
-- divided into zones. A zone can be:
--   * `reserved`   -- nothing may occupy it (the driver's seat). Red.
--   * `height`     -- the tallest height class that fits. Taller is red, or yellow if `coverable` (a raised
--                     cover is an adaptation).
--   * `adaptable`  -- extra rects that belong to the zone only by cutting into them (yellow).
--   * `fabricable` -- a missing mount can be fabricated here (yellow) rather than being impossible (red).
-- Plus the site's own mounts and ports (a car's engine output and differential input), its CAPACITIES, which
-- are never refusals (L314, doc 50 §5), and its STOCK: the factory layout and the record mass it implies.
--
-- **Provenance on every site, and unknown fails closed** (the `parts.architecture` rule). A site whose
-- geometry nobody has surveyed is not guessed at: `fit` reports it as red with "not yet surveyed".
local Core = NcmCore

Core.define("engineering.envelope", function(C)
    local M = { version = "0.1.0" }

    M.PROVENANCE = { derived = true, authored = true, fixture = true, unknown = true }

    local function key(i, j) return i .. "," .. j end

    --- Validate and index a site. Returns the site with `_cells` (cell key -> {zone, adaptable}) attached,
    --- or nil and reasons. Zones are an ARRAY so overlapping rects resolve deterministically: first zone wins.
    function M.compile(site)
        local errs = {}
        local function bad(fmt, ...) errs[#errs + 1] = fmt:format(...) end
        if type(site) ~= "table" then return nil, { "a site is a table" } end
        if type(site.kind) ~= "string" then bad("site.kind is required (car, road, ...)") end
        if not M.PROVENANCE[site.provenance or ""] then bad("site.provenance is derived / authored / fixture / unknown") end
        local g = site.grid
        if type(g) ~= "table" or type(g.cell) ~= "number" or type(g.w) ~= "number" or type(g.l) ~= "number" then
            bad("site.grid = {cell, w, l}")
        end
        if #errs > 0 then return nil, errs end

        local cells = {}
        local zoneByName = {}
        for zi, z in ipairs(site.zones or {}) do
            if type(z.name) ~= "string" then bad("zone %d needs a name", zi) end
            zoneByName[z.name] = z
            local function fill(rects, adaptable)
                for _, r in ipairs(rects or {}) do
                    for i = r[1], r[3] do
                        for j = r[2], r[4] do
                            if i < 0 or j < 0 or i >= g.w or j >= g.l then
                                bad("zone %s rect leaves the grid at %d,%d", tostring(z.name), i, j)
                                return
                            end
                            local k = key(i, j)
                            if not cells[k] then cells[k] = { zone = z.name, adaptable = adaptable } end
                        end
                    end
                end
            end
            fill(z.rects, false)
            fill(z.adaptable, true)
        end
        if #errs > 0 then return nil, errs end
        site._cells = cells
        site._zones = zoneByName
        return site
    end

    --- What is at a cell: nil (outside every zone), or {zone = <zone table>, adaptable = bool}.
    function M.cellAt(site, i, j)
        local c = site._cells[key(i, j)]
        if not c then return nil end
        return { zone = site._zones[c.zone], adaptable = c.adaptable }
    end

    function M.mountsAt(site, i, j, kind)
        local out = {}
        for _, m in ipairs(site.mounts or {}) do
            if m.cell[1] == i and m.cell[2] == j and (kind == nil or m.kind == kind) then out[#out + 1] = m end
        end
        return out
    end

    function M.port(site, id)
        for _, p in ipairs(site.ports or {}) do if p.id == id then return p end end
        return nil
    end

    function M.surveyed(site) return site.provenance ~= "unknown" end

    return M
end)
