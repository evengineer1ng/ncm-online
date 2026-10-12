-- ncm_observer / client / observer -- the ghost's lens (doc 46, L307).
--
-- THE PANEL (client/panel.lua, F3): races, running order, cameras, director -- iRacing's replay controls without the
-- replay. It drives this file through `NcmObs`. Hotkeys while observing: 1-8 camera, PgUp/PgDn car, Home leader,
-- B battle, N director, H clean HUD (all rebindable in Settings -> KEY BINDINGS).
--
-- Commands (chat):
--   /ncm.observe on | off                       ask to enter (the server decides) / leave observer mode
--   /ncm.observe <race ..|racer ..|pos n|p6|leader|battle|auto>   what to watch
--   /ncm.cam <chase|far|drone|onboard|orbit|side|front|low>       the racer-relative shot
--   /ncm.cam next                               the next shot in that list
--   /ncm.cam clean                              toggle the gameplay HUD off (letterbox) for capture
--
-- THE LENS: one scripted camera, moved every frame from the target car's frame (`character.frame{vehicleId}`: local
-- position and the entity's own axes) through the pure `observer.director` shot table. While the car lives only in
-- the Paddock model (no vehicle in this game yet), the lens hangs over its model point from the 2 s racer snapshot,
-- and the body goes there so the bubble brings the car in.
-- THE BODY: invisible, non-solid (server) and flying (noclip, here). The world streams around the body, a scripted
-- camera refuses past 250 m, and the bubble materialises cars around player positions, so the body leapfrogs
-- (`observer.director.leapfrog`) ahead of the car with a short local teleport; long jumps are the server's.
local D = NcmCore.get("observer.director")
local function log(fmt, ...) print(("[ncm_observer] " .. fmt):format(...)) end

local on, target, mode = false, nil, "chase"
local cam, camFov = nil, nil
local snap = nil
local clean = false
local st = { hops = 0, jumps = 0, refusals = 0, src = "none" }
local lastHop, lastJumpAsk, lastRefusalLog = 0, 0, 0
local lastPos, travel = nil, nil

NcmObs = NcmObs or {}
local function changed() if NcmObs.onChange then pcall(NcmObs.onChange) end end

local function say(text)
    if not (NcmObs.toast and NcmObs.toast(tostring(text))) then
        if not pcall(Open77.hud.notify, "OBSERVER  " .. tostring(text)) then log("%s", tostring(text)) end
    end
    log("%s", tostring(text))
end

local function nowMs() return GetGameTimer() end

local function seated()
    local ok, seat = pcall(Open77.vehicles.getPlayerSeat)
    return ok and seat ~= nil
end

local function body()
    local ok, f = pcall(Open77.character.frame)
    if ok and type(f) == "table" and type(f.position) == "table" then return f.position end
    local ok2, s = pcall(Open77.character.state)
    if ok2 and type(s) == "table" and type(s.position) == "table" then return s.position end
    return nil
end

local function release()
    if cam then
        pcall(Open77.camera.deactivate)
        pcall(Open77.camera.destroy, cam)
    end
    cam, camFov = nil, nil
end

local function setClean(v)
    clean = v
    local ok, r, why = pcall(Open77.hud.setCinematic, v)
    if not (ok and r ~= false) then log("setCinematic(%s) refused: %s", tostring(v), tostring(ok and why or r)) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Where the target is this frame
-- ---------------------------------------------------------------------------------------------------------------

local function targetCar()
    if not (target and snap) then return nil end
    return D.findCar(snap, target.raceId, target.key)
end

-- Returns pos, forward, right, src, veh  (src = "frame" | "replicated" | "model")
local function locate()
    local car = targetCar()
    if not car then return nil end
    if car.v then
        local okF, f = pcall(Open77.character.frame, { vehicleId = car.v })
        if okF and type(f) == "table" and type(f.position) == "table" and type(f.forward) == "table" then
            local fw = { x = f.forward.x, y = f.forward.y, z = 0 }
            local l = math.sqrt(fw.x * fw.x + fw.y * fw.y)
            if l > 1e-3 then fw.x, fw.y = fw.x / l, fw.y / l end
            return f.position, fw, { x = fw.y, y = -fw.x, z = 0 }, "frame", car
        end
        local okV, v = pcall(Open77.vehicles.get, car.v)
        if okV and type(v) == "table" and type(v.position) == "table" then
            local fw, rt = D.basis(v.orientation, travel)
            return v.position, fw, rt, "replicated", car, v
        end
    end
    local p = { x = car.x, y = car.y, z = car.z or 0 }
    local fw, rt = D.basis(nil, travel)
    return p, fw, rt, "model", car
