-- ncm_world / server / deep -- L326: the handoff between REDengine and NCM's own universe. DEVELOPMENT ONLY.
--
-- Climbing through ENTER_Z (game height, below Snowglobe 0's 14 km rebase), the client hands the Machine to NCM: the
-- server freezes the car where it is (setFrozen: transform pinned, gravity and impulses stopped) and the client flies it
-- in NCM's real-scale Earth (core `space.deep`, drawn in a WebUI surface). Coming back down through the exit height,
-- the client says where it is; the server moves the car there and releases it, and the client gives back the velocity.
-- The server owns only the car's transform and freeze bit; it never decides what happens out there.
local function log(fmt, ...) print(("[ncm_world/deep] " .. fmt):format(...)) end

local ENTER_Z, EXIT_Z = 12000, 11500
local inDeep = {}   -- pid -> { vid, at, flags }

local function enabled()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    local env = ok and type(id) == "table" and id.environment or "development"
    return tostring(env) == "development"
end

local function driving(pid)
    local b = NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority and NcmVehicleAccess.bindingForAuthority(pid)
    return b and b.vehicleId and tonumber(b.vehicleId) or nil, b
end

-- Owner, 2026-10-06 (IDEA-1143, option 1): on the DEVELOPMENT server installed parts never overheat, the way dev fuel
-- never runs dry -- one RP-16 sheds a third of its heat and could not hold the Hella up for guidance (KB-349). Online is
-- untouched. A deliberate heat test turns it off with the convar `ncm_dev_heat 0`.
local function devHeat()
    if not enabled() then return false end
    local okC, v = pcall(GetConvar, "ncm_dev_heat", "1")
    return not okC or tostring(v) ~= "0"
end

RegisterNetEvent("ncm:deep.config.request", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    TriggerClientEvent("ncm:deep.config", pid, { enabled = enabled(), enterZ = ENTER_Z, exitZ = EXIT_Z,
        devFuel = NcmFuel_devFuel and NcmFuel_devFuel() or false, devHeat = devHeat(),
        -- L331: the labelled DEVELOPMENT attitude waiver, until the Machine carries an attitude part (convar to turn off)
        devAttitude = enabled() and tostring(GetConvar("ncm_dev_attitude", "1")) ~= "0",
        utc = Open77.time.unix(),   -- NCM's one clock: Deep's sun is the real sun (owner: "night = night")
        -- the visual ascent band (convars so it can be tuned to where REDengine actually runs out, without a build)
        ascentZ = tonumber(GetConvar("ncm_deep_ascent_z", "4000")) or 4000,
        maskNearM = tonumber(GetConvar("ncm_deep_mask_near", "9000")) or 9000,
        maskFarM = tonumber(GetConvar("ncm_deep_mask_far", "16000")) or 16000 })
end)

RegisterNetEvent("ncm:deep.enter", function(r)
    local pid = tonumber(source) or 0
    if pid <= 0 or not enabled() then return end
    local vid, b = driving(pid)
    if not vid then log("player=%d enter refused: not driving a bound Machine", pid); return end
    local okV, v = pcall(Open77.vehicles.get, vid)
    local okF, frozen, why = pcall(Open77.vehicles.setFrozen, vid, true)
    inDeep[pid] = { vid = vid, at = Open77.time.unix(), flags = okV and type(v) == "table" and v.flags or nil, asset = b and b.assetId }
    log("ENTER player=%d vehicle=%d asset=..%s at game (%.0f, %.0f, %.0f) v (%.1f, %.1f, %.1f) m/s -> frozen %s %s",
        pid, vid, tostring(b and b.assetId or "?"):sub(-6), okV and v.position and v.position.x or 0, okV and v.position and v.position.y or 0,
        okV and v.position and v.position.z or 0, type(r) == "table" and tonumber(r.vx) or 0, type(r) == "table" and tonumber(r.vy) or 0,
        type(r) == "table" and tonumber(r.vz) or 0, tostring(okF and frozen), tostring(okF and why or frozen))
    if NcmJourney then NcmJourney.start(pid, { asset = b and b.assetId, mass = type(r) == "table" and tonumber(r.mass) or nil,
        devices = type(r) == "table" and r.devices or nil, game = okV and type(v) == "table" and v.position or nil }) end
end)

RegisterNetEvent("ncm:deep.exit", function(r)
    local pid = tonumber(source) or 0
    local st = inDeep[pid]
    if not st or type(r) ~= "table" then return end
    inDeep[pid] = nil
    local x, y, z = tonumber(r.x) or 0, tonumber(r.y) or 0, tonumber(r.z) or EXIT_Z
    -- KB-349: never put the car back under the city (06:43 put it at z -2,431); the client now sends these home too
    if z < 1000 then z = EXIT_Z end
    local okT, moved, why = pcall(Open77.vehicles.setTransform, st.vid, { position = { x = x, y = y, z = z }, yaw = tonumber(r.yaw) or 0 })
    if st.flags ~= nil then pcall(Open77.vehicles.update, st.vid, { flags = st.flags }) end   -- setTransform clears flags
    local okF = pcall(Open77.vehicles.setFrozen, st.vid, false)
    log("EXIT player=%d vehicle=%d after %ds: back at game (%.0f, %.0f, %.0f)%s | landing was %.1f km from Night City | move %s %s, released %s",
        pid, st.vid, math.floor(Open77.time.unix() - st.at), x, y, z, r.clamped and " (clamped to the map)" or "", (tonumber(r.landKm) or 0),
        tostring(okT and moved), tostring(okT and why or moved), tostring(okF))
    TriggerClientEvent("ncm:deep.released", pid, { vid = st.vid })
    if NcmJourney then NcmJourney.finish(pid, tostring(r.why or "returned"), { landKm = tonumber(r.landKm), back = { x = x, y = y, z = z } }) end
end)

RegisterNetEvent("ncm:deep.telemetry", function(t)
    local pid = tonumber(source) or 0
    if not inDeep[pid] or type(t) ~= "table" then return end
    log("DEEP player=%d alt %.0f m | speed %.0f m/s (horizontal %.0f, vertical %+.0f; orbit at this altitude %.0f) | at %.4f, %.4f = %.1f km from Night City | "
        .. "landing %s | fuel %.1f kg | thrust %.0f N%s%s",
        pid, tonumber(t.alt) or 0, tonumber(t.speed) or 0, tonumber(t.hspeed) or 0, tonumber(t.vspeed) or 0, tonumber(t.orbit) or 0,
        tonumber(t.lat) or 0, tonumber(t.lon) or 0, tonumber(t.ncKm) or 0, tostring(t.landing or "?"), tonumber(t.fuelKg) or 0,
        tonumber(t.thrust) or 0, t.rig and " | dev attitude rig ON" or "", t.devices and (" | " .. tostring(t.devices)) or "")
    if NcmJourney then NcmJourney.sample(pid, t) end
end)

-- ------------------------------------------------------------------------------------------------ L327: guidance + embodiment
local Venues = NcmCore.get("space.venues")
local RaceWorld = NcmCore.get("space.raceworld")
local Embodiment = NcmCore.get("space.embodiment")
local BRIDGE = "http://127.0.0.1:47710"
local drivers, driversAt = nil, 0

--- NCM's own NPC drivers (paddock_person), as the race world needs them. Cached ten minutes.
local function npcDrivers()
    if drivers and Open77.time.unix() - driversAt < 600 then return drivers end
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    local sid = ok and type(id) == "table" and id.serverId or "ncm-devbox"
    local rows = MySQL.query.await([[SELECT person_id, display, attrs_json FROM paddock_person
        WHERE server_id=? AND role='driver' AND state='active' ORDER BY person_id]], { sid }) or {}
    local Json = NcmCore.get("vocabulary.json")
    local out = {}
    for i, r in ipairs(rows) do
        if i % 40 == 0 then Wait(0) end   -- KB-351: 744 JSON decodes in one slice exceeded the instruction quota
        local okA, a = pcall(Json.decode, tostring(r.attrs_json or "{}"))
        a = okA and type(a) == "table" and a or {}
        out[#out + 1] = { id = r.person_id, name = r.display, pace = (tonumber(a.race_pace) or 50) / 100,
            consistency = (tonumber(a.consistency) or 50) / 100, aggression = (tonumber(a.aggression) or 50) / 100,
            mistake = (tonumber(a.mistake_rate) or 50) / 100, night = (tonumber(a.night_skill) or 50) / 100,
            racecraft = (tonumber(a.racecraft) or 50) / 100 }
    end
    drivers, driversAt = out, Open77.time.unix()
    return out
end

-- the host bridge's reports (departure, results, probes), polled while anyone is embodied
local embodied = {}   -- pid -> venue id
local bridgeNext = 0
CreateThread(function()
    while true do
        Wait(2000)
        if next(embodied) then
            PerformHttpRequest(BRIDGE .. "/events?since=" .. bridgeNext, function(code, text)
                if tonumber(code) ~= 200 then return end
                local Json = NcmCore.get("vocabulary.json")
                local ok, r = pcall(Json.decode, tostring(text or "{}"))
                if not ok or type(r) ~= "table" then return end
                bridgeNext = tonumber(r.next) or bridgeNext
                for _, ev in ipairs(type(r.events) == "table" and r.events or {}) do
                    local who = next(embodied)
                    if who and NcmJourney then
                        if ev.type == "telemetry" then NcmJourney.hostSample(who, ev)
                        elseif ev.type == "probe" and ev.what == "airborneSpawn" then NcmJourney.mark(who, "physicalized", { host = "assetto_corsa", result = ev.result })
                        elseif ev.type == "probe" and (ev.what == "force" or ev.what == "thrust" or ev.what == "thermal") then NcmJourney.mark(who, "host_" .. ev.what, { result = ev.result, component = ev.component })
                        elseif ev.type == "departed" then NcmJourney.mark(who, "host_departed", { height = ev.height, up = ev.up }) end
                    end
                    if ev.type ~= "telemetry" then log("AC %s %s", tostring(ev.type), tostring(text):sub(1, 0) .. (function()
                        local okE, s = pcall(Json.encode, ev); return okE and s:sub(1, 300) or "?" end)()) end
                    if ev.type == "departed" then
                        for pid, venue in pairs(embodied) do
                            if venue == ev.venue then
                                embodied[pid] = nil
                                TriggerClientEvent("ncm:deep.resume", pid, ev)
                                log("RESUME player=%d from %s (height %.0f m, up %.0f m/s)", pid, venue, tonumber(ev.height) or 0, tonumber(ev.up) or 0)
                            end
                        end
                    end
                end
            end, "GET", "", {})
        end
    end
end)

RegisterNetEvent("ncm:deep.guidance", function(r)
    local pid = tonumber(source) or 0
    if type(r) ~= "table" then return end
    log("GUIDANCE player=%d %s %s%s", pid, tostring(r.event), tostring(r.venue), r.km and (" (%.0f km)"):format(r.km) or "")
    if NcmJourney then NcmJourney.mark(pid, r.event == "arrived" and "arrived" or ("guidance_" .. tostring(r.event)), { venue = r.venue, km = r.km }) end
end)

--- The player consented over a venue: what is racing there NOW (one clock), and ask the host bridge to physicalize it.
RegisterNetEvent("ncm:deep.embody.request", function(r)
    local pid = tonumber(source) or 0
    if type(r) ~= "table" or not inDeep[pid] then return end
    CreateThread(function()
        local v = Venues.get(tostring(r.venue or ""))
        if not v then return end
        local now = Open77.time.unix()
        -- KB-351: each step in its own slice, and said, so a quota failure names its step
        log("EMBODY player=%d over %s: asked (step: race world)", pid, v.id)
        if NcmJourney then NcmJourney.mark(pid, "embody_requested", { venue = v.id }) end
        -- L330: the Racing Week's calendar (its seed), and the session the clock is in -- never a race laid on for arrival
        local seed = NcmWeek and NcmWeek.seed and NcmWeek.seed() or nil
        local ss = RaceWorld.session(v, now, seed)
        local e = ss.event
        local drv = e and npcDrivers() or {}
        Wait(0)
        local field = e and RaceWorld.field(e, drv) or {}
        Wait(0)
        local st = e and RaceWorld.state(e, field, now) or nil
        Wait(0)
        local lh, sh = Venues.localHour(v, now)
        local machine = MySQL.single.await("SELECT vehicle_key FROM vehicle_asset WHERE asset_id=?", { tostring(r.asset or "") })
        local body = Embodiment.forMachine(machine and machine.vehicle_key)
        local top = {}
        if st then for i = 1, math.min(3, #st.cars) do top[#top + 1] = st.cars[i].driver.name end end
        log("EMBODY player=%d over %s (local %02d:%02d, solar %.1f h) | %s, %d min left | event %s %s %s lap %s/%s | body %s (%s) | %d NPC(s) in the field",
            pid, v.id, math.floor(lh), math.floor((lh % 1) * 60), sh, ss.name, math.floor((ss.endUtc - now) / 60),
            e and e.eventId or "none", e and e.family or "-", st and st.phase or "-",
            st and st.leaderLap or 0, e and e.laps or 0, body.car, body.why, #field)
        local driverId = NcmCanonical and NcmCanonical.driverOf(pid) or nil
        local payload = { player = pid, driverId = driverId, venue = v, layout = r.layout or v.layouts[1], body = body, arrival = r, event = e,
            state = st and { phase = st.phase, leaderLap = st.leaderLap, laps = st.laps, cars = (function()
                local c = {}
                for _, x in ipairs(st.cars) do c[#c + 1] = { id = x.driver.id, name = x.driver.name, car = x.car, lap = x.lap,
                    progress = x.progress, position = x.position, retired = x.retired, pace = x.driver.pace, aggression = x.driver.aggression,
                    consistency = x.driver.consistency, mistake = x.driver.mistake } end
                return c end)() } or nil,
            localHour = lh, solarHour = sh, sunAngle = Venues.acSunAngle(sh), utc = now,
            session = { kind = ss.kind, name = ss.name, startUtc = ss.startUtc, endUtc = ss.endUtc, remainingS = math.max(0, ss.endUtc - now) } }
        local Json = NcmCore.get("vocabulary.json")
        Wait(0)
        local okE, body2 = pcall(Json.encode, payload)
        Wait(0)
        local summary = { venue = v.name, family = e and e.family, phase = ss.name, lap = st and st.leaderLap, laps = e and e.laps,
            top = top, localHour = lh, body = body.car }
        PerformHttpRequest(BRIDGE .. "/embody", function(code, text, _, err)
            local ok = tonumber(code) == 200
            -- KB-352: status 0 = the request never left (it was `http.request` missing from the manifest); say why
            log("EMBODY bridge -> %s %s%s", tostring(code), tostring(text):sub(1, 160), err and (" | error: " .. tostring(err)) or "")
            summary.ac = ok and "opening" or ((tonumber(code) == 409 and tostring(text):match('"why": "([^"]+)"')) or ("Assetto Corsa bridge not reachable (" .. tostring(code) .. ")"))
            if ok then embodied[pid] = v.id end
            -- L329: the Machine is now canonically AT this place, embodied by Assetto Corsa (Cyberpunk may close)
            if ok and NcmCanonical and driverId then
                NcmCanonical.set(driverId, "host_surface", "assetto_corsa", v.id, { asset = r.asset, massKg = r.mass, devices = r.devices,
                    bindings = r.bindings, fuelKg = r.fuelKg, devFuel = r.devFuel, devHeat = r.devHeat }, true)
            end
            if NcmJourney then NcmJourney.mark(pid, ok and "host_launched" or "host_refused", { host = "assetto_corsa", code = tonumber(code) }) end
            summary.detail = ok and tostring(text) or nil
            TriggerClientEvent("ncm:deep.embody.status", pid, summary)
        end, "POST", okE and body2 or "{}", { ["Content-Type"] = "application/json" })
    end)
end)

-- L329: optional host adapters, asked for and reversed from the pad (no chat commands): the bridge owns the files.
RegisterNetEvent("ncm:deep.adapter", function(r)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(r) ~= "table" or not enabled() then return end
    local action = tostring(r.action or "status")
    local url = BRIDGE .. (action == "enable" and "/adapter/enable" or action == "disable" and "/adapter/disable" or "/adapter")
    PerformHttpRequest(url, function(code, text, _, err)
        local Json = NcmCore.get("vocabulary.json")
        local ok, st = pcall(Json.decode, tostring(text or "{}"))
        local on = ok and type(st) == "table" and st.enabled == true
        log("ADAPTER player=%d %s -> %s %s%s", pid, action, tostring(code), on and "enabled" or "disabled", err and (" | " .. tostring(err)) or "")
        local msg = tonumber(code) ~= 200 and ("Host adapters unavailable (" .. tostring(code) .. ")")
            or action == "enable" and "NCM Assetto Corsa adapter installed. Continuing the descent."
            or action == "disable" and "NCM Assetto Corsa adapter removed: Assetto Corsa is ordinary Assetto Corsa again. Your history stays."
            or ("NCM Assetto Corsa adapter: " .. (on and "ENABLED" or "not enabled"))
        TriggerClientEvent("ncm:deep.adapter.state", pid, { enabled = on, message = msg,
            venue = (action == "enable" and tonumber(code) == 200) and r.venue or nil })
    end, action == "status" and "GET" or "POST", action == "status" and "" or '{"why":"player, from the pad"}', { ["Content-Type"] = "application/json" })
end)

-- L330: the posted timetable of a place (its local time), so a driver can drop in when they choose
RegisterNetEvent("ncm:deep.schedule", function(id)
    local pid = tonumber(source) or 0
    local v = Venues.get(tostring(id or ""))
    if pid <= 0 or not v or not enabled() then return end
    local now = Open77.time.unix()
    local seed = NcmWeek and NcmWeek.seed and NcmWeek.seed() or nil
    local items = {}
    for i, it in ipairs(RaceWorld.schedule(v, now, seed, 4)) do
        local lh = Venues.localHour(v, it.startUtc)
        local hh, mm = math.floor(lh), math.floor((lh % 1) * 60)
        items[#items + 1] = ("%s %02d:%02d  %s%s%s"):format(i == 1 and "NOW " or "    ", hh, mm, it.name,
            it.family and (" (" .. it.family:gsub("_", " ") .. ")") or "", it.kind == "race" and it.laps and (", " .. it.laps .. " laps") or "")
        if i == 1 then items[#items] = items[#items] .. ("  -- %d min left"):format(math.floor((it.endUtc - now) / 60)) end
    end
    TriggerClientEvent("ncm:deep.schedule", pid, { venue = v.id, items = items })
end)

AddEventHandler("playerDropped", function()
    local pid = tonumber(source) or 0
    if NcmJourney then NcmJourney.finish(pid, "player_left") end
    embodied[pid] = nil   -- KB-354: a stale entry got the next player's AC departure (RESUME player=1 at 13:20)
    local st = inDeep[pid]
    if st then
        pcall(Open77.vehicles.setFrozen, st.vid, false)
        inDeep[pid] = nil
        log("player=%d left while in deep: vehicle %d released where it was frozen", pid, st.vid)
    end
end)

AddEventHandler("onResourceStart", function(name)
    if name == "ncm_world" then log("deep handoff %s: out at game z %d climbing, back at %d (development only)", enabled() and "ENABLED" or "disabled", ENTER_Z, EXIT_Z) end
end)
