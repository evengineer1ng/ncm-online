-- Race Week Live: listen to a simulated stretch of the real station (doc 59 §3) and report what a listener hears.
--
--   lua tools/sim-radio.lua [root] [hours] [lane] [startHour]
--
-- Uses the REAL pack (only rendered clips air), Paddock-shaped races (a preview ten minutes out, the start, the
-- result with its race id, every twelve minutes), and reports: share of time speaking, the longest silence, beats
-- that ended on a handoff and what answered them, and a transcript of the first beats by id.
local root = (arg and arg[1]) or "."
local hours = tonumber(arg and arg[2]) or 3
local laneMood = (arg and arg[3]) or "hostile"          -- Online on 2026-10-09: a bad Week
local startHour = tonumber(arg and arg[4]) or 20
local R = root .. "/ncm/online/resources/ncm_radio/server/"
dofile(R .. "corpus_data.lua")
dofile(R .. "spoken.lua")
dofile(R .. "director.lua")
local C = NcmRadioCorpus
local byId = {}
for _, b in ipairs(C.beats) do byId[b.id] = b end

-- the sim's names are voiced only if the pack voiced them, so use names the pack has for every host
local function voiced(cls, candidates)
    for _, v in ipairs(candidates) do
        local ok = true
        for _, sp in ipairs({ "MARA", "JULES", "TOMMY" }) do
            if not C.lex["lex/" .. sp .. "/" .. RadioSpoken.slug(v)] then ok = false end
        end
        if ok then return v end
    end
    return nil
end
local names = {}
for k in pairs(C.lex) do
    local sp, slug = k:match("^lex/([^/]+)/(.+)$")
    if sp == "MARA" then names[#names + 1] = slug end
end

local d = RadioDirector.new(C)
local t0 = 1800000000
local pid = 1
d:listener(pid, { driverId = "drv-me", name = "baremetaleven", stats = { starts = 3, podiums = 0, wins = 0, dnfs = 1 } })
-- the Week opened two days ago; this is Day 3 evening
local opened = t0 - 2 * 86400
d:observe({ id = "week:1:open", kind = "week_open", at = opened, salience = 70, data = { run = 1 } }, t0)
d:observe({ id = "vibe:1", kind = "week_vibe", at = t0, data = { mood = laneMood } }, t0)
d.listeners[pid].heard["open:1"] = opened

-- race facts every 12 minutes, staggered: preview (T-8 min), start (T), result (T+6 min)
local drivers = { "Rhea Santos", "Kat Morrow", "Sol Brandt", "Ines Vale", "Dmitri Okoye" }
local function pickName(i)
    for j = 0, #drivers - 1 do
        local n = drivers[(i + j) % #drivers + 1]
        if C.lex["lex/TOMMY/" .. RadioSpoken.slug(n)] and C.lex["lex/MARA/" .. RadioSpoken.slug(n)] then return n end
    end
    return nil
end
-- fall back to real names from the pack when the sim's are not voiced
local realNames = {}
for _, slug in ipairs(names) do
    if C.lex["lex/TOMMY/" .. slug] and C.lex["lex/JULES/" .. slug] and not slug:find("%d") and slug:find("%-") then
        realNames[#realNames + 1] = slug
    end
    if #realNames >= 12 then break end
end
local function nameAt(i)
    local n = pickName(i)
    if n then return n end
    local slug = realNames[(i % #realNames) + 1]
    return (slug:gsub("%-", " "):gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end))
end
local seriesName = nil
for k in pairs(C.lex) do
    local sp, slug = k:match("^lex/([^/]+)/(.+)$")
    if sp == "MARA" and slug:find("cup") and C.lex["lex/JULES/" .. slug] and C.lex["lex/TOMMY/" .. slug] then
        seriesName = (slug:gsub("%-", " "):gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end)) break
    end
end

local events = {}
local t = t0
local endT = t0 + hours * 3600
local k = 0
for at = t0 + 300, endT, 720 do
    k = k + 1
    local race = "pr-sim-" .. k
    events[#events + 1] = { at = at - 480, f = { id = "preview:" .. race, kind = "race_preview", salience = 30,
        data = { race = race, series = seriesName, opensAt = at, opensHour = (startHour + math.floor((at - t0) / 3600)) % 24, opensMinute = 0 } } }
    events[#events + 1] = { at = at, f = { id = "start:" .. race, kind = "race_start", salience = 40, data = { race = race, series = seriesName } } }
    events[#events + 1] = { at = at + 360, f = { id = "rr:" .. race, kind = "race_result", trigger = "race_result", salience = 25,
        data = { race = race, winner = nameAt(k), second = nameAt(k + 1), third = nameAt(k + 2), series = seriesName,
            fieldSize = 10, marginSeconds = (k % 4 == 0) and 0.3 or 1.6 } } }
end
table.sort(events, function(a, b) return a.at < b.at end)

local ei = 1
local speech, silent, longest, curSilence = 0, 0, 0, 0
local log, handoffs, answered = {}, 0, 0
local pendingHandoff
while t < endT do
    while events[ei] and events[ei].at <= t do
        local f = events[ei].f
        f.at = events[ei].at
        d:observe(f, t)
        ei = ei + 1
    end
    local hh = (startHour + math.floor((t - t0) / 3600)) % 24
    local item = d:next(pid, t, { hour = hh, minute = 0 })
    local talk = item.totalMs / 1000
    local quiet = item.silenceMs / 1000
    if item.beat ~= "" then
        local b = byId[item.beat]
        log[#log + 1] = string.format("%5.1f min  %-48s %-14s %4.0f s talk  %4.1f s gap", (t - t0) / 60, item.beat, item.trigger or "", talk, quiet)
        if pendingHandoff then
            if b.lead == pendingHandoff then answered = answered + 1 end
            pendingHandoff = nil
        end
        if b.handoff then handoffs = handoffs + 1; pendingHandoff = b.handoff end
        speech = speech + talk
        curSilence = quiet
    else
        curSilence = curSilence + quiet
    end
    silent = silent + quiet
    if curSilence > longest then longest = curSilence end
    if item.beat ~= "" then curSilence = 0 end
    t = t + math.max(1, math.ceil(talk + quiet))
end
for i = 1, math.min(#log, tonumber(os.getenv("SIM_LINES") or 40)) do print(log[i]) end
print(string.format("\n%d h, lane %s: %d beats, speech %.0f%% of the time, longest silence %.0f s, handoffs %d answered %d",
    hours, d.world.lane, #log, 100 * speech / (speech + silent), longest, handoffs, answered))
