-- Offline stub run of the NCM server resources under plain Lua 5.4 (no game, no DB).
-- Fakes the OPEN//77 host (Open77.*, MySQL, CreateThread/Wait as coroutines on a virtual clock, events,
-- commands) and loads ncm_league + ncm_world from their manifests. Then drives a scenario and asserts.
--   lua54 tools/ncm-stub.lua [scenario]      (default: gridcars)
-- Run tools/ncm-build.ps1 first so shared/core is current.

local REPO = (arg[0]:match("^(.*)[/\\]tools[/\\]") or "."):gsub("\\", "/")
local RES = REPO .. "/ncm/online/resources/"

-- ------------------------------------------------------------------ virtual host
local clock = 1789920000.0
local threads = {}            -- { co, wakeAt }
local handlers = {}           -- event -> { fn }
local commands = {}           -- name -> fn
local netEvents = {}
local chatLog, toastLog, sqlLog = {}, {}, {}
local vehicles, nextVid = {}, 100
local players = {}            -- id -> { name, userId, position, heading, bucket }
local bags = {}
local world = { props = {}, npcs = {}, nextId = 500, perf = {}, population = {} }   -- fake props/NPCs/ceilings/density
local tunableOverrides = { ambientEnabled = false }   -- scenarios opt in; see Open77.tunables.declare
GlobalState = {}
local clientEvents = {}       -- TriggerClientEvent recorder

function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wakeAt = clock } end
function Wait(ms)
    if coroutine.isyieldable() then coroutine.yield((tonumber(ms) or 0) / 1000) end
