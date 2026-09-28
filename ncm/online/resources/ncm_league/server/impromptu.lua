-- ncm_league / server / impromptu — a driver calling their own race (`L179`, reshaped by `L181`; P12, P17).
--
-- `P12` gave impromptu events their permission on day one -- *"any driver, from wherever they stand; lightweight
-- rules"* -- and `P17` said they post through the scheduler like everything else. `impromptu` sat in the
-- `EventClass` enum and the `event.class` column with no code on either side of it until `L179`.
--
-- WHAT `L181` CHANGED HERE. The first build asked six questions and could only start a race at an authored node,
-- which made the one thing a driver actually wants -- *race, here, now* -- the one thing it could not do. The form
-- is now submitted whole, its default start is the driver's own position, and that position becomes a **temporary
-- route** registered at runtime and thrown away afterwards.
--
-- THE EPHEMERAL ROUTE IS THE INTERESTING PART. A route is a list of points, and the host already turns a list of
-- points into a course: `/ncm.ar` authors one that way and `scenario.lua::registerCustom` registers it. This does
-- the same thing with two deliberate differences, which is why it is a separate function rather than a reuse:
--   * **Nothing is persisted.** An authored route is reference data and lives in `custom_route`; a Street Call
--     route describes where somebody happened to be standing once, so it exists only in `data.roots` /
--     `data.nodes` for the lifetime of the process.
--   * **It is swept.** `releaseRoute` unregisters the root and its two temporary nodes once the event is done.
--     Without that, every called race would leave a start line on the map and a row in the builder's own node
--     list forever -- which is why `data.nodes` grew an `unregister` for this.
--
-- THE FORM IS VALIDATED SERVER-SIDE AND THE OPTION LISTS ARE THE SERVER'S. The client renders the schema the
-- server published and submits a form; the server re-derives every list and refuses anything not on it, so a
-- client cannot invent a node, a class, a start time or a checkpoint.
--
-- WHAT A PLAYER-CALLED RACE DELIBERATELY IS NOT:
--   * Not invitational. Announced server-wide, entered at the start line like a calendar event (`L35`).
--   * Not paid. `economy` is nil, so settlement finds no purse -- two friends alternating wins would be a money
--     printer and the economy is younger than this feature.
--   * Not free of cadence. `KB-165`: a per-race permission is a permanent cadence. Hence a per-driver cooldown
--     AND a server-wide cap on how many may be open at once; the second is not redundant, because five drivers
--     each obeying the first would still fill the board.
NcmImpromptu = {}

local Core = NcmCore
local Builder = Core.get("competition.race_builder")
local Routes = Core.get("course.routes")
local Roots = Core.get("data.roots")
local Nodes = Core.get("data.nodes")
local Entry = Core.get("competition.entry")

local function log(fmt, ...) print(("[ncm_league/impromptu] " .. fmt):format(...)) end
local now = function() return Open77.time.unix() end

local function setting(key, default)
    local s = NcmCalendar and NcmCalendar.settings
    local ok, v = pcall(function() return s and s[key] end)
    return (ok and v) or default
end

local function tell(pid, text) if pid then pcall(Open77.chat.send, pid, "[NCM] " .. text) end end
local function toast(pid, def) if pid then pcall(Open77.notifications.send, pid, def) end end

--- How close a driver must be to the start to enter one of these. NOT the scenario host's 1e9 (which means
--- "anywhere", so a QA scenario can enter everyone where they stand): a Street Call is a real event and `L35`
--- applies to it like any other.
local VENUE_RADIUS_M = 60

local open = {}          -- playerId -> true while a form is open (the form itself lives on the client)
local lastCalled = {}    -- ncmDriverId -> unix seconds of their last CONFIRMED race
local ephemeral = {}     -- eventId -> { rootId, nodeIds = { startId, finishId } }

-- ---------------------------------------------------------------------------------------------
-- Position, refusals, publication
-- ---------------------------------------------------------------------------------------------

