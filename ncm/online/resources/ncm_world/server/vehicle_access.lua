-- Runtime access only. The league owns persistent title; this adapter never writes economy/asset tables.
-- Client physics probes are placement evidence, not ownership authority (L106).
NcmVehicleAccess = {}
local pending, locks, active, cooldown, tradeReserved = {}, {}, {}, {}, {}
-- Runtime vehicle ids are ephemeral, but while an owned Machine is materialised this reverse index is the
-- authoritative bridge from OPEN//77's live vehicle to NCM's permanent asset identity. Parts must never
-- infer that identity from a record: two physical Machines (and, with Foundry, two Designs) can share one.
local assetByVehicle = {}
local seq = 0
-- This first clearance envelope is only for the Base Market's small starter cars.
-- Larger models need their own validated envelope, not a guess based on category.
-- 2026-10-12 (owner: "only 3 vehicles whitelisted??? how do i call other 40+ vehicles from index"): every model NCM's
-- catalogue knows can be called (data.vehicle_catalogue resolves the stored record, gearbox clones and liveries included).
-- The three founding models stood here alone since the first call slice; the markets have sold forty more since.
local Catalogue = NcmCore.get("data.vehicle_catalogue")
local supported = setmetatable({}, { __index = function(_, record)
    return type(record) == "string" and Catalogue.resolveRecord(record) ~= nil
end })
local function clock() return Open77.time.unix() end
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < 1000000 end
local function position(p) return type(p) == "table" and finite(p.x) and finite(p.y) and finite(p.z) end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
-- Every outcome goes to the PAGE as well as the toast.
--
-- Owner QA, 2026-09-23: the button *"doesn't go green or red or anything to indicate success, barely
-- registers as a click."* It was working -- it just never said so. All feedback was an OPEN//77 notification,
-- and the panel the player is looking at is exactly what a toast is behind. A button that does not
-- acknowledge its own press reads as broken even when the call succeeds.
--
-- `state` is "pending" | "ok" | "fail": pressing is not succeeding, so the checking message must not turn the
-- button green.
local function feedback(pid, message, ok, state, title)
    state = state or (ok and "ok" or "fail")
    pcall(Open77.notifications.send, pid, { type=ok and "success" or "error", title=title or "CALL VEHICLE",
        message=message, icon="NCM", durationMs=7000 })
    pcall(TriggerClientEvent, "ncm:vehicle.result", pid, { state=state, message=message })
end

-- Same channel, different verb: the button the player pressed said STORE, so the toast must not say CALL.
local function storeFeedback(pid, message, ok, state)
    return feedback(pid, message, ok, state, "STORE VEHICLE")
end

