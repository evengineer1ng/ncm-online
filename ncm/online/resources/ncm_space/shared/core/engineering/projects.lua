-- ncm-core module: engineering.projects
--
-- The Workshop (L361; docs 19/21/32/33/48; rulings L120, L134, L353): one project grammar for the engineering lanes
-- a player works on the bench --
--
--   knowledge + competency + a legitimate operation + committed inputs -> bounded uncertainty -> an attributed outcome
--
--   teardown   DESTRUCTIVE reverse engineering (Diagnostics). The specimen is consumed when the work starts. Four stages
--              (doc 48): 1 dimensions, mass, materials; 2 ratings and limits; 3 manufacturing method; 4 reproducible
--              principles. How deep you get is set by your reverse-engineering skill. What you learn is the design's
--              true numbers inside the error band your knowledge and skill leave (`engineering.lineage.errorBand`).
--   fabricate  make ONE physical prototype from what you know (Fabrication). `engineering.lineage.reverseEngineer`
--              does the physics: usually a little worse and heavier, now and then better, or nothing usable. A
--              nonfunctional result is still a physical thing you own (L134); it just cannot do the job.
--   promote    turn a working prototype into your own immutable DESIGN, a new lineage that names its parent (Design).
--              Promotion never rewrites the prototype (L134).
--   run        repeat manufacture of your design (Design/production): n units, the production skill decides how many
--              come out as rejects.
--
-- Pure: no database, no clock. The host passes seeded rng streams, competency state and what is known; it owns money,
-- time, custody and persistence. Costs are MATERIALS only -- your own hands cost nothing (L353). Competency credit is
-- for completed work and never reads the outcome (`engineering.competency`'s invariant).
local Core = NcmCore

Core.define("engineering.projects", function(C)
    local M = { version = "0.1.0" }
    local Lineage = C.get("engineering.lineage")
    local Comp = C.get("engineering.competency")
    local Sys = C.get("engineering.systems")
    local Seed = C.get("world.seed")

    M.KINDS = { teardown = true, fabricate = true, promote = true, run = true }
    M.SLOTS = 2                 -- bench slots per engineer
    M.RUN_MAX = 3               -- units per manufacturing run

    -- Doc 48's four stages of tearing a thing down. `minSkill` is the reverse-engineering skill (0..1000) the stage needs.
    M.STAGES = {
        { n = 1, rung = "measured", minSkill = 0, label = "Dimensions, mass and materials",
          reveals = { "massKg", "envelope", "kind", "propellant", "family" } },
        { n = 2, rung = "specimen", minSkill = 40, label = "Ratings: output, heat and limits",
          reveals = { "thrustN", "forceN", "torqueNm", "capacityKg", "ispS", "heatKw", "pulseS", "armM", "gimbalDeg",
                      "limitK", "rejectKw", "capacityKjK", "throttleTauS" } },
        { n = 3, rung = "specimen", minSkill = 100, label = "Manufacturing method and internal layout",
          reveals = { "process" } },
        { n = 4, rung = "documents", minSkill = 200, label = "Reproducible design principles",
          reveals = { "principles" } },
    }
    M.FABRICATE_MIN_STAGE = 3
    M.PROMOTE_MIN_STAGE = 4
    M.MATERIALS = { teardown = 0.02, fabricate = 0.40, promote = 0.25, run = 0.30 }   -- share of the source's price
    M.MINUTES = { teardown = { 5, 15 }, fabricate = { 10, 30 }, promote = { 10, 10 }, run = { 10, 10 }, runPerUnit = 5 }
    M.MASS_SPAN_KG = 150        -- a part this heavy takes the longest time
    M.REJECT_MAX = 0.25         -- a run's reject chance with no production skill

    -- Installed-component families -> the twelve mechanical families competency credits (L120).
    M.FAMILY_OF = {
        propulsor = "power_unit", impulse_actuator = "power_unit", attitude = "steering", tank = "power_unit",
        gearbox = "transmission", slipstream = "electrical",
    }

    local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

    --- Which stage a reverse-engineering skill reaches (1..4).
    function M.depth(state)
        local v = Comp.valueOf(state, "reverse_engineering")
        local d = 1
        for _, st in ipairs(M.STAGES) do if v >= st.minSkill then d = st.n end end
        return d
    end

    --- The knowledge rung a reached stage gives (`engineering.lineage.KNOWLEDGE`).
    function M.rungOf(stage)
        local st = M.STAGES[clamp(math.floor(tonumber(stage) or 0), 1, #M.STAGES)]
        return (tonumber(stage) or 0) >= 1 and st.rung or nil
    end

    --- The discipline level (0..1000) a lane's outcome is judged by.
    function M.disciplineValue(state, discipline) return Comp.disciplineLevel(state, discipline) or 0 end

    --- Materials (eddies) a project commits up front. Never zero for real work.
    function M.cost(kind, price, n)
        local share = M.MATERIALS[kind]
        if not share then return nil, "unknown_kind" end
        local p = math.max(0, tonumber(price) or 0)
        local units = kind == "run" and clamp(math.floor(tonumber(n) or 1), 1, M.RUN_MAX) or 1
        return math.max(10, math.floor(p * share * units + 0.5))
    end

    --- Seconds a project takes. Heavier parts take longer; a teardown takes time per stage reached.
    function M.duration(kind, massKg, opts)
        opts = opts or {}
        local span = M.MINUTES[kind]
        if not span then return nil, "unknown_kind" end
        local f = clamp((tonumber(massKg) or 0) / M.MASS_SPAN_KG, 0, 1)
        local minutes = span[1] + (span[2] - span[1]) * f
        if kind == "teardown" then
            minutes = minutes * clamp(tonumber(opts.stages) or 1, 1, #M.STAGES) / #M.STAGES
            minutes = math.max(span[1] * 0.5, minutes)
        elseif kind == "run" then
            minutes = minutes + M.MINUTES.runPerUnit * clamp(math.floor(tonumber(opts.n) or 1), 1, M.RUN_MAX)
        end
        return math.floor(minutes * 60 * clamp(tonumber(opts.timeScale) or 1, 0.001, 100) + 0.5)
    end

    -- the facts a stage can read off a design: its perf, its thermal block, its mass and envelope
    local function factSource(d, key)
        if key == "massKg" then return d.massKg end
        if key == "envelope" then return d.envelope end
        if key == "family" then return d.family end
        if key == "kind" or key == "propellant" then return d.perf and d.perf[key] end
        if d.perf and d.perf[key] ~= nil then return d.perf[key] end
        if d.thermal and d.thermal[key] ~= nil then return d.thermal[key] end
        return nil
    end

    local PROCESS = {
        reaction_engine = "a regeneratively cooled chamber, machined, its injector plate the hard part",
        pulse_reaction = "a stacked charge cartridge on a sprung stroke rail",
        attitude_control = "opposed micro-thruster pairs on a common manifold",
        propellant_tank = "a wound composite shell with a baffled liner",
        gearbox = "machined gear sets in a cast case",
        wake_system = "a sealed sensor head and a controller board",
    }

    --- What tearing `d` down to `stage` reveals, measured with `skill` (reverse engineering, 0..1000).
    --- Numbers come back within the error band of the stage's rung; words come back as they are.
    function M.reveal(d, stage, skill, rng)
        local facts = {}
        for _, st in ipairs(M.STAGES) do
            if st.n > stage then break end
            local band = Lineage.errorBand(st.rung, skill)
            for _, key in ipairs(st.reveals) do
                if key == "process" then
                    facts.process = PROCESS[d.perf and d.perf.kind] or "conventional fabrication"
                elseif key == "principles" then
                    facts.principles = "complete: the drawings could be redrawn from this"
                else
                    local v = factSource(d, key)
                    if type(v) == "number" then
                        facts[key] = { value = v * math.max(0.05, 1 + (rng and rng:normal(0, band) or 0)), band = band }
                    elseif type(v) == "table" then
                        local e = {}
                        for i, x in ipairs(v) do e[i] = type(x) == "number" and x * math.max(0.05, 1 + (rng and rng:normal(0, band) or 0)) or x end
                        facts[key] = { value = e, band = band }
                    elseif v ~= nil then
                        facts[key] = { value = v }
                    end
                end
            end
        end
        return facts
    end

    --- Plan a teardown: how deep this engineer will get, how long, what it costs.
    function M.planTeardown(d, state, opts)
        if type(d) ~= "table" or not d.perf then return nil, "not_physical" end
        local stages = M.depth(state)
        return { stages = stages, seconds = M.duration("teardown", d.massKg, { stages = stages, timeScale = opts and opts.timeScale }),
                 cost = M.cost("teardown", d.price) }
    end

    --- The key output a grade is judged on.
    local function keyOutput(perf)
        return perf.thrustN or perf.forceN or perf.torqueNm or perf.capacityKg or perf.outputW or 1
    end

    --- Grade a working prototype against its source: output per mass, the way an engineer would read it.
    function M.grade(src, proto)
        local r = keyOutput(proto.perf) / math.max(1e-9, keyOutput(src.perf))
        local m = (src.massKg or 1) / math.max(1e-9, proto.massKg or 1)
        local score = r * m ^ 0.3
        if score >= 1.0 then return "good", score end
        if score >= 0.93 then return "neutral", score end
        return "poor", score
    end

    --- Fabricate one prototype of `src` from what is known of it (`stage`, 1..4) with this engineer's competency.
    --- Returns { class = "good" | "neutral" | "poor" | "junk", spec = the prototype's physical design (nil for junk),
    ---           reason, chance } or nil + why when the work cannot start.
    function M.fabricate(src, stage, state, rng, meta)
        if type(src) ~= "table" or not src.perf then return nil, "not_physical" end
        if (tonumber(stage) or 0) < M.FABRICATE_MIN_STAGE then return nil, "knowledge" end
        meta = meta or {}
        local registry = Lineage.newRegistry()
        local root = Seed.deepCopy(src)
        registry:newLineage(root, "night_city", src.makerKey or "?", { id = src.designId })
        local rung = M.rungOf(stage)
        local competency = M.disciplineValue(state, "fabrication")
        local rec, failed = registry:reverseEngineer(src.designId, { knowledge = rung, competency = competency, rng = rng,
            origin = "night_city", principal = meta.makerKey, intent = "reconstruct" })
        if not rec then
            return { class = "junk", reason = failed and failed.reason or "nothing usable", chance = failed and failed.chance }
        end
        local spec = rec.design
        spec.id = nil
        local class = M.grade(src, spec)
        return { class = class, spec = spec, chance = Lineage.failureChance(rung, competency), errorBand = rec.errorBand }
    end

    --- Can this prototype be promoted to a design by this engineer? (complete knowledge of its source, and it works)
    function M.canPromote(protoClass, stage)
        if protoClass == "junk" then return false, "nonfunctional" end
        if (tonumber(stage) or 0) < M.PROMOTE_MIN_STAGE then return false, "knowledge" end
        return true
    end

    --- A manufacturing run: which of n units come out as rejects (the production skill moves the odds).
    function M.run(n, state, rng)
        n = clamp(math.floor(tonumber(n) or 1), 1, M.RUN_MAX)
        local production = Comp.valueOf(state, "production")
        local pReject = M.REJECT_MAX * (1 - clamp(production, 0, Comp.CEILING) / Comp.CEILING)
        local units = {}
        for i = 1, n do units[i] = (rng and rng() or 1) < pReject and "reject" or "good" end
        return units, pReject
    end

    --- The competency operations a COMPLETED project credits. There is no outcome parameter, on purpose.
    function M.credit(kind, opts)
        opts = opts or {}
        local fam = M.FAMILY_OF[opts.family or ""]
        local ops = {}
        local function op(skill, base) ops[#ops + 1] = { skillId = skill, familyId = fam, base = base, jobLevel = opts.jobLevel or 0, completed = true } end
        if kind == "teardown" then
            op("reverse_engineering", 50 * clamp(tonumber(opts.stages) or 1, 1, #M.STAGES))
            op("inspection", 15)
        elseif kind == "fabricate" then
            op("forming", 30); op("process_control", 30); op("finishing", 30)
        elseif kind == "promote" then
            op("specification", 60); op("tooling", 30)
        elseif kind == "run" then
            op("production", 20 * clamp(tonumber(opts.n) or 1, 1, M.RUN_MAX)); op("tooling", 10)
        end
        return ops
    end

    --- Apply a completed project's credit to a competency state. Returns the state and the deltas.
    function M.applyCredit(state, kind, opts)
        state = state or Comp.newState()
        local all = {}
        for _, o in ipairs(M.credit(kind, opts)) do
            local _, deltas = Comp.apply(state, o)
            for _, d in ipairs(deltas) do all[#all + 1] = d end
        end
        return state, all
    end

    --- A skill or discipline level in words. Competency is never shown as a number (engineering.competency).
    M.WORDS = { { 0, "Untrained" }, { 1, "Novice" }, { 60, "Apprentice" }, { 150, "Capable" }, { 300, "Skilled" },
                { 500, "Expert" }, { 750, "Master" } }
    function M.word(value)
        local w = M.WORDS[1][2]
        for _, x in ipairs(M.WORDS) do if (tonumber(value) or 0) >= x[1] then w = x[2] end end
        return w
    end

    --- The engineer card: each discipline in words, and how deep a teardown reaches.
    function M.card(state)
        local out = { disciplines = {}, depth = M.depth(state) }
        for _, d in ipairs(Comp.DISCIPLINE_IDS) do
            out.disciplines[#out.disciplines + 1] = { id = d, word = M.word(M.disciplineValue(state, d)) }
        end
        return out
    end

    --- Validate a physical spec the way installation will (so a host never stores a design it cannot register).
    function M.valid(spec)
        if type(spec) ~= "table" or type(spec.perf) ~= "table" then return false, "no perf" end
        local ok, errs = Sys.validate(spec.perf)
        if not ok then return false, table.concat(errs, "; ") end
        return true
    end

    return M
end)
