-- ncm_world / server / engineering -- L324: the first engineering loop, server side.
--
--   acquire a component asset -> inspect it -> check it against a mount on YOUR Machine -> install it with a facing
--   (a new machine_configuration revision, like every other fit) -> bind a control to one of its commands -> drive.
--
-- The truth lives where every other Part's truth lives: component_asset (custody, serial), machine_configuration +
-- items (+ install_json, the facing), component_operation (what changed, idempotent), machine_control_binding. The
-- physics is core `engineering.installation`; the client turns its output into a world-space force the Carrier
-- applies to the bound body. This file never decides what a component is FOR.
--
-- Fuel: an installed device burns the Machine's own tank (NcmFuel.draw). The client reports what it spent once a
-- second; the server clamps the claim to what the installed devices could physically have burned in that time.
--
-- Acquisition is the one temporary shortcut: `/ncm.eng.fabricate` mints a component asset on DEVELOPMENT only (no
-- market lists these designs yet). From the asset onward nothing is special-cased.
NcmEngineering = {}

local Install = NcmCore.get("engineering.installation")
local Controls = NcmCore.get("engineering.controls")
local Sys = NcmCore.get("engineering.systems")
local Json = NcmCore.get("vocabulary.json")
local ids = NcmCore.get("vocabulary.ids")
local hostRng = function() return math.random() end

