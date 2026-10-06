-- ncm-core module: week.curve
-- Racing Week as a continuous 72-hour social-pressure curve (owner, 2026-10-03, L302; doc 45 §N).
--
-- Two signals, one number. The CARRIER is history: Racing Week always runs enthusiasm -> concern -> attempted
-- accommodation -> resentment -> rejection, as authored keyframes over the run's hours, interpolated with a monotone
-- cubic (no overshoot, no stair-steps; midnight is not magic). The LIVE SIGNAL is this run: a deviation pushed by what
-- racing participants actually do -- human or NPC, the city does not care which -- that leaks back toward the carrier.
--
--   tolerance(h) = clamp(carrier(h) + deviation, 0, 1),  |deviation| <= band(h)
--
-- The BAND keeps the chapters' identities (doc 45 rule 1): +-0.12 on opening day, widening to +-0.30 by the end. Twelve
-- animals on Day 1 sour the opening day; they cannot make it angry. A clean week reaches hour 68 at "fine, but go
-- home"; it never reaches "stay".
--
-- HARM IS ABSOLUTE, MEASURED AGAINST AN EXPECTATION. Racing has a normal cost the carrier already prices in
-- (`EXPECTED` per race run). Only harm beyond it -- or calm beyond it -- moves the deviation, so a quiet NPC-only week
-- tracks the carrier and a dozen reckless humans drag the city down faster.
--
-- INSTITUTIONS STEP, CROWDS DRIFT. Speed limits, race rules and police posture are ANNOUNCED (`STEPS`): each fires
-- once, when the actual tolerance crosses its threshold inside its hour window, or at the window's end regardless.
-- A bad week brings the crackdown early. Everything social (tolerance, and what reads it) is continuous.
-- Pure and deterministic: the host passes hours and facts in.
--
-- SEVEN DAYS (doc 47, L309-L310). The carrier is history's PULL, not a verdict: it falls to near nothing by hour 72
-- (history's usual end) and decides nothing -- `week.continuation` reads the state at each possible end. A run that
-- survives is past what the reconstruction knows: the carrier eases off to a low, neutral level and the band widens
-- to +-0.45 by hour 168, so Days 4-7 look like whatever the run made them (doc 47 §1.7).
-- RESERVOIRS (L309 Q5): the live signal is three coupled reservoirs fed by real facts -- SAFETY (crashes, wrecks,
-- civilian contact, chrome, clean races), ENFORCEMENT (speeding), MOMENTUM (races run against this server's normal
-- rate; only when the host measures that rate) -- and SENTIMENT, the deviation, is derived from their sum. When the sum
-- leaves the band all three are scaled back together, so the sum behaves exactly as L302's single deviation did.
-- MOODY (week.moody) never touches the reservoirs: its effects reach `read` as rule changes (limit, police) only.
local Core = NcmCore

Core.define("week.curve", function()
    local M = { version = "0.2.0", HOURS = 72, MAX_HOURS = 168, REVERT_PER_H = 0.08 }

    -- The carrier, hour -> tolerance (1 = the city loves this, 0 = get out). Owner's outline, 2026-10-03.
    M.CARRIER = {
        tolerance = {
            { 0, 0.95 },   -- honeymoon
            { 10, 0.90 },  -- normalisation begins
            { 16, 0.80 },  -- first cracks
            { 24, 0.62 },  -- day two: attempted correction holds it ...
            { 30, 0.58 },
            { 36, 0.52 },  -- ... credibility erodes
            { 48, 0.35 },  -- tolerance collapses
            { 60, 0.18 },  -- get out
            { 70, 0.08 },
            { 72, 0.04 },  -- GET. OUT. -- history's usual end (doc 47: an attractor, not a rule)
            { 84, 0.14 },  -- a run that survived is off history's map: the pull eases ...
            { 96, 0.22 },
            { 168, 0.26 }, -- ... to a low, neutral level; the state decides how Day 4+ feels
        },
        -- MONEY (owner, 2026-10-03, L303): "the in lore reason for spike in racing is money is unusually high, people
        -- are thinking its a gold mine, but its more flash craze for racing". A purse/sponsor multiplier: the rush
        -- builds through opening day, then the craze burns out. The crown at hour 72 is paid separately.
        money = {
            { 0, 1.60 },   -- the opening: everyone has heard about the money
            { 8, 1.80 },   -- gold rush
            { 20, 1.60 },
            { 32, 1.35 },  -- sponsors start hedging
            { 44, 1.15 },
            { 56, 1.00 },  -- the craze is over; the money that is left is ordinary
            { 72, 0.95 },
            { 168, 0.95 },
        },
    }
    M.MONEY_SENSITIVITY = 0.5   -- money moves with the live signal: a reckless week scares sponsors off sooner
    M.MONEY_FLOOR = 0.80

    M.BAND = { from = 0.12, to = 0.30, late = 0.45 }   -- late: the band at hour 168 (Days 4-7 are the run's own)

    -- What one fact does to the deviation, per unit. Units: speeding = 1,000 metre-seconds over the sign;
    -- everything else is a count. Unknown kinds are counted, never guessed at.
    M.IMPULSE = {
        speeding = -0.010,
        civilian_contact = -0.015,
        wreck = -0.008,
        race_crash = -0.003,
        chrome_impact = -0.004,
        clean_race = 0.004,
    }
    -- Which reservoir each fact feeds (L309 Q5). Momentum is fed by races run, not by this table.
    M.RESERVOIR = { speeding = "enforcement", civilian_contact = "safety", wreck = "safety", race_crash = "safety",
        chrome_impact = "safety", clean_race = "safety" }
    M.RESERVOIRS = { "safety", "enforcement", "momentum" }
    -- one race above (or below) this server's normal rate, per race: a fuller calendar is a livelier festival
    M.MOMENTUM_PER_RACE = 0.0012
    -- The normal cost of one race, already priced into the carrier. Measured, not guessed: dev's Paddock, 2026-10-03,
    -- 325 crash/contact DNFs in 655 resolved races (0.50 per race; ~7.9 races an hour).
    M.EXPECTED = { race_crash = 0.5 }

    -- The organisers' announcements. `limit` multiplies the game's posted lane speeds; `race` is what a race charges
    -- for going over (L301: Day 1 time, Day 2 warnings, Day 3 police only). Fire once, in order, latched.
    -- `below` sits just under the carrier at the window's end: a week no worse than history fires on schedule (`to`);
    -- only a worse one crosses early. A test holds that.
    M.STEPS = {
        { id = "opening", from = 0, to = 0, below = 2, limit = 0.75, race = "penalty",
            pa = "Welcome to Racing Week. Please respect Night City traffic and other competitors. Keep it friendly." },
        { id = "we_hear_you", from = 20, to = 30, below = 0.56, limit = 1.60, race = "warning",
            pa = "Racing Week update: we hear you. Limits on race routes are raised; please keep it off the sidewalks and out of traffic." },
        { id = "back_to_sane", from = 44, to = 54, below = 0.24, limit = 1.00, race = "police",
            pa = "Night City notice: standard traffic law applies city-wide. NCPD will enforce it." },
        { id = "clampdown", from = 62, to = 68, below = 0.07, limit = 0.80, race = "police",
            pa = "Night City notice: reduced limits are in force until Racing Week concludes. Clear the roads." },
    }

    -- The organisers' official chapter labels for an advertised seven-day festival (doc 47; three until L310).
    M.CHAPTERS = { "OPENING DAY", "RACING CONTINUES", "DAY THREE", "DAY FOUR", "DAY FIVE", "DAY SIX", "FINAL DAY" }

    -- ----------------------------------------------------------------------------------------- interpolation

    -- Fritsch-Butland tangents: monotone between keyframes, so a falling curve never rises.
    local function tangents(kf)
        local n, m = #kf, {}
        local d = {}
        for i = 1, n - 1 do d[i] = (kf[i + 1][2] - kf[i][2]) / (kf[i + 1][1] - kf[i][1]) end
        m[1], m[n] = d[1], d[n - 1]
        for i = 2, n - 1 do
            local h0, h1 = kf[i][1] - kf[i - 1][1], kf[i + 1][1] - kf[i][1]
            local a, b = d[i - 1], d[i]
            if a * b <= 0 then m[i] = 0
            else m[i] = 3 * (h0 + h1) / ((2 * h1 + h0) / a + (h1 + 2 * h0) / b) end
        end
        return m
    end
    local cache = {}

    --- A curve's value at `hours` (clamped to its first and last keyframe).
    function M.sample(kf, hours)
        local n = #kf
        if hours <= kf[1][1] then return kf[1][2] end
        if hours >= kf[n][1] then return kf[n][2] end
        local m = cache[kf]
        if not m then m = tangents(kf); cache[kf] = m end
        for i = 1, n - 1 do
            local x0, x1 = kf[i][1], kf[i + 1][1]
            if hours <= x1 then
                local h = x1 - x0
                local t = (hours - x0) / h
                local t2, t3 = t * t, t * t * t
                return (2 * t3 - 3 * t2 + 1) * kf[i][2] + (t3 - 2 * t2 + t) * h * m[i]
                    + (-2 * t3 + 3 * t2) * kf[i + 1][2] + (t3 - t2) * h * m[i + 1]
            end
        end
        return kf[n][2]
    end

    function M.carrier(hours) return M.sample(M.CARRIER.tolerance, hours) end

    function M.band(hours)
        hours = hours or 0
        if hours > M.HOURS then
            local g = math.min(1, (hours - M.HOURS) / (M.MAX_HOURS - M.HOURS))
            return M.BAND.to + (M.BAND.late - M.BAND.to) * g
        end
        local f = math.max(0, math.min(1, hours / M.HOURS))
        return M.BAND.from + (M.BAND.to - M.BAND.from) * f
    end

    function M.chapter(hours)
        local d = math.min(#M.CHAPTERS, math.floor(math.max(0, hours or 0) / 24) + 1)
        return d, M.CHAPTERS[d]
    end

    -- ----------------------------------------------------------------------------------------- the live signal

    function M.newState(hours)
        return { deviation = 0, hours = hours or 0, fired = {}, step = nil, facts = {},
            res = { safety = 0, enforcement = 0, momentum = 0 } }
    end

    --- A state saved before the reservoirs existed: its whole deviation was safety-and-enforcement; call it safety.
    local function reservoirs(st)
        if type(st.res) ~= "table" then st.res = { safety = st.deviation or 0, enforcement = 0, momentum = 0 } end
        for _, k in ipairs(M.RESERVOIRS) do st.res[k] = tonumber(st.res[k]) or 0 end
        return st.res
    end

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    --- Net impulse of a fact tally, after the expected cost of the races run in it. `expected` (optional) overrides
    --- `M.EXPECTED` per kind: the host measures its own server's normal (L305: Online runs 1.04 crashes a race, dev 0.5).
    function M.impulse(facts, expected)
        local by = M.impulses(facts, expected, 0)
        return by.safety + by.enforcement + by.momentum
    end

    --- The impulse per reservoir. Momentum needs the host's normal race rate (`expected.racesPerHour`) and the hours
    --- the tally covers (`dtH`); without them it is zero, never guessed.
    function M.impulses(facts, expected, dtH)
        local races = tonumber(facts.race) or 0
        local by = { safety = 0, enforcement = 0, momentum = 0 }
        for kind, w in pairs(M.IMPULSE) do
            local exp = (expected and tonumber(expected[kind])) or M.EXPECTED[kind] or 0
            local n = (tonumber(facts[kind]) or 0) - exp * races
            local r = M.RESERVOIR[kind] or "safety"
            by[r] = by[r] + w * n
        end
        local rate = expected and tonumber(expected.racesPerHour)
        if rate and dtH and dtH > 0 then by.momentum = M.MOMENTUM_PER_RACE * (races - rate * dtH) end
        return by
    end

    --- Advance to `hours` with the facts tallied since the last step. Returns the state and any steps fired now.
    function M.step(st, hours, facts, expected)
        local dtH = math.max(0, hours - (st.hours or hours))
        st.hours = hours
        local res = reservoirs(st)
        local leak = math.exp(-M.REVERT_PER_H * dtH)
        local by = M.impulses(facts or {}, expected, dtH)
        local sum = 0
        for _, k in ipairs(M.RESERVOIRS) do
            res[k] = res[k] * leak + by[k]
            sum = sum + res[k]
        end
        -- sentiment is the sum; outside the band all three scale back together (L302's clamp, unchanged)
        local b = M.band(hours)
        if math.abs(sum) > b then
            local f = b / math.abs(sum)
            for _, k in ipairs(M.RESERVOIRS) do res[k] = res[k] * f end
            sum = (sum > 0) and b or -b
        end
        st.deviation = sum
        local tol = M.tolerance(st, hours)
        local fired = {}
        for _, s in ipairs(M.STEPS) do
            if not st.fired[s.id] and hours >= s.from and (hours >= s.to or tol <= s.below) then
                st.fired[s.id] = { hours = hours, tolerance = tol, early = hours < s.to }
                st.step = s.id
                fired[#fired + 1] = s
            end
        end
        return st, fired
    end

    function M.tolerance(st, hours)
        return clamp(M.carrier(hours) + (st and st.deviation or 0), 0, 1)
    end

    local STEP = {}
    for _, s in ipairs(M.STEPS) do STEP[s.id] = s end
    function M.stepById(id) return STEP[id or ""] end

    --- Everything a host reads at an instant: { hours, day, chapter, carrier, tolerance, deviation, reservoirs, step,
    --- limit, race, policeCap, perLevel, money }. Police discretion is continuous: less tolerance, a lower bar and a
    --- higher cap. `fx` (optional, week.moody.effects) changes the RULES only: limit x, police cap +, bar x.
    function M.read(st, hours, fx)
        local tol = M.tolerance(st, hours)
        local s = STEP[st and st.step or "opening"] or M.STEPS[1]
        local day, chapter = M.chapter(hours)
        fx = fx or {}
        local res = st and reservoirs(st) or { safety = 0, enforcement = 0, momentum = 0 }
        return {
            hours = hours, day = day, chapter = chapter, carrier = M.carrier(hours), tolerance = tol,
            deviation = st and st.deviation or 0, step = s.id, limit = s.limit * (tonumber(fx.limit) or 1), race = s.race,
            reservoirs = { safety = res.safety, enforcement = res.enforcement, momentum = res.momentum },
            policeCap = clamp(math.ceil((1 - tol) * 5 - 1e-9) + math.floor(tonumber(fx.policeCap) or 0), 1, 5),
            perLevel = 150 * (0.5 + tol) * (tonumber(fx.perLevel) or 1),
            money = math.max(M.MONEY_FLOOR, M.sample(M.CARRIER.money, hours) + M.MONEY_SENSITIVITY * (st and st.deviation or 0)),
        }
    end

    return M
end)
