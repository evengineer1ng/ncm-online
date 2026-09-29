-- ncm_world / client / race — the entrant's race HUD and gate reporter (M3.2).
--
-- Reads GlobalState.ncmSessions (server-published, ~1 Hz; one view per live session). If the local driver is an entrant:
-- forming/gridded: a marker at the grid slot and a card with the distance to it; countdown: the
-- lights arrive as server toasts; running: the next gate is a world marker, crossings are detected
-- locally (core course.gates, same line geometry as SP) and REPORTED to the server, which
-- re-validates against its own position read; finishing/complete: the result card.
-- The client never decides a classification.
local Core = NcmCore
local Gates = Core.get("course.gates")
local Routes = Core.get("course.routes")
local Entry = Core.get("competition.entry")
local Tm = Core.get("telemetry")
local Identity = Core.get("data.vehicle_identity")
local Standings = Core.get("session.standings")

NcmClientGraphOn = true          -- P40 live race graph; F8 / /ncm.graph toggles
local gridGpsFor = nil           -- REPORT TO GRID waypoint sent once per session
local courseLen = nil            -- polyline length for the graph, per session

local function log(fmt, ...)
    print(("[ncm_world/client/race] " .. fmt):format(...))
end

local function call(resource, name, ...)
    local promise, reason = Open77.exports.call(resource, name, ...)
    if not promise then return nil, reason end
    return promise:await()
end

NcmClientRaceActive = false      -- read by calendar.lua to yield the heartbeat card
NcmClientRacePhase = "none"      -- the live phase; "complete" is the result hold, when a driver is free again (KB-187)

local view = nil                 -- last view picked from GlobalState.ncmSessions / ncmPractice
local lastView = nil             -- what mattered from the previous tick (green flag edge)
local base = { serverNow = 0, mono = 0 }
local me = nil                   -- my entrant record from the view
local lastMe = nil
local markers = {}               -- name -> handle
local crossed = {}               -- gateIndex -> mono time of local detection (per session)
local reported = {}              -- gateIndex -> mono time of last report
local retries = {}               -- gateIndex -> retry count
local sessionSeen = nil
local notMine = nil
local prevPos = nil
local origin = nil               -- where we sat when the lights started (start rule: moved 30 m from here)
local targetedViews = {}         -- sessionId -> entrant-targeted read model (KB-79 primary handoff)

local function serverNow() return base.serverNow + (Open77.time.monotonic() - base.mono) end
NcmClientServerNow = serverNow   -- the synced server clock, shared with client/telemetry.lua
-- `/ncm.gps` re-routes to the session's target rather than the street cadence.
--
-- **This used to be broken in the most silent way available.** It read `gpsTarget`, which is declared
-- `local` ~110 lines BELOW this point, so the closure captured a GLOBAL of that name that nothing ever
-- assigns: `NcmClientRaceTarget()` returned nil for every race NCM has ever run. `/ncm.gps` therefore
-- always fell through to the calendar branch and routed a racing driver to a VENUE. That is the Hook
-- failure of 2026-09-23 -- "GPS continued routing to the START" -- and it was never Hook-specific.
-- The fourth instance of Lua local-ordering biting this codebase; `luac -p` cannot see it.
-- Scoped to a live session on purpose: `NcmNav` also holds the calendar's venue target, and `/ncm.gps`
-- outside a race must still be free to re-derive which race is yours.
NcmClientRaceTarget = function() return NcmClientRaceActive and NcmNav.target() or nil end

local function myDriverId()
    local ok, bag = pcall(Open77.state.localPlayer)
    if ok and type(bag) == "table" and type(bag.ncm) == "table" then return bag.ncm.driverId end
    return nil
end

local function myPlayerId()
    local ok, value = pcall(Open77.players.localId)
    return ok and tonumber(value) or nil
end

local function localPosition()
    local ok, x, y, z = pcall(Open77.character.position)
    if ok and type(x) == "number" then return { x = x, y = y, z = z } end
    return nil
end

local function removeMarker(name)
    if markers[name] then pcall(function() call("open77_worldui", "remove", markers[name]) end) end
    markers[name] = nil
end

local function ensureMarker(name, def)
    local sig = def.x .. "," .. def.y .. "|" .. tostring(def.label or "") .. "|" .. tostring(def.color or "")
    if markers[name] and markers[name .. "@"] == sig then return end
    removeMarker(name)
    local spec = {
        id = "ncm_" .. name,
        position = { x = def.x, y = def.y, z = def.z },
        radius = def.radius or 4.0, style = def.style or "objective", maxDistance = def.maxDistance or 250.0,
        groundOffset = 0.25, color = def.color or "#00E5FF",
    }
    if def.label then spec.label = def.label; spec.description = def.description end
    if def.event then spec.key = def.key or "E"; spec.holdSeconds = def.holdSeconds or 0.5; spec.promptDistance = def.promptDistance or 6.0; spec.event = def.event end
    local result, err = call("open77_worldui", "create", spec)
    if result and result.ok then
        markers[name] = result.handle
        markers[name .. "@"] = sig
    else
        log("marker %s failed: %s", name, tostring(err or (result and result.error)))
    end
end

-- ---------------------------------------------------------------------------------------------
-- The race HUD page (web/race.html): F1 light tree, big banner, race strip. Lights are rendered
-- from the synced server clock so they are not at the mercy of the 1 Hz state publication; the
-- server's greenAt stays the authoritative timing reference.
-- ---------------------------------------------------------------------------------------------
-- Zero is a measurement; absence is not (IDEA-361). Shared definition, so the HUD and the database
-- cannot disagree about what counts as having been read.
local Reading = NcmCore.get("competition.machine_knowledge").reading

local page, pageReady = nil, false
-- Declared HERE, with the other page state, because `pushInputs` -- defined far above the speedometer
-- block that owns these -- writes `haveSpeedReading`. A `local` declared below its reader is captured as
-- a nil GLOBAL instead, silently, and `luac -p` cannot see it. This file's own header names that defect
-- class; it has cost this codebase five separate sessions.
local speedoClaimed, lastSpeedoClaimAt = false, 0
local haveSpeedReading = false
local lastSent = nil
local bannerUntil, bannerState = 0, nil

