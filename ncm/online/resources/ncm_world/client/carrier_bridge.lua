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

-- ---------------------------------------------------------------------------------------------------
-- `KB-147`: the carrier's port is no longer fixed, so this has to LOOK for it.
-- ---------------------------------------------------------------------------------------------------
--
-- Two game instances on one PC each load the carrier from the same directory and read the same
-- `ncm_carrier.json`. Only one can hold 38480, so the second walks up to the next free port -- which is
-- why a second client has never had Parts, telemetry or force feedback at all.
--
-- **The danger this creates, and why it is the carrier that guards it:** if this client simply scanned
-- until something answered, it would happily attach to the OTHER game's carrier whenever that one bound
-- first, and start pushing this player's Parts into the other player's physics. Nothing in the Lua
-- sandbox knows its own process id, so this side cannot tell two loopback carriers apart. The carrier
-- can, and does -- it refuses any peer that is not its own process (`bridge/server.cpp`). This scan is
-- therefore safe by construction: a wrong port is refused, not silently served.
-- Rig input/feel and Machine projection are deliberately different products now.  Keeping them on separate
-- ranges prevents an FFB surface from ever consuming the Carrier's only socket (or vice versa).
--
-- ---------------------------------------------------------------------------------------------------
-- **THE CARRIER SERVES ONE CLIENT AT A TIME, SO A PORT IS A LOCK AND NOT A CHANNEL** (`KB-177`).
-- ---------------------------------------------------------------------------------------------------
--
-- `Server::run` in `bridge/server.cpp` is a serial accept loop: `serveWebSocket` blocks until that one
-- socket closes, and only then does `accept` return again. Two surfaces cannot share a Carrier. Whichever
-- one connects first OWNS it, and the other waits forever on a port that looks alive.
--
-- That made the skip rule load-bearing, and **the first version pointed it the wrong way**. It protected
-- FORCE FEEDBACK -- the machine walk refused to use the FFB channel's port -- and top speed only ever
-- worked by accident: the retired companion held 38480, so the Carrier fell to 38481 and the machine walk
-- could reach it. The moment the companion stopped being started, the Carrier bound 38480, the machine
-- channel skipped it by rule, and every car in the world silently went back to its stock gearbox. Seven
-- live sessions say it exactly: Carrier on 38481 -> 42 gear chains applied; Carrier on 38480 -> zero.
--
-- **The Machine channel outranks force feedback and the skip now runs the other way.** Parts, gearing and
-- the governor are the product; force feedback needs a process NCM does not ship. So:
--
--   * the machine walk sweeps `38480-38483` with no skip and no exception;
--   * the FFB walk starts in the Rig Bridge's own range, and only falls back to the legacy companion
--     range once the Carrier has been FOUND -- then skipping the port it is on.
--
-- The fallback is what keeps the external companion usable until `MASTER_TEST §BU` retires it. Deferring
-- it until `peerIsCarrier` removes the start-up race: at t=0 both walks would otherwise begin on 38480.
local RIG_PORT_BASE, CARRIER_PORT_BASE, PORT_SPAN = 38520, 38480, 4
local FFB_SEARCH_SPAN = PORT_SPAN * 2      -- the rig range, then the legacy companion range
local portIndex = 0

-- ---------------------------------------------------------------------------------------------------
-- **THE PORT SCAN'S SAFETY ARGUMENT HAD A HOLE, AND IT COST A WHOLE SESSION.**
-- ---------------------------------------------------------------------------------------------------
--
-- The comment above says a wrong port is "refused, not silently served", because the Carrier rejects any
-- peer that is not its own process. That is true of **one Carrier against another Carrier**. It says
-- nothing about a THIRD program on the same port -- and there is one: `NCM.Wheel.Support.exe`, the
-- retired companion the Carrier replaced, which speaks the same protocol on the same port and has no PID
-- guard at all.
--
-- Observed 2026-09-26: the companion was already running, held 38480 AND the G29 exclusively, and the
-- Carrier fell back to 38481 logging *"port 38480 was taken -- another game instance?"*. This client
-- connected to 38480, logged `carrier connected`, showed a working wheel, and pushed every projection and
-- every handling setup into a program that cannot apply any of them. Force feedback worked perfectly the
-- whole time, which is exactly what made it invisible: the half that proves the link is the half the
-- companion still does.
--
-- **The discriminator is `health.version`.** Only the Carrier sends one. If none arrives shortly after a
-- successful handshake, we are talking to the companion, and saying so by name is worth more than any
-- amount of re-testing the thing on the other end of the wrong socket.
local peerIsCarrier, peerVersion = false, nil

-- ---------------------------------------------------------------------------------------------------
-- TWO PEERS, TWO SURFACES. The rig is proven; the Carrier is not. Neither has to lose.
-- ---------------------------------------------------------------------------------------------------
--
-- `NCM.Wheel.Support.exe` and the Carrier speak the same protocol on the same port range, and the
-- companion is the one that actually drives the owner's rig today. It binds 38480 first, so the Carrier
-- walks up to 38481 -- and a single-surface client connects to whichever answered first, gets a perfectly
-- working wheel, and silently throws every projection into a program with no TweakDB. That is exactly
-- what happened on 2026-09-26 and it cost a session.
--
-- **The single-transport rule in this file's header assumed ONE peer could do both jobs.** It cannot any
-- more, so the rule is narrowed rather than broken: FORCE FEEDBACK keeps its own surface and its own
-- proven peer, and the MACHINE channel -- projections, handling, gear chain, arch dump -- gets a second
-- surface that will only ever talk to something that identifies itself as the Carrier.
--
-- The original rationale for one transport was that an effect must not arrive while the channel that
-- reports feel is down. That still holds WITHIN each channel, and across them it no longer can: the two
-- jobs now live in two processes, so one socket could not have covered both however much we wanted it to.
--
-- **`health.version` is the discriminator.** Only the Carrier sends one. A peer that completes a
-- handshake and never names a version is the companion, and the machine surface moves past it.
-- ---------------------------------------------------------------------------------------------------
-- **THE TWO CHANNELS NEED TWO SWITCHES, AND SHARING ONE COST A WHOLE AFTERNOON.**
-- ---------------------------------------------------------------------------------------------------
--
-- `enabled` is the FORCE FEEDBACK switch. The panel's toggle writes it, and until now the supervisor
-- loop's single `if enabled` gate governed BOTH surfaces -- so turning off a wheel effect also tore down
-- the Machine channel, the Carrier saw the client disconnect, and it restored every flat it had written:
--
--   12:17:49  gear chain v1 on Galena: 14 applied, 14 captured
--   12:18:13  NCM disconnected from the bridge
--   12:18:13  restored 180 flat(s) to their original values
--
-- The driver then did three laps on stock gearing wondering what had broken. Nothing had: a force-feedback
-- preference silently reverted the physics of all 42 cars, because one boolean meant two things.
--
-- **The Machine channel defaults ON and is not a peripheral preference.** Force feedback is optional --
-- it needs a process NCM does not ship. Parts, gearing and the governor are the product.
local machineEnabled = true
local machineSurface, machineReady = nil, false
-- **The machine walk starts at the Carrier's own base and skips nothing** (`KB-177`). It used to start one
-- port up and step over the FFB channel's port, to stop it displacing a wheel companion mid-corner. That
-- protected the optional half of the product at the expense of the whole of it: when the companion was not
-- running the Carrier bound 38480, the walk refused that port by rule, and no projection, no governor and
-- no gear headroom reached any car. The skip now lives on the FFB walk, where losing a port costs feel and
-- not physics. A companion answering here is handled below -- it never names a version, so the grace timer
-- walks past it.
local machineIndex, machineUrl = 0, nil
local machineTicks = 0
local MACHINE_GRACE_TICKS = 150            -- ~5 s at HZ, long enough for a real handshake plus a health

