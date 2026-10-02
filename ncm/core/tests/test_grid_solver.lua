-- course.grid_solver (L250 step 1): baked lane grids, overrides, the yaw convention.
local ENTRY = { formation = "staggered", cols = 2, depth = 120, flags = "",
    slots = "10,0,5,90,1,1;14,-5,5,90,2,1;10,-10,5,90,1,2;14,-15,5,90,2,2;10,-20,5,90,1,3" }

return {
    a_baked_grid_decodes_in_pole_order_with_the_profile_yaw = function(T)
        local G = T.Core.get("course.grid_solver")
        local slots, note = G.slotsFor(ENTRY, "nodeA", "nodeB", 4, { startSlotHeadingOffsetDeg = -90 })
        T.eq(note, "baked"); T.eq(#slots, 4)
        T.eq(slots[1].x, 10); T.eq(slots[1].slot, 1); T.eq(slots[2].col, 2)
        T.eq(slots[1].yaw, 0, "heading 90 + offset -90")
        T.eq(slots[3].row, 2)
    end,

    a_short_grid_says_so_and_never_invents_slots = function(T)
        local G = T.Core.get("course.grid_solver")
        local slots, note = G.slotsFor(ENTRY, "nodeA", "nodeB", 12, {})
        T.eq(#slots, 5); T.eq(note, "short")
        local none, n2 = G.slotsFor(nil, "x", "y", 12, {})
        T.eq(#none, 0); T.eq(n2, "none")
    end,

    overrides_win_by_leg_then_by_node = function(T)
        local G = T.Core.get("course.grid_solver")
        local O = T.Core.get("data.grid_overrides")
        O.NODES.nodeA = { excludeCols = { 2 } }
        local slots = G.slotsFor(ENTRY, "nodeA", "nodeB", 12, {})
        T.eq(#slots, 3, "column 2 dropped")
        for _, s in ipairs(slots) do T.eq(s.col, 1) end
        O.LEGS["nodeA__nodeB"] = { slots = { { x = 1, y = 2, z = 3, heading = 180 } } }
        local one, note = G.slotsFor(ENTRY, "nodeA", "nodeB", 12, { startSlotHeadingOffsetDeg = 0 })
        T.eq(note, "short"); T.eq(#one, 1); T.eq(one[1].x, 1); T.eq(one[1].yaw, 180)
        O.NODES.nodeA = nil; O.LEGS["nodeA__nodeB"] = nil
    end,

    the_shipped_bake_never_stacks_cars_or_strays_from_its_start = function(T)
        -- the Paddock server's generated grids, read as data: no two slots of a leg closer than 2.5 m, every slot
        -- within 160 m of its start node
        local path = T.root and (T.root .. "/../online/resources/ncm_paddock/server/grid_slots_data.lua") or nil
        local f = path and io.open(path, "r")
        if not f then return end
        local src = f:read("*a"); f:close()
        local env = {}
        local chunk = (loadstring or load)(src, "grid_slots_data", "t", env)
        if setfenv then setfenv(chunk, env) end
        chunk()
        local G = T.Core.get("course.grid_solver")
        local Nodes = T.Core.get("data.nodes")
        local legs, bad = 0, 0
        for key, entry in pairs(env.PaddockGridSlots or {}) do
            legs = legs + 1
            local startId = key:match("^(.-)__")
            local node = Nodes.byId(startId)
            local s = G.decode(entry)
            for i = 1, #s do
                if node and math.sqrt((s[i].x - node.x) ^ 2 + (s[i].y - node.y) ^ 2) > 160 then bad = bad + 1 end
                for j = i + 1, #s do
                    if math.sqrt((s[i].x - s[j].x) ^ 2 + (s[i].y - s[j].y) ^ 2) < 2.5 then bad = bad + 1 end
                end
            end
        end
        T.ok(legs > 1000, "the bake covers the legs (" .. legs .. ")")
        T.eq(bad, 0, "stacked or stray slots")
    end,
}
