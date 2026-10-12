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
    local function copyBasis(b) return b and { right = copy3(b.right), forward = copy3(b.forward), up = copy3(b.up) } or nil end

    --- A record from a live Deep state. `extra` carries identity and context (asset, driver, massKg, devices, devState,
    --- fuelKg, devFuel, devHeat, guidance = { venueId, engaged }, host, origin, destination, journeyId, raceWeek).
    --- doc 57 §5: p / vel / basis stay Earth-fixed for every reader; a state flying in an inertial frame also carries
    --- `frame` and its authoritative `ip` / `iv` / `ibasis` (and the `futc` they hold at).
    function M.fromDeep(s, utc, extra)
        local r = { v = 1, place = "deep", p = copy3(s.p), vel = copy3(s.v), basis = copyBasis(s.basis),
            utc = tonumber(utc) or 0, provenance = { "observed" } }
        if type(s.frame) == "table" and s.ip then
            r.frame, r.ip, r.iv, r.ibasis, r.futc = s.frame, copy3(s.ip), copy3(s.iv), copyBasis(s.ibasis), tonumber(s.utc)
        end
        for k, x in pairs(type(extra) == "table" and extra or {}) do r[k] = x end
        return r
    end

    --- A live Deep state from a record (for a host that resumes it).
    function M.toDeep(r)
        local d = { p = copy3(r.p), v = copy3(r.vel), t = 0, basis = copyBasis(r.basis) }
        if type(r.frame) == "table" and r.ip and r.iv and r.ibasis then
            d.frame, d.ip, d.iv, d.ibasis, d.utc = r.frame, copy3(r.ip), copy3(r.iv), copyBasis(r.ibasis), tonumber(r.futc or r.utc)
        end
        return d
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
        local s = F.state(m, M.toDeep(r), r.dyn, r.utc)
        -- doc 58: nobody is flying -- an experimental drive in progress ends where the Machine is (`pilot_lost`)
        local Dm = F.drives and F.drives()
        info.driveEvents = {}
        if Dm and s.utc and s.drv then
            for _, e in ipairs(Dm.pilotLost(m, s)) do info.driveEvents[#info.driveEvents + 1] = e end
        end
        -- L334: the target may be the KSA border (Earth's sphere of influence) as well as an Earth venue
        local venue = r.guidance and r.guidance.engaged and r.guidance.venueId and G.target(r.guidance.venueId, VN) or nil
        local canPoint = F.canPoint(m, r.devAttitude)
        if venue and not canPoint then info.cannotPoint = true end
        local route = (venue and canPoint and F.mainAxis(m)) and G.planTo(M.toDeep(r), venue) or nil
        if route then F.toEarthFixed(s) end   -- doc 57: guidance reads s.pos as Earth-fixed
        -- the waiver turns the body directly (stable at 1 s); a physical attitude law needs finer steps
        local dt = (route and not r.devAttitude) and 0.25 or M.DT
        local budget = maxSteps or math.huge
        while (r.utc or 0) + dt <= toUtc and info.steps < budget do
            local cmd, waiver = {}, nil
            if route then
                cmd, waiver = G.fly(route, m, s, { devHeat = r.devHeat, waiver = r.devAttitude })
                if not r.guidance.arrived and G.arrived(route, F.deep(s)) then
                    r.guidance.arrived = true; info.arrived = true
                    if route.kind == "border" then
                        -- L334: at the border the Machine waits for its next host (KSA); Deep stops flying it
                        r.utc = r.utc + dt
                        r.place, r.border = "border", { utc = r.utc, host = "ksa" }
                        info.border = true
                        info.steps = info.steps + 1
                        break
                    end
                end
            end
            -- doc 57: the step's UTC turns on the astronomical substrate; guidance flies Earth-fixed (its plan is)
            local tel
            s, tel = F.step(m, s, cmd, dt, { devFuel = r.devFuel, devHeat = r.devHeat, waiver = waiver, utc = r.utc, earthFixed = route ~= nil, pilot = false })
            if tel and tel.driveEvents and #info.driveEvents < 50 then
                for _, e in ipairs(tel.driveEvents) do info.driveEvents[#info.driveEvents + 1] = e end
            end
            if route and not r.devFuel and F.fuelKg(m, s) <= 1e-6 then r.guidance.engaged, route, info.fuelOut = false, nil, true end
            r.utc = r.utc + dt
            info.steps = info.steps + 1
            if s.frameSwitched then info.frame, s.frameSwitched = s.frameSwitched, nil end
            local alt = F.altitude(s)
            local la, lo = 0, 0
            if alt <= 1e6 then la, lo = D.ecefToLla((F.deep(s)).p) end   -- lat/lon only matter near the ground
            if alt <= (route and G.groundBelow(route, la, lo) + 25 or M.GROUND_M) then
                r.place, r.landed, info.landed = "landed", { lat = la, lon = lo, utc = r.utc }, true
                break
            end
        end
        local dv = F.deep(s)
        r.p, r.vel, r.basis, r.dyn = dv.p, dv.v, dv.basis, F.carry(s, true)
        r.frame, r.ip, r.iv, r.ibasis, r.futc = dv.frame, dv.ip, dv.iv, dv.ibasis, dv.frame and dv.utc or nil
        if not r.devFuel then r.fuelKg = F.fuelKg(m, s) end
        local done = r.place ~= "deep" or (r.utc or 0) + dt > toUtc
        if info.steps > 0 then r.provenance = { "simulated" } end
        return r, done, info
    end

    return M
end)
