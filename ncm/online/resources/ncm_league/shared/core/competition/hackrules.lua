-- ncm-core module: competition.hackrules
--
-- What a race's rules say about vehicle quickhacks (owner brief 2026-10-08: "Do not make every NCM race a cyberwar").
--   allowed     street / unsanctioned: nobody official cares; consequences are physical only
--   restricted  mild interference tolerated (severity <= RESTRICTED_MAX); anything heavier is an offence
--   prohibited  formal motorsport: every offensive hack is an offence
-- **The rules never gate the physics.** A hack uploaded in a prohibited race still lands (owner ruling 2026-10-08:
-- humans "allowed, penalised if caught"); what the rules decide is whether it is an OFFENCE, how likely officials are
-- to ATTRIBUTE it, and the sporting PENALTY if they do. Attribution is a separate fact from the physical incident: a
-- car that explodes has exploded whether or not anyone knows who did it.
local Core = NcmCore

Core.define("competition.hackrules", function(C)
    local M = { version = "0.1.0" }
    local Chrome = C.get("competition.chrome")
    local Discipline = C.get("competition.discipline")

    M.LEVELS = { allowed = true, restricted = true, prohibited = true }
    M.RESTRICTED_MAX = 2
    M.BY_TIER = { street = "allowed", sanctioned = "prohibited", both = "restricted" }

    --- The level for a tier ("street", "regional", "pro", "premier" -- Paddock tiers -- or a discipline tier).
    function M.forTier(tier)
        tier = tostring(tier or "street")
        if M.BY_TIER[tier] then return M.BY_TIER[tier] end
        return tier == "street" and "allowed" or "prohibited"   -- Paddock regional/pro/premier are sanctioned
    end

    --- The level for a discipline id: its own `hacking` field wins, else its tier's.
    function M.forDiscipline(id)
        local d = Discipline.byId(id)
        if d and M.LEVELS[d.hacking or ""] then return d.hacking end
        return M.forTier(d and d.tier or "street")
    end

    --- Is using `hackId` an offence under `level`? Defensive actions never are.
    function M.offence(level, hackId)
        local h = Chrome.hack(hackId)
        if not (h and Chrome.harms(hackId)) then return false end
        if level == "prohibited" then return true end
        if level == "restricted" then return (h.severity or 0) > M.RESTRICTED_MAX end
        return false
    end

    --- The chance officials ATTRIBUTE an offending hack to its source. Heavier hacks leave more evidence; a car that
    --- explodes is investigated. `stealth` 0..1 (an attacker's skill at covering it) shaves some off.
    function M.detectChance(level, hackId, stealth)
        if not M.offence(level, hackId) then return 0 end
        local h = Chrome.hack(hackId)
        local sev = h.severity or 1
        local base = (level == "prohibited" and 0.30 or 0.20) + 0.10 * sev
        if h.catastrophic then base = base + 0.15 end
        base = base * (1 - 0.5 * math.max(0, math.min(1, tonumber(stealth) or 0)))
        return math.max(0, math.min(0.95, base))
    end

    --- Roll attribution with a seeded stream. Returns true when officials know who did it.
    function M.attribute(level, hackId, rng, stealth)
        local p = M.detectChance(level, hackId, stealth)
        return p > 0 and rng() < p
    end

    --- The sporting penalty for an ATTRIBUTED offence: { kind = "none" } | { kind = "time", seconds } | { kind = "dsq" }.
    function M.penalty(level, hackId)
        if not M.offence(level, hackId) then return { kind = "none" } end
        local h = Chrome.hack(hackId)
        local sev = h.severity or 1
        if level == "prohibited" and sev >= 3 then return { kind = "dsq" } end
        if level == "restricted" and sev >= 5 then return { kind = "dsq" } end
        return { kind = "time", seconds = (level == "prohibited" and 15 or 10) * sev }
    end

    return M
end)
