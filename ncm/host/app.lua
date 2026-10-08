-- NCM Host app (L338, doc 55): the tape deck + one mounted world.
--
--   app = App.new(env)          env = { load(rel) -> module, read(path), write(path, text), rename(a, b), remove(path),
--                                       sqlite() -> driver, log(fmt, ...), clock = <host clock>, resourceRoot,
--                                       tapesPath, game = <optional CET bindings> }
--   app:tapes()                 deck rows: { tape, present, ago } for every tape (no world needed)
--   app:newTape()               a fresh continuity (RW 01 · D1), not mounted
--   app:mount(id)               settle the database, start the resources on that tape's server_id, join as player 1
--   app:tick(budgetMs)          per frame while mounted
--   app:unmount()               stop the world, remember the tape
-- Single player only. The OPEN//77 dev server is untouched by any of this: same resources, different host.
local App = { version = "0.1.0" }
App.__index = App

-- The resources NCM 3.0 runs (dev-only ones -- ncm_link, ncm_space, ncm_probe, ncm_weather_probe -- are not loaded).
-- ncm_aero (L339) is single-player only: auto_start false, and it idles unless the world says single_player.
App.RESOURCES = { "ncm_league", "ncm_world", "ncm_paddock", "ncm_speed", "ncm_broadcast", "ncm_scanner", "ncm_observer", "ncm_aero" }
-- The host's own view of core (deck arithmetic, json): loaded privately from a resource's vendored copy.
App.CORE = { "init.lua", "vocabulary/ids.lua", "vocabulary/json.lua", "vocabulary/hash.lua", "world/clock.lua",
    "week/clock.lua", "week/curve.lua", "week/continuation.lua", "week/catchup.lua", "data/liveries.lua" }

function App.new(env)
    local a = setmetatable({ env = env }, App)
    a.compile = env.compile or function(path, src, e) return load(src, "@" .. path, "t", e) end
    a.log = env.log or function(fmt, ...) print(("[ncm-host] " .. fmt):format(...)) end
    a.root = env.resourceRoot or "resources/"
    a.T = env.load("sql/translate.lua")
    a.S = env.load("sql/schema.lua").init(a.T)
    a.Shim = env.load("sql/mysql.lua")
    a.Runtime = env.load("runtime.lua")
    a.Headless = env.load("api/headless.lua")
    a.Clock = env.load("clock.lua")
    a.Tapes = env.load("tapes.lua")
    a.core = a:loadCore()
    a.json = a.core.get("vocabulary.json")
    a.store = a.Tapes.open({ read = env.read, write = env.write, rename = env.rename, remove = env.remove },
        env.tapesPath or "save/ncm_tapes.json", a.json)
    a.clock = env.clock or a.Clock.real(a.store.doc)
    return a
end

function App:loadCore()
    local env = setmetatable({}, { __index = self.env.globals or _G })
    env._G = env
    local base = self.root .. "ncm_world/shared/core/"
    for _, f in ipairs(App.CORE) do
        local src = self.env.read(base .. f)
        if not src then error("host core: missing " .. base .. f) end
        local chunk = assert(self.compile(base .. f, src, env))
        chunk()
    end
    return env.NcmCore
end

-- ------------------------------------------------------------------------------------------------ the deck

function App:tapes()
    local now = self.clock.unix()
    local out = {}
    for _, t in ipairs(self.store:list()) do
        local okP, p = pcall(self.Tapes.present, t, now, self.core)
        out[#out + 1] = { tape = t, present = okP and p or nil, error = (not okP) and tostring(p) or nil,
            ago = self.Tapes.ago(now - (t.lastSeen or now)) }
    end
    return out
end

function App:newTape(opts)
    local t = self.store:create(self.clock.unix(), opts)
    self.store:note(t, self.clock.unix(), "created" .. ((opts and opts.devAltered) and " (dev)" or ""))
    self.store:save()
    return t
