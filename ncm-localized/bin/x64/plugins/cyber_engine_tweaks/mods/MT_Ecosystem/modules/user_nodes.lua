-- ============================================================
-- MT_Ecosystem: modules/user_nodes.lua
-- Let the player permanently record race nodes from the CET console.
--
-- USAGE (CET console):
--   MTE_AddNode("My Spot", "Watson")        -- save current pos as a node
--   MTE_ListNodes()                         -- print all saved nodes
--   MTE_RemoveNode("my_spot")               -- remove by name or id
--   MTE_ClearUserNodes()                    -- wipe all user nodes
--
-- Nodes persist in save/user_nodes.json and are injected into
-- MTE.Nodes immediately so they're available for racing without restart.
-- ============================================================

local UserNodes = {}

local Persist = require("modules/persistence")
local SAVE_FILE = "user_nodes.json"

local _nodes = {}   -- persisted user nodes

-- ── Helpers ──────────────────────────────────────────────────

local function refreshRoots()
    if MTE and MTE.Roots and MTE.Roots._initialized and MTE.Roots.refresh then
        MTE.Roots.refresh()
    end
end

local function slugify(s)
    return tostring(s or "node"):lower():gsub("%s+", "_"):gsub("[^%w_]", "")
end

local function getPlayerPos()
    local pos = nil
    pcall(function()
        local p = Game.GetPlayer()
        if p then pos = p:GetWorldPosition() end
    end)
    return pos
end

local function getHeading()
    local heading = 0
    pcall(function()
        local p = Game.GetPlayer()
        if not p then return end
        local veh = Game.GetMountedVehicle(p)
        local target = veh or p
        if target and target.GetWorldYaw then
            heading = target:GetWorldYaw() or 0
        end
    end)
    return heading
end

local function injectIntoPool(node)
    if not (MTE and MTE.Nodes) then return end
    -- Replace if same id already in live pool
    for i = #MTE.Nodes, 1, -1 do
        if MTE.Nodes[i].id == node.id then
            table.remove(MTE.Nodes, i)
        end
    end
    table.insert(MTE.Nodes, node)
end

local function removeFromPool(id)
    if not (MTE and MTE.Nodes) then return end
    for i = #MTE.Nodes, 1, -1 do
        if MTE.Nodes[i].id == id then
            table.remove(MTE.Nodes, i)
        end
    end
end

-- ── Public API ────────────────────────────────────────────────

function UserNodes.init()
    local saved = Persist.load(SAVE_FILE)
    if type(saved) == "table" then
        _nodes = saved
    end
    -- Assign ids to any legacy entries that lack one
    for _, n in ipairs(_nodes) do
        if not n.id then
            n.id = slugify(n.name) .. "_" .. math.floor(n.x or 0) .. "_" .. math.floor(n.y or 0)
        end
    end
    -- Inject into live pool (MTE.Nodes populated by init.lua before this runs)
    for _, node in ipairs(_nodes) do
        injectIntoPool(node)
    end
    print(string.format("[NCM/UserNodes] Loaded %d user-defined node(s).", #_nodes))
end

--- Capture the player's current position and save it as a named race node.
--- @param name   string  human-readable name (required)
--- @param region string  region label, e.g. "Watson" (optional, defaults to "Night City")
function UserNodes.add(name, region)
    if not name or name == "" then
        print("[NCM/UserNodes] Usage: MTE_AddNode('Node Name', 'Region')")
        return false
    end
    local pos = getPlayerPos()
    if not pos then
        print("[NCM/UserNodes] Cannot capture position — not in a game session.")
        return false
    end
    local x = math.floor((pos.x or 0) + 0.5)
    local y = math.floor((pos.y or 0) + 0.5)
    local z = math.floor((pos.z or 0) + 0.5)
    local id = slugify(name) .. "_" .. x .. "_" .. y

    local node = {
        id          = id,
        x           = x,
        y           = y,
        z           = z,
        heading     = getHeading(),
        name        = name,
        region      = region or "Night City",
        urban       = true,
        waypointable = true,
        road        = true,
        raceLegal   = true,
    }

    -- Remove any existing node with same id
    for i = #_nodes, 1, -1 do
        if _nodes[i].id == id then
            table.remove(_nodes, i)
        end
    end
    table.insert(_nodes, node)
    Persist.save(SAVE_FILE, _nodes)
    injectIntoPool(node)
    refreshRoots()

    print(string.format("[NCM/UserNodes] Saved '%s' (%s)  pos=(%.0f, %.0f, %.0f)  heading=%.0f  id=%s",
        node.name, node.region, node.x, node.y, node.z, node.heading, node.id))
    return true
end

--- Remove a node by name or id (case-insensitive, spaces become underscores).
--- @param idOrName string
function UserNodes.remove(idOrName)
    if not idOrName or idOrName == "" then
        print("[NCM/UserNodes] Usage: MTE_RemoveNode('name or id')")
        return false
    end
    local key = slugify(idOrName)
    local removed = 0
    for i = #_nodes, 1, -1 do
        local n = _nodes[i]
        if n.id == idOrName or slugify(n.name) == key then
            print(string.format("[NCM/UserNodes] Removed '%s'  id=%s", n.name, n.id))
            removeFromPool(n.id)
            table.remove(_nodes, i)
            removed = removed + 1
        end
    end
    if removed > 0 then
        Persist.save(SAVE_FILE, _nodes)
        refreshRoots()
    else
        print("[NCM/UserNodes] No node found matching: " .. tostring(idOrName))
    end
    return removed > 0
end

--- Print all user-defined nodes to the CET console.
function UserNodes.list()
    if #_nodes == 0 then
        print("[NCM/UserNodes] No user nodes saved yet.")
        print("  Use: MTE_AddNode('Name', 'Region')")
        return
    end
    print(string.format("[NCM/UserNodes] %d node(s):", #_nodes))
    for i, n in ipairs(_nodes) do
        print(string.format("  [%2d] %-28s  region=%-15s  pos=(%.0f, %.0f, %.0f)  hdg=%.0f  id=%s",
            i, n.name, n.region, n.x, n.y, n.z, n.heading or 0, n.id))
    end
end

--- Remove all user-defined nodes.
function UserNodes.clear()
    for _, n in ipairs(_nodes) do
        removeFromPool(n.id)
    end
    _nodes = {}
    Persist.save(SAVE_FILE, _nodes)
    refreshRoots()
    print("[NCM/UserNodes] All user nodes cleared.")
end

function UserNodes.getAll()
    return _nodes
end

return UserNodes
