-- ncm_ls_space / client / eva: staying alive above the air, and crossing between cars in space (L323; doc 54 §S).
--
-- BREATHING (`life.breath`). Every frame: what is this person breathing? Outside air (density from the city height
-- below the doorway, universe altitude in Snowglobe), the car's SEALED cabin (the NCM machine's `pressure_cabin` and
-- its oxygen, `life_support`), or the emergency suit everyone wears (about 10 minutes working hard). Without any:
-- hypoxia, then blackout (ragdoll), then death (GTA respawn). Real breathing rates; named consequences.
--
-- EVA. On foot in Snowglobe the frame already carries you (client/frame.lua follows the player). The suit's EVA pack
-- adds a small push (120 N, 3 kg of nitrogen, Isp 70 s: about 20 m/s of delta-v): left stick = camera-relative,
-- JUMP up, DUCK down. It is finite.
--
-- BOARDING A CAR IN SPACE is the relay exchange (`space.relay`): within 4 m of the car and matched to under 2 m/s for
-- a full second -- then you are in. `/ncm.eva.drill` puts a teammate car 20 m beside you in Snowglobe, coasting on the
-- same orbit as you were; get out, cross, board: a PASSENGER BATON transfer, logged as a relay exchange. (Which baton
-- the Relay discipline uses is still the owner's ruling, L322 Q1; this makes the passenger candidate real.)
local Core = NcmCore
local U = Core.get("space.universe")
local V = U.vec
local B = Core.get("life.breath")
local Relay = Core.get("space.relay")
local Fix = Core.get("engineering.fixtures")
local C = NcmLsConfig

local frame = U.anchorFrame(C.anchor)
local SUIT = Fix.DESIGNS.eva_suit_emergency.perf
local G0 = 9.80665
local PED_KG = 80

NcmLsEva = { accLocal = { 0, 0, 0 }, n2Kg = SUIT.packN2Kg, breath = B.newState(SUIT.o2Kg) }
local X = NcmLsEva

local function report(fmt, ...)
    local line = fmt:format(...)
    print("[ncm_ls_space] " .. line)
    TriggerServerEvent("ncm:ls:report", line)
end

local function newSuit()
    X.breath = B.newState(SUIT.o2Kg)
    X.n2Kg = SUIT.packN2Kg
end

local drill = nil

RegisterCommand("ncm.eva.drill", function()
    local F = NcmLsFrame
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not (F and F.active) or veh == 0 then report("EVA drill: be in a car in Snowglobe first"); return end
    if drill and drill.veh and DoesEntityExist(drill.veh) then DeleteEntity(drill.veh) end
    local model = joaat("sultan")
    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t0 < 3000 do Wait(0) end
    local p = GetEntityCoords(veh)
    local car = CreateVehicle(model, p.x + 20.0, p.y, p.z, GetEntityHeading(veh), true, false)
    SetModelAsNoLongerNeeded(model)
    SetVehicleGravity(car, false)
    local side = U.localToEarth(frame, { 20, 0, 0 })
    drill = { veh = car, u = V.add(F.u, side), w = { F.w[1], F.w[2], F.w[3] }, from = veh, boarded = false, startedAt = GetGameTimer(),
        relay = Relay.new({ { zone = { centre = { 0, 0, 0 }, radiusM = 4 } }, {} }, { "you", "teammate" }, { vRelMaxMs = 2, holdS = 1 }) }
    report("EVA drill: a teammate car is coasting 20 m to your right on your orbit. Get out, cross on the EVA pack (stick, JUMP up, DUCK down), match it within 4 m and 2 m/s for a second.")
end, false)

-- the drill car coasts under NCM gravity and is drawn where it is
CreateThread(function()
    while true do
        if not drill or drill.boarded then
            Wait(250)
        else
            Wait(0)
            local F = NcmLsFrame
            if not (F and F.active and F.u) or not DoesEntityExist(drill.veh) then
                drill = nil
            else
                local dt = GetFrameTime()
                U.integrate(drill, U.gravity(drill.u), dt)
                local ped = PlayerPedId()
                local subject = GetVehiclePedIsIn(ped, false)
                if subject == 0 then subject = ped end
                local p = GetEntityCoords(subject)
                local d = U.earthToLocal(frame, V.sub(drill.u, F.u))
                SetEntityCoordsNoOffset(drill.veh, p.x + d[1], p.y + d[2], p.z + d[3], false, false, false)
                local lv = U.earthToLocal(frame, drill.w)
                SetEntityVelocity(drill.veh, lv[1], lv[2], lv[3])
            end
        end
    end
end)

-- breathing, the EVA pack, and boarding
local lastStatus, lastLog = "ok", 0
CreateThread(function()
    while true do
        Wait(0)
        local dt = GetFrameTime()
        local ped = PlayerPedId()
        local F = NcmLsFrame or {}
        local veh = GetVehiclePedIsIn(ped, false)
        local p = GetEntityCoords(veh ~= 0 and veh or ped)
        if IsEntityDead(ped) then
            if X.breath.status == "dead" or X.breath.status == "blackout" then newSuit() end
            X.accLocal = { 0, 0, 0 }
        else
            local rho = F.active and U.density(F.u) or U.densityAt(p.z)
            local Mc = NcmLsMachine
            local cabin
            if veh ~= 0 and Mc and Mc.mode == "machine" and Mc.model and Mc.model.cabin then
                cabin = { sealed = true, o2 = Mc.o2 }
            end
            local exertion = veh == 0 and 2 or 1.3
            local ev = B.step(X.breath, { rho = rho, cabin = cabin, suit = true, exertion = exertion }, dt)
            if ev then
                if ev.status == "hypoxic" then report("AIR: nothing to breathe (air %.3f kg/m3, %s) -- hypoxia", rho, cabin and "cabin empty" or "no sealed cabin, suit empty")
                elseif ev.status == "blackout" then report("AIR: BLACKOUT"); SetPedToRagdoll(ped, 5000, 5000, 0, false, false, false)
                elseif ev.status == "dead" then report("AIR: dead of hypoxia"); SetEntityHealth(ped, 0)
                elseif ev.status == "ok" and lastStatus ~= "ok" then report("AIR: breathing again (%s)", tostring(ev.source)) end
                lastStatus = ev.status
            end
            if X.breath.status == "blackout" then SetPedToRagdoll(ped, 1000, 1000, 0, false, false, false) end
            -- the EVA pack: on foot in Snowglobe
            X.accLocal = { 0, 0, 0 }
            if veh == 0 and F.active and X.breath.status ~= "blackout" then
                local lr, ud = GetControlNormal(0, 30), -GetControlNormal(0, 31)
                local upDown = (IsControlPressed(0, 22) and 1 or 0) - (IsControlPressed(0, 36) and 1 or 0)
                if (math.abs(lr) > 0.1 or math.abs(ud) > 0.1 or upDown ~= 0) and X.n2Kg > 0 then
                    local rot = GetGameplayCamRot(2)
                    local h = math.rad(rot.z)
                    local fwd, right = { -math.sin(h), math.cos(h), 0 }, { math.cos(h), math.sin(h), 0 }
                    local dir = { fwd[1] * ud + right[1] * lr, fwd[2] * ud + right[2] * lr, upDown }
                    local m = V.len(dir)
                    if m > 0 then
                        dir = V.scale(dir, math.min(1, m) / m)
                        local mass = PED_KG + Fix.DESIGNS.eva_suit_emergency.massKg + X.n2Kg
                        X.accLocal = V.scale(dir, SUIT.packThrustN / mass)
                        X.n2Kg = math.max(0, X.n2Kg - SUIT.packThrustN / (SUIT.packIspS * G0) * dt * math.min(1, m))
                    end
                end
            end
            -- boarding the drill car: the relay exchange, judged in local coordinates (both presented in my frame)
            if drill and not drill.boarded and veh == 0 and DoesEntityExist(drill.veh) then
                local cp, cv = GetEntityCoords(drill.veh), GetEntityVelocity(drill.veh)
                local pv = GetEntityVelocity(ped)
                drill.relay.legs[1].zone.centre = { cp.x, cp.y, cp.z }
                local e = Relay.exchange(drill.relay, { pos = { p.x, p.y, p.z }, vel = { pv.x, pv.y, pv.z } },
                    { pos = { cp.x, cp.y, cp.z }, vel = { cv.x, cv.y, cv.z } }, GetGameTimer() / 1000, dt)
                if e and e.transferred then
                    drill.boarded = true
                    SetPedIntoVehicle(ped, drill.veh, -1)
                    local x = drill.relay.exchanges[1]
                    report("RELAY EXCHANGE (passenger baton): boarded the teammate car after %.1f s, closing %.2f m/s; suit O2 %.1f min left, EVA N2 %.2f kg",
                        (GetGameTimer() - drill.startedAt) / 1000, x.vRelMs, X.breath.suitO2 / (B.O2_PER_S * 2) / 60, X.n2Kg)
                end
            end
        end
        local now = GetGameTimer()
        if (F.active or X.breath.status ~= "ok") and now - lastLog > 5000 then
            lastLog = now
            TriggerServerEvent("ncm:ls:report", ("air: %s via %s | conscious %.2f | suit O2 %.4f kg | N2 %.2f kg | %s"):format(
                X.breath.status, tostring(X.breath.source), X.breath.conscious, X.breath.suitO2, X.n2Kg, veh ~= 0 and "in a car" or "EVA"))
        end
    end
end)

-- HUD: air
local function text(x, y, scale, s, r, g, b)
    SetTextFont(4); SetTextScale(scale, scale); SetTextColour(r or 235, g or 240, b or 255, 230); SetTextOutline()
    BeginTextCommandDisplayText("STRING"); AddTextComponentSubstringPlayerName(s); EndTextCommandDisplayText(x, y)
end
CreateThread(function()
    while true do
        local F = NcmLsFrame or {}
        local st = X.breath
        if not F.active and st.status == "ok" then
            Wait(250)
        else
            Wait(0)
            local bad = st.status ~= "ok"
            local suitMin = st.suitO2 / (B.O2_PER_S * 2) / 60
            local Mc = NcmLsMachine
            local cab = (Mc and Mc.o2) and ("cabin O2 %.2f kg"):format(Mc.o2.kg) or "no cabin"
            text(0.80, 0.42, 0.42, ("AIR %s via %s"):format(st.status:upper(), tostring(st.source or "nothing")), bad and 255 or 150, bad and 90 or 230, bad and 70 or 255)
            text(0.80, 0.445, 0.36, ("suit %.1f min | %s | conscious %d%%"):format(suitMin, cab, math.floor(st.conscious * 100)))
            if GetVehiclePedIsIn(PlayerPedId(), false) == 0 and F.active then
                text(0.80, 0.467, 0.36, ("EVA pack N2 %.2f kg%s"):format(X.n2Kg, drill and not drill.boarded and " | teammate car: match it" or ""))
            end
        end
    end
end)
