-- ncm_slipstream / server -- the Eddywright SL-1's world (L356).
--
--   * WHICH Machine carries a unit, and whether it is switched on (slipstream_unit; the fit itself is an ordinary
--     machine_configuration item in the electronics bay, made by the Engineering bench like any add-on);
--   * the boot ceremony, once per installation (a unit moved to another Machine boots again there);
--   * the NETWORK: a unit holding a wake tells the wake's owner -- only if the owner carries an enabled unit
--     (aero.slipstream.notices). Human and NPC alike: ncm_paddock registers its equipped NPC cars and reports their
--     links here, so human->NPC, NPC->human and NPC->NPC go through the same rules as human->human;
--   * TRACE: every client's wake/tow numbers once a second while a wake is in play, logged as `SLIPTRACE` lines --
--     the live A/B instrument (MASTER_TEST §SS).
--
-- The physics never runs here for humans (the client applies its own tow at frame rate); for NPCs it runs in
-- ncm_paddock, beside the AI speed it changes.
local Slip = NcmCore.get("aero.slipstream")

local function log(fmt, ...) print(("[ncm_slipstream] " .. fmt):format(...)) end
local function now() return math.floor(Open77.time.unix()) end
local function serverId()
    local ok, id = pcall(function() return GlobalState.ncmIdentity end)
    return (ok and type(id) == "table" and id.serverId) or "ncm-dev"
end
-- KB-358: CHAR(36) columns come back as GUID values: compare ids as lowercase text
local function idOf(v) return v ~= nil and tostring(v):lower() or nil end
local function sameId(a, b) return a ~= nil and b ~= nil and idOf(a) == idOf(b) end

-- ------------------------------------------------------------------------------------------------ who is who
local driverOf = {}            -- pid -> { ncmDriverId, display }
local function driver(pid)
    pid = tonumber(pid) or 0
    if pid <= 0 then return nil end
    if driverOf[pid] then return driverOf[pid] end
    local ok, userId = pcall(GetPlayerIdentifier, pid)
    if not ok or type(userId) ~= "string" or userId == "" or not MySQL.isReady() then return nil end
    local row = MySQL.single.await([[SELECT b.ncm_driver_id, p.display FROM ncm_driver_binding b
        LEFT JOIN driver_profile p ON p.ncm_driver_id = b.ncm_driver_id AND p.server_id = b.server_id
        WHERE b.server_id = ? AND b.user_id = ?]], { serverId(), userId })
    if not row or not row.ncm_driver_id then return nil end
    driverOf[pid] = { ncmDriverId = row.ncm_driver_id, display = row.display or GetPlayerName(pid) }
    return driverOf[pid]
end
AddEventHandler("playerDropped", function() local pid = tonumber(source); if pid then driverOf[pid] = nil end end)

-- ------------------------------------------------------------------------------------------------ units
local units = {}               -- pid -> { assetId, vehicleId, componentId, enabled, booted, perf, name }
local npcs = {}                -- vehicle id (string) -> { name, personId, equipped }

--- The unit installed in this Machine's electronics bay right now, with its switch and boot state.
local function unitOf(machineId)
    local row = MySQL.single.await([[SELECT i.component_asset_id, a.design_id FROM machine_configuration_current x
        JOIN machine_configuration_item i ON i.configuration_id = x.configuration_id
        JOIN component_asset a ON a.asset_id = i.component_asset_id
        JOIN component_design d ON d.design_id = a.design_id
        WHERE x.machine_asset_id = ? AND d.family = 'slipstream' LIMIT 1]], { machineId })
    if not row then return nil end
    local componentId = idOf(row.component_asset_id)
    MySQL.insert.await([[INSERT IGNORE INTO slipstream_unit (server_id, component_asset_id, machine_asset_id, enabled, updated_at)
        VALUES (?, ?, ?, 1, ?)]], { serverId(), componentId, idOf(machineId), now() })
    local st = MySQL.single.await("SELECT enabled, booted_at FROM slipstream_unit WHERE component_asset_id = ? AND machine_asset_id = ?",
        { componentId, idOf(machineId) }) or {}
    local design = NcmCore.get("engineering.installation").design(row.design_id)
    return { componentId = componentId, designId = row.design_id, enabled = tonumber(st.enabled) ~= 0,
        booted = st.booted_at ~= nil, perf = design and design.perf or nil }
end

