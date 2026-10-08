-- NCM Host runtime (L338, doc 55 §3): the OPEN//77 resources, run in-process, single player.
--
-- One NcmHost instance = one mounted tape. It loads each resource from its own `open77.lua` manifest into TWO
-- isolated environments (server half, client half), exactly as OPEN//77 gives each resource half its own VM, and
-- supplies the host surface they were written against:
--   CreateThread / Wait / SetTimeout          coroutines, resumed by `host:tick()` under a per-frame budget
--   AddEventHandler / TriggerEvent / RegisterNetEvent / TriggerClientEvent / TriggerServerEvent
--                                             two local event buses; "the network" is a queue drained each tick
--   GlobalState, Open77.state.*               one shared store (server writes, client reads), change callbacks
--   GetConvar, RegisterCommand, GetGameTimer, GetPlayerName, GetPlayerIdentifier, json, MySQL (server only)
--   Open77.<ns>.<fn>                          `api/server.lua` + `api/client.lua` (headless world model), overlaid
--                                             by `game/*.lua` bindings when running inside Cyberpunk (CET)
-- Anything a resource calls that the host does not implement returns nil, "unsupported_in_ncm_host" and is
-- COUNTED (`host.unsupported`), so the gap list is measured, never guessed.
-- Single player: exactly one player, id 1. `source` is 1 for every net event.
local Runtime = { version = "0.1.0" }
Runtime.__index = Runtime

local unpack = table.unpack or unpack
local function pack(...) return { n = select("#", ...), ... } end

-- ------------------------------------------------------------------------------------------------ helpers

--- Deep copy that behaves like a serialised network payload: functions/userdata/threads dropped, cycles cut.
local function wire(v, seen)
    local tv = type(v)
    if tv ~= "table" then
        if tv == "function" or tv == "userdata" or tv == "thread" then return nil end
        return v
    end
    seen = seen or {}
    if seen[v] then return nil end
    seen[v] = true
    local out = {}
    for k, x in pairs(v) do
        local kk = wire(k, seen)
        if kk ~= nil then out[kk] = wire(x, seen) end
    end
    seen[v] = nil
    return out
end
Runtime.wire = wire

