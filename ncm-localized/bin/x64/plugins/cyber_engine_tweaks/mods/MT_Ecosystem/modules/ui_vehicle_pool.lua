local UIVehiclePool = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end

local VehiclePool = require("data/vehicle_pool")

local TIER_ORDER = { "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }
local CLASS_ORDER = { "Muscle", "Sport", "Tech", "Nomad", "Bike" }

local _manualInputBuf = {}
local _manualPrestige = {}
for _, tier in ipairs(TIER_ORDER) do
    _manualInputBuf[tier] = { "" }
    _manualPrestige[tier] = { 1 }
end

local _statusMessage = nil
local _statusIsError = false

local function setStatus(message, isError)
    _statusMessage = message
    _statusIsError = isError == true
end

local function getOverrides()
    local settings = MTE and MTE.Settings
    local overrides = settings and settings.get and settings.get("vehiclePoolOverrides")
    if type(overrides) ~= "table" then
        return {}
    end
    return overrides
end

local function saveOverrides(overrides)
    local settings = MTE and MTE.Settings
    if not settings or not settings.current then return end
    settings.current.vehiclePoolOverrides = overrides
    if settings.save then settings.save() end
end

local function stampCurrentCar(tier)
    local player = Game.GetPlayer()
    if not player then
        setStatus("Player not available.", true)
        return
    end
    local vehicle = Game.GetMountedVehicle(player)
    if not vehicle then
        setStatus("You must be in a vehicle to stamp it.", true)
        return
    end
    local record = vehicle:GetRecord()
    if not record then
        setStatus("Could not read vehicle record.", true)
        return
    end
    local vid = record:GetID()
    local tdbKey = TDBID.ToStringDEBUG(vid)
    if type(tdbKey) ~= "string" or tdbKey == "" then
        setStatus("Could not resolve TweakDB key.", true)
        return
    end

    local prestige = VehiclePool.PRESTIGE_FLOOR[tier] or 1
    local overrides = getOverrides()
    if type(overrides[tier]) ~= "table" then
        overrides[tier] = {}
    end

    for _, entry in ipairs(overrides[tier]) do
        if entry.id == tdbKey then
            setStatus(tdbKey .. " is already in " .. tier .. " pool.", false)
            return
        end
    end

    overrides[tier][#overrides[tier] + 1] = { id = tdbKey, prestige = prestige }
    saveOverrides(overrides)
    setStatus("Stamped " .. tdbKey .. " into " .. tier .. " (prestige " .. tostring(prestige) .. ").", false)
end

local function addManualEntry(tier)
    local raw = _manualInputBuf[tier] and _manualInputBuf[tier][1] or ""
    local tdbKey = raw:match("^%s*(.-)%s*$")
    if not tdbKey or tdbKey == "" then
        setStatus("Enter a TweakDB vehicle key.", true)
        return
    end
    local prestige = _manualPrestige[tier] and _manualPrestige[tier][1] or 1
    prestige = math.max(1, math.min(5, math.floor(tonumber(prestige) or 1)))

    local overrides = getOverrides()
    if type(overrides[tier]) ~= "table" then
        overrides[tier] = {}
    end

    for _, entry in ipairs(overrides[tier]) do
        if entry.id == tdbKey then
            setStatus(tdbKey .. " is already in " .. tier .. " pool.", false)
            return
        end
    end

    overrides[tier][#overrides[tier] + 1] = { id = tdbKey, prestige = prestige }
    saveOverrides(overrides)
    _manualInputBuf[tier][1] = ""
    setStatus("Added " .. tdbKey .. " to " .. tier .. " (prestige " .. tostring(prestige) .. ").", false)
end

local function removeOverride(tier, index)
    local overrides = getOverrides()
    if type(overrides[tier]) ~= "table" then return end
    table.remove(overrides[tier], index)
    if #overrides[tier] == 0 then
        overrides[tier] = nil
    end
    saveOverrides(overrides)
    setStatus("Removed override from " .. tier .. ".", false)
end

local function drawTierSection(tier)
    local floor = VehiclePool.PRESTIGE_FLOOR[tier] or 1
    local classWeights = VehiclePool.TIER_CLASS_WEIGHTS[tier] or {}
    local prestigeWeights = VehiclePool.TIER_PRESTIGE_WEIGHTS[tier] or {}
    local overrides = getOverrides()
    local tierOverrides = overrides[tier] or {}

    local headerLabel = string.format("%s  (prestige floor: %d)", tier, floor)
    if not ImGui.CollapsingHeader(headerLabel) then
        return
    end

    -- Class weights
    ImGui.Text("Class Weights:")
    ImGui.SameLine()
    local parts = {}
    for _, cls in ipairs(CLASS_ORDER) do
        local w = classWeights[cls] or 0
        if w > 0 then
            parts[#parts + 1] = string.format("%s %d%%", cls, w)
        end
    end
    ImGui.TextDisabled(table.concat(parts, "  |  "))

    -- Prestige weights
    ImGui.Text("Prestige Weights:")
    ImGui.SameLine()
    local pParts = {}
    for p = 1, 5 do
        local w = prestigeWeights[p] or 0
        pParts[#pParts + 1] = string.format("P%d: %d%%", p, w)
    end
    ImGui.TextDisabled(table.concat(pParts, "  |  "))

    ImGui.Separator()

    -- Default vehicles eligible for this tier
    ImGui.Text("Default Pool (at or above prestige floor):")
    for _, cls in ipairs(CLASS_ORDER) do
        local pool = VehiclePool.RECORDS[cls] or {}
        for _, entry in ipairs(pool) do
            if entry.prestige >= floor then
                ImGui.TextDisabled(string.format("  [%s] %s  (P%d)", cls, entry.id, entry.prestige))
            end
        end
    end

    -- User overrides
    ImGui.Spacing()
    ImGui.Text("User Overrides:")
    if #tierOverrides == 0 then
        ImGui.TextDisabled("  (none)")
    else
        for idx, entry in ipairs(tierOverrides) do
            ImGui.Text(string.format("  %s  (P%d)", tostring(entry.id), tonumber(entry.prestige) or 1))
            ImGui.SameLine()
            if ImGui.SmallButton("Remove##vp_remove_" .. tier .. "_" .. tostring(idx)) then
                removeOverride(tier, idx)
                break
            end
        end
    end

    -- Stamp current car
    ImGui.Spacing()
    if ImGui.Button("Stamp Current Car##vp_stamp_" .. tier, s(180), s(24)) then
        stampCurrentCar(tier)
    end
    ImGui.SameLine()
    ImGui.TextDisabled("Adds the vehicle you're sitting in to this tier's pool.")

    -- Manual input
    ImGui.Spacing()
    ImGui.Text("Manual Add:")
    ImGui.InputText("TweakDB Key##vp_manual_id_" .. tier, _manualInputBuf[tier], 256)
    local pVal, pChanged = ImGui.SliderInt("Prestige##vp_manual_p_" .. tier, _manualPrestige[tier][1], 1, 5)
    if pChanged then _manualPrestige[tier][1] = pVal end
    if ImGui.SmallButton("Add##vp_manual_add_" .. tier) then
        addManualEntry(tier)
    end
    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.6, 0.2, 1.0)
    ImGui.TextWrapped("WARNING: An invalid TweakDB key will crash the game when a driver tries to spawn this vehicle.")
    ImGui.PopStyleColor()

    ImGui.Spacing()
end

function UIVehiclePool.draw()
    ImGui.Text("Vehicle Pool Configuration")
    ImGui.TextDisabled("View and override the vehicles that AI drivers can spawn in per tier. Overrides are added alongside the defaults.")
    ImGui.Separator()

    if _statusMessage then
        if _statusIsError then
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.35, 0.35, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.35, 0.9, 0.45, 1.0)
        end
        ImGui.TextWrapped(_statusMessage)
        ImGui.PopStyleColor()
        ImGui.Separator()
    end

    for _, tier in ipairs(TIER_ORDER) do
        drawTierSection(tier)
    end
end

return UIVehiclePool

