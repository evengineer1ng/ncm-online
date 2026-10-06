-- world.seed (L321; doc 54 §F): a seed TREE (facts keyed by path, never by draw order) and composition
-- (generated base + committed modifications = current world).
local function S(T) return T.Core.get("world.seed") end

return {
    the_same_path_gives_the_same_facts = function(T)
        local Seed = S(T)
        local a = Seed.root(4242):child("earth", "infrastructure"):child("station", 3)
        local b = Seed.root(4242):child("earth"):child("infrastructure", "station", 3)
        T.eq(a:id(), b:id(), "a path is a path however it was built")
        T.eq(a:stream()(), b:stream()(), "and draws the same")
        T.ok(a:stream()() ~= Seed.root(4243):child("earth", "infrastructure", "station", 3):stream()(), "another seed differs")
    end,

    adding_a_subsystem_never_reshuffles_an_established_seed = function(T)
        local Seed = S(T)
        local root = Seed.root("night-and-sand")
        local function stations(r)
            local out = {}
            for i = 1, 5 do out[i] = r:child("snowglobe", "station", i):stream():int(1000, 9999) end
            return out
        end
        local before = stations(root)
        -- a later NCM version adds a whole new subsystem and makes many unrelated draws first
        for i = 1, 200 do local _ = root:child("asteroids", i):stream()() end
        local _ = root:child("snowglobe", "station", 99):stream()()
        local after = stations(root)
        for i = 1, 5 do T.eq(after[i], before[i], "station " .. i .. " is unchanged") end
    end,

    the_same_seed_and_history_rebuild_the_same_world = function(T)
        local Seed = S(T)
        local base = { stations = { { name = "Halo", fuel = 100 }, { name = "Kestrel", fuel = 80 } }, records = {} }
        local mods = {
            { id = "m2", at = 20, path = "stations.1.fuel", op = "add", value = -30 },
            { id = "m1", at = 10, path = "stations.2.name", op = "set", value = "Kestrel Deep" },
            { id = "m3", at = 30, path = "records", op = "append", value = { course = "ring-1", ms = 182000 } },
            { id = "m4", at = 40, path = "nebula.size", op = "set", value = 3 },
        }
        local w1, r1 = Seed.compose(base, mods)
        local w2 = Seed.compose(base, { mods[3], mods[1], mods[4], mods[2] })
        T.eq(w1.stations[1].fuel, 70, "add applied")
        T.eq(w1.stations[2].name, "Kestrel Deep", "set applied")
        T.eq(#w1.records, 1, "append applied")
        T.eq(r1.applied, 3, "three applied")
        T.eq(#r1.refused, 1, "a path the base does not have is refused, not invented")
        T.eq(w2.stations[1].fuel, w1.stations[1].fuel, "order of the list does not matter, only (at, id)")
        T.eq(base.stations[1].fuel, 100, "the base is never mutated")
    end,
}
