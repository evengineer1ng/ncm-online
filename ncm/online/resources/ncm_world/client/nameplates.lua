-- ncm_world / client / nameplates — rich NCM Driver Cards over streamed remote players (L130).
--
-- Native code owns per-frame projection. Lua publishes only slow-changing, deliberately public presentation.
-- Handoff order is strict: page ready -> native stream established -> system native drawer disabled. Any failure
-- stops our stream and restores the system drawer, so a broken NCM page cannot leave players unidentified.
local Core = NcmCore
local Presentation = Core.get("driver.presentation")

local page, pageReady, active = nil, false, false
local nativeSuppressed = false
local lastHeartbeat = 0
local lastPresentationSignature = nil
local running = true

local function log(fmt, ...)
    print(("[ncm_world/client/nameplates] " .. fmt):format(...))
end

local function call(resource, name, ...)
    local promise, reason = Open77.exports.call(resource, name, ...)
    if not promise then return nil, reason end
    return promise:await()
end

local function restoreNative(why, force)
    if Open77.nameplates and Open77.nameplates.stopStream then pcall(Open77.nameplates.stopStream) end
    if nativeSuppressed or force then
        local ok, reason = call("open77_nameplates", "setEnabled", true)
        log("native renderer restored (%s): %s %s", tostring(why or "teardown"), tostring(ok), tostring(reason or ""))
    end
    active = false
    nativeSuppressed = false
end

local function activate()
    if active or not (page and pageReady) then return end
    local streamed, streamReason = Open77.nameplates.stream(page)
    if streamed ~= true then
        log("custom stream refused: %s; native renderer left on", tostring(streamReason))
        restoreNative("stream_refused")
        return
    end
    local disabled, disableReason = call("open77_nameplates", "setEnabled", false)
    if disabled ~= true then
        log("native renderer handoff refused: %s; custom stream stopped", tostring(disableReason))
        restoreNative("handoff_refused", true)
        return
    end
    nativeSuppressed = true
    active = true
    lastHeartbeat = GetGameTimer()
    log("custom Driver Card active; native text renderer suppressed")
end

local function presentationRows()
    local rows, sig = {}, {}
    local ok, players = pcall(Open77.players.all, { streamed = true })
    if not ok or type(players) ~= "table" then return rows, "unavailable" end
    local localId = Open77.players.localId and Open77.players.localId() or nil
    for _, raw in ipairs(players) do
        local id = tonumber(raw)
        if id and id ~= tonumber(localId) then
            local bagOk, bag = pcall(Open77.state.player, id)
            local rawProjection = bagOk and type(bag) == "table" and bag.ncmPresentation or nil
            local projection = Presentation.sanitizePublicProjection(rawProjection)
            rows[#rows + 1] = { id = tostring(id), presentation = projection }
            sig[#sig + 1] = table.concat({ tostring(id), projection.bannerId,
                table.concat(projection.displayedBadgeIds, ","), projection.fingerprint.sampleState,
                tostring(projection.fingerprint.definitionVersion) }, "|")
        end
    end
    table.sort(rows, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    table.sort(sig)
    return rows, table.concat(sig, ";")
end

local function publishPresentations(force)
    if not (page and pageReady) then return end
    local rows, signature = presentationRows()
    if not force and signature == lastPresentationSignature then return end
    lastPresentationSignature = signature
    page:send("ncm-card:presentations", { rows = rows })
end

local function createPage()
    if page then return true end
    local reason
    page, reason = WebUI.create({
        entry = "web/nameplates.html", layer = "hud", width = 1920, height = 1080,
        fps = 60, zIndex = 650, transparent = true, visible = true,
    })
    if not page then log("Driver Card WebUI failed: %s; native renderer left on", tostring(reason)); return false end
    page:on("ncm-card:ready", function()
        pageReady = true
        lastHeartbeat = GetGameTimer()
        page:send("ncm-card:assets", Presentation.assets())
        publishPresentations(true)
        CreateThread(activate)
    end)
    page:on("ncm-card:heartbeat", function() lastHeartbeat = GetGameTimer() end)
    page:on("ncm-card:error", function(data)
        pageReady = false
        log("Driver Card page fault: %s", type(data) == "table" and tostring(data.message) or tostring(data))
        CreateThread(function() restoreNative("page_fault") end)
    end)
    return true
end

AddEventHandler("onClientResourceStart", function(name)
    if name == GetCurrentResourceName() then
        createPage()
        return
    end
    if name == "open77_nameplates" and running then
        -- The system resource's in-memory enabled flag resets to true on its own reload. Re-acquire the
        -- handoff after its start rather than allowing native text and the NCM card to coexist.
        active, nativeSuppressed = false, false
        CreateThread(function()
            Wait(250)
            if page and pageReady then activate() end
        end)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name == "open77_nameplates" then nativeSuppressed = false end
end)

-- World exit releases both render and stream ownership. The system resource restores native on worldReady;
-- after it has done so, re-establish the same safe handoff.
AddEventHandler("open77:worldReady", function()
    if not running then return end
    active = false
    lastPresentationSignature = nil
    CreateThread(function()
        Wait(250)
        restoreNative("world_ready")
        if page and pageReady then activate(); publishPresentations(true) end
    end)
end)

CreateThread(function()
    while running do
        if active and GetGameTimer() - lastHeartbeat > 3000 then
            pageReady = false
            restoreNative("heartbeat_timeout")
        end
        publishPresentations(false)
        Wait(250)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    running = false
    pcall(Open77.nameplates.stopStream)
    -- Export dispatch is immediate; do not await during teardown because the stopping resource cannot safely
    -- yield. The system resource owns the renderer and survives this resource generation.
    if nativeSuppressed then pcall(Open77.exports.call, "open77_nameplates", "setEnabled", true) end
    active, nativeSuppressed, pageReady, page = false, false, false, nil
end)
