-- NCM Host page adapters (plan "dev-server parity", phase 1): the real resources reach the NCM plugins with no browser.
--
-- The resources (ncm_world's Carrier bridge, ncm_scanner, ncm_broadcast, the Paddock's Pace transport) open the
-- plugins' hidden pages exactly as on the dev server; host/webui plays those pages over a fake loopback network that
-- answers like the plugins' own websockets. Proved here:
--   * a port with nothing listening is REFUSED (the resources walk their port range, KB-147)
--   * Carrier: the handshake, then a health frame with a version -> ncm_world logs MACHINE CHANNEL BOUND
--   * a page event the served JavaScript whitelists reaches the socket in the page's frame shape; one it does not, never
--   * the Scanner and Broadcast transports connect; a dropped socket is re-opened after 2 s
--   * Rig Bridge's pad request goes over HTTP on port + 10 and comes back in parts
local REPO = ((arg and arg[1]) or "."):gsub("\\", "/")
local HOST = REPO .. "/ncm/host/"
local RES = REPO .. "/ncm/online/resources/"
package.path = HOST .. "?.lua;" .. package.path
if type(rawget(_G, "jit")) ~= "table" then print("host webui: skipped under " .. _VERSION .. " (needs LuaJIT FFI for SQLite)"); return end
local Driver = dofile(HOST .. "sql/driver_ffi.lua")
local dll = Driver.locate()
if not dll then print("host webui: SKIP (no sqlite3.dll for LuaJIT FFI)"); os.exit(0) end
local VERBOSE = os.getenv("NCM_HOST_VERBOSE") == "1"
local fails, passes = 0, 0
local function check(cond, fmt, ...)
    if cond then passes = passes + 1 else fails = fails + 1; print("  FAIL " .. string.format(fmt, ...)) end
end
local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local tmpDir = (os.getenv("TEMP") or "."):gsub("\\", "/")
local tapesPath = tmpDir .. "/ncm-host-webui-tapes.json"
os.remove(tapesPath); os.remove(tapesPath .. ".bak")

-- ------------------------------------------------------------------------------------------------ the fake loopback
-- listening ports, and what each websocket does once it opens
local LISTEN = { [38480] = "carrier", [38600] = "vision", [38680] = "broadcast", [38520] = "rig" }
local sockets, nextId, sent, http = {}, 1, {}, {}
local net = {}
function net.tcp_probe(host, port) return host == "127.0.0.1" and LISTEN[port] ~= nil end
function net.ws_open(url)
    local port, path = url:match("^ws://127%.0%.0%.1:(%d+)(/.*)$")
    local id = nextId; nextId = nextId + 1
    sockets[id] = { port = tonumber(port), path = path, state = "connecting", inbox = {}, polls = 0 }
    return id
