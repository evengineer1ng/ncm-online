-- ncm_world / client / ffb_bridge — telemetry out to a local force-feedback companion (IDEA-386).
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
local enabled, url = false, DEFAULT_URL
local surface, surfaceReady = nil, false
local sent, skipped = 0, 0

-- What the companion told us about the hardware, or nil if it has not said. **Never invented**: an absent
-- device is reported as absent, because "no wheel detected" and "a wheel we could not identify" are different
-- things to show a player, and only one of them is their problem to fix.
local device = nil

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
        device = device, sent = sent, idle = skipped,
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

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("bridge closed (%s) after %d frame(s), %d skipped", tostring(why), sent, skipped)
    end
    surface, surfaceReady, device = nil, false, nil
    announce()
end

local function bringUp()
    if surface then return end
    local page, reason = WebUI.create({
        entry = url, layer = "hud", width = 16, height = 16,
        zIndex = 1, transparent = true, visible = false,
    })
    if not page then
        -- Not an error worth shouting about: "the companion is not running" is the ordinary case.
        log("bridge unavailable (%s) — is the companion listening on %s?", tostring(reason), url)
        enabled = false
        announce()
        return
    end
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
        device = {
            name = tostring(d.name or "unknown device"),
            class = Feedback.CLASSES[d.class] and d.class or "unknown",
            rung = tonumber(d.rung), rungs = type(d.rungs) == "table" and d.rungs or nil,
            armed = d.armed and true or false,
            haptics = type(d.haptics) == "table" and d.haptics or nil,
        }
        announce()
        log("device: %s | class=%s | rung=%s | armed=%s",
            device.name, device.class, tostring(device.rung), tostring(device.armed))
    end)
    log("bridge surface created for %s; waiting for the companion", url)
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
local function seated()
    local ok, st = pcall(Open77.character.state)
    if ok and type(st) == "table" and type(st.inVehicle) == "boolean" then return st.inVehicle end
    local ok2, seat = pcall(Open77.vehicles.getPlayerSeat)
    if ok2 and type(seat) == "table" then return true end
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
