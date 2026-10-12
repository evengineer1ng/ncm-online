-- ncm_world/client/engineering.lua against deterministic doubles (KB-429): the server re-sends an UNCHANGED Machine on
-- every odometer checkpoint; the client must keep its running state (throttle lag, hold gesture, heat, the burn not yet
-- reported) instead of rebuilding from zero, and must rebuild when the parts or bindings really change. In Deep a gap in
-- the binding bag must not take the parts away.
local root = arg[1] or "."
local passed = 0
local function check(label, value)
    if not value then print("  FAIL " .. label); error(label, 0) end
    passed = passed + 1; print("  PASS " .. label)
end

local handlers, threads = {}, {}
function RegisterNetEvent(name, fn) handlers[name] = fn end
function AddEventHandler() end
function RegisterCommand() end
function TriggerServerEvent() end
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait() coroutine.yield() end
function exports() end
local now = 0
function GetGameTimer() return now end
local bag = { ncmHandling = { bound = true, assetId = "M1", vehicleId = 7 } }
Open77 = {
    state = { localPlayer = function() return bag end },
    vehicles = { getPlayerSeat = function() return { vehicleId = 7 } end },
    input = { isCaptured = function() return false end, isDown = function() return false end },
}
local realPrint = print
print = function() end

NcmCore = dofile(root .. "/ncm/core/init.lua")
for _, f in ipairs(dofile(root .. "/ncm/core/MANIFEST.lua")) do dofile(root .. "/ncm/core/" .. f) end
dofile(root .. "/ncm/online/resources/ncm_world/client/engineering.lua")
print = realPrint
local function run() for _, co in ipairs(threads) do if coroutine.status(co) ~= "dead" then coroutine.resume(co) end end end
run(); run()          -- the binding thread reads the bag: bound to M1

local Install = NcmCore.get("engineering.installation")
local function payload(fill, bindings)
    return { v = 2, assetId = "M1", vehicleKey = "archer_hella", fuel = { ml = 40000 },
        items = { { componentId = "C-FD1", designId = "eng:zetatech:fd1:r1", mountId = "mount.underside", facing = "down" },
                  { componentId = "C-PT", designId = "eng:zetatech:pt500:r1", mountId = "mount.front", facing = "up", fillKg = fill } },
        specs = {}, bindings = bindings or { { control = "padY", gesture = "hold", componentId = "C-FD1", command = "throttle" } } }
end

handlers["ncm:engineering"](payload(380))
local E = NcmClientEngineering.get()
check("the Machine arrives with its parts", E and #E.devices >= 1)
local state, ctl = E.state, E.ctl
E.ctl.marker = "holding"
E.report.fusionKg = 2.5                          -- burned since the last report to the server
handlers["ncm:engineering"](payload(380))        -- the odometer checkpoint: same Machine, same fill
E = NcmClientEngineering.get()
check("an unchanged re-send keeps the runtime state", E.state == state)
check("...and the control (hold) state", E.ctl == ctl and E.ctl.marker == "holding")
check("...and counts the unreported burn against the server's fill", math.abs(E.fusionKg - 377.5) < 1e-6)
check("...and keeps the unreported burn to report", E.report.fusionKg == 2.5)
handlers["ncm:engineering"](payload(380, { { control = "padX", gesture = "hold", componentId = "C-FD1", command = "throttle" } }))
E = NcmClientEngineering.get()
check("a changed binding rebuilds", E.ctl ~= ctl and E.ctl.marker == nil)

NcmClientDeepActive = true
bag.ncmHandling = nil                             -- a gap in the bag mid-Deep
run()
check("in Deep a binding gap keeps the parts", NcmClientEngineering.get() ~= nil)
NcmClientDeepActive = false
run()
check("on the ground the gap still unbinds", NcmClientEngineering.get() == nil)
realPrint(("engineering client: %d passed, 0 failed"):format(passed))
