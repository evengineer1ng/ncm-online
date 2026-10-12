-- ncm_engineering / client -- the Engineering panel: SERVICE, PARTS, BUILD, docked on the right (owner 2026-10-09).
--
-- FOCUS IS THE DANGEROUS PART (KB-61, KB-389). This page takes the CURSOR only, never the keyboard: the game keeps
-- the keyboard, so F9 and Esc always reach Lua, and closing never depends on the page being healthy. Focus follows a
-- confirmed draw (`eng:drawn`), and a watchdog gives the cursor back if the page never answers.
--
-- Data: the SERVICE view is ncm_world's (`ncm:eng.service`), the PARTS inventory is ncm_league's existing stream
-- (`ncm:component.inventory.*`, reassembled here with the same `vocabulary.chunks` receiver ncm_world uses). Every
-- action is a server event that already exists and is already authorised; this resource writes nothing.
local Chunks = NcmCore.get("vocabulary.chunks")

local function log(fmt, ...) print(("[ncm_engineering] " .. fmt):format(...)) end

local page, pageReady = nil, false
local isOpen = false
local tab = "service"
local focusToken = 0
local FOCUS_CONFIRM_MS = 2500
local lastService, lastParts, lastStates = nil, nil, nil

local function send(name, payload)
    if not (page and pageReady) then return false end
    return (pcall(function() page:send(name, payload or {}) end))
end

-- cursor only: keyboard false, cursor true (`setFocus(keyboard, cursor)`)
local function focus(on)
    if not page then return end
    local ok, err = pcall(function() return page:setFocus(false, on) end)
    if not ok then log("setFocus failed: %s", tostring(err)) end
end

