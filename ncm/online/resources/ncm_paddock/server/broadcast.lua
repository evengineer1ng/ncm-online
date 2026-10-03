-- ncm_paddock / server / broadcast -- the Paddock's feed to NCM Broadcast (L235): names over its cars and the rows of
-- the opt-in timing tower, once a second, to the players near a race.
--
-- "Near" is within broadcastRadiusM of any of the race's physical cars (a street run, a staged grid, or cars the
-- bubble made physical) -- the only cars a client can draw a name over. Each row carries the car's OPEN//77 vehicle
-- id; the client maps it to the engine entity. The rows are PaddockViews.live's, so the F6 LIVE tab and the tower
-- never disagree.
PaddockBroadcast = {}

local Clock = NcmCore.get("world.clock")
local U = PaddockUtil

local function set(k, d) return PaddockSettings.get(k, d) end
local function dist2(a, b) local dx, dy = a.x - b.x, a.y - b.y return dx * dx + dy * dy end

local function positions()
    local ok, list = pcall(Open77.players.positions)
    return (ok and type(list) == "table") and list or {}
end

--- A staged grid, before the lights: names in grid order, so the field can be read on the line.
local function gridRows(race, lr)
    local rows = {}
    local taken = {}
    for _, c in ipairs(lr.cars or {}) do
        local p = PaddockStore.world.people[c.personId]
        local o = PaddockStore.world.orgs[c.orgId or ""]
        rows[#rows + 1] = { pos = c.slot, id = c.personId, name = p and p.display or "?", org = o and o.name, gap = "GRID",
            state = "racing", physical = true, vid = c.vehicleId }
        taken[c.personId] = true
    end
    -- a mixed grid's humans hold the slots no NPC car was set down on (L250)
    local f = race.frozen
    if f and f.humans then
        for k, id in ipairs(f.grid or {}) do
            local h = f.humans[id]
            if h and not taken[id] then
                rows[#rows + 1] = { pos = k, id = id, name = h.display or "?", org = PaddockHumans.teamOf(h.driverId), gap = "GRID", state = "racing",
                    human = true, driverId = h.driverId }
            end
        end
    end
    table.sort(rows, function(a, b) return (a.pos or 99) < (b.pos or 99) end)
    return { raceId = race.raceId, title = ("%s · %s"):format(PaddockWorld.seriesName(race.seriesId), PaddockWorld.routeName(race.routeId)),
        sub = ("ON THE GRID · LIGHTS %s ET"):format(Clock.hhmm(race.opensAt)), rows = rows }
end

--- A frozen grid that is not (yet) a staged street run -- the bubble's pre-grid, or nothing physical at all: the
--- whole field in grid order, humans included, so an entrant's tower agrees with the P-number on their HUD.
local function frozenGridRows(race)
    local f = race.frozen
    if not (f and type(f.grid) == "table" and #f.grid > 0) then return nil end
    local rows = {}
    for k, id in ipairs(f.grid) do
        local h = f.humans and f.humans[id]
        local p = not h and PaddockStore.world.people[id] or nil
        local o = p and PaddockStore.world.orgs[p.orgId or ""] or nil
        rows[#rows + 1] = { pos = k, id = id, name = h and h.display or (p and p.display) or "?", org = o and o.name or (h and PaddockHumans.teamOf(h.driverId) or nil),
            gap = "GRID", state = "racing", human = h and true or nil, driverId = h and h.driverId or nil }
    end
    return { raceId = race.raceId, title = ("%s · %s"):format(PaddockWorld.seriesName(race.seriesId), PaddockWorld.routeName(race.routeId)),
        sub = ("ON THE GRID · LIGHTS %s ET"):format(Clock.hhmm(race.opensAt)), rows = rows }
end

local function liveRows(race)
    local v = PaddockViews.live(nil, { raceId = race.raceId })
    if not v or v.raceId ~= race.raceId then return nil end
    local e = v.elapsed or 0
    -- an oval counts the leader's laps (L236)
    local route = PaddockWorld.route(race.routeId)
    local laps = route and route.oval and route.oval.laps
    local lap = ""
    if laps and v.rows and v.rows[1] then
        lap = (" · LAP %d/%d"):format(math.max(1, math.min(laps, tonumber(v.rows[1].lap) or 1)), laps)
    end
    -- the flag: once the leader is home, everyone sees the countdown to the close (owner, 2026-10-02)
    local flag = ""
    if race.flagAt then
        local left = math.max(0, race.flagAt - U.now())
        flag = (" · FLAG %d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
    end
    return { raceId = race.raceId, title = ("%s · %s"):format(v.series or "", v.route or ""), flagAt = race.flagAt,
        sub = ("%s%s · %d:%02d%s"):format(v.street and "STREET RUN" or "LIVE", lap, math.floor(e / 60), e % 60, flag), rows = v.rows }
end

function PaddockBroadcast.tick()
    if not set("broadcastEnabled", true) then return end
    local people = positions()
    if next(people) == nil then return end
    local r2 = set("broadcastRadiusM", 600) ^ 2
    for _, race in pairs(PaddockRaces.byId) do
        local lr = PaddockLive.byRace[race.raceId]
        local msg
        local mixed = PaddockHumans and PaddockHumans.mixed(race)
        if lr and lr.state == "staging" and lr.cars and #lr.cars > 0 then
            msg = gridRows(race, lr)
        elseif race.state == "running" and race.model and U.now() >= race.opensAt then
            msg = liveRows(race)
        elseif mixed and race.opensAt > U.now() and race.opensAt - U.now() <= 120 then
            msg = frozenGridRows(race)
        end
        -- A mixed race's own humans get the whole field wherever they are: it is their race's running order (HUD
        -- position, tower), not a spectator's view of cars nearby (2026-10-02: the tower showed a field of one).
        local entrants = {}
        if msg and mixed then
            msg.mixed, msg.d = true, 0
            for _, pid in ipairs(PaddockHumans.playerIds(race)) do
                entrants[pid] = true
                TriggerClientEvent("ncm:broadcast.paddock", pid, msg)
            end
        end
        -- only a race with a physical car somewhere has anything to put a name over
        local cars = {}
        for _, r in ipairs(msg and msg.rows or {}) do
            if r.vid then
                local ok, pos = pcall(Open77.vehicles.getPosition, r.vid)
                if ok and type(pos) == "table" then cars[#cars + 1] = pos end
            end
        end
        if #cars > 0 then
            for pid, pos in pairs(people) do
                if not entrants[tonumber(pid)] then
                    local best
                    for _, c in ipairs(cars) do
                        local d = dist2(pos, c)
                        if not best or d < best then best = d end
                    end
                    if best and best <= r2 then
                        msg.d = math.floor(math.sqrt(best))
                        TriggerClientEvent("ncm:broadcast.paddock", tonumber(pid), msg)
                    end
                end
            end
        end
        Wait(0)
    end
end

function PaddockBroadcast.start()
    CreateThread(function()
        while true do
            local ok, err = pcall(PaddockBroadcast.tick)
            if not ok then print("[ncm_paddock/broadcast] tick failed: " .. tostring(err)) end
            Wait(1000)
        end
    end)
end