end

-- ---------------------------------------------------------------------------------------------------------------
-- The lens, every frame
-- ---------------------------------------------------------------------------------------------------------------

local function refused(what, why)
    st.refusals = st.refusals + 1
    if nowMs() - lastRefusalLog > 5000 then
        lastRefusalLog = nowMs()
        log("%s refused (%d so far): %s", what, st.refusals, tostring(why))
    end
end

local function frame()
    local pos, fw, rt, src = locate()
    st.src = src or "none"
    -- the car left the snapshot (finished, retired, race over): give the view back rather than freeze on a road
    if not pos then if cam then release(); changed() end return end
    if lastPos then
        local dx, dy = pos.x - lastPos.x, pos.y - lastPos.y
        if dx * dx + dy * dy > 0.04 then travel = { x = dx, y = dy } end
    end
    lastPos = { x = pos.x, y = pos.y, z = pos.z }

    -- the body: a model car may be anywhere, so ask the server for a settling jump; a physical one gets a short hop
    local b = body()
    if b then
        local dx, dy = b.x - pos.x, b.y - pos.y
        local far = math.sqrt(dx * dx + dy * dy)
        if far > 240 then
            if nowMs() - lastJumpAsk > 4000 then
                lastJumpAsk = nowMs(); st.jumps = st.jumps + 1
                TriggerServerEvent("ncm:observer:jump")
            end
            release()          -- a scripted camera refuses past 250 m; wait for the body
            return
        end
        if nowMs() - lastHop > 250 then
            local n = D.leapfrog(b, pos, fw)
            if n then
                lastHop = nowMs()
                local ok, r, why = pcall(Open77.travel.teleport, n.x, n.y, n.z)
                if ok and r ~= false then st.hops = st.hops + 1 else refused("hop", ok and why or r) end
            end
        end
    end

    local mo = (src == "model") and "drone" or mode
    local shot = D.shot(mo, pos, fw, rt, nowMs() / 1000)
    if not cam then
        local okC, id, why = pcall(Open77.camera.create, { position = shot.pos, lookAt = shot.look, fov = shot.fov })
        if not (okC and id) then refused("camera.create", okC and why or id); return end
        local okA, act, whyA = pcall(Open77.camera.activate, id)
        if not (okA and act) then
            refused("camera.activate", okA and whyA or act)
            pcall(Open77.camera.destroy, id)
            return
        end
        cam, camFov = id, shot.fov
        log("lens up: %s on %s (%s)", mo, tostring(target and target.name), src)
        return
    end
    if camFov ~= shot.fov then
        pcall(Open77.camera.setTransform, cam, { position = shot.pos, fov = shot.fov })
        camFov = shot.fov
    else
        pcall(Open77.camera.setTransform, cam, shot.pos)
    end
    pcall(Open77.camera.lookAt, cam, shot.look)
end