--- Send on the MACHINE channel. Absent is refused rather than silently dropped: a projection that went
--- nowhere must not look like one that was applied.
---
--- **Declared HERE, above every caller, and that is not tidiness.** The first version of this sat beside
--- `bringUpMachine` two hundred lines down, so `pushProjection` -- defined above it -- captured a nil
--- GLOBAL instead of this local and died with "attempt to call a nil value (global 'sendMachine')" the
--- first time a gear command ran. This file's header names that defect class as having bitten the
--- codebase five times and notes that `luac -p` cannot see it. Six.
local function sendMachine(event, payload)
    if not (machineSurface and machineReady and peerIsCarrier) then return false end
    machineSurface:send(event, payload)
    return true
end

--- The FFB channel's search order: `0..3` are the Rig Bridge's range, `4..7` the legacy companion's.
local function ffbPortForIndex(i)
    i = i % FFB_SEARCH_SPAN
    if i < PORT_SPAN then return RIG_PORT_BASE + i end
    return CARRIER_PORT_BASE + (i - PORT_SPAN)
end

local function urlForIndex(i)
    return ("http://127.0.0.1:%d/bridge.html"):format(ffbPortForIndex(i))
end

--- Advance the FFB walk, and never onto the Carrier.
---
--- The legacy half of the range is where the Carrier lives too, and taking its socket would strand the
--- Machine channel on a port that answers and never finishes (see the note beside `RIG_PORT_BASE`). So the
--- second half is entered only once the Carrier has been located, and its port is stepped over.
local function nextFfbUrl()
    for _ = 1, FFB_SEARCH_SPAN do
        portIndex = (portIndex + 1) % FFB_SEARCH_SPAN
        local candidate = urlForIndex(portIndex)
        if portIndex < PORT_SPAN then
            return candidate                       -- the Rig range is ours alone
        elseif machineEnabled and not peerIsCarrier then
            -- The machine walk is still sweeping this range. Stay out of it entirely.
        elseif candidate ~= machineUrl then
            return candidate
        end
    end
    portIndex = 0
    return urlForIndex(0)
end

local function machineUrlForIndex(i)
    return ("http://127.0.0.1:%d/bridge.html"):format(CARRIER_PORT_BASE + (i % PORT_SPAN))
end

local DEFAULT_URL = urlForIndex(0)
local HZ = 30                       -- the rate the platform's own observers run at; the wheel wants smooth
-- **On by default, unlike the companion era.** The carrier ships WITH the world through RequiredMods, so
-- for most players something IS listening, and requiring `/ncm.ffb on` before parts or weather could reach
-- the car would be a trap. A player with no carrier costs a handful of failed connects and a log line.
local enabled, url = true, DEFAULT_URL
local attempts, MAX_ATTEMPTS = 0, FFB_SEARCH_SPAN + 4   -- must outlast a full sweep of both ranges
-- ---------------------------------------------------------------------------------------------------
-- How long to let a page prove itself before moving to the next port (`KB-148`).
-- ---------------------------------------------------------------------------------------------------
--
-- **This was 60 ticks and 60 ticks is TWO SECONDS**, because the supervision loop runs at `HZ` (30) --
-- `Wait(1000 / HZ)` is 33 ms. A CEF surface has to be created, navigate to the carrier's page, boot its
-- JavaScript and complete a WebSocket upgrade before it can emit `ncm:ffb.ready`, and that is nowhere
-- near two seconds. So the scan tore down every attempt just before it could succeed and cycled forever,
-- **including on a single-client machine where the very first port was the right one**. The carrier saw
-- no telemetry at all (`ncm=n/a`) and Parts never arrived.
--
-- Twenty seconds is the backstop, not the mechanism. The mechanism is `ncm:ffb.closed` below: a page that
-- reaches a port with nothing on it -- or one whose carrier REFUSES it because it belongs to another game
-- (`KB-147`) -- closes quickly and says so, and three of those move us on in about six seconds. The
-- backstop only covers a port that accepts and then goes silent, which nothing is known to do.
local unreadyTicks, UNREADY_LIMIT = 0, 600
-- Consecutive socket closes with no successful handshake in between. Three, not one, because the page
-- retries every two seconds on its own and the FIRST attempt can legitimately lose a race with a carrier
-- that is still coming up -- advancing on that would walk away from the correct port.
local unreadyCloses, UNREADY_CLOSE_LIMIT = 0, 3
-- Set by `/ncm.ffb url <url>`. An explicit address is an instruction, not a hint: once given, the scan
-- stops so a deliberate override cannot be walked away from on the next failed connect.
local pinnedUrl = nil
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
        -- **FORCE FEEDBACK ONLY.** This switch does not reach the Machine channel and must never be
        -- allowed to again: it used to, and a driver turning off wheel effects silently reverted the
        -- gearing of every car in the world (see the note beside `machineEnabled`).
        enabled = (type(payload) == "table") and (payload.on and true or false) or false
        log("force feedback %s by the panel -- the machine channel is unaffected",
            enabled and "ON" or "OFF")
        announce()
        return true
    end
    if not (surface and surfaceReady) then return false, "not_connected" end
    -- `bind` assigns a role (steering/throttle/brake/clutch/ffb) to a device the player picked from the
    -- WHEEL panel's dropdowns. It travels the same way settings do and, like them, never reaches the
    -- server: which pedal set is plugged into this PC is nobody else's business.
    if kind == "settings" or kind == "test" or kind == "bind" then
        surface:send("ncm:ffb." .. kind, type(payload) == "table" and payload or {})
        return true
    end
    return false, "unknown_command"
end

--- The last projection set we pushed, by record, so an unchanged world costs nothing. Keyed by the same
--- signature the server publishes with; a record that disappears is sent a restore rather than forgotten.
local projected = {}

--- The last handling setup we pushed, as a signature (`L152`). **Declared here rather than beside its own
--- loop at the foot of the file** because `tearDown` below resets it, and a `local` declared after its
--- reader binds that reader to a global instead -- the reset would then silently do nothing and a driver
--- would lose their parts on any reconnect.
local pushedHandling = nil

--- Push one envelope to the carrier. The plugin applies it and interprets nothing -- which part moved which
--- flat, and why, was decided server-side in `machine.projection`.
local function pushProjection(envelope)
    return sendMachine("ncm:machine.projection", envelope)
end

-- ---------------------------------------------------------------------------------------------------
-- GEAR HEADROOM: lift every governed model's ceiling out of the governor's way (`L162`).
-- ---------------------------------------------------------------------------------------------------
--
-- The server sends ONE multiplier. Which records it applies to is decided here, from the same vendored
-- catalogue the server uses, because 42 record entries would not fit in the state bag that carries this
-- (`KB-136`: 4,032 bytes accepted).
--
-- **Idempotent by record.** The carrier captures each flat's original before its first write and every
-- later write multiplies that captured original, so re-sending is harmless -- but re-sending on every
-- publish would still spend a message per record per tick, so the last applied multiplier is remembered.
local gearHeadroomApplied = {}
-- Declared here, ABOVE the worker thread that reads them. A `local` referenced from a function defined
-- earlier in the file captures a nil global instead -- the defect this file's header names five times.
local headroomWanted = false
local HEADROOM_PER_TICK = 6        -- records per tick, so one pass never approaches a callback's budget
local headroomAttempts = 0
local HEADROOM_MAX_ATTEMPTS = 12   -- ~5 s of retries; past that it is not a transient and saying so is
                                   -- more use than retrying forever