local function ownsMachine(d, machineId)
    local owner = MySQL.scalar.await("SELECT ncm_driver_id FROM vehicle_asset WHERE asset_id = ? AND server_id = ?", { machineId, serverId() })
    return owner ~= nil and sameId(owner, d.ncmDriverId)
end

-- ncm_paddock needs every bound human Machine as a wake source (NPC -> human), unit or not: the air is the air.
local function broadcastHumans()
    local list = {}
    for _, u in pairs(units) do if u.vehicleId ~= "" then list[#list + 1] = u.vehicleId end end
    TriggerEvent("ncm:slip.humans", list)
end

local function sendUnit(pid)
    local u = units[pid]
    TriggerClientEvent("ncm:slip.unit", pid, u and {
        assetId = u.assetId, vehicleId = u.vehicleId, present = u.componentId ~= nil, enabled = u.enabled,
        boot = u.componentId ~= nil and u.enabled and not u.booted, componentId = u.componentId,
        reliefMax = u.perf and u.perf.reliefMax, lockPerS = u.perf and u.perf.lockPerS, acquireQ = u.perf and u.perf.acquireQ,
    } or { present = false })
end

-- The client names the Machine it is bound to (ncmHandling) whenever that changes, and again now and then.
RegisterNetEvent("ncm:slip.machine", function(m)
    local pid = tonumber(source)
    local d = driver(pid)
    if not d or type(m) ~= "table" or type(m.assetId) ~= "string" then units[pid] = nil; sendUnit(pid); return end
    if not ownsMachine(d, m.assetId) then units[pid] = nil; sendUnit(pid); return end
    local u = unitOf(m.assetId)
    units[pid] = { assetId = m.assetId, vehicleId = tostring(m.vehicleId or ""), name = d.display,
        componentId = u and u.componentId, enabled = u and u.enabled or false, booted = u and u.booted or false, perf = u and u.perf }
    sendUnit(pid)
    broadcastHumans()
    if u then log("unit %s on Machine ..%s (player %d, vehicle %s): %s%s", u.componentId:sub(-6), m.assetId:sub(-6), pid,
        tostring(m.vehicleId), u.enabled and "ON" or "OFF", u.booted and "" or ", boot owed") end
end)

RegisterNetEvent("ncm:slip.booted", function(m)
    local pid = tonumber(source)
    local u = units[pid]
    if not u or not u.componentId or type(m) ~= "table" or not sameId(m.componentId, u.componentId) then return end
    MySQL.update.await("UPDATE slipstream_unit SET booted_at = ?, updated_at = ? WHERE component_asset_id = ? AND machine_asset_id = ? AND booted_at IS NULL",
        { now(), now(), u.componentId, idOf(u.assetId) })
    u.booted = true
    log("unit ..%s booted on Machine ..%s (player %d)", u.componentId:sub(-6), u.assetId:sub(-6), pid)
end)

-- The Engineering panel's switch (F9 -> PARTS -> the unit). Off: no lock, no assist, no HUD, no network.
RegisterNetEvent("ncm:slip.enable", function(componentId, machineId, enabled)
    local pid = tonumber(source)
    local d = driver(pid)
    local function reply(ok, message) TriggerClientEvent("ncm:slip.enable.result", pid, { ok = ok, message = message }) end
    if not d or type(componentId) ~= "string" or type(machineId) ~= "string" then return reply(false, "No such unit.") end
    if not ownsMachine(d, machineId) then return reply(false, "Not your Machine.") end
    local u = unitOf(machineId)
    if not u or not sameId(u.componentId, componentId) then return reply(false, "That unit is not installed on that Machine.") end
    MySQL.update.await("UPDATE slipstream_unit SET enabled = ?, updated_at = ? WHERE component_asset_id = ? AND machine_asset_id = ?",
        { enabled and 1 or 0, now(), u.componentId, idOf(machineId) })
    log("unit ..%s on Machine ..%s switched %s (player %d)", u.componentId:sub(-6), machineId:sub(-6), enabled and "ON" or "OFF", pid)
    local mine = units[pid]
    if mine and sameId(mine.assetId, machineId) then mine.enabled = enabled and true or false; sendUnit(pid) end
    reply(true, enabled and "Slipstream unit on." or "Slipstream unit off.")
end)

-- ------------------------------------------------------------------------------------------------ the network
-- Whoever is behind a wake: { kind = "human"|"npc", pid?, vid, name, equipped }.
local function party(vid)
    vid = tostring(vid or "")
    if vid == "" then return nil end
    for pid, u in pairs(units) do
        if u.vehicleId == vid then return { kind = "human", pid = pid, vid = vid, name = u.name, equipped = u.componentId ~= nil and u.enabled } end
    end
    local n = npcs[vid]
    if n then return { kind = "npc", vid = vid, name = n.name, equipped = n.equipped } end
    return { kind = "unknown", vid = vid, equipped = false }
end

local links = {}               -- follower vid -> leader vid (active links only)

--- One unit's link to a wake, started (on = true) or ended. `follower` and `leader` are party() tables.
local function link(follower, leader, on)
    if not follower or not leader then return end
    local n = Slip.notices(on and follower.equipped, leader.equipped)
    if on then links[follower.vid] = leader.vid else links[follower.vid] = nil end
    -- the leader hears of it only through its own unit
    if leader.kind == "human" and leader.equipped then
        TriggerClientEvent("ncm:slip.inbound", leader.pid, { on = on and n.leader == "inbound", from = follower.name or "another vehicle",
            npc = follower.kind == "npc" or nil })
    end
    -- the follower learns WHO only when the leader's unit answers
    if follower.kind == "human" then
        TriggerClientEvent("ncm:slip.peer", follower.pid, { on = on and n.follower == "peer", name = n.follower == "peer" and leader.name or nil,
            npc = leader.kind == "npc" or nil })
    end
    log("LINK %s %s(%s%s) -> %s(%s%s): follower=%s leader=%s", on and "ON " or "OFF", follower.kind, tostring(follower.name or follower.vid),
        follower.equipped and ",unit" or "", leader.kind, tostring(leader.name or leader.vid), leader.equipped and ",unit" or "",
        tostring(n.follower), tostring(n.leader))
end

local lastLink = {}
RegisterNetEvent("ncm:slip.link", function(m)
    local pid = tonumber(source)
    local u = units[pid]
    if not u or not u.componentId or not u.enabled or type(m) ~= "table" then return end
    local t = GetGameTimer and GetGameTimer() or 0
    if lastLink[pid] and t - lastLink[pid] < 200 then return end     -- a unit changes its mind at most 5 times a second
    lastLink[pid] = t
    local me = party(u.vehicleId)
    local leader = party(m.leader)
    if not leader or leader.vid == me.vid then return end
    link(me, leader, m.on == true)
end)

-- ncm_paddock: an NPC car is on the road (equipped or not), or gone.
AddEventHandler("ncm:slip.npc", function(vid, info)
    vid = tostring(vid or "")
    if vid == "" then return end
    if type(info) ~= "table" then npcs[vid] = nil; links[vid] = nil; return end
    npcs[vid] = { name = tostring(info.name or "a driver"), personId = info.personId, equipped = info.equipped == true }
end)
-- ncm_paddock: an NPC unit took (or let go of) a wake.
AddEventHandler("ncm:slip.npclink", function(vid, leaderVid, on)
    local follower, leader = party(vid), party(leaderVid)
    if follower and follower.kind == "npc" and follower.equipped then link(follower, leader, on == true) end
end)

-- ------------------------------------------------------------------------------------------------ trace
RegisterNetEvent("ncm:slip.trace", function(m)
    local pid = tonumber(source)
    if type(m) ~= "table" then return end
    local num = function(k, f) return (f or "%.2f"):format(tonumber(m[k]) or 0) end
    log("SLIPTRACE pid=%d unit=%s phase=%s q=%s lock=%s ahead=%s lat=%s v=%s relief=%s natural=%s active=%s towN=%s leader=%s",
        pid, tostring(m.unit), tostring(m.phase), num("q", "%.3f"), num("lock"), num("ahead", "%.1f"), num("lat", "%.2f"),
        num("v", "%.1f"), num("relief", "%.3f"), num("natural", "%.3f"), num("active", "%.3f"), num("towN", "%.0f"), tostring(m.leader))
end)

AddEventHandler("playerDropped", function()
    local pid = tonumber(source)
    local u = pid and units[pid]
    if u and links[u.vehicleId] then link(party(u.vehicleId), party(links[u.vehicleId]), false) end
    if pid then units[pid] = nil; lastLink[pid] = nil end
    broadcastHumans()
end)

log("ready: %s %s by %s -- %s", Slip.PRODUCT.name, Slip.PRODUCT.code, Slip.MAKER.name, Slip.SLOGAN)
