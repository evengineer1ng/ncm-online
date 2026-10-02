-- The life sim (L237 M1, L240): world.places, life.climate, life.needs, life.schedule, life.trajectory.
local SEED = 4242
local SEASON = "2026-S4"
local DAY = 20727                 -- an Eastern day index (2026-10-01)

local worldCache
local function world(T)
    if not worldCache then worldCache = T.Core.get("paddock.world").genesis(SEED, SEASON) end
    return worldCache
end

local function sameTable(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not sameTable(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- A driver from the genesis world, with their org and its garage, ready to plan.
local function ctxFor(T, index, opts)
    opts = opts or {}
    local w = world(T)
    local G = T.Core.get("paddock.garages")
    local P = T.Core.get("world.places")
    local people = {}
    for _, id in ipairs(w.personOrder) do
        local p = w.people[id]
        if p.orgId and p.state == "active" and (not opts.role or p.role == opts.role) then people[#people + 1] = p end
    end
    local p = people[index]
    local org = w.orgs[p.orgId]
    local orgs = {}
    for _, oid in ipairs(w.orgOrder) do orgs[#orgs + 1] = { id = oid, tier = w.orgs[oid].tier } end
    local siteId = G.assign(w.seed, orgs, {})[org.id]
    local site = P.get(siteId)
    local shift = G.shiftFor(w.seed, org)
    return {
        seed = w.seed, person = p, tier = org.tier, workDistrict = site and site.district, workPlaceId = siteId,
        climate = opts.climate or T.Core.get("life.climate").genesis(SEED, SEASON, DAY - 1),
        commitment = function(utc) if opts.noShift then return nil end return G.onShift(shift, utc) and "work" or nil end,
    }, shift
end

return {
    -- ---------------------------------------------------------------------------------------------- world.places
    places_registry_is_derived_complete_and_unique = function(T)
        local P = T.Core.get("world.places")
        local all = P.all()
        T.ok(#all >= 200, "service points, meets, garages, fuel and Autofixers all merge: " .. #all)
        local seen, kinds = {}, {}
        for _, p in ipairs(all) do
            T.falsy(seen[p.id], "unique place id " .. p.id); seen[p.id] = true
            T.ok(P.KINDS[p.kind], "known kind " .. tostring(p.kind))
            kinds[p.kind] = true
            T.ok(type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number", "coordinates " .. p.id)
            local known = false
            for _, d in ipairs(P.DISTRICTS) do if d == p.district then known = true end end
            T.ok(known or p.district == "Outskirts", "a real district: " .. p.id .. " " .. tostring(p.district))
            T.falsy(p.path or p.refs or p.journal, "no raw game identifiers cross into NCM: " .. p.id)
            T.falsy(P.label(p):match("%d"), "a label names a place, never a number: " .. P.label(p))
        end
        for _, k in ipairs({ "food", "clinic", "ripperdoc", "meet", "garage", "fuel", "autofixer", "fixer" }) do
            T.ok(kinds[k], "the registry has " .. k)
        end
        T.eq(P.label(P.get("s001")) ~= nil, true)
    end,

    places_hours_run_past_midnight_and_fuel_clusters = function(T)
        local P = T.Core.get("world.places")
        local H = 3600
        local meet = { kind = "meet" }
        T.ok(P.openAt(meet, 23 * H) and P.openAt(meet, 2 * H), "a street meet is on at night, past midnight")
        T.falsy(P.openAt(meet, 14 * H), "and not at two in the afternoon")
        T.ok(P.openAt({ kind = "clinic" }, 4 * H), "a clinic never closes")
        local stations = 0
        local sites = T.Core.get("data.fuel_locations").sites
        for _, p in ipairs(P.all()) do if p.kind == "fuel" then stations = stations + 1 end end
        T.eq(stations, #sites, "every fuel station on the map is a place, and nothing else is")
        local s19 = P.get("fuel_station_19")
        T.ok(s19 and s19.name == "Fuel Station 19" and s19.kind == "fuel", "the map's own id and name: Fuel Station 19")
        T.eq(P.label({ kind = "food", area = "the Glen" }), "a Glen food stall")
    end,

    -- ---------------------------------------------------------------------------------------------- life.climate
    climate_is_deterministic_and_seeded_noise_varies_worlds = function(T)
        local Cl = T.Core.get("life.climate")
        local a, b = Cl.genesis(SEED, SEASON, DAY), Cl.genesis(SEED, SEASON, DAY)
        T.ok(sameTable(a, b), "same seed, same season -> same climate")
        local differ = 0
        for s = 1, 20 do
            local x = Cl.genesis(s, SEASON, DAY)
            if x.districts.Watson.base.heat ~= a.districts.Watson.base.heat then differ = differ + 1 end
        end
        T.ok(differ >= 18, "other seeds give other Night Cities")
        -- Character dominates noise: City Center is richer than Pacifica in nearly every world.
        local richer = 0
        for s = 1, 50 do
            local x = Cl.genesis(s, SEASON, DAY)
            if x.districts["City Center"].axes.prosperity > x.districts.Pacifica.axes.prosperity then richer = richer + 1 end
        end
        T.ok(richer >= 48, "canon character survives the noise: " .. richer .. "/50")
    end,

    climate_seasons_draw_different_city_climates = function(T)
        local Cl = T.Core.get("life.climate")
        local seen = {}
        for q = 1, 40 do seen[Cl.cityClimate(SEED, "20" .. (26 + math.floor(q / 4)) .. "-S" .. (q % 4 + 1)).id] = true end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        T.ok(n >= 4, "forty seasons see at least four kinds of city climate: " .. n)
    end,

    climate_step_is_idempotent_by_day_and_facts_push_their_way = function(T)
        local Cl = T.Core.get("life.climate")
        local quiet = Cl.genesis(SEED, SEASON, DAY)
        local busy = Cl.genesis(SEED, SEASON, DAY)
        for d = 1, 10 do
            Cl.step(quiet, SEED, DAY + d, {})
            Cl.step(busy, SEED, DAY + d, { Heywood = { street_race = 6, turf_record = 1 } })
        end
        T.ok(busy.districts.Heywood.axes.scene > quiet.districts.Heywood.axes.scene + 5,
            "ten nights of street racing grow Heywood's scene")
        T.eq(busy.districts.Watson.axes.scene, quiet.districts.Watson.axes.scene, "and leave Watson where it was")
        local before = busy.districts.Heywood.axes.scene
        local _, tr = Cl.step(busy, SEED, DAY + 10, { Heywood = { street_race = 50 } })
        T.eq(#tr, 0, "a day already stepped does nothing")
        T.eq(busy.districts.Heywood.axes.scene, before, "not even the facts")
        T.ok(#busy.districts.Heywood.causes >= 1, "the last day's causes are kept for explanation")
    end,

    climate_regimes_hold_scar_and_do_not_pin = function(T)
        local Cl = T.Core.get("life.climate")
        local s = Cl.genesis(SEED, SEASON, DAY)
        local regimes, transitions, pinned, scars = {}, 0, 0, 0
        for d = 1, 360 do
            local facts = {}
            -- A war in Pacifica for a month, then quiet: it must end, and leave a mark.
            if d >= 30 and d < 60 then facts.Pacifica = { ncpd_incident = -1, race_crash = 20 } end
            local _, tr = Cl.step(s, SEED, DAY + d, facts)
            for _, t in ipairs(tr) do
                transitions = transitions + 1
                if t.scar then scars = scars + 1 end
                T.ok(t.axes and t.to ~= t.from, "a transition records the values that caused it")
            end
            for name, dist in pairs(s.districts) do
                regimes[dist.regime] = true
                for _, a in ipairs(Cl.AXES) do
                    if dist.axes[a] <= 0 or dist.axes[a] >= 100 then pinned = pinned + 1 end
                end
            end
        end
        local n = 0
        for _ in pairs(regimes) do n = n + 1 end
        T.ok(n >= 3, "a year in Night City sees several regimes: " .. n)
        T.ok(transitions >= 3, "and districts change hands: " .. transitions)
        T.ok(pinned < 360 * 8 * 6 * 0.02, "dampening keeps axes off the rails: " .. pinned)
        T.ok(#s.history <= Cl.HISTORY, "history is bounded")
        local r = Cl.reading(s, "Watson")
        T.ok(r and r.label:match(", "), "a reading is regime x condition: " .. (r and r.label or "nil"))
    end,

    climate_hold_prevents_one_day_flicker = function(T)
        local Cl = T.Core.get("life.climate")
        local s = Cl.genesis(SEED, SEASON, DAY)
        local d = s.districts["City Center"]
        d.regime = "balance"
        d.axes.order, d.axes.grip, d.axes.heat = 90, 90, 10
        Cl.HOLD = 2
        local _, tr = Cl.step(s, SEED, DAY + 1, {})
        T.eq(#tr, 0, "one day reading differently is not a change of regime")
        _, tr = Cl.step(s, SEED, DAY + 2, {})
        T.eq(#tr, 1, "two days is")
        T.eq(tr[1].to, "lockdown")
    end,

    climate_pressures_follow_the_axes = function(T)
        local Cl = T.Core.get("life.climate")
        local s = Cl.genesis(SEED, SEASON, DAY)
        s.districts.Watson.axes.prosperity = 10
        s.districts.Westbrook.axes.prosperity = 90
        T.ok(Cl.pressures(s, "Watson").money > Cl.pressures(s, "Westbrook").money, "a poor district costs more to live in")
        s.districts.Watson.regime = "lockdown"
        T.falsy(Cl.pressures(s, "Watson").meets, "a lockdown busts the street meets")
    end,

    -- ---------------------------------------------------------------------------------------------- life.needs
    needs_decay_bends_by_role_and_personality = function(T)
        local N = T.Core.get("life.needs")
        local driver = N.decayFor({ role = "driver", personality = { drive = 1, warmth = 0 } }, {})
        local owner = N.decayFor({ role = "owner", personality = { drive = -1, warmth = 1 } }, {})
        T.ok(driver.drive > owner.drive * 3, "a hungry driver needs seat time far more than an owner")
        T.ok(owner.social > driver.social, "a warm owner needs company more")
        T.ok(N.urgency(20) > 3 * N.urgency(60), "urgency is steep: a need at 20 shouts")
        local after = N.apply({ money = 50, rest = 50, social = 50, drive = 50 }, driver, { rest = 200 })
        T.eq(after.rest, 100, "needs clamp at 100")
    end,

    -- ---------------------------------------------------------------------------------------------- life.schedule
    schedule_is_deterministic_and_covers_the_day = function(T)
        local S = T.Core.get("life.schedule")
        local ctx = ctxFor(T, 1)
        local a, b = S.plan(ctx, DAY), S.plan(ctx, DAY)
        T.ok(sameTable(a, b), "a day plans the same way twice (a restart recomputes the same day)")
        T.eq(a.runs[1].startBlock, 0)
        T.eq(a.runs[#a.runs].endBlock, S.BLOCKS, "the plan covers all 48 blocks")
        for i = 2, #a.runs do T.eq(a.runs[i].startBlock, a.runs[i - 1].endBlock, "runs are contiguous") end
        local c = S.plan(ctx, DAY + 1)
        T.falsy(sameTable(a.runs, c.runs), "tomorrow is not a copy of today")
    end,

    schedule_people_sleep_mostly_at_their_own_night = function(T)
        local S = T.Core.get("life.schedule")
        local slept, nightShare, n = 0, 0, 0
        for i = 1, 24 do
            local ctx = ctxFor(T, i, { noShift = true })
            local plan = S.plan(ctx, DAY)
            local blocks, inNight = 0, 0
            for _, run in ipairs(plan.runs) do
                if run.activity == "sleep" then
                    for bl = run.startBlock, run.endBlock - 1 do
                        blocks = blocks + 1
                        local sod = (S.DAY_START + bl * 1800) % 86400
                        if (sod - plan.sleepFrom) % 86400 < 9 * 3600 then inNight = inNight + 1 end
                    end
                end
            end
            slept = slept + blocks
            if blocks > 0 then nightShare = nightShare + inNight / blocks end
            n = n + 1
        end
        local avgHours = slept / n / 2
        T.ok(avgHours >= 5 and avgHours <= 10.5, "people sleep a human night on average: " .. avgHours .. " h")
        T.ok(nightShare / n >= 0.75, "and mostly in their own night: " .. nightShare / n)
    end,

    schedule_commitments_override_choice = function(T)
        local S = T.Core.get("life.schedule")
        local G = T.Core.get("paddock.garages")
        local Clock = T.Core.get("world.clock")
        local worked, shiftBlocks = 0, 0
        for i = 1, 10 do
            local ctx, shift = ctxFor(T, i)
            local plan = S.plan(ctx, DAY)
            for bl = 0, S.BLOCKS - 1 do
                local utc = Clock.utcAt(DAY, S.DAY_START + bl * 1800)
                if G.onShift(shift, utc) then
                    shiftBlocks = shiftBlocks + 1
                    local run = S.at(plan, utc)
                    if run and run.activity == "work" and run.placeId == ctx.workPlaceId then worked = worked + 1 end
                end
            end
        end
        T.ok(shiftBlocks > 0, "some of these people have a shift today")
        T.eq(worked, shiftBlocks, "every shift block is spent at the garage")
    end,

    schedule_days_vary_and_bodies_appear_at_real_places = function(T)
        local S = T.Core.get("life.schedule")
        local P = T.Core.get("world.places")
        local acts, places, bodies = {}, {}, 0
        for i = 1, 30 do
            local ctx = ctxFor(T, i)
            local plan = S.plan(ctx, DAY)
            for _, run in ipairs(plan.runs) do
                acts[run.activity] = true
                if S.BODILY[run.activity] then
                    places[run.placeId] = true
                    local place = S.bodyAt(plan, run.fromUtc)
                    T.ok(place and place.id == run.placeId, "a bodily run resolves to its place")
                    if run.activity ~= "work" then
                        T.ok(P.openAt(place, (S.DAY_START + run.startBlock * 1800) % 86400), "nobody eats at a shut stall")
                    end
                    bodies = bodies + 1
                end
            end
        end
        local na, np = 0, 0
        for _ in pairs(acts) do na = na + 1 end
        for _ in pairs(places) do np = np + 1 end
        T.ok(na >= 5, "thirty people do at least five different kinds of thing: " .. na)
        T.ok(np >= 15, "at many different places: " .. np)
        T.ok(bodies >= 30, "and a player could meet them there")
    end,

    schedule_climate_changes_behaviour = function(T)
        local S = T.Core.get("life.schedule")
        local Cl = T.Core.get("life.climate")
        local open, shut = Cl.genesis(SEED, SEASON, DAY - 1), Cl.genesis(SEED, SEASON, DAY - 1)
        for _, d in pairs(open.districts) do d.axes.scene = 95; d.axes.order = 30; d.regime = "scene_town" end
        for _, d in pairs(shut.districts) do d.regime = "lockdown" end
        local hangOpen, hangShut = 0, 0
        for i = 1, 30 do
            local a = S.plan(ctxFor(T, i, { climate = open, noShift = true, role = "driver" }), DAY)
            local b = S.plan(ctxFor(T, i, { climate = shut, noShift = true, role = "driver" }), DAY)
            for _, run in ipairs(a.runs) do if run.activity == "hang" then hangOpen = hangOpen + 1 end end
            for _, run in ipairs(b.runs) do if run.activity == "hang" then hangShut = hangShut + 1 end end
        end
        T.eq(hangShut, 0, "under lockdown nobody makes a street meet")
        T.ok(hangOpen > 0, "where the scene runs things, drivers do: " .. hangOpen)
    end,

    schedule_usually_names_regular_haunts = function(T)
        local S = T.Core.get("life.schedule")
        local ctx = ctxFor(T, 3)
        local plans = {}
        for d = 0, 6 do plans[#plans + 1] = S.plan(ctx, DAY + d) end
        local u = S.usually(plans)
        T.ok(#u >= 1, "a week of days has somewhere this person is usually found")
        for i = 2, #u do T.ok(u[i - 1].blocks >= u[i].blocks, "most-used first") end
    end,

    -- ---------------------------------------------------------------------------------------------- life.trajectory
    trajectory_recognises_rather_than_counts = function(T)
        local Tr = T.Core.get("life.trajectory")
        local p = Tr.new()
        Tr.record(p, SEED, "pA", { id = "f1", kind = "race_finish", district = "Heywood" })
        T.eq(p.bucket, "unknown", "one race says nothing yet")
        for i = 2, 12 do Tr.record(p, SEED, "pA", { id = "f" .. i, kind = "race_finish", district = "Heywood" }) end
        for i = 1, 6 do Tr.record(p, SEED, "pA", { id = "c" .. i, kind = "clean_finish", district = "Heywood" }) end
        T.eq(p.bucket, "professional", "clean, steady racing reads as a professional")
        local q = Tr.new()
        for i = 1, 12 do Tr.record(q, SEED, "pB", { id = "s" .. i, kind = "street_race", district = "Watson" }) end
        for i = 1, 6 do Tr.record(q, SEED, "pB", { id = "e" .. i, kind = "police_escape", district = "Watson" }) end
        T.eq(q.bucket, "wildfire", "street racing and running from NCPD reads as a wildfire")
    end,

    trajectory_is_idempotent_deterministic_and_noisy_per_player = function(T)
        local Tr = T.Core.get("life.trajectory")
        local a, b, c = Tr.new(), Tr.new(), Tr.new()
        for i = 1, 20 do
            local f = { id = "x" .. i, kind = (i % 3 == 0) and "market_trade" or "race_finish" }
            Tr.record(a, SEED, "p1", f); Tr.record(a, SEED, "p1", f)
            Tr.record(b, SEED, "p1", f)
            Tr.record(c, SEED, "p2", f)
        end
        T.ok(sameTable(a.raw, b.raw), "a fact recorded twice counts once, and replays identically")
        T.falsy(sameTable(a.raw, c.raw), "another player doing the same things is not stamped from one mould")
    end,

    trajectory_ghost_and_hold = function(T)
        local Tr = T.Core.get("life.trajectory")
        local p = Tr.new()
        for i = 1, 14 do Tr.record(p, SEED, "g", { id = "r" .. i, kind = "race_finish" }) end
        local before = p.bucket
        T.neq(before, "unknown")
        for i = 1, 9 do Tr.record(p, SEED, "g", { id = "o" .. i, kind = "offer_lapsed" }) end
        T.eq(p.bucket, before, "two readings as a ghost are not yet a ghost (hold)")
        for i = 10, 12 do Tr.record(p, SEED, "g", { id = "o" .. i, kind = "offer_lapsed" }) end
        -- Offers carry no axis, so the silences alone must turn the reading, after the hold.
        T.eq(p.bucket, "ghost", "a driver who lets every offer lapse becomes a ghost")
    end,

    trajectory_band_crosses_bucket_with_home_climate = function(T)
        local Tr = T.Core.get("life.trajectory")
        local Cl = T.Core.get("life.climate")
        local s = Cl.genesis(SEED, SEASON, DAY)
        local p = Tr.new()
        for i = 1, 16 do Tr.record(p, SEED, "b", { id = "t" .. i, kind = "market_trade", district = "Pacifica" }) end
        local band = Tr.band(p, s)
        T.eq(band.district, "Pacifica", "home is where the deeds were done")
        T.ok(band.id >= 1 and band.id <= #Cl.REGIMES * #Tr.BUCKETS, "band id in range")
        s.districts.Pacifica.regime = "open_war"
        local war = Tr.band(p, s)
        s.districts.Pacifica.regime = "scene_town"
        local scene = Tr.band(p, s)
        T.neq(war.id, scene.id, "the same player in a different Pacifica lives a different life")
        T.ok(war.crisis, "a war is a crisis")
    end,
}