local function log(fmt, ...) print(("[ncm_world/engineering] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function enc(v) local ok, x = pcall(Json.encode, v); return ok and x or "{}" end
local function dec(v) if type(v) == "table" then return v end local ok, x = pcall(Json.decode, tostring(v or "")); return ok and x or nil end
local function identity()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    if ok and type(id) == "table" then return id.serverId or "ncm-dev", tostring(id.environment or "unknown") end
    return "ncm-dev", "unknown"
end
local function serverId() local s = identity(); return s end
local function isDev() local _, env = identity(); return env == "development" end

local function chat(pid, fmt, ...) pcall(Open77.chat.send, pid, "[ENG] " .. fmt:format(...)) end
local function toast(pid, ok, title, msg)
    pcall(Open77.notifications.send, pid, { type = ok and "success" or "error", title = title, message = msg, icon = "NCM", durationMs = 7000 })
end
local function short(id) return tostring(id or "-"):sub(-6) end
-- KB-358: CHAR(36) columns come back as GUID values, not strings -- compare ids as lowercase text
local function sameId(a, b) return a ~= nil and b ~= nil and tostring(a):lower() == tostring(b):lower() end


local subscribed = {}   -- pid -> machine asset the driver's client asked about (and is bound to)
local lastMachine = {}  -- pid -> the Machine the bench works on (last driven, or chosen)
local cache = {}        -- machine asset -> { devices, items, vehicleKey, at }

-- ------------------------------------------------------------------------------------------------ designs
--- Every engineering design gets its component_design row (the FK every asset needs). Empty positions and fitment:
--- these are not factory-interface parts, so the Parts inventory's fitter can never place one.
local function seedDesigns()
    for _, d in ipairs(Install.DESIGNS) do
        MySQL.insert.await([[INSERT IGNORE INTO component_design
            (design_id,lineage_id,revision,manufacturer_key,display_manufacturer,code,subtitle,family,tier,effect,price,
             fidelity,distribution,origin_kind,positions_json,fitment_json,spec_json,created_at)
            VALUES (?,?,?,?,?,?,?,?,'engineering',1.0,?,'physical','engineering','design','[]',?,?,?)]],
            { d.designId, d.lineageId, d.revision, d.makerKey, d.manufacturer, d.code, d.subtitle, d.family, d.price,
              enc({ standard = d.interface }), enc(d), now() })
        MySQL.update.await("UPDATE component_design SET spec_json=? WHERE design_id=? AND spec_json IS NULL", { enc(d), d.designId })
    end
    log("engineering designs ready: %d (%s)", #Install.DESIGNS, (function()
        local c = {} for _, d in ipairs(Install.DESIGNS) do c[#c + 1] = d.code end return table.concat(c, ", ") end)())
end
AddEventHandler("ncm:rnd:design", function(spec)
    -- L361: the Workshop's prototypes and player designs register the same way as R&D's
    local PHYSICAL = { rnd_physical = true, prototype = true, player_design = true }
    if type(spec) ~= "table" or not PHYSICAL[spec.origin] then return end
    local registered, why = Install.register(spec)
    if not registered then log("physical R&D Design refused: %s", tostring(why)) end
end)

-- ------------------------------------------------------------------------------------------------ reads
local function driverOf(pid)
    local p = NcmIdentity and NcmIdentity.get(pid)
    return p and p.ncmDriverId or nil
end

local function machineRow(machineId)
    return MySQL.single.await("SELECT asset_id,vehicle_key,record,ncm_driver_id FROM vehicle_asset WHERE asset_id=? AND server_id=?", { machineId, serverId() })
end

local function currentConfig(machineId)
    local head = MySQL.single.await([[SELECT c.configuration_id,c.revision FROM machine_configuration_current x
        JOIN machine_configuration c ON c.configuration_id=x.configuration_id WHERE x.machine_asset_id=?]], { machineId })
    if not head then return nil, "this Machine has no configuration record" end
    head.items = MySQL.query.await([[SELECT i.interface_id,i.component_asset_id,i.install_json,a.design_id,d.family
        FROM machine_configuration_item i JOIN component_asset a ON a.asset_id=i.component_asset_id
        JOIN component_design d ON d.design_id=a.design_id WHERE i.configuration_id=? ORDER BY i.interface_id]], { head.configuration_id }) or {}
    return head
end

--- The Machine's installed add-ons as core items, and the devices they resolve to.
local function resolveMachine(machineId)
    local c = cache[machineId]
    if c then return c end
    local m = machineRow(machineId)
    if not m then return nil, "unknown Machine" end
    local head, why = currentConfig(machineId)
    if not head then return nil, why end
    local items = {}
    for _, i in ipairs(head.items) do
        if Install.isAddOnFamily(i.family) then
            local inst = dec(i.install_json) or {}
            items[#items + 1] = { componentId = i.component_asset_id, designId = i.design_id, mountId = i.interface_id, facing = inst.facing }
        end
    end
    local devices, refused = Install.resolve(items, m.vehicle_key)
    c = { devices = devices, refused = refused, items = items, vehicleKey = m.vehicle_key, record = m.record, head = head, owner = m.ncm_driver_id }
    cache[machineId] = c
    return c
end

local function bindingsOf(machineId)
    local rows = MySQL.query.await([[SELECT control_key,gesture,component_asset_id,command FROM machine_control_binding
        WHERE machine_asset_id=? ORDER BY control_key,gesture]], { machineId }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = { control = r.control_key, gesture = r.gesture, componentId = r.component_asset_id, command = r.command } end
    return out
end

-- KB-363: every add-on family core knows (was a literal list that missed `attitude`, so an AC-6 could never be fitted)
local FAMILY_SQL = (function()
    local t = {} for f in pairs(Install.FAMILIES) do t[#t + 1] = "'" .. f:gsub("[^%w_]", "") .. "'" end
    table.sort(t) return table.concat(t, ",")
end)()

--- The driver's own engineering components (storage and installed), oldest first: the list the bench numbers.
local function componentsOf(driverId)
    return MySQL.query.await([[SELECT a.asset_id,a.design_id,a.location_kind,a.machine_asset_id,a.design_ordinal,a.acquired_via,d.code,d.family
        FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
        WHERE a.server_id=? AND a.ncm_driver_id=? AND d.family IN (]] .. FAMILY_SQL .. [[) AND a.lifecycle='active'
        ORDER BY a.created_at,a.asset_id]], { serverId(), driverId }) or {}
end

local function serial(r) return ("%s #%s"):format(tostring(r.code), tostring(r.design_ordinal or "?")) end

--- `ref` = the bench number (1, 2 ...), or the tail/head of an asset id.
local function findComponent(driverId, ref)
    local list = componentsOf(driverId)
    local n = tonumber(ref)
    if n and list[n] then return list[n] end
    ref = tostring(ref or ""):lower()
    if #ref >= 4 then
        for _, r in ipairs(list) do
            local id = tostring(r.asset_id):lower()
            if id:sub(1, #ref) == ref or id:sub(-#ref) == ref then return r end
        end
    end
    return nil
end

local function machinesOf(driverId)
    return MySQL.query.await([[SELECT asset_id,vehicle_key,record FROM vehicle_asset WHERE server_id=? AND ncm_driver_id=?
        ORDER BY acquired_at,asset_id]], { serverId(), driverId }) or {}
end

--- The Machine the bench works on: chosen, else the one this driver last drove, else their only one.
local function benchMachine(pid, driverId)
    local id = lastMachine[pid]
    if id then
        local m = machineRow(id)
        if m and sameId(m.ncm_driver_id, driverId) then return id end
    end
    local list = machinesOf(driverId)
    if #list == 1 then lastMachine[pid] = list[1].asset_id; return list[1].asset_id end
    return nil
end

-- ------------------------------------------------------------------------------------------------ tank fill (L334)
-- A tank PART's own propellant (schema 069). No row = full (a fresh tank); the row is created on first read.
local function tankFill(assetId, design)
    -- doc 58: an experimental drive's charge store is kept the same way (in charge units, not kg)
    local perf = design and design.perf or {}
    local cap = tonumber(perf.capacityKg) or (type(perf.store) == "table" and tonumber(perf.store.capacity)) or 0
    local kg = MySQL.scalar.await("SELECT propellant_kg FROM component_state WHERE asset_id=?", { assetId })
    if kg == nil then
        MySQL.insert.await("INSERT IGNORE INTO component_state (asset_id, propellant_kg, updated_at) VALUES (?,?,?)", { assetId, cap, now() })
        return cap
    end
    return math.max(0, math.min(cap, tonumber(kg) or 0))
end

--- Take `kg` of a propellant from a Machine's tank parts (largest first); returns what was taken and what is left.
local function drawTanks(machineId, propellant, kg)
    local c = resolveMachine(machineId)
    if not c or kg <= 0 then return 0, nil end
    local taken, left = 0, 0
    for _, d in ipairs(c.devices) do
        if d.kind == "propellant_tank" and (d.perf.propellant or "fuel") == propellant then
            local have = tankFill(d.componentId, Install.design(d.designId))
            local take = math.min(have, kg - taken)
            if take > 0 then
                MySQL.update.await("UPDATE component_state SET propellant_kg=?, updated_at=? WHERE asset_id=?", { have - take, now(), d.componentId })
                taken = taken + take
            end
            left = left + (have - take)
        end
    end
    return taken, left
end

-- ------------------------------------------------------------------------------------------------ delivery
local function payload(machineId)
    local c, why = resolveMachine(machineId)
    if not c then return nil, why end
    local ml, cap = nil, nil
    if NcmFuel and NcmFuel.ensure then ml, cap = NcmFuel.ensure(machineId) end
    -- L334: each tank part's current fill rides with its item (the core resolves it into the device)
    local items = {}
    for i, it in ipairs(c.items) do
        local d = Install.design(it.designId)
        local copy = {}
        for k, v in pairs(it) do copy[k] = v end
        if d and d.perf and (d.perf.kind == "propellant_tank" or d.perf.store) then copy.fillKg = tankFill(it.componentId, d) end
        items[i] = copy
    end
    local specs, seen = {}, {}
    for _, it in ipairs(items) do
        if not seen[it.designId] then
            local d = Install.design(it.designId)
            if d then specs[#specs + 1] = d; seen[it.designId] = true end
        end
    end
    return { v = 2, assetId = machineId, vehicleKey = c.vehicleKey, items = items, specs = specs, refused = c.refused,
        bindings = bindingsOf(machineId), addedMassKg = Install.addedMassKg(c.devices), fuel = { ml = ml, capacityMl = cap } }
end

local function push(pid, machineId)
    local p = payload(machineId)
    if p then
        TriggerClientEvent("ncm:engineering", pid, p)
        log("player=%d machine=..%s delivered: %d device(s), %d binding(s), +%.0f kg", pid, short(machineId), #p.items, #p.bindings, p.addedMassKg)
    end
end

--- Called by NcmComponentInstall.apply after ANY configuration change (a factory part fitted, an add-on mounted).
function NcmEngineering.changed(machineId, why)
    cache[machineId] = nil
    for pid, aid in pairs(subscribed) do if aid == machineId then push(pid, machineId) end end
end

--- The mass the Machine's mounted add-ons add (kg; 0 when it has none or no configuration). L336: the passport's loaded mass.
function NcmEngineering.addedMassKg(machineId)
    local c = resolveMachine(machineId)
    return c and Install.addedMassKg(c.devices) or 0
end

local function boundTo(pid, machineId)
    if not (NcmVehicleAccess and NcmVehicleAccess.bindingForAuthority) then return nil end
    local b = NcmVehicleAccess.bindingForAuthority(pid)
    if b and b.assetId == machineId then return b end
    return nil
end

RegisterNetEvent("ncm:engineering.request", function(machineId)
    local pid = tonumber(source) or 0
    machineId = tostring(machineId or "")
    CreateThread(function()
        if not boundTo(pid, machineId) then
            -- the client saw a binding the server does not hold (a moment after a seat change): say nothing
            return
        end
        subscribed[pid], lastMachine[pid] = machineId, machineId
        push(pid, machineId)
    end)
end)

AddEventHandler("playerDropped", function() local pid = tonumber(source) or 0; subscribed[pid] = nil end)

-- ------------------------------------------------------------------------------------------------ fuel
--- The client's once-a-second account of what its devices burned, plus telemetry. Clamped to physics.
RegisterNetEvent("ncm:engineering.burn", function(r)
    local pid = tonumber(source) or 0
    if type(r) ~= "table" then return end
    local machineId = tostring(r.assetId or "")
    CreateThread(function()
        local b = boundTo(pid, machineId)
        if not b then return end
        local c = resolveMachine(machineId)
        if not c then return end
        local dtS = math.max(0, math.min(5, tonumber(r.dtS) or 0))
        local maxKg, maxFusion = 0, 0
        for _, d in ipairs(c.devices) do
            -- L334: a part that burns something other than the car's fuel is accounted to its own tank
            if d.kind == "reaction_engine" and (d.perf.propellant or "fuel") ~= "fuel" then maxFusion = maxFusion + Sys.massFlow(d.perf) * dtS
            elseif d.kind == "reaction_engine" or d.kind == "jet" then maxKg = maxKg + Sys.massFlow(d.perf) * dtS   -- an AV's lift fans burn fuel too
            elseif d.kind == "pulse_reaction" then
                local per = d.perf.retrigger and 0.05 or ((d.perf.pulseS or 0.2) + (d.perf.rechargeS or 0))   -- a retriggered hop can fire on every press
                maxKg = maxKg + Sys.pulseMass(d.perf) * (math.floor(dtS / math.max(0.05, per)) + 1)
            end
        end
        local claimed = math.max(0, tonumber(r.kg) or 0)
        local kg = math.min(claimed, maxKg * 1.05)
        local ml = kg / Install.FUEL_KG_PER_L * 1000
        local fusionKg = math.min(math.max(0, tonumber(r.fusionKg) or 0), maxFusion * 1.05)
        if fusionKg > 0 then
            local took, leftF = drawTanks(machineId, "fusion", fusionKg)
            log("FUSION player=%d machine=..%s burned %.4f kg (claimed %.4f, cap %.4f) | tanks left %.2f kg", pid, short(machineId),
                took, tonumber(r.fusionKg) or 0, maxFusion * 1.05, leftF or 0)
        end
        local left, cap = nil, nil
        if ml > 0 and NcmFuel and NcmFuel.draw then left, cap = NcmFuel.draw(machineId, ml, pid, b.vehicleId) end
        local t = type(r.t) == "table" and r.t or {}
        local off = NcmSnowglobe and NcmSnowglobe.offset and NcmSnowglobe.offset(b.vehicleId) or 0
        -- KB-445: already formatted -- through log() a '%' in the device text (Deep's "ZTC-FD1 6%") was formatted twice and threw
        print("[ncm_world/engineering] " .. ("TELEMETRY player=%d machine=..%s | %s | F world (%.0f, %.0f, %.0f) N |F| %.0f | fwd (%.2f, %.2f, %.2f) up (%.2f, %.2f, %.2f) | "
            .. "speed %.1f m/s | z %.0f (+%.0f snowglobe = %.0f) | burned %.3f kg = %.0f ml%s (claimed %.3f, cap %.3f) | fuel %s/%s ml%s | loss: %s"):format(
            pid, short(machineId), tostring(t.devices or "-"),
            tonumber(t.fx) or 0, tonumber(t.fy) or 0, tonumber(t.fz) or 0, tonumber(t.f) or 0,
            tonumber(t.fwx) or 0, tonumber(t.fwy) or 0, tonumber(t.fwz) or 0, tonumber(t.upx) or 0, tonumber(t.upy) or 0, tonumber(t.upz) or 0,
            tonumber(t.speed) or 0, tonumber(t.z) or 0, off, (tonumber(t.z) or 0) + off,
            kg, ml, (tonumber(r.pulses) or 0) > 0 and (" in " .. tostring(r.pulses) .. " discharge(s)") or "", claimed, maxKg * 1.05,
            tostring(left or "?"), tostring(cap or "?"), t.hot and " | HOT" or "", tostring(t.loss or "torque from off-centre mounts not applied (force at CoM)")))
    end)
end)

-- ------------------------------------------------------------------------------------------------ writes
local function parkCheck(machineId)
    if NcmComponentInstall and NcmComponentInstall.state then
        local park = NcmComponentInstall.state(machineId)
        if not park.eligible then return false, park.reason .. " -- park it and get out first" end
    end
    if NcmOdometer and NcmOdometer.flushAsset then
        local settled, why = NcmOdometer.flushAsset(machineId, "before engineering change", true)
        if settled == false then return false, why or "exposure_checkpoint_failed" end
    end
    return true
end

local function newRevision(driverId, machineId, old, items, componentId, kind, componentSql)
    local cfg, op, t = ids.uuid4(hostRng), ids.uuid4(hostRng), now()
    local tx = { { query = [[INSERT INTO machine_configuration
        (configuration_id,machine_asset_id,revision,operation_id,created_at,created_by_driver_id)
        SELECT ?,?,?,?,?,? FROM DUAL WHERE
        EXISTS(SELECT 1 FROM vehicle_asset WHERE asset_id=? AND ncm_driver_id=?) AND
        EXISTS(SELECT 1 FROM machine_configuration_current WHERE machine_asset_id=? AND configuration_id=?)]],
        values = { cfg, machineId, (tonumber(old.revision) or 0) + 1, op, t, driverId, machineId, driverId, machineId, old.configuration_id } } }
    for _, i in ipairs(items) do
        -- KB-347: a factory item's install_json is nil, and a trailing nil drops out of a Lua list (3 values for 4
        -- placeholders: every install failed). NULL is spelled out in the statement instead.
        if i.install then
            tx[#tx + 1] = { query = "INSERT INTO machine_configuration_item (configuration_id,interface_id,component_asset_id,install_json) VALUES (?,?,?,?)",
                values = { cfg, i.interfaceId, i.assetId, i.install } }
        else
            tx[#tx + 1] = { query = "INSERT INTO machine_configuration_item (configuration_id,interface_id,component_asset_id,install_json) VALUES (?,?,?,NULL)",
                values = { cfg, i.interfaceId, i.assetId } }
        end
    end
    tx[#tx + 1] = { query = [[INSERT INTO component_operation
        (operation_id,idem_key,server_id,ncm_driver_id,machine_asset_id,component_asset_id,old_configuration_id,new_configuration_id,kind,occurred_at)
        VALUES (?,?,?,?,?,?,?,?,?,?)]], values = { op, "eng:" .. kind .. ":" .. op, serverId(), driverId, machineId, componentId, old.configuration_id, cfg, kind, t } }
    tx[#tx + 1] = { query = "UPDATE machine_configuration_current SET configuration_id=? WHERE machine_asset_id=? AND configuration_id=?",
        values = { cfg, machineId, old.configuration_id } }
    for _, q in ipairs(componentSql) do tx[#tx + 1] = q end
    local ok, err = MySQL.transaction.await(tx)
    if not ok then return nil, "transaction: " .. tostring(err) end
    local held = MySQL.scalar.await("SELECT configuration_id FROM machine_configuration_current WHERE machine_asset_id=?", { machineId })
    if held ~= cfg then return nil, "configuration not committed (changed underneath)" end
    return cfg, (tonumber(old.revision) or 0) + 1
end

local function carried(old, skipInterface)
    local out = {}
    for _, i in ipairs(old.items) do
        if i.interface_id ~= skipInterface then out[#out + 1] = { interfaceId = i.interface_id, assetId = i.component_asset_id, install = i.install_json } end
    end
    return out
end

function NcmEngineering.install(pid, ref, mountId, facing, onMachine)
    local driverId = driverOf(pid)
    if not driverId then return nil, "no driver profile" end
    local machineId = benchMachine(pid, driverId)
    if onMachine then   -- the pad names the Machine (panel Parts)
        local row = machineRow(onMachine)
        if not row or not sameId(row.ncm_driver_id, driverId) then return nil, "that Machine is not yours" end
        machineId = onMachine
        lastMachine[pid] = onMachine
    end
    if not machineId then return nil, "which Machine? drive it once, or /ncm.eng.machine <n>" end
    local part = findComponent(driverId, ref)
    if not part then return nil, "no component " .. tostring(ref) .. " (see /ncm.eng)" end
    if part.location_kind ~= "storage" then return nil, serial(part) .. " is not in storage (remove it first)" end
    local m = machineRow(machineId)
    local design = Install.design(part.design_id)
    local verdict = Install.check(design, m and m.vehicle_key, mountId, facing)
    if not verdict.ok then return nil, verdict.reason end
    -- stacked gearboxes stack on a manual (owner, 2026-10-08: "if car has manual gearbox it is manual. if car has auto
    -- it is auto"): NCM Gearbox drives the boxes, and it drives only a manual
    if design and design.perf and Install.isDriveline(design.perf.kind) then
        local kind = MySQL.scalar.await("SELECT gearbox_kind FROM vehicle_asset WHERE asset_id=?", { machineId })
        if tostring(kind or "") ~= "manual" then return nil, "a driveline box stacks on a manual gearbox; this Machine is an automatic" end
    end
    local okPark, whyPark = parkCheck(machineId)
    if not okPark then return nil, whyPark end
    local old, why = currentConfig(machineId)
    if not old then return nil, why end
    local items = carried(old, mountId)
    local displaced = nil
    for _, i in ipairs(old.items) do if i.interface_id == mountId then displaced = i.component_asset_id end end
    items[#items + 1] = { interfaceId = mountId, assetId = part.asset_id, install = enc({ facing = facing }) }
    local sql = { { query = "UPDATE component_asset SET location_kind='installed',machine_asset_id=? WHERE asset_id=? AND ncm_driver_id=? AND location_kind='storage'",
        values = { machineId, part.asset_id, driverId } } }
    if displaced then
        sql[#sql + 1] = { query = "UPDATE component_asset SET location_kind='storage',machine_asset_id=NULL WHERE asset_id=? AND machine_asset_id=?", values = { displaced, machineId } }
    end
    local cfg, rev = newRevision(driverId, machineId, old, items, part.asset_id, "mount", sql)
    if not cfg then return nil, rev end
    log("MOUNT player=%d machine=..%s %s (%s) on %s facing %s -> thrust axis (%g, %g, %g) | configuration rev %d%s", pid, short(machineId),
        serial(part), part.asset_id, mountId, facing, verdict.axis[1], verdict.axis[2], verdict.axis[3], rev, displaced and (" | displaced .." .. short(displaced)) or "")
    NcmComponentInstall.apply(machineId, "engineering mount")
    if pid > 0 then TriggerEvent("ncm:component.changed", pid, machineId) end
    if verdict.mount.driveline then
        return true, ("%s in the %s. %s Configuration revision %d."):format(serial(part), verdict.mount.label,
            verdict.mount.driveline == "side" and "Bind a control to its ENGAGE in Parts to drive through it." or "It is part of the car's gear ladder now.", rev)
    end
    return true, ("%s on the %s, facing %s: it pushes the Machine (%g, %g, %g) in its own frame. Configuration revision %d."):format(
        serial(part), verdict.mount.label, facing, verdict.axis[1], verdict.axis[2], verdict.axis[3], rev)
end

function NcmEngineering.remove(pid, ref)
    local driverId = driverOf(pid)
    if not driverId then return nil, "no driver profile" end
    local part = findComponent(driverId, ref)
    if not part then return nil, "no component " .. tostring(ref) end
    if part.location_kind ~= "installed" or not part.machine_asset_id then return nil, serial(part) .. " is not installed" end
    local machineId = part.machine_asset_id
    local okPark, whyPark = parkCheck(machineId)
    if not okPark then return nil, whyPark end
    local old, why = currentConfig(machineId)
    if not old then return nil, why end
    local at = nil
    for _, i in ipairs(old.items) do if i.component_asset_id == part.asset_id then at = i.interface_id end end
    if not at or not Install.isMount(at) then return nil, serial(part) .. " is not on a mount of the current configuration" end
    local sql = { { query = "UPDATE component_asset SET location_kind='storage',machine_asset_id=NULL WHERE asset_id=? AND machine_asset_id=? AND ncm_driver_id=?",
        values = { part.asset_id, machineId, driverId } } }
    local cfg, rev = newRevision(driverId, machineId, old, carried(old, at), part.asset_id, "unmount", sql)
    if not cfg then return nil, rev end
    log("UNMOUNT player=%d machine=..%s %s from %s | configuration rev %d", pid, short(machineId), serial(part), at, rev)
    NcmComponentInstall.apply(machineId, "engineering unmount")
    if pid > 0 then TriggerEvent("ncm:component.changed", pid, machineId) end
    return true, ("%s is off the Machine and back in storage. Bindings to it are kept but inert until it is installed again. Revision %d."):format(serial(part), rev)
end

function NcmEngineering.bind(pid, control, gesture, ref, command)
    local driverId = driverOf(pid)
    if not driverId then return nil, "no driver profile" end
    local ctl, why = Controls.normalize(control)
    if not ctl then return nil, why end
    local part = findComponent(driverId, ref)
    if not part then return nil, "no component " .. tostring(ref) end
    if part.location_kind ~= "installed" then return nil, serial(part) .. " is not installed on a Machine" end
    local machineId = part.machine_asset_id
    local c = resolveMachine(machineId)
    local device
    for _, d in ipairs(c and c.devices or {}) do if d.componentId == part.asset_id then device = d end end
    local binding = { control = ctl, gesture = tostring(gesture or ""):lower(), componentId = part.asset_id, command = tostring(command or ""):lower() }
    local ok, whyBind = Controls.check(binding, device)
    if not ok then return nil, whyBind end
    -- schema 066: a control may command several components (they move together); binding one again updates its command
    MySQL.query.await([[INSERT INTO machine_control_binding (machine_asset_id,control_key,gesture,component_asset_id,command,created_by_driver_id,updated_at)
        VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE command=VALUES(command),
        created_by_driver_id=VALUES(created_by_driver_id),updated_at=VALUES(updated_at)]],
        { machineId, ctl, binding.gesture, part.asset_id, binding.command, driverId, now() })
    log("BIND player=%d machine=..%s %s %s -> %s.%s", pid, short(machineId), ctl, binding.gesture, serial(part), binding.command)
    NcmEngineering.changed(machineId, "binding")
    local n = MySQL.scalar.await("SELECT COUNT(*) FROM machine_control_binding WHERE machine_asset_id=? AND control_key=? AND gesture=?", { machineId, ctl, binding.gesture }) or 1
    return true, ("%s %s now commands %s: %s%s."):format(ctl, binding.gesture, serial(part), binding.command,
        (tonumber(n) or 1) > 1 and (" (together with %d other component(s) on this control)"):format((tonumber(n) or 1) - 1) or "")
end

function NcmEngineering.unbind(pid, control, gesture, ref)
    local driverId = driverOf(pid)
    if not driverId then return nil, "no driver profile" end
    local machineId = benchMachine(pid, driverId)
    if not machineId then return nil, "which Machine? /ncm.eng.machine <n>" end
    local ctl, why = Controls.normalize(control)
    if not ctl then return nil, why end
    if ref then
        local part = findComponent(driverId, ref)
        if not part then return nil, "no component " .. tostring(ref) end
        MySQL.query.await("DELETE FROM machine_control_binding WHERE machine_asset_id=? AND control_key=? AND gesture=? AND component_asset_id=?",
            { machineId, ctl, tostring(gesture or ""):lower(), part.asset_id })
        NcmEngineering.changed(machineId, "unbind")
        return true, ("%s %s no longer commands %s."):format(ctl, tostring(gesture), serial(part))
    end
    MySQL.query.await("DELETE FROM machine_control_binding WHERE machine_asset_id=? AND control_key=? AND gesture=?", { machineId, ctl, tostring(gesture or ""):lower() })
    NcmEngineering.changed(machineId, "unbind")
    return true, ("%s %s is unbound (every component on it)."):format(ctl, tostring(gesture))
end

function NcmEngineering.fabricate(pid, which)
    if not isDev() then return nil, "fabrication is a development shortcut; on Online components come from markets" end
    local driverId = driverOf(pid)
    if not driverId then return nil, "no driver profile" end
    local key = tostring(which or ""):lower()
    local d
    for _, x in ipairs(Install.DESIGNS) do
        if x.code:lower():find(key, 1, true) or x.designId:lower():find(key, 1, true) then d = x end
    end
    if not d or key == "" then return nil, "fabricate what? rp16 (Reaction Propulsor) or ia10 (Impulse Actuator)" end
    local asset, t = ids.uuid4(hostRng), now()
    local ok, err = MySQL.transaction.await({
        { query = [[INSERT INTO component_asset (asset_id,server_id,design_id,run_id,ncm_driver_id,manufacturer_key,location_kind,machine_asset_id,
            global_ordinal,maker_ordinal,design_ordinal,factory_original,acquired_via,acquired_at,exposure_m,created_at,lifecycle)
            SELECT ?,?,?,NULL,?,?,'storage',NULL,NULL,NULL,COALESCE(MAX(design_ordinal),0)+1,0,'dev_fabricate',?,0,?,'active'
            FROM component_asset WHERE server_id=? AND design_id=?]],
          values = { asset, serverId(), d.designId, driverId, d.makerKey, t, t, serverId(), d.designId } },
        { query = [[INSERT INTO component_asset_transfer (transfer_id,idem_key,server_id,asset_id,from_driver_id,to_driver_id,kind,market_id,amount,occurred_at)
            VALUES (?,?,?,?,NULL,?,'fabricate',NULL,NULL,?)]], values = { ids.uuid4(hostRng), "eng_fab:" .. asset, serverId(), asset, driverId, t } },
    })
    if not ok then return nil, "fabrication failed: " .. tostring(err) end
    if d.perf and d.perf.kind == "propellant_tank" then   -- L334: a fabricated tank comes full
        MySQL.insert.await("INSERT IGNORE INTO component_state (asset_id, propellant_kg, updated_at) VALUES (?,?,?)", { asset, d.perf.capacityKg or 0, t })
    end
    local n = MySQL.scalar.await("SELECT design_ordinal FROM component_asset WHERE asset_id=?", { asset })
    log("FABRICATE player=%d %s #%s asset=%s (dev shortcut; custody from here is ordinary)", pid, d.code, tostring(n), asset)
    if pid > 0 then TriggerEvent("ncm:component.changed", pid, nil) end
    return true, ("%s #%s (%s) is in your storage. /ncm.eng to see it."):format(d.code, tostring(n), d.name)
end

-- ------------------------------------------------------------------------------------------------ the bench
local function describe(d)
    local p = d.perf
    if p.kind == "reaction_engine" then
        return ("%.1f kN sustained, Isp %d s (%.2f kg/s = %.2f L/s of fuel at full), throttle lag %.2f s, heat %d kW (rejects %d, limit +%d K), %d kg"):format(
            p.thrustN / 1000, p.ispS, Sys.massFlow(p), Sys.massFlow(p) / Install.FUEL_KG_PER_L, p.throttleTauS or 0, p.heatKw or 0,
            d.thermal and d.thermal.rejectKw or 0, d.thermal and d.thermal.limitK or 0, d.massKg)
    elseif p.kind == "attitude_control" then
        return ("%.1f kN m about every axis (force %.1f kN at a %.1f m arm), Isp %d s on fuel, heat %d kW, %d kg"):format(
            p.torqueNm / 1000, p.torqueNm / p.armM / 1000, p.armM, p.ispS, p.heatKw or 0, d.massKg)
    elseif p.kind == "pulse_reaction" then
        return ("%.0f kN for %.2f s per discharge (%.1f kN s), Isp %d s (%.2f L per discharge), %d kg"):format(
            p.forceN / 1000, p.pulseS, p.forceN * p.pulseS / 1000, p.ispS, Sys.pulseMass(p) / Install.FUEL_KG_PER_L, d.massKg)
    end
    return p.kind
end

local function bench(pid)
    local driverId = driverOf(pid)
    if not driverId then chat(pid, "no driver profile yet"); return end
    local machineId = benchMachine(pid, driverId)
    chat(pid, "ENGINEERING BENCH")
    if machineId then
        local c = resolveMachine(machineId)
        local ml, cap = nil, nil
        if NcmFuel and NcmFuel.ensure then ml, cap = NcmFuel.ensure(machineId) end
        chat(pid, "Machine ..%s (%s), fuel %s / %s ml, add-ons +%.0f kg", short(machineId), tostring(c and c.vehicleKey), tostring(ml), tostring(cap), Install.addedMassKg(c and c.devices))
        local onMount = {}
        for _, d in ipairs(c and c.devices or {}) do onMount[d.mountId] = d end
        for _, mnt in ipairs(Install.MOUNTS) do
            local d = onMount[mnt.id]
            chat(pid, "  %s (%s, rated %d kN): %s", mnt.id, mnt.label, mnt.ratedN / 1000,
                d and ("%s facing %s -> pushes (%g, %g, %g)"):format(d.code, d.facing, d.axis[1], d.axis[2], d.axis[3]) or "empty")
        end
        for _, r in ipairs(c and c.refused or {}) do chat(pid, "  REFUSED ..%s: %s", short(r.componentId), r.reason) end
        local b = bindingsOf(machineId)
        if #b == 0 then chat(pid, "  controls: nothing bound") end
        for _, x in ipairs(b) do
            local live = false
            for _, d in ipairs(c and c.devices or {}) do if d.componentId == x.componentId then live = true end end
            chat(pid, "  control %s %s -> ..%s.%s%s", x.control, x.gesture, short(x.componentId), x.command, live and "" or " (component not installed: inert)")
        end
    else
        chat(pid, "No Machine selected: drive one, or /ncm.eng.machine to choose.")
    end
    local list = componentsOf(driverId)
    if #list == 0 then chat(pid, "Components: none. %s", isDev() and "/ncm.eng.fabricate rp16 | ia10 (dev)" or "") end
    for i, r in ipairs(list) do
        local d = Install.design(r.design_id)
        chat(pid, "  [%d] %s %s -- %s -- %s", i, serial(r), d and d.name or "", r.location_kind == "installed" and ("installed on ..%s"):format(short(r.machine_asset_id)) or "in storage",
            d and describe(d) or "")
    end
    chat(pid, "/ncm.eng.inspect <n> | /ncm.eng.install <n> <mount> <facing> | /ncm.eng.remove <n> | /ncm.eng.bind <control> <tap|hold|press|held> <n> <command>")
end

local function inspect(pid, ref)
    local driverId = driverOf(pid)
    local part = driverId and findComponent(driverId, ref)
    if not part then chat(pid, "no component %s", tostring(ref)); return end
    local d = Install.design(part.design_id)
    chat(pid, "%s -- %s (%s, revision %d, lineage %s)", serial(part), d.name, d.manufacturer, d.revision, d.lineageId)
    chat(pid, "  %s", d.subtitle)
    chat(pid, "  physics: %s", describe(d))
    chat(pid, "  envelope %.1f x %.1f x %.1f m, interface %s, peak %.0f kN through its mount", d.envelope[1], d.envelope[2], d.envelope[3], d.interface, Install.peakForceN(d) / 1000)
    local cmds = {}
    for name, spec in pairs(Sys.commands(d.perf.kind)) do cmds[#cmds + 1] = ("%s (%s: %s)"):format(name, spec.type, spec.desc) end
    chat(pid, "  commands: %s", table.concat(cmds, "; "))
    chat(pid, "  custody: %s, acquired via %s, asset %s", part.location_kind, tostring(part.acquired_via), part.asset_id)
    local machineId = benchMachine(pid, driverId)
    local m = machineId and machineRow(machineId)
    if m then
        local okList, noList = {}, {}
        for _, o in ipairs(Install.options(d, m.vehicle_key)) do
            if o.ok then okList[#okList + 1] = o.mountId:gsub("^mount%.", "") .. "/" .. o.facing
            elseif not o.reason:find("own body", 1, true) then noList[o.mountId] = o.reason end
        end
        chat(pid, "  on Machine ..%s it can go: %s", short(machineId), #okList > 0 and table.concat(okList, ", ") or "nowhere")
        for mnt, why in pairs(noList) do chat(pid, "  %s: %s", mnt, why) end
    end
end

local function reply(pid, ok, title, msg)
    chat(pid, "%s", tostring(msg))
    toast(pid, ok, title, tostring(msg))
end

local function cmd(name, fn)
    RegisterCommand(name, function(source, args)
        local pid = tonumber(source) or 0
        if pid <= 0 then return end
        CreateThread(function()
            local ok, err = pcall(fn, pid, args or {})
            if not ok then log("%s failed for player %d: %s", name, pid, tostring(err)); chat(pid, "%s failed: %s", name, tostring(err)) end
        end)
    end, false)
end

cmd("ncm.eng", function(pid) bench(pid) end)
cmd("ncm.eng.inspect", function(pid, a) inspect(pid, a[1]) end)
cmd("ncm.eng.fabricate", function(pid, a) local ok, m = NcmEngineering.fabricate(pid, a[1]); reply(pid, ok, ok and "FABRICATED" or "REFUSED", m) end)
cmd("ncm.eng.install", function(pid, a)
    local ok, m = NcmEngineering.install(pid, a[1], (a[2] and not a[2]:find("^mount%.")) and ("mount." .. a[2]) or a[2], a[3] and a[3]:lower())
    reply(pid, ok, ok and "INSTALLED" or "INSTALL REFUSED", m)
end)
cmd("ncm.eng.remove", function(pid, a) local ok, m = NcmEngineering.remove(pid, a[1]); reply(pid, ok, ok and "REMOVED" or "REMOVE REFUSED", m) end)
cmd("ncm.eng.bind", function(pid, a) local ok, m = NcmEngineering.bind(pid, a[1], a[2], a[3], a[4]); reply(pid, ok, ok and "BOUND" or "BIND REFUSED", m) end)
cmd("ncm.eng.unbind", function(pid, a) local ok, m = NcmEngineering.unbind(pid, a[1], a[2], a[3]); reply(pid, ok, ok and "UNBOUND" or "REFUSED", m) end)
cmd("ncm.eng.machine", function(pid, a)
    local driverId = driverOf(pid)
    if not driverId then return end
    local list = machinesOf(driverId)
    local n = tonumber(a[1])
    if n and list[n] then
        lastMachine[pid] = list[n].asset_id
        chat(pid, "bench Machine: [%d] ..%s %s", n, short(list[n].asset_id), tostring(list[n].vehicle_key))
        return
    end
    for i, m in ipairs(list) do chat(pid, "  [%d] ..%s %s%s", i, short(m.asset_id), tostring(m.vehicle_key), lastMachine[pid] == m.asset_id and "  <- bench" or "") end
    chat(pid, "/ncm.eng.machine <n> to choose")
end)

-- ------------------------------------------------------------------------------------------------ the pad (panel Parts)
-- The owner plays, never types: fabricate (dev), mount with a facing, and remove are panel holds, not chat commands.
local function padResult(pid, ok, title, msg)
    toast(pid, ok, title, tostring(msg))
    TriggerClientEvent("ncm:component.install.result", pid, { ok = ok and true or false, message = tostring(msg or "") })
    if pid > 0 then TriggerEvent("ncm:component.changed", pid, nil) end
end
RegisterNetEvent("ncm:engineering.fabricate", function(key)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local ok, m = NcmEngineering.fabricate(pid, tostring(key or ""))
        padResult(pid, ok, ok and "FABRICATED" or "REFUSED", m)
    end)
end)
RegisterNetEvent("ncm:engineering.mount", function(componentId, machineId, mountId, facing)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local ok, m = NcmEngineering.install(pid, tostring(componentId or ""), tostring(mountId or ""), tostring(facing or ""):lower(), tostring(machineId or ""))
        padResult(pid, ok, ok and "MOUNTED" or "MOUNT REFUSED", m)
        -- L361: fitting a part is Installation work; the Workshop keeps the engineer's competency
        if ok then TriggerEvent("ncm:workshop.credit", driverOf(pid), "fitment", 10, nil) end
    end)
end)
-- Bindings from the pad (stacked gearboxes, owner 2026-10-08: "mappable to buttons, not a hard button assigned"): the
-- Parts panel offers the controls; the player holds the one they want. Unbinding clears that component's binding.
RegisterNetEvent("ncm:engineering.bindpad", function(componentId, control, gesture, command)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local ok, m = NcmEngineering.bind(pid, tostring(control or ""), tostring(gesture or "tap"), tostring(componentId or ""), tostring(command or ""))
        padResult(pid, ok, ok and "BOUND" or "BIND REFUSED", m)
    end)
end)
RegisterNetEvent("ncm:engineering.unbindpad", function(componentId)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local driverId = driverOf(pid)
        local part = driverId and findComponent(driverId, tostring(componentId or ""))
        if not (part and part.machine_asset_id) then padResult(pid, false, "REFUSED", "that component is not installed"); return end
        MySQL.query.await("DELETE FROM machine_control_binding WHERE machine_asset_id=? AND component_asset_id=?", { part.machine_asset_id, part.asset_id })
        NcmEngineering.changed(part.machine_asset_id, "unbind")
        padResult(pid, true, "UNBOUND", serial(part) .. " answers no control now.")
    end)
end)
RegisterNetEvent("ncm:engineering.unmount", function(componentId)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local ok, m = NcmEngineering.remove(pid, tostring(componentId or ""))
        padResult(pid, ok, ok and "REMOVED" or "REMOVE REFUSED", m)
    end)
end)

-- Development one-shot (owner asked "do it for me", 2026-10-06): tunable ncm_world.devGrant = "<driverId>|<machineId>|<design key>|<mount>|<facing>"
-- fabricates that component for that driver and mounts it, once -- skipped when the driver already holds that design.
local devGrantOne
local function devGrant()
    local okS, v = pcall(function() return NcmIdentity and NcmIdentity.settings and NcmIdentity.settings.devGrant end)
    local spec = tostring(okS and v or "")
    if spec == "" then log("DEV GRANT: no grant configured (tunable empty or unreadable: %s)", tostring(okS and type(v) or v)); return end
    log("DEV GRANT: %d grant(s) configured (%d chars)", select(2, spec:gsub(";", ";")) + 1, #spec)
    -- the identity (server id, environment) is published by ncm_league a little after start: wait for it
    for _ = 1, 60 do
        local ok, id = pcall(function() return GlobalState.ncmIdentity end)
        if ok and type(id) == "table" and id.serverId then break end
        Wait(1000)
    end
    if not isDev() then log("DEV GRANT: not a development server -- ignored"); return end
    -- KB-371: Open77 silently drops a long string tunable (290 chars read back as ""; 99 worked). The compact form
    -- "<driver id prefix>|<machine id suffix>|<design>@<mount>@<facing>[@control:gesture:command],..." is expanded here.
    local dPre, mSuf, list = spec:match("^([%w%-]+)|([%w%-]+)|(.+)$")
    if dPre and not spec:find(";", 1, true) and list:find("@", 1, true) then
        local drv = MySQL.scalar.await("SELECT ncm_driver_id FROM ncm_driver WHERE ncm_driver_id LIKE ? LIMIT 1", { dPre .. "%" })
        local mac = drv and MySQL.scalar.await("SELECT asset_id FROM vehicle_asset WHERE server_id=? AND ncm_driver_id=? AND asset_id LIKE ? LIMIT 1",
            { serverId(), drv, "%" .. mSuf })
        if not drv or not mac then log("DEV GRANT: no driver %s* / Machine *%s", dPre, mSuf); return end
        local parts = {}
        for one in list:gmatch("[^,]+") do
            local key, mnt, facing, bind = one:match("^([^@]+)@([^@]+)@([^@]+)@?(.*)$")
            if key then
                local mountId = mnt:find("^mount%.") and mnt or ("mount." .. mnt)
                parts[#parts + 1] = ("%s|%s|%s|%s|%s%s"):format(tostring(drv), tostring(mac), key, mountId, facing, (bind or "") ~= "" and ("|" .. bind) or "")
            end
        end
        spec = table.concat(parts, ";")
        log("DEV GRANT: %d grant(s) for driver ..%s Machine ..%s", #parts, short(drv), short(mac))
    end
    -- L334: several grants separated by ';', each "<driver>|<machine>|<design>|<mount>|<facing>[|<control>:<gesture>:<command>]"
    if spec:find(";", 1, true) then
        for one in spec:gmatch("[^;]+") do
            local okOne, errOne = pcall(devGrantOne, one)
            if not okOne then log("DEV GRANT %s failed: %s", one, tostring(errOne)) end
        end
        return
    end
    return devGrantOne(spec)
end
devGrantOne = function(spec)
    local driverId, machineId, key, mountId, facing, bindSpec = spec:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|?([^|]*)$")
    if not driverId then log("DEV GRANT ignored: bad spec %s", spec); return end
    local d
    for _, x in ipairs(Install.DESIGNS) do if x.code:lower():find(key:lower(), 1, true) then d = x end end
    if not d then log("DEV GRANT ignored: no design %s", key); return end
    local have = MySQL.scalar.await("SELECT COUNT(*) FROM component_asset WHERE server_id=? AND ncm_driver_id=? AND design_id=? AND lifecycle='active'",
        { serverId(), driverId, d.designId })
    if (tonumber(have) or 0) > 0 then log("DEV GRANT: driver ..%s already holds %s -- nothing to do", short(driverId), d.code); return end
    local m = machineRow(machineId)
    if not m or not sameId(m.ncm_driver_id, driverId) then
        log("DEV GRANT ignored: Machine ..%s is not driver ..%s's (server %s, row %s, owner %s)", short(machineId), short(driverId), tostring(serverId()),
            tostring(m ~= nil), tostring(m and m.ncm_driver_id))
        return
    end
    -- the same two operations the pad performs, as that driver (pid 0: no player is connected at resource start)
    local saved = driverOf
    driverOf = function() return driverId end
    local ok1, m1 = NcmEngineering.fabricate(0, key)
    local ok2, m2 = false, "not fabricated"
    if ok1 then
        local part = MySQL.single.await([[SELECT asset_id FROM component_asset WHERE server_id=? AND ncm_driver_id=? AND design_id=? AND location_kind='storage'
            ORDER BY created_at DESC LIMIT 1]], { serverId(), driverId, d.designId })
        ok2, m2 = NcmEngineering.install(0, part and part.asset_id, mountId, facing, machineId)
        local control, gesture, command = (bindSpec or ""):match("^([^:]+):([^:]+):([^:]+)$")
        if ok2 and control and part then
            local okB, mB = NcmEngineering.bind(0, control, gesture, part.asset_id, command)
            m2 = tostring(m2) .. " | bind " .. tostring(okB) .. " (" .. tostring(mB) .. ")"
        end
    end
    driverOf = saved
    log("DEV GRANT %s -> Machine ..%s %s %s: fabricate %s (%s) | mount %s (%s)", d.code, short(machineId), mountId, facing,
        tostring(ok1), tostring(m1), tostring(ok2), tostring(m2))
end

-- L352 (owner, 2026-10-08: "equip my anchored galena with the same flight package equipped to my dev server hella"):
-- an OWNER one-shot that works on Online too. Tunable ncm_world.ownerGrant = "<driver id prefix>|<vehicle>|<kit>[#nonce]"
-- (short on purpose: KB-371). <vehicle> is a catalogue word ("galena": the driver's anchored one first) or an asset id
-- suffix. A kit is a fit, part for part. Each part already on the Machine is skipped; one in the driver's storage is
-- used; otherwise it is minted with provenance `owner_grant` (never `dev_fabricate`). Logged per part.
--
-- Doc 58 (2026-10-12) -- THE ENGINEERING-PERSISTENCE FIX. On 2026-10-11 a `flight` grant left in tunables.json re-ran
-- at every restart (two deploys and a crash) and put the Hella's parts back into an obsolete layout each time. A grant
-- is now ONE-SHOT BY CONSTRUCTION: every applied spec is written to `owner_grant_ledger` before anything is touched, and
-- a spec already in the ledger is never applied again -- a leftover tunable logs "skipped" and changes nothing. To apply
-- a kit again, change the nonce (`#<anything>`; dist/deeplab.sh stamps the UTC time). If the ledger cannot be read the
-- grant is REFUSED. A player's normal engineering (the panel, the pad) never passes through here.
--
-- Kit items:
--   { code, mount, facing, refit = true, bind = {control, gesture, command} | binds = { {...}, ... }, charge = true }
--                                fit a part (refit: move it if it is elsewhere); charge: fill its store (doc 58 drives)
--   { code, stow = true }        take a part off the Machine into storage (if it is on)
--   { family, stow = true }      every installed part of a family to storage (`except` a code)
--   { clear = { controls } }     unbind every component from those controls on this Machine (no button fires two systems)
--   { fuel = "full" }            the Machine's own fuel tank to capacity (attitude sets and the IA-10 burn it)
--   { fusionMinKg = n }          the fusion tank parts topped up to at least n kg
local LAB_BINDS_TARGET = { { "triangle", "tap", "engage" }, { "triangle", "hold", "abort" }, { "rb", "tap", "next" }, { "lb", "tap", "prev" } }
local LAB_CLEAR = { clear = { "triangle", "lb", "rb" } }
local LAB_BASE = {   -- the Hella's flight hardware kept installed (fusion unbound) under an exotic drive
    { code = "ZTC-FD1", mount = "mount.underside", facing = "down", refit = true },
    { code = "ZTC-PT500", mount = "mount.rear", facing = "left", refit = true },
    { code = "ZTC-AC6", mount = "mount.roof", facing = "up", refit = true },
    { fuel = "full" },
}
local function labKit(code, binds)
    local k = { LAB_CLEAR, { family = "exotic_drive", stow = true, except = code } }
    for _, it in ipairs(LAB_BASE) do k[#k + 1] = it end
    k[#k + 1] = { code = code, mount = "mount.front", facing = "fore", refit = true, charge = true, binds = binds }
    return k
end
local KITS = {
    flight = {   -- the dev Hella (..0003) after L331/L334/KB-373: PT-400 front, FD-1 rear aft on HOLD Triangle, AC-6 roof, IA-10 hop on TAP
        { code = "ZTC-PT500", mount = "mount.front", facing = "up" },
        { code = "ZTC-FD1", mount = "mount.rear", facing = "aft", bind = { "triangle", "hold", "throttle" } },
        { code = "ZTC-AC6", mount = "mount.roof", facing = "up" },
        { code = "ARC-IA10", mount = "mount.underside", facing = "down", bind = { "triangle", "tap", "discharge" } },
    },
    -- KB-413 (owner ruling 2026-10-08: "FD-1 under floor"): on Online fuel the IA-10 hop cannot reach the seam; the FD-1
    -- under the floor facing down lifts on fusion. It displaces the IA-10 to storage (the floor is its only rated mount).
    -- 2026-10-11 (owner): the Hella as it flew before the leftover `flight` grant moved its parts at restarts
    restore = {
        { code = "ZTC-FD1", mount = "mount.underside", facing = "down", bind = { "triangle", "hold", "throttle" }, refit = true },
        { code = "ZTC-PT500", mount = "mount.rear", facing = "left", refit = true },
        { code = "ZTC-AC6", mount = "mount.roof", facing = "up", refit = true },
    },
    climb = {
        { code = "ZTC-FD1", mount = "mount.underside", facing = "down", bind = { "triangle", "hold", "throttle" }, refit = true },
    },
    -- Doc 58: the propulsion laboratory (owner, 2026-10-12: Alabino's Hella, one drive at a time). Each kit leaves
    -- EXACTLY ONE system on Triangle; the others stay fitted (or go to storage) but answer nothing.
    lab_impulse = {   -- the IA-10 needs the floor-pan hardpoint: the FD-1 goes to storage for this test
        LAB_CLEAR, { family = "exotic_drive", stow = true },
        { code = "ZTC-FD1", stow = true },
        { code = "ARC-IA10", mount = "mount.underside", facing = "down", refit = true, bind = { "triangle", "tap", "discharge" } },
        { code = "ZTC-PT500", mount = "mount.rear", facing = "left", refit = true },
        { code = "ZTC-AC6", mount = "mount.roof", facing = "up", refit = true },
        { fuel = "full" },
    },
    lab_fusion = {    -- the Hella as it flies: FD-1 under the floor on HOLD Triangle (the IA-10 displaced to storage)
        LAB_CLEAR, { family = "exotic_drive", stow = true },
        { code = "ZTC-FD1", mount = "mount.underside", facing = "down", refit = true, bind = { "triangle", "hold", "throttle" } },
        { code = "ZTC-PT500", mount = "mount.rear", facing = "left", refit = true },
        { code = "ZTC-AC6", mount = "mount.roof", facing = "up", refit = true },
        { fuel = "full" }, { fusionMinKg = 300 },
    },
    lab_warp = labKit("XLB-WD1", { { "triangle", "tap", "engage" }, { "triangle", "hold", "abort" }, { "rb", "tap", "up" }, { "lb", "tap", "down" } }),
    lab_alcubierre = labKit("XLB-AB1", LAB_BINDS_TARGET),
    lab_jump = labKit("XLB-JD1", LAB_BINDS_TARGET),
    lab_wormhole = labKit("XLB-WH1", LAB_BINDS_TARGET),
    -- 2026-10-12 (owner: "make it fly ... aren't we using our engineering parts and vfx" / "also give it a wormhole
    -- drive"): the Zetatech Atlus AV, flown on NCM engineering. Four VL-28 lift fans on its engine pods and the FC-1
    -- flight computer fly it in Night City (fly-by-wire: W/S A/D Q/E, Space/R up, C down); two FD-1s under it take it
    -- through the thin air to the Deep seam (the computer adds them when the fans run short) and drive it in Deep on HOLD
    -- Triangle; the AC-6 turns it in vacuum; the PT-500 in the cabin bay feeds the FD-1s; the XLB-WH1 opens the wormhole
    -- (Deep: TAP Triangle engage, RB/LB TAP target, LB HOLD abort). `another`: a second part of a design on its own mount.
    av = {
        { clear = { "triangle", "lb", "rb" } },
        { code = "ZTC-VL28", mount = "mount.av.pod.fl", facing = "down", another = true },
        { code = "ZTC-VL28", mount = "mount.av.pod.fr", facing = "down", another = true },
        { code = "ZTC-VL28", mount = "mount.av.pod.rl", facing = "down", another = true },
        { code = "ZTC-VL28", mount = "mount.av.pod.rr", facing = "down", another = true },
        { code = "ZTC-FD1", mount = "mount.underside", facing = "down", another = true, bind = { "triangle", "hold", "throttle" } },
        { code = "ZTC-FD1", mount = "mount.rear", facing = "down", another = true, bind = { "triangle", "hold", "throttle" } },
        { code = "ZTC-AC6", mount = "mount.roof", facing = "up", refit = true },
        { code = "ZTC-PT500", mount = "mount.av.bay", facing = "fore", refit = true },
        { code = "XLB-WH1", mount = "mount.front", facing = "fore", refit = true, charge = true,
          binds = { { "triangle", "tap", "engage" }, { "lb", "hold", "abort" }, { "rb", "tap", "next" }, { "lb", "tap", "prev" } } },
        { code = "ZTC-FC1", mount = "mount.electronics", facing = "fore", refit = true },
        -- 2026-10-13: the FL-6 fusion lift drives (installation.lua) haul it up with the fans
        { code = "ZTC-FL6", mount = "mount.av.belly.f", facing = "down", another = true },
        { code = "ZTC-FL6", mount = "mount.av.belly.r", facing = "down", another = true },
        { fuel = "full" }, { fusionMinKg = 400 },
    },
    -- the retrofit for an Atlus already carrying the `av` kit: the two FL-6s, both tanks topped up
    av_lift = {
        { code = "ZTC-FL6", mount = "mount.av.belly.f", facing = "down", another = true },
        { code = "ZTC-FL6", mount = "mount.av.belly.r", facing = "down", another = true },
        { fuel = "full" }, { fusionMinKg = 400 },
    },
}
NcmEngineering.KITS = KITS

local function ownerMachine(driverId, which)
    if which:match("^%x+$") or which:find("-", 1, true) then
        return MySQL.scalar.await("SELECT asset_id FROM vehicle_asset WHERE server_id=? AND ncm_driver_id=? AND asset_id LIKE ? LIMIT 1",
            { serverId(), driverId, "%" .. which })
    end
    local rows = MySQL.query.await([[SELECT v.asset_id, MAX(a.asset_id IS NOT NULL) AS anchored FROM vehicle_asset v
        LEFT JOIN racing_week_anchor a ON a.server_id=v.server_id AND a.asset_id=v.asset_id
        WHERE v.server_id=? AND v.ncm_driver_id=? AND v.vehicle_key LIKE ? GROUP BY v.asset_id ORDER BY anchored DESC, v.asset_id]],
        { serverId(), driverId, "%" .. which:lower() .. "%" }) or {}
    if #rows == 0 then return nil, "the driver has no " .. which end
    if #rows > 1 and tonumber(rows[1].anchored) ~= 1 then return nil, ("%d %s(s) and none anchored: name one by id suffix"):format(#rows, which) end
    return rows[1].asset_id
end

local function designByCode(code) for _, x in ipairs(Install.DESIGNS) do if x.code == code then return x end end end

local function installedOf(machineId, designId)
    return MySQL.scalar.await([[SELECT asset_id FROM component_asset WHERE machine_asset_id=? AND design_id=? AND location_kind='installed'
        AND lifecycle='active' LIMIT 1]], { machineId, designId })
end

local function ownerGrantPart(driverId, machineId, item)
    -- the kit's non-part items
    if item.clear then
        local out = {}
        for _, c in ipairs(item.clear) do
            local ctl = Controls.normalize(c)
            if ctl then
                local n = MySQL.update.await("DELETE FROM machine_control_binding WHERE machine_asset_id=? AND control_key=?", { machineId, ctl })
                out[#out + 1] = ("%s (%s binding(s))"):format(ctl, tostring(n or 0))
            end
        end
        NcmEngineering.changed(machineId, "owner grant: controls cleared")
        return "controls cleared: " .. table.concat(out, ", ")
    end
    if item.fuel == "full" then
        -- through the fuel module's loaded tank (a bare database write is overwritten by its cached level)
        if not (NcmFuel and NcmFuel.refill) then return "fuel: no fuel module (left as it is)" end
        local before, after = NcmFuel.refill(machineId)
        return ("fuel: %.0f -> %.0f ml (full)"):format(tonumber(before) or 0, tonumber(after) or 0)
    end
    if item.fusionMinKg then
        local out = {}
        for _, row in ipairs(MySQL.query.await([[SELECT a.asset_id, a.design_id FROM component_asset a WHERE a.machine_asset_id=? AND a.location_kind='installed'
            AND a.lifecycle='active']], { machineId }) or {}) do
            local d = Install.design(row.design_id)
            if d and d.perf and d.perf.kind == "propellant_tank" and d.perf.propellant == "fusion" then
                local have = tankFill(row.asset_id, d)
                local want = math.min(d.perf.capacityKg or 0, math.max(have, item.fusionMinKg))
                if want > have then MySQL.update.await("UPDATE component_state SET propellant_kg=?, updated_at=? WHERE asset_id=?", { want, now(), row.asset_id }) end
                out[#out + 1] = ("%s %.1f -> %.1f kg"):format(d.code, have, want)
            end
        end
        return "fusion: " .. (#out > 0 and table.concat(out, ", ") or "no fusion tank fitted")
    end
    if item.family and item.stow then
        local out = {}
        for _, row in ipairs(MySQL.query.await([[SELECT a.asset_id, d.code FROM component_asset a JOIN component_design d ON d.design_id=a.design_id
            WHERE a.machine_asset_id=? AND a.location_kind='installed' AND a.lifecycle='active' AND d.family=?]], { machineId, item.family }) or {}) do
            if row.code ~= item.except then
                local okR, mR = NcmEngineering.remove(0, row.asset_id)
                out[#out + 1] = ("%s stowed %s (%s)"):format(row.code, tostring(okR), tostring(mR))
            end
        end
        return ("%s: %s"):format(item.family, #out > 0 and table.concat(out, "; ") or "none to stow")
    end
    local d = designByCode(item.code)
    if not d then return "no design " .. tostring(item.code) end
    local on = installedOf(machineId, d.designId)
    local out
    if item.another then
        -- one of several of this design: only the one already ON this mount counts (the others stay where they are)
        on = MySQL.scalar.await([[SELECT a.asset_id FROM machine_configuration_current x
            JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id
            JOIN component_asset a ON a.asset_id=i.component_asset_id
            WHERE x.machine_asset_id=? AND i.interface_id=? AND a.design_id=? AND a.lifecycle='active' LIMIT 1]], { machineId, item.mount, d.designId })
        if on then
            out = ("%s already on %s: kept"):format(d.code, item.mount)
        end
    end
    if item.stow then
        if not on then return d.code .. " not fitted: nothing to stow" end
        local okR, mR = NcmEngineering.remove(0, on)
        return ("%s stowed: %s (%s)"):format(d.code, tostring(okR), tostring(mR))
    end
    if on and item.another then
        -- kept above
    elseif on and item.refit then
        -- a refit moves the part: where is it now in the current configuration?
        local cur = MySQL.single.await([[SELECT i.interface_id, i.install_json FROM machine_configuration_current x
            JOIN machine_configuration_item i ON i.configuration_id=x.configuration_id
            WHERE x.machine_asset_id=? AND i.component_asset_id=?]], { machineId, on })
        local facing = cur and tostring(cur.install_json or ""):match('"facing"%s*:%s*"(%a+)"')
        if cur and cur.interface_id == item.mount and facing == item.facing then
            out = ("%s already on %s facing %s: kept"):format(d.code, item.mount, item.facing)
        else
            local okR, mR = NcmEngineering.remove(0, on)
            if not okR then return ("%s refit refused at remove: %s"):format(d.code, tostring(mR)) end
            on = nil
        end
    elseif on then
        out = ("%s already on the Machine (..%s): kept"):format(d.code, short(on))
    end
    local part = on
    if not on then
        part = MySQL.scalar.await([[SELECT asset_id FROM component_asset WHERE server_id=? AND ncm_driver_id=? AND design_id=?
            AND location_kind='storage' AND lifecycle='active' ORDER BY created_at LIMIT 1]], { serverId(), driverId, d.designId })
        local how = "from storage"
        if not part then
            part, how = ids.uuid4(hostRng), "minted (owner_grant)"
            local t = now()
            local ok, err = MySQL.transaction.await({
                { query = [[INSERT INTO component_asset (asset_id,server_id,design_id,run_id,ncm_driver_id,manufacturer_key,location_kind,machine_asset_id,
                    global_ordinal,maker_ordinal,design_ordinal,factory_original,acquired_via,acquired_at,exposure_m,created_at,lifecycle)
                    SELECT ?,?,?,NULL,?,?,'storage',NULL,NULL,NULL,COALESCE(MAX(design_ordinal),0)+1,0,'owner_grant',?,0,?,'active'
                    FROM component_asset WHERE server_id=? AND design_id=?]],
                  values = { part, serverId(), d.designId, driverId, d.makerKey, t, t, serverId(), d.designId } },
                { query = [[INSERT INTO component_asset_transfer (transfer_id,idem_key,server_id,asset_id,from_driver_id,to_driver_id,kind,market_id,amount,occurred_at)
                    VALUES (?,?,?,?,NULL,?,'owner_grant',NULL,NULL,?)]], values = { ids.uuid4(hostRng), "eng_owner:" .. part, serverId(), part, driverId, t } },
            })
            if not ok then return ("%s mint failed: %s"):format(d.code, tostring(err)) end
            if d.perf and d.perf.kind == "propellant_tank" then   -- a new tank comes full (L334)
                MySQL.insert.await("INSERT IGNORE INTO component_state (asset_id, propellant_kg, updated_at) VALUES (?,?,?)", { part, d.perf.capacityKg or 0, t })
            end
        end
        local okM, mM = NcmEngineering.install(0, part, item.mount, item.facing, machineId)
        out = ("%s %s -> %s %s: mount %s (%s)"):format(d.code, how, item.mount, item.facing, tostring(okM), tostring(mM))
        if not okM then return out end
    end
    local binds = item.binds or (item.bind and { item.bind }) or {}
    for _, b in ipairs(binds) do
        local okB, mB = NcmEngineering.bind(0, b[1], b[2], part, b[3])
        out = out .. (" | bind %s %s %s: %s (%s)"):format(b[1], b[2], b[3], tostring(okB), tostring(mB))
    end
    if item.charge and d.perf and d.perf.store then
        -- doc 58: the drive's store, full (about two test activations)
        local cap = tonumber(d.perf.store.capacity) or 0
        MySQL.query.await([[INSERT INTO component_state (asset_id, propellant_kg, updated_at) VALUES (?,?,?)
            ON DUPLICATE KEY UPDATE propellant_kg=VALUES(propellant_kg), updated_at=VALUES(updated_at)]], { part, cap, now() })
        out = out .. (" | charge %.0f (full)"):format(cap)
    end
    return out
end

-- Doc 58: the server's unhosted flight reads the Machine from its PRESENCE RECORD (devices, tanks, drive states). After
-- a kit changes the Machine, that record is rewritten from the new configuration -- otherwise the server would keep
-- flying the old parts (the second half of the 2026-10-11 collision). Position, velocity, attitude, spin and the
-- travel ledger are kept exactly; per-device states (indexed by the old device list) are dropped.
local function refreshPresence(driverId, machineId)
    for _ = 1, 240 do if NcmCanonical and NcmCanonical.booted then break end Wait(500) end
    if not (NcmCanonical and NcmCanonical.refreshMachine) then return "presence: canonical not available" end
    cache[machineId] = nil
    local p = payload(machineId)
    if not p then return "presence: no payload" end
    local devices = Install.resolve(p.items or {}, p.vehicleKey)
    local fuelKg = p.fuel and tonumber(p.fuel.ml) and (tonumber(p.fuel.ml) / 1000 * Install.FUEL_KG_PER_L) or nil
    return NcmCanonical.refreshMachine(driverId, machineId, devices, fuelKg)
end

local function ledgerRead(spec)
    local ok, row = pcall(MySQL.single.await, "SELECT applied_at, result_json FROM owner_grant_ledger WHERE spec=?", { spec })
    if not ok then return nil, tostring(row) end
    return row or false
end

local function ownerGrant()
    local okS, v = pcall(function() return NcmIdentity and NcmIdentity.settings and NcmIdentity.settings.ownerGrant end)
    local spec = tostring(okS and v or "")
    if spec == "" then return end
    for _ = 1, 60 do   -- the server identity arrives from ncm_league a little after start (KB-363)
        local ok, id = pcall(function() return GlobalState.ncmIdentity end)
        if ok and type(id) == "table" and id.serverId then break end
        Wait(1000)
    end
    local dPre, which, kitName, nonce = spec:match("^([%w%-]+)|([%w%-]+)|([%w_]+)#?([%w%-%.:]*)$")
    local kit = kitName and KITS[kitName]
    if not kit then
        local names = {}
        for k in pairs(KITS) do names[#names + 1] = k end
        table.sort(names)
        log("OWNER GRANT ignored: bad spec %q (driver prefix|vehicle|kit[#nonce]; kits: %s)", spec, table.concat(names, ", "))
        return
    end
    -- the ledger: one application per spec, ever
    local prior, whyL = ledgerRead(spec)
    if prior == nil then log("OWNER GRANT REFUSED %q: the grant ledger is unreadable (%s) -- a grant that cannot prove it is new is never applied", spec, tostring(whyL)); return end
    if prior then
        log("OWNER GRANT skipped %q: already applied (ledger, applied_at %s) -- nothing touched. Remove ownerGrant from tunables.json, or change its #nonce to apply the kit again.",
            spec, tostring(prior.applied_at))
        return
    end
    local drv = MySQL.scalar.await("SELECT ncm_driver_id FROM ncm_driver WHERE ncm_driver_id LIKE ? LIMIT 2", { dPre .. "%" })
    if not drv then log("OWNER GRANT: no driver %s*", dPre); return end
    local mac, why = ownerMachine(drv, which)
    if not mac then log("OWNER GRANT: driver ..%s: %s", short(drv), tostring(why)); return end
    -- claim the spec BEFORE touching anything: a crash part-way through is not re-run by the next restart either
    local okI, errI = pcall(MySQL.insert.await, "INSERT INTO owner_grant_ledger (spec, server_id, driver_id, asset_id, kit, applied_at, result_json) VALUES (?,?,?,?,?,?,?)",
        { spec, serverId(), drv, mac, kitName, now(), "[]" })
    if not okI then log("OWNER GRANT REFUSED %q: could not claim it in the ledger (%s)", spec, tostring(errI)); return end
    local lab = kitName:match("^lab_(.+)$")
    log("OWNER GRANT kit %s -> driver ..%s Machine ..%s (%s)%s", kitName, short(drv), short(mac), which,
        lab and (" | DEEP LAB: developer test-drive override for `%s` (not a player refit)"):format(lab) or "")
    local saved = driverOf
    driverOf = function() return drv end
    local results = {}
    for _, item in ipairs(kit) do
        local okP, msg = pcall(ownerGrantPart, drv, mac, item)
        results[#results + 1] = tostring(msg)
        log("OWNER GRANT %s", tostring(msg))
        Wait(0)
    end
    driverOf = saved
    cache[mac] = nil
    local okR, pres = pcall(refreshPresence, drv, mac)
    results[#results + 1] = tostring(pres)
    log("OWNER GRANT %s", tostring(okR and pres or ("presence refresh failed: " .. tostring(pres))))
    pcall(MySQL.update.await, "UPDATE owner_grant_ledger SET result_json=? WHERE spec=?", { enc(results), spec })
    if lab then
        pcall(MySQL.insert.await, "INSERT INTO deep_lab_log (server_id, driver_id, asset_id, drive, spec, applied_at, detail_json) VALUES (?,?,?,?,?,?,?)",
            { serverId(), drv, mac, lab, spec, now(), enc(results) })
        log("DEEP LAB %s applied to Machine ..%s (driver ..%s) -- developer override, spec %q, nonce %s", lab, short(mac), short(drv), spec, nonce ~= "" and nonce or "(none)")
    end
end

AddEventHandler("onResourceStart", function(name)
    if name ~= "ncm_world" then return end
    CreateThread(function()
        Wait(6000)
        local ok, err = pcall(seedDesigns)
        if not ok then log("design seed failed: %s", tostring(err)) end
        local okR, errR = pcall(function()
            local rows = MySQL.query.await("SELECT spec_json FROM component_design WHERE spec_json IS NOT NULL AND origin_kind IN ('rnd_physical','prototype','player_design')") or {}
            for _, row in ipairs(rows) do
                local spec = dec(row.spec_json)
                local registered, why = Install.register(spec)
                if not registered then log("physical Design refused on load: %s", tostring(why)) end
            end
        end)
        if not okR then log("physical Design load failed: %s", tostring(errR)) end
        local okG, errG = pcall(devGrant)
        if not okG then log("DEV GRANT failed: %s", tostring(errG)) end
        local okO, errO = pcall(ownerGrant)
        if not okO then log("OWNER GRANT failed: %s", tostring(errO)) end
    end)
end)
