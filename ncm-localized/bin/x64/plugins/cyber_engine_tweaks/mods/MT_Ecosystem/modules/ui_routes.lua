local UIRoutes = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end

local _createNameBuf = { "" }
local _renameNameBuf = { "" }
local _selectedRootId = nil
local _createPathNodeIds = {}
local _createAppendNodeId = nil
local _showInvalidRoots = true
local _confirmRestoreDefaults = false
local _statusMessage = nil
local _statusColor = { 0.4, 1.0, 0.4, 1.0 }
local _profileSectionTab = "gridSolver"

local function setStatus(message, color)
    _statusMessage = message
    _statusColor = color or { 0.4, 1.0, 0.4, 1.0 }
end

local function profileSectionLabel(sectionId)
    if sectionId == "raceSettings" then
        return "Race Settings"
    end
    return "Grid Solver"
end

local function drawProfileFieldEditor(root, field, resolvedValue, rootsMod, settings)
    local profile = type(root.profileSettings) == "table" and root.profileSettings or nil
    local hasOverride = profile ~= nil and profile[field.key] ~= nil
    local toggled, changed = ImGui.Checkbox("Override##root_profile_" .. field.key, hasOverride)
    if changed then
        local updated, err
        if toggled then
            updated, err = rootsMod.setProfileSetting and rootsMod.setProfileSetting(root.rootId, field.key, resolvedValue)
            if updated then
                setStatus("Enabled root override for " .. field.label .. ".")
            else
                setStatus(err or "Could not enable root override.", { 1.0, 0.4, 0.4, 1.0 })
            end
        else
            updated, err = rootsMod.clearProfileSetting and rootsMod.clearProfileSetting(root.rootId, field.key)
            if updated then
                setStatus("Removed root override for " .. field.label .. ".")
            else
                setStatus(err or "Could not remove root override.", { 1.0, 0.4, 0.4, 1.0 })
            end
        end
        return updated
    end

    ImGui.SameLine()
    if hasOverride then
        ImGui.TextColored(0.45, 0.95, 0.45, 1.0, field.label)
    else
        ImGui.Text(field.label)
    end

    local currentValue = hasOverride and profile[field.key] or resolvedValue
    local changedValue = false
    local newValue = currentValue
    if field.control == "int" then
        newValue, changedValue = ImGui.SliderInt("##root_value_" .. field.key, tonumber(currentValue) or field.default, field.min, field.max)
    else
        newValue, changedValue = ImGui.SliderFloat("##root_value_" .. field.key, tonumber(currentValue) or field.default, field.min, field.max)
    end

    if changedValue then
        local updated, err = rootsMod.setProfileSetting and rootsMod.setProfileSetting(root.rootId, field.key, newValue)
        if updated then
            setStatus("Updated root override for " .. field.label .. ".")
            return updated
        end
        setStatus(err or "Could not update root override.", { 1.0, 0.4, 0.4, 1.0 })
    end

    ImGui.TextDisabled(string.format("Global %.2f  |  Resolved %.2f", tonumber(settings.getTuningValue and settings.getTuningValue(field.key) or field.default) or 0.0, tonumber(resolvedValue) or 0.0))
    ImGui.TextDisabled(field.description or "")
    return nil
end

