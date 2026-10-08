-- ncm_world / server / week -- Racing Week's clock, curve, Moody and verdicts (L301, L302, L309-L310; doc 45 §M-§N,
-- doc 47).
--
-- WHERE WE ARE is derived over recorded run ends (`week.clock.locate`): run 1 opens at the epoch, each next run where
-- the last one ended. A run's end is not arithmetic any more (doc 47): it is decided at each POSSIBLE END -- noon of
-- Day 3 (hour 72) through the scheduled conclusion (hour 168) -- by `week.continuation`, which reads the world state
-- and makes one seeded, recorded draw (`racing_week_verdict`). Most runs end at 72 hours; a few see Day 4; about 1 in
-- 144 unattended runs see Day 7. This resource is the timeline's only writer (`racing_week_run.start_utc/end_utc/
-- end_kind/survived`); ncm_league and ncm_paddock read the same rows and hear `ncm:week:timeline`.
-- HOW IT IS GOING is the curve (`week.curve`): history's carrier plus this run's live signal -- three reservoirs
-- (safety, enforcement, momentum) fed by facts from any resource, human or NPC alike (`ncm:week:fact`) -- stepped once a
-- minute and persisted per run, so a restart resumes it.
-- MOODY (`week.moody`) rolls a D20 every few hours from the run seed: ceremonial, public, announced. Its faces change
-- RULES and INCENTIVES only -- posted limits and police posture here (through `week.curve.read`), purses, calendar
-- density and lures in the Paddock (`GlobalState.ncmWeekFx`, `ncm:week:fx`). It never touches the state the verdict
-- reads (doc 47 §1.2). Every roll is a row (`racing_week_moody`).
--
-- Published: `GlobalState.ncmWeek = { run, day, chapter, hours, step, limit, race, policeCap, endsIn, money, moody,
-- overridden }` -- `moody` is the active faces by name. The city's tolerance, the reservoirs and any probability are
-- NEVER published (doc 47 §1.6): players read the city, not a meter. Read server-side with `NcmWeek.read()`.
--
-- THE ENDING (L309 Q3): a countdown before EVERY possible end. At 12:00 the verdict is drawn: a collapse (or the
-- completed seventh day) plays the rewind; a run that goes on plays NOTHING -- 12:00 becomes 12:01.
--
-- Dev convars: ncm_week_epoch, ncm_week_day_seconds (compress the run), ncm_week_boundary_hour (default 12 ET),
-- ncm_week_hour_override (pin a run hour), ncm_week_verdict (`live` default | `history`: every run ends at hour 72).
-- Console: `ncm.week` (status, with the developer's view) | `hour <0..168>` | `day <1..7>` | `clock` | `fact <kind> <n>`
--          | `moody` (this run's rolls) | `judge` (what the next verdict would be now; nothing recorded) | `rewind`.
-- A pinned hour runs on a SCRATCH state, never persisted: testing Day 5 must not spend the real run's rolls or verdicts.
NcmWeek = {}

local Week = NcmCore.get("week.clock")
local Curve = NcmCore.get("week.curve")
local Moody = NcmCore.get("week.moody")
local Cont = NcmCore.get("week.continuation")
local Catch = NcmCore.get("week.catchup")
local Vibe = NcmCore.get("week.vibe")
local Hash = NcmCore.get("vocabulary.hash")
local Json = NcmCore.get("vocabulary.json")
local function log(fmt, ...) print(("[ncm_world/week] " .. fmt):format(...)) end
local function now() return Open77.time.unix() end
local function conv(k, d) return (GetConvar and GetConvar(k, d)) or d end
local function sid() return (NcmIdentity and NcmIdentity.serverId and NcmIdentity.serverId()) or conv("ncm_server_id", "ncm") end
local function cfg() return Week.config(GetConvar or function(_, d) return d end) end
local function verdictMode() return conv("ncm_week_verdict", "live") end

local STEP_S = 60

local pinned = tonumber(conv("ncm_week_hour_override", ""))
local run = nil                             -- { index, openedAt, startUtc, seed, st, md, scratch }
local runs = {}                             -- runIndex -> { endUtc, endKind, survived } (the timeline)
local runsLoadedAt = 0
local facts = {}                            -- kind -> n since the last step
local lastSampleHour = {}                   -- runIndex -> last integer hour sampled
local lastRead

local function enc(v) local ok, x = pcall(Json.encode, v); return ok and x or "{}" end
local function dec(s) local ok, x = pcall(Json.decode, tostring(s or "")); return ok and x or nil end

-- ---------------------------------------------------------------------------------------------------- the timeline

local function loadRuns(force)
    if not force and now() - runsLoadedAt < 60 then return runs end
    local okQ, rows = pcall(MySQL.query.await, [[SELECT run_index, end_utc, end_kind, survived FROM racing_week_run WHERE server_id = ?]], { sid() })
    if okQ and type(rows) == "table" then
        local out = {}
        for _, r in ipairs(rows) do
            out[tonumber(r.run_index)] = { endUtc = tonumber(r.end_utc), endKind = r.end_kind, survived = tonumber(r.survived) or 2 }
        end
        runs, runsLoadedAt = out, now()
    end
    return runs
end

local function clock(t)
    return Week.nowIn(cfg(), loadRuns(), t, pinned)
end

local function runSeed(index) return Hash.key(sid(), "racing-week", index) end

local function persist(t)
    if not run or run.scratch then return end
    run.st.moody = run.md
    pcall(MySQL.update.await, [[INSERT INTO racing_week_run (server_id, run_index, opened_at, state_json, updated_at, start_utc, seed)
        VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE state_json = VALUES(state_json), updated_at = VALUES(updated_at),
        start_utc = COALESCE(start_utc, VALUES(start_utc)), seed = COALESCE(seed, VALUES(seed))]],
        { sid(), run.index, run.openedAt, enc(run.st), t, run.startUtc, run.seed })
end

local function event(kind, ref, hours, data, t)
    if not run or run.scratch then return end
    pcall(MySQL.update.await, [[INSERT IGNORE INTO racing_week_event (server_id, run_index, kind, ref, hours, data_json, at)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], { sid(), run.index, kind, ref, hours, enc(data), t })
end

local function tellTimeline()
    TriggerEvent("ncm:week:timeline", runs)
end

-- The run this instant belongs to: resumed from the database, or opened. A pinned hour gets a scratch state.
local function ensureRun(c, t)
    local rec = Week.locate(cfg(), runs, t)
    if pinned then
        if not run or not run.scratch or run.pinned ~= pinned then
            run = { index = c.runIndex, openedAt = t, startUtc = rec and rec.startUtc, seed = runSeed(c.runIndex) .. ":scratch",
                st = Curve.newState(c.hours), md = Moody.newState(), scratch = true, pinned = pinned }
            log("pinned hour %.1f: scratch state (nothing persisted)", pinned)
        end
        return
    end
    if run and not run.scratch and run.index == c.runIndex then return end
    local row = MySQL.single.await("SELECT opened_at, state_json, seed FROM racing_week_run WHERE server_id = ? AND run_index = ?",
        { sid(), c.runIndex })
    local st = row and dec(row.state_json)
    if type(st) == "table" and type(st.fired) == "table" then
        local md = type(st.moody) == "table" and st.moody or nil
        if not md then
            -- a run from before Moody (L310): its dice start now -- no retroactive rolls for hours already lived
            md = Moody.newState()
            md.nextRollH = math.max(Moody.FIRST_ROLL_H, math.ceil(c.hours))
            log("RUN %d predates Moody: first roll at hour %.0f", c.runIndex, md.nextRollH)
        end
        st.moody = nil
        run = { index = c.runIndex, openedAt = tonumber(row.opened_at) or t, startUtc = rec and rec.startUtc,
            seed = row.seed or runSeed(c.runIndex), st = st, md = md }
        log("RUN %d resumed at hour %.2f (day %d): deviation %.3f, step %s, %d Moody roll(s)", c.runIndex, c.hours, c.day,
            st.deviation or 0, tostring(st.step), md.n or 0)
    else
        run = { index = c.runIndex, openedAt = t, startUtc = rec and rec.startUtc, seed = runSeed(c.runIndex),
            st = Curve.newState(c.hours), md = Moody.newState() }
        log("RUN %d opened at hour %.2f (starts %s)", c.runIndex, c.hours, tostring(run.startUtc))
        persist(t)
        loadRuns(true)
        tellTimeline()
    end
end

-- ---------------------------------------------------------------------------------------------------- broadcasts

local function players()
    local ok, all = pcall(Open77.players.all)
    local out = {}
    for _, raw in ipairs(ok and all or {}) do local pid = tonumber(raw); if pid and pid > 0 then out[#out + 1] = pid end end
    return out
end

local function broadcast(title, text, ms, kind)
    for _, pid in ipairs(players()) do
        pcall(Open77.chat.send, pid, "[" .. title .. "] " .. text)
        pcall(Open77.notifications.send, pid, { type = kind or "info", title = title, message = text, icon = "NCM", durationMs = ms or 9000 })
    end
end

local function announce(s, c, t)
    log("ANNOUNCE %s at hour %.2f%s: limit x%.2f, race %s -- %s", s.id, c.hours,
        run.st.fired[s.id] and run.st.fired[s.id].early and " (EARLY)" or "", s.limit, s.race, s.pa)
    event("step", s.id, c.hours, { tolerance = run.st.fired[s.id] and run.st.fired[s.id].tolerance, early = run.st.fired[s.id] and run.st.fired[s.id].early }, t)
    broadcast("RACING WEEK", s.pa)
end

-- Moody's roll: ceremonial and public -- the face and what it does, never what it will cause.
local function rolled(rec, t)
    local data = { name = rec.name, kind = rec.kind, line = rec.line, untilH = rec.untilH, target = rec.target, into = rec.into,
        delayH = rec.delayH, extended = rec.extended }
    if not run.scratch then
        pcall(MySQL.update.await, [[INSERT IGNORE INTO racing_week_moody (server_id, run_index, roll_n, d20, face, hours, data_json, at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)]], { sid(), run.index, rec.n, rec.d20, rec.id, rec.hours, enc(data), t })
    end
    log("MOODY roll %d (d20 = %d) at hour %.1f: %s%s%s", rec.n, rec.d20, rec.hours, rec.name,
        rec.target and (" -> " .. rec.target .. (rec.into and (" becomes " .. rec.into) or "")) or "",
        run.scratch and " [scratch]" or "")
    if not run.scratch and not rec.quiet then broadcast("MOODY", rec.name .. " -- " .. rec.line, 11000) end
end

local lastPublished, lastFxKey
local function publish(c, r, fx)
    local pub = Moody.public(run.md, c.hours)
    local names = {}
    for _, a in ipairs(pub.active) do names[#names + 1] = a.name end
    local v = { run = c.runIndex, day = r.day, chapter = r.chapter, hours = math.floor(c.hours * 10 + 0.5) / 10,
        step = r.step, limit = math.floor(r.limit * 100 + 0.5) / 100, race = r.race, policeCap = r.policeCap, endsIn = c.secondsRemaining,
        money = math.floor(r.money * 100 + 0.5) / 100, perLevel = math.floor(r.perLevel + 0.5), moody = names,
        overridden = c.overridden or nil }
    local key = table.concat({ v.run, v.day, v.step, v.policeCap, v.limit, tostring(v.overridden), math.floor(v.hours), v.money,
        table.concat(names, ",") }, ":")
    if key ~= lastPublished then
        lastPublished = key
        pcall(function() GlobalState.ncmWeek = v end)
    end
    -- the Paddock's half of Moody: purses, calendar density and lures per tier (server-side; rules, not outcomes)
    local f = { run = c.runIndex, purse = fx.purse, calendar = fx.calendar, lure = fx.lure, overridden = c.overridden or nil }
    local fkey = enc(f)
    if fkey ~= lastFxKey then
        lastFxKey = fkey
        pcall(function() GlobalState.ncmWeekFx = f end)
        TriggerEvent("ncm:week:fx", f)
    end
end

-- ---------------------------------------------------------------------------------------------------- the ending
-- A countdown before every possible end (L309 Q3). At 00:00 the verdict is drawn (`NcmWeek.step`); only a collapse or
-- the completed seventh day plays the rewind: every client's world slows to a near-freeze together
-- (`world.setTimeScale`), the picture corrupts (`effects.screen`), and Kimiko speaks. A run that goes on hears nothing.
local SCREEN_PREFER = { "glitch", "braindance", "bd", "static", "netrunner", "quickhack", "hacked", "drugged" }
local endingFor = {}
local function toastAll(title, msg, ms)
    for _, pid in ipairs(players()) do pcall(Open77.notifications.send, pid, { type = "warning", title = title, message = msg or "", icon = "NCM", durationMs = ms or 3000 }) end
end
local function screenEffect()
    local ok, list = pcall(Open77.effects.screenCatalog)
    local have = {}
    for _, a in ipairs(ok and list or {}) do have[a] = true end
    for _, want in ipairs(SCREEN_PREFER) do if have[want] then return want end end
    for _, a in ipairs(ok and list or {}) do if tostring(a):match("glitch") or tostring(a):match("static") then return a end end
    return nil
end

local function returning(pid)
    local id = NcmIdentity and NcmIdentity.get and NcmIdentity.get(pid)
    if not id or not id.ncmDriverId then return false end
    local n = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM ledger WHERE ncm_driver_id = ? AND server_id = ? AND kind = 'reconstruction_open'",
        { id.ncmDriverId, sid() })) or 0
    return n > 0
end

--- The rewind. `kind` = "collapse" (history caught the run) or "complete" (Racing Week held for all seven days).
function NcmWeek.rewind(runIndex, kind)
    local fx = screenEffect()
    log("REWIND run %s (%s): shared freeze, screen %s, %d player(s)", tostring(runIndex), tostring(kind or "collapse"), tostring(fx), #players())
    if kind == "complete" then
        broadcast("RACING WEEK", "Seven days. Racing Week is complete. It held.", 12000)
    end
    local okT, _, whyT = pcall(Open77.world.setTimeScale, 0, 0.05, { durationMs = 7000, easeMs = 1500 })
    if not okT then log("timescale refused: %s", tostring(whyT)) end
    for _, pid in ipairs(players()) do
        if fx then pcall(Open77.effects.screen, pid, fx, { strength = 1, duration = 8 }) end
        pcall(Open77.chat.send, pid, "[RACING WEEK] 00:00:00")
    end
    CreateThread(function()
        Wait(8500)
        for _, pid in ipairs(players()) do
            pcall(Open77.effects.screen, pid, false, {})
            local again = returning(pid)
            local line
            if kind == "complete" then line = "...It held. Seven days. Logging it. Reconstruction reloading -- Day 1."
            elseif again then line = "This braindance again? Really?"
            else line = "Reconstruction loaded. Night City Racing Week -- Day 1." end
            pcall(Open77.notifications.send, pid, { type = "info", title = "KIMIKO", message = line, icon = "NCM", durationMs = 9000 })
            pcall(Open77.chat.send, pid, "[KIMIKO] " .. line)
        end
    end)
end

local function ending(c)
    if c.overridden or not c.open then return end           -- a pinned hour never ends the real week
    local key = ("%d:%d"):format(c.runIndex, c.possibleEnd or 0)
    local e = endingFor[key] or {}
    endingFor[key] = e
    if c.secondsRemaining <= 3600 and not e.hour then
        e.hour = true
        toastAll("RACING WEEK", "One hour to noon.", 8000)
    end
    if c.secondsRemaining <= 150 and not e.final then
        e.final = true
        local endsAt = c.endUtc or (now() + c.secondsRemaining)
        local runIndex, boundary = c.runIndex, (c.possibleEnd or 3) * 24
        CreateThread(function()
            local said = {}
            while true do
                local left = math.floor(endsAt - now())
                if left <= 0 then break end
                for _, mark in ipairs({ 120, 60, 30, 10, 5, 4, 3, 2, 1 }) do
                    if left <= mark and not said[mark] then
                        said[mark] = true
                        toastAll("RACING WEEK", ("00:%02d:%02d"):format(math.floor(left / 60), left % 60), 1500)
                    end
                end
                Wait(250)
            end
            -- 12:00: the verdict, now. The step judges; the record says what it was. Never a rewind without a verdict:
            -- wait for the instant itself, then for the row (a slow database must not read as a collapse).
            while now() < endsAt do Wait(200) end
            local row
            for _ = 1, 15 do
                pcall(NcmWeek.step)
                row = MySQL.single.await("SELECT kind FROM racing_week_verdict WHERE server_id = ? AND run_index = ? AND boundary_h = ?",
                    { sid(), runIndex, boundary })
                if row then break end
                Wait(2000)
            end
            if not row then log("run %d: no verdict recorded for hour %d after 30 s -- nothing plays (check the step log)", runIndex, boundary); return end
            local kind = row.kind
            if kind == "continue" then
                log("run %d: 12:00 became 12:01 (hour %d survived) -- nothing plays", runIndex, boundary)
            else
                NcmWeek.rewind(runIndex, kind)
            end
        end)
    end
end

-- ---------------------------------------------------------------------------------------------------- the verdict

--- The standing a run's verdicts are judged on: the live run's curve, a stored run's last persisted curve, or nil --
--- a run nobody lived in faces history unattended (week.catchup).
local function standingFor(n)
    if run and not run.scratch and run.index == n then return run.st end
    local okR, row = pcall(MySQL.single.await, "SELECT state_json FROM racing_week_run WHERE server_id = ? AND run_index = ?", { sid(), n })
    local st = okR and row and dec(row.state_json)
    if type(st) == "table" and st.deviation ~= nil then return st end
    return nil
end

--- Judge every possible end that has passed and not been judged -- one while the world runs, every one it missed
--- after downtime or a single player's absence (week.catchup, L338), in order. Records each verdict (once per
--- boundary, ever), moves the timeline and tells the other resources once. `history` mode ends every run at hour 72.
local function judgeIfDue(t)
    if run and run.scratch then return end
    local settled = Catch.settle(cfg(), runs, t, runSeed, standingFor, { mode = verdictMode() })
    if #settled.verdicts == 0 then return end
    for _, v in ipairs(settled.verdicts) do
        local st = standingFor(v.run)
        local state = { deviation = st and st.deviation, reservoirs = st and st.res, carrier = Curve.carrier(v.hours),
            band = Curve.band(v.hours), moody = (run and run.index == v.run) and Moody.public(run.md, v.hours).active or nil,
            mode = verdictMode(), unattended = v.unattended or nil }
        -- a run the world never opened (it passed entirely during an absence) still gets its row: the timeline is rows
        pcall(MySQL.update.await, [[INSERT IGNORE INTO racing_week_run (server_id, run_index, opened_at, state_json, updated_at, start_utc, seed)
            VALUES (?, ?, ?, ?, ?, ?, ?)]], { sid(), v.run, t, "{}", t, v.startUtc, runSeed(v.run) })
        local okI = pcall(MySQL.update.await, [[INSERT IGNORE INTO racing_week_verdict (server_id, run_index, boundary_h, kind, p, z, u, state_json, at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], { sid(), v.run, v.hours, v.kind, v.p, v.z, v.u, enc(state), t })
        -- the recorded verdict wins (a restart re-judges nothing)
        local row = MySQL.single.await("SELECT kind, p, z, u FROM racing_week_verdict WHERE server_id = ? AND run_index = ? AND boundary_h = ?",
            { sid(), v.run, v.hours })
        local kind = row and row.kind or v.kind
        log("VERDICT run %d at hour %d: p %.3f (z %+.3f, u %.3f) -> %s%s%s", v.run, v.hours, tonumber(row and row.p) or v.p,
            tonumber(row and row.z) or v.z, tonumber(row and row.u) or v.u, kind, v.unattended and " [unattended]" or "",
            okI and "" or " (record failed)")
        if kind == "continue" then
            pcall(MySQL.update.await, "UPDATE racing_week_run SET survived = GREATEST(survived, ?) WHERE server_id = ? AND run_index = ?",
                { math.floor(v.hours / 24), sid(), v.run })
        else
            pcall(MySQL.update.await, [[UPDATE racing_week_run SET end_utc = COALESCE(end_utc, ?), end_kind = COALESCE(end_kind, ?)
                WHERE server_id = ? AND run_index = ?]], { v.atUtc, kind, sid(), v.run })
        end
    end
    if #settled.verdicts > 1 then log("caught up %d verdict(s) missed while the world was not running", #settled.verdicts) end
    loadRuns(true)
    tellTimeline()
end

-- L305: what is NORMAL here -- this server's trailing 7-day crash/contact DNFs per Paddock race, and races an hour
-- (momentum's baseline), measured hourly, so a crashy or busy server is not read as a crashy or busy week.
local expectedCache, expectedAt = nil, 0
function NcmWeek.expected(t)
    if expectedCache and t - expectedAt < 3600 then return expectedCache end
    expectedAt = t
    local okQ, row = pcall(MySQL.single.await, [[SELECT SUM(dnf_reason IN ('crash','contact')) AS crashes, COUNT(DISTINCT race_id) AS races,
        MIN(at) AS first FROM paddock_result WHERE server_id = ? AND at >= ?]], { sid(), t - 7 * 86400 })
    local races = okQ and row and tonumber(row.races) or 0
    if races >= 50 then
        local rate = math.max(0.2, math.min(2.0, (tonumber(row.crashes) or 0) / races))
        local spanH = math.max(24, (t - (tonumber(row.first) or t)) / 3600)
        expectedCache = { race_crash = rate, racesPerHour = races / spanH }
        log("expected crash rate %.2f per race, %.1f races an hour (%d races, %.0f h)", rate, races / spanH, races, spanH)
    else
        expectedCache = nil
    end
    return expectedCache
end

--- One step: the timeline, Moody, the curve, the verdict. Idempotent in time.
function NcmWeek.step(t)
    t = t or now()
    loadRuns()
    -- the verdicts first, every one that is due (after an absence there may be many): the run this instant belongs to
    -- is only known once the timeline is settled
    if not pinned then judgeIfDue(t) end
    local c = clock(t)
    if not c then return nil end
    ensureRun(c, t)
    -- after downtime the missed rolls are made late, in order; all are recorded, only the last three are announced
    local made = Moody.step(run.md, run.seed, run.index, c.hours)
    for i, rec in ipairs(made) do rec.quiet = (#made - i) >= 3; rolled(rec, t) end
    local fx = Moody.effects(run.md, c.hours)
    local tally = facts
    facts = {}
    local _, fired = Curve.step(run.st, c.hours, tally, NcmWeek.expected(t))
    for _, s in ipairs(fired) do announce(s, c, t) end
    local r = Curve.read(run.st, c.hours, fx)
    lastRead = { clock = c, read = r, fx = fx }
    local h = math.floor(c.hours)
    if not run.scratch and lastSampleHour[run.index] ~= h then
        lastSampleHour[run.index] = h
        event("sample", tostring(h), c.hours, { carrier = r.carrier, tolerance = r.tolerance, deviation = r.deviation, step = r.step,
            reservoirs = r.reservoirs, moody = Moody.public(run.md, c.hours).active }, t)
        log("hour %d of run %d (day %d): carrier %.3f tolerance %.3f (deviation %+.3f: safety %+.3f enforcement %+.3f momentum %+.3f) step %s cap %d",
            h, run.index, c.day, r.carrier, r.tolerance, r.deviation, r.reservoirs.safety, r.reservoirs.enforcement,
            r.reservoirs.momentum, r.step, r.policeCap)
        -- the racing radio, every two run hours: the city's mood composed from the state (doc 47 §1.7), never a number
        if h > 0 and h % 2 == 0 then
            local v = Vibe.classify(r, fx, c.hours)
            local line = Vibe.line(run.seed, run.index, h, v)
            log("RADIO hour %d: [%s / %s%s%s] %s", h, v.mood, v.cause, v.surprise and (" / " .. v.surprise) or "", v.offMap and " / off the map" or "", line)
            event("sample", "radio:" .. tostring(h), c.hours, { mood = v.mood, cause = v.cause, surprise = v.surprise, offMap = v.offMap, line = line }, t)
            broadcast("RACING RADIO", line, 10000)
        end
    end
    if next(tally) then
        local parts = {}
        for k, n in pairs(tally) do parts[#parts + 1] = ("%s=%g"):format(k, n) end
        table.sort(parts)
        log("facts %s -> deviation %+.3f (band %.3f)", table.concat(parts, " "), run.st.deviation, Curve.band(c.hours))
    end
    persist(t)
    publish(c, r, fx)
    pcall(ending, c)
    return lastRead
end

--- What the host reads now: { clock = week.clock result, read = week.curve read, fx = Moody's effects }.
function NcmWeek.read()
    if not lastRead then pcall(NcmWeek.step) end
    return lastRead
end

--- L330: this run's seed -- the one seed every NCM calendar of this Racing Week derives from (Night City's and every
--- Earth venue's). Server-side only, like the tolerance: players read the calendar, not the seed.
function NcmWeek.seed()
    if not run then pcall(NcmWeek.step) end
    return run and run.seed or nil, run and run.index or nil
end

--- The timeline (runIndex -> { endUtc, endKind, survived }), for other server code in this resource.
function NcmWeek.runs() return loadRuns() end

--- Tally a fact for the next step. Kinds: week.curve IMPULSE keys plus `race`; unknown kinds are kept and logged.
function NcmWeek.fact(kind, n)
    if type(kind) ~= "string" then return end
    n = tonumber(n) or 1
    if n == 0 then return end
    facts[kind] = (facts[kind] or 0) + n
end
AddEventHandler("ncm:week:fact", function(kind, n) NcmWeek.fact(kind, n) end)

CreateThread(function()
    Wait(4000)
    loadRuns(true)
    tellTimeline()
    while true do
        local ok, err = pcall(NcmWeek.step)
        if not ok then log("step FAILED: %s", tostring(err)) end
        Wait(STEP_S * 1000)
    end
end)

-- ---------------------------------------------------------------------------------------------------- the console

local function devView()
    local cur = NcmWeek.step()
    if not cur then log("before the epoch: no run yet"); return end
    local c, r, fx = cur.clock, cur.read, cur.fx
    log("run %d %s (day %d) hour %.2f%s | carrier %.3f tolerance %.3f deviation %+.3f band %.3f | reservoirs safety %+.3f enforcement %+.3f momentum %+.3f",
        c.runIndex, r.chapter, r.day, c.hours, c.overridden and " [pinned]" or "", r.carrier, r.tolerance, r.deviation,
        Curve.band(c.hours), r.reservoirs.safety, r.reservoirs.enforcement, r.reservoirs.momentum)
    log("  step %s: limit x%.2f race %s police cap %d per-level %.0f | money x%.2f | %s end at hour %d in %d s (survived to day %d) | verdicts: %s",
        r.step, r.limit, r.race, r.policeCap, r.perLevel, r.money, c.open and "possible" or "recorded", (c.possibleEnd or 3) * 24,
        c.secondsRemaining, (c.survived or 2) + 1, verdictMode())
    local boundary = (c.possibleEnd or 3) * 24
    local z = Cont.z(run.st, boundary)
    log("  DEVELOPER ONLY: if judged now at hour %d, p = %.3f (z %+.3f)", boundary, Cont.probability(boundary, z) or -1, z)
    local pub = Moody.public(run.md, c.hours)
    local act = {}
    for _, a in ipairs(pub.active) do act[#act + 1] = ("%s until h%.1f"):format(a.name, a.untilH) end
    log("  MOODY: %d roll(s); next at hour %.1f%s; active: %s", run.md.n or 0, run.md.nextRollH or -1, pub.restless and " (RESTLESS)" or "",
        #act > 0 and table.concat(act, ", ") or "none")
    local p = {}
    for t, x in pairs(fx.purse or {}) do if x ~= 1 then p[#p + 1] = ("purse %s x%.2f"):format(t, x) end end
    for t, x in pairs(fx.calendar or {}) do if x ~= 1 then p[#p + 1] = ("calendar %s x%.2f"):format(t, x) end end
    for t, x in pairs(fx.lure or {}) do if x > 0 then p[#p + 1] = ("lure %s %.1f"):format(t, x) end end
    table.sort(p)
    if #p > 0 then log("  MOODY effects: %s", table.concat(p, ", ")) end
end

RegisterCommand("ncm.week", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local verb, arg = args and args[1], tonumber(args and args[2])
    if verb == "hour" and arg then pinned = math.max(0, math.min(Curve.MAX_HOURS, arg))
    elseif verb == "day" and arg and arg >= 1 and arg <= 7 then pinned = (math.floor(arg) - 1) * 24 + 12
    elseif verb == "clock" then pinned = nil
    elseif verb == "fact" and args[2] then NcmWeek.fact(args[2], tonumber(args[3]) or 1)
    elseif verb == "rewind" then CreateThread(function() NcmWeek.rewind((lastRead and lastRead.clock.runIndex) or 0, args[2] == "complete" and "complete" or "collapse") end); return
    elseif verb == "moody" then
        CreateThread(function()
            local rows = MySQL.query.await("SELECT roll_n, d20, face, hours, data_json FROM racing_week_moody WHERE server_id = ? AND run_index = ? ORDER BY roll_n",
                { sid(), run and run.index or 0 }) or {}
            if #rows == 0 then log("no Moody rolls recorded for run %s yet", tostring(run and run.index)) end
            for _, r in ipairs(rows) do
                local d = dec(r.data_json) or {}
                log("  roll %d  d20=%2d  hour %5.1f  %s%s", r.roll_n, r.d20, tonumber(r.hours) or 0, tostring(d.name or r.face),
                    d.target and (" -> " .. tostring(d.target) .. (d.into and (" becomes " .. tostring(d.into)) or "")) or "")
            end
        end)
        return
    elseif verb == "judge" then
        CreateThread(function()
            local cur = NcmWeek.read()
            if not cur then return end
            local boundary = (cur.clock.possibleEnd or 3) * 24
            local v = Cont.judge(run.seed, run.index, boundary, run.st)
            log("judge (NOT recorded): run %d at hour %d -> p %.3f z %+.3f u %.3f -> %s", run.index, boundary, v.p, v.z, v.u, v.kind)
        end)
        return
    elseif verb then log("usage: ncm.week [hour <0..168> | day <1..7> | clock | fact <kind> <n> | moody | judge | rewind [complete]]"); return end
    lastPublished, lastFxKey = nil, nil
    CreateThread(devView)
end, false)
