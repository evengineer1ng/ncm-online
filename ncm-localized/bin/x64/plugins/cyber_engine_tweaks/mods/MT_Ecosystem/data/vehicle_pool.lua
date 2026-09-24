-- ============================================================
-- MT_Ecosystem: data/vehicle_pool.lua
-- TweakDB vehicle records with prestige metadata and tier-aware
-- weighted selection so league grids feel visually appropriate.
--
-- Prestige scale:
--   1  beater / entry / low-status
--   2  ordinary street car
--   3  respectable performance hardware
--   4  premium / aspirational
--   5  halo / legendary / ultra-rare
-- ============================================================

local VehiclePool = {}

-- ── Ordered class list (iteration order must be deterministic) ─
local CLASS_ORDER = { "Muscle", "Sport", "Tech", "Nomad", "Bike" }

-- ── Structured vehicle catalog ────────────────────────────────
-- Every entry: { id = <TweakDB record>, prestige = 1-5, tags = {...} }
-- Tags are metadata only — used for future filtering and UI badges.
VehiclePool.RECORDS = {
    Muscle = {
        { id = "Vehicle.v_standard2_thorton_galena",        prestige = 1, tags = { "budget", "starter"         } },
        { id = "Vehicle.v_standard25_thorton_colby_pickup", prestige = 1, tags = { "budget", "utility"         } },
        { id = "Vehicle.v_standard2_thorton_colby",         prestige = 2, tags = { "street", "muscle"          } },
        { id = "Vehicle.v_standard25_villefort_columbus",   prestige = 2, tags = { "street", "utility"         } },
        { id = "Vehicle.v_sport2_quadra_type66",            prestige = 3, tags = { "muscle", "classic"         } },
        { id = "Vehicle.v_sport2_villefort_alvarado",       prestige = 4, tags = { "muscle", "luxury"          } },
        { id = "Vehicle.v_sport2_villefort_deleon",         prestige = 4, tags = { "muscle", "race", "iconic"  } },
    },
    Sport = {
        { id = "Vehicle.v_sport1_herrera_outlaw",           prestige = 2, tags = { "street", "sport"           } },
        { id = "Vehicle.v_sport2_mizutani_shion",           prestige = 3, tags = { "sport", "tech"             } },
        { id = "Vehicle.v_sport1_quadra_turbo",             prestige = 4, tags = { "sport", "race"             } },
        { id = "Vehicle.v_sport1_rayfield_caliburn",        prestige = 5, tags = { "halo", "race", "sport"     } },
        { id = "Vehicle.v_sport1_rayfield_aerondight",      prestige = 5, tags = { "halo", "iconic", "sport"   } },
    },
    Tech = {
        { id = "Vehicle.v_standard2_makigai_maimai",        prestige = 1, tags = { "budget", "tech"            } },
        { id = "Vehicle.v_standard2_archer_hella",          prestige = 2, tags = { "street", "tech"            } },
        { id = "Vehicle.v_standard25_mahir_supron",         prestige = 2, tags = { "street", "tech"            } },
        { id = "Vehicle.v_standard2_villefort_cortes",      prestige = 2, tags = { "street", "tech"            } },
        { id = "Vehicle.v_standard3_chevalier_emperor",     prestige = 3, tags = { "executive", "tech"         } },
        { id = "Vehicle.v_standard2_chevalier_thrax",       prestige = 4, tags = { "executive", "tech", "race" } },
    },
    Nomad = {
        { id = "Vehicle.v_standard25_thorton_colby_pickup", prestige = 1, tags = { "budget", "offroad"         } },
        { id = "Vehicle.v_standard25_villefort_columbus",   prestige = 2, tags = { "street", "utility"         } },
        { id = "Vehicle.v_standard3_thorton_mackinaw",      prestige = 2, tags = { "offroad", "nomad"          } },
        { id = "Vehicle.v_sport2_quadra_type66_nomad",      prestige = 3, tags = { "offroad", "iconic"         } },
        { id = "Vehicle.v_sport2_mizutani_shion_nomad",     prestige = 4, tags = { "offroad", "premium", "halo"} },
    },
    Bike = {
        { id = "Vehicle.v_sportbike3_brennan_apollo",               prestige = 1, tags = { "bike", "motorcycle", "street", "apollo"   } },
        { id = "Vehicle.v_sportbike3_brennan_apollo_sport",         prestige = 2, tags = { "bike", "motorcycle", "sport", "apollo"    } },
        { id = "Vehicle.v_sportbike3_brennan_apollo_nomad",         prestige = 4, tags = { "bike", "motorcycle", "nomad", "apollo"    } },
        { id = "Vehicle.v_sportbike1_yaiba_kusanagi_tyger",         prestige = 4, tags = { "bike", "motorcycle", "race", "kusanagi"  } },
        { id = "Vehicle.v_sportbike1_yaiba_kusanagi_animal",        prestige = 4, tags = { "bike", "motorcycle", "race", "yaiba"     } },
    },
}

