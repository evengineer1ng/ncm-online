-- ncm-core module: paddock.garages
-- Garages as rented, shared workplaces (doc 44 §11, L224.6, IDEA-735).
--
-- An organization does not own a garage; it RENTS one, on a shift. One site serves several teams across the day:
-- a sanctioned team by day and a street team by night is the natural pairing, and where density requires it a
-- site stacks up to `DEPTH` tenants whose shifts may overlap. Where an org's people physically are is then a pure
-- function of the Eastern clock: on shift at their garage, at the track around their own races, otherwise nowhere
-- a player can meet them.
--
-- Pure and deterministic. The host persists each org's `garageId` and `shift` once assigned, so a team never moves
-- because another team folded; only a site marked bad (or a new org) is (re)assigned.
local Core = NcmCore

Core.define("paddock.garages", function(C)
    local M = { version = "0.1.0", DEPTH = 3, MAX_BODIES = 6 }
    local Hash = C.get("vocabulary.hash")
    local Clock = C.get("world.clock")
    local Data = C.get("paddock.garages_data")

    local H = 3600
    -- Where each tier's shift starts (Eastern seconds of day), how far one org's start may drift from it, and how
    -- long it lasts. Street skews to the night like its racing (§11); the sanctioned tiers keep office hours.
    M.SHIFT = {
        street = { from = 18 * H, spread = 3 * H, len = 7 * H },
        regional = { from = 9 * H, spread = 2 * H, len = 7 * H },
        pro = { from = 8 * H, spread = 2 * H, len = 8 * H },
        premier = { from = 9 * H, spread = 1 * H, len = 8 * H },
    }
    M.NIGHT = { street = true }

    -- The track takes a team's drivers away from the garage this long either side of their own race.
    M.AWAY_BEFORE_SEC = 30 * 60
    M.AWAY_AFTER_SEC = 20 * 60

    local KIND_LABEL = { garage = "garage", workshop = "workshop", parking = "parking garage" }

    function M.sites() return Data.SITES end

    local byId
    function M.site(id)
        if not byId then
            byId = {}
            for _, s in ipairs(Data.SITES) do byId[s.id] = s end
        end
        return byId[id or ""]
    end

    --- "the Heywood workshop (g014)"-style label for a player. Never a coordinate.
    function M.label(site)
        if not site then return "no fixed garage" end
        return ("%s %s"):format(site.district or "Night City", KIND_LABEL[site.kind] or "garage")
    end

    --- One org's weekly shift: { from, len, off = { weekday, weekday } } in Eastern time.
    function M.shiftFor(seed, org)
        local spec = M.SHIFT[org.tier] or M.SHIFT.regional
        local r = Hash.stream(seed, "shift", org.id)
        local from = spec.from + math.floor((r() * 2 - 1) * spec.spread / 1800 + 0.5) * 1800
        local a = r:int(0, 6)
        local b = (a + r:int(2, 4)) % 7
        return { from = from % 86400, len = spec.len, off = { a, b } }
    end

    function M.encodeShift(s)
        if type(s) ~= "table" then return "" end
        return ("%d:%d:%d,%d"):format(s.from or 0, s.len or 0, (s.off or {})[1] or 0, (s.off or {})[2] or 0)
    end

    function M.decodeShift(text)
        if type(text) ~= "string" then return nil end
        local f, l, a, b = text:match("^(%d+):(%d+):(%d+),(%d+)$")
        if not f then return nil end
        return { from = tonumber(f), len = tonumber(l), off = { tonumber(a), tonumber(b) } }
    end

    --- Is the shift running at `utc`? A shift that crosses midnight belongs to the day it started on, so a street
    --- team's Friday night is still Friday at 01:30 Saturday.
    function M.onShift(shift, utc)
        if type(shift) ~= "table" then return false end
        local e = Clock.eastern(utc)
        for back = 0, 1 do
            local day = e.dayIndex - back
            local startSod = shift.from
            local sod = e.secondsOfDay + back * 86400
            if sod >= startSod and sod < startSod + shift.len then
                local wd = Clock.weekday(day)
                local off = shift.off or {}
                if wd ~= off[1] and wd ~= off[2] then return true end
            end
        end
        return false
    end

    --- The time class a shift occupies: tenants of a shared site should mostly not overlap.
    local function nightTier(tier) return M.NIGHT[tier] == true end

    --- Assign garages. `orgs` is a list of { id, tier, garageId? }; `bad` a set of site ids out of the pool.
    --- Returns orgId -> siteId for EVERY org (existing good assignments kept as they are). Deterministic.
    --- Preference, in order: a site holding one tenant of the OTHER time class (a day team pairs with a night
    --- team), then an empty site, then any site under DEPTH.
    function M.assign(seed, orgs, bad, depth)
        bad = bad or {}
        depth = depth or M.DEPTH
        local pool = {}
        for _, s in ipairs(Data.SITES) do if not bad[s.id] then pool[#pool + 1] = s end end
        table.sort(pool, function(a, b)
            local ha, hb = Hash.fnv1a32(Hash.key(seed, "site", a.id)), Hash.fnv1a32(Hash.key(seed, "site", b.id))
            if ha ~= hb then return ha < hb end
            return a.id < b.id
        end)
        local tenants = {}         -- siteId -> { night = n, day = n, total = n }
        local out = {}
        local function add(siteId, tier)
            local t = tenants[siteId] or { night = 0, day = 0, total = 0 }
            tenants[siteId] = t
            if nightTier(tier) then t.night = t.night + 1 else t.day = t.day + 1 end
            t.total = t.total + 1
        end
        local sorted = {}
        for _, o in ipairs(orgs) do sorted[#sorted + 1] = o end
        table.sort(sorted, function(a, b) return a.id < b.id end)
        for _, o in ipairs(sorted) do
            if o.garageId and not bad[o.garageId] and M.site(o.garageId) then
                out[o.id] = o.garageId
                add(o.garageId, o.tier)
            end
        end
        for _, o in ipairs(sorted) do
            if not out[o.id] and #pool > 0 then
                local night = nightTier(o.tier)
                local start = Hash.fnv1a32(Hash.key(seed, "rent", o.id)) % #pool
                local pick, pickRank
                for k = 0, #pool - 1 do
                    local s = pool[1 + (start + k) % #pool]
                    local t = tenants[s.id] or { night = 0, day = 0, total = 0 }
                    local rank
                    if t.total == 1 and ((night and t.day == 1) or (not night and t.night == 1)) then rank = 1
                    elseif t.total == 0 then rank = 2
                    elseif t.total < depth then rank = 3 end
                    if rank and (not pickRank or rank < pickRank) then pick, pickRank = s, rank end
                    if pickRank == 1 then break end
                end
                if pick then out[o.id] = pick.id; add(pick.id, o.tier) end
            end
        end
        return out
    end

    --- Who of an org is at its garage at `utc`, most senior first, at most MAX_BODIES. `people` is the org's active
    --- members; `racingSoon(personId)` says whether that person's own race keeps them at the track right now.
    --- The owner shows up one shift day in five; a human-managed org has no NPC manager to show.
    local ORDER = { manager = 1, engineer = 2, strategist = 3, driver = 4, owner = 5 }
    function M.present(seed, org, people, utc, racingSoon)
        local shift = org.shift
        if not M.onShift(shift, utc) then return {} end
        local day = Clock.eastern(utc).dayIndex
        local out = {}
        for _, p in ipairs(people or {}) do
            local here = p.state == "active"
            if here and p.role == "owner" then here = Hash.unit(seed, "owner_visit", org.id, day) < 0.2 end
            if here and p.role == "driver" and racingSoon and racingSoon(p.id) then here = false end
            if here and p.role == "driver" and not (p.seat and (p.seat:match("^race") or p.seat == "reserve")) then here = false end
            if here then out[#out + 1] = p end
        end
        table.sort(out, function(a, b)
            local ra, rb = ORDER[a.role] or 9, ORDER[b.role] or 9
            if ra ~= rb then return ra < rb end
            return a.id < b.id
        end)
        while #out > M.MAX_BODIES do table.remove(out) end
        return out
    end

    --- Where a body stands: a small deterministic ring around the site's pin, so a crew does not stack on one spot.
    function M.standPoint(site, index, count)
        local n = math.max(1, count or 1)
        local a = (index - 1) / n * 2 * math.pi
        local r = 2.5 + (index % 2) * 1.5
        return { x = site.x + math.cos(a) * r, y = site.y + math.sin(a) * r, z = site.z,
            yaw = (math.deg(a) + 180) % 360 }
    end

    --- Plain distance in the plane; hosts use it for "is a player near this garage".
    function M.distance(site, pos)
        if not site or type(pos) ~= "table" then return math.huge end
        local dx, dy = (pos.x or 0) - site.x, (pos.y or 0) - site.y
        return math.sqrt(dx * dx + dy * dy)
    end

    return M
end)
