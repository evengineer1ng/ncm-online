-- ncm_league / server / race — automated race control (M3.2; L19, L23, L20, L21; Batch 1: L53 formats, L56
-- incidents, L57 telemetry, holding L48).
--
-- An event runs a PLAN: the list of sessions its format declares (sprint = one race; weekend = practice, quali,
-- race; two_race = race, race with a reversed grid). Each session is driven by a kernel from ncm-core —
-- session.race for races, session.quali for practice/qualifying — through one interface (new/mark/leave/suspend/
-- resume/report/penalty/disqualify/incident/abort/step/classify/publicView). This file is only the host: clock,
-- positions, storage, messages, and the publication on GlobalState.ncmSession the client HUD reads.
NcmRace = {}

local Core = NcmCore
local Race = Core.get("session.race")
local Quali = Core.get("session.quali")
local Practice = Core.get("session.practice")
local Guide = Core.get("competition.guide")
local Grid = Core.get("session.grid")
local Gates = Core.get("course.gates")
local Routes = Core.get("course.routes")
local Entry = Core.get("competition.entry")
local Format = Core.get("competition.format")
local Discipline = Core.get("competition.discipline")
local Teams = Core.get("competition.teams")
local ids = Core.get("vocabulary.ids")

local function log(fmt, ...)
    print(("[ncm_league/race] " .. fmt):format(...))
end

-- Tunables are declared once per resource, in calendar.lua.
local function setting(key, default)
    local s = NcmCalendar and NcmCalendar.settings
    local ok, v = pcall(function() return s and s[key] end)
    return (ok and v) or default
end

local now = function() return Open77.time.unix() end
local hostRng = function() return math.random() end

