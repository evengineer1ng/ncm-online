-- ncm-core module: engineering.drivetrain
--
-- What a layout's driveline IS: a directed graph from the site's power source to its wheels, through bodies
-- (L314 R4). This module produces a DRIVETRAIN SPEC -- paths of stages -- and never a flattened gear table.
-- A runtime (the NCM Gearbox DLL) may derive an active table from a path, and the helpers at the foot of this
-- file are that derivation, kept separate on purpose.
--
-- The four ruled relationships, and how each is represented:
--
--   1. SERIES / SUPPLEMENTARY -- two shiftable stages on one path. Their ratios multiply: a path's
--      `combinations` is the product of its stages. A 6-speed into a 2-speed range box is 12 combinations.
--   2. RANGE -- a stage of kind `range`: it multiplies like any series stage, but it carries its own shift
--      PROCEDURE (`ms`, `when` = any / neutral / stationary), separate from the main box's.
--   3. DISCRETE / SELECTABLE -- more than one path from source to wheels. Power may only split or rejoin at a
--      body whose `perf.kind` is `selector`; anything else splitting the driveline is red. Each path keeps
--      its own ratio set. **Nothing is de-duplicated across paths**: two identical boxes in parallel are two
--      paths with identical ratios, because that overlap is the build (L314 R4.3).
--   4. ADAPTER / PREREQUISITE -- a stage of kind `adapter` (default ratio 1). It exists to make two ports
--      connect, and it is a real body with its own mass, loss and geometry.
--
-- **A transmission never creates power by existing.** Every stage has efficiency <= 1, and the derived
-- virtual gears trade force for speed through the same ratio (share up, ceiling down). No perf block has a
-- power field, and `compose` refuses one.
local Core = NcmCore

