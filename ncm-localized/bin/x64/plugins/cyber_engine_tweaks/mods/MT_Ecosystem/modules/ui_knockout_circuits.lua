local UIKnockoutCircuits = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end

local _selectedCircuitId = nil
local _editCircuitId = nil
local _nameBuf = { "" }
local _regionBuf = { "" }
local _pendingNodeId = nil
local _pendingDeleteId = nil
local _editorCheckpoints = {}
local _statusMessage = nil
local _statusIsError = false
local _isNewCircuitMode = false

local function clone(value)
    if MTE and MTE.Persist and MTE.Persist.clone then
        return MTE.Persist.clone(value)
    end
    if type(value) ~= "table" then
        return value
    end
    local copied = {}
    for index, entry in ipairs(value) do
        copied[index] = entry
    end
    return copied
end

local function trim(text)
    if type(text) ~= "string" then return nil end
    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function checkpointNodeLabel(node)
    if not node then return "(missing node)" end
    return string.format("%s [%s]", node.name or node.id or "Node", node.region or node.district or "Unknown")
end

local function getNodeById(nodeId)
    for _, node in ipairs((MTE and MTE.Nodes) or {}) do
        if node.id == nodeId then
            return node
        end
    end
    return nil
end

local function getCircuits()
    local module = MTE and MTE.KnockoutCircuits or nil
    return module and module.all and module.all() or {}
end

local function getQuickRaceCircuits()
    local module = MTE and MTE.KnockoutCircuits or nil
    return module and module.quickRaceAll and module.quickRaceAll() or {}
end

local function getCircuitById(circuitId)
    local module = MTE and MTE.KnockoutCircuits or nil
    return module and module.get and module.get(circuitId) or nil
end

local function setStatus(message, isError)
    _statusMessage = message
    _statusIsError = isError == true
end