-- ── Tier-based class weight tables ────────────────────────────
-- Higher numbers = more likely to appear. Must sum to 100 each row.
-- Gonk: rough, mixed hardware. Edgerunner: mostly premium Sport.
VehiclePool.TIER_CLASS_WEIGHTS = {
    Gonk       = { Muscle = 35, Tech = 35, Nomad = 20, Sport = 10, Bike = 0 },
    Streetkid  = { Muscle = 30, Tech = 25, Nomad = 20, Sport = 25, Bike = 0 },
    Solo       = { Muscle = 30, Tech = 15, Nomad = 15, Sport = 40, Bike = 0 },
    Fixer      = { Muscle = 20, Tech = 10, Nomad = 10, Sport = 60, Bike = 0 },
    Edgerunner = { Muscle = 15, Tech =  5, Nomad = 10, Sport = 70, Bike = 0 },
}

-- ── Tier-based prestige weight tables ─────────────────────────
-- Applied within the chosen class. Controls how "high-end" the
-- selected car is. Edgerunner grids skew heavily toward P4-P5.
VehiclePool.TIER_PRESTIGE_WEIGHTS = {
    Gonk       = { [1] = 50, [2] = 30, [3] = 15, [4] =  5, [5] =  0 },
    Streetkid  = { [1] = 25, [2] = 35, [3] = 25, [4] = 12, [5] =  3 },
    Solo       = { [1] = 10, [2] = 25, [3] = 35, [4] = 20, [5] = 10 },
    Fixer      = { [1] =  0, [2] = 10, [3] = 30, [4] = 35, [5] = 25 },
    Edgerunner = { [1] =  0, [2] =  5, [3] = 15, [4] = 40, [5] = 40 },
}

-- ── Elite prestige floors ─────────────────────────────────────
-- Drivers in these tiers will never spawn in a car below this floor.
-- If the chosen class has no entries at or above the floor, the system
-- falls back to the highest prestige available in that class.
VehiclePool.PRESTIGE_FLOOR = {
    Gonk = 1, Streetkid = 1, Solo = 1, Fixer = 3, Edgerunner = 4,
}

