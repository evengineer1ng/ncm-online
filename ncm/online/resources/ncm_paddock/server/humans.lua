-- ncm_paddock / server / humans -- humans on Paddock grids (L250 steps 3-4; reverses L224.1).
--
-- ncm_league owns the humans: their entry, fee, qualifying runs, gate timing and pay (server/paddock_link.lua there). This
-- file is the Paddock's half, by events only (resources never call each other's globals):
--
--   ncm:paddock.entry         (league -> here) a driver entered / re-qualified / withdrew; kept in paddock_entry
--   freeze (T-10)             each entered human takes the place of the last NPC who turned up, and the grid is everyone
--                             by qualifying time, entered-but-unqualified humans at the back (paddock.mixed.gridOrder)
--   ncm:paddock.grid          (here -> league) each human's slot on the lane grid, re-sent until the lights
--   the bubble                never spawns a human's slot (bubble.lua); NPCs launch at the same green, race.opensAt
--   ncm:paddock.human.result  (league -> here) the humans' times from that green; the race's close waits for them
--   resolve                   the NPC classification and the humans' merged by time (paddock.mixed.merge) and written
--                             as the race's result; ncm:paddock.classified (here -> league) carries each human's place
--                             and the field size, which is what the league pays them on
PaddockHumans = { byRace = {}, results = {}, names = {}, penaltyMs = {}, finishedAt = {} }   -- penaltyMs: raceId -> key -> live incident ms

local U = PaddockUtil
local log = U.logger("humans")
local Mixed = NcmCore.get("paddock.mixed")
local L = NcmCore.get("paddock.live")
local liveProgress = {} -- raceId -> person key -> fraction of the full race course
local liveDistance = {} -- raceId -> person key -> monotonic, physically projected metres

local function entriesOf(raceId)
    PaddockHumans.byRace[raceId] = PaddockHumans.byRace[raceId] or {}
    return PaddockHumans.byRace[raceId]
end

--- A human's name and driver id by their Paddock key, for views that outlive the in-memory entries (season standings,
--- results): the last name they entered under. Cached; a miss is cached too so a view never queries per row twice.
local identities = {}
function PaddockHumans.identity(key)
    if type(key) ~= "string" then return nil end
    local hit = identities[key]
    if hit then return hit.display and hit or nil end
    local ok, rows = pcall(MySQL.query.await, [[SELECT display, ncm_driver_id FROM paddock_entry WHERE server_id = ? AND person_key = ?
        ORDER BY entered_at DESC LIMIT 1]], { U.sid(), key })
    local r = ok and type(rows) == "table" and rows[1] or nil
    identities[key] = { display = r and r.display or PaddockHumans.names[key], driverId = r and r.ncm_driver_id or nil }
    if identities[key].display then PaddockHumans.names[key] = PaddockHumans.names[key] or identities[key].display end
    return identities[key].display and identities[key] or nil
end

--- A human's team label: the team they manage, else "Privateer" (owner, 2026-10-02).
function PaddockHumans.teamOf(driverId)
    local o = driverId and PaddockWorld.orgManagedBy(driverId)
    return o and o.name or "Privateer"
end

