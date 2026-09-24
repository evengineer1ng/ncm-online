-- ============================================================
-- MT_Ecosystem: modules/heat.lua
-- Per-district faction heat system.
--   • Each race in a district raises heat vs that district's faction.
--   • Heat decays daily (game-time) when not racing.
--   • At high heat levels, faction drivers join the field uninvited.
--   • Four levels: Clean / Known / Marked / Hunted
-- ============================================================

local Heat = {}
local Persist = require("modules/persistence")

-- ── Faction map (district → faction name) ────────────────────
Heat.FACTION_MAP = {
    Watson            = "Maelstrom",
    Westbrook         = "Tigers",
    Heywood           = "Valentinos",
    Pacifica          = "Animals",
    ["Santo Domingo"] = "6th Street",
    Badlands          = "Wraiths",
    ["City Center"]   = "Arasaka",
}

-- ── Heat level thresholds ─────────────────────────────────────
-- Each entry describes what happens when heat is in that range.
local HEAT_LEVELS = {
    { name = "Clean",  lo = 0,  hi = 25, extraDrivers = 0, paceMod = 0.00 },
    { name = "Known",  lo = 26, hi = 50, extraDrivers = 1, paceMod = 0.05 },
    { name = "Marked", lo = 51, hi = 75, extraDrivers = 2, paceMod = 0.10 },
    { name = "Hunted", lo = 76, hi = 100,extraDrivers = 3, paceMod = 0.20 },
}

-- Gain / loss constants
local HEAT_WIN_GAIN     = 15
local HEAT_LOSS_GAIN    = 5   -- even losing raises your profile a little
local HEAT_DAILY_DECAY  = 3   -- per game-day of not racing in that district
local GAME_DAY_SECONDS  = 2880 -- one in-game day ≈ 48 real minutes

-- Heat stored as a flat table: { [district] = heatValue (0-100) }
-- Also: { _lastDecayRealTime } to handle day-based decay via os.time()

local HEAT_FILE = "heat.json"

-- ── State ─────────────────────────────────────────────────────

Heat._data = {}  -- { districts = { Watson=12, ... }, lastDecayRealTime = 0 }

-- ── Init / Persistence ────────────────────────────────────────

function Heat.init()
    local data = Persist.load(HEAT_FILE)
    if type(data) == "table" then
        Heat._data = data
        -- Migrate legacy lastDecayHour → lastDecayRealTime
        if Heat._data.lastDecayHour and not Heat._data.lastDecayRealTime then
            Heat._data.lastDecayRealTime = os.time()
            Heat._data.lastDecayHour = nil
        end
    else
        Heat._data = { districts = {}, lastDecayRealTime = os.time() }
    end
    print("[NCM/Heat] Loaded faction heat data.")
end

function Heat.save()
    Persist.save(HEAT_FILE, Heat._data)
end

-- ── Public API ────────────────────────────────────────────────

--- Return current heat (0-100) for a district.
function Heat.get(district)
    return (Heat._data.districts or {})[district] or 0
end

--- Return the heat level definition table for a district.
function Heat.level(district)
    local h = Heat.get(district)
    for i = #HEAT_LEVELS, 1, -1 do
        if h >= HEAT_LEVELS[i].lo then return HEAT_LEVELS[i] end
    end
    return HEAT_LEVELS[1]
end

--- Return the level name string e.g. "Marked".
function Heat.levelName(district)
    return Heat.level(district).name
end

--- Called after each race. Raises heat, saves.
--- @param district  string  e.g. "Watson"
--- @param playerWon bool
function Heat.applyRaceResult(district, playerWon)
    if not district then return end
    Heat._data.districts = Heat._data.districts or {}
    local current = Heat._data.districts[district] or 0
    local gain    = playerWon and HEAT_WIN_GAIN or HEAT_LOSS_GAIN
    Heat._data.districts[district] = math.min(100, current + gain)
    print(string.format("[NCM/Heat] %s heat: %d → %d (%s)",
        district, current, Heat._data.districts[district],
        playerWon and "win" or "loss"))
    Heat.save()
end

--- Called on game-time tick. Decays heat for all districts by daily amount.
--- Uses real wall-clock time (os.time) scaled to game-day length to avoid
--- the 0-23 hour wrap bug.
function Heat.tickDecay(gameHour)
    Heat._data.lastDecayRealTime = Heat._data.lastDecayRealTime or os.time()
    local now     = os.time()
    local elapsed = now - Heat._data.lastDecayRealTime

    -- Count how many game-days worth of real time have passed
    local daysPassed = math.floor(elapsed / GAME_DAY_SECONDS)
    if daysPassed < 1 then return end

    local totalDecay = daysPassed * HEAT_DAILY_DECAY
    Heat._data.lastDecayRealTime = Heat._data.lastDecayRealTime + daysPassed * GAME_DAY_SECONDS
    local changed = false

    for district, h in pairs(Heat._data.districts or {}) do
        if h > 0 then
            local newH = math.max(0, h - totalDecay)
            Heat._data.districts[district] = newH
            changed = true
        end
    end

    if changed then
        Heat.save()
    end
