-- ncm-core module: paddock.scouting
-- The scouting report: what a team manager is told about a Paddock driver (doc 44 §4.3).
--
-- The simulation keeps the numbers; players get WORDS derived deterministically from them. Every word is a lossy
-- projection of a stat the race model actually reads (`paddock.sim`) or the growth model uses -- never invented
-- biography, never a number. Three layers:
--
--   * SIMULATED CAREER. Earned tags (`paddock.tags`) need evidence, and on 2026-10-09 74% of Online's 868 drivers
--     had none to show (free agents were mostly bare or "Rookie"), so hiring could not tell a good signing from a
--     bad one. `history` gives every NPC a pre-Paddock career: real `paddock.sim` races against peers of their own
--     level, in a neutral car, seeded by the driver's id. It is evidence about the DRIVER (the car is held at 50),
--     it replays identically, and it is labelled simulated wherever it is shown. It counts toward earned tags.
--   * IMPRESSIONS. Graded word banks per facet (pace, consistency, aggression, traffic, starts, risk, conditions,
--     machinery, growth) and COMPOUND tags read from relationships between stats ("Mercurial" = quick but
--     inconsistent). Banks overlap and can pull against one another, so no single word means "buy".
--   * KNOWLEDGE. The driver never changes; how well the team understands them does. Starts in the Paddock, the
--     simulated career (scouting reports, a quarter weight) and having them on your own team decide how many
--     impressions show, most salient first. Earned tags always show.
--
-- Nothing returned here carries a hidden key (`paddock.attributes.HIDDEN`); hosts still run `assertNoHidden`.
local Core = NcmCore

