-- One host boundary for NCM's player communication: priority, repeat policy, cooldown and durable exposure.
NcmComms = {}

local Policy = NcmCore.get("player.communication")
local memory = {} -- honest fallback while the database is unavailable; scoped to this process only
local function now() return math.floor(Open77.time.unix()) end
local function sid() return NcmCalendar.serverId() end
local function log(fmt, ...) print(("[ncm_league/comms] " .. fmt):format(...)) end

local TYPE = { ambient="info", informative="info", actionable="warning", time_sensitive="warning", critical="error" }

local function identity(pid)
    local d = NcmCalendar.resolveDriver(tonumber(pid) or 0)
    return d and d.ncmDriverId or nil
end

local function load(driverId, key)
    if MySQL.isReady() then
        local ok, row = pcall(MySQL.single.await, [[SELECT shown_count,last_shown_at,acknowledged_at
            FROM player_message_exposure WHERE ncm_driver_id=? AND server_id=? AND message_key=?]],
            {driverId, sid(), key})
        if ok and row then return {shownCount=tonumber(row.shown_count) or 0,lastShownAt=tonumber(row.last_shown_at),acknowledgedAt=tonumber(row.acknowledged_at)} end
        if not ok then log("exposure read failed driver=%s key=%s: %s",driverId:sub(1,8),key,tostring(row)) end
    end
    return memory[driverId.."|"..key] or {}
end

local function save(driverId, key, exposure)
    memory[driverId.."|"..key] = exposure
    if not MySQL.isReady() then return end
    local ok, err = pcall(MySQL.insert.await, [[INSERT INTO player_message_exposure
        (ncm_driver_id,server_id,message_key,shown_count,last_shown_at,acknowledged_at)
        VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE shown_count=VALUES(shown_count),
        last_shown_at=VALUES(last_shown_at),acknowledged_at=VALUES(acknowledged_at)]],
        {driverId,sid(),key,exposure.shownCount or 0,exposure.lastShownAt,exposure.acknowledgedAt})
    if not ok then log("exposure write failed driver=%s key=%s: %s",driverId:sub(1,8),key,tostring(err)) end
end

--- Send one authored message. Returns true when delivered, false + policy reason when suppressed.
function NcmComms.send(pid, def)
    pid = tonumber(pid) or 0
    local normalized, why = Policy.normalize(def)
    if not normalized then log("message refused: %s",tostring(why)); return nil, why end
    local driverId = identity(pid)
    local exposure = driverId and load(driverId, normalized.id) or {}
    local decision, decisionWhy = Policy.decide(normalized, exposure, now())
    if not decision then return nil, decisionWhy end
    if not decision.deliver then return false, decision.reason end
    local p = decision.presentation
    if p.surface == "chat" or p.surface == "both" then
        pcall(Open77.chat.send, pid, "[NCM] " .. p.title .. " — " .. p.message)
    end
    if p.surface ~= "chat" then
        pcall(Open77.notifications.send, pid, {type=TYPE[p.priority] or "info",title=p.title,
            message=p.message,icon="NCM",durationMs=p.durationMs})
    end
    if driverId then save(driverId, normalized.id, Policy.record(exposure, now())) end
    return true, p
end

function NcmComms.acknowledge(pid, key)
    local driverId = identity(pid)
    if not driverId or type(key) ~= "string" or key == "" then return nil, "invalid" end
    local exposure = Policy.acknowledge(load(driverId, key), now())
    save(driverId, key, exposure)
    return true
end

-- Trusted cross-resource seam for ncm_world. This is deliberately not a client net event.
AddEventHandler("ncm:comms:send", function(pid, def) NcmComms.send(pid, def) end)
AddEventHandler("onPlayerDisconnected", function(pid)
    local prefix = tostring(identity(pid) or "") .. "|"
    if prefix ~= "|" then for key in pairs(memory) do if key:sub(1,#prefix)==prefix then memory[key]=nil end end end
end)

log("player communication ready")
