-- ncm_paddock / server / probe -- what moves an AI car on build .102, measured rather than assumed (L228, L229).
--
-- The first probe (2026-09-29) found a car 3.6 km from the only player sat in `waiting_for_simulator` for 30 s. That is
-- ONE negative, not a rule: nobody asked any client to take it, and nothing was tried between "right beside you" and
-- 3.6 km. This suite asks the questions the continuous-race design depends on, one row per car:
--
--   distance  cars on road points at about 150 m, 400 m, 800 m, 1.5 km and 3 km from the probing player
--   leg A     unasked: does a client pick the car up by itself at that distance?
--   leg B     `vehicles.requestAuthority(car, player)`: does ASKING the player's client make it simulate the car?
--   leg C     a remote-camera interest lease at the car (`open77_remote_camera` acquire) plus the request again: does
--             streaming the car's surroundings to the player make it simulable? (the manager broadcast camera)
--
-- Every row lands in `paddock_live` as race_id `probe-<t>-<n>` (detail_json holds the samples), so the answer can be
-- read back without the console. Console: `ncm.paddock.probe [playerId]`.
PaddockProbe = { last = nil }

local U = PaddockUtil
local log = U.logger("probe")
local L = NcmCore.get("paddock.live")
local G = NcmCore.get("paddock.garages")
local Nodes = NcmCore.get("data.nodes")
local Season = NcmCore.get("paddock.season")

local NO_DRIVER = "00000000-0000-0000-0000-000000000000"
local BANDS = { { 100, 250 }, { 250, 600 }, { 600, 1100 }, { 1100, 2200 }, { 2200, 5000 } }
local LEG_SEC = 25

