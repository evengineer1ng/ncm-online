-- L334: Deep to the KSA border -- the Fusion Drive FD-1, the Propellant Tank PT-500, the gimbal, and Guidance to Earth's
-- sphere of influence (the border: 98 % of KSA's own, ~854,000 km), live and offline.
local function mods(T)
    local C = T.Core
    return C.get("space.deep"), C.get("space.guidance"), C.get("engineering.flightmodel"), C.get("engineering.installation"),
        C.get("engineering.dynamics"), C.get("space.canonical")
end

local function hella(T, opts)
    local D, G, F, I = mods(T)
    opts = opts or {}
    local ids = {}
    for _, d in ipairs(I.DESIGNS) do ids[d.code] = d.designId end
    local items = {
        { componentId = "fd", designId = ids["ZTC-FD1"], mountId = "mount.rear", facing = "aft" },
        { componentId = "pt", designId = ids["ZTC-PT500"], mountId = "mount.front", facing = "up", fillKg = opts.fillKg or 500 },
        { componentId = "ia", designId = ids["ARC-IA10"], mountId = "mount.underside", facing = "down" },
        { componentId = "ac", designId = ids["ZTC-AC6"], mountId = "mount.roof", facing = "up" },
    }
    local devices, refused = I.resolve(items, "archer_hella")
    local m = F.build(devices, { vehicleKey = "archer_hella", fuelKg = 44 })
    local e, n, u = D.enu(35.37, -120.85)
    local ds = { p = D.llaToEcef(35.37, -120.85, 12100), v = D.vec.scale(u, 90), basis = { right = e, forward = u, up = D.vec.scale(n, -1) } }
    return m, F.state(m, ds), ds, devices, refused
end

return {
    the_drive_and_tank_fit_the_hella = function(T)
        local _, _, _, I = mods(T)
        local m, s, ds, devices, refused = hella(T)
        T.eq(#refused, 0, "FD-1 rear facing aft, PT-500 front: both mate")
        local fd, pt
        for _, d in ipairs(devices) do if d.code == "ZTC-FD1" then fd = d elseif d.code == "ZTC-PT500" then pt = d end end
        T.ok(fd and fd.perf.propellant == "fusion" and fd.perf.thrustN <= I.mount("mount.rear").ratedN, "the drive burns fusion, inside the rear rating")
        T.eq(pt.fillKg, 500, "the tank carries its own fill")
    end,

    each_part_burns_its_own_propellant = function(T)
        local _, _, _, I = mods(T)
        local _, _, _, devices = hella(T)
        local st = I.newState(devices)
        local fdId
        for _, d in ipairs(devices) do if d.code == "ZTC-FD1" then fdId = d.componentId end end
        local cmds = { [fdId] = { throttle = 1 } }
        for _ = 1, 60 do I.step(devices, st, cmds, 0.1, { fuel = 44, fusion = 500 }) end
        local r = I.step(devices, st, cmds, 0.1, { fuel = 44, fusion = 500 })
        T.ok((r.byPropellant.fusion or 0) > 0, "the FD-1 drew fusion")
        T.ok(not r.byPropellant.fuel, "and none of the car's fuel")
        local dry = I.step(devices, I.newState(devices), cmds, 0.1, { fuel = 44, fusion = 0 })
        T.eq(dry.out[fdId].thrustN, 0, "no fusion, no thrust (the car's fuel cannot feed it)")
    end,

    the_gimbal_trims_the_thrust_through_the_centre_of_mass = function(T)
        local _, _, F, _, Dyn = mods(T)
        local m, s = hella(T)
        local fdIndex
        for i, d in ipairs(m.devices) do if d.kind == "reaction_engine" then fdIndex = i end end
        local tel
        for _ = 1, 8 do s, tel = F.step(m, s, { throttle = { [fdIndex] = 1 }, torqueNm = { 0, 0, 0 } }, 0.25, { devFuel = false }) end
        local tq = tel.torque or { 0, 0, 0 }
        T.ok(math.abs(tq[1]) < 50 and math.abs(tq[3]) < 50, ("full thrust, near-zero pitch/yaw torque (%.0f, %.0f N m)"):format(tq[1], tq[3]))
    end,

    the_border_is_within_reach_and_says_so_when_not = function(T)
        local D, G = mods(T)
        local m, s, ds = hella(T)
        local ok, need, have = G.borderBudget(ds, 2600, 28000, 100000, 500)
        T.ok(ok and have > need, ("full tank: %.0f km/s needed, %.0f available"):format(need / 1000, have / 1000))
        local ok2 = G.borderBudget(ds, 2150, 28000, 100000, 50)
        T.falsy(ok2, "50 kg of fusion cannot reach the border")
        T.ok(G.target("ksa_border").radiusM < G.KSA_SOI_M and G.target("ksa_border").radiusM > 0.95 * G.KSA_SOI_M,
            "the border sits just inside KSA's own Earth sphere of influence")
    end,

    guidance_flies_the_hella_to_the_border = function(T)
        local D, G, F, _, Dyn = mods(T)
        local m, s, ds = hella(T)
        local route = G.planBorder(ds)
        local t, minAlt, arrived = 0, 1e18, false
        while t < 5 * 3600 do
            -- the physical attitude law near the ground, the waiver (1 s steps) far out: same thrust, cheaper test
            local far = t > 1200
            local cmd, wv = G.fly(route, m, s, { waiver = far })
            local dt = far and 1.0 or 0.25
            s = F.step(m, s, cmd, dt, { waiver = wv })
            t = t + dt
            local _, _, alt = D.ecefToLla(s.pos)
            if t > 5 then minAlt = math.min(minAlt, alt) end
            if G.arrived(route, { p = s.pos, v = s.vel }) then arrived = true; break end
        end
        T.ok(arrived, ("reached the KSA border (after %.2f h)"):format(t / 3600))
        T.ok(t < 4.5 * 3600, "in under 4.5 hours")
        T.ok(minAlt > 12000, ("never sank below where it started (min %.0f m)"):format(minAlt))
        T.ok(Dyn.propellantLeft(m, s, "fusion") > 25, ("with propellant to spare (%.0f kg)"):format(Dyn.propellantLeft(m, s, "fusion")))
    end,

    offline_flight_reaches_the_border_and_waits_for_ksa = function(T)
        local D, G, F, _, _, CN = mods(T)
        local m, s, ds, devices = hella(T)
        local rec = CN.fromDeep(ds, 1000, { devices = devices, vehicleKey = "archer_hella", fuelKg = 44, devAttitude = true,
            guidance = { venueId = "ksa_border", engaged = true } })
        local done, info = false, nil
        local n = 0
        repeat
            rec, done, info = CN.propagate(rec, 1000 + 5 * 3600, 4000)
            n = n + 1
        until done or n > 200
        T.eq(rec.place, "border", "the record waits at the border")
        T.ok(rec.border and rec.border.host == "ksa", "for KSA")
        T.ok(D.vec.len(rec.p) >= G.BORDER.radiusM, "at the border")
    end,
}
