local M = NcmCore.get("world.ambient")
local cases = {}

-- A deterministic rng: cycles a fixed sequence, so a site is reproducible under both interpreters.
local function seq(values)
    local i = 0
    return function()
        i = i + 1
        return values[((i - 1) % #values) + 1]
    end
end

local function P(id, x, y, bucket) return { id = id, x = x, y = y, z = 10, bucket = bucket } end
local function E(key, kind, x, y, watched, bucket)
    return { key = key, kind = kind, x = x, y = y, z = 10, watched = watched, bucket = bucket }
end

-- A corridor along the x axis from 0 to 400, 70 m wide.
local function corridor()
    return M.corridorFromRoute({
        routeId = "test_route",
        start = { x = 0, y = 0, z = 10 },
        finish = { x = 400, y = 0, z = 10 },
    })
end

-- ------------------------------------------------------------------ geometry

cases.densify_leaves_no_hole_between_authored_points = function(T)
    local out = M.densify({ { x = 0, y = 0 }, { x = 400, y = 0 } }, 90)
    T.eq(#out, 6)                       -- origin + ceil(400/90) = 5 steps
    for i = 2, #out do
        T.ok(M.planar(out[i - 1], out[i]) <= 90.0001, "gap " .. i)
    end
    T.eq(out[#out].x, 400)
end

cases.densify_of_a_single_point_is_that_point = function(T)
    local out = M.densify({ { x = 7, y = 9 } }, 90)
    T.eq(#out, 1); T.eq(out[1].x, 7)
end

cases.densify_of_nothing_is_nothing = function(T)
    T.eq(#M.densify({}, 90), 0)
    T.eq(#M.densify(nil, 90), 0)
end

cases.a_route_corridor_runs_through_its_intermediates = function(T)
    local c = M.corridorFromRoute({
        routeId = "r", start = { x = 0, y = 0 },
        intermediate = { { x = 0, y = 300 } }, finish = { x = 300, y = 300 },
    })
    T.ok(M.inCorridor({ c }, { x = 0, y = 150 }), "first leg")
    T.ok(M.inCorridor({ c }, { x = 150, y = 300 }), "second leg")
    -- the crow-flies line between start and finish must NOT be covered
    T.eq(M.inCorridor({ c }, { x = 150, y = 150 }), nil)
end

cases.a_route_without_endpoints_is_refused = function(T)
    local c, why = M.corridorFromRoute({ routeId = "r" })
    T.eq(c, nil); T.eq(why, "invalid_route")
end

cases.corridor_membership_respects_the_margin = function(T)
    local c = corridor()
    T.ok(M.inCorridor({ c }, { x = 200, y = 69 }), "inside")
    T.eq(M.inCorridor({ c }, { x = 200, y = 80 }), nil)
    T.ok(M.inCorridor({ c }, { x = 200, y = 80 }, 40), "inside with margin")
end

cases.a_corridor_bound_to_a_bucket_ignores_another_bucket = function(T)
    local c = corridor(); c.bucket = 4
    T.eq(M.inCorridor({ c }, { x = 200, y = 0, bucket = 0 }), nil)
    T.ok(M.inCorridor({ c }, { x = 200, y = 0, bucket = 4 }), "same bucket")
    T.ok(M.inCorridor({ c }, { x = 200, y = 0 }), "bucketless point is tested everywhere")
end

cases.nearest_player_with_nobody_connected_is_infinite = function(T)
    T.eq(M.nearestPlayer({}, { x = 0, y = 0 }), math.huge)
end

-- ------------------------------------------------------------------ the corridor rule

cases.an_unwatched_entity_in_the_corridor_is_despawned = function(T)
    local r = M.plan({
        now = 100,
        -- 300 m away: past sightM, but well inside retireM, so this isolates the corridor rule from
        -- the unattended one rather than letting both fire on the same entity.
        players = { P(1, 200, 300) },
        entities = { E("a", "vehicle", 200, 0, false) },
        corridors = { corridor() },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 1); T.eq(r.despawn[1].key, "a"); T.eq(r.despawn[1].reason, "corridor")
    T.eq(#r.deferred, 0)
end

cases.an_entity_a_client_is_projecting_is_left_standing = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 200, 300) },
        entities = { E("a", "vehicle", 200, 0, true) },   -- watched = a client renders it
        corridors = { corridor() },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 0)
    T.eq(#r.deferred, 1); T.eq(r.deferred[1].reason, "corridor_projected")
end

cases.an_entity_within_sight_is_left_standing_even_if_unprojected = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 200, 100) },          -- 100 m from the entity: inside sightM
        entities = { E("a", "ped", 200, 0, false) },
        corridors = { corridor() },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 0)
    T.eq(#r.deferred, 1); T.eq(r.deferred[1].reason, "corridor_in_sight")
end

cases.an_unknown_projection_state_counts_as_watched = function(T)
    -- watched = nil: the host could not tell. A despawn we are not sure about is one somebody may see.
    local r = M.plan({
        now = 100,
        players = { P(1, 200, 300) },
        entities = { E("a", "vehicle", 200, 0, nil) },
        corridors = { corridor() },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 0)
    T.eq(#r.deferred, 1); T.eq(r.deferred[1].reason, "corridor_projected")
end

cases.a_deferred_entity_comes_out_once_the_watcher_moves_on = function(T)
    local state = {
        now = 100,
        players = { P(1, 200, 100) },
        entities = { E("a", "ped", 200, 0, false) },
        corridors = { corridor() },
        settings = { spawnPerTick = 0 },
    }
    T.eq(#M.plan(state).despawn, 0)
    state.players = { P(1, 200, 400) }        -- 400 m away now
    local r = M.plan(state)
    T.eq(#r.despawn, 1); T.eq(r.despawn[1].reason, "corridor")
end

cases.entities_outside_the_corridor_are_untouched_by_it = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 200, 300) },
        entities = { E("a", "ped", 200, 300, false) },   -- beside the player, well clear of the line
        corridors = { corridor() },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 0); T.eq(#r.deferred, 0); T.eq(r.counts.ped, 1)
end

-- ------------------------------------------------------------------ budget and reclaim

cases.an_entity_nobody_is_near_is_reclaimed = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = { E("far", "ped", 5000, 5000, false) },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 1); T.eq(r.despawn[1].reason, "unattended")
end

cases.reclaim_still_stops_for_a_client_that_is_rendering_it = function(T)
    -- Past retireM, so the distance heuristic says nobody can see it -- but the host's projection read
    -- says a client is drawing it, and the read is the one that actually looked.
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = { E("far", "ped", 5000, 5000, true) },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 0)
end

cases.reclaim_proceeds_when_the_projection_read_is_unavailable = function(T)
    -- Unlike the corridor rule, an unknown projection does NOT block a reclaim: a host whose read keeps
    -- failing would otherwise leak the whole budget, and the entity is past retireM either way.
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = { E("far", "ped", 5000, 5000, nil) },
        settings = { spawnPerTick = 0 },
    })
    T.eq(#r.despawn, 1); T.eq(r.despawn[1].reason, "unattended")
end

cases.over_budget_eats_the_furthest_unwatched_first = function(T)
    local ents = {}
    for i = 1, 4 do ents[i] = E("v" .. i, "vehicle", i * 50, 0, false) end
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = ents,
        settings = { vehicleBudget = 2, spawnPerTick = 0, retireM = 10000, sightM = 10 },
    })
    T.eq(#r.despawn, 2)
    local keys = { r.despawn[1].key, r.despawn[2].key }
    table.sort(keys)
    T.eq(table.concat(keys, ","), "v3,v4")
    T.eq(r.counts.vehicle, 2)
end

cases.budget_never_overrides_the_sight_rule = function(T)
    local ents = {}
    for i = 1, 4 do ents[i] = E("v" .. i, "vehicle", i * 50, 0, true) end   -- all projected
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = ents,
        settings = { vehicleBudget = 2, spawnPerTick = 0, retireM = 10000 },
    })
    T.eq(#r.despawn, 0)
    T.eq(#r.deferred, 2)
    T.eq(r.deferred[1].reason, "budget_watched")
end

cases.the_two_kinds_hold_separate_budgets = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = { E("v", "vehicle", 50, 0, false), E("p", "ped", 60, 0, false) },
        settings = { vehicleBudget = 0, pedBudget = 4, spawnPerTick = 0, retireM = 10000, sightM = 10 },
    })
    T.eq(#r.despawn, 1); T.eq(r.despawn[1].key, "v")
end

-- ------------------------------------------------------------------ spawning

cases.a_spawn_never_lands_within_the_no_pop_radius = function(T)
    local rng = seq({ 0.1, 0.9, 0.33, 0.5, 0.7, 0.2 })
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0), P(2, 300, 0) },
        entities = {},
        settings = { spawnPerTick = 6 },
        rng = rng,
    })
    T.ok(#r.spawn > 0, "something was proposed")
    for _, site in ipairs(r.spawn) do
        for _, p in ipairs({ P(1, 0, 0), P(2, 300, 0) }) do
            T.ok(M.planar(p, site) >= M.DEFAULTS.spawnMinM, "too close to a player")
        end
    end
end

cases.a_spawn_never_lands_inside_the_corridor_or_its_margin = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 200, 0) },            -- standing ON the racing line
        entities = {},
        corridors = { corridor() },
        settings = { spawnPerTick = 8 },
        rng = seq({ 0.05, 0.2, 0.4, 0.55, 0.7, 0.85, 0.95, 0.15 }),
    })
    for _, site in ipairs(r.spawn) do
        T.eq(M.inCorridor({ corridor() }, site, M.DEFAULTS.corridorMarginM), nil)
    end