local function drawRootProfileEditor(selectedRoot, rootsMod)
    local settings = MTE and MTE.Settings or nil
    if not settings then
        ImGui.TextDisabled("Settings module not loaded.")
        return selectedRoot
    end

    local profileCount = settings.countProfileSettings and settings.countProfileSettings(selectedRoot.profileSettings) or 0
    if profileCount > 0 then
        ImGui.TextDisabled(string.format("Custom root tuning saved: %d setting(s)", tonumber(profileCount or 0)))
    else
        ImGui.TextDisabled("This root currently inherits the global race and grid tuning.")
    end

    if ImGui.Button("Stamp Current Globals", s(170), s(24)) then
        local updated, err = rootsMod.captureCurrentTuning and rootsMod.captureCurrentTuning(selectedRoot.rootId)
        if updated then
            selectedRoot = updated
            setStatus("Stamped the current global tuning into this root.", { 0.4, 1.0, 0.4, 1.0 })
        else
            setStatus(err or "Could not capture tuning for this root.", { 1.0, 0.4, 0.4, 1.0 })
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Clear Root Profile", s(160), s(24)) then
        local updated, err = rootsMod.clearProfileSettings and rootsMod.clearProfileSettings(selectedRoot.rootId)
        if updated then
            selectedRoot = updated
            setStatus("Cleared the root-specific tuning profile.", { 0.4, 1.0, 0.4, 1.0 })
        else
            setStatus(err or "Could not clear the root profile.", { 1.0, 0.4, 0.4, 1.0 })
        end
    end

    ImGui.TextDisabled("Stamped root settings override the global race/grid tuning whenever this root is active.")
    ImGui.Spacing()
    if ImGui.SmallButton("Grid Solver##root_profile_tab") then _profileSectionTab = "gridSolver" end
    ImGui.SameLine()
    if ImGui.SmallButton("Race Settings##root_profile_tab") then _profileSectionTab = "raceSettings" end
    ImGui.SameLine()
    ImGui.TextDisabled("Editing: " .. profileSectionLabel(_profileSectionTab))
    ImGui.Separator()

    local resolvedProfile = settings.resolveTuningProfile and settings.resolveTuningProfile(selectedRoot) or {}
    local fields = settings.getTuningFields and settings.getTuningFields(_profileSectionTab) or {}
    if ImGui.BeginChild("##rootProfileFields", 0, 310, true) then
        for _, field in ipairs(fields) do
            local updated = drawProfileFieldEditor(selectedRoot, field, resolvedProfile[field.key], rootsMod, settings)
            if updated then
                selectedRoot = updated
                resolvedProfile = settings.resolveTuningProfile and settings.resolveTuningProfile(selectedRoot) or resolvedProfile
            end
            ImGui.Spacing()
        end
    end
    ImGui.EndChild()
    return selectedRoot
end

local function nodeLabel(node)
    if not node then return "(none)" end
    return string.format("%s [%s]", node.name or node.id or "Node", node.region or "Unknown")
end

local function rootPrimaryLabel(root)
    if not root then return "[Invalid Root]" end
    return root.primaryLabel or root.displayName or root.autoLabel or "[Invalid Root]"
end

local function rootSecondaryLabel(root)
    if not root then return nil end
    return root.secondaryLabel or root.subtitleOverride or nil
end

local function findNodeById(nodeId, nodes)
    for _, node in ipairs(nodes or {}) do
        if node.id == nodeId then
            return node
        end
    end
    return nil
end

local function findRootById(rootId, roots)
    for _, root in ipairs(roots or {}) do
        if root.rootId == rootId then
            return root
        end
    end
    return nil
end

local function pathNodeLabel(nodeId, nodes)
    return nodeLabel(findNodeById(nodeId, nodes) or { id = nodeId, name = nodeId, region = "Unknown" })
end

