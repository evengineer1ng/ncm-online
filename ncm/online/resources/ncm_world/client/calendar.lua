-- ncm_world / client / calendar — the heartbeat and the venue prompt (M3.1; L34, L35, P19).
--
-- Reads GlobalState.ncmCalendar (server-published), shows a persistent "NEXT RACE" hint with a
-- countdown and the distance to the start, places a world marker with the prompt
-- "Pay entry fee and enter?" at the venue, and asks the server to enter on confirmation.
-- The client never decides anything sporting: the server re-validates window and position.
local Core = NcmCore
local Entry = Core.get("competition.entry")
local Routes = Core.get("course.routes")

local function log(fmt, ...)
    print(("[ncm_world/client/calendar] " .. fmt):format(...))
end

local function call(resource, name, ...)
    local promise, reason = Open77.exports.call(resource, name, ...)
    if not promise then return nil, reason end
    return promise:await()
end

local cal = nil                 -- last GlobalState.ncmCalendar
local base = { offset = nil }    -- KB-25: serverNow - monotonic, kept at its RUNNING MAXIMUM (see seedClock)
-- One ring per race inside its window, each at its own venue (owner, 2026-09-28). eventId -> { handle, venue }.
-- It used to be ONE ring for the whole world, given to "your" soonest race or else the soonest public one, so a
-- second race starting inside the same twenty minutes had no ring at its venue at all.
local rings = {}
local ringFailedAt = {}         -- eventId -> monotonic time of a refused create (retried every 10 s, not every tick)
local standingIn = nil          -- eventId of the ring the driver is inside, as last told to the server
local standingToldAt = 0
local lastHint = { text = nil, title = nil }
local gps = { eventId = nil, blipId = nil }
local autoRouted = {}            -- eventId -> true once we set the venue route for it
local VENUE_RING_LEAD_S = Entry.RING_LEAD_S
local routeTo                    -- defined below (used by the heartbeat and /ncm.gps)
-- The drawn ring IS the entry rule: the server accepts inside this radius (plus a staleness tolerance) and nowhere
-- else (owner, 2026-09-28). It is visible from far enough away to spot and head for -- it was 15 m, which meant a
-- ring could only be found by already standing next to it.
local VENUE_RADIUS_M = Entry.RING_RADIUS_M
local VENUE_SHOW_M = Entry.RING_VISIBLE_M
local PAD_KEY = "padX"            -- vanilla "interact" on a pad; same tap/hold job as E
local holdFraction = 0            -- 0..1 while the engage key is held, for the list's progress bar

-- KB-25: every published `serverNow` is already stale when it lands (publish cadence + latency), and staleness
-- is a one-directional BIAS: a snapshot can only make the server look older than it is, never newer. Re-seeding
-- the clock from each snapshot therefore walks the countdown forward and snaps it back. `serverNow - monotonic`
-- is understated by exactly the staleness, so the least-stale sample is the MAXIMUM offset: keeping the running
-- maximum converges on the truth and can never step the displayed clock backwards. A large drop means the server
-- restarted, which is the one case where following it down is right.
local function serverNow()
    if not base.offset then return 0 end
    return Open77.time.monotonic() + base.offset
end

local function seedClock(published)
    local t = tonumber(published) or 0
    if t <= 0 then return end
    local sample = t - Open77.time.monotonic()
    if not base.offset or sample > base.offset then
        base.offset = sample
    elseif sample < base.offset - 30 then
        base.offset = sample
    end
end

