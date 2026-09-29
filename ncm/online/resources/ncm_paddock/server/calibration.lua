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
    local total = 0
    for _ in pairs(buckets) do total = total + 1 end
    log("recomputed: %d human samples in %d buckets, %d past the minimums (n>=%d, drivers>=%d); the rest run on the declared baseline",
        #races + #practice, total, qualified, minN, minD)
end

--- The base seconds and source for a race.
function PaddockCalibration.baseFor(seed, route, tier, cond)
    local human = PaddockCalibration.buckets[key(route.routeId, tier, cond.bucket or "dry:day")]
    if human then human.cond = cond end
    return Cal.basePace(seed, route, tier, cond, human, PaddockSettings.get("calibMinN", 8), PaddockSettings.get("calibMinDrivers", 3))
end
