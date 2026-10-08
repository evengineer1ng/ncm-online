-- engineering.flightbody + engineering.loadout (aerospace racing brief, 2026-10-07): the Machine, not the filename. The
-- same parts on different Machines make different racing machines because the Machines are physically different.
local function FB(T) return T.Core.get("engineering.flightbody") end
local function LO(T) return T.Core.get("engineering.loadout") end
local function FM(T) return T.Core.get("engineering.flightmodel") end
local function D(T) return T.Core.get("space.deep") end

local function at(T, alt, v)
    local s = D(T).enter({ 0, 0, alt }, v or { 0, 0, 0 }, nil)
    return { p = s.p, v = s.v, basis = s.basis }
end

local function speedAfter(T, m, s, seconds, opts)
    local tel
    for _ = 1, math.floor(seconds / 0.05 + 0.5) do s, tel = FM(T).step(m, s, {}, 0.05, opts) end
    return s, tel
end

return {
    a_body_comes_from_the_passport_with_provenance = function(T)
        local cal = FB(T).forKey("rayfield_caliburn")
        T.eq(cal.family, "supercar", "a vanilla catalogue car is its body family")
        T.eq(cal.prov.massKg.src, "authored", "its mass is the authored seed")
        T.eq(cal.massKg, 1350 + FB(T).DRIVER_KG, "plus its driver")
        T.eq(cal.prov.cd.src, "inferred", "its drag is a family prior, and says so")
        -- a car NCM has never shipped, plugged in by the player's own install: what its host data says, nothing named
        local P = T.Core.get("machine.passport")
        local ow = FB(T).fromPassport(P.fromAc("someones_open_wheeler", { brand = "?", name = "?", class = "race",
            tags = { "open wheel" }, specs = { weight = "720kg", bhp = "900bhp" } }))
        T.eq(ow.family, "formula", "an unknown open-wheeler is an open-wheel body")
        T.eq(ow.prov.massKg.src, "host_data", "its mass is what its host says")
        T.ok(ow.cl < 0, "open wheels make downforce")
        local h = FB(T).forKey("archer_hella")
        T.eq(h.prov.massKg.src, "measured", "the Hella's flown chassis mass is a measurement")
        T.eq(h.massKg, 1800 + FB(T).DRIVER_KG, "1800 kg flown body plus driver")
        local m = FB(T).forKey("rayfield_caliburn", { massKg = 1410 })
        T.eq(m.prov.massKg.src, "measured", "a measured mass wins over the seed")
        local unknown = FB(T).forKey("some_mod_car_nobody_seeded", { tags = { "bike" } })
        T.eq(unknown.family, "bike", "an unknown record still becomes a body, from what the host says")
        T.ok(unknown.prov.massKg.conf <= 0.35, "with low confidence")
    end,

    the_same_kit_on_different_machines_is_F_equals_m_a = function(T)
        local rb, he, bk = LO(T).build("rayfield_caliburn"), LO(T).build("archer_hella"), LO(T).build("arch_nazare")
        for _, f in ipairs({ rb, he, bk }) do T.eq(#f.refused, 0, "the deep_racer fit mates") end
        local function accel(f)
            local m = f.model
            local s = FM(T).state(m, at(T, 600000))   -- vacuum: thrust and gravity only
            local s2, tel = FM(T).step(m, s, { throttle = { fd1 = 1 } }, 0.05, { devFuel = true })
            for _ = 1, 40 do s2, tel = FM(T).step(m, s2, { throttle = { fd1 = 1 } }, 0.05, { devFuel = true }) end
            return FM(T).row(m, s2, tel)
        end
        local a, b, c = accel(rb), accel(he), accel(bk)
        T.ok(math.abs(a.thrustN - b.thrustN) < 1 and math.abs(a.thrustN - c.thrustN) < 1, "identical thrust")
        T.ok(math.abs(a.accel / b.accel - b.massKg / a.massKg) < 1e-6, ("acceleration ratio is the inverse mass ratio (%.2f vs %.2f m/s^2)"):format(a.accel, b.accel))
        T.ok(c.accel > a.accel and a.accel > b.accel, "bike > Caliburn > Hella on the same drive")
    end,

    air_matters_in_air_and_not_in_vacuum = function(T)
        local rb, bk = LO(T).build("rayfield_caliburn").model, LO(T).build("arch_nazare").model
        local function decel(m, alt)
            local d = at(T, alt, { 300, 0, 0 })
            local s = FM(T).state(m, d)
            local v0 = math.sqrt(s.vel[1] ^ 2 + s.vel[2] ^ 2 + s.vel[3] ^ 2)
            local _, tel = FM(T).step(m, s, {}, 0.05, {})
            return tel.qPa or 0, tel
        end
        local qVac = decel(rb, 400000)
        T.eq(qVac, 0, "no dynamic pressure in vacuum")
        -- drag area x dynamic pressure, over mass: a supercar's CdA (~0.65 m^2) vs a bike's (~0.5)
        local rbA, bkA = rb.surfaces[1].perf.cd * rb.surfaces[1].perf.areaM2, bk.surfaces[1].perf.cd * bk.surfaces[1].perf.areaM2
        T.ok(rbA > bkA, ("the supercar's drag area (%.2f) is bigger than the bike's (%.2f)"):format(rbA, bkA))
    end,

    reentry_heats_and_road_speed_does_not = function(T)
        local m = LO(T).build("rayfield_caliburn").model
        local _, road = FM(T).step(m, FM(T).state(m, at(T, 10, { 90, 0, 0 })), {}, 0.05, {})
        T.ok((road.aeroHeatKw or 0) < 1, ("road speed: %.3f kW"):format(road.aeroHeatKw or 0))
        local _, hot = FM(T).step(m, FM(T).state(m, at(T, 60000, { 7000, 0, -500 })), {}, 0.05, {})
        T.ok((hot.aeroHeatKw or 0) > 1000, ("7 km/s at 60 km: %.0f kW"):format(hot.aeroHeatKw or 0))
        -- a hot skin radiates: at the derate threshold, tens of kW
        local s = FM(T).state(m, at(T, 400000))
        s.heatK = 96
        local _, tel = FM(T).step(m, s, {}, 0.05, {})
        T.ok((tel.skinRejectKw or 0) > 5, ("a hot skin sheds %.1f kW in vacuum"):format(tel.skinRejectKw or 0))
    end,

    the_live_hella_path_is_unchanged = function(T)
        local I = T.Core.get("engineering.installation")
        local devices = I.resolve({ { componentId = "rp", designId = "eng:zetatech:rp16:r1", mountId = "mount.rear", facing = "aft" } }, "archer_hella")
        local m = FM(T).build(devices, { vehicleKey = "archer_hella", fuelKg = 40 })
        T.falsy(m.skin, "no body passed: CHASSIS by key, no skin, the flown model as before")
        T.ok(math.abs(m.wetMassKg - (1800 + 85 + 40)) < 1, "same mass as before")
    end,

    hardpoints_sit_on_the_machine_they_are_on = function(T)
        local bk = LO(T).build("arch_nazare")
        local he = LO(T).build("archer_hella")
        local function rear(f) for _, d in ipairs(f.devices) do if d.componentId == "fd1" then return d.pos end end end
        T.ok(math.abs(rear(bk)[2]) < 1.2, ("a 2.3 m bike's rear hardpoint is inside it (%.2f m)"):format(rear(bk)[2]))
        T.ok(math.abs(rear(he)[2]) > 2.1, "the Hella's is where it always was")
    end,

    the_telemetry_row_is_canonical = function(T)
        local f = LO(T).build("rayfield_caliburn")
        local s = FM(T).state(f.model, at(T, 30000, { 0, 0, 500 }))
        local s2, tel = FM(T).step(f.model, s, { throttle = { fd1 = 1 } }, 0.05, {})
        local r = FM(T).row(f.model, s2, tel, { machineId = "m1", driver = "Justina", leg = "ascent" })
        for _, k in ipairs({ "massKg", "thrustN", "accel", "pos", "vel", "vRadial", "vTangential", "altM", "omega", "propellantKg",
            "heatK", "rho", "qPa", "aeroHeatKw", "machineId", "driver", "leg", "family" }) do
            T.ok(r[k] ~= nil, "row has " .. k)
        end
        T.ok(r.vRadial > 400, "climbing: radial velocity")
        T.eq(r.family, "supercar", "and says what it is")
    end,
}
