-- paddock.live: physical-authoritative Paddock races, the pure half (doc 44 §12, phase 5).
local function route(T)
    return T.Core.get("course.routes").resolve("root_parque_del_mar_2326_1125__to__gold_niwaki_plaza_264_304")
end

-- A synthetic ghost: an L-shaped road from the route's start to its finish, 10 Hz.
local function ghost(r)
    local poses, t = {}, 0
    local corner = { x = r.start.x, y = r.finish.y }
    local function leg(a, b, n)
        for i = 0, n - 1 do
            local f = i / n
            poses[#poses + 1] = { t = t, x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = 10, yaw = 0 }
            t = t + 0.1
        end
    end
    leg(r.start, corner, 400); leg(corner, r.finish, 400)
    poses[#poses + 1] = { t = t, x = r.finish.x, y = r.finish.y, z = 10, yaw = 0 }
    return poses
end

-- Drive a car along the path at `mps`, sampling every `dtMs`, feeding the timing sheet.
local function drive(L, timing, id, points, mps, dtMs, stopAtM)
    local t, travelled = 0, 0
    L.observe(timing, id, points[1], 0)
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local d = L.dist(a, b)
        local steps = math.max(1, math.floor(d / (mps * dtMs / 1000)))
        for k = 1, steps do
            if stopAtM and travelled >= stopAtM then return t end
            local f = k / steps
            t = t + math.floor(d / steps / mps * 1000)
            travelled = travelled + d / steps
            L.observe(timing, id, { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = 10 }, t)
        end
    end
    -- carry on past the finish so the finish line is crossed, not merely reached
    local last, before = points[#points], points[#points - 1]
    local dx, dy = last.x - before.x, last.y - before.y
    local len = math.sqrt(dx * dx + dy * dy)
    L.observe(timing, id, { x = last.x + dx / len * 40, y = last.y + dy / len * 40, z = 10 }, t + 1000)
    return t
end

return {
    path_comes_from_a_ghost_within_the_followRoute_limit = function(T)
        local L = T.Core.get("paddock.live")
        local r = route(T)
        local p = L.path(r, ghost(r))
        T.eq(p.source, "ghost")
        T.ok(#p.points <= L.MAX_POINTS, "at most 64 points")
        T.ok(#p.points >= 16, "a real line, not two points")
        T.ok(L.dist(p.points[1], r.start) < 1 and L.dist(p.points[#p.points], r.finish) < 1, "it starts and ends on the route")
        local direct = L.path(r, nil)
        T.eq(direct.source, "direct"); T.eq(#direct.points, 2)
        local tiny = L.resample({ { x = 0, y = 0 }, { x = 10, y = 0 } }, 500)
        T.ok(#tiny <= L.MAX_POINTS, "resample never exceeds the limit")
    end,

    yaw_is_redengine_convention = function(T)
        local L = T.Core.get("paddock.live")
        T.ok(math.abs(L.yawFromDir(0, 1) - 0) < 1e-6, "+Y is yaw 0")
        T.ok(math.abs(L.yawFromDir(1, 0) - 270) < 1e-6, "+X is yaw 270 (-90)")
        T.ok(math.abs(L.yawFromDir(-1, 0) - 90) < 1e-6, "-X is yaw 90")
    end,

    speed_plan_mirrors_each_cars_sim_pace_under_the_cap = function(T)
        local L = T.Core.get("paddock.live")
        local r = route(T)
        local p = L.path(r, ghost(r))
        local segs = 6
        local fast, slow = {}, {}
        for s = 1, segs do fast[s] = math.floor(s * p.lengthM / segs / 40 * 1000); slow[s] = math.floor(s * p.lengthM / segs / 30 * 1000) end
        local a = L.speedPlan(p.points, p.lengthM, fast, segs, 55)
        local b = L.speedPlan(p.points, p.lengthM, slow, segs, 55)
        T.eq(#a, #p.points - 1, "one ceiling per leg")
        for i = 1, #a do
            T.ok(a[i] > b[i], "the faster sim driver has the higher ceiling on leg " .. i)
            T.ok(a[i] <= 55 and b[i] >= L.MIN_MPS, "within [MIN, cap]")
        end
        local capped = L.speedPlan(p.points, p.lengthM, fast, segs, 30)
        for i = 1, #capped do T.ok(capped[i] <= 30, "the platform cap holds") end
        local dnf = L.speedPlan(p.points, p.lengthM, { fast[1], fast[2] }, segs, 55)
        T.eq(#dnf, #p.points - 1, "a sim DNF still gets a full plan")
    end,

    timing_orders_the_field_and_the_verdict_is_physical = function(T)
        local L = T.Core.get("paddock.live")
        local r = route(T)
        local p = L.path(r, ghost(r))
        local gates = L.checkpoints(r, p, 6)
        T.eq(#gates, 7, "start, five splits, finish")
        local field = { { id = "p1", orgId = "o1" }, { id = "p2", orgId = "o2" }, { id = "p3", orgId = "o3" }, { id = "p4", orgId = "o4" } }
        local timing = L.newTiming(gates, { "p1", "p2", "p3", "p4" })
        drive(L, timing, "p1", p.points, 30, 250)
        drive(L, timing, "p2", p.points, 40, 250)
        drive(L, timing, "p3", p.points, 35, 250)
        drive(L, timing, "p4", p.points, 45, 250, 900)          -- crashes out early
        T.ok(timing.cars.p2.done and timing.cars.p1.done and timing.cars.p3.done, "three cars crossed every gate")
        T.falsy(timing.cars.p4.done, "the crasher did not")
        for g = 3, #gates do T.ok(timing.cars.p2.times[g] > timing.cars.p2.times[g - 1], "gates in order") end
        local c = L.classify(timing, field, { p4 = "contact" })
        T.eq(c.verdict, "physical")
        T.eq(c.entrants[1].id, "p2"); T.eq(c.entrants[2].id, "p3"); T.eq(c.entrants[3].id, "p1")
        T.eq(c.entrants[1].gapMs, 0); T.ok(c.entrants[2].gapMs > 0)
        T.eq(c.entrants[4].state, "dnf"); T.eq(c.entrants[4].dnfReason, "contact")
        T.eq(c.entrants[2].grid, 3, "grid is where they started")
    end,

    too_few_finishers_or_disagreeing_times_fall_back_to_the_sim = function(T)
        local L = T.Core.get("paddock.live")
        local r = route(T)
        local p = L.path(r, ghost(r))
        local gates = L.checkpoints(r, p, 4)
        local field = { { id = "a" }, { id = "b" }, { id = "c" }, { id = "d" } }
        local timing = L.newTiming(gates, { "a", "b", "c", "d" })
        drive(L, timing, "a", p.points, 40, 250)
        drive(L, timing, "b", p.points, 30, 250, 500)
        drive(L, timing, "c", p.points, 30, 250, 700)
        local c = L.classify(timing, field, {})
        T.eq(c.verdict, "fallback", "one finisher of four is not a race")
        -- corroboration against Pace DLL times
        local t2 = L.newTiming(gates, { "a", "b" })
        drive(L, t2, "a", p.points, 40, 250)
        drive(L, t2, "b", p.points, 35, 250)
        local client = { a = {}, b = {} }
        for g = 2, #gates do client.a[g] = t2.cars.a.times[g] + 120; client.b[g] = t2.cars.b.times[g] - 90 end
        local ok = L.corroborate(t2, client)
        T.ok(ok, "times within tolerance corroborate")
        client.b[#gates] = client.b[#gates] + 5000
        local ok2, why = L.corroborate(t2, client)
        T.falsy(ok2); T.eq(why.reason, "disagree")
        T.eq(L.classify(t2, { { id = "a" }, { id = "b" } }, {}, { clientOk = false }).verdict, "fallback")
        T.falsy(L.corroborate(t2, nil), "no client times, no pace corroboration")
    end,

    the_grid_is_single_players_and_a_stuck_car_goes_back_on_the_line = function(T)
        local L = T.Core.get("paddock.live")
        local Profiles = T.Core.get("data.grid_profiles")
        local r = route(T)
        local p = L.path(r, ghost(r))
        local gates = L.checkpoints(r, p, 6)
        local slots = L.gridSlots(r.start, r.finish, 12, Profiles.forRoot(r.routeId))
        for i = 3, 12 do T.ok(math.abs(L.dist(slots[i], slots[i - 2]) - 12) < 0.01, "SP rows: 12 m apart") end
        T.ok(math.abs(L.dist(slots[1], slots[2]) - 8) < 0.01, "SP columns: 4 m either side")
        T.ok(math.abs(L.dist(slots[1], r.start) - math.sqrt(12 * 12 + 4 * 4)) < 0.01, "SP setback: pole 12 m behind the node")
        T.eq(slots[1].z, r.start.z, "every slot at the start node's height, like SP")
        T.eq(slots[1].row, 1); T.eq(slots[12].row, 6)
        -- the Sewer profile rotates the whole grid 180 degrees (the owner's SP tuning)
        local sewer = T.Core.get("course.routes").resolve("root_north_tunnel_1450_2467__to__japantown_crossway_373_0")
        local plain = L.gridSlots(sewer.start, sewer.finish, 2, Profiles.forRoot("none"))
        local tuned = L.gridSlots(sewer.start, sewer.finish, 2, Profiles.forRoot(sewer.routeId))
        local d = (plain[1].heading - tuned[1].heading) % 360
        T.ok(math.abs(d - 180) < 0.01, "Sewer's gridHeadingOffsetDeg -180 is applied")
        -- SP's launch for Sewer (L234): a gentle capped release, then race minimums at 74% of the ceiling
        local lp = L.launchProfile(Profiles.forRoot(sewer.routeId))
        T.eq(lp.relMax, 18, "Sewer release cap is SP's 18 m/s")
        T.eq(lp.relForced, 4, "Sewer release forced start is SP's 4 m/s")
        T.eq(lp.relDist, 5, "Sewer release target distance is SP's 5 m")
        T.ok(math.abs(lp.minFrac - 0.74) < 1e-9, "race minimum fraction is aiMinSpeedFrac + SP's race term")
        T.ok(math.abs(lp.recommandS - 3.1) < 1e-9 and math.abs(lp.stallMps - 5.5) < 1e-9 and math.abs(lp.stallS - 1.9) < 1e-9,
            "recommand and stall follow SP's race-active terms")
        local off = { x = p.points[20].x + 30, y = p.points[20].y }
        local rp = L.resetPoint(p.points, off)
        T.ok(rp.index <= 20 and rp.index >= 18, "reset goes to the line just behind the car (" .. rp.index .. ")")
        T.ok(L.distToPath(p.points, p.points[10]) < 0.01, "on the line is zero from the line")
        T.ok(math.abs(L.distToPath(p.points, off) - 30) < 31, "off the line is measured to the line")
        -- a slow car is not stuck: 5 m/s sampled every 250 ms moves 1.25 m a sample
        local timing = L.newTiming(gates, { "slow" })
        for k = 0, 160 do L.observe(timing, "slow", { x = r.start.x + k * 1.25, y = r.start.y }, k * 250) end
        T.falsy(L.stalled(timing, "slow", 40000, 8), "a car making slow way is still racing")
        L.forget(timing, "slow", 41000)
        T.falsy(timing.cars.slow.lastPos, "a moved car's last sample is forgotten, so the jump crosses no gate")
        T.eq(L.leaderMs(timing), nil, "no leader before anyone finishes")
    end,

    a_stopped_car_is_stalled = function(T)
        local L = T.Core.get("paddock.live")
        local r = route(T)
        local gates = L.checkpoints(r, L.path(r, nil), 1)
        local timing = L.newTiming(gates, { "x" })
        L.observe(timing, "x", { x = r.start.x, y = r.start.y }, 0)
        L.observe(timing, "x", { x = r.start.x + 1, y = r.start.y }, 20000)
        T.falsy(L.stalled(timing, "x", 25000))
        T.ok(L.stalled(timing, "x", 31000), "no progress for 30 s")
        T.falsy(L.allDone(timing, {}))
        T.ok(L.allDone(timing, { x = "stalled" }))
    end,
}