Core.define("paddock.scouting", function(C)
    local M = { version = "0.1.0" }
    local Attr = C.get("paddock.attributes")
    local Sim = C.get("paddock.sim")
    local Tags = C.get("paddock.tags")
    local Hash = C.get("vocabulary.hash")

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
    local function st(a, k) return (a and tonumber(a[k])) or 50 end

    -- ---- simulated career --------------------------------------------------------------------------------------

    M.HISTORY_VERSION = 1
    M.LEVEL_LABELS = { street = "Street", regional = "Regional", pro = "Pro", premier = "Premier" }
    -- Cost (measured on Online's drivers, Lua 5.4 instruction counts): ~260k per career on average, 322k worst, so
    -- ONE career fits a metered slice (< 400k, KB-211) and hosts compute them one per tick in the background; a
    -- report from a cached career is ~2k. Views never simulate (`ctx.cacheOnly`).
    M.SIM_RACES_MAX = 12         -- races actually simulated; a longer career scales the counts (sampled)
    M.FIELD = 8                  -- cars per simulated race
    M.PEERS = 16                 -- the peer pool a career is raced against
    M.COURSE = { distanceM = 3000, laps = 1 }
    M.BASE_SEC = 180

    --- The tier a driver's ability places them in (nearest tier mean to their rating).
    function M.levelOf(attrs)
        local r, best, bestD = Attr.rating(attrs), "street", math.huge
        for _, t in ipairs(Attr.TIERS) do
            local d = math.abs(Attr.TIER_STATS[t].mean - r)
            if d < bestD then best, bestD = t, d end
        end
        return best
    end

    --- Career starts before the Paddock: none at 18, ~6 a year after, capped (a 40-year-old is not a 130-start rookie).
    function M.careerStarts(id, age, seed)
        local u = Hash.unit(seed or "", "career", id or "")
        return clamp(math.floor(((age or 25) - 18) * 6 * (0.6 + 0.8 * u) + 0.5), 0, 72)
    end

    local cache = setmetatable({}, { __mode = "k" })

    --- The career if it has been computed this session, else nil. Never simulates.
    function M.cachedHistory(person)
        local hit = cache[person]
        return hit and hit.h or nil
    end

    --- A driver's simulated career: { starts, wins, podiums, finishes, dnfs, crashes, contacts, mistakes, passes,
    --- passedBy, launchGain, placesGained, upsetWins, wetStarts, wetTop3, nightStarts, nightTop3, best, recent,
    --- level, simulated = true }. Deterministic in (seed, id, attrs, age). Cached per person table for the session:
    --- daily growth does not re-roll a career that has already been told. ctx.yield, if given, is called every few
    --- races so a metered host can spread one career over several slices.
    function M.history(person, ctx)
        ctx = ctx or {}
        local a = person.attrs or {}
        local key = M.HISTORY_VERSION .. "|" .. tostring(ctx.age) .. "|" .. tostring(ctx.seed)
        local hit = cache[person]
        if hit and hit.key == key then return hit.h end
        local seed = ctx.seed or ""
        local id = person.id or "?"
        local starts = M.careerStarts(id, ctx.age, seed)
        local h = { starts = starts, wins = 0, podiums = 0, finishes = 0, dnfs = 0, crashes = 0, contacts = 0, mistakes = 0,
            passes = 0, passedBy = 0, launchGain = 0, placesGained = 0, upsetWins = 0, wetStarts = 0, wetTop3 = 0,
            nightStarts = 0, nightTop3 = 0, recent = {}, simulated = true, version = M.HISTORY_VERSION }
        local level = M.levelOf(a)
        h.level = level
        local n = math.min(starts, M.SIM_RACES_MAX)
        if n > 0 then
            local rng = Hash.stream(seed, "history", M.HISTORY_VERSION, id)
            local peers = {}
            for i = 1, M.PEERS do peers[i] = { id = "peer" .. i, attrs = Attr.rollDriver(rng, level, 26), carPerf = 50 } end
            local me = { id = id, attrs = a, carPerf = 50 }
            local best
            for race = 1, n do
                local field, used = { me }, {}
                while #field < M.FIELD do
                    local k = rng:int(1, M.PEERS)
                    if not used[k] then used[k] = true; field[#field + 1] = peers[k] end
                end
                local grid = Sim.qualify(field, rng)
                local cond = { roadWetness = (rng() < 0.2) and 0.7 or 0, light = (rng() < 0.3) and "night" or "day" }
                local res = Sim.simulate(grid, M.COURSE, cond, rng, { baseSec = M.BASE_SEC, tier = level })
                local wet, night = cond.roadWetness >= 0.5, cond.light == "night"
                if wet then h.wetStarts = h.wetStarts + 1 end
                if night then h.nightStarts = h.nightStarts + 1 end
                local mine
                for _, e in ipairs(res.entrants) do if e.id == id then mine = e end end
                for _, ev in ipairs(res.events) do
                    local ids = ev.ids or {}
                    if ev.kind == "overtake" then
                        if ids[1] == id then h.passes = h.passes + 1 elseif ids[2] == id then h.passedBy = h.passedBy + 1 end
                    elseif ev.kind == "contact" and (ids[1] == id or ids[2] == id) then h.contacts = h.contacts + 1
                    elseif ev.kind == "mistake" and ids[1] == id then h.mistakes = h.mistakes + 1 end
                end
                -- places made off the line: grid slot vs order after segment 1, read from the splits
                if mine and mine.splits and mine.splits[1] then
                    local ahead = 0
                    for _, e in ipairs(res.entrants) do
                        if e.id ~= id and e.splits and e.splits[1] and e.splits[1] < mine.splits[1] then ahead = ahead + 1 end
                    end
                    h.launchGain = h.launchGain + ((mine.grid - 1) - ahead)
                end
                local pos = mine.state == "finished" and mine.position or #field
                if mine.state == "finished" then
                    h.finishes = h.finishes + 1
                    h.placesGained = h.placesGained + (mine.grid - pos)
                    if pos == 1 then h.wins = h.wins + 1; if mine.grid >= 5 then h.upsetWins = h.upsetWins + 1 end end
                    if pos <= 3 then
                        h.podiums = h.podiums + 1
                        if wet then h.wetTop3 = h.wetTop3 + 1 end
                        if night then h.nightTop3 = h.nightTop3 + 1 end
                    end
                    if not best or pos < best then best = pos end
                else
                    h.dnfs = h.dnfs + 1
                    if mine.dnfReason ~= "mechanical" then h.crashes = h.crashes + 1 end
                end
                h.recent[#h.recent + 1] = pos
                if #h.recent > 5 then table.remove(h.recent, 1) end
                if ctx.yield and race % 4 == 0 then ctx.yield() end     -- hosts slice a career (KB-211)
            end
            -- a longer career than was simulated: scale the counts (rates are what the sample measured)
            if starts > n then
                local f = starts / n
                for _, k in ipairs({ "wins", "podiums", "finishes", "dnfs", "crashes", "contacts", "mistakes", "passes", "passedBy",
                    "launchGain", "placesGained", "upsetWins", "wetStarts", "wetTop3", "nightStarts", "nightTop3" }) do
                    h[k] = math.floor(h[k] * f + 0.5)
                end
            end
            h.sampled = n
            h.best = best
        end
        cache[person] = { key = key, h = h }
        return h
    end

    local COUNTS = { "starts", "wins", "podiums", "finishes", "dnfs", "crashes", "contacts", "wetStarts", "wetTop3",
        "nightStarts", "nightTop3", "placesGained", "upsetWins" }

    --- Paddock evidence plus the simulated career, for the earned-tag predicates. Season/recent fields stay the
    --- Paddock's own (a career is not this season's form).
    function M.mergedEvidence(evidence, history)
        local out = {}
        for k, v in pairs(evidence or {}) do out[k] = v end
        for _, k in ipairs(COUNTS) do out[k] = (tonumber(out[k]) or 0) + (tonumber(history and history[k]) or 0) end
        return out
    end

    -- ---- impressions -----------------------------------------------------------------------------------------

    -- PACE is read against a level (the viewing team's tier, else the driver's own): a Street manager's "Rapid" is a
    -- Regional manager's "Competitive". Every other skill is read against the driver's OWN pace -- their profile, what
    -- they are good at for their level. Read against the tier instead, a weak driver collected every negative word
    -- at once (measured on Online 2026-10-09: "Hesitant in packs" 20% vs "Decisive passer" 8%) and the nuance drowned.
    -- Skills sit around a driver's core pace with sd ~8 (Online, 868 drivers). Traits read on the absolute 0-100 scale.
    M.PACE_SD = 9
    M.PROFILE_SD = 8

    local function facets(a, level)
        local mean = (Attr.TIER_STATS[level] or Attr.TIER_STATS.regional).mean
        local core = 0.45 * st(a, "pace") + 0.35 * st(a, "race_pace") + 0.20 * st(a, "consistency")  -- sim.performance
        local function z(v) return (v - core) / M.PROFILE_SD end
        local f = {}
        f.pace = (core - mean) / M.PACE_SD
        f.racePace = z(st(a, "race_pace"))
        f.oneLap = st(a, "quali_pace") - st(a, "race_pace")
        f.consistency = z(st(a, "consistency"))
        f.pressure = z(st(a, "pressure_handling"))
        f.launch = z(st(a, "launch"))
        f.overtaking = z(st(a, "overtaking"))
        f.racecraft = z(st(a, "racecraft"))
        f.defending = z(st(a, "defending"))
        f.wet = z(st(a, "wet_weather_skill"))
        f.night = z(st(a, "night_skill"))
        f.sympathy = z(st(a, "vehicle_sympathy"))
        f.feedback = z(st(a, "feedback"))
        f.learning = z((st(a, "adaptability") + st(a, "feedback")) / 2)
        f.risk = Sim.riskFactor(a)
        f.lateSigma = clamp(1 + (st(a, "confidence_volatility") - 50) / 200 - (st(a, "pressure_handling") - 50) / 200, 0.6, 1.5)
        for _, k in ipairs({ "aggression", "discipline", "mistake_rate", "confidence_volatility", "mettle", "ego", "loyalty" }) do
            f[k] = st(a, k)
        end
        f.headroom = st(a, "potential") - core
        f.peakStart, f.peakEnd = st(a, "peak_start"), st(a, "peak_end")
        return f
    end
    M._facets = facets

    -- { id, label, facet, test(f, ctx) -> salience or nil }. One word per facet at most (first match wins), so the
    -- banks are ordered strongest first. Salience orders what a thin scouting report shows.
    local function above(v, t, s) return v >= t and (s + (v - t)) or nil end
    local function below(v, t, s) return v <= t and (s + (t - v)) or nil end
    M.WORDS = {
        -- pace (sim.performance: the driver blend)
        { "rapid", "Rapid", "pace", function(f) return above(f.pace, 1.6, 2.0) end },
        { "quick", "Quick", "pace", function(f) return above(f.pace, 0.9, 1.6) end },
        { "competitive", "Competitive", "pace", function(f) return above(f.pace, 0.35, 1.1) end },
        { "midfield", "Midfield pace", "pace", function(f) return f.pace > -0.35 and 0.6 or nil end },
        { "workmanlike", "Workmanlike", "pace", function(f) return below(f.pace, -0.35, 1.0) and f.pace > -0.9 and 1.0 or nil end },
        { "limited", "Limited", "pace", function(f) return f.pace > -1.6 and (1.4 + (-0.9 - f.pace)) or nil end },
        { "struggling", "Struggling for pace", "pace", function(f) return 1.9 end },
        -- one lap vs a race (sim.qualify vs sim.performance)
        { "quali_minded", "Qualifying-minded", "onelap", function(f) return above(f.oneLap, 9, 0.9) end },
        { "race_paced", "Race-paced", "onelap", function(f) return below(f.oneLap, -9, 0.9) end },
        -- consistency (segment noise) and the late-race swing (volatility vs pressure)
        { "metronomic", "Metronomic", "consistency", function(f) return f.consistency >= 1.4 and f.confidence_volatility <= 50 and 1.6 or nil end },
        { "dependable", "Dependable", "consistency", function(f) return above(f.consistency, 0.7, 1.0) end },
        { "volatile", "Volatile", "consistency", function(f) return f.consistency <= -0.9 and f.confidence_volatility >= 58 and 1.6 or nil end },
        { "streaky", "Streaky", "consistency", function(f) return above(f.confidence_volatility, 68, 1.1) end },
        { "inconsistent", "Inconsistent", "consistency", function(f) return below(f.consistency, -0.8, 1.0) end },
        { "ice_in_veins", "Strong closer", "late", function(f) return below(f.lateSigma, 0.8, 1.2) end },
        { "fades", "Fades late", "late", function(f) return above(f.lateSigma, 1.2, 1.1) end },
        -- starts (sim: launch on segment 1)
        { "strong_starter", "Strong starter", "launch", function(f) return above(f.launch, 0.9, 1.0) end },
        { "slow_away", "Slow off the line", "launch", function(f) return below(f.launch, -0.9, 1.0) end },
        -- traffic (sim: overtaking margin and duel, defending, dirty air vs racecraft)
        { "traffic_confident", "Traffic-confident", "traffic", function(f) return f.overtaking >= 0.7 and f.racecraft >= 0.7 and 1.5 or nil end },
        { "decisive_passer", "Decisive passer", "traffic", function(f) return above(f.overtaking, 0.9, 1.1) end },
        { "picks_through", "Picks through traffic", "traffic", function(f) return above(f.racecraft, 0.9, 1.0) end },
        { "hesitant_packs", "Hesitant in packs", "traffic", function(f) return below(f.overtaking, -0.9, 1.0) end },
        { "needs_clean_air", "Needs clean air", "traffic", function(f) return below(f.racecraft, -0.9, 0.9) end },
        { "hard_to_pass", "Hard to pass", "defence", function(f) return above(f.defending, 0.9, 1.0) end },
        { "soft_defender", "Gives way easily", "defence", function(f) return below(f.defending, -0.9, 0.9) end },
        -- aggression (trait: risk factor, contact on a pass)
        { "sends_it", "Sends it", "aggression", function(f) return above(f.aggression, 80, 1.5) end },
        { "combative", "Combative", "aggression", function(f) return above(f.aggression, 68, 1.1) end },
        { "assertive", "Assertive", "aggression", function(f) return above(f.aggression, 60, 0.7) end },
        { "reluctant", "Reluctant racer", "aggression", function(f) return below(f.aggression, 22, 1.3) end },
        { "cautious", "Cautious", "aggression", function(f) return below(f.aggression, 32, 1.0) end },
        { "patient", "Patient", "aggression", function(f) return below(f.aggression, 40, 0.7) end },
        -- risk (sim.riskFactor: DNFs and mistakes)
        { "incident_prone", "Incident-prone", "risk", function(f) return above(f.risk, 1.6, 1.7) end },
        { "error_prone", "Error-prone", "risk", function(f) return f.mistake_rate >= 66 and (1.2 + (f.mistake_rate - 66) / 20) or nil end },
        { "calculated", "Calculated", "risk", function(f) return f.risk <= 0.75 and f.aggression >= 55 and 1.2 or nil end },
        { "conservative", "Conservative", "risk", function(f) return below(f.risk, 0.7, 0.9) end },
        { "disciplined", "Disciplined", "conduct", function(f) return above(f.discipline, 72, 0.8) end },
        { "undisciplined", "Undisciplined", "conduct", function(f) return below(f.discipline, 28, 1.0) end },
        -- conditions (sim.conditionFactor)
        { "wet_sharp", "Comfortable in the wet", "wet", function(f) return above(f.wet, 1.0, 1.0) end },
        { "hates_wet", "Hates the wet", "wet", function(f) return below(f.wet, -1.0, 1.0) end },
        { "night_sharp", "Sharp after dark", "night", function(f) return above(f.night, 1.0, 0.8) end },
        { "night_shy", "Struggles after dark", "night", function(f) return below(f.night, -1.0, 0.8) end },
        -- machinery (sim.riskFactor's sympathy term; engineering feedback and learning)
        { "mech_sympathy", "Mechanically sympathetic", "machine", function(f) return above(f.sympathy, 1.0, 0.8) end },
        { "hard_on_car", "Hard on equipment", "machine", function(f) return below(f.sympathy, -1.0, 0.9) end },
        { "quick_learner", "Quick learner", "learning", function(f) return above(f.learning, 1.0, 0.8) end },
        { "slow_to_adapt", "Slow to adapt", "learning", function(f) return below(f.learning, -1.0, 0.8) end },
        -- growth (attributes.growDay: headroom to the ceiling, the peak window)
        { "raw", "Raw", "growth", function(f, c) return (c.age or 30) <= 22 and f.headroom >= 14 and 1.3 or nil end },
        { "still_improving", "Still improving", "growth", function(f, c) return (c.age or 30) < f.peakStart and f.headroom >= 7 and 0.9 or nil end },
        { "late_bloomer", "Late bloomer", "growth", function(f, c) return (c.age or 0) >= 27 and f.headroom >= 7 and 1.1 or nil end },
        { "prime", "In their prime", "growth", function(f, c) return (c.age or 0) >= f.peakStart and (c.age or 0) <= f.peakEnd and 0.5 or nil end },
        { "past_peak", "Past their peak", "growth", function(f, c) return (c.age or 0) > f.peakEnd + 1 and (0.8 + ((c.age or 0) - f.peakEnd) / 10) or nil end },
        -- character (contracts: ego raises what a move must offer; loyalty)
        { "demanding", "Demanding", "character", function(f) return above(f.ego, 74, 0.6) end },
        { "team_player", "Team player", "character", function(f) return f.ego <= 30 and f.loyalty >= 50 and 0.6 or nil end },
    }

    -- Compounds: what no single number says. Shown ahead of a plain word of equal salience.
    M.COMPOUNDS = {
        { "mercurial", "Mercurial", function(f) return f.pace >= 0.9 and (f.consistency <= -0.6 or f.confidence_volatility >= 64) and 2.0 or nil end },
        { "trouble_magnet", "Trouble magnet", function(f) return f.aggression >= 64 and f.risk >= 1.3 and 1.9 or nil end },
        { "clinical_attacker", "Clinical attacker", function(f) return f.aggression >= 60 and f.risk <= 0.95 and f.overtaking >= 0.4 and 1.9 or nil end },
        { "race_day_closer", "Race-day closer", function(f) return f.oneLap <= -8 and f.pace >= 0 and 1.7 or nil end },
        { "comeback", "Comeback specialist", function(f) return f.launch <= -0.4 and (f.overtaking + f.racecraft) / 2 >= 0.7 and 1.7 or nil end },
        { "creature_of_habit", "Creature of habit", function(f) return f.sympathy >= 0.7 and f.learning <= -0.7 and 1.5 or nil end },
        { "naturally_mechanical", "Naturally mechanical", function(f) return f.feedback >= 0.9 and f.sympathy >= 0.6 and 1.5 or nil end },
        { "all_or_nothing", "All or nothing", function(f) return f.pace >= 0.6 and f.risk >= 1.45 and 1.8 or nil end },
        { "safe_hands", "Safe pair of hands", function(f) return f.pace >= -0.35 and f.risk <= 0.85 and f.consistency >= 0.4 and 1.5 or nil end },
        { "grinder", "Grinder", function(f) return f.pace < -0.35 and f.consistency >= 0.6 and f.risk <= 1.0 and 1.2 or nil end },
        { "wet_weapon", "Wet-weather weapon", function(f) return f.wet >= 1.3 and f.pace >= 0.3 and 1.6 or nil end },
        { "front_runner", "Front-runner", function(f) return f.pace >= 0.6 and f.launch >= 0.6 and f.overtaking <= -0.3 and 1.4 or nil end },
    }

    -- Leanings: milder words, used only when a report would otherwise read thinner than MIN_WORDS. An ordinary
    -- driver still leans somewhere, and saying where is still a projection of the numbers, not filler.
    M.MIN_WORDS = 3
    M.LEANINGS = {
        { "lean_launch", "Decent starter", "Hesitant starter", "launch", function(f) return f.launch end },
        { "lean_pass", "Will make a pass", "Rarely passes", "traffic", function(f) return f.overtaking end },
        { "lean_defend", "Holds position", "Concedes places", "defence", function(f) return f.defending end },
        { "lean_steady", "Fairly steady", "Up and down", "consistency", function(f) return f.consistency end },
        { "lean_wet", "Fine in the wet", "Uneasy in the wet", "wet", function(f) return f.wet end },
        { "lean_night", "Fine after dark", "Uneasy after dark", "night", function(f) return f.night end },
        { "lean_risk", "Tidy", "Scrappy", "risk", function(f) return (1 - f.risk) * 2 end },
        { "lean_aggr", "Leans aggressive", "Leans patient", "aggression", function(f) return (f.aggression - 50) / 15 end },
    }

    --- Every impression a driver has, salience-ordered: { { id, label, salience, compound? } }.
    --- ctx = { age, level } (level: the tier the words are read against).
    function M.impressions(attrs, ctx)
        ctx = ctx or {}
        local f = facets(attrs or {}, ctx.level or M.levelOf(attrs))
        local out, used = {}, {}
        for _, w in ipairs(M.WORDS) do
            if not used[w[3]] then
                local s = w[4](f, ctx)
                if s then used[w[3]] = true; out[#out + 1] = { id = w[1], label = w[2], salience = s, pace = w[3] == "pace" or nil } end
            end
        end
        for _, w in ipairs(M.COMPOUNDS) do
            local s = w[3](f, ctx)
            if s then out[#out + 1] = { id = w[1], label = w[2], salience = s + 0.25, compound = true } end
        end
        if #out < M.MIN_WORDS then
            local leans = {}
            for _, l in ipairs(M.LEANINGS) do
                if not used[l[4]] then
                    local v = l[5](f)
                    if v ~= 0 then leans[#leans + 1] = { id = l[1], label = v > 0 and l[2] or l[3], salience = math.min(0.5, math.abs(v) / 2), facet = l[4] } end
                end
            end
            table.sort(leans, function(a, b) if a.salience ~= b.salience then return a.salience > b.salience end return a.id < b.id end)
            for _, l in ipairs(leans) do
                if #out >= M.MIN_WORDS then break end
                if not used[l.facet] then used[l.facet] = true; out[#out + 1] = { id = l.id, label = l.label, salience = l.salience } end
            end
        end
        table.sort(out, function(a, b) if a.salience ~= b.salience then return a.salience > b.salience end return a.id < b.id end)
        return out
    end

    -- ---- knowledge ---------------------------------------------------------------------------------------------

    -- { min knowledge, label, impressions shown }
    M.LEVELS = {
        { 0, "Scouting report", 3 },
        { 8, "Watched", 5 },
        { 20, "Known", 7 },
        { 40, "Well known", 10 },
    }
    M.OWN_BONUS = 40

    --- How well the team understands this driver: Paddock starts count in full, the simulated career at a quarter
    --- (other people's scouting), and your own driver is well known.
    function M.knowledge(liveStarts, careerStarts, own)
        local k = (tonumber(liveStarts) or 0) + (tonumber(careerStarts) or 0) / 4 + (own and M.OWN_BONUS or 0)
        local lv = M.LEVELS[1]
        for _, l in ipairs(M.LEVELS) do if k >= l[1] then lv = l end end
        return { score = k, label = lv[2], shown = lv[3] }
    end

    -- ---- the report --------------------------------------------------------------------------------------------

    local function bestOf(list)
        local b
        for _, p in ipairs(list or {}) do if not b or p < b then b = p end end
        return b
    end

    --- The scouting report for one NPC driver.
    ---   person { id, attrs, morale, evidence }   ctx { age, seed, level?, own? }
    --- ctx.cacheOnly: never simulate (see M.cachedHistory).
    --- Returns { tags = { label... }, knowledge = label, record = { starts, wins, podiums, dnfs, bestRecent,
    --- paddockStarts, careerStarts, careerLevel } } -- labels and counts only; safe to send after assertNoHidden.
    local NO_CAREER = { starts = 0, recent = {}, pending = true }

    function M.report(person, ctx)
        ctx = ctx or {}
        local e = person.evidence or {}
        -- cacheOnly (hosts' views): a career not yet computed reads as none -- impressions still show, the record and
        -- knowledge come from the Paddock alone until the warmer reaches this driver
        local h = ctx.cacheOnly and (M.cachedHistory(person) or NO_CAREER) or M.history(person, ctx)
        local merged = M.mergedEvidence(e, h)
        local earned = Tags.driver(person, merged, { age = ctx.age })
        local know = M.knowledge(e.starts, h.starts, ctx.own)
        local tags, seen = {}, {}
        for _, t in ipairs(earned) do tags[#tags + 1] = t.label; seen[t.label] = true end
        -- the pace word always shows, first among the impressions (it is the headline of any report); the rest by
        -- salience up to what the team knows
        local imps = M.impressions(person.attrs, { age = ctx.age, level = ctx.level })
        local shown = 0
        for _, imp in ipairs(imps) do
            if imp.pace then tags[#tags + 1] = imp.label; seen[imp.label] = true; shown = 1 end
        end
        for _, imp in ipairs(imps) do
            if shown >= know.shown then break end
            if not seen[imp.label] then tags[#tags + 1] = imp.label; seen[imp.label] = true; shown = shown + 1 end
        end
        local recent = (#(e.recent or {}) > 0) and e.recent or h.recent
        return {
            tags = tags,
            knowledge = know.label,
            record = {
                starts = merged.starts, wins = merged.wins, podiums = merged.podiums, dnfs = merged.dnfs,
                bestRecent = bestOf(recent), paddockStarts = tonumber(e.starts) or 0, careerStarts = h.starts,
                -- a podium count means nothing without the field it came against
                careerLevel = h.starts > 0 and M.LEVEL_LABELS[h.level] or nil,
            },
        }
    end

    return M
end)
