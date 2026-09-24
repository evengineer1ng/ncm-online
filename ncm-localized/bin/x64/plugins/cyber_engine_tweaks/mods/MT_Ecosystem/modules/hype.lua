-- ============================================================
-- MT_Ecosystem: modules/hype.lua
-- Hype Index: a layered multiplier applied to race payouts.
--
-- Inputs (all optional — graceful degradation if missing):
--   • District fan interest (location baseline)
--   • Driver dynamics (popularity, faction home-turf/rival tension)
--   • Car prestige (exotic/legendary vehicles raise the spectacle)
--   • Storyline arcs (V or AI win streaks, rematches)
--   • Random city noise (daily event roll per real session)
--   • Finish closeness (gap between V and nearest finisher)
--
-- Output: Hype.scoreRace(career, config, results) → {
--     index        number   final hype index (1.0 = neutral)
--     multiplier   number   payout multiplier derived from index + tier curve
--     breakdown    table    named components for UI display
-- }
--
-- Payout curve by tier (applied to the index → multiplier mapping):
--   Gonk:       very low ceiling,  small upside
--   Streetkid:  modest ceiling
--   Solo:       mid-range
--   Fixer:      high ceiling
--   Edgerunner: large floor + steep upper curve = very lucrative peak
-- ============================================================

local Hype = {}

-- ── District baseline fan interest ────────────────────────────
-- 0 = nobody is watching, 1 = moderate interest, 2 = hot market
-- Reflects lore: Westbrook / City Center are prestige venues;
-- Badlands and Pacifica are scrappy low-profile scenes.
local DISTRICT_BASE = {
    ["City Center"]   = 1.6,
    Westbrook         = 1.5,
    Heywood           = 1.2,
    Watson            = 1.1,
    ["Santo Domingo"] = 1.0,
    Pacifica          = 0.8,
    Badlands          = 0.6,
}
local DISTRICT_BASE_DEFAULT = 1.0

-- ── Faction home-turf bonus ───────────────────────────────────
-- A faction racing on their home ground draws more crowd interest.
-- Match is fuzzy: faction id substring vs district key.
local FACTION_HOME_PAIRS = {
    { faction = "tyger_claws",       district = "Westbrook"     },
    { faction = "valentinos",        district = "Heywood"       },
    { faction = "aldecaldo",         district = "Badlands"      },
    { faction = "wraith",            district = "Badlands"      },
    { faction = "sixth_street",      district = "Santo Domingo" },
    { faction = "maelstrom",         district = "Watson"        },
    { faction = "animals",           district = "Pacifica"      },
    { faction = "arasaka",           district = "City Center"   },
    { faction = "afterlife",         district = "Westbrook"     },
    { faction = "mox",               district = "Watson"        },
}

-- ── Tier payout curve ─────────────────────────────────────────
-- base:  eddies multiplier at index 1.0 (neutral race)
-- scale: how steeply the index drives extra payout.
--        final_multiplier = base + (index - 1.0) * scale
--        clamped to [min, max]
-- The Gonk tier has a very tight band; Edgerunner ranges are wide
-- and start from a higher base, so even a mediocre race pays well.
local TIER_CURVE = {
    Gonk       = { base = 0.40, scale = 0.30, min = 0.20, max = 0.70 },
    Streetkid  = { base = 0.65, scale = 0.60, min = 0.35, max = 1.30 },
    Solo       = { base = 1.00, scale = 1.00, min = 0.55, max = 2.20 },
    Fixer      = { base = 1.50, scale = 1.60, min = 0.90, max = 3.80 },
    Edgerunner = { base = 2.40, scale = 2.80, min = 1.60, max = 7.00 },
}

-- ── Daily noise seed (re-rolls once per real-world session) ───
-- A small randomized "city event" factor — concert in Corpo Plaza,
-- Maelstrom rally, festival in Heywood, etc.  Rolled once on first
-- scoreRace call and kept stable for the IRL session.
local _sessionNoise     = nil
local _sessionNoiseRand = nil  -- district-keyed stable noise values

