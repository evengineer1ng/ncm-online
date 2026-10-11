-- ncm_slipstream's server (L356) against deterministic doubles: the unit registry, the boot-once flag, the F9 switch
-- and above all the NETWORK -- who is told what when one car holds another's wake. The rules are proved in
-- ncm/core/tests/test_aero_slipstream.lua; what is only provable here is that the relay applies them to every pairing
-- the brief names (MASTER_TEST §SS D1-D5): human->human, human->NPC, NPC->human, NPC->NPC, unequipped and switched off.
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

local events, replies = {}, {}
function AddEventHandler(name, fn) events[name] = events[name] or {}; table.insert(events[name], fn) end
function RegisterNetEvent(name, fn) AddEventHandler(name, fn) end
function RegisterCommand() end
function TriggerEvent(name, ...) for _, fn in ipairs(events[name] or {}) do fn(...) end end
function TriggerClientEvent(name, pid, body) replies[#replies + 1] = { name = name, pid = pid, body = body } end
function print(s) logs[#logs + 1] = tostring(s) end
local gameMs = 0
function GetGameTimer() return gameMs end
function GetPlayerIdentifier(pid) return "user:" .. tostring(pid) end
function GetPlayerName(pid) return "player" .. tostring(pid) end
GlobalState = { ncmIdentity = { serverId = "test", environment = "development" } }
Open77 = { time = { unix = function() return 1790000000 end } }

local function fire(name, pid, ...)
    source = pid
    local args = { ... }
    for _, fn in ipairs(events[name] or {}) do fn((table.unpack or unpack)(args)) end
end
local function sent(name, pid)
    local out = {}
    for _, r in ipairs(replies) do if r.name == name and (pid == nil or r.pid == pid) then out[#out + 1] = r.body end end
    return out
end
local function last(name, pid) local l = sent(name, pid); return l[#l] end

-- ---------------------------------------------------------------- doubles
-- three drivers; Ana and Ben run SL-1s, Cy has none
local drivers = { ["user:1"] = { id = "D-ANA", name = "Ana" }, ["user:2"] = { id = "D-BEN", name = "Ben" }, ["user:3"] = { id = "D-CY", name = "Cy" } }
local machines = { ["M-ANA"] = "D-ANA", ["M-BEN"] = "D-BEN", ["M-CY"] = "D-CY" }
local installed = { ["M-ANA"] = "C-ANA", ["M-BEN"] = "C-BEN" }     -- machine -> slipstream component
local unitRows = {}                                                   -- "comp:machine" -> { enabled, booted_at }

MySQL = {
    isReady = function() return true end,
    single = { await = function(sql, p)
        if sql:find("ncm_driver_binding") then local d = drivers[p[2]]; return d and { ncm_driver_id = d.id, display = d.name } or nil end
        if sql:find("family = 'slipstream'") then local c = installed[p[1]]; return c and { component_asset_id = c, design_id = "eng:eddywright:sl1:r1" } or nil end
        if sql:find("SELECT enabled, booted_at") then return unitRows[p[1]:lower() .. ":" .. p[2]:lower()] end
        error("unexpected single: " .. sql)
    end },
    scalar = { await = function(sql, p)
        if sql:find("FROM vehicle_asset") then return machines[p[1]] end
        error("unexpected scalar: " .. sql)
    end },
    insert = { await = function(sql, p)
        if sql:find("INSERT IGNORE INTO slipstream_unit") then
            local k = p[2]:lower() .. ":" .. p[3]:lower()
            unitRows[k] = unitRows[k] or { enabled = 1, booted_at = nil }
            return 1
        end
        error("unexpected insert: " .. sql)
    end },
    update = { await = function(sql, p)
        if sql:find("SET enabled") then unitRows[p[3]:lower() .. ":" .. p[4]:lower()].enabled = p[1]; return 1 end
        if sql:find("SET booted_at") then unitRows[p[3]:lower() .. ":" .. p[4]:lower()].booted_at = p[1]; return 1 end
        error("unexpected update: " .. sql)
    end },
}

-- ---------------------------------------------------------------- load core + the resource
local core = root .. "/ncm/core"
NcmCore = dofile(core .. "/init.lua")
local manifest = dofile(core .. "/MANIFEST.lua")
for _, f in ipairs(manifest) do dofile(core .. "/" .. f) end
dofile(root .. "/ncm/online/resources/ncm_slipstream/server/main.lua")

-- every bound Machine says hello
fire("ncm:slip.machine", 1, { assetId = "M-ANA", vehicleId = 101 })
fire("ncm:slip.machine", 2, { assetId = "M-BEN", vehicleId = 102 })
fire("ncm:slip.machine", 3, { assetId = "M-CY", vehicleId = 103 })
-- ncm_paddock registers two NPC cars: Kenji's team runs an SL-1, Omar's does not
TriggerEvent("ncm:slip.npc", 201, { name = "Kenji Mori", personId = "p1", equipped = true })
TriggerEvent("ncm:slip.npc", 202, { name = "Omar Haddad", personId = "p2", equipped = false })

-- ---------------------------------------------------------------- the unit
local a = last("ncm:slip.unit", 1)
check("an installed unit is reported present and on", a and a.present and a.enabled)
check("a fresh installation owes its boot ceremony", a.boot == true)
check("a Machine without a unit has none", last("ncm:slip.unit", 3).present == false)
check("someone else's Machine is not yours", (function()
    fire("ncm:slip.machine", 3, { assetId = "M-ANA", vehicleId = 101 }); local r = last("ncm:slip.unit", 3)
    fire("ncm:slip.machine", 3, { assetId = "M-CY", vehicleId = 103 }); return r.present == false end)())
fire("ncm:slip.booted", 1, { componentId = "C-ANA" })
fire("ncm:slip.machine", 1, { assetId = "M-ANA", vehicleId = 101 })
check("the boot plays once per installation", last("ncm:slip.unit", 1).boot == false)

-- ---------------------------------------------------------------- the network
local function linkFrom(pid, leader, on) replies = {}; gameMs = gameMs + 1000; fire("ncm:slip.link", pid, { leader = leader, on = on }) end
local function npcLink(vid, leader, on) replies = {}; TriggerEvent("ncm:slip.npclink", vid, leader, on) end

-- D1: equipped follower -> unequipped leader
linkFrom(1, 103, true)
check("D1 the follower keeps its own link, nameless", #sent("ncm:slip.peer", 1) == 1 and last("ncm:slip.peer", 1).on == false)
check("D1 a leader without a unit hears nothing", #sent("ncm:slip.inbound", 3) == 0)
-- D2: equipped follower -> equipped leader
linkFrom(1, 102, true)
check("D2 the follower learns who", last("ncm:slip.peer", 1).on and last("ncm:slip.peer", 1).name == "Ben")
check("D2 the leader is told who is in its wake", last("ncm:slip.inbound", 2).on and last("ncm:slip.inbound", 2).from == "Ana")
linkFrom(1, 102, false)
check("D2 letting go is told too", last("ncm:slip.inbound", 2).on == false)
-- D3: NPC (equipped) -> human (equipped)
npcLink(201, 101, true)
check("D3 an NPC's unit is named to the human it tows behind", last("ncm:slip.inbound", 1).on and last("ncm:slip.inbound", 1).from == "Kenji Mori"
    and last("ncm:slip.inbound", 1).npc == true)
npcLink(201, 103, true)
check("D3 ...but not to a human without a unit", #sent("ncm:slip.inbound", 3) == 0)
-- D4: human (equipped) -> NPC (equipped / not)
linkFrom(2, 201, true)
check("D4 a human's unit names the equipped NPC ahead", last("ncm:slip.peer", 2).on and last("ncm:slip.peer", 2).name == "Kenji Mori")
linkFrom(2, 202, true)
check("D4 an unequipped NPC stays nameless", last("ncm:slip.peer", 2).on == false)
-- D5: NPC -> NPC: nobody human to tell; the link is logged
logs = {}
npcLink(201, 202, true)
check("D5 NPC to NPC tells no client", #replies == 0)
local logged = false
for _, l in ipairs(logs) do if l:find("LINK ON  npc%(Kenji Mori,unit%) %-> npc%(Omar Haddad%)") then logged = true end end
check("D5 NPC to NPC is in the log", logged)
npcLink(202, 201, true)
check("an NPC without a unit links to nobody", #replies == 0)

-- ---------------------------------------------------------------- the switch (G)
replies = {}
fire("ncm:slip.enable", 3, "C-ANA", "M-ANA", false)
check("only the owner can switch a unit", last("ncm:slip.enable.result", 3).ok == false)
fire("ncm:slip.enable", 1, "C-ANA", "M-ANA", false)
check("the owner switches it off", last("ncm:slip.enable.result", 1).ok and last("ncm:slip.unit", 1).enabled == false)
linkFrom(1, 102, true)
check("G a switched-off unit links to nobody", #replies == 0)
npcLink(201, 101, true)
check("G and nobody can see it", #sent("ncm:slip.inbound", 1) == 0)
fire("ncm:slip.enable", 1, "C-ANA", "M-ANA", true)
check("and back on", last("ncm:slip.unit", 1).enabled == true)

-- ---------------------------------------------------------------- the trace
logs = {}
fire("ncm:slip.trace", 1, { unit = "on", phase = "active", q = 0.71, lock = 1, ahead = 9.2, lat = 0.3, v = 50, relief = 0.31, natural = 0.11, active = 0.2, towN = 350, leader = "102" })
check("a trace is a SLIPTRACE line", logs[1] and logs[1]:find("SLIPTRACE pid=1 unit=on phase=active q=0.710") ~= nil)

realPrint(("slipstream host: %d passed, 0 failed"):format(passed))
