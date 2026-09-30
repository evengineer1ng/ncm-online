-- ncm_paddock / server / main -- boot and the one scheduler loop.
--
-- Boot waits for ncm_league's migrations to reach 052, checks that this resource's `serverId` is the world's (its
-- rows must key the same way as the binding table's), loads or creates the world, and starts the loop. Every pass is
-- bounded: at most one race run, one resolve and one pricing per tick, and the daily/Cup/season passes are
-- idempotent by key, so a server that was down for a day catches up over a few minutes instead of in one handler.
local U = PaddockUtil
local log = U.logger("main")

local SCHEMA_REQUIRED = 52

local function schemaReady()
    local ok, v = pcall(MySQL.scalar.await, "SELECT MAX(version) FROM schema_migrations")
    return ok and (tonumber(v) or 0) >= SCHEMA_REQUIRED
end

local function serverIdCheck()
    local n = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM ncm_driver_binding WHERE server_id = ?", { U.sid() })) or 0
    if n == 0 then
        log("WARNING: serverId '%s' has no driver bindings. If this server's worlds use another serverId, set ncm_paddock's " ..
            "serverId tunable to match ncm_league and ncm_world, or the Paddock will not know its players.", U.sid())
    end
end

local lastCalibration, lastPrune, lastSpotlight = 0, 0, 0

local function prune(t)
    local sid = U.sid()
    local detailDays = PaddockSettings.get("pruneDetailDays", 14)
    local eventDays = PaddockSettings.get("pruneEventDays", 30)
    local newsDays = PaddockSettings.get("pruneNewsDays", 90)
    pcall(MySQL.update.await, "UPDATE paddock_race SET detail_json = NULL WHERE server_id = ? AND state = 'resolved' AND window_opens_at < ?",
        { sid, t - detailDays * 86400 })
    pcall(MySQL.update.await, "DELETE FROM paddock_event WHERE server_id = ? AND retain = 0 AND salience < 50 AND at < ?",
        { sid, t - eventDays * 86400 })
    pcall(MySQL.update.await, [[DELETE FROM paddock_news WHERE server_id = ? AND at < ? AND kind NOT IN
        ('season_title','cup_title','fold','retirement','founded','promotion','relegation')]], { sid, t - newsDays * 86400 })
    pcall(MySQL.update.await, "DELETE FROM paddock_push WHERE server_id = ? AND day_index < ?",
        { sid, NcmCore.get("world.clock").eastern(t).dayIndex - 7 })
    -- results older than the previous season are summarised by the standings archive; lines of settled races go
    pcall(MySQL.update.await, [[DELETE l FROM paddock_line l JOIN paddock_race r ON r.server_id = l.server_id AND r.race_id = l.race_id
        WHERE l.server_id = ? AND l.state = 'settled' AND r.window_opens_at < ?]], { sid, t - detailDays * 86400 })
    log("prune pass done")
end

local function tick()
    local t = U.now()
    PaddockRaces.materialise(t)
    PaddockRaces.tick(t)
    if PaddockSettings.get("liveEnabled", true) then PaddockLive.tick(t) end
    PaddockLife.cupBoundary(t)
    PaddockLife.rollover(t)
    PaddockLife.daily(t)
    if t - lastSpotlight >= 60 then lastSpotlight = t; PaddockSpotlight.scan(t) end
    if t - lastCalibration >= 3600 then lastCalibration = t; PaddockCalibration.recompute() end
    if t - lastPrune >= 86400 then lastPrune = t; prune(t) end
    PaddockStore.flush()
end

CreateThread(function()
    Wait(3000)
    while not (MySQL.isReady and MySQL.isReady()) do Wait(2000) end
    while not schemaReady() do
        log("waiting for schema %d (ncm_league migrations)", SCHEMA_REQUIRED)
        Wait(10000)
    end
    while not PaddockSettings.get("paddockEnabled", true) do Wait(30000) end
    serverIdCheck()
    if not PaddockWorld.boot() then log("BOOT FAILED: no world") return end
    PaddockCalibration.load()
    PaddockRaces.load()
    Wait(0)                                  -- each boot step gets its own slice of the instruction quota (KB-211)
    PaddockLive.boot()
    Wait(0)
    PaddockGarages.start()
    PaddockBubble.start()
    PaddockClock.start()
    lastCalibration = U.now() - 3500     -- first recompute a minute after boot, not inside it
    log("the Paddock is running (season %s)", PaddockStore.world.seasonId)
    while true do
        if PaddockSettings.get("paddockEnabled", true) then
            local ok, err = pcall(tick)
            if not ok then log("tick FAILED: %s", tostring(err)) end
        end
        Wait(PaddockSettings.get("tickSeconds", 5) * 1000)
    end
end)
