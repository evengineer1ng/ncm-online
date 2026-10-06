-- ncm-core module: engineering.installation
--
-- L324: a physical component on a physical Machine. The first playable engineering loop:
--
--   component asset -> compatible (or not) with a mount -> installed at a POSITION with a FACING -> fed from the
--   Machine's own resources -> told what to do through its COMMANDS -> its output is a force in the Machine frame
--   -> the host turns that into a world-space force on the rigid body.
--
-- Nothing here knows the word "flight". A propulsor pushes along its installed thrust axis because that is what it
-- physically does; mounted at the rear facing aft it drives the Machine forward, under the floor facing down it lifts
-- it, on the roof facing left it shoves it sideways. Whatever that turns out to be useful for is the player's
-- discovery, not this file's (doc 54 §D, the L324 brief: "the component does not know its purpose").
--
-- Machine frame (as engineering.machine): x right, y forward, z up, metres, origin at the chassis reference point.
--
-- FACING is where the business end points -- the nozzle, the stroke face. The force on the Machine is the reaction,
-- so the THRUST AXIS is -facing. Stored per installation (machine_configuration_item.install_json), never inferred.
--
-- MOUNTS are discrete hardpoints for now (rear, underside, roof, front). Each carries a position, the facings the
-- body of the car leaves open, and a structural rating. Named mounts are a stand-in for geometry, not a replacement
-- for it: a later pass can make the position free without changing anything that reads `pos` and `axis`.
local Core = NcmCore

