-- ncm_ls_space / client / race: racing in Snowglobe (L321; doc 54 §G). The world comes from the SEED, not from a
-- script: `space.genesis` builds the same stations, venues, organisations, pilots and machines on every client and on
-- the server from `universeSeed`. The NPCs are already racing whether you come or not; `/ncm.race N` asks the server
-- (the authority) to start venue N's race. Rings: the NPC field arrives as a `paddock.sim` run you fly against.
-- Sprint and Fireball venues (L322): client/events.lua and server/events.lua, with NPCs at tactical fidelity.
--
--   sky ring       gates hung over a city at 350-650 m (fixed on Earth): fans and engines, no orbit needed
--   station ring   gates around an ORBITING station, in its co-moving frame (radial / along-track / orbit normal):
--                  to race there you must first reach its orbit and match it -- the HUD gives range and closing speed
--
-- Gates are crossed in their own course frame (`space.course.timer`), so a station's 180 m/s orbit does not matter to
-- the timing, only your motion relative to the ring. NPCs are drawn as ghosts along the line from the racestate model
-- (`paddock.racestate`); the race clock starts when YOU take gate 1. Your time is PHYSICAL, theirs SIMULATED, and the
-- classification says so.
local Core = NcmCore
local U = Core.get("space.universe")
local V = U.vec
local Seed = Core.get("world.seed")
local Gen = Core.get("space.genesis")
local Course = Core.get("space.course")
local Race = Core.get("space.racesim")
local RS = Core.get("paddock.racestate")
local Mach = Core.get("engineering.machine")
local C = NcmLsConfig

local frame = U.anchorFrame(C.anchor)
local world = Gen.generate(Seed.root(C.universeSeed):child("snowglobe"))
NcmLsRace = { world = world, active = nil, result = nil, resultUntil = 0 }
local R = NcmLsRace

local cloud0, gt0 = 0, 0
local function now()
    if cloud0 == 0 then cloud0, gt0 = GetCloudTimeAsInt(), GetGameTimer() end
    return (cloud0 - C.orbitEpoch) + (GetGameTimer() - gt0) / 1000
end
R.now = now

local function report(fmt, ...)
    local line = fmt:format(...)
    print("[ncm_ls_space] " .. line)
    TriggerServerEvent("ncm:ls:report", line)
end

local stationById = {}
for _, s in ipairs(world.stations) do stationById[s.id] = s end

--- The venue's course frame at time t (universe).
local function venueFrame(v, t)
    if v.kind == "sky_ring" then return Course.anchorFrame(v.anchor, v.altitudeM) end
    local pos, vel = Gen.orbitAt(stationById[v.stationId].orbit, t)
    return Course.lvlhFrame(pos, vel), pos, vel
end

--- The player's universe position and velocity, whichever regime they are in.
local function playerState()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local subject = veh ~= 0 and veh or ped
    local p = GetEntityCoords(subject)
    local F = NcmLsFrame
    if F and F.active and F.u then return F.u, F.w, p end
    local v = GetEntityVelocity(subject)
    return U.cityToUniverse({ p.x, p.y, p.z }, C.anchor), U.localToEarth(frame, { v.x, v.y, v.z }), p
end

--- Where to draw universe point w in GTA coordinates, from the body's GTA position p and universe position u.
local function drawPos(w, u, p)
    local d = U.earthToLocal(frame, V.sub(w, u))
    return p.x + d[1], p.y + d[2], p.z + d[3], V.len(d)
end

