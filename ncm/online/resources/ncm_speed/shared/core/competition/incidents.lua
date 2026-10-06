-- ncm-core module: competition.incidents
-- Zero-fault incident scoring (L56, P39). An incident is a contact — with a car, an object, a person, a lane
-- line — scored into a severity band by delta-v and expressed as seconds added to the driver's corrected time.
-- No blame: both cars in a car-to-car contact carry the incident. Pure: hosts feed samples, get records back.
--
-- A sample is { t, x, y, z, v (speed m/s), vx?, vy?, h? (vehicle health 0..1) }. Where a host has no velocity
-- vector, it is derived from two consecutive samples of the same driver.
local Core = NcmCore

Core.define("competition.incidents", function(C)
    local M = { version = "0.0.1" }

    M.DEFAULT = {
        bands = { { dv = 2.0, mult = 1 }, { dv = 6.0, mult = 2 }, { dv = 12.0, mult = 4 } },   -- delta-v thresholds (m/s) → ×1 ×2 ×4
        baseSec = 2,          -- seconds for a ×1 incident
        escalation = 0.5,     -- each prior incident by the same driver adds this much to the multiplier …
        maxMult = 3,          -- … up to this cap on the escalation factor
        contactM = 4.5,       -- two cars closer than this (planar, centre to centre) are in contact
        dedupeSec = 2.0,      -- the same pair cannot log twice within this window
        episodeSec = 3.0,     -- repeated evidence from one sustained crash belongs to one incident
        episodeM = 15,        -- ...provided it is still in the same physical place
        objectDecelMps = 8,   -- a speed drop of this much between samples with no car nearby is an object hit
        objectWindowSec = 0.6,
        neighbourM = 8,       -- another car within this distance means the decel was a car contact, not an object
        healthDelta = 0.05,   -- vehicle health drop that counts as an object hit on its own
        maxSpeedMps = 90,     -- faster than this between samples is a teleport, never a contact
        alignSec = 0.25,      -- two drivers' samples further apart in time than this are not comparable (KB-34)
        neighbourStaleSec = 0.35,  -- a neighbour sample older than this cannot prove nobody was alongside (KB-34)
    }

    local function rules(r)
        local out = {}
        for k, v in pairs(M.DEFAULT) do out[k] = v end
        for k, v in pairs(r or {}) do out[k] = v end
        return out
    end
    M.rules = rules

    local function planar(a, b)
        local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
        return math.sqrt(dx * dx + dy * dy)
    end

    --- Velocity vector of a driver from two samples (prev, cur); falls back to speed along +x when only one.
    local function velocity(prev, cur)
        if cur.vx and cur.vy then return cur.vx, cur.vy end
        if prev and cur.t and prev.t and cur.t > prev.t then
            local dt = cur.t - prev.t
            return ((cur.x or 0) - (prev.x or 0)) / dt, ((cur.y or 0) - (prev.y or 0)) / dt
        end
        return cur.v or 0, 0
    end

    --- Severity band 0..#bands for a delta-v in m/s (0 = below the first threshold: no incident).
    function M.band(dv, r)
        r = rules(r)
        local band = 0
        for i, b in ipairs(r.bands) do if dv >= b.dv then band = i end end
        return band
    end

    --- Seconds for a band, escalated by the driver's prior incident count in this session.
    function M.seconds(band, priorCount, r)
        r = rules(r)
        if band <= 0 then return 0 end
        local mult = (r.bands[band] or r.bands[#r.bands]).mult
        local esc = math.min(r.maxMult, 1 + r.escalation * (priorCount or 0))
        return r.baseSec * mult * esc
    end

    --- Car-to-car contact between drivers a and b. a/b = { driverId, prev, cur }. Returns two symmetric records
    --- (zero-fault) or nil when the cars are apart or the closing speed is below the first band.
    function M.carCar(a, b, r)
        r = rules(r)
        if not (a.cur and b.cur) then return nil end
        -- KB-34: the two cars are sampled by their own clients, so the host may hand us readings taken at
        -- different moments. Comparing them as if simultaneous is how real contact went unseen: at 50 m/s a
        -- fifth of a second is 10 m, twice contactM. Refuse rather than guess.
        local skew = math.abs((a.cur.t or 0) - (b.cur.t or 0))
        if skew > r.alignSec then return nil, "unaligned" end
        local d = planar(a.cur, b.cur)
        if d > r.contactM then return nil end
        local avx, avy = velocity(a.prev, a.cur)
        local bvx, bvy = velocity(b.prev, b.cur)
        -- a teleport (reconnect, race control) reads as an impossible speed; that is not a contact
        if avx * avx + avy * avy > r.maxSpeedMps ^ 2 or bvx * bvx + bvy * bvy > r.maxSpeedMps ^ 2 then return nil end
        local dv = math.sqrt((avx - bvx) ^ 2 + (avy - bvy) ^ 2)
        local band = M.band(dv, r)
        if band == 0 then return nil end
        local t = math.max(a.cur.t or 0, b.cur.t or 0)
        local function rec(me, other)
            return { kind = "car", band = band, dv = dv, other = other.driverId, x = me.cur.x, y = me.cur.y, z = me.cur.z or 0, t = t, attributed = "both" }
        end
        return rec(a, b), rec(b, a)
    end

    --- Object contact for one driver: a sharp speed drop (or a vehicle health drop) with no other car nearby.
    --- neighbours = array of the other drivers' latest samples.
    function M.object(prev, cur, neighbours, r)
        r = rules(r)
        if not (prev and cur) then return nil end
        local dt = (cur.t or 0) - (prev.t or 0)
        if dt <= 0 or dt > r.objectWindowSec then return nil end
        -- A neighbour clears this driver of car contact only if we know where it actually was. A stale or
        -- untimed reading proves nothing (absent is not zero), and treating it as "nobody nearby" is what
        -- filed car-to-car contact as scenery (KB-34).
        for _, n in ipairs(neighbours or {}) do
            if planar(n, cur) <= r.neighbourM then return nil end
            if not n.t or math.abs((cur.t or 0) - n.t) > r.neighbourStaleSec then return nil, "neighbour_unknown" end
        end
        local decel = (prev.v or 0) - (cur.v or 0)
        local healthDrop = (prev.h and cur.h) and (prev.h - cur.h) or 0
        if decel < r.objectDecelMps and healthDrop < r.healthDelta then return nil end
        local band = math.max(1, M.band(decel, r))
        return { kind = "object", band = band, dv = decel, x = cur.x, y = cur.y, z = cur.z or 0, t = cur.t, attributed = "self" }
    end

    --- Canonical vehicle-damage change. The platform tells the host that damage changed but does not identify
    --- the world object or expose collision impulse, so severity is deliberately coarse. A nearby competitor
    --- must be ruled out by the host before calling this as an object incident.
    function M.damage(prev, cur, speed, pos, t, r)
        r = rules(r)
        if type(cur) ~= "table" then return nil, "no_snapshot" end
        local function bodyTotal(v)
            local n = 0
            for _, x in ipairs(v.bodyDamage or {}) do n = n + math.max(0, tonumber(x) or 0) end
            return n
        end
        local hp = tonumber(cur.health)
        local oldHp = prev and tonumber(prev.health) or nil
        local hpDrop = oldHp and math.max(0, oldHp - (hp or oldHp)) or 0
        local body = bodyTotal(cur)
        local bodyDrop = prev and math.max(0, body - bodyTotal(prev)) or body
        local masksChanged = prev and ((cur.brokenGlass or 0) ~= (prev.brokenGlass or 0)
            or (cur.brokenLights or 0) ~= (prev.brokenLights or 0) or (cur.tires or 0) ~= (prev.tires or 0))
        local damaged = hpDrop >= 0.002 or bodyDrop >= 0.002 or masksChanged
        if not damaged and not prev then
            damaged = (hp and hp < 0.999) or body >= 0.002 or (cur.brokenGlass or 0) ~= 0
                or (cur.brokenLights or 0) ~= 0 or (cur.tires or 0) ~= 0
        end
        if not damaged then return nil, "no_material_change" end
        local evidence = math.max(hpDrop * 100, bodyDrop * 10)
        local band = 1
        if evidence >= 2 or (tonumber(speed) or 0) >= 20 then band = 2 end
        if evidence >= 8 then band = 3 end
        return { kind = "object", band = band, dv = 0, x = pos and pos.x, y = pos and pos.y,
            z = pos and pos.z or 0, t = t, attributed = "self", signal = "vehicle_damage",
            healthDrop = hpDrop, bodyDelta = bodyDrop }
    end

    --- Per-session ledger with dedupe. :add(driverId, rec, rules) -> rec with seconds, or nil when deduped.
    M.Ledger = {}
    M.Ledger.__index = M.Ledger
    function M.Ledger.new()
        return setmetatable({ byDriver = {}, lastPair = {}, lastEpisode = {} }, M.Ledger)
    end
    local function pairKey(a, b) if a < b then return a .. "|" .. b end return b .. "|" .. a end
    function M.Ledger:count(driverId) return #(self.byDriver[driverId] or {}) end
    function M.Ledger:sum(driverId)
        local s = 0
        for _, i in ipairs(self.byDriver[driverId] or {}) do s = s + (i.seconds or 0) end
        return s
    end
    function M.Ledger:add(driverId, rec, r)
        r = rules(r)
        if rec.kind == "car" and rec.other then
            local k = driverId .. "#" .. pairKey(driverId, rec.other)   -- each driver carries their own half of a contact
            local last = self.lastPair[k]
            if last and (rec.t or 0) - last < r.dedupeSec then return nil, "deduped" end
            self.lastPair[k] = rec.t or 0
        end
        if rec.kind == "object" then
            local last = self.lastEpisode[driverId]
            local samePlace = last and rec.x and rec.y and last.x and last.y and planar(last, rec) <= r.episodeM
            if last and samePlace and (rec.t or 0) - (last.t or 0) < r.episodeSec then return nil, "coalesced" end
            self.lastEpisode[driverId] = { t = rec.t or 0, x = rec.x, y = rec.y }
        end
        local list = self.byDriver[driverId] or {}
        self.byDriver[driverId] = list
        rec.seconds = rec.seconds or M.seconds(rec.band, #list, r)
        list[#list + 1] = rec
        return rec
    end

    return M
end)
