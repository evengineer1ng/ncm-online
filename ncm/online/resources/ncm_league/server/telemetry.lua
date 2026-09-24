-- ncm_league / server / telemetry — the stream (L57) and the incident scan (L56, P39, P43).
--
-- Clients sample their own car at 5 Hz and send batches (`ncm:telemetry`); the server keeps a ring per driver per
-- session, projects progress along the course polyline, persists chunks (one row per driver per ~10 s), and every
-- race tick scans the latest samples for car-to-car contact (zero-fault: both carry it) and object hits. When a
-- client sends nothing the server's own 1 Hz position read stands in, so nothing depends on the client.
NcmTelemetry = {}

local Core = NcmCore
local Gates = Core.get("course.gates")
local Tm = Core.get("telemetry")
local Incidents = Core.get("competition.incidents")

local function log(fmt, ...) print(("[ncm_league/telemetry] " .. fmt):format(...)) end
local now = function() return Open77.time.unix() end

local function setting(key, default)
    local s = NcmCalendar and NcmCalendar.settings
    local ok, v = pcall(function() return s and s[key] end)
    return (ok and v) or default
end

local RING_N = 60          -- 12 s at 5 Hz
local FLUSH_EVERY_S = 10
local FRESH_S = 2.0        -- a client sample newer than this beats the server's own read
local DRIFT_M = 60         -- client vs server position disagreement worth logging
local SCAN_STEP_S = 0.2    -- the client sample rate: the finest instant two drivers can both be placed at
local SCAN_WINDOW_S = 3.0  -- how much per-driver history the scan interpolates within
local SCAN_MAX_LOOKBACK_S = 2.0  -- a stalled tick never replays more than this (KB-5: no unbounded catch-up)

--- Per-session telemetry state on the race record.
function NcmTelemetry.attach(rec)
    rec.tm = {
        course = Tm.polyline(rec.s.gates),
        rings = {},        -- driverId -> Ring
        seg = {},          -- driverId -> last polyline segment (search hint)
        pending = {},      -- driverId -> samples not yet persisted
        lastClient = {},   -- driverId -> last accepted client sample (the monotonic reference; never a server stand-in)
        seq = {},          -- driverId -> chunk sequence
        lastFlush = now(),
        ledger = Incidents.Ledger.new(),
        drift = {},        -- driverId -> count
        refused = 0,
        received = 0,
        damage = {},       -- vehicleId -> last canonical damage snapshot seen during this session
        diagnostic = {},   -- driverId -> bounded candidate log counters
    }
end

local function ringOf(rec, driverId)
    if not rec.tm then NcmTelemetry.attach(rec) end
    local r = rec.tm.rings[driverId]
    if not r then r = Tm.Ring.new(RING_N); rec.tm.rings[driverId] = r end
    return r
end
NcmTelemetry.ringOf = ringOf

local function updateProgress(rec, driverId, s)
    local p = Tm.progress(rec.tm.course, s, rec.tm.seg[driverId])
    rec.tm.seg[driverId] = p.seg
    rec.progressM[driverId] = p.m
    local entrant = rec.s.entrants[driverId]
    local incSec = entrant and (entrant.incidentSec or 0) or 0
    rec.correctedM[driverId] = Tm.correctedM(p.m, incSec, Tm.avgSpeed(ringOf(rec, driverId), 10))
    return p
end

--- The server's own 1 Hz read; used when the client is silent (or as a cross-check when it is not).
function NcmTelemetry.serverSample(rec, driverId, pos, t)
    if not rec.tm then NcmTelemetry.attach(rec) end
    local ring = ringOf(rec, driverId)
    local last = ring:last(1)
    if last and last.client and (t - (last.t or 0)) < FRESH_S then
        -- client is streaming; cross-check only
        local d = math.sqrt((pos.x - last.x) ^ 2 + (pos.y - last.y) ^ 2)
        if d > DRIFT_M then
            rec.tm.drift[driverId] = (rec.tm.drift[driverId] or 0) + 1
            if rec.tm.drift[driverId] % 10 == 1 then log("drift driver=%s client vs server %.0f m (#%d)", driverId, d, rec.tm.drift[driverId]) end
        end
        return
    end
    local prev = last
    local v = 0
    if prev and t > (prev.t or 0) then v = math.sqrt((pos.x - prev.x) ^ 2 + (pos.y - prev.y) ^ 2) / (t - prev.t) end
    ring:push({ t = t, x = pos.x, y = pos.y, z = pos.z or 0, v = v, server = true })
    updateProgress(rec, driverId, pos)
