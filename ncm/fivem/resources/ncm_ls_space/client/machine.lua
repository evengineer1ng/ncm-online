-- ncm_ls_space / client / machine: the NCM machine you are driving (L321; doc 54 §D, §H). Physics, not a lift flag.
--
-- Your GTA car carries an NCM MACHINE: an assembled design from `engineering.fixtures.MACHINES` (default
-- `ls_orbiter`: a 45 kN hydrazine main engine, two tanks, sixteen cold-gas RCS thrusters in opposed pairs, a radiator,
-- a battery). Every frame `engineering.dynamics` turns your controls into force and torque FROM WHERE EACH DEVICE IS
-- MOUNTED, burns propellant (and stops when it is gone), heats the machine (and derates it), and gives the change of
-- velocity; GTA only expresses it (`engineering.hosts`):
--   below the doorway   the velocity change is added to the GTA car (GTA keeps gravity, contact and collisions)
--   in Snowglobe        the frame (client/frame.lua) adds the acceleration to the UNIVERSE velocity instead
--   torque              equal and opposite forces at +/- `attitudeArm` (a pure couple), scaled by `torqueGain` --
--                       RAGE's force units at an offset are UNCALIBRATED; §SR1 logs commanded against observed spin.
--
-- Controls: TRIANGLE / Y (or H) = lift -- every upward-pointing main device at full throttle; on the ground it also
-- fires a ground ram if the machine has one (in the air a ram does nothing: there is nothing to push against).
-- Left stick / WASD in the air = pitch and roll, ALLOCATED to the devices by their real lever arms: a machine whose
-- thrusters cannot make a torque about an axis cannot turn about it.
--   /ncm.machine                list machines;  /ncm.machine <name>   fit one (full tanks)
--   /ncm.machine instrument     the old dev lift rig -- an INSTRUMENT for measuring the host, not a technology
--   /ncm.refuel                 full tanks and charge, on the ground and stopped
local Core = NcmCore
local U = Core.get("space.universe")
local Mach = Core.get("engineering.machine")
local Dyn = Core.get("engineering.dynamics")
local Fix = Core.get("engineering.fixtures")
local Alloc = Core.get("engineering.allocate")
local C = NcmLsConfig

NcmLsMachine = { mode = C.machineMode or "machine", name = nil, accLocal = { 0, 0, 0 }, flash = nil, flashUntil = 0 }
local M = NcmLsMachine

local function report(fmt, ...)
    local line = fmt:format(...)
    print("[ncm_ls_space] " .. line)
    TriggerServerEvent("ncm:ls:report", line)
end

local function fit(name)
    local design = Fix.MACHINES[name]
    if not design then return false end
    M.name, M.model = name, Mach.assemble(design)
    M.state = Dyn.init(M.model)
    M.o2 = { kg = M.model.o2Kg or 0 }                 -- the sealed cabin's oxygen (client/eva.lua breathes it)
    M.cap = Mach.capability(M.model, { g = C.surfaceG })
    M.axes = Mach.authority(M.model, { reaction = true }).controlledAxes
    M.prep = Alloc.prepare(M.model)                  -- the same allocation NPC pilots use (engineering.allocate)
    M.propCap = 0
    for _, t in ipairs(M.model.tanks) do M.propCap = M.propCap + t.capacityKg end
    report("machine %s fitted: %.0f kg wet / %.0f dry | twr %.2f sea, %.2f vacuum | delta-v %.0f m/s | burn %.0f s | hop %.2f m | %d/6 vacuum axes | first to fail: %s",
        name, M.model.wetMassKg, M.model.dryMassKg, M.cap.twrSea, M.cap.twrVacuum, M.cap.deltaVms, M.cap.burnTimeS,
        M.cap.hopHeightM, M.axes, tostring(M.cap.firstFailure))
    for _, c in ipairs(M.cap.consequences) do report("  %s", c) end
    return true
end
fit(C.machine or "ls_orbiter")

--- Delta-v left at the current mass (the rocket equation on what is still in the tanks).
function M.deltaVLeft()
    if not M.model or M.cap.deltaVms <= 0 then return 0 end
    local wet, dry = M.model.wetMassKg, M.model.dryMassKg
    local now = Dyn.mass(M.model, M.state)
    return M.cap.deltaVms * math.log(now / dry) / math.log(wet / dry)
end

function M.propellantLeft() return M.model and Dyn.propellantLeft(M.model, M.state) or 0 end

local function flash(text) M.flash, M.flashUntil = text, GetGameTimer() + 2500 end

