-- ncm_world / server / deep_drives -- doc 58: what the experimental propulsion stable DID, recorded.
--
-- Every drive activation (impulse, fusion, warp, alcubierre, jump, wormhole) is one row in `deep_drive_activation`:
-- who, which Machine, when, from where to where (astronomical coordinates: cell + offset), path vs endpoint distance,
-- velocities, charge and fuel spent, frames, success and the termination reason, plus each drive's own detail (warp
-- factors, bubble parameters, the jump vector, the wormhole and both its mouths). Events arrive from the host flying
-- the Machine (the Cyberpunk client, `ncm:deep.drive`) or from the server's own unhosted flight (server/canonical.lua).
-- A continuous drive streams a line a second while engaged: those go to the log (`DRIVE <drive> STREAM`) and the row's
-- last stream.
--
-- DEVELOPER SAFETY (doc 58 §7): at the start of every exotic activation the server stores the Machine's presence record
-- and part states (`deep_dev_checkpoint`). The flying host restores its own state automatically when a drive produces an
-- invalid one; `ncm.deep.labrestore <activation id>` (server console only, Machine unhosted) puts the stored record back
-- by hand. Nothing here restores because a result is surprising.
--
-- Charge: the drives' stores live in component_state (like a tank part's propellant). The host reports what is left;
-- the server only ever LOWERS it (a host cannot add charge).
local function log(fmt, ...) print(("[ncm_world/deep_drives] " .. fmt):format(...)) end
local Json = NcmCore.get("vocabulary.json")
local A = NcmCore.get("space.astro")
local Cat = NcmCore.get("space.catalogue")
local Install = NcmCore.get("engineering.installation")
local V = A.vec

NcmDeepDrives = {}

local function now() return Open77.time.unix() end
local function sid()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    return ok and type(id) == "table" and id.serverId or "ncm-devbox"
end
local function enc(v) local ok, x = pcall(Json.encode, v); return ok and x or nil end
local function short(id) return tostring(id or "-"):sub(-6) end
local function num(x) x = tonumber(x); return (x and x == x and x ~= math.huge and x ~= -math.huge) and x or nil end

-- where a position is, in words: distance from the Sun and the Earth, and the system it is in
local function where(pt, utc)
    if type(pt) ~= "table" or type(pt.c) ~= "table" then return "?" end
    local ok, s = pcall(function()
        local p = A.fromParts(pt.c, pt.o)
        local dSun = A.distance(p, A.ORIGIN)
        local dEarth = A.distance(p, (Cat.stateAt("earth", utc)))
        local sys = Cat.system(p, utc)
        local function fmt(m)
            if m < 1e9 then return ("%.0f km"):format(m / 1000) end
            if m < 0.05 * A.LY then return ("%.4f AU"):format(m / A.AU) end
            return ("%.4f ly"):format(m / A.LY)
        end
        return ("earth %s, sun %s, system %s"):format(fmt(dEarth), fmt(dSun), sys and (sys.name or sys.id) or "?")
    end)
    return ok and s or "?"
end
local function dist(m)
    m = num(m)
    if not m then return "?" end
    if m < 1e9 then return ("%.3f km"):format(m / 1000) end
    if m < 0.05 * A.LY then return ("%.6f AU"):format(m / A.AU) end
    return ("%.6f ly"):format(m / A.LY)
end

local realStart = {}   -- activation id -> host real ms at start

local function db(fn, ...)
    if not MySQL then return nil end
    local ok, r = pcall(fn, ...)
    if not ok then log("database: %s", tostring(r)) return nil end
    return r
end

local function partStates(assetId)
    local rows = db(MySQL.query.await, [[SELECT a.asset_id, a.design_id, s.propellant_kg FROM component_asset a LEFT JOIN component_state s ON s.asset_id=a.asset_id
        WHERE a.machine_asset_id=? AND a.location_kind='installed' AND a.lifecycle='active']], { assetId }) or {}
    return rows
end

