-- ============================================================
-- MT_Ecosystem: modules/careers.lua
-- Unlimited named careers. Each career has:
--   • Prestige tier: Gonk → Streetkid → Solo → Fixer → Edgerunner
--   • Rep that goes up AND down. Promotion + relegation are resolved at season end.
--   • Small real street cred XP bonus per race.
--   • Locked config set at career creation.
-- ============================================================

local Careers = {}
local Persist = require("modules/persistence")

-- ── Tier system ───────────────────────────────────────────────
-- repFloor:    if rep drops below this, relegate (nil = can't go lower)
-- repCeiling:  when rep hits this, promote
-- relegReset:  after relegation, rep is set to this value in the new tier

local TIER_TABLE = {
    { name = "Gonk",       repFloor = nil,    repCeiling = 1500,  relegReset = nil   },
    { name = "Streetkid",  repFloor = 200,    repCeiling = 5500,  relegReset = 900   },
    { name = "Solo",       repFloor = 1200,   repCeiling = 15000, relegReset = 2800  },
    { name = "Fixer",      repFloor = 5000,   repCeiling = 40000, relegReset = 9000  },
    { name = "Edgerunner", repFloor = 15000,  repCeiling = nil,   relegReset = 22000 },
}

local TIER_BY_NAME = {}
for i, t in ipairs(TIER_TABLE) do TIER_BY_NAME[t.name] = { i=i, def=t } end

-- Points awarded per finish position | keyed 1–last
-- DEPRECATED: Old fixed table kept as reference only.
-- local POS_REP   = { 300, 170, 90, 40, 10, -10, -30, -55, -80 }
local POS_REP_BOTTOM = -100  -- last place penalty (scaled by field)
local DNF_REP        = -150  -- did not finish penalty

-- Street cred XP amounts (real game API)
local SCRED_WIN      = 25
local SCRED_TOP_HALF = 10
local SCRED_FINISH   = 5

-- Default career config (can be overridden at creation)
local CONFIG_DEFAULTS = {
    defaultStartType  = "grid",     -- "grid"|"rolling"|"sidebyside"
    defaultFieldSize  = 8,          -- AI count
    allowStakes       = true,
    stakeMaxByTier    = { Gonk=2000, Streetkid=8000, Solo=25000, Fixer=75000, Edgerunner=200000 },
    qualiEnabled      = false,
    handicapMode      = false,      -- rubber-band AI pacing on losing streak
    vehicleClass      = nil,        -- nil = any | "Muscle"|"Sport"|"Tech"|"Nomad"|"Bike"
    timeOfDay         = nil,        -- nil = any | "night" | "day"
    minDistanceM      = 1500,
    maxDistanceM      = 8000,
    preferredRegions  = {},         -- [] = any district
    seasonLength      = 8,          -- races per season
}

local CHAMPIONSHIP_CONFIG_DEFAULTS = {
    eventMix = "mixed",           -- "mixed"|"drag_only"|"sprint_only"
    lastRaceKnockout = false,
}

local BOX_SCORE_PAYOUT_BY_POS = { 2500, 1400, 700, 350, 150, 75, 40, 20 }

local VALID_EVENT_MIX = {
    mixed = true,
    drag_only = true,
    sprint_only = true,
}

-- ── State ─────────────────────────────────────────────────────

Careers.all    = {}    -- all careers keyed by id
Careers._active = nil  -- active career id

-- ── Persistence ───────────────────────────────────────────────

local CAREERS_FILE = "careers.json"

local function deepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and deepCopy(v) or v
    end
    return copy
end

local function normalizeChampionshipConfig(config)
    local normalized = deepCopy(CHAMPIONSHIP_CONFIG_DEFAULTS)
    if type(config) ~= "table" then
        return normalized
    end

    if VALID_EVENT_MIX[config.eventMix] then
        normalized.eventMix = config.eventMix
    end
    normalized.lastRaceKnockout = config.lastRaceKnockout == true
    return normalized
end

local function repForFinish(position, fieldSize)
    local pos = math.max(1, tonumber(position) or 1)
    local total = math.max(2, tonumber(fieldSize) or 2)

    -- Normalised finish: 1.0 = first, 0.0 = last
    local norm = (total - pos) / math.max(1, total - 1)

    -- Base reward scales with field size (bigger fields = more at stake)
    -- fieldFactor: 4-car race ≈ 0.7, 8-car ≈ 1.0, 12-car ≈ 1.15
    local fieldFactor = 0.5 + 0.5 * math.min(1.3, total / 8.0)

    -- Reward curve: top half earns rep, bottom half loses rep, symmetrically
    -- At norm=1.0 (P1): +180, at norm=0.5 (mid): 0, at norm=0.0 (last): -180
    local baseRep = 180
    local rep = baseRep * (2.0 * norm - 1.0) * fieldFactor

    -- Slight winner bonus: P1 gets extra kick
    if pos == 1 then rep = rep + 40 * fieldFactor end
    -- Podium micro-bonus
    if pos <= 3 and pos > 1 then rep = rep + 15 * fieldFactor end

    return math.floor(rep + 0.5)
end

local function seasonRewardScale(tier)
    local tierInfo = TIER_BY_NAME[tier]
    if not tierInfo then return 1.0 end
    return 1.0 + ((tierInfo.i - 1) * 0.45)
end

-- ── Public API ────────────────────────────────────────────────

function Careers.init()
    Careers.load()
    print(string.format("[NCM/Careers] Loaded %d career(s).", 
        (function() local n=0; for _ in pairs(Careers.all) do n=n+1 end return n end)()))
end

function Careers.load()
    local data = Persist.load(CAREERS_FILE)
    if type(data) == "table" then
        Careers.all    = data.careers  or {}
        Careers._active = data.activeId or nil
        local dirty = false
        for _, career in pairs(Careers.all) do
            local normalizedChampionshipConfig = normalizeChampionshipConfig(career.championshipConfig)
            if type(career.championshipConfig) ~= "table"
                or career.championshipConfig.eventMix ~= normalizedChampionshipConfig.eventMix
                or career.championshipConfig.lastRaceKnockout ~= normalizedChampionshipConfig.lastRaceKnockout then
                career.championshipConfig = normalizedChampionshipConfig
                dirty = true
            end
        end
        -- Migrate existing careers for faction/championship fields
        if MTE.Championships then
            for _, career in pairs(Careers.all) do
                MTE.Championships.migrateCareer(career)
            end
        end
        if MTE.Management and MTE.Management.migrateCareer then
            for _, career in pairs(Careers.all) do
                local _, changed = MTE.Management.migrateCareer(career)
                dirty = dirty or changed
            end
        end
        if dirty then
            Careers.save()
        end
    end
end

function Careers.save()
    Persist.save(CAREERS_FILE, {
        careers  = Careers.all,
        activeId = Careers._active,
    })
end

--- Create a new career. Returns the career object.
--- @param name   string  display name  e.g. "Nomad Run"
--- @param config table   (optional) config keys to override defaults
--- @param championshipConfig table|nil  championship event mix settings
function Careers.create(name, config, championshipConfig)
    local id   = "career_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local seed = os.time() + math.random(1, 999999)

    local cfg = deepCopy(CONFIG_DEFAULTS)
    if type(config) == "table" then
        for k, v in pairs(config) do cfg[k] = v end
    end

    local career = {
        id          = id,
        name        = name or "New Career",
        seed        = seed,
        createdAt   = os.time(),
        tier        = "Gonk",
        rep         = 750,
        config      = cfg,
        stats = {
            racesRun       = 0,
            racesFinished  = 0,
            wins           = 0,
            podiums        = 0,
            top5s          = 0,
            poles          = 0,
            dnfs           = 0,
            lossStreak     = 0,
            winStreak      = 0,
            totalFinishPos = 0,
            totalStartPos  = 0,
            eddiesEarned   = 0,
            credAwarded    = 0,
        },
        raceHistory  = {},   -- last 20 results
        bounties     = {},   -- { [driverId] = {escalated=bool, resolvedCount=int} }
        seasonRaces  = 0,    -- races in current season
        seasonNumber = 1,
        -- Championship / faction layer (separate from prestige tier)
        playerFactionMode  = "independent",
        playerFactionId    = "independent",
        playerFactionName  = "Independent",
        playerFactionColor = { 1.0, 0.93, 0.33 },
        activeSeasonId     = nil,
        seasons            = {},
        championshipConfig = normalizeChampionshipConfig(championshipConfig),
        fanState = {
            sentMilestones = {},
            identityProfile = {},
            pending = {},
            lastPushText = "",
            lastPushCategory = "",
            lastPushKey = "",
            lastPullMode = "",
            lastPushRace = -99,
            lastPushAt = 0,
            lastIdentityAt = 0,
            lastSignatureAt = 0,
            lastChampPos = 0,
        },
        management = (MTE and MTE.Management and MTE.Management.defaultState and MTE.Management.defaultState()) or nil,
    }

    Careers.all[id] = career
    Careers.save()
    print(string.format("[NCM/Careers] Created career '%s' (tier=Gonk, seed=%d).", name, seed))
    pcall(function()
        if MTE and MTE.PhoneBridge and MTE.PhoneBridge.requestIntroPing then
            MTE.PhoneBridge.requestIntroPing(true)
        end
    end)
    return career
end

function Careers.championshipConfigDefaults()
    return deepCopy(CHAMPIONSHIP_CONFIG_DEFAULTS)
end

function Careers.normalizeChampionshipConfig(config)
    return normalizeChampionshipConfig(config)
end

--- Delete a career by id.
function Careers.delete(id)
    if Careers.all[id] then
        local career = Careers.all[id]
        -- Clean up orphaned roster cache file
        if career.seed then
            pcall(function() Persist.delete("roster_" .. tostring(career.seed) .. ".json") end)
            pcall(function() Persist.delete("roster_meta_" .. tostring(career.seed) .. ".json") end)
        end
        if MTE and MTE.SafetyRating and MTE.SafetyRating.removeCareerProfile then
            MTE.SafetyRating.removeCareerProfile(id)
        end
        Careers.all[id] = nil
        if Careers._active == id then Careers._active = nil end
        Careers.save()
        print("[NCM/Careers] Deleted career " .. id)
    end
end

--- Set the active career.
function Careers.select(id)
    if not Careers.all[id] then
        print("[NCM/Careers] Career not found: " .. tostring(id))
        return
    end
    Careers._active = id
    Careers.save()
    -- Load roster cache for this career
    if MTE.Roster then MTE.Roster.loadForCareer(Careers.all[id]) end
    print("[NCM/Careers] Selected: " .. Careers.all[id].name)
end

--- Returns the active career object, or nil.
function Careers.active()
    if Careers._active then return Careers.all[Careers._active] end
    return nil
end

--- Returns a sorted list of all careers (newest first).
function Careers.list()
    local out = {}
    for _, c in pairs(Careers.all) do table.insert(out, c) end
    table.sort(out, function(a, b) return (a.createdAt or 0) > (b.createdAt or 0) end)
    return out
end

-- ── Rep & prestige ────────────────────────────────────────────

--- Check handicap: if lossStreak >= 3, return a downward pace multiplier for AI.
--- E.g. 0.95 means AI are 5% slower to help the player.
--- Returns 1.0 (no effect) if handicap is off or streak is low.
function Careers.handicapMult(career)
    if not career.config.handicapMode then return 1.0 end
    local streak = career.stats.lossStreak or 0
    if streak < 3 then return 1.0 end
    -- Soften AI by 5% per streak loss, cap at 20% easier
    local soften = math.min(0.20, (streak - 2) * 0.05)
    return 1.0 - soften
end

--- Award rep after a race. Handles promotion and relegation.
--- @param career   table
--- @param position number  finish position (1 = win)
--- @param fieldSize number  total drivers including player
--- @param extras   table   { distance=m, clean=bool, wagerWon=bool, bountyResolved=bool, dnf=bool }
function Careers.awardRep(career, position, fieldSize, extras)
    extras = extras or {}

    local gain = 0

    if extras.dnf then
        gain = DNF_REP
    else
        -- Position-based rep
        gain = repForFinish(position, fieldSize)
        -- Bonuses
        if extras.distance then gain = gain + math.floor(extras.distance / 100) end
        if extras.clean    then gain = gain + 150 end
        if extras.wagerWon then gain = gain + 100 end
        -- Bounty bonus: 2× position rep if resolved, 3× if escalated
        if extras.bountyResolved then
            gain = extras.bountyEscalated and gain * 3 or gain * 2
        end
    end

    career.rep = career.rep + gain

    -- Update streaks
    if extras.dnf or (position == fieldSize) then
        career.stats.lossStreak = career.stats.lossStreak + 1
        career.stats.winStreak  = 0
    elseif position == 1 then
        career.stats.winStreak  = career.stats.winStreak + 1
        career.stats.lossStreak = 0
    elseif position <= math.ceil(fieldSize / 2) then
        -- Top-half finish breaks the loss streak
        career.stats.lossStreak = 0
    end

    -- Loss streak catch-up: bonus rep injection to break regression loops
    local streak = career.stats.lossStreak or 0
    if streak >= 5 and not extras.dnf and position <= math.ceil(fieldSize / 2) then
        local catchUp = math.min(300, streak * 40)
        gain = gain + catchUp
        career.rep = career.rep + catchUp
        print(string.format("[NCM/Careers] Catch-up bonus: +%d rep (loss streak %d)", catchUp, streak))
        MTE.Events.emit("CatchUpBonus", { amount = catchUp, streak = streak })
    end

    -- Award real street cred
    if not extras.dnf then
        local credAmt = position == 1 and SCRED_WIN
                     or position <= math.ceil(fieldSize / 2) and SCRED_TOP_HALF
                     or SCRED_FINISH
        Careers._awardStreetCred(credAmt)
        career.stats.credAwarded = career.stats.credAwarded + credAmt
    end

    print(string.format("[NCM/Careers] Rep: %+d → %d (tier: %s)", gain, career.rep, career.tier))

    Careers._checkTierChange(career, {
        source = extras.source or "race",
        finishPosition = position,
        fieldSize = fieldSize,
        startPosition = extras.startPosition,
        playerDeltaPos = extras.playerDeltaPos,
        marginToNext = extras.marginToNext,
        gapToLeader = extras.gapToLeader,
        isDNF = extras.dnf == true,
        isClean = extras.clean == true,
        winStreak = career.stats.winStreak,
        lossStreak = career.stats.lossStreak,
    })

    Careers.save()
    return gain
end

function Careers.resolveSeasonMovement(career, championshipRank, fieldSize)
    if not career then
        return { direction = "stay", newTier = nil }
    end

    local tierInfo = TIER_BY_NAME[career.tier]
    if not tierInfo then
        return { direction = "stay", newTier = nil }
    end

    local rank = math.max(1, tonumber(championshipRank) or 1)
    local total = math.max(1, tonumber(fieldSize) or 1)
    local movementSlots = math.max(1, math.min(2, math.floor(total / 4)))
    local nextTier = TIER_TABLE[tierInfo.i + 1]
    local prevTier = TIER_TABLE[tierInfo.i - 1]

    if nextTier and rank <= movementSlots then
        return { direction = "up", newTier = nextTier.name }
    end
    if prevTier and rank > (total - movementSlots) then
        return { direction = "down", newTier = prevTier.name }
    end
    return { direction = "stay", newTier = nil }
end

local TIER_TRANSITION_MESSAGES = {
    up = {
        Streetkid = {
            line1 = "You're in Streetkid now.",
            base = "Pace is real, mistakes get noticed.",
            dominant = "You had control - keep it under pressure.",
            narrow = "Margins like that don't hold here.",
            comeback = "Climbing works - staying does not.",
        },
        Solo = {
            line1 = "Welcome to Solo.",
            base = "Everyone here can win - execution decides it.",
            dominant = "That level is expected now.",
            narrow = "You won't get that margin again.",
            consistent = "You earned it - now repeat it.",
        },
        Fixer = {
            line1 = "You've reached Fixer.",
            base = "Races are controlled, not chased.",
            dominant = "Control like that is the requirement.",
            consistent = "Consistency got you here - keep it.",
        },
        Edgerunner = {
            line1 = "Edgerunner tier.",
            base = "No room left - this is the ceiling.",
            dominant = "That was control at the limit.",
            narrow = "Margins here decide everything.",
            consistent = "You sustained it - now defend it.",
        },
    },
    down = {
        Gonk = {
            line1 = "Back to Gonk.",
            base = "Nothing carries over down here - earn it again.",
            collapse = "You lost control - start from zero.",
            chaotic = "Doesn't matter how - it resets all the same.",
        },
        Streetkid = {
            line1 = "Dropped to Streetkid.",
            base = "Still fast - but no longer untouchable.",
            collapse = "That fall doesn't stop unless you fix it.",
            chaotic = "You lost position in the noise.",
        },
        Solo = {
            line1 = "Back to Solo.",
            base = "Close the gaps or get buried in them.",
            collapse = "Gaps opened - you didn't close them.",
            narrow = "Close wasn't enough.",
        },
        Fixer = {
            line1 = "Dropped to Fixer.",
            base = "You had control - now prove you can take it back.",
            collapse = "Control broke - that's the difference.",
            chaotic = "You let the race dictate you.",
        },
    },
}

local function _resolveTierTransitionVariant(career, direction, context)
    context = type(context) == "table" and context or {}

    local finishPosition = math.max(1, tonumber(context.finishPosition or context.finalPosition) or 1)
    local fieldSize = math.max(1, tonumber(context.fieldSize) or 1)
    local startPosition = math.max(1, tonumber(context.startPosition or finishPosition) or finishPosition)
    local deltaPos = tonumber(context.playerDeltaPos)
    local marginToNext = tonumber(context.marginToNext)
    local gapToLeader = tonumber(context.gapToLeader)
    local lossStreak = math.max(0, tonumber(context.lossStreak or (career and career.stats and career.stats.lossStreak) or 0) or 0)
    local winStreak = math.max(0, tonumber(context.winStreak or (career and career.stats and career.stats.winStreak) or 0) or 0)
    local isDNF = context.isDNF == true
    local isClean = context.isClean == true
    local closestGap = nil

    if deltaPos == nil then
        deltaPos = startPosition - finishPosition
    end
    if type(marginToNext) == "number" and marginToNext >= 0 then
        closestGap = marginToNext
    end
    if type(gapToLeader) == "number" and gapToLeader >= 0 and (closestGap == nil or gapToLeader < closestGap) then
        closestGap = gapToLeader
    end

    if direction == "up" and not isDNF and finishPosition == 1 and isClean and type(marginToNext) == "number" and marginToNext >= 1.50 then
        return "dominant"
    end
    if direction == "down" and (isDNF or deltaPos <= -3 or lossStreak >= 3) then
        return "collapse"
    end
    if direction == "up" and deltaPos >= 3 then
        return "comeback"
    end
    if context.source == "race" and isClean == false then
        return "chaotic"
    end
    if type(closestGap) == "number" and closestGap <= 0.75 then
        return "narrow"
    end
    if direction == "up" and (winStreak >= 3 or context.source == "season") then
        return "consistent"
    end

    return "base"
end

function Careers.prestigeRevealText(career, data)
    local direction = tostring(data and data.dir or "")
    local tier = tostring(data and data.to or (career and career.tier) or "")
    local variant = tostring(data and data.variant or "base")
    local tierBucket = TIER_TRANSITION_MESSAGES[direction]
    local tierCopy = tierBucket and tierBucket[tier] or nil

    if not tierCopy then
        return nil
    end

    return string.format("%s\n%s", tostring(tierCopy.line1 or ""), tostring(tierCopy[variant] or tierCopy.base or ""))
end

function Careers._applyTierChange(career, direction, newTier, context)
    if not career or not newTier or newTier == career.tier then
        return false
    end

    local oldTier = career.tier
    career.tier = newTier

    local tierInfo = TIER_BY_NAME[newTier]
    if direction == "up" then
        -- Start in the middle of the new tier
        local newDef = tierInfo and tierInfo.def
        local lo = newDef and newDef.repFloor or 0
        local hi = newDef and newDef.repCeiling or (lo + 2000)
        career.rep = math.floor((lo + hi) / 2)
    elseif direction == "down" then
        career.rep = tierInfo and tierInfo.def and tierInfo.def.relegReset or 0
    end

    print(string.format("[NCM/Careers] %s: %s → %s",
        direction == "up" and "PROMOTED" or "RELEGATED",
        oldTier,
        career.tier))
    local variant = _resolveTierTransitionVariant(career, direction, context)
    MTE.Events.emit("PrestigeChange", {
        dir = direction,
        from = oldTier,
        to = career.tier,
        career = career,
        variant = variant,
        context = context,
    })
    return true
end

function Careers.applySeasonLifecycle(career, summary)
    if not career then return nil end

    local seasonNumber = tonumber(summary and summary.seasonNumber) or career.seasonNumber or 1
    local finalPosition = math.max(1, tonumber(summary and summary.finalPosition) or 1)
    local fieldSize = math.max(1, tonumber(summary and summary.fieldSize) or 1)
    local scale = seasonRewardScale(career.tier)
    local normalizedFinish = (fieldSize - finalPosition) / math.max(1, fieldSize - 1)
    local movement = Careers.resolveSeasonMovement(career, finalPosition, fieldSize)

    local repBonus = math.floor((180 + (normalizedFinish * 360)) * scale)
    local eddies = math.floor((3500 + (normalizedFinish * 9000)) * scale)

    if movement.direction == "up" then
        repBonus = repBonus + math.floor(240 * scale)
        eddies = eddies + math.floor(6000 * scale)
    elseif movement.direction == "down" then
        repBonus = repBonus - math.floor(220 * scale)
        eddies = math.max(0, eddies - math.floor(2500 * scale))
    end

    career.rep = math.max(0, career.rep + repBonus)
    pcall(function() Game.AddToInventory("Items.money", eddies) end)
    career.stats.eddiesEarned = (career.stats.eddiesEarned or 0) + eddies

    if movement.newTier then
        Careers._applyTierChange(career, movement.direction, movement.newTier, {
            source = "season",
            finalPosition = finalPosition,
            fieldSize = fieldSize,
        })
    end

    Careers.save()
    return {
        season = seasonNumber,
        repBonus = repBonus,
        eddies = eddies,
        finalPosition = finalPosition,
        fieldSize = fieldSize,
        direction = movement.direction,
        fromTier = summary and summary.tier or nil,
        toTier = career.tier,
    }
end

--- Internal: check and apply real-time promotion or relegation based on rep thresholds.
function Careers._checkTierChange(career, context)
    if not career then return career end
    local tierInfo = TIER_BY_NAME[career.tier]
    if not tierInfo then return career end

    local idx = tierInfo.i
    local def = tierInfo.def

    -- Demotion: rep fell below current tier's floor
    if def.repFloor and career.rep < def.repFloor then
        local prevTier = TIER_TABLE[idx - 1]
        if prevTier then
            Careers._applyTierChange(career, "down", prevTier.name, context)
        end
    -- Promotion: rep reached current tier's ceiling
    elseif def.repCeiling and career.rep >= def.repCeiling then
        local nextTier = TIER_TABLE[idx + 1]
        if nextTier then
            Careers._applyTierChange(career, "up", nextTier.name, context)
        end
    end

    return career
end

--- Internal: award real CP2077 street cred XP.
function Careers._awardStreetCred(amount)
    if amount <= 0 then return end
    pcall(function()
        local devSys = Game.GetScriptableSystemsContainer():Get("PlayerDevelopmentSystem")
        local player = Game.GetPlayer()
        if devSys and player then
            devSys:AddExperience(player, amount, "StreetCred", "Quest")
        end
    end)
end

--- Record a completed race in career history (last 20 kept).
--- @param career  table
--- @param summary table  { position, time, district, fieldSize, distance, payout, repGain }
function Careers.recordRace(career, summary)
    career.stats.racesRun = career.stats.racesRun + 1
    if summary.dnf then
        career.stats.dnfs = career.stats.dnfs + 1
    else
        local f = career.stats
        f.racesFinished  = (f.racesFinished  or 0) + 1
        f.totalFinishPos = (f.totalFinishPos or 0) + (summary.position or 1)
        f.totalStartPos  = (f.totalStartPos  or 0) + (summary.startPos  or 1)
        if summary.position == 1          then f.wins    = (f.wins    or 0) + 1 end
        if (summary.position or 99) <= 3  then f.podiums = (f.podiums or 0) + 1 end
        if (summary.position or 99) <= 5  then f.top5s   = (f.top5s   or 0) + 1 end
        if summary.pole                   then f.poles   = (f.poles   or 0) + 1 end
    end
    career.stats.eddiesEarned = career.stats.eddiesEarned + (summary.payout or 0)

    table.insert(career.raceHistory, 1, summary)
    if #career.raceHistory > 20 then table.remove(career.raceHistory, 21) end

    -- Persist immediately so a crash doesn't lose race progress
    Careers.save()
end

local function playerBoxScoreStats(career)
    local summary = {
        racesRun = 0,
        racesFinished = 0,
        wins = 0,
        podiums = 0,
        top5s = 0,
        totalFinishPos = 0,
        totalStartPos = 0,
        eddiesEarned = 0,
    }

    local boxScores = career and career.boxScores or nil
    local records = boxScores and boxScores.records or nil
    if type(records) ~= "table" then
        return summary
    end

    local function payoutFromRecord(record, participant)
        local participantPayout = tonumber(participant and (participant.payout or participant.playerPayout or participant.purseAwarded) or 0) or 0
        local recordPayout = tonumber(type(record) == "table" and (record.playerPayout or record.payout or record.purseAwarded) or 0) or 0
        local explicitPayout = math.max(0, participantPayout, recordPayout)
        if explicitPayout > 0 then
            return explicitPayout
        end

        if type(participant) == "table" and participant.dnf ~= true then
            local finishPos = tonumber(participant.finishPos or 0) or 0
            return tonumber(BOX_SCORE_PAYOUT_BY_POS[finishPos] or 0) or 0
        end
        return 0
    end

    for _, record in ipairs(records) do
        local participants = type(record) == "table" and record.participants or nil
        if type(participants) == "table" then
            for _, participant in ipairs(participants) do
                if type(participant) == "table" and participant.isPlayer == true then
                    summary.racesRun = summary.racesRun + 1
                    summary.eddiesEarned = summary.eddiesEarned + payoutFromRecord(record, participant)
                    if participant.dnf ~= true then
                        local finishPos = tonumber(participant.finishPos or 0) or 0
                        local startPos = tonumber(participant.startPos or 0) or 0
                        summary.racesFinished = summary.racesFinished + 1
                        summary.totalFinishPos = summary.totalFinishPos + math.max(0, finishPos)
                        summary.totalStartPos = summary.totalStartPos + math.max(0, startPos)
                        if finishPos == 1 then summary.wins = summary.wins + 1 end
                        if finishPos > 0 and finishPos <= 3 then summary.podiums = summary.podiums + 1 end
                        if finishPos > 0 and finishPos <= 5 then summary.top5s = summary.top5s + 1 end
                    end
                    break
                end
            end
        end
    end

    return summary
end

--- Returns a computed stats summary for a career (averages, rates).
--- All raw counts plus derived percentages and averages.
function Careers.getStats(career)
    local s = career.stats or {}
    local boxScoreStats = playerBoxScoreStats(career)
    local racesRun = math.max(tonumber(s.racesRun or 0) or 0, boxScoreStats.racesRun)
    local finished = math.max(tonumber(s.racesFinished or 0) or 0, boxScoreStats.racesFinished)
    local wins = math.max(tonumber(s.wins or 0) or 0, boxScoreStats.wins)
    local podiums = math.max(tonumber(s.podiums or 0) or 0, boxScoreStats.podiums)
    local top5s = math.max(tonumber(s.top5s or 0) or 0, boxScoreStats.top5s)
    local totalFinishPos = math.max(tonumber(s.totalFinishPos or 0) or 0, boxScoreStats.totalFinishPos)
    local totalStartPos = math.max(tonumber(s.totalStartPos or 0) or 0, boxScoreStats.totalStartPos)
    local eddiesEarned = math.max(tonumber(s.eddiesEarned or 0) or 0, boxScoreStats.eddiesEarned)
    local safe     = math.max(finished, 1)  -- avoid div-by-zero
    return {
        racesRun      = racesRun,
        racesFinished = finished,
        wins          = wins,
        podiums       = podiums,
        top5s         = top5s,
        poles         = s.poles          or 0,
        dnfs          = s.dnfs           or 0,
        winStreak     = s.winStreak      or 0,
        lossStreak    = s.lossStreak     or 0,
        eddiesEarned  = eddiesEarned,
        winRate       = finished > 0 and string.format("%.1f%%", wins / safe * 100) or "--",
        podiumRate    = finished > 0 and string.format("%.1f%%", podiums / safe * 100) or "--",
        poleRate      = finished > 0 and string.format("%.1f%%", (s.poles   or 0) / safe * 100) or "--",
        top5Rate      = finished > 0 and string.format("%.1f%%", top5s / safe * 100) or "--",
        avgFinishPos  = finished > 0 and string.format("%.2f", totalFinishPos / safe) or "--",
        avgStartPos   = finished > 0 and string.format("%.2f", totalStartPos / safe) or "--",
    }
end

--- Check and update bounty state for a given driver after a race.
--- @param career   table
--- @param driverId string
--- @param playerWon bool
function Careers.updateBounty(career, driverId, playerWon)
    if not driverId then return false, false end

    local bounties = career.bounties or {}
    local b        = bounties[driverId]

    if playerWon then
        if not b then
            -- First time beating this driver → set bounty
            bounties[driverId] = { escalated = false, resolvedCount = 0 }
            career.bounties    = bounties
            Careers.save()
            return false, false  -- first beat, no bounty bonus yet (will show skull next time)
        else
            -- Resolving an existing bounty
            b.resolvedCount = b.resolvedCount + 1
            local wasEscalated  = b.escalated
            b.escalated         = false   -- reset escalation after resolution
            Careers.save()
            return true, wasEscalated    -- bountyResolved=true, bountyEscalated
        end
    else
        -- Player lost to a bounty driver → escalate
        if b then
            b.escalated = true
            Careers.save()
        end
        return false, false
    end
end

--- Returns true if driver has an active bounty from the player.
function Careers.hasBounty(career, driverId)
    local b = (career.bounties or {})[driverId]
    return b ~= nil
end

--- Returns true if the bounty is escalated (player lost after setting it).
function Careers.isBountyEscalated(career, driverId)
    local b = (career.bounties or {})[driverId]
    return b and b.escalated or false
end

--- Returns rep progress as 0-1 fraction between floor and ceiling of current tier.
function Careers.repProgress(career)
    local tierInfo = TIER_BY_NAME[career.tier]
    if not tierInfo then return 0 end
    local def = tierInfo.def
    local lo  = def.repFloor   or 0
    local hi  = def.repCeiling or (career.rep + 1000)
    local range = hi - lo
    if range <= 0 then return 1.0 end
    return math.max(0, math.min(1, (career.rep - lo) / range))
end

--- Returns floor and ceiling for the current tier (nil if unbounded).
function Careers.repThresholds(career)
    local tierInfo = TIER_BY_NAME[career.tier]
    if not tierInfo then return 0, nil end
    local def = tierInfo.def
    return def.repFloor or 0, def.repCeiling
end

--- Returns the stake max for the career's current tier.
function Careers.maxStake(career)
    return (career.config.stakeMaxByTier or {})[career.tier] or 1000
end

return Careers
