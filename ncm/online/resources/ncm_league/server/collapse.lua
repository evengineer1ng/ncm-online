-- ncm_league / server / collapse -- the end of a Racing Week: archive, reset, keep what survives (L303; doc 45 §P).
--
-- WHEN. After the crown: the Paddock announces a run's champions (`ncm:week:champions`), or CROWN_GRACE_S after the
-- run's end if nobody was crowned. A run's end is its RECORDED end (doc 47, L310): ncm_world's verdict at a possible end
-- -- noon of Day 3 through Day 7 -- writes it, and this resource reads the same timeline (`week.clock.locate` over
-- `racing_week_run`, refreshed on `ncm:week:timeline`). A run that went on past hour 72 has not ended. Only the newest finished run collapses; older ones missed while the server was down
-- are recorded `unwitnessed` (nothing is invented). A run never collapses twice (racing_week_collapse).
--
-- MODE (convar `ncm_week_collapse`): "dryrun" (THE DEFAULT) computes and records the complete plan and changes
-- nothing; "live" executes it; "off" does neither. The owner reads a dry run before flipping to live, because live
-- moves real garages and wallets. Console: `ncm.week.collapse plan` plans the CURRENT run now, as if it had ended.
--
-- WHAT (week.collapse): every driver's wallet closes to zero and reopens at the new-player grant; every car not
-- anchored, and the parts on it and in the driver's inventory, is re-keyed to the run's archive namespace; SR halves
-- toward neutral; NPC team affiliations end. Then the Paddock moves its world to the archive and restarts into a new
-- genesis from the historical seed (`ncm:week:collapse.paddock`), and every called car goes home (`ncm:week:collapsed`).
-- Nothing is deleted. The rewind presentation covers the restart.
NcmCollapse = {}