local function _ensureSessionNoise()
    if _sessionNoise then return end
    _sessionNoise = 0.85 + math.random() * 0.30  -- 0.85–1.15
    _sessionNoiseRand = {}
    -- Per-district variance rolls carried lazily
end

local function _getDistrictNoise(district)
    _ensureSessionNoise()
    if district and not _sessionNoiseRand[district] then
        _sessionNoiseRand[district] = 0.90 + math.random() * 0.20  -- 0.90–1.10
    end
    return district and _sessionNoiseRand[district] or _sessionNoise
end

-- ── Helpers ───────────────────────────────────────────────────

local function _tierCurve(tier)
    return TIER_CURVE[tier] or TIER_CURVE.Gonk
end

local function _clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Count how many rivals in the field are from a given faction.
local function _countFactionRivals(results, factionId)
    if not results or not factionId then return 0 end
    local n = 0
    for _, r in ipairs(results) do
        if not r.isPlayer then
            local dFac = (r.driver and r.driver.factionId) or r.factionId or ""
            if dFac == factionId or dFac:find(factionId, 1, true) then
                n = n + 1
            end
        end
    end
    return n
end

-- Average prestige of AI vehicles in the field (1–5 scale).
local function _avgFieldPrestige(results)
    if not results or #results == 0 then return 2 end
    local total, count = 0, 0
    for _, r in ipairs(results) do
        if not r.isPlayer then
            local p = tonumber(
                (r.driver and r.driver.vehiclePrestige)
                or (r.vehicleBuild and r.vehicleBuild.vehiclePrestige)
                or nil)
            if p then total = total + p; count = count + 1 end
        end
    end
    if count == 0 then return 2 end
    return total / count
end

