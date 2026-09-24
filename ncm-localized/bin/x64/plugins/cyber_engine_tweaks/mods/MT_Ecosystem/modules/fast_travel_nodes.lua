-- ============================================================
-- MT_Ecosystem: modules/fast_travel_nodes.lua
-- Harvests real fast-travel terminal locations from loaded DataTerm
-- entities and persists them as race-node anchors.
-- ============================================================

local FastTravelNodes = {}

local Persist = require("modules/persistence")

local SAVE_FILE = "fast_travel_nodes.json"
local _nodes = {}
local _byId = {}
local _observerInstalled = false

local function slugify(value)
    local s = tostring(value or "node"):lower()
    s = s:gsub("%s+", "_"):gsub("[^%w_]", "")
    return s
end

local function displayNameFromPoint(point)
    local name = nil
    pcall(function()
        if point.GetPointDisplayDescription then
            name = point:GetPointDisplayDescription()
        end
    end)
    if not name or name == "" then
        pcall(function()
            if point.GetPointDisplayName then
                name = point:GetPointDisplayName()
            end
        end)
    end
    return name or "Fast Travel"
end

local function districtNameFromPoint(point)
    local district = nil
    pcall(function()
        if point.GetDistrictDisplayName then
            district = point:GetDistrictDisplayName()
        end
    end)
    return district or "Night City"
end

local function pointIdFromPoint(point, fallbackName)
    local id = nil
    pcall(function()
        if point.GetPointRecord then
            id = tostring(point:GetPointRecord())
        end
    end)
    return slugify(id or fallbackName)
end

local function appendNode(node)
    _byId[node.id] = node
    local replaced = false
    for i, existing in ipairs(_nodes) do
        if existing.id == node.id then
            _nodes[i] = node
            replaced = true
            break
        end
    end
    if not replaced then
        _nodes[#_nodes + 1] = node
        if MTE and MTE.Nodes then
            MTE.Nodes[#MTE.Nodes + 1] = node
        end
    end
end

local function saveNodes()
    Persist.save(SAVE_FILE, _nodes)
end

local function captureDataTerm(self)
    local point = nil
    local pos = nil

    pcall(function()
        point = self.m_linkedFastTravelPoint
    end)
    if not point then return end

    pcall(function()
        pos = self:GetWorldPosition()
    end)
    if not pos then return end

    local name = displayNameFromPoint(point)
    local district = districtNameFromPoint(point)
    local id = pointIdFromPoint(point, name)

    local node = {
        id = id,
        x = math.floor((pos.x or 0) + 0.5),
        y = math.floor((pos.y or 0) + 0.5),
        z = math.floor((pos.z or 0) + 0.5),
        name = name,
        region = district,
        urban = true,
        waypointable = true,
        road = true,
        raceLegal = true,
    }

    local existing = _byId[id]
    if existing
       and existing.x == node.x
       and existing.y == node.y
       and existing.z == node.z
       and existing.name == node.name
       and existing.region == node.region then
        return
    end

    appendNode(node)
    saveNodes()
    print(string.format("[NCM/FastTravelNodes] Captured %s (%s) at %.0f, %.0f, %.0f",
        node.name, node.region, node.x, node.y, node.z))
end

function FastTravelNodes.init()
    local saved = Persist.load(SAVE_FILE)
    if type(saved) == "table" then
        _nodes = saved
        for _, node in ipairs(_nodes) do
            if node.id then
                _byId[node.id] = node
            end
        end
    end

    if not _observerInstalled then
        _observerInstalled = true
        ObserveAfter("DataTerm", "OnGameAttached", function(self)
            captureDataTerm(self)
        end)
        ObserveAfter("DataTerm", "ResolveGameplayState", function(self)
            captureDataTerm(self)
        end)
    end

    print(string.format("[NCM/FastTravelNodes] Loaded %d harvested fast-travel anchors.", #_nodes))
end

function FastTravelNodes.getAll()
    return _nodes
end

return FastTravelNodes