-- KB-63: a large page:send is silently dropped, so lists go one item per message
local function pushService()
    local v = lastService
    if not v then return end
    send("eng:service.head", { balance = v.balance, skill = v.skill, site = v.site, n = #(v.cars or {}), error = v.error })
    for i, car in ipairs(v.cars or {}) do send("eng:service.car", { index = i, car = car }) end
    send("eng:service.done", { n = #(v.cars or {}) })
end

local function pushParts()
    local v = lastParts
    if not v then return end
    local machines = type(v.machines) == "table" and v.machines or {}
    local parts = type(v.parts) == "table" and v.parts or {}
    send("eng:parts.head", { balance = v.balance, partsEnabled = v.partsEnabled == true, n = #parts, m = #machines,
        fabricable = v.fabricable })
    for i, m in ipairs(machines) do send("eng:parts.machine", { index = i, machine = m }) end
    for i, p in ipairs(parts) do send("eng:parts.item", { index = i, part = p }) end
    send("eng:parts.done", { n = #parts })
    if lastStates then send("eng:parts.states", lastStates) end
end

local function refresh()
    TriggerServerEvent("ncm:eng.service.request")
    TriggerServerEvent("ncm:component.inventory.request")
    TriggerServerEvent("ncm:build.request")      -- ncm_build's server answers ncm_build's client (IDEA-1282)
end

local function close(why)
    if not isOpen then return end
    isOpen = false
    focusToken = focusToken + 1
    focus(false)
    send("eng:hide", {})
    if why then log("closed (%s)", why) end
end

local function openPanel()
    if not (page and pageReady) then log("not ready yet"); return false, "not_ready" end
    if isOpen then return true end
    isOpen = true
    focusToken = focusToken + 1
    local token = focusToken
    send("eng:show", { tab = tab })
    pushService(); pushParts()
    refresh()
    -- the page has 2.5 s to say it drew; otherwise the cursor goes back to the game and the panel closes
    CreateThread(function()
        Wait(FOCUS_CONFIRM_MS)
        if token ~= focusToken or not isOpen then return end
        log("ENGINEERING PANEL DID NOT DRAW in %d ms -- releasing the cursor (KB-61)", FOCUS_CONFIRM_MS)
        close("did not draw")
    end)
    return true
end

local function toggle()
    if isOpen then close("F9") return true end
    return openPanel()
end

exports("toggle", function() return toggle() end)
pcall(function() RegisterKeyMapping("ncm.engineering", "NCM: Engineering", "F9", toggle) end)
AddEventHandler("open77:pauseKey", function() close("Esc") end)

-- ------------------------------------------------------------------------------------------------ data in
RegisterNetEvent("ncm:eng.service", function(v)
    if type(v) ~= "table" then return end
    lastService = v
    if isOpen then pushService() end
end)

-- the Parts Inventory stream (ncm_league), received exactly as ncm_world's panel receives it
do
    local wire = nil
    local function finish()
        if not wire or not Chunks.complete(wire.rx) then return end
        local rows, why = Chunks.collect(wire.rx)
        if not rows then log("parts stream refused: %s", tostring(why)); wire = nil; return end
        local value = wire.head
        value.parts = rows
        wire = nil
        lastParts = value
        local ids = {}
        for _, m in ipairs(type(value.machines) == "table" and value.machines or {}) do ids[#ids + 1] = m.asset_id end
        if isOpen then TriggerServerEvent("ncm:component.state.request", ids); pushParts() end
    end
    RegisterNetEvent("ncm:component.inventory.stream.begin", function(meta)
        if type(meta) ~= "table" or type(meta.id) ~= "string" then return end
        local head = type(meta.head) == "table" and meta.head or {}
        wire = { id = meta.id, head = head, rx = Chunks.receiver(tonumber(meta.parts) or 0) }
        finish()
    end)
    RegisterNetEvent("ncm:component.inventory.stream.part", function(part)
        if not wire or type(part) ~= "table" or tostring(part.id or "") ~= wire.id then return end
        Chunks.accept(wire.rx, part.index, part.items)
        finish()
    end)
    RegisterNetEvent("ncm:component.inventory", function(value)
        if type(value) ~= "table" then return end
        lastParts = value
        if isOpen then pushParts() end
    end)
end

RegisterNetEvent("ncm:component.state", function(v)
    lastStates = type(v) == "table" and v or {}
    if isOpen then send("eng:parts.states", lastStates) end
end)

-- results: the page shows each one where it happened, then the views are re-read
local function result(name)
    RegisterNetEvent(name, function(v)
        if isOpen then send("eng:result", { kind = name, value = type(v) == "table" and v or {} }) end
        if isOpen then refresh() end
    end)
end
for _, n in ipairs({ "ncm:component.install.result", "ncm:component.service.result", "ncm:component.trunk.result", "ncm:slip.enable.result" }) do result(n) end

-- the repair's verdict carries the four section rolls: the page draws them in ink
RegisterNetEvent("ncm:vehicle.repair.result", function(v)
    if isOpen then send("eng:repair.result", type(v) == "table" and v or {}) end
    TriggerServerEvent("ncm:eng.service.request")
end)
RegisterNetEvent("ncm:vehicle.active", function() if isOpen then TriggerServerEvent("ncm:eng.service.request") end end)

-- ------------------------------------------------------------------------------------------------ WORKSHOP (L361)
-- ncm_workshop owns the bench; this tab talks to it over net events (never exports: KB-443)
local WORKSHOP_OPS = { start = true, collect = true, list = true }
RegisterNetEvent("ncm:workshop.state", function(s)
    if isOpen then send("eng:workshop.state", type(s) == "table" and s or { unavailable = true }) end
end)
RegisterNetEvent("ncm:workshop.result", function(r) if isOpen then send("eng:workshop.result", type(r) == "table" and r or {}) end end)
RegisterNetEvent("ncm:workshop.sheet", function(s) if isOpen then send("eng:workshop.sheet", type(s) == "table" and s or {}) end end)
CreateThread(function()            -- while WORKSHOP is on screen: the bench as it moves
    while true do
        Wait(10000)
        if isOpen and tab == "workshop" then TriggerServerEvent("ncm:workshop.request") end
    end
end)

-- ------------------------------------------------------------------------------------------------ BUILD (IDEA-1282)
-- ncm_build's client exports, called across resources (local.events). Only these verbs reach it from the page.
BUILD_OPS = { refresh = true, begin = true, edit = true, nudge = true, step = true, commit = true, cancel = true, remove = true }
function buildCall(fn, ...)
    local promise, why = Open77.exports.call("ncm_build", fn, ...)
    if not promise then return nil, why end
    local okP, v = promise:await()
    if okP then return v end
    return nil, v
end
local lastBuildWhy = nil
function pushBuild()
    local okC, s, why = pcall(buildCall, "state")
    if not okC then s, why = nil, s end
    if type(s) ~= "table" then
        -- KB-443: the owner saw "Build is not running on this server" while the server logged ncm_build ready and the
        -- client started it; the reason was never shown. Say it, once per distinct reason.
        local w = tostring(why or (s == nil and "no answer" or ("answered " .. type(s))))
        if w ~= lastBuildWhy then lastBuildWhy = w; log("BUILD unreachable: Open77.exports.call(ncm_build, state) -> %s", w) end
        send("eng:build.state", { unavailable = true, why = w })
        return
    end
    if lastBuildWhy then log("BUILD reachable again"); lastBuildWhy = nil end
    send("eng:build.state", s)
end
CreateThread(function()            -- while BUILD is on screen: results and server state as they arrive
    while true do
        Wait(500)
        if isOpen and tab == "build" then pcall(pushBuild) end
    end
end)

-- ------------------------------------------------------------------------------------------------ the page

-- 2026-10-12: the surface follows the screen (the page fits its 1920x1080 canvas uniformly); 1920x1080 if refused
local function createFitted(opts)
    local p, why = WebUI.create(opts)
    if p then return p, why end
    local fixed = {}
    for k, v in pairs(opts) do fixed[k] = v end
    fixed.width, fixed.height = 1920, 1080
    return WebUI.create(fixed)
end
AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    local reason
    page, reason = createFitted({ entry = "web/engineering.html", layer = "menu",
        fps = 30, zIndex = 860, transparent = true, visible = true })
    if not page then log("WebUI failed: %s", tostring(reason)); return end
    page:on("eng:ready", function() pageReady = true; log("ready (F9)") end)
    page:on("eng:drawn", function()
        if not isOpen then return end
        focusToken = focusToken + 1          -- cancels the watchdog for this open
        focus(true)
    end)
    page:on("eng:close", function() close("close button") end)
    page:on("eng:tab", function(d)
        if type(d) == "table" and type(d.tab) == "string" then
            tab = d.tab
            if tab == "build" then CreateThread(function() buildCall("refresh"); Wait(400); pushBuild() end) end
            if tab == "workshop" then TriggerServerEvent("ncm:workshop.request") end
        end
    end)
    -- BUILD (IDEA-1282): ncm_build owns placement and the attachments; this tab is only its controls
    page:on("eng:build", function(d)
        if type(d) ~= "table" or not BUILD_OPS[tostring(d.op or "")] then return end
        CreateThread(function()
            buildCall(d.op, d.a, d.b, d.c)
            pushBuild()
        end)
    end)
    page:on("eng:refresh", function() refresh() end)
    -- SERVICE
    page:on("eng:repair", function(d)
        if type(d) ~= "table" or type(d.assetId) ~= "string" or (d.provider ~= "self" and d.provider ~= "shop") then return end
        TriggerServerEvent("ncm:vehicle.repair", d.assetId, d.provider, tostring(d.key or ""))
    end)
    page:on("eng:route", function(d)
        if type(d) ~= "table" or type(d.x) ~= "number" or type(d.y) ~= "number" then return end
        CreateThread(function()
            local promise, why = Open77.exports.call("ncm_world", "routeTo", { x = d.x, y = d.y, z = d.z, name = d.name }, "workshop")
            if not promise then log("route: ncm_world unreachable (%s)", tostring(why)); return end
            local ok, routed = promise:await()
            send("eng:routed", { ok = ok and routed ~= false, name = d.name })
        end)
    end)
    -- PARTS (the same server events Machine Index used)
    page:on("eng:part.service", function(d)
        if type(d) == "table" and d.componentAssetId and d.conditionId then
            TriggerServerEvent("ncm:component.service", tostring(d.componentAssetId), tostring(d.conditionId), tostring(d.key or ""))
        end
    end)
    page:on("eng:part.install", function(d)
        if type(d) == "table" and d.componentAssetId and d.machineAssetId then
            TriggerServerEvent("ncm:component.install", tostring(d.componentAssetId), tostring(d.machineAssetId), tostring(d.key or ""))
        end
    end)
    page:on("eng:part.trunk", function(d)
        if type(d) == "table" and d.componentAssetId and d.machineAssetId then
            TriggerServerEvent("ncm:component.trunk", tostring(d.componentAssetId), tostring(d.machineAssetId), d.unload == true)
        end
    end)
    page:on("eng:part.mount", function(d)
        if type(d) == "table" and d.componentAssetId and d.machineAssetId and d.mountId and d.facing then
            TriggerServerEvent("ncm:engineering.mount", tostring(d.componentAssetId), tostring(d.machineAssetId), tostring(d.mountId), tostring(d.facing))
        end
    end)
    page:on("eng:part.unmount", function(d)
        if type(d) == "table" and d.componentAssetId then TriggerServerEvent("ncm:engineering.unmount", tostring(d.componentAssetId)) end
    end)
    page:on("eng:part.bind", function(d)
        if type(d) == "table" and d.componentAssetId and d.control then
            TriggerServerEvent("ncm:engineering.bindpad", tostring(d.componentAssetId), tostring(d.control),
                tostring(d.gesture or "tap"), tostring(d.command or "engage"))
        end
    end)
    page:on("eng:part.unbind", function(d)
        if type(d) == "table" and d.componentAssetId then TriggerServerEvent("ncm:engineering.unbindpad", tostring(d.componentAssetId)) end
    end)
    -- L356: a Slipstream unit's switch (ncm_slipstream owns the unit's state)
    page:on("eng:part.slip", function(d)
        if type(d) == "table" and d.componentAssetId and d.machineAssetId then
            TriggerServerEvent("ncm:slip.enable", tostring(d.componentAssetId), tostring(d.machineAssetId), d.enabled == true)
        end
    end)
    page:on("eng:workshop", function(d)
        if type(d) ~= "table" then return end
        if d.op == "refresh" then TriggerServerEvent("ncm:workshop.request") return end
        if not WORKSHOP_OPS[tostring(d.op or "")] then return end
        if d.op == "start" then
            TriggerServerEvent("ncm:workshop.start", { kind = tostring(d.kind or ""), assetId = d.assetId and tostring(d.assetId) or nil,
                designId = d.designId and tostring(d.designId) or nil, n = tonumber(d.n), key = tostring(d.key or "") })
        elseif d.op == "collect" then
            TriggerServerEvent("ncm:workshop.collect", tostring(d.projectId or ""))
        elseif d.op == "list" then
            TriggerServerEvent("ncm:workshop.list", { assetId = tostring(d.assetId or ""), price = tonumber(d.price), key = tostring(d.key or "") })
        end
    end)
    page:on("eng:part.fabricate", function(d)
        if type(d) == "table" and d.key then TriggerServerEvent("ncm:engineering.fabricate", tostring(d.key)) end
    end)
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    -- whatever happens to the page, the cursor goes back
    if page then pcall(function() page:setFocus(false, false) end) end
end)
