-- ncm-core module: competition.chrome
-- NCM Chrome: vehicle quickhacks on OPEN//77's hacking framework (`L200`, IDEA-067, IDEA-076..079, IDEA-681).
--
-- **Chrome affects vehicles only.** The platform runs the part it is good at -- target selection, the warned
-- interruptible upload (1..80 m), line-of-sight challenges, Self-ICE, purge and the native UPLOAD / INCOMING bars.
-- Every grade NCM registers is `cosmetic` with `damage = 0`, so the platform never touches the person. When an
-- upload reaches `impact`, NCM applies the VEHICLE consequence itself. This module is the pure half: the roster,
-- the platform grades built from it, and how active effects compose into one performance ceiling and one
-- handling contributor per vehicle. The host (`ncm_world/server/chrome.lua`) owns the platform calls.
--
-- **Speed goes through the Carrier governor, never `setPerformance`.** The gear chain is stretched
-- (`parts.handling.GEAR_HEADROOM`, the Carrier's `applyGears`) so the native cap sits above every Machine, and the
-- Carrier tapers drive onto `governedTopSpeedKph`, which `handling.lua` composes per Machine (`L157`, `L161`).
-- Machines are held under that headroom by driveScale/gripScale, so there is room to dip into:
--   * POWER SURGE / OVERCLOCK raise the `chrome` layer's driveScale and topSpeedScale (up to its 1.25 clamp);
--   * LIMITER / LIMP lower driveScale and impose a CAP -- a fraction of the Machine's authored baseline passed as
--     the most-restrictive-wins argument of `Handling.topSpeedKph`, so it can cut deeper than the 0.80 clamp.
-- Governor hacks need a Carrier-bound, player-driven NCM Machine. On anything else (AI traffic) they refuse by
-- name; the native-lever hacks (engine, tyre, lights, health, explode) work on every network vehicle.
--
-- Nothing here is balanced. Every number is a first-pass tunable, owned by this table.
local Core = NcmCore

Core.define("competition.chrome", function()
    local M = { version = "0.1.0" }

    M.DECK_ID = "ncm.chrome"
    M.ICE_ID = "ncm.chrome.ice"
    M.PURGE_ID = "ncm.chrome.purge"
    M.DEFINITION_VERSION = 1

    -- The roster, in the order the Scanner cycles through it. `target`:
    --   "other" -- uploaded onto another vehicle through the platform (a player-driven car) or NCM (AI traffic);
    --   "self"  -- acts on the player's own vehicle, no upload onto anyone.
    -- `effect` is what `impact` does to the TARGET vehicle; see `M.effectFor`.
    M.ROSTER = {
        { id = "limiter", label = "LIMITER", target = "other", range = 60, uploadMs = 2000, cooldownMs = 20000,
          durationMs = 8000, effect = { cap = 0.70, handling = { driveScale = 0.6 } }, carrier = true },
        { id = "engine_cut", label = "ENGINE CUT", target = "other", range = 45, uploadMs = 2500, cooldownMs = 30000,
          durationMs = 3000, effect = { engineCut = true } },
        { id = "limp", label = "LIMP", target = "other", range = 45, uploadMs = 3000, cooldownMs = 45000,
          durationMs = 12000, effect = { cap = 0.35, handling = { driveScale = 0.35, gripScale = 0.85 },
                                         healthTo = 0.35 } },
        { id = "tire_sabotage", label = "TIRE SABOTAGE", target = "other", range = 35, uploadMs = 3000,
          cooldownMs = 45000, effect = { breakTire = true } },
        { id = "power_surge", label = "POWER SURGE", target = "other", range = 60, uploadMs = 2000, cooldownMs = 25000,
          durationMs = 5000, effect = { handling = { driveScale = 1.6, gripScale = 0.8, topSpeedScale = 1.15 } },
          carrier = true },
        { id = "overclock", label = "OVERCLOCK", target = "other", range = 45, uploadMs = 3500, cooldownMs = 60000,
          durationMs = 6000, effect = { handling = { driveScale = 2.0, gripScale = 0.7, topSpeedScale = 1.25 },
                                        after = { engineCutMs = 2500, healthDrop = 0.3 } }, carrier = true },
        { id = "blackout", label = "BLACKOUT", target = "other", range = 60, uploadMs = 2000, cooldownMs = 30000,
          durationMs = 15000, effect = { blackout = true } },
        { id = "total_failure", label = "TOTAL FAILURE", target = "other", range = 25, uploadMs = 8000,
          cooldownMs = 600000, effect = { explode = true }, catastrophic = true },
        { id = "ally_purge", label = "ALLY PURGE", target = "other", range = 30, uploadMs = 1000, cooldownMs = 20000,
          effect = { purge = true }, support = true },
        { id = "system_restore", label = "SYSTEM RESTORE", target = "self", channelMs = 3000, cooldownMs = 90000,
          effect = { restore = true } },
        { id = "purge", label = "PURGE", target = "self", cooldownMs = 8000, effect = { purge = true } },
        { id = "self_ice", label = "SELF-ICE", target = "self", passive = true },
    }

    M.BY_ID = {}
    for i, h in ipairs(M.ROSTER) do h.order = i; M.BY_ID[h.id] = h end

    function M.hack(id) return M.BY_ID[id] end

    --- The hacks that are grades of the platform deck: everything uploaded onto another vehicle.
    function M.deckHacks()
        local out = {}
        for _, h in ipairs(M.ROSTER) do if h.target == "other" then out[#out + 1] = h end end
        return out
    end

    --- `Open77.hacking.define` for the deck. **Every grade is cosmetic, nonlethal and damage 0**: the car is the
    --- target, never the driver. `short_circuit` is the one kind whose status is a bounded 0..2000 ms disruption,
    --- and `statusMs = 0` makes it a pure carrier for NCM's own consequence.
    function M.deckDefinition()
        local grades = {}
        for _, h in ipairs(M.deckHacks()) do
            grades[#grades + 1] = {
                id = h.id, kind = "short_circuit", range = h.range, uploadMs = h.uploadMs, staminaCost = 0,
                cooldownMs = h.cooldownMs, damage = 0, statusMs = 0, recoveryMs = 1000,
                nonlethal = true, cosmetic = true, friendlyFire = h.support == true,
                interruptOnDamage = true, interruptDamage = 0,
            }
        end
        return { id = M.DECK_ID, version = M.DEFINITION_VERSION, grades = grades }
    end

    M.ICE_GRADE = { id = "street", charges = 2, rechargeMs = 45000 }
    M.PURGE_GRADE = { id = "street", staminaCost = 0, cooldownMs = 8000, allowSelf = true, allowAlly = true,
                      range = 30, cancelUploads = true, removeStatuses = true }

    function M.iceDefinition()
        return { id = M.ICE_ID, version = M.DEFINITION_VERSION, grades = { M.ICE_GRADE } }
    end

    function M.purgeDefinition()
        return { id = M.PURGE_ID, version = M.DEFINITION_VERSION, grades = { M.PURGE_GRADE } }
    end

    --- The inert implant grade the platform needs beside each hacking definition (same id, version, grade ids).
    local INERT = { normalDamage = 0, chargedDamage = 0, knockbackMeters = 0, cooldownMs = 100, chargeMs = 100,
                    nonlethal = true, cosmetic = true }
    function M.implantDefinition(id, slot, profile, gradeIds)
        local grades = {}
        for _, gid in ipairs(gradeIds) do
            local g = { id = gid }
            for k, v in pairs(INERT) do g[k] = v end
            grades[#grades + 1] = g
        end
        return { id = id, version = M.DEFINITION_VERSION, slot = slot, profile = profile, grades = grades }
    end

    function M.implants()
        local deckGrades = {}
        for _, h in ipairs(M.deckHacks()) do deckGrades[#deckGrades + 1] = h.id end
        return {
            M.implantDefinition(M.DECK_ID, "operating_system", "cyberdeck", deckGrades),
            M.implantDefinition(M.ICE_ID, "self_ice", "self_ice", { M.ICE_GRADE.id }),
            M.implantDefinition(M.PURGE_ID, "purge", "active_purge", { M.PURGE_GRADE.id }),
        }
    end

    -- -------------------------------------------------------------------------------------------------------
    -- Active effects on one vehicle, and what they compose into
    -- -------------------------------------------------------------------------------------------------------
    --
    -- `effects` is an array of { hack, startedAt, endsAt }. Two outputs, both consumed by `handling.lua`:
    --   * capFactor -- the LOWEST active cap, as a fraction of the Machine's authored baseline top speed; nil
    --                  when nothing caps it. Applied most-restrictive-wins, exactly like a class cap.
    --   * handling  -- the PRODUCT of every active effect's multipliers, as the `chrome` contributor. The lever
    --                  clamps (and the 0.80..1.25 topSpeedScale clamp) in `parts.handling` still bound it.

    function M.active(effects, nowMs)
        local out = {}
        for _, e in ipairs(effects or {}) do
            if e.endsAt == nil or e.endsAt > nowMs then out[#out + 1] = e end
        end
        return out
    end

    function M.capFactor(effects, nowMs)
        local cap
        for _, e in ipairs(M.active(effects, nowMs)) do
            local h = M.BY_ID[e.hack]
            local c = h and h.effect and h.effect.cap
            if c and (not cap or c < cap) then cap = c end
        end
        return cap
    end

    --- The cap in km/h against an authored baseline. No baseline, no cap: nothing is invented.
    function M.capKph(effects, nowMs, baselineKph)
        local f, b = M.capFactor(effects, nowMs), tonumber(baselineKph)
        if not f or not b then return nil end
        return math.floor(b * f + 0.5)
    end

    function M.handling(effects, nowMs)
        local out, any = { source = "chrome" }, false
        for _, e in ipairs(M.active(effects, nowMs)) do
            local h = M.BY_ID[e.hack]
            local hv = h and h.effect and h.effect.handling
            if hv then
                for lever, m in pairs(hv) do out[lever] = (out[lever] or 1.0) * m; any = true end
            end
        end
        return any and out or nil
    end

    --- May this actor use this hack at all? Distinct reasons, never one standing in for another.
    function M.admit(facts)
        if type(facts) ~= "table" then return nil, "no_facts" end
        local h = M.BY_ID[facts.hack]
        if not h then return nil, "unknown_hack" end
        if h.passive then return nil, "passive" end
        if h.target == "other" then
            if facts.targetVehicle == nil then return nil, "no_target" end
            if facts.targetVehicle == facts.ownVehicle then return nil, "own_vehicle" end
            local d = tonumber(facts.distance)
            if d == nil then return nil, "no_position" end
            if d > h.range then return nil, "out_of_range" end
            if h.carrier and not facts.targetBound then return nil, "needs_driven_ncm_machine" end
        else
            if facts.ownVehicle == nil then return nil, "not_in_a_vehicle" end
        end
        local ready = tonumber(facts.cooldownUntil)
        if ready and tonumber(facts.now) and facts.now < ready then return nil, "cooling_down" end
        return h
    end

    return M
end)
