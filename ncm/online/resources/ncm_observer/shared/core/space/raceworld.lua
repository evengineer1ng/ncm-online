-- ncm-core module: space.raceworld
--
-- L327: NCM motorsport at the Earth venues, on the one clock. Unobserved races are SIMULATED; observed ones are
-- PHYSICALIZED -- and they are the same race.
--
-- Everything here is a pure function of (venue, slot, drivers, utc). A race at Monza exists and progresses with no host
-- running: at any instant `state()` says who is where, on which lap, how far apart, who retired. A player who arrives on
-- lap 18 is handed lap 18 (the AC side places the field at those track positions); when nobody comes, `result()` is the
-- canonical classification. Physical results flow back in by the caller recording them against the same `eventId`.
--
-- Scheduling: a slot every SLOT_H hours per venue (offset by venue), a race starting SLOT_START_MIN into it. An UNLIT
-- venue only holds races whose start falls in local solar daylight; `lit` venues may race at night. Each slot races one
-- of the venue's championship families, rotating.
--
-- L330 (owner, 2026-10-06): the calendar belongs to the RACING WEEK. Every event is seeded by the run's seed (the same
-- seed as Night City's week), so each run posts a different calendar, field and set of incidents, and a reset rewinds
-- them all. Each slot is a POSTED TIMETABLE on the real clock -- practice, qualifying, the grid, the race, then a track
-- day until the next slot -- and a player who drops in meets whichever session the clock says, never a race that
-- conveniently starts on arrival.
local Core = NcmCore

