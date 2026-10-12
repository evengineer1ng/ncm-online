-- ncm-core module: course.generator
-- The procedural race generator (L236). The owner hand-picked every node in `data.nodes` as a start/finish
-- location; ten named roots used a tiny subset of the pairs, so "race ten times and you have done them all" held for
-- multiplayer and the Paddock alike. This turns the node set into every eligible race:
--
--   * a sprint: any two nodes whose separation passes the distance filter;
--   * a checkpointed race: the same, through one or two other nodes as checkpoints, each leg long enough to be a
--     leg, and the whole not wandering too far from the direct line (a detour cap), so a checkpoint is on the way
--     somewhere rather than a random zig-zag.
--
-- Generated routes are unnamed ("Hanford Overpass to Stadium via Chapel"). Their ids ENCODE their nodes
-- ("gen-k3f9-a8d2-zz01"), four base-36 characters per node from a hash of its id, so any generated id resolves again
-- after a restart with no registry and no database -- and a route that races well can later be formalised as a
-- named root.
--
-- Never generated, because the owner authors them: drag races (the generator never sets a discipline, so its routes
-- are street sprints) and ovals (their nodes carry `oval = true` and are left out of the pool). Runtime nodes (a
-- Street Call's temporary start) are not `raceLegal` and never enter the pool either.
local Core = NcmCore

Core.define("course.generator", function(C)
    local M = { version = "0.1.0", PREFIX = "gen-" }
    local Nodes = C.get("data.nodes")
    local Hash = C.get("vocabulary.hash")

    -- Tunable defaults; callers pass their own per series/tier.
    M.DEFAULTS = {
        minM = 900,            -- the whole route, summed over legs
        maxM = 7000,
        legMinM = 450,         -- no leg shorter than this (and no two nodes of a route closer than this)
        detourMax = 1.9,       -- legs summed / direct start->finish; the direct line must also be >= legMinM
        checkpoints = 2,       -- up to this many
        checkpointShare = 0.5, -- of picks, the share that try for checkpoints at all
    }

    local function planar(a, b)
        local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
        return math.sqrt(dx * dx + dy * dy)
    end
    M.planar = planar

    local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
    --- A node's four-character code: stable for as long as its id is.
    local codeCache = {}
    function M.code(nodeId)
        local c = codeCache[nodeId]
        if c then return c end
        local h = Hash.fnv1a32("node|" .. tostring(nodeId)) % (36 ^ 4)
        local s = ""
        for _ = 1, 4 do
            local d = h % 36
            s = B36:sub(d + 1, d + 1) .. s
            h = math.floor(h / 36)
        end
        codeCache[nodeId] = s
        return s
    end

    local pool, byCode = nil, nil
    --- The authored start/finish nodes the generator may use, and their codes (checked unique).
    function M.pool()
        if pool then return pool, byCode end
        pool, byCode = {}, {}
        for _, n in ipairs(Nodes.LIST) do
            if n.raceLegal and not n.oval and not n.generatorExclude then
                local code = M.code(n.id)
                if byCode[code] then error("course.generator: node code collision " .. code .. " (" .. n.id .. ", " .. byCode[code].id .. ")") end
                byCode[code] = n
                pool[#pool + 1] = n
            end
        end
        return pool, byCode
    end

    --- The route id for a node sequence (start, checkpoints..., finish).
    function M.encode(nodeIds)
        local parts = {}
        for i, id in ipairs(nodeIds) do parts[i] = M.code(id) end
        return M.PREFIX .. table.concat(parts, "-")
    end

    function M.isGenerated(rootId) return type(rootId) == "string" and rootId:sub(1, #M.PREFIX) == M.PREFIX end

    local function nameOf(seq)
        local s, f = seq[1], seq[#seq]
        local name = ("%s to %s"):format(s.name, f.name)
        if #seq == 3 then name = name .. (" via %s"):format(seq[2].name)
        elseif #seq == 4 then name = name .. (" via %s & %s"):format(seq[2].name, seq[3].name) end
        return name
    end

    --- Length and validity of a node sequence under opts. Returns lengthM or nil, reason.
    function M.check(seq, opts)
        opts = opts or M.DEFAULTS
        local legMin = opts.legMinM or M.DEFAULTS.legMinM
        if #seq < 2 or #seq > 2 + (opts.checkpoints or M.DEFAULTS.checkpoints) then return nil, "shape" end
        for i = 1, #seq do
            for j = i + 1, #seq do
                if seq[i].id == seq[j].id then return nil, "repeat" end
                if planar(seq[i], seq[j]) < legMin then return nil, "too_close" end
            end
        end
        local len = 0
        for i = 2, #seq do len = len + planar(seq[i - 1], seq[i]) end
        if len < (opts.minM or M.DEFAULTS.minM) then return nil, "too_short" end
        if len > (opts.maxM or M.DEFAULTS.maxM) then return nil, "too_long" end
        if #seq > 2 and len / planar(seq[1], seq[#seq]) > (opts.detourMax or M.DEFAULTS.detourMax) then return nil, "detour" end
        return len
    end

    --- Decode a generated id into a root (the shape `data.roots` holds), or nil.
    function M.decode(rootId)
        if not M.isGenerated(rootId) then return nil end
        local _, codes = M.pool()
        local seq = {}
        for code in rootId:sub(#M.PREFIX + 1):gmatch("[0-9a-z]+") do
            local n = codes[code]
            if not n then return nil end
            seq[#seq + 1] = n
        end
        if #seq < 2 or #seq > 4 then return nil end
        local mids = {}
        for i = 2, #seq - 1 do
            local n = seq[i]
            -- no heading: a node's authored heading is the way ITS race leaves it, not the way this one passes through,
            -- so the gate faces the direction of travel (course.gates derives it from the previous point)
            mids[#mids + 1] = { x = n.x, y = n.y, z = n.z, name = n.name, nodeId = n.id }
        end
        return { rootId = rootId, startNodeId = seq[1].id, endNodeId = seq[#seq].id, displayName = nameOf(seq),
            intermediate = (#mids > 0) and mids or nil, generated = true, checkpoints = #mids }
    end

    --- Every eligible sprint (no checkpoints) under opts: { { rootId, lengthM } }, in a stable order.
    -- on a host every hashed byte is metered against the instruction quota, and a schedule materialises dozens of
    -- picks at once: the sprint list for a filter is computed once
    local sprintCache = {}
    function M.sprints(opts)
        opts = opts or M.DEFAULTS
        local key = table.concat({ opts.minM or M.DEFAULTS.minM, opts.maxM or M.DEFAULTS.maxM, opts.legMinM or M.DEFAULTS.legMinM, #Nodes.LIST }, "|")
        if sprintCache[key] then return sprintCache[key] end
        local p = M.pool()
        local out = {}
        for _, a in ipairs(p) do
            for _, b in ipairs(p) do
                if a.id ~= b.id then
                    local len = M.check({ a, b }, opts)
                    if len then out[#out + 1] = { rootId = M.encode({ a.id, b.id }), lengthM = len, startId = a.id, finishId = b.id } end
                end
            end
        end
        table.sort(out, function(x, y) return x.rootId < y.rootId end)
        sprintCache[key] = out
        return out
    end

    --- One race, deterministically from the key parts. Tries a checkpointed race on `checkpointShare` of keys and
    --- falls back to a sprint. `opts.avoid` (set of rootIds) is skipped when possible. Returns rootId, root.
    function M.pick(opts, ...)
        opts = opts or M.DEFAULTS
        local rng = Hash.stream("generator", ...)
        local p = M.pool()
        local maxCp = math.max(0, math.min(2, opts.checkpoints or M.DEFAULTS.checkpoints))
        local avoid = opts.avoid or {}
        -- a district league starts in its district (`startRegion`); the rest of the route goes where it goes
        local starts = p
        if opts.startRegion then
            starts = {}
            for _, n in ipairs(p) do if n.region == opts.startRegion then starts[#starts + 1] = n end end
            if #starts == 0 then starts = p end
        end
        if maxCp > 0 and rng() < (opts.checkpointShare or M.DEFAULTS.checkpointShare) then
            for _ = 1, 60 do
                local k = rng:int(1, maxCp)
                local seq = { rng:pick(starts) }
                for _ = 1, k + 1 do seq[#seq + 1] = rng:pick(p) end
                if M.check(seq, opts) then
                    local ids = {}
                    for i, n in ipairs(seq) do ids[i] = n.id end
                    local id = M.encode(ids)
                    if not avoid[id] then return id, M.decode(id) end
                end
            end
        end
        local list = M.sprints(opts)
        if opts.startRegion then
            local keep = {}
            for _, x in ipairs(list) do
                local n = Nodes.byId(x.startId)
                if n and n.region == opts.startRegion then keep[#keep + 1] = x end
            end
            if #keep > 0 then list = keep end
        end
        if #list == 0 then return nil end
        for _ = 1, 8 do
            local s = list[rng:int(1, #list)]
            if not avoid[s.rootId] then return s.rootId, M.decode(s.rootId) end
        end
        local s = list[rng:int(1, #list)]
        return s.rootId, M.decode(s.rootId)
    end

    --- How much there is to race under opts (for the ops console and the data the owner asked for).
    function M.census(opts)
        opts = opts or M.DEFAULTS
        local sprints = M.sprints(opts)
        local lo, hi, sum = math.huge, 0, 0
        for _, s in ipairs(sprints) do lo = math.min(lo, s.lengthM); hi = math.max(hi, s.lengthM); sum = sum + s.lengthM end
        return { nodes = #M.pool(), sprints = #sprints, minM = (#sprints > 0) and math.floor(lo) or 0, maxM = math.floor(hi),
            meanM = (#sprints > 0) and math.floor(sum / #sprints) or 0 }
    end

    return M
end)
