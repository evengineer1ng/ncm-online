-- NCM Host page adapters (plan "dev-server parity", phase 1): the NCM plugins, reached without a browser.
--
-- On the dev server each NCM plugin serves a tiny hidden page; the resource opens it with `WebUI.create({ entry =
-- "http://127.0.0.1:<port>/<page>" })` and the page's JavaScript relays named events to the plugin's websocket
-- (Carrier: ncm/carrier/src/bridge/server.cpp; Rig Bridge: ncm/rig_bridge/src/bridge.cpp; Vision, Broadcast, Pace:
-- ncm/<plugin>/src/bridge.cpp). Single player has no CEF, so the NCM Host plays that page itself: the same websocket
-- path, the same whitelist of outbound events and payload shapes, the same inbound events, the same 2 s reconnect.
-- The resources are unchanged -- they cannot tell a page from an adapter.
--
--   W.new({ net, json, log, now }) -> adapter with onCreate(page) / onSend(page, ev, p) / onDestroy(page) / tick()
--   net = ncmnative (ws_open/ws_send/ws_poll/ws_close, tcp_probe, http_start/http_poll) or a test double
--
-- A page whose port has nothing listening is REFUSED (create returns nil), exactly as CEF refused it: the resources
-- walk their port range on that signal (KB-147). Pages that are not a plugin's (web/panel.html ...) stay as recorded
-- stubs until their native screens exist (phase 3).
local W = { version = "0.1.0" }

local function pass(p) return p or {} end

-- Each spec IS the served page's script, line for line. `out` maps a page event to the frame it sends; `inbound` turns
-- one decoded frame into the events the page emits; `ready` / `closed` are the page's own handshake events.
W.SPECS = {
    carrier = {
        path = "/telemetry", ready = "ncm:ffb.ready", closed = "ncm:ffb.closed",
        out = {
            ["ncm:ffb.frame"] = function(p) return p end,
            ["ncm:ffb.idle"] = function(p) return { v = (p and p.v) or 1, idle = true } end,
            ["ncm:ffb.settings"] = function(p) return { cmd = "settings", settings = pass(p) } end,
            ["ncm:ffb.test"] = function(p) return { cmd = "test", test = pass(p) } end,
            ["ncm:machine.projection"] = function(p) return { cmd = "projection", projection = pass(p) } end,
            ["ncm:machine.handling"] = function(p) return { cmd = "handling", handling = pass(p) } end,
            ["ncm:machine.wrench"] = function(p) return { cmd = "wrench", wrench = pass(p) } end,
            ["ncm:machine.archdump"] = function(p) return { cmd = "archdump", records = (p and p.records) or {} } end,
            ["ncm:machine.geardump"] = function(p) return { cmd = "geardump", records = (p and p.records) or {} } end,
        },
        inbound = function(m, emit)
            if m.device then emit("ncm:ffb.device", m.device) end
            if m.health then emit("ncm:carrier.health", m.health) end
        end,
    },
    rig = {
        path = "/rig", ready = "ncm:ffb.ready", closed = "ncm:ffb.closed", pad = true,
        out = {
            ["ncm:ffb.frame"] = function(p) return p end,
            ["ncm:ffb.idle"] = function(p) return { v = (p and p.v) or 1, idle = true } end,
            ["ncm:ffb.settings"] = function(p) return { cmd = "settings", settings = pass(p) } end,
            ["ncm:ffb.test"] = function(p) return { cmd = "test", test = pass(p) } end,
            ["ncm:ffb.bind"] = function(p) return { cmd = "bind", bind = pass(p) } end,
        },
        inbound = function(m, emit)
            if m.device then emit("ncm:ffb.device", m.device) end
            if m.rig then emit("ncm:rig.health", m.rig) end
        end,
    },
    vision = {
        path = "/vision", ready = "ncm:vision.ready", closed = "ncm:vision.closed",
        out = { ["ncm:vision.send"] = pass },
        inbound = function(m, emit)
            if m.vision then emit("ncm:vision.target", m.vision) elseif m.health then emit("ncm:vision.health", m.health) end
        end,
    },
    broadcast = {
        path = "/broadcast", ready = "ncm:bcast.ready", closed = "ncm:bcast.closed",
        out = { ["ncm:bcast.send"] = pass },
        inbound = function(m, emit) emit("ncm:bcast.msg", m) end,
    },
    pace = {
        path = "/pace", ready = "ncm:pace.ready", closed = "ncm:pace.closed",
        out = { ["ncm:pace.send"] = pass },
        inbound = function(m, emit) emit("ncm:pace.msg", m) end,
    },
}

-- Which plugin owns a page: its file and its port range (each plugin owns four ports; Carrier and Rig Bridge both
-- serve bridge.html, told apart by range -- the same ranges the resources walk).
W.RANGES = {
    { lo = 38480, hi = 38483, page = "bridge.html", spec = "carrier" },
    { lo = 38520, hi = 38523, page = "bridge.html", spec = "rig" },
    { lo = 38600, hi = 38603, page = "vision.html", spec = "vision" },
    { lo = 38640, hi = 38643, page = "pace.html", spec = "pace" },
    { lo = 38680, hi = 38683, page = "broadcast.html", spec = "broadcast" },
}
W.RETRY_S = 2
W.PAD_CHUNK = 3000

