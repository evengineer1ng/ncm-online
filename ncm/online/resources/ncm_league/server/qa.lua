-- ncm_league / server / qa — passive QA observation during ordinary play.
--
-- `wp/QA_INSTRUMENTATION.md` maps this back to the QA corpus. The short version: 102 of 133 QA items had never
-- been run, because they need an operator present and there is one operator. When players use NCM normally,
-- the server should accumulate evidence against questions we already care about, without those players knowing
-- they are testing anything.
--
-- **Three properties this file must keep, in priority order.**
--
-- 1. **Gameplay never depends on it.** Every observation is wrapped. A throw in here is swallowed and logged;
--    it can never reach a player. Nothing downstream of an observation changes what the game does.
-- 2. **The flag gates the WRITING, not the observing.** Domain code emits facts it would emit anyway; this
--    module subscribes. Disabling stops the subscription doing work -- it does not put `if qaEnabled` branches
--    inside domain logic, because that is the architecture that becomes impossible to remove later.
-- 3. **Observe, never re-implement.** Verdicts come from `qa.rules`, and the facts come from the authoritative
--    systems that already computed them. A second "telemetry truth" that disagrees with domain truth would be
--    worse than no instrumentation at all.
--
-- Facts, never conclusions: this records `calls=3` and `help_opened`, never `PLAYER_CONFUSED`.
NcmQa = {}

local Core = NcmCore
local Rules = Core.get("qa.rules")

--- The one server-side flag. **Default ON for the current alpha environment**, per the instrumentation brief.
--- Turning it off cleanly stops optional QA work and changes nothing a player can see.
local ENABLED_DEFAULT = true
local enabled = ENABLED_DEFAULT
local BUILD_BASE = "world 0.5.0 · league 0.3.0"

--- Evidence must say which world produced it. A FAIL observed on the developer's Windows box and a FAIL
--- observed on the official server are different facts, and once two environments exist they will otherwise be
--- indistinguishable in the same-shaped table.
local function build()
    local env = (NcmCalendar and NcmCalendar.environment and NcmCalendar.environment()) or "development"
    return BUILD_BASE .. " · " .. env
end

