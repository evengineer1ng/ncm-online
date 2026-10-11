-- ncm_league / server / calendar — the scheduler (M3.1; decision record L34, L37, P19, P20, L35).
--
-- Every tick: materialise the enabled series over the horizon (core competition.calendar), persist
-- new events, advance states (posted -> entry_open -> closed), publish the next events on
-- GlobalState.ncmCalendar, and send T-15/-5/-1 pings. `ncm:enter` (client, at the venue prompt) is
-- re-validated here with the server's own position read before an entry is written.
NcmCalendar = {}

local Core = NcmCore
local Cal = Core.get("competition.calendar")
local Entry = Core.get("competition.entry")
local ids = Core.get("vocabulary.ids")
local Json = Core.get("vocabulary.json")

local function log(fmt, ...)
    print(("[ncm_league/calendar] " .. fmt):format(...))
end

-- One declaration per resource (a second declare replaces the first -- observed 2026-09-20), so
-- the race controller's tunables live here too and race.lua reads NcmCalendar.settings.
local settings = Open77.tunables.declare({
    -- **`serverId` is an OPAQUE IDENTITY, not a statement about environment.** Every canonical row in the
    -- persistent world is keyed on it -- assets, ledger, events, discoveries, reports, QA evidence -- so
    -- changing it would orphan the entire history rather than rename it. The live world has been keyed
    -- `ncm-dev` since the first migration and **must keep that value forever**, however the server is branded.
    -- Renaming to NCM Online is a display and access change; it is not an identity change (L112).
    serverId = { value = "ncm-dev", type = "string", apply = "live" },
    -- Which ROLE this server plays. `development` is the safe default, so a fresh or misconfigured server is
    -- never mistaken for the world. Only the official server is deliberately set to `online`, via the
    -- platform's own tunables -- no second configuration file, no duplicated settings.
    environment = { value = "development", type = "string", apply = "live" },
    horizonMinutes = { value = 120, type = "integer", min = 30, max = 1440, unit = "min", apply = "live" },
    -- L250: Paddock races are the only organized races shown to players. Legacy league series remain in
    -- storage for standings/history, but are neither scheduled nor published as overworld events.
    guideFromPaddock = { value = true, type = "boolean", apply = "live" },
    -- L250: humans in Paddock races. On: the Paddock's next races are calendar events (class `paddock`) a driver can
    -- QUALIFY for and enter (server/paddock_link.lua); their grids are mixed, NPCs and humans.
    paddockEntries = { value = true, type = "boolean", apply = "live" },
    tickSeconds = { value = 10, type = "integer", min = 2, max = 60, unit = "s", apply = "live" },
    publishCount = { value = 3, type = "integer", min = 1, max = 10, apply = "live" },
    -- race control: sessions form when entries close (T-60 by the street pack's window)
    raceFormAtSec = { value = 60, type = "integer", min = 30, max = 600, unit = "s", apply = "live" },
    raceTickMs = { value = 1000, type = "integer", min = 250, max = 5000, unit = "ms", apply = "live" },
    raceResultHoldSec = { value = 60, type = "integer", min = 5, max = 300, unit = "s", apply = "live" },
    -- Player-called races (`server/impromptu.lua`, L178). BOTH of these exist because `KB-165` is a standing
    -- trap: a per-race permission is a permanent cadence. The cooldown bounds one driver, the cap bounds the
    -- board -- without the second, five drivers each obeying the first would still fill it.
    impromptuCooldownSec = { value = 60, type = "integer", min = 60, max = 7200, unit = "s", apply = "live" },   -- a floor; one call on the board per driver is the real limit (KB-187)
    impromptuMaxOpen = { value = 2, type = "integer", min = 0, max = 10, apply = "live" },
    -- chauffeur pickup for organized events (M7.5a): rides dispatched this long before the start
    pickupLeadSec = { value = 300, type = "integer", min = 90, max = 1800, unit = "s", apply = "live" },
    pickupSpeedMps = { value = 18, type = "number", min = 5, max = 40, unit = "m/s", apply = "live" },
    -- Batch 1: holding stage (organized events), telemetry, incidents, formats
    holdReleasePct = { value = 0.75, type = "number", min = 0.5, max = 1, apply = "live" },
    holdMaxWaitSec = { value = 60, type = "integer", min = 30, max = 300, unit = "s", apply = "live" },
    telemetryPersist = { value = 1, type = "integer", min = 0, max = 1, apply = "live" },
    telemetryDebug = { value = 0, type = "integer", min = 0, max = 1, apply = "live" },
    incidentBaseSec = { value = 2, type = "number", min = 0.5, max = 10, unit = "s", apply = "live" },
    sessionGapSec = { value = 90, type = "integer", min = 30, max = 600, unit = "s", apply = "live" },
    -- Parts economy (`server/components.lua`). **They live here because a second `declare` in this resource
    -- replaces the first**, which is the rule stated at the top of this block -- and `components.lua`
    -- learned it the hard way: its own declaration silently wiped `serverId` and `environment`, and the
    -- calendar started failing on reads that had worked for a week.
    --
    -- `restart` is NOT a valid apply timing on this platform. The three accepted values are `live`,
    -- `next_round` and `next_match`, and the declaration is REJECTED outright for anything else -- which
    -- takes the whole resource down with it, so this is not a soft failure.
    partsEnabled = { value = true, type = "boolean", apply = "live" },
    partsReleaseEpoch = { value = 0, type = "number", apply = "next_match" },
    partsRndSecret = { value = "ncm-dev-parts", type = "string", apply = "next_match" },
})
NcmCalendar.settings = settings

--- A car number for this entry, unique WITHIN THE EVENT (IDEA-312). A driver keeps the number they last
--- raced under when it is free, because a number people recognise is half the point of having one; otherwise
--- the lowest free number. Returns nil only if all 99 are taken, which would be a very good problem.
local function assignNumber(eventId, driverId)
    local taken = {}
    for _, r in ipairs(MySQL.query.await(
        "SELECT car_number FROM entry WHERE event_id = ? AND car_number IS NOT NULL", { eventId }) or {}) do
        taken[tonumber(r.car_number) or 0] = true
    end
    local prev = tonumber(MySQL.scalar.await(
        "SELECT car_number FROM entry WHERE ncm_driver_id = ? AND car_number IS NOT NULL " ..
        "ORDER BY COALESCE(checked_in_at, registered_at, 0) DESC LIMIT 1", { driverId }))
    if prev and not taken[prev] then return prev end
    for n = 1, 99 do if not taken[n] then return n end end
    return nil
end

local function serverId()
    local v = tostring(settings.serverId or "ncm-dev")
    return ids.isSlug(v) and v or "ncm-dev"
end

local hostRng = function() return math.random() end
local now = function() return Open77.time.unix() end
local publish                      -- defined in the Publication section; used by adopt() above it

local events = {}        -- eventId -> event (core slot + state + entries{driverId->entry})

-- KB-29: ONE definition of "how many are in this race". `interested` is a soft list (L35/P21/P52) and is never an
-- entrant; `withdrawn` is gone. Three call sites used to count this three different ways, so the same event
-- published `entry_open:0` and then logged `closed (1 entrant(s))` -- and the host's own `ncm.calendar` could not
-- tell interest from entry, which is exactly the state a tester window needs to be legible (L63).
local function countEntries(e)
    local entrants, interested = 0, 0
    for _, en in pairs((e and e.entries) or {}) do
        if en.state == "interested" then interested = interested + 1
        elseif en.state ~= "withdrawn" then entrants = entrants + 1 end
    end
    return entrants, interested
end
local order = {}         -- eventIds ascending by startsAt
-- `order` is rebound each tick; readers use the accessor.
function NcmCalendar.orderedIds() return order end
local pinged = {}        -- "eventId|playerId|key" -> true
local driverOf = {}      -- playerId -> { ncmDriverId, display }
NcmCalendar.events = events

-- ---------------------------------------------------------------------------------------------
-- Driver lookup (ncm_world owns minting; the binding table is the shared truth).
-- ---------------------------------------------------------------------------------------------
-- Ties broken by id: two races at the same minute used to swap places on every sort, which changed the
-- published signature every tick and resent every player's whole Guide every 10 s.
local function byStart(a, b)
    local x, y = events[a].startsAt, events[b].startsAt
    if x ~= y then return x < y end
    return a < b
end

-- NCM Observer (doc 46, L307): a connection in observer mode is a presence without a person -- no driver, so
-- nothing built on this lookup lets it enter, earn, buy or count. ncm_observer owns the list.
local function observing(id)
    local ok, o = pcall(function() return GlobalState.ncmObservers end)
    return ok and type(o) == "table" and o[tostring(id)] ~= nil
end

local function resolveDriver(playerId)
    local id = tonumber(playerId) or 0
    if observing(id) then return nil end
    if driverOf[id] then return driverOf[id] end
    local userId = GetPlayerIdentifier(id)
    if type(userId) ~= "string" or userId == "" or not MySQL.isReady() then return nil end
    local row = MySQL.single.await(
        "SELECT b.ncm_driver_id, p.display FROM ncm_driver_binding b " ..
        "LEFT JOIN driver_profile p ON p.ncm_driver_id = b.ncm_driver_id AND p.server_id = b.server_id " ..
        "WHERE b.server_id = ? AND b.user_id = ?", { serverId(), userId })
    if not row or not row.ncm_driver_id then return nil end
    driverOf[id] = { ncmDriverId = row.ncm_driver_id, display = row.display or GetPlayerName(id) }
    return driverOf[id]
end

AddEventHandler("onPlayerDisconnected", function(playerId)
    driverOf[tonumber(playerId) or 0] = nil
end)
NcmCalendar.resolveDriver = resolveDriver
NcmCalendar.serverId = serverId

--- Which world this is, and which role it plays.
---
--- `ncm_world` is a SEPARATE RESOURCE with its own Lua VM and cannot see `NcmCalendar` at all, so identity is
--- published to GlobalState rather than reached for across the boundary. That is not a nicety: on 2026-09-23
--- `driver_location` rows were written under `server_id = "ncm"` -- a fallback string in `ncm_world` -- while
--- every other canonical table used `ncm-dev`, because the cross-resource reference silently evaluated to nil.
--- One identity, published once, read everywhere.
function NcmCalendar.environment()
    local v = tostring(settings.environment or "development"):lower()
    -- `single_player` (the NCM Host, L338) is its own role: not Online, and not Development either -- no dev waivers.
    if v == "single_player" then return "single_player" end
    return (v == "online") and "online" or "development"
end

local function publishIdentity()
    pcall(function()
        GlobalState.ncmIdentity = { serverId = serverId(), environment = NcmCalendar.environment() }
    end)
end
NcmCalendar.publishIdentity = publishIdentity

-- ---------------------------------------------------------------------------------------------
-- Persistence helpers
-- ---------------------------------------------------------------------------------------------
local function copyTree(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k, x in pairs(v) do out[k] = copyTree(x) end; return out
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Twelve-race rolling signal, measured within the actual Paddock series. Neutral history prices at the
-- authored baseline. Betting is an optional signal: it contributes only when real win slips exist.
local intrigueCache = {}
local function seriesIntrigue(e)
    local series = e.paddockSeriesId or e.seriesId
    if not series then return 0.5, "warming up", 0 end
    local cached=intrigueCache[series]
    if cached and now()-cached.at<60 then return cached.score,cached.band,cached.sample end
    local ok, rows = pcall(MySQL.query.await, [[
        SELECT x.race_id,x.person_id,x.position,x.state,x.gap_ms,x.finish_ms,x.points,x.dnf_reason,x.at
        FROM paddock_result x JOIN (
            SELECT race_id,MAX(at) AS at FROM paddock_result
            WHERE server_id=? AND series_id=? GROUP BY race_id ORDER BY MAX(at) DESC LIMIT 12
        ) recent ON recent.race_id=x.race_id
        WHERE x.server_id=? AND x.series_id=? ORDER BY recent.at DESC,x.position ASC
    ]], {serverId(), series, serverId(), series})
    if not ok or type(rows) ~= "table" or #rows == 0 then
        local out={at=now(),score=0.5,band="warming up",sample=0}; intrigueCache[series]=out
        return out.score,out.band,out.sample
    end
    local races, order, seen = {}, {}, {}
    for _, r in ipairs(rows) do
        local id = tostring(r.race_id)
        if not races[id] then races[id] = {rows={}, at=tonumber(r.at) or 0}; order[#order+1]=id end
        races[id].rows[#races[id].rows+1]=r
    end
    table.sort(order, function(a,b) return races[a].at > races[b].at end)
    local closeness, clean, winners, points, crashRaces, raceN = 0, 0, {}, {}, 0, 0
    for _, id in ipairs(order) do
        local rr = races[id].rows; raceN=raceN+1
        local first, second, crashed, winner
        for _, r in ipairs(rr) do
            local p=tonumber(r.position) or 999
            if r.state == "finished" then
                points[tostring(r.person_id)] = (points[tostring(r.person_id)] or 0) + (tonumber(r.points) or math.max(0, 12-p))
                if p==1 then first=r; winner=tostring(r.person_id) end
                if p==2 then second=r end
            end
            local why=tostring(r.dnf_reason or ""):lower()
            if why=="crash" or why=="contact" or why=="wreck" then crashed=true end
        end
        if first and second then
            local gap=tonumber(second.gap_ms) or tonumber(second.finish_ms) and ((tonumber(second.finish_ms) or 0)-(tonumber(first.finish_ms) or 0)) or 999999
            closeness=closeness+(1-clamp(gap/10000,0,1))
        end
        if crashed then crashRaces=crashRaces+1 else clean=clean+1 end
        if winner then winners[winner]=(winners[winner] or 0)+1 end
    end
    local winnerKinds, maxWins=0,0
    for _, n in pairs(winners) do winnerKinds=winnerKinds+1; maxWins=math.max(maxWins,n) end
    local diversity=raceN>1 and clamp((winnerKinds-1)/(math.min(raceN,6)-1),0,1) or 0.5
    local dominance=raceN>1 and (1-clamp((maxWins/raceN-0.25)/0.75,0,1)) or 0.5
    local tablePts={}; for _, n in pairs(points) do tablePts[#tablePts+1]=n end; table.sort(tablePts,function(a,b)return a>b end)
    local titleFight=(tablePts[1] and tablePts[2]) and (1-clamp((tablePts[1]-tablePts[2])/math.max(1,tablePts[1]),0,1)) or 0.5
    local tok, standings=pcall(MySQL.query.await, [[SELECT person_id,SUM(points) AS points FROM paddock_result
        WHERE server_id=? AND series_id=?
          AND season_id=(SELECT season_id FROM paddock_race WHERE server_id=? AND series_id=? ORDER BY window_opens_at DESC LIMIT 1)
          AND cup_id=(SELECT cup_id FROM paddock_race WHERE server_id=? AND series_id=? ORDER BY window_opens_at DESC LIMIT 1)
        GROUP BY person_id ORDER BY points DESC LIMIT 2]], {serverId(),series,serverId(),series,serverId(),series})
    if tok and type(standings)=="table" and standings[1] and standings[2] then
        local a,b=tonumber(standings[1].points) or 0,tonumber(standings[2].points) or 0
        if a>0 then titleFight=1-clamp((a-b)/a,0,1) end
    end
    local close=closeness/math.max(1,raceN)
    local cleanRate=clean/math.max(1,raceN)
    local score=(0.34*close)+(0.25*titleFight)+(0.16*diversity)+(0.10*dominance)+(0.15*cleanRate)

    -- Betting splits are server-side evidence from actual Billie win slips, never predicted odds.
    local bok, bets=pcall(MySQL.query.await, [[SELECT s.subject_a,SUM(s.stake) AS stake FROM paddock_slip s
        JOIN (SELECT race_id FROM paddock_race WHERE server_id=? AND series_id=? ORDER BY window_opens_at DESC LIMIT 12) recent
          ON recent.race_id=s.race_id
        WHERE s.server_id=? AND s.market='win' AND s.state IN ('won','lost','open') GROUP BY s.subject_a]],
        {serverId(),series,serverId()})
    local stakeBySubject,total,subjects={},0,0
    if bok and type(bets)=="table" then for _,b in ipairs(bets) do local n=tonumber(b.stake) or 0; if n>0 then stakeBySubject[b.subject_a]=n;total=total+n;subjects=subjects+1 end end end
    if total>0 and subjects>1 then
        local hhi=0; for _,n in pairs(stakeBySubject) do hhi=hhi+(n/total)^2 end
        local balance=clamp((1-hhi)/(1-1/subjects),0,1)
        score=score*0.85+balance*0.15
    end
    score=clamp(score,0,1)
    local band=score>=0.68 and "electric" or score<=0.32 and "cooling" or "alive"
    intrigueCache[series]={at=now(),score=score,band=band,sample=raceN}
    return score,band,raceN
end

local function freezeEconomy(e)
    if type(e.economy)~="table" or e.economy.dynamicsFrozen then return end
    local econ=copyTree(e.economy)
    local score,band,sample=seriesIntrigue(e)
    local intrigue=0.70+0.60*score -- bounded 0.70x..1.30x; no history yields exactly 1x
    local wkfx={}; pcall(function() wkfx=GlobalState.ncmWeekFx or {} end)
    local scale=tonumber(econ.scale) or 1
    local tier=econ.purseTier or tostring(e.paddockSeriesId or ""):match("^(%a+)")
    if tier~="street" and tier~="regional" and tier~="pro" and tier~="premier" then
        tier=(scale>=200 and "premier") or (scale>=20 and "pro") or (scale>=2 and "regional") or "street"
    end
    local moody=clamp(tonumber(wkfx.purse and wkfx.purse[tier]) or 1,0.5,2.5)
    local purseFactor=intrigue*moody
    local function mul(v,f) return math.floor((tonumber(v) or 0)*f+0.5) end
    econ.entryFee=mul(econ.entryFee,intrigue)
    econ.timeTrialCompletion=mul(econ.timeTrialCompletion,purseFactor)
    econ.raceCompletion=mul(econ.raceCompletion,purseFactor)
    econ.repeatFloor=mul(econ.repeatFloor,purseFactor)
    econ.maxTagBounty=mul(econ.maxTagBounty,purseFactor)
    for k,v in pairs(econ.placement or {}) do econ.placement[k]=mul(v,purseFactor) end
    for k,v in pairs(econ.fieldBonus or {}) do econ.fieldBonus[k]=mul(v,purseFactor) end
    for k,v in pairs(econ.tagBounties or {}) do econ.tagBounties[k]=mul(v,purseFactor) end
    for _,v in ipairs(econ.targets or {}) do v.amount=mul(v.amount,purseFactor) end
    econ.intrigueScore=math.floor(score*100+0.5); econ.intrigueBand=band; econ.intrigueSample=raceN
    econ.intrigueFactor=math.floor(intrigue*100+0.5)/100; econ.moodyPurseTier=tier
    econ.moodyPurseFactor=math.floor(moody*100+0.5)/100; econ.dynamicsFrozen=true
    econ.id=tostring(econ.id or e.seriesId).."_live"; econ.version=(tonumber(econ.version) or 1)+1
    e.economy=econ
end

local function persistEvent(e)
    MySQL.insert.await(
        "INSERT IGNORE INTO event (event_id, server_id, class, series_id, series_name, ruleset_id, route_id, route_name, " ..
        "starts_at, entry_opens_at, entry_closes_at, venue_x, venue_y, venue_z, venue_name, state, invitation, registration, seats_total, pack_id, " ..
        "discipline_id, format_id, class_id, laps, economy_id, economy_version, economy_json) " ..
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, ''))",
        { e.eventId, serverId(), e.class or "calendar", e.seriesId, e.seriesName, e.rulesetId, e.routeId, e.routeName,
          math.floor(e.startsAt), math.floor(e.entryOpensAt), math.floor(e.entryClosesAt),
          e.venue.x, e.venue.y, e.venue.z, e.venue.name, e.state,
          e.invitation and 1 or 0, e.registration or "venue", e.seatsTotal or 0, e.packId or "",
          e.disciplineId or "street_sprint", e.formatId or "sprint", e.classId or "street_open", e.laps or 1,
          e.economy and e.economy.id or "", e.economy and e.economy.version or 0,
          e.economy and Json.encode(e.economy) or "" })
end

--- Adopt a one-off event (organized/invitation) into the calendar: persist, index, publish.
function NcmCalendar.adopt(e)
    if events[e.eventId] then return nil, "duplicate_event" end
    local saved=MySQL.single.await("SELECT economy_json FROM event WHERE server_id=? AND event_id=?",{serverId(),e.eventId})
    local frozen=saved and type(saved.economy_json)=="string" and Json.decode(saved.economy_json) or nil
    local hasEntries=type(e.entries)=="table" and next(e.entries)~=nil
    if type(frozen)=="table" and (frozen.dynamicsFrozen or hasEntries) then e.economy=frozen else freezeEconomy(e) end
    -- The await above yields: a second adopt of the same id can pass the first check meanwhile, and a
    -- duplicate in `order` later wedges every tick (KB: calendar.lua:545 from 2026-10-09 07:24).
    if events[e.eventId] then return nil, "duplicate_event" end
    events[e.eventId] = e
    order[#order + 1] = e.eventId
    table.sort(order, byStart)
    local ok, err = pcall(persistEvent, e)
    if not ok then log("adopt: persist failed: %s", tostring(err)) end
    if saved and type(e.economy)=="table" and e.economy.dynamicsFrozen and not (type(frozen)=="table" and frozen.dynamicsFrozen) and not hasEntries then
        pcall(MySQL.update.await,"UPDATE event SET economy_id=?,economy_version=?,economy_json=? WHERE server_id=? AND event_id=?",
            {e.economy.id,e.economy.version,Json.encode(e.economy),serverId(),e.eventId})
    end
    publish(now(), true)
    return true
end

function NcmCalendar.publishNow() publish(now(), true) end

-- Organized events are not produced by a cadence, so they are rebuilt from the database on start.
local function restoreOrganized(t)
    local rows = MySQL.query.await(
        "SELECT event_id, series_id, series_name, ruleset_id, route_id, route_name, starts_at, entry_opens_at, entry_closes_at, state, seats_total, pack_id, " ..
        "discipline_id, format_id, class_id, laps " ..
        "FROM event WHERE server_id = ? AND class = 'organized' AND starts_at >= ?", { serverId(), math.floor(t - 3600) }) or {}
    local Routes = Core.get("course.routes")
    local n = 0
    for _, r in ipairs(rows) do
        if not events[r.event_id] then
            local route = Routes.resolve(r.route_id, r.route_name)
            if route then
                events[r.event_id] = {
                    eventId = r.event_id, class = "organized", invitation = true, registration = "advance", packId = r.pack_id,
                    seriesId = r.series_id, seriesName = r.series_name, rulesetId = r.ruleset_id,
                    routeId = route.routeId, routeName = route.name,
                    startsAt = tonumber(r.starts_at), entryOpensAt = tonumber(r.entry_opens_at), entryClosesAt = tonumber(r.entry_closes_at),
                    venue = { x = route.start.x, y = route.start.y, z = route.start.z, heading = route.start.heading, name = route.start.name, nodeId = route.start.id },
                    finish = { x = route.finish.x, y = route.finish.y, z = route.finish.z, name = route.finish.name, nodeId = route.finish.id },
                    -- The authored intermediate points, carried on the event so the publication can hand the
                    -- racing line to anyone who needs the whole lap rather than its two ends (`L177`).
                    via = route.intermediate,
                    distanceM = route.distanceM, venueRadiusM = NcmPackNcx and NcmPackNcx.invitational.venueRadiusM or 40,
                    state = r.state, entries = {}, seatsTotal = tonumber(r.seats_total) or 0,
                    disciplineId = r.discipline_id or "ncx_formula", formatId = r.format_id or "sprint", classId = r.class_id or "ncx_rb15", laps = tonumber(r.laps) or 1,
                    economy = NcmPackNcx and NcmPackNcx.invitational.economy or nil,
                }
                order[#order + 1] = r.event_id
                if NcmOrganized and NcmOrganized.restore then NcmOrganized.restore(events[r.event_id]) end
                n = n + 1
            end
        end
    end
    return n
end

local function persistState(e)
    MySQL.update.await("UPDATE event SET state = ? WHERE event_id = ?", { e.state, e.eventId })
end

local function loadPersisted(t)
    -- Events already in the database (state + entries) for the horizon, so restarts do not forget entries.
    local rows = MySQL.query.await(
        "SELECT event_id, state, starts_at, entry_opens_at, entry_closes_at FROM event WHERE server_id = ? AND starts_at >= ?", { serverId(), math.floor(t - 3600) }) or {}
    local states = {}
    for _, r in ipairs(rows) do
        states[r.event_id] = { state = r.state, startsAt = tonumber(r.starts_at), entryOpensAt = tonumber(r.entry_opens_at), entryClosesAt = tonumber(r.entry_closes_at) }
    end
    local entries = MySQL.query.await(
        "SELECT en.entry_id, en.event_id, en.ncm_driver_id, en.state, en.fee, en.checked_in_at, en.registered_at, en.interested_at, en.team_id, en.seat_index FROM entry en " ..
        "JOIN event ev ON ev.event_id = en.event_id WHERE ev.server_id = ? AND ev.starts_at >= ?",
        { serverId(), math.floor(t - 3600) }) or {}
    return states, entries
end

-- ---------------------------------------------------------------------------------------------
-- Publication (public read model)
-- ---------------------------------------------------------------------------------------------
local lastPublished = ""
publish = function(t, force)
    local list = {}
    for _, eid in ipairs(order) do
        local e = events[eid]
        -- The soonest `publishCount`, and ALSO every race inside the ring lead: each one gets its own ring at its
        -- own venue (owner, 2026-09-28), and a client can only draw a ring for a race it has been told about.
        local inRingLead = (e.startsAt or 0) - t <= Entry.RING_LEAD_S and #list < Entry.RING_MAX
        local n, interested = countEntries(e)
        local hasDriverInterest = n > 0 or interested > 0
        local selectedForVenue = hasDriverInterest and #list < Entry.RING_MAX
        if e.class == "paddock" and e.state ~= "closed" and e.state ~= "cancelled" and
            (#list < (settings.publishCount or 3) or inRingLead or selectedForVenue) then
            local seatsTaken = 0
            if e.class == "organized" and NcmOrganized and NcmOrganized.rosters[e.eventId] then
                seatsTaken = Core.get("competition.teams").occupied(NcmOrganized.rosters[e.eventId])
            end
            list[#list + 1] = {
                eventId = e.eventId, seriesName = e.seriesName, routeName = e.routeName, routeId = e.routeId,
                class = e.class or "calendar", invitation = e.invitation and true or false, seatsTotal = e.seatsTotal or 0, seatsTaken = seatsTaken,
                startsAt = math.floor(e.startsAt), entryOpensAt = math.floor(e.entryOpensAt), entryClosesAt = math.floor(e.entryClosesAt),
                state = e.state, entries = n, interested = interested, distanceM = math.floor(e.distanceM),
                venue = { x = e.venue.x, y = e.venue.y, z = e.venue.z, name = e.venue.name },
                -- The finish CARRIES ITS COORDINATES (added with `L177`). It used to publish a name and
                -- nothing else, which was enough for the HUD line and not enough for anybody who needs
                -- the racing line itself. `ncm_world` clears ambient population out of a corridor before
                -- a start, and a corridor drawn from the grid box alone would clear a circle round the
                -- lights and leave the rest of the lap exactly as busy as it was. `via` is the authored
                -- intermediate list when the route has one; nil for a point-to-point.
                finish = { x = e.finish.x, y = e.finish.y, z = e.finish.z, name = e.finish.name },
                via = e.via,
            }
        end
    end
    local sig = {}
    for _, x in ipairs(list) do sig[#sig + 1] = x.eventId .. ":" .. x.state .. ":" .. x.entries end
    local signature = table.concat(sig, ",")
    -- serverNow lets clients run the countdown between publications; republish at least every tick.
    local snapshot = { next = list, serverNow = math.floor(t), signature = signature }
    -- A single unusually large route must not abort the event broadcast (or strand every venue ring).
    -- Calendar consumers only need a bounded route summary; oval `via` is the four authored marks from
    -- paddock.mixed, not one repeated checkpoint per lap.
    local okState, stateErr = pcall(function() GlobalState.ncmCalendar = snapshot end)
    if not okState then log("calendar state-bag publish refused; sending client snapshot directly: %s", tostring(stateErr)) end
    -- Production clients do not currently receive this GlobalState key (the live client logged it absent for
    -- its entire session while the server kept publishing it). Send the same small read model explicitly on
    -- every calendar tick. A late join therefore needs no request/replay path, and GlobalState remains a
    -- harmless fallback for hosts where replication does work.
    for _, pid in ipairs(Open77.players.all()) do
        TriggerClientEvent("ncm:calendar", pid, snapshot)
    end
    -- Republished alongside the calendar: the tunables are `apply = "live"`, so an operator flipping
    -- `environment` in Warden takes effect without a restart, and ncm_world sees it on the next tick.
    publishIdentity()
    if signature ~= lastPublished or force then
        lastPublished = signature
        log("published %d upcoming: %s", #list, signature)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Pings
-- ---------------------------------------------------------------------------------------------
local PING_TEXT = {
    t15 = "in 15 minutes",
    t5 = "in 5 minutes — be at the start or be square",
    t1 = "in 1 minute — entries close now",
}

local function sendPings(t)
    local players = Open77.players.all()
    for _, eid in ipairs(order) do
        local e = events[eid]
        if e.class == "paddock" and e.state ~= "closed" and e.state ~= "cancelled" then
            for _, pid in ipairs(players) do
                -- Owner, 2026-09-22: pings go ONLY to drivers who have asked for this event. Everyone else is
                -- funnelled to the Race Guide, which is the one place races are browsed.
                --
                -- This used to toast every connected player about every open event. That was merely noisy with
                -- one series; with five championships posting on independent cadences it is five times the
                -- traffic, for races the player never expressed any interest in. An unsolicited countdown is
                -- also the wrong shape of message: it announces something the player cannot act on from where
                -- they are standing, which is exactly the "made you hesitate about what to do next" failure.
                local mine = e.entries and driverOf[pid] and e.entries[driverOf[pid].ncmDriverId] or nil
                local wants = mine ~= nil and mine.state ~= "withdrawn"
                if wants then
                    local sentKey = eid .. "|" .. tostring(pid) .. "|"
                    local sent = { t15 = pinged[sentKey .. "t15"], t5 = pinged[sentKey .. "t5"], t1 = pinged[sentKey .. "t1"] }
                    for _, key in ipairs(Entry.pingsDue(e, t, sent)) do
                        pinged[sentKey .. key] = true
                        local entered = mine.state == "checked_in"
                        pcall(Open77.notifications.send, pid, {
                            type = "success",
                            title = e.seriesName .. " · " .. e.routeName,
                            message = ("%s. Start: %s. %s"):format(PING_TEXT[key], e.venue.name,
                                entered and "You're entered." or "You're on the list — enter at the line."),
                            icon = "NCM", durationMs = 9000,
                        })
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------------------------
local seriesList = {}

local function tick()
    local t = now()
    local horizon = (settings.horizonMinutes or 120) * 60
    local lists = {}
    -- L238/KB-211: every generated slot resolves a route, and seven series over a two-hour horizon is ~40 slots;
    -- one slice for all of it exceeded the instruction quota and killed this thread on boot. Yield per series.
    -- This is now a product rule, not an operator toggle: all legacy league series are retired from discovery.
    local fold = true
    for _, s in ipairs(seriesList) do
        if not fold then lists[#lists + 1] = Cal.materialize(s, t, horizon) end
        Wait(0)
    end
    local merged = Cal.merge(lists)
    local seen, posted = {}, 0
    for _, slot in ipairs(merged) do
        seen[slot.eventId] = true
        if not events[slot.eventId] then
            slot.state = "posted"
            slot.postedAt = t
            slot.entries = {}
            slot.venueRadiusM = nil
            for _, s in ipairs(seriesList) do if s.seriesId == slot.seriesId then slot.venueRadiusM = s.venueRadiusM end end
            events[slot.eventId] = slot
            order[#order + 1] = slot.eventId
            persistEvent(slot)
            posted = posted + 1
            if posted % 4 == 0 then Wait(0) end
            log("posted %s | %s · %s | start in %s | venue %s", slot.eventId, slot.seriesName, slot.routeName, Entry.countdown(slot.startsAt - t), slot.venue.name)
        end
    end
    -- Self-heal `order`: drop ids with no event and any duplicate, so one bad id cannot wedge the calendar.
    do
        local clean, have = {}, {}
        for _, eid in ipairs(order) do
            if events[eid] and not have[eid] then have[eid] = true; clean[#clean + 1] = eid end
        end
        if #clean ~= #order then log("order repaired: %d stale/duplicate id(s) dropped", #order - #clean) end
        order = clean
    end
    -- State advance.
    for _, eid in ipairs(order) do
        local e = events[eid]
        local before = e.state
        if e.state == "posted" and t >= e.entryOpensAt then e.state = "entry_open" end
        if (e.state == "posted" or e.state == "entry_open") and t >= e.startsAt then e.state = "closed" end
        if e.state ~= before then
            persistState(e)
            local n, onList = countEntries(e)
            log("%s -> %s (%d entrant(s)%s)", eid, e.state, n,
                onList > 0 and (", %d on the list"):format(onList) or "")
        end
    end
    -- Drop events that ended more than an hour ago from memory.
    local kept = {}
    for _, eid in ipairs(order) do
        local e = events[eid]
        if e.startsAt > t - 3600 then kept[#kept + 1] = eid else events[eid] = nil end
    end
    order = kept
    table.sort(order, byStart)
    sendPings(t)
    publish(t)
end

function NcmCalendar.start(series)
    seriesList = {}
    for _, s in ipairs(series) do
        local ok, why = Cal.validateSeries(s)
        if ok then
            seriesList[#seriesList + 1] = s
            -- IDEA-111/113: a championship whose eligibility spec admits nothing will refuse every entry with
            -- `championship_admits_nothing`. That is the operator's mistake, and it should surface at boot --
            -- when the data was edited -- rather than as a confused driver at a venue an hour later.
            local Elig = NcmCore.get("competition.eligibility")
            local n = #Elig.recordsFor(s.eligibility or {})
            if n == 0 then
                log("WARNING: series %s admits 0 vehicles -- every entry will be refused. CHECK ITS ELIGIBILITY SPEC.", tostring(s.seriesId))
            else
                log("series %s: every %d min, %d route(s), %d eligible vehicle(s)",
                    tostring(s.seriesId), math.floor(s.cadence.everyMinutes), #s.routes, n)
            end
        else
            log("series %s rejected: %s", tostring(s.seriesId), tostring(why))
        end
    end
    CreateThread(function()
        local t = now()
        local okLoad, states, entries = pcall(loadPersisted, t)
        local okOrg, nOrg = pcall(restoreOrganized, t)
        if okOrg then log("restored %d organized event(s)", nOrg or 0) else log("could not restore organized events: %s", tostring(nOrg)) end
        local okTick, errTick = pcall(tick)
        if not okTick then log("first tick error: %s", tostring(errTick)) end
        if okLoad then
            for eid, st in pairs(states) do
                local e = events[eid]
                if e then
                    -- The database is the truth for times too: a pulled-forward start (ncm.race.now) must
                    -- not snap back to the cadence slot on restart and re-form a zombie session.
                    if st.startsAt then e.startsAt, e.entryOpensAt, e.entryClosesAt = st.startsAt, st.entryOpensAt or e.entryOpensAt, st.entryClosesAt or e.entryClosesAt end
                    if st.state == "closed" or st.state == "cancelled" then e.state = st.state end
                end
            end
            table.sort(order, byStart)
            for _, r in ipairs(entries) do
                local e = events[r.event_id]
                if e then e.entries[r.ncm_driver_id] = { entryId = r.entry_id, state = r.state, fee = tonumber(r.fee) or 0, checkedInAt = tonumber(r.checked_in_at), registeredAt = tonumber(r.registered_at), interestedAt = tonumber(r.interested_at), teamId = r.team_id, seatIndex = tonumber(r.seat_index) } end
            end
            log("restored %d persisted event state(s), %d entr(ies)", (function() local n = 0 for _ in pairs(states) do n = n + 1 end return n end)(), #entries)
        else
            log("could not load persisted events: %s", tostring(states))
        end
        publish(now(), true)
        while true do
            Wait((settings.tickSeconds or 10) * 1000)
            local ok, err = pcall(tick)
            if not ok then log("tick error: %s", tostring(err)) end
        end
    end)
    log("scheduler started: %d series, horizon %d min, tick %d s", #seriesList, settings.horizonMinutes or 120, settings.tickSeconds or 10)
end

-- ---------------------------------------------------------------------------------------------
-- Entry at the venue (L35). The client only says "I pressed enter on event X"; everything else is ours.
-- ---------------------------------------------------------------------------------------------
local function tell(playerId, text)
    pcall(Open77.chat.send, playerId, "[NCM] " .. text)
end

--- opts.switchFrom = the eventId of the entry the driver confirmed giving up for this one (venue CONFIRM SWITCH).
--- One entry at a time (owner, 2026-09-28): without it, an entry held elsewhere refuses this one.
local function enterPlayer(pid, eventId, opts)
    opts = opts or {}
    CreateThread(function()
        local e = events[tostring(eventId or "")]
        if not e then tell(pid, "That race is not on the calendar."); return end
        if NcmRace and NcmRace.hasSession and NcmRace.hasSession(e.eventId) then tell(pid, "The grid is already forming for this one."); return end
        if e.invitation then tell(pid, "This one is by invitation — a team has to offer you a seat."); return end
        local driver = resolveDriver(pid)
        if not driver then tell(pid, "No NCM driver on this session."); return end
        -- L249: a Street Call time trial is its caller's alone
        if e.timeTrial and e.calledBy ~= driver.ncmDriverId then tell(pid, "That is someone's time trial."); return end
        -- KB-37: one session at a time. Holding entries on two events is what let a driver be classified DNS
        -- for a race that started while they were out on track in another.
        local busySid, busyEvent, busyKind = NcmRace and NcmRace.busySession and NcmRace.busySession(driver.ncmDriverId)
        -- L114: same-event practice is allowed to proceed through every entry validation. It is released only
        -- after the durable entry write succeeds, so a stale/invalid ENTER press cannot destroy a practice run.
        local sameEventPractice = busySid and busyEvent == e.eventId and busyKind == "practice"
        if sameEventPractice then busySid = nil end
        if busySid then
            tell(pid, "You're still out in a session. Finish it or retire before entering another race.")
            log("enter refused player=%d event=%s reason=in_live_session other_event=%s session=%s",
                pid, e.eventId, tostring(busyEvent), tostring(busySid):sub(1, 8))
            return
        end
        -- L83/IDEA-113: bring your own car. Refused, never substituted -- handing them a compliant car instead
        -- would make the eligibility rule meaningless and the earned car worthless. The venue list already
        -- hides ENTER RACE for this, so reaching here means a stale client or a console entry; either way the
        -- server is the one that decides.
        if NcmCompetition and NcmCompetition.carRefusal then
            local why, admits = NcmCompetition.carRefusal(e, driver.ncmDriverId)
            if why == "no_eligible_car" then
                tell(pid, ("You don't own a car eligible for %s. %d car(s) qualify -- earn or bring one of those."):format(
                    tostring(e.seriesName or "this race"), tonumber(admits) or 0))
                log("enter refused player=%d event=%s reason=no_eligible_car admits=%d", pid, e.eventId, tonumber(admits) or 0)
                return
            elseif why then
                -- the championship itself admits nothing: an operator's mistake, not the driver's, and it must
                -- not be reported as though they did something wrong
                tell(pid, "This race is not accepting entries right now.")
                log("enter refused player=%d event=%s reason=%s (CHECK THE SERIES ELIGIBILITY SPEC)", pid, e.eventId, tostring(why))
                return
            end
        end
        -- IDEA-312: an entry names a MACHINE, not just a driver who owns something legal. The car they drove
        -- up in wins if it is eligible.
        local seated = NcmRace and NcmRace.seatedAsset and NcmRace.seatedAsset(pid) or nil
        local enteredAsset = NcmCompetition and NcmCompetition.enterMachine
            and NcmCompetition.enterMachine(e, driver.ncmDriverId, seated) or nil
        local p = Open77.players.get(pid)
        -- The switch is honoured only for the exact entry the driver confirmed giving up. Anything else held
        -- elsewhere still refuses, so a stale confirm cannot release a race they never saw named.
        local held = NcmGuide and NcmGuide.heldEntry and NcmGuide.heldEntry(driver.ncmDriverId, e.eventId) or nil
        local switchFrom = held and opts.switchFrom and held.eventId == opts.switchFrom and held or nil
        local decision = Entry.checkIn({
            event = e, now = now(), driverId = driver.ncmDriverId,
            position = p and p.fresh and p.position or nil,
            existingEntry = e.entries[driver.ncmDriverId],
            heldElsewhere = (held and not switchFrom) and held or nil,
            radiusM = e.venueRadiusM, rng = hostRng,
            fee = (NcmCompetition.economyFor(e) or {}).entryFee or 0,
        })
        if not decision.ok then
            local why = decision.reason
            local text = ({
                already_entered = "You're already entered.",
                window_not_open = ("Too early: entries open in %s (%d min before the start). Stick around."):format(
                    Entry.countdown(decision.opensIn or 0), math.floor((e.startsAt - e.entryOpensAt) / 60 + 0.5)),
                window_closed = "Entries are closed for this one.",
                not_at_venue = ("You need to be at the start (%d m away)."):format(math.floor(decision.distanceM or 0)),
                position_unknown = "Position not fresh yet, try again.",
                entered_elsewhere = ("You're entered in %s. Use SWITCH ENTRY at this ring to move to this race."):format(
                    tostring(held and held.routeName or "another race")),
            })[why] or ("Cannot enter: " .. tostring(why))
            tell(pid, text)
            log("enter refused player=%d event=%s reason=%s", pid, e.eventId, tostring(why))
            return
        end
        local en = decision.entry
        -- Set BEFORE the write: the insert below persists these, and an entry that names no machine is the
        -- gap IDEA-312 exists to close.
        en.assetId = enteredAsset
        if enteredAsset and not en.carNumber then en.carNumber = assignNumber(e.eventId, driver.ncmDriverId) end
        local okCall, paid, payWhy = pcall(NcmEconomy.checkIn, {
            economy=NcmCompetition.economyFor(e), unpaid=NcmEconomy.isUnpaid(e), upgraded=decision.upgraded, entryId=en.entryId,
            eventId=e.eventId, seriesId=e.seriesId, driverId=driver.ncmDriverId, checkedInAt=en.checkedInAt,
            assetId=en.assetId, carNumber=en.carNumber,
        })
        if not okCall or not paid then
            local why = okCall and tostring(payWhy or "insufficient balance") or tostring(paid)
            tell(pid, "Entry refused: " .. why .. ". Check /ncm.balance.")
            log("entry economic refusal player=%d event=%s reason=%s",pid,e.eventId,why)
            return
        end
        if sameEventPractice and NcmRace and NcmRace.practiceLeave then
            NcmRace.practiceLeave(e.eventId, driver.ncmDriverId, now(), "entered_race")
        end
        e.entries[driver.ncmDriverId] = en
        -- The other half of a confirmed switch, done only now that this entry is written and paid: a refused
        -- entry must never have cost the driver the race they already held. Withdrawal forfeits that race's fee
        -- under the ordinary rule; the confirm text said so.
        if switchFrom and NcmGuide and NcmGuide.withdraw then
            local okW, whyW = NcmGuide.withdraw(pid, switchFrom.eventId)
            if not okW then
                log("SWITCH INCOMPLETE player=%d kept=%s entered=%s reason=%s", pid, switchFrom.eventId, e.eventId, tostring(whyW))
                tell(pid, ("You're in %s, but %s could not be released (%s). Withdraw from it at its ring."):format(
                    e.routeName, tostring(switchFrom.routeName), tostring(whyW)))
            else
                log("SWITCH player=%d from=%s to=%s", pid, switchFrom.eventId, e.eventId)
            end
        end
        -- Through the one writer (KB-75/L107). This used to set the bag itself, which also skipped the Guide's
        -- record of what it had published, so the refresh never corrected it again.
        if NcmGuide and NcmGuide.refreshEntryBag then NcmGuide.refreshEntryBag(pid) end
        tell(pid, ("You're in: %s · %s. Start in %s. Entry -€$%d · balance €$%d."):format(e.seriesName, e.routeName, Entry.countdown(e.startsAt - now()), paid.fee, paid.balance))
        if e.class == "paddock" and not (NcmPaddockLink and NcmPaddockLink.bests
            and NcmPaddockLink.bests[e.eventId] and NcmPaddockLink.bests[e.eventId][driver.ncmDriverId]) then
            tell(pid, "No qualifying time yet. You are entered; qualify here before T-11 to improve your grid place. If you do not qualify in time, you remain entered and start last.")
        end
        if NcmComms then
            NcmComms.acknowledge(pid,"race.interest.registered")
            NcmComms.send(pid,{id="race.entry:"..e.eventId,category="confirmation",priority="actionable",
                title="ENTERED · -€$"..paid.fee,
                message=e.routeName.." · grid place recorded · balance €$"..paid.balance.." · wait for race control",
                reference="driver",surface="toast",repeatPolicy={mode="once"}})
        end
        log("ENTERED player=%d driver=%s event=%s entry=%s dist=%.1fm%s", pid, driver.ncmDriverId, e.eventId, en.entryId, en.distanceM or -1, decision.upgraded and " (from interest)" or "")
        -- L250: an entry at the line with no qualifying time is still an entry -- it starts at the back
        if e.class == "paddock" and NcmPaddockLink then NcmPaddockLink.announce(e, driver.ncmDriverId, driver.display, "entered") end
        -- Navigation intent changes HERE, not at lights-out (owner QA 2026-09-23). The venue GPS has served
        -- its purpose the moment the driver is standing at the venue and entered; from now on the useful
        -- destination is the course. Doing it now is also what buys them time to notice a route line that has
        -- not drawn and refresh it themselves BEFORE the clock starts.
        local courseTarget = NcmRace and NcmRace.courseTarget and NcmRace.courseTarget(e) or nil
        if courseTarget then
            courseTarget.why = "entered"
            TriggerClientEvent("ncm:guide.route", pid, courseTarget)
            log("entry navigation player=%d event=%s -> %s", pid, e.eventId, tostring(courseTarget.name))
        end
        publish(now(), true)
        if NcmGuide and NcmGuide.pushAll then NcmGuide.pushAll() end
    end)
end

-- IDEA-095: the venue option list engages entry through this, so the option and the prompt share one path.
NcmCalendar.enter = enterPlayer

RegisterNetEvent("ncm:enter", function(eventId)
    enterPlayer(tonumber(source) or 0, eventId)   -- never a switch: that is only ever the venue's two-press confirm
end)

-- Server console (KB-4: a second local instance has no chat and no key input at the prompt):
--   ncm.enter <playerId> [eventId]   -- same validation as the prompt; defaults to the next open event
RegisterCommand("ncm.enter", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.enter <playerId> [eventId]"); return end
    local eid = args[2]
    if not eid then
        for _, x in ipairs(order) do
            if events[x].state == "entry_open" then eid = x; break end
        end
    end
    if not eid then log("ncm.enter: no event with entries open"); return end
    enterPlayer(pid, eid)
end, false)

-- Dev/admin: pull the next open race to start in 2 minutes (entries stay open for the first minute,
-- the grid forms at T-60). Server console only in practice; it is not ACL-restricted on the dev box.
-- ncm.race.now [route]   e.g. ncm.race.now snake | bline | tip  (matches the route name, case-insensitive)
RegisterCommand("ncm.race.now", function(source, args)
    local t = now()
    local want = args and args[1] and tostring(args[1]):lower():gsub("[^%w]", "") or nil
    for _, eid in ipairs(order) do
        local e = events[eid]
        local routeKey = tostring(e.routeName or ""):lower():gsub("[^%w]", "")
        local matches = (not want) or routeKey:find(want, 1, true) ~= nil
        -- posted/open events, or a closed one that never actually raced (a burned pull); never a cancelled or raced one
        local eligible = e.state == "posted" or e.state == "entry_open" or (e.state == "closed" and not (NcmRace and NcmRace.raced and NcmRace.raced(eid)))
        if matches and eligible and not (NcmRace and NcmRace.hasSession and NcmRace.hasSession(eid)) then
            e.startsAt = t + 180
            e.entryOpensAt = t
            e.entryClosesAt = t + 120
            e.state = "entry_open"
            if NcmRace and NcmRace.forget then NcmRace.forget(e.eventId) end
            pcall(function()
                MySQL.update.await("UPDATE event SET starts_at = ?, entry_opens_at = ?, entry_closes_at = ?, state = ? WHERE event_id = ?",
                    { math.floor(e.startsAt), math.floor(e.entryOpensAt), math.floor(e.entryClosesAt), e.state, e.eventId })
            end)
            table.sort(order, byStart)
            publish(t, true)
            for _, pid in ipairs(Open77.players.all()) do
                pcall(Open77.notifications.send, pid, { type = "warning", title = "RACE PULLED FORWARD", message = e.routeName .. " starts in 3:00 — enter at " .. e.venue.name .. " within 2:00", icon = "NCM", durationMs = 9000 })
            end
            log("race.now: %s now starts at +3:00 (entries close +2:00)", eid)
            return
        end
    end
    log("race.now: no open event to pull forward%s", want and (" matching '" .. want .. "'") or "")
end, false)

RegisterCommand("ncm.calendar", function(source)
    local t = now()
    log("calendar now=%d | %d event(s) in memory", math.floor(t), #order)
    for _, eid in ipairs(order) do
        local e = events[eid]
        local n, onList = countEntries(e)
        log("  %-40s %-11s start in %8s  %s -> %s  entrants=%d%s", eid, e.state, Entry.countdown(e.startsAt - t),
            e.venue.name, e.finish.name, n, onList > 0 and (" (+%d on the list)"):format(onList) or "")
    end
end, false)
