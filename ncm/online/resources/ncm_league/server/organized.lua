-- ncm_league / server / organized — organized (invitation-only) events, teams, seats, the sorting hat
-- and race control (M4-lite; L18, L19, L45, P21, L43).
--
-- An organized event is posted once (not from a cadence), carries a roster of team seats, and is
-- entered by accepting an offer, not at the venue prompt (L35 still holds for the car: you must be on
-- your mark). The offer itself is a placeholder for NCM Messages v0 (P23): a toast + chat line.
NcmOrganized = {}

local Core = NcmCore
local Teams = Core.get("competition.teams")
local Entry = Core.get("competition.entry")
local Routes = Core.get("course.routes")
local ids = Core.get("vocabulary.ids")

local function log(fmt, ...)
    print(("[ncm_league/organized] " .. fmt):format(...))
end

local now = function() return Open77.time.unix() end
local hostRng = function() return math.random() end

local rosters = {}      -- eventId -> roster (core competition.teams)
local offers = {}       -- driverId -> { eventId, seat, offeredAt }
NcmOrganized.rosters = rosters

local function tell(pid, text)
    if pid then pcall(Open77.chat.send, pid, "[NCX] " .. text) end
end

local function toast(pid, def)
    if pid then pcall(Open77.notifications.send, pid, def) end
end

