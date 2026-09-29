-- ncm_paddock / server / garages -- Paddock people at their rented garages (doc 44 §11, phase 4, L224.6).
--
-- Every org rents a garage on a shift (`paddock.garages`); both are persisted on the org row (schema 051) so a team
-- never moves because another folded. Bodies are materialised ONLY where a player is: every few seconds the loop
-- reads every player's position (`Open77.players.positions`, one call), finds garages within `garageNearM`, and
-- asks each on-shift tenant who is there (`paddock.garages.present`: senior first, drivers away around their own
-- races). A body stays while any player is within `garageLeaveM` and its person is still on shift; the global cap
-- bounds the city. Each body gets a "Talk" prompt on every client that streams it (client/presence.lua).
--
-- A talk is a request, not proof: the server re-reads the body's canonical position and the player's, and refuses
-- anything further than `talkRadiusM`. The line comes from `paddock.talk`, facts only; the meeting is recorded
-- (schema 051) so a second visit hears something new. Native dialogue replaces the notification once IDEA-727
-- passes.
PaddockGarages = { bad = {}, good = {}, bodies = {}, tenants = {} }

local U = PaddockUtil
local log = U.logger("garages")
local G = NcmCore.get("paddock.garages")
local Talk = NcmCore.get("paddock.talk")
local Hash = NcmCore.get("vocabulary.hash")
local Clock = NcmCore.get("world.clock")
local World = NcmCore.get("paddock.world")

local bodies = PaddockGarages.bodies        -- personId -> { npcId, siteId, orgId, bucket, bornAt }
local stats = { spawned = 0, removed = 0, refused = 0, talks = 0, groundMisses = 0 }
PaddockGarages.stats = stats

-- Records by role and gender. Crew wear work clothes; the office wears corpo. A body is a costume, never an
-- identity: the name on the prompt is the person.
local RECORDS = {
    crew = { m = { "Character.WorkerMale", "Character.YoungsterMale", "Character.AsianMale" },
             f = { "Character.YoungsterFemale", "Character.AsianFemale" } },
    office = { m = { "Character.CorpoMan" }, f = { "Character.CorpoWoman" } },
}
local function recordFor(p)
    local set = (p.role == "manager" or p.role == "owner" or p.role == "strategist") and RECORDS.office or RECORDS.crew
    local list = set[p.gender == "f" and "f" or "m"]
    return Hash.pick(list, "body", p.id)
end

local function world() return PaddockStore.world end
local function active(o) return o and o.lifecycle ~= "folded" end

--- Load the in-engine site checks (schema 051).
function PaddockGarages.load()
    PaddockGarages.bad, PaddockGarages.good = {}, {}
    for _, r in ipairs(MySQL.query.await("SELECT site_id, verdict FROM paddock_garage_check WHERE server_id = ?", { U.sid() }) or {}) do
        if r.verdict == "bad" then PaddockGarages.bad[r.site_id] = true else PaddockGarages.good[r.site_id] = true end
    end
end

