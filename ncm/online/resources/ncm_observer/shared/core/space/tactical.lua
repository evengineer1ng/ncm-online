-- ncm-core module: space.tactical
--
-- THE SAME RACE AT TACTICAL FIDELITY (L322; doc 54 §O). Nobody needs a rendered rigid body for a Fireball happening
-- out of sight, but the race must still HAPPEN: every entrant's machine (`engineering.machine`) flown by its driver
-- (`space.pilot` with `npc.behavior` + `npc.competency`) through `engineering.dynamics` -- propellant burns, heat
-- builds, forces act where the devices are mounted -- judged by the discipline's own judge (`space.fireball`,
-- `space.sprint`), at a fixed step, deterministically.
--
-- ONE EVENT, THREE FIDELITIES. An event is { id (a seed path), discipline, venue, entrants }. Abstract
-- (`space.racesim`), tactical (here) and physical (a host) all run THAT event:
--   * snapshot / resume: the whole mutable state is plain data, and every random draw comes from a stream keyed by
--     (event id, entrant id, step), so running 0 -> T equals 0 -> t, snapshot, resume -> T exactly;
--   * promote(id): an entrant's universe state, attitude and resources for a host to spawn; from then the host OBSERVES
--     it (`observe`) and the tactical sim neither integrates nor plans for it;
--   * demote(id, observed): the host hands it back where it really was; the tactical sim flies on from there;
--   * provenance per entrant: the share of race time it spent physical.
-- Simplifications at this fidelity, stated: attitude is slewed kinematically toward the thrust direction at a rate
-- the machine's torque authority and the pilot's attitude skill allow (moments from off-centre thrust are not
-- integrated here); contact is a closest-approach event, not a collision solve.
local Core = NcmCore