-- ── NPC driver profiles ───────────────────────────────────────
-- Stored as stable profile IDs. Each profile points at a compatible
-- Character.* spawn record first, with an entity template fallback so
-- cached careers can be migrated in place without breaking old data.
VehiclePool.NPC_RECORDS = {
    { id = "npc_citizen_default_ma",    legacyRecord = "Character.intrasys_citizen_01",    record = "Character.LowlifeMaleDriver",                     entPath = "base\\characters\\entities\\citizen\\citizen__default_ma.ent",     archetype = "citizen" },
    { id = "npc_citizen_default_wa",    legacyRecord = "Character.intrasys_citizen_02",    record = "Character.LowlifeWomanDriver",                    entPath = "base\\characters\\entities\\citizen\\citizen__default_wa.ent",     archetype = "citizen" },
    { id = "npc_citizen_nightlife_ma",  record = "Character.NightlifeMaleDriver",                           entPath = "base\\characters\\entities\\citizen\\citizen__nightlife_ma.ent",   archetype = "nightlife" },
    { id = "npc_citizen_nightlife_mb",  record = "Character.NightlifeMaleDriver",                           entPath = "base\\characters\\entities\\citizen\\citizen__nightlife_mb.ent",   archetype = "nightlife" },
    { id = "npc_citizen_nightlife_wa",  record = "Character.NightlifeFemaleDriver",                         entPath = "base\\characters\\entities\\citizen\\citizen__nightlife_wa.ent",   archetype = "nightlife" },
    { id = "npc_citizen_biker_ma",      record = "Character.LowlifeMaleRedneckDriver",             entPath = "base\\characters\\entities\\citizen\\citizen__biker_ma.ent",       archetype = "biker" },
    { id = "npc_citizen_biker_wa",      record = "Character.LowlifeWomanRedneckDriver",            entPath = "base\\characters\\entities\\citizen\\citizen__biker_wa.ent",       archetype = "biker" },
    { id = "npc_citizen_rich_ma",       record = "Character.CitizenRichMaleDriver",                  entPath = "base\\characters\\entities\\citizen\\citizen__rich_ma.ent",        archetype = "rich" },
    { id = "npc_citizen_rich_wa",       record = "Character.CitizenRichFemaleDriver",                entPath = "base\\characters\\entities\\citizen\\citizen__rich_wa.ent",        archetype = "rich" },
    { id = "npc_aldecaldo_ma",          record = "Character.adelcaldos_grunt2_ranged2_copperhead_ma", entPath = "base\\characters\\entities\\citizen\\citizen__aldecaldos_ma.ent",  archetype = "aldecaldo" },
    { id = "npc_aldecaldo_mb",          record = "Character.adelcaldos_grunt2_ranged2_sidewinder_ma", entPath = "base\\characters\\entities\\citizen\\citizen__aldecaldos_mb.ent",  archetype = "aldecaldo" },
    { id = "npc_aldecaldo_wa",          record = "Character.adelcaldos_grunt1_ranged1_pulsar_ma",    entPath = "base\\characters\\entities\\citizen\\citizen__aldecaldos_wa.ent",  archetype = "aldecaldo" },
    { id = "npc_corpo_arasaka_ma",      legacyRecord = "Character.intrasys_corpo_01",      record = "Character.CorpoManArasakaDriver",                entPath = "base\\characters\\entities\\corpo\\corpo__arasaka_ma.ent",      archetype = "corpo" },
    { id = "npc_corpo_arasaka_wa",      legacyRecord = "Character.intrasys_corpo_02",      record = "Character.CorpoWomanArasakaDriver",              entPath = "base\\characters\\entities\\corpo\\corpo__arasaka_wa.ent",      archetype = "corpo" },
    { id = "npc_corpo_arasaka_mb",      record = "Character.CorpoManArasakaDriver",                  entPath = "base\\characters\\entities\\corpo\\corpo__arasaka_mb.ent",      archetype = "corpo" },
    { id = "npc_corpo_militech_ma",     record = "Character.CorpoManCorporatDriver",                entPath = "base\\characters\\entities\\corpo\\corpo__militech_ma.ent",     archetype = "corpo" },
    { id = "npc_corpo_militech_mb",     record = "Character.CorpoManCorporatDriver",                entPath = "base\\characters\\entities\\corpo\\corpo__militech_mb.ent",     archetype = "corpo" },
    { id = "npc_corpo_militech_wa",     record = "Character.CorpoWomanCorporatDriver",              entPath = "base\\characters\\entities\\corpo\\corpo__militech_wa.ent",     archetype = "corpo" },
    { id = "npc_corpo_generic_ma",      record = "Character.CorpoManCorporatDriver",                entPath = "base\\characters\\entities\\corpo\\corpo__generic_ma.ent",      archetype = "corpo" },
    { id = "npc_corpo_generic_mb",      record = "Character.CorpoManCorporatDriver",                entPath = "base\\characters\\entities\\corpo\\corpo_generic_mb.ent",       archetype = "corpo" },
    { id = "npc_corpo_generic_wa",      record = "Character.CorpoWomanCorporatDriver",              entPath = "base\\characters\\entities\\corpo\\corpo__generic_wa.ent",      archetype = "corpo" },
    { id = "npc_6thstreet_ma",          legacyRecord = "Character.intrasys_6thstreet_01",  record = "Character.sixthstreet_hooligan_ranged1_nova_ma", entPath = "base\\characters\\entities\\gang\\gang__6thstreet_ma.ent",       archetype = "gang" },
    { id = "npc_6thstreet_wa",          legacyRecord = "Character.intrasys_6thstreet_02",  record = "Character.sixthstreet_hooligan_ranged1_nova_wa", entPath = "base\\characters\\entities\\gang\\gang__6thstreet_wa.ent",       archetype = "gang" },
    { id = "npc_animals_mb",            legacyRecord = "Character.intrasys_animals_01",    entPath = "base\\characters\\entities\\gang\\gang__animals_mb.ent",         archetype = "gang" },
    { id = "npc_animals_wba",           legacyRecord = "Character.intrasys_animals_02",    entPath = "base\\characters\\entities\\gang\\gang__animals_wba.ent",        archetype = "gang" },
    { id = "npc_maelstrom_ma",          legacyRecord = "Character.intrasys_maelstrom_01",  record = "Character.maelstrom_grunt1_ranged1_lexington_ma", entPath = "base\\characters\\entities\\gang\\gang__maelstrom_ma.ent",       archetype = "gang" },
    { id = "npc_maelstrom_wa",          legacyRecord = "Character.intrasys_maelstrom_02",  record = "Character.maelstrom_grunt1_ranged1_lexington_wa", entPath = "base\\characters\\entities\\gang\\gang__maelstrom_wa.ent",       archetype = "gang" },
    { id = "npc_maelstrom_mb",          record = "Character.maelstrom_fast_franged2_pulsar_ma_rare", entPath = "base\\characters\\entities\\gang\\gang__maelstrom_mb.ent",       archetype = "gang" },
    { id = "npc_tyger_ma",              legacyRecord = "Character.intrasys_tyger_claws_01", record = "Character.tyger_claws_biker1_ranged1_nue_ma", entPath = "base\\characters\\entities\\gang\\gang__tyger_ma.ent",           archetype = "gang" },
    { id = "npc_tyger_wa",              legacyRecord = "Character.intrasys_tyger_claws_02", record = "Character.tyger_claws_biker1_ranged1_nue_wa", entPath = "base\\characters\\entities\\gang\\gang__tyger_wa.ent",           archetype = "gang" },
    { id = "npc_tyger_mb",              record = "Character.tyger_claws_biker2_ranged2_shingen_ma", entPath = "base\\characters\\entities\\gang\\gang__tyger_mb.ent",           archetype = "gang" },
    { id = "npc_valentinos_ma",         legacyRecord = "Character.intrasys_valentinos_01",  record = "Character.valentinos_grunt1_ranged1_nova_ma", entPath = "base\\characters\\entities\\gang\\gang__valentinos_ma.ent",      archetype = "gang" },
    { id = "npc_valentinos_wa",         legacyRecord = "Character.intrasys_valentinos_02",  record = "Character.valentinos_grunt1_ranged1_nue_wa", entPath = "base\\characters\\entities\\gang\\gang__valentinos_wa.ent",      archetype = "gang" },
    { id = "npc_valentinos_mb",         record = "Character.valentinos_grunt2_ranged2_ajax_ma", entPath = "base\\characters\\entities\\gang\\gang__valentinos_mb.ent",      archetype = "gang" },
    { id = "npc_wraith_ma",             legacyRecord = "Character.intrasys_wraith_01",      record = "Character.wraiths_ghost2_sniper2_achilles_ma_rare", entPath = "base\\characters\\entities\\gang\\gang__wraith_ma.ent",          archetype = "gang" },
    { id = "npc_wraith_wa",             legacyRecord = "Character.intrasys_wraith_02",      record = "Character.wraiths_grunt2_ranged2_copperhead_wa", entPath = "base\\characters\\entities\\gang\\gang__wraith_wa.ent",          archetype = "gang" },
    { id = "npc_wraith_mb",             record = "Character.wraiths_strong_gunner3_hmg_mb_elite", entPath = "base\\characters\\entities\\gang\\gang__wraith_mb.ent",          archetype = "gang" },
}

