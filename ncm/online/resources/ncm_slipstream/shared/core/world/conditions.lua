-- ncm-core module: world.conditions
-- The racing conditions at an instant, derived purely from the persisted weather plan (doc 44 §5.4, §7).
--
-- `ncm_world/server/machine.lua` integrates road wetness live, in memory, and only that VM can read it. A result
-- stamped in `ncm_league` and a Paddock race resolved in `ncm_paddock` need the same answer without that memory,
-- so the integrator is restated here over plan rows (`weather_transition`, seven days ahead). The constants are
-- machine.lua's (`L208`: ~2 min to soak from dry, ~6 min to dry out) and a test holds them equal. machine.lua is
-- left alone: it remains the live handling source; this is the reproducible one.
--
-- The Paddock never SETS weather (L222). It reads it here.
local Core = NcmCore

Core.define("world.conditions", function(C)
    local M = { version = "0.1.0", ROAD_SOAK_S = 120, ROAD_DRY_S = 360, ROAD_STEP = 0.05 }

    local FAMILY = {
        sunny = "dry", lightclouds = "dry", cloudy = "dry", rain = "wet",
        heavyclouds = "obscured", fog = "obscured", pollution = "hazardous", sandstorm = "hazardous",
    }
    M.FAMILY = FAMILY

    local function wetOf(weather)
        local thermal = C.get("parts.thermal")
        return (thermal.weatherProfile(weather).wet) or 0
    end
    M.wetOf = wetOf

    --- Road wetness 0..1 at `utc`, integrated across the plan rows (sorted by startsAtUtc) up to that instant.
    --- Rows before the first one are taken as dry. Quantised like machine.lua so the two agree on steps.
    function M.roadWetnessAt(rows, utc)
        if type(rows) ~= "table" or #rows == 0 then return 0 end
        local road = 0
        for i = 1, #rows do
            local from = rows[i].startsAtUtc
            if from >= utc then break end
            local to = rows[i + 1] and rows[i + 1].startsAtUtc or utc
            if to > utc then to = utc end
            local dt = to - from
            local target = wetOf(rows[i].weather)
            if road < target then road = math.min(target, road + dt / M.ROAD_SOAK_S)
            elseif road > target then road = math.max(target, road - dt / M.ROAD_DRY_S) end
        end
        return math.floor(road / M.ROAD_STEP + 0.5) * M.ROAD_STEP
    end

    --- The light band from seconds of the (Eastern, L221) day.
    function M.lightOf(secondsOfDay)
        local h = (tonumber(secondsOfDay) or 43200) / 3600
        if h >= 7 and h < 18.5 then return "day" end
        if (h >= 5.5 and h < 7) or (h >= 18.5 and h < 20.5) then return "dusk" end
        return "night"
    end

    --- The weather row in force at `utc`, or nil.
    function M.weatherAt(rows, utc)
        local found
        for i = 1, #(rows or {}) do
            if rows[i].startsAtUtc <= utc then found = rows[i] else break end
        end
        return found and found.weather or nil
    end

    --- { weather, family, roadWetness, secondsOfDay, light, bucket } at `utc`. `secondsOfDay` is Eastern
    --- (world.clock) unless the caller passes the in-game value explicitly.
    function M.at(rows, utc, secondsOfDay)
        local weather = M.weatherAt(rows, utc) or "sunny"
        if secondsOfDay == nil then secondsOfDay = C.get("world.clock").eastern(utc).secondsOfDay end
        local wet = M.roadWetnessAt(rows, utc)
        local light = M.lightOf(secondsOfDay)
        return {
            weather = weather, family = FAMILY[weather] or "dry", roadWetness = wet,
            secondsOfDay = math.floor(secondsOfDay), light = light,
            bucket = M.bucket(wet, light),
        }
    end

    --- The calibration bucket for conditions: coarse on purpose, because two humans produce little data
    --- (L223) and a fine bucket would never fill.
    function M.bucket(roadWetness, light)
        local w = (tonumber(roadWetness) or 0) >= 0.5 and "wet" or ((tonumber(roadWetness) or 0) > 0.1 and "damp" or "dry")
        return w .. ":" .. ((light == "night") and "night" or "day")
    end

    return M
end)