--- Which of this player's Machines are standing in the world right now.
---
--- The Machine Index lives in `ncm_league`, which cannot see this registry, and a called car cannot be called
--- again -- so without this the panel offers CALL for a car already parked two districts away and the player
--- has no way to get it back other than disconnecting. This is the one fact the page needs to show STORE
--- instead, and it is pushed rather than polled: materialise, store and reclaim are the only three moments it
--- changes.
local function sendActive(pid)
    pid = tonumber(pid) or 0
    if pid <= 0 then return end
    local ids = {}
    for assetId, cur in pairs(active) do
        if cur.pid == pid then ids[#ids + 1] = assetId end
    end
    pcall(TriggerClientEvent, "ncm:vehicle.active", pid, { assets = ids })
end

-- Why the probe found nowhere. Being told "the ground is uneven" is actionable; "try somewhere else" is not.
local REASON = {
    moving      = "Stand still on foot and try again.",
    walked_away = "You moved while it was checking. Stand still and try again.",
    in_vehicle  = "Get out of your vehicle first.",
    not_alive   = "You cannot call a vehicle right now.",
    airborne    = "Stand on solid ground and try again.",
    no_position = "Your position is not available yet. Try again in a moment.",
    no_state    = "Your character state is not available yet. Try again in a moment.",
    error       = "Placement check failed. Try again.",
    no_ground   = "There is no solid ground to place it on. Move onto a road or parking area.",
    sloped      = "The ground around you is too steep. Try flatter ground nearby.",
    uneven      = "The ground around you is too uneven -- a kerb or step is in the way. Try a flatter spot.",
    obstructed  = "No clear space around you. Move somewhere more open and try again.",
    not_visible = "No clear space in sight. Move somewhere more open and try again.",
    timeout     = "Could not find space in time. Try again.",
}
--- Placement that does not depend on the client being able to answer at all.
---
--- `/ncm car` has placed cars reliably for weeks using exactly this: the SERVER's player snapshot, which NCM
--- uses in nine places, and a defensive `heading or yaw or 0`. It casts no rays and asks the client nothing.
--- The clearance probe is a refinement on top of that, not a prerequisite -- so when the probe cannot RUN
--- (no character state, no position yet), fall back here rather than refusing a car the player owns.
---
--- A geometry refusal is different and is still honoured: "there is a wall there" is real information, and
--- this does not override it.
local function kerbPose(pid)
    local p = Open77.players.get(pid)
    if not p or not position(p.position) then return nil end
    local yaw = tonumber(p.heading or p.yaw or 0) or 0
    local rad = math.rad(yaw)
    local fx, fy = -math.sin(rad), math.cos(rad)
    local rx, ry = math.cos(rad), math.sin(rad)
    return { x = p.position.x + fx*5.0 + rx*3.0, y = p.position.y + fy*5.0 + ry*3.0,
             z = p.position.z + 0.5, yaw = yaw }
end

-- Reasons meaning "the probe could not run", as opposed to "there is no room".
local CANNOT_PROBE = { no_state=true, no_position=true, error=true }

local function clear(pid, request)
    if pending[pid] == request then pending[pid] = nil end
    if locks[request.assetId] == request then locks[request.assetId] = nil end
end
local function vehicleIndexKey(vehicleId)
    if vehicleId == nil then return nil end
    return tostring(vehicleId)
end

local function forgetActive(assetId, why)
    local cur = active[assetId]
    if not cur then return nil end
    local key = vehicleIndexKey(cur.vehicleId)
    if key and assetByVehicle[key] == assetId then assetByVehicle[key] = nil end
    active[assetId] = nil
    -- Same-resource lifecycle signal. Consumers receive permanent identity plus the exact ephemeral body
    -- that ceased representing it; no client can forge this event.
    TriggerEvent("ncm:vehicle:dematerialized", assetId, cur.vehicleId, why)
    return cur
end
local function owner(pid, assetId)
    local profile = NcmIdentity.get(pid)
    if not profile or not MySQL.isReady() then return nil end
    local row = MySQL.single.await([[SELECT asset_id, vehicle_key, record, paint_primary, paint_secondary,
        gearbox_kind, gearbox_spec, gearbox_source
        FROM vehicle_asset
        WHERE asset_id=? AND ncm_driver_id=? AND server_id=?]],
        { assetId, profile.ncmDriverId, profile.serverId })
    return row, profile
end
--- Print the scalar fields a player snapshot actually carries. Used only on refusal, so it costs nothing in
--- the normal path and answers "which field is missing?" once, from the platform itself, rather than from a
--- guess about the platform.
local function describeSnap(p)
    if type(p) ~= "table" then return "snapshot=" .. tostring(p) end
    local parts = {}
    for k, v in pairs(p) do
        if type(v) ~= "table" and type(v) ~= "function" then parts[#parts+1] = tostring(k) .. "=" .. tostring(v) end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, " ") .. "}"
end

--- The player must be on foot, still, and in the world.
---
--- **Instrumented because the refusal was indistinguishable from the cause.** The owner stood still on a road
--- divider and was told to stand still: one of these conditions was failing and nothing said which. Note that
--- `p.ready` is required here and is referenced NOWHERE else in NCM, while `p.fresh` and `p.position` are used
--- throughout proven code -- so a snapshot without a `ready` field would refuse every call ever made, silently
--- and forever. This log settles that from the platform rather than from inference.
local function player(pid, why)
    local p = Open77.players.get(pid)
    local fail
    if not p then fail = "no snapshot"
    elseif not position(p.position) then fail = "no position"
    -- `ready` is honoured when the platform supplies it, but its ABSENCE is not a refusal. It appears
    -- nowhere else in NCM, whereas `fresh` + `position` are what the rest of the codebase (and KB-60's
    -- readiness work) rely on -- so demanding `ready == true` would refuse every call forever on a snapshot
    -- that simply does not carry the field. The substantive checks are unchanged: in the world, on foot,
    -- stationary. The log line below records the real snapshot either way, so this is settled by evidence on
    -- the next attempt rather than left as an assumption.
    elseif p.ready == false then fail = "ready=false"
    elseif p.fresh ~= true then fail = "fresh~=true"
    elseif not finite(p.speed) then fail = "speed not finite"
    elseif p.speed > 0.5 then fail = ("speed=%.2f > 0.5"):format(p.speed) end
    if fail then
        print(("[ncm_world/access] player check refused (%s) at %s: %s | snapshot %s")
            :format(tostring(why or "?"), tostring(pid), fail, describeSnap(p)))
        return nil
    end
    return p
end
local function existing(pid, assetId)
    local cur = active[assetId]
    if not cur then return false end
    local snap = Open77.vehicles.get(cur.vehicleId) -- nil means unknown, errors fail closed in caller
    if snap then
        feedback(pid, "This vehicle is already in the world. Return to it; another copy will not be called.", true)
        return true
    end
    TriggerEvent("ncm:collection:unregisterVehicle", cur.vehicleId)
    forgetActive(assetId, "runtime missing")
    return false
end

RegisterNetEvent("ncm:vehicle.call", function(assetId)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(assetId) ~= "string" or #assetId ~= 36 then return end
    if tradeReserved[assetId] then
        feedback(pid,"This Machine is reserved in an Exchange. Remove it from the offer or cancel the Exchange first.")
        return
    end
    if pending[pid] or locks[assetId] or clock() < (cooldown[pid] or 0) then
        feedback(pid, "Please wait for your current vehicle call."); return
    end
    print(("[ncm_world/access] CALL requested by player=%d asset=%s"):format(pid, tostring(assetId):sub(1,8)))
    cooldown[pid] = clock() + 3
    seq = seq + 1
    local request = { assetId=assetId, token=tostring(seq), started=clock() }
    pending[pid], locks[assetId] = request, request -- before any yielding database read
    CreateThread(function()
        local ok, err = pcall(function()
            local row, profile = owner(pid, assetId)
            if pending[pid] ~= request then return end
            if not row then feedback(pid, "That asset is not available under your ownership."); clear(pid,request); return end
            if not supported[row.record] then feedback(pid,"Calling this model is not supported yet. Your ownership is unchanged."); clear(pid,request); return end
            request.driverId = profile.ncmDriverId
            if existing(pid,assetId) then clear(pid,request); return end
            local p = player(pid, "before probe")
            if not p then feedback(pid,"Stand still on foot in an open roadway or parking area and try again."); clear(pid,request); return end
            request.origin = {x=p.position.x,y=p.position.y,z=p.position.z}
            request.bucket = p.bucket
            TriggerClientEvent("ncm:vehicle.probe", pid, request.token, request.origin)
            feedback(pid, "Checking nearby space...", true, "pending")
        end)
        if not ok then
            print("[ncm_world/access] request failed: " .. tostring(err))
            clear(pid,request); feedback(pid,"Vehicle access is unavailable. Your ownership is unchanged.")
        end
    end)
    CreateThread(function()
        Wait(10000)
        if pending[pid] == request then
            clear(pid,request); feedback(pid,"Unable to call your vehicle here. Move to an open roadway or parking area and try again.")
        end
    end)
end)

--- Spawn an OWNED Machine at a pose and register it (paint, registry, collection, the player's active list). Shared
--- by CALL (after its ground probe) and by `NcmVehicleAccess.materializeAt` (L329: arriving from Deep, no probe).
local function spawnOwned(pid, assetId, row, profile, pose, bucket)
    -- Exact stored record only. No model fallback, issue, grant, replacement asset or stock mutation.
    -- L306: a manual is the same machine in its gearbox clone record (`<record>_ncm_gbx_<spec>`), which
    -- only exists where NCM Gearbox is installed -- so it spawns as one only where the operator says
    -- every client has it (`ncm_gearbox_spawn_clones`, dev spike first). Never silently as an automatic:
    -- with the switch off a manual asset spawns its model record AND says so in the log.
    local spawnRecord = row.record
    do
        local GB = NcmCore.get("machine.gearbox")
        local gb = GB.fromRow(row)
        if GB.isManual(gb) then
            if GetConvar("ncm_gearbox_spawn_clones", "false") == "true" then
                spawnRecord = GB.record(row.record, gb)
            else
                print(("[ncm_world/access] asset %s is a %s manual; clones off -- model record"):format(
                    tostring(row.asset_id):sub(1, 8), gb.spec))
            end
        end
    end
    local vid, why = Open77.vehicles.create({record=spawnRecord,
        position={x=pose.x,y=pose.y,z=pose.z},yaw=pose.yaw,bucket=bucket})
    if not vid then
        print("[ncm_world/access] create refused: " .. tostring(why))
        return nil, why
    end
    -- L111: this machine's own finish, not whatever the engine felt like.
    --
    -- **This previously reached for `NcmOwnership`, which does not exist here.** `ncm_league` and
    -- `ncm_world` are separate resources with separate Lua VMs, so the guard `if NcmOwnership` was
    -- simply false and the paint was never applied once -- which is why an owned MaiMai came back
    -- green, then red. That is the third time in one day this cross-resource assumption has bitten
    -- (KB-66's grant, the `driver_location` identity, and now this).
    --
    -- The fix removes the dependency rather than bridging it: this file already reads `vehicle_asset`
    -- directly, and `data.vehicle_config` is shared core available in both resources. Nothing is asked
    -- of another VM.
    -- Wrapped in a closure, not `pcall(NcmCore.get, ...)`: that form INDEXES `NcmCore` before pcall
    -- can protect anything, so a missing core would throw rather than degrade. Caught by the
    -- vehicle-access harness, which has no core loaded.
    local okCfg, Config = pcall(function() return NcmCore.get("data.vehicle_config") end)
    if okCfg and Config then
        local paint = Config.paintFor(row.vehicle_key, assetId,
            { primary = row.paint_primary, secondary = row.paint_secondary })
        if paint and paint.primary then
            -- **Applied twice, deliberately.** The first call lands in the same tick as `create`, and
            -- owner QA on 2026-09-23 saw one machine spawn red and the next blue from identical calls
            -- that both logged success -- a client that has already streamed the vehicle keeps the
            -- engine's own variant. The second pass, after the entity has settled, is what makes the
            -- finish stick. Cosmetic either way: a refused repaint never costs the player their car.
            --
            -- The result is logged RAW. The previous line treated a `nil` return as success, so it
            -- could not have told us which of the two calls actually worked.
            local function apply(tag)
                local okPaint, applied = pcall(Open77.vehicles.setPaint, vid,
                    { primary = paint.primary, secondary = paint.secondary })
                print(("[ncm_world/access] paint %s asset=%s %s (%s) ok=%s ret=%s"):format(
                    tag, tostring(assetId):sub(1, 8),
                    tostring(paint.name or "stored"), tostring(paint.source),
                    tostring(okPaint), tostring(applied)))
                return okPaint and applied
            end
            apply("pass1")
            CreateThread(function()
                Wait(1500)
                if active[assetId] and active[assetId].vehicleId == vid then apply("pass2") end
            end)
        end
    end
    -- `pid` is stored so the disconnect path never has to ask an identity cache that may already
    -- have been cleared. At materialise time we certainly know who asked; at disconnect we
    -- certainly know who left. Nothing in between needs to still be true.
    active[assetId] = {vehicleId=vid,driverId=profile.ncmDriverId,record=row.record,pid=pid}
    if NcmVehicleCondition and NcmVehicleCondition.restore then
        local okCondition, applied, whyCondition = pcall(NcmVehicleCondition.restore, assetId, vid)
        if not okCondition or applied == false then
            print(("[ncm_world/access] damage restore asset=%s refused: %s"):format(assetId:sub(1,8), tostring(okCondition and whyCondition or applied)))
            pcall(Open77.vehicles.remove, vid)
            active[assetId] = nil
            return nil, "damage_restore_failed"
        end
    end
    assetByVehicle[vehicleIndexKey(vid)] = assetId
    TriggerEvent("ncm:vehicle:materialized", assetId, vid, pid)
    TriggerEvent("ncm:collection:registerVehicle",vid,row.record,"owned_call",profile.ncmDriverId,"owned",assetId)
    print(("[ncm_world/access] materialized asset=%s runtime=%s"):format(assetId,tostring(vid)))
    -- Before the result, not after: the page labels the button from the active set, so settling it
    -- first means CALL becomes STORE in one step rather than flickering through "CALL" again.
    sendActive(pid)
    return vid
end

RegisterNetEvent("ncm:vehicle.probed", function(token, pose, why, shape)
    local pid = tonumber(source) or 0
    local request = pending[pid]
    if not request or token ~= request.token or request.consuming then return end
    request.consuming = true -- duplicate replies cannot race a yielding ownership check
    CreateThread(function()
        local ok, err = pcall(function()
            if not position(pose) or not finite(pose.yaw) then
                print(("[ncm_world/access] probe found nowhere for player=%d: %s %s")
                    :format(pid, tostring(why), type(shape) == "string" and shape:sub(1, 300) or ""))
                -- The probe could not run at all: use the placement `/ncm car` has always used. Every
                -- server-side check below (distance, bucket, nearby players, nearby vehicles) still applies.
                if CANNOT_PROBE[tostring(why)] then
                    pose = kerbPose(pid)
                    if pose then
                        print(("[ncm_world/access] falling back to kerb placement for player=%d"):format(pid))
                    end
                end
            end
            if not position(pose) or not finite(pose.yaw) then
                feedback(pid, REASON[tostring(why)] or
                    "No clear space within 10 m. Move to an open roadway or parking area and try again."); return
            end
            local row, profile = owner(pid,request.assetId) -- fresh authoritative title, never cached UI ownership
            if pending[pid] ~= request then return end
            if tradeReserved[request.assetId] then
                feedback(pid,"This Machine entered an Exchange while placement was being checked. Call cancelled.")
                return
            end
            if not row or profile.ncmDriverId ~= request.driverId or not supported[row.record] then
                feedback(pid,"This asset is no longer available to call under your ownership."); return
            end
            local p = player(pid, "after probe")
            if not p or p.bucket ~= request.bucket or clock()-request.started > 10
                or distance(p.position,request.origin)>1 or distance(p.position,pose)<5
                or distance(p.position,pose)>12 or math.abs(pose.z-p.position.z)>1.5 then
                feedback(pid,"You moved or the location changed. Stand still and try again."); return
            end
            if existing(pid,request.assetId) then return end
            -- The client can see local geometry; the server independently checks shared occupants/vehicles.
            for _,otherId in ipairs(Open77.players.all()) do
                if tonumber(otherId) ~= pid then
                    local other=Open77.players.get(otherId)
                    if other and other.bucket==p.bucket and position(other.position) and distance(other.position,pose)<5 then
                        feedback(pid,"Someone is too close to the call location. Move and try again."); return
                    end
                end
            end
            for _,vehicle in ipairs(Open77.vehicles.all()) do
                local snap=Open77.vehicles.get(type(vehicle)=="table" and vehicle.id or vehicle)
                local at=snap and (snap.position or {x=snap.x,y=snap.y,z=snap.z})
                if snap and snap.bucket==p.bucket and position(at) and distance(at,pose)<6 then
                    feedback(pid,"Another vehicle is too close. Move to a clear area and try again."); return
                end
            end
            local vid, whyCreate = spawnOwned(pid, request.assetId, row, profile, pose, p.bucket)
            if not vid then
                feedback(pid,"Your vehicle could not be called. Your ownership is unchanged."); return
            end
            feedback(pid,"Your vehicle has been called nearby. Look around before driving.",true)
        end)
        clear(pid,request)
        if not ok then
            print("[ncm_world/access] call failed: " .. tostring(err))
            feedback(pid,"Vehicle access is unavailable. Your ownership is unchanged.")
        end
    end)
end)

--- STORE: the other half of CALL, and the reason CALL is usable more than once.
---
--- Owner, 2026-09-27: a called car cannot be called again while it is in the world, so a car left behind at a
--- venue is a car you cannot use until you disconnect. Storing has to work from ANYWHERE -- the whole point is
--- that the player is not standing next to it -- so there is no placement probe, no distance check and no
--- pose: nothing is being created, only removed.
---
--- Ownership is untouched, exactly as in `reclaim`. Title is still re-read from `vehicle_asset` rather than
--- trusted from the runtime registry, because "this is mine" is a database fact and the panel is a client.
---
--- An OCCUPIED car is refused rather than deleted from under whoever is sitting in it -- the same rule
--- `reclaim` follows, for the same reason.
RegisterNetEvent("ncm:vehicle.store", function(assetId)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(assetId) ~= "string" or #assetId ~= 36 then return end
    if pending[pid] or locks[assetId] then
        storeFeedback(pid, "Please wait for your current vehicle call."); return
    end
    if not active[assetId] then
        sendActive(pid)   -- the page was offering STORE for something that is gone; correct it first
        storeFeedback(pid, "That Machine is not in the world."); return
    end
    print(("[ncm_world/access] STORE requested by player=%d asset=%s"):format(pid, tostring(assetId):sub(1,8)))
    seq = seq + 1
    local request = { assetId = assetId, token = tostring(seq), started = clock() }
    locks[assetId] = request -- one store at a time per asset; a yielding title read must not race a call
    CreateThread(function()
        local ok, err = pcall(function()
            local row, profile = owner(pid, assetId)
            if not row then storeFeedback(pid, "That asset is not available under your ownership."); return end
            local cur = active[assetId]
            if not cur then storeFeedback(pid, "That Machine is not in the world."); return end
            if cur.driverId ~= profile.ncmDriverId then
                storeFeedback(pid, "That Machine is not yours to store."); return
            end
            local okSnap, snap = pcall(Open77.vehicles.get, cur.vehicleId)
            if okSnap and type(snap) == "table" and snap.occupants and next(snap.occupants) ~= nil then
                storeFeedback(pid, "Someone is still sitting in it. Step out (or wait) and store it again."); return
            end
            -- Its kilometres must be durable before the live vehicle disappears (same order as `reclaim`).
            if NcmOdometer and NcmOdometer.release then pcall(NcmOdometer.release, assetId) end
            if NcmVehicleCondition and NcmVehicleCondition.save then
                local okCondition, saved = pcall(NcmVehicleCondition.save, assetId, cur.vehicleId)
                if not okCondition or saved == false then storeFeedback(pid, "Vehicle damage could not be saved. Try again."); return end
            end
            TriggerEvent("ncm:collection:unregisterVehicle", cur.vehicleId)
            pcall(Open77.vehicles.remove, cur.vehicleId)
            forgetActive(assetId, "stored by owner")
            print(("[ncm_world/access] stored asset=%s (owner request); ownership unchanged")
                :format(tostring(assetId):sub(1,8)))
            sendActive(pid)
            storeFeedback(pid, "Stored. Call it again from Machine Index whenever you need it.", true)
        end)
        if locks[assetId] == request then locks[assetId] = nil end
        if not ok then
            print("[ncm_world/access] store failed: " .. tostring(err))
            sendActive(pid)   -- whatever happened, the page must not be left guessing
            storeFeedback(pid, "Vehicle access is unavailable. Your ownership is unchanged.")
        end
    end)
end)

-- The panel asks when it opens: a car called in an earlier open is still out there.
RegisterNetEvent("ncm:vehicle.active.request", function() sendActive(tonumber(source) or 0) end)

-- A league-resource restart loses its in-memory custody mirror while this resource may still own live cars.
-- Replay the exact registry on request so Exchange can never transfer a body it merely forgot was outside.
AddEventHandler("ncm:trade:requestActiveSnapshot",function()
    for assetId,cur in pairs(active) do TriggerEvent("ncm:vehicle:materialized",assetId,cur.vehicleId,cur.pid) end
end)

-- An offered Machine may not race a placement probe into the world between final validation and SQL commit.
-- The Exchange owns the reservation; this resource only enforces it at both sides of its yielding probe.
AddEventHandler("ncm:trade:reserveMachine",function(assetId,tradeId)
    if type(assetId)=="string" and assetId~="" then tradeReserved[assetId]=tostring(tradeId or "trade") end
end)
AddEventHandler("ncm:trade:releaseMachine",function(assetId,tradeId)
    if type(assetId)=="string" and (tradeId==nil or tradeReserved[assetId]==tostring(tradeId)) then tradeReserved[assetId]=nil end
end)
AddEventHandler("ncm:trade:reservationsReset",function() tradeReserved={} end)
CreateThread(function() Wait(0);TriggerEvent("ncm:trade:requestReservationSnapshot") end)

--- Called cars do not outlive their owner's session.
---
--- Owner QA, 2026-09-23: *"the mai mai i had spawned in just before was still on the road in the same spot
--- when i rejoined. that would become unsustainable accumulation."* Correct -- the previous rule kept every
--- materialised car forever so a reconnect would find it, which means a world that only ever gains vehicles.
---
--- Ownership is untouched: the asset stays theirs and CALL brings it back in seconds. An OCCUPIED car is left
--- alone, because removing a vehicle somebody is sitting in is the one outcome worse than accumulation.
local function reclaim(pid, why, force)
    pid = tonumber(pid) or 0
    if pid <= 0 then return end
    local looked = 0
    for assetId, cur in pairs(active) do
        looked = looked + 1
        if cur.pid == pid then
            local okSnap, snap = pcall(Open77.vehicles.get, cur.vehicleId)
            local occupied = okSnap and type(snap) == "table" and snap.occupants and next(snap.occupants) ~= nil
            if occupied and not force then
                print(("[ncm_world/access] left asset=%s in the world: occupied"):format(tostring(assetId):sub(1,8)))
            else
                -- Its kilometres must be durable before the live vehicle disappears.
                if NcmOdometer and NcmOdometer.release then pcall(NcmOdometer.release, assetId) end
                local checkpointOkay = true
                if not tostring(why):match("^Racing Week ") and NcmVehicleCondition and NcmVehicleCondition.save then
                    local okCondition, saved = pcall(NcmVehicleCondition.save, assetId, cur.vehicleId)
                    if not okCondition or saved == false then
                        print(("[ncm_world/access] reclaim held asset=%s: damage checkpoint failed"):format(tostring(assetId):sub(1,8)))
                        -- The live representation holds the only trustworthy damage snapshot.
                        checkpointOkay = false
                    end
                end
                if checkpointOkay then
                    TriggerEvent("ncm:collection:unregisterVehicle", cur.vehicleId)
                    pcall(Open77.vehicles.remove, cur.vehicleId)
                    forgetActive(assetId, why)
                    print(("[ncm_world/access] reclaimed asset=%s (%s); ownership unchanged")
                        :format(tostring(assetId):sub(1,8), tostring(why)))
                end
            end
        end
    end
end

--- L329: put an owned Machine in the world at a pose WITHOUT the call's ground probe -- the Machine arrives from NCM
--- Deep (canonical position, possibly in the air). Ownership is re-read from `vehicle_asset` exactly as CALL does; an
--- already-live copy is reused, never duplicated. Returns vehicleId or nil + why.
function NcmVehicleAccess.materializeAt(pid, assetId, pose, why)
    pid = tonumber(pid) or 0
    if pid <= 0 or type(assetId) ~= "string" or not position(pose) then return nil, "bad request" end
    local cur = active[assetId]
    if cur and Open77.vehicles.get(cur.vehicleId) then return cur.vehicleId, "already live" end
    if cur then forgetActive(assetId, "runtime missing") end
    local row, profile = owner(pid, assetId)
    if not row or not supported[row.record] then return nil, "not owned or unsupported" end
    local p = Open77.players.get(pid)
    local vid, whyC = spawnOwned(pid, assetId, row, profile, pose, p and p.bucket or 0)
    print(("[ncm_world/access] materializeAt asset=%s (%s) -> %s %s"):format(assetId:sub(1, 8), tostring(why), tostring(vid), tostring(whyC or "")))
    return vid, whyC
end

--- Every asset currently materialised in the world, as { assetId, vehicleId } pairs.
---
--- `odometer.lua` reads this to know which live vehicle IS which persistent machine. Same resource, same Lua
--- VM, so this is a plain call and not a cross-scope reach (L113).
function NcmVehicleAccess.liveAssets()
    local out = {}
    for assetId, cur in pairs(active) do
        if cur and cur.vehicleId then
            out[#out + 1] = { assetId = assetId, vehicleId = cur.vehicleId, pid = cur.pid }
        end
    end
    return out
end

--- The active representation of one persistent Machine, or nil.
---
--- A copy is returned so another subsystem cannot mutate the access registry by retaining the table.
function NcmVehicleAccess.liveAsset(assetId)
    local cur = type(assetId) == "string" and active[assetId] or nil
    if not cur then return nil end
    return { assetId = assetId, vehicleId = cur.vehicleId, pid = cur.pid,
             driverId = cur.driverId, record = cur.record }
end

function NcmVehicleAccess.assetForVehicle(vehicleId)
    return assetByVehicle[vehicleIndexKey(vehicleId)]
end

--- Emergency recovery after an authoritative dismount (fuel/tow). Ownership is untouched.
function NcmVehicleAccess.recoveryStore(assetId, reason)
    local cur=type(assetId)=="string" and active[assetId] or nil;if not cur then return false,"not_materialized" end
    if NcmOdometer and NcmOdometer.release then local ok,why=NcmOdometer.release(assetId);if ok==false then return false,why end end
    if NcmVehicleCondition and NcmVehicleCondition.save then
        local okCondition, saved = pcall(NcmVehicleCondition.save, assetId, cur.vehicleId)
        if not okCondition or saved == false then return false, "damage_checkpoint_failed" end
    end
    TriggerEvent("ncm:collection:unregisterVehicle",cur.vehicleId)
    pcall(Open77.vehicles.remove,cur.vehicleId);forgetActive(assetId,reason or "emergency recovery")
    if cur.pid then sendActive(cur.pid) end
    return true
end

--- Resolve the persistent Machine this player's client is authoritatively simulating.
---
--- Driver and physics owner are not interchangeable: authority may briefly be held by a passenger/steward
--- while another player occupies the driver seat. Force interception has to run on the physics owner, so
--- delivery follows `Open77.vehicles.owner`, while a present human driver proves this is an operational car
--- and not merely a parked stewardship lease. More than one candidate fails closed as ambiguous.
function NcmVehicleAccess.bindingForAuthority(playerId)
    local pid = tonumber(playerId) or 0
    if pid <= 0 then return nil, "bad_player" end
    local found
    for assetId, cur in pairs(active) do
        local okOwner, owner = pcall(Open77.vehicles.owner, cur.vehicleId)
        if okOwner and type(owner) == "table" then
            local physicsOwner = tonumber(owner.physicsOwner or owner.authorityPlayerId) or 0
            local driver = tonumber(owner.driver) or 0
            local epoch = tonumber(owner.epoch)
            if physicsOwner == pid and driver > 0 and not owner.aiDriven and epoch then
                if found then return nil, "ambiguous_authority" end
                found = { assetId = assetId, vehicleId = cur.vehicleId, pid = pid,
                    driverPlayerId = driver, authorityEpoch = epoch, record = cur.record }
            end
        end
    end
    if not found then return nil, "no_owned_active_asset" end
    return found
end

-- Transitional name for callers written against the first asset-binding draft. It deliberately has the
-- corrected physics-authority semantics above, not seat/operator semantics.
NcmVehicleAccess.bindingForOperator = NcmVehicleAccess.bindingForAuthority

--- Current authoritative operator of an active Machine, if one is proven.
function NcmVehicleAccess.operatorForAsset(assetId)
    local cur = type(assetId) == "string" and active[assetId] or nil
    if not cur then return nil, "not_materialized" end
    local okOwner, owner = pcall(Open77.vehicles.owner, cur.vehicleId)
    if not okOwner or type(owner) ~= "table" then return nil, "owner_unavailable" end
    local pid = tonumber(owner.physicsOwner or owner.authorityPlayerId) or 0
    if pid <= 0 or (tonumber(owner.driver) or 0) <= 0 or owner.aiDriven then
        return nil, "no_human_driven_authority"
    end
    local binding, why = NcmVehicleAccess.bindingForAuthority(pid)
    if not binding or binding.assetId ~= assetId then return nil, why or "binding_mismatch" end
    return pid, binding
end

-- Record an actual drive, including a short one with no odometer interval yet. A called or
-- passenger-occupied car is not the owner's "last driven" car.
local lastDriveWrite, lastDrivenAsset = {}, {}
CreateThread(function()
    while true do
        Wait(5000)
        local t = math.floor(Open77.time.unix())
        for assetId, cur in pairs(active) do
            if t - (lastDriveWrite[assetId] or 0) >= 30 or lastDrivenAsset[cur.pid] ~= assetId then
                local driver = NcmVehicleAccess.operatorForAsset(assetId)
                local okMotion, motion = pcall(Open77.vehicles.get, cur.vehicleId)
                local speed = okMotion and type(motion)=="table" and (tonumber(motion.speed) or ((tonumber(motion.speedKph) or 0)/3.6)) or 0
                if driver and driver == cur.pid and speed > 0.5 then
                    local ok, err = pcall(MySQL.update.await,
                        "UPDATE vehicle_asset SET last_driven_at=? WHERE asset_id=? AND ncm_driver_id=? AND server_id=?",
                        { t, assetId, cur.driverId, (GlobalState.ncmIdentity or {}).serverId })
                    if ok then lastDriveWrite[assetId], lastDrivenAsset[cur.pid] = t, assetId
                    else print("[ncm_world/access] last drive checkpoint failed: " .. tostring(err)) end
                end
            end
        end
    end
end)

AddEventHandler("ncm:week:collapse.prepare", function()
    local t = math.floor(Open77.time.unix())
    for assetId, cur in pairs(active) do
        local driver = NcmVehicleAccess.operatorForAsset(assetId)
        local okMotion, motion = pcall(Open77.vehicles.get, cur.vehicleId)
        local speed = okMotion and type(motion)=="table" and (tonumber(motion.speed) or ((tonumber(motion.speedKph) or 0)/3.6)) or 0
        if driver == cur.pid and speed > 0.5 then
            MySQL.update.await("UPDATE vehicle_asset SET last_driven_at=? WHERE asset_id=? AND ncm_driver_id=?",
                { t, assetId, cur.driverId })
        end
    end
end)

AddEventHandler("onPlayerDisconnected", function(pid)
    pid=tonumber(pid) or 0
    if pending[pid] then clear(pid,pending[pid]) end
    cooldown[pid]=nil
    -- Keyed on the player id recorded at materialise time. The first attempt asked `NcmIdentity` here and
    -- reclaimed nothing in production while passing in the harness, so the identity lookup is gone rather
    -- than debugged: at disconnect the one fact we are certain of is which player left.
    local n = 0
    for _, cur in pairs(active) do if cur.pid == pid then n = n + 1 end end
    print(("[ncm_world/access] disconnect player=%d: %d called vehicle(s) to reclaim"):format(pid, n))
    pcall(reclaim, pid, "owner disconnected")
end)
-- Racing Week's collapse (L303): the tape rewinds and every called car goes back to its garage. Anchored cars are
-- still owned and can be called again; the rest now live in the run's archive namespace.
AddEventHandler("ncm:week:collapsed", function(run)
    local pids = {}
    for _, cur in pairs(active) do if cur.pid then pids[cur.pid] = true end end
    -- A rewind has a hard custody boundary. Open77.vehicles.remove clears canonical occupancy;
    -- leaving an occupied, now-archived car in the new Week would defeat both the anchor and damage reset.
    for pid in pairs(pids) do pcall(reclaim, pid, "Racing Week " .. tostring(run) .. " ended", true) end
    print(("[ncm_world/access] Racing Week %s collapsed: called cars reclaimed for %d player(s)"):format(tostring(run),
        (function() local n = 0 for _ in pairs(pids) do n = n + 1 end return n end)()))
end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_world" then return end
    for _,cur in pairs(active) do
        TriggerEvent("ncm:collection:unregisterVehicle",cur.vehicleId)
        pcall(Open77.vehicles.remove,cur.vehicleId)
    end
    -- Tell consumers to clear while the exact identities are still available. `pairs` cannot be mutated
    -- safely while iterating on every Lua runtime, so collect the keys first.
    local ids = {}
    for assetId in pairs(active) do ids[#ids + 1] = assetId end
    for _, assetId in ipairs(ids) do forgetActive(assetId, "resource stopping") end
end)