local function onStart(d, asset, pid, host, ev)
    local a = ev.act or {}
    if ev.realMs then realStart[a.id or "?"] = ev.realMs end
    log("DRIVE %s START act=%s vehicle=..%s driver=..%s player=%s host=%s | from %s | v %.3f km/s | frame %s | target %s | charge %s",
        tostring(a.drive), tostring(a.id), short(asset), short(d), tostring(pid or "-"), host, where(a.startPos, a.startUtc or now()),
        (num(a.startVel and V.len(a.startVel)) or 0) / 1000, tostring(a.frameStart), tostring(a.target or "-"), tostring(a.chargeStart or "-"))
    db(MySQL.insert.await, [[INSERT IGNORE INTO deep_drive_activation (activation_id, server_id, driver_id, asset_id, player_id, host, drive, code,
        started_utc, start_pos_json, start_vel_json, start_earth_m, frame_start, target, charge_start, detail_json, stream_count, updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?)]],
        { a.id, sid(), d, asset, pid or 0, host, a.drive, a.code, num(a.startUtc) or now(), enc(a.startPos), enc(a.startVel), num(a.startEarthM) or 0,
          tostring(a.frameStart or ""), tostring(a.target or ""), num(a.chargeStart) or 0, enc(a.detail or {}), math.floor(now()) })
    -- the developer checkpoint: the exotic drives only (an impulse stroke or a fusion burn is ordinary flight)
    if ev.checkpoint and a.componentId ~= "conventional" then
        local r = NcmCanonical and NcmCanonical.get and NcmCanonical.get(d) or nil
        db(MySQL.insert.await, [[INSERT IGNORE INTO deep_dev_checkpoint (activation_id, server_id, driver_id, asset_id, created_at, presence_json, dynamics_json, components_json)
            VALUES (?,?,?,?,?,?,?,?)]], { a.id, sid(), d, asset, math.floor(now()), r and r.rec and enc(r.rec) or nil, enc(ev.checkpoint), enc(partStates(asset)) })
        log("DRIVE %s CHECKPOINT act=%s stored (presence record + part states) -- developer-only restore: ncm.deep.labrestore %s", tostring(a.drive), tostring(a.id), tostring(a.id))
    end
end

