-- ncm_world / server / venue — venue authoring kit (M7.5.1; P26 drafting loop, P35 spawn/node pairs, P36 authored routes).
--
-- The owner drives; the server records. Everything lands in `venue_point` / `venue_route` (schema 007) and is read
-- back at start, so the TW1 opening (dispersed spawn → chauffeur → paddock → grid) runs off data, not code.
--
--   /ncm.au venue <id>           working venue (default pacifica_stadium)
--   /ncm.au spot <n>             tester spawn spot n at my position/heading
--   /ncm.au node <n>             where spot n's chauffeur is born (inside streaming range of the spot, KB-10)
--   /ncm.au paddock | grid       the drop-off (paddock) and the grid start line (position + heading of travel)
--   /ncm.au route <n>            start recording my drive from spot n to the paddock; /ncm.au route stop saves it
--   /ncm.au route play <n>       validation: chauffeur at node n → pulls up to me → follows the route to the paddock
--   /ncm.au tp spot|node|paddock|grid [n]
--   /ncm.au list | del <kind> <key> | tw1 on|off
--   /ncm.au dress <alias> [yaw] [radius]   place a server prop here / at the waypoint. Aliases are the platform's curated table
--                                (open77_admin shared/config.lua): barrier.road.jersey, barrier.concrete, barrier.roadblock.concrete,
--                                barrier.tire_blocker, race.route_arrow, race.checkpoint, street.lamp …; an unknown alias fails
--                                on the client as template_backend_disabled (Batch 1 live, 2026-09-21)
--   /ncm.au dress npc <template> [face:grid] a spectator NPC here, looking at the grid
--   /ncm.au dress list | undo | clear yes | up | down   the loader: spawn / tear down the venue's dressing
--   /ncm.aw <same>               the same captures taken at the MAP WAYPOINT instead of my body (client/main.lua);
--                                /ncm.aw route <n> add appends the waypoint to a route draft, /ncm.aw route stop saves it
NcmVenue = {}

local Core = NcmCore
local function log(fmt, ...) print(("[ncm_world/venue] " .. fmt):format(...)) end
local function tell(pid, text) pcall(Open77.chat.send, pid, "[NCM] " .. text) end

local venueId = "pacifica_stadium"
local points = {}     -- kind -> key -> { x, y, z, heading, meta }
local routes = {}     -- routeKey -> { fromKind, fromKey, toKind, toKey, points = {...}, lengthM }
local settings = {}   -- tw1 = true/false
local recording = {}  -- pid -> { key, points, last, startedAt, lengthM }
local drafts = {}     -- pid -> { key, points, lengthM }  (routes drawn with map markers)

local SAMPLE_MIN_M = 110
local MAX_POINTS = 64
local DEFAULT_VENUE = "pacifica_stadium"

local function dist2d(a, b)
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function serverId()
    return (NcmIdentity and NcmIdentity.serverId and NcmIdentity.serverId()) or "ncm-dev"
end

