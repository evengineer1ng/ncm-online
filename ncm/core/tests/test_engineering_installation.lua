-- engineering.installation + engineering.controls (L324): the first playable engineering loop, as invariants.
-- The numbers are balance and will move; what must not move is that physics, not purpose, decides what a component
-- does: the same component installed differently is a different Machine.
local function I(T) return T.Core.get("engineering.installation") end
local function Ctl(T) return T.Core.get("engineering.controls") end
local RP, IA = "eng:zetatech:rp16:r1", "eng:archer:ia10:r1"

local function near(T, a, b, tol, msg) T.ok(math.abs(a - b) <= (tol or 1e-6), (msg or "") .. (" (%s vs %s)"):format(tostring(a), tostring(b))) end

local function resolved(T, items)
    local devices, refused = I(T).resolve(items, "archer_hella")
    T.eq(#refused, 0, "every item resolves")
    return devices
end

return {
    the_thrust_axis_is_the_reaction_to_the_facing = function(T)
        local v = I(T).check(I(T).design(RP), "archer_hella", "mount.rear", "aft")
        T.ok(v.ok, v.reason)
        T.eq(v.axis[2], 1, "nozzle aft pushes the Machine forward")
        v = I(T).check(I(T).design(RP), "archer_hella", "mount.underside", "down")
        T.ok(v.ok, v.reason)
        T.eq(v.axis[3], 1, "the same propulsor facing down lifts it")
        v = I(T).check(I(T).design(RP), "archer_hella", "mount.front", "left")
        T.ok(v.ok, v.reason)
        T.eq(v.axis[1], 1, "facing left shoves it right")
    end,

    every_refusal_is_physical = function(T)
        local M = I(T)
        T.falsy(M.check(M.design(RP), "archer_hella", "mount.rear", "fore").ok, "a rear mount cannot fire into the car")
        local v = M.check(M.design(IA), "archer_hella", "mount.rear", "down")
        T.falsy(v.ok, "53 kN on a 30 kN hardpoint")
        T.match(v.reason, "structural", "says why")
        T.falsy(M.check(M.design(RP), "no_such_car", "mount.rear", "aft").ok, "no hardpoint profile")
        T.falsy(M.check(M.design(RP), "archer_hella", "mount.wing", "aft").ok, "no such mount")
        T.falsy(M.check(M.design(RP), "archer_hella", "mount.rear", "sideways").ok, "no such facing")
        T.falsy(M.check({ family = "tires", perf = {} }, "archer_hella", "mount.rear", "aft").ok, "factory families are not add-ons")
    end,

    the_component_does_not_know_its_vehicle = function(T)
        -- nothing in the design names the Hella: any catalogued Machine has the same hardpoints
        local M = I(T)
        T.ok(M.check(M.design(RP), "thorton_galena", "mount.rear", "aft").ok, "fits a Galena")
        T.ok(M.check(M.design(RP), "makigai_maimai", "mount.rear", "aft").ok, "fits a MaiMai")
        T.eq(M.design(RP).family, "propulsor", "")
        T.eq(M.design(RP).perf.kind, "reaction_engine", "a propulsor is a reaction engine, not a flight mode")
    end,

    a_propulsor_pushes_along_its_axis_and_burns_fuel = function(T)
        local M = I(T)
        local d = resolved(T, { { componentId = "c1", designId = RP, mountId = "mount.rear", facing = "aft" } })
        local s = M.newState(d)
        local r
        for _ = 1, 240 do r = M.step(d, s, { c1 = { throttle = 1 } }, 1 / 60, 100) end   -- 4 s: past the throttle lag
        near(T, r.force[2], 30000, 1, "full forward thrust")
        near(T, r.force[1], 0, 1e-9, "no side force")
        near(T, r.force[3], 0, 1e-9, "no lift")
        T.ok(r.propellantKg > 0, "it burns")
        near(T, r.propellantKg, 30000 / (2000 * 9.80665) / 60, 1e-6, "F / (Isp g0) per step")
        -- off-centre mount: a rear push above the CoM pitches the nose down (torque about x, the right axis)
        T.ok(math.abs(r.torque[1]) > 0, "an off-CoM mount makes torque")
    end,

    no_fuel_no_thrust = function(T)
        local M = I(T)
        local d = resolved(T, { { componentId = "c1", designId = RP, mountId = "mount.rear", facing = "aft" } })
        local s = M.newState(d)
        local r = M.step(d, s, { c1 = { throttle = 1 } }, 1 / 60, 0)
        T.eq(r.force[2], 0, "an empty tank pushes nothing")
        T.ok(r.out.c1.starved, "and says it was starved")
    end,

    an_uncommanded_component_does_nothing = function(T)
        local M = I(T)
        local d = resolved(T, { { componentId = "c1", designId = RP, mountId = "mount.rear", facing = "aft" },
            { componentId = "c2", designId = IA, mountId = "mount.underside", facing = "down" } })
        local s = M.newState(d)
        local r = M.step(d, s, {}, 1 / 60, 50)
        T.eq(r.force[1] + r.force[2] + r.force[3], 0, "installed but inactive is inert")
        T.eq(r.propellantKg, 0, "and free")
    end,

    a_discharge_is_one_exact_impulse_at_any_frame_rate = function(T)
        local M = I(T)
        for _, hz in ipairs({ 30, 60, 144 }) do
            local d = resolved(T, { { componentId = "a", designId = IA, mountId = "mount.underside", facing = "down" } })
            local s = M.newState(d)
            local dt, impulse, fired = 1 / hz, 0, 0
            for i = 1, hz do
                local r = M.step(d, s, i == 1 and { a = { discharge = true } } or {}, dt, 50)
                impulse = impulse + r.force[3] * dt
                fired = fired + r.pulses
            end
            T.eq(fired, 1, "one discharge per command")
            near(T, impulse, 53000 * 0.2, 1e-6, hz .. " Hz: forceN x pulseS")
        end
    end,

    the_hop_points_where_the_car_points = function(T)
        -- the legacy hop pushed WORLD up; an installed actuator pushes along the car's up -- tumbling is real
        local M = I(T)
        local w = M.toWorld({ 0, 0, 1 }, { right = { 1, 0, 0 }, forward = { 0, 0, 1 }, up = { 0, -1, 0 } })   -- nose straight up
        near(T, w[2], -1, 1e-9, "car's up is now world -y")
        near(T, w[3], 0, 1e-9, "and no longer world up")
        w = M.toWorld({ 0, 1, 0 }, { right = { x = 1, y = 0, z = 0 }, forward = { x = 0, y = 0, z = 1 }, up = { x = 0, y = -1, z = 0 } })
        near(T, w[3], 1, 1e-9, "a rear propulsor with the nose up drives straight up")
        T.eq(M.toWorld({ 1, 0, 0 }, {}), nil, "no basis, no force")
    end,

    overheating_shuts_it_down_until_it_cools = function(T)
        local M = I(T)
        local d = resolved(T, { { componentId = "c1", designId = RP, mountId = "mount.rear", facing = "aft" } })
        local s = M.newState(d)
        local hotAt
        for i = 1, 60 * 120 do
            local r = M.step(d, s, { c1 = { throttle = 1 } }, 1 / 60, 1e6)
            if r.out.c1.hot then hotAt = i / 60; break end
        end
        T.ok(hotAt and hotAt > 20 and hotAt < 90, "a sustained full burn overheats within a tank or two (" .. tostring(hotAt) .. " s)")
        local r = M.step(d, s, { c1 = { throttle = 1 } }, 1 / 60, 1e6)
        T.ok(r.force[2] < 30000, "hot: thrust falls away")
    end,

    controls_tap_and_hold_share_one_button = function(T)
        local C = Ctl(T)
        local d = resolved(T, { { componentId = "rp", designId = RP, mountId = "mount.rear", facing = "aft" },
            { componentId = "ia", designId = IA, mountId = "mount.underside", facing = "down" } })
        local b = {
            { control = "padY", gesture = "tap", componentId = "ia", command = "discharge" },
            { control = "padY", gesture = "hold", componentId = "rp", command = "throttle" },
        }
        local st = C.newState()
        local c = C.step(st, b, d, { padY = true }, 1000)
        T.eq(c.ia and c.ia.discharge, true, "the hop answers the press, not the release")
        c = C.step(st, b, d, { padY = false }, 1080)
        T.eq(c.ia, nil, "releasing does not fire it again")
        c = C.step(st, b, d, { padY = true }, 2000)
        c = C.step(st, b, d, { padY = true }, 2100)
        T.eq(c.rp, nil, "not yet a hold")
        c = C.step(st, b, d, { padY = true }, 2200)
        T.eq(c.rp and c.rp.throttle, 1, "past HOLD_MS it throttles")
        c = C.step(st, b, d, { padY = false }, 2600)
        T.eq(c.ia, nil, "releasing a hold fires nothing")
        T.eq(c.rp, nil, "and the throttle closes")
    end,

    a_lone_tap_fires_on_the_press = function(T)
        local C = Ctl(T)
        local d = resolved(T, { { componentId = "ia", designId = IA, mountId = "mount.underside", facing = "down" } })
        local b = { { control = "padY", gesture = "tap", componentId = "ia", command = "discharge" } }
        local c = C.step(C.newState(), b, d, { padY = true }, 0)
        T.eq(c.ia and c.ia.discharge, true, "nothing to wait for: mashing stays instant")
    end,

    bindings_check_against_the_component = function(T)
        local C = Ctl(T)
        local d = resolved(T, { { componentId = "rp", designId = RP, mountId = "mount.rear", facing = "aft" } })[1]
        T.ok(C.check({ control = "padY", gesture = "hold", componentId = "rp", command = "throttle" }, d), "")
        local ok, why = C.check({ control = "padY", gesture = "tap", componentId = "rp", command = "throttle" }, d)
        T.falsy(ok, "an analog command cannot be tapped")
        ok, why = C.check({ control = "padY", gesture = "tap", componentId = "rp", command = "discharge" }, d)
        T.falsy(ok, "a propulsor has no discharge")
        T.match(why, "throttle", "and says what it does take")
        T.eq(C.normalize("triangle"), "padY", "")
        T.eq(C.normalize("h"), "H", "")
        T.falsy(C.normalize("F13"), "")
    end,

    an_uninstalled_component_stops_answering = function(T)
        local C = Ctl(T)
        local b = { { control = "padY", gesture = "held", componentId = "gone", command = "throttle" } }
        local c = C.step(C.newState(), b, {}, { padY = true }, 0)
        T.eq(next(c), nil, "a binding to nothing commands nothing")
    end,

    one_control_can_command_several_propulsors = function(T)
        local C = Ctl(T)
        local d = resolved(T, { { componentId = "front", designId = RP, mountId = "mount.front", facing = "down" },
            { componentId = "rear", designId = RP, mountId = "mount.rear", facing = "down" } })
        local b = { { control = "padY", gesture = "hold", componentId = "front", command = "throttle" },
            { control = "padY", gesture = "hold", componentId = "rear", command = "throttle" } }
        local c = C.step(C.newState(), b, d, { padY = true }, 0)
        T.eq(c.front and c.front.throttle, 1, "the front one")
        T.eq(c.rear and c.rear.throttle, 1, "and the rear one, together")
        local M = I(T)
        local s = M.newState(d)
        local r
        for _ = 1, 240 do r = M.step(d, s, c, 1 / 60, 100) end
        near(T, r.force[3], 60000, 2, "two 30 kN propulsors facing down: 60 kN of lift")
    end,

    mashing_the_hop_is_nearly_continuous_like_the_old_one = function(T)
        -- owner: waiting out each stroke made the hop "take insane mashing". Every press restarts the stroke now.
        local M, C = I(T), Ctl(T)
        local d = resolved(T, { { componentId = "ia", designId = IA, mountId = "mount.underside", facing = "down" } })
        local b = { { control = "padY", gesture = "tap", componentId = "ia", command = "discharge" } }
        local s, cs = M.newState(d), C.newState()
        local up, fired = 0, 0
        for f = 0, 59 do                                   -- one second at 60 Hz, pressing 8 times (down 2 frames of every 7)
            local down = (f % 7) < 2
            local cmds = C.step(cs, b, d, { padY = down }, f * 1000 / 60)
            local r = M.step(d, s, cmds, 1 / 60, 100)
            up, fired = up + r.force[3] / 60, fired + r.pulses
        end
        T.ok(fired >= 8, "every press is a stroke (" .. fired .. ")")
        T.ok(up > 53000 * 0.85, ("~continuous 53 kN while mashing (mean %.0f N)"):format(up))
    end,
}
