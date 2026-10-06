-- ncm_ls_space / client / hud: the altimeter. Below the doorway: game altitude and the distance to the doorway. In
-- Snowglobe: UNIVERSE altitude, universe speed, horizontal speed against the circular-orbit speed (orbit when they
-- match), gravity there, and the GTA body's local z.
-- L321: the MACHINE panel (what it burns, what is left, how hot, what just failed) and the RACE panel (venue, lap,
-- next gate, station range and closing speed, the classification with provenance).
local C = NcmLsConfig

local function text(x, y, scale, s, r, g, b)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r or 235, g or 240, b or 255, 230)
    SetTextOutline()
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(s)
    EndTextCommandDisplayText(x, y)
end

local lastZ, lastT, climb = nil, 0, 0.0

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local subject = veh ~= 0 and veh or ped
        local F, T = NcmLsFrame or {}, NcmLsThrust or {}
        local pos, now = GetEntityCoords(subject), GetGameTimer()
        local Mc = NcmLsMachine or {}
        local thrusting = (T.twr or 0) > 0 or (Mc.tel and (Mc.tel.thrustN or 0) > 0)
        if not F.active and pos.z < 50 and not thrusting then
            lastZ = nil
            Wait(200)
        else
            Wait(0)
            local alt = F.active and F.alt or pos.z
            if lastZ and now - lastT >= 200 then
                climb = (alt - lastZ) / ((now - lastT) / 1000)
                lastZ, lastT = alt, now
            elseif not lastZ then
                lastZ, lastT = alt, now
            end
            local x, y = 0.80, 0.52
            text(x, y, 0.42, F.active and "ALTITUDE - IN SPACE (NCM owns it)" or "ALTITUDE", 150, 210, 255)
            text(x, y + 0.025, 0.9, ("%d m"):format(math.floor(alt)), F.active and 115 or 235, F.active and 215 or 240, 255)
            text(x, y + 0.085, 0.45, (climb >= 0 and "CLIMB +%.1f m/s" or "FALL %.1f m/s"):format(climb),
                climb >= 0 and 80 or 255, climb >= 0 and 255 or 190, climb >= 0 and 140 or 60)
            if F.active then
                text(x, y + 0.11, 0.4, ("speed %.0f m/s | sideways %.0f / orbit %.0f m/s"):format(F.uspeed or 0, F.hspeed or 0, F.vcirc or 0))
                text(x, y + 0.133, 0.4, ("g %.2f | %s"):format(F.gmag or 0, F.kind or ""))
                text(x, y + 0.156, 0.36, ("game z %d | home below %d m"):format(math.floor(pos.z), C.homeAlt))
            else
                text(x, y + 0.11, 0.4, ("speed %d km/h | g %.2f"):format(math.floor(GetEntitySpeed(subject) * 3.6), C.surfaceG))
                text(x, y + 0.133, 0.36, ("doorway at %d m: %d m to go"):format(C.up, math.floor(C.up - pos.z)))
            end
        end
    end
end)

-- ------------------------------------------------------------------------------------------ machine and race panels
local Mach = NcmCore.get("engineering.machine")
CreateThread(function()
    while true do
        local Mc, R = NcmLsMachine, NcmLsRace
        local ped = PlayerPedId()
        local inCar = GetVehiclePedIsIn(ped, false) ~= 0
        local showMachine = Mc and inCar
        local showRace = R and (R.active or (R.result and GetGameTimer() < R.resultUntil))
        if not showMachine and not showRace then
            Wait(250)
        else
            Wait(0)
            local x, y = 0.015, 0.30
            if showMachine and Mc.mode == "instrument" then
                text(x, y, 0.42, "INSTRUMENT - dev lift rig (not a technology)", 255, 190, 60)
                y = y + 0.03
            elseif showMachine and Mc.model then
                local tel = Mc.tel or {}
                local prop = Mc.propellantLeft()
                text(x, y, 0.42, ("MACHINE %s"):format(Mc.name), 150, 210, 255)
                text(x, y + 0.025, 0.38, ("thrust %.1f kN | %d/6 axes"):format((tel.thrustN or 0) / 1000, Mc.axes or 0))
                if Mc.propCap > 0 then
                    local pct = prop / Mc.propCap
                    text(x, y + 0.047, 0.38, ("propellant %.0f kg (%d%%) | dv left %.0f m/s"):format(prop, math.floor(pct * 100), Mc.deltaVLeft()),
                        pct > 0.2 and 235 or 255, pct > 0.2 and 240 or 120, pct > 0.2 and 255 or 80)
                end
                local heat = Mc.state and Mc.state.heatK or 0
                local hot = heat > 0.8 * Mach.TEMP_LIMIT_K
                text(x, y + 0.069, 0.38, ("heat +%.0f / %d K%s | air %.3f kg/m3"):format(heat, Mach.TEMP_LIMIT_K, hot and " DERATING" or "", tel.rho or 0),
                    hot and 255 or 235, hot and 120 or 240, hot and 80 or 255)
                y = y + 0.095
                if Mc.flash and GetGameTimer() < Mc.flashUntil then
                    text(x, y, 0.45, Mc.flash, 255, 200, 60)
                    y = y + 0.03
                end
            end
            if showRace and R.active then
                local A = R.active
                local v = A.venue
                text(x, y + 0.01, 0.42, ("RACE %s"):format(v.name), 255, 220, 40)
                local tm = A.goT and ("%.1f s"):format(R.now() - A.goT) or "take gate 1 to start"
                text(x, y + 0.035, 0.38, ("lap %d/%d | next %s | %s"):format(math.max(1, A.timer.lap), v.course.laps,
                    v.course.gates[A.timer.next].id, tm))
                if A.local_ then
                    local g = v.course.gates[A.timer.next].centre
                    local d = math.sqrt((A.local_[1] - g[1]) ^ 2 + (A.local_[2] - g[2]) ^ 2 + (A.local_[3] - g[3]) ^ 2)
                    text(x, y + 0.057, 0.38, ("next gate %.0f m"):format(d))
                end
                if A.stationRange then
                    text(x, y + 0.079, 0.38, ("station %.1f km | closing %+.0f m/s | station alt %.0f m"):format(A.stationRange / 1000, A.closing or 0, A.stationAlt or 0), 150, 210, 255)
                end
            elseif showRace and R.result then
                text(x, y + 0.01, 0.42, "RESULT (physical = flown; simulated = the NPC field)", 255, 220, 40)
                for i, r in ipairs(R.result) do
                    if i > 12 then break end
                    text(x, y + 0.01 + i * 0.021, 0.34, ("P%d %s  %s  %s"):format(r.position, r.name or r.id,
                        r.state == "finished" and ("%.2f s"):format((r.finishMs or 0) / 1000) or (r.dnfReason or "dnf"), r.mode or ""),
                        r.mode == "physical" and 120 or 235, 240, r.mode == "physical" and 140 or 255)
                end
            end
        end
    end
end)
