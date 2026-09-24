-- ============================================================
-- MT_Ecosystem: modules/records.lua
-- All-time fastest times per node pair per career.
--   • Top 5 times stored per route.
--   • Auto-broken when player beats them.
--   • Shown in ui_racing.lua "Records" tab.
-- ============================================================

local Records = {}
local Persist = require("modules/persistence")

local RECORDS_FILE = "records.json"
local MAX_PER_ROUTE = 5

-- ── State ─────────────────────────────────────────────────────
-- Structure: { [careerKey] = { [routeKey] = { {time, driverName, vehicleId, date}, ... } } }
-- careerKey = career.id
-- routeKey  = nodeA_id .. "|" .. nodeB_id  (canonical: alphabetically ordered)

Records._data = {}

-- ── Helpers ───────────────────────────────────────────────────

local function routeKey(nodeA, nodeB)
    -- Canonical order so A→B and B→A share the same record board
    if nodeA <= nodeB then
        return nodeA .. "|" .. nodeB
    else
        return nodeB .. "|" .. nodeA
    end
end

local function careerKey(career)
    return career and career.id or "global"
end

local function ensurePath(careerId, rKey)
    Records._data[careerId] = Records._data[careerId] or {}
    Records._data[careerId][rKey] = Records._data[careerId][rKey] or {}
end

-- ── Init / Persistence ────────────────────────────────────────

function Records.init()
    local data = Persist.load(RECORDS_FILE)
    if type(data) == "table" then
        Records._data = data
    end
    print("[NCM/Records] Loaded fastest-time boards.")
end

function Records.save()
    Persist.save(RECORDS_FILE, Records._data)
end

-- ── Public API ────────────────────────────────────────────────

--- Submit a time for a route. Returns: isRecord (bool), position (1-5 or 0)
--- @param career     table
--- @param nodeA_id   string
--- @param nodeB_id   string
--- @param timeSeconds number
--- @param driverName string  (player display name or driver id)
--- @param vehicleId  string  (optional)
function Records.submit(career, nodeA_id, nodeB_id, timeSeconds, driverName, vehicleId)
    local ck = careerKey(career)
    local rk = routeKey(nodeA_id, nodeB_id)
    ensurePath(ck, rk)

    local board = Records._data[ck][rk]
    local entry = {
        time        = timeSeconds,
        driverName  = driverName or "Player",
        vehicleId   = vehicleId  or "unknown",
        date        = os.date("%Y-%m-%d"),
        timestamp   = os.time(),
    }

    table.insert(board, entry)
    table.sort(board, function(a, b) return a.time < b.time end)

    -- Trim to max entries
    while #board > MAX_PER_ROUTE do table.remove(board, #board) end

    -- Find position of the submitted entry (by timestamp, since times could tie)
    local pos = 0
    for i, e in ipairs(board) do
        if e.timestamp == entry.timestamp and e.driverName == entry.driverName then
            pos = i
            break
        end
    end

    local isRecord = pos == 1
    if isRecord then
        print(string.format("[NCM/Records] NEW RECORD on %s: %.2fs by %s",
            rk, timeSeconds, driverName))
        MTE.Events.emit("NewRecord", {
            careerId    = ck,
            routeKey    = rk,
            time        = timeSeconds,
            driverName  = driverName,
        })
    end

    Records.save()
    return isRecord, pos
end

--- Get the leaderboard for a route.
--- @param career    table
--- @param nodeA_id  string
--- @param nodeB_id  string
--- @return table   sorted list of { time, driverName, vehicleId, date }
function Records.getBoard(career, nodeA_id, nodeB_id)
    local ck = careerKey(career)
    local rk = routeKey(nodeA_id, nodeB_id)
    return ((Records._data[ck] or {})[rk]) or {}
end

--- Get the fastest time on a route, or nil.
function Records.getFastest(career, nodeA_id, nodeB_id)
    local board = Records.getBoard(career, nodeA_id, nodeB_id)
    return board[1] and board[1].time or nil
end

--- Returns a summary list of all routes with records for a career.
--- Each entry: { nodeA, nodeB, routeKey, boardSize, fastest }
function Records.allRoutes(career)
    local ck = careerKey(career)
    local out = {}
    for rk, board in pairs(Records._data[ck] or {}) do
        if #board > 0 then
            local parts = {}
            for p in rk:gmatch("[^|]+") do table.insert(parts, p) end
            table.insert(out, {
                nodeA    = parts[1] or "?",
                nodeB    = parts[2] or "?",
                routeKey = rk,
                boardSize = #board,
                fastest  = board[1].time,
            })
        end
    end
    table.sort(out, function(a, b) return a.fastest < b.fastest end)
    return out
end

--- Clear all records for a career's route (e.g., reset option).
function Records.clearRoute(career, nodeA_id, nodeB_id)
    local ck = careerKey(career)
    local rk = routeKey(nodeA_id, nodeB_id)
    if Records._data[ck] then
        Records._data[ck][rk] = nil
        Records.save()
    end
end

--- Clear all records for a career.
function Records.clearCareer(career)
    local ck = careerKey(career)
    Records._data[ck] = nil
    Records.save()
end

return Records
