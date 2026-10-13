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

-- 2026-10-13: one propellant, fast climb -- VL-28E fans and the FC-2 computer, with the FL-6s (the `av` kit now)
local KIT_FUSION = {}
for i, k in ipairs(KIT_LIFT) do
    local d = k[1]
    if d == "eng:zetatech:vl28:r1" then d = "eng:zetatech:vl28:r2" elseif d == "eng:zetatech:fc1:r1" then d = "eng:zetatech:fc1:r2" end
    KIT_FUSION[i] = { d, k[2], k[3] }
end

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

    -- owner: "why am i using car fuel to go to space" / "it takes way too long to get up there"
    the_fusion_atlus_burns_no_car_fuel = function(T)
        local Dyn = T.Core.get("engineering.dynamics")
        local m, devices = atlus(T, KIT_FUSION)
        local s = fly(T, m, devices, {}, 2)
        local fuel, fusion = Dyn.propellantLeft(m, s, "fuel"), Dyn.propellantLeft(m, s, "fusion")
        s = fly(T, m, devices, {}, 10, s)
        -- the lift is all fusion; the only car fuel left is the AC-6 attitude set's trims (shared with the Hella)
        local carPerS = (fuel - Dyn.propellantLeft(m, s, "fuel")) / 10
        T.ok(carPerS < 0.002, ("car fuel %.4f kg/s at hover: the AC-6's trims only (the fans burned ~1.5)"):format(carPerS))
        local perS = (fusion - Dyn.propellantLeft(m, s, "fusion")) / 10
        T.ok(perS > 0 and perS < 0.1, ("fusion pellets %.4f kg/s at hover"):format(perS))
    end,

    the_fc2_climbs_fast_and_comes_down_gently = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local m, devices = atlus(T, KIT_FUSION)
        local s = fly(T, m, devices, { lift = 1 }, 20)
        local pitch, roll = FC.attitude(s.rot)
        T.ok(s.vel[3] > 60, ("climbing %.1f m/s after 20 s"):format(s.vel[3]))
        T.ok(s.pos[3] > 900, ("%.0f m up after 20 s"):format(s.pos[3]))
        T.ok(math.abs(math.deg(pitch)) < 3 and math.abs(math.deg(roll)) < 3, ("level in the climb: %.2f %.2f"):format(math.deg(pitch), math.deg(roll)))
        s = fly(T, m, devices, { lift = -1 }, 40, s)
        T.ok(s.vel[3] > -26 and s.vel[3] < 0, ("descending %.1f m/s (cap 25)"):format(s.vel[3]))
    end,

    -- KB-475 (owner: "everytime i get to deep, the av spirals out and i cant stay in deep or go any higher"): the same
    -- computer flies in Deep's Earth-centred frame through FC.localView, under Earth's gravity and thin air
    in_deep_it_holds_and_climbs_on_fusion = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local Flight = T.Core.get("engineering.flightmodel")
        local Deep = T.Core.get("space.deep")
        local m, devices = atlus(T, KIT_FUSION)
        local lat, lon = Deep.ORIGIN.lat, Deep.ORIGIN.lon
        local e, n, u = Deep.enu(lat, lon)
        local R = Deep.R + 12100
        local s = Dyn.init(m, { pos = { u[1] * R, u[2] * R, u[3] * R }, vel = { 0, 0, 0 },
            rot = { { e[1], n[1], u[1] }, { e[2], n[2], u[2] }, { e[3], n[3], u[3] } } })
        local perf = FC.computer(devices)
        local function deepFly(stick, seconds)
            local dt = 1 / 60
            for _ = 1, math.floor(seconds / dt) do
                local view, alt = FC.localView(s)
                local cmd = FC.step(m, view, stick, { mass = Dyn.mass(m, s), inertia = m.inertia, rho = Flight.density(alt), g = 9.81, contact = false, perf = perf })
                s = Flight.step(m, s, cmd, dt, {})
            end
            local view, alt = FC.localView(s)
            return view, alt
        end
        local view, alt = deepFly({}, 15)
        T.ok(math.abs(alt - 12100) < 30, ("let go in Deep it holds its height: %.0f m"):format(alt))
        local pitch, roll = FC.attitude(view.rot)
        T.ok(math.abs(math.deg(pitch)) < 3 and math.abs(math.deg(roll)) < 3, ("and stays level: %.2f %.2f deg"):format(math.deg(pitch), math.deg(roll)))
        view, alt = deepFly({ lift = 1 }, 20)
        T.ok(alt > 12100 + 600, ("Space climbs on through Deep: %.0f m"):format(alt))
        T.ok(view.vel[3] > 30, ("climbing %.1f m/s"):format(view.vel[3]))
    end,

    -- KB-478 (owner: "takes forever to go anywhere ... why isnt fd available?"): HOLD Triangle burns the FD-1s; the
    -- computer used to write them back to 0 every frame (18:17 local: "pressed padY", both FD-1s 0 %). Burning, every lift
    -- drive runs from full (trimmed for balance), the stick points the Machine, and the burn goes where the nose goes.
    a_driver_burn_is_never_overwritten_and_goes_where_it_points = function(T)
        local FC = T.Core.get("engineering.flightcontrol")
        local Dyn = T.Core.get("engineering.dynamics")
        local Flight = T.Core.get("engineering.flightmodel")
        local Sys = T.Core.get("engineering.systems")
        local Deep = T.Core.get("space.deep")
        local m, devices = atlus(T, KIT_FUSION)
        local fd, isFd = {}, {}
        for _, d in ipairs(devices) do if d.designId == "eng:zetatech:fd1:r1" then isFd[d.componentId] = true end end
        -- by componentId, the way client/deep.lua hands the binding's throttle over
        for i, d in ipairs(m.devices) do if isFd[d.componentId] then fd[#fd + 1] = i end end
        T.eq(#fd, 2, "two FD-1s")
        local burn = { [fd[1]] = 1, [fd[2]] = 1 }
        local lat, lon = Deep.ORIGIN.lat, Deep.ORIGIN.lon
        local e, n, u = Deep.enu(lat, lon)
        local R = Deep.R + 20000
        local s = Dyn.init(m, { pos = { u[1] * R, u[2] * R, u[3] * R }, vel = { 0, 0, 0 },
            rot = { { e[1], n[1], u[1] }, { e[2], n[2], u[2] }, { e[3], n[3], u[3] } } })
        local perf = FC.computer(devices)
        local rho = Flight.density(20000)
        local view = FC.localView(s)
        local cmd0 = FC.step(m, view, {}, { mass = Dyn.mass(m, s), inertia = m.inertia, rho = rho, g = 9.81, perf = perf })
        T.eq(cmd0.throttle[fd[1]], 0, "not burning: the FD-1s stay the computer's thin-air reserve")
        local cmd1, rep = FC.step(m, view, {}, { mass = Dyn.mass(m, s), inertia = m.inertia, rho = rho, g = 9.81, perf = perf, burn = burn })
        T.ok(rep.burn, "the computer knows the driver is burning")
        T.ok(cmd1.throttle[fd[1]] > 0.5 and cmd1.throttle[fd[2]] > 0.5,
            ("both FD-1s burn (%.2f, %.2f): trimmed for balance, never zeroed"):format(cmd1.throttle[fd[1]], cmd1.throttle[fd[2]]))
        local push = 0
        for _, l in ipairs(FC.liftDevices(m)) do push = push + cmd1.throttle[l.index] * Sys.thrustAt(m.devices[l.index].perf, rho, 1) end
        T.ok(push > 140000, ("burning, the lift drives push %.0f kN (FL-6s 120 + FD-1s 60 at full)"):format(push / 1000))
        -- nose forward for 2.5 s, let the stick go, burn on for 20 s: it goes somewhere, fast, and stays pointed
        local dt = 1 / 60
        local pitchAtRelease, hold
        for k = 1, math.floor(21 / dt) do
            local v, alt = FC.localView(s)
            local stick = k * dt < 2.5 and { pitch = 1 } or {}
            -- client/deep.lua's hold: the attitude when the stick was let go
            if k * dt < 2.5 then hold = nil else hold = hold or v.rot end
            if hold and not pitchAtRelease then pitchAtRelease = FC.attitude(v.rot) end
            local cmd = FC.step(m, v, stick, { mass = Dyn.mass(m, s), inertia = m.inertia, rho = Flight.density(alt), g = 9.81, perf = perf, burn = burn, holdRot = hold })
            s = Flight.step(m, s, cmd, dt, {})
        end
        local v = FC.localView(s)
        local pitchEnd = FC.attitude(v.rot)
        T.ok(math.abs(math.deg(pitchEnd - pitchAtRelease)) < 10, ("let go, it stays pointed: %.1f -> %.1f deg"):format(math.deg(pitchAtRelease), math.deg(pitchEnd)))
        local horiz = math.sqrt(v.vel[1] ^ 2 + v.vel[2] ^ 2)
        T.ok(horiz > 150, ("the burn goes where the nose went: %.0f m/s across at %.0f deg (the hover's tilt gave ~0)"):format(horiz, math.deg(pitchEnd)))
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