end

-- ------------------------------------------------------------------------------------------------ database

function App:migrations()
    local manifest = assert(self.env.read(self.root .. "ncm_league/open77.lua"), "ncm_league manifest")
    local env = setmetatable({}, { __index = self.env.globals or _G })
    env.NcmSchema = {}
    for path in manifest:gmatch('server_script%s+"(server/schema/[^"]+)"') do
        local src = assert(self.env.read(self.root .. "ncm_league/" .. path), path)
        assert(self.compile(self.root .. "ncm_league/" .. path, src, env))()
    end
    local list = {}
    for i = 1, #env.NcmSchema do list[i] = env.NcmSchema[i] end
    table.sort(list, function(x, y) return x.version < y.version end)
    return list
end

--- Bring the one SQLite database to the resources' schema. Every tape shares it, separated by server_id.
function App:database()
    if self.db then return self.db, self.model end
    local d = assert(self.env.sqlite())
    local migrations = self:migrations()
    local model, dml = self.S.replay(migrations)
    local rep = self.S.sync(d, model, self.clock.unix())
    local applied = {}
    for _, r in ipairs(d.query("SELECT version FROM schema_migrations")) do applied[tonumber(r.version)] = true end
    local ctx = { datetime = self.clock.datetime, unix = self.clock.unix, uuid = self.Clock.uuid }
    local ran = 0
    for _, s in ipairs(dml) do
        if not applied[s.version] then
            local ok, e = pcall(function() d.exec(self.T.dml(s.sql, ctx)) end)
            if not ok then self.log("migration %03d data step failed (continuing): %s", s.version, tostring(e)) else ran = ran + 1 end
        end
    end
    for _, m in ipairs(migrations) do
        if not applied[m.version] then
            d.exec(("INSERT OR IGNORE INTO schema_migrations (version, name) VALUES (%d, %s)"):format(m.version, self.T.quote(m.name)))
        end
    end
    self.log("database: %d table(s) created, %d altered, %d rebuilt; %d migration data step(s); SQLite %s",
        #rep.created, #rep.altered, #rep.rebuilt, ran, d.version and d.version() or "?")
    self.db, self.model = d, model
    return d, model
end

-- ------------------------------------------------------------------------------------------------ mount

function App:mount(id)
    if self.world then return nil, "already_mounted" end
    local tape = self.store:get(id)
    if not tape then return nil, "no_such_tape" end
    -- a clock that went backwards (Windows time changed, a dead CMOS battery) never un-rolls a tape: hold at lastSeen
    if self.clock.unix() < (tape.lastSeen or 0) then
        self.store:note(tape, self.clock.unix(), ("clock regression: wall clock %d is before last seen %d; held"):format(math.floor(self.clock.unix()), tape.lastSeen))
        self.clockRegressed = true
        if self.clock.setFloor then self.clock.setFloor(tape.lastSeen) end
    end
    local before = self.Tapes.present(tape, self.clock.unix(), self.core)
    local d, model = self:database()
    local MySQL = self.Shim.new({ driver = d, model = model, T = self.T, S = self.S, clock = self.clock, uuid = self.Clock.uuid,
        log = function(fmt, ...) self.log("sql: " .. fmt, ...) end })
    local env = self.env
    local h = self.Runtime.new({
        read = env.read, compile = self.compile, globals = env.globals, resourceRoot = self.root, resources = env.resources or App.RESOURCES, clock = self.clock,
        convars = self.Tapes.convars(tape), MySQL = MySQL, json = { encode = self.json.encode, decode = self.json.decode },
        player = env.player, log = env.worldLog or self.log, budgetMs = env.budgetMs or 4,
        apis = { server = self.Headless.server, client = self.Headless.client },
    })
    h.exports = self.Headless.exports(h)
    h.game = env.game
    -- phase 1: the NCM plugins' hidden pages, played natively (host/webui) when the host has loopback networking
    if env.net then
        self.Webui = self.Webui or env.load("webui/init.lua")
        h.webui = self.Webui.new({ net = env.net, json = self.json, now = function() return self.clock.mono() end,
            log = function(fmt, ...) self.log(fmt, ...) end })
        self.webui = h.webui
    end
    -- a claim answered by ncm_league (ownership.claim): remember it, and put the car in V's garage (vanilla call menu)
    h:listen("server", "ncm:host:claimed", function(pid, record, assetId, state, serial)
        self.lastClaim = { record = record, assetId = assetId, state = state, serial = serial, at = self.clock.unix() }
        if assetId then
            self.store:note(self.tape, self.clock.unix(), ("claimed %s%s"):format(tostring(record), serial and (" " .. serial) or ""))
            if env.game and env.game.giveCar then pcall(env.game.giveCar, record) end
        end
    end)
    -- L339: the aerospace race's tower, as ncm_aero last published it (the deck reads it through `aero`)
    self.aero = nil
    h:listen("server", "ncm:host:aero", function(snap) self.aero = snap end)
    MySQL.ready = function(fn) h:spawn({ key = "mysql", stopped = false, env = {} }, fn, "MySQL.ready"); return true end
    local w = self.Headless.world(h)
    w.tunables["*"] = { serverId = tape.serverId, environment = "single_player" }
    self.world, self.tape, self.mysql = h, tape, MySQL
    self.store.doc.lastMounted = tape.id
    if env.game and env.game.attach then env.game.attach(h, self) end
    h:start()
    h:connect()
    h:ready()
    self.mountedAt = self.clock.unix()
    -- what changed while the tape was away: told once, plainly (doc 55 §5: never hide that time works differently)
    local after = self.Tapes.present(tape, self.clock.unix(), self.core)
    if before and after and after.run > (tonumber(tape.cache and tape.cache.lastRun) or after.run) then
        local n = after.run - (tonumber(tape.cache.lastRun) or after.run)
        self.store:note(tape, self.clock.unix(), ("returned: %d Race Week rollover(s) while away; now %s"):format(n, after.label))
        self.lastReturn = { rolled = n, label = after.label }
    end
    self:remember()
    self.store:save()
    return true
end

--- Snapshot the tape's cache from the world's own records (timeline rows, live standing, presence).
function App:remember()
    if not self.world then return end
    local tape, d = self.tape, self.db
    local runs, standing, last = {}, {}, 1
    local okQ, rows = pcall(d.query, ("SELECT run_index, end_utc, end_kind, survived, state_json FROM racing_week_run WHERE server_id = %s")
        :format(self.T.quote(tape.serverId)))
    for _, r in ipairs(okQ and rows or {}) do
        local n = tonumber(r.run_index)
        runs[n] = { endUtc = tonumber(r.end_utc), endKind = r.end_kind, survived = tonumber(r.survived) }
        if not r.end_utc then
            local okJ, st = pcall(self.json.decode, r.state_json or "")
            if okJ and type(st) == "table" and st.deviation ~= nil then standing[n] = st.deviation end
        end
        if n > last then last = n end
    end
    local info = { runs = runs, standing = standing, lastRun = last }
    local okP, pres = pcall(d.query, ("SELECT place, host, location_id FROM ncm_presence WHERE server_id = %s ORDER BY updated_at DESC LIMIT 1")
        :format(self.T.quote(tape.serverId)))
    if okP and pres and pres[1] then
        info.place, info.location = pres[1].place, pres[1].location_id or pres[1].host
    end
    self.store:remember(tape, self.clock.unix(), info)
end

function App:tick(budgetMs)
    if not self.world then return 0 end
    local n = self.world:tick(budgetMs)
    local t = self.clock.unix()
    if not self.lastRemember or t - self.lastRemember >= 60 then
        self.lastRemember = t
        local c0 = os.clock()
        self:remember()
        self.store:save()
        local ms = (os.clock() - c0) * 1000
        if ms > 8 then self.log("slow tape snapshot %.1f ms (remember + save)", ms) end
    end
    return n
end

function App:unmount(reason)
    if not self.world then return end
    self:remember()
    self.world:stop(reason or "unmount")
    if self.env.game and self.env.game.detach then pcall(self.env.game.detach, self.world, self) end
    self.store:save()
    self.world, self.tape, self.mysql = nil, nil, nil
end

-- ------------------------------------------------------------------------------------------------ claiming cars

--- CLAIM a car into the mounted tape (L338): ncm_league mints a serialized machine (or an unserialized one for a record
--- NCM has never heard of) and the game gets it in V's garage. `record` is a TweakDB record; `appearance` the live
--- appearance name when the player is sitting in it (a base RB15 wearing "kimiko" is the Kimiko car).
function App:claim(record, appearance)
    if not self.world then return nil, "mount_a_tape_first" end
    if type(record) ~= "string" or record == "" then return nil, "no_record" end
    local Liveries = self.core.get("data.liveries")
    local l = Liveries.fromRecord(record, appearance)
    if l and l.id ~= "stock" then
        local m = Liveries.MODELS[l.model]
        record = m.prefix .. l.id
    end
    self.lastClaim = { record = record, state = "pending", at = self.clock.unix() }
    self.world:trigger("server", "ncm:host:claim", 1, record)
    self.world:tick(1e6)
    return true, record
end

--- What can be claimed right now: every registered livery of every model, plus the car the player is sitting in.
function App:claimable()
    local Liveries = self.core.get("data.liveries")
    local out = {}
    for key, m in pairs(Liveries.MODELS) do
        for _, id in ipairs(m.order) do
            local s = m.liveries[id]
            out[#out + 1] = { model = key, id = id, label = s.label, record = m.prefix .. id }
        end
    end
    return out
end

--- This tape's machines (the player's): { record, assetId, serial, vehicleKey }.
function App:garage()
    if not (self.world and self.db and self.tape) then return {} end
    local q = self.T.quote
    local ok, rows = pcall(self.db.query, ([[SELECT a.asset_id, a.record, a.vehicle_key, a.production_ordinal, a.maker_ordinal,
        a.manufacturer_key, a.acquired_via FROM vehicle_asset a JOIN ncm_driver_binding b ON b.ncm_driver_id = a.ncm_driver_id
        AND b.server_id = a.server_id WHERE a.server_id = %s ORDER BY a.acquired_at]]):format(q(self.tape.serverId)))
    local out = {}
    for _, r in ipairs(ok and rows or {}) do
        local serial = r.production_ordinal and ("NCM #%07d · %s #%04d"):format(tonumber(r.production_ordinal) or 0,
            tostring(r.manufacturer_key), tonumber(r.maker_ordinal) or 0) or nil
        out[#out + 1] = { assetId = r.asset_id, record = r.record, vehicleKey = r.vehicle_key, serial = serial, via = r.acquired_via }
    end
    return out
end

-- ------------------------------------------------------------------------------------------------ aerospace racing

--- L339: the aerospace race (ncm_aero). action = "start" (arg = { vehicleKey, size, turnAltM }: a machine from THIS
--- tape's garage -- the host checks it is one), "stop", "rate" (DEV only: race time x arg), or nil to just read.
--- Returns the tower snapshot ncm_aero last published (nil before any race).
function App:aeroCmd(action, arg)
    if not self.world then return nil, "mount_a_tape_first" end
    if action == "start" then
        local key = type(arg) == "table" and arg.vehicleKey
        local owned = false
        for _, m in ipairs(self:garage()) do if m.vehicleKey and m.vehicleKey == key then owned = true end end
        if not owned then return nil, "not_in_this_tapes_garage" end
        self.world:trigger("server", "ncm:aero:cmd", "start", { vehicleKey = key, size = arg.size, turnAltM = arg.turnAltM })
    elseif action == "stop" then
        self.world:trigger("server", "ncm:aero:cmd", "stop")
    elseif action == "rate" then
        if not self.store.doc.devMode then return nil, "dev_mode_off" end
        self.world:trigger("server", "ncm:aero:cmd", "rate", tonumber(arg) or 1)
        if self.tape and (tonumber(arg) or 1) > 1 then
            self.tape.devAltered = true
            self.store:note(self.tape, self.clock.unix(), "dev: aerospace race x" .. tostring(arg))
            self.store:save()
        end
    elseif action ~= nil then
        return nil, "unknown_action"
    end
    if action then self.world:tick(1e6) end
    return self.aero or false
end

-- ------------------------------------------------------------------------------------------------ dev time lab

--- DEV ONLY. Every action is noted on the tape and marks it dev-altered; production semantics never change.
function App:dev(action, arg)
    local doc = self.store.doc
    if not doc.devMode then return nil, "dev_mode_off" end
    local tape = self.tape or (doc.lastMounted and self.store:get(doc.lastMounted))
    local t = self.clock.unix()
    local function skew(dt)
        if self.clock.advance then self.clock.advance(dt) else doc.devSkew = (doc.devSkew or 0) + dt end
    end
    if action == "hour" then skew(3600)
    elseif action == "day" then skew(86400)
    elseif action == "skip_weeks" then skew((tonumber(arg) or 1) * 3 * 86400)
    elseif action == "near_end" or action == "cross" then
        local p = tape and self.Tapes.present(tape, t, self.core)
        if not p then return nil, "no_tape" end
        skew(math.max(0, p.secondsRemaining - (action == "near_end" and 60 or -5)))
    elseif action == "reset_skew" then doc.devSkew = 0
    elseif action == "age_tape" then
        if not tape then return nil, "no_tape" end
        tape.epoch = tape.epoch - (tonumber(arg) or 7) * 86400
        tape.created = tape.created - (tonumber(arg) or 7) * 86400
    elseif action == "strand_deep" then
        -- the player's Machine is left in Deep with an empty tank: what quitting after a failed climb looks like.
        -- Done on a tape AT REST (unmounted) -- the world reads it at the next mount, exactly as after a real quit.
        if not tape then return nil, "no_tape" end
        if self.world then return nil, "unmount_first" end
        local d = self:database()
        local q = self.T.quote
        local drv = d.query(("SELECT ncm_driver_id FROM ncm_driver_binding WHERE server_id = %s LIMIT 1"):format(q(tape.serverId)))[1]
        if not drv then return nil, "no_driver_on_this_tape_yet" end
        local run = tonumber(tape.cache and tape.cache.lastRun) or 1
        d.exec(("INSERT INTO ncm_presence (driver_id, server_id, place, host, location_id, state_json, race_week_run, updated_at) " ..
            "VALUES (%s, %s, 'deep', 'ncm', 'deep', %s, %d, %d) ON CONFLICT DO UPDATE SET place = excluded.place, host = excluded.host, " ..
            "location_id = excluded.location_id, state_json = excluded.state_json, race_week_run = excluded.race_week_run, " ..
            "updated_at = excluded.updated_at"):format(q(drv.ncm_driver_id), q(tape.serverId),
            q(self.json.encode({ dev = "strand_deep", propellantKg = 0, alt = 600000000 })), run, math.floor(t)))
        tape.cache = tape.cache or {}
        tape.cache.place, tape.cache.location = "deep", "deep"
    else
        return nil, "unknown_action"
    end
    if tape then
        tape.devAltered = true
        self.store:note(tape, self.clock.unix(), "dev: " .. action .. (arg and (" " .. tostring(arg)) or ""))
    end
    self.store:save()
    if self.world then self.world:tick(1e6) end
    return true
end

return App