end

--- A client batch. Validates, pushes, projects; persists in chunks.
function NcmTelemetry.ingest(rec, driverId, raw, t)
    if not rec.tm then NcmTelemetry.attach(rec) end
    local ring = ringOf(rec, driverId)
    local samples, why = Tm.decodeBatch(raw, rec.tm.lastClient[driverId])
    if NcmScenario and NcmScenario.traced[driverId] then
        local first = type(raw) == "table" and raw[1] or nil
        log("TRACE telemetry driver=%s batch=%d ok=%s %s first=%s", driverId:sub(1, 8), type(raw) == "table" and #raw or -1, tostring(samples ~= nil), tostring(why or ""),
            (type(first) == "table") and ("t=%.1f %.0f,%.0f v=%.1f"):format(tonumber(first[1]) or 0, tonumber(first[2]) or 0, tonumber(first[3]) or 0, tonumber(first[5]) or 0) or "?")
    end
    if not samples then
        rec.tm.refused = rec.tm.refused + 1
        if rec.tm.refused % 20 == 1 then log("telemetry refused driver=%s reason=%s (#%d)", driverId, tostring(why), rec.tm.refused) end
        return false, why
    end
    for _, s in ipairs(samples) do
        s.client = true
        ring:push(s)
        local pend = rec.tm.pending[driverId] or {}
        rec.tm.pending[driverId] = pend
        pend[#pend + 1] = s
    end
    rec.tm.received = rec.tm.received + #samples
    -- Gate capture from the stream: a segment between consecutive samples that crosses the driver's next line is a
    -- crossing whether or not the client reported it (no reverse crossings, no proximity luck — owner QA batch 2).
    local prevSample = rec.tm.lastClient[driverId]
    local r = rec.s.entrants[driverId]
    if r and NcmRace.streamGate then
        local list = {}
        if prevSample then list[1] = prevSample end
        for _, s in ipairs(samples) do list[#list + 1] = s end
        rec.tm.originOf = rec.tm.originOf or {}
        if not rec.tm.originOf[driverId] and samples[1] then rec.tm.originOf[driverId] = { x = samples[1].x, y = samples[1].y } end
        for i = 2, #list do
            local nextIndex = ((r.run and r.run.progress) or r.progress or 0) + 1
            local g = rec.s.gates[nextIndex]
            local phaseOk = rec.s.phase == "running" or rec.s.phase == "finishing" or rec.s.phase == "open"
            if g and phaseOk and (rec.kind ~= "race" or r.state == "racing") then
                local a, b = list[i - 1], list[i]
                local f = Gates.crossFraction(g, a, b)
                local hit = f ~= nil
                -- the race start also counts as "left the mark" (30 m from where the car sat at the lights), like the client rule
                if not hit and rec.kind == "race" and nextIndex == 1 and rec.tm.originOf[driverId] then hit = Gates.startedFrom(rec.tm.originOf[driverId], b, g.leaveM); f = 1 end
                if hit then
                    -- KB-23: date the crossing, not the packet. `t` is when this batch reached the server -- one
                    -- value for all five samples in it, up to a second after the car actually crossed. The swept
                    -- segment says where between a and b the line was cut, so it says when.
                    local at = t
                    if a.t and b.t and b.t >= a.t then at = a.t + (b.t - a.t) * f end
                    NcmRace.streamGate(rec, driverId, nextIndex, { x = b.x, y = b.y, z = b.z }, at)
                end
            end
        end
    end
    -- rolling start: the formation speed cap is judged from the stream (one incident per driver, kernel rule)
    if rec.kind == "race" and rec.kernel.pace and rec.s.rules.start == "rolling" and not rec.s.rollingGreenAt then
        for _, smp in ipairs(samples) do
            local ev = rec.kernel.pace(rec.s, driverId, smp.v or 0, t)
            if ev and #ev > 0 then NcmRace.handle(rec, ev, t) end
        end
    end
    rec.tm.lastClient[driverId] = samples[#samples]
    updateProgress(rec, driverId, samples[#samples])
    if setting("telemetryDebug", 0) == 1 then
        local last = samples[#samples]
        log("telemetry driver=%s n=%d t=%.1f v=%.1f g=%s progress=%.0fm", driverId, #samples, last.t, last.v or 0, tostring(last.g), rec.progressM[driverId] or 0)
    end
    if t - rec.tm.lastFlush >= FLUSH_EVERY_S then NcmTelemetry.flush(rec, false) end
    return true
end

--- Persist pending samples as chunks (one INSERT per driver).
function NcmTelemetry.flush(rec, final)
    if not rec.tm then return end
    rec.tm.lastFlush = now()
    if setting("telemetryPersist", 1) ~= 1 or not MySQL.isReady() then rec.tm.pending = {}; return end
    for driverId, list in pairs(rec.tm.pending) do
        if #list > 0 and (final or #list >= 25) then
            local seq = (rec.tm.seq[driverId] or 0) + 1
            rec.tm.seq[driverId] = seq
            local parts = {}
            for i, s in ipairs(list) do
                parts[i] = ("[%.2f,%.1f,%.1f,%.1f,%.1f,%s,%s,%s]"):format(s.t, s.x, s.y, s.z or 0, s.v or 0, tostring(s.g or 0), s.og == false and "0" or "1", tostring(s.h or 1))
            end
            local from, to = list[1].t, list[#list].t
            local n = #list
            rec.tm.pending[driverId] = {}
            pcall(function()
                MySQL.insert.await("INSERT INTO telemetry_chunk (session_id, ncm_driver_id, seq, t_from, t_to, n, samples_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    { rec.s.sessionId, driverId, seq, from, to, n, "[" .. table.concat(parts, ",") .. "]" })
            end)
        end
    end
end

--- Every race tick: scan for contacts (racing entrants only).
---
--- KB-34: this used to compare each driver's newest sample against every other driver's newest sample. Those are
--- taken by different clients at different moments — up to the 3 s freshness tolerance apart, and routinely a
--- fifth of a second apart through ordinary batching and jitter. At racing speed that is tens of metres, so two
--- cars genuinely touching almost never read as within contactM, and the object detector's "nobody nearby" test
--- cleared just as wrongly. Every contact in the first two-human race was therefore filed as scenery.
---
--- Instead we walk a common clock across the interval since the last scan at the client sample rate, and at each
--- instant interpolate every driver onto it. A driver with no bracketing samples at that instant is absent, not
--- assumed stationary, so the neighbour test refuses instead of mis-clearing.
function NcmTelemetry.scan(rec, t)
    if not rec.tm then return end
    local s = rec.s
    if s.phase ~= "running" and s.phase ~= "finishing" then return end
    local rules = rec.rules and rec.rules.incidents or nil
    local resolvedRules = Incidents.rules(rules)
    local step = setting("incidentScanStepSec", SCAN_STEP_S)
    local from = rec.tm.lastScanAt or (t - step)
    if (t - from) > SCAN_MAX_LOOKBACK_S then from = t - SCAN_MAX_LOOKBACK_S end
    rec.tm.lastScanAt = t

    -- sorted so the order of pair checks (and so which contact dedupes first) does not depend on table iteration
    local ids, windows = {}, {}
    for driverId, r in pairs(s.entrants) do
        if r.state == "racing" then
            local w = ringOf(rec, driverId):window(SCAN_WINDOW_S)
            if #w > 0 then ids[#ids + 1] = driverId; windows[driverId] = w end
        end
    end
    table.sort(ids)
    if #ids == 0 then return end

    local at = t
    for instant = from + step, t, step do
        at = instant
        local here = {}
        for _, driverId in ipairs(ids) do
            local cur = Tm.sampleAt(windows[driverId], instant)
            if cur then here[driverId] = { driverId = driverId, prev = Tm.sampleAt(windows[driverId], instant - step), cur = cur } end
        end

        -- car <-> car (each pair once; both records applied)
        for i = 1, #ids do
            for j = i + 1, #ids do
                local a, b = here[ids[i]], here[ids[j]]
                if a and b then
                    local ra, rb = Incidents.carCar(a, b, rules)
                    if ra then
                        local la = rec.tm.ledger:add(a.driverId, ra, rules)
                        local lb = rec.tm.ledger:add(b.driverId, rb, rules)
                        if la then NcmRace.incident(rec, a.driverId, la, t) end
                        if lb then NcmRace.incident(rec, b.driverId, lb, t) end
                    end
                end
            end
        end

        -- car <-> object (a hard stop with every other car accounted for and none of them alongside)
        for i = 1, #ids do
            local me = here[ids[i]]
            if me and me.cur and me.cur.client then
                local neighbours = {}
                for j = 1, #ids do
                    if j ~= i then
                        -- an absent driver stays absent: Incidents.object refuses when it cannot place someone
                        local other = here[ids[j]]
                        neighbours[#neighbours + 1] = other and other.cur or { t = nil }
                    end
                end
                -- Judge the whole authored object window, not only the last 200 ms scan step. A real barrier
                -- impact often sheds its speed over two or three samples; the old step comparison missed it.
                local impactPrev = Tm.sampleAt(windows[ids[i]], instant - resolvedRules.objectWindowSec) or me.prev
                local hit = Incidents.object(impactPrev, me.cur, neighbours, rules)
                if hit then
                    hit.signal = hit.signal or "motion_window"
                    local l, why = rec.tm.ledger:add(me.driverId, hit, rules)
                    log("candidate session=%s driver=%s type=object signal=%s speed=%.1f dv=%.1f accepted=%s reason=%s episode=%s",
                        tostring(s.sessionId):sub(1, 8), me.driverId:sub(1, 8), hit.signal, me.cur.v or 0,
                        hit.dv or 0, tostring(l ~= nil), tostring(why or "accepted"), l and tostring(#rec.tm.ledger.byDriver[me.driverId]) or "-")
                    if l then NcmRace.incident(rec, me.driverId, l, t) end
                end
            end
        end
    end
    -- resume from the last instant actually walked, so a partial step is not skipped
    rec.tm.lastScanAt = at
end

local function damageSnapshot(v)
    return { health = v.health, bodyDamage = v.bodyDamage, brokenGlass = v.brokenGlass,
        brokenLights = v.brokenLights, tires = v.tires }
end

local function activeDriverForVehicle(vehicleId)
    for _, rec in pairs(NcmRace.sessions or {}) do
        if rec.tm and (rec.s.phase == "running" or rec.s.phase == "finishing") then
            for driverId, pid in pairs(rec.playerOf or {}) do
                local entrant = rec.s.entrants[driverId]
                if entrant and entrant.state == "racing" then
                    local ok, seat = pcall(Open77.players.getVehicleSeat, pid)
                    local seated = ok and type(seat) == "table" and (seat.vehicleId or seat.vehicle or seat.id)
                    if tostring(seated) == tostring(vehicleId) then return rec, driverId, pid end
                end
            end
        end
    end
end

-- Build .87 exposes canonical damage changes, but not the collider/object that caused them. Treat a damage
-- change as object evidence only when the affected vehicle belongs to a currently racing entrant and no other
-- racer is close enough for this to plausibly be car-to-car contact.
AddEventHandler("onVehicleDamageChanged", function(vehicleId, revision)
    local rec, driverId = activeDriverForVehicle(vehicleId)
    if not rec or (NcmScenario and NcmScenario.overrides.incidents == false) then return end
    local ok, vehicle = pcall(Open77.vehicles.get, tonumber(vehicleId) or vehicleId)
    if not ok or type(vehicle) ~= "table" then return end
    local cur = damageSnapshot(vehicle)
    local prev = rec.tm.damage[vehicleId]
    rec.tm.damage[vehicleId] = cur
    local pos = { x = vehicle.x, y = vehicle.y, z = vehicle.z }
    local speed = tonumber(vehicle.speed) or ((tonumber(vehicle.speedKph) or 0) / 3.6)
    local closeDriver = nil
    for otherId, other in pairs(rec.s.entrants) do
        if otherId ~= driverId and other.state == "racing" then
            local smp = ringOf(rec, otherId):last(1)
            if smp and pos.x and pos.y then
                local dx, dy = smp.x - pos.x, smp.y - pos.y
                if dx * dx + dy * dy <= 8 * 8 then closeDriver = otherId; break end
            end
        end
    end
    local identity = NcmCollection and NcmCollection.vehicleInfo and NcmCollection.vehicleInfo(vehicleId) or nil
    if closeDriver then
        log("candidate session=%s driver=%s asset=%s vehicle=%s type=damage accepted=false reason=near_competitor other=%s revision=%s",
            rec.s.sessionId:sub(1, 8), driverId:sub(1, 8), tostring(identity and identity.assetId or "-"),
            tostring(vehicleId), closeDriver:sub(1, 8), tostring(revision))
        return
    end
    local hit, why = Incidents.damage(prev, cur, speed, pos, now(), rec.rules and rec.rules.incidents)
    if not hit then
        log("candidate session=%s driver=%s asset=%s vehicle=%s type=damage accepted=false reason=%s revision=%s",
            rec.s.sessionId:sub(1, 8), driverId:sub(1, 8), tostring(identity and identity.assetId or "-"),
            tostring(vehicleId), tostring(why), tostring(revision))
        return
    end
    local accepted, reason = rec.tm.ledger:add(driverId, hit, rec.rules and rec.rules.incidents)
    log("candidate session=%s driver=%s asset=%s vehicle=%s type=object signal=vehicle_damage speed=%.1f band=%d accepted=%s reason=%s episode=%s revision=%s",
        rec.s.sessionId:sub(1, 8), driverId:sub(1, 8), tostring(identity and identity.assetId or "-"),
        tostring(vehicleId), speed, hit.band or 0, tostring(accepted ~= nil), tostring(reason or "accepted"),
        accepted and tostring(#rec.tm.ledger.byDriver[driverId]) or "-", tostring(revision))
    if accepted then NcmRace.incident(rec, driverId, accepted, now()) end
end)

RegisterNetEvent("ncm:telemetry", function(sessionId, batch)
    local pid = tonumber(source) or 0
    local rec = NcmRace.sessions[tostring(sessionId or "")]
    if not rec then return end
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then return end
    local entrant = rec.s.entrants[driver.ncmDriverId]
    if not entrant then return end
    NcmTelemetry.ingest(rec, driver.ncmDriverId, batch, now())
end)

RegisterCommand("ncm.telemetry", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    for sid, rec in pairs(NcmRace.sessions) do
        if rec.tm then
            local parts = {}
            for d, ring in pairs(rec.tm.rings) do
                local last = ring:last(1)
                parts[#parts + 1] = ("%s: %d samples, last %s %.0fm"):format(d:sub(1, 8), ring.count, last and (last.client and "client" or "server") or "-", rec.progressM[d] or 0)
            end
            log("session=%s received=%d refused=%d | %s", sid, rec.tm.received, rec.tm.refused, table.concat(parts, " | "))
        end
    end
end, false)
