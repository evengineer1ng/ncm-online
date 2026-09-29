-- ncm_paddock / client / live -- the declarer's side of a live Paddock race (phase 5), and the Pace transport.
--
--   * declared: a GPS waypoint to the start line, because the grid only spawns if you are there;
--   * Pace:     a hidden loopback surface to the Pace plugin (`ncm/pace`, 127.0.0.1:38640-38643, the L129 pattern
--               the Scanner uses). On connect the server is told the plugin is here, so `liveBackend = auto`
--               picks it. When the server says drive, each car's OPEN//77 vehicle id is mapped to its engine
--               entity (`Open77.vehicles.get(id).engineEntity`, the same hash the Scanner proved matches
--               redscript's `EntityID.GetHash`), and the plan goes to the plugin. The plugin's gate reports come
--               back here and go to the server as evidence; the server's own timing is what decides.
local function log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    print("[ncm_paddock/live] " .. (ok and line or tostring(fmt)))
end

local PORT_BASE, PORT_SPAN = 38640, 4
local portIndex, attempts = 0, 0
local surface, ready, health = nil, false, nil
local reported = nil
local current = nil          -- { raceId, byEntity = { [hash] = vehicleId } }

local function url() return ("http://127.0.0.1:%d/pace.html"):format(PORT_BASE + portIndex) end

local function send(payload)
    if not (surface and ready) then return false end
    return (pcall(function() surface:send("ncm:pace.send", payload) end))
end

local function report(ok, version)
    if reported == ok then return end
    reported = ok
    TriggerServerEvent("ncm:paddock.live.pace", { ok = ok, version = version })
end

local function tearDown()
    if surface then pcall(function() surface:destroy() end) end
    surface, ready, health = nil, false, nil
end

local function bringUp()
    if surface then return end
    local page, why = WebUI.create({ entry = url(), layer = "hud", width = 16, height = 16, fps = 10,
        zIndex = 1, transparent = true, visible = true })
    if not page then
        attempts = attempts + 1
        portIndex = (portIndex + 1) % PORT_SPAN
        if attempts == PORT_SPAN then log("no Pace plugin on 127.0.0.1:%d-%d (%s); live races use platform AI", PORT_BASE, PORT_BASE + PORT_SPAN - 1, tostring(why)); report(false) end
        return
    end
    surface = page
    pcall(function() page:hide() end)
    page:on("ncm:pace.ready", function()
        ready, attempts = true, 0
        send({ cmd = "hello" })
    end)
    page:on("ncm:pace.closed", function()
        local was = ready
        ready = false
        if not was then tearDown(); portIndex = (portIndex + 1) % PORT_SPAN; attempts = attempts + 1
            if attempts == PORT_SPAN then report(false) end
        else report(false) end
    end)
    page:on("ncm:pace.msg", function(m)
        if type(m) ~= "table" then return end
        if m.health then
            if not health then log("Pace plugin %s on %s", tostring(m.health.version), url()) end
            health = m.health
            report(true, m.health.version)
        elseif m.gate and current then
            local g = m.gate
            local vid = current.byEntity[tostring(g.entity)]
            if vid then TriggerServerEvent("ncm:paddock.live.gate", { raceId = current.raceId, vehicleId = vid, gate = g.gate, tMs = g.tMs }) end
        elseif m.ack then
            log("pace %s: %s", tostring(m.ack.what), tostring(m.ack.detail))
        end
    end)
end

CreateThread(function()
    Wait(6000)
    while true do
        if not surface then bringUp() end
        Wait(ready and 5000 or 2000)
        if ready then send({ cmd = "health" }) end
        if attempts >= PORT_SPAN * 3 then Wait(60000); attempts = 0 end
    end
end)

-- -------------------------------------------------------------------------------------------------- race events

RegisterNetEvent("ncm:paddock.live.declared", function(m)
    if type(m) ~= "table" or type(m.start) ~= "table" then return end
    pcall(Open77.blips.clearWaypoint)
    local ok, why = pcall(Open77.blips.setWaypoint, { x = m.start.x, y = m.start.y, z = m.start.z or 0 })
    log("declared %s: waypoint to %s (%s)", tostring(m.raceId), tostring(m.name), ok and "set" or tostring(why))
end)

RegisterNetEvent("ncm:paddock.live.stage", function(m)
    if type(m) ~= "table" then return end
    log("staged %s: %d cars, backend %s", tostring(m.raceId), #(m.cars or {}), tostring(m.backend))
end)

RegisterNetEvent("ncm:paddock.live.drive", function(m)
    if type(m) ~= "table" then return end
    CreateThread(function()
        local startedAt = GetGameTimer()
        local byEntity, cars = {}, {}
        for _, c in ipairs(m.cars or {}) do
            local v
            for _ = 1, 40 do
                local ok, snap = pcall(Open77.vehicles.get, c.vehicleId)
                if ok and type(snap) == "table" and snap.engineEntity then v = snap break end
                Wait(100)
            end
            if v then
                local hash = tostring(v.engineEntity)
                byEntity[hash] = c.vehicleId
                cars[#cars + 1] = { entity = hash, vehicleId = c.vehicleId, speeds = c.speeds }
            else
                log("car %s never streamed here; the plugin cannot drive it", tostring(c.vehicleId))
            end
        end
        current = { raceId = m.raceId, byEntity = byEntity }
        local goIn = math.max(0, (tonumber(m.goInMs) or 0) - (GetGameTimer() - startedAt))
        local sent = send({ cmd = "drive.start", raceId = m.raceId, goInMs = goIn, points = m.points, gates = m.gates, cars = cars })
        log("drive.start %s: %d/%d cars mapped, go in %d ms, sent=%s", tostring(m.raceId), #cars, #(m.cars or {}), goIn, tostring(sent))
    end)
end)

RegisterNetEvent("ncm:paddock.live.end", function(m)
    if current then send({ cmd = "drive.end", raceId = current.raceId }) end
    current = nil
    pcall(Open77.blips.clearWaypoint)
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    if current then send({ cmd = "drive.cancel" }) end
    tearDown()
end)
