-- ncm_world / client / carrier_bridge -- the single channel between NCM and whatever is listening on
-- loopback: the NCM Carrier plugin, or the older force-feedback companion.
--
-- It began as the FFB bridge (`IDEA-386`) and carries two things now: telemetry UP, so a wheel can be made
-- to feel what the car is doing, and machine projections DOWN, so fitted parts, class rules and the weather
-- can actually reach the car. **One transport for both**, deliberately: an effect must not be able to arrive
-- while the channel that reports feel is down, and two sockets would be two places for the sides to
-- disagree about which is authoritative.
--
-- **The direction is inverted from the obvious one, and that is the whole trick** (L129, MASTER_TEST §AJ).
-- A bundled WebUI page has no outbound network at all — `ws`, `wss`, `http` and `https` alike refused in
-- ~0ms from the private `cym-ui` origin, with no socket ever opened. So the companion serves a page, NCM
-- creates a surface whose `entry` is that URL, and the page talks to its own origin. `Open77.webui.create`
-- still injects the Lua bridge into the configured top-level entry origin, so this file reaches it with an
-- ordinary `page:send`.
--
-- Consequences worth stating, because each is load-bearing:
--
--   * **Off by default.** It needs a process NCM does not ship and cannot see. `/ncm.ffb on`.
--   * **A separate hidden surface, never the race HUD** (`IDEA-393`). If the companion is not running, this
--     surface fails to create and nothing else notices. Core race presentation must never depend on an
--     optional peripheral process on a machine we do not control.
--   * **Your own occupied vehicle and nothing else** (`IDEA-388`). Not the nearest car, not the car ahead.
--     That scoping is by construction here rather than by policy, because the moment it carries facts about
--     another machine it reopens the leak `IDEA-341` was filed to close.
--   * **No TLS.** Loopback is a secure context over plain HTTP, so there is no certificate to install.
local function log(fmt, ...) print(("[ncm_world/client/ffb] " .. fmt):format(...)) end

-- Declared BEFORE anything that reads them: a `local` referenced from a function defined above it captures a
-- nil global instead, the defect class that has bitten this codebase five times and that `luac -p` cannot see.
local Feedback = NcmCore.get("driver.feedback")

local DEFAULT_URL = "http://127.0.0.1:38480/bridge.html"
local HZ = 30                       -- the rate the platform's own observers run at; the wheel wants smooth
-- **On by default, unlike the companion era.** The carrier ships WITH the world through RequiredMods, so
-- for most players something IS listening, and requiring `/ncm.ffb on` before parts or weather could reach
-- the car would be a trap. A player with no carrier costs a handful of failed connects and a log line.
local enabled, url = true, DEFAULT_URL
local attempts, MAX_ATTEMPTS = 0, 6
local surface, surfaceReady = nil, false
local sent, skipped = 0, 0

-- What the companion told us about the hardware, or nil if it has not said. **Never invented**: an absent
-- device is reported as absent, because "no wheel detected" and "a wheel we could not identify" are different
-- things to show a player, and only one of them is their problem to fix.
local device = nil

-- What the carrier plugin reports about itself, or nil if nothing is listening or it is the older companion
-- (which knows nothing about projections and simply never sends this).
local carrier = nil

--- Read by the NCM panel (`client/panel.lua`) to draw the WHEEL tab. A plain snapshot, so the panel never
--- reaches into this file's state or has to know a companion exists.
--- **The panel is a one-shot reader, so it has to be told when to read again.**
---
--- Bringing the surface up, loading the page and waiting for the companion's socket all take longer than a
--- button press. Without this the WHEEL tab renders the state at the instant of the click -- *"companion not
--- detected"* -- and stays wrong forever while a perfectly healthy companion is connected behind it. That is
--- exactly what happened on the first live run (2026-09-24).
---
--- A client-local event, not a global callback: `panel.lua` is in the same VM and the same resource, and an
--- event means the bridge does not have to know whether a panel exists.
local function announce()
    pcall(TriggerEvent, "ncm:ffb.state")
end

NcmClientFfbState = function()
    return {
        enabled = enabled, url = url,
        surface = surface ~= nil, connected = surfaceReady,
        device = device, carrier = carrier, sent = sent, idle = skipped,
    }
end

--- The panel's only way in. Settings and the test pulse go DOWN the same bridge the telemetry comes up, so
--- there is no second transport and no second place for the two sides to disagree about state.
NcmClientFfbCommand = function(kind, payload)
    if kind == "enable" then
        enabled = (type(payload) == "table") and (payload.on and true or false) or false
        announce()
        return true
    end
    if not (surface and surfaceReady) then return false, "not_connected" end
    if kind == "settings" or kind == "test" then
        surface:send("ncm:ffb." .. kind, type(payload) == "table" and payload or {})
        return true
    end
    return false, "unknown_command"
end

--- The last projection set we pushed, by record, so an unchanged world costs nothing. Keyed by the same
--- signature the server publishes with; a record that disappears is sent a restore rather than forgotten.
local projected = {}

