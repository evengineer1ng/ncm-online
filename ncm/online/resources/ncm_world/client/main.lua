-- ncm_world / client — v0.1.0 (M2.1): report generation; watch our own driver view on the state bag.
local Core = NcmCore

local function log(fmt, ...)
    print(("[ncm_world/client] " .. fmt):format(...))
end

local function safe(fn, fallback)
    local ok, v = pcall(fn)
    if ok then return v end
    return fallback
end

local generation = safe(function() return Open77.resource.generation() end, "?")
local luaVersion = safe(function() return Open77.runtime.luaVersion() end, _VERSION)
log("loaded | generation %s | client lua %s | ncm-core %s | modules: %s",
    tostring(generation), tostring(luaVersion), Core.VERSION, table.concat(Core.defined(), ", "))

-- Our public driver view arrives on our own player bag under key "ncm" (server-written).
local okWatch, err = pcall(function()
    Open77.state.onChange("player", "ncm", function(selector, key, value, previous)
        if type(value) == "table" then
            log("driver view: %s #%s rep=%s sr=%s id=%s", tostring(value.display), tostring(value.number or "--"),
                tostring(value.reputation), tostring(value.sr), tostring(value.driverId))
        end
    end)
end)
if not okWatch then log("state.onChange unavailable: %s", tostring(err)) end

-- Dev-console bridge (KB-4): `resource.emit ncm:console car sport` runs /ncm car sport without chat.
AddEventHandler("ncm:console", function(...)
    local args = { ... }
    log("console -> ncm %s", table.concat(args, " "))
    TriggerServerEvent("ncm:cmd", table.unpack(args))
end)

-- /ncm.ride — a chauffeur to the waypoint you set on the map (M7.5a dev/test; the event flow dispatches rides itself).
RegisterCommand("ncm.ride", function()
    local wp = Open77.blips.waypoint()
    if not wp then
        TriggerServerEvent("ncm:ride")
        return
    end
    log("ride requested to waypoint %.1f %.1f %.1f", wp.x, wp.y, wp.z or 0)
    TriggerServerEvent("ncm:ride", wp.x, wp.y, wp.z or 0)
end, false)

-- /ncm.aw <args…> — venue authoring at the map waypoint (server/venue.lua): spot/node/paddock/grid/route add/stop.
RegisterCommand("ncm.aw", function(_, args)
    local wp = Open77.blips.waypoint()
    if not wp then TriggerServerEvent("ncm:auwp", nil, nil, nil, table.unpack(args or {})); return end
    TriggerServerEvent("ncm:auwp", wp.x, wp.y, wp.z or 0, table.unpack(args or {}))
end, false)

-- ---------------------------------------------------------------------------------------------
-- Class performance ceilings (KB-30 / D7 / L77)
--
-- The RB15 collapses from ~360 km/h to ~60 km/h every time; the answer is a class ceiling below the cliff, set
-- at 355 by the owner after measuring it. The governor is CLIENT-LOCAL by design -- it clamps a throttle float
-- inside the client simulating the car -- so each client applies its own, and the server only publishes what the
-- ceilings are. It is balance, not anti-cheat: a modified client can decline, and the server cannot corroborate.
--
-- Both halves of the API pair are probed, never one. A half-present governor would leave us able to set a cap and
-- unable to clear it, which is worse than having no cap at all.
-- ---------------------------------------------------------------------------------------------
local function governorApi()
    local v = Open77 ~= nil and Open77.vehicles or nil
    if type(v) ~= "table" then return nil end
    if type(v.setPerformanceClass) ~= "function" then return nil end
    if type(v.clearPerformanceClass) ~= "function" then return nil end
    return v
end

CreateThread(function()
    local applied = {}       -- record -> signature of the profile in force
    local warned = false
    while true do
        local api = governorApi()
        if not api then
            if not warned then
                warned = true
                log("performance governor not available on this client build; class ceilings cannot be applied (KB-30)")
            end
        else
            local ok, state = pcall(function() return GlobalState.ncmCeilings end)
            local records = (ok and type(state) == "table" and type(state.records) == "table") and state.records or nil
            if records then
                for record, prof in pairs(records) do
                    if type(prof) == "table" then
                        local sig = ("%s/%s/%s"):format(tostring(prof.topSpeedKph), tostring(prof.accelerationScale), tostring(prof.taperKph))
                        if applied[record] ~= sig then
                            local okSet, reason = pcall(api.setPerformanceClass, record, prof)
                            if okSet and reason ~= false then
                                applied[record] = sig
                                log("ceiling applied: %s -> %s km/h (taper %s)", record, tostring(prof.topSpeedKph), tostring(prof.taperKph))
                            else
                                log("ceiling refused for %s: %s", record, tostring(reason))
                            end
                        end
                    end
                end
                -- a record that stopped having a ceiling must have it lifted, or it stays capped forever
                for record in pairs(applied) do
                    if records[record] == nil then
                        pcall(api.clearPerformanceClass, record)
                        applied[record] = nil
                        log("ceiling cleared: %s", record)
                    end
                end
            end
        end
        Wait(10000)
    end
end)

