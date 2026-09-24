-- ============================================================
-- MT_Ecosystem: modules/roster.lua
-- 870-driver virtual roster, deterministically seeded per career.
-- Drivers are generated on demand and cached in roster_<seed>.json.
-- Same driver always has same name, color, car class, personality,
-- and base stats across all sessions in the same career.
--
-- Tier pool sizes:
--   Gonk: 500  Streetkid: 200  Solo: 100  Fixer: 50  Edgerunner: 20
--
-- Global index layout:
--   Gonk        0–499
--   Streetkid 500–699
--   Solo      700–799
--   Fixer     800–849
--   Edgerunner 850–869
-- ============================================================

local Roster = {}
local Persist = require("modules/persistence")

local VehiclePool = require("data/vehicle_pool")
local Factions    = require("data/factions")

-- ── Tier definitions ──────────────────────────────────────────

local TIER_DEFS = {
    { name = "Gonk",        size = 500, offset = 0,   aiMin = 8,  aiMax = 12 },
    { name = "Streetkid",   size = 200, offset = 500, aiMin = 7,  aiMax = 10 },
    { name = "Solo",        size = 100, offset = 700, aiMin = 6,  aiMax = 9  },
    { name = "Fixer",       size = 50,  offset = 800, aiMin = 5,  aiMax = 7  },
    { name = "Edgerunner",  size = 20,  offset = 850, aiMin = 4,  aiMax = 6  },
}

local TIER_INDEX = {}
for _, td in ipairs(TIER_DEFS) do TIER_INDEX[td.name] = td end

local CURATED_TIERS = { Fixer = 0.70, Edgerunner = 0.85 }

-- Minimum drivers to pre-generate per tier for background simulation.
-- Enough to create meaningful leaderboard depth without generating all 870.
local MIN_POP = {
    Gonk       = 80,
    Streetkid  = 40,
    Solo       = 25,
    Fixer      = 15,
    Edgerunner = 20,
}

-- Pace range per tier (multiplier: >1 = faster than baseline 50m/s)
local TIER_PACE = {
    Gonk       = { lo = 0.72, hi = 0.96 },
    Streetkid  = { lo = 0.82, hi = 1.06 },
    Solo       = { lo = 0.92, hi = 1.16 },
    Fixer      = { lo = 1.02, hi = 1.26 },
    Edgerunner = { lo = 1.12, hi = 1.40 },
}

local REP_BY_POS = { 280, 160, 90, 35, 10 }
local PROMO_REP = {
    Gonk = 1500,
    Streetkid = 5500,
    Solo = 15000,
    Fixer = 40000,
    Edgerunner = math.huge,
}
local DEMOTE_REP = {
    Gonk = 0,
    Streetkid = 200,
    Solo = 800,
    Fixer = 3000,
    Edgerunner = 8000,
}
local DEMOTE_AFTER_RACES = 20
local RECENT_FINISH_WINDOW = 5
local TOP_TIER_NAME = "Edgerunner"
local TOP_TIER_SIZE = 20
local SIDELINE_TICK_MAX = 4
local WORLD_EVENT_COOLDOWN = 3
local RETIREMENT_MIN_RACES = 18

-- ── Name banks (CP2077-flavored) ──────────────────────────────

local FIRST_NAMES = {
    "Rache","Zora","Mox","Dex","Sable","Ghost","Nyx","Flux","Kira","Brix",
    "Vex","Colt","Dusk","Kaze","Ronin","Pixel","Wire","Blade","Arc","Kai",
    "Juno","Relic","Cipher","Drift","Storm","Ash","Blaze","Cruz","Dante","Echo",
    "Frost","Glitch","Havoc","Iris","Jin","Knox","Lyra","Mace","Nova","Orin",
    "Pyre","Quinn","Reed","Sera","Thorn","Ursa","Vale","Wick","Xen","Yuri",
    "Akira","Bryx","Caen","Daze","Edge","Fray","Grim","Hex","Ink","Jade",
    "Aero","Anya","Basil","Bishop","Blaine","Cairo","Camber","Cass","Chroma","Cinder",
    "Clove","Coda","Corin","Crow","Cyra","Daxton","Delta","Dorian","Ember","Falcon",
    "Faye","Gage","Halo","Indra","Ivo","Jax","Jet","Jett","Kael","Kato",
    "Keir","Kestrel","Koda","Lark","Lazar","Lex","Lio","Lux","Mira","Nero",
    "Nika","Nyra","Onyx","Pax","Piper","Quade","Riven","Rook","Rune","Sable",
    "Scar","Shade","Skye","Slate","Sol","Static","Styx","Talon","Tempest","Vanta",
    "Vector","Vera","Vigil","Volt","Wren","Xara","Yara","Zephyr","Zero","Ziv",
}  -- 140

local LAST_NAMES = {
    "Hamilton","Cruz","Kasinski","Okafor","Tanaka","Muller","Reyes","Petrov","Kim","Santos",
    "Okonkwo","Volkov","Nakamura","Ferreira","Chen","Johansson","Al-Rashid","Larson","Kovač","Nkosi",
    "Yamamoto","Delgado","Svensson","Patel","Rossi","Fischer","Andersen","Kowalski","Webb","Stone",
    "Cross","Steel","Sharp","Fox","Cole","Drake","Lane","Nash","Reid","Shaw",
    "Todd","Wade","York","Holt","Kerr","Moss","Page","Ray","Sage","Wolf",
    "Zane","Beck","Carr","Dale","Flint","Grant","Hayes","Irons","Kane","Lake",
    "Moore","Night","Pierce","Rook","Trace","Voss","Ward","Wyatt","Lord","Vale",
    "Obi","Steele","Graves","Frost","Ace","Ren","Mori","Park","Diaz","Finn",
    "Archer","Ashford","Black","Blake","Blythe","Boone","Brandt","Briar","Brooks","Byrne",
    "Calder","Callow","Carver","Cassidy","Cline","Corvin","Crowe","Danner","Darrow","Dax",
    "Doyle","Easton","Emberlane","Everett","Farrow","Fenix","Fenn","Ford","Gallow","Gant",
    "Gideon","Glass","Grimm","Halden","Hale","Hawke","Huxley","Ives","Jett","Kaine",
    "Keegan","Kincaid","Knoll","Kross","Lennox","Locke","Maddox","Marlowe","Mercer","Morrow",
    "Nero","North","Novak","Ortega","Pryce","Quill","Quinn","Raine","Rex","Riven",
    "Rowan","Ryder","Sable","Salazar","Scorn","Sloan","Stroud","Thatcher","Thorne","Valez",
    "Vega","Vesper","Vey","Vigil","Vireo","Warden","Wolfe","Wren","Yates","Zorin",
}  -- 160

local EXTRA_FIRST_NAMES = {
    "Aksel","Alix","Alma","Amari","Arden","Aria","Ariq","Astra","Atlas","Avery",
    "Azra","Bex","Bianca","Bodie","Bolt","Brand","Breaker","Brio","Callum","Calyx",
    "Cannon","Carys","Cassian","Cato","Celine","Chase","Chrome","Cian","Circuit","Cleo",
    "Clio","Cutter","Dara","Darian","Dash","Decker","Demi","Dion","Dune","Elio",
    "Elara","Enzo","Eris","Eska","Fable","Faris","Fawn","Felix","Fiora","Freya",
    "Galen","Glimmer","Greer","Grit","Hana","Harper","Helix","Hera","Hush","Ilan",
    "Imani","Indigo","Ione","Ion","Jace","Jessa","Jules","Jun","Kaia","Kellan",
    "Kian","Kit","Koa","Lena","Levi","Lumen","Mara","Marek","Mica","Milan",
    "Mina","Moxie","Nadia","Nia","Niko","Nolan","Nyssa","Omar","Orchid","Osric",
    "Petra","Quill","Rhea","Rina","Roux","Sacha","Selene","Shiv","Soren","Suri",
    "Talia","Tarin","Thane","Tove","Valea","Veda","Vespera","Vexley","Vida","Viktor",
    "Wilder","Xavi","Yuna","Zadie","Zella","Aurel","Brisa","Cora","Eamon","Iskra",
    "Jori","Kairo","Liora","Maven","Noor","Oriel","Phaedra","Renna","Sablet","Talonis",
}

