-- ncm_world / client / altitude -- S0, the altitude expedition (L316; doc 51 §S0). Read-only instrument; dev only.
--
-- How high does Night City go before it stops being Night City? `/ncm.altlog` (toggle) logs, once a second, where the
-- character is, whether it sits in a car and how fast that car moves; every ten seconds, the weather state the
-- platform reports. Each line is also sent to the server (`ncm:altlog`), which logs it beside the position the
-- SERVER holds for the same player -- the replication half of the question. Climb with NCM Thrust in hold mode, or
-- be lifted on foot with the server's `ncm.lift <pid> <metres>`. Nothing here changes the world.
local function log(fmt, ...) print(("[ncm_world/client/altitude] " .. fmt):format(...)) end

local on = false
local samples = 0
local peakZ = nil

local function scalars(t)
    if type(t) ~= "table" then return tostring(t) end
    local keys = {}
    for k, v in pairs(t) do if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = k .. "=" .. tostring(v) end end
    table.sort(keys)
    return table.concat(keys, " ")
end

local function weather()
    local promise, reason = Open77.exports.call("open77_weather", "getState")
    if not promise then return "unavailable (" .. tostring(reason) .. ")" end
    local ok, state = pcall(function() return promise:await() end)
    return ok and scalars(state) or ("error " .. tostring(state))
end

RegisterCommand("ncm.altlog", function(_, args)
    local a = args and args[1]
    if a == "on" then on = true elseif a == "off" then on = false else on = not on end
    if on then samples, peakZ = 0, nil end
    log("altlog %s%s", on and "ON" or "OFF", (not on and peakZ) and (" -- peak z %.1f over %d sample(s)"):format(peakZ, samples) or "")
end, false)

CreateThread(function()
    while true do
        if not on then
            Wait(500)
        else
            Wait(1000)
            local okP, x, y, z = pcall(Open77.character.position)
            if okP and type(x) == "table" then x, y, z = x.x, x.y, x.z end
            if okP and tonumber(z) then
                samples = samples + 1
                if not peakZ or z > peakZ then peakZ = z end
                local own = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
                local speed = own and tonumber(own.speed) or nil
                local ground = own and own.onGround
                local wx = (samples % 10 == 1) and weather() or nil
                log("alt z=%.1f (peak %.1f) at %.1f,%.1f | %s%s%s", z, peakZ, x, y,
                    own and "in car" or "on foot",
                    speed and (" %.1f m/s"):format(speed) or "",
                    ground ~= nil and (" onGround=" .. tostring(ground)) or "")
                if wx then log("alt weather: %s", wx) end
                TriggerServerEvent("ncm:altlog", x, y, z, speed or -1, own and true or false, wx)
            else
                log("alt: no character position (%s)", tostring(x))
            end
        end
    end
end)
