-- ncm-core module: space.canonical
--
-- L329 (owner, "NCM 3.0 - one universe"): the CANONICAL record of a Machine in NCM Deep, independent of any host.
-- Cyberpunk and Assetto Corsa are runners: whichever host embodies the Machine integrates it with the shared core
-- (`space.deep`, `space.guidance`, `engineering.installation`) and checkpoints this record; when no host has it, the NCM
-- server propagates it here. Same Earth frame (space.deep: ORIGIN, R, GM), same venues, same clock -- one Deep, so two
-- Machines entering from two hosts share one coordinate system.
--
-- Offline (owner ruling, 2026-10-06: "autopilot keeps going"): with Guidance engaged the Machine keeps flying on its own
-- propulsors -- fuel and heat permitting, the dev waivers honoured -- and holds over the venue on arrival; otherwise
-- gravity flies it. Coming down to the ground ends the flight there (`place = "landed"`): the caller decides recovery.
-- No interpolation: every second is integrated.
local Core = NcmCore

Core.define("space.canonical", function(C)
    local M = { version = "0.1.0", DT = 1.0, GROUND_M = 300 }
    local D = C.get("space.deep")
    local G = C.get("space.guidance")
    local VN = C.get("space.venues")
    local I = C.get("engineering.installation")
    local V = D.vec

    local function copy3(a) return a and { tonumber(a[1] or a.x) or 0, tonumber(a[2] or a.y) or 0, tonumber(a[3] or a.z) or 0 } or nil end

    --- A record from a live Deep state. `extra` carries identity and context (asset, driver, massKg, devices, devState,
    --- fuelKg, devFuel, devHeat, guidance = { venueId, engaged }, host, origin, destination, journeyId, raceWeek).
    function M.fromDeep(s, utc, extra)
        local r = { v = 1, place = "deep", p = copy3(s.p), vel = copy3(s.v),
            basis = { right = copy3(s.basis.right), forward = copy3(s.basis.forward), up = copy3(s.basis.up) },
            utc = tonumber(utc) or 0, provenance = { "observed" } }
        for k, x in pairs(type(extra) == "table" and extra or {}) do r[k] = x end
        return r
    end

    --- A live Deep state from a record (for a host that resumes it).
    function M.toDeep(r)
        return { p = copy3(r.p), v = copy3(r.vel), t = 0,
            basis = { right = copy3(r.basis.right), forward = copy3(r.basis.forward), up = copy3(r.basis.up) } }
    end

    --- Where the record says the Machine is: lat, lon, alt.
    function M.where(r)
        if r.place == "landed" and r.landed then return r.landed.lat, r.landed.lon, 0 end
        return D.ecefToLla(r.p)
    end

    local function thrustAxis(devices)
        local a = { 0, 0, 0 }
        for _, d in ipairs(devices or {}) do
            if d.kind == "reaction_engine" then
                local t = (d.perf and d.perf.thrustN) or 0
                a = V.add(a, V.scale(d.axis or { 0, 1, 0 }, t))
            end
        end
        return V.len(a) > 0 and V.unit(a) or nil
    end

    --- Advance the record to `toUtc` (at most `maxSteps` steps per call, so a host's script budget is never exceeded:
    --- call again until `done`). Returns record, done, info { steps, arrived, landed, fuelOut, cannotPoint }.
    ---
    --- L331: on the FULL machine model (`engineering.flightmodel`): the record's install + chassis + tank is the
    --- machine; air thins with altitude; the autopilot turns the Machine with its own attitude parts, or -- development
    --- only, `r.devAttitude` -- the labelled waiver. A Machine that can do neither is not flown: gravity has it.
    function M.propagate(r, toUtc, maxSteps)
        local info = { steps = 0 }
        if r.place ~= "deep" then r.utc = math.max(r.utc or 0, toUtc); return r, true, info end
        local F = C.get("engineering.flightmodel")
        local m = F.build(r.devices or {}, { vehicleKey = r.vehicleKey, fuelKg = r.devFuel and 40 or (tonumber(r.fuelKg) or 0) })
        local s = F.state(m, M.toDeep(r), r.dyn)
        local venue = r.guidance and r.guidance.engaged and r.guidance.venueId and VN.get(r.guidance.venueId) or nil
        local canPoint = F.canPoint(m, r.devAttitude)
        if venue and not canPoint then info.cannotPoint = true end
        local route = (venue and canPoint and F.mainAxis(m)) and G.plan(M.toDeep(r), venue) or nil
        -- the waiver turns the body directly (stable at 1 s); a physical attitude law needs finer steps
        local dt = (route and not r.devAttitude) and 0.25 or M.DT
        local budget = maxSteps or math.huge
        while (r.utc or 0) + dt <= toUtc and info.steps < budget do
            local cmd, waiver = {}, nil
            if route then
                cmd, waiver = G.fly(route, m, s, { devHeat = r.devHeat, waiver = r.devAttitude })
                if not r.guidance.arrived and G.arrived(route, F.deep(s)) then r.guidance.arrived = true; info.arrived = true end
            end
            s = F.step(m, s, cmd, dt, { devFuel = r.devFuel, devHeat = r.devHeat, waiver = waiver })
            if route and not r.devFuel and F.fuelKg(m, s) <= 1e-6 then r.guidance.engaged, route, info.fuelOut = false, nil, true end
            r.utc = r.utc + dt
            info.steps = info.steps + 1
            local la, lo, alt = D.ecefToLla(s.pos)
            if alt <= (route and G.groundBelow(route, la, lo) + 25 or M.GROUND_M) then
                r.place, r.landed, info.landed = "landed", { lat = la, lon = lo, utc = r.utc }, true
                break
            end
        end
        local dv = F.deep(s)
        r.p, r.vel, r.basis, r.dyn = dv.p, dv.v, dv.basis, F.carry(s)
        if not r.devFuel then r.fuelKg = F.fuelKg(m, s) end
        local done = r.place ~= "deep" or (r.utc or 0) + dt > toUtc
        if info.steps > 0 then r.provenance = { "simulated" } end
        return r, done, info
    end

    return M
end)