--- **A refusal here is almost always TRANSIENT, and treating it as final was the defect.**
---
--- The script budget is shared with everything else running that tick, so the same call fits one moment
--- and is refused the next. The first version logged and gave up, so a car silently went back to its
--- stock ceiling for the rest of the session -- which read exactly like a regression somebody had
--- introduced, because there was no way to tell a one-tick refusal from a broken build.
---
--- Logged once per attempt, capped, and the final line says it stopped rather than trailing off.
local function retryHeadroom(why)
    headroomAttempts = headroomAttempts + 1
    if headroomAttempts >= HEADROOM_MAX_ATTEMPTS then
        log("gear headroom GIVING UP after %d attempts: %s -- this Machine keeps the gearbox the game "
            .. "shipped", headroomAttempts, tostring(why))
        return
    end
    log("gear headroom deferred (attempt %d/%d): %s", headroomAttempts, HEADROOM_MAX_ATTEMPTS,
        tostring(why))
    headroomWanted = true              -- try again next tick, with a fresh budget
end

--- **Asking is not doing.** This only raises a flag; the worker below does the work, on its own thread.
---
--- `Open77` gives every callback a SCRIPT EXECUTION BUDGET, and the bind callback had already spent most
--- of its own by the time it got here. Building `data.vehicle_catalogue` -- which pulls in the vehicle
--- pool -- then blew it, and the whole headroom was refused with
--- `vehicle_catalogue.lua:110: Open77 script execution budget exceeded`.
---
--- A `Wait()` yields and the next tick starts with a fresh budget, so the only way to do 42 records'
--- worth of work is to spread it across ticks. That cannot happen inside a callback, which has to run to
--- completion. Hence a flag here and a thread below.
local function requestGearHeadroom()
    headroomWanted = true
end

--- The worker. Resolves core lazily, one module per tick, then pushes in small batches.
---
--- **Idempotent by record.** The carrier captures each flat's original before its first write and later
--- writes multiply that captured original, so a re-send is harmless -- but the applied map still stops
--- this from spending 42 messages on every bind.
CreateThread(function()
    while true do
        Wait(400)
        if headroomWanted and machineSurface and machineReady and peerIsCarrier then
            headroomWanted = false

            -- **Warm the dependency tree ONE MODULE PER TICK.**
            --
            -- `parts.handling` requires `parts.ontology`, `machine.expression` and `parts.thermal`, and
            -- `parts.thermal` runs 24-iteration self-check loops at module load. Asking for `handling`
            -- cold therefore builds all four inside ONE callback, against Open77's per-callback script
            -- budget -- which it fitted inside once and then did not, giving a car the stock ceiling back
            -- with nothing on screen to say why. `Wait(0)` yields and the next tick starts fresh, so each
            -- module gets a budget of its own and the last call finds everything already built.
            for _, dependency in ipairs({ "parts.ontology", "machine.expression", "parts.thermal" }) do
                pcall(function() return NcmCore.get(dependency) end)
                Wait(0)
            end

            -- Each `pcall` is its own refusal with its own log line, because "the constant is missing"
            -- and "the catalogue is missing" are different repairs.
            local okParts, Parts = pcall(function() return NcmCore.get("parts.handling") end)
            if not okParts then
                retryHeadroom("parts.handling would not load -- " .. tostring(Parts))
                goto continue
            end
            local factor = tonumber(Parts and Parts.GEAR_HEADROOM)
            if not factor or factor <= 0 then
                retryHeadroom("no multiplier (" .. tostring(Parts and Parts.GEAR_HEADROOM) .. ")")
                goto continue
            end

            Wait(0)   -- fresh budget before the expensive one
            local okCat, Catalogue = pcall(function() return NcmCore.get("data.vehicle_catalogue") end)
            if not okCat or not Catalogue then
                retryHeadroom("data.vehicle_catalogue unavailable -- "
                    .. (okCat and "nil" or tostring(Catalogue)))
                goto continue
            end

            Wait(0)
            local okList, records = pcall(Catalogue.allRecords)
            if not okList or type(records) ~= "table" then
                retryHeadroom("allRecords failed -- " .. tostring(records))
                goto continue
            end

            local pushed, skipped, since = 0, 0, 0
            for _, record in ipairs(records) do
                -- **Only records with an authored top speed.** A car nobody has written a figure for
                -- keeps the gearbox the game shipped: lifting its ceiling with nothing governing it
                -- would simply make it faster than stock (`L157`).
                local okSpeed, authored = pcall(Catalogue.topSpeedKph, record)
                if okSpeed and authored and gearHeadroomApplied[record] ~= factor then
                    -- **The WHOLE chain, both ends, not just the top gear's ceiling.**
                    --
                    -- Lifting only gear 7 left the Galena with six gears spanning 20-25 km/h each and a
                    -- seventh spanning 95-157: the car reached top gear at the same place it always had
                    -- and then sat in one enormous ratio for the entire rest of its range. That is what
                    -- `/ncm.gearcap` is FOR as a deliberate experiment, and it is the wrong shape for a
                    -- permanent headroom -- it does not raise the gearbox, it just stretches its last
                    -- ratio until the box is lopsided.
                    --
                    -- `gear = 0` is every gear (`tweak.cpp`), and scaling `minSpeed` with `maxSpeed`
                    -- keeps each ratio's proportional span, so the box changes SIZE without changing
                    -- SHAPE. That is a longer final drive: the same progression, further up the range.
                    --
                    -- Two changes, one contributor id. The carrier's ledger keys by gear and suffix, so
                    -- each flat's original is captured once and every later write multiplies that
                    -- original -- re-sending stays harmless.
                    local ok = pushProjection({ v = 1, record = { path = record, flats = {}, gears = {
                        { id = "gear_headroom", gear = 0, suffix = ".maxSpeed", multiplier = factor },
                        { id = "gear_headroom", gear = 0, suffix = ".minSpeed", multiplier = factor },
                    } } })
                    if not ok then
                        log("gear headroom INTERRUPTED after %d record(s) -- the machine channel "
                            .. "stopped accepting; the rest stay gear-limited until the next bind", pushed)
                        headroomWanted = true      -- unfinished work is not finished work
                        break
                    end
                    gearHeadroomApplied[record] = factor
                    pushed, since = pushed + 1, since + 1
                    if since >= HEADROOM_PER_TICK then since = 0; Wait(0) end
                elseif okSpeed and not authored then
                    skipped = skipped + 1
                end
            end
            headroomAttempts = 0        -- got all the way through; a later re-bind starts fresh
            if pushed > 0 then
                log("gear headroom x%.2f pushed for %d record(s), %d left stock -- each governed model "
                    .. "becomes drag-limited rather than gear-limited. **Spawn-cached: call a FRESH car "
                    .. "for it to take effect.**", factor, pushed, skipped)
            else
                log("gear headroom x%.2f: nothing to push (%d record(s) already at this factor)",
                    factor, skipped)
            end
        end
        ::continue::
    end
end)

