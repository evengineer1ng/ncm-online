-- ============================================================
-- MT_Ecosystem: modules/manual_nodes.lua
-- Lets the player save a manual start/finish node pair from their
-- current position and reuse that pair in race setup.
-- ============================================================

local ManualNodes = {}

local Persist = require("modules/persistence")

local SAVE_FILE = "manual_nodes.json"

ManualNodes._data = {
    start = nil,
    finish = nil,
}

local function getPlayerPos()
    local pos = nil
    pcall(function()
        local p = Game.GetPlayer()
        if p then pos = p:GetWorldPosition() end
    end)
    return pos
end

local function getVehicleHeading()
    local heading = 0
    pcall(function()
        local veh = Game.GetMountedVehicle(Game.GetPlayer())
        local target = veh or Game.GetPlayer()
        if target and target.GetWorldYaw then
            heading = target:GetWorldYaw()
        end
    end)
    return heading or 0
end

local function buildNode(kind, label, region)
    local pos = getPlayerPos()
    if not pos then return nil end
    local suffix = kind == "start" and "start" or "finish"
    return {
        id = "manual_" .. suffix,
        x = math.floor((pos.x or 0) + 0.5),
        y = math.floor((pos.y or 0) + 0.5),
        z = math.floor((pos.z or 0) + 0.5),
        heading = getVehicleHeading(),
        name = label and label ~= "" and label or ("Manual " .. suffix),
        region = region and region ~= "" and region or "Manual",
        urban = true,
        waypointable = true,
        road = true,
        raceLegal = true,
    }
end

local function save()
    Persist.save(SAVE_FILE, ManualNodes._data)
end

function ManualNodes.init()
    local data = Persist.load(SAVE_FILE)
    if type(data) == "table" then
        ManualNodes._data.start = data.start
        ManualNodes._data.finish = data.finish
    end
end

function ManualNodes.captureStart(label, region)
    local node = buildNode("start", label, region)
    if not node then return false end
    ManualNodes._data.start = node
    save()
    print(string.format("[NCM/ManualNodes] Saved start: %s (%.0f, %.0f, %.0f)",
        node.name, node.x, node.y, node.z))
    return true
end

function ManualNodes.captureFinish(label, region)
    local node = buildNode("finish", label, region)
    if not node then return false end
    ManualNodes._data.finish = node
    save()
    print(string.format("[NCM/ManualNodes] Saved finish: %s (%.0f, %.0f, %.0f)",
        node.name, node.x, node.y, node.z))
    return true
end

function ManualNodes.clear()
    ManualNodes._data.start = nil
    ManualNodes._data.finish = nil
    save()
end

function ManualNodes.getPair()
    return ManualNodes._data.start, ManualNodes._data.finish
end

function ManualNodes.hasPair()
    return ManualNodes._data.start ~= nil and ManualNodes._data.finish ~= nil
end

return ManualNodes
