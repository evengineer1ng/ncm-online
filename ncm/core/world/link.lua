-- ncm-core module: world.link
--
-- One NCM driver across servers (L323; doc 52 §2, doc 54 §S). Night City (OPEN//77) knows a driver by its
-- `ncmDriverId` (uuid, bound to the platform user); Los Santos (FiveM) knows a player by a FiveM identifier. A LINK CODE
-- joins them, consensually and from inside both games: the driver asks for a code in one world and claims it in the
-- other. The hub keeps, as committed `world.seed` history:
--   links.d_<ncmDriverId>       { night_city = <id>, los_santos = <id> }       which host identity is this driver
--   discovered.d_<ncmDriverId>  { los_santos = true, snowglobe = true }         domains they have legitimately reached
--   legs.d_<ncmDriverId>        { {domain, week, venue, position, raceS, ...} } results usable as event legs
--   facts.<domain>              { race, race_crash, clean_race }                each world's Race Week evidence (hidden)
-- Codes are ephemeral (minutes), single-use, and never the identity itself. Pure: hosts move the bytes.
local Core = NcmCore

Core.define("world.link", function(C)
    local M = { version = "0.1.0" }
    local Hash = C.get("vocabulary.hash")
    local ME = C.get("space.multievent")

    M.CODE_TTL_S = 600
    M.ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"     -- no 0/O, 1/I
    M.DOMAINS = { "night_city", "los_santos", "snowglobe" }

    local function dk(id) return "d_" .. tostring(id) end
    M.key = dk

    function M.base()
        return { links = {}, discovered = {}, legs = {}, facts = { night_city = {}, los_santos = {}, snowglobe = {} } }
    end

    --- A fresh code for `driverId` (in `fromDomain`), stored in the ephemeral `codes` table.
    function M.issue(codes, driverId, fromDomain, identity, now, salt)
        local s = Hash.stream("ncm-link-code", driverId, now, salt or "")
        local code
        for _ = 1, 20 do
            local c = {}
            for i = 1, 6 do local k = s:int(1, #M.ALPHABET); c[i] = M.ALPHABET:sub(k, k) end
            code = table.concat(c)
            if not codes[code] then break end
        end
        codes[code] = { driver = driverId, from = fromDomain, identity = identity, expires = now + M.CODE_TTL_S }
        return code
    end

    --- Claim a code in another domain. Returns mods (to commit) or nil, reason.
    function M.claim(codes, state, code, domain, identity, now, at)
        code = tostring(code or ""):upper()
        local c = codes[code]
        if not c then return nil, "unknown code" end
        codes[code] = nil                                                     -- single use, whatever happens next
        if now > c.expires then return nil, "expired code" end
        if c.from == domain then return nil, "a code must be claimed in the OTHER world" end
        local k = dk(c.driver)
        local rec = {}
        for _, d in ipairs(M.DOMAINS) do rec[d] = state.links[k] and state.links[k][d] or nil end
        rec[c.from] = c.identity or rec[c.from]
        rec[domain] = identity
        local disc = {}
        for _, d in ipairs(M.DOMAINS) do disc[d] = state.discovered[k] and state.discovered[k][d] or nil end
        disc[domain] = true
        return {
            { id = "link#" .. k .. "#" .. at, at = at, path = { "links", k }, op = "set", value = rec },
            { id = "disc#" .. k .. "#" .. at, at = at, path = { "discovered", k }, op = "set", value = disc },
        }, c.driver
    end

    --- The driver behind a host identity in a domain (nil if not linked).
    function M.driverOf(state, domain, identity)
        local keys = {}
        for k in pairs(state.links) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            if state.links[k][domain] == identity then return k:sub(3) end
        end
        return nil
    end

    --- A discovery: the driver has legitimately reached `domain`.
    function M.discover(state, driverId, domain, at)
        local k = dk(driverId)
        local disc = {}
        for _, d in ipairs(M.DOMAINS) do disc[d] = state.discovered[k] and state.discovered[k][d] or nil end
        if disc[domain] then return nil end
        disc[domain] = true
        return { id = "disc#" .. k .. "#" .. domain .. "#" .. at, at = at, path = { "discovered", k }, op = "set", value = disc }
    end

    --- A finished race as a possible event leg.
    function M.legMod(state, driverId, leg, at)
        local k = dk(driverId)
        if not state.legs[k] then
            return { id = "legs#" .. k .. "#" .. at, at = at, path = { "legs", k }, op = "set", value = { leg } }
        end
        return { id = "leg#" .. k .. "#" .. at .. "#" .. tostring(leg.venue), at = at, path = { "legs", k }, op = "append", value = leg }
    end

    --- This Race Week's THREE CITIES event (cross-domain triathlon, doc 54 §M).
    function M.threeCities(week, format)
        return { id = "three-cities/" .. tostring(week), format = format or "points",
            legs = { { domain = "night_city", discipline = "any" }, { domain = "los_santos", discipline = "any" },
                     { domain = "snowglobe", discipline = "sprint|fireball" } } }
    end

    --- Score it from the linked drivers' legs this week: each driver's best result per domain.
    function M.scoreThreeCities(state, ev, week)
        local results = {}
        for li, leg in ipairs(ev.legs) do
            results[li] = {}
            local keys = {}
            for k in pairs(state.legs) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local best
                for _, l in ipairs(state.legs[k]) do
                    if l.domain == leg.domain and l.week == week and l.state == "finished" then
                        if not best or (l.position or 99) < (best.position or 99)
                            or ((l.position or 99) == (best.position or 99) and (l.raceS or 1e9) < (best.raceS or 1e9)) then best = l end
                    end
                end
                if best then
                    results[li][#results[li] + 1] = { id = k:sub(3), position = best.position, state = "finished", raceS = best.raceS,
                        startT = best.startT, finishT = best.finishT }
                end
            end
        end
        return ME.score(ev, results)
    end

    --- Who may see the Three Cities event: only drivers who have discovered every domain in it.
    function M.visible(state, driverId, ev)
        local d = state.discovered[dk(driverId)] or {}
        return ME.visibleTo(ev, { discovered = d })
    end

    return M
end)
