-- ncm_ls_space / client / events: racing Snowglobe's own disciplines with the NPC field and other players
-- (L322 + L323; doc 54 §L-§O, §S).
--
-- `/ncm.race N` on a Sprint or Fireball venue opens or joins that venue's event on the server. The server sends the
-- field (players in the first lanes, then NPCs) and the venue in UNIVERSE coordinates. This client then:
--   * presents every NPC -- and, away from the city frame, every OTHER PLAYER -- as a local car placed each frame from
--     the server's universe states (10 Hz, extrapolated by velocity) through `drawPos`. In Snowglobe each client has
--     its own floating origin, so another player's real GTA car is at the wrong place for me: it is hidden and its
--     universe state drawn instead. At a city-frame venue (the vertical sprint) real networked cars are right and
--     are left alone;
--   * syncs its clock with the server (min round trip of 5 pings, again every 10 s) and stamps every sample it sends
--     in SERVER time, so a photo finish between two players is fair;
--   * reports CONTACT between its own car and an NPC car (touching, closing faster than 2 m/s); the server checks it
--     against the race and turns it into physics;
--   * runs the five lights from the server's lights time, and the HUD.
local Core = NcmCore
local U = Core.get("space.universe")
local SP = Core.get("space.sprint")
local V = U.vec
local C = NcmLsConfig

local frame = U.anchorFrame(C.anchor)
NcmLsEvent = nil
local E

local function report(fmt, ...)
    local line = fmt:format(...)
    print("[ncm_ls_space] " .. line)
    TriggerServerEvent("ncm:ls:report", line)
end
RegisterNetEvent("ncm:ls:say", function(text) print("[ncm_ls_space] " .. tostring(text)) end)

local function myVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    return veh ~= 0 and veh or nil, ped
end

local function playerUniverse()
    local veh, ped = myVehicle()
    local subject = veh or ped
    local p, v = GetEntityCoords(subject), GetEntityVelocity(subject)
    local F = NcmLsFrame
    if F and F.active and F.u then return F.u, F.w, p, subject end
    return U.cityToUniverse({ p.x, p.y, p.z }, C.anchor), U.localToEarth(frame, { v.x, v.y, v.z }), p, subject
end

local function drawPos(w, u, p)
    local d = U.earthToLocal(frame, V.sub(w, u))
    return p.x + d[1], p.y + d[2], p.z + d[3], V.len(d)
end

-- ------------------------------------------------------------------------------------------ clock
local clock = { offset = nil, rtt = nil, samples = {}, last = 0 }
local function clientS() return GetGameTimer() / 1000 end
local function serverNow() return clientS() + (clock.offset or 0) end
local function syncClock()
    clock.samples = {}
    for _ = 1, 5 do
        TriggerServerEvent("ncm:ls:ev:ping", clientS())
        Wait(120)
    end
