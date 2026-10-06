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
-- server-to-server events between resources (L250: ncm_league <-> ncm_paddock): recorded, and delivered to a handler here
EMITTED = {}
function TriggerEvent(name, ...)
    EMITTED[#EMITTED + 1] = { name = name, args = { ... } }
    if events[name] then return events[name](...) end
end
function CreateThread(fn) queue[#queue + 1] = coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function TriggerClientEvent(name, pid, body)
    replies[#replies + 1] = { name = name, pid = pid, body = body }
    -- KB-238: a bubble car comes up empty; the client reports it settled after delayMs and the server seats its driver
    if name == "ncm:paddock.bubble.car" and type(body) == "table" and body.op == "seat" then
        SEAT_QUEUE[#SEAT_QUEUE + 1] = { pid = pid, body = body, at = Open77.time.unix() + (body.delayMs or 3000) / 1000 }
    end
    if PACE_HOOK then PACE_HOOK(name, pid, body) end
end
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
SEAT_QUEUE = {}
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
    getView = function(_, id) return { id = id, state = "stub" } end,
} }
local function vdist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
local function advance(v)
    if not (v.route and v.t) or clock <= v.t then return end           -- nothing moves before its go
    -- the Pace double's stall rule (Pace 0.7.0): a stuck car gets a fresh racing command 6 s in and races on
    if v.stall and v.stuckUntilReset and v.unstickAt and clock >= v.unstickAt then
        v.dist = v.dist + 0; v.t = clock; v.stall = false; v.speed = v.paceSpeed; v.unstuck = true
    end
    v.dist = v.dist + (v.speed or 0) * (clock - v.t); v.t = clock
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
    environment = {
        state = { rate = 8, secondsOfDay = 12 * 3600, frozen = false },
        getState = function() return Open77.environment.state end,
        setTimeRate = function(r) Open77.environment.state.rate = r return Open77.environment.state end,
        setTimeFrozen = function(f) Open77.environment.state.frozen = f return Open77.environment.state end,
        setTime = function(h, m, sec) Open77.environment.state.secondsOfDay = h * 3600 + m * 60 + sec; Open77.environment.setCalls = (Open77.environment.setCalls or 0) + 1 return Open77.environment.state end,
    },
    world = { groundZ = function(p, o) return (o.fromZ or 1.5) - 1.5 end },
    npcs = {
        ai = { tasks = 1 }, damage = { invulnerable = 2 },
        create = function(def) nextEnt = nextEnt + 1; NPC[nextEnt] = { position = def.position, record = def.record } return nextEnt end,
        remove = function(id) NPC[id] = nil return true end,
        -- the real shape: a FLAT snapshot (x, y, z, bucket), as freeroam's bots read it -- never `.position` (KB-234)
        get = function(id)
            local n = NPC[id]
            if not n then return nil end
            return { x = n.position.x, y = n.position.y, z = n.position.z, bucket = 0, record = n.record }
        end,
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
        remove = function(id) if VEH[id] and VEH[id].driver then REMOVED_WITH_DRIVER = (REMOVED_WITH_DRIVER or 0) + 1 end VEH[id] = nil return true end,
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
    climate = nil, climateEvent = {}, trajectory = {}, placeCheck = {},
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
            "attrs_json", "personality_json", "principal_json", "morale", "state", "wage", "contract_ends", "evidence_json",
            "league_id", "car_json", "cash" }
        local r = {}
        for i, k in ipairs(keys) do r[k] = v[i] end
        if r.org_id == "" then r.org_id = nil end
        if r.seat == "" then r.seat = nil end
        if r.league_id == "" then r.league_id = nil end
        if r.car_json == "" then r.car_json = nil end
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
    elseif has(q, "INTO paddock_climate_event") then
        DB.climateEvent[v[2] .. "|" .. v[3]] = { day_index = v[2], district = v[3], from_regime = v[4], to_regime = v[5] }
    elseif has(q, "INTO paddock_climate") then
        DB.climate = { day_index = v[2], season_id = v[3], state_json = v[4], facts_json = v[5] }
    elseif has(q, "INTO paddock_trajectory") then
        DB.trajectory[v[2]] = { bucket = v[3], profile_json = v[4] }
    elseif has(q, "INTO paddock_place_check") then
        DB.placeCheck[v[2]] = { place_id = v[2], verdict = v[3] }
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
        if has(q, "MAX(version) FROM schema_migrations") then return 64 end
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
        if has(q, "FROM paddock_climate") then return DB.climate end
        if has(q, "FROM paddock_trajectory") then return DB.trajectory[v[2]] end
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
        elseif has(q, "FROM paddock_place_check") then
            for _, r in pairs(DB.placeCheck) do out[#out + 1] = r end
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
        "billie", "life", "manager", "spotlight", "garages", "days", "live", "humans", "probe", "bubble", "clock", "views", "requests", "admin", "main" }) do
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
check("170 organizations and their people exist (L236: ~3x)", #W.orgOrder == 170 and #W.personOrder > 1100)
local persisted = 0
for _ in pairs(DB.org) do persisted = persisted + 1 end
check("every org was persisted", persisted == 170)
-- L249: every league carries its owner-approved name
do
    local Names = NcmCore.get("paddock.names")
    local named = 0
    for id, s in pairs(W.series) do if s.name == Names.LEAGUES[id] then named = named + 1 end end
    check(("every league has its approved name (%d of 15; street_a is %s)"):format(named, tostring(W.series.street_a and W.series.street_a.name)),
        named == 15 and W.series.premier.name == "Hypercar Championship")
end
check("genesis wrote a founding story", next(DB.news) ~= nil)

-- reload round-trip: the store reads back what it wrote
do
    local copy = PaddockStore.load and nil
    run(function() PaddockStore.flush(); copy = PaddockStore.load() end)
    check("reloaded world has the same orgs and names", copy and #copy.orgOrder == 170 and copy.orgs.o001.name == W.orgs.o001.name
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
W.orgs[("o%03d"):format(#W.orgOrder + 1)] = nil   -- the first org past genesis (o061 before L236)
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
-- The field freezes at T-1 with entries (L269; owner 2026-10-02), not when Billie prices: freeze it here as T-1 would
run(function() PaddockRaces.freeze(race) end)
check("the freeze grids the field", race.frozen ~= nil and #race.frozen.grid > 0)
-- L249: the Race Guide reads the Paddock's next events from GlobalState (ncm_league cannot call this VM)
do
    GlobalState = GlobalState or {}
    run(function() PaddockRaces.publishGuide(clock + 100) end)
    local rows = GlobalState.ncmPaddockGuide or {}
    local premierRow
    for _, r in ipairs(rows) do if r.raceId == premierId then premierRow = r end end
    check(("the Race Guide gets the Paddock's next events (%d rows)"):format(#rows), #rows >= 1 and #rows <= 40
        and premierRow and premierRow.seriesName == "Hypercar Championship" and premierRow.field == #race.frozen.grid
        and premierRow.venue and premierRow.startsAt == race.opensAt)
    -- L250 step 2: every frozen entrant has a qualifying time, in grid order, and the feed carries the sheet
    local q, ordered, prev = race.frozen.quali or {}, true, 0
    for _, pid in ipairs(race.frozen.grid) do
        if not q[pid] or q[pid] < prev then ordered = false end
        prev = q[pid] or math.huge
    end
    check("the frozen grid is in qualifying-time order, every entrant timed", ordered)
    check("the Race Guide feed carries the qualifying sheet", premierRow and type(premierRow.quali) == "table"
        and #premierRow.quali == #race.frozen.grid and premierRow.quali[1].quali and premierRow.quali[1].name ~= "?")
end
-- L249: the frozen field is who TURNED UP -- teams field their available drivers -- and every absence has a reason
do
    local absentN = 0
    for _, n in pairs(race.frozen.absent or {}) do absentN = absentN + n end
    check(("the premier field is who turned up (%d on the grid, %d not)"):format(#race.frozen.grid, absentN),
        #race.frozen.grid >= 10 and #race.frozen.grid <= 16 and absentN >= 16)
    local touched = NcmCore.get("paddock.world").growPools(W, 50)
    check(("a world already at its pools grows nothing at boot (%d)"):format(#touched), #touched == 0)
    for _, pid in ipairs(race.frozen.grid) do
        local p = W.people[pid]
        if not (p.evidence and p.evidence.lastStartAt == race.opensAt) then check("a frozen entrant is marked as having started", false) end
    end
end
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

-- THE FLAG (2026-10-02): once the leader is home the race is flagged a window per metre later, the league is told,
-- and the close never moves later than it was
do
    local before = race.closesAt
    local RS = NcmCore.get("paddock.racestate")
    local leadMs = RS.leaderFinishAt(race.model)
    local flagEvents = {}
    local realTrigger = TriggerEvent
    TriggerEvent = function(name, ...) if name == "ncm:paddock.flag" then flagEvents[#flagEvents + 1] = { ... } end return realTrigger(name, ...) end
    PaddockRaces.flagCheck(race, race.modelGoAt + leadMs / 1000 - 1)
    check("no flag before the leader is home", race.flagAt == nil)
    PaddockRaces.flagCheck(race, race.modelGoAt + leadMs / 1000 + 1)
    TriggerEvent = realTrigger
    local window = NcmCore.get("paddock.mixed").finishWindowSec(race.model.lengthM)
    check(("the flag is the leader's crossing + %d s, and the league hears it"):format(window), race.flagAt
        and math.abs(race.flagAt - (race.modelGoAt + leadMs / 1000 + window)) <= 1
        and #flagEvents == 1 and flagEvents[1][1] == premierId and flagEvents[1][2] == race.flagAt)
    check("the close never moves later", race.closesAt <= before and race.closesAt <= race.flagAt)
end

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

-- ---------------------------------------------------------------- the clock: Night City on Eastern real time (KB-217)
do
    local env = Open77.environment
    env.state.rate, env.state.secondsOfDay, env.setCalls = 8, 12 * 3600, 0
    run(function() PaddockClock.sync(true) end)
    local e = Clock.eastern(clock)
    check("the clock runs at 1x (NCM Clock makes the engine agree)", env.state.rate == 1.0)
    check("and shows Eastern time", math.abs(PaddockClock.circular(e.secondsOfDay, env.state.secondsOfDay)) <= 1)
    local calls = env.setCalls
    env.state.secondsOfDay = env.state.secondsOfDay + 60                        -- a minute of drift is left alone
    run(function() PaddockClock.sync(false) end)
    check("a small drift is not corrected (every write is a jump)", env.setCalls == calls)
    env.state.secondsOfDay = env.state.secondsOfDay + 3600
    run(function() PaddockClock.sync(false) end)
    check("a real drift is corrected", env.setCalls == calls + 1)
    check("the circle wraps at midnight", PaddockClock.circular(86000, 100) == 500 and PaddockClock.circular(100, 86000) == -500)
end

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
-- every body the server placed, at any garage near the player (at ~3x the cast a neighbouring garage can be on shift too)
local placed = 0
for _ in pairs(PaddockGarages.bodies) do placed = placed + 1 end
for _, r in ipairs(replies) do if r.name == "ncm:paddock.bodies" and r.pid == -1 and #r.body.rows == placed then told = true end end
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

-- ---------------------------------------------------------------- the life sim (L240): climate, days, bodies, trajectory
do
    local Places = NcmCore.get("world.places")
    local Sched = NcmCore.get("life.schedule")
    local Clock_ = NcmCore.get("world.clock")
    maxSlice = 0
    run(function() PaddockDays.loadClimate(); PaddockDays.loadChecks() end)
    check(("loading the climate fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
    check("a first boot writes the climate's genesis", DB.climate and DB.climate.state_json and #DB.climate.state_json > 100)
    local c = PaddockDays.climate()
    local nd = 0
    for _ in pairs(c.districts) do nd = nd + 1 end
    check("every district has a climate (" .. nd .. ")", nd == #Places.DISTRICTS)

    -- the live order: the first pass builds the day's index (and the regulars counts the planner's turns use)
    POS = {}
    maxSlice = 0
    run(function() PaddockDays.tick() end)
    check(("building the day's index fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
    -- find someone whose day puts them at a place a player can stand near, and when
    local who, whereP, when
    for _, pid in ipairs(W.personOrder) do
        local p = W.people[pid]
        local o = p.orgId and W.orgs[p.orgId]
        if p.state == "active" and o and o.lifecycle ~= "folded" and not o.humanManagerDriverId then
            local plan
            run(function() plan = PaddockDays.planFor(p, Sched.planDay(clock)) end)
            for _, runX in ipairs(plan and plan.runs or {}) do
                if runX.activity ~= "work" and Sched.BODILY[runX.activity] and runX.fromUtc > clock then
                    who, whereP, when = p, Places.get(runX.placeId), runX.fromUtc
                    break
                end
            end
        end
        if who then break end
    end
    check("someone's day takes them to a real place", who ~= nil and whereP ~= nil)
    local savedClock2 = clock
    clock = when + 60
    POS = { [1] = { x = whereP.x + 3, y = whereP.y, z = whereP.z, bucket = 0 } }
    maxSlice = 0
    for _ = 1, 400 do
        run(function() PaddockDays.tick() end)
        if PaddockGarages.bodies[who.id] then break end
    end
    check(("a life pass fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
    local b = PaddockGarages.bodies[who.id]
    check("a player standing there meets them, off shift, at " .. Places.label(whereP), b and b.source == "day" and b.siteId == whereP.id)
    local n = 0
    for _, x in pairs(PaddockGarages.bodies) do if x.siteId == whereP.id then n = n + 1 end end
    check("a place never holds more than four day bodies (" .. n .. ")", n <= 4)
    -- the garage loop must not retire a day body
    run(function() PaddockGarages.tick() end)
    check("the garage pass leaves day bodies to their own plan", PaddockGarages.bodies[who.id] ~= nil)
    -- talk works on a day body, and the trajectory and climate hear of it
    -- player 2: the harness clock is rewound for this section, and player 1's talk throttle remembers the future
    POS[2] = { x = NPC[b.npcId].position.x + 1, y = NPC[b.npcId].position.y, z = whereP.z, bucket = 0 }
    NOTES = {}
    fire("ncm:paddock.talk", 2, { personId = who.id })
    check("talking to someone at " .. Places.label(whereP) .. " works like at a garage", #NOTES == 1)
    check("and the Driver's hidden trajectory recorded it", DB.trajectory["driver-2"] ~= nil)
    check("the trajectory never reaches a client", not (NOTES[1].message or ""):find("bucket", 1, true))
    -- the Scanner reads them (scan.lua): the right person, plausible rows, nothing hidden; and nothing where nobody is
    replies = {}
    fire("ncm:life.scan", 2, { token = "t1", pos = NPC[b.npcId].position })
    local sr
    for _, r in ipairs(replies) do if r.name == "ncm:life.scan.result" and r.pid == 2 then sr = r.body end end
    check("scanning them reads who they are and what they are doing", sr and sr.found == true and sr.name == who.display
        and sr.doing and sr.at and sr.district and sr.token == "t1")
    local leak = false
    for k in pairs(sr or {}) do if k == "attrs" or k == "personality" or k == "needs" or k == "bucket" then leak = true end end
    check("the scan carries no hidden stat", not leak)
    replies = {}
    clock = clock + 1
    fire("ncm:life.scan", 2, { token = "t2", pos = { x = whereP.x + 40, y = whereP.y, z = whereP.z } })
    local miss
    for _, r in ipairs(replies) do if r.name == "ncm:life.scan.result" then miss = r.body end end
    check("scanning a point where no Paddock person stands finds nobody", miss and miss.found == false)
    -- when the plan moves them on, the body goes
    local plan = PaddockDays.planFor(who, Sched.planDay(clock))
    local runNow = Sched.at(plan, clock)
    clock = runNow.toUtc + 60
    local nextPlace = Sched.bodyAt(PaddockDays.planFor(who, Sched.planDay(clock)), clock)
    run(function() PaddockDays.tick() end)
    local after = PaddockGarages.bodies[who.id]
    check("when their day moves on, so does the body", (nextPlace and nextPlace.id == whereP.id) or after == nil
        or after.siteId ~= whereP.id)
    POS = { [1] = { x = whereP.x + 5000, y = whereP.y, z = whereP.z, bucket = 0 } }
    run(function() PaddockDays.tick() end)
    local left = 0
    for _, x in pairs(PaddockGarages.bodies) do if x.source == "day" then left = left + 1 end end
    check("when the player leaves, the day bodies go", left == 0)

    -- the climate steps once a day with the tallied facts, and not twice
    PaddockDays.fact("Heywood", "street_race", 5)
    PaddockDays.fact("Nowhere", "street_race", 5)
    PaddockDays.fact("Heywood", "no_such_fact", 5)
    local sceneBefore = c.districts.Heywood.axes.scene
    clock = clock + 86400
    maxSlice = 0
    local stepped
    run(function() stepped = PaddockDays.daily(clock) end)
    check(("a climate step fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
    check("the climate steps at the day change", stepped == true and PaddockDays.climate().day == Clock_.eastern(clock).dayIndex)
    check("with the day's facts", #PaddockDays.climate().districts.Heywood.causes >= 1)
    local again
    run(function() again = PaddockDays.daily(clock) end)
    check("and only once a day", again == false)
    -- a place marked bad leaves every day
    run(function() PaddockDays.check(whereP.id, "bad", "roof pin") end)
    check("a place marked bad is recorded", DB.placeCheck[whereP.id] and DB.placeCheck[whereP.id].verdict == "bad")
    local fresh
    run(function() fresh = PaddockDays.planFor(who, Sched.planDay(clock)) end)
    local uses = 0
    for _, r in ipairs(fresh.runs) do if r.placeId == whereP.id then uses = uses + 1 end end
    check("and nobody's new day goes there", uses == 0)
    clock = savedClock2
    POS = {}
    for k in pairs(NPC) do NPC[k] = nil end
    for pid, x in pairs(PaddockGarages.bodies) do if x.source == "day" then PaddockGarages.bodies[pid] = nil end end
end

-- ---------------------------------------------------------------- phase 5: live races, on schedule (L228)
local Live = NcmCore.get("paddock.live")
-- the client half of the seat handshake (KB-238): every pass, report the cars that have stood their delay
do
    local bubbleTick = PaddockBubble.tick
    PaddockBubble.tick = function(...)
        local due, keep = {}, {}
        for _, q in ipairs(SEAT_QUEUE) do if clock >= q.at then due[#due + 1] = q else keep[#keep + 1] = q end end
        SEAT_QUEUE = keep
        for _, q in ipairs(due) do
            source = q.pid
            events["ncm:paddock.bubble.settled"]({ raceId = q.body.raceId, vehicleId = q.body.vehicleId })
        end
        return bubbleTick(...)
    end
end

-- THE PACE DOUBLE (L246). Street runs are the host's NCM Pace driving the engine's racer on race splines; the server
-- never drives them. Standing in for the host's Pace, this takes the drive plan the server sends, races every car
-- along the route from the lights (through every checkpoint and on past the finish, as the splines' run-outs do),
-- gives a stuck car a fresh command 6 s in (Pace's stall rule), and reports each gate the car crosses back to the
-- server as Pace does -- timed from the car's own positions, so the server's corroboration is exercised for real.
PACE_DOUBLE_SPEED = 24
local paceRuns = {}
PACE_HOOK = function(name, pid, body)
    if name ~= "ncm:paddock.live.drive" or (body.part or 1) ~= 1 then return end
    local lr = PaddockLive.byRace[body.raceId]
    if not lr or not lr.path then return end
    local go = lr.goMs / 1000
    local ids = {}
    for i, c in ipairs(lr.cars) do
        ids[i] = c.personId
        local v = VEH[c.vehicleId]
        if v then
            v.route = { v.pos }
            for _, p in ipairs(lr.path.points) do v.route[#v.route + 1] = p end
            v.paceSpeed = PACE_DOUBLE_SPEED - (i % 4) * 0.5
            v.speed, v.t, v.dist, v.unstickAt = v.stall and 0 or v.paceSpeed, go, 0, go + 6
        end
    end
    paceRuns[body.raceId] = { lr = lr, timing = Live.newTiming(lr.gates, ids), legs = body.legs }
end
PACE_TICK = function()
    for raceId, run in pairs(paceRuns) do
        local lr = run.lr
        if lr.state ~= "running" then paceRuns[raceId] = nil
        else
            local tMs = clock * 1000 - lr.goMs
            for _, c in ipairs(lr.cars) do
                local pos = Open77.vehicles.getPosition(c.vehicleId)
                if pos and tMs >= 0 then
                    for _, g in ipairs(Live.observe(run.timing, c.personId, pos, tMs) or {}) do
                        source = lr.pid
                        events["ncm:paddock.live.gate"]({ raceId = raceId, vehicleId = c.vehicleId, gate = g,
                            tMs = run.timing.cars[c.personId].times[g] })
                    end
                end
            end
        end
    end
end
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
    local utc = Clock.utcAt(liveDay, 18 * 3600 + minute * 60)   -- L249: street nights open at 18:00
    clock = utc - 600
    -- these are point-to-point street runs with a straight ghost: keep the owner's authored ovals (L236) out of the
    -- draw, or a slot that lands on a roundabout gets a sprint's ghost
    local ovals = NcmCore.get("data.ovals")
    local authored = ovals.LIST
    ovals.LIST = {}
    run(function() PaddockRaces.materialise(clock) end)
    ovals.LIST = authored
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
    for _ = 1, 80 do if race.state == "running" then break end run(function() PaddockRaces.tick(clock) end) end
    queue = {}
    run(function() PaddockLive.tick(clock) end)
    local steps = 0
    maxSlice = 0
    while lr.state == "running" and steps < 8000 do
        steps = steps + 1
        clock = clock + 0.25
        local q = queue; queue = {}
        for _, co in ipairs(q) do local ok, err = resumeMetered(co); assert(ok, err); if coroutine.status(co) ~= "dead" then queue[#queue + 1] = co end end
        PACE_TICK()
        if steps % 40 == 0 then run(function() PaddockRaces.tick(math.floor(clock)) end) end
        if steps == 120 then run(function() lr.liveView = PaddockViews.live(1, { raceId = race.raceId }) end) end
        if steps == 121 then
            replies = {}
            run(function() PaddockBroadcast.tick() end)
            for _, r in ipairs(replies) do if r.name == "ncm:broadcast.paddock" and r.body.raceId == race.raceId then lr.bcast = r.body end end
        end
    end
    lr.steps = steps
    return lr
end

-- nobody near the route: the race stays simulated, and nothing spawns
local quiet = streetRace("street_a", 0)
POS = { [1] = { x = 6000, y = -6000, z = 0, bucket = 0 } }          -- far from every route
local lrq = runLive(quiet)
check("a race nobody is near stays simulated: nothing spawns", (not lrq or lrq.state == "skipped") and next(VEH) == nil)

-- players near a start are warned before the grid spawns (the native HUD banner), and a car never lands on a person
do
    local warnRace = streetRace("street_a", 42)
    local wr = PaddockWorld.route(warnRace.routeId)
    clock = warnRace.opensAt - 120
    POS = { [1] = { x = wr.start.x + 30, y = wr.start.y, z = 10, bucket = 0 } }
    replies = {}
    run(function() PaddockLive.tick(clock) end)
    local banner
    for _, r in ipairs(replies) do if r.name == "ncm:paddock.live.warn" and r.pid == 1 then banner = r.body end end
    check("a player near the start gets the race-start banner", banner and banner.title == "WARNING: IMPENDING RACE START" and banner.seconds >= 119)
    -- it ends when the cars go -- the window's opening -- not 5 s later (cars left ~10 s before it cleared, 2026-10-01)
    check(("the banner's countdown ends exactly at green (%s s for %d s)"):format(tostring(banner and banner.seconds), warnRace.opensAt - clock),
        banner and math.abs(banner.seconds - (warnRace.opensAt - clock)) <= 1)
    -- the warning also raises the native traffic null area on that client: SP's trafficClearRadiusM around the start (L234)
    local area
    for _, r in ipairs(replies) do if r.name == "ncm:paddock.live.area" and r.pid == 1 then area = r.body end end
    check("the warning raises a traffic null area over the start", area and area.half == 140 and area.x == wr.start.x and area.seconds >= 120 + 60)
    replies = {}
    run(function() PaddockLive.tick(clock + 5) end)
    local again = false
    for _, r in ipairs(replies) do if r.name == "ncm:paddock.live.warn" then again = true end end
    check("once per race, not every tick", not again)
    replies = {}
    run(function() PaddockLive.lowerAreas(warnRace.raceId) end)
    check("and the race's end lowers it", replies[1] and replies[1].name == "ncm:paddock.live.area" and replies[1].body.seconds == 0)
end

-- L247 (KB-238): A STREET RACE ON THE CONTINUOUS MODEL AND THE BUBBLE, with a driver in every physical car. The grid
-- run kept twelve driven cars alive however far from the host they got, and the CTDs came as they crossed the edge of
-- the host's streaming. Now: the server's line is the baked road (IDEA-787); a player with Pace at the start sees the
-- grid come up 30 s before the lights; cars further than bubbleOutM from every player go back to the model -- the
-- driver out first -- and come back in, driver seated, wherever a player meets them (IDEA-786); Pace races every one
-- on the race spline of the leg it is on.
do
    local R = NcmCore.get("paddock.racestate")
    local sr = streetRace("street_a", 42)
    local route = PaddockWorld.route(sr.routeId)
    POS = { [1] = { x = route.start.x + 20, y = route.start.y, z = 10, bucket = 0 } }
    PaddockLive.paceClients[1] = { ok = true, version = "0.8.1" }
    -- the bubble's Pace double: a car that joins drives the road line from where it was set down, from the lights
    local bubblePace = { adds = {}, removes = 0, plans = {}, held = {} }   -- held: vehicles Pace was given and not yet taken back
    local prevHook = PACE_HOOK
    PACE_HOOK = function(name, pid, body)
        if name == "ncm:paddock.bubble.plan" and body.raceId == sr.raceId then bubblePace.plans[#bubblePace.plans + 1] = body end
        if name == "ncm:paddock.bubble.car" and body.raceId == sr.raceId then
            if body.op == "remove" then bubblePace.removes = bubblePace.removes + 1; bubblePace.held[body.vehicleId] = nil end
            if body.op == "add" then bubblePace.held[body.vehicleId] = true end
            local v = VEH[body.vehicleId]
            if body.op == "add" and v then
                bubblePace.adds[#bubblePace.adds + 1] = body
                local pts = PaddockLive.pathFor(sr.routeId).points
                local k = Live.nearestIndex(pts, v.pos)
                v.route = { v.pos }
                for i = k + 1, #pts do v.route[#v.route + 1] = pts[i] end
                v.speed, v.dist, v.t = PACE_DOUBLE_SPEED, 0, math.max(clock, sr.opensAt)
            end
        end
        if prevHook then prevHook(name, pid, body) end
    end
    REMOVED_WITH_DRIVER = 0
    -- an older Pace drops the legs and drives the retired command (01:36): it brings no street car in
    do
        local old = streetRace("street_c", 12)
        local oroute = PaddockWorld.route(old.routeId)
        POS = { [1] = { x = oroute.start.x + 20, y = oroute.start.y, z = 10, bucket = 0 } }
        PaddockLive.paceClients[1] = { ok = true, version = "0.8.0" }
        clock = old.opensAt - 70
        for _ = 1, 6 do run(function() PaddockRaces.tick(clock) end) end
        clock = old.opensAt - 20
        for _ = 1, 10 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
        local ob = PaddockBubble.byRace[old.raceId]
        check("a player with Pace 0.8.0 brings no street car in (it would drive the retired command)", (not ob or next(ob.cars) == nil) and next(VEH) == nil)
        PaddockRaces.byId[old.raceId] = nil          -- off the board: it must not run beside the race below
        PaddockLive.paceClients[1] = { ok = true, version = "0.8.1" }
        POS = { [1] = { x = route.start.x + 20, y = route.start.y, z = 10, bucket = 0 } }
    end
    clock = sr.opensAt - 70
    for _ = 1, 6 do run(function() PaddockRaces.tick(clock) end) end
    run(function() PaddockLive.tick(clock) end)
    check("a street route with a road line is never staged as a grid street run (L247)", PaddockLive.byRace[sr.raceId] == nil
        and PaddockLive.onBubble(sr.routeId))
    -- the pre-grid
    replies = {}
    clock = sr.opensAt - 20
    -- KB-238: a car comes up EMPTY and Pace does not have it; its driver is seated only once the player's game has had
    -- it for bubbleSeatDelayMs (past the engine's spawn physics cycle, where every crashing seat mount landed)
    clock = clock + 0.5; run(function() PaddockBubble.tick() end)
    do
        local b0 = PaddockBubble.byRace[sr.raceId]
        local up, empty = 0, 0
        for _, car in pairs(b0 and b0.cars or {}) do
            up = up + 1
            if not car.seated and not car.npc and (VEH[car.vid].driver == nil) then empty = empty + 1 end
        end
        check(("cars come up empty, no driver yet and not Pace's (%d of %d, %d added)"):format(empty, up, #bubblePace.adds),
            up >= 1 and empty == up and #bubblePace.adds == 0)
        -- bubbleSeatDelayMs 0 (owner: no empty cars): seated on the next pass once the player's game has the car
        clock = clock + 0.5; run(function() PaddockBubble.tick() end)
        local seatedNext = 0
        for _, car in pairs(b0.cars) do if car.seated and car.npc then seatedNext = seatedNext + 1 end end
        check(("seated as soon as the player's game has them (%d of %d)"):format(seatedNext, up), seatedNext == up)
    end
    for _ = 1, 10 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
    local b = PaddockBubble.byRace[sr.raceId]
    check(("every Pace add came after its car's driver was seated (%d adds)"):format(#bubblePace.adds), (function()
        for _, a in ipairs(bubblePace.adds) do
            local seatedCar = false
            for _, car in pairs(b.cars) do if car.vid == a.vehicleId and car.seated and car.npc then seatedCar = true end end
            if not seatedCar then return false end
        end
        return #bubblePace.adds >= 6 end)())
    local pre, seated = 0, 0
    for _, car in pairs(b and b.cars or {}) do
        pre = pre + 1
        if car.npc and VEH[car.vid] and VEH[car.vid].driver == car.npc then seated = seated + 1 end
    end
    check(("the street grid is up before the lights (%d cars at %d s out)"):format(pre, math.floor(sr.opensAt - clock)), pre >= 6 and sr.state ~= "running")
    check(("every car on the grid has its driver in the seat (%d of %d)"):format(seated, pre), seated == pre)
    check("no car was set down on the player", (function()
        for _, car in pairs(b.cars) do if Live.dist(VEH[car.vid].pos, POS[1]) <= 6 then return false end end
        return true end)())
    -- L250: the grid is the lane-based bake (tools/bake-grids.py): every pre-grid car stands on its slot, on a lane
    -- centreline, and no two closer than 3 m (01:36: twelve cars 14-77 m off the road on a slope; Hill Abode: eight
    -- behind a mansion gate)
    local profile = NcmCore.get("data.grid_profiles").forRoot(sr.routeId)
    local baked, note = PaddockLive.gridSlots(route, 12, profile)
    local onSlot, closest = 0, math.huge
    local list = {}
    for _, car in pairs(b.cars) do list[#list + 1] = VEH[car.vid].pos end
    for _, pos in ipairs(list) do
        for _, sl in ipairs(baked) do if Live.dist(pos, sl) <= 1.0 then onSlot = onSlot + 1 break end end
    end
    for i = 1, #list do for j = i + 1, #list do closest = math.min(closest, Live.dist(list[i], list[j])) end end
    check(("the street grid is the baked lane grid (%s: %d of %d on their slots, closest two %.1f m)"):format(tostring(note), onSlot, pre, closest),
        (note == "baked" or note == "short") and onSlot == pre and closest >= 3.0)
    local plan = bubblePace.plans[1]
    local nodesWant = 2 + #(route.intermediate or {})
    local legs = PaddockLive.legsFor(route)
    check(("Pace's plan is the route's nodes with a race spline per leg (%d points, %d legs)"):format(plan and #(plan.points or {}) or -1,
        plan and #(plan.legs or {}) or -1),
        plan and #plan.points == nodesWant and plan.legs and #plan.legs == nodesWant - 1 and plan.legs[1] == legs[1]
        and math.abs(plan.points[1].x - route.start.x) < 0.02 and (plan.goInMs or 0) > 0)
    check(("a car off the grid races the first leg (from %s)"):format(tostring(bubblePace.adds[1] and bubblePace.adds[1].from)),
        bubblePace.adds[1] and bubblePace.adds[1].from == 1)
    -- the lights: the model takes over the road line
    clock = sr.opensAt
    for _ = 1, 80 do if sr.state == "running" then break end run(function() PaddockRaces.tick(clock) end) end
    check("the street race runs on its continuous model, on the road", sr.model ~= nil and sr.model.path.source == "road")
    -- 4 s: the field is ~70 m in, still inside bubbleOutM (150 m, owner 2026-10-01) of a player at the start
    for _ = 1, 8 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
    local moved = 0
    for _, car in pairs(b.cars) do if (car.lastD or 0) > 30 then moved = moved + 1 end end
    check(("the grid races off on the road (%d cars past 30 m)"):format(moved), moved >= 4)
    -- the player goes away: every car goes back to the model, its driver out of the seat first
    local away = PaddockBubble.stats.handedBack
    POS = { [1] = { x = 6000, y = -6000, z = 0, bucket = 0 } }
    for _ = 1, 4 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
    check(("beyond bubbleOutM every car is handed back (%d)"):format(PaddockBubble.stats.handedBack - away), next(b.cars) == nil
        and PaddockBubble.stats.handedBack - away >= 6)
    check(("never a car removed with its driver still seated (%d)"):format(REMOVED_WITH_DRIVER), REMOVED_WITH_DRIVER == 0)
    -- every car Pace was given is taken back (a car handed back before Pace ever had it is owed no remove: L296's
    -- slower street seed moved the harness timing enough to hand one back while its driver was still being seated)
    local stillHeld = 0
    for _ in pairs(bubblePace.held) do stillHeld = stillHeld + 1 end
    check(("Pace was told of every car leaving (%d removes, %d still held)"):format(bubblePace.removes, stillHeld), stillHeld == 0 and bubblePace.removes > 0)
    check("nothing of the race is left on the road", next(VEH) == nil)
    -- ...and meets the field again further down the road: the cars come back in ON the road, driver seated, each on
    -- the leg it is in (IDEA-786: as many times a race as it takes)
    local pts = sr.model.path.points
    local tMs = (clock - sr.modelGoAt) * 1000
    local leadD = 0
    for _, id in ipairs(sr.model.order) do local p = R.carAt(sr.model, id, tMs); if p and p.d > leadD then leadD = p.d end end
    local meetD = math.min(sr.model.lengthM * 0.8, leadD + 600)
    local meet = Live.along(pts, meetD / sr.model.lengthM)
    POS = { [1] = { x = meet.x + 10, y = meet.y, z = 10, bucket = 0 } }
    local addsBefore, spawnedBefore = #bubblePace.adds, PaddockBubble.stats.spawned
    for _ = 1, 400 do
        clock = clock + 0.5
        run(function() PaddockBubble.tick() end)
        -- three in at once, each seated
        local seatedNow = 0
        for _, car in pairs(b.cars) do if car.seated then seatedNow = seatedNow + 1 end end
        if seatedNow >= 3 then break end
    end
    local again, onRoad, seated2, legOk = 0, 0, 0, 0
    -- the cars past their one-pass seat handshake (a car that came in this very pass is still being reported)
    local fresh = 0
    for _, car in pairs(b.cars) do
        if car.seated then
            again = again + 1
            if Live.distToPath(pts, car.pos) < 3 then onRoad = onRoad + 1 end
            if car.npc and VEH[car.vid] and VEH[car.vid].driver == car.npc then seated2 = seated2 + 1 end
        elseif not car.npc and VEH[car.vid] and VEH[car.vid].driver == nil then
            fresh = fresh + 1
        end
    end
    check(("no car is past its handshake without a driver (%d waiting this pass)"):format(fresh), fresh + again == (function()
        local n = 0 for _ in pairs(b.cars) do n = n + 1 end return n end)())
    for i = addsBefore + 1, #bubblePace.adds do
        local a = bubblePace.adds[i]
        for _, car in pairs(b.cars) do
            if car.vid == a.vehicleId then
                -- `from` is the 0-based index of the node it heads for: the end of the leg its distance falls in
                local nd, want = sr.model.path.nodeD, nil
                for k = 2, #nd do if nd[k] > (car.spawnD or 0) then want = k break end end
                if a.from == (want or #nd) - 1 then legOk = legOk + 1 end
            end
        end
    end
    check(("the field comes back in where the player meets it (%d cars)"):format(again), again >= 3)
    check(("set down on the road line (%d of %d)"):format(onRoad, again), onRoad == again)
    check(("with a driver in every seat (%d of %d)"):format(seated2, again), seated2 == again)
    check(("each on the leg its distance falls in (%d of %d)"):format(legOk, again), legOk == again)
    -- the stream line (KB-238): the player's game reports a car's state change; the server answers with the distance,
    -- written in that player's own log
    do
        local anyCar
        for _, car in pairs(b.cars) do if car.seated then anyCar = car break end end
        replies = {}
        source = 1
        events["ncm:paddock.bubble.stream"]({ raceId = sr.raceId, vehicleId = anyCar.vid, state = "true|42|1|true" })
        local line
        for _, r in ipairs(replies) do if r.name == "ncm:paddock.bubble.streamline" and r.pid == 1 then line = r.body end end
        local d = line and tonumber(line:match("at (%d+) m"))
        check(("a stream change comes back as a STREAMLINE with its distance (%s)"):format(tostring(line)),
            d ~= nil and math.abs(d - Live.dist(POS[1], Open77.vehicles.getPosition(anyCar.vid))) <= 1 and line:find("seated", 1, true) ~= nil)
    end
    -- its Pace player leaves while another player (no Pace) stays beside the cars: they go back all the same -- a car
    -- is driven by one client, and kept it would sit at the edge of that client's streaming (KB-238)
    local hostGone = PaddockBubble.stats.handedBack
    POS = { [1] = { x = 6000, y = -6000, z = 0, bucket = 0 }, [2] = { x = meet.x + 10, y = meet.y, z = 10, bucket = 0 } }
    for _ = 1, 4 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
    check(("cars whose Pace player left go back, whoever else is near (%d)"):format(PaddockBubble.stats.handedBack - hostGone),
        next(b.cars) == nil and PaddockBubble.stats.handedBack - hostGone == again + fresh and REMOVED_WITH_DRIVER == 0)
    -- away again, and the race finishes on the model with every anchor applied
    POS = { [1] = { x = 6000, y = -6000, z = 0, bucket = 0 } }
    local steps = 0
    while sr.state == "running" and steps < 6000 do
        steps = steps + 1
        clock = clock + 0.5
        run(function() PaddockBubble.tick() end)
        if steps % 10 == 0 then run(function() PaddockRaces.tick(math.floor(clock)) end) end
    end
    for _ = 1, 6 do
        if DB.race[sr.raceId].state == "resolved" then break end
        clock = clock + 10
        run(function() PaddockRaces.tick(math.floor(clock)) end)
    end
    check(("never a car removed with its driver still seated, all race (%d)"):format(REMOVED_WITH_DRIVER), REMOVED_WITH_DRIVER == 0)
    check("the race resolved with the bubble's stretches in it: MIXED (" .. tostring(DB.race[sr.raceId].provenance) .. ")",
        DB.race[sr.raceId].state == "resolved" and DB.race[sr.raceId].provenance == "mixed")
    local rows = 0
    for _, r in ipairs(DB.result) do if r.race_id == sr.raceId then rows = rows + 1 end end
    check(("every car is classified (%d of %d)"):format(rows, #sr.frozen.grid), rows == #sr.frozen.grid)
    check("nothing is left on the road", next(VEH) == nil)
    PACE_HOOK = prevHook
    PaddockLive.paceClients[1] = nil
    POS = {}
    queue = {}
end

-- KB-242 (20:24): a player near the route's far end at staging stages nothing (there is no grid run); the race is the
-- model's, and the bubble brings in only the cars that reach that player.
do
    local farRace = streetRace("street_b", 90)
    local fr = PaddockWorld.route(farRace.routeId)
    POS = { [1] = { x = fr.finish.x + 40, y = fr.finish.y, z = 10, bucket = 0 } }
    local lrf = runLive(farRace)
    check("a player at the far end, not the grid, never hosts a street run (KB-242)", (not lrf or lrf.state == "skipped") and next(VEH) == nil)
    queue = {}
end

local race4 = streetRace("street_a", 126)
POS = { [1] = { x = 6000, y = -6000, z = 0, bucket = 0 } }                 -- far away at staging: no street race
clock = race4.opensAt - 70
for _ = 1, 6 do run(function() PaddockRaces.tick(clock) end) end
run(function() PaddockLive.tick(clock) end)
check("with nobody near at staging, no street race is staged", not PaddockLive.byRace[race4.raceId] or PaddockLive.byRace[race4.raceId].state == "skipped")
clock = race4.opensAt
-- one overdue race starts per pass, earliest first; the harness's clock jumps leave a backlog (L249: regional races
-- now share the evening with the streets)
for _ = 1, 60 do if race4.state == "running" then break end run(function() PaddockRaces.tick(clock) end) end
check("the race runs on its continuous model (" .. tostring(race4.state) .. ")", race4.state == "running" and race4.model ~= nil)
local path4 = race4.model.path.points
local stand = path4[math.floor(#path4 * 0.55)]
POS = { [1] = { x = stand.x + 15, y = stand.y, z = 10, bucket = 0 } }        -- the player walks to the middle of the route
local maxCars, steps4 = 0, 0
local spawned4 = PaddockBubble.stats.spawned
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
-- L245/L247: a street race is the engine's racer on race splines, or nothing. A player without Pace brings no car in:
-- the model runs the race and LIVE shows it.
check(("without Pace near, a street race stays in the model: nothing spawns in the bubble (%d spawned)"):format(bs.spawned - spawned4), bs.spawned == spawned4 and maxCars == 0)
check(("a bubble pass fits the quota (max slice %d)"):format(maxSlice), maxSlice < 400000)
check("the race resolved on the model's own result", DB.race[race4.raceId].state == "resolved"
    and (DB.race[race4.raceId].provenance or "simulated") == "simulated")
local rows4 = 0
for _, r in ipairs(DB.result) do if r.race_id == race4.raceId then rows4 = rows4 + 1 end end
check("every car is classified", rows4 == #race4.frozen.grid)
check("nothing is left on the road", next(VEH) == nil)
POS = {}

-- an OVAL on the continuous model, the Pace plugin near (KB-223): never a grid street run; the field comes in at
-- SP's formation laid along the ring, spaced; the line goes to that player's Pace once as a dynamic plan, and every
-- car joins it with car.add -- no platform route for any of them
GlobalState = GlobalState or {}            -- the platform's replicated state table (ncm_world reads what Paddock puts here)
local race5 = streetRace("street_a", 168)
race5.routeId = "oval_corpo_circle"
local ring5 = PaddockWorld.route("oval_corpo_circle")
POS = { [1] = { x = ring5.start.x - 15, y = ring5.start.y - 25, z = 8, bucket = 0 } }
PaddockLive.paceClients[1] = { ok = true, version = "0.8.1" }
clock = race5.opensAt - 70
for _ = 1, 6 do run(function() PaddockRaces.tick(clock) end) end
run(function() PaddockLive.tick(clock) end)
check("an oval is never staged as a grid street run", PaddockLive.byRace[race5.raceId] == nil)
-- the pre-grid (owner, 05:08): 30 s before the lights the frozen grid comes up on its slots, held by Pace
replies = {}
clock = race5.opensAt - 20
run(function() PaddockBubble.tick() end)
check("Pace 0.8.1 cannot bring in an oval car without closed-spline support", next(VEH) == nil)
PaddockLive.paceClients[1] = { ok = true, version = "0.8.2" }
for _ = 1, 8 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
local preCars, preHeld, closed5 = 0, false, false
for _ in pairs(VEH) do preCars = preCars + 1 end
for _, r in ipairs(replies) do
    if r.name == "ncm:paddock.bubble.plan" and r.body.part == 1 then
        preHeld = (r.body.goInMs or 0) > 0
        closed5 = r.body.loopSpline == "$/mod/ncm_pace/#leg_oval_corpo_circle__loop" and r.body.legs == nil
    end
end
check(("the grid is up before the lights (%d cars at %d s out)"):format(preCars, math.floor(race5.opensAt - clock)), preCars >= 6 and race5.state ~= "running")
local pub5 = false
for _, e in ipairs(GlobalState.ncmPaddockRaces or {}) do if e.id == race5.raceId and #(e.points or {}) >= 8 then pub5 = true end end
check("the oval's ring is published for ncm_world to keep its own traffic out", pub5)
check("and Pace holds it until they go (the plan's go is still ahead)", preHeld)
check("the oval plan names its one closed race spline", closed5)
-- Pace's marks still count lap progress; the closed spline steers the car.
local planPts5, addFrom5 = 0, {}
for _, r in ipairs(replies) do
    if r.name == "ncm:paddock.bubble.plan" then planPts5 = planPts5 + #(r.body.points or {}) end
    if r.name == "ncm:paddock.bubble.car" and r.body.op == "add" then addFrom5[#addFrom5 + 1] = r.body.from end
end
local expect5 = 1 + ring5.oval.laps * #ring5.oval.loop
check(("Pace gets the marks lap after lap (%d points, expected %d)"):format(planPts5, expect5), planPts5 == expect5)
check(("and a car off the grid starts for the second mark (from %s)"):format(tostring(addFrom5[1])), addFrom5[1] == 1)
clock = race5.opensAt
for _ = 1, 80 do if race5.state == "running" then break end run(function() PaddockRaces.tick(clock) end) end
check("the oval runs on its continuous model, on the ring", race5.model ~= nil and race5.model.path.source == "ring")
for _ = 1, 16 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
local plans5, adds5, routes5 = 0, 0, 0
for _, r in ipairs(replies) do
    if r.name == "ncm:paddock.bubble.plan" and r.body.part == 1 then plans5 = plans5 + 1 end
    if r.name == "ncm:paddock.bubble.car" and r.body.op == "add" then adds5 = adds5 + 1 end
end
local cars5 = {}
for _, v in pairs(VEH) do cars5[#cars5 + 1] = v; if v.route then routes5 = routes5 + 1 end end
check(("the line went to the Pace player once (%d)"):format(plans5), plans5 == 1)
-- the sim, modelled (owner, 05:53): after the lights each car holds ITS OWN sim pace, not one shared ceiling
local setBy5, distinct5 = {}, {}
for _, r in ipairs(replies) do
    if r.name == "ncm:paddock.bubble.car" and r.body.op == "set" then setBy5[r.body.vehicleId] = r.body.speed end
end
local nSet5 = 0
for _, v in pairs(setBy5) do nSet5 = nSet5 + 1; distinct5[v] = true end
local nDistinct5 = 0
for _ in pairs(distinct5) do nDistinct5 = nDistinct5 + 1 end
check(("each car follows its own sim pace (%d cars set, %d different ceilings)"):format(nSet5, nDistinct5), nSet5 >= 6 and nDistinct5 >= 3)
check(("every physical car joined Pace (%d cars, %d car.add)"):format(#cars5, adds5), #cars5 >= 6 and adds5 == #cars5)
check(("and none was given a platform route (%d)"):format(routes5), routes5 == 0)
local closest5 = math.huge
for i = 1, #cars5 do for j = i + 1, #cars5 do
    local a, b = cars5[i].pos, cars5[j].pos
    closest5 = math.min(closest5, math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2))
end end
check(("no two cars set down on each other (closest %.1f m, SP rows 12 m / columns 4 m)"):format(closest5), closest5 >= 7)
local offLine5 = 0
for _, v in ipairs(cars5) do
    offLine5 = math.max(offLine5, NcmCore.get("paddock.live").distToPath(race5.model.path.points, v.pos))
end
check(("every car near the spline's road line, including the grid (%.1f m)"):format(offLine5), offLine5 <= 9)
PaddockLive.paceClients[1] = nil
POS = { [1] = { x = ring5.start.x + 5000, y = ring5.start.y, z = 8, bucket = 0 } }
for _ = 1, 4 do clock = clock + 0.5; run(function() PaddockBubble.tick() end) end
check("the oval's cars go back to the model when the player leaves", next(VEH) == nil)
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
check("a second team is refused by the One-Team Rule", #W.orgOrder == 171 and ledgerTotal("driver-2") == 25000)
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

-- ---------------------------------------------------------------- L250: a mixed grid, NPCs and humans
do
    local Mixed = NcmCore.get("paddock.mixed")
    run(function() PaddockRaces.materialise(clock) end)
    local mr
    for _, r in pairs(PaddockRaces.byId) do
        local rt = PaddockWorld.route(r.routeId)
        if r.tier == "street" and r.state == "scheduled" and not r.frozen and r.opensAt >= clock + 1500 and rt and not rt.oval
            and (not mr or r.opensAt < mr.opensAt) then mr = r end
    end
    clock = mr.opensAt - 1200
    check("a street race 20 min out is not frozen yet (entries are open)", mr.frozen == nil)
    local D1, D2, D3 = "0a1b2c3d-4e5f-4061-8a7b-9c0d1e2f3a4b", "1b2c3d4e-5f60-4172-9b8c-0d1e2f3a4b5c", "2c3d4e5f-6071-4283-8c9d-1e2f3a4b5c6d"
    EMITTED = {}
    TriggerEvent("ncm:paddock.entry", { raceId = mr.raceId, driverId = D1, display = "Owner", state = "entered", qualiMs = 1000, enteredAt = clock })
    TriggerEvent("ncm:paddock.entry", { raceId = mr.raceId, driverId = D2, display = "Late Joiner", state = "entered", enteredAt = clock })
    TriggerEvent("ncm:paddock.entry", { raceId = mr.raceId, driverId = D3, display = "Changed Mind", state = "entered", enteredAt = clock })
    TriggerEvent("ncm:paddock.entry", { raceId = mr.raceId, driverId = D3, display = "Changed Mind", state = "withdrawn", enteredAt = clock })
    local npcAlone = #NcmCore.get("paddock.world").raceField(W, mr)
    clock = mr.opensAt - 600
    run(function() PaddockRaces.freeze(mr) end)
    local K1, K2, K3 = Mixed.personKey(D1), Mixed.personKey(D2), Mixed.personKey(D3)
    local g = mr.frozen.grid
    check(("the field keeps its size: two humans took the places of the last two NPCs (%d on the grid, %d turned up)"):format(#g, npcAlone),
        #g == npcAlone and mr.frozen.humans[K1] and mr.frozen.humans[K2] and not mr.frozen.humans[K3])
    check("the grid is qualifying time: the fastest human is on pole, the unqualified one at the back", g[1] == K1 and g[#g] == K2
        and mr.frozen.quali[K1] == 1000 and mr.frozen.quali[g[2]] ~= nil)
    local sent
    for _, e in ipairs(EMITTED) do if e.name == "ncm:paddock.grid" and e.args[1] == mr.raceId then sent = e.args[2] end end
    check("the league is sent each human's slot on the lane grid", sent and sent.slots[D1] and sent.slots[D1].slot == 1
        and sent.slots[D2].slot == #g and sent.fieldSize == #g and sent.greenAt == mr.opensAt and sent.slots[D1].yaw ~= nil)
    TriggerEvent("ncm:paddock.entry", { raceId = mr.raceId, driverId = D3, display = "Too Late", state = "entered", enteredAt = clock })
    check("an entry after the freeze is not on the grid", not mr.frozen.humans[K3] and #mr.frozen.grid == #g)
    check("Billie will not write paper for a driver entered in that league", PaddockHumans.enteredInSeries(D1, mr.seriesId))
    clock = mr.opensAt
    run(function() PaddockRaces.run(mr, clock) end)
    local simHumans = 0
    for _, e in ipairs(mr.result.entrants) do if Mixed.isHuman(e.id) then simHumans = simHumans + 1 end end
    check(("the sim races the NPCs only (%d entrants, no humans)"):format(#mr.result.entrants), simHumans == 0 and #mr.result.entrants == #g - 2)
    clock = mr.closesAt + 1
    check("the close waits for the humans' results", PaddockHumans.holds(mr, clock))
    local winMs = mr.result.entrants[1].finishMs
    TriggerEvent("ncm:paddock.human.result", mr.raceId, { { driverId = D1, state = "finished", finishMs = winMs - 1500, progressPct = 100 },
        { driverId = D2, state = "dnf", progressPct = 40, dnfReason = "forfeit" } })
    check("and closes once they are in", not PaddockHumans.holds(mr, clock))
    EMITTED = {}
    run(function() PaddockRaces.resolve(mr, clock) end)
    local cls
    for _, e in ipairs(EMITTED) do if e.name == "ncm:paddock.classified" and e.args[1] == mr.raceId then cls = e.args[2] end end
    check(("the league hears the whole field's classification (owner P%s of %s)"):format(tostring(cls and cls.places[D1]), tostring(cls and cls.fieldSize)),
        cls and cls.places[D1] == 1 and cls.fieldSize == #g and cls.places[D2] and cls.places[D2] > 1)
    local own, npcWinner
    for _, r in ipairs(DB.result) do
        if r.race_id == mr.raceId and r.person_id == K1 then own = r end
        if r.race_id == mr.raceId and r.position == 2 then npcWinner = r end
    end
    check("the result rows carry the human, first, with no Paddock purse", own and own.position == 1 and own.purse == 0 and own.state == "finished")
    check("the NPC who would have won is second, and paid for second", npcWinner and not Mixed.isHuman(npcWinner.person_id) and (npcWinner.purse or 0) > 0)
    check("the human is named in the Paddock as they entered", PaddockWorld.personName(K1) == "Owner" and mr.state == "resolved")
end

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
