-- ncm-core module: world.ambient
--
-- The ambient population DIRECTOR. Pure: it decides what the world should gain and lose this tick;
-- the host (ncm_world/server/ambient.lua) is the only thing that touches Open77.
--
-- WHY A SERVER-OWNED LAYER EXISTS AT ALL (`L177`). Two different population systems are in play and they
-- are not interchangeable:
--
--   1. VANILLA population -- pedestrians, traffic and police the REDengine spawns. The DENSITY SWITCH is
--      server-owned and replicated (`Open77.world.setPopulation(bucket, { crowd, traffic, police })`,
--      `world.population`), so one server decision reaches every client in the bucket. The ENTITIES are
--      not: each client spawns its own, so two players on one corner see two different sets of cars, and
--      no server call can name, move or remove any single one of them. `crowd` is a continuous
--      multiplier; `traffic` and `police` are binary on 2.31 and `getPopulation` says so
--      (`trafficGranularity = "binary"`).
--   2. SERVER-OWNED ambient -- vehicles and NPCs this resource creates. Canonical, shared, identical for
--      every player, and ours to remove by id, anywhere, at any radius.
--
-- So "despawn traffic in a radius before a race" splits cleanly in two: the vanilla half can only be
-- suppressed BUCKET-WIDE, and the radius-scoped half is only possible for entities we own.
--
-- THE TWO HALVES ARE NOT EQUALLY USABLE, and saying so is the single most important thing on this page.
-- A bucket-wide switch in the SHARED world is not "quiet streets during a race". The five shipped street
-- series run on 20/30/60/180-minute cadences at staggered offsets — 21 starts in any three-hour window —
-- so a corridor is in its window essentially all the time, and suppressing the shared bucket for one
-- would leave the city **permanently empty**: this module's own purpose, undone by this module. The
-- vanilla switch is therefore used ONLY in a bucket a race has to itself (`maySuppress`), where the only
-- players it can affect are the ones racing. **Clearing a race corridor is the server-owned layer's job,
-- and only the server-owned layer can actually do it by radius.**
--
-- The point of the server-owned layer is NOT AI racers. It is that a street with people on it is a street
-- two players can talk about: the courier on the corner is in the same place for both of them, which is
-- the one thing per-client traffic can never be.
local Core = NcmCore

