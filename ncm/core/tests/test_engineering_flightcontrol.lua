-- engineering.flightcontrol: the AV's fly-by-wire, flown through the canonical engineering.dynamics on the Atlus kit.
local function near(T, a, b, tol, msg) T.ok(math.abs((a or 0) - (b or 0)) <= tol, ("%s: %s vs %s"):format(msg or "near", tostring(a), tostring(b))) end
local KEY = "zetatech_atlus_trauma"
local KIT = {
    { "eng:zetatech:vl28:r1", "mount.av.pod.fl", "down" }, { "eng:zetatech:vl28:r1", "mount.av.pod.fr", "down" },
    { "eng:zetatech:vl28:r1", "mount.av.pod.rl", "down" }, { "eng:zetatech:vl28:r1", "mount.av.pod.rr", "down" },
    { "eng:zetatech:fd1:r1", "mount.underside", "down" }, { "eng:zetatech:fd1:r1", "mount.rear", "down" },
    { "eng:zetatech:ac6:r1", "mount.roof", "up" }, { "eng:zetatech:pt500:r1", "mount.av.bay", "fore" },
    { "eng:ncmlab:wh1:r1", "mount.front", "fore" }, { "eng:zetatech:fc1:r1", "mount.electronics", "fore" },
}

-- 2026-10-13: the same Atlus with the two FL-6 fusion lift drives on its belly mounts (the `av` kit now)
local KIT_LIFT = {}
for i, k in ipairs(KIT) do KIT_LIFT[i] = k end
KIT_LIFT[#KIT_LIFT + 1] = { "eng:zetatech:fl6:r1", "mount.av.belly.f", "down" }
KIT_LIFT[#KIT_LIFT + 1] = { "eng:zetatech:fl6:r1", "mount.av.belly.r", "down" }

local function atlus(T, kit)
    kit = kit or KIT
    local Install = T.Core.get("engineering.installation")
    local Flight = T.Core.get("engineering.flightmodel")
    local items = {}
    for i, k in ipairs(kit) do items[i] = { componentId = ("c%02d"):format(i), designId = k[1], mountId = k[2], facing = k[3], fillKg = 400 } end
    local devices, refused = Install.resolve(items, KEY)
    local pushing = {}
    for _, d in ipairs(devices) do if not Install.isElectronic(d.kind) then pushing[#pushing + 1] = d end end
    return Flight.build(pushing, { vehicleKey = KEY, fuelKg = 1100 }), devices, refused
end

local function fly(T, m, devices, stick, seconds, s, rho)
    local FC = T.Core.get("engineering.flightcontrol")
    local Dyn = T.Core.get("engineering.dynamics")
    local perf = FC.computer(devices)
    s = s or Dyn.init(m, { pos = { 0, 0, 100 } })
    local dt = 1 / 60
    for _ = 1, math.floor(seconds / dt) do
        local cmd = FC.step(m, s, stick, { mass = Dyn.mass(m, s), inertia = m.inertia, rho = rho or 1.2, g = 9.81, contact = false, perf = perf })
        Dyn.step(m, s, { g = { 0, 0, -9.81 }, rho = rho or 1.2 }, cmd, dt)
    end
    return s
end

local function find(devices, wh) for _, d in ipairs(devices) do if d.designId == wh then return d end end end

return {
    the_atlus_kit_fits_and_the_pods_are_the_atlus_alone = function(T)
        local Install = T.Core.get("engineering.installation")
        local _, devices, refused = atlus(T)
        T.eq(#refused, 0, "every kit part fits the Atlus: " .. (refused[1] and refused[1].reason or ""))
        T.eq(#devices, #KIT)
        T.ok(find(devices, "eng:ncmlab:wh1:r1"), "the wormhole drive is on it")
        local v = Install.check(Install.design("eng:zetatech:vl28:r1"), "archer_hella", "mount.av.pod.fl", "down")
        T.ok(not v.ok and v.reason:find("no front%-left engine pod"), "a Hella has no engine pods: " .. tostring(v.reason))
    end,

    parked_on_the_ground_it_idles = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local m, devices = atlus(T)
        local s = Dyn.init(m)
        local cmd, rep = FC.step(m, s, {}, { mass = Dyn.mass(m, s), contact = true, perf = FC.computer(devices) })
        T.ok(rep.idle, "idle")
        for _, u in pairs(cmd.throttle) do T.eq(u, 0) end
    end,

    it_hovers_on_its_fans_and_saves_the_fusion = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local m, devices = atlus(T)
        local s = Dyn.init(m, { pos = { 0, 0, 100 } })
        local mass = Dyn.mass(m, s)
        local _, rep = FC.step(m, s, {}, { mass = mass, rho = 1.225, contact = false, perf = FC.computer(devices) })
        T.ok(mass > 6500 and mass < 8000, ("fitted Atlus %.0f kg"):format(mass))
        near(T, rep.uAir, mass * 9.81 / rep.airCapN, 1e-6, "the fans carry the hover")
        T.eq(rep.uRocket, 0, "no fusion burned to hover at sea level")
    end,

    in_thin_air_the_fusion_drives_make_up_the_lift = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local Flight = T.Core.get("engineering.flightmodel")
        local m, devices = atlus(T)
        local s = Dyn.init(m, { pos = { 0, 0, 12000 } })
        local _, rep = FC.step(m, s, {}, { mass = Dyn.mass(m, s), rho = Flight.density(12000), contact = false, perf = FC.computer(devices) })
        T.eq(rep.uAir, 1, "the fans are flat out up there")
        T.ok(rep.uRocket > 0 and rep.uRocket < 1, ("the FD-1s cover the rest (%.2f)"):format(rep.uRocket))
        T.ok(not rep.short, "it can still hold itself at the Deep seam")
    end,

    let_go_it_holds_height_and_level = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local m, devices = atlus(T)
        local s = fly(T, m, devices, {}, 12)
        local pitch, roll = FC.attitude(s.rot)
        T.ok(math.abs(s.pos[3] - 100) < 3, ("height held: %.1f m"):format(s.pos[3]))
        T.ok(math.abs(math.deg(pitch)) < 2 and math.abs(math.deg(roll)) < 2, ("level: pitch %.2f roll %.2f deg"):format(math.deg(pitch), math.deg(roll)))
    end,

    lift_climbs_and_pitch_flies_it_forward = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local m, devices = atlus(T)
        local s = fly(T, m, devices, { lift = 1 }, 6)
        T.ok(s.vel[3] > 6, ("climbing %.1f m/s"):format(s.vel[3]))
        s = fly(T, m, devices, { pitch = 1 }, 8, s)
        local fwd = s.rot[1][2] * s.vel[1] + s.rot[2][2] * s.vel[2]
        local pitch = FC.attitude(s.rot)
        T.ok(fwd > 10, ("flying forward %.1f m/s"):format(fwd))
        T.ok(math.deg(pitch) < -10, ("nose down %.1f deg"):format(math.deg(pitch)))
        T.ok(math.abs(s.vel[3]) < 2, ("height held while flying: vz %.2f"):format(s.vel[3]))
    end,

    yaw_right_turns_it_right = function(T)
        local m, devices = atlus(T)
        local s = fly(T, m, devices, { yaw = 1 }, 2)
        -- forward's world x grows when it turns right from +y (clockwise seen from above)
        T.ok(s.rot[1][2] > 0.3, ("heading swung right: forward x %.2f"):format(s.rot[1][2]))
    end,

    -- owner, 2026-10-13: "we need some fusion drives designed specifically for hauling a trauma team vehicle up ... ran out
    -- of fuel 3km up" (the fans carried it all, ~2 L/s, the FD-1s at 0 %)
    the_fl6_kit_fits_the_atlus = function(T)
        local _, devices, refused = atlus(T, KIT_LIFT)
        T.eq(#refused, 0, "the FL-6s fit the belly mounts: " .. (refused[1] and refused[1].reason or ""))
        T.eq(#devices, #KIT_LIFT)
    end,

    the_fl6s_carry_half_the_hover_and_halve_the_fuel = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local function fuelPerS(kit)
            local m, devices = atlus(T, kit)
            local s = fly(T, m, devices, {}, 2)
            local before = Dyn.propellantLeft(m, s, "fuel")
            s = fly(T, m, devices, {}, 10, s)
            return (before - Dyn.propellantLeft(m, s, "fuel")) / 10, m, s
        end
        local without = fuelPerS(KIT)
        local with, m, s = fuelPerS(KIT_LIFT)
        T.ok(without > 0, ("fans alone burn %.3f kg/s"):format(without))
        T.ok(with < without * 0.6, ("with the FL-6s %.3f kg/s of car fuel (was %.3f)"):format(with, without))
        T.ok(math.abs(s.pos[3] - 100) < 3, ("height held: %.1f m"):format(s.pos[3]))
    end,

    at_the_seam_the_fl6s_hold_it_without_the_torches = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local Flight = T.Core.get("engineering.flightmodel")
        local m, devices = atlus(T, KIT_LIFT)
        local s = Dyn.init(m, { pos = { 0, 0, 12000 } })
        local _, rep = FC.step(m, s, {}, { mass = Dyn.mass(m, s), rho = Flight.density(12000), contact = false, perf = FC.computer(devices) })
        T.ok(not rep.short, "it holds itself at the Deep seam")
        T.ok(rep.uAir < 1, ("lift drives and fans together are not flat out (%.2f)"):format(rep.uAir))
    end,

    with_the_fl6s_it_still_climbs_and_flies_level = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local m, devices = atlus(T, KIT_LIFT)
        local s = fly(T, m, devices, { lift = 1 }, 6)
        T.ok(s.vel[3] > 6, ("climbing %.1f m/s"):format(s.vel[3]))
        s = fly(T, m, devices, {}, 12, s)
        local pitch, roll = FC.attitude(s.rot)
        T.ok(math.abs(math.deg(pitch)) < 2 and math.abs(math.deg(roll)) < 2, ("level: pitch %.2f roll %.2f deg"):format(math.deg(pitch), math.deg(roll)))
    end,

    omega_comes_back_from_two_attitudes = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local m = atlus(T)
        local s = Dyn.init(m, { omega = { 0.3, -0.2, 0.5 } })
        local before = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
        Dyn.step(m, s, { g = { 0, 0, 0 }, rho = 0 }, {}, 0.01)
        local w = FC.omegaFrom(before, s.rot, 0.01)
        near(T, w[1], 0.3, 0.01); near(T, w[2], -0.2, 0.01); near(T, w[3], 0.5, 0.01)
    end,
}
