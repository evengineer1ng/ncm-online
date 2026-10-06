-- ncm_world / client / engineering -- L324: the installed components of the Machine you are driving, expressed.
--
-- The server says what is installed where, facing which way, and which controls command it (`ncm:engineering`). This
-- file reads those controls, runs the devices through core `engineering.installation` (throttle lag, discharges,
-- heat, the tank), turns the Machine-frame output into WORLD space with the car's own live axes
-- (`Open77.character.frame` -- forward/right/up including pitch and roll), and hands the Carrier two things over its
-- existing Machine channel:
--
--   * a sustained-force LEASE (`ncm:machine.wrench`, ttl 150 ms, refreshed while any device pushes, heartbeat 250 ms
--     while the Machine has installed devices at all -- which also tells the Carrier to ignore NCM Thrust's legacy
--     lift lever for this Machine: one owner for the car's propulsion);
--   * one PULSE per discharge (world force + duration, timed by the Carrier in physics time, so the impulse is exact).
--
-- Nothing is stabilised. A propulsor pointing where the car points drives the car where it points, tumbling included.
--
-- EXPRESSION LOSSES (said in every telemetry line): the Carrier applies force at the centre of mass -- a mount's
-- offset makes torque in the model (`step().torque`) that the host does not apply; a pulse's direction is frozen at
-- the moment of discharge; the engine caps vertical speed near 99.7 m/s (KB-342).
local Core = NcmCore
local Install = Core.get("engineering.installation")
local Controls = Core.get("engineering.controls")

local function log(fmt, ...) print(("[ncm_world/client/engineering] " .. fmt):format(...)) end

local SEND_MS, LEASE_TTL_MS, HEARTBEAT_MS, REPORT_MS = 33, 150, 250, 1000
local LOSS = "torque from off-centre mounts not applied (force at CoM); pulse direction fixed at discharge; vertical speed capped ~99.7 m/s (KB-342)"

local E = nil              -- { assetId, vehicleId, devices, bindings, state, ctl, fuelKg, controls }
local boundAsset, boundVehicle = nil, nil
local requestedAt = {}     -- assetId -> ms of the last request
local pulseSeq = 0

local function ms() return GetGameTimer() end

--- The DEVELOPMENT heat waiver (owner, 2026-10-06; set from `ncm:deep.config`): no installed part ever heats up.
function NcmClientCoolAll(state)
    for _, st in pairs(state and state.dev or {}) do st.heatK, st.hot = 0, false end
end

local function apply(p)
    local devices, refused = Install.resolve(p.items or {}, p.vehicleKey)
    local fuelMl = p.fuel and tonumber(p.fuel.ml)
    E = {
        assetId = p.assetId, vehicleKey = p.vehicleKey, devices = devices, bindings = p.bindings or {}, state = Install.newState(devices),
        ctl = Controls.newState(), fuelKg = fuelMl and (fuelMl / 1000 * Install.FUEL_KG_PER_L) or 0, fuelKnown = fuelMl ~= nil,
        controls = Controls.controls(p.bindings or {}), report = { kg = 0, pulses = 0, since = ms() }, lastSend = 0, lastF = nil,
    }
    local parts = {}
    for _, d in ipairs(devices) do parts[#parts + 1] = ("%s@%s/%s"):format(d.code, d.mountId:gsub("^mount%.", ""), d.facing) end
    for _, r in ipairs(refused) do parts[#parts + 1] = "REFUSED " .. tostring(r.reason) end
    local b = {}
    for _, x in ipairs(E.bindings) do b[#b + 1] = ("%s:%s->..%s.%s"):format(x.control, x.gesture, tostring(x.componentId):sub(-6), x.command) end
    log("Machine ..%s: %s | controls %s | fuel %s kg", tostring(p.assetId):sub(-6), #parts > 0 and table.concat(parts, ", ") or "no add-ons",
        #b > 0 and table.concat(b, ", ") or "none", E.fuelKnown and ("%.1f"):format(E.fuelKg) or "?")
end

--- L326: client/deep.lua reads the same devices, bindings, runtime state and tank (never a copy: one Machine).
NcmClientEngineering = { get = function() return E end, bound = function() return boundAsset, boundVehicle end }

RegisterNetEvent("ncm:engineering", function(p)
    if type(p) ~= "table" or p.assetId ~= boundAsset then return end
    apply(p)
end)

-- KB-345b: this build REQUIRES the handler argument (a bare RegisterNetEvent failed activation and refused every join).
RegisterNetEvent("ncm:fuel", function(f)
    if E and type(f) == "table" and f.assetId == E.assetId and tonumber(f.ml) then
        E.fuelKg, E.fuelKnown = tonumber(f.ml) / 1000 * Install.FUEL_KG_PER_L, true
    end
end)

--- What the server says we are bound to (the same bag the Carrier bridge reads).
local function readBinding()
    local ok, bag = pcall(Open77.state.localPlayer)
    local h = ok and type(bag) == "table" and bag.ncmHandling or nil
    if type(h) == "table" and h.bound and type(h.assetId) == "string" and h.assetId ~= "" then return h.assetId, h.vehicleId end
    return nil, nil
end

local function seatedIn(vid)
    local ok, seat = pcall(Open77.vehicles.getPlayerSeat)
    if not ok or type(seat) ~= "table" then return false end
    return tostring(seat.vehicleId or seat.vehicle or seat.id) == tostring(vid)
end

local function down(control)
    local okC, captured = pcall(Open77.input.isCaptured)
    if okC and captured == true then return false end    -- typing in chat or a menu is not driving
    local ok, d = pcall(Open77.input.isDown, control)
    return ok and d == true
end

-- Owner, 2026-10-06: the clean architecture is the installed one -- tap = the hop (an impulse actuator), hold = forward
-- (a propulsor). Once a Machine carries components they own its propulsion, so NCM Thrust's legacy hop is parked.
local function lease(fx, fy, fz)
    if not NcmClientMachineWrench then return false end
    return NcmClientMachineWrench({ v = 1, assetId = E.assetId, vehicleId = tostring(boundVehicle), fx = fx, fy = fy, fz = fz,
        ttlMs = LEASE_TTL_MS, supersedeLift = true })
end

local function pulse(w, durationMs)
    if not NcmClientMachineWrench then return false end
    pulseSeq = pulseSeq + 1
    return NcmClientMachineWrench({ v = 1, assetId = E.assetId, vehicleId = tostring(boundVehicle), fx = 0, fy = 0, fz = 0,
        ttlMs = LEASE_TTL_MS, supersedeLift = true, pulse = { seq = pulseSeq, fx = w[1], fy = w[2], fz = w[3], ms = durationMs } })
end

-- binding: who we are bound to, and asking the server what that Machine carries
CreateThread(function()
    Wait(10000)
    while true do
        local aid, vid = readBinding()
        if aid ~= boundAsset then
            boundAsset, boundVehicle = aid, vid
            if E and E.assetId ~= aid then E = nil end
        end
        boundVehicle = vid
        if aid and not E and ms() - (requestedAt[aid] or -1e9) > 5000 then
            requestedAt[aid] = ms()
            TriggerServerEvent("ncm:engineering.request", aid)
        end
        Wait(500)
    end
end)

-- the devices, every frame while they exist and we drive them
CreateThread(function()
    local last = ms()
    while true do
        -- L326: while NCM's universe owns the Machine (client/deep.lua) the car is frozen in REDengine: no wrench, no burn here.
        if NcmClientDeepActive or not (E and #E.devices > 0 and boundVehicle and seatedIn(boundVehicle)) then
            last = ms()
            Wait(250)
        else
            Wait(0)
            local t = ms()
            local dt = math.min(0.1, math.max(0.001, (t - last) / 1000))
            last = t
            local pressed = {}
            for _, c in ipairs(E.controls) do pressed[c] = down(c) end
            local commands = Controls.step(E.ctl, E.bindings, E.devices, pressed, t)
            -- `/ncm.eng.devfuel` (client/deep.lua, development only): nothing burned, nothing reported
            if NcmClientDevHeat then NcmClientCoolAll(E.state) end
            local r = Install.step(E.devices, E.state, commands, dt, NcmClientDevFuel and 1e9 or E.fuelKg)
            if not NcmClientDevFuel then
                E.fuelKg = math.max(0, E.fuelKg - r.propellantKg)
                E.report.kg = E.report.kg + r.propellantKg
                E.report.pulses = E.report.pulses + r.pulses
            end

            local okF, frame = pcall(Open77.character.frame, { vehicleId = boundVehicle })
            frame = okF and type(frame) == "table" and frame or nil
            -- sustained devices only: a pulse is handed over whole, below
            local sustained = { 0, 0, 0 }
            local hot = false
            for _, d in ipairs(E.devices) do
                local o = r.out[d.componentId]
                if o and o.hot then hot = true end
                if o and d.kind ~= "pulse_reaction" and o.thrustN > 0 then
                    sustained[1] = sustained[1] + d.axis[1] * o.thrustN
                    sustained[2] = sustained[2] + d.axis[2] * o.thrustN
                    sustained[3] = sustained[3] + d.axis[3] * o.thrustN
                end
                if d.kind == "pulse_reaction" and (E.state.dev[d.componentId] or {}).sinceS == 0 and frame then   -- fired this step
                    local w = Install.toWorld({ d.axis[1] * d.perf.forceN, d.axis[2] * d.perf.forceN, d.axis[3] * d.perf.forceN }, frame)
                    if w then pulse(w, math.floor(d.perf.pulseS * 1000 + 0.5)) end
                end
            end
            local w = frame and Install.toWorld(sustained, frame) or { 0, 0, 0 }
            local mag = math.sqrt(w[1] ^ 2 + w[2] ^ 2 + w[3] ^ 2)
            local changed = (E.lastF == nil) or math.abs(mag - E.lastF) > 50
            if (mag > 0 and (t - E.lastSend >= SEND_MS)) or (changed and t - E.lastSend >= SEND_MS) or (t - E.lastSend >= HEARTBEAT_MS) then
                lease(w[1], w[2], w[3])
                E.lastSend, E.lastF = t, mag
            end
            E.lastW, E.lastFrame, E.hot = w, frame, hot

            if t - E.report.since >= REPORT_MS then
                local active = E.report.kg > 0 or mag > 0
                if active then
                    local okV, v = pcall(Open77.vehicles.get, boundVehicle)
                    local pos = okV and type(v) == "table" and v.position or {}
                    local parts = {}
                    for _, d in ipairs(E.devices) do
                        local o = E.state.dev[d.componentId] or {}
                        parts[#parts + 1] = d.kind == "pulse_reaction" and ("%s@%s/%s"):format(d.code, d.mountId:gsub("^mount%.", ""), d.facing)
                            or ("%s@%s/%s thr %.2f %.1f kN %.0f K%s"):format(d.code, d.mountId:gsub("^mount%.", ""), d.facing, o.throttle or 0,
                                ((r.out[d.componentId] or {}).thrustN or 0) / 1000, o.heatK or 0, o.hot and " HOT" or "")
                    end
                    local f = frame or {}
                    local fw, up = f.forward or {}, f.up or {}
                    TriggerServerEvent("ncm:engineering.burn", { assetId = E.assetId, kg = E.report.kg, dtS = (t - E.report.since) / 1000, pulses = E.report.pulses,
                        t = { devices = table.concat(parts, " | "), fx = w[1], fy = w[2], fz = w[3], f = mag,
                            fwx = fw.x, fwy = fw.y, fwz = fw.z, upx = up.x, upy = up.y, upz = up.z,
                            speed = okV and type(v) == "table" and v.speed or 0, z = pos.z or 0, hot = hot, loss = LOSS } })
                end
                E.report = { kg = 0, pulses = 0, since = t }
            end
        end
    end
end)

--- `/ncm.eng.hud` -- what the devices are doing, in chat, once.
RegisterCommand("ncm.eng.status", function()
    if not E then print("[ENG] no installed devices on the Machine you are bound to"); return end
    for _, d in ipairs(E.devices) do
        local o = E.state.dev[d.componentId] or {}
        print(("[ENG] %s %s on %s facing %s: throttle %.2f heat +%.0f K%s"):format(d.code, d.kind, d.mountId, d.facing, o.throttle or 0, o.heatK or 0, o.hot and " HOT" or ""))
    end
    print(("[ENG] fuel %.1f kg; last world force (%.0f, %.0f, %.0f) N"):format(E.fuelKg, (E.lastW or {})[1] or 0, (E.lastW or {})[2] or 0, (E.lastW or {})[3] or 0))
end, false)