local function onEnd(d, asset, pid, host, ev)
    local a = ev.act or {}
    local realS = (ev.realMs and realStart[a.id or "?"]) and (ev.realMs - realStart[a.id]) / 1000 or nil
    realStart[a.id or "?"] = nil
    log("DRIVE %s END act=%s vehicle=..%s %s reason=%s | to %s | path %s | endpoint %s | sim %.1f s real %s | v %.3f -> %.3f km/s | charge used %s left %s | fuel %s kg fusion %s kg | frame %s -> %s | soi %s",
        tostring(a.drive), tostring(a.id), short(asset), a.ok and "SUCCESS" or "FAILED", tostring(a.reason), where(a.endPos, a.endUtc or now()),
        dist(a.pathM), dist(a.endpointM), num(a.simS) or 0, realS and ("%.1f s"):format(realS) or "-",
        (num(a.startVel and V.len(a.startVel)) or 0) / 1000, (num(a.endVel and V.len(a.endVel)) or 0) / 1000,
        tostring(a.chargeUsed and ("%.0f"):format(a.chargeUsed) or "-"), tostring(a.chargeLeft and ("%.0f"):format(a.chargeLeft) or "-"),
        tostring(a.fuelUsedKg and ("%.3f"):format(a.fuelUsedKg) or "-"), tostring(a.fusionUsedKg and ("%.4f"):format(a.fusionUsedKg) or "-"),
        tostring(a.frameStart), tostring(a.frameEnd), tostring(a.soiEnd))
    local detail = enc(a.detail or {})
    if detail and #detail < 60000 then
        log("DRIVE %s DETAIL act=%s %s", tostring(a.drive), tostring(a.id), detail)
    end
    local args = { num(a.endUtc) or now(), enc(a.endPos), enc(a.endVel), num(a.endEarthM) or 0, num(a.pathM) or 0, num(a.endpointM) or 0, num(a.simS) or 0,
        realS, num(a.chargeUsed) or 0, num(a.fuelUsedKg), num(a.fusionUsedKg), tostring(a.frameEnd or ""), tostring(a.soiEnd or ""), a.ok and 1 or 0,
        tostring(a.reason or ""), detail, math.floor(now()), a.id }
    local n = db(MySQL.update.await, [[UPDATE deep_drive_activation SET ended_utc=?, end_pos_json=?, end_vel_json=?, end_earth_m=?, path_m=?, endpoint_m=?, sim_s=?,
        real_s=?, charge_used=?, fuel_used_kg=?, fusion_used_kg=?, frame_end=?, soi_end=?, ok=?, reason=?, detail_json=?, updated_at=? WHERE activation_id=?]], args)
    if (tonumber(n) or 0) == 0 then
        onStart(d, asset, pid, host, { act = a })
        db(MySQL.update.await, [[UPDATE deep_drive_activation SET ended_utc=?, end_pos_json=?, end_vel_json=?, end_earth_m=?, path_m=?, endpoint_m=?, sim_s=?,
            real_s=?, charge_used=?, fuel_used_kg=?, fusion_used_kg=?, frame_end=?, soi_end=?, ok=?, reason=?, detail_json=?, updated_at=? WHERE activation_id=?]], args)
    end
    -- the wormhole: its record (both mouths, identity) persists apart from the activation that made it
    local w = type(a.detail) == "table" and a.detail.wormhole or nil
    if w and w.id then
        db(MySQL.query.await, [[INSERT INTO deep_wormhole (wormhole_id, server_id, owner_asset_id, origin, state, opened_utc, lifetime_s, record_json, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE state=VALUES(state), record_json=VALUES(record_json), updated_at=VALUES(updated_at)]],
            { w.id, sid(), asset, tostring(w.origin or "artificial"), a.ok and "traversed" or tostring(a.reason or "closed"), num(a.startUtc) or now(),
              num(w.lifetimeS), enc(w), math.floor(now()) })
    end
end

--- Record a batch of drive events for driver `d`'s Machine `asset` (pid: the player, nil for the server's own flight).
function NcmDeepDrives.record(d, asset, pid, host, events)
    for _, ev in ipairs(events or {}) do
        local okE, err = pcall(function()
            if ev.type == "start" then onStart(d, asset, pid, host, ev)
            elseif ev.type == "end" then onEnd(d, asset, pid, host, ev)
            elseif ev.type == "stream" then
                log("DRIVE %s STREAM act=%s t=%.0f %s | %s | path %s | charge %s%s", tostring(ev.drive), tostring(ev.id), num(ev.utc) or 0, tostring(ev.state),
                    where(ev.pos, ev.utc or now()), dist(ev.pathM), tostring(ev.charge and ("%.0f"):format(ev.charge) or "-"),
                    (ev.W and (" | W%d %.4g c"):format(ev.W, num(ev.vC) or 0) or "") .. (ev.stability and (" | bubble stability %.3f, %.4g c, x %s of %s"):format(ev.stability, num(ev.vC) or 0, dist(ev.x), dist(ev.D)) or "")
                    .. (ev.throttle and (" | throttle %.2f"):format(ev.throttle) or ""))
                db(MySQL.update.await, "UPDATE deep_drive_activation SET stream_count=stream_count+1, last_stream_json=?, updated_at=? WHERE activation_id=?",
                    { enc(ev), math.floor(now()), ev.id })
            elseif ev.type == "state" then
                log("DRIVE %s STATE vehicle=..%s %s -> %s (%s)%s", tostring(ev.drive), short(asset), tostring(ev.from), tostring(ev.to), tostring(ev.why),
                    ev.act and (" act=" .. tostring(ev.act)) or "")
            elseif ev.type == "transit" then
                log("DRIVE %s TRANSIT vehicle=..%s wormhole %s mouth %s -> %s | endpoint separation %s", tostring(ev.drive), short(asset), tostring(ev.id),
                    tostring(ev.from), tostring(ev.to), dist(ev.separationM))
            elseif ev.type == "restored" then
                log("DRIVE %s CHECKPOINT RESTORED vehicle=..%s act=%s: the drive produced an invalid state (%s); the host put the Machine back where it was before the activation",
                    tostring(ev.drive), short(asset), tostring(ev.act), tostring(ev.why))
                db(MySQL.update.await, "UPDATE deep_dev_checkpoint SET restored_at=?, restored_by=? WHERE activation_id=?", { math.floor(now()), host .. ": " .. tostring(ev.why), ev.act })
            elseif ev.type == "diag" then
                log("DRIVE %s DIAG vehicle=..%s %s", tostring(ev.drive), short(asset), tostring(ev.text))
            elseif ev.type == "error" then
                log("DRIVE %s ERROR vehicle=..%s: %s", tostring(ev.drive or "?"), short(asset), tostring(ev.error))
            end
        end)
        if not okE then log("event %s not recorded: %s", tostring(ev.type), tostring(err)) end
    end
