-- ============================================================
-- MT_Ecosystem: modules/ui_tuning.lua
-- Tuning tab UI: 6-category parameter sliders, named profiles,
-- vehicle info, ManualClutch anti-crawl toggle.
-- Drawn from ui.lua's Tuning tab slot via UI.drawTuningTab().
-- ============================================================

local UIT = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end

-- Sub-tab = current category being viewed
local _catIdx        = 1
local _profileNameBuf = { "" }
local _confirmDelProfile = nil
local _confirmOverwrite  = nil

-- -- Helpers ---------------------------------------------------

local CAT_LABELS = { "Engine", "Drivetrain", "Brakes", "Handling", "Stability", "Anti-Crawl" }
-- Map display label ? PARAMS category key
local CAT_KEY_MAP = {
    ["Engine"]     = "Engine",
    ["Drivetrain"] = "Drivetrain",
    ["Brakes"]     = "Brakes",
    ["Handling"]   = "Handling",
    ["Stability"]  = "Stability",
    ["Anti-Crawl"] = "AntiCrawl",
}

local function paramsForCat(catKey)
    local out = {}
    for _, p in ipairs(MTE.Tuning.PARAMS) do
        if p.cat == catKey then table.insert(out, p) end
    end
    return out
end

local function sliderColor(val, def)
    if math.abs(val - def) < 0.02 then
        return 0.4, 0.4, 0.4, 1  -- grey ï¿½ at default
    elseif val > def then
        return 0.2, 0.8, 0.3, 1  -- green ï¿½ boosted
    else
        return 0.9, 0.4, 0.2, 1  -- orange ï¿½ reduced
    end
end

-- -- Main draw -------------------------------------------------

function UIT.draw()
    local T = MTE.Tuning

    -- Vehicle info bar
    local vk = T._vehicleKey
    if vk and vk ~= "" then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.9, 1.0, 1)
        ImGui.Text(string.format("Vehicle: %s", vk))
        ImGui.PopStyleColor()
    else
        ImGui.TextDisabled("Not in a vehicle.")
    end

    ImGui.Separator()

    -- Category sub-tabs
    for i, label in ipairs(CAT_LABELS) do
        if i > 1 then ImGui.SameLine() end
        local active = (_catIdx == i)
        if active then ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.9, 1) end
        if ImGui.Button(label .. "##ctab" .. i, s(84), s(22)) then _catIdx = i end
        if active then ImGui.PopStyleColor() end
    end

    ImGui.Separator()
    ImGui.Spacing()

    local catLabel = CAT_LABELS[_catIdx]
    local catKey   = CAT_KEY_MAP[catLabel]
    local params   = paramsForCat(catKey)

    if #params == 0 then
        ImGui.TextDisabled("No parameters in this category.")
    else
        UIT._drawSliders(T, params)
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    UIT._drawActions(T)
    UIT._drawProfiles(T)
end

-- -- Sliders for one category ----------------------------------

function UIT._drawSliders(T, params)
    for _, p in ipairs(params) do
        local val = T.scratch[p.key] or p.default
        local r, g, b, a = sliderColor(val, p.default)

        ImGui.PushStyleColor(ImGuiCol.SliderGrab,     r,   g,   b, a)
        ImGui.PushStyleColor(ImGuiCol.SliderGrabActive, r*1.2, g*1.2, b*1.2, a)

        ImGui.SetNextItemWidth(220)
        local newVal, changed = ImGui.SliderFloat(
            string.format("##%s", p.key), val, p.min, p.max,
            string.format("%.2f", val))

        ImGui.PopStyleColor(2)
        ImGui.SameLine()

        -- Color-coded label showing delta from default
        ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, a)
        local delta = val - p.default
        local sign  = delta >= 0 and "+" or ""
        ImGui.Text(string.format("%-18s  [def %.1f  %s%.2f]",
            p.label, p.default, sign, delta))
        ImGui.PopStyleColor()

        if changed then
            T.set(p.key, newVal)
        end

        -- Reset individual param button
        ImGui.SameLine()
        if ImGui.SmallButton("R##" .. p.key) then
            T.set(p.key, p.default)
        end
    end
end

-- -- Action row ------------------------------------------------

function UIT._drawActions(T)
    if ImGui.Button("Reset All", s(90), s(22)) then
        T.resetAll()
    end
    ImGui.SameLine()
    if ImGui.Button("Apply Now", s(90), s(22)) then
        T.dirty = true
    end
    ImGui.SameLine()
    ImGui.TextDisabled(T.dirty and "  (pending)" or "  (applied)")
end

-- -- Profile panel ---------------------------------------------

function UIT._drawProfiles(T)
    ImGui.Spacing()
    ImGui.Text("Profiles")
    ImGui.Separator()

    local names = T.profileNames()

    -- Save current as named profile
    ImGui.Text("Save as:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(150)
    local buf, ch = ImGui.InputText("##pname", _profileNameBuf[1], 32)
    if ch then _profileNameBuf[1] = buf end
    ImGui.SameLine()
    if ImGui.SmallButton("Save##psave") then
        if _profileNameBuf[1] ~= "" then
            -- Check if profile already exists
            local exists = false
            for _, n in ipairs(names) do
                if n == _profileNameBuf[1] then exists = true; break end
            end
            if exists and not _confirmOverwrite then
                _confirmOverwrite = _profileNameBuf[1]
            else
                local ok, err = T.saveProfile(_profileNameBuf[1])
                if not ok then
                    print("[NCM/Tuning] Profile save error: " .. tostring(err))
                end
                _confirmOverwrite = nil
            end
        end
    end

    -- Overwrite confirmation
    if _confirmOverwrite then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.7, 0.1, 1)
        ImGui.Text(string.format("Overwrite '%s'?", _confirmOverwrite))
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.SmallButton("Yes##ovw") then
            local ok, err = T.saveProfile(_confirmOverwrite)
            if not ok then print("[NCM/Tuning] Profile save error: " .. tostring(err)) end
            _confirmOverwrite = nil
        end
        ImGui.SameLine()
        if ImGui.SmallButton("No##ovw") then _confirmOverwrite = nil end
    end

    ImGui.Spacing()

    if #names == 0 then
        ImGui.TextDisabled("No profiles saved for this vehicle.")
        return
    end

    for _, name in ipairs(names) do
        ImGui.Text(string.format("  %-24s", name))
        ImGui.SameLine()
        if ImGui.SmallButton("Load##" .. name) then
            T.loadProfile(name)
        end
        ImGui.SameLine()
        if ImGui.SmallButton("Del##" .. name) then
            _confirmDelProfile = name
        end

        -- Confirm delete
        if _confirmDelProfile == name then
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0.3, 0.3, 1)
            ImGui.Text("Delete?")
            ImGui.PopStyleColor()
            ImGui.SameLine()
            if ImGui.SmallButton("Yes##dpy") then
                T.deleteProfile(name)
                _confirmDelProfile = nil
            end
            ImGui.SameLine()
            if ImGui.SmallButton("No##dpn") then
                _confirmDelProfile = nil
            end
        end
    end
end

function UIT.init()
    -- Nothing to register
end

return UIT

