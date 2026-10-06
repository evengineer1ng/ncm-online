-- ncm-core module: world.clock
-- US Eastern civil time from a UTC unix timestamp, with daylight saving (L221, L222: `America/New_York`).
--
-- Pure, so the Paddock's daily rhythm (doc 44 §5) does not depend on the in-game clock service (IDEA-729). The
-- rule is the current US one: DST starts at 02:00 local on the second Sunday of March (07:00 UTC) and ends at
-- 02:00 local on the first Sunday of November (06:00 UTC). Dates are proleptic Gregorian via days-from-civil.
local Core = NcmCore

Core.define("world.clock", function()
    local M = { version = "0.1.0", zone = "America/New_York" }

    local floor = math.floor

    --- Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
    function M.daysFromCivil(y, m, d)
        y = (m <= 2) and (y - 1) or y
        local era = floor(y / 400)
        local yoe = y - era * 400
        local mp = (m + 9) % 12
        local doy = floor((153 * mp + 2) / 5) + d - 1
        local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
        return era * 146097 + doe - 719468
    end

    --- Civil date for days since 1970-01-01. Returns y, m, d.
    function M.civilFromDays(z)
        z = z + 719468
        local era = floor(z / 146097)
        local doe = z - era * 146097
        local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
        local y = yoe + era * 400
        local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
        local mp = floor((5 * doy + 2) / 153)
        local d = doy - floor((153 * mp + 2) / 5) + 1
        local m = (mp < 10) and (mp + 3) or (mp - 9)
        if m <= 2 then y = y + 1 end
        return y, m, d
    end

    --- 0 = Sunday ... 6 = Saturday.
    function M.weekday(days) return (days + 4) % 7 end

    local function nthSunday(y, m, n)
        local first = M.daysFromCivil(y, m, 1)
        local offset = (7 - M.weekday(first)) % 7
        return first + offset + (n - 1) * 7
    end

    --- The UTC instants DST begins and ends in year `y`.
    function M.dstBounds(y)
        local startUtc = nthSunday(y, 3, 2) * 86400 + 7 * 3600
        local endUtc = nthSunday(y, 11, 1) * 86400 + 6 * 3600
        return startUtc, endUtc
    end

    --- True while Eastern is on daylight time.
    function M.isDst(utc)
        local y = M.civilFromDays(floor(utc / 86400))
        local s, e = M.dstBounds(y)
        return utc >= s and utc < e
    end

    --- The Eastern offset in seconds (-14400 in summer, -18000 in winter).
    function M.offset(utc)
        return M.isDst(utc) and -14400 or -18000
    end

    --- Eastern wall clock for a UTC instant:
    --- { y, m, d, hour, min, sec, secondsOfDay, weekday, dayIndex, dst, localUnix }.
    --- `dayIndex` is the Eastern calendar day as a day number, so "today's schedule" is one integer.
    function M.eastern(utc)
        utc = floor(tonumber(utc) or 0)
        local off = M.offset(utc)
        local lu = utc + off
        local days = floor(lu / 86400)
        local sod = lu - days * 86400
        local y, m, d = M.civilFromDays(days)
        return {
            y = y, m = m, d = d,
            hour = floor(sod / 3600), min = floor((sod % 3600) / 60), sec = sod % 60,
            secondsOfDay = sod, weekday = M.weekday(days), dayIndex = days,
            dst = off == -14400, localUnix = lu,
        }
    end

    --- The UTC instant of an Eastern wall-clock time on Eastern day `dayIndex` (+ `secondsOfDay`, may exceed a day).
    --- Around the transitions the offset is taken at the target itself, so 03:00 on spring-forward day and
    --- 01:30 on fall-back day both land on a real instant.
    function M.utcAt(dayIndex, secondsOfDay)
        local lu = dayIndex * 86400 + secondsOfDay
        local guess = lu + 18000
        local off = M.offset(guess)
        local utc = lu - off
        if M.offset(utc) ~= off then utc = lu - M.offset(utc) end
        return utc
    end

    --- "HH:MM" Eastern.
    function M.hhmm(utc)
        local e = M.eastern(utc)
        return string.format("%02d:%02d", e.hour, e.min)
    end

    return M
end)