local EXTRA_LAST_NAMES = {
    "Avery","Baird","Bannon","Barlow","Barrett","Beaumont","Bennett","Benson","Bexley","Boden",
    "Brenner","Briggs","Brock","Cabrera","Cade","Calhoun","Caruso","Castro","Cervantes","Clay",
    "Colson","Conrad","Corbett","Costa","Crowley","Dalca","Dawes","Delane","Donovan","Drexler",
    "Duarte","Ellis","Everly","Falco","Farren","Farrowe","Fenwick","Ferrer","Frostholm","Gaines",
    "Garnett","Givens","Goss","Granger","Halevy","Harker","Harlow","Hart","Hawthorne","Hendrix",
    "Ibarra","Ivers","Iverson","Jacobs","Jarik","Kade","Keller","Kestrel","Knoxx","Korvin",
    "Kozlov","Lazaro","Ledger","Lennart","Leto","Lugo","Madden","Marin","Marrow","Mercury",
    "Meyer","Monroe","Montrose","Navarro","Nox","Orsini","Oakes","Pereira","Prescott","Quarry",
    "Quint","Ramirez","Ransom","Ravel","Rooke","Rourke","Santosh","Serrano","Severin","Shepard",
    "Silva","Sorensen","Straker","Sutter","Talbot","Tanner","Thorneau","Torres","Valen","Varik",
    "Vargas","Vegares","Ventra","Verano","Vossler","Welles","West","Wilder","Winters","Yarrow",
    "Yorin","Zoric","Zayas","Ashen","Blackwell","Cinder","Draven","Emory","Folsom","Hux",
    "Jasper","Kincannon","Lockhart","Nightingale","Roth","Sterling","Vandal","Aldrin","Bracken","Caulder",
    "Dunne","Echevarria","Fairchild","Galloway","Hollis","Icarus","Junoir","Kesting","Lovelace","Mirek",
}

local DRIVER_HANDLES = {
    "Afterburn","Ashes","Backspin","Blackout","Bleed","Blink","Bluewire","Bones","Boost","Breakpoint",
    "Burnout","Caltrop","Carbon","Chimera","Circuit","Crash","Crowbar","Deadlock","Deadwire","Dervish",
    "Doubleshift","Downforce","Driftline","Dustup","Faultline","Firewall","Flipside","Ghostline","Glare","Hardline",
    "Hex","Hotlap","Jetwash","Killjoy","Knifeline","Liftoff","Limiter","Lockjaw","Longshot","Lowline",
    "Mainline","Mayhem","Monsoon","Nightglass","Nitro","Null","Oversteer","Patch","Payload","Pitghost",
    "Quickhack","Ratchet","Redmist","Reverb","Roadrash","Rollback","Sidebite","Sideslip","Skid","Slipstream",
    "Snapshot","Spark","Spinout","Splitter","Static","Switch","Takedown","Throttle","Torque","Trailbrake",
    "Undercut","Volt","Wetwork","Wildcard","Wildfire","Zero-Day","Black ICE","Cold Start","Dogtown","Ghost Mile",
}

