-- ncm_build / server / main -- the authority for Build attachments (IDEA-1282).
--
-- The server is the only writer. A request names a catalogue id, a parent (a Machine, or another attachment) and a
-- transform relative to that parent; it is checked (catalogue, ownership of the root Machine, limits, reach: core
-- `build.attach`), written (build_attachment, schema 078), and drawn: one server-owned prop in the vehicle's bucket,
-- bound to the vehicle with the platform's replicated binding. Chains are composed here (the platform binds to
-- vehicles and players only), so every link binds to the root vehicle at its composed transform.
--
-- Lifetime follows the MACHINE, not the spawned car: `ncm:vehicle:materialized` (ncm_world) rebuilds every live row
-- on the new vehicle; `ncm:vehicle:dematerialized` removes the props (the rows stay). A trade moves the Machine, and
-- its attachments with it, because they belong to the Machine's asset id.
--
-- Net events (client -> server):
--   ncm:build.request                                    -> ncm:build.state { catalogue, machines, attachments }
--   ncm:build.attach { machineId, parent, assetId, pos, rot }  -> ncm:build.result, then ncm:build.state
--   ncm:build.edit   { attachmentId, pos, rot }                -> ncm:build.result, then ncm:build.state
--   ncm:build.remove { attachmentId }                          -> ncm:build.result, then ncm:build.state
local B = NcmCore.get("build.attach")