--- The plugin a page entry belongs to, or nil (an ordinary NCM page).
function W.match(entry)
    if type(entry) ~= "string" then return nil end
    local host, port, file = entry:match("^http://([%w%.%-]+):(%d+)/([%w_%.%-]+)")
    port = tonumber(port)
    if not port then return nil end
    for _, r in ipairs(W.RANGES) do
        if port >= r.lo and port <= r.hi and file == r.page then return r.spec, host, port end
    end
    return nil
end

function W.new(o)
    local net, json, log, now = o.net, o.json, o.log or function() end, o.now or os.clock
    local A = { conns = {}, stats = { created = 0, refused = 0, sent = 0, received = 0 } }

    local function emitter(c)
        return function(ev, payload) c.page:emit(ev, payload) end
    end

    local function open(c)
        c.id = net.ws_open(("ws://%s:%d%s"):format(c.host, c.port, c.spec.path))
        c.ready, c.retryAt = false, nil
    end

    function A.onCreate(page)
        local name, host, port = W.match(page.entry)
        if not name then return nil end
        if not net.tcp_probe(host, port, 150) then
            A.stats.refused = A.stats.refused + 1
            return false, "nothing listening on " .. host .. ":" .. port
        end
        local c = { page = page, spec = W.SPECS[name], name = name, host = host, port = port, pads = {} }
        A.conns[page.id] = c
        open(c)
        A.stats.created = A.stats.created + 1
        log("webui: %s page %s -> native adapter (ws %s:%d%s)", name, page.entry, host, port, c.spec.path)
        return true
    end

    function A.onDestroy(page)
        local c = A.conns[page.id]
        if not c then return end
        if c.id then net.ws_close(c.id) end
        A.conns[page.id] = nil
    end

    function A.onSend(page, ev, payload)
        local c = A.conns[page.id]
        if not c then return end
        if ev == "ncm:pad.req" and c.spec.pad then
            -- Rig Bridge's pad service (HTTP on port + 10): GET /pad/state or POST /pad/cmd, answered in 3000-char parts
            local p = payload
            if type(p) ~= "table" or not p.id then return end
            local path = p.path == "/pad/cmd" and "/pad/cmd" or "/pad/state"
            local base = p.base or ("http://127.0.0.1:" .. (c.port + 10))
            local rid = net.http_start(path == "/pad/cmd" and "POST" or "GET", base .. path, path == "/pad/cmd" and tostring(p.body or "{}") or nil)
            if rid then c.pads[#c.pads + 1] = { rid = rid, id = p.id } else c.page:emit("ncm:pad.fail", { id = p.id, error = "bad url" }) end
            return
        end
        local f = c.spec.out[ev]
        if not f or not c.ready then return end          -- the page drops what it does not whitelist, and anything before open
        local ok, text = pcall(json.encode, f(payload))
        if ok and net.ws_send(c.id, text) then A.stats.sent = A.stats.sent + 1 end
    end

    function A.tick()
        local t = now()
        for _, c in pairs(A.conns) do
            local emit = emitter(c)
            if c.retryAt then
                if t >= c.retryAt then open(c) end
            else
                local state, msgs, err = net.ws_poll(c.id)
                if state == "open" and not c.ready then
                    c.ready = true
                    emit(c.spec.ready, { detail = ("http://%s:%d"):format(c.host, c.port) })
                end
                for _, m in ipairs(msgs or {}) do
                    local ok, dec = pcall(json.decode, m)
                    if ok and type(dec) == "table" then
                        A.stats.received = A.stats.received + 1
                        pcall(c.spec.inbound, dec, emit)
                    end
                end
                if state == "closed" then
                    if c.ready then emit(c.spec.closed, { detail = tostring(err or "socket closed") }) end
                    net.ws_close(c.id)
                    c.ready, c.id, c.retryAt = false, nil, t + W.RETRY_S
                end
            end
            for i = #c.pads, 1, -1 do
                local q = c.pads[i]
                local done, status, body, err = net.http_poll(q.rid)
                if done then
                    table.remove(c.pads, i)
                    if err or (status or 0) < 200 or (status or 0) >= 300 then
                        emit("ncm:pad.fail", { id = q.id, error = err or ("HTTP " .. tostring(status)) })
                    else
                        body = body or ""
                        local n = math.max(1, math.ceil(#body / W.PAD_CHUNK))
                        for k = 1, n do emit("ncm:pad.part", { id = q.id, i = k, n = n, s = body:sub((k - 1) * W.PAD_CHUNK + 1, k * W.PAD_CHUNK) }) end
                    end
                end
            end
        end
    end

    --- What is connected, for the status command and logs.
    function A.summary()
        local out = {}
        for _, c in pairs(A.conns) do out[#out + 1] = { plugin = c.name, port = c.port, ready = c.ready } end
        table.sort(out, function(a, b) return a.port < b.port end)
        return out
    end

    return A
end

return W