RegisterCommand("ncm.machine", function(_, args)
    local a = args[1]
    if not a then
        local names = {}
        for k in pairs(Fix.MACHINES) do names[#names + 1] = k end
        table.sort(names)
        report("mode %s, machine %s; fixtures: %s; or 'instrument' for the dev lift rig", M.mode, tostring(M.name), table.concat(names, ", "))
    elseif a == "instrument" or a == "dev" then
        M.mode = "instrument"
        report("INSTRUMENT mode: the F0 lift rig (a measuring device, not a technology); /ncm.machine <name> to go back")
    elseif fit(a) then
        M.mode = "machine"
    else
        report("no machine called %s", a)
    end
end, false)

RegisterCommand("ncm.refuel", function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh ~= 0 and (IsEntityInAir(veh) or GetEntitySpeed(veh) > 2.0) then report("refuel refused: land and stop first"); return end
    if NcmLsFrame and NcmLsFrame.active then report("refuel refused: no infrastructure in Snowglobe yet"); return end
    M.state = Dyn.init(M.model)
    M.o2 = { kg = M.model.o2Kg or 0 }
    report("refuelled: %.0f kg propellant, stores charged", M.propellantLeft())
end, false)

local function rotationOf(veh)
    local fwd, right, up = GetEntityMatrix(veh)            -- world vectors of the car's y, x, z axes
    return { { right.x, fwd.x, up.x }, { right.y, fwd.y, up.y }, { right.z, fwd.z, up.z } }
end

local lastLog = 0
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if M.mode ~= "machine" or not M.model or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
            M.accLocal = { 0, 0, 0 }
            Wait(250)
        else
            Wait(0)
            DisableControlAction(0, 75, true)                 -- Y/TRIANGLE is the lift, never "exit" (IDEA-1047)
            local dt = GetFrameTime()
            local F = NcmLsFrame or {}
            local lift = IsDisabledControlPressed(0, 75) or (NcmLsThrust and NcmLsThrust.keyHeld)
            local inAir = IsEntityInAir(veh)
            local tauD = { 0, 0, 0 }
            if inAir then
                tauD[1] = -GetControlNormal(0, 61)            -- stick up/down: pitch (torque about x), as the instrument did
                tauD[2] = -GetControlNormal(0, 59)            -- stick left/right: roll (torque about y), as the instrument did
            end
            -- allocation: each device's throttle = lift share + how much its own torque points where you asked
            local thr = Alloc.attitude(M.prep, tauD, lift and true or false)
            local s = M.state
            s.pos, s.vel, s.omega, s.rot = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, rotationOf(veh)
            local p = GetEntityCoords(veh)
            local alt = F.active and F.alt or p.z
            local _, tel = Dyn.step(M.model, s, { g = { 0, 0, 0 }, rho = U.densityAt(alt), contact = not inAir },
                { throttle = thr, fire = lift and not inAir }, dt)
            M.tel = tel
            local dv = s.vel                                    -- this frame's change of velocity, world (east/north/up)
            M.accLocal = dt > 0 and { dv[1] / dt, dv[2] / dt, dv[3] / dt } or { 0, 0, 0 }
            for _, e in ipairs(tel.events) do
                if e.what == "fired" then report("ram fired: %.0f J -> +%.2f m/s", e.energyJ, e.dv); flash("RAM")
                elseif e.what == "no_contact" then flash("NO CONTACT - nothing to push against")
                elseif e.what == "not_charged" then flash("RAM CHARGING")
                elseif e.what == "starved" then flash("PROPELLANT EMPTY")
                elseif e.what == "no_energy" then flash("BATTERY EMPTY") end
            end
            if tel.derate < 1 then flash(("OVERHEAT - derated to %d%%"):format(math.floor(tel.derate * 100))) end
            if NetworkHasControlOfEntity(veh) then
                if not F.active and (dv[1] ~= 0 or dv[2] ~= 0 or dv[3] ~= 0) then
                    local v = GetEntityVelocity(veh)
                    SetEntityVelocity(veh, v.x + dv[1], v.y + dv[2], v.z + dv[3])
                end
                -- torque as a couple on the car's own axes (uncalibrated gain; §SR1 measures it)
                local arm, k = C.attitudeArm, C.torqueGain
                local wx, wy = s.omega[1] * k, s.omega[2] * k
                if math.abs(wx) > 1e-5 then
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, wx, 0.0, arm, 0.0, 0, true, true, true, false, true)
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, -wx, 0.0, -arm, 0.0, 0, true, true, true, false, true)
                end
                if math.abs(wy) > 1e-5 then
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, -wy, arm, 0.0, 0.0, 0, true, true, true, false, true)
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, wy, -arm, 0.0, 0.0, 0, true, true, true, false, true)
                end
            end
            local now = GetGameTimer()
            if (lift or inAir) and now - lastLog >= 1000 then
                lastLog = now
                local rv = GetEntityRotationVelocity(veh)
                report("machine %s: thrust %.0f N | prop %.1f kg | dv left %.0f m/s | heat +%.1f K (derate %.2f) | rho %.3f | cmd spin x %.4f y %.4f rad/s per frame | GTA rot vel %.2f %.2f %.2f",
                    M.name, tel.thrustN, M.propellantLeft(), M.deltaVLeft(), s.heatK, tel.derate, tel.rho, s.omega[1], s.omega[2], rv.x, rv.y, rv.z)
            end
        end
    end
end)