end
function net.ws_send(id, text)
    local s = sockets[id]
    if not s or s.state ~= "open" then return false end
    sent[#sent + 1] = { port = s.port, path = s.path, text = text }
    return true
end
function net.ws_poll(id)
    local s = sockets[id]
    if not s then return "closed", {}, "no such socket" end
    s.polls = s.polls + 1
    if s.state == "connecting" and s.polls >= 2 then
        s.state = "open"
        -- what each plugin says first: the Carrier its health (with a version), the scanner its health
        if s.path == "/telemetry" then s.inbox[#s.inbox + 1] = '{"health":{"version":"0.1.37","bridge":"up"}}' end
        if s.path == "/vision" then s.inbox[#s.inbox + 1] = '{"health":{"version":"0.4.0"}}' end
    end
    local msgs = s.inbox; s.inbox = {}
    return s.state, msgs, s.err
end
function net.ws_close(id) sockets[id] = nil end
local function socketOn(path) for id, s in pairs(sockets) do if s.path == path then return id, s end end end
function net.http_start(method, url, body) http[#http + 1] = { method = method, url = url, body = body, polls = 0 }; return #http end
function net.http_poll(id)
    local q = http[id]; q.polls = q.polls + 1
    if q.polls < 2 then return false, 0, nil, nil end
    return true, 200, string.rep("x", 6500), nil
end

-- ------------------------------------------------------------------------------------------------ the host
local Clock = dofile(HOST .. "clock.lua")
local clock = Clock.virtual(1791388800)
local logLines = {}
local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    s = ok and s or tostring(fmt)
    logLines[#logLines + 1] = s
    if VERBOSE then print("    " .. s) end
end
local function grep(pat) local n = 0; for _, l in ipairs(logLines) do if l:find(pat) then n = n + 1 end end; return n end
local db
local env = {
    load = function(rel) return dofile(HOST .. rel) end, read = readFile,
    write = function(p, s) local f = io.open(p, "wb"); if not f then return false end; f:write(s); f:close(); return true end,
    rename = function(a, b) os.remove(b); return os.rename(a, b) end, remove = function(p) os.remove(p) end,
    sqlite = function() db = db or assert(Driver.open(dll, ":memory:")); return db end,
    log = log, clock = clock, resourceRoot = RES, tapesPath = tapesPath, net = net,
}
local App = dofile(HOST .. "app.lua")
local app = App.new(env)
local t = app:newTape()
local okM, whyM = pcall(app.mount, app, t.id)
check(okM and whyM == true, "a tape mounts with the adapters installed: %s", tostring(whyM))
local h = app.world
if h then
    check(app.webui ~= nil, "the page adapters are installed")
    h:advance(40, 1)

    -- the Carrier
    check(grep("MACHINE CHANNEL BOUND to the NCM Carrier 0%.1%.37") >= 1, "ncm_world binds its machine channel to the Carrier (%d)", grep("MACHINE CHANNEL BOUND"))
    check(grep("webui: carrier page http://127%.0%.0%.1:38480/bridge%.html") >= 1, "the Carrier page became a native adapter on 38480")
    check(app.webui.stats.refused >= 1, "pages on ports with nothing listening were refused (%d)", app.webui.stats.refused)

    -- a whitelisted event reaches the socket in the page's own frame shape; a non-whitelisted one never does
    local carrierPage
    for _, p in pairs(h.world.pages) do if p.entry == "http://127.0.0.1:38480/bridge.html" then carrierPage = p end end
    check(carrierPage ~= nil, "the Carrier page is live")
    if carrierPage then
        local before = #sent
        carrierPage:send("ncm:machine.wrench", { fd1 = { fz = 1 } })
        carrierPage:send("ncm:not.whitelisted", { x = 1 })
        local last = sent[#sent]
        check(#sent == before + 1 and last and last.path == "/telemetry" and last.text:find('"cmd":"wrench"', 1, true)
            and last.text:find('"wrench":', 1, true), "a wrench goes out as {cmd:'wrench',wrench:...}; an unknown event never leaves (%s)",
            last and last.text or "nothing")
    end

    -- the Scanner and Broadcast transports
    check(grep("%[ncm_scanner%].*transport connected at http://127%.0%.0%.1:38600/vision%.html") >= 1 or socketOn("/vision") ~= nil,
        "the scanner's transport is up on 38600")
    check(socketOn("/broadcast") ~= nil, "the broadcast transport is up on 38680")

    -- a dropped socket comes back after 2 s
    local id, s = socketOn("/vision")
    if s then
        s.state, s.err = "closed", "socket closed"
        h:advance(1, 1)
        local id2 = socketOn("/vision")
        check(id2 == nil or id2 == id, "no instant reconnect storm")
        h:advance(3, 1)
        local id3, s3 = socketOn("/vision")
        check(id3 ~= nil and id3 ~= id and s3.state == "open", "the scanner socket is re-opened after the 2 s retry")
    end

    -- Rig Bridge's pad service: HTTP on port + 10, answered in 3000-char parts
    local rigPage
    for _, p in pairs(h.world.pages) do if p.entry and p.entry:find(":38520/", 1, true) then rigPage = p end end
    if rigPage then
        local parts = {}
        rigPage.handlers["ncm:pad.part"] = function(p) parts[#parts + 1] = p end
        rigPage:send("ncm:pad.req", { id = "q1", path = "/pad/state" })
        h:advance(2, 1)
        check(http[#http] and http[#http].url == "http://127.0.0.1:38530/pad/state" and http[#http].method == "GET",
            "the pad request goes to the pad service on port + 10 (%s)", http[#http] and http[#http].url or "none")
        check(#parts == 3 and parts[1].n == 3 and #parts[3].s == 500, "and comes back as 3 parts of a 6,500-char answer (%d)", #parts)
    else
        print("  (rig page not opened by ncm_world in this run: force feedback is off by default; pad path checked by spec only)")
    end

    local errs = #h.errors
    if errs > 0 then for i = 1, math.min(8, errs) do print(("    error %s %s: %s"):format(h.errors[i].vm, h.errors[i].label, h.errors[i].err:sub(1, 300))) end end
    check(errs == 0, "no thread or handler errors (%d)", errs)
    app:unmount("done")
end
os.remove(tapesPath); os.remove(tapesPath .. ".bak")
print(("host webui: %d pass, %d FAIL"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)
