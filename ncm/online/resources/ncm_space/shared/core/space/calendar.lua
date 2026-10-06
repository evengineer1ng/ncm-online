-- ncm-core module: space.calendar
--
-- Snowglobe racing that happens whether anyone watches (L322; doc 54 §P). From the seeded world (`space.genesis`)
-- this turns a venue and a slot into an EVENT -- the one object every fidelity runs -- and turns what happened into
-- COMMITTED HISTORY: `world.seed` modifications on a history base, so seed + history rebuilds every Snowglobe result,
-- record, driver's learning and engineering response ever run.
--   event(world, venueIdx, slot, opts)   id (a seed path), discipline, venue physics (frames / centre as functions of
--                                        time), judge rules, and the entrants: each org's machine BUILT FOR that
--                                        discipline flown by its pilot, if its physics can fly the venue at all
--   historyBase(world)                   the empty history every seed starts from (drivers' competency, org flags)
--   outcome(world, history, event, rows, fidelity, at)
--                                        the mods one finished event commits: the event summary, records, Race Week
--                                        facts, each driver's learning (from `npc.competency`), and an ENGINEERING
--                                        RESPONSE (an org whose machine overheated adds radiator capacity next time)
--   apply(world, history)                fold history back into the world's people and machines
-- Path keys are prefixed (`p_<id>`, `o_<id>`) because `world.seed` paths read an all-digit segment as an index.
local Core = NcmCore

Core.define("space.calendar", function(C)
    local M = { version = "0.1.0" }
    local U = C.get("space.universe")
    local Seed = C.get("world.seed")
    local Course = C.get("space.course")
    local Gen = C.get("space.genesis")
    local Sprint = C.get("space.sprint")
    local Fireball = C.get("space.fireball")
    local Race = C.get("space.racesim")
    local Mach = C.get("engineering.machine")
    local Fx = C.get("engineering.fixtures")
    local Comp = C.get("npc.competency")

    M.MAX_ENTRANTS = 8
    M.EVERY_MIN = 20                       -- dev cadence: one Snowglobe event every 20 minutes, venues in turn

    local function V3(dir, k) return { dir[1] * k, dir[2] * k, dir[3] * k } end

    local function stationOf(world, id)
        for _, s in ipairs(world.stations) do if s.id == id then return s end end
    end

    --- The physics of a venue at race time: frames and centres as functions of t (seconds on the shared clock).
    function M.venuePhysics(world, venue, t0)
        if venue.kind == "sprint" and venue.style == "vertical" then
            local f = Sprint.verticalFrame(venue.anchor, 0)
            f.origin = U.cityToUniverse(venue.spot, venue.anchor)
            return { frame = f, gravity = "flat", up = f.y, ground = true, baseAltM = venue.spot[3] }
        elseif venue.kind == "sprint" then
            local st = stationOf(world, venue.stationId)
            local pos, vel = Gen.orbitAt(st.orbit, t0 or 0)
            local f = Course.lvlhFrame(pos, vel)
            -- the grid 300 m behind the station along-track, racing forward past it (frozen at the lights: a short
            -- sprint in free fall alongside the station)
            f.origin = Course.toWorld(f, { 0, -300, 0 })
            -- lanes across the orbit plane, racing along-track; right-handed (z = x cross y = -radial)
            local frame = { origin = f.origin, x = f.z, y = f.y, z = V3(f.x, -1), kind = "station" }
            return { frame = frame, gravity = "radial", up = frame.z, ground = false }
        elseif venue.kind == "fireball" and venue.centre == "earth" then
            local af = U.anchorFrame(venue.anchor)
            local R = U.BODIES.earth.radius
            return { centre = nil, gridCentre = V3(af.up, R + venue.gridAltM), gridUp = af.up, gridFwd = af.east, gravity = "radial" }
        elseif venue.kind == "fireball" then
            local st = stationOf(world, venue.stationId)
            local centre = function(t) local p, v = Gen.orbitAt(st.orbit, t); return p, v end
            local p, v = centre(t0 or 0)
            local f = Course.lvlhFrame(p, v)
            return { centre = centre, gridCentre = Course.toWorld(f, { venue.gridAltM, 0, 0 }), gridUp = f.x, gridFwd = f.y, gravity = "radial" }
        end
    end

    --- The event for venue `vi` at `slot` (any integer). opts = { t0 (shared clock at the lights), startT, external =
    --- { {id, person, design} } extra entrants (players) }.
    function M.event(world, vi, slot, opts)
        opts = opts or {}
        local venue = world.venues[vi]
        local node = Seed.root("ncm-snowglobe-events"):child(world.node, venue.id, slot)
        local phys = M.venuePhysics(world, venue, opts.t0)
        local startT = opts.startT or 5
        local rules
        if venue.kind == "sprint" then
            rules = Sprint.rules({ distanceM = venue.distanceM, lanes = venue.lanes, startT = startT, frame = phys.frame })
            rules.maxS = startT + 120
            rules.flagWindowS = 15
        else
            local c = phys.centre
            rules = Fireball.rules({ inner = venue.inner, outer = venue.outer, distanceM = venue.distanceM, centre = c })
            if not c then rules.centre = { 0, 0, 0 } end
            rules.startT = startT
            rules.maxS = startT + venue.distanceM / 40
            rules.flagWindowS = 90
        end
        -- entrants: every org's machine built for this discipline that its physics can fly here, in a seeded grid order
        local cand = {}
        for i, fl in ipairs(world.fleet) do
            local design = fl[venue.kind]
            if design then
                local est = Race.estimate(Mach.assemble(design), venue)
                if est.eligible then cand[#cand + 1] = { i = i, est = est } end
            end
        end
        local s = node:stream("grid")
        for i = #cand, 2, -1 do local j = s:int(1, i); cand[i], cand[j] = cand[j], cand[i] end
        local entrants = {}
        for _, x in ipairs(opts.external or {}) do entrants[#entrants + 1] = x end
        for _, c in ipairs(cand) do
            if #entrants >= (opts.maxEntrants or M.MAX_ENTRANTS) then break end
            local p = world.pilots[c.i]
            entrants[#entrants + 1] = { id = p.id, person = p, design = world.fleet[c.i][venue.kind], orgId = p.orgId }
        end
        return { id = node:id(), slot = slot, venueIdx = vi, discipline = venue.kind, venue = phys, venueInfo = venue,
                 rules = rules, entrants = entrants }
    end

    --- Which venue and slot are due at shared-clock minute `minute`: venues with Snowglobe disciplines in turn.
    function M.due(world, minute, everyMin)
        everyMin = everyMin or M.EVERY_MIN
        local slot = math.floor(minute / everyMin)
        local list = {}
        for i, v in ipairs(world.venues) do if v.kind == "sprint" or v.kind == "fireball" then list[#list + 1] = i end end
        return list[slot % #list + 1], slot
    end

    -- ------------------------------------------------------------------------------------------ history
    local function pk(id) return "p_" .. tostring(id) end
    local function ok(id) return "o_" .. tostring(id) end

    function M.historyBase(world)
        local h = { events = {}, records = {}, facts = { race = 0, race_crash = 0, clean_race = 0 }, drivers = {}, orgs = {} }
        for _, p in ipairs(world.pilots) do
            local d = { hours = 0 }
            for _, k in ipairs(Comp.SKILLS.snowglobe) do d[k] = 0 end      -- learning since genesis, added to the base
            h.drivers[pk(p.id)] = d
        end
        for _, o in ipairs(world.orgs) do h.orgs[ok(o.id)] = { radiatorBonusKw = 0, overheats = 0 } end
        return h
    end

    --- The modifications one finished event commits. rows = a classification with provenance (`space.tactical.result`
    --- or the abstract one). Returns a list of `world.seed` mods.
    function M.outcome(world, event, rows, fidelity, at)
        local mods, n = {}, 0
        local function mod(path, op, value)
            n = n + 1
            mods[#mods + 1] = { id = event.id .. "#" .. n, at = at, path = path, op = op, value = value }
        end
        local summary = { id = event.id, venue = event.venueInfo.name, discipline = event.discipline, fidelity = fidelity, at = at, rows = {} }
        local crashes, dur = 0, (event.rules.maxS or 120) - (event.rules.startT or 0)
        for _, r in ipairs(rows) do
            summary.rows[#summary.rows + 1] = { id = r.id, position = r.position, state = r.state, raceS = r.raceS, creditM = r.creditM,
                reason = r.reason, mode = r.mode }
            if r.reason == "contact" or r.reason == "hit the ground" then crashes = crashes + 1 end
        end
        mod("events", "append", summary)
        mod("facts.race", "add", 1)
        if crashes > 0 then mod("facts.race_crash", "add", crashes) else mod("facts.clean_race", "add", 1) end
        -- records: the fastest finish per venue and distance
        local best
        for _, r in ipairs(rows) do if r.state == "finished" and r.raceS and (not best or r.raceS < best.raceS) then best = r end end
        if best then mod("records", "append", { venue = event.venueInfo.name, distanceM = event.venueInfo.distanceM, raceS = best.raceS, id = best.id, event = event.id }) end
        -- drivers learn (per fidelity), and orgs answer what broke
        for _, e in ipairs(event.entrants) do
            local p = e.person
            if world.pilotsById and world.pilotsById[e.id] then
                local before = {}
                local probe = Seed.deepCopy(p)
                for _, k in ipairs(Comp.SKILLS.snowglobe) do before[k] = Comp.level(probe, "snowglobe", k) end
                local hours = 0
                for _, r in ipairs(rows) do if r.id == e.id then hours = (r.raceS or dur) / 3600 end end
                Comp.learn(probe, "snowglobe", { hours = hours, fidelity = fidelity, discipline = event.discipline })
                for _, k in ipairs(Comp.SKILLS.snowglobe) do
                    local g = Comp.level(probe, "snowglobe", k) - before[k]
                    if g > 0 then mod("drivers." .. pk(e.id) .. "." .. k, "add", g) end
                end
                mod("drivers." .. pk(e.id) .. ".hours", "add", hours)
            end
        end
        for _, r in ipairs(rows) do
            if r.reason == "overheated" and r.orgId then
                mod("orgs." .. ok(r.orgId) .. ".overheats", "add", 1)
                mod("orgs." .. ok(r.orgId) .. ".radiatorBonusKw", "add", 40)
            end
        end
        return mods
    end

    --- Fold the composed history into the world: drivers' learned competency, orgs' engineering responses.
    function M.apply(world, history)
        for _, p in ipairs(world.pilots) do
            local d = history.drivers[pk(p.id)]
            local rec = Comp.enter(p, "snowglobe")
            rec.base = rec.base or Seed.deepCopy(rec.skills)
            if d then
                for _, k in ipairs(Comp.SKILLS.snowglobe) do rec.skills[k] = math.min(99, rec.base[k] + (d[k] or 0)) end
                rec.hours = d.hours or 0
            end
        end
        for i, o in ipairs(world.orgs) do
            local x = history.orgs[ok(o.id)]
            if x and x.radiatorBonusKw > 0 then
                for _, purpose in ipairs({ "sprint", "fireball" }) do
                    local m = world.fleet[i] and world.fleet[i][purpose]
                    if m then
                        local kept = {}
                        for _, part in ipairs(m.parts) do if part.key ~= "rad_response" then kept[#kept + 1] = part end end
                        local b = Seed.deepCopy(Fx.DESIGNS.radiator_panel_40)
                        b.perf.radiativeKw = x.radiatorBonusKw
                        kept[#kept + 1] = { key = "rad_response", body = b, pos = { 0, 0, 1.4 } }
                        m.parts = kept
                    end
                end
            end
        end
        return world
    end

    --- Index pilots by id (for outcome); call once after genesis.
    function M.index(world)
        world.pilotsById = {}
        for _, p in ipairs(world.pilots) do world.pilotsById[p.id] = p end
        return world
    end

    return M
end)
