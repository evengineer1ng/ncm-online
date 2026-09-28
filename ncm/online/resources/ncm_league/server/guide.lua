-- ncm_league / server / guide — the Race Guide (Batch 2; P47, P48, P52).
--
-- The spine: every posted event is a row a driver browses; "interest" is the ordinary entry (a soft list —
-- no reservation; the grid is whoever checks in at the venue, L48); interest opens on-demand practice for that
-- event (session.practice, until the first session forms) and routes the driver to the venue. The page lives in
-- ncm_world's panel (bag `ncmGuide`), and every action has a chat twin (/ncm.guide, /ncm.interest <n>,
-- /ncm.withdraw, /ncm.practice) and a console twin (ncm.interest <pid> <n>) for KB-4 clients.
NcmGuide = {}

local Core = NcmCore
local Guide = Core.get("competition.guide")
local Entry = Core.get("competition.entry")
local VenueOptions = Core.get("competition.venue_options")

local function log(fmt, ...) print(("[ncm_league/guide] " .. fmt):format(...)) end
local now = function() return Open77.time.unix() end

-- Not a platform limit -- a tripwire. We do not know the real ceiling, so this is set where a Guide payload
-- stops being obviously reasonable, and its job is to put a number in the log before anyone has to guess.
-- The Guide payload crosses two size-sensitive boundaries: the server->client net event, and then the
-- client's `page:send` bridge (KB-63). Neither reports a failure -- the payload simply never arrives and the
-- panel draws its empty placeholder. A known-good payload was ~17.9 KB and a broken one ~22.5 KB, so warn
-- well below that gap rather than above it: the old 24 KB threshold sat ABOVE the size that actually broke,
-- which is why nothing warned.
local PAYLOAD_WARN_BYTES = 18 * 1024

-- KB-160. The tripwire above is not a fix, and twice now it has not even been a warning that arrived in time:
-- the Guide broke at ~22.5 KB in KB-86 (twenty rows of history in the head), was rescued by making the payload
-- smaller, and broke again the moment Economy v1 put a per-row `economy` block on seventeen rows. Making a
-- payload smaller is a fix with a shelf life, so the hop is BOUNDED instead -- see `server/stream.lua`, which
-- now does this for every payload that carries a list.
local hostRng = function() return math.random() end

local function setting(key, default)
    local s = NcmCalendar and NcmCalendar.settings
    local ok, v = pcall(function() return s and s[key] end)
    return (ok and v) or default
end

local function tell(pid, text) if pid then pcall(Open77.chat.send, pid, "[NCM] " .. text) end end
local function toast(pid, def) if pid then pcall(Open77.notifications.send, pid, def) end end

local function serverId() return NcmCalendar.serverId() end

