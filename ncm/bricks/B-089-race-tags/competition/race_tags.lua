-- ncm-core module: competition.race_tags
-- Post-event descriptors for IDEA-089. Pure: one settled session in, per-driver tags out.
local Core = NcmCore

local function listCount(t)
    if type(t) ~= "table" then
        return nil
    end
    local n = 0
    while t[n + 1] ~= nil do
        n = n + 1
    end
    return n
end

local function hasItems(t)
    local n = listCount(t)
    return n ~= nil and n > 0
end

local function noItems(t)
    local n = listCount(t)
    return n ~= nil and n == 0
end

local function incidentCountKnownZero(row)
    if row.incidentCount ~= nil then
        if row.incidentCount ~= 0 then
            return false
        end
        if row.incidents == nil then
            return true
        end
        return noItems(row.incidents)
    end
    return noItems(row.incidents)
end

local function raceClean(row)
    return row.state == "finished"
        and incidentCountKnownZero(row)
        and noItems(row.penalties)
        and row.jumpStart == false
end

local function runClean(row)
    if row.state ~= "finished" then
        return false
    end
    if row.bestSec == nil or type(row.bestSec) ~= "number" then
        return false
    end
    if row.runs ~= nil and row.runs <= 0 then
        return false
    end
    if not incidentCountKnownZero(row) then
        return false
    end
    if hasItems(row.penalties) or row.jumpStart == true then
        return false
    end
    return true
end

local function rowTime(row, kind)
    if kind == "race" then
        if row.state == "finished" and type(row.totalSec) == "number" then
            return row.totalSec
        end
        return nil
    end
    if type(row.bestSec) == "number" then
        return row.bestSec
    end
    return nil
end

local function correctedTime(row)
    if type(row.correctedSec) == "number" then
        return row.correctedSec
    end
    if type(row.totalSec) == "number" then
        return row.totalSec
    end
    return nil
end

local function crossingAt(row, gate)
    if type(row.crossings) ~= "table" then
        return nil
    end
    local t = row.crossings[gate]
    if type(t) == "number" then
        return t
    end
    return nil
end

local function isStrictEarliest(results, row, gate)
    local t = crossingAt(row, gate)
    if t == nil then
        return false
    end
    for i = 1, #results do
        local other = results[i]
        if other ~= row then
            local ot = crossingAt(other, gate)
            if ot ~= nil and ot <= t then
                return false
            end
        end
    end
    return true
end

local function hasKnownEarlier(results, row, gate)
    local t = crossingAt(row, gate)
    if t == nil then
        return false
    end
    for i = 1, #results do
        local other = results[i]
        if other ~= row then
            local ot = crossingAt(other, gate)
            if ot ~= nil and ot < t then
                return true
            end
        end
    end
    return false
end

local function gateOrder(results, row, gate)
    local t = crossingAt(row, gate)
    if t == nil then
        return nil
    end
    local earlier = 0
    local missing = 0
    for i = 1, #results do
        local other = results[i]
        if other ~= row then
            local ot = crossingAt(other, gate)
            if ot == nil then
                missing = missing + 1
            elseif ot == t then
                return nil
            elseif ot < t then
                earlier = earlier + 1
            end
        end
    end
    -- Missing crossings could all have happened before this driver. Return the worst-case
    -- order so a Good Start is emitted only when the threshold is still provable.
    return 1 + earlier + missing
end

local function hasHeavyIncident(row)
    if type(row.incidents) ~= "table" then
        return false
    end
    for i = 1, #row.incidents do
        local incident = row.incidents[i]
        if type(incident) == "table" and incident.band == 3 then
            return true
        end
    end
    return false
end

