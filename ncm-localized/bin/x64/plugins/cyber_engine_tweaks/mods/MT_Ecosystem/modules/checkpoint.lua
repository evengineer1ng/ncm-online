-- ============================================================
-- MT_Ecosystem: modules/checkpoint.lua
-- Shared checkpoint detection helpers for circuit-based race modes.
-- Used by knockout.lua and potentially future circuit race types.
--
-- Checkpoint progress is computed as:
--   completedCheckpoints * 1000 + (1000 - normalizedDistToNext)
-- This gives a monotonically increasing value as a driver progresses
-- around the circuit, suitable for ranking.
-- ============================================================

local Checkpoint = {}
local i18n = require("modules/i18n")

-- â”€â”€ Constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local DEFAULT_RADIUS = 50.0   -- metres; checkpoint capture radius

-- â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

--- 3D distance between two positions.
local function dist3d(a, b)
    if not a or not b then return 999999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

--- 2D distance (ignoring Z) between two positions.
local function dist2d(a, b)
    if not a or not b then return 999999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return math.sqrt(dx*dx + dy*dy)
end

-- â”€â”€ Public API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

--- Check if a position is within capture radius of a checkpoint node.
--- @param pos    table  { x, y, z }
--- @param node   table  { x, y, z }
--- @param radius number (optional) override default radius
--- @return boolean
function Checkpoint.isNear(pos, node, radius)
    return dist2d(pos, node) <= (radius or DEFAULT_RADIUS)
end

--- Distance from a position to a checkpoint node (2D).
--- @param pos  table { x, y, z }
--- @param node table { x, y, z }
--- @return number
function Checkpoint.distanceTo(pos, node)
    return dist2d(pos, node)
end

--- Distance from a position to a checkpoint node (3D).
function Checkpoint.distanceTo3d(pos, node)
    return dist3d(pos, node)
end

--- Resolve a circuit's checkpoint node IDs to position tables.
--- @param circuit    table  circuit definition from data/circuits.lua
--- @param allNodes   table  array of node objects (MTE.Nodes)
--- @return table[] resolved  array of { id, name, x, y, z, region } or nil if a node is missing
--- @return string|nil error  error message if any node ID couldn't be resolved
function Checkpoint.resolveCircuit(circuit, allNodes)
    if not circuit or not circuit.checkpoints then
        return nil, "No circuit or checkpoints provided"
    end

    -- Build a lookup by node ID
    local byId = {}
    for _, node in ipairs(allNodes or {}) do
        if node.id then
            byId[node.id] = node
        end
    end

    local resolved = {}
    for _, cpId in ipairs(circuit.checkpoints) do
        local node = byId[cpId]
        if not node then
            return nil, i18n.format("Checkpoint node '%s' not found in node pool", cpId)
        end
        table.insert(resolved, {
            id     = node.id,
            name   = node.name,
            x      = node.x,
            y      = node.y,
            z      = node.z,
            region = node.region,
        })
    end
    return resolved, nil
end

--- Compute a driver's total progress value along a circuit.
--- Higher value = further along the circuit. Supports multiple laps.
---
--- @param checkpointIndex number  1-based index of the NEXT checkpoint to reach
--- @param totalCheckpoints number total checkpoints in the circuit
--- @param pos             table   driver's current { x, y, z }
--- @param nextCheckpoint  table   the next checkpoint's { x, y, z }
--- @param lap             number  current lap (1-based)
--- @return number progress  monotonically increasing progress score
function Checkpoint.computeProgress(checkpointIndex, totalCheckpoints, pos, nextCheckpoint, lap)
    lap = lap or 1
    local completedCPs = ((lap - 1) * totalCheckpoints) + (checkpointIndex - 1)
    -- Invert distance so closer = higher progress
    local distToNext = dist2d(pos, nextCheckpoint)
    -- Clamp distance contribution to 0-1000 range
    local distScore = math.max(0, 1000 - distToNext)
    return completedCPs * 1000 + distScore
end

--- Build waypoint position array from resolved checkpoints.
--- For AI driving: returns { x, y, z } positions starting from
--- a given checkpoint index (wrapping for loops).
---
--- @param resolvedCheckpoints table[] array of resolved checkpoint nodes
--- @param startIndex          number  1-based start checkpoint
--- @param isLoop              boolean whether the circuit loops
--- @return table[] waypoints  array of { x, y, z } positions
function Checkpoint.buildWaypoints(resolvedCheckpoints, startIndex, isLoop)
    local waypoints = {}
    local n = #resolvedCheckpoints
    if n == 0 then return waypoints end

    startIndex = startIndex or 1
    if isLoop then
        -- Full loop starting from startIndex
        for i = 0, n - 1 do
            local idx = ((startIndex - 1 + i) % n) + 1
            local cp = resolvedCheckpoints[idx]
            table.insert(waypoints, { x = cp.x, y = cp.y, z = cp.z })
        end
    else
        -- Linear: startIndex to end
        for i = startIndex, n do
            local cp = resolvedCheckpoints[i]
            table.insert(waypoints, { x = cp.x, y = cp.y, z = cp.z })
        end
    end

    return waypoints
end

return Checkpoint