local Core = NcmCore
local K = Core.get("week.collapse")
local Week = Core.get("week.clock")
local Mixed = Core.get("paddock.mixed")
local Markets = Core.get("economy.markets")
local Json = Core.get("vocabulary.json")
local function log(fmt, ...) print(("[ncm_league/collapse] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function sid() return NcmCalendar.serverId() end
local function cfg() return Week.config(GetConvar or function(_, d) return d end) end
local function mode() return (GetConvar and GetConvar("ncm_week_collapse", "dryrun")) or "dryrun" end
local function enc(v) local ok, x = pcall(Json.encode, v); return ok and x or "{}" end

local function singlePlayer()
    local ok, h = pcall(function() return Open77.runtime.host and Open77.runtime.host() end)
    return ok and h == "ncm_sp"
end

local CROWN_GRACE_S = 25 * 60

-- the timeline (doc 47): runIndex -> { endUtc, endKind, survived }, from ncm_world's rows
local runs, runsAt = {}, 0
local function normRuns(r)
    local out = {}
    for k, v in pairs(r or {}) do
        local n = tonumber(k)
        if n and type(v) == "table" then out[n] = { endUtc = tonumber(v.endUtc), endKind = v.endKind, survived = tonumber(v.survived) } end
    end
    return out
end
local function timeline(force)
    if force or now() - runsAt >= 60 then
        local okQ, rows = pcall(MySQL.query.await, "SELECT run_index, end_utc, end_kind, survived FROM racing_week_run WHERE server_id = ?", { sid() })
        if okQ and type(rows) == "table" then
            local out = {}
            for _, r in ipairs(rows) do out[tonumber(r.run_index)] = { endUtc = tonumber(r.end_utc), endKind = r.end_kind, survived = tonumber(r.survived) } end
            runs, runsAt = out, now()
        end
    end
    return runs
end
AddEventHandler("ncm:week:timeline", function(r) runs, runsAt = normRuns(r), now() end)
--- Where an instant sits in the week: week.clock fields over the recorded ends.
local function weekAt(c, utc) return Week.nowIn(c, timeline(), math.floor(tonumber(utc) or 0)) end
--- The Racing Week run this instant belongs to (markets rotate their line-ups per run, 2026-10-12).
function NcmCollapse.runIndex()
    local ok, at = pcall(weekAt, cfg(), now())
    return ok and type(at) == "table" and tonumber(at.runIndex) or nil
end
local crowned = {}                 -- run -> true once the Paddock announced its champions
local busy = false

AddEventHandler("ncm:week:champions", function(run) crowned[tonumber(run) or -1] = true end)

-- ---------------------------------------------------------------------------------------------------- facts

local function drivers(base)
    local rows = MySQL.query.await([[SELECT DISTINCT ncm_driver_id AS d FROM vehicle_asset WHERE server_id = ? AND ncm_driver_id IS NOT NULL
        UNION SELECT DISTINCT ncm_driver_id AS d FROM ledger WHERE server_id = ? AND ncm_driver_id IS NOT NULL]], { base, base }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.d end
    table.sort(out)
    return out
end

local function carsOf(base, driverId)
    local cars = MySQL.query.await([[SELECT asset_id, record, odometer_m, last_driven_at, acquired_via, granted_by FROM vehicle_asset
        WHERE server_id = ? AND ncm_driver_id = ?]], { base, driverId }) or {}
    local raced = {}
    for _, r in ipairs(MySQL.query.await([[SELECT sr.asset_id, COUNT(*) AS n, SUM(sr.state = 'finished' AND sr.position = 1) AS wins
        FROM session_result sr JOIN session s ON s.session_id = sr.session_id JOIN event e ON e.event_id = s.event_id
        WHERE sr.ncm_driver_id = ? AND e.server_id = ? AND s.kind = 'race' AND sr.asset_id IS NOT NULL GROUP BY sr.asset_id]],
        { driverId, base }) or {}) do raced[r.asset_id] = { n = tonumber(r.n) or 0, wins = tonumber(r.wins) or 0 } end
    local out = {}
    for _, c in ipairs(cars) do
        local r = raced[c.asset_id] or { n = 0, wins = 0 }
        out[#out + 1] = { assetId = c.asset_id, record = c.record, races = r.n, sanctionedWins = r.wins,
            odometerM = tonumber(c.odometer_m) or 0, lastDrivenAt = tonumber(c.last_driven_at),
            -- a car a run condition granted (doc 45 §G) -- none exist yet; the rule is in place for when they do
            conditionGrant = c.acquired_via == "grant" and tostring(c.granted_by or ""):match("^condition:") ~= nil }
    end
    return out
end

local function history(base, driverId, c)
    local day3 = false
    for _, r in ipairs(MySQL.query.await([[SELECT s.green_at FROM session_result sr JOIN session s ON s.session_id = sr.session_id
        JOIN event e ON e.event_id = s.event_id WHERE sr.ncm_driver_id = ? AND e.server_id = ? AND s.kind = 'race'
        AND sr.state = 'finished' AND s.green_at IS NOT NULL ORDER BY s.green_at DESC LIMIT 400]], { driverId, base }) or {}) do
        local at = weekAt(c, r.green_at)
        if at and at.hours >= 48 then day3 = true; break end
    end
    local key = Mixed.personKey(driverId)
    local premier = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM paddock_result WHERE (server_id = ? OR server_id LIKE ?)
        AND person_id = ? AND series_id = 'premier']], { base, base .. "#R%", key })) or 0
    return { day3Finish = day3, premierStart = premier > 0 }
end

