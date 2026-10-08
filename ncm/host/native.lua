-- NCM Host, inside the ncm_host plugin (L338, KB-385): the dispatcher CET talks to through NcmHost_Call.
--
-- The plugin's VM is Lua 5.4 with the full standard library (coroutines, load with env) -- what OPEN//77 gives the
-- resources -- so the host modules and the resources run here unchanged. CET sends JSON commands; every answer is JSON
-- with `ok`. Game effects the world asks for (teleport, pins, toasts, a car into V's garage) are QUEUED and handed back
-- in the next `tick` answer for CET to perform; the player's position and car come in with every tick.
local ROOT = (NCM_HOST_ROOT or "."):gsub("\\", "/")
local native = require("ncmnative")
local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    native.log(ok and s or tostring(fmt), "info")
end

local function loadHost(rel)
    local chunk, err = loadfile(ROOT .. "/host/" .. rel)
    if not chunk then error(err) end
    return chunk()
end
local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end

local App = loadHost("app.lua")
local Clock = loadHost("clock.lua")
local Driver = loadHost("sql/driver_native.lua")

local app, json, test
local outbox = {}
local function push(op, t) t = t or {}; t.op = op; outbox[#outbox + 1] = t end

-- The game, as the world sees it from here: every effect becomes a command for CET.
local game = {
    teleport = function(pos, heading) push("teleport", { x = pos.x, y = pos.y, z = pos.z, heading = heading }); return true end,
    blipCreated = function(id, spec)
        local p = spec and (spec.position or (spec.x and spec))
        if p then push("pin", { id = id, x = p.x, y = p.y, z = p.z, title = spec.title }) end
    end,
    blipRemoved = function(id) push("unpin", { id = id }) end,
    blipUpdated = function(id, spec)
        local p = spec and (spec.position or (spec.x and spec))
        if p then push("pin", { id = id, x = p.x, y = p.y, z = p.z, title = spec.title }) end
    end,
    setWaypoint = function(pos) push("waypoint", pos and { x = pos.x, y = pos.y, z = pos.z } or { clear = true }) end,
    giveCar = function(record) push("giveCar", { record = record }); return true end,
    attach = function(h)
        h.onNotify = function(n)
            if type(n) == "table" then push("toast", { title = n.title or "NCM", message = n.message or n.text or "", ms = n.durationMs })
            else push("toast", { title = "NCM", message = tostring(n) }) end
        end
        h.onChat = function(text) push("chat", { text = tostring(text) }) end
    end,
    detach = function() push("clearPins", {}) end,
}

local function boot(p)
    if app then return end
    test = p.test == true
    local store = { devSkew = 0 }
    local env = {
        load = loadHost, read = readFile,
        write = function(path, s) local f = io.open(path, "wb"); if not f then return false end; f:write(s); f:close(); return true end,
        rename = function(a, b) os.remove(b); return os.rename(a, b) and true or false end,
        remove = function(path) os.remove(path) end,
        sqlite = function() return assert(Driver.open(p.memoryDb and ":memory:" or (ROOT .. "/ncm.sqlite3"))) end,
        log = log, resourceRoot = ROOT .. "/resources/",
        tapesPath = test and (ROOT .. "/save/ncm_tapes.selftest.json") or (ROOT .. "/save/ncm_tapes.json"),
        game = game, budgetMs = tonumber(p.budgetMs) or 3,
        -- loopback websockets / probe / http (src/net.cpp) for the plugin page adapters; the self-test has them too
        net = (native.ws_open and not p.noNet) and native or nil,
        clock = test and Clock.virtual(tonumber(p.virtualClock) or os.time()) or nil,
    }
    if test then os.remove(env.tapesPath); os.remove(env.tapesPath .. ".bak") end
    app = App.new(env)
    json = app.json
    log("NCM Host app ready: %d tape(s)%s", #app.store.doc.tapes, test and " [selftest]" or "")
end

local function deckRows()
    local rows = {}
    for _, r in ipairs(app:tapes()) do
        local t, pr = r.tape, r.present
        rows[#rows + 1] = { id = t.id, ordinal = t.ordinal, label = pr and pr.label or "RW ??", run = pr and pr.run, day = pr and pr.day,
            remaining = pr and app.Tapes.remaining(pr) or "", place = t.cache and t.cache.place or "surface",
            machine = t.cache and t.cache.machine and t.cache.machine.label or nil, ago = r.ago, devAltered = t.devAltered or false }
    end
    local d = app.store.doc
    return { tapes = rows, doc = { firstRunSeen = d.firstRunSeen or false, devMode = d.devMode or false, recovered = d.recovered,
        devSkewH = (tonumber(d.devSkew) or 0) / 3600 }, mounted = app.tape and app.tape.id or nil }
end

local function hud()
    if not (app.world and app.tape) then return nil end
    local pr = app.Tapes.present(app.tape, app.clock.unix(), app.core)
    if not pr then return nil end
    return { ordinal = app.tape.ordinal, label = pr.label, remaining = app.Tapes.remaining(pr), lastReturn = app.lastReturn }
end

local handlers = {}
function handlers.boot(p) boot(p); local out = deckRows(); out.version = "3.0.0-alpha.7"; out.host = _VERSION; return out end
function handlers.deck() return deckRows() end
function handlers.newTape() local t = app:newTape(); return { id = t.id, ordinal = t.ordinal } end
function handlers.setDoc(p)
    if p.key == "devMode" or p.key == "firstRunSeen" then app.store.doc[p.key] = p.value and true or false; app.store:save() end
    return deckRows()
end
function handlers.mount(p)
    local ok, why = app:mount(p.id)
    if not ok then return { ok = false, error = tostring(why) } end
    return { mounted = p.id, lastReturn = app.lastReturn }
end
function handlers.unmount() app:unmount("left the session"); return {} end
function handlers.tick(p)
    if app.world and type(p.player) == "table" then
        local P = app.world.world.player
        local pl = p.player
        if pl.x then P.position = { x = pl.x, y = pl.y, z = pl.z } end
        if pl.heading then P.heading = pl.heading end
        P.gameVehicle = type(pl.vehicle) == "table" and pl.vehicle or nil
    end
    if app.world then app:tick(tonumber(p.budgetMs) or 3) end
    local cmds = outbox
    outbox = {}
    return { hud = hud() or false, commands = cmds, lastClaim = app.lastClaim, mounted = app.tape and app.tape.id or nil }
end
function handlers.claim(p)
    local ok, rec = app:claim(p.record, p.appearance)
    if not ok then return { ok = false, error = tostring(rec) } end
    return { record = rec, lastClaim = app.lastClaim }
end
function handlers.garage()
    local cur = app.world and app.world.world.player.gameVehicle or nil
    return { mine = app:garage(), claimable = app:claimable(), current = cur, ordinal = app.tape and app.tape.ordinal or nil }
end
function handlers.aero(p)
    local snap, why = app:aeroCmd(p.action, p.arg)
    if snap == nil then return { ok = false, error = tostring(why) } end
    local mine = {}
    for _, m in ipairs(app:garage()) do if m.vehicleKey then mine[#mine + 1] = { vehicleKey = m.vehicleKey, record = m.record, serial = m.serial } end end
    return { aero = snap or false, machines = mine, devMode = app.store.doc.devMode or false }
end
function handlers.dev(p)
    local ok, why = app:dev(p.action, p.arg)
    if not ok then return { ok = false, error = tostring(why) } end
    return deckRows()
end
function handlers.advance(p)
    if not test and not app.store.doc.devMode then return { ok = false, error = "advance is a test/dev command" } end
    if app.world then app.world:advance(tonumber(p.seconds) or 0, 5) end
    return {}
end
function handlers.status()
    local w = app.world
    local errs = {}
    if w then for i = math.max(1, #w.errors - 4), #w.errors do errs[#errs + 1] = w.errors[i].vm .. ": " .. w.errors[i].err:sub(1, 300) end end
    return { mounted = app.tape and app.tape.id or nil, errors = w and #w.errors or 0, lastErrors = errs,
        unsupported = w and #w:unsupportedList() or 0, sql = app.mysql and app.mysql.stats or nil,
        plugins = app.webui and app.webui.summary() or nil, webui = app.webui and app.webui.stats or nil }
end
function handlers.shutdown() if app and app.world then app:unmount("game exit") end; return {} end

-- ------------------------------------------------------------------------------------------------ the game, no CET
-- L340 phase 2: redscript (r6/scripts/ncm_host/*.reds) drives NCM directly. Redscript has no JSON parser, so these
-- answers are LINES: one record per line, fields separated by '|', an empty field written '~' (the NCM Radial wire
-- rule: StrSplit collapses empty fields). The payloads coming IN are JSON as before (the host parses them).
local function esc(v)
    if v == nil then return "~" end
    if type(v) == "number" then return (string.format("%.3f", v):gsub("%.?0+$", "")) end
    local s = tostring(v):gsub("[|\r\n]", " ")
    return s == "" and "~" or s
end
local function ln(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = esc((select(i, ...))) end
    return table.concat(t, "|")
end
local function raw(lines) return { __raw = table.concat(lines, "\n") } end

--- The choice the deck or the phone made, applied to the session that is running now.
local function applyChoice()
    local c = app.store.doc.choice
    if type(c) ~= "table" then return "none" end
    if c.kind == "without" then
        if app.world then app:unmount("chose without NCM") end
        return "without"
    end
    if c.kind == "new" then
        local t = app:newTape()
        app.store.doc.choice = { kind = "tape", id = t.id }
        app.store:save()
        c = app.store.doc.choice
    end
    if c.kind == "tape" then
        if app.tape and app.tape.id == c.id then return "mounted" end
        if app.world then app:unmount("switched tape") end
        local ok, why = app:mount(c.id)
        if not ok then return "failed " .. tostring(why) end
        return "mounted"
    end
    return "none"
end

--- The Mod Settings value "Tape in play" -> the choice (L340: Mod Settings is the one place NCM is set up).
--- 0 = without NCM; n = TAPE n; a number past the last tape starts ONE new tape (it becomes the next TAPE).
local function selectOrdinal(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then app.store.doc.choice = { kind = "without" }; app.store:save(); return end
    for _, r in ipairs(app:tapes()) do
        if tonumber(r.tape.ordinal) == n then app.store.doc.choice = { kind = "tape", id = r.tape.id }; app.store:save(); return end
    end
    local c = app.store.doc.choice
    -- already started the new tape this number asked for (the setting keeps its value): keep it, never mint another
    if type(c) == "table" and c.kind == "tape" and c.fromSelect == n then return end
    local t = app:newTape()
    app.store.doc.choice = { kind = "tape", id = t.id, fromSelect = n }
    app.store:save()
end

--- A save finished loading (redscript's OnPlayerAttach). NCM stays dormant until a tape has been chosen.
function handlers.session(p)
    app.inSession = true
    if p and p.select ~= nil then selectOrdinal(p.select) end
    local state = applyChoice()
    local lines = { ln("state", state, app.tape and app.tape.id or nil, app.tape and app.tape.ordinal or nil) }
    if state == "none" or state == "without" then
        lines[#lines + 1] = ln("toast", "NIGHT CITY MOTORSPORTS", "NCM is off. To race: Settings -> Mod Settings -> Night City Motorsports -> Tape in play.", 9000)
    end
    return raw(lines)
end

--- Mod Settings changed while a session runs: apply the new "Tape in play" now.
function handlers.select(p)
    selectOrdinal(p.select)
    local state = app.inSession and applyChoice() or "chosen"
    return raw({ ln("state", state, app.tape and app.tape.id or nil, app.tape and app.tape.ordinal or nil) })
end

--- The session ended (back to the main menu, or quit).
function handlers.leave()
    app.inSession = false
    if app.world then app:unmount("left the session") end
    outbox = {}
    return raw({ ln("state", "dormant") })
end

--- Every frame while a session runs: the player in, the game commands out.
local SLOW_MS = 8
function handlers.frame(p)
    local c0 = os.clock()
    local t = handlers.tick(p)
    local ms = (os.clock() - c0) * 1000
    local w = app.world
    if w then
        local pr = w.prof
        -- a frame NCM held for more than SLOW_MS is logged with the job that took it (KB-388: measure, don't guess)
        if ms > SLOW_MS then
            log("slow frame %.1f ms: slowest %s %s (%s) %.1f ms of %d resume(s) %.1f ms", ms, tostring(pr and pr.vm), tostring(pr and pr.label),
                tostring(pr and pr.where), pr and pr.ms or 0, pr and pr.n or 0, pr and pr.total or 0)
        end
        w.prof = nil
    end
    local lines = {}
    local h = t.hud
    if h then lines[#lines + 1] = ln("hud", ("TAPE %02d  ·  %s"):format(tonumber(h.ordinal) or 0, tostring(h.label)), h.remaining) end
    for _, c in ipairs(t.commands or {}) do
        if c.op == "toast" then lines[#lines + 1] = ln("toast", c.title, c.message, c.ms)
        elseif c.op == "teleport" then lines[#lines + 1] = ln("teleport", c.x, c.y, c.z, c.heading)
        elseif c.op == "waypoint" then
            if c.clear then lines[#lines + 1] = ln("waypoint", "clear") else lines[#lines + 1] = ln("waypoint", c.x, c.y, c.z) end
        elseif c.op == "giveCar" then lines[#lines + 1] = ln("givecar", c.record)
        end
        -- pins / chat: map layers return in phase 3 under a budget (KB-387); chat lines become phone messages there
    end
    return raw(lines)
end

--- The tape screen (menu entry): every tape, what is mounted, what was chosen.
function handlers.tapes()
    local lines = {}
    local d = deckRows()
    for _, r in ipairs(d.tapes) do
        lines[#lines + 1] = ln("tape", r.id, r.ordinal, r.label, r.remaining, r.place, r.ago, r.devAltered and 1 or 0)
    end
    local c = app.store.doc.choice
    lines[#lines + 1] = ln("choice", type(c) == "table" and c.kind or nil, type(c) == "table" and c.id or nil)
    lines[#lines + 1] = ln("mounted", d.mounted)
    lines[#lines + 1] = ln("session", app.inSession and 1 or 0)
    return raw(lines)
end

--- Choose from the tape screen: { kind = "tape" | "new" | "without", id }. Applied now when a session runs, otherwise
--- when the next save finishes loading.
function handlers.choose(p)
    if p.kind ~= "tape" and p.kind ~= "new" and p.kind ~= "without" then return raw({ ln("error", "bad choice") }) end
    if p.kind == "tape" and not app.store:get(p.id) then return raw({ ln("error", "no such tape") }) end
    app.store.doc.choice = { kind = p.kind, id = p.id }
    app.store.doc.firstRunSeen = true
    app.store:save()
    local state = app.inSession and applyChoice() or "chosen"
    return raw({ ln("state", state, app.tape and app.tape.id or nil, app.tape and app.tape.ordinal or nil) })
end

return function(cmd, payload)
    local p = {}
    if payload and payload ~= "" and payload ~= "{}" then
        if not json then
            -- before the app exists (the boot command): its payload is flat -- "key": value pairs
            for k, v in payload:gmatch('"([%w_]+)"%s*:%s*([^,}]+)') do
                v = v:gsub('^%s*"', ""):gsub('"%s*$', "")
                if v == "true" then p[k] = true elseif v == "false" then p[k] = false else p[k] = tonumber(v) or v end
            end
        else
            local okP, dec = pcall(json.decode, payload)
            if okP and type(dec) == "table" then p = dec end
        end
    end
    local h = handlers[cmd]
    if not h then return '{"ok":false,"error":"unknown command ' .. tostring(cmd) .. '"}' end
    if cmd ~= "boot" and not app then boot({}) end
    local ok, res = pcall(h, p)
    if not ok then
        log("command %s failed: %s", cmd, tostring(res))
        res = { ok = false, error = tostring(res) }
    elseif type(res) ~= "table" then res = {} end
    if type(res.__raw) == "string" then return res.__raw end   -- line answers for redscript (L340 phase 2)
    if res.ok == nil then res.ok = true end
    if not json then
        -- the app never came up (a failed boot): answer without the core json
        local msg = tostring(res.error or "host not booted"):gsub('[%c"\\]', " ")
        return '{"ok":false,"error":"' .. msg .. '"}'
    end
    local okE, text = pcall(json.encode, res)
    if not okE then return '{"ok":false,"error":"encode failed: ' .. tostring(text):gsub('"', "'") .. '"}' end
    return text
end
