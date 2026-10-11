-- ncm_radio / server / clock -- Night City time (the Paddock's US-Eastern clock) from unix seconds, for the
-- station's time-of-day beats (doc 59 §3). Its own file so `tools/test-radio.lua` can check the DST switches.
-- US Eastern (the Paddock's clock): EDT from the second Sunday of March 02:00 to the first Sunday of November 02:00.
-- Arithmetic only: the OPEN//77 server VM has no `os`, and the host's own time zone must never matter.
local function civil(days)            -- days since 1970-01-01 -> y, m, d (Hinnant's civil_from_days)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    return (m <= 2) and (y + 1) or y, m, d
end
local function weekday(y, m, d)       -- 0 = Sunday (Sakamoto)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if m < 3 then y = y - 1 end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end
local function nthSunday(y, m, n) return 1 + (7 - weekday(y, m, 1)) % 7 + (n - 1) * 7 end
local function easternOffset(utc)
    local days = math.floor(utc / 86400)
    local y, m, d = civil(days)
    local h = math.floor((utc - days * 86400) / 3600)
    local function key(mm, dd, hh) return mm * 10000 + dd * 100 + hh end
    local k = key(m, d, h)
    -- 02:00 EST = 07:00 UTC (spring forward); 02:00 EDT = 06:00 UTC (fall back)
    if k >= key(3, nthSunday(y, 3, 2), 7) and k < key(11, nthSunday(y, 11, 1), 6) then return -4 * 3600 end
    return -5 * 3600
end
local function clockOf(utc)
    local t = utc + easternOffset(utc)
    local s = t - math.floor(t / 86400) * 86400
    return math.floor(s / 3600), math.floor((s % 3600) / 60)
end
RadioClock = { offset = easternOffset, clockOf = clockOf, civil = civil }