Core.define("world.ambient", function(C)
    local M = { version = "0.0.1" }
    local nodes = C.get("data.nodes")

    -- ---------------------------------------------------------------------------------------------
    -- Settings
    -- ---------------------------------------------------------------------------------------------

    -- Distances are metres. The three that matter most are `sightM`, `spawnMinM` and `corridorRadiusM`;
    -- everything else is budget.
    M.DEFAULTS = {
        -- Budget. Server-wide ceilings first, then what any one player may be surrounded by, so a
        -- lobby of one does not consume the whole allowance and a lobby of ten does not multiply it.
        vehicleBudget      = 24,
        pedBudget          = 48,
        perPlayerVehicles  = 5,
        perPlayerPeds      = 10,
        spawnPerTick       = 3,     -- at most this many creations per tick, so a join is not a stampede

        -- Placement.
        spawnMinM          = 110,   -- never closer to ANY player than this: nothing pops in where it is watched
        spawnMaxM          = 240,   -- and never further from the player it is being spawned for
        retireM            = 420,   -- beyond every player by this much, reclaim the budget
        siteTries          = 6,     -- candidate bearings tried per spawn before giving up this tick

        -- Visibility. `sightM` is the distance at which we stop assuming a despawn is unobserved. It is
        -- deliberately larger than the 180 m default NPC streaming radius: beyond it no client has the
        -- entity streamed, so removing it cannot blink in front of anybody. It is a DISTANCE, not a view
        -- frustum -- a server has no camera -- which is why the host pairs it with the projection count
        -- (`Open77.npcs.owner(id).readyClients`) and needs BOTH to agree before a corridor despawn.
        sightM             = 220,

        -- Race corridor.
        corridorRadiusM    = 70,    -- cleared half-width either side of the racing line
        corridorStepM      = 90,    -- route legs are densified to this spacing before the radius test
        corridorMarginM    = 40,    -- extra no-spawn margin outside the cleared radius
        leadSeconds        = 240,   -- begin clearing this long before the published start
        holdSeconds        = 180,   -- and keep it clear this long after the session ends
        -- How long a SCHEDULED row keeps holding past its own start before the live session board has to
        -- justify it. Sessions form at T-60, so this only has to cover the handover; it is not a guess at
        -- how long a race lasts, and it must not become one. See `isHeldClear`.
        graceSeconds       = 120,

        -- Vanilla density, applied per bucket. `traffic`/`police` are booleans on 2.31 whatever number
        -- is written here; `crowd` really is a multiplier.
        crowd              = 1.0,
        traffic            = 1.0,
        police             = true,
        raceCrowd          = 0.0,   -- what a DEDICATED race bucket is set to while its corridor is held
        raceTraffic        = 0.0,
        racePolice         = false,
        -- Which bucket is the shared world. Its vanilla population is never suppressed for a corridor --
        -- see `maySuppress`, which is the guard that stops this service emptying the city it populates.
        sharedBucket       = 0,
        vanillaSuppress    = true,  -- may the switch be used at all, in a bucket that qualifies
        suppressShared     = false, -- the explicit override for the shared bucket; leave it off
    }

    --- Merge caller overrides onto the defaults. Unknown keys are kept: a host tunable that core has not
    --- heard of is the host's business, and dropping it silently is how a tunable stops working.
    function M.settings(overrides)
        local s = {}
        for k, v in pairs(M.DEFAULTS) do s[k] = v end
        if type(overrides) == "table" then
            for k, v in pairs(overrides) do if v ~= nil then s[k] = v end end
        end
        return s
    end

    -- ---------------------------------------------------------------------------------------------
    -- Geometry
    -- ---------------------------------------------------------------------------------------------

    local function planar(a, b)
        local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
        return math.sqrt(dx * dx + dy * dy)
    end
    M.planar = planar

    --- Distance to the nearest player, and that player. `math.huge` when nobody is connected -- which is
    --- the correct answer and not a special case: with no players, nothing is watched and nothing is near.
    function M.nearestPlayer(players, point)
        local best, who = math.huge, nil
        for i = 1, #(players or {}) do
            local p = players[i]
            if point.bucket == nil or p.bucket == nil or p.bucket == point.bucket then
                local d = planar(p, point)
                if d < best then best, who = d, p end
            end
        end
        return best, who
    end

    --- Densify a polyline so that no two consecutive points are further apart than `stepM`. A corridor
    --- test is a union of discs; without this a 400 m straight between two authored nodes is two discs
    --- with a hole between them, and the hole is exactly where the racing line runs.
    function M.densify(points, stepM)
        stepM = stepM or M.DEFAULTS.corridorStepM
        local out = {}
        if type(points) ~= "table" or #points == 0 then return out end
        out[1] = { x = points[1].x, y = points[1].y, z = points[1].z }
        for i = 2, #points do
            local a, b = points[i - 1], points[i]
            local d = planar(a, b)
            local steps = math.max(1, math.ceil(d / stepM))
            for s = 1, steps do
                local t = s / steps
                out[#out + 1] = {
                    x = a.x + (b.x - a.x) * t,
                    y = a.y + (b.y - a.y) * t,
                    z = (a.z or 0) + ((b.z or 0) - (a.z or 0)) * t,
                }
            end
        end
        return out
    end

    --- Build a corridor from a resolved route (course.routes.resolve): start, authored intermediates,
    --- finish. Returns { id, points, radiusM, bucket } or nil, reason.
    function M.corridorFromRoute(route, options)
        if type(route) ~= "table" or type(route.start) ~= "table" or type(route.finish) ~= "table" then
            return nil, "invalid_route"
        end
        local s = M.settings(options)
        local line = { route.start }
        for _, p in ipairs(route.intermediate or {}) do line[#line + 1] = p end
        line[#line + 1] = route.finish
        return {
            id = route.routeId,
            points = M.densify(line, s.corridorStepM),
            radiusM = s.corridorRadiusM,
            bucket = options and options.bucket or nil,
        }
    end

    --- Planar distance from a point to the SEGMENT ab, not to its endpoints.
    local function toSegment(a, b, p)
        local abx, aby = (b.x or 0) - (a.x or 0), (b.y or 0) - (a.y or 0)
        local len2 = abx * abx + aby * aby
        if len2 <= 0 then return planar(a, p) end
        local t = (((p.x or 0) - (a.x or 0)) * abx + ((p.y or 0) - (a.y or 0)) * aby) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        return planar({ x = (a.x or 0) + abx * t, y = (a.y or 0) + aby * t }, p)
    end
    M.toSegment = toSegment

    --- Is the point inside any corridor (plus `margin` metres of slack)? Returns the corridor, or nil.
    ---
    --- The corridor is a CAPSULE around the polyline, not a union of discs on its points. A disc union
    --- scallops: with 90 m spacing and a 70 m radius the true half-width falls to 54 m halfway between
    --- two points, so a car sitting 60 m off the racing line reads as outside the corridor exactly where
    --- the straight is longest and the closing speed highest. Measuring to the segment makes the cleared
    --- width the width that was asked for, everywhere along the lap.
    function M.inCorridor(corridors, point, margin)
        margin = margin or 0
        for i = 1, #(corridors or {}) do
            local c = corridors[i]
            if c.bucket == nil or point.bucket == nil or c.bucket == point.bucket then
                local r = (c.radiusM or M.DEFAULTS.corridorRadiusM) + margin
                local pts = c.points or {}
                if #pts == 1 and planar(pts[1], point) <= r then return c end
                for j = 2, #pts do
                    if toSegment(pts[j - 1], pts[j], point) <= r then return c end
                end
            end
        end
        return nil
    end

    --- Should this event's corridor be held clear right now? `event` is a calendar row
    --- ({ startsAt, entrants }) or a live session ({ startsAt, live, endedAt }).
    ---
    --- THE DUTY CYCLE IS THE WHOLE PROBLEM HERE, and the first version of this function got it wrong.
    --- The five shipped street series run on 20/30/60/180-minute cadences at staggered offsets: 21 starts
    --- in any three-hour window. Holding a corridor from T-4 to fifteen minutes past every *scheduled*
    --- start merges into ONE CONTINUOUS INTERVAL — 100% of the clock — so a service built to put people
    --- in the world would have kept the roads it cares about permanently empty instead. Two corrections
    --- follow from that, and both are about holding a road only for a race that is really going to use it:
    ---
    ---   * **A slot nobody entered holds nothing.** `entrants` is the calendar's own entry count. Zero is
    ---     a slot that will form no session at all, and most slots on a small server are exactly that.
    ---     `nil` means the caller does not know and the time window alone decides, which is the old
    ---     behaviour and the right default for a caller that has no count to give.
    ---   * **After the start, the live session board is the authority, not the schedule.** A scheduled row
    ---     holds only to `startsAt + graceSeconds` — long enough for the formed session to appear and take
    ---     over — rather than guessing a race length for a race that may never have begun. A session that
    ---     IS live holds for as long as it runs, however far it overruns its own estimate.
    function M.isHeldClear(event, now, options)
        if type(event) ~= "table" then return false end
        local s = M.settings(options)
        local startsAt = tonumber(event.startsAt)
        if startsAt == nil then return false end
        if now < startsAt - s.leadSeconds then return false end
        -- A session that has ended releases its corridor after the hold; one still running never does.
        local endedAt = tonumber(event.endedAt)
        if endedAt ~= nil then return now <= endedAt + s.holdSeconds end
        if event.live then return true end
        local entrants = tonumber(event.entrants)
        if entrants ~= nil and entrants <= 0 then return false end
        return now <= startsAt + s.graceSeconds
    end

    -- ---------------------------------------------------------------------------------------------
    -- The plan
    -- ---------------------------------------------------------------------------------------------

    local function kindKey(kind) return kind == "vehicle" and "vehicle" or "ped" end

    --- Decide this tick.
    ---
    --- state = {
    ---   now       = seconds,
    ---   players   = { { id, x, y, z, bucket } ... },
    ---   entities  = { { key, kind = "vehicle"|"ped", x, y, z, bucket, watched = bool|nil } ... },
    ---   corridors = { { id, points, radiusM, bucket? } ... },
    ---   settings  = {...},
    ---   rng       = function() -> 0..1,
    --- }
    ---
    --- `watched` is the host's projection read: true when at least one client is rendering the entity,
    --- false when none is, nil when the host could not tell. NIL IS TREATED AS WATCHED. A despawn we are
    --- not sure about is a despawn somebody might see, and the cost of being wrong is a car vanishing in
    --- front of a driver at racing speed.
    ---
    --- -> { spawn = {...}, despawn = {...}, deferred = {...}, counts = {...}, live = {...} }
    function M.plan(state)
        if type(state) ~= "table" then return nil, "invalid_state" end
        local s = M.settings(state.settings)
        local now = tonumber(state.now) or 0
        local players = state.players or {}
        local entities = state.entities or {}
        local corridors = state.corridors or {}
        local rng = type(state.rng) == "function" and state.rng or function() return 0.5 end

        local out = { spawn = {}, despawn = {}, deferred = {}, counts = {}, live = {} }
        local budget = { vehicle = s.vehicleBudget, ped = s.pedBudget }
        local live = { vehicle = 0, ped = 0 }
        local removing = {}

        -- One pass to classify, so an entity is judged once against a single distance read.
        local judged = {}
        for i = 1, #entities do
            local e = entities[i]
            local k = kindKey(e.kind)
            local d = M.nearestPlayer(players, e)
            local unwatched = (e.watched == false) and d > s.sightM
            judged[#judged + 1] = { e = e, k = k, d = d, unwatched = unwatched }
        end

        -- 1. The corridor. This is the reason the whole mechanism exists, so it outranks budget.
        for _, j in ipairs(judged) do
            if M.inCorridor(corridors, j.e) then
                if j.unwatched then
                    removing[j.e.key] = true
                    out.despawn[#out.despawn + 1] = { key = j.e.key, kind = j.e.kind, reason = "corridor" }
                else
                    -- Left standing ON PURPOSE, and reported so the host can say why the corridor is not
                    -- clear yet instead of looking like it failed. It comes out on a later tick, once the
                    -- player who is looking at it has moved on.
                    out.deferred[#out.deferred + 1] = {
                        key = j.e.key, kind = j.e.kind,
                        reason = (j.e.watched ~= false) and "corridor_projected" or "corridor_in_sight",
                    }
                end
            end
        end

        -- 2. Unattended. Nothing within `retireM` of any player, so ordinarily nothing can be watching
        -- it either and the distance is its own justification. Two deliberate asymmetries with rule 1:
        --
        --   * an explicit `watched == true` still blocks it. "We only remove what nobody is looking at"
        --     is a promise with no exceptions, and if the host's projection read disagrees with the
        --     distance heuristic, the read is the one that saw a client.
        --   * `watched == nil` does NOT block it, unlike in the corridor rule. A host whose projection
        --     read keeps failing would otherwise never reclaim anything and the budget would leak until
        --     no ambient life could be spawned at all -- and the entity is past `retireM` regardless.
        for _, j in ipairs(judged) do
            if not removing[j.e.key] and j.d > s.retireM and j.e.watched ~= true then
                removing[j.e.key] = true
                out.despawn[#out.despawn + 1] = { key = j.e.key, kind = j.e.kind, reason = "unattended" }
            end
        end

        -- Survivors, furthest first: that is the order budget pressure should eat them in.
        local survivors = {}
        for _, j in ipairs(judged) do
            if not removing[j.e.key] then
                live[j.k] = live[j.k] + 1
                survivors[#survivors + 1] = j
            end
        end
        table.sort(survivors, function(a, b)
            if a.d == b.d then return tostring(a.e.key) < tostring(b.e.key) end
            return a.d > b.d
        end)

        -- 3. Budget. A ceiling lowered at runtime has to be able to take effect, but not at the cost of
        -- rule 1's promise: an over-budget entity somebody is looking at waits its turn like any other.
        --
        -- `excess` is counted ONCE, up front, and decremented per entity considered -- deferred ones
        -- included. Testing `live > budget` inside the loop instead would flag every survivor whenever
        -- the furthest few happen to be watched, because nothing comes off `live` to end the condition:
        -- four cars over a budget of two reported four deferrals rather than two.
        local excess = { vehicle = live.vehicle - budget.vehicle, ped = live.ped - budget.ped }
        for _, j in ipairs(survivors) do
            if excess[j.k] > 0 then
                excess[j.k] = excess[j.k] - 1
                if j.unwatched then
                    removing[j.e.key] = true
                    live[j.k] = live[j.k] - 1
                    out.despawn[#out.despawn + 1] = { key = j.e.key, kind = j.e.kind, reason = "budget" }
                else
                    out.deferred[#out.deferred + 1] = { key = j.e.key, kind = j.e.kind, reason = "budget_watched" }
                end
            end
        end

        -- 4. Spawn. Per player, nearest-first on the player's own crowding, capped by what is left of the
        -- server ceiling and by `spawnPerTick`.
        local perPlayer = {}
        for _, j in ipairs(survivors) do
            if not removing[j.e.key] then
                for _, p in ipairs(players) do
                    if planar(p, j.e) <= s.spawnMaxM then
                        perPlayer[p.id] = perPlayer[p.id] or { vehicle = 0, ped = 0 }
                        perPlayer[p.id][j.k] = perPlayer[p.id][j.k] + 1
                    end
                end
            end
        end

        -- Sites already promised this tick. Two spawns must not land on top of each other, and the
        -- pending list is local rather than written back into the caller's state table: `plan` reads its
        -- argument and nothing else, which is what makes it safe to call twice on the same input.
        local pending = {}
        local made = 0
        for _, p in ipairs(players) do
            local mine = perPlayer[p.id] or { vehicle = 0, ped = 0 }
            for _, kind in ipairs({ "ped", "vehicle" }) do
                local want = (kind == "vehicle") and s.perPlayerVehicles or s.perPlayerPeds
                while made < s.spawnPerTick and mine[kind] < want and live[kind] < budget[kind] do
                    local site = M.site(p, { players = players, corridors = corridors, pending = pending },
                        s, rng)
                    if site == nil then break end
                    site.kind = kind
                    site.forPlayer = p.id
                    out.spawn[#out.spawn + 1] = site
                    pending[#pending + 1] = site
                    -- Counted as if it already exists, so the budget is not spent twice.
                    live[kind] = live[kind] + 1
                    mine[kind] = mine[kind] + 1
                    made = made + 1
                end
            end
        end

        out.counts = { vehicle = live.vehicle, ped = live.ped }
        out.live = out.counts
        out.now = now
        return out
    end

    --- One candidate placement around a player, or nil when every try was rejected.
    ---
    --- `state` needs only `players`, `corridors` and `pending` (sites already promised this tick, so two
    --- spawns do not land on each other); a full `plan` state satisfies that and so does a bare table.
    --- Exposed rather than local because the host may want one site without running a whole plan, and
    --- because a placement rule is worth testing on its own.
    function M.site(player, state, s, rng)
        s = s or M.settings(state and state.settings)
        rng = rng or function() return 0.5 end
        local players = (state and state.players) or {}
        local corridors = (state and state.corridors) or {}
        local pending = (state and state.pending) or {}
        for _ = 1, s.siteTries do
            local bearing = rng() * math.pi * 2
            local radius = s.spawnMinM + rng() * (s.spawnMaxM - s.spawnMinM)
            local site = {
                x = (player.x or 0) + math.cos(bearing) * radius,
                y = (player.y or 0) + math.sin(bearing) * radius,
                z = player.z or 0,             -- a HINT; the host settles it with Open77.world.groundZ
                bucket = player.bucket,
                heading = (bearing * 180 / math.pi + 90) % 360,
            }
            local nearest = M.nearestPlayer(players, site)
            local clearOfPending = true
            for i = 1, #pending do
                if planar(pending[i], site) < 25 then clearOfPending = false; break end
            end
            if nearest >= s.spawnMinM and clearOfPending
                and not M.inCorridor(corridors, site, s.corridorMarginM) then
                local node = M.nearestNode(site)
                site.region = node and node.region or "Night City"
                -- Borrow the authored heading of a road node we are effectively standing on: a car
                -- dropped square across the lanes still joins traffic, but it looks like a mistake first.
                if node and planar(node, site) < 60 and node.heading then site.heading = node.heading end
                return site
            end
        end
        return nil
    end

    --- The curated node nearest a point, for region attribution. Nodes are sparse (35 road nodes), so
    --- this is a FLAVOUR lookup, not a position source.
    function M.nearestNode(point)
        local best, who = math.huge, nil
        for _, n in ipairs(nodes.LIST) do
            local d = planar(n, point)
            if d < best then best, who = d, n end
        end
        return who, best
    end

    function M.regionAt(point)
        local n = M.nearestNode(point)
        return n and n.region or "Night City"
    end

    -- ---------------------------------------------------------------------------------------------
    -- Vanilla density
    -- ---------------------------------------------------------------------------------------------

    --- What `Open77.world.setPopulation` should be told for one bucket. `held` is true while a corridor
    --- in that bucket is being kept clear.
    function M.populationFor(held, options)
        local s = M.settings(options)
        if held then
            return { crowd = s.raceCrowd, traffic = s.raceTraffic, police = s.racePolice }
        end
        return { crowd = s.crowd, traffic = s.traffic, police = s.police }
    end

    --- MAY this bucket's vanilla population be suppressed for a held corridor? This is the guard that
    --- stops the service undoing its own purpose, and it is structural rather than a matter of taste.
    ---
    --- The vanilla switch is PER BUCKET and there is no radius-scoped equivalent on 2.31. In the shared
    --- world bucket that makes it the wrong instrument by construction: with 21 scheduled starts in a
    --- three-hour window, *something* is nearly always within its corridor window, so a bucket-wide
    --- suppression is not "quiet streets during a race" — it is **an empty city, permanently**, which is
    --- the exact opposite of what this module exists to do. The radius-scoped half is the server-owned
    --- layer, and that half is what clears a race corridor.
    ---
    --- In a bucket of the race's OWN, the same switch is exactly right and costs nobody anything: the
    --- only players in it are the ones racing. So the rule is the bucket, not the operator's judgement.
    --- `suppressShared` is the explicit escape hatch for a private server where everyone present is at
    --- the race; it is off by default and should stay off on anything with a spectator on it.
    function M.maySuppress(bucket, options)
        local s = M.settings(options)
        if s.vanillaSuppress == false then return false, "disabled" end
        if bucket == s.sharedBucket then
            if s.suppressShared == true then return true, "shared_bucket_override" end
            return false, "shared_bucket"
        end
        return true, "dedicated_bucket"
    end

    -- ---------------------------------------------------------------------------------------------
    -- Catalogues
    -- ---------------------------------------------------------------------------------------------

    -- Street traffic, not a race grid: the `standard` half of the NCM pool, which is the half a Night
    -- City street is actually made of. No halo cars -- a Caliburn parked in ambient traffic reads as a
    -- prize nobody can claim, and NCM sells those through the collection.
    M.VEHICLE_RECORDS = {
        "Vehicle.v_standard2_thorton_galena",
        "Vehicle.v_standard2_archer_hella",
        "Vehicle.v_standard2_makigai_maimai",
        "Vehicle.v_standard2_villefort_cortes",
        "Vehicle.v_standard2_thorton_colby",
        "Vehicle.v_standard25_thorton_colby_pickup",
        "Vehicle.v_standard25_villefort_columbus",
        "Vehicle.v_standard25_mahir_supron",
        "Vehicle.v_standard3_chevalier_emperor",
        "Vehicle.v_standard3_thorton_mackinaw",
    }

    -- Pedestrians, by region. Every record is `crowd` + `candidate` in the platform's own model
    -- catalogue (open77_admin/server/models-data.lua) -- that list is discovery and not an allowlist,
    -- so this is a hand-picked subset of the plainly ambient archetypes rather than the whole 390.
    local GENERIC = {
        "Character.CorpoMan", "Character.CorpoWoman", "Character.WorkerMale",
        "Character.YoungsterMale", "Character.YoungsterFemale",
        "Character.AsianMale", "Character.AsianFemale",
    }
    M.PED_RECORDS = {
        ["City Center"] = {
            "Character.CorpoMan", "Character.CorpoWoman", "Character.CorpoManCellphone",
            "Character.CorpoManCoffee", "Character.CorpoWomanAfterWork", "Character.CitizenRichMale",
            "Character.CitizenRichFemale", "Character.ArasakaScientist",
        },
        ["Westbrook"] = {
            "Character.CitizenRichFemaleCasual", "Character.CitizenRichMaleCasual",
            "Character.CitizenRichMaleUmbrella", "Character.AsianVendorFemale",
            "Character.AsianNonVendorMale", "Character.YoungsterFemale",
        },
        ["Watson"] = {
            "Character.AsianMale", "Character.AsianFemale", "Character.AsianVendorMale",
            "Character.YoungsterMale", "Character.YoungsterMaleBig", "Character.WorkerMale",
        },
        ["Heywood"] = {
            "Character.CreoleVendorMale", "Character.CreoleVendorFemale", "Character.WorkerMale",
            "Character.YoungsterFemale", "Character.CorpoManAfterWork", "Character.VendorFemale",
        },
        ["Pacifica"] = {
            "Character.HomelessMan", "Character.HomelessFemale", "Character.HomelessManBackpack",
            "Character.YoungsterMale", "Character.WorkerMale", "Character.CitizenBikerMale",
        },
        ["Santo Domingo"] = {
            "Character.WorkerMale", "Character.WorkerSpecialistMale", "Character.VendorMale",
            "Character.YoungsterMaleBig", "Character.HomelessManBig",
        },
        ["Badlands"] = {
            "Character.CitizenAldecaldosMale", "Character.CitizenAldecaldosFemale",
            "Character.CitizenAldecaldosMaleNomad", "Character.CitizenAldecaldosFemaleNomad",
            "Character.CitizenAldecaldosMaleFarmer",
        },
    }

    local function pick(list, rng)
        if type(list) ~= "table" or #list == 0 then return nil end
        local i = math.floor((rng or math.random)() * #list) + 1
        if i > #list then i = #list end
        return list[i]
    end

    function M.pickVehicle(rng) return pick(M.VEHICLE_RECORDS, rng) end

    function M.pickPed(region, rng)
        return pick(M.PED_RECORDS[region] or GENERIC, rng)
    end

    --- Drivers are peds too, but a driver is seen through a windscreen at speed: the region flavour is
    --- wasted and the generic set is enough.
    function M.pickDriver(rng) return pick(GENERIC, rng) end

    return M
end)
