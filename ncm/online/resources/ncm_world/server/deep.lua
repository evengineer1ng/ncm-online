-- ncm_world / server / deep -- L326: the handoff between REDengine and NCM's own universe. Development AND Online
-- (L341, owner 2026-10-07: "deep and flight are crucial to ship"); the dev waivers below stay development-only.
--
-- Climbing through ENTER_Z (game height, below Snowglobe 0's 14 km rebase), the client hands the Machine to NCM: the
-- server freezes the car where it is (setFrozen: transform pinned, gravity and impulses stopped) and the client flies it
-- in NCM's real-scale Earth (core `space.deep`, drawn in a WebUI surface). Coming back down through the exit height,
-- the client says where it is; the server moves the car there and releases it, and the client gives back the velocity.
-- The server owns only the car's transform and freeze bit; it never decides what happens out there.
local function log(fmt, ...) print(("[ncm_world/deep] " .. fmt):format(...)) end

local ENTER_Z, EXIT_Z = 12000, 11500
local inDeep = {}   -- pid -> { vid, at, flags }

local function environment()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    return tostring(ok and type(id) == "table" and id.environment or "unknown")
end
-- L341: Deep runs on Online too. What a Machine can do out there is what its owner bought and installed.
local function enabled() local env = environment(); return env == "development" or env == "online" end
-- The development waivers (dev heat, dev attitude, the ascent probe, the KSA rehearsal): never on Online.
local function development() return environment() == "development" end

-- KB-448: a join that resumes Deep (canonical.lua) materializes the Machine and freezes it on the SERVER before seating the
-- player, so the player never holds its physics and `bindingForAuthority` finds nothing: the 2026-10-11 02:57 rejoin's
-- ENTER was refused, every stage after it too, and the car stayed frozen at the 12,100 m spawn over Night City. The resume
-- leaves a claim on the vehicle it made for this player; ENTER accepts that one vehicle when no binding is proven.
NcmDeepResumeClaims = NcmDeepResumeClaims or {}   -- pid -> { vid, asset } (set by canonical.lua's resume)
local function driving(pid)
    local b, why = nil, nil
    if NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority then b, why = NcmVehicleAccess.bindingForAuthority(pid) end
    if b and b.vehicleId then return tonumber(b.vehicleId), b end
    local c = NcmDeepResumeClaims[pid]
    if c and tonumber(c.vid) then
        local okO, o = pcall(Open77.vehicles.owner, tonumber(c.vid))
        return tonumber(c.vid), { vehicleId = c.vid, assetId = c.asset, resumed = true,
            seat = okO and type(o) == "table" and ("driver %s, physics %s"):format(tostring(o.driver), tostring(o.physicsOwner or o.authorityPlayerId)) or "owner unknown" }
    end
    return nil, why
end

-- Owner, 2026-10-06 (IDEA-1143, option 1): on the DEVELOPMENT server installed parts never overheat, the way dev fuel
-- never runs dry -- one RP-16 sheds a third of its heat and could not hold the Hella up for guidance (KB-349). Online is
-- untouched. A deliberate heat test turns it off with the convar `ncm_dev_heat 0`.
local function devHeat()
    if not development() then return false end
    local okC, v = pcall(GetConvar, "ncm_dev_heat", "1")
    return not okC or tostring(v) ~= "0"
end

RegisterNetEvent("ncm:deep.config.request", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    TriggerClientEvent("ncm:deep.config", pid, { enabled = enabled(), enterZ = ENTER_Z, exitZ = EXIT_Z,
        devFuel = NcmFuel_devFuel and NcmFuel_devFuel() or false, devHeat = devHeat(),
        -- L331: the labelled DEVELOPMENT attitude waiver, until the Machine carries an attitude part (convar to turn off)
        devAttitude = development() and tostring(GetConvar("ncm_dev_attitude", "1")) ~= "0",
        utc = Open77.time.unix(),   -- NCM's one clock: Deep's sun is the real sun (owner: "night = night")
        -- the visual ascent band (convars so it can be tuned to where REDengine actually runs out, without a build)
        ascentZ = tonumber(GetConvar("ncm_deep_ascent_z", "4000")) or 4000,
        maskNearM = tonumber(GetConvar("ncm_deep_mask_near", "9000")) or 9000,
        maskFarM = tonumber(GetConvar("ncm_deep_mask_far", "16000")) or 16000,
        -- the ascent ring (NCM Sky kinds 10-14): from this game z up to the seam; its far edge kept this close to the eye
        ringOnZ = tonumber(GetConvar("ncm_deep_ring_z", "1500")) or 1500,
        ringFarM = tonumber(GetConvar("ncm_deep_ring_far", "6000")) or 6000,
        -- KB-377: the measurement build -- the ascent draws no Earth and logs the game's real camera (development only)
        ascentProbe = development() and tostring(GetConvar("ncm_deep_ascent_probe", "0")) == "1" })   -- off: IDEA-1174 reads the camera live
end)

RegisterNetEvent("ncm:deep.enter", function(r)
    local pid = tonumber(source) or 0
    if pid <= 0 or not enabled() then return end
    local vid, b = driving(pid)
    if not vid then log("player=%d enter refused: not driving a bound Machine (%s)", pid, tostring(b)); return end
    if b.resumed then
        NcmDeepResumeClaims[pid] = nil
        log("ENTER player=%d: the resumed Machine ..%s (vehicle %d, %s) taken from the join's claim", pid, tostring(b.assetId):sub(-6), vid, tostring(b.seat))
    end
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

-- L352: Deep in the game's own world. The client asks for its held car to be shown at a point of a stage of the
-- `ncm_world_layer` package (core space.stage); the server moves the frozen car there and keeps it frozen. Only points
-- inside a stage's shell are accepted, so this can never be used to move a car anywhere else.
local Stage = NcmCore.get("space.stage")
-- KB-444: Open77 does not keep the order of different net events (PRESENCE, sent after ENTER, was logged before it).
-- The client's one stage request, sent in ENTER's frame, could land before `inDeep` existed and was dropped without a
-- word, so the car stayed frozen at the seam over Night City while the sky was drawn at the stage. The client now
-- repeats the request until this handler acknowledges it (`ncm:deep.staged`, echoing its `seq`).
local earlyStage = {}   -- pid -> true once an early request has been logged for this wait
RegisterNetEvent("ncm:deep.stage", function(r)
    local pid = tonumber(source) or 0
    local st = inDeep[pid]
    if type(r) ~= "table" then return end
    if not st then
        if not earlyStage[pid] then
            earlyStage[pid] = true
            log("STAGE player=%d arrived before ENTER (net events are not ordered): the client repeats it", pid)
        end
        return
    end
    earlyStage[pid] = nil
    local function ack() TriggerClientEvent("ncm:deep.staged", pid, { seq = r.seq, stage = st.stage }) end
    local stage = Stage.STAGES[tostring(r.stage or "")]
    local x, y, z = tonumber(r.x), tonumber(r.y), tonumber(r.z)
    if not stage or not x or not y or not z then return end
    local dx, dy, dz = x - stage.center[1], y - stage.center[2], z - stage.center[3]
    if dx * dx + dy * dy + dz * dz > (stage.shellR - 50) ^ 2 then
        log("STAGE player=%d refused: (%.0f, %.0f, %.0f) is outside the %s shell", pid, x, y, z, tostring(r.stage))
        return
    end
    -- KB-438: ONE move per Deep entry. Every setTransform hands the car to the server and back (the 2026-10-10 stay
    -- flipped ownership 126 times in 22 s: the flicker); an older client that still re-stages on every turn is ignored.
    if st.staged then
        st.restageRefused = (st.restageRefused or 0) + 1
        if st.restageRefused == 1 then log("STAGE player=%d: already staged for this entry; further moves ignored", pid) end
        return ack()   -- a repeat whose acknowledgement was lost: say so again, never move again
    end
    st.staged = true
    local okT, moved, why = pcall(Open77.vehicles.setTransform, st.vid, { position = { x = x, y = y, z = z }, yaw = tonumber(r.yaw) or 0 })
    if st.flags ~= nil then pcall(Open77.vehicles.update, st.vid, { flags = st.flags }) end   -- setTransform clears flags
    pcall(Open77.vehicles.setFrozen, st.vid, true)
    if st.stage ~= r.stage then
        st.stage = r.stage
        log("STAGE player=%d vehicle=%d -> %s at (%.0f, %.0f, %.0f): move %s %s", pid, st.vid, tostring(r.stage), x, y, z,
            tostring(okT and moved), tostring(okT and why or moved))
    end
    ack()
end)

-- L332: the Deep page's render probes (WebGL facts, the render scale, whether imagery tiles arrive), one line each
RegisterNetEvent("ncm:deep.render", function(t)
    log("RENDER PROBE player=%d %s", tonumber(source) or 0, tostring(t):sub(1, 700))
end)

RegisterNetEvent("ncm:deep.telemetry", function(t)
    local pid = tonumber(source) or 0
    if not inDeep[pid] or type(t) ~= "table" then return end
    log("DEEP player=%d alt %.0f m | speed %.0f m/s (horizontal %.0f, vertical %+.0f; orbit at this altitude %.0f) | at %.4f, %.4f = %.1f km from Night City | "
        .. "landing %s | fuel %.1f kg | thrust %.0f N%s%s",
        pid, tonumber(t.alt) or 0, tonumber(t.speed) or 0, tonumber(t.hspeed) or 0, tonumber(t.vspeed) or 0, tonumber(t.orbit) or 0,
        tonumber(t.lat) or 0, tonumber(t.lon) or 0, tonumber(t.ncKm) or 0, tostring(t.landing or "?"), tonumber(t.fuelKg) or 0,
        tonumber(t.thrust) or 0, t.rig and " | dev attitude rig ON" or "", t.devices and (" | " .. tostring(t.devices)) or "")
    if t.guidance then log("GUIDE player=%d %s", pid, tostring(t.guidance):sub(1, 240)) end   -- KB-376
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
        -- L336: the Machine's passport picks its AC body and skin (sticky); the old table only if the roster is unavailable
        local body = machine and NcmPassport and NcmPassport.expressAc(tostring(r.asset)) or nil
        if not body then body = Embodiment.forMachine(machine and machine.vehicle_key) end
        Wait(0)
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

-- L335: KITTEN SPACE AGENCY -- the pre-flight checks, the placement self-test and the handoff at the border, relayed to
-- the host bridge (which owns KSA, StarMap and the NcmKsa mod). Nothing here decides whether KSA is ready: the bridge
-- answers from the files and from KSA itself.
local function ksaRelay(pid, path, method, body, reply)
    PerformHttpRequest(BRIDGE .. path, function(code, text, _, err)
        local Json = NcmCore.get("vocabulary.json")
        local ok, st = pcall(Json.decode, tostring(text or "{}"))
        reply(tonumber(code) or 0, ok and type(st) == "table" and st or {}, err)
    end, method, body or "", { ["Content-Type"] = "application/json" })
end
-- KB-375: no KSA call before consent -- the client only learns whether this is a development server (the L3 rehearsal)
RegisterNetEvent("ncm:deep.ksa.preflight", function()
    local pid = tonumber(source) or 0
    if pid <= 0 or not inDeep[pid] then return end
    TriggerClientEvent("ncm:deep.ksa.preflight", pid, { dev = development() })
end)
RegisterNetEvent("ncm:deep.ksa.selftest", function()
    local pid = tonumber(source) or 0
    if pid <= 0 or not inDeep[pid] then return end
    log("KSA ACTIVATE player=%d consented: start KSA and prove a placement", pid)
    local function done(r, how)
        log("KSA SELFTEST player=%d -> %s %s%s", pid, r.ok and "PASS" or "FAIL", tostring(r.why or r.error or ""), how or "")
        TriggerClientEvent("ncm:deep.ksa.selftest", pid, { ok = r.ok == true, why = r.why or r.error, errors = r.errors })
    end
    -- KB-374: starting KSA takes ~25 s and this HTTP call stops waiting at 10 s (it said "FAIL nil" over a PASS). Note the
    -- bridge's self-test counter first; if the reply never comes, read the verdict when the counter moves (up to 4 min).
    ksaRelay(pid, "/ksa/selftest-result", "GET", nil, function(_, before)
        local seq0 = tonumber(before.seq) or 0
        ksaRelay(pid, "/ksa/selftest", "POST", "{}", function(code, r)
            if code == 200 or r.ok ~= nil then return done(r) end
            CreateThread(function()
                local t0 = Open77.time.unix()
                while Open77.time.unix() - t0 < 240 do
                    Wait(3000)
                    local got
                    ksaRelay(pid, "/ksa/selftest-result", "GET", nil, function(_, res) got = res end)
                    local w0 = Open77.time.unix()
                    while got == nil and Open77.time.unix() - w0 < 12 do Wait(200) end
                    if got and (tonumber(got.seq) or 0) > seq0 then return done(got, " (read back after KSA started)") end
                end
                done({ ok = false, why = "the bridge never finished the self-test (4 min)" })
            end)
        end)
    end)
end)
RegisterNetEvent("ncm:deep.ksa.embody", function(r)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(r) ~= "table" or not inDeep[pid] then return end
    local driverId = NcmCanonical and NcmCanonical.driverOf(pid) or nil
    r.driverId = driverId
    -- L336: the Machine's KSA body, chosen through its passport (sticky, recorded) -- the craft KSA spawns at the handoff
    local kb = r.asset and NcmPassport and NcmPassport.expressKsa(tostring(r.asset)) or nil
    r.ksaBody = kb and kb.body or "NcmHella"   -- cross-scope-ok: a KSA craft id (a string), not a global
    local Json = NcmCore.get("vocabulary.json")
    local okE, body = pcall(Json.encode, r)
    log("KSA EMBODY player=%d at %.4f, %.4f alt %.0f km (%s)", pid, tonumber(r.lat) or 0, tonumber(r.lon) or 0, (tonumber(r.altM) or 0) / 1000,
        r.rehearsal and "DEV REHEARSAL" or "the border")
    if NcmJourney then NcmJourney.mark(pid, "embody_requested", { venue = "ksa_border", host = "ksa" }) end
    ksaRelay(pid, "/ksa/embody", "POST", okE and body or "{}", function(code, res)
        local ok = code == 200 and res.ok == true
        log("KSA EMBODY player=%d -> %d %s %s", pid, code, ok and "VERIFIED" or "REFUSED", tostring(res.why or ""))
        if ok and NcmCanonical and driverId then
            -- the Machine is now canonically in Kitten Space Agency, past Deep
            NcmCanonical.set(driverId, "host_space", "ksa", "ksa_border", { asset = r.asset, massKg = r.massKg, devices = r.devices,
                ksa = res.placed }, true)
        end
        if NcmJourney then NcmJourney.mark(pid, ok and "host_launched" or "host_refused", { host = "ksa", code = code }) end
        TriggerClientEvent("ncm:deep.ksa.status", pid, { ok = ok, why = res.why, errors = res.errors })
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
    NcmDeepResumeClaims[pid] = nil   -- KB-448: a claim never outlives its player
    local st = inDeep[pid]
    if st then
        pcall(Open77.vehicles.setFrozen, st.vid, false)
        inDeep[pid] = nil
        log("player=%d left while in deep: vehicle %d released where it was frozen", pid, st.vid)
    end
end)

-- IDEA-1294 (owner, 2026-10-11: "instrument ... observationally; do not perturb the Galena"): once a minute, every
-- Machine whose stored presence says `deep` (flown by its client or by the server) is logged in BOTH frames. Read-only:
-- it decodes the stored record and writes a log line, nothing else. EARTH-FIXED = the rotating frame the HUD's SPEED /
-- horizontal / vertical use; INERTIAL = Earth-fixed velocity + W x p, the frame the orbit (energy, h, apo/peri) uses.
local DeepCore = NcmCore.get("space.deep")
local function frameLine(row)
    local Json = NcmCore.get("vocabulary.json")
    local ok, rec = pcall(Json.decode, tostring(row.state_json or ""))
    if not ok or type(rec) ~= "table" or type(rec.p) ~= "table" or type(rec.vel) ~= "table" then return end
    local V = DeepCore.vec
    local p, v = rec.p, rec.vel
    local r = V.len(p)
    local lat, lon, alt = DeepCore.ecefToLla(p)
    local e, n, u = DeepCore.enu(lat, lon)
    local vs, sp = V.dot(v, u), V.len(v)
    local vi = DeepCore.inertialVel(p, v)
    local rad = V.dot(vi, V.scale(p, 1 / r))
    local tan = math.sqrt(math.max(0, V.dot(vi, vi) - rad * rad))
    local o = DeepCore.orbit(p, v)
    local rho2 = p[1] ^ 2 + p[2] ^ 2
    local dyn = type(rec.dyn) == "table" and rec.dyn or {}
    local thr = type(dyn.thr) == "table" and dyn.thr or {}
    local thrTxt = {}
    for _, x in ipairs(thr) do thrTxt[#thrTxt + 1] = ("%.2f"):format(tonumber(x) or 0) end
    log("FRAME driver ..%s %s via %s, record %.0f s old (%s) | r %.0f km alt %.0f km at %.4f, %.4f | p ECEF (%.0f, %.0f, %.0f) km"
        .. " | EARTH-FIXED v (%.1f, %.1f, %.1f) |v| %.1f = horizontal %.1f (E %+.1f N %+.1f) + vertical %+.1f, frame sweep W*rho %.1f"
        .. " | INERTIAL |v| %.1f = radial %+.1f tangential %.1f | g %.4f, coriolis+centrifugal %.4f m/s^2 | thrust state [%s], spin %.4f rad/s"
        .. " | energy %.1f J/kg h %.6e m2/s e %.6f apo %s km peri %.0f km | Jacobi %.2f J/kg",
        tostring(row.driver_id):sub(-6), tostring(row.place), tostring(row.host or "server"), Open77.time.unix() - (tonumber(rec.utc) or 0),
        type(rec.provenance) == "table" and tostring(rec.provenance[1]) or "?", r / 1000, alt / 1000, lat, lon, p[1] / 1000, p[2] / 1000, p[3] / 1000,
        v[1], v[2], v[3], sp, math.sqrt(math.max(0, sp * sp - vs * vs)), V.dot(v, e), V.dot(v, n), vs, DeepCore.OMEGA * math.sqrt(rho2),
        V.len(vi), rad, tan, V.len(DeepCore.gravity(p)), V.len(DeepCore.fictitious(p, v)), table.concat(thrTxt, ","),
        type(dyn.omega) == "table" and V.len(dyn.omega) or 0,
        o.energy, V.len(V.cross(p, vi)), o.e, o.apoM and ("%.0f"):format(o.apoM / 1000) or "ESCAPE", o.periM / 1000,
        V.dot(v, v) / 2 - DeepCore.GM / r - DeepCore.OMEGA ^ 2 * rho2 / 2)
end
CreateThread(function()
    Wait(30000)
    while true do
        if enabled() and MySQL and MySQL.query then
            local okI, id = pcall(function() return GlobalState.ncmIdentity end)
            local sid = okI and type(id) == "table" and id.serverId or nil
            local okQ, rows = pcall(MySQL.query.await, "SELECT driver_id, place, host, state_json FROM ncm_presence WHERE server_id=? AND place='deep'", { sid })
            for _, row in ipairs(okQ and type(rows) == "table" and rows or {}) do
                local okF, err = pcall(frameLine, row)
                if not okF then log("FRAME driver ..%s not readable: %s", tostring(row.driver_id):sub(-6), tostring(err)) end
                Wait(0)
            end
        end
        Wait(60000)
    end
end)

AddEventHandler("onResourceStart", function(name)
    if name == "ncm_world" then log("deep handoff %s: out at game z %d climbing, back at %d (%s)", enabled() and "ENABLED" or "disabled", ENTER_Z, EXIT_Z, environment()) end
end)
