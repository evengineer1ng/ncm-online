-- ncm_paddock / server / world -- boot, genesis and the lookups every other file uses.
PaddockWorld = { ready = false }

local U = PaddockUtil
local log = U.logger("world")
local World = NcmCore.get("paddock.world")
local Seasons = NcmCore.get("competition.seasons")
local Season = NcmCore.get("paddock.season")
local Routes = NcmCore.get("course.routes")
local Conditions = NcmCore.get("world.conditions")

--- Load the world, or run genesis when this server has none. Genesis is stepped with a yield per org so it never
--- nears the instruction quota (KB-211); it is deterministic for its seed, which is drawn once and stored.
function PaddockWorld.boot()
    local w = PaddockStore.load()
    if w then
        World.reindex(w)
        PaddockStore.world = w
        log("loaded world seed-commit=%s season=%s orgs=%d people=%d", NcmCore.get("vocabulary.hash").commit(w.seed),
            w.seasonId, #w.orgOrder, #w.personOrder)
        -- L249: a world from before league pools grows into them here (street leagues to ~56, sanctioned rosters
        -- deeper), a few people per slice; idempotent, so every boot of a full world does nothing
        local grown = 0
        while true do
            local touched, more = World.growPools(w, 10)
            for _, p in ipairs(touched) do PaddockStore.markPerson(p.id) end
            grown = grown + #touched
            if not more then break end
            Wait(0)
        end
        -- L249: every league takes its authored name (approved by the owner); the old generated name goes
        local renamed = 0
        for id, s in pairs(w.series) do
            local name = NcmCore.get("paddock.names").LEAGUES[id]
            if name and s.name ~= name then
                log("league %s renamed: %s -> %s", id, tostring(s.name), name)
                w.takenSeriesNames[s.name] = nil
                s.name = name
                w.takenSeriesNames[name] = true
                PaddockStore.markSeries(id)
                renamed = renamed + 1
            end
        end
        if renamed > 0 then PaddockStore.flush() end
        if grown > 0 then
            PaddockStore.flush()
            log("league pools grown (L249): %d people joined or created; %d people now", grown, #w.personOrder)
        end
        -- W-1 (L303): the world that exists is history's cast; record its seed once so every reconstruction replays it
        pcall(MySQL.update.await, "INSERT IGNORE INTO racing_week_genesis (server_id, seed, recorded_at) VALUES (?, ?, ?)",
            { U.sid(), w.seed, U.now() })
        PaddockWorld.ready = true
        return w
    end
    local season = Seasons.atUtc(U.now()).id
    -- W-1 (L303): a reconstruction is born from the historical seed -- the same cast, the same Day 1 -- never a new one
    local okH, hist = pcall(MySQL.scalar.await, "SELECT seed FROM racing_week_genesis WHERE server_id = ?", { U.sid() })
    local seed = okH and tonumber(hist) or nil
    if seed then log("GENESIS from the historical seed (commit %s)", NcmCore.get("vocabulary.hash").commit(seed))
    else
        seed = math.random(1, 2147483646)
        pcall(MySQL.update.await, "INSERT IGNORE INTO racing_week_genesis (server_id, seed, recorded_at) VALUES (?, ?, ?)",
            { U.sid(), seed, U.now() })
        log("GENESIS from a NEW seed (no history yet); recorded as the historical seed")
    end
    log("GENESIS begins season=%s", season)
    local b = World.newBuilder(seed, season)
    while b.step() do Wait(0) end
    local nw = b.world
    nw.createdAt = U.now()
    nw.recentTemplates = {}
    World.reindex(nw)
    local ok, err = PaddockStore.saveAll(nw)
    if not ok then log("GENESIS save FAILED: %s", tostring(err)); return nil end
    PaddockStore.world = nw
    PaddockWorld.ready = true
    log("GENESIS done: %d orgs, %d people, %d sponsors, %d series", #nw.orgOrder, #nw.personOrder, #nw.sponsorOrder,
        (function() local n = 0 for _ in pairs(nw.series) do n = n + 1 end return n end)())
    PaddockStory.record({ NcmCore.get("paddock.tape").event("founded", "genesis", U.now(), {
        facts = { org = "The Paddock", tier = "every", founder = "Night City" }, salience = 40 }) })
    return nw
end

function PaddockWorld.w() return PaddockStore.world end

function PaddockWorld.person(id) local w = PaddockStore.world return w and w.people[id] end
function PaddockWorld.org(id) local w = PaddockStore.world return w and w.orgs[id] end
function PaddockWorld.personName(id)
    -- L250: a human on a mixed grid is known by the name they entered under
    if PaddockHumans and NcmCore.get("paddock.mixed").isHuman(id) then
        local who = PaddockHumans.names[id] and { display = PaddockHumans.names[id] } or PaddockHumans.identity(id)
        return who and who.display or "?"
    end
    local p = PaddockWorld.person(id) return p and p.display or "?"
end
-- an entrant with no team is an independent street racer (L249)
function PaddockWorld.orgName(id)
    if id == nil or id == "" then return "Independent" end
    local o = PaddockWorld.org(id)
    return o and o.name or "?"
end
function PaddockWorld.seriesName(id)
    local w = PaddockStore.world
    local s = w and w.series[id]
    return s and s.name or tostring(id)
end

local routeCache = {}
function PaddockWorld.route(rootId)
    if routeCache[rootId] then return routeCache[rootId] end
    local r = Routes.resolve(rootId)
    if r then routeCache[rootId] = r end
    return r
end
function PaddockWorld.routeName(rootId)
    local r = PaddockWorld.route(rootId)
    return r and r.name or tostring(rootId)
end

-- The weather plan, read from the table ncm_league's weather service writes (this VM cannot call NcmWeather).
-- Refreshed every ten minutes; the plan runs seven days ahead, so a race never waits on it.
local planRows, planAt = {}, 0
function PaddockWorld.weatherRows()
    local t = U.now()
    if t - planAt > 600 or #planRows == 0 then
        local ok, rows = pcall(MySQL.query.await, [[SELECT starts_at_utc, weather FROM weather_transition
            WHERE scope = 'default' AND starts_at_utc BETWEEN ? AND ? ORDER BY starts_at_utc]], { t - 86400, t + 8 * 86400 })
        if ok and rows then
            local out = {}
            for i, r in ipairs(rows) do out[i] = { startsAtUtc = tonumber(r.starts_at_utc), weather = tostring(r.weather) } end
            planRows = out
            planAt = t
        end
    end
    return planRows
end

--- Conditions for an instant: weather plan + Eastern light (L221). Dry and day when no plan exists yet.
function PaddockWorld.conditionsAt(utc)
    local rows = PaddockWorld.weatherRows()
    if #rows == 0 then
        local sod = NcmCore.get("world.clock").eastern(utc).secondsOfDay
        return { weather = "sunny", family = "dry", roadWetness = 0, secondsOfDay = sod, light = Conditions.lightOf(sod),
            bucket = Conditions.bucket(0, Conditions.lightOf(sod)), noPlan = true }
    end
    return Conditions.at(rows, utc)
end

--- The human-managed orgs, keyed by org id -> driver id.
function PaddockWorld.humanManaged()
    local out = {}
    local w = PaddockStore.world
    for _, oid in ipairs(w and w.orgOrder or {}) do
        local o = w.orgs[oid]
        if o.humanManagerDriverId and o.lifecycle == "active" then out[oid] = o.humanManagerDriverId end
    end
    return out
end

--- The org a human manages, or nil.
function PaddockWorld.orgManagedBy(driverId)
    local w = PaddockStore.world
    for _, oid in ipairs(w and w.orgOrder or {}) do
        local o = w.orgs[oid]
        if o.humanManagerDriverId == driverId and o.lifecycle == "active" then return o end
    end
    return nil
end

function PaddockWorld.cupNow() return Season.cupOf(U.now()) end
