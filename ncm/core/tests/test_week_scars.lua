-- week.scars (IDEA-1262, L351): what Race Week leaves on the city, wiped at rollover.
local function site()
    return { id = "pdm", anchors = {
        { x = 0, y = 0, z = 13, ox = -1, oy = 0 }, { x = 0, y = 10, z = 13, ox = -1, oy = 0 },
        { x = 0, y = 20, z = 13, ox = -1, oy = 0 }, { x = 0, y = 30, z = 13, ox = -1, oy = 0 } } }
end

local function keys(plan)
    local k = {}
    for _, p in ipairs(plan) do k[#k + 1] = p.key end
    table.sort(k)
    return table.concat(k, ",")
end

return {
    classes_follow_the_incident = function(T)
        local S = T.Core.get("week.scars")
        T.eq(S.class("person", 1), "memorial")
        T.eq(S.class("car", 3), "wreck")
        T.eq(S.class("car", 2), "contact")
        T.eq(S.class("car", 1), nil, "a touch leaves nothing")
        T.eq(S.class("object", 1), "contact")
        T.eq(S.class("speed", 1), nil)
        T.eq(S.class("cut", 2), nil)
    end,

    levels_by_tolerance = function(T)
        local S = T.Core.get("week.scars")
        T.eq(S.level(0.9), 0, "a joyful city is clean")
        T.eq(S.level(0.6), 1)
        T.eq(S.level(0.4), 2)
        T.eq(S.level(0.1), 3)
        T.eq(S.level(nil), 0)
    end,

    a_clean_day_one_has_no_scars = function(T)
        local S = T.Core.get("week.scars")
        T.eq(#S.plan({ run = 4, seed = "s", level = 0, incidents = {}, sites = { site() } }), 0)
    end,

    memorial_moves_behind_the_nearest_barrier = function(T)
        local S = T.Core.get("week.scars")
        local plan = S.plan({ run = 4, seed = "s", level = 0, sites = { site() },
            incidents = { { id = 1, kind = "person", band = 1, x = 6, y = 11, z = 12.6 } } })
        T.eq(#plan, #S.KITS.memorial)
        for _, p in ipairs(plan) do
            T.ok(p.x < 0, "on the pavement side of the barrier line, not in the road")
            T.eq(p.z, 13, "at the barrier's pavement height")
            T.ok(p.key:find("^R4:"), "keys carry the run")
        end
    end,

    incidents_cluster_and_grow = function(T)
        local S = T.Core.get("week.scars")
        local one = S.plan({ run = 1, seed = "s", incidents = { { id = 1, kind = "car", band = 3, x = 50, y = 50, z = 0 } } })
        local three = S.plan({ run = 1, seed = "s", incidents = {
            { id = 1, kind = "car", band = 3, x = 50, y = 50, z = 0 }, { id = 2, kind = "car", band = 4, x = 51, y = 52, z = 0 },
            { id = 3, kind = "car", band = 3, x = 53, y = 50, z = 0 } } })
        T.eq(#one, #S.KITS.wreck)
        T.eq(#three, #S.KITS.wreck + #S.KITS.wreck_more, "one cell, a bigger wreck")
        local apart = S.plan({ run = 1, seed = "s", incidents = {
            { id = 1, kind = "car", band = 3, x = 50, y = 50, z = 0 }, { id = 2, kind = "car", band = 3, x = 150, y = 50, z = 0 } } })
        T.eq(#apart, 2 * #S.KITS.wreck, "two places, two wrecks")
        local noPos = S.plan({ run = 1, seed = "s", incidents = { { id = 1, kind = "person", band = 1 } } })
        T.eq(#noPos, 0, "an incident without a position leaves nothing")
    end,

    wear_accumulates_by_level = function(T)
        local S = T.Core.get("week.scars")
        local function n(lv) return #S.plan({ run = 2, seed = "s", level = lv, sites = { site() } }) end
        T.eq(n(1), 3 * #S.KITS.litter)
        T.eq(n(2), 3 * #S.KITS.litter + 3 * #S.KITS.wear)
        T.eq(n(3), 3 * (#S.KITS.litter + #S.KITS.wear + #S.KITS.ruin))
        -- a higher level keeps every lower level's pieces (nothing jumps around as the city sours)
        local l1 = S.plan({ run = 2, seed = "s", level = 1, sites = { site() } })
        local l3 = S.plan({ run = 2, seed = "s", level = 3, sites = { site() } })
        local have = {}
        for _, p in ipairs(l3) do have[p.key] = p end
        for _, p in ipairs(l1) do
            T.ok(have[p.key] and have[p.key].x == p.x and have[p.key].y == p.y, "level 1 piece unchanged at level 3")
        end
    end,

    deterministic_and_rollover_is_a_new_key_set = function(T)
        local S = T.Core.get("week.scars")
        local input = { run = 7, seed = "seed7", level = 2, sites = { site() },
            incidents = { { id = 9, kind = "person", band = 1, x = 2, y = 2, z = 13 } } }
        T.eq(keys(S.plan(input)), keys(S.plan(input)), "same run, same scars, every boot")
        local nextRun = S.plan({ run = 8, seed = "seed8", level = 0, sites = { site() }, incidents = {} })
        T.eq(#nextRun, 0, "the loop resets: Day 1 is clean")
        local have = {}
        for _, p in ipairs(S.plan(input)) do have[p.key] = "id" end
        local d = S.diff(have, nextRun)
        T.eq(#d.add, 0)
        T.eq(#d.remove, #S.plan(input), "rollover removes every scar of the old run")
    end,

    diff_adds_only_what_is_missing = function(T)
        local S = T.Core.get("week.scars")
        local plan = S.plan({ run = 1, seed = "s", incidents = { { id = 1, kind = "car", band = 3, x = 0, y = 0, z = 0 } } })
        local have = { [plan[1].key] = "a", stale = "b" }
        local d = S.diff(have, plan)
        T.eq(#d.add, #plan - 1)
        T.eq(d.remove[1], "stale")
    end,

    budget_caps_the_prop_count = function(T)
        local S = T.Core.get("week.scars")
        local incidents = {}
        for i = 1, 2000 do incidents[i] = { id = i, kind = "person", band = 1, x = i * 20, y = 0, z = 0 } end
        local plan = S.plan({ run = 1, seed = "s", incidents = incidents })
        T.eq(#plan, S.BUDGET, "never more props than the budget")
        T.ok(plan[1].key:find("^R1:memorial:2:0:"), "the oldest incidents keep their scars")
    end,

    a_yield_changes_nothing_but_is_called = function(T)
        local S = T.Core.get("week.scars")
        local inc = { { id = 1, kind = "person", band = 1, x = 1, y = 5, z = 13 }, { id = 2, kind = "car", band = 3, x = 90, y = 90, z = 0 } }
        local calls = 0
        local a = S.plan({ run = 2, seed = "s", level = 3, incidents = inc, sites = { site() } })
        local b = S.plan({ run = 2, seed = "s", level = 3, incidents = inc, sites = { site() }, yield = function() calls = calls + 1 end })
        T.eq(keys(a), keys(b), "same plan with a yield")
        T.ok(calls >= 3, "called per cell and per site (KB-410)")
    end,
}
