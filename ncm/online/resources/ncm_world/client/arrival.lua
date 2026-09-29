-- ncm_world / client / arrival -- one arrival on join, not two (KB-207).
--
-- **Why.** NCM cannot choose the platform's spawn point. Every join showed the template save's spawn in the
-- Badlands (2566.9, 112.6) and then, once the server's restore teleported the body ~4 km to where the Driver
-- left (L110), a second loading screen. The owner: "I always spawn somewhere out in the Badlands, same place,
-- then moments later it cuts to loading and loads me in at my persisted location."
--
-- **How.** The moment this client's body exists in the real world (away from the pre-game menu world at the
-- origin), cover the screen and ASK the server where to be. The server's decision is unchanged
-- (`decideLocation` in server/main.lua). With a destination, move there with `travel.teleportAndSettle` --
-- which re-issues the teleport while the floor streams in -- still under black, report the result, then give
-- the image back. Without one, give the image back at once.
--
-- **Failure is bounded.** The fade carries its own client-enforced deadline, this file releases after 40 s
-- regardless, and a failed settle falls back to the old server teleport.
local fadeId, released, asked = nil, false, false

local function log(fmt, ...)
    print(("[ncm_world/client/arrival] " .. fmt):format(...))
end

local function release(why)
    if released then return end
    released = true
    if fadeId then pcall(Open77.screen.fadeIn, fadeId, { durationMs = 600 }) end
    fadeId = nil
    log("screen returned (%s)", tostring(why))
end

local function inRealWorld()
    local ok, st = pcall(Open77.character.state)
    local p = ok and type(st) == "table" and st.position or nil
    return type(p) == "table" and type(p.x) == "number" and (math.abs(p.x) + math.abs(p.y)) > 100
end

CreateThread(function()
    -- Poll quickly: every frame of the platform spawn that shows is the bug. Two minutes covers the slowest join.
    local found = false
    for _ = 1, 1200 do
        if inRealWorld() then found = true; break end
        Wait(100)
    end
    if not found then log("never saw a body in the world; not covering"); return end
    local ok, id, reason = pcall(Open77.screen.fadeOut, { durationMs = 0, timeoutMs = 45000 })
    if ok and id then fadeId = id else log("could not cover the screen (%s); arrival will be visible", tostring((not ok) and id or reason)) end
    asked = true
    TriggerServerEvent("ncm:location.request")
    Wait(40000)
    if not released then release("no answer within 40 s") end
end)

RegisterNetEvent("ncm:location.restore", function(pose)
    if released or not asked then return end
    if type(pose) ~= "table" or type(pose.x) ~= "number" then release("no restore"); return end
    CreateThread(function()
        local state
        local okCall, pending, why = pcall(Open77.travel.teleportAndSettle,
            { x = pose.x, y = pose.y, z = pose.z }, tonumber(pose.heading), { timeoutMs = 15000 })
        if okCall and pending then
            local okAwait, arrival, err = pcall(function() return pending:await() end)
            if okAwait and type(arrival) == "table" then state = tostring(arrival.state)
            else state = "failed:" .. tostring(okAwait and err or arrival) end
        else
            state = "failed:" .. tostring(okCall and why or pending)
        end
        log("arrival at %.1f,%.1f,%.1f: %s", pose.x, pose.y, pose.z, state)
        TriggerServerEvent("ncm:location.arrived", state)
        release("arrived " .. state)
    end)
end)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then release("resource stop") end
end)
