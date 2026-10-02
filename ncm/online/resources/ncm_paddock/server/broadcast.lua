-- ncm_paddock / server / broadcast -- the Paddock's feed to NCM Broadcast (L235): names over its cars and the rows of
-- the opt-in timing tower, once a second, to the players near a race.
--
-- "Near" is within broadcastRadiusM of any of the race's physical cars (a street run, a staged grid, or cars the
-- bubble made physical) -- the only cars a client can draw a name over. Each row carries the car's OPEN//77 vehicle
-- id; the client maps it to the engine entity. The rows are PaddockViews.live's, so the F6 LIVE tab and the tower
-- never disagree.
PaddockBroadcast = {}

local Clock = NcmCore.get("world.clock")

local function set(k, d) return PaddockSettings.get(k, d) end
local function dist2(a, b) local dx, dy = a.x - b.x, a.y - b.y return dx * dx + dy * dy end

local function positions()
    local ok, list = pcall(Open77.players.positions)
    return (ok and type(list) == "table") and list or {}
end

--- A staged grid, before the lights: names in grid order, so the field can be read on the line.
local function gridRows(race, lr)
    local rows = {}
    for _, c in ipairs(lr.cars or {}) do
        local p = PaddockStore.world.people[c.personId]
        local o = PaddockStore.world.orgs[c.orgId or ""]
        rows[#rows + 1] = { pos = c.slot, id = c.personId, name = p and p.display or "?", org = o and o.name, gap = "GRID",
            state = "racing", physical = true, vid = c.vehicleId }
    end
    table.sort(rows, function(a, b) return (a.pos or 99) < (b.pos or 99) end)
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
    return { raceId = race.raceId, title = ("%s · %s"):format(v.series or "", v.route or ""),
        sub = ("%s%s · %d:%02d"):format(v.street and "STREET RUN" or "LIVE", lap, math.floor(e / 60), e % 60), rows = v.rows }
end

function PaddockBroadcast.tick()
    if not set("broadcastEnabled", true) then return end
    local people = positions()
    if next(people) == nil then return end
    local r2 = set("broadcastRadiusM", 600) ^ 2
    for _, race in pairs(PaddockRaces.byId) do
        local lr = PaddockLive.byRace[race.raceId]
        local msg
        if lr and lr.state == "staging" and lr.cars and #lr.cars > 0 then
            msg = gridRows(race, lr)
        elseif race.state == "running" and race.model then
            msg = liveRows(race)
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