-- IDEA-236/IDEA-303: which machine each connected player is sitting in, announced by `ncm_world` because
-- the two resources are separate Lua VMs and this cannot be read across. Kept here so settlement can resolve
-- it synchronously; latched per session at GREEN, never read live at settlement (a driver who steps out of
-- the car after finishing would otherwise settle as nil).
local seatedByPid = {}   -- playerId -> assetId | nil
AddEventHandler("ncm:machine.seated", function(pid, assetId)
    pid = tonumber(pid)
    if not pid or pid <= 0 then return end
    seatedByPid[pid] = (type(assetId) == "string" and #assetId == 36) and assetId or nil
end)
AddEventHandler("onPlayerDisconnected", function()
    local pid = tonumber(source)
    if pid then seatedByPid[pid] = nil end
end)

--- The machine this player is sitting in right now, or nil. Read by the ENTER gate so a driver who walks up
--- in a car enters THAT car rather than whichever of their machines happens to sort first (IDEA-312).
function NcmRace.seatedAsset(pid)
    pid = tonumber(pid)
    return pid and seatedByPid[pid] or nil
end

local sessions = {}      -- sessionId -> rec { s, kernel, kind, spec, plan, eventId, playerOf, slots, lastPos, toNext, progressM, doneAt, machineOf, ... }
local plans = {}         -- eventId -> { formatId, specs, i, sessionIds = {}, results = {}, done, e }
local byEvent = {}       -- eventId -> live sessionId | "done"
local practices = {}     -- eventId -> rec (on-demand practice, P48; also in `sessions` so gate reports find it)
local practiceViews = {} -- eventId -> public view (GlobalState.ncmPractice: one per event, beside the live session)
local sessionViews = {}  -- sessionId -> public view (GlobalState.ncmSessions: one per live session, IDEA-112)
NcmRace.sessions = sessions
NcmRace.plans = plans

local function serverId()
    return tostring((NcmCalendar and NcmCalendar.serverId and NcmCalendar.serverId()) or "ncm-dev")
end

-- ---------------------------------------------------------------------------------------------
-- Player <-> driver
-- ---------------------------------------------------------------------------------------------
local function playersByDriver()
    local out = {}
    for _, pid in ipairs(Open77.players.all()) do
        local d = NcmCalendar.resolveDriver(pid)
        if d then out[d.ncmDriverId] = tonumber(pid) end
    end
    return out
end

local function tell(pid, text)
    if pid then pcall(Open77.chat.send, pid, "[NCM] " .. text) end
end

local function toast(pid, def)
    if pid then pcall(Open77.notifications.send, pid, def) end
end

local function positionOf(pid)
    if not pid then return nil end
    local ok, p = pcall(Open77.players.get, pid)
    if ok and p and p.position then return p.position, p.fresh end
    return nil
end

local function fmtTime(sec)
    if not sec then return "--" end
    local m = math.floor(sec / 60)
    return string.format("%d:%06.3f", m, sec - m * 60)
end

-- ---------------------------------------------------------------------------------------------
-- Publication
-- ---------------------------------------------------------------------------------------------
--- The authored grid point of the working venue, but only when this route starts there: ncm_world has one
--- working venue (pacifica_stadium) and its grid sat next to the Troll Pass FINISH, so REPORT TO GRID pointed
--- the driver at the wrong end of the course (owner QA batch 2, 2026-09-21).
local VENUE_GRID_MAX_M = 120
local function venueGrid(start)
    local ok, v = pcall(function() return GlobalState.ncmVenue end)
    if not (ok and type(v) == "table" and type(v.grid) == "table") then return nil end
    if start and math.sqrt((v.grid.x - start.x) ^ 2 + (v.grid.y - start.y) ^ 2) > VENUE_GRID_MAX_M then return nil end
    return v.grid
end

local publishPractice   -- below
local republishSessions -- below

-- KB-79: send the same bounded read model directly to each entrant. The calendar GlobalState document reaches
-- clients, but the nested session map has repeatedly failed to produce a selectable client view. GlobalState is
-- retained as recovery/observation; this targeted path is the deliberate calendar-to-race ownership handoff.
local function publishToEntrants(rec, sessionView)
    local sent = {}
    for _, playerId in pairs(rec.playerOf or {}) do
        playerId = tonumber(playerId)
        if playerId and playerId > 0 and not sent[playerId] then
            sent[playerId] = true
            TriggerClientEvent("ncm:session", playerId, rec.s.sessionId, sessionView)
        end
    end
end

local function dropFromEntrants(rec)
    local sent = {}
    for _, playerId in pairs(rec.playerOf or {}) do
        playerId = tonumber(playerId)
        if playerId and playerId > 0 and not sent[playerId] then
            sent[playerId] = true
            TriggerClientEvent("ncm:session", playerId, rec.s.sessionId, false)
        end
    end
end

local function publish(rec, t)
    if rec.practice then return publishPractice(rec, t) end
    local v = rec.kernel.publicView(rec.s)
    -- The client matches itself by player id first (its own bag can lag after a reconnect), driver id second.
    for _, en in ipairs(v.entrants) do
        en.playerId = rec.playerOf[en.driverId]
        en.toNextM = rec.toNext and rec.toNext[en.driverId] or nil
        en.progressM = rec.progressM and rec.progressM[en.driverId] or nil
        en.correctedM = rec.correctedM and rec.correctedM[en.driverId] or en.progressM
        local sl = rec.slotOf and rec.slotOf[en.driverId]
        if sl then en.colour = sl.colour; en.number = sl.number; en.teamName = sl.teamName; en.teamShort = sl.teamShort end
    end
    v.serverNow = t
    -- The route's IDENTITY, not just its name. A ghost is keyed by route, and `routeName` is a display string
    -- that two routes may share; nothing client-side can recover the id from it.
    v.routeId = rec.routeId
    v.routeName = rec.routeName
    v.seriesName = rec.seriesName
    v.slots = rec.slots
    v.results = rec.results
    v.completeReason = rec.completeReason
    v.kind = rec.kind
    v.ordinal = rec.spec and rec.spec.ordinal or 1
    v.ofSessions = rec.spec and rec.spec.of or 1
    v.formatId = rec.spec and rec.spec.formatId or "sprint"
    v.disciplineId = rec.disciplineId
    v.lengthM = rec.course and rec.course.lengthM or nil
    v.laps = rec.course and rec.course.laps or 1
    v.grid = rec.gridPoint
    v.next = rec.nextSpec and { kind = rec.nextSpec.kind, ordinal = rec.nextSpec.ordinal, gridFrom = rec.nextSpec.gridFrom, n = rec.nextSpec.n, at = rec.nextAt } or nil
    sessionViews[rec.s.sessionId] = v
    republishSessions(t)
    publishToEntrants(rec, v)
end

-- IDEA-112: this used to be `GlobalState.ncmSession = v` -- ONE slot, written by every session, last writer wins.
-- With two races live at once every driver's HUD flickered between them, which made concurrent championships
-- impossible however well the rest of the runtime coped (and it copes: sessions, plans, byEvent and pickups are
-- all keyed maps and the tick already loops them all). Practice had already solved this exact problem one
-- function below with a map per event, so this follows that shape rather than inventing a second one.
--
-- Views are pruned against the live `sessions` table, so a retired session drops out on the next publish without
-- anyone having to remember to remove it. A completed session keeps its view until its rec is retired, which is
-- what holds the result board up during the result hold.
republishSessions = function(t)
    local out = {}
    for sid, v in pairs(sessionViews) do
        if sessions[sid] then out[sid] = v else sessionViews[sid] = nil end
    end
    out.serverNow = math.floor(t or now())
    GlobalState.ncmSessions = out
end

local function clearPublication()
    republishSessions(now())
end

-- Practice publications live beside the session one: one view per event; a client shows the practice it is
-- an entrant of only while no live session includes it (client/race.lua pickView).
local function republishPractice(t)
    local out = {}
    for eid, v in pairs(practiceViews) do out[eid] = v end
    out.serverNow = math.floor(t)
    GlobalState.ncmPractice = out
end

publishPractice = function(rec, t)
    local v = rec.kernel.publicView(rec.s)
    for _, en in ipairs(v.entrants) do
        en.playerId = rec.playerOf[en.driverId]
        en.toNextM = rec.toNext and rec.toNext[en.driverId] or nil
    end
    v.serverNow = t
    v.routeId = rec.routeId
    v.routeName = rec.routeName
    v.seriesName = rec.seriesName
    v.formatId = "practice"
    v.disciplineId = rec.disciplineId
    v.lengthM = rec.course and rec.course.lengthM or nil
    practiceViews[rec.eventId] = v
    republishPractice(t)
end

-- ---------------------------------------------------------------------------------------------
-- Forming: one session of a plan
-- ---------------------------------------------------------------------------------------------
local busyLogged = {}    -- eventId -> the last "held back" line logged, so the form retry does not repeat it

local function entrantsOf(e)
    local organized = e.class == "organized"
    local seatOrder = organized and NcmOrganized and NcmOrganized.seatOrder(e.eventId) or {}
    local entrants, busy = {}, {}
    for driverId, en in pairs(e.entries) do
        if en.state == "checked_in" or (organized and en.state == "registered") then
            -- KB-37: still racing elsewhere. Leaving them out is not a DNS -- their entry stays checked_in and
            -- unjudged, because "did not start" is a sporting fact and this is a scheduling collision.
            local otherSid, otherEvent = NcmRace.busySession(driverId)
            if otherSid then
                busy[#busy + 1] = ("%s (in %s of %s)"):format(driverId:sub(1, 8), otherSid:sub(1, 8), tostring(otherEvent))
            else
                entrants[#entrants + 1] = { driverId = driverId, entryId = en.entryId, checkedInAt = en.checkedInAt or 0, registeredAt = en.registeredAt or 0,
                    teamId = en.teamId, seatIndex = en.seatIndex, seatOrder = seatOrder[driverId] }
            end
        end
    end
    -- the form window retries every tick for ~65 s; say this once per event, not sixty-five times
    if #busy > 0 then
        local line = table.concat(busy, ", ")
        if busyLogged[e.eventId] ~= line then
            busyLogged[e.eventId] = line
            log("event=%s held back %d entrant(s) already in a live session: %s", e.eventId, #busy, line)
        end
    else
        busyLogged[e.eventId] = nil
    end
    return entrants, organized
end

local function courseFor(e, rules)
    local route = Routes.resolve(e.routeId, e.routeName)
    if not route then return nil, "route_unresolved" end
    local course, why = Discipline.buildCourse(e.disciplineId or "street_sprint", route,
        { laps = e.laps or 1, start = rules and rules.start or nil, formationM = rules and rules.formationM or nil })
    if not course then return nil, why end
    return course
end

--- Where a driver who has just entered this event should be pointed, BEFORE the grid forms.
---
--- Owner QA 2026-09-23: *"Do NOT make the player wait for lights-out before NCM changes navigation intent."*
--- Once entry succeeds we already know the event, so we already know the course -- `courseFor` needs nothing
--- from a session. The useful target is the first gate that is somewhere to GO: gate 1 is always the start
--- line (`discipline.buildCourse`) and the driver is standing on it. For a two-gate sprint that is the finish,
--- which is what "route me to Pothole, not to Hook's start" means.
---
--- Returns { x, y, z, name } or nil when the route cannot be resolved; a nil is not an error, it just means
--- this event has nothing better to offer than the venue the driver is already at.
function NcmRace.courseTarget(e)
    if type(e) ~= "table" then return nil end
    local ok, course = pcall(courseFor, e, NcmCompetition and NcmCompetition.rulesFor and NcmCompetition.rulesFor(e) or nil)
    if not ok or type(course) ~= "table" or type(course.gates) ~= "table" then return nil end
    for _, g in ipairs(course.gates) do
        if g.kind ~= "start" and type(g.x) == "number" then
            return { x = g.x, y = g.y, z = g.z, name = g.name or g.kind }
        end
    end
    return nil
end

local function formSession(plan, spec, t, startsAt)
    local e = plan.e
    local rules0 = NcmCompetition and NcmCompetition.rulesFor(e) or {}
    local kind0 = spec.kind or "race"
    -- the green gate belongs to races only; a qualifying run on the same route has no formation
    local course, why = courseFor(e, kind0 == "race" and rules0 or nil)
    if not course then log("cannot form %s: %s", e.eventId, tostring(why)); return nil end
    local gates = course.gates
    local entrants, organized = entrantsOf(e)
    if #entrants == 0 then return nil end
    local pmap = playersByDriver()
    for _, en in ipairs(entrants) do
        local pid = pmap[en.driverId]
        local name = (pid and GetPlayerName(pid)) or en.driverId:sub(1, 8)
        local team = en.teamId and Teams.byId(en.teamId)
        en.display = team and ("[" .. team.short .. "] " .. name) or name
    end
    -- grid order: from the prior session when the format says so, else seat order (organized) / check-in order
    local gridOpts = organized and { by = "seat" } or nil
    local prior = plan.results[#plan.results]
    local order = Format.gridFor(spec, prior)
    if order then
        local rank = {}
        for i, d in ipairs(order) do rank[d] = i end
        gridOpts = { order = rank }
    end
    local slots = Grid.assign(entrants, gates[1], gridOpts)
    local slotOf, specEntrants = {}, {}
    for _, sl in ipairs(slots) do
        local team = sl.teamId and Teams.byId(sl.teamId)
        local car = sl.teamId and Teams.carForSeat(sl.teamId, sl.seatIndex)
        local en = e.entries and e.entries[sl.driverId] or nil
        sl.colour = team and team.colour; sl.teamName = team and team.name; sl.teamShort = team and team.short
        -- A team seat carries the team car's number; a privateer carries the one their entry was given.
        sl.number = (car and car.number) or (en and en.carNumber) or nil
        sl.enteredAsset = en and en.assetId or nil          -- IDEA-312: the machine this entry named
        slotOf[sl.driverId] = sl
        specEntrants[#specEntrants + 1] = { driverId = sl.driverId, entryId = sl.entryId, slot = sl.slot, display = sl.display, teamId = sl.teamId, seatIndex = sl.seatIndex }
    end
    local sessionId = ids.uuid4(hostRng)
    local kind = spec.kind or "race"
    local kernel, s
    local rules = rules0
    if kind == "quali" or kind == "practice" then
        kernel = Quali
        s = Quali.new({ sessionId = sessionId, eventId = e.eventId, kind = kind, startsAt = startsAt, windowSec = spec.windowSec, maxRuns = spec.maxRuns, gates = gates, entrants = specEntrants })
    else
        kernel = Race
        rules.holdReleasePct = setting("holdReleasePct", rules.holdReleasePct or 0.75)
        rules.holdMaxWaitSec = setting("holdMaxWaitSec", rules.holdMaxWaitSec or 60)
        if rules.incidents then rules.incidents.baseSec = setting("incidentBaseSec", rules.incidents.baseSec or 2) end
        s = Race.new({ sessionId = sessionId, eventId = e.eventId, startsAt = startsAt, gates = gates, entrants = specEntrants, rules = rules })
    end
    local rec = {
        -- `routeId` is the route's IDENTITY; `routeName` is a display string two routes may share. Only the
        -- practice record carried the id, so anything keyed by route -- a ghost, a record, a leaderboard --
        -- silently got nil from a race session. A time trial is a race, so it got nil too.
        s = s, kernel = kernel, kind = kind, spec = spec, plan = plan, eventId = e.eventId,
        routeId = e.routeId, routeName = e.routeName, seriesName = e.seriesName,
        organized = organized, disciplineId = e.disciplineId, course = course, slots = slots, slotOf = slotOf, playerOf = pmap,
        results = nil, completeReason = nil, doneAt = nil, lastPos = {}, toNext = {}, progressM = {}, correctedM = {},
        gridPoint = venueGrid(gates[1]) or { x = gates[1].x, y = gates[1].y, z = gates[1].z, heading = 0 },
        rules = rules,
    }
    sessions[sessionId] = rec
    byEvent[e.eventId] = sessionId
    plan.sessionIds[#plan.sessionIds + 1] = sessionId
    local parent = plan.sessionIds[1] ~= sessionId and plan.sessionIds[1] or nil
    pcall(function()
        MySQL.insert.await(
            "INSERT INTO session (session_id, event_id, kind, state, starts_at, formed_at, entrants, gates, parent_session_id, ordinal, lap_count, format_id) VALUES (?, ?, ?, 'forming', ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?)",
            { sessionId, e.eventId, kind, math.floor(startsAt), math.floor(t), #slots, #gates, parent or "", spec.ordinal or 1, course.laps or 1, spec.formatId or "sprint" })
    end)
    if NcmTelemetry and NcmTelemetry.attach then NcmTelemetry.attach(rec) end
    -- announce
    local gridCars = {}
    for _, sl in ipairs(slots) do
        local pid = pmap[sl.driverId]
        local car = organized and sl.teamId and Teams.carForSeat(sl.teamId, sl.seatIndex) or nil
        -- The team car goes out at the plan's FIRST session, whatever its kind: drivers arrive on foot, and a
        -- practice window with no car is a wall (Batch 1 live, 2026-09-21). It stays out until the plan retires.
        if car and plan.gridCarsSpawned ~= true then
            gridCars[#gridCars + 1] = { driverId = sl.driverId, playerId = pid, slot = sl.slot, record = car.record, number = car.number,
                teamId = sl.teamId, teamName = sl.teamName, x = sl.x, y = sl.y, z = sl.z, heading = sl.heading }
        end
        if kind == "race" then
            if car then
                tell(pid, ("Grid is forming: %s · %s%s. Your car: #%d %s RB15 at slot %d of %d. Lights at %s."):format(
                    e.seriesName, e.routeName, spec.formatId == "two_race" and (" · race " .. (spec.ordinal or 1)) or "", car.number, sl.teamName, sl.slot, #slots, Entry.countdown(startsAt - t)))
                toast(pid, { type = "warning", title = ("#%d · P%d"):format(car.number, sl.slot), message = "Your car is on the grid — " .. e.routeName, icon = sl.teamShort or "NCM", color = sl.colour, durationMs = 8000 })
            else
                tell(pid, ("Grid is forming: %s · %s. You are P%d of %d — go to your mark. Lights at %s."):format(e.seriesName, e.routeName, sl.slot, #slots, Entry.countdown(startsAt - t)))
                toast(pid, { type = "warning", title = "GRID · P" .. sl.slot, message = "Go to your mark — " .. e.routeName, icon = "NCM", durationMs = 8000 })
            end
        else
            tell(pid, ("%s opens at %s: %s · %s. %sCross the start line to begin a run; your best run counts."):format(
                kind == "quali" and "Qualifying" or "Practice", Entry.countdown(startsAt - t), e.seriesName, e.routeName,
                car and ("Your car: #%d %s RB15 at the start. "):format(car.number, sl.teamName) or ""))
            toast(pid, { type = "info", title = string.upper(kind) .. " · " .. Entry.countdown(startsAt - t), message = e.routeName .. " — best run counts", icon = "NCM", durationMs = 8000 })
        end
    end
    if #gridCars > 0 then
        rec.gridCars = true; plan.gridCarsSpawned = true; plan.gridCarsSession = sessionId
        TriggerEvent("ncm:gridCars", sessionId, gridCars)
    end
    log("FORMED session=%s event=%s kind=%s %d/%d entrants=%d gates=%d cars=%d starts in %s%s", sessionId, e.eventId, kind, spec.index or 1, spec.of or 1,
        #slots, #gates, #gridCars, Entry.countdown(startsAt - t), order and (" grid from " .. tostring(spec.gridFrom)) or "")
    publish(rec, t)
    return rec
end

--- Start an event's plan: the format's sessions, the first one at the event's start time.
local function formPlan(e, t)
    if practices[e.eventId] then NcmRace.practiceClose(e.eventId, t, "session_forming") end
    local specs = Format.plan(e.formatId or "sprint", { gapSec = setting("sessionGapSec", 90), lengthM = e.distanceM })
    local plan = { formatId = e.formatId or "sprint", specs = specs, i = 1, sessionIds = {}, results = {}, e = e }
    plans[e.eventId] = plan
    local windows = {}
    for _, sp in ipairs(specs) do if sp.windowSec then windows[#windows + 1] = ("%s %d min"):format(sp.kind, math.floor(sp.windowSec / 60)) end end
    log("PLAN event=%s format=%s sessions=%d route=%d m%s", e.eventId, plan.formatId, #specs, math.floor(tonumber(e.distanceM) or 0), #windows > 0 and (" | " .. table.concat(windows, ", ")) or "")
    if e.class == "organized" then TriggerEvent("ncm:venueDress", e.eventId) end
    local rec = formSession(plan, specs[1], t, e.startsAt)
    if not rec then plans[e.eventId] = nil; return nil end
    return rec
end

--- Hand the field's cars back once a plan is over (after the result hold, or on abort).
local function releaseGridCars(plan, reason)
    if not plan.gridCarsSpawned then return end
    plan.gridCarsSpawned = false
    TriggerEvent("ncm:gridCarsRelease", plan.gridCarsSession, reason)
end

-- ---------------------------------------------------------------------------------------------
--- The machine this driver raced, and HOW WELL WE KNOW IT (L124 A4). Returns three values ready for the
--- insert: assetId (or "" for the NULLIF) and attributionBasis. There is no third value -- a team car is
--- a car (L126), so WHICH machine and HOW WELL WE KNOW IT are the only facts.
---
--- `recorded` is only ever claimed when the machine was observed under the driver at green. Everything else
--- is `unknown`, deliberately: a result with no machine is a gap in the record, and a gap must never be
--- dressed up as a fact. The core validator refuses the combinations that would be lies.
--- The machine this driver is racing. Once a session has gone green the LATCH is authoritative, including
--- when it holds nil -- "they started in no asset" is an answer, not a missing value. Sessions that never go
--- green (practice, time trial) have no latch, so the machine they are sitting in now is the machine they set
--- the lap in.
local function machineFor(rec, driverId)
    if not driverId then return nil end
    if rec and rec.machineOf then return rec.machineOf[driverId] end
    local pid = rec and rec.playerOf and rec.playerOf[driverId]
    return pid and seatedByPid[pid] or nil
end

--- Asset, basis, and the configuration that asset was in at GREEN. The third value fills
--- `session_result.configuration_ref`, reserved unwritten since migration 024 because there was no record
--- for it to name; migration 031 built one. It is latched, never read live -- see the GREEN handler.
---
--- All three degrade to unknown independently: a result may name a machine whose configuration was not
--- readable, and that is a better row than one that guesses.
local function attribution(rec, driverId)
    local assetId = machineFor(rec, driverId)
    local basis = assetId and "recorded" or "unknown"
    local ok, why = NcmCore.get("vocabulary.provenance").validateAttribution({ assetId = assetId, basis = basis })
    if not ok then
        -- Never write an attribution core refuses; record the gap and say why.
        log("attribution refused driver=%s: %s", tostring(driverId), tostring(why))
        return "", "unknown", ""
    end
    -- Core validates the shape so a malformed id cannot reach a CHAR(36) column; a refusal means unknown,
    -- and the empty string is the NULLIF sentinel the INSERTs already use.
    local cfg = rec and rec.configOf and rec.configOf[driverId] or nil
    if cfg ~= nil then cfg = NcmCore.get("competition.machine_knowledge").configurationRef(cfg) end
    return assetId or "", basis, cfg or ""
end

-- Completion: persist, settle (zero eddies), announce
-- ---------------------------------------------------------------------------------------------
local function complete(rec, results, reason, t)
    rec.results = results
    rec.completeReason = reason
    rec.doneAt = t
    local s = rec.s
    local plan = rec.plan
    plan.results[#plan.results + 1] = { kind = rec.kind, sessionId = s.sessionId, results = results }
    -- Economy v1 owns result + payout atomicity. Attribution is resolved here because race.lua owns the GREEN
    -- latch; the money host receives explicit facts and never guesses which Machine produced a result.
    for _, r in ipairs(results) do
        r._assetId, r._basis, r._configurationRef = attribution(rec, r.driverId)
    end
    local settlements, settlementWhy = NcmEconomy.settle(rec, results, reason, t)
    if not settlements then
        log("ECONOMY SETTLEMENT FAILED session=%s: %s", s.sessionId, tostring(settlementWhy))
        -- The operation is idempotent, so retry the complete transaction rather than writing compensations.
        CreateThread(function()
            for attempt = 1, 3 do
                Wait(attempt * 1000)
                local retry, why = NcmEconomy.settle(rec, results, reason, t)
                if retry then settlements = retry; log("economy settlement recovered session=%s attempt=%d", s.sessionId, attempt); return end
                log("economy retry failed session=%s attempt=%d: %s", s.sessionId, attempt, tostring(why))
            end
        end)
    end
    -- Schema 043: the conditions the session was driven in, for Paddock calibration (doc 44 §7).
    if NcmWeather and NcmWeather.stamp then
        local sid = s.sessionId
        CreateThread(function() Wait(2000); NcmWeather.stamp("session", sid, s.greenAt or t) end)
    end
    if NcmTelemetry and NcmTelemetry.flush then pcall(NcmTelemetry.flush, rec, true) end
    if rec.kind == "race" then
        if NcmRecords and NcmRecords.refresh then pcall(NcmRecords.refresh) end
        if NcmProgression and NcmProgression.apply then pcall(NcmProgression.apply, rec, results, t) end
    end
    -- L67 / IDEA-001: a race with a field of one is a TIME TRIAL. It is real, recorded and classified, but it is
    -- not won -- so it is never announced as a position. Core owns the predicate so host and rules agree.
    local timeTrial = (rec.kind == "race") and Core.get("driver.progression").isTimeTrial({ fieldSize = #results })
    -- **A time trial gets a ghost; a contested race does not** (`L166`). A time trial IS the solo activity
    -- practice is, under a different name and on the race kernel -- so the same rule applies to it. In a
    -- contested race a ghost would be clutter among real competitors and could be read as another entrant,
    -- which is the one presentation mistake this feature must not make.
    --
    -- Claimed at completion rather than at the finish gate because `timeTrial` is only knowable from the
    -- finished field, and core owns that predicate. The client's buffer survives the end of its run, so an
    -- invitation that arrives now still finds the poses.
    if timeTrial and NcmGhost then
        for _, r in ipairs(results) do
            local pid = rec.playerOf and rec.playerOf[r.driverId] or nil
            -- The machine was latched at GREEN, which is this session's start line; `attribution` reads that
            -- latch rather than the seat now.
            local assetId, _, configurationRef = attribution(rec, r.driverId)
            -- **Refuse loudly rather than claim something unkeyable.** A claim with no route produced exactly
            -- one symptom -- no ghost appeared - and the actual cause was a missing field three functions away.
            -- The upload would have been refused by the manifest, but only if a client had recorded anything to
            -- upload, and the same missing field stopped that too. So the refusal belongs here, first.
            if r.state == "finished" and (rec.routeId == nil or rec.routeId == "") then
                log("ghost NOT claimed for driver=%s: this session has no routeId (event=%s name=%s)",
                    r.driverId, tostring(rec.eventId), tostring(rec.routeName))
            elseif r.state == "finished" and r.finishAt and s.greenAt and pid then
                NcmGhost.claim(r.driverId, {
                    sessionId = s.sessionId, eventId = rec.eventId, routeId = rec.routeId or "",
                    disciplineId = rec.disciplineId, rulesetId = rec.rulesetId, classId = rec.classId,
                    laps = (rec.course and rec.course.laps) or 1,
                    startedAt = s.greenAt, finishedAt = r.finishAt,
                    elapsedMs = math.floor((r.totalSec or 0) * 1000),
                    incidentMs = math.floor((r.incidentSec or 0) * 1000),
                    rawMs = math.floor((r.finishAt - s.greenAt) * 1000),
                    assetId = assetId ~= "" and assetId or nil,
                    configurationRef = configurationRef ~= "" and configurationRef or nil,
                    gatesDone = r.progress or 0, gatesTotal = r.gatesTotal or #s.gates,
                })
                TriggerClientEvent("ncm:ghost.invite", pid, {
                    routeId = rec.routeId or "", elapsedMs = math.floor((r.totalSec or 0) * 1000),
                    incidentMs = math.floor((r.incidentSec or 0) * 1000), kind = "time_trial",
                })
                log("time trial ghost invited driver=%s route=%s %dms", r.driverId, tostring(rec.routeId),
                    math.floor((r.totalSec or 0) * 1000))
            end
        end
    end
    local lines = {}
    for _, r in ipairs(results) do
        local what
        if rec.kind ~= "race" then
            what = r.bestSec and ("best " .. fmtTime(r.bestSec) .. (r.gapSec and (" (+" .. string.format("%.3f", r.gapSec) .. ")") or "")) or "no time"
        else
            what = r.state == "finished" and (fmtTime(r.correctedSec or r.totalSec) .. (r.gapSec and (" (+" .. string.format("%.3f", r.gapSec) .. ")") or "")
                    .. (r.jumpStart and " JS+5" or "") .. ((r.incidentSec or 0) > 0 and (" +" .. string.format("%.1f", r.incidentSec) .. " inc") or ""))
                or (r.state == "dnf" and ("DNF " .. tostring(r.dnfReason) .. " " .. tostring(r.progress) .. "/" .. tostring(r.gatesTotal)))
                or (r.state == "dsq" and "DSQ") or "DNS"
        end
        if timeTrial then
            lines[#lines + 1] = ("TIME TRIAL %s %s"):format(tostring(r.display), what)
        else
            lines[#lines + 1] = ("P%d %s %s"):format(r.position, tostring(r.display), what)
        end
    end
    -- QA G1/A2/G4: announce the finished session's own numbers. Facts only; nothing here reads the answer,
    -- and with the QA flag off the event is simply unobserved. See wp/QA_INSTRUMENTATION.md.
    pcall(TriggerEvent, "ncm:race.completed", {
        sessionId = s.sessionId, eventId = rec.eventId, kind = rec.kind,
        fieldSize = type(results) == "table" and #results or 0, results = results,
    })
    log("COMPLETE session=%s kind=%s%s reason=%s | %s", s.sessionId, rec.kind,
        timeTrial and " (time trial: field of one)" or "", reason, table.concat(lines, " | "))
    -- what comes next in the plan?
    local nextSpec = plan.specs[#plan.results + 1]
    if nextSpec then
        rec.nextSpec = nextSpec
        -- the gap covers the drive from this session's finish back to the next start (P50), whole minutes
        local g = rec.s and rec.s.gates or {}
        local travelM = (#g >= 2) and math.sqrt((g[#g].x - g[1].x) ^ 2 + (g[#g].y - g[1].y) ^ 2) or 0
        rec.nextAt = t + Format.gapFor(travelM, nextSpec.gapSec or 90)
        local how = nextSpec.gridFrom == "quali" and "grid from qualifying" or (nextSpec.gridFrom == "reversed_top_n" and ("top %d reversed"):format(nextSpec.n or 8)) or "grid in order"
        for _, pid in pairs(rec.playerOf) do
            tell(pid, ("Next: %s%s in %s — %s."):format(nextSpec.kind, nextSpec.kind == "race" and (" " .. (nextSpec.ordinal or "")) or "", Entry.countdown(rec.nextAt - t), how))
        end
    end
    for _, r in ipairs(results) do
        local pid = rec.playerOf[r.driverId]
        if pid then
            tell(pid, ("%s: %s · %s — %s"):format(rec.kind == "race" and "Result" or (rec.kind == "quali" and "Qualifying" or "Practice"), rec.seriesName or "", rec.routeName or "", lines[r.position]))
            local receipt = settlements and settlements[r.driverId] or nil
            if receipt then tell(pid, "Statement: " .. receipt.text .. " · BALANCE €$" .. tostring(receipt.balance)) end
            toast(pid, {
                type = r.position == 1 and (r.state == "finished" or r.state == "timed") and "success" or "info",
                title = timeTrial and "TIME TRIAL COMPLETE" or (("%s · P%d of %d"):format(rec.kind == "race" and "RESULT" or string.upper(rec.kind), r.position, #results)),
                message = (receipt and ((receipt.net >= 0 and "+€$" or "-€$") .. math.abs(receipt.net) .. " · balance €$" .. receipt.balance))
                    or ((rec.routeName or "") .. " · " .. ((r.state == "finished" or r.state == "timed") and fmtTime(r.correctedSec or r.totalSec or r.bestSec) or string.upper(r.state))),
                icon = "NCM", durationMs = 15000,
            })
            if rec.kind == "race" then
                pcall(function()
                    local bag = Open77.state.player(pid)
                    bag:set("ncmResult", { sessionId = s.sessionId, position = r.position, of = #results, state = r.state, totalSec = r.totalSec, correctedSec = r.correctedSec, incidentSec = r.incidentSec, gapSec = r.gapSec, routeName = rec.routeName, settlement = receipt, at = t })
                    if not nextSpec then pcall(function() bag:clear("ncmEntry") end) end
                end)
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------------------------------
local function handle(rec, events, t)
    local s = rec.s
    for _, e in ipairs(events) do
        if e.type == "phase" then
            log("session=%s phase -> %s%s", s.sessionId, e.phase, e.reason and (" (" .. e.reason .. ")") or "")
            pcall(function() MySQL.update.await("UPDATE session SET state = ? WHERE session_id = ?", { e.phase == "open" and "running" or e.phase, s.sessionId }) end)
            if e.phase == "gridded" and not (s.rules and s.rules.hold) then
                for id, pid in pairs(rec.playerOf) do
                    local r = s.entrants[id]
                    if r and r.state == "ready" then tell(pid, "Hold your position. Lights in " .. Entry.countdown(s.startsAt - t - s.rules.countdownSec) .. ".") end
                end
            elseif e.phase == "open" then
                for _, pid in pairs(rec.playerOf) do
                    tell(pid, ("%s is open for %s. Cross the start to begin a run."):format(rec.kind == "quali" and "Qualifying" or "Practice", Entry.countdown((e.closesAt or t) - t)))
                end
            end
        elseif e.type == "hold" then
            log("session=%s HOLD %d/%d at the mark, release by %.0f", s.sessionId, e.ready, e.total, e.until_ or 0)
            for _, pid in pairs(rec.playerOf) do
                tell(pid, ("Holding for the field: %d of %d on the grid. Lights when %d%% are in, or in %s."):format(e.ready, e.total, math.floor((s.rules.holdReleasePct or 0.75) * 100 + 0.5), Entry.countdown((e.until_ or t) - t)))
            end
        elseif e.type == "light" then
            -- The client renders the light tree from the synced clock (race HUD page); nothing to send.
        elseif e.type == "green" then
            log("session=%s GREEN at %.3f", s.sessionId, e.at)
            -- Latch the machine each driver actually went racing in. At GREEN rather than at settlement,
            -- because the car is guaranteed to be under them here and may not be afterwards.
            rec.machineOf = {}
            -- The CONFIGURATION each machine raced in, latched in the same breath and for the same reason.
            -- `machine_configuration` is an append-only revision chain and `machine_configuration_current`
            -- moves the moment a part is fitted, so reading the head at settlement would attribute the race
            -- to whatever the car became afterwards. The question this column answers is *what was it when
            -- it set that time*, and this is the only moment that can be known.
            rec.configOf = {}
            local named, anon, configured = 0, 0, 0
            for driverId, pid in pairs(rec.playerOf or {}) do
                local assetId = seatedByPid[pid]
                rec.machineOf[driverId] = assetId
                if assetId then named = named + 1 else anon = anon + 1 end
                if assetId and NcmComponents and NcmComponents.currentConfiguration then
                    local ok, cfg = pcall(NcmComponents.currentConfiguration, assetId)
                    -- A failed read leaves this UNKNOWN. It must never fall through to another machine's
                    -- configuration or to the current head.
                    rec.configOf[driverId] = ok and cfg or nil
                    if rec.configOf[driverId] then configured = configured + 1 end
                end
            end
            log("session=%s machines at green: %d attributed, %d unknown, %d with a configuration",
                s.sessionId, named, anon, configured)
            -- Deferred by one tick so the kernel is not re-entered while it is still emitting green.
            CreateThread(function() Wait(0); pcall(NcmRace.enforceEnteredMachine, rec, t) end)
        elseif e.type == "dns" then
            log("session=%s DNS driver=%s reason=%s", s.sessionId, e.driverId, tostring(e.reason))
            tell(rec.playerOf[e.driverId], "You did not start: " .. tostring(e.reason) .. ".")
        elseif e.type == "suspended" then
            log("session=%s SUSPENDED driver=%s reason=%s grace until %.0f", s.sessionId, e.driverId, tostring(e.reason), e.until_ or 0)
        elseif e.type == "resumed" then
            log("session=%s RESUMED driver=%s progress=%d", s.sessionId, e.driverId, e.progress or 0)
            local pid = rec.playerOf[e.driverId]
            tell(pid, ("Welcome back: you are still racing (gate %d/%d). Go."):format(e.progress or 0, #s.gates))
            toast(pid, { type = "success", title = "BACK IN THE RACE", message = ("gate %d/%d - the clock never stopped"):format(e.progress or 0, #s.gates), icon = "NCM", durationMs = 6000 })
        elseif e.type == "penalty" then
            log("session=%s PENALTY driver=%s +%ss reason=%s", s.sessionId, e.driverId, tostring(e.seconds), tostring(e.reason))
            local pid = rec.playerOf[e.driverId]
            tell(pid, ("Race control: +%d s penalty (%s)."):format(e.seconds, tostring(e.reason)))
            toast(pid, { type = "error", title = ("PENALTY +%d s"):format(e.seconds), message = tostring(e.reason), icon = "RC", durationMs = 6000 })
        elseif e.type == "incident" then
            local mult = 2 ^ ((e.band or 1) - 1)
            log("session=%s INCIDENT driver=%s kind=%s band=%s +%.1fs other=%s total=%.1fs (#%d)", s.sessionId, e.driverId, tostring(e.kind), tostring(e.band), e.seconds or 0, tostring(e.other), e.incidentSec or 0, e.count or 0)
            local pid = rec.playerOf[e.driverId]
            tell(pid, ("Incident x%d (%s): +%.1f s on your time. Total +%.1f s."):format(mult, tostring(e.kind), e.seconds or 0, e.incidentSec or 0))
            toast(pid, { type = "error", title = ("INCIDENT x%d · +%.1f s"):format(mult, e.seconds or 0), message = ("%s contact · total +%.1f s"):format(tostring(e.kind), e.incidentSec or 0), icon = "NCM", durationMs = 5000 })
            pcall(function()
                -- IDEA-236: a machine's biography needs what it was INVOLVED in, not only what it finished.
                -- Both sides are attributed where known: contact is a fact about two machines.
                MySQL.insert.await("INSERT INTO incident (session_id, ncm_driver_id, other_driver_id, kind, band, delta_v, seconds, x, y, z, t, attributed, asset_id, other_asset_id) VALUES (?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''))",
                    { s.sessionId, e.driverId, e.other or "", (e.kind == "formation_speed") and "formation" or (e.kind or "car"), e.band or 1, e.dv or 0, e.seconds or 0, e.x or 0, e.y or 0, e.z or 0, t, e.other and "both" or "self",
                      machineFor(rec, e.driverId) or "", machineFor(rec, e.other) or "" })
            end)
        elseif e.type == "dsq" then
            log("session=%s DSQ driver=%s reason=%s", s.sessionId, e.driverId, tostring(e.reason))
            local pid = rec.playerOf[e.driverId]
            tell(pid, ("Race control: disqualified (%s)."):format(tostring(e.reason)))
            toast(pid, { type = "error", title = "DISQUALIFIED", message = tostring(e.reason), icon = "RC", durationMs = 10000 })
        elseif e.type == "dnf" then
            log("session=%s DNF driver=%s reason=%s", s.sessionId, e.driverId, tostring(e.reason))
        elseif e.type == "left" then
            log("session=%s LEFT driver=%s reason=%s", s.sessionId, e.driverId, tostring(e.reason))
        elseif e.type == "complete" then
            if rec.practice then NcmRace.practiceComplete(rec, e.results, e.reason or "complete", t) else complete(rec, e.results, e.reason or "complete", t) end
        end
    end
end
NcmRace.handle = handle
NcmRace.publish = publish

-- ---------------------------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------------------------
local function gridCheck(rec)
    local s = rec.s
    if rec.kind ~= "race" or rec.lightsForced then return end   -- ncm.lights now: the marks stand wherever the cars are
    if s.phase ~= "forming" and s.phase ~= "gridded" then return end
    local pmap = playersByDriver()
    for driverId, pid in pairs(pmap) do rec.playerOf[driverId] = pid end
    for _, sl in ipairs(rec.slots) do
        local pid = rec.playerOf[sl.driverId]
        local pos = positionOf(pid)
        local at = pos ~= nil and Routes.planarDistance(pos, sl) <= sl.radiusM
        local r = s.entrants[sl.driverId]
        if r and (r.state == "entered" or r.state == "ready") and r.atMark ~= at then
            Race.mark(s, sl.driverId, at)
            log("session=%s driver=%s %s the mark (P%d)", s.sessionId, sl.driverId, at and "AT" or "LEFT", sl.slot)
            if at then toast(pid, { type = "success", title = "ON YOUR MARK · P" .. sl.slot, message = "Hold here for the lights.", icon = "NCM", durationMs = 5000 }) end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Chauffeur pickup (M7.5a, P24): at T-pickupLead every registered, connected driver of an organized
-- event gets a ride to the venue drop-off. ncm_world drives the cars; this side decides who and where.
-- ---------------------------------------------------------------------------------------------
local pickups = {}   -- eventId -> { dropoff, dispatched = { [driverId] = true } }

local function dropoffFor(e, entrantCount)
    local ok, v = pcall(function() return GlobalState.ncmVenue end)
    if ok and type(v) == "table" and type(v.paddock) == "table" then return v.paddock end
    local route = Routes.resolve(e.routeId, e.routeName)
    if not route then return nil end
    local gates = Gates.build(route)
    if not gates or not gates[1] then return nil end
    return Grid.dropoffPosition(gates[1], entrantCount)
end

--- Dispatch rides for `driverIds` (nil = every registered driver not yet dispatched) of an organized event.
--- The chauffeur is TW1 presentation, not race-weekend infrastructure (P52, owner QA batch 2): rides go out only
--- while the world runs in TW1 mode (`/ncm.au tw1 on`, published as GlobalState.ncmVenue.tw1).
local function chauffeurOn()
    local ok, v = pcall(function() return GlobalState.ncmVenue end)
    return ok and type(v) == "table" and v.tw1 == true
end

function NcmRace.pickup(e, driverIds, t)
    t = t or now()
    if e.class ~= "organized" then return 0 end
    local n = 0
    for _ in pairs(e.entries or {}) do n = n + 1 end
    local st = pickups[e.eventId]
    if not st then
        local d = dropoffFor(e, n)
        if not d then log("pickup %s: no drop-off (route unresolved)", e.eventId); return 0 end
        st = { dropoff = d, dispatched = {} }
        pickups[e.eventId] = st
        TriggerEvent("ncm:venueDress", e.eventId)   -- spectators and barriers are in place before the first arrival
    end
    local pmap = playersByDriver()
    local riders = {}
    local wanted = driverIds
    if not wanted then
        wanted = {}
        for driverId, en in pairs(e.entries or {}) do if en.state == "registered" then wanted[#wanted + 1] = driverId end end
    end
    for _, driverId in ipairs(wanted) do
        local en = e.entries[driverId]
        local pid = pmap[driverId]
        if en and en.state == "registered" and pid and not st.dispatched[driverId] then
            st.dispatched[driverId] = true
            local team = en.teamId and Teams.byId(en.teamId)
            local car = en.teamId and Teams.carForSeat(en.teamId, en.seatIndex)
            riders[#riders + 1] = {
                driverId = driverId, playerId = pid, teamId = en.teamId, teamName = team and team.name or "NCX",
                teamShort = team and team.short, colour = team and team.colour,
                number = car and car.number, seatIndex = en.seatIndex, venueName = e.venue and e.venue.name or e.routeName,
                startsAt = e.startsAt,
            }
        end
    end
    if #riders > 0 then
        TriggerEvent("ncm:pickup", e.eventId, {
            dropoff = st.dropoff, speed = setting("pickupSpeedMps", 18), venueName = e.venue and e.venue.name or e.routeName,
            routeName = e.routeName, startsAt = e.startsAt, riders = riders,
        })
        log("PICKUP event=%s riders=%d drop-off %.1f,%.1f starts in %s", e.eventId, #riders, st.dropoff.x, st.dropoff.y, Entry.countdown(e.startsAt - t))
    end
    return #riders
end

function NcmRace.pickupStarted(eventId) return pickups[eventId] ~= nil end

--- A driver who registers or (re)connects after the rides went out gets one straight away.
function NcmRace.pickupLate(e, driverId)
    if not chauffeurOn() then return 0 end
    if not pickups[e.eventId] then return 0 end
    return NcmRace.pickup(e, { driverId })
end

AddEventHandler("onPlayerReady", function(playerId)
    CreateThread(function()
        Wait(2000)
        local d = NcmCalendar.resolveDriver(tonumber(playerId) or 0)
        if not d then return end
        for _, e in pairs(NcmCalendar.events or {}) do
            if pickups[e.eventId] and e.entries and e.entries[d.ncmDriverId] and not byEvent[e.eventId] then
                pickups[e.eventId].dispatched[d.ncmDriverId] = nil
                NcmRace.pickupLate(e, d.ncmDriverId)
            end
        end
    end)
end)

local function retirePlan(plan, reason)
    releaseGridCars(plan, reason)
    pickups[plan.e.eventId] = nil
    TriggerEvent("ncm:pickupRelease", plan.e.eventId)
    if plan.e.class == "organized" then TriggerEvent("ncm:venueUndress", plan.e.eventId, reason) end
    plans[plan.e.eventId] = nil
    byEvent[plan.e.eventId] = "done"
end

local function tick()
    local t = now()
    -- Inside the lead (before the grid forms): dress the venue; rides go out only in TW1 mode (P52).
    for eid, e in pairs(NcmCalendar.events or {}) do
        if e.class == "organized" and not pickups[eid] and not byEvent[eid] and e.state ~= "cancelled" and e.state ~= "closed"
            and e.startsAt - t <= setting("pickupLeadSec", 300) and e.startsAt > t then
            if chauffeurOn() then NcmRace.pickup(e, nil, t) else TriggerEvent("ncm:venueDress", eid) end
            pickups[eid] = pickups[eid] or { dropoff = nil, dispatched = {} }
        end
    end
    -- Form the first session of events about to start.
    for eid, e in pairs(NcmCalendar.events or {}) do
        if not byEvent[eid] and e.state ~= "cancelled" and e.state ~= "closed" and e.startsAt - t <= setting("raceFormAtSec", 60) and e.startsAt > t - 5 then
            local n = 0
            for _, en in pairs(e.entries or {}) do if en.state ~= "interested" and en.state ~= "withdrawn" then n = n + 1 end end   -- interest alone is not a grid
            if n > 0 then formPlan(e, t) elseif practices[eid] then NcmRace.practiceClose(eid, t, "no_entrants") end
        end
    end
    -- Advance sessions. (Mutations of `sessions` are deferred: pairs() must not see keys change under it.)
    local toForm, toRetire = {}, {}
    for sid, rec in pairs(sessions) do
        local s = rec.s
        if s.phase ~= "complete" then
            gridCheck(rec)
            if s.phase == "running" or s.phase == "finishing" or s.phase == "open" then
                local pmap = playersByDriver()
                for driverId, pid in pairs(pmap) do
                    rec.playerOf[driverId] = pid
                    local r = s.entrants[driverId]
                    if r and r.state == "suspended" then
                        local ev2 = rec.kernel.resume(s, driverId, t)
                        if ev2 then
                            handle(rec, ev2, t)
                            TriggerEvent("ncm:driverResumed", pid, rec.lastPos[driverId])
                        end
                    end
                end
                -- Track where every racer is (server truth; telemetry refines it between ticks).
                for driverId, pid in pairs(rec.playerOf) do
                    local r = s.entrants[driverId]
                    if r and (r.state == "racing" or rec.kind ~= "race") then
                        local pos = positionOf(pid)
                        if pos then
                            rec.lastPos[driverId] = { x = pos.x, y = pos.y, z = pos.z }
                            local g = s.gates[((r.run and r.run.progress) or r.progress or 0) + 1]
                            if g then rec.toNext[driverId] = math.floor(Routes.planarDistance(pos, g)) end
                            if NcmTelemetry and NcmTelemetry.serverSample then NcmTelemetry.serverSample(rec, driverId, pos, t) end
                        end
                    end
                end
                if NcmTelemetry and NcmTelemetry.scan and not (NcmScenario and NcmScenario.overrides.incidents == false) then
                    local ok, err = pcall(NcmTelemetry.scan, rec, t)
                    if not ok then log("incident scan error: %s", tostring(err)) end
                end
            end
            local events = rec.kernel.step(s, t)
            if #events > 0 then handle(rec, events, t) end
            publish(rec, t)
        elseif rec.nextSpec then
            if t >= rec.nextAt then toForm[#toForm + 1] = { sid = sid, rec = rec } else publish(rec, t) end
        elseif rec.doneAt and t - rec.doneAt > setting("raceResultHoldSec", 30) then
            toRetire[#toRetire + 1] = { sid = sid, rec = rec }
        end
    end
    for _, x in ipairs(toRetire) do
        retirePlan(x.rec.plan, "session_retired")
        dropFromEntrants(x.rec)
        sessions[x.sid] = nil
        clearPublication()
        log("session=%s retired", x.sid)
    end
    for _, x in ipairs(toForm) do
        dropFromEntrants(x.rec)
        sessions[x.sid] = nil
        local nextRec = formSession(x.rec.plan, x.rec.nextSpec, t, t + setting("raceFormAtSec", 60))
        if not nextRec then retirePlan(x.rec.plan, "no_entrants"); clearPublication() end
    end
end

function NcmRace.hasSession(eventId)
    local sid = byEvent[eventId]
    return sid ~= nil and sid ~= "none" and sessions[sid] ~= nil
end

-- KB-37: a driver can only be in one session at a time. Nothing used to say so, so an event whose start time
-- arrived while its entrants were racing something else formed without them and classified them DNS -- permanent
-- history (L74c) for a race they could not physically attend. Returns the session and event holding them, or nil.
local LIVE_ENTRANT = { entered = true, ready = true, racing = true, suspended = true }
function NcmRace.busySession(driverId)
    if not driverId then return nil end
    for sid, rec in pairs(sessions) do
        if rec.s and rec.s.phase ~= "complete" then
            local en = rec.s.entrants and rec.s.entrants[driverId]
            if en and LIVE_ENTRANT[en.state] then return sid, rec.eventId, rec.kind end
        end
    end
    return nil
end

-- Events that already had a session (this run or a previous one) never form again.
local function loadSessionHistory()
    local ok, rows = pcall(function()
        -- practice sessions are not "raced" (P48): an event with only a practice row must still form its plan
        return MySQL.query.await("SELECT event_id FROM session WHERE starts_at >= ? AND kind <> 'practice'", { math.floor(now() - 7200) }) or {}
    end)
    if not ok then log("session history unavailable: %s", tostring(rows)); return end
    for _, r in ipairs(rows) do if not byEvent[r.event_id] then byEvent[r.event_id] = "done" end end
    log("session history: %d event(s) already raced", #rows)
end

function NcmRace.raced(eventId)
    local sid = byEvent[eventId]
    return sid == "done" or (sid ~= nil and sessions[sid] ~= nil)
end

function NcmRace.forget(eventId)
    if byEvent[eventId] ~= nil and not sessions[byEvent[eventId]] then byEvent[eventId] = nil end
end

--- Race control entry point: action = "penalty" (value = seconds) | "dsq".
function NcmRace.control(sessionId, action, driverId, value, reason)
    local rec = sessions[sessionId]
    if not rec then return nil, "unknown_session" end
    local t = now()
    local events, err
    if action == "penalty" then
        events, err = rec.kernel.penalty(rec.s, driverId, tonumber(value), reason, t)
    elseif action == "dsq" then
        events, err = rec.kernel.disqualify(rec.s, driverId, reason, t)
    else
        return nil, "unknown_action"
    end
    if not events then return nil, err end
    handle(rec, events, t)
    local more = rec.kernel.step(rec.s, t)
    if #more > 0 then handle(rec, more, t) end
    publish(rec, t)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Forfeit: leaving a race you have already started.
--
-- WITHDRAWN = entered but did not start. FORFEIT = started but did not finish. They are different acts on
-- different objects -- a withdrawal edits an entry row, a forfeit is a sporting fact about a session -- and
-- `NcmGuide.withdraw` refuses the second and points here.
--
-- Until now the only way out of a race that had gone wrong was to disconnect, which is how Hook came to be
-- recorded `dnf / disconnected` on 2026-09-23. The classification is the same either way; what was missing was
-- a way to say it on purpose. The kernel already models this exactly (`session.race.leave`: DNS before green,
-- DNF after), so this is a surface over an existing rule, not a new one.
--
-- The session itself is untouched for everyone else. Whether the race then ends is the kernel's ordinary
-- decision: if the forfeiting driver was the last one running, `step` completes it, as it would have on any
-- other retirement.
-- ---------------------------------------------------------------------------------------------
local FORFEIT_CONFIRM_S = 15
local forfeitAsked = {}          -- driverId -> server-clock deadline of the pending confirmation

--- Retire this driver from the session they are in. `confirmed` skips the two-step prompt (console/host use).
--- Returns true, or nil + reason ("not_racing" | "confirm" | kernel reason).
-- NOTE ON PLACEMENT: this lives below `local function handle` deliberately. Defined earlier it would
-- capture a GLOBAL `handle` (nil) instead of the local, fail at runtime, and be swallowed by the pcall
-- that calls it -- the fourth-plus instance of the Lua local-ordering defect in this codebase (KB-81a),
-- and one `luac -p` cannot see.
--- **You race the car you entered** (IDEA-312). Checked once, just after green.
---
--- Refuses only on an EXPLICIT contradiction: an entry that named a machine, and a driver demonstrably sitting
--- in a different one. An unknown seat is not a violation -- absence is not evidence, which is the lesson
--- KB-72 cost us when two gates demanded exact values from fields that might not exist.
---
--- A team entry names no machine **until M6 converts team cars into assets** -- that is a migration that has not
--- run yet, NOT a carve-out. Team machines are ordinary machine assets owned by an organization principal
--- (L126, L124 A2, IDEA-168), and when they carry an `assetId` this rule covers them unchanged.
function NcmRace.enforceEnteredMachine(rec, t)
    if not rec or not rec.machineOf or not rec.slotOf then return 0 end
    local out = 0
    for driverId, pid in pairs(rec.playerOf or {}) do
        local sl = rec.slotOf[driverId]
        local entered = sl and sl.enteredAsset or nil
        local fielded = rec.machineOf[driverId]
        if entered and fielded and entered ~= fielded then
            log("session=%s WRONG MACHINE driver=%s entered=%s fielded=%s -> refused start",
                rec.s.sessionId, driverId:sub(1, 8), entered:sub(1, 8), fielded:sub(1, 8))
            local events = rec.kernel.leave(rec.s, driverId, t, "wrong_machine")
            if events then
                handle(rec, events, t)
                out = out + 1
                if pid then
                    tell(pid, "You entered a different machine. A race is entered with one car, and that is the car that starts it.")
                    toast(pid, { type = "error", title = "WRONG MACHINE", message = "You did not start in the machine you entered.", icon = "NCM", durationMs = 9000 })
                end
            end
        end
    end
    if out > 0 then
        local more = rec.kernel.step(rec.s, t)
        if #more > 0 then handle(rec, more, t) end
        publish(rec, t)
    end
    return out
end

function NcmRace.forfeit(driverId, reason, confirmed)
    if not driverId then return nil, "not_racing" end
    local sid, eventId, kind = NcmRace.busySession(driverId)
    if not sid or kind == "practice" then return nil, "not_racing" end
    local rec = sessions[sid]
    if not rec then return nil, "not_racing" end
    local pid = rec.playerOf and rec.playerOf[driverId] or nil
    -- One keystroke should not end a race. Ask once; a second press inside the window commits.
    if not confirmed then
        local deadline = forfeitAsked[driverId]
        if not (deadline and now() < deadline) then
            forfeitAsked[driverId] = now() + FORFEIT_CONFIRM_S
            if pid then
                tell(pid, ("Forfeit %s? This retires you from the race and cannot be undone. Type /ncm.forfeit again within %ds to confirm."):format(
                    tostring(rec.routeName or "this session"), FORFEIT_CONFIRM_S))
            end
            return nil, "confirm"
        end
    end
    forfeitAsked[driverId] = nil
    local t = now()
    local started = rec.s.phase == "running" or rec.s.phase == "finishing"
    local events, err = rec.kernel.leave(rec.s, driverId, t, reason or "forfeit")
    if not events then return nil, err or "already_classified" end
    handle(rec, events, t)
    local more = rec.kernel.step(rec.s, t)
    if #more > 0 then handle(rec, more, t) end
    publish(rec, t)
    if pid then
        tell(pid, started and ("Retired from %s. Recorded DNF."):format(tostring(rec.routeName or ""))
                          or ("Left %s before the start. Recorded DNS."):format(tostring(rec.routeName or "")))
        toast(pid, { type = "warning", title = started and "FORFEIT · DNF" or "FORFEIT · DNS",
                     message = tostring(rec.routeName or "") .. " · you are out of this session", icon = "NCM", durationMs = 8000 })
    end
    log("FORFEIT driver=%s session=%s event=%s phase=%s -> %s", driverId:sub(1, 8), sid:sub(1, 8), tostring(eventId),
        rec.s.phase, started and "dnf" or "dns")
    return true
end

--- Incident from the telemetry scan: apply to the kernel and announce.
function NcmRace.incident(rec, driverId, inc, t)
    local events = rec.kernel.incident and rec.kernel.incident(rec.s, driverId, inc, t)
    if events then handle(rec, events, t) end
    return events
end

--- End one event's live session(s) and its plan now (host kit: scenario stop/restart). Returns the count.
function NcmRace.abortEvent(eventId, reason)
    local t = now()
    local n = 0
    local plan = plans[eventId]
    for sid, rec in pairs(sessions) do
        if rec.eventId == eventId then
            if rec.practice then
                NcmRace.practiceClose(eventId, t, reason or "aborted")
            elseif rec.s.phase ~= "complete" then
                local events = rec.kernel.abort(rec.s, t, reason or "aborted")
                if events then handle(rec, events, t) end
                n = n + 1
            end
            rec.nextSpec = nil
            if sessions[sid] then dropFromEntrants(rec); sessions[sid] = nil end
        end
    end
    if plan then retirePlan(plan, reason or "aborted") end
    if NcmEconomy and NcmEconomy.refundEvent then
        local ok, refunded = pcall(NcmEconomy.refundEvent, eventId, reason or "aborted")
        if ok and (refunded or 0) > 0 then log("refunded %d paid entr(ies) for aborted event=%s", refunded, eventId) end
    end
    clearPublication()
    byEvent[eventId] = "done"
    return n
end

--- Host kit: lights now. Every entrant still in it counts as on their mark; the countdown starts on the next tick.
function NcmRace.lightsNow()
    local t = now()
    local n = 0
    for _, rec in pairs(sessions) do
        local s = rec.s
        if rec.kind == "race" and (s.phase == "forming" or s.phase == "gridded") then
            for id, r in pairs(s.entrants) do if r.state == "entered" or r.state == "ready" then Race.mark(s, id, true) end end
            rec.lightsForced = true
            s.startsAt = t + (s.rules.countdownSec or 5) + 1
            s.originalStartsAt = math.min(s.originalStartsAt or s.startsAt, s.startsAt)
            if s.phase == "forming" then s.phase = "gridded"; handle(rec, { { type = "phase", phase = "gridded" } }, t) end
            local events = rec.kernel.step(s, t)
            if #events > 0 then handle(rec, events, t) end
            publish(rec, t)
            n = n + 1
            for _, pid in pairs(rec.playerOf) do tell(pid, "Race control: lights now.") end
        end
    end
    return n
end

function NcmRace.abort(reason)
    local n = 0
    for _, rec in pairs(sessions) do
        if rec.s.phase ~= "complete" then
            local events = rec.kernel.abort(rec.s, now(), reason or "aborted")
            if events then handle(rec, events, now()); publish(rec, now()); n = n + 1 end
            rec.nextSpec = nil   -- an abort ends the whole plan
            if NcmEconomy and NcmEconomy.refundEvent then pcall(NcmEconomy.refundEvent, rec.eventId, reason or "aborted") end
        end
    end
    return n
end

RegisterCommand("ncm.race.abort", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    log("race.abort: %d session(s) aborted", NcmRace.abort("aborted"))
end, false)

function NcmRace.start()
    clearPublication()
    loadSessionHistory()
    CreateThread(function()
        while true do
            Wait(setting("raceTickMs", 1000))
            local ok, err = pcall(tick)
            if not ok then log("tick error: %s", tostring(err)) end
        end
    end)
    log("race control started: form at T-%ds, tick %d ms", setting("raceFormAtSec", 60), setting("raceTickMs", 1000))
end

-- ---------------------------------------------------------------------------------------------
-- Gate reports: the client says "I crossed gate k"; the server checks its own position read.
-- ---------------------------------------------------------------------------------------------
--- One gate crossing, whoever saw it: the client's own detection (ncm:gate) or the server's telemetry stream
--- (NcmRace.streamGate). `source` names the witness in the log; the kernel decides with the position given.
--- The machine under this driver right now, with the configuration it is in, as a fact the kernel can latch.
---
--- Read at the START LINE for a timed run. `machineFor` on its own answers "the latch, or the seat right now",
--- and for practice there is no latch -- so without this the car was only ever read when the SESSION closed,
--- and a driver who left practice, refitted and came back had their lap credited to the wrong machine.
local function machineNow(rec, driverId)
    local assetId = machineFor(rec, driverId)
    if not assetId then return nil end
    local cfg = nil
    if NcmComponents and NcmComponents.currentConfiguration then
        local ok, c = pcall(NcmComponents.currentConfiguration, assetId)
        -- A failed read leaves the configuration UNKNOWN; it must never fall through to another machine's.
        if ok then cfg = c end
    end
    local ref = nil
    if cfg ~= nil then ref = NcmCore.get("competition.machine_knowledge").configurationRef(cfg) end
    return { assetId = assetId, configurationRef = ref }
end

function NcmRace.reportGate(rec, pid, driver, gateIndex, pos, t, source)
    local res = rec.kernel.report(rec.s, { driverId = driver.ncmDriverId, gateIndex = tonumber(gateIndex), now = t, position = pos,
        machine = machineNow(rec, driver.ncmDriverId) })
    if NcmScenario and NcmScenario.traced[driver.ncmDriverId] then
        log("TRACE gate report player=%d gate=%s via=%s pos=%s ok=%s %s", pid or -1, tostring(gateIndex), tostring(source), pos and ("%.1f,%.1f"):format(pos.x, pos.y) or "?", tostring(res.ok), tostring(res.reason or ""))
    end
    if not res.ok then
        if source ~= "stream" or (res.reason ~= "out_of_order" and res.reason ~= "run_just_started" and res.reason ~= "not_open" and res.reason ~= "no_runs_left" and res.reason ~= "no_run") then
            log("gate refused player=%d driver=%s gate=%s via=%s reason=%s%s", pid or -1, driver.ncmDriverId, tostring(gateIndex), tostring(source), tostring(res.reason),
                res.distanceM and (" dist=" .. math.floor(res.distanceM) .. "m") or (res.expected and (" expected=" .. res.expected) or ""))
        end
        return res
    end
    local g = res.gate
    log("gate OK player=%d driver=%s gate=%d/%d %s via=%s%s%s%s", pid or -1, driver.ncmDriverId, g.index, #rec.s.gates, g.kind, tostring(source),
        res.penalty and " JUMP START +5s" or "", res.finished and (" FINISHED " .. fmtTime(res.runSec or res.totalSec)) or "", res.runStarted and " RUN START" or "")
    if res.rollingGreen then
        log("session=%s GREEN FLAG leader=%s at %.3f", rec.s.sessionId, tostring(res.rollingGreen.leader), res.rollingGreen.at)
        for _, p2 in pairs(rec.playerOf) do
            tell(p2, "GREEN FLAG — the race is on.")
            toast(p2, { type = "success", title = "GREEN FLAG", message = "race on — the clock started at the leader's green", icon = "NCM", durationMs = 4000 })
        end
    end
    if res.formationFault then
        log("session=%s FORMATION FAULT driver=%s %s +%.1fs", rec.s.sessionId, driver.ncmDriverId, tostring(res.formationFault), res.formationSec or 0)
        tell(pid, ("Formation fault (%s): +%.1f s on your time."):format(tostring(res.formationFault):gsub("_", " "), res.formationSec or 0))
        toast(pid, { type = "error", title = ("FORMATION · +%.1f s"):format(res.formationSec or 0), message = tostring(res.formationFault):gsub("_", " "), icon = "NCM", durationMs = 5000 })
        local p = positionOf(pid)
        pcall(function()
            MySQL.insert.await("INSERT INTO incident (session_id, ncm_driver_id, other_driver_id, kind, band, delta_v, seconds, x, y, z, t, attributed, asset_id) VALUES (?, ?, NULL, 'formation', ?, 0, ?, ?, ?, ?, ?, 'self', NULLIF(?, ''))",
                { rec.s.sessionId, driver.ncmDriverId, rec.s.rules.formationBand or 1, res.formationSec or 0, p and p.x or 0, p and p.y or 0, p and p.z or 0, t,
                  machineFor(rec, driver.ncmDriverId) or "" })
        end)
    elseif g.kind == "green" then
        toast(pid, { type = "info", title = "GREEN", message = "you're through the green — race on", icon = "NCM", durationMs = 2500 })
    elseif not (res.penalty or res.finished or res.runStarted) then
        -- an intermediate gate: the driver hears it (readable state, L63)
        toast(pid, { type = "info", title = ("GATE %d/%d"):format(g.index, #rec.s.gates), message = tostring(g.name or ""), icon = "NCM", durationMs = 2500 })
    end
    if res.penalty then
        tell(pid, "Jump start: +5 s.")
        toast(pid, { type = "error", title = "JUMP START", message = "+5 s penalty", icon = "NCM", durationMs = 4000 })
    elseif res.finished and rec.kind == "race" then
        toast(pid, { type = "success", title = "FINISH", message = fmtTime(res.totalSec), icon = "NCM", durationMs = 6000 })
    elseif res.finished then
        toast(pid, { type = "success", title = "RUN " .. fmtTime(res.runSec), message = "best " .. fmtTime(res.bestSec), icon = "NCM", durationMs = 5000 })
        if rec.practice then
            -- `incident_ms` used to read `r.run.incidentSec` HERE, one line after the kernel set `r.run = nil`
            -- at the finish -- so it was written as 0 for every practice run ever recorded. The kernel now
            -- returns the run's own incident time, which is the only place it still exists.
            local incidentMs = math.floor((res.incidentSec or 0) * 1000)
            local runMs = math.floor((res.runSec or 0) * 1000)
            pcall(function()
                local runId = MySQL.insert.await("INSERT INTO practice_run (server_id, event_id, route_id, ncm_driver_id, session_id, run_started_at, run_finished_at, run_ms, incident_ms, incident_count, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    { serverId(), rec.eventId, rec.routeId or "", driver.ncmDriverId, rec.s.sessionId,
                      res.startedAt, res.finishedAt, runMs, incidentMs, 0, math.floor(t) })
                if runId and NcmWeather and NcmWeather.stamp then NcmWeather.stamp("practice", runId, res.startedAt or t) end   -- schema 043
            end)
            -- What the SERVER saw, offered to the ghost host. The client may now upload the poses for this
            -- lap and nothing else: every number a stored ghost carries comes from here, not from the client.
            if NcmGhost and res.improved then
                NcmGhost.claim(driver.ncmDriverId, {
                    sessionId = rec.s.sessionId, eventId = rec.eventId, routeId = rec.routeId or "",
                    disciplineId = rec.disciplineId, rulesetId = rec.rulesetId, classId = rec.classId,
                    laps = 1, startedAt = res.startedAt, finishedAt = res.finishedAt,
                    elapsedMs = runMs, incidentMs = incidentMs,
                    rawMs = math.floor((res.rawSec or 0) * 1000),
                    assetId = res.machine and res.machine.assetId or nil,
                    configurationRef = res.machine and res.machine.configurationRef or nil,
                    gatesDone = #rec.s.gates, gatesTotal = #rec.s.gates,
                })
                TriggerClientEvent("ncm:ghost.invite", pid, {
                    routeId = rec.routeId or "", elapsedMs = runMs, incidentMs = incidentMs,
                    record = res.machine and res.machine.assetId and NcmGhost.recordFor(res.machine.assetId) or nil,
                })
            end
            local board, timed, mine = Practice.leaderboard(rec.s), 0, nil
            for _, row in ipairs(board) do if row.timed then timed = timed + 1 end; if row.driverId == driver.ncmDriverId then mine = row end end
            if mine then tell(pid, ("Practice: P%d of %d timed · best %s · %d run(s). /ncm.practice for the board."):format(mine.position, timed, fmtTime(mine.bestSec), mine.runs or 0)) end
        end
    elseif res.runStarted then
        toast(pid, { type = "info", title = "RUN STARTED", message = ("run %d"):format(res.runs or 1), icon = "NCM", durationMs = 2500 })
    end
    local events = rec.kernel.step(rec.s, t)
    if #events > 0 then handle(rec, events, t) end
    publish(rec, t)
    return res
end

RegisterNetEvent("ncm:gate", function(sessionId, gateIndex)
    local pid = tonumber(source) or 0
    local rec = sessions[tostring(sessionId or "")]
    if not rec then return end
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then return end
    NcmRace.reportGate(rec, pid, driver, gateIndex, positionOf(pid), now(), "client")
end)

--- The telemetry stream saw a crossing (server-side detection, L63): report it as the server's own witness.
function NcmRace.streamGate(rec, driverId, gateIndex, pos, t)
    local pid = rec.playerOf[driverId]
    local driver = { ncmDriverId = driverId }
    return NcmRace.reportGate(rec, pid, driver, gateIndex, pos, t, "stream")
end

AddEventHandler("onPlayerDisconnected", function(playerId)
    local pid = tonumber(playerId) or 0
    for _, rec in pairs(sessions) do
        for driverId, p in pairs(rec.playerOf) do
            if p == pid then
                local events = rec.kernel.suspend(rec.s, driverId, now(), "disconnected")
                if not events then events = rec.kernel.leave(rec.s, driverId, now(), "disconnected") end
                if events then handle(rec, events, now()) end
                rec.playerOf[driverId] = nil
                local more = rec.kernel.step(rec.s, now())
                if #more > 0 then handle(rec, more, now()) end
                publish(rec, now())
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- On-demand practice (P48): one session per event from the first interest until the first plan session forms.
-- ---------------------------------------------------------------------------------------------
function NcmRace.practiceFor(e, t)
    local rec = practices[e.eventId]
    if rec then return rec end
    local open, w = Guide.practiceOpen(e, t, setting("raceFormAtSec", 60))
    if not open then return nil, w end
    local course, why = courseFor(e)
    if not course then return nil, why end
    local sessionId = ids.uuid4(hostRng)
    local s = Practice.new({ sessionId = sessionId, eventId = e.eventId, gates = course.gates, closesAt = w.closesAt, openAt = t })
    rec = { s = s, kernel = Practice, kind = "practice", practice = true, spec = { kind = "practice" }, eventId = e.eventId, routeId = e.routeId,
            routeName = e.routeName, seriesName = e.seriesName, disciplineId = e.disciplineId, course = course,
            playerOf = {}, lastPos = {}, toNext = {}, progressM = {}, correctedM = {} }
    practices[e.eventId] = rec
    sessions[sessionId] = rec
    pcall(function()
        MySQL.insert.await(
            "INSERT INTO session (session_id, event_id, kind, state, starts_at, formed_at, entrants, gates, ordinal, lap_count, format_id) VALUES (?, ?, 'practice', 'running', ?, ?, 0, ?, 0, ?, 'practice')",
            { sessionId, e.eventId, math.floor(t), math.floor(t), #course.gates, course.laps or 1 })
    end)
    if NcmTelemetry and NcmTelemetry.attach then NcmTelemetry.attach(rec) end
    log("PRACTICE open session=%s event=%s until %s (%s)", sessionId, e.eventId, Entry.countdown(w.closesAt - t), e.routeName)
    publish(rec, t)
    return rec
end

function NcmRace.practiceJoin(e, driver, pid, t)
    local rec, why = NcmRace.practiceFor(e, t)
    if not rec then return nil, why end
    local r, note = rec.kernel.join(rec.s, { driverId = driver.ncmDriverId, display = driver.display or (pid and GetPlayerName(pid)) or driver.ncmDriverId:sub(1, 8) })
    if not r then return nil, note end
    rec.playerOf[driver.ncmDriverId] = pid
    publish(rec, t)
    return true, note
end

function NcmRace.practiceLeave(eventId, driverId, t, reason)
    local rec = practices[eventId]
    if not rec then return end
    local events = rec.kernel.leave(rec.s, driverId, t, reason or "withdrawn")
    if events then handle(rec, events, t) end
    rec.playerOf[driverId] = nil
    publish(rec, t)
    return true
end

function NcmRace.practiceClose(eventId, t, reason)
    local rec = practices[eventId]
    if not rec then return end
    local events = rec.kernel.close(rec.s, t, reason)
    if events then handle(rec, events, t) end
end

function NcmRace.practiceComplete(rec, results, reason, t)
    rec.results = results; rec.completeReason = reason; rec.doneAt = t
    pcall(function()
        MySQL.update.await("UPDATE session SET state = 'complete', completed_at = ?, complete_reason = ? WHERE session_id = ?", { t, reason, rec.s.sessionId })
        for _, r in ipairs(results) do
            if r.bestSec then
                MySQL.insert.await(
                    "INSERT INTO session_result (session_id, ncm_driver_id, entry_id, position, state, total_ms, penalty_ms, gates_done, gates_total, incident_ms, incident_count, best_ms, asset_id, attribution_basis, configuration_ref) VALUES (?, ?, NULL, ?, 'finished', ?, 0, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, ''))",
                    { rec.s.sessionId, r.driverId, r.position, math.floor(r.bestSec * 1000), r.gatesTotal or 2, r.gatesTotal or 2,
                      math.floor((r.incidentSec or 0) * 1000), r.incidentCount or 0, math.floor(r.bestSec * 1000),
                      attribution(rec, r.driverId) })
            end
        end
    end)
    if NcmWeather and NcmWeather.stamp then NcmWeather.stamp("session", rec.s.sessionId, t) end   -- schema 043
    local timed = 0
    for _, r in ipairs(results) do if r.bestSec then timed = timed + 1 end end
    for driverId, pid in pairs(rec.playerOf) do
        local en = rec.s.entrants[driverId]
        if en and en.state ~= "left" then   -- the tick refreshes playerOf from every connected driver; withdrawn ones are not told
            local mine
            for _, r in ipairs(results) do if r.driverId == driverId then mine = r end end
            if mine and mine.bestSec then tell(pid, ("Practice closed (%s): P%d of %d timed · best %s."):format(reason, mine.position, timed, fmtTime(mine.bestSec)))
            else tell(pid, ("Practice closed (%s)."):format(reason)) end
        end
    end
    log("PRACTICE closed session=%s event=%s reason=%s timed=%d", rec.s.sessionId, rec.eventId, reason, timed)
    practices[rec.eventId] = nil
    sessions[rec.s.sessionId] = nil
    practiceViews[rec.eventId] = nil
    republishPractice(t)
end

--- { [eventId] = { [driverId] = bestSec } } from the live practices (the Guide's "my practice best").
function NcmRace.practiceBests()
    local out = {}
    for eid, rec in pairs(practices) do
        out[eid] = {}
        for id, r in pairs(rec.s.entrants) do if r.bestSec then out[eid][id] = r.bestSec end end
    end
    return out
end

--- Chat lines for a player's practice leaderboard (ref = eventId or nil = the practice they are in).
function NcmRace.practiceBoard(pid, ref)
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then return nil end
    local rec = ref and practices[tostring(ref)] or nil
    if not rec then
        for _, r in pairs(practices) do if r.s.entrants[driver.ncmDriverId] then rec = r; break end end
    end
    if not rec then return nil end
    local board = Practice.leaderboard(rec.s)
    local lines = { ("Practice · %s · %s · closes in %s"):format(rec.seriesName or "", rec.routeName or "", Entry.countdown((rec.s.closesAt or now()) - now())) }
    for _, row in ipairs(board) do
        lines[#lines + 1] = ("  P%d %s%s · %s · %d run(s)%s"):format(row.position, tostring(row.display), row.driverId == driver.ncmDriverId and " (you)" or "",
            row.bestSec and fmtTime(row.bestSec) or "no time", row.runs or 0, row.gapSec and (" · +" .. string.format("%.3f", row.gapSec)) or "")
    end
    return lines
end

RegisterCommand("ncm.race", function()
    local n = 0
    for sid, rec in pairs(sessions) do
        n = n + 1
        local v = rec.kernel.publicView(rec.s)
        local parts = {}
        for _, en in ipairs(v.entrants) do parts[#parts + 1] = ("%s:%s:%d"):format(tostring(en.display), en.state, en.progress or 0) end
        log("session=%s event=%s kind=%s phase=%s entrants=[%s]", sid, rec.eventId, rec.kind, v.phase, table.concat(parts, " "))
    end
    if n == 0 then log("no sessions") end
end, false)
