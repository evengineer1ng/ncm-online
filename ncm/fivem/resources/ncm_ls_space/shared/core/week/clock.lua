-- ncm-core module: week.clock
-- Which Racing Week reconstruction and which Day it is (doc 45 §A, rung 0; L300, L301).
--
-- DERIVED, NEVER STORED. The run and the Day are a pure function of (epoch, now), as `world.clock`'s dayIndex is, so
-- a restart, a crash or a quiet server can never leave "what day is it" wrong. What HAPPENED in a run is the
-- database's business; what day it IS is arithmetic.
--
-- Real time (the default): a Day starts at `boundarySod` Eastern -- NOON (W-2, L303: a 72-hour run always ends at the
-- same time of day, so it ends where players are awake to see the countdown and the rewind). Day 1 of run 1 is the
-- boundary-to-boundary day containing `epochUtc`. `M.at` / `M.runBounds` are the HISTORICAL calendar: three Days a run,
-- tiled from the epoch -- what history does when nothing changes it.
-- Compressed time (dev only): `daySeconds` < 86400 ignores the calendar and counts flat periods from the epoch, so a
-- whole reconstruction can be lived in an evening.
--
-- THE TIMELINE (doc 47, L309-L310). Racing Week was advertised as seven days; history pulls it to collapse at 72 hours
-- but a run can survive to Day 7. A run's END is therefore not arithmetic: it is decided at each possible end (noon of
-- Day 3 .. Day 7) by `week.continuation` and recorded (`racing_week_run.end_utc`). What day it IS stays arithmetic --
-- over the recorded ends: `M.locate(cfg, runs, utc)` walks run 1 from the epoch, each next run opening at the last
-- one's end. An open run has a PROVISIONAL end, the next possible end it has not yet survived; instants at or past it
-- are `beyond` (undecided: the Paddock posts nothing there until the verdict is in).
local Core = NcmCore

