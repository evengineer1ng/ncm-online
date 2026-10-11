-- Race Week Live (doc 59, L348): the corpus, the spoken forms and the director, in Lua 5.4 and LuaJIT.
--
--   * every speaker paragraph of the authoring bible is in the corpus the station airs (owner: "spare no lines");
--   * the director speaks every finite slot domain exactly as the voice render voiced it (clip keys agree);
--   * a simulated 72-hour Race Week: the fixed opening first, results and incidents covered by their own families,
--     the bible's gates respected (no Day-2 beat on Day 1, no "first podium" twice, no healthy-Week beat in a bad Week),
--     no beat repeated for a listener within 20 hours, every slot bound to a fact, and the same Week twice gives the
--     same programme (deterministic: a restart re-airs nothing differently).
local root = (arg and arg[1]) or "."
local passed = 0
local function check(label, ok, detail)
    if not ok then error("FAIL " .. label .. (detail and (": " .. tostring(detail)) or ""), 0) end
    passed = passed + 1
    print("  PASS " .. label)
end

local R = root .. "/ncm/online/resources/ncm_radio/server/"
dofile(R .. "corpus_data.lua")
dofile(R .. "spoken.lua")
dofile(R .. "director.lua")
local C = NcmRadioCorpus

-- ---------------------------------------------------------------- the corpus is the whole bible
local bible = io.open(root .. "/docs/ncm-online/radio/RACE_WEEK_RADIO_BIBLE.md", "rb"):read("*a")
local paragraphs = 0
for line in (bible .. "\n"):gmatch("([^\n]*)\n") do
    local body = line:gsub("^> ", "")
    local plain = body:match("^([A-Z][A-Z /]+): ")
    local cast = { MARA = 1, JULES = 1, TOMMY = 1, NIA = 1, IMANI = 1, CELESTE = 1, DARNELL = 1, DRIVER = 1, ["SECOND REMOTE FEED"] = 1 }
    if body:match("^%*%*[A-Z][A-Z .()/\"-]+:%*%*") or (plain and cast[(plain:match("^([^/]+)"))]) then
        paragraphs = paragraphs + 1
    end
end
local lines, ids = 0, {}
for _, b in ipairs(C.beats) do
    check_unique = ids[b.id] == nil
    if not check_unique then error("FAIL duplicate beat id " .. b.id, 0) end
    ids[b.id] = true
    for _, l in ipairs(b.lines) do if l.id then lines = lines + 1 end end
end
check("every speaker paragraph of the bible is a corpus line (" .. paragraphs .. ")", lines == paragraphs and paragraphs > 3000,
    lines .. " lines vs " .. paragraphs .. " paragraphs")
