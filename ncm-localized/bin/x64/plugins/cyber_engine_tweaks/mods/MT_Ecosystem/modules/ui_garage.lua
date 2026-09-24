local UIGarage = {}
local i18n = require("modules/i18n")
local ImGui = i18n.wrapImGui(ImGui)
local function s(px) return MTE and MTE.UI and MTE.UI.s and MTE.UI.s(px) or px end
local PartsData = require("data/parts")

-- Sub-tab state
local _subTab = 1          -- 1=My Car, 2=Shop, 3=Rivals
local _shopSlotFilter = 0  -- 0=All, 1..6=specific slot
local _carSubTab = 1       -- 1=Installed, 2=Inventory

local RARITY_COLORS = {
    Common   = { 0.75, 0.75, 0.75, 1.0 },
    Street   = { 0.40, 0.85, 0.40, 1.0 },
    Pro      = { 0.30, 0.55, 1.00, 1.0 },
    Elite    = { 0.80, 0.40, 1.00, 1.0 },
}

local SLOT_LABELS = {
    engine      = "Engine",
    drivetrain  = "Drivetrain",
    brakes      = "Brakes",
    handling    = "Handling",
    stability   = "Stability",
    antiCrawl   = "Anti-Crawl",
}

-- â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function getTransactionSystem()
    local ts = nil
    pcall(function()
        ts = Game.GetTransactionSystem()
    end)
    if ts then
        return ts
    end
    pcall(function()
        local container = Game.GetScriptableSystemsContainer()
        if container then
            ts = container:Get("TransactionSystem")
        end
    end)
    return ts
end

local function getMoneyItemID()
    local itemId = nil
    pcall(function()
        itemId = ItemID.FromTDBID(TweakDBID.new("Items.money"))
    end)
    return itemId
end

local function getPlayerEddies()
    local qty = nil
    pcall(function()
        local player = Game.GetPlayer()
        local ts = getTransactionSystem()
        local itemId = getMoneyItemID()
        if not ts or not player then return end
        if itemId then
            local ok, value = pcall(function()
                return ts:GetItemQuantity(player, itemId, false)
            end)
            if ok and value ~= nil then
                qty = value
                return
            end
            ok, value = pcall(function()
                return ts:GetItemQuantity(player, itemId)
            end)
            if ok and value ~= nil then
                qty = value
                return
            end
            ok, value = pcall(function()
                return ts:GetItemQuantity(player, itemId, true)
            end)
            if ok and value ~= nil then
                qty = value
                return
            end
        end
    end)
    local numericQty = tonumber(qty)
    if numericQty == nil then
        return nil
    end
    return math.max(0, numericQty)
end

local function deductEddies(amount)
    local target = math.max(0, math.floor(tonumber(amount) or 0))
    if target <= 0 then
        return true
    end
    local removed = nil
    local callOk = pcall(function()
        local player = Game.GetPlayer()
        local ts = getTransactionSystem()
        local itemId = getMoneyItemID()
        if ts and player and itemId then
            removed = ts:RemoveItem(player, itemId, target)
        end
    end)
    if not callOk then
        return false
    end
    if removed == nil then
        return true
    end
    return removed == true
end

local function getCareer()
    local c = MTE and MTE.Careers
    return c and c.active and c.active() or nil
end

local function getVehicleKey()
    local t = MTE and MTE.Tuning
    return t and t._vehicleKey or nil
end

local function rarityCol(rarity)
    return RARITY_COLORS[rarity] or RARITY_COLORS.Common
end

local function metricRow(label, value, lo, hi)
    local norm = math.max(0, math.min(1, (value - lo) / (hi - lo)))
    ImGui.Text(string.format("%-18s  %.3f", label, value))
    ImGui.SameLine()
    ImGui.ProgressBar(norm, s(130), s(14), "")
end

local function partFamilyText(entry)
    local label = entry and (entry.familyLabel or entry.family) or nil
    return type(label) == "string" and label ~= "" and label or "General"
end

local function categoryUsage(summary, slotId)
    local entries = summary and summary.installedByCategory and summary.installedByCategory[slotId] or {}
    local used = #entries
    local capacity = math.max(used, tonumber(summary and summary.slotProfile and summary.slotProfile[slotId] or 0) or 0)
    return entries, used, capacity, math.max(0, capacity - used)
end

