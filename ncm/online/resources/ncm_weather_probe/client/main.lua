local function report(captureId, label)
    CreateThread(function()
        local promise, callReason = Open77.exports.call("open77_weather", "getState")
        if not promise then
            TriggerServerEvent("ncm:wxprobe:observation", captureId, label, nil, callReason)
            return
        end
        local ok, state = pcall(function() return promise:await() end)
        if not ok then
            TriggerServerEvent("ncm:wxprobe:observation", captureId, label, nil, state)
            return
        end
        TriggerServerEvent("ncm:wxprobe:observation", captureId, label, state, nil)
    end)
end

RegisterNetEvent("ncm:wxprobe:capture", report)
