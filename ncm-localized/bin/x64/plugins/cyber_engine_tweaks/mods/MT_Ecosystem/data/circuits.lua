-- ============================================================
-- MT_Ecosystem: data/circuits.lua
-- Circuit definitions for Knockout mode: ordered checkpoint
-- arrays forming loops through Night City.
--
-- Each circuit:
--   id             string   unique slug
--   name           string   display name
--   region         string   primary region (for UI grouping)
--   checkpoints    string[] ordered node IDs from data/nodes.lua
--   isLoop         bool     true = last checkpoint connects back to first
--   estimatedLapTime  number  rough seconds per lap (for AI timing)
--
-- Circuits reference existing node IDs (auto-slugged from node names).
-- The knockout module resolves IDs to positions at runtime via MTE.Nodes.
-- ============================================================

local Circuits = {}

local _circuits = {

    -- ── Night City Nurburgring ────────────────────────────────
    -- Full-city knockout loop built around checkpoint eliminations.
    {
        id              = "night_city_nurburgring",
        name            = "Night City Nurburgring",
        region          = "Citywide",
        checkpoints     = {
            "parque_del_mar_-2326_-1125",
            "trench_-2899_-2711",
            "arcade_fire_408_-1966",
            "go_smile_5042_-1044",
            "gold_niwaki_plaza_-264_304",
            "hill_abode_505_1229",
            "north_oak_ramp_2_-31_2084",
            "kabuki_bridge_-1106_1853",
            "allfoods_intersection_-558_2522",
            "arasaka_-2065_1819",
            "little_china_freeway_-1909_1245",
            "checkerboard_-2380_-472",
        },
        isLoop          = true,
        estimatedLapTime = 480,
        knockout        = {
            eliminationMode = "checkpoint",
            maxFieldSize = 11,
            eliminationCheckpointIds = {
                "trench_-2899_-2711",
                "arcade_fire_408_-1966",
                "go_smile_5042_-1044",
                "gold_niwaki_plaza_-264_304",
                "hill_abode_505_1229",
                "north_oak_ramp_2_-31_2084",
                "kabuki_bridge_-1106_1853",
                "allfoods_intersection_-558_2522",
                "arasaka_-2065_1819",
                "little_china_freeway_-1909_1245",
            },
            finalSprintStartCheckpointId = "checkerboard_-2380_-472",
            finishCheckpointId = "parque_del_mar_-2326_-1125",
        },
    },
}

-- ── Public API ────────────────────────────────────────────────

--- Return all circuit definitions.
function Circuits.all()
    return _circuits
end

--- Find a circuit by its ID.
function Circuits.get(circuitId)
    for _, c in ipairs(_circuits) do
        if c.id == circuitId then return c end
    end
    return nil
end

--- Return circuits filtered by region (case-insensitive).
function Circuits.byRegion(region)
    local r = region:lower()
    local out = {}
    for _, c in ipairs(_circuits) do
        if c.region:lower() == r then
            table.insert(out, c)
        end
    end
    return out
end

--- Return circuit count.
function Circuits.count()
    return #_circuits
end

return Circuits