local function extendUnique(base, extra)
    local seen = {}
    local out = {}

    local function append(list)
        for _, value in ipairs(list or {}) do
            if type(value) == "string" and value ~= "" and not seen[value] then
                seen[value] = true
                out[#out + 1] = value
            end
        end
    end

    append(base)
    append(extra)
    return out
end

FIRST_NAMES = extendUnique(FIRST_NAMES, EXTRA_FIRST_NAMES)
LAST_NAMES = extendUnique(LAST_NAMES, EXTRA_LAST_NAMES)
DRIVER_HANDLES = extendUnique(DRIVER_HANDLES, {})

-- Names are now composed from first-name, surname, and optional handle/compound-surname layers.
-- Collisions across tiers are still acceptable (same name, different tier = different person).

local CAR_CLASSES    = { "Muscle", "Sport", "Tech", "Nomad", "Bike" }
local PERSONALITIES  = {
    "aggressive closer", "clean runner",   "crash magnet",
    "inconsistent",      "ice cold",       "dirty fighter",
    "slow starter",      "street smart",   "risk taker",
    "steady grinder",
}
local HOME_REGIONS   = { "Watson", "Westbrook", "Heywood", "Pacifica", "City Center", "Santo Domingo", "Badlands" }

-- ── LCG seeder (deterministic, Lua-safe with doubles) ─────────
-- Numerical Recipes LCG: x = (a*x + c) mod m
-- m = 2^32, a = 1664525, c = 1013904223
-- Max intermediate: 1664525 * (2^32-1) ≈ 7.1e12 < 2^53 ✓

local LCG_A = 1664525
local LCG_C = 1013904223
local LCG_M = 4294967296  -- 2^32

local function lcgNext(s)
    return math.floor((s * LCG_A + LCG_C) % LCG_M)
end

--- Derive the base seed for driver at globalIndex in this career.
local function driverSeed(careerSeed, globalIndex)
    -- Mix career seed with index using two passes to spread distribution
    local s = math.floor((careerSeed + globalIndex * 2654435761) % LCG_M)
    s = lcgNext(s)
    s = lcgNext(s)
    return s
end

--- Pull N successive 0-1 floats from a seed chain.
local function seededFloats(seed, n)
    local vals = {}
    local s = seed
    for i = 1, n do
        s = lcgNext(s)
        vals[i] = s / LCG_M
    end
    return vals
end

--- Pick an index into a table from a 0-1 float.
local function pick(list, frac)
    return list[math.max(1, math.floor(frac * #list + 1))]
end

local function pickDistinct(list, frac, forbidden)
    local count = #list
    if count <= 0 then
        return nil
    end
    local index = math.max(1, math.min(count, math.floor((frac or 0) * count) + 1))
    local value = list[index]
    if value ~= forbidden or count == 1 then
        return value
    end
    index = (index % count) + 1
    return list[index]
end

local function pickDriverName(vals)
    local firstName = pick(FIRST_NAMES, vals[1] or 0)
    local lastName = pick(LAST_NAMES, vals[2] or 0)
    local secondLast = pickDistinct(LAST_NAMES, vals[3] or vals[14] or 0, lastName)
    local handle = pickDistinct(DRIVER_HANDLES, vals[16] or vals[12] or 0, firstName)
    local surnameRoll = vals[4] or 0
    local handleRoll = vals[5] or 1

    local resolvedLast = lastName
    if secondLast then
        if surnameRoll < 0.11 then
            resolvedLast = string.format("%s-%s", tostring(lastName), tostring(secondLast))
        elseif surnameRoll < 0.19 then
            resolvedLast = string.format("%s %s", tostring(lastName), tostring(secondLast))
        end
    end

    if handle and handleRoll < 0.17 then
        return string.format("%s \"%s\" %s", tostring(firstName), tostring(handle), tostring(resolvedLast))
    end
    return string.format("%s %s", tostring(firstName), tostring(resolvedLast))
end

local function shuffleArray(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local function tierOrdinal(tier)
    for i, td in ipairs(TIER_DEFS) do
        if td.name == tier then
            return i, td
        end
    end
    return nil, nil
end

local function averageRecentFinish(driver)
    local finishes = driver and driver.recentFinishes or nil
    if type(finishes) ~= "table" or #finishes <= 0 then
        return nil
    end
    local total = 0
    local count = 0
    for _, finish in ipairs(finishes) do
        local position = tonumber(finish)
        if position and position > 0 then
            total = total + position
            count = count + 1
        end
    end
    if count <= 0 then
        return nil
    end
    return total / count
end

local function recentDNFCount(driver)
    local count = 0
    for _, finish in ipairs(driver and driver.recentFinishes or {}) do
        if (tonumber(finish) or 0) >= 99 then
            count = count + 1
        end
    end
    return count
end

local function setLastWorldEvent(driver, text)
    driver.lastWorldEvent = text
    driver.lastWorldEventAt = os.time()
    driver.worldCooldown = WORLD_EVENT_COOLDOWN
end

local function ensureLifecycleFields(driver)
    local dirty = false
    if driver.availability == nil then
        driver.availability = "active"
        dirty = true
    end
    if driver.availabilityTicks == nil then
        driver.availabilityTicks = 0
        dirty = true
    end
    if driver.formBias == nil then
        driver.formBias = 0.0
        dirty = true
    end
    if driver.formTag == nil then
        driver.formTag = ""
        dirty = true
    end
    if driver.formTicks == nil then
        driver.formTicks = 0
        dirty = true
    end
    if driver.lastWorldEvent == nil then
        driver.lastWorldEvent = ""
        dirty = true
    end
    if driver.lastWorldEventAt == nil then
        driver.lastWorldEventAt = 0
        dirty = true
    end
    if driver.worldCooldown == nil then
        driver.worldCooldown = 0
        dirty = true
    end
    return dirty
end

local function driverIsAvailable(driver)
    ensureLifecycleFields(driver)
    return tostring(driver.availability or "active") == "active"
end

local function pushRecentFinish(driver, position)
    ensureLifecycleFields(driver)
    if type(driver.recentFinishes) ~= "table" then
        driver.recentFinishes = {}
    end
    table.insert(driver.recentFinishes, tonumber(position) or 99)
    while #driver.recentFinishes > RECENT_FINISH_WINDOW do
        table.remove(driver.recentFinishes, 1)
    end
end

local function updateDriverMomentum(driver)
    ensureLifecycleFields(driver)
    local avgFinish = averageRecentFinish(driver)
    local dnfs = recentDNFCount(driver)

    if avgFinish and avgFinish <= 2.4 then
        driver.formBias = math.min(0.10, (tonumber(driver.formBias) or 0.0) + 0.025)
        driver.formTag = "surging"
        driver.formTicks = math.max(tonumber(driver.formTicks) or 0, 3)
        return
    end

    if avgFinish and (avgFinish >= 5.5 or dnfs >= 2) then
        driver.formBias = math.max(-0.10, (tonumber(driver.formBias) or 0.0) - 0.025)
        driver.formTag = "slumping"
        driver.formTicks = math.max(tonumber(driver.formTicks) or 0, 3)
        return
    end

    driver.formBias = (tonumber(driver.formBias) or 0.0) * 0.65
    if math.abs(driver.formBias) < 0.01 then
        driver.formBias = 0.0
    end
    if (tonumber(driver.formTicks) or 0) <= 0 and math.abs(driver.formBias) < 0.02 then
        driver.formTag = ""
    end
end

local function getDriverIdentitySeedValues(driver, careerSeed)
    local baseTier = driver.tier or driver.currentTier or "Gonk"
    local td = TIER_INDEX[baseTier] or TIER_DEFS[1]
    local idxStr = tostring(driver.id or ""):match("_(%d+)$")
    local driverIdx = tonumber(idxStr) or 0
    local globalIdx = td.offset + driverIdx
    local seed = driverSeed(careerSeed, globalIdx)
    return seededFloats(seed, 16)
end

local function refreshNameIdentity(driver, careerSeed)
    if type(driver) ~= "table" then
        return false
    end
    local vals = getDriverIdentitySeedValues(driver, careerSeed)
    local resolved = pickDriverName(vals)
    if driver.name == resolved then
        return false
    end
    driver.name = resolved
    return true
end

local function refreshNPCIdentity(driver, careerSeed)
    local vals = getDriverIdentitySeedValues(driver, careerSeed)
    local factionId = driver.factionId
    if not factionId then
        local faction = Factions.pickForDriver(vals[15], driver.currentTier or driver.tier)
        driver.factionId    = faction.id
        driver.factionName  = faction.name
        driver.factionColor = faction.color
        factionId = faction.id
    end
    driver.npcRecord = VehiclePool.resolveNPC(math.floor((vals[13] or 0) * 1000), factionId)
end

-- ── Driver generation ─────────────────────────────────────────

local function generateDriver(careerSeed, tier, index)
    local td        = TIER_INDEX[tier]
    local globalIdx = td.offset + index
    local seed      = driverSeed(careerSeed, globalIdx)
    local vals      = seededFloats(seed, 16)

    local displayName = pickDriverName(vals)

    -- Hue-spread colors — avoid near-black or near-white
    local r = 0.3 + vals[3] * 0.7
    local g = 0.3 + vals[4] * 0.7
    local b = 0.3 + vals[5] * 0.7

    local pr   = TIER_PACE[tier]
    local pace = pr.lo + vals[6] * (pr.hi - pr.lo)

    -- Tier-aware class and vehicle: deterministic off seeded float stream
    local carClass     = VehiclePool.pickWeightedClassForTier(tier, vals[7])
    local vehicleEntry = VehiclePool.resolveVehicleForTier(tier, carClass, vals[14])

    -- Faction/team identity: deterministic from seed, stable across sessions
    local faction = Factions.pickForDriver(vals[15], tier)

    -- Stable cosmetic identity: deterministic NPC from career seed
    local npcRecord        = VehiclePool.resolveNPC(math.floor(vals[13] * 1000), faction.id)
    local vehicleSignature = vehicleEntry.id
    local vehiclePrestige  = vehicleEntry.prestige

    return {
        id          = tier:lower():sub(1,4) .. "_" .. string.format("%03d", index),
        name        = displayName,
        tier        = tier,
        color       = { r, g, b },
        carClass    = carClass,
        personality = pick(PERSONALITIES, vals[8]),
        homeRegion  = pick(HOME_REGIONS,  vals[9]),
        -- Stats (0-1 normalized, tier-biased via pace range above)
        pace        = pace,
        aggression  = vals[10],
        precision   = vals[11],
        consistency = vals[12],
        -- Stable cosmetic identity (persisted with roster cache)
        npcRecord        = npcRecord,
        vehicleSignature = vehicleSignature,
        vehiclePrestige  = vehiclePrestige,
        -- Faction/team identity (motorsport layer, separate from prestige tier)
        factionId    = faction.id,
        factionName  = faction.name,
        factionColor = faction.color,
        -- Rival tracking (mutates per career, saved with cache)
        rivalScore     = 0,
        headToHeadWins = 0,
        lastBeatPlayer = false,
        -- Dynamic state (mutates per career — NOT seeded, saved separately)
        rep         = 0,
        currentTier = tier,
        racesRun    = 0,
        wins        = 0,
        hasBountyOn = false,      -- player has beaten this driver
        bountyEscalated = false,  -- player lost to them after bounty was set
        lastRaceResult  = nil,
        -- Recent form (rolling window of last 5 finish positions; 1=win, 99=DNF)
        recentFinishes  = {},
        availability = "active",
        availabilityTicks = 0,
        formBias = 0.0,
        formTag = "",
        formTicks = 0,
        lastWorldEvent = "",
        lastWorldEventAt = 0,
        worldCooldown = 0,
    }
end

-- ── Cache ─────────────────────────────────────────────────────
-- _cache[careerSeed][driverId] = driverTable
local _cache = {}

local function cacheKey(careerSeed)
    return tostring(careerSeed)
end

local function getCacheForCareer(careerSeed)
    local k = cacheKey(careerSeed)
    if not _cache[k] then _cache[k] = {} end
    return _cache[k]
end

local function collectAvailableDriversForTier(career, tier, minCount)
    local td = TIER_INDEX[tier]
    if not td then return {} end

    local cache = getCacheForCareer(career.seed)
    local available = {}
    for _, driver in pairs(cache) do
        if driver.currentTier == tier and driverIsAvailable(driver) then
            table.insert(available, driver)
        end
    end

    local need = math.max(0, (tonumber(minCount) or 0) - #available)
    if need > 0 then
        local generated = {}
        for i = 0, td.size - 1 do
            local id = tier:lower():sub(1,4) .. "_" .. string.format("%03d", i)
            if not cache[id] then
                table.insert(generated, i)
            end
        end
        shuffleArray(generated)
        for i = 1, math.min(need, #generated) do
            local driver = Roster.get(career, tier, generated[i])
            table.insert(available, driver)
        end
    end

    return available
end

local function scoreDriverForCuration(driver, maxRep)
    local formScore = 0
    if driver.recentFinishes and #driver.recentFinishes > 0 then
        local sum = 0
        for _, pos in ipairs(driver.recentFinishes) do sum = sum + pos end
        local avgPos = sum / #driver.recentFinishes
        formScore = math.max(-20, 40 - (avgPos - 1) * (60 / 9))
    end
    return ((driver.rep or 0) / math.max(1, maxRep)) * 50
        + (driver.wins or 0) * 5
        + (driver.rivalScore or 0) * 0.5
        + formScore
        + ((tonumber(driver.formBias) or 0.0) * 60.0)
end

local function selectTierField(career, tier, count)
    local available = collectAvailableDriversForTier(career, tier, count)
    if count <= 0 or #available == 0 then return {} end

    local field = {}
    local curationFrac = CURATED_TIERS[tier]
    if curationFrac and #available > count then
        local maxRep = 1
        for _, driver in ipairs(available) do
            if (driver.rep or 0) > maxRep then maxRep = driver.rep end
        end

        local scored = {}
        for _, driver in ipairs(available) do
            table.insert(scored, {
                driver = driver,
                score = scoreDriverForCuration(driver, maxRep),
            })
        end
        table.sort(scored, function(left, right) return left.score > right.score end)

        local eliteSlots = math.floor(count * curationFrac)
        local wildcardSlots = count - eliteSlots
        local elitePool = {}
        local topBand = math.ceil(math.max(1, eliteSlots) * 1.5)
        for i = 1, math.min(topBand, #scored) do
            table.insert(elitePool, scored[i].driver)
        end
        shuffleArray(elitePool)
        for i = 1, math.min(eliteSlots, #elitePool) do
            table.insert(field, elitePool[i])
        end

        local usedIds = {}
        for _, driver in ipairs(field) do usedIds[driver.id] = true end

        local wildPool = {}
        for _, entry in ipairs(scored) do
            if not usedIds[entry.driver.id] then
                table.insert(wildPool, entry.driver)
            end
        end
        shuffleArray(wildPool)
        for i = 1, math.min(wildcardSlots, #wildPool) do
            table.insert(field, wildPool[i])
        end
        return field
    end

    shuffleArray(available)
    for i = 1, math.min(count, #available) do
        table.insert(field, available[i])
    end
    return field
end

local function cacheFilename(careerSeed)
    return "roster_" .. tostring(careerSeed) .. ".json"
end

--- Re-derive carClass, vehicleSignature, and vehiclePrestige for a driver
--- whose currentTier has just changed (promotion or demotion).
--- Uses the same deterministic seed stream as generateDriver so the vehicle
--- assignment is stable within a tier but updates when the tier changes.
--- @param driver      table   live driver object (currentTier must already be updated)
--- @param careerSeed  number  the career's seed value
local function refreshVehicleForTier(driver, careerSeed)
    local td = TIER_INDEX[driver.currentTier]
    if not td then return end
    local idxStr    = driver.id:match("_(%d+)$")
    local driverIdx = tonumber(idxStr) or 0
    local globalIdx = td.offset + driverIdx
    local seed      = driverSeed(careerSeed, globalIdx)
    local vals      = seededFloats(seed, 16)
    local cls       = VehiclePool.pickWeightedClassForTier(driver.currentTier, vals[7])
    local entry     = VehiclePool.resolveVehicleForTier(driver.currentTier, cls, vals[14], driver)
    driver.carClass         = cls
    driver.vehicleSignature = entry.id
    driver.vehiclePrestige  = entry.prestige
end

local function standingScore(driver, maxRep)
    local avgFinish = averageRecentFinish(driver)
    local formScore = avgFinish and math.max(-25, 36 - ((avgFinish - 1) * 7)) or 0
    return (tonumber(driver.pace) or 0.0) * 70.0
        + (tonumber(driver.precision) or 0.0) * 18.0
        + (tonumber(driver.consistency) or 0.0) * 24.0
        + ((tonumber(driver.rep) or 0) / math.max(1, maxRep)) * 45.0
        + (tonumber(driver.wins) or 0) * 5.0
        + formScore
        + ((tonumber(driver.formBias) or 0.0) * 85.0)
end

local function protectedDriverIds(career)
    local protected = {}
    local slots = career and career.management and career.management.signedSlots or nil
    if type(slots) ~= "table" then
        return protected
    end
    for _, slot in ipairs(slots) do
        local driverId = slot and slot.driverId or nil
        if driverId then
            protected[driverId] = true
        end
    end
    return protected
end

local function setDriverTier(career, driver, newTier, resetRep, eventText)
    if not driver or not newTier or driver.currentTier == newTier then
        return false
    end
    driver.currentTier = newTier
    if resetRep ~= nil then
        driver.rep = resetRep
    end
    ensureLifecycleFields(driver)
    driver.availability = "active"
    driver.availabilityTicks = 0
    refreshVehicleForTier(driver, career.seed)
    if eventText then
        setLastWorldEvent(driver, eventText)
    end
    return true
end

local function applyTierPressureToDriver(career, driver)
    if not driver then
        return nil
    end
    ensureLifecycleFields(driver)
    if tostring(driver.availability or "active") == "retired" then
        return nil
    end

    local threshold = PROMO_REP[driver.currentTier]
    if threshold and driver.rep >= threshold then
        local nextTier = Roster.nextTier(driver.currentTier)
        if nextTier then
            setDriverTier(career, driver, nextTier, 0, string.format("Moved up to %s.", tostring(nextTier)))
            return "promoted"
        end
    elseif driver.racesRun >= DEMOTE_AFTER_RACES then
        local demoteThreshold = DEMOTE_REP[driver.currentTier] or 0
        if driver.rep < demoteThreshold then
            local prevTier = Roster.prevTier(driver.currentTier)
            if prevTier then
                local resetRep = PROMO_REP[prevTier] and math.floor(PROMO_REP[prevTier] * 0.8) or driver.rep
                setDriverTier(career, driver, prevTier, resetRep, string.format("Dropped back to %s.", tostring(prevTier)))
                return "demoted"
            end
        end
    end
    return nil
end

local function tierDrivers(cache, tier, onlyAvailable)
    local drivers = {}
    for _, driver in pairs(cache) do
        if driver.currentTier == tier and (not onlyAvailable or driverIsAvailable(driver)) then
            drivers[#drivers + 1] = driver
        end
    end
    return drivers
end

local function replenishTierPopulation(career, tier, minCount)
    local cache = getCacheForCareer(career.seed)
    local active = tierDrivers(cache, tier, true)
    local need = math.max(0, tonumber(minCount or 0) - #active)
    if need <= 0 then
        return 0
    end

    local td = TIER_INDEX[tier]
    if not td then
        return 0
    end

    local added = 0
    for index = 0, td.size - 1 do
        if added >= need then
            break
        end
        local driverId = tier:lower():sub(1,4) .. "_" .. string.format("%03d", index)
        if not cache[driverId] then
            local rookie = generateDriver(career.seed, tier, index)
            setLastWorldEvent(rookie, string.format("Called up into %s.", tostring(tier)))
            cache[driverId] = rookie
            added = added + 1
        end
    end
    return added
end

local function enforceTopTierCap(career)
    local cache = getCacheForCareer(career.seed)
    local activeTopTier = tierDrivers(cache, TOP_TIER_NAME, true)

    local maxRep = 1
    for _, driver in ipairs(activeTopTier) do
        maxRep = math.max(maxRep, tonumber(driver.rep) or 0)
    end

    table.sort(activeTopTier, function(left, right)
        return standingScore(left, maxRep) > standingScore(right, maxRep)
    end)

    local changes = 0
    for index = TOP_TIER_SIZE + 1, #activeTopTier do
        local driver = activeTopTier[index]
        local resetRep = math.floor((PROMO_REP.Fixer or 0) * 0.8)
        if setDriverTier(career, driver, "Fixer", resetRep, "Edgerunner seat lost.") then
            changes = changes + 1
        end
    end

    activeTopTier = tierDrivers(cache, TOP_TIER_NAME, true)
    if #activeTopTier < TOP_TIER_SIZE then
        collectAvailableDriversForTier(career, "Fixer", TOP_TIER_SIZE)
        local fixerPool = tierDrivers(cache, "Fixer", true)
        local fixerMaxRep = 1
        for _, driver in ipairs(fixerPool) do
            fixerMaxRep = math.max(fixerMaxRep, tonumber(driver.rep) or 0)
        end
        table.sort(fixerPool, function(left, right)
            return standingScore(left, fixerMaxRep) > standingScore(right, fixerMaxRep)
        end)
        local openSeats = TOP_TIER_SIZE - #activeTopTier
        for index = 1, math.min(openSeats, #fixerPool) do
            local driver = fixerPool[index]
            if setDriverTier(career, driver, TOP_TIER_NAME, 0, "Promoted into the Edgerunner field.") then
                changes = changes + 1
            end
        end
    end

    return changes
end

local function tickAvailability(driver)
    ensureLifecycleFields(driver)
    driver.worldCooldown = math.max(0, (tonumber(driver.worldCooldown) or 0) - 1)
    if driver.formTicks and driver.formTicks > 0 then
        driver.formTicks = driver.formTicks - 1
        if driver.formTicks <= 0 and math.abs(tonumber(driver.formBias) or 0.0) < 0.02 then
            driver.formTag = ""
        end
    end

    if driver.availability == "sidelined" then
        driver.availabilityTicks = math.max(0, (tonumber(driver.availabilityTicks) or 0) - 1)
        if driver.availabilityTicks <= 0 then
            driver.availability = "active"
            setLastWorldEvent(driver, "Cleared back onto the grid.")
        end
    end
end

local function runLifecycleSweep(career, pulses)
    local cache = getCacheForCareer(career.seed)
    local protected = protectedDriverIds(career)
    local totalPulses = math.max(1, tonumber(pulses) or 1)

    for _ = 1, totalPulses do
        for _, driver in pairs(cache) do
            tickAvailability(driver)
        end

        local sidelineCandidates = {}
        local retirementCandidates = {}
        for _, driver in pairs(cache) do
            ensureLifecycleFields(driver)
            if driverIsAvailable(driver) and not protected[driver.id] and (tonumber(driver.worldCooldown) or 0) <= 0 then
                local avgFinish = averageRecentFinish(driver) or 6.0
                local dnfs = recentDNFCount(driver)
                local racesRun = tonumber(driver.racesRun) or 0
                local rep = tonumber(driver.rep) or 0
                local sidelineScore = (dnfs * 18.0)
                    + ((tonumber(driver.aggression) or 0.0) * 10.0)
                    + ((1.0 - (tonumber(driver.consistency) or 0.0)) * 8.0)
                    + math.max(0.0, avgFinish - 4.0) * 3.0
                sidelineCandidates[#sidelineCandidates + 1] = {
                    driver = driver,
                    score = sidelineScore,
                }

                if racesRun >= RETIREMENT_MIN_RACES and driver.currentTier ~= TOP_TIER_NAME then
                    local retirementScore = (racesRun * 0.8)
                        + math.max(0.0, avgFinish - 5.0) * 12.0
                        + (dnfs * 10.0)
                        - math.min(45.0, rep / 220.0)
                    retirementCandidates[#retirementCandidates + 1] = {
                        driver = driver,
                        score = retirementScore,
                    }
                end
            end
        end

        table.sort(sidelineCandidates, function(left, right) return left.score > right.score end)
        table.sort(retirementCandidates, function(left, right) return left.score > right.score end)

        if #sidelineCandidates > 0 and math.random() < 0.30 then
            local pickIndex = math.random(1, math.min(3, #sidelineCandidates))
            local driver = sidelineCandidates[pickIndex].driver
            driver.availability = "sidelined"
            driver.availabilityTicks = math.random(1, SIDELINE_TICK_MAX)
            setLastWorldEvent(driver, "Picked up damage and missed a few heats.")
        end

        if #retirementCandidates > 0 and math.random() < 0.14 then
            local pickIndex = math.random(1, math.min(2, #retirementCandidates))
            local driver = retirementCandidates[pickIndex].driver
            driver.availability = "retired"
            driver.availabilityTicks = 0
            setLastWorldEvent(driver, "Stepped away from the circuit.")
        end

        for _, td in ipairs(TIER_DEFS) do
            replenishTierPopulation(career, td.name, MIN_POP[td.name] or 0)
        end
        enforceTopTierCap(career)
    end
end

-- ── Public API ────────────────────────────────────────────────

--- Developer toggle: set to true before loading a career to re-derive all
--- vehicle assignments from current tier rules, overwriting legacy cars.
--- Set back to false immediately after for normal operation.
Roster.REBALANCE_VEHICLES = false
Roster.REBALANCE_NAMES = false

-- ── Roster metadata (separate file so driver cache stays a flat driver map) ──

local function metaFilename(careerSeed)
    return "roster_meta_" .. tostring(careerSeed) .. ".json"
end

local function loadMeta(careerSeed)
    local data = Persist.load(metaFilename(careerSeed))
    if type(data) == "table" then return data end
    return {}
end

local function saveMeta(careerSeed, meta)
    meta.lastSimTime = os.time()
    Persist.save(metaFilename(careerSeed), meta)
end

-- ── Ensure minimum population across ALL tiers ────────────────
--- Pre-generates enough drivers in every tier so the background
--- simulation and leaderboards have substance from the start.
--- Safe to call repeatedly — only creates drivers that don't exist yet.
local function ensurePopulated(career)
    local cache   = getCacheForCareer(career.seed)
    local created = 0
    for _, td in ipairs(TIER_DEFS) do
        local minCount = MIN_POP[td.name] or 10
        for i = 0, minCount - 1 do
            local id = td.name:lower():sub(1, 4) .. "_" .. string.format("%03d", i)
            if not cache[id] then
                cache[id] = generateDriver(career.seed, td.name, i)
                created = created + 1
            end
        end
    end
    if created > 0 then
        print(string.format("[NCM/Roster] Pre-populated %d drivers across all tiers.", created))
    end
end

-- ── History seeding: give every tier a backstory on first load ─
--- Runs a large batch of simulated ghost races so drivers start with
--- realistic variance in wins, rep, and tier movement rather than
--- everyone sitting at 0/0 on a fresh career.
--- Only runs once per career (gated by meta.historySeeded).
local function seedHistory(career)
    -- Batch count: enough to create ~3-8 wins for top drivers in lower tiers,
    -- and some organic promotions from Gonk → Streetkid.
    local SEED_RACES = 200

    local cache = getCacheForCareer(career.seed)
    local TIER_ORDER = { "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }
    -- Distribute seed races across tiers (heavier in lower tiers where population is bigger)
    local tierShare = { Gonk=0.35, Streetkid=0.25, Solo=0.20, Fixer=0.12, Edgerunner=0.08 }

    local totalSimmed = 0
    for _, tierName in ipairs(TIER_ORDER) do
        local pool = {}
        for _, driver in pairs(cache) do
            if driver.currentTier == tierName then
                table.insert(pool, driver)
            end
        end
        local tierRaces = math.max(1, math.floor(SEED_RACES * (tierShare[tierName] or 0.1)))
        if #pool >= 2 then
            for _ = 1, tierRaces do
                local maxField = math.min(8, #pool)
                local minField = math.min(4, maxField)
                local fieldSize = (minField < maxField) and math.random(minField, maxField) or maxField
                shuffleArray(pool)
                local racers = {}
                for i = 1, fieldSize do
                    local d = pool[i]
                    local spread = (1.0 - (d.consistency or 0.5)) * 0.12
                    local t = (100.0 / (d.pace or 1.0)) + (math.random() * 2 - 1) * spread * 100
                    table.insert(racers, { driver = d, time = t })
                end
                table.sort(racers, function(a, b) return a.time < b.time end)
                for place, r in ipairs(racers) do
                    r.driver.racesRun = r.driver.racesRun + 1
                    r.driver.rep      = r.driver.rep + (REP_BY_POS[place] or 5)
                    if place == 1 then r.driver.wins = r.driver.wins + 1 end
                    pushRecentFinish(r.driver, place)
                    updateDriverMomentum(r.driver)
                end
                totalSimmed = totalSimmed + 1
            end
        end
    end

    -- Process promotions/demotions from the seeded history
    local promotions, demotions = 0, 0
    for _, driver in pairs(cache) do
        local movement = applyTierPressureToDriver(career, driver)
        if movement == "promoted" then
            promotions = promotions + 1
        elseif movement == "demoted" then
            demotions = demotions + 1
        end
    end
    promotions = promotions + enforceTopTierCap(career)
    runLifecycleSweep(career, 2)

    print(string.format("[NCM/Roster] History seeded: %d races, +%d promos, -%d demotions.",
        totalSimmed, promotions, demotions))
end

-- ── Catch-up simulation: account for real time between sessions ─
--- When the player returns after being away, simulate proportional
--- background races so the leaderboard has drifted realistically.
--- Rate: ~1 race per 4 minutes of real elapsed time, capped at 100 races.
local function catchUpSimulation(career, meta)
    local lastTime = tonumber(meta.lastSimTime) or 0
    if lastTime <= 0 then return end  -- no previous timestamp; seedHistory handles first load

    local elapsed = os.time() - lastTime
    if elapsed < 300 then return end  -- less than 5 minutes away, skip

    -- 1 race per 240 seconds (4 min), capped at 100 to prevent huge stalls
    local racesToSim = math.min(100, math.floor(elapsed / 240))
    if racesToSim <= 0 then return end

    print(string.format("[NCM/Roster] Catch-up: %d seconds away → simulating %d races.",
        elapsed, racesToSim))
    Roster.simulate(career, racesToSim)
end

--- Initialise: nothing to do globally; called per career when activated.
function Roster.init()
    print("[NCM/Roster] Initialised.")
end

function Roster.tierNames()
    local out = {}
    for _, td in ipairs(TIER_DEFS) do
        out[#out + 1] = td.name
    end
    return out
end

function Roster.tierIndex(tier)
    local index = tierOrdinal(tier)
    return index
end

function Roster.normalizeTierRange(minTier, maxTier, fallbackTier)
    local fallback = TIER_INDEX[fallbackTier] and fallbackTier or TIER_DEFS[1].name
    local minIndex, minDef = tierOrdinal(minTier)
    if not minIndex then
        minIndex, minDef = tierOrdinal(fallback)
    end
    local maxIndex, maxDef = tierOrdinal(maxTier)
    if not maxIndex then
        maxIndex, maxDef = minIndex, minDef
    end
    if minIndex > maxIndex then
        minIndex, maxIndex = maxIndex, minIndex
        minDef, maxDef = maxDef, minDef
    end
    return minDef.name, maxDef.name
end

function Roster.tiersInRange(minTier, maxTier, fallbackTier)
    local startTier, finishTier = Roster.normalizeTierRange(minTier, maxTier, fallbackTier)
    local startIndex = Roster.tierIndex(startTier)
    local finishIndex = Roster.tierIndex(finishTier)
    local out = {}
    for i = startIndex, finishIndex do
        out[#out + 1] = TIER_DEFS[i].name
    end
    return out
end

--- Load cached roster for a career from disk.
--- Runs a safe migration pass so existing careers gain vehiclePrestige
--- without losing their existing vehicle identity.
--- Set Roster.REBALANCE_VEHICLES = true before calling to force re-roll
--- all vehicle assignments using current tier rules (developer toggle).
--- Call when a career is selected.
function Roster.loadForCareer(career)
    local k    = cacheKey(career.seed)
    local data = Persist.load(cacheFilename(career.seed))
    if type(data) == "table" then
        _cache[k] = data

        -- ── Vehicle metadata migration ────────────────────────
        -- Safe mode (default): preserves existing vehicleSignature.
        --   Infers vehiclePrestige from catalog if missing.
        -- Rebalance mode: re-derives carClass and vehicleSignature from
        --   tier-aware weighted selection (requires Roster.REBALANCE_VEHICLES = true).
        local migrated = 0
        local rebalanced = 0
        local npcMigrated = 0
        local lifecycleMigrated = 0
        local namesRebalanced = 0
        for _, driver in pairs(_cache[k]) do
            if Roster.REBALANCE_VEHICLES then
                -- Rebalance: recompute class + vehicle using live currentTier.
                -- refreshVehicleForTier prioritises currentTier over the original
                -- generation tier, and passes the driver so elite floor bumping fires.
                refreshVehicleForTier(driver, career.seed)
                rebalanced = rebalanced + 1
            elseif not driver.vehiclePrestige then
                -- Safe mode: infer prestige from existing signature
                local meta = VehiclePool.getVehicleMeta(driver.vehicleSignature)
                if meta then
                    driver.vehiclePrestige = meta.prestige
                else
                    -- Record not in catalog (legacy or modded); default to P2
                    driver.vehiclePrestige = 2
                end
                migrated = migrated + 1
            end

            if Roster.REBALANCE_NAMES then
                if refreshNameIdentity(driver, career.seed) then
                    namesRebalanced = namesRebalanced + 1
                end
            elseif type(driver.name) ~= "string" or driver.name == "" then
                if refreshNameIdentity(driver, career.seed) then
                    namesRebalanced = namesRebalanced + 1
                end
            end

            -- Ensure recentFinishes exists (added this session)
            if not driver.recentFinishes then
                driver.recentFinishes = {}
            end
            if ensureLifecycleFields(driver) then
                lifecycleMigrated = lifecycleMigrated + 1
            end

            -- Faction identity migration: assign deterministically if missing
            if not driver.factionId then
                local ftd     = TIER_INDEX[driver.currentTier or driver.tier or "Gonk"]
                local fidxStr = driver.id:match("_(%d+)$")
                local fIdx    = tonumber(fidxStr) or 0
                if ftd then
                    local fGlobalIdx = ftd.offset + fIdx
                    local fSeed      = driverSeed(career.seed, fGlobalIdx)
                    local fVals      = seededFloats(fSeed, 16)
                    local fac        = Factions.pickForDriver(fVals[15], driver.currentTier or driver.tier)
                    driver.factionId    = fac.id
                    driver.factionName  = fac.name
                    driver.factionColor = fac.color
                else
                    local fb = Factions.assignable()[1] or {}
                    driver.factionId    = fb.id    or "afterlife_speedworks"
                    driver.factionName  = fb.name  or "Afterlife Speedworks"
                    driver.factionColor = fb.color or { 0.75, 0.65, 0.20 }
                end
            end

            if VehiclePool.npcNeedsMigration(driver.npcRecord) then
                refreshNPCIdentity(driver, career.seed)
                npcMigrated = npcMigrated + 1
            end
        end

        local count = 0
        for _ in pairs(data) do count = count + 1 end
        local summary = {}
        if rebalanced > 0 then
            summary[#summary + 1] = string.format("rebalanced vehicles=%d", rebalanced)
        end
        if migrated > 0 then
            summary[#summary + 1] = string.format("migrated vehicle metadata=%d", migrated)
        end
        if npcMigrated > 0 then
            summary[#summary + 1] = string.format("migrated npc identities=%d", npcMigrated)
        end
        if lifecycleMigrated > 0 then
            summary[#summary + 1] = string.format("migrated lifecycle state=%d", lifecycleMigrated)
        end
        if namesRebalanced > 0 then
            summary[#summary + 1] = string.format("rebalanced names=%d", namesRebalanced)
        end
        if #summary > 0 then
            print(string.format("[NCM/Roster] Loaded %d drivers for '%s'. %s.",
                count, career.name, table.concat(summary, "; ")))
        else
            print(string.format("[NCM/Roster] Loaded %d cached drivers for career '%s'.", count, career.name))
        end
    else
        _cache[k] = {}
    end

    -- ── Populate, seed history, and catch up ──────────────────
    -- Ensure every tier has enough drivers for meaningful simulation.
    ensurePopulated(career)

    -- Load roster metadata (separate from driver cache).
    local meta = loadMeta(career.seed)

    -- First-time history seeding: give the ecosystem a backstory so
    -- nobody starts at 0 wins / 0 rep on a brand new career.
    if not meta.historySeeded then
        seedHistory(career)
        meta.historySeeded = true
        saveMeta(career.seed, meta)
        Roster.saveForCareer(career)
    else
        -- Returning player: simulate proportional races for elapsed time
        -- so the leaderboard has drifted while the player was away.
        catchUpSimulation(career, meta)
        saveMeta(career.seed, meta)
    end
end

--- Save cached roster for a career to disk.
--- Also updates the roster metadata timestamp so catch-up simulation
--- can measure elapsed time on next load.
function Roster.saveForCareer(career)
    local k = cacheKey(career.seed)
    if _cache[k] then
        Persist.save(cacheFilename(career.seed), _cache[k])
        -- Keep metadata timestamp fresh so catch-up sim knows when we last saved
        local meta = loadMeta(career.seed)
        saveMeta(career.seed, meta)
    end
end

--- Get or generate a specific driver. Caches on first access.
--- @param career table  career object (needs .seed)
--- @param tier   string tier name
--- @param index  number 0-based index within tier
--- @return table driver object
function Roster.get(career, tier, index)
    local td = TIER_INDEX[tier]
    if not td then return nil end
    index = math.max(0, math.min(td.size - 1, index))

    local cache  = getCacheForCareer(career.seed)
    local id     = tier:lower():sub(1,4) .. "_" .. string.format("%03d", index)

    if not cache[id] then
        cache[id] = generateDriver(career.seed, tier, index)
    end
    return cache[id]
end

--- Pick a field of drivers for a race. Returns array of driver objects.
--- For Fixer/Edgerunner tiers, biases toward high-rep, high-wins, hot-form drivers
--- so the elite fields feel earned rather than random. Lower tiers stay random.
--- Injects faction drivers from Heat module if district heat is high.
--- @param career    table   active career
--- @param count     number  total AI drivers to pick
--- @param district  string  race district (for heat injection)
--- @return table[]  array of driver objects
function Roster.pickForRace(career, count, district)
    local td    = TIER_INDEX[career.tier]
    if not td then return {} end

    local cache = getCacheForCareer(career.seed)

    -- Collect all cached drivers for this tier
    local available = {}
    for id, driver in pairs(cache) do
        if driver.currentTier == career.tier then
            table.insert(available, driver)
        end
    end

    -- If we don't have enough cached, generate more until we do
    local need = math.max(0, count - #available)
    if need > 0 then
        local generated = {}
        for i = 0, td.size - 1 do
            local id = td.name:lower():sub(1,4) .. "_" .. string.format("%03d", i)
            if not cache[id] then
                table.insert(generated, i)
            end
        end
        for i = #generated, 2, -1 do
            local j = math.random(i)
            generated[i], generated[j] = generated[j], generated[i]
        end
        for i = 1, math.min(need, #generated) do
            local driver = Roster.get(career, career.tier, generated[i])
            table.insert(available, driver)
        end
    end

    -- ── Tier-weighted selection ───────────────────────────────
    -- Fixer and Edgerunner: rank the pool by a composite score so the
    -- strongest, most consistent recent performers dominate the field.
    -- A small "wildcard" slot stays random for churn and surprise.
    -- Lower tiers stay fully random (matches the chaotic feel of Gonk/Streetkid).
    local curationFrac  = CURATED_TIERS[career.tier]

    local field = {}

    if curationFrac and #available > count then
        -- Score each driver: rep (normalised) + wins bonus + recent-form bonus
        local maxRep = 1
        for _, d in ipairs(available) do
            if (d.rep or 0) > maxRep then maxRep = d.rep end
        end

        local scored = {}
        for _, d in ipairs(available) do
            -- Recent-form: average finish position from last 5 races, lower = better
            local formScore = 0
            if d.recentFinishes and #d.recentFinishes > 0 then
                local sum = 0
                for _, pos in ipairs(d.recentFinishes) do sum = sum + pos end
                local avgPos = sum / #d.recentFinishes
                -- Invert: pos 1 → +40, pos 10 → 0, pos 99 (DNF) → -20
                formScore = math.max(-20, 40 - (avgPos - 1) * (60 / 9))
            end
            local score = (d.rep or 0) / maxRep * 50
                        + (d.wins or 0) * 5
                        + (d.rivalScore or 0) * 0.5
                        + formScore
            table.insert(scored, { driver = d, score = score })
        end
        table.sort(scored, function(a, b) return a.score > b.score end)

        -- Top curationFrac of the field comes from ranked elite pool
        local eliteSlots    = math.floor(count * curationFrac)
        local wildcardSlots = count - eliteSlots

        -- Elite: top-ranked drivers with a small shuffle in the top band
        -- (±5% positional swap) to keep things from being perfectly deterministic
        local elitePool = {}
        local topBand   = math.ceil(eliteSlots * 1.5)  -- take 50% more than needed
        for i = 1, math.min(topBand, #scored) do
            table.insert(elitePool, scored[i].driver)
        end
        for i = #elitePool, 2, -1 do
            local j = math.random(i)
            elitePool[i], elitePool[j] = elitePool[j], elitePool[i]
        end
        for i = 1, math.min(eliteSlots, #elitePool) do
            table.insert(field, elitePool[i])
        end

        -- Wildcard: random from remainder of pool (fresh blood / churn)
        local usedIds = {}
        for _, d in ipairs(field) do usedIds[d.id] = true end
        local wildpool = {}
        for _, s in ipairs(scored) do
            if not usedIds[s.driver.id] then
                table.insert(wildpool, s.driver)
            end
        end
        for i = #wildpool, 2, -1 do
            local j = math.random(i)
            wildpool[i], wildpool[j] = wildpool[j], wildpool[i]
        end
        for i = 1, math.min(wildcardSlots, #wildpool) do
            table.insert(field, wildpool[i])
        end
    else
        -- Gonk / Streetkid / Solo: pure random shuffle
        for i = #available, 2, -1 do
            local j = math.random(i)
            available[i], available[j] = available[j], available[i]
        end
        for i = 1, math.min(count, #available) do
            table.insert(field, available[i])
        end
    end

    -- Bias: ensure bounty target drivers are included when available
    if career.bounties and MTE.Careers then
        for driverId, bInfo in pairs(career.bounties) do
            if (bInfo.resolvedCount or 0) == 0 then
                local bDriver = cache[driverId]
                if bDriver and bDriver.currentTier == career.tier then
                    local found = false
                    for _, d in ipairs(field) do
                        if d.id == driverId then found = true; break end
                    end
                    if not found and #field < count then
                        table.insert(field, bDriver)
                    elseif not found and #field >= count then
                        for j = #field, 1, -1 do
                            if not field[j].isFaction then
                                field[j] = bDriver
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Inject faction drivers for high district heat
    if district and MTE.Heat then
        local injected = MTE.Heat.injectFactionDrivers(district, career.seed)
        for _, d in ipairs(injected) do table.insert(field, d) end
    end

    return field
end

function Roster.pickQuickRaceField(career, count, district, options)
    options = options or {}
    local minTier, maxTier = Roster.normalizeTierRange(options.minTier, options.maxTier, career and career.tier)
    local tiers = Roster.tiersInRange(minTier, maxTier, career and career.tier)
    if #tiers == 0 then return {} end

    count = math.max(0, tonumber(count) or 0)
    local quotas = {}
    local baseCount = math.floor(count / #tiers)
    local remainder = count % #tiers
    for _, tier in ipairs(tiers) do
        quotas[tier] = baseCount
    end

    local remainderOrder = {}
    for i, tier in ipairs(tiers) do
        remainderOrder[i] = tier
    end
    shuffleArray(remainderOrder)
    for i = 1, remainder do
        local tier = remainderOrder[i]
        quotas[tier] = (quotas[tier] or 0) + 1
    end

    local field = {}
    local usedIds = {}
    for _, tier in ipairs(tiers) do
        local selected = selectTierField(career, tier, quotas[tier] or 0)
        for _, driver in ipairs(selected) do
            if not usedIds[driver.id] then
                table.insert(field, driver)
                usedIds[driver.id] = true
            end
        end
    end

    if #field < count then
        local fallbackPool = {}
        for _, tier in ipairs(tiers) do
            local available = collectAvailableDriversForTier(career, tier, count)
            for _, driver in ipairs(available) do
                if not usedIds[driver.id] then
                    table.insert(fallbackPool, driver)
                end
            end
        end
        shuffleArray(fallbackPool)
        for i = 1, math.min(count - #field, #fallbackPool) do
            table.insert(field, fallbackPool[i])
            usedIds[fallbackPool[i].id] = true
        end
    end

    shuffleArray(field)
    return field
end

function Roster.findById(career, driverId)
    if not career or not driverId then
        return nil
    end

    local cache = getCacheForCareer(career.seed)
    if cache[driverId] then
        ensureLifecycleFields(cache[driverId])
        return cache[driverId]
    end

    local prefix, index = tostring(driverId):match("^(%a+)_([0-9]+)$")
    index = tonumber(index)
    if prefix and index then
        for _, tierDef in ipairs(TIER_DEFS) do
            if tierDef.name:lower():sub(1, 4) == prefix then
                return Roster.get(career, tierDef.name, index)
            end
        end
    end

    return nil
end

function Roster.listByTier(career, tier)
    if not career then
        return {}
    end

    local targetTier = tier or career.tier
    local cache = getCacheForCareer(career.seed)
    local drivers = {}
    for _, driver in pairs(cache) do
        if driver.currentTier == targetTier and driverIsAvailable(driver) then
            drivers[#drivers + 1] = driver
        end
    end

    table.sort(drivers, function(left, right)
        local leftRep = tonumber(left and left.rep or 0) or 0
        local rightRep = tonumber(right and right.rep or 0) or 0
        if leftRep == rightRep then
            return tostring(left and left.id or "") < tostring(right and right.id or "")
        end
        return leftRep > rightRep
    end)

    return drivers
end

function Roster.eachSeededDriver(career, callback, includeUncached)
    if type(career) ~= "table" or type(callback) ~= "function" then
        return 0
    end

    local cache = getCacheForCareer(career.seed)
    local total = 0
    for _, td in ipairs(TIER_DEFS) do
        for index = 0, td.size - 1 do
            local driverId = td.name:lower():sub(1, 4) .. "_" .. string.format("%03d", index)
            local driver = cache[driverId]
            if not driver and includeUncached == true then
                driver = generateDriver(career.seed, td.name, index)
            end
            if driver then
                callback(driver, td.name, index, cache[driverId] ~= nil)
                total = total + 1
            end
        end
    end
    return total
end

--- Apply race results to drivers: update wins, rep, tier changes.
--- This is the authoritative real-race path; live promotion/demotion fires here
--- so Fixer/Edgerunner fields self-curate over actual play.
--- @param career  table      career object
--- @param results table[]    sorted { name, driverId, position, time }
function Roster.applyRaceResult(career, results)
    local cache = getCacheForCareer(career.seed)

    -- Find player position in results
    local playerPos = nil
    for _, r in ipairs(results) do
        if r.isPlayer then playerPos = r.position or 999; break end
    end

    for _, r in ipairs(results) do
        local driver = r.driverId and cache[r.driverId]
        if driver then
            ensureLifecycleFields(driver)
            driver.racesRun = driver.racesRun + 1
            driver.lastRaceResult = r.position
            local repGain = REP_BY_POS[r.position] or 5
            driver.rep    = driver.rep + repGain
            if r.position == 1 then driver.wins = driver.wins + 1 end

            pushRecentFinish(driver, (r.dnf == true) and 99 or (r.position or 99))
            updateDriverMomentum(driver)

            -- Rival tracking: update head-to-head vs player
            if playerPos then
                local pos = r.position or 999
                if pos < playerPos then
                    driver.lastBeatPlayer = true
                    driver.headToHeadWins = (driver.headToHeadWins or 0) + 1
                    driver.rivalScore     = (driver.rivalScore or 0) + 10
                else
                    driver.lastBeatPlayer = false
                    driver.rivalScore = math.max(0, (driver.rivalScore or 0) - 3)
                end
            end
        end
    end
    for _, driver in pairs(cache) do
        local movement = applyTierPressureToDriver(career, driver)
        if movement == "promoted" then
            print(string.format("[NCM/Roster] %s promoted into %s.", driver.name, driver.currentTier))
        elseif movement == "demoted" then
            print(string.format("[NCM/Roster] %s dropped into %s.", driver.name, driver.currentTier))
        end
    end
    enforceTopTierCap(career)
    runLifecycleSweep(career, 1)
    Roster.saveForCareer(career)
end

--- Run a background simulation tick: simulate ghost races across the full 870-driver
--- ecosystem, not just the player's current tier. This keeps ALL tiers evolving so
--- Edgerunner drivers earned their spot through the full pipeline rather than only
--- when the player is in that tier.
--- Each tier gets count races proportionally. Tier changes are applied at the end.
--- @param career table  active career
--- @param count  number total simulated races to distribute (default 5)
function Roster.simulate(career, count)
    count = count or 5
    local cache = getCacheForCareer(career.seed)

    local TIER_ORDER = { "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }

    -- Partition cached drivers by current tier
    local poolByTier = {}
    for _, tierName in ipairs(TIER_ORDER) do poolByTier[tierName] = {} end
    for _, driver in pairs(cache) do
        local pool = poolByTier[driver.currentTier]
        if pool and driverIsAvailable(driver) then table.insert(pool, driver) end
    end

    -- Distribute races across tiers — higher tiers get fewer simulated races
    -- so churn is lower and elite spots are harder to earn.
    local tierRaceShare = { Gonk=0.35, Streetkid=0.30, Solo=0.20, Fixer=0.10, Edgerunner=0.05 }

    -- Pre-allocate races using largest-remainder (Hamilton) method so the
    -- total never exceeds count. This prevents math.max forcing ≥1 per tier
    -- when count is small and the old code ran 5+ races for a count of 3.
    local allocations    = {}
    local totalAllocated = 0
    local fractionals    = {}
    for _, tierName in ipairs(TIER_ORDER) do
        local exact = count * (tierRaceShare[tierName] or 0)
        local n     = math.floor(exact)
        allocations[tierName] = n
        totalAllocated        = totalAllocated + n
        table.insert(fractionals, { name = tierName, frac = exact - n })
    end
    table.sort(fractionals, function(a, b) return a.frac > b.frac end)
    local remainder = count - totalAllocated
    for i = 1, remainder do
        local t = fractionals[i]
        if t then allocations[t.name] = allocations[t.name] + 1 end
    end

    local totalSimmed = 0
    for _, tierName in ipairs(TIER_ORDER) do
        local pool      = poolByTier[tierName]
        local tierCount = allocations[tierName] or 0
        if #pool >= 2 and tierCount > 0 then
            for _ = 1, tierCount do
                local maxField = math.min(8, #pool)
                local minField = math.min(4, maxField)
                local fieldSize = (minField < maxField) and math.random(minField, maxField) or maxField
                for i = #pool, 2, -1 do
                    local j = math.random(i)
                    pool[i], pool[j] = pool[j], pool[i]
                end
                local racers = {}
                for i = 1, fieldSize do
                    local d = pool[i]
                    local spread = (1.0 - (d.consistency or 0.5)) * 0.12
                    local t = (100.0 / (d.pace or 1.0)) + (math.random() * 2 - 1) * spread * 100
                    table.insert(racers, { driver = d, time = t })
                end
                table.sort(racers, function(a, b) return a.time < b.time end)
                for place, r in ipairs(racers) do
                    r.driver.racesRun = r.driver.racesRun + 1
                    r.driver.rep      = r.driver.rep + (REP_BY_POS[place] or 5)
                    if place == 1 then r.driver.wins = r.driver.wins + 1 end
                    pushRecentFinish(r.driver, place)
                    updateDriverMomentum(r.driver)
                end
                totalSimmed = totalSimmed + 1
            end
        end
    end

    -- Process tier changes across ALL cached drivers (not just current tier)
    local promotions, demotions = 0, 0
    for _, driver in pairs(cache) do
        local movement = applyTierPressureToDriver(career, driver)
        if movement == "promoted" then
            promotions = promotions + 1
        elseif movement == "demoted" then
            demotions = demotions + 1
        end
    end
    promotions = promotions + enforceTopTierCap(career)
    runLifecycleSweep(career, math.max(1, math.floor(totalSimmed / 8)))

    print(string.format("[NCM/Roster] Background sim: %d races across all tiers. +%d promos, -%d demotions.",
        totalSimmed, promotions, demotions))
    Roster.saveForCareer(career)
end

--- Returns the next tier up, or nil if already at top.
function Roster.nextTier(tier)
    local order = { "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }
    for i, t in ipairs(order) do
        if t == tier and order[i+1] then return order[i+1] end
    end
    return nil
end

--- Returns the previous tier down, or nil if already at bottom.
function Roster.prevTier(tier)
    local order = { "Gonk", "Streetkid", "Solo", "Fixer", "Edgerunner" }
    for i, t in ipairs(order) do
        if t == tier and i > 1 then return order[i-1] end
    end
    return nil
end

function Roster.getLeaderboard(career, tier, maxCount)
    local cache = getCacheForCareer(career.seed)
    local td    = TIER_INDEX[tier or career.tier]
    if not td then return {} end
    if not maxCount or maxCount <= 0 then
        maxCount = td.size
    end

    -- Ensure at least maxCount drivers exist in cache
    for i = 0, math.min(td.size - 1, maxCount - 1) do
        Roster.get(career, tier or career.tier, i)
    end

    local list = {}
    for _, driver in pairs(cache) do
        if driver.currentTier == (tier or career.tier) and driverIsAvailable(driver) then
            table.insert(list, driver)
        end
    end

    table.sort(list, function(a, b)
        if a.wins ~= b.wins then return a.wins > b.wins end
        return a.rep > b.rep
    end)

    local out = {}
    for i = 1, math.min(maxCount, #list) do
        table.insert(out, list[i])
    end
    return out
end

--- Debug: print the prestige distribution for a tier to the CET console.
--- Call from CET console: MTE.Roster.debugPrestige(MTE.Careers.active(), "Edgerunner")
--- @param career table  active career
--- @param tier   string tier name (defaults to career.tier)
function Roster.debugPrestige(career, tier)
    tier = tier or career.tier
    local cache = getCacheForCareer(career.seed)
    local counts  = { [1]=0, [2]=0, [3]=0, [4]=0, [5]=0 }
    local classes = {}
    local total = 0
    for _, driver in pairs(cache) do
        if driver.currentTier == tier then
            local p = driver.vehiclePrestige or 0
            counts[p] = (counts[p] or 0) + 1
            classes[driver.carClass or "?"] = (classes[driver.carClass or "?"] or 0) + 1
            total = total + 1
        end
    end
    print(string.format("[NCM/Roster] Prestige distribution for %s (%d drivers):", tier, total))
    for p = 1, 5 do
        local n = counts[p] or 0
        local pct = total > 0 and math.floor(n / total * 100) or 0
        print(string.format("  P%d: %d (%d%%)", p, n, pct))
    end
    print("[NCM/Roster] Class breakdown:")
    for cls, n in pairs(classes) do
        local pct = total > 0 and math.floor(n / total * 100) or 0
        print(string.format("  %s: %d (%d%%)", cls, n, pct))
    end
end

return Roster
