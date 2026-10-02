-- ncm_league / server / paddock_link -- humans in Paddock races (L250 steps 3-4; reverses L224.1).
--
-- The Paddock (another resource, another VM) publishes its next races on GlobalState.ncmPaddockGuide. This file makes
-- each one an ordinary calendar event of class `paddock` (`paddock.mixed.eventFromRow`), so everything a league race
-- already has -- the Race Guide row, the venue ring, ENTER RACE, the grid, the lights, gate timing, settlement -- works
-- for it unchanged. What is different, and lives here:
--
--   QUALIFY        a solo timed run of the whole route from a STANDING start (the practice engine, staged at the line),
--                  any number of runs until T-11; the best counts, and the first time ENTERS the driver (owner: "quali =
--                  entry"). An entry without a time (ENTER RACE at the ring) is allowed; it starts at the back.
--   the hand-over  entries and best times go to the Paddock (`ncm:paddock.entry`); it freezes the field at T-10 with
--                  the humans in it, grids everyone by qualifying time and sends each human's slot back
--                  (`ncm:paddock.grid`). The session forms on THOSE slots: one grid, one green (race.opensAt).
--   auto-place     at T-20 an entered human at the venue but not on their mark is put there in their own car.
--   the result     the league times its humans; the Paddock merges them with its NPCs (`ncm:paddock.human.result`) and
--                  answers with the whole field's classification (`ncm:paddock.classified`); settlement waits for it, so a
--                  human is paid for P4 of 12, not P1 of 1.
--
-- Resources never call each other's globals (tools/test-paddock-host.lua lints the Paddock side): events only.
NcmPaddockLink = { bests = {} }

local Core = NcmCore
local Mixed = Core.get("paddock.mixed")
local Routes = Core.get("course.routes")
local Entry = Core.get("competition.entry")
local ids = Core.get("vocabulary.ids")

local function log(fmt, ...) print(("[ncm_league/paddock_link] " .. fmt):format(...)) end
local now = function() return Open77.time.unix() end
local hostRng = function() return math.random() end
local function tell(pid, text) if pid then pcall(Open77.chat.send, pid, "[NCM] " .. text) end end
local function toast(pid, def) if pid then pcall(Open77.notifications.send, pid, def) end end

local function enabled()
    local s = NcmCalendar and NcmCalendar.settings
    local ok, v = pcall(function() return s and s.paddockEntries end)
    return ok and v ~= false
end

local function fmtTime(ms)
    if not ms then return "--" end
    local sec = ms / 1000
    local m = math.floor(sec / 60)
    return string.format("%d:%05.2f", m, sec - m * 60)
end

local function packFor(seriesName)
    for _, s in ipairs(NcmPackStreet and NcmPackStreet.series or {}) do
        if s.name == seriesName and s.seriesId ~= "street_drag" then return s end
    end
    return nil
end

local function fallbackEconomy()
    for _, s in ipairs(NcmPackStreet and NcmPackStreet.series or {}) do
        if s.seriesId == "city_cup" then return s.economy end
    end
    return nil
end

local function eventOf(raceId) return NcmCalendar.events["paddock:" .. tostring(raceId)] end

-- The Paddock's next races: its `ncm:paddock.guide` event (server events between resources are proven), with
-- GlobalState.ncmPaddockGuide as the fallback.
local feed, feedAt, feedVia = nil, 0, nil
function NcmPaddockLink.feed()
    if type(feed) == "table" and now() - feedAt <= 180 then return feed, "event" end
    local okG, list = pcall(function() return GlobalState and GlobalState.ncmPaddockGuide end)
    if okG and type(list) == "table" then return list, "GlobalState" end
    return nil, okG and ("GlobalState " .. type(list)) or ("GlobalState error " .. tostring(list))
end
NcmPaddockLink.eventOf = eventOf

-- The Paddock may replace an already-posted broken course during its boot schedule repair. Existing entries remain,
-- but course-specific times no longer count; unqualified humans are explicitly ordered behind the timed field.
AddEventHandler("ncm:paddock.routeChanged", function(raceId, routeId)
    local e = eventOf(raceId)
    local route = Routes.resolve(routeId)
    if not e or not route then return end
    e.routeId, e.routeName, e.distanceM = route.routeId, route.name, route.distanceM
    e.venue, e.finish = route.oval and route.oval.entry or route.start, route.finish
    e.via = route.oval and route.oval.loop or route.intermediate
    NcmPaddockLink.bests[e.eventId] = {}
    if NcmCalendar.publishNow then NcmCalendar.publishNow() end
    if NcmGuide and NcmGuide.pushAll then NcmGuide.pushAll() end
    log("course updated for %s to point-to-point %s", e.eventId, route.routeId)
end)

-- ------------------------------------------------------------------------------------------------ adoption
--- A restart must not forget who entered or how fast they were: entries and best times come back with the event.
local function restore(e)
    local okE, rows = pcall(MySQL.query.await, [[SELECT entry_id, ncm_driver_id, state, fee, checked_in_at, interested_at, asset_id, car_number
        FROM entry WHERE event_id = ?]], { e.eventId })
    for _, r in ipairs(okE and rows or {}) do
        e.entries[r.ncm_driver_id] = { entryId = r.entry_id, state = r.state, fee = tonumber(r.fee) or 0,
            checkedInAt = tonumber(r.checked_in_at), interestedAt = tonumber(r.interested_at), assetId = r.asset_id,
            carNumber = tonumber(r.car_number) }
    end
    local okQ, qrows = pcall(MySQL.query.await, "SELECT ncm_driver_id, best_ms FROM paddock_quali WHERE server_id = ? AND race_id = ?",
        { NcmCalendar.serverId(), e.paddockRaceId })
    for _, r in ipairs(okQ and qrows or {}) do
        NcmPaddockLink.bests[e.eventId] = NcmPaddockLink.bests[e.eventId] or {}
        NcmPaddockLink.bests[e.eventId][r.ncm_driver_id] = tonumber(r.best_ms)
    end
end

--- Adopt every Paddock race on the feed that is still open for entries. Returns how many were new.
function NcmPaddockLink.adoptAll(t)
    if not enabled() then return 0 end
    local list, via = NcmPaddockLink.feed()
    if via ~= feedVia then
        feedVia = via
        log("Paddock feed: %s (%s)", list and (#list .. " race(s)") or "none", tostring(via))
    end
    if type(list) ~= "table" then return 0 end
    local n = 0
    for _, row in ipairs(list) do
        if type(row) == "table" and row.raceId and (row.state == "scheduled" or row.state == "priced") then
            local route = Routes.resolve(row.routeId, row.routeName)
            local existing = eventOf(row.raceId)
            if existing and tonumber(row.startsAt) then
                -- Reconcile events persisted/adopted under an older cutoff (e.g. T-11). The feed is authoritative;
                -- otherwise the Guide can say entries closed well before the current T-1 rule.
                local closesAt = tonumber(row.startsAt) - Mixed.ENTRY_CLOSE_LEAD_SEC
                local state = existing.state
                if state == "closed" and t < closesAt then state = "entry_open" end
                if existing.entryClosesAt ~= closesAt or existing.state ~= state then
                    existing.startsAt, existing.entryClosesAt, existing.state = tonumber(row.startsAt), closesAt, state
                    pcall(MySQL.update.await, "UPDATE event SET starts_at = ?, entry_closes_at = ?, state = ? WHERE event_id = ?",
                        { math.floor(existing.startsAt), math.floor(closesAt), state, existing.eventId })
                    n = n + 1
                end
            elseif route then
                local e = Mixed.eventFromRow(row, route, t, packFor(row.seriesName), fallbackEconomy())
                if e then
                    restore(e)
                    local ok, why = NcmCalendar.adopt(e)
                    if ok then
                        n = n + 1
                        log("adopted %s | %s · %s | start in %s | venue %s", e.eventId, tostring(e.seriesName), tostring(e.routeName),
                            Entry.countdown(e.startsAt - t), tostring(e.venue.name))
                    elseif why ~= "duplicate_event" then
                        log("adopt %s refused: %s", e.eventId, tostring(why))
                    end
                end
            end
        end
    end
    if n > 0 then
        if NcmCalendar.publishNow then NcmCalendar.publishNow() end
        if NcmGuide and NcmGuide.pushAll then NcmGuide.pushAll() end
    end
    return n
end

-- The Guide must never expose a Paddock row before the calendar has materialised the matching event: the
-- client receives venue rings only through the calendar.  Previously this event merely cached the feed and the
-- 15-second linker poll adopted it later.  A player who opened the Guide in that gap could see a race, but had
-- no ring and could receive `No such race in the Guide` when acting on its stale row.  Adopt as soon as the
-- Paddock publishes; the poll below remains the restart/fallback path.
AddEventHandler("ncm:paddock.guide", function(rows)
    if type(rows) ~= "table" then return end
    feed, feedAt = rows, now()
    CreateThread(function()
        local ok, adopted = pcall(NcmPaddockLink.adoptAll, now())
        if not ok then
            log("immediate Paddock feed adoption failed: %s", tostring(adopted))
            return
        end
        if adopted > 0 then
            log("immediate Paddock feed adoption: %d event(s)", adopted)
            if NcmGuide and NcmGuide.pushAll then NcmGuide.pushAll() end
        end
    end)
end)

-- ------------------------------------------------------------------------------------------------ entries
local function displayOf(pid, driver)
    return (driver and driver.display) or (pid and GetPlayerName(pid)) or (driver and driver.ncmDriverId:sub(1, 8)) or "?"
end

--- Tell the Paddock who is in, with their best time (nil = entered, not qualified).
function NcmPaddockLink.announce(e, driverId, display, state)
    local en = e.entries and e.entries[driverId] or {}
    local best = NcmPaddockLink.bests[e.eventId] and NcmPaddockLink.bests[e.eventId][driverId] or nil
    TriggerEvent("ncm:paddock.entry", {
        raceId = e.paddockRaceId, driverId = driverId, display = display, seriesId = e.paddockSeriesId,
        state = state or "entered", qualiMs = best, assetId = en.assetId, enteredAt = math.floor(en.checkedInAt or now()),
    })
    log("announce %s driver=%s state=%s quali=%s", e.eventId, driverId:sub(1, 8), tostring(state or "entered"), best and fmtTime(best) or "none")
end

--- Enter a driver whose qualifying time has just made them an entrant: the league's ordinary entry (fee, machine,
--- ledger) without the at-the-line rule, because the run itself was at the line. Returns true when they are in.
local function ensureEntry(pid, e, driver, assetId)
    local driverId = driver.ncmDriverId
    local ex = e.entries[driverId]
    if ex and ex.state ~= "withdrawn" and ex.state ~= "interested" then return true, false end
    if now() >= e.entryClosesAt then return false, "closed" end
    local machine = NcmCompetition and NcmCompetition.enterMachine and NcmCompetition.enterMachine(e, driverId, assetId or NcmRace.seatedAsset(pid)) or nil
    if not machine then
        tell(pid, ("Your time stands, but you don't own a car eligible for %s, so you are not entered."):format(tostring(e.seriesName)))
        return false, "no_eligible_car"
    end
    local en = { entryId = (ex and ex.entryId) or ids.uuid4(hostRng), state = "checked_in", checkedInAt = now(), assetId = machine }
    local okCall, paid, why = pcall(NcmEconomy.checkIn, {
        economy = NcmCompetition.economyFor(e), unpaid = false, upgraded = ex ~= nil, entryId = en.entryId,
        eventId = e.eventId, seriesId = e.seriesId, driverId = driverId, checkedInAt = en.checkedInAt, assetId = machine,
    })
    if not okCall or not paid then
        tell(pid, "Your time stands, but the entry was refused: " .. tostring(okCall and (why or "insufficient balance") or paid) .. ". Check /ncm.balance.")
        return false, "refused"
    end
    en.fee = paid.fee
    e.entries[driverId] = en
    if NcmGuide and NcmGuide.refreshEntryBag then NcmGuide.refreshEntryBag(pid) end
    NcmCalendar.publishNow()
    log("ENTERED by qualifying player=%d driver=%s event=%s fee=%d", pid or -1, driverId:sub(1, 8), e.eventId, paid.fee or 0)
    return true, true, paid
end

--- A run finished in a Paddock qualifying session (race.lua's gate host calls this).
function NcmPaddockLink.onQualiRun(rec, driverId, pid, res, t)
    local e = NcmCalendar.events[rec.eventId]
    if not e or e.class ~= "paddock" or not res.finished then return end
    local ms = math.floor((res.runSec or 0) * 1000 + 0.5)
    if ms <= 0 then return end
    NcmPaddockLink.bests[e.eventId] = NcmPaddockLink.bests[e.eventId] or {}
    local prev = NcmPaddockLink.bests[e.eventId][driverId]
    local improved = not prev or ms < prev
    if improved then NcmPaddockLink.bests[e.eventId][driverId] = ms end
    local assetId = res.machine and res.machine.assetId or nil
    pcall(MySQL.insert.await, [[INSERT INTO paddock_quali (server_id, race_id, ncm_driver_id, best_ms, runs, asset_id, last_at)
        VALUES (?, ?, ?, ?, 1, NULLIF(?, ''), ?) ON DUPLICATE KEY UPDATE runs = runs + 1, last_at = VALUES(last_at),
        asset_id = IF(VALUES(best_ms) < best_ms, VALUES(asset_id), asset_id), best_ms = LEAST(best_ms, VALUES(best_ms))]],
        { NcmCalendar.serverId(), e.paddockRaceId, driverId, ms, assetId or "", math.floor(t) })
    local driver = NcmCalendar.resolveDriver(pid) or { ncmDriverId = driverId }
    local inNow, newly = ensureEntry(pid, e, driver, assetId)
    if inNow and (improved or newly) then NcmPaddockLink.announce(e, driverId, displayOf(pid, driver), "entered") end
    local best = NcmPaddockLink.bests[e.eventId][driverId]
    if inNow then
        tell(pid, ("Qualifying %s: %s%s. %s The grid sets at T-10 (%s)."):format(tostring(e.routeName), fmtTime(ms),
            improved and (prev and " -- a new best" or "") or (" (best " .. fmtTime(best) .. ")"),
            newly and ("You're entered in " .. tostring(e.seriesName) .. ".") or "Your entry stands.", Entry.countdown(e.startsAt - 600 - t)))
        toast(pid, { type = "success", title = (improved and "QUALIFYING BEST · " or "QUALIFYING · ") .. fmtTime(ms),
            message = newly and ("ENTERED · " .. tostring(e.seriesName)) or ("best " .. fmtTime(best)), icon = "NCM", durationMs = 7000 })
    end
    log("QUALI %s driver=%s run=%s best=%s entered=%s", e.eventId, driverId:sub(1, 8), fmtTime(ms), fmtTime(best), tostring(inNow))
    if NcmGuide and NcmGuide.pushAll then NcmGuide.pushAll() end
end

--- QUALIFY from the venue card only: the Guide can express interest and route the driver here.
function NcmPaddockLink.qualify(pid, eventId)
    local driver = NcmCalendar.resolveDriver(pid)
    if not driver then tell(pid, "No NCM driver on this session."); return nil, "no_driver" end
    local e = NcmCalendar.events[tostring(eventId or "")]
    if not e or e.class ~= "paddock" then tell(pid, "That race has no qualifying."); return nil, "no_event" end
    if not (NcmGuide and NcmGuide.venueAt and NcmGuide.venueAt(pid) == e.eventId) then
        tell(pid, "Drive inside this race's venue ring to start qualifying.")
        return nil, "not_at_venue"
    end
    local t = now()
    if t >= e.entryClosesAt then tell(pid, "Qualifying has closed for that one (it closes at T-11)."); return nil, "closed" end
    local busy, busyEvent, busyKind = NcmRace.busySession(driver.ncmDriverId)
    if busy and busyKind ~= "practice" then tell(pid, "You're out in a session. Finish it or retire first."); return nil, "busy" end
    -- one qualifying session at a time: picking another race moves you to it
    if busy and busyEvent ~= e.eventId then NcmRace.practiceLeave(busyEvent, driver.ncmDriverId, t, "qualifying_elsewhere") end
    if NcmCompetition and NcmCompetition.carRefusal then
        local why = NcmCompetition.carRefusal(e, driver.ncmDriverId)
        if why then tell(pid, ("You don't own a car eligible for %s."):format(tostring(e.seriesName))); return nil, why end
    end
    local ok, why = NcmRace.practiceJoin(e, driver, pid, t)
    if not ok and why ~= "already_joined" then tell(pid, "Could not open qualifying: " .. tostring(why)); return nil, why end
    TriggerClientEvent("ncm:guide.route", pid, { x = e.venue.x, y = e.venue.y, z = e.venue.z, name = e.venue.name, why = "qualifying" })
    local fee = (NcmCompetition.economyFor(e) or {}).entryFee or 0
    tell(pid, ("Qualifying open: %s · %s. Drive to %s, STOP on the start line, then go -- a standing start. Your best run counts; your first time enters you (fee €$%d). Closes in %s."):format(
        tostring(e.seriesName), tostring(e.routeName), tostring(e.venue.name), fee, Entry.countdown(e.entryClosesAt - t)))
    toast(pid, { type = "info", title = "QUALIFYING · " .. tostring(e.routeName), message = "Stop on the line at " .. tostring(e.venue.name) .. ", then go", icon = "NCM", durationMs = 8000 })
    log("QUALIFY open player=%d driver=%s event=%s", pid, driver.ncmDriverId:sub(1, 8), e.eventId)
    if NcmGuide and NcmGuide.pushAll then NcmGuide.pushAll() end
    return true
end

RegisterNetEvent("ncm:guide.qualify", function(eventId) NcmPaddockLink.qualify(tonumber(source) or 0, eventId) end)
RegisterCommand("ncm.qualify", function(source, args)
    local pid = tonumber(source) or 0
    if pid > 0 then NcmPaddockLink.qualify(pid, args and args[1]) return end
    local target = tonumber(args and args[1])
    if target then NcmPaddockLink.qualify(target, args[2]) else log("usage: ncm.qualify <playerId> <eventId>") end
end, false)

-- ------------------------------------------------------------------------------------------------ the grid
-- The Paddock's slots for this race's humans, re-sent until the lights (a restart here between T-10 and the race must
-- still find them).
AddEventHandler("ncm:paddock.grid", function(raceId, msg)
    local e = eventOf(raceId)
    if not e or type(msg) ~= "table" then return end
    local first = e.paddockGrid == nil
    e.paddockGrid = msg
    if first then
        local n = 0
        for _ in pairs(msg.slots or {}) do n = n + 1 end
        log("grid for %s: %d human slot(s) of %d", e.eventId, n, tonumber(msg.fieldSize) or 0)
    end
end)

--- The session's slots from the Paddock's grid, pole first. nil when the Paddock has sent none (the host falls back).
function NcmPaddockLink.slotsFor(e, entrants)
    local g = e and e.paddockGrid
    if type(g) ~= "table" or type(g.slots) ~= "table" then return nil end
    local out, missing = {}, {}
    for _, en in ipairs(entrants) do
        local s = g.slots[en.driverId]
        if s then
            out[#out + 1] = { slot = tonumber(s.slot), driverId = en.driverId, entryId = en.entryId, display = en.display,
                teamId = en.teamId, seatIndex = en.seatIndex, x = s.x, y = s.y, z = s.z, heading = s.heading, yaw = s.yaw,
                radiusM = 4, paddock = true }
        else
            missing[#missing + 1] = en.driverId:sub(1, 8)
        end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    if #missing > 0 then log("%s: no Paddock slot for %s (entered after the freeze?)", e.eventId, table.concat(missing, ", ")) end
    return out, tonumber(g.fieldSize)
end

local lastProgressAt = {}
function NcmPaddockLink.publishProgress(rec, t)
    if not rec or not rec.paddock or t - (lastProgressAt[rec.eventId] or 0) < 2 then return end
    lastProgressAt[rec.eventId] = t
    local total = #(rec.s.gates or {})
    if total == 0 then return end
    local rows = {}
    for driverId, r in pairs(rec.s.entrants or {}) do
        if r.state == "racing" or r.state == "finished" or r.state == "dnf" then
            rows[#rows + 1] = { driverId = driverId, progressPct = r.state == "finished" and 100 or (100 * (tonumber(r.progress) or 0) / total) }
        end
    end
    if #rows > 0 then TriggerEvent("ncm:paddock.human.progress", rec.plan.e.paddockRaceId, rows) end
end

-- ------------------------------------------------------------------------------------------------ auto-place
local function placeOne(rec, sl, pid)
    local okP, p = pcall(Open77.players.get, pid)
    local pos = okP and type(p) == "table" and p.position or nil
    if not pos then return false, "position_unavailable" end
    local d = Routes.planarDistance(pos, sl)
    if d <= (sl.radiusM or 4) then return true, "already_on_mark" end
    if d > 20 then
        tell(pid, ("Race control: you are %d m from P%d. Drive closer; grid assist only moves a nearby car."):format(math.floor(d), sl.slot))
        log("auto-place skipped session=%s player=%d: %.0f m from slot %d", rec.s.sessionId:sub(1, 8), pid, d, sl.slot)
        return false, "outside_auto_place_range"
    end
    local okS, seat = pcall(Open77.vehicles.getPlayerSeat, pid)
    local vid = okS and type(seat) == "table" and tonumber(seat.vehicleId) or nil
    if not vid then
        tell(pid, "Race control: get in your car and drive to your grid ring. You remain entered until the lights go green.")
        log("auto-place skipped session=%s player=%d: on foot %.0f m from slot %d", rec.s.sessionId:sub(1, 8), pid, d, sl.slot)
        return false, "on_foot"
    end
    local okAll, allVehicles = pcall(Open77.vehicles.all)
    if not okAll or type(allVehicles) ~= "table" then
        tell(pid, "Race control: I cannot confirm your grid spot is clear. Drive into place instead.")
        return false, "clearance_unavailable"
    end
    for _, other in pairs(allVehicles) do
        local otherId = tonumber(type(other) == "table" and (other.id or other.vehicleId) or nil)
        local otherPos = type(other) == "table" and (other.position or other) or nil
        if otherId and otherId ~= vid and type(otherPos) == "table" and Routes.planarDistance(otherPos, sl) < 6 then
            tell(pid, "Race control: your grid ring is occupied. Move into place manually; your car will not be placed into another.")
            log("auto-place refused session=%s player=%d slot=%d: vehicle=%d within 6m", rec.s.sessionId:sub(1, 8), pid, sl.slot, otherId)
            return false, "slot_occupied"
        end
    end
    toast(pid, { type = "warning", title = "RACE CONTROL", message = "Placing you on your slot · P" .. sl.slot, icon = "NCM", durationMs = 5000 })
    -- never move an occupied car (open77_admin: the solver throws it): out, move the empty car, back in
    local okO, out, whyO = pcall(Open77.vehicles.forcePlayerOutOfVehicle, pid, vid)
    for _ = 1, 30 do
        Wait(100)
        local okS2, s2 = pcall(Open77.vehicles.getPlayerSeat, pid)
        if not (okS2 and type(s2) == "table" and s2.vehicleId) then break end
    end
    local okT, moved, whyT = pcall(Open77.vehicles.setTransform, vid, { position = { x = sl.x, y = sl.y, z = (sl.z or pos.z or 0) + 0.6 }, yaw = sl.yaw or sl.heading or 0 })
    Wait(400)
    local okW, warped, whyW = pcall(Open77.vehicles.warpPlayerIntoVehicle, pid, vid, "driver", { moveBucket = true })
    local placedDistance
    if okT and moved == true and okW and warped == true then
        -- API success only means the transform/seat calls returned true. Verify the actual player position that
        -- gridCheck uses; auto-place previously marked success without this and could still DNS the entrant.
        for _ = 1, 10 do
            Wait(100)
            local okV, verified = pcall(Open77.players.get, pid)
            local actual = okV and type(verified) == "table" and verified.position or nil
            if actual then
                placedDistance = Routes.planarDistance(actual, sl)
                if placedDistance <= (sl.radiusM or 4) then break end
            end
        end
    end
    local verified = placedDistance ~= nil and placedDistance <= (sl.radiusM or 4)
    log("AUTO-PLACE session=%s player=%d vehicle=%d slot=%d from %.0f m: out=%s/%s move=%s/%s in=%s/%s verified=%s distance=%s",
        rec.s.sessionId:sub(1, 8), pid, vid, sl.slot, d, tostring(okO), tostring(out or whyO), tostring(okT), tostring(moved or whyT),
        tostring(okW), tostring(warped or whyW), tostring(verified), placedDistance and ("%.1f m"):format(placedDistance) or "unavailable")
    if not verified and okT and moved == true and okW and warped == true then return false, "position_unverified" end
    return verified, (not okT or not moved) and "transform_failed" or ((not okW or not warped) and "warp_failed" or (verified and "placed" or "position_unverified"))
end

--- At T-20 (paddock.mixed.AUTO_PLACE_SEC): offer a nearby placement assist; refuse if the slot is occupied.
function NcmPaddockLink.autoPlace(rec, t)
    if rec.kind ~= "race" or not rec.paddock then return end
    local s = rec.s
    if s.phase ~= "forming" and s.phase ~= "gridded" then return end
    if t < s.startsAt - Mixed.AUTO_PLACE_SEC then return end
    rec.autoPlaced = rec.autoPlaced or {}
    rec.autoPlaceNextAt = rec.autoPlaceNextAt or {}
    rec.autoPlacing = rec.autoPlacing or {}
    for _, sl in ipairs(rec.slots or {}) do
        local r = s.entrants[sl.driverId]
        local pid = rec.playerOf[sl.driverId]
        local id = sl.driverId
        if r and r.state == "entered" and pid and not rec.autoPlaced[id] and not rec.autoPlacing[id]
            and t >= (rec.autoPlaceNextAt[id] or 0) then
            rec.autoPlacing[id] = true
            CreateThread(function()
                local ok, placed, why = pcall(placeOne, rec, sl, pid)
                rec.autoPlacing[id] = nil
                if ok and placed then
                    rec.autoPlaced[id] = true
                else
                    rec.autoPlaceNextAt[id] = (Open77.time.unix() or t) + 2
                    if not ok then log("auto-place error session=%s player=%d slot=%d: %s", s.sessionId:sub(1, 8), pid, sl.slot, tostring(placed))
                    elseif why == "transform_failed" or why == "warp_failed" or why == "position_unverified" then
                        log("auto-place will retry session=%s player=%d slot=%d: %s", s.sessionId:sub(1, 8), pid, sl.slot, tostring(why))
                    end
                end
            end)
        end
    end
end

-- ------------------------------------------------------------------------------------------------ the result
local waiting = {}   -- raceId -> { rec, results, reason, completeFn }

--- The league has timed its humans: hand them to the Paddock and settle when the whole field is classified.
function NcmPaddockLink.awaitClassification(rec, results, reason, t, completeFn)
    local e = rec.plan.e
    local raceId = e.paddockRaceId
    local rows = {}
    local gates = #(rec.s.gates or {})
    for _, r in ipairs(results) do
        local sec = r.correctedSec or r.totalSec
        rows[#rows + 1] = { driverId = r.driverId, display = r.display, state = r.state,
            finishMs = (r.state == "finished" and sec) and math.floor(sec * 1000 + 0.5) or nil,
            progressPct = math.floor(100 * (r.progress or 0) / math.max(1, r.gatesTotal or gates)), dnfReason = r.dnfReason }
    end
    rec.results, rec.completeReason, rec.provisional = results, reason, true
    waiting[raceId] = { rec = rec, results = results, reason = reason, completeFn = completeFn }
    TriggerEvent("ncm:paddock.human.result", raceId, rows)
    for _, r in ipairs(results) do
        local pid = rec.playerOf and rec.playerOf[r.driverId]
        if pid and r.state == "finished" then
            tell(pid, "Finished. The Paddock classifies the whole field when the last car is home; your result and pay follow.")
        end
    end
    log("RESULT %s -> Paddock: %d human(s); settlement waits for the classification", e.eventId, #rows)
    CreateThread(function()
        Wait(Mixed.CLASSIFY_WAIT_SEC * 1000)
        local w = waiting[raceId]
        if not w then return end
        waiting[raceId] = nil
        log("RESULT %s: no classification from the Paddock in %d s; settling the humans alone", e.eventId, Mixed.CLASSIFY_WAIT_SEC)
        w.rec.classified = true
        w.completeFn(w.rec, w.results, w.reason, now())
    end)
end

AddEventHandler("ncm:paddock.classified", function(raceId, msg)
    local w = waiting[raceId]
    if not w or type(msg) ~= "table" then return end
    waiting[raceId] = nil
    local places = type(msg.places) == "table" and msg.places or {}
    for _, r in ipairs(w.results) do
        local p = tonumber(places[r.driverId])
        if p then r.position = p end
    end
    table.sort(w.results, function(a, b) return (a.position or 99) < (b.position or 99) end)
    w.rec.classified = true
    w.rec.mixedField = tonumber(msg.fieldSize)
    log("RESULT %s classified by the Paddock: field %s", w.rec.eventId, tostring(msg.fieldSize))
    w.completeFn(w.rec, w.results, w.reason, now())
end)

-- ------------------------------------------------------------------------------------------------ start
function NcmPaddockLink.start()
    CreateThread(function()
        Wait(15000)                                    -- the calendar's first tick and the Paddock's first feed
        while true do
            local ok, err = pcall(NcmPaddockLink.adoptAll, now())
            if not ok then log("adopt error: %s", tostring(err)) end
            Wait(10000)
        end
    end)
    log("paddock link started (entries %s)", enabled() and "on" or "OFF")
end