local NPC_FACTION_POOLS = {
    independent = {
        "npc_citizen_default_ma",
        "npc_citizen_default_wa",
        "npc_citizen_biker_ma",
        "npc_citizen_rich_wa",
    },
    afterlife_speedworks = {
        "npc_citizen_nightlife_ma",
        "npc_citizen_nightlife_mb",
        "npc_citizen_rich_ma",
        "npc_citizen_rich_wa",
    },
    aldecaldo_racing = {
        "npc_aldecaldo_ma",
        "npc_aldecaldo_mb",
        "npc_aldecaldo_wa",
    },
    tyger_claws_gp = {
        "npc_tyger_ma",
        "npc_tyger_mb",
        "npc_tyger_wa",
    },
    ["6th_street_motorsports"] = {
        "npc_6thstreet_ma",
        "npc_6thstreet_wa",
    },
    valentinos_racing_club = {
        "npc_valentinos_ma",
        "npc_valentinos_mb",
        "npc_valentinos_wa",
    },
    wraith_performance = {
        "npc_wraith_ma",
        "npc_wraith_mb",
        "npc_wraith_wa",
    },
    arasaka_advanced_motorsport = {
        "npc_corpo_arasaka_ma",
        "npc_corpo_arasaka_mb",
        "npc_corpo_arasaka_wa",
    },
    militech_track_division = {
        "npc_corpo_militech_ma",
        "npc_corpo_militech_mb",
        "npc_corpo_militech_wa",
    },
    night_corp_velocity = {
        "npc_corpo_generic_ma",
        "npc_corpo_generic_mb",
        "npc_corpo_generic_wa",
    },
    mox_motor_club = {
        "npc_citizen_nightlife_wa",
        "npc_citizen_nightlife_ma",
        "npc_citizen_biker_wa",
    },
}

local DEFAULT_NPC_POOL = NPC_FACTION_POOLS.independent

local NPC_PROFILES_BY_ID = {}
local NPC_PROFILES_BY_LEGACY = {}
for _, profile in ipairs(VehiclePool.NPC_RECORDS) do
    NPC_PROFILES_BY_ID[profile.id] = profile
    if profile.legacyRecord then
        NPC_PROFILES_BY_LEGACY[profile.legacyRecord] = profile
    end
end

local VEHICLE_META_BY_ID = {}
for carClass, pool in pairs(VehiclePool.RECORDS) do
    for _, entry in ipairs(pool) do
        VEHICLE_META_BY_ID[entry.id] = {
            id = entry.id,
            prestige = entry.prestige,
            tags = entry.tags,
            carClass = carClass,
        }
    end
end