--- Give every active org a garage and a shift; keep what it has unless its site went bad. Cheap: ~60 orgs.
function PaddockGarages.ensure()
    local w = world()
    if not w then return end
    local orgs = {}
    for _, id in ipairs(w.orgOrder) do
        local o = w.orgs[id]
        if active(o) then orgs[#orgs + 1] = { id = o.id, tier = o.tier, garageId = o.garageId } end
    end
    local a = G.assign(w.seed, orgs, PaddockGarages.bad)
    local tenants, moved = {}, 0
    for _, x in ipairs(orgs) do
        local o = w.orgs[x.id]
        local changed = false
        if a[o.id] and a[o.id] ~= o.garageId then o.garageId = a[o.id]; changed = true; moved = moved + 1 end
        if not o.shift then o.shift = G.shiftFor(w.seed, o); changed = true end
        if changed then PaddockStore.markOrg(o.id) end
        if o.garageId then
            tenants[o.garageId] = tenants[o.garageId] or {}
            table.insert(tenants[o.garageId], o.id)
        end
    end
    PaddockGarages.tenants = tenants
    if moved > 0 then log("rentals: %d org(s) housed or rehoused", moved) end
end

--- The org's garage and hours as a player may see them.
function PaddockGarages.describe(o)
    if not o or not o.garageId then return nil end
    local site = G.site(o.garageId)
    local s = o.shift
    local hours
    if s then
        local function hm(sod) sod = sod % 86400 return ("%02d:%02d"):format(math.floor(sod / 3600), math.floor(sod % 3600 / 60)) end
        hours = hm(s.from) .. "-" .. hm(s.from + s.len) .. " ET"
    end
    return { label = G.label(site), district = site and site.district, hours = hours,
        here = s and G.onShift(s, U.now()) or false, siteId = o.garageId }
end

-- Which series have a race keeping their drivers at the track right now.
local function busySeries(t)
    local out = {}
    for _, race in pairs(PaddockRaces.byId) do
        local from = race.opensAt - G.AWAY_BEFORE_SEC
        local to = (race.closesAt or (race.opensAt + 600)) + G.AWAY_AFTER_SEC
        if t >= from and t <= to and race.state ~= "void" then out[race.seriesId] = true end
    end
    return out
end

local function ground(p)
    -- From just above the pin downward first: a garage is usually under a roof, and a ray from high above lands
    -- on it. Only a miss falls back to the pin's own height.
    local ok, z = pcall(Open77.world.groundZ, { x = p.x, y = p.y }, { radius = 300, fromZ = (p.z or 0) + 1.5, timeout = 2500, cache = true })
    if ok and type(z) == "number" and math.abs(z - (p.z or 0)) < 6 then return z end
    stats.groundMisses = stats.groundMisses + 1
    return p.z
end

local function broadcast()
    local rows = {}
    local w = world()
    for pid, b in pairs(bodies) do
        local p = w and w.people[pid]
        if p and b.npcId then
            rows[#rows + 1] = { npcId = b.npcId, personId = pid, name = p.display, role = Talk.ROLE_LABEL[p.role] or p.role,
                org = PaddockWorld.orgName(b.orgId) }
        end
    end
    TriggerClientEvent("ncm:paddock.bodies", -1, { rows = rows })
end
PaddockGarages.broadcast = broadcast

local function removeBody(pid, why)
    local b = bodies[pid]
    if not b then return end
    if b.npcId then pcall(Open77.npcs.remove, b.npcId) end
    bodies[pid] = nil
    stats.removed = stats.removed + 1
    if why == "shutdown" then return end
end

local function spawnBody(p, org, site, stand, bucket)
    local z = ground(stand)
    local damage = Open77.npcs.damage and Open77.npcs.damage.invulnerable or nil
    local ok, id, reason = pcall(Open77.npcs.create, {
        record = recordFor(p), position = { x = stand.x, y = stand.y, z = (z or site.z) + 0.1 }, yaw = stand.yaw,
        bucket = bucket or 0, aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or nil, damagePolicy = damage,
        despawnWhenUnobserved = false, persistent = false,
    })
    if not ok or not id then
        stats.refused = stats.refused + 1
        log("body %s (%s) at %s refused: %s", p.id, p.role, site.id, tostring(reason or id))
        return false
    end
    bodies[p.id] = { npcId = id, siteId = site.id, orgId = org.id, bucket = bucket or 0, bornAt = U.now() }
    stats.spawned = stats.spawned + 1
    if Open77.npcs.tasks and Open77.npcs.tasks.lookAt then
        pcall(Open77.npcs.tasks.lookAt, id, { type = "position", position = { x = site.x, y = site.y, z = site.z } })
    end
    return true
end

--- One presence pass. Bounded: at most four spawns per pass, and the global cap.
function PaddockGarages.tick()
    local w = world()
    if not w or not PaddockSettings.get("garagesEnabled", true) then
        if next(bodies) then for pid in pairs(bodies) do removeBody(pid, "disabled") end broadcast() end
        return
    end
    local ok, positions = pcall(Open77.players.positions)
    if not ok or type(positions) ~= "table" then return end
    local t = U.now()
    local nearM, leaveM = PaddockSettings.get("garageNearM", 120), PaddockSettings.get("garageLeaveM", 200)
    local cap = PaddockSettings.get("garageBodyCap", 18)
    local busy = busySeries(t)
    local liveAway = PaddockLive and PaddockLive.awayPeople and PaddockLive.awayPeople() or {}
    -- who should be standing where
    local want, siteNear, siteBucket = {}, {}, {}
    for _, pos in pairs(positions) do
        for siteId, orgIds in pairs(PaddockGarages.tenants) do
            local site = G.site(siteId)
            local d = G.distance(site, pos)
            if d <= leaveM then siteNear[siteId] = true end
            if d <= nearM and not want[siteId] then
                siteBucket[siteId] = pos.bucket or 0
                local crew = {}
                for _, oid in ipairs(orgIds) do
                    local o = w.orgs[oid]
                    if active(o) and o.shift then
                        local racing = function(personId)
                            if liveAway[personId] then return true end
                            return busy[o.seriesId] == true
                        end
                        for _, p in ipairs(G.present(w.seed, o, World.members(w, o.id), t, racing)) do
                            if not (o.humanManagerDriverId and p.role == "manager") then crew[#crew + 1] = { p = p, o = o } end
                        end
                    end
                end
                while #crew > G.MAX_BODIES do table.remove(crew) end
                want[siteId] = crew
            end
        end
    end
    -- retire bodies whose person left the shift or whose garage nobody is near
    local changed = false
    for pid, b in pairs(bodies) do
        local keep = siteNear[b.siteId] == true
        if keep then
            local o = w.orgs[b.orgId]
            local p = w.people[pid]
            keep = active(o) and p and p.orgId == b.orgId and G.onShift(o.shift, t) and not liveAway[pid]
            if keep and p.role == "driver" and busy[o.seriesId] then keep = false end
        end
        if not keep then removeBody(pid, "left"); changed = true end
    end
    -- materialise
    local count = 0
    for _ in pairs(bodies) do count = count + 1 end
    local spawns = 0
    for siteId, crew in pairs(want) do
        local site = G.site(siteId)
        for i, x in ipairs(crew) do
            if count >= cap or spawns >= 4 then break end
            if not bodies[x.p.id] then
                if spawnBody(x.p, x.o, site, G.standPoint(site, i, #crew), siteBucket[siteId]) then
                    count, spawns, changed = count + 1, spawns + 1, true
                end
            end
        end
    end
    if changed then broadcast() end
end

--- Mark a site good or bad from play (the in-engine look a map pin needs). A bad site's tenants move now.
function PaddockGarages.check(siteId, verdict, note)
    if not G.site(siteId) or (verdict ~= "good" and verdict ~= "bad") then return false, "unknown site or verdict" end
    local ok = pcall(MySQL.update.await, [[INSERT INTO paddock_garage_check (server_id, site_id, verdict, note, at) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE verdict = VALUES(verdict), note = VALUES(note), at = VALUES(at)]],
        { U.sid(), siteId, verdict, tostring(note or ""), U.now() })
    if not ok then return false, "database" end
    PaddockGarages.bad[siteId] = verdict == "bad" or nil
    PaddockGarages.good[siteId] = verdict == "good" or nil
    if verdict == "bad" then
        for pid, b in pairs(bodies) do if b.siteId == siteId then removeBody(pid, "bad_site") end end
        broadcast()
        PaddockGarages.ensure()
    end
    return true
end

--- The nearest site to a position (admin and the player's own "which garage is this").
function PaddockGarages.nearest(pos)
    local best, bestD
    for _, s in ipairs(G.sites()) do
        local d = G.distance(s, pos)
        if not bestD or d < bestD then best, bestD = s, d end
    end
    return best, bestD
end

-- ------------------------------------------------------------------------------------------------------------ talk

local lastTalk = {}

local function nextRaceFor(o, t)
    local best
    for _, race in pairs(PaddockRaces.byId) do
        if race.seriesId == o.seriesId and race.opensAt > t and race.opensAt < t + 12 * 3600 and race.state ~= "void" then
            if not best or race.opensAt < best.opensAt then best = race end
        end
    end
    if not best then return nil end
    local cond = PaddockWorld.conditionsAt(best.opensAt)
    return { route = PaddockWorld.routeName(best.routeId), when = Clock.hhmm(best.opensAt), weather = cond and cond.weather }
end

local function lastResultFor(o)
    local r = MySQL.single.await([[SELECT x.person_id, x.position, x.state, r.route_id FROM paddock_result x
        JOIN paddock_race r ON r.server_id = x.server_id AND r.race_id = x.race_id
        WHERE x.server_id = ? AND x.org_id = ? AND r.state = 'resolved' ORDER BY x.at DESC, x.position LIMIT 1]], { U.sid(), o.id })
    if not r then return nil end
    return { driver = PaddockWorld.personName(r.person_id), position = tonumber(r.position), state = r.state,
        route = PaddockWorld.routeName(r.route_id) }
end

--- A player asked to talk to a Paddock person standing at their garage.
function PaddockGarages.talk(pid, personId)
    local b = bodies[personId or ""]
    local w = world()
    if not b or not w then return false, "not_here" end
    local p, o = w.people[personId], w.orgs[b.orgId]
    if not p or not o then return false, "not_here" end
    local okP, positions = pcall(Open77.players.positions)
    local me = okP and type(positions) == "table" and positions[pid] or nil
    local okN, npc = pcall(Open77.npcs.get, b.npcId)
    local at = okN and type(npc) == "table" and npc.position or nil
    if not me or not at then return false, "position_unknown" end
    local dx, dy = (me.x or 0) - (at.x or 0), (me.y or 0) - (at.y or 0)
    if math.sqrt(dx * dx + dy * dy) > PaddockSettings.get("talkRadiusM", 6) then return false, "too_far" end
    local d = PaddockPlayers.driver(pid)
    if not d then return false, "no_driver" end
    local t = U.now()
    local met = tonumber(MySQL.scalar.await("SELECT met_count FROM paddock_meeting WHERE server_id = ? AND ncm_driver_id = ? AND person_id = ?",
        { U.sid(), d.ncmDriverId, p.id })) or 0
    local tags, tagSubject = {}, nil
    if p.role == "driver" then tags, tagSubject = PaddockViews.driverTags(p), p.display
    else tags, tagSubject = PaddockViews.orgTags(o), o.name end
    local ctx = { person = p, org = o, seriesName = PaddockWorld.seriesName(o.seriesId), next = nextRaceFor(o, t),
        last = lastResultFor(o), tags = tags, tagSubject = tagSubject }
    local line = Talk.line(ctx, Clock.eastern(t).dayIndex, met)
    pcall(MySQL.update.await, [[INSERT INTO paddock_meeting (server_id, ncm_driver_id, person_id, first_at, last_at, met_count)
        VALUES (?, ?, ?, ?, ?, 1) ON DUPLICATE KEY UPDATE last_at = VALUES(last_at), met_count = met_count + 1]],
        { U.sid(), d.ncmDriverId, p.id, t, t })
    stats.talks = stats.talks + 1
    pcall(Open77.npcs.speak, b.npcId, "greeting", {})
    local title = ("%s · %s, %s"):format(p.display, Talk.ROLE_LABEL[p.role] or p.role, o.name)
    pcall(Open77.notifications.send, pid, { type = "info", title = title, message = line.text, icon = "NCM", durationMs = 9000 })
    return true, line
end

RegisterNetEvent("ncm:paddock.talk", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(req) ~= "table" then return end
    local nowMs = (Open77.time.unix() or 0) * 1000
    if lastTalk[pid] and nowMs - lastTalk[pid] < 1500 then return end
    lastTalk[pid] = nowMs
    CreateThread(function()
        local ok, why = PaddockGarages.talk(pid, tostring(req.personId or ""))
        if not ok and why == "too_far" then
            pcall(Open77.notifications.send, pid, { type = "info", title = "THE PADDOCK", message = "Get closer.", icon = "NCM", durationMs = 2500 })
        end
    end)
end)

-- A client that joins late asks for the current bodies instead of waiting for the next change.
RegisterNetEvent("ncm:paddock.bodies.request", function()
    local pid = tonumber(source) or 0
    if pid <= 0 then return end
    local rows = {}
    local w = world()
    for personId, b in pairs(bodies) do
        local p = w and w.people[personId]
        if p then rows[#rows + 1] = { npcId = b.npcId, personId = personId, name = p.display,
            role = Talk.ROLE_LABEL[p.role] or p.role, org = PaddockWorld.orgName(b.orgId) } end
    end
    TriggerClientEvent("ncm:paddock.bodies", pid, { rows = rows })
end)

AddEventHandler("onPlayerDisconnected", function(playerId) lastTalk[tonumber(playerId) or 0] = nil end)

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    for pid in pairs(bodies) do removeBody(pid, "shutdown") end
end)

--- Start the presence loop (main.lua, after boot).
function PaddockGarages.start()
    PaddockGarages.load()
    PaddockGarages.ensure()
    CreateThread(function()
        local lastEnsure = U.now()
        while true do
            Wait(PaddockSettings.get("garageTickSeconds", 6) * 1000)
            if PaddockSettings.get("paddockEnabled", true) then
                local okT, err = pcall(PaddockGarages.tick)
                if not okT then log("tick FAILED: %s", tostring(err)) end
                if U.now() - lastEnsure >= 300 then
                    lastEnsure = U.now()
                    local okE, errE = pcall(PaddockGarages.ensure)
                    if not okE then log("ensure FAILED: %s", tostring(errE)) end
                end
            end
        end
    end)
end
