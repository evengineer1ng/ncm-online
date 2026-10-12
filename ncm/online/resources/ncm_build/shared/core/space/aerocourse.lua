-- ncm-core module: space.aerocourse
--
-- THE AEROSPACE COURSE (aerospace racing brief, 2026-10-07): one race, one field, one clock, one classification, from
-- Night City into Deep and home. A course is a CHAIN OF 3D GATES (`space.course.gate`: centre, normal, radius; crossing
-- is a sign change through the plane within the radius) in the universe frame, each labelled with the LEG it belongs to
-- -- ground, ascent, deep, return, reentry, landing. The leg is a label for people and the tower; physics never reads
-- it (air thins with altitude, not with a leg name).
--
--   route     a course from city nodes (`data.nodes`) and altitudes: Westbrook -> Pothole -> up -> a Deep turnaround ->
--             down over Night City -> Hill Abode. City gates are a LOW CORRIDOR above the node (tactical fidelity has
--             no tyres; on a host the ground legs are driven -- the seam, stated).
--   judge     next gate, the gates passed and when, the finish (the last gate), PROGRESS = the course length up to the
--             last gate passed plus the leg flown toward the next: one number that orders a field whether a car is on
--             the road, in Deep or coming home.
--   standings the timing tower: position, leg, next gate, gates passed, progress, gap to the leader and to the car
--             ahead (metres, and seconds at the chaser's own speed), status.
--   facts     incidents the city can see (`ncm:week:fact` vocabulary: race_crash, wreck, civilian_contact) -- only those
--             that happen where Night City is: low, and near it. A crash at 300 km is a DNF, not a city's problem.
local Core = NcmCore

Core.define("space.aerocourse", function(C)
    local M = { version = "0.1.0" }
    local U = C.get("space.universe")
    local Course = C.get("space.course")
    local Nodes = C.get("data.nodes")
    local V = U.vec
    local add, sub, scale, dot, len = V.add, V.sub, V.scale, V.dot, V.len
    local function unit(a) local l = len(a); return l > 0 and scale(a, 1 / l) or { 0, 0, 1 } end

    M.CITY_RADIUS_M = 25000      -- Night City and its approaches, for "the city saw it"
    M.CITY_CEILING_M = 3000

    local function node(id)
        for _, n in ipairs(Nodes.LIST) do
            if type(n) == "table" and (n.id == id or n.name == id) then return n end
        end
        error("space.aerocourse: no node " .. tostring(id))
    end
    M.node = node

    --- A city point (REDengine x, y, z) raised `above` metres, in the universe.
    function M.cityPoint(n, above)
        return U.cityToUniverse({ n.x, n.y, (n.z or 0) + (above or 0) }, "night_city")
    end

    --- Build a course. spec = { start = node, via = node, finish = node, corridorM = 60, deepAltM = 100000,
    --- turnAltM = 300000, downrangeM = 0 (horizontal offset of the turnaround, east), reentryAltM = 20000 }.
    --- Returns { gates = { {id, leg, centre, normal, radius, passMs?} }, grid = { {pos, fwd, up} x n }, lengthM, ... }.
    function M.route(spec)
        spec = spec or {}
        local S, P, F = node(spec.start or "Japantown Crossway"), node(spec.via or "Pothole"), node(spec.finish or "Hill Abode")
        local corridor = spec.corridorM or 60
        local frame = U.anchorFrame("night_city")
        local upAt = function(p) return unit(p) end
        local pts = {}
        local function g(id, leg, centre, radius, extra)
            local x = { id = id, leg = leg, centre = centre, radius = radius }
            for k, v in pairs(extra or {}) do x[k] = v end
            pts[#pts + 1] = x
        end
        local pothole = M.cityPoint(P, corridor)
        local finish = M.cityPoint(F, 3)
        local deepAlt, turnAlt = spec.deepAltM or 100000, spec.turnAltM or 300000
        local R = U.BODIES.earth.radius
        local function over(p, alt, east)
            local base = add(p, scale(frame.east, east or 0))
            return scale(unit(base), R + alt)
        end
        g("pothole", "ground", pothole, 120)
        g("climb", "ascent", over(pothole, 20000), 2000)
        g("deep", "ascent", over(pothole, deepAlt, (spec.downrangeM or 0) * 0.3), 8000)
        g("turn", "deep", over(pothole, turnAlt, spec.downrangeM or 0), 10000)
        g("return", "return", over(finish, deepAlt), 8000)
        g("reentry", "reentry", over(finish, spec.reentryAltM or 20000), 3000)
        g("approach", "landing", M.cityPoint(F, 400), 150)
        g("finish", "landing", finish, 60, { passMs = spec.landingMs or 8 })
        -- normals: the way you arrive (from the previous gate); the first from the grid
        local start = M.cityPoint(S, 0)
        local prev = start
        local length = 0
        for _, x in ipairs(pts) do
            x.normal = unit(sub(x.centre, prev))
            x.fromM = length
            length = length + len(sub(x.centre, prev))
            x.toM = length
            prev = x.centre
        end
        -- the finish is crossed coming DOWN onto Hill Abode
        pts[#pts].normal = scale(upAt(finish), -1)
        -- the grid: rows of two behind the start, pointing at Pothole, on the road
        local fwdC = unit(sub({ P.x, P.y, 0 }, { S.x, S.y, 0 }))
        local sideC = { fwdC[2], -fwdC[1], 0 }
        local grid = {}
        for i = 1, (spec.gridSize or 12) do
            local row, col = math.floor((i - 1) / 2), (i - 1) % 2
            local c = { S.x - fwdC[1] * 12 * row + sideC[1] * (col == 0 and -4 or 4),
                S.y - fwdC[2] * 12 * row + sideC[2] * (col == 0 and -4 or 4), (S.z or 0) }
            local pos = U.cityToUniverse(c, "night_city")
            local fwd = sub(U.cityToUniverse({ c[1] + fwdC[1], c[2] + fwdC[2], c[3] }, "night_city"), pos)
            grid[i] = { pos = pos, fwd = unit(fwd), up = unit(pos) }
        end
        return { gates = pts, grid = grid, lengthM = length, start = start, groundAltM = (S.z or 0),
            names = { start = S.name, via = P.name, finish = F.name } }
    end

    -- ------------------------------------------------------------------------------------------ judge
    function M.newState() return { next = 1, passed = {}, finishT = nil, progressM = 0, prev = nil } end

    --- One judge step: did the car cross its next gate between its last position and this one?
    function M.step(rules, st, t, pos, vel, dt)
        local gates = rules.gates
        local ev
        local prev = st.prev or pos
        st.prev = pos
        local gate = gates[st.next]
        if gate and not st.finishT then
            local ok, f, miss = Course.crossed(gate, prev, pos)
            if ok then
                local at = t - dt + (f or 1) * dt
                st.passed[#st.passed + 1] = { id = gate.id, t = at, missM = miss, speed = len(vel) }
                st.next = st.next + 1
                ev = { gate = gate.id, t = at }
                if st.next > #gates then st.finishT, ev.finished = at, at end
            end
        end
        local g = gates[st.next]
        if g then
            local seg = g.toM - g.fromM
            st.progressM = g.fromM + math.max(0, math.min(seg, seg - len(sub(g.centre, pos))))
        else
            st.progressM = rules.lengthM
        end
        return st, ev
    end

    function M.leg(rules, st)
        local g = rules.gates[st.next]
        return g and g.leg or "finished", g and g.id or nil, g and len(sub(g.centre, st.prev or g.centre)) or 0
    end

    -- ------------------------------------------------------------------------------------------ the tower
    --- rows = { { id, judge = state, status, pos, vel, finishT } }. Finished first by time, then by progress.
    function M.standings(rules, rows, startT)
        local list = {}
        for _, r in ipairs(rows) do list[#list + 1] = r end
        table.sort(list, function(a, b)
            local fa, fb = a.judge.finishT, b.judge.finishT
            if fa and fb then return fa < fb end
            if fa or fb then return fa ~= nil end
            local la, lb = (a.status == "racing" or a.status == "finished") and 1 or 0, (b.status == "racing" or b.status == "finished") and 1 or 0
            if la ~= lb then return la > lb end
            if a.judge.progressM ~= b.judge.progressM then return a.judge.progressM > b.judge.progressM end
            return a.id < b.id
        end)
        local out = {}
        local lead = list[1]
        for i, r in ipairs(list) do
            local leg, gateId, toGate = M.leg(rules, r.judge)
            local speed = r.vel and len(r.vel) or 0
            local o = { position = i, id = r.id, status = r.status, reason = r.reason, leg = leg, gate = gateId, toGateM = toGate,
                gatesPassed = #r.judge.passed, progressM = r.judge.progressM, speed = speed,
                altM = r.pos and U.altitude(r.pos) or nil,
                raceS = r.judge.finishT and (r.judge.finishT - (startT or 0)) or nil, mode = r.mode, family = r.family }
            if i > 1 then
                local ahead = list[i - 1]
                if r.judge.finishT and lead.judge.finishT then
                    o.gapS = r.judge.finishT - lead.judge.finishT
                    o.intervalS = r.judge.finishT - (ahead.judge.finishT or r.judge.finishT)
                else
                    o.gapM = lead.judge.progressM - r.judge.progressM
                    o.intervalM = ahead.judge.progressM - r.judge.progressM
                    o.gapS = speed > 1 and o.gapM / speed or nil
                end
            end
            out[i] = o
        end
        return out
    end

    --- One tower line (a HUD, a log).
    function M.line(o)
        local gap = o.position == 1 and "LEADER" or (o.raceS and ("+%.1fs"):format(o.gapS or 0))
            or (o.gapM and ("+%.1fkm"):format(o.gapM / 1000)) or "--"
        return ("P%-2d %-14s %-8s %-9s %-10s alt %7.1fkm %6.0fm/s"):format(o.position, tostring(o.id), tostring(o.leg),
            tostring(o.status), gap, (o.altM or 0) / 1000, o.speed or 0)
    end

    -- ------------------------------------------------------------------------------------------ the city hears it
    --- Is a universe point where Night City can see it?
    function M.inCity(pos)
        local c = U.anchorFrame("night_city").up
        local alt = U.altitude(pos)
        local cosA = math.max(-1, math.min(1, dot(unit(pos), c)))
        return alt < M.CITY_CEILING_M and U.BODIES.earth.radius * math.acos(cosA) < M.CITY_RADIUS_M
    end

    --- A race's incident log -> Race Week facts, in `ncm:week:fact` vocabulary ({ kind, n }), each with the incident it
    --- came from (machine, driver, position, speed, leg, band, cause) so a city-memory record can keep the evidence.
    --- band >= 3 -> a wreck; any crash DNF -> race_crash. Out of the city's sight -> no fact (the log keeps it).
    function M.facts(log)
        local out = {}
        for _, e in ipairs(log or {}) do
            if e.pos and M.inCity(e.pos) then
                if e.kind == "impact" or e.kind == "landing" or e.kind == "contact" then
                    if e.dnf then out[#out + 1] = { kind = "race_crash", n = 1, incident = e } end
                    if (e.band or 0) >= 3 then out[#out + 1] = { kind = "wreck", n = 1, incident = e } end
                end
            end
        end
        return out
    end

    -- ------------------------------------------------------------------------------------------ the event
    M.DRIVERS = { "Justina", "Oscar", "Ritesh", "Facundo", "Mireille", "Kenji", "Amara", "Tomas", "Ilse", "Dmitri", "Noor", "Callum" }

    --- A seeded driver: road attributes the behaviour and competency models read (no space-native skill: every one of
    --- them is a road racer flying Deep for the first time).
    function M.driver(seedId, name)
        local Hash = C.get("vocabulary.hash")
        local h = Hash.stream("ncm-aerocourse-driver", seedId, name)
        local a = {}
        for _, k in ipairs({ "aggression", "discipline", "ego", "pressure_handling", "mettle", "confidence_volatility", "mistake_rate",
            "consistency", "launch", "racecraft", "overtaking", "vehicle_sympathy", "tyre_sympathy" }) do
            a[k] = 25 + math.floor(h() * 60)
        end
        return { id = "npc:" .. name:lower(), display = name, attrs = a, personality = { valor = h() * 2 - 1, temperament = h() * 2 - 1 } }
    end

    --- An aerospace event from Westbrook through Pothole into Deep and home to Hill Abode, for WHATEVER machines the caller
    --- has -- the tape's garage, a claimed car, a vanilla catalogue record, a car the player's own install plugs in. Core
    --- names no vehicle: a third-party car (a modded Formula car, never redistributed) is never a default or a dependency
    --- here. Liveries are used when that machine has any (`data.liveries`), otherwise none.
    --- opts = { id, size = 12, vehicleKey (required unless `machines` names every slot), machines = { [i] = vehicleKey },
    --- fit = "deep_racer", route = M.route spec, startT = 5, maxS, player = { id, livery } (an external entrant, slot 1) }.
    function M.event(opts)
        opts = opts or {}
        local LO = C.get("engineering.loadout")
        local Liv = C.get("data.liveries")
        local id = opts.id or "aero:night-city:deep:1"
        local route = M.route(opts.route or {})
        local key = opts.vehicleKey
        local order = (key and Liv.MODELS[key] and Liv.MODELS[key].order) or {}
        local entrants = {}
        local size = opts.size or 12
        -- the player keeps their livery; the field takes the machine's other liveries in deck order, then repeats
        local pool = {}
        for _, l in ipairs(order) do if not (opts.player and l == opts.player.livery) then pool[#pool + 1] = l end end
        local n = 0
        for i = 1, size do
            local mk = (opts.machines and opts.machines[i]) or key
            assert(mk, "space.aerocourse.event: no machine for grid slot " .. i .. " (pass vehicleKey or machines)")
            local fit = LO.build(mk, { fit = opts.fit or "deep_racer" })
            if i == 1 and opts.player then
                entrants[i] = { id = opts.player.id or "player", person = M.driver(id, "V"), model = fit.model, external = true,
                    livery = opts.player.livery, vehicleKey = mk }
            else
                n = n + 1
                local name = M.DRIVERS[((n - 1) % #M.DRIVERS) + 1]
                local p = M.driver(id, name)
                local liv = #pool > 0 and pool[((n - 1) % #pool) + 1] or nil
                entrants[i] = { id = p.id, person = p, model = fit.model, orgId = liv, livery = liv, vehicleKey = mk }
            end
        end
        return {
            id = id, discipline = "course",
            venue = { gravity = "radial", grid = route.grid, groundAltM = route.groundAltM, names = route.names },
            rules = { gates = route.gates, lengthM = route.lengthM, startT = opts.startT or 5, maxS = opts.maxS or 7200,
                flagWindowS = opts.flagWindowS or 900 },
            entrants = entrants,
        }
    end

    --- Severity band from a velocity change (m/s), on `competition.incidents`' coarse scale (1 scrape .. 4 destroyed).
    function M.band(dv)
        if dv >= 45 then return 4 elseif dv >= 20 then return 3 elseif dv >= 8 then return 2 elseif dv >= 3 then return 1 end
        return 0
    end

    return M
end)
