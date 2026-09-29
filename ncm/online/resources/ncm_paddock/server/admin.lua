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
--   ncm.paddock.live                              live races and the Pace clients
--   ncm.paddock.live <playerId> [raceId]          declare the soonest eligible (or named) race live for a player
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

RegisterCommand("ncm.paddock.live", function(source, args)
    if not console(source) then return end
    local pid = tonumber(args and args[1])
    if not pid then
        for id, lr in pairs(PaddockLive.byRace) do
            print(("[ncm_paddock] live %s state=%s backend=%s verdict=%s reason=%s cars=%d declarer=%s"):format(id, lr.state,
                tostring(lr.backend), tostring(lr.verdict), tostring(lr.reason), #(lr.cars or {}), tostring(lr.declaredByName)))
        end
        for p, info in pairs(PaddockLive.paceClients) do print(("  pace client %d ok=%s version=%s"):format(p, tostring(info.ok), info.version)) end
        return
    end
    CreateThread(function()
        local raceId = args[2]
        if not raceId then
            local t, best = U.now(), nil
            for _, r in pairs(PaddockRaces.byId) do
                if PaddockLive.eligible(r, t) and (not best or r.opensAt < best.opensAt) then best = r end
            end
            raceId = best and best.raceId
        end
        if not raceId then print("[ncm_paddock] no eligible race") return end
        local ok, res = PaddockLive.declare(pid, raceId)
        print(("[ncm_paddock] declare %s for player %d: %s"):format(raceId, pid, ok and ("ok, start " .. tostring(res.name)) or tostring(res)))
        if ok then TriggerClientEvent("ncm:paddock.live.declared", pid, { raceId = raceId, start = res.start, name = res.name }) end
    end)
end, false)