--- Push one envelope to the carrier. The plugin applies it and interprets nothing -- which part moved which
--- flat, and why, was decided server-side in `machine.projection`.
local function pushProjection(envelope)
    if not (surface and surfaceReady) then return false end
    surface:send("ncm:machine.projection", envelope)
    return true
end

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("bridge closed (%s) after %d frame(s), %d skipped", tostring(why), sent, skipped)
    end
    surface, surfaceReady, device, carrier = nil, false, nil, nil
    -- Forget what we pushed. The carrier restores its own originals when the socket drops, so re-sending on
    -- reconnect is correct and re-sending nothing would leave a fresh carrier with no projection at all.
    projected = {}
    announce()
end

local function bringUp()
    if surface then return end
    local page, reason = WebUI.create({
        entry = url, layer = "hud", width = 16, height = 16,
        zIndex = 1, transparent = true, visible = false,
    })
    if not page then
        -- Not an error worth shouting about: "nothing is listening" is an ordinary state, and on a fresh
        -- launch it is usually just early -- the plugin's socket comes up while the game is still loading.
        attempts = attempts + 1
        if attempts >= MAX_ATTEMPTS then
            log("no carrier or companion on %s after %d attempt(s) — giving up until /ncm.ffb on",
                url, attempts)
            enabled = false
        end
        announce()
        return
    end
    attempts = 0
    surface = page
    page:on("ncm:ffb.ready", function(info)
        surfaceReady = true
        announce()
        log("companion connected: %s", type(info) == "table" and tostring(info.detail or "ok") or "ok")
    end)
    page:on("ncm:ffb.closed", function(info)
        surfaceReady = false
        device = nil
        announce()
        log("companion dropped: %s", type(info) == "table" and tostring(info.detail or "?") or "?")
    end)
    -- The companion is the only thing that can see the hardware, so it is the only thing that may describe
    -- it. `class` decides the ceiling (`driver.feedback`), and a class we do not recognise is NOT silently
    -- upgraded here -- `clamp` treats it as the most dangerous thing it could be.
    page:on("ncm:ffb.device", function(d)
        if type(d) ~= "table" then return end
        -- **Rebuilt field by field, and that is why the steering slider never appeared**: `rig` and `tune`
        -- were simply not in the list, so the panel had nothing to draw them from. Anything the companion
        -- reports and the panel needs has to be named here; a copy that silently drops fields is worse than
        -- passing the table through, because it fails quietly and looks like a UI bug.
        device = {
            name = tostring(d.name or "unknown device"),
            class = Feedback.CLASSES[d.class] and d.class or "unknown",
            rung = tonumber(d.rung), rungs = type(d.rungs) == "table" and d.rungs or nil,
            armed = d.armed and true or false,
            haptics = type(d.haptics) == "table" and d.haptics or nil,
            rig = type(d.rig) == "table" and d.rig or nil,
            tune = type(d.tune) == "table" and d.tune or nil,
            caps = type(d.caps) == "table" and d.caps or nil,
        }
        announce()
        log("device: %s | class=%s | rung=%s | armed=%s",
            device.name, device.class, tostring(device.rung), tostring(device.armed))
    end)
    -- The carrier reports what it did with a projection. Kept separate from `device` because "your wheel"
    -- and "your car" are different questions and a player debugging one should not have to read the other.
    page:on("ncm:carrier.health", function(h)
        if type(h) ~= "table" then return end
        carrier = {
            version = tostring(h.version or "?"),
            hook = h.hook and true or false,
            applied = tonumber(h.applied) or 0,
            records = tonumber(h.records) or 0,
        }
        announce()
        log("carrier %s | hook=%s | %d flat(s) on %d record(s)",
            carrier.version, tostring(carrier.hook), carrier.applied, carrier.records)
    end)
    log("bridge surface created for %s; waiting for a listener", url)
end

--- The car the local player is sitting in, or nil. Shared with the race sampler on purpose
--- (`NcmClientOwnVehicle`, declared in client/telemetry.lua): a second copy of the seat/snapshot dance is a
--- second place for field names to drift out of agreement with the runtime.
---
--- **This is also the scoping.** There is no path in this file to any vehicle but the one under the driver.
--- **Are we actually in a car?** Asked of the platform, not inferred from a seat handle.
---
--- `getPlayerSeat` proved sticky: a session that spent time on foot still produced 986 vehicle frames and
--- ZERO idle frames, so the rig kept steering while the driver was walking. `Open77.character.state()`
--- carries an `inVehicle` flag and is what `client/vehicle_access.lua` already trusts for the same question.
---
--- **Absent is not a negative** -- the same rule vehicle_access learned the hard way. If the platform does
--- not report the field, fall back to the seat read rather than declaring the driver on foot and killing
--- their steering mid-corner.
local loggedState = false

