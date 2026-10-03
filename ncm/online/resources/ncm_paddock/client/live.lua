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
local TAPE_STRETCH = 24      -- points (and gates, and legs) per plan message: ~5 KB for 12 cars, far under the hop's limit
local portIndex, attempts = 0, 0
local surface, ready, health = nil, false, nil
local reported = nil
local current = nil          -- { raceId, byEntity = { [hash] = vehicleId } }
local traceSerial = {}       -- raceId -> generation; ending a race stops its diagnostic watcher

local function traceValue(v) return v == nil and "nil" or tostring(v) end
local function traceEngine(v)
    local n = tonumber(v)
    return n and ("%s/0x%X"):format(tostring(v), n) or traceValue(v)
end

-- KB-238: capture the OPEN//77 projection and lease transitions for this race's cars. The native crash probe
-- records engine entity hashes but not race IDs; these transition lines join the two without polling every car
-- into the log every frame. Keep the watcher alive through a stream-out and return, not just the start.
local function traceRace(m)
    local raceId = tostring(m.raceId)
    local generation = (traceSerial[raceId] or 0) + 1
    traceSerial[raceId] = generation
    CreateThread(function()
        local previous = {}
        local began = GetGameTimer()
        while traceSerial[raceId] == generation and GetGameTimer() - began < 600000 do
            for _, c in ipairs(m.cars or {}) do
                local ok, v = pcall(Open77.vehicles.get, c.vehicleId)
                local snap = ok and type(v) == "table" and v or nil
                local state = snap and table.concat({ traceValue(snap.streamed), traceValue(snap.entity),
                    traceValue(snap.engineEntity), traceValue(snap.locallyOwned), traceValue(snap.physicsOwner),
                    traceValue(snap.authorityEpoch) }, "|") or (ok and "absent" or "get_error")
                if state ~= previous[c.vehicleId] then
                    previous[c.vehicleId] = state
                    local p = snap and snap.position
                    log("TRACE race=%s t=%d slot=%s person=%s vid=%s streamed=%s entity=%s engine=%s local=%s owner=%s epoch=%s pos=%s",
                        raceId, GetGameTimer(), traceValue(c.slot), traceValue(c.personId), traceValue(c.vehicleId),
                        snap and traceValue(snap.streamed) or state, snap and traceValue(snap.entity) or "nil",
                        snap and traceEngine(snap.engineEntity) or "nil", snap and traceValue(snap.locallyOwned) or "nil",
                        snap and traceValue(snap.physicsOwner) or "nil", snap and traceValue(snap.authorityEpoch) or "nil",
                        type(p) == "table" and ("%.1f,%.1f,%.1f"):format(p.x or 0, p.y or 0, p.z or 0) or "nil")
                end
            end
            Wait(250)
        end
        if traceSerial[raceId] == generation then traceSerial[raceId] = nil end
    end)
end

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

-- The race-start warning: NCM Pace draws it natively in the HUD (no WebUI page); without the plugin, the server's
-- notification is all there is.
RegisterNetEvent("ncm:paddock.live.warn", function(m)
    if type(m) ~= "table" then return end
    local sent = send({ cmd = "banner", title = tostring(m.title or ""), detail = tostring(m.detail or ""), seconds = tonumber(m.seconds) or 0 })
    log("warning banner %s (%s s)", sent and "sent to Pace" or "not shown: no Pace plugin", tostring(m.seconds))
end)

-- The traffic null area over a start (L234): NCM Pace 0.3.0 calls the engine's EnableDynamicCrowdNullArea on this
-- client; seconds 0 takes it down. Without the plugin there is nothing to call.
RegisterNetEvent("ncm:paddock.live.area", function(m)
    if type(m) ~= "table" then return end
    local seconds = tonumber(m.seconds) or 0
    local sent = send({ cmd = "area", x = tonumber(m.x) or 0, y = tonumber(m.y) or 0, z = tonumber(m.z) or 0,
        half = tonumber(m.half) or 140, halfZ = tonumber(m.halfZ) or 30, seconds = seconds })
    log("traffic null area %s for %s (%s s)", sent and "sent to Pace" or "not raised: no Pace plugin", tostring(m.raceId), tostring(seconds))
end)