local QUICK_RACE_PRESTIGE_WEIGHTS = {
    mostly_low = { [1] = 12, [2] = 7, [3] = 3, [4] = 1, [5] = 1 },
    mixed = { [1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 1 },
    mostly_high = { [1] = 1, [2] = 1, [3] = 3, [4] = 7, [5] = 12 },
}

-- Stable spawnable entity templates for the curated race pool.
-- Some TweakDB vehicle records are appearance variants that still share a
-- common base vehicle entity, so a few mappings intentionally point at the
-- nearest spawn-safe parent template.
local VEHICLE_ENTITY_TEMPLATES = {
    ["Vehicle.v_standard2_thorton_galena"] = "base\\vehicles\\standard\\v_standard2_thorton_galena_01__basic_01.ent",
    ["Vehicle.v_standard25_thorton_colby_pickup"] = "base\\vehicles\\standard\\v_standard25_thorton_colby_pickup__basic_01.ent",
    ["Vehicle.v_standard2_thorton_colby"] = "base\\vehicles\\standard\\v_standard2_thorton_colby__basic_01.ent",
    ["Vehicle.v_standard25_villefort_columbus"] = "base\\vehicles\\standard\\v_standard25_villefort_columbus_01__basic_01.ent",
    ["Vehicle.v_sport2_quadra_type66"] = "base\\vehicles\\sport\\v_sport2_quadra_type66__basic_01.ent",
    ["Vehicle.v_sport2_villefort_alvarado"] = "base\\vehicles\\sport\\v_sport2_villefort_alvarado__basic_01.ent",
    ["Vehicle.v_sport2_villefort_deleon"] = "base\\vehicles\\sport\\v_sport2_villefort_deleon_01.ent",
    ["Vehicle.v_sport1_herrera_outlaw"] = "base\\vehicles\\sport\\v_sport1_herrera_outlaw_basic_01.ent",
    ["Vehicle.v_sport2_mizutani_shion"] = "base\\vehicles\\sport\\v_sport2_mizutani_shion__basic_01.ent",
    ["Vehicle.v_sport1_quadra_turbo"] = "base\\vehicles\\sport\\v_sport1_quadra_turbo__basic_01.ent",
    ["Vehicle.v_sport1_rayfield_caliburn"] = "base\\vehicles\\sport\\v_sport1_rayfield_caliburn__basic_01.ent",
    ["Vehicle.v_sport1_rayfield_aerondight"] = "base\\vehicles\\sport\\v_sport1_rayfield_aerondight__basic_01.ent",
    ["Vehicle.v_standard2_makigai_maimai"] = "base\\vehicles\\standard\\v_standard2_makigai_maimai_01_basic_01.ent",
    ["Vehicle.v_standard2_archer_hella"] = "base\\vehicles\\standard\\v_standard2_archer_hella__basic_01.ent",
    ["Vehicle.v_standard25_mahir_supron"] = "base\\vehicles\\standard\\v_standard25_mahir_supron_01__basic_01.ent",
    ["Vehicle.v_standard2_villefort_cortes"] = "base\\vehicles\\standard\\v_standard2_villefort_cortes_01__basic_01.ent",
    ["Vehicle.v_standard3_chevalier_emperor"] = "base\\vehicles\\standard\\v_standard3_chevalier_emperor_01__basic_01.ent",
    ["Vehicle.v_standard2_chevalier_thrax"] = "base\\vehicles\\standard\\v_standard2_chevalier_thrax__basic_01.ent",
    ["Vehicle.v_standard3_thorton_mackinaw"] = "base\\vehicles\\standard\\v_standard3_thorton_mackinaw_01__basic_01.ent",
    ["Vehicle.v_sport2_quadra_type66_nomad"] = "base\\vehicles\\sport\\v_sport2_quadra_type66_nomad__basic_01.ent",
    ["Vehicle.v_sport2_mizutani_shion_nomad"] = "base\\vehicles\\sport\\v_sport2_mizutani_shion_nomad__basic_01.ent",
    -- Bike entries: use real TweakDB vehicle record IDs so DynamicEntitySystem
    -- can resolve them directly without crashing on invalid record lookups.
    ["Vehicle.v_sportbike3_brennan_apollo"]          = "base\\vehicles\\sportbike\\v_sportbike3_brennan_apollo_basic_01.ent",
    ["Vehicle.v_sportbike3_brennan_apollo_sport"]    = "base\\vehicles\\sportbike\\v_sportbike3_brennan_apollo_basic_01.ent",
    ["Vehicle.v_sportbike3_brennan_apollo_nomad"]    = "base\\vehicles\\sportbike\\v_sportbike3_brennan_apollo_basic_01.ent",
    ["Vehicle.v_sportbike1_yaiba_kusanagi_tyger"]    = "base\\vehicles\\sportbike\\v_sportbike1_yaiba_kusanagi_basic_01.ent",
    ["Vehicle.v_sportbike1_yaiba_kusanagi_animal"]   = "base\\vehicles\\sportbike\\v_sportbike1_yaiba_kusanagi_basic_01.ent",
}

-- ── Internal helpers ──────────────────────────────────────────

--- Deterministic weighted pick from a keyed table, iterated in CLASS_ORDER order.
--- @param weights   table   { ClassName = weight, ... }
--- @param seedValue number  0-1 float
--- @return string class name
local function weightedPickClass(weights, seedValue)
    local total = 0
    for _, cls in ipairs(CLASS_ORDER) do
        total = total + (weights[cls] or 0)
    end
    if total == 0 then return CLASS_ORDER[1] end
    local target = seedValue * total
    local acc = 0
    for _, cls in ipairs(CLASS_ORDER) do
        acc = acc + (weights[cls] or 0)
        if acc >= target then return cls end
    end
    return CLASS_ORDER[#CLASS_ORDER]
end

--- Build a weighted list of vehicle entries eligible for a tier+class.
--- Applies prestige floor; falls back to highest-prestige entries if floor
--- eliminates everything (e.g. Edgerunner driver in Muscle class).
--- @param tier      string  "Gonk" etc.
--- @param carClass  string  "Muscle" etc.
--- @param driver    table   optional, used for elite floor bumping
--- @return table[]  { entry, w } pairs; never empty if pool is non-empty
local function buildCandidates(tier, carClass, driver)
    local pool      = VehiclePool.RECORDS[carClass] or VehiclePool.RECORDS.Muscle
    local pWeights  = VehiclePool.TIER_PRESTIGE_WEIGHTS[tier] or VehiclePool.TIER_PRESTIGE_WEIGHTS.Gonk
    local floor     = VehiclePool.PRESTIGE_FLOOR[tier] or 1

    -- Elite floor bump for recognizable killers
    if driver then
        if (driver.wins or 0) >= 15 or (driver.rivalScore or 0) >= 50 then
            floor = math.min(5, floor + 1)
        end
    end

    -- Primary pass: entries at or above floor with nonzero weight
    local candidates = {}
    local total = 0
    for _, entry in ipairs(pool) do
        if entry.prestige >= floor then
            local w = pWeights[entry.prestige] or 0
            if w > 0 then
                table.insert(candidates, { entry = entry, w = w })
                total = total + w
            end
        end
    end

    -- User overrides: prepend entries from vehiclePoolOverrides for this tier
    local userOverrides = VehiclePool.getUserOverrides and VehiclePool.getUserOverrides(tier)
    if type(userOverrides) == "table" then
        for _, uEntry in ipairs(userOverrides) do
            if type(uEntry) == "table" and type(uEntry.id) == "string" then
                local p = tonumber(uEntry.prestige) or floor
                local w = math.max(1, pWeights[p] or 1)
                local synth = { id = uEntry.id, prestige = p, tags = uEntry.tags or { "user_override" } }
                table.insert(candidates, 1, { entry = synth, w = w })
                total = total + w
            end
        end
    end

    -- Fallback: floor too high for this class → use highest prestige available
    if #candidates == 0 then
        local bestP = 0
        for _, entry in ipairs(pool) do
            if entry.prestige > bestP then bestP = entry.prestige end
        end
        for _, entry in ipairs(pool) do
            if entry.prestige == bestP then
                local w = math.max(1, pWeights[entry.prestige] or 1)
                table.insert(candidates, { entry = entry, w = w })
                total = total + w
            end
        end
    end

    return candidates, total
end

local function getNPCPoolIds(factionId)
    local pool = factionId and NPC_FACTION_POOLS[factionId] or nil
    if type(pool) == "table" and #pool > 0 then
        return pool
    end
    return DEFAULT_NPC_POOL
end

local function getNPCProfileByKey(npcRecord)
    if type(npcRecord) == "table" then
        local profileId = npcRecord.id or npcRecord.npcRecord or npcRecord.key
        if type(profileId) == "string" and NPC_PROFILES_BY_ID[profileId] then
            return NPC_PROFILES_BY_ID[profileId]
        end
        local legacyRecord = npcRecord.legacyRecord or npcRecord.record or npcRecord.recordID
        if type(legacyRecord) == "string" and NPC_PROFILES_BY_LEGACY[legacyRecord] then
            return NPC_PROFILES_BY_LEGACY[legacyRecord]
        end
        return nil
    end

    if type(npcRecord) ~= "string" or npcRecord == "" then
        return nil
    end

    return NPC_PROFILES_BY_ID[npcRecord] or NPC_PROFILES_BY_LEGACY[npcRecord]
end

local function tweakRecordExists(recordKey)
    if type(recordKey) ~= "string" or recordKey == "" then
        return false
    end

    local record = nil
    pcall(function()
        record = TweakDB:GetRecord(TweakDBID.new(recordKey))
    end)
    return record ~= nil
end

local function copyVehicleMeta(meta)
    if type(meta) ~= "table" then return nil end
    local tags = {}
    for i, tag in ipairs(meta.tags or {}) do
        tags[i] = tag
    end
    return {
        id = meta.id,
        prestige = meta.prestige,
        tags = tags,
        carClass = meta.carClass,
    }
end

local function normalizeQuickRaceWeighting(weighting)
    if QUICK_RACE_PRESTIGE_WEIGHTS[weighting] then
        return weighting
    end
    return "mixed"
end

local function collectQuickRaceCandidates(carClass, prestigeMin, prestigeMax)
    local classes = {}
    if type(carClass) == "string" and VehiclePool.RECORDS[carClass] then
        classes[1] = carClass
    else
        for _, className in ipairs(CLASS_ORDER) do
            classes[#classes + 1] = className
        end
    end

    local candidates = {}
    for _, className in ipairs(classes) do
        for _, entry in ipairs(VehiclePool.RECORDS[className] or {}) do
            if entry.prestige >= prestigeMin and entry.prestige <= prestigeMax then
                candidates[#candidates + 1] = {
                    id = entry.id,
                    prestige = entry.prestige,
                    tags = entry.tags,
                    carClass = className,
                }
            end
        end
    end
    return candidates, classes
end

local function fallbackQuickRaceCandidates(classes, prestigeMin, prestigeMax)
    local targetPrestige = prestigeMax
    local bestDistance = math.huge
    local candidates = {}

    for _, className in ipairs(classes or {}) do
        for _, entry in ipairs(VehiclePool.RECORDS[className] or {}) do
            local distance = math.abs((entry.prestige or 1) - targetPrestige)
            if distance < bestDistance then
                bestDistance = distance
                candidates = {
                    {
                        id = entry.id,
                        prestige = entry.prestige,
                        tags = entry.tags,
                        carClass = className,
                    },
                }
            elseif distance == bestDistance then
                candidates[#candidates + 1] = {
                    id = entry.id,
                    prestige = entry.prestige,
                    tags = entry.tags,
                    carClass = className,
                }
            end
        end
    end
    return candidates
end

-- ── Public API ────────────────────────────────────────────────

--- Pick a car class deterministically for a tier using class weights.
--- @param tier       string  "Gonk", "Streetkid", etc.
--- @param seedValue  number  0-1 float from seeded stream
--- @return string    class name
function VehiclePool.pickWeightedClassForTier(tier, seedValue)
    local weights = VehiclePool.TIER_CLASS_WEIGHTS[tier] or VehiclePool.TIER_CLASS_WEIGHTS.Gonk
    return weightedPickClass(weights, seedValue)
end

--- Return the structured vehicle entry for a tier+class, using prestige weighting.
--- Never returns nil as long as RECORDS[carClass] is non-empty.
--- @param tier       string  "Gonk" etc.
--- @param carClass   string  "Muscle" etc.
--- @param seedValue  number  0-1 float from seeded stream
--- @param driver     table   optional driver table for elite floor bumping
--- @return table     { id, prestige, tags }
function VehiclePool.resolveVehicleForTier(tier, carClass, seedValue, driver)
    local pool = VehiclePool.RECORDS[carClass] or VehiclePool.RECORDS.Muscle
    if #pool == 0 then return { id = "Vehicle.v_sport2_quadra_type66", prestige = 3, tags = {} } end

    local candidates, total = buildCandidates(tier, carClass, driver)
    if #candidates == 0 then return pool[1] end

    local target = seedValue * total
    local acc = 0
    for _, c in ipairs(candidates) do
        acc = acc + c.w
        if acc >= target then return c.entry end
    end
    return candidates[#candidates].entry
end

function VehiclePool.normalizeQuickRaceWeighting(weighting)
    return normalizeQuickRaceWeighting(weighting)
end

function VehiclePool.recommendedPrestigeBandForTier(tier)
    local pWeights = VehiclePool.TIER_PRESTIGE_WEIGHTS[tier] or VehiclePool.TIER_PRESTIGE_WEIGHTS.Gonk
    local floor = VehiclePool.PRESTIGE_FLOOR[tier] or 1
    local minPrestige, maxPrestige = nil, nil

    for prestige = floor, 5 do
        local weight = pWeights[prestige] or 0
        if weight >= 10 then
            if not minPrestige then minPrestige = prestige end
            maxPrestige = prestige
        end
    end

    if not minPrestige then
        for prestige = floor, 5 do
            local weight = pWeights[prestige] or 0
            if weight > 0 then
                if not minPrestige then minPrestige = prestige end
                maxPrestige = prestige
            end
        end
    end

    minPrestige = minPrestige or floor
    maxPrestige = maxPrestige or minPrestige
    return minPrestige, maxPrestige
end

function VehiclePool.resolveQuickRaceVehicle(carClass, prestigeMin, prestigeMax, weighting, seedValue, options)
    prestigeMin = math.max(1, math.min(5, tonumber(prestigeMin) or 1))
    prestigeMax = math.max(1, math.min(5, tonumber(prestigeMax) or 5))
    if prestigeMin > prestigeMax then prestigeMin, prestigeMax = prestigeMax, prestigeMin end

    weighting = normalizeQuickRaceWeighting(weighting)
    options = options or {}

    local candidates, classes = collectQuickRaceCandidates(carClass, prestigeMin, prestigeMax)
    if #candidates == 0 and options.fallbackToAnyClass and carClass then
        candidates, classes = collectQuickRaceCandidates(nil, prestigeMin, prestigeMax)
    end
    if #candidates == 0 then
        candidates = fallbackQuickRaceCandidates(classes, prestigeMin, prestigeMax)
    end
    if #candidates == 0 then
        return copyVehicleMeta(VEHICLE_META_BY_ID["Vehicle.v_sport2_quadra_type66"]) or {
            id = "Vehicle.v_sport2_quadra_type66",
            prestige = 3,
            tags = {},
            carClass = carClass or "Muscle",
        }
    end

    local weights = QUICK_RACE_PRESTIGE_WEIGHTS[weighting] or QUICK_RACE_PRESTIGE_WEIGHTS.mixed
    local total = 0
    for _, entry in ipairs(candidates) do
        local baseWeight = weights[entry.prestige] or 1
        if options.preferHighest then
            baseWeight = baseWeight * math.max(1, entry.prestige)
        end
        entry._weight = baseWeight
        total = total + baseWeight
    end

    local target = (tonumber(seedValue) or math.random()) * total
    local acc = 0
    for _, entry in ipairs(candidates) do
        acc = acc + (entry._weight or 1)
        if acc >= target then
            entry._weight = nil
            return copyVehicleMeta(entry)
        end
    end

    candidates[#candidates]._weight = nil
    return copyVehicleMeta(candidates[#candidates])
end

--- Look up structured metadata for a vehicle by TweakDB record ID.
--- Scans all classes. Returns nil if the record is not in the catalog.
--- @param recordId string  e.g. "Vehicle.v_sport1_rayfield_caliburn"
--- @return table|nil  { id, prestige, tags } or nil
function VehiclePool.getVehicleMeta(recordId)
    if not recordId then return nil end
    return copyVehicleMeta(VEHICLE_META_BY_ID[recordId])
end

--- Return a stable spawnable entity template path for a stored vehicle key.
--- @param vehicleRecord string|table
--- @return string|nil
function VehiclePool.getVehicleEntityTemplate(vehicleRecord)
    local lookupKey = vehicleRecord
    if type(vehicleRecord) == "table" then
        lookupKey = vehicleRecord.id or vehicleRecord.record or vehicleRecord.vehicleRecord
    end
    if type(lookupKey) ~= "string" or lookupKey == "" then
        return nil
    end
    return VEHICLE_ENTITY_TEMPLATES[lookupKey]
end

--- Resolve a profile definition for a stored NPC key or legacy record.
--- @param npcRecord string|table
--- @return table|nil
function VehiclePool.getNPCProfile(npcRecord)
    return getNPCProfileByKey(npcRecord)
end

--- Return the preferred dynamic spawn key for a stored NPC identity.
--- Uses the compatible Character.* record first and leaves the template as
--- a separate fallback for older or thinner profiles.
--- @param npcRecord string|table|nil
--- @param driver table|nil
--- @return string|nil
function VehiclePool.getNPCSpawnKey(npcRecord, driver)
    local customRecord = nil
    if type(driver) == "table" and MTE and MTE.NamedRivals and MTE.NamedRivals.getRecordForDriver then
        pcall(function()
            customRecord = MTE.NamedRivals.getRecordForDriver(driver)
        end)
    end
    if type(customRecord) == "string" and customRecord ~= "" and tweakRecordExists(customRecord) then
        return customRecord
    end

    local profile = getNPCProfileByKey(npcRecord)
    if profile then
        return profile.record or profile.legacyRecord or profile.id
    end
    if type(npcRecord) == "table" then
        return npcRecord.record or npcRecord.legacyRecord or npcRecord.id
    end
    if type(npcRecord) == "string" and npcRecord ~= "" then
        return npcRecord
    end
    return nil
end

--- Return a stable profile ID for a stored NPC key, falling back to the
--- faction pool if the cached value is legacy or missing.
--- @param npcRecord string|table|nil
--- @param factionId string|nil
--- @param driverId  string|nil
--- @return string|nil
function VehiclePool.normalizeNPCRecord(npcRecord, factionId, driverId)
    local profile = getNPCProfileByKey(npcRecord)
    if profile then
        return profile.id
    end
    if driverId and driverId ~= "" then
        return VehiclePool.pickNPCForDriver(driverId, factionId)
    end
    return VehiclePool.resolveNPC(0, factionId)
end

--- Return the spawnable entity template path for a stored NPC key.
--- @param npcRecord string|table
--- @return string|nil, table|nil
function VehiclePool.getNPCEntityTemplate(npcRecord)
    local profile = getNPCProfileByKey(npcRecord)
    if not profile then return nil, nil end
    return profile.entPath, profile
end

--- Whether a cached NPC identity still needs migration.
--- Legacy intrasys strings intentionally return true.
--- @param npcRecord string|table|nil
--- @return boolean
function VehiclePool.npcNeedsMigration(npcRecord)
    return type(npcRecord) ~= "string" or NPC_PROFILES_BY_ID[npcRecord] == nil
end

--- Human-readable identifier for logs/UI.
--- @param npcRecord string|table|nil
--- @return string
function VehiclePool.describeNPC(npcRecord)
    local profile = getNPCProfileByKey(npcRecord)
    if profile then
        return profile.id
    end
    if type(npcRecord) == "table" then
        return tostring(npcRecord.id or npcRecord.legacyRecord or npcRecord.entPath or "npc:table")
    end
    return tostring(npcRecord)
end

--- Backward-compatible: pick a random vehicle record for a class.
--- Prefer resolveVehicleForTier for new code.
function VehiclePool.pickVehicle(carClass)
    local pool = VehiclePool.RECORDS[carClass] or VehiclePool.RECORDS.Muscle
    return pool[math.random(#pool)].id
end

--- Resolve a vehicle by car class and a stable index (backward compat).
--- @param carClass     string
--- @param signatureIdx number  numeric index (mod pool size)
--- @return string TweakDB record ID
function VehiclePool.resolveVehicle(carClass, signatureIdx)
    local pool = VehiclePool.RECORDS[carClass] or VehiclePool.RECORDS.Muscle
    local idx  = (math.floor(signatureIdx) % #pool) + 1
    return pool[idx].id
end

--- Pick a random NPC record.
function VehiclePool.pickNPC(factionId)
    local poolIds = getNPCPoolIds(factionId)
    return poolIds[math.random(#poolIds)]
end

--- Pick a deterministic NPC record for a specific driver ID.
function VehiclePool.pickNPCForDriver(driverId, factionId)
    local poolIds = getNPCPoolIds(factionId)
    if not driverId or driverId == "" then
        return VehiclePool.pickNPC(factionId)
    end
    local hash = 0
    for i = 1, #driverId do
        hash = ((hash * 33) + string.byte(driverId, i)) % 2147483647
    end
    if factionId and factionId ~= "" then
        for i = 1, #factionId do
            hash = ((hash * 33) + string.byte(factionId, i)) % 2147483647
        end
    end
    local idx = (hash % #poolIds) + 1
    return poolIds[idx]
end

--- Resolve an NPC record by a stable index.
function VehiclePool.resolveNPC(npcIdx, factionId)
    local poolIds = getNPCPoolIds(factionId)
    local idx = (math.floor(tonumber(npcIdx) or 0) % #poolIds) + 1
    return poolIds[idx]
end

return VehiclePool