Core.define("engineering.installation", function(C)
    local M = { version = "0.1.0" }
    local Sys = C.get("engineering.systems")
    local Vehicles = C.get("data.vehicle_catalogue")

    M.FACINGS = {
        aft = { 0, -1, 0 }, fore = { 0, 1, 0 }, down = { 0, 0, -1 }, up = { 0, 0, 1 },
        left = { -1, 0, 0 }, right = { 1, 0, 0 },
    }
    M.FACING_ORDER = { "aft", "fore", "down", "up", "left", "right" }

    --- The hardpoint standard every v1 mount and v1 add-on component shares. A future standard is a new string.
    M.STANDARD = "hardpoint.h1"

    --- Generic hardpoints for a road car (the Hella is ~4.6 m long). `blocked` facings would fire into the car's
    --- own body. `ratedN` is the sustained force the mount's structure takes; past it the fit is refused.
    M.MOUNTS = {
        { id = "mount.rear",      label = "rear bumper hardpoint", pos = { 0, -2.2, 0.55 }, ratedN = 30000, blocked = { fore = true } },
        { id = "mount.underside", label = "floor-pan hardpoint",   pos = { 0, 0.1, 0.15 },  ratedN = 60000, blocked = { up = true } },
        { id = "mount.roof",      label = "roof hardpoint",        pos = { 0, -0.3, 1.45 }, ratedN = 20000, blocked = { down = true } },
        { id = "mount.front",     label = "front bumper hardpoint", pos = { 0, 2.2, 0.55 }, ratedN = 30000, blocked = { aft = true } },
    }
    local mountById = {}
    for _, m in ipairs(M.MOUNTS) do mountById[m.id] = m end
    function M.mount(id) return mountById[id] end
    function M.isMount(interfaceId) return mountById[interfaceId] ~= nil end

    --- Families that install on a mount (add-ons), as opposed to the effect-scalar families that replace a
    --- factory component at a fixed interface (parts.catalogue). Handling composition must never see these.
    M.FAMILIES = { propulsor = true, impulse_actuator = true, attitude = true }
    function M.isAddOnFamily(family) return M.FAMILIES[family] == true end

    -- ------------------------------------------------------------------------------------------ designs
    --- The first two physical components. Revision 1 of each lineage. Numbers are physical (SI) and are the
    --- balance: a heavier Machine gets less out of the same thrust, and that is the point.
    M.DESIGNS = {
        {
            designId = "eng:zetatech:rp16:r1", lineageId = "eng:zetatech:rp16", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-RP16", family = "propulsor",
            name = "Reaction Propulsor RP-16",
            subtitle = "Sustained reaction thrust along its installed axis. Burns the Machine's own fuel.",
            interface = "hardpoint.h1", massKg = 85, envelope = { 0.5, 1.1, 0.5 }, price = 6500,
            -- owner, 2026-10-06: 16 kN (< 1 g on the Hella) "weakened the crap out of" forward push. 30 kN = the rear
            -- hardpoint's rating, ~1.7 g on the 1.8 t body. Same design id: dev balance, not a new revision.
            perf = { kind = "reaction_engine", thrustN = 30000, ispS = 2000, propellant = "fuel", seaLevelFactor = 1.0,
                throttleTauS = 0.25, minThrottle = 0, heatKw = 600 },
            thermal = { capacityKjK = 40, rejectKw = 200, limitK = 450, resumeK = 300 },
        },
        {
            designId = "eng:archer:ia10:r1", lineageId = "eng:archer:ia10", revision = 1,
            manufacturer = "Archer", makerKey = "archer", code = "ARC-IA10", family = "impulse_actuator",
            name = "Impulse Actuator IA-10",
            subtitle = "One short reaction stroke per discharge. Works in the air. Burns the Machine's own fuel.",
            interface = "hardpoint.h1", massKg = 40, envelope = { 0.6, 0.6, 0.25 }, price = 3200,
            -- matches the hop the owner already flies (NCM Thrust twr 3.0 x 200 ms on the 1,800 kg Hella body)
            -- rechargeS 0 + `retrigger`: every press starts a fresh stroke even mid-stroke, like NCM Thrust's hop ("interrupted
            -- by the next burn"); owner: waiting out each stroke made the hop "take insane mashing" (3/s measured vs ~8/s).
            perf = { kind = "pulse_reaction", forceN = 53000, pulseS = 0.2, ispS = 3000, propellant = "fuel", rechargeS = 0,
                retrigger = true, heatKj = 0 },
        },
        -- L331: the first ATTITUDE part. On the full machine model a car only turns if something on it makes torque;
        -- the Hella's RP-16 and IA-10 sit on the centreline, so without this it cannot point. Reaction-control
        -- micro-thrusters in opposed pairs: torque about every axis, no net force, burning the Machine's own fuel.
        -- Sized from the Hella's inertia (~3,500 kg m^2 in pitch and yaw): a quarter turn in about three seconds.
        {
            designId = "eng:zetatech:ac6:r1", lineageId = "eng:zetatech:ac6", revision = 1,
            manufacturer = "Zetatech", makerKey = "zetatech", code = "ZTC-AC6", family = "attitude",
            name = "Attitude Control Set AC-6",
            subtitle = "Turns the Machine about any axis. Burns the Machine's own fuel.",
            interface = "hardpoint.h1", massKg = 30, envelope = { 0.6, 0.6, 0.3 }, price = 5400,
            perf = { kind = "attitude_control", torqueNm = 1500, armM = 1.0, ispS = 220, propellant = "fuel", heatKw = 40 },
            thermal = { capacityKjK = 20, rejectKw = 25, limitK = 300, resumeK = 150 },
        },
    }
    local designById = {}
    for _, d in ipairs(M.DESIGNS) do designById[d.designId] = d end
    function M.design(id) return designById[id] end

    --- Peak force a design can put through its mount (N).
    function M.peakForceN(d)
        local p = d and d.perf or {}
        return p.thrustN or p.forceN or 0
    end

    -- ------------------------------------------------------------------------------------------ fitment
    local function neg(v) return { -v[1], -v[2], -v[3] } end

    --- Can design `d` go on `mountId` of a `vehicleKey` Machine, pointing `facing`? Returns a verdict table:
    --- { ok, reason, mount, axis } -- `axis` is the thrust axis in the Machine frame. Every refusal is physical.
    function M.check(d, vehicleKey, mountId, facing)
        if type(d) ~= "table" or not d.perf then return { ok = false, reason = "not an installable component" } end
        if not M.isAddOnFamily(d.family) then return { ok = false, reason = "this component replaces a factory part; fit it with the Parts inventory" } end
        local ok, errs = Sys.validate(d.perf)
        if not ok then return { ok = false, reason = "component data invalid: " .. table.concat(errs, "; ") } end
        if not (vehicleKey and Vehicles.byKey(vehicleKey)) then return { ok = false, reason = "no hardpoint profile for this Machine" } end
        local m = mountById[mountId or ""]
        if not m then return { ok = false, reason = "no such mount (" .. tostring(mountId) .. ")" } end
        if d.interface ~= M.STANDARD then return { ok = false, reason = ("interface %s does not mate with %s"):format(tostring(d.interface), M.STANDARD) } end
        local f = M.FACINGS[facing or ""]
        if not f then return { ok = false, reason = "facing must be one of: " .. table.concat(M.FACING_ORDER, ", ") } end
        if m.blocked[facing] then return { ok = false, reason = ("facing %s from the %s would fire into the Machine's own body"):format(facing, m.label) } end
        local peak = M.peakForceN(d)
        if peak > m.ratedN then
            return { ok = false, reason = ("structural: %.0f kN peak exceeds the %s rating of %.0f kN"):format(peak / 1000, m.label, m.ratedN / 1000) }
        end
        return { ok = true, reason = "mates", mount = m, axis = neg(f) }
    end

    --- Every (mount, facing) a design could take on this Machine, with the verdict for each. For inspection.
    function M.options(d, vehicleKey)
        local out = {}
        for _, m in ipairs(M.MOUNTS) do
            for _, facing in ipairs(M.FACING_ORDER) do
                local v = M.check(d, vehicleKey, m.id, facing)
                out[#out + 1] = { mountId = m.id, facing = facing, ok = v.ok, reason = v.reason }
            end
        end
        return out
    end

    -- ------------------------------------------------------------------------------------------ resolution
    --- Installed items -> devices. `items` = { { componentId, designId, mountId, facing }, ... } (from the
    --- configuration). Items that no longer check out (a design changed, a facing became illegal) are returned in
    --- `refused` with the reason and produce nothing -- never a silent default.
    function M.resolve(items, vehicleKey)
        local devices, refused = {}, {}
        for _, it in ipairs(items or {}) do
            local d = designById[it.designId or ""]
            local v = d and M.check(d, vehicleKey, it.mountId, it.facing) or { ok = false, reason = "unknown design " .. tostring(it.designId) }
            if v.ok then
                local cmds = {}
                for name, spec in pairs(Sys.commands(d.perf.kind)) do cmds[name] = spec.type end
                devices[#devices + 1] = {
                    componentId = it.componentId, designId = d.designId, code = d.code, name = d.name, family = d.family,
                    kind = d.perf.kind, perf = d.perf, thermal = d.thermal, massKg = d.massKg,
                    mountId = it.mountId, facing = it.facing, pos = { v.mount.pos[1], v.mount.pos[2], v.mount.pos[3] },
                    axis = v.axis, commands = cmds,
                }
            else
                refused[#refused + 1] = { componentId = it.componentId, reason = v.reason }
            end
        end
        table.sort(devices, function(a, b) return tostring(a.componentId) < tostring(b.componentId) end)
        return devices, refused
    end

    function M.addedMassKg(devices)
        local s = 0
        for _, d in ipairs(devices or {}) do s = s + (d.massKg or 0) end
        return s
    end

    -- ------------------------------------------------------------------------------------------ the step
    --- Per-device runtime state (throttle lag, pulse timers, heat). Pure data; the host keeps one per Machine.
    function M.newState(devices)
        local s = { dev = {} }
        for _, d in ipairs(devices or {}) do s.dev[d.componentId] = { throttle = 0, pulseLeft = 0, sinceS = 1e9, heatK = 0, hot = false } end
        return s
    end

    --- Advance every device by dt seconds under `commands` ({ [componentId] = { throttle = 0..1, discharge = true } })
    --- with `fuelKg` available. Returns { force = {x,y,z} N (Machine frame), torque = {x,y,z} N m about `com`,
    --- propellantKg, pulses, out = { [componentId] = { thrustN, heatK, hot, starved } } }.
    ---
    --- Propellant is checked BEFORE it is spent: a device that cannot be fed for this step produces nothing.
    function M.step(devices, state, commands, dt, fuelKg, com)
        commands = commands or {}
        com = com or { 0, 0, 0.5 }
        local fuel = math.max(0, tonumber(fuelKg) or 0)
        local F, T = { 0, 0, 0 }, { 0, 0, 0 }
        local spent, pulses, out = 0, 0, {}
        for _, d in ipairs(devices or {}) do
            local st = state.dev[d.componentId]
            if not st then st = { throttle = 0, pulseLeft = 0, sinceS = 1e9, heatK = 0, hot = false }; state.dev[d.componentId] = st end
            local cmd = commands[d.componentId] or {}
            local p, thrust, starved = d.perf, 0, false
            local heatIn = 0
            if p.kind == "reaction_engine" then
                local want = math.max(0, math.min(1, tonumber(cmd.throttle) or 0))
                if st.hot then want = 0 end
                local tau = p.throttleTauS or 0
                st.throttle = tau > 0 and (st.throttle + (want - st.throttle) * math.min(1, dt / tau)) or want
                if st.throttle < 1e-3 then st.throttle = 0 end
                local f = Sys.thrustAt(p, Sys.RHO0, st.throttle)
                local kg = f / (p.ispS * Sys.G0) * dt
                if kg > fuel then starved = f > 0; f, kg = 0, 0; st.throttle = 0 end
                fuel, spent, thrust = fuel - kg, spent + kg, f
                heatIn = (p.heatKw or 0) * st.throttle * dt
            elseif p.kind == "pulse_reaction" then
                st.sinceS = st.sinceS + dt
                local ready = st.pulseLeft <= 0 or p.retrigger
                if cmd.discharge and ready and st.sinceS >= (p.rechargeS or 0) and not st.hot then
                    local kg = Sys.pulseMass(p)
                    if kg <= fuel then
                        fuel, spent, pulses = fuel - kg, spent + kg, pulses + 1
                        st.pulseLeft, st.sinceS = p.pulseS, 0
                        heatIn = heatIn + (p.heatKj or 0)
                    else
                        starved = true
                    end
                end
                if st.pulseLeft > 0 then
                    local active = math.min(dt, st.pulseLeft)
                    thrust = p.forceN * active / dt   -- the step's average force: impulse is exact at any frame rate
                    st.pulseLeft = st.pulseLeft - active
                end
            end
            -- heat: in from the device, out through its rejection; past the limit it shuts itself down until cool
            local th = d.thermal
            if th and th.capacityKjK and th.capacityKjK > 0 then
                st.heatK = math.max(0, st.heatK + (heatIn - (th.rejectKw or 0) * dt) / th.capacityKjK)
                if not st.hot and st.heatK >= (th.limitK or 1e9) then st.hot = true end
                if st.hot and st.heatK <= (th.resumeK or 0) then st.hot = false end
            end
            local f = { d.axis[1] * thrust, d.axis[2] * thrust, d.axis[3] * thrust }
            F[1], F[2], F[3] = F[1] + f[1], F[2] + f[2], F[3] + f[3]
            local r = { d.pos[1] - com[1], d.pos[2] - com[2], d.pos[3] - com[3] }
            T[1] = T[1] + r[2] * f[3] - r[3] * f[2]
            T[2] = T[2] + r[3] * f[1] - r[1] * f[3]
            T[3] = T[3] + r[1] * f[2] - r[2] * f[1]
            out[d.componentId] = { thrustN = thrust, throttle = st.throttle, heatK = st.heatK, hot = st.hot, starved = starved }
        end
        return { force = F, torque = T, propellantKg = spent, pulses = pulses, out = out }
    end

    --- Machine frame -> world, with the host's live basis ({ right, forward, up }, each {x,y,z} or {1,2,3}).
    function M.toWorld(v, frame)
        local function c(a, i, k) return tonumber(a[k] or a[i]) or 0 end
        local r, f, u = frame and frame.right, frame and frame.forward, frame and frame.up
        if type(r) ~= "table" or type(f) ~= "table" or type(u) ~= "table" then return nil end
        return {
            c(r, 1, "x") * v[1] + c(f, 1, "x") * v[2] + c(u, 1, "x") * v[3],
            c(r, 2, "y") * v[1] + c(f, 2, "y") * v[2] + c(u, 2, "y") * v[3],
            c(r, 3, "z") * v[1] + c(f, 3, "z") * v[2] + c(u, 3, "z") * v[3],
        }
    end

    M.FUEL_KG_PER_L = 0.745   -- the Machine tank holds petrol; propellant draws convert at this density

    return M
end)
