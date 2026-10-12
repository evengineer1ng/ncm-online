-- ncm-core module: life.trajectory
-- Who a player is turning into, recognised rather than chosen (L240; Oracle Court's OracleIdentityProfile, Neikos's
-- PlayerTrajectory and outcome band). The seed of M6 (L237): an earned handle and access gates derived from evidence,
-- with NO visible archetype meter. Nothing in this module is ever sent to a client; the host may show a handle an NPC
-- uses, never the profile.
--
-- SIGNALS. Every recorded fact about the player (a race finished, a street race, a trade, a talk, an offer let lapse)
-- adds to behaviour axes -- racer, street, wrench, broker, social -- and nudges risk appetite. Each signal's weight
-- carries DETERMINISTIC NOISE keyed by (seed, player, fact id): the same play replays to the same profile, yet two
-- players who do the same things are not stamped out of one mould, and no fixed count of actions buys a bucket.
-- Axes saturate (1 - e^-x), so early deeds shape a player more than the hundredth of the same.
--
-- BUCKET. First match wins, after an evidence floor (Oracle: "too early to tell"):
--   unknown    not enough evidence yet
--   ghost      lets most opportunities pass (Oracle THE_SILENT)
--   wildcard   no stable pattern: recent deeds disagree with the lifetime shape (Oracle THE_ERRATIC)
--   journeyman no axis dominates (Neikos "Balanced Growth")
--   otherwise  the dominant axis, split by risk appetite (Neikos compute_personal_quadrant)
-- A change of bucket must hold for HOLD signals, so one odd night does not rename anyone.
--
-- OUTCOME BAND = the player's home district's climate regime x their bucket (Neikos compute_outcome_band): "a Charger
-- in a district under gang rule, in crisis" is a different life from "a Charger where the scene runs it".
local Core = NcmCore

