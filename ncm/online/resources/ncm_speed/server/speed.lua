-- ncm_speed / server / speed -- Racing Week's advertised speed limits (owner, 2026-10-03, L301, L302; doc 45 §M-§N).
--
-- ITS OWN RESOURCE (KB-327). This lived in ncm_world until its lane index pushed that VM over the 64 MB Lua quota and
-- the platform stopped it mid-drive, removing the owner's car. Now ncm_world's odometer only sends facts
-- (`ncm:speed:sample`: player, driver, position, speed, heading, time) and the index (compact, ~4 MB) lives here.
-- No `os`, no `collectgarbage` in the server sandbox (KB-322, KB-327): memory cannot be measured from inside.
--
-- THE SIGN. The game's own posted lane speed under the car (`world.speed_limits` over `lane_limits_data.lua`) x the
-- organisers' current factor (`GlobalState.ncmWeek.limit`, an announced step of `week.curve`), sent to the driver's
-- client as `ncm:limit { kph, over, day, chapter }` when it changes.
--
-- THE COST. Police everywhere: the rolling minute of excess against the city's bar and ceiling (`ncmWeek.perLevel`,
-- `ncmWeek.policeCap`); the server never learns the engine's real heat, so the level is cleared after a clean
-- stretch. In a race, each second's excess goes to ncm_league with the organisers' rule (`ncmWeek.race`).
-- THE CITY HEARS IT: `speeding` facts for the curve (`ncm:week:fact`), one `speeding` per episode for the trajectory.
NcmSpeed = { index = nil, ready = false }

local S = NcmCore.get("world.speed_limits")
local function log(fmt, ...) print(("[ncm_speed] " .. fmt):format(...)) end

local CLEAR_AFTER_S = 45                     -- a clean stretch this long ends a speeding chase we started
local EPISODE_GAP_S = 120                    -- over again after this long is a new conduct episode

local per = {}                               -- pid -> { st, lane, shown, wanted, cleanSince, lastOverAt, episodes, at }
local errors = 0

local function week()
    local ok, v = pcall(function() return GlobalState.ncmWeek end)
    return ok and type(v) == "table" and v or nil
end

local function stateFor(pid)
    local e = per[pid]
    if not e then e = { st = S.newState(), wanted = 0, episodes = 0 }; per[pid] = e end
    return e
end

local function show(pid, e, msg)
    local key = msg and (msg.kph .. ":" .. (msg.over or 0) .. ":" .. tostring(msg.day) .. ":" .. tostring(msg.chapter)) or "off"
    if e.shown == key then return end
    e.shown = key
    pcall(TriggerClientEvent, "ncm:limit", pid, msg or false)
end

local function setWanted(pid, e, level, why)
    if level == e.wanted then return end
    local ok, res, reason = pcall(Open77.players.setWanted, pid, level)
    log("wanted player=%d %d -> %d (%s): %s", pid, e.wanted, level, why,
        ok and res and ("level=" .. tostring(res.level)) or ("REFUSED " .. tostring(ok and reason or res)))
    if ok and res then e.wanted = level end
end

local function sample(pid, driverId, x, y, z, speedMps, heading, t)
    if not NcmSpeed.ready then return end
    pid, t = tonumber(pid), tonumber(t)
    if not pid or pid <= 0 or not t then return end
    local wk = week()
    if not wk or not wk.limit then return end          -- no Racing Week published yet: no sign
    local e = stateFor(pid)
    local lane, posted = S.nearest(NcmSpeed.index, x, y, z, (heading and heading > -999) and heading or nil, e.lane)
    e.lane = lane
    local dt = e.at and (t - e.at) or 1
    e.at = t
    if not posted then
        S.account(e.st, speedMps or 0, nil, dt, t)
        show(pid, e, false)
    else
        local adv, kph = S.advertised(posted, wk.limit)
        local overKph = S.account(e.st, speedMps or 0, adv, dt, t)
        show(pid, e, { kph = kph, over = overKph > 0 and math.floor(overKph + 0.5) or 0, day = wk.day, chapter = wk.chapter })
        local last = e.st.samples[#e.st.samples]
        local excess = last and last.e or 0
        if excess > 0 then
            TriggerEvent("ncm:week:fact", "speeding", excess / 1000)
            local id = (type(driverId) == "string" and driverId ~= "") and driverId or nil
            if not e.lastOverAt or t - e.lastOverAt > EPISODE_GAP_S then
                e.episodes = e.episodes + 1
                if id then TriggerEvent("ncm:life:record", id, { id = ("speed:%d:%d"):format(tonumber(wk.run) or 0, math.floor(t)), kind = "speeding" }) end
                log("OVER player=%d driver=%s %d km/h on a %d sign (posted %d m/s x%.2f, %s, hour %.1f, episode %d)", pid,
                    tostring(id), math.floor((speedMps or 0) * 3.6), kph, math.floor(posted), wk.limit, tostring(wk.step),
                    tonumber(wk.hours) or -1, e.episodes)
            end
            e.lastOverAt = t
            if id then TriggerEvent("ncm:speed:excess", id, pid, excess, wk.race or "police", t) end
        end
    end
    local cap, bar = tonumber(wk.policeCap) or 5, tonumber(wk.perLevel) or S.POLICY.perLevel
    local level = S.wanted(e.st.excess60, cap, bar)
    if level > e.wanted then
        setWanted(pid, e, level, ("excess %.0f m*s in 60 s, bar %.0f, cap %d, hour %.1f"):format(e.st.excess60, bar, cap, tonumber(wk.hours) or -1))
        e.cleanSince = nil
    elseif e.wanted > 0 and e.st.excess60 == 0 then
        e.cleanSince = e.cleanSince or t
        if t - e.cleanSince >= CLEAR_AFTER_S then setWanted(pid, e, 0, "clean " .. CLEAR_AFTER_S .. " s") end
    end
end

AddEventHandler("ncm:speed:sample", function(...)
    local ok, err = pcall(sample, ...)
    if not ok then
        errors = errors + 1
        if errors <= 5 or errors % 100 == 0 then log("sample error #%d: %s", errors, tostring(err)) end
    end
end)

AddEventHandler("onPlayerDisconnected", function(pid) per[tonumber(pid) or -1] = nil end)

CreateThread(function()
    Wait(3000)
    local t0 = Open77.time.monotonic()          -- no `os` in the server sandbox (KB-322)
    local n = 0
    NcmSpeed.index = S.build(NcmLaneLimitsData, function() n = n + 1; Wait(0) end)
    NcmLaneLimitsData = nil                  -- the compact index is all that is kept (~4 MB measured offline)
    NcmSpeed.ready = true
    log("lane index ready: %d lanes, %d points, %d yields, %.1f s", NcmSpeed.index.count,
        NcmSpeed.index.points, n, Open77.time.monotonic() - t0)
end)

RegisterCommand("ncm.limit", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    for pid, e in pairs(per) do
        log("player=%d lane=%s shown=%s excess60=%.0f wanted=%d episodes=%d maxOver=%.0f", pid, tostring(e.lane),
            tostring(e.shown), e.st.excess60, e.wanted, e.episodes, e.st.maxOverKph)
    end
    if not next(per) then log("no driver sampled yet (index %s)", NcmSpeed.ready and "ready" or "building") end
    log("sample errors %d", errors)
end, false)