-- Finish closeness: smallest time gap between V and the nearest other
-- finisher with a real time, clamped to [0, 30] seconds → [1.0, 0.0]
-- inverted so a photo-finish = high hype bonus.
local function _closenessBonus(results)
    if not results then return 0 end
    local playerTime = nil
    local otherTimes = {}
    for _, r in ipairs(results) do
        local t = tonumber(r.time)
        if t and t > 0 then
            if r.isPlayer then
                playerTime = t
            else
                otherTimes[#otherTimes+1] = t
            end
        end
    end
    if not playerTime or #otherTimes == 0 then return 0 end
    local minGap = math.huge
    for _, t in ipairs(otherTimes) do
        local gap = math.abs(playerTime - t)
        if gap < minGap then minGap = gap end
    end
    -- 0 s gap → 0.40 bonus; 5 s gap → 0.20; ≥15 s → 0
    if minGap >= 15.0 then return 0 end
    return _clamp(0.40 * (1.0 - minGap / 15.0), 0, 0.40)
end

-- Home turf bonus: count how many home-faction/district pairings
-- are represented in the current race.
local function _homeTurfScore(district, results)
    if not district or not results then return 0 end
    local matches = 0
    for _, pair in ipairs(FACTION_HOME_PAIRS) do
        if district == pair.district or district:find(pair.district, 1, true) then
            -- Check if any driver from that faction is in the field
            for _, r in ipairs(results) do
                if not r.isPlayer then
                    local dFac = (r.driver and r.driver.factionId) or r.factionId or ""
                    if dFac:find(pair.faction, 1, true) then
                        matches = matches + 1
                        break
                    end
                end
            end
        end
    end
    -- Each home-turf rivalry match adds +0.10, cap at +0.30
    return _clamp(matches * 0.10, 0, 0.30)
end

-- Rematch detector: did V race at least one of these same rivals recently?
local function _raceHistoryBonus(career, results)
    if not career or not results then return 0 end
    local history = career.raceHistory or {}
    if #history == 0 then return 0 end

    -- Collect current rival driver ids
    local currentIds = {}
    for _, r in ipairs(results) do
        if not r.isPlayer then
            local id = r.driverId or r.id or r.displayName
            if id then currentIds[id] = true end
        end
    end

    -- Check last 5 races for overlapping rivals
    local rematches = 0
    for i = 1, math.min(5, #history) do
        local prev = history[i]
        -- We don't store field in history, so we check node pair instead as a
        -- route-rematch signal (same route = same crowd scene = rising stakes).
        if prev.nodeA and prev.nodeB then
            -- Route repeat bonus — same start node in recent history
            local anyCurrentNode = career.raceHistory[1]
            if anyCurrentNode and anyCurrentNode.nodeA == prev.nodeA then
                rematches = rematches + 1
            end
        end
    end
    return _clamp(rematches * 0.08, 0, 0.20)
end

-- ── Public API ────────────────────────────────────────────────

--- Compute the hype index for a completed race and derive the payout multiplier.
--- All parameters are optional; missing data gracefully degrades each component.
---
--- @param career    table|nil  active career object
--- @param config    table|nil  race config (district, nodeA, nodeB, …)
--- @param results   table|nil  Racing._results array of finisher entries
--- @return table   { index, multiplier, breakdown }
function Hype.scoreRace(career, config, results)
    local district  = config and config.district or nil
    local tier      = (career and career.tier) or "Gonk"
    local curve     = _tierCurve(tier)

    -- ── 1. Location baseline ─────────────────────────────────
    local locationScore = DISTRICT_BASE[district] or DISTRICT_BASE_DEFAULT

    -- ── 2. District noise (daily "city event" randomiser) ────
    local noiseScore = _getDistrictNoise(district)

    -- ── 3. Home turf / faction clash bonus ───────────────────
    local homeTurfScore = _homeTurfScore(district, results)

    -- ── 4. Car prestige (field average 1–5 → 0.8–1.4) ───────
    local avgPrestige = _avgFieldPrestige(results)
    local prestigeScore = 0.8 + (avgPrestige - 1) * 0.15   -- 1→0.8, 5→1.40

    -- ── 5. V win streak (momentum) ───────────────────────────
    local winStreak      = tonumber(career and career.stats and career.stats.winStreak) or 0
    local streakScore    = 1.0 + _clamp(winStreak * 0.06, 0, 0.30)

    -- ── 6. History / rematch bonus ───────────────────────────
    local narrativeScore = 1.0 + _raceHistoryBonus(career, results)

    -- ── 7. Finish closeness ───────────────────────────────────
    local closenessBonus = _closenessBonus(results)

    -- ── Combine into single index ─────────────────────────────
    -- Index is a product of multiplicative factors (location, noise,
    -- prestige, streak, narrative) plus additive bonuses (home turf,
    -- closeness) so that every factor has its own contribution visible
    -- in the breakdown but none can independently blow up the total.
    local index = locationScore
               * noiseScore
               * prestigeScore
               * streakScore
               * narrativeScore
               + homeTurfScore
               + closenessBonus

    index = _clamp(index, 0.20, 4.00)

    -- ── Tier curve → payout multiplier ───────────────────────
    local multiplier = curve.base + (index - 1.0) * curve.scale
    multiplier = _clamp(multiplier, curve.min, curve.max)

    return {
        index       = index,
        multiplier  = multiplier,
        breakdown   = {
            location   = locationScore,
            noise      = noiseScore,
            homeTurf   = homeTurfScore,
            prestige   = prestigeScore,
            streak     = streakScore,
            narrative  = narrativeScore,
            closeness  = closenessBonus,
        },
        tier       = tier,
        district   = district,
    }
end

--- Re-roll the session noise (call on a new play session or manually).
function Hype.resetSessionNoise()
    _sessionNoise     = nil
    _sessionNoiseRand = nil
end

--- Return a short human-readable label for the hype index level.
function Hype.label(index)
    if index >= 3.0 then return "LEGENDARY"
    elseif index >= 2.0 then return "EPIC"
    elseif index >= 1.4 then return "HOT"
    elseif index >= 1.0 then return "LIVE"
    elseif index >= 0.7 then return "Quiet"
    else                     return "Dead Scene"
    end
end

return Hype