local function chosenFor(base, run, driverId)
    local out = {}
    for _, r in ipairs(MySQL.query.await([[SELECT asset_id FROM racing_week_anchor WHERE server_id = ? AND run_index = ?
        AND ncm_driver_id = ? AND source = 'chosen' ORDER BY chosen_at DESC, asset_id]], { base, run, driverId }) or {}) do out[#out + 1] = r.asset_id end
    return out
end

function NcmCollapse.anchorStatus(driverId)
    if singlePlayer() then return nil end
    local at = weekAt(cfg(), now())
    if not at then return nil end
    local cars = carsOf(sid(), driverId)
    local chosen = chosenFor(sid(), at.runIndex, driverId)
    local selected = K.onlineAnchor(cars, chosen)
    return { runIndex = at.runIndex, assetId = selected[1] and selected[1].assetId or nil,
        source = selected[1] and selected[1].source or nil }
end

--- The full plan for run `run` -- read-only.
function NcmCollapse.plan(run)
    local base, c = sid(), cfg()
    local archive = K.archiveKey(base, run)
    local plan = { run = run, server = base, archive = archive, at = now(), drivers = {}, paddock = {} }
    for i, d in ipairs(drivers(base)) do
        local cars = carsOf(base, d)
        local h = history(base, d, c)
        local slots = singlePlayer() and K.anchorSlots(h) or 1
        local anchors, refused
        if singlePlayer() then anchors, refused = K.anchors(cars, chosenFor(base, run, d), slots)
        else anchors, refused = K.onlineAnchor(cars, chosenFor(base, run, d)) end
        local keep = {}
        for _, a in ipairs(anchors) do keep[a.assetId] = true end
        local move = {}
        for _, car in ipairs(cars) do if not keep[car.assetId] then move[#move + 1] = car.assetId end end
        local sr = tonumber(MySQL.scalar.await("SELECT sr FROM driver_sr WHERE ncm_driver_id = ? AND server_id = ?", { d, base }))
        plan.drivers[#plan.drivers + 1] = { driverId = d, balance = NcmEconomy.balanceOf(d) or 0, slots = slots, history = h,
            anchors = anchors, refused = refused, moveCars = move, cars = #cars, sr = sr,
            srAfter = sr and (singlePlayer() and K.srReset(sr) or 5.0) or nil,
            wallet = K.wallet(NcmEconomy.balanceOf(d) or 0, Markets.STARTER_GRANT) }
        if i % 10 == 0 then Wait(0) end
    end
    -- the Paddock's side, counted: every run-local table, NPC assets, Exchange rows
    local tables = {}
    for _, r in ipairs(MySQL.query.await([[SELECT TABLE_NAME AS t FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
        AND COLUMN_NAME = 'server_id' AND TABLE_NAME LIKE 'paddock\_%']], {}) or {}) do tables[#tables + 1] = r.t end
    for _, t in ipairs(K.paddockMoves(tables)) do
        plan.paddock[#plan.paddock + 1] = { table = t, rows = tonumber(MySQL.scalar.await(("SELECT COUNT(*) FROM `%s` WHERE server_id = ?"):format(t), { base })) or 0 }
    end
    plan.npcCars = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM vehicle_asset WHERE server_id = ? AND ncm_driver_id IS NULL AND owner_principal_kind IN ('person','org')", { base })) or 0
    plan.npcParts = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM component_asset WHERE server_id = ? AND ncm_driver_id IS NULL AND owner_principal_kind IN ('person','org')", { base })) or 0
    return plan
end

local function summary(plan)
    local moved, kept, money = 0, 0, 0
    for _, d in ipairs(plan.drivers) do moved = moved + #d.moveCars; kept = kept + #d.anchors; money = money + (d.balance or 0) end
    local rows = 0
    for _, p in ipairs(plan.paddock) do rows = rows + p.rows end
    return ("run %d -> %s: %d driver(s), %d car(s) anchored, %d archived, €$%d of wallets closed; Paddock %d row(s) in %d table(s), %d NPC car(s), %d NPC part(s)")
        :format(plan.run, plan.archive, #plan.drivers, kept, moved, money, rows, #plan.paddock, plan.npcCars, plan.npcParts)
end

-- ---------------------------------------------------------------------------------------------------- execute

-- Single player keeps its earlier wallet and anchor policy (L338); this new rule is for Online.

local function executeDrivers(plan, t)
    local base, archive = plan.server, plan.archive
    local keepMoney = singlePlayer()
    for _, d in ipairs(plan.drivers) do
        local tx = {}
        if not keepMoney then
            tx[#tx + 1] = { query = [[INSERT IGNORE INTO ledger (ncm_driver_id, server_id, kind, amount, currency, ref, note, idem_key)
                VALUES (?, ?, 'reconstruction_collapse', ?, 'eddies', ?, 'Racing Week ended: the run''s money is gone', ?)]],
                values = { d.driverId, base, d.wallet.close, archive, ("rw-close:%s:%s"):format(archive, d.driverId) } }
            tx[#tx + 1] = { query = [[INSERT IGNORE INTO ledger (ncm_driver_id, server_id, kind, amount, currency, ref, note, idem_key)
                VALUES (?, ?, 'reconstruction_open', ?, 'eddies', ?, 'Racing Week begins: everyone starts here', ?)]],
                values = { d.driverId, base, d.wallet.open, archive, ("rw-open:%s:%s"):format(archive, d.driverId) } }
        end
        for _, a in ipairs(d.anchors) do
            tx[#tx + 1] = { query = [[INSERT IGNORE INTO racing_week_anchor (server_id, run_index, ncm_driver_id, asset_id, source, chosen_at)
                VALUES (?, ?, ?, ?, ?, ?)]], values = { base, plan.run, d.driverId, a.assetId, a.source, t } }
        end
        for _, assetId in ipairs(d.moveCars) do
            tx[#tx + 1] = { query = "UPDATE component_asset SET server_id = ? WHERE server_id = ? AND machine_asset_id = ?", values = { archive, base, assetId } }
            tx[#tx + 1] = { query = "UPDATE vehicle_asset SET server_id = ? WHERE server_id = ? AND asset_id = ?", values = { archive, base, assetId } }
            tx[#tx + 1] = { query = "UPDATE vehicle_week_condition SET server_id = ? WHERE server_id = ? AND asset_id = ?", values = { archive, base, assetId } }
        end
        if not keepMoney then
            for _, a in ipairs(d.anchors) do
                tx[#tx + 1] = { query = "UPDATE vehicle_week_condition SET damage_json = NULL, repair_json = NULL, recorded_at = NULL WHERE server_id = ? AND asset_id = ?", values = { base, a.assetId } }
            end
        end
        -- loose parts (not fitted to any machine) are physical inventory: they go with the run
        tx[#tx + 1] = { query = "UPDATE component_asset SET server_id = ? WHERE server_id = ? AND ncm_driver_id = ? AND machine_asset_id IS NULL",
            values = { archive, base, d.driverId } }
        if not keepMoney then
            tx[#tx + 1] = { query = "UPDATE driver_licence SET server_id=? WHERE ncm_driver_id=? AND server_id=?", values = { archive,d.driverId,base } }
            tx[#tx + 1] = { query = "UPDATE driver_rating SET server_id=? WHERE ncm_driver_id=? AND server_id=?", values = { archive,d.driverId,base } }
        end
        if d.srAfter then
            if keepMoney then
                tx[#tx + 1] = { query = "UPDATE driver_sr SET sr = ?, updated_at = ? WHERE ncm_driver_id = ? AND server_id = ?", values = { d.srAfter, t, d.driverId, base } }
            else
                tx[#tx + 1] = { query = "UPDATE driver_sr SET sr = ?, incidents=0, clean_sessions=0, updated_at = ? WHERE ncm_driver_id = ? AND server_id = ?",
                    values = { d.srAfter, t, d.driverId, base } }
            end
        end
        tx[#tx + 1] = { query = [[UPDATE team_affiliation SET effective_to = ?, end_reason = 'reconstruction' WHERE server_id = ?
            AND ncm_driver_id = ? AND circuit = 'npc' AND effective_to IS NULL]], values = { t, base, d.driverId } }
        local ok, err = MySQL.transaction.await(tx)
        if not ok then return false, ("driver %s: %s"):format(d.driverId, tostring(err)) end
        if NcmOwnership and NcmOwnership.forget then pcall(NcmOwnership.forget, d.driverId) end
        Wait(0)
    end
    return true
end

local function record(plan, m, state, result, t)
    pcall(MySQL.update.await, [[INSERT INTO racing_week_collapse (server_id, run_index, mode, state, plan_json, result_json, started_at, finished_at)
        VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, -1)) ON DUPLICATE KEY UPDATE state = VALUES(state), result_json = VALUES(result_json),
        finished_at = VALUES(finished_at), plan_json = VALUES(plan_json)]], { plan.server, plan.run, m, state, enc(plan),
        result and enc(result) or "", t, (state == "done" or state == "failed") and now() or -1 })   -- never a nil in values (KB-168)
end

--- Collapse run `run` in mode `m` ("dryrun" | "live"). Returns true, or nil + reason.
function NcmCollapse.run(run, m, force)
    if busy then return nil, "busy" end
    busy = true
    local ok, a, b = pcall(function()
        local base = sid()
        local done = MySQL.single.await("SELECT state FROM racing_week_collapse WHERE server_id = ? AND run_index = ? AND mode = ?", { base, run, m })
        if done and not force and (done.state == "done" or done.state == "executing") then return nil, "already " .. done.state end
        local t = now()
        if m == "live" then TriggerEvent("ncm:week:collapse.prepare", run) end
        local plan = NcmCollapse.plan(run)
        log("%s PLAN %s", m:upper(), summary(plan))
        for _, d in ipairs(plan.drivers) do
            local keep = {}
            for _, x in ipairs(d.anchors) do keep[#keep + 1] = x.assetId:sub(1, 8) .. "(" .. x.source .. ")" end
            log("  driver %s: wallet %d -> %d, slots %d (day3=%s premier=%s), keep [%s], archive %d car(s), SR %s -> %s%s",
                d.driverId:sub(1, 8), d.balance or 0, d.wallet.open, d.slots, tostring(d.history.day3Finish), tostring(d.history.premierStart),
                table.concat(keep, " "), #d.moveCars, tostring(d.sr), tostring(d.srAfter), #d.refused > 0 and (" refused " .. #d.refused) or "")
        end
        for _, p in ipairs(plan.paddock) do if p.rows > 0 then log("  paddock %-26s %d row(s)", p.table, p.rows) end end
        if m ~= "live" then
            -- a console plan (`force`) only logs: recording it would mark the run's real end-of-run dry run as done
            if not force then record(plan, m, "done", { dryrun = true }, t) end
            return true
        end
        record(plan, m, "executing", nil, t)
        TriggerEvent("ncm:week:collapse.begin", run)
        local okD, why = executeDrivers(plan, t)
        if not okD then TriggerEvent("ncm:week:collapse.abort", run); record(plan, m, "failed", { error = why }, t); log("LIVE collapse FAILED (drivers): %s", why); return nil, why end
        -- the Paddock moves its world and restarts into the historical seed; every called car goes home
        TriggerEvent("ncm:week:collapse.paddock", run, plan.archive)
        TriggerEvent("ncm:week:collapsed", run, plan.archive)
        record(plan, m, "done", { drivers = #plan.drivers }, t)
        log("LIVE collapse of run %d DONE", run)
        return true
    end)
    busy = false
    if not ok then log("collapse error: %s", tostring(a)); return nil, tostring(a) end
    return a, b
end

-- ---------------------------------------------------------------------------------------------------- the watch

CreateThread(function()
    Wait(20000)
    while true do
        local m = mode()
        if m == "dryrun" or m == "live" then
            local okW, err = pcall(function()
                local c, t = cfg(), now()
                local rec = Week.locate(c, timeline(), t)
                local finished = rec and rec.run - 1 or 0
                if finished >= 1 then
                    -- the next run opened where this one ended (recorded, or Day 7 if the world never judged it)
                    local endUtc = (runs[finished] and runs[finished].endUtc) or rec.startUtc
                    if crowned[finished] or t >= endUtc + CROWN_GRACE_S then
                        local row = MySQL.single.await("SELECT state FROM racing_week_collapse WHERE server_id = ? AND run_index = ? AND mode = ?",
                            { sid(), finished, m })
                        if not row then
                            log("run %d has ended%s: collapsing (%s)", finished, crowned[finished] and " and been crowned" or "", m)
                            NcmCollapse.run(finished, m)
                        end
                    end
                end
            end)
            if not okW then log("watch error: %s", tostring(err)) end
        end
        Wait(60000)
    end
end)

RegisterCommand("ncm.week.collapse", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local verb = args and args[1]
    CreateThread(function()
        local at = weekAt(cfg(), now())
        if verb == "plan" then
            -- the CURRENT run, planned as if it had ended now: what the owner reads before choosing live
            local ok, why = NcmCollapse.run(at and at.runIndex or 1, "dryrun", true)
            log("plan: %s", ok and "logged above (not recorded: the run's real dry run still happens at its end)" or tostring(why))
        else
            log("mode %s; current run %s hour %.1f. usage: ncm.week.collapse plan", mode(), tostring(at and at.runIndex), at and at.hours or -1)
        end
    end)
end, false)

-- ---------------------------------------------------------------------------------------------------- the driver's choice

--- `/ncm.anchor` lists your cars and this run's choices; `/ncm.anchor <n>` toggles car n as an anchor.
RegisterCommand("ncm.anchor", function(source, args)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    if not singlePlayer() then
        pcall(Open77.chat.send, pid, "[NCM] Choose your one anchor in Machine Index.")
        return
    end
    CreateThread(function()
        local d = NcmCalendar.resolveDriver(pid)
        if not d then return end
        local base, c = sid(), cfg()
        local at = weekAt(c, now())
        if not at then return end
        local run = at.runIndex
        local cars = carsOf(base, d.ncmDriverId)
        table.sort(cars, function(a, b) return a.assetId < b.assetId end)
        local slots = K.anchorSlots(history(base, d.ncmDriverId, c))
        local chosen = {}
        for _, id in ipairs(chosenFor(base, run, d.ncmDriverId)) do chosen[id] = true end
        local n = tonumber(args and args[1])
        if n and cars[n] then
            local id = cars[n].assetId
            if chosen[id] then
                MySQL.update.await("DELETE FROM racing_week_anchor WHERE server_id = ? AND run_index = ? AND ncm_driver_id = ? AND asset_id = ? AND source = 'chosen'",
                    { base, run, d.ncmDriverId, id })
                chosen[id] = nil
            else
                local count = 0
                for _ in pairs(chosen) do count = count + 1 end
                if count >= slots then
                    pcall(Open77.chat.send, pid, ("[NCM] You can save %d car(s) this Racing Week. Unmark one first."):format(slots))
                    return
                end
                local okA, why = K.anchorable(cars[n])
                if not okA then pcall(Open77.chat.send, pid, "[NCM] That car came from the week itself; it can only be saved if it won a race."); return end
                MySQL.update.await([[INSERT IGNORE INTO racing_week_anchor (server_id, run_index, ncm_driver_id, asset_id, source, chosen_at)
                    VALUES (?, ?, ?, ?, 'chosen', ?)]], { base, run, d.ncmDriverId, id, now() })
                chosen[id] = true
            end
        end
        pcall(Open77.chat.send, pid, ("[NCM] When Racing Week ends, you keep %d car(s). Mark one with /ncm.anchor <n>:"):format(slots))
        for i, car in ipairs(cars) do
            pcall(Open77.chat.send, pid, ("  %d. %s  %d race(s), %.0f km%s"):format(i, tostring(car.record):gsub("^Vehicle%.", ""), car.races,
                (car.odometerM or 0) / 1000, chosen[car.assetId] and "  [SAVED]" or ""))
        end
        if not next(chosen) then pcall(Open77.chat.send, pid, "  (nothing marked: your most-raced car is kept)") end
    end)
end, false)

-- The Machine Index is the Online anchor control. A client supplies only an asset id; title,
-- eligibility and run are read again on the server. Empty id clears an explicit choice and
-- returns to the last-driven default.
local anchorBusy = {}
RegisterNetEvent("ncm:week.anchor.select", function(assetId)
    local pid = tonumber(source) or 0
    if pid <= 0 or anchorBusy[pid] then return end
    anchorBusy[pid] = true
    CreateThread(function()
        local ok, err = pcall(function()
            if singlePlayer() then return end
            local d = NcmCalendar.resolveDriver(pid)
            local at = weekAt(cfg(), now())
            if not d or not at then return end
            local id = tostring(assetId or "")
            if id ~= "" then
                local car
                for _, c in ipairs(carsOf(sid(), d.ncmDriverId)) do if c.assetId == id then car = c; break end end
                if not car or not K.anchorable(car) then return end
            end
            local tx = { { query = "DELETE FROM racing_week_anchor WHERE server_id=? AND run_index=? AND ncm_driver_id=? AND source='chosen'",
                values = { sid(), at.runIndex, d.ncmDriverId } } }
            if id ~= "" then tx[#tx + 1] = { query = [[INSERT INTO racing_week_anchor
                (server_id,run_index,ncm_driver_id,asset_id,source,chosen_at) VALUES (?,?,?,?,'chosen',?)]],
                values = { sid(), at.runIndex, d.ncmDriverId, id, now() } } end
            local committed, why = MySQL.transaction.await(tx)
            if not committed then error(tostring(why)) end
            if NcmCollection and NcmCollection.payload then
                local payload = NcmCollection.payload(pid)
                if payload then NcmStream.send(pid, "ncm:collection", payload, "slots") end
            end
        end)
        anchorBusy[pid] = nil
        if not ok then log("anchor selection failed: %s", tostring(err)) end
    end)
end)

log("ready: collapse mode %s (dryrun until the owner says live)", mode())
