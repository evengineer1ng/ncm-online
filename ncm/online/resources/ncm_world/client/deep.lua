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
local Json = Core.get("vocabulary.json")

local function log(fmt, ...) print(("[ncm_world/client/deep] " .. fmt):format(...)) end
local function ms() return GetGameTimer() end

local MASS_KG = 1800            -- the Hella's physics body as the Carrier measures it (thrust log: mass=1800 kg)
local RIG_RATE = 1.1            -- rad/s at full stick
local MAP = { xmin = -6500, xmax = 6500, ymin = -8500, ymax = 5000 }   -- where a returning car may be put down
local RETURN_DV_MAX = 80        -- m/s: 150 kN x 1 s on 1.8 t (the Carrier's clamp)
local GROUND_M = 300            -- KB-349: Deep has no terrain; below this the trip ends (home over Night City)
local EXIT_SAFE_M = 3000        -- KB-349: a return from lower than this comes home at the bound, at rest

local cfg = { enabled = false, enterZ = 12000, exitZ = 11500, ascentZ = 4000, maskNearM = 9000, maskFarM = 16000 }
--- NCM's one clock on this client: the server's UTC at config time, advanced by the game timer
local utcBase, utcAtMs = nil, 0
local function utcNow() return utcBase and (utcBase + (GetGameTimer() - utcAtMs) / 1000) or nil end
local function sunNow() local u = utcNow(); return u and Deep.sunAt(u) or Deep.sun(13) end
local ASC = nil                 -- the ascent page (transparent Deep, before the seam): { page, ready }
local A = nil                   -- the active flight
local GD                        -- the guidance computer (below); exit() resets it
local samples = {}              -- recent { t, x, y, z } of the car, for a velocity at the handoff
local rig = true
local camMode = 1
local CAM_NAMES = { "chase", "high", "earth" }

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
        vehicleKey = EN and EN.vehicleKey or "archer_hella", dyn = A.dyn and Flight.carry(A.dyn) or nil,
        guidance = (GD and GD.route) and { venueId = GD.route.venue.id, engaged = GD.engaged == true } or nil })
    TriggerServerEvent("ncm:canonical.save", { place = place or "deep", rec = rec, transition = transition == true, locationId = locationId })
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
            transparent = false, visible = true, fps = 60 })
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
    if type(m) == "table" and Venues.VENUES[GD.sel] and m.venue == Venues.VENUES[GD.sel].id then GD.schedule = m.items end
end)

-- ------------------------------------------------------------------------------------------------ config + watch
RegisterNetEvent("ncm:deep.config", function(c)
    if type(c) ~= "table" then return end
    cfg.enabled, cfg.enterZ, cfg.exitZ = c.enabled == true, tonumber(c.enterZ) or cfg.enterZ, tonumber(c.exitZ) or cfg.exitZ
    -- the development server takes care of fuel (owner, 2026-10-06): nothing burns, the parts never starve
    if c.devFuel == true then NcmClientDevFuel = true end
    if tonumber(c.utc) then utcBase, utcAtMs = tonumber(c.utc), GetGameTimer() end
    cfg.ascentZ = tonumber(c.ascentZ) or cfg.ascentZ
    cfg.maskNearM, cfg.maskFarM = tonumber(c.maskNearM) or cfg.maskNearM, tonumber(c.maskFarM) or cfg.maskFarM
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
                            pcall(function() page:send("deep:init", { ascent = true, nc = Deep.ORIGIN, R = Deep.R, sun = sunNow(),
                                sprite = "deep/sprites/machine.png", earth = "deep/earth.jpg", venues = {} }) end)
                            mine.ready = true
                        end)
                        log("ASCENT overlay on at game z %.0f (Deep at %d)", p.z, cfg.enterZ)
                    end
                elseif ASC.ready then
                    local okF, f = pcall(Open77.character.frame, { vehicleId = vid })
                    local s = Deep.enter({ p.x, p.y, p.z }, { 0, 0, 0 }, okF and type(f) == "table" and f or nil)
                    local k = math.max(0, math.min(1, (p.z - cfg.ascentZ) / math.max(1, cfg.enterZ - cfg.ascentZ)))
                    pcall(function() ASC.page:send("deep:ascent", { sun = sunNow(), p = s.p, f = s.basis.forward, u = s.basis.up, k = k * k * (3 - 2 * k),
                        alt = p.z, toSeam = cfg.enterZ - p.z, d0 = cfg.maskNearM, d1 = cfg.maskFarM }) end)
                    geoTick(ASC.page, s, GetGameTimer(), nil)
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

