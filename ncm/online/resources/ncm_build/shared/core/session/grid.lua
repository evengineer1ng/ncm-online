-- ncm-core module: session.grid
-- Grid slot assignment and slot positions. v0 order is check-in order (rating splits are L38, later).
-- Slots sit behind the start line in two columns, along the start gate's direction of travel.
-- Pure: returns JSON-safe records; hosts place markers and check presence.
local Core = NcmCore

Core.define("session.grid", function(C)
    local M = { version = "0.0.1" }

    M.ROW_SPACING_M = 7.0      -- distance between rows
    M.COLUMN_OFFSET_M = 2.6    -- lateral offset of each column from the road centre
    M.FIRST_ROW_BEHIND_M = 6.0 -- pole sits this far behind the start line
    M.SLOT_RADIUS_M = 30.0     -- "at your mark" tolerance (v0: generous; the road is the grid)

    -- LuaJIT has math.atan2 and a one-argument math.atan; Lua 5.4 has the two-argument math.atan.
    local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

    --- Order entrants. v0 street: by checkedInAt ascending, then driverId. Organized events (opts.by =
    --- "seat"): by seatOrder (the roster's grid order index), unseated last.
    function M.order(entrants, opts)
        opts = opts or {}
        if type(opts.order) == "table" then
            -- an explicit ranking (driverId -> rank) from a prior session (competition.format gridFor); unranked last
            local list = {}
            for _, e in ipairs(entrants) do list[#list + 1] = e end
            table.sort(list, function(a, b)
                local ra, rb = opts.order[a.driverId] or math.huge, opts.order[b.driverId] or math.huge
                if ra ~= rb then return ra < rb end
                return tostring(a.driverId) < tostring(b.driverId)
            end)
            return list
        end
        local list = {}
        for _, e in ipairs(entrants) do list[#list + 1] = e end
        local bySeat = opts and opts.by == "seat"
        table.sort(list, function(a, b)
            if bySeat then
                local sa, sb = a.seatOrder or math.huge, b.seatOrder or math.huge
                if sa ~= sb then return sa < sb end
            end
            local ca, cb = a.checkedInAt or a.registeredAt or 0, b.checkedInAt or b.registeredAt or 0
            if ca ~= cb then return ca < cb end
            return tostring(a.driverId) < tostring(b.driverId)
        end)
        return list
    end

    --- Slot position i (1-based) behind a start gate { x, y, z, dir = {x,y} }.
    function M.slotPosition(startGate, i)
        local row = math.floor((i - 1) / 2)
        local col = ((i - 1) % 2 == 0) and -1 or 1     -- pole on the left column
        local fx, fy = startGate.dir.x, startGate.dir.y
        local lx, ly = -fy, fx                          -- lateral (left of travel)
        local back = M.FIRST_ROW_BEHIND_M + row * M.ROW_SPACING_M
        return {
            x = startGate.x - fx * back + lx * col * M.COLUMN_OFFSET_M,
            y = startGate.y - fy * back + ly * col * M.COLUMN_OFFSET_M,
            z = startGate.z or 0,
            heading = (math.deg(atan2(fy, fx)) + 360) % 360,
        }
    end

    --- Where a chauffeured ride drops a driver: behind the last grid row, off the racing line on the right
    --- of travel, facing the grid (M7.5a pickup). `entrantCount` sizes the rows to clear.
    M.DROPOFF_BEHIND_LAST_ROW_M = 25
    M.DROPOFF_LATERAL_M = 12
    function M.dropoffPosition(startGate, entrantCount)
        local rows = math.max(1, math.ceil((tonumber(entrantCount) or 0) / 2))
        local fx, fy = startGate.dir.x, startGate.dir.y
        local lx, ly = -fy, fx
        local back = M.FIRST_ROW_BEHIND_M + (rows - 1) * M.ROW_SPACING_M + M.DROPOFF_BEHIND_LAST_ROW_M
        return {
            x = startGate.x - fx * back - lx * M.DROPOFF_LATERAL_M,
            y = startGate.y - fy * back - ly * M.DROPOFF_LATERAL_M,
            z = startGate.z or 0,
            heading = (math.deg(atan2(fy, fx)) + 360) % 360,
        }
    end

    --- Assign slots. entrants = { {driverId, entryId, checkedInAt, display?}, ... } -> array of
    --- { slot, driverId, entryId, display, x, y, z, heading, radiusM }.
    function M.assign(entrants, startGate, opts)
        local out = {}
        for i, e in ipairs(M.order(entrants, opts)) do
            local p = M.slotPosition(startGate, i)
            out[i] = {
                slot = i, driverId = e.driverId, entryId = e.entryId, display = e.display,
                teamId = e.teamId, seatIndex = e.seatIndex,
                x = p.x, y = p.y, z = p.z, heading = p.heading, radiusM = M.SLOT_RADIUS_M,
            }
        end
        return out
    end

    return M
end)
