-- ncm-core module: week.scars
-- What Race Week leaves on the city (IDEA-1262, L351). Pure rules; the host gathers facts and spawns props.
--
-- THE DAY 1 MAP NEVER CHANGES. It ships as a static world package (NCWE export) and is the same every
-- reconstruction. A server-owned prop cannot hide a static object, so scars are ADDITIVE: things the week leaves
-- around the Day 1 dressing, never edits of it. Rollover wipes them: every key carries the run, so a new run is a
-- new key set and the host removes whatever the old run left.
--
-- TWO SOURCES.
--   * INCIDENTS (recorded with a position: `incident` x/y/z): a person hit becomes a memorial, a heavy car crash
--     (band >= 3) wreckage, a lighter contact or an object hit debris. Incidents cluster in CELL-metre cells per class;
--     a cell that keeps happening grows its kit. A memorial is moved off the carriageway to the pavement behind the
--     nearest Day 1 barrier when one is within SNAP metres.
--   * WEAR: the city's tolerance (never published -- players read the city, not a meter: doc 47 §1.6) sets a level,
--     and each level adds litter, then broken barrier sections and dumped tyres, behind every site's barriers. The
--     host ratchets the level: what the city reached this run does not heal before rollover.
-- Deterministic: the same run, incidents and level give the same scars on every server boot.
local Core = NcmCore

