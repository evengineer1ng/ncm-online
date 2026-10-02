-- ncm_paddock / server / scan -- the Scanner reads a Paddock person (L240; owner 2026-09-30: "this should be a
-- scanner / vision surface 100%").
--
-- `ncm_scanner` sends the world point its reticle sits on when the target is not a vehicle (`ncm-vision` reports
-- every non-vehicle as kind "other" with its position). The server is the only authority: it matches the point to
-- a body it placed itself (within MATCH_M of that body's canonical position, with the scanning player within
-- RANGE_M), and answers from the person's day plan and their district's climate. A point that is no Paddock
-- person gets `found = false`, and the reticle stays quiet over vanilla crowds.
--
-- What goes on the wire is what a scanner in Night City would plausibly read: name, role, team, what they are doing
-- and where, until when, where they are usually found, the district's reading. Never needs, personality or any
-- hidden stat (`paddock.attributes` HIDDEN), and never the player's own trajectory.
local U = PaddockUtil
local log = U.logger("scan")
local Places = NcmCore.get("world.places")
local Sched = NcmCore.get("life.schedule")
local Climate = NcmCore.get("life.climate")
local G = NcmCore.get("paddock.garages")
local Talk = NcmCore.get("paddock.talk")
local Clock = NcmCore.get("world.clock")

local MATCH_M, RANGE_M, GAP_MS = 3.0, 80.0, 200
local last = {}
local stats = { asked = 0, found = 0 }
PaddockScan = { stats = stats }

local DOING = {
    eat = "EATING", loiter = "HANGING AROUND", hang = "AT THE MEET", errand = "RUNNING AN ERRAND",
    hustle = "WORKING AN ANGLE", fuel = "FUEL STOP", work = "ON SHIFT", cruise = "DRIVING", race = "RACING",
}

local function dist(a, b)
    local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function placeName(place)
    if not place then return nil end
    if place.name then return place.name:upper() end
    return Places.label(place):gsub("^an? ", ""):upper()
end

local function reply(pid, r) TriggerClientEvent("ncm:life.scan.result", pid, r) end

RegisterNetEvent("ncm:life.scan", function(req)
    local pid = tonumber(source) or 0
    if pid <= 0 or type(req) ~= "table" or type(req.pos) ~= "table" then return end
    local nowMs = (Open77.time.unix() or 0) * 1000
    if last[pid] and nowMs - last[pid] < GAP_MS then return end
    last[pid] = nowMs
    stats.asked = stats.asked + 1
    local tokenId = tostring(req.token or "")
    local w = PaddockStore.world
    local okP, positions = pcall(Open77.players.positions)
    local me = okP and type(positions) == "table" and positions[pid] or nil
    if not w or not me then return reply(pid, { token = tokenId, found = false }) end
    local at = { x = tonumber(req.pos.x) or 0, y = tonumber(req.pos.y) or 0, z = tonumber(req.pos.z) or 0 }
    local best, bestD, bestPid
    for personId, b in pairs(PaddockGarages.bodies) do
        local pos = U.npcPos(b.npcId)
        if pos then
            local d = dist(pos, at)
            if d <= MATCH_M and dist(pos, me) <= RANGE_M and (not bestD or d < bestD) then best, bestD, bestPid = b, d, personId end
        end
    end
    if not best then return reply(pid, { token = tokenId, found = false }) end
    local p, o = w.people[bestPid], w.orgs[best.orgId or ""]
    if not p then return reply(pid, { token = tokenId, found = false }) end
    stats.found = stats.found + 1
    local t = U.now()
    local r = { token = tokenId, found = true, name = p.display, role = (Talk.ROLE_LABEL[p.role] or p.role or ""):upper(),
        team = o and o.name and o.name:upper() or nil }
    local place = Places.get(best.siteId) or G.site(best.siteId)
    local plan = PaddockDays and PaddockDays.planFor and (function()
        local ok, pl = pcall(PaddockDays.planFor, p, Sched.planDay(t))
        return ok and pl or nil
    end)()
    local run = plan and Sched.at(plan, t)
    if best.source ~= "day" then
        r.doing, r.till = "ON SHIFT", nil
    else
        r.doing = DOING[best.activity or (run and run.activity) or ""] or "HERE"
        if run then r.till = Clock.hhmm(run.toUtc) end
    end
    r.at = placeName(place)
    if plan then
        for _, u in ipairs(Sched.usually({ plan })) do
            if u.placeId ~= best.siteId then r.usually = placeName(Places.get(u.placeId)); break end
        end
    end
    local climate = PaddockDays and PaddockDays.climate and PaddockDays.climate()
    local reading = place and climate and Climate.reading(climate, place.district)
    if reading then r.district = (place.district .. " · " .. reading.label):upper() end
    log("player %d scanned %s (%s, %s) at %s", pid, p.id, p.display or "?", r.doing or "?", tostring(best.siteId))
    reply(pid, r)
end)

AddEventHandler("onPlayerDisconnected", function(playerId) last[tonumber(playerId) or 0] = nil end)