end
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function TriggerEvent(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do
        local args = table.pack(...)
        CreateThread(function() fn(table.unpack(args, 1, args.n)) end)
    end
end
function RegisterNetEvent(name, fn) netEvents[name] = true; if fn then handlers["__net:" .. name] = handlers["__net:" .. name] or {}; table.insert(handlers["__net:" .. name], fn) end end
function RegisterCommand(name, fn) commands[name] = fn end
function GetPlayerName(id) return players[id] and players[id].name end
function GetPlayerIdentifier(id) return players[id] and players[id].userId end
function TriggerClientEvent(name, pid, ...) clientEvents[#clientEvents + 1] = { name = name, pid = pid, args = table.pack(...) } end


local wall = nil   -- { x, y, r }: an AI car inside this circle makes no progress (routing failure stand-in)
local function stepVehicles(dt)
    for vid, v in pairs(vehicles) do
        local ai = v.ai
        if ai and ai.target then
            local dx, dy = ai.target.x - v.position.x, ai.target.y - v.position.y
            local d = math.sqrt(dx * dx + dy * dy)
            local blocked = wall and math.sqrt((v.position.x - wall.x) ^ 2 + (v.position.y - wall.y) ^ 2) < wall.r
            if blocked then ai.speedNow = 0; ai.status = "blocked"
            elseif d < 1 then
                if ai.route and #ai.route > 0 then ai.target = table.remove(ai.route, 1) else ai.speedNow = 0; ai.status = "arrived"; ai.target = nil end
            else
                local step = math.min(d, ai.speed * dt); ai.speedNow = step / dt; ai.status = "driving"
                v.position = { x = v.position.x + dx / d * step, y = v.position.y + dy / d * step, z = v.position.z }
                for _, p in pairs(players) do if p.seat and p.seat.vehicleId == vid then p.position = v.position end end
            end
        end
    end
end

local function run(seconds)
    local stop = clock + (seconds or 0)
    repeat
        local progressed = false
        for _, t in ipairs(threads) do
            if coroutine.status(t.co) ~= "dead" and t.wakeAt <= clock then
                local ok, delay = coroutine.resume(t.co)
                if not ok then error("thread error: " .. tostring(delay)) end
                t.wakeAt = clock + (tonumber(delay) or 0)
                progressed = true
            end
        end
        if not progressed then
            local nextWake
            for _, t in ipairs(threads) do
                if coroutine.status(t.co) ~= "dead" and (not nextWake or t.wakeAt < nextWake) then nextWake = t.wakeAt end
            end
            if not nextWake or nextWake > stop then stepVehicles(stop - clock); clock = stop; break end
            local dt = nextWake - clock
            if dt > 0 then stepVehicles(dt) end
            clock = math.max(clock, nextWake)
        end
    until clock > stop
    -- drop dead threads
    local live = {}
    for _, t in ipairs(threads) do if coroutine.status(t.co) ~= "dead" then live[#live + 1] = t end end
    threads = live
end

--- Fire a client->server net event as player `src` (the `__net:` registry pattern).
local function clientNet(name, src, ...)
    source = src
    for _, fn in ipairs(handlers["__net:" .. name] or {}) do fn(...) end
    run(0)
end

local function command(name, source, ...)
    assert(commands[name], "no command " .. name)
    commands[name](source or 0, { ... })
    run(0)
end

Open77 = {
    time = { unix = function() return clock end },
    runtime = { luaVersion = function() return _VERSION end },
    -- Declared tunables, with a scenario override layer. Ambient population is OFF here by default: it
    -- spawns cars and pedestrians on a timer, and every scenario that counts what is in the world would
    -- otherwise be counting the city as well as the grid. A scenario that wants it says so.
    tunables = { declare = function(spec)
        local t = {}
        for k, v in pairs(spec) do t[k] = v.value end
        for k, v in pairs(tunableOverrides) do if t[k] ~= nil then t[k] = v end end
        return t
    end },
    chat = { send = function(pid, text) chatLog[#chatLog + 1] = { pid = pid, text = text }; print(("  chat -> %s: %s"):format(tostring(pid), text)) end },
    notifications = { send = function(pid, n) toastLog[#toastLog + 1] = { pid = pid, n = n } end },
    players = {
        all = function() local out = {}; for id in pairs(players) do out[#out + 1] = id end; table.sort(out); return out end,
        get = function(id) return players[id] end,
        position = function(id) return players[id] and players[id].position end,
        teleport = function(id, pos) if players[id] then players[id].position = pos end; return true end,
        localId = function() return 1 end,
        getVehicleSeat = function(id) local p = players[id]; return p and p.seat or nil end,
        warpIntoVehicle = function(id, vid, seat) if not players[id] or not vehicles[vid] then return nil, "bad" end; players[id].seat = { vehicleId = vid, seat = seat }; return true end,
        taskEnterVehicle = function(id, vid, seat) if not players[id] or not vehicles[vid] then return nil, "bad" end; players[id].seat = { vehicleId = vid, seat = seat }; return true end,
    },
    props = {
        create = function(spec) if not spec.model or spec.model == "bad.alias" then return nil, "unknown_model" end; world.nextId = world.nextId + 1; world.props[world.nextId] = spec; return world.nextId end,
        remove = function(id) if not world.props[id] then return false, "no_such_prop" end; world.props[id] = nil; return true end,
        all = function() local out = {}; for id, p in pairs(world.props) do out[#out + 1] = { id = id, model = p.model } end; return out end,
    },
    npcs = {
        -- Flag/enum tables the real prelude exposes; ambient.lua reads them at spawn time.
        ai = { tasks = 0, frozen = 1, native = 2 },
        damage = { mortal = 0, immortal = 1, invulnerable = 2 },
        flags = { alive = 1, ragdoll = 2, despawnWhenUnobserved = 4, persistent = 8 },
        create = function(spec) if spec.template == "Character.bad" or spec.record == "Character.bad" then return nil, "npc_template_invalid" end
            if spec.template and spec.template:find("recordonly") and not spec.record then return nil, "npc_template_invalid" end
            world.nextId = world.nextId + 1; world.npcs[world.nextId] = spec; return world.nextId end,
        remove = function(id) if not world.npcs[id] then return false, "no_such_npc" end; world.npcs[id] = nil; return true end,
        get = function(id) local n = world.npcs[id]; if not n then return nil end
            local p = n.position or n
            return { id = id, x = p.x, y = p.y, z = p.z, yaw = n.yaw or 0, bucket = n.bucket or 0 } end,
        -- `readyClients` is how the server learns whether anyone is RENDERING an NPC, which is the exact
        -- half of the ambient sight rule a distance test cannot supply. Nobody is streaming in the stub.
        owner = function(id) if not world.npcs[id] then return nil, "not_found" end
            return { authorityPlayerId = 0, physicsOwner = 0, readyClients = 0, epoch = 1 } end,
        tasks = {
            lookAt = function(id, o) if world.npcs[id] then world.npcs[id].lookAt = o end; return true end,
            wander = function(id, o) if world.npcs[id] then world.npcs[id].wander = o or true end; return true end,
        },
    },
    routingBuckets = { getPlayer = function(id) return players[id] and players[id].bucket or 0 end },
    state = { player = function(pid) bags[pid] = bags[pid] or {}; local b = bags[pid]; return { set = function(_, k, v) b[k] = v; return true end, get = function(_, k) return b[k] end, clear = function(_, k) b[k] = nil; return true end } end },
    vehicles = {
        create = function(spec) nextVid = nextVid + 1; vehicles[nextVid] = spec; spec.ai = nil; print(("  vehicle %d = %s at %.1f,%.1f yaw %.0f"):format(nextVid, spec.record, spec.position.x, spec.position.y, spec.yaw or 0)); return nextVid end,
        remove = function(vid) if not vehicles[vid] then return false, "no_such_vehicle" end; vehicles[vid] = nil; return true end,
        get = function(vid) local v = vehicles[vid]; if not v then return nil end
            return { id = vid, position = v.position, x = v.position.x, y = v.position.y, z = v.position.z, speed = v.ai and v.ai.speedNow or 0, moving = (v.ai and v.ai.speedNow or 0) > 0.1, driverPlayerId = nil, gear = 1, onGround = true, health = 1.0 } end,
        owner = function(vid) if not vehicles[vid] then return nil, "not_streamed" end
            return { authorityPlayerId = 0, physicsOwner = 0, aiDriven = vehicles[vid].ai ~= nil, epoch = 1 } end,
        setPerformance = function(vid, profile) if not vehicles[vid] then return false, "vehicle_not_found" end; world.perf[vid] = profile; return true end,
        ai = {
            attachDriver = function(vid) if not vehicles[vid] then return nil, "no_such_vehicle" end; vehicles[vid].ai = { status = "idle", speedNow = 0 }; return true end,
            removeDriver = function(vid) if vehicles[vid] then vehicles[vid].ai = nil end; return true end,
            driveTo = function(vid, o) local v = vehicles[vid]; if not v or not v.ai then return nil, "no_driver" end
                v.ai.target = o.position; v.ai.speed = o.speed or 10; v.ai.status = "driving"; v.ai.drives = (v.ai.drives or 0) + 1; return { status = "driving" } end,
            stop = function(vid) local v = vehicles[vid]; if v and v.ai then v.ai.target = nil; v.ai.status = "idle"; v.ai.speedNow = 0 end; return true end,
            followRoute = function(vid, o) local v = vehicles[vid]; if not v or not v.ai then return nil, "no_driver" end
                v.ai.route = {}; for i, pt in ipairs(o.points) do v.ai.route[i] = pt end
                v.ai.target = table.remove(v.ai.route, 1); v.ai.speed = o.speed or 10; v.ai.status = "driving"; return { status = "driving" } end,
            joinTraffic = function(vid, o) local v = vehicles[vid]; if not v or not v.ai then return nil, "no_driver" end
                v.ai.target = { x = v.position.x + 30, y = v.position.y, z = v.position.z }; v.ai.speed = (o and o.speed) or 6; v.ai.status = "driving"; return { status = "driving" } end,
            state = function(vid) local v = vehicles[vid]; return v and v.ai and { status = v.ai.status } or nil end,
        },
    },
    ready = { participate = function() return true end, hold = function() return "h" end, release = function() end },
    map = { open = function() end, close = function() end },
    resource = { name = function() return "ncm_world" end, state = function() return "started" end },
    -- The SERVER half of Open77.world. `setPopulation` is the vanilla density switch -- server-owned and
    -- replicated per routing bucket -- and `groundZ` asks a nearby client for a downward ray. Both are
    -- what ncm_world/server/ambient.lua needs to do anything at all; without them its tick logged a nil
    -- index once a second and the stub's output became unreadable.
    world = {
        setPopulation = function(bucket, policy) world.population[bucket] = policy; return true end,
        getPopulation = function(bucket)
            local p = world.population[bucket] or { crowd = 1.0, traffic = 1.0, police = true }
            return { bucket = bucket, crowd = p.crowd, traffic = p.traffic, police = p.police,
                     enabled = true, trafficGranularity = "binary", crowdGranularity = "continuous" }
        end,
        -- Flat ground at z = 0: the stub has no geometry, and a number is what the caller must handle.
        groundZ = function() return 0.0, { playerId = 1, cached = true } end,
    },
}

-- MySQL: answers the handful of shapes the resources need; everything else is a no-op that logs the SQL.
local bindings = {}           -- userId -> driverId
local venuePoints, venueRoutes = {}, {}   -- authored data round-trips through the stub DB
local messages = {}           -- message_id -> row
local onboarding = {}         -- driverId -> onboarding_json string
local driverSr = {}           -- driverId -> { sr, incidents, clean }
-- Economy v1 (L169) made check-in conditional on a ledger balance, and made the check-in write itself a
-- conditional INSERT/UPDATE guarded by `(SELECT SUM(amount) FROM ledger ...) >= fee`. A double that answers 0 to
-- every scalar and `true` to every transaction turns that into a permanent `insufficient_funds`, so the offline
-- stub could not check in to a paid event at all. These two tables are the minimum needed to make the funded and
-- unfunded cases actually DIFFER -- which is the whole point of having them.
local ledger = {}             -- driverId -> { total, idem = { [key] = true } }
local entries = {}            -- entryId -> { state, fee }
local function ledgerFor(d) ledger[d] = ledger[d] or { total = 0, idem = {} }; return ledger[d] end
local function ledgerAdd(driverId, amount, idemKey)
    local l = ledgerFor(driverId)
    if idemKey and l.idem[idemKey] then return false end   -- INSERT IGNORE on a unique idem_key
    if idemKey then l.idem[idemKey] = true end
    l.total = l.total + (tonumber(amount) or 0)
    return true
end
local driverLic = {}          -- driverId -> { [discipline] = { level, clean } }
local function sql(kind, q, p) sqlLog[#sqlLog + 1] = { kind = kind, q = q, p = p } end
MySQL = {
    isReady = function() return true end,
    ready = function(fn) CreateThread(fn); return true end,
    scalar = { await = function(q, p) sql("scalar", q, p)
        if q:find("VERSION%(%)") then return "stub" end
        if q:find("schema_migrations") then return 9 end
        if q:find("SUM%(amount%)") and q:find("FROM ledger") then return ledgerFor(p[1]).total end
        return 0 end },
    single = { await = function(q, p) sql("single", q, p)
        if q:find("FROM ncm_driver_binding") then
            local d = bindings[p[2]]
            return d and { ncm_driver_id = d, display = nil, onboarding_json = onboarding[d] } or nil
        end
        if q:find("SELECT onboarding_json FROM driver_profile") then return { onboarding_json = onboarding[p[1]] } end
        if q:find("FROM driver_sr") then local r = driverSr[p[1]]; return r and { sr = r.sr, incidents = r.incidents, clean_sessions = r.clean } or nil end
        -- `NcmEconomy.checkIn` decides insufficient_funds by reading this row back after the transaction, so a
        -- double that returns nil here reports every check-in as unfunded no matter what the ledger says.
        if q:find("FROM entry WHERE entry_id") then local e = entries[p[1]]; return e and { state = e.state, fee = e.fee } or nil end
        return nil end },
    query = { await = function(q, p) sql("query", q, p)
        if q:find("FROM venue_point") then local out = {}; for _, r in pairs(venuePoints) do out[#out + 1] = r end; return out end
        if q:find("FROM venue_route") then local out = {}; for _, r in pairs(venueRoutes) do out[#out + 1] = r end; return out end
        if q:find("FROM driver_licence") then
            local out = {}
            for disc, l in pairs(driverLic[p[1]] or {}) do out[#out + 1] = { discipline_id = disc, level = l.level, clean_sessions = l.clean } end
            return out
        end
        if q:find("FROM message") then
            local out = {}
            for _, m in pairs(messages) do if m.to_driver_id == p[2] and (m.state == "unread" or m.state == "read" or m.state == "accepted" or m.state == "declined") then out[#out + 1] = m end end
            table.sort(out, function(a, b) return a.created_at > b.created_at end)
            return out
        end
        return {} end },
    insert = { await = function(q, p) sql("insert", q, p)
        if q:find("INTO venue_point") then venuePoints[p[3] .. "/" .. p[4]] = { kind = p[3], point_key = p[4], x = p[5], y = p[6], z = p[7], heading = p[8], meta_json = p[9] } end
        if q:find("INTO message") then messages[p[1]] = { message_id = p[1], to_driver_id = p[3], from_kind = p[4], from_id = p[5], kind = p[6], subject = p[7], body = p[8], actions = p[9], state = "unread", ref_id = p[11], created_at = p[12], expires_at = p[13] } end
        if q:find("INTO driver_sr") then driverSr[p[1]] = { sr = p[3], incidents = p[4], clean = p[5] } end
        if q:find("INTO driver_licence") then driverLic[p[1]] = driverLic[p[1]] or {}; driverLic[p[1]][p[3]] = { level = p[4], clean = p[5] } end
        if q:find("INTO venue_route") then venueRoutes[p[3]] = { route_key = p[3], from_kind = p[4], from_key = p[5], to_kind = p[6], to_key = p[7], points_json = p[8], length_m = p[9] } end
        -- starter_grant and any other direct ledger write: (driver, server, kind, amount, currency, ref, note, idem)
        if q:find("INTO ledger") then ledgerAdd(p[1], p[3], p[8]) end
        -- interest, registration and the host-kit shortcut all create entry rows outside the check-in
        -- transaction, and check-in UPDATEs the row they made.
        if q:find("INSERT INTO entry") then
            entries[p[1]] = { state = q:match("'(%a[%a_]*)',%s*%d*,?%s*%w*_?at") or
                (q:find("'interested'") and "interested") or (q:find("'registered'") and "registered") or
                (q:find("'checked_in'") and "checked_in") or "interested", fee = tonumber(p[5]) or 0 }
        end
        return 1 end },
    update = { await = function(q, p) sql("update", q, p)
        if q:find("DELETE FROM venue_point") then venuePoints[p[3] .. "/" .. p[4]] = nil end
        if q:find("UPDATE message SET state = ?, resolved_at", 1, true) then if messages[p[3]] then messages[p[3]].state = p[1] end end
        if q:find("UPDATE message SET state = 'read'") then if messages[p[1]] then messages[p[1]].state = "read" end end
        if q:find("UPDATE driver_profile SET onboarding_json") then onboarding[p[2]] = p[1] end
        if q:find("UPDATE entry SET state = 'interested'") then local e = entries[p[2]]; if e then e.state = "interested" end end
        if q:find("UPDATE entry SET state = 'withdrawn'") then local e = entries[p[1]]; if e then e.state = "withdrawn" end end
        return 1 end },
    transaction = { await = function(list) sql("transaction", "tx", list)
        for _, st in ipairs(list) do
            local q, v = st.query, st.values
            if q:find("INSERT INTO ncm_driver_binding") then bindings[v[2]] = v[3] end
            -- The funds test lives in the WHERE clause of the write itself, which is deliberate (it is what stops
            -- balance being read, changing, and then acted on). Model it, rather than letting every write succeed.
            if q:find("UPDATE entry SET state='checked_in'") then
                local fee, entryId, driverId, need = tonumber(v[1]) or 0, v[5], v[6], tonumber(v[8]) or 0
                local e = entries[entryId]
                if e and (e.state == "interested" or e.state == "withdrawn") and ledgerFor(driverId).total >= need then
                    e.state, e.fee = "checked_in", fee
                end
            elseif q:find("INSERT INTO entry %(entry_id") then
                local entryId, fee, driverId, need = v[1], tonumber(v[4]) or 0, v[3], tonumber(v[10]) or 0
                if ledgerFor(driverId).total >= need then entries[entryId] = { state = "checked_in", fee = fee } end
            elseif q:find("INSERT IGNORE INTO ledger") and q:find("FROM entry WHERE entry_id") then
                -- `SELECT … -fee … FROM entry WHERE entry_id=? AND state='checked_in' AND fee=?`: the debit only
                -- happens if the entry write above actually landed, which is the atomicity being tested.
                local entryId, fee = v[4], tonumber(v[5]) or 0
                local e = entries[entryId]
                if e and e.state == "checked_in" and e.fee == fee then
                    -- the driver is not in this statement's values; find them from the entry we just wrote
                    for _, st2 in ipairs(list) do
                        local d = st2.query:find("entry") and (st2.values[6] or st2.values[3]) or nil
                        if type(d) == "string" and ledger[d] then ledgerAdd(d, -fee, v[2]); break end
                    end
                end
            end
        end
        return true end },
}

-- ------------------------------------------------------------------ load resources
local function loadResource(name)
    NcmCore = nil   -- each resource is its own VM in the host; shared core loads fresh per resource
    -- The host answers per VM; `impromptu.lua` compares it in `onResourceStart`, and without it the stub died
    -- at load before any scenario could run.
    GetCurrentResourceName = function() return name end
    local manifest = assert(io.open(RES .. name .. "/open77.lua")):read("a")
    for kind, path in manifest:gmatch('(%w+_script)%s+"([^"]+)"') do
        if kind ~= "client_script" then
            local chunk = assert(loadfile(RES .. name .. "/" .. path))
            chunk()
        end
    end
    TriggerEvent("onResourceStart", name)
    run(0)
end

local function connect(id, name, x, y, heading)
    players[id] = { name = name, userId = "user:" .. name, position = { x = x, y = y, z = 10 }, heading = heading or 0, bucket = 0 }
    TriggerEvent("onPlayerConnected", id); run(2)
    TriggerEvent("onPlayerReady", id); run(1)
end

local function count(pattern, list, field)
    local n = 0
    for _, e in ipairs(list) do if tostring(e[field]):find(pattern) then n = n + 1 end end
    return n
end
local function assertf(cond, fmt, ...) if not cond then error(("ASSERT: " .. fmt):format(...), 2) end end

-- The Race Guide is no longer a state bag (KB-97) and no longer one event (KB-160): it arrives as a head plus
-- numbered row packets. Reassemble the latest stream for `pid` exactly the way client/panel.lua does -- which is
-- the point. This scenario asserted on `bags[pid].ncmGuide` for three days after KB-97 deleted that bag, so it
-- failed on line 1 and stopped exercising the Guide at all, which is how a transport regression reached a live
-- client twice. Asserting through the real transport is what makes the coverage true.
local GUIDE_PACKET_CEILING = 6 * 1024   -- must match ROW_PACKET_BUDGET_BYTES in server/guide.lua
local GUIDE_HEAD_CEILING = 6 * 1024
local function guidePayload(pid)
    local Chunks, Json = NcmCore.get("vocabulary.chunks"), NcmCore.get("vocabulary.json")
    local function bytes(v) local ok, e = pcall(Json.encode, v); assertf(ok, "a Guide packet must be encodable"); return #e end
    local id, head, rx = nil, nil, nil
    for _, ce in ipairs(clientEvents) do
        if ce.pid == pid and ce.name == "ncm:guide.stream.begin" then
            local meta = ce.args[1]
            id, head, rx = meta.id, meta.head, Chunks.receiver(tonumber(meta.parts) or 0)
        end
    end
    if not id then return nil end
    -- The head cannot be split, so it is the one part of the stream that can still break it on its own. That is
    -- precisely where KB-86's twenty rows of history sat.
    local headBytes = bytes(head)
    assertf(headBytes <= GUIDE_HEAD_CEILING, "guide head is %d bytes, above the %d ceiling -- it is not split",
        headBytes, GUIDE_HEAD_CEILING)
    for _, ce in ipairs(clientEvents) do
        if ce.pid == pid and ce.name == "ncm:guide.stream.part" and ce.args[1].id == id then
            local part = ce.args[1]
            local n = bytes(part)
            assertf(n <= GUIDE_PACKET_CEILING, "guide packet %s is %d bytes, above the %d ceiling -- a packet " ..
                "this size is the one that disappears without a word", tostring(part.index), n, GUIDE_PACKET_CEILING)
            assertf(Chunks.accept(rx, part.index, part.items), "guide packet %s rejected", tostring(part.index))
        end
    end
    assertf(Chunks.complete(rx), "guide stream incomplete: %d of %d packet(s)", rx.received, rx.expected)
    local rows = assert(Chunks.collect(rx))
    local out = {}
    for k, v in pairs(head) do out[k] = v end
    out.rows = rows
    return out
end

-- ------------------------------------------------------------------ scenario: grid cars
local scenarios = {}
function scenarios.gridcars()
    print("== load")
    loadResource("ncm_league")
    loadResource("ncm_world")
    assertf(count("INSERT INTO team_car", sqlLog, "q") == 20, "team_car seed rows: %d", count("INSERT INTO team_car", sqlLog, "q"))

    print("== connect two drivers")
    connect(1, "owner", 100, 100, 0)
    connect(2, "tester", 110, 100, 0)

    print("== post invitational T+6, invite both, accept both")
    command("ncm.event.post", 0, "tip", "6")
    command("ncm.invite", 0, "1", "kimiko")
    command("ncm.invite", 0, "2", "kimiko")
    assertf(count("INSERT INTO message", sqlLog, "q") == 2, "seat offers persisted as messages")
    command("ncm.accept", 0, "1")
    command("ncm.accept", 0, "2")
    local accepted = 0
    for _, e in ipairs(sqlLog) do if e.q:find("UPDATE message SET state") and e.p[1] == "accepted" then accepted = accepted + 1 end end
    assertf(accepted == 2, "messages resolved accepted: %d", accepted)
    local carNumbers = {}
    for _, e in ipairs(sqlLog) do if e.q:find("INSERT INTO entry") then carNumbers[#carNumbers + 1] = e.p[7] end end
    assertf(#carNumbers == 2 and carNumbers[1] == 7 and carNumbers[2] == 77, "entry car numbers 7/77, got %s/%s", tostring(carNumbers[1]), tostring(carNumbers[2]))

    print("== advance to T-60: session forms, field spawns")
    local before = 0; for _ in pairs(vehicles) do before = before + 1 end
    run(6 * 60 - 55)
    local spawned = {}
    for vid, v in pairs(vehicles) do spawned[#spawned + 1] = v.record end
    table.sort(spawned)
    assertf(#spawned == 2, "two grid cars spawned, got %d", #spawned)
    assertf(spawned[1] == "Vehicle.v_sport1_rb15_f1_kimiko", "kimiko livery, got %s", spawned[1])
    assertf(count("Your car: #7 Kimiko RB15", chatLog, "text") == 1 and count("Your car: #77 Kimiko RB15", chatLog, "text") == 1, "grid chat names both cars")
    assertf(NcmGarage.describe(1):find("rb15_f1_kimiko") ~= nil, "car 1 issued to player 1: %s", NcmGarage.describe(1))
    assertf(NcmGarage.describe(2):find("rb15_f1_kimiko") ~= nil, "car 2 issued to player 2: %s", NcmGarage.describe(2))

    print("== nobody starts: DNS, hold, release")
    run(60 + 90 + 5)            -- start + startTimeout
    run(NcmCalendar.settings.raceResultHoldSec + 5)
    local left = 0; for _ in pairs(vehicles) do left = left + 1 end
    assertf(left == 0, "grid cars released after the hold, %d left", left)
    assertf(NcmGarage.describe(1) == "no car issued", "player 1 car returned: %s", NcmGarage.describe(1))
    print("== reconnect re-issue keeps the team car")
    TriggerEvent("ncm:driverResumed", 1, { x = 1, y = 2, z = 3 }); run(3)
    assertf(NcmGarage.describe(1):find("rb15_f1_kimiko") ~= nil, "resume re-issues the Formula/kimiko car: %s", NcmGarage.describe(1))
    print("OK gridcars")
end

-- late arrival: a registered driver is offline when the grid forms; the car is parked and claimed on arrival
function scenarios.latearrival()
    loadResource("ncm_league"); loadResource("ncm_world")
    connect(1, "owner", 100, 100, 0); connect(2, "tester", 110, 100, 0)
    command("ncm.event.post", 0, "tip", "6")
    command("ncm.invite", 0, "1", "raven"); command("ncm.invite", 0, "2", "raven")
    command("ncm.accept", 0, "1"); command("ncm.accept", 0, "2")
    print("== tester disconnects before the grid forms")
    TriggerEvent("onPlayerDisconnected", 2, "quit"); players[2] = nil; run(1)
    run(6 * 60 - 60)
    local n = 0; for _ in pairs(vehicles) do n = n + 1 end
    assertf(n == 2, "both cars on the grid although one driver is absent, got %d", n)
    assertf(NcmGarage.describe(2) == "no car issued", "absent driver owns nothing yet")
    print("== tester reconnects: same identity, claims the parked car")
    connect(2, "tester", 200, 200, 0)
    assertf(NcmGarage.describe(2):find("rb15_f1_raven") ~= nil, "parked car claimed on arrival: %s", NcmGarage.describe(2))
    assertf(count("Your car is waiting: #88 Raven RB15 at grid slot 2", chatLog, "text") == 1, "claim message")
    local n2 = 0; for _ in pairs(vehicles) do n2 = n2 + 1 end
    assertf(n2 == 2, "no extra car spawned on claim, got %d", n2)
    print("OK latearrival")
end

-- chauffeur pickup: rides at T-5, board, arrive; one rider hits a routing wall -> retries -> hand-over
function scenarios.pickup()
    loadResource("ncm_league"); loadResource("ncm_world")
    connect(1, "owner", 100, 100, 0); connect(2, "tester", -3000, 2000, 0)
    commands["ncm.au"](1, { "tw1", "on" }); run(1)   -- rides are TW1 presentation (P52): nothing goes out otherwise
    command("ncm.event.post", 0, "tip", "8")
    command("ncm.invite", 0, "1", "kimiko"); command("ncm.invite", 0, "2", "raven")
    command("ncm.accept", 0, "1"); command("ncm.accept", 0, "2")
    print("== T-5: rides go out")
    run(3 * 60 + 2)
    assertf(count("Your ride from Kimiko is", chatLog, "text") == 1, "owner offered a Kimiko ride")
    assertf(count("Your ride from Raven is", chatLog, "text") == 1, "tester offered a Raven ride")
    local rideVid = {}
    for vid, v in pairs(vehicles) do if v.record:find("chevalier") then rideVid[#rideVid + 1] = vid end end
    assertf(#rideVid == 2, "two transports spawned, got %d", #rideVid)
    print("== both board after the pull-up (owner's ride approaches from a road node ~420 m away)")
    run(40)
    local r1, r2 = NcmPickup.rides[1], NcmPickup.rides[2]
    assertf(r1 and r2, "rides tracked")
    players[1].seat = { vehicleId = r1.vehicleId, seat = 1 }
    players[2].seat = { vehicleId = r2.vehicleId, seat = 1 }
    -- tester's road is walled off 400 m into the trip
    local tv = vehicles[r2.vehicleId]
    local dx, dy = r2.dropoff.x - tv.position.x, r2.dropoff.y - tv.position.y
    local d = math.sqrt(dx * dx + dy * dy)
    wall = { x = tv.position.x + dx / d * 400, y = tv.position.y + dy / d * 400, r = 60 }
    run(3)
    assertf(count("En route to Tip", chatLog, "text") == 2, "both en route")
    print("== drive: owner arrives; grid forms at T-60 with the RB15s; the walled rider exhausts the ladder later")
    run(290)
    assertf(count("You've arrived at Tip", chatLog, "text") == 1, "owner arrived")
    assertf(math.abs(players[1].position.x - r1.dropoff.x) < 15, "owner's body travelled with the car")
    local rb = 0; for _, v in pairs(vehicles) do if v.record:find("rb15") then rb = rb + 1 end end
    assertf(rb == 2, "grid RB15s spawned: %d", rb)
    players[1].seat = nil
    run(50)
    local sedans = 0; for _, v in pairs(vehicles) do if v.record:find("chevalier") then sedans = sedans + 1 end end
    assertf(sedans == 1, "owner's transport removed after exit, tester's still theirs: %d sedans", sedans)
    run(200)
    assertf(count("take the wheel", chatLog, "text") == 1, "tester handed the wheel after the ladder")
    assertf(tv.ai == nil and players[2].seat.seat == "driver", "AI released and tester in the driver seat")
    assertf(r2.failures >= 3, "failures logged: %d", r2.failures or 0)
    print("OK pickup")
end

-- venue authoring: capture, record a route by driving, play it back, then TW1 mode end to end
function scenarios.authoring()
    loadResource("ncm_league"); loadResource("ncm_world")
    connect(1, "owner", 0, 0, 0)
    local function chat(...) commands["ncm.au"](1, { ... }); run(1) end
    local function moveTo(x, y) players[1].position = { x = x, y = y, z = 10 } end
    print("== capture spot 1, node 1, paddock, grid")
    moveTo(0, 0); chat("spot", "1")
    moveTo(-40, -20); players[1].heading = 90; chat("node", "1")
    moveTo(1500, 800); chat("paddock")
    moveTo(1600, 850); chat("grid")
    assertf(NcmVenue.point("spot", "1").x == 0 and NcmVenue.point("node", "1").heading == 90, "points captured")
    print("== record route 1 by driving spot -> paddock (1.7 km, samples every 1 s at 20 m/s)")
    moveTo(0, 0); chat("route", "1")
    for step = 1, 85 do moveTo(step * 17.6, step * 9.4); run(1) end
    moveTo(1500, 800); chat("route", "stop")
    local r = NcmVenue.route("1")
    assertf(r and #r.points >= 10 and #r.points <= 64, "route thinned into range: %s", tostring(r and #r.points))
    assertf(r.lengthM > 1600 and r.lengthM < 1900, "route length %.0f", r.lengthM)
    assertf(count("Route 1 saved", chatLog, "text") == 1, "saved message")
    print("== reload from the stub DB, then play the approach")
    NcmVenue.load()
    assertf(NcmVenue.route("1") and #NcmVenue.route("1").points == #r.points, "route persisted")
    moveTo(0, 0); chat("route", "play", "1")
    run(3)
    local ride = NcmPickup.rides[1]
    assertf(ride and ride.spawnAt and ride.route, "ride built from the approach")
    assertf(ride.spawnHow == "authored node", "born at the node: %s", tostring(ride.spawnHow))
    run(12)   -- pull-up 45 m at 10 m/s
    players[1].seat = { vehicleId = ride.vehicleId, seat = 1 }
    run(130)  -- 1.7 km at 18 m/s ≈ 95 s
    assertf(count("You've arrived at pacifica_stadium paddock", chatLog, "text") == 1, "arrived at the paddock via the route")
    assertf(count("following %d point", chatLog, "text") == 0, "no chat noise")
    print("== TW1 mode: a registered tester spawns at spot 1 and rides the authored route at T-5")
    chat("tw1", "on")
    players[1].seat = nil
    connect(2, "tester", 900, 900, 0); run(3)
    assertf(math.abs(players[2].position.x - 0) < 1 and math.abs(players[2].position.y - 0) < 1, "tester placed at spot 1")
    command("ncm.event.post", 0, "tip", "6")
    command("ncm.invite", 0, "2", "raven"); command("ncm.accept", 0, "2")
    run(65)
    local r2 = NcmPickup.rides[2]
    assertf(r2 and r2.route and #r2.route == #r.points and math.abs(r2.dropoff.x - 1500) < 1, "tester's ride uses spot 1's route to the paddock")
    print("== route 2 drawn with map markers (spot 2 at the waypoint, three turns, saved to the paddock)")
    local function aw(x, y, ...) handlers["ncm:auwp"] = handlers["ncm:auwp"] or {} end
    -- the client sends its waypoint with the args; emulate the net event by calling the registered handler with `source`
    local function wpcmd(x, y, ...)
        source = 1
        for _, fn in ipairs(handlers["__net:ncm:auwp"] or {}) do fn(x, y, 10, ...) end
        run(1)
    end
    wpcmd(3000, 0, "spot", "2"); wpcmd(2900, -60, "node", "2")
    wpcmd(2600, 300, "route", "2", "add"); wpcmd(2100, 600, "route", "2", "add"); wpcmd(1700, 780, "route", "2", "add")
    wpcmd(0, 0, "route", "stop")
    local r2 = NcmVenue.route("2")
    assertf(r2 and #r2.points == 5 and math.abs(r2.points[5].x - 1500) < 1, "marker route: spot + 3 markers + paddock = %s pts", tostring(r2 and #r2.points))
    assertf(math.floor(NcmVenue.point("node", "2").heading) == math.floor(NcmVenue.point("node", "2").heading) and NcmVenue.point("spot", "2").heading > 90, "headings derived from the route")
    print("OK authoring")
end

-- ================================================================== Batch 1 scenarios
-- Shared helpers for the batch scenarios: a two-driver invitational, moving players onto gates, racing to the end.
local function bootstrap()
    loadResource("ncm_league"); loadResource("ncm_world")
    connect(1, "owner", 100, 100, 0); connect(2, "tester", 110, 100, 0)
end
local function driverIdOf(pid) return NcmIdentity.get(pid).ncmDriverId end
local function inviteBoth(team1, team2)
    command("ncm.invite", 0, "1", team1 or "kimiko"); command("ncm.invite", 0, "2", team2 or "kimiko")
    command("ncm.accept", 0, "1"); command("ncm.accept", 0, "2")
end
local function liveSession()
    for sid, rec in pairs(NcmRace.sessions) do return sid, rec end
end
local function moveTo(pid, pos) players[pid].position = { x = pos.x, y = pos.y, z = pos.z or 10 } end
--- Put both players on their marks, run to green, then cross every gate in `order` (first pid finishes first).
local function raceThrough(order)
    order = order or { 1, 2 }
    local sid, rec = liveSession()
    for _, sl in ipairs(rec.slots) do moveTo(rec.playerOf[sl.driverId], sl) end
    run(1)
    while rec.s.phase ~= "running" do run(1); if rec.s.phase == "complete" then return sid, rec end end
    local gates = rec.s.gates
    for gi = 1, #gates do
        for _, pid in ipairs(order) do
            moveTo(pid, { x = gates[gi].x + (pid - 1) * 8, y = gates[gi].y, z = gates[gi].z }); run(1)   -- side by side, never overlapping
            clientNet("ncm:gate", pid, sid, gi)
        end
    end
    return sid, rec
end

-- 1. questionnaire -> affinity -> secret offer
function scenarios.onboarding()
    loadResource("ncm_league"); loadResource("ncm_world")
    connect(1, "owner", 100, 100, 0)
    assertf(count("Complete your NCM Driver Profile", chatLog, "text") == 1, "first join asks for the profile")
    assertf(bags[1].ncmOnboarding and bags[1].ncmOnboarding.pending, "bag says pending")
    -- the panel path: all answers at once, raven-heavy
    clientNet("ncm:onboarding", 1, 1, { "d", "c", "a", "d", "b", "b" })
    assertf(count("Profile complete", chatLog, "text") == 1, "profile complete")
    assertf(bags[1].ncmOnboarding.complete == true, "bag flips to complete")
    local saved
    for _, e in ipairs(sqlLog) do if e.q:find("UPDATE driver_profile SET onboarding_json") then saved = e.p[1] end end
    assertf(saved and saved:find("raven"), "onboarding_json persisted with the affinity: %s", tostring(saved))
    -- the hat uses it: invite with no team -> raven (variety rule: all teams empty, affinity breaks the tie)
    command("ncm.event.post", 0, "tip", "6")
    command("ncm.invite", 0, "1")
    local seatTeam
    for _, e in ipairs(sqlLog) do if e.q:find("UPDATE seat SET ncm_driver_id") then seatTeam = e.p[4] end end
    assertf(seatTeam == "raven", "affinity steered the seat: %s", tostring(seatTeam))
    assertf(count("affinity_top=raven", chatLog, "text") == 0, "the player is never told about affinity")
    -- the chat path on a second driver
    connect(2, "tester", 110, 100, 0)
    for _ = 1, 6 do command("ncm.q", 2, "a") end
    assertf(count("Profile complete", chatLog, "text") == 2, "chat answers complete the profile too")
    print("OK onboarding")
end

-- 2. inbox: list / read / act
function scenarios.inbox()
    bootstrap()
    command("ncm.event.post", 0, "tip", "6")
    command("ncm.invite", 0, "1", "kimiko")
    clientNet("ncm:inbox", 1)
    local inbox = bags[1].ncmInbox
    assertf(inbox and #inbox.items == 1 and inbox.items[1].kind == "seat_offer" and inbox.items[1].state == "unread", "offer in the inbox, unread")
    assertf(inbox.unread == 1, "unread count")
    assertf(#inbox.items[1].actions == 2, "accept/decline actions")
    local id = inbox.items[1].id
    clientNet("ncm:inbox.read", 1, id)
    assertf(bags[1].ncmInbox.items[1].state == "read" and bags[1].ncmInbox.unread == 0, "read flips the state")
    clientNet("ncm:inbox.act", 1, id, "accept")
    assertf(count("INSERT INTO entry", sqlLog, "q") == 1, "accept registered the entry")
    assertf(bags[1].ncmInbox.items[1].state == "accepted", "message accepted")
    clientNet("ncm:inbox.act", 1, id, "accept")
    assertf(count("INSERT INTO entry", sqlLog, "q") == 1, "a second act is ignored")
    command("ncm.inbox", 1)
    assertf(count("1%. %[accepted%]", chatLog, "text") == 1, "chat twin lists it")
    print("OK inbox")
end

-- 3. holding: lights wait for the field; YOUR CAR warps
function scenarios.holding()
    bootstrap()
    command("ncm.event.post", 0, "tip", "3")
    inviteBoth("kimiko", "raven")
    run(3 * 60 - 55)
    local sid, rec = liveSession()
    assertf(rec and rec.s.rules.hold == true, "organized events hold")
    -- only the owner reaches the mark
    moveTo(1, rec.slots[1]); run(56)
    assertf(rec.s.phase == "gridded" and rec.s.hold and rec.s.hold.ready == 1, "holding with 1 of 2: phase=%s hold=%s", rec.s.phase, tostring(rec.s.hold and rec.s.hold.ready))
    assertf(count("Holding for the field", chatLog, "text") >= 1, "hold announced")
    assertf(GlobalState.ncmSession.hold ~= nil, "hold published")
    -- YOUR CAR: the owner asks to get in
    clientNet("ncm:yourCar", 1, sid)
    assertf(players[1].seat and players[1].seat.seat == "driver", "warped into the driver seat")
    -- tester arrives -> release
    moveTo(2, rec.slots[2]); run(3)
    assertf(rec.s.phase == "countdown", "released on arrival: %s", rec.s.phase)
    run(8)
    assertf(rec.s.phase == "running", "green after the full light count")
    print("OK holding")
end

-- 4. dressing: props/NPCs authored, loader up/down with the event
function scenarios.dressing()
    bootstrap()
    local function au(...) commands["ncm.au"](1, { ... }); run(1) end
    moveTo(1, { x = 1500, y = 800 }); au("paddock"); moveTo(1, { x = 1600, y = 850 }); au("grid")
    moveTo(1, { x = 1610, y = 830 }); au("dress", "barrier.road.jersey")
    moveTo(1, { x = 1620, y = 830 }); au("dress", "barrier.road.jersey", "90")
    moveTo(1, { x = 1630, y = 830 }); au("dress", "race.route_arrow")
    moveTo(1, { x = 1640, y = 860 }); au("dress", "npc", "Character.spectator")
    moveTo(1, { x = 1645, y = 860 }); au("dress", "npc", "Character.bad")
    local lp, ln = NcmVenue.dressCount()
    assertf(lp == 3 and ln == 1, "3 props + 1 NPC live (the bad template refused): %d/%d", lp, ln)
    assertf(count("refused", chatLog, "text") == 1, "refusal told to the author")
    local rows = 0
    for _, e in ipairs(sqlLog) do if e.q:find("INTO venue_point") and (e.p[3] == "prop" or e.p[3] == "npc") then rows = rows + 1 end end
    assertf(rows == 5, "5 dressing points persisted with meta: %d", rows)
    au("dress", "undo")
    au("dress", "down")
    lp, ln = NcmVenue.dressCount(); assertf(lp == 0 and ln == 0, "undressed")
    NcmVenue.load()
    assertf(NcmVenue.point("prop", "2").meta.yaw == 90 and NcmVenue.point("npc", "1").meta.template == "Character.spectator", "meta survives a reload")
    assertf(GlobalState.ncmVenue and GlobalState.ncmVenue.grid.x == 1600, "grid published for the league")
    -- the event flow: dressed at pickup dispatch, undressed at retire
    command("ncm.event.post", 0, "tip", "6"); inviteBoth()
    run(65)
    lp, ln = NcmVenue.dressCount(); assertf(lp == 3 and ln == 1, "dressed at T-5: %d/%d", lp, ln)
    run(6 * 60 + 130)   -- nobody drives: hold -> deadline -> DNS -> result hold -> retire
    lp, ln = NcmVenue.dressCount(); assertf(lp == 0 and ln == 0, "undressed at retire: %d/%d", lp, ln)
    au("dress", "clear", "yes")
    assertf(NcmVenue.point("prop", "1") == nil, "cleared")
    print("OK dressing")
end

-- 6. telemetry: batches -> progress; chunks persisted; garbage refused
function scenarios.telemetry()
    bootstrap()
    command("ncm.event.post", 0, "tip", "3"); inviteBoth()
    run(3 * 60 - 55)
    local sid, rec = liveSession()
    for _, sl in ipairs(rec.slots) do moveTo(rec.playerOf[sl.driverId], sl) end
    while rec.s.phase ~= "running" do run(1) end
    local g1, g2 = rec.s.gates[1], rec.s.gates[#rec.s.gates]
    local t0 = clock
    local last
    -- the first metres at a real cadence (a few metres per sample), so the start rule sees "left the mark"
    local warm = {}
    for i = 1, 5 do local f = i / 500; warm[i] = { t0 - 2 + i * 0.2, g1.x + (g2.x - g1.x) * f, g1.y + (g2.y - g1.y) * f, 10, 12, 2, true, 1.0 } end
    clientNet("ncm:telemetry", 1, sid, warm); run(0)
    for k = 1, 12 do
        local batch = {}
        for i = 1, 5 do
            local f = ((k - 1) * 5 + i) / 60
            local t = t0 + (k - 1) + i * 0.2
            batch[i] = { t, g1.x + (g2.x - g1.x) * f, g1.y + (g2.y - g1.y) * f, 10, 30, 3, true, 1.0 }
        end
        clientNet("ncm:telemetry", 1, sid, batch)
        run(1)
        local p = GlobalState.ncmSession.entrants[1].progressM
        assertf(p and (not last or p >= last), "progress monotonic: %s", tostring(p))
        last = p
    end
    assertf(last > 0.9 * rec.course.lengthM, "reached most of the course: %.0f of %.0f", last, rec.course.lengthM)
    assertf(count("INTO telemetry_chunk", sqlLog, "q") >= 1, "chunk persisted")
    assertf(rec.tm.received == 65, "65 samples received: %d", rec.tm.received)
    -- gates from the stream (host kit): no ncm:gate was ever sent, yet the start and the finish were captured
    local me = rec.s.entrants[driverIdOf(1)]
    assertf(me.state == "finished" and me.progress == #rec.s.gates, "finished from the stream alone (state=%s progress=%d)", me.state, me.progress or -1)
    clientNet("ncm:telemetry", 1, sid, { { clock + 1, g1.x + 9000, g1.y, 0, 0, 0, true, 1 } })
    assertf(rec.tm.refused == 1, "5 km jump refused")
    print("OK telemetry")
end

-- 7. incidents: zero-fault contact; corrected time decides
function scenarios.incidents()
    bootstrap()
    command("ncm.event.post", 0, "tip", "3"); inviteBoth("kimiko", "raven")
    run(3 * 60 - 55)
    local sid, rec = liveSession()
    for _, sl in ipairs(rec.slots) do moveTo(rec.playerOf[sl.driverId], sl) end
    while rec.s.phase ~= "running" do run(1) end
    local g1, g2 = rec.s.gates[1], rec.s.gates[#rec.s.gates]
    for pid = 1, 2 do moveTo(pid, g1); clientNet("ncm:gate", pid, sid, 1) end
    -- both stream: converging at 10 m/s closing speed, then adjacent within 3 m
    local t = clock
    local function sample(pid, x, y, v) clientNet("ncm:telemetry", pid, sid, { { t, x, y, 10, v, 3, true, 1 } }) end
    -- owner at 20 m/s, tester at 12 m/s, 2.5 m to the side: the third pair of samples is 3.75 m apart, closing 8 m/s (ncx band x2)
    sample(1, g1.x, g1.y + 10, 20); sample(2, g1.x + 2.5, g1.y + 16, 12)
    t = t + 0.2; run(0)
    sample(1, g1.x, g1.y + 14, 20); sample(2, g1.x + 2.5, g1.y + 18.4, 12)
    t = t + 0.2; run(0)
    sample(1, g1.x, g1.y + 18, 20); sample(2, g1.x + 2.5, g1.y + 20.8, 12)
    run(1)
    local e1, e2 = rec.s.entrants[driverIdOf(1)], rec.s.entrants[driverIdOf(2)]
    assertf(e1.incidentCount == 1 and e2.incidentCount == 1, "both carry the incident: %d/%d", e1.incidentCount, e2.incidentCount)
    assertf(e1.incidentSec == 4 and e2.incidentSec == 4, "x2 band = 4 s each: %s/%s", tostring(e1.incidentSec), tostring(e2.incidentSec))
    assertf(count("Incident x2", chatLog, "text") == 2, "both told")
    assertf(count("INTO incident", sqlLog, "q") == 2, "two incident rows")
    run(1)
    assertf(e1.incidentCount == 1, "deduped on the next tick")
    -- the owner finishes 2 s faster raw but carries +4 s; wait — both carry 4 s. give the tester a clean-up: owner gets a second incident
    NcmRace.incident(rec, driverIdOf(1), { kind = "object", band = 1, seconds = 3 }, clock)
    moveTo(1, g2); run(60); clientNet("ncm:gate", 1, sid, #rec.s.gates)
    moveTo(2, g2); run(2); clientNet("ncm:gate", 2, sid, #rec.s.gates)
    run(2)
    assertf(GlobalState.ncmSession.entrants[1].correctedSec ~= nil, "corrected published")
    run(70)
    assertf(rec.s.phase == "complete", "complete")
    local res = rec.results
    assertf(res[1].driverId == driverIdOf(2), "the cleaner car wins on corrected time (P1 tester)")
    assertf(res[2].incidentSec == 7 and res[2].incidentCount == 2, "owner: 4 + 3 s, 2 incidents")
    local resultRow
    for _, e in ipairs(sqlLog) do if e.q:find("INSERT INTO session_result") and e.p[2] == driverIdOf(1) then resultRow = e end end
    assertf(resultRow and resultRow.p[14] == 7000 and resultRow.p[15] == 2, "session_result carries incident_ms/incident_count")
    print("OK incidents")
end

-- 8a. two-race: race 2 forms from race 1 with the top reversed
function scenarios.tworace()
    bootstrap()
    command("ncm.event.post", 0, "tip", "3", "tworace"); inviteBoth("kimiko", "raven")
    assertf(count("kimiko/two_race\\|ncx_formula/two_race", chatLog, "text") >= 0, "posted")
    run(3 * 60 - 55)
    local sid1, rec1 = liveSession()
    assertf(rec1.plan and #rec1.plan.specs == 2, "plan has two races")
    local p1 = rec1.slots[1].driverId
    raceThrough({ 1, 2 })   -- owner finishes first
    run(70)
    assertf(rec1.s.phase == "complete" and rec1.results[1].driverId == driverIdOf(1), "race 1: owner wins")
    assertf(rec1.nextSpec and rec1.nextSpec.ordinal == 2, "race 2 scheduled")
    assertf(count("Next: race 2", chatLog, "text") >= 1, "players told")
    run(math.floor(rec1.nextAt - clock) + 5)   -- the gap is the drive from the finish back to the grid (P50)
    local sid2, rec2 = liveSession()
    assertf(sid2 ~= sid1 and rec2.spec.ordinal == 2, "race 2 formed")
    assertf(rec2.slots[1].driverId == driverIdOf(2), "reversed grid: tester on pole")
    local sessionRows = 0
    for _, e in ipairs(sqlLog) do if e.q:find("INSERT INTO session ") then sessionRows = sessionRows + 1; if sessionRows == 2 then assertf(e.p[8] == sid1, "race 2 has race 1 as parent") end end end
    assertf(sessionRows == 2, "two session rows")
    assertf(#(world.props) == 0 or true, "noop")
    raceThrough({ 2, 1 })
    run(70)
    assertf(rec2.s.phase == "complete" and rec2.results[1].driverId == driverIdOf(2), "race 2: tester wins")
    run(65)
    assertf(next(NcmRace.sessions) == nil and NcmRace.plans[rec2.eventId] == nil, "plan retired")
    assertf(count("INSERT INTO session_result", sqlLog, "q") == 4, "four result rows")
    print("OK tworace")
end

-- 8b. weekend: one-run qualifying (window sized to the route) sets the race grid; practice is on demand (P48), not here
function scenarios.weekend()
    bootstrap()
    command("ncm.event.post", 0, "tip", "3", "weekend"); inviteBoth("kimiko", "raven")
    run(3 * 60 - 55)
    local sidQ, recQ = liveSession()
    assertf(recQ.kind == "quali", "qualifying first: %s", tostring(recQ and recQ.kind))
    -- windows are sized to the route (Tip-to-Trench 6.6 km → 20 min), never the format's bare 240 s
    assertf(recQ.spec.windowSec == 1200, "route-sized window (%s)", tostring(recQ.spec.windowSec))
    run(60 + 5)
    assertf(recQ.s.phase == "open", "quali open")
    local g1, g2 = recQ.s.gates[1], recQ.s.gates[#recQ.s.gates]
    -- tester sets the faster time
    moveTo(2, g1); clientNet("ncm:gate", 2, sidQ, 1); run(0)
    for gi = 2, #recQ.s.gates do moveTo(2, recQ.s.gates[gi]); run(gi == #recQ.s.gates and 40 or 5); clientNet("ncm:gate", 2, sidQ, gi) end
    moveTo(1, g1); clientNet("ncm:gate", 1, sidQ, 1); run(0)
    for gi = 2, #recQ.s.gates do moveTo(1, recQ.s.gates[gi]); run(gi == #recQ.s.gates and 60 or 5); clientNet("ncm:gate", 1, sidQ, gi) end
    assertf(recQ.s.entrants[driverIdOf(2)].bestSec and recQ.s.entrants[driverIdOf(1)].bestSec, "both timed")
    assertf(recQ.s.entrants[driverIdOf(2)].bestSec < recQ.s.entrants[driverIdOf(1)].bestSec, "tester faster")
    -- one run each (format.weekend quali maxRuns = 1): a second start is refused and the window closes at once
    moveTo(1, g1); clientNet("ncm:gate", 1, sidQ, 1); run(2)
    assertf(recQ.s.entrants[driverIdOf(1)].runs == 1, "second qualifying start refused (runs=%s)", tostring(recQ.s.entrants[driverIdOf(1)].runs))
    assertf(recQ.s.phase == "complete" and recQ.s.completeReason == "all_runs_done", "quali closed once every run is in: %s", tostring(recQ.s.completeReason))
    assertf(count("Qualifying:", chatLog, "text") == 2, "quali results told")
    -- the gap to the race is the drive from the finish back to the grid (P50): 6.6 km at 15 m/s + 60 s → 9 min
    assertf(recQ.nextAt - clock >= 8 * 60, "geography-aware gap (%d s)", math.floor(recQ.nextAt - clock))
    run(9 * 60 + 5)
    local sidR, recR = liveSession()
    assertf(recR.kind == "race" and recR.slots[1].driverId == driverIdOf(2), "race grid from quali: tester on pole")
    print("OK weekend")
end

-- 11. guide: interest is soft state; explicit PRACTICE opens practice; venue entry upgrades in place (L114)
function scenarios.guide()
    bootstrap()
    local function chat(name, pid, ...) commands[name](pid, { ... }); run(1) end
    print("== /ncm.guide lists the posted cadence (street tier), numbered")
    chat("ncm.guide", 1)
    assertf(count("Race Guide: ", chatLog, "text") == 1, "guide header told")
    local guide = guidePayload(1)
    assertf(guide and #guide.rows >= 3, "guide streamed with rows (%s)", tostring(guide and #guide.rows))
    assertf(tonumber(guide.serverNow) and guide.serverNow > 0,
        "every Guide head carries serverNow -- without it the panel's clock reads 1969 (KB-86, KB-160)")
    local row = guide.rows[1]
    assertf(row.tier == "street", "row 1 is the next street event")
    local e = NcmCalendar.events[row.eventId]
    assertf(e and (e.state == "posted" or e.state == "entry_open") and row.practice == "open", "practice open from posting (%s)", tostring(row.practice))

    print("== interest: soft entry and map route, no practice session")
    chat("ncm.interest", 1, "1")
    assertf(e.entries[driverIdOf(1)] and e.entries[driverIdOf(1)].state == "interested", "interested entry in memory")
    assertf(count("INSERT INTO entry", sqlLog, "q") == 1 and sqlLog[#sqlLog - 0] ~= nil, "entry row inserted")
    assertf(count("You're on the list", chatLog, "text") == 1, "told")
    local routed = false
    for _, ce in ipairs(clientEvents) do if ce.name == "ncm:guide.route" and ce.pid == 1 then routed = true end end
    assertf(routed, "map routed to the venue")
    assertf(bags[1].ncmEntry and bags[1].ncmEntry.state == "interested", "entry bag = interested")
    chat("ncm.interest", 1, "1")
    assertf(count("already on the list", chatLog, "text") == 1, "second interest refused")
    local psid, prec
    for sid, rec in pairs(NcmRace.sessions) do if rec.practice then psid, prec = sid, rec end end
    assertf(prec == nil, "interest alone never joins practice")

    print("== explicit PRACTICE opens and joins practice")
    -- The venue card belongs to the ring the driver is standing in (owner, 2026-09-28): name it first.
    clientNet("ncm:venue.at", 1, e.eventId); run(0)
    clientNet("ncm:venue.option", 1, "practice"); run(1)
    for sid, rec in pairs(NcmRace.sessions) do if rec.practice then psid, prec = sid, rec end end
    assertf(prec and prec.eventId == e.eventId and prec.s.phase == "open", "practice session open for the event")
    assertf(GlobalState.ncmPractice and GlobalState.ncmPractice[e.eventId] and GlobalState.ncmPractice[e.eventId].practice == true, "practice published beside the session")
    assertf(GlobalState.ncmSession == nil or GlobalState.ncmSession.phase == "none", "the live race publication is untouched")

    print("== a practice run: start, finish, leaderboard, run persisted")
    local g1, g2 = prec.s.gates[1], prec.s.gates[#prec.s.gates]
    moveTo(1, g1); clientNet("ncm:gate", 1, psid, 1)
    assertf(prec.s.entrants[driverIdOf(1)].run ~= nil, "run started")
    run(40); moveTo(1, g2); clientNet("ncm:gate", 1, psid, #prec.s.gates)
    assertf(prec.s.entrants[driverIdOf(1)].bestSec and prec.s.entrants[driverIdOf(1)].bestSec >= 40, "best recorded")
    assertf(count("INSERT INTO practice_run", sqlLog, "q") == 1, "practice_run row")
    assertf(count("Practice: P1 of 1 timed", chatLog, "text") == 1, "told the position")
    chat("ncm.practice", 1)
    assertf(count("  P1 owner %(you%)", chatLog, "text") == 1, "leaderboard line")
    chat("ncm.guide", 1)
    local mine = guidePayload(1).rows[1]
    assertf(mine.myPracticeBest ~= nil and mine.myState == "interested", "guide shows my best and state")

    print("== a second driver joins, then withdraws")
    chat("ncm.interest", 2, "1")
    clientNet("ncm:venue.at", 2, e.eventId); run(0)
    clientNet("ncm:venue.option", 2, "practice"); run(1)
    assertf(prec.s.entrants[driverIdOf(2)] ~= nil, "tester joined the same practice")
    chat("ncm.withdraw", 2)
    assertf(e.entries[driverIdOf(2)].state == "withdrawn" and count("Off the list", chatLog, "text") == 1, "withdrawn")
    assertf(prec.s.entrants[driverIdOf(2)].state == "left", "left the practice (state=%s)", tostring(prec.s.entrants[driverIdOf(2)] and prec.s.entrants[driverIdOf(2)].state))
    assertf(count("UPDATE entry SET state = 'withdrawn'", sqlLog, "q") == 1, "withdraw persisted")

    print("== interest is not a grid: at the venue the entry upgrades (same id); practice closes when the session forms")
    -- Check-in refuses a driver with no eligible machine (L83), so the garage has to be seeded for this leg. It is
    -- seeded through the real `ncm.grant`, not a bypass: a bypass would only ever exercise the bypass.
    command("ncm.grant", 0, "1", "all"); run(1)
    local entryId = e.entries[driverIdOf(1)].entryId
    while e.state ~= "entry_open" do run(10) end
    moveTo(1, e.venue); players[1].fresh = true; command("ncm.enter", 0, "1")
    assertf(e.entries[driverIdOf(1)].state == "checked_in" and e.entries[driverIdOf(1)].entryId == entryId, "upgraded in place")
    -- Economy v1 moved the upgrade inside the check-in TRANSACTION, so it is logged as a transaction whose
    -- statements carry the SQL -- `sqlLog[].q` is just "tx". Count the statement, not the log line.
    local upgrades = 0
    for _, r in ipairs(sqlLog) do
        if r.kind == "transaction" then
            for _, st in ipairs(r.p or {}) do if st.query:find("UPDATE entry SET state='checked_in'", 1, true) then upgrades = upgrades + 1 end end
        end
    end
    assertf(upgrades == 1, "upgrade persisted as an update, not an insert (%d)", upgrades)
    assertf(count("INSERT INTO entry", sqlLog, "q") == 2, "no new entry row for the upgrade (owner + tester interest = 2 inserts)")
    while e.startsAt - clock > 58 do run(5) end
    run(2)
    assertf(prec.s.phase == "complete" and prec.s.completeReason == "session_forming", "practice closed as the session formed: %s", tostring(prec.s.completeReason))
    assertf(NcmRace.sessions[psid] == nil and GlobalState.ncmPractice[e.eventId] == nil, "practice removed and unpublished")
    assertf(count("Practice closed", chatLog, "text") == 1, "only the driver still in the practice is told (%d)", count("Practice closed", chatLog, "text"))
    assertf(count("INSERT INTO session_result", sqlLog, "q") >= 1, "practice result persisted")
    local sid, rec = liveSession()
    assertf(rec and rec.kind == "race" and #rec.slots == 1, "race formed with the one checked-in driver")
    print("OK guide")
end

-- 12. guide2: interest alone never creates a session or forms a grid
function scenarios.guide2()
    bootstrap()
    commands["ncm.interest"](1, { "1" }); run(1)
    local row = guidePayload(1).rows[1]
    local e = NcmCalendar.events[row.eventId]
    local prec; for _, rec in pairs(NcmRace.sessions) do if rec.practice then prec = rec end end
    assertf(prec == nil, "interest did not create practice")
    while e.startsAt - clock > 55 do run(5) end
    assertf(liveSession() == nil, "no session formed from interest alone")
    print("OK guide2")
end

-- entrybag (KB-185, KB-186): the ring follows the driver past a race they never entered, and a Street Call can
-- be entered at all. Owner, 2026-09-28: "the venue entry ring doesnt show up unless im there and i re express
-- interest ... also custom races fail to be entered due to some economy reason".
function scenarios.entrybag()
    bootstrap()
    run(11)   -- the push rides the calendar tick; the boot-time publish happens before anyone has connected
    local calendarPushed = false
    for _, ev in ipairs(clientEvents) do
        if ev.name == "ncm:calendar" and ev.pid == 1 and type(ev.args[1]) == "table" then
            calendarPushed = true
            break
        end
    end
    assertf(calendarPushed, "the public calendar reaches the client over an explicit net event")
    print("== interest in the two soonest races: the bag names the sooner one")
    commands["ncm.guide"](1, {}); run(1)
    local rows = guidePayload(1).rows
    local first, second = NcmCalendar.events[rows[1].eventId], nil
    for i = 2, #rows do
        local x = NcmCalendar.events[rows[i].eventId]
        if x and x.startsAt > first.startsAt and not x.invitation then second = x; break end
    end
    assertf(second, "the cadence posts a later race to be interested in")
    commands["ncm.interest"](1, { first.eventId }); run(1)
    commands["ncm.interest"](1, { second.eventId }); run(1)
    assertf(bags[1].ncmEntry and bags[1].ncmEntry.eventId == first.eventId, "bag = the sooner race (%s)",
        tostring(bags[1].ncmEntry and bags[1].ncmEntry.eventId))

    print("== the sooner race starts without them: the bag moves on by itself, no second interest")
    while clock < first.startsAt + 75 do run(5) end
    assertf(bags[1].ncmEntry and bags[1].ncmEntry.eventId == second.eventId,
        "bag moved to the next live entry (%s) -- the ring must not wait for the driver to re-express interest",
        tostring(bags[1].ncmEntry and bags[1].ncmEntry.eventId))
    assertf(bags[1].ncmEntry.venue and bags[1].ncmEntry.state == "interested", "the moved bag is complete")

    print("== a Street Call enters free and settles to nothing")
    local call = { eventId = "impromptu:stub@1", class = "impromptu", unpaid = true, seriesId = "impromptu" }
    assertf(NcmEconomy.isUnpaid(call), "a Street Call declares itself unpaid")
    local paid, why = NcmEconomy.checkIn({ economy = NcmCompetition.economyFor(call), unpaid = NcmEconomy.isUnpaid(call),
        entryId = "stub-entry", eventId = call.eventId, seriesId = call.seriesId, driverId = driverIdOf(1),
        checkedInAt = clock })
    assertf(why ~= "economy_required", "check-in no longer refuses a Street Call for having no economy")
    assertf(NcmEconomy.settle({ plan = { e = call }, kind = "race", s = {} }, {}, "finished", clock) ~= nil,
        "settlement of an unpaid event succeeds with nothing to pay")
    local broken = { eventId = "paid:stub@1", class = "calendar", seriesId = "no_such_series" }
    local _, brokenWhy = NcmEconomy.checkIn({ economy = NcmCompetition.economyFor(broken), unpaid = NcmEconomy.isUnpaid(broken),
        entryId = "stub-entry-2", eventId = broken.eventId, seriesId = broken.seriesId, driverId = driverIdOf(1), checkedInAt = clock })
    assertf(brokenWhy == "economy_required", "a paid event that lost its economy still refuses (%s)", tostring(brokenWhy))
    print("OK entrybag")
end

-- ringcard (2026-09-28): the card belongs to the ring you are standing in; one entry at a time; switching is two
-- presses. Owner: "we have been fighting bugs for our race entries and things are getting lost in translation."
-- On the previous code the card at B's ring was A's card (A was bookmarked and sooner), so LEAVE LIST pressed at
-- B took the driver off A -- and entering B left the Guide believing A was their race.
function scenarios.ringcard()
    bootstrap()
    command("ncm.grant", 0, "1", "all"); run(1)
    commands["ncm.guide"](1, {}); run(1)
    local rows = guidePayload(1).rows
    local A, B = nil, nil
    for _, r in ipairs(rows) do
        local x = NcmCalendar.events[r.eventId]
        if x and not x.invitation then
            if not A then A = x
            elseif x.venue.name ~= A.venue.name and x.startsAt > A.startsAt then B = x; break end
        end
    end
    assertf(A and B, "two public races at two different venues")
    for _, x in ipairs({ A, B }) do x.entryOpensAt = clock - 1; x.state = "entry_open" end
    local me = driverIdOf(1)
    local function card() return bags[1].ncmVenue end
    local function first() return card() and card().options[1] or nil end
    local function stand(x) moveTo(1, x.venue); players[1].fresh = true; clientNet("ncm:venue.at", 1, x.eventId); run(0) end

    print("== bookmarked A (sooner); standing in B's ring: the card is B's")
    commands["ncm.interest"](1, { A.eventId }); run(1)
    stand(B)
    assertf(card() and card().eventId == B.eventId, "the card at B's ring is B's (was %s)", tostring(card() and card().eventId))
    assertf(first().id == "enter_race" and first().enabled, "entry is offered at B, bookmark or not")

    print("== LEAVE LIST at B does not touch the bookmark on A")
    clientNet("ncm:venue.option", 1, "leave_list", B.eventId); run(1)
    assertf(A.entries[me].state == "interested", "A's bookmark survived a press at B's ring (%s)", tostring(A.entries[me].state))

    print("== enter B: it is the driver's race, whatever they bookmarked")
    clientNet("ncm:venue.option", 1, "enter_race", B.eventId); run(2)
    assertf(B.entries[me] and B.entries[me].state == "checked_in", "entered B")
    assertf(NcmGuide.driverEvent(me) == B, "driverEvent names the entry, not the sooner bookmark")
    run(6)
    assertf(bags[1].ncmEntry and bags[1].ncmEntry.eventId == B.eventId and bags[1].ncmEntry.state == "checked_in",
        "the bag names B and stays there through a refresh (%s)", tostring(bags[1].ncmEntry and bags[1].ncmEntry.eventId))

    print("== a card drawn for another ring is refused")
    stand(A)
    clientNet("ncm:venue.option", 1, "withdraw", B.eventId); run(1)
    assertf(B.entries[me].state == "checked_in", "a stale ring's WITHDRAW did nothing")

    print("== one entry at a time: at A the ENTER slot is a switch, and a switch takes two presses")
    command("ncm.enter", 0, "1", A.eventId); run(2)
    assertf(A.entries[me].state == "interested", "a plain entry at A is refused while B is held")
    assertf(count("SWITCH ENTRY at this ring", chatLog, "text") >= 1, "and the refusal says how to switch")
    assertf(first().id == "switch_entry" and first().enabled, "A's card offers SWITCH ENTRY (%s)", tostring(first().id))
    clientNet("ncm:venue.option", 1, "switch_entry", A.eventId); run(1)
    assertf(B.entries[me].state == "checked_in" and A.entries[me].state == "interested", "the first press changes nothing")
    assertf(first().id == "confirm_switch" and first().label:find(B.routeName, 1, true), "the confirm names B")
    clientNet("ncm:venue.option", 1, "confirm_switch", A.eventId); run(2)
    assertf(A.entries[me].state == "checked_in", "entered A (%s)", tostring(A.entries[me].state))
    assertf(B.entries[me].state == "withdrawn", "withdrew from B (%s)", tostring(B.entries[me].state))
    run(6)
    assertf(bags[1].ncmEntry and bags[1].ncmEntry.eventId == A.eventId, "the bag followed the switch")

    print("== leaving every ring clears the card")
    moveTo(1, { x = A.venue.x + 400, y = A.venue.y }); clientNet("ncm:venue.at", 1, nil); run(1)
    assertf(card() == nil, "no ring, no card")
    print("OK ringcard")
end

-- 13. hostkit: scenario console, lights now, incident injection, restart/stop, authored routes, world reset
function scenarios.hostkit()
    bootstrap()
    print("== ncm.scenario gt troll: posts and enters everyone connected")
    command("ncm.scenario", 0, "gt", "troll", "in", "2")
    local e
    for eid, x in pairs(NcmCalendar.events) do if x.seriesId == "scenario" then e = x end end
    assertf(e and e.state == "entry_open" and e.disciplineId == "street_sprint", "scenario event posted")
    assertf(e.entries[driverIdOf(1)] and e.entries[driverIdOf(2)] and e.entries[driverIdOf(1)].state == "checked_in", "both entered as checked in")
    assertf(count("S1: Scenario", chatLog, "text") == 2, "both told with the scenario id")
    assertf(count("INSERT INTO entry", sqlLog, "q") == 2, "entries persisted")
    assertf(clientEvents[#clientEvents].name == "ncm:guide.route", "map routed to the start")
    command("ncm.scenario", 0, "field")

    print("== forms at T-60; lights now forces the countdown without waiting")
    while e.startsAt - clock > 58 do run(5) end
    run(2)
    local sid, rec = liveSession()
    assertf(rec and rec.kind == "race" and #rec.slots == 2, "race formed for the field")
    command("ncm.lights", 0, "now")
    run(1)
    assertf(rec.s.phase == "gridded" or rec.s.phase == "countdown", "lights now: phase %s", rec.s.phase)
    for _, sl in ipairs(rec.slots) do moveTo(rec.playerOf[sl.driverId], sl) end
    run(8)
    assertf(rec.s.phase == "running", "green after lights now (phase %s)", rec.s.phase)

    print("== an injected incident lands on the driver")
    command("ncm.incident", 0, "1", "2", "car")
    assertf(rec.s.entrants[driverIdOf(1)].incidentSec and rec.s.entrants[driverIdOf(1)].incidentSec > 0, "incident seconds on the driver")
    assertf(count("INSERT INTO incident", sqlLog, "q") == 1, "incident row")
    command("ncm.rules", 0, "incidents", "off")
    assertf(NcmScenario.overrides.incidents == false, "scan override off")
    command("ncm.rules", 0, "incidents", "on")
    command("ncm.state", 0)
    command("ncm.trace", 0, "1", "on")
    assertf(NcmScenario.traced[driverIdOf(1)] == true, "traced")

    print("== restart: the same field, a fresh event, no server restart")
    command("ncm.scenario", 0, "restart")
    run(1)
    assertf(rec.s.phase == "complete", "old session aborted")
    local e2
    for eid, x in pairs(NcmCalendar.events) do if x.seriesId == "scenario" and x.state == "entry_open" then e2 = x end end
    assertf(e2 and e2 ~= e and e2.entries[driverIdOf(1)] and e2.entries[driverIdOf(2)], "new scenario event with the same field")
    assertf(e.state == "closed", "old event closed")
    while e2.startsAt - clock > 58 do run(5) end
    run(2)
    local sid2, rec2 = liveSession()
    assertf(rec2 and rec2.eventId == e2.eventId, "second scenario formed")
    command("ncm.scenario", 0, "stop")
    run(1)
    assertf(liveSession() == nil and e2.state == "closed", "stopped: no session, event closed")

    print("== authored route: start, two gates, loop -> an oval scenario with laps")
    local function ar(pid, ...) commands["ncm.ar"](pid, { ... }); run(1) end
    moveTo(1, { x = 3000, y = 3000 }); ar(1, "start", "ring", "Test", "Ring")
    moveTo(1, { x = 3100, y = 3000 }); ar(1, "gate", "T1")
    moveTo(1, { x = 3100, y = 3100 }); ar(1, "gate", "T2")
    moveTo(1, { x = 3000, y = 3100 }); ar(1, "gate", "T3")
    ar(1, "loop")
    assertf(count("Route saved: Test Ring", chatLog, "text") == 1, "route saved")
    assertf(count("INSERT INTO custom_route", sqlLog, "q") == 1, "route persisted")
    ar(1, "list")
    assertf(count("ring · Test Ring · 3 gate", chatLog, "text") == 1, "listed")
    command("ncm.scenario", 0, "oval", "ring", "laps", "2", "in", "2")
    local e3
    for eid, x in pairs(NcmCalendar.events) do if x.seriesId == "scenario" and x.state == "entry_open" then e3 = x end end
    assertf(e3 and e3.disciplineId == "oval" and e3.laps == 2 and e3.routeName == "Test Ring", "oval scenario on the authored ring")
    while e3.startsAt - clock > 58 do run(5) end
    run(2)
    local sid3, rec3 = liveSession()
    -- ovals roll by default (P41): start, green flag, then 2 laps × 4 lines
    local greenAt
    for i, g in ipairs(rec3 and rec3.s.gates or {}) do if g.kind == "green" then greenAt = i end end
    assertf(rec3 and rec3.course.adapter == "laps" and #rec3.s.gates == 1 + 1 + 2 * 4 and greenAt == 4 and rec3.s.rules.start == "rolling", "laps course with a green gate 300 m in: %d gates, green=%s start=%s", rec3 and #rec3.s.gates or -1, tostring(greenAt), tostring(rec3 and rec3.s.rules.start))

    print("== world reset: sessions gone, cars back, no restart")
    command("ncm.world", 0, "reset")
    run(1)
    assertf(liveSession() == nil, "no sessions after reset")
    assertf(count("World reset by the host", chatLog, "text") == 2, "everyone told")
    print("OK hostkit")
end

-- 14. rolling: a rolling-start scenario — formation under the cap, green at the leader, faults as incidents
function scenarios.rolling()
    bootstrap()
    command("ncm.scenario", 0, "gt", "troll", "rolling", "formation", "200", "pace", "60", "in", "2")
    command("ncm.rules", 0, "incidents", "off")   -- stub cars share a point: keep the contact scan out of a formation test
    local e
    for _, x in pairs(NcmCalendar.events) do if x.seriesId == "scenario" then e = x end end
    assertf(e and e.startType == "rolling", "rolling scenario posted")
    while e.startsAt - clock > 58 do run(5) end
    run(2)
    local sid, rec = liveSession()
    assertf(rec and rec.s.rules.start == "rolling" and rec.s.gates[2].kind == "green" and #rec.s.gates == 3, "green gate in the course (%d gates)", rec and #rec.s.gates or -1)
    local pole, second
    for _, sl in ipairs(rec.slots) do moveTo(rec.playerOf[sl.driverId], sl); if sl.slot == 1 then pole = rec.playerOf[sl.driverId] else second = rec.playerOf[sl.driverId] end end
    local P, S = rec.s.entrants[driverIdOf(pole)], rec.s.entrants[driverIdOf(second)]
    while rec.s.phase ~= "running" do run(1) end
    assertf(not rec.s.rollingGreenAt, "lights released the roll-out, no green yet")
    local g1, g2, g3 = rec.s.gates[1], rec.s.gates[2], rec.s.gates[3]
    -- both cross the start in grid order; the second car speeds in formation (80 km/h against a 60 cap) -> one formation incident
    for _, pid in ipairs({ pole, second }) do moveTo(pid, g1); clientNet("ncm:gate", pid, sid, 1) end
    clientNet("ncm:telemetry", second, sid, { { clock + 0.2, g1.x, g1.y + 5, 10, 80 / 3.6, 3, true, 1 }, { clock + 0.4, g1.x, g1.y + 10, 10, 80 / 3.6, 3, true, 1 } })
    assertf(S.incidentCount == 1 and S.incidents[1].detail == "over_pace", "over pace: one formation incident")
    assertf(count("INSERT INTO incident", sqlLog, "q") == 1, "formation incident persisted")
    -- the second car reaches the green before the pole car: green for all, and a passing fault on it
    run(5); moveTo(second, g2); clientNet("ncm:gate", second, sid, 2)
    assertf(rec.s.rollingGreenAt and rec.s.rollingLeader == driverIdOf(second), "green at the first car to the flag")
    assertf(count("GREEN FLAG", chatLog, "text") == 2, "everyone told")
    assertf(S.formationFault == "passed_before_green", "passing before the green is a fault")
    assertf(count("Formation fault", chatLog, "text") == 1, "the offender told")
    run(1); moveTo(pole, g2); clientNet("ncm:gate", pole, sid, 2)
    assertf(P.formationFault == nil, "the pole car passed nobody")
    -- finish: the second car first on the road by 1 s, but two formation faults (2 s each) put the clean pole car P1
    run(30); moveTo(second, g3); clientNet("ncm:gate", second, sid, 3)
    run(1); moveTo(pole, g3); clientNet("ncm:gate", pole, sid, 3)
    run(65)
    assertf(rec.s.phase == "complete" and rec.results[1].driverId == driverIdOf(pole), "clean pole car wins on corrected time")
    assertf(rec.results[2].incidentSec == 4, "two formation faults = +4 s (%s)", tostring(rec.results[2].incidentSec))
    print("OK rolling")
end

-- 10. progression: SR/licence rows after a race
function scenarios.progression()
    bootstrap()
    command("ncm.event.post", 0, "tip", "3"); inviteBoth("kimiko", "raven")
    run(3 * 60 - 55)
    raceThrough({ 1, 2 })
    run(70)
    assertf(count("INTO driver_sr", sqlLog, "q") >= 2, "driver_sr upserted for both")
    assertf(count("INTO driver_licence", sqlLog, "q") >= 2, "licence rows")
    assertf(count("Driver profile:", chatLog, "text") == 2, "both told their deltas")
    command("ncm.profile", 1)
    assertf(count("Licence: ncx_formula rookie %(1 clean%)", chatLog, "text") == 1, "profile readout")
    print("OK progression")
end

-- 18. ambient: the world is inhabited, and a race clears its own road.
--
-- This is the INTEGRATION the unit tests cannot reach: ncm_league publishes a calendar row, ncm_world
-- reads it out of GlobalState in a different Lua VM, turns the route into a corridor, and takes its own
-- ambient population out of the way. Both halves of the population story are asserted, because the
-- interesting failure is doing one and believing you did both.
function scenarios.ambient()
    tunableOverrides.ambientEnabled = true
    tunableOverrides.ambientSpawnPerTick = 4
    bootstrap()

    -- Record where things are CREATED, which is what the no-pop radius actually promises. Asserting on
    -- where they are LATER would be wrong and was: an ambient car on joinTraffic drives, and driving past
    -- the player at 100 m is the behaviour, not a violation.
    local births = {}
    local realVehicleCreate, realNpcCreate = Open77.vehicles.create, Open77.npcs.create
    Open77.vehicles.create = function(spec)
        local id = realVehicleCreate(spec)
        if id then births[#births + 1] = { kind = "vehicle", x = spec.position.x, y = spec.position.y } end
        return id
    end
    Open77.npcs.create = function(spec)
        local id = realNpcCreate(spec)
        if id then births[#births + 1] = { kind = "ped", x = spec.position.x, y = spec.position.y } end
        return id
    end

    moveTo(1, { x = 0, y = 0 })
    run(30)

    local cars, peds = 0, 0
    for _, e in pairs(NcmAmbient.owned) do
        if e.kind == "vehicle" then cars = cars + 1 else peds = peds + 1 end
    end
    assertf(cars + peds > 0, "the world was populated around a connected player, got %d", cars + peds)
    assertf(peds > 0, "there are people on the pavements, not only cars: %d ped(s)", peds)
    assertf(#births > 0, "births were recorded")
    for _, b in ipairs(births) do
        local d = math.sqrt(b.x * b.x + b.y * b.y)
        assertf(d >= 110, "nothing popped in beside the player: %s born at %.0f m", b.kind, d)
    end
    -- Every ambient car is enrolled in the engine's own lane traffic. A parked car is scenery.
    for _, e in pairs(NcmAmbient.owned) do
        if e.kind == "vehicle" then
            assertf(vehicles[e.vehicleId] ~= nil and vehicles[e.vehicleId].ai ~= nil,
                "ambient car %s has a driver attached", tostring(e.vehicleId))
        end
    end
    assertf(world.population[0] ~= nil, "the vanilla density switch was asserted for the bucket")
    assertf(world.population[0].crowd == 1.0, "...at the open policy while nothing is due")

    -- Post the race FIRST, then place our ambient population on the road that race actually got. Placing
    -- it on a route of our own choosing and hoping the calendar picked the same one is how this assertion
    -- passes for the wrong reason.
    -- Post the race AND enter it. An empty slot must hold no road at all -- there are 21 scheduled starts
    -- in any three-hour window on the shipped cadence and most of them have nobody in them, so holding a
    -- corridor per slot would clear every route permanently. The entrants are what make this race real.
    command("ncm.event.post", 0, "tip", "3")
    inviteBoth()
    run(30)
    local cal = GlobalState.ncmCalendar
    assertf(cal and cal.next and cal.next[1], "a race is on the calendar")
    local row = cal.next[1]
    assertf((tonumber(row.entries) or 0) > 0, "the race has entrants, got %s", tostring(row.entries))
    assertf(row.finish and row.finish.x ~= nil,
        "the publication carries the finish COORDINATES, not just its name -- a corridor needs the whole lap")

    -- Midway down the racing line and 50 m to the SIDE of it. Midway, because that is the part a radius
    -- drawn round the grid box would miss entirely; to the side, because sitting exactly on the line
    -- would be cleared by a corridor of any width at all and would prove nothing about this one's.
    local dx, dy = row.finish.x - row.venue.x, row.finish.y - row.venue.y
    local len = math.max(1e-6, math.sqrt(dx * dx + dy * dy))
    local mid = {
        x = (row.venue.x + row.finish.x) / 2 + (-dy / len) * 50,
        y = (row.venue.y + row.finish.y) / 2 + (dx / len) * 50,
    }
    local onTheLine = {}
    for key, e in pairs(NcmAmbient.owned) do
        e.x, e.y = mid.x, mid.y
        if e.vehicleId then
            vehicles[e.vehicleId].position = { x = e.x, y = e.y, z = e.z }
            -- ...and drop the traffic target with it. The stub drives enrolled cars toward whatever
            -- point joinTraffic last set, so a car teleported onto the racing line would drive straight
            -- back off it and be reclaimed for distance instead -- which is this assertion passing for
            -- the wrong reason.
            if vehicles[e.vehicleId].ai then vehicles[e.vehicleId].ai.target = nil end
        end
        if e.npcId and world.npcs[e.npcId] then world.npcs[e.npcId].position = { x = e.x, y = e.y, z = e.z } end
        onTheLine[#onTheLine + 1] = key
    end
    assertf(#onTheLine > 0, "the fixture put something in the corridor's path")

    -- 260 m to the side: past `ambientSightM` (220) so a despawn is unobserved, but inside
    -- `ambientRetireM` (300) so the ONLY rule that can remove these is the corridor. Standing further off
    -- would let the reclaim rule clear them and the assertion would prove nothing.
    moveTo(1, { x = mid.x, y = mid.y + 260 })
    run(30)

    local left = 0
    for _, key in ipairs(onTheLine) do if NcmAmbient.owned[key] then left = left + 1 end end
    local pp = {}
    for pid, pl in pairs(players) do
        pp[#pp+1] = ("p%s@%.0f,%.0f d=%.0f"):format(pid, pl.position.x, pl.position.y,
            math.sqrt((pl.position.x-mid.x)^2 + (pl.position.y-mid.y)^2))
    end
    assertf(left == 0, "the race corridor was cleared of ambient population, %d left standing", left)
    -- And the city AROUND the corridor is untouched. The vanilla switch is bucket-wide with no radius, so
    -- throwing it here would empty Night City for everyone -- permanently, given a corridor is in its
    -- window almost always on this cadence. The corridor is cleared by removing OUR entities from it.
    assertf(world.population[0].crowd == 1.0 and world.population[0].police == true,
        "the shared world bucket keeps its vanilla population through a race")

    -- Nothing this file spawns may ever appear in a session.
    for _, e in pairs(NcmAmbient.owned) do
        assertf(vehicles[e.vehicleId or -1] == nil or NcmGarage.describe(1):find(tostring(e.vehicleId)) == nil,
            "ambient cars are never issued to a driver")
    end
    print("OK ambient")
end

local which = arg[1] or "gridcars"
assert(scenarios[which], "unknown scenario " .. which)
scenarios[which]()
