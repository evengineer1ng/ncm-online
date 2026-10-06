-- ncm_ls_space / client / thrust: the DEV LIFT INSTRUMENT (L319; doc 53; L321: an instrument, not a technology).
-- Active only in `/ncm.machine instrument` mode; an NCM machine (client/machine.lua) is the default since 0.3.0.
--
-- LIFT. The NCM lift rig (`engineering.fixtures.f0_lift_rig`, a thrust LOAD of 36,100 N along the body's +Z) becomes a
-- thrust-to-weight through `engineering.actuate.lift(thrust, mass)` with the car's real handling mass, clamped by the
-- adapter (`maxTwr`). While the lift is held, the car's velocity gains r * g * dt along the car's OWN up axis every
-- frame: F = m a, integrated by us; GTA keeps gravity, contacts and collisions. Tilt the car and the lift tilts too.
--
-- ATTITUDE. Torque from mounting points (L314 IDEA-1019), which REDengine could not give us and GTA can: equal and
-- opposite forces at +/- `attitudeArm` along the car's axes through `APPLY_FORCE_TO_ENTITY` -- a pure couple, so pitch
-- and roll without net push. Only while airborne.
--
-- CONTROLS. Pad: TRIANGLE / Y = lift (IDEA-1047; the exit control is disabled while the lift is armed, whatever the
-- input device, so Y never throws you out mid-air -- `/ncm.thrust off` to get out with Y or F again). Keyboard: H (rebindable: FiveM Settings > Key
-- Bindings > FiveM > "NCM lift"). Left stick / WASD pitch and roll while airborne.
--
-- Every press is a measured hop, as F0 was: vz at the start, peak, rise, against `engineering.actuate.hopPrediction`.
local Core = NcmCore
local Act = Core.get("engineering.actuate")
local Fix = Core.get("engineering.fixtures")
local C = NcmLsConfig

NcmLsThrust = { armed = true, keyHeld = false, twr = 0, liftOn = false }
local T = NcmLsThrust

local rigN = Act.liftN(Fix.DESIGNS[C.rig])
local G = 9.81

RegisterCommand("+ncmlift", function() T.keyHeld = true end, false)
RegisterCommand("-ncmlift", function() T.keyHeld = false end, false)
RegisterKeyMapping("+ncmlift", "NCM lift (thrust)", "keyboard", "H")

RegisterCommand("ncm.thrust", function(_, args)
    local a = args[1]
    if a == "off" then T.armed = false elseif a == "on" then T.armed = true end
    print(("[ncm_ls_space] thrust %s; rig %.0f N; clamp twr %.1f"):format(T.armed and "ARMED" or "off", rigN, C.maxTwr))
end, false)

local function report(fmt, ...)
    local line = fmt:format(...)
    print("[ncm_ls_space] " .. line)
    TriggerServerEvent("ncm:ls:report", line)
end

local hop = nil          -- the burn being measured
local lastVeh = 0

local function upVector(veh)
    local _, _, up = GetEntityMatrix(veh)   -- forward, right, up, position
    return up
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local instrument = not NcmLsMachine or NcmLsMachine.mode == "instrument"
        if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped or not instrument then
            -- L321: the lift rig is an INSTRUMENT; with an NCM machine fitted, client/machine.lua drives the car
            T.liftOn, T.twr, lastVeh = false, 0, 0
            Wait(250)
        else
            Wait(0)
            if veh ~= lastVeh then
                lastVeh = veh
                SetEntityMaxSpeed(veh, C.maxSpeed)
                local mass = GetVehicleHandlingFloat(veh, "CHandlingData", "fMass")
                local l = Act.lift(rigN, mass)
                report("in a car: mass %.0f kg, lift rig %.0f N -> twr %.2f (expressed %.2f, clamp %.1f); max speed set %.0f",
                    mass, rigN, l.stateTwr, math.min(l.expressedTwr, C.maxTwr), C.maxTwr, C.maxSpeed)
            end
            -- Y/TRIANGLE is the lift whenever the lift is armed, WHATEVER the last input device: through a game stream
            -- (Apollo/Sunshine) the virtual mouse jitters, IsUsingKeyboard() reads true, and the old pad-only guard let
            -- TRIANGLE exit the car mid-air (owner, 2026-10-05: "clicked triangle to go higher and jumped out of car").
            -- Exit with `/ncm.thrust off` (then Y/F exits as usual).
            if T.armed then DisableControlAction(0, 75, true) end
            local padLift = T.armed and IsDisabledControlPressed(0, 75)
            local want = T.armed and (T.keyHeld or padLift) and NetworkHasControlOfEntity(veh)
            local dt = GetFrameTime()
            local mass = GetVehicleHandlingFloat(veh, "CHandlingData", "fMass")
            local r = math.min(Act.lift(rigN, mass).expressedTwr, C.maxTwr)
            T.twr = want and r or 0
            local vel = GetEntityVelocity(veh)
            if want then
                -- inside Snowglobe the frame (client/frame.lua) adds the lift to the UNIVERSE velocity; here only below it
                if not (NcmLsFrame and NcmLsFrame.active) then
                    local up = upVector(veh)
                    local a = r * G * dt
                    SetEntityVelocity(veh, vel.x + up.x * a, vel.y + up.y * a, vel.z + up.z * a)
                end
                if not hop then hop = { vz0 = vel.z, peak = vel.z, burn = 0, rise = 0, r = r } end
                hop.burn = hop.burn + dt
            end
            if hop then
                vel = GetEntityVelocity(veh)
                if vel.z > hop.peak then hop.peak = vel.z end
                hop.rise = hop.rise + (vel.z - hop.vz0) * dt
                if not want and vel.z < hop.vz0 then
                    local pv, ph = Act.hopPrediction(hop.r, hop.burn)
                    report("burn: twr %.2f for %.2f s | vz %+.1f -> peak %+.1f (pred dv %.1f) | rise %.1f m (pred %.1f) | speed now %.1f m/s",
                        hop.r, hop.burn, hop.vz0, hop.peak, pv, hop.rise, ph, #vel)
                    hop = nil
                end
            end
            -- attitude: a pure couple from paired offset forces, airborne only
            if IsEntityInAir(veh) and NetworkHasControlOfEntity(veh) then
                local pitch = -GetControlNormal(0, 61)   -- vehicle move up/down
                local roll = GetControlNormal(0, 59)     -- vehicle move left/right
                local k, arm = C.attitudeGain * dt * mass / 1000, C.attitudeArm
                if math.abs(pitch) > 0.05 then
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, pitch * k, 0.0, arm, 0.0, 0, true, true, true, false, true)
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, -pitch * k, 0.0, -arm, 0.0, 0, true, true, true, false, true)
                end
                if math.abs(roll) > 0.05 then
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, roll * k, arm, 0.0, 0.0, 0, true, true, true, false, true)
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, -roll * k, -arm, 0.0, 0.0, 0, true, true, true, false, true)
                end
            end
        end
    end
end)
