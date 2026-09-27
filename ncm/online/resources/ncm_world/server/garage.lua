-- ncm_world / server / garage — issued vehicles (M2.2; decision record L13/P3 `issued` model, L21 zero cost).
--
-- `/ncm garage`            your current car and the classes on offer
-- `/ncm car <Class>`       be issued a car of that class at the kerb (returns your current one first)
-- `/ncm return`            hand the car back
-- The car is a canonical server vehicle; the issue is logged in issued_vehicle; leaving the server
-- returns it. Core decides *what* is issued (world.provisioning); this file only spawns and records.
NcmGarage = {}

local Core = NcmCore
local Provisioning = Core.get("world.provisioning")
local Pool = Core.get("data.vehicle_pool")
local Teams = Core.get("competition.teams")
local ids = Core.get("vocabulary.ids")

local function log(fmt, ...)
    print(("[ncm_world/garage] " .. fmt):format(...))
end

local hostRng = function() return math.random() end

local active = {}   -- playerId -> { issueId, vehicleId, record, spawnedRecord, class }
NcmGarage.active = active
local lastIssue = {}  -- driverId -> { record, class, teamId } so a reconnect gets the same car back (team cars, M7-lite)
local gridCars = {}   -- sessionId -> { [driverId] = { vehicleId, record, number, teamName, slot, playerId? } }

--- Tell the Collection which vehicle to watch, and whose it is.
--- `sourceDriverId` is what makes a discovery attributable (spec 1 §A): without it the Collection can record
--- that someone found a car but never that another Driver showed it to them, and that fact cannot be
--- reconstructed afterwards. `holding` says how they held it -- recorded, never filtered here (IDEA-138).
local function registerCollection(vehicleId, record, context, sourceDriverId, holding)
    TriggerEvent("ncm:collection:registerVehicle", vehicleId, record, context, sourceDriverId, holding)
end
local function unregisterCollection(vehicleId)
    TriggerEvent("ncm:collection:unregisterVehicle", vehicleId)
end

local function tell(playerId, text)
    pcall(Open77.chat.send, playerId, "[NCM] " .. text)
end

--- Kerb-side spawn point: 5 m ahead of the player, 3 m to their right, facing their heading.
local function kerbPose(playerId)
    local p = Open77.players.get(playerId)
    if not p or not p.position then return nil, "player_position_unknown" end
    local yaw = tonumber(p.heading or p.yaw or 0) or 0
    local rad = math.rad(yaw)
    -- REDengine: yaw 0 faces +Y; +X is the player's right when facing +Y. Forward = (-sin, cos).
    local fx, fy = -math.sin(rad), math.cos(rad)
    local rx, ry = math.cos(rad), math.sin(rad)
    return {
        x = p.position.x + fx * 5.0 + rx * 3.0,
        y = p.position.y + fy * 5.0 + ry * 3.0,
        z = p.position.z + 0.5,
        yaw = yaw,
        bucket = p.bucket or 0,
    }
end

--- Remove the player's current issued car (if any). Returns true when something was returned.
function NcmGarage.returnCar(playerId, reason)
    local id = tonumber(playerId) or 0
    local cur = active[id]
    if not cur then return false end
    active[id] = nil
    unregisterCollection(cur.vehicleId)
    local okRm, err = pcall(Open77.vehicles.remove, cur.vehicleId)
    log("return player=%d issue=%s vehicle=%s remove=%s %s reason=%s", id, cur.issueId, tostring(cur.vehicleId),
        tostring(okRm), tostring(err or ""), tostring(reason))
    if MySQL.isReady() then
        pcall(function()
            MySQL.update.await("UPDATE issued_vehicle SET returned_at = NOW(), return_reason = ? WHERE issue_id = ?",
                { tostring(reason or "returned"), cur.issueId })
        end)
    end
    return true
end

--- Host kit (Batch 2): every issued car and every parked grid car back, no restart. Returns the count.
function NcmGarage.returnAll(reason)
    local n = 0
    for sid, field in pairs(gridCars) do
        for _, entry in pairs(field) do
            if not (entry.playerId and active[entry.playerId] and active[entry.playerId].vehicleId == entry.vehicleId) then
                unregisterCollection(entry.vehicleId); pcall(Open77.vehicles.remove, entry.vehicleId); n = n + 1
            end
        end
        gridCars[sid] = nil
    end
    for pid in pairs(active) do if NcmGarage.returnCar(pid, reason or "world_reset") then n = n + 1 end end
    return n
end

