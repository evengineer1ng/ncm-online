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

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("bridge closed (%s) after %d frame(s), %d skipped", tostring(why), sent, skipped)
    end
    surface, surfaceReady = nil, false
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
        return
    end
    surface = page
    page:on("ncm:ffb.ready", function(info)
        surfaceReady = true
        log("companion connected: %s", type(info) == "table" and tostring(info.detail or "ok") or "ok")
    end)
    page:on("ncm:ffb.closed", function(info)
        surfaceReady = false
        log("companion dropped: %s", type(info) == "table" and tostring(info.detail or "?") or "?")
    end)
    log("bridge surface created for %s; waiting for the companion", url)
end

--- The car the local player is sitting in, or nil. Shared with the race sampler on purpose
--- (`NcmClientOwnVehicle`, declared in client/telemetry.lua): a second copy of the seat/snapshot dance is a
--- second place for field names to drift out of agreement with the runtime.
---
--- **This is also the scoping.** There is no path in this file to any vehicle but the one under the driver.
local function ownSnapshot()
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
