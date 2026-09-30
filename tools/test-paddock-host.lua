-- The Paddock's server half (`ncm/online/resources/ncm_paddock`, doc 44) run against deterministic doubles.
--
-- Core rules are proved by ncm/core/tests/test_paddock_*.lua. What is only provable HERE is the host:
--   * genesis, persistence and reload round-trip through the store
--   * a race goes scheduled -> priced -> running -> resolved, and a RUNNING race never shows a result
--   * Billie's lines refuse a human-managed org's drivers; a slip debits once, pays once, and settles idempotently
--   * founding a team takes the fee and the One-Team Rule refuses a second team
--   * withdrawals respect the weekly cap and the tax
--   * no file in ncm_paddock calls another resource's globals (they are separate VMs; ncm-stub would hide it)
--   * the wallet's balance-lock statements are the same shape as economy.lua's
--   * no handler slice runs more VM instructions than the quota headroom allows (KB-211)
local root = arg[1] or "."
local RES = root .. "/ncm/online/resources/"
local passed = 0
local realPrint = print
local logs = {}
local function check(label, value)
    if not value then
        realPrint("  FAIL " .. label)
        for i = math.max(1, #logs - 30), #logs do realPrint("    log| " .. logs[i]) end
        error(label, 0)
    end
    passed = passed + 1
    realPrint("  PASS " .. label)
end

-- ---------------------------------------------------------------- host doubles
local events, queue, replies, commands = {}, {}, {}, {}
function AddEventHandler(name, fn) events[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function CreateThread(fn) queue[#queue + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function TriggerClientEvent(name, pid, body) replies[#replies + 1] = { name = name, pid = pid, body = body } end
function print(s) logs[#logs + 1] = tostring(s) end
function GetPlayerIdentifier(pid) return "user:" .. tostring(pid) end
function GetPlayerName(pid) return "Player" .. tostring(pid) end
function GetPlayers() return { 1, 2 } end
function GetCurrentResourceName() return "ncm_paddock" end

local clock = 1790000000
-- Phases 4-5 doubles: player positions, NPC bodies, vehicles that drive a followRoute at their set speed (so the
-- server's own timing loop sees them cross gates), and the notifications a player would read.
local POS, VEH, NPC, NOTES, aiHandlers = {}, {}, {}, {}, {}
local nextEnt = 5000
STUCK_FROM, STUCK_UNTIL_RESET = nil, false   -- cars from this grid index on stall; until a reset, or for good
GHOSTS = {}
-- open77_remote_camera's server exports, as far as the probe uses them
local CAMS, LEASES = {}, {}
exports = { open77_remote_camera = {
    create = function(_, d) local id = #CAMS + 1; CAMS[id] = d; return { id = id } end,
    setAccess = function() return true end,
    acquire = function(_, pid, cam) LEASES[#LEASES + 1] = { pid = pid, cam = cam }; return #LEASES end,
    release = function(_, lease) LEASES[lease] = nil; return true end,
    remove = function(_, id) CAMS[id] = nil; return true end,
    openView = function(_, pid, cam) return "view" .. cam end,
    closeView = function() return true end,
} }
local function vdist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
local function advance(v)
    if v.route and v.t then v.dist = v.dist + (v.speed or 0) * (clock - v.t); v.t = clock end
end
local function polyAt(pts, d)
    for i = 2, #pts do
        local seg = vdist(pts[i - 1], pts[i])
        if d <= seg and seg > 0 then
            local f = d / seg
            return { x = pts[i - 1].x + (pts[i].x - pts[i - 1].x) * f, y = pts[i - 1].y + (pts[i].y - pts[i - 1].y) * f, z = 10 }
        end
        d = d - seg
    end
    local a, b = pts[#pts - 1], pts[#pts]
    local seg = vdist(a, b)
    return { x = b.x + (b.x - a.x) / seg * d, y = b.y + (b.y - a.y) / seg * d, z = 10 }     -- carry on past the end
end
Open77 = {
    time = { unix = function() return clock end },
    tunables = { declare = function(spec) local p = {} for k, v in pairs(spec) do p[k] = v.value end return p end },
    notifications = { send = function(pid, n) NOTES[#NOTES + 1] = { pid = pid, title = n.title, message = n.message } return true end },
    players = { positions = function() return POS end },
    world = { groundZ = function(p, o) return (o.fromZ or 1.5) - 1.5 end },
    npcs = {
        ai = { tasks = 1 }, damage = { invulnerable = 2 },
        create = function(def) nextEnt = nextEnt + 1; NPC[nextEnt] = { position = def.position, record = def.record } return nextEnt end,
        remove = function(id) NPC[id] = nil return true end,
        get = function(id) return NPC[id] end,
        speak = function() return true end,
        tasks = { lookAt = function() return true end },
    },
    vehicles = {
        create = function(def)
            nextEnt = nextEnt + 1
            local count = 0
            for _ in pairs(VEH) do count = count + 1 end
            VEH[nextEnt] = { pos = def.position, record = def.record, health = 1, dist = 0, stall = STUCK_FROM ~= nil and count >= STUCK_FROM,
                stuckUntilReset = STUCK_UNTIL_RESET }
            return nextEnt
        end,
        remove = function(id) VEH[id] = nil return true end,
        getPosition = function(id)
            local v = VEH[id]
            if not v then return nil end
            if v.route then advance(v); return polyAt(v.route, v.dist) end
            return v.pos
        end,
        getHealth = function(id) return VEH[id] and VEH[id].health end,
        setTransform = function(id, tr)
            local v = VEH[id]
            if not v then return false end
            v.pos, v.route, v.dist, v.t = tr.position, nil, 0, nil
            if v.stuckUntilReset then v.stall = false end
            return true
        end,
        owner = function(id) return VEH[id] and { kind = "stub" } or nil end,
        requestAuthority = function() return true end,
        ai = {
            on = function(ev, fn) aiHandlers[ev] = fn return true end,
            attachDriver = function(id, o) if not VEH[id] then return nil, "no_vehicle" end VEH[id].driver = o and o.npcId or "none" return { status = "idle" } end,
            followRoute = function(id, o)
                local v = VEH[id]
                if not v or not v.driver then return nil, "no_controller" end
                if #o.points < 1 or #o.points > 64 then return nil, "invalid_points" end
                if v.route then advance(v); v.pos = polyAt(v.route, v.dist) end     -- a re-send starts where the car IS
                v.route = { v.pos }
                for _, p in ipairs(o.points) do v.route[#v.route + 1] = p end
                v.speed, v.t, v.dist = v.stall and 0 or o.speed, clock, 0
                return { status = "running" }
            end,
            setSpeed = function(id, sp) local v = VEH[id] if v then advance(v); v.speed = v.stall and 0 or sp end return {} end,
            removeDriver = function(id) if VEH[id] then VEH[id].driver = nil end return true end,
            stop = function() return true end,
            state = function(id) return VEH[id] and { status = VEH[id].route and "running" or "idle" } or nil end,
            driveTo = function(id, o)
                local v = VEH[id]
                if not v or not v.driver then return nil, "no_controller" end
                v.route, v.speed, v.t, v.dist = { v.pos, o.position }, v.stall and 0 or o.speed, clock, 0
                return { status = "running" }
            end,
        },
    },
}

-- Instruction metering: the most VM instructions any coroutine ran between two yields.
local maxSlice, slice = 0, 0
local function hook() slice = slice + 1000 end
local function resumeMetered(co)
    slice = 0
    debug.sethook(co, hook, "", 1000)
    local ok, err = coroutine.resume(co)
    if slice > maxSlice then maxSlice = slice end
    return ok, err
end

local function drain(limit, untilFn)
    local guard = 0
    while #queue > 0 and guard < (limit or 200000) and not (untilFn and untilFn()) do
        guard = guard + 1
        local co = table.remove(queue, 1)
        local ok, err = resumeMetered(co)
        assert(ok, err)
        if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end
    end
end

local function run(fn)
    local co = coroutine.create(fn)
    local ok, err = resumeMetered(co)
    assert(ok, err)
    while coroutine.status(co) ~= "dead" do
        ok, err = resumeMetered(co)
        assert(ok, err)
    end
end

local function fire(name, pid, ...)
    source = pid
    local args = { ... }
    run(function() events[name]((table.unpack or unpack)(args)) end)
    drain()
end

-- ---------------------------------------------------------------- a database double for the Paddock tables
local DB = {
    world = nil, series = {}, org = {}, person = {}, sponsor = {}, race = {}, result = {}, line = {}, slip = {},
    ledger = {}, idem = {}, affiliation = {}, treasury = {}, tidem = {}, event = {}, news = {}, message = {}, push = {},
    contact = { ["driver-1"] = true, ["driver-2"] = true },
    live = {}, crossing = {}, meeting = {}, garageCheck = {},
}
local function ledgerTotal(d) local s = 0 for _, r in ipairs(DB.ledger) do if r.d == d then s = s + r.amount end end return s end
local function ledgerAdd(d, kind, amount, idem)
    if idem and DB.idem[idem] then return false end
    if idem then DB.idem[idem] = true end
    DB.ledger[#DB.ledger + 1] = { d = d, kind = kind, amount = amount, idem = idem }
    return true
end
local function activeAff(d) for _, a in ipairs(DB.affiliation) do if a.d == d and not a.to then return a end end end
local function has(q, s) return q:find(s, 1, true) ~= nil end

local function exec(q, v)
    v = v or {}
    -- Sentinels mirror the SQL: a `NULLIF(?, -1)` / `NULLIF(?, '')` column stores NULL, so the double stores nil.
    if has(q, "INTO paddock_world") then
        DB.world = { server_id = v[1], seed = v[2], genesis_version = v[3], genesis_season = v[4], season_id = v[5],
            season_ordinal = v[6], paddock_year = v[7], day_index_applied = v[8] ~= -1 and v[8] or nil, cup_id = v[9] ~= "" and v[9] or nil, counters_json = v[10], created_at = v[11] }
    elseif has(q, "INTO paddock_series") then
        DB.series[v[2]] = { series_id = v[2], tier = v[3], division = v[4], name = v[5] }
    elseif has(q, "INTO paddock_org") then
        local keys = { "server_id", "org_id", "tier", "series_id", "name", "short", "colour", "prestige", "cash", "facility", "car_json",
            "owner_person_id", "manager_person_id", "engineer_person_id", "strategist_person_id", "sponsor_ids", "human_manager_driver_id",
            "origin", "lifecycle", "founded_season", "seasons_active", "red_days", "low_cash_days", "evidence_json", "pending_json", "folded_at",
            "garage_id", "garage_shift" }
        local r = {}
        for i, k in ipairs(keys) do r[k] = v[i] end
        for _, k in ipairs({ "owner_person_id", "manager_person_id", "engineer_person_id", "strategist_person_id", "human_manager_driver_id",
            "garage_id", "garage_shift" }) do
            if r[k] == "" then r[k] = nil end
        end
        DB.org[r.org_id] = r
    elseif has(q, "INTO paddock_person") then
        local keys = { "server_id", "person_id", "role", "org_id", "seat", "first", "last", "display", "region", "gender", "birth_year",
            "attrs_json", "personality_json", "principal_json", "morale", "state", "wage", "contract_ends", "evidence_json" }
        local r = {}
        for i, k in ipairs(keys) do r[k] = v[i] end
        if r.org_id == "" then r.org_id = nil end
        if r.seat == "" then r.seat = nil end
        DB.person[r.person_id] = r
    elseif has(q, "INTO paddock_sponsor") then
        DB.sponsor[v[2]] = { sponsor_id = v[2], name = v[3], short = v[4], industry = v[5], tier = v[6], personality_json = v[7],
            org_id = v[8] ~= "" and v[8] or nil, per_day = v[9] }
    elseif has(q, "INSERT IGNORE INTO paddock_race") then
        if not DB.race[v[2]] then
            DB.race[v[2]] = { race_id = v[2], series_id = v[3], tier = v[4], season_id = v[5], cup_id = v[6], route_id = v[7],
                window_opens_at = v[8], state = "scheduled", seed = v[9], seed_commit = v[10] }
        end
    elseif has(q, "UPDATE paddock_race SET state = 'running'") then
        local r = DB.race[v[11]]
        r.state, r.window_closes_at, r.detail_json = "running", v[1], v[9]
        r.weather, r.road_wetness, r.light = v[2] ~= "" and v[2] or nil, v[3] ~= -1 and v[3] or nil, v[5] ~= "" and v[5] or nil
    elseif has(q, "UPDATE paddock_race SET state = 'priced'") then
        local r = DB.race[v[2]]
        if r and r.state == "scheduled" then r.state = "priced" end
    elseif has(q, "UPDATE paddock_race SET state = 'resolved'") then
        DB.race[v[3]].state = "resolved"
    elseif has(q, "UPDATE paddock_race SET detail_json") then
        if DB.race[v[3]] then DB.race[v[3]].detail_json = v[1] end
    elseif has(q, "DELETE FROM paddock_result") then
        local keep = {}
        for _, r in ipairs(DB.result) do if r.race_id ~= v[2] then keep[#keep + 1] = r end end
        DB.result = keep
    elseif has(q, "UPDATE paddock_race SET provenance = ?") then
        local r = DB.race[v[6]]
        if r then r.provenance, r.backend, r.detail_json, r.window_closes_at = v[1], v[2], v[3], v[4] end
    elseif has(q, "INTO paddock_live_crossing") then
        DB.crossing[#DB.crossing + 1] = { race_id = v[2], person_id = v[3], gate = v[4], source = has(q, "'pace'") and "pace" or "server", t_ms = v[5] }
    elseif has(q, "INSERT INTO paddock_live") then
        if DB.live[v[2]] then error("Duplicate entry for key 'PRIMARY'") end
        DB.live[v[2]] = { race_id = v[2], declared_by = v[3], state = "declared", cars = v[5] }
    elseif has(q, "UPDATE paddock_live SET") and has(q, "server restarted") then
        for _, l in pairs(DB.live) do if l.state ~= "finished" then l.state = "cancelled" end end
    elseif has(q, "UPDATE paddock_live SET") then
        local cols = {}
        for c in q:match("SET (.-) WHERE"):gmatch("([%w_]+) = %?") do cols[#cols + 1] = c end
        local row = DB.live[v[#v]]
        if row then for i, c in ipairs(cols) do row[c] = v[i] end end
    elseif has(q, "INTO paddock_meeting") then
        local k = v[2] .. "|" .. v[3]
        if DB.meeting[k] then DB.meeting[k].met_count = DB.meeting[k].met_count + 1 else DB.meeting[k] = { met_count = 1 } end
    elseif has(q, "INTO paddock_garage_check") then
        DB.garageCheck[v[2]] = { site_id = v[2], verdict = v[3] }
    elseif has(q, "INTO paddock_result") then
        DB.result[#DB.result + 1] = { race_id = v[2], person_id = v[3], org_id = v[4], series_id = v[5], season_id = v[6], cup_id = v[7],
            position = v[8], grid = v[9], state = v[10], finish_ms = v[11] ~= -1 and v[11] or nil, gap_ms = v[12] ~= -1 and v[12] or nil, points = v[13], purse = v[14], dnf_reason = v[15] }
    elseif has(q, "INTO paddock_line") then
        DB.line[v[2]] = { line_id = v[2], race_id = v[3], market = v[4], subject_a = v[5], subject_b = v[6] ~= "" and v[6] or nil,
            prob = v[7], price = v[8] ~= -1 and v[8] or nil, version = 1, refused = v[9], state = v[10] }
    elseif has(q, "UPDATE paddock_line SET state = 'closed'") then
        for _, l in pairs(DB.line) do if l.race_id == v[2] and (l.state == "open" or l.state == "suspended") then l.state = "closed" end end
    elseif has(q, "UPDATE paddock_line SET state = 'settled'") then
        for _, l in pairs(DB.line) do if l.race_id == v[2] then l.state = "settled" end end
    elseif has(q, "INSERT IGNORE INTO ledger") and has(q, "WHERE (SELECT COALESCE(SUM(amount),0)") then
        if ledgerTotal(v[1]) >= v[10] then ledgerAdd(v[1], v[3], v[4], v[7]) end
    elseif has(q, "INSERT IGNORE INTO ledger") then
        ledgerAdd(v[1], v[3], v[4], v[7])
    elseif has(q, "INTO paddock_slip") then
        if DB.idem[v[15]] then
            DB.slip[v[1]] = { slip_id = v[1], idem_key = v[2], ncm_driver_id = v[4], race_id = v[5], line_id = v[6], market = v[7],
                subject_a = v[8], subject_b = v[9] ~= "" and v[9] or nil, line_version = v[10], stake = v[11], price = v[12], potential = v[13], placed_at = v[14],
                state = "open", payout = 0 }
        end
    elseif has(q, "UPDATE paddock_slip SET state") then
        local s = DB.slip[v[4]]
        if s and s.state == "open" then s.state, s.payout = v[1], v[2] end
    elseif has(q, "INTO team_affiliation") and has(q, "WHERE EXISTS") then
        if DB.idem[v[6]] then
            if activeAff(v[3]) then error("Duplicate entry for key 'ux_one_team'") end
            DB.affiliation[#DB.affiliation + 1] = { d = v[3], org = v[4], circuit = "npc", role = "manager" }
        end
    elseif has(q, "INTO team_affiliation") then
        if activeAff(v[3]) then error("Duplicate entry for key 'ux_one_team'") end
        DB.affiliation[#DB.affiliation + 1] = { d = v[3], org = v[4], circuit = "npc", role = "manager" }
    elseif has(q, "UPDATE team_affiliation SET effective_to") then
        for _, a in ipairs(DB.affiliation) do if a.d == v[4] and not a.to then a.to = v[1] end end
    elseif has(q, "INTO paddock_treasury") then
        local idem = has(q, "'withdrawal'") and v[4] or (has(q, "'deposit'") and v[4] or v[5])
        if not DB.tidem[idem] then
            DB.tidem[idem] = true
            local kind = has(q, "'withdrawal'") and "withdrawal" or (has(q, "'deposit'") and "deposit" or v[3])
            local amount = has(q, "'withdrawal'") and v[3] or (has(q, "'deposit'") and v[3] or v[4])
            DB.treasury[#DB.treasury + 1] = { org = v[2], kind = kind, amount = amount, at = clock }
        end
    elseif has(q, "INTO paddock_event") then
        DB.event[v[2]] = { event_id = v[2], kind = v[5], facts = v[9] }
    elseif has(q, "INTO paddock_news") then
        DB.news[v[2]] = { story_id = v[2], at = v[4], kind = v[5], headline = v[7], body = v[8], prominence = v[9] }
    elseif has(q, "INTO message") then
        DB.message[#DB.message + 1] = { to = v[3], subject = v[6] }
    end
    return 1
end

MySQL = {
    isReady = function() return true end,
    transaction = { await = function(list)
        for _, st in ipairs(list) do
            local ok, err = pcall(exec, st.query, st.values)
            if not ok then return false, err end
        end
        return true
    end },
    update = { await = function(q, v) return exec(q, v) end },
    insert = { await = function(q, v) return exec(q, v) end },
    scalar = { await = function(q, v)
        if has(q, "MAX(version) FROM schema_migrations") then return 52 end
        if has(q, "FROM ncm_driver_binding") then return 2 end
        if has(q, "SUM(amount),0) FROM ledger") then return ledgerTotal(v[1]) end
        if has(q, "COUNT(*) FROM ledger WHERE idem_key") then return DB.idem[v[1]] and 1 or 0 end
        if has(q, "SUM(stake)") then local s = 0 for _, x in pairs(DB.slip) do if x.ncm_driver_id == v[2] then s = s + x.stake end end return s end
        if has(q, "SELECT price FROM paddock_line") then return DB.line[v[2]] and DB.line[v[2]].price end
        if has(q, "kind = 'withdrawal'") then local s = 0 for _, t in ipairs(DB.treasury) do if t.org == v[2] and t.kind == "withdrawal" then s = s + t.amount end end return s end
        if has(q, "SELECT count FROM paddock_push") then return 0 end
        if has(q, "SELECT display FROM driver_profile") then return "Human " .. tostring(v[1]) end
        if has(q, "SELECT detail_json FROM paddock_race") then return DB.race[v[2]] and DB.race[v[2]].detail_json end
        if has(q, "FROM paddock_meeting") then local m = DB.meeting[v[2] .. "|" .. v[3]] return m and m.met_count end
        return 0
    end },
    single = { await = function(q, v)
        if has(q, "FROM paddock_world") then return DB.world end
        if has(q, "FROM ncm_driver_binding") then return { ncm_driver_id = "driver-" .. tostring(v[2]):match("(%d+)$"), display = "Human" } end
        if has(q, "FROM player_contact") then return DB.contact[v[1]] and { state = "known" } or nil end
        if has(q, "FROM paddock_line WHERE server_id = ? AND line_id") then return DB.line[v[2]] end
        if has(q, "FROM paddock_slip WHERE idem_key") then for _, s in pairs(DB.slip) do if s.idem_key == v[1] then return s end end return nil end
        if has(q, "FROM team_affiliation") then local a = activeAff(v[2]) return a and { circuit = a.circuit, role = a.role } or nil end
        if has(q, "FROM paddock_race WHERE server_id = ? AND race_id") then return DB.race[v[2]] end
        if has(q, "FROM ghost_lap") then return GHOSTS[v[2]] end
        return nil
    end },
    query = { await = function(q, v)
        local out = {}
        if has(q, "FROM paddock_series") then for _, r in pairs(DB.series) do out[#out + 1] = r end
        elseif has(q, "FROM paddock_org") then for _, r in pairs(DB.org) do out[#out + 1] = r end table.sort(out, function(a, b) return a.org_id < b.org_id end)
        elseif has(q, "FROM paddock_person") then for _, r in pairs(DB.person) do out[#out + 1] = r end table.sort(out, function(a, b) return a.person_id < b.person_id end)
        elseif has(q, "FROM paddock_sponsor") then for _, r in pairs(DB.sponsor) do out[#out + 1] = r end table.sort(out, function(a, b) return a.sponsor_id < b.sponsor_id end)
        elseif has(q, "FROM paddock_garage_check") then
            for _, r in pairs(DB.garageCheck) do out[#out + 1] = r end
        elseif has(q, "FROM weather_transition") then
            out = { { starts_at_utc = clock - 7200, weather = "sunny" }, { starts_at_utc = clock + 86400 * 3, weather = "rain" } }
        elseif has(q, "FROM paddock_result WHERE server_id = ? AND race_id") then
            for _, r in ipairs(DB.result) do if r.race_id == v[2] then out[#out + 1] = r end end
            table.sort(out, function(a, b) return a.position < b.position end)
        elseif has(q, "FROM paddock_slip WHERE server_id = ? AND race_id") then
            for _, s in pairs(DB.slip) do if s.race_id == v[2] and s.state == "open" then out[#out + 1] = s end end
        elseif has(q, "FROM paddock_line WHERE server_id = ? AND race_id") then
            for _, l in pairs(DB.line) do if l.race_id == v[2] then out[#out + 1] = l end end
        elseif has(q, "FROM paddock_news") then
            for _, n in pairs(DB.news) do if n.prominence >= v[2] then out[#out + 1] = n end end
        elseif has(q, "FROM paddock_race r LEFT JOIN paddock_result") then
            for _, r in pairs(DB.race) do
                if r.state == "resolved" then
                    local winner
                    for _, x in ipairs(DB.result) do if x.race_id == r.race_id and x.position == 1 then winner = x end end
                    out[#out + 1] = { race_id = r.race_id, series_id = r.series_id, route_id = r.route_id, window_opens_at = r.window_opens_at,
                        weather = r.weather, light = r.light, road_wetness = r.road_wetness, provenance = "simulated", seed_commit = r.seed_commit,
                        winner = winner and winner.person_id, winner_org = winner and winner.org_id }
                end
            end
        elseif has(q, "GROUP BY") and has(q, "FROM paddock_result") then
            local col = has(q, "org_id AS id") and "org_id" or "person_id"
            local by, list = {}, {}
            for _, r in ipairs(DB.result) do
                if r.season_id == v[2] and r.series_id == v[3] then
                    local id = r[col]
                    local s = by[id]
                    if not s then s = { id = id, points = 0, wins = 0, podiums = 0, starts = 0, dnfs = 0, best = 99 }; by[id] = s; list[#list + 1] = s end
                    s.points = s.points + r.points; s.starts = s.starts + 1
                    if r.state == "finished" then
                        if r.position == 1 then s.wins = s.wins + 1 end
                        if r.position <= 3 then s.podiums = s.podiums + 1 end
                    else s.dnfs = s.dnfs + 1 end
                end
            end
            table.sort(list, function(a, b) if a.points ~= b.points then return a.points > b.points end return a.id < b.id end)
            out = list
        end
        return out
    end },
}

-- Host fidelity: the real runtime refuses a nil inside `values` with a bare `invalid_parameters` throw
-- (`open77/runtime.lua:351`). This stub used to accept it, so genesis passed here and died on the first real
-- boot (2026-09-29, `paddock_world.day_index_applied`). Every call now counts `?` against its values first.
local function refuseHoles(q, v)
    if type(q) ~= "string" then return end
    local _, want = q:gsub("%?", "")
    v = v or {}
    for k = 1, want do
        if v[k] == nil then
            error(("invalid_parameters: value %d of %d is nil in %s"):format(k, want, (q:gsub("%s+", " ")):sub(1, 90)), 2)
        end
    end
end
for _, ns in pairs(MySQL) do
    if type(ns) == "table" and type(ns.await) == "function" then
        local inner = ns.await
        ns.await = function(q, v)
            if type(q) == "table" then for _, st in ipairs(q) do refuseHoles(st.query, st.values) end
            else refuseHoles(q, v) end
            return inner(q, v)
        end
    end
end

-- ---------------------------------------------------------------- load the resource the way the host does
local function loadResource(name)
    NcmCore = nil
    local text = assert(io.open(RES .. name .. "/open77.lua")):read("a")
    for kind, path in text:gmatch('(%w+_script)%s+"([^"]+)"') do
        if kind ~= "client_script" then assert(loadfile(RES .. name .. "/" .. path))() end
    end
end
math.randomseed(7)
loadResource("ncm_paddock")

realPrint("paddock host harness")

-- ---------------------------------------------------------------- static checks
do
    local offenders = {}
    for _, f in ipairs({ "settings", "util", "store", "players", "stream", "wallet", "story", "world", "calibration", "races",
        "billie", "life", "manager", "spotlight", "garages", "live", "probe", "bubble", "views", "requests", "admin", "main" }) do
        local text = assert(io.open(RES .. "ncm_paddock/server/" .. f .. ".lua")):read("a")
        text = text:gsub("%-%-[^\n]*", "")   -- code only: comments may name the resource they mirror
        for g in text:gmatch("(Ncm%u%a+)%.") do
            if g ~= "NcmCore" then offenders[#offenders + 1] = f .. ":" .. g end
        end
    end
    check("no ncm_paddock file calls another resource's globals (" .. table.concat(offenders, ",") .. ")", #offenders == 0)
    local econ = assert(io.open(RES .. "ncm_league/server/economy.lua")):read("a")
    check("the wallet's balance-lock INSERT matches economy.lua", has(econ, "INSERT IGNORE INTO economy_balance_lock (server_id,ncm_driver_id,revision) VALUES (?,?,0)"))
    check("the wallet's balance-lock UPDATE matches economy.lua", has(econ, "UPDATE economy_balance_lock SET revision=revision+1 WHERE server_id=? AND ncm_driver_id=?"))
    local lockTx = PaddockWallet.withBalanceLocks({}, { "b", "a", "a" })
    check("locks are deduplicated and sorted like economy.lua", #lockTx == 4 and lockTx[1].values[2] == "a" and lockTx[2].values[2] == "b")
end

-- ---------------------------------------------------------------- boot: genesis
-- boot runs inside the resource's forever-loop thread: drive it until the world is ready, then drop it (the
-- harness calls the scheduler's pieces itself so each step can be asserted)
drain(400000, function() return PaddockWorld.ready and PaddockStore.world ~= nil and next(DB.news) ~= nil end)
queue = {}
check("genesis ran and the world is ready", PaddockWorld.ready and PaddockStore.world ~= nil)
-- the scheduler's first tick opens the world's first Cup; boot yields between steps, so the harness may have dropped
-- the boot thread before that tick ran -- run it here rather than depend on where the drop landed
if not PaddockStore.world.cupId then run(function() PaddockLife.cupBoundary(clock) end) end
local W = PaddockStore.world
check("60 organizations and their people exist", #W.orgOrder == 60 and #W.personOrder > 400)
local persisted = 0
for _ in pairs(DB.org) do persisted = persisted + 1 end
check("every org was persisted", persisted == 60)
check("genesis wrote a founding story", next(DB.news) ~= nil)

-- reload round-trip: the store reads back what it wrote
do
    local copy = PaddockStore.load and nil
    run(function() PaddockStore.flush(); copy = PaddockStore.load() end)
    check("reloaded world has the same orgs and names", copy and #copy.orgOrder == 60 and copy.orgs.o001.name == W.orgs.o001.name
        and copy.people.p00001.display == W.people.p00001.display and copy.seed == W.seed)
    local did
    for _, pid in ipairs(W.personOrder) do if W.people[pid].role == "driver" then did = pid break end end
    check("hidden attributes survive the round trip (" .. did .. ")", copy.people[did].attrs and math.abs(copy.people[did].attrs.pace - W.people[did].attrs.pace) < 0.001)
end

-- ---------------------------------------------------------------- a race's life
local Season = NcmCore.get("paddock.season")
local Clock = NcmCore.get("world.clock")
-- 14:50 Eastern: the Premier feature at 15:00 is ten minutes out, inside Billie's window
local day = Clock.eastern(clock).dayIndex
clock = Clock.utcAt(day, 14 * 3600 + 50 * 60)
local premierId = Season.raceId("premier", Clock.utcAt(day, 15 * 3600))
W.orgs.o061 = nil
-- make one premier org human-managed so Billie must refuse its drivers
local humanOrg
for _, oid in ipairs(W.orgOrder) do if W.orgs[oid].seriesId == "premier" then humanOrg = W.orgs[oid]; break end end
humanOrg.humanManagerDriverId = "driver-9"
run(function() PaddockRaces.materialise(clock) end)
check("the Premier feature was materialised", PaddockRaces.byId[premierId] ~= nil and DB.race[premierId] ~= nil)
local race = PaddockRaces.byId[premierId]
check("a race is committed to a seed before it opens", #race.commit == 8 and DB.race[premierId].seed_commit == race.commit)

maxSlice = 0
local t0 = os.clock()
run(function() PaddockBillie.price(race) end)
local pricingSec = os.clock() - t0
check(("pricing one race takes under 1.5 s (%.2f s)"):format(pricingSec), pricingSec < 1.5)
check(("no pricing slice exceeds 400k VM instructions (max %d)"):format(maxSlice), maxSlice < 400000)
check("the race is on the board", race.state == "priced" and DB.race[premierId].state == "priced")
local lines, refused, open = 0, 0, 0
for _, l in pairs(DB.line) do
    if l.race_id == premierId then
        lines = lines + 1
        local p = W.people[l.subject_a]
        if p.orgId == humanOrg.id then check("a human-managed driver's line is refused: " .. l.line_id, l.refused == 1 and l.price == nil) end
        if l.refused == 1 then refused = refused + 1 end
        if l.state == "open" then open = open + 1 end
    end
end
check("win, podium and head-to-head lines were written", lines > 20 and open > 10 and refused >= 4)

-- a slip on an NPC-run favourite
DB.ledger = {}; DB.idem = {}
ledgerAdd("driver-1", "starter", 1000, "seed:1")
local line
for _, l in pairs(DB.line) do
    if l.race_id == premierId and l.market == "win" and l.state == "open" and (not line or l.price < line.price) then line = l end
end
fire("ncm:paddock.slip", 1, { lineId = line.line_id, version = 1, stake = 100, idem = "abc" })
local slipCount = 0
for _ in pairs(DB.slip) do slipCount = slipCount + 1 end
check("a slip was written and the stake debited", slipCount == 1 and ledgerTotal("driver-1") == 900)
fire("ncm:paddock.slip", 1, { lineId = line.line_id, version = 1, stake = 100, idem = "abc" })
local slipCount2 = 0
for _ in pairs(DB.slip) do slipCount2 = slipCount2 + 1 end
check("the same slip twice is one slip and one debit", slipCount2 == 1 and ledgerTotal("driver-1") == 900)
clock = clock + 1
fire("ncm:paddock.slip", 1, { lineId = line.line_id, version = 1, stake = 5000, idem = "big" })
check("over the slip cap is refused", ledgerTotal("driver-1") == 900)
local refusedLine
for _, l in pairs(DB.line) do if l.race_id == premierId and l.refused == 1 then refusedLine = l end end
clock = clock + 1
fire("ncm:paddock.slip", 1, { lineId = refusedLine.line_id, version = 1, stake = 50, idem = "ref" })
check("a slip on a refused line is refused", ledgerTotal("driver-1") == 900)
local lastResult
for _, r in ipairs(replies) do if r.name == "ncm:paddock.result" then lastResult = r.body end end
check("Billie answered in her own words", lastResult and not lastResult.ok and lastResult.text == PaddockBillie.REFUSAL)

-- the window opens: the sim runs, but the result is sealed
clock = race.opensAt
maxSlice = 0
-- one run per tick by design (a backlog drains across ticks); other series open at 15:00 too
for _ = 1, 6 do
    if race.state == "running" then break end
    run(function() PaddockRaces.tick(clock) end)
end
check("the race is running with results stored", race.state == "running" and #DB.result > 0)
check(("a race run fits one slice (max %d instructions)"):format(maxSlice), maxSlice < 400000)
local box
run(function() box = PaddockViews.box(1, { raceId = premierId }) end)
check("a RUNNING race never shows its result", box.error == "not_resolved" and #box.rows == 0)
local liveV
run(function() liveV = PaddockViews.live(1, {}) end)
check("LIVE shows the running race from its continuous model", liveV.raceId ~= nil and #liveV.rows >= 8 and liveV.street == nil
    and liveV.rows[1].pos == 1)
local res
run(function() res = PaddockViews.results(1, {}) end)
local leaked = false
for _, r in ipairs(res.rows) do if r.raceId == premierId then leaked = true end end
check("and is not in RESULTS", not leaked)
local lineClosed = true
for _, l in pairs(DB.line) do if l.race_id == premierId and l.state == "open" then lineClosed = false end end
check("the board closed when the window opened", lineClosed)

-- the window closes: public, settled
clock = race.closesAt + 1
for _ = 1, 8 do
    if race.state == "resolved" then break end
    run(function() PaddockRaces.tick(clock) end)
end
check("the race resolved", DB.race[premierId].state == "resolved")
local slip = next(DB.slip) and DB.slip[next(DB.slip)]
check("the slip settled", slip.state == "won" or slip.state == "lost")
local after = ledgerTotal("driver-1")
check("a winning slip pays stake times price, a losing one pays nothing",
    (slip.state == "won" and after == 900 + math.floor(100 * slip.price)) or (slip.state == "lost" and after == 900))
run(function() PaddockBillie.settle(race, {}) end)
check("settling again pays nothing more", ledgerTotal("driver-1") == after)
run(function() box = PaddockViews.box(1, { raceId = premierId }) end)
check("the box score is public now", #box.rows > 0 and box.rows[1].pos == 1)
local story = false
for _, e in pairs(DB.event) do if e.event_id == "race_result:" .. premierId then story = true end end
check("the result is on the tape", story)

-- every view passes the hidden-key guard, inside the quota
maxSlice = 0
for _, view in ipairs({ "today", "wire", "standings", "results", "pace", "directory", "board", "myorg" }) do
    replies = {}
    logs = {}
    fire("ncm:paddock.request", 2, { view = view })
    clock = clock + 1
    local begun = false
    for _, r in ipairs(replies) do if r.name == "ncm:paddock.stream.begin" then begun = r.body.head.error == nil end end
    local refusedLog = false
    for _, l in ipairs(logs) do if l:find("REFUSED") or l:find("FAILED") then refusedLog = l end end
    check("view " .. view .. " streams without a hidden key or error" .. (refusedLog and (": " .. refusedLog) or ""), begun and not refusedLog)
end
fire("ncm:paddock.request", 2, { view = "profile", kind = "person", id = "p00010" })
clock = clock + 1
fire("ncm:paddock.request", 2, { view = "profile", kind = "org", id = "o002" })
clock = clock + 1
check(("every view handler fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)

-- ---------------------------------------------------------------- phase 4: garages, bodies, talk
local G = NcmCore.get("paddock.garages")
-- boot already housed every org, but the harness dropped the boot thread mid-flush (a yielding flush), so re-mark
-- them: what is asserted is that an org row CARRIES its garage and shift, not when boot wrote it
run(function()
    PaddockGarages.load(); PaddockGarages.ensure()
    for _, oid in ipairs(W.orgOrder) do PaddockStore.markOrg(oid) end
    PaddockStore.flush()
end)
local housed, persistedGarage = 0, 0
for _, oid in ipairs(W.orgOrder) do if W.orgs[oid].garageId and W.orgs[oid].shift then housed = housed + 1 end end
for _, r in pairs(DB.org) do if r.garage_id and r.garage_shift then persistedGarage = persistedGarage + 1 end end
check(("every org rents a garage on a shift (%d)"):format(housed), housed == #W.orgOrder)
check(("and the rental is persisted on the org row (%d)"):format(persistedGarage), persistedGarage == #W.orgOrder)
do
    -- a from-scratch rental (the first boot after schema 051) must fit one slice: it died on the quota live
    local saved = {}
    for _, oid in ipairs(W.orgOrder) do saved[oid] = { W.orgs[oid].garageId, W.orgs[oid].shift }; W.orgs[oid].garageId, W.orgs[oid].shift = nil, nil end
    maxSlice = 0
    run(function() PaddockGarages.ensure() end)
    check(("housing every org from scratch fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
    for _, oid in ipairs(W.orgOrder) do check("rental is deterministic for " .. oid, W.orgs[oid].garageId == saved[oid][1]) end
end
local deepest = 0
for _, list in pairs(PaddockGarages.tenants) do if #list > deepest then deepest = #list end end
check("no garage is stacked past three tenants (" .. deepest .. ")", deepest <= 3)
do
    local copy
    run(function() copy = PaddockStore.load() end)
    local o1 = W.orgs[W.orgOrder[1]]
    check("the garage and shift survive a reload", copy.orgs[o1.id].garageId == o1.garageId and copy.orgs[o1.id].shift
        and copy.orgs[o1.id].shift.from == o1.shift.from)
end

-- find a sanctioned org on shift at some hour with no race of its own nearby, and stand a player in its garage
local visitOrg, visitAt
for _, oid in ipairs(W.orgOrder) do
    local o = W.orgs[oid]
    if o.tier ~= "street" and not visitOrg then
        for h = 0, 47 do
            local t = clock + h * 3600
            if G.onShift(o.shift, t) then visitOrg, visitAt = o, t break end
        end
    end
end
check("an org is on shift somewhere in the next two days", visitOrg ~= nil)
local savedClock = clock
clock = visitAt
local site = G.site(visitOrg.garageId)
POS = { [1] = { x = site.x + 3, y = site.y, z = site.z, bucket = 0 } }
replies = {}
maxSlice = 0
run(function() PaddockGarages.tick() end)
local here = {}
for pid, b in pairs(PaddockGarages.bodies) do if b.siteId == site.id then here[#here + 1] = pid end end
check(("a player at the garage meets its crew (%d bodies)"):format(#here), #here >= 1 and #here <= G.MAX_BODIES)
check(("a presence pass fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
local told = false
for _, r in ipairs(replies) do if r.name == "ncm:paddock.bodies" and r.pid == -1 and #r.body.rows == #here then told = true end end
check("every client is told who is standing there", told)
local visitor = here[1]
local b1 = PaddockGarages.bodies[visitor]
POS[1] = { x = NPC[b1.npcId].position.x + 1, y = NPC[b1.npcId].position.y, z = site.z, bucket = 0 }
NOTES = {}
fire("ncm:paddock.talk", 1, { personId = visitor })
check("talking to them gets a line in their voice", #NOTES == 1 and NOTES[1].title:find(W.people[visitor].display, 1, true) ~= nil
    and not NOTES[1].message:find("{", 1, true))
check("and the meeting is recorded", DB.meeting["driver-1|" .. visitor] and DB.meeting["driver-1|" .. visitor].met_count == 1)
local firstLine = NOTES[1].message
clock = clock + 2
NOTES = {}
fire("ncm:paddock.talk", 1, { personId = visitor })
check("a second talk is a second meeting", DB.meeting["driver-1|" .. visitor].met_count == 2 and #NOTES == 1)
POS[1] = { x = site.x + 40, y = site.y, z = site.z, bucket = 0 }
clock = clock + 2
NOTES = {}
fire("ncm:paddock.talk", 1, { personId = visitor })
check("talking from 40 m away is refused by the server", DB.meeting["driver-1|" .. visitor].met_count == 2 and #NOTES == 1 and NOTES[1].message == "Get closer.")
check("the first meeting was an introduction", firstLine ~= nil)
POS = { [1] = { x = site.x + 5000, y = site.y, z = site.z, bucket = 0 } }
run(function() PaddockGarages.tick() end)
check("when the player leaves, the bodies go", next(PaddockGarages.bodies) == nil and next(NPC) == nil)
POS = { [1] = { x = site.x, y = site.y, z = site.z, bucket = 0 } }
local oldGarage = visitOrg.garageId
run(function() PaddockGarages.check(oldGarage, "bad", "roof pin") end)
check("a site marked bad leaves the pool and its tenants move", visitOrg.garageId ~= nil and visitOrg.garageId ~= oldGarage
    and DB.garageCheck[oldGarage].verdict == "bad")
local prof
run(function() prof = PaddockViews.profile(1, { kind = "org", id = visitOrg.id }) end)
check("an org profile says where its garage is, never a coordinate", prof.profile.garage and prof.profile.garage.label
    and prof.profile.garage.hours and prof.profile.garage.x == nil)
clock = savedClock
POS = {}
for k in pairs(NPC) do NPC[k] = nil end
PaddockGarages.bodies = PaddockGarages.bodies

-- ---------------------------------------------------------------- phase 5: live races, on schedule (L228)
local Live = NcmCore.get("paddock.live")
local liveDay = Clock.eastern(clock).dayIndex + 1
-- a human ghost of a route: a gentle dog-leg from start to finish at 10 Hz
local function ghostFor(route)
    local s, f = route.start, route.finish
    local mid = { x = (s.x + f.x) / 2 + 150, y = (s.y + f.y) / 2 - 150 }
    local raw, t = {}, 0
    for _, leg in ipairs({ { s, mid }, { mid, f } }) do
        for i = 0, 299 do
            local u = i / 300
            raw[#raw + 1] = { t, leg[1].x + (leg[2].x - leg[1].x) * u, leg[1].y + (leg[2].y - leg[1].y) * u, 10, 0 }
            t = t + 0.1
        end
    end
    raw[#raw + 1] = { t, f.x, f.y, 10, 0 }
    GHOSTS[route.routeId] = { poses_json = NcmCore.get("vocabulary.json").encode(raw), format = 1 }
end
local function streetRace(series, minute)
    local utc = Clock.utcAt(liveDay, 20 * 3600 + minute * 60)
    clock = utc - 600
    run(function() PaddockRaces.materialise(clock) end)
    local race = PaddockRaces.byId[Season.raceId(series, utc)]
    ghostFor(PaddockWorld.route(race.routeId))
    return race
end
-- stage, go, and step the street run in 250 ms until it has a verdict
local function runLive(race, lr0)
    clock = race.opensAt - 70
    for _ = 1, 6 do run(function() PaddockRaces.tick(clock) end) end
    run(function() PaddockLive.tick(clock) end)
    local lr = PaddockLive.byRace[race.raceId]
    if not lr or lr.state ~= "staging" then return lr end
    clock = race.opensAt
    for _ = 1, 8 do if race.state == "running" then break end run(function() PaddockRaces.tick(clock) end) end
    queue = {}
    run(function() PaddockLive.tick(clock) end)
    local steps = 0
    maxSlice = 0
    while lr.state == "running" and steps < 8000 do
        steps = steps + 1
        clock = clock + 0.25
        local q = queue; queue = {}
        for _, co in ipairs(q) do local ok, err = resumeMetered(co); assert(ok, err); if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end end
        if steps % 40 == 0 then run(function() PaddockRaces.tick(math.floor(clock)) end) end
        if steps == 120 then run(function() lr.liveView = PaddockViews.live(1, { raceId = race.raceId }) end) end
    end
    lr.steps = steps
    return lr
end

-- nobody near the route: the race stays simulated, and nothing spawns
local quiet = streetRace("street_a", 0)
POS = { [1] = { x = 6000, y = -6000, z = 0, bucket = 0 } }          -- far from every route
local lrq = runLive(quiet)
check("a race nobody is near stays simulated: nothing spawns", lrq and lrq.state == "skipped" and next(VEH) == nil)

-- a player at the start: it goes on the street by itself, no declaration; some cars get stuck and are rescued
local liveRace = streetRace("street_a", 40)
local liveRoute = PaddockWorld.route(liveRace.routeId)
POS = { [1] = { x = liveRoute.start.x + 20, y = liveRoute.start.y, z = 10, bucket = 0 } }
STUCK_FROM, STUCK_UNTIL_RESET = 8, true          -- cars 9-12 stall until something puts them back on the road
local lr = runLive(liveRace)
STUCK_FROM = nil
check("with a player at the start, the race goes on the street by itself", lr and lr.backend == "platform" and #lr.cars >= 8)
check(("the street run finished (%.0f s)"):format((lr.steps or 0) * 0.25), lr.state == "finished")
check("LIVE follows the street race's real cars mid-race", lr.liveView and lr.liveView.street == true and #lr.liveView.rows == #lr.cars
    and lr.liveView.rows[1].pct > 0)
check(("the timing loop fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
local rescued = 0
for _, c in ipairs(lr.cars) do if c.resets > 0 then rescued = rescued + 1 end end
check(("stuck cars were put back on the road and kept racing (%d rescued)"):format(rescued), rescued >= 3)
check("the verdict is physical: " .. tostring(lr.reason), lr.verdict == "physical" and DB.live[liveRace.raceId].verdict == "physical")
local rows = {}
for _, r in ipairs(DB.result) do if r.race_id == liveRace.raceId then rows[#rows + 1] = r end end
table.sort(rows, function(a, b) return a.position < b.position end)
local finished = 0
for _, r in ipairs(rows) do if r.state == "finished" then finished = finished + 1 end end
check(("every car finished, rescued ones included (%d of %d)"):format(finished, #rows), finished == #rows and #rows == #lr.cars)
check("the physical classification replaced the sim's rows", DB.race[liveRace.raceId].provenance == "physical" and rows[1].gap_ms == 0)
clock = math.floor(clock) + 10
for _ = 1, 6 do if liveRace.state == "resolved" then break end run(function() PaddockRaces.tick(clock) end) end
local box
run(function() box = PaddockViews.box(1, { raceId = liveRace.raceId }) end)
check("then the race resolves, and its box score says PHYSICAL", DB.race[liveRace.raceId].state == "resolved" and box.provenance == "physical")
queue = {}
for id in pairs(VEH) do VEH[id] = nil end

-- a player halfway along the route counts as watching
local race2 = streetRace("street_b", 60)
local r2 = PaddockWorld.route(race2.routeId)
local path2 = PaddockLive.pathFor(race2.routeId)
local mid = path2.points[math.floor(#path2.points / 2)]
POS = { [1] = { x = mid.x + 40, y = mid.y, z = 10, bucket = 0 } }
STUCK_FROM, STUCK_UNTIL_RESET = 2, false            -- ten cars are stuck for good
local lr2 = runLive(race2)
STUCK_FROM = nil
check("a player halfway along the route is enough to put it on the street", lr2 and lr2.cars and #lr2.cars >= 8 and #lr2.watchers == 1)
check("the run ends once the winner is home and the grace has passed", lr2.state == "finished" and lr2.closeMs ~= nil)
check("too few finishers: the verdict falls back (" .. tostring(lr2.reason) .. ")", lr2.verdict == "fallback" and tostring(lr2.reason):find("only 2 of", 1, true) ~= nil)
local notClassified = 0
for _, why in pairs(lr2.out) do if why == "not_classified" then notClassified = notClassified + 1 end end
check("cars still out there at the close are 'not classified', not written off early", notClassified >= 1)
check("and the sealed sim result stands", (DB.race[race2.raceId].provenance or "simulated") == "simulated")
queue = {}
for id in pairs(VEH) do VEH[id] = nil end

-- the physical bubble: nobody at the start, so the race runs on its model; a player halfway along the line sees the
-- field arrive, race past physically, and hand back to the model; the result is MIXED
local race4 = streetRace("street_a", 120)
POS = { [1] = { x = 6000, y = -6000, z = 0, bucket = 0 } }                 -- far away at staging: no street race
clock = race4.opensAt - 70
for _ = 1, 6 do run(function() PaddockRaces.tick(clock) end) end
run(function() PaddockLive.tick(clock) end)
check("with nobody near at staging, no street race is staged", not PaddockLive.byRace[race4.raceId] or PaddockLive.byRace[race4.raceId].state == "skipped")
clock = race4.opensAt
for _ = 1, 8 do if race4.state == "running" then break end run(function() PaddockRaces.tick(clock) end) end
check("the race runs on its continuous model", race4.state == "running" and race4.model ~= nil)
local path4 = race4.model.path.points
local stand = path4[math.floor(#path4 * 0.55)]
POS = { [1] = { x = stand.x + 15, y = stand.y, z = 10, bucket = 0 } }        -- the player walks to the middle of the route
local maxCars, steps4 = 0, 0
maxSlice = 0
local simClose = race4.closesAt
while race4.state == "running" and steps4 < 4000 do
    steps4 = steps4 + 1
    clock = clock + 0.5
    run(function() PaddockBubble.tick() end)
    local n = 0
    for _ in pairs(VEH) do n = n + 1 end
    if n > maxCars then maxCars = n end
    if steps4 % 10 == 0 then run(function() PaddockRaces.tick(math.floor(clock)) end) end
end
local bs = PaddockBubble.stats
check(("the field became physical as it reached the player (%d spawned, at most %d at once)"):format(bs.spawned, maxCars), bs.spawned >= 6 and maxCars >= 1)
check(("and handed back to the model as it drove away (%d handed back)"):format(bs.handedBack), bs.handedBack >= 6)
check(("a bubble pass fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
check("the race resolved, with the model's result and its anchors", DB.race[race4.raceId].state == "resolved" and DB.race[race4.raceId].provenance == "mixed")
local rows4 = 0
for _, r in ipairs(DB.result) do if r.race_id == race4.raceId then rows4 = rows4 + 1 end end
check("every car is classified", rows4 == #race4.frozen.grid)
local detail4 = NcmCore.get("vocabulary.json").decode(DB.race[race4.raceId].detail_json or "{}") or {}
local shared = 0
for _, pct in pairs((detail4.live or {}).physicalPct or {}) do if pct > 0 then shared = shared + 1 end end
check(("each car's physical share is recorded (%d cars drove part of it for real)"):format(shared), shared >= 6)
check("nothing is left on the road", next(VEH) == nil)
POS = {}

-- the probe suite: a distance ladder of cars, each tried unasked, asked (requestAuthority) and with a camera lease
local W0 = PaddockWorld.route(Season.ROUTES.hook)
POS = { [1] = { x = W0.start.x, y = W0.start.y, z = 10, bucket = 0 } }
local probeOk, probeRes
local co = coroutine.create(function() probeOk, probeRes = PaddockProbe.run(1) end)
for _ = 1, 400 do
    if coroutine.status(co) == "dead" then break end
    local ok, err = coroutine.resume(co); assert(ok, err)
    clock = clock + 1
end
local probeRows = 0
for id in pairs(DB.live) do if id:match("^probe%-") then probeRows = probeRows + 1 end end
check(("the probe ladder records one row per distance (%d rows): %s"):format(probeRows, tostring(probeRes):sub(1, 160)), probeOk and probeRows >= 3)
check("every leg ran for every car", tostring(probeRes):find("A ", 1, true) and tostring(probeRes):find("| B ", 1, true) and tostring(probeRes):find("| C ", 1, true)
    and tostring(probeRes):find("| D ", 1, true) and tostring(probeRes):find("E driverless request", 1, true))
check("the probe leaves nothing behind: cars, drivers, cameras, leases", next(VEH) == nil and next(CAMS) == nil and next(LEASES) == nil)
POS = {}
queue = {}

-- ---------------------------------------------------------------- manager mode
DB.ledger = {}; DB.idem = {}
ledgerAdd("driver-2", "starter", 30000, "seed:2")
fire("ncm:paddock.manager", 2, { action = "found", args = { name = "Kabuki Night Racing" } })
local mine = PaddockWorld.orgManagedBy("driver-2")
check("founding creates a Street team run by the human", mine ~= nil and mine.tier == "street" and mine.origin == "human_founded")
check("the fee was taken from the wallet", ledgerTotal("driver-2") == 25000)
check("the treasury holds fee plus grant", mine.cash == 20000)
check("the One-Team affiliation row exists", activeAff("driver-2") ~= nil)
clock = clock + 1
fire("ncm:paddock.manager", 2, { action = "found", args = { name = "Second Team" } })
check("a second team is refused by the One-Team Rule", #W.orgOrder == 61 and ledgerTotal("driver-2") == 25000)
clock = clock + 1
fire("ncm:paddock.manager", 2, { action = "withdraw", args = { eddies = 1500, idem = "w1" } })
check("a withdrawal pays out after tax", ledgerTotal("driver-2") == 25000 + 1050 and mine.cash == 18500)
clock = clock + 1
fire("ncm:paddock.manager", 2, { action = "withdraw", args = { eddies = 1000, idem = "w2" } })
check("the weekly cap holds", ledgerTotal("driver-2") == 26050)
clock = clock + 1
local fa = NcmCore.get("paddock.world").freeAgents(W)[1]
fire("ncm:paddock.manager", 2, { action = "sign", args = { driverId = fa.id, wage = 200, seasons = 2 } })
check("a signing is queued for the Cup boundary, not applied", #mine.pending == 1 and fa.orgId == nil)
clock = clock + 1
fire("ncm:paddock.manager", 2, { action = "develop", args = { area = "aerodynamics", eddies = 3000 } })
check("development spends treasury now", mine.cash == 15500)

-- ---------------------------------------------------------------- time passes
local function passFn(fn)
    local co = coroutine.create(fn)
    maxSlice = 0
    repeat
        local ok, err = resumeMetered(co)
        assert(ok, err)
    until coroutine.status(co) == "dead"
end
local cashBefore = W.orgs.o002.cash
clock = clock + 86400
passFn(function() PaddockLife.daily(clock) end)
check(("a daily tick fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
check("the day's money moved", W.orgs.o002.cash ~= cashBefore)
check("the daily tick is idempotent for its day", (function() local r; run(function() r = PaddockLife.daily(clock) end) return r == false end)())

local cup = Season.cupOf(clock)
clock = cup.cupEndUtc + 60
passFn(function() PaddockLife.cupBoundary(clock) end)
check(("a Cup boundary fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
check("the queued signing was decided at the boundary", #mine.pending == 0)
check("the world moved to the next Cup", W.cupId == Season.cupOf(clock).cupId)

local yearBefore = W.paddockYear
local seasons = NcmCore.get("competition.seasons")
clock = seasons.parse(W.seasonId).endUtc + 3600
passFn(function() PaddockLife.cupBoundary(clock); PaddockLife.rollover(clock) end)
check(("a season rollover fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
check("a paddock year passed", W.paddockYear == yearBefore + 1 and W.seasonOrdinal == 1)
local fas = #NcmCore.get("paddock.world").freeAgents(W)
check("the free-agent pool is topped up (" .. fas .. ")", fas >= 40)
local seats = 0
for _, o in ipairs(NcmCore.get("paddock.world").orgsInSeries(W, "premier")) do
    for _, d in ipairs(NcmCore.get("paddock.world").drivers(W, o.id)) do if d.seat and d.seat:match("^race") then seats = seats + 1 end end
end
check("every Premier race seat is filled after rollover (" .. seats .. ")", seats >= 14)

realPrint(("%d passed, 0 failed"):format(passed))
