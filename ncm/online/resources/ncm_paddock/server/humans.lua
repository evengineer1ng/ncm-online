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
PaddockHumans = { byRace = {}, results = {}, names = {} }

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

local lastSend = 0
function PaddockHumans.tick(t)
    local sendGrid = t - lastSend >= 30
    if sendGrid then lastSend = t end
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
            PaddockHumans.results[raceId][key] = { state = state, finishMs = tonumber(r.finishMs),
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
            local reported = math.max(0, math.min(1, (tonumber(r.progressPct) or 0) / 100))
            -- A delayed or duplicated League update must not put a human back on an earlier lap.
            target[key] = math.max(target[key] or 0, reported)
        end
    end
end)

--- A mixed race's close waits for its humans' results (or HUMAN_RESULT_WAIT_SEC past the green).
function PaddockHumans.holds(race, t)
    if not PaddockHumans.mixed(race) then return false end
    local res = PaddockHumans.results[race.raceId] or {}
    for key in pairs(race.frozen.humans) do
        if not res[key] then return t < race.opensAt + Mixed.HUMAN_RESULT_WAIT_SEC end
    end
    return false
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
            grid = gridOf[key], dnfReason = r.dnfReason or (res[key] == nil and "no_result" or nil) }
    end
    table.sort(humans, function(a, b) return a.key < b.key end)
    local npc = {}
    for _, e in ipairs(entrants or {}) do if not Mixed.isHuman(e.id) then npc[#npc + 1] = e end end
    local merged = Mixed.merge(npc, humans)
    local ok, err = PaddockLive.writeResult(race, merged, "mixed", "mixed_grid", { mode = "mixed_grid", humans = #humans })
    if not ok then log("%s: merged result NOT written: %s", race.raceId, tostring(err)) return nil end
    local places, n = Mixed.humanPlaces(merged)
    local byDriver = {}
    for key, pos in pairs(places) do
        local h = race.frozen.humans[key]
        if h then byDriver[h.driverId] = pos end
    end
    TriggerEvent("ncm:paddock.classified", race.raceId, { places = byDriver, fieldSize = n })
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

local function pidFor(driverId)
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
            local frac = liveProgress[race.raceId] and liveProgress[race.raceId][key]
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
        out[#out + 1] = { id = key, d = d, human = true, name = h.display,
            state = r and (r.state == "finished" and "finished" or "out") or "racing", finishMs = r and r.finishMs or nil }
    end
    return out
end
