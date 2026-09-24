-- ncm_world / server / presentation — authoritative public Driver Card projection (L130).
--
-- The player bag is bucket-public by platform contract. Only the compact card projection is written here.
-- Earned accomplishments are read to derive entitlement but are never copied into the bag.
NcmPresentation = {}

local Core = NcmCore
local Presentation = Core.get("driver.presentation")
local Json = Core.get("vocabulary.json")
local preview = {}       -- Development-only, in-memory, cleared on reload/disconnect.
local current = {}       -- playerId -> last public projection (for diagnostics only).

local function log(fmt, ...)
    print(("[ncm_world/presentation] " .. fmt):format(...))
end

local function encode(value)
    if json and json.encode then return json.encode(value) end
    return Json.encode(value)
end

local function decode(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" or value == "" then return {} end
    if json and json.decode then
        local ok, decoded = pcall(json.decode, value)
        if ok and type(decoded) == "table" then return decoded end
    end
    local decoded = Json.decode(value)
    return type(decoded) == "table" and decoded or {}
end

local function environment()
    local ok, identity = pcall(function() return GlobalState.ncmIdentity end)
    if ok and type(identity) == "table" and type(identity.environment) == "string" then
        return identity.environment
    end
    return "unknown"
end

local function tell(playerId, text)
    pcall(Open77.chat.send, tonumber(playerId) or 0, "[NCM] " .. tostring(text))
end

local function loadSelection(profile)
    local fallback = { bannerId = Presentation.DEFAULT_BANNER_ID, displayedBadgeIds = {} }
    if not MySQL.isReady() then return fallback, {}, "database_not_ready" end

    local ok, row = pcall(MySQL.single.await,
        "SELECT banner_id, displayed_badges_json FROM driver_presentation WHERE ncm_driver_id = ? AND server_id = ?",
        { profile.ncmDriverId, profile.serverId })
    if not ok then return fallback, {}, "presentation_schema_not_ready" end

    local kinds = {}
    local okAcc, rows = pcall(MySQL.query.await,
        "SELECT kind FROM accomplishment WHERE ncm_driver_id = ? AND server_id = ?",
        { profile.ncmDriverId, profile.serverId })
    if okAcc and type(rows) == "table" then
        for _, acc in ipairs(rows) do if type(acc.kind) == "string" then kinds[#kinds + 1] = acc.kind end end
    end

    if not row then
        pcall(MySQL.update.await,
            "INSERT IGNORE INTO driver_presentation (ncm_driver_id, server_id, banner_id, displayed_badges_json) VALUES (?, ?, ?, ?)",
            { profile.ncmDriverId, profile.serverId, Presentation.DEFAULT_BANNER_ID, encode({}) })
        return fallback, kinds
    end
    return {
        bannerId = row.banner_id or Presentation.DEFAULT_BANNER_ID,
        displayedBadgeIds = decode(row.displayed_badges_json),
    }, kinds
end

local function writeBag(playerId, projection)
    local ok, result, reason = pcall(function()
        return Open77.state.player(playerId):set("ncmPresentation", projection)
    end)
    if not ok then return false, result end
    if result ~= true then return false, reason end
    current[playerId] = projection
    return true
end

--- Rebuild the intentionally public projection from canonical selection + entitlement.
function NcmPresentation.publish(playerId, profile)
    local id = tonumber(playerId) or 0
    profile = profile or (NcmIdentity and NcmIdentity.get and NcmIdentity.get(id))
    if id <= 0 or not profile then return false, "no_profile" end

    local selection, kinds, loadReason = loadSelection(profile)
    local opts = nil
    if preview[id] then
        selection = preview[id]
        opts = { development = true }
    end
    local entitled = Presentation.entitlements(kinds, opts)
    local projection = Presentation.publicProjection(selection, entitled)
    local ok, reason = writeBag(id, projection)
    if not ok then
        log("publish failed player=%d: %s", id, tostring(reason))
        return false, reason
    end
    log("published player=%d banner=%s badges=%d fingerprint=%s%s", id, projection.bannerId,
        #projection.displayedBadgeIds, projection.fingerprint.sampleState,
        loadReason and (" fallback=" .. loadReason) or "")
    return true, projection
end

local function saveSelection(playerId, requested)
    local id = tonumber(playerId) or 0
    local profile = NcmIdentity and NcmIdentity.get and NcmIdentity.get(id)
    if not profile then return false, "no_profile" end
    if not MySQL.isReady() then return false, "database_not_ready" end

    local _, kinds, loadReason = loadSelection(profile)
    if loadReason == "presentation_schema_not_ready" then return false, loadReason end
    local entitled = Presentation.entitlements(kinds)
    local safe, reason = Presentation.validateSelection(requested, entitled)
    if not safe then return false, reason end

    local ok, err = pcall(MySQL.update.await, [[
        INSERT INTO driver_presentation (ncm_driver_id, server_id, banner_id, displayed_badges_json)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE banner_id = VALUES(banner_id), displayed_badges_json = VALUES(displayed_badges_json)]],
        { profile.ncmDriverId, profile.serverId, safe.bannerId, encode(safe.displayedBadgeIds) })
    if not ok then return false, tostring(err) end
    preview[id] = nil
    return NcmPresentation.publish(id, profile)
end

-- Player-facing minimal selection command. It does not award anything.
--   /ncm.card select ncm_default first_finish first_win
RegisterCommand("ncm.card", function(source, args)
    local id = tonumber(source) or 0
    if id <= 0 then return end
    args = type(args) == "table" and args or {}
    if tostring(args[1] or ""):lower() ~= "select" then
        local p = current[id]
        tell(id, p and ("Driver Card: " .. p.bannerId .. " · " .. #p.displayedBadgeIds .. "/3 badges · Fingerprint unavailable")
            or "Driver Card is not ready yet.")
        tell(id, "Select: /ncm.card select ncm_default [earned badge ids]")
        return
    end
    local badges = {}
    for i = 3, #args do badges[#badges + 1] = tostring(args[i]) end
    CreateThread(function()
        local ok, reason = saveSelection(id, { bannerId = tostring(args[2] or Presentation.DEFAULT_BANNER_ID), displayedBadgeIds = badges })
        if ok then tell(id, "Driver Card presentation saved.")
        else tell(id, "Driver Card selection refused: " .. tostring(reason)) end
    end)
end, false)

-- Console-only, Development-only fixture. It changes no entitlement/history and survives no reload.
--   ncm.card.preview <playerId> <0|1|2|3|clear> [default|selected]
RegisterCommand("ncm.card.preview", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    if environment() ~= "development" then log("preview refused outside Development"); return end
    local id = tonumber(args and args[1])
    local count = args and tostring(args[2] or "") or ""
    if not id or (count ~= "clear" and (not tonumber(count) or tonumber(count) < 0 or tonumber(count) > 3)) then
        log("usage: ncm.card.preview <playerId> <0|1|2|3|clear> [default|selected]")
        return
    end
    if count == "clear" then
        preview[id] = nil
    else
        local badges = {}
        for i = 1, math.floor(tonumber(count)) do badges[i] = "dev_slot_" .. tostring(i) end
        local selectedBanner = tostring(args[3] or "selected") == "default"
            and Presentation.DEFAULT_BANNER_ID or "ncm_development"
        preview[id] = { bannerId = selectedBanner, displayedBadgeIds = badges }
    end
    local ok, reason = NcmPresentation.publish(id)
    log("preview player=%d badges=%s -> %s %s", id, count, tostring(ok), tostring(reason or ""))
end, false)

AddEventHandler("onPlayerDisconnected", function(playerId)
    local id = tonumber(playerId) or 0
    preview[id], current[id] = nil, nil
end)