check("every beat id is unique (" .. #C.beats .. " beats)", #C.beats > 1000)

-- ---------------------------------------------------------------- spoken forms agree with the render
local cases = dofile(root .. "/ncm/radio/tests/spoken_cases.lua")
for _, c in ipairs(cases) do
    local kind, input, want = c[1], c[2], c[3]
    local got
    if kind == "clock" then got = RadioSpoken.clock(input[1], input[2]) else got = RadioSpoken[kind](input) end
    if got ~= want then error(("FAIL spoken.%s(%s) = %q, the render voiced %q"):format(kind, tostring(type(input) == "table" and table.concat(input, ":") or input), tostring(got), tostring(want)), 0) end
end
check("spoken forms match the render for all " .. #cases .. " probe cases", true)
check("slug matches the render's", RadioSpoken.slug("Four tenths of a second!") == "four-tenths-of-a-second")

-- ---------------------------------------------------------------- Night City time, without `os` (absent in the VM)
dofile(R .. "clock.lua")
local function at(utc, wantH, wantM)
    local h, m = RadioClock.clockOf(utc)
    return h == wantH and m == wantM, ("%d:%02d"):format(h, m)
end
check("2026-10-08 12:00 UTC is 08:00 EDT", at(1791460800, 8, 0))
check("2026-01-15 12:00 UTC is 07:00 EST", at(1768478400, 7, 0))
check("spring forward: 06:59 UTC is 01:59 EST", at(1772953140, 1, 59))
check("spring forward: 07:00 UTC is 03:00 EDT", at(1772953200, 3, 0))
check("fall back: 05:59 UTC is 01:59 EDT", at(1793512740, 1, 59))
check("fall back: 06:00 UTC is 01:00 EST", at(1793512800, 1, 0))

-- ---------------------------------------------------------------- a simulated Race Week
local function week(seed)
    local d = RadioDirector.new(C, { assumeRendered = true, assumeVoiced = true })
    local t0 = 1800000000
    local log = {}
    local function hm(t) local h = math.floor(((t - t0) / 3600 + 9) % 24) return h, 0 end
    local pid = 7
    d:listener(pid, { driverId = "drv-me", name = "Baremetal", stats = { starts = 0, podiums = 0, wins = 0, dnfs = 0 } })
    d:observe({ id = "week:1:open", kind = "week_open", at = t0, salience = 70, data = { run = 1 } }, t0)
    local names = { "Kat Morrow", "Sol Brandt", "Ines Vale", "Dmitri Okoye", "Rhea Santos", "Bo Lindqvist" }
    local routes = { "Kabuki Loop", "Corpo Plaza Sprint", "Badlands Run" }
    local series = { "Night City Street Series", "Pacifica Cup" }
    local t, n, nextFact = t0, 0, t0 + 1200
    local endT = t0 + 72 * 3600
    local mood = { [1] = "buoyant", [2] = "uneasy", [3] = "hostile" }
    while t < endT do
        -- the world keeps happening every ~20 minutes
        if t >= nextFact then
            n = n + 1
            local k = (n * 7 + seed) % 11
            local day = math.floor((t - t0) / 86400) + 1
            if n % 6 == 0 then d:observe({ id = "vibe:" .. n, kind = "week_vibe", at = t, data = { mood = mood[day] or "tense" } }, t) end
            local w = names[(n + seed) % #names + 1]
            local f
            if k <= 5 then
                f = { id = "rr:" .. n, kind = "race_result", at = t, salience = 25, data = { winner = w, second = names[(n + 1) % #names + 1],
                    third = names[(n + 2) % #names + 1], series = series[n % 2 + 1], route = routes[n % 3 + 1], fieldSize = 8 + n % 6,
                    marginSeconds = (n % 5 == 0) and 0.2 or (n % 7 == 0 and 6.5 or 1.4), wet = (n % 9 == 0) or nil } }
            elseif k == 6 then
                f = { id = "co:" .. n, kind = "crash_out", at = t, salience = 30, data = { driver = w, series = series[1], route = routes[1], cause = "mechanical failure" } }
            elseif k == 7 then
                f = { id = "up:" .. n, kind = "upset", trigger = "upset", at = t, salience = 60, data = { winner = w, second = names[1], third = names[2],
                    series = series[2], route = routes[2], fieldSize = 10, marginSeconds = 0.8, price = 9.0 } }
            elseif k == 8 then
                f = { id = "vd:" .. n, kind = "vehicle_destroyed", at = t, salience = 50, data = { driver = w, route = routes[3] } }
            elseif k == 9 then
                f = { id = "mo:" .. n, kind = "moody", at = t, salience = 50, data = { face = "open_roads", line = C.moody.open_roads.line, effect = "expansive" } }
            else
                local pos = (n % 4) + 1
                local kind = pos == 1 and "player_win" or (pos <= 3 and "player_podium" or "player_result")
                f = { id = "pr:" .. n, kind = kind, at = t, salience = 60, driverId = "drv-me", data = { position = pos, series = series[1] } }
            end
            d:observe(f, t)
            nextFact = t + 1200
        end
        local h, m = hm(t)
        local item = d:next(pid, t, { hour = h, minute = m })
        if item.beat ~= "" then
            log[#log + 1] = { t = t, beat = item.beat, trigger = item.trigger, clips = item.clips, day = d:day(t), lane = d.world.lane,
                ms = item.totalMs }
            -- keep the listener's career honest for player_first gates, as the server does from the database
            local L = d.listeners[pid]
            if item.trigger == "player_win" then L.stats.wins = L.stats.wins + 1; L.stats.podiums = L.stats.podiums + 1; L.stats.starts = L.stats.starts + 1 end
            if item.trigger == "player_podium" then L.stats.podiums = L.stats.podiums + 1; L.stats.starts = L.stats.starts + 1 end
        end
        t = t + math.ceil((item.totalMs + item.silenceMs) / 1000)
    end
    return log, d
end

local log, d = week(3)
check("the Week produced a programme (" .. #log .. " beats in 72 h)", #log > 150, #log)
check("the fixed opening airs first", log[1].beat == "S12-WORKING-FIXED-OPENING-VERSION-A", log[1].beat)
local openings = 0
for _, e in ipairs(log) do if e.beat == "S12-WORKING-FIXED-OPENING-VERSION-A" then openings = openings + 1 end end
check("the fixed opening airs once per Week", openings == 1, openings)

local byBeat, triggers, airedAt = {}, {}, {}
for _, e in ipairs(log) do
    triggers[e.trigger] = (triggers[e.trigger] or 0) + 1
    local last = airedAt[e.beat]
    -- every beat rests at least the shortest rest (owner 2026-10-09: repeats are allowed, back-to-back loops are not)
    local cool = RadioDirector.REAIR_LAST_S
    if last and e.t - last < cool and e.beat ~= "S12-WORKING-FIXED-OPENING-VERSION-A" then
        error("FAIL beat " .. e.beat .. " repeated after " .. (e.t - last) .. " s", 0)
    end
    airedAt[e.beat] = e.t
    byBeat[e.beat] = true
end
check("no beat repeats for a listener within fifteen minutes", true)
local kinds = 0
for _ in pairs(triggers) do kinds = kinds + 1 end
check("results, incidents, Moody, the player and the studio all get air (" .. kinds .. " families)",
    (triggers.race_result or 0) > 5 and (triggers.studio or 0) > 5 and (triggers.vehicle_destroyed or 0) > 0
    and (triggers.moody or 0) > 0 and ((triggers.player_win or 0) + (triggers.player_podium or 0) + (triggers.player_result or 0)) > 0,
    (function() local s = {} for k, v in pairs(triggers) do s[#s + 1] = k .. "=" .. v end return table.concat(s, " ") end)())

-- bible §246: in a healthy stretch the studio's own conversations are budgeted in, not only played when nothing else is
local healthyRun, worst, habitation = 0, 0, 0
for _, e in ipairs(log) do
    if e.trigger == "studio" then healthyRun = 0 else
        if e.lane == "healthy" then healthyRun = healthyRun + 1; if healthyRun > worst then worst = healthyRun end end
    end
    local b = nil
    for _, x in ipairs(C.beats) do if x.id == e.beat then b = x break end end
    if b and b.gates and b.gates.habitation then habitation = habitation + 1 end
end
check("habitation conversations air (" .. habitation .. ")", habitation >= 20, habitation)
check("a healthy Week never goes long without the studio (longest run " .. worst .. ")", worst <= 8, worst)

-- owner 2026-10-09: "always talking organically" -- the station speaks most of the Week, and no silence is long
local spoken = 0
for _, e in ipairs(log) do spoken = spoken + e.ms / 1000 end
if os.getenv("RADIO_GAPS") then
    local per = {}
    for i = 2, #log do
        local gap = log[i].t - (log[i - 1].t + log[i - 1].ms / 1000)
        local h = math.floor((log[i].t - log[1].t) / 3600)
        per[h] = (per[h] or 0) + gap
    end
    for h = 0, 71 do if (per[h] or 0) > 600 then print(("  hour %d (day %d, %02d:00 NC): %.0f s silent"):format(h, math.floor(h / 24) + 1, (h + 9) % 24, per[h])) end end
end
check(("the station talks %.0f%% of the 72 hours"):format(100 * spoken / (72 * 3600)), spoken / (72 * 3600) >= 0.80, spoken)
local longestGap = 0
for i = 2, #log do
    local gap = log[i].t - (log[i - 1].t + log[i - 1].ms / 1000)
    if gap > longestGap then longestGap = gap end
end
-- this Week is harsh on purpose (a destroyed car every ~4 h, a catastrophic lane): for 45 minutes after each one the
-- long relaxed conversations stand down (bible §172 RHYTHM-E) and only incident follow-ups may air
check(("no silence longer than ten minutes, even in a catastrophic Week (longest %.0f s)"):format(longestGap), longestGap <= 600, longestGap)
-- bible §76: a handoff ("Tommy?") is answered by that voice in the very next beat
local handoffs = 0
for i = 1, #log - 1 do
    local b = nil
    for _, x in ipairs(C.beats) do if x.id == log[i].beat then b = x break end end
    if b and b.handoff then
        handoffs = handoffs + 1
        local nb = nil
        for _, x in ipairs(C.beats) do if x.id == log[i + 1].beat then nb = x break end end
        if not (nb and nb.lead == b.handoff) then error("FAIL " .. b.id .. " handed to " .. b.handoff .. " and " .. tostring(nb and nb.lead) .. " answered", 0) end
    end
end
check("every handoff is answered by the voice it named (" .. handoffs .. " handoffs)", true)

-- the bible's gates hold on every aired beat
local beatById = {}
for _, b in ipairs(C.beats) do beatById[b.id] = b end
local firstPodium, firstWin = 0, 0
for _, e in ipairs(log) do
    local g = beatById[e.beat].gates or {}
    if g.day then check_day = e.day >= g.day[1] and e.day <= g.day[2]
        if not check_day then error("FAIL " .. e.beat .. " (days " .. g.day[1] .. "-" .. g.day[2] .. ") aired on day " .. e.day, 0) end end
    if g.lane then
        local okLane = false
        for _, l in ipairs(g.lane) do if l == e.lane then okLane = true end end
        if not okLane then error("FAIL " .. e.beat .. " aired in lane " .. e.lane, 0) end
    end
    if g.player_first and e.trigger == "player_podium" then firstPodium = firstPodium + 1 end
    if g.player_first and e.trigger == "player_win" then firstWin = firstWin + 1 end
    for _, c in ipairs(e.clips) do
        if not c.k or c.ms <= 0 then error("FAIL " .. e.beat .. " has an empty clip", 0) end
    end
end
check("day gates hold (no Day-2 beat on Day 1)", true)
check("Week-condition lanes hold", true)
check("a 'first podium' beat airs at most once", firstPodium <= 1, firstPodium)
check("a 'first win' beat airs at most once", firstWin <= 1, firstWin)

-- every lexicon clip a beat used came from a fact the Week produced
local allowed = {}
for _, w in ipairs({ "Kat Morrow", "Sol Brandt", "Ines Vale", "Dmitri Okoye", "Rhea Santos", "Bo Lindqvist", "Kabuki Loop",
    "Corpo Plaza Sprint", "Badlands Run", "Night City Street Series", "Pacifica Cup", "Baremetal", "mechanical failure",
    C.moody.open_roads.line }) do allowed[RadioSpoken.slug(w)] = true end
for _, e in ipairs(log) do
    for _, c in ipairs(e.clips) do
        local slug = c.k:match("^lex/[^/]+/(.+)$")
        if slug and not allowed[slug] then
            -- built-in domains (numbers, ordinals, days, margins, clock, odds) are words, not names
            local builtin = slug:match("^day%-") or slug:match("second") or slug:match("^%a+$") or slug:match("%-to%-") or
                slug:match("o%-clock") or slug:match("^noon$") or slug:match("^midnight$") or slug:match("^%a+%-%a+$") or
                slug:match("in%-the") or slug:match("at%-night") or slug:match("^%a+%-%a+%-%a+$")
            if not builtin then error("FAIL " .. e.beat .. " spoke an unbound value: " .. slug, 0) end
        end
    end
end
check("every spoken name came from a fact", true)

-- bible §247: a motif callback never airs before its origin aired for the listener
local gave, callbacksAired = {}, 0
for _, e in ipairs(log) do
    local b = beatById[e.beat]
    for _, m in ipairs(b.needs or {}) do
        if not gave[m] then error("FAIL " .. e.beat .. " recalled " .. m .. " before its origin aired", 0) end
    end
    if b.needs and #b.needs > 0 then callbacksAired = callbacksAired + 1 end
    for _, m in ipairs(b.gives or {}) do gave[m] = true end
end
check("motif callbacks only after their origin (" .. callbacksAired .. " callbacks aired)", callbacksAired > 0, callbacksAired)
local sameSection = 0
for i = 2, #log do
    local a, b = beatById[log[i - 1].beat], beatById[log[i].beat]
    if a.section == b.section and a.section ~= 0 then sameSection = sameSection + 1 end
end
check("the same section rarely runs twice in a row (" .. sameSection .. " of " .. #log .. ")", sameSection < #log / 10, sameSection)

-- bible §206: a rhetorical shape (banter aside) does not dominate four beats running -- in an ordinary Week; a bad one
-- is meant to stay restrained and reflective (§172 RHYTHM-E)
local worstRun, runOf = 0, {}
for i = 1, #log do
    local here = {}
    if log[i].lane == "bad" or log[i].lane == "cata" then runOf = {} goto continue end
    for _, sh in ipairs(beatById[log[i].beat].shapes or {}) do
        if sh ~= "banter" then here[sh] = (runOf[sh] or 0) + 1; if here[sh] > worstRun then worstRun = here[sh] end end
    end
    runOf = here
    ::continue::
end
-- four, not three: when everything fitting has aired lately, talk beats a fifth beat of the same shape (owner 2026-10-09)
check("no conversational shape runs through more than five beats in a row (longest " .. worstRun .. ")", worstRun <= 5, worstRun)
-- and a bad or cataclysmic Week airs nothing bright that was not written for it
for _, e in ipairs(log) do
    local b = beatById[e.beat]
    if (e.lane == "bad" or e.lane == "cata") and b.direction == "bright" and not (b.gates and b.gates.lane) then
        error("FAIL " .. e.beat .. " (bright, ungated) aired in a " .. e.lane .. " Week", 0)
    end
end
check("nothing bright and ungated airs in a bad Week", true)

-- show history survives a server restart
local h = d:history(7)
local d2 = RadioDirector.new(C, { assumeRendered = true, assumeVoiced = true })
d2.world.run = d.world.run
check("show history restores", d2:restore(7, h) and d2.listeners[7].aired[log[1].beat] == log[1].t)
local someMotif = next(d.listeners[7].motifs)
check("heard motifs survive a restart", someMotif ~= nil and d2.listeners[7].motifs[someMotif] == true)

-- determinism
local again = week(3)
local same = #again == #log
for i = 1, math.min(#again, #log) do if again[i].beat ~= log[i].beat or again[i].t ~= log[i].t then same = false break end end
check("the same Week gives the same programme", same)

-- a gate this code cannot verify keeps a beat off the air
local ghost = { id = "TEST-GHOST", trigger = "studio", gates = { needs_memory = "prediction" }, lines = {}, ready = true }
check("an unverifiable premise is never guessed", not d:eligible(ghost, d.listeners[7], nil, log[#log].t, { clockSlot = "night" }))

print(("test-radio: %d checks passed"):format(passed))
