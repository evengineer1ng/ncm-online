-- ============================================================
-- MT_Ecosystem: data/nodes.lua
-- Node pool is now populated entirely by user-defined nodes.
-- Use MTE_AddNode("Name", "Region") from the CET console to add nodes.
-- Nodes persist in save/user_nodes.json and are injected into
-- MTE.Nodes at startup by modules/user_nodes.lua.
-- ============================================================

local Nodes = {}

-- Empty at load time. user_nodes.lua injects into MTE.Nodes after init.
local _pool = {}

function Nodes.findById(nodeId)
    if not nodeId or nodeId == "" then return nil end
    for _, n in ipairs(MTE and MTE.Nodes or _pool) do
        if n.id == nodeId then return n end
    end
    return nil
end

--- Return the node pool (MTE.Nodes at runtime, _pool at load time).
function Nodes.all()
    return MTE and MTE.Nodes or _pool
end

--- Return nodes filtered by region name (case-insensitive).
function Nodes.byRegion(region)
    local r = region:lower()
    local out = {}
    for _, n in ipairs(Nodes.all()) do
        if (n.region or ""):lower() == r then
            table.insert(out, n)
        end
    end
    return out
end

--- Return node count.
function Nodes.count()
    return #(MTE and MTE.Nodes or _pool)
end

return Nodes