-- ---------------------------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------------------------
local function orderedEvents()
    local out = {}
    for _, eid in ipairs(NcmCalendar.orderedIds()) do
        local e = NcmCalendar.events[eid]
        if e then out[#out + 1] = e end
    end
    return out
end

--- Guide rows for a player (nil driver = anonymous).
function NcmGuide.rows(pid)
    local driver = pid and NcmCalendar.resolveDriver(pid) or nil
    local practice = NcmRace and NcmRace.practiceBests and NcmRace.practiceBests() or {}
    return Guide.rows(orderedEvents(), driver and driver.ncmDriverId or nil, now(),
        { formLeadSec = setting("raceFormAtSec", 60), practice = practice }), driver
end

-- pid -> last row count published, so the line above is logged on change rather than every five seconds
local lastGuideRows = {}

--- What a driver needs to know about machinery BEFORE committing (IDEA-124, L83).
--- Returns { summary, admits, iOwn, ok } or nil when it cannot be answered. `ok = false` means the venue list
--- will not offer ENTER RACE, so the guide should say so here rather than letting them drive across the city.
local function carFacts(e, driverId)
    if not (NcmCompetition and NcmCompetition.eligibilityFor) then return nil end
    local Elig = NcmCore.get("competition.eligibility")
    local spec = NcmCompetition.eligibilityFor(e)
    local admits = Elig.recordsFor(spec)
    local iOwn = 0
    if driverId and NcmOwnership then
        -- distinct records (IDEA-157): owning a spare must not read as owning a second eligible car
        iOwn = #Elig.eligibleOwned(spec, NcmOwnership.records(driverId))
    end
    return {
        summary = Elig.describe(spec, #admits),
        admits = #admits,
        iOwn = iOwn,
        ok = #admits > 0 and iOwn > 0,
    }
end

-- The weather seam (11_WEATHER.md). The Guide presents the service's one bounded read model and owns no weather
-- authority. Startup/database/environment failure remains an honest unavailable state.
--- The forecast for ONE event, as the smallest thing worth putting on a schedule row.
--- The full read model rides once at payload top level (11_WEATHER.md §"API and presentation seam"); this is the
--- per-row cue the ribbon and the event block need, not a copy of the forecast onto every row.
---
--- Returns nil when the bands cannot answer -- past the horizon, or the service is not ready. **Absent is not
--- "sunny"**: the client must render nothing rather than invent an icon.
local function eventWeather(model, startsAt)
    if type(model) ~= "table" or model.state ~= "ready" or type(startsAt) ~= "number" then return nil end
    -- No event carries an authoritative duration yet, so no end time is passed: this reports the START honestly
    -- and flags a transition landing close to it. Guessing a race length and calling the guess a forecast is
    -- exactly what the brief warns against; IDEA-134 closes the window half once duration is real.
    local f = NcmCore.get("world.weather").forEvent(model.forecast, startsAt)
    if not f then return nil end
    return { w = f.atStart.weather, family = f.atStart.family, conf = f.confidence,
             kind = f.atStart.kind, changes = f.changes or nil, soonAt = f.transitionNearStart }
end

local function weatherBlock()
    local w = NcmWeather and NcmWeather.readModel and NcmWeather.readModel() or nil
    if type(w) == "table" then return w end
    return { state = "unavailable", reason = "weather_service_not_implemented" }
end

--- What the CLIENT gets. The service read model is the right thing to compute from and the wrong thing to send.
---
--- 11_WEATHER.md asks for "one bounded read model at payload top level". The first implementation put
--- `NcmWeather.readModel()` there whole -- current conditions, every forecast band inside a 24 h horizon, AND
--- the last sixteen observations -- which is neither bounded nor a read model for this screen. The Guide needs
--- to say what it is doing now and what each event should expect; the per-row cue already carries the latter.
---
--- `recent` is dropped outright: it is observation history, nothing on the Guide renders it, and its `preset`
--- and `reason` come straight off a database row without passing through tostring/tonumber -- the one part of
--- this payload whose type we do not actually control.
local function weatherForClient(w)
    if type(w) ~= "table" then return { state = "unavailable", reason = "no_model" } end
    if w.state ~= "ready" then
        return { state = tostring(w.state or "unavailable"), reason = tostring(w.reason or "not_ready") }
    end
    local c = type(w.current) == "table" and w.current or {}
    return {
        state = "ready",
        scope = tostring(w.scope or "NIGHT CITY"),
        now = {
            w = c.weather and tostring(c.weather) or nil,
            family = c.weather and NcmCore.get("world.weather").family(tostring(c.weather)) or nil,
            sinceUtc = tonumber(c.observedAtUtc) or nil,
        },
        issuedAtUtc = tonumber(w.issuedAtUtc) or nil,
        revision = tonumber(w.revision) or nil,
        modelVersion = tonumber(w.modelVersion) or nil,
    }
end

-- ---------------------------------------------------------------------------------------------
-- PAST RESULTS (was the greyed-out "Past Races" tab).
--
-- The results were never missing. `race.complete()` has written `session_result` since M3, and the owner's two
-- completed runs of 2026-09-23 -- Sewer 153.052 and Overbridge Curve 82.031 -- were both in the table while the
-- tab sat disabled. The tab was hard-coded `disabled` in `panel.html` with no query behind it and
-- `capabilities.pastRaces = false` on the wire. It was an unimplemented surface, not a broken one.
--
-- **Past RESULTS, not past races**, because a field of one is a time trial (L67/IDEA-001) and every one of the
-- owner's runs so far has been one. A history that only counted wheel-to-wheel races would show them nothing
-- they had actually done.
--
-- L74c: these rows are sporting history. This reads them; it never writes, derives or prunes them. A later
-- personal best does not remove the slow early run that came before it -- that run is the thing worth keeping.
local RESULTS_MAX = 20
local RESULTS_TTL_S = 60
local resultsCache = {}          -- driverId -> { at = monotonic, rows = { ... } }

--- This driver's completed results, newest first. Cached: `pushGuide` runs for every connected player on every
--- calendar tick, and history changes only when a session completes.
function NcmGuide.results(driverId)
    if not driverId then return {} end
    local hit = resultsCache[driverId]
    if hit and (now() - hit.at) < RESULTS_TTL_S then return hit.rows end
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT s.session_id, s.kind, s.starts_at, s.ordinal,
                   e.series_name, e.route_name,
                   r.position, r.state, r.total_ms, r.corrected_ms, r.best_ms, r.penalty_ms,
                   r.gates_done, r.gates_total, r.dnf_reason,
                   (SELECT COUNT(*) FROM session_result x WHERE x.session_id = s.session_id) AS field_size
              FROM session_result r
              JOIN session s ON s.session_id = r.session_id
              LEFT JOIN event e ON e.event_id = s.event_id
             WHERE r.ncm_driver_id = ? AND s.state = 'complete'
             ORDER BY s.starts_at DESC
             LIMIT ]] .. RESULTS_MAX, { driverId }) or {}
    end)
    if not ok then
        log("results query failed driver=%s: %s", tostring(driverId):sub(1, 8), tostring(rows))
        return (hit and hit.rows) or {}
    end
    local out = {}
    for i, r in ipairs(rows) do
        local field = tonumber(r.field_size) or 1
        out[i] = {
            sessionId = tostring(r.session_id),
            kind = tostring(r.kind or "race"),
            at = tonumber(r.starts_at) or 0,
            series = r.series_name and tostring(r.series_name) or nil,
            route = r.route_name and tostring(r.route_name) or nil,
            position = tonumber(r.position) or 0,
            state = tostring(r.state or ""),
            fieldSize = field,
            -- L67: a field of one is a time trial. The client must not be left to infer that from a count it
            -- might not have, so the fact travels with the row.
            timeTrial = (tostring(r.kind or "race") == "race") and field <= 1 or false,
            totalSec = tonumber(r.corrected_ms) and (tonumber(r.corrected_ms) / 1000) or (tonumber(r.total_ms) and tonumber(r.total_ms) / 1000) or nil,
            bestSec = tonumber(r.best_ms) and (tonumber(r.best_ms) / 1000) or nil,
            penaltySec = (tonumber(r.penalty_ms) or 0) > 0 and (tonumber(r.penalty_ms) / 1000) or nil,
            gates = tonumber(r.gates_done) or 0,
            gatesTotal = tonumber(r.gates_total) or 0,
            why = r.dnf_reason and tostring(r.dnf_reason) or nil,
        }
    end
    resultsCache[driverId] = { at = now(), rows = out }
    return out