Core.define("competition.race_tags", function(C)
    local M = { version = "1.0.0" }

    M.DEFAULTS = {
        maxTags = 4,
        closeFinishSec = 0.5,
        clearWinSec = 5.0,
        gainedMin = 2,
        lostMin = 2,
        goodStartMin = 2,
        toughIncidents = 3,
        priority = {
            "route_record",
            "personal_best",
            "clean_race",
            "clean_run",
            "clear_win",
            "close_finish",
            "led_every_gate",
            "came_through",
            "good_start",
            "gained_positions",
            "lost_positions",
            "heavy_contact",
            "tough_one",
            "jump_start",
            "penalised",
            "did_not_finish",
        },
    }

    M.CATALOGUE = {
        { id = "clean_race", label = "Clean Race", modes = { "race" } },
        { id = "clean_run", label = "Clean Run", modes = { "race", "quali", "practice" } },
        { id = "close_finish", label = "Close Finish", modes = { "race" } },
        { id = "clear_win", label = "Clear Win", modes = { "race" } },
        { id = "gained_positions", label = "Gained Positions", modes = { "race" } },
        { id = "lost_positions", label = "Lost Positions", modes = { "race" } },
        { id = "good_start", label = "Good Start", modes = { "race" } },
        { id = "led_every_gate", label = "Led Every Gate", modes = { "race" } },
        { id = "came_through", label = "Came Through", modes = { "race" } },
        { id = "heavy_contact", label = "Heavy Contact", modes = { "race", "quali", "practice" } },
        { id = "tough_one", label = "Tough One", modes = { "race", "quali", "practice" } },
        { id = "jump_start", label = "Jump Start", modes = { "race" } },
        { id = "penalised", label = "Penalised", modes = { "race" } },
        { id = "did_not_finish", label = "Did Not Finish", modes = { "race" } },
        { id = "personal_best", label = "Personal Best", modes = { "race", "quali", "practice" } },
        { id = "route_record", label = "Route Record", modes = { "race", "quali", "practice" } },
    }

    local catalogueById = {}
    for i = 1, #M.CATALOGUE do
        local item = M.CATALOGUE[i]
        catalogueById[item.id] = item
    end

    local function option(opts, name)
        local value = opts[name]
        if value ~= nil then
            return value
        end
        return M.DEFAULTS[name]
    end

    local function addCandidate(candidates, id)
        candidates[id] = true
    end

    local function orderedTags(candidates, opts)
        local maxTags = option(opts, "maxTags")
        if type(maxTags) ~= "number" or maxTags < 0 then
            error("competition.race_tags.evaluate: maxTags must be a non-negative number", 3)
        end
        maxTags = math.floor(maxTags)
        if maxTags == 0 then
            return {}
        end

        local priority = option(opts, "priority")
        if type(priority) ~= "table" then
            error("competition.race_tags.evaluate: priority must be an array", 3)
        end

        local ids = {}
        local seen = {}
        for i = 1, #priority do
            local id = priority[i]
            if type(id) ~= "string" then
                error("competition.race_tags.evaluate: priority entries must be strings", 3)
            end
            if candidates[id] and catalogueById[id] and not seen[id] then
                ids[#ids + 1] = id
                seen[id] = true
            end
        end
        for i = 1, #M.CATALOGUE do
            local id = M.CATALOGUE[i].id
            if candidates[id] and not seen[id] then
                ids[#ids + 1] = id
                seen[id] = true
            end
        end

        local tags = {}
        local limit = math.min(maxTags, #ids)
        for i = 1, limit do
            local item = catalogueById[ids[i]]
            tags[i] = { id = item.id, label = item.label }
        end
        return tags
    end

    local function finishNeighbors(results, index)
        local before = nil
        local after = nil
        local i = index - 1
        while i >= 1 do
            if results[i].state == "finished" then
                before = results[i]
                break
            end
            i = i - 1
        end
        i = index + 1
        while i <= #results do
            if results[i].state == "finished" then
                after = results[i]
                break
            end
            i = i + 1
        end
        return before, after
    end

    -- Evaluate one settled session and return per-driver post-event descriptor tags.
    function M.evaluate(facts, opts)
        if type(facts) ~= "table" then
            error("competition.race_tags.evaluate: facts must be a table", 2)
        end
        if opts ~= nil and type(opts) ~= "table" then
            error("competition.race_tags.evaluate: opts must be a table", 2)
        end
        opts = opts or {}
        if type(facts.session) ~= "table" then
            error("competition.race_tags.evaluate: session must be a table", 2)
        end
        if type(facts.results) ~= "table" then
            error("competition.race_tags.evaluate: results must be an array", 2)
        end
        local kind = facts.session.kind
        if type(kind) ~= "string" then
            error("competition.race_tags.evaluate: session.kind must be a string", 2)
        end
        if kind ~= "race" and kind ~= "quali" and kind ~= "practice" then
            return nil, "unknown_session_kind"
        end

        local diagnostics = {}
        local isTimeTrial = false
        if kind == "race" then
            if facts.session.timeTrial == true then
                isTimeTrial = true
            elseif facts.session.timeTrial == false then
                isTimeTrial = false
            elseif facts.session.fieldSize == 1 then
                isTimeTrial = true
                diagnostics[#diagnostics + 1] = "timeTrial absent; fieldSize 1 treated as time trial"
            else
                error("competition.race_tags.evaluate: race session.timeTrial must be a boolean", 2)
            end
        end

        for i = 1, #facts.results do
            local row = facts.results[i]
            if type(row) ~= "table" then
                error("competition.race_tags.evaluate: result row must be a table", 2)
            end
            if type(row.driverId) ~= "string" or row.driverId == "" then
                error("competition.race_tags.evaluate: result row driverId must be a non-empty string", 2)
            end
            if type(row.state) ~= "string" or row.state == "" then
                error("competition.race_tags.evaluate: result row state must be a non-empty string", 2)
            end
        end

        local output = { drivers = {} }
        if #diagnostics > 0 then
            output.diagnostics = diagnostics
        end

        local positionMode = kind == "race" and not isTimeTrial and (facts.session.fieldSize or #facts.results) >= 2
        local p2 = nil
        if positionMode then
            for i = 1, #facts.results do
                if facts.results[i].position == 2 then
                    p2 = facts.results[i]
                    break
                end
            end
        end

        for i = 1, #facts.results do
            local row = facts.results[i]
            local candidates = {}

            if row.state ~= "dns" and row.state ~= "dsq" then
                if kind == "race" then
                    if isTimeTrial then
                        if raceClean(row) then
                            addCandidate(candidates, "clean_run")
                        end
                    elseif raceClean(row) then
                        addCandidate(candidates, "clean_race")
                    end
                elseif runClean(row) then
                    addCandidate(candidates, "clean_run")
                end

                if hasHeavyIncident(row) then
                    addCandidate(candidates, "heavy_contact")
                end
                if row.state == "finished" and type(row.incidentCount) == "number"
                    and row.incidentCount >= option(opts, "toughIncidents") then
                    addCandidate(candidates, "tough_one")
                end

                if kind == "race" then
                    if row.jumpStart == true then
                        addCandidate(candidates, "jump_start")
                    end
                    if hasItems(row.penalties) then
                        addCandidate(candidates, "penalised")
                    end
                    if row.state == "dnf" then
                        addCandidate(candidates, "did_not_finish")
                    end
                end

                local time = rowTime(row, kind)
                if time ~= nil and type(row.previousBestSec) == "number" and time < row.previousBestSec then
                    addCandidate(candidates, "personal_best")
                end
                if time ~= nil and type(facts.routeRecordSec) == "number" and time < facts.routeRecordSec then
                    addCandidate(candidates, "route_record")
                    candidates.personal_best = nil
                end

                if positionMode and row.state == "finished" then
                    local rowCorrected = correctedTime(row)
                    if rowCorrected ~= nil then
                        local before, after = finishNeighbors(facts.results, i)
                        local close = false
                        if before ~= nil then
                            local t = correctedTime(before)
                            if t ~= nil and math.abs(rowCorrected - t) <= option(opts, "closeFinishSec") then
                                close = true
                            end
                        end
                        if after ~= nil then
                            local t = correctedTime(after)
                            if t ~= nil and math.abs(rowCorrected - t) <= option(opts, "closeFinishSec") then
                                close = true
                            end
                        end
                        if close then
                            addCandidate(candidates, "close_finish")
                        end
                    end

                    if row.position == 1 and p2 ~= nil and p2.state == "finished" then
                        local firstTime = correctedTime(row)
                        local secondTime = correctedTime(p2)
                        if firstTime ~= nil and secondTime ~= nil
                            and secondTime - firstTime >= option(opts, "clearWinSec") then
                            addCandidate(candidates, "clear_win")
                        end
                    end

                    if type(row.slot) == "number" and type(row.position) == "number" then
                        if row.slot - row.position >= option(opts, "gainedMin") then
                            addCandidate(candidates, "gained_positions")
                        end
                        if row.position - row.slot >= option(opts, "lostMin") then
                            addCandidate(candidates, "lost_positions")
                        end
                    end

                    if type(row.slot) == "number" then
                        local order = gateOrder(facts.results, row, 1)
                        if order ~= nil and row.slot - order >= option(opts, "goodStartMin") and row.jumpStart == false then
                            addCandidate(candidates, "good_start")
                        end
                    end

                    if row.position == 1 then
                        local gatesTotal = facts.session.gatesTotal
                        if type(gatesTotal) == "number" and gatesTotal >= 1 then
                            local ledEvery = true
                            local gate = 1
                            while gate <= gatesTotal do
                                if not isStrictEarliest(facts.results, row, gate) then
                                    ledEvery = false
                                    break
                                end
                                gate = gate + 1
                            end
                            if ledEvery then
                                addCandidate(candidates, "led_every_gate")
                            end
                        end
                        if hasKnownEarlier(facts.results, row, 1) then
                            addCandidate(candidates, "came_through")
                        end
                    end
                end
            end

            local tags = orderedTags(candidates, opts)
            output.drivers[i] = {
                driverId = row.driverId,
                position = row.position,
                state = row.state,
                tags = tags,
            }
        end

        return output
    end

    return M
end)