Core.define("life.trajectory", function(C)
    local M = { version = "0.1.0", FLOOR = 12, HOLD = 4, RECENT = 20, SEEN = 256, JITTER = 0.2, SCALE = 40 }
    local Hash = C.get("vocabulary.hash")
    local Climate = C.get("life.climate")

    M.AXES = { "racer", "street", "wrench", "broker", "social" }

    -- What each kind of fact says about a person. `risk` moves appetite (0..100, starts at 50); `opportunity` and
    -- `silence` count offers taken and offers let pass.
    M.SIGNALS = {
        race_finish      = { racer = 3 },
        race_win         = { racer = 5, risk = 0.5 },
        race_dnf         = { racer = 1, risk = 1 },
        clean_finish     = { racer = 1, risk = -1 },
        dirty_drive      = { street = 2, risk = 3 },
        street_race      = { street = 4, risk = 1 },
        meet_visit       = { street = 1, social = 1 },
        police_escape    = { street = 3, risk = 4 },
        speeding         = { street = 2, risk = 2 },          -- L301: over the Day's advertised limit, once per episode
        part_fitted      = { wrench = 3 },
        design_research  = { wrench = 4 },
        car_scanned      = { wrench = 1 },
        market_trade     = { broker = 3 },
        delivery_done    = { broker = 2, social = 1 },
        delivery_failed  = { broker = 1, risk = 1 },
        talk             = { social = 2 },
        helped_contact   = { social = 4, risk = -1 },
        betrayed_contact = { social = 1, risk = 4 },
        offer_accepted   = { opportunity = 1 },
        offer_declined   = { silence = 1 },
        offer_lapsed     = { silence = 1 },
    }

    -- The recognised buckets, in band order. Split pairs are (cautious, reckless).
    M.BUCKETS = {
        { id = "unknown",      label = "a newcomer" },
        { id = "ghost",        label = "a ghost" },
        { id = "wildcard",     label = "a wildcard" },
        { id = "journeyman",   label = "a journeyman" },
        { id = "professional", label = "a professional",  axis = "racer",  risky = false },
        { id = "charger",      label = "a charger",       axis = "racer",  risky = true },
        { id = "tactician",    label = "a night tactician", axis = "street", risky = false },
        { id = "wildfire",     label = "a wildfire",      axis = "street", risky = true },
        { id = "engineer",     label = "an engineer",     axis = "wrench", risky = false },
        { id = "mad_scientist", label = "a mad scientist", axis = "wrench", risky = true },
        { id = "dealer",       label = "a dealer",        axis = "broker", risky = false },
        { id = "operator",     label = "an operator",     axis = "broker", risky = true },
        { id = "confidant",    label = "a confidant",     axis = "social", risky = false },
        { id = "kingmaker",    label = "a kingmaker",     axis = "social", risky = true },
    }
    local BUCKET = {}
    for i, b in ipairs(M.BUCKETS) do b.index = i; BUCKET[b.id] = b end
    function M.bucket(id) return BUCKET[id or ""] end

    local function r2(v) return math.floor(v * 100 + 0.5) / 100 end
    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    function M.new()
        local raw = {}
        for _, a in ipairs(M.AXES) do raw[a] = 0 end
        return { raw = raw, risk = 50, evidence = 0, opportunities = 0, silences = 0, recent = {}, districts = {},
            seen = {}, seenOrder = {}, bucket = "unknown", pending = nil, pendingCount = 0, since = 0 }
    end

    --- Saturating axis score, 0..100.
    function M.score(raw) return 100 * (1 - math.exp(-(raw or 0) / M.SCALE)) end

    local function dominant(raw)
        local best, bestV, total = nil, -1, 0
        for _, a in ipairs(M.AXES) do
            local v = raw[a] or 0
            total = total + v
            if v > bestV then best, bestV = a, v end
        end
        return best, bestV, total
    end

    --- The bucket a profile reads as right now, ignoring hold.
    function M.classify(p)
        if p.evidence < M.FLOOR then return BUCKET.unknown end
        local offers = p.opportunities + p.silences
        if offers >= 8 and p.silences / offers > 0.6 then return BUCKET.ghost end
        local dom, domV, total = dominant(p.raw)
        if total <= 0 then return BUCKET.unknown end
        -- Wildcard: the last RECENT deeds lean somewhere the lifetime shape does not.
        if #p.recent >= M.RECENT then
            local agree = 0
            for _, a in ipairs(p.recent) do if a == dom then agree = agree + 1 end end
            if agree / #p.recent < 0.2 and domV / total >= 0.35 then return BUCKET.wildcard end
        end
        if domV / total < 0.3 then return BUCKET.journeyman end
        local risky = p.risk > 50
        for _, b in ipairs(M.BUCKETS) do
            if b.axis == dom and b.risky == risky then return b end
        end
        return BUCKET.journeyman
    end

    --- Record one fact: { id, kind, district?, day? }. Idempotent by id (the last SEEN ids are remembered).
    --- Returns the profile and, when the bucket changed, { from, to }.
    function M.record(p, seed, playerKey, fact)
        local sig = M.SIGNALS[fact.kind or ""]
        if not sig or not fact.id then return p, nil end
        if p.seen[fact.id] then return p, nil end
        p.seen[fact.id] = true
        p.seenOrder[#p.seenOrder + 1] = fact.id
        while #p.seenOrder > M.SEEN do p.seen[table.remove(p.seenOrder, 1)] = nil end

        local jitter = 1 + (Hash.unit(seed, "trajectory", playerKey, fact.id) * 2 - 1) * M.JITTER
        local lead, leadV = nil, 0
        for _, a in ipairs(M.AXES) do
            local v = sig[a]
            if v then
                p.raw[a] = r2(p.raw[a] + v * jitter)
                p.evidence = r2(p.evidence + v * jitter)
                if v > leadV then lead, leadV = a, v end
            end
        end
        if sig.risk then p.risk = r2(clamp(p.risk + sig.risk * jitter, 0, 100)) end
        if sig.opportunity then p.opportunities = p.opportunities + 1 end
        if sig.silence then p.silences = p.silences + 1 end
        if lead then
            p.recent[#p.recent + 1] = lead
            while #p.recent > M.RECENT do table.remove(p.recent, 1) end
        end
        if fact.district then p.districts[fact.district] = r2((p.districts[fact.district] or 0) + jitter) end

        local read = M.classify(p)
        local change
        if read.id == p.bucket then
            p.pending, p.pendingCount = nil, 0
        elseif p.bucket == "unknown" then
            change = { from = p.bucket, to = read.id }                -- the first recognition needs no hold
            p.bucket, p.since, p.pending, p.pendingCount = read.id, fact.day or 0, nil, 0
        else
            if p.pending == read.id then p.pendingCount = p.pendingCount + 1 else p.pending, p.pendingCount = read.id, 1 end
            if p.pendingCount >= M.HOLD then
                change = { from = p.bucket, to = read.id }
                p.bucket, p.since, p.pending, p.pendingCount = read.id, fact.day or 0, nil, 0
            end
        end
        return p, change
    end

    --- The district the player lives their life in: the one with the most recorded deeds.
    function M.homeDistrict(p)
        local best, bestV
        local names = {}
        for d in pairs(p.districts) do names[#names + 1] = d end
        table.sort(names)
        for _, d in ipairs(names) do
            if not bestV or p.districts[d] > bestV then best, bestV = d, p.districts[d] end
        end
        return best
    end

    --- The outcome band: { id, bucket, regime, condition, crisis, district, label }. id = (regime-1)*#BUCKETS + bucket.
    function M.band(p, climate)
        local b = BUCKET[p.bucket] or BUCKET.unknown
        local d = M.homeDistrict(p)
        local read = d and Climate.reading(climate, d)
        local regIndex = read and read.regimeIndex or #Climate.REGIMES
        return {
            id = (regIndex - 1) * #M.BUCKETS + b.index,
            bucket = b.id, regime = read and read.regime or "balance", condition = read and read.condition,
            crisis = read and read.crisis or false, district = d,
            label = read and ("%s in %s (%s)"):format(b.label, d, read.label) or b.label,
        }
    end

    return M
end)
