-- ncm_paddock / server / calibration -- human pace into NPC base pace (doc 44 §7).
--
-- Hourly: every human result that carries a schema-043 conditions stamp is bucketed by (route, NPC tier, condition
-- bucket) and summarised into `paddock_calibration`. The sim reads a bucket only once it clears the minimums;
-- otherwise the declared seeded baseline stands. At two humans (L223) most buckets never qualify, and the log says
-- which do, so "is the Paddock calibrated?" has an answer rather than a guess.
PaddockCalibration = { buckets = {}, computedAt = 0 }

local U = PaddockUtil
local log = U.logger("calibration")
local Cal = NcmCore.get("paddock.calibration")
local Conditions = NcmCore.get("world.conditions")

local function key(routeId, tier, bucket) return routeId .. "|" .. tier .. "|" .. bucket end

function PaddockCalibration.load()
    local rows = MySQL.query.await("SELECT * FROM paddock_calibration WHERE server_id = ?", { U.sid() }) or {}
    local b = {}
    for _, r in ipairs(rows) do
        b[key(r.route_id, r.tier, r.cond_bucket)] = { n = tonumber(r.n), drivers = tonumber(r.drivers),
            median = tonumber(r.median_ms), p25 = tonumber(r.p25_ms) }
    end
    PaddockCalibration.buckets = b
end