end

cases.spawning_respects_the_server_ceiling = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = {},
        settings = { pedBudget = 2, vehicleBudget = 0, spawnPerTick = 10 },
        rng = seq({ 0.1, 0.4, 0.6, 0.2, 0.8, 0.3 }),
    })
    local peds, cars = 0, 0
    for _, s in ipairs(r.spawn) do
        if s.kind == "ped" then peds = peds + 1 else cars = cars + 1 end
    end
    T.eq(peds, 2); T.eq(cars, 0)
end

cases.spawning_respects_the_per_player_cap = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = {},
        settings = { perPlayerPeds = 1, perPlayerVehicles = 1, spawnPerTick = 10 },
        rng = seq({ 0.1, 0.4, 0.6, 0.2, 0.8, 0.3 }),
    })
    T.eq(#r.spawn, 2)
end

cases.a_crowded_player_gets_nothing_new = function(T)
    local ents = {}
    for i = 1, 10 do ents[i] = E("p" .. i, "ped", 150 + i, 0, true) end
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0) },
        entities = ents,
        settings = { perPlayerPeds = 10, perPlayerVehicles = 0, spawnPerTick = 4 },
        rng = seq({ 0.1, 0.4 }),
    })
    T.eq(#r.spawn, 0)
end

cases.spawn_is_capped_per_tick_across_every_player = function(T)
    local r = M.plan({
        now = 100,
        players = { P(1, 0, 0), P(2, 3000, 0), P(3, 6000, 0) },
        entities = {},
        settings = { spawnPerTick = 2 },
        rng = seq({ 0.1, 0.4, 0.6, 0.2 }),
    })
    T.eq(#r.spawn, 2)
end

cases.plan_does_not_mutate_its_input = function(T)
    local state = {
        now = 100,
        players = { P(1, 0, 0) },
        entities = { E("a", "ped", 150, 0, false) },
        settings = { spawnPerTick = 3 },
        rng = seq({ 0.1, 0.4, 0.6 }),
    }
    local first = M.plan(state)
    state.rng = seq({ 0.1, 0.4, 0.6 })
    local second = M.plan(state)
    T.eq(#first.spawn, #second.spawn)
    T.eq(first.spawn[1].x, second.spawn[1].x)
    T.eq(#state.players, 1); T.eq(#state.entities, 1)
    T.eq(state.pending, nil)
end

cases.an_empty_world_plans_nothing = function(T)
    local r = M.plan({ now = 0 })
    T.eq(#r.spawn, 0); T.eq(#r.despawn, 0); T.eq(r.counts.ped, 0)
end

cases.plan_refuses_a_non_table = function(T)
    local r, why = M.plan("no")
    T.eq(r, nil); T.eq(why, "invalid_state")
end

-- ------------------------------------------------------------------ the hold window

cases.the_corridor_opens_at_the_lead_time = function(T)
    local e = { startsAt = 1000 }
    T.eq(M.isHeldClear(e, 1000 - 241), false)
    T.eq(M.isHeldClear(e, 1000 - 239), true)
end

cases.a_slot_nobody_entered_holds_no_road = function(T)
    -- The defect this exists for: 21 scheduled starts in a three-hour window on the shipped cadence, most
    -- of them with nobody in them. Holding a corridor for each merged into one continuous interval.
    T.eq(M.isHeldClear({ startsAt = 1000, entrants = 0 }, 900), false)
    T.eq(M.isHeldClear({ startsAt = 1000, entrants = 1 }, 900), true)
    -- An unknown count is not a zero: a caller with no number to give gets the time window alone.
    T.eq(M.isHeldClear({ startsAt = 1000 }, 900), true)
end

cases.a_scheduled_row_stops_holding_shortly_after_its_own_start = function(T)
    -- It may not guess a race length. After the grace, only a live session justifies a corridor.
    local e = { startsAt = 1000, entrants = 2 }
    T.eq(M.isHeldClear(e, 1000 + 119), true)
    T.eq(M.isHeldClear(e, 1000 + 121), false)
end

cases.a_finished_session_releases_after_the_hold = function(T)
    local e = { startsAt = 1000, endedAt = 1200 }
    T.eq(M.isHeldClear(e, 1300), true)
    T.eq(M.isHeldClear(e, 1381), false)
end

cases.a_running_session_holds_however_long_it_overruns = function(T)
    local e = { startsAt = 1000, live = true }
    T.eq(M.isHeldClear(e, 99999), true)
end

cases.a_race_that_overruns_its_estimate_keeps_its_road = function(T)
    -- The live board, not the schedule, is what holds a corridor after the start.
    T.eq(M.isHeldClear({ startsAt = 1000, live = true }, 1000 + 4000), true)
    T.eq(M.isHeldClear({ startsAt = 1000, entrants = 8 }, 1000 + 4000), false)
end

cases.an_event_without_a_start_time_holds_nothing = function(T)
    T.eq(M.isHeldClear({}, 500), false)
    T.eq(M.isHeldClear(nil, 500), false)
end

-- ------------------------------------------------------------------ density and catalogues

cases.the_shared_bucket_is_never_emptied_for_a_corridor = function(T)
    -- THE GUARD. Without it this module empties the city it exists to populate: the vanilla switch has no
    -- radius, and on the shipped cadence a corridor is in its window essentially all the time.
    local may, why = M.maySuppress(0)
    T.eq(may, false); T.eq(why, "shared_bucket")
end

cases.a_bucket_a_race_has_to_itself_may_be_suppressed = function(T)
    local may, why = M.maySuppress(7)
    T.eq(may, true); T.eq(why, "dedicated_bucket")
end

cases.the_shared_bucket_can_be_overridden_but_only_explicitly = function(T)
    local may, why = M.maySuppress(0, { suppressShared = true })
    T.eq(may, true); T.eq(why, "shared_bucket_override")
end

cases.suppression_can_be_switched_off_entirely = function(T)
    local may, why = M.maySuppress(7, { vanillaSuppress = false })
    T.eq(may, false); T.eq(why, "disabled")
    -- off means off, override or not
    T.eq(M.maySuppress(0, { vanillaSuppress = false, suppressShared = true }), false)
end

cases.which_bucket_counts_as_shared_is_configurable = function(T)
    T.eq(M.maySuppress(4, { sharedBucket = 4 }), false)
    T.eq(M.maySuppress(0, { sharedBucket = 4 }), true)
end

cases.the_held_population_is_the_race_one = function(T)
    local p = M.populationFor(true)
    T.eq(p.crowd, 0); T.eq(p.traffic, 0); T.eq(p.police, false)
    local q = M.populationFor(false)
    T.eq(q.crowd, 1.0); T.eq(q.police, true)
end

cases.population_overrides_are_honoured = function(T)
    local p = M.populationFor(false, { crowd = 0.4 })
    T.eq(p.crowd, 0.4)
end

cases.settings_keep_unknown_host_keys = function(T)
    local s = M.settings({ tickSeconds = 7 })
    T.eq(s.tickSeconds, 7)
    T.eq(s.sightM, M.DEFAULTS.sightM)
end

cases.every_ambient_vehicle_is_a_street_record = function(T)
    T.ok(#M.VEHICLE_RECORDS > 0, "catalogue is not empty")
    for _, r in ipairs(M.VEHICLE_RECORDS) do
        T.eq(r:sub(1, 8), "Vehicle.")
        -- no halo cars in traffic: the collection sells those
        T.ok(not r:find("rayfield"), r)
        T.ok(not r:find("rb15"), r)
    end
end

cases.every_ped_record_is_a_character_record = function(T)
    for region, list in pairs(M.PED_RECORDS) do
        T.ok(#list > 0, region .. " is empty")
        for _, r in ipairs(list) do
            T.eq(r:sub(1, 10), "Character.")
        end
    end
end

cases.an_unknown_region_still_answers_with_a_ped = function(T)
    local r = M.pickPed("Atlantis", seq({ 0.5 }))
    T.eq(type(r), "string"); T.eq(r:sub(1, 10), "Character.")
end

cases.region_attribution_comes_from_the_curated_nodes = function(T)
    -- Corpo Plaza is a City Center node at (-1103, -19).
    T.eq(M.regionAt({ x = -1103, y = -19 }), "City Center")
end

cases.a_site_borrows_the_heading_of_the_road_node_it_lands_on = function(T)
    -- Place the player so the first candidate bearing lands within 60 m of a curated node.
    local node = NcmCore.get("data.nodes").LIST[1]
    local s = M.settings({ siteTries = 1, spawnMinM = 100, spawnMaxM = 100 })
    local site = M.site({ id = 1, x = node.x - 100, y = node.y, z = node.z },
        { players = {} }, s, seq({ 0.0, 0.0 }))
    T.ok(site ~= nil, "a site was found")
    T.eq(site.heading, node.heading)
    T.eq(site.region, node.region)
end

cases.a_site_gives_up_rather_than_placing_in_sight = function(T)
    -- Two players bracketing every candidate ring position: nothing can be spawnMinM from both.
    local s = M.settings({ siteTries = 4, spawnMinM = 400, spawnMaxM = 410 })
    local site = M.site({ id = 1, x = 0, y = 0, z = 0 },
        { players = { P(1, 0, 0), P(2, 400, 0), P(3, -400, 0), P(4, 0, 400), P(5, 0, -400) } },
        s, seq({ 0.0, 0.5, 0.25, 0.5, 0.75, 0.5, 0.9, 0.5 }))
    T.eq(site, nil)
end

return cases