--- Parse an `open77.lua` manifest (a declaration DSL, read as text the way ncm-stub does).
function Runtime.parseManifest(text)
    local m = { scripts = {}, deps = {}, name = text:match('resource%s+"([^"]+)"'), version = text:match('version%s+"([^"]+)"') }
    m.autoStart = not text:find("auto_start%s+false")
    for line in text:gmatch("[^\n]+") do
        local code = line:gsub("%-%-.*$", "")
        local kind, path = code:match("^%s*(%w+_script)%s+\"([^\"]+)\"")
        if kind then m.scripts[#m.scripts + 1] = { kind = kind, path = path } end
        local dep = code:match('^%s*dependency%s+"([^"]+)"')
        if dep then m.deps[#m.deps + 1] = dep end
        local page = code:match('^%s*web_ui_page%s+"([^"]+)"')
        if page then m.webPage = page end
    end
    return m
end

-- ------------------------------------------------------------------------------------------------ construction

--- opts: {
---   read(path) -> text|nil          file access (mod-relative in CET, repo paths in tests)
---   resourceRoot = "resources/"     where resource folders live
---   resources = { "ncm_league", ... }  load order
---   clock = { unix(), mono() }      host clock (dev skew lives in the clock, not here)
---   convars = { k = "v" }, MySQL = <shim>, json = { encode, decode }
---   player = { name, userId }, log(fmt, ...), budgetMs = 4, apis = { server = fn(host, vm) -> table, client = ... }
--- }
function Runtime.new(opts)
    local h = setmetatable({}, Runtime)
    h.opts = opts
    h.read = opts.read
    h.root = opts.resourceRoot or "resources/"
    h.clock = opts.clock
    h.convars = opts.convars or {}
    h.log = opts.log or function(fmt, ...) print(("[ncm-host] " .. fmt):format(...)) end
    h.budgetMs = opts.budgetMs or 4
    h.vms = {}                    -- list of vm
    h.threads = {}                -- { co, wakeAt (mono s), vm, label }
    h.handlers = { server = {}, client = {} }   -- name -> list { vm, fn }
    h.net = { server = {}, client = {} }        -- name -> true (RegisterNetEvent seen on that side)
    h.queue = {}                  -- network: { side, name, args }
    h.commands = {}               -- name -> { vm, fn }
    h.keyMappings = {}            -- command -> { vm, desc, device, key }
    h.global = {}                 -- GlobalState backing store
    h.bags = {}                   -- pid -> { k = v }
    h.bagWatch = {}               -- list { vm, key|nil, fn }
    h.unsupported = {}            -- "ns.fn" -> count
    h.errors = {}                 -- recent thread/handler errors { vm, label, err }
    h.players = { [1] = { id = 1, name = (opts.player and opts.player.name) or "V",
        userId = (opts.player and opts.player.userId) or "00000000-0000-4000-8000-00000000c0de", ready = false } }
    h.startedAt = h.clock.mono()
    h.started = {}
    h.apiFactories = opts.apis or {}
    h.exports = opts.exports or {}
    h.resourceExports = {}        -- "resource/side" -> { name -> fn }
    h.MySQL = opts.MySQL
    h.json = opts.json
    h.frame = 0
    -- compile(path, src, env) -> chunk bound to env. CET's sandbox has no `load`; the CET entry supplies one that works there
    h.compile = opts.compile or function(path, src, env) return load(src, "@" .. path, "t", env) end
    return h
end

function Runtime:err(vm, label, e)
    local msg = tostring(e)
    self.errors[#self.errors + 1] = { vm = vm and vm.key or "?", label = label, err = msg, at = self.clock.unix() }
    if #self.errors > 200 then table.remove(self.errors, 1) end
    self.log("%s %s: %s", vm and vm.key or "?", label, msg)
end

-- ------------------------------------------------------------------------------------------------ threads

function Runtime:spawn(vm, fn, label, ...)
    local args = pack(...)
    local co = coroutine.create(function() return fn(unpack(args, 1, args.n)) end)
    local t = { co = co, wakeAt = 0, vm = vm, label = label or "thread" }
    -- where the thread was made (file:line), so a slow frame can name it (KB-388 follow-up: measure, don't guess)
    if debug and debug.getinfo then
        local okI, info = pcall(debug.getinfo, fn, "S")
        if okI and info then t.where = (tostring(info.short_src):match("([^/\\]+/[^/\\]+/[^/\\]+)$") or info.short_src) .. ":" .. tostring(info.linedefined) end
    end
    -- run synchronously until the first Wait (FiveM/OPEN//77 handlers start immediately)
    self:resume(t)
    if coroutine.status(co) ~= "dead" then self.threads[#self.threads + 1] = t end
    return t
end

function Runtime:resume(t)
    local prev = self.current
    self.current = t
    local c0 = os.clock()
    local ok, delay = coroutine.resume(t.co)
    local ms = (os.clock() - c0) * 1000
    self.current = prev
    -- the frame's slowest resume, read and reset by the host after each frame
    local p = self.prof
    if not p then p = { ms = 0, n = 0, total = 0 }; self.prof = p end
    p.n, p.total = p.n + 1, p.total + ms
    if ms > p.ms then p.ms, p.label, p.vm, p.where = ms, t.label, t.vm and t.vm.key, t.where end
    if not ok then
        self:err(t.vm, t.label, debug and debug.traceback and debug.traceback(t.co, tostring(delay)) or delay)
        return
    end
    t.wakeAt = self.clock.mono() + (tonumber(delay) or 0)
end

--- Run due threads and deliver queued network events. Returns the number of resumes.
function Runtime:tick(budgetMs)
    self.frame = self.frame + 1
    -- page adapters (host/webui): plugin sockets polled, their events queued into the resources before threads run
    if self.webui and self.webui.tick then local okW, eW = pcall(self.webui.tick); if not okW then self:err({ key = "host/webui" }, "tick", eW) end end
    self:drainNetwork()
    local now = self.clock.mono()
    local deadline = os.clock() + (budgetMs or self.budgetMs) / 1000
    local n = 0
    local list = self.threads
    local live = {}
    local i = 1
    while i <= #list do
        local t = list[i]
        if coroutine.status(t.co) ~= "dead" and not t.vm.stopped then
            if t.wakeAt <= now and os.clock() < deadline then
                self:resume(t); n = n + 1
            end
            if coroutine.status(t.co) ~= "dead" then live[#live + 1] = t end
        end
        i = i + 1
    end
    -- threads spawned during this tick were appended to self.threads after `list` was captured? (same table) -- keep
    self.threads = live
    return n
end

--- Headless: advance the virtual clock in `step` second increments, ticking each time (tests / catch-up).
function Runtime:advance(seconds, step)
    step = step or 1
    local target = self.clock.mono() + seconds
    while self.clock.mono() < target do
        local dt = math.min(step, target - self.clock.mono())
        self.clock.advance(dt)
        self:tick(1e6)
    end
    self:tick(1e6)
end

-- ------------------------------------------------------------------------------------------------ events

function Runtime:addHandler(vm, name, fn)
    local list = self.handlers[vm.side][name]
    if not list then list = {}; self.handlers[vm.side][name] = list end
    local hnd = { vm = vm, fn = fn, name = name }
    list[#list + 1] = hnd
    return hnd
end

function Runtime:removeHandler(side, hnd)
    local list = hnd and self.handlers[side][hnd.name]
    if not list then return end
    for i, x in ipairs(list) do if x == hnd then table.remove(list, i); return end end
end

--- Invoke every handler for `name` on `side`. `src` sets the `source` global in each handler's VM.
--- The host itself listening to a resource event (e.g. `ncm:host:claimed`): called synchronously, never in a VM.
function Runtime:listen(side, name, fn)
    self.listeners = self.listeners or { server = {}, client = {} }
    self.listeners[side][name] = self.listeners[side][name] or {}
    table.insert(self.listeners[side][name], fn)
end

function Runtime:dispatch(side, name, src, args)
    local hl = self.listeners and self.listeners[side][name]
    if hl then
        for _, fn in ipairs(hl) do
            local ok, e = pcall(fn, unpack(args, 1, args.n))
            if not ok then self:err(nil, "host listener " .. name, e) end
        end
    end
    local list = self.handlers[side][name]
    if not list then return 0 end
    local snapshot = {}
    for i, x in ipairs(list) do snapshot[i] = x end
    for _, hnd in ipairs(snapshot) do
        if not hnd.vm.stopped then
            hnd.vm.env.source = src
            self:spawn(hnd.vm, hnd.fn, "event " .. name, unpack(args, 1, args.n))
        end
    end
    return #snapshot
end

function Runtime:trigger(side, name, ...)
    return self:dispatch(side, name, nil, pack(...))
end

function Runtime:drainNetwork()
    local q = self.queue
    if #q == 0 then return end
    self.queue = {}
    for _, m in ipairs(q) do
        self:dispatch(m.side, m.name, m.side == "server" and 1 or nil, m.args)
    end
end

function Runtime:send(side, name, ...)
    local raw = pack(...)
    local args = { n = raw.n }
    for i = 1, raw.n do args[i] = wire(raw[i]) end
    self.queue[#self.queue + 1] = { side = side, name = name, args = args }
end

-- ------------------------------------------------------------------------------------------------ state

function Runtime:makeGlobalState(vm)
    local h = self
    return setmetatable({}, {
        __index = function(_, k) return h.global[k] end,
        __newindex = function(_, k, v)
            if vm.side ~= "server" then h:err(vm, "GlobalState", "client write to GlobalState." .. tostring(k)); return end
            h.global[k] = wire(v)
        end,
    })
end

function Runtime:bag(pid)
    pid = tonumber(pid) or 0
    local b = self.bags[pid]
    if not b then b = {}; self.bags[pid] = b end
    return b
end

function Runtime:bagSet(pid, key, value)
    local b = self:bag(pid)
    local old = b[key]
    b[key] = wire(value)
    for _, w in ipairs(self.bagWatch) do
        if not w.vm.stopped and (w.key == nil or w.key == key) then
            self:spawn(w.vm, w.fn, "state.onChange " .. tostring(key), key, b[key], old)
        end
    end
    return true
end

-- ------------------------------------------------------------------------------------------------ VMs

local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "rawlen",
    "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "xpcall", "unpack", "load" }

--- A stub namespace: known functions resolve; unknown ones are counted and answer nil, "unsupported_in_ncm_host".
function Runtime:namespace(nsName, impl, vm)
    local h = self
    return setmetatable(impl or {}, {
        __index = function(t, fn)
            local key = vm.side .. ":" .. nsName .. "." .. tostring(fn)
            local f = function()
                h.unsupported[key] = (h.unsupported[key] or 0) + 1
                if h.unsupported[key] == 1 then h.log("unsupported %s (%s)", key, vm.key) end
                return nil, "unsupported_in_ncm_host"
            end
            rawset(t, fn, f)
            return f
        end,
    })
end

function Runtime:makeEnv(vm)
    local h = self
    local env = {}
    -- the standard library the resources see: from opts.globals when the host supplies it (CET: never assume its _G)
    local G = h.opts.globals or _G
    for _, k in ipairs(SAFE) do env[k] = G[k] end
    env.string, env.table, env.math, env.coroutine = G.string or string, G.table or table, G.math or math, G.coroutine or coroutine
    env.utf8 = rawget(G, "utf8")
    env.bit = rawget(G, "bit")
    env.unpack = unpack
    env._VERSION = _VERSION
    -- table.unpack exists in 5.4; LuaJIT gets a per-VM table copy so resources may call table.unpack portably
    if not table.unpack then
        local t2 = {}
        for k, v in pairs(table) do t2[k] = v end
        t2.unpack = unpack
        env.table = t2
    end
    env._G = env
    env.print = function(...)
        local parts = pack(...)
        for i = 1, parts.n do parts[i] = tostring(parts[i]) end
        h.log("%s: %s", vm.key, table.concat(parts, "\t", 1, parts.n))
    end

    env.CreateThread = function(fn) h:spawn(vm, fn, "CreateThread") end
    env.Citizen = { CreateThread = env.CreateThread }
    env.Wait = function(ms)
        if not coroutine.isyieldable or not coroutine.isyieldable() then
            if not h.current then error("Wait() outside a thread", 2) end
        end
        coroutine.yield((tonumber(ms) or 0) / 1000)
    end
    env.SetTimeout = function(ms, fn) h:spawn(vm, function() env.Wait(ms); fn() end, "SetTimeout") end
    env.GetGameTimer = function() return math.floor((h.clock.mono() - h.startedAt) * 1000) end
    env.GetCurrentResourceName = function() return vm.resource end
    env.GetConvar = function(k, d) local v = h.convars[k]; if v == nil then return d end; return tostring(v) end
    env.GetConvarInt = function(k, d) return tonumber(h.convars[k]) or d end
    env.GetPlayerName = function(pid) local p = h.players[tonumber(pid) or 0]; return p and p.name or nil end
    env.GetPlayerIdentifier = function(pid) local p = h.players[tonumber(pid) or 0]; return p and p.userId or nil end
    env.GetPlayers = function() return { "1" } end

    env.AddEventHandler = function(name, fn) return h:addHandler(vm, name, fn) end
    env.RemoveEventHandler = function(hnd) h:removeHandler(vm.side, hnd) end
    env.RegisterNetEvent = function(name, fn)
        h.net[vm.side][name] = true
        if fn then return h:addHandler(vm, name, fn) end
    end
    env.TriggerEvent = function(name, ...) h:trigger(vm.side, name, ...) end
    env.TriggerLocalEvent = env.TriggerEvent
    if vm.side == "server" then
        env.TriggerClientEvent = function(name, target, ...)
            target = tonumber(target) or -1
            if target == -1 or target == 1 then h:send("client", name, ...) end
        end
        env.MySQL = h.MySQL
        env.PerformHttpRequest = function(url, cb)
            -- no host bridge in single player (AC/KSA: doc 55 §G); answer like an unreachable endpoint
            h:spawn(vm, function() env.Wait(0); if cb then cb(0, nil, {}, "ncm_host: no http in single player") end end, "http")
        end
    else
        env.TriggerServerEvent = function(name, ...) h:send("server", name, ...) end
        env.RegisterKeyMapping = function(cmd, desc, device, key)
            h.keyMappings[cmd] = { vm = vm, desc = desc, device = device, key = key }
        end
    end
    -- `exports("name", fn)` publishes a function other resources reach with Open77.exports.call(resource, name, ...)
    env.exports = function(name, fn)
        local key = vm.resource .. "/" .. vm.side
        h.resourceExports[key] = h.resourceExports[key] or {}
        h.resourceExports[key][name] = fn
    end
    env.RegisterCommand = function(name, fn, restricted) h.commands[name] = { vm = vm, fn = fn, restricted = restricted } end
    env.json = h.json
    env.GlobalState = h:makeGlobalState(vm)

    local api = {}
    local factory = h.apiFactories[vm.side]
    local spec = factory and factory(h, vm) or {}
    for ns, impl in pairs(spec) do if ns:sub(1, 2) ~= "__" then api[ns] = h:namespace(ns, impl, vm) end end
    env.Open77 = setmetatable(api, {
        __index = function(t, ns)
            local s = h:namespace(ns, {}, vm)
            rawset(t, ns, s)
            return s
        end,
    })
    if spec.__WebUI then env.WebUI = spec.__WebUI end
    return env
end

function Runtime:loadVM(resource, side, manifest)
    local vm = { resource = resource, side = side, key = resource .. "/" .. side, stopped = false }
    vm.env = self:makeEnv(vm)
    local want = { shared_script = true }
    want[side .. "_script"] = true
    for _, s in ipairs(manifest.scripts) do
        if want[s.kind] then
            local path = self.root .. resource .. "/" .. s.path
            local src = self.read(path)
            if not src then error(("%s: missing script %s"):format(vm.key, path)) end
            local chunk, e = self.compile(path, src, vm.env)
            if not chunk then error(("%s: %s"):format(vm.key, tostring(e))) end
            local t = { co = coroutine.create(chunk), vm = vm, label = "load " .. s.path, wakeAt = 0 }
            self:resume(t)
            if coroutine.status(t.co) ~= "dead" then self.threads[#self.threads + 1] = t end
        end
    end
    self.vms[#self.vms + 1] = vm
    return vm
end

--- Load and start a list of resources (both halves), then announce the local player.
function Runtime:start()
    local list = self.opts.resources or {}
    for _, name in ipairs(list) do
        local text = self.read(self.root .. name .. "/open77.lua")
        if not text then error("no manifest for " .. name) end
        local m = Runtime.parseManifest(text)
        self.started[name] = { manifest = m }
        local hasServer, hasClient = false, false
        for _, s in ipairs(m.scripts) do
            if s.kind == "server_script" then hasServer = true end
            if s.kind == "client_script" then hasClient = true end
        end
        if hasServer then self.started[name].server = self:loadVM(name, "server", m) end
        if hasClient then self.started[name].client = self:loadVM(name, "client", m) end
    end
    for _, name in ipairs(list) do
        self:trigger("server", "onResourceStart", name)
        self:trigger("server", "onServerResourceStart", name)
    end
    for _, name in ipairs(list) do self:trigger("client", "onClientResourceStart", name) end
    self:tick(1e6)
end

function Runtime:connect()
    self:trigger("server", "playerConnecting", 1)
    self:trigger("server", "onPlayerConnected", 1)
    self:tick(1e6)
end

function Runtime:ready()
    self.players[1].ready = true
    self:trigger("server", "onPlayerReady", 1)
    self:trigger("client", "onClientReady", 1)
    self:tick(1e6)
end

--- Stop everything: disconnect, resource stop events, then mark every VM stopped (threads die with them).
function Runtime:stop(reason)
    self:trigger("server", "onPlayerDisconnected", 1, reason or "unmount")
    self:trigger("server", "playerDropped", reason or "unmount")
    local list = self.opts.resources or {}
    for i = #list, 1, -1 do
        self:trigger("client", "onClientResourceStop", list[i])
        self:trigger("server", "onResourceStop", list[i])
    end
    self:tick(1e6)
    for _, vm in ipairs(self.vms) do vm.stopped = true end
    self.threads = {}
    self.queue = {}
end

--- Run a registered command as the local player (dev console; the owner never types -- L??? no chat commands).
function Runtime:command(name, args, src)
    local c = self.commands[name]
    if not c then return nil, "no_such_command" end
    args = args or {}
    self:spawn(c.vm, c.fn, "command " .. name, src or 1, args, name .. " " .. table.concat(args, " "))
    return true
end

function Runtime:unsupportedList()
    local out = {}
    for k, n in pairs(self.unsupported) do out[#out + 1] = { key = k, n = n } end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

return Runtime