end

-- A finished session is the only thing that changes history, so it is the only thing that invalidates the
-- cache. Cheap and exact: no polling, no TTL guesswork at the moment it actually matters.
AddEventHandler("ncm:race.completed", function() resultsCache = {} end)

local function pushGuide(pid)
    local rows, driver = NcmGuide.rows(pid)
    local driverId = driver and driver.ncmDriverId or nil
    local wx = weatherBlock()
    local slim = {}
    for i, r in ipairs(rows) do
        slim[i] = { n = r.n, eventId = r.eventId, tier = r.tier, series = r.seriesName, route = r.routeName, venue = r.venueName, finish = r.finishName,
            distanceM = r.distanceM, discipline = r.disciplineId, format = r.formatId, class = r.classId, laps = r.laps,
            seriesId = r.seriesId,
            startsAt = r.startsAt, entryOpensAt = r.entryOpensAt, state = r.state, invitation = r.invitation,
            interested = r.interested, entered = r.entered, seatsTotal = r.seatsTotal, myState = r.myState, practice = r.practice, myPracticeBest = r.myPracticeBest,
            region = r.region, finishRegion = r.finishRegion, courseAdapter = r.courseAdapter, startType = r.startType, description = r.description, summary = r.summary,
            -- IDEA-124/125: what to bring and what the regs are, before committing. `car` is per driver.
            car = carFacts(NcmCalendar.events[r.eventId], driverId),
            regs = { tier = r.tier, discipline = r.disciplineId, format = r.formatId, laps = r.laps,
                     startType = r.startType, capacity = r.seatsTotal, rulesetId = r.rulesetId },
            economy = r.economy and {
                id=r.economy.id, version=r.economy.version, entryFee=r.economy.entryFee,
                timeTrialCompletion=r.economy.timeTrialCompletion, raceCompletion=r.economy.raceCompletion,
                placement={p1=r.economy.placement[1],p2=r.economy.placement[2],p3=r.economy.placement[3]}, fieldBonus=r.economy.fieldBonus,
                repeatFloor=r.economy.repeatFloor, tagBounties=r.economy.tagBounties,
                maxTagBounty=r.economy.maxTagBounty,
            } or nil,
            weather = eventWeather(wx, r.startsAt) }
    end
    -- A bare `pcall` here swallowed every publish failure, which is why an empty Race Guide was indistinguishable
    -- from a server that had posted nothing: `/ncm.guide` read the same rows and listed them happily while the
    -- panel showed "Nothing posted right now." A publish that fails must say so, and say how big it was --
    -- deploy 11 took the calendar from one series to five, so the row count roughly tripled.
    local payload = {
        rows = slim, at = math.floor(now()), serverNow = math.floor(now()),
        balance = driverId and NcmEconomy and NcmEconomy.balanceOf(driverId) or nil,
        -- one bounded read model at payload top level, NOT forecast facts copied onto every row (11_WEATHER.md).
        -- `wx` stays server-side for eventWeather(); only the bounded projection goes on the wire.
        weather = weatherForClient(wx),
        -- **Results are NOT in this payload.** They were, for about an hour, and it broke the Race Guide:
        -- the payload went from ~17.9 KB to ~22.5 KB and stopped arriving altogether, so the panel drew its
        -- empty placeholder -- no races, and a 1969 date because `serverNow` was missing too.
        --
        -- Both hops are now bounded (KB-160), so size is no longer the reason they stay out -- the reason that
        -- survives is that they are the wrong thing to broadcast at all: this payload is rebuilt for every
        -- connected player on every calendar tick, and a driver's own history changes only when they finish a
        -- race. Fetched on demand instead -- see `ncm:guide.results` below. Note also that the head is still
        -- the one unsplittable part of the stream, which is exactly where those twenty rows used to sit.
        capabilities = { myRaces = true, pastResults = true, reminders = false, routePreview = false,
                         concurrentLanes = true, carRequirements = true, regs = true,
                         weather = wx.state == "ready" }
    }
    -- KB-160: this hop is BOUNDED, it is not merely measured. `NcmStream.send` splits the rows into packets
    -- packed by measured bytes and leaves a head that carries `serverNow`, weather, balance and capabilities.
    -- Before this, `sendBig` on the client batched the rows for the WebUI bridge only -- which cannot rescue a
    -- payload that never reached the client, and this event was sent whole.
    --
    -- KB-97: the targeted event is the whole delivery. The `ncmGuide` bag alongside it carried the SAME payload
    -- to every player in the routing bucket, including `iOwn` and `carRefusal`, so deleting it changed nothing
    -- the subject sees.
    local size, headBytes, packets = NcmStream.send(pid, "ncm:guide", payload, "rows")
    if size > PAYLOAD_WARN_BYTES then
        -- Not a failure any more -- the stream carries it whatever this says. It stays because the total is the
        -- number that tells us the Guide is growing, and growth is what produced KB-86 and KB-160.
        log("guide payload large player=%d rows=%d bytes=%d (above %d) -- streamed in packets, not dropped",
            pid, #slim, size, PAYLOAD_WARN_BYTES)
    end

    if #slim ~= (lastGuideRows[pid] or -1) then
        lastGuideRows[pid] = #slim
        log("guide published player=%d rows=%d bytes=%d head=%d packets=%d", pid, #slim, size, headBytes, packets)
    end
    return rows, driver
end
NcmGuide.push = pushGuide

-- ---------------------------------------------------------------------------------------------
-- The venue option list (IDEA-095) and the history panel -- both as structured bags, never chat.
--
-- KB-31/L?: chat is not a display surface. Anything with structure -- a list of actions, a leaderboard, a run
-- history -- is published as data and drawn by the client. The /ncm.* chat commands stay as the KB-4 console
-- twin for a second client that has no WebUI, and for nothing else.
-- ---------------------------------------------------------------------------------------------

--- The soonest published event, which is the one a venue marker is for.
local function nextEvent()
    for _, eid in ipairs(NcmCalendar.orderedIds()) do
        local e = NcmCalendar.events[eid]
        if e and e.state ~= "closed" and e.state ~= "cancelled" then return e end
    end
    return nil
end

local ENTRY_GRACE_S = 60   -- a race that has just gone green is still "yours" for a moment

--- The soonest race this driver still has a live entry in, or nil. ONE definition, so the ring, the card,
--- the waypoint and the venue options can never disagree about which race is "yours".
local function driverEvent(driverId)
    if not driverId then return nil end
    local t = now()
    for _, x in ipairs(orderedEvents()) do          -- ordered by start time: the first match is the soonest
        local en = x.entries and x.entries[driverId]
        local st = en and tostring(en.state or "") or nil
        if st and st ~= "withdrawn" and st ~= "cancelled" and (x.startsAt or 0) > t - ENTRY_GRACE_S then
            return x, st
        end
    end
    return nil
end

--- What this driver can do at that event's venue right now. Pure decision in core; this only gathers facts.
function NcmGuide.venueOptions(pid)
    local driver = NcmCalendar.resolveDriver(pid)
    local busy, busyEvent, busyKind = nil, nil, nil
    if driver and NcmRace and NcmRace.busySession then
        busy, busyEvent, busyKind = NcmRace.busySession(driver.ncmDriverId)
    end
    -- YOUR race, not the server's soonest. `nextEvent()` ignores the driver entirely, so a player standing on
    -- the start line of the race they entered was shown the card for an unrelated championship that happened
    -- to start sooner -- which of course offered nothing but HISTORY, because they were not in it. Third
    -- occurrence of this class today, after `ncmEntry` and `/ncm.gps` (owner, 2026-09-23).
    local mine = driver and driverEvent(driver.ncmDriverId) or nil
    -- L114: practice is independent of interest. Keep the venue card on the practice event so its explicit
    -- LEAVE PRACTICE action cannot disappear merely because the driver never joined the interest list.
    local practiceEvent = busyKind == "practice" and NcmCalendar.events[tostring(busyEvent or "")] or nil
    local e = practiceEvent or mine or nextEvent()
    if not e then return nil end
    -- QA P4 / L107: announce whether this card names the driver's own race. A fact, not a decision -- nothing
    -- below reads it, and `wp/QA_INSTRUMENTATION.md` explains why this particular invariant earns an observer.
    if driver then
        pcall(TriggerEvent, "ncm:qa.guidance", mine and mine.eventId or nil, e.eventId, "venue_card", driver.ncmDriverId)
    end
    local entry = driver and e.entries and e.entries[driver.ncmDriverId] or nil
    local practiceActive = busy ~= nil and busyEvent == e.eventId and busyKind == "practice"
    -- L83/IDEA-113: do not offer an entry the server would refuse a second later. `carRefusal` is nil when the
    -- driver can field a legal car, and nil is also what a ledger we could not read returns -- "we could not
    -- ask" must never present as "you may not race".
    local carRefusal = driver and NcmCompetition and NcmCompetition.carRefusal
        and NcmCompetition.carRefusal(e, driver.ncmDriverId) or nil
    local result = VenueOptions.evaluate({
        now = now(),
        event = e,
        entryState = entry and entry.state or nil,
        sessionLive = NcmRace and NcmRace.hasSession and NcmRace.hasSession(e.eventId) or false,
        busyElsewhere = busy ~= nil and not practiceActive,
        practiceActive = practiceActive,
        carRefusal = carRefusal,
        formLeadSec = setting("raceFormAtSec", 60),
    })
    return result, e
end

local function pushVenue(pid)
    local result, e = NcmGuide.venueOptions(pid)
    if not result or not e then
        pcall(function() Open77.state.player(pid):clear("ncmVenue") end)
        return
    end
    local okSet, err = pcall(function()
        Open77.state.player(pid):set("ncmVenue", {
            eventId = e.eventId, series = e.seriesName, route = e.routeName, venue = e.venue.name,
            startsAt = math.floor(e.startsAt), options = result.options, serverNow = math.floor(now()),
        })
    end)
    if not okSet then log("VENUE PUBLISH FAILED player=%d: %s", pid, tostring(err)) end
end
NcmGuide.pushVenue = pushVenue

--- Refresh every connected player's Guide (calendar tick, interest changes).
function NcmGuide.pushAll()
    for _, pid in ipairs(Open77.players.all()) do pushGuide(pid); pushVenue(pid) end
end

-- One option engaged. The client sends the id it drew; the server re-derives the list and refuses anything that
-- is not on it, so a stale client cannot act on an option that has since stopped applying.
RegisterNetEvent("ncm:venue.option", function(optionId)
    local pid = tonumber(source) or 0
    local id = tostring(optionId or "")
    local result, e = NcmGuide.venueOptions(pid)
    if not result or not e then return end
    local allowed = false
    for _, o in ipairs(result.options) do if o.id == id then allowed = true end end
    if not allowed then
        log("venue option refused player=%d option=%s reason=%s", pid, id, tostring(result.reasons[id] or "unknown_option"))
        toast(pid, { type = "warning", title = "Not available", message = "That option is no longer available here.", icon = "NCM", durationMs = 5000 })
        pushVenue(pid)
        return
    end
    log("venue option player=%d event=%s option=%s", pid, e.eventId, id)
    if id == "enter_race" then
        NcmCalendar.enter(pid, e.eventId)
    elseif id == "practice" then
        -- L114: practice is an explicit act. Interest, entry and proximity never join a session.
        local driver = NcmCalendar.resolveDriver(pid)
        local ok, why = driver and NcmRace and NcmRace.practiceJoin and NcmRace.practiceJoin(e, driver, pid, now())
        if ok then
            tell(pid, ("Practice started: %s. Cross the start line when ready."):format(e.routeName))
            NcmGuide.pushPractice(pid, e)
        else
            tell(pid, "Could not start practice: " .. tostring(why or "unavailable"))
        end
    elseif id == "leave_practice" then
        local driver = NcmCalendar.resolveDriver(pid)
        if driver and NcmRace and NcmRace.practiceLeave then
            NcmRace.practiceLeave(e.eventId, driver.ncmDriverId, now(), "left_practice")
            tell(pid, ("Practice ended: %s."):format(e.routeName))
        end
    elseif id == "withdraw" or id == "leave_list" then
        NcmGuide.withdraw(pid, e.eventId)
    elseif id == "history" then
        NcmGuide.pushHistory(pid, e.routeId, e.routeName)
    end
    pushVenue(pid)
end)

--- The practice panel: the board and, above all, how to start a run. Structured, not chat (KB-31).
function NcmGuide.pushPractice(pid, e)
    local driver = NcmCalendar.resolveDriver(pid)
    local bests = NcmRace and NcmRace.practiceBests and NcmRace.practiceBests() or {}
    local mineId = driver and driver.ncmDriverId or nil
    local rows = {}
    for id, sec in pairs(bests[e.eventId] or {}) do
        rows[#rows + 1] = { driverId = id, bestSec = sec, me = id == mineId }
    end
    table.sort(rows, function(a, b) return a.bestSec < b.bestSec end)
    for i, r in ipairs(rows) do r.rank = i; r.driverId = nil end   -- ranks and times only: no driver ids to the client
    local open = Guide.practiceOpen(e, now(), setting("raceFormAtSec", 60))
    pcall(function()
        -- Migrated with history (KB-97): not itself private, but leaving one of the two request-driven
        -- panels on a persisted bag would mean the client kept two different rules for the same interaction.
        TriggerClientEvent("ncm:venue.practice", pid, {
            eventId = e.eventId, route = e.routeName, open = open and true or false,
            -- L67/KB-31: practice runs until the race forms. It is NOT a registration deadline and must never
            -- be worded as one, so the client gets the fact and not a countdown to "entries close".
            untilRaceForms = true, formsAt = math.floor((e.startsAt or 0) - setting("raceFormAtSec", 60)),
            howToStart = "Cross the start line to begin a run. Your best run counts. Take as many as you like.",
            board = rows, at = math.floor(now()),
        })
    end)
end

--- The history panel: this driver's runs on the route, and the server's larger history for it (owner, 2026-09-21
--- -- one option, one panel, both readings). Published as `ncmHistory`; the client draws it.
function NcmGuide.pushHistory(pid, routeId, routeName)
    CreateThread(function()
        local driver = NcmCalendar.resolveDriver(pid)
        local mine, best = {}, nil
        if driver and MySQL.isReady() then
            local rows = MySQL.query.await(
                "SELECT sr.position, sr.state, sr.total_ms, sr.corrected_ms, sr.incident_count, s.entrants, s.completed_at, s.kind " ..
                "FROM session_result sr JOIN session s ON s.session_id = sr.session_id JOIN event ev ON ev.event_id = s.event_id " ..
                "WHERE sr.ncm_driver_id = ? AND ev.route_id = ? ORDER BY s.completed_at DESC LIMIT 10",
                { driver.ncmDriverId, routeId }) or {}
            for i, r in ipairs(rows) do
                mine[i] = { position = tonumber(r.position), state = r.state, totalMs = tonumber(r.total_ms),
                            correctedMs = tonumber(r.corrected_ms), incidents = tonumber(r.incident_count) or 0,
                            entrants = tonumber(r.entrants) or 0, at = tonumber(r.completed_at), kind = r.kind }
                if r.state == "finished" and tonumber(r.total_ms) and (not best or tonumber(r.total_ms) < best) then best = tonumber(r.total_ms) end
            end
        end
        -- the server's side of the same route, from the leaderboard that already exists
        local board, updatedAt = {}, nil
        local rec = GlobalState.ncmRecords
        if type(rec) == "table" then
            updatedAt = rec.updatedAt
            for _, rt in ipairs(rec.routes or {}) do
                if rt.routeId == routeId then
                    for i, b in ipairs(rt.best or {}) do
                        board[i] = { rank = i, display = b.display, bestMs = b.bestMs, finishes = b.finishes,
                                     me = driver and b.driverId == driver.ncmDriverId or false }
                    end
                end
            end
        end
        pcall(function()
            -- KB-97: `mine` and `myBestMs` are this driver's own runs and personal best. Pushed only when
            -- the driver picks HISTORY, so a targeted event is both private AND a truer fit than a persisted
            -- bag: an event cannot be mistaken for a request that survived into the next session, which is
            -- exactly what made the history panel reopen itself (KB-67).
            TriggerClientEvent("ncm:venue.history", pid, {
                routeId = routeId, route = routeName, mine = mine, myBestMs = best,
                board = board, updatedAt = updatedAt, at = math.floor(now()),
            })
        end)
        log("history pushed player=%d route=%s mine=%d board=%d", pid, tostring(routeId), #mine, #board)
    end)
end

RegisterNetEvent("ncm:history", function(routeId, routeName)
    local pid = tonumber(source) or 0
    local e = nextEvent()
    NcmGuide.pushHistory(pid, routeId or (e and e.routeId), routeName or (e and e.routeName))
end)

-- ---------------------------------------------------------------------------------------------
-- Interest / withdraw
-- ---------------------------------------------------------------------------------------------
local function eventByIndex(pid, ref)
    local rows = NcmGuide.rows(pid)
    local n = tonumber(ref)
    if n then
        local r = rows[n]
        return r and NcmCalendar.events[r.eventId] or nil, r
    end
    for _, r in ipairs(rows) do if r.eventId == tostring(ref) then return NcmCalendar.events[r.eventId], r end end
    return nil
end

local REASONS = {
    no_event = "No such race in the Guide.", event_closed = "That race is over.", event_started = "That race has already started.",
    invitation_only = "That one is by invitation — a team has to offer you a seat.", already_interested = "You're already on the list for that one.",
    already_entered = "You're already entered.", no_entry = "You're not on that list.", no_driver = "No NCM driver on this session.",
    already_raced = "That one is already in your results.",
    in_session = "You are out in that session -- /ncm.forfeit to retire from it.",
}

--- Publish `ncmEntry`: the one race the client should ring, card and route to.
---
--- **It holds exactly one event, and it used to hold whichever race was clicked LAST.** A driver interested
--- in three races was ringed and routed to whichever they pressed most recently rather than the one starting
--- next -- and withdrawing from any single race cleared the bag outright, leaving a driver with two live
--- entries staring at no ring, no card and no way to find the start line (owner, 2026-09-23, nine minutes
--- before a race).
---
--- The client derives ring, card and waypoint from this bag, so it must always describe the SOONEST race this
--- driver still has a live entry in. Recomputed from the entries themselves after any change, never inferred
--- from the action that caused it.
local function publishEntryBag(pid, driverId)
    if not (pid and pid > 0 and driverId) then return end
    local best, bestState = driverEvent(driverId)
    if not best then
        pcall(function() Open77.state.player(pid):clear("ncmEntry") end)
        return
    end
    pcall(function() Open77.state.player(pid):set("ncmEntry", {
        eventId = best.eventId, state = bestState, routeName = best.routeName,
        startsAt = math.floor(best.startsAt),
        venue = { x = best.venue.x, y = best.venue.y, z = best.venue.z, name = best.venue.name } }) end)
end

function NcmGuide.interest(pid, ref)
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then tell(pid, REASONS.no_driver); return nil, "no_driver" end
    local e = eventByIndex(pid, ref)
    if not e then tell(pid, REASONS.no_event); return nil, "no_event" end
    local t = now()
    local decision = Guide.interest({ event = e, now = t, driverId = driver.ncmDriverId, existingEntry = e.entries[driver.ncmDriverId], rng = hostRng })
    if not decision.ok then tell(pid, REASONS[decision.reason] or ("Cannot: " .. tostring(decision.reason))); return nil, decision.reason end
    local en = decision.entry
    local okDb, err = pcall(function()
        if decision.rejoined then
            MySQL.update.await("UPDATE entry SET state = 'interested', interested_at = ? WHERE entry_id = ?", { math.floor(t), en.entryId })
        else
            MySQL.insert.await("INSERT INTO entry (entry_id, event_id, ncm_driver_id, state, fee, interested_at) VALUES (?, ?, ?, 'interested', 0, ?)",
                { en.entryId, e.eventId, driver.ncmDriverId, math.floor(t) })
        end
    end)
    if not okDb then tell(pid, "Could not record your interest: " .. tostring(err)); return nil, "db" end
    e.entries[driver.ncmDriverId] = en
    publishEntryBag(pid, driver.ncmDriverId)   -- soonest live entry, not necessarily the one just clicked
    tell(pid, ("You're on the list: %s · %s at %s, start in %s. Entries at the line from %s before the start."):format(
        e.seriesName, e.routeName, e.venue.name, Entry.countdown(e.startsAt - t), Entry.countdown(e.startsAt - e.entryOpensAt)))
    NcmComms.send(pid, {
        id = "race.interest.registered", category = "objective", priority = "actionable", title = "ROUTE SET · ON THE LIST",
        firstMessage = e.routeName .. " · Interest is not entry. Ride to " .. e.venue.name .. "; enter at the line when the window opens.",
        repeatMessage = e.routeName .. " · " .. e.venue.name .. " · starts in " .. Entry.countdown(e.startsAt - t),
        actionHint = "/ncm.gps re-marks the venue", reference = "driver", surface = "toast",
        repeatPolicy = { mode = "adaptive" },
    })
    log("INTEREST player=%d driver=%s event=%s entry=%s", pid, driver.ncmDriverId, e.eventId, en.entryId)
    TriggerClientEvent("ncm:guide.route", pid, { x = e.venue.x, y = e.venue.y, z = e.venue.z, name = e.venue.name, eventId = e.eventId })
    NcmCalendar.publishNow()
    NcmGuide.pushAll()
    return en
end

function NcmGuide.withdraw(pid, ref)
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then tell(pid, REASONS.no_driver); return nil, "no_driver" end
    local e = ref and eventByIndex(pid, ref) or nil
    if not e then
        -- No ref: the driver's own soonest live entry. This used to look only for `state == "interested"`, so
        -- `/ncm.withdraw` could not reach an entry the driver had actually made -- the same half of the bug
        -- the core decision had. `driverEvent` is the ONE definition of "your race" (L107); use it.
        e = driverEvent(driver.ncmDriverId)
    end
    if not e then tell(pid, REASONS.no_event); return nil, "no_event" end
    -- Out on track is a forfeit, not a withdrawal, and only the host can see a live session.
    local busySid, busyEvent, busyKind = NcmRace and NcmRace.busySession and NcmRace.busySession(driver.ncmDriverId)
    local heldHere = busySid ~= nil and busyEvent == e.eventId and busyKind ~= "practice"
    local decision = Guide.withdraw({ existingEntry = e.entries[driver.ncmDriverId], inSession = heldHere })
    if not decision.ok then tell(pid, REASONS[decision.reason] or tostring(decision.reason)); return nil, decision.reason end
    pcall(function() MySQL.update.await("UPDATE entry SET state = 'withdrawn' WHERE entry_id = ?", { decision.entryId }) end)
    e.entries[driver.ncmDriverId] = { entryId = decision.entryId, state = "withdrawn" }   -- the row stays; a rejoin reuses it
    publishEntryBag(pid, driver.ncmDriverId)   -- other live entries must survive this withdrawal
    if NcmRace and NcmRace.practiceLeave then NcmRace.practiceLeave(e.eventId, driver.ncmDriverId, now()) end
    -- Leaving a list and withdrawing an entry are different acts (that is why they are different options);
    -- they must not report themselves with the same sentence.
    if decision.wasEntered then
        tell(pid, ("Withdrawn: %s · %s. You can enter again while entries are open."):format(e.seriesName, e.routeName))
        toast(pid, { type = "info", title = "WITHDRAWN", message = e.routeName .. " · you are not entered", icon = "NCM", durationMs = 6000 })
    else
        tell(pid, ("Off the list: %s · %s."):format(e.seriesName, e.routeName))
    end
    log("WITHDRAW player=%d driver=%s event=%s entered=%s", pid, driver.ncmDriverId, e.eventId, tostring(decision.wasEntered))
    NcmCalendar.publishNow()
    NcmGuide.pushAll()
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Chat twins
-- ---------------------------------------------------------------------------------------------
local function chatRows(pid)
    local rows = pushGuide(pid)
    if #rows == 0 then tell(pid, "Race Guide: nothing posted right now."); return end
    local t = now()
    tell(pid, ("Race Guide: %d race(s). /ncm.interest <n> to get on a list, /ncm.withdraw to leave it."):format(#rows))
    for _, r in ipairs(rows) do
        local mine = r.myState ~= "none" and (" · you: " .. r.myState) or ""
        local prac = r.practice == "open" and (r.myPracticeBest and (" · practice best " .. string.format("%.1f", r.myPracticeBest) .. "s") or " · practice open") or ""
        tell(pid, ("%d. [%s] %s · %s (%s → %s, %d m) · %s · in %s · %d on the list, %d entered%s%s"):format(
            r.n, r.tier, r.seriesName, r.routeName, r.venueName, r.finishName or "?", math.floor(r.distanceM or 0),
            r.invitation and "invitation" or r.state, Entry.countdown(r.startsAt - t), r.interested, r.entered, mine, prac))
    end
end

RegisterNetEvent("ncm:guide", function() pushGuide(tonumber(source) or 0) end)
RegisterNetEvent("ncm:guide.interest", function(ref) NcmGuide.interest(tonumber(source) or 0, ref) end)
--- PAST RESULTS, on demand. Asked for when the player opens that tab, answered to that player only.
---
--- Deliberately a separate message rather than a field on the Guide payload: this is per-driver history that
--- changes once per finished race, while the Guide payload is rebuilt for everyone on every calendar tick.
--- Putting it in there made the whole Guide too large to arrive (see `pushGuide`).
RegisterNetEvent("ncm:guide.results", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    CreateThread(function()
        local driver = NcmCalendar.resolveDriver(pid)
        local rows = driver and NcmGuide.results(driver.ncmDriverId) or {}
        -- IDEA-595: this is the very list whose twenty rows in the Guide head caused KB-86. It is bounded here
        -- for the same reason it was moved out of that payload in the first place.
        NcmStream.send(pid, "ncm:guide.results", { results = rows, at = math.floor(now()) }, "results")
        log("results sent player=%d rows=%d", pid, #rows)
    end)
end)

RegisterNetEvent("ncm:guide.withdraw", function(ref) NcmGuide.withdraw(tonumber(source) or 0, ref) end)

RegisterCommand("ncm.guide", function(source) if (tonumber(source) or 0) > 0 then chatRows(tonumber(source)) end end, false)
RegisterCommand("ncm.interest", function(source, args)
    local pid = tonumber(source) or 0
    if pid > 0 then
        if not (args and args[1]) then tell(pid, "Usage: /ncm.interest <n> (numbers from /ncm.guide)"); return end
        NcmGuide.interest(pid, args[1])
    else
        -- console: ncm.interest <playerId> <n>
        local target, ref = tonumber(args and args[1]), args and args[2]
        if not (target and ref) then log("usage: ncm.interest <playerId> <n|eventId>"); return end
        NcmGuide.interest(target, ref)
    end
end, false)
RegisterCommand("ncm.withdraw", function(source, args)
    local pid = tonumber(source) or 0
    if pid > 0 then NcmGuide.withdraw(pid, args and args[1]) else
        local target = tonumber(args and args[1]); if target then NcmGuide.withdraw(target, args[2]) end
    end
end, false)
--- Leave a race you have already started. The counterpart to WITHDRAW, which refuses once a session holds you
--- and names this command in its refusal. Two-step: the first call asks, a second within 15 s commits.
local function forfeit(pid)
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then tell(pid, REASONS.no_driver); return end
    if not (NcmRace and NcmRace.forfeit) then tell(pid, "Race control is not available."); return end
    local ok, why = NcmRace.forfeit(driver.ncmDriverId, "forfeit")
    if ok or why == "confirm" then return end   -- both already spoke for themselves
    if why == "not_racing" then tell(pid, "You are not out in a race. /ncm.withdraw leaves a race you have entered but not started.")
    else tell(pid, "Could not retire you: " .. tostring(why)) end
end
NcmGuide.forfeit = forfeit
RegisterNetEvent("ncm:race.forfeit", function() forfeit(tonumber(source) or 0) end)
RegisterCommand("ncm.forfeit", function(source, args)
    local pid = tonumber(source) or 0
    if pid > 0 then forfeit(pid); return end
    -- console: ncm.forfeit <playerId>  -- no confirmation step, the operator already typed a player id
    local target = tonumber(args and args[1])
    if not target then log("usage: ncm.forfeit <playerId>"); return end
    local driver = NcmCalendar.resolveDriver(target)
    if not driver then log("ncm.forfeit: no NCM driver on player %d", target); return end
    local ok, why = NcmRace and NcmRace.forfeit and NcmRace.forfeit(driver.ncmDriverId, "race_control", true)
    log("ncm.forfeit player=%d -> %s", target, ok and "retired" or tostring(why))
end, false)

RegisterCommand("ncm.practice", function(source, args)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    if not (NcmRace and NcmRace.practiceBoard) then tell(pid, "Practice is not available."); return end
    local lines = NcmRace.practiceBoard(pid, args and args[1])
    if not lines or #lines == 0 then tell(pid, "No practice open for you. /ncm.guide → /ncm.interest <n> first."); return end
    for _, l in ipairs(lines) do tell(pid, l) end
end, false)

-- The Guide follows the calendar: refresh everyone's rows when the published calendar changes.
CreateThread(function()
    local last = nil
    while true do
        Wait(5000)
        local ok, sig = pcall(function() return GlobalState.ncmCalendar and GlobalState.ncmCalendar.signature end)
        if ok and sig ~= last then last = sig; NcmGuide.pushAll() end
    end
end)

log("race guide ready")