local function loadEditor(circuit, forceNew)
    if type(circuit) ~= "table" then
        _editCircuitId = nil
        _nameBuf[1] = ""
        _regionBuf[1] = ""
        _editorCheckpoints = {}
        return
    end

    _editCircuitId = (forceNew or circuit.editable ~= true) and nil or circuit.id
    _nameBuf[1] = tostring(circuit.name or "")
    _regionBuf[1] = tostring(circuit.region or "")
    _editorCheckpoints = {}
    for _, checkpointId in ipairs(circuit.checkpoints or {}) do
        _editorCheckpoints[#_editorCheckpoints + 1] = checkpointId
    end
end

local function ensureSelection()
    local circuits = getCircuits()
    if _isNewCircuitMode then
        return circuits
    end
    if _selectedCircuitId and getCircuitById(_selectedCircuitId) then
        return circuits
    end
    _selectedCircuitId = circuits[1] and circuits[1].id or nil
    if _selectedCircuitId and #_editorCheckpoints == 0 then
        loadEditor(getCircuitById(_selectedCircuitId), false)
    end
    return circuits
end

local function currentMaxCars()
    return #(_editorCheckpoints or {})
end

local function currentMaxAI()
    return math.max(0, currentMaxCars() - 1)
end

local function drawCircuitList(circuits)
    ImGui.BeginChild("##knockoutCircuitList", 250, 0, true)
    if ImGui.Button("New Circuit##ko_circuit_new", s(110), s(24)) then
        _selectedCircuitId = nil
        _isNewCircuitMode = true
        loadEditor(nil, true)
        setStatus(nil, false)
    end
    ImGui.SameLine()
    if ImGui.Button("Refresh##ko_circuit_refresh", s(110), s(24)) then
        circuits = ensureSelection()
    end
    ImGui.Separator()

    if #circuits == 0 then
        ImGui.TextDisabled("No knockout circuits available.")
        ImGui.EndChild()
        return
    end

    for _, circuit in ipairs(circuits) do
        local label = circuit.editable and circuit.name or (circuit.name .. " [built-in]")
        local selected = _selectedCircuitId == circuit.id
        if selected then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1)
        end
        if ImGui.Button(label .. "##ko_circuit_" .. tostring(circuit.id), s(220), s(22)) then
            _selectedCircuitId = circuit.id
            _isNewCircuitMode = false
            loadEditor(circuit, false)
            setStatus(nil, false)
        end
        if selected then
            ImGui.PopStyleColor()
        end
        ImGui.TextDisabled(string.format(
            "%s  |  %d nodes  |  %d cars max incl. V",
            tostring(circuit.region or "Unknown"),
            tonumber(#(circuit.checkpoints or {}) or 0),
            tonumber((MTE and MTE.KnockoutCircuits and MTE.KnockoutCircuits.getMaxTotalGridSize and MTE.KnockoutCircuits.getMaxTotalGridSize(circuit)) or #(circuit.checkpoints or {}) or 0)))
        ImGui.Spacing()
    end
    ImGui.EndChild()
end

local function drawCheckpointEditor()
    local nodes = (MTE and MTE.Nodes) or {}
    local selectedNode = getNodeById(_pendingNodeId) or nodes[1]
    _pendingNodeId = selectedNode and selectedNode.id or nil

    if ImGui.BeginCombo("Add Node##ko_circuit_node_picker", checkpointNodeLabel(selectedNode)) then
        for _, node in ipairs(nodes) do
            local isSelected = node.id == _pendingNodeId
            if ImGui.Selectable(checkpointNodeLabel(node), isSelected) then
                _pendingNodeId = node.id
            end
        end
        ImGui.EndCombo()
    end
    ImGui.SameLine()
    local canAddNode = _pendingNodeId ~= nil and #_editorCheckpoints < 13
    if not canAddNode then ImGui.BeginDisabled() end
    if ImGui.Button("Append Node##ko_circuit_add", s(120), s(22)) then
        _editorCheckpoints[#_editorCheckpoints + 1] = _pendingNodeId
    end
    if not canAddNode then ImGui.EndDisabled() end

    ImGui.TextDisabled("Checkpoint order drives the knockout flow. Node 1 is the grid, the final node is the finish, and the last two drivers sprint from node N-1 to node N.")
    ImGui.Separator()

    if #_editorCheckpoints == 0 then
        ImGui.TextDisabled("No checkpoints added yet.")
        return
    end

    for index, checkpointId in ipairs(_editorCheckpoints) do
        local node = getNodeById(checkpointId)
        ImGui.Text(string.format("%d.", index))
        ImGui.SameLine()
        ImGui.Text(checkpointNodeLabel(node or { id = checkpointId, name = checkpointId, region = "Missing" }))
        ImGui.SameLine()
        if index > 1 then
            if ImGui.SmallButton("Up##ko_checkpoint_up_" .. tostring(index)) then
                _editorCheckpoints[index], _editorCheckpoints[index - 1] = _editorCheckpoints[index - 1], _editorCheckpoints[index]
            end
            ImGui.SameLine()
        end
        if index < #_editorCheckpoints then
            if ImGui.SmallButton("Down##ko_checkpoint_down_" .. tostring(index)) then
                _editorCheckpoints[index], _editorCheckpoints[index + 1] = _editorCheckpoints[index + 1], _editorCheckpoints[index]
            end
            ImGui.SameLine()
        end
        if ImGui.SmallButton("Remove##ko_checkpoint_remove_" .. tostring(index)) then
            table.remove(_editorCheckpoints, index)
            break
        end
    end
end

local function drawEditorPanel()
    local selectedCircuit = _selectedCircuitId and getCircuitById(_selectedCircuitId) or nil

    ImGui.BeginChild("##knockoutCircuitEditor", 0, 0, true)
    ImGui.Text("Knockout Circuit Configurator")
    ImGui.TextDisabled("Build point-to-point knockout routes from named nodes. Total grid cap always matches the number of configured nodes, including V.")
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

    if selectedCircuit then
        ImGui.Text(string.format("Selected: %s", tostring(selectedCircuit.name or selectedCircuit.id)))
        ImGui.TextDisabled(string.format(
            "%s  |  %d nodes  |  %d AI max",
            selectedCircuit.editable and "User circuit" or "Built-in circuit",
            tonumber(#(selectedCircuit.checkpoints or {}) or 0),
            tonumber((MTE and MTE.KnockoutCircuits and MTE.KnockoutCircuits.getMaxAIFieldSize and MTE.KnockoutCircuits.getMaxAIFieldSize(selectedCircuit)) or math.max(0, #(selectedCircuit.checkpoints or {}) - 1))))
    else
        ImGui.Text("Selected: New circuit")
    end

    ImGui.Separator()
    ImGui.InputText("Name##ko_circuit_name", _nameBuf, 128)
    ImGui.InputText("Region##ko_circuit_region", _regionBuf, 128)
    ImGui.TextDisabled(string.format("Current cap: %d cars total, %d AI rivals max", currentMaxCars(), currentMaxAI()))
    drawCheckpointEditor()

    ImGui.Separator()
    local canSave = #_editorCheckpoints >= 3
    if not canSave then ImGui.BeginDisabled() end
    if ImGui.Button(_editCircuitId and "Save Changes##ko_circuit_save" or "Save Circuit##ko_circuit_save", s(140), s(26)) then
        local module = MTE and MTE.KnockoutCircuits or nil
        local saved, err = nil, "Knockout circuit registry is unavailable."
        if module and module.upsertUserCircuit then
            saved, err = module.upsertUserCircuit({
                id = _editCircuitId,
                name = trim(_nameBuf[1]),
                region = trim(_regionBuf[1]),
                checkpoints = clone(_editorCheckpoints),
            })
        end
        if saved then
            _selectedCircuitId = saved.id
            _editCircuitId = saved.id
            _isNewCircuitMode = false
            loadEditor(saved, false)
            setStatus("Knockout circuit saved.", false)
        else
            setStatus(err or "Could not save knockout circuit.", true)
        end
    end
    if not canSave then ImGui.EndDisabled() end
    ImGui.SameLine()
    if selectedCircuit then
        if ImGui.Button("Clone Into Editor##ko_circuit_clone", s(140), s(26)) then
            loadEditor(selectedCircuit, true)
            setStatus("Loaded selected circuit into the editor as a new user circuit.", false)
        end
        if selectedCircuit.editable ~= true then
            ImGui.SameLine()
            ImGui.TextDisabled("Built-in circuits are read-only.")
        end
    end

    if selectedCircuit and selectedCircuit.editable == true then
        ImGui.SameLine()
        if _pendingDeleteId ~= selectedCircuit.id then
            if ImGui.Button("Delete Circuit##ko_circuit_delete", s(120), s(26)) then
                _pendingDeleteId = selectedCircuit.id
            end
        else
            if ImGui.Button("Confirm Delete##ko_circuit_delete_confirm", s(120), s(26)) then
                local module = MTE and MTE.KnockoutCircuits or nil
                local ok, err = module and module.deleteUserCircuit and module.deleteUserCircuit(selectedCircuit.id)
                if ok then
                    _pendingDeleteId = nil
                    _selectedCircuitId = nil
                    loadEditor(nil, true)
                    ensureSelection()
                    setStatus("Knockout circuit deleted.", false)
                else
                    setStatus(err or "Could not delete knockout circuit.", true)
                end
            end
        end
    else
        _pendingDeleteId = nil
    end

    local quickRaceCircuits = getQuickRaceCircuits()
    ImGui.Separator()
    ImGui.Text(string.format("Quick Race knockout choices: %d", tonumber(#quickRaceCircuits or 0)))
    ImGui.TextDisabled("Only checkpoint knockout circuits are surfaced in Quick Race. Built-in loops stay available only for legacy/manual knockout flows.")
    ImGui.EndChild()
end

function UIKnockoutCircuits.draw()
    local circuits = ensureSelection()
    drawCircuitList(circuits)
    ImGui.SameLine()
    drawEditorPanel()
end

return UIKnockoutCircuits