--- **Are we actually in a car?**
---
--- Answered the hard way, because the two easy answers are both wrong on this build:
---
---   * `Open77.character.state()` has **no `inVehicle` field at all**. Logged from the running client, it
---     returns age, air, alive, animation, attached, crouched, engineId, fall, groundSpeed, grounded,
---     hasDouble, health, id, inWorkspot, isPlayer, landing, owned, sliding, source, speed, vaulting, yaw.
---     The check for it therefore always fell through.
---   * `getPlayerSeat()` is **sticky** -- it keeps naming a seat after the driver has walked away.
---
--- So the seat is treated as a claim and then verified: ask the vehicle it names who is actually aboard. A
--- stale seat pointing at a car whose occupants no longer include us is exactly the on-foot case, and it is
--- the one the sticky read cannot see.
local function seated()
    local okSeat, seat = pcall(Open77.vehicles.getPlayerSeat)
    if not okSeat or type(seat) ~= "table" then return false end
    local vid = seat.vehicleId or seat.vehicle or seat.id
    if not vid then return false end

    local okV, v = pcall(Open77.vehicles.get, vid)
    if not okV or type(v) ~= "table" then
        -- The car is not streamed to us. We cannot be sitting in it.
        return false
    end
    local okId, me = pcall(Open77.players.localId)
    if not okId or me == nil or type(v.occupants) ~= "table" then
        -- Cannot verify. **Absent is not a negative** -- believe the seat rather than cutting steering
        -- mid-corner on a missing field, which is the mistake `vehicle_access.lua` records.
        if not loggedState then
            loggedState = true
            log("seat check: cannot verify occupants (localId=%s occupants=%s); trusting the seat read",
                tostring(okId and me or "?"), type(v.occupants))
        end
        return true
    end
    for _, occ in pairs(v.occupants) do
        local who = occ
        if type(occ) == "table" then who = occ.playerId or occ.player or occ.id end
        if who ~= nil and tostring(who) == tostring(me) then return true end
    end
    return false
end

local function ownSnapshot()
    if not seated() then return nil end
    if type(NcmClientOwnVehicle) ~= "function" then return nil end
    local ok, v = pcall(NcmClientOwnVehicle)
    if not ok or type(v) ~= "table" then return nil end
    return v
end

CreateThread(function()
    Wait(6000)
    while true do
        if enabled then
            if not surface then bringUp() end
            if surface and surfaceReady then
                local snap = ownSnapshot()
                local frame = snap and Feedback.frame(snap, { at = Open77.time.monotonic() }) or nil
                if frame then
                    surface:send("ncm:ffb.frame", frame)
                    sent = sent + 1
                else
                    -- Out of the car, or the snapshot was unreadable. Say so explicitly rather than going
                    -- quiet: silence and "no force" are different instructions, and a companion holding the
                    -- last frame would keep pushing at a wheel whose car we can no longer see.
                    skipped = skipped + 1
                    surface:send("ncm:ffb.idle", { v = Feedback.FRAME_VERSION })
                end
            end
            Wait(math.floor(1000 / HZ))
        else
            if surface then tearDown("disabled") end
            Wait(1000)
        end
    end
end)

--- Machine projections, pushed down the same socket the telemetry comes up.
---
--- Slow on purpose: the record carrier is **spawn-cached**, so a change reaches a car the next time one
--- spawns and there is nothing to be gained by shouting it twice a second. 2 Hz is about latency to a fresh
--- spawn, not about smoothness.
CreateThread(function()
    Wait(9000)
    while true do
        if enabled and surface and surfaceReady then
            local ok, state = pcall(function() return GlobalState.ncmProjections end)
            local records = (ok and type(state) == "table" and type(state.records) == "table")
                and state.records or nil
            if records then
                for record, envelope in pairs(records) do
                    if type(envelope) == "table" and type(envelope.record) == "table" then
                        -- The signature is what the server changed, not what we think it means. Comparing
                        -- flat counts would miss a multiplier that moved without the count changing.
                        local sig = ("%s/%d/%s"):format(tostring(envelope.at),
                                                        #(envelope.record.flats or {}),
                                                        tostring(envelope.record.restore))
                        if projected[record] ~= sig and pushProjection(envelope) then
                            projected[record] = sig
                        end
                    end
                end
                -- A record the server stopped publishing keeps its altered flats until something says
                -- otherwise, so say otherwise.
                for record in pairs(projected) do
                    if records[record] == nil then
                        if pushProjection({ v = 1, record = { path = record, flats = {}, restore = true } }) then
                            projected[record] = nil
                        end
                    end
                end
            end
        end
        Wait(500)
    end
end)

AddEventHandler("onClientResourceStop", function(name)
    if name == GetCurrentResourceName() then tearDown("resource stopping") end
end)

RegisterCommand("ncm.ffb", function(_, args)
    local a = args and args[1] and tostring(args[1]):lower() or nil
    if a == "on" then
        enabled = true
    elseif a == "off" then
        enabled = false
        tearDown("command")
    elseif a == "url" and args[2] then
        url = tostring(args[2])
        tearDown("url changed")
        log("companion url set to %s", url)
    end
    log("ffb %s | url=%s | surface=%s ready=%s | sent=%d idle=%d",
        enabled and "on" or "off", url, tostring(surface ~= nil), tostring(surfaceReady), sent, skipped)
end, false)
