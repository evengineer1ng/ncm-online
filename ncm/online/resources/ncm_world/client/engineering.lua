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
--
-- 2026-10-12, A FLIGHT COMPUTER ON BOARD (the AV; owner: "make it fly ... aren't we using our engineering parts and
-- vfx"): a Machine carrying an installed `flight_computer` is flown on the FULL model instead -- the same
-- engineering.flightmodel + engineering.dynamics Deep steps, with engineering.flightcontrol turning the stick into
-- engine throttles and a torque request. Every frame the model is seeded with the body's real state (attitude from
-- `character.frame`, velocity and spin from the last frames), stepped once, and its force AND torque go to the Carrier
-- (`massKg` so the host body's own mass does not change the acceleration; `ax/ay/az` the angular acceleration; `av` so
-- the Carrier switches an AV body's physics on). Here torque IS expressed.
local Core = NcmCore
local Install = Core.get("engineering.installation")
local Controls = Core.get("engineering.controls")
local Fx = Core.get("presentation.fx")
local FC = Core.get("engineering.flightcontrol")
local Flight = Core.get("engineering.flightmodel")
local Dyn = Core.get("engineering.dynamics")
local Sys = Core.get("engineering.systems")

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
    for _, spec in ipairs(p.specs or {}) do Install.register(spec) end
    local all, refused = Install.resolve(p.items or {}, p.vehicleKey)
    -- stacked gearboxes (client/gearing.lua) are driveline, never propulsion: kept out of the force loop, so a Machine
    -- whose only add-on is a gearbox never sends a wrench (which would park NCM Thrust's hop)
    local devices, driveline = {}, {}
    for _, d in ipairs(all) do
        -- L356: electronics (a Slipstream unit) push nothing and are run by ncm_slipstream: kept out of the force loop too
        if Install.isDriveline(d.kind) then driveline[#driveline + 1] = d
        elseif not Install.isElectronic(d.kind) then devices[#devices + 1] = d end
    end
    if NcmClientGearingApply then NcmClientGearingApply(p.assetId, driveline, p.bindings or {}) end
    local fc = FC.computer(all)
    local fuelMl = p.fuel and tonumber(p.fuel.ml)
    -- KB-429: the server re-sends an UNCHANGED Machine on every odometer checkpoint (~every 250 m: every few seconds in
    -- a climb). Rebuilding from scratch reset the throttle lag, the hold gesture, heat and the fuel reading each time,
    -- so a sustained burn kept collapsing (in Deep: "thrust 0 N"). Same parts, same bindings: keep the running state.
    local sig = {}
    for _, d in ipairs(devices) do sig[#sig + 1] = ("%s@%s/%s"):format(tostring(d.componentId), tostring(d.mountId), tostring(d.facing)) end
    for _, x in ipairs(p.bindings or {}) do sig[#sig + 1] = ("%s:%s:%s:%s"):format(tostring(x.control), tostring(x.gesture), tostring(x.componentId), tostring(x.command)) end
    sig = table.concat(sig, ",")
    local keep = E and E.assetId == p.assetId and E.sig == sig and E or nil
    E = {
        assetId = p.assetId, vehicleKey = p.vehicleKey, devices = devices, bindings = p.bindings or {}, sig = sig,
        state = keep and keep.state or Install.newState(devices), ctl = keep and keep.ctl or Controls.newState(),
        fuelKg = fuelMl and (fuelMl / 1000 * Install.FUEL_KG_PER_L) or 0, fuelKnown = fuelMl ~= nil,
        controls = Controls.controls(p.bindings or {}), report = keep and keep.report or { kg = 0, fusionKg = 0, pulses = 0, since = ms() },
        lastSend = keep and keep.lastSend or 0, lastF = keep and keep.lastF or nil,
        fc = fc, fly = keep and keep.fly or nil,
    }
    -- L334: a tank PART's own propellant (the Fusion Drive's), apart from the car's fuel
    E.fusionKg = 0
    for _, d in ipairs(devices) do if d.kind == "propellant_tank" and (d.perf.propellant or "fuel") == "fusion" then E.fusionKg = E.fusionKg + (d.fillKg or 0) end end
    if keep then
        -- the server's figures are as of its last burn report; what has burned since is still in our report
        E.fusionKg = math.max(0, E.fusionKg - (keep.report.fusionKg or 0))
        if fuelMl then E.fuelKg = math.max(0, E.fuelKg - (keep.report.kg or 0))
        else E.fuelKg, E.fuelKnown = keep.fuelKg, keep.fuelKnown end
        return
    end
    local parts = {}
    for _, d in ipairs(all) do parts[#parts + 1] = ("%s@%s/%s"):format(d.code, d.mountId:gsub("^mount%.", ""), d.facing) end
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
local function lease(fx, fy, fz, assetId)
    if not NcmClientMachineWrench then return false end
    return NcmClientMachineWrench({ v = 1, assetId = assetId, vehicleId = tostring(boundVehicle), fx = fx, fy = fy, fz = fz,
        ttlMs = LEASE_TTL_MS, supersedeLift = true })
end

-- L356: the aerodynamic tow (natural draft + an SL-1's active share), a WORLD force computed by ncm_slipstream from
-- the wake and handed over here, because this file owns the Machine's one wrench lease. It is added to whatever the
-- installed devices push; with no devices pushing, it goes out as its own lease. It is never Thrust's lift owner.
local tow = { x = 0, y = 0, z = 0, untilMs = 0, asset = nil }
exports("slipTow", function(fx, fy, fz, ttlMs, assetId)
    tow.x, tow.y, tow.z = tonumber(fx) or 0, tonumber(fy) or 0, tonumber(fz) or 0
    tow.untilMs = ms() + math.max(0, math.min(500, tonumber(ttlMs) or 0))
    tow.asset = assetId
    return true
end)
local function towNow(assetId)
    if tow.untilMs <= ms() or (assetId and tow.asset and tow.asset ~= assetId) then return nil end
    return tow
end

local function pulse(w, durationMs, assetId)
    if not NcmClientMachineWrench then return false end
    pulseSeq = pulseSeq + 1
    return NcmClientMachineWrench({ v = 1, assetId = assetId, vehicleId = tostring(boundVehicle), fx = 0, fy = 0, fz = 0,
        ttlMs = LEASE_TTL_MS, supersedeLift = true, pulse = { seq = pulseSeq, fx = w[1], fy = w[2], fz = w[3], ms = durationMs } })
end

-- binding: who we are bound to, and asking the server what that Machine carries
CreateThread(function()
    Wait(10000)
    while true do
        local aid, vid = readBinding()
        -- KB-429: in Deep the car is server-frozen and moved into a stage; a passing gap in the binding bag must not
        -- take the Machine's parts away mid-flight ("no installed components")
        if not aid and NcmClientDeepActive and boundAsset then aid, vid = boundAsset, boundVehicle end
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

-- ------------------------------------------------------------------------------------------------ the flight computer
local function axis(n)
    local okC, captured = pcall(Open77.input.isCaptured)
    if okC and captured == true then return 0 end
    local ok, v = pcall(Open77.input.axis, n)
    v = ok and type(v) == "number" and v or 0
    return math.abs(v) < 0.15 and 0 or v
end

--- The pilot's stick, on Deep's keys (one grammar on the ground and in space): W/S pitch to fly forward/back, A/D turn,
--- Q/E bank, Space climb, C descend; on a pad the left stick (pitch, turn), right stick X (bank), the triggers (lift).
local function stick()
    local function k(c) return down(c) and 1 or 0 end
    local function cl(x) return math.max(-1, math.min(1, x)) end
    return {
        pitch = cl(k("W") - k("S") + axis("padLeftStickY")),
        yaw = cl(k("D") - k("A") + axis("padLeftStickX")),
        roll = cl(k("E") - k("Q") + axis("padRightStickX")),
        -- Space climbs, C descends (Space IS an OPEN//77 control: Open77.dll's key table). Not R: R is the radio (owner,
        -- 2026-10-13: "r button is nonsensical thats radio button")
        lift = cl(k("Space") - k("C") + axis("padRightTrigger") - axis("padLeftTrigger")),
    }
end

local function vec(p) return p and { tonumber(p.x or p[1]) or 0, tonumber(p.y or p[2]) or 0, tonumber(p.z or p[3]) or 0 } end

local function avFrame(E, dt, t)
    local okF, frame = pcall(Open77.character.frame, { vehicleId = boundVehicle })
    local okV, v = pcall(Open77.vehicles.get, boundVehicle)
    if not (okF and type(frame) == "table" and frame.right and frame.forward and frame.up and okV and type(v) == "table") then return end
    -- 2026-10-12 (owner, first AV flight: "janky af, doesnt rise properly"): the BODY's own position, from
    -- `character.frame` -- the replicated snapshot moves in steps, so its frame-to-frame difference read 0 m/s for most
    -- frames and then 29 m/s, and the computer fought its own bad readings
    local bodyPos = frame.position or v.position
    if not bodyPos then return end
    local r, f, u, pos = vec(frame.right), vec(frame.forward), vec(frame.up), vec(bodyPos)
    local rot = { { r[1], f[1], u[1] }, { r[2], f[2], u[2] }, { r[3], f[3], u[3] } }

    -- the model: built once per installed configuration; its state (tanks, throttle lag, heat) is kept across frames
    local F = E.fly
    if not F or F.sig ~= E.sig then
        local m = Flight.build(E.devices, { vehicleKey = E.vehicleKey, fuelKg = E.fuelKg })
        F = { sig = E.sig, m = m, s = Dyn.init(m, { pos = pos, rot = rot }), prevPos = pos, prevRot = rot, vel = { 0, 0, 0 }, omega = { 0, 0, 0 } }
        E.fly = F
        log("FLIGHT COMPUTER on Machine ..%s: %.0f kg, %d lift device(s), inertia (%.0f, %.0f, %.0f) kg m^2 -- fly-by-wire armed",
            tostring(E.assetId):sub(-6), Dyn.mass(m, F.s), #FC.liftDevices(m), m.inertia[1], m.inertia[2], m.inertia[3])
    end
    local m, s = F.m, F.s

    -- the body's real state: velocity and spin from the frames it actually moved through (smoothed)
    -- the spin is smoothed less than the velocity (KB-470): its lag fed the attitude loop's oscillation
    local a, aw = 0.35, 0.7
    local vRaw = { (pos[1] - F.prevPos[1]) / dt, (pos[2] - F.prevPos[2]) / dt, (pos[3] - F.prevPos[3]) / dt }
    local wRaw = FC.omegaFrom(F.prevRot, rot, dt)
    for i = 1, 3 do
        F.vel[i] = F.vel[i] + (vRaw[i] - F.vel[i]) * a
        F.omega[i] = F.omega[i] + (wRaw[i] - F.omega[i]) * aw
    end
    F.prevPos, F.prevRot = pos, rot
    s.pos, s.rot, s.vel, s.omega = pos, rot, { F.vel[1], F.vel[2], F.vel[3] }, { F.omega[1], F.omega[2], F.omega[3] }

    local rho = Flight.density(pos[3])
    local mass = Dyn.mass(m, s)
    -- PARKED until the pilot asks for lift; parked again once it has settled after a descent (the snapshot carries no
    -- ground contact: on the first flight the computer hovered on the pad with every plume burning)
    local st = stick()
    F.parked = F.parked ~= false
    if F.parked then
        if st.lift > 0 then F.parked, F.settleMs = false, nil end
    else
        if st.lift < 0 and math.abs(F.vel[3]) < 0.4 then
            F.settleMs = (F.settleMs or 0) + dt * 1000
            if F.settleMs > 1500 then F.parked = true end
        else
            F.settleMs = nil
        end
    end
    local contact = F.parked
    local cmd, rep = FC.step(m, s, st, { mass = mass, inertia = m.inertia, rho = rho, g = 9.81, contact = contact, perf = E.fc })
    -- KB-468: the whole AV frame in one slice ran out of OPEN//77's script budget nearly every frame (600 faults in
    -- 13 s on 2026-10-13: the flight computer and the plumes were cut off mid-frame). Each stage gets its own slice.
    Wait(0)
    if NcmClientDevHeat then for _, st in pairs(s.dev or {}) do st.heatK, st.hot = 0, false end end
    local fuelBefore, fusionBefore = Dyn.propellantLeft(m, s, "fuel"), Dyn.propellantLeft(m, s, "fusion")
    local _, tel = Dyn.step(m, s, { g = { 0, 0, -9.81 }, rho = rho, contact = contact }, cmd, dt)
    -- the host moves the body; the model's own integration is discarded (the next frame re-seeds it)
    local usedFuel = math.max(0, fuelBefore - Dyn.propellantLeft(m, s, "fuel"))
    local usedFusion = math.max(0, fusionBefore - Dyn.propellantLeft(m, s, "fusion"))
    if NcmClientDevFuel then
        for i, tk in ipairs(m.tanks) do s.tanks[i] = tk.kg end
    else
        E.fuelKg = math.max(0, E.fuelKg - usedFuel)
        E.report.kg = E.report.kg + usedFuel
        E.report.fusionKg = (E.report.fusionKg or 0) + usedFusion
    end

    -- force (world, N) and angular acceleration (world, rad/s^2) to the Carrier
    local Fw = tel.forceN or { 0, 0, 0 }
    local Tb = tel.torque or { 0, 0, 0 }
    local ab = { Tb[1] / math.max(1, m.inertia[1]), Tb[2] / math.max(1, m.inertia[2]), Tb[3] / math.max(1, m.inertia[3]) }
    local aw = {
        rot[1][1] * ab[1] + rot[1][2] * ab[2] + rot[1][3] * ab[3],
        rot[2][1] * ab[1] + rot[2][2] * ab[2] + rot[2][3] * ab[3],
        rot[3][1] * ab[1] + rot[3][2] * ab[2] + rot[3][3] * ab[3],
    }
    if t - E.lastSend >= SEND_MS and NcmClientMachineWrench then
        NcmClientMachineWrench({ v = 1, assetId = E.assetId, vehicleId = tostring(boundVehicle), fx = Fw[1], fy = Fw[2], fz = Fw[3],
            ttlMs = LEASE_TTL_MS, supersedeLift = true, av = true, massKg = mass, ax = aw[1], ay = aw[2], az = aw[3] })
        E.lastSend = t
    end
    NcmClientEngineeringLoopAt = t
    E.lastW, E.lastFrame = Fw, frame
    Wait(0)

    -- what each engine is doing, for NCM FX (the plumes at the pods) and the report
    local out = {}
    for i, d in ipairs(m.devices) do
        local thr = (s.thr and s.thr[i]) or 0
        out[d.key] = { thrustN = Sys.thrustAt(d.perf, rho, thr), throttle = thr, heatK = (s.dev and s.dev[i] or {}).heatK or 0 }
    end
    if NcmFx then
        local env = { rho = rho, contact = contact, altitude = pos[3] }
        if F.parked then out = {} end   -- parked: nothing burns, nothing is drawn
        local em = Fx.fromInstall(E.assetId, E.devices, out, E.state, env)
        local body = Fx.machine(E.assetId, { speed = tonumber(v.speed) or 0, rho = rho, contact = contact, altitude = pos[3] }, E.fxBody)
        E.fxBody = body[1].q
        em[#em + 1] = body[1]
        NcmFx.publish(E.assetId, boundVehicle, em)
        NcmFx.frame(E.assetId, em, frame, bodyPos)
        Wait(0)
    end

    if t - E.report.since >= REPORT_MS then
        local parts = {}
        for _, d in ipairs(E.devices) do
            local o = out[d.componentId]
            if o then parts[#parts + 1] = ("%s@%s thr %.2f %.1f kN"):format(d.code, d.mountId:gsub("^mount%.", ""), o.throttle, o.thrustN / 1000) end
        end
        local pitch, roll = FC.attitude(rot)
        local state = rep.idle and " PARKED" or (rep.short and " SHORT" or "")
        TriggerServerEvent("ncm:engineering.burn", { assetId = E.assetId, kg = E.report.kg, fusionKg = E.report.fusionKg or 0,
            dtS = (t - E.report.since) / 1000, pulses = 0,
            t = { devices = ("FLY-BY-WIRE [%s z %.1f snap %.1f] need %.0f kN (air %.0f%%, fusion %.0f%%)%s pitch %.1f roll %.1f vz %.1f | %s"):format(
                    frame.position and "body" or "SNAPSHOT", pos[3], v.position and tonumber(v.position.z) or -1,
                    (rep.needN or 0) / 1000, (rep.uAir or 0) * 100, (rep.uRocket or 0) * 100, state,
                    math.deg(pitch), math.deg(roll), F.vel[3], table.concat(parts, " | "))
                    .. (" | stick lift %.1f pitch %.1f | CARRIER %s"):format(st.lift, st.pitch,
                        (NcmClientCarrierAv and GetGameTimer() - NcmClientCarrierAv.at < 3000) and NcmClientCarrierAv.line or "no AV report"),
                fx = Fw[1], fy = Fw[2], fz = Fw[3], f = math.sqrt(Fw[1] ^ 2 + Fw[2] ^ 2 + Fw[3] ^ 2),
                fwx = f[1], fwy = f[2], fwz = f[3], upx = u[1], upy = u[2], upz = u[3],
                speed = tonumber(v.speed) or 0, z = pos[3], hot = false,
                snapZ = v.position and tonumber(v.position.z) or nil, src = frame.position and "body" or "snapshot",
                loss = "torque expressed as angular acceleration on the body; host collisions and damping not in the model" } })
        E.report = { kg = 0, fusionKg = 0, pulses = 0, since = t }
    end
end

-- One frame of the devices. KB-436 (2026-10-10): the binding thread can drop `E` while this thread is parked in
-- Wait(0) (it did on the drop back from Deep), and `E.controls` then threw and killed the whole loop -- the propulsor and
-- actuator stayed dead for the rest of the session. The frame now works on the Machine it was handed.
local function deviceFrame(E, dt, t)
            local pressed = {}
            for _, c in ipairs(E.controls) do pressed[c] = down(c) end
            local commands = Controls.step(E.ctl, E.bindings, E.devices, pressed, t)
            -- dev fuel (the DEVELOPMENT server's setting, sent in the Deep config): nothing burned, nothing reported
            if NcmClientDevHeat then NcmClientCoolAll(E.state) end
            local r = Install.step(E.devices, E.state, commands, dt,
                NcmClientDevFuel and { fuel = 1e9, fusion = 1e9 } or { fuel = E.fuelKg, fusion = E.fusionKg or 0 })
            if not NcmClientDevFuel then
                local bp = r.byPropellant or {}
                E.fuelKg = math.max(0, E.fuelKg - (bp.fuel or 0))
                E.fusionKg = math.max(0, (E.fusionKg or 0) - (bp.fusion or 0))
                E.report.kg = E.report.kg + (bp.fuel or 0)
                E.report.fusionKg = (E.report.fusionKg or 0) + (bp.fusion or 0)
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
                    if w then pulse(w, math.floor(d.perf.pulseS * 1000 + 0.5), E.assetId) end
                end
            end
            local w = frame and Install.toWorld(sustained, frame) or { 0, 0, 0 }
            local tw = towNow(E.assetId)
            if tw then w[1], w[2], w[3] = w[1] + tw.x, w[2] + tw.y, w[3] + tw.z end
            NcmClientEngineeringLoopAt = t
            local mag = math.sqrt(w[1] ^ 2 + w[2] ^ 2 + w[3] ^ 2)
            local changed = (E.lastF == nil) or math.abs(mag - E.lastF) > 50
            if (mag > 0 and (t - E.lastSend >= SEND_MS)) or (changed and t - E.lastSend >= SEND_MS) or (t - E.lastSend >= HEARTBEAT_MS) then
                lease(w[1], w[2], w[3], E.assetId)
                E.lastSend, E.lastF = t, mag
            end
            E.lastW, E.lastFrame, E.hot = w, frame, hot

            -- NCM FX (presentation.fx): what the devices just did, drawn at their mounts (client/fx.lua)
            if NcmFx and frame then
                local okV, v = pcall(Open77.vehicles.get, boundVehicle)
                local pos = okV and type(v) == "table" and v.position or nil
                if pos then
                    local z = tonumber(pos.z) or 0
                    local env = { rho = 1.225 * math.exp(-math.max(0, z) / 8500), contact = v.onGround == true, altitude = z }
                    local em = Fx.fromInstall(E.assetId, E.devices, r.out, E.state, env)
                    local body = Fx.machine(E.assetId, { speed = tonumber(v.speed) or 0, rho = env.rho, contact = env.contact,
                        altitude = z }, E.fxBody)
                    E.fxBody = body[1].q
                    em[#em + 1] = body[1]
                    NcmFx.publish(E.assetId, boundVehicle, em)
                    NcmFx.frame(E.assetId, em, frame, pos)
                end
            end

            if t - E.report.since >= REPORT_MS then
                local active = E.report.kg > 0 or (E.report.fusionKg or 0) > 0 or mag > 0
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
                    TriggerServerEvent("ncm:engineering.burn", { assetId = E.assetId, kg = E.report.kg, fusionKg = E.report.fusionKg or 0,
                        dtS = (t - E.report.since) / 1000, pulses = E.report.pulses,
                        t = { devices = table.concat(parts, " | "), fx = w[1], fy = w[2], fz = w[3], f = mag,
                            fwx = fw.x, fwy = fw.y, fwz = fw.z, upx = up.x, upy = up.y, upz = up.z,
                            speed = okV and type(v) == "table" and v.speed or 0, z = pos.z or 0, hot = hot, loss = LOSS } })
                end
                E.report = { kg = 0, fusionKg = 0, pulses = 0, since = t }
            end
end

-- the devices, every frame while they exist and we drive them
CreateThread(function()
    local last = ms()
    local faults = 0
    while true do
        -- L326: while NCM's universe owns the Machine (client/deep.lua) the car is frozen in REDengine: no wrench, no burn here.
        if NcmClientDeepActive or not (E and #E.devices > 0 and boundVehicle and seatedIn(boundVehicle)) then
            last = ms()
            Wait(250)
        else
            Wait(0)
            local e = E   -- whatever the binding thread did while we waited
            local t = ms()
            local dt = math.min(0.1, math.max(0.001, (t - last) / 1000))
            last = t
            if e and #e.devices > 0 and not NcmClientDeepActive then
                local ok, err = pcall(e.fc and avFrame or deviceFrame, e, dt, t)
                if not ok then
                    faults = faults + 1
                    if faults <= 5 or faults % 600 == 0 then log("device frame fault #%d (the loop keeps running): %s", faults, tostring(err)) end
                end
            end
        end
    end
end)

-- L356: the tow alone, when the device loop above is not running (a Machine whose only add-on is a Slipstream unit,
-- or none: the natural draft needs no part). Never supersedes Thrust's lift: the car's propulsion owner is unchanged.
CreateThread(function()
    local lastSend = 0
    while true do
        local t = ms()
        local tw = towNow(boundAsset)
        local loopRunning = NcmClientEngineeringLoopAt and (t - NcmClientEngineeringLoopAt) < 200
        if tw and boundAsset and boundVehicle and not loopRunning and not NcmClientDeepActive and NcmClientMachineWrench then
            if t - lastSend >= SEND_MS then
                NcmClientMachineWrench({ v = 1, assetId = boundAsset, vehicleId = tostring(boundVehicle), fx = tw.x, fy = tw.y, fz = tw.z,
                    ttlMs = LEASE_TTL_MS, supersedeLift = false })
                lastSend = t
            end
            Wait(0)
        else
            Wait(100)
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