CreateThread(function()
    while true do
        if on and target then
            local ok, err = pcall(frame)
            if not ok then refused("frame", err) end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- every 10 s: what the lens is doing, to the server log (instrument every hop)
CreateThread(function()
    while true do
        Wait(10000)
        if on then
            local car = targetCar()
            local out = { mode = mode, target = target and target.name or "none", src = st.src, cam = cam and "up" or "down",
                hops = st.hops, jumps = st.jumps, refusals = st.refusals }
            if car and car.v then
                local ok, v = pcall(Open77.vehicles.get, car.v)
                if ok and type(v) == "table" then
                    out.gear, out.rpm = v.gear, v.rpm and math.floor(v.rpm) or nil
                    out.thr, out.kph = v.throttle and math.floor(v.throttle * 100) / 100 or nil, v.speedKph and math.floor(v.speedKph) or nil
                end
            end
            TriggerServerEvent("ncm:observer:status", out)
        end
    end
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Server events
-- ---------------------------------------------------------------------------------------------------------------

RegisterNetEvent("ncm:paddock:racers", function(s)
    if type(s) == "table" and type(s.races) == "table" then snap = s; changed() end
end)

RegisterNetEvent("ncm:observer:say", function(text) say(text) end)

-- the Paddock team this player manages (server/main.lua `teamOf`): its drivers are marked wherever they race
local team = nil
RegisterNetEvent("ncm:observer:team", function(t)
    if type(t) == "table" then team = t; changed() end
end)
CreateThread(function()
    Wait(8000)
    TriggerServerEvent("ncm:observer:team.ask")
    while true do                  -- a roster changes at the Cup boundary; a slow refresh keeps the marks honest
        Wait(300000)
        TriggerServerEvent("ncm:observer:team.ask")
    end
end)

-- armed by the console or an allowed request: confirm only on foot (the server sets the mode on this reply)
RegisterNetEvent("ncm:observer:armed", function()
    if seated() then say("Step out of the car first, then ENTER OBSERVER again (F3)."); return end
    TriggerServerEvent("ncm:observer:enter")
end)

RegisterNetEvent("ncm:observer:mode", function(m)
    on = type(m) == "table" and m.on == true
    local ok, r, why = pcall(Open77.travel.setNoclip, on)
    if not (ok and r ~= false) then log("setNoclip(%s) refused: %s", tostring(on), tostring(ok and why or r)) end
    if on then
        st = { hops = 0, jumps = 0, refusals = 0, src = "none" }
        say("Observer ON. F3 opens the panel · Y finds your team · N lets the director choose.")
        TriggerServerEvent("ncm:observer:team.ask")
    else
        target = nil
        release()
        if clean then setClean(false) end
        say("Observer OFF.")
    end
    changed()
end)

RegisterNetEvent("ncm:observer:target", function(t)
    if t == false or type(t) ~= "table" then target = nil; release(); changed(); return end
    local moved = not target or target.key ~= t.key or target.raceId ~= t.raceId
    target = t
    if moved then lastPos, travel = nil, nil end
    changed()
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------------------------

RegisterCommand("ncm.observe", function(_, args)
    local text = table.concat(args or {}, " ")
    if text == "on" then
        if on then say("Already observing."); return end
        if seated() then say("Step out of the car first."); return end
        TriggerServerEvent("ncm:observer:ask")
    elseif text == "off" then
        TriggerServerEvent("ncm:observer:exit")
    elseif not on then
        say("Not observing. /ncm.observe on")
    elseif text == "" then
        say(("Watching %s, %s shot."):format(target and tostring(target.name) or "nothing", mode))
    else
        TriggerServerEvent("ncm:observer:watch", text)
    end
end, false)

RegisterCommand("ncm.cam", function(_, args)
    local m = tostring(args and args[1] or ""):lower()
    if not on then say("Not observing."); return end
    if m == "clean" then setClean(not clean); changed(); return end
    if m == "next" then
        for i, x in ipairs(D.MODES) do if x == mode then m = D.MODES[i % #D.MODES + 1] break end end
    end
    for _, x in ipairs(D.MODES) do
        if x == m then
            mode = m
            say("Shot: " .. m)
            changed()
            return
        end
    end
    say("Shots: " .. table.concat(D.MODES, " ") .. " · next · clean")
end, false)

-- ---------------------------------------------------------------------------------------------------------------
-- What the panel (client/panel.lua) drives
-- ---------------------------------------------------------------------------------------------------------------
function NcmObs.isOn() return on end
function NcmObs.team() return team end
function NcmObs.askTeam() TriggerServerEvent("ncm:observer:team.ask") end
function NcmObs.target() return target end
function NcmObs.mode() return mode end
function NcmObs.isClean() return clean end
function NcmObs.snapshot() return snap end
function NcmObs.carOf(t) return t and snap and D.findCar(snap, t.raceId, t.key) or nil end
function NcmObs.setMode(m)
    for _, x in ipairs(D.MODES) do if x == m then mode = m; changed(); return true end end
    return false
end
function NcmObs.toggleClean() setClean(not clean); changed() end
function NcmObs.watch(text) if on then TriggerServerEvent("ncm:observer:watch", text) end end
function NcmObs.enter()
    if on then return end
    if seated() then say("Step out of the car first, then enter Observer."); return end
    TriggerServerEvent("ncm:observer:ask")
end
function NcmObs.exit() if on then TriggerServerEvent("ncm:observer:exit") end end

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_observer" then return end
    release()
    if on then pcall(Open77.travel.setNoclip, false) end
    if clean then pcall(Open77.hud.setCinematic, false) end
end)
