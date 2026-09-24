local GridSolver = {}

GridSolver.STATUS = {
    SUCCESS = "success",
    DEGRADED = "degraded_success",
    FAILURE = "failure",
}

GridSolver.FORMATION = {
    DOUBLE_FILE = "double_file",
    COMPRESSED_DOUBLE_FILE = "compressed_double_file",
    SINGLE_FILE = "single_file",
    SIDEBYSIDE = "sidebyside",
}

GridSolver.REASON = {
    NO_VALID_GRID = "NO_VALID_GRID",
}

local DEFAULTS = {
    genericVehicleWidth = 2.25,
    genericVehicleLength = 5.20,
    lateralMargin = 0.60,
    minimumRoadWidth = 8.00,
    urbanRoadWidth = 11.00,
    openRoadWidth = 13.50,
    minCorridorLength = 48.00,
    maxCorridorLength = 120.00,
    trafficCorridorFactor = 0.85,
    maxDoubleFileGrade = 0.08,
    maxCompressedGrade = 0.11,
    maxSingleFileGrade = 0.16,
}

local SOLVER_LOG_ENABLED = true

local function solverFormatNumber(value, precision)
    local numeric = tonumber(value)
    if numeric == nil then
        return tostring(value)
    end
    return string.format("%." .. tostring(precision or 2) .. "f", numeric)
end

local function solverPositionSummary(position)
    if type(position) ~= "table" then
        return tostring(position)
    end
    return string.format(
        "(x=%s y=%s z=%s h=%s long=%s lat=%s row=%s col=%s)",
        solverFormatNumber(position.x, 2),
        solverFormatNumber(position.y, 2),
        solverFormatNumber(position.z, 2),
        solverFormatNumber(position.heading, 2),
        solverFormatNumber(position.longitudinalOffset, 2),
        solverFormatNumber(position.lateralOffset, 2),
        tostring(position.row),
        tostring(position.col))
end

local function solverSpecSummary(spec)
    if type(spec) ~= "table" then
        return tostring(spec)
    end
    return string.format(
        "{tag=%s formation=%s layout=%s rowSpacing=%s colOffset=%s startSetback=%s maxGrade=%s}",
        tostring(spec.tag),
        tostring(spec.formation),
        tostring(spec.layout),
        solverFormatNumber(spec.rowSpacing, 2),
        solverFormatNumber(spec.colOffset, 2),
        solverFormatNumber(spec.startSetback, 2),
        solverFormatNumber(spec.maxRouteGrade, 3))
end

local function solverAttemptSummary(attempt)
    if type(attempt) ~= "table" then
        return tostring(attempt)
    end
    return string.format(
        "{tag=%s formation=%s valid=%s reason=%s}",
        tostring(attempt.tag),
        tostring(attempt.formation),
        tostring(attempt.valid == true),
        tostring(attempt.reason))
end