local function log(fmt, ...) print(("[ncm_league/qa] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function serverId() return (NcmCalendar and NcmCalendar.serverId and NcmCalendar.serverId()) or "ncm" end

function NcmQa.enabled() return enabled == true end

--- Record one verdict. Idempotent in the way that matters: a repeated identical observation increments a
--- counter rather than appending a row, so the table is bounded by (items x verdicts x servers) forever.
---
--- Never raises. A QA write that broke a race would be the worst possible outcome of a QA system.
function NcmQa.record(v, driverId)
    if not enabled or type(v) ~= "table" or not v.qaId then return end
    local ok, err = pcall(function()
        if not (MySQL and MySQL.isReady()) then return end
        local detail = tostring(v.detail or ""):sub(1, 500)
        -- **No nils in the parameter array.** A nil in the middle of a Lua table literal truncates the
        -- sequence, and the bridge then rejects the call with `invalid_parameters` -- which is exactly what a
        -- boot observation with no driver did on first deploy. `NULLIF(?, '')` keeps the column honestly NULL
        -- while the array stays dense.
        MySQL.insert.await(
            "INSERT INTO qa_observation (qa_id, server_id, verdict, occurrences, first_seen, last_seen, " ..
            "last_detail, last_driver_id, build) VALUES (?, ?, ?, 1, ?, ?, ?, NULLIF(?, ''), ?) " ..
            "ON DUPLICATE KEY UPDATE occurrences = occurrences + 1, last_seen = VALUES(last_seen), " ..
            "last_detail = VALUES(last_detail), last_driver_id = VALUES(last_driver_id), build = VALUES(build)",
            { v.qaId, serverId(), v.verdict, now(), now(), detail, tostring(driverId or ""), build() })
    end)
    if not ok then
        log("observation dropped (%s): %s", tostring(v.qaId), tostring(err))
        return
    end
    -- A FAIL is a stated invariant being violated, so it earns a log line of its own. PASS and REVIEW
    -- accumulate silently; the point of them is the count, not the noise.
    if v.verdict == Rules.FAIL then
        log("QA FAIL %s: %s", tostring(v.qaId), tostring(v.detail))
    end
end

--- Convenience for host code that has facts but not a verdict yet.
local function observe(fn, ...)
    if not enabled then return end
    local ok, v = pcall(fn, ...)
    if ok and type(v) == "table" then NcmQa.record(v) end
end

-- ---------------------------------------------------------------------------------------------
-- Subscriptions. Every one of these is a fact some authoritative system already announces.
-- ---------------------------------------------------------------------------------------------

--- G1/D6, A2, G4 — the race invariants. `ncm:race.completed` carries what the session already computed.
AddEventHandler("ncm:race.completed", function(info)
    if not enabled or type(info) ~= "table" then return end
    for _, r in ipairs(type(info.results) == "table" and info.results or {}) do
        if r.elapsedMs then observe(Rules.raceTime, r.elapsedMs) end
        if r.accomplishments then
            observe(Rules.soloResult, info.fieldSize, r.accomplishments)
            observe(Rules.onceOnly, r.accomplishments, r.heldBefore)
        end
    end
end)

--- P4 / L107 — ring, card, waypoint and venue options must all name the driver's own race.
AddEventHandler("ncm:qa.guidance", function(expectedEventId, shownEventId, surface, driverId)
    if not enabled then return end
    local ok, v = pcall(Rules.guidanceTarget, expectedEventId, shownEventId, surface)
    if ok and type(v) == "table" then NcmQa.record(v, driverId) end
end)

--- P1 — a Guide that was published and never drew is the silent-drop family (KB-59/63/65).
AddEventHandler("ncm:qa.guideDelivery", function(rows, drew, ms, driverId)
    if not enabled then return end
    local ok, v = pcall(Rules.guideDelivery, rows, drew, ms)
    if ok and type(v) == "table" then NcmQa.record(v, driverId) end
end)

--- T2/T3/T4 — discovery provenance, including the anti-farm rule that cannot be re-derived later.
AddEventHandler("ncm:qa.discovery", function(driverId, sourceDriverId, previousSource, holding)
    if not enabled then return end
    local ok, v = pcall(Rules.discovery, driverId, sourceDriverId, previousSource, holding)
    if ok and type(v) == "table" then NcmQa.record(v, driverId) end
end)

--- N7 — the option list is presentation; the server decides. A stale client must not be able to enter.
AddEventHandler("ncm:qa.entry", function(offered, accepted, reason, driverId)
    if not enabled then return end
    local ok, v = pcall(Rules.entryAgreement, offered, accepted, reason)
    if ok and type(v) == "table" then NcmQa.record(v, driverId) end
end)

-- ---------------------------------------------------------------------------------------------
-- Boot observations. These need no player at all and answer items nobody has had time to run.
-- ---------------------------------------------------------------------------------------------

local function bootObservations()
    -- M7: assets must survive a restart. Compared against what the previous boot recorded.
    local ok, row = pcall(function()
        return MySQL.single.await("SELECT COUNT(*) AS n FROM vehicle_asset WHERE server_id = ?", { serverId() })
    end)
    local after = ok and row and tonumber(row.n) or nil
    local okPrev, prev = pcall(function()
        return MySQL.single.await(
            "SELECT last_detail FROM qa_observation WHERE qa_id = 'M7' AND server_id = ? " ..
            "ORDER BY last_seen DESC LIMIT 1", { serverId() })
    end)
    local before = okPrev and prev and tonumber(tostring(prev.last_detail or ""):match("(%d+)")) or nil
    if after ~= nil then
        if before ~= nil then observe(Rules.ownershipSurvived, before, after)
        else NcmQa.record({ qaId = "M7", verdict = Rules.PASS, detail = ("%d asset(s) intact"):format(after) }) end
    end

    -- M1: migrations settled. `NcmMigrations.status()` is the authoritative answer, not a guess.
    local okM, st = pcall(NcmMigrations.status)
    if okM and type(st) == "table" then
        observe(Rules.migrations, #(st.pending or {}), 0)
    end

    -- O1: the championships the calendar actually started.
    local okC, series = pcall(function() return NcmCalendar and NcmCalendar.series end)
    if okC and type(series) == "table" then
        local list = {}
        for _ in pairs(series) do list[#list + 1] = true end
        observe(Rules.calendarShape, list, 5)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Operator surface
-- ---------------------------------------------------------------------------------------------

-- ncm.qa [fail|review|pass] -- the morning read. What was exercised while nobody was watching.
RegisterCommand("ncm.qa", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local want = args and args[1] and tostring(args[1]):lower() or nil
    CreateThread(function()
        if not (MySQL and MySQL.isReady()) then log("database unavailable"); return end
        local sql = "SELECT qa_id, verdict, occurrences, first_seen, last_seen, last_detail FROM qa_observation " ..
                    "WHERE server_id = ?"
        local params = { serverId() }
        if want == "fail" or want == "review" or want == "pass" then
            sql = sql .. " AND verdict = ?"; params[#params + 1] = want
        end
        sql = sql .. " ORDER BY FIELD(verdict,'fail','review','pass'), last_seen DESC"
        local ok, rows = pcall(function() return MySQL.query.await(sql, params) or {} end)
        if not ok then log("read failed: %s", tostring(rows)); return end
        if #rows == 0 then
            log("no QA evidence recorded yet (instrumentation %s)", enabled and "ON" or "OFF")
            return
        end
        log("QA evidence (%s) -- instrumentation %s", want or "all", enabled and "ON" or "OFF")
        local counts = { fail = 0, review = 0, pass = 0 }
        for _, r in ipairs(rows) do
            counts[r.verdict] = (counts[r.verdict] or 0) + 1
            log("  %-5s %-5s x%-5d %s", tostring(r.verdict):upper(), tostring(r.qa_id),
                tonumber(r.occurrences) or 0, tostring(r.last_detail or ""):sub(1, 110))
        end
        log("  -- %d item(s) failing, %d for review, %d passing. QA corpus: wp/OFFLINE_TEST_QUEUE.md",
            counts.fail or 0, counts.review or 0, counts.pass or 0)
    end)
end, false)

-- ncm.qa.off / ncm.qa.on -- the one flag. Gameplay is identical either way.
RegisterCommand("ncm.qa.off", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    enabled = false; log("QA instrumentation OFF (gameplay unchanged)")
end, false)
RegisterCommand("ncm.qa.on", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    enabled = true; log("QA instrumentation ON")
end, false)

AddEventHandler("onResourceStart", function(name)
    if name ~= "ncm_league" then return end
    CreateThread(function()
        for _ = 1, 40 do
            if MySQL and MySQL.isReady() then break end
            Wait(500)
        end
        -- ...and after migrations, or a boot observation races the CREATE TABLE that holds it. Observed on the
        -- first deploy: M7 and M1 were dropped 200 ms before migration 020 ran.
        for _ = 1, 60 do
            local okS, st = pcall(NcmMigrations.status)
            if okS and type(st) == "table" and #(st.pending or {}) == 0 then break end
            Wait(500)
        end
        log("QA instrumentation %s on %s; %d rule(s) wired. Inspect with `ncm.qa`.",
            enabled and "ON" or "OFF", build(), #Rules.covers())
        if enabled then pcall(bootObservations) end
    end)
end)
