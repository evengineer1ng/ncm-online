-- ============================================================
-- MT_Ecosystem: data/tracks.lua
-- Named race routes between specific node pairs.
--
-- IDs are the slug of the node .name from nodes.lua:
--   lower-case, spaces → underscores, non-alphanum stripped.
--
-- For any pair without a curated name, Tracks.getRouteName()
-- falls back to "Node A Name → Node B Name".
-- ============================================================

local Tracks = {}

-- ── Curated named routes ──────────────────────────────────────

local _named = {
    -- ── City Center ──────────────────────────────────────────
    { a = "corpo_plaza_north_gate",       b = "arasaka_tower_underpass",    name = "Corporate Mile"            },
    { a = "charter_hill_junction",        b = "memorial_park_exit",         name = "Charter Sprint"            },
    { a = "nc_spine_road_n",              b = "nc_spine_road_s",            name = "Night City Spine"          },
    { a = "charter_hill_junction",        b = "west_highway_overpass",      name = "Charter Hill Climb"        },
    { a = "kabuki_market_ramp",           b = "nc_spine_road_n",            name = "Kabuki Express"            },

    -- ── Watson ───────────────────────────────────────────────
    { a = "northside_industrial_rd",      b = "little_china_highway",       name = "Industrial Circuit"        },
    { a = "nc_port_north_gate",           b = "malstrom_project_bridge",    name = "Harbour Straight"          },
    { a = "kabuki_roundabout",            b = "watson_underpass_west",      name = "Kabuki Loop"               },
    { a = "northside_industrial_rd",      b = "nc_port_north_gate",         name = "Northside Haul"            },
    { a = "northern_freeway_west",        b = "northern_freeway_east",      name = "The Freeway"               },
    { a = "little_china_highway",         b = "kabuki_roundabout",          name = "Little China Run"          },

    -- ── Westbrook ─────────────────────────────────────────────
    { a = "japantown_main_strip",         b = "coastview_bypass",           name = "Japantown Strip"           },
    { a = "north_oak_highway_bend",       b = "charter_hill_overpass",      name = "North Oak Descent"         },
    { a = "japantown_south_plaza",        b = "japantown_main_strip",       name = "Japantown Boulevard"       },
    { a = "east_highway_overpass",        b = "coastview_bypass",           name = "Coastview Flyover"         },
    { a = "north_oak_highway_bend",       b = "japantown_south_plaza",      name = "North Oak to Japantown"    },

    -- ── Heywood ───────────────────────────────────────────────
    { a = "wellsprings_drag_strip",       b = "vista_del_rey_straight",     name = "Wellsprings Drag"          },
    { a = "the_glen_main_rd",             b = "heywood_south_exit",         name = "Glen to South"             },
    { a = "arroyo_north_interchange",     b = "heywood_east_connector",     name = "Eastern Bypass"            },
    { a = "wellsprings_drag_strip",       b = "heywood_east_connector",     name = "Wellsprings-East Link"     },
    { a = "the_glen_main_rd",             b = "nc_spine_road_s",            name = "Spine Gate South"          },

    -- ── Pacifica ──────────────────────────────────────────────
    { a = "pacifica_racetrack_ruins",     b = "west_wind_ave",              name = "Racetrack Ruins Run"       },
    { a = "batallion_beachhead_road",     b = "coastview_overpass",         name = "Beachhead Straight"        },
    { a = "west_wind_ave",                b = "pacific_commerce_centre",    name = "West Wind Commerce"        },
    { a = "pacifica_racetrack_ruins",     b = "batallion_beachhead_road",   name = "Beach Circuit"             },
    { a = "pacific_commerce_centre",      b = "coastview_overpass",         name = "Commerce Overpass"         },

    -- ── Santo Domingo ─────────────────────────────────────────
    { a = "arroyo_industrial_straight",   b = "rancho_coronado_blvd",       name = "Arroyo Industrial"         },
    { a = "santo_domingo_south_gate",     b = "recycling_plant_rd",         name = "South Gate Circuit"        },
    { a = "sd_connector_to_heywood",      b = "arroyo_industrial_straight", name = "SD-Heywood Connector"      },
    { a = "rancho_coronado_blvd",         b = "recycling_plant_rd",         name = "Rancho Coronado Loop"      },
    { a = "santo_domingo_south_gate",     b = "arroyo_north_interchange",   name = "SD to Arroyo"              },

    -- ── Badlands ──────────────────────────────────────────────
    { a = "rocky_ridge_hairpin",          b = "desert_highway_east",        name = "Badlands Haul"             },
    { a = "badlands_northern_route",      b = "badlands_ne_plateau",        name = "Northern Plateau Run"      },
    { a = "wraith_camp_road",             b = "southern_desert_run",        name = "Desert Gauntlet"           },
    { a = "biotechnica_fields_north",     b = "splitsville_crossroads",     name = "Biotechnica Straight"      },
    { a = "far_east_trail",               b = "badlands_sw_gate",           name = "Cross-Badlands"            },
    { a = "badlands_northern_route",      b = "wraith_camp_road",           name = "Wraith Country"            },
    { a = "rocky_ridge_hairpin",          b = "badlands_ne_plateau",        name = "Plateau Hairpin"           },
    { a = "southern_desert_run",          b = "far_east_trail",             name = "Far Desert Loop"           },
}

-- ── Lookup table (both directions share same key) ─────────────

local _lookup = {}

local function _slug(a, b)
    if a <= b then return a .. "|" .. b
    else            return b .. "|" .. a
    end
end

for _, r in ipairs(_named) do
    _lookup[_slug(r.a, r.b)] = r.name
end

-- ── Public API ────────────────────────────────────────────────

--- Return the display name for a route between two node objects.
--- Falls back to "NodeA Name → NodeB Name" if no curated entry exists.
--- @param nodeA  table  node object (fields: .id, .name)
--- @param nodeB  table  node object (fields: .id, .name)
function Tracks.getRouteName(nodeA, nodeB)
    if not nodeA or not nodeB then return "Unknown Route" end
    local key = _slug(nodeA.id or nodeA.name, nodeB.id or nodeB.name)
    return _lookup[key] or (nodeA.name .. " → " .. nodeB.name)
end

--- Return the display name from raw string IDs.
--- Useful for the Records tab where only IDs are stored.
--- @param nodeA_id  string
--- @param nodeB_id  string
function Tracks.getNameByIds(nodeA_id, nodeB_id)
    if not nodeA_id or not nodeB_id then return "Unknown Route" end
    local key = _slug(nodeA_id, nodeB_id)
    return _lookup[key] or (nodeA_id .. " → " .. nodeB_id)
end

--- Return the full curated list (for tooling / debug).
function Tracks.all()
    return _named
end

return Tracks