-- Candidate road points: route nodes, the Paddock routes' lines, and garage sites (road-adjacent by construction).
local function candidates()
    local out = {}
    for _, n in ipairs(Nodes.LIST) do if n.road ~= false then out[#out + 1] = { x = n.x, y = n.y, z = n.z or 0, name = n.name } end end
    for _, rootId in pairs(Season.ROUTES) do
        local path = PaddockLive.pathFor(rootId)
        if path then for i = 1, #path.points, 6 do local p = path.points[i]; out[#out + 1] = { x = p.x, y = p.y, z = p.z or 0, name = "line of " .. PaddockWorld.routeName(rootId) } end end
    end
    for _, s in ipairs(G.sites()) do out[#out + 1] = { x = s.x, y = s.y, z = s.z, name = s.id } end
    return out
end

local function camera()
    return exports and exports.open77_remote_camera or nil
end

--- Run the suite for one player. Blocks for about three legs of LEG_SEC; call from a thread.
function PaddockProbe.run(pid)
    local ok, positions = pcall(Open77.players.positions)
    positions = (ok and type(positions) == "table") and positions or {}
    if not pid then for p in pairs(positions) do pid = tonumber(p) break end end
    local me = pid and positions[pid]
    if not me then return false, "no player online to probe from" end
    local t = U.now()
    local pool = candidates()
    local cars = {}
    for bi, band in ipairs(BANDS) do
        local pick, pickD
        for _, c in ipairs(pool) do
            local d = L.dist(c, me)
            if d >= band[1] and d < band[2] and (not pickD or math.abs(d - (band[1] + band[2]) / 2) < math.abs(pickD - (band[1] + band[2]) / 2)) then pick, pickD = c, d end
        end
        if pick then
            -- a destination 250-700 m from the spawn, so a moving car shows it
            local dest
            for _, c in ipairs(pool) do local d = L.dist(c, pick); if d > 250 and d < 700 then dest = c break end end
            dest = dest or { x = pick.x + 300, y = pick.y, z = pick.z }
            local okV, vid = pcall(Open77.vehicles.create, { record = "Vehicle.v_sport2_quadra_type66", position = { x = pick.x, y = pick.y, z = (pick.z or 0) + 0.8 }, yaw = 0, bucket = me.bucket or 0 })
            if okV and vid then
                local okN, npc = pcall(Open77.npcs.create, { record = "Character.WorkerMale", position = { x = pick.x, y = pick.y, z = (pick.z or 0) + 0.8 }, yaw = 0,
                    bucket = me.bucket or 0, aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or nil, despawnWhenUnobserved = false, persistent = false })
                local okA, st = pcall(Open77.vehicles.ai.attachDriver, vid, (okN and npc) and { npcId = npc } or nil)
                local okF = okA and st and pcall(Open77.vehicles.ai.driveTo, vid, { position = { x = dest.x, y = dest.y, z = dest.z or 0 }, speed = 15, behavior = "normal" })
                cars[#cars + 1] = { band = bi, d = pickD, at = pick, vid = vid, npc = okN and npc or nil, attached = okA and st and true or false,
                    drive = okF and true or false, legs = {}, samples = {} }
            else
                log("band %d: vehicle refused: %s", bi, tostring(vid))
            end
        end
    end
    if #cars == 0 then return false, "no road point in any distance band" end
    log("probe: %d car(s) from %.0f m to %.0f m away; leg A (unasked) for %d s", #cars, cars[1].d, cars[#cars].d, LEG_SEC)

    local function leg(tag)
        local start = {}
        for _, c in ipairs(cars) do start[c] = select(2, pcall(Open77.vehicles.getPosition, c.vid)) end
        local statuses = {}
        for _, c in ipairs(cars) do statuses[c] = {} end
        for i = 1, LEG_SEC do
            Wait(1000)
            for _, c in ipairs(cars) do
                local okS, s = pcall(Open77.vehicles.ai.state, c.vid)
                local status = okS and type(s) == "table" and tostring(s.status) or "?"
                statuses[c][status] = (statuses[c][status] or 0) + 1
                if i % 5 == 0 then
                    local okP, p = pcall(Open77.vehicles.getPosition, c.vid)
                    local moved = (okP and type(p) == "table" and type(start[c]) == "table") and L.dist(start[c], p) or -1
                    c.samples[#c.samples + 1] = ("%s %ds %.0fm %s"):format(tag, i, moved, status)
                end
            end
        end
        for _, c in ipairs(cars) do
            local okP, p = pcall(Open77.vehicles.getPosition, c.vid)
            local moved = (okP and type(p) == "table" and type(start[c]) == "table") and L.dist(start[c], p) or -1
            local okO, owner = pcall(Open77.vehicles.owner, c.vid)
            local st = {}
            for k, v in pairs(statuses[c]) do st[#st + 1] = k .. "x" .. v end
            c.legs[tag] = { moved = moved, statuses = table.concat(st, " "), owner = okO and owner or nil }
        end
    end

    leg("A")
    local asked = {}
    for _, c in ipairs(cars) do
        local okR, st, why = pcall(Open77.vehicles.requestAuthority, c.vid, pid)
        c.request = okR and st and "ok" or tostring(okR and (why or st) or st)
    end
    log("probe: leg B (requestAuthority to player %d) for %d s", pid, LEG_SEC)
    leg("B")
    local cam = camera()
    for _, c in ipairs(cars) do
        if cam then
            local okC, snap, why = pcall(function() return cam:create({ key = "ncm_probe:" .. t .. ":" .. c.band, bucket = me.bucket or 0,
                position = { x = c.at.x, y = c.at.y, z = (c.at.z or 0) + 12 }, rotation = { yaw = 0, pitch = -35, roll = 0 }, fov = 70, range = 150 }) end)
            if okC and type(snap) == "table" and snap.id then
                c.cam = snap.id
                pcall(function() return cam:setAccess(snap.id, pid, { view = true }) end)
                local okL, lease, whyL = pcall(function() return cam:acquire(pid, snap.id) end)
                c.lease = okL and lease or nil
                c.leaseWhy = okL and (lease and "ok" or tostring(whyL)) or tostring(lease)
            else
                c.leaseWhy = "camera refused: " .. tostring(okC and (why or snap) or snap)
            end
        else
            c.leaseWhy = "open77_remote_camera exports unavailable"
        end
        pcall(Open77.vehicles.requestAuthority, c.vid, pid)
    end
    log("probe: leg C (remote-camera interest at each car + request) for %d s", LEG_SEC)
    leg("C")

    local rows, summary = {}, {}
    for n, c in ipairs(cars) do
        local function mv(tag) local l = c.legs[tag] return l and ("%s %.0fm [%s]"):format(tag, l.moved, l.statuses) or tag .. " ?" end
        local line = ("%.0f m: attached=%s drive=%s | %s | %s (request %s) | %s (lease %s)"):format(c.d, tostring(c.attached), tostring(c.drive),
            mv("A"), mv("B"), tostring(c.request), mv("C"), tostring(c.leaseWhy))
        summary[#summary + 1] = line
        log("probe %s", line)
        rows[#rows + 1] = { query = [[INSERT INTO paddock_live (server_id, race_id, declared_by, declared_at, state, cars, reason, detail_json, ended_at)
            VALUES (?, ?, ?, ?, 'finished', 1, ?, ?, ?)]], values = { U.sid(), ("probe-%d-%d"):format(t, n), NO_DRIVER, t, line:sub(1, 160),
            U.encode({ line = line, samples = c.samples, owner = c.legs.C and c.legs.C.owner, at = c.at.name }) or "{}", U.now() } }
    end
    local okT, err = U.transact(rows)
    if not okT then log("probe rows not stored: %s", tostring(err)) end
    -- tidy up
    for _, c in ipairs(cars) do
        if cam and c.lease then pcall(function() return cam:release(c.lease) end) end
        if cam and c.cam then pcall(function() return cam:remove(c.cam) end) end
        pcall(Open77.vehicles.ai.removeDriver, c.vid)
        pcall(Open77.vehicles.remove, c.vid)
        if c.npc then pcall(Open77.npcs.remove, c.npc) end
    end
    PaddockProbe.last = { at = t, lines = summary }
    return true, table.concat(summary, " || ")
end

RegisterCommand("ncm.paddock.probe", function(source, args)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function()
        local ok, res = PaddockProbe.run(tonumber(args and args[1]))
        print("[ncm_paddock] probe " .. (ok and "done" or "FAILED") .. ": " .. tostring(res))
    end)
end, false)
