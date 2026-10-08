-- ncm_world / server / canonical -- L329 ("NCM 3.0 - one universe"): where every driver's Machine canonically IS.
--
-- The NCM server owns it, not a host. A host that embodies a Machine checkpoints its `space.canonical` record here
-- (Cyberpunk through `ncm:canonical.save`, Assetto Corsa through the host bridge); when no host has checkpointed a
-- Deep Machine for UNHOSTED_S, the server flies it itself with the same core (owner ruling: "autopilot keeps going";
-- otherwise gravity), in budget-sized slices (KB-336 / KB-351). One record per driver (`ncm_presence`, schema 068).
--
-- It also publishes the UNIVERSE to the local host bridge (utc, Race Week, the driver records, the place registry) so
-- a host that is not Cyberpunk -- Assetto Corsa, started on its own -- sees the same clock and the same Deep.
-- DEVELOPMENT and SINGLE PLAYER (L338); never Online.
local function log(fmt, ...) print(("[ncm_world/canonical] " .. fmt):format(...)) end
local Canon = NcmCore.get("space.canonical")
local Places = NcmCore.get("space.places")
local Json = NcmCore.get("vocabulary.json")
local BRIDGE = "http://127.0.0.1:47710"
local UNHOSTED_S = 15
local SLICE = 400
-- KB-358 (KB-347's shape): a nil in the middle of a Lua parameter list is a hole -- the insert silently failed for every
-- unresolved place (no lat/lon). NULL is spelled out in the statement for each nil value instead.
local function sqlValues(cols, vals, n)
    local marks, out = {}, {}
    for i = 1, n do
        if vals[i] == nil then marks[i] = "NULL" else marks[i] = "?"; out[#out + 1] = vals[i] end
    end
    return "(" .. cols .. ") VALUES (" .. table.concat(marks, ",") .. ")", out
end

NcmCanonical = {}
local rows = {}          -- driverId -> { place, host, locationId, rec, run, updatedAt, hostedAt, dirty }

local function now() return Open77.time.unix() end
local function sid()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    return ok and type(id) == "table" and id.serverId or "ncm-devbox"
end
local function enabled()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    local env = ok and type(id) == "table" and id.environment or "unknown"
    -- single player (L338): the temporal loop is the tape's own -- presence and the rollover reset belong to NCM 3.0
    -- L341: Online too -- Deep and the Racing Week loop ship together (owner: "everything goes to online")
    return tostring(env) == "development" or tostring(env) == "single_player" or tostring(env) == "online"
end
local function week()
    local ok, w = pcall(function() return GlobalState.ncmWeek end)
    return ok and type(w) == "table" and w or nil
end
local function runNow() local w = week(); return w and tonumber(w.run) or nil end

local function persist(driverId)
    local r = rows[driverId]
    if not r or not MySQL then return end
    r.dirty = false
    local okE, sj = true, nil
    if r.rec then okE, sj = pcall(Json.encode, r.rec) end
    local vals, args = sqlValues("driver_id, server_id, place, host, location_id, state_json, race_week_run, updated_at",
        { driverId, sid(), r.place, r.host, r.locationId, okE and sj or nil, r.run, math.floor(r.updatedAt) }, 8)
    -- its own thread: callers include HTTP callbacks (the bridge relay, the embodiment reply), which are not threads (KB-358)
    CreateThread(function()
        local ok, err = pcall(MySQL.update.await, "INSERT INTO ncm_presence " .. vals .. [[ ON DUPLICATE KEY UPDATE place=VALUES(place), host=VALUES(host),
            location_id=VALUES(location_id), state_json=VALUES(state_json), race_week_run=VALUES(race_week_run), updated_at=VALUES(updated_at)]], args)
        if not ok then log("could not store presence ..%s: %s", tostring(driverId):sub(-6), tostring(err)) end
    end)
end

--- Where is this driver? (cached; loaded at boot)
function NcmCanonical.get(driverId) return driverId and rows[driverId] or nil end

--- Record where a driver is. place: surface | deep | host_surface | landed. `rec` = the space.canonical record (deep).
--- `transition` persists at once; a running Deep checkpoint persists at most every 5 s.
function NcmCanonical.set(driverId, place, host, locationId, rec, transition)
    if not driverId then return end
    local r = rows[driverId] or {}
    local t = now()
    local fresh = r.place ~= place
    local prevRun = r.run
    -- the receiving host acknowledged: Cyberpunk is flying the Machine AC was flying -> the bridge may release AC
    if place == "deep" and host == "cyberpunk" and r.host == "assetto_corsa" and r.place == "deep" then   -- KB-361
        log("HANDOFF driver ..%s: Cyberpunk has the Machine (from Assetto Corsa)", tostring(driverId):sub(-6))
        PerformHttpRequest(BRIDGE .. "/host/ready", function() end, "POST", '{"host":"cyberpunk","why":"the client resumed the Machine in Deep"}',
            { ["Content-Type"] = "application/json" })
    end
    r.place, r.host, r.locationId, r.rec, r.run, r.updatedAt = place, host, locationId, rec, runNow() or r.run, t
    if place == "deep" and host then r.hostedAt = t end
    rows[driverId] = r
    if prevRun and r.run and prevRun ~= r.run then
        log("driver ..%s was away for Race Week run %d -> %d (%s)", tostring(driverId):sub(-6), prevRun, r.run, place)
    end
    if transition or fresh or not r.persistedAt or t - r.persistedAt >= 5 then r.persistedAt = t; persist(driverId) end
    if transition or fresh then log("PRESENCE driver ..%s: %s%s%s", tostring(driverId):sub(-6), place, host and (" via " .. host) or "",
        locationId and (" at " .. locationId) or "") end
end

local function driverOf(pid)
    local p = NcmIdentity and NcmIdentity.get and NcmIdentity.get(pid)
    return p and p.ncmDriverId or nil
end
NcmCanonical.driverOf = driverOf

-- the Cyberpunk host's checkpoints (client/deep.lua, 1 Hz in Deep and at every transition)
RegisterNetEvent("ncm:canonical.save", function(m)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(m) ~= "table" or not enabled() then return end
    local d = driverOf(pid)
    if not d then return end
    if type(m.rec) == "table" then m.rec.utc = now(); m.rec.driver = d end   -- the server's clock, never a host's
    NcmCanonical.set(d, tostring(m.place or "deep"), "cyberpunk", m.locationId, type(m.rec) == "table" and m.rec or nil, m.transition == true)
end)

-- ------------------------------------------------------------------------------------------------ boot + unhosted Deep
CreateThread(function()
    Wait(8000)
    -- the world's identity first (ncm_league publishes it): before it, sid() is the fallback and the boot would read
    -- nobody's presence -- a Machine left in Deep would never be found by the loop (KB-379, found by the NCM Host)
    for _ = 1, 120 do
        local okI, id = pcall(function() return GlobalState.ncmIdentity end)
        if okI and type(id) == "table" and id.serverId then break end
        Wait(500)
    end
    if not enabled() or not MySQL then return end
    for _ = 1, 60 do if MySQL.isReady and MySQL.isReady() then break end; Wait(500) end
    local okQ, list = pcall(MySQL.query.await, "SELECT driver_id, place, host, location_id, state_json, race_week_run, updated_at FROM ncm_presence WHERE server_id=?", { sid() })
    log("BOOT %s presence row(s) for server %s%s", okQ and type(list) == "table" and tostring(#list) or "NO", sid(), okQ and "" or (" -- " .. tostring(list)))
    for _, row in ipairs(okQ and list or {}) do
        local okD, rec = true, nil
        if row.state_json then okD, rec = pcall(Json.decode, row.state_json) end
        rows[row.driver_id] = { place = row.place, host = row.host, locationId = row.location_id, rec = okD and rec or nil,
            run = tonumber(row.race_week_run), updatedAt = tonumber(row.updated_at) or 0, hostedAt = 0, persistedAt = tonumber(row.updated_at) or 0 }
        log("BOOT driver ..%s is %s%s (written %.0f s ago)", tostring(row.driver_id):sub(-6), row.place,
            row.location_id and (" at " .. row.location_id) or "", now() - (tonumber(row.updated_at) or now()))
    end
    while true do
        Wait(5000)
        local t = now()
        for d, r in pairs(rows) do
            -- a record from before this run began belongs to the loop reset, not to more flying
            local okW, wk = pcall(function() return NcmWeek and NcmWeek.read and NcmWeek.read() end)
            local runStartUtc = okW and type(wk) == "table" and wk.clock and tonumber(wk.clock.startUtc) or nil
            local stale = runStartUtc and (r.updatedAt or 0) < runStartUtc
            if not stale and r.place == "deep" and r.rec and t - (r.hostedAt or 0) > UNHOSTED_S and (r.rec.utc or t) < t - 1 then
                -- nobody is flying it: the server does (in slices so the instruction quota is never the limit)
                local from = r.rec.utc or t
                local rec, done, info, arrived, landed, border = r.rec, false, nil, false, false, false
                repeat
                    rec, done, info = Canon.propagate(rec, t, SLICE)
                    arrived, landed, border = arrived or info.arrived, landed or info.landed, border or info.border
                    Wait(0)
                until done
                r.rec, r.host = rec, nil
                if from < t - 30 or arrived or landed then
                    log("UNHOSTED driver ..%s flown %.0f s by the server%s%s", tostring(d):sub(-6), t - from,
                        arrived and " | arrived (holding over the venue)" or "", landed and (" | CAME DOWN at %.3f, %.3f"):format(rec.landed.lat, rec.landed.lon) or "")
                end
                if border then
                    -- L334: Earth's sphere of influence reached with nobody flying: the Machine waits there for KSA
                    log("UNHOSTED driver ..%s reached the KSA border: waiting for the KSA host", tostring(d):sub(-6))
                    NcmCanonical.set(d, "border", nil, "ksa_border", rec, true)
                elseif landed then NcmCanonical.set(d, "landed", nil, ("%.3f,%.3f"):format(rec.landed.lat, rec.landed.lon), rec, true)
                else r.updatedAt = t; if t - (r.persistedAt or 0) >= 30 then r.persistedAt = t; persist(d) end end
            end
        end
    end
end)

-- ------------------------------------------------------------------------------------------------ the bridge
-- The bridge relays what non-Cyberpunk hosts say (AC checkpoints, places it measured, the track scan).
local placesSeen = {}
local function upsertPlace(rec)
    if not rec or not rec.id or not MySQL then return end
    local okF, flags = pcall(Json.encode, rec.flags or {})
    local vals, args = sqlValues("place_id, host, track, layout, name, lat, lon, alt, tz, status, provenance, flags_json, updated_at",
        { rec.id, rec.host, rec.track, rec.layout, rec.name, rec.lat, rec.lon, rec.alt, rec.tz, rec.status, rec.provenance, okF and flags or nil, math.floor(now()) }, 13)
    local ok, err = pcall(MySQL.update.await, "INSERT INTO place_registry " .. vals .. [[ ON DUPLICATE KEY UPDATE name=VALUES(name), lat=VALUES(lat),
        lon=VALUES(lon), alt=VALUES(alt), tz=VALUES(tz), status=VALUES(status), provenance=VALUES(provenance), flags_json=VALUES(flags_json),
        updated_at=VALUES(updated_at)]], args)
    if not ok then log("could not store place %s: %s", tostring(rec.id), tostring(err)) end
    placesSeen[rec.id] = rec
end
function NcmCanonical.places() return placesSeen end

local bridgeSeq = 0
CreateThread(function()
    Wait(9000)
    while true do
        Wait(1000)
        if enabled() then
            PerformHttpRequest(BRIDGE .. "/canonical?since=" .. bridgeSeq, function(code, text)
                if tonumber(code) ~= 200 then return end
                local ok, m = pcall(Json.decode, tostring(text or "{}"))
                if not ok or type(m) ~= "table" then return end
                bridgeSeq = tonumber(m.seq) or bridgeSeq
                if type(m.checkpoint) == "table" and m.checkpoint.driverId then
                    local c = m.checkpoint
                    if type(c.rec) == "table" then c.rec.utc = now(); c.rec.driver = c.driverId end
                    NcmCanonical.set(c.driverId, tostring(c.place or "deep"), "assetto_corsa", c.locationId, type(c.rec) == "table" and c.rec or nil, c.transition == true)
                end
                -- a thread of its own: an HTTP callback is not one, and the DB calls and yields need one (KB-358)
                local obsList = type(m.places) == "table" and m.places or {}
                if #obsList > 0 then CreateThread(function()
                    local n = { verified = 0, resolved = 0, unresolved = 0 }
                    for i, obs in ipairs(obsList) do
                        local okR, rec = pcall(Places.resolve, obs)
                        if okR and rec then
                            upsertPlace(rec)
                            n[rec.status] = (n[rec.status] or 0) + 1
                            if #rec.flags > 0 or obs.csp then log("PLACE %s: %s (%s)%s", rec.id, rec.status, rec.provenance, #rec.flags > 0 and (" | " .. table.concat(rec.flags, "; ")) or "") end
                        else log("PLACE observation refused: %s", tostring(rec)) end
                        if i % 10 == 0 then Wait(0) end
                    end
                    log("PLACES %d observation(s): %d verified, %d resolved, %d unresolved", #obsList, n.verified or 0, n.resolved or 0, n.unresolved or 0)
                end) end
            end, "GET", "", {})
        end
    end
end)

-- the universe, for hosts that are not Cyberpunk (every 3 s)
CreateThread(function()
    Wait(10000)
    while true do
        Wait(3000)
        if enabled() then
            local drivers = {}
            for d, r in pairs(rows) do drivers[#drivers + 1] = { driverId = d, place = r.place, host = r.host, locationId = r.locationId, rec = r.rec, updatedAt = r.updatedAt } end
            table.sort(drivers, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
            local places = {}
            for _, p in pairs(placesSeen) do if Places.destination(p) then places[#places + 1] = { id = p.id, name = p.name, lat = p.lat, lon = p.lon, track = p.track, status = p.status } end end
            local okE, body = pcall(Json.encode, { utc = now(), week = week(), drivers = drivers, places = places })
            if okE then PerformHttpRequest(BRIDGE .. "/universe", function() end, "POST", body, { ["Content-Type"] = "application/json" }) end
        end
    end
end)

-- ------------------------------------------------------------------------------------------------ joining Cyberpunk
-- Cyberpunk is the front door, but Night City is not where everyone respawns: a driver who left in Deep is still in
-- Deep, and one who stopped at Laguna Seca is still there. `main.lua` asks before restoring a surface position.
local Deep = NcmCore.get("space.deep")
local Venues = NcmCore.get("space.venues")
local MAPB = { xmin = -6500, xmax = 6500, ymin = -8500, ymax = 5000 }

local function resume(pid, r)
    CreateThread(function()
        Wait(6000)   -- after the arrival cover (client/arrival.lua) has settled the body
        local rec, prompt = r.rec, nil
        if r.place == "host_surface" then
            -- Cyberpunk cannot draw Laguna Seca: the Machine is shown where the host would take it, above the place,
            -- with the same prompt guidance shows on arrival (an expression loss, said so)
            local v = Venues.get(tostring(r.locationId or ""))
            if not v then log("JOIN driver at unknown place %s: surface restore", tostring(r.locationId)); return end
            local Guid = NcmCore.get("space.guidance")
            local alt = (v.alt or 0) + (v.host == "assetto_corsa" and Guid.HOST_ARRIVE_ABOVE_M or Guid.ARRIVE_ABOVE_M)
            local e, n, u = Deep.enu(v.lat, v.lon)
            rec = Canon.fromDeep({ p = Deep.llaToEcef(v.lat, v.lon, alt), v = { 0, 0, 0 }, basis = { right = e, forward = n, up = u } }, now(),
                { asset = r.rec and r.rec.asset, massKg = r.rec and r.rec.massKg })
            prompt = v.id
        end
        if not rec or not rec.asset then log("JOIN player=%d: canonical %s has no Machine on record; surface restore", pid, r.place); return end
        local la, lo = Deep.ecefToLla(rec.p)
        local x, y = Deep.llaToGame(la, lo, 0)
        x, y = math.max(MAPB.xmin, math.min(MAPB.xmax, x)), math.max(MAPB.ymin, math.min(MAPB.ymax, y))
        local vid, why = NcmVehicleAccess and NcmVehicleAccess.materializeAt and NcmVehicleAccess.materializeAt(pid, rec.asset,
            { x = x, y = y, z = 12100, yaw = 0 }, "canonical " .. r.place)
        if not vid then log("JOIN player=%d: could not materialize ..%s (%s)", pid, tostring(rec.asset):sub(-6), tostring(why)); return end
        pcall(Open77.vehicles.setFrozen, vid, true)
        local okW, warped, whyW = pcall(Open77.players.warpIntoVehicle, pid, vid, "driver")
        log("JOIN player=%d resumes %s%s: Hella %s, seated %s %s", pid, r.place, prompt and (" over " .. prompt) or "", tostring(vid),
            tostring(okW and warped), tostring(okW and whyW or warped))
        TriggerClientEvent("ncm:deep.resumeCanonical", pid, { vid = vid, rec = rec, prompt = prompt })
    end)
end

--- Called by the location restore. true = this driver is NOT on Night City's surface; the restore must not run.
local claimed = {}   -- pid -> true once this join has been resumed (both restore paths ask)
AddEventHandler("playerDropped", function() claimed[tonumber(source) or 0] = nil end)
function NcmCanonical.claimJoin(pid, driverId)
    local r = rows[driverId]
    if not enabled() or not r then return false end
    if r.place == "deep" or r.place == "host_surface" or r.place == "border" then   -- L334: waiting at the KSA border resumes there
        if not claimed[pid] then claimed[pid] = true; resume(pid, r) end
        return true
    end
    if r.place == "landed" then
        log("JOIN player=%d: the Machine came down at %s while you were away -- recovered to Night City", pid, tostring(r.locationId))
        pcall(Open77.notifications.send, pid, { type = "warning", title = "NCM", message = "While you were away your Machine came down at "
            .. tostring(r.locationId) .. ". It has been recovered to Night City.", icon = "NCM", durationMs = 12000 })
        NcmCanonical.set(driverId, "surface", "cyberpunk", "night_city", nil, true)
    end
    return false
end

-- ------------------------------------------------------------------------------------------------ the temporal loop
-- L330 (owner, 2026-10-06): the Racing Week is a temporal loop, and it is universe-wide. When the run rolls over, every
-- Machine -- in Night City, in Deep, at an Assetto Corsa circuit, online or not -- is back in Night City: a driver who
-- went to space on day 1 is still there until the reset, then wakes at the default spawn. Nobody is exempt for being
-- away; a record written before this run began is reset the moment it is seen (boot, the periodic check, a join).
local function loopSpawn()
    local x, y, z, h = tostring(GetConvar and GetConvar("ncm_loop_spawn", "") or ""):match("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),?([%-%d%.]*)")
    return { x = tonumber(x) or -1442.2, y = tonumber(y) or 127.4, z = tonumber(z) or 18.0, heading = tonumber(h) or 0 }
end
local function runStart()
    local ok, w = pcall(function() return NcmWeek and NcmWeek.read and NcmWeek.read() end)
    return ok and type(w) == "table" and w.clock and tonumber(w.clock.startUtc) or nil, ok and type(w) == "table" and w.clock and tonumber(w.clock.runIndex) or nil
end
local function pidOf(driverId)
    for _, pid in ipairs(Open77.players.all() or {}) do if driverOf(pid) == driverId then return tonumber(pid) end end
    return nil
end

local function loopReset(d, r, why)
    local was, host = r.place, r.host
    local start, idx = runStart()
    r.place, r.host, r.locationId, r.rec, r.run, r.updatedAt, r.hostedAt = "surface", "cyberpunk", "night_city_loop", nil, idx or r.run, now(), 0
    persist(d)
    log("LOOP driver ..%s (%s): was %s%s -> Night City (Racing Week run %s)", tostring(d):sub(-6), why, tostring(was),
        host and (" via " .. host) or "", tostring(idx))
    if was == "host_surface" or host == "assetto_corsa" then
        PerformHttpRequest(BRIDGE .. "/host/loop", function() end, "POST", '{"why":"the Racing Week reset"}', { ["Content-Type"] = "application/json" })
    end
end

--- Wake a connected player at the loop spawn: out of Deep first, their called car stored (the loop rewinds it too).
local function wake(pid)
    TriggerClientEvent("ncm:deep.loop", pid)
    CreateThread(function()
        Wait(3500)
        if NcmVehicleAccess and NcmVehicleAccess.liveAssets then
            for _, a in ipairs(NcmVehicleAccess.liveAssets()) do
                if tonumber(a.pid) == pid and NcmVehicleAccess.recoveryStore then NcmVehicleAccess.recoveryStore(a.assetId, "Racing Week reset") end
            end
        end
        local p = loopSpawn()
        local ok, done, why = pcall(Open77.players.teleport, pid, { x = p.x, y = p.y, z = p.z }, { fade = true, dismount = true })
        log("LOOP woke player=%d at the loop spawn %.0f, %.0f, %.0f: %s %s", pid, p.x, p.y, p.z, tostring(ok and done), tostring(ok and why or done))
    end)
end

local seenRun = nil
CreateThread(function()
    Wait(12000)
    while true do
        if enabled() then
            local start, idx = runStart()
            if start then
                for d, r in pairs(rows) do
                    if (r.updatedAt or 0) < start and not (r.place == "surface" and r.locationId == "night_city_loop") then
                        loopReset(d, r, "written before this run began")
                    end
                end
            end
            if idx and seenRun and idx ~= seenRun then
                log("LOOP Racing Week run %d -> %d: every Machine back to Night City", seenRun, idx)
                for _, pid in ipairs(Open77.players.all() or {}) do wake(tonumber(pid)) end
                for d, r in pairs(rows) do if r.place ~= "surface" or r.locationId ~= "night_city_loop" then loopReset(d, r, "rollover") end end
            end
            seenRun = idx or seenRun
        end
        Wait(5000)
    end
end)

--- A join after the reset: the record from the previous run is reset before anything resumes it.
local claimJoinInner = NcmCanonical.claimJoin
function NcmCanonical.claimJoin(pid, driverId)
    local r = rows[driverId]
    local start = runStart()
    if r and start and (r.updatedAt or 0) < start and not (r.place == "surface" and r.locationId == "night_city_loop") then
        loopReset(driverId, r, "joined after the reset")
    end
    return claimJoinInner(pid, driverId)
end