local function encodePoints(list)
    local parts = {}
    for i, p in ipairs(list) do parts[i] = ("[%.2f,%.2f,%.2f]"):format(p.x, p.y, p.z or 0) end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function decodePoints(sv)
    local out = {}
    if type(sv) == "table" then
        for _, p in ipairs(sv) do out[#out + 1] = { x = tonumber(p[1] or p.x), y = tonumber(p[2] or p.y), z = tonumber(p[3] or p.z) or 0 } end
        return out
    end
    for x, y, z in tostring(sv or ""):gmatch("%[%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*%]") do
        out[#out + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end
    return out
end

local CoreJson = Core.get("vocabulary.json")
local function encodeMeta(t)
    if t == nil then return nil end
    if json and json.encode then return json.encode(t) end
    return CoreJson.encode(t)
end

local function decodeMeta(sv)
    if sv == nil then return nil end
    if type(sv) == "table" then return sv end
    if json and json.decode then local ok, v = pcall(json.decode, sv); if ok and type(v) == "table" then return v end end
    local v = CoreJson.decode(sv)
    return type(v) == "table" and v or nil
end

-- ---------------------------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------------------------
function NcmVenue.load()
    points, routes, settings = {}, {}, {}
    if not MySQL.isReady() then return end
    pcall(function()
        local rows = MySQL.query.await("SELECT kind, point_key, x, y, z, heading, meta_json FROM venue_point WHERE server_id = ? AND venue_id = ?", { serverId(), venueId }) or {}
        for _, r in ipairs(rows) do
            points[r.kind] = points[r.kind] or {}
            points[r.kind][r.point_key] = { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z), heading = tonumber(r.heading) or 0, meta = decodeMeta(r.meta_json) }
            if r.kind == "setting" then settings[r.point_key] = tonumber(r.x) == 1 end
        end
        local rr = MySQL.query.await("SELECT route_key, from_kind, from_key, to_kind, to_key, points_json, length_m FROM venue_route WHERE server_id = ? AND venue_id = ?", { serverId(), venueId }) or {}
        for _, r in ipairs(rr) do
            routes[r.route_key] = { fromKind = r.from_kind, fromKey = r.from_key, toKind = r.to_kind, toKey = r.to_key, points = decodePoints(r.points_json), lengthM = tonumber(r.length_m) or 0 }
        end
    end)
    local np = 0
    for _, byKey in pairs(points) do for _ in pairs(byKey) do np = np + 1 end end
    local nr = 0
    for _ in pairs(routes) do nr = nr + 1 end
    log("venue %s loaded: %d point(s), %d route(s), tw1=%s", venueId, np, nr, tostring(settings.tw1 or false))
    NcmVenue.publish()
end

--- Points the league needs (grid for REPORT TO GRID, paddock for the drop-off) travel on GlobalState.
function NcmVenue.publish()
    pcall(function()
        GlobalState.ncmVenue = { venueId = venueId, grid = NcmVenue.point("grid", "1"), paddock = NcmVenue.point("paddock", "1"), tw1 = settings.tw1 == true }
    end)
end

local function savePoint(kind, key, p, meta)
    points[kind] = points[kind] or {}
    points[kind][key] = { x = p.x, y = p.y, z = p.z, heading = p.heading or 0, meta = meta }
    if kind == "grid" or kind == "paddock" then NcmVenue.publish() end
    if not MySQL.isReady() then return end
    pcall(function()
        MySQL.insert.await(
            "INSERT INTO venue_point (server_id, venue_id, kind, point_key, x, y, z, heading, meta_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) " ..
            "ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z), heading = VALUES(heading), meta_json = VALUES(meta_json)",
            { serverId(), venueId, kind, key, p.x, p.y, p.z, p.heading or 0, encodeMeta(meta) })
    end)
end

local function deletePoint(kind, key)
    if points[kind] then points[kind][key] = nil end
    if not MySQL.isReady() then return end
    pcall(function() MySQL.update.await("DELETE FROM venue_point WHERE server_id = ? AND venue_id = ? AND kind = ? AND point_key = ?", { serverId(), venueId, kind, key }) end)
end

local function bearing(a, b)
    return (math.deg(math.atan(b.y - a.y, b.x - a.x)) + 360) % 360
end

local function saveRoute(key, r, driverId)
    routes[key] = r
    -- the spot faces its first route point, the node faces the spot (map-drawn captures carry no heading)
    local spot, node = points.spot and points.spot[key], points.node and points.node[key]
    if spot and r.points[2] then spot.heading = bearing(spot, r.points[2]); savePoint("spot", key, spot) end
    if node and spot then node.heading = bearing(node, spot); savePoint("node", key, node) end
    if not MySQL.isReady() then return end
    pcall(function()
        MySQL.insert.await(
            "INSERT INTO venue_route (server_id, venue_id, route_key, from_kind, from_key, to_kind, to_key, points_json, length_m, recorded_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) " ..
            "ON DUPLICATE KEY UPDATE points_json = VALUES(points_json), length_m = VALUES(length_m), recorded_by = VALUES(recorded_by), from_kind = VALUES(from_kind), from_key = VALUES(from_key)",
            { serverId(), venueId, key, r.fromKind, r.fromKey, r.toKind, r.toKey, encodePoints(r.points), r.lengthM or 0, driverId })
    end)
end

-- ---------------------------------------------------------------------------------------------
-- Read API (used by the arrival flow)
-- ---------------------------------------------------------------------------------------------
function NcmVenue.id() return venueId end
function NcmVenue.point(kind, key) return points[kind] and points[kind][tostring(key)] end
function NcmVenue.route(key) return routes[tostring(key)] end
function NcmVenue.tw1() return settings.tw1 == true end

--- Spots in numeric order.
function NcmVenue.spots()
    local out = {}
    for k, p in pairs(points.spot or {}) do out[#out + 1] = { key = k, n = tonumber(k) or 0, x = p.x, y = p.y, z = p.z, heading = p.heading } end
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end

--- Everything a chauffeur needs for spot n: node (birth), spot (pull-up), route points, paddock (drop-off).
function NcmVenue.approach(n)
    local key = tostring(n)
    local spot, node, paddock = NcmVenue.point("spot", key), NcmVenue.point("node", key), NcmVenue.point("paddock", "1")
    local route = routes[key]
    if not (spot and paddock) then return nil, "spot_or_paddock_missing" end
    return { spot = spot, node = node or spot, paddock = paddock, route = route and route.points or nil, routeLengthM = route and route.lengthM or nil }
end

-- ---------------------------------------------------------------------------------------------
-- Route recording (sampler thread per recording player)
-- ---------------------------------------------------------------------------------------------
--- Keep at most MAX_POINTS by dropping the least significant interior points (smallest deviation from the
--- line between their neighbours) until the list fits. Endpoints always stay.
local function thin(list)
    local function deviation(i)
        local a, b, c = list[i - 1], list[i], list[i + 1]
        local abx, aby = c.x - a.x, c.y - a.y
        local len = math.sqrt(abx * abx + aby * aby)
        if len < 1 then return 0 end
        return math.abs((b.x - a.x) * aby - (b.y - a.y) * abx) / len
    end
    while #list > MAX_POINTS do
        local worst, worstDev = nil, math.huge
        for i = 2, #list - 1 do
            local d = deviation(i)
            if d < worstDev then worst, worstDev = i, d end
        end
        table.remove(list, worst)
    end
    return list
end

local function sampler(pid)
    while recording[pid] do
        Wait(1000)
        local rec = recording[pid]
        if not rec then break end
        local p = Open77.players.get(pid)
        if p and p.position then
            local last = rec.points[#rec.points]
            local d = dist2d(last, p.position)
            if d >= SAMPLE_MIN_M then
                rec.points[#rec.points + 1] = { x = p.position.x, y = p.position.y, z = p.position.z }
                rec.lengthM = rec.lengthM + d
                if #rec.points % 10 == 0 then tell(pid, ("Recording: %d points, %.1f km"):format(#rec.points, rec.lengthM / 1000)) end
            end
        end
    end
end

local function startRoute(pid, key)
    local p = Open77.players.get(pid)
    if not p or not p.position then tell(pid, "No position."); return end
    if recording[pid] then tell(pid, "Already recording; /ncm.au route stop first."); return end
    recording[pid] = { key = key, points = { { x = p.position.x, y = p.position.y, z = p.position.z } }, startedAt = Open77.time.unix(), lengthM = 0 }
    tell(pid, ("Recording route %s from here. Drive to the paddock, then /ncm.au route stop."):format(key))
    CreateThread(function() sampler(pid) end)
end

local function stopRoute(pid, driverId)
    local rec = recording[pid]
    if not rec then tell(pid, "Not recording."); return end
    recording[pid] = nil
    local p = Open77.players.get(pid)
    if p and p.position then
        local last = rec.points[#rec.points]
        if dist2d(last, p.position) > 5 then
            rec.lengthM = rec.lengthM + dist2d(last, p.position)
            rec.points[#rec.points + 1] = { x = p.position.x, y = p.position.y, z = p.position.z }
        end
    end
    if #rec.points < 2 then tell(pid, "Route too short; nothing saved."); return end
    local raw = #rec.points
    thin(rec.points)
    local r = { fromKind = "spot", fromKey = rec.key, toKind = "paddock", toKey = "1", points = rec.points, lengthM = rec.lengthM }
    saveRoute(rec.key, r, driverId)
    tell(pid, ("Route %s saved: %d points (%d sampled), %.2f km, %.0f s of driving."):format(rec.key, #rec.points, raw, rec.lengthM / 1000, Open77.time.unix() - rec.startedAt))
    log("route %s saved by player %d: %d points, %.0f m", rec.key, pid, #rec.points, rec.lengthM)
end

-- ---------------------------------------------------------------------------------------------
-- Dressing (Batch 1, item 4; P26): props and spectator NPCs authored in the world, spawned by the loader when an
-- organized event at this venue dresses (pickup dispatch / first session) and removed when it retires.
-- Every refusal reason is logged — that is the E19/E20 data. NPC count is capped.
-- ---------------------------------------------------------------------------------------------
local live = { prop = {}, npc = {} }   -- kind -> key -> platform id
local lastPlaced = {}                  -- pid -> { kind, key }
local NPC_CAP = 12
local DRESS_STREAM_M = 150
local DEFAULT_PROP = "barrier.road.jersey"

--- op77.84 wants `damagePolicy` as a member of the `Open77.npcs.damage` enum (a number), not the string the
--- op77.78 API card shows. Only `mortal` is named in shipped sources; try the likely non-mortal names, else omit
--- the field (every policy but mortal is immortal anyway) and log the enum once so the real name gets recorded.
local damageLogged = false
local function invulnerablePolicy()
    local enum = Open77.npcs and Open77.npcs.damage
    if type(enum) ~= "table" then return nil end
    for _, k in ipairs({ "invulnerable", "immortal", "immune", "invincible", "godmode", "none" }) do
        if enum[k] ~= nil then
            if not damageLogged then damageLogged = true; log("npcs.damage.%s = %s (KB-13: record this name in the docs)", k, tostring(enum[k])) end
            return enum[k]
        end
    end
    if not damageLogged then
        damageLogged = true
        local keys = {}
        for k, v in pairs(enum) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
        table.sort(keys)
        log("npcs.damage enum has no invulnerable-like member; keys: %s", table.concat(keys, " "))
    end
    return nil
end

local function nextKey(kind)
    local n = 0
    for k in pairs(points[kind] or {}) do n = math.max(n, tonumber(k) or 0) end
    return tostring(n + 1)
end

local function spawnProp(key, p)
    local meta = p.meta or {}
    local ok, id, reason = pcall(Open77.props.create, {
        model = meta.model or DEFAULT_PROP, position = { x = p.x, y = p.y, z = p.z }, yaw = tonumber(meta.yaw) or p.heading or 0,
        bucket = 0, streamingRadius = tonumber(meta.streamingRadius) or DRESS_STREAM_M, persistent = false,
    })
    if not ok or not id then log("prop %s (%s) refused: %s", key, tostring(meta.model), tostring(reason or id)); return nil, reason or id end
    live.prop[key] = id
    return id
end

local function spawnNpc(key, p)
    local meta = p.meta or {}
    local grid = NcmVenue.point("grid", "1")
    local yaw = p.heading or 0
    if grid and meta.face ~= "none" then yaw = (math.deg(math.atan(grid.y - p.y, grid.x - p.x)) + 360) % 360 end
    local spec = { position = { x = p.x, y = p.y, z = p.z }, yaw = yaw, bucket = 0, streamingRadius = tonumber(meta.streamingRadius) or DRESS_STREAM_M,
                   persistent = false, damagePolicy = invulnerablePolicy() }
    spec.template = meta.template
    local ok, id, reason = pcall(Open77.npcs.create, spec)
    if not ok or not id then
        spec.template = nil; spec.record = meta.template
        local ok2, id2, reason2 = pcall(Open77.npcs.create, spec)
        if not ok2 or not id2 then log("npc %s (%s) refused: %s / %s", key, tostring(meta.template), tostring(reason or id), tostring(reason2 or id2)); return nil, reason2 or reason end
        id = id2
    end
    live.npc[key] = id
    if grid and Open77.npcs.tasks and Open77.npcs.tasks.lookAt then
        pcall(Open77.npcs.tasks.lookAt, id, { type = "position", position = { x = grid.x, y = grid.y, z = grid.z } })
    end
    return id
end

--- Spawn everything authored for the venue (idempotent).
function NcmVenue.dressUp(reason)
    local props, npcs, failed = 0, 0, 0
    for key, p in pairs(points.prop or {}) do
        if not live.prop[key] then if spawnProp(key, p) then props = props + 1 else failed = failed + 1 end end
    end
    local n = 0
    for key, p in pairs(points.npc or {}) do
        n = n + 1
        if n <= NPC_CAP and not live.npc[key] then if spawnNpc(key, p) then npcs = npcs + 1 else failed = failed + 1 end end
    end
    log("dressUp venue=%s reason=%s props=%d npcs=%d failed=%d", venueId, tostring(reason), props, npcs, failed)
    return props, npcs, failed
end

function NcmVenue.dressDown(reason)
    local n = 0
    for key, id in pairs(live.prop) do pcall(Open77.props.remove, id); live.prop[key] = nil; n = n + 1 end
    for key, id in pairs(live.npc) do pcall(Open77.npcs.remove, id); live.npc[key] = nil; n = n + 1 end
    log("dressDown venue=%s reason=%s removed=%d", venueId, tostring(reason), n)
    return n
end

function NcmVenue.dressCount()
    local a, b = 0, 0
    for _ in pairs(live.prop) do a = a + 1 end
    for _ in pairs(live.npc) do b = b + 1 end
    return a, b
end

function NcmVenue.dressCommand(pid, what, a3, a4, here)
    if not what or what == "list" then
        local lp, ln = NcmVenue.dressCount()
        local np, nn = 0, 0
        for _ in pairs(points.prop or {}) do np = np + 1 end
        for _ in pairs(points.npc or {}) do nn = nn + 1 end
        tell(pid, ("Dressing at %s: %d prop(s), %d NPC(s) authored; %d + %d live."):format(venueId, np, nn, lp, ln))
        for k, p in pairs(points.prop or {}) do tell(pid, ("  prop %s %s  %.1f,%.1f%s"):format(k, tostring(p.meta and p.meta.model), p.x, p.y, live.prop[k] and "  (live)" or "")) end
        for k, p in pairs(points.npc or {}) do tell(pid, ("  npc %s %s  %.1f,%.1f%s"):format(k, tostring(p.meta and p.meta.template), p.x, p.y, live.npc[k] and "  (live)" or "")) end
    elseif what == "up" then
        local a, b, c = NcmVenue.dressUp("command"); tell(pid, ("Dressed: %d props, %d NPCs, %d refused (see log)."):format(a, b, c))
    elseif what == "down" then
        tell(pid, ("Undressed: %d removed."):format(NcmVenue.dressDown("command")))
    elseif what == "undo" then
        local last = lastPlaced[pid]
        if not last then tell(pid, "Nothing to undo."); return end
        local id = live[last.kind][last.key]
        if id then pcall(last.kind == "prop" and Open77.props.remove or Open77.npcs.remove, id); live[last.kind][last.key] = nil end
        deletePoint(last.kind, last.key); lastPlaced[pid] = nil
        tell(pid, ("Removed %s %s."):format(last.kind, last.key))
    elseif what == "clear" then
        if a3 ~= "yes" then tell(pid, "Type /ncm.au dress clear yes to delete every prop and NPC of this venue."); return end
        NcmVenue.dressDown("clear")
        local n = 0
        for _, kind in ipairs({ "prop", "npc" }) do
            for k in pairs(points[kind] or {}) do deletePoint(kind, k); n = n + 1 end
        end
        tell(pid, ("Cleared %d dressing point(s)."):format(n))
    elseif what == "npc" then
        local template = a3
        if not template then tell(pid, "Usage: /ncm.au dress npc <template> [face:grid|none]"); return end
        local p = here(pid); if not p then tell(pid, "No position."); return end
        local key = nextKey("npc")
        local meta = { template = template, face = (a4 == "face:none") and "none" or "grid", streamingRadius = DRESS_STREAM_M }
        savePoint("npc", key, p, meta); lastPlaced[pid] = { kind = "npc", key = key }
        local id, why = spawnNpc(key, points.npc[key])
        tell(pid, id and ("Placed NPC %s (%s) — looking at the grid."):format(key, template) or ("Saved NPC %s but the platform refused it: %s"):format(key, tostring(why)))
    else
        local model = what
        local p = here(pid); if not p then tell(pid, "No position."); return end
        -- 2.5 m ahead of the author, not at their feet: a barrier placed on the player traps them (Batch 1 live).
        local rad = math.rad(p.heading or 0)
        p = { x = p.x + math.cos(rad) * 2.5, y = p.y + math.sin(rad) * 2.5, z = p.z, heading = p.heading }
        local key = nextKey("prop")
        local meta = { model = model, yaw = tonumber(a3) or p.heading or 0, streamingRadius = tonumber(a4) or DRESS_STREAM_M }
        savePoint("prop", key, p, meta); lastPlaced[pid] = { kind = "prop", key = key }
        local id, why = spawnProp(key, points.prop[key])
        tell(pid, id and ("Placed prop %s %s at %.1f,%.1f yaw %.0f."):format(key, model, p.x, p.y, meta.yaw) or ("Saved prop %s but the platform refused it: %s"):format(key, tostring(why)))
    end
end

-- The league says when the venue should be dressed (rides dispatched / first session) and undressed (plan retired).
AddEventHandler("ncm:venueDress", function(eventId) CreateThread(function() NcmVenue.dressUp("event " .. tostring(eventId)) end) end)
AddEventHandler("ncm:venueUndress", function(eventId, reason) CreateThread(function() NcmVenue.dressDown(tostring(reason or eventId)) end) end)
AddEventHandler("onResourceStop", function(name) if name == "ncm_world" then NcmVenue.dressDown("resource_stopped") end end)

-- ---------------------------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------------------------
local function here(pid)
    local p = Open77.players.get(pid)
    if not p or not p.position then return nil end
    local okSeat, seat = pcall(Open77.players.getVehicleSeat, pid)
    if okSeat and type(seat) == "table" then tell(pid, "Note: captured from inside a vehicle — points are best taken on foot.") end
    return { x = p.position.x, y = p.position.y, z = p.position.z, heading = tonumber(p.heading or p.yaw or 0) or 0 }
end

local function describe(kind, key, p)
    return ("%s %s  %.1f, %.1f, %.1f  hdg %.0f"):format(kind, key, p.x, p.y, p.z, p.heading or 0)
end

function NcmVenue.command(pid, args, wp)
    local sub = tostring(args[1] or ""):lower()
    local here = wp and function() return { x = wp.x, y = wp.y, z = wp.z or 0, heading = 0 } end or here
    local a2, a3 = args[2] and tostring(args[2]):lower() or nil, args[3] and tostring(args[3]) or nil
    local driver = NcmIdentity.get(pid)
    local driverId = driver and driver.ncmDriverId or nil
    if sub == "venue" then
        if a2 then venueId = a2; NcmVenue.load() end
        tell(pid, "Working venue: " .. venueId)
    elseif sub == "spot" or sub == "node" then
        local n = tonumber(a2)
        if not n then tell(pid, "Usage: /ncm.au " .. sub .. " <1-20>"); return true end
        local p = here(pid); if not p then tell(pid, "No position."); return true end
        savePoint(sub, tostring(math.floor(n)), p)
        tell(pid, "Saved " .. describe(sub, tostring(math.floor(n)), p))
    elseif sub == "paddock" or sub == "grid" then
        local p = here(pid); if not p then tell(pid, "No position."); return true end
        savePoint(sub, "1", p)
        tell(pid, "Saved " .. describe(sub, "1", p))
    elseif sub == "route" and a3 and a3:lower() == "add" then
        local n = tonumber(a2)
        if not (n and wp) then tell(pid, "Usage: set a map waypoint, then /ncm.aw route <n> add"); return true end
        local key = tostring(math.floor(n))
        local d = drafts[pid]
        if not d or d.key ~= key then
            local spot = NcmVenue.point("spot", key)
            d = { key = key, points = { spot and { x = spot.x, y = spot.y, z = spot.z } or nil }, lengthM = 0 }
            if #d.points == 0 then tell(pid, "Draft starts at the waypoint (no spot " .. key .. " yet; capture it to start the route there).") end
            drafts[pid] = d
        end
        local pt = { x = wp.x, y = wp.y, z = wp.z or 0 }
        if #d.points > 0 then d.lengthM = d.lengthM + dist2d(d.points[#d.points], pt) end
        d.points[#d.points + 1] = pt
        tell(pid, ("Route %s draft: %d point(s), %.2f km. Next marker + /ncm.aw route %s add, or /ncm.aw route stop to save."):format(key, #d.points, d.lengthM / 1000, key))
    elseif sub == "route" then
        if a2 == "stop" and drafts[pid] then
            local d = drafts[pid]; drafts[pid] = nil
            local paddock = NcmVenue.point("paddock", "1")
            if paddock and dist2d(d.points[#d.points], paddock) > 15 then
                d.lengthM = d.lengthM + dist2d(d.points[#d.points], paddock)
                d.points[#d.points + 1] = { x = paddock.x, y = paddock.y, z = paddock.z }
            end
            if #d.points < 2 then tell(pid, "Draft too short; nothing saved."); return true end
            thin(d.points)
            saveRoute(d.key, { fromKind = "spot", fromKey = d.key, toKind = "paddock", toKey = "1", points = d.points, lengthM = d.lengthM }, driverId)
            tell(pid, ("Route %s saved from markers: %d points, %.2f km (ends at the paddock)."):format(d.key, #d.points, d.lengthM / 1000))
        elseif a2 == "stop" then stopRoute(pid, driverId)
        elseif a2 == "play" then
            local n = tonumber(a3)
            if not n then tell(pid, "Usage: /ncm.au route play <n>"); return true end
            local ap, why = NcmVenue.approach(math.floor(n))
            if not ap then tell(pid, "Cannot play: " .. tostring(why)); return true end
            if not ap.route then tell(pid, "No route recorded for spot " .. math.floor(n) .. " yet (drive it: /ncm.au route " .. math.floor(n) .. ")."); return true end
            NcmPickup.request(pid, { eventId = "au", teamName = "NCM", teamShort = "NCM", venueName = venueId .. " paddock",
                spawnAt = ap.node, pullUpTo = ap.spot, route = ap.route, dropoff = ap.paddock, speed = 18, replace = true })
            tell(pid, ("Playing approach %d: chauffeur born at the node, %d route points, %.2f km."):format(math.floor(n), #ap.route, (ap.routeLengthM or 0) / 1000))
        else
            local n = tonumber(a2)
            if not n then tell(pid, "Usage: /ncm.au route <n> | route stop | route play <n>"); return true end
            startRoute(pid, tostring(math.floor(n)))
        end
    elseif sub == "tp" then
        local kind, key = a2, (a3 or "1")
        local p = NcmVenue.point(kind, key)
        if not p then tell(pid, "No such point: " .. tostring(kind) .. " " .. tostring(key)); return true end
        local okSeat, seat = pcall(Open77.players.getVehicleSeat, pid)
        if okSeat and type(seat) == "table" then tell(pid, "Get out of the car first (teleporting while seated freezes the client)."); return true end
        CreateThread(function()
            local ok, reason = Open77.players.teleport(pid, { x = p.x, y = p.y, z = p.z + 1.0 }, { heading = p.heading, fade = true, dismount = true })
            tell(pid, ok and ("At " .. describe(kind, key, p)) or ("Teleport failed: " .. tostring(reason)))
        end)
    elseif sub == "del" then
        if not (a2 and a3) then tell(pid, "Usage: /ncm.au del <kind> <key>"); return true end
        deletePoint(a2, a3); tell(pid, "Deleted " .. a2 .. " " .. a3)
    elseif sub == "dress" then
        NcmVenue.dressCommand(pid, a2, a3, args[4], here)
    elseif sub == "tw1" then
        settings.tw1 = (a2 == "on")
        savePoint("setting", "tw1", { x = settings.tw1 and 1 or 0, y = 0, z = 0, heading = 0 })
        NcmVenue.publish()   -- the league reads GlobalState.ncmVenue.tw1 (chauffeur only in TW1 mode, P52)
        tell(pid, "TW1 mode " .. (settings.tw1 and "ON: testers spawn at spots, rides follow authored routes" or "OFF"))
    elseif sub == "list" then
        tell(pid, "Venue " .. venueId .. (settings.tw1 and " (TW1 mode on)" or ""))
        for _, kind in ipairs({ "paddock", "grid", "spot", "node", "prop", "npc" }) do
            local keys = {}
            for k in pairs(points[kind] or {}) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
            for _, k in ipairs(keys) do tell(pid, "  " .. describe(kind, k, points[kind][k])) end
        end
        local rkeys = {}
        for k in pairs(routes) do rkeys[#rkeys + 1] = k end
        table.sort(rkeys, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
        for _, k in ipairs(rkeys) do tell(pid, ("  route %s: %d points, %.2f km"):format(k, #routes[k].points, (routes[k].lengthM or 0) / 1000)) end
        if #rkeys == 0 then tell(pid, "  (no routes yet)") end
    else
        tell(pid, "/ncm.au venue <id> | spot <n> | node <n> | paddock | grid | route <n> | route stop | route play <n> | tp <kind> [n] | list | del <kind> <key> | tw1 on|off")
    end
    return true
end

RegisterCommand("ncm.au", function(source, args)
    local pid = tonumber(source) or 0
    if pid <= 0 then log("ncm.au is a chat command (the owner drives and captures)"); return end
    CreateThread(function() NcmVenue.command(pid, args or {}) end)
end, false)

-- /ncm.aw: the client forwards its map waypoint with the arguments (client/main.lua)
RegisterNetEvent("ncm:auwp", function(x, y, z, ...)
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local args = { ... }
    x, y = tonumber(x), tonumber(y)
    if not (x and y) then tell(pid, "Set a waypoint on the map first, then /ncm.aw …"); return end
    CreateThread(function() NcmVenue.command(pid, args, { x = x, y = y, z = tonumber(z) or 0 }) end)
end)

-- ---------------------------------------------------------------------------------------------
-- Dispersed spawn (TW1 mode): a driver arriving gets an unused spot; the same driver keeps it for the session.
-- ---------------------------------------------------------------------------------------------
local spotOf = {}      -- driverId -> spot key
local takenBy = {}     -- spot key -> driverId
NcmVenue.spotOf = spotOf

function NcmVenue.assignSpot(driverId)
    if spotOf[driverId] then return spotOf[driverId] end
    for _, s in ipairs(NcmVenue.spots()) do
        if not takenBy[s.key] then takenBy[s.key] = driverId; spotOf[driverId] = s.key; return s.key end
    end
    return nil
end

AddEventHandler("onPlayerReady", function(playerId)
    if not settings.tw1 then return end
    local pid = tonumber(playerId) or 0
    CreateThread(function()
        Wait(1500)
        local prof = NcmIdentity.get(pid)
        if not prof then return end
        local key = NcmVenue.assignSpot(prof.ncmDriverId)
        if not key then log("tw1: no free spot for player %d", pid); return end
        local p = NcmVenue.point("spot", key)
        local ok, reason = Open77.players.teleport(pid, { x = p.x, y = p.y, z = p.z + 1.0 }, { heading = p.heading, fade = true, dismount = true })
        log("tw1: player %d -> spot %s (%s)", pid, key, ok and "ok" or tostring(reason))
    end)
end)

AddEventHandler("onResourceStart", function(name)
    if name ~= "ncm_world" then return end
    CreateThread(function()
        -- the league applies migrations; wait for the tables before reading
        for _ = 1, 30 do
            local ok, n = pcall(function() return MySQL.scalar.await("SELECT COUNT(*) FROM schema_migrations WHERE version >= 9") end)
            if ok and tonumber(n) and tonumber(n) >= 1 then break end
            Wait(1000)
        end
        NcmVenue.load()
    end)
end)
