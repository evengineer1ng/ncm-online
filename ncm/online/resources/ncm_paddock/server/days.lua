-- ncm_paddock / server / days -- Paddock people have days, districts have a climate, players have a trajectory
-- (L237 M1, L240).
--
-- CLIMATE. One `life.climate` state for the city (schema 053). Sim facts are tallied per district as they happen --
-- a Paddock race resolved on a route in Heywood, a team folding at its Watson garage, a player talking to someone --
-- and at each Eastern day change the climate steps once with them (idempotent by day; after downtime it catches up
-- day by day, the tally landing on the latest day). A regime change is logged and kept in `paddock_climate_event`.
--
-- DAYS. A person's day is `life.schedule.plan`: pure, so it is computed only for people a player could meet --
-- those whose home or work district holds a place a player is near -- at most PLAN_BUDGET new plans per pass, and
-- cached for the plan day. Commitments are real: their org's garage shift (`paddock.garages.onShift`) and, for a
-- seated driver, the window around their own series' races.
--
-- BODIES. Off-shift people whose plan puts them at a place within `lifeNearM` of a player get a body there, in the
-- garages' own `bodies` table (tagged `source = "day"`) and under the same global cap, so Talk, the client prompt
-- and the broadcast all work unchanged. Garage presence stays with `garages.lua`; a `work` run is never duplicated.
--
-- TRAJECTORY. Server-corroborated player facts (a talk, a night at a street meet) feed `life.trajectory`. The profile
-- is persisted and never sent to any client. Other resources feed it through the `lifeRecord` export.
PaddockDays = { stats = { plans = 0, spawned = 0, removed = 0, refused = 0, transitions = 0, recorded = 0 } }

local U = PaddockUtil
local log = U.logger("days")
local Places = NcmCore.get("world.places")
local Sched = NcmCore.get("life.schedule")
local Climate = NcmCore.get("life.climate")
local Traj = NcmCore.get("life.trajectory")
local G = NcmCore.get("paddock.garages")
local Clock = NcmCore.get("world.clock")
local Hash = NcmCore.get("vocabulary.hash")
local World = NcmCore.get("paddock.world")

