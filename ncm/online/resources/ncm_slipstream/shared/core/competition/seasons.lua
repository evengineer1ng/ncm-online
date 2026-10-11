-- ncm-core module: competition.seasons
--
-- The global NCM competitive clock. A season is a UTC calendar quarter, not a
-- rolling duration and not the player-completed "season" used by the current
-- single-player career. Hosts inject Unix seconds; core never reads a clock.
-- Bounds are half-open: startUtc <= factUtc < endUtc.
local Core = NcmCore

Core.define("competition.seasons", function()
    local M = { version = "0.1.0", timezone = "UTC", boundary = "00:00:00" }
    local DAY = 86400

    local function integer(n) return type(n) == "number" and n == math.floor(n) end
    local function leap(y) return y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0) end
    local MONTH_DAYS = { 31,28,31,30,31,30,31,31,30,31,30,31 }

    local function validDate(year, month, day)
        if not integer(year) or year < 1970 then return false end
        if not integer(month) or month < 1 or month > 12 then return false end
        local limit = MONTH_DAYS[month] + ((month == 2 and leap(year)) and 1 or 0)
        return integer(day) and day >= 1 and day <= limit
    end

    -- Gregorian civil date -> days since 1970-01-01. Howard Hinnant's civil
    -- calendar arithmetic, expressed with math.floor for Lua 5.4/LuaJIT parity.
    local function daysFromCivil(year, month, day)
        local y = year - (month <= 2 and 1 or 0)
        local era = math.floor(y / 400)
        local yoe = y - era * 400
        local mp = month + (month > 2 and -3 or 9)
        local doy = math.floor((153 * mp + 2) / 5) + day - 1
        local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
        return era * 146097 + doe - 719468
    end

    local function civilFromDays(days)
        local z = days + 719468
        local era = math.floor(z / 146097)
        local doe = z - era * 146097
        local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
        local year = yoe + era * 400
        local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
        local mp = math.floor((5 * doy + 2) / 153)
        local day = doy - math.floor((153 * mp + 2) / 5) + 1
        local month = mp + (mp < 10 and 3 or -9)
        year = year + (month <= 2 and 1 or 0)
        return year, month, day
    end

    local function utcAt(year, month, day)
        return daysFromCivil(year, month, day) * DAY
    end

    local function make(year, number)
        if not integer(year) or year < 1970 then error("seasons: invalid_year", 3) end
        if not integer(number) or number < 1 or number > 4 then error("seasons: invalid_number", 3) end
        local startMonth = (number - 1) * 3 + 1
        local endYear, endMonth = year, startMonth + 3
        if endMonth > 12 then endYear, endMonth = year + 1, 1 end
        return {
            id = string.format("%04d-S%d", year, number),
            year = year,
            number = number,
            timezone = M.timezone,
            startUtc = utcAt(year, startMonth, 1),
            endUtc = utcAt(endYear, endMonth, 1),
        }
    end

    function M.forDate(year, month, day)
        if not validDate(year, month, day) then error("seasons.forDate: invalid_date", 2) end
        return make(year, math.floor((month - 1) / 3) + 1)
    end

    function M.atUtc(utc)
        if not integer(utc) or utc < 0 then error("seasons.atUtc: invalid_utc", 2) end
        local year, month, day = civilFromDays(math.floor(utc / DAY))
        local season = M.forDate(year, month, day)
        season.factUtc = utc
        return season
    end

    function M.parse(id)
        if type(id) ~= "string" then return nil, "invalid_season_id" end
        local year, number = id:match("^(%d%d%d%d)%-S([1-4])$")
        if not year or tonumber(year) < 1970 then return nil, "invalid_season_id" end
        return make(tonumber(year), tonumber(number))
    end

    function M.contains(season, utc)
        return type(season) == "table" and integer(utc)
            and utc >= season.startUtc and utc < season.endUtc
    end

    function M.next(season)
        if type(season) ~= "table" then error("seasons.next: season_required", 2) end
        if season.number == 4 then return make(season.year + 1, 1) end
        return make(season.year, season.number + 1)
    end

    return M
end)