--- IDEA-507: ask the carrier to read the game's own drive-model data for every record NCM knows about and
--- write it to a file beside its log. **Read-only** -- nothing is applied, nothing is mutated, and `L148` is
--- not engaged. It exists because `parts.architecture` knows 124 of 378 (vehicle, facet) pairs and the rest
--- live in `vehDriveModelData`, which only a running game can read.
---
--- Deliberately manual rather than automatic. It is a one-off measurement, not a feature, and a dump that
--- fired on every join would rewrite the file while somebody was reading it.
local function requestArchDump()
    if not (machineSurface and machineReady and peerIsCarrier) then return false, "no_carrier" end

    local catalogue = NcmCore and NcmCore.get and NcmCore.get("data.vehicle_catalogue") or nil
    if not catalogue then return false, "no_catalogue" end

    -- Every runtime record, not just one per machine: the `_player` variants and the RB15 liveries are
    -- separate TweakDB records and may carry different drive models. Asking about all of them costs one
    -- message and settles whether they differ.
    local seen, records = {}, {}
    for _, entry in ipairs(catalogue.entries()) do
        for _, record in ipairs(entry.runtimeRecords or {}) do
            if not seen[record] then
                seen[record] = true
                records[#records + 1] = record
            end
        end
    end
    table.sort(records)

    if not sendMachine("ncm:machine.archdump", { records = records }) then
        return false, "no_carrier"
    end
    log("architecture dump requested for %d record(s)", #records)
    return true
end

RegisterCommand("ncm.archdump", function()
    local ok, why = requestArchDump()
    if not ok then log("architecture dump not sent: %s", tostring(why)) end
end, false)

local function tearDown(why)
    if surface then
        pcall(function() surface:destroy() end)
        log("bridge closed (%s) after %d frame(s), %d skipped", tostring(why), sent, skipped)
    end
    surface, surfaceReady, device, carrier = nil, false, nil, nil
    -- Forget what we pushed. The carrier restores its own originals when the socket drops, so re-sending on
    -- reconnect is correct and re-sending nothing would leave a fresh carrier with no projection at all.
    projected = {}
    -- Same reasoning for the handling setup, and it matters MORE here: the carrier calls `clearHandling()`
    -- on disconnect, so after a reconnect it is genuinely inert and would stay that way until something
    -- moved. A driver must not silently lose their parts because the socket blinked.
    pushedHandling = nil
    announce()
end

local function tearDownMachine(why)
    if machineSurface then
        pcall(function() machineSurface:destroy() end)
        log("machine channel closed (%s) at %s", tostring(why), tostring(machineUrl))
    end
    machineSurface, machineReady = nil, false
    peerIsCarrier, peerVersion = false, nil
    machineTicks = 0
    -- The carrier restores every flat it captured when its socket drops, so the gearboxes are back to
    -- stock and the memo of what we pushed is now a lie. Forgetting is what makes the next publish redo it.
    gearHeadroomApplied = {}
    -- The Carrier restores its own originals when its socket drops, so everything we pushed has to be
    -- pushed again on reconnect. Forgetting is what makes that happen.
    projected = {}
    pushedHandling = nil
end

--- The next Carrier port. Rig Bridge owns a separate range, so no skip or peer collision is possible.
local function nextMachineUrl()
    return machineUrlForIndex(machineIndex)
end

local function bringUpMachine()
    if machineSurface then return end
    machineUrl = machineUrl or nextMachineUrl()
    local page = WebUI.create({
        entry = machineUrl, layer = "hud", width = 16, height = 16,
        zIndex = 1, transparent = true, visible = false,
    })
    if not page then
        machineIndex = machineIndex + 1
        machineUrl = nextMachineUrl()
        return
    end
    machineSurface = page
    machineTicks = 0
    page:on("ncm:ffb.ready", function()
        machineReady = true
        -- Ready is NOT proof. The companion reaches this point too. `peerIsCarrier` decides, and it is
        -- only ever set by a health payload carrying a version.
        log("machine channel handshook at %s -- waiting for a carrier version", tostring(machineUrl))
    end)
    page:on("ncm:ffb.closed", function()
        machineReady = false
        peerIsCarrier, peerVersion = false, nil
    end)
    page:on("ncm:carrier.health", function(h)
        if type(h) == "table" and h.version and not peerIsCarrier then
            peerIsCarrier, peerVersion = true, tostring(h.version)
            log("MACHINE CHANNEL BOUND to the NCM Carrier %s at %s", peerVersion, tostring(machineUrl))
            -- **Driven by the Carrier binding, NOT by the projection state bag.** That bag has never
            -- reached a client -- every session logs `projections: absent(nil)`, the same way
            -- `ncmCeilings` never arrived -- so anything that waited for it waited forever. The headroom
            -- needs no server input: it is one constant from core, applied to the records this client's
            -- own catalogue says are authored.
            -- **Raise a flag; do not do the work here.** Resolving core inside this callback blew
            -- Open77's per-callback script budget and the whole headroom was refused. The worker
            -- thread spreads it over ticks, each with a fresh budget.
            requestGearHeadroom()
            -- Everything the server already decided has to be re-sent: this socket missed all of it.
            projected = {}
            pushedHandling = nil
        end
    end)
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
        -- `KB-147`: try the next port in the range before counting this as a real failure. Only a full
        -- sweep that found nothing is evidence that no carrier is running; one dead port is not, and
        -- treating it as one is what would leave a second client permanently without a bridge.
        if not pinnedUrl then url = nextFfbUrl() end
        if attempts >= MAX_ATTEMPTS then
            log("no rig found on 127.0.0.1:%d-%d or %d-%d after %d attempt(s) — giving up until "
                .. "/ncm.ffb on", RIG_PORT_BASE, RIG_PORT_BASE + PORT_SPAN - 1,
                CARRIER_PORT_BASE, CARRIER_PORT_BASE + PORT_SPAN - 1, attempts)
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
        -- Name the port. With a range in play this is the difference between "my carrier" and "somebody
        -- else's", and it is the first thing worth knowing when two clients are being debugged at once.
        log("carrier connected on %s: %s", url,
            type(info) == "table" and tostring(info.detail or "ok") or "ok")
    end)
    page:on("ncm:ffb.closed", function(info)
        -- **A close BEFORE any successful handshake is the fast "wrong port" signal** (`KB-148`). A close
        -- after one is an ordinary disconnect and must not move us: the carrier we already proved is still
        -- the right one, and walking away from it because the game paused would lose Parts mid-drive.
        local neverConnected = not surfaceReady
        surfaceReady = false
        device = nil
        announce()
        if neverConnected then
            unreadyCloses = unreadyCloses + 1
            log("carrier at %s closed before connecting (%d/%d)", url, unreadyCloses, UNREADY_CLOSE_LIMIT)
        else
            unreadyCloses = 0
            log("carrier dropped: %s", type(info) == "table" and tostring(info.detail or "?") or "?")
        end
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
            -- Force is a continuous fraction of the class ceiling now. **These three were the reason the
            -- FORCE slider snapped back to 0 and force never arrived**: the rebuild dropped them, so the
            -- panel drew `undefined` as zero, sent zero on the next commit, and the wheel stayed dead.
            strength = tonumber(d.strength), magnitude = tonumber(d.magnitude),
            ceiling = tonumber(d.ceiling),
            classes = type(d.classes) == "table" and d.classes or nil,
            steerDegrees = tonumber(d.steerDegrees), wheelRange = tonumber(d.wheelRange),
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
        -- **This is the FFB peer's health and it may NOT set `peerIsCarrier`.** That flag belongs to the
        -- machine channel alone; letting this socket set it would bind the gear chain to whatever is
        -- driving the wheel, which is the exact confusion the two-surface split exists to end.
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
    page:on("ncm:rig.health", function(h)
        if type(h) ~= "table" then return end
        log("Rig Bridge %s | provider=%s | hook=%s | devices=%d", tostring(h.version or "?"),
            tostring(h.provider or "?"), tostring(h.hook and true or false),
            type(h.devices) == "table" and #h.devices or 0)
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
        if enabled or machineEnabled then
            -- **The FFB surface is supervised only while FFB is on.** Everything in this branch that
            -- touches `surface` is now behind its own flag, so the Machine channel below survives a
            -- driver switching force feedback off.
            if enabled and not surface then bringUp() end
            -- **A page that loads but never says `ready` is its own failure**, distinct from a port with
            -- nothing on it, and the old loop had no answer for it: `surface` was non-nil, so `bringUp`
            -- was never called again and the client waited forever. That is exactly what a carrier
            -- REFUSING us looks like from here (`KB-147`) -- the HTTP GET for the page succeeds, the
            -- WebSocket is then closed because we are the wrong process -- so this path is now the
            -- common one on a second client, not a corner case.
            if not enabled and surface then tearDown("force feedback switched off") end
            if enabled and surface and not surfaceReady then
                unreadyTicks = unreadyTicks + 1
                -- Either signal moves us on: repeated closes (fast, the usual case) or a long silence
                -- (the backstop). `KB-148` -- the backstop alone, set too short, broke the ordinary
                -- single-client case by never letting the first page finish its handshake.
                if unreadyCloses >= UNREADY_CLOSE_LIMIT or unreadyTicks >= UNREADY_LIMIT then
                    local why = unreadyCloses >= UNREADY_CLOSE_LIMIT
                        and "refused or nothing listening" or "served a page but never connected"
                    unreadyTicks, unreadyCloses = 0, 0
                    log("%s: %s -- trying the next port", url, why)
                    tearDown("no handshake")
                    if not pinnedUrl then url = nextFfbUrl() end
                end
            else
                unreadyTicks, unreadyCloses = 0, 0
            end
            -- ---- the MACHINE channel, supervised beside the FFB one but on its own port walk
            --
            -- The companion answers and never names a version, so "handshook but not a Carrier" is the
            -- EXPECTED state on 38480, not a fault. Walking past it is the whole mechanism.
            if not machineEnabled and machineSurface then
                tearDownMachine("machine channel switched off")
            elseif machineEnabled and not machineSurface then
                bringUpMachine()
            elseif not peerIsCarrier then
                machineTicks = machineTicks + 1
                if machineTicks >= MACHINE_GRACE_TICKS then
                    local why = machineReady and "handshook but never sent a carrier version (the wheel "
                        .. "companion does this)" or "no handshake"
                    log("%s: %s -- trying the next port for the Carrier", tostring(machineUrl), why)
                    tearDownMachine(why)
                    machineIndex = machineIndex + 1
                    machineUrl = nextMachineUrl()
                end
            else
                machineTicks = 0
            end

            -- **Built once, sent to whichever peers are up.** It used to be built only when the FFB
            -- surface was ready, so switching force feedback off also stopped the Carrier's brake-pedal
            -- and speed feed -- the very thing that separates drag from braking.
            if (surface and surfaceReady) or (machineSurface and machineReady and peerIsCarrier) then
                local snap = ownSnapshot()
                local frame = snap and Feedback.frame(snap, { at = Open77.time.monotonic() }) or nil
                if frame then
                    if surface and surfaceReady then surface:send("ncm:ffb.frame", frame) end
                    -- **The Carrier needs this frame too, and for a different reason.** The FFB peer wants
                    -- it to drive a wheel; the Carrier wants the brake PEDAL, which is the only thing that
                    -- separates aerodynamic drag from braking at its force write site (`IDEA-538`), and
                    -- the speed, which is the yardstick its probe checks itself against.
                    --
                    -- Splitting FFB onto its own surface silently cut this feed and the Carrier logged
                    -- `ncm=n/a` on every sample for the rest of the session. Same frame, both peers.
                    sendMachine("ncm:ffb.frame", frame)
                    sent = sent + 1
                else
                    -- Out of the car, or the snapshot was unreadable. Say so explicitly rather than going
                    -- quiet: silence and "no force" are different instructions, and a companion holding the
                    -- last frame would keep pushing at a wheel whose car we can no longer see.
                    skipped = skipped + 1
                    if surface and surfaceReady then
                        surface:send("ncm:ffb.idle", { v = Feedback.FRAME_VERSION })
                    end
                    -- Idle must reach the Carrier as well, or a player who steps out of a car leaves it
                    -- holding a stale pedal -- and a stale pedal reading "not braking" is exactly what
                    -- would let real braking be scaled as drag.
                    sendMachine("ncm:ffb.idle", { v = Feedback.FRAME_VERSION })
                end
            end
            Wait(math.floor(1000 / HZ))
        else
            if surface then tearDown("disabled") end
            if machineSurface then tearDownMachine("disabled") end
            Wait(1000)
        end
        -- Both switches off is the only path that reaches the branch above, and it is deliberately hard
        -- to arrive at: it needs force feedback off AND the machine channel explicitly off.
    end
end)

-- KB-136 observability: the last thing the projection loop saw, so a change is logged once rather than
-- every 500 ms.
local lastProjectionState = nil

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
            -- KB-136: prefer the array shape, fall back to the map. Rebuilt into a record-keyed table so the
            -- loop below is unchanged -- the transport shape is a transport concern and should not leak into
            -- the logic that decides what to push.
            -- KB-136: the wire form is now the carrier's own shape -- path, flats, restore -- with the
            -- server-side `trace` and `ceiling` left behind, because shipping the audit trail to every
            -- client is what pushed the payload over the state bag's size limit. Normalised here into the
            -- record-keyed table the loop below already expected.
            local records = nil
            if ok and type(state) == "table" then
                if type(state.entries) == "table" then
                    records = {}
                    for _, entry in ipairs(state.entries) do
                        if type(entry) == "table" and type(entry.path) == "string" then
                            records[entry.path] = {
                                v = state.version or 1,
                                at = entry.at,
                                record = {
                                    path = entry.path,
                                    flats = entry.flats or {},
                                    gears = entry.gears or {},
                                    restore = entry.restore or false,
                                },
                            }
                        end
                    end
                elseif type(state.records) == "table" then
                    records = state.records
                end
            end
            -- Belt and braces: if the projection bag ever starts arriving, let it ask too. It never has,
            -- which is why the carrier binding is the real trigger. **It only ASKS** -- the multiplier
            -- comes from core either way, so the bag cannot become a second opinion on the number, and
            -- doing the work here would blow this loop's script budget exactly as it blew the callback's.
            if ok and type(state) == "table" and state.gearHeadroom then
                requestGearHeadroom()
            end

            -- Say what we saw, once per change. The loop used to be silent on every path, which is why
            -- KB-136 went weeks with no evidence beyond "nothing happened".
            do
                local seen
                if not ok then seen = "PCALL_FAILED"
                elseif type(state) ~= "table" then seen = "absent(" .. type(state) .. ")"
                elseif records == nil then seen = "no entries and no records field"
                else
                    local n = 0
                    for _ in pairs(records) do n = n + 1 end
                    seen = ("%d record(s) via %s"):format(n, type(state.entries) == "table" and "entries" or "records")
                end
                if seen ~= lastProjectionState then
                    lastProjectionState = seen
                    log("projections: %s", seen)
                end
            end
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
                        if pushProjection({ v = 1, record = { path = record, flats = {}, gears = {}, restore = true } }) then
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
        pinnedUrl = url
        tearDown("url changed")
        log("carrier url pinned to %s (port scan disabled; /ncm.ffb url auto to resume scanning)", url)
    elseif a == "url" and not args[2] then
        log("carrier url is %s (%s)", url, pinnedUrl and "pinned" or "scanning")
    elseif a == "auto" then
        pinnedUrl, portIndex = nil, 0
        url = urlForIndex(0)
        tearDown("scan resumed")
        log("carrier url scanning resumed from %s", url)
    end
    log("ffb %s | url=%s | surface=%s ready=%s | sent=%d idle=%d",
        enabled and "on" or "off", url, tostring(surface ~= nil), tostring(surfaceReady), sent, skipped)
end, false)


-- ---------------------------------------------------------------------------------------------------
-- `L152`: the driver's fitted parts, pushed down the same socket (the INSTANCE channel)
-- ---------------------------------------------------------------------------------------------------
--
-- The projection loop above carries the RECORD channel: TweakDB flats, per-record, spawn-cached, shared by
-- every instance of that model on this client. This one carries the other half -- three force scales that
-- land on ONE BODY, the car the local player is in, live and with no respawn.
--
-- **That is what makes Parts personal.** Two drivers in the same model with different engines feel
-- different, because each client scales the forces of the car it is simulating and nothing is shared.
--
-- `KB-41` is why this reads its own bag rather than trusting a watcher's value: player bags are visible to
-- every client and the selector fires for whoever changed. Polling our own is correct whatever shape the
-- notification takes, which is the lesson `panel.lua` already paid for.
local lastHandlingState = nil

--- Candidate field names for the REDengine `ent::EntityID` on a streamed vehicle snapshot.
---
--- **The name is not established anywhere in this repository and that is why this is a list.** The
--- character snapshot logged from a running client carries `engineId`; the vehicle snapshot has never been
--- dumped. `arch_dump.cpp` set the precedent for this situation -- *an unresolved name is a result, and a
--- resolved one is a discovery* -- so every candidate is tried in order, the winner is logged ONCE, and
--- nothing is guessed. The Carrier accepts both spellings for the same reason.
local ENTITY_FIELDS = { "engineEntity", "entityId", "entityID", "engineId", "entId", "handle" }
local resolvedEntityField = nil

--- Read the engine entity out of a vehicle snapshot, as a DECIMAL STRING.
---
--- **A string, deliberately.** This value is a 64-bit id and it crosses a WebUI page that parses and
--- re-serialises JSON in JavaScript, where every number is a double: anything above 2^53 would come out
--- silently rounded, and a rounded identity matches nothing. The Carrier parses the string back with
--- `std::from_chars`.
local function entityOf(snapshot)
    if type(snapshot) ~= "table" then return nil end
    for _, field in ipairs(ENTITY_FIELDS) do
        local value = snapshot[field]
        local text
        if type(value) == "string" and value:match("^%d+$") and value ~= "0" then
            text = value
        elseif type(value) == "number" and value > 0 then
            text = ("%.0f"):format(value)
        end
        if text then
            if resolvedEntityField ~= field then
                resolvedEntityField = field
                log("handling: vehicle entity id resolves from '%s' (this is the discovery KB-146 needed)",
                    field)
            end
            return text
        end
    end
    return nil
end

--- Turn the server's published setup into the exact message the Carrier will accept, or into an explicit
--- unbind. Returns `payload, reason`.
---
--- **Three independent links must all hold**, and the whole point of `KB-146` is that none of them is
--- inferred from speed, mass or proximity:
---
---   1. the server names an `assetId` and the live `vehicleId` it has authority over;
---   2. this client verifies it is really in that exact vehicle -- `KB-41`'s rule, applied to vehicles:
---      never trust a value about yourself that you did not read yourself;
---   3. the local snapshot yields the engine entity the native probe can compare against a body.
---
--- Any link missing produces an unbind, never a fallback. An unbind is a real message: going silent would
--- leave the Carrier holding the last setup until its lease expired.
local WetHandling = NcmCore.get("parts.handling")   -- `L208`: wetPowerGrip
local wetFast = false

local function resolveHandling(bagOk, setup)
    local function unbound(reason)
        return { v = 2, bound = false }, reason
    end

    if not bagOk then return unbound("PCALL_FAILED") end
    if type(setup) ~= "table" then return unbound("no ncmHandling key") end
    if setup.v ~= 2 then return unbound(("wire v%s, expected v2"):format(tostring(setup.v))) end
    if not setup.bound then return unbound("server says unbound") end
    if type(setup.levers) ~= "table" then return unbound("bound but no levers") end
    if type(setup.assetId) ~= "string" or setup.assetId == "" then
        return unbound("bound but no assetId")
    end
    if setup.vehicleId == nil then return unbound("bound but no vehicleId") end

    -- Link 2. The seat is a claim; the vehicle is the proof. `seated()` above already learned that
    -- `getPlayerSeat` is sticky, so the vehicle the server named is read directly and compared.
    local okSeat, seat = pcall(Open77.vehicles.getPlayerSeat)
    if not okSeat or type(seat) ~= "table" then return unbound("no seat") end
    local mine = seat.vehicleId or seat.vehicle or seat.id
    if mine == nil then return unbound("seat names no vehicle") end
    if tostring(mine) ~= tostring(setup.vehicleId) then
        -- Not an error: the server's view and ours disagree for a moment after a seat change or a call.
        -- It IS a refusal to write, because this is precisely the case where the old code would have
        -- tuned whatever car happened to be fastest.
        return unbound(("seat=%s but server says %s"):format(tostring(mine), tostring(setup.vehicleId)))
    end

    local okVehicle, snapshot = pcall(Open77.vehicles.get, mine)
    if not okVehicle or type(snapshot) ~= "table" then return unbound("vehicle not streamed to us") end

    -- Link 3.
    local entity = entityOf(snapshot)
    if not entity then
        return unbound("no engine entity on the vehicle snapshot (tried: "
            .. table.concat(ENTITY_FIELDS, ", ") .. ")")
    end

    -- `L208` "push on entry, loose on power": on a wet road, heavy throttle lifts grip above the wet value
    -- (past 1.0 at full wet), which on this engine steps the rear out (`E26`). Live throttle exists only
    -- here, at the lease rate; the server says how wet the road is. Quantised so the lease is not rewritten
    -- by pedal noise.
    local levers = setup.levers
    local wet = tonumber(setup.wetPower)
    if wet and wet > 0 and type(levers.gripScale) == "number" then
        local okL, lift = pcall(WetHandling.wetPowerGrip, wet, tonumber(snapshot.throttle))
        if okL and type(lift) == "number" and lift > 1.0 then
            lift = math.floor(lift / 0.02 + 0.5) * 0.02
            local copy = {}
            for k, v in pairs(levers) do copy[k] = v end
            copy.gripScale = math.min(1.5, levers.gripScale * lift)
            levers = copy
        end
    end

    return {
        v = 2,
        bound = true,
        assetId = setup.assetId,
        vehicleId = tostring(setup.vehicleId),
        authorityEpoch = tostring(setup.authorityEpoch or ""),
        engineEntity = entity,
        levers = levers,
    -- **The tail, not the head.** Truncating to the first 8 characters made both seeded fixtures read as
    -- `10000000`, so the one log a player is most likely to look at could not tell two Machines apart --
    -- during the very test whose whole point is that two Machines differ.
    }, ("BOUND asset=..%s vehicle=%s entity=%s grip=%.3f drive=%.3f brake=%.3f topSpeed=%s"):format(
        setup.assetId:sub(-6), tostring(setup.vehicleId), entity,
        tonumber(setup.levers.gripScale) or 1,
        tonumber(setup.levers.driveScale) or 1,
        tonumber(setup.levers.brakeScale) or 1,
        -- **Named even when absent.** The governor produced no carrier line at all and there was no way
        -- to tell "the server never sent a target" from "the carrier ignored one", which are different
        -- bugs in different processes.
        setup.levers.topSpeedKph and (tostring(setup.levers.topSpeedKph) .. "kph") or "ABSENT")
end

CreateThread(function()
    Wait(9500)
    while true do
        if enabled and surface and surfaceReady then
            local ok, bag = pcall(Open77.state.localPlayer)
            local setup = nil
            if ok and type(bag) == "table" and type(bag.ncmHandling) == "table" then
                setup = bag.ncmHandling
            end

            local payload, seen = resolveHandling(ok, setup)

            -- Say what we saw, once per change. The projection loop went weeks with no evidence beyond
            -- "nothing happened" (`KB-136`) precisely because it was silent on every path. With a binding
            -- in the way there are more ways to end up inert, so the reason is part of the line.
            if seen ~= lastHandlingState then
                lastHandlingState = seen
                log("handling: %s", seen)
            end

            -- **This is a LEASE, not an edit.** The Carrier disarms itself 2 s after the last accepted
            -- message (`kBindingLeaseMs`), so an unchanged binding must still be re-sent twice a second.
            -- Suppressing an identical payload the way the projection loop does would silently expire the
            -- binding and leave the driver's Parts inert with nothing in any log to explain it.
            sendMachine("ncm:machine.handling", payload)
            pushedHandling = seen
            -- `L208`: on a wet road the lift follows the throttle, so re-send faster than the lease needs.
            wetFast = type(setup) == "table" and (tonumber(setup.wetPower) or 0) > 0
        else
            wetFast = false
        end
        Wait(wetFast and 100 or 500)
    end
end)

--- `/ncm.setup` -- fit a synthetic part and feel it, before the parts economy exists.
---
--- The server holds the truth and does the composing; this only relays. See `server/handling.lua` for what
--- it accepts. Deliberately a test instrument, and it drives the real mechanism rather than a shortcut
--- around it -- `NcmHandling.setParts` is the same call the inventory will make.
RegisterCommand("ncm.setup", function(_, args)
    TriggerServerEvent("ncm:setup", args and args[1] or nil, args and args[2] or nil)
end, false)

--- `/ncm.topspeed <kph>` -- the capability spike for per-instance top speed.
---
--- Nothing in NCM has ever capped a top speed: the per-record path's payload has never reached a client
--- (`server/state_probe.lua`), and the per-instance server call has never been made. This relays to a
--- server that makes it for the first time. See `server/handling.lua` for what it answers.
---
--- Deliberately separate from `/ncm.setup`: this proves a PLATFORM capability, while `ncm.setup` drives
--- NCM's own composition. Folding an unproven call into the command that already works would make one
--- failure look like the other.
--- `/ncm.tyre` -- the readout behind the gauge. The gauge shows a POSITION; this shows the degrees, the
--- ambient it is being pulled toward, and the window. Added after a live drive where the needle sat on the
--- bottom stop and there was no way to tell a broken feed from a cold tyre.
--- `/ncm.govern <kph>` -- set this Machine's top speed, live, per car.
---
--- Not TweakDB and not spawn-cached: the carrier tapers drive as the target is approached, so the change
--- is felt on the straight you are already on.
RegisterCommand("ncm.govern", function(_, args)
    local a = args and args[1]
    if a == nil then
        log("usage: /ncm.govern <kph>   or   /ncm.govern off")
        return
    end
    TriggerServerEvent("ncm:govern", (tostring(a):lower() == "off") and 0 or tonumber(a))
end, false)

RegisterCommand("ncm.tyre", function()
    TriggerServerEvent("ncm:tyre.query")
end, false)

RegisterCommand("ncm.topspeed", function(_, args)
    TriggerServerEvent("ncm:topspeed", args and args[1] or nil)
end, false)

--- `/ncm.ratedtopspeed` -- the one-off dump that fills `data.vehicle_catalogue`'s authored table.
---
--- `Open77.vehicles.ratedTopSpeed(record)` reads the record's own gearing and rated max RPM, so it is an
--- AUTHORED SPECIFICATION rather than a measurement -- which is exactly why its output may be copied into
--- the catalogue. `IDEA-328`/`IDEA-331` forbid the reverse: "highest observed 108 km/h" is evidence and
--- "top speed 108" is a claim, and a number that crossed silently from one to the other would be a
--- specification nobody authored.
---
--- **Client-side because the call is client-side.** It is absent from the server scripting assembly, which
--- is why the catalogue holds copied numbers rather than calling this at runtime. Same pattern as
--- `arch_dump.cpp`: dump for a human to read and author, never for the server to trust live.
---
--- The card also notes it returns the GEARING rating and not terminal velocity, "which torque and
--- aerodynamic drag carry higher" -- so these numbers are a conservative baseline, and a Machine that
--- lifts its governor above them is asking for something its own physics can actually deliver.
RegisterCommand("ncm.ratedtopspeed", function()
    local api = Open77.vehicles
    if not (api and type(api.ratedTopSpeed) == "function") then
        log("ratedTopSpeed: NOT AVAILABLE on this build -- the catalogue table cannot be filled from here")
        return
    end
    local Catalogue = NcmCore.get("data.vehicle_catalogue")
    -- `Catalogue.allRecords()`, NOT `entry.record`. A conceptual machine owns a LIST of runtime records --
    -- the base car, its `_player` variant, and ten liveries for the RB15 -- so there is no single `record`
    -- field on an entry. Reading one returned nil for all 27 and the first dump printed zero rows.
    local records = Catalogue.allRecords()
    local rows, missing = {}, 0
    for _, record in ipairs(records) do
        local ok, kph = pcall(api.ratedTopSpeed, record)
        if ok and type(kph) == "number" then
            rows[#rows + 1] = ("        %s = %d,"):format((record:gsub("[%.%-]", "_")),
                math.floor(kph + 0.5))
        else
            missing = missing + 1
            rows[#rows + 1] = ("        -- %s = ?  (%s)"):format((record:gsub("[%.%-]", "_")),
                ok and "returned nil" or tostring(kph))
        end
    end
    table.sort(rows)
    log("---- paste into data/vehicle_catalogue.lua M.TOP_SPEED_KPH ----")
    for _, row in ipairs(rows) do log("%s", row) end
    log("---- %d record(s), %d unresolved ----", #rows, missing)

    -- ----------------------------------------------------------------- which ARGUMENT does it want?
    --
    -- **The first dump returned nil for all 47 records.** The card's prose says "a vehicle's TweakDB
    -- record" and its example passes a record path, but the PARAMETER IS NAMED `vehicleId` -- so the prose
    -- and the signature disagree, and prose loses. Try the live id of the car the player is sitting in and
    -- say which form answered, because a table that cannot be filled is the thing blocking top speed.
    local own = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
    local id = own and (own.id or own.vehicleId)
    if not id then
        log("ratedTopSpeed: sit in a car and run this again -- the live-id form is untested without one")
        return
    end
    local okLive, live = pcall(api.ratedTopSpeed, id)
    log("ratedTopSpeed(liveId=%s) -> %s%s", tostring(id),
        okLive and tostring(live) or "THREW",
        (okLive and type(live) == "number") and " km/h  <-- THIS is the accepted form" or "")
    -- And the record of the car actually being sat in, so a record that IS resolvable can be told from a
    -- record path being the wrong kind of argument entirely.
    if own and own.record then
        local okRec, byRecord = pcall(api.ratedTopSpeed, own.record)
        log("ratedTopSpeed(record=%s) -> %s", tostring(own.record),
            okRec and tostring(byRecord) or "THREW")
    end
end, false)

-- ---------------------------------------------------------------------------------------------------
-- THE GEAR CHAIN
-- ---------------------------------------------------------------------------------------------------
--
-- **Every gear declares a speed FLOOR, and the engine enforces it with forward force.** A car in a high
-- gear has a high floor, so full brake from speed does not stop the car -- it brings the car down to the
-- gear's `minSpeed` and holds it there. NCM's own Manual Transmission work found this and fixed it by
-- zeroing the floor.
--
-- **Neither existing lever can reach it, and that is why this needed a new channel rather than a tune.**
-- `brakeScale` only ever scales RETARDING force and the floor is a forward PUSH. `driveScale` does scale
-- it, but it bottoms out at 0.30, so it can remove at most 70 percent of the floor -- and it takes the
-- car's entire power delivery down with it. A car that cannot stop and a car with no engine are not a
-- trade worth making.
--
-- Sent straight to the carrier rather than through the fleet publication, on purpose: `NcmMachine` composes
-- projections from `GlobalState.ncmCeilings`, whose only producer was the class disabled by `KB-144`, so
-- the fleet may currently be empty. This proves the MECHANISM against the car you are sitting in, which is
-- the question, and leaves wiring it into the fleet as a separate and later thing.
local function gearFloorCommand(args)
    local own = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
    local record = own and own.record
    if not record then
        log("gearfloor: sit in a car first -- there is no record to write against")
        return
    end

    local restore = (args and args[1] == "off")
    if restore then
        if pushProjection({ v = 1, record = { path = record, flats = {}, gears = {}, restore = true } }) then
            log("gearfloor OFF: asked the carrier to restore %s", tostring(record))
        else
            log("gearfloor: bridge is down, nothing sent")
        end
        return
    end

    local Projection = NcmCore.get("machine.projection")
    local gears = {}
    for _, change in ipairs(Projection.GEAR_FLOOR) do
        gears[#gears + 1] = {
            id = change.id, gear = change.gear,
            suffix = change.suffix, multiplier = change.multiplier,
        }
    end

    if pushProjection({ v = 1, record = { path = record, flats = {}, gears = gears } }) then
        log("gearfloor ON: %d gear change(s) pushed for %s -- the carrier log says how many landed",
            #gears, tostring(record))
        log("gearfloor: now brake hard from speed in a high gear. Before this, the car stops at the "
            .. "gear's minSpeed and crawls; after it, it should come to a stop.")
    else
        log("gearfloor: bridge is down, nothing sent")
    end
end

RegisterCommand("ncm.gearfloor", function(_, args) gearFloorCommand(args) end, false)

--- `/ncm.gears` -- read the gear chain of the car being sat in.
---
--- **Goes through the carrier, because the resource sandbox has no `TweakDB` global.** The first version of
--- this command called `TweakDB:GetFlat` directly and died on `attempt to index a nil value (global
--- 'TweakDB')` -- that is a Cyber Engine Tweaks global and this is not CET. Every TweakDB access NCM makes
--- already goes through the carrier; this one forgot.
---
--- The answer lands in the CARRIER's log, not here, because it is a table and that is where the other
--- TweakDB answers are written.
--- Which program is on the other end of the bridge, and is it the one that can actually do anything?
--- Both channels, named separately, because they are two sockets to two programs and the whole class of
--- bug this command exists for is one of them working while the other quietly does not.
RegisterCommand("ncm.carrier", function()
    if surface and surfaceReady then
        log("FFB channel:     connected at %s (%s)", tostring(url),
            device and tostring(device.name) or "no device reported")
    else
        log("FFB channel:     NOT connected (url %s)", tostring(url))
    end
    if peerIsCarrier then
        log("MACHINE channel: NCM Carrier %s at %s -- parts, weather and the gear chain CAN be applied",
            tostring(peerVersion), tostring(machineUrl))
    elseif machineSurface and machineReady then
        log("MACHINE channel: %s answered but has not named a carrier version -- still walking the port "
            .. "range. If this never settles, no Carrier is running.", tostring(machineUrl))
    else
        log("MACHINE channel: searching %d-%d for a Carrier (currently %s)",
            CARRIER_PORT_BASE, CARRIER_PORT_BASE + PORT_SPAN - 1, tostring(machineUrl))
    end
end, false)

RegisterCommand("ncm.gears", function()
    local own = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
    local record = own and own.record
    if not record then
        log("gears: sit in a car first")
        return
    end
    if not (surface and surfaceReady) then
        log("gears: bridge is down, nothing sent")
        return
    end
    if not sendMachine("ncm:machine.geardump", { records = { record } }) then
        log("gears: the machine channel is not bound to a Carrier -- run /ncm.carrier")
        return
    end
    log("gears: asked the carrier to read %s -- the answer is in the CARRIER log", tostring(record))
end, false)

-- ---------------------------------------------------------------------------------------------------
-- THE CEILING
-- ---------------------------------------------------------------------------------------------------
--
-- **Top speed is the last gear's `maxSpeed`.** Not drag, not power. The engine will not pull a car past
-- the band of the gear it is in, so the top of the last band is the top of the car -- which is exactly why
-- three drag runs at 1.0, 1.217 and 1.575 drive all finished at the SAME speed. There was nothing left to
-- multiply: at the ceiling the drive force is already gone.
--
-- Two different operations, because they are two different cars:
--
--   `/ncm.gearcap 1.2`    stretch ONLY the last gear. Same acceleration through the box, then a longer
--                         run at the top. The cheapest possible top-speed change.
--   `/ncm.gearing 1.2`    stretch the WHOLE chain, every gear's floor and ceiling together. That is a
--                         longer final drive: higher top speed AND lazier acceleration, the real trade.
--
-- Multipliers against whatever this install's original was, never absolutes -- the same rule every other
-- flat obeys, because the server does not know what the factory value is on this machine.
local function pushGearChange(label, changes)
    local own = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
    local record = own and own.record
    if not record then
        log("%s: sit in a car first -- there is no record to write against", label)
        return
    end
    if pushProjection({ v = 1, record = { path = record, flats = {}, gears = changes } }) then
        log("%s: %d gear change(s) pushed for %s -- the CARRIER log says how many landed",
            label, #changes, tostring(record))
    else
        log("%s: bridge is down, nothing sent", label)
    end
end

local function gearMultiplierArg(args, label)
    local mult = tonumber(args and args[1])
    if args and args[1] == "off" then return nil, true end
    if not mult or mult <= 0 then
        log("usage: /%s <multiplier>   e.g. 1.25 for 25%% more, or 'off' to restore", label)
        return nil, false
    end
    -- Bounded for the same reason every lever is: a typo that multiplied a gear by 100 would be a car
    -- that never reaches its own first upshift.
    if mult < 0.25 then mult = 0.25 elseif mult > 4.0 then mult = 4.0 end
    return mult, false
end

--- Stretch the LAST gear only. The narrowest possible top-speed change.
RegisterCommand("ncm.gearcap", function(_, args)
    local mult, off = gearMultiplierArg(args, "ncm.gearcap")
    if off then
        local own = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
        local record = own and own.record
        if record and pushProjection({ v = 1, record = { path = record, flats = {}, gears = {}, restore = true } }) then
            log("gearcap off: asked the carrier to restore %s", tostring(record))
        end
        return
    end
    if not mult then return end
    pushGearChange("gearcap", {
        { id = "ceiling_top_gear", gear = -1, suffix = ".maxSpeed", multiplier = mult },
    })
    log("gearcap: top gear maxSpeed x%.2f. Run /ncm.gears first and after to see the number move, "
        .. "then drive a long straight.", mult)
end, false)

--- Stretch the WHOLE chain -- a longer or shorter final drive.
RegisterCommand("ncm.gearing", function(_, args)
    local mult, off = gearMultiplierArg(args, "ncm.gearing")
    if off then
        local own = NcmClientOwnVehicle and NcmClientOwnVehicle() or nil
        local record = own and own.record
        if record and pushProjection({ v = 1, record = { path = record, flats = {}, gears = {}, restore = true } }) then
            log("gearing off: asked the carrier to restore %s", tostring(record))
        end
        return
    end
    if not mult then return end
    -- Both ends of every band, or the bands stop meeting and a gear has a hole in front of it.
    pushGearChange("gearing", {
        { id = "gearing_max", gear = 0, suffix = ".maxSpeed", multiplier = mult },
        { id = "gearing_min", gear = 0, suffix = ".minSpeed", multiplier = mult },
    })
    log("gearing: every gear x%.2f -- higher top speed AND lazier acceleration, which is the trade a "
        .. "longer final drive actually makes.", mult)
end, false)

--- The server answers in chat as well (`Open77.chat.send`); this puts the same line in the client log,
--- beside the bridge's own `handling:` lines, so one log shows what was asked for AND what was pushed.
RegisterNetEvent("ncm:setup.result", function(message)
    log("setup: %s", tostring(message))
end)
