-- ncm-core module: economy.supply_profiles
--
-- **How fast a manufacturer refills its shelf, and nothing else.** Pure, deterministic, no randomness.
--
-- > THE MANUFACTURER MAY CHANGE HOW QUICKLY IT REFILLS THE SHELF.
-- > IT MAY NOT MOVE THE SHELF, CHANGE THE PRICE, JUDGE THE BUYER, OR BREAK OWNERSHIP.
--
-- The whole module has authority over exactly two numbers -- the next batch quantity and the next interval --
-- and both are clamped into an authored envelope it cannot leave. It never sees a driver id, a player name,
-- an owner, or who bought what. It cannot: the facts it is given do not contain them. That is a structural
-- guarantee rather than a rule somebody has to remember (packet section 8).
--
-- ---------------------------------------------------------------------------------------------
-- One mechanism, several personalities
-- ---------------------------------------------------------------------------------------------
--
-- Every profile runs the same three steps and differs only in parameters, so a hundred future models scale
-- through DATA rather than a hundred bespoke formulas (packet sections 4 and 31):
--
--   1. **Pressure.** Bounded factual signals become one number in roughly [-1, +1]. Positive means the market
--      is asking for more; negative means the shelf is glutted.
--   2. **Gates.** Cold start, dead zone, persistence and cooldown decide whether to act at all. This is where
--      thrashing and threshold-farming are prevented, and it is why a single purchase can never move a
--      schedule.
--   3. **The ladder.** A bounded integer step along an ordered list of legal (batch, interval) rungs.
--
-- ---------------------------------------------------------------------------------------------
-- Why a ladder
-- ---------------------------------------------------------------------------------------------
--
-- A response calculation naturally produces a fractional desired RATE, and there is no such thing as
-- producing 1.8 Hellas. Rather than round a rate and hope, the envelope is expanded once into every legal
-- discrete (batch, interval) pair, ordered slowest to fastest. A decision is then "move at most N rungs",
-- which makes integer production, envelope clamping and bounded adjustment the same single fact.
--
-- It also keeps the distinction the Market packet insists on: "1 every 30 min" and "2 every 60 min" have the
-- same average and are **different rungs**, because they are different market behaviour. Nothing here ever
-- collapses a schedule into units per hour.
local Core = NcmCore

