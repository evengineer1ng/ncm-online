-- ncm-core module: life.climate
-- What each Night City district is LIKE right now, and why (L240; Oracle Kingdom's era and material classifiers,
-- Neikos's seeded climate archetypes, ForkUniverse's namespaced streams).
--
-- Six axes per district, 0..100:
--   order       enforcement: NCPD, corp security, who answers when something happens
--   grip        how concentrated power is: one gang or one corp holding the district, versus nobody
--   prosperity  money moving: shops open, teams paid, eddies spent
--   cohesion    whether people look out for each other
--   heat        violence and open conflict
--   scene       the street motorsport culture: meets, crews, who is fast
--
-- DETERMINISTIC NOISY INPUTS. Where a district starts is three layers, all from the world seed:
--   1. its CHARACTER, authored from canon (City Center is ordered and rich; Pacifica is neither);
--   2. the season's CITY CLIMATE, one weighted draw per season (a corporate boom, a crackdown, a gang summer...),
--      which leans every district the same way for three months -- Neikos's climate archetype over a region offset;
--   3. per-district NOISE, so two worlds from different seeds are recognisably Night City and never identical.
-- Then every day FACTS from the sim move the axes (a street race, a team folding, an NCPD incident), the axes revert
-- toward where the district "wants" to be, the current regime drifts them (Oracle's era modifiers: a regime tends to
-- keep itself), cross-axis coherence applies (Oracle's StateCoherenceEngine), and a little daily noise lands.
--
-- READING = regime x condition, the Oracle pairing ("authoritarian and thriving", "authoritarian and in crisis"):
--   regime     first match in REGIMES, held for HOLD days before it changes, so a district does not flicker
--   condition  thriving | functional | strained | collapsed, from prosperity and cohesion (Oracle MaterialState)
--   crisis     a strained or collapsed district running hot
-- A regime transition is recorded with the values that caused it. Leaving a crisis regime SCARS the district's
-- baseline permanently (Oracle's crisis residues): the city remembers.
--
-- Pure and deterministic: the same seed, season and facts give the same climate under Lua 5.4 and LuaJIT, whether
-- stepped day by day or caught up after downtime. Nothing here reaches a client except `reading().label`.
local Core = NcmCore

Core.define("life.climate", function(C)
    local M = { version = "0.1.0", HOLD = 2, REVERT = 0.06, NOISE = 1.2, SCAR = 2, HISTORY = 64 }
    local Hash = C.get("vocabulary.hash")
    local Places = C.get("world.places")

    M.AXES = { "order", "grip", "prosperity", "cohesion", "heat", "scene" }

    -- 1. Character, from canon. Authored vocabulary, not a situation.
    M.CHARACTER = {
        ["Watson"]        = { order = 35, grip = 45, prosperity = 30, cohesion = 45, heat = 60, scene = 55 },
        ["Westbrook"]     = { order = 60, grip = 55, prosperity = 70, cohesion = 50, heat = 40, scene = 60 },
        ["City Center"]   = { order = 80, grip = 80, prosperity = 85, cohesion = 35, heat = 25, scene = 35 },
        ["Heywood"]       = { order = 45, grip = 50, prosperity = 45, cohesion = 65, heat = 50, scene = 65 },
        ["Santo Domingo"] = { order = 40, grip = 45, prosperity = 30, cohesion = 55, heat = 50, scene = 60 },
        ["Pacifica"]      = { order = 15, grip = 40, prosperity = 15, cohesion = 40, heat = 70, scene = 40 },
        ["Dogtown"]       = { order = 20, grip = 75, prosperity = 35, cohesion = 35, heat = 65, scene = 30 },
        ["Badlands"]      = { order = 15, grip = 30, prosperity = 25, cohesion = 70, heat = 45, scene = 70 },
    }
    M.CHARACTER_NOISE_SD = 7

    -- 2. The season's city climate (Neikos climate archetypes). Weighted; one per season per seed.
    M.CITY_CLIMATES = {
        { id = "uneasy_calm",    label = "an uneasy calm",  weight = 3, lean = {} },
        { id = "corporate_boom", label = "a corporate boom", weight = 2,
            lean = { grip = 8, prosperity = 8, order = 5, scene = -4 } },
        { id = "crackdown",      label = "a crackdown",     weight = 2,
            lean = { order = 12, heat = -8, scene = -6, cohesion = -3 } },
        { id = "gang_summer",    label = "a gang summer",   weight = 2,
            lean = { heat = 10, order = -6, cohesion = -3, scene = 3 } },
        { id = "recession",      label = "a recession",     weight = 2,
            lean = { prosperity = -10, cohesion = 4, heat = 4 } },
        { id = "scene_revival",  label = "a scene revival", weight = 1,
            lean = { scene = 12, cohesion = 4, order = -3 } },
    }

    -- What one counted fact does to its district, per unit. Unknown kinds are counted, never guessed at.
    M.IMPULSE = {
        street_race     = { scene = 0.6, heat = 0.1 },
        sanctioned_race = { scene = 0.3, prosperity = 0.1, order = 0.1 },
        race_crash      = { heat = 0.2, order = 0.1 },
        org_folded      = { prosperity = -1.5, cohesion = -0.8, scene = -0.3 },
        org_founded     = { prosperity = 1.0, scene = 0.5 },
        cash_k          = { prosperity = 0.02 },          -- signed thousands of eddies moved by teams based here
        ncpd_incident   = { order = 0.8, heat = 0.4 },
        player_talk     = { cohesion = 0.05 },
        delivery_done   = { prosperity = 0.3, cohesion = 0.2 },
        delivery_failed = { cohesion = -0.2 },
        turf_record     = { scene = 0.8, heat = 0.3 },
    }
    M.IMPULSE_CAP = 6        -- no single day's facts move an axis further than this

    -- Regimes, first match wins (Oracle ERA_DETECTION_RULES). `drift` is the per-day pull while it holds (Oracle
    -- ERA_MODIFIERS): mild self-reinforcement, except that a war burns itself out.
    M.REGIMES = {
        { id = "lockdown", label = "Corpo lockdown",
            when = { order = { 70 }, grip = { 60 }, heat = { nil, 35 } },
            drift = { order = 0.3, scene = -0.3, cohesion = -0.1 } },
        { id = "open_war", label = "Open war", crisis = true,
            when = { heat = { 72 } },
            drift = { prosperity = -0.4, cohesion = -0.3, heat = -0.25 } },
        { id = "gang_rule", label = "Gang rule",
            when = { order = { nil, 35 }, heat = { 58 }, grip = { 45 } },
            drift = { heat = 0.15, order = -0.2, grip = 0.1 } },
        { id = "oligarchy", label = "One hand on everything",
            when = { grip = { 72 } },
            drift = { grip = 0.2, cohesion = -0.2, prosperity = 0.1 } },
        { id = "scene_town", label = "The scene runs it",
            when = { scene = { 70 }, cohesion = { 50 } },
            drift = { scene = 0.2, cohesion = 0.1, order = -0.1 } },
        { id = "fracture", label = "Everyone for themselves", crisis = true,
            when = { cohesion = { nil, 30 } },
            drift = { cohesion = -0.1, heat = 0.2 } },
        { id = "neglect", label = "Nobody's watching",
            when = { order = { nil, 30 }, prosperity = { nil, 35 } },
            drift = { prosperity = -0.2, heat = 0.1 } },
        { id = "balance", label = "An uneasy balance", when = {}, drift = {} },
    }
    local REGIME = {}
    for i, r in ipairs(M.REGIMES) do r.index = i; REGIME[r.id] = r end
    function M.regime(id) return REGIME[id or ""] end

    M.CONDITIONS = { "thriving", "functional", "strained", "collapsed" }

    local function clamp(v) if v < 0 then return 0 elseif v > 100 then return 100 end return v end
    local function r2(v) return math.floor(v * 100 + 0.5) / 100 end

    --- The season's city climate for a seed.
    function M.cityClimate(seed, seasonId)
        local r = Hash.stream(seed, "city_climate", seasonId or "")
        return (r:weighted(M.CITY_CLIMATES))
    end

    local function matches(rule, ax)
        for axis, band in pairs(rule.when) do
            local v = ax[axis] or 50
            if band[1] and v < band[1] then return false end
            if band[2] and v > band[2] then return false end
        end
        return true
    end

    --- The regime a set of axes reads as, ignoring hold.
    function M.classify(ax)
        for _, rule in ipairs(M.REGIMES) do
            if matches(rule, ax) then return rule end
        end
        return REGIME.balance
    end

    function M.condition(ax)
        local p, c = ax.prosperity or 50, ax.cohesion or 50
        if p > 65 and c > 45 then return "thriving" end
        if p > 40 then return "functional" end
        if p > 20 or c > 40 then return "strained" end
        return "collapsed"
    end

    --- A new climate: every district's baseline and today's axes, for a seed and season.
    function M.genesis(seed, seasonId, dayIndex)
        local city = M.cityClimate(seed, seasonId)
        local s = { version = M.version, seasonId = seasonId, city = city.id, day = dayIndex or 0, districts = {},
            history = {} }
        for _, name in ipairs(Places.DISTRICTS) do
            local ch = M.CHARACTER[name]
            local r = Hash.stream(seed, "district_character", name)
            local base, ax = {}, {}
            for _, a in ipairs(M.AXES) do
                base[a] = r2(clamp(ch[a] + r:normal(0, M.CHARACTER_NOISE_SD)))
                ax[a] = r2(clamp(base[a] + (city.lean[a] or 0)))
            end
            local reg = M.classify(ax)
            s.districts[name] = { base = base, scars = {}, axes = ax, regime = reg.id, pending = nil, pendingDays = 0,
                since = s.day, causes = {} }
        end
        return s
    end

    --- A new season re-draws the city climate; baselines, scars and today's axes carry on.
    function M.newSeason(s, seed, seasonId)
        s.seasonId = seasonId
        s.city = M.cityClimate(seed, seasonId).id
        return s
    end

    local function lean(s)
        for _, c in ipairs(M.CITY_CLIMATES) do if c.id == s.city then return c.lean end end
        return {}
    end

    -- Oracle dampening: a push toward an extreme weakens as the axis nears it; a push back toward 50 never does.
    local function damp(v, delta)
        if delta == 0 then return 0 end
        local outward = (delta > 0 and v > 50) or (delta < 0 and v < 50)
        if not outward then return delta end
        local f = 1 - ((v - 50) / 50) ^ 2
        if f < 0.1 then f = 0.1 end
        return delta * f
    end

    --- Advance one day. `facts` is district -> { kind -> count }. Returns the state and this day's transitions.
    --- Idempotent by day: stepping a day that is not after `s.day` does nothing.
    function M.step(s, seed, dayIndex, facts)
        if dayIndex <= (s.day or 0) then return s, {} end
        local transitions = {}
        local cityLean = lean(s)
        for _, name in ipairs(Places.DISTRICTS) do
            local d = s.districts[name]
            if d then
                local ax = d.axes
                -- Sorted, never `pairs` order: float sums must add up the same way on every host.
                local push, causes = {}, {}
                local df = (facts or {})[name] or {}
                local kinds = {}
                for kind in pairs(df) do kinds[#kinds + 1] = kind end
                table.sort(kinds)
                for _, kind in ipairs(kinds) do
                    local imp, count = M.IMPULSE[kind], df[kind]
                    if imp and type(count) == "number" and count ~= 0 then
                        for _, a in ipairs(M.AXES) do
                            local per = imp[a]
                            if per then
                                push[a] = (push[a] or 0) + per * count
                                causes[#causes + 1] = { kind = kind, axis = a, delta = per * count }
                            end
                        end
                    end
                end
                local rule = REGIME[d.regime] or REGIME.balance
                local r = Hash.stream(seed, "district_day", name, dayIndex)
                local nx = {}
                for _, a in ipairs(M.AXES) do
                    local v = ax[a]
                    local target = d.base[a] + (cityLean[a] or 0) + (d.scars[a] or 0)
                    local p = push[a] or 0
                    if p > M.IMPULSE_CAP then p = M.IMPULSE_CAP elseif p < -M.IMPULSE_CAP then p = -M.IMPULSE_CAP end
                    v = v + (target - v) * M.REVERT
                    v = v + damp(v, (rule.drift[a] or 0) + p)
                    v = v + r:normal(0, M.NOISE)
                    nx[a] = v
                end
                -- Coherence (Oracle StateCoherenceEngine): axes that cannot sit together pull on each other.
                if nx.prosperity < 25 then nx.heat = nx.heat + 0.5 end
                if nx.heat > 70 then nx.prosperity = nx.prosperity - 0.4; nx.cohesion = nx.cohesion - 0.3 end
                if nx.order > 75 then nx.scene = nx.scene - 0.4; nx.heat = nx.heat - 0.3 end
                for _, a in ipairs(M.AXES) do ax[a] = r2(clamp(nx[a])) end
                table.sort(causes, function(x, y)
                    local ax_, ay = math.abs(x.delta), math.abs(y.delta)
                    if ax_ ~= ay then return ax_ > ay end
                    if x.kind ~= y.kind then return x.kind < y.kind end
                    return x.axis < y.axis
                end)
                while #causes > 3 do table.remove(causes) end
                d.causes = causes

                local read = M.classify(ax)
                if read.id == d.regime then
                    d.pending, d.pendingDays = nil, 0
                else
                    if d.pending == read.id then d.pendingDays = d.pendingDays + 1 else d.pending, d.pendingDays = read.id, 1 end
                    if d.pendingDays >= M.HOLD then
                        local from = REGIME[d.regime] or REGIME.balance
                        local snap = {}
                        for _, a in ipairs(M.AXES) do snap[a] = ax[a] end
                        local t = { day = dayIndex, district = name, from = from.id, to = read.id, axes = snap,
                            causes = d.causes }
                        -- Crisis residue: the district's baseline keeps a mark of what it went through.
                        if from.crisis then
                            d.scars.cohesion = (d.scars.cohesion or 0) - M.SCAR
                            d.scars.heat = (d.scars.heat or 0) + M.SCAR / 2
                            t.scar = "crisis"
                        elseif from.id == "scene_town" then
                            d.scars.scene = (d.scars.scene or 0) + M.SCAR / 2
                            t.scar = "scene"
                        end
                        d.regime, d.since, d.pending, d.pendingDays = read.id, dayIndex, nil, 0
                        transitions[#transitions + 1] = t
                        s.history[#s.history + 1] = t
                    end
                end
            end
        end
        while #s.history > M.HISTORY do table.remove(s.history, 1) end
        s.day = dayIndex
        return s, transitions
    end

    --- How a district reads: { regime, condition, crisis, label, since }.
    function M.reading(s, district)
        local d = s and s.districts[district]
        if not d then return nil end
        local reg = REGIME[d.regime] or REGIME.balance
        local cond = M.condition(d.axes)
        local crisis = reg.crisis == true or ((cond == "strained" or cond == "collapsed") and d.axes.heat > 55)
        local tail = crisis and "in crisis" or cond
        return { regime = reg.id, regimeIndex = reg.index, condition = cond, crisis = crisis, since = d.since,
            label = ("%s, %s"):format(reg.label, tail) }
    end

    --- What the district's state asks of the people in it. Multipliers read by `life.needs` and `life.schedule`.
    ---   money   how fast Money runs down (a poor district costs more to live in)
    ---   social  how much a place full of people satisfies
    ---   drive   how strongly the scene pulls
    ---   night   how dangerous late hours feel (a valorous person shrugs it off)
    ---   meets   whether street meets can happen at all (a lockdown busts them)
    function M.pressures(s, district)
        local d = s and s.districts[district]
        if not d then return { money = 1, social = 1, drive = 1, night = 0.3, meets = true } end
        local ax = d.axes
        return {
            money = 1 + (50 - ax.prosperity) / 100,
            social = 0.6 + ax.cohesion / 125,
            drive = 0.6 + ax.scene / 125,
            night = ax.heat / 100,
            meets = not (d.regime == "lockdown" or ax.order > 80),
        }
    end

    return M
end)