local stats = PaddockDays.stats
local bodies = PaddockGarages.bodies
local PLAN_BUDGET = 40          -- new plans per pass, each in its own quota slice (8 took ~3 min over Heywood's 208, live 2026-09-30)
local MAX_PER_PLACE = 4
local GARAGE_KINDS = { garage = true, workshop = true, parking = true }
local BODY_KINDS = {}
for k in pairs(Places.KINDS) do if not GARAGE_KINDS[k] then BODY_KINDS[k] = true end end

local climate                 -- the live life.climate state
local facts = {}              -- district -> kind -> count, since the last step
local factsDirty = false
local bad = {}                -- place id -> true
local plans = {}              -- personId -> plan (current plan day only)
local planDay
local index                   -- district -> { personId, ... } for the plan day
local regularCount = {}       -- place id -> how many people count it a regular (the planner's turns at crowded places)
local indexDay
local profiles = {}           -- ncmDriverId -> trajectory profile (cache)
local lastReport = 0          -- the hop-by-hop pass report, at most every REPORT_S (first live run, 2026-09-30)
local REPORT_S = 30
local meetSeen = {}           -- "player:place:day" -> true

local function world() return PaddockStore.world end
local function active(o) return o and o.lifecycle ~= "folded" end

-- ------------------------------------------------------------------------------------------------------ climate

local function saveClimate()
    if not climate then return end
    local okS, stateJson = pcall(U.encode, climate)
    local okF, factsJson = pcall(U.encode, facts)
    if not okS or not stateJson or not okF or not factsJson then log("climate encode FAILED") return end
    local ok, err = pcall(MySQL.update.await, [[INSERT INTO paddock_climate (server_id, day_index, season_id, state_json, facts_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE day_index = VALUES(day_index), season_id = VALUES(season_id),
        state_json = VALUES(state_json), facts_json = VALUES(facts_json), updated_at = VALUES(updated_at)]],
        { U.sid(), climate.day or 0, climate.seasonId or "", stateJson, factsJson, U.now() })
    if not ok then log("climate save FAILED: %s", tostring(err)) else factsDirty = false end
end

function PaddockDays.loadClimate()
    local w = world()
    if not w then return end
    local row = MySQL.single.await("SELECT state_json, facts_json FROM paddock_climate WHERE server_id = ?", { U.sid() })
    if row then
        climate = U.decode(row.state_json)
        facts = U.decode(row.facts_json) or {}
    end
    if type(climate) ~= "table" or type(climate.districts) ~= "table" then
        local today = Clock.eastern(U.now()).dayIndex
        climate = Climate.genesis(w.seed, w.seasonId or "", today - 1)
        facts = {}
        log("climate genesis: season %s, city climate %s", tostring(w.seasonId), tostring(climate.city))
        saveClimate()
    end
    for _, d in ipairs(Places.DISTRICTS) do
        local r = Climate.reading(climate, d)
        if r then log("  %-13s %s", d, r.label) end
    end
end

--- Tally one sim fact against a district. Cheap; persisted with the climate every few minutes and at the step.
function PaddockDays.fact(district, kind, n)
    if type(district) ~= "string" or not Climate.IMPULSE[kind] then return end
    facts[district] = facts[district] or {}
    facts[district][kind] = (facts[district][kind] or 0) + (n or 1)
    factsDirty = true
end

--- The district a Paddock race counts against: its route's start region.
function PaddockDays.raceDistrict(race)
    local r = race and PaddockWorld.route(race.routeId)
    return r and r.region or nil
end

--- The district an org lives in: its rented garage's.
function PaddockDays.orgDistrict(org)
    local site = org and org.garageId and Places.get(org.garageId)
    return site and site.district or nil
end

--- The daily step (main tick). Idempotent: steps only days after the climate's own.
function PaddockDays.daily(t)
    local w = world()
    if not climate or not w then return false end
    local today = Clock.eastern(t).dayIndex
    if (climate.day or 0) >= today then return false end
    if w.seasonId and climate.seasonId ~= w.seasonId then Climate.newSeason(climate, w.seed, w.seasonId) end
    local from = math.max(climate.day + 1, today - 30)          -- a month is the most any downtime catches up
    local all = {}
    for d = from, today do
        local _, tr = Climate.step(climate, w.seed, d, d == today and facts or {})   -- the tally is the latest day's
        for _, x in ipairs(tr) do all[#all + 1] = x end
        Wait(0)
    end
    facts = {}
    for _, x in ipairs(all) do
        stats.transitions = stats.transitions + 1
        local from_, to_ = Climate.regime(x.from), Climate.regime(x.to)
        log("CLIMATE %s: %s -> %s (day %d)%s", x.district, from_ and from_.label or x.from, to_ and to_.label or x.to,
            x.day, x.scar and (" [scar: " .. x.scar .. "]") or "")
        pcall(MySQL.update.await, [[INSERT IGNORE INTO paddock_climate_event (server_id, day_index, district, from_regime,
            to_regime, axes_json, causes_json, scar, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            { U.sid(), x.day, x.district, x.from, x.to, U.encode(x.axes) or "{}", U.encode(x.causes or {}) or "[]",
                x.scar or "", t })
    end
    saveClimate()
    log("climate stepped to day %d (%d transition(s))", today, #all)
    return true
end

function PaddockDays.climate() return climate end

-- ------------------------------------------------------------------------------------------------------ plans

local function orgRaces(o, dayIndex)
    local out = {}
    local lo = Clock.utcAt(dayIndex, Sched.DAY_START) - 3600
    local hi = lo + 26 * 3600
    for _, race in pairs(PaddockRaces.byId or {}) do
        if race.seriesId == o.seriesId and race.opensAt and race.opensAt >= lo and race.opensAt <= hi and race.state ~= "void" then
            out[#out + 1] = race.opensAt
        end
    end
    return out
end

local function ctxFor(p, dayIndex)
    local w = world()
    local o = p.orgId and w.orgs[p.orgId]
    if not active(o) then return nil end
    local site = o.garageId and Places.get(o.garageId)
    local races = (p.role == "driver" and p.seat and p.seat:match("^race")) and orgRaces(o, dayIndex) or {}
    return {
        seed = w.seed, person = p, tier = o.tier, workDistrict = site and site.district, workPlaceId = o.garageId,
        climate = climate, bad = bad, yield = function() Wait(0) end, regularCount = regularCount,
        commitment = function(utc)
            for _, at in ipairs(races) do
                if utc >= at - G.AWAY_BEFORE_SEC and utc < at + G.AWAY_AFTER_SEC then return "race" end
            end
            if o.shift and G.onShift(o.shift, utc) then return "work" end
            return nil
        end,
    }
end

local function planFor(p, dayIndex)
    if planDay ~= dayIndex then plans, planDay = {}, dayIndex end
    local plan = plans[p.id]
    if plan then return plan end
    local ctx = ctxFor(p, dayIndex)
    if not ctx then return nil end
    plan = Sched.plan(ctx, dayIndex)
    plans[p.id] = plan
    stats.plans = stats.plans + 1
    return plan
end
PaddockDays.planFor = planFor

--- district -> people who live or work there, for the plan day. Built once a day, yielding as it goes.
local function buildIndex(dayIndex)
    local w = world()
    local idx, counts = {}, {}
    local y = U.yielder(1)            -- regulars hash every place in two districts (~70k instructions): one person per slice
    for _, pid in ipairs(w.personOrder) do
        local p = w.people[pid]
        local o = p.state == "active" and p.orgId and w.orgs[p.orgId]
        if active(o) and not (o.humanManagerDriverId and p.role == "manager") then
            local site = o.garageId and Places.get(o.garageId)
            local work = site and site.district
            local home = Sched.homeDistrict(w.seed, p, o.tier, work)
            for _, list in pairs(Sched.regulars(w.seed, p, home, work, bad)) do
                for _, pl in ipairs(list) do counts[pl.id] = (counts[pl.id] or 0) + 1 end
            end
            for _, d in ipairs({ home, work }) do
                if d then
                    idx[d] = idx[d] or {}
                    local list = idx[d]
                    if list[#list] ~= pid then list[#list + 1] = pid end
                end
            end
        end
        y()
    end
    index, indexDay = idx, dayIndex
    regularCount = counts
    plans = {}                        -- plans made before the counts existed would ignore the turns
end

-- ------------------------------------------------------------------------------------------------------ bodies

local RECORDS = { m = { "Character.WorkerMale", "Character.YoungsterMale", "Character.AsianMale" },
    f = { "Character.YoungsterFemale", "Character.AsianFemale" } }

-- Returns the z to stand on and how it was found ("ray" or "pin:<why>"), for the body log line below.
local function ground(p)
    local ok, z = pcall(Open77.world.groundZ, { x = p.x, y = p.y }, { radius = 300, fromZ = (p.z or 0) + 1.5, timeout = 2500, cache = true })
    if ok and type(z) == "number" and math.abs(z - (p.z or 0)) < 6 then return z, "ray" end
    return p.z, ok and (type(z) == "number" and ("pin:ray_at_%.1f"):format(z) or "pin:no_ground") or ("pin:" .. tostring(z))
end

--- Where a body stands. A fuel station's pin IS a pump, and the garages' 2.5-4 m ring stood people on it (owner,
--- 2026-09-30: "standing there awkwardly right at pump"), so forecourts use a wider ring; everywhere else the ring.
local function standFor(place, i, n)
    if place.kind ~= "fuel" then return G.standPoint(place, i, n) end
    local a = (i - 1) / math.max(1, n) * 2 * math.pi + 0.6
    local r = 7 + (i % 2) * 1.5
    return { x = place.x + math.cos(a) * r, y = place.y + math.sin(a) * r, z = place.z, yaw = (math.deg(a) + 180) % 360 }
end

local function removeBody(pid)
    local b = bodies[pid]
    if not b or b.source ~= "day" then return end
    if b.npcId then pcall(Open77.npcs.remove, b.npcId) end
    bodies[pid] = nil
    stats.removed = stats.removed + 1
end

local function spawnBody(p, place, run, stand, bucket, near)
    local z, how = ground(stand)
    local damage = Open77.npcs.damage and Open77.npcs.damage.invulnerable or nil
    local rec = Hash.pick(RECORDS[p.gender == "f" and "f" or "m"], "body", p.id)
    local ok, id, reason = pcall(Open77.npcs.create, {
        record = rec, position = { x = stand.x, y = stand.y, z = (z or place.z) + 0.1 }, yaw = stand.yaw,
        bucket = bucket or 0, aiMode = Open77.npcs.ai and Open77.npcs.ai.tasks or nil, damagePolicy = damage,
        despawnWhenUnobserved = false, persistent = false,
    })
    if not ok or not id then
        stats.refused = stats.refused + 1
        log("body %s at %s refused: %s", p.id, place.id, tostring(reason or id))
        return false
    end
    bodies[p.id] = { npcId = id, siteId = place.id, orgId = p.orgId, bucket = bucket or 0, bornAt = U.now(),
        source = "day", activity = run.activity, placeLabel = Places.label(place),
        x = stand.x, y = stand.y, z = (z or place.z) + 0.1 }
    stats.spawned = stats.spawned + 1
    log("body %s %s (%s) at %s %s npc=%s stand=%.1f,%.1f,%.1f ground=%s player=%s bucket=%s", p.id, p.display or "?",
        run.activity, place.id, Places.label(place), tostring(id), stand.x, stand.y, (z or place.z) + 0.1, how,
        near and ("%.1f,%.1f,%.1f"):format(near.x or 0, near.y or 0, near.z or 0) or "?", tostring(bucket or 0))
    -- Where the engine actually has it a moment later: the one fact that says "under the floor" or "on the roof".
    local npcId = id
    CreateThread(function()
        Wait(3000)
        local at = U.npcPos(npcId)
        log("body %s npc=%s after 3 s: %s", p.id, tostring(npcId),
            at and ("%.1f,%.1f,%.1f bucket=%s"):format(at.x, at.y, at.z, tostring(at.bucket)) or "unknown")
    end)
    return true
end

local function recordMeets(positions, t)
    local day = Clock.eastern(t).dayIndex
    for pid, pos in pairs(positions) do
        for _, place in ipairs(Places.near(pos, 40, { meet = true }, bad)) do
            if Places.isOpen(place, t) then
                local key = pid .. ":" .. place.id .. ":" .. day
                if not meetSeen[key] then
                    meetSeen[key] = true
                    local d = PaddockPlayers.driver(pid)
                    if d then PaddockDays.record(d.ncmDriverId, { id = "meet:" .. place.id .. ":" .. day, kind = "meet_visit",
                        district = place.district, day = day }) end
                end
            end
        end
    end
end

--- One presence pass: plan whom a player could meet, then materialise them. Bounded per pass.
function PaddockDays.tick()
    local w = world()
    if not w or not climate then return end
    local enabled = PaddockSettings.get("lifeEnabled", true) and PaddockSettings.get("garagesEnabled", true)
    local ok, positions = pcall(Open77.players.positions)
    if not enabled or not ok or type(positions) ~= "table" then
        local changed = false
        for pid, b in pairs(bodies) do if b.source == "day" then removeBody(pid); changed = true end end
        if changed then PaddockGarages.broadcast() end
        return
    end
    local t = U.now()
    local day = Sched.planDay(t)
    if indexDay ~= day then buildIndex(day) end
    pcall(recordMeets, positions, t)

    local nearM, leaveM = PaddockSettings.get("lifeNearM", 120), PaddockSettings.get("lifeLeaveM", 200)
    local cap = PaddockSettings.get("garageBodyCap", 18)
    -- places players are near, and the districts whose people could be there
    local nearPlace, placeDist, placeBucket, keepPlace, districts, placePlayer = {}, {}, {}, {}, {}, {}
    for _, pos in pairs(positions) do
        for _, place in ipairs(Places.near(pos, leaveM, BODY_KINDS, bad)) do
            keepPlace[place.id] = true
            local d = Places.distance(place, pos)
            if d <= nearM and (not placeDist[place.id] or d < placeDist[place.id]) then
                nearPlace[place.id], placeDist[place.id], placeBucket[place.id], placePlayer[place.id] = place, d, pos.bucket or 0, pos
                districts[place.district] = true
            end
        end
    end
    -- plan the candidates (bounded) and see who is at a near place right now
    local want, budget = {}, PLAN_BUDGET
    local dnames = {}
    for d in pairs(districts) do dnames[#dnames + 1] = d end
    table.sort(dnames)
    for _, d in ipairs(dnames) do
        for _, pid in ipairs(index[d] or {}) do
            local p = w.people[pid]
            if p and (plans[pid] or budget > 0) then
                local fresh = not plans[pid]
                local plan = planFor(p, day)
                if fresh then budget = budget - 1; Wait(0) end       -- each new plan gets its own quota slice (KB-211)
                local place, run = Sched.bodyAt(plan, t)
                if place and run.activity ~= "work" and nearPlace[place.id] then
                    want[place.id] = want[place.id] or {}
                    table.insert(want[place.id], { p = p, run = run })
                end
            end
        end
    end
    -- retire day bodies whose person moved on, or whose place nobody is near
    local changed = false
    for pid, b in pairs(bodies) do
        if b.source == "day" then
            local p = w.people[pid]
            local plan = p and plans[pid]
            local place = plan and Sched.bodyAt(plan, t)
            if not keepPlace[b.siteId] or not place or place.id ~= b.siteId then removeBody(pid); changed = true end
        end
    end
    -- materialise, nearest place first
    local count = 0
    for _ in pairs(bodies) do count = count + 1 end
    local order = {}
    for id in pairs(want) do order[#order + 1] = id end
    table.sort(order, function(a, b)
        if placeDist[a] ~= placeDist[b] then return placeDist[a] < placeDist[b] end
        return a < b
    end)
    local spawns = 0
    local refusedBefore = stats.refused
    for _, id in ipairs(order) do
        local list = want[id]
        table.sort(list, function(a, b) return a.p.id < b.p.id end)
        local place = nearPlace[id]
        for i, x in ipairs(list) do
            if i > MAX_PER_PLACE or count >= cap or spawns >= 4 then break end
            if not bodies[x.p.id] then
                if spawnBody(x.p, place, x.run, standFor(place, i, math.min(#list, MAX_PER_PLACE)), placeBucket[id], placePlayer[id]) then
                    count, spawns, changed = count + 1, spawns + 1, true
                end
            end
        end
    end
    if changed then PaddockGarages.broadcast() end
    -- Every hop of this pass, while anyone is near a place: players, places, districts, candidates, plans, who is
    -- wanted where, bodies, spawns, refusals. A silent pass is the failure this line exists for.
    if next(nearPlace) and t - lastReport >= REPORT_S then
        lastReport = t
        local np, nd, nw, cand, planned, dayBodies = {}, {}, {}, 0, 0, 0
        for id, place in pairs(nearPlace) do np[#np + 1] = ("%s@%.0fm"):format(id, placeDist[id] or -1) end
        for _, d in ipairs(dnames) do nd[#nd + 1] = d .. ":" .. #(index[d] or {}); cand = cand + #(index[d] or {}) end
        for id, list in pairs(want) do nw[#nw + 1] = id .. "=" .. #list end
        for _ in pairs(plans) do planned = planned + 1 end
        for _, b in pairs(bodies) do if b.source == "day" then dayBodies = dayBodies + 1 end end
        table.sort(np); table.sort(nw)
        log("pass: players=%d near=[%s] districts=[%s] candidates=%d plans=%d/%d wanted=[%s] dayBodies=%d spawns=%d refused=%d cap=%d",
            (function() local n = 0 for _ in pairs(positions) do n = n + 1 end return n end)(), table.concat(np, ","),
            table.concat(nd, ","), cand, planned, cand, table.concat(nw, ","), dayBodies, spawns,
            stats.refused - refusedBefore, cap)
    end
end

-- ------------------------------------------------------------------------------------------------------ trajectory

local function loadProfile(ncmDriverId)
    if profiles[ncmDriverId] then return profiles[ncmDriverId] end
    local row = MySQL.single.await("SELECT profile_json FROM paddock_trajectory WHERE server_id = ? AND ncm_driver_id = ?",
        { U.sid(), ncmDriverId })
    local p = row and U.decode(row.profile_json)
    if type(p) ~= "table" or type(p.raw) ~= "table" then p = Traj.new() end
    p.seen = p.seen or {}
    p.seenOrder = p.seenOrder or {}
    profiles[ncmDriverId] = p
    return p
end

--- Record a server-corroborated fact about a Driver. Never echoed to any client.
function PaddockDays.record(ncmDriverId, fact)
    local w = world()
    if not w or type(ncmDriverId) ~= "string" or ncmDriverId == "" or type(fact) ~= "table" or not fact.id then return end
    local p = loadProfile(ncmDriverId)
    local _, change = Traj.record(p, w.seed, ncmDriverId, fact)
    stats.recorded = stats.recorded + 1
    if change then log("trajectory %s: %s -> %s", ncmDriverId, change.from, change.to) end
    pcall(MySQL.update.await, [[INSERT INTO paddock_trajectory (server_id, ncm_driver_id, bucket, profile_json, updated_at)
        VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE bucket = VALUES(bucket), profile_json = VALUES(profile_json),
        updated_at = VALUES(updated_at)]], { U.sid(), ncmDriverId, p.bucket or "unknown", U.encode(p) or "{}", U.now() })
end

-- Guarded: the only exports precedent in this tree is client-side, and a missing global must not stop the resource.
local okX, errX = pcall(function()
    exports("lifeRecord", function(ncmDriverId, fact) PaddockDays.record(ncmDriverId, fact) end)
    exports("lifeFact", function(district, kind, n) PaddockDays.fact(district, kind, n) end)
end)
if not okX then log("exports unavailable (%s): other resources cannot feed the life sim yet", tostring(errX)) end
-- The same feed as a server event, for resources that must not depend on ncm_paddock (ncm_world's speed limits, L301).
AddEventHandler("ncm:life:record", function(ncmDriverId, fact) pcall(PaddockDays.record, ncmDriverId, fact) end)

--- A talk happened (garages.lua): the player's trajectory and the district's cohesion both hear of it.
function PaddockDays.onTalk(ncmDriverId, body, personId, t)
    local place = body and Places.get(body.siteId)
    local district = place and place.district
    if district then PaddockDays.fact(district, "player_talk", 1) end
    local day = Clock.eastern(t).dayIndex
    PaddockDays.record(ncmDriverId, { id = "talk:" .. personId .. ":" .. day, kind = "talk", district = district, day = day })
end

--- The profile and band for the console. Server-side only.
function PaddockDays.profile(ncmDriverId)
    local p = loadProfile(ncmDriverId)
    return p, Traj.band(p, climate)
end

-- ------------------------------------------------------------------------------------------------------ checks

function PaddockDays.loadChecks()
    bad = {}
    for _, r in ipairs(MySQL.query.await("SELECT place_id, verdict FROM paddock_place_check WHERE server_id = ?", { U.sid() }) or {}) do
        if r.verdict == "bad" then bad[r.place_id] = true end
    end
    for id in pairs(PaddockGarages.bad or {}) do bad[id] = true end
    plans, planDay = {}, nil
end

function PaddockDays.check(placeId, verdict, note)
    if not Places.get(placeId) or (verdict ~= "good" and verdict ~= "bad") then return false, "unknown place or verdict" end
    local ok = pcall(MySQL.update.await, [[INSERT INTO paddock_place_check (server_id, place_id, verdict, note, at) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE verdict = VALUES(verdict), note = VALUES(note), at = VALUES(at)]],
        { U.sid(), placeId, verdict, tostring(note or ""), U.now() })
    if not ok then return false, "database" end
    PaddockDays.loadChecks()
    return true
end

function PaddockDays.isBad(placeId) return bad[placeId] == true end

-- ------------------------------------------------------------------------------------------------------ start

function PaddockDays.start()
    PaddockDays.loadClimate()
    Wait(0)
    PaddockDays.loadChecks()
    Wait(0)
    CreateThread(function()
        local lastSave = U.now()
        while true do
            Wait(PaddockSettings.get("lifeTickSeconds", 7) * 1000)
            if PaddockSettings.get("paddockEnabled", true) then
                local okT, err = pcall(PaddockDays.tick)
                if not okT then log("tick FAILED: %s", tostring(err)) end
                if factsDirty and U.now() - lastSave >= 300 then lastSave = U.now(); saveClimate() end
            end
        end
    end)
    log("life sim up: %d places, climate day %d, city climate %s", #Places.all(), climate and climate.day or -1,
        climate and tostring(climate.city) or "none")
end

AddEventHandler("onResourceStop", function(name)
    if name ~= "ncm_paddock" then return end
    if factsDirty then saveClimate() end
    for pid, b in pairs(bodies) do if b.source == "day" then removeBody(pid) end end
end)