local function labelsForTradeoffs(entries, maxCount)
    local labels = {}
    for _, entry in ipairs(entries or {}) do
        labels[#labels + 1] = tostring(entry.label or entry.axis or "")
    end
    local out = {}
    for index = 1, math.min(maxCount or #labels, #labels) do
        out[#out + 1] = labels[index]
    end
    return table.concat(out, "  |  ")
end

local function effectMetricSummary()
    local metrics = MTE and MTE.Metrics or nil
    if not metrics then return nil end
    if metrics.currentSummary then
        local current = metrics.currentSummary()
        if type(current) == "table" then
            return current
        end
    end
    return metrics.latestSummary and metrics.latestSummary() or nil
end

local function metricTimeText(value)
    local n = tonumber(value)
    if not n or n <= 0 then return "--.-- s" end
    return string.format("%.2f s", n)
end

local function slipText(value)
    local n = tonumber(value)
    if not n or n <= 0 then return "0.00" end
    return string.format("%.2f", n)
end

-- â”€â”€ My Car tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function drawMyCarTab()
    local career     = getCareer()
    local vehicleKey = getVehicleKey()
    if not career or not vehicleKey then
        ImGui.TextDisabled("No active career or vehicle detected.")
        return
    end

    local parts     = MTE.Parts
    local summary   = parts.getVehicleSummary(career, vehicleKey) or {}
    local hw = summary.performance or summary.perf or {}

    -- Inner sub-tab bar: Installed | Inventory
    local carSubLabels = { "Installed", "Inventory" }
    for i, label in ipairs(carSubLabels) do
        if i > 1 then ImGui.SameLine() end
        local display = (_carSubTab == i) and ("[" .. label .. "]") or label
        if ImGui.Button(display .. "##cstab" .. i) then
            _carSubTab = i
        end
    end
    ImGui.Separator()

    if _carSubTab == 1 then
        -- â”€â”€ Installed slots â”€â”€
        ImGui.Text("Installed Parts")
        ImGui.Separator()
        for _, slotId in ipairs(PartsData.SLOT_ORDER) do
            local slotLabel = SLOT_LABELS[slotId] or slotId
            local entries, used, capacity, openCount = categoryUsage(summary, slotId)
            ImGui.Text(string.format("%s  [%d/%d]", slotLabel, used, capacity))
            for index, inst in ipairs(entries) do
                local c = rarityCol(inst.rarity)
                ImGui.Text(string.format("  #%d", index))
                ImGui.SameLine()
                ImGui.TextColored(c[1], c[2], c[3], c[4], inst.name or inst.partId)
                ImGui.SameLine()
                if ImGui.SmallButton("Uninstall##mcar_" .. slotId .. "_" .. index) then
                    parts.uninstallPart(career, vehicleKey, slotId, index)
                end
            end
            for index = 1, openCount do
                ImGui.TextDisabled(string.format("  [ empty %d ]", used + index))
            end
        end

        -- â”€â”€ Performance metrics â”€â”€
        ImGui.Spacing()
        ImGui.Text("Performance Metrics")
        ImGui.Separator()
        if summary.buildIdentity and summary.buildIdentity.headline then
            ImGui.Text(string.format("Build Identity: %s", tostring(summary.buildIdentity.headline)))
            if type(summary.buildIdentity.tags) == "table" and #summary.buildIdentity.tags > 0 then
                ImGui.TextDisabled(table.concat(summary.buildIdentity.tags, "  |  "))
            end
            ImGui.Spacing()
        end
        metricRow("Speed Scale",   hw.liveSpeedScale   or 1.0, 0.80, 1.25)
        metricRow("Sprint Scale",  hw.sprintScale      or 1.0, 0.80, 1.30)
        metricRow("Drag Scale",    hw.dragScale        or 1.0, 0.80, 1.28)
        metricRow("Knockout Scale",hw.knockoutScale    or 1.0, 0.80, 1.25)
        ImGui.Spacing()
        ImGui.Text("Driver-Feel Effects")
        ImGui.Separator()
        local effectEntries = summary.canonicalEffectEntries or {}
        for _, entry in ipairs(effectEntries) do
            metricRow(tostring(entry.label or entry.axis or "Effect"), tonumber(entry.value) or 1.0, 0.84, 1.30)
        end
        ImGui.Spacing()
        ImGui.Text("Race Context Fit")
        ImGui.Separator()
        local fits = summary.raceFits or {}
        metricRow("Drag",          fits.drag       or 1.0, 0.88, 1.24)
        metricRow("Sprint",        fits.sprint     or 1.0, 0.88, 1.22)
        metricRow("Knockout",      fits.knockout   or 1.0, 0.88, 1.22)
        metricRow("Long Route",    fits.longRoute  or 1.0, 0.88, 1.23)
        ImGui.Spacing()
        ImGui.Text("Effect Readback")
        ImGui.Separator()
        local metrics = effectMetricSummary()
        if metrics then
            ImGui.Text(string.format("0-100: %s", metricTimeText(metrics.zeroToHundred)))
            ImGui.Text(string.format("80-150 Pull: %s", metricTimeText(metrics.pullEightyToOneFifty)))
            ImGui.Text(string.format("Launch Slip Avg / Peak: %s / %s", slipText(metrics.launchSlipAvg), slipText(metrics.launchSlipPeak)))
            if metrics.active then
                ImGui.TextDisabled("Readback source: current session")
            else
                ImGui.TextDisabled("Readback source: last completed session")
            end
        else
            ImGui.TextDisabled("No effect readback recorded yet.")
        end
        ImGui.Spacing()
        ImGui.Text(string.format("Filled Slots: %d / %d", summary.installedCount or 0, summary.slotCount or 0))
        local strengths = summary.canonicalStrengths or summary.strengths
        local weaknesses = summary.canonicalWeaknesses or summary.weaknesses
        if type(strengths) == "table" and #strengths > 0 then
            ImGui.TextDisabled("Gains Time In: " .. labelsForTradeoffs(strengths, 3))
        end
        if type(weaknesses) == "table" and #weaknesses > 0 then
            ImGui.TextDisabled("Bleeds Time In: " .. labelsForTradeoffs(weaknesses, 2))
        end

    else
        -- â”€â”€ Inventory: list uninstalled parts by slot â”€â”€
        ImGui.Text("Parts in Inventory (uninstalled)")
        ImGui.Separator()

        local anyParts = false
        for _, slotId in ipairs(PartsData.SLOT_ORDER) do
            local available = parts.getAvailableInventory(career, vehicleKey, slotId) or {}
            if #available > 0 then
                anyParts = true
                local slotLabel = SLOT_LABELS[slotId] or slotId
                local _, used, capacity, openCount = categoryUsage(summary, slotId)
                ImGui.Text(string.format("%s  [%d/%d]", slotLabel, used, capacity))
                ImGui.Separator()
                for _, entry in ipairs(available) do
                    local c = rarityCol(entry.rarity)
                    ImGui.TextColored(c[1], c[2], c[3], c[4],
                        string.format("[%-6s]", entry.rarity or "?"))
                    ImGui.SameLine()
                    ImGui.Text(string.format("%s  [%s]", entry.name or entry.partId or "?", partFamilyText(entry)))
                    -- Show condition
                    if entry.condition then
                        ImGui.SameLine()
                        ImGui.TextDisabled(string.format("(%.0f%%)", (entry.condition or 1) * 100))
                    end
                    if entry.focus and entry.focus ~= "" then
                        ImGui.TextDisabled("   " .. tostring(entry.focus))
                    end
                    if entry.tradeoff and entry.tradeoff ~= "" then
                        ImGui.TextDisabled("   Tradeoff: " .. tostring(entry.tradeoff))
                    end
                    -- Modifier preview
                    if entry.modifiers then
                        local mods = {}
                        for k, v in pairs(entry.modifiers) do
                            mods[#mods+1] = string.format("%s:%.2f", k, v)
                        end
                        if #mods > 0 then
                            ImGui.SameLine()
                            ImGui.TextDisabled("  " .. table.concat(mods, "  "))
                        end
                    end
                    if openCount > 0 then
                        ImGui.SameLine()
                        if ImGui.SmallButton("Install##inv_" .. entry.instanceId) then
                            parts.installPart(career, vehicleKey, entry.instanceId, slotId, used + 1)
                        end
                    else
                        for index = 1, used do
                            ImGui.SameLine()
                            if ImGui.SmallButton("Replace " .. index .. "##inv_" .. entry.instanceId .. "_" .. index) then
                                parts.installPart(career, vehicleKey, entry.instanceId, slotId, index)
                            end
                        end
                    end
                end
                ImGui.Spacing()
            end
        end

        if not anyParts then
            ImGui.TextDisabled("No uninstalled parts in inventory.")
            ImGui.TextDisabled("Buy parts from the Shop tab or earn them through races.")
        end
    end
end

-- â”€â”€ Shop tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function drawShopTab()
    local career     = getCareer()
    local vehicleKey = getVehicleKey()
    if not career then
        ImGui.TextDisabled("No active career.")
        return
    end

    local parts  = MTE.Parts
    local eddies = getPlayerEddies()
    local summary = vehicleKey and parts.getVehicleSummary(career, vehicleKey) or nil
    local allStock = parts.getShopInventory(career, vehicleKey) or {}
    local offers = parts.getPendingOffers(career) or {}
    local balanceKnown = type(eddies) == "number"
    local balanceStr = (balanceKnown and eddies > 0)
        and string.format("Balance: %.0f \xE2\x82\xA1", eddies)
        or  (balanceKnown and "Balance: 0 \xE2\x82\xA1" or "Balance: unavailable  (money check did not resolve this frame)")
    ImGui.Text(balanceStr)
    if allStock[1] and allStock[1].refreshAtRace then
        local racesRemaining = math.max(0, tonumber(allStock[1].refreshAtRace or 0) - tonumber(career and career.stats and (career.stats.racesFinished or career.stats.racesRun) or 0))
        ImGui.TextDisabled(string.format("Rotating stock refresh in %d finished race%s.", racesRemaining, racesRemaining == 1 and "" or "s"))
    end
    ImGui.Separator()

    if #offers > 0 then
        ImGui.Text("Pending Offers")
        ImGui.Separator()
        for _, offer in ipairs(offers) do
            ImGui.Text(offer.title or offer.offerId)
            if offer.subtitle and offer.subtitle ~= "" then
                ImGui.TextDisabled("   " .. tostring(offer.subtitle))
            end
            if offer.expiresAtRace then
                local racesLeft = math.max(0, tonumber(offer.expiresAtRace or 0) - tonumber(career and career.stats and (career.stats.racesFinished or career.stats.racesRun) or 0))
                ImGui.TextDisabled(string.format("   Expires in %d finished race%s", racesLeft, racesLeft == 1 and "" or "s"))
            end
            for _, item in ipairs(offer.items or {}) do
                local c = rarityCol(item.rarity)
                ImGui.TextColored(c[1], c[2], c[3], c[4], string.format("   [%-6s]", item.rarity or "?"))
                ImGui.SameLine()
                ImGui.Text(string.format("%s  [%s]", item.name or item.id or "?", partFamilyText(item)))
                if item.focus and item.focus ~= "" then
                    ImGui.TextDisabled("      " .. tostring(item.focus))
                end
            end

            local offerPrice = tonumber(offer.price) or 0
            local canAfford = (not balanceKnown) or eddies >= offerPrice
            if not canAfford then ImGui.BeginDisabled() end
            if ImGui.SmallButton((offerPrice <= 0 and "Claim" or string.format("Buy Pack (%.0f \xE2\x82\xA1)", offerPrice)) .. "##offer_" .. tostring(offer.offerId)) then
                local paid = offerPrice <= 0 or deductEddies(offerPrice)
                if paid then
                    local acquired, err = parts.claimOffer(career, offer.offerId)
                    if not acquired then
                        print("[NCM/Garage] Offer claim failed: " .. tostring(err))
                    end
                else
                    print("[NCM/Garage] Offer purchase failed: could not remove eddies.")
                end
            end
            if not canAfford then ImGui.EndDisabled() end
            ImGui.Separator()
        end
    end

    local slotOptions = { "All", "Engine", "Drivetrain", "Brakes", "Handling", "Stability", "Anti-Crawl" }
    local changed
    local newFilter
    changed, newFilter = ImGui.Combo("Slot Filter", _shopSlotFilter, slotOptions, #slotOptions)
    if type(newFilter) == "number" then _shopSlotFilter = newFilter end

    ImGui.Separator()

    local slotKey = _shopSlotFilter > 0 and PartsData.SLOT_ORDER[_shopSlotFilter] or nil
    local catalog = parts.getShopInventory(career, vehicleKey, slotKey) or {}

    ImGui.BeginChild("ShopList", 0, 320, false)
    for _, def in ipairs(catalog) do
        local c = rarityCol(def.rarity)
        ImGui.TextColored(c[1], c[2], c[3], c[4], string.format("[%-6s]", def.rarity))
        ImGui.SameLine()
        ImGui.Text(def.name or def.id)
        ImGui.SameLine(0, 6)
        ImGui.TextDisabled(string.format("(%s / %s)", SLOT_LABELS[def.slot] or def.slot, partFamilyText(def)))
        ImGui.SameLine(0, 6)
        ImGui.Text(string.format("%.0f \xE2\x82\xA1", def.price or 0))

        if def.description and def.description ~= "" then
            ImGui.TextDisabled("   " .. def.description)
        end
        if def.focus and def.focus ~= "" then
            ImGui.TextDisabled("   Focus: " .. tostring(def.focus))
        end
        if def.tradeoff and def.tradeoff ~= "" then
            ImGui.TextDisabled("   Tradeoff: " .. tostring(def.tradeoff))
        end

        -- Modifier preview
        if def.modifiers then
            local mods = {}
            for k, v in pairs(def.modifiers) do
                mods[#mods+1] = string.format("%s: %.2f", k, v)
            end
            if #mods > 0 then
                ImGui.TextDisabled("   " .. table.concat(mods, "  |  "))
            end
        end

        local _, used, capacity, openCount = categoryUsage(summary, def.slot)
        if vehicleKey then
            ImGui.TextDisabled(string.format("   Slot usage: %d/%d", used, capacity))
        end

        local canAfford = (not balanceKnown) or eddies >= (def.price or 0)
        if not canAfford then ImGui.BeginDisabled() end
        if ImGui.SmallButton("Buy##shop_" .. def.id) then
            if deductEddies(def.price or 0) then
                local instanceId, err = parts.purchasePart(career, def.id)
                if not instanceId then
                    print("[NCM/Garage] Purchase failed: " .. tostring(err))
                end
            else
                print("[NCM/Garage] Purchase failed: could not remove eddies.")
            end
        end
        if vehicleKey and openCount > 0 then
            ImGui.SameLine()
            if ImGui.SmallButton("Buy & Install##shop_install_" .. def.id) then
                if deductEddies(def.price or 0) then
                    local instanceId, err = parts.purchasePart(career, def.id, vehicleKey, def.slot, used + 1)
                    if not instanceId then
                        print("[NCM/Garage] Purchase failed: " .. tostring(err))
                    end
                else
                    print("[NCM/Garage] Purchase failed: could not remove eddies.")
                end
            end
        end
        if not canAfford then ImGui.EndDisabled() end

        ImGui.Separator()
    end
    ImGui.EndChild()
end

-- â”€â”€ Rivals tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function drawRivalsTab()
    local racing = MTE and MTE.Racing
    local field  = racing and racing._field
    if not field or #field == 0 then
        ImGui.TextDisabled("No active race field.")
        return
    end

    local parts = MTE.Parts

    ImGui.Columns(6, "RivalsTable", true)
    ImGui.Text("Driver")      ImGui.NextColumn()
    ImGui.Text("Tier")        ImGui.NextColumn()
    ImGui.Text("Pace")        ImGui.NextColumn()
    ImGui.Text("Build")       ImGui.NextColumn()
    ImGui.Text("Slots")       ImGui.NextColumn()
    ImGui.Text("Best Fit")    ImGui.NextColumn()
    ImGui.Separator()

    for _, entry in ipairs(field) do
        local hw = (parts and parts.getDriverHardwareSummary(entry))
               or { buildHeadline = "Balanced", slotCount = 0, bestRaceFit = 1.0 }

        ImGui.Text(tostring(entry.displayName or entry.name or entry.id or "?"))
        ImGui.NextColumn()

        ImGui.Text(tostring(entry.tier or "?"))
        ImGui.NextColumn()

        ImGui.Text(string.format("%.3f", tonumber(entry.pace) or 0))
        ImGui.NextColumn()

        ImGui.Text(tostring(hw.buildHeadline or "Balanced"))
        ImGui.NextColumn()

        ImGui.Text(tostring(hw.slotCount or 0))
        ImGui.NextColumn()

        local scale = hw.bestRaceFit or 1.0
        local r, g, b
        if scale >= 1.10 then r,g,b = 0.4, 1.0, 0.4
        elseif scale <= 0.92 then r,g,b = 1.0, 0.4, 0.4
        else r,g,b = 0.9, 0.9, 0.9 end
        ImGui.TextColored(r, g, b, 1.0, string.format("%.3f", scale))
        ImGui.NextColumn()
    end

    ImGui.Columns(1)
end

-- â”€â”€ Public entry point â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function UIGarage.draw()
    local subTabs = { "My Car", "Shop", "Rivals" }
    for i, label in ipairs(subTabs) do
        if i > 1 then ImGui.SameLine() end
        local display = (_subTab == i) and ("[" .. label .. "]") or label
        if ImGui.Button(display .. "##gtab" .. i) then
            _subTab = i
        end
    end
    ImGui.Separator()

    if     _subTab == 1 then drawMyCarTab()
    elseif _subTab == 2 then drawShopTab()
    elseif _subTab == 3 then drawRivalsTab()
    end
end

return UIGarage