local function ser(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. ser(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function hud(state)
    if not page or not pageReady then return end
    local key = ser(state)
    if key == lastSent then return end
    lastSent = key
    page:send("race:state", state)
end

local function banner(kind, text_, sub, seconds)
    bannerState = { kind = kind, text = text_, sub = sub }
    bannerUntil = Open77.time.monotonic() + (seconds or 3)
end

local function currentBanner()
    if bannerState and Open77.time.monotonic() < bannerUntil then return bannerState end
    return nil
end

AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    local reason
    page, reason = WebUI.create({
        entry = "web/race.html", layer = "hud", width = 1920, height = 1080,
        fps = 30, zIndex = 730, transparent = true, visible = true,
    })
    if not page then log("race HUD WebUI failed: %s", tostring(reason)); return end
    page:on("race:ready", function() pageReady = true; lastSent = nil; log("race HUD ready") end)
    -- IDEA-387: the probe's verdict, logged so it lands in the client log rather than only in a console.
    page:on("race:wsprobe.result", function(r)
        if type(r) ~= "table" then log("wsprobe: malformed result"); return end
        log("wsprobe: %s | origin=%s secureContext=%s protocol=%s | %s (%sms)",
            tostring(r.verdict), tostring(r.origin), tostring(r.secureContext),
            tostring(r.protocol), tostring(r.detail), tostring(r.elapsedMs))
    end)
end)

local function clearAll(instr)
    for _, name in ipairs({ "slot", "gate", "grid" }) do removeMarker(name) end
    -- The cluster survives the race HUD letting go: it is information about the machine, not about a session.
    hud({ instrument = instr })
    NcmClientRaceActive = false
    NcmClientRacePhase = "none"
    -- Nothing of this race may outlive it. A stale race target is how a finished session keeps steering the
    -- next one; `gridGpsFor` is keyed by session so it self-invalidates, but the waypoint itself did not.
    if gpsTarget then gpsTarget = nil; NcmNav.clear() end
end

local function fmt(sec)
    if not sec then return "--" end
    local m = math.floor(sec / 60)
    return string.format("%d:%04.1f", m, sec - m * 60)
end

local function km(m)
    if m >= 1000 then return string.format("%.1f km", m / 1000) end
    return string.format("%d m", math.floor(m))
end

-- GPS to a point without the player touching chat. NCM sets the waypoint and stops there (L70) -- it never
-- opens the player's map to force the engine's route calculation.
local gpsTarget = nil            -- the point the race HUD is currently routing to (read by /ncm.gps)
-- KB-22 (owner 2026-09-21): the results board and the result banner share ONE lifetime. The board used to
-- dismiss itself after BOARD_SEC while the big "RESULT - P1" strip stayed up for tens of seconds. After the
-- window the strip keeps only what is still useful (where to go next) and disappears when there is nothing next.
local BOARD_SEC = 15             -- results board + result banner; then the strip is forward-looking only
local boardSince = {}            -- sessionId -> monotonic time the result was first shown
local function boardOn(sessionId)
    boardSince[sessionId] = boardSince[sessionId] or Open77.time.monotonic()
    return (Open77.time.monotonic() - boardSince[sessionId]) < BOARD_SEC
end
local function inVehicle()
    local ok, seat = pcall(Open77.players.getVehicleSeat)
    if ok and type(seat) == "table" then return true end
    local ok2, seat2 = pcall(Open77.vehicles.getPlayerSeat)
    return ok2 and type(seat2) == "table"
end
-- L70 still holds: NCM never opens the player's map for them. What changed is that it no longer needs to --
-- `client/nav.lua` uses the platform's routable blip + track recipe, which is what actually wakes the native
-- road line, and re-selects it when the driver gets into the car. See that file's header.
local function gpsTo(p, why)
    gpsTarget = { x = p.x, y = p.y, z = p.z, why = why }
    NcmNav.to({ x = p.x, y = p.y, z = p.z, name = p.name or p.kind }, why)
end

local function report(index)
    reported[index] = Open77.time.monotonic()
    log("crossed gate %d -> reporting", index)
    TriggerServerEvent("ncm:gate", view.sessionId, index)
end

-- ---------------------------------------------------------------------------------------------
-- Per-phase presentation (runs at 10 Hz)
-- ---------------------------------------------------------------------------------------------
local goShownFor = nil
local outNoticeUntil = nil

--- The live race graph (P40): where you are on the course, and who is immediately around you.
---
--- **It used to draw every driver across the full width of the screen**, which covered the speedometer, said
--- nothing at all in a field of one, and would have been unreadable with a real grid on track (owner,
--- 2026-09-23). It is now a short vertical strip showing at most four drivers: `session.standings` picks the
--- window, this only sorts and shapes.
---
--- Sorted leader-first by corrected progress, because that is the order the strip is drawn in and the order
--- the window is chosen from. Corrected progress is deliberate: it is the sporting position, so a penalty
--- already shows up here as ground lost, and a richer incident treatment later has somewhere to live.
local function graphState()
    if not NcmClientGraphOn or not view or not view.gates or #view.gates < 2 then return nil end
    if not courseLen then courseLen = (view.lengthM and view.lengthM > 0) and view.lengthM or Tm.polyline(view.gates).lengthM end
    if not courseLen or courseLen <= 0 then return nil end
    local rows = {}
    for _, en in ipairs(view.entrants) do
        if en.state == "racing" or en.state == "finished" or en.state == "suspended" then
            local m = en.correctedM or en.progressM or 0
            if en.state == "finished" then m = courseLen end
            local tag = en.teamShort or (en.display and tostring(en.display):sub(1, 3):upper()) or "?"
            rows[#rows + 1] = { tag = tag, colour = en.colour or "#00E5FF", m = m,
                                frac = math.max(0, math.min(1, m / courseLen)),
                                me = (me and en.driverId == me.driverId) or false,
                                inc = en.incidentSec or 0, number = en.number }
        end
    end
    if #rows == 0 then return nil end
    table.sort(rows, function(a, b)
        if a.m ~= b.m then return a.m > b.m end
        return tostring(a.tag) < tostring(b.tag)        -- stable, so the strip does not flicker on a tie
    end)
    for i, r in ipairs(rows) do r.pos = i end
    local shown = Standings.focus(rows)
    return { on = true, dots = shown, laps = view.laps or 1, field = #rows }
end

--- The driver's instrument cluster: which machine this is and how far it has travelled in its life.
---
--- **Deliberately not hidden during a race** (P.S.): race kilometres are real kilometres travelled by the
--- physical asset, and a car entered into an event carries whatever mileage it already had. The continuity is
--- the point -- an old road car converted to competition should read like one.
---
--- It shows accumulated distance and NOTHING about any future lifespan: no engine health, no remaining
--- kilometres, no prediction. That threshold, if it ever exists, stays private server state.
-- KB-97 / IDEA-341: the odometer used to ride a `player(id)` bag, so every client in the routing bucket
-- received the serialised identity, serial and lifetime distance of the machine every other driver occupied --
-- precisely the facts 28_MACHINE_KNOWLEDGE.md intends players to earn. Declared BEFORE the handler on purpose:
-- a `local` referenced from a function defined above it captures a nil global instead, the defect class that
-- has bitten this codebase five times and that `luac -p` cannot see.
local odoState = nil
RegisterNetEvent("ncm:odo", function(v) odoState = (type(v) == "table") and v or nil end)

-- Tyre temperature (`L159`). Its own channel and straight through to the page, for the same reason driver
-- inputs have one: `race:state` is diffed and republished on race events, and folding a continuously
-- changing value into it would defeat that throttling for every other consumer.
--
-- The server already quantises, suppresses an unchanged value and heartbeats every two seconds, so there
-- is nothing to rate-limit here -- this is a relay, and adding a second filter would only make the two
-- disagree. `false` means "not derivable", which the page draws as a dash and NOT as a needle at rest.
RegisterNetEvent("ncm:tyre", function(v)
    if not page then return end
    pcall(function() page:send("race:tyre", (type(v) == "table") and v or false) end)
end)

-- Derived component warnings are targeted to the current operator and contain system/severity only.
RegisterNetEvent("ncm:wear", function(v)
    if not page then return end
    pcall(function() page:send("race:wear", (type(v)=="table") and v or false) end)
end)

RegisterNetEvent("ncm:fuel", function(v)
    if not page then return end
    pcall(function() page:send("race:fuel", (type(v)=="table") and v or false) end)
end)
RegisterNetEvent("ncm:fuel.route", function(v, why)
    if type(v)=="table" and NcmNav then NcmNav.to(v, type(why)=="string" and why or "Fuel recovery") end
end)

local function instrumentState()
    local o = odoState
    if type(o) ~= "table" then return nil end
    if type(o.m) ~= "number" then return nil end
    return { odo = Identity.formatOdometer(o.m), name = o.name,
             serial = o.ord and Identity.formatOrdinal(o.ord) or nil }
end

-- ---------------------------------------------------------------------------------------------
-- Driver inputs: what my hands and feet are commanding right now (IDEA-366).
-- ---------------------------------------------------------------------------------------------
--
-- `31_CAPABILITY_AUDIT.md` §3 established that these three fields exist **only on the client snapshot** --
-- there is no `getThrottle` among the 138 server natives -- and §5 that `steering` exists at all only because
-- Open77's adapter reads the native lateral input directly, REDengine having no RTTI for it. So this display
-- is client-local by necessity, and anything it ever persists would be `client_attested`, never measured.
--
-- **It shows only what it read.** A field the running build does not expose renders as a dash, not as a
-- centred wheel or an empty pedal, because a confidently wrong instrument is worse than an absent one -- the
-- same rule as `IDEA-361` one layer up. The published cards answer for `op77.78` and this server runs `.87`,
-- so the field names are resolved against the live snapshot once and reported rather than assumed.
local inputNames = { throttle = { "throttle" }, brake = { "brake" }, steering = { "steering" } }
local inputField, inputResolved = {}, false
local lastInputs, lastInputAt = nil, 0

local function resolveInputFields(v)
    if inputResolved then return end
    inputResolved = true
    local found, missing = {}, {}
    for key, candidates in pairs(inputNames) do
        for _, name in ipairs(candidates) do
            if type(v[name]) == "number" then inputField[key] = name; break end
        end
        if inputField[key] then found[#found + 1] = key .. "=" .. inputField[key]
        else missing[#missing + 1] = key end
    end
    table.sort(found); table.sort(missing)
    log("driver inputs resolved: %s%s", table.concat(found, " "),
        #missing > 0 and ("  UNAVAILABLE: " .. table.concat(missing, " ")) or "")
end

--- Quantised so the HUD is driven by real movement rather than by float noise. A pedal to 2% and the wheel
--- to 1% is finer than the eye resolves at racing speed and still costs at most a handful of sends a second.
local function quantise(n, step)
    if n == nil then return nil end
    return math.floor(n / step + 0.5) * step
end

local function driverInputs()
    if type(NcmClientOwnVehicle) ~= "function" then return nil end
    local ok, v = pcall(NcmClientOwnVehicle)
    if not ok or type(v) ~= "table" then return nil end
    resolveInputFields(v)
    local function read(key, lo, hi)
        local name = inputField[key]
        if not name then return nil end
        local n = Reading(v[name])
        if n == nil then return nil end
        if n < lo then n = lo elseif n > hi then n = hi end
        return n
    end
    local t, b = read("throttle", 0, 1), read("brake", 0, 1)
    local st = read("steering", -1, 1)
    -- Nothing readable at all is not a neutral car; it is no car. Hide rather than show a resting cluster.
    -- **Speed rides with the inputs rather than getting its own event.** It comes off the same snapshot,
    -- at the same rate, and a second channel would be a second place for the two to disagree about
    -- whether the player is in a car.
    --
    -- Quantised to 1 km/h: the readout has no decimals, and an unquantised value would defeat the
    -- unchanged-state suppression below and push a message every frame.
    -- `speedKph` is the platform's own conversion; `speed` is m/s and the fallback when it is absent.
    local kph = Reading(v.speedKph)
    if kph == nil and type(v.speed) == "number" then kph = v.speed * 3.6 end
    if type(kph) == "number" then kph = math.floor(math.abs(kph) + 0.5) else kph = nil end

    if t == nil and b == nil and st == nil and kph == nil then return nil end
    return { throttle = quantise(t, 0.02), brake = quantise(b, 0.02), steering = quantise(st, 0.01),
             kph = kph }
end

local function pushInputs()
    if not page or not pageReady then return end
    local v = driverInputs()
    local key = v and (tostring(v.throttle) .. "/" .. tostring(v.brake) .. "/" .. tostring(v.steering)
        .. "/" .. tostring(v.kph)) or "off"
    local nowM = Open77.time.monotonic()
    -- Resend an unchanged state every two seconds so a page that reloaded mid-drive recovers on its own.
    if key == lastInputs and (nowM - lastInputAt) < 2 then return end
    lastInputs, lastInputAt = key, nowM
    -- **Proof a number reached the page**, not merely that the page exists. This is what the claim waits
    -- on, so the vanilla dial is only ever taken away once ours has something to show in its place.
    if v and type(v.kph) == "number" then haveSpeedReading = true end
    page:send("race:inputs", v or { off = true })
end

--- The ghost row, on its own channel for the same reason the driver inputs are (L166).
---
--- A ghost's delta changes continuously; folding it into `race:state` would defeat that payload's own
--- throttling, which exists because it is diffed and republished on race events.
---
--- **It is never a standings row.** The ghost has no position, is not counted in the field, and is drawn
--- separately from `#rows` -- a target, not an entrant. Giving it a `P` number is the one presentation
--- mistake this feature must not make.
local lastGhost = nil
local function pushGhost()
    if not page or not pageReady then return end
    local g = NcmClientGhost and NcmClientGhost() or nil
    local key = g and (tostring(g.mode) .. "/" .. tostring(g.present) .. "/" .. tostring(g.elapsedMs)
        .. "/" .. tostring(g.deltaMs) .. "/" .. tostring(g.playing) .. "/" .. tostring(g.none)) or "off"
    if key == lastGhost then return end
    lastGhost = key
    page:send("race:ghost", g or { present = false })
end

-- ---------------------------------------------------------------------------------------------
-- THE VANILLA SPEEDOMETER LIES, AND IT CANNOT BE CORRECTED -- SO IT IS REPLACED (`IDEA-563`)
-- ---------------------------------------------------------------------------------------------
--
-- Measured 2026-09-26 against the physics probe and against TweakDB's own authored gear ceiling,
-- which agree with each other to within 2%:
--
--   stock Galena, flat out   29.5 m/s   = 66 mph true   -- vanilla dial read 90
--   whole chain stretched    37.6 m/s   = 84 mph true   -- vanilla dial read past 135
--
-- It was wrong by x1.34 before NCM touched anything, and the error GREW every time the gear bands
-- moved, so it is not reading ground speed. `Open77.hud.setVisible` controls VISIBILITY, not value --
-- there is no way to correct the number, only to stop showing it.
--
-- **Freeroam's rule, inherited deliberately: never hide a vanilla widget unless the replacement is
-- actually live.** A player with no speedometer is worse off than one with a wrong speedometer, so the
-- claim waits for the page to be ready AND for a real reading to have arrived, and the claim is
-- released on resource stop so a reload never leaves the HUD permanently missing a component.
local function claimVanillaSpeedometer(claim)
    if type(Open77.hud) ~= "table" or type(Open77.hud.setVisible) ~= "function" then
        return false, "hud API unavailable"
    end
    local ok, accepted, result = pcall(Open77.hud.setVisible, "speedometer", not claim)
    if ok and accepted then return true end
    return false, tostring(ok and result or accepted)
end

local function reconcileSpeedometerClaim()
    if speedoClaimed or not pageReady or not haveSpeedReading then return end
    -- Throttled: a refusal must not become a once-per-tick retry storm in the client log.
    local at = Open77.time.monotonic()
    if (at - lastSpeedoClaimAt) < 2 then return end
    lastSpeedoClaimAt = at
    local ok, why = claimVanillaSpeedometer(true)
    if ok then
        speedoClaimed = true
        log("vanilla speedometer hidden -- it reads roughly 2.6x true speed and cannot be corrected, "
            .. "only replaced. NCM's km/h readout is the speedometer now.")
    else
        log("vanilla speedometer NOT hidden (%s) -- leaving it visible rather than leaving the driver "
            .. "with no speed at all", tostring(why))
    end
end

--- Give the component back. A resource that claims and never releases leaves the player's HUD short a
--- widget with nothing on screen explaining why.
AddEventHandler("onClientResourceStop", function(name)
    if name ~= GetCurrentResourceName() or not speedoClaimed then return end
    local ok, why = claimVanillaSpeedometer(false)
    speedoClaimed = false
    log("vanilla speedometer restored on stop (%s)", ok and "accepted" or tostring(why))
end)

CreateThread(function()
    Wait(4000)
    while true do
        pcall(pushInputs)
        pcall(pushGhost)
        pcall(reconcileSpeedometerClaim)
        -- 20 Hz while there is something to show, 2 Hz when out of a car. The platform's own observers run at
        -- 30 Hz; 20 is smooth to the eye for pedal travel and costs a third less traffic.
        Wait(lastInputs ~= "off" and 50 or 500)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- `/ncm.wsprobe` -- can this page reach a local companion? (IDEA-387)
-- ---------------------------------------------------------------------------------------------
--
-- Official OPEN//77 docs say a bundled page may use fetch/XHR and WS/WSS, and that localhost is the player's
-- PC and not the game server. That settles the PLATFORM. It does not settle the BROWSER: a page served from
-- an `https://` origin may not open a `ws://` connection. Chromium treats `127.0.0.1` as potentially
-- trustworthy, which normally exempts it -- but that carve-out has shifted across releases and interacts with
-- Private Network Access, so it is a question about the build in front of us.
--
-- **Inert unless invoked.** No thread, no tick, nothing sent until someone types the command. It also reports
-- the page's own `origin` and `isSecureContext`, which is the bundled-virtual-HTTPS question answered by the
-- client instead of guessed.
--
-- Run `python tools/ws-probe-server.py` first, then `/ncm.wsprobe` in game.
-- `/ncm.bridgeprobe` -- the candidate solution, after the bundled page failed (IDEA-387).
--
-- Round 2 was conclusive and negative: from the bundled page, `ws`, `wss`, `http` and `https` were ALL
-- refused in ~0ms, the whole five-trial matrix finishing in 1ms. Nothing touched a socket. That is not mixed
-- content -- a mixed-content block would have spared the secure schemes -- it is a bundled origin with no
-- outbound network at all. Its origin is `https://r-NN-g-1.cym-ui`, a private scheme.
--
-- `Open77.webui.create` names the way out:
--
--   > "An HTTP(S) `entry` does not require `web_files` ... External scripts, media, requests and embeds
--   >  follow browser CORS and TLS rules. **Only the configured top-level entry origin receives the Lua
--   >  bridge.**"
--
-- So: serve the page FROM the companion. Its origin is then a real `http://127.0.0.1:<port>`, a WebSocket
-- back to it is **same-origin** -- no CORS, no mixed content, nothing to negotiate -- and that sentence says
-- the Lua bridge still reaches it.
--
-- **This is a separate, hidden surface and not the race HUD.** If the companion is not running the surface
-- simply fails to load, and the HUD is untouched. The HUD must never depend on an external process.
local bridgePage = nil

RegisterCommand("ncm.bridgeprobe", function(_, args)
    local url = (args and args[1]) and tostring(args[1]) or "http://127.0.0.1:38480/bridge.html"
    if bridgePage then
        pcall(function() bridgePage:destroy() end)
        bridgePage = nil
    end
    log("bridgeprobe: creating a WebUI surface with a REMOTE entry: %s", url)
    local p, reason = WebUI.create({
        entry = url, layer = "hud", width = 16, height = 16,
        zIndex = 1, transparent = true, visible = false,
    })
    if not p then
        log("bridgeprobe: WebUI.create REFUSED the remote entry: %s", tostring(reason))
        return
    end
    bridgePage = p
    p:on("ncm:bridge.result", function(r)
        if type(r) ~= "table" then log("bridgeprobe: malformed result"); return end
        log("bridgeprobe: %s | origin=%s secureContext=%s hasBridge=%s | %s",
            tostring(r.stage), tostring(r.origin), tostring(r.secureContext),
            tostring(r.hasBridge), tostring(r.detail))
    end)
    log("bridgeprobe: surface created; waiting for the page to report")
end, false)

RegisterCommand("ncm.wsprobe", function(_, args)
    local url = (args and args[1]) and tostring(args[1]) or "ws://127.0.0.1:38480"
    if not page or not pageReady then
        log("wsprobe: race HUD page is not ready; cannot probe")
        return
    end
    log("wsprobe: asking the HUD page to open %s", url)
    page:send("race:wsprobe", { url = url })
end, false)

local function present()
    local instr = instrumentState()
    if not view or view.phase == "none" or not me then clearAll(instr); return end
    NcmClientRaceActive = true
    NcmClientRacePhase = tostring(view.phase)
    local pos = localPosition()
    local n = #view.entrants
    local phase = view.phase
    local now = serverNow()
    local state = { tree = false, banner = currentBanner(), instrument = instr }
    local isQuali = view.kind == "quali" or view.kind == "practice"
    local sessionTag = (view.ofSessions or 1) > 1 and ((view.kind == "race" and view.formatId == "two_race") and (" · RACE " .. tostring(view.ordinal or 1)) or (isQuali and (" · " .. string.upper(view.kind)) or "")) or ""

    -- Time attack sessions (practice / qualifying): open window, runs, best time.
    if isQuali then
        removeMarker("slot"); removeMarker("grid")
        local best = me.bestSec and fmt(me.bestSec) or "--"
        -- Where to go is never a guess: forming → the start line is marked and routed on the map (a driver who
        -- just finished practice is at the far end of the course); open → the next gate, and the map route back to
        -- the start whenever a run is not in progress (Batch 1 live, 2026-09-21).
        -- Markers carry no label: the platform turns a labelled marker into an "E" card even with nothing behind
        -- it (owner QA 2026-09-21). The strip says what the marker is and how far.
        local start = view.gates[1]
        local runsLeft = (view.maxRuns or 99) - (me.runs or 0)
        if phase == "forming" then
            local label = view.kind == "quali" and "Qualifying" or "Practice"
            state.strip = { kind = "grid", eyebrow = string.upper(view.kind) .. " · " .. (view.routeName or ""), big = Entry.countdown(view.startsAt - now), mid = label .. " opens · stage at the start line", dim = "" }
            if start then
                local d = pos and Routes.planarDistance(pos, start) or nil
                ensureMarker("gate", { x = start.x, y = start.y, z = start.z, radius = 6.0, color = "#F5C95C" })
                state.strip.dim = (d and d > 30) and ("start line %s away"):format(km(d)) or "you are staged · wait for the window"
                if gridGpsFor ~= view.sessionId then gridGpsFor = view.sessionId; gpsTo(start, view.kind .. " start") end
            else
                removeMarker("gate")
            end
        elseif phase == "open" then
            local nextIndex = (me.runProgress or 0) + 1
            local g = view.gates[nextIndex]
            local onRun = (me.runProgress or 0) > 0
            if g and (onRun or runsLeft > 0) then
                ensureMarker("gate", { x = g.x, y = g.y, z = g.z, radius = math.min(50, g.captureM or 12), color = g.kind == "finish" and "#3BE28A" or (g.kind == "start" and "#F5C95C" or "#00E5FF") })
            else
                removeMarker("gate")
            end
            local d = pos and g and Routes.planarDistance(pos, g) or nil
            -- the map always routes to the next gate: the start before a run, the next gate during one
            local gpsKey = view.sessionId .. ":" .. tostring(me.runs or 0) .. ":" .. tostring(nextIndex)
            if g and (onRun or runsLeft > 0) and gridGpsFor ~= gpsKey then gridGpsFor = gpsKey; gpsTo(g, "next gate " .. tostring(g.kind)) end
            local mid
            if onRun then mid = ("run %d · gate %d/%d"):format(me.runs or 1, me.runProgress or 0, #view.gates)
            elseif runsLeft <= 0 then mid = "run complete · waiting for the window"
            elseif (view.maxRuns or 99) == 1 then mid = "one run · cross the start when ready"
            else mid = "no run · cross the start" end
            local gateName = g and (g.kind == "finish" and "finish" or (g.kind == "start" and "start line" or (g.name or "next gate"))) or ""
            local dim = (g and (onRun or runsLeft > 0)) and ("%s to the %s"):format(d and km(d) or "?", gateName) or ""
            state.strip = { kind = "", eyebrow = string.upper(view.kind) .. " · best " .. best, big = Entry.countdown((view.closesAt or now) - now), mid = mid, dim = dim }
        elseif phase == "complete" then
            if not (view.next and start) then removeMarker("gate") end
            local mine, rows = nil, {}
            for _, r in ipairs(view.results or {}) do
                if r.driverId == me.driverId then mine = r end
                rows[#rows + 1] = { pos = r.position, name = tostring(r.display), time = r.bestSec and fmt(r.bestSec) or "no time", gap = r.gapSec and ("+" .. string.format("%.1f", r.gapSec)) or "", me = r.driverId == me.driverId }
            end
            local nxt = view.next and (("%s in %s — go to the start line%s"):format(view.next.kind == "race" and "race" or view.next.kind, Entry.countdown((view.next.at or now) - now), view.next.gridFrom == "quali" and " · your grid slot comes from this result" or "")) or ""
            if view.next and start then
                ensureMarker("gate", { x = start.x, y = start.y, z = start.z, radius = 6.0, color = "#F5C95C" })
                local gpsKey = view.sessionId .. ":complete"
                if gridGpsFor ~= gpsKey then gridGpsFor = gpsKey; gpsTo(start, "next session start") end
            end
            if boardOn(view.sessionId) then
                state.strip = { kind = "done", eyebrow = string.upper(view.kind) .. " · " .. (view.routeName or ""), big = mine and ("P%d"):format(mine.position) or "", mid = mine and (mine.bestSec and fmt(mine.bestSec) or "no time") or "", dim = nxt }
                state.board = { title = ("%s · %s · %s"):format(view.seriesName or "NCM", view.routeName or "", string.upper(view.kind)), rows = rows }
            elseif nxt ~= "" then
                state.strip = { kind = "done", eyebrow = string.upper(view.kind) .. " · done", big = "", mid = nxt, dim = "" }
            end
        end
        hud(state)
        return
    end

    -- A driver who is out of it (DNS / DNF) gets one short notice, then the race HUD lets go so the
    -- heartbeat returns; they must never see another driver's lights or a strip pointing at a start.
    if (me.state == "dns" or me.state == "dnf") and phase ~= "complete" then
        if not outNoticeUntil then outNoticeUntil = Open77.time.monotonic() + 8 end
        removeMarker("gate"); removeMarker("slot")
        if Open77.time.monotonic() < outNoticeUntil then
            state.strip = me.state == "dns" and { kind = "grid", eyebrow = "DID NOT START", big = "DNS", mid = "you were not on your mark at T-30", dim = view.routeName or "" }
                or { kind = "grid", eyebrow = "DNF", big = "OUT", mid = "classified by progress", dim = view.routeName or "" }
            hud(state)
        else
            clearAll()
        end
        return
    end

    if phase == "forming" or phase == "gridded" then
        local slot = view.slots and view.slots[me.slot]
        if slot then
            local d = pos and Routes.planarDistance(pos, slot) or nil
            -- Far from the SLOT is what matters: the venue's grid point can sit at the other end of a route.
            local grid = (d and d > 60) and slot or (view.grid or slot)
            local dGrid = d
            local teamTag = me.teamName and (string.upper(me.teamName) .. " · ") or (me.teamId and (string.upper(tostring(me.teamId)):gsub("_", " ") .. " · ") or "")
            local carTag = me.number and ("#" .. me.number) or ("P" .. me.slot)
            -- Grid reveal (L48): far away -> REPORT TO GRID; close -> your car, in your team's colour, with a prompt.
            if dGrid and dGrid > 60 then
                removeMarker("slot")
                ensureMarker("grid", { x = grid.x, y = grid.y, z = grid.z, radius = 6.0, color = "#F5C95C" })
                if gridGpsFor ~= view.sessionId then gridGpsFor = view.sessionId; gpsTo(grid, "report to grid") end
            else
                removeMarker("grid")
                ensureMarker("slot", { x = slot.x, y = slot.y, z = slot.z, radius = 3.0, color = me.colour or "#F5C95C",
                    label = me.number and ("YOUR CAR · #%d %s"):format(me.number, me.teamName or "") or ("YOUR MARK · P%d"):format(me.slot),
                    description = me.number and "hold E to get in" or nil, event = me.number and "ncm:yourCarPrompt" or nil, key = "E", holdSeconds = 0.6 })
            end
            local holdText = view.hold and ("holding · %d/%d on the grid"):format(view.hold.ready or 0, view.hold.total or n) or nil
            if me.state == "ready" then
                state.strip = { kind = "grid", eyebrow = teamTag .. "ON YOUR MARK" .. sessionTag, big = carTag, mid = holdText or ("P%d of %d · hold position"):format(me.slot, n),
                                dim = view.hold and ("lights when %d%% are in, or in %s"):format(75, Entry.countdown((view.hold.deadline or now) - now))
                      or ((view.startsAt - now - 5) > 0 and ("lights in " .. Entry.countdown(view.startsAt - now - 5)) or "waiting for the field") }
            elseif me.state == "dns" then
                state.strip = { kind = "grid", eyebrow = "DID NOT START", big = "DNS", mid = "not on your mark in time", dim = "" }
            else
                state.strip = { kind = "grid", eyebrow = teamTag .. (dGrid and dGrid > 60 and "REPORT TO GRID" or "GRID FORMING") .. sessionTag, big = carTag,
                                mid = ("P%d of %d · %s"):format(me.slot, n, dGrid and dGrid > 60 and (km(dGrid) .. " to the grid") or ("your car · " .. (d and km(d) or "?"))),
                                dim = holdText or ((view.startsAt - now - (view.gridHoldBeforeSec or 30)) > 0
                                    and ("grid closes in " .. Entry.countdown(view.startsAt - now - (view.gridHoldBeforeSec or 30)))
                                    or "grid closed · get to your mark or you are DNS at the deadline") }
            end
        end
        removeMarker("gate")
    elseif phase == "countdown" or (phase == "running" and now < view.startsAt + 2.5) then
        removeMarker("slot")
        local t = view.startsAt - now
        state.tree = true
        if t > 0 then
            state.lights = math.max(0, math.min(5, math.floor(5 - t) + 1))
            state.strip = { kind = "grid", eyebrow = view.routeName or "", big = "", mid = "hold until the lights go out", dim = "" }
        else
            state.lights = 0; state.out = true
            if goShownFor ~= view.sessionId then goShownFor = view.sessionId; banner("go", "GO", nil, 2.5) end
            state.banner = currentBanner()
        end
    elseif phase == "running" or phase == "finishing" then
        removeMarker("slot")
        local nextIndex = (me.progress or 0) + 1
        local g = view.gates[nextIndex]
        if me.state == "finished" then
            state.strip = { kind = "done", eyebrow = "FINISHED", big = fmt(me.totalSec), mid = "waiting for the field", dim = Entry.countdown((view.firstFinishAt or now) + (view.finishWindowSec or 60) - now) }
            removeMarker("gate")
        elseif me.state == "dnf" then
            state.strip = { kind = "grid", eyebrow = "DNF", big = "OUT", mid = "classified by progress", dim = "" }
            removeMarker("gate")
        elseif me.state == "suspended" then
            state.strip = { kind = "grid", eyebrow = "RECONNECTING", big = "HOLD", mid = "your seat is kept for 60 s", dim = "" }
        elseif g then
            ensureMarker("gate", { x = g.x, y = g.y, z = g.z, radius = math.min(50, g.captureM or 12), color = (g.kind == "finish" or g.kind == "green") and "#3BE28A" or "#00E5FF" })
            -- The MARKER stands on the next scoring gate; NAVIGATION may not. Gate 1 is the start line
            -- (`discipline.buildCourse`), and a driver whose start has not been credited yet is sitting ON it:
            -- routing them to it is the "GPS keeps pointing at the start" report from Hook, 2026-09-23. Route
            -- to the first gate that is somewhere to go. A rolling start's `green` gate IS somewhere to go and
            -- is deliberately not skipped.
            local navGate = (g.kind == "start" and view.gates[nextIndex + 1]) or g
            local gpsKey = view.sessionId .. ":race:" .. tostring(navGate.index or nextIndex)
            if gridGpsFor ~= gpsKey then gridGpsFor = gpsKey; gpsTo(navGate, "race gate " .. tostring(navGate.index or nextIndex)) end
            local d = pos and Routes.planarDistance(pos, g) or nil
            local elapsed = view.greenAt and (now - view.greenAt) or 0
            local formation = view.start == "rolling" and not view.rollingGreenAt
            local solo = #(view.entrants or {}) <= 1
            -- Live running order: finished by time, then racers by progress, then by distance to the next gate.
            local order = {}
            for _, en in ipairs(view.entrants) do
                if en.state == "finished" or en.state == "racing" or en.state == "suspended" then order[#order + 1] = en end
            end
            table.sort(order, function(a, b)
                local fa, fb = a.state == "finished", b.state == "finished"
                if fa ~= fb then return fa end
                if fa then return (a.totalSec or 0) < (b.totalSec or 0) end
                if (a.progress or 0) ~= (b.progress or 0) then return (a.progress or 0) > (b.progress or 0) end
                local da = a.driverId == me.driverId and d or a.toNextM
                local db = b.driverId == me.driverId and d or b.toNextM
                return (da or math.huge) < (db or math.huge)
            end)
            local myPos = 0
            for i, en in ipairs(order) do if en.driverId == me.driverId then myPos = i end end
            local inc = (me.incidentSec or 0) > 0 and (" · +%.0fs inc"):format(me.incidentSec) or ""
            if formation then
                state.strip = { kind = "grid", eyebrow = "FORMATION · " .. (view.routeName or "") .. sessionTag, big = ("P%d"):format(me.slot or myPos), mid = ("hold your place · under %d km/h"):format(view.paceKph or 80), dim = ("%s to the green flag · the leader starts the race"):format(d and km(d) or "?") }
            elseif solo then
                -- KB-33 / L67: a field of one is a time trial for its whole length, not only at settlement. The
                -- clock is the hero value; there is no position to hold. (Field size, not the live order: a race
                -- whose other cars have all retired is still a race.)
                state.strip = { kind = "", eyebrow = "TIME TRIAL · " .. (view.routeName or "") .. sessionTag,
                                big = Entry.countdown(elapsed), mid = ("gate %d/%d%s"):format(me.progress or 0, #view.gates, inc),
                                dim = ("%s to %s"):format(d and km(d) or "?", g.name or g.kind) }
            else
            state.strip = { kind = "", eyebrow = "RACING · " .. (view.routeName or "") .. sessionTag, big = ("P%d"):format(myPos), mid = ("of %d · %s · gate %d/%d%s"):format(#order, Entry.countdown(elapsed), me.progress or 0, #view.gates, inc), dim = ("%s to %s"):format(d and km(d) or "?", g.name or g.kind) }
            end
        end
    elseif phase == "complete" then
        removeMarker("gate"); removeMarker("slot")
        local mine, rows = nil, {}
        for _, r in ipairs(view.results or {}) do
            if r.driverId == me.driverId then mine = r end
            local timeText = r.state == "finished" and fmt(r.correctedSec or r.totalSec) or string.upper(tostring(r.state))
            if r.state == "dnf" then timeText = ("DNF %d/%d"):format(r.progress or 0, r.gatesTotal or #view.gates) end
            rows[#rows + 1] = {
                pos = r.position, name = tostring(r.display) .. (r.jumpStart and "  (JS +5)" or "") .. ((r.incidentSec or 0) > 0 and ("  (+%.0fs inc)"):format(r.incidentSec) or ""),
                time = timeText, gap = r.gapSec and ("+" .. string.format("%.1f", r.gapSec)) or "",
                me = r.driverId == me.driverId,
            }
        end
        if mine then
            local nxt = view.next and (("next: %s %s in %s"):format(view.next.kind, view.next.kind == "race" and tostring(view.next.ordinal or "") or "", Entry.countdown((view.next.at or now) - now))) or ""
            -- L67/IDEA-001: a field of one is a time trial, so the banner never claims a position.
            local solo = (n <= 1)
            if boardOn(view.sessionId) then
                local myTime = mine.state == "finished" and fmt(mine.correctedSec or mine.totalSec) or string.upper(mine.state)
                state.strip = solo
                    -- solo: the time is the hero value, because there is no position to show
                    and { kind = "done", eyebrow = "TIME TRIAL · " .. (view.routeName or "") .. sessionTag,
                          big = myTime, mid = "", dim = nxt }
                    or  { kind = "done", eyebrow = "RESULT · " .. (view.routeName or "") .. sessionTag,
                          big = ("P%d"):format(mine.position), mid = ("of %d · %s"):format(n, myTime), dim = nxt }
                state.board = { title = ("%s · %s · %s"):format(view.seriesName or "NCM", view.routeName or "",
                    solo and "time trial" or ("%d entrant(s)"):format(n)), rows = rows }
            elseif nxt ~= "" then
                state.strip = { kind = "done", eyebrow = "NEXT" .. sessionTag, big = "", mid = nxt, dim = "" }
            end
        end
    end
    if phase == "running" or phase == "finishing" then state.graph = graphState() end
    hud(state)
end

-- ---------------------------------------------------------------------------------------------
-- Crossing detection (runs at 20 Hz while racing)
-- ---------------------------------------------------------------------------------------------
local function detect()
    if not view or not me then prevPos = nil; return false end
    local phase = view.phase
    local isQuali = view.kind == "quali" or view.kind == "practice"
    if isQuali then
        if phase ~= "open" then prevPos = nil; return false end
    else
        if not (phase == "countdown" or phase == "running" or phase == "finishing") then prevPos = nil; origin = nil; return false end
        if me.state ~= "racing" then return false end
    end
    local pos = localPosition()
    if not pos then return true end
    -- The start origin is only meaningful if taken at the grid during the lights. A client that first
    -- sees a running race later (reconnect, restart) must reach the real start point instead.
    if not origin and phase == "countdown" then origin = pos; log("start origin recorded at the grid %.1f %.1f", pos.x, pos.y) end
    local nextIndex = (isQuali and (me.runProgress or 0) or (me.progress or 0)) + 1
    local g = view.gates[nextIndex]
    if isQuali and nextIndex == 1 and crossed[1] and (Open77.time.monotonic() - crossed[1]) > 4 then crossed[1] = nil; retries[1] = nil end   -- a new run may start
    if g and prevPos then
        local hit = Gates.crossed(g, prevPos, pos) or (not isQuali and g.kind == "start" and origin ~= nil and Gates.startedFrom(origin, pos, g.leaveM))
        if not crossed[nextIndex] and hit then
            crossed[nextIndex] = Open77.time.monotonic()
            report(nextIndex)
        elseif crossed[nextIndex] and (Open77.time.monotonic() - (reported[nextIndex] or 0)) > 2.0 and (retries[nextIndex] or 0) < 5 then
            -- The server has not advanced our progress: retry a few times while still near the gate.
            if Routes.planarDistance(pos, g) <= (g.armM or 60) then retries[nextIndex] = (retries[nextIndex] or 0) + 1; report(nextIndex) end
        end
    end
    prevPos = pos
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Threads
-- ---------------------------------------------------------------------------------------------
-- The live session wins when it includes me; otherwise the practice I am an entrant of (P48: one per event,
-- GlobalState.ncmPractice); otherwise whatever the live session says (so a non-entrant still sees "none").
local function pickView()
    local id = myDriverId()
    local pid = myPlayerId()
    local ss = GlobalState and GlobalState.ncmSessions or nil
    local serverNow = (type(ss) == "table" and tonumber(ss.serverNow)) or nil
    -- The targeted entrant stream is authoritative for presentation. Keep GlobalState below as a recovery path,
    -- but do not make a live driver's HUD depend on a nested shared-map replication detail.
    local targetedIds = {}
    for sid, v in pairs(targetedViews) do
        if type(v) == "table" and v.phase and v.phase ~= "none" then targetedIds[#targetedIds + 1] = sid end
    end
    table.sort(targetedIds)
    if #targetedIds > 0 then return targetedViews[targetedIds[1]] end
    -- IDEA-112: several races can be live at once, so "the session" is no longer a thing -- there is only
    -- "the session I am in". Sorted, because iteration order over a string-keyed table is not deterministic and
    -- a driver must not be handed a different race on alternate ticks if they somehow appear in two.
    -- KB-79: selecting the session used to require the replicated local player's `ncm.driverId`, even though
    -- the host deliberately publishes `playerId` and the entrant match below already accepts it. During the
    -- failed live race that local bag was not usable here: the server formed, gridded and greened the owner,
    -- while this client never selected/logged the session. Player id is the connection-local authoritative
    -- fallback; driver id remains the durable fallback across a reconnect.
    if type(ss) == "table" and (pid or id) then
        local ids = {}
        for sid, v in pairs(ss) do if type(v) == "table" and v.phase and v.phase ~= "none" then ids[#ids + 1] = sid end end
        table.sort(ids)
        for _, sid in ipairs(ids) do
            for _, en in ipairs(ss[sid].entrants or {}) do
                if (pid and tonumber(en.playerId) == pid) or (id and en.driverId == id) then return ss[sid] end
            end
        end
    end
    local pr = GlobalState and GlobalState.ncmPractice or nil
    if type(pr) == "table" and id then
        local keys = {}
        for k, pv in pairs(pr) do if type(pv) == "table" and pv.phase == "open" then keys[#keys + 1] = k end end
        table.sort(keys)
        for _, k in ipairs(keys) do
            for _, en in ipairs(pr[k].entrants or {}) do if en.driverId == id then return pr[k] end end
        end
    end
    -- In no session: a synthetic "none" view, because the HUD clears on receiving one rather than on nil (the
    -- main loop has no else branch -- a nil would leave the last view frozen on screen forever).
    -- NOTE: this is a deliberate behaviour change. A non-entrant used to be handed whatever single race was
    -- live; with several live there is no defensible answer to "which one", so a spectator now sees nothing
    -- until spectating is designed.
    return { phase = "none", serverNow = serverNow or (GlobalState and GlobalState.ncmPractice and GlobalState.ncmPractice.serverNow) or 0 }
end

RegisterNetEvent("ncm:session", function(sessionId, sessionView)
    sessionId = tostring(sessionId or "")
    if sessionId == "" then return end
    if type(sessionView) ~= "table" then
        targetedViews[sessionId] = nil
        log("targeted session %s retired", sessionId)
        return
    end
    targetedViews[sessionId] = sessionView
    log("targeted session %s received phase=%s entrants=%d", sessionId, tostring(sessionView.phase), #(sessionView.entrants or {}))
end)

CreateThread(function()
    Wait(2500)
    while true do
        local g = pickView()
        if type(g) == "table" then
            if not view or g.serverNow ~= view.serverNow then
                base = { serverNow = tonumber(g.serverNow) or 0, mono = Open77.time.monotonic() }
            end
            if g.sessionId ~= sessionSeen then
                sessionSeen = g.sessionId
                crossed, reported, retries, prevPos, origin, outNoticeUntil, courseLen = {}, {}, {}, nil, nil, nil, nil
                -- A new session inherits no navigation from the last one (owner QA 2026-09-23: Hook, entered
                -- and started after two completed races, kept routing to a start).
                gridGpsFor, gpsTarget = nil, nil
                if g.sessionId then log("session %s (%s) phase=%s", tostring(g.sessionId), tostring(g.routeName), tostring(g.phase)) end
            end
            local before = view and view.phase
            view = g
            NcmClientView = g   -- client/telemetry.lua samples against the view the HUD shows (a practice included)
            me = nil
            local id = myDriverId()
            local myPid = myPlayerId()
            for _, en in ipairs(g.entrants or {}) do
                if (myPid and en.playerId == myPid) or (id and en.driverId == id) then me = en end
            end
            -- Exported rather than re-derived. The seat/identity dance is the one thing a second consumer
            -- must not copy: a second copy is a second place for it to drift out of agreement with the view
            -- the driver is actually looking at (the same reason `NcmClientOwnVehicle` is a single accessor).
            NcmClientMyEntrant = me
            if not me and g.sessionId and g.sessionId ~= notMine then
                notMine = g.sessionId
                log("session %s: not an entrant (localId=%s driverId=%s entrants=%d)", tostring(g.sessionId), tostring(myPid), tostring(id), #(g.entrants or {}))
            end
            if me and before ~= g.phase then
                log("phase %s -> %s (me: %s progress=%d)", tostring(before), g.phase, me.state, me.progress or 0)
            end
            if me and lastMe then
                if me.state == "finished" and lastMe.state ~= "finished" then banner("go", "FINISH", fmt(me.correctedSec or me.totalSec), 4) end
                if g.start == "rolling" and g.rollingGreenAt and not (lastView and lastView.rollingGreenAt) then banner("go", "GREEN FLAG", "race on", 3) end
                if (me.incidentSec or 0) > (lastMe.incidentSec or 0) then
                    banner("bad", ("INCIDENT +%.0f s"):format((me.incidentSec or 0) - (lastMe.incidentSec or 0)), ("total +%.0f s"):format(me.incidentSec or 0), 3)
                end
                if (me.runProgress or 0) == 0 and (lastMe.runProgress or 0) > 0 then crossed = {}; reported = {}; retries = {} end   -- quali run ended: next run may re-cross every gate
                if (me.penaltySec or 0) > (lastMe.penaltySec or 0) then
                    local added = (me.penaltySec or 0) - (lastMe.penaltySec or 0)
                    if me.jumpStart and not lastMe.jumpStart then banner("bad", "JUMP START", ("+%d s"):format(added), 3)
                    else banner("bad", ("PENALTY +%d s"):format(added), "race control", 3) end
                end
            end
            lastMe = me and { state = me.state, penaltySec = me.penaltySec, progress = me.progress, jumpStart = me.jumpStart, incidentSec = me.incidentSec, runProgress = me.runProgress } or nil
            lastView = { rollingGreenAt = g.rollingGreenAt }
        end
        local ok, err = pcall(present)
        if not ok then log("present error: %s", tostring(err)) end
        Wait(100)
    end
end)

CreateThread(function()
    while true do
        local ok, racing = pcall(detect)
        if not ok then log("detect error: %s", tostring(racing)) end
        Wait(racing == true and 50 or 500)
    end
end)

-- The server asking the client to navigate somewhere: interest routes to the venue, and a successful race or
-- practice entry routes to the first point on the COURSE (see `NcmCalendar.enter`). `why` is supplied by the
-- caller so the log names the real reason rather than assuming interest.
RegisterNetEvent("ncm:guide.route", function(p)
    if type(p) == "table" and p.x then gpsTo(p, (tostring(p.why or "guide interest") .. ": " .. tostring(p.name))) end
end)

-- YOUR CAR: the marker prompt fires a local event; the server puts us in the driver seat.
AddEventHandler("ncm:yourCarPrompt", function()
    if view and view.sessionId then
        log("YOUR CAR prompt -> server")
        TriggerServerEvent("ncm:yourCar", view.sessionId)
    end
end)

-- /ncm.debug (host kit): what this client believes — phase, my state, next gate + distance, gps target,
-- telemetry — as a banner and one log line, so a tester's screenshot explains itself.
RegisterCommand("ncm.debug", function()
    local pos = localPosition()
    local phase = view and view.phase or "none"
    local isQuali = view and (view.kind == "quali" or view.kind == "practice")
    local nextIndex = me and ((isQuali and (me.runProgress or 0) or (me.progress or 0)) + 1) or nil
    local g = view and nextIndex and view.gates and view.gates[nextIndex] or nil
    local d = (pos and g) and Routes.planarDistance(pos, g) or nil
    local line = ("session=%s kind=%s phase=%s me=%s progress=%s next=%s dist=%s gps=%s pos=%s telemetry=%s"):format(
        tostring(view and view.sessionId), tostring(view and view.kind), phase, me and me.state or "-", me and tostring(me.progress or me.runProgress or 0) or "-",
        g and (tostring(g.index) .. ":" .. tostring(g.kind)) or "-", d and math.floor(d) or "-", gpsTarget and tostring(gpsTarget.why) or "-",
        pos and ("%.0f,%.0f,%.0f"):format(pos.x, pos.y, pos.z) or "?", NcmClientTelemetryStatus and NcmClientTelemetryStatus() or "?")
    log("DEBUG %s", line)
    banner("go", "DEBUG · " .. phase .. (me and (" · " .. me.state) or ""), (g and ("next " .. tostring(g.kind) .. " " .. (d and math.floor(d) .. " m" or "")) or "no gate") .. " · gps " .. tostring(gpsTarget and gpsTarget.why or "-"), 6)
end, false)

-- The live race graph: F8 or /ncm.graph toggles it (P40; on by default).
local function toggleGraph()
    NcmClientGraphOn = not NcmClientGraphOn
    log("race graph %s", NcmClientGraphOn and "on" or "off")
    lastSent = nil
end
pcall(function() RegisterKeyMapping("ncm.graph", "NCM: race graph", "F8", toggleGraph) end)
RegisterCommand("ncm.graph", toggleGraph, false)
NcmQuickActions = NcmQuickActions or {}
NcmQuickActions.graph = toggleGraph

AddEventHandler("onClientResourceStop", function(name)
    if name == "ncm_world" then clearAll() end
end)
