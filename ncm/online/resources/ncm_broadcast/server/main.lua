-- ncm_broadcast / server -- the toggles' confirmation, and the projection calibration (L235).
--
-- The feeds themselves come from their owners: ncm_paddock sends `ncm:broadcast.paddock` to players near a race;
-- multiplayer sessions reach the client through ncm_league's own `ncm:session` / GlobalState.ncmSessions.
local function log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    print("[ncm_broadcast] " .. (ok and line or tostring(fmt)))
end

RegisterNetEvent("ncm:broadcast.toast", function(m)
    local pid = source
    if type(m) ~= "table" or not pid then return end
    local msg = tostring(m.message or ""):sub(1, 160)
    pcall(Open77.notifications.send, pid, { type = "info", title = "NCM BROADCAST", message = msg, icon = "NCM", durationMs = 4000 })
end)

-- ncm.broadcast.view <range> <scale> <projX> <projY> [lift] [towerX] [towerY] -- server console; every client's plugin
-- takes it at once. For correcting the name projection from the plugin log's `calibration:` line without a rebuild.
local current = nil
RegisterCommand("ncm.broadcast.view", function(src, args)
    if (tonumber(src) or 0) ~= 0 then return end   -- server console only
    local keys = { "range", "scale", "projX", "projY", "lift", "towerX", "towerY" }
    local v = { cmd = "view" }
    for i, k in ipairs(keys) do if tonumber(args[i]) then v[k] = tonumber(args[i]) end end
    current = v
    TriggerClientEvent("ncm:broadcast.view", -1, v)
    log("view -> range=%s scale=%s projX=%s projY=%s lift=%s tower=%s,%s", tostring(v.range), tostring(v.scale), tostring(v.projX),
        tostring(v.projY), tostring(v.lift), tostring(v.towerX), tostring(v.towerY))
end)

RegisterNetEvent("ncm:broadcast.hello", function()
    if current and source then TriggerClientEvent("ncm:broadcast.view", source, current) end
end)
