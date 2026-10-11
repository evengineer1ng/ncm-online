-- ncm-core data: data.nodes
-- Curated NCM route nodes carried over from the SP payload (data/nodes_curated.lua). Coordinates are
-- world metres; heading degrees; ids are the SP slugs (stable across SP and online).
local Core = NcmCore

Core.define("data.nodes", function(C)
    local M = { version = "0.0.1" }

    M.LIST = {
        { x = -2326, y = -1125, z = 13,  heading =   39.033, name = "Parque Del Mar",         region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "parque_del_mar_-2326_-1125" },
        { x =  -264, y =   304, z = 29,  heading =  -15.270, name = "Gold Niwaki Plaza",       region = "Westbrook",   road = true, urban = true, waypointable = true, raceLegal = true, id = "gold_niwaki_plaza_-264_304" },
        { x = -1281, y = -1107, z = 13,  heading = -157.342, name = "Hanford Overpass",        region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "hanford_overpass_-1281_-1107" },
        { x = -2362, y =   117, z = 13,  heading = -171.401, name = "Downtown",                region = "City Center", road = true, urban = true, waypointable = true, raceLegal = true, id = "downtown_-2362_117" },
        { x =  -900, y =  -751, z =  9,  heading =  -35.168, name = "Vista Del Drag",          region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "vista_del_drag_-900_-751" },
        { x =  -373, y =     0, z = 13,  heading =  -35.311, name = "Japantown Crossway",      region = "Westbrook",   road = true, urban = true, waypointable = true, raceLegal = true, id = "japantown_crossway_-373_0" },
        { x = -1776, y = -1371, z = 35,  heading =  -95.716, name = "Glen Straight",           region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "glen_straight_-1776_-1371" },
        { x = -1829, y = -2030, z = 43,  heading =  118.081, name = "Chapel",                  region = "Pacifica",    road = true, urban = true, waypointable = true, raceLegal = true, id = "chapel_-1829_-2030" },
        { x = -1336, y =  -713, z =  8,  heading =    0.238, name = "Ebunike",                 region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "ebunike_-1336_-713" },
        { x = -1103, y =   -19, z =  8,  heading =  104.434, name = "Corpo Plaza",             region = "City Center", road = true, urban = true, waypointable = true, raceLegal = true, id = "corpo_plaza_-1103_-19" },
        { x =    42, y =  1118, z = 140, heading =  164.186, name = "North Oak Tunnel",        region = "Westbrook",   road = true, urban = true, waypointable = true, raceLegal = true, id = "north_oak_tunnel_42_1118" },
        { x = -1765, y = -1531, z = 46,  heading =   69.866, name = "Coastview Highway",       region = "Pacifica",    road = true, urban = true, waypointable = true, raceLegal = true, id = "coastview_highway_-1765_-1531" },
        { x = -1489, y =  -964, z = 15,  heading =   -1.206, name = "Glenview Lofts",          region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "glenview_lofts_-1489_-964" },
        { x = -1326, y = -1656, z = 45,  heading =    0.176, name = "Stadium",                 region = "Pacifica",    road = true, urban = true, waypointable = true, raceLegal = true, id = "stadium_-1326_-1656" },
        { x = -1110, y =   342, z = 26,  heading =  -40.051, name = "Central Highway",         region = "City Center", road = true, urban = true, waypointable = true, raceLegal = true, id = "central_highway_-1110_342" },
        { x =   505, y =  1229, z = 230, heading = -119.845, name = "Hill Abode",              region = "Westbrook",   road = true, urban = true, waypointable = true, raceLegal = true, id = "hill_abode_505_1229" },
        { x = -2899, y = -2711, z = 20,  heading =  -62.795, name = "Trench",                  region = "Pacifica",    road = true, urban = true, waypointable = true, raceLegal = true, id = "trench_-2899_-2711" },
        { x = -1354, y =  -476, z =  8,  heading =  -87.368, name = "Pothole",                 region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "pothole_-1354_-476" },
        { x = -1450, y =  2467, z = -5,  heading =   21.755, name = "North Tunnel",            region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "north_tunnel_-1450_2467" },
        { x = -1035, y =  3652, z = 14,  heading = -104.707, name = "Tip",                     region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "tip_-1035_3652" },
        { x = -2832, y = -2675, z = 23,  heading =  -65.958, name = "A bit",                   region = "Pacifica",    road = true, urban = true, waypointable = true, raceLegal = true, id = "a_bit_-2832_-2675" },
        { x =   -42, y =  1553, z = 115, heading =   -2.684, name = "North Oak Ramp",          region = "Westbrook",   road = true, urban = true, waypointable = true, raceLegal = true, id = "north_oak_ramp_-42_1553" },
        { x =   -31, y =  2084, z = 101, heading =  175.307, name = "North Oak Ramp 2",        region = "Westbrook",   road = true, urban = true, waypointable = true, raceLegal = true, id = "north_oak_ramp_2_-31_2084" },
        { x = -1106, y =  1853, z = 23,  heading =   -3.555, name = "Kabuki Bridge",           region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "kabuki_bridge_-1106_1853" },
        { x =  -558, y =  2522, z = 56,  heading =   48.866, name = "Allfoods Intersection",   region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "allfoods_intersection_-558_2522" },
        { x =  -574, y =  3379, z = 13,  heading =   -1.806, name = "Graveyard Shift",         region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "graveyard_shift_-574_3379" },
        { x = -2065, y =  1819, z = 18,  heading =  -57.232, name = "Arasaka",                 region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "arasaka_-2065_1819" },
        { x = -2080, y =  1779, z = 35,  heading = -153.739, name = "Watsins Glen",            region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "watsins_glen_-2080_1779" },
        { x = -1909, y =  1245, z = 52,  heading =  153.219, name = "Little China Freeway",   region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "little_china_freeway_-1909_1245" },
        { x = -2380, y =  -472, z = 13,  heading =  176.676, name = "Checkerboard",            region = "Heywood",     road = true, urban = true, waypointable = true, raceLegal = true, id = "checkerboard_-2380_-472" },
        { x = -2131, y = -2248, z = 18,  heading =   45.561, name = "Dogtown",                 region = "Pacifica",    road = true, urban = true, waypointable = true, raceLegal = true, id = "dogtown_-2131_-2248" },
        { x =  5042, y = -1044, z = 140, heading =   81.383, name = "Go Smile",                region = "Badlands",    road = true, urban = true, waypointable = true, raceLegal = true, id = "go_smile_5042_-1044" },
        { x =   408, y = -1966, z = -2,  heading = -144.426, name = "Arcade Fire",             region = "Santo Domingo", road = true, urban = true, waypointable = true, raceLegal = true, id = "arcade_fire_408_-1966" },
        { x = -2350, y = -2446, z = 11,  heading =  114.209, name = "Deep Dive",               region = "Pacifica",    road = true, urban = true, waypointable = true, raceLegal = true, id = "deep_dive_-2350_-2446" },
        { x =  -569, y =  2648, z = 53,  heading =  -36.627, name = "Waterfront",              region = "Watson",      road = true, urban = true, waypointable = true, raceLegal = true, id = "waterfront_-569_2648" },
    }

    local byId = nil
    local function index()
        if not byId then
            byId = {}
            for _, n in ipairs(M.LIST) do byId[n.id] = n end
        end
        return byId
    end
    function M.byId(id) return index()[id] end

    --- Register a node at runtime (authored routes, Batch 2 host kit). Replaces an existing node of the same id.
    function M.register(n)
        if type(n) ~= "table" or type(n.id) ~= "string" or type(n.x) ~= "number" or type(n.y) ~= "number" then return nil, "invalid_node" end
        local ix = index()
        if not ix[n.id] then M.LIST[#M.LIST + 1] = n else
            for i, x in ipairs(M.LIST) do if x.id == n.id then M.LIST[i] = n end end
        end
        ix[n.id] = n
        return n
    end

    --- Remove a runtime-registered node. `data.roots` has had this since the host kit; nodes did not, because
    --- authored routes are permanent and never needed it. A player-called race does (`L181`): its start point is a
    --- temporary node created from wherever the driver was standing, and without this every Street Call would
    --- leave two nodes behind for the lifetime of the process -- growing the map markers, the route resolver and
    --- the builder's own node list a little more every time.
    function M.unregister(id)
        local ix = index()
        if not ix[id] then return false end
        ix[id] = nil
        for i, x in ipairs(M.LIST) do if x.id == id then table.remove(M.LIST, i); break end end
        return true
    end

    function M.count() return #M.LIST end

    return M
end)
