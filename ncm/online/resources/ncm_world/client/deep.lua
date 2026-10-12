-- ncm_world / client / deep -- L326: the Machine out of REDengine's reach, in NCM's own real-scale universe.
--
-- Climb through the enter height (game z, server-configured; development only) and the screen whites out: the server
-- freezes the car, and this file flies it -- core `space.deep` (real-scale Earth, inverse-square gravity, Night City at
-- 35.37 N 120.85 W), the Machine's OWN installed components and bindings (client/engineering.lua's state: one Machine,
-- one tank), drawn in a full-screen WebUI surface (web/deep.html, WebGL; §DP0 proved it on the GPU at 60 fps).
-- Fall back through the exit height and it whites out again: the server puts the car where you are (clamped to the
-- map when you came down far away) and releases it, and the Carrier gives the velocity back (capped).
--
-- NOT PHYSICAL, AND SAID SO ON SCREEN: the DEV ATTITUDE RIG (sticks turn the car; no installed component makes torque
-- yet). `/ncm.deep.rig` turns it off. Returning speed is capped by the Carrier's pulse (~80 m/s on a 1.8 t car).
--
-- KB-61: closing never depends on the page. `/ncm.deep.home` always brings you back over Night City.
local Core = NcmCore
local Deep = Core.get("space.deep")
local Install = Core.get("engineering.installation")
local Controls = Core.get("engineering.controls")
local Guid = Core.get("space.guidance")
local Canon = Core.get("space.canonical")   -- L329: the host-independent Deep record
local Flight = Core.get("engineering.flightmodel")   -- L331: the full machine model
local Venues = Core.get("space.venues")
local GeoLod = Core.get("space.geolod")   -- L332: which real imagery the Deep page holds
local Dyn = Core.get("engineering.dynamics")
local Drives = Core.get("space.drives")   -- doc 58: the experimental propulsion stable
local Travel = Core.get("space.travel")
local Fx = Core.get("presentation.fx")   -- NCM FX: physics -> native effects (client/fx.lua draws)
-- KB-375 (owner, 2026-10-07: "cant have ksa opening way before you know its there ... a consent screen saying that there is
-- a deeper simulation layer and activating it ... on demand when approaching the border of ncm deep"): nothing about KSA is
-- asked, probed or launched until the player consents, approaching the border. `consent` nil = not asked yet, true =
-- activate, false = stay in Deep. `ready` = KSA started and proved a placement (the activation). L329's AC rule, for KSA.
local KSA_ASK_ETA_S = 600   -- ask ~10 min out, so KSA is ready on arrival; arrival without it holds there and asks again
local KSA = { consent = nil, ask = false, activating = false, ready = false, why = nil, embodying = false, holdL3 = nil, dev = nil, devAt = 0 }

--- L334: what Guidance can be pointed at: the KSA border (Earth's sphere of influence) first, then the Earth venues
local TARGETS = nil
local function targets()
    if not TARGETS then
        -- L351/L352: KSA is retired from the player path; the border is no longer a Guidance target
        TARGETS = {}
        for _, v in ipairs(Venues.VENUES) do TARGETS[#TARGETS + 1] = v end
    end
    return TARGETS
end
local Json = Core.get("vocabulary.json")

local function log(fmt, ...) print(("[ncm_world/client/deep] " .. fmt):format(...)) end
local function ms() return GetGameTimer() end

local MASS_KG = 1800            -- the Hella's physics body as the Carrier measures it (thrust log: mass=1800 kg)
local RIG_RATE = 1.1            -- rad/s at full stick
local MAP = { xmin = -6500, xmax = 6500, ymin = -8500, ymax = 5000 }   -- where a returning car may be put down
local RETURN_DV_MAX = 80        -- m/s: 150 kN x 1 s on 1.8 t (the Carrier's clamp)
local GROUND_M = 300            -- KB-349: Deep has no terrain; below this the trip ends (home over Night City)
local EXIT_SAFE_M = 3000        -- KB-349: a return from lower than this comes home at the bound, at rest

local cfg = { enabled = false, enterZ = 12000, exitZ = 11500, ascentZ = 4000, maskNearM = 9000, maskFarM = 16000, ascentProbe = false,
    ringOnZ = 1500, ringFarM = 6000 }
--- NCM's one clock on this client: the server's UTC at config time, advanced by the game timer
local utcBase, utcAtMs = nil, 0
local function utcNow() return utcBase and (utcBase + (GetGameTimer() - utcAtMs) / 1000) or nil end
-- doc 57 §5.4: the Deep page draws the SAME universe NCM flies in -- the Sun, the Moon, the planets and the naked-eye stars
-- come from space.catalogue (positions Earth-centred, Earth-fixed, the page's frame). A host without the substrate
-- falls back to space.deep's sun, as before.
local SkyOk, Astro, Cat, BrightStars = pcall(function()
    return NcmCore.get("space.astro"), NcmCore.get("space.catalogue"), NcmCore.get("space.data.brightstars")
end)
if not SkyOk then Astro, Cat, BrightStars = nil, nil, nil end
--- Every catalogued body except home and barycentres, Earth-centred Earth-fixed metres (the page's frame).
local function catalogueBodies(utc)
    if not (Astro and Cat) then return nil end
    Cat.load()
    local home
    for _, r in ipairs(Cat.list()) do if r.home then home = r end end
    local Rh = Cat.stateAt(home, utc)
    local out = {}
    for _, rec in ipairs(Cat.list()) do
        if not rec.home and rec.kind ~= "barycentre" then
            local e = Astro.eciToEcefVec(Astro.delta(Cat.stateAt(rec, utc), Rh), utc)
            out[#out + 1] = { id = rec.id, name = rec.name, kind = rec.kind, p = e, r = rec.radius or 0 }
        end
    end
    return out
end
local sunCache = { u = nil, d = nil }
local function sunNow()
    local u = utcNow()
    if u and sunCache.u and math.abs(u - sunCache.u) < 1 then return sunCache.d end   -- the Sun moves 0.004 deg/s here
    if u and Astro and Cat then
        local ok, d = pcall(function()
            Cat.load()
            local home
            for _, r in ipairs(Cat.list()) do if r.home then home = r end end
            return Astro.vec.unit(Astro.eciToEcefVec(Astro.delta(Cat.stateAt("sun", u), Cat.stateAt(home, u)), u))
        end)
        if ok and d then sunCache.u, sunCache.d = u, d; return d end
    end
    return u and Deep.sunAt(u) or Deep.sun(13)
end
local ASC = nil                 -- the ascent page (transparent Deep, before the seam): { page, ready }
local A = nil                   -- the active flight
local GD                        -- the guidance computer (below); exit() resets it
local samples = {}              -- recent { t, x, y, z } of the car, for a velocity at the handoff
local rig = true
local camMode = 1
-- L352: "native" first -- the car in the game's own world (client/deepview.lua); the WebGL views stay for scale
local CAM_NAMES = { "native", "chase", "high", "earth" }

NcmClientDeepActive = false

local function seat()
    local okS, s = pcall(Open77.vehicles.getPlayerSeat)
    if not okS or type(s) ~= "table" then return nil end
    return s.vehicleId or s.vehicle or s.id
end

local function down(c)
    local okC, cap = pcall(Open77.input.isCaptured)
    if okC and cap == true then return false end
    local ok, d = pcall(Open77.input.isDown, c)
    return ok and d == true
end

local function axis(n)
    local ok, v = pcall(Open77.input.axis, n)
    return ok and type(v) == "number" and v or 0
end

local function dead(v) return math.abs(v) < 0.15 and 0 or v end

-- ------------------------------------------------------------------------------------------------ the page
local function send(kind, payload) if A and A.page then pcall(function() A.page:send(kind, payload) end) end end

-- L332: GEOGRAPHIC LOD. Core space.geolod plans the clipmap for the camera's ground point (twice a second) and, every two
-- seconds, the tiles along the predicted path and at Guidance's destination; the page fetches them through the host
-- bridge. The page reports its WORLD layer's internal height (it changes with the dynamic render scale) and its field
-- of view, so the plan asks for no more geography than the pixels can show. Resolution never reaches the simulation.
-- KB-368: Open77 runs client scripts under a per-frame budget. Planning the PREFETCH inside the flight frame exceeded it
-- (23:48, "geolod.lua: script execution budget exceeded"), the flight frame threw and Deep dropped the Machine over Night
-- City. So: the frame only plans the clipmap (a few dozen operations), guarded so geography can never end a flight; the
-- prefetch runs in its own thread, one predicted point per frame.
local GEO = { planAt = 0, prefetchAt = 0, heightPx = 693, fovY = 1.0, job = nil, busy = false }
local function geoTick(page, st, now, dest)
    if not page or not st or not st.p or now - GEO.planAt < 500 then return end
    GEO.planAt = now
    local ok, err = pcall(function()
        local lat, lon, alt = Deep.ecefToLla(st.p)
        local view = { fovY = GEO.fovY, heightPx = GEO.heightPx }
        local plan = GeoLod.plan(lat, lon, math.max(1, alt), view)
        page:send("deep:tiles", { zFine = plan.zFine, levels = plan.levels, credit = GeoLod.credit(plan) })
        if now - GEO.prefetchAt >= 3000 and not GEO.busy then
            GEO.prefetchAt = now
            GEO.job = { page = page, view = view, pts = GeoLod.prefetchPoints({ p = st.p, v = st.v or { 0, 0, 0 } }, dest) }
        end
    end)
    if not ok then log("geography skipped this tick: %s", tostring(err)) end
end
CreateThread(function()
    while true do
        Wait(100)
        local job = GEO.job
        if job then
            GEO.job, GEO.busy = nil, true
            local list = {}
            for _, pt in ipairs(job.pts) do
                Wait(0)   -- one point per frame
                local ok, tiles = pcall(GeoLod.prefetchAt, pt, job.view)
                if ok then for _, t in ipairs(tiles) do list[#list + 1] = t end end
            end
            Wait(0)
            if #list > 0 then pcall(function() job.page:send("deep:tiles", { prefetch = list }) end) end
            GEO.busy = false
        end
    end
end)
--- the page's own reports: its render view, and the probes (WebGL facts, whether tiles arrive) -- logged once each
local function watchPage(page)
    pcall(function()
        page:on("deep:view", function(v)
            if type(v) ~= "table" then return end
            GEO.heightPx, GEO.fovY = tonumber(v.h) or GEO.heightPx, tonumber(v.fov) or GEO.fovY
            GEO.planAt = 0
        end)
        page:on("deep:probe", function(v)
            local ok, txt = pcall(Json.encode, v)
            print("[ncm_world/client/deep] RENDER PROBE " .. (ok and txt or tostring(v)))
            TriggerServerEvent("ncm:deep.render", ok and txt or tostring(v))
        end)
        page:on("deep:error", function(v)
            local ok, txt = pcall(Json.encode, v)
            print("[ncm_world/client/deep] PAGE ERROR " .. (ok and txt or tostring(v)))
        end)
    end)
end

local function closePage(page)
    if not page then return end
    CreateThread(function()
        Wait(1600)   -- let the white-out finish
        pcall(function() page:hide() end)
        pcall(function() page:destroy() end)
    end)
end

-- ------------------------------------------------------------------------------------------------ in and out
local function velocity()
    if #samples < 2 then return 0, 0, 0 end
    local a, b = samples[1], samples[#samples]
    local dt = (b.t - a.t) / 1000
    if dt <= 0 then return 0, 0, 0 end
    return (b.x - a.x) / dt, (b.y - a.y) / dt, (b.z - a.z) / dt
end

--- L329: checkpoint the canonical record to the NCM server (1 Hz in Deep, and at every transition). The server owns
--- where the Machine is; this host only flies it while it embodies it.
local function checkpoint(place, transition, locationId)
    if not A then return end
    local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
    local rec = Canon.fromDeep(A.s, 0, { asset = A.asset, massKg = A.mass, devices = EN and EN.devices or {},
        devState = EN and EN.state or nil, fuelKg = EN and EN.fuelKg or nil, devFuel = NcmClientDevFuel == true,
        devHeat = NcmClientDevHeat == true, devAttitude = NcmClientDevAttitude == true, host = "cyberpunk",
        vehicleKey = EN and EN.vehicleKey or "archer_hella", dyn = A.dyn and Flight.carry(A.dyn, true) or nil,   -- doc 58: compact
        guidance = (GD and GD.route) and { venueId = GD.route.venue.id, engaged = GD.engaged == true } or nil })
    -- doc 58 (2026-10-12 10:07): the record goes as ONE JSON string. As a table, every save that held a drive activation
    -- in progress (a jump charging, a wormhole open) was silently dropped by the net serializer; the server took the
    -- Machine over from a stale copy.
    local okJ, js = pcall(Json.encode, rec)
    if okJ then
        TriggerServerEvent("ncm:canonical.save", { place = place or "deep", json = js, transition = transition == true, locationId = locationId })
    else
        log("checkpoint not encoded (%s): sent as a table", tostring(js))
        TriggerServerEvent("ncm:canonical.save", { place = place or "deep", rec = rec, transition = transition == true, locationId = locationId })
    end
end

local function enter(vid, pos, why, resumeRec)
    if A then return end
    local vx, vy, vz = velocity()
    local okF, f = pcall(Open77.character.frame, { vehicleId = vid })
    local axes = okF and type(f) == "table" and f or nil
    -- the ascent page is already showing the planet: it BECOMES Deep (no second page, no white-out)
    local ok, page, reason, seamless = true, nil, nil, false
    if ASC and ASC.page and ASC.ready then page, seamless = ASC.page, true; ASC = nil
    else
        if ASC and ASC.page then pcall(function() ASC.page:destroy() end); ASC = nil end
        ok, page, reason = pcall(Open77.webui.create, { entry = "web/deep.html", layer = "hud", zIndex = 950,
            transparent = true, visible = true, fps = 60 })   -- L352: the native view shows through it
    end
    if not ok or not page then log("could not open the deep surface (%s %s): staying in Night City", tostring(page), tostring(reason)); return end
    if not seamless then watchPage(page) end
    local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
    local asset = NcmClientEngineering and select(1, NcmClientEngineering.bound()) or nil
    A = {
        -- L329: a canonical record (resumed from NCM) wins over the game pose: the Machine continues, it does not restart
        vid = vid, page = page, s = resumeRec and Canon.toDeep(resumeRec) or Deep.enter({ pos.x, pos.y, pos.z }, { vx, vy, vz }, axes),
        resumeDyn = resumeRec and resumeRec.dyn or nil,
        mass = MASS_KG + Install.addedMassKg(EN and EN.devices or {}), startedAt = ms(), last = ms(),
        lastSend = 0, lastImpact = 0, lastTele = 0, impact = "?", report = { kg = 0, pulses = 0, since = ms() },
        asset = asset, camHeld = false, thrustN = 0,
    }
    NcmClientDeepActive = true
    local function init()
        local hour = 13
        local vs = {}
        for _, v in ipairs(Venues.VENUES) do vs[#vs + 1] = { id = v.id, name = v.name, region = v.region, lat = v.lat, lon = v.lon } end
        send("deep:init", { nc = Deep.ORIGIN, R = Deep.R, sun = sunNow(), sprite = "deep/sprites/machine.png", earth = "deep/earth.jpg", venues = vs })
        -- doc 57 §5.4: the real naked-eye sky (Hipparcos, ICRF directions); the page turns it by sidereal time
        if BrightStars then send("deep:sky", { stars = BrightStars, source = "Hipparcos (ESA, van Leeuwen 2007)" }) end
    end
    if seamless then send("deep:mode", { mode = "deep" }); init() else page:on("deep:ready", init) end
    local codes = {}
    for _, d in ipairs(EN and EN.devices or {}) do codes[#codes + 1] = d.code end
    TriggerServerEvent("ncm:deep.enter", { vx = vx, vy = vy, vz = vz, mass = A.mass, devices = codes })
    if resumeRec and resumeRec.guidance and resumeRec.guidance.engaged and resumeRec.guidance.venueId then
        local v = Venues.get(resumeRec.guidance.venueId)
        if v then GD.route = Guid.plan(A.s, v); GD.engaged = true; GD.msg = "Guidance resumed: " .. v.name end
    end
    checkpoint("deep", true)
    log("ENTER (%s) at game (%.0f, %.0f, %.0f) v (%.1f, %.1f, %.1f) m/s | mass %.0f kg | devices %d",
        why, pos.x, pos.y, pos.z, vx, vy, vz, A.mass, EN and #EN.devices or 0)
    do   -- KB-437: the Machine as it crosses -- tanks, heat, and which control drives which part
        local d, b = {}, {}
        for _, x in ipairs(EN and EN.devices or {}) do
            local st = EN.state and EN.state.dev and EN.state.dev[x.componentId] or {}
            d[#d + 1] = ("%s %s ..%s %.0f K%s"):format(x.code, x.kind, tostring(x.componentId):sub(-6), st.heatK or 0, st.hot and " HOT" or "")
        end
        for _, x in ipairs(EN and EN.bindings or {}) do b[#b + 1] = ("%s:%s->..%s.%s"):format(x.control, x.gesture, tostring(x.componentId):sub(-6), x.command) end
        log("ENTER Machine: fuel %.1f kg fusion %.1f kg | %s | controls %s", EN and EN.fuelKg or 0, EN and EN.fusionKg or 0,
            #d > 0 and table.concat(d, " | ") or "no devices", #b > 0 and table.concat(b, ", ") or "none")
    end
end

local function exit(why, home)
    if not A then return end
    local lat, lon, alt = Deep.ecefToLla(A.s.p)
    -- KB-349: a return from low down (guidance let go near the ground) went back at game z -2,431, under Night City.
    -- Below EXIT_SAFE_M it comes home over Night City at the bound, at rest, like the held-B return.
    if not home and alt < EXIT_SAFE_M then home = true end
    if home then lat, lon, alt = Deep.ORIGIN.lat, Deep.ORIGIN.lon, cfg.exitZ end
    checkpoint("surface", true, "night_city")
    GD.engaged, GD.prompt, GD.route, GD.hold = false, nil, nil, nil
    local x, y = Deep.llaToGame(lat, lon, alt)
    local clamped = false
    if x < MAP.xmin or x > MAP.xmax or y < MAP.ymin or y > MAP.ymax then
        x, y = math.max(MAP.xmin, math.min(MAP.xmax, x)), math.max(MAP.ymin, math.min(MAP.ymax, y))
        clamped = true
    end
    local vEnu = home and { 0, 0, 0 } or Deep.ecefToEnu(A.s.v, lat, lon)
    local fEnu = Deep.ecefToEnu(A.s.basis.forward, lat, lon)
    local yaw = math.deg((math.atan2 or math.atan)(-fEnu[1], fEnu[2]))
    local landKm = Deep.distance(lat, lon, Deep.ORIGIN.lat, Deep.ORIGIN.lon) / 1000
    send("deep:leave", {})
    if NcmDeepView then pcall(NcmDeepView.clear) end
    if NcmDriveFx then pcall(NcmDriveFx.clear, A.page) end
    TriggerServerEvent("ncm:deep.exit", { x = x, y = y, z = math.min(alt, cfg.exitZ), yaw = yaw, clamped = clamped, landKm = landKm, why = why })
    log("EXIT (%s) at %.4f, %.4f alt %.0f -> game (%.0f, %.0f)%s, %.1f km from Night City | v ENU (%.1f, %.1f, %.1f) | %.0f s out",
        why, lat, lon, alt, x, y, clamped and " CLAMPED" or "", landKm, vEnu[1], vEnu[2], vEnu[3], (ms() - A.startedAt) / 1000)
    A.returning = { v = vEnu, asset = A.asset, vid = A.vid, mass = A.mass }
    local page = A.page
    local ret = A.returning
    A = nil
    closePage(page)
    -- the velocity comes back after the server's release (ncm:deep.released)
    NcmClientDeepPending = ret
end

RegisterNetEvent("ncm:deep.released", function()
    local r = NcmClientDeepPending
    NcmClientDeepPending = nil
    CreateThread(function()
        Wait(2000)   -- the server's move re-binds the car (SEAM-1b: ~3 s of lease churn); a pulse before that is dropped
        NcmClientDeepActive = false
        samples = {}
        if not r or not NcmClientMachineWrench then return end
        local v = r.v
        local mag = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
        local k = mag > RETURN_DV_MAX and RETURN_DV_MAX / mag or 1
        local F = { r.mass * v[1] * k, r.mass * v[2] * k, r.mass * v[3] * k }
        local sent = NcmClientMachineWrench({ v = 1, assetId = r.asset, vehicleId = tostring(r.vid), fx = 0, fy = 0, fz = 0, ttlMs = 150,
            supersedeLift = false, pulse = { seq = ms(), fx = F[1], fy = F[2], fz = F[3], ms = 1000 } })
        log("velocity back: %.1f of %.1f m/s through the Carrier (pulse %s)", mag * k, mag, tostring(sent))
    end)
end)

--- L329: joining while canonically in Deep (or at another host's place): the server has put the Hella back in the world
--- at the bound with you in it; Deep continues from the record -- you are not sent home.
RegisterNetEvent("ncm:deep.resumeCanonical", function(m)
    if type(m) ~= "table" or type(m.rec) ~= "table" then return end
    CreateThread(function()
        local vid = tonumber(m.vid)
        for _ = 1, 100 do
            if tonumber(seat()) == vid then break end
            Wait(100)
        end
        if tonumber(seat()) ~= vid then log("RESUME refused: not seated in %s", tostring(vid)); return end
        local okV, v = pcall(Open77.vehicles.get, vid)
        local p = okV and type(v) == "table" and v.position or { x = 0, y = 0, z = 12100 }
        while not cfg.enabled do Wait(500) end
        -- KB-361: the Machine's parts arrive a few seconds after it does (16:37: "devices 0", nothing could hold it up).
        -- The car is frozen meanwhile; Deep resumes with its propulsors, or after 20 s without (said so).
        for _ = 1, 200 do
            local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
            if EN and EN.devices and #EN.devices > 0 then break end
            Wait(100)
        end
        local EN0 = NcmClientEngineering and NcmClientEngineering.get() or nil
        if not (EN0 and EN0.devices and #EN0.devices > 0) then log("RESUME without delivered components (20 s): the Machine cannot hold itself up") end
        enter(vid, p, m.prompt and ("canonical: at " .. m.prompt) or "canonical: in Deep", m.rec)
        if A and m.prompt then
            local venue = Venues.get(m.prompt)
            if venue then GD.route = Guid.plan(A.s, venue); GD.prompt = venue end
        end
    end)
end)

--- L329: the adapter's state, and what to do after consent (continue the descent the player asked for).
RegisterNetEvent("ncm:deep.adapter.state", function(m)
    if type(m) ~= "table" then return end
    GD.acEnabled = m.enabled == true
    GD.msg = m.message
    if m.enabled and m.venue and A then
        local v = Venues.get(m.venue)
        if v then requestEmbodiment(v) end
    end
end)

--- L330: the Racing Week reset reaches Deep too: out of Deep, home; the server wakes you at the loop spawn.
RegisterNetEvent("ncm:deep.loop", function()
    if A then
        GD.msg = "Racing Week reset. Reconstruction reloading in Night City."
        exit("the Racing Week reset", true)
    end
    if ASC and ASC.page then pcall(function() ASC.page:destroy() end); ASC = nil end
end)

RegisterNetEvent("ncm:deep.schedule", function(m)
    if type(m) == "table" and targets()[GD.sel] and m.venue == targets()[GD.sel].id then GD.schedule = m.items end
end)

-- ------------------------------------------------------------------------------------------------ config + watch
RegisterNetEvent("ncm:deep.config", function(c)
    if type(c) ~= "table" then return end
    cfg.enabled, cfg.enterZ, cfg.exitZ = c.enabled == true, tonumber(c.enterZ) or cfg.enterZ, tonumber(c.exitZ) or cfg.exitZ
    -- the development server takes care of fuel (owner, 2026-10-06): nothing burns, the parts never starve
    NcmClientDevFuel = c.devFuel == true   -- L341: only the server says so, and never on Online
    if tonumber(c.utc) then utcBase, utcAtMs = tonumber(c.utc), GetGameTimer() end
    cfg.ascentZ = tonumber(c.ascentZ) or cfg.ascentZ
    cfg.maskNearM, cfg.maskFarM = tonumber(c.maskNearM) or cfg.maskNearM, tonumber(c.maskFarM) or cfg.maskFarM
    cfg.ascentProbe = c.ascentProbe == true
    cfg.ringOnZ, cfg.ringFarM = tonumber(c.ringOnZ) or cfg.ringOnZ, tonumber(c.ringFarM) or cfg.ringFarM
    -- and no part overheats (owner, 2026-10-06: dev heat waiver, IDEA-1143)
    NcmClientDevHeat = c.devHeat == true
    NcmClientDevAttitude = c.devAttitude == true   -- L331: the labelled attitude waiver (development only)
    log("deep handoff %s (out at game z %d climbing, back at %d)", cfg.enabled and "ENABLED" or "off", cfg.enterZ, cfg.exitZ)
end)

CreateThread(function()
    Wait(12000)
    TriggerServerEvent("ncm:deep.config.request")
    while true do
        if cfg.enabled and not A and not NcmClientDeepActive then
            local vid = seat()
            local okV, v = pcall(Open77.vehicles.get, vid)
            local p = okV and type(v) == "table" and v.position or nil
            if vid and p and p.z then
                samples[#samples + 1] = { t = ms(), x = p.x, y = p.y, z = p.z }
                while #samples > 4 do table.remove(samples, 1) end
                local _, _, vz = velocity()
                if p.z >= cfg.enterZ and vz > 2 then enter(vid, p, "climbed through the bound") end
            else
                samples = {}
            end
        end
        Wait(100)
    end
end)

-- ------------------------------------------------------------------------------------------------ the flight
--- L327: ask for the physical representation of the place below (Assetto Corsa). The server relays it to the local host
--- bridge; the Machine's canonical state goes with it so the embodiment arrives in the air, moving.
function requestEmbodiment(v)
    if not A then return end
    local lat, lon, alt = Deep.ecefToLla(A.s.p)
    local vEnu = Deep.ecefToEnu(A.s.v, lat, lon)
    local fEnu = Deep.ecefToEnu(A.s.basis.forward, lat, lon)
    local uEnu = Deep.ecefToEnu(A.s.basis.up, lat, lon)
    local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
    TriggerServerEvent("ncm:deep.embody.request", {
        venue = v.id, layout = v.layouts[1], lat = lat, lon = lon, alt = alt, venueAlt = v.alt or 0,
        v = vEnu, forward = fEnu, up = uEnu, asset = A.asset, mass = A.mass, vehicleKey = EN and EN.vehicleKey or "archer_hella",
        devAttitude = NcmClientDevAttitude == true, devFuel = NcmClientDevFuel == true, devHeat = NcmClientDevHeat == true,
        fuelKg = EN and EN.fuelKg or nil,
        -- the Machine's parts and bindings, so the embodiment can express them as forces at their mounts
        devices = (function()
            local out = {}
            for _, d in ipairs(EN and EN.devices or {}) do
                out[#out + 1] = { componentId = d.componentId, code = d.code, kind = d.kind, axis = d.axis, pos = d.pos,
                    perf = d.perf, thermal = d.thermal, massKg = d.massKg }   -- L329/L331: the whole design: AC's Deep builds the same machine
            end
            return out
        end)(),
        bindings = EN and EN.bindings or {},
    })
    A.embodyPending = v.id
    GD.msg = "Asking for Assetto Corsa: " .. v.name .. "..."
    log("EMBODY request: %s at %.4f, %.4f alt %.0f m, v ENU (%.0f, %.0f, %.0f)", v.id, lat, lon, alt, vEnu[1], vEnu[2], vEnu[3])
end

--- Back from Assetto Corsa: the Machine climbed out of the venue. Deep resumes above that place with its vertical and
--- horizontal speed (heading in AC is the track's own frame, not geography: an expression loss).
RegisterNetEvent("ncm:deep.resume", function(r)
    if not A or type(r) ~= "table" then return end
    local v = Venues.get(tostring(r.venue or A.embodied or ""))
    if not v then return end
    local alt = (v.alt or 0) + (tonumber(r.height) or 2500)
    A.s.p = Deep.llaToEcef(v.lat, v.lon, alt)
    local e, n, u = Deep.enu(v.lat, v.lon)
    local up, hz = tonumber(r.up) or 0, tonumber(r.horizontal) or 0
    A.s.v = Deep.vec.add(Deep.vec.scale(u, up), Deep.vec.scale(n, hz))
    A.s.basis = { right = e, forward = n, up = u }
    A.s.frame, A.s.ip, A.s.iv, A.s.ibasis = nil, nil, nil, nil   -- doc 57: a state set here is Earth-fixed
    A.embodied = nil
    A.last = ms()
    GD.msg = ("Back in NCM Deep above %s. Guidance (D-pad up) for the next place."):format(v.name)
    log("RESUME from Assetto Corsa above %s at %.0f m, up %.0f m/s, horizontal %.0f m/s", v.id, alt, up, hz)
end)

--- What is racing below, from the server's race world, and what the embodiment host said.
RegisterNetEvent("ncm:deep.embody.status", function(st)
    if type(st) ~= "table" then return end
    local race = st.family and ("%s race, %s, lap %s/%s%s"):format(tostring(st.family):gsub("_", " "), tostring(st.phase), tostring(st.lap or 0),
        tostring(st.laps or 0), (st.top and st.top[1]) and (", leading: " .. tostring(st.top[1])) or "") or "nothing racing right now"
    local msg = ("%s at %02d:%02d local: %s. Assetto Corsa: %s"):format(tostring(st.venue), math.floor(tonumber(st.localHour) or 0),
        math.floor(((tonumber(st.localHour) or 0) % 1) * 60), race, tostring(st.ac))
    log("EMBODY status: %s", msg)
    -- only an OPENED host takes the Machine; a refusal leaves it flying in Deep
    if A and A.embodyPending and st.ac == "adapter_not_enabled" then
        GD.consent = Venues.get(A.embodyPending)
        A.embodyPending = nil
        return
    end
    if A and A.embodyPending then
        if st.ac == "opening" then A.embodied = A.embodyPending end
        A.embodyPending = nil
    end
    if NcmClientDeepSetMessage then NcmClientDeepSetMessage(msg) end
end)

-- ------------------------------------------------------------------------------------------------ KB-377: the game's camera
--- The REAL game camera, measured: Open77.camera.project gives where a world point lands on screen (0..1), so aim at a far
--- point until it sits at the screen centre (Newton on yaw/pitch), then read the field of view and roll from how the screen
--- moves per radian there. Points are 100 km out, so the camera's few metres from the car do not matter. ~14 projections.
--- Returns { yaw, pitch, roll, fovX, fovY } (radians; yaw from +x towards +y, pitch up positive) or nil.
-- the first climb measured nothing at 100 km ("unmeasured" on every line): try nearer points, and log the raw answer once
local CAM_TRY = { 100000, 20000, 3000, 500 }
local CAM_D, camDumped = nil, false
local function camRaw(o, yaw, pitch, d)
    local cp = math.cos(pitch)
    return pcall(Open77.camera.project, { x = o.x + d * cp * math.cos(yaw), y = o.y + d * cp * math.sin(yaw), z = o.z + d * math.sin(pitch) })
end
local function camProject(o, yaw, pitch)
    for _, d in ipairs(CAM_D and { CAM_D } or CAM_TRY) do
        local ok, r = camRaw(o, yaw, pitch, d)
        if not camDumped then
            local parts = {}
            if type(r) == "table" then for k, v in pairs(r) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
            else parts[1] = tostring(r) end
            log("ASCENT PROBE camera.project at %d m: ok=%s %s {%s}", d, tostring(ok), type(r), table.concat(parts, " "))
        end
        if ok and type(r) == "table" and tonumber(r.x) and tonumber(r.y) then
            if not CAM_D then CAM_D = d; log("ASCENT PROBE camera measured with points %d m out", d) end
            camDumped = true
            -- a point BEHIND the camera (depth < 0) projects mirrored: the second climb locked on to the wrong side
            return tonumber(r.x), tonumber(r.y), tonumber(r.depth) or 1
        end
    end
    camDumped = true
    return nil
end
function NcmGameCamera(o, yaw0, pitch0)
    local yaw, pitch, e = yaw0 or 0, pitch0 or -0.05, 0.01
    local iters = 6
    if pitch0 then
        iters = 2   -- warm start from the last frame's camera (it moves little in 1/15 s)
    else
        -- start IN FRONT of the camera: of the car's heading and the other three quarters, the one most squarely ahead
        local best
        for q = 0, 3 do
            local _, _, dep = camProject(o, yaw0 + q * math.pi / 2, pitch)
            if dep and dep > 0 and (not best or dep > best) then yaw, best = yaw0 + q * math.pi / 2, dep end
        end
        if not best then return nil end
    end
    local jx, jy
    for _ = 1, iters do
        local x, y, dep = camProject(o, yaw, pitch)
        local xa, ya = camProject(o, yaw + e, pitch)
        local xb, yb = camProject(o, yaw, pitch + e)
        if not (x and xa and xb) or (dep or 1) <= 0 then return nil end
        local a, b, c, d = (xa - x) / e, (xb - x) / e, (ya - y) / e, (yb - y) / e
        local det = a * d - b * c
        if math.abs(det) < 1e-9 then return nil end
        local ex, ey = 0.5 - x, 0.5 - y
        local dy, dp = (d * ex - b * ey) / det, (-c * ex + a * ey) / det
        local step = math.max(math.abs(dy), math.abs(dp))
        if step > 0.5 then dy, dp = dy * 0.5 / step, dp * 0.5 / step end   -- never jump past the camera's side
        yaw, pitch = yaw + dy, math.max(-1.5, math.min(1.5, pitch + dp))
        jx, jy = { a, c }, { b, d }
    end
    local xc, yc = camProject(o, yaw, pitch)
    if not xc or math.abs(xc - 0.5) > 0.01 or math.abs(yc - 0.5) > 0.01 then return nil end   -- did not converge: say so
    -- at the centre: screen x per radian of yaw = 1 / (2 tan(fovX/2)); roll tilts the yaw motion off the screen's x axis
    local sx = math.sqrt(jx[1] * jx[1] + jx[2] * jx[2]) / math.max(1e-6, math.cos(pitch))
    local sy = math.sqrt(jy[1] * jy[1] + jy[2] * jy[2])
    return { yaw = yaw, pitch = pitch, roll = math.atan(-jx[2], -jx[1]), fovX = 2 * math.atan(1 / (2 * sx)), fovY = 2 * math.atan(1 / (2 * sy)) }
end

-- ------------------------------------------------------------------------------------------------ the ascent (visual)
-- The authority seam stays at enterZ. The VISUAL takeover starts at ascentZ: a transparent Deep page over REDengine draws
-- NCM's Earth beyond maskNearM..maskFarM from the camera, fading in with altitude, anchored to the same Earth frame as
-- Deep, Guidance and the venues (space.deep.ORIGIN). At the seam that page becomes Deep.
CreateThread(function()
    Wait(14000)
    while true do
        Wait(33)
        if cfg.enabled and not A and not NcmClientDeepActive then
            local vid = seat()
            local okV, v = pcall(Open77.vehicles.get, vid)
            local p = vid and okV and type(v) == "table" and v.position or nil
            if p and p.z and p.z >= cfg.ascentZ then
                if not ASC then
                    local okP, page = pcall(Open77.webui.create, { entry = "web/deep.html", layer = "hud", zIndex = 950,
                        transparent = true, visible = true, fps = 60 })
                    if okP and page then
                        watchPage(page)
                        ASC = { page = page, ready = false }
                        local mine = ASC
                        page:on("deep:ready", function()
                            pcall(function() page:send("deep:init", { ascent = true, probe = cfg.ascentProbe, nc = Deep.ORIGIN, R = Deep.R, sun = sunNow(),
                                sprite = "deep/sprites/machine.png", earth = "deep/earth.jpg", venues = {} }) end)
                            mine.ready = true
                        end)
                        log("ASCENT overlay on at game z %.0f (Deep at %d)", p.z, cfg.enterZ)
                    end
                elseif ASC.ready then
                    local okF, f = pcall(Open77.character.frame, { vehicleId = vid })
                    local s = Deep.enter({ p.x, p.y, p.z }, { 0, 0, 0 }, okF and type(f) == "table" and f or nil)
                    local k = math.max(0, math.min(1, (p.z - cfg.ascentZ) / math.max(1, cfg.enterZ - cfg.ascentZ)))
                    -- IDEA-1174: the GAME's camera, read live (Open77.camera.project), so our Earth lands where the game's
                    -- own world band is instead of under a guessed chase camera; the guess remains only as the fallback
                    local now = GetGameTimer()
                    if now - (ASC.camAt or 0) >= 66 then
                        ASC.camAt = now
                        local la0, lo0 = Deep.ecefToLla(s.p)
                        local okC, cam = pcall(NcmGameCamera, p, ASC.cam and ASC.cam.yaw or (function()
                            local e0, n0 = Deep.enu(la0, lo0)
                            return math.atan(Deep.vec.dot(s.basis.forward, n0), Deep.vec.dot(s.basis.forward, e0)) end)(), ASC.cam and ASC.cam.pitch or nil)
                        if okC and cam then
                            local cy, sy, cp, sp = math.cos(cam.yaw), math.sin(cam.yaw), math.cos(cam.pitch), math.sin(cam.pitch)
                            ASC.cam = cam
                            ASC.camF = Deep.vec.unit(Deep.enuToEcef({ cp * cy, cp * sy, sp }, la0, lo0))
                            ASC.camU = Deep.vec.unit(Deep.enuToEcef({ -sp * cy, -sp * sy, cp }, la0, lo0))
                            if now - (ASC.camLogAt or 0) >= 5000 then
                                ASC.camLogAt = now
                                log("ASCENT CAMERA z %.0f | yaw %.1f pitch %.2f fovY %.1f fovX %.1f deg (the game's own)", p.z, math.deg(cam.yaw),
                                    math.deg(cam.pitch), math.deg(cam.fovY), math.deg(cam.fovX))
                            end
                        else
                            if ASC.cam or not ASC.camWhy then log("ASCENT CAMERA unreadable (%s): the guessed chase camera stands in", okC and "no solution" or tostring(cam)) end
                            ASC.cam, ASC.camF, ASC.camU, ASC.camWhy = nil, nil, nil, true
                        end
                    end
                    pcall(function() ASC.page:send("deep:ascent", { sun = sunNow(), p = s.p, f = s.basis.forward, u = s.basis.up, k = k * k * (3 - 2 * k),
                        alt = p.z, toSeam = cfg.enterZ - p.z, d0 = cfg.maskNearM, d1 = cfg.maskFarM,
                        camF = ASC.camF, camU = ASC.camU, camFovY = ASC.cam and ASC.cam.fovY or nil }) end)
                    geoTick(ASC.page, s, GetGameTimer(), nil)
                    -- KB-377: the measurement -- the game's real camera and the car, twice a second, into the client log
                    if cfg.ascentProbe and GetGameTimer() - (ASC.probeAt or 0) >= 500 then
                        ASC.probeAt = GetGameTimer()
                        -- KB-377: a probe bug must never stop the ascent loop (a %d on 22.5 did, 2026-10-07 14:03)
                        local okProbe, probeErr = pcall(function()
                        local fwd = s.basis.forward
                        local up = Deep.vec.unit(s.p)
                        local carPitch = math.asin(math.max(-1, math.min(1, Deep.vec.dot(fwd, up))))
                        -- start the search along the car's heading (game x = east, y = north at Night City)
                        local la0, lo0 = Deep.ecefToLla(s.p)
                        local e0, n0 = Deep.enu(la0, lo0)
                        local cam = NcmGameCamera(p, math.atan(Deep.vec.dot(fwd, n0), Deep.vec.dot(fwd, e0)))
                        -- KB-377: the third climb measured nothing (a point 29 deg off-centre came back 3 screens away):
                        -- every 500 m log the raw projection of 16 headings x 3 pitches, to fit offline whatever it really is
                        local band = math.floor(p.z / 500)
                        if band ~= ASC.gridBand then
                            ASC.gridBand = band
                            local rows = {}
                            for _, pd in ipairs({ -30, -10, 10 }) do
                                for h = 0, 15 do
                                    local yw, pr = math.rad(h * 22.5), math.rad(pd)
                                    local ok, r = pcall(Open77.camera.project, { x = p.x + 3000 * math.cos(pr) * math.cos(yw),
                                        y = p.y + 3000 * math.cos(pr) * math.sin(yw), z = p.z + 3000 * math.sin(pr) })
                                    rows[#rows + 1] = (ok and type(r) == "table") and ("%.1f/%d:%.3f,%.3f,%.0f"):format(h * 22.5, pd,
                                        tonumber(r.x) or 0 / 0, tonumber(r.y) or 0 / 0, tonumber(r.depth) or 0 / 0) or ("%.1f/%d:-"):format(h * 22.5, pd)
                                end
                            end
                            log("ASCENT GRID z %.0f car %.1f,%.1f | %s", p.z, p.x, p.y, table.concat(rows, " "))
                        end
                        log("ASCENT PROBE z %.0f | camera %s | car pitch %.1f deg", p.z,
                            cam and ("yaw %.1f pitch %.2f roll %.2f fovX %.1f fovY %.1f deg"):format(math.deg(cam.yaw), math.deg(cam.pitch),
                                math.deg(cam.roll), math.deg(cam.fovX), math.deg(cam.fovY)) or "unmeasured", math.deg(carPitch))
                        end)
                        if not okProbe then log("ASCENT PROBE error (the ascent carries on): %s", tostring(probeErr)) end
                    end
                end
            elseif ASC and (not p or not p.z or p.z < cfg.ascentZ - 200) then
                local page = ASC.page
                ASC = nil
                pcall(function() page:hide() end)
                pcall(function() page:destroy() end)
                log("ASCENT overlay off")
            end
        end
    end
end)

-- ------------------------------------------------------------------------------------------------ the ascent ring
-- 2026-10-12 (owner: "make ascent from 2 km to the 12 km handoff as seamless and visually consistent as possible"). The
-- Earth Underlay (a holed Blue Marble annulus, 9..420 km around the map, true size) is beyond REDengine's draw distance
-- from altitude: climbing showed the game's black void instead. NCM Sky draws the SAME mesh shrunk by k about the game's
-- own camera (kinds 10-14, NcmSky.reds places it at eye + k (anchor - eye) every tick): the identical picture, k times
-- nearer. k is the largest template that keeps the visible horizon within ringFarM of the eye; its inner edge stays
-- hundreds of metres out, in directions where the map has nothing. On a change of k the next template is spawned beside
-- the old one (identical picture, no gap) and the old one goes a moment later. At the seam Deep's own sky takes over.
local RING_ANCHOR = { 0.0, -1750.0, 6000.0 }            -- the underlay's pivot (tools/deep/ncwe/build-earth-underlay.py)
local RING_K = { { kind = 10, k = 0.04 }, { kind = 11, k = 0.028 }, { kind = 12, k = 0.02 }, { kind = 13, k = 0.014 },
    { kind = 14, k = 0.01 } }
local RING_OVERLAP_MS = 1500
local RING_ID = { 0.0, 0.0, 0.0, 1.0 }
local RING = nil                                         -- { kind, prev, prevUntil }

local function ringScene(bodies)
    pcall(Open77.exports.call, "ncm_sky", "scene", "ascent", bodies)
end

local function ringKind(h)
    local horizon = math.sqrt(2 * Deep.R * math.max(h, 1) + h * h)
    for _, t in ipairs(RING_K) do
        if t.k * horizon <= cfg.ringFarM then return t.kind end
    end
    return RING_K[#RING_K].kind
end

CreateThread(function()
    Wait(15000)
    while true do
        Wait(100)
        local p
        if cfg.enabled and not A and not NcmClientDeepActive then
            local vid = seat()
            local okV, v = pcall(Open77.vehicles.get, vid)
            p = vid and okV and type(v) == "table" and v.position or nil
        end
        local z = p and tonumber(p.z) or nil
        local on = z and z < cfg.enterZ and z >= (RING and cfg.ringOnZ - 200 or cfg.ringOnZ)
        if on then
            local kind = ringKind(z)
            local now = GetGameTimer()
            if not RING then
                RING = { kind = kind }
                log("ASCENT RING on at game z %.0f: kind %d", z, kind)
            elseif kind ~= RING.kind then
                RING.prev, RING.prevUntil, RING.kind = RING.kind, now + RING_OVERLAP_MS, kind
                log("ASCENT RING z %.0f: kind %d -> %d", z, RING.prev, kind)
            end
            local bodies = { { id = "ascent_ring_" .. RING.kind, kind = RING.kind, p = RING_ANCHOR, q = RING_ID } }
            if RING.prev and now < (RING.prevUntil or 0) then
                bodies[2] = { id = "ascent_ring_" .. RING.prev, kind = RING.prev, p = RING_ANCHOR, q = RING_ID }
            else
                RING.prev = nil
            end
            ringScene(bodies)
        elseif RING then
            RING = nil
            ringScene({})
            log("ASCENT RING off%s", z and (" at game z %.0f"):format(z) or " (Deep, or out of the car)")
        end
    end
end)

AddEventHandler("onClientResourceStop", function(name) if name == GetCurrentResourceName() then ringScene({}) end end)

-- ------------------------------------------------------------------------------------------------ guidance (L327)
-- The NCM guidance computer, driven with the pad (owner: no chat commands). D-pad up / G opens it (the camera goes to an
-- Earth view); left/right (Z/C) choose a destination, the view travels there, the right stick pans, R3 zooms; A / F
-- engages the autopilot (the Machine's OWN sustained thrust, gravity first; attitude is the flagged assist); B / X
-- disengages or closes. At the arrival envelope guidance lets go and offers the physical representation (Assetto Corsa):
-- A / F yes, Square / R always, B / X stay in Deep. With guidance closed, HOLD B / X two seconds to come home.
GD = { open = false, sel = 1, engaged = false, route = nil, held = {}, panLat = 0, panLon = 0, zoom = 2, msg = nil,
    prompt = nil, always = false, backSince = nil }
local ZOOMS = { 12000000, 3000000, 600000, 120000 }
NcmClientDeepSetMessage = function(m) GD.msg = m end

local function edge(name, isDown)
    local was = GD.held[name]
    GD.held[name] = isDown
    return isDown and not was
end

-- KB-375: the deeper layer's events and activation (here, below A / GD / log, which they use)
RegisterNetEvent("ncm:deep.ksa.preflight", function(p) KSA.dev = type(p) == "table" and p.dev == true end)
RegisterNetEvent("ncm:deep.ksa.selftest", function(p)
    KSA.activating = false
    p = type(p) == "table" and p or { ok = false, why = "no answer" }
    KSA.ready, KSA.why = p.ok == true, p.why
    if not A then return end
    if KSA.ready then
        GD.msg = "The deeper layer is active: Kitten Space Agency is ready behind the game." .. (A.borderHold and " Handing over now." or " It takes the Machine at the border.")
        log("KSA activated (placement proved)")
        if A.borderHold and KSA.consent and not KSA.embodying then ksaHandover(A.borderHold, GD.rehearsal) end
    else
        GD.msg = "The deeper layer could not be activated: " .. tostring(p.why) .. ". Deep holds the Machine at the border -- A asks again."
        log("KSA activation failed: %s", tostring(p.why))
    end
end)

--- KB-375: the player said yes -- prepare the deeper layer now (KSA starts behind the game and proves a placement)
local function ksaActivate()
    KSA.consent, KSA.ask = true, false
    if KSA.ready or KSA.activating then return end
    KSA.activating = true
    GD.msg = "Activating the deeper layer: Kitten Space Agency is starting behind the game (about 25 s)..."
    TriggerServerEvent("ncm:deep.ksa.selftest")
end

--- L335: hand the Machine to Kitten Space Agency: its exact state (latitude, longitude, altitude, INERTIAL velocity on the
--- Earth-fixed axes). The bridge starts KSA, places the craft, reads it back and only then says yes.
function ksaHandover(st, rehearsal)
    if KSA.embodying then return end
    KSA.embodying = true
    local la, lo, alt = Deep.ecefToLla(st.p)
    local vI = Deep.inertialVel(st.p, st.v)
    GD.msg = "KSA border: handing the Machine to Kitten Space Agency -- KSA is starting (up to a minute)..."
    -- L336: what is really left in the PT-500 goes with the Machine (KSA's craft is filled to it, not to full)
    TriggerServerEvent("ncm:deep.ksa.embody", { lat = la, lon = lo, altM = alt, velocityInertialCcf = vI, massKg = A.mass,
        asset = A.asset, rehearsal = rehearsal == true, propellantKg = EN and EN.fusionKg or nil })
end
RegisterNetEvent("ncm:deep.ksa.status", function(p)
    KSA.embodying = false
    if not A then return end
    if type(p) == "table" and p.ok then
        local e = p.errors or {}
        GD.msg = ("In Kitten Space Agency: placed and verified (%.0f m, %.2f m/s, %.4f deg). Cyberpunk closes now."):format(
            tonumber(e.radiusM) or 0, tonumber(e.speedMps) or 0, math.max(tonumber(e.latDeg) or 0, tonumber(e.lonDeg) or 0))
        log("KSA has the Machine (verified)")
    else
        GD.msg = "KSA handover failed: " .. tostring(p and p.why or "no answer") .. ". Holding at the border -- A retries."
        log("KSA handover failed: %s", tostring(p and p.why))
    end
end)

--- The pre-flight checklist for the border of Deep: THIS MACHINE only (drive, delta-v, attitude). KB-375: KSA is not part
--- of it -- the deeper layer is offered at the border, with consent; nothing about it is probed at departure.
local function ksaPreflight()
    local list, allOk = {}, true
    local function add(ok, label, detail)
        list[#list + 1] = { ok = ok, label = label, detail = detail }
        if not ok then allOk = false end
    end
    local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
    local sus = Guid.thrustBudget(EN and EN.devices or {}, nil, NcmClientDevHeat)
    local okF, tw = Guid.feasible(sus, A.mass)
    add(okF, "Sustained thrust", ("thrust/weight %.2f"):format(tw or 0))
    if A.fm and A.dyn then
        local mass = Dyn.mass(A.fm, A.dyn)
        local thrust, isp, prop = 0, 0, "fuel"
        for _, d in ipairs(A.fm.devices) do
            if d.kind == "reaction_engine" and (d.perf.thrustN or 0) > thrust then thrust, isp, prop = d.perf.thrustN, d.perf.ispS or 0, d.perf.propellant or "fuel" end
        end
        local left = NcmClientDevFuel and 1e9 or Dyn.propellantLeft(A.fm, A.dyn, prop)
        local okB, need, have = Guid.borderBudget(A.s, mass, thrust, isp, math.min(left, mass * 0.9))
        add(okB, "Delta-v to the border", ("%.0f km/s needed, %.0f available (%s)"):format(need / 1000, have / 1000, prop))
        local okP = Flight.canPoint(A.fm, NcmClientDevAttitude == true)
        add(okP, "Attitude authority", Flight.authorityText(A.fm))
        local okT, twT, whyT = Guid.trimFeasible(A.fm, A.mass)
        add(okT, "Thrust line", okT and "through the centre of mass, or trimmed" or tostring(whyT))
    end
    return allOk, list
end

--- DEVELOPMENT rehearsal (owner: "we are not burning 3 hours per attempt"): put the Machine on a real arrival -- outward at
--- ~148 km/s, 60 s before the border, over where it is now -- with Guidance engaged, so the whole handover is tested in a
--- minute. Not physical, said on the HUD and in the log.
local function ksaRehearse()
    if not A or not A.fm then return end
    local la, lo = Deep.ecefToLla(A.s.p)
    local e, n, u = Deep.enu(la, lo)
    local speed = 148000
    local r = Guid.BORDER.radiusM - speed * 60
    local p = Deep.vec.scale(u, r)
    local vI = Deep.vec.add(Deep.vec.scale(u, speed), Deep.vec.scale(e, 3))
    local vFixed = Deep.vec.add(vI, Deep.vec.scale(Deep.vec.cross({ 0, 0, Deep.OMEGA }, p), -1))
    A.s = { p = p, v = vFixed, basis = { right = e, forward = u, up = Deep.vec.scale(n, -1) }, t = A.s.t }
    A.dyn = Flight.state(A.fm, A.s, Flight.carry(A.dyn), utcNow())
    GD.route = Guid.planBorder(A.s)
    GD.engaged, GD.rehearsal, GD.open = true, true, false
    A.borderHold, A.atBorder = nil, nil
    KSA.consent, KSA.ask = nil, false   -- KB-375: the rehearsal goes through the same consent screen
    GD.msg = "DEV REHEARSAL (not physical): 60 s before the border of Deep, Guidance engaged."
    log("KSA REHEARSAL: placed 60 s before the border over %.3f, %.3f (r %.0f km, %.0f km/s)", la, lo, r / 1000, speed / 1000)
end

local function guidanceInput(now, dt)
    local openE = edge("open", down("padUp") or down("G"))
    local prevE = edge("prev", down("padLeft") or down("Z"))
    local nextE = edge("next", down("padRight") or down("C"))
    local aE = edge("a", down("padA") or down("F"))
    local backDown = down("padB") or down("X")
    local backE = edge("b", backDown)
    local alwaysE = edge("always", down("padX") or down("R"))
    local zoomE = edge("zoom", GD.open and (down("padRightThumb")) or false)

    -- KB-375: the deeper layer, asked at the border (A activates it, B stays in Deep)
    if KSA.ask then
        if aE then ksaActivate()
        elseif backE then
            KSA.consent, KSA.ask = false, false
            GD.msg = "Staying in Deep. Nothing was started; the border holds the Machine -- A there asks again."
        end
        return
    end
    -- L329: the adapter is only installed with consent, asked when it matters (over the place, never at install)
    if GD.consent then
        if aE then
            local v = GD.consent
            GD.consent, GD.msg = nil, "Installing the NCM Assetto Corsa adapter..."
            TriggerServerEvent("ncm:deep.adapter", { action = "enable", venue = v.id })
        elseif backE then
            GD.msg = "Staying in Deep. " .. GD.consent.name .. " is below you; NCM changed nothing in Assetto Corsa."
            GD.consent = nil
        end
        return
    end
    if GD.prompt then
        if aE or alwaysE then
            if alwaysE then GD.always = true end
            local v = GD.prompt
            GD.prompt = nil
            requestEmbodiment(v)
        elseif backE then
            -- KB-361: staying is not letting go -- guidance keeps the Machine over the place until you take it
            GD.msg = "Staying in Deep, holding over " .. GD.prompt.name .. ". D-pad up: Guidance; your controls take over."
            GD.hold, GD.prompt = GD.prompt, nil
        end
        return
    end
    if openE then GD.open = not GD.open; GD.msg = nil end
    -- L329: HOST ADAPTERS (D-pad down with guidance open; X / Square toggles) -- the reversible part, no command needed
    local adaptersE = edge("adapters", GD.open and down("padDown") or false)
    if adaptersE then GD.adapters = not GD.adapters; if GD.adapters then TriggerServerEvent("ncm:deep.adapter", { action = "status" }) end end
    if GD.adapters and edge("adapterToggle", down("padX") or down("R")) then
        TriggerServerEvent("ncm:deep.adapter", { action = GD.acEnabled and "disable" or "enable" })
    end
    if GD.open then
        local n = #targets()
        if prevE then GD.sel = (GD.sel - 2) % n + 1; GD.panLat, GD.panLon = 0, 0 end
        if nextE then GD.sel = GD.sel % n + 1; GD.panLat, GD.panLon = 0, 0 end
        -- L330: the posted timetable of the selected place (asked again every 30 s while guidance is open)
        if prevE or nextE or openE or now - (GD.schedAt or 0) > 30000 then
            GD.schedAt, GD.schedule = now, nil
            if not targets()[GD.sel].border then TriggerServerEvent("ncm:deep.schedule", targets()[GD.sel].id) end
        end
        if zoomE then GD.zoom = GD.zoom % #ZOOMS + 1 end
        -- L335: the KSA border selected: keep the pre-flight fresh; on dev, L3 held 2 s = the rehearsal
        if targets()[GD.sel] and targets()[GD.sel].border then
            if KSA.dev == nil and now - KSA.devAt > 8000 then KSA.devAt = now; TriggerServerEvent("ncm:deep.ksa.preflight") end
            if KSA.dev and down("padLeftThumb") then
                KSA.holdL3 = KSA.holdL3 or now
                if now - KSA.holdL3 >= 2000 then KSA.holdL3 = nil; ksaRehearse(); return end
            else KSA.holdL3 = nil end
        end
        local px, py = dead(axis("padRightStickX")), dead(axis("padRightStickY"))
        local rate = ZOOMS[GD.zoom] / 1000000 * 8 * dt
        GD.panLon, GD.panLat = GD.panLon + px * rate, math.max(-60, math.min(60, GD.panLat + py * rate))
        if aE and A.borderHold and not KSA.embodying then
            if KSA.ready then ksaHandover(A.borderHold, GD.rehearsal) else KSA.ask = true end
            return
        end
        if aE then
            if GD.engaged then GD.engaged = false; GD.msg = "Autopilot off: you have the Machine."
            else
                -- KB-349: only a Machine that can hold itself up on thrust it can keep making (heat included)
                local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
                local sus = Guid.thrustBudget(EN and EN.devices or {}, nil, NcmClientDevHeat)
                local okF, tw, why = Guid.feasible(sus, A.mass)
                if okF and A.fm then okF, tw, why = Guid.trimFeasible(A.fm, A.mass) end   -- KB-442: a thrust line off the centre of mass
                if not okF then
                    GD.msg = ("Guidance cannot fly this Machine to %s: %s."):format(targets()[GD.sel].name, why)
                    log("GUIDANCE refused -> %s: %s", targets()[GD.sel].id, why)
                    TriggerServerEvent("ncm:deep.guidance", { event = "refused", venue = targets()[GD.sel].id })
                    return
                end
                -- L335/KB-375: the border flies on THIS MACHINE's pre-flight; the deeper layer is offered at the border
                if targets()[GD.sel].border then
                    local okAll, list = ksaPreflight()
                    if not okAll then
                        local bad = {}
                        for _, c in ipairs(list) do if not c.ok then bad[#bad + 1] = c.label end end
                        GD.msg = "Pre-flight not passed: " .. table.concat(bad, ", ")
                        return
                    end
                end
                -- L334: the border needs the delta-v to get there -- the main drive's own propellant, honestly
                if targets()[GD.sel].border and A.fm and A.dyn then
                    local mass = Dyn.mass(A.fm, A.dyn)
                    local thrust, isp, prop = 0, 0, "fuel"
                    for _, d in ipairs(A.fm.devices) do
                        if d.kind == "reaction_engine" and (d.perf.thrustN or 0) > thrust then thrust, isp, prop = d.perf.thrustN, d.perf.ispS or 0, d.perf.propellant or "fuel" end
                    end
                    local left = NcmClientDevFuel and 1e9 or Dyn.propellantLeft(A.fm, A.dyn, prop)
                    local okB, need, have = Guid.borderBudget(A.s, mass, thrust, isp, math.min(left, mass * 0.9))
                    if not okB then
                        GD.msg = ("Guidance cannot reach the KSA border: it needs about %.0f km/s and this Machine's %s gives %.0f km/s (a Fusion Drive FD-1 and a Propellant Tank PT-500 can)."):format(
                            need / 1000, prop, have / 1000)
                        log("GUIDANCE refused -> ksa_border: delta-v %.0f of %.0f km/s", have / 1000, need / 1000)
                        TriggerServerEvent("ncm:deep.guidance", { event = "refused", venue = "ksa_border" })
                        return
                    end
                end
                GD.route = Guid.planTo(A.s, targets()[GD.sel])
                GD.engaged, GD.hold = true, nil
                GD.msg = nil
                local pts = {}
                for _, w in ipairs(GD.route.waypoints) do pts[#pts + 1] = { w.lat, w.lon } end
                pts[#pts + 1] = { GD.route.arrival.lat, GD.route.arrival.lon }
                send("deep:route", { points = pts })
                log("GUIDANCE engaged -> %s (%.0f km, %d waypoint(s))", GD.route.venue.id, GD.route.distanceM / 1000, #GD.route.waypoints)
                TriggerServerEvent("ncm:deep.guidance", { event = "engaged", venue = GD.route.venue.id, km = GD.route.distanceM / 1000 })
                A.yieldFrame = true   -- KB-369: planning the route is this frame's work; flying it starts next frame
            end
        end
        if backE then
            if GD.engaged then GD.engaged = false; GD.msg = "Autopilot off: you have the Machine." else GD.open = false end
        end
        GD.backSince = nil
    else
        -- hold B / X to come home (replaces /ncm.deep.home)
        if backDown then
            GD.backSince = GD.backSince or now
            if now - GD.backSince >= 2000 then GD.backSince = nil; exit("held B: home", true) end
        else
            GD.backSince = nil
        end
    end
end

-- Doc 58 (2026-10-12): where a Deep frame's time goes, section by section (Open77.time.monotonic), logged every 5 s
-- with the frames OPEN//77 skipped for its script budget -- so a budget problem names its section instead of a guess.
local PROF = { at = 0, n = 0, sum = {}, max = {}, order = {} }
local function profNow() local ok, t = pcall(Open77.time.monotonic); return ok and tonumber(t) or 0 end
local profT0 = 0
local function prof(name)
    local t = profNow()
    if name then
        local d = (t - profT0) * 1000
        if not PROF.sum[name] then PROF.sum[name], PROF.max[name] = 0, 0; PROF.order[#PROF.order + 1] = name end
        PROF.sum[name] = PROF.sum[name] + d
        if d > PROF.max[name] then PROF.max[name] = d end
    end
    profT0 = t
end
local function profReport(now)
    PROF.n = PROF.n + 1
    if now - PROF.at < 5000 then return end
    local parts = {}
    for _, k in ipairs(PROF.order) do parts[#parts + 1] = ("%s %.2f/%.1f"):format(k, PROF.sum[k] / math.max(1, PROF.n), PROF.max[k]) end
    log("PROFILE %d frames, ms avg/max: %s | budget-skipped %d", PROF.n, table.concat(parts, "  "), (A and A.overBudgetWindow) or 0)
    if A then A.overBudgetWindow = 0 end
    PROF.at, PROF.n, PROF.sum, PROF.max, PROF.order = now, 0, {}, {}, {}
end

-- doc 58 (2026-10-12 07:13): the 1 Hz canonical checkpoint, built and sent from its own thread. Inside the flight frame
-- it was the last thing before the budget ran out on heavy frames; for 15 s none arrived and the server took over a
-- Machine that was mid-jump.
CreateThread(function()
    while true do
        Wait(0)
        if A and A.ckptDue then
            A.ckptDue = false
            local okC, errC = pcall(checkpoint, "deep", false)
            if not okC and A then A.ckptDue = true; if not A.ckptWarned then A.ckptWarned = true; log("checkpoint retried: %s", tostring(errC)) end end
        end
    end
end)

-- doc 58: the drive-event sender. One event per frame, encoded here (never in the flight frame), sent as one JSON
-- string (the net serializer dropped tables holding a bubble's 8.7e57 J estimate). An event that cannot be encoded is
-- retried on the next frame, then dropped and said so.
DriveOut = DriveOut or {}
CreateThread(function()
    while true do
        Wait(0)
        local e = DriveOut[1]
        if e then
            local okJ, js = pcall(Json.encode, { events = { e }, realMs = GetGameTimer(), travel = DriveOut.travel })
            if okJ then
                table.remove(DriveOut, 1)
                DriveOut.travel = nil
                pcall(TriggerServerEvent, "ncm:deep.drive", { json = js })
                e.tries = nil
            else
                e.tries = (e.tries or 0) + 1
                if e.tries >= 5 then
                    table.remove(DriveOut, 1)
                    log("DRIVE event %s not sent after 5 tries (%s)", tostring(e.type), tostring(js))
                end
            end
        end
    end
end)

local function tick()
    prof(nil)
    local now = ms()
    local dt = math.min(0.05, math.max(0.001, (now - A.last) / 1000))
    A.last = now

    if A.embodied then
        -- the Machine is physical in Assetto Corsa: Deep holds it (one Machine, one place) until it climbs back out
        A.last = now
        if now - A.lastSend >= 250 then
            A.lastSend = now
            send("deep:state", { p = A.s.p, v = { 0, 0, 0 }, r = A.s.basis.right, f = A.s.basis.forward, u = A.s.basis.up,
                alt = 0, lat = 0, lon = 0, speed = 0, hs = 0, vs = 0, orbit = 0, thrust = 0, devices = "", impact = "-",
                rig = false, cam = "earth", t = 0, guidance = { msg = "Embodied in Assetto Corsa at " .. A.embodied .. ". Climb out past 2,500 m to return." } })
        end
        return
    end
    guidanceInput(now, dt)
    prof("guidance")
    if not A then return end   -- held B brought us home
    if A.yieldFrame then A.yieldFrame = nil; return end

    -- L331: the sticks. With an attitude part they command TORQUE (physical); without one, on the development server
    -- only, they turn the body directly (the labelled waiver). The autopilot owns attitude while engaged or holding.
    local stick = { pitch = 0, yaw = 0, roll = 0 }
    if rig and not GD.engaged and not GD.prompt and not GD.hold then
        local pitch, yaw, roll = dead(axis("padLeftStickY")), dead(axis("padLeftStickX")), GD.open and 0 or dead(axis("padRightStickX"))
        if down("W") then pitch = pitch + 1 end
        if down("S") then pitch = pitch - 1 end
        if down("A") then yaw = yaw - 1 end
        if down("D") then yaw = yaw + 1 end
        if down("Q") then roll = roll - 1 end
        if down("E") then roll = roll + 1 end
        stick = { pitch = pitch, yaw = yaw, roll = roll }
    end
    if not GD.open then
        -- the zoom (owner, 2026-10-06: zoom toward the Hella, then out until it is a speck on the Earth): log scale
        local zy = dead(axis("padRightStickY")) + (down("I") and 1 or 0) - (down("O") and 1 or 0)
        if zy ~= 0 then A.zoom = math.max(8, math.min(4e7, (A.zoom or 22) * math.exp(-zy * 1.6 * dt))) end
        local cam = down("V") or down("padRightThumb")
        if cam and not A.camHeld then camMode = camMode % #CAM_NAMES + 1 end
        A.camHeld = cam
    end

    -- L331: THE FULL MACHINE MODEL. The Machine's install + chassis + its own tank is one engineering.machine; every
    -- frame is one engineering.dynamics step (6-DOF: off-centre force spins it, air thins with altitude, parts heat up
    -- and shut down) -- the same model AC's Deep and the server's offline flight step.
    local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
    local devText = "no installed components"
    local gcmd = nil
    local devs = EN and EN.devices or {}
    local key = #devs .. ":" .. table.concat((function() local t = {} for i, d in ipairs(devs) do t[i] = tostring(d.componentId) end return t end)(), ",")
    if not A.fm or A.fmKey ~= key then
        -- dev fuel needs a tank to draw from even before the fuel system has reported one (nothing is burned from it)
        local fk = EN and tonumber(EN.fuelKg) or 0
        if fk <= 0 and NcmClientDevFuel then fk = 40 end
        A.fm = Flight.build(devs, { vehicleKey = EN and EN.vehicleKey or "archer_hella", fuelKg = fk })
        A.dyn = Flight.state(A.fm, A.s, A.dyn and Flight.carry(A.dyn) or A.resumeDyn, utcNow())
        A.fmKey = key
    end
    local m, ds = A.fm, A.dyn
    local devAtt = NcmClientDevAttitude == true
    local cmd = { throttle = {}, discharge = {} }
    -- doc 57: NCM's clock turns on the astronomical substrate (every relevant body's gravity; inertial frames far from
    -- home); guidance and the border hold plan Earth-fixed, so they keep the Earth-fixed frame
    local opts = { devFuel = NcmClientDevFuel == true, devHeat = NcmClientDevHeat == true, utc = utcNow(),
                   earthFixed = (GD and GD.engaged) or A.atBorder or nil }
    if EN and #devs > 0 then
        local pressed = {}
        for _, c in ipairs(EN.controls) do pressed[c] = down(c) end
        -- KB-437: what the controls did, for the once-a-second line and the HUD (the 2026-10-10 stay had zero thrust
        -- for 22 s and nothing said why)
        local okC, cap = pcall(Open77.input.isCaptured)
        A.captured = okC and cap == true
        for c, d in pairs(pressed) do if d then A.pressedSeen = A.pressedSeen or {}; A.pressedSeen[c] = true end end
        local cmds = Controls.step(EN.ctl, EN.bindings, EN.devices, pressed, now)
        if GD.hold then for _, c in pairs(pressed) do if c then GD.hold, GD.route = nil, nil; GD.msg = "You have the Machine." break end end end
        for id, c in pairs(cmds) do
            if c.throttle then cmd.throttle[id] = c.throttle end
            if c.discharge then cmd.discharge[id] = true; A.report.pulses = A.report.pulses + 1 end
            -- doc 58: a drive's own commands (engage / abort / up / down / next / prev) go to space.drives
            if c.engage or c.abort or c.up or c.down or c.next or c.prev then
                cmd.drive = cmd.drive or {}
                cmd.drive[tostring(id)] = c
            end
        end
    end
    -- the sticks: torque from attitude parts, or the development waiver
    if stick.pitch ~= 0 or stick.yaw ~= 0 or stick.roll ~= 0 then
        if #(m.attitude or {}) > 0 then cmd.torque = { stick.pitch, stick.roll, -stick.yaw }
        elseif devAtt then opts.rig = { pitch = stick.pitch * RIG_RATE, yaw = stick.yaw * RIG_RATE, roll = stick.roll * RIG_RATE } end
    end
    -- KB-349: past the envelope guidance keeps HOLDING over the venue while the prompt is up and while the host is asked
    local holding = GD.route and not GD.engaged and (GD.prompt or A.embodyPending or GD.hold) and true or false
    if GD.engaged or holding then
        local canPoint, why = Flight.canPoint(m, devAtt)
        if not Flight.mainAxis(m) then
            GD.engaged, GD.hold, GD.msg = false, nil, "Guidance cannot fly this Machine: it has no sustained thrust installed."
        elseif not canPoint then
            GD.engaged, GD.hold, GD.msg = false, nil, "Guidance cannot point this Machine: " .. tostring(why)
        else
            if Flight.toEarthFixed then ds.utc = ds.utc or opts.utc; Flight.toEarthFixed(ds) end   -- doc 57: guidance reads Earth-fixed
            local gc, waiver, info = Guid.fly(GD.route, m, ds, { devHeat = opts.devHeat, waiver = devAtt and #(m.attitude or {}) == 0 })
            Guid.apply(cmd, gc)   -- KB-376: ALL of Guidance's command (it steers by torqueNm with a gimballed engine)
            opts.waiver = waiver
            gcmd = info
            local thr = 0
            for _, th in pairs(gc.throttle) do thr = math.max(thr, th) end
            gcmd.throttle = thr
            if GD.engaged and GD.route.kind == "border" and KSA.consent == nil and not KSA.ask and (info.etaS or 1e9) <= KSA_ASK_ETA_S then
                KSA.ask = true   -- KB-375: approaching the border -- offer the deeper layer now, so it is ready on arrival
                log("GUIDANCE approaching the border of Deep (%.0f s): offering the deeper layer", info.etaS or 0)
            end
            if GD.engaged and GD.route.kind == "border" and Guid.arrived(GD.route, Flight.deep(ds)) then
                -- L335: Earth's sphere of influence -- KSA takes the Machine at THIS state. Deep holds it here (labelled, like
                -- AC's held body) until KSA confirms it placed it and read it back.
                GD.engaged = false
                log("GUIDANCE reached the KSA border")
                TriggerServerEvent("ncm:deep.guidance", { event = "arrived", venue = "ksa_border" })
                A.atBorder = true
                A.borderHold = Flight.deep(ds)
                if KSA.ready and KSA.consent then ksaHandover(A.borderHold, GD.rehearsal)
                elseif KSA.consent and KSA.activating then GD.msg = "At the border: holding while Kitten Space Agency gets ready..."
                else KSA.ask = true end   -- not asked, declined or failed: ask here (KB-375)
            elseif GD.engaged and Guid.arrived(GD.route, Flight.deep(ds)) then
                GD.engaged = false
                GD.prompt = GD.route.venue
                GD.msg = nil
                log("GUIDANCE arrived over %s", GD.route.venue.id)
                TriggerServerEvent("ncm:deep.guidance", { event = "arrived", venue = GD.route.venue.id })
                if GD.always then local v = GD.prompt; GD.prompt = nil; requestEmbodiment(v) end
            end
        end
    end
    if A.borderHold then   -- L335: held at the border for the handover (not physical, said on the HUD)
        ds.vel = { 0, 0, 0 }
    end
    local fuel0 = Flight.fuelKg(m, ds)
    A.fusion0 = Dyn.propellantLeft(m, ds, "fusion")
    local tel
    A.dtMax = math.max(A.dtMax or 0, dt)   -- KB-376: the longest physics step this second (telemetry)
    prof("controls")
    ds, tel = Flight.step(m, ds, cmd, dt, opts)
    prof("flight.step")
    A.dyn = ds
    -- doc 58: what the drives did this step, to the server (an activation's start / end / transit at once, the rest batched)
    if tel.driveEvents and #tel.driveEvents > 0 then
        A.dq = A.dq or {}
        for _, e in ipairs(tel.driveEvents) do
            A.dq[#A.dq + 1] = e
            if e.type == "diag" then log("DRIVE %s %s", tostring(e.drive), tostring(e.text)) end
            if e.type ~= "stream" and e.type ~= "state" and e.type ~= "diag" then A.dqUrgent = true end
            if e.type == "start" or e.type == "end" or e.type == "restored" or e.type == "transit" or e.type == "error" then
                log("DRIVE %s %s%s%s", tostring(e.drive), tostring(e.type), e.act and (" " .. tostring(e.act.id or e.act)) or "",
                    e.type == "end" and e.act and (" " .. tostring(e.act.reason) .. (" | endpoint %.6g m path %.6g m"):format(e.act.endpointM or 0, e.act.pathM or 0)) or (e.why and (" " .. tostring(e.why)) or ""))
            end
        end
    end
    -- the events go out from their own thread, one per frame (the sender below): encoding an activation's record in
    -- the flight frame ran it out of the script budget and the start / end were dropped (2026-10-12 07:13)
    if A.dq and #A.dq > 0 then
        for _, e in ipairs(A.dq) do
            if e.checkpoint then e.checkpoint = nil end   -- the server stores its own (deep_dev_checkpoint)
            DriveOut[#DriveOut + 1] = e
        end
        A.dq = {}
        if now - (A.travelAt or 0) >= 30000 and ds.travel then DriveOut.travel = Travel.save(ds.travel); A.travelAt = now end
    end
    A.ev = A.ev or {}
    for _, ev in ipairs(tel.events or {}) do
        local k = tostring(ev.device) .. ":" .. tostring(ev.what)
        A.ev[k] = (A.ev[k] or 0) + 1
    end
    if EN and not opts.devFuel then
        local usedF = math.max(0, (A.fusion0 or 0) - Dyn.propellantLeft(m, ds, "fusion"))
        EN.fusionKg = math.max(0, (EN.fusionKg or 0) - usedF)
        A.report.fusionKg = (A.report.fusionKg or 0) + usedF
        local used = math.max(0, fuel0 - Flight.fuelKg(m, ds))
        EN.fuelKg = math.max(0, (EN.fuelKg or 0) - used)
        A.report.kg = A.report.kg + used
    end
    A.s = Flight.deep(ds)
    A.thrustN, A.mass, A.waiverOn = tel.thrustN or 0, tel.mass or A.mass, tel.waiver == true
    if #devs > 0 then
        local parts = {}
        for i, d in ipairs(m.devices) do
            local st = ds.dev and ds.dev[i] or {}
            parts[#parts + 1] = d.kind == "pulse_reaction" and ((d.perf.code or d.key or "IA") .. ((ds.pulse and (ds.pulse[i] or 0) > 0) and " FIRING" or ""))
                or ("%s %.0f%%%s"):format(tostring(d.key):sub(1, 8), ((ds.thr and ds.thr[i]) or 0) * 100, st.hot and " HOT" or "")
        end
        local boundIds = {}
        for _, x in ipairs(EN and EN.bindings or {}) do boundIds[tostring(x.componentId)] = true end
        for i, md in ipairs(m.devices) do
            local evs = A.evShown or {}
            if (evs[tostring(md.key) .. ":starved"] or 0) > 0 then parts[i] = parts[i] .. " NO FUEL" end
            if (evs[tostring(md.key) .. ":no_energy"] or 0) > 0 then parts[i] = parts[i] .. " NO ENERGY" end
            if md.kind ~= "propellant_tank" and md.componentId and not boundIds[tostring(md.componentId)]
                and (md.kind == "reaction_engine" or md.kind == "pulse_reaction") then parts[i] = parts[i] .. " NO CONTROL" end
        end
        for _, d in ipairs(devs) do
            for i, md in ipairs(m.devices) do if md.componentId == d.componentId then parts[i] = parts[i]:gsub("^[^ ]+", d.code) end end
        end
        devText = (A.captured and "CONTROLS BLOCKED (input captured) | " or "") .. table.concat(parts, " | ")
    elseif GD.engaged then
        GD.engaged, GD.msg = false, "Guidance cannot fly this Machine: it has no installed propulsion."
    end
    -- KB-369: the authority table depends only on the Machine -- once per model, not every frame
    if A.authorityKey ~= A.fmKey then A.authority, A.authorityKey = Flight.authorityText(m), A.fmKey end
    A.spin = Deep.vec.len(ds.omega)

    local lat, lon, alt = Deep.ecefToLla(A.s.p)
    local e, n, u = Deep.enu(lat, lon)
    local vs = Deep.vec.dot(A.s.v, u)
    local speed = Deep.vec.len(A.s.v)
    local hs = math.sqrt(math.max(0, speed * speed - vs * vs))
    prof("after-step")
    if now - A.lastImpact > 500 then
        A.lastImpact = now
        local la, lo = Deep.impact(A.s.p, A.s.v)   -- closed form: one evaluation (KB-348)
        if la then
            A.impact = ("%.1f km from Night City"):format(Deep.distance(la, lo, Deep.ORIGIN.lat, Deep.ORIGIN.lon) / 1000)
            A.land = { la, lo }
        else
            A.impact, A.land = (lo == "escape") and "none: escaping Earth" or "none: in orbit", nil
        end
    end
    prof("impact")
    geoTick(A.page, A.s, now, GD.route and GD.route.venue and { lat = GD.route.venue.lat, lon = GD.route.venue.lon } or nil)
    prof("geolod")
    -- L352: what REDengine shows -- the held car in its stage, the bodies at their true angular size (guarded: a view
    -- problem never ends a flight)
    if NcmDeepView then
        local okV, errV = pcall(NcmDeepView.update, A.s, utcNow(), now)
        if not okV and not A.viewErr then A.viewErr = true; log("native view skipped: %s", tostring(errV)) end
    end
    -- doc 58: the drives' layer (native and NCM's own views) -- guarded: a drawing problem never ends a flight
    prof("deepview")
    if NcmDriveFx and utcNow() then
        local thrMax, pulsing = 0, false
        for i, md in ipairs(m.devices or {}) do
            if md.kind == "reaction_engine" then thrMax = math.max(thrMax, (ds.thr and ds.thr[i]) or 0) end
            if md.kind == "pulse_reaction" and ds.pulse and (ds.pulse[i] or 0) > 0 then pulsing = true end
        end
        local conv = ds.conv and ds.conv.method and { method = ds.conv.method, throttle = thrMax, pulse = pulsing } or (pulsing and { method = "impulse", pulse = true }) or nil
        local okX, errX = pcall(NcmDriveFx.update, { page = A.page, m = m, dyn = ds, s = A.s, utc = utcNow(), now = now,
            native = CAM_NAMES[camMode] == "native" and not GD.open, conv = conv })
        if not okX and not A.fxErr then A.fxErr = true; log("drive layer skipped: %s", tostring(errX)) end
    end
    -- NCM FX (presentation.fx): the parts, the body and the drives, drawn natively on the held car. Every frame (a
    -- stroke is an edge of ONE step); the drive views are refreshed ten times a second. Guarded like the rest.
    if NcmFx and tel then
        local okFx, errFx = pcall(function()
            local em = Fx.fromDynamics(A.asset or "deep", m, ds, tel, {})
            local body = Fx.machine(A.asset or "deep", { speed = Deep.vec.len(ds.vel or { 0, 0, 0 }), rho = tel.rho,
                qPa = tel.qPa, aeroHeatKw = tel.aeroHeatKw }, A.fxBody)
            A.fxBody = body[1].q
            em[#em + 1] = body[1]
            if now - (A.fxViewsAt or 0) >= 100 then A.fxViewsAt, A.fxViews = now, Fx.fromDrives(A.asset or "deep", Drives.view(m, ds)) end
            for _, e in ipairs(A.fxViews or {}) do em[#em + 1] = e end
            local okF, f = pcall(Open77.character.frame, { vehicleId = A.vid })
            local okP, v = pcall(Open77.vehicles.get, A.vid)
            if okF and type(f) == "table" and okP and type(v) == "table" and v.position then
                NcmFx.publish(A.asset or "deep", A.vid, em)
                NcmFx.frame(A.asset or "deep", em, f, v.position)
            end
        end)
        if not okFx and not A.fxNativeErr then A.fxNativeErr = true; log("native FX skipped: %s", tostring(errFx)) end
        prof("fx")
    end
    -- doc 58: each drive's store, to the server (it only ever lowers it) every two seconds when it changed
    if #(m.drives or {}) > 0 and now - (A.chargeAt or 0) >= 2000 then
        A.chargeAt = now
        local left, changed = {}, false
        for _, d in ipairs(m.drives) do
            local dsd = ds.drv and ds.drv[d.componentId]
            if dsd then
                left[d.componentId] = dsd.charge
                if not A.chargeSent or A.chargeSent[d.componentId] ~= dsd.charge then changed = true end
            end
        end
        if changed then A.chargeSent = left; TriggerServerEvent("ncm:deep.drive.charge", { left = left }) end
    end
    prof("drivefx+charge")
    if now - A.lastSend >= 33 then
        A.lastSend = now
        local sel = targets()[GD.sel]
        local g = {
            open = GD.open, sel = GD.sel, engaged = GD.engaged, msg = GD.msg, always = GD.always,
            prompt = GD.prompt and GD.prompt.name or nil,
            consent = GD.consent and GD.consent.name or nil, adapters = GD.adapters and { ac = GD.acEnabled == true } or nil,
            schedule = GD.schedule,
            selName = sel.name, selRegion = sel.region, selId = sel.id,
            preflight = (sel.border and GD.open) and (function() local _, l = ksaPreflight(); return l end)() or nil,
            held = A.borderHold and "HELD AT THE BORDER OF DEEP (not physical)" or nil,
            ksaAsk = KSA.ask or nil, ksaRehearsal = GD.rehearsal or nil,
            selKm = sel.border and math.max(0, sel.radiusM - Deep.vec.len(A.s.p)) / 1000 or Deep.distance(lat, lon, sel.lat, sel.lon) / 1000,
            backHold = GD.backSince and math.min(1, (now - GD.backSince) / 2000) or 0,
        }
        if gcmd then
            g.phase, g.target, g.km, g.eta, g.throttle, g.vWant = gcmd.phase, GD.route.venue.name, gcmd.distanceM / 1000, gcmd.etaS, gcmd.throttle, gcmd.vWant
        end
        if GD.open then
            -- KB-372: the KSA border is a radius, not a place (no lat/lon): the map looks at the Machine instead
            g.cam = { lat = (sel.lat or lat) + GD.panLat, lon = (sel.lon or lon) + GD.panLon, alt = ZOOMS[GD.zoom] }
        end
        send("deep:state", {
            p = A.s.p, v = A.s.v, r = A.s.basis.right, f = A.s.basis.forward, u = A.s.basis.up,
            alt = alt, lat = lat, lon = lon, speed = speed, hs = hs, vs = vs, orbit = Deep.orbitSpeed(alt),
            orb = (function() local o = Deep.orbit(A.s.p, A.s.v); return { apo = o.apoM, peri = o.periM, escape = o.escape, vi = o.speed } end)(),
            borderKm = math.max(0, Guid.BORDER.radiusM - Deep.vec.len(A.s.p)) / 1000,
            fusionKg = A.fm and Dyn.propellantLeft(A.fm, A.dyn, "fusion") or nil,
            fuelKg = EN and EN.fuelKg or nil, thrust = A.thrustN, devices = devText, impact = A.impact, land = A.land,
            rig = rig and not GD.engaged, cam = CAM_NAMES[camMode], zoom = A.zoom or 22, t = (now - A.startedAt) / 1000, devFuel = NcmClientDevFuel == true,
            twr = (A.fm and (function() local t = 0 for _, d in ipairs(A.fm.devices) do if d.kind == "reaction_engine" then t = t + (d.perf.thrustN or 0) end end return t end)() or 0)
                / (A.mass * Deep.vec.len(Deep.gravity(A.s.p))), guidance = g, sun = sunNow(),
            authority = A.authority, waiver = A.waiverOn, spin = A.spin, rho = Flight.density(alt),
            gmst = Astro and utcNow() and Astro.gmst(utcNow()) or nil, frame = A.dyn and A.dyn.frame and (A.dyn.frame.body or "anchor") or "earth_fixed",
        })
        -- doc 57 §5.4: the Sun, the Moon, the planets (and the Galactic Centre) where the catalogue says, once a second
        if Astro and utcNow() and now - (A.bodiesAt or 0) >= 1000 then
            A.bodiesAt = now
            local okB, bodies = pcall(catalogueBodies, utcNow())
            if okB and bodies then send("deep:bodies", { bodies = bodies }) end
        end
    end
    prof("page-state")
    if now - A.lastTele >= 1000 then
        A.ckptDue = true   -- doc 58: sent from its own thread (below), never inside the flight frame's budget
        A.lastTele = now
        do
            local evs = {}
            for k, n in pairs(A.ev or {}) do if not k:find(":fired$") then evs[#evs + 1] = ("%s x%d"):format(k, n) end end
            table.sort(evs)
            local pr = {}
            for c in pairs(A.pressedSeen or {}) do pr[#pr + 1] = c end
            table.sort(pr)
            log("STAY t+%.0fs alt %.0f vz %.1f | thrust %.1f kN | fuel %.1f kg fusion %.1f kg | %s | pressed %s%s | events %s",
                (now - A.startedAt) / 1000, alt, vs, (A.thrustN or 0) / 1000, EN and EN.fuelKg or 0, EN and EN.fusionKg or 0, devText,
                #pr > 0 and table.concat(pr, ",") or "none", A.captured and " (INPUT CAPTURED)" or "", #evs > 0 and table.concat(evs, ", ") or "none")
            A.evShown, A.ev, A.pressedSeen = A.ev or {}, {}, nil
        end
        local ncKm = Deep.distance(lat, lon, Deep.ORIGIN.lat, Deep.ORIGIN.lon) / 1000
        TriggerServerEvent("ncm:deep.telemetry", { alt = alt, speed = speed, hspeed = hs, vspeed = vs, orbit = Deep.orbitSpeed(alt),
            lat = lat, lon = lon, ncKm = ncKm, landing = A.impact, fuelKg = EN and EN.fuelKg or 0, thrust = A.thrustN, rig = rig and NcmClientDevAttitude == true,   -- the waiver as APPLIED (Online never applies it)
            -- KB-376: how the Machine is pointing (alignment of its thrust with what Guidance wants, spin rate) and how the
            -- frames ran -- the live climb fell in bursts the simulation never shows
            devices = devText, guidance = gcmd and ("%s -> %s %.0f km eta %.0f s throttle %.2f | align %.2f spin %.2f rad/s | dt max %.0f ms skipped %d"):format(
                gcmd.phase, GD.route.venue.id, gcmd.distanceM / 1000, gcmd.etaS, gcmd.throttle, tonumber(gcmd.align) or -1,
                Deep.vec.len(A.dyn and A.dyn.omega or { 0, 0, 0 }), (A.dtMax or 0) * 1000, A.overBudgetTotal or 0) or nil })
        A.dtMax = 0
        if EN and (A.report.kg > 0 or (A.report.fusionKg or 0) > 0) then
            TriggerServerEvent("ncm:engineering.burn", { assetId = EN.assetId, kg = A.report.kg, fusionKg = A.report.fusionKg or 0, dtS = (now - A.report.since) / 1000,
                pulses = A.report.pulses, t = { devices = devText, f = A.thrustN, z = alt, speed = speed,
                    loss = "in NCM deep space (no REDengine): force at CoM; attitude by the dev rig / guidance assist" } })
        end
        A.report = { kg = 0, pulses = 0, since = now }
    end
    -- back into Night City only near Night City; anywhere else low altitude is that place's business (its embodiment
    -- host), and coming down to the ground far from any host ends the trip home
    prof("1hz")
    profReport(now)
    local ncKm2 = Deep.distance(lat, lon, Deep.ORIGIN.lat, Deep.ORIGIN.lon) / 1000
    -- KB-349: Deep has no terrain, so the ground is a floor here; engaged or not, the Machine never goes through it
    -- (the 06:37 and 06:42 flights reached -18 km and -2.4 km)
    if alt <= (GD.route and Guid.groundBelow(GD.route, lat, lon) + 25 or GROUND_M) then
        if GD.engaged then log("GUIDANCE lost the Machine at %.0f m (%.0f m/s down)", alt, -vs) end
        exit(("came down %.0f km from Night City"):format(ncKm2), true)
        return
    end
    if not GD.engaged and vs < 0 then
        if ncKm2 < 60 and alt <= cfg.exitZ then exit("fell back through the bound")
        elseif ncKm2 >= 60 and alt <= 300 and not GD.prompt then exit(("came down %.0f km from Night City"):format(ncKm2), true) end
    end
end

-- KB-348: a frame that throws (a script budget, a bad value) must never strand the driver on a white screen with a
-- frozen car. The error is logged and the Machine is brought home over Night City.
-- Doc 58 (2026-10-12 05:44): a budget error raised OUTSIDE pcall(tick) -- in the handling below -- killed this thread
-- and left the Machine to the server. The whole iteration is guarded now; only Wait() is outside it.
local function frameOnce()
            local ok, err = pcall(tick)
            -- KB-369: a frame that only ran out of OPEN//77's per-frame budget (1.5 M instructions / ~6 ms; a garbage
            -- collection pause on a heavy frame is enough) is SKIPPED and the next frame carries on. Only a run of them
            -- (about two seconds) -- or any other error -- still brings the Machine home (KB-348).
            if ok then
                if A and (A.overBudget or 0) > 0 then log("budget recovered after %d skipped frame(s)", A.overBudget); A.overBudget = 0 end
            elseif A and tostring(err):find("budget exceeded", 1, true) then
                -- doc 58 (2026-10-12 05:58): a RUN of budget-skipped frames used to bring the Machine home (an Alcubierre
                -- engage was thrown back to Night City). A budget overrun is never a reason to end a flight: the frame is
                -- skipped, the Machine waits where it is, and the profile says why.
                A.overBudget = (A.overBudget or 0) + 1
                A.overBudgetTotal = (A.overBudgetTotal or 0) + 1
                A.overBudgetWindow = (A.overBudgetWindow or 0) + 1
                if A.overBudget == 1 or A.overBudget % 300 == 0 then log("frame over the script budget -- skipped (%s)%s", tostring(err),
                    A.overBudget > 1 and (" -- %d in a row"):format(A.overBudget) or "") end
            else
                log("FLIGHT ERROR, bringing you home: %s", tostring(err))
                -- KB-372: the reason reaches the server log too (it was only in the player's client log)
                pcall(TriggerServerEvent, "ncm:deep.render", '{"what":"flight_error","error":' .. string.format("%q", tostring(err):sub(1, 300)) .. '}')
                pcall(exit, "flight error", true)
            end
end
CreateThread(function()
    while true do
        if not A then
            Wait(100)
        else
            Wait(0)
            pcall(frameOnce)
        end
    end
end)

-- ------------------------------------------------------------------------------------------------ commands
RegisterCommand("ncm.deep.home", function() if A then exit("/ncm.deep.home", true) else log("not in deep space") end end, false)
RegisterCommand("ncm.deep.rig", function() rig = not rig; log("dev attitude rig %s", rig and "ON" or "OFF") end, false)
-- L341 (owner, 2026-10-07): `/ncm.eng.devfuel` and `/ncm.deep.go` are gone -- no typed fuel, no typed altitude. Dev
-- fuel survives only as the DEVELOPMENT server's own setting (server/fuel.lua `ncm_dev_fuel`), never on Online.