local function solverContextSummary(context)
    if type(context) ~= "table" then
        return ""
    end
    local parts = {
        "startType=" .. tostring(context.startType or "grid"),
        "raceType=" .. tostring(context.raceType or "sprint"),
        "count=" .. tostring(context.count or 0),
    }
    if context.routeId ~= nil then
        parts[#parts + 1] = "route=" .. tostring(context.routeId)
    end
    if context.stageSource ~= nil then
        parts[#parts + 1] = "source=" .. tostring(context.stageSource)
    end
    return table.concat(parts, " ")
end

local function solverLog(context, fmt, ...)
    if not SOLVER_LOG_ENABLED then
        return
    end

    local prefix = "[NCM/GridSolver]"
    local contextSummary = solverContextSummary(context)
    if contextSummary ~= "" then
        prefix = prefix .. " " .. contextSummary
    end

    local ok, line = pcall(string.format, prefix .. " " .. tostring(fmt), ...)
    if ok then
        pcall(print, line)
        return
    end

    local parts = {
        prefix .. " format_error",
        " fmt=", tostring(fmt),
        " err=", tostring(line),
    }
    local argc = select("#", ...)
    for i = 1, argc do
        parts[#parts + 1] = " arg"
        parts[#parts + 1] = tostring(i)
        parts[#parts + 1] = "="
        parts[#parts + 1] = tostring(select(i, ...))
    end
    pcall(print, table.concat(parts))
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0.0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function cloneArray(values)
    local out = {}
    if type(values) ~= "table" then
        return out
    end
    for i, value in ipairs(values) do
        out[i] = value
    end
    return out
end

local function joinReasons(reasons)
    if type(reasons) ~= "table" or #reasons == 0 then
        return nil
    end
    return table.concat(reasons, ",")
end

local function planarDistance(a, b)
    if not a or not b then return 0.0 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return math.sqrt((dx * dx) + (dy * dy))
end

local function estimateRouteGrade(context)
    local startNode = context and context.startNode or nil
    local finishNode = context and context.finishNode or nil
    local distance2d = planarDistance(startNode, finishNode)
    local dz = math.abs((finishNode and finishNode.z or 0) - (startNode and startNode.z or 0))
    if distance2d < 0.1 then
        solverLog(
            context,
            "grid_solver_grade distance2d=%s dz=%s grade=0.0000 reason=short_distance start=%s finish=%s",
            solverFormatNumber(distance2d, 2),
            solverFormatNumber(dz, 2),
            solverPositionSummary(startNode),
            solverPositionSummary(finishNode))
        return 0.0
    end
    local grade = dz / distance2d
    solverLog(
        context,
        "grid_solver_grade distance2d=%s dz=%s grade=%s start=%s finish=%s",
        solverFormatNumber(distance2d, 2),
        solverFormatNumber(dz, 2),
        solverFormatNumber(grade, 4),
        solverPositionSummary(startNode),
        solverPositionSummary(finishNode))
    return grade
end

local function estimateRoadWidth(context)
    local startNode = context and context.startNode or nil
    local explicitWidth = tonumber(context and context.estimatedRoadWidthM or nil)
        or tonumber(startNode and (startNode.roadWidthM or startNode.startWidthM) or nil)
    if explicitWidth and explicitWidth > 0.0 then
        solverLog(
            context,
            "grid_solver_road_width value=%s source=explicit startNode=%s",
            solverFormatNumber(explicitWidth, 2),
            tostring(startNode and startNode.name or "?"))
        return explicitWidth, "explicit"
    end
    if startNode and startNode.road == false then
        solverLog(
            context,
            "grid_solver_road_width value=%s source=non_road_default startNode=%s",
            solverFormatNumber(DEFAULTS.minimumRoadWidth, 2),
            tostring(startNode and startNode.name or "?"))
        return DEFAULTS.minimumRoadWidth, "non_road_default"
    end
    if startNode and startNode.urban == false then
        solverLog(
            context,
            "grid_solver_road_width value=%s source=open_road_default startNode=%s",
            solverFormatNumber(DEFAULTS.openRoadWidth, 2),
            tostring(startNode and startNode.name or "?"))
        return DEFAULTS.openRoadWidth, "open_road_default"
    end
    solverLog(
        context,
        "grid_solver_road_width value=%s source=urban_default startNode=%s",
        solverFormatNumber(DEFAULTS.urbanRoadWidth, 2),
        tostring(startNode and startNode.name or "?"))
    return DEFAULTS.urbanRoadWidth, "urban_default"
end

local function estimateCorridorLength(context)
    local clearRadius = tonumber(context and context.trafficClearRadius or nil)
    if context and context.trafficPrepared and clearRadius and clearRadius > 0.0 then
        local corridor = clamp(clearRadius * DEFAULTS.trafficCorridorFactor, DEFAULTS.minCorridorLength, DEFAULTS.maxCorridorLength)
        solverLog(
            context,
            "grid_solver_corridor value=%s source=traffic_clear_radius clearRadius=%s factor=%s",
            solverFormatNumber(corridor, 2),
            solverFormatNumber(clearRadius, 2),
            solverFormatNumber(DEFAULTS.trafficCorridorFactor, 2))
        return corridor
    end
    solverLog(
        context,
        "grid_solver_corridor value=%s source=max_default trafficPrepared=%s clearRadius=%s",
        solverFormatNumber(DEFAULTS.maxCorridorLength, 2),
        tostring(context and context.trafficPrepared == true),
        solverFormatNumber(clearRadius, 2))
    return DEFAULTS.maxCorridorLength
end

local function getWholeGridSlotOrdinal(entry, fallbackIndex, playerGridPos)
    local slotOrdinal = tonumber(entry and entry.gridPos or fallbackIndex) or fallbackIndex or 1
    if playerGridPos and slotOrdinal >= playerGridPos then
        slotOrdinal = slotOrdinal + 1
    end
    return math.max(1, math.floor(slotOrdinal))
end

local function getSideBySideLaneIndex(entry, fallbackIndex, playerGridPos, context)
    local dragStrip = context and context.dragStrip or nil
    local laneIndexByGridPos = dragStrip and dragStrip.laneIndexByGridPos or nil
    if type(laneIndexByGridPos) == "table" then
        local gridPos = tonumber(entry and entry.gridPos or fallbackIndex) or fallbackIndex or 1
        local laneIndex = tonumber(laneIndexByGridPos[math.max(1, math.floor(gridPos))] or nil)
        local playerLaneIndex = playerGridPos and tonumber(laneIndexByGridPos[math.max(1, math.floor(playerGridPos))] or nil) or nil
        if laneIndex and playerLaneIndex then
            return laneIndex, playerLaneIndex
        end
    end
    return getWholeGridSlotOrdinal(entry, fallbackIndex, playerGridPos), playerGridPos
end

local function getGridRowCol(slotOrdinal)
    local ordinal = math.max(1, math.floor(slotOrdinal or 1))
    local row = math.ceil(ordinal / 2) - 1
    local col = (ordinal % 2 == 0) and 1 or -1
    return row, col
end

local function buildPosition(context, longitudinalOffset, lateralOffset, row, col, tag)
    local heading = context and (context.slotHeading or context.heading) or 0.0
    local forwardX = context and context.forwardX or 1.0
    local forwardY = context and context.forwardY or 0.0
    local rightX = context and context.rightX or 0.0
    local rightY = context and context.rightY or 1.0
    local startNode = context and context.startNode or {}
    local baseZ = tonumber(context and context.baseZ or nil) or (startNode.z or 0)
    local position = {
        x = (startNode.x or 0) + longitudinalOffset * forwardX + lateralOffset * rightX,
        y = (startNode.y or 0) + longitudinalOffset * forwardY + lateralOffset * rightY,
        z = baseZ,
        heading = heading,
        longitudinalOffset = longitudinalOffset,
        lateralOffset = lateralOffset,
        row = row,
        col = col,
        formationTag = tag,
    }
    solverLog(
        context,
        "grid_solver_position tag=%s row=%s col=%s long=%s lat=%s pos=%s",
        tostring(tag),
        tostring(row),
        tostring(col),
        solverFormatNumber(longitudinalOffset, 2),
        solverFormatNumber(lateralOffset, 2),
        solverPositionSummary(position))
    return position
end

local function buildCandidateSpecs(context)
    local spacing = context and context.spacing or {}
    local startType = tostring(context and context.startType or "grid")
    local raceType = tostring(context and context.raceType or "sprint")
    local dragStrip = context and context.dragStrip or nil
    local gridRowSpacing = tonumber(spacing.gridRowSpacing or 12.0) or 12.0
    local rollingRowSpacing = tonumber(spacing.rollingRowSpacing or gridRowSpacing) or gridRowSpacing
    local gridColOffset = tonumber(spacing.gridColOffset or 4.0) or 4.0
    local startSetback = tonumber(spacing.gridStartSetback or 12.0) or 12.0
    local sideBySideSpacing = tonumber(spacing.sideBySideSpacing or 6.0) or 6.0
    local sideBySideSetback = tonumber(spacing.sideBySideSetback or 18.0) or 18.0

    if startType == "sidebyside" then
        if raceType == "drag" then
            local specs = {
                {
                    tag = "requested_drag_sidebyside",
                    formation = GridSolver.FORMATION.SIDEBYSIDE,
                    layout = "sidebyside",
                    rowSpacing = 0.0,
                    colOffset = tonumber(dragStrip and dragStrip.laneCenterSpacingM or sideBySideSpacing) or sideBySideSpacing,
                    startSetback = tonumber(dragStrip and dragStrip.startSetbackM or sideBySideSetback) or sideBySideSetback,
                    maxRouteGrade = tonumber(dragStrip and dragStrip.maxRouteGrade or DEFAULTS.maxDoubleFileGrade) or DEFAULTS.maxDoubleFileGrade,
                },
            }
            solverLog(context, "grid_solver_specs count=%d requestedStartType=%s requestedRaceType=%s", #specs, tostring(startType), tostring(raceType))
            for index, spec in ipairs(specs) do
                solverLog(context, "grid_solver_spec index=%d spec=%s", index, solverSpecSummary(spec))
            end
            return specs
        end
        local specs = {
            {
                tag = "requested_sidebyside",
                formation = GridSolver.FORMATION.SIDEBYSIDE,
                layout = "sidebyside",
                rowSpacing = 0.0,
                colOffset = sideBySideSpacing,
                startSetback = sideBySideSetback,
                maxRouteGrade = DEFAULTS.maxDoubleFileGrade,
            },
            {
                tag = "sidebyside_single_file_fallback",
                formation = GridSolver.FORMATION.SINGLE_FILE,
                layout = "single_file",
                rowSpacing = math.max(10.0, gridRowSpacing * 0.9),
                colOffset = 0.0,
                startSetback = math.max(8.0, startSetback * 0.75),
                maxRouteGrade = DEFAULTS.maxSingleFileGrade,
            },
        }
        solverLog(context, "grid_solver_specs count=%d requestedStartType=%s requestedRaceType=%s", #specs, tostring(startType), tostring(raceType))
        for index, spec in ipairs(specs) do
            solverLog(context, "grid_solver_spec index=%d spec=%s", index, solverSpecSummary(spec))
        end
        return specs
    end

    local requestedRowSpacing = startType == "rolling" and rollingRowSpacing or gridRowSpacing

    if startType == "rolling" then
        local specs = {
            {
                tag = "requested_rolling_double_file",
                formation = GridSolver.FORMATION.DOUBLE_FILE,
                layout = "double_file",
                rowSpacing = requestedRowSpacing,
                colOffset = gridColOffset,
                startSetback = startSetback,
                maxRouteGrade = DEFAULTS.maxDoubleFileGrade,
            },
            {
                tag = "compressed_rolling_double_file",
                formation = GridSolver.FORMATION.COMPRESSED_DOUBLE_FILE,
                layout = "double_file",
                rowSpacing = math.max(9.5, requestedRowSpacing * 0.85),
                colOffset = math.max(3.0, gridColOffset * 0.80),
                startSetback = math.max(10.0, startSetback * 0.80),
                maxRouteGrade = DEFAULTS.maxCompressedGrade,
            },
            {
                tag = "rolling_single_file_fallback",
                formation = GridSolver.FORMATION.SINGLE_FILE,
                layout = "single_file",
                rowSpacing = math.max(10.0, requestedRowSpacing * 0.90),
                colOffset = 0.0,
                startSetback = math.max(8.0, startSetback * 0.75),
                maxRouteGrade = DEFAULTS.maxSingleFileGrade,
            },
        }
        solverLog(context, "grid_solver_specs count=%d requestedStartType=%s requestedRaceType=%s", #specs, tostring(startType), tostring(raceType))
        for index, spec in ipairs(specs) do
            solverLog(context, "grid_solver_spec index=%d spec=%s", index, solverSpecSummary(spec))
        end
        return specs
    end

    local specs = {
        {
            tag = "requested_double_file",
            formation = GridSolver.FORMATION.DOUBLE_FILE,
            layout = "double_file",
            rowSpacing = requestedRowSpacing,
            colOffset = gridColOffset,
            startSetback = startSetback,
            maxRouteGrade = DEFAULTS.maxDoubleFileGrade,
        },
        {
            tag = "compressed_double_file",
            formation = GridSolver.FORMATION.COMPRESSED_DOUBLE_FILE,
            layout = "double_file",
            rowSpacing = math.max(9.5, requestedRowSpacing * 0.85),
            colOffset = math.max(3.0, gridColOffset * 0.80),
            startSetback = math.max(10.0, startSetback * 0.80),
            maxRouteGrade = DEFAULTS.maxCompressedGrade,
        },
        {
            tag = "single_file_fallback",
            formation = GridSolver.FORMATION.SINGLE_FILE,
            layout = "single_file",
            rowSpacing = math.max(10.0, requestedRowSpacing * 0.90),
            colOffset = 0.0,
            startSetback = math.max(8.0, startSetback * 0.75),
            maxRouteGrade = DEFAULTS.maxSingleFileGrade,
        },
    }
    solverLog(context, "grid_solver_specs count=%d requestedStartType=%s requestedRaceType=%s", #specs, tostring(startType), tostring(raceType))
    for index, spec in ipairs(specs) do
        solverLog(context, "grid_solver_spec index=%d spec=%s", index, solverSpecSummary(spec))
    end
    return specs
end

local function generateCandidatePositions(context, spec)
    local positions = {}
    local slots = {}
    local count = tonumber(context and context.count or 0) or 0
    local field = context and context.field or nil
    local playerGridPos = tonumber(context and context.playerGridPos or nil)
    local layout = spec and spec.layout or "double_file"
    local rowSpacing = tonumber(spec and spec.rowSpacing or 12.0) or 12.0
    local colOffset = tonumber(spec and spec.colOffset or 0.0) or 0.0
    local startSetback = tonumber(spec and spec.startSetback or 12.0) or 12.0
    solverLog(
        context,
        "grid_solver_candidate_begin spec=%s playerGridPos=%s count=%d",
        solverSpecSummary(spec),
        tostring(playerGridPos),
        tonumber(count or 0))

    local function addSlot(index, longitudinalOffset, lateralOffset, row, col)
        local position = buildPosition(context, longitudinalOffset, lateralOffset, row, col, spec and spec.tag or nil)
        positions[index] = position
        slots[index] = {
            index = index,
            valid = true,
            reason = nil,
            reasons = {},
            tag = spec and spec.tag or nil,
            formation = spec and spec.formation or nil,
            position = position,
        }
        solverLog(
            context,
            "grid_solver_candidate_slot spec=%s slot=%d row=%s col=%s pos=%s",
            tostring(spec and spec.tag or "?"),
            tonumber(index or 0),
            tostring(row),
            tostring(col),
            solverPositionSummary(position))
    end

    if layout == "sidebyside" then
        local playerOrdinal = playerGridPos and math.max(1, math.floor(playerGridPos)) or nil
        for i = 1, count do
            local entry = field and field[i] or nil
            if playerOrdinal then
                local laneIndex, playerLaneIndex = getSideBySideLaneIndex(entry, i, playerOrdinal, context)
                local laneDelta = laneIndex - playerLaneIndex
                local lateralDelta = laneDelta * colOffset
                addSlot(i, 0.0, lateralDelta, 0, laneDelta)
            else
                local lateralOffset = (i - ((count + 1) / 2)) * colOffset
                addSlot(i, -startSetback, lateralOffset, 0, i)
            end
        end
        solverLog(context, "grid_solver_candidate_complete spec=%s generated=%d layout=%s", tostring(spec and spec.tag or "?"), #positions, tostring(layout))
        return positions, slots
    end

    if layout == "single_file" then
        local playerRow = playerGridPos and (math.max(1, math.floor(playerGridPos)) - 1) or nil
        for i = 1, count do
            local entry = field and field[i] or nil
            if playerRow ~= nil then
                local wholeOrdinal = getWholeGridSlotOrdinal(entry, i, playerGridPos)
                local row = math.max(0, wholeOrdinal - 1)
                local longitudinalOffset = -(row - playerRow) * rowSpacing
                addSlot(i, longitudinalOffset, 0.0, row, 0)
            else
                local row = i - 1
                local backOffset = -(startSetback + rowSpacing * row)
                addSlot(i, backOffset, 0.0, row, 0)
            end
        end
        solverLog(context, "grid_solver_candidate_complete spec=%s generated=%d layout=%s", tostring(spec and spec.tag or "?"), #positions, tostring(layout))
        return positions, slots
    end

    local playerRow, playerCol = nil, nil
    if playerGridPos then
        playerRow, playerCol = getGridRowCol(playerGridPos)
    end
    for i = 1, count do
        local entry = field and field[i] or nil
        if playerRow ~= nil then
            local wholeOrdinal = getWholeGridSlotOrdinal(entry, i, playerGridPos)
            local row, col = getGridRowCol(wholeOrdinal)
            local longitudinalOffset = -(row - playerRow) * rowSpacing
            local lateralOffset = (col - playerCol) * colOffset
            addSlot(i, longitudinalOffset, lateralOffset, row, col)
        else
            local row = math.ceil(i / 2) - 1
            local col = (i % 2 == 0) and 1 or -1
            local backOffset = -(startSetback + rowSpacing * row)
            local sideOffset = col * colOffset
            addSlot(i, backOffset, sideOffset, row, col)
        end
    end

    solverLog(context, "grid_solver_candidate_complete spec=%s generated=%d layout=%s", tostring(spec and spec.tag or "?"), #positions, tostring(layout))
    return positions, slots
end

local function measureCandidate(positions)
    local minLongitudinal = 0.0
    local maxLongitudinal = 0.0
    local minLateral = 0.0
    local maxLateral = 0.0
    for _, position in ipairs(positions or {}) do
        local longitudinalOffset = tonumber(position and position.longitudinalOffset or 0.0) or 0.0
        local lateralOffset = tonumber(position and position.lateralOffset or 0.0) or 0.0
        if longitudinalOffset < minLongitudinal then
            minLongitudinal = longitudinalOffset
        end
        if longitudinalOffset > maxLongitudinal then
            maxLongitudinal = longitudinalOffset
        end
        if lateralOffset < minLateral then
            minLateral = lateralOffset
        end
        if lateralOffset > maxLateral then
            maxLateral = lateralOffset
        end
    end
    local metrics = {
        totalLength = (maxLongitudinal - minLongitudinal) + DEFAULTS.genericVehicleLength,
        lateralSpan = (maxLateral - minLateral) + DEFAULTS.genericVehicleWidth,
        minLongitudinal = minLongitudinal,
        maxLongitudinal = maxLongitudinal,
        minLateral = minLateral,
        maxLateral = maxLateral,
    }
    solverLog(
        nil,
        "grid_solver_metrics totalLength=%s lateralSpan=%s minLong=%s maxLong=%s minLat=%s maxLat=%s count=%d",
        solverFormatNumber(metrics.totalLength, 2),
        solverFormatNumber(metrics.lateralSpan, 2),
        solverFormatNumber(metrics.minLongitudinal, 2),
        solverFormatNumber(metrics.maxLongitudinal, 2),
        solverFormatNumber(metrics.minLateral, 2),
        solverFormatNumber(metrics.maxLateral, 2),
        #(positions or {}))
    return metrics
end

local function validateCandidate(context, spec, positions, slots)
    local reasons = {}
    local perSlotReasons = {}
    local dragStrip = context and context.dragStrip or nil
    local routeGrade = estimateRouteGrade(context)
    local estimatedRoadWidthM, roadWidthSource = estimateRoadWidth(context)
    if dragStrip and tonumber(dragStrip.estimatedRoadWidthM) then
        estimatedRoadWidthM = tonumber(dragStrip.estimatedRoadWidthM)
        roadWidthSource = dragStrip.estimatedRoadWidthSource or roadWidthSource
    end
    local corridorLengthM = estimateCorridorLength(context)
    if dragStrip and tonumber(dragStrip.corridorLengthM) then
        corridorLengthM = tonumber(dragStrip.corridorLengthM)
    end
    local metrics = measureCandidate(positions)
    solverLog(
        context,
        "grid_solver_validate_begin spec=%s routeGrade=%s roadWidth=%s roadWidthSource=%s corridor=%s metricsLength=%s metricsWidth=%s",
        solverSpecSummary(spec),
        solverFormatNumber(routeGrade, 4),
        solverFormatNumber(estimatedRoadWidthM, 2),
        tostring(roadWidthSource),
        solverFormatNumber(corridorLengthM, 2),
        solverFormatNumber(metrics.totalLength, 2),
        solverFormatNumber(metrics.lateralSpan, 2))

    if routeGrade > tonumber(spec and spec.maxRouteGrade or DEFAULTS.maxSingleFileGrade) then
        reasons[#reasons + 1] = "slope_too_severe"
        solverLog(context, "grid_solver_validate_reason spec=%s reason=slope_too_severe routeGrade=%s maxAllowed=%s",
            tostring(spec and spec.tag or "?"),
            solverFormatNumber(routeGrade, 4),
            solverFormatNumber(spec and spec.maxRouteGrade or DEFAULTS.maxSingleFileGrade, 4))
    end
    if dragStrip and tonumber(dragStrip.supportedLaneCount or 0) > 0 and (#positions + 1) > tonumber(dragStrip.supportedLaneCount or 0) then
        reasons[#reasons + 1] = "drag_lane_capacity_exceeded"
        solverLog(context, "grid_solver_validate_reason spec=%s reason=drag_lane_capacity_exceeded supported=%s requested=%s",
            tostring(spec and spec.tag or "?"),
            tostring(dragStrip and dragStrip.supportedLaneCount or "?"),
            tostring(#positions + 1))
    end
    if metrics.lateralSpan + (DEFAULTS.lateralMargin * 2.0) > estimatedRoadWidthM then
        reasons[#reasons + 1] = "road_too_narrow_estimate"
        solverLog(context, "grid_solver_validate_reason spec=%s reason=road_too_narrow_estimate required=%s available=%s",
            tostring(spec and spec.tag or "?"),
            solverFormatNumber(metrics.lateralSpan + (DEFAULTS.lateralMargin * 2.0), 2),
            solverFormatNumber(estimatedRoadWidthM, 2))
    end
    if metrics.totalLength > corridorLengthM then
        reasons[#reasons + 1] = "grid_too_long_for_clear_zone"
        solverLog(context, "grid_solver_validate_reason spec=%s reason=grid_too_long_for_clear_zone required=%s available=%s",
            tostring(spec and spec.tag or "?"),
            solverFormatNumber(metrics.totalLength, 2),
            solverFormatNumber(corridorLengthM, 2))
    end

    local minLongitudinalGap = DEFAULTS.genericVehicleLength + 0.25
    local minLateralGap = DEFAULTS.genericVehicleWidth + 0.25
    for i = 1, #positions do
        perSlotReasons[i] = {}
    end

    for i = 1, #positions do
        local left = positions[i]
        for j = i + 1, #positions do
            local right = positions[j]
            local longitudinalDelta = math.abs((left.longitudinalOffset or 0.0) - (right.longitudinalOffset or 0.0))
            local lateralDelta = math.abs((left.lateralOffset or 0.0) - (right.lateralOffset or 0.0))
            if longitudinalDelta < minLongitudinalGap and lateralDelta < minLateralGap then
                reasons[#reasons + 1] = "spacing_conflict"
                perSlotReasons[i][#perSlotReasons[i] + 1] = "spacing_conflict"
                perSlotReasons[j][#perSlotReasons[j] + 1] = "spacing_conflict"
                solverLog(
                    context,
                    "grid_solver_validate_reason spec=%s reason=spacing_conflict left=%d right=%d longDelta=%s latDelta=%s minLong=%s minLat=%s",
                    tostring(spec and spec.tag or "?"),
                    tonumber(i or 0),
                    tonumber(j or 0),
                    solverFormatNumber(longitudinalDelta, 2),
                    solverFormatNumber(lateralDelta, 2),
                    solverFormatNumber(minLongitudinalGap, 2),
                    solverFormatNumber(minLateralGap, 2))
            end
        end
    end

    local valid = #reasons == 0
    for i, slot in ipairs(slots or {}) do
        if valid then
            slot.valid = true
            slot.reason = nil
            slot.reasons = {}
            solverLog(context, "grid_solver_slot_validation spec=%s slot=%d valid=true reasons=none pos=%s",
                tostring(spec and spec.tag or "?"),
                tonumber(i or 0),
                solverPositionSummary(slot.position))
        else
            local slotReasons = perSlotReasons[i]
            if #slotReasons == 0 then
                slotReasons = cloneArray(reasons)
            end
            slot.valid = false
            slot.reason = slotReasons[1]
            slot.reasons = slotReasons
            solverLog(context, "grid_solver_slot_validation spec=%s slot=%d valid=false reason=%s reasons=%s pos=%s",
                tostring(spec and spec.tag or "?"),
                tonumber(i or 0),
                tostring(slot.reason),
                tostring(joinReasons(slotReasons)),
                solverPositionSummary(slot.position))
        end
    end

    local result = {
        valid = valid,
        reasons = reasons,
        reason = joinReasons(reasons),
        routeGrade = routeGrade,
        estimatedRoadWidthM = estimatedRoadWidthM,
        estimatedRoadWidthSource = roadWidthSource,
        corridorLengthM = corridorLengthM,
        metrics = metrics,
        positions = positions,
        slots = slots,
    }
    solverLog(
        context,
        "grid_solver_validate_complete spec=%s valid=%s reason=%s reasons=%s",
        tostring(spec and spec.tag or "?"),
        tostring(valid == true),
        tostring(result.reason),
        tostring(joinReasons(reasons)))
    return result
end

local function buildResult(context, specs, selectedSpec, validation, attempts, degraded, legacyFallback)
    local requestedFormation = specs[1] and specs[1].formation or GridSolver.FORMATION.DOUBLE_FILE
    local requestedStartType = tostring(context and context.startType or "grid")
    local dragStrip = context and context.dragStrip or nil
    local resultValid = validation and validation.valid == true and legacyFallback ~= true
    local resultSlots = {}
    for i, slot in ipairs(validation and validation.slots or {}) do
        resultSlots[i] = {
            index = slot.index,
            valid = legacyFallback and false or slot.valid,
            reason = legacyFallback and "legacy_fallback_unvalidated" or slot.reason,
            reasons = legacyFallback and { "legacy_fallback_unvalidated" } or cloneArray(slot.reasons),
            tag = slot.tag,
            formation = slot.formation,
            position = slot.position,
        }
    end
    local result = {
        status = legacyFallback and GridSolver.STATUS.DEGRADED or GridSolver.STATUS.SUCCESS,
        valid = resultValid == true,
        degraded = degraded or legacyFallback,
        legacyFallback = legacyFallback == true,
        probeMode = "heuristic_only",
        trafficPrepared = context and context.trafficPrepared == true,
        requestedStartType = requestedStartType,
        requestedFormation = requestedFormation,
        finalFormation = selectedSpec and selectedSpec.formation or requestedFormation,
        reason = legacyFallback and (validation and validation.reason or "legacy_fallback_unvalidated") or (degraded and attempts[1] and attempts[1].reason or nil),
        positions = validation and validation.positions or {},
        slots = resultSlots,
        attempts = attempts or {},
        routeGrade = validation and validation.routeGrade or 0.0,
        estimatedRoadWidthM = validation and validation.estimatedRoadWidthM or nil,
        estimatedRoadWidthSource = validation and validation.estimatedRoadWidthSource or nil,
        corridorLengthM = validation and validation.corridorLengthM or nil,
        metrics = validation and validation.metrics or nil,
        supportedLaneCount = dragStrip and dragStrip.supportedLaneCount or nil,
        effectiveLaneCount = dragStrip and dragStrip.effectiveLaneCount or nil,
        fieldSizeReduced = dragStrip and dragStrip.fieldSizeReduced == true or false,
    }
    solverLog(
        context,
        "grid_solver_result status=%s valid=%s degraded=%s legacy=%s requested=%s final=%s reason=%s attempts=%d",
        tostring(result.status),
        tostring(result.valid == true),
        tostring(result.degraded == true),
        tostring(result.legacyFallback == true),
        tostring(result.requestedFormation),
        tostring(result.finalFormation),
        tostring(result.reason),
        #(attempts or {}))
    for index, attempt in ipairs(attempts or {}) do
        solverLog(context, "grid_solver_result_attempt index=%d attempt=%s", index, solverAttemptSummary(attempt))
    end
    for index, slot in ipairs(resultSlots) do
        solverLog(
            context,
            "grid_solver_result_slot index=%d valid=%s reason=%s tag=%s formation=%s pos=%s",
            tonumber(index or 0),
            tostring(slot.valid == true),
            tostring(slot.reason),
            tostring(slot.tag),
            tostring(slot.formation),
            solverPositionSummary(slot.position))
    end
    return result
end

local function buildFailureResult(context, specs, validation, attempts, reasonOverride)
    local requestedFormation = specs[1] and specs[1].formation or GridSolver.FORMATION.SIDEBYSIDE
    local requestedStartType = tostring(context and context.startType or "grid")
    local dragStrip = context and context.dragStrip or nil
    local result = {
        status = GridSolver.STATUS.FAILURE,
        valid = false,
        degraded = false,
        legacyFallback = false,
        probeMode = "heuristic_only",
        trafficPrepared = context and context.trafficPrepared == true,
        requestedStartType = requestedStartType,
        requestedFormation = requestedFormation,
        finalFormation = requestedFormation,
        reason = reasonOverride or validation and validation.reason or (attempts[1] and attempts[1].reason) or "drag_sidebyside_invalid",
        positions = {},
        slots = nil,
        attempts = attempts or {},
        routeGrade = validation and validation.routeGrade or 0.0,
        estimatedRoadWidthM = validation and validation.estimatedRoadWidthM or nil,
        estimatedRoadWidthSource = validation and validation.estimatedRoadWidthSource or nil,
        corridorLengthM = validation and validation.corridorLengthM or nil,
        metrics = validation and validation.metrics or nil,
        supportedLaneCount = dragStrip and dragStrip.supportedLaneCount or nil,
        effectiveLaneCount = dragStrip and dragStrip.effectiveLaneCount or nil,
        fieldSizeReduced = dragStrip and dragStrip.fieldSizeReduced == true or false,
    }
    solverLog(
        context,
        "grid_solver_failure status=%s reason=%s requested=%s final=%s attempts=%d validationReason=%s",
        tostring(result.status),
        tostring(result.reason),
        tostring(result.requestedFormation),
        tostring(result.finalFormation),
        #(attempts or {}),
        tostring(validation and validation.reason))
    for index, attempt in ipairs(attempts or {}) do
        solverLog(context, "grid_solver_failure_attempt index=%d attempt=%s", index, solverAttemptSummary(attempt))
    end
    return result
end

function GridSolver.init()
end

function GridSolver.solveFormation(context)
    solverLog(
        context,
        "grid_solver_begin startNode=%s finishNode=%s playerGridPos=%s trafficPrepared=%s clearRadius=%s",
        solverPositionSummary(context and context.startNode),
        solverPositionSummary(context and context.finishNode),
        tostring(context and context.playerGridPos),
        tostring(context and context.trafficPrepared == true),
        solverFormatNumber(context and context.trafficClearRadius, 2))
    local specs = buildCandidateSpecs(context)
    local attempts = {}
    local isDrag = tostring(context and context.raceType or "sprint") == "drag"

    for index, spec in ipairs(specs) do
        solverLog(context, "grid_solver_attempt_begin index=%d spec=%s", index, solverSpecSummary(spec))
        local positions, slots = generateCandidatePositions(context, spec)
        local validation = validateCandidate(context, spec, positions, slots)
        attempts[#attempts + 1] = {
            tag = spec.tag,
            formation = spec.formation,
            valid = validation.valid,
            reason = validation.reason,
        }
        solverLog(
            context,
            "grid_solver_attempt_complete index=%d spec=%s valid=%s reason=%s",
            index,
            tostring(spec.tag),
            tostring(validation.valid == true),
            tostring(validation.reason))
        if validation.valid then
            solverLog(context, "grid_solver_accept index=%d spec=%s degraded=%s", index, tostring(spec.tag), tostring(index > 1))
            return buildResult(context, specs, spec, validation, attempts, index > 1, false)
        end
    end

    if isDrag then
        local failedSpec = specs[1]
        local positions, slots = generateCandidatePositions(context, failedSpec)
        local validation = validateCandidate(context, failedSpec, positions, slots)
        solverLog(context, "grid_solver_drag_failure spec=%s reason=%s", tostring(failedSpec and failedSpec.tag or "?"), tostring(validation and validation.reason))
        return buildFailureResult(context, specs, validation, attempts)
    end

    local fallbackSpec = specs[1]
    local positions, slots = generateCandidatePositions(context, fallbackSpec)
    local validation = validateCandidate(context, fallbackSpec, positions, slots)
    solverLog(
        context,
        "grid_solver_no_valid_grid spec=%s reason=%s override=%s",
        tostring(fallbackSpec and fallbackSpec.tag or "?"),
        tostring(validation and validation.reason),
        tostring(GridSolver.REASON.NO_VALID_GRID))
    return buildFailureResult(context, specs, validation, attempts, GridSolver.REASON.NO_VALID_GRID)
end

return GridSolver