Core.define("week.clock", function(C)
    local M = { version = "0.3.0", DAYS = 3, MAX_DAYS = 7, DAY = 86400, BOUNDARY_SOD = 12 * 3600,
        DEFAULT_EPOCH = 1791043200 }        -- 2026-10-03 16:00 UTC = 12:00 ET: Day 1 of run 1 on dev
    local Clock = C.get("world.clock")
    local floor = math.floor

    -- Eastern day number with the day starting at `boundarySod` rather than midnight.
    local function shiftedDay(utc, boundarySod)
        local e = Clock.eastern(utc)
        return floor((e.localUnix - boundarySod) / M.DAY)
    end

    --- { runIndex >= 1, day 1..3, dayNumber >= 0, secondsIntoDay } or nil when `now` is before the epoch.
    --- Also { hours 0..72, phase 0..1, secondsRemaining }.
    --- opts: { daySeconds = 86400, boundarySod = 21600, hours = <pinned run hour, dev> }.
    function M.at(epochUtc, nowUtc, opts)
        opts = opts or {}
        epochUtc, nowUtc = floor(tonumber(epochUtc) or 0), floor(tonumber(nowUtc) or 0)
        local daySeconds = floor(tonumber(opts.daySeconds) or M.DAY)
        local boundary = floor(tonumber(opts.boundarySod) or M.BOUNDARY_SOD)
        local dayNumber, into
        if daySeconds > 0 and daySeconds < M.DAY then
            if nowUtc < epochUtc then return nil end
            dayNumber = floor((nowUtc - epochUtc) / daySeconds)
            into = (nowUtc - epochUtc) - dayNumber * daySeconds
        else
            daySeconds = M.DAY
            local first, today = shiftedDay(epochUtc, boundary), shiftedDay(nowUtc, boundary)
            if today < first then return nil end
            dayNumber = today - first
            local e = Clock.eastern(nowUtc)
            into = (e.localUnix - boundary) - floor((e.localUnix - boundary) / M.DAY) * M.DAY
        end
        local out = { runIndex = floor(dayNumber / M.DAYS) + 1, day = dayNumber % M.DAYS + 1, dayNumber = dayNumber,
            secondsIntoDay = into, daySeconds = daySeconds }
        -- Run hours (0..72) on the curve's own scale, whatever the day length: a compressed dev day is still 24 hours.
        out.hours = (out.day - 1) * 24 + into / daySeconds * 24
        -- A pinned hour (dev): the run, the clock's Day and its boundary are unchanged; the curve reads this hour.
        local ph = tonumber(opts.hours)
        if ph and ph >= 0 then
            out.hours, out.overridden = math.min(ph, M.DAYS * 24), true
            out.day = math.min(M.DAYS, floor(out.hours / 24) + 1)
        end
        out.phase = out.hours / (M.DAYS * 24)
        out.secondsRemaining = floor((M.DAYS * 24 - out.hours) / 24 * daySeconds + 0.5)
        return out
    end

    --- The one Racing Week config, read through a host getter (`GetConvar`): every resource derives the same run.
    --- Convars: ncm_week_epoch, ncm_week_day_seconds, ncm_week_boundary_hour (Eastern, default 12).
    function M.config(get)
        local function g(k, d) local ok, v = pcall(get, k, d); return ok and v or d end
        return {
            epoch = tonumber(g("ncm_week_epoch", tostring(M.DEFAULT_EPOCH))) or M.DEFAULT_EPOCH,
            daySeconds = tonumber(g("ncm_week_day_seconds", "86400")) or M.DAY,
            boundarySod = (tonumber(g("ncm_week_boundary_hour", "12")) or 12) * 3600,
        }
    end

    --- [startUtc, endUtc) of run `runIndex` (1-based) under `cfg`.
    function M.runBounds(cfg, runIndex)
        local n = floor(tonumber(runIndex) or 1) - 1
        local daySeconds = floor(cfg.daySeconds or M.DAY)
        if daySeconds > 0 and daySeconds < M.DAY then
            local s = floor(cfg.epoch) + n * M.DAYS * daySeconds
            return s, s + M.DAYS * daySeconds
        end
        local boundary = floor(cfg.boundarySod or M.BOUNDARY_SOD)
        local first = shiftedDay(floor(cfg.epoch), boundary)
        return Clock.utcAt(first + n * M.DAYS, boundary), Clock.utcAt(first + (n + 1) * M.DAYS, boundary)
    end

    --- `M.at` under a config.
    function M.now(cfg, nowUtc, pinnedHours)
        return M.at(cfg.epoch, nowUtc, { daySeconds = cfg.daySeconds, boundarySod = cfg.boundarySod, hours = pinnedHours })
    end

    -- ------------------------------------------------------------------------------------------ the timeline

    local function compressed(cfg)
        local d = floor(tonumber(cfg.daySeconds) or M.DAY)
        return d > 0 and d < M.DAY, d
    end

    --- The instant `k` Days after a run that opened at `startUtc` (a noon boundary, or a compressed period).
    function M.boundary(cfg, startUtc, k)
        local comp, d = compressed(cfg)
        if comp then return floor(startUtc) + floor(k) * d end
        local boundary = floor(cfg.boundarySod or M.BOUNDARY_SOD)
        return Clock.utcAt(shiftedDay(floor(startUtc), boundary) + floor(k), boundary)
    end

    --- The run an instant belongs to, over the recorded ends. `runs` = { [runIndex] = { endUtc?, endKind?, survived? } }
    --- (survived = the highest Day boundary, 3..6, the run has already lived through). Returns
    --- { run, startUtc, endUtc (recorded, or nil while open), provisionalEnd, open, beyond, survived, endKind } or nil
    --- before the epoch. An open run never outlives Day 7: past it, the run is read as ended there (unjudged) and the
    --- next one opens -- the host records the verdict; this function never invents one.
    function M.locate(cfg, runs, utc)
        utc = floor(tonumber(utc) or 0)
        runs = runs or {}
        local start = M.runBounds(cfg, 1)
        if utc < start then return nil end
        local n = 1
        while n < 100000 do
            local rec = runs[n] or {}
            local endUtc = tonumber(rec.endUtc)
            local survived = math.max(M.DAYS - 1, math.min(M.MAX_DAYS - 1, floor(tonumber(rec.survived) or 0)))
            if endUtc then
                if utc < endUtc then
                    return { run = n, startUtc = start, endUtc = endUtc, provisionalEnd = endUtc, open = false, beyond = false,
                        survived = survived, endKind = rec.endKind }
                end
                start = endUtc
            else
                local hardEnd = M.boundary(cfg, start, M.MAX_DAYS)
                if utc < hardEnd then
                    local prov = M.boundary(cfg, start, survived + 1)
                    return { run = n, startUtc = start, endUtc = nil, provisionalEnd = prov, open = true, beyond = utc >= prov,
                        survived = survived }
                end
                start = hardEnd
            end
            n = n + 1
        end
        return nil
    end

    --- Clock fields for an instant inside a located run: { runIndex, day 1..7, hours 0..168, secondsIntoDay, daySeconds,
    --- phase (hours / 72: the historical arc), secondsRemaining (to the provisional or recorded end), possibleEnd
    --- (Day boundary k of that end), open, beyond }. A pinned hour (dev) overrides hours/day only.
    function M.inRun(cfg, rec, nowUtc, pinnedHours)
        if not rec then return nil end
        local comp, d = compressed(cfg)
        local daySeconds = comp and d or M.DAY
        local k, dayStart = 0, rec.startUtc
        while k < M.MAX_DAYS - 1 and M.boundary(cfg, rec.startUtc, k + 1) <= nowUtc do k = k + 1 end
        dayStart = M.boundary(cfg, rec.startUtc, k)
        local dayLen = M.boundary(cfg, rec.startUtc, k + 1) - dayStart
        local into = math.max(0, nowUtc - dayStart)
        local out = { runIndex = rec.run, day = k + 1, dayNumber = k, secondsIntoDay = into, daySeconds = daySeconds,
            open = rec.open, beyond = rec.beyond, survived = rec.survived }
        out.hours = k * 24 + math.min(24, into / math.max(1, dayLen) * 24)
        local ph = tonumber(pinnedHours)
        if ph and ph >= 0 then
            out.hours, out.overridden = math.min(ph, M.MAX_DAYS * 24), true
            out.day = math.min(M.MAX_DAYS, floor(out.hours / 24) + 1)
        end
        local endUtc = rec.endUtc or rec.provisionalEnd
        out.endUtc = endUtc
        out.secondsRemaining = math.max(0, floor(endUtc - nowUtc))
        out.possibleEnd = floor((endUtc - rec.startUtc) / math.max(1, daySeconds) + 0.5)
        out.phase = out.hours / (M.DAYS * 24)
        return out
    end

    --- `M.locate` + `M.inRun`.
    function M.nowIn(cfg, runs, nowUtc, pinnedHours)
        return M.inRun(cfg, M.locate(cfg, runs, nowUtc), floor(tonumber(nowUtc) or 0), pinnedHours)
    end

    return M
end)
