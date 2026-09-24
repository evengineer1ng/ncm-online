-- ncm_world / client / telemetry — the driver's own car, sampled at 5 Hz while racing (L57).
--
-- Samples are positional arrays { t, x, y, z, v, g, og, h } (core telemetry.SAMPLE_FIELDS) sent in batches of five
-- (`ncm:telemetry`). Position comes from the character; speed/gear/on-ground/health from the vehicle snapshot the
-- client may read for the car it sits in (`vehicles.read`). The first time a vehicle snapshot is read, its field
-- names are logged: that is the E4/L57 record of what this build exposes. /ncm.telemetry on|off.
local function log(fmt, ...) print(("[ncm_world/client/telemetry] " .. fmt):format(...)) end

local enabled = true
local batch = {}
local loggedFields = false
local sent, refused = 0, 0
NcmClientTelemetryStatus = function() return ("%s sent=%d"):format(enabled and "on" or "off", sent) end

local function serverNow()
    -- the race HUD keeps the synced clock; fall back to the last published serverNow (IDEA-112: the map carries
    -- one `serverNow` for all live sessions, so this no longer needs to know which session it is in)
    if NcmClientServerNow then return NcmClientServerNow() end
    local ss = GlobalState and GlobalState.ncmSessions or nil
    return (type(ss) == "table" and tonumber(ss.serverNow)) or 0
end

local function myVehicle()
    local ok, seat = pcall(Open77.vehicles.getPlayerSeat)
    if not ok or type(seat) ~= "table" then
        local ok2, s2 = pcall(Open77.players.getVehicleSeat)
        if ok2 and type(s2) == "table" then seat = s2 else return nil end
    end
    local vid = seat.vehicleId or seat.vehicle or seat.id
    if not vid then return nil end
    local okV, v = pcall(Open77.vehicles.get, vid)
    if not okV or type(v) ~= "table" then return nil end
    if not loggedFields then
        loggedFields = true
        local keys = {}
        for k, val in pairs(v) do if type(val) ~= "table" then keys[#keys + 1] = k .. "=" .. tostring(val) end end
        table.sort(keys)
        log("telemetry fields: %s", table.concat(keys, " "))
    end
    return v
end

local function sample()
    local ok, x, y, z = pcall(Open77.character.position)
    if not ok or type(x) ~= "number" then return nil end
    local v = myVehicle()
    local speed = v and tonumber(v.speed) or 0
    if v and not v.speed and v.speedKph then speed = v.speedKph / 3.6 end
    local gear = v and tonumber(v.gear) or 0
    local onGround = v and v.onGround
    if onGround == nil then onGround = true end
    local health = v and tonumber(v.health) or 1
    if health > 1 then health = health / 100 end
    return { serverNow(), x, y, z or 0, speed, gear, onGround and true or false, health }
end

CreateThread(function()
    Wait(3000)
    while true do
        -- IDEA-112: only ever the view the HUD picked -- telemetry belongs to the session I am actually in.
        local g = NcmClientView or nil
        local racing = enabled and NcmClientRaceActive and type(g) == "table" and (g.phase == "countdown" or g.phase == "running" or g.phase == "finishing" or g.phase == "open")
        if racing then
            local s = sample()
            if s then batch[#batch + 1] = s end
            if #batch >= 5 then
                TriggerServerEvent("ncm:telemetry", g.sessionId, batch)
                sent = sent + #batch
                batch = {}
            end
            Wait(200)
        else
            if #batch > 0 and type(g) == "table" and g.sessionId then TriggerServerEvent("ncm:telemetry", g.sessionId, batch) end
            batch = {}
            Wait(1000)
        end
    end
end)

RegisterCommand("ncm.telemetry", function(_, args)
    local a = args and args[1] and tostring(args[1]):lower() or nil
    if a == "on" then enabled = true elseif a == "off" then enabled = false end
    log("telemetry %s · sent %d sample(s)", enabled and "on" or "off", sent)
end, false)