--- Boot: the entries and results of the races still in memory.
function PaddockHumans.load()
    local ok, rows = pcall(MySQL.query.await, [[SELECT race_id, ncm_driver_id, person_key, display, series_id, state, quali_ms,
        asset_id, entered_at, result_state, finish_ms, progress_pct FROM paddock_entry WHERE server_id = ? AND entered_at >= ?]],
        { U.sid(), U.now() - 2 * 86400 })
    if not ok then log("could not load entries: %s", tostring(rows)) return end
    for _, r in ipairs(rows or {}) do
        entriesOf(r.race_id)[r.ncm_driver_id] = { driverId = r.ncm_driver_id, key = r.person_key, display = r.display,
            seriesId = r.series_id, state = r.state, qualiMs = tonumber(r.quali_ms), assetId = r.asset_id, enteredAt = tonumber(r.entered_at) }
        PaddockHumans.names[r.person_key] = r.display
        if r.result_state then
            PaddockHumans.results[r.race_id] = PaddockHumans.results[r.race_id] or {}
            PaddockHumans.results[r.race_id][r.person_key] = { state = r.result_state, finishMs = tonumber(r.finish_ms),
                progressFrac = (tonumber(r.progress_pct) or 0) / 100 }
        end
    end
    log("loaded %d human entr(ies)", #(rows or {}))
end

AddEventHandler("ncm:paddock.entry", function(m)
    if type(m) ~= "table" or type(m.raceId) ~= "string" or type(m.driverId) ~= "string" or #m.driverId ~= 36 then return end
    local race = PaddockRaces.byId[m.raceId]
    if not race then log("entry for unknown race %s refused", m.raceId) return end
    if race.frozen then
        log("%s: %s from %s arrived after the freeze -- not on this grid", m.raceId, tostring(m.state), m.driverId:sub(1, 8))
        return
    end
    local key = Mixed.personKey(m.driverId)
    local display = tostring(m.display or "?"):sub(1, 64)
    local state = m.state == "withdrawn" and "withdrawn" or "entered"
    local en = entriesOf(m.raceId)[m.driverId] or {}
    en.driverId, en.key, en.display, en.state = m.driverId, key, display, state
    en.seriesId = race.seriesId
    en.qualiMs = tonumber(m.qualiMs) or en.qualiMs
    en.assetId = (type(m.assetId) == "string" and #m.assetId == 36) and m.assetId or en.assetId
    en.enteredAt = en.enteredAt or tonumber(m.enteredAt) or U.now()
    entriesOf(m.raceId)[m.driverId] = en
    PaddockHumans.names[key] = display
    pcall(MySQL.insert.await, [[INSERT INTO paddock_entry (server_id, race_id, ncm_driver_id, person_key, display, series_id, state,
        quali_ms, asset_id, entered_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, ''), ?)
        ON DUPLICATE KEY UPDATE display = VALUES(display), state = VALUES(state), quali_ms = VALUES(quali_ms), asset_id = VALUES(asset_id)]],
        { U.sid(), m.raceId, m.driverId, key, display, race.seriesId, state, en.qualiMs or -1, en.assetId or "", en.enteredAt })
    log("%s: %s %s (%s)%s", m.raceId, display, state, key, en.qualiMs and (" quali %.2f s"):format(en.qualiMs / 1000) or " no time")
end)

--- The humans entered in a race (before its freeze), for paddock.mixed.gridOrder.
function PaddockHumans.entered(race)
    local out = {}
    for _, en in pairs(PaddockHumans.byRace[race.raceId] or {}) do
        if en.state == "entered" then
            out[#out + 1] = { key = en.key, driverId = en.driverId, display = en.display, qualiMs = en.qualiMs, enteredAt = en.enteredAt }
        end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

--- Is this race's frozen grid mixed?
function PaddockHumans.mixed(race)
    return race.frozen ~= nil and type(race.frozen.humans) == "table" and next(race.frozen.humans) ~= nil
end

function PaddockHumans.isHuman(race, id)
    return race.frozen ~= nil and type(race.frozen.humans) == "table" and race.frozen.humans[id] ~= nil
end

--- Each human's slot, from the same lane grid the bubble sets its NPCs down on (PaddockLive.gridSlots, by grid index).
function PaddockHumans.slots(race)
    if not PaddockHumans.mixed(race) then return nil end
    local route = PaddockWorld.route(race.routeId)
    if not route then return nil end
    local profile = NcmCore.get("data.grid_profiles").forRoot(race.routeId)
    local slots
    if route.oval then
        local path = PaddockLive.pathFor(race.routeId)
        slots = (path and path.ovalBehind and L.roadSlots(path.ovalBehind, #race.frozen.grid, profile))
            or L.ovalSlots(route.oval, #race.frozen.grid, profile)
    else
        slots = PaddockLive.gridSlots(route, #race.frozen.grid, profile)
    end
    local out = {}
    for k, id in ipairs(race.frozen.grid) do
        local h = race.frozen.humans[id]
        local s = slots and slots[k]
        if h and s then
            out[h.driverId] = { slot = k, x = s.x, y = s.y, z = s.z or (route.start and route.start.z) or route.oval.entry.z, heading = s.heading, yaw = s.yaw }
        end
    end
    return out
end

--- Send the league its humans' slots (at the freeze, and again every 30 s until the lights).
function PaddockHumans.sendGrid(race)
    local slots = PaddockHumans.slots(race)
    if not slots then return false end
    TriggerEvent("ncm:paddock.grid", race.raceId, { slots = slots, fieldSize = #race.frozen.grid, greenAt = race.opensAt })
    return true
end

--- L296 PRE-GRID: before the freeze, each entered human's PROVISIONAL slot, so the league can route them to the grid
--- minutes early instead of at T-50. The field's size is the guide's estimate and the NPCs' qualifying is not run yet,
--- so every human is put at the BACK (timed humans by time, then the untimed in entry order): the frozen grid can only
--- move a human forward from there -- a few rows up the same lane, never somewhere else.
function PaddockHumans.preGrid(race)
    local humans = PaddockHumans.entered(race)
    if #humans == 0 then return nil end
    local route = PaddockWorld.route(race.routeId)
    if not route then return nil end
    local s = NcmCore.get("paddock.season").TIERS[race.tier] or {}
    local n = math.floor((s.orgs or 12) / (s.divisions or 1)) * (s.carsPerOrg or 1)
    if route.oval and route.oval.fieldMax then n = math.min(n, route.oval.fieldMax) end
    n = math.max(n, #humans)
    table.sort(humans, function(a, b)
        local ta, tb = tonumber(a.qualiMs), tonumber(b.qualiMs)
        if (ta ~= nil) ~= (tb ~= nil) then return ta ~= nil end
        if ta and tb and ta ~= tb then return ta < tb end
        if (a.enteredAt or 0) ~= (b.enteredAt or 0) then return (a.enteredAt or 0) < (b.enteredAt or 0) end
        return a.key < b.key
    end)
    local profile = NcmCore.get("data.grid_profiles").forRoot(race.routeId)
    local slots
    if route.oval then
        local path = PaddockLive.pathFor(race.routeId)
        slots = (path and path.ovalBehind and L.roadSlots(path.ovalBehind, n, profile)) or L.ovalSlots(route.oval, n, profile)
    else
        slots = PaddockLive.gridSlots(route, n, profile)
    end
    if not slots then return nil end
    local out = {}
    for i, h in ipairs(humans) do
        local k = n - #humans + i
        local sl = slots[k]
        if sl then
            out[h.driverId] = { slot = k, x = sl.x, y = sl.y, z = sl.z or (route.start and route.start.z) or (route.oval and route.oval.entry.z),
                heading = sl.heading, yaw = sl.yaw, qualified = tonumber(h.qualiMs) ~= nil }
        end
    end
    return out, n
end

local lastSend, lastPre = 0, 0
function PaddockHumans.tick(t)
    local sendGrid = t - lastSend >= 30
    if sendGrid then lastSend = t end
    -- L296: the pre-grid every 10 s, from preGridLeadSec before the start until the freeze
    local sendPre = t - lastPre >= 10
    if sendPre then lastPre = t end
    if sendPre then
        local lead = PaddockSettings.get("preGridLeadSec", 900)
        for _, race in pairs(PaddockRaces.byId) do
            if (race.state == "scheduled" or race.state == "priced") and not race.frozen and race.opensAt > t
                and race.opensAt - t <= lead and PaddockHumans.byRace[race.raceId] then
                local okP, slots, n = pcall(PaddockHumans.preGrid, race)
                if okP and slots then
                    TriggerEvent("ncm:paddock.pregrid", race.raceId, { slots = slots, fieldSize = n, greenAt = race.opensAt, provisional = true })
                elseif not okP then
                    log("%s: pre-grid failed: %s", race.raceId, tostring(slots))
                end
            end
        end
    end
    for _, race in pairs(PaddockRaces.byId) do
        if (race.state == "scheduled" or race.state == "priced") and race.opensAt > t
            and race.opensAt - t <= Mixed.FREEZE_LEAD_SEC and not race.frozen then
            PaddockRaces.freeze(race)
        end
        if sendGrid and (race.state == "scheduled" or race.state == "priced") and race.opensAt > t and race.opensAt - t <= Mixed.FREEZE_LEAD_SEC + 60
            and PaddockHumans.mixed(race) then
            pcall(PaddockHumans.sendGrid, race)
        end
    end
end

AddEventHandler("ncm:paddock.human.result", function(raceId, rows)
    if type(raceId) ~= "string" or type(rows) ~= "table" then return end
    local race = PaddockRaces.byId[raceId]
    PaddockHumans.results[raceId] = PaddockHumans.results[raceId] or {}
    for _, r in ipairs(rows) do
        if type(r) == "table" and type(r.driverId) == "string" then
            local key = Mixed.personKey(r.driverId)
            local state = ({ finished = "finished", dnf = "dnf", dns = "dns", dsq = "dsq" })[tostring(r.state)] or "dns"
            if state == "finished" and race and race.opensAt and tonumber(r.rawFinishMs) then
                PaddockHumans.finishedAt[raceId] = PaddockHumans.finishedAt[raceId] or {}
                PaddockHumans.finishedAt[raceId][key] = PaddockHumans.finishedAt[raceId][key] or (race.opensAt + tonumber(r.rawFinishMs) / 1000)
            end
            PaddockHumans.results[raceId][key] = { rawFinishMs = tonumber(r.rawFinishMs), penaltyMs = tonumber(r.penaltyMs),
                state = state, finishMs = tonumber(r.finishMs),
                progressFrac = math.max(0, math.min(1, (tonumber(r.progressPct) or 0) / 100)), dnfReason = r.dnfReason, driverId = r.driverId }
            pcall(MySQL.update.await, [[UPDATE paddock_entry SET result_state = ?, finish_ms = NULLIF(?, -1), progress_pct = ?
                WHERE server_id = ? AND race_id = ? AND ncm_driver_id = ?]],
                { state, tonumber(r.finishMs) or -1, tonumber(r.progressPct) or 0, U.sid(), raceId, r.driverId })
            log("%s: %s %s%s", raceId, PaddockHumans.names[key] or key, state, r.finishMs and (" %.2f s"):format(r.finishMs / 1000) or "")
        end
    end
    if not race then log("result for %s, which is not in memory", raceId) end
end)

AddEventHandler("ncm:paddock.human.progress", function(raceId, rows)
    if type(raceId) ~= "string" or type(rows) ~= "table" then return end
    local target = liveProgress[raceId] or {}
    liveProgress[raceId] = target
    for _, r in ipairs(rows) do
        if type(r) == "table" and type(r.driverId) == "string" then
            local key = Mixed.personKey(r.driverId)
            if (tonumber(r.progressPct) or 0) >= 100 then
                PaddockHumans.finishedAt[raceId] = PaddockHumans.finishedAt[raceId] or {}
                PaddockHumans.finishedAt[raceId][key] = PaddockHumans.finishedAt[raceId][key] or (tonumber(r.finishedAt) or U.now())
            end
            PaddockHumans.penaltyMs[raceId] = PaddockHumans.penaltyMs[raceId] or {}
            PaddockHumans.penaltyMs[raceId][key] = math.floor((tonumber(r.incidentSec) or 0) * 1000 + 0.5)
            local reported = math.max(0, math.min(1, (tonumber(r.progressPct) or 0) / 100))
            -- A delayed or duplicated League update must not put a human back on an earlier lap.
            target[key] = math.max(target[key] or 0, reported)
        end
    end
end)

--- A mixed race's close waits for its humans' results (or HUMAN_RESULT_WAIT_SEC past the green). Once the race is
--- flagged the league closes its session at the same moment, so the wait is a few seconds for the result to arrive.
function PaddockHumans.holds(race, t)
    if not PaddockHumans.mixed(race) then return false end
    local res = PaddockHumans.results[race.raceId] or {}
    for key in pairs(race.frozen.humans) do
        if not res[key] then
            if race.flagAt then return t < race.flagAt + 20 end
            return t < race.opensAt + Mixed.HUMAN_RESULT_WAIT_SEC
        end
    end
    return false
end

--- The first moment a human of this race was home (unix), or nil -- one of the candidates for the leader (the flag).
function PaddockHumans.firstFinishAt(race)
    local best
    for _, at in pairs(PaddockHumans.finishedAt[race.raceId] or {}) do if not best or at < best then best = at end end
    return best
end

--- The merged classification, written as the race's result. Returns the merged entrants (or nil when not mixed).
function PaddockHumans.merge(race, entrants)
    if not PaddockHumans.mixed(race) then return nil end
    local res = PaddockHumans.results[race.raceId] or {}
    local gridOf = {}
    for k, id in ipairs(race.frozen.grid or {}) do gridOf[id] = k end
    local humans = {}
    for key in pairs(race.frozen.humans) do
        local r = res[key] or { state = "dns" }
        humans[#humans + 1] = { key = key, state = r.state, finishMs = r.finishMs, progressFrac = r.progressFrac,
            grid = gridOf[key], dnfReason = r.dnfReason or (res[key] == nil and "no_result" or nil),
            rawFinishMs = r.rawFinishMs, penaltyMs = r.penaltyMs }
    end
    table.sort(humans, function(a, b) return a.key < b.key end)
    -- the model's own rows carry what the stored ones do not: raw crossing, penalties, how far a flagged car got
    local fromModel = {}
    for _, e in ipairs(race.modelEntrants or {}) do fromModel[e.id] = e end
    local npc = {}
    for _, e in ipairs(entrants or {}) do
        if not Mixed.isHuman(e.id) then
            local m = fromModel[e.id]
            if m then
                e.rawFinishMs, e.penaltyMs = m.rawFinishMs, m.penaltyMs
                if m.dnfReason == "flagged" and race.model then e.progressFrac = (m.reachedM or 0) / math.max(1, race.model.lengthM); e.dnfReason = "flagged" end
            end
            npc[#npc + 1] = e
        end
    end
    local merged = Mixed.merge(npc, humans)
    local ok, err = PaddockLive.writeResult(race, merged, "mixed", "mixed_grid", { mode = "mixed_grid", humans = #humans })
    if not ok then log("%s: merged result NOT written: %s", race.raceId, tostring(err)) return nil end
    local places, n = Mixed.humanPlaces(merged)
    local byDriver = {}
    for key, pos in pairs(places) do
        local h = race.frozen.humans[key]
        if h then byDriver[h.driverId] = pos end
    end
    -- the ceremony: the board as they crossed, then as classified with penalties (owner, 2026-10-02)
    local board = {}
    for i, row in ipairs(Mixed.ceremony(merged)) do
        local h = race.frozen.humans[row.id]
        local p = not h and PaddockStore.world.people[row.id] or nil
        board[i] = { pos = row.pos, rawPos = row.rawPos, moved = row.moved, name = h and h.display or (p and p.display) or "?",
            human = h and true or nil, driverId = h and h.driverId or nil, state = row.state,
            rawMs = row.rawMs, finalMs = row.finalMs, penMs = (row.penaltyMs or 0) > 0 and row.penaltyMs or nil, reason = row.dnfReason }
    end
    table.sort(board, function(a, b) return a.pos < b.pos end)
    TriggerEvent("ncm:paddock.classified", race.raceId, { places = byDriver, fieldSize = n, board = board })
    log("%s: mixed classification written, %d human(s) in a field of %d", race.raceId, #humans, n)
    return merged
end

--- Billie's rule (L250): no paper on a league you are entered in this season.
function PaddockHumans.enteredInSeries(driverId, seriesId)
    for raceId, list in pairs(PaddockHumans.byRace) do
        local en = list[driverId]
        local race = PaddockRaces.byId[raceId]
        if en and en.state == "entered" and race and race.seriesId == seriesId then return true end
    end
    local n = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM paddock_entry WHERE server_id = ? AND ncm_driver_id = ? AND series_id = ?
        AND state = 'entered' AND entered_at >= ?]], { U.sid(), driverId, seriesId, U.now() - 30 * 86400 })) or 0
    return n > 0
end

local pidFor
--- The connected player ids of a mixed race's humans (the broadcast sends them the whole field wherever they are).
function PaddockHumans.playerIds(race)
    local out = {}
    if not PaddockHumans.mixed(race) then return out end
    for _, h in pairs(race.frozen.humans) do
        local pid = pidFor(h.driverId)
        if pid then out[#out + 1] = tonumber(pid) end
    end
    return out
end

pidFor = function(driverId)
    local pid = PaddockPlayers.pidOf(driverId)
    if pid then return pid end
    local okA, all = pcall(Open77.players.all)
    for _, p in ipairs(okA and all or {}) do
        local d = PaddockPlayers.driver(p)
        if d and d.ncmDriverId == driverId then return tonumber(p) end
    end
    return nil
end

--- LIVE rows for a mixed race's humans: where each one is on the line, from their player's position.
function PaddockHumans.liveRows(race, model, project)
    local out = {}
    if not PaddockHumans.mixed(race) then return out end
    local res = PaddockHumans.results[race.raceId] or {}
    for key, h in pairs(race.frozen.humans) do
        local r = res[key]
        local d = 0
        liveDistance[race.raceId] = liveDistance[race.raceId] or {}
        local distances = liveDistance[race.raceId]
        if r and r.state == "finished" then d = model.lengthM
        else
            -- Gate progress is a FLOOR only on an oval (laps, L282). On a point-to-point the gates are the start and the
            -- finish, so "1 of 2" -- crossing the start -- read as half the race, and the monotonic distance kept the
            -- owner at mid-race from the lights: always P1 on the tower (2026-10-02). There the street position rules.
            local frac = PaddockWorld.route(race.routeId) and PaddockWorld.route(race.routeId).oval
                and liveProgress[race.raceId] and liveProgress[race.raceId][key] or nil
            local prior = distances[key] or ((frac or 0) * model.lengthM)
            -- Bound the physical projection around this human's last known distance. Oval coordinates repeat
            -- every lap; an unrestricted nearest-point query always prefers lap one. A 300 m window covers
            -- several seconds of travel while keeping the projection on the current lap.
            local pid = pidFor(h.driverId)
            local okP, p = pcall(Open77.players.get, pid)
            local physical = pid and okP and type(p) == "table" and type(p.position) == "table"
                and project(p.position, math.max(0, prior - 300), math.min(model.lengthM, prior + 300)) or nil
            d = math.max(prior, (frac or 0) * model.lengthM, physical or 0)
            distances[key] = math.min(model.lengthM, d)
        end
        -- a finished human's time from the league is already corrected (penalties in it); a racing one carries them
        local pen = (not r) and (PaddockHumans.penaltyMs[race.raceId] or {})[key] or 0
        out[#out + 1] = { id = key, d = d, human = true, name = h.display, driverId = h.driverId, penaltyMs = pen,
            state = r and (r.state == "finished" and "finished" or "out") or "racing", finishMs = r and r.finishMs or nil }
    end
    return out
end