Core.define("economy.supply_profiles", function(C)
    local M = { version = "0.1.0" }

    --- Bumped when the DECISION LOGIC OR PARAMETERS CHANGE. Written next to every decision so that a year
    --- from now "why did Archer behave differently in September" has a factual answer instead of a shrug
    --- (packet section 25). Changing a profile's numbers without bumping this is the mistake to avoid.
    M.LOGIC_VERSION = 1

    local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    local function clamp01(v) return clamp(v, 0, 1) end

    -- ---------------------------------------------------------------------------------------------
    -- Profiles. Internal configuration: none of this is ever shown to a player (packet section 15).
    -- ---------------------------------------------------------------------------------------------
    --
    -- `wImbalance` weighs the shelf's direction of travel, `wSellout` an empty shelf, `wGlut` a full one.
    -- There is deliberately no "sales per window" parameter: raw velocity is not comparable between a shelf
    -- of 4 and a shelf of 40, and -- as the section 27 simulations proved the hard way -- a market in perfect
    -- equilibrium sells exactly what it produces, which a velocity signal reads as maximum demand and
    -- answers by raising production forever.
    M.PROFILES = {
        -- The default. A manufacturer that plans in quarters, not in minutes.
        steady_hand = {
            lookbackCycles = 4, minCycles = 3,
            fullAt = 0.9,
            selloutCycles = 3, glutCycles = 4,
            wImbalance = 0.9, wSellout = 0.4, wGlut = 0.8,
            deadZone = 0.30, persistCycles = 2, cooldownCycles = 2,
            maxStepUp = 1, maxStepDown = 1,
            grain = "fine",
        },
        -- Mass-market: notices demand, moves sooner, still bounded. Retreats faster than it advances, which
        -- is the ordinary asymmetry of not wanting a yard full of unsold cars.
        volume_responsive = {
            lookbackCycles = 3, minCycles = 2,
            fullAt = 0.9,
            selloutCycles = 2, glutCycles = 3,
            wImbalance = 1.0, wSellout = 0.6, wGlut = 0.7,
            deadZone = 0.22, persistCycles = 1, cooldownCycles = 1,
            maxStepUp = 2, maxStepDown = 2,
            grain = "fine",
        },
        -- Halo/low-volume: scarcity is the product. It will barely chase demand, and a sellout is close to
        -- a compliment rather than a problem to solve. It still backs off when genuinely glutted.
        scarcity_keeper = {
            lookbackCycles = 6, minCycles = 4,
            fullAt = 0.85,
            selloutCycles = 6, glutCycles = 3,
            wImbalance = 0.35, wSellout = 0.15, wGlut = 0.9,
            deadZone = 0.45, persistCycles = 3, cooldownCycles = 4,
            maxStepUp = 1, maxStepDown = 1,
            grain = "coarse",
        },
    }
    M.DEFAULT_PROFILE = "steady_hand"

    function M.profile(id)
        return M.PROFILES[tostring(id or "")] or M.PROFILES[M.DEFAULT_PROFILE]
    end

    function M.profileId(id)
        return M.PROFILES[tostring(id or "")] and tostring(id) or M.DEFAULT_PROFILE
    end

    -- ---------------------------------------------------------------------------------------------
    -- The ladder
    -- ---------------------------------------------------------------------------------------------

    --- Every legal discrete schedule inside an envelope, slowest first.
    ---
    --- Intervals are laid out geometrically (min, 2x, 4x ... capped at max, plus max itself) rather than in
    --- fixed steps, because supply response is naturally multiplicative: halving an interval is a meaningful
    --- move whether the interval is 15 minutes or 15 days, and an additive step is not.
    ---
    --- **One rung per distinct rate, and `grain` chooses how that rate is expressed.**
    ---
    --- The first version kept every equal-rate pair as its own rung, reasoning that "1 every 30 min" and
    --- "2 every 60 min" are genuinely different market behaviour. They are -- but as LADDER RUNGS it made
    --- stepping meaningless: a manufacturer told to decrease could move one rung and land on an identical
    --- rate, having changed only the shape. That happened live on 2026-09-23, where a `decrease` took MaiMai
    --- from 4x/30min to 6x/60min and back to a neighbouring rate by accident.
    ---
    --- So the distinction now lives where it belongs: `grain` decides, once, whether this manufacturer
    --- expresses a given rate as frequent small batches ("fine") or rare large ones ("coarse"), and every
    --- step up or down genuinely changes the rate. Two manufacturers at the same rate still behave
    --- differently, which was the point of the rule.
    function M.ladder(envelope, grain)
        local e = type(envelope) == "table" and envelope or {}
        local bMin = math.max(1, math.floor(tonumber(e.batchMin) or 1))
        local bMax = math.max(bMin, math.floor(tonumber(e.batchMax) or bMin))
        local iMin = math.max(1, math.floor(tonumber(e.intervalMin) or 60))
        local iMax = math.max(iMin, math.floor(tonumber(e.intervalMax) or iMin))
        local intervals, seen = {}, {}
        local v = iMin
        while v < iMax do
            if not seen[v] then intervals[#intervals + 1] = v; seen[v] = true end
            v = v * 2
        end
        if not seen[iMax] then intervals[#intervals + 1] = iMax end
        local coarse = grain == "coarse"
        local byRate = {}
        for _, interval in ipairs(intervals) do
            for batch = bMin, bMax do
                local rate = batch / interval
                -- Float keys would make two arithmetically equal rates miss each other, so group on a
                -- rounded string instead.
                local key = ("%.12f"):format(rate)
                local cand = { batch = batch, intervalSec = interval, rate = rate }
                local held = byRate[key]
                if not held then byRate[key] = cand
                elseif coarse then if batch > held.batch then byRate[key] = cand end
                else if batch < held.batch then byRate[key] = cand end end
            end
        end
        local rungs = {}
        for _, r in pairs(byRate) do rungs[#rungs + 1] = r end
        table.sort(rungs, function(a, b)
            if a.rate ~= b.rate then return a.rate < b.rate end
            return a.batch < b.batch          -- unreachable after grouping; keeps the sort total anyway
        end)
        return rungs
    end

    --- Which rung a schedule currently sits on. An exact match when there is one; otherwise the nearest rate,
    --- so a schedule authored outside the ladder (or left behind by an envelope change) still has a defined
    --- place to step from instead of snapping to an extreme.
    function M.rungOf(rungs, batch, intervalSec)
        local bestExact, bestNear, bestDelta = nil, 1, math.huge
        local rate = (tonumber(batch) or 1) / math.max(1, tonumber(intervalSec) or 1)
        for i, r in ipairs(rungs) do
            if r.batch == batch and r.intervalSec == intervalSec then bestExact = i end
            local d = math.abs(r.rate - rate)
            if d < bestDelta then bestDelta, bestNear = d, i end
        end
        return bestExact or bestNear
    end

    -- ---------------------------------------------------------------------------------------------
    -- Signals
    -- ---------------------------------------------------------------------------------------------

    --- Turn market facts into one bounded pressure, plus the components, so a decision can be explained.
    ---
    --- **Every input is a count, a ratio or a duration.** There is deliberately no input that could carry a
    --- buyer's identity, and therefore no way for this to treat ten sales to one player differently from ten
    --- sales to ten players (packet section 8 and the section 27 invariant).
    ---
    --- facts = { available, capacity, soldInWindow, cyclesObserved, soldOutCycles, fullCycles }
    function M.signals(p, facts)
        local capacity = math.max(1, math.floor(tonumber(facts.capacity) or 1))
        local sold = math.max(0, math.floor(tonumber(facts.soldInWindow) or 0))
        local supplied = math.max(0, math.floor(tonumber(facts.suppliedInWindow) or 0))
        -- **Imbalance: is the shelf draining or accumulating?** Sales measured against what this manufacturer
        -- actually supplied over the same window, which is self-normalising -- a shelf of 4 and a shelf of 40
        -- both read 0 when they are in equilibrium, and neither needs a per-model tuning constant.
        --
        -- Equilibrium is the case that matters and the one a raw velocity signal gets exactly wrong: a market
        -- that sells precisely what it produces is not in high demand, it is balanced.
        --
        -- **Weighted by how material the flow was.** A ratio is at its most sensitive when the numbers are
        -- smallest: one car sold against none produced is a ratio of 1.0, which would read as infinite unmet
        -- demand and let a single purchase move a schedule -- precisely the trivial, repeatable manipulation
        -- section 12 exists to prevent. Significance is squared so that small flows are discounted hard and a
        -- full shelf's worth of turnover still counts fully.
        local flow = sold + supplied
        local significance = clamp01(flow / capacity)
        local imbalance = (flow > 0) and (((sold - supplied) / flow) * significance * significance) or 0
        -- Imbalance goes blind at both bounds, and that is why the streaks exist rather than being
        -- redundant with it. At a sold-out shelf you sell everything you make, so imbalance reads 0 while
        -- demand is unmet; at a full shelf you make nothing and sell nothing, so it reads 0 while you are
        -- glutted. The streaks are what see past the bound.
        local sellout = clamp01((tonumber(facts.soldOutCycles) or 0) / math.max(1, p.selloutCycles))
        local glut = clamp01((tonumber(facts.fullCycles) or 0) / math.max(1, p.glutCycles))
        local w = p.wImbalance or 0
        local up = w * math.max(0, imbalance) + p.wSellout * sellout
        local down = w * math.max(0, -imbalance) + p.wGlut * glut
        return {
            imbalance = imbalance, sellout = sellout, glut = glut,
            pressure = clamp(up - down, -1, 1),
            soldInWindow = sold, suppliedInWindow = supplied,
            available = math.max(0, math.floor(tonumber(facts.available) or 0)),
            capacity = capacity, cyclesObserved = math.max(0, math.floor(tonumber(facts.cyclesObserved) or 0)),
            soldOutCycles = math.max(0, math.floor(tonumber(facts.soldOutCycles) or 0)),
            fullCycles = math.max(0, math.floor(tonumber(facts.fullCycles) or 0)),
        }
    end

    --- Fold completed cycles into the fact bundle `signals` consumes.
    ---
    --- **The host and the tests must fold identically**, or the scenario simulations would be exercising a
    --- different economy than the one that runs. So this lives here rather than in either of them.
    ---
    --- `cycles` is oldest-first; each entry is { endedAvailable, sold, minted, capacity } -- what the shelf
    --- held when the cycle closed, how many left it, and how many the manufacturer put on it. Streaks are
    --- counted backwards from the most recent cycle, so they mean "currently sold out / currently glutted",
    --- not "ever was".
    function M.observe(cycles, p)
        cycles = type(cycles) == "table" and cycles or {}
        local n = #cycles
        local lookback = math.max(1, math.floor(p.lookbackCycles or 1))
        local sold, supplied = 0, 0
        for i = math.max(1, n - lookback + 1), n do
            sold = sold + (tonumber(cycles[i].sold) or 0)
            supplied = supplied + (tonumber(cycles[i].minted) or 0)
        end
        local capacity = n > 0 and (tonumber(cycles[n].capacity) or 1) or 1
        local soldOut, full = 0, 0
        for i = n, 1, -1 do
            if (tonumber(cycles[i].endedAvailable) or 0) <= 0 then soldOut = soldOut + 1 else break end
        end
        for i = n, 1, -1 do
            local cap = math.max(1, tonumber(cycles[i].capacity) or 1)
            if (tonumber(cycles[i].endedAvailable) or 0) >= (p.fullAt or 0.9) * cap then full = full + 1 else break end
        end
        return {
            available = n > 0 and (tonumber(cycles[n].endedAvailable) or 0) or 0,
            capacity = capacity, soldInWindow = sold, suppliedInWindow = supplied, cyclesObserved = n,
            soldOutCycles = soldOut, fullCycles = full,
        }
    end

    -- ---------------------------------------------------------------------------------------------
    -- The decision
    -- ---------------------------------------------------------------------------------------------

    --- Choose the NEXT schedule, having just completed a production cycle.
    ---
    --- This is called once per completed cycle, never per purchase. That single choice is most of the
    --- manipulation resistance in the system: an individual transaction has no event to trigger, so there is
    --- no threshold to step back and forth across (packet section 12).
    ---
    --- req = {
    ---   profileId, envelope,
    ---   current = { batch, intervalSec },
    ---   facts   = { available, capacity, soldInWindow, cyclesObserved, soldOutCycles, fullCycles },
    ---   memory  = { signRuns, lastSign, cyclesSinceChange },   -- persisted between cycles
    --- }
    ---
    --- Returns { batch, intervalSec, changed, reason, steps, fromRung, toRung, signals, memory,
    ---           profileId, logicVersion, clamped }.
    --- `reason` is the internal diagnostic vocabulary, never player copy.
    function M.decide(req)
        req = type(req) == "table" and req or {}
        local pid = M.profileId(req.profileId)
        local p = M.profile(pid)
        local envelope = req.envelope or {}
        local current = type(req.current) == "table" and req.current or {}
        local facts = type(req.facts) == "table" and req.facts or {}
        local memory = type(req.memory) == "table" and req.memory or {}

        local rungs = M.ladder(envelope, p.grain)
        local fromRung = M.rungOf(rungs, tonumber(current.batch) or rungs[1].batch,
                                         tonumber(current.intervalSec) or rungs[1].intervalSec)
        local sig = M.signals(p, facts)

        local cyclesSinceChange = (tonumber(memory.cyclesSinceChange) or 0) + 1
        local sign = (sig.pressure > 0 and 1) or (sig.pressure < 0 and -1) or 0

        -- **A hold holds.** Not `rungs[fromRung]`: now that the ladder keeps one rung per rate, the nearest
        -- rung to an authored schedule may express that rate differently (4 every 30 min and 2 every 15 min
        -- are the same rate), and returning it would silently rewrite a schedule nobody decided to change.
        -- Only a real step may snap to a rung.
        local keep = { batch = tonumber(current.batch) or rungs[fromRung].batch,
                       intervalSec = tonumber(current.intervalSec) or rungs[fromRung].intervalSec }

        local function hold(reason, keepSign)
            local s = keepSign and sign or 0
            local runs = (keepSign and s ~= 0 and s == (tonumber(memory.lastSign) or 0))
                and ((tonumber(memory.signRuns) or 0) + 1) or (keepSign and s ~= 0 and 1 or 0)
            return {
                batch = keep.batch, intervalSec = keep.intervalSec, changed = false, reason = reason,
                steps = 0, fromRung = fromRung, toRung = fromRung, signals = sig, profileId = pid,
                logicVersion = M.LOGIC_VERSION, clamped = false,
                memory = { signRuns = runs, lastSign = s, cyclesSinceChange = cyclesSinceChange },
            }
        end

        -- COLD START. Too little history is not evidence of no demand; it is absence of evidence. A market
        -- with one player and two cycles of history must not send a manufacturer to an extreme
        -- (packet section 18).
        if sig.cyclesObserved < p.minCycles then return hold("cold_start", false) end

        -- DEAD ZONE. A band around neutral in which nothing happens at all, so ordinary small variation
        -- never moves a schedule.
        if math.abs(sig.pressure) < p.deadZone then return hold("within_dead_zone", false) end

        -- PERSISTENCE. The same direction has to hold for several completed cycles before it counts, which
        -- is what makes an oscillating market fail to drive the schedule (packet section 22).
        local lastSign = tonumber(memory.lastSign) or 0
        local signRuns = (sign == lastSign) and ((tonumber(memory.signRuns) or 0) + 1) or 1
        if signRuns < p.persistCycles then
            return {
                batch = keep.batch, intervalSec = keep.intervalSec, changed = false,
                reason = "awaiting_persistence", steps = 0, fromRung = fromRung, toRung = fromRung,
                signals = sig, profileId = pid, logicVersion = M.LOGIC_VERSION, clamped = false,
                memory = { signRuns = signRuns, lastSign = sign, cyclesSinceChange = cyclesSinceChange },
            }
        end

        -- COOLDOWN. A manufacturer revises a production plan; it does not track a ticker
        -- (packet section 13).
        if cyclesSinceChange < p.cooldownCycles then
            return {
                batch = keep.batch, intervalSec = keep.intervalSec, changed = false,
                reason = "cooldown", steps = 0, fromRung = fromRung, toRung = fromRung,
                signals = sig, profileId = pid, logicVersion = M.LOGIC_VERSION, clamped = false,
                memory = { signRuns = signRuns, lastSign = sign, cyclesSinceChange = cyclesSinceChange },
            }
        end

        -- THE STEP. Bounded, integer, and asymmetric where the profile says so. At least one rung, or the
        -- gates above would have held us.
        local span = (sign > 0) and p.maxStepUp or p.maxStepDown
        local steps = math.max(1, math.ceil(math.abs(sig.pressure) * span)) * sign
        local toRung = clamp(fromRung + steps, 1, #rungs)
        local clamped = (fromRung + steps) ~= toRung
        local chosen = rungs[toRung]
        local changed = toRung ~= fromRung
        return {
            batch = changed and chosen.batch or keep.batch,
            intervalSec = changed and chosen.intervalSec or keep.intervalSec, changed = changed,
            reason = changed and ((sign > 0) and "increase" or "decrease") or "already_at_bound",
            steps = toRung - fromRung, fromRung = fromRung, toRung = toRung, signals = sig,
            profileId = pid, logicVersion = M.LOGIC_VERSION, clamped = clamped,
            -- A change resets the cooldown; a no-op at the ladder's end does not, or a manufacturer pinned
            -- at maximum would be unable to ever come back down promptly.
            memory = { signRuns = signRuns, lastSign = sign,
                       cyclesSinceChange = changed and 0 or cyclesSinceChange },
        }
    end

    return M
end)
