-- space.canonical (L329): the host-independent Deep record, and the offline flight ("autopilot keeps going").
local function CN(T) return T.Core.get("space.canonical") end
local function D(T) return T.Core.get("space.deep") end

local function rp16s(T, n)
    local I = T.Core.get("engineering.installation")
    local d = I.design("eng:zetatech:rp16:r1")
    local out = {}
    for i = 1, n do out[i] = { componentId = "rp" .. i, code = d.code, kind = "reaction_engine", perf = d.perf, thermal = d.thermal,
        axis = { 0, 1, 0 }, pos = { 0, 0, 0.5 } } end
    return out
end

local function record(T, z, vz, extra)
    local s = D(T).enter({ 0, 0, z }, { 0, 0, vz }, nil)
    return CN(T).fromDeep(s, 1000000, extra)
end

--- Propagate in host-sized slices, the way the server must (never one giant call).
local function run(T, r, toUtc)
    local done, info, last = false, nil, {}
    local guard = 0
    repeat
        r, done, info = CN(T).propagate(r, toUtc, 2000)
        if info.arrived then last.arrived = true end
        if info.landed then last.landed = true end
        if info.fuelOut then last.fuelOut = true end
        guard = guard + 1
    until done or guard > 1000
    return r, last
end

return {
    the_record_round_trips_without_loss = function(T)
        local s = D(T).enter({ 120, -40, 15000 }, { 3, 4, 50 }, nil)
        local r = CN(T).fromDeep(s, 123456, { asset = "a1", host = "cyberpunk" })
        local s2 = CN(T).toDeep(r)
        for i = 1, 3 do
            T.ok(math.abs(s2.p[i] - s.p[i]) < 1e-6 and math.abs(s2.v[i] - s.v[i]) < 1e-9, "position and velocity survive")
            T.ok(math.abs(s2.basis.forward[i] - s.basis.forward[i]) < 1e-12, "attitude survives")
        end
        T.eq(r.asset, "a1", "identity rides along")
        local la, lo = CN(T).where(r)
        T.ok(math.abs(la - 35.37) < 0.01 and math.abs(lo + 120.85) < 0.02, "it is over Night City")
    end,

    offline_the_autopilot_keeps_flying_to_laguna_seca = function(T)
        -- L331: on the full model it needs something to turn it -- here the development attitude waiver (labelled)
        local r = record(T, 15000, 0, { massKg = 1925, devices = rp16s(T, 1), devFuel = true, devHeat = true, devAttitude = true,
            guidance = { venueId = "laguna_seca", engaged = true } })
        local t0 = r.utc
        local r2, ev = run(T, r, t0 + 36 * 3600)
        T.ok(ev.arrived, "it arrived while nobody was playing")
        T.eq(r2.place, "deep", "and is still flying (holding over the venue), not on the ground")
        local la, lo, alt = CN(T).where(r2)
        local d = D(T).distance(la, lo, 36.5843, -121.7535)
        T.ok(d < 20000, ("holding near Laguna Seca after 36 h (%.1f km away, %.0f m up)"):format(d / 1000, alt))
        T.eq(r2.utc, t0 + 36 * 3600, "every second of the 36 hours was integrated")
    end,

    offline_without_guidance_gravity_flies_it = function(T)
        local r = record(T, 15000, 50, { massKg = 1925, devices = {} })
        local t0 = r.utc
        local r2, ev = run(T, r, t0 + 3600)
        T.ok(ev.landed, "it came down")
        T.eq(r2.place, "landed", "the record says where")
        local fall = r2.landed.utc - t0
        T.ok(fall > 40 and fall < 120, ("a 15 km climb-and-fall lands in about a minute (%.0f s)"):format(fall))
    end,

    offline_fuel_runs_out_and_the_flight_ends_honestly = function(T)
        local r = record(T, 15000, 0, { massKg = 1925, devices = rp16s(T, 3), fuelKg = 2.0, devHeat = false, devAttitude = true,
            guidance = { venueId = "monza", engaged = true } })
        local r2, ev = run(T, r, r.utc + 6 * 3600)
        T.ok(ev.fuelOut, "two kilograms do not reach Monza")
        T.eq(r2.fuelKg, 0, "the tank is empty")
        T.eq(r2.place, "landed", "and then gravity: it came down short")
    end,

    a_landed_record_does_not_move = function(T)
        local r = { place = "landed", landed = { lat = 1, lon = 2 }, utc = 10 }
        local r2, done = CN(T).propagate(r, 99999)
        T.ok(done, "nothing to integrate")
        T.eq(r2.utc, 99999, "only the clock advances")
    end,

    -- KB-360: a record that goes through JSON (the server, the bridge, the database) keeps its position
    the_record_survives_json = function(T)
        local J = T.Core.get("vocabulary.json")
        local s = D(T).enter({ 1234.5, -987.25, 15000.75 }, { 3.25, 4.5, 50.125 }, nil)
        local r = CN(T).fromDeep(s, 1791320018.4, {})
        local r2 = J.decode(J.encode(r))
        for i = 1, 3 do T.ok(math.abs(r2.p[i] - r.p[i]) < 0.01, ("position survives (%.3f m off)"):format(math.abs(r2.p[i] - r.p[i]))) end
        T.ok(math.abs(r2.utc - r.utc) < 0.01, "the clock survives")
    end,

    -- L331: the full machine model -- a Machine that cannot turn itself is not flown by the autopilot
    offline_a_machine_that_cannot_point_is_not_flown = function(T)
        local r = record(T, 15000, 0, { devices = rp16s(T, 1), devFuel = true, devHeat = true,
            guidance = { venueId = "laguna_seca", engaged = true } })
        local _, _, info = CN(T).propagate(r, r.utc + 5, 100)
        T.ok(info.cannotPoint, "no attitude part, no waiver: guidance cannot turn it")
        local r2, ev = run(T, r, r.utc + 3600)
        T.ok(ev.landed and r2.place == "landed", "and gravity has it")
    end,

    offline_the_ac6_flies_it_physically = function(T)
        local I = T.Core.get("engineering.installation")
        local devices = I.resolve({
            { componentId = "rp", designId = "eng:zetatech:rp16:r1", mountId = "mount.rear", facing = "aft" },
            { componentId = "ac", designId = "eng:zetatech:ac6:r1", mountId = "mount.roof", facing = "up" },
        }, "archer_hella")
        local r = record(T, 15000, 0, { vehicleKey = "archer_hella", devices = devices, devFuel = true, devHeat = true,
            guidance = { venueId = "laguna_seca", engaged = true } })
        local r2, ev = run(T, r, r.utc + 3 * 3600)
        T.ok(ev.arrived, "the AC-6 turns it; the RP-16 flies it there, no waiver")
        T.eq(r2.place, "deep", "holding over the venue")
    end,
}
