-- ============================================================
-- MT_Ecosystem: data/factions.lua
-- Motorsport team / faction identity catalog.
-- These are racing team identities, not strict lore-locks.
-- They can be inspired by world factions but function purely
-- as a motorsport team layer separate from prestige tier.
-- ============================================================

local Factions = {}

-- ── Catalog ───────────────────────────────────────────────────
local CATALOG = {
    {
        id    = "independent",
        name  = "Independent",
        color = { 1.0, 0.93, 0.33 },
        style = "privateer",
    },
    {
        id    = "afterlife_speedworks",
        name  = "Afterlife Speedworks",
        color = { 0.75, 0.65, 0.20 },
        style = "elite_street",
    },
    {
        id    = "aldecaldo_racing",
        name  = "Aldecaldo Racing",
        color = { 0.85, 0.50, 0.15 },
        style = "nomad_circuit",
    },
    {
        id    = "tyger_claws_gp",
        name  = "Tyger Claws GP",
        color = { 0.95, 0.50, 0.10 },
        style = "aggressive_street",
    },
    {
        id    = "6th_street_motorsports",
        name  = "6th Street Motorsports",
        color = { 0.20, 0.70, 0.30 },
        style = "muscle_street",
    },
    {
        id    = "valentinos_racing_club",
        name  = "Valentinos Racing Club",
        color = { 0.85, 0.20, 0.20 },
        style = "street_flash",
    },
    {
        id    = "wraith_performance",
        name  = "Wraith Performance",
        color = { 0.50, 0.50, 0.55 },
        style = "badlands_build",
    },
    {
        id    = "arasaka_advanced_motorsport",
        name  = "Arasaka Advanced Motorsport",
        color = { 0.15, 0.15, 0.80 },
        style = "corporate_precision",
    },
    {
        id    = "militech_track_division",
        name  = "Militech Track Division",
        color = { 0.30, 0.45, 0.25 },
        style = "corporate_aggression",
    },
    {
        id    = "night_corp_velocity",
        name  = "Night Corp Velocity",
        color = { 0.05, 0.55, 0.85 },
        style = "corporate_tech",
    },
    {
        id    = "mox_motor_club",
        name  = "Mox Motor Club",
        color = { 0.70, 0.25, 0.75 },
        style = "underground_flash",
    },
}

local _byId = {}
for _, f in ipairs(CATALOG) do _byId[f.id] = f end

-- Factions eligible for AI driver assignment (excludes "independent" — V-only)
local _assignable = {}
for _, f in ipairs(CATALOG) do
    if f.id ~= "independent" then
        table.insert(_assignable, f)
    end
end

-- ── Public API ────────────────────────────────────────────────

--- Return the full catalog including "independent".
function Factions.all()
    return CATALOG
end

--- Return factions available for AI driver assignment.
function Factions.assignable()
    return _assignable
end

--- Get a single faction record by id. Returns nil if not found.
--- @param id string  e.g. "tyger_claws_gp"
--- @return table|nil  { id, name, color, style }
function Factions.get(id)
    return _byId[id]
end

--- Deterministically pick a faction for an AI driver.
--- Operates on the assignable list (excludes "independent").
--- @param seedValue number  0–1 float from the seeded stream
--- @param tier       string  reserved for tier-weighted bias in a future pass
--- @return table  faction record { id, name, color, style }
function Factions.pickForDriver(seedValue, tier)
    local idx = math.max(1, math.min(#_assignable, math.floor(seedValue * #_assignable) + 1))
    return _assignable[idx]
end

return Factions
