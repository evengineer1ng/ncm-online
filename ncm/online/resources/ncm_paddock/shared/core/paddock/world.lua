-- ncm-core module: paddock.world
-- Genesis: the Paddock's founding world from one seed (doc 44 §4). About 60 organizations, 140 contracted drivers,
-- 40 free agents, and an owner, manager, engineer, strategist and a sponsor or two per org.
--
-- Deterministic for a seed. Built INCREMENTALLY (`newBuilder(...):step()`), because OPEN//77 meters instructions per
-- handler (KB-211) and a whole world in one call would cost millions; the server yields between steps.
--
-- Shapes (all ids are strings and stable; names are unique but NEVER used as keys):
--   org    { id, tier, seriesId, name, short, colour, prestige, cash, car, facility, ownerId, managerId, engineerId,
--            strategistId, sponsorIds, origin, lifecycle, humanManagerDriverId, foundedSeason, seasonsActive }
--   person { id, role, orgId, seat, first, last, display, region, gender, birthYear, attrs, personality, principal,
--            morale, state, wage, contractEnds, leagueId (street pool membership), car (an independent's own car) }
--   sponsor{ id, name, short, industry, tier, personality, orgId, perDay, endsSeason }
local Core = NcmCore

Core.define("paddock.world", function(C)
    -- GENESIS 3 (L249): street leagues are pools of ~56 drivers (`person.leagueId`; independents race their own car),
    -- sanctioned teams carry deeper rosters (Season.TIERS[tier].roster)
    local M = { version = "0.2.0", GENESIS_VERSION = 3, FREE_AGENTS = 120 }   -- L236: ~3x cast
    local Hash = C.get("vocabulary.hash")
    local Names = C.get("paddock.names")
    local Attr = C.get("paddock.attributes")
    local Car = C.get("paddock.car")
    local Season = C.get("paddock.season")

    -- Eddies. Tuned so an org drifts rather than bleeds: see `paddock.finance`.
    M.TIER_CASH = { street = { 20000, 60000 }, regional = { 80000, 200000 }, pro = { 300000, 800000 },
        premier = { 1500000, 4000000 } }
    M.TIER_WAGE = { street = 90, regional = 260, pro = 700, premier = 1800 }       -- per driver per day at rating 50
    M.TIER_SPONSOR = { street = 120, regional = 420, pro = 1300, premier = 4200 }  -- per sponsor per day
    M.DRIVER_AGE = { street = 23, regional = 25, pro = 27, premier = 29 }

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    local function colour(seed, id)
        local h = Hash.fnv1a32(Hash.key(seed, "colour", id))
        local hue = (h % 360) / 60
        local x = 1 - math.abs(hue % 2 - 1)
        local r, g, b
        if hue < 1 then r, g, b = 1, x, 0 elseif hue < 2 then r, g, b = x, 1, 0 elseif hue < 3 then r, g, b = 0, 1, x
        elseif hue < 4 then r, g, b = 0, x, 1 elseif hue < 5 then r, g, b = x, 0, 1 else r, g, b = 1, 0, x end
        local function ch(v) return math.floor(60 + v * 180) end
        return string.format("#%02x%02x%02x", ch(r), ch(g), ch(b))
    end
    M.colour = colour

    function M.wageFor(tier, rating)
        local base = M.TIER_WAGE[tier] or 90
        return math.floor(base * clamp(0.5 + (rating or 50) / 100, 0.6, 1.6) + 0.5)
    end

    --- A new person. `role` is driver|owner|manager|engineer|strategist.
    function M.newPerson(world, role, tier, opts)
        opts = opts or {}
        world.nextPerson = (world.nextPerson or 0) + 1
        local id = string.format("p%05d", world.nextPerson)
        local rng = Hash.stream(world.seed, "person", id)
        local n = Names.person(world.seed, role, id, { taken = world.takenNames })
        local p = {
            id = id, role = role, orgId = opts.orgId, seat = opts.seat, first = n.first, last = n.last,
            display = n.display, region = n.region, gender = n.gender, state = opts.state or "active",
            personality = Attr.personality(world.seed, id),
        }
        local year = world.paddockYear or Season.PADDOCK_EPOCH_YEAR
        if role == "driver" then
            local age = math.floor(clamp(rng:normal(opts.ageMean or M.DRIVER_AGE[tier] or 25, 4), 17, 39) + 0.5)
            p.birthYear = year - age
            p.attrs = Attr.rollDriver(rng, tier, age)
            p.morale = Attr.moraleBaseline(p.attrs)
            p.wage = M.wageFor(tier, Attr.rating(p.attrs))
        elseif role == "owner" or role == "manager" then
            p.birthYear = year - math.floor(clamp(rng:normal(role == "owner" and 52 or 44, 8), 30, 72) + 0.5)
            p.principal = Attr.rollPrincipal(rng)
            p.wage = role == "manager" and math.floor(M.wageFor(tier, 50) * 0.8) or 0
        else
            p.birthYear = year - math.floor(clamp(rng:normal(38, 8), 23, 62) + 0.5)
            p.attrs = Attr.rollStaff(rng, tier)
            p.wage = math.floor(M.wageFor(tier, p.attrs.skill) * 0.6)
        end
        world.people[id] = p
        world.personOrder[#world.personOrder + 1] = id
        world._byOrg, world._byLeague = nil, nil
        return p
    end

    function M.newSponsor(world, tier, orgId)
        world.nextSponsor = (world.nextSponsor or 0) + 1
        local id = string.format("s%04d", world.nextSponsor)
        local name, short, industry = Names.companyName(world.seed, id, nil, world.takenCompanies)
        local rng = Hash.stream(world.seed, "sponsor", id)
        local s = { id = id, name = name, short = short, industry = industry, tier = tier, orgId = orgId,
            personality = Names.sponsorPersonality(world.seed, id),
            perDay = math.floor((M.TIER_SPONSOR[tier] or 100) * (0.6 + rng() * 0.8) + 0.5) }
        world.sponsors[id] = s
        world.sponsorOrder[#world.sponsorOrder + 1] = id
        return s
    end

    --- A new organization in `seriesId`. Staffs it, gives it a car, cash and one or two sponsors.
    function M.newOrg(world, tier, seriesId, opts)
        opts = opts or {}
        world.nextOrg = (world.nextOrg or 0) + 1
        local id = string.format("o%03d", world.nextOrg)
        local rng = Hash.stream(world.seed, "org", id)
        local name, short = opts.name, nil
        if name then world.takenOrgNames[name] = true; short = Names.short(name)
        else name, short = Names.teamName(world.seed, tier, id, world.takenOrgNames) end
        local cash = M.TIER_CASH[tier] or { 20000, 60000 }
        local o = {
            id = id, tier = tier, seriesId = seriesId, name = name, short = short, colour = colour(world.seed, id),
            prestige = math.floor(clamp(rng:normal(40 + (Season.TIERS[tier].rank - 1) * 15, 10), 5, 95)),
            cash = opts.cash or math.floor(cash[1] + rng() * (cash[2] - cash[1])),
            car = Car.roll(rng, tier), facility = math.floor(clamp(rng:normal(50, 15), 10, 95)),
            sponsorIds = {}, origin = opts.origin or "genesis", lifecycle = "active",
            foundedSeason = world.seasonId, seasonsActive = opts.seasonsActive or (1 + rng:int(0, 8)),
        }
        world.orgs[id] = o
        world.orgOrder[#world.orgOrder + 1] = id
        o.ownerId = M.newPerson(world, "owner", tier, { orgId = id, seat = "owner" }).id
        if not opts.noManager then
            o.managerId = M.newPerson(world, "manager", tier, { orgId = id, seat = "manager" }).id
        end
        o.engineerId = M.newPerson(world, "engineer", tier, { orgId = id, seat = "staff" }).id
        o.strategistId = M.newPerson(world, "strategist", tier, { orgId = id, seat = "staff" }).id
        if not opts.noDrivers then
            local spec = Season.TIERS[tier]
            for i = 1, spec.roster do
                local seat = (i <= spec.carsPerOrg) and ("race" .. i) or "reserve"
                local d = M.newPerson(world, "driver", tier, { orgId = id, seat = seat })
                d.contractEnds = world.seasonOrdinal + rng:int(0, 2)
                if tier == "street" then d.leagueId = seriesId end
            end
        end
        local sponsors = opts.sponsors or (1 + (rng:chance(0.45) and 1 or 0))
        for _ = 1, sponsors do o.sponsorIds[#o.sponsorIds + 1] = M.newSponsor(world, tier, id).id end
        return o
    end

    --- An independent street racer in league `seriesId`: no team, their own car, racing for the purse (L249).
    function M.newIndependent(world, seriesId, opts)
        opts = opts or {}
        local d = M.newPerson(world, "driver", "street", { seat = "pool", ageMean = opts.ageMean })
        d.leagueId = seriesId
        d.car = Car.roll(Hash.stream(world.seed, "indie-car", d.id), "street")
        return d
    end

    --- A street league's pool: every active driver who is a member (team drivers and independents), in id order.
    function M.leaguePool(world, seriesId)
        if not world._byLeague then M.reindex(world) end
        local out = {}
        for _, p in ipairs(world._byLeague[seriesId] or {}) do
            if p.role == "driver" and p.state == "active" and p.leagueId == seriesId then out[#out + 1] = p end
        end
        return out
    end

    --- An empty world shell. `seasonId` is the genesis season (competition.seasons id).
    function M.shell(seed, seasonId)
        return {
            seed = seed, genesisVersion = M.GENESIS_VERSION, genesisSeasonId = seasonId, seasonId = seasonId,
            seasonOrdinal = 0, paddockYear = Season.PADDOCK_EPOCH_YEAR,
            series = {}, orgs = {}, people = {}, sponsors = {},
            orgOrder = {}, personOrder = {}, sponsorOrder = {},
            takenNames = {}, takenOrgNames = {}, takenCompanies = {}, takenSeriesNames = {},
        }
    end

    --- An incremental genesis. `builder:step()` does one org (or ten free agents) and returns true while work
    --- remains. `builder.world` is the result. Same seed, same world, regardless of how the steps are scheduled.
    function M.newBuilder(seed, seasonId)
        local world = M.shell(seed, seasonId)
        local jobs = {}
        for idx, s in ipairs(Season.allSeries()) do
            world.series[s.id] = { id = s.id, tier = s.tier, division = s.division,
                name = Names.leagueNameFor(s.id, seed, s.tier, idx, world.takenSeriesNames) }
        end
        for _, tier in ipairs(Season.TIER_ORDER) do
            local spec = Season.TIERS[tier]
            local ids = Season.seriesIds(tier)
            local perSeries = spec.orgs / #ids
            for _, sid in ipairs(ids) do
                for _ = 1, perSeries do jobs[#jobs + 1] = { kind = "org", tier = tier, seriesId = sid } end
            end
        end
        -- the rest of each street league's pool: independents (L249)
        local Attendance = C.get("paddock.attendance")
        local streetTeamDrivers = (Season.TIERS.street.orgs / Season.TIERS.street.divisions) * Season.TIERS.street.roster
        for _, sid in ipairs(Season.seriesIds("street")) do
            local left = Attendance.STREET_POOL - streetTeamDrivers
            while left > 0 do
                local n = math.min(10, left)
                jobs[#jobs + 1] = { kind = "independents", seriesId = sid, n = n }
                left = left - n
            end
        end
        local fa = M.FREE_AGENTS
        while fa > 0 do
            local n = math.min(10, fa)
            jobs[#jobs + 1] = { kind = "free_agents", n = n }
            fa = fa - n
        end
        local b = { world = world, jobs = jobs, at = 0 }
        function b.step()
            b.at = b.at + 1
            local job = jobs[b.at]
            if not job then return false end
            if job.kind == "org" then
                M.newOrg(world, job.tier, job.seriesId)
            elseif job.kind == "independents" then
                for i = 1, job.n do M.newIndependent(world, job.seriesId, { ageMean = (i % 3 == 0) and 30 or 22 }) end
            else
                for i = 1, job.n do
                    -- free agents skew to the lower tiers and the extremes of age: rookies and veterans
                    local tier = (i % 4 == 0) and "regional" or ((i % 7 == 0) and "pro" or "street")
                    local ageMean = (i % 3 == 0) and 33 or 21
                    M.newPerson(world, "driver", tier, { state = "free_agent", ageMean = ageMean })
                end
            end
            return b.at < #jobs
        end
        function b.progress() return b.at, #jobs end
        return b
    end

    --- The whole genesis in one call (tests and offline tools only; the server steps).
    function M.genesis(seed, seasonId)
        local b = M.newBuilder(seed, seasonId)
        while b.step() do end
        return b.world
    end

    function M.age(world, person)
        return (world.paddockYear or Season.PADDOCK_EPOCH_YEAR) - (person.birthYear or world.paddockYear)
    end

    --- Build (or rebuild) the org -> people index. Hosts call this after any roster change; without it
    --- `drivers` scans every person, which a metered host cannot afford per request (KB-211).
    function M.reindex(world)
        local by, league = {}, {}
        for _, pid in ipairs(world.personOrder) do
            local p = world.people[pid]
            if p.orgId then
                local list = by[p.orgId]
                if not list then list = {}; by[p.orgId] = list end
                list[#list + 1] = p
            end
            if p.leagueId then
                local list = league[p.leagueId]
                if not list then list = {}; league[p.leagueId] = list end
                list[#list + 1] = p
            end
        end
        world._byOrg, world._byLeague = by, league
        return by
    end

    function M.invalidate(world) world._byOrg, world._byLeague = nil, nil end

    --- People of an org (any role, any state), from the index.
    function M.members(world, orgId)
        local by = world._byOrg or M.reindex(world)
        return by[orgId] or {}
    end

    --- Contracted drivers of an org, sorted by seat then id.
    function M.drivers(world, orgId)
        local out = {}
        for _, p in ipairs(M.members(world, orgId)) do
            if p.role == "driver" and p.orgId == orgId and p.state == "active" then out[#out + 1] = p end
        end
        table.sort(out, function(a, b)
            if (a.seat or "z") ~= (b.seat or "z") then return (a.seat or "z") < (b.seat or "z") end
            return a.id < b.id
        end)
        return out
    end

    --- Orgs in a series (active only), in id order.
    function M.orgsInSeries(world, seriesId)
        local out = {}
        for _, oid in ipairs(world.orgOrder) do
            local o = world.orgs[oid]
            if o.seriesId == seriesId and o.lifecycle == "active" then out[#out + 1] = o end
        end
        return out
    end

    --- The entry list for a race: every active org's race-seat drivers.
    function M.field(world, seriesId)
        local out = {}
        for _, o in ipairs(M.orgsInSeries(world, seriesId)) do
            for _, d in ipairs(M.drivers(world, o.id)) do
                if d.seat and d.seat:match("^race") then out[#out + 1] = { driver = d, org = o } end
            end
        end
        return out
    end

    --- The field for one race (L249): a street league's pool turns up or not; a sanctioned team fields its available
    --- drivers. `race` = { raceId, seriesId, tier, opensAt }. Returns entrants { { driver, org } } (org nil for an
    --- independent) and `absent` { [personId] = reason }. `pull` (optional): Moody's lure, per person (doc 47).
    function M.raceField(world, race, pull)
        local Attendance = C.get("paddock.attendance")
        local spec = Season.TIERS[race.tier]
        local fieldSize = math.floor(spec.orgs / spec.divisions) * spec.carsPerOrg
        if race.tier == "street" then
            local came, absent = Attendance.streetField(world.seed, race.raceId, M.leaguePool(world, race.seriesId), fieldSize, race.opensAt, pull)
            local out = {}
            for _, d in ipairs(came) do
                local o = d.orgId and world.orgs[d.orgId]
                out[#out + 1] = { driver = d, org = (o and o.lifecycle == "active") and o or nil }
            end
            return out, absent
        end
        local teams = {}
        for _, o in ipairs(M.orgsInSeries(world, race.seriesId)) do teams[#teams + 1] = { org = o, drivers = M.drivers(world, o.id) } end
        return Attendance.teamField(world.seed, race.raceId, teams, race.tier, spec.carsPerOrg, race.opensAt, pull)
    end

    --- Grow an existing world to GENESIS 3's pools (L249), a little per call: street team drivers join their team's
    --- league; each street league is topped up with independents to STREET_POOL; each sanctioned team with reserves to
    --- its tier's roster. Returns the people created or changed this call, and whether work remains. Idempotent.
    function M.growPools(world, budget)
        local Attendance = C.get("paddock.attendance")
        budget = budget or 20
        local touched = {}
        for _, pid in ipairs(world.personOrder) do
            local p = world.people[pid]
            if p.role == "driver" and p.state == "active" and not p.leagueId and p.orgId then
                local o = world.orgs[p.orgId]
                if o and o.tier == "street" then p.leagueId = o.seriesId; touched[#touched + 1] = p end
            end
        end
        local counts = {}
        for _, pid in ipairs(world.personOrder) do
            local p = world.people[pid]
            if p.role == "driver" and p.state == "active" and p.leagueId then counts[p.leagueId] = (counts[p.leagueId] or 0) + 1 end
        end
        for _, sid in ipairs(Season.seriesIds("street")) do
            while (counts[sid] or 0) < Attendance.STREET_POOL and budget > 0 do
                touched[#touched + 1] = M.newIndependent(world, sid)
                counts[sid] = (counts[sid] or 0) + 1
                budget = budget - 1
            end
        end
        for _, oid in ipairs(world.orgOrder) do
            local o = world.orgs[oid]
            if o.lifecycle == "active" and o.tier ~= "street" and not o.humanManagerDriverId then
                local have = #M.drivers(world, oid)
                while have < Season.TIERS[o.tier].roster and budget > 0 do
                    local d = M.newPerson(world, "driver", o.tier, { orgId = oid, seat = "reserve" })
                    d.contractEnds = (world.seasonOrdinal or 0) + 1
                    touched[#touched + 1] = d
                    have, budget = have + 1, budget - 1
                end
            end
        end
        if #touched > 0 then M.reindex(world) end
        return touched, budget <= 0
    end

    function M.freeAgents(world)
        local out = {}
        for _, pid in ipairs(world.personOrder) do
            local p = world.people[pid]
            if p.role == "driver" and p.state == "free_agent" then out[#out + 1] = p end
        end
        return out
    end

    return M
end)
