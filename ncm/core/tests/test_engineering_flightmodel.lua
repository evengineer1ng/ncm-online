-- engineering.flightmodel (L331): Deep on the full machine model -- the same Machine, forces that change with the world.
local function FM(T) return T.Core.get("engineering.flightmodel") end
local function I(T) return T.Core.get("engineering.installation") end
local function D(T) return T.Core.get("space.deep") end

--- The owner's Hella as installed: RP-16 rear facing aft, IA-10 underside facing down (+ optional AC-6, an off-centre RP-16).
local function hella(T, extra)
    local items = {
        { componentId = "rp", designId = "eng:zetatech:rp16:r1", mountId = "mount.rear", facing = "aft" },
        { componentId = "ia", designId = "eng:archer:ia10:r1", mountId = "mount.underside", facing = "down" },
    }
    for _, it in ipairs(extra or {}) do items[#items + 1] = it end
    local devices, refused = I(T).resolve(items, "archer_hella")
    T.eq(#refused, 0, "the install resolves")
    return devices
end

local function at(T, alt, vz)
    local s = D(T).enter({ 0, 0, alt }, { 0, 0, vz or 0 }, nil)
    return { p = s.p, v = s.v, basis = s.basis }
end

local function run(T, m, s, cmd, seconds, opts, dt)
    dt = dt or 0.02
    local tel
    for _ = 1, math.floor(seconds / dt + 0.5) do s, tel = FM(T).step(m, s, cmd, dt, opts) end
    return s, tel
end

return {
    the_install_is_a_machine = function(T)
        local m = FM(T).build(hella(T), { vehicleKey = "archer_hella", fuelKg = 40 })
        T.ok(math.abs(m.wetMassKg - (1800 + 85 + 40 + 40)) < 1, ("chassis + parts + fuel (%.0f kg)"):format(m.wetMassKg))
        T.eq(#m.devices, 2, "two pushing devices")
        T.ok(m.inertia[1] > 2000 and m.inertia[3] > 2000, "a car's inertia, not a point")
    end,

    the_hella_today_cannot_point_itself = function(T)
        local m = FM(T).build(hella(T), { vehicleKey = "archer_hella", fuelKg = 40 })
        local ok, why = FM(T).canPoint(m, false)
        T.falsy(ok, "centreline parts give no yaw or roll")
        T.ok(why:find("yaw none") and why:find("AC%-6"), "and it says what is missing: " .. why)
        T.ok((FM(T).canPoint(m, true)), "the development waiver lets it (labelled)")
        local m2 = FM(T).build(hella(T, { { componentId = "ac", designId = "eng:zetatech:ac6:r1", mountId = "mount.roof", facing = "up" } }),
            { vehicleKey = "archer_hella", fuelKg = 40 })
        T.ok((FM(T).canPoint(m2, false)), "with the AC-6 installed it can, physically")
    end,

    off_centre_thrust_cartwheels = function(T)
        -- a second RP-16 under the floor facing aft: 30 kN below the CoM pitches the nose up, hard (the roof mount is
        -- rated 20 kN and refuses an RP-16 -- structure is physical too)
        local m = FM(T).build(hella(T, { { componentId = "rp2", designId = "eng:zetatech:rp16:r1", mountId = "mount.underside", facing = "aft" } }),
            { vehicleKey = "archer_hella", fuelKg = 40 })
        local s = FM(T).state(m, at(T, 30000))
        s = run(T, m, s, { throttle = { rp2 = 1 } }, 3, { devFuel = true, devHeat = true })
        local w = math.sqrt(s.omega[1] ^ 2 + s.omega[2] ^ 2 + s.omega[3] ^ 2)
        T.ok(w > 0.5, ("it spins (%.2f rad/s): engineering, not an animation"):format(w))
        local m0 = FM(T).build(hella(T), { vehicleKey = "archer_hella", fuelKg = 40 })
        local s0 = run(T, m0, FM(T).state(m0, at(T, 30000)), { throttle = { rp = 1 } }, 3, { devFuel = true, devHeat = true })
        local w0 = math.sqrt(s0.omega[1] ^ 2 + s0.omega[2] ^ 2 + s0.omega[3] ^ 2)
        T.ok(w0 < w / 4, ("the rear RP-16 near the CoM line barely turns it (%.3f rad/s)"):format(w0))
    end,

    the_hop_is_a_stroke_with_a_kick = function(T)
        local m = FM(T).build(hella(T), { vehicleKey = "archer_hella", fuelKg = 40 })
        local s = FM(T).state(m, at(T, 30000))
        local v0 = { s.vel[1], s.vel[2], s.vel[3] }
        s = run(T, m, s, { discharge = { ia = true } }, 0.02, { devFuel = true }, 0.02)
        s = run(T, m, s, {}, 0.3, { devFuel = true }, 0.02)
        local dv = math.sqrt((s.vel[1] - v0[1]) ^ 2 + (s.vel[2] - v0[2]) ^ 2 + (s.vel[3] - v0[3]) ^ 2)
        local gdv = 9.7 * 0.32   -- gravity over the same 0.32 s, straight against the stroke
        local expect = 53000 * 0.2 / m.wetMassKg
        T.ok(math.abs(dv - (expect - gdv)) < 0.2, ("one stroke up against gravity: %.2f m/s (impulse %.2f, gravity %.2f)"):format(dv, expect, gdv))
        -- L360 addendum: the floor pan is centred, so an underside stroke goes through the centre of mass
        T.ok(math.abs(s.omega[1]) < 1e-6, ("an underside stroke does not pitch it (%.2e rad/s)"):format(s.omega[1]))
    end,

    air_thins_with_altitude = function(T)
        local F = FM(T)
        T.ok(F.density(0) > 1.2 and F.density(40000) < 0.02 and F.density(400000) == 0, "sea level, 40 km, orbit")
        local m = F.build({}, { vehicleKey = "archer_hella" })
        -- falling from 3 km: drag holds it near the car's terminal speed in thick air
        local s = run(T, m, F.state(m, at(T, 3000, -60)), {}, 20, {}, 0.05)
        local v = math.sqrt(s.vel[1] ^ 2 + s.vel[2] ^ 2 + s.vel[3] ^ 2)
        -- a car's terminal speed at sea level: sqrt(2 m g / (rho Cd A)) ~ 200 m/s
        T.ok(v < 210, ("held under the car's terminal speed in air (%.0f m/s)"):format(v))
        local s2 = run(T, m, F.state(m, at(T, 60000, -60)), {}, 20, {}, 0.05)
        local v2 = math.sqrt(s2.vel[1] ^ 2 + s2.vel[2] ^ 2 + s2.vel[3] ^ 2)
        T.ok(v2 > 240 and v2 > v + 50, ("near vacuum it just falls (%.0f m/s)"):format(v2))
    end,

    a_part_overheats_and_shuts_itself_down = function(T)
        local m = FM(T).build(hella(T), { vehicleKey = "archer_hella", fuelKg = 40 })
        local s = FM(T).state(m, at(T, 30000))
        local hot = false
        for _ = 1, 3000 do
            local tel
            s, tel = FM(T).step(m, s, { throttle = { rp = 1 } }, 0.05, { devFuel = true })
            for _, st in pairs(s.dev) do if st.hot then hot = true end end
            if hot then break end
        end
        T.ok(hot, "the RP-16 at full reaches its limit and stops (one sheds a third of its heat)")
        local s2 = FM(T).state(m, at(T, 30000))
        for _ = 1, 3000 do s2 = FM(T).step(m, s2, { throttle = { rp = 1 } }, 0.05, { devFuel = true, devHeat = true }) end
        for _, st in pairs(s2.dev) do T.falsy(st.hot, "the development heat waiver keeps it cool") end
    end,

    the_waiver_turns_it_and_says_so = function(T)
        local F = FM(T)
        local m = F.build(hella(T), { vehicleKey = "archer_hella", fuelKg = 40 })
        local s = F.state(m, at(T, 30000))
        local up = D(T).vec.unit(s.pos)
        local tel
        s, tel = run(T, m, s, {}, 3, { waiver = { dir = up, axis = { 0, 1, 0 }, rate = 1.0 } })
        local fw = { s.rot[1][2], s.rot[2][2], s.rot[3][2] }
        T.ok(D(T).vec.dot(fw, up) > 0.99, "the nose points up")
        T.ok(tel.waiver, "telemetry: not physical")
    end,

    the_ac6_turns_it_physically_and_burns_fuel = function(T)
        local F = FM(T)
        local m = F.build(hella(T, { { componentId = "ac", designId = "eng:zetatech:ac6:r1", mountId = "mount.roof", facing = "up" } }),
            { vehicleKey = "archer_hella", fuelKg = 40 })
        local s = F.state(m, at(T, 30000))
        local f0 = F.fuelKg(m, s)
        s = run(T, m, s, { torque = { 0, 0, 1 } }, 1, {})
        T.ok(s.omega[3] > 0.2, ("full yaw command spins it up (%.2f rad/s)"):format(s.omega[3]))
        T.ok(F.fuelKg(m, s) < f0, ("and costs fuel (%.2f kg)"):format(f0 - F.fuelKg(m, s)))
    end,
}