Core.define("week.scars", function(C)
    local M = { version = "0.1.0", CELL = 8, SNAP = 25, BEHIND = 1.4, BUDGET = 1500 }
    local Hash = C.get("vocabulary.hash")
    local atan2 = math.atan2 or math.atan                        -- LuaJIT has atan2; Lua 5.4's atan takes two arguments

    local P = {
        candle = [[base\environment\decoration\lighting\candles\candle_simple\candle_simple_a_fresh.mesh]],
        candle_burned = [[base\environment\decoration\lighting\candles\candle_simple\candle_simple_a_burned.mesh]],
        candle_stand = [[base\environment\decoration\lighting\candles\candle_stand_funeral\candle_stand_funeral_a.mesh]],
        flowers_a = [[base\environment\decoration\containers\vases\poor_flower_pot\poor_flower_pot_a.mesh]],
        flowers_b = [[base\environment\decoration\containers\vases\poor_flower_pot\poor_flower_pot_b.mesh]],
        tape = [[base\environment\architecture\megabuilding\decorations\police_tape\megabuilding_police_tape_a.mesh]],
        barrier_broken_a = [[base\environment\decoration\public_utility\roadblock\road_barrier_02\road_barrier_02_a_broken_a.mesh]],
        barrier_broken_b = [[base\environment\decoration\public_utility\roadblock\road_barrier_02\road_barrier_02_a_broken_b.mesh]],
        tire_a = [[base\environment\decoration\vehicles\deco_tire_1.mesh]],
        tire_b = [[base\environment\decoration\vehicles\deco_tire_2.mesh]],
        tire_flat = [[base\environment\decoration\vehicles\thorton_galena_tire_flat_01.mesh]],
        tire_blocker = [[base\environment\decoration\public_utility\road_block\tire_blocker\tire_blocker_a.mesh]],
        bag_a = [[base\environment\decoration\garbage\trash\garbage_bag\garbage_bag_a.mesh]],
        bag_c = [[base\environment\decoration\garbage\trash\garbage_bag\garbage_bag_c.mesh]],
        bag_f = [[base\environment\decoration\garbage\trash\garbage_bag\garbage_bag_f.mesh]],
        box_a = [[base\environment\vegetation\debris\trash\debris_trash_cardboard_box_open_a.mesh]],
        box_d = [[base\environment\vegetation\debris\trash\debris_trash_cardboard_box_open_d.mesh]],
    }
    M.MODELS = P

    -- A kit is pieces at offsets in the kit's own frame: x along the kit's facing-right, y outward, metres.
    M.KITS = {
        memorial = { { P.candle_stand, 0, 0.2 }, { P.flowers_a, -0.6, 0 }, { P.flowers_b, 0.6, 0.1 },
                     { P.candle, -0.3, -0.3 }, { P.candle, 0.2, -0.35 }, { P.candle, 0.5, -0.25 } },
        memorial_more = { { P.tape, 0, 0.9 }, { P.candle, -0.9, -0.4 }, { P.candle_burned, 0.9, -0.4 }, { P.flowers_a, 1.2, 0.2 } },
        wreck = { { P.barrier_broken_a, -2.5, 0 }, { P.tire_flat, 1.2, -0.6 }, { P.tire_a, 2.1, 0.4 } },
        wreck_more = { { P.barrier_broken_b, 2.5, 0.6 }, { P.tire_b, -1.5, -1.0 }, { P.box_a, 0.3, 1.0 } },
        contact = { { P.tire_a, 0, 0 }, { P.box_d, 0.9, 0.3 } },
        contact_more = { { P.barrier_broken_a, -2.0, 0.4 } },
        litter = { { P.bag_a, 0, 0 }, { P.bag_c, 0.6, 0.3 }, { P.box_a, -0.7, 0.2 } },
        wear = { { P.barrier_broken_b, 0, 0.2 }, { P.bag_f, 1.9, 0.5 } },
        ruin = { { P.tire_blocker, 0, 0.3 }, { P.tire_flat, 1.4, -0.2 }, { P.box_d, -1.2, 0.4 }, { P.bag_c, -1.8, 0.6 } },
    }

    -- Wear levels by tolerance (the curve's chapters: enthusiasm ~0.8, concern ~0.6, resentment ~0.4, rejection ~0.2).
    -- `spots` is how many anchors per site carry that level's kit.
    M.LEVELS = { { below = 0.62, kit = "litter", spots = 3 }, { below = 0.45, kit = "wear", spots = 3 },
                 { below = 0.30, kit = "ruin", spots = 3 } }

    --- The wear level this tolerance reaches (0 = none). The host keeps the maximum seen this run.
    function M.level(tolerance)
        local t, lv = tonumber(tolerance) or 1, 0
        for i, L in ipairs(M.LEVELS) do if t < L.below then lv = i end end
        return lv
    end

    --- The incident's scar class, or nil for incidents that leave nothing (speeding, cuts, lane).
    function M.class(kind, band)
        band = tonumber(band) or 1
        if kind == "person" then return "memorial" end
        if kind == "car" then return band >= 3 and "wreck" or (band >= 2 and "contact" or nil) end
        if kind == "object" then return "contact" end
        return nil
    end

    local function cellKey(cls, x, y)
        return ("%s:%d:%d"):format(cls, math.floor(x / M.CELL), math.floor(y / M.CELL))
    end

    -- nearest anchor within SNAP metres (anchors: { x, y, z, ox, oy } -- ox/oy points away from the road)
    local function nearestAnchor(sites, x, y)
        local best, bd = nil, M.SNAP
        for _, s in ipairs(sites or {}) do
            for _, a in ipairs(s.anchors or {}) do
                local d = math.sqrt((a.x - x) ^ 2 + (a.y - y) ^ 2)
                if d < bd then best, bd = a, d end
            end
        end
        return best
    end

    -- Lay a kit at (x, y, z) with its outward axis (ox, oy); `prefix` makes every piece key unique and stable.
    local function lay(out, kitName, prefix, x, y, z, ox, oy, yawSeed)
        local kit = M.KITS[kitName]
        if not kit then return end
        local rx, ry = oy, -ox                                    -- the kit's right, looking outward
        for i, piece in ipairs(kit) do
            local px, py = piece[2], piece[3]
            local jitter = (Hash.unit(yawSeed, i) - 0.5) * 50
            out[#out + 1] = {
                key = ("%s:%s:%d"):format(prefix, kitName, i), model = piece[1],
                x = x + rx * px + ox * py, y = y + ry * px + oy * py, z = z,
                yaw = math.deg(atan2(-ox, oy)) + jitter,       -- facing outward: NCWE/Open77 yaw 0 faces +Y
            }
        end
    end

    --- The run's scars.
    --- in = { run, seed, level (0..#LEVELS), incidents = { { id, kind, band, x, y, z } },
    ---        sites = { { id, anchors = { { x, y, z, ox, oy } } } }, yield = optional function }
    --- `yield` (KB-410, again 2026-10-08 19:37): a host under a per-slice instruction quota passes one (e.g. `Wait(0)`); it
    --- is called between incident cells and between sites, and changes nothing about the result.
    --- -> list of { key, model, x, y, z, yaw }, at most BUDGET (incident scars first, oldest first).
    function M.plan(input)
        local run, seed = tostring(input.run or 0), tostring(input.seed or "")
        local yield = type(input.yield) == "function" and input.yield or function() end
        local out = {}
        -- incidents: one cell per class, anchored at its first (lowest id) incident
        local cells, order = {}, {}
        local incs = {}
        for _, e in ipairs(input.incidents or {}) do
            if e.x and e.y and e.z then incs[#incs + 1] = e end
        end
        table.sort(incs, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
        for _, e in ipairs(incs) do
            local cls = M.class(e.kind, e.band)
            if cls then
                local k = cellKey(cls, e.x, e.y)
                local c = cells[k]
                if not c then
                    c = { cls = cls, x = e.x, y = e.y, z = e.z, n = 0, key = k }
                    cells[k] = c; order[#order + 1] = c
                end
                c.n = c.n + 1
            end
        end
        for _, c in ipairs(order) do
            yield()
            local x, y, z, ox, oy = c.x, c.y, c.z, 0, 1
            local a = nearestAnchor(input.sites, x, y)
            if a then
                ox, oy = a.ox or 0, a.oy or 1
                if c.cls == "memorial" then                         -- off the carriageway, behind the barrier
                    x, y, z = a.x + ox * M.BEHIND, a.y + oy * M.BEHIND, a.z
                end
            end
            local prefix = ("R%s:%s"):format(run, c.key)
            lay(out, c.cls, prefix, x, y, z, ox, oy, Hash.key(seed, prefix))
            if c.n >= 3 then lay(out, c.cls .. "_more", prefix, x, y, z, ox, oy, Hash.key(seed, prefix, "more")) end
        end
        -- wear: each level adds its kit at `spots` anchors per site, chosen by the run seed
        local level = math.max(0, math.min(#M.LEVELS, math.floor(tonumber(input.level) or 0)))
        for _, s in ipairs(input.sites or {}) do
            yield()
            local anchors = s.anchors or {}
            if #anchors > 0 then
                for lv = 1, level do
                    local L = M.LEVELS[lv]
                    local r = Hash.stream(seed, run, s.id, "wear", lv)
                    for spot = 1, math.min(L.spots, #anchors) do
                        local a = anchors[r:int(1, #anchors)]
                        local prefix = ("R%s:wear:%s:%d:%d"):format(run, tostring(s.id), lv, spot)
                        lay(out, L.kit, prefix, a.x + (a.ox or 0) * M.BEHIND, a.y + (a.oy or 1) * M.BEHIND, a.z,
                            a.ox or 0, a.oy or 1, Hash.key(seed, prefix))
                    end
                end
            end
        end
        while #out > M.BUDGET do table.remove(out) end
        return out
    end

    --- What the host must do to go from the props it has (key -> id) to the plan: { add = {piece}, remove = {key} }.
    function M.diff(have, plan)
        local want, add, remove = {}, {}, {}
        for _, p in ipairs(plan) do
            want[p.key] = true
            if not have[p.key] then add[#add + 1] = p end
        end
        for k in pairs(have) do if not want[k] then remove[#remove + 1] = k end end
        table.sort(remove)
        return { add = add, remove = remove }
    end

    return M
end)