Core.define("engineering.drivetrain", function(C)
    local M = { version = "0.1.0" }

    local Body = C.get("engineering.body")

    M.KIND = "driveline"           -- the port kind this module follows
    M.SOURCE, M.SINK = "engine_out", "diff_in"
    M.WHEN = { any = true, neutral = true, stationary = true }

    local function stageOf(key, design)
        local perf = design.perf or {}
        local eff = perf.efficiency
        local st = { key = key, design = design.id, kind = perf.kind or "passive", torqueNm = perf.torqueNm }
        if perf.kind == "gearbox" then
            st.ratios = perf.ratios
            st.reverse = perf.reverse
            st.procedure = { ms = perf.shiftMs or 0, when = "any" }
        elseif perf.kind == "range" then
            st.ratios = perf.ranges
            local rs = perf.rangeShift or {}
            st.procedure = { ms = rs.ms or perf.shiftMs or 0, when = rs.when or "any" }
        elseif perf.kind == "selector" then
            st.ratios = { 1 }
            local sel = perf.select or {}
            st.procedure = { ms = sel.ms or 0, when = sel.when or "stationary" }
        elseif perf.kind == "adapter" then
            st.ratios = { perf.ratio or 1 }
            eff = eff or 0.98
        else
            st.ratios = { 1 }
        end
        st.efficiency = eff or 1
        return st
    end

    --- Compose a layout's driveline. `layout = {placements = {{key, design, ...}}, connections = {{a = {key,
    --- port}, b = {key, port}}}}`; the key "site" names the site's own ports. `opts.edgeEfficiency[index]`
    --- is the loss of a summarised adaptation on that connection (from `engineering.fit`).
    function M.compose(site, layout, designs, opts)
        opts = opts or {}
        local res = { ok = true, errors = {}, paths = {}, selection = "single", selectors = {} }
        local function err(code, text, keys)
            res.ok = false
            res.errors[#res.errors + 1] = { code = code, text = text, keys = keys or {} }
        end

        local byKey = {}
        for _, p in ipairs(layout.placements or {}) do byKey[p.key] = p end
        local function designOf(k) local p = byKey[k]; return p and designs[p.design] end
        local function portOf(k, id)
            if k == "site" then
                for _, sp in ipairs(site.ports or {}) do if sp.id == id then return sp end end
                return nil
            end
            local d = designOf(k)
            return d and Body.port(d, id)
        end

        for _, p in ipairs(layout.placements or {}) do
            local d = designs[p.design]
            if d and d.perf and (d.perf.powerKw or d.perf.forceN or d.perf.torqueAddNm) then
                err("creates_power", ("%s declares power; a transmission routes power, it never creates it")
                    :format(p.key), { p.key })
            end
        end

        -- nodes: "site:<port>" for the site's ends, the placement key for a body
        local out, inc = {}, {}
        local function addEdge(from, to, index)
            out[from] = out[from] or {}
            inc[to] = inc[to] or {}
            out[from][#out[from] + 1] = { to = to, index = index }
            inc[to][#inc[to] + 1] = { from = from, index = index }
        end
        local touched = {}
        for idx, c in ipairs(layout.connections or {}) do
            local pa, pb = portOf(c.a[1], c.a[2]), portOf(c.b[1], c.b[2])
            if pa and pb and pa.kind == M.KIND and pb.kind == M.KIND then
                local na = c.a[1] == "site" and ("site:" .. c.a[2]) or c.a[1]
                local nb = c.b[1] == "site" and ("site:" .. c.b[2]) or c.b[1]
                touched[na], touched[nb] = true, true
                -- orient by flow; a listed order stands in for "both"
                if pa.flow == "in" and pb.flow ~= "in" then addEdge(nb, na, idx) else addEdge(na, nb, idx) end
            end
        end

        local SRC, SNK = "site:" .. M.SOURCE, "site:" .. M.SINK
        -- every simple path from the engine to the wheels
        local function copy(t) local o = {}; for i = 1, #t do o[i] = t[i] end; return o end
        local paths = {}
        local onPath = {}
        local function walk(node, trail, edges)
            if node == SNK then
                paths[#paths + 1] = { nodes = copy(trail), edges = copy(edges) }
                return
            end
            onPath[node] = true
            for _, e in ipairs(out[node] or {}) do
                if not onPath[e.to] then
                    trail[#trail + 1] = e.to
                    edges[#edges + 1] = e.index
                    walk(e.to, trail, edges)
                    trail[#trail] = nil
                    edges[#edges] = nil
                end
            end
            onPath[node] = nil
        end
        walk(SRC, { SRC }, {})

        if #paths == 0 then
            err("no_driveline", "the driveline does not run from the engine to the wheels")
        end

        -- power may only split or rejoin at a selector
        for node, list in pairs(out) do
            if #list > 1 and node ~= SRC then
                local d = designOf(node)
                if not (d and d.perf and d.perf.kind == "selector") then
                    err("split_without_selector", ("power splits at %s, which is not a selector"):format(node), { node })
                end
            elseif #list > 1 then
                err("split_without_selector", "power splits at the engine output with no selector", { node })
            end
        end
        for node, list in pairs(inc) do
            if #list > 1 and node ~= SNK then
                local d = designOf(node)
                if not (d and d.perf and d.perf.kind == "selector") then
                    err("merge_without_selector", ("power rejoins at %s, which is not a selector"):format(node), { node })
                end
            elseif #list > 1 then
                err("merge_without_selector", "two paths reach the wheels with no selector to join them", { node })
            end
        end

        -- a body with driveline ports that is on no path is dangling
        local onAny = {}
        for _, p in ipairs(paths) do for _, n in ipairs(p.nodes) do onAny[n] = true end end
        for _, p in ipairs(layout.placements or {}) do
            local d = designs[p.design]
            local hasDriveline = false
            for _, port in ipairs((d and d.ports) or {}) do if port.kind == M.KIND then hasDriveline = true end end
            if hasDriveline and not onAny[p.key] then
                err("dangling", ("%s is in the driveline's way but connects nothing to the wheels"):format(p.key), { p.key })
            end
        end

        local edgeEff = opts.edgeEfficiency or {}
        for pi, p in ipairs(paths) do
            local path = { id = "p" .. pi, nodes = {}, stages = {}, efficiency = 1, torqueLimitNm = nil, combinations = 1 }
            for _, n in ipairs(p.nodes) do
                if n ~= SRC and n ~= SNK then
                    path.nodes[#path.nodes + 1] = n
                    local st = stageOf(n, designOf(n))
                    path.stages[#path.stages + 1] = st
                    path.efficiency = path.efficiency * st.efficiency
                    if st.torqueNm and (not path.torqueLimitNm or st.torqueNm < path.torqueLimitNm) then
                        path.torqueLimitNm = st.torqueNm
                    end
                    path.combinations = path.combinations * #st.ratios
                    if st.kind == "selector" then res.selectors[n] = true end
                end
            end
            for _, idx in ipairs(p.edges) do path.efficiency = path.efficiency * (edgeEff[idx] or 1) end
            res.paths[#res.paths + 1] = path
        end
        if #res.paths > 1 then res.selection = "selectable" end
        return res
    end

    -- ---------------------------------------------------------------------------------------------
    -- Derivations a runtime may use (implementation detail; not the spec)
    -- ---------------------------------------------------------------------------------------------

    --- Every ratio combination on one path, lowest gear (largest reduction) first. Nothing removed.
    function M.combinations(path)
        local combos = { { ratio = 1, choice = {} } }
        for si, st in ipairs(path.stages) do
            if #st.ratios > 1 or st.kind == "gearbox" or st.kind == "range" then
                local nextCombos = {}
                for _, c in ipairs(combos) do
                    for gi, r in ipairs(st.ratios) do
                        local choice = {}
                        for k, v in pairs(c.choice) do choice[k] = v end
                        choice[si] = gi
                        nextCombos[#nextCombos + 1] = { ratio = c.ratio * r, choice = choice }
                    end
                end
                combos = nextCombos
            else
                for _, c in ipairs(combos) do c.ratio = c.ratio * st.ratios[1] end
            end
        end
        table.sort(combos, function(a, b) return a.ratio > b.ratio end)
        return combos
    end

    --- A sequential ladder for a runtime that has one shifter. `minStep` (relative, default 0) prunes only
    --- within this one path; across paths nothing is ever merged.
    function M.ladder(path, minStep)
        minStep = minStep or 0
        local out = {}
        for _, c in ipairs(M.combinations(path)) do
            local last = out[#out]
            if not last or (last - c.ratio) / last > minStep then out[#out + 1] = c.ratio end
        end
        return out
    end

    --- Virtual gears in the Gearbox DLL's shape ({ceilingMps, share}), from overall ratios against the
    --- car's stock reference (`topMps` reached at `topRatio`; full drive at `firstRatio`). The ceiling falls
    --- and the share rises by the same ratio, times efficiency: force traded for speed, never created.
    --- `share` is capped at 1 because today's actuator only scales drive DOWN; `capped` says so.
    function M.virtualGears(ratios, ref, efficiency)
        local eff = efficiency or 1
        local gears = {}
        for _, r in ipairs(ratios) do
            local share = (r / ref.firstRatio) * eff
            gears[#gears + 1] = { ratio = r, ceilingMps = ref.topMps * ref.topRatio / r,
                                  share = math.min(1, share), capped = share > 1 }
        end
        return gears
    end

    return M
end)
