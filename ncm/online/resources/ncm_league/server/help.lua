-- ncm_league / server / help — the NCM Help surface and in-game problem reporting.
--
-- **The server is the support channel** (owner, 2026-09-23). A player who hits a gameplay problem tells NCM
-- from inside NCM. No Discord handle, no GitHub account, no email, and no requirement that the owner is awake.
--
-- This lives in ncm_league rather than ncm_world for one reason: the facts worth capturing are here. Ownership,
-- eligibility refusal, the calendar and the market are all league state, and the single most valuable line in a
-- report -- *why* a race refused somebody -- is `NcmCompetition.carRefusal`, which already computes it. The
-- panel-push pattern is the one `market.lua` and `collection.lua` already use.
--
-- Deliberately NOT here: ticket status, assignment, replies, priorities, a support account system. A player
-- submits, NCM captures, the row persists, a developer reads it later.
NcmHelp = {}

local Core = NcmCore
local Help = Core.get("player.help")
local Json = Core.get("vocabulary.json")
local ids = Core.get("vocabulary.ids")
local hostRng = function() return math.random() end

local function log(fmt, ...) print(("[ncm_league/help] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function serverId() return NcmCalendar.serverId() end
local function tell(pid, text) if pid and pid > 0 then pcall(Open77.chat.send, pid, "[NCM] " .. text) end end

local BUILD = "world 0.5.0 · league 0.3.0"

--- Player-facing notices and recent changes are AUTHORED and OPTIONAL.
---
--- The owner's instruction was exact: *"authorship sounds small until it isnt."* So these start empty, and
--- `player.help` renders nothing at all for an empty list -- no heading, no "nothing to report here", no
--- standing obligation to write release notes for every deploy. Adding an entry is a deliberate act; the
--- absence of entries costs nothing and cannot go stale.
---
--- A notice belongs here only if knowing it helps an ordinary player: recognise a failure, use a workaround,
--- or stop wasting time. Internal defects, migrations and operator-only problems stay in `KNOWN_BUGS.md`,
--- which is never rendered to players.
local NOTICES = {
    -- Load-bearing enough that it cannot stay tribal knowledge (owner, 2026-09-23): two races were driven with
    -- no route line and a third was abandoned. NCM now uses the platform's routable-waypoint recipe and
    -- re-selects the route when you get into the car, which should make this rare -- but "rare" is not "never",
    -- and a player who hits it needs to know the cure is five seconds long and costs them nothing.
    { title = "Route line not showing?",
      text = "Cyberpunk sometimes does not draw the road route straight away after NCM changes your destination. " ..
             "The destination itself is set -- it is the line on the map that is missing.",
      workaround = "Open the map and close it again (M by default). Nothing about your race changes: you stay " ..
                   "entered, your position is unaffected and the clock is not touched." },
}
local CHANGES = {
    -- { title = "...", text = "...", at = "2026-09-23" },
}

--- What this server can honestly advertise right now. A surface that is not loaded is simply absent from Help
--- rather than listed and broken (section 11: do not document hypothetical features).
local function liveCapabilities()
    return {
        market = NcmMarket ~= nil and NcmMarket.payload ~= nil,
        collection = NcmCollection ~= nil,
        guide = NcmGuide ~= nil,
        racing = NcmRace ~= nil and NcmRace.forfeit ~= nil,
    }
end

function NcmHelp.payload(pid)
    return Help.page({
        build = BUILD,
        live = liveCapabilities(),
        notices = NOTICES,
        changes = CHANGES,
        canReport = true,
    })
end

function NcmHelp.push(pid)
    pid = tonumber(pid) or 0
    if pid <= 0 then return end
    local ok, payload = pcall(NcmHelp.payload, pid)
    if not ok then log("payload failed for player=%d: %s", pid, tostring(payload)); return end
    TriggerClientEvent("ncm:help.payload", pid, payload)
end

RegisterNetEvent("ncm:help", function()
    local pid = tonumber(source) or 0
    if pid > 0 then CreateThread(function() NcmHelp.push(pid) end) end
end)

-- ---------------------------------------------------------------------------------------------
-- Report context: FACTS, never conclusions
-- ---------------------------------------------------------------------------------------------

--- Bounded snapshot of what authoritative systems already knew. Every value here was computed by the system
--- that owns it; nothing is inferred and nothing is summarised into a verdict.
---
--- Section 7 is the rule: record `ownership = true, eligibility = false, reason = X` and let a developer draw
--- the conclusion. A snapshot that says "ownership bug caused race rejection" is a guess wearing evidence's
--- clothes, and it will eventually be wrong in a way nobody can check.
local function snapshot(pid, clientCtx)
    local ctx = { build = BUILD, serverId = serverId() }
    local id = tonumber(pid) or 0

    local driver = NcmCalendar and NcmCalendar.resolveDriver and NcmCalendar.resolveDriver(id) or nil
    if driver then ctx.driverId = driver.ncmDriverId end
    ctx.playerName = tostring(GetPlayerName(id) or "")
    ctx.userId = tostring(GetPlayerIdentifier(id) or "")

    local okPos, pos = pcall(Open77.players.position, id)
    if okPos and type(pos) == "table" and pos.x then
        ctx.position = { x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z) }
    end
    local okB, bucket = pcall(Open77.routingBuckets.getPlayer, id)
    if okB then ctx.bucket = tonumber(bucket) end

    -- what the page itself was showing, and whether it had drawn (KB-65's telemetry answers the second)
    if type(clientCtx) == "table" then
        ctx.panel = type(clientCtx.panel) == "string" and clientCtx.panel:sub(1, 24) or nil
        ctx.clientMs = tonumber(clientCtx.ms) or nil
    end

    if driver and NcmOwnership then
        local okOwn, list = pcall(NcmOwnership.list, driver.ncmDriverId)
        local okRec, records = pcall(NcmOwnership.records, driver.ncmDriverId)
        if okOwn and okRec then
            ctx.garage = { examples = #list, models = #records }
        end
    end

    -- The headline case: "I own a car but I cannot race." `carRefusal` already returns the authoritative
    -- reason, so capture it against the soonest event the player could be looking at.
    if driver and NcmGuide and NcmGuide.rows and NcmCompetition then
        local okRows, rows = pcall(NcmGuide.rows, id)
        if okRows and type(rows) == "table" and rows[1] then
            local r = rows[1]
            ctx.event = { eventId = r.eventId, series = r.seriesName, startsAt = r.startsAt, myState = r.myState }
            local e = NcmCalendar.events and NcmCalendar.events[r.eventId] or nil
            if e then
                local okRef, reason, admits = pcall(NcmCompetition.carRefusal, e, driver.ncmDriverId)
                if okRef then
                    ctx.eligibility = { refused = reason ~= nil, reason = reason, admits = admits }
                end
            end
        end
    end

    if driver and NcmMarket and NcmMarket.payload then
        local okM, m = pcall(NcmMarket.payload, id)
        if okM and type(m) == "table" then
            ctx.market = { balance = m.balance, currency = m.currency, offers = m.items and #m.items or nil }
        end
    end
    return ctx
end

-- ---------------------------------------------------------------------------------------------
-- Submission
-- ---------------------------------------------------------------------------------------------

local lastSubmitAt = {}      -- pid -> GetGameTimer(), a courtesy throttle, not a security control

--- `reportId` is generated by the PAGE and reused on retry. That is the whole idempotency story: INSERT IGNORE
--- on the primary key means a retry after a timeout writes nothing and still acknowledges, so a player who
--- presses SUBMIT twice does not create two reports and never sees a false failure.
---
--- Nothing is acknowledged as received until the row is actually there (section 9).
RegisterNetEvent("ncm:report.submit", function(reportId, text, clientCtx)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end

    local function reply(ok, state, detail)
        TriggerClientEvent("ncm:report.result", pid, { ok = ok, state = state, reportId = reportId, detail = detail })
    end

    if type(reportId) ~= "string" or not ids.isUuid(reportId) then
        log("report refused from player=%d: bad id", pid)
        return reply(false, "invalid")
    end

    local clean, why = Help.cleanReport(text)
    if not clean then return reply(false, why or "invalid") end

    local nowMs = GetGameTimer()
    if lastSubmitAt[pid] and (nowMs - lastSubmitAt[pid]) < 3000 then
        return reply(false, "too_fast")
    end
    lastSubmitAt[pid] = nowMs

    CreateThread(function()
        if not MySQL.isReady() then
            -- Honest failure. The page keeps the text and the same report id, so a retry is the same report.
            log("report from player=%d could NOT be stored: database unavailable", pid)
            return reply(false, "unavailable")
        end
        local ctx = snapshot(pid, clientCtx)
        local encoded
        local okEnc, enc = pcall(Json.encode, ctx)
        if okEnc then encoded = enc end

        local okDb = pcall(function()
            MySQL.insert.await(
                "INSERT IGNORE INTO player_report (report_id, server_id, submitted_at, ncm_driver_id, user_id, " ..
                "player_name, player_text, context_json, build) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                { reportId, serverId(), now(), ctx.driverId, ctx.userId, ctx.playerName, clean, encoded, BUILD })
        end)
        if not okDb then
            log("report from player=%d FAILED to persist", pid)
            return reply(false, "unavailable")
        end

        log("REPORT %s player=%d driver=%s panel=%s eligibility=%s: %s",
            reportId:sub(1, 8), pid, tostring(ctx.driverId and ctx.driverId:sub(1, 8) or "none"),
            tostring(ctx.panel or "-"),
            ctx.eligibility and tostring(ctx.eligibility.reason or "ok") or "-",
            clean:sub(1, 160):gsub("\n", " "))
        reply(true, "stored")
        tell(pid, ("Report %s received. Thank you -- it is stored on the server with what NCM knew at the time."):format(reportId:sub(1, 8)))
    end)
end)

-- ---------------------------------------------------------------------------------------------
-- Operator: read reports without leaving the game
-- ---------------------------------------------------------------------------------------------

-- ncm.reports [n] -- the most recent reports. Console only.
RegisterCommand("ncm.reports", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local n = math.max(1, math.min(25, math.floor(tonumber(args and args[1]) or 8)))
    CreateThread(function()
        if not MySQL.isReady() then log("reports: database unavailable"); return end
        local ok, rows = pcall(function()
            return MySQL.query.await(
                "SELECT report_id, submitted_at, player_name, player_text, context_json FROM player_report " ..
                "WHERE server_id = ? ORDER BY submitted_at DESC LIMIT " .. n, { serverId() }) or {}
        end)
        if not ok then log("reports: read failed: %s", tostring(rows)); return end
        if #rows == 0 then log("reports: none yet"); return end
        log("%d most recent report(s):", #rows)
        for _, r in ipairs(rows) do
            log("  %s  %s  %s", tostring(r.report_id):sub(1, 8), tostring(r.player_name or "?"),
                tostring(r.player_text):sub(1, 140):gsub("\n", " "))
            if r.context_json then log("      %s", tostring(r.context_json):sub(1, 320)) end
        end
    end)
end, false)

AddEventHandler("onPlayerDisconnected", function(playerId)
    lastSubmitAt[tonumber(playerId) or 0] = nil
end)

log("help surface ready (build %s; %d notice(s), %d change(s) authored)", BUILD, #NOTICES, #CHANGES)
