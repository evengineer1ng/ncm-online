-- KB-444: the Deep stage handshake (ncm_world server/deep.lua + client/deepview.lua) against deterministic doubles.
-- Open77 does not keep the order of different net events; the 2026-10-10 23:40 entry's one stage request reached the
-- server before ENTER and was dropped, so the car stayed frozen at the seam over Night City. Proved here: an early
-- request is said and not acted on, the client repeats until acknowledged, the car moves once, a repeat is re-acked.
local root = arg[1] or "."
local passed = 0
local realPrint = print
local logs = {}
local function check(label, value)
    if not value then
        realPrint("  FAIL " .. label)
        for _, l in ipairs(logs) do realPrint("    log| " .. l) end
        error(label, 0)
    end
    passed = passed + 1; realPrint("  PASS " .. label)
end
local function logged(pat) for _, l in ipairs(logs) do if l:find(pat) then return true end end return false end

-- ---------------------------------------------------------------- platform doubles (one table per side)
local server, client = {}, {}
local toServer, toClient = {}, {}     -- queued net events, delivered when the test says
local side = server
function AddEventHandler(name, fn) side[name] = side[name] or {}; table.insert(side[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function RegisterCommand() end
function TriggerServerEvent(name, body) toServer[#toServer + 1] = { name = name, body = body } end
function TriggerClientEvent(name, pid, body) toClient[#toClient + 1] = { name = name, pid = pid, body = body } end
local threads = {}
function CreateThread(fn) threads[#threads + 1] = fn end   -- kept, run only where a check says so
function Wait(ms) if ms == 60000 then error("one pass", 0) end end   -- the FRAME loop's sleep ends a test pass
function GetConvar(_, d) return d end
function GetCurrentResourceName() return "ncm_world" end
function print(s) logs[#logs + 1] = tostring(s) end
GlobalState = { ncmIdentity = { serverId = "test", environment = "online" } }

local moves, frozen = {}, {}
Open77 = {
    time = { unix = function() return 1791684477 end },
    vehicles = {
        get = function(vid) return { id = vid, position = { x = -352, y = 498, z = 12004 }, flags = 7 } end,
        setFrozen = function(vid, on) frozen[vid] = on; return true, "ok" end,
        setTransform = function(vid, t) moves[#moves + 1] = { vid = vid, t = t }; return true, "ok" end,
        update = function() return true end,
    },
    exports = { call = function() return true end },
}
NcmVehicleAccess = { bindingForAuthority = function(pid) return { vehicleId = 77, assetId = "10000000-0000-4000-8000-000000000002" } end }

NcmCore = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
side = server; dofile(root .. "/ncm/online/resources/ncm_world/server/deep.lua")
local frameThreadFn = threads[#threads]   -- the FRAME logger is the last thread server/deep.lua starts
side = client; dofile(root .. "/ncm/online/resources/ncm_world/client/deepview.lua")

local function deliverServer(filter)
    local keep = {}
    for _, e in ipairs(toServer) do
        if not filter or filter(e) then
            source = 3
            for _, fn in ipairs(server[e.name] or {}) do fn(e.body) end
        else keep[#keep + 1] = e end
    end
    toServer = keep
end
local function deliverClient()
    local list = toClient; toClient = {}
    for _, e in ipairs(list) do for _, fn in ipairs(client[e.name] or {}) do fn(e.body) end end
end
local function count(name) local n = 0; for _, e in ipairs(toServer) do if e.name == name then n = n + 1 end end; return n end

-- the Galena's persisted state at 2026-10-11 02:07:58 UTC (docs/research/open77/snapshots), ~41,000 km up
local s = { p = { -34253376.66284, -20117066.768708, 28082828.220792 }, v = { -4235.26, 776.54, 2300.45 },
    basis = { forward = { -0.57980184, -0.28491936, -0.76331565 }, right = { -0.69925885, 0.65485410, 0.28671096 },
        up = { -0.41817088, -0.69999077, 0.57891799 } } }

realPrint("deep stage handshake (KB-444)")
-- the client's first Deep frame: the stage request goes out with ENTER in the same frame
TriggerServerEvent("ncm:deep.enter", { vx = 0, vy = 0, vz = 96.6, mass = 2294 })
NcmDeepView.update(s, 1791684477, 10000)
check("first frame sends one stage request", count("ncm:deep.stage") == 1)

-- the network delivers the stage request BEFORE ENTER (what the 23:40 server log shows for PRESENCE)
deliverServer(function(e) return e.name == "ncm:deep.stage" end)
check("an early stage request does not move the car", #moves == 0)
check("an early stage request is said in the log", logged("arrived before ENTER"))
check("no acknowledgement for an early request", #toClient == 0)

deliverServer()   -- now ENTER
check("ENTER froze the car", frozen[77] == true)

-- frames inside the retry interval do not resend; the next one past it does
NcmDeepView.update(s, 1791684477, 10100)
check("no resend inside the retry interval", count("ncm:deep.stage") == 0)
NcmDeepView.update(s, 1791684478, 10600)
check("the client repeats the unacknowledged request", count("ncm:deep.stage") == 1)
deliverServer()
check("the repeat moves the car once, to the near stage", #moves == 1 and moves[1].t.position.x == -12000 and moves[1].t.position.y == 12000)
check("the car stays frozen at the stage", frozen[77] == true)
check("the server acknowledges with the request's seq", #toClient == 1 and toClient[1].name == "ncm:deep.staged" and toClient[1].body.seq == 10000)
deliverClient()
check("the client hears the confirmation", logged("stage confirmed by the server after 2 request"))

for t = 11200, 14000, 600 do NcmDeepView.update(s, 1791684480, t) end
check("no more requests once confirmed", count("ncm:deep.stage") == 0)

-- a duplicate that was already in flight: acknowledged again, never a second move
TriggerServerEvent("ncm:deep.stage", { stage = "near", x = -12000, y = 12000, z = 8000, yaw = 0, seq = 10000 })
deliverServer()
check("a repeat after staging never moves the car again", #moves == 1)
check("a repeat after staging is acknowledged again", #toClient == 1 and toClient[1].name == "ncm:deep.staged")
deliverClient()

-- a lost server: the client gives up after 40 requests and says so once
NcmDeepView.clear()
toServer = {}
NcmDeepView.update(s, 1791684490, 20000)
for t = 20500, 20000 + 500 * 45, 500 do NcmDeepView.update(s, 1791684490, t) end
check("the client stops after 41 requests", count("ncm:deep.stage") == 41)
check("an unconfirmed stage is said loudly", logged("STAGE NOT CONFIRMED"))

-- KB-448: the rejoin. The server materialized and froze the car itself, so no physics binding is proven; the join's
-- claim lets ENTER take that vehicle, and the stage then moves it. Without the claim ENTER is refused (and says why).
fire = function(name, pid, body) source = pid; for _, fn in ipairs(server[name] or {}) do fn(body) end end
fire("playerDropped", 3)
NcmVehicleAccess = { bindingForAuthority = function() return nil, "no_owned_active_asset" end }
Open77.vehicles.owner = function(vid) return { driver = 3, physicsOwner = 0, epoch = 1 } end
moves, toClient = {}, {}
fire("ncm:deep.enter", 3, { vx = 0, vy = 0, vz = 0, mass = 2294 })
check("rejoin without a claim: ENTER refused, with the reason", logged("enter refused: not driving a bound Machine %(no_owned_active_asset%)"))
NcmDeepResumeClaims[3] = { vid = 88, asset = "10000000-0000-4000-8000-000000000002" }
fire("ncm:deep.enter", 3, { vx = 0, vy = 0, vz = 0, mass = 2294 })
check("rejoin with the claim: ENTER takes the resumed Machine", logged("the resumed Machine ..000002 %(vehicle 88, driver 3"))
check("the claim is used once", NcmDeepResumeClaims[3] == nil)
check("the resumed Machine is frozen", frozen[88] == true)
fire("ncm:deep.stage", 3, { stage = "near", x = -12000, y = 12000, z = 8000, yaw = 0, seq = 777 })
check("the resumed Machine is staged into space", #moves == 1 and moves[1].vid == 88 and moves[1].t.position.z == 8000)
check("and the stage is acknowledged", #toClient == 1 and toClient[1].body.seq == 777)
NcmDeepResumeClaims[3] = { vid = 88 }
fire("playerDropped", 3)
check("a claim never outlives its player", NcmDeepResumeClaims[3] == nil)

-- IDEA-1294: the FRAME line, from the Galena's stored record exactly as the snapshot holds it (read-only: one query)
local snapshotJson = [[{"asset":"10000000-0000-4000-8000-000000000002","basis":{"forward":[-0.57980184099642,-0.28491936136547,-0.76331565076071],"right":[-0.69925885323768,0.65485409333951,0.28671095654896],"up":[-0.41817087577435,-0.69999076705024,0.57891799479592]},"dyn":{"omega":[1.9697012190059e-29,0,0],"thr":[0]},"p":[-34253376.66284,-20117066.768708,28082828.220792],"place":"deep","provenance":["observed"],"utc":1791684477.441,"vel":[-4235.2601132799,776.53671231107,2300.4487539257]}]]
local queries = 0
MySQL = { query = { await = function(sql) queries = queries + 1
    check("FRAME reads only Deep presence rows", sql:find("^SELECT") and sql:find("place='deep'"))
    return { { driver_id = "11111111-1111-4111-8111-111111111111", place = "deep", host = "cyberpunk", state_json = snapshotJson } } end } }
pcall(frameThreadFn)
check("the FRAME pass ran one query", queries == 1)
local frame = nil
for _, l in ipairs(logs) do if l:find("FRAME driver ..111111") then frame = l end end
check("the FRAME line is written", frame ~= nil)
check("FRAME: Earth-fixed speed and its horizontal part (the HUD's numbers)", frame and frame:find("|v| 4881.9 = horizontal 2814.4", 1, true) ~= nil)
check("FRAME: inertial speed, almost all radial", frame and frame:find("INERTIAL |v| 3989.8 = radial +3988.9", 1, true) ~= nil)
check("FRAME: bound, apo 1,694,067 km", frame and frame:find("apo 1694067 km") ~= nil)
check("FRAME: no unreadable record", not logged("not readable"))

realPrint(("deep stage host: %d checks passed"):format(passed))