Core.define("space.tactical", function(C)
    local M = { version = "0.1.0" }
    local U = C.get("space.universe")
    local Hash = C.get("vocabulary.hash")
    local Seed = C.get("world.seed")
    local Mach = C.get("engineering.machine")
    local Dyn = C.get("engineering.dynamics")
    local Alloc = C.get("engineering.allocate")
    local Beh = C.get("npc.behavior")
    local Comp = C.get("npc.competency")
    local Pilot = C.get("space.pilot")
    local Fireball = C.get("space.fireball")
    local Sprint = C.get("space.sprint")
    local Course = C.get("space.course")
    local V = Pilot.vec
    local add, sub, scale, dot, cross, len, unit = V.add, V.sub, V.scale, V.dot, V.cross, V.len, V.unit

    M.DT = 0.05
    M.CONTACT_M = 6
    M.SIM_RATE = { sprint = 1, fireball = 1 }

    -- ------------------------------------------------------------------------------------------ venue physics
    local function gravityAt(venue, pos)
        if venue.gravity == "flat" then return scale(venue.up, -U.BODIES.earth.mass * U.G / U.BODIES.earth.radius ^ 2) end
        return U.gravity(pos)
    end
    --- Air density. A FLAT venue is a city patch (below the doorway the city is flat and its own height is altitude),
    --- so its air thins with height above the patch's sea level -- not with altitude above the compressed sphere,
    --- which a tangent-plane city sits hundreds of metres above (L320 Q1).
    local function densityAt(venue, pos)
        if venue.gravity == "flat" then
            return U.densityAt((venue.baseAltM or 0) + dot(sub(pos, venue.frame.origin), venue.up))
        end
        return U.density(pos)
    end
    M.densityAt = densityAt

    local function centreOf(venue, t)
        if venue.centre then return venue.centre(t) end
        return { 0, 0, 0 }, { 0, 0, 0 }
    end

    --- Rotation whose body z is `up` and body y is as close to `fwd` as possible.
    local function rotFrom(up, fwd)
        local z = unit(up)
        local y = unit(sub(fwd, scale(z, dot(fwd, z))))
        local x = cross(y, z)
        return { { x[1], y[1], z[1] }, { x[2], y[2], z[2] }, { x[3], y[3], z[3] } }
    end
    local function bodyZ(R) return { R[1][3], R[2][3], R[3][3] } end
    local function rotateRot(R, axis, ang)
        local x, y, z = axis[1], axis[2], axis[3]
        local c, s = math.cos(ang), math.sin(ang)
        local k = 1 - c
        local Q = { { c + x * x * k, x * y * k - z * s, x * z * k + y * s },
                    { y * x * k + z * s, c + y * y * k, y * z * k - x * s },
                    { z * x * k - y * s, z * y * k + x * s, c + z * z * k } }
        local O = {}
        for i = 1, 3 do
            O[i] = {}
            for j = 1, 3 do O[i][j] = Q[i][1] * R[1][j] + Q[i][2] * R[2][j] + Q[i][3] * R[3][j] end
        end
        return O
    end

    -- ------------------------------------------------------------------------------------------ the race
    --- event = { id, discipline = "sprint"|"fireball", venue, rules, entrants = { {id, person, design, orgId,
    --- external?} }, startT? }. Venue: sprint { frame, gravity = "flat"|"radial", up, ground = true }, fireball
    --- { centre = fn(t) or nil (Earth), gridCentre, gridUp, gridFwd, gravity = "radial" }.
    function M.new(event)
        local race = { event = event, t = 0, k = 0, entrants = {}, order = {}, log = {} }
        local rules = event.rules
        for i, e in ipairs(event.entrants) do
            local model = Mach.assemble(e.design)
            local prep = Alloc.prepare(model)
            local person = e.person
            Comp.enter(person, "snowglobe")
            local pos, vel, rot
            if event.discipline == "sprint" then
                local f = event.venue.frame
                pos = Course.toWorld(f, Sprint.laneSpot(rules, i))
                vel = { 0, 0, 0 }
                rot = rotFrom(f.y, scale(f.z, -1))
            else
                local v = event.venue
                local side = unit(cross(v.gridUp, v.gridFwd))
                local row, col = math.floor((i - 1) / 3), (i - 1) % 3 - 1
                pos = add(add(v.gridCentre, scale(side, col * 25)), scale(v.gridFwd, -row * 30))
                vel = { 0, 0, 0 }
                rot = rotFrom(v.gridUp, v.gridFwd)
            end
            local cap = Mach.capability(model)
            local maxRate = 0
            for a = 1, 2 do maxRate = math.max(maxRate, prep.maxTau[a] / math.max(1, model.inertia[a])) end
            race.entrants[e.id] = {
                id = e.id, orgId = e.orgId, person = person, model = model, prep = prep, cap = cap, external = e.external or false,
                profile = Beh.profile(person),
                -- mutable state (snapshot covers exactly these)
                s = {
                    dyn = Dyn.init(model, { pos = pos, vel = vel, rot = rot }),
                    judge = event.discipline == "sprint" and Sprint.newState() or Fireball.newState(),
                    mood = Beh.newMood(), plan = nil, nextPlanT = 0, status = "racing", reason = nil,
                    reactS = nil, physicalS = 0, axis = nil, note = nil, laneX = event.discipline == "sprint" and Sprint.laneSpot(rules, i)[1] or 0,
                    hotS = 0, finishT = nil,
                },
                slewRate = math.min(1.2, maxRate),       -- rad/s the machine's torque can turn it (capped)
                lane = i,
            }
            race.order[i] = e.id
        end
        return race
    end

    local function selfView(race, E)
        local d = E.s.dyn
        local mass = Dyn.mass(E.model, d)
        local thrustUp = 0
        for _, dev in ipairs(E.model.devices) do
            if dev.kind == "reaction_engine" or dev.kind == "jet" or dev.kind == "propeller" then
                thrustUp = thrustUp + math.max(0, dev.dir[3]) * (dev.perf.thrustN or 0)
            end
        end
        local dry = E.model.dryMassKg
        local dvLeft = E.cap.deltaVms > 0 and E.cap.deltaVms * math.log(mass / dry) / math.log(E.model.wetMassKg / dry) or 0
        return { pos = d.pos, vel = d.vel, aMax = thrustUp / mass, dvLeft = dvLeft, mass = mass,
            heatFrac = d.heatK / Mach.TEMP_LIMIT_K, creditM = E.s.judge.creditM or 0, axis = E.s.axis }
    end

    local function comp(E)
        local d = E.person.domains and E.person.domains.snowglobe
        return d and d.skills or {}
    end

    local function stakes(race, E)
        local ev = race.event
        if ev.discipline == "sprint" then
            return (race.t < ev.rules.startT + 2) and 1 or 0.4
        end
        local frac = (E.s.judge.creditM or 0) / ev.rules.distanceM
        return frac > 0.9 and 1 or (race.t < 10 and 0.8 or 0.2)
    end

    --- One fixed step for every non-external entrant; then judges, contact, provocation.
    function M.step(race)
        local ev, dt = race.event, M.DT
        local t = race.t + dt
        local rules = ev.rules
        for _, id in ipairs(race.order) do
            local E = race.entrants[id]
            local S = E.s
            if not E.external and S.status == "racing" then
                local rng = Hash.stream("ncm-tactical", ev.id, id, race.k)
                local d = S.dyn
                local selfv = selfView(race, E)
                local g = gravityAt(ev.venue, d.pos)
                local eff = Beh.effective(E.profile, S.mood, stakes(race, E))
                Beh.decay(S.mood, E.profile, dt)
                local cs = comp(E)
                if t >= S.nextPlanT or not S.plan then
                    if ev.discipline == "sprint" then
                        if not S.reactS then S.reactS = Pilot.reaction(cs, E.profile, Hash.stream("ncm-react", ev.id, id)) end
                        local grounded = dot(sub(d.pos, ev.venue.frame.origin), ev.venue.frame.y) <= 0.01
                        S.plan = Pilot.sprint({ t = t, startT = rules.startT, reactS = S.reactS, self = selfv, frame = ev.venue.frame,
                            laneX = S.laneX, g = g, comp = cs, eff = eff, rng = rng, grounded = grounded })
                    else
                        local c, cv = centreOf(ev.venue, t)
                        local gRel = ev.venue.centre and sub(g, U.gravity(c)) or g
                        if not S.axis then
                            local h = Hash.stream("ncm-axis", ev.id, id)
                            S.axis = unit({ h:normal(0, 1), h:normal(0, 1), h:normal(0, 1) })
                            selfv.axis = S.axis
                        end
                        local others = {}
                        for _, oid in ipairs(race.order) do
                            local O = race.entrants[oid]
                            if oid ~= id and O.s.status == "racing" then
                                others[#others + 1] = { id = oid, pos = O.s.dyn.pos, vel = sub(O.s.dyn.vel, cv), creditM = O.s.judge.creditM or 0 }
                            end
                        end
                        local selfRel = { pos = d.pos, vel = sub(d.vel, cv), aMax = selfv.aMax, dvLeft = selfv.dvLeft,
                            heatFrac = selfv.heatFrac, creditM = selfv.creditM, axis = S.axis }
                        local note
                        if t < rules.startT then
                            S.plan = scale(gRel, -1)                                     -- hold station on the grid
                            if ev.venue.centre == nil then S.plan = scale(g, -1) end
                            note = "grid"
                        else
                            S.plan, note = Pilot.fireball({ t = t, self = selfRel, rules = rules, centre = c, g = gRel,
                                comp = cs, eff = eff, prof = E.profile, others = others, rng = rng })
                        end
                        S.note = note
                    end
                    S.nextPlanT = t + Pilot.decisionPeriod(cs)
                end
                -- attitude: slew the main thrust axis toward the planned thrust, as fast as the machine can turn
                local want = unit(S.plan)
                if len(want) > 0 then
                    local z = bodyZ(d.rot)
                    local ang = math.acos(math.max(-1, math.min(1, dot(z, want))))
                    local axis = unit(cross(z, want))
                    local skill = 0.4 + 0.6 * ((cs.attitude or 8) / 100)
                    local step = math.min(ang, E.slewRate * skill * dt)
                    if step > 1e-6 and len(axis) > 0 then d.rot = rotateRot(d.rot, axis, step) end
                end
                local rho = densityAt(ev.venue, d.pos)
                local thr = Alloc.vector(E.prep, d.rot, S.plan, selfv.mass, rho)
                -- ground: a sprint grid sits on its start plane until it lifts
                local contact
                if ev.discipline == "sprint" and ev.venue.ground then
                    contact = dot(sub(d.pos, ev.venue.frame.origin), ev.venue.frame.y) <= 0.01
                end
                local rot = d.rot
                Dyn.step(E.model, d, { g = g, rho = rho, contact = contact }, { throttle = thr }, dt)
                d.rot, d.omega = rot, { 0, 0, 0 }                -- attitude is the planner's slew at this fidelity
                if contact ~= nil then
                    local h = dot(sub(d.pos, ev.venue.frame.origin), ev.venue.frame.y)
                    if h < 0 then
                        d.pos = add(d.pos, scale(ev.venue.frame.y, -h))
                        local vn = dot(d.vel, ev.venue.frame.y)
                        if vn < 0 then d.vel = sub(d.vel, scale(ev.venue.frame.y, vn)) end
                    end
                end
                if d.heatK >= Mach.TEMP_LIMIT_K then S.hotS = S.hotS + dt else S.hotS = 0 end
                if S.hotS > 10 then S.status, S.reason = "dnf", "overheated" end
                if ev.venue.centre == nil and ev.discipline == "fireball" and U.altitude(d.pos) <= 0 then
                    S.status, S.reason = "dnf", "hit the ground"
                end
            elseif E.external then
                S.physicalS = S.physicalS + dt
            end
        end
        race.t, race.k = t, race.k + 1
        -- judges (non-external entrants; external ones are judged as they are observed)
        for _, id in ipairs(race.order) do
            local E = race.entrants[id]
            local S = E.s
            if not E.external and S.status == "racing" then
                M.judge(race, E, t, dt)
            end
        end
        M.contacts(race)
        return race
    end

    function M.judge(race, E, t, dt)
        local ev, S = race.event, E.s
        local before = S.judge.creditM
        if ev.discipline == "sprint" then
            local _, e = Sprint.step(ev.rules, S.judge, t, S.dyn.pos, S.dyn.vel)
            if e and e.finished then S.status, S.finishT = "finished", e.finished end
        else
            local _, e = Fireball.step(ev.rules, S.judge, S.dyn.pos, S.dyn.vel, t, dt)
            if e and e.finished then S.status, S.finishT = "finished", e.finished end
            if e and e.dq then S.status, S.reason = "dq", e.dq end
            -- being passed provokes
            for _, oid in ipairs(race.order) do
                local O = race.entrants[oid]
                if O ~= E and before and O.s.judge.creditM and O.s.judge.creditM > S.judge.creditM
                    and (O.s.judge.prevCreditM or 0) <= (before or 0) and len(sub(O.s.dyn.pos, S.dyn.pos)) < 300 then
                    Beh.provoke(S.mood, E.profile, "passed")
                end
            end
            S.judge.prevCreditM = S.judge.creditM
        end
    end

    --- L323: contact between a HOST-flown entrant (a player's car) and an NPC, reported by the host and checked by the
    --- caller against the race's own positions. The NPC's truth takes the consequence: a momentum exchange along the
    --- line of the hit with both machines' real masses (restitution `e`), provocation, the same DNF hazard as NPC-NPC
    --- contact, and an incident in the log. The external entrant's row counts its contacts.
    ---   vExt = the host's velocity of the external car (universe), massExt = its machine's mass (kg)
    M.RESTITUTION = 0.3
    function M.contactExternal(race, npcId, extId, vExt, massExt)
        local N, X = race.entrants[npcId], race.entrants[extId]
        if not N or N.external or N.s.status ~= "racing" then return nil end
        local d = N.s.dyn
        local mN = Dyn.mass(N.model, d)
        local mX = massExt or (X and Dyn.mass(X.model, X.s.dyn)) or mN
        local rel = sub(vExt, d.vel)                               -- how the external car closes on the NPC
        local vrel = len(rel)
        local n = unit(rel)
        -- impulse on the NPC along the closing direction: J = (1 + e) * mu * vrel, mu the reduced mass
        local mu = mN * mX / (mN + mX)
        local J = (1 + M.RESTITUTION) * mu * vrel
        d.vel = add(d.vel, scale(n, J / mN))
        Beh.provoke(N.s.mood, N.profile, "contact")
        if X then
            X.s.contacts = (X.s.contacts or 0) + 1
            Beh.provoke(X.s.mood, X.profile, "contact")
        end
        local h = Hash.stream("ncm-contact-ext", race.event.id, npcId, extId, race.k)
        local p = math.min(0.9, vrel / 80)
        local out = h() < p
        if out then N.s.status, N.s.reason = "dnf", "contact" end
        race.log[#race.log + 1] = { t = race.t, kind = "contact", ids = { extId, npcId }, vRelMs = vrel, external = true,
            npcOut = out or nil, dvNpc = J / mN }
        return { vRelMs = vrel, dvNpc = J / mN, npcOut = out }
    end

    --- Every external entrant (player) ready for the lights? `ready` = { [id] = true }; a straggler cut-off is the host's.
    function M.allExternalReady(race, ready)
        for _, id in ipairs(race.order) do
            if race.entrants[id].external and not ready[id] then return false end
        end
        return true
    end

    function M.contacts(race)
        local ids = race.order
        for i = 1, #ids do
            local A = race.entrants[ids[i]]
            for j = i + 1, #ids do
                local B = race.entrants[ids[j]]
                -- a host-flown entrant's contacts are the host's to report (`contactExternal`), never guessed here
                if A.s.status == "racing" and B.s.status == "racing" and not A.external and not B.external then
                    local d = len(sub(A.s.dyn.pos, B.s.dyn.pos))
                    if d < M.CONTACT_M then
                        local vrel = len(sub(A.s.dyn.vel, B.s.dyn.vel))
                        local key = ids[i] .. "|" .. ids[j]
                        race.touching = race.touching or {}
                        if vrel > 3 and not race.touching[key] then
                            race.touching[key] = true
                            Beh.provoke(A.s.mood, A.profile, "contact")
                            Beh.provoke(B.s.mood, B.profile, "contact")
                            local h = Hash.stream("ncm-contact", race.event.id, key, race.k)
                            local p = math.min(0.9, vrel / 80)
                            race.log[#race.log + 1] = { t = race.t, kind = "contact", ids = { ids[i], ids[j] }, vRelMs = vrel }
                            for _, X in ipairs({ A, B }) do
                                if not X.external and h() < p then X.s.status, X.s.reason = "dnf", "contact" end
                            end
                        end
                    elseif race.touching then
                        race.touching[ids[i] .. "|" .. ids[j]] = nil
                    end
                end
            end
        end
    end

    --- The flag: once the first car is home, the rest have `flagWindowS` (rules) to finish; then the race is over and
    --- whoever is still out is classified by how far they got ("flagged"). Returns true when the race is over.
    function M.over(race)
        local first, live = nil, false
        for _, id in ipairs(race.order) do
            local s = race.entrants[id].s
            if s.status == "racing" then live = true end
            local f = s.finishT or s.judge.finishT
            if f and (not first or f < first) then first = f end
        end
        if not live or race.t >= race.event.rules.maxS then return true end
        local w = race.event.rules.flagWindowS
        return first ~= nil and w ~= nil and race.t >= first + w
    end

    --- Run until the race is over or `untilT`.
    function M.run(race, untilT)
        local limit = untilT or race.event.rules.maxS
        while race.t < limit and not M.over(race) do
            local live = false
            for _, id in ipairs(race.order) do if race.entrants[id].s.status == "racing" then live = true end end
            if not live then break end
            M.step(race)
        end
        return race
    end

    -- ------------------------------------------------------------------------------------------ fidelity
    function M.snapshot(race)
        local snap = { t = race.t, k = race.k, log = Seed.deepCopy(race.log), touching = Seed.deepCopy(race.touching or {}), s = {}, external = {} }
        for _, id in ipairs(race.order) do
            snap.s[id] = Seed.deepCopy(race.entrants[id].s)
            snap.external[id] = race.entrants[id].external
        end
        return snap
    end

    function M.resume(event, snap)
        local race = M.new(event)
        race.t, race.k, race.log, race.touching = snap.t, snap.k, Seed.deepCopy(snap.log), Seed.deepCopy(snap.touching)
        for _, id in ipairs(race.order) do
            race.entrants[id].s = Seed.deepCopy(snap.s[id])
            race.entrants[id].external = snap.external[id]
        end
        return race
    end

    --- Hand an entrant to a host: its state for spawning. From now the host observes it.
    function M.promote(race, id)
        local E = race.entrants[id]
        E.external = true
        local d = E.s.dyn
        return { id = id, pos = d.pos, vel = d.vel, rot = d.rot, tanks = d.tanks, heatK = d.heatK, creditM = E.s.judge.creditM }
    end

    --- A host's observation of an external entrant (universe position and velocity at race time t).
    function M.observe(race, id, t, pos, vel)
        local E = race.entrants[id]
        if not E or not E.external or E.s.status ~= "racing" then return end
        local last = E.s.lastObsT or t
        E.s.dyn.pos, E.s.dyn.vel = pos, vel
        E.s.lastObsT = t
        M.judge(race, E, t, math.max(1e-3, t - last))
    end

    --- Hand an entrant back to the simulation where the host last saw it.
    function M.demote(race, id, observed)
        local E = race.entrants[id]
        if observed then
            E.s.dyn.pos, E.s.dyn.vel = observed.pos or E.s.dyn.pos, observed.vel or E.s.dyn.vel
            if observed.rot then E.s.dyn.rot = observed.rot end
        end
        E.external = false
    end

    --- Classification with provenance. Every row: id, position, state, raceS / creditM, reason, mode, physicalShare.
    function M.result(race)
        local ev = race.event
        local entries = {}
        for _, id in ipairs(race.order) do
            local E = race.entrants[id]
            entries[#entries + 1] = { id = id, state = E.s.judge, E = E }
        end
        local rows
        if ev.discipline == "sprint" then
            rows = Sprint.classify(ev.rules, entries)
        else
            local cl = Fireball.classify(entries)
            rows = {}
            for i, e in ipairs(cl) do
                rows[i] = { id = e.id, position = i, raceS = e.state.finishT and (e.state.finishT - ev.rules.startT) or nil,
                    creditM = e.state.creditM, dq = e.state.dq }
            end
        end
        for _, r in ipairs(rows) do
            local E = race.entrants[r.id]
            local share = race.t > 0 and E.s.physicalS / race.t or 0
            r.state = E.s.status == "racing" and (r.raceS and "finished" or "running") or E.s.status
            if r.state == "running" and M.over(race) then
                r.state, E.s.reason = "dnf", race.t >= (ev.rules.maxS or math.huge) - 1e-9 and "time limit" or "flagged"
            end
            if r.raceS and r.state ~= "dq" then r.state = "finished" end
            r.reason = E.s.reason
            r.physicalShare = share
            r.mode = share >= 0.999 and "physical" or (share > 0 and "mixed" or "tactical")
            r.orgId = E.orgId
            r.contacts = E.s.contacts
        end
        return rows
    end

    return M
end)
