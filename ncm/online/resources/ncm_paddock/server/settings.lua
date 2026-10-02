-- ncm_paddock / server / settings -- the ONE tunables declaration for this resource.
--
-- `Open77.tunables.declare` is per resource and a second call REPLACES the first (observed 2026-09-20), so every
-- Paddock tunable lives here and other files read `PaddockSettings.get(key, fallback)` at the point of use.
-- `apply` accepts only `live`, `next_round` and `next_match`; anything else takes the resource down.
-- These are FIRST NUMBERS (doc 44 §5.2): balance data to tune on dev, not locked constants.
PaddockSettings = {}

local ok, settings = pcall(Open77.tunables.declare, {
    -- Must equal ncm_league's and ncm_world's `serverId`: every row is keyed on it (L112). Checked at boot.
    serverId = { value = "ncm-dev", type = "string", apply = "live" },
    paddockEnabled = { value = true, type = "boolean", apply = "live" },
    tickSeconds = { value = 5, type = "integer", min = 2, max = 60, unit = "s", apply = "live" },
    -- L250: races post ~3 h ahead, so a driver can qualify for one hours before it runs
    horizonMinutes = { value = 200, type = "integer", min = 30, max = 1440, unit = "min", apply = "live" },
    -- Billie (doc 44 §9). Lines open this long before a race and close when its window opens.
    billieEnabled = { value = true, type = "boolean", apply = "live" },
    -- L250: the field and grid freeze here -- at T-10, after entries and qualifying close at T-11 (paddock.mixed)
    billieLeadMinutes = { value = 10, type = "integer", min = 5, max = 120, unit = "min", apply = "live" },
    billieMcSims = { value = 400, type = "integer", min = 50, max = 2000, apply = "live" },
    billieSimsPerYield = { value = 2, type = "integer", min = 1, max = 50, apply = "live" },
    billieOverround = { value = 0.10, type = "number", min = 0.02, max = 0.30, apply = "live" },
    billieSlipCap = { value = 250, type = "integer", min = 10, max = 100000, apply = "live" },
    billieDailyCap = { value = 2000, type = "integer", min = 10, max = 1000000, apply = "live" },
    billieMaxPayout = { value = 10000, type = "integer", min = 100, max = 10000000, apply = "live" },
    -- Calibration (doc 44 §7): a bucket replaces the declared baseline only past these minimums.
    calibMinN = { value = 8, type = "integer", min = 1, max = 1000, apply = "live" },
    calibMinDrivers = { value = 3, type = "integer", min = 1, max = 100, apply = "live" },
    -- Manager mode (doc 44 §10).
    managerFoundFee = { value = 5000, type = "integer", min = 0, max = 10000000, apply = "live" },
    managerFoundGrant = { value = 15000, type = "integer", min = 0, max = 10000000, apply = "live" },
    managerWithdrawWeeklyCap = { value = 2000, type = "integer", min = 0, max = 10000000, apply = "live" },
    managerWithdrawTax = { value = 0.30, type = "number", min = 0, max = 0.95, apply = "live" },
    -- Messages (L226): at most this many unsolicited Paddock messages per player per Eastern day.
    pushPerDay = { value = 3, type = "integer", min = 0, max = 20, apply = "live" },
    -- WIRE shows stories at or above this prominence; everything is still in RESULTS.
    wireMinProminence = { value = 30, type = "integer", min = 0, max = 100, apply = "live" },
    -- Retention (doc 44 §14.1).
    pruneDetailDays = { value = 14, type = "integer", min = 1, max = 365, apply = "live" },
    pruneEventDays = { value = 30, type = "integer", min = 1, max = 365, apply = "live" },
    pruneNewsDays = { value = 90, type = "integer", min = 7, max = 3650, apply = "live" },
    -- Phase 4 (doc 44 §11): Paddock people at their rented garages. Bodies exist only while a player is near a
    -- garage whose tenant is on shift, and never more than the global cap.
    garagesEnabled = { value = true, type = "boolean", apply = "live" },
    garageNearM = { value = 120, type = "integer", min = 30, max = 500, unit = "m", apply = "live" },
    garageLeaveM = { value = 200, type = "integer", min = 50, max = 800, unit = "m", apply = "live" },
    garageBodyCap = { value = 18, type = "integer", min = 0, max = 60, apply = "live" },
    garageTickSeconds = { value = 6, type = "integer", min = 2, max = 60, unit = "s", apply = "live" },
    talkRadiusM = { value = 6, type = "integer", min = 2, max = 20, unit = "m", apply = "live" },
    -- Phase 5 (doc 44 §12, L228): scheduled races run on the street by themselves -- nobody declares them.
    -- `liveMode` = watched (a player is near the route), always (anyone online), or off. `liveBackend` = auto (the
    -- NCM Pace plugin when the nearest player has it, else the platform), platform, or pace.
    liveEnabled = { value = true, type = "boolean", apply = "live" },
    liveMode = { value = "watched", type = "string", apply = "live" },
    liveBackend = { value = "auto", type = "string", apply = "live" },
    liveWatchRadiusM = { value = 600, type = "integer", min = 50, max = 5000, unit = "m", apply = "live" },    liveMaxConcurrent = { value = 2, type = "integer", min = 1, max = 6, apply = "live" },
    liveMaxCars = { value = 16, type = "integer", min = 2, max = 24, apply = "live" },
    liveStageLeadSec = { value = 55, type = "integer", min = 30, max = 600, unit = "s", apply = "live" },
    liveCountdownSec = { value = 5, type = "integer", min = 3, max = 30, unit = "s", apply = "live" },
    liveStartGapMs = { value = 900, type = "integer", min = 0, max = 5000, unit = "ms", apply = "live" },
    liveSampleMs = { value = 250, type = "integer", min = 100, max = 2000, unit = "ms", apply = "live" },
    -- Perseverance: re-send a stuck car, then put it back on the road, and retire it only after a long time.
    liveRecoverSec = { value = 8, type = "integer", min = 3, max = 120, unit = "s", apply = "live" },
    liveResetSec = { value = 20, type = "integer", min = 5, max = 300, unit = "s", apply = "live" },
    liveRetireSec = { value = 180, type = "integer", min = 30, max = 1800, unit = "s", apply = "live" },
    -- The finish: after the winner, everyone still running gets this long (or half the winner's time, if longer).
    liveFinishGraceSec = { value = 90, type = "integer", min = 15, max = 900, unit = "s", apply = "live" },
    liveTimeoutFactor = { value = 4, type = "number", min = 1.2, max = 10, apply = "live" },
    liveMinFinishShare = { value = 0.5, type = "number", min = 0.1, max = 1, apply = "live" },
    livePaceMaxMps = { value = 90, type = "number", min = 20, max = 150, unit = "m/s", apply = "live" },
    -- Extra headroom above the sim-derived (already faster) oval baseline. Pace's minimum command also scales
    -- from this ceiling via launch.minFrac; the configured cap remains livePaceMaxMps.
    liveOvalSpeedCeilingFactor = { value = 2.25, type = "number", min = 1, max = 2.5, apply = "live" },
    liveNpcDrivers = { value = true, type = "boolean", apply = "live" },
    -- L234: a visible driver in every Pace car too (SP seats one). attachDriver with the NPC and no task; the Pace
    -- plugin issues the drive commands. Off = the 0.2.0 driverless cars with authority requested for the host.
    livePaceDrivers = { value = true, type = "boolean", apply = "live" },
    -- L234: the native traffic null area (NCM Pace 0.3.0) over a start, radius = the route's SP trafficClearRadiusM;
    -- raised with the warning, held until this long after the lights.
    -- L235: names over Paddock cars and the tower's rows, to players within broadcastRadiusM of a physical car.
    broadcastEnabled = { value = true, type = "boolean", apply = "live" },
    broadcastRadiusM = { value = 600, type = "integer", min = 100, max = 2000, unit = "m", apply = "live" },
    liveTrafficClear = { value = true, type = "boolean", apply = "live" },
    liveTrafficClearTailSec = { value = 60, type = "integer", min = 0, max = 600, unit = "s", apply = "live" },
    -- L236: an oval races the whole ring, so its null area and warning are centred on the roundabout: this far past
    -- the ring on every side.
    -- KB-223 (owner, 09-30 07:05): ovals came off the schedule until they could be trusted. Back on (owner, 2026-10-01:
    -- "i want the pace.dll with ovals installed, and ovals back on the calendar") with Pace 0.8.2's closed oval splines
    -- (L248); a player with an older Pace brings no oval car in, and the race runs on the model.
    ovalsScheduled = { value = true, type = "boolean", apply = "live" },
    liveOvalClearMarginM = { value = 80, type = "integer", min = 0, max = 400, unit = "m", apply = "live" },
    -- KB-223 experiment: `ring` (the whole roundabout), `start` (the start line, as point to point), or `off`. The
    -- second live oval, with the ring cleared, never moved; the null area may also take the lanes the planner drives.
    liveOvalClearMode = { value = "ring", type = "string", apply = "live" },
    -- KB-223, 05:08: a Pace bubble car's speed CEILING is its sim pace times this (the planner brakes for corners).
    bubblePaceSpeedFactor = { value = 1.5, type = "number", min = 1, max = 3, apply = "live" },
    -- ...and an oval's grid comes up this long before the lights for a player near its start, held until they go.
    bubbleGridLeadSec = { value = 30, type = "integer", min = 0, max = 120, unit = "s", apply = "live" },
    -- KB-238: how long a bubble car stands in its Pace player's game before its driver is seated. 0: at once (owner,
    -- 2026-10-01: an empty car is "a downgrade for drivers in cars"; the fix is keeping cars well inside streaming,
    -- bubbleInM/OutM). 3000 clears the engine's spawn physics cycle if crashes persist. Never reported = gone after
    -- bubbleSeatTimeoutMs.
    bubbleSeatDelayMs = { value = 0, type = "integer", min = 0, max = 15000, unit = "ms", apply = "live" },
    bubbleSeatTimeoutMs = { value = 20000, type = "integer", min = 5000, max = 120000, unit = "ms", apply = "live" },
    -- The race-start warning (L233): a native HUD banner (NCM Pace) for players this near a start line, this long out.
    liveWarnLeadSec = { value = 150, type = "integer", min = 30, max = 900, unit = "s", apply = "live" },
    liveWarnRadiusM = { value = 200, type = "integer", min = 30, max = 1000, unit = "m", apply = "live" },
    liveSlotClearM = { value = 6, type = "integer", min = 2, max = 30, unit = "m", apply = "live" },
    -- The physical bubble (L229): model cars within bubbleInM of a player become physical; beyond bubbleOutM of every
    -- player they hand back to the model. First numbers: a client picks AI up somewhere between 186 m and 573 m.
    -- Night City on Eastern real time (clock.lua, KB-217). Needs NCM Clock on EVERY client (the engine at 1x); a client
    -- without it runs 8x and is jumped back about every 15 s. `off` leaves the OPEN//77 default day alone.
    clockMode = { value = "eastern", type = "string", apply = "live" },
    clockSyncSeconds = { value = 600, type = "integer", min = 30, max = 3600, unit = "s", apply = "live" },
    clockToleranceSec = { value = 120, type = "integer", min = 10, max = 3600, unit = "s", apply = "live" },
    bubbleEnabled = { value = true, type = "boolean", apply = "live" },
    -- L249 step 4 (IDEA-730): Paddock teams and independents buy real parts and cars with real money. Players keep
    -- first claim: nothing listed less than npcExclusivitySec ago, and at most npcPartsPerMarketHour sales a market.
    npcMarketsEnabled = { value = true, type = "boolean", apply = "live" },
    npcExclusivitySec = { value = 1200, type = "integer", min = 0, max = 86400, unit = "s", apply = "live" },
    npcPartsPerMarketHour = { value = 2, type = "integer", min = 0, max = 50, apply = "live" },
    npcShopEverySec = { value = 300, type = "integer", min = 30, max = 7200, unit = "s", apply = "live" },
    npcShoppersPerPass = { value = 4, type = "integer", min = 0, max = 50, apply = "live" },
    npcShopMinCash = { value = 800, type = "integer", min = 0, max = 1000000, apply = "live" },
    npcVehicleMinCash = { value = 9000, type = "integer", min = 0, max = 10000000, apply = "live" },
    -- L249 step 5: NPC traders on the posted Exchange (they post surplus and wants, take good bids, bid on players' posts)
    npcExchangeEnabled = { value = true, type = "boolean", apply = "live" },
    npcExchangeEverySec = { value = 180, type = "integer", min = 30, max = 7200, unit = "s", apply = "live" },
    npcExchangeActionsPerPass = { value = 6, type = "integer", min = 0, max = 50, apply = "live" },
    -- Owner, 2026-10-01 evening: 100/150 m was a diagnostic and not the cause (KB-238 was Paddock's vehicle/driver
    -- lifecycle and the native attachment path, fixed in another session) -- "restore larger distances of streaming".
    bubbleInM = { value = 250, type = "integer", min = 50, max = 800, unit = "m", apply = "live" },
    bubbleOutM = { value = 300, type = "integer", min = 80, max = 1200, unit = "m", apply = "live" },
    bubbleSpawnsPerPass = { value = 3, type = "integer", min = 1, max = 16, apply = "live" },
    bubbleTickMs = { value = 500, type = "integer", min = 200, max = 5000, unit = "ms", apply = "live" },
})
if not ok then print("[ncm_paddock/settings] tunables.declare FAILED: " .. tostring(settings)) settings = nil end
PaddockSettings.proxy = settings

function PaddockSettings.get(key, fallback)
    if not settings then return fallback end
    local ok2, v = pcall(function() return settings[key] end)
    if ok2 and v ~= nil then return v end
    return fallback
end