local function formatNodePath(nodeIds, nodes, maxNodes)
    local ids = nodeIds or {}
    local limit = math.max(2, tonumber(maxNodes) or #ids)
    local labels = {}
    for index, nodeId in ipairs(ids) do
        if index > limit then
            labels[#labels + 1] = string.format("... (+%d more)", #ids - limit + 1)
            break
        end
        local node = findNodeById(nodeId, nodes)
        labels[#labels + 1] = node and (node.name or node.id or "Node") or tostring(nodeId)
    end
    return table.concat(labels, " -> ")
end

local function ensureCreateAppendDefault(nodes)
    if type(nodes) ~= "table" or #nodes <= 0 then
        _createAppendNodeId = nil
        return
    end
    if not findNodeById(_createAppendNodeId, nodes) then
        _createAppendNodeId = nodes[1].id
    end
end

local function ensureCreateDefaults(nodes)
    if #nodes == 0 then
        _createPathNodeIds = {}
        _createAppendNodeId = nil
        return
    end

    local filtered = {}
    for _, nodeId in ipairs(_createPathNodeIds or {}) do
        if findNodeById(nodeId, nodes) then
            filtered[#filtered + 1] = nodeId
        end
    end
    _createPathNodeIds = filtered

    if #_createPathNodeIds <= 0 then
        _createPathNodeIds[1] = nodes[1].id
    end
    if #_createPathNodeIds <= 1 then
        local fallback = nodes[2] or nodes[1]
        _createPathNodeIds[2] = fallback and fallback.id or nodes[1].id
    end

    ensureCreateAppendDefault(nodes)
end

local function syncRenameBuffer(root)
    if not root then
        _selectedRootId = nil
        _renameNameBuf[1] = ""
        return
    end
    if _selectedRootId ~= root.rootId then
        _selectedRootId = root.rootId
        _renameNameBuf[1] = root.displayName or ""
    end
end

function UIRoutes.init()
end

function UIRoutes.draw()
    local rootsMod = MTE and MTE.Roots
    if not rootsMod then
        ImGui.TextDisabled("Roots module not loaded.")
        return
    end

    local nodes = (MTE and MTE.Nodes) or {}
    local roots = rootsMod.all and rootsMod.all({ includeInvalid = _showInvalidRoots }) or {}
    local stats = rootsMod.getStats and rootsMod.getStats() or { total = 0, valid = 0, invalid = 0, defaults = 0, user = 0 }
    local pack = rootsMod.exportPackDocument and rootsMod.exportPackDocument() or nil
    local userNodeCount = MTE and MTE.UserNodes and MTE.UserNodes.getAll and #(MTE.UserNodes.getAll() or {}) or 0
    local hasManualPair = MTE and MTE.ManualNodes and MTE.ManualNodes.hasPair and MTE.ManualNodes.hasPair() or false
    local selectedRoot = rootsMod.resolveRoot and rootsMod.resolveRoot(_selectedRootId) or nil

    ImGui.Text("Roots & Named Routes")
    ImGui.Separator()
    ImGui.Text(string.format("Active Pack: %s  (v%s)",
        tostring(pack and pack.packName or "No active pack"),
        tostring(pack and pack.version or "?")))
    if pack and pack.description then
        ImGui.TextDisabled(tostring(pack.description))
    end
    ImGui.TextDisabled(string.format(
        "Total: %d  |  Valid: %d  |  Invalid: %d  |  Default: %d  |  User: %d",
        tonumber(stats.total or 0),
        tonumber(stats.valid or 0),
        tonumber(stats.invalid or 0),
        tonumber(stats.defaults or 0),
        tonumber(stats.user or 0)))
    ImGui.TextDisabled(string.format("User Nodes: %d  |  Manual Pair: %s",
        tonumber(userNodeCount or 0),
        hasManualPair and "saved" or "missing"))
    if tonumber(stats.defaults or 0) == 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.55, 0.15, 1.0)
        ImGui.TextWrapped("The bundled roots pack is still empty. Restore/reset will apply the pack metadata, but it will not add curated routes until that pack is authored. Right now this tab is primarily operating on your user-created roots.")
        ImGui.PopStyleColor()
    end

    ImGui.Spacing()
    ImGui.Text("Create Root")
    ImGui.Separator()

    if #nodes < 2 then
        ImGui.TextDisabled("Add at least two nodes in the Nodes tab before creating a root.")
    else
        ensureCreateDefaults(nodes)
        ImGui.TextDisabled("Build an ordered node path. Two nodes create a simple A -> B root; three or more nodes create a sequence root.")
        ImGui.TextDisabled("Repeat the first node at the end if you want a loop root.")

        for index, nodeId in ipairs(_createPathNodeIds) do
            local moveUpId = "Up##root_create_up_" .. tostring(index)
            local moveDownId = "Down##root_create_down_" .. tostring(index)
            local removeId = "Remove##root_create_remove_" .. tostring(index)

            if index > 1 then
                if ImGui.SmallButton(moveUpId) then
                    _createPathNodeIds[index], _createPathNodeIds[index - 1] = _createPathNodeIds[index - 1], _createPathNodeIds[index]
                end
            else
                ImGui.Dummy(36, 1)
            end
            ImGui.SameLine()

            if index < #_createPathNodeIds then
                if ImGui.SmallButton(moveDownId) then
                    _createPathNodeIds[index], _createPathNodeIds[index + 1] = _createPathNodeIds[index + 1], _createPathNodeIds[index]
                end
            else
                ImGui.Dummy(48, 1)
            end
            ImGui.SameLine()

            ImGui.Text(string.format("%d.", index))
            ImGui.SameLine()
            ImGui.TextWrapped(pathNodeLabel(nodeId, nodes))
            ImGui.SameLine()
            if ImGui.SmallButton(removeId) and #_createPathNodeIds > 2 then
                table.remove(_createPathNodeIds, index)
                break
            end
        end

        ensureCreateAppendDefault(nodes)
        if ImGui.BeginCombo("Append Node##root_append_node", pathNodeLabel(_createAppendNodeId, nodes)) then
            for _, node in ipairs(nodes) do
                local isSelected = node.id == _createAppendNodeId
                if ImGui.Selectable(nodeLabel(node), isSelected) then
                    _createAppendNodeId = node.id
                end
            end
            ImGui.EndCombo()
        end
        if ImGui.Button("Add Node", s(110), s(24)) and _createAppendNodeId then
            _createPathNodeIds[#_createPathNodeIds + 1] = _createAppendNodeId
        end
        ImGui.SameLine()
        if ImGui.Button("Reset Path", s(110), s(24)) then
            _createPathNodeIds = { nodes[1].id, (nodes[2] or nodes[1]).id }
        end
        ImGui.SameLine()
        if hasManualPair and ImGui.Button("Use Manual Pair", s(130), s(24)) then
            local startNode, finishNode = MTE.ManualNodes.getPair()
            _createPathNodeIds = {
                startNode and startNode.id or nodes[1].id,
                finishNode and finishNode.id or (nodes[2] or nodes[1]).id,
            }
        end

        ImGui.TextDisabled(string.format("Path: %s", formatNodePath(_createPathNodeIds, nodes, 8)))

        local createName, createChanged = ImGui.InputText("Custom Name##root_create_name", _createNameBuf[1], 64)
        if createChanged then _createNameBuf[1] = createName end

        if ImGui.Button("Create Root", s(130), s(24)) then
            local created, err = rootsMod.create and rootsMod.create(_createPathNodeIds, {
                displayName = _createNameBuf[1],
            })
            if created then
                syncRenameBuffer(created)
                _createNameBuf[1] = ""
                setStatus("Created root: " .. rootPrimaryLabel(created), { 0.4, 1.0, 0.4, 1.0 })
            else
                setStatus(err or "Could not create root.", { 1.0, 0.4, 0.4, 1.0 })
            end
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Text("Manage Roots")
    ImGui.Separator()

    local toggledShowInvalid, changedShowInvalid = ImGui.Checkbox("Show invalid roots", _showInvalidRoots)
    if changedShowInvalid then _showInvalidRoots = toggledShowInvalid end
    ImGui.SameLine()
    if not _confirmRestoreDefaults then
        if ImGui.Button("Reset To Pack", s(150), s(24)) then
            _confirmRestoreDefaults = true
        end
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.45, 0.35, 1.0)
        if tonumber(stats.defaults or 0) == 0 then
            ImGui.Text("Reset current roots to the active pack state? This pack currently has no curated roots.")
        else
            ImGui.Text("Replace current roots with the active bundled pack?")
        end
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.SmallButton("Confirm##roots_restore") then
            rootsMod.restoreDefaults()
            _confirmRestoreDefaults = false
            _selectedRootId = nil
            _renameNameBuf[1] = ""
            setStatus("Restored bundled roots.", { 0.4, 1.0, 0.4, 1.0 })
            roots = rootsMod.all and rootsMod.all({ includeInvalid = _showInvalidRoots }) or {}
        end
        ImGui.SameLine()
        if ImGui.SmallButton("Cancel##roots_restore") then
            _confirmRestoreDefaults = false
        end
    end

    if _statusMessage then
        ImGui.PushStyleColor(ImGuiCol.Text, _statusColor[1], _statusColor[2], _statusColor[3], _statusColor[4])
        ImGui.TextWrapped(_statusMessage)
        ImGui.PopStyleColor()
    end

    if selectedRoot and selectedRoot.rootId then
        syncRenameBuffer(selectedRoot)
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Text("Selected Root")
        ImGui.Separator()
        ImGui.Text(rootPrimaryLabel(selectedRoot))
        local subtitle = rootSecondaryLabel(selectedRoot)
        if subtitle then
            ImGui.TextDisabled(subtitle)
        end
        ImGui.TextDisabled(string.format(
            "ID: %s  |  Nodes: %d  |  Dist: %.0f m  |  Source: %s",
            tostring(selectedRoot.rootId or "?"),
            tonumber(selectedRoot.nodeCount or #(selectedRoot.nodeIds or {})),
            tonumber(selectedRoot.distanceM or 0),
            selectedRoot.isDefaultPackRoot and "default" or "user"))
        ImGui.TextWrapped("Path: " .. formatNodePath(selectedRoot.nodeIds or {}, nodes, 12))
        if selectedRoot.isLoop == true then
            ImGui.TextDisabled("Loop root: the first and last path nodes are the same.")
        end
        if selectedRoot.isValid == false then
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.4, 0.3, 1.0)
            ImGui.Text("Invalid root")
            ImGui.PopStyleColor()
            local errors = selectedRoot.validationErrors or {}
            for _, err in ipairs(errors) do
                ImGui.TextDisabled("  " .. tostring(err))
            end
        end

        local renameValue, renameChanged = ImGui.InputText("Display Name##root_rename", _renameNameBuf[1], 64)
        if renameChanged then _renameNameBuf[1] = renameValue end
        if ImGui.Button("Save Name", s(120), s(24)) then
            local renamed, err = rootsMod.rename and rootsMod.rename(selectedRoot.rootId, _renameNameBuf[1])
            if renamed then
                syncRenameBuffer(renamed)
                setStatus("Updated root name.", { 0.4, 1.0, 0.4, 1.0 })
                roots = rootsMod.all and rootsMod.all({ includeInvalid = _showInvalidRoots }) or roots
            else
                setStatus(err or "Could not update root name.", { 1.0, 0.4, 0.4, 1.0 })
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Clear Custom Name", s(150), s(24)) then
            local cleared, err = rootsMod.clearCustomName and rootsMod.clearCustomName(selectedRoot.rootId)
            if cleared then
                syncRenameBuffer(cleared)
                setStatus("Cleared custom root name.", { 0.4, 1.0, 0.4, 1.0 })
                roots = rootsMod.all and rootsMod.all({ includeInvalid = _showInvalidRoots }) or roots
            else
                setStatus(err or "Could not clear root name.", { 1.0, 0.4, 0.4, 1.0 })
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Delete Root", s(120), s(24)) then
            local ok, err = rootsMod.delete and rootsMod.delete(selectedRoot.rootId)
            if ok then
                _selectedRootId = nil
                _renameNameBuf[1] = ""
                setStatus("Deleted root.", { 0.4, 1.0, 0.4, 1.0 })
                roots = rootsMod.all and rootsMod.all({ includeInvalid = _showInvalidRoots }) or {}
            else
                setStatus(err or "Could not delete root.", { 1.0, 0.4, 0.4, 1.0 })
            end
        end

        ImGui.Spacing()
        ImGui.Text("Root Profile")
        ImGui.Separator()
        selectedRoot = drawRootProfileEditor(selectedRoot, rootsMod)
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Text("Root Catalog")
    ImGui.Separator()

    if #roots == 0 then
        ImGui.TextDisabled("No roots saved yet. Create one above or restore bundled defaults.")
        return
    end

    for _, root in ipairs(roots) do
        local isSelected = root.rootId == _selectedRootId
        if isSelected then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.40, 1.0, 0.40, 1.0)
        elseif root.isValid == false then
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.45, 0.35, 1.0)
        end

        if ImGui.SmallButton((isSelected and "Selected##" or "View##") .. tostring(root.rootId)) then
            syncRenameBuffer(root)
            selectedRoot = root
        end
        ImGui.SameLine()
        ImGui.Text(rootPrimaryLabel(root))

        if isSelected or root.isValid == false then
            ImGui.PopStyleColor()
        end

        local meta = string.format(
            "%s  |  %d node(s)  |  %.0f m  |  %s",
            tostring(root.districtLabel or "?"),
            tonumber(root.nodeCount or #(root.nodeIds or {})),
            tonumber(root.distanceM or 0),
            root.isDefaultPackRoot and "default" or "user")
        if root.isValid == false then
            meta = meta .. "  |  INVALID"
        end
        ImGui.TextDisabled("    " .. meta)
        ImGui.TextDisabled("    Path: " .. formatNodePath(root.nodeIds or {}, nodes, 6))
        local subtitle = rootSecondaryLabel(root)
        if subtitle then
            ImGui.TextDisabled("    " .. subtitle)
        end
        if root.isValid == false then
            local errors = root.validationErrors or {}
            if #errors > 0 then
                ImGui.TextDisabled("    " .. tostring(errors[1]))
            end
        end
        ImGui.Spacing()
    end
end

return UIRoutes
