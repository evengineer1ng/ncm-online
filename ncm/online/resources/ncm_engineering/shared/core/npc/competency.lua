-- ncm-core module: npc.competency
--
-- PERSONALITY TRANSFERS; SKILL DOES NOT (L322; doc 54 §N). A brilliant Night City racer entering Fireball for the
-- first time is still aggressive and still clutch (`npc.behavior` reads the same traits everywhere), but may be
-- terrible at attitude control, closure rates and three-dimensional traffic. Competency is per DOMAIN, stored on the
-- same person record (`person.domains[domain]`), learned by exposure, never granted:
--   snowglobe: piloting (holding a commanded vector), attitude (turning the machine), traffic3d (reading closure and
--              closest approach), energy_mgmt (propellant, charge and heat), launch_reaction, and per-discipline
--              fireball / sprint; plus per-machine familiarity.
-- A terrestrial driver starts LOW with a small TRANSFER from related road skills (a launch is partly a person's
-- reflexes; racecraft is partly reading other racers). Learning is headroom-shaped and per hour of racing, faster for
-- adaptable drivers who give good feedback (bent by `paddock.attributes.modulate`, like every Paddock growth), and
-- weighted by fidelity: flying it physically teaches more than a tactical simulation, which teaches more than an
-- abstract one. Values are 0..100 like every Paddock stat, and hidden like them.
local Core = NcmCore

Core.define("npc.competency", function(C)
    local M = { version = "0.1.0" }
    local Attr = C.get("paddock.attributes")

    M.SKILLS = {
        snowglobe = { "piloting", "attitude", "traffic3d", "energy_mgmt", "launch_reaction", "fireball", "sprint" },
    }
    -- road skill -> space skill, as a fraction carried over on first entry
    M.TRANSFER = {
        snowglobe = {
            launch_reaction = { launch = 0.40 },
            traffic3d = { racecraft = 0.20, overtaking = 0.05 },
            piloting = { consistency = 0.20, vehicle_sympathy = 0.05 },
            energy_mgmt = { tyre_sympathy = 0.10, vehicle_sympathy = 0.10 },
            attitude = {},
            fireball = {},
            sprint = { launch = 0.10 },
        },
    }
    M.FLOOR = 8                         -- a complete novice still knows which way is forward
    M.FIDELITY = { physical = 1.0, tactical = 0.6, abstract = 0.25 }
    M.PER_HOUR = 30                     -- points per hour of racing at full headroom, average learner, physical

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    --- Give a person a domain record if they have none. opts.native = a level (0..100) for people who grew up there
    --- (Snowglobe's own pilots), applied before the transfer. Returns the domain record.
    function M.enter(person, domain, opts)
        opts = opts or {}
        person.domains = person.domains or {}
        if person.domains[domain] then return person.domains[domain] end
        local a = person.attrs or {}
        local rec = { skills = {}, hours = 0, machines = {}, disciplines = {} }
        for _, k in ipairs(M.SKILLS[domain] or {}) do
            local v = opts.native or M.FLOOR
            local tr = M.TRANSFER[domain][k] or {}
            local roads = {}
            for road in pairs(tr) do roads[#roads + 1] = road end
            table.sort(roads)                                 -- fixed order: the same bits in every process (KB-343)
            for _, road in ipairs(roads) do v = v + tr[road] * (a[road] or 50) end
            rec.skills[k] = math.floor(clamp(v, 1, 99) * 10 + 0.5) / 10
        end
        person.domains[domain] = rec
        return rec
    end

    function M.level(person, domain, skill)
        local d = person.domains and person.domains[domain]
        return d and d.skills[skill] or M.FLOOR
    end

    --- Learn from racing. exp = { hours, fidelity, discipline?, machineId? }. Returns the per-skill gains.
    function M.learn(person, domain, exp)
        local d = M.enter(person, domain)
        local a = person.attrs or {}
        local rate = M.PER_HOUR * (0.5 + ((a.adaptability or 50) + (a.feedback or 50)) / 200)
        local w = (M.FIDELITY[exp.fidelity] or 0.25) * (exp.hours or 0)
        local gains = {}
        for _, k in ipairs(M.SKILLS[domain] or {}) do
            local discOnly = (k == "fireball" or k == "sprint")
            if not discOnly or k == exp.discipline then
                local v = d.skills[k]
                local g = Attr.modulate(person.personality, "adaptability", rate * w * (100 - v) / 100)
                d.skills[k] = clamp(v + g, 1, 99)
                gains[k] = g
            end
        end
        d.hours = d.hours + (exp.hours or 0)
        if exp.discipline then d.disciplines[exp.discipline] = (d.disciplines[exp.discipline] or 0) + (exp.hours or 0) end
        if exp.machineId then d.machines[exp.machineId] = (d.machines[exp.machineId] or 0) + (exp.hours or 0) end
        return gains
    end

    --- Familiarity with one machine, 0..1 (saturating with hours in it).
    function M.familiarity(person, domain, machineId)
        local d = person.domains and person.domains[domain]
        local h = d and d.machines[machineId] or 0
        return 1 - math.exp(-h / 2)
    end

    return M
end)
