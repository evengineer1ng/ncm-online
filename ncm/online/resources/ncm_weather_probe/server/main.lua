local function log(fmt, ...)
    print(("[ncm_weather_probe] " .. fmt):format(...))
end

local function integer(value)
    local n = tonumber(value)
    if not n or n ~= math.floor(n) or n < 0 then return nil end
    return n
end

local function compact(state)
    if type(state) ~= "table" then return "state=nil" end
    return table.concat({
        "scope=" .. tostring(state.scope),
        "bucket=" .. tostring(state.bucket),
        "epoch=" .. tostring(state.authorityEpoch),
        "rev=" .. tostring(state.revision),
        "wxrev=" .. tostring(state.weatherRevision),
        "weather=" .. tostring(state.weather),
        "preset=" .. tostring(state.weatherPreset),
        "transition_ms=" .. tostring(state.weatherTransitionRemainingMs),
        "next_ms=" .. tostring(state.nextWeatherInMs),
        "random=" .. tostring(state.randomWeather),
        "seconds=" .. tostring(math.floor(tonumber(state.secondsOfDay) or -1)),
    }, " ")
end

local function canonical(bucket)
    local ok, state, reason = pcall(Open77.environment.getState, bucket)
    if not ok then return nil, tostring(state) end
    if not state then return nil, tostring(reason) end
    return state
end

local captureSequence = 0

RegisterNetEvent("ncm:wxprobe:observation", function(captureId, label, state, errorReason)
    local playerId = tonumber(source) or 0
    local bucket = Open77.routingBuckets.getPlayer(playerId)
    local serverState, serverReason = canonical(bucket)
    log("OBS capture=%s label=%s player=%d player_bucket=%s client={%s} server={%s} client_error=%s server_error=%s",
        tostring(captureId), tostring(label), playerId, tostring(bucket), compact(state), compact(serverState),
        tostring(errorReason), tostring(serverReason))
end)

RegisterCommand("ncm.wx.capture", function(source, args)
    captureSequence = captureSequence + 1
    local label = table.concat(args or {}, " ")
    if label == "" then label = "capture-" .. tostring(captureSequence) end
    local state, reason = canonical(nil)
    log("CAPTURE id=%d label=%s default={%s} error=%s", captureSequence, label, compact(state), tostring(reason))
    TriggerClientEvent("ncm:wxprobe:capture", -1, captureSequence, label)
end, false)

RegisterCommand("ncm.wx.state", function(source, args)
    local bucket = args and args[1] and integer(args[1]) or nil
    local state, reason = canonical(bucket)
    log("STATE requested_bucket=%s canonical={%s} error=%s", tostring(bucket), compact(state), tostring(reason))
end, false)

RegisterCommand("ncm.wx.set", function(source, args)
    local weather = args and args[1]
    local transition = tonumber(args and args[2]) or 20
    local bucket = args and args[3] and integer(args[3]) or nil
    if type(weather) ~= "string" or weather == "" then
        return log("SET rejected usage=ncm.wx.set <preset> [transition_seconds] [bucket]")
    end
    local ok, state, reason = pcall(Open77.environment.setWeather, weather, transition, bucket)
    log("SET weather=%s transition=%s bucket=%s ok=%s state={%s} error=%s",
        weather, tostring(transition), tostring(bucket), tostring(ok), compact(ok and state or nil), tostring(ok and reason or state))
end, false)

RegisterCommand("ncm.wx.random", function(source, args)
    local enabled = args and tostring(args[1]):lower() == "on"
    local bucket = args and args[2] and integer(args[2]) or nil
    local ok, state, reason = pcall(Open77.environment.setWeatherFrozen, not enabled, bucket)
    log("RANDOM enabled=%s bucket=%s ok=%s state={%s} error=%s",
        tostring(enabled), tostring(bucket), tostring(ok), compact(ok and state or nil), tostring(ok and reason or state))
end, false)

RegisterCommand("ncm.wx.clear", function(source, args)
    local bucket = args and args[1] and integer(args[1]) or nil
    if bucket == nil then return log("CLEAR rejected usage=ncm.wx.clear <bucket>") end
    local ok, state, reason = pcall(Open77.environment.clearBucket, bucket)
    log("CLEAR bucket=%s ok=%s state={%s} error=%s",
        tostring(bucket), tostring(ok), compact(ok and state or nil), tostring(ok and reason or state))
end, false)

RegisterCommand("ncm.wx.move", function(source, args)
    local playerId = args and integer(args[1])
    local bucket = args and integer(args[2])
    if playerId == nil or bucket == nil then return log("MOVE rejected usage=ncm.wx.move <player_id> <bucket>") end
    local ok, moved, reason = pcall(Open77.routingBuckets.setPlayer, playerId, bucket)
    log("MOVE player=%d bucket=%d ok=%s moved=%s error=%s", playerId, bucket, tostring(ok), tostring(moved), tostring(ok and reason or moved))
end, false)

AddEventHandler("onEnvironmentChanged", function(state)
    log("CHANGED reason=%s canonical={%s}", tostring(state and state.reason), compact(state))
end)

log("ready; commands: ncm.wx.state/capture/set/random/clear/move")
