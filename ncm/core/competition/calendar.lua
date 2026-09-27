-- ncm-core module: competition.calendar
-- Turns series cadence into posted slots (decision record L34, L37, P20). Pure and deterministic:
-- the same series + horizon always yields the same event ids, so re-materialising never duplicates.
local Core = NcmCore

Core.define("competition.calendar", function(C)
    local M = { version = "0.0.1" }
    local routes = C.get("course.routes")
    local ids = C.get("vocabulary.ids")
    local seasons = C.get("competition.seasons")

    --- Validate a series definition. Returns true or false, reason.
    function M.validateSeries(s)
        if type(s) ~= "table" then return false, "not_a_table" end
        if not ids.isSlug(s.seriesId) then return false, "invalid_series_id" end
        if type(s.name) ~= "string" or s.name == "" then return false, "name_required" end
        if not ids.isSlug(s.rulesetId) then return false, "invalid_ruleset_id" end
        local c = s.cadence
        if type(c) ~= "table" or type(c.everyMinutes) ~= "number" or c.everyMinutes < 1 then return false, "invalid_cadence" end
        if type(s.routes) ~= "table" or #s.routes == 0 then return false, "routes_required" end
        for _, r in ipairs(s.routes) do
            local rid = type(r) == "table" and r.rootId or r
            if not routes.resolve(rid) then return false, "unknown_route:" .. tostring(rid) end
        end
        local w = s.entryWindow or {}
        if (w.opensMinutes or 15) <= (w.closesMinutes or 1) then return false, "invalid_entry_window" end
        if s.economy ~= nil then
            local ok, why = C.get("economy.settlement").validate(s.economy)
            if not ok then return false, "invalid_economy:" .. tostring(why) end
        end
        return true
    end

    local function slotStartsAfter(everySec, offsetSec, t)
        -- first start strictly after t on the cadence grid
        local k = math.floor((t - offsetSec) / everySec) + 1
        return k * everySec + offsetSec, k
    end

    --- Materialise the posted slots of one series between now and now+horizonSec.
    --- Returns an array of events (ascending startsAt).
    function M.materialize(series, nowUnix, horizonSec)
        local ok, why = M.validateSeries(series)
        if not ok then error("calendar.materialize: " .. why, 2) end
        local everySec = math.floor(series.cadence.everyMinutes * 60)
        local offsetSec = math.floor((series.cadence.offsetMinutes or 0) * 60)
        local opens = math.floor((series.entryWindow and series.entryWindow.opensMinutes or 15) * 60)
        local closes = math.floor((series.entryWindow and series.entryWindow.closesMinutes or 1) * 60)
        local out = {}
        local startsAt, k = slotStartsAfter(everySec, offsetSec, nowUnix)
        while startsAt <= nowUnix + horizonSec do
            local r = series.routes[(k % #series.routes) + 1]
            local rid = type(r) == "table" and r.rootId or r
            local label = type(r) == "table" and r.label or nil
            local route = routes.resolve(rid, label)
            out[#out + 1] = {
                eventId = series.seriesId .. "@" .. tostring(math.floor(startsAt)),
                seriesId = series.seriesId,
                -- Enduring series identity and bounded competitive period are separate facts.
                seasonId = seasons.atUtc(startsAt).id,
                seriesName = series.name,
                rulesetId = series.rulesetId,
                class = "calendar",
                -- L58: street and sanctioned are both first-class, and which one a championship is cannot be
                -- derived from `class` -- every cadence series is "calendar". The championship declares it, and
                -- `guide.tierOf` prefers this over the class default.
                tier = series.tier,
                routeId = rid,
                routeName = route.name,
                startsAt = startsAt,
                entryOpensAt = startsAt - opens,
                entryClosesAt = startsAt - closes,
                venue = { x = route.start.x, y = route.start.y, z = route.start.z, heading = route.start.heading,
                          name = route.start.name, nodeId = route.start.id },
                finish = { x = route.finish.x, y = route.finish.y, z = route.finish.z, name = route.finish.name, nodeId = route.finish.id },
                distanceM = route.distanceM,
                region = route.region,
                finishRegion = route.finishRegion,
                description = route.description,
                seatsTotal = tonumber(series.capacity) or 0,
                -- competition vocabulary (L53): series may declare them; defaults are the street sprint
                disciplineId = series.disciplineId or "street_sprint",
                formatId = series.formatId or "sprint",
                classId = series.classId or "street_open",
                laps = series.laps or 1,
                -- L168: economics belong to the championship, and the event freezes the authored revision it
                -- was posted under. Routes still own geography only.
                economy = series.economy,
            }
            startsAt = startsAt + everySec
            k = k + 1
        end
        return out
    end

    --- Merge slots from several series, ascending by start time.
    function M.merge(lists)
        local out = {}
        for _, l in ipairs(lists) do
            for _, e in ipairs(l) do out[#out + 1] = e end
        end
        table.sort(out, function(a, b)
            if a.startsAt == b.startsAt then return a.eventId < b.eventId end
            return a.startsAt < b.startsAt
        end)
        return out
    end

    return M
end)