--- Issue a car of `class` to the player. Runs inside a thread. Returns record or nil, reason.
--- `teamId` (Formula only) swaps in the team's RB15 livery record (competition.teams `liveryRecord`).
function NcmGarage.issue(playerId, class, teamId)
    local id = tonumber(playerId) or 0
    local profile = NcmIdentity.get(id)
    if not profile then return nil, "no_ncm_driver" end
    if not Pool.isClass(class) then return nil, "unknown_class" end

    local decision, why = Provisioning.issue({ class = class, rng = hostRng })
    if not decision then return nil, why end
    if teamId and teamId ~= "" then
        if class ~= "Formula" then return nil, "livery_needs_formula" end
        local rec = Teams.liveryRecord(teamId)
        if not rec then return nil, "unknown_team" end
        decision.record = rec
    end

    local pose, perr = kerbPose(id)
    if not pose then return nil, perr end

    -- One issued car per driver: hand the old one back first.
    NcmGarage.returnCar(id, "reissued")

    local vehicleId, spawned, lastReason
    for _, rec in ipairs(Provisioning.spawnCandidates(decision.record)) do
        local vid, reason = Open77.vehicles.create({
            record = rec, position = { x = pose.x, y = pose.y, z = pose.z }, yaw = pose.yaw, bucket = pose.bucket,
        })
        if vid then vehicleId, spawned = vid, rec; break end
        lastReason = reason
        log("create %s refused: %s", rec, tostring(reason))
    end
    if not vehicleId then return nil, "spawn_failed:" .. tostring(lastReason) end

    active[id] = { issueId = decision.issueId, vehicleId = vehicleId, record = decision.record, spawnedRecord = spawned, class = class }
    registerCollection(vehicleId, spawned, "issued", profile and profile.ncmDriverId or nil, "issued")
    lastIssue[profile.ncmDriverId] = { record = decision.record, class = class, teamId = teamId }
    if MySQL.isReady() then
        pcall(function()
            MySQL.insert.await(
                "INSERT INTO issued_vehicle (issue_id, ncm_driver_id, server_id, model, class, record, spawned_record, vehicle_id, cost) " ..
                "VALUES (?, ?, ?, 'issued', ?, ?, ?, ?, ?)",
                { decision.issueId, profile.ncmDriverId, profile.serverId, class, decision.record, spawned, vehicleId, decision.cost })
        end)
    end
    log("issued player=%d driver=%s class=%s record=%s (spawned %s) vehicle=%s at %.1f,%.1f,%.1f yaw=%.0f",
        id, profile.ncmDriverId, class, decision.record, spawned, tostring(vehicleId), pose.x, pose.y, pose.z, pose.yaw)

    return active[id]
end

--- Spawn one team car at a grid slot (record exact, position from session.grid). Owned by the player when
--- connected; otherwise parked under the driver id and claimed on arrival. Runs inside a thread.
local function spawnGridCar(sessionId, car)
    local pid = tonumber(car.playerId) or 0
    local bucket = 0
    if pid > 0 then
        local p = Open77.players.get(pid)
        bucket = (p and p.bucket) or 0
        NcmGarage.returnCar(pid, "grid_car")
    end
    -- Ground z (KB-17): the platform has no snap; a hand-typed node z can sit above the road and the car hangs
    -- there. A player standing within 80 m of the slot is on the ground — use their z. Authored routes (/ncm.ar)
    -- carry a true z already, so this only corrects the legacy node table.
    local z = (car.z or 0)
    local best
    for _, other in ipairs(Open77.players.all()) do
        local op = Open77.players.get(other)
        if op and op.position then
            local d = math.sqrt((op.position.x - car.x) ^ 2 + (op.position.y - car.y) ^ 2)
            if d <= 80 and (not best or d < best) then best = d; z = op.position.z end
        end
    end
    if best then log("grid car #%d z from a player %.0f m away: %.1f (node %.1f)", car.number, best, z, car.z or 0) end
    local vid, reason = Open77.vehicles.create({
        record = car.record, position = { x = car.x, y = car.y, z = z + 0.5 }, yaw = car.heading or 0, bucket = bucket,
    })
    if not vid then
        log("grid car #%d %s slot %d: create refused: %s", car.number, car.record, car.slot, tostring(reason))
        return nil
    end
    local entry = { vehicleId = vid, record = car.record, number = car.number, teamName = car.teamName, teamId = car.teamId, slot = car.slot, playerId = pid > 0 and pid or nil }
    gridCars[sessionId][car.driverId] = entry
    registerCollection(vid, car.record, "grid", car.driverId, "team")
    if pid > 0 then
        local profile = NcmIdentity.get(pid)
        local issueId = ids.uuid4(hostRng)
        active[pid] = { issueId = issueId, vehicleId = vid, record = car.record, spawnedRecord = car.record, class = "Formula", sessionId = sessionId }
        lastIssue[car.driverId] = { record = car.record, class = "Formula", teamId = car.teamId }
        if profile and MySQL.isReady() then
            pcall(function()
                MySQL.insert.await(
                    "INSERT INTO issued_vehicle (issue_id, ncm_driver_id, server_id, model, class, record, spawned_record, vehicle_id, cost) " ..
                    "VALUES (?, ?, ?, 'issued', 'Formula', ?, ?, ?, 0)",
                    { issueId, profile.ncmDriverId, profile.serverId, car.record, car.record, vid })
            end)
        end
    end
    log("grid car #%d %s (%s) slot %d vehicle=%s player=%s", car.number, car.teamName, car.record, car.slot, tostring(vid), pid > 0 and tostring(pid) or "absent")
    return entry