end

--- Inject faction drivers into a race field based on current district heat.
--- Called by Roster.pickForRace(). Returns a list of faction driver objects.
--- @param district  string
--- @param careerSeed number  for deterministic generation
--- @return table   array of faction driver objects (may be empty)
function Heat.injectFactionDrivers(district, careerSeed)
    local level = Heat.level(district)
    if level.extraDrivers == 0 then return {} end

    local faction = Heat.FACTION_MAP[district] or "Unknown"
    local drivers = {}
    local seed    = (careerSeed or 12345) + math.floor(os.time() / 3600)  -- hourly variance

    for i = 1, level.extraDrivers do
        -- Generate a faction enforcer: tougher than normal, has faction branding
        local s = Heat._lcg(seed + i * 971)
        local nameSeed = Heat._lcg(s)
        local paceSeed = Heat._lcg(nameSeed)

        local driver = {
            id           = string.format("faction_%s_%d_%d", district:lower(), i, os.time()),
            isFaction    = true,
            faction      = faction,
            displayName  = Heat._factionName(faction, nameSeed),
            tier         = "faction",
            pace         = 0.90 + (paceSeed / 4294967296.0) * (level.paceMod + 0.10),
            aggression   = 0.75 + (Heat._lcg(paceSeed) / 4294967296.0) * 0.25,
            precision    = 0.60 + (Heat._lcg(Heat._lcg(paceSeed)) / 4294967296.0) * 0.35,
            consistency  = 0.65,
            personality  = "dirty fighter",
            color        = Heat._factionColor(faction),
            wins         = 0,
            rep          = 0,
        }
        table.insert(drivers, driver)
    end

    print(string.format("[NCM/Heat] Injecting %d %s enforcer(s) into %s race (heat=%d).",
        #drivers, faction, district, Heat.get(district)))

    return drivers
end

--- Get a summary of all districts' heat for HUD display.
--- Returns sorted list of { district, heat, levelName, faction }.
function Heat.summary()
    local out = {}
    for dist, faction in pairs(Heat.FACTION_MAP) do
        local h = Heat.get(dist)
        if h > 0 then
            table.insert(out, {
                district  = dist,
                faction   = faction,
                heat      = h,
                levelName = Heat.level(dist).name,
            })
        end
    end
    table.sort(out, function(a, b) return a.heat > b.heat end)
    return out
end

--- Reset heat for one district (e.g., after a long absence or a special event).
function Heat.resetDistrict(district)
    if Heat._data.districts then
        Heat._data.districts[district] = 0
        Heat.save()
    end
end

-- ── Internal helpers ──────────────────────────────────────────

function Heat._lcg(seed)
    return (seed * 1664525 + 1013904223) % 4294967296
end

local FACTION_PREFIXES = {
    Maelstrom   = { "Chrome", "Spike", "Rust", "Zero", "Dead", "Volt" },
    Valentinos  = { "Loco", "Fuego", "Santo", "Cholo", "Rojo", "Diablo" },
    Animals     = { "Beast", "Fang", "Claw", "Stomp", "Grind", "Crush" },
    ["6th Street"] = { "Flag", "Blaze", "Steel", "Riot", "Iron", "War" },
    Tigers      = { "Tiger", "Night", "Claw", "Shadow", "Blade", "Gold" },
    Wraiths     = { "Dust", "Ghost", "Sand", "Wail", "Drift", "Howl" },
    Arasaka     = { "Unit", "Sec", "Prime", "Delta", "Kage", "En" },
}

local FACTION_SUFFIXES = {
    "Runner", "Hawk", "Hook", "Blade", "Strike", "Fury",
    "Dog", "Snake", "Wolf", "Fang", "Death", "Edge",
}

function Heat._factionName(faction, seed)
    local prefixes = FACTION_PREFIXES[faction] or { "Ghost" }
    local pi = (seed % #prefixes) + 1
    local si = (Heat._lcg(seed) % #FACTION_SUFFIXES) + 1
    return prefixes[pi] .. "-" .. FACTION_SUFFIXES[si]
end

local FACTION_COLORS = {
    Maelstrom      = { 0.90, 0.20, 0.20 },  -- red-ish
    Valentinos     = { 0.85, 0.70, 0.10 },  -- gold-ish
    Animals        = { 0.20, 0.75, 0.30 },  -- green
    ["6th Street"] = { 0.20, 0.40, 0.90 },  -- blue
    Tigers         = { 0.95, 0.50, 0.10 },  -- orange
    Wraiths        = { 0.70, 0.70, 0.70 },  -- grey
    Arasaka        = { 0.85, 0.05, 0.05 },  -- deep red
}

function Heat._factionColor(faction)
    return FACTION_COLORS[faction] or { 1, 1, 1 }
end

return Heat
