-- ncm_world / client / drivefx -- doc 58: what the experimental drives LOOK like from the driver's seat.
--
-- client/deep.lua flies the Machine; every Deep frame it hands this file the flight model and state. Thirty times a
-- second this sends the Deep page (web/deep.html -> web/deep/drivefx.js) what the drive layer needs:
--   drives   each drive's view (space.drives.view: state, progress, direction, bubble, wormhole mouths and mapping...)
--   carPc    where the Machine is among the stars (parsecs from the Sun, ICRF) -- the layer draws OUR catalogue from here
--   conv     an impulse stroke / a fusion burn in progress (they touch no stars: light and a jolt)
--   W, cam   for the NATIVE view: the rotation from the sky (ICRF) into the game's world at the held car (space.sky's
--            cockpit frame, G * Rz(-GMST)), and the game's own camera, measured (NcmGameCamera, KB-377)
-- and it asks for the native things only the game can do: the game's own star dome is hidden while a drive redraws the
-- whole sky (warp, an Alcubierre bubble, a jump's charge) and restored after; a jump and a wormhole crossing get a
-- native screen fade; an Alcubierre bubble's formation and collapse a server screen effect (`ncm:deep.drive.fx`).
-- Never authoritative, never able to end a flight: every call is guarded by deep.lua.
local Dr = NcmCore.get("space.drives")
local Sky = NcmCore.get("space.sky")
local A = NcmCore.get("space.astro")
local V = A.vec

local function log(fmt, ...) print(("[ncm_world/client/drivefx] " .. fmt):format(...)) end

NcmDriveFx = {}
local S = { sentAt = 0, camAt = 0, cam = nil, last = {}, domeHidden = false, fade = nil }
local SEND_MS, CAM_MS = 50, 100   -- 2026-10-12: the per-frame script budget (KB-369) -- 20 Hz scene, 10 Hz camera
local ROLL_SIGN = 1   -- NcmGameCamera's roll convention; flip if the layer rolls the wrong way in the cabin

local function anyRedraw(views)
    for _, v in ipairs(views) do
        if v.drive == "warp" and (v.state == "SPOOLING" or v.state == "ENGAGED" or v.state == "DISENGAGING") and (v.spool or 0) > 0.25 then return true end
        if v.drive == "alcubierre" and (v.state == "BUBBLE_STABLE" or v.state == "ENGAGED" or (v.state == "BUBBLE_FORMING" and (v.bubble or 0) > 0.3)) then return true end
        if v.drive == "jump" and v.state == "CHARGING" and (v.charge or 0) > 0.15 then return true end
    end
    return false
end

local function fadeBlink(holdMs)
    -- a native blackout across a discontinuity (screen.effects): out at once, back in over half a second
    local ok, id = pcall(Open77.screen.fadeOut, { durationMs = 60, timeoutMs = 4000 })
    if ok and id then
        CreateThread(function() Wait(holdMs or 180); pcall(Open77.screen.fadeIn, id, { durationMs = 520 }) end)
    end
end

local function moments(views)
    for _, v in ipairs(views) do
        local was = S.last[v.drive]
        if was ~= v.state then
            S.last[v.drive] = v.state
            if v.drive == "jump" and was == "CHARGING" and v.state == "ENGAGED" then fadeBlink(220) end
            if v.drive == "wormhole" and v.state == "ENGAGED" then fadeBlink(120) end
            if v.drive == "alcubierre" and v.state == "BUBBLE_FORMING" then TriggerServerEvent("ncm:deep.drive.fx", { kind = "distort", duration = 16 }) end
            if v.drive == "alcubierre" and was == "ENGAGED" and v.state == "DISENGAGING" then TriggerServerEvent("ncm:deep.drive.fx", { kind = "flash", duration = 2 }) end
            if v.drive == "jump" and v.state == "CHARGING" then TriggerServerEvent("ncm:deep.drive.fx", { kind = "charge", duration = 3 }) end
            log("%s: %s -> %s", tostring(v.drive), tostring(was), tostring(v.state))
        end
    end
end

--- Every Deep frame (rate-limited here). f = { page, m (flight model), dyn (dynamics state), s (Deep state: Earth-fixed
--- p, basis), utc, now, native (the native camera is showing), conv }
function NcmDriveFx.update(f)
    if not (f and f.page and f.m and f.dyn and f.utc) then return end
    if f.now - S.sentAt < SEND_MS then return end
    S.sentAt = f.now
    local views = Dr.view(f.m, f.dyn)
    local here = Dr.astro(f.dyn)
    local pc = V.scale(A.metres(here), 1 / A.PC)
    local far = V.len(pc) > 0.006   -- beyond ~1,250 AU the Sun is a star and the near stars have moved
    moments(views)
    -- the camera is measured (~10 projections) only while the layer draws something: a drive past OFF, a burn, the far sky
    local busy = false
    for _, v in ipairs(views) do
        if v.state ~= "OFF" and v.state ~= "COOLDOWN" and v.state ~= "FAILED" then busy = true end
        if v.wormhole then busy = true end
    end
    local active = busy or (f.conv and f.conv.method) or far
    local msg = { drives = views, carPc = pc, conv = f.conv, far = far, gmst = A.gmst(f.utc), native = f.native, rollSign = ROLL_SIGN }
    if f.native and active then
        local st = NcmDeepView and NcmDeepView.stage and NcmDeepView.stage() or nil
        if st then
            local G = Sky.frame(f.s, st.yaw)
            local W = Sky.mm(G, Sky.rz(-Sky.gmst(f.utc)))
            msg.W = { W[1][1], W[1][2], W[1][3], W[2][1], W[2][2], W[2][3], W[3][1], W[3][2], W[3][3] }
            -- the game's camera, measured (KB-377) -- but each measurement is ~10-20 native projections, so: at most 10 Hz,
            -- warm-started, and after a failure not again for 5 s. Meanwhile (and when it never converges) the camera is
            -- taken to look along the held car's heading, level (first person in an upright held car).
            if NcmGameCamera and f.now - S.camAt >= CAM_MS and f.now >= (S.camRetryAt or 0) then
                S.camAt = f.now
                local okC, cam = pcall(NcmGameCamera, { x = st.x, y = st.y, z = st.z }, S.cam and S.cam.yaw or math.rad(90 + (st.yaw or 0)), S.cam and S.cam.pitch or nil)
                if okC and cam then
                    S.cam = cam
                    if not S.camOk then S.camOk = true; log("game camera measured: yaw %.1f pitch %.1f fovY %.1f deg", math.deg(cam.yaw), math.deg(cam.pitch), math.deg(cam.fovY)) end
                else
                    S.cam, S.camRetryAt = nil, f.now + 5000
                    if not S.camWarned then S.camWarned = true; log("game camera unreadable: the drive layer assumes the held heading (retrying every 5 s)") end
                end
            end
            msg.cam = S.cam or { yaw = math.rad(90 + (st.yaw or 0)), pitch = 0, roll = 0, fovY = math.rad(70), assumed = true }
        end
        -- the game's own dome: hidden while the layer redraws the whole sky
        local hide = anyRedraw(views)
        if hide ~= S.domeHidden and NcmDeepView and NcmDeepView.hideDome then
            S.domeHidden = hide
            NcmDeepView.hideDome(hide)
            log("native star dome %s", hide and "hidden (the drive layer draws the sky)" or "restored")
        end
    end
    pcall(function() f.page:send("deep:drivefx", msg) end)
end

function NcmDriveFx.clear(page)
    if S.domeHidden and NcmDeepView and NcmDeepView.hideDome then NcmDeepView.hideDome(false) end
    S.domeHidden, S.last, S.cam = false, {}, nil
    if page then pcall(function() page:send("deep:drivefx", { drives = {} }) end) end
end