local function log(fmt, ...) print(("[ncm_build] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function serverId()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    return (ok and type(id) == "table" and id.serverId) or "ncm-dev"
end
-- KB-358: CHAR(36) columns come back as GUID values: compare ids as lowercase text
local function idOf(v) return v ~= nil and tostring(v):lower() or nil end

local ok, settings = pcall(Open77.tunables.declare, {
    buildEnabled = { value = true, type = "boolean", apply = "live" },
    buildPerMachine = { value = B.LIMITS.perParent, type = "integer", min = 1, max = 30, apply = "live" },
    buildPerPlayer = { value = B.LIMITS.perPlayer, type = "integer", min = 1, max = 500, apply = "live" },
    buildTotal = { value = B.LIMITS.totalActive, type = "integer", min = 1, max = 2000, apply = "live" },
    buildMaxDepth = { value = B.LIMITS.maxDepth, type = "integer", min = 1, max = 6, apply = "live" },
    buildMaxReachM = { value = B.LIMITS.maxReachM, type = "number", min = 0.5, max = 15, apply = "live" },
    buildMaxLocalM = { value = B.LIMITS.maxLocalM, type = "number", min = 0.2, max = 15, apply = "live" },
})
if not ok then log("tunables.declare FAILED: %s", tostring(settings)); settings = nil end
local function set(k, d)
    if not settings then return d end
    local okV, v = pcall(function() return settings[k] end)
    if okV and v ~= nil then return v end
    return d
end
local function limits()
    return { perParent = set("buildPerMachine", B.LIMITS.perParent), perPlayer = set("buildPerPlayer", B.LIMITS.perPlayer),
        totalActive = set("buildTotal", B.LIMITS.totalActive), maxDepth = set("buildMaxDepth", B.LIMITS.maxDepth),
        maxReachM = set("buildMaxReachM", B.LIMITS.maxReachM), maxLocalM = set("buildMaxLocalM", B.LIMITS.maxLocalM) }
end

-- ------------------------------------------------------------------------------------------------ who is who
local driverOf = {}
local function driver(pid)
    pid = tonumber(pid) or 0
    if pid <= 0 then return nil end
    if driverOf[pid] then return driverOf[pid] end
    local okU, userId = pcall(GetPlayerIdentifier, pid)
    if not okU or type(userId) ~= "string" or userId == "" or not MySQL.isReady() then return nil end
    local row = MySQL.single.await("SELECT ncm_driver_id FROM ncm_driver_binding WHERE server_id = ? AND user_id = ?", { serverId(), userId })
    if not (row and row.ncm_driver_id) then return nil end
    driverOf[pid] = { ncmDriverId = idOf(row.ncm_driver_id) }
    return driverOf[pid]
end
AddEventHandler("playerDropped", function() local pid = tonumber(source); if pid then driverOf[pid] = nil end end)

local function ownerOf(machineId)
    local v = MySQL.scalar.await("SELECT ncm_driver_id FROM vehicle_asset WHERE asset_id = ? AND server_id = ?", { machineId, serverId() })
    return v and idOf(v) or nil
end

-- ------------------------------------------------------------------------------------------------ live state
local machines = {}    -- machineId -> { vid, pid }
local rows = {}        -- attachmentId -> { id, assetId, parent = {kind,id}, pos, rot, root, builder, revision, propId }
local function decode(r)
    return { id = idOf(r.attachment_id), assetId = r.build_asset_id, parent = { kind = r.parent_kind, id = idOf(r.parent_id) },
        pos = { tonumber(r.pos_x), tonumber(r.pos_y), tonumber(r.pos_z) },
        rot = { tonumber(r.rot_roll), tonumber(r.rot_pitch), tonumber(r.rot_yaw) },
        root = idOf(r.root_machine_id), builder = idOf(r.builder_driver_id), revision = tonumber(r.revision) or 1 }
end
local function countOn(machineId)
    local n = 0
    for _, a in pairs(rows) do if a.root == machineId then n = n + 1 end end
    return n
end
local function countBy(builder)
    local n = 0
    for _, a in pairs(rows) do if a.builder == builder then n = n + 1 end end
    return n
end
local function totalLive()
    local n = 0
    for _, a in pairs(rows) do if a.propId then n = n + 1 end end
    return n
end

-- Prop ids are decimal strings; the attach card types the id as an integer. Try the string, then the number.
local function bind(id, binding)
    local okA, res, why = pcall(Open77.props.attach, id, binding)
    if not (okA and res) and tonumber(id) then okA, res, why = pcall(Open77.props.attach, tonumber(id), binding) end
    return okA and res, okA and why or res
end

local function unprop(a)
    if a and a.propId then pcall(Open77.props.remove, a.propId); a.propId = nil end
end

--- Draw one attachment on its Machine's current vehicle, at its composed transform.
local function draw(a)
    local m = machines[a.root]
    if not m then return false, "machine_not_out" end
    local item = B.CATALOGUE[a.assetId]
    if not item then return false, "unknown_asset" end
    local root, why = B.resolve(rows, a.id, set("buildMaxDepth", B.LIMITS.maxDepth))
    if not root then return false, why end
    local okV, v = pcall(Open77.vehicles.get, m.vid)
    if not (okV and type(v) == "table" and type(v.position) == "table") then return false, "vehicle_unreadable" end
    local binding = { parentType = "vehicle", parentId = tostring(m.vid), bone = "",
        offset = { x = root.pos[1], y = root.pos[2], z = root.pos[3] }, rotation = { x = root.rot[1], y = root.rot[2], z = root.rot[3] } }
    if a.propId then
        local okB, reason = bind(a.propId, binding)
        if okB then return true end
        log("re-bind %s failed (%s); minting again", a.id:sub(1, 8), tostring(reason))
        unprop(a)
    end
    local okC, id, reason = pcall(Open77.props.create, { model = item.model, position = v.position, bucket = v.bucket or 0,
        physics = "none", collision = false, visible = true, streamingRadius = 300 })
    if not (okC and id) then return false, "prop_refused:" .. tostring(okC and reason or id) end
    local okB, why2 = bind(id, binding)
    if not okB then
        pcall(Open77.props.remove, id)
        return false, "bind_refused:" .. tostring(why2)
    end
    a.propId = id
    return true
end

--- Draw an attachment and everything carried on it (a moved member moves its children).
local function drawTree(a)
    local okD, why = draw(a)
    if not okD then log("draw %s (%s) on ..%s: %s", a.id:sub(1, 8), a.assetId, tostring(a.root):sub(-6), tostring(why)) end
    for _, c in pairs(rows) do
        if c.parent.kind == "attachment" and c.parent.id == a.id then drawTree(c) end
    end
    return okD, why
end

local function loadMachine(machineId)
    local list = MySQL.query.await([[SELECT * FROM build_attachment WHERE server_id = ? AND root_machine_id = ? AND removed_at IS NULL]],
        { serverId(), machineId }) or {}
    for _, r in ipairs(list) do
        local a = decode(r)
        rows[a.id] = rows[a.id] or a
    end
    local n = 0
    for _, a in pairs(rows) do
        if a.root == machineId and a.parent.kind == "machine" then drawTree(a); n = n + 1 end
    end
    if #list > 0 then log("Machine ..%s out as vehicle %s: %d attachment(s) rebuilt", machineId:sub(-6), tostring(machines[machineId].vid), #list) end
    return n
end

AddEventHandler("ncm:vehicle:materialized", function(assetId, vehicleId, pid)
    local id = idOf(assetId)
    if not id or not vehicleId then return end
    local was = machines[id]
    if was and tostring(was.vid) == tostring(vehicleId) then return end
    for _, a in pairs(rows) do if a.root == id then unprop(a) end end
    machines[id] = { vid = vehicleId, pid = tonumber(pid) }
    CreateThread(function()
        local okL, err = pcall(loadMachine, id)
        if not okL then log("load ..%s FAILED: %s", id:sub(-6), tostring(err)) end
    end)
end)

AddEventHandler("ncm:vehicle:dematerialized", function(assetId)
    local id = idOf(assetId)
    if not id then return end
    machines[id] = nil
    local n = 0
    for k, a in pairs(rows) do
        if a.root == id then unprop(a); rows[k] = nil; n = n + 1 end
    end
    if n > 0 then log("Machine ..%s stored: %d attachment prop(s) removed (rows kept)", id:sub(-6), n) end
end)

-- ------------------------------------------------------------------------------------------------ requests
local REASONS = {
    unknown_asset = "That object is not in the Build catalogue.", bad_parent = "Attach it to a Machine or a member.",
    bad_transform = "That position is not a number.", too_far_from_parent = "Too far from what it is mounted on.",
    missing_parent = "What it was mounted on is gone.", parent_cannot_carry = "Only a bar or beam can carry other things.",
    cycle = "That would mount something on itself.", too_deep = "Too many things stacked on one another.",
    outside_platform_reach = "Too far from the car.", too_far_from_machine = "Too far from the car.",
    machine_full = "This Machine carries as much as it may.", player_limit = "You have built as much as you may.",
    server_limit = "The city has built as much as it may right now.", not_yours = "That is not your Machine.",
    machine_not_out = "Call the Machine first: it must be standing in the city.", no_driver = "No Driver file on this server.",
    disabled = "Build is switched off.", not_found = "That attachment is gone.", has_children = "Remove what is mounted on it first.",
}
local function result(pid, okR, op, text, extra)
    local r = { ok = okR == true, op = op, text = REASONS[text] or tostring(text or "") }
    for k, v in pairs(extra or {}) do r[k] = v end
    TriggerClientEvent("ncm:build.result", pid, r)
end

local function stateFor(pid)
    local d = driver(pid)
    local cat = {}
    for _, id in ipairs(B.ORDER) do
        local it = B.CATALOGUE[id]
        cat[#cat + 1] = { id = id, label = it.label, category = it.category, model = it.model, massKg = it.massKg,
            surface = it.surface, standIn = it.standIn or nil, carries = it.surface == "structural" or nil }
    end
    local mine, list = {}, {}
    if d then
        for mid, m in pairs(machines) do
            if ownerOf(mid) == d.ncmDriverId then
                local name = MySQL.scalar.await("SELECT vehicle_key FROM vehicle_asset WHERE asset_id = ?", { mid })
                mine[#mine + 1] = { machineId = mid, vehicleId = tostring(m.vid), name = tostring(name or "Machine") }
                for _, a in pairs(rows) do
                    if a.root == mid then
                        local root = B.resolve(rows, a.id)
                        list[#list + 1] = { id = a.id, assetId = a.assetId, label = (B.CATALOGUE[a.assetId] or {}).label,
                            parent = a.parent, pos = a.pos, rot = a.rot, machineId = mid, vehicleId = tostring(m.vid),
                            rootPos = root and root.pos, rootRot = root and root.rot, drawn = a.propId ~= nil, mine = a.builder == d.ncmDriverId }
                    end
                end
            end
        end
    end
    return { catalogue = cat, machines = mine, attachments = list, limits = limits() }
end
local function sendState(pid) TriggerClientEvent("ncm:build.state", pid, stateFor(pid)) end

local last = {}
local function allowed(pid)
    local t = GetGameTimer()
    if last[pid] and t - last[pid] < 300 then return false end
    last[pid] = t
    return true
end

RegisterNetEvent("ncm:build.request", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    CreateThread(function() sendState(pid) end)
end)

RegisterNetEvent("ncm:build.attach", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(req) ~= "table" or not allowed(pid) then return end
    CreateThread(function()
        if not set("buildEnabled", true) then return result(pid, false, "attach", "disabled") end
        local d = driver(pid)
        if not d then return result(pid, false, "attach", "no_driver") end
        local parent = type(req.parent) == "table" and { kind = tostring(req.parent.kind or ""), id = idOf(req.parent.id) } or {}
        local machineId = parent.kind == "machine" and parent.id or (rows[parent.id or ""] and rows[parent.id].root)
        if not machineId then return result(pid, false, "attach", "missing_parent") end
        if not machines[machineId] then return result(pid, false, "attach", "machine_not_out") end
        if ownerOf(machineId) ~= d.ncmDriverId then return result(pid, false, "attach", "not_yours") end
        local okV, plan = B.validate({ assetId = tostring(req.assetId or ""), parent = parent, pos = req.pos, rot = req.rot },
            { byId = rows, onMachine = countOn(machineId), byPlayer = countBy(d.ncmDriverId), total = totalLive(), limits = limits() })
        if not okV then return result(pid, false, "attach", plan) end
        local t = now()
        local id = NcmCore.get("vocabulary.ids").uuid4(function() return math.random() end)
        local a = { id = id, assetId = tostring(req.assetId), parent = parent, pos = plan.pos, rot = plan.rot, root = machineId,
            builder = d.ncmDriverId, revision = 1 }
        local okI = pcall(MySQL.insert.await, [[INSERT INTO build_attachment (attachment_id, server_id, build_asset_id, parent_kind,
            parent_id, root_machine_id, pos_x, pos_y, pos_z, rot_roll, rot_pitch, rot_yaw, builder_driver_id, provenance, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'player_build', ?, ?)]],
            { id, serverId(), a.assetId, parent.kind, parent.id, machineId, a.pos[1], a.pos[2], a.pos[3], a.rot[1], a.rot[2], a.rot[3],
              d.ncmDriverId, t, t })
        if not okI then return result(pid, false, "attach", "could not save") end
        rows[id] = a
        local okD, why = draw(a)
        log("ATTACH %s %s on ..%s by %s at (%.2f, %.2f, %.2f) rot (%.0f, %.0f, %.0f) parent %s: %s", id:sub(1, 8), a.assetId,
            machineId:sub(-6), d.ncmDriverId:sub(1, 8), a.pos[1], a.pos[2], a.pos[3], a.rot[1], a.rot[2], a.rot[3], parent.kind,
            okD and "drawn" or ("NOT DRAWN " .. tostring(why)))
        result(pid, true, "attach", okD and "Attached." or ("Saved, but not drawn: " .. tostring(why)), { attachmentId = id })
        sendState(pid)
    end)
end)

RegisterNetEvent("ncm:build.edit", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(req) ~= "table" or not allowed(pid) then return end
    CreateThread(function()
        local d = driver(pid)
        if not d then return result(pid, false, "edit", "no_driver") end
        local a = rows[idOf(req.attachmentId) or ""]
        if not a then return result(pid, false, "edit", "not_found") end
        if ownerOf(a.root) ~= d.ncmDriverId then return result(pid, false, "edit", "not_yours") end
        local view = {}
        for k, v in pairs(rows) do if k ~= a.id then view[k] = v end end
        local okV, plan = B.validate({ assetId = a.assetId, parent = a.parent, pos = req.pos, rot = req.rot },
            { byId = view, onMachine = countOn(a.root) - 1, byPlayer = 0, total = 0, limits = limits() })
        if not okV then return result(pid, false, "edit", plan) end
        local okU = pcall(MySQL.update.await, [[UPDATE build_attachment SET pos_x = ?, pos_y = ?, pos_z = ?, rot_roll = ?, rot_pitch = ?,
            rot_yaw = ?, updated_at = ?, revision = revision + 1 WHERE attachment_id = ? AND removed_at IS NULL]],
            { plan.pos[1], plan.pos[2], plan.pos[3], plan.rot[1], plan.rot[2], plan.rot[3], now(), a.id })
        if not okU then return result(pid, false, "edit", "could not save") end
        a.pos, a.rot, a.revision = plan.pos, plan.rot, a.revision + 1
        drawTree(a)
        log("EDIT %s to (%.2f, %.2f, %.2f) rot (%.0f, %.0f, %.0f) rev %d", a.id:sub(1, 8), a.pos[1], a.pos[2], a.pos[3], a.rot[1], a.rot[2], a.rot[3], a.revision)
        result(pid, true, "edit", "Moved.", { attachmentId = a.id })
        sendState(pid)
    end)
end)

RegisterNetEvent("ncm:build.remove", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(req) ~= "table" or not allowed(pid) then return end
    CreateThread(function()
        local d = driver(pid)
        if not d then return result(pid, false, "remove", "no_driver") end
        local id = idOf(req.attachmentId) or ""
        local a = rows[id]
        local root = a and a.root or idOf(MySQL.scalar.await("SELECT root_machine_id FROM build_attachment WHERE attachment_id = ? AND removed_at IS NULL", { id }))
        if not root then return result(pid, false, "remove", "not_found") end
        if ownerOf(root) ~= d.ncmDriverId then return result(pid, false, "remove", "not_yours") end
        for _, c in pairs(rows) do
            if c.parent.kind == "attachment" and c.parent.id == id then return result(pid, false, "remove", "has_children") end
        end
        local okU = pcall(MySQL.update.await, "UPDATE build_attachment SET removed_at = ?, removed_by = ? WHERE attachment_id = ? AND removed_at IS NULL",
            { now(), d.ncmDriverId, id })
        if not okU then return result(pid, false, "remove", "could not save") end
        if a then unprop(a); rows[id] = nil end
        log("REMOVE %s from ..%s by %s", id:sub(1, 8), tostring(root):sub(-6), d.ncmDriverId:sub(1, 8))
        result(pid, true, "remove", "Removed.")
        sendState(pid)
    end)
end)

-- Console: ncm.build -- what is out, what is drawn
RegisterCommand("ncm.build", function(src)
    if (tonumber(src) or 0) ~= 0 then return end
    local n, drawn = 0, 0
    for _, a in pairs(rows) do n = n + 1; if a.propId then drawn = drawn + 1 end end
    local out = 0
    for _ in pairs(machines) do out = out + 1 end
    log("%d Machine(s) out, %d attachment(s) loaded, %d drawn", out, n, drawn)
end, false)

AddEventHandler("onResourceStop", function(name)
    if name ~= GetCurrentResourceName() then return end
    for _, a in pairs(rows) do unprop(a) end
end)

CreateThread(function()
    while not (MySQL and MySQL.isReady and MySQL.isReady()) do Wait(500) end
    Wait(1000)
    -- the Machines already out when this resource (re)started: ncm_world replays its registry on this request
    TriggerEvent("ncm:trade:requestActiveSnapshot")
    log("ready (enabled=%s; per Machine %d, per player %d, total %d, depth %d, reach %.1f m)", tostring(set("buildEnabled", true)),
        limits().perParent, limits().perPlayer, limits().totalActive, limits().maxDepth, limits().maxReachM)
end)