--- Recompute from stamped human results (the last 60 days, bounded). Yields while it works.
function PaddockCalibration.recompute()
    local sid, t = U.sid(), U.now()
    local samples = {}
    local y = U.yielder(200)
    local function add(routeId, seriesId, ms, driverId, wet, light)
        local tier = Cal.HUMAN_SERIES_TIER[seriesId or ""]
        if not tier or not routeId or not ms then return end
        local k = key(routeId, tier, Conditions.bucket(tonumber(wet) or 0, light))
        samples[k] = samples[k] or {}
        local list = samples[k]
        list[#list + 1] = { ms = tonumber(ms), driverId = driverId }
        y()
    end
    local races = MySQL.query.await([[SELECT e.route_id, sr.series_id, COALESCE(sr.corrected_ms, sr.total_ms) AS ms,
            sr.ncm_driver_id, sr.road_wetness, sr.light
        FROM session_result sr JOIN session s ON s.session_id = sr.session_id JOIN event e ON e.event_id = s.event_id
        WHERE e.server_id = ? AND sr.state = 'finished' AND sr.conditions_source IS NOT NULL AND s.kind = 'race'
          AND s.completed_at > ? LIMIT 5000]], { sid, t - 60 * 86400 }) or {}
    for _, r in ipairs(races) do add(r.route_id, r.series_id, r.ms, r.ncm_driver_id, r.road_wetness, r.light) end
    local practice = MySQL.query.await([[SELECT route_id, series_id, run_ms AS ms, ncm_driver_id, road_wetness, light
        FROM practice_run WHERE server_id = ? AND conditions_source IS NOT NULL AND at > ? LIMIT 5000]],
        { sid, t - 60 * 86400 }) or {}
    for _, r in ipairs(practice) do add(r.route_id, r.series_id, r.ms, r.ncm_driver_id, r.road_wetness, r.light) end
    local st, buckets, qualified = {}, {}, 0
    local minN, minD = PaddockSettings.get("calibMinN", 8), PaddockSettings.get("calibMinDrivers", 3)
    for k, list in pairs(samples) do
        local s = Cal.summarise(list)
        buckets[k] = s
        if Cal.qualifies(s, minN, minD) then qualified = qualified + 1 end
        local routeId, tier, bucket = k:match("^(.-)|(%a+)|(.+)$")
        st[#st + 1] = { query = [[INSERT INTO paddock_calibration (server_id, route_id, tier, cond_bucket, n, drivers, median_ms,
            p25_ms, computed_at) VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, -1), NULLIF(?, -1), ?) ON DUPLICATE KEY UPDATE n = VALUES(n),
            drivers = VALUES(drivers), median_ms = VALUES(median_ms), p25_ms = VALUES(p25_ms), computed_at = VALUES(computed_at)]],
            -- A bucket without samples has no median yet: -1 travels, NULLIF restores the NULL (a nil is a hole).
            values = { sid, routeId, tier, bucket, s.n, s.drivers, s.median and math.floor(s.median) or -1,
                s.p25 and math.floor(s.p25) or -1, t } }
        y()
    end
    if #st > 0 then U.transact(st) end
    PaddockCalibration.buckets = buckets
    PaddockCalibration.computedAt = t
    pcall(PaddockCalibration.humanPaddock, t)
    local total = 0
    for _ in pairs(buckets) do total = total + 1 end
    log("recomputed: %d human samples in %d buckets, %d past the minimums (n>=%d, drivers>=%d); the rest run on the declared baseline",
        #races + #practice, total, qualified, minN, minD)
end

--- L305: humans in PADDOCK races (where the owner actually races), per tier, normalised to a stat-50 driver in a stat-50
--- car (`paddock.calibration.normaliseMs`): the human's machine -- fitted parts and all -- is backed out, so the field's
--- pace comes from each NPC's own attributes and car against what the human brings. Street routes only (the baked road
--- line is the distance); one driver is enough (owner, 2026-10-04: "yes, my laps now"). The median speed of the last
--- `calibHumanDays` replaces the physical-pace estimate for that tier once it has `calibrationMinHumanSamples` laps.
PaddockCalibration.humanLearned = {}
function PaddockCalibration.humanPaddock(t)
    if not PaddockSettings.get("calibrationHumanPaddock", true) then PaddockCalibration.humanLearned = {} return end
    local G = NcmCore.get("economy.npc_garage")
    local Car = NcmCore.get("paddock.car")
    local rows = MySQL.query.await([[SELECT x.finish_ms, r.route_id, r.tier, e.asset_id, e.ncm_driver_id
        FROM paddock_result x JOIN paddock_race r ON r.server_id = x.server_id AND r.race_id = x.race_id
        JOIN paddock_entry e ON e.server_id = x.server_id AND e.race_id = x.race_id AND e.person_key = x.person_id
        WHERE x.server_id = ? AND x.person_id LIKE 'h%' AND x.state = 'finished' AND x.finish_ms > 0 AND r.window_opens_at > ?
        ORDER BY r.window_opens_at DESC LIMIT 400]], { U.sid(), t - PaddockSettings.get("calibHumanDays", 30) * 86400 }) or {}
    local byTier, used, perfs = {}, 0, {}
    for i, r in ipairs(rows) do
        local route = PaddockWorld.route(r.route_id)
        local okP, path = pcall(PaddockLive.pathFor, r.route_id)
        local lineM = route and not route.oval and okP and path and path.source == "road" and path.lengthM or nil
        local c = r.asset_id and PaddockCars.load(r.asset_id)
        if lineM and c then
            local perf = perfs[r.asset_id]
            if not perf then perf = Car.performance(G.levels(c.prestige, c.parts, nil)); perfs[r.asset_id] = perf end
            local v = Cal.humanSpeed(lineM, tonumber(r.finish_ms), perf)
            if v and v >= Cal.LEARN_MIN_MPS and v <= Cal.LEARN_MAX_MPS then
                byTier[r.tier] = byTier[r.tier] or {}
                local list = byTier[r.tier]; list[#list + 1] = v
                used = used + 1
            end
        end
        if i % 10 == 0 then Wait(0) end
    end
    local learned, parts = {}, {}
    local minN = PaddockSettings.get("calibrationMinHumanSamples", 3)
    for tier, list in pairs(byTier) do
        local m = Cal.median(list)
        if m and #list >= minN then learned[tier] = math.floor(m * 100 + 0.5) / 100 end
        parts[#parts + 1] = ("%s %d lap(s) median %.1f m/s%s"):format(tier, #list, m or 0, learned[tier] and "" or " (too few)")
    end
    PaddockCalibration.humanLearned = learned
    table.sort(parts)
    log("human Paddock laps: %d of %d usable; %s", used, #rows, #parts > 0 and table.concat(parts, "; ") or "none yet")
end

--- The base seconds and source for a race.
function PaddockCalibration.baseFor(seed, route, tier, cond)
    local human = PaddockCalibration.buckets[key(route.routeId, tier, cond.bucket or "dry:day")]
    if human then human.cond = cond end
    -- L296: a street route is timed over the road line it actually runs (the baked line), at the tier's MEASURED pace
    if not route.oval and PaddockLive and PaddockLive.pathFor then
        local okP, path = pcall(PaddockLive.pathFor, route.routeId)
        if okP and path and path.source == "road" and (path.lengthM or 0) > 0 then
            route = setmetatable({ lineM = path.lengthM }, { __index = route })
        end
    end
    local w = PaddockStore.world
    -- L305: a tier's speed is the humans' when their Paddock laps say so, else the physical NPC field's (L296), else seeds
    local learned = nil
    if w and w.paceLearned then learned = {}; for k, v in pairs(w.paceLearned) do learned[k] = v end end
    for k, v in pairs(PaddockCalibration.humanLearned or {}) do learned = learned or {}; learned[k] = v end
    return Cal.basePace(seed, route, tier, cond, human, PaddockSettings.get("calibMinN", 8), PaddockSettings.get("calibMinDrivers", 3),
        (PaddockSettings.get("paceLearn", true) or next(PaddockCalibration.humanLearned or {}) ~= nil) and learned or nil)
end

--- L296: one race's physical pace, learned into its tier (persisted in paddock_world.counters_json). `metres`/`ms` are
--- the race's pooled physical stretches at racing speed; under `paceLearnMinM` of road says too little.
function PaddockCalibration.learnPhysical(race, metres, ms)
    local w = PaddockStore.world
    if not w or not race or not race.tier or not metres or not ms or ms <= 0 then return end
    local route = PaddockWorld.route(race.routeId)
    if route and route.oval then return end
    if metres < PaddockSettings.get("paceLearnMinM", 2000) then
        log("%s: physical pace %.1f m/s over %.0f m -- too little road to learn from", race.raceId, metres / ms * 1000, metres)
        return
    end
    local sample = metres / ms * 1000
    w.paceLearned = w.paceLearned or {}
    local prev = w.paceLearned[race.tier]
    local nextV, ok = Cal.learn(prev or Cal.TIER_SPEED[race.tier], sample)
    if not ok then
        log("%s: physical pace %.1f m/s over %.0f m refused (outside %d-%d)", race.raceId, sample, metres, Cal.LEARN_MIN_MPS, Cal.LEARN_MAX_MPS)
        return
    end
    w.paceLearned[race.tier] = math.floor(nextV * 100 + 0.5) / 100
    PaddockStore.markMeta()
    log("%s: physical pace %.1f m/s over %.0f m; %s tier speed %.2f -> %.2f m/s", race.raceId, sample, metres, race.tier,
        prev or Cal.TIER_SPEED[race.tier], w.paceLearned[race.tier])
end