end

--- ncm_league formed an organized session: put the field on the grid (M7-lite).
AddEventHandler("ncm:gridCars", function(sessionId, cars)
    if type(cars) ~= "table" then return end
    gridCars[sessionId] = gridCars[sessionId] or {}
    CreateThread(function()
        local n = 0
        for _, car in ipairs(cars) do
            if spawnGridCar(sessionId, car) then n = n + 1 end
            Wait(150)
        end
        log("grid cars session=%s spawned %d/%d", sessionId, n, #cars)
    end)
end)

--- The session is over: remove every car of the field that is still ours.
AddEventHandler("ncm:gridCarsRelease", function(sessionId, reason)
    local field = gridCars[sessionId]
    if not field then return end
    gridCars[sessionId] = nil
    for _, entry in pairs(field) do
        if entry.playerId and active[entry.playerId] and active[entry.playerId].vehicleId == entry.vehicleId then
            NcmGarage.returnCar(entry.playerId, reason or "session_over")
        else
            unregisterCollection(entry.vehicleId); pcall(Open77.vehicles.remove, entry.vehicleId)
        end
    end
    log("grid cars session=%s released (%s)", sessionId, tostring(reason))
end)

--- A driver arrives (or comes back) while their grid car is parked: hand it over.
function NcmGarage.claimGridCar(playerId)
    local pid = tonumber(playerId) or 0
    local profile = NcmIdentity.get(pid)
    if not profile then return false end
    for sessionId, field in pairs(gridCars) do
        local entry = field[profile.ncmDriverId]
        if entry and not entry.playerId then
            NcmGarage.returnCar(pid, "grid_car")
            entry.playerId = pid
            active[pid] = { issueId = ids.uuid4(hostRng), vehicleId = entry.vehicleId, record = entry.record, spawnedRecord = entry.record, class = "Formula", sessionId = sessionId }
            lastIssue[profile.ncmDriverId] = { record = entry.record, class = "Formula", teamId = entry.teamId }
            tell(pid, ("Your car is waiting: #%d %s RB15 at grid slot %d."):format(entry.number, entry.teamName, entry.slot))
            log("grid car claimed player=%d #%d vehicle=%s", pid, entry.number, tostring(entry.vehicleId))
            return true
        end
    end
    return false
end

--- YOUR CAR (grid reveal, Batch 1 item 3): the player is at their slot and asks to get in.
RegisterNetEvent("ncm:yourCar", function(sessionId)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local profile = NcmIdentity.get(pid)
    if not profile then return end
    local entry, anySession
    for sid, field in pairs(gridCars) do
        if field[profile.ncmDriverId] then
            anySession = field[profile.ncmDriverId]
            if not sessionId or sid == sessionId then entry = field[profile.ncmDriverId] end
        end
    end
    -- Cars are issued once per plan (at its first session); a quali/race that follows carries a new session id.
    entry = entry or anySession
    if not entry then
        local cur = active[pid]
        if cur and cur.class == "Formula" then entry = { vehicleId = cur.vehicleId, number = 0, teamName = "your", slot = 0 } end
    end
    if not entry then tell(pid, "No grid car is yours right now."); return end
    if not entry.playerId then NcmGarage.claimGridCar(pid) end
    local ok, res, reason = pcall(Open77.players.warpIntoVehicle, pid, entry.vehicleId, "driver")
    if not ok or not res then
        local ok2, res2, reason2 = pcall(Open77.players.taskEnterVehicle, pid, entry.vehicleId, "driver")
        ok, res, reason = ok2, res2, reason2 or reason
    end
    log("yourCar player=%d vehicle=%s -> %s %s", pid, tostring(entry.vehicleId), tostring(ok and res), tostring(reason or ""))
    if ok and res then
        tell(pid, ("You're in #%s. Hold on the grid for the lights."):format(tostring(entry.number or "?")))
    else
        tell(pid, ("Your car is #%s at slot %d — get in."):format(tostring(entry.number or "?"), entry.slot or 0))
    end
end)

--- Re-issue what the driver last had (reconnect): their team car if it is still on the grid, else the same record.
function NcmGarage.reissueLast(playerId)
    local pid = tonumber(playerId) or 0
    if NcmGarage.claimGridCar(pid) then return true end
    local profile = NcmIdentity.get(pid)
    local last = profile and lastIssue[profile.ncmDriverId]
    if last and last.class == "Formula" then
        local ok = NcmGarage.issue(pid, "Formula", last.teamId)
        if ok then return true end
    end
    -- system resume, not a request: restoring what this racer already had (L102)
    return NcmGarage.command(pid, { "car", (last and last.class) or "Sport" }, true)
end

function NcmGarage.describe(playerId)
    local cur = active[tonumber(playerId) or 0]
    if not cur then return "no car issued" end
    return ("car: %s (%s, vehicle %s)"):format(cur.spawnedRecord, cur.class, tostring(cur.vehicleId))
end

--- Command surface used by main.lua's `/ncm` dispatcher.
--- L102. `authorized` is the whole gate, and it lives HERE rather than at the call sites because there are two
--- player-reachable routes into this function and only one of them is obvious: the `/ncm` chat dispatcher, and
--- the `ncm:cmd` NET EVENT, which any client can trigger. Blocking the chat command alone would have left the
--- net event as an open bypass — and a bypass into car spawning is exactly what must not exist.
---
--- Why no player may spawn a car at all (owner, 2026-09-23): a car spawned into a wall makes bad physics; a
--- command that can be repeated is an abuse surface; and, decisively, **a free loaner is a permanent
--- substitute for a purchase** -- the Market would open with no reason for anyone to use it.
---
--- Two callers ARE authorized and neither is a player asking for a free car: the operator console
--- (`ncm.car`, gated `source == 0`), and `reissueLast`, which restores the car of a racer who dropped
--- mid-race and reconnected. The second is fired by `race.lua` through a server-side `AddEventHandler`, so no
--- client can reach it. Refusing it would break mid-race reconnection, which is a different thing entirely
--- from handing out a car.
function NcmGarage.command(playerId, args, authorized)
    local id = tonumber(playerId) or 0
    local sub = tostring(args[1] or ""):lower()
    if sub == "garage" then
        tell(id, "Garage: " .. NcmGarage.describe(id))
        tell(id, "Vehicles are earned or bought in Market. F6 opens it; Machine Index calls a specific owned Machine. /ncm return hands back a loaner.")
        return true
    elseif sub == "car" and not authorized then
        tell(id, "Cars are not issued on request. Buy a Machine in Market, then call the owned asset from Machine Index (F10).")
        log("refused player-invoked car spawn from player=%d (L102)", id)
        return true
    elseif sub == "car" then
        local wanted = tostring(args[2] or "")
        local class
        for _, c in ipairs(Pool.classes()) do if c:lower() == wanted:lower() then class = c end end
        if not class then
            tell(id, "Unknown class. Classes: " .. table.concat(Pool.classes(), ", "))
            return true
        end
        CreateThread(function()
            local rec, why = NcmGarage.issue(id, class, args[3] and tostring(args[3]):lower() or nil)
            if rec then
                tell(id, ("Issued: %s — at the kerb, zero cost. /ncm return when done."):format(rec.spawnedRecord))
                pcall(Open77.notifications.send, id, {
                    type = "success", title = "Car issued", message = rec.spawnedRecord .. " (" .. class .. ")", icon = "NCM", durationMs = 6000,
                })
            else
                tell(id, "Could not issue a car: " .. tostring(why))
            end
        end)
        return true
    elseif sub == "return" then
        CreateThread(function()
            local returned = NcmGarage.returnCar(id, "returned")
            tell(id, returned and "Car returned." or "You have no issued car.")
        end)
        return true
    end
    return false
end

AddEventHandler("onPlayerDisconnected", function(playerId)
    NcmGarage.returnCar(playerId, "disconnected")
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_world" then return end
    for pid, _ in pairs(active) do NcmGarage.returnCar(pid, "resource_stopped") end
    for _, field in pairs(gridCars) do
        for _, entry in pairs(field) do unregisterCollection(entry.vehicleId); pcall(Open77.vehicles.remove, entry.vehicleId) end
    end
    gridCars = {}
end)
