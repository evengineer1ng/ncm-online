-- ncm_league / server / records — the read side of results (M3.3): a driver's recent results and
-- bests, and per-route leaderboards published on GlobalState.ncmRecords. Storage is
-- session_result/session/event (migration 004); this file only reads and formats.
NcmRecords = {}

local function log(fmt, ...)
    print(("[ncm_league/records] " .. fmt):format(...))
end

local function serverId()
    return (NcmCalendar and NcmCalendar.serverId and NcmCalendar.serverId()) or "ncm-dev"
end

local function fmtMs(ms)
    if not ms then return "--" end
    local sec = ms / 1000
    local m = math.floor(sec / 60)
    return string.format("%d:%06.3f", m, sec - m * 60)
end
NcmRecords.fmtMs = fmtMs

local function tell(pid, text)
    pcall(Open77.chat.send, pid, "[NCM] " .. text)
end

-- ---------------------------------------------------------------------------------------------
-- Leaderboards: best finished time per route, top 5, on GlobalState.ncmRecords
-- ---------------------------------------------------------------------------------------------
function NcmRecords.refresh()
    if not MySQL.isReady() then return end
    local rows = MySQL.query.await(
        "SELECT ev.route_id, ev.route_name, sr.ncm_driver_id, COALESCE(p.display, LEFT(sr.ncm_driver_id, 8)) AS display, " ..
        "MIN(sr.total_ms) AS best_ms, COUNT(*) AS finishes " ..
        "FROM session_result sr JOIN session s ON s.session_id = sr.session_id JOIN event ev ON ev.event_id = s.event_id " ..
        "LEFT JOIN driver_profile p ON p.ncm_driver_id = sr.ncm_driver_id AND p.server_id = ev.server_id " ..
        "WHERE ev.server_id = ? AND sr.state = 'finished' GROUP BY ev.route_id, ev.route_name, sr.ncm_driver_id, display " ..
        "ORDER BY ev.route_id, best_ms ASC", { serverId() }) or {}
    local routes, order = {}, {}
    for _, r in ipairs(rows) do
        local rt = routes[r.route_id]
        if not rt then
            rt = { routeId = r.route_id, routeName = r.route_name, best = {} }
            routes[r.route_id] = rt
            order[#order + 1] = r.route_id
        end
        if #rt.best < 5 then
            rt.best[#rt.best + 1] = { driverId = r.ncm_driver_id, display = r.display, bestMs = tonumber(r.best_ms), finishes = tonumber(r.finishes) }
        end
    end
    local list = {}
    for _, rid in ipairs(order) do list[#list + 1] = routes[rid] end
    GlobalState.ncmRecords = { routes = list, updatedAt = math.floor(Open77.time.unix()) }
    log("leaderboards refreshed: %d route(s), %d row(s)", #list, #rows)
end

-- ---------------------------------------------------------------------------------------------
-- /ncm.results — my last five results. /ncm.best — my best per route.
-- ---------------------------------------------------------------------------------------------
RegisterCommand("ncm.results", function(source)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local d = NcmCalendar.resolveDriver(pid)
        if not d then tell(pid, "No NCM driver on this session."); return end
        local rows = MySQL.query.await(
            "SELECT sr.position, sr.state, sr.total_ms, sr.gap_ms, sr.jump_start, ev.route_name, s.entrants, s.completed_at " ..
            "FROM session_result sr JOIN session s ON s.session_id = sr.session_id JOIN event ev ON ev.event_id = s.event_id " ..
            "WHERE sr.ncm_driver_id = ? ORDER BY s.completed_at DESC LIMIT 5", { d.ncmDriverId }) or {}
        if #rows == 0 then tell(pid, "No results yet. Enter a race."); return end
        tell(pid, ("Your last %d result(s):"):format(#rows))
        for _, r in ipairs(rows) do
            local what
            if r.state == "finished" then
                what = fmtMs(tonumber(r.total_ms))
                if r.gap_ms then what = what .. " (+" .. fmtMs(tonumber(r.gap_ms)) .. ")" end
                if (tonumber(r.jump_start) or 0) > 0 then what = what .. " JS" end
            else
                what = string.upper(tostring(r.state))
            end
            tell(pid, ("  P%d of %d · %s · %s"):format(tonumber(r.position) or 0, tonumber(r.entrants) or 0, tostring(r.route_name), what))
        end
    end)
end, false)

RegisterCommand("ncm.best", function(source)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local d = NcmCalendar.resolveDriver(pid)
        if not d then tell(pid, "No NCM driver on this session."); return end
        local rows = MySQL.query.await(
            "SELECT ev.route_id, ev.route_name, MIN(sr.total_ms) AS best_ms, COUNT(*) AS finishes " ..
            "FROM session_result sr JOIN session s ON s.session_id = sr.session_id JOIN event ev ON ev.event_id = s.event_id " ..
            "WHERE sr.ncm_driver_id = ? AND sr.state = 'finished' GROUP BY ev.route_id, ev.route_name ORDER BY ev.route_name", { d.ncmDriverId }) or {}
        if #rows == 0 then tell(pid, "No finishes yet."); return end
        local board = GlobalState.ncmRecords
        tell(pid, "Your bests:")
        for _, r in ipairs(rows) do
            local rank = "--"
            if type(board) == "table" then
                for _, rt in ipairs(board.routes or {}) do
                    if rt.routeId == r.route_id then
                        for i, b in ipairs(rt.best) do if b.driverId == d.ncmDriverId then rank = "#" .. i end end
                    end
                end
            end
            tell(pid, ("  %s · %s · %d finish(es) · route rank %s"):format(tostring(r.route_name), fmtMs(tonumber(r.best_ms)), tonumber(r.finishes) or 0, rank))
        end
    end)
end, false)

RegisterCommand("ncm.records", function()
    local board = GlobalState.ncmRecords
    if type(board) ~= "table" or #(board.routes or {}) == 0 then log("no records yet"); return end
    for _, rt in ipairs(board.routes) do
        local parts = {}
        for i, b in ipairs(rt.best) do parts[#parts + 1] = ("#%d %s %s"):format(i, tostring(b.display), fmtMs(b.bestMs)) end
        log("%s: %s", tostring(rt.routeName), table.concat(parts, " | "))
    end
end, false)
