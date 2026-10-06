-- ncm_paddock / server / week -- Racing Week is the Cup; the crown at hour 72; the hall of champions (L303, doc 45 §O).
--
-- THE CUP IS THE RUN. This installs `paddock.season`'s run provider over the recorded timeline (doc 47, L310:
-- `racing_week_run`, written by ncm_world's verdicts, refreshed on `ncm:week:timeline`), so every series' standings
-- span one reconstruction -- however long it lives -- the calendar runs its finales (double points, tier by tier, the
-- Hypercar last) before EVERY possible end, and the Cup boundary crowns everyone at the collapse (L309 Q2).
--
-- MOODY reaches the Paddock here (doc 47 §1.8): `GlobalState.ncmWeekFx` / `ncm:week:fx` carry purses, calendar density
-- and lures per tier. Purses scale race money; calendar density spaces the posted slots; a lure is weighed by EACH
-- driver (week.moody.pull: need from their own or their team's money, boldness, caution, a crash they saw lately) into
-- whether they turn up and how hard they drive once there. Rules and reasons -- never outcomes.
--
-- THE HALL OF CHAMPIONS. "There was ultimately a name to remember at shut down ... those names get etched into the
-- fabric of the lore" (owner). Every crown is written to `racing_week_champion` -- keyed on the server, never on a
-- run's world -- and it outlives every reset: NPC voices and WIRE can name past champions in later weeks, the way
-- 2077 still remembers Johnny Silverhand. Humans are crowned exactly like NPCs: the standings do not care who drove.
PaddockWeek = {}

local U = PaddockUtil
local log = U.logger("week")
local Week = NcmCore.get("week.clock")
local Season = NcmCore.get("paddock.season")
local Mixed = NcmCore.get("paddock.mixed")

local Moody = NcmCore.get("week.moody")
local World = NcmCore.get("paddock.world")

local function cfg() return Week.config(GetConvar or function(_, d) return d end) end

function PaddockWeek.enabled() return PaddockSettings.get("racingWeek", true) == true end

-- the timeline: runIndex -> { endUtc, endKind, survived }. Loaded in a thread (install, a 60 s refresh, the event);
-- the provider only ever reads the cache, so it is safe from any context.
local runs = {}
local function loadRuns()
    local okQ, rows = pcall(MySQL.query.await, "SELECT run_index, end_utc, end_kind, survived FROM racing_week_run WHERE server_id = ?", { U.sid() })
    if okQ and type(rows) == "table" then
        local out = {}
        for _, r in ipairs(rows) do out[tonumber(r.run_index)] = { endUtc = tonumber(r.end_utc), endKind = r.end_kind, survived = tonumber(r.survived) } end
        runs = out
        return true
    end
    return false
end
AddEventHandler("ncm:week:timeline", function(r)
    local out = {}
    for k, v in pairs(r or {}) do
        local n = tonumber(k)
        if n and type(v) == "table" then out[n] = { endUtc = tonumber(v.endUtc), endKind = v.endKind, survived = tonumber(v.survived) } end
    end
    runs = out
end)

--- The provider paddock.season reads: { run, startUtc, endUtc, beyond } for an instant, or nil before the epoch.
--- endUtc is the run's recorded end or, while it is open, its next possible end.
function PaddockWeek.at(utc)
    local rec = Week.locate(cfg(), runs, utc)
    if not rec then return nil end
    return { run = rec.run, startUtc = rec.startUtc, endUtc = rec.endUtc or rec.provisionalEnd, beyond = rec.beyond, open = rec.open }
end

-- ---------------------------------------------------------------------------------------------------- Moody
local fx = nil
local function currentFx()
    if not fx then
        local ok, v = pcall(function() return GlobalState.ncmWeekFx end)
        fx = ok and type(v) == "table" and v or nil
    end
    -- a pinned dev hour rolls a scratch Moody: it never reaches the live Paddock
    if not fx or fx.overridden then return nil end
    return fx
end
AddEventHandler("ncm:week:fx", function(f) if type(f) == "table" then fx = f end end)

local function tierX(field, tier, d) local f = currentFx(); return f and f[field] and tonumber(f[field][tier]) or d end

--- Moody's purse multiplier for a tier (1 without Racing Week or Moody).
function PaddockWeek.purseX(tier) return tierX("purse", tier, 1) end

--- The race rhythm with Moody's calendar density (slot spacing x per tier; never tighter than 10 minutes).
function PaddockWeek.rhythm()
    local f = currentFx()
    if not (f and f.calendar) then return nil end
    local out, changed = {}, false
    for tier, r in pairs(Season.RHYTHM) do
        local x = tonumber(f.calendar[tier]) or 1
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        if x ~= 1 then copy.everySec = math.max(600, math.floor(r.everySec * x)); changed = true end
        out[tier] = copy
    end
    return changed and out or nil
end

-- how badly this driver needs money (0 rich .. 1 broke): their team's cash, or their own as an independent, against
-- the tier's founding range
local function need(person, org, tier)
    local range = World.TIER_CASH[tier] or { 20000, 60000 }
    local cash = tonumber((org and org.cash) or person.cash) or range[1]
    return math.max(0, math.min(1, 1 - cash / (2 * range[2])))
end

-- a crash in a race they were in, in the last day: shaken, fading
local function shaken(person, t)
    local at = tonumber(person.evidence and person.evidence.lastCrashSeenAt)
    if not at or not t or t < at then return 0 end
    return math.max(0, 1 - (t - at) / 86400)
end

local function who(person, org, tier, t)
    local a = person.attrs or {}
    return { aggression = a.aggression, discipline = a.discipline, need = need(person, org, tier), shaken = shaken(person, t) }
end

--- For World.raceField: function(person) -> x on their chance to turn up, or nil when nothing lures.
function PaddockWeek.pull(race)
    local lure = tierX("lure", race.tier, 0)
    if lure <= 0 then return nil end
    local purse = PaddockWeek.purseX(race.tier)
    local w = PaddockStore.world
    return function(person)
        local attend = Moody.pull(lure, purse, who(person, w and w.orgs[person.orgId or ""], race.tier, race.opensAt))
        return attend
    end
end

--- x on one entrant's racing hazard: the bait is driven harder by those it caught.
function PaddockWeek.risk(race, person, org)
    local lure = tierX("lure", race.tier, 0)
    if lure <= 0 or not person then return 1 end
    local _, risk = Moody.pull(lure, PaddockWeek.purseX(race.tier), who(person, org, race.tier, race.opensAt))
    return risk
end

function PaddockWeek.install()
    loadRuns()
    CreateThread(function()
        while true do
            Wait(60000)
            pcall(loadRuns)
        end
    end)
    if PaddockWeek.enabled() then
        Season.setWeek(PaddockWeek.at)
        local now = PaddockWeek.at(U.now())
        log("Racing Week cups ON: run %s, %s -> %s (%s; finales from %d min before every possible end)", tostring(now and now.run),
            tostring(now and now.startUtc), tostring(now and now.endUtc), now and now.open and "open: the next possible end" or "recorded end",
            math.floor(Season.FINALE_CLEAR_S / 60))
    else
        Season.setWeek(nil)
        log("Racing Week cups OFF (setting racingWeek): weekly Cups")
    end
end

--- A standings id's name and team: an NPC from the world, a human from their Paddock entries.
function PaddockWeek.whoIs(id)
    local world = PaddockStore.world
    local p = world and world.people[id]
    if p then return { display = p.display, orgName = PaddockWorld.orgName(p.orgId), personId = p.id, orgId = p.orgId, human = false } end
    if Mixed.isHuman(id) then
        local row = MySQL.single.await("SELECT display, ncm_driver_id FROM paddock_entry WHERE server_id = ? AND person_key = ? ORDER BY entered_at DESC LIMIT 1",
            { U.sid(), id })
        if row then return { display = row.display, orgName = "Privateer", driverId = row.ncm_driver_id, human = true } end
    end
    return nil
end

--- The run a Cup id names ("2026-S4-RW007" -> 7), or nil for a weekly Cup.
function PaddockWeek.runOf(cupId) return tonumber(tostring(cupId or ""):match("%-RW(%d+)$")) end

--- Write one crown and tell everyone. Idempotent per (server, run, series).
function PaddockWeek.crown(run, series, top, who, t)
    pcall(MySQL.update.await, [[INSERT IGNORE INTO racing_week_champion (server_id, run_index, series_id, series_name, tier,
        champion_key, display, org_name, human, ncm_driver_id, points, wins, podiums, starts, crowned_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?)]],
        { U.sid(), run, series.id, series.name, series.tier, top.id, who.display, who.orgName or "", who.human and 1 or 0,
          who.driverId or "", top.points, top.wins, top.podiums, top.starts, t })
    log("CROWNED run %d %s (%s): %s (%s) %d pts, %d wins%s", run, series.name, series.id, who.display, who.orgName or "?",
        top.points, top.wins, who.human and " [HUMAN]" or "")
end

local TIER_RANK = { premier = 1, pro = 2, regional = 3, street = 4 }

--- After the crowns: one ceremony broadcast, biggest title first (the full ceremony UI is doc 45 §O's next piece).
function PaddockWeek.announce(run, crowns)
    table.sort(crowns, function(a, b)
        local ra, rb = TIER_RANK[a.tier] or 9, TIER_RANK[b.tier] or 9
        if ra ~= rb then return ra < rb end
        return a.series < b.series
    end)
    local lines = {}
    for _, c in ipairs(crowns) do lines[#lines + 1] = ("%s: %s (%s)"):format(c.series, c.display, c.org) end
    local head = ("RACING WEEK %d IS OVER. THE CHAMPIONS:"):format(run)
    local ok, all = pcall(Open77.players.all)
    for _, raw in ipairs(ok and all or {}) do
        local pid = tonumber(raw)
        if pid and pid > 0 then
            pcall(Open77.chat.send, pid, "[RACING WEEK] " .. head)
            for _, l in ipairs(lines) do pcall(Open77.chat.send, pid, "  " .. l) end
            pcall(Open77.notifications.send, pid, { type = "info", title = head, message = lines[1] or "", icon = "NCM", durationMs = 15000 })
        end
    end
    TriggerEvent("ncm:week:champions", run, crowns)          -- the ceremony and the collapse listen for this
    TriggerClientEvent("ncm:week:champions", -1, run, crowns)
end

--- The hall: past champions, newest first (for voices, WIRE, the archive). `limit` defaults to 20.
function PaddockWeek.hall(limit, seriesId)
    return MySQL.query.await([[SELECT run_index, series_id, series_name, tier, display, org_name, human, points, wins
        FROM racing_week_champion WHERE server_id = ? AND (? = '' OR series_id = ?) ORDER BY run_index DESC, tier LIMIT ?]],
        { U.sid(), seriesId or "", seriesId or "", limit or 20 }) or {}
end

RegisterCommand("ncm.week.hall", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function()
        local rows = PaddockWeek.hall(40)
        if #rows == 0 then log("the hall of champions is empty") end
        for _, r in ipairs(rows) do
            log("run %s  %-24s %s (%s) %s pts%s", tostring(r.run_index), tostring(r.series_name), tostring(r.display),
                tostring(r.org_name), tostring(r.points), tonumber(r.human) == 1 and " [HUMAN]" or "")
        end
    end)
end, false)

RegisterCommand("ncm.week.cup", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    local cup = Season.cupOf(U.now())
    local wk = Season.weekAt(U.now())
    log("cup %s (run %s) %s -> %s; finales:", tostring(cup.cupId), tostring(cup.run), tostring(cup.cupStartUtc), tostring(cup.cupEndUtc))
    if wk then
        for _, f in ipairs(Season.finaleSlots(wk.endUtc)) do
            log("  %-12s %s  (%d min before the end)", f.seriesId, Season.raceId(f.seriesId, f.utc), math.floor((wk.endUtc - f.utc) / 60))
        end
    end
end, false)

-- ---------------------------------------------------------------------------------------------------- the collapse

--- W-1 (L303): the run's world moves to its archive namespace and the Paddock restarts into the historical seed.
--- Driven by ncm_league's collapse (`ncm:week:collapse.paddock`) in live mode only. One transaction: every run-local
--- `paddock_*` table (week.collapse.paddockMoves -- what the Paddock learned about the physical world stays), NPC-owned
--- cars and parts, NPC money and the Exchange. Nothing is deleted; `<server>#R<run>` keeps the whole week.
local EXTRA = { "npc_money", "exchange_post", "exchange_bid", "exchange_reservation", "exchange_settlement" }

AddEventHandler("ncm:week:collapse.paddock", function(run, archive)
    CreateThread(function()
        local base = U.sid()
        if type(archive) ~= "string" or archive:sub(1, #base + 2) ~= base .. "#R" then log("collapse refused: bad archive key %s", tostring(archive)) return end
        PaddockWeek.collapsing = true
        local tables = {}
        for _, r in ipairs(MySQL.query.await([[SELECT TABLE_NAME AS t FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
            AND COLUMN_NAME = 'server_id']], {}) or {}) do tables[r.t] = true end
        local list = {}
        for _, t in ipairs(NcmCore.get("week.collapse").paddockMoves((function() local o = {} for t in pairs(tables) do o[#o + 1] = t end return o end)())) do list[#list + 1] = t end
        for _, t in ipairs(EXTRA) do if tables[t] then list[#list + 1] = t end end
        local tx = {}
        for _, t in ipairs(list) do
            tx[#tx + 1] = { query = ("UPDATE `%s` SET server_id = ? WHERE server_id = ?"):format(t), values = { archive, base } }
        end
        tx[#tx + 1] = { query = [[UPDATE component_asset SET server_id = ? WHERE server_id = ? AND ncm_driver_id IS NULL
            AND owner_principal_kind IN ('person','org')]], values = { archive, base } }
        tx[#tx + 1] = { query = [[UPDATE vehicle_asset SET server_id = ? WHERE server_id = ? AND ncm_driver_id IS NULL
            AND owner_principal_kind IN ('person','org')]], values = { archive, base } }
        local ok, err = MySQL.transaction.await(tx)
        if not ok then
            PaddockWeek.collapsing = false
            log("COLLAPSE of run %s FAILED, nothing moved: %s", tostring(run), tostring(err))
            return
        end
        log("COLLAPSE run %s: %d table(s) and NPC assets moved to %s; restarting into the historical seed", tostring(run), #list, archive)
        local okR, why = pcall(Open77.resource.restart, GetCurrentResourceName())
        if not okR then log("restart REFUSED (%s): restart ncm_paddock by hand", tostring(why)) end
    end)
end)

-- ---------------------------------------------------------------------------------------------------- the legend

local hallCache, hallAt = nil, 0

--- One past champion for a conversation, deterministic per `key` (person + day), from finished runs only. nil when
--- the hall is empty -- and then no line can name one (the voice bank's truth rule).
function PaddockWeek.pastChampion(key)
    local t = U.now()
    if not hallCache or t - hallAt > 600 then
        local cur = PaddockWeek.at(t)
        local okH, rows = pcall(MySQL.query.await, [[SELECT run_index, series_name, display FROM racing_week_champion
            WHERE server_id = ? AND run_index < ? ORDER BY run_index DESC, tier LIMIT 60]], { U.sid(), cur and cur.run or 0 })
        hallCache, hallAt = (okH and rows) or {}, t
    end
    if #hallCache == 0 then return nil end
    local r = hallCache[1 + NcmCore.get("vocabulary.hash").fnv1a32(tostring(key)) % #hallCache]
    return { champion = r.display, championSeries = r.series_name, championRun = tostring(r.run_index) }
end
