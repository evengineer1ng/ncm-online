-- ncm-core module: engineering.gearing
--
-- Stacked gearboxes on a live Machine (owner, 2026-10-08: "a stacked gearbox allows 12 sequential gears between box 1
-- and 2 ... two different kinds of discrete gearboxes side by side ... 3 gearboxes, 2 stacked and 1 additional
-- discrete. it needs to be emergent"). `engineering.drivetrain` composes a designed layout into a graph (L314 R4);
-- this is the RUNTIME half: the driveline boxes actually installed on a Machine (engineering.installation, driveline
-- mounts) become the paths NCM Gearbox drives. Nothing here names a configuration -- what the boxes do follows from
-- where they sit and what they are:
--
--   MAIN PATH   the car's own box, then each INLINE box in mount order:
--               * a `gearbox` CONTINUES the ladder past its tallest gear: each of its ratios times that tallest gear
--                 (a 6-speed car + an OD-6 = 12 sequential gears; box 2's gears open once box 1 is in its top gear)
--               * a `range` box MULTIPLIES every gear by each of its ranges (6 x 2 = 12); moving between ranges keeps
--                 the range's own procedure (`rangeShift.when` any / neutral / stationary, `rangeShift.ms`)
--   SIDE PATHS  each box on a side mount is a separate path with its own ratios (relative to the car's top gear),
--               engaged by whatever control the driver binds to its `engage` command (`select.when` gates it).
--               Nothing is de-duplicated across paths (R4.3): two identical boxes side by side are two paths.
--
-- The car's own ratios are never known here (they live in NCM Gearbox's spec). Every gear is therefore written
-- RELATIVE to the car's box: `A*m` = each of the car's gears times m, `T*m` = the car's top gear times m. Ratio > 1 is
-- shorter (more pull, lower ceiling). A transmission never creates power: a path's drive is scaled by its stages'
-- efficiency, and the Gearbox can only take drive away (Carrier's levers are downward only).
--
-- Wire text (one line, read by NCM Gearbox through NCM Carrier):
--   v1;P,<when>,<shiftMs>,<rangeWhen>,<rangeMs>,<efficiency>,<label>|<entry>|<entry>...;P,...
--   entry = A*<m>@<group> or T*<m>@<group>   (group: which range the gear sits in; a change of group is a range shift)
local Core = NcmCore

Core.define("engineering.gearing", function(C)
    local M = { version = "0.1.0" }
    local Install = C.get("engineering.installation")

    M.WHEN = { any = true, neutral = true, stationary = true }
    M.MAX_PATHS, M.MAX_GEARS = 4, 32

    local function whenOf(w, default) w = tostring(w or default) return M.WHEN[w] and w or default end
    local function label(s) return (tostring(s or "box"):gsub("[;|,]", " ")) end

    local function tallest(entries)
        local t = nil
        for _, e in ipairs(entries) do if t == nil or e.m < t then t = e.m end end
        return t or 1
    end

    local function positive(list)
        local out = {}
        for _, r in ipairs(type(list) == "table" and list or {}) do
            local n = tonumber(r)
            if n and n > 0 and n == n then out[#out + 1] = n end
        end
        return out
    end

    --- Compose the installed driveline devices (engineering.installation.resolve output, any order) into paths.
    --- Returns { paths = { { label, when, shiftMs, rangeWhen, rangeMs, efficiency, entries = {{base, m, group}}, componentId } },
    ---           pathOf = { [componentId] = pathIndex }, refused = { {componentId, reason} }, summary = "..." }.
    function M.compose(devices)
        local inline, side, refused = {}, {}, {}
        for _, d in ipairs(devices or {}) do
            local mount = Install.mount(d.mountId)
            if Install.isDriveline(d.kind) and mount and mount.driveline then
                local list = mount.driveline == "inline" and inline or side
                list[#list + 1] = { d = d, order = mount.order or 9 }
            end
        end
        local byOrder = function(a, b) return a.order < b.order end
        table.sort(inline, byOrder)
        table.sort(side, byOrder)

        local main = { label = "car", when = "any", shiftMs = 0, rangeWhen = "any", rangeMs = 0, efficiency = 1,
            entries = { { base = "A", m = 1, group = 0 } } }
        local groups = 1
        for _, x in ipairs(inline) do
            local d, p = x.d, x.d.perf or {}
            if p.kind == "gearbox" then
                local top = tallest(main.entries)
                local ratios = positive(p.ratios)
                if #ratios == 0 then refused[#refused + 1] = { componentId = d.componentId, reason = "no ratios" } else
                    table.sort(ratios, function(a, b) return a > b end)   -- shortest first
                    -- its first gear continues from the top of what is already there, in the top gear's own range
                    local g = 0
                    for _, e in ipairs(main.entries) do if e.m == top then g = e.group end end
                    for _, r in ipairs(ratios) do main.entries[#main.entries + 1] = { base = "T", m = top * r, group = g } end
                    main.shiftMs = math.max(main.shiftMs, tonumber(p.shiftMs) or 0)
                end
            elseif p.kind == "range" then
                local ranges = positive(p.ranges)
                if #ranges == 0 then refused[#refused + 1] = { componentId = d.componentId, reason = "no ranges" } else
                    local out = {}
                    for ri, q in ipairs(ranges) do
                        for _, e in ipairs(main.entries) do
                            out[#out + 1] = { base = e.base, m = e.m * q, group = e.group * #ranges + (ri - 1) }
                        end
                    end
                    main.entries = out
                    groups = groups * #ranges
                    local rs = type(p.rangeShift) == "table" and p.rangeShift or {}
                    main.rangeWhen = whenOf(rs.when, "any") ~= "any" and whenOf(rs.when, "any") or main.rangeWhen
                    main.rangeMs = math.max(main.rangeMs, tonumber(rs.ms) or tonumber(p.shiftMs) or 0)
                end
            end
            main.efficiency = main.efficiency * math.max(0, math.min(1, tonumber(p.efficiency) or 1))
            main.label = main.label .. "+" .. label(d.code)
        end

        local paths, pathOf = { main }, {}
        for _, x in ipairs(inline) do pathOf[x.d.componentId] = 1 end
        for _, x in ipairs(side) do
            local d, p = x.d, x.d.perf or {}
            if #paths >= M.MAX_PATHS then refused[#refused + 1] = { componentId = d.componentId, reason = "too many paths" } else
                local path = { label = label(d.code), shiftMs = tonumber(p.shiftMs) or 0, rangeWhen = "any", rangeMs = 0,
                    efficiency = math.max(0, math.min(1, tonumber(p.efficiency) or 1)), entries = {}, componentId = d.componentId }
                if p.kind == "gearbox" then
                    path.when = whenOf(type(p.select) == "table" and p.select.when, "any")
                    for _, r in ipairs(positive(p.ratios)) do path.entries[#path.entries + 1] = { base = "T", m = r, group = 0 } end
                else   -- a range box on its own path: the car's box in each of its ranges
                    local rs = type(p.rangeShift) == "table" and p.rangeShift or {}
                    path.when = whenOf(rs.when, "any")
                    path.rangeWhen, path.rangeMs = whenOf(rs.when, "any"), tonumber(rs.ms) or 0
                    for ri, q in ipairs(positive(p.ranges)) do path.entries[#path.entries + 1] = { base = "A", m = q, group = ri - 1 } end
                end
                if #path.entries == 0 then refused[#refused + 1] = { componentId = d.componentId, reason = "no ratios" } else
                    paths[#paths + 1] = path
                    pathOf[d.componentId] = #paths
                end
            end
        end

        local parts = {}
        for i, p in ipairs(paths) do
            parts[#parts + 1] = ("%s%s: %s (%d stage%s, engage %s%s)"):format(i == 1 and "main" or ("side " .. (i - 1)),
                "", p.label, #p.entries, #p.entries == 1 and "" or "s", p.when,
                p.rangeWhen ~= "any" and (", range change " .. p.rangeWhen) or "")
        end
        return { paths = paths, pathOf = pathOf, refused = refused, summary = table.concat(parts, " | "),
            stacked = #inline > 0 or #side > 0 }
    end

    local function num(v) return (("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", "")) end

    --- The wire text for NCM Gearbox ("" when the Machine has no driveline boxes: the car's own box alone).
    function M.encode(composed)
        if not (composed and composed.stacked) then return "" end
        local out = { "v1" }
        for i, p in ipairs(composed.paths) do
            if i > M.MAX_PATHS then break end
            local s = { ("P,%s,%d,%s,%d,%s,%s"):format(p.when, math.floor(p.shiftMs + 0.5), p.rangeWhen, math.floor(p.rangeMs + 0.5),
                num(p.efficiency), label(p.label)) }
            for k, e in ipairs(p.entries) do
                if k > M.MAX_GEARS then break end
                s[#s + 1] = ("%s*%s@%d"):format(e.base, num(e.m), e.group)
            end
            out[#out + 1] = table.concat(s, "|")
        end
        return table.concat(out, ";")
    end

    return M
end)