end

--- The Machine's travel ledger (space.travel), as of now.
local travelAt = {}
function NcmDeepDrives.travel(d, asset, L)
    if type(L) ~= "table" or not asset then return end
    local t = now()
    if travelAt[asset] and t - travelAt[asset] < 30 then return end
    travelAt[asset] = t
    db(MySQL.query.await, [[INSERT INTO deep_travel (asset_id, server_id, driver_id, path_m, discontinuous_m, max_earth_m, current_earth_m, ledger_json, updated_at)
        VALUES (?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE path_m=VALUES(path_m), discontinuous_m=VALUES(discontinuous_m), max_earth_m=VALUES(max_earth_m),
        current_earth_m=VALUES(current_earth_m), ledger_json=VALUES(ledger_json), updated_at=VALUES(updated_at)]],
        { asset, sid(), d, num(L.pathM) or 0, num(L.jumpM) or 0, num(L.maxEarthM) or 0, num(L.earthM) or 0, enc(L), math.floor(t) })
end

-- ------------------------------------------------------------------------------------------------ from the host
local function deepAsset(pid)
    local d = NcmCanonical and NcmCanonical.driverOf and NcmCanonical.driverOf(pid) or nil
    local r = d and NcmCanonical.get(d) or nil
    return d, r and r.rec and r.rec.asset or nil
end

RegisterNetEvent("ncm:deep.drive", function(m)
    local pid = tonumber(source) or 0
    if type(m) == "table" and type(m.json) == "string" then
        local okJ, dm = pcall(Json.decode, m.json)
        m = okJ and dm or nil
        if not okJ then log("drive events from player=%d unreadable: %s", pid, tostring(dm)) end
    end
    if pid <= 0 or type(m) ~= "table" or type(m.events) ~= "table" then return end
    local d, asset = deepAsset(pid)
    if not d or not asset then return end
    local evs = {}
    for i = 1, math.min(#m.events, 60) do
        local e = m.events[i]
        if type(e) == "table" then e.realMs = tonumber(m.realMs); evs[#evs + 1] = e end
    end
    CreateThread(function()
        NcmDeepDrives.record(d, asset, pid, "cyberpunk", evs)
        if type(m.travel) == "table" then NcmDeepDrives.travel(d, asset, m.travel) end
    end)
end)

RegisterNetEvent("ncm:deep.drive.charge", function(m)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(m) ~= "table" then return end
    local d, asset = deepAsset(pid)
    if not d or not asset then return end
    CreateThread(function()
        for cid, left in pairs(type(m.left) == "table" and m.left or {}) do
            left = num(left)
            if left and left >= 0 then
                local row = db(MySQL.single.await, [[SELECT a.design_id, s.propellant_kg FROM component_asset a LEFT JOIN component_state s ON s.asset_id=a.asset_id
                    WHERE a.asset_id=? AND a.machine_asset_id=? AND a.location_kind='installed']], { cid, asset })
                local design = row and Install.design(row.design_id) or nil
                if design and design.perf and design.perf.store then
                    local have = num(row.propellant_kg) or tonumber(design.perf.store.capacity) or 0
                    if left < have then
                        db(MySQL.query.await, [[INSERT INTO component_state (asset_id, propellant_kg, updated_at) VALUES (?,?,?)
                            ON DUPLICATE KEY UPDATE propellant_kg=LEAST(propellant_kg, VALUES(propellant_kg)), updated_at=VALUES(updated_at)]], { cid, left, math.floor(now()) })
                    end
                end
            end
        end
    end)
end)

-- ------------------------------------------------------------------------------------------------ native screen effects
-- The game's own post-process for a drive moment (players.screenfx): an Alcubierre bubble forming (a distortion), its
-- collapse (a flash), a jump charging. Aliases come from the server's catalogue (logged once); none found = nothing.
local FX_PREFER = {
    distort = { "drugged.light", "drugged", "drunk", "braindance", "bd", "glitch" },
    flash = { "blinded", "flashbang", "flash", "blackout" },
    charge = { "netrunner", "quickhack", "hacked", "braindance", "glitch" },
}
local fxCatalog, fxLast = nil, {}
local function fxAlias(kind)
    if not fxCatalog then
        local ok, list = pcall(Open77.effects.screenCatalog)
        fxCatalog = {}
        local names = {}
        for _, a in ipairs(ok and type(list) == "table" and list or {}) do fxCatalog[tostring(a)] = true; names[#names + 1] = tostring(a) end
        log("screen effect catalogue: %s", #names > 0 and table.concat(names, ", ") or ("none (" .. tostring(ok and "empty" or list) .. ")"))
    end
    for _, a in ipairs(FX_PREFER[kind] or {}) do if fxCatalog[a] then return a end end
    return nil
end
RegisterNetEvent("ncm:deep.drive.fx", function(m)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(m) ~= "table" then return end
    local t = now()
    if fxLast[pid] and t - fxLast[pid] < 1 then return end
    fxLast[pid] = t
    local alias = fxAlias(tostring(m.kind))
    if not alias then return end
    local dur = math.max(0.5, math.min(20, tonumber(m.duration) or 2))
    pcall(Open77.effects.screen, pid, alias, { strength = m.kind == "flash" and 1 or 0.6, duration = dur })
    CreateThread(function() Wait(math.floor(dur * 1000)); pcall(Open77.effects.screen, pid, false, {}) end)
end)
AddEventHandler("playerDropped", function() fxLast[tonumber(source) or 0] = nil end)

-- ------------------------------------------------------------------------------------------------ developer restore
-- Server console only. The Machine must be unhosted (its owner not connected): a flying host owns its state.
RegisterCommand("ncm.deep.labrestore", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local id = tostring(args and args[1] or "")
    CreateThread(function()
        local row = db(MySQL.single.await, "SELECT driver_id, asset_id, presence_json FROM deep_dev_checkpoint WHERE activation_id=?", { id })
        if not row or not row.presence_json then log("LABRESTORE %s: no checkpoint with a presence record", id); return end
        for _, pid in ipairs(Open77.players.all() or {}) do
            if NcmCanonical.driverOf(tonumber(pid)) == row.driver_id then log("LABRESTORE %s refused: driver ..%s is connected (their host owns the Machine)", id, short(row.driver_id)); return end
        end
        local ok, rec = pcall(Json.decode, row.presence_json)
        if not ok or type(rec) ~= "table" then log("LABRESTORE %s: checkpoint record unreadable", id); return end
        rec.utc = now()   -- the record resumes from now (the time in between is not re-flown)
        NcmCanonical.set(row.driver_id, "deep", nil, nil, rec, true)
        db(MySQL.update.await, "UPDATE deep_dev_checkpoint SET restored_at=?, restored_by='console' WHERE activation_id=?", { math.floor(now()), id })
        log("LABRESTORE %s: driver ..%s Machine ..%s put back at its pre-activation state (developer restore)", id, short(row.driver_id), short(row.asset_id))
    end)
end, true)
