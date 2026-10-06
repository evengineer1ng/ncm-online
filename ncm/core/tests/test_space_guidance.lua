-- space.venues + space.guidance (L327): Assetto Corsa tracks as places on NCM Earth, and an autopilot that FLIES there.
local function D(T) return T.Core.get("space.deep") end
local function G(T) return T.Core.get("space.guidance") end
local function VN(T) return T.Core.get("space.venues") end

--- Fly a route with the owner's Hella numbers: 1,925 kg, one 30 kN RP-16 at the rear (thrust axis = forward), the
--- attitude assist turning at up to 1 rad/s. Returns arrived?, seconds, lowest altitude.
local function fly(T, venueId, maxS)
    local M, Gd = D(T), G(T)
    local s = M.enter({ 0, 0, 12000 }, { 0, 0, 80 }, nil)
    local route = Gd.plan(s, VN(T).get(venueId))
    local mass, thrust, dt = 1925, 30000, 0.1
    local lowest, t = 1e12, 0
    while t < maxS do
        local cmd = Gd.command(route, s, thrust / mass)
        Gd.point(s.basis, { 0, 1, 0 }, cmd.dir, 1.0 * dt)
        local f = M.machineToEcef({ 0, thrust * cmd.throttle, 0 }, s.basis)
        M.step(s, dt, { f[1] / mass, f[2] / mass, f[3] / mass })
        t = t + dt
        local _, _, alt = M.ecefToLla(s.p)
        if alt < lowest then lowest = alt end
        if Gd.arrived(route, s) then return true, t, lowest, route end
    end
    return false, t, lowest, route
end

--- Fly the way the client does (KB-349): n RP-16s with their real thermal model, the budget's caps on each throttle,
--- starting at game height `z` with vertical speed `vz`. Returns arrived?, seconds, lowest altitude, seconds hot.
local function flyHot(T, venueId, n, z, vz, maxS)
    local M, Gd = D(T), G(T)
    local I = T.Core.get("engineering.installation")
    local d = I.design("eng:zetatech:rp16:r1")
    local devices = {}
    for i = 1, n do devices[i] = { componentId = "rp" .. i, kind = "reaction_engine", perf = d.perf, thermal = d.thermal, axis = { 0, 1, 0 }, pos = { 0, 0, 0.5 } } end
    local st = I.newState(devices)
    local s = M.enter({ 0, 0, z }, { 0, 0, vz }, nil)
    local route = Gd.plan(s, VN(T).get(venueId))
    local mass, dt, t, lowest, hot = 1840 + 85 * n, 0.1, 0, 1e12, 0
    while t < maxS do
        local _, nowN, caps = Gd.thrustBudget(devices, st)
        local cmd = Gd.command(route, s, nowN / mass)
        Gd.point(s.basis, { 0, 1, 0 }, cmd.dir, 1.0 * dt)
        local cmds = {}
        for _, dv in ipairs(devices) do cmds[dv.componentId] = { throttle = cmd.throttle * caps[dv.componentId] } end
        local f = M.machineToEcef(I.step(devices, st, cmds, dt, 1e9).force, s.basis)
        M.step(s, dt, { f[1] / mass, f[2] / mass, f[3] / mass })
        t = t + dt
        for _, dv in ipairs(devices) do if st.dev[dv.componentId].hot then hot = hot + dt end end
        local _, _, alt = M.ecefToLla(s.p)
        if alt < lowest then lowest = alt end
        if alt < 0 then return false, t, lowest, hot end
        if Gd.arrived(route, s) then return true, t, lowest, hot end
    end
    return false, t, lowest, hot
end

