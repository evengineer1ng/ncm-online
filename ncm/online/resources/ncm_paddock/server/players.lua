-- ncm_paddock / server / players -- player id -> NCM Driver, read from the binding table ncm_world writes.
-- The same query as ncm_league's calendar (resources do not share memory, so it is restated, not called).
PaddockPlayers = {}

local U = PaddockUtil
local driverOf = {}

-- NCM Observer (doc 46, L307): a connection in observer mode is a presence without a person -- no driver, so
-- nothing built on this lookup lets it enter, earn, buy or count. ncm_observer owns the list.
local function observing(id)
    local ok, o = pcall(function() return GlobalState.ncmObservers end)
    return ok and type(o) == "table" and o[tostring(id)] ~= nil
end

function PaddockPlayers.driver(playerId)
    local id = tonumber(playerId) or 0
    if id <= 0 then return nil end
    if observing(id) then return nil end
    if driverOf[id] then return driverOf[id] end
    local ok, userId = pcall(GetPlayerIdentifier, id)
    if not ok or type(userId) ~= "string" or userId == "" or not MySQL.isReady() then return nil end
    local row = MySQL.single.await(
        "SELECT b.ncm_driver_id, p.display FROM ncm_driver_binding b " ..
        "LEFT JOIN driver_profile p ON p.ncm_driver_id = b.ncm_driver_id AND p.server_id = b.server_id " ..
        "WHERE b.server_id = ? AND b.user_id = ?", { U.sid(), userId })
    if not row or not row.ncm_driver_id then return nil end
    driverOf[id] = { ncmDriverId = row.ncm_driver_id, display = row.display or GetPlayerName(id) }
    return driverOf[id]
end

--- Connected players as { pid, driver } for anything that must reach "everyone online".
function PaddockPlayers.online()
    local out = {}
    local ok, list = pcall(GetPlayers)
    if not ok or type(list) ~= "table" then return out end
    for _, pid in ipairs(list) do
        local d = PaddockPlayers.driver(pid)
        if d then out[#out + 1] = { pid = tonumber(pid), driver = d } end
    end
    return out
end

--- The player id currently bound to a driver, or nil when they are offline.
function PaddockPlayers.pidOf(driverId)
    for pid, d in pairs(driverOf) do
        if d.ncmDriverId == driverId then return pid end
    end
    return nil
end

AddEventHandler("onPlayerDisconnected", function(playerId) driverOf[tonumber(playerId) or 0] = nil end)