RegisterNetEvent("ncm:paddock.live.stage", function(m)
    if type(m) ~= "table" then return end
    log("staged %s: %d cars, backend %s", tostring(m.raceId), #(m.cars or {}), tostring(m.backend))
    if m.raceId and type(m.cars) == "table" then traceRace(m) end
end)

--- Drive a whole plan: map the cars, then feed Pace. `startedAt` is when the plan's first part arrived.
local function drive(m, startedAt)
    CreateThread(function()
        -- Every car is looked for at once, for up to 4 s in all -- not 4 s EACH, one after another: twelve absent cars took
        -- 48 s and the lights had gone by the time Pace heard (20:24, KB-242). A yield after every lookup: a callback's
        -- script budget is shared with everything else that tick (KB-241).
        local byEntity, cars, found = {}, {}, {}
        local want = m.cars or {}
        for _ = 1, 40 do
            local missing = 0
            for i, c in ipairs(want) do
                if not found[i] then
                    local ok, snap = pcall(Open77.vehicles.get, c.vehicleId)
                    -- 0 is truthy in Lua: a car still streaming in reports engineEntity 0 (bubbleAdd, 04:31)
                    local e = ok and type(snap) == "table" and snap.engineEntity
                    if e and e ~= 0 and tostring(e) ~= "0" then found[i] = tostring(e) else missing = missing + 1 end
                    Wait(0)
                end
            end
            if missing == 0 then break end
            Wait(100)
        end
        local mapped = {}
        for i, c in ipairs(want) do
            if found[i] then
                byEntity[found[i]] = c.vehicleId
                cars[#cars + 1] = { entity = found[i], vehicleId = c.vehicleId, speeds = c.speeds }
                mapped[#mapped + 1] = c.vehicleId
            else
                log("car %s never streamed here; the plugin cannot drive it", tostring(c.vehicleId))
            end
        end
        -- the server takes what never arrived off the grid, and calls the street run off if too few did (KB-242)
        TriggerServerEvent("ncm:paddock.live.mapped", { raceId = m.raceId, total = #want, mapped = mapped })
        current = { raceId = m.raceId, byEntity = byEntity }
        if #cars == 0 then
            log("drive.start %s: 0/%d cars reached this game; nothing for Pace to drive", tostring(m.raceId), #want)
            return
        end
        local goIn = math.max(0, (tonumber(m.goInMs) or 0) - (GetGameTimer() - startedAt))
        -- KB-223: the page hop drops large payloads silently (KB-86), so the plan goes as a TAPE (Pace 0.3.1): drive.start
        -- with the first TAPE_STRETCH points, gates and per-leg speeds, then drive.more stretches, the last marked `last`.
        -- All of it before the lights; a street plan is one stretch, exactly as before.
        local points, gates = m.points or {}, m.gates or {}
        local function slice(t, a, b) local o = {} for i = a, math.min(b, #t) do o[#o + 1] = t[i] end return o end
        local n = math.max(#points, #gates)
        local stretches = math.max(1, math.ceil(n / TAPE_STRETCH))
        -- never an empty list: an empty Lua table crosses as {} and Pace refuses a non-array (the Broadcast lesson)
        local function speedsFor(c, a, b)
            local s = slice(c.speeds or {}, a, b)
            if #s == 0 then s = { (c.speeds and c.speeds[#c.speeds]) or 20 } end
            return s
        end
        local function carsFor(a, b)
            local out = {}
            for i, c in ipairs(cars) do out[i] = (a == 1) and { entity = c.entity, vehicleId = c.vehicleId, speeds = speedsFor(c, a, b) }
                or speedsFor(c, a, b) end
            return out
        end
        local function nonEmpty(t) return #t > 0 and t or nil end
        local sent = true
        for k = 1, stretches do
            local a, b = (k - 1) * TAPE_STRETCH + 1, k * TAPE_STRETCH
            local msg
            if k == 1 then
                msg = { cmd = "drive.start", raceId = m.raceId, goInMs = goIn, points = slice(points, a, b), gates = slice(gates, a, b),
                    cars = carsFor(a, b), launch = m.launch, advanceM = m.advanceM, legs = m.legs, more = stretches > 1 }
            else
                msg = { cmd = "drive.more", raceId = m.raceId, points = nonEmpty(slice(points, a, b)), gates = nonEmpty(slice(gates, a, b)),
                    speeds = carsFor(a, b), last = k == stretches }
            end
            -- no Lua json.encode to measure it: serialising in Lua is what spends the script budget (KB-63, KB-241), and the
            -- platform serialises the send natively. One stretch per tick.
            sent = send(msg) and sent
            Wait(0)
        end
        log("drive.start %s: %d/%d cars mapped, %d points, %d gates in %d stretch(es), go in %d ms, sent=%s",
            tostring(m.raceId), #cars, #(m.cars or {}), #points, #gates, stretches, goIn, tostring(sent))
    end)
end

-- The plan arrives from the server in numbered parts (KB-223: one event for a 25-lap oval was dropped as malformed).
-- Part 1 carries the header; every part carries its stretch of points, gates and each car's per-leg speeds.
local assembling = {}        -- raceId -> { at, parts = { [k] = m } }

local function list(v) return type(v) == "table" and v or {} end

RegisterNetEvent("ncm:paddock.live.drive", function(m)
    if type(m) ~= "table" or not m.raceId then return end
    local now = GetGameTimer()
    local a = assembling[m.raceId]
    if not a then a = { at = now, parts = {}, got = 0 }; assembling[m.raceId] = a end
    local k = tonumber(m.part) or 1
    if not a.parts[k] then a.parts[k] = m; a.got = a.got + 1 end
    local n = tonumber(m.parts) or 1
    if a.got < n then return end
    assembling[m.raceId] = nil
    local head = a.parts[1]
    if not head then log("drive %s: the header part never arrived", tostring(m.raceId)) return end
    local plan = { raceId = m.raceId, goInMs = head.goInMs, launch = head.launch, advanceM = head.advanceM, legs = head.legs, points = {}, gates = {}, cars = {} }
    for i, c in ipairs(list(head.cars)) do plan.cars[i] = { vehicleId = c.vehicleId, personId = c.personId, speeds = {} } end
    for p = 1, n do
        local part = a.parts[p]
        if not part then log("drive %s: part %d of %d missing; not driving a broken plan", tostring(m.raceId), p, n) return end
        for _, x in ipairs(list(part.points)) do plan.points[#plan.points + 1] = x end
        for _, x in ipairs(list(part.gates)) do plan.gates[#plan.gates + 1] = x end
        for i, s in ipairs(list(part.speeds)) do
            local car = plan.cars[i]
            if car then for _, v in ipairs(list(s)) do car.speeds[#car.speeds + 1] = v end end
        end
    end
    drive(plan, a.at)
end)

-- ------------------------------------------------------------------------------ bubble cars on Pace (Pace 0.4.0)
-- KB-223: a race on the continuous model (L230) makes cars physical near this player. The server sends the race
-- line once, in numbered parts; it goes to Pace as a DYNAMIC plan (no cars), then every car that comes in near us
-- joins with `car.add` from the point it was set down at, and leaves with `car.remove`. Every message to Pace is
-- logged with its size: nothing about this path is silent.
local BUBBLE_STRETCH = 96
local bubbleParts, bubblePlanned, bubblePending, bubbleEntity = {}, {}, {}, {}

local function paceSend(msg)
    local okJ, s = pcall(function() return NcmCore.get("vocabulary.json").encode(msg) end)
    local sent = send(msg)
    log("-> Pace %s %s (%s bytes)%s", tostring(msg.cmd), tostring(msg.raceId), okJ and type(s) == "string" and tostring(#s) or "?",
        sent and "" or " NOT SENT: no Pace plugin connected")
    return sent
end

local function bubbleAdd(m)
    CreateThread(function()
        local hash
        for _ = 1, 40 do
            local ok, snap = pcall(Open77.vehicles.get, m.vehicleId)
            -- 0 is truthy in Lua: a car still streaming in reports engineEntity 0, and Pace refused `car.add` "0" (04:31)
            local e = ok and type(snap) == "table" and snap.engineEntity
            if e and e ~= 0 and tostring(e) ~= "0" then hash = tostring(e) break end
            Wait(100)
        end
        if not hash then log("bubble car %s never streamed here; Pace cannot drive it", tostring(m.vehicleId)) return end
        bubbleEntity[m.vehicleId] = hash
        paceSend({ cmd = "car.add", raceId = m.raceId, entity = hash, vehicleId = m.vehicleId, from = m.from, speed = m.speed, releaseMs = m.releaseMs, startMps = m.startMps })
        -- KB-238 / Pace 0.8.1: the game can re-create a car under a NEW engine entity (streamed out and back in). Pace
        -- then drove nothing -- it held the old one. Watch it while it is ours, and hand Pace the new one (`car.entity`):
        -- the same car keeps its leg and gets a fresh racing command.
        while bubbleEntity[m.vehicleId] do
            Wait(1000)
            local was = bubbleEntity[m.vehicleId]
            if not was then break end
            local ok, snap = pcall(Open77.vehicles.get, m.vehicleId)
            local e = ok and type(snap) == "table" and snap.engineEntity
            if e and e ~= 0 and tostring(e) ~= "0" and tostring(e) ~= was then
                bubbleEntity[m.vehicleId] = tostring(e)
                paceSend({ cmd = "car.entity", raceId = m.raceId, old = was, entity = tostring(e) })
                log("bubble car %s re-created here: entity %s -> %s", tostring(m.vehicleId), was, tostring(e))
            end
        end
    end)
end

RegisterNetEvent("ncm:paddock.bubble.plan", function(m)
    if type(m) ~= "table" or not m.raceId then return end
    local a = bubbleParts[m.raceId] or { parts = {}, got = 0, at = GetGameTimer() }
    bubbleParts[m.raceId] = a
    local k = tonumber(m.part) or 1
    if not a.parts[k] then a.parts[k] = m; a.got = a.got + 1 end
    local n = tonumber(m.parts) or 1
    if a.got < n then return end
    bubbleParts[m.raceId] = nil
    local head = a.parts[1]
    local points = {}
    for p = 1, n do
        local part = a.parts[p]
        if not part then log("bubble line %s: part %d of %d missing", tostring(m.raceId), p, n) return end
        for _, x in ipairs(type(part.points) == "table" and part.points or {}) do points[#points + 1] = x end
    end
    local stretches = math.max(1, math.ceil(#points / BUBBLE_STRETCH))
    local goIn = math.max(0, (tonumber(head.goInMs) or 0) - (GetGameTimer() - a.at))
    for s = 1, stretches do
        local chunk = {}
        for i = (s - 1) * BUBBLE_STRETCH + 1, math.min(s * BUBBLE_STRETCH, #points) do chunk[#chunk + 1] = points[i] end
        if s == 1 then
            -- no `cars` key at all: an empty Lua table crosses as {} and Pace wants an array; missing means none
            -- lookaheadM: aim far along the line (Pace 0.4.1). It was dropped here once, so every oval car aimed at the
            -- next 15 m point and stopped and started (05:08 Corpo, KB-223)
            paceSend({ cmd = "drive.start", raceId = m.raceId, dynamic = true, goInMs = goIn, points = chunk, gates = head.gates,
                launch = head.launch, advanceM = head.advanceM, lookaheadM = head.lookaheadM, reaimFrac = head.reaimFrac, ring = head.ring,
                legs = head.legs, loopSpline = head.loopSpline, more = stretches > 1 })
        else
            paceSend({ cmd = "drive.more", raceId = m.raceId, points = chunk, last = s == stretches })
        end
    end
    log("bubble line %s: %d points to Pace in %d stretch(es)", tostring(m.raceId), #points, stretches)
    bubblePlanned[m.raceId] = true
    for _, add in ipairs(bubblePending[m.raceId] or {}) do bubbleAdd(add) end
    bubblePending[m.raceId] = nil
end)

-- THE STREAM LINE (KB-238, owner 2026-10-01: "how close to the observable line of streaming are we?"). L229 placed the
-- distance at which this game takes an AI car only between 186 m and 573 m; the bubble's 250/300 m sits inside that
-- unknown. Every change in a race car's state HERE -- streamed in/out, a new engine entity, who simulates it -- goes to
-- the server, which measures the distance from this player and sends the line back to be written in this log
-- (`STREAMLINE`), where it survives a crash. Evidence only: nothing acts on it.
local streamWatch = {}
local function watchStream(raceId, vehicleId)
    if streamWatch[vehicleId] then return end
    streamWatch[vehicleId] = true
    CreateThread(function()
        local last, gone = nil, 0
        while streamWatch[vehicleId] do
            local ok, snap = pcall(Open77.vehicles.get, vehicleId)
            local e = ok and type(snap) == "table" and snap.engineEntity
            local state = (ok and type(snap) == "table")
                and table.concat({ tostring(snap.streamed), (e and e ~= 0 and tostring(e) ~= "0") and tostring(e) or "-",
                    tostring(snap.physicsOwner), tostring(snap.locallyOwned) }, "|") or "absent"
            if state ~= last then
                TriggerServerEvent("ncm:paddock.bubble.stream", { raceId = raceId, vehicleId = vehicleId, state = state, was = last })
                last = state
            end
            gone = (state == "absent") and gone + 1 or 0
            if gone > 240 then break end          -- a minute gone: the car was removed
            Wait(250)
        end
        streamWatch[vehicleId] = nil
    end)
end

RegisterNetEvent("ncm:paddock.bubble.streamline", function(line)
    if type(line) == "string" then log("STREAMLINE %s", line) end
end)

RegisterNetEvent("ncm:paddock.bubble.car", function(m)
    if type(m) ~= "table" or not m.raceId then return end
    if m.vehicleId and (m.op == "seat" or m.op == "add") then watchStream(m.raceId, m.vehicleId) end
    if m.op == "remove" and m.vehicleId then
        -- keep watching a little: the stream-out after a hand-back is part of the line
        CreateThread(function() Wait(5000); streamWatch[m.vehicleId] = nil end)
    end
    if m.op == "seat" then
        -- KB-238: the car is up EMPTY. Once it has stood in this game for delayMs -- past the engine's spawn physics
        -- cycle, ~1.5 s, inside which every crashing seat mount landed -- tell the server, which seats its driver.
        -- A car re-created while waiting starts the wait again.
        CreateThread(function()
            local delay, seen, since = tonumber(m.delayMs) or 3000, nil, nil
            for _ = 1, 400 do
                local ok, snap = pcall(Open77.vehicles.get, m.vehicleId)
                local e = ok and type(snap) == "table" and snap.engineEntity
                e = (e and e ~= 0 and tostring(e) ~= "0") and tostring(e) or nil
                if e ~= seen then seen, since = e, e and GetGameTimer() or nil end
                if since and GetGameTimer() - since >= delay then
                    TriggerServerEvent("ncm:paddock.bubble.settled", { raceId = m.raceId, vehicleId = m.vehicleId })
                    log("bubble car %s settled here (%d ms); asking for its driver", tostring(m.vehicleId), GetGameTimer() - since)
                    return
                end
                Wait(100)
            end
            log("bubble car %s never settled here in 40 s", tostring(m.vehicleId))
        end)
    elseif m.op == "add" then
        if bubblePlanned[m.raceId] then bubbleAdd(m)
        else bubblePending[m.raceId] = bubblePending[m.raceId] or {}; table.insert(bubblePending[m.raceId], m) end
    elseif m.op == "set" then
        -- the car's own sim pace on this stretch (Pace 0.4.4); not logged per message: it can come every 2 s per car
        local hash = bubbleEntity[m.vehicleId]
        if hash then send({ cmd = "car.set", raceId = m.raceId, entity = hash, speed = m.speed }) end
    elseif m.op == "remove" then
        local hash = bubbleEntity[m.vehicleId]
        bubbleEntity[m.vehicleId] = nil
        if hash then paceSend({ cmd = "car.remove", raceId = m.raceId, entity = hash }) end
    end
end)

RegisterNetEvent("ncm:paddock.live.end", function(m)
    if current then send({ cmd = "drive.end", raceId = current.raceId }) end
    current = nil
    if type(m) == "table" and m.raceId then traceSerial[tostring(m.raceId)] = nil end
    pcall(Open77.blips.clearWaypoint)
end)

AddEventHandler("onClientResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    if current then send({ cmd = "drive.cancel" }) end
    tearDown()
end)