--- The authoritative position, or nothing. `fresh` is respected because a stale snapshot is a position the driver
--- has left, and 0,0,0 is a real place in Night City. A missing position is not fatal: the form simply cannot
--- offer "here" and says so (`schema.hasPosition`), rather than locking the feature.
local function observedPosition(pid)
    local ok, ps = pcall(Open77.players.get, tonumber(pid) or 0)
    if ok and ps and ps.fresh and type(ps.position) == "table" then
        local p = ps.position
        return { x = p.x, y = p.y, z = p.z, heading = tonumber(ps.heading or ps.yaw or 0) or 0 }
    end
    return nil
end

local function openImpromptuCount(t)
    local n = 0
    for _, eid in ipairs(NcmCalendar.orderedIds()) do
        local e = NcmCalendar.events[eid]
        if e and e.class == "impromptu" and e.state ~= "closed" and e.state ~= "cancelled" and (e.startsAt or 0) > t then
            n = n + 1
        end
    end
    return n
end

--- Why this driver may not call a race right now, or nil. The builder knows nothing about races, clocks or quotas,
--- so the host decides this and the builder never guesses.
local function refusalFor(pid, driver, t)
    if not driver then return "no_driver" end
    if NcmRace and NcmRace.busySession and NcmRace.busySession(driver.ncmDriverId) then return "already_racing" end
    local cooldown = tonumber(setting("impromptuCooldownSec", 900)) or 900
    local last = lastCalled[driver.ncmDriverId]
    if last and (t - last) < cooldown then return "cooldown" end
    if openImpromptuCount(t) >= (tonumber(setting("impromptuMaxOpen", 2)) or 2) then return "too_many_open" end
    return nil
end

local REFUSAL_TEXT = {
    no_driver = "No NCM driver on this connection yet.",
    already_racing = "Finish the race you are in first.",
    cooldown = "You called one recently. Give the street a minute.",
    too_many_open = "There are already enough open races on the board.",
    -- form validation, from competition.race_builder
    form_not_table = "That form did not arrive intact.",
    position_unknown = "Cannot read where you are standing yet -- pick a start point instead.",
    invalid_start = "That start point is not one a race may use.",
    finish_required = "Choose where the race finishes.",
    invalid_finish = "That finish is not one a race may use.",
    invalid_checkpoint = "One of those checkpoints is not a place a race may pass through.",
    too_many_checkpoints = "That is more checkpoints than a route may carry.",
    repeated_point = "Two points in a row are the same place -- that leg has no length.",
    invalid_class = "That class cannot enter a street race.",
    invalid_minutes = "Pick one of the offered start times.",
    too_short = "That route is too short to be a race.",
    route_unresolved = "Could not build a course from those points.",
    too_few_points = "A race needs a start and a finish.",
}

