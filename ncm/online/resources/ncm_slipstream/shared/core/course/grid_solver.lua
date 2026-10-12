-- ncm-core module: course.grid_solver
-- Start grids from the game's own lanes (L250 step 1; owner: "dynamic grid solving to leverage our understanding of
-- local geometry so everyone gets a fair unblocked start").
--
-- `tools/bake-grids.py` lays every race leg's grid offline: the road behind the start found by following lane
-- centrelines (junctions included), its parallel lanes as columns (2-4 wide; a single wide lane carries two tight
-- columns), rows staggered on two columns, 10 m apart (8 m when the road behind is short), NEVER past the end of a
-- lane -- and the opposite lanes of the same road only when the grid would otherwise be short. The Paddock server
-- carries the result as `PaddockGridSlots["<start>__<next>"]` = { formation, cols, depth, flags, slots = "x,y,z,h,col,row;..." }.
--
-- This module turns one of those into the slots a race uses: hand overrides first (`data.grid_overrides`, by leg or by
-- start node), then the bake, pole first, yaw in the convention every grid here uses (race heading + the profile's
-- slot heading offset, as `paddock.live` gridSlots/roadSlots). Pure; both the Paddock and the human race controller
-- read it.
local Core = NcmCore

Core.define("course.grid_solver", function(C)
    local M = { version = "0.1.0" }
    local Overrides = C.get("data.grid_overrides")

    --- A baked entry's slots: { { x, y, z, heading, col, row } }.
    function M.decode(entry)
        if type(entry) ~= "table" or type(entry.slots) ~= "string" then return {} end
        local out = {}
        for x, y, z, h, c, r in entry.slots:gmatch("([^,;]+),([^,;]+),([^,;]+),([^,;]+),([^,;]+),([^,;]+)") do
            out[#out + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z), heading = tonumber(h), col = tonumber(c), row = tonumber(r) }
        end
        return out
    end

    --- The override for a leg: by leg key first, then by start node id.
    function M.override(startId, nextId)
        return Overrides.LEGS[tostring(startId) .. "__" .. tostring(nextId)] or Overrides.NODES[tostring(startId)]
    end

    --- Up to `n` slots for a race starting `startId` towards `nextId`, from the baked `entry` and its override, with
    --- yaw from `profile` (data.grid_profiles: startSlotHeadingOffsetDeg). Returns slots ({ x, y, z, yaw, heading,
    --- slot, col, row }) and a note ("baked", "override", "short", "none").
    function M.slotsFor(entry, startId, nextId, n, profile)
        profile = profile or {}
        local yawOff = profile.startSlotHeadingOffsetDeg or -90
        local ov = M.override(startId, nextId)
        local list, note
        if ov and type(ov.slots) == "table" and #ov.slots > 0 then
            list, note = {}, "override"
            for i, s in ipairs(ov.slots) do
                list[i] = { x = s.x, y = s.y, z = s.z, heading = s.heading or s.h, col = s.col or (((i - 1) % 2) + 1), row = s.row or math.ceil(i / 2) }
            end
        else
            list, note = M.decode(entry), "baked"
            if ov and type(ov.excludeCols) == "table" then
                local drop = {}
                for _, c in ipairs(ov.excludeCols) do drop[c] = true end
                local kept = {}
                for _, s in ipairs(list) do if not drop[s.col] then kept[#kept + 1] = s end end
                list = kept
            end
        end
        local out = {}
        for i = 1, math.min(n or #list, #list) do
            local s = list[i]
            out[i] = { x = s.x, y = s.y, z = s.z, heading = s.heading, yaw = ((s.heading or 0) + yawOff) % 360, slot = i, col = s.col, row = s.row }
        end
        if #list == 0 then note = "none" elseif #out < (n or 0) then note = "short" end
        return out, note
    end

    return M
end)
