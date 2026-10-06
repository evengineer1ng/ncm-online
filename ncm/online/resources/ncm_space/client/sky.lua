-- ncm_space / client: the Badlands Sky Sprint on screen (L323; doc 54 §S). The NPC field arrives as server states
-- (10 Hz) and is drawn as CLIENT-LOCAL PROP CARS -- no collision, no physics, only this client -- moved with
-- `props.setTransform` and interpolated between states, exactly as ncm_world's ghost car is (a successful create id is
-- not proof it drew: `props.get` is read back and logged). A ring marks my lane. The lights and the results are the
-- server's notifications and chat (`Open77.chat` is server-only).
local function log(fmt, ...) print(("[ncm_space/client] " .. fmt):format(...)) end

local Templates = NcmCore.get("data.vehicle_templates")
local RECORDS = { "Vehicle.v_standard2_archer_hella", "Vehicle.v_sport2_quadra_type66", "Vehicle.v_sport1_herrera_outlaw",
    "Vehicle.v_standard3_chevalier_emperor", "Vehicle.v_sport2_mizutani_shion", "Vehicle.v_standard2_thorton_galena" }

local S = nil                -- { field, cars = { [id] = { propId, from, to, at } }, ring }
local gotoBlip, dropGoto = nil, nil  -- the GPS pin `/ncm.sky` drops from far away (below)


local function clear()
    if not S then return end
    for _, c in pairs(S.cars) do if c.propId then pcall(Open77.props.remove, c.propId) end end
    if S.ring then pcall(Open77.markers.remove, S.ring) end
    S = nil
end

local function spawn(c, i, p)
    local cands = Templates.candidates(RECORDS[(i - 1) % #RECORDS + 1])
    for _, model in ipairs(cands) do
        local ok, id = pcall(Open77.props.create, { model = model, position = { x = p.x, y = p.y, z = p.z }, yaw = p.yaw or 0,
            physics = "none", collision = false, visible = true, streamingRadius = 1500 })
        if ok and id then
            local okGet, got = pcall(Open77.props.get, id)
            log("NPC car %s: prop %s model %s readback %s", c.name, tostring(id), model, okGet and type(got) == "table" and "present" or "ABSENT")
            c.propId = id
            return
        end
    end
    log("NPC car %s: no prop could be created", c.name)
end

RegisterNetEvent("ncm:sky:field", function(info)
    clear()
    dropGoto()
    S = { info = info, cars = {} }
    local i = 0
    for _, f in ipairs(info.field) do
        if f.npc then
            i = i + 1
            S.cars[f.id] = { name = f.name, idx = i }
        end
    end
    for _, n in ipairs(info.npcs or {}) do
        local c = S.cars[n.id]
        if c then c.to, c.at = n, GetGameTimer(); spawn(c, c.idx, n) end
    end
    if info.mySpot then
        local ok, h = pcall(Open77.markers.create, { position = { x = info.mySpot.x, y = info.mySpot.y, z = info.mySpot.z + 0.12 },
            shape = "ring", radius = 4.5, maxDistance = 2000.0, color = { r = 255, g = 218, b = 72, a = 240 } })
        if ok then S.ring = h end
    end
end)

RegisterNetEvent("ncm:sky:lights", function(lightsS)
    if not S then return end
    if S.ring then pcall(Open77.markers.remove, S.ring); S.ring = nil end
end)

RegisterNetEvent("ncm:sky:state", function(npcs)
    if not S then return end
    local now = GetGameTimer()
    for _, n in ipairs(npcs) do
        local c = S.cars[n.id]
        if c then
            c.from, c.to, c.at = c.to or n, n, now
            if not c.propId then spawn(c, c.idx, n) end
        end
    end
end)

RegisterNetEvent("ncm:sky:result", function() clear() end)

-- `/ncm.sky` from far away: a routable GPS pin on the grid (ncm_world/client/nav.lua's recipe -- a routable blip,
-- then `blips.track`; a bare setWaypoint only if this build has no routable blips). Removed when the field arrives.
dropGoto = function()
    if gotoBlip then pcall(Open77.blips.remove, gotoBlip); gotoBlip = nil end
end

RegisterNetEvent("ncm:sky:goto", function(p)
    dropGoto()
    local ok, id = pcall(Open77.blips.create, { position = { x = p.x, y = p.y, z = p.z }, sprite = "CustomPositionVariant",
        title = tostring(p.name or "Sky Sprint"), description = "NCM: the sprint grid -- type /ncm.sky when you get there",
        active = true, routable = true })
    if ok and id then
        gotoBlip = id
        local called, tracked, why = pcall(Open77.blips.track, id)
        log("goto %s: routable pin %s, track %s %s", tostring(p.name), tostring(id), tostring(called and tracked), tostring(why))
    else
        pcall(Open77.blips.clearWaypoint)
        local okW, r = pcall(Open77.blips.setWaypoint, { x = p.x, y = p.y, z = p.z })
        log("goto %s: no routable blip (%s); setWaypoint %s %s", tostring(p.name), tostring(id), tostring(okW), tostring(r))
    end
end)
AddEventHandler("onClientResourceStop", function(name) if name == GetCurrentResourceName() then dropGoto() end end)

-- move the props between server states (100 ms apart), 20 Hz
CreateThread(function()
    while true do
        Wait(50)
        if S then
            local now = GetGameTimer()
            for _, c in pairs(S.cars) do
                if c.propId and c.to then
                    local a, b = c.from or c.to, c.to
                    local f = math.min(1, (now - (c.at or now)) / 100)
                    pcall(Open77.props.setTransform, c.propId, { position = { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f,
                        z = a.z + (b.z - a.z) * f }, yaw = b.yaw })
                end
            end
        end
    end
end)