--- Publish this player's builder form: the option lists and a blank form. The client draws this and holds the
--- form; the server keeps no copy, because a form is worthless until it is submitted and re-validated.
---
--- **A STREAM, NOT A STATE BAG, AND THAT IS `KB-172`.** This was `Open77.state.player(pid):set("ncmBuild", ...)`
--- and it never once worked. A player state bag holds **4,032 bytes** (`IDEA-509`: 4,032 accepted, ~5,010
--- refused); one schema is **11,515**, because it carried the 35-node list twice. So every press of F5 wrote a
--- bag the platform discarded, the client polled for three seconds and gave up, and **nothing anywhere said
--- why** -- the server logged `form opened`, the client logged `no form arrived`, and neither was wrong.
---
--- Two things made it silent, and both are fixed here. The write was wrapped in a `pcall` that **discarded
--- `:set`'s return value**, so a refusal that reports rather than raises was indistinguishable from success.
--- And the payload was never measured. `NcmStream` does both: it splits the rows by measured bytes and it
--- returns the size for this log line. That is the whole point of `server/stream.lua`, whose header already
--- named `KB-59`, `KB-86`, `KB-153` and `KB-160` as four instances of this one bug -- this is the fifth, and
--- the first to reach a player.
local function publish(pid)
    -- Closing needs no message: there is no bag to clear, and a stream that is not sent is not received. The
    -- client tears its own card down on the path that asked for the close.
    if not open[pid] then return end
    local facts = { position = observedPosition(pid), now = now() }
    local payload = Builder.wire(facts)
    payload.serverNow = math.floor(now())

    local okSend, size, headBytes, packets = pcall(NcmStream.send, pid, "ncm:build", payload, "nodes")
    if not okSend then
        log("BUILD PUBLISH FAILED player=%d: %s", pid, tostring(size))
        tell(pid, "Could not build the form. Try again in a moment.")
        return
    end
    log("form published player=%d nodes=%d bytes=%d head=%d packets=%d",
        pid, #(payload.nodes or {}), size, headBytes, packets)
end
NcmImpromptu.publish = publish

-- ---------------------------------------------------------------------------------------------
-- The ephemeral route
-- ---------------------------------------------------------------------------------------------

--- Register a one-race route from a point list. Same shape as the host kit's authored routes, without the
--- persistence. Returns the resolved route, nil, and the handle needed to give it back.
local function claimRoute(key, name, points, laps, loop)
    if type(points) ~= "table" or #points < 2 then return nil, "too_few_points" end
    local rootId = "street_call_" .. key
    local sId, eId = rootId .. "_s", rootId .. "_e"
    local first, last = points[1], points[#points]
    Nodes.register({ id = sId, x = first.x, y = first.y, z = first.z or 0, heading = first.heading or 0,
                     name = first.name or (name .. " start"), road = true, custom = true })
    Nodes.register({ id = eId, x = last.x, y = last.y, z = last.z or 0, heading = last.heading or 0,
                     name = last.name or (name .. " finish"), road = true, custom = true })
    local mid = {}
    for i = 2, #points - 1 do
        mid[#mid + 1] = { x = points[i].x, y = points[i].y, z = points[i].z or 0,
                          heading = points[i].heading, name = points[i].name or ("gate " .. (i - 1)) }
    end
    Roots.register({
        rootId = rootId, startNodeId = sId, endNodeId = eId, displayName = name,
        intermediate = mid, disciplineId = Builder.DISCIPLINE, laps = laps or 1, custom = true, loop = loop == true,
    })
    local route = Routes.resolve(rootId, name)
    if not route then
        Roots.unregister(rootId); Nodes.unregister(sId); Nodes.unregister(eId)
        return nil, "route_unresolved"
    end
    return route, nil, { rootId = rootId, nodeIds = { sId, eId } }
end

--- Give a one-race route back. Called when the event is done, and also swept -- an event can end in ways nothing
--- routes through this file, so the release is driven by observation rather than by being told.
local function releaseRoute(eventId)
    local ref = ephemeral[eventId]
    if not ref then return false end
    ephemeral[eventId] = nil
    Roots.unregister(ref.rootId)
    for _, id in ipairs(ref.nodeIds or {}) do Nodes.unregister(id) end
    log("released route %s (event %s)", ref.rootId, tostring(eventId))
    return true
end
NcmImpromptu.releaseRoute = releaseRoute

-- ---------------------------------------------------------------------------------------------
-- Creating the event
-- ---------------------------------------------------------------------------------------------

local function create(pid, driver, spec, t)
    local tag = ("%s%d"):format((tostring(driver.ncmDriverId):gsub("%-", "")):sub(1, 6), math.floor(t) % 100000)
    local route, why, ref = claimRoute(tag, spec.routeName, spec.points, spec.laps, spec.loop)
    if not route then return nil, why end

    local startsAt = math.floor(t + spec.minutes * 60)
    local e = {
        eventId = ("impromptu:%s@%d"):format(tag, startsAt),
        class = "impromptu", invitation = false, registration = "venue",
        packId = "ncm_pack_street",
        seriesId = "impromptu", seriesName = "Street Call",
        rulesetId = "street_sprint_v0", tier = "street",
        routeId = route.routeId, routeName = route.name,
        startsAt = startsAt,
        entryOpensAt = math.floor(t),
        entryClosesAt = startsAt - (tonumber(setting("raceFormAtSec", 60)) or 60),
        venue = { x = route.start.x, y = route.start.y, z = route.start.z, heading = route.start.heading,
                  name = route.start.name, nodeId = route.start.id },
        finish = { x = route.finish.x, y = route.finish.y, z = route.finish.z,
                   name = route.finish.name, nodeId = route.finish.id },
        -- the authored intermediate points, so a publication can hand out the whole lap rather than its two ends (L177)
        via = route.intermediate,
        distanceM = route.distanceM, venueRadiusM = VENUE_RADIUS_M,
        state = "entry_open", entries = {}, postedAt = t,
        disciplineId = spec.disciplineId, formatId = spec.formatId, classId = spec.classId, laps = spec.laps,
        -- no `economy`: a Street Call pays nothing (see the header). Settlement finds no purse and that is the
        -- intended behaviour, not an omission waiting to be filled in.
        calledBy = driver.ncmDriverId,
        ephemeralRoute = true,
    }
    local ok, err = NcmCalendar.adopt(e)
    if not ok then
        Roots.unregister(ref.rootId)
        for _, id in ipairs(ref.nodeIds) do Nodes.unregister(id) end
        return nil, err or "adopt_failed"
    end
    ephemeral[e.eventId] = ref
    lastCalled[driver.ncmDriverId] = t

    local gates = #(route.intermediate or {})
    log("CALLED %s | %s | %s | %d m%s | %d gate(s)%s | start in %s | by %s",
        e.eventId, e.routeName, e.venue.name, math.floor(e.distanceM),
        e.laps > 1 and (" x " .. e.laps .. " laps") or "", gates,
        spec.startsHere and " | improvised start" or "", Entry.countdown(e.startsAt - t), tostring(driver.ncmDriverId))

    -- announced to everyone, because that is what makes it a race rather than a private arrangement (P12)
    local caller = tostring(driver.display or "A driver")
    local via = gates > 0 and ((" via %d checkpoint(s)"):format(gates)) or ""
    for _, other in ipairs(Open77.players.all()) do
        toast(other, {
            type = other == pid and "success" or "info",
            title = "Street Call · " .. e.routeName,
            message = ("%s · %.1f km · start in %s"):format(caller, e.distanceM / 1000, Entry.countdown(e.startsAt - t)),
            icon = "NCM", durationMs = 9000,
        })
        tell(other, ("Street Call: %s called a race -- %s, %.1f km%s. Start in %s, be on the mark at %s."):format(
            caller, e.routeName, e.distanceM / 1000, via, Entry.countdown(e.startsAt - t), e.venue.name))
    end
    pcall(function()
        TriggerClientEvent("ncm:guide.route", pid,
            { x = e.venue.x, y = e.venue.y, z = e.venue.z, name = e.venue.name, eventId = e.eventId })
    end)
    return e
end

-- ---------------------------------------------------------------------------------------------
-- The three things a player can do
-- ---------------------------------------------------------------------------------------------

--- Open a form (the hotkey, or `/ncm.call`). Opening twice republishes rather than erroring: the key is a toggle
--- and a lost bag must be recoverable by pressing it again.
function NcmImpromptu.open(pid)
    pid = tonumber(pid) or 0
    local t = now()
    local driver = NcmCalendar.resolveDriver(pid)
    local refusal = refusalFor(pid, driver, t)
    if refusal then
        tell(pid, REFUSAL_TEXT[refusal] or ("Cannot call a race: " .. tostring(refusal)))
        log("open refused player=%d reason=%s", pid, tostring(refusal))
        return false, refusal
    end
    open[pid] = true
    publish(pid)
    log("form opened player=%d driver=%s", pid, tostring(driver.ncmDriverId))
    return true
end

function NcmImpromptu.close(pid, reason)
    pid = tonumber(pid) or 0
    if not open[pid] then return false end
    open[pid] = nil
    publish(pid)
    log("form closed player=%d reason=%s", pid, tostring(reason or "player"))
    return true
end

--- Submit the whole form. One call, one event.
function NcmImpromptu.submit(pid, form)
    pid = tonumber(pid) or 0
    if not open[pid] then return false, "no_form" end
    local t = now()
    local driver = NcmCalendar.resolveDriver(pid)

    -- re-check the quota at the moment of creation, not only when the form was opened: a form can sit open while
    -- somebody else fills the board (`KB-155` -- a guard that cannot fire is indistinguishable from a bug)
    local refusal = refusalFor(pid, driver, t)
    if refusal then
        local msg = REFUSAL_TEXT[refusal] or ("Cannot post it: " .. tostring(refusal))
        pcall(function() TriggerClientEvent("ncm:build.refused", pid, msg) end)
        log("submit refused player=%d reason=%s", pid, tostring(refusal))
        return false, refusal
    end

    -- the creator id is the server's, never the client's
    local submitted = type(form) == "table" and form or {}
    submitted.creatorId = driver.ncmDriverId
    local facts = { position = observedPosition(pid), now = t, creatorId = driver.ncmDriverId }

    local spec, why = Builder.spec(submitted, facts)
    if not spec then
        local msg = REFUSAL_TEXT[why] or ("That race cannot be posted: " .. tostring(why))
        -- the card the driver is looking at shows the reason; chat is the fallback, not the only channel
        pcall(function() TriggerClientEvent("ncm:build.refused", pid, msg) end)
        log("submit rejected player=%d reason=%s", pid, tostring(why))
        return false, why
    end

    local e, createWhy = create(pid, driver, spec, t)
    if not e then
        local msg = REFUSAL_TEXT[createWhy] or ("Could not post that race: " .. tostring(createWhy))
        pcall(function() TriggerClientEvent("ncm:build.refused", pid, msg) end)
        log("create failed player=%d reason=%s", pid, tostring(createWhy))
        return false, createWhy
    end
    pcall(function() TriggerClientEvent("ncm:build.posted", pid) end)
    NcmImpromptu.close(pid, "posted")
    return true, nil, e
end

-- ---------------------------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------------------------

RegisterNetEvent("ncm:build.open", function() NcmImpromptu.open(tonumber(source) or 0) end)
RegisterNetEvent("ncm:build.close", function() NcmImpromptu.close(tonumber(source) or 0, "client") end)
RegisterNetEvent("ncm:build.submit", function(form) NcmImpromptu.submit(tonumber(source) or 0, form) end)

AddEventHandler("onPlayerDisconnected", function(playerId)
    open[tonumber(playerId) or 0] = nil
end)

--- Chat twins, for the same reason every other surface has them: a keybind can collide (`KB-62`), a chat command
--- cannot. `false` is the restricted flag every other league command passes.
RegisterCommand("ncm.call", function(source)
    local pid = tonumber(source) or 0
    if pid > 0 then NcmImpromptu.open(pid) end
end, false)

RegisterCommand("ncm.call.scrap", function(source)
    local pid = tonumber(source) or 0
    if pid > 0 then NcmImpromptu.close(pid, "command") end
end, false)

--- Sweep. A route whose event is closed, cancelled, gone from the calendar, or an hour past its start has no
--- further use. Driven by observation because an event can end through a race abort, an operator cancel or a
--- settlement, none of which pass through this file.
CreateThread(function()
    while true do
        Wait(60000)
        local t = now()
        for eventId, _ in pairs(ephemeral) do
            local e = NcmCalendar.events and NcmCalendar.events[eventId]
            local finished = (not e)
                or e.state == "closed" or e.state == "cancelled"
                or ((tonumber(e.startsAt) or 0) + 3600) < t
            if finished then releaseRoute(eventId) end
        end
    end
end)

--- An impromptu event is minutes long, so nothing is restored across a restart -- and its route is not persisted,
--- so it could not be. The ROW persists though, and an `entry_open` row with no scheduler behind it is a ghost on
--- the board, so they are closed on boot rather than left looking live.
AddEventHandler("onResourceStart", function(name)
    if name ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(5000)      -- after migrations and the calendar's own restore
        local ok, err = pcall(function()
            MySQL.update.await(
                "UPDATE event SET state = 'closed' WHERE server_id = ? AND class = 'impromptu' AND state IN ('posted','entry_open')",
                { NcmCalendar.serverId() })
        end)
        if not ok then log("boot cleanup failed: %s", tostring(err)) end
    end)
end)
