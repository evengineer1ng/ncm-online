-- ncm-core data: data.roots
-- The NCM default roots pack (SP data/default_roots_pack.lua v1.2.0): named point-to-point routes
-- as start/finish node ids. Per-root profile settings stay in SP; online rulesets own such tuning.
local Core = NcmCore

Core.define("data.roots", function(C)
    local M = { version = "0.0.1", packId = "ncm_default_roots", packVersion = "1.2.0" }

    M.LIST = {
        { rootId = "root_hill_abode_505_1229__to__downtown_2362_117", startNodeId = "hill_abode_505_1229", endNodeId = "downtown_-2362_117", displayName = "Snake in the Grass", description = "Slither downhill through sweeping S-curves and a tunnel before the route tightens into hard-banked downtown corners and ninety-degree turns." },
        { rootId = "root_gold_niwaki_plaza_264_304__to__parque_del_mar_2326_1125", startNodeId = "gold_niwaki_plaza_-264_304", endNodeId = "parque_del_mar_-2326_-1125", displayName = "Reverse Cut", description = "The Cut run backward: a long, fast sweep through the city with its distinctive curved section approached from the opposite direction." },
        { rootId = "root_vista_del_drag_900_751__to__japantown_crossway_373_0", startNodeId = "vista_del_drag_-900_-751", endNodeId = "japantown_crossway_-373_0", displayName = "B-line", recommendedMode = "drag", description = "A short, flat-out drag ending with a sharp uphill ramp that can launch an overcommitted car beyond the finish." },
        { rootId = "root_hanford_overpass_1281_1107__to__stadium_1326_1656", startNodeId = "hanford_overpass_-1281_-1107", endNodeId = "stadium_-1326_-1656", displayName = "Troll Pass", description = "A short sprint from beneath the overpass, threading unexpected barriers and a handful of quick turns before reaching Stadium." },
        { rootId = "root_glenview_lofts_1489_964__to__corpo_plaza_1103_19", startNodeId = "glenview_lofts_-1489_-964", endNodeId = "corpo_plaza_-1103_-19", displayName = "Overbridge Curve", description = "A compact city run defined by its curving bridge crossing on the way from Glenview into Corpo Plaza." },
        { rootId = "root_central_highway_1110_342__to__pothole_1354_476", startNodeId = "central_highway_-1110_342", endNodeId = "pothole_-1354_-476", displayName = "Hook", description = "A city-to-Heywood run whose bending route hooks away from Central Highway before turning toward Pothole." },
        { rootId = "root_north_tunnel_1450_2467__to__japantown_crossway_373_0", startNodeId = "north_tunnel_-1450_2467", endNodeId = "japantown_crossway_-373_0", displayName = "Sewer", description = "A long Watson-to-Westbrook run beginning underground, climbing sharply out of North Tunnel before opening into the city." },
        { rootId = "root_deep_dive_2350_2446__to__trench_2899_2711", startNodeId = "deep_dive_-2350_-2446", endNodeId = "trench_-2899_-2711", displayName = "Hold Your Breath", recommendedMode = "drag", description = "A mostly straight Pacifica sprint with a gentle curve and a barrier-lined finish that rewards a clean final weave." },
        { rootId = "root_tip_1035_3652__to__trench_2899_2711", startNodeId = "tip_-1035_3652", endNodeId = "trench_-2899_-2711", displayName = "Ukulele", description = "A 6.6 km cross-city run mixing fast straights, chicanes, varied corners and a long, kinked tunnel toward the finish." },
        { rootId = "root_parque_del_mar_2326_1125__to__gold_niwaki_plaza_264_304", startNodeId = "parque_del_mar_-2326_-1125", endNodeId = "gold_niwaki_plaza_-264_304", displayName = "The Cut", description = "A fast run built around a long straight and distinctive sweeping uphill curve, carving a broad slice toward Gold Niwaki Plaza." },
    }

    local byId = nil
    local function index()
        if not byId then
            byId = {}
            for _, r in ipairs(M.LIST) do byId[r.rootId] = r end
        end
        return byId
    end
    function M.byId(rootId) return index()[rootId] end

    --- Register a root at runtime (authored routes, Batch 2 host kit): { rootId, startNodeId, endNodeId, displayName,
    --- intermediate? = { {x,y,z,name,heading?}... }, disciplineId?, laps?, custom = true }. Replaces one of the same id.
    function M.register(r)
        if type(r) ~= "table" or type(r.rootId) ~= "string" or not r.startNodeId or not r.endNodeId then return nil, "invalid_root" end
        local ix = index()
        if not ix[r.rootId] then M.LIST[#M.LIST + 1] = r else
            for i, x in ipairs(M.LIST) do if x.rootId == r.rootId then M.LIST[i] = r end end
        end
        ix[r.rootId] = r
        return r
    end

    function M.unregister(rootId)
        local ix = index()
        if not ix[rootId] then return false end
        ix[rootId] = nil
        for i, x in ipairs(M.LIST) do if x.rootId == rootId then table.remove(M.LIST, i); break end end
        return true
    end

    function M.count() return #M.LIST end

    return M
end)