RegisterCommand("ncm.race", function(_, args)
    local a = args[1]
    if a == "off" then R.active = nil; report("race abandoned"); return end
    local n = tonumber(a)
    if not n then
        local Mc = NcmLsMachine
        report("Snowglobe seed %s: %d station(s), %d venue(s), %d organisations", C.universeSeed, #world.stations, #world.venues, #world.orgs)
        for i, v in ipairs(world.venues) do
            local mine = Mc and Mc.model and Race.estimate(Mc.model, v)
            local shape
            if v.course then
                shape = ("%d gates x %d laps, %.1f km"):format(#v.course.gates, v.course.laps, v.course.lengthM / 1000)
            elseif v.kind == "sprint" then
                shape = ("%s sprint, %d m, %d lanes"):format(v.style, v.distanceM, v.lanes)
            else
                shape = ("%d km of valid distance in a %.0f-%.0f m shell"):format(v.distanceM / 1000, v.inner, v.outer)
            end
            report("  %d. %s (%s%s) -- %s | your %s: %s", i, v.name, v.kind,
                v.altitudeM and (", " .. v.altitudeM .. " m") or "", shape,
                Mc and Mc.name or "machine", mine and (mine.eligible and ("eligible, est %.0f s"):format(mine.raceSec) or mine.reason) or "-")
        end
        report("  /ncm.race N to start one; /ncm.race off to stop")
        return
    end
    if not world.venues[n] then report("no venue %s", tostring(a)); return end
    local kind = world.venues[n].kind
    if kind == "sprint" or kind == "fireball" then NcmLsEnterEvent(n); return end
    TriggerServerEvent("ncm:ls:race:enter", n)
end, false)

RegisterNetEvent("ncm:ls:race:field", function(payload)
    local v = world.venues[payload.venue]
    if not v then return end
    local L = v.course.lengthM
    local model = RS.new({ points = { { x = 0, y = 0 }, { x = L, y = 0 } }, lengthM = L }, payload.entrants, payload.segments)
    R.active = { venue = v, venueIdx = payload.venue, raceNo = payload.raceNo, model = model, names = payload.names,
                 timer = Course.timer(v.course.gates, v.course.laps), prevLocal = nil, prevT = nil, entrants = payload.entrants }
    R.result = nil
    report("race %d at %s: %d NPC(s) on the grid (simulated), %d refused by physics; take gate 1 to start",
        payload.raceNo, v.name, #payload.entrants, payload.refused or 0)
end)

RegisterNetEvent("ncm:ls:race:result", function(rows)
    R.result, R.resultUntil = rows, GetGameTimer() + 20000
    for _, r in ipairs(rows) do
        report("  P%d %s %s %s", r.position, r.name or r.id, r.state == "finished" and ("%.3f s"):format((r.finishMs or 0) / 1000) or (r.dnfReason or "dnf"), r.mode)
    end
end)

local function circle(x, y, z, n, radius, cr, cg, cb)
    -- a ring of small spheres perpendicular to the gate normal n (GTA local axes)
    local a = { n[2], -n[1], 0 }
    if V.len(a) < 1e-3 then a = { 1, 0, 0 } end
    a = V.scale(a, 1 / V.len(a))
    local b = { n[2] * a[3] - n[3] * a[2], n[3] * a[1] - n[1] * a[3], n[1] * a[2] - n[2] * a[1] }
    local size = math.max(1.5, radius / 10)
    for k = 0, 15 do
        local th = k / 16 * 2 * math.pi
        local px = x + radius * (math.cos(th) * a[1] + math.sin(th) * b[1])
        local py = y + radius * (math.cos(th) * a[2] + math.sin(th) * b[2])
        local pz = z + radius * (math.cos(th) * a[3] + math.sin(th) * b[3])
        DrawMarker(28, px, py, pz, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, size, cr, cg, cb, 200, false, false, 2, false, nil, nil, false)
    end
end

CreateThread(function()
    while true do
        local A = R.active
        if not A then
            Wait(250)
        else
            Wait(0)
            local t = now()
            local v = A.venue
            local vf, sPos, sVel = venueFrame(v, t)
            local u, w, p = playerState()
            local lp = Course.toLocal(vf, u)
            -- timing, in the course's own frame
            if A.prevLocal then
                local ev = A.timer:update(A.prevLocal, lp, A.prevT, t)
                if ev and ev.started then report("GO at %s: the NPC field starts with you", v.name); A.goT = t
                elseif ev and ev.missed then report("missed %s by %.0f m", ev.missed, ev.missM - v.course.gates[1].radius)
                elseif ev and ev.finished then
                    report("FINISH %s: %.3f s (physical)", v.name, ev.ms / 1000)
                    TriggerServerEvent("ncm:ls:race:finish", A.raceNo, ev.ms)
                    R.active = nil
                end
            end
            A.prevLocal, A.prevT = lp, t
            if R.active then
                -- gates
                for i, g in ipairs(v.course.gates) do
                    local gw = Course.toWorld(vf, g.centre)
                    local x, y, z, d = drawPos(gw, u, p)
                    if d < C.raceDrawM then
                        local n = U.earthToLocal(frame, Course.dirToWorld(vf, g.normal))
                        local nxt = i == A.timer.next
                        circle(x, y, z, n, g.radius, nxt and 255 or 60, nxt and 220 or 200, nxt and 40 or 255)
                    end
                end
                -- NPC ghosts along the line, on the race clock
                if A.goT then
                    local ms = (t - A.goT) * 1000
                    for _, e in ipairs(A.entrants) do
                        local d = RS.distanceAt(A.model, e.id, ms)
                        if d then
                            local gw = Course.toWorld(vf, Race.pointAt(v.course, d))
                            local x, y, z, dist = drawPos(gw, u, p)
                            if dist < C.raceDrawM then
                                DrawMarker(28, x, y, z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 3.0, 255, 60, 200, 220, false, false, 2, false, nil, nil, false)
                            end
                        end
                    end
                end
                A.local_, A.stationRange, A.closing = lp, nil, nil
                if sPos then
                    local rel = V.sub(u, sPos)
                    A.stationRange = V.len(rel)
                    A.closing = -V.dot(V.sub(w, sVel), V.scale(rel, 1 / math.max(1, A.stationRange)))
                    A.stationAlt = U.altitude(sPos)
                end
            end
        end
    end
end)
