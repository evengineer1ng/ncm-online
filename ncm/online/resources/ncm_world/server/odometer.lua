-- ncm_world / server / odometer -- how far THIS machine has actually travelled.
--
-- **Mileage belongs to the assetId.** Not to the player, not to the model, not to the ephemeral runtime
-- entity, not to the current ownership period, not to the session. Selling a car does not reset it. CALLing
-- it back does not reset it. A restart does not reset it. Repainting it does not reset it. The machine is
-- the machine (addendum section 10).
--
-- ---------------------------------------------------------------------------------------------
-- Where the distance comes from, and why not from the client
-- ---------------------------------------------------------------------------------------------
--
-- `Open77.vehicles.get(vehicleId)`, read on the server at 1 Hz. NCM already has a 5 Hz client telemetry
-- stream, and it is deliberately NOT used here: it is sampled by the player's own machine, it only runs
-- during races, and this number may one day have irreversible consequences for someone's property. A future
-- terminal-failure mechanic must not be built on a figure a client can edit (addendum section 11).
--
-- It measures the VEHICLE's movement while somebody is aboard -- not the driver's. Sampling the player
-- would count them walking around their own parked car, and an empty vehicle being shoved or towed is not
-- travelling.
--
-- The server read is authoritative but coarse. One sample per second means a straight line between positions,
-- so a tight corner is very slightly under-measured. That is the honest trade and it is stated here rather
-- than hidden: this is an odometer, not a survey instrument.
--
-- ---------------------------------------------------------------------------------------------
-- What is deliberately NOT counted
-- ---------------------------------------------------------------------------------------------
--
--   * Anything while nobody is aboard, or while the vehicle is not an identified NCM asset.
--   * Any segment where the asset changed between samples.
--   * Any gap longer than `MAX_GAP_S` (a stall, a reconnect, a streaming pause).
--   * Any segment implying more than `MAX_SPEED_MPS` -- which is how teleports, CALL materialisation at a new
--     place, administrative relocation and streaming jumps are all rejected by one rule rather than four
--     special cases (addendum section 13).
--
-- **Any car that IS an asset accrues, whatever spawned it** (owner, 2026-09-23: *"race grid cars should
-- accrue mileage though any car should"*). Two sources feed one sampler: the CALL/access map, and a
-- registration event any resource may fire. So a materialisation path added later needs no change here -- it
-- announces its asset and the kilometres follow.
--
-- What cannot accrue is a vehicle that is not a persistent machine: NCX invitational TEAM CARS are issued
-- equipment (`issued_vehicle`, a record and a number, no assetId), and ordinary traffic is not NCM's at all.
-- There is no asset for their distance to belong to. Whether team cars should become real assets is a design
-- question, not something to fake here.
local Identity = NcmCore.get("data.vehicle_identity")

local function log(fmt, ...) print(("[ncm_world/odometer] " .. fmt):format(...)) end
local function now() return Open77.time.unix() end

local SAMPLE_MS = 1000
--- Checkpoint after this much unwritten distance, or this long, whichever comes first. A crash therefore
--- costs at most one checkpoint's worth of progress -- bounded, documented, and far cheaper than writing the
--- database every metre (addendum section 12).
local CHECKPOINT_M = 250
local CHECKPOINT_S = 60

local last = {}      -- assetId -> { assetId, x, y, z, at }  (the machine's last observed place)
local pending = {}   -- assetId -> { metres, since }
local rejected = {}  -- reason -> count, for the periodic diagnostic line
local stored = {}    -- assetId -> odometer_m as durably recorded, read once per materialisation
local card = {}      -- assetId -> { name, ordinal }, likewise
local shown = {}     -- pid -> the assetId last published, so the bag is written only when it changes
local tracked = {}   -- vehicleId -> { assetId, pid } registered by any materialisation path

-- ---------------------------------------------------------------------------------------------------
-- TYRE TEMPERATURE (`L159`) -- here, because this loop already knows everything it needs
-- ---------------------------------------------------------------------------------------------------
--
-- **Why the odometer hosts a thermal model.** It already polls every live vehicle once a second, already
-- resolves speed with a runtime availability check and a positional fallback, already reads position, and
-- is already keyed by `assetId`. A tyre model needs exactly those four things and nothing else, so putting
-- it anywhere else would mean a second poll of the same vehicles for the same fields.
--
-- The alternatives were both worse:
--
--   * **The Carrier** holds ONE bound body at a time and has no per-entity map, so it structurally cannot
--     keep a temperature for a car the driver just stepped out of. It also dies with the process.
--   * **The client** has richer data -- throttle, brake, slip, at 20 Hz -- and every bit of it is
--     `client_attested`. A number the client computes that then feeds back into grip is forgeable for 15
--     percent of a car's cornering, which is precisely the property `IDEA-458` says must stay server-side.
--
-- Temperature belongs to the MACHINE, like mileage and like fitted Parts. Leaving the car does not reset
-- it; it keeps cooling in real time, and a car found ten minutes later is stone cold.
NcmOdometer = {}

local Thermal = NcmCore.get("parts.thermal")

local thermal = {}   -- assetId -> { tempC, at, headingRad }

--- World conditions for the thermal model. Weather and time of day both act on AMBIENT rather than on grip
--- directly, which is why neither needs a lever of its own: a cold night makes a tyre harder to warm, and
--- that is the real mechanism rather than a flat penalty for driving after dark.
local function conditions()
    local wetness, seconds
    if NcmMachine and NcmMachine.state then
        local c = NcmMachine.state()
        if type(c) == "table" then wetness, seconds = c.wetness, c.secondsOfDay end
    end
    return { wetness = wetness, secondsOfDay = seconds }
end

--- Cornering load, in m/s^2, from what a ONE HERTZ poll can honestly see.
---
--- ---------------------------------------------------------------------------------------------------
--- WHY THERE ARE TWO ESTIMATORS AND NOT ONE
--- ---------------------------------------------------------------------------------------------------
---
--- The obvious method -- change in heading over the interval, times speed -- has a failure mode that a
--- live drive found immediately: **it cancels under oscillation.** A weaving car swings left, then right,
--- and lands the next sample pointing almost where it started. The yaw rate was high the whole time and
--- the NET heading change is near zero, so the model saw a car travelling in a straight line and kept its
--- tyres stone cold. Sustained donuts have a related problem: past pi radians in one sample the wrap is
--- genuinely ambiguous and a fast spin reads as a slow one.
---
--- The second estimator cannot cancel, because it measures a DISTANCE rather than an angle. A car that is
--- turning covers more PATH than DISPLACEMENT: drive one second at 10 m/s in a straight line and you are
--- 10 m away, but weave and you are 9 m away having still travelled 10 m of road. The deficit between the
--- two is a direct measure of how much the car is not going straight, and it survives any amount of
--- direction reversal inside the sample.
---
--- Inverting it: for an arc turned through `theta` in one sample, `displacement/path = sin(theta/2) /
--- (theta/2)`, which for moderate angles is about `1 - theta^2 / 24`. So `theta ~= sqrt(24 * deficit)`.
--- A weave is not a circular arc, but it gives the honest "the car turned about this much" answer that a
--- signed heading delta throws away.
---
--- **Take whichever is larger.** Heading is the better estimator for a long steady corner, where the
--- deficit over one second is tiny; the path deficit is the better one for weaving, donuts and anything
--- that changes direction faster than the sample rate. Neither is right everywhere and the maximum is
--- honest about that -- it reports the most cornering this poll can PROVE, not the most it can imagine.
local function lateralAccel(entry, prev, cur, dt)
    if dt <= 0 or not cur then return 0 end
    local speed = cur.speedMps or 0
    if speed < 1.0 then return 0 end

    local state = thermal[entry.assetId]

    -- ---- estimator one: net heading change
    local byHeading = 0
    local heading = cur.headingRad
    if heading then
        local previous = state and state.headingRad
        if state then state.headingRad = heading end
        if previous then
            local delta = heading - previous
            while delta > math.pi do delta = delta - 2 * math.pi end
            while delta < -math.pi do delta = delta + 2 * math.pi end
            byHeading = math.abs(delta / dt) * speed
        end
    end

    -- ---- estimator two: path travelled versus ground covered
    local byDeficit = 0
    if prev then
        local dx, dy = cur.x - prev.x, cur.y - prev.y
        local displacement = math.sqrt(dx * dx + dy * dy)
        -- **The AVERAGE speed across the interval, not the instantaneous one at its end.** Using `speed`
        -- here would make hard acceleration in a dead straight line read as cornering: the car ends the
        -- second faster than it spent it, so `speed * dt` overstates the path and the surplus looks
        -- exactly like a turn. That would have heated tyres on a drag strip.
        local avg = ((prev.speedMps or speed) + speed) * 0.5
        local path = avg * dt
        if path > 0.5 then
            local ratio = displacement / path
            -- A deadband, because position and speed come from different samples and never agree perfectly.
            -- Below two percent this is measurement noise, and noise times thirty metres a second would be
            -- a violent phantom corner on an empty straight.
            local deficit = 1.0 - ratio - 0.02
            if deficit > 0 then
                -- Past ~0.45 the chord approximation has broken down entirely -- a tight donut, or a spin
                -- on the spot. Cap it rather than let the inversion run away.
                if deficit > 0.45 then deficit = 0.45 end
                local theta = math.sqrt(24 * deficit)
                byDeficit = (theta / dt) * avg
            end
        end
    end

    return math.max(byHeading, byDeficit)
end

--- Advance one Machine's tyre temperature. Called for every sampled asset, driven or not.
-- Set by `thermalStep` and read by `step` immediately afterwards, single-threaded per sample.
local observedLateral

local function thermalStep(entry, prev, cur, t)
    local assetId = entry.assetId
    local state = thermal[assetId]
    local ambient = Thermal.ambient(conditions())
    if not state then
        thermal[assetId] = { tempC = Thermal.initial(conditions()), at = t }
        return
    end
    -- **Measured dt, never an assumed tick.** `SAMPLE_MS` is a minimum wait, not a period; a hitched
    -- server that cooled a tyre by a whole second when 300 ms had passed would drift slowly and
    -- invisibly, which is the worst way for a model to be wrong.
    local dt = t - (state.at or t)
    state.at = t
    if dt <= 0 then return end

    local speed = cur and (cur.speedMps or 0) or 0
    -- Derived once and RETURNED, so the observation producer can record the same cornering load the tyre
    -- model just felt rather than computing a second, subtly different one from the same two samples.
    local lateral = cur and lateralAccel(entry, prev, cur, dt) or 0
    local load = cur and Thermal.load(speed, lateral) or 0
    observedLateral = cur and lateral or nil

    -- ----------------------------------------------------------------- what the model actually sees
    --
    -- **Added after two live drives where the gauge stayed cold and there was no way to tell why.** The
    -- first was the model's equilibrium; the second is still open, and the difference between "the car is
    -- barely cornering", "the yaw rate is aliasing at 1 Hz" and "lateral is reading zero" is invisible
    -- from a grip number alone -- they all look like a cold tyre.
    --
    -- Every five seconds while occupied, so a sixty-second drive leaves twelve readable lines and a
    -- parked server writes nothing. The owner cannot type commands while driving; this needs no typing.
    if cur and speed > 1.0 then
        state.diagAt = state.diagAt or 0
        if t - state.diagAt >= 5 then
            state.diagAt = t
            -- `track` and `air` are both printed because the whole point of `L160` is that they are
            -- different numbers, and a diagnostic that showed one of them could not show that.
            local world = conditions()
            log("thermal asset=%s v=%.1f m/s lat=%.1f m/s2 load=%.3f T=%.1fC pos=%+.2f "
                .. "track=%.1fC air=%.1fC surf=x%.3f",
                tostring(assetId):sub(-6), speed, lateral, load, state.tempC,
                Thermal.position(state.tempC) or 0, ambient, Thermal.airTemperature(world),
                Thermal.surfaceMultiplier(ambient))
        end
    end

    if dt > Thermal.MAX_STEP_SECONDS and load <= 0 then
        -- A long gap with nothing happening: closed-form, so a car parked for ten minutes ends up at
        -- ambient rather than five seconds cooler.
        state.tempC = Thermal.cool(state.tempC, ambient, dt)
    else
        state.tempC = Thermal.step(state.tempC, load, ambient, dt, speed)
    end
end

--- The current tyre temperature for a Machine, cooled forward to NOW.
---
--- Lazily settled rather than ticked: an asset nobody is sampling still has a correct temperature the
--- moment somebody asks, and that costs one exponential instead of a timer per car.
function NcmOdometer.tyreTemperature(assetId)
    local state = thermal[assetId]
    if not state then return nil end
    local elapsed = now() - (state.at or now())
    if elapsed > 2 then return Thermal.cool(state.tempC, Thermal.ambient(conditions()), elapsed) end
    return state.tempC
end

--- Where a live vehicle is, from the server's own snapshot. Two shapes are accepted because
--- `vehicle_access.lua` already has to accept both.
--- The vehicle's own speed in m/s, if this build reports one. Two spellings, same as the client telemetry
--- has to accept.
local function speedOf(snap)
    if type(snap) ~= "table" then return nil end
    local v = tonumber(snap.speed)
    if v then return math.abs(v) end
    local kph = tonumber(snap.speedKph)
    if kph then return math.abs(kph) / 3.6 end
    return nil
end

local loggedFields = false
--- Once per boot, say exactly what the server can see on a vehicle. The odometer's accuracy depends on
--- whether `speed` is among them, so this is the first thing to check if mileage ever looks wrong again.
local function noteFields(snap)
    if loggedFields or type(snap) ~= "table" then return end
    loggedFields = true
    local keys = {}
    for k, v in pairs(snap) do if type(v) ~= "table" then keys[#keys + 1] = k .. "=" .. tostring(v) end end
    table.sort(keys)
    log("vehicle snapshot fields: %s", table.concat(keys, " "))
    log("speed reading %s -- %s", speedOf(snap) and "AVAILABLE" or "ABSENT",
        speedOf(snap) and "jitter is filtered by speed" or "falling back to the positional floor")
end

--- The vehicle's facing in radians, from the snapshot's own `heading` (degrees), with `yaw` as the second
--- spelling. Absent rather than guessed when neither is present: a tyre model that invents a yaw rate
--- would heat a tyre on a straight road.
local function headingOf(snap)
    if type(snap) ~= "table" then return nil end
    local deg = tonumber(snap.heading) or tonumber(snap.yaw)
    if not deg then return nil end
    return math.rad(deg)
end

local function positionOf(snap)
    if type(snap) ~= "table" then return nil end
    local p = snap.position or { x = snap.x, y = snap.y, z = snap.z }
    if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
    return p
end

--- Is anybody aboard? **An empty car is not travelling**, whatever is happening to it. This is what keeps
--- towing, shoving and physics drift out of the odometer, and it is the same occupancy test the CALL
--- reclaim path already uses (addendum section 11).
local function occupied(snap)
    return type(snap) == "table" and type(snap.occupants) == "table" and next(snap.occupants) ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Bounded diagnostics
-- ---------------------------------------------------------------------------------------------
--
-- One asset, one window, one line per sample. Deliberately not a permanent per-sample log: the point is to
-- answer "where did those metres come from" during a controlled run and then stop.
local traceAsset, traceUntil, traceTotals = nil, 0, nil

local function trace(assetId, prev, cur, seg)
    if traceAsset ~= assetId or now() > traceUntil then return end
    local dt = cur.at - prev.at
    local raw = math.sqrt((cur.x - prev.x) ^ 2 + (cur.y - prev.y) ^ 2 + (cur.z - prev.z) ^ 2)
    traceTotals.samples = traceTotals.samples + 1
    traceTotals.raw = traceTotals.raw + raw
    if seg.accept then traceTotals.accepted = traceTotals.accepted + seg.metres
    else traceTotals.rejected = traceTotals.rejected + raw end
    log("trace %s dt=%.1f raw=%.2fm accepted=%.2fm speed=%s reason=%s | totals raw=%.1f acc=%.1f rej=%.1f n=%d",
        tostring(assetId):sub(1, 8), dt, raw, seg.accept and seg.metres or 0,
        cur.speedMps and ("%.1fm/s"):format(cur.speedMps) or "n/a", seg.reason,
        traceTotals.raw, traceTotals.accepted, traceTotals.rejected, traceTotals.samples)
end

--- Register a live vehicle as a persistent machine, so its travel is recorded against that asset.
--- Any resource may announce one: `TriggerEvent("ncm:odometer.track", assetId, vehicleId, playerId)`.
function NcmOdometer.track(assetId, vehicleId, pid)
    if type(assetId) ~= "string" or assetId == "" or vehicleId == nil then return false end
    tracked[vehicleId] = { assetId = assetId, pid = tonumber(pid) or nil }
    return true
end

function NcmOdometer.untrack(vehicleId)
    if vehicleId == nil then return end
    local reg = tracked[vehicleId]
    tracked[vehicleId] = nil
    -- Memory only. The durable running best lives in `vehicle_knowledge_evidence` and the next sample of
    -- this machine reads it back.
    if reg and NcmObservation and NcmObservation.forget then
        pcall(NcmObservation.forget, reg.assetId)
    end
end

--- Everything to sample this tick: the access map plus anything registered. Keyed by vehicleId so a car
--- reachable through both is measured once.
local function watchlist()
    local seen, out = {}, {}
    if NcmVehicleAccess and NcmVehicleAccess.liveAssets then
        local ok, live = pcall(NcmVehicleAccess.liveAssets)
        if ok and type(live) == "table" then
            for _, e in ipairs(live) do
                if not seen[e.vehicleId] then seen[e.vehicleId] = true; out[#out + 1] = e end
            end
        end
    end
    for vehicleId, reg in pairs(tracked) do
        if not seen[vehicleId] then
            seen[vehicleId] = true
            out[#out + 1] = { assetId = reg.assetId, vehicleId = vehicleId, pid = reg.pid }
        end
    end
    return out
end

--- The durable reading and the machine's identity, read once when it appears rather than every second.
local function describe(assetId)
    if stored[assetId] then return end
    stored[assetId] = 0
    local ok, row = pcall(function()
        return MySQL.single.await([[SELECT odometer_m, vehicle_key, production_ordinal
            FROM vehicle_asset WHERE asset_id = ?]], { assetId })
    end)
    if ok and type(row) == "table" then
        stored[assetId] = tonumber(row.odometer_m) or 0
        local entry = row.vehicle_key and NcmCore.get("data.vehicle_catalogue").byKey(row.vehicle_key) or nil
        card[assetId] = { name = entry and entry.displayName or row.vehicle_key,
                          ordinal = tonumber(row.production_ordinal) }
    end
end

--- Publish what this driver's instrument cluster should read. **Bound to the assetId**, so swapping machines
--- swaps the reading and nothing about a driver, a session or a race enters into it (P.S. section 8).
local function publish(pid, assetId)
    if not pid or pid <= 0 then return end
    if shown[pid] == assetId then
        -- Same machine: refresh the number only, at most once a second.
        if not assetId then return end
    end
    -- IDEA-236/IDEA-303: the LEAGUE needs to know which machine a driver is sitting in, and cannot see it.
    -- `ncm_world` and `ncm_league` are separate Lua VMs, so this map is simply invisible over there. Announce
    -- the change instead -- the inverse of the `ncm:odometer.track` event this module already accepts. Pushed
    -- rather than answered on request, because the consumer reads it inside settlement, which must stay
    -- synchronous, deterministic and idempotent (IDEA-164).
    if shown[pid] ~= assetId then
        pcall(function() TriggerEvent("ncm:machine.seated", pid, assetId) end)
    end
    shown[pid] = assetId
    pcall(function()
        -- KB-97 / IDEA-341: this is the serialised identity, serial and lifetime distance of the machine the
        -- driver is sitting in. On a bag it reached every player in the bucket continuously -- precisely the
        -- facts `28_MACHINE_KNOWLEDGE.md` intends players to EARN through discovery and observation. Targeted.
        if not assetId then TriggerClientEvent("ncm:odo", pid, false); return end
        local c = card[assetId] or {}
        TriggerClientEvent("ncm:odo", pid, {
            assetId = assetId,
            m = NcmOdometer.readingFor(assetId, stored[assetId] or 0),
            name = c.name, ord = c.ordinal,
        })
    end)
end

--- Write one asset's accumulated metres. `odometer_m = odometer_m + ?` so a concurrent write cannot lose the
--- other's contribution, and so the stored value is never computed from a stale read.
local function flush(assetId, metres, t)
    if not assetId or (metres or 0) < 1 then return end
    local ok, err = pcall(function()
        local delta, at = math.floor(metres), math.floor(t or now())
        local committed, why = MySQL.transaction.await({
            { query = "UPDATE vehicle_asset SET odometer_m = odometer_m + ?, odometer_at = ? WHERE asset_id = ?",
              values = { delta, at, assetId } },
            { query = [[UPDATE component_asset SET exposure_m = exposure_m + ?
                WHERE machine_asset_id = ? AND location_kind = 'installed']],
              values = { delta, assetId } },
        })
        if not committed then error(why or "odometer transaction refused") end
    end)
    if not ok then log("checkpoint failed asset=%s: %s", tostring(assetId):sub(1, 8), tostring(err)) end
    -- Keep the cached durable figure in step, so the reading never jumps backwards at a checkpoint.
    if ok then stored[assetId] = (stored[assetId] or 0) + math.floor(metres) end
    return ok
end

--- Persist everything outstanding. Called on resource stop and by the checkpoint rule.
function NcmOdometer.flushAll(reason)
    local t = now()
    local n = 0
    for assetId, acc in pairs(pending) do
        if acc.metres >= 1 then flush(assetId, acc.metres, t); n = n + 1 end
        pending[assetId] = nil
    end
    if n > 0 then log("checkpoint %d asset(s) (%s)", n, tostring(reason or "periodic")) end
    return n
end

--- One sample of one materialised machine. The pure decision about whether the movement was real travel
--- lives in `data.vehicle_identity.segment`; this only gathers facts.
local function step(entry, t)
    local assetId, vehicleId = entry.assetId, entry.vehicleId
    describe(assetId)
    local okSnap, snap = pcall(Open77.vehicles.get, vehicleId)
    if not okSnap then last[assetId] = nil; publish(entry.pid, nil); return end
    local p = positionOf(snap)
    if not p or not occupied(snap) then
        publish(entry.pid, nil)
        -- The tyres keep cooling with nobody aboard. This is the branch that makes temperature a property
        -- of the Machine rather than of the drive, and it costs one call.
        thermalStep(entry, nil, nil, t)
        -- Unreadable, gone, or nobody aboard. Break the chain so the next observation cannot be joined to
        -- this one across the gap.
        last[assetId] = nil
        return
    end
    noteFields(snap)
    local cur = { assetId = assetId, x = p.x, y = p.y, z = p.z or 0, at = t, speedMps = speedOf(snap),
                  headingRad = headingOf(snap) }
    local prev = last[assetId]
    last[assetId] = cur
    observedLateral = nil
    thermalStep(entry, prev, cur, t)
    -- **The same facts, offered to the knowledge substrate before they are discarded** (31 section 9).
    -- No extra snapshot read, no extra loop: `cur` and the cornering load are already here, and a
    -- measurement not taken now cannot be taken later. Guarded because a failure to record what a car was
    -- seen doing must never stop its odometer from advancing.
    if NcmObservation and NcmObservation.sample then
        pcall(NcmObservation.sample, entry, cur, observedLateral, t)
    end
    if not prev then return end
    local seg = Identity.segment(prev, cur)
    trace(assetId, prev, cur, seg)
    if not seg.accept then
        if seg.reason ~= "stationary" and seg.reason ~= "stationary_by_speed" then
            rejected[seg.reason] = (rejected[seg.reason] or 0) + 1
        end
        return
    end
    local acc = pending[assetId]
    if not acc then acc = { metres = 0, since = t }; pending[assetId] = acc end
    acc.metres = acc.metres + seg.metres
    if acc.metres >= CHECKPOINT_M or (t - acc.since) >= CHECKPOINT_S then
        flush(assetId, acc.metres, t)
        pending[assetId] = nil
    end
    publish(entry.pid, assetId)
end

--- The live reading for one asset: what is durably stored plus what has accumulated since the last
--- checkpoint. The HUD shows this so the number moves while you drive rather than jumping every 250 m.
function NcmOdometer.readingFor(assetId, storedM)
    local acc = pending[assetId]
    return math.floor((tonumber(storedM) or 0) + (acc and acc.metres or 0))
end

--- Flush and forget one asset -- used when a called car is reclaimed, so its last metres are durable before
--- the live vehicle disappears.
function NcmOdometer.release(assetId)
    if not assetId then return end
    local acc = pending[assetId]
    if acc then flush(assetId, acc.metres, now()) end
    pending[assetId], last[assetId], stored[assetId], card[assetId] = nil, nil, nil, nil
    for vehicleId, reg in pairs(tracked) do if reg.assetId == assetId then tracked[vehicleId] = nil end end
end

CreateThread(function()
    Wait(6000)
    local lastReport = 0
    while true do
        Wait(SAMPLE_MS)
        local t = now()
        for _, entry in ipairs(watchlist()) do
            local ok, err = pcall(step, entry, t)
            if not ok then log("sample error asset=%s: %s", tostring(entry.assetId):sub(1, 8), tostring(err)) end
        end
        -- One diagnostic line every five minutes, never per sample: a rejection is normal (every CALL
        -- produces one) and only a PATTERN of them is worth reading (addendum section 30).
        if t - lastReport >= 300 then
            lastReport = t
            local parts = {}
            for reason, n in pairs(rejected) do parts[#parts + 1] = reason .. "=" .. n end
            if #parts > 0 then
                table.sort(parts)
                log("discontinuities filtered in the last 5 min: %s", table.concat(parts, " "))
                rejected = {}
            end
        end
    end
end)

-- A disconnect reclaims the driver's called cars, so the distance they covered must be durable before the
-- vehicles vanish. Those last kilometres belong to the machine, not to the session that ended.
AddEventHandler("onPlayerDisconnected", function()
    NcmOdometer.flushAll("player disconnected")
end)

AddEventHandler("ncm:odometer.track", function(assetId, vehicleId, pid)
    NcmOdometer.track(assetId, vehicleId, pid)
end)
AddEventHandler("ncm:odometer.untrack", function(vehicleId) NcmOdometer.untrack(vehicleId) end)

AddEventHandler("onResourceStop", function(name)
    if name == GetCurrentResourceName() then NcmOdometer.flushAll("resource stop") end
end)

-- Console: follow one machine's accumulator for a few minutes. `ncm.odo.trace <assetId> [minutes]`,
-- or `ncm.odo.trace off`. Bounded by design -- it expires on its own.
RegisterCommand("ncm.odo.trace", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local target = args and args[1]
    if not target or target == "off" then
        traceAsset, traceUntil, traceTotals = nil, 0, nil
        log("trace off")
        return
    end
    local minutes = math.max(1, math.min(30, tonumber(args[2]) or 10))
    traceAsset = tostring(target)
    traceUntil = now() + minutes * 60
    traceTotals = { samples = 0, raw = 0, accepted = 0, rejected = 0 }
    log("trace on for asset=%s for %d min", traceAsset:sub(1, 8), minutes)
end, false)

-- Console: the odometer as it stands right now, including unflushed progress.
RegisterCommand("ncm.odo", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function()
        local rows = MySQL.query.await([[SELECT asset_id, vehicle_key, production_ordinal, odometer_m
            FROM vehicle_asset WHERE odometer_m > 0 ORDER BY odometer_m DESC LIMIT 20]]) or {}
        if #rows == 0 then log("no vehicle has recorded distance yet"); return end
        for _, r in ipairs(rows) do
            log("%s %-22s %s", Identity.formatOrdinal(r.production_ordinal) or "#------",
                tostring(r.vehicle_key),
                Identity.formatOdometer(NcmOdometer.readingFor(r.asset_id, r.odometer_m)))
        end
    end)
end, false)
