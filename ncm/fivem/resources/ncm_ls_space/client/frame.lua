-- ncm_ls_space / client / frame: the Snowglobe reference frame (L320; doc 53 §5). Once Snowglobe owns you, NCM -- not
-- GTA -- integrates where you are and how you move.
--
--   * UNIVERSE STATE {u, w}: position and velocity in the Earth frame (`space.universe`, doubles), integrated here every
--     frame under NCM gravity -- radial toward the centre of a compressed Snowglobe Earth (`earthRadius`, about 1 g at
--     the surface) -- plus the NCM machine's acceleration (client/machine.lua; or the dev lift instrument).
--     Ballistic arcs and real orbits fall out of that.
--   * THE GTA BODY only PRESENTS it: GTA gravity off, its velocity set each frame to the universe velocity in local
--     axes, clamped at `presentCap` (GTA's ~150 m/s entity cap, §LS2). The universe velocity is separate and uncapped.
--   * FLOATING ORIGIN: the GTA body is kept in a local band [down, up] (and near x/y 0) by SERVER moves; the universe
--     state never moves. The local<->universe mapping is not stored -- it is whatever u says vs where the body is.
--   * THE FRAME FOLLOWS THE PLAYER, not the car (owner: "once NCM owns the scene, player and vehicle must remain in the
--     same local/universe reference frame"). Leave the car in Snowglobe and you keep its universe state, on foot.
--   * HOME: universe altitude below `homeAlt`, falling, over the Los Santos patch -> moved to your TRUE local position,
--     GTA gravity back. Anywhere else there is no surface yet (NCM Earth beyond the patch is not built): reaching the
--     ground there returns you above Los Santos and says so.
local Core = NcmCore
local U = Core.get("space.universe")
local V = U.vec
local C = NcmLsConfig

U.setWorld({ earthRadius = C.earthRadius, surfaceG = C.surfaceG })
local frame = U.anchorFrame(C.anchor)

NcmLsFrame = { active = false, u = nil, w = nil, alt = 0, gmag = C.surfaceG, uspeed = 0, hspeed = 0, vcirc = 0, kind = "" }
local F = NcmLsFrame

local coolUntil, lastSubject, lastReport = 0, 0, 0

local function say(fmt, ...)
    local line = fmt:format(...)
    print("[ncm_ls_space] " .. line)
    TriggerServerEvent("ncm:ls:report", line)
end

local function rebase(entity, x, y, z, why)
    TriggerServerEvent("ncm:ls:rebase", NetworkGetNetworkIdFromEntity(entity), x + 0.0, y + 0.0, z + 0.0, why)
    coolUntil = GetGameTimer() + C.rebaseCooldownMs
end

local function gtaGravity(entity, isVeh, on)
    if isVeh then SetVehicleGravity(entity, on) else SetEntityHasGravity(entity, on) end
end

CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local isVeh = veh ~= 0
        if isVeh and GetPedInVehicleSeat(veh, -1) ~= ped then goto continue end   -- passengers ride the driver's frame
        do
            local subject = isVeh and veh or ped
            local now, dt = GetGameTimer(), GetFrameTime()
            local p, v = GetEntityCoords(subject), GetEntityVelocity(subject)
            F.kind = isVeh and "vehicle" or "on foot"
            if F.active and subject ~= lastSubject and lastSubject ~= 0 then
                say("frame follows the player: now %s, universe altitude %.0f m kept", F.kind, F.alt)
            end
            lastSubject = subject

            if not F.active then
                if p.z >= C.up and v.z > 0 and now >= coolUntil and NetworkHasControlOfEntity(subject) then
                    F.u = U.cityToUniverse({ p.x, p.y, p.z }, C.anchor)
                    F.w = U.localToEarth(frame, { v.x, v.y, v.z })
                    F.active = true
                    rebase(subject, p.x, p.y, C.mid, "THROUGH THE DOORWAY")
                    say("THROUGH THE DOORWAY (%s): universe altitude %.0f m, speed %.1f m/s; NCM owns gravity from here", F.kind, U.altitude(F.u), V.len(F.w))
                end
            else
                -- forces: NCM gravity (radial, compressed Earth) + lift along the car's own up axis
                local a = U.gravity(F.u)
                local T, Mc = NcmLsThrust, NcmLsMachine
                if isVeh and Mc and Mc.mode == "machine" then
                    -- the NCM machine's own acceleration this frame (engineering.dynamics), already in east/north/up
                    a = V.add(a, U.localToEarth(frame, Mc.accLocal or { 0, 0, 0 }))
                elseif not isVeh and NcmLsEva then
                    -- on foot: the suit's EVA pack (client/eva.lua), already in east/north/up
                    a = V.add(a, U.localToEarth(frame, NcmLsEva.accLocal or { 0, 0, 0 }))
                elseif isVeh and T and (T.twr or 0) > 0 then
                    local _, _, up = GetEntityMatrix(veh)
                    a = V.add(a, V.scale(U.localToEarth(frame, { up.x, up.y, up.z }), T.twr * C.surfaceG))
                end
                U.integrate(F, a, dt)
                -- present: the GTA body follows the universe velocity, clamped at GTA's cap
                gtaGravity(subject, isVeh, false)
                local lv = U.earthToLocal(frame, F.w)
                local m = V.len(lv)
                if m > C.presentCap then lv = V.scale(lv, C.presentCap / m) end
                if NetworkHasControlOfEntity(subject) then SetEntityVelocity(subject, lv[1], lv[2], lv[3]) end

                -- readouts
                F.alt = U.altitude(F.u)
                local rhat = V.scale(F.u, 1 / V.len(F.u))
                local vr = V.dot(F.w, rhat)
                F.uspeed = V.len(F.w)
                F.hspeed = V.len(V.sub(F.w, V.scale(rhat, vr)))
                F.vcirc = U.circularSpeed(F.u)
                F.gmag = V.len(U.gravity(F.u))

                if now >= coolUntil then
                    local tl = U.universeToCity(F.u, C.anchor)
                    local overPatch = math.abs(tl[1]) < C.homePatch and math.abs(tl[2]) < C.homePatch
                    if F.alt < C.homeAlt and vr < 0 and overPatch then
                        F.active = false
                        gtaGravity(subject, isVeh, true)
                        rebase(subject, tl[1], tl[2], math.max(tl[3], 50.0), "HOME over Los Santos")
                        say("HOME: universe altitude %.0f m -> back at your true position over Los Santos (%.0f, %.0f, %.0f)", F.alt, tl[1], tl[2], tl[3])
                    elseif F.alt <= 30 then
                        F.active = false
                        gtaGravity(subject, isVeh, true)
                        F.w = { 0, 0, 0 }
                        rebase(subject, 0.0, 0.0, C.homeAlt, "NO SURFACE")
                        say("reached the ground of NCM Earth outside the Los Santos patch (%.0f, %.0f): no surface is built there yet -- returned above Los Santos", tl[1], tl[2])
                    elseif p.z > C.up or p.z < C.down or math.abs(p.x) > C.recenterXY or math.abs(p.y) > C.recenterXY then
                        local tx = math.abs(p.x) > C.recenterXY and 0.0 or p.x
                        local ty = math.abs(p.y) > C.recenterXY and 0.0 or p.y
                        rebase(subject, tx, ty, C.mid, "rebase")
                    end
                end
            end

            if now - lastReport >= C.logEveryMs and (F.active or p.z > 150) then
                lastReport = now
                TriggerServerEvent("ncm:ls:state", F.active, F.kind, p.z, F.active and F.alt or p.z, F.uspeed, F.hspeed, F.vcirc, F.gmag)
            end
        end
        ::continue::
    end
end)
