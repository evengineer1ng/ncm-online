-- ncm-core module: competition.discipline
-- Disciplines are the sporting vocabulary (L53): how a course is structured (adapter), what counts as finishing,
-- what incidents mean. Adapters turn a route into the flat gate list the race kernel runs (session.race only ever
-- sees a gate index and a `finish` kind): p2p (point to point), laps (ovals, P41/P45), lanes (drag, P44).
local Core = NcmCore

Core.define("competition.discipline", function(C)
    local M = { version = "0.0.1" }
    local Gates = C.get("course.gates")

    M.LIST = {
        { id = "street_sprint", name = "Street Sprint",   adapter = "p2p",   enabled = true,  contactM = 4.5, bands = { 2.0, 6.0, 12.0 }, tier = "street" },
        { id = "ncx_formula",   name = "NCX Formula",     adapter = "p2p",   enabled = true,  contactM = 4.0, bands = { 1.5, 5.0, 10.0 }, tier = "sanctioned" },
        { id = "oval",          name = "Oval",            adapter = "laps",  enabled = true,  contactM = 4.5, bands = { 1.5, 5.0, 10.0 }, tier = "both" },
        { id = "drag",          name = "Drag",            adapter = "lanes", enabled = true,  contactM = 4.0, bands = { 2.0, 6.0, 12.0 }, tier = "both" },
        { id = "time_attack",   name = "Time Attack",     adapter = "p2p",   enabled = true,  contactM = 4.5, bands = { 2.0, 6.0, 12.0 }, tier = "both" },
        { id = "knockout",      name = "Knockout",        adapter = "eliminations", enabled = false },
        { id = "endurance",     name = "Endurance",       adapter = "laps",  enabled = false },
        { id = "kart",          name = "Kart Cup",        adapter = "laps",  enabled = false },
        { id = "quad",          name = "Quad / Badlands", adapter = "p2p",   enabled = true,  contactM = 5.0, bands = { 2.5, 7.0, 14.0 }, tier = "street" },
        { id = "rally_stage",   name = "Rally Stage",     adapter = "p2p",   enabled = true,  contactM = 5.0, bands = { 2.5, 7.0, 14.0 }, tier = "both" },
        -- drift is a timed run with incidents for TW1 footage; judging (P?) comes later
        { id = "drift",         name = "Drift",           adapter = "p2p",   enabled = true,  contactM = 4.5, bands = { 2.0, 6.0, 12.0 }, tier = "both", judged = true },
    }

    local byId
    function M.byId(id)
        if not byId then
            byId = {}
            for _, d in ipairs(M.LIST) do byId[d.id] = d end
        end
        return byId[id]
    end

    function M.ids(enabledOnly)
        local out = {}
        for _, d in ipairs(M.LIST) do if not enabledOnly or d.enabled then out[#out + 1] = d.id end end
        return out
    end

    --- Incident rule overrides for a discipline (feeds competition.incidents rules).
    function M.incidentRules(id)
        local d = M.byId(id)
        if not d or not d.bands then return {} end
        return {
            contactM = d.contactM,
            bands = { { dv = d.bands[1], mult = 1 }, { dv = d.bands[2], mult = 2 }, { dv = d.bands[3], mult = 4 } },
        }
    end

    -- ------------------------------------------------------------------ point to point
    local function p2pCourse(route, opts)
        local gates, why = Gates.build(route, opts)
        if not gates then return nil, why end
        local len = 0
        for i = 2, #gates do len = len + math.sqrt((gates[i].x - gates[i - 1].x) ^ 2 + (gates[i].y - gates[i - 1].y) ^ 2) end
        return { adapter = "p2p", gates = gates, lengthM = len, laps = 1, gatesPerLap = #gates }
    end

    -- ------------------------------------------------------------------ laps (ovals)
    --- A lap template is a closed loop: start line = finish line, `gatesPerLap` intermediate lines around the ring
    --- (authored via opts.intermediate, or one back-straight gate at route.finish when none are authored).
    --- The flat list repeats the loop `laps` times; only the very last line is a `finish` (session.race unchanged).
    function M.ovalCourse(route, opts)
        opts = opts or {}
        local laps = math.max(1, math.floor(tonumber(opts.laps) or 3))
        local ring = { start = route.start, finish = route.start, name = route.name }
        local intermediate = opts.intermediate
        if not intermediate or #intermediate == 0 then
            intermediate = { { x = route.finish.x, y = route.finish.y, z = route.finish.z, name = (route.finish.name or "back straight") } }
        end
        local template, why = Gates.build(ring, { intermediate = intermediate, halfWidthM = opts.halfWidthM, armM = opts.armM, captureM = opts.captureM })
        if not template then return nil, why end
        -- template = start, gates..., finish(at start). Per lap we use gates... then the line at start.
        local perLap = {}
        for i = 2, #template do perLap[#perLap + 1] = template[i] end
        local gates = {}
        local function copy(g, index, kind, name)
            local out = {}
            for k, v in pairs(g) do out[k] = v end
            out.index, out.kind, out.name = index, kind, name
            if kind ~= "start" then out.leaveM = nil end
            return out
        end
        gates[1] = copy(template[1], 1, "start", template[1].name)
        local lapOf = { [1] = 1 }
        for lap = 1, laps do
            for j, g in ipairs(perLap) do
                local last = (lap == laps and j == #perLap)
                local idx = #gates + 1
                local label = last and "finish" or ((j == #perLap) and ("L" .. lap .. " · line") or ("L" .. lap .. " · " .. tostring(g.name or j)))
                gates[idx] = copy(g, idx, last and "finish" or "gate", label)
                lapOf[idx] = lap
            end
        end
        local lapLen = 0
        for i = 2, #template do lapLen = lapLen + math.sqrt((template[i].x - template[i - 1].x) ^ 2 + (template[i].y - template[i - 1].y) ^ 2) end
        return {
            adapter = "laps", gates = gates, laps = laps, gatesPerLap = #perLap, lengthM = lapLen * laps, lapLengthM = lapLen,
            lapOf = function(index) return lapOf[index] or 0 end,
        }
    end

    -- ------------------------------------------------------------------ lanes (drag)
    M.MAX_STRAIGHTNESS_RATIO = 1.15   -- SP: a route is a drag strip when path length / straight line <= this

    --- Path length divided by the straight-line distance of a polyline; 1.0 is perfectly straight.
    function M.straightness(polyline)
        if type(polyline) ~= "table" or #polyline < 2 then return nil end
        local path = 0
        for i = 2, #polyline do path = path + math.sqrt((polyline[i].x - polyline[i - 1].x) ^ 2 + (polyline[i].y - polyline[i - 1].y) ^ 2) end
        local a, b = polyline[1], polyline[#polyline]
        local straight = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        if straight < 1 then return math.huge end
        return path / straight
    end

    --- Two gates (start, finish) plus lane geometry. lanes[i] = { index, offsetM, role } with the line offset
    --- laterally from the route axis; lane 1 is the rightmost (traffic-side) fast lane per P44.
    function M.dragCourse(route, opts)
        opts = opts or {}
        local lanes = math.max(1, math.floor(tonumber(opts.lanes) or 4))
        local width = tonumber(opts.laneWidthM) or 3.5
        local gates, why = Gates.build(route, { halfWidthM = opts.halfWidthM or (lanes * width / 2 + 2), armM = opts.armM })
        if not gates then return nil, why end
        local dir = gates[1].dir
        local lx, ly = -dir.y, dir.x   -- left of travel
        local list = {}
        local roles = { "fast_traffic", "slow_traffic", "slow_oncoming", "fast_oncoming" }
        for i = 1, lanes do
            -- lane 1 rightmost: offsets go from -(lanes-1)/2 .. +(lanes-1)/2 lane widths, right = negative lateral
            local k = (i - 1) - (lanes - 1) / 2
            list[i] = { index = i, offsetM = -k * width, role = roles[i] or ("lane_" .. i), axis = { lx = lx, ly = ly } }
        end
        return { adapter = "lanes", gates = gates, lanes = list, laneWidthM = width, lengthM = math.sqrt((gates[2].x - gates[1].x) ^ 2 + (gates[2].y - gates[1].y) ^ 2), laps = 1, gatesPerLap = 2 }
    end

    --- Lane assignment from qualifying order (P44): P1 fast/traffic, P2 slow/traffic, P3 slow/oncoming, P4 fast/oncoming.
    function M.laneAssignment(order, lanes)
        lanes = lanes or 4
        local seq = { 1, 2, 3, 4 }
        local out = {}
        for i, driverId in ipairs(order) do
            out[driverId] = seq[((i - 1) % math.min(lanes, #seq)) + 1]
        end
        return out
    end

    --- Deviation of a driver's samples from their lane line. Returns { excessM2, maxM, penaltySec }.
    --- Excess = sum over samples of (|lateral offset| - tolerance)+ squared; penaltySec = excess / 50, one decimal.
    function M.laneDeviation(course, laneIndex, samples, opts)
        opts = opts or {}
        local tol = tonumber(opts.toleranceM) or 1.5
        local lane = course.lanes[laneIndex]
        if not lane then return nil, "unknown_lane" end
        local g = course.gates[1]
        local excess, maxM = 0, 0
        for _, s in ipairs(samples or {}) do
            local rx, ry = (s.x or 0) - g.x, (s.y or 0) - g.y
            local lateral = rx * lane.axis.lx + ry * lane.axis.ly - lane.offsetM
            local over = math.abs(lateral) - tol
            if over > 0 then excess = excess + over * over; if math.abs(lateral) > maxM then maxM = math.abs(lateral) end end
        end
        local penalty = math.floor(excess / 50 * 10 + 0.5) / 10
        return { excessM2 = excess, maxM = maxM, penaltySec = penalty }
    end

    -- ------------------------------------------------------------------ rolling start: the green gate
    --- Insert a `green` gate `formationM` along the course after the start (walking the gate polyline), unless an
    --- authored gate named "green" already exists. The list is re-indexed; only the last line stays `finish`.
    function M.withGreenGate(course, formationM)
        local gates = course.gates
        for _, g in ipairs(gates) do if g.kind == "green" then return course end end
        local want = math.max(20, tonumber(formationM) or 300)
        local walked = 0
        local insertAt, pt, dir = nil, nil, nil
        for i = 2, #gates do
            local a, b = gates[i - 1], gates[i]
            local leg = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
            if walked + leg >= want and leg > 0 then
                local f = (want - walked) / leg
                pt = { x = a.x + (b.x - a.x) * f, y = a.y + (b.y - a.y) * f, z = (a.z or 0) + ((b.z or 0) - (a.z or 0)) * f }
                dir = { x = (b.x - a.x) / leg, y = (b.y - a.y) / leg }
                insertAt = i
                break
            end
            walked = walked + leg
        end
        if not insertAt then
            -- shorter course than the formation: the green gate sits halfway along the first leg
            local a, b = gates[1], gates[2]
            local leg = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
            if leg <= 0 then return course end
            pt = { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, z = ((a.z or 0) + (b.z or 0)) / 2 }
            dir = { x = (b.x - a.x) / leg, y = (b.y - a.y) / leg }
            insertAt = 2
        end
        local green = { kind = "green", name = "green flag", x = pt.x, y = pt.y, z = pt.z, dir = dir,
                        halfWidthM = gates[1].halfWidthM, armM = gates[1].armM, captureM = gates[1].captureM, radiusM = gates[2].radiusM or gates[1].radiusM }
        table.insert(gates, insertAt, green)
        for i, g in ipairs(gates) do g.index = i end
        course.gatesPerLap = (course.gatesPerLap or (#gates - 1)) + 1
        course.greenIndex = insertAt
        return course
    end

    -- ------------------------------------------------------------------ dispatch
    --- Build the course for a discipline. Returns { adapter, gates, lengthM, laps, gatesPerLap, lanes?, lapOf? }.
    function M.buildCourse(id, route, opts)
        local d = M.byId(id) or M.byId("street_sprint")
        opts = opts or {}
        -- an authored route's gates ride along unless the caller authored its own
        if opts.intermediate == nil and route.intermediate then opts.intermediate = route.intermediate end
        local course, why
        if d.adapter == "laps" then course, why = M.ovalCourse(route, opts)
        elseif d.adapter == "lanes" then course, why = M.dragCourse(route, opts)
        else course, why = p2pCourse(route, opts) end
        if course and opts.start == "rolling" then course = M.withGreenGate(course, opts.formationM) end
        return course, why
    end

    return M
end)
