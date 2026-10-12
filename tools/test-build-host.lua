-- ncm_build's server (IDEA-1282) against deterministic doubles: the Build primitive's first milestone, as far as it can
-- be proved off the game -- attach to an owned Machine, the prop bound to THAT vehicle at the composed transform,
-- store and recall (rebuilt on the new vehicle from the database), a chain, move, remove, and every refusal.
local root = arg[1] or "."
local passed = 0
local realPrint = print
local logs = {}
local function check(label, value)
    if not value then
        realPrint("  FAIL " .. label)
        for _, l in ipairs(logs) do realPrint("    log| " .. l) end
        error(label, 0)
    end
    passed = passed + 1; realPrint("  PASS " .. label)
end

-- ---------------------------------------------------------------- platform doubles
local events, results, states = {}, {}, {}
function AddEventHandler(name, fn) events[name] = events[name] or {}; table.insert(events[name], fn) end
function RegisterNetEvent(name, fn) AddEventHandler(name, fn) end
function RegisterCommand() end
function TriggerEvent(name, ...) for _, fn in ipairs(events[name] or {}) do fn(...) end end
function TriggerClientEvent(name, pid, body)
    if name == "ncm:build.result" then results[#results + 1] = body end
    if name == "ncm:build.state" then states[pid] = body end
end
function CreateThread(fn) fn() end
function Wait() end
local gameMs = 0
function GetGameTimer() gameMs = gameMs + 1000; return gameMs end
function GetPlayerIdentifier(pid) return "user:" .. tostring(pid) end
function print(s) logs[#logs + 1] = tostring(s) end
GlobalState = { ncmIdentity = { serverId = "test", environment = "development" } }

local props, nextProp = {}, 100
Open77 = {
    time = { unix = function() return 1790000000 end },
    tunables = { declare = function() return {} end },
    vehicles = { get = function(vid) return { position = { x = 10, y = 20, z = 1 }, bucket = 0, id = vid } end },
    props = {
        create = function(def) nextProp = nextProp + 1; local id = tostring(nextProp); props[id] = { def = def }; return id end,
        attach = function(id, b) if not props[id] then return nil, "not_found" end; props[id].binding = b; return true end,
        remove = function(id) props[id] = nil; return true end,
    },
}
local function fire(name, pid, ...) source = pid; for _, fn in ipairs(events[name] or {}) do fn(...) end end

-- ---------------------------------------------------------------- database double
local drivers = { ["user:1"] = "D-ANA", ["user:2"] = "D-BEN" }
local owners = { ["m-mai"] = "d-ana", ["m-ben"] = "d-ben" }
local db = {}                  -- attachment_id -> row
MySQL = {
    isReady = function() return true end,
    single = { await = function(sql, p)
        if sql:find("ncm_driver_binding") then local d = drivers[p[2]]; return d and { ncm_driver_id = d } or nil end
        error("unexpected single: " .. sql)
    end },
    scalar = { await = function(sql, p)
        if sql:find("SELECT ncm_driver_id FROM vehicle_asset") then return owners[p[1]] end
        if sql:find("SELECT vehicle_key FROM vehicle_asset") then return "makigai_maimai" end
        if sql:find("SELECT root_machine_id") then local r = db[p[1]]; return r and not r.removed_at and r.root_machine_id or nil end
        error("unexpected scalar: " .. sql)
    end },
    query = { await = function(sql, p)
        local out = {}
        for _, r in pairs(db) do if r.root_machine_id == p[2] and not r.removed_at then out[#out + 1] = r end end
        return out
    end },
    insert = { await = function(sql, p)
        db[p[1]] = { attachment_id = p[1], server_id = p[2], build_asset_id = p[3], parent_kind = p[4], parent_id = p[5],
            root_machine_id = p[6], pos_x = p[7], pos_y = p[8], pos_z = p[9], rot_roll = p[10], rot_pitch = p[11], rot_yaw = p[12],
            builder_driver_id = p[13], created_at = p[14], updated_at = p[15], revision = 1 }
        return 1
    end },
    update = { await = function(sql, p)
        if sql:find("SET removed_at") then db[p[3]].removed_at = p[1]; db[p[3]].removed_by = p[2]; return 1 end
        if sql:find("SET pos_x") then
            local r = db[p[8]]
            r.pos_x, r.pos_y, r.pos_z, r.rot_roll, r.rot_pitch, r.rot_yaw = p[1], p[2], p[3], p[4], p[5], p[6]
            r.revision = r.revision + 1
            return 1
        end
        error("unexpected update: " .. sql)
    end },
}

-- ---------------------------------------------------------------- load core + the resource
NcmCore = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
dofile(root .. "/ncm/online/resources/ncm_build/server/main.lua")
local function last() return results[#results] end
local function boundTo(vid)
    local out = {}
    for id, p in pairs(props) do if p.binding and p.binding.parentId == tostring(vid) then out[#out + 1] = p end end
    return out
end

-- ---------------------------------------------------------------- the milestone
TriggerEvent("ncm:vehicle:materialized", "M-MAI", 501, 1)        -- Ana calls her Mai Mai
fire("ncm:build.request", 1)
check("my Machine out in the city is offered", states[1] and #states[1].machines == 1 and states[1].machines[1].vehicleId == "501")
check("the catalogue is offered by stable id", states[1].catalogue[1].id == "NCM_WING_SMALL_01")

fire("ncm:build.attach", 1, { parent = { kind = "machine", id = "m-mai" }, assetId = "NCM_WING_SMALL_01", pos = { 0, -1.9, 1.1 }, rot = { 0, -8, 0 } })
check("a wing attaches", last().ok == true and last().attachmentId)
local wingId = last().attachmentId
local b = boundTo(501)
check("one prop, bound to that vehicle's root", #b == 1 and b[1].binding.parentType == "vehicle" and b[1].binding.bone == "")
check("at the transform placed, relative to the car", math.abs(b[1].binding.offset.y + 1.9) < 1e-9 and math.abs(b[1].binding.rotation.y + 8) < 1e-9)
check("in the vehicle's bucket, without collision", b[1].def.bucket == 0 and b[1].def.collision == false and b[1].def.model == "sign.rect.blank")
check("and saved against the Machine, not the car", db[wingId] and db[wingId].root_machine_id == "m-mai")

-- store, then recall as a different vehicle: the wing comes back from the database
TriggerEvent("ncm:vehicle:dematerialized", "M-MAI", 501, "stored")
check("storing the Machine takes its props away", #boundTo(501) == 0)
check("...and keeps the row", db[wingId] and not db[wingId].removed_at)
TriggerEvent("ncm:vehicle:materialized", "M-MAI", 777, 1)
local back = boundTo(777)
check("recalled as vehicle 777, the wing returns on 777", #back == 1 and math.abs(back[1].binding.offset.z - 1.1) < 1e-9)

-- a chain: a beam on the car, a wing on the beam
fire("ncm:build.attach", 1, { parent = { kind = "machine", id = "m-mai" }, assetId = "NCM_BEAM_01", pos = { 0, -1.6, 1.0 }, rot = { 0, 0, 90 } })
local beamId = last().attachmentId
fire("ncm:build.attach", 1, { parent = { kind = "attachment", id = beamId }, assetId = "NCM_WING_SMALL_01", pos = { 0, 0.5, 0.2 }, rot = { 0, 0, 0 } })
check("a wing mounts on a beam", last().ok == true)
local found
for _, p in pairs(props) do if p.binding and math.abs(p.binding.offset.x + 0.5) < 1e-9 then found = p end end
check("a chained wing binds to the root car at the composed transform", found and found.binding.parentId == "777" and math.abs(found.binding.rotation.z - 90) < 1e-9)
fire("ncm:build.attach", 1, { parent = { kind = "attachment", id = wingId }, assetId = "NCM_BOX_SMALL_01", pos = { 0, 0, 0.2 }, rot = { 0, 0, 0 } })
check("a wing cannot carry", last().ok == false and last().text:find("bar or beam"))

-- move
fire("ncm:build.edit", 1, { attachmentId = wingId, pos = { 0.1, -1.95, 1.2 }, rot = { 0, -12, 0 } })
check("a wing moves", last().ok == true and db[wingId].revision == 2 and math.abs(db[wingId].pos_z - 1.2) < 1e-9)

-- refusals
fire("ncm:build.attach", 2, { parent = { kind = "machine", id = "m-mai" }, assetId = "NCM_WING_SMALL_01", pos = { 0, 0, 1 }, rot = { 0, 0, 0 } })
check("someone else cannot build on my Machine", last().ok == false and last().text:find("not your Machine"))
fire("ncm:build.remove", 2, { attachmentId = wingId })
check("...nor remove from it", last().ok == false)
fire("ncm:build.attach", 1, { parent = { kind = "machine", id = "m-mai" }, assetId = "C:\\evil.mesh", pos = { 0, 0, 1 }, rot = { 0, 0, 0 } })
check("only catalogue objects", last().ok == false and last().text:find("catalogue"))
fire("ncm:build.attach", 1, { parent = { kind = "machine", id = "m-mai" }, assetId = "NCM_WING_SMALL_01", pos = { 0, 0, 9 }, rot = { 0, 0, 0 } })
check("not floating metres away", last().ok == false)
TriggerEvent("ncm:vehicle:dematerialized", "M-BEN", 0, "x")
fire("ncm:build.attach", 2, { parent = { kind = "machine", id = "m-ben" }, assetId = "NCM_WING_SMALL_01", pos = { 0, 0, 1 }, rot = { 0, 0, 0 } })
check("only on a Machine that is out", last().ok == false and last().text:find("Call the Machine"))
fire("ncm:build.remove", 1, { attachmentId = beamId })
check("a member with something on it cannot go first", last().ok == false and last().text:find("mounted on it"))

-- remove
local before = 0
for _ in pairs(props) do before = before + 1 end
fire("ncm:build.remove", 1, { attachmentId = wingId })
local after = 0
for _ in pairs(props) do after = after + 1 end
check("removing takes the prop away", last().ok == true and after == before - 1)
check("...and is kept as history, not deleted", db[wingId].removed_at and db[wingId].removed_by == "d-ana")
TriggerEvent("ncm:vehicle:dematerialized", "M-MAI", 777, "stored")
TriggerEvent("ncm:vehicle:materialized", "M-MAI", 888, 1)
local wingBack = false
for _, p in pairs(props) do if p.binding and p.binding.parentId == "888" and math.abs((p.binding.offset.y or 0) + 1.95) < 1e-9 then wingBack = true end end
check("a removed wing does not come back on the next call", not wingBack and #boundTo(888) == 2)
realPrint(("build host: %d passed, 0 failed"):format(passed))
