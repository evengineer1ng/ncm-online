-- ncm_radio / server / spoken -- a fact value as the words a host says, exactly as `ncm/radio/voice/spoken.py` writes
-- them for the render (doc 59 §4). The lexicon clip key is `lex/<SPEAKER>/<slug(words)>`, so the two sides must agree
-- to the letter; `tools/test-radio.lua` checks every case in `ncm/radio/tests/spoken_cases.lua`.
-- LuaJIT ∩ Lua 5.4 (the NCM Host runs resources on CET's LuaJIT).
RadioSpoken = {}

local ONES = { [0] = "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
    "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" }
local TENS = { [2] = "twenty", [3] = "thirty", [4] = "forty", [5] = "fifty", [6] = "sixty", [7] = "seventy",
    [8] = "eighty", [9] = "ninety" }
local ORD = { one = "first", two = "second", three = "third", five = "fifth", eight = "eighth", nine = "ninth",
    twelve = "twelfth", twenty = "twentieth", thirty = "thirtieth", forty = "fortieth" }
local NUMBER_MAX, ORDINAL_MAX = 99, 40

-- Python's round(): halves to even. Only margins and odds round, and only their buckets must agree.
local function pyround(x)
    local f = math.floor(x)
    local d = x - f
    if d > 0.5 then return f + 1 end
    if d < 0.5 then return f end
    return (f % 2 == 0) and f or f + 1
end

function RadioSpoken.number(n)
    n = math.floor(tonumber(n) or -1)
    if n < 0 or n > NUMBER_MAX then return nil end
    if n < 20 then return ONES[n] end
    local t, o = math.floor(n / 10), n % 10
    return TENS[t] .. (o == 0 and "" or ("-" .. ONES[o]))
end

function RadioSpoken.ordinal(n)
    n = math.floor(tonumber(n) or 0)
    if n < 1 or n > ORDINAL_MAX then return nil end
    local w = RadioSpoken.number(n)
    local head, last = w:match("^(.*%-)([^%-]+)$")
    if not head then head, last = "", w end
    if ORD[last] then last = ORD[last]
    elseif last:sub(-1) == "y" then last = last:sub(1, -2) .. "ieth"
    else last = last .. "th" end
    return head .. last
end

function RadioSpoken.day(n)
    n = math.floor(tonumber(n) or 0)
    local w = RadioSpoken.number(n)
    if not w or n < 1 then return nil end
    return "Day " .. w:sub(1, 1):upper() .. w:sub(2)
end

function RadioSpoken.margin(seconds)
    local s = tonumber(seconds)
    if not s or s < 0 then return nil end
    if s < 0.05 then return "less than a tenth of a second" end
    if s < 1.95 then
        local tenths = pyround(s * 10)
        if tenths < 10 then
            return (tenths == 1 and "one tenth" or (RadioSpoken.number(tenths) .. " tenths")) .. " of a second"
        end
        local whole, frac = math.floor(tenths / 10), tenths % 10
        if frac == 0 then return whole == 1 and "one second" or (RadioSpoken.number(whole) .. " seconds") end
        return RadioSpoken.number(whole) .. " point " .. RadioSpoken.number(frac) .. " seconds"
    end
    if s < 9.75 then
        local halves = pyround(s * 2)
        local whole, half = math.floor(halves / 2), halves % 2
        return RadioSpoken.number(whole) .. (half == 1 and " and a half seconds" or " seconds")
    end
    if s < 59.5 then return RadioSpoken.number(pyround(s)) .. " seconds" end
    return "more than a minute"
end

function RadioSpoken.clock(hour, minute)
    local h, m = math.floor(tonumber(hour) or 0) % 24, math.floor(tonumber(minute) or 0)
    local q = pyround(m / 15.0) * 15
    if q == 60 then h, q = (h + 1) % 24, 0 end
    if h == 0 and q == 0 then return "midnight" end
    if h == 12 and q == 0 then return "noon" end
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    local tail = (q == 0 and " o'clock") or (q == 15 and " fifteen") or (q == 30 and " thirty") or " forty-five"
    return RadioSpoken.number(h12) .. tail .. (h < 12 and " in the morning" or (h < 18 and " in the afternoon" or " at night"))
end

function RadioSpoken.odds(price)
    local p = tonumber(price)
    if not p or p < 1.05 then return nil end
    local against = p - 1.0
    if against < 1.0 then
        local n = pyround(1.0 / against)
        if n > 20 then return nil end
        if n <= 1 then return "even money" end
        return RadioSpoken.number(n) .. " to one on"
    end
    if against < 3.0 then
        local halves = pyround(against * 2)
        if halves % 2 == 1 then return RadioSpoken.number(halves) .. " to two" end
        return halves == 2 and "even money" or (RadioSpoken.number(math.floor(halves / 2)) .. " to one")
    end
    local n = pyround(against)
    if n > NUMBER_MAX then return nil end
    return RadioSpoken.number(n) .. " to one"
end

function RadioSpoken.slug(text)
    return (tostring(text):lower():gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end