end
RegisterNetEvent("ncm:ls:ev:pong", function(sent, serverT)
    clock.samples[#clock.samples + 1] = { clientSend = sent, serverT = serverT, clientRecv = clientS() }
    if #clock.samples >= 5 then
        local off, rtt = SP.clockOffset(clock.samples)
        if off then
            clock.offset, clock.rtt = off, rtt
            TriggerServerEvent("ncm:ls:ev:clock", off, rtt)
        end
    end
end)

-- ------------------------------------------------------------------------------------------ cars
local function cleanup()
    if E then
        for _, n in pairs(E.cars) do if n.veh and DoesEntityExist(n.veh) then DeleteEntity(n.veh) end end
    end
    E, NcmLsEvent = nil, nil
end

function NcmLsEnterEvent(vi)
    cleanup()
    local Mc = NcmLsMachine
    TriggerServerEvent("ncm:ls:ev:enter", vi, Mc and Mc.name or C.machine)
end

RegisterCommand("ncm.quit", function()
    if E then TriggerServerEvent("ncm:ls:ev:quit"); report("left %s", E.info.name) end
    cleanup()
end, false)

local function spawnCar(n, i)
    local model = joaat(C.npcModels[(i - 1) % #C.npcModels + 1])
    RequestModel(model)
    local t0 = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t0 < 3000 do Wait(0) end
    local veh = CreateVehicle(model, 0.0, 0.0, -100.0, 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityInvincible(veh, true)
    SetVehicleGravity(veh, false)
    SetEntityCollision(veh, true, true)
    SetVehicleEngineOn(veh, true, true, false)
    n.veh = veh
end

local function cityFrameVenue(info) return info.kind == "sprint" and info.style == "vertical" end

RegisterNetEvent("ncm:ls:ev:field", function(info)
    local keep = E and E.info.eventId == info.eventId and E or nil
    if not keep then cleanup() end
    E = keep or { cars = {}, phase = "grid", me = {}, lastSample = 0, touching = {} }
    E.info = info
    NcmLsEvent = E
    local i = 0
    for _, n in pairs(E.cars) do i = math.max(i, n.idx) end
    for _, f in ipairs(info.field) do
        if f.me then
            E.lane = f.lane
        elseif not f.player or not cityFrameVenue(info) then
            -- NPCs always; other players only where their real car would be in the wrong place for me
            if not E.cars[f.id] then
                i = i + 1
                E.cars[f.id] = { id = f.id, name = f.name, player = f.player, serverId = f.serverId, idx = i }
            end
        end
    end
    for _, s in ipairs(info.npcs or {}) do
        if E.cars[s.id] then E.cars[s.id].s, E.cars[s.id].at = s, GetGameTimer() end
    end
    local Ev = E
    CreateThread(function()
        for _, n in pairs(Ev.cars) do if not n.veh then spawnCar(n, n.idx) end end
    end)
    if not keep then
        CreateThread(syncClock)
        if info.kind == "sprint" then
            local l = U.universeToCity(info.mySpot, C.anchor)
            SetNewWaypoint(l[1], l[2])
        end
    end
    local players = 0
    for _, f in ipairs(info.field) do if f.player then players = players + 1 end end
    if info.kind == "sprint" then
        report("%s: %d player(s), %d NPC(s); your lane %d is waypointed -- stop on its marker for the lights. Finish plane %d m up.",
            info.name, players, #info.field - players, E.lane or 1, info.distanceM)
    else
        report("%s: %d player(s), %d NPC(s) on the grid %.0f m up; shell %.0f-%.0f m; %d km of valid distance. Reach the grid for the lights.",
            info.name, players, #info.field - players, U.altitude(info.grid), info.inner - U.BODIES.earth.radius,
            info.outer - U.BODIES.earth.radius, info.distanceM / 1000)
    end
end)

RegisterNetEvent("ncm:ls:ev:lights", function(startT, t0S)
    if not E then return end
    E.startT, E.t0S, E.phase = startT, t0S, "racing"
end)

RegisterNetEvent("ncm:ls:ev:state", function(t, npcs, me, remotes)
    if not E then return end
    local now = GetGameTimer()
    for _, s in ipairs(npcs) do
        local n = E.cars[s.id]
        if n then n.s, n.at = s, now end
    end
    for _, s in ipairs(remotes or {}) do
        local n = E.cars[s.id]
        if n and s.y and s.z then n.s, n.at = { p = s.p, v = s.v, y = s.y, z = s.z, st = "racing" }, now end
    end
    E.me = me or E.me
end)

RegisterNetEvent("ncm:ls:race:result", function() cleanup() end)

local function circle(x, y, z, nrm, radius, cr, cg, cb, count)
    local a = { nrm[2], -nrm[1], 0 }
    if V.len(a) < 1e-3 then a = { 1, 0, 0 } end
    a = V.scale(a, 1 / V.len(a))
    local b = { nrm[2] * a[3] - nrm[3] * a[2], nrm[3] * a[1] - nrm[1] * a[3], nrm[1] * a[2] - nrm[2] * a[1] }
    count = count or 24
    for k = 0, count - 1 do
        local th = k / count * 2 * math.pi
        DrawMarker(28, x + radius * (math.cos(th) * a[1] + math.sin(th) * b[1]), y + radius * (math.cos(th) * a[2] + math.sin(th) * b[2]),
            z + radius * (math.cos(th) * a[3] + math.sin(th) * b[3]), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, cr, cg, cb, 200, false, false, 2, false, nil, nil, false)
    end
end

local function rotationFrom(yU, zU)
    local f, up = U.earthToLocal(frame, yU), U.earthToLocal(frame, zU)
    local right = { f[2] * up[3] - f[3] * up[2], f[3] * up[1] - f[1] * up[3], f[1] * up[2] - f[2] * up[1] }
    local yaw = math.deg(math.atan(-f[1], f[2]))
    local pitch = math.deg(math.asin(math.max(-1, math.min(1, f[3]))))
    local roll = math.deg(math.asin(math.max(-1, math.min(1, -right[3]))))
    return pitch, roll, yaw
end

local function bodyAxes(veh)
    local fwd, _, up = GetEntityMatrix(veh)
    return U.localToEarth(frame, { fwd.x, fwd.y, fwd.z }), U.localToEarth(frame, { up.x, up.y, up.z })
end

CreateThread(function()
    while true do
        if not E then
            Wait(250)
        else
            Wait(0)
            local E = E
            if not E then goto continue end
            local now = GetGameTimer()
            local u, w, p = playerUniverse()
            local veh = myVehicle()
            -- samples to the authority at 20 Hz, stamped in server time; resync the clock every 10 s
            if now - E.lastSample >= 50 then
                E.lastSample = now
                local y, z
                if veh then y, z = bodyAxes(veh) end
                TriggerServerEvent("ncm:ls:ev:sample", serverNow(), u, w, y, z)
            end
            if E.phase == "racing" and now - clock.last > 10000 then clock.last = now; CreateThread(syncClock) end
            -- cars: NPCs and remote players from universe states
            for _, n in pairs(E.cars) do
                if n.veh and n.s and DoesEntityExist(n.veh) then
                    local dt = (now - n.at) / 1000
                    local up = V.add(n.s.p, V.scale(n.s.v, math.min(dt, 0.5)))
                    local x, y, z, d = drawPos(up, u, p)
                    if d < C.raceDrawM then
                        SetEntityCoordsNoOffset(n.veh, x, y, z, false, false, false)
                        local lv = U.earthToLocal(frame, n.s.v)
                        SetEntityVelocity(n.veh, lv[1], lv[2], lv[3])
                        local pi_, ro, ya = rotationFrom(n.s.y, n.s.z)
                        SetEntityRotation(n.veh, pi_, ro, ya, 2, false)
                        if d < 400 then
                            SetDrawOrigin(x, y, z + 2.5, 0)
                            SetTextScale(0.3, 0.3); SetTextFont(4); SetTextCentre(true); SetTextOutline()
                            BeginTextCommandDisplayText("STRING")
                            AddTextComponentSubstringPlayerName(n.name .. (n.s.st ~= "racing" and (" - " .. tostring(n.s.st)) or ""))
                            EndTextCommandDisplayText(0.0, 0.0)
                            ClearDrawOrigin()
                        end
                        -- contact: my car touching this NPC car and closing faster than 2 m/s
                        if veh and not n.player and E.phase == "racing" then
                            local touching = IsEntityTouchingEntity(veh, n.veh)
                            if touching and not E.touching[n.id] then
                                local rel = V.len(V.sub(w, n.s.v))
                                if rel > 2 then TriggerServerEvent("ncm:ls:ev:contact", n.id, w) end
                            end
                            E.touching[n.id] = touching or nil
                        end
                    else
                        SetEntityCoordsNoOffset(n.veh, 0.0, 0.0, -100.0, false, false, false)
                    end
                    -- the remote player's real car is in the wrong place in my frame: hide it, and never collide with it
                    if n.player and n.serverId then
                        local pl = GetPlayerFromServerId(n.serverId)
                        if pl and pl ~= -1 then
                            local rv = GetVehiclePedIsIn(GetPlayerPed(pl), false)
                            if rv ~= 0 then
                                SetEntityLocallyInvisible(rv)
                                if veh then SetEntityNoCollisionEntity(veh, rv, true) end
                            end
                        end
                    end
                end
            end
            -- the grid and the finish
            local info = E.info
            if info.kind == "sprint" then
                local f = info.frame
                local sx, sy, sz = drawPos(info.mySpot, u, p)
                if E.phase == "grid" then
                    DrawMarker(1, sx, sy, sz - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.0, 6.0, 1.5, 255, 220, 40, 160, false, false, 2, false, nil, nil, false)
                end
                local centre = V.add(f.origin, V.scale(f.y, info.distanceM))
                local fx, fy, fz = drawPos(centre, u, p)
                circle(fx, fy, fz, U.earthToLocal(frame, f.y), (info.lanes + 1) * 6, 255, 255, 255, 36)
            end
            ::continue::
        end
    end
end)

-- ------------------------------------------------------------------------------------------ the HUD
local function text(x, y, scale, s, r, g, b)
    SetTextFont(4); SetTextScale(scale, scale); SetTextColour(r or 235, g or 240, b or 255, 230); SetTextOutline()
    BeginTextCommandDisplayText("STRING"); AddTextComponentSubstringPlayerName(s); EndTextCommandDisplayText(x, y)
end

CreateThread(function()
    while true do
        if not E then
            Wait(250)
        else
            Wait(0)
            local E = E
            if not E then goto continue end
            local info = E.info
            local x, y = 0.40, 0.04
            text(x, y, 0.5, info.name:upper() .. (info.kind == "sprint" and "  -  SPRINT" or "  -  FIREBALL"), 255, 220, 40)
            if clock.rtt then text(x + 0.33, y + 0.005, 0.3, ("clock %+.3f s / rtt %d ms"):format(clock.offset, math.floor(clock.rtt * 1000)), 150, 150, 150) end
            if E.phase == "grid" then
                local u = playerUniverse()
                local target = info.kind == "sprint" and info.mySpot or info.grid
                text(x, y + 0.035, 0.4, ("to the grid: %.0f m%s"):format(V.len(V.sub(u, target)),
                    info.kind == "fireball" and (" | grid altitude %.0f m"):format(U.altitude(target)) or (" | lane %d"):format(E.lane or 1)))
            elseif E.t0S then
                local t = serverNow() - E.t0S
                if t < E.startT then
                    local lit = math.min(5, math.floor(t / (E.startT / 5)) + 1)
                    for k = 1, 5 do
                        local on = k <= lit
                        DrawRect(0.42 + (k - 1) * 0.04, 0.12, 0.03, 0.05, on and 230 or 40, on and 20 or 40, on and 20 or 40, 230)
                    end
                elseif t < E.startT + 1.5 then
                    text(0.46, 0.09, 1.0, "GO", 80, 255, 120)
                end
                local me = E.me or {}
                if info.kind == "fireball" then
                    local ahead = 0
                    for _, n in pairs(E.cars) do if n.s and (n.s.c or 0) > (me.c or 0) then ahead = ahead + 1 end end
                    text(x, y + 0.035, 0.4, ("valid %.2f / %d km | P%d | altitude %.0f (shell %.0f-%.0f) | plane %.2f%s"):format(
                        (me.c or 0) / 1000, info.distanceM / 1000, ahead + 1, (me.r or 0) - U.BODIES.earth.radius,
                        info.inner - U.BODIES.earth.radius, info.outer - U.BODIES.earth.radius, me.coh or 0,
                        (me.oob or 0) > 0 and (" | OUT OF BOUNDS %.1f s"):format(me.oob) or ""))
                else
                    text(x, y + 0.035, 0.4, ("%.1f s | to the line %.0f m"):format(math.max(0, t - E.startT), info.distanceM - (me.y or 0)))
                end
            end
            ::continue::
        end
    end
end)