local function guidanceInput(now, dt)
    local openE = edge("open", down("padUp") or down("G"))
    local prevE = edge("prev", down("padLeft") or down("Z"))
    local nextE = edge("next", down("padRight") or down("C"))
    local aE = edge("a", down("padA") or down("F"))
    local backDown = down("padB") or down("X")
    local backE = edge("b", backDown)
    local alwaysE = edge("always", down("padX") or down("R"))
    local zoomE = edge("zoom", GD.open and (down("padRightThumb")) or false)

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
        local n = #Venues.VENUES
        if prevE then GD.sel = (GD.sel - 2) % n + 1; GD.panLat, GD.panLon = 0, 0 end
        if nextE then GD.sel = GD.sel % n + 1; GD.panLat, GD.panLon = 0, 0 end
        -- L330: the posted timetable of the selected place (asked again every 30 s while guidance is open)
        if prevE or nextE or openE or now - (GD.schedAt or 0) > 30000 then
            GD.schedAt, GD.schedule = now, nil
            TriggerServerEvent("ncm:deep.schedule", Venues.VENUES[GD.sel].id)
        end
        if zoomE then GD.zoom = GD.zoom % #ZOOMS + 1 end
        local px, py = dead(axis("padRightStickX")), dead(axis("padRightStickY"))
        local rate = ZOOMS[GD.zoom] / 1000000 * 8 * dt
        GD.panLon, GD.panLat = GD.panLon + px * rate, math.max(-60, math.min(60, GD.panLat + py * rate))
        if aE then
            if GD.engaged then GD.engaged = false; GD.msg = "Autopilot off: you have the Machine."
            else
                -- KB-349: only a Machine that can hold itself up on thrust it can keep making (heat included)
                local EN = NcmClientEngineering and NcmClientEngineering.get() or nil
                local sus = Guid.thrustBudget(EN and EN.devices or {}, nil, NcmClientDevHeat)
                local okF, tw, why = Guid.feasible(sus, A.mass)
                if not okF then
                    GD.msg = ("Guidance cannot fly this Machine to %s: %s."):format(Venues.VENUES[GD.sel].name, why)
                    log("GUIDANCE refused -> %s: %s", Venues.VENUES[GD.sel].id, why)
                    TriggerServerEvent("ncm:deep.guidance", { event = "refused", venue = Venues.VENUES[GD.sel].id })
                    return
                end
                GD.route = Guid.plan(A.s, Venues.VENUES[GD.sel])
                GD.engaged, GD.hold = true, nil
                GD.msg = nil
                local pts = {}
                for _, w in ipairs(GD.route.waypoints) do pts[#pts + 1] = { w.lat, w.lon } end
                pts[#pts + 1] = { GD.route.arrival.lat, GD.route.arrival.lon }
                send("deep:route", { points = pts })
                log("GUIDANCE engaged -> %s (%.0f km, %d waypoint(s))", GD.route.venue.id, GD.route.distanceM / 1000, #GD.route.waypoints)
                TriggerServerEvent("ncm:deep.guidance", { event = "engaged", venue = GD.route.venue.id, km = GD.route.distanceM / 1000 })
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

local function tick()
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
    if not A then return end   -- held B brought us home

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
        A.dyn = Flight.state(A.fm, A.s, A.dyn and Flight.carry(A.dyn) or A.resumeDyn)
        A.fmKey = key
    end
    local m, ds = A.fm, A.dyn
    local devAtt = NcmClientDevAttitude == true
    local cmd = { throttle = {}, discharge = {} }
    local opts = { devFuel = NcmClientDevFuel == true, devHeat = NcmClientDevHeat == true }
    if EN and #devs > 0 then
        local pressed = {}
        for _, c in ipairs(EN.controls) do pressed[c] = down(c) end
        local cmds = Controls.step(EN.ctl, EN.bindings, EN.devices, pressed, now)
        if GD.hold then for _, c in pairs(pressed) do if c then GD.hold, GD.route = nil, nil; GD.msg = "You have the Machine." break end end end
        for id, c in pairs(cmds) do
            if c.throttle then cmd.throttle[id] = c.throttle end
            if c.discharge then cmd.discharge[id] = true; A.report.pulses = A.report.pulses + 1 end
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
            local gc, waiver, info = Guid.fly(GD.route, m, ds, { devHeat = opts.devHeat, waiver = devAtt and #(m.attitude or {}) == 0 })
            for id, th in pairs(gc.throttle) do cmd.throttle[id] = th end
            if gc.torque then cmd.torque = gc.torque end
            opts.waiver = waiver
            gcmd = info
            local thr = 0
            for _, th in pairs(gc.throttle) do thr = math.max(thr, th) end
            gcmd.throttle = thr
            if GD.engaged and Guid.arrived(GD.route, Flight.deep(ds)) then
                GD.engaged = false
                GD.prompt = GD.route.venue
                GD.msg = nil
                log("GUIDANCE arrived over %s", GD.route.venue.id)
                TriggerServerEvent("ncm:deep.guidance", { event = "arrived", venue = GD.route.venue.id })
                if GD.always then local v = GD.prompt; GD.prompt = nil; requestEmbodiment(v) end
            end
        end
    end
    local fuel0 = Flight.fuelKg(m, ds)
    local tel
    ds, tel = Flight.step(m, ds, cmd, dt, opts)
    A.dyn = ds
    if EN and not opts.devFuel then
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
        for _, d in ipairs(devs) do
            for i, md in ipairs(m.devices) do if md.componentId == d.componentId then parts[i] = parts[i]:gsub("^[^ ]+", d.code) end end
        end
        devText = table.concat(parts, " | ")
    elseif GD.engaged then
        GD.engaged, GD.msg = false, "Guidance cannot fly this Machine: it has no installed propulsion."
    end
    A.authority = Flight.authorityText(m)
    A.spin = Deep.vec.len(ds.omega)

    local lat, lon, alt = Deep.ecefToLla(A.s.p)
    local e, n, u = Deep.enu(lat, lon)
    local vs = Deep.vec.dot(A.s.v, u)
    local speed = Deep.vec.len(A.s.v)
    local hs = math.sqrt(math.max(0, speed * speed - vs * vs))
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
    geoTick(A.page, A.s, now, GD.route and GD.route.venue and { lat = GD.route.venue.lat, lon = GD.route.venue.lon } or nil)
    if now - A.lastSend >= 33 then
        A.lastSend = now
        local sel = Venues.VENUES[GD.sel]
        local g = {
            open = GD.open, sel = GD.sel, engaged = GD.engaged, msg = GD.msg, always = GD.always,
            prompt = GD.prompt and GD.prompt.name or nil,
            consent = GD.consent and GD.consent.name or nil, adapters = GD.adapters and { ac = GD.acEnabled == true } or nil,
            schedule = GD.schedule,
            selName = sel.name, selRegion = sel.region,
            selKm = Deep.distance(lat, lon, sel.lat, sel.lon) / 1000,
            backHold = GD.backSince and math.min(1, (now - GD.backSince) / 2000) or 0,
        }
        if gcmd then
            g.phase, g.target, g.km, g.eta, g.throttle, g.vWant = gcmd.phase, GD.route.venue.name, gcmd.distanceM / 1000, gcmd.etaS, gcmd.throttle, gcmd.vWant
        end
        if GD.open then
            g.cam = { lat = sel.lat + GD.panLat, lon = sel.lon + GD.panLon, alt = ZOOMS[GD.zoom] }
        end
        send("deep:state", {
            p = A.s.p, v = A.s.v, r = A.s.basis.right, f = A.s.basis.forward, u = A.s.basis.up,
            alt = alt, lat = lat, lon = lon, speed = speed, hs = hs, vs = vs, orbit = Deep.orbitSpeed(alt),
            fuelKg = EN and EN.fuelKg or nil, thrust = A.thrustN, devices = devText, impact = A.impact, land = A.land,
            rig = rig and not GD.engaged, cam = CAM_NAMES[camMode], zoom = A.zoom or 22, t = (now - A.startedAt) / 1000, devFuel = NcmClientDevFuel == true,
            twr = (A.fm and (function() local t = 0 for _, d in ipairs(A.fm.devices) do if d.kind == "reaction_engine" then t = t + (d.perf.thrustN or 0) end end return t end)() or 0)
                / (A.mass * Deep.vec.len(Deep.gravity(A.s.p))), guidance = g, sun = sunNow(),
            authority = A.authority, waiver = A.waiverOn, spin = A.spin, rho = Flight.density(alt),
        })
    end
    if now - A.lastTele >= 1000 then
        checkpoint("deep", false)
        A.lastTele = now
        local ncKm = Deep.distance(lat, lon, Deep.ORIGIN.lat, Deep.ORIGIN.lon) / 1000
        TriggerServerEvent("ncm:deep.telemetry", { alt = alt, speed = speed, hspeed = hs, vspeed = vs, orbit = Deep.orbitSpeed(alt),
            lat = lat, lon = lon, ncKm = ncKm, landing = A.impact, fuelKg = EN and EN.fuelKg or 0, thrust = A.thrustN, rig = rig,
            devices = devText, guidance = gcmd and ("%s -> %s %.0f km eta %.0f s throttle %.2f"):format(gcmd.phase, GD.route.venue.id,
                gcmd.distanceM / 1000, gcmd.etaS, gcmd.throttle) or nil })
        if EN and A.report.kg > 0 then
            TriggerServerEvent("ncm:engineering.burn", { assetId = EN.assetId, kg = A.report.kg, dtS = (now - A.report.since) / 1000,
                pulses = A.report.pulses, t = { devices = devText, f = A.thrustN, z = alt, speed = speed,
                    loss = "in NCM deep space (no REDengine): force at CoM; attitude by the dev rig / guidance assist" } })
        end
        A.report = { kg = 0, pulses = 0, since = now }
    end
    -- back into Night City only near Night City; anywhere else low altitude is that place's business (its embodiment
    -- host), and coming down to the ground far from any host ends the trip home
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
CreateThread(function()
    while true do
        if not A then
            Wait(100)
        else
            Wait(0)
            local ok, err = pcall(tick)
            if not ok then
                log("FLIGHT ERROR, bringing you home: %s", tostring(err))
                pcall(exit, "flight error", true)
            end
        end
    end
end)

-- ------------------------------------------------------------------------------------------------ commands
RegisterCommand("ncm.deep.home", function() if A then exit("/ncm.deep.home", true) else log("not in deep space") end end, false)
RegisterCommand("ncm.deep.rig", function() rig = not rig; log("dev attitude rig %s", rig and "ON" or "OFF") end, false)
--- `/ncm.eng.devfuel` (DEVELOPMENT ONLY): installed components burn nothing and report nothing, in Night City and in deep
--- space, until toggled off. A developer convenience, never a game rule: the HUD says DEV FUEL while it is on.
RegisterCommand("ncm.eng.devfuel", function()
    if not cfg.enabled then log("dev fuel is development-only"); return end
    NcmClientDevFuel = not NcmClientDevFuel
    print(("[ENG] DEV FUEL %s: installed components %s"):format(NcmClientDevFuel and "ON" or "OFF", NcmClientDevFuel and "burn nothing (dev only)" or "burn the Machine's tank again"))
end, false)
--- `/ncm.deep.go [km]` (dev): leave now, starting `km` up (default 30) at rest -- to test without the climb. Starting
--- at the 12 km bound left 500 m before the return (owner: "couldnt get it to keep me going higher").
RegisterCommand("ncm.deep.go", function(_, args)
    if not cfg.enabled then log("deep is off on this server"); return end
    local vid = seat()
    local okV, v = pcall(Open77.vehicles.get, vid)
    if not (vid and okV and type(v) == "table" and v.position) then log("get in your car first"); return end
    local p = v.position
    local km = math.max(cfg.enterZ / 1000 + 1, math.min(2000, tonumber(args and args[1]) or 30))
    samples = {}
    enter(vid, { x = p.x, y = p.y, z = km * 1000 }, "/ncm.deep.go " .. km .. " km")
end, false)
