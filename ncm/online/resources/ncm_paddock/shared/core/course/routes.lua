-- ncm-core module: course.routes
-- Resolves a root (start/finish node ids) into a route with coordinates and a planar distance.
-- Authored gates/sectors arrive with M3.2 courses; this is the data every calendar slot needs.
local Core = NcmCore

Core.define("course.routes", function(C)
    local M = { version = "0.0.1" }
    local nodes = C.get("data.nodes")
    local roots = C.get("data.roots")

    function M.planarDistance(a, b)
        local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
        return math.sqrt(dx * dx + dy * dy)
    end

    --- Resolve a rootId. Returns route or nil, reason.
    function M.resolve(rootId, label)
        local root = roots.byId(rootId)
        if not root then return nil, "unknown_root" end
        local start = nodes.byId(root.startNodeId)
        local finish = nodes.byId(root.endNodeId)
        if not start or not finish then return nil, "missing_node" end
        -- an authored route carries its intermediate gates and its path length (the sum of legs), not the crow-flies
        local distance = M.planarDistance(start, finish)
        if root.intermediate and #root.intermediate > 0 then
            distance = 0
            local prev = start
            for _, p in ipairs(root.intermediate) do distance = distance + M.planarDistance(prev, p); prev = p end
            distance = distance + M.planarDistance(prev, finish)
        end
        return {
            routeId = rootId,
            name = label or root.displayName or rootId,
            start = start,
            finish = finish,
            region = start.region or finish.region or "Unknown",
            finishRegion = finish.region or start.region or "Unknown",
            distanceM = distance,
            recommendedMode = root.recommendedMode,
            intermediate = root.intermediate,
            disciplineId = root.disciplineId,
            laps = root.laps,
            custom = root.custom or nil,
            description = root.description,
        }
    end

    return M
end)
