-- ncm_league / server / scenario — the TW1 host kit (Batch 2; L59, L63).
--
-- What the host needs to put 3–5 real people into the system and beat on it for an hour without a server restart:
--   ncm.scenario <discipline> <route> [format] [in <min>] [laps <n>] [class <id>]   post + enter everyone connected
--   ncm.scenario restart | stop | field | status                                     repeat, end, who is where
--   ncm.warp <pid> start|finish|grid|<pid>|<x,y,z>       ncm.lights now       ncm.spectate <pid>     ncm.kick <pid>
--   ncm.incident <pid> <band> [car|object]               ncm.rules incidents on|off [bands a,b,c]
--   ncm.trace <pid> on|off                               ncm.state            ncm.world reset
-- Authored routes (any discipline, in-world, by the host):  /ncm.ar start <key> [name] · gate [name] · finish · loop ·
--   list · del <key> · tp <key>        (persisted in custom_route, registered into ncm-core's roots at start)
-- Every line is logged with the scenario id (S<n>) so a run sheet lines up with the server log.
NcmScenario = {}

local Core = NcmCore
local Routes = Core.get("course.routes")
local Roots = Core.get("data.roots")
local Nodes = Core.get("data.nodes")
local Discipline = Core.get("competition.discipline")
local Format = Core.get("competition.format")
local Entry = Core.get("competition.entry")
local Json = Core.get("vocabulary.json")
local ids = Core.get("vocabulary.ids")

local function log(fmt, ...) print(("[ncm_league/scenario] " .. fmt):format(...)) end
local now = function() return Open77.time.unix() end
local hostRng = function() return math.random() end
local function tell(pid, text) if pid then pcall(Open77.chat.send, pid, "[NCM] " .. text) end end
local function toast(pid, def) if pid then pcall(Open77.notifications.send, pid, def) end end
local function serverId() return NcmCalendar.serverId() end
local function setting(key, default)
    local s = NcmCalendar and NcmCalendar.settings
    local ok, v = pcall(function() return s and s[key] end)
    return (ok and v) or default
end

local current = nil       -- { id, n, spec, eventId, field = { [pid] = driverId }, postedAt }
local counter = 0
NcmScenario.overrides = { incidents = true, bands = nil }   -- per-scenario rule overrides (ncm.rules)
NcmScenario.traced = {}                                     -- driverId -> true (ncm.trace)

local function sid() return current and current.id or "S0" end
local function slog(fmt, ...) log("%s " .. fmt, sid(), ...) end

-- ---------------------------------------------------------------------------------------------
-- Authored routes: custom_route rows -> ncm-core roots
-- ---------------------------------------------------------------------------------------------
local drafts = {}   -- pid -> { key, name, start = node, gates = {}, }

local function customRootId(key) return "custom_" .. key end

local function registerCustom(row)
    local pts = Json.decode(row.points_json or "[]") or {}
    if #pts < 2 then return nil, "too_few_points" end
    local first, last = pts[1], pts[#pts]
    local sId, eId = customRootId(row.route_key) .. "_s", customRootId(row.route_key) .. "_e"
    Nodes.register({ id = sId, x = first.x, y = first.y, z = first.z or 0, heading = first.heading or 0, name = first.name or (row.name .. " start"), road = true, custom = true })
    Nodes.register({ id = eId, x = last.x, y = last.y, z = last.z or 0, heading = last.heading or 0, name = last.name or (row.name .. " finish"), road = true, custom = true })
    local mid = {}
    for i = 2, #pts - 1 do mid[#mid + 1] = { x = pts[i].x, y = pts[i].y, z = pts[i].z or 0, heading = pts[i].heading, name = pts[i].name or ("gate " .. (i - 1)) } end
    local root = { rootId = customRootId(row.route_key), startNodeId = sId, endNodeId = eId, displayName = row.name or row.route_key,
                   intermediate = mid, disciplineId = row.discipline_id, laps = tonumber(row.laps) or 1, custom = true, loop = (tonumber(row.is_loop) or 0) == 1 or row.is_loop == true }
    Roots.register(root)
    return root
end

function NcmScenario.loadRoutes()
    local ok, rows = pcall(function() return MySQL.query.await("SELECT route_key, name, discipline_id, points_json, laps, is_loop FROM custom_route WHERE server_id = ?", { serverId() }) or {} end)
    if not ok then log("custom routes unavailable: %s", tostring(rows)); return 0 end
    local n = 0
    for _, r in ipairs(rows) do if registerCustom(r) then n = n + 1 end end
    log("authored routes registered: %d", n)
    return n
end

local function here(pid)
    local p = Open77.players.get(pid)
    if not p or not p.position then return nil end
    return { x = p.position.x, y = p.position.y, z = p.position.z, heading = tonumber(p.heading or p.yaw or 0) or 0 }
end

local function saveRoute(pid, d, loop)
    local pts = { { x = d.start.x, y = d.start.y, z = d.start.z, heading = d.start.heading, name = d.name .. " start" } }
    for _, g in ipairs(d.gates) do pts[#pts + 1] = g end
    local fin = loop and { x = d.start.x, y = d.start.y, z = d.start.z, heading = d.start.heading, name = d.name .. " line" } or here(pid)
    if not fin then tell(pid, "No position."); return end
    fin.name = fin.name or (d.name .. " finish")
    pts[#pts + 1] = fin
    local row = { route_key = d.key, name = d.name, discipline_id = d.disciplineId, points_json = Json.encode(pts), laps = d.laps or 1, is_loop = loop and 1 or 0 }
    pcall(function()
        MySQL.insert.await(
            "INSERT INTO custom_route (server_id, route_key, name, discipline_id, points_json, laps, is_loop, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) " ..
            "ON DUPLICATE KEY UPDATE name = VALUES(name), discipline_id = VALUES(discipline_id), points_json = VALUES(points_json), laps = VALUES(laps), is_loop = VALUES(is_loop)",
            { serverId(), d.key, d.name, d.disciplineId or "", row.points_json, row.laps, row.is_loop, math.floor(now()) })
    end)
    local root = registerCustom(row)
    drafts[pid] = nil
    local route = Routes.resolve(root.rootId)
    tell(pid, ("Route saved: %s (%s) · %d gate(s) · %d m%s. Run it: ncm.scenario <discipline> %s"):format(d.name, d.key, #d.gates, math.floor(route.distanceM), loop and " · loop" or "", d.key))
    log("ROUTE saved key=%s name=%s points=%d loop=%s length=%dm", d.key, d.name, #pts, tostring(loop), math.floor(route.distanceM))
end

local function routeCommand(pid, args)
    local sub = tostring(args[1] or ""):lower()
    if sub == "start" then
        local key = tostring(args[2] or ""):lower():gsub("[^%w_]", "")
        if key == "" then tell(pid, "Usage: /ncm.ar start <key> [name…]"); return end
        local p = here(pid); if not p then tell(pid, "No position."); return end
        local name = #args > 2 and table.concat(args, " ", 3) or key
        drafts[pid] = { key = key, name = name, start = p, gates = {} }
        tell(pid, ("Recording route '%s' from here (facing %.0f°). Drive it: /ncm.ar gate at each checkpoint, then /ncm.ar finish (or /ncm.ar loop for a ring)."):format(name, p.heading))
    elseif sub == "gate" then
        local d = drafts[pid]; if not d then tell(pid, "Start a route first: /ncm.ar start <key>"); return end
        local p = here(pid); if not p then tell(pid, "No position."); return end
        p.name = #args > 1 and table.concat(args, " ", 2) or ("gate " .. (#d.gates + 1))
        d.gates[#d.gates + 1] = p
        tell(pid, ("Gate %d '%s' at %.0f,%.0f."):format(#d.gates, p.name, p.x, p.y))
    elseif sub == "finish" or sub == "loop" then
        local d = drafts[pid]; if not d then tell(pid, "Start a route first: /ncm.ar start <key>"); return end
        saveRoute(pid, d, sub == "loop")
    elseif sub == "list" then
        local n = 0
        for _, r in ipairs(Roots.LIST) do
            if r.custom then
                n = n + 1
                local route = Routes.resolve(r.rootId)
                tell(pid, ("  %s · %s · %d gate(s) · %d m%s"):format(r.rootId:gsub("^custom_", ""), r.displayName, #(r.intermediate or {}), math.floor(route and route.distanceM or 0), r.loop and " · loop" or ""))
            end
        end
        if n == 0 then tell(pid, "No authored routes yet. /ncm.ar start <key> [name] to record one.") end
    elseif sub == "del" then
        local key = tostring(args[2] or ""):lower()
        if not Roots.unregister(customRootId(key)) then tell(pid, "No such route."); return end
        pcall(function() MySQL.update.await("DELETE FROM custom_route WHERE server_id = ? AND route_key = ?", { serverId(), key }) end)
        tell(pid, "Deleted route " .. key .. ".")
    elseif sub == "tp" then
        local key = tostring(args[2] or ""):lower()
        local route = Routes.resolve(customRootId(key))
        if not route then tell(pid, "No such route."); return end
        TriggerEvent("ncm:warp", pid, { x = route.start.x, y = route.start.y, z = route.start.z, heading = route.start.heading, why = "route start" })
    else
        tell(pid, "/ncm.ar start <key> [name] · gate [name] · finish · loop · list · del <key> · tp <key>")
    end
end

RegisterCommand("ncm.ar", function(source, args)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    routeCommand(pid, args or {})
end, false)

-- ---------------------------------------------------------------------------------------------
-- Scenario: post + enter everyone connected
-- ---------------------------------------------------------------------------------------------
local function routeByLabel(label)
    local want = tostring(label or ""):lower():gsub("[^%w]", "")
    for _, r in ipairs(Roots.LIST) do
        local key = tostring(r.displayName or ""):lower():gsub("[^%w]", "")
        if key == want or r.rootId:lower():gsub("[^%w]", "") == want or r.rootId:lower():gsub("^custom_", "") == want then return r end
    end
    for _, r in ipairs(Roots.LIST) do
        local key = tostring(r.displayName or ""):lower():gsub("[^%w]", "")
        if key:find(want, 1, true) or r.rootId:lower():find(want, 1, true) then return r end
    end
    return nil
end

local function parseSpec(args)
    local spec = { disciplineId = tostring(args[1] or "street_sprint"):lower(), route = args[2], formatId = "sprint", minutes = 3, laps = nil, classId = nil }
    if spec.disciplineId == "ncx" or spec.disciplineId == "formula" then spec.disciplineId = "ncx_formula" end
    if spec.disciplineId == "gt" or spec.disciplineId == "road" or spec.disciplineId == "street" then spec.disciplineId = "street_sprint" end
    if spec.disciplineId == "badlands" then spec.disciplineId = "quad" end
    if spec.disciplineId == "rally" then spec.disciplineId = "rally_stage" end
    local i = 3
    while i <= #args do
        local a = tostring(args[i]):lower()
        if a == "in" then spec.minutes = tonumber(args[i + 1]) or spec.minutes; i = i + 2
        elseif a == "laps" then spec.laps = tonumber(args[i + 1]); i = i + 2
        elseif a == "class" then spec.classId = args[i + 1]; i = i + 2
        elseif a == "rolling" then spec.startType = "rolling"; i = i + 1
        elseif a == "standing" then spec.startType = "standing"; i = i + 1
        elseif a == "formation" then spec.formationM = tonumber(args[i + 1]); i = i + 2
        elseif a == "pace" then spec.paceKph = tonumber(args[i + 1]); i = i + 2
        elseif Format.byId(a) then spec.formatId = Format.byId(a).id; i = i + 1
        else i = i + 1 end
    end
    return spec
end

local function enterEveryone(e, t)
    local n = 0
    for _, pid in ipairs(Open77.players.all()) do
        local driver = NcmCalendar.resolveDriver(pid)
        if driver and not e.entries[driver.ncmDriverId] then
            local en = { entryId = ids.uuid4(hostRng), eventId = e.eventId, driverId = driver.ncmDriverId, state = "checked_in", checkedInAt = t, fee = 0 }
            pcall(function()
                MySQL.insert.await("INSERT INTO entry (entry_id, event_id, ncm_driver_id, state, fee, checked_in_at) VALUES (?, ?, ?, 'checked_in', 0, ?)",
                    { en.entryId, e.eventId, driver.ncmDriverId, math.floor(t) })
            end)
            e.entries[driver.ncmDriverId] = en
            current.field[pid] = driver.ncmDriverId
            pcall(function() Open77.state.player(pid):set("ncmEntry", { eventId = e.eventId, state = "checked_in", routeName = e.routeName, startsAt = math.floor(e.startsAt) }) end)
            n = n + 1
        end
    end
    return n
end

function NcmScenario.post(spec, t)
    t = t or now()
    local d = Discipline.byId(spec.disciplineId)
    if not d then return nil, "unknown_discipline" end
    local root = routeByLabel(spec.route)
    if not root then return nil, "unknown_route" end
    counter = counter + 1
    current = { id = "S" .. counter, n = counter, spec = spec, field = {}, postedAt = t }
    if spec.disciplineId == "ncx_formula" then
        -- the invitational keeps its presentation (P52): post, then offer + accept a seat to everyone connected
        local e, err = NcmOrganized.post(spec.route, spec.minutes, { formatId = spec.formatId, laps = spec.laps, startType = spec.startType, formationM = spec.formationM, paceKph = spec.paceKph })
        if not e then current = nil; return nil, err end
        current.eventId = e.eventId
        local n = 0
        for _, pid in ipairs(Open77.players.all()) do
            if NcmOrganized.invite(pid) then NcmOrganized.acceptFor(pid); n = n + 1 end
        end
        for _, pid in ipairs(Open77.players.all()) do local dr = NcmCalendar.resolveDriver(pid); if dr and e.entries[dr.ncmDriverId] then current.field[pid] = dr.ncmDriverId end end
        slog("POSTED ncx event=%s route=%s format=%s in=%s seated=%d", e.eventId, e.routeName, spec.formatId, tostring(spec.minutes), n)
        return e
    end
    local route = Routes.resolve(root.rootId, root.displayName)
    if not route then current = nil; return nil, "route_unresolved" end
    local startsAt = math.floor(t + (tonumber(spec.minutes) or 3) * 60)
    local e = {
        eventId = ("scenario@%d"):format(startsAt), class = "calendar", invitation = false, registration = "venue",
        seriesId = "scenario", seriesName = "Scenario · " .. d.name, rulesetId = "street_sprint_v0", tier = d.tier == "sanctioned" and "sanctioned" or "street",
        routeId = route.routeId, routeName = route.name,
        startsAt = startsAt, entryOpensAt = math.floor(t), entryClosesAt = startsAt - setting("raceFormAtSec", 60),
        venue = { x = route.start.x, y = route.start.y, z = route.start.z, heading = route.start.heading, name = route.start.name, nodeId = route.start.id },
        finish = { x = route.finish.x, y = route.finish.y, z = route.finish.z, name = route.finish.name, nodeId = route.finish.id },
        distanceM = route.distanceM, venueRadiusM = 1e9, state = "entry_open", entries = {}, postedAt = t,
        disciplineId = spec.disciplineId, formatId = spec.formatId, classId = spec.classId or "street_open", laps = spec.laps or route.laps or (d.adapter == "laps" and 3 or 1),
        scenarioId = current.id, startType = spec.startType, formationM = spec.formationM, paceKph = spec.paceKph,
    }
    local ok, err = NcmCalendar.adopt(e)
    if not ok then current = nil; return nil, err end
    current.eventId = e.eventId
    local n = enterEveryone(e, t)
    NcmCalendar.publishNow()
    for pid, _ in pairs(current.field) do
        tell(pid, ("%s: %s · %s (%s → %s, %d m%s). You're entered. Start in %s — the map shows the start."):format(current.id, e.seriesName, e.routeName, e.venue.name, e.finish.name,
            math.floor(e.distanceM), e.laps > 1 and (" × " .. e.laps .. " laps") or "", Entry.countdown(e.startsAt - t)))
        toast(pid, { type = "warning", title = current.id .. " · " .. d.name, message = e.routeName .. " · start in " .. Entry.countdown(e.startsAt - t), icon = "NCM", durationMs = 8000 })
        TriggerClientEvent("ncm:guide.route", pid, { x = e.venue.x, y = e.venue.y, z = e.venue.z, name = e.venue.name, eventId = e.eventId })
    end
    slog("POSTED event=%s discipline=%s route=%s format=%s laps=%d start=%s in=%s entered=%d", e.eventId, e.disciplineId, e.routeName, e.formatId, e.laps, tostring(spec.startType or "default"), tostring(spec.minutes), n)
    return e
end

function NcmScenario.stop(reason, t)
    t = t or now()
    if not current or not current.eventId then return 0 end
    local e = NcmCalendar.events[current.eventId]
    local n = NcmRace.abortEvent and NcmRace.abortEvent(current.eventId, reason or "scenario_stop") or 0
    if e then
        e.state = "closed"
        pcall(function() MySQL.update.await("UPDATE event SET state = 'closed' WHERE event_id = ?", { e.eventId }) end)
        for pid, _ in pairs(current.field) do pcall(function() Open77.state.player(pid):clear("ncmEntry") end) end
    end
    NcmCalendar.publishNow()
    slog("STOP event=%s reason=%s sessions=%d", tostring(current.eventId), tostring(reason), n)
    for pid, _ in pairs(current.field) do tell(pid, ("%s stopped (%s)."):format(current.id, tostring(reason or "host"))) end
    local was = current
    current = nil
    return n, was
end

function NcmScenario.restart(t)
    t = t or now()
    if not current then return nil, "no_scenario" end
    local spec = current.spec
    NcmScenario.stop("restart", t)
    spec.minutes = math.max(1.5, (setting("raceFormAtSec", 60) + 30) / 60)
    return NcmScenario.post(spec, t)
end

local function fieldReport()
    if not current then log("no scenario"); return end
    local e = NcmCalendar.events[current.eventId]
    log("%s event=%s state=%s start in %s field=%d", current.id, tostring(current.eventId), e and e.state or "?", e and Entry.countdown(e.startsAt - now()) or "?", (function() local n = 0 for _ in pairs(current.field) do n = n + 1 end return n end)())
    local sid_, rec = nil, nil
    for s, r in pairs(NcmRace.sessions) do if r.eventId == current.eventId then sid_, rec = s, r end end
    for pid, driverId in pairs(current.field) do
        local p = Open77.players.get(pid)
        local okSeat, seat = pcall(Open77.players.getVehicleSeat, pid)
        local en = rec and rec.s.entrants[driverId]
        local d = (p and p.position and e) and math.floor(Routes.planarDistance(p.position, e.venue)) or -1
        log("  pid=%d %s driver=%s %s car=%s pos=%s dist_to_start=%dm", pid, tostring(GetPlayerName(pid)), driverId:sub(1, 8),
            en and (en.state .. " p" .. tostring(en.progress or 0)) or (e and e.entries[driverId] and e.entries[driverId].state or "-"),
            (okSeat and type(seat) == "table") and tostring(seat.vehicleId or seat.vehicle or "yes") or "on foot",
            p and p.position and ("%.0f,%.0f"):format(p.position.x, p.position.y) or "?", d)
    end
    if rec then log("  session=%s kind=%s phase=%s", sid_, rec.kind, rec.s.phase) end
end

RegisterCommand("ncm.scenario", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    args = args or {}
    local sub = tostring(args[1] or ""):lower()
    if sub == "" or sub == "status" then fieldReport(); return end
    if sub == "field" then fieldReport(); return end
    if sub == "stop" then local n = NcmScenario.stop("host"); log("stopped (%d session(s))", n); return end
    if sub == "restart" then
        CreateThread(function() local e, err = NcmScenario.restart(); if not e then log("restart failed: %s", tostring(err)) end end)
        return
    end
    CreateThread(function()
        if current then NcmScenario.stop("replaced") end
        local e, err = NcmScenario.post(parseSpec(args))
        if not e then log("scenario failed: %s (ncm.scenario <discipline> <route> [format] [in <min>] [laps <n>])", tostring(err)) end
    end)
end, false)

-- ---------------------------------------------------------------------------------------------
-- Host commands on the live session
-- ---------------------------------------------------------------------------------------------
local function liveFor(pid)
    local driver = pid and NcmCalendar.resolveDriver(pid) or nil
    for s, rec in pairs(NcmRace.sessions) do
        if not rec.practice and (not driver or rec.s.entrants[driver.ncmDriverId]) then return s, rec, driver end
    end
    return nil
end

RegisterCommand("ncm.warp", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1]); local to = tostring(args and args[2] or "start")
    if not pid then log("usage: ncm.warp <pid> start|finish|grid|<pid>|<x,y,z>"); return end
    local target
    local _, rec, driver = liveFor(pid)
    local e = current and NcmCalendar.events[current.eventId] or nil
    if to == "start" or to == "grid" then
        if rec and driver and rec.slotOf and rec.slotOf[driver.ncmDriverId] and to == "grid" then local sl = rec.slotOf[driver.ncmDriverId]; target = { x = sl.x, y = sl.y, z = sl.z, heading = sl.heading }
        elseif rec then local g = rec.s.gates[1]; target = { x = g.x, y = g.y, z = g.z, heading = e and e.venue.heading }
        elseif e then target = { x = e.venue.x, y = e.venue.y, z = e.venue.z, heading = e.venue.heading } end
    elseif to == "finish" then
        if rec then local g = rec.s.gates[#rec.s.gates]; target = { x = g.x, y = g.y, z = g.z } elseif e then target = { x = e.finish.x, y = e.finish.y, z = e.finish.z } end
    elseif tonumber(to) then
        local p = Open77.players.get(tonumber(to)); if p and p.position then target = { x = p.position.x + 4, y = p.position.y + 4, z = p.position.z } end
    else
        local x, y, z = to:match("^(-?[%d%.]+),(-?[%d%.]+),?(-?[%d%.]*)$")
        if x then target = { x = tonumber(x), y = tonumber(y), z = tonumber(z) or 0 } end
    end
    if not target then log("ncm.warp: no target (%s)", to); return end
    target.why = "host warp " .. to
    TriggerEvent("ncm:warp", pid, target)
    slog("WARP pid=%d to=%s (%.0f,%.0f)", pid, to, target.x, target.y)
end, false)

RegisterCommand("ncm.lights", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local n = NcmRace.lightsNow and NcmRace.lightsNow() or 0
    slog("LIGHTS now -> %d session(s)", n)
end, false)

RegisterCommand("ncm.incident", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, band, kind = tonumber(args and args[1]), tonumber(args and args[2]) or 1, tostring(args and args[3] or "car")
    if not pid then log("usage: ncm.incident <pid> <band 1-3> [car|object]"); return end
    local s, rec, driver = liveFor(pid)
    if not rec or not driver then log("ncm.incident: pid %d is not in a live session", pid); return end
    local p = Open77.players.get(pid)
    local inc = { kind = kind, band = math.max(1, math.min(3, band)), dv = 0, x = p and p.position and p.position.x or 0, y = p and p.position and p.position.y or 0, z = p and p.position and p.position.z or 0, t = now(), attributed = "self", injected = true }
    if rec.tm and rec.tm.ledger then inc = rec.tm.ledger:add(driver.ncmDriverId, inc, rec.rules and rec.rules.incidents or nil) or inc end
    NcmRace.incident(rec, driver.ncmDriverId, inc, now())
    NcmRace.publish(rec, now())
    slog("INCIDENT injected pid=%d band=%d kind=%s", pid, band, kind)
end, false)

RegisterCommand("ncm.rules", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local what, val = tostring(args and args[1] or ""):lower(), tostring(args and args[2] or ""):lower()
    if what == "incidents" then
        NcmScenario.overrides.incidents = (val ~= "off")
        slog("RULES incidents %s", NcmScenario.overrides.incidents and "on" or "off")
    else
        log("ncm.rules incidents on|off   (current: incidents %s)", NcmScenario.overrides.incidents and "on" or "off")
    end
end, false)

RegisterCommand("ncm.trace", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid, val = tonumber(args and args[1]), tostring(args and args[2] or "on"):lower()
    local driver = pid and NcmCalendar.resolveDriver(pid)
    if not driver then log("usage: ncm.trace <pid> on|off"); return end
    NcmScenario.traced[driver.ncmDriverId] = (val ~= "off") or nil
    slog("TRACE pid=%d driver=%s %s", pid, driver.ncmDriverId:sub(1, 8), val)
end, false)

RegisterCommand("ncm.spectate", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    local s, rec, driver = liveFor(pid)
    if not rec then log("ncm.spectate: pid %s is not in a live session", tostring(pid)); return end
    local events = rec.kernel.leave(rec.s, driver.ncmDriverId, now(), "spectating")
    if events then NcmRace.handle(rec, events, now()) end
    NcmRace.publish(rec, now())
    tell(pid, "Race control: you're out of this one — spectating.")
    slog("SPECTATE pid=%d", pid)
end, false)

RegisterCommand("ncm.kick", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    local pid = tonumber(args and args[1])
    if not pid then log("usage: ncm.kick <pid> [reason]"); return end
    local ok, err = pcall(function() return Open77.players.kick(pid, args[2] or "host") end)
    slog("KICK pid=%d -> %s %s", pid, tostring(ok), tostring(err or ""))
end, false)

RegisterCommand("ncm.state", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    local t = now()
    log("STATE %s now=%d | scenario=%s | overrides incidents=%s", sid(), math.floor(t), current and (current.id .. " " .. tostring(current.eventId)) or "none", tostring(NcmScenario.overrides.incidents))
    local n = 0
    for s, rec in pairs(NcmRace.sessions) do
        n = n + 1
        local v = rec.kernel.publicView(rec.s)
        log("  session=%s event=%s kind=%s phase=%s%s starts=%s hold=%s", s, rec.eventId, rec.kind, v.phase, rec.practice and " (practice)" or "",
            v.startsAt and Entry.countdown((v.startsAt or t) - t) or "-", v.hold and (v.hold.ready .. "/" .. v.hold.total) or "-")
        for _, en in ipairs(v.entrants or {}) do
            local tm = rec.tm and rec.tm.rings and rec.tm.rings[en.driverId]
            local last = tm and tm:last(1) or nil
            log("    %-22s pid=%s state=%-9s progress=%s%s best=%s inc=%.1fs telemetry=%s", tostring(en.display), tostring(rec.playerOf[en.driverId]), en.state,
                tostring(en.progress or 0), en.runProgress and (" run=" .. en.runProgress) or "", en.bestSec and string.format("%.1f", en.bestSec) or "-", en.incidentSec or 0,
                last and ((last.client and "client " or "server ") .. string.format("%.0fs ago", t - (last.t or t))) or "none")
        end
    end
    if n == 0 then log("  no sessions") end
    for eid, plan in pairs(NcmRace.plans) do log("  plan event=%s format=%s session %d/%d results=%d", eid, plan.formatId, plan.i or 0, #plan.specs, #plan.results) end
end, false)

RegisterCommand("ncm.world", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    if tostring(args and args[1] or "") ~= "reset" then log("usage: ncm.world reset"); return end
    local n = NcmRace.abort("world_reset")
    if current then NcmScenario.stop("world_reset") end
    if NcmOrganized and NcmOrganized.clearOffers then NcmOrganized.clearOffers() end
    TriggerEvent("ncm:worldReset")
    for _, pid in ipairs(Open77.players.all()) do pcall(function() Open77.state.player(pid):clear("ncmEntry") end); tell(pid, "World reset by the host: sessions ended, cars returned.") end
    log("WORLD RESET sessions=%d", n)
end, false)

CreateThread(function()
    Wait(2500)   -- after the migrations and the calendar have started
    NcmScenario.loadRoutes()
end)
log("host kit ready")