Core.define("space.raceworld", function(C)
    local M = { version = "0.1.0" }
    local Venues = C.get("space.venues")

    M.SLOT_H = 3
    M.SLOT_START_MIN = 45          -- the race starts 45 min into the slot
    M.PRACTICE_MIN = 25            -- 0:00-0:25 practice
    M.QUALI_MIN = 15               -- 0:25-0:40 qualifying, 0:40-0:45 the grid
    M.RACE_TARGET_S = 35 * 60
    M.FIELD_MAX = 14

    -- family -> average lap speed (m/s, for the abstract lap time) and the AC cars its NPCs drive (all installed)
    M.FAMILIES = {
        open_wheel = { speed = 58, cars = { "ks_ferrari_sf70h", "ks_ferrari_sf15t", "ks_ferrari_f138" } },
        gt = { speed = 47, cars = { "ks_audi_r8_lms_2016", "ks_ferrari_488_gt3", "ks_lamborghini_huracan_gt3", "ks_mclaren_650_gt3",
            "ks_mercedes_amg_gt3", "ks_nissan_gtr_gt3", "ks_porsche_911_gt3_r_2016", "bmw_z4_gt3" } },
        touring = { speed = 41, cars = { "bmw_m3_e30_dtm", "ks_alfa_romeo_155_v6", "ks_mercedes_190_evo2", "ks_audi_tt_cup" } },
        endurance = { speed = 52, cars = { "ks_porsche_919_hybrid_2016", "ks_audi_r18_etron_quattro", "ks_toyota_ts040" } },
        road = { speed = 36, cars = { "ks_mazda_mx5_cup", "ks_toyota_gt86", "ks_bmw_m235i_racing" } },
        historic = { speed = 40, cars = { "ks_lotus_25", "ks_ferrari_312_67", "lotus_49" } },
    }

    -- venue -> circuit length (m) of its first layout (from the AC inventory's ui_track.json)
    M.LENGTH = { monza = 5793, monza_1966 = 10000, spa = 7004, nordschleife = 20832, nurburgring_gp = 5148, silverstone = 5901,
        silverstone_1967 = 4710, imola = 4909, mugello = 5245, barcelona = 4655, brands_hatch = 3908, laguna_seca = 3602,
        red_bull_ring = 4326, zandvoort = 4307, vallelunga = 4085, magione = 2507, trento_bondone = 17619 }

    local function hash(s)
        local h = 2166136261
        for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
        return h
    end
    --- a deterministic number in [0,1) from any key parts
    local function rnd(...)
        local parts = { ... }
        for i = 1, #parts do parts[i] = tostring(parts[i]) end
        local h = hash(table.concat(parts, "|"))
        h = (h * 1103515245 + 12345) % 2147483648
        return h / 2147483648
    end
    M.rnd = rnd

    local function venueOffsetH(v) return hash(v.id) % M.SLOT_H end

    local function slotStart(v, k) return (k * M.SLOT_H + venueOffsetH(v)) * 3600 end
    local function seedTag(seed) return seed and ("%08x"):format(hash(tostring(seed))) or "s0" end

    --- The race of a venue's slot k in a Racing Week run (`seed`): nil when there is none (an unlit venue in the dark).
    function M.event(v, k, seed)
        local start = slotStart(v, k) + M.SLOT_START_MIN * 60
        local day = Venues.daylight(v, start)
        local _, solarEnd = Venues.localHour(v, start + M.RACE_TARGET_S)
        if not v.lit and (not day or solarEnd >= 18.5 or solarEnd < 6.5) then return nil end
        local fam = v.families[(k + (seed and hash(tostring(seed)) or 0)) % #v.families + 1]
        local F = M.FAMILIES[fam] or M.FAMILIES.gt
        local len = M.LENGTH[v.id] or 5000
        local lapS = len / F.speed
        local laps = math.max(2, math.floor(M.RACE_TARGET_S / lapS + 0.5))
        local slot0 = slotStart(v, k)
        return { eventId = ("%s:%s:%d"):format(v.id, seedTag(seed), k), venue = v.id, slot = k, family = fam, startUtc = start,
            practiceUtc = slot0, qualiUtc = slot0 + M.PRACTICE_MIN * 60, gridUtc = slot0 + (M.PRACTICE_MIN + M.QUALI_MIN) * 60,
            raceEndUtc = start + math.floor(laps * lapS * 1.12), slotEndUtc = slot0 + M.SLOT_H * 3600,
            laps = laps, baseLapS = lapS, lengthM = len, layout = v.layouts[1], cars = F.cars, seed = seed }
    end

    M.SESSION_NAMES = { practice = "Practice", qualifying = "Qualifying", grid = "Grid", race = "Race", trackday = "Track day",
        closed = "Closed (dark)" }

    --- Which session of the posted timetable is running at `utc`: { kind, name, startUtc, endUtc, event }.
    --- kind: practice | qualifying | grid | race | trackday | closed (an unlit venue in the dark: nothing scheduled).
    function M.session(v, utc, seed)
        local k = math.floor((utc / 3600 - venueOffsetH(v)) / M.SLOT_H)
        local e = M.event(v, k, seed)
        local s0, s1 = slotStart(v, k), slotStart(v, k + 1)
        local function out(kind, a, b) return { kind = kind, name = M.SESSION_NAMES[kind], startUtc = a, endUtc = b, event = e, slot = k } end
        if not e then return out("closed", s0, s1) end
        if utc < e.qualiUtc then return out("practice", e.practiceUtc, e.qualiUtc) end
        if utc < e.gridUtc then return out("qualifying", e.qualiUtc, e.gridUtc) end
        if utc < e.startUtc then return out("grid", e.gridUtc, e.startUtc) end
        if utc < e.raceEndUtc then return out("race", e.startUtc, e.raceEndUtc) end
        return out("trackday", e.raceEndUtc, e.slotEndUtc)
    end

    --- The posted timetable from `utc`: the running session and the next `n`.
    function M.schedule(v, utc, seed, n)
        local list, t = {}, utc
        for _ = 1, (n or 4) + 1 do
            local s = M.session(v, t, seed)
            list[#list + 1] = { kind = s.kind, name = s.name, startUtc = s.startUtc, endUtc = s.endUtc,
                family = s.event and s.event.family, laps = s.event and s.event.laps, eventId = s.event and s.event.eventId }
            t = s.endUtc + 1
        end
        return list
    end

    --- The event at a venue around `utc`: the one running, else the next one (up to a day ahead).
    function M.current(v, utc, seed)
        local k0 = math.floor((utc / 3600 - venueOffsetH(v)) / M.SLOT_H)
        for k = k0 - 1, k0 + 8 do
            local e = M.event(v, k, seed)
            if e and e.startUtc + e.laps * e.baseLapS * 1.2 > utc then return e end
        end
        return nil
    end

    --- The field: up to FIELD_MAX of `drivers` ({ id, name, pace 0..1, consistency 0..1, aggression 0..1 }), picked
    --- deterministically for this event, each given a car from the family.
    function M.field(e, drivers)
        -- KB-351: one key per driver, not a hash per comparison (744 drivers blew the server's instruction quota)
        local pool, key = {}, {}
        for i, d in ipairs(drivers or {}) do pool[i] = d; key[d] = rnd(e.eventId, d.id) end
        table.sort(pool, function(a, b) return key[a] < key[b] end)
        local out = {}
        for i = 1, math.min(M.FIELD_MAX, #pool) do
            local d = pool[i]
            out[i] = { driver = d, car = e.cars[(hash(e.eventId .. d.id) % #e.cars) + 1], grid = i }
        end
        -- grid by qualifying pace (a little seeded noise)
        table.sort(out, function(a, b)
            return (a.driver.pace or 0.5) + 0.05 * rnd(e.eventId, "q", a.driver.id) > (b.driver.pace or 0.5) + 0.05 * rnd(e.eventId, "q", b.driver.id)
        end)
        for i, x in ipairs(out) do x.grid = i end
        return out
    end

    --- One driver's time for lap n (s): pace sets the mean, consistency the spread, lap 1 slower from the start.
    local function lapTime(e, d, n)
        local base = e.baseLapS * (1.07 - 0.10 * (d.pace or 0.5))
        local spread = 0.012 + 0.03 * (1 - (d.consistency or 0.5))
        local t = base * (1 + spread * (rnd(e.eventId, d.id, n) - 0.5) * 2)
        if n == 1 then t = t * 1.08 end
        return t
    end

    --- Does the driver retire, and on which lap? (aggression and low consistency raise the odds)
    local function retireLap(e, d)
        local p = 0.03 + 0.05 * (d.aggression or 0.5) + 0.04 * (1 - (d.consistency or 0.5))
        if rnd(e.eventId, d.id, "dnf") < p then return 1 + math.floor(rnd(e.eventId, d.id, "dnflap") * (e.laps - 1)) end
        return nil
    end

    --- The race at `utc`: { phase = scheduled|practice|racing|finished, leaderLap, cars = { {driver, car, grid, lap,
    --- progress (0..1 into the current lap), elapsedS, gapS, retired, position} } } sorted by position.
    function M.state(e, field, utc)
        local el = utc - e.startUtc
        local ss = M.session(Venues.get(e.venue), utc, e.seed)
        local phase = (utc < e.practiceUtc) and "scheduled" or (el < 0 and (ss.kind == "practice" and "practice" or ss.kind) or "racing")
        local cars = {}
        for _, x in ipairs(field) do
            local d = x.driver
            local dnf = retireLap(e, d)
            local t, lap, prog, done = 0, 0, 0, false
            local startDelay = (x.grid - 1) * 0.25            -- grid spacing off the line
            local clock = math.max(0, el) - startDelay
            local n = 1
            while n <= e.laps do
                if dnf and n >= dnf then break end
                local lt = lapTime(e, d, n)
                if clock < t + lt then prog = math.max(0, (clock - t) / lt); break end
                t = t + lt
                lap = n
                n = n + 1
            end
            if lap >= e.laps then done, prog = true, 0 end
            local retired = dnf ~= nil and lap + 1 >= dnf and clock >= t
            cars[#cars + 1] = { driver = d, car = x.car, grid = x.grid, lap = lap, progress = el > 0 and prog or 0,
                finishedS = done and t or nil, retired = retired and not done or false, dist = lap + prog }
        end
        local allDone = true
        for _, c in ipairs(cars) do if not (c.finishedS or c.retired) then allDone = false end end
        if el > 0 and allDone then phase = "finished" end
        table.sort(cars, function(a, b)
            if a.retired ~= b.retired then return not a.retired end
            if a.finishedS and b.finishedS then return a.finishedS < b.finishedS end
            if a.dist ~= b.dist then return a.dist > b.dist end
            return a.grid < b.grid
        end)
        local leader = cars[1]
        for i, c in ipairs(cars) do
            c.position = i
            c.gapS = leader and (leader.dist - c.dist) * e.baseLapS or 0
        end
        return { phase = phase, leaderLap = leader and math.min(e.laps, leader.lap + 1) or 0, laps = e.laps, cars = cars, elapsedS = el }
    end

    --- The canonical classification once finished (nil before).
    function M.result(e, field, utc)
        local s = M.state(e, field, utc)
        if s.phase ~= "finished" then return nil end
        local out = {}
        for _, c in ipairs(s.cars) do
            out[#out + 1] = { position = c.position, driverId = c.driver.id, name = c.driver.name, car = c.car,
                timeS = c.finishedS, retired = c.retired, provenance = "simulated" }
        end
        return out
    end

    return M
end)
