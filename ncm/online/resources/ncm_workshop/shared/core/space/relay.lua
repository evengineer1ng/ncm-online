-- ncm-core module: space.relay
--
-- RELAY (L322; doc 54 §L): a team carries CONTINUITY through several machines. A sprint (or any leg-able discipline)
-- split into N legs -- N is data, never 4 -- with an exchange zone between legs. The BATON IS NOT DECIDED (owner): a
-- physical object, cargo, a passenger who must change vehicles, an official token... Every candidate shares one
-- physical requirement, and only that is built here: the incoming and outgoing machines must be TOGETHER at the
-- exchange -- both inside the zone, nearly matched in velocity, for long enough -- and the outgoing leg does not count
-- until the token has moved. Leaving early is a fault. What the token IS gets decided later and plugs in as the
-- `transfer` rule (a passenger might need a longer hold and a lower relative speed than a token).
local Core = NcmCore

Core.define("space.relay", function(C)
    local M = { version = "0.1.0" }

    M.DEFAULTS = { vRelMaxMs = 2.0, holdS = 1.0 }

    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function len(a) return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3]) end

    --- A relay: legs = { { zone = {centre, radiusM} or nil for the last }, ... }; team = { machine ids by leg }.
    function M.new(legs, team, transfer)
        local t = {}
        for k, v in pairs(M.DEFAULTS) do t[k] = v end
        for k, v in pairs(transfer or {}) do t[k] = v end
        return { legs = legs, team = team, transfer = t, leg = 1, holder = team[1], heldS = 0, exchanges = {}, faults = {} }
    end

    --- Advance the exchange at the end of the current leg with both machines' universe states.
    --- `incoming`/`outgoing` = { pos, vel }. Returns { transferred = t } | { fault = "..." } | nil.
    function M.exchange(r, incoming, outgoing, t, dt)
        local leg = r.legs[r.leg]
        if not leg or not leg.zone or r.leg >= #r.team then return nil end
        local z = leg.zone
        local inA = len(sub(incoming.pos, z.centre)) <= z.radiusM
        local inB = len(sub(outgoing.pos, z.centre)) <= z.radiusM
        local vrel = len(sub(incoming.vel, outgoing.vel))
        if not inB and r.wasInZone and r.holder == r.team[r.leg] then
            r.faults[#r.faults + 1] = { leg = r.leg, t = t, fault = "early departure: left the zone without the token" }
            r.wasInZone = false
            r.heldS = 0
            return { fault = "early departure" }
        end
        r.wasInZone = inB
        if inA and inB and vrel <= r.transfer.vRelMaxMs then
            r.heldS = r.heldS + dt
            if r.heldS >= r.transfer.holdS then
                r.exchanges[#r.exchanges + 1] = { leg = r.leg, t = t, from = r.team[r.leg], to = r.team[r.leg + 1], vRelMs = vrel }
                r.leg = r.leg + 1
                r.holder = r.team[r.leg]
                r.heldS, r.wasInZone = 0, false
                return { transferred = t }
            end
        else
            r.heldS = 0
        end
        return nil
    end

    --- Whose leg counts now: only the holder's progress is the team's.
    function M.counts(r, machineId) return r.holder == machineId end

    return M
end)
