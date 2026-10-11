-- Race Week Live: how much studio talk can air in each situation (doc 59 §3). With no fact pending, the station
-- talks from studio / clock / handoff material; this counts the beats and minutes eligible per Week day x condition,
-- and why the rest are kept off (the first failing gate).
--   lua tools/pool-radio.lua [root]
local root = (arg and arg[1]) or "."
local R = root .. "/ncm/online/resources/ncm_radio/server/"
dofile(R .. "corpus_data.lua")
dofile(R .. "spoken.lua")
dofile(R .. "director.lua")
local C = NcmRadioCorpus
local MOOD = { healthy = "buoyant", slight = "uneasy", subpar = "tense", bad = "hostile" }
local why = {}
for _, lane in ipairs({ "healthy", "slight", "subpar", "bad" }) do
    local row = {}
    for day = 1, 4 do
        local d = RadioDirector.new(C)
        local t0 = 1800000000
        d:observe({ id = "o", kind = "week_open", at = t0, salience = 70, data = { run = 1 } }, t0)
        d:observe({ id = "v", kind = "week_vibe", at = t0, data = { mood = MOOD[lane] } }, t0)
        d.world.results = 12
        d.world.lastWinner = nil
        local now = t0 + (day - 1) * 86400 + 14 * 3600
        local L = d:listener(1, { name = "x" })
        local n, sec = 0, 0
        for _, t in ipairs({ "studio", "clock", "handoff" }) do
            for _, b in ipairs(d.byTrigger[t] or {}) do
                local ctx = { clockSlot = "night" }
                if d:eligible(b, L, nil, now, ctx) then
                    local clips, total = d:perform(b, d:context(L, nil, now, ctx))
                    if clips then n = n + 1; sec = sec + total / 1000
                    elseif lane == "bad" and day == 3 then
                        local _, w = d:perform(b, d:context(L, nil, now, ctx))
                        local key = tostring(w):gsub("[%w_%-]*#.*", "line"):gsub("lex/.*", "lex"):sub(1, 40)
                        why[key] = (why[key] or 0) + 1
                    end
                elseif lane == "bad" and day == 3 then
                    local g = b.gates or {}
                    local first = "other"
                    for k in pairs(g) do first = k break end
                    if g.day then first = "day" elseif g.lane then first = "lane" end
                    why["gate:" .. first] = (why["gate:" .. first] or 0) + 1
                end
            end
        end
        row[#row + 1] = string.format("D%d %3d beats %5.1f min", day, n, sec / 60)
    end
    print(string.format("%-8s %s", lane, table.concat(row, " | ")))
end
print("\nkept off on a bad Day 3 night:")
local keys = {}
for k, v in pairs(why) do keys[#keys + 1] = { k, v } end
table.sort(keys, function(a, b) return a[2] > b[2] end)
for _, kv in ipairs(keys) do print(string.format("  %4d  %s", kv[2], kv[1])) end