return {
    the_registry_is_real_places_only = function(T)
        local V = VN(T)
        T.ok(#V.VENUES >= 17, "17 real venues installed")
        T.ok(V.get("monza") and V.get("spa") and V.get("laguna_seca") and V.get("nordschleife"), "the brief's examples are there")
        T.eq(V.get("ks_black_cat_county"), nil, "fictional tracks are not given Earth coordinates")
        T.eq(V.UNREGISTERED.ks_highlands, "fictional", "and say why")
        for _, v in ipairs(V.VENUES) do
            T.ok(v.lat > -90 and v.lat < 90 and v.lon > -180 and v.lon < 180, v.id .. " has a real position")
            T.ok(v.track and #v.layouts >= 1, v.id .. " names its AC track")
        end
    end,

    one_clock_many_local_times = function(T)
        local V = VN(T)
        local utc = 20730 * 86400 + 12 * 3600       -- a UTC noon (day 20730 since the epoch)
        local monzaH = V.localHour(V.get("monza"), utc)
        local lagunaH = V.localHour(V.get("laguna_seca"), utc)
        T.eq(math.floor(monzaH + 0.5), 13, "noon UTC is 13:00 at Monza")
        T.eq(math.floor(lagunaH + 0.5), 4, "and 04:00 at Laguna Seca: the same instant")
        T.ok(V.daylight(V.get("monza"), utc), "Monza is in daylight")
        T.falsy(V.daylight(V.get("laguna_seca"), utc), "Laguna Seca is dark")
    end,

    the_route_never_cuts_through_the_earth = function(T)
        local M, Gd = D(T), G(T)
        local s = M.enter({ 0, 0, 12000 }, { 0, 0, 0 }, nil)
        local r = Gd.plan(s, VN(T).get("monza"))
        T.ok(#r.waypoints >= 5, "a long trip is a chain of waypoints")
        local prev = s.p
        for _, w in ipairs(r.waypoints) do
            -- the chord's midpoint must be above ground
            local mid = M.vec.scale(M.vec.add(prev, w.p), 0.5)
            local _, _, alt = M.ecefToLla(mid)
            T.ok(alt > 0, "chord midpoint above ground (" .. math.floor(alt) .. " m)")
            prev = w.p
        end
    end,

    the_autopilot_flies_the_hella_to_laguna_seca = function(T)
        local ok, t, lowest, route = fly(T, "laguna_seca", 3600)
        T.ok(ok, ("arrives in the envelope (%.0f s)"):format(t))
        -- an AC venue takes the Machine LOW (HOST_ARRIVE_ABOVE_M): never under 40 m above its ground on the way down
        local ground = route.venue.alt or 0
        T.ok(lowest > ground + 40, ("never near the ground on the way (lowest %.0f m above the venue)"):format(lowest - ground))
    end,

    the_autopilot_flies_the_hella_to_monza = function(T)
        local ok, t, lowest, route = fly(T, "monza", 4 * 3600)
        T.ok(ok, ("arrives in the envelope (%.0f s)"):format(t))
        -- an AC venue takes the Machine LOW (HOST_ARRIVE_ABOVE_M): never under 40 m above its ground on the way down
        local ground = route.venue.alt or 0
        T.ok(lowest > ground + 40, ("never near the ground on the way (lowest %.0f m above the venue)"):format(lowest - ground))
    end,

    -- KB-349, 06:42: engaged at 21 km already falling 409 m/s, the old controller spent its clipped thrust on cruise
    -- speed and went into the ground at a constant ~405 m/s on full throttle. Altitude comes first now.
    engaged_while_falling_it_stops_the_fall_first = function(T)
        local M, Gd = D(T), G(T)
        local s = M.enter({ 0, 0, 21000 }, { 0, 0, -409 }, nil)
        local route = Gd.plan(s, VN(T).get("silverstone"))
        local mass, thrust, dt, lowest = 1925, 30000, 0.1, 1e12
        for _ = 1, 1200 do
            local cmd = Gd.command(route, s, thrust / mass)
            Gd.point(s.basis, { 0, 1, 0 }, cmd.dir, 1.0 * dt)
            local f = M.machineToEcef({ 0, thrust * cmd.throttle, 0 }, s.basis)
            M.step(s, dt, { f[1] / mass, f[2] / mass, f[3] / mass })
            local _, _, alt = M.ecefToLla(s.p)
            if alt < lowest then lowest = alt end
        end
        T.ok(lowest >= Gd.FLOOR_M * 0.8, ("the fall is stopped above the floor (lowest %.0f m)"):format(lowest))
    end,

    -- KB-349, 06:37: one RP-16 sheds a third of the heat it makes at full throttle, so on the 1.9 t Hella it can hold
    -- 10 kN against 19 kN of weight. Guidance must say so, not take off and fall.
    one_rp16_cannot_hold_the_hella_up_and_guidance_says_why = function(T)
        local Gd = G(T)
        local d = T.Core.get("engineering.installation").design("eng:zetatech:rp16:r1")
        local sus = Gd.thrustBudget({ { componentId = "a", kind = "reaction_engine", perf = d.perf, thermal = d.thermal } }, nil)
        T.ok(math.abs(sus - 10000) < 1, ("sustained thrust is what it can shed (%.0f N)"):format(sus))
        local ok, tw, why = Gd.feasible(sus, 1925)
        T.falsy(ok, "refused")
        T.ok(tw < 1 and type(why) == "string" and why:find("kN"), "with the numbers: " .. tostring(why))
        -- the DEVELOPMENT heat waiver (owner, IDEA-1143): heat not modelled, the same Hella flies
        local dev = { { componentId = "a", kind = "reaction_engine", perf = d.perf, thermal = d.thermal } }
        local hot = { dev = { a = { heatK = 999, hot = true } } }
        local susDev, nowDev, caps = Gd.thrustBudget(dev, hot, true)
        T.eq(susDev, 30000, "dev waiver: all 30 kN is sustained")
        T.eq(nowDev, 30000, "and available even from a hot state")
        T.eq(caps.a, 1, "uncapped")
        T.ok((Gd.feasible(susDev, 1925)), "guidance accepts the one-RP-16 Hella on dev")
    end,

    three_rp16s_fly_to_laguna_seca_without_ever_overheating = function(T)
        local ok, t, lowest, hot = flyHot(T, "laguna_seca", 3, 12000, 80, 3600)
        T.ok(ok, ("arrives (%.0f s)"):format(t))
        T.ok(lowest > 40, ("never near the ground (lowest %.0f m)"):format(lowest))
        T.eq(hot, 0, "no propulsor ever reaches its thermal shutdown")
    end,

    three_rp16s_engaged_falling_still_reach_monza = function(T)
        local ok, t, lowest, hot = flyHot(T, "monza", 3, 21000, -409, 4 * 3600)
        T.ok(ok, ("arrives (%.0f s)"):format(t))
        T.ok(lowest > 40, ("never near the ground (lowest %.0f m)"):format(lowest))
        T.eq(hot, 0, "no thermal shutdown")
    end,

    -- owner, 2026-10-06: "I don't fall out of the sky gracefully": an AC venue receives the Machine low and slow
    an_ac_venue_takes_the_machine_low_and_slow = function(T)
        local M, Gd = D(T), G(T)
        local ok, _, _, route = fly(T, "laguna_seca", 3600)
        T.ok(ok, "arrives")
        T.eq(route.arriveAbove, Gd.HOST_ARRIVE_ABOVE_M, "with the host envelope")
        local r2 = Gd.plan(M.enter({ 0, 0, 12000 }, { 0, 0, 0 }, nil), { id = "x", name = "x", lat = 40, lon = -100, alt = 0 })
        T.eq(r2.arriveAbove, Gd.ARRIVE_ABOVE_M, "a place with no host keeps the high envelope")
    end,
}
