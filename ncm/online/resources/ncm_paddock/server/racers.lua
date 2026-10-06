-- ncm_paddock / server / racers -- every racer on the map while racing happens (owner, 2026-10-04: "custom racer icons
-- ... visible in map. including your own race / minimap and ambient races as they happen").
--
-- Every `racerIconsEverySec` (2 s) each running Paddock race -- simulated, bubble, street or mixed -- is read exactly as
-- the LIVE view reads it (`PaddockViews.rowsFor`: the continuous model, cars physically in a bubble where they really
-- are, humans where their players are) and each car still racing becomes one point on its route
-- (`paddock.racestate.pointAt`). One broadcast to every client: `ncm:paddock:racers { at, races = { { r, tier, series,
-- cars = { { k, x, y, z, n, p, d, g?, v?, h?, pid? } } } } }` (d metres along the line, g gap ms, v the vehicle while
-- physical). The same table is raised server-side as `ncm:paddock:racers:server` for ncm_observer (doc 46).
-- Clients draw them (client/racers.lua). Coverage, not a leak: the live view already shows the same order to anyone.
PaddockRacers = { stats = { sent = 0, cars = 0 } }

local U = PaddockUtil
local log = U.logger("racers")
local function set(k, d) return PaddockSettings.get(k, d) end

local function pidMap()
    local out = {}
    local ok, all = pcall(Open77.players.all)
    for _, raw in ipairs(ok and all or {}) do
        local pid = tonumber(raw)
        local d = pid and PaddockPlayers.driver(pid)
        if d and d.ncmDriverId then out[d.ncmDriverId] = pid end
    end
    return out
end

function PaddockRacers.snapshot(t)
    local Racestate = NcmCore.get("paddock.racestate")
    local w = PaddockStore.world
    local pids = pidMap()
    local races, total = {}, 0
    for _, race in pairs(PaddockRaces.byId or {}) do
        if race.state == "running" and race.model and t >= race.opensAt then
            local okR, rows, model = pcall(PaddockViews.rowsFor, race, t)
            if okR and type(rows) == "table" and model then
                local cars = {}
                for _, r in ipairs(rows) do
                    if r.d and r.state ~= "finished" and r.state ~= "out" and r.state ~= "dnf" then
                        local pt = Racestate.pointAt(model, math.max(0, math.min(model.lengthM, r.d)))
                        local p = w.people[r.id]
                        cars[#cars + 1] = {
                            k = tostring(r.id), x = math.floor(pt.x * 10) / 10, y = math.floor(pt.y * 10) / 10,
                            z = math.floor((pt.z or 0) * 10) / 10,
                            n = r.human and (r.name or "Driver") or (p and p.display) or tostring(r.id),
                            p = r.pos, h = r.human and 1 or nil, pid = r.human and r.driverId and pids[r.driverId] or nil,
                            -- NCM Observer (doc 46): distance along the line, gap to the leader, and the network
                            -- vehicle while the car is physical -- what the director and the lens need
                            d = math.floor(r.d), g = r.gapMs and math.floor(r.gapMs) or nil, v = r.vid,
                        }
                    end
                end
                if #cars > 0 then
                    total = total + #cars
                    races[#races + 1] = { r = race.raceId, tier = race.tier, series = PaddockWorld.seriesName(race.seriesId), cars = cars }
                end
            end
            Wait(0)                           -- one race per slice (KB-211)
        end
    end
    return { at = t, races = races }, total
end

function PaddockRacers.start()
    CreateThread(function()
        Wait(15000)
        local lastLog = 0
        while true do
            if set("racerIcons", true) and PaddockWorld.ready then
                local ok, snap, n = pcall(PaddockRacers.snapshot, U.now())
                if ok and snap then
                    pcall(TriggerClientEvent, "ncm:paddock:racers", -1, snap)
                    pcall(TriggerEvent, "ncm:paddock:racers:server", snap)   -- the same snapshot for ncm_observer
                    PaddockRacers.stats.sent = PaddockRacers.stats.sent + 1
                    PaddockRacers.stats.cars = n
                    if U.now() - lastLog >= 300 then
                        lastLog = U.now()
                        log("racer icons: %d race(s), %d car(s) on the map (%d broadcasts)", #snap.races, n, PaddockRacers.stats.sent)
                    end
                elseif not ok then
                    log("snapshot FAILED: %s", tostring(snap))
                end
            end
            Wait(math.max(1, set("racerIconsEverySec", 2)) * 1000)
        end
    end)
end
