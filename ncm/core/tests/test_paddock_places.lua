-- paddock.garages and paddock.talk: rented garages on shifts, and what their people say (doc 44 §11, phase 4).
local SEASON = "2026-S4"

local worldCache
local function world(T)
    if not worldCache then worldCache = T.Core.get("paddock.world").genesis(4242, SEASON) end
    return worldCache
end

local function orgList(w)
    local out = {}
    for _, id in ipairs(w.orgOrder) do local o = w.orgs[id]; out[#out + 1] = { id = o.id, tier = o.tier } end
    return out
end

return {
    garage_registry_is_derived_and_complete = function(T)
        local G = T.Core.get("paddock.garages")
        local sites = G.sites()
        T.ok(#sites >= 60, "the rental pool has the extracted garages, workshops and parking sites")
        local seen = {}
        for _, s in ipairs(sites) do
            T.falsy(seen[s.id], "unique site id " .. s.id); seen[s.id] = true
            T.ok(s.kind == "garage" or s.kind == "workshop" or s.kind == "parking", "no Autofixer in the pool: " .. s.id)
            T.ok(type(s.x) == "number" and type(s.y) == "number" and type(s.z) == "number", "coordinates " .. s.id)
            T.ok(type(s.district) == "string" and s.district ~= "", "district " .. s.id)
            T.falsy(s.refs or s.journal or s.entity, "no raw game identifiers cross into NCM: " .. s.id)
            T.falsy(G.label(s):match("%d"), "a label names a place, never a number")
        end
    end,

    every_org_rents_and_sites_are_shared_but_never_over_depth = function(T)
        local G = T.Core.get("paddock.garages")
        local w = world(T)
        local orgs = orgList(w)
        local a = G.assign(w.seed, orgs, {})
        local tenants, nightDay = {}, 0
        for _, o in ipairs(orgs) do
            T.ok(a[o.id], "org " .. o.id .. " has a garage")
            tenants[a[o.id]] = tenants[a[o.id]] or {}
            table.insert(tenants[a[o.id]], o.tier)
        end
        local shared = 0
        for _, list in pairs(tenants) do
            T.ok(#list <= G.DEPTH, "no site holds more than DEPTH tenants")
            if #list >= 2 then shared = shared + 1 end
            local night, day = false, false
            for _, t in ipairs(list) do if t == "street" then night = true else day = true end end
            if night and day then nightDay = nightDay + 1 end
        end
        T.ok(shared >= 15, "garages are shared (" .. shared .. " sites hold two or more teams)")
        T.ok(nightDay >= 15, "a day team and a night team pair up (" .. nightDay .. " sites)")
        -- deterministic, and existing tenancies survive a new org and a bad site elsewhere
        local b = G.assign(w.seed, orgs, {})
        for _, o in ipairs(orgs) do T.eq(b[o.id], a[o.id], "same assignment twice") end
        local kept = {}
        for i, o in ipairs(orgs) do kept[i] = { id = o.id, tier = o.tier, garageId = a[o.id] } end
        local victim = kept[1].garageId
        kept[#kept + 1] = { id = "o99999", tier = "street" }
        local c = G.assign(w.seed, kept, { [victim] = true })
        for _, o in ipairs(kept) do
            if o.garageId and o.garageId ~= victim then T.eq(c[o.id], o.garageId, "a team never moves for someone else") end
        end
        T.ok(c[kept[1].id] and c[kept[1].id] ~= victim, "a team on a bad site is moved")
        T.ok(c["o99999"], "a new org is housed")
    end,

    shifts_follow_the_rhythm_and_cross_midnight = function(T)
        local G = T.Core.get("paddock.garages")
        local Clock = T.Core.get("world.clock")
        local shift = { from = 20 * 3600, len = 7 * 3600, off = { 7, 7 } }        -- no days off
        local day = Clock.eastern(1790000000).dayIndex
        T.ok(G.onShift(shift, Clock.utcAt(day, 21 * 3600)), "on at 21:00")
        T.ok(G.onShift(shift, Clock.utcAt(day, 26 * 3600)), "still on at 02:00 the next morning")
        T.falsy(G.onShift(shift, Clock.utcAt(day, 28 * 3600)), "off at 04:00")
        T.falsy(G.onShift(shift, Clock.utcAt(day, 12 * 3600)), "off at noon")
        local wd = Clock.weekday(day)
        local offToday = { from = 20 * 3600, len = 7 * 3600, off = { wd, wd } }
        T.falsy(G.onShift(offToday, Clock.utcAt(day, 21 * 3600)), "a day off is off")
        T.falsy(G.onShift(offToday, Clock.utcAt(day, 26 * 3600)), "the night of a day off belongs to that day")
        local w = world(T)
        for _, id in ipairs(w.orgOrder) do
            local o = w.orgs[id]
            local s = G.shiftFor(w.seed, o)
            T.eq(G.decodeShift(G.encodeShift(s)).from, s.from, "shift round-trips")
            T.ok(s.off[1] ~= s.off[2], "two different days off")
            if o.tier == "street" then T.ok(s.from >= 15 * 3600 or s.from <= 3 * 3600, "street shifts start in the evening") end
            if o.tier == "pro" or o.tier == "premier" then T.ok(s.from >= 6 * 3600 and s.from <= 11 * 3600, "sanctioned shifts start in the morning") end
        end
    end,

    presence_is_senior_first_and_racers_are_at_the_track = function(T)
        local G = T.Core.get("paddock.garages")
        local World = T.Core.get("paddock.world")
        local Clock = T.Core.get("world.clock")
        local w = world(T)
        local org = w.orgs[w.orgOrder[1]]
        local day = Clock.eastern(1790000000).dayIndex
        local o = { id = org.id, shift = { from = 10 * 3600, len = 8 * 3600, off = { 7, 7 } } }
        local at = Clock.utcAt(day, 12 * 3600)
        local people = World.members(w, org.id)
        local here = G.present(w.seed, o, people, at, function() return false end)
        T.ok(#here >= 3 and #here <= G.MAX_BODIES, "a crew is present")
        T.ok(here[1].role == "manager" or here[1].role == "engineer", "the most senior person first")
        local busy = G.present(w.seed, o, people, at, function() return true end)
        for _, p in ipairs(busy) do T.ok(p.role ~= "driver", "drivers racing soon are at the track") end
        T.eq(#G.present(w.seed, o, people, Clock.utcAt(day, 20 * 3600), nil), 0, "nobody off shift")
        local s = G.sites()[1]
        local p1, p2 = G.standPoint(s, 1, 4), G.standPoint(s, 2, 4)
        T.ok(G.distance(s, p1) < 6 and G.distance(s, p2) < 6, "bodies stand at the garage")
        T.ok(math.abs(p1.x - p2.x) + math.abs(p1.y - p2.y) > 1, "and not on top of each other")
    end,

    talk_speaks_only_from_facts_and_varies = function(T)
        local Talk = T.Core.get("paddock.talk")
        local P = T.Core.get("paddock.projection")
        local w = world(T)
        local org = w.orgs[w.orgOrder[3]]
        local person = w.people[org.engineerId]
        local ctx = { person = person, org = org, seriesName = "Neon Cup" }
        local first = Talk.line(ctx, 100, 0)
        T.match(first.id, "^in", "a first meeting is an introduction")
        T.ok(first.text:find(person.display, 1, true) or first.text:find(org.name, 1, true), "introductions name someone real")
        -- without a next race, no line may mention one
        for n = 1, 30 do
            local l = Talk.line(ctx, 100 + n, n)
            T.falsy(l.text:find("{", 1, true), "every slot filled")
            T.falsy(l.id:match("^nx") or l.id:match("^ls"), "no race talk without a race: " .. l.id)
        end
        ctx.next = { route = "The Cut", when = "21:40", weather = "rain" }
        ctx.last = { route = "Hook", driver = "A. Driver", position = 2, state = "finished" }
        local ids = {}
        for n = 1, 40 do ids[Talk.line(ctx, 200 + n, n).id] = true end
        local distinct = 0
        for _ in pairs(ids) do distinct = distinct + 1 end
        T.ok(distinct >= 4, "repeat visits hear different lines (" .. distinct .. ")")
        T.eq(Talk.line(ctx, 250, 7).id, Talk.line(ctx, 250, 7).id, "and the same visit replays the same line")
        T.falsy(P.findHidden(Talk.facts(ctx)), "talk facts carry no hidden key")
        T.eq(Talk.ordinal(1), "1st"); T.eq(Talk.ordinal(12), "12th")
    end,
}