local function applyCalendar(g, transport)
    if type(g) ~= "table" or type(g.next) ~= "table" then return false end
    if not cal or g.signature ~= cal.signature then
        log("calendar: %d upcoming via %s (%s)", #g.next, tostring(transport), tostring(g.signature))
    end
    seedClock(g.serverNow)
    cal = g
    return true
end

-- The production platform currently leaves GlobalState.ncmCalendar absent on clients. The server sends the
-- same bounded three-row snapshot explicitly every tick; the GlobalState read in the heartbeat stays as a
-- fallback rather than being trusted as the only transport.
RegisterNetEvent("ncm:calendar", function(g) applyCalendar(g, "event") end)

local function localPosition()
    local ok, x, y, z = pcall(Open77.character.position)
    if ok and type(x) == "number" then return { x = x, y = y, z = z } end
    return nil
end

local function myEntry()
    local ok, bag = pcall(Open77.state.localPlayer)
    if ok and type(bag) == "table" then return bag.ncmEntry end
    return nil
end

local function km(m)
    if m >= 1000 then return string.format("%.1f km", m / 1000) end
    return string.format("%d m", math.floor(m))
end

-- **The heartbeat card must not change every second.** OPEN//77's notification page renders an update as
-- remove + rebuild + slide-in and moves the card to the bottom of the stack, so a per-second countdown (and a
-- live distance while driving) re-animated it every second -- "highly disorienting" (owner, 2026-09-28). The
-- text is coarse on purpose: it changes about once a minute, or once a kilometre. The race HUD owns seconds.
local function coarseCountdown(seconds)
    if seconds < 60 then return "starts in under a minute" end
    return ("starts in %d min"):format(math.ceil(seconds / 60))
end

local function coarseDistance(m, venueName)
    if m <= 50 then return "at " .. venueName end
    if m < 1000 then return "under 1 km to " .. venueName end
    return ("%d km to %s"):format(math.floor(m / 1000 + 0.5), venueName)
end

local function removeRing(eventId)
    local r = rings[eventId]
    if r and r.handle then
        pcall(function() call("open77_worldui", "remove", r.handle) end)
    end
    rings[eventId] = nil
end

local function removeAllRings()
    for eventId in pairs(rings) do removeRing(eventId) end
end

local function createRing(ev)
    -- A refused create is retried every 10 s, not every tick (one log line per attempt).
    if ringFailedAt[ev.eventId] and Open77.time.monotonic() - ringFailedAt[ev.eventId] < 10 then return end
    -- IDEA-095: the marker is a RING ONLY. It carries no label, key, holdSeconds or event, because a labelled
    -- worldui marker always makes the platform facade draw its own E card (KB-3, KB-16) -- and that card can offer
    -- exactly one action, which is the whole reason a single key was doing three jobs (KB-32). NCM draws the option
    -- list itself (web/venue.html) and owns the key.
    local result, err = call("open77_worldui", "create", {
        id = "ncm_venue_" .. tostring(ev.eventId):gsub("[^%w_]", "_"):sub(1, 40),
        position = { x = ev.venue.x, y = ev.venue.y, z = ev.venue.z },
        radius = VENUE_RADIUS_M,
        style = "objective",
        maxDistance = VENUE_SHOW_M,
        promptDistance = VENUE_RADIUS_M,
        groundOffset = 0.25,
        color = "#00E5FF",
    })
    if result and result.ok then
        rings[ev.eventId] = { handle = result.handle, venue = ev.venue }
        ringFailedAt[ev.eventId] = nil
        log("venue ring at %s for %s", tostring(ev.venue.name), ev.eventId)
    else
        ringFailedAt[ev.eventId] = Open77.time.monotonic()
        log("venue ring failed for %s: %s", ev.eventId, tostring(err or (result and result.error)))
    end
end

--- Make the drawn rings exactly `targets` (array of calendar rows).
local function syncRings(targets)
    local want = {}
    for _, ev in ipairs(targets or {}) do
        if ev.eventId and type(ev.venue) == "table" then want[ev.eventId] = ev end
    end
    for eventId in pairs(rings) do if not want[eventId] then removeRing(eventId) end end
    for eventId, ev in pairs(want) do if not rings[eventId] then createRing(ev) end end
end

--- The ring the driver is standing inside, or nil. The nearest wins where two venues overlap.
local function ringHere(pos)
    if not pos then return nil end
    local best, bestD = nil, nil
    for eventId, r in pairs(rings) do
        local d = Routes.planarDistance(pos, r.venue)
        if d <= VENUE_RADIUS_M + 0.5 and (not bestD or d < bestD) then best, bestD = eventId, d end
    end
    return best
end

--- Tell the server which ring we are in: on every change, and again every 10 s while inside one, so a restarted
--- server re-learns it without the driver having to step out and back in.
local function tellStanding(eventId)
    local t = Open77.time.monotonic()
    if eventId == standingIn and (not eventId or t - standingToldAt < 10) then return end
    standingIn, standingToldAt = eventId, t
    pcall(TriggerServerEvent, "ncm:venue.at", eventId)
end

-- ---------------------------------------------------------------------------------------------
-- The venue option list (IDEA-095)
--
-- One marker, a short FLAT list of final acts, and ONE key. Tap E to move the highlight, hold E to engage the
-- highlighted option. A second key was the obvious design and is the wrong one here: every spare key at a venue
-- is already a movement key, and the owner asked for one button and a list, not two buttons. Tapping to cycle
-- costs nothing and keeps `hold E` meaning exactly what it means everywhere else in the game.
--
-- The list itself is decided by the server (competition.venue_options) and arrives on the `ncmVenue` bag. The
-- client never decides what is available -- it draws what it was given and sends back the id it drew, and the
-- server refuses anything no longer on the list.
-- ---------------------------------------------------------------------------------------------
local ENGAGE_KEY = "E"
local HOLD_S = 0.6           -- hold this long to engage; below it, a release is a tap
local vpage, vpageReady = nil, false

-- ---------------------------------------------------------------------------------------------
-- `NcmVenueSurface` — this page, lent out (`L193`, 2026-09-28)
-- ---------------------------------------------------------------------------------------------
--
-- `kMaximumWebSurfaces` is **8 per resource** and `ncm_world` had reached 8 of 8 (`IDEA-570`), with three of
-- them invisible transport pages that come and go — so `WebUI.create` for a ninth was refused depending on
-- timing. The Street Call form therefore draws on THIS page instead of owning one, and the owner chose that
-- explicitly (2026-09-28: *"use venue.html i dont care just make it work without adding a second page"*).
--
-- Two rules keep the two tenants out of each other's way, and neither is new:
--   * **The venue option list yields while the card is up.** The input loop below already stands down on
--     `NcmClientBuildActive`, exactly as it does on `NcmClientRaceActive`, and sends `venue:hide` on the way
--     out — so only one of the two is ever on screen.
--   * **Nothing here takes focus.** The page stays `pointer-events: none` and is never focused, which is what
--     makes it safe to leave attached during a race (`KB-67`). `race_builder.lua` reads its keys in Lua.
--
-- `on` is deferred because handlers are registered at file scope, before `onClientResourceStart` has built the
-- page. A handler registered against a page that does not exist yet would simply be lost, which is the same
-- class of silent failure as a stream beginning before its receiver.
NcmVenueSurface = {}

local borrowed = {}      -- name -> fn, registered before the page existed

--- The live page, or nil while it does not exist or has not reported ready. Callers must treat nil as "not now"
--- rather than as an error: a surface that is not ready is a normal state during resource start.
function NcmVenueSurface.page()
    if vpage and vpageReady then return vpage end
    return nil
end

function NcmVenueSurface.send(name, value)
    local p = NcmVenueSurface.page()
    if not p then return false end
    local ok, err = pcall(function() p:send(name, value) end)
    if not ok then log("venue surface send(%s) failed: %s", tostring(name), tostring(err)) end
    return ok
end

function NcmVenueSurface.on(name, fn)
    borrowed[name] = fn
    if vpage then pcall(function() vpage:on(name, fn) end) end
end
local venueBag, historyBag, practiceBag = nil, nil, nil
-- The server's `at` stamp last acted on, per panel. See `readVenueBags`: a persisted bag must be
-- adopted silently, never treated as a fresh request.
local historyAt, practiceAt = nil, nil
local venueSig = nil                 -- I4: content signature of the list, so a republish is not a change
local selId, panelOpen = nil, nil    -- I4: the highlight is remembered by option ID, never by row index
local lastDrawn = nil

--- Index of the remembered option, or 1 when it is gone (the list is contextual, so options come and go).
local function selIndex(options)
    for i, o in ipairs(options) do if o.id == selId then return i end end
    return 1
end

local function sendVenue()
    if not (vpage and vpageReady) then return end
    local v = venueBag
    -- The card must belong to the ring we are standing in. A bag for a different ring is a card on its way out
    -- (the server has not yet answered our new position), and drawing it is exactly the old defect: the list on
    -- one ring acting on another race.
    if v and v.eventId ~= standingIn then v = nil end
    if not v or type(v.options) ~= "table" or #v.options == 0 or panelOpen then
        if lastDrawn ~= "hidden" then lastDrawn = "hidden"; vpage:send("venue:hide", {}) end
        return
    end
    local i = selIndex(v.options)
    selId = v.options[i].id
    lastDrawn = "list"
    vpage:send("venue:list", {
        series = v.series, route = v.route, sub = v.venue, options = v.options, sel = i - 1, hold = holdFraction or 0,
    })
end

local function closePanel()
    if not panelOpen then return end
    panelOpen = nil
    if vpage and vpageReady then vpage:send("venue:closePanel", {}) end
    lastDrawn = nil
    sendVenue()
end

local function engage()
    local v = venueBag
    if not v or type(v.options) ~= "table" or v.eventId ~= standingIn then return end
    local o = v.options[selIndex(v.options)]
    if not o then return end
    -- Disabled options are shown so the player can see what exists (owner, 2026-09-23), but pressing one must
    -- do nothing except explain itself. The server re-checks regardless; this stops a pointless round trip.
    if o.enabled == false then
        log("venue option refused: %s (%s)", tostring(o.id), tostring(o.why))
        pcall(function()
            call("open77_notifications", "show", { id = "ncm_venue_why", replace = true, type = "warning",
                title = tostring(o.label or o.id):upper(), message = tostring(o.why or "Not available right now."),
                icon = "NCM", durationMs = 4000 })
        end)
        return
    end
    log("venue option engaged: %s (%s)", tostring(o.id), tostring(v.eventId))
    TriggerServerEvent("ncm:venue.option", o.id, v.eventId)   -- the ring it was drawn for; the server refuses a stale one
end

AddEventHandler("onClientResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    local reason
    vpage, reason = WebUI.create({
        entry = "web/venue.html", layer = "hud", width = 1920, height = 1080,
        fps = 20, zIndex = 720, transparent = true, visible = true,
    })
    if not vpage then log("venue WebUI failed: %s", tostring(reason)); return end
    vpage:on("venue:ready", function() vpageReady = true; lastDrawn = nil; log("venue list ready") end)
    -- Handlers other files asked for before this page existed (`NcmVenueSurface.on`). Bound here rather than
    -- dropped, because a listener registered against a page that does not exist yet is silently lost.
    for name, fn in pairs(borrowed) do
        pcall(function() vpage:on(name, fn) end)
    end
end)


-- The three bags the server writes for this surface. KB-41: the watcher carries no payload; we always read our own.
local function readVenueBags()
    local ok, bag = pcall(Open77.state.localPlayer)
    if not ok or type(bag) ~= "table" then return end
    -- I4 (live QA 2026-09-22: "tapping e moves to the second row briefly, then back to the top without any user
    -- input"). The old test was `bag.ncmVenue ~= venueBag` -- a table IDENTITY check. The server republishes this
    -- bag on every guide refresh and calendar publish, so a fresh table arrived every few seconds with identical
    -- contents, the check fired, and the highlight was reset to row 1. Rows 2 and 3 were unreachable in practice.
    -- Compare what the list SAYS instead, and remember the highlight by option id so it survives a republish --
    -- and so it still points at the right thing when the list itself changes (ENTER RACE -> WITHDRAW).
    local nv = bag.ncmVenue
    local sig = nil
    if type(nv) == "table" and type(nv.options) == "table" then
        local ids = {}
        for i, o in ipairs(nv.options) do ids[i] = tostring(o.id) end
        sig = tostring(nv.eventId) .. "|" .. table.concat(ids, ",")
    end
    if sig ~= venueSig then
        venueSig = sig
        lastDrawn = nil
        if selId then
            local still = false
            for _, o in ipairs((type(nv) == "table" and nv.options) or {}) do if o.id == selId then still = true end end
            if not still then selId = nil end
        end
    end
    venueBag = nv
end

-- **A request is an event, not a persisted bag** (KB-97).
--
-- History and practice are pushed ONLY when the driver picks that option, so an event is both the private
-- channel and the honest one. The bag version needed an `at`-stamp adoption rule purely because a bag survives
-- into the next session and would otherwise read as a fresh request -- which is what made the history panel
-- reopen itself and hide the option list (KB-67, and the owner QA "there is no race panel to enter the race
-- when i am at race venue"). An event cannot arrive twice, so that whole class of bug is gone rather than
-- guarded against.
local function openVenuePanel(kind, v)
    if type(v) ~= "table" then return end
    if vpage and vpageReady then
        panelOpen = kind
        vpage:send("venue:" .. kind, v)
        vpage:send("venue:hide", {})
        lastDrawn = "hidden"
    end
end

RegisterNetEvent("ncm:venue.history", function(v) historyBag = v; openVenuePanel("history", v) end)
RegisterNetEvent("ncm:venue.practice", function(v) practiceBag = v; openVenuePanel("practice", v) end)

-- One key, polled: tap cycles, hold engages. Pad X does the same job for a controller.
CreateThread(function()
    local heldSince, fired = nil, false
    while true do
        local here = (next(rings) ~= nil and not NcmClientRaceActive) and ringHere(localPosition()) or nil
        tellStanding(here)
        local near = here ~= nil
        -- while racing, race.lua owns the HUD and the venue list must not sit under it; while the Street Call
        -- card is up, race_builder.lua owns the same E key and the same corner of the screen (L179)
        if near and not NcmClientRaceActive and not NcmClientBuildActive then
            readVenueBags()
            local captured = false
            pcall(function() captured = Open77.input.isCaptured() == true end)
            local down = false
            if not captured then
                local okK, k = pcall(Open77.input.isDown, ENGAGE_KEY)
                local okP, pk = pcall(Open77.input.isDown, PAD_KEY)
                down = (okK and k == true) or (okP and pk == true)
            end
            if down then
                heldSince = heldSince or Open77.time.monotonic()
                local held = Open77.time.monotonic() - heldSince
                holdFraction = math.min(1, held / HOLD_S)
                if held >= HOLD_S and not fired then
                    fired = true
                    holdFraction = 0
                    if panelOpen then closePanel() else engage() end
                end
            else
                if heldSince and not fired then
                    -- a release below the hold time is a tap: move the highlight, or close an open panel
                    if panelOpen then
                        closePanel()
                    elseif venueBag and type(venueBag.options) == "table" and #venueBag.options > 0 then
                        local opts = venueBag.options
                        -- step to the next PRESSABLE option; fall back to the next one if none are
                        local start, pick = selIndex(opts), nil
                        for step = 1, #opts do
                            local cand = opts[((start + step - 1) % #opts) + 1]
                            if cand and cand.enabled ~= false then pick = cand; break end
                        end
                        selId = (pick or opts[(start % #opts) + 1]).id
                        lastDrawn = nil
                    end
                end
                heldSince, fired, holdFraction = nil, false, 0
            end
            sendVenue()
            Wait(50)
        else
            -- KB-67. This teardown used to be guarded by `lastDrawn ~= "hidden"` alone, and opening a panel
            -- sets `lastDrawn = "hidden"` (it hides the option LIST). So the one state that most needed
            -- cleaning up was the one state that skipped it: start a race or walk out of radius with the
            -- history panel open and `venue:closePanel` was never sent, while `panelOpen` was cleared in this
            -- same line -- which also killed the tap-to-close path, because that needs `panelOpen` truthy.
            -- A dead overlay then sat on top of a screen `race.lua` owns, with nothing able to dismiss it.
            --
            -- The panel and the list are two different things and now get two different tests.
            if panelOpen and vpage and vpageReady then
                vpage:send("venue:closePanel", {})
                log("venue: closed a left-open %s panel (KB-67)", tostring(panelOpen))
            end
            if lastDrawn ~= "hidden" and vpage and vpageReady then lastDrawn = "hidden"; vpage:send("venue:hide", {}) end
            -- cleared only AFTER the close has gone out
            heldSince, fired, holdFraction, panelOpen = nil, false, 0, nil
            Wait(400)
        end
    end
end)

local function refreshHint()
    -- While the local driver is in a race session, race.lua owns the card and the markers.
    if NcmClientRaceActive then
        if lastHint.text then
            lastHint = { text = nil, title = nil }
            pcall(function() call("open77_notifications", "clear") end)   -- do not leave a frozen card behind the race HUD
        end
        removeAllRings()
        return
    end
    local entry = myEntry()
    local entryState = entry and tostring(entry.state or "") or nil
    local activeEntry = entry and entry.eventId and entryState ~= "withdrawn" and entryState ~= "cancelled"
    local entryEvent = nil
    if activeEntry and cal and type(cal.next) == "table" then
        for _, candidate in ipairs(cal.next) do
            if candidate.eventId == entry.eventId then entryEvent = candidate; break end
        end
    end
    -- Venue discovery is world information, not a reward for clicking INTEREST: every race inside its window has
    -- its own ring at its own venue, Street Calls included (owner, 2026-09-28). An invitational is ringed only
    -- for the driver who holds a seat in it -- nobody else can do anything there.
    local targets = {}
    if cal and type(cal.next) == "table" then
        local t = serverNow()
        for _, candidate in ipairs(cal.next) do
            local mineSeat = activeEntry and entry.eventId == candidate.eventId
            if (not candidate.invitation or mineSeat) and candidate.startsAt - t <= VENUE_RING_LEAD_S then
                targets[#targets + 1] = candidate
            end
        end
    end
    syncRings(targets)

    -- Race toasts are personal: only an event the driver is interested in or has entered may own one.
    -- The venue ring remains above even when there is no personal notification.
    if not entryEvent then
        if lastHint.text then
            lastHint = { text = nil, title = nil }
            pcall(function() call("open77_notifications", "clear") end)
        end
        return
    end
    local next = entryEvent
    -- A driver with a seat in an organized event is routed by the race HUD, never by the street cadence (a
    -- cadence pin sent the owner to Vista Del Drag mid-weekend, Batch 1 live 2026-09-21).
    local ownsTarget = activeEntry and entry.eventId == next.eventId
    local interested = ownsTarget and entryState == "interested"
    local entered = ownsTarget and not interested
    if interested and next.state == "entry_open" and not next.invitation and not autoRouted[next.eventId] and not NcmClientRaceActive then
        autoRouted[next.eventId] = true
        local okWp, wp = pcall(Open77.blips.waypoint)
        if not (okWp and wp) then
            CreateThread(function() routeTo(next.venue, next.eventId, "entries open") end)
        else
            log("entries open for %s; keeping the player's own waypoint", next.eventId)
        end
    end
    local remaining = next.startsAt - serverNow()
    local pos = localPosition()
    local dist = pos and Routes.planarDistance(pos, next.venue) or nil
    -- KB-27: an entry in state `interested` is NOT an entry. Interest is a soft list (L35/P21/P52): it reserves
    -- nothing, forms no grid, and the driver must still enter physically at the line. Conflating the two told the
    -- player he was racing AND removed the venue marker he needed in order to actually enter.
    local n = tonumber(next.entries) or 0
    local onList = tonumber(next.interested) or 0
    local field
    if next.invitation then
        field = entered and entry.teamName and ("you drive for " .. entry.teamName .. " (car " .. tostring(entry.seatIndex or 1) .. ")")
            or (("%d/%d seats taken · invited drivers only"):format(tonumber(next.seatsTaken) or 0, tonumber(next.seatsTotal) or 0))
    else
        if interested then
            field = "you're on the list · drive to the line to enter"
                .. (n > 0 and ("  ·  " .. n .. " entered") or "")
        else
            field = entered and (n <= 1 and "you alone so far" or ("you + " .. (n - 1) .. " other" .. (n > 2 and "s" or "")))
                or (n == 0 and (onList > 0 and (onList .. " on the list · nobody entered yet") or "nobody entered yet")
                or (n .. " entered"))
        end
    end
    local text
    if remaining <= 0 then
        text = ("%s · %s · starting · %s"):format(next.seriesName, next.routeName, field)
    else
        text = ("%s · %s · %s%s · %s"):format(next.seriesName, next.routeName, coarseCountdown(remaining),
            dist and ("  ·  " .. coarseDistance(dist, next.venue.name)) or "", field)
    end
    local title
    if next.invitation then
        title = entered and ("NCX · " .. string.upper(tostring(entry.teamShort or "SEAT"))) or "NCX · INVITATIONAL"
    else
        title = (entered and "NCM · ENTERED")
            or (interested and "NCM · ON THE LIST")
            or (next.state == "entry_open" and "NCM · NEXT RACE · ENTRIES OPEN")
            or "NCM · NEXT RACE"
    end
    if text ~= lastHint.text or title ~= lastHint.title then
        lastHint = { text = text, title = title }
        local okShow, res, why = pcall(function()
            return call("open77_notifications", "show", {
                id = "ncm_heartbeat", replace = true,
                type = entered and "success" or "info",
                title = title, message = text, icon = "NCM",
                position = "middle_left", durationMs = 0,
                -- three visibly distinct states: entered (green) / on the list (amber) / just upcoming (cyan)
                color = (entered and "#3BE28A") or (interested and "#E2B93B") or "#22D8E2",
            })
        end)
        local failure = (not okShow and tostring(res)) or (type(res) == "table" and not res.ok and tostring(res.error)) or (res == nil and tostring(why)) or nil
        if failure and failure ~= lastHint.failure then
            lastHint.failure = failure
            log("hint show failed: %s", failure)
        elseif not failure and lastHint.failure then
            lastHint.failure = nil
            log("hint show recovered")
        end
    end
    -- I9 (live QA 2026-09-22: "entrance ring disappears upon race entry ... no options panel available").
    -- This used to read `if entered or next.invitation`, from when the marker's only job was to enter the race --
    -- once you were in, it had nothing left to say. IDEA-095 changed what the marker IS: it is now the way to
    -- reach WITHDRAW, PRACTICE and HISTORY, all of which matter most *after* you are entered. Taking it down on
    -- entry deletes the surface at the moment it becomes useful. An owned invitational seat keeps it too;
    -- unowned invitationals are filtered from the automatic calendar target above.
    -- Every ring owns its own venue surface; the personal event above owns only the toast.
end

CreateThread(function()
    Wait(2000)
    while true do
        local g = GlobalState and GlobalState.ncmCalendar or nil
        if type(g) == "table" then
            applyCalendar(g, "global")
        elseif not cal and (Open77.time.monotonic() % 10) < 1 then
            log("calendar: GlobalState.ncmCalendar not present yet")
        end
        local ok, err = pcall(refreshHint)
        if not ok then log("hint error: %s", tostring(err)) end
        Wait(1000)
    end
end)

local function clearGps()
    NcmNav.clear()
    gps = { eventId = nil }
end

-- Set the waypoint. NCM never opens the player's map for them (L70, owner 2026-09-21): the old KB-1 "kick"
-- (open then close the native map to force the engine to compute the road line) was jarring, fired while the
-- player was driving, and was unreliable anyway.
--
-- IDEA-052 assumed the missing road line was a platform limitation. It is not: `client/nav.lua` now uses the
-- routable-blip recipe the platform's own race gamemode uses, and re-selects it when the driver's seat context
-- changes. This function is kept as the calendar's spelling of "point me at a venue".
routeTo = function(p, eventId, why)
    gps = { eventId = eventId }
    NcmNav.to(p, why)
end

-- /ncm.gps — a calculated road route to the next start venue.
-- Verified 2026-09-19 (E17): a routable blip that is created and tracked gets a pin but the engine
-- does not compute the road path until tracking is cleared and re-set (opening the map does the
-- same). clearWaypoint -> setWaypoint routes immediately, so that is the whole recipe.
local function gpsCommand()
    -- In a session, the HUD's target (grid, start line, next gate) wins over the street cadence. `/ncm.gps` is
    -- a RECOVERY tool, not part of racing: what it does here is re-select the existing target against the
    -- driver's current seat context, which is precisely what opening and closing the map used to do by hand.
    local target = NcmClientRaceTarget and NcmClientRaceTarget() or nil
    if target then
        NcmNav.refresh("command")
        log("gps: refreshed the live target (%s)", tostring(target.why))
        return
    end
    -- Your own race first. `cal.next[1]` is merely the soonest race ON THE SERVER, usually one you have
    -- never heard of -- the same trap the heartbeat card warns about above. It also never checked whether
    -- that race had already STARTED, so /ncm.gps routed to elapsed events one after another before ever
    -- reaching the one the driver had actually entered (owner, 2026-09-23).
    local entry = myEntry()
    local state = entry and tostring(entry.state or "") or nil
    if entry and entry.venue and state ~= "withdrawn" and state ~= "cancelled" then
        CreateThread(function() routeTo(entry.venue, entry.eventId, "command:my entry") end)
        return
    end
    local soonest, at = nil, serverNow()
    for _, candidate in ipairs((cal and cal.next) or {}) do
        if (candidate.startsAt or 0) > at and (not soonest or candidate.startsAt < soonest.startsAt) then
            soonest = candidate
        end
    end
    if not soonest then return end
    CreateThread(function() routeTo(soonest.venue, soonest.eventId, "command") end)
end
RegisterCommand("ncm.gps", gpsCommand, false)
NcmQuickActions = NcmQuickActions or {}
NcmQuickActions.gps = gpsCommand

-- /ncm.gps.echo — diagnostic (E17): take the waypoint the player set by hand on the map, clear it,
-- and re-set the SAME coordinates through the scripted API. If the route line comes back, scripted
-- pins route and our venue coordinates are the problem; if it does not, scripted pins never route.
RegisterCommand("ncm.gps.echo", function()
    CreateThread(function()
        local wp, reason = Open77.blips.waypoint()
        if not wp then log("gps.echo: no hand waypoint (%s)", tostring(reason)); return end
        log("gps.echo: hand waypoint at %.1f %.1f %.1f", wp.x, wp.y, wp.z)
        Open77.blips.clearWaypoint()
        Wait(1000)
        local ok, r = Open77.blips.setWaypoint({ x = wp.x, y = wp.y, z = wp.z })
        log("gps.echo: scripted setWaypoint -> %s %s", tostring(ok), tostring(r))
    end)
end, false)

AddEventHandler("onClientResourceStop", function(name)
    if name == "ncm_world" then
        removeAllRings()
        clearGps()
        pcall(function() call("open77_notifications", "clear") end)
    end
end)
