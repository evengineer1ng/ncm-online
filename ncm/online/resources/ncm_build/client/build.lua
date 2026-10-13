-- ncm_build / client / build -- placement for the Build primitive (IDEA-1282).
--
-- PLACEMENT is local: the chosen catalogue object is a client-only prop bound to the Machine with the platform's own
-- binding (`Open77.props.attach` works on a resource's local props too), so the preview rides the car exactly as the
-- real one will. Nudges move it in the PARENT's frame (a Machine: x right, y forward, z up; a member: its own axes);
-- nothing is sent until ATTACH. The server then mints the real, replicated prop; the preview goes.
--
-- Driven by ncm_engineering's BUILD tab through these client exports (the panel is cursor-only: no keyboard):
--   state()                          the catalogue, my Machines out in the city, their attachments, the placement
--   refresh()                        ask the server again
--   begin(assetId, machineId, parentAttachmentId?)   start placing a new object
--   edit(attachmentId)               start moving an existing one (the preview starts where it is)
--   nudge(axis, sign)                axis: x y z roll pitch yaw; sign +1 / -1; one step of the current size
--   step(size)                       "coarse" (10 cm, 15 deg) | "fine" (1 cm, 1 deg)
--   commit()  cancel()  remove(attachmentId)
local B = NcmCore.get("build.attach")
local function log(fmt, ...) print(("[ncm_build] " .. fmt):format(...)) end

local STEPS = { coarse = { m = 0.10, deg = 15 }, fine = { m = 0.01, deg = 1 } }
local view = { catalogue = {}, machines = {}, attachments = {} }
local placing = nil   -- { assetId, machineId, vehicleId, parent, pos, rot, editing?, propId, base = { pos, rot } }
local stepSize = "coarse"
local lastResult = nil

local function byId()
    local t = {}
    for _, a in ipairs(view.attachments or {}) do t[a.id] = a end
    return t
end

local function machine(id)
    for _, m in ipairs(view.machines or {}) do if m.machineId == id then return m end end
    return nil
end

-- The parent's frame in the root Machine's frame (identity for a Machine; the member's composed transform otherwise).
local function parentFrame(parent)
    if parent.kind ~= "attachment" then return { 0, 0, 0 }, { 0, 0, 0 } end
    local a = byId()[parent.id]
    if a and a.rootPos and a.rootRot then return a.rootPos, a.rootRot end
    return { 0, 0, 0 }, { 0, 0, 0 }
end

local function dropPreview()
    if placing and placing.propId then pcall(Open77.props.remove, placing.propId) end
    if placing then placing.propId, placing.kitPose = nil, nil end
end

local function showPreview()
    if not placing then return end
    local item = B.CATALOGUE[placing.assetId]
    if not item then return end
    local ppos, prot = parentFrame(placing.parent)
    local pos, rot = B.compose(ppos, prot, placing.pos, placing.rot)
    if item.kit then          -- the kit: NCM Sky draws the preview (below), exactly as the real piece will look
        placing.kitPose = { kind = item.skyKind, pos = pos, rot = rot }
        return
    end
    local binding = { parentType = "vehicle", parentId = tostring(placing.vehicleId), bone = "",
        offset = { x = pos[1], y = pos[2], z = pos[3] }, rotation = { x = rot[1], y = rot[2], z = rot[3] } }
    if not placing.propId then
        local okC, id, why = pcall(Open77.props.create, { model = item.model, position = { x = 0, y = 0, z = -500 },
            collision = false })
        if not (okC and id) then
            lastResult = { ok = false, text = "Preview refused: " .. tostring(okC and why or id) }
            log("preview %s refused: %s", placing.assetId, tostring(okC and why or id))
            return
        end
        placing.propId = id
    end
    local okA, res, why = pcall(Open77.props.attach, placing.propId, binding)
    if not (okA and res) then
        lastResult = { ok = false, text = "Preview could not mount: " .. tostring(okA and why or res) }
        log("preview bind refused: %s", tostring(okA and why or res))
    end
end

local function snapshot()
    return {
        catalogue = view.catalogue, machines = view.machines, attachments = view.attachments, limits = view.limits,
        step = stepSize, result = lastResult,
        placing = placing and { assetId = placing.assetId, machineId = placing.machineId, parent = placing.parent,
            pos = placing.pos, rot = placing.rot, editing = placing.editing,
            label = (B.CATALOGUE[placing.assetId] or {}).label } or nil,
    }
end

RegisterNetEvent("ncm:build.state", function(s)
    if type(s) ~= "table" then return end
    view = s
    -- a Machine that left the city takes its placement with it
    if placing and not machine(placing.machineId) then dropPreview(); placing = nil end
end)

RegisterNetEvent("ncm:build.result", function(r)
    if type(r) ~= "table" then return end
    lastResult = { ok = r.ok == true, text = tostring(r.text or ""), op = r.op }
    log("%s %s: %s", tostring(r.op), r.ok and "ok" or "REFUSED", tostring(r.text))
    if r.ok then dropPreview(); placing = nil end
end)

exports("state", function() return snapshot() end)
exports("refresh", function() TriggerServerEvent("ncm:build.request"); return true end)

exports("begin", function(assetId, machineId, parentAttachmentId)
    local m = machine(tostring(machineId or ""))
    if not (B.CATALOGUE[assetId or ""] and m) then return false end
    dropPreview()
    local parent = parentAttachmentId and { kind = "attachment", id = tostring(parentAttachmentId) } or { kind = "machine", id = m.machineId }
    -- a fresh object starts behind and above a Machine's origin (where a rear wing goes), or just above a member
    local start = parent.kind == "machine" and { 0, -1.6, 1.1 } or { 0, 0, 0.3 }
    placing = { assetId = assetId, machineId = m.machineId, vehicleId = m.vehicleId, parent = parent, pos = start, rot = { 0, 0, 0 } }
    lastResult = nil
    showPreview()
    return true
end)

exports("edit", function(attachmentId)
    local a = byId()[tostring(attachmentId or "")]
    local m = a and machine(a.machineId)
    if not (a and m) then return false end
    dropPreview()
    placing = { assetId = a.assetId, machineId = a.machineId, vehicleId = m.vehicleId, parent = a.parent,
        pos = { a.pos[1], a.pos[2], a.pos[3] }, rot = { a.rot[1], a.rot[2], a.rot[3] }, editing = a.id }
    lastResult = nil
    showPreview()
    return true
end)

local AXES = { x = { "pos", 1 }, y = { "pos", 2 }, z = { "pos", 3 }, roll = { "rot", 1 }, pitch = { "rot", 2 }, yaw = { "rot", 3 } }
exports("nudge", function(axis, sign)
    local ax = AXES[tostring(axis or "")]
    if not (placing and ax) then return false end
    local st = STEPS[stepSize]
    local v = placing[ax[1]]
    v[ax[2]] = v[ax[2]] + ((tonumber(sign) or 0) >= 0 and 1 or -1) * (ax[1] == "pos" and st.m or st.deg)
    if ax[1] == "rot" then v[ax[2]] = ((v[ax[2]] + 180) % 360) - 180 end
    showPreview()
    return true
end)

exports("step", function(size) if STEPS[size] then stepSize = size end; return stepSize end)

exports("commit", function()
    if not placing then return false end
    if placing.editing then
        TriggerServerEvent("ncm:build.edit", { attachmentId = placing.editing, pos = placing.pos, rot = placing.rot })
    else
        TriggerServerEvent("ncm:build.attach", { machineId = placing.machineId, parent = placing.parent, assetId = placing.assetId,
            pos = placing.pos, rot = placing.rot })
    end
    return true
end)

exports("cancel", function() dropPreview(); placing = nil; lastResult = nil; return true end)
exports("remove", function(attachmentId) TriggerServerEvent("ncm:build.remove", { attachmentId = tostring(attachmentId or "") }); return true end)

-- a called car changes what is buildable: the panel asks when it opens, and this keeps it current
RegisterNetEvent("ncm:vehicle.active", function() TriggerServerEvent("ncm:build.request") end)

-- ------------------------------------------------------------------------------------------------ the kit, drawn
-- Kit pieces are NCM Sky bodies (NcmSky.reds kinds 15-29), not platform props. The server says which piece sits on
-- which Machine at which composed transform (ncm:build.world, a JSON string). On the car this player is driving a
-- piece rides it every frame inside the game ("attach_mine": NcmSky.reds composes the car's transform with the
-- piece's); on any other car it is placed in world space ten times a second from that car's pose.
local Sky = NcmCore.get("space.sky")
local Json = NcmCore.get("vocabulary.json")
local world = {}

RegisterNetEvent("ncm:build.world", function(blob)
    local okD, list = pcall(Json.decode, blob)
    if okD and type(list) == "table" then world = list end
end)

local function seatVehicle()
    local ok, seat = pcall(Open77.vehicles.getPlayerSeat)
    if not ok or type(seat) ~= "table" then return nil end
    return tostring(seat.vehicleId or seat.vehicle or seat.id)
end

-- NCM Sky ids are [a-z0-9_], at most 24 characters (ncm_sky.dll state.cpp validId): "b_" + 20 hex of the attachment id
local function skyId(attachmentId)
    return "b_" .. tostring(attachmentId):lower():gsub("[^0-9a-f]", ""):sub(1, 20)
end

local function c(a, i, k) return tonumber(a and (a[k] or a[i])) or 0 end

-- a piece at (pos, rot) in its car's frame -> the body NCM Sky draws
local function body(id, kind, pos, rot, vid, mine)
    local Rl = B.matrix(rot)
    if mine then
        return { id = id, kind = kind, app = "attach_mine", p = { pos[1], pos[2], pos[3] }, q = Sky.quat(Rl) }
    end
    local okP, v = pcall(Open77.vehicles.get, vid)
    local okF, f = pcall(Open77.character.frame, { vehicleId = vid })
    if not (okP and type(v) == "table" and v.position and okF and type(f) == "table" and f.forward) then return nil end
    local r, fw, u = f.right, f.forward, f.up
    local Rc = { { c(r, 1, "x"), c(fw, 1, "x"), c(u, 1, "x") }, { c(r, 2, "y"), c(fw, 2, "y"), c(u, 2, "y") },
        { c(r, 3, "z"), c(fw, 3, "z"), c(u, 3, "z") } }
    local w = Sky.mv(Rc, pos)
    return { id = id, kind = kind, p = { v.position.x + w[1], v.position.y + w[2], v.position.z + w[3] }, q = Sky.quat(Sky.mm(Rc, Rl)) }
end

CreateThread(function()
    Wait(6000)
    TriggerServerEvent("ncm:build.worldRequest")
    local warned, sentEmpty = false, false
    while true do
        Wait(100)
        local bodies = {}
        local mineVid = seatVehicle()
        for _, a in ipairs(world) do
            local b = body(skyId(a.id), tonumber(a.kind) or 0, a.pos or { 0, 0, 0 }, a.rot or { 0, 0, 0 },
                a.vehicleId, mineVid ~= nil and tostring(a.vehicleId) == mineVid)
            if b then bodies[#bodies + 1] = b end
        end
        if placing and placing.kitPose then
            local kp = placing.kitPose
            local b = body("b_preview", kp.kind, kp.pos, kp.rot, placing.vehicleId, mineVid ~= nil and tostring(placing.vehicleId) == mineVid)
            if b then bodies[#bodies + 1] = b end
        end
        -- KB-462: no call when nothing is drawn and nothing was, and every call is awaited. Ten unawaited calls a
        -- second ran the client into export_request_limit ~12 min after a join (2026-10-12), and the frame cost grew
        -- from ~1 ms to ~12 ms until it did; every other resource's exports then failed too (venue rings).
        if #bodies > 0 or not sentEmpty then
            local okC, promise, why = pcall(Open77.exports.call, "ncm_sky", "scene", "build", bodies)
            if okC and promise then
                pcall(promise.await, promise)
                sentEmpty = #bodies == 0
            elseif not warned then
                warned = true
                log("ncm_sky unreachable (%s): kit pieces are not drawn", tostring(okC and why or promise))
            end
        end
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then
        dropPreview()
        pcall(Open77.exports.call, "ncm_sky", "scene", "build", {})
    end
end)
