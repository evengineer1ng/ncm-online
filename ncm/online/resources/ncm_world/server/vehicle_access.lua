-- Runtime access only. The league owns persistent title; this adapter never writes economy/asset tables.
-- Client physics probes are placement evidence, not ownership authority (L106).
NcmVehicleAccess = {}
local pending, locks, active, cooldown = {}, {}, {}, {}
local seq = 0
-- This first clearance envelope is only for the Base Market's small starter cars.
-- Larger models need their own validated envelope, not a guess based on category.
local supported = {
    ["Vehicle.v_standard2_makigai_maimai"]=true,
    ["Vehicle.v_standard2_thorton_galena"]=true,
    ["Vehicle.v_standard2_archer_hella"]=true,
}
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
local function feedback(pid, message, ok, state)
    state = state or (ok and "ok" or "fail")
    pcall(Open77.notifications.send, pid, { type=ok and "success" or "error", title="CALL VEHICLE",
        message=message, icon="NCM", durationMs=7000 })
    pcall(TriggerClientEvent, "ncm:vehicle.result", pid, { state=state, message=message })
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
local function owner(pid, assetId)
    local profile = NcmIdentity.get(pid)
    if not profile or not MySQL.isReady() then return nil end
    local row = MySQL.single.await([[SELECT asset_id, vehicle_key, record, paint_primary, paint_secondary
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
    active[assetId] = nil
    return false
end

RegisterNetEvent("ncm:vehicle.call", function(assetId)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(assetId) ~= "string" or #assetId ~= 36 then return end
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
            -- Exact stored record only. No model fallback, issue, grant, replacement asset or stock mutation.
            local vid, why = Open77.vehicles.create({record=row.record,
                position={x=pose.x,y=pose.y,z=pose.z},yaw=pose.yaw,bucket=p.bucket})
            if not vid then
                print("[ncm_world/access] create refused: " .. tostring(why))
                feedback(pid,"Your vehicle could not be called. Your ownership is unchanged."); return
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
                local paint = Config.paintFor(row.vehicle_key, request.assetId,
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
                            tag, tostring(request.assetId):sub(1, 8),
                            tostring(paint.name or "stored"), tostring(paint.source),
                            tostring(okPaint), tostring(applied)))
                        return okPaint and applied
                    end
                    apply("pass1")
                    CreateThread(function()
                        Wait(1500)
                        if active[request.assetId] and active[request.assetId].vehicleId == vid then apply("pass2") end
                    end)
                end
            end
            -- `pid` is stored so the disconnect path never has to ask an identity cache that may already
            -- have been cleared. At materialise time we certainly know who asked; at disconnect we
            -- certainly know who left. Nothing in between needs to still be true.
            active[request.assetId] = {vehicleId=vid,driverId=profile.ncmDriverId,record=row.record,pid=pid}
            TriggerEvent("ncm:collection:registerVehicle",vid,row.record,"owned_call",profile.ncmDriverId,"owned",request.assetId)
            print(("[ncm_world/access] materialized asset=%s runtime=%s"):format(request.assetId,tostring(vid)))
            feedback(pid,"Your vehicle has been called nearby. Look around before driving.",true)
        end)
        clear(pid,request)
        if not ok then
            print("[ncm_world/access] call failed: " .. tostring(err))
            feedback(pid,"Vehicle access is unavailable. Your ownership is unchanged.")
        end
    end)
end)

--- Called cars do not outlive their owner's session.
---
--- Owner QA, 2026-09-23: *"the mai mai i had spawned in just before was still on the road in the same spot
--- when i rejoined. that would become unsustainable accumulation."* Correct -- the previous rule kept every
--- materialised car forever so a reconnect would find it, which means a world that only ever gains vehicles.
---
--- Ownership is untouched: the asset stays theirs and CALL brings it back in seconds. An OCCUPIED car is left
--- alone, because removing a vehicle somebody is sitting in is the one outcome worse than accumulation.
local function reclaim(pid, why)
    pid = tonumber(pid) or 0
    if pid <= 0 then return end
    local looked = 0
    for assetId, cur in pairs(active) do
        looked = looked + 1
        if cur.pid == pid then
            local okSnap, snap = pcall(Open77.vehicles.get, cur.vehicleId)
            local occupied = okSnap and type(snap) == "table" and snap.occupants and next(snap.occupants) ~= nil
            if occupied then
                print(("[ncm_world/access] left asset=%s in the world: occupied"):format(tostring(assetId):sub(1,8)))
            else
                -- Its kilometres must be durable before the live vehicle disappears.
                if NcmOdometer and NcmOdometer.release then pcall(NcmOdometer.release, assetId) end
                TriggerEvent("ncm:collection:unregisterVehicle", cur.vehicleId)
                pcall(Open77.vehicles.remove, cur.vehicleId)
                active[assetId] = nil
                print(("[ncm_world/access] reclaimed asset=%s (%s); ownership unchanged")
                    :format(tostring(assetId):sub(1,8), tostring(why)))
            end
        end
    end
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
AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_world" then return end
    for _,cur in pairs(active) do
        TriggerEvent("ncm:collection:unregisterVehicle",cur.vehicleId)
        pcall(Open77.vehicles.remove,cur.vehicleId)
    end
end)
