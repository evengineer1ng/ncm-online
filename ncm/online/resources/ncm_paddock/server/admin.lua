-- ncm_paddock / server / admin -- console commands for the operator (server console only: source 0).
--
--   ncm.paddock.status               world, clock, next races, calibration
--   ncm.paddock.resolve [raceId]     run and resolve the next (or named) race now, for testing
--   ncm.paddock.offer <driverId> <orgId>   an NPC owner offers a human the manager's job
--   ncm.paddock.calibrate            recompute calibration now
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