-- ---------------------------------------------------------------------------------------------
-- Teams: seed the pack's teams into the database once per server.
-- ---------------------------------------------------------------------------------------------
function NcmOrganized.seedTeams()
    local sid = NcmCalendar.serverId()
    local ids = {}
    for _, t in ipairs(Teams.NCX) do
        ids[#ids + 1] = t.teamId
        pcall(function()
            MySQL.insert.await(
                "INSERT INTO team (server_id, team_id, pack_id, name, short, colour, livery, seats) VALUES (?, ?, ?, ?, ?, ?, ?, ?) " ..
                "ON DUPLICATE KEY UPDATE name = VALUES(name), short = VALUES(short), colour = VALUES(colour), livery = VALUES(livery), seats = VALUES(seats)",
                { sid, t.teamId, NcmPackNcx.packId, t.name, t.short, t.colour, t.livery, Teams.SEATS_PER_TEAM })
        end)
    end
    -- teams renamed to their livery keys (borton -> thorton, miyutsaki -> mizutani): drop rows no longer in the pack
    pcall(function()
        MySQL.update.await(
            "DELETE FROM team WHERE server_id = ? AND pack_id = ? AND team_id NOT IN ('" .. table.concat(ids, "','") .. "')",
            { sid, NcmPackNcx.packId })
        MySQL.update.await("DELETE FROM team_car WHERE server_id = ? AND team_id NOT IN ('" .. table.concat(ids, "','") .. "')", { sid })
    end)
    local cars = 0
    for _, t in ipairs(Teams.NCX) do
        for _, car in ipairs(Teams.cars(t.teamId)) do
            cars = cars + 1
            pcall(function()
                MySQL.insert.await(
                    "INSERT INTO team_car (server_id, team_id, car_index, vehicle_def, livery, number) VALUES (?, ?, ?, ?, ?, ?) " ..
                    "ON DUPLICATE KEY UPDATE vehicle_def = VALUES(vehicle_def), livery = VALUES(livery), number = VALUES(number)",
                    { sid, car.teamId, car.carIndex, car.record, car.livery, car.number })
            end)
        end
    end
    log("teams seeded: %d (%s), %d team cars", #Teams.NCX, NcmPackNcx.packId, cars)
end

-- ---------------------------------------------------------------------------------------------
-- NCM Messages v0 (P30): the seat offer is a persisted message from the first offer on. Delivery is
-- still toast + chat; the Messages panel (M7.5) reads the same rows.
-- ---------------------------------------------------------------------------------------------
local function messageCreate(driverId, m)
    local id = ids.uuid4(hostRng)
    pcall(function()
        MySQL.insert.await(
            "INSERT INTO message (message_id, server_id, to_driver_id, from_kind, from_id, kind, subject, body, actions, state, ref_kind, ref_id, created_at, expires_at) " ..
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'unread', ?, ?, ?, ?)",
            { id, NcmCalendar.serverId(), driverId, m.fromKind or "system", m.fromId, m.kind, m.subject, m.body,
              m.actions and ("[\"" .. table.concat(m.actions, "\",\"") .. "\"]") or nil, m.refKind, m.refId, math.floor(now()), m.expiresAt and math.floor(m.expiresAt) or nil })
    end)
    return id
end

local function messageResolve(messageId, state)
    if not messageId then return end
    pcall(function()
        MySQL.update.await("UPDATE message SET state = ?, resolved_at = ? WHERE message_id = ?", { state, math.floor(now()), messageId })
    end)
end

--- The driver's inbox (unread/read, newest first; expired offers flip to `expired` lazily).
local function messageList(driverId)
    if not MySQL.isReady() then return {} end
    local t = math.floor(now())
    local rows = {}
    pcall(function()
        MySQL.update.await("UPDATE message SET state = 'expired' WHERE server_id = ? AND to_driver_id = ? AND state IN ('unread','read') AND expires_at IS NOT NULL AND expires_at < ?",
            { NcmCalendar.serverId(), driverId, t })
        -- Lifecycle (owner QA): open messages always; resolved ones (accepted/declined/expired) for 6 h, then archived
        -- (the rows stay; the thread stops showing them).
        rows = MySQL.query.await(
            "SELECT message_id, from_kind, from_id, kind, subject, body, actions, state, ref_kind, ref_id, created_at, expires_at FROM message " ..
            "WHERE server_id = ? AND to_driver_id = ? AND (state IN ('unread','read') OR (state IN ('accepted','declined','expired') AND created_at > ?)) " ..
            "ORDER BY created_at DESC LIMIT 20",
            { NcmCalendar.serverId(), driverId, t - 6 * 3600 }) or {}
    end)
    local out, unread = {}, 0
    for i, r in ipairs(rows) do
        if r.state == "unread" then unread = unread + 1 end
        local actions = {}
        for a in tostring(r.actions or ""):gmatch('"([%w_]+)"') do actions[#actions + 1] = a end
        out[i] = { id = r.message_id, n = i, fromKind = r.from_kind, fromId = r.from_id, kind = r.kind, subject = r.subject, body = r.body,
                   actions = actions, state = r.state, refId = r.ref_id, createdAt = tonumber(r.created_at), expiresAt = tonumber(r.expires_at) }
    end
    return out, unread
end
NcmOrganized.messageList = messageList

local function messageRead(messageId, driverId)
    pcall(function()
        MySQL.update.await("UPDATE message SET state = 'read' WHERE message_id = ? AND to_driver_id = ? AND state = 'unread'", { messageId, driverId })
    end)
end

--- Push the inbox to the player's bag (the panel renders it; chat has /ncm.inbox).
local function pushInbox(pid, driverId)
    if not pid then return end
    local items, unread = messageList(driverId)
    pcall(function()
        Open77.state.player(pid):set("ncmInbox", { items = items, unread = unread, at = math.floor(now()) })
    end)
    return items, unread
end
NcmOrganized.pushInbox = pushInbox

--- The affinity vector from the driver's onboarding document (P29), or nil.
function NcmOrganized.loadAffinity(driverId)
    if not MySQL.isReady() then return nil end
    local ok, row = pcall(function()
        return MySQL.single.await("SELECT onboarding_json FROM driver_profile WHERE ncm_driver_id = ? AND server_id = ?", { driverId, NcmCalendar.serverId() })
    end)
    if not ok or not row or not row.onboarding_json then return nil end
    local doc = row.onboarding_json
    if type(doc) == "string" then doc = Core.get("vocabulary.json").decode(doc) end
    return type(doc) == "table" and type(doc.affinity) == "table" and doc.affinity or nil
end

-- ---------------------------------------------------------------------------------------------
-- Posting an organized event
-- ---------------------------------------------------------------------------------------------
local function routeByLabel(label)
    local roots = Core.get("data.roots")
    local want = tostring(label or ""):lower():gsub("[^%w]", "")
    for _, r in ipairs(roots.LIST) do
        local key = tostring(r.displayName or ""):lower():gsub("[^%w]", "")
        if key:find(want, 1, true) or r.rootId:lower():find(want, 1, true) then return r end
    end
    return nil
end

--- Post an invitational at T+minutes on a route. Returns the event or nil, reason.
function NcmOrganized.post(routeLabel, minutes, opts)
    opts = opts or {}
    local root = routeByLabel(routeLabel)
    if not root then return nil, "unknown_route" end
    local streetLabel = nil
    for _, s in ipairs(NcmPackStreet.series) do
        for _, r in ipairs(s.routes) do if r.rootId == root.rootId then streetLabel = r.label end end
    end
    local route = Routes.resolve(root.rootId, streetLabel or root.displayName)
    if not route then return nil, "route_unresolved" end
    local t = now()
    local inv = NcmPackNcx.invitational
    local startsAt = math.floor(t + (tonumber(minutes) or 10) * 60)
    local e = {
        eventId = ("%s@%d"):format(inv.seriesId, startsAt),
        class = "organized", invitation = true, registration = "advance", packId = NcmPackNcx.packId,
        seriesId = inv.seriesId, seriesName = inv.seriesName, rulesetId = inv.rulesetId,
        routeId = route.routeId, routeName = route.name,
        startsAt = startsAt, entryOpensAt = math.floor(t), entryClosesAt = startsAt - inv.entryClosesBeforeSec,
        venue = { x = route.start.x, y = route.start.y, z = route.start.z, heading = route.start.heading, name = route.start.name, nodeId = route.start.id },
        finish = { x = route.finish.x, y = route.finish.y, z = route.finish.z, name = route.finish.name, nodeId = route.finish.id },
        distanceM = route.distanceM, venueRadiusM = inv.venueRadiusM,
        state = "entry_open", entries = {},
        seatsTotal = #Teams.NCX * Teams.SEATS_PER_TEAM,
        -- vocabulary (L53): the pack's defaults, overridable per post (ncm.event.post <route> <min> [format])
        disciplineId = opts.disciplineId or inv.disciplineId or "ncx_formula",
        formatId = opts.formatId or inv.formatId or "sprint",
        classId = opts.classId or inv.classId or "ncx_rb15",
        laps = opts.laps or inv.laps or 1,
        startType = opts.startType, formationM = opts.formationM, paceKph = opts.paceKph,
    }
    local roster = Teams.newRoster(e.eventId)
    rosters[e.eventId] = roster
    local ok, err = NcmCalendar.adopt(e)
    if not ok then return nil, err end
    pcall(function()
        for _, s in ipairs(roster.seats) do
            MySQL.insert.await("INSERT IGNORE INTO seat (event_id, team_id, seat_index) VALUES (?, ?, ?)", { e.eventId, s.teamId, s.seatIndex })
        end
    end)
    log("POSTED %s | %s · %s | start in %s | venue %s | %d seats | %s/%s/%s", e.eventId, e.seriesName, e.routeName, Entry.countdown(e.startsAt - t), e.venue.name, e.seatsTotal, e.disciplineId, e.formatId, e.classId)
    for _, pid in ipairs(Open77.players.all()) do
        toast(pid, { type = "info", title = "NCX · " .. e.routeName, message = ("Invitational posted · starts in %s · invited drivers only"):format(Entry.countdown(e.startsAt - t)), icon = "NCX", durationMs = 8000 })
    end
    return e
end

--- Restore rosters for organized events the calendar loaded from the database (server restart).
function NcmOrganized.restore(e)
    if rosters[e.eventId] then return end
    local roster = Teams.newRoster(e.eventId)
    local ok, rows = pcall(function()
        return MySQL.query.await("SELECT team_id, seat_index, ncm_driver_id, entry_id FROM seat WHERE event_id = ?", { e.eventId }) or {}
    end)
    if ok then
        for _, r in ipairs(rows) do
            for _, s in ipairs(roster.seats) do
                if s.teamId == r.team_id and s.seatIndex == tonumber(r.seat_index) then s.driverId = r.ncm_driver_id; s.entryId = r.entry_id end
            end
        end
    end
    rosters[e.eventId] = roster
end

-- ---------------------------------------------------------------------------------------------
-- The offer (sorting hat) and the acceptance
-- ---------------------------------------------------------------------------------------------
local function nextInvitational(t)
    for _, eid in ipairs(NcmCalendar.orderedIds()) do
        local e = NcmCalendar.events[eid]
        if e and e.class == "organized" and e.invitation and (e.state == "posted" or e.state == "entry_open") and e.startsAt > t then
            return e
        end
    end
    return nil
end

--- Console: ncm.invite <pid> [team]
function NcmOrganized.invite(pid, teamId)
    local t = now()
    local e = nextInvitational(t)
    if not e then return nil, "no_invitational_open" end
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then return nil, "no_driver" end
    if e.entries[driver.ncmDriverId] then return nil, "already_entered" end
    if offers[driver.ncmDriverId] and offers[driver.ncmDriverId].eventId == e.eventId then return nil, "already_offered" end
    local roster = rosters[e.eventId]
    if not roster then NcmOrganized.restore(e); roster = rosters[e.eventId] end
    local affinity = NcmOrganized.loadAffinity(driver.ncmDriverId)
    local seat, why = Teams.assignSeat(roster, driver.ncmDriverId, { rng = hostRng, teamId = teamId, affinity = affinity })
    if not seat then return nil, why end
    local team = Teams.byId(seat.teamId)
    local car = Teams.carForSeat(seat.teamId, seat.seatIndex)
    local body = ("%s want you in their car. %s · %s → %s · lights in %s. Reply /ncm.accept or /ncm.decline."):format(
        team.name, e.routeName, e.venue.name, e.finish.name, Entry.countdown(e.startsAt - t))
    local messageId = messageCreate(driver.ncmDriverId, {
        fromKind = "team", fromId = seat.teamId, kind = "seat_offer", subject = ("%s · seat offer · car #%d"):format(team.name, car and car.number or seat.seatIndex),
        body = body, actions = { "accept", "decline" }, refKind = "event", refId = e.eventId, expiresAt = e.startsAt - 60,
    })
    offers[driver.ncmDriverId] = { eventId = e.eventId, seat = seat, offeredAt = t, playerId = pid, messageId = messageId }
    pcall(function()
        MySQL.update.await("UPDATE seat SET ncm_driver_id = ?, offered_at = ? WHERE event_id = ? AND team_id = ? AND seat_index = ?",
            { driver.ncmDriverId, math.floor(t), e.eventId, seat.teamId, seat.seatIndex })
    end)
    -- One voice for all teams until the Messages panel (M7.5).
    tell(pid, body)
    toast(pid, { type = "warning", title = "NEW MESSAGE · F9", message = ("%s · seat offer — open your messages (F9) or /ncm.accept"):format(team.name), icon = team.short, color = team.colour, durationMs = 15000 })
    local Q = Core.get("onboarding.questionnaire")
    local top = affinity and Q.top(affinity) or nil
    log("OFFER driver=%s player=%d team=%s seat=%d event=%s affinity_top=%s", driver.ncmDriverId, pid, seat.teamId, seat.seatIndex, e.eventId, tostring(top or "none"))
    pushInbox(pid, driver.ncmDriverId)
    return seat
end

local function acceptOffer(pid)
    local t = now()
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then tell(pid, "No NCM driver on this session."); return end
    local offer = offers[driver.ncmDriverId]
    if not offer then tell(pid, "No open seat offer."); return end
    if offer.busy then return end   -- a second accept while the first awaits the database (double click) hit SQL 1062
    offer.busy = true
    local e = NcmCalendar.events[offer.eventId]
    if not e then offers[driver.ncmDriverId] = nil; tell(pid, "That event is gone."); return end
    local decision = Entry.register({ event = e, now = t, driverId = driver.ncmDriverId, existingEntry = e.entries[driver.ncmDriverId], seat = offer.seat, rng = hostRng })
    if not decision.ok then offer.busy = nil; tell(pid, "Cannot register: " .. tostring(decision.reason)); return end
    local en = decision.entry
    local car = Teams.carForSeat(en.teamId, en.seatIndex)
    en.carNumber = car and car.number or nil
    local okDb, err = pcall(function()
        MySQL.insert.await(
            "INSERT INTO entry (entry_id, event_id, ncm_driver_id, state, fee, registered_at, team_id, seat_index, car_number) VALUES (?, ?, ?, 'registered', 0, ?, ?, ?, ?)",
            { en.entryId, e.eventId, driver.ncmDriverId, math.floor(t), en.teamId, en.seatIndex, en.carNumber })
        MySQL.update.await("UPDATE seat SET entry_id = ?, accepted_at = ? WHERE event_id = ? AND team_id = ? AND seat_index = ?",
            { en.entryId, math.floor(t), e.eventId, en.teamId, en.seatIndex })
    end)
    if not okDb then offer.busy = nil; tell(pid, "Registration could not be recorded: " .. tostring(err)); return end
    e.entries[driver.ncmDriverId] = en
    messageResolve(offer.messageId, "accepted")
    offers[driver.ncmDriverId] = nil
    pushInbox(pid, driver.ncmDriverId)
    local team = Teams.byId(en.teamId)
    pcall(function()
        Open77.state.player(pid):set("ncmEntry", { eventId = e.eventId, state = "registered", routeName = e.routeName, startsAt = math.floor(e.startsAt),
            teamId = en.teamId, teamName = team.name, teamShort = team.short, colour = team.colour, seatIndex = en.seatIndex })
    end)
    local numberText = en.carNumber and ("#" .. en.carNumber) or ("car " .. en.seatIndex)
    tell(pid, ("You're driving for %s (%s). Be on your mark at %s — lights in %s. Your car will be waiting in your grid slot."):format(team.name, numberText, e.venue.name, Entry.countdown(e.startsAt - t)))
    toast(pid, { type = "success", title = ("%s · %s"):format(string.upper(team.name), string.upper(numberText)), message = "Report to the grid at " .. e.venue.name, icon = team.short, color = team.colour, durationMs = 10000 })
    log("ACCEPTED driver=%s player=%d team=%s seat=%d event=%s entry=%s", driver.ncmDriverId, pid, en.teamId, en.seatIndex, e.eventId, en.entryId)
    NcmCalendar.publishNow()
    if NcmRace.pickupStarted(e.eventId) then NcmRace.pickupLate(e, driver.ncmDriverId) end
end

local function declineOffer(pid)
    local driver = NcmCalendar.resolveDriver(pid)
    local offer = driver and offers[driver.ncmDriverId]
    if not offer then tell(pid, "No open seat offer."); return end
    local roster = rosters[offer.eventId]
    if roster then Teams.releaseSeat(roster, driver.ncmDriverId) end
    pcall(function()
        MySQL.update.await("UPDATE seat SET ncm_driver_id = NULL, offered_at = NULL WHERE event_id = ? AND team_id = ? AND seat_index = ?",
            { offer.eventId, offer.seat.teamId, offer.seat.seatIndex })
    end)
    messageResolve(offer.messageId, "declined")
    offers[driver.ncmDriverId] = nil
    pushInbox(pid, driver.ncmDriverId)
    tell(pid, "Offer declined.")
    log("DECLINED driver=%s event=%s", driver.ncmDriverId, offer.eventId)
end

-- Chat: /ncm.accept. Console (KB-4 tester instance has no chat): ncm.accept <playerId>.
-- ---------------------------------------------------------------------------------------------
-- Inbox surface (Batch 1, item 2): the panel talks net events; chat and console have twins.
-- ---------------------------------------------------------------------------------------------
RegisterNetEvent("ncm:inbox", function()
    local pid = tonumber(source) or 0
    local driver = pid > 0 and NcmCalendar.resolveDriver(pid)
    if driver then pushInbox(pid, driver.ncmDriverId) end
end)

RegisterNetEvent("ncm:inbox.read", function(messageId)
    local pid = tonumber(source) or 0
    local driver = pid > 0 and NcmCalendar.resolveDriver(pid)
    if not driver or type(messageId) ~= "string" then return end
    messageRead(messageId, driver.ncmDriverId)
    pushInbox(pid, driver.ncmDriverId)
end)

local function actOnMessage(pid, driver, messageId, action)
    local offer = offers[driver.ncmDriverId]
    if not offer or offer.messageId ~= messageId then tell(pid, "That message is no longer open."); pushInbox(pid, driver.ncmDriverId); return end
    if action == "accept" then acceptOffer(pid) elseif action == "decline" then declineOffer(pid) end
end

RegisterNetEvent("ncm:inbox.act", function(messageId, action)
    local pid = tonumber(source) or 0
    local driver = pid > 0 and NcmCalendar.resolveDriver(pid)
    if not driver then return end
    actOnMessage(pid, driver, tostring(messageId or ""), tostring(action or ""):lower())
end)

--- /ncm.inbox — list; /ncm.read <n> — one message's body (chat twins of the panel).
RegisterCommand("ncm.inbox", function(source, args)
    local caller = tonumber(source) or 0
    local pid = caller > 0 and caller or tonumber(args and args[1])
    if not pid then log("usage: ncm.inbox <playerId>"); return end
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then tell(caller > 0 and caller or nil, "No NCM driver on this session."); return end
    local items, unread = pushInbox(pid, driver.ncmDriverId)
    local out = caller > 0 and function(t) tell(caller, t) end or function(t) log("%s", t) end
    out(("Messages: %d (%d unread). /ncm.read <n> · /ncm.accept · /ncm.decline"):format(#items, unread))
    for _, m in ipairs(items) do out(("%d. [%s] %s"):format(m.n, m.state, m.subject)) end
end, false)

RegisterCommand("ncm.read", function(source, args)
    local caller = tonumber(source) or 0
    if caller <= 0 then return end
    local driver = NcmCalendar.resolveDriver(caller)
    if not driver then return end
    local n = tonumber(args and args[1]) or 1
    local items = messageList(driver.ncmDriverId)
    local m = items[n]
    if not m then tell(caller, "No message " .. n .. "."); return end
    messageRead(m.id, driver.ncmDriverId)
    tell(caller, ("%s — %s"):format(m.subject, m.body))
    pushInbox(caller, driver.ncmDriverId)
end, false)

RegisterCommand("ncm.accept", function(source, args)
    local pid = tonumber(source) or 0
    if pid == 0 then pid = tonumber(args and args[1]) or 0 end
    if pid > 0 then CreateThread(function() acceptOffer(pid) end) end
end, false)
RegisterCommand("ncm.decline", function(source) local pid = tonumber(source) or 0; if pid > 0 then CreateThread(function() declineOffer(pid) end) end end, false)

RegisterCommand("ncm.event.post", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function()
        -- ncm.event.post <route> [minutes] [sprint|weekend|tworace] [laps]
        local Format = Core.get("competition.format")
        local fmt = args and args[3] and Format.byId(tostring(args[3]):lower())
        local opts = { formatId = fmt and fmt.id or nil, laps = tonumber(args and args[4]) }
        for _, a in ipairs(args or {}) do if tostring(a):lower() == "rolling" then opts.startType = "rolling" end end
        local e, err = NcmOrganized.post(args and args[1] or "bline", tonumber(args and args[2]) or 10, opts)
        if not e then log("event.post failed: %s", tostring(err)) end
    end)
end, false)

RegisterCommand("ncm.invite", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.invite <playerId> [teamId]"); return end
    CreateThread(function()
        local seat, err = NcmOrganized.invite(pid, args[2])
        if not seat then log("invite player=%d failed: %s", pid, tostring(err)) end
    end)
end, false)

--- Seat order for the grid (core gridOrder index) — used by race.lua when forming organized events.
NcmOrganized.acceptFor = acceptOffer
function NcmOrganized.clearOffers() for k in pairs(offers) do offers[k] = nil end end

function NcmOrganized.seatOrder(eventId)
    local roster = rosters[eventId]
    if not roster then return {} end
    local out = {}
    for i, s in ipairs(Teams.gridOrder(roster)) do out[s.driverId] = i end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Race control (L19): console commands with an audit trail.
-- ---------------------------------------------------------------------------------------------
local function audit(sessionId, eventId, action, targetDriver, value, reason)
    pcall(function()
        MySQL.insert.await("INSERT INTO rc_audit (event_id, session_id, actor, action, target_driver, value, reason, at) VALUES (NULLIF(?, ''), NULLIF(?, ''), 'console', ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?)",
            { eventId or "", sessionId or "", action, targetDriver or "", value and tostring(value) or "", reason or "", now() })
    end)
    log("RC %s target=%s value=%s reason=%s session=%s", action, tostring(targetDriver), tostring(value), tostring(reason), tostring(sessionId))
end

local function activeSessionFor(pid)
    local driver = pid and NcmCalendar.resolveDriver(pid)
    for sid, rec in pairs(NcmRace.sessions) do
        if rec.s.phase ~= "complete" then
            if not driver then return sid, rec, nil end
            if rec.s.entrants[driver.ncmDriverId] then return sid, rec, driver.ncmDriverId end
        end
    end
    return nil, nil, driver and driver.ncmDriverId or nil
end

RegisterCommand("ncm.rc.penalty", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, sec = tonumber(args and args[1]), tonumber(args and args[2])
    if not pid or not sec then log("usage: ncm.rc.penalty <playerId> <seconds> [reason]"); return end
    local reason = args[3] and table.concat(args, " ", 3) or "race_control"
    local sid, rec, driverId = activeSessionFor(pid)
    if not rec or not driverId then log("rc.penalty: player %d is not in an active session", pid); return end
    local ok, err = NcmRace.control(sid, "penalty", driverId, sec, reason)
    if ok then audit(sid, rec.eventId, "penalty", driverId, sec, reason) else log("rc.penalty refused: %s", tostring(err)) end
end, false)

RegisterCommand("ncm.rc.dsq", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.rc.dsq <playerId> [reason]"); return end
    local reason = args[2] and table.concat(args, " ", 2) or "race_control"
    local sid, rec, driverId = activeSessionFor(pid)
    if not rec or not driverId then log("rc.dsq: player %d is not in an active session", pid); return end
    local ok, err = NcmRace.control(sid, "dsq", driverId, nil, reason)
    if ok then audit(sid, rec.eventId, "dsq", driverId, nil, reason) else log("rc.dsq refused: %s", tostring(err)) end
end, false)

RegisterCommand("ncm.rc.abort", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local reason = args and args[1] and table.concat(args, " ") or "aborted"
    for sid, rec in pairs(NcmRace.sessions) do
        if rec.s.phase ~= "complete" then audit(sid, rec.eventId, "abort", nil, nil, reason) end
    end
    log("rc.abort: %d session(s)", NcmRace.abort(reason))
end, false)

RegisterCommand("ncm.rc.log", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function()
        local rows = MySQL.query.await("SELECT action, target_driver, value, reason, session_id, at FROM rc_audit ORDER BY audit_id DESC LIMIT 10") or {}
        if #rows == 0 then log("rc.log: empty"); return end
        for _, r in ipairs(rows) do
            log("  %s %s %s %s session=%s at=%s", tostring(r.action), tostring(r.target_driver or "-"), tostring(r.value or "-"), tostring(r.reason or "-"), tostring(r.session_id or "-"), tostring(r.at))
        end
    end)
end, false)
