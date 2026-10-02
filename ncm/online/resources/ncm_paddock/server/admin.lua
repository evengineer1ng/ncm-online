-- ncm_paddock / server / admin -- console commands for the operator (server console only: source 0).
--
--   ncm.paddock.status               world, clock, next races, calibration
--   ncm.paddock.resolve [raceId]     run and resolve the next (or named) race now, for testing
--   ncm.paddock.offer <driverId> <orgId>   an NPC owner offers a human the manager's job
--   ncm.paddock.calibrate            recompute calibration now
--   ncm.paddock.garage, ncm.paddock.live   phases 4-5, see the bottom of this file
PaddockAdmin = {}

local U = PaddockUtil
local Clock = NcmCore.get("world.clock")

local function console(source) return (tonumber(source) or 0) == 0 end

RegisterCommand("ncm.paddock.status", function(source)
    if not console(source) then return end
    local w = PaddockStore.world
    if not w then print("[ncm_paddock] no world yet (ready=" .. tostring(PaddockWorld.ready) .. ")") return end
    local t = U.now()
    local e = Clock.eastern(t)
    local counts = {}
    for _, race in pairs(PaddockRaces.byId) do counts[race.state] = (counts[race.state] or 0) + 1 end
    local parts = {}
    for k, v in pairs(counts) do parts[#parts + 1] = k .. "=" .. v end
    print(("[ncm_paddock] season=%s cup=%s year=%d eastern=%04d-%02d-%02d %02d:%02d%s orgs=%d people=%d races{%s} enabled=%s"):format(
        w.seasonId, tostring(w.cupId), w.paddockYear or 0, e.y, e.m, e.d, e.hour, e.min, e.dst and " EDT" or " EST",
        #w.orgOrder, #w.personOrder, table.concat(parts, " "), tostring(PaddockSettings.get("paddockEnabled", true))))
    local list = {}
    for _, race in pairs(PaddockRaces.byId) do if race.opensAt >= t then list[#list + 1] = race end end
    table.sort(list, function(a, b) return a.opensAt < b.opensAt end)
    for i = 1, math.min(5, #list) do
        local r = list[i]
        print(("  next %s ET %s %s on %s [%s]"):format(Clock.hhmm(r.opensAt), r.raceId, PaddockWorld.seriesName(r.seriesId),
            PaddockWorld.routeName(r.routeId), r.state))
    end
end, false)

RegisterCommand("ncm.paddock.resolve", function(source, args)
    if not console(source) then return end
    CreateThread(function()
        local t = U.now()
        local race = args and args[1] and PaddockRaces.byId[args[1]]
        if not race then
            for _, r in pairs(PaddockRaces.byId) do
                if (r.state == "scheduled" or r.state == "priced") and (not race or r.opensAt < race.opensAt) then race = r end
            end
        end
        if not race then print("[ncm_paddock] no race to resolve") return end
        print("[ncm_paddock] forcing " .. race.raceId)
        if race.state == "scheduled" then PaddockBillie.price(race) end
        race.opensAt = math.min(race.opensAt, t)
        PaddockRaces.run(race, t)
        race.closesAt = t
        PaddockRaces.resolve(race, t)
        print("[ncm_paddock] resolved " .. race.raceId)
    end)
end, false)

RegisterCommand("ncm.paddock.offer", function(source, args)
    if not console(source) then return end
    local driverId, orgId = args and args[1], args and args[2]
    local org = PaddockWorld.org(orgId or "")
    if not driverId or not org then print("usage: ncm.paddock.offer <ncmDriverId> <orgId>") return end
    CreateThread(function()
        local id = PaddockManager.makeOffer(driverId, org, U.now())
        print("[ncm_paddock] offer " .. tostring(id) .. " to " .. driverId .. " for " .. org.name)
    end)
end, false)

RegisterCommand("ncm.paddock.calibrate", function(source)
    if not console(source) then return end
    CreateThread(function() PaddockCalibration.recompute() end)
end, false)

-- ---------------------------------------------------------------------------------------------- phases 4-5
--   ncm.paddock.garage <playerId>                 the garage nearest that player: site, tenants, shifts, bodies
--   ncm.paddock.garage <playerId|siteId> good|bad [note]   the in-engine look: a bad site leaves the rental pool
--   ncm.paddock.live                              live races, the Pace clients and the last probe
--   ncm.paddock.probe [playerId]                  what moves an AI car: distance ladder x (unasked, asked, camera) (server/probe.lua)
local G = NcmCore.get("paddock.garages")

local function siteFor(arg)
    if G.site(arg) then return G.site(arg) end
    local pid = tonumber(arg)
    local ok, positions = pcall(Open77.players.positions)
    local pos = pid and ok and type(positions) == "table" and positions[pid] or nil
    if not pos then return nil, "no position for player " .. tostring(arg) end
    local site, d = PaddockGarages.nearest(pos)
    return site, nil, d
end

RegisterCommand("ncm.paddock.garage", function(source, args)
    if not console(source) then return end
    local site, err, d = siteFor(args and args[1] or "")
    if not site then print("[ncm_paddock] " .. tostring(err or "usage: ncm.paddock.garage <playerId|siteId> [good|bad] [note]")) return end
    local verdict = args[2]
    if verdict == "good" or verdict == "bad" then
        CreateThread(function()
            local ok, why = PaddockGarages.check(site.id, verdict, table.concat(args, " ", 3))
            print(("[ncm_paddock] site %s marked %s: %s"):format(site.id, verdict, ok and "ok" or tostring(why)))
        end)
        return
    end
    local w = PaddockStore.world
    print(("[ncm_paddock] site %s (%s, %s) at %.1f %.1f %.1f%s check=%s"):format(site.id, G.label(site), site.kind,
        site.x, site.y, site.z, d and (" -- %.0f m from the player"):format(d) or "",
        PaddockGarages.bad[site.id] and "bad" or (PaddockGarages.good[site.id] and "good" or "unchecked")))
    for _, oid in ipairs(PaddockGarages.tenants[site.id] or {}) do
        local o = w.orgs[oid]
        local desc = PaddockGarages.describe(o) or {}
        print(("  tenant %s %s [%s] hours %s %s"):format(o.id, o.name, o.tier, tostring(desc.hours), desc.here and "ON SHIFT" or "off"))
    end
    for pid, b in pairs(PaddockGarages.bodies) do
        if b.siteId == site.id then print(("  body %s npc=%s %s"):format(pid, tostring(b.npcId), PaddockWorld.personName(pid))) end
    end
    local s = PaddockGarages.stats
    print(("  stats spawned=%d removed=%d refused=%d talks=%d groundMisses=%d"):format(s.spawned, s.removed, s.refused, s.talks, s.groundMisses))
end, false)

RegisterCommand("ncm.paddock.live", function(source)
    if not console(source) then return end
    print(("[ncm_paddock] liveMode=%s backend=%s"):format(tostring(PaddockSettings.get("liveMode", "watched")), tostring(PaddockSettings.get("liveBackend", "auto"))))
    for id, lr in pairs(PaddockLive.byRace) do
        print(("  live %s state=%s backend=%s verdict=%s reason=%s cars=%d"):format(id, lr.state, tostring(lr.backend), tostring(lr.verdict),
            tostring(lr.reason), #(lr.cars or {})))
    end
    for p, info in pairs(PaddockLive.paceClients) do print(("  pace client %d ok=%s version=%s"):format(p, tostring(info.ok), info.version)) end
    if PaddockProbe and PaddockProbe.last then for _, l in ipairs(PaddockProbe.last.lines) do print("  probe " .. l) end end
end, false)


-- ---------------------------------------------------------------------------------------------- the life sim (L240)
--   ncm.life                                   every district's reading, the season's city climate, pass stats
--   ncm.life.district <name>                   one district: axes, regime, last causes, recent transitions
--   ncm.life.near <playerId>                   places within 200 m of a player and who is there now
--   ncm.life.who <personId>                    that person's day, block by block
--   ncm.life.place <playerId|placeId> good|bad [note]   the in-engine look: a bad place leaves every day
--   ncm.life.player <playerId>                 that Driver's hidden trajectory and band (console only, never a client)
--   ncm.life.fact <district> <kind> [n]        tally a climate fact by hand (testing)
local LPlaces = NcmCore.get("world.places")

-- On the DEVELOPMENT server the owner runs these from chat, and each line answers in chat as well as the console.
-- Online they stay console-only. `ncm.life.player` is console-only everywhere: the trajectory never reaches a client.
local function lifeAllowed(source)
    local pid = tonumber(source) or 0
    if pid == 0 then return true end
    return PaddockSettings.get("lifeChatCommands", PaddockUtil.sid() == "ncm-devbox") == true
end
local function say(source, line)
    print(line)
    local pid = tonumber(source) or 0
    if pid > 0 then pcall(Open77.chat.send, pid, line) end
end
local LClimate = NcmCore.get("life.climate")
local LSched = NcmCore.get("life.schedule")
local LClock = NcmCore.get("world.clock")

local function districtName(s)
    s = tostring(s or ""):lower():gsub("_", " ")
    for _, d in ipairs(LPlaces.DISTRICTS) do if d:lower() == s then return d end end
    return nil
end

RegisterCommand("ncm.life", function(source)
    if not lifeAllowed(source) then return end
    local c = PaddockDays.climate()
    if not c then say(source, "[ncm_paddock] life: no climate loaded") return end
    say(source, ("[ncm_paddock] life: season %s, city climate %s, climate day %d"):format(tostring(c.seasonId), tostring(c.city), c.day or -1))
    for _, d in ipairs(LPlaces.DISTRICTS) do
        local r = LClimate.reading(c, d)
        local ax = c.districts[d].axes
        say(source, ("  %-13s %-40s ord %5.1f grip %5.1f pros %5.1f coh %5.1f heat %5.1f scene %5.1f"):format(d, r.label,
            ax.order, ax.grip, ax.prosperity, ax.cohesion, ax.heat, ax.scene))
    end
    local s = PaddockDays.stats
    say(source, ("  stats plans=%d spawned=%d removed=%d refused=%d transitions=%d recorded=%d"):format(s.plans, s.spawned,
        s.removed, s.refused, s.transitions, s.recorded))
end, false)

RegisterCommand("ncm.life.district", function(source, args)
    if not lifeAllowed(source) then return end
    local c, d = PaddockDays.climate(), districtName(table.concat(args or {}, " "))
    if not c or not d then say(source, "[ncm_paddock] usage: ncm.life.district <Watson|Westbrook|City Center|...>") return end
    local x = c.districts[d]
    say(source, ("[ncm_paddock] %s: %s (since day %d)%s"):format(d, LClimate.reading(c, d).label, x.since or 0,
        x.pending and (" -- reading %s for %d day(s)"):format(x.pending, x.pendingDays) or ""))
    for _, a in ipairs(LClimate.AXES) do
        say(source, ("  %-10s %5.1f   base %5.1f  scar %+.1f"):format(a, x.axes[a], x.base[a], x.scars[a] or 0))
    end
    for _, cause in ipairs(x.causes or {}) do say(source, ("  last day: %s moved %s by %+.2f"):format(cause.kind, cause.axis, cause.delta)) end
    for _, t in ipairs(c.history or {}) do
        if t.district == d then say(source, ("  day %d: %s -> %s%s"):format(t.day, t.from, t.to, t.scar and (" [scar " .. t.scar .. "]") or "")) end
    end
end, false)

RegisterCommand("ncm.life.near", function(source, args)
    if not lifeAllowed(source) then return end
    local pid = tonumber(args and args[1]) or ((tonumber(source) or 0) > 0 and tonumber(source) or nil)
    local ok, positions = pcall(Open77.players.positions)
    local pos = pid and ok and type(positions) == "table" and positions[pid] or nil
    if not pos then say(source, "[ncm_paddock] usage: ncm.life.near [playerId]") return end
    local t = PaddockUtil.now()
    for _, place in ipairs(LPlaces.near(pos, 200)) do
        say(source, ("  %-18s %-32s %4.0f m %s %s"):format(place.id, LPlaces.label(place), LPlaces.distance(place, pos),
            LPlaces.isOpen(place, t) and "open" or "shut", PaddockDays.isBad(place.id) and "BAD" or ""))
        for personId, b in pairs(PaddockGarages.bodies) do
            if b.siteId == place.id then
                say(source, ("      body %s %s (%s)"):format(personId, PaddockWorld.personName(personId), tostring(b.activity or "work")))
            end
        end
    end
end, false)

RegisterCommand("ncm.life.who", function(source, args)
    if not lifeAllowed(source) then return end
    local w = PaddockStore.world
    local p = w and w.people[tostring(args and args[1] or "")]
    if not p then say(source, "[ncm_paddock] usage: ncm.life.who <personId>") return end
    CreateThread(function()
        local t = PaddockUtil.now()
        local plan = PaddockDays.planFor(p, LSched.planDay(t))
        if not plan then say(source, "[ncm_paddock] " .. p.id .. " has no day (no active org)") return end
        say(source, ("[ncm_paddock] %s (%s), lives in %s, sleeps from %s"):format(p.display, p.role, plan.home,
            LClock.hhmm(LClock.utcAt(plan.day, plan.sleepFrom))))
        local now = LSched.at(plan, t)
        for _, run in ipairs(plan.runs) do
            local place = LPlaces.get(run.placeId)
            say(source, ("  %s-%s %-7s %s%s"):format(LClock.hhmm(run.fromUtc), LClock.hhmm(run.toUtc), run.activity,
                place and LPlaces.label(place) or run.placeId, run == now and "   <- now" or ""))
        end
    end)
end, false)

RegisterCommand("ncm.life.place", function(source, args)
    if not lifeAllowed(source) then return end
    local arg, verdict = args and args[1], args and args[2]
    local place = LPlaces.get(arg)
    if not place then
        local pid = tonumber(arg)
        local ok, positions = pcall(Open77.players.positions)
        local pos = pid and ok and type(positions) == "table" and positions[pid] or nil
        place = pos and LPlaces.near(pos, 150)[1]
    end
    if not place or (verdict ~= "good" and verdict ~= "bad") then
        say(source, "[ncm_paddock] usage: ncm.life.place <playerId|placeId> good|bad [note]") return
    end
    CreateThread(function()
        local ok, why = PaddockDays.check(place.id, verdict, table.concat(args, " ", 3))
        say(source, ("[ncm_paddock] place %s (%s) marked %s: %s"):format(place.id, LPlaces.label(place), verdict, ok and "ok" or tostring(why)))
    end)
end, false)

RegisterCommand("ncm.life.player", function(source, args)
    if not console(source) then return end
    local pid = tonumber(args and args[1])
    CreateThread(function()
        local d = pid and PaddockPlayers.driver(pid)
        if not d then print("[ncm_paddock] usage: ncm.life.player <playerId> (a bound Driver)") return end
        local p, band = PaddockDays.profile(d.ncmDriverId)
        print(("[ncm_paddock] %s: bucket %s, band %d -- %s"):format(d.ncmDriverId, p.bucket, band.id, band.label))
        local parts = {}
        for _, a in ipairs(NcmCore.get("life.trajectory").AXES) do parts[#parts + 1] = ("%s %.1f"):format(a, p.raw[a] or 0) end
        print(("  %s | risk %.1f | evidence %.1f | offers %d taken, %d let pass"):format(table.concat(parts, ", "), p.risk,
            p.evidence, p.opportunities, p.silences))
    end)
end, false)

RegisterCommand("ncm.life.fact", function(source, args)
    if not lifeAllowed(source) then return end
    local d, kind, n = districtName(args and args[1]), args and args[2], tonumber(args and args[3]) or 1
    if not d or not LClimate.IMPULSE[kind or ""] then
        say(source, "[ncm_paddock] usage: ncm.life.fact <district> <kind> [n] (district with _ for spaces)") return
    end
    PaddockDays.fact(d, kind, n)
    say(source, ("[ncm_paddock] tallied %s x%s in %s; it lands at the next daily step"):format(kind, tostring(n), d))
end, false)
