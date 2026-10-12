-- ncm_radio / server / director -- Race Week Live's editor: which authored beat airs next, for one listener (doc 59 §3,
-- bible §51 and §174). Pure: no database, no network, no clock of its own -- `main.lua` feeds it facts and the time.
--
-- The bible's selection order, as code:
--   1. what owns attention (a pending fact for this listener, else the station's own clock: the Week's opening, a
--      day boundary, a time of day; else the studio's long-form reservoir);
--   2. salience: NCM's own number for the fact, + the listener's own involvement;
--   3. the authored family the fact's trigger names (corpus `trigger`);
--   4. the gates the bible states for each beat (day, Week condition, how early, whose result, ...);
--   5. a whole beat that has not aired lately -- never a random line (bible §150: variance is the shape of attention);
--   6. every slot bound to a fact AND to a voiced clip; a gate or a slot this code cannot verify makes the beat
--      ineligible rather than guessed (bible §9.4: characters may be wrong in opinion, never in supplied fact);
--   7. continuity (bible §76): a thread -- the race the show committed to, the conversation it is in, the voice it
--      just handed to -- outranks a fresher fact; a handoff ("Tommy?") airs only when that voice can answer next;
--   8. the station talks (owner, 2026-10-09: "always talking organically ... allowed to repeat"): about a second
--      between beats, repeats allowed after a short rest, silence only when nothing authored can be said truthfully.
-- LuaJIT ∩ Lua 5.4.
RadioDirector = {}
local D = RadioDirector
D.__index = D

local S = RadioSpoken

-- How long a fact stays worth airing after it happened (seconds). Older facts are learned silently.
D.TTL = {
    week_open = 3 * 3600, race_preview = 0, race_start = 120, race_result = 25 * 60, upset = 30 * 60, streak = 45 * 60,
    first_win = 45 * 60, crash_out = 20 * 60, feud = 60 * 60, vehicle_destroyed = 60 * 60, chrome_attack = 30 * 60,
    org = 3 * 3600, title = 3 * 3600, rnd_release = 3 * 3600, moody = 90 * 60, policy = 90 * 60, standings = 60 * 60,
    player_entered = 15 * 60, player_result = 30 * 60, player_win = 30 * 60, player_podium = 30 * 60, player_dnf = 30 * 60,
    player_position = 90, week_end = 6 * 3600,
}
-- A fact can select beats of more than its own trigger (a win is also a result; a player's result is a result).
D.ALSO = {
    upset = { "race_result" }, player_win = { "player_result" }, player_podium = { "player_result" },
}
-- Gates that describe a beat rather than restrict it.
local SOFT = { segment = true, longform = true, fixed = true, priority = true, recap = true, guard = true, why = true,
    running_joke = true, closing = true }
-- Habitation (bible §210, §246): how many mundane conversations an hour the Week's condition leaves room for.
-- "Healthy Race Week has room to be bored. Troubled Race Week keeps stealing that room."
D.HABITATION_PER_HOUR = { healthy = 4, slight = 3, subpar = 2, bad = 1, cata = 0 }
D.HABITATION_RUN = 2
-- Clock slots in Night City time (the Paddock's US-Eastern clock).
local function clockSlot(h)
    if h >= 5 and h < 7 then return "dawn" end
    if h >= 7 and h < 11 then return "morning" end
    if h >= 11 and h < 14 then return "midday" end
    if h >= 14 and h < 18 then return "afternoon" end
    if h >= 18 and h < 20 then return "sunset" end
    if h >= 0 and h < 2 then return "midnight" end
    return "night"
end
D.clockSlot = clockSlot

local LANE_OF_MOOD = { euphoric = "healthy", buoyant = "healthy", uneasy = "slight", tense = "subpar", hostile = "bad" }

-- A string hash for deterministic tie-breaks (a restart re-airs nothing differently). Every intermediate stays below
-- 2^37, so Lua 5.4 (integers) and LuaJIT (doubles) compute the same value: the Online server and the single-player
-- host must air the same Week.
local function hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 2147483647
    end
    return h
end
D.hash = hash

function D.new(corpus, opts)
    local self = setmetatable({}, D)
    self.corpus = corpus
    self.opts = opts or {}
    corpus.lex, corpus.stings = corpus.lex or {}, corpus.stings or {}
    self.byTrigger = {}
    for i, b in ipairs(corpus.beats) do
        b.order = i                               -- bible order: a section's beats read as one conversation
        if b.trigger ~= "dormant" and (b.ready or self.opts.assumeRendered) and not b.example then
            local list = self.byTrigger[b.trigger] or {}
            list[#list + 1] = b
            self.byTrigger[b.trigger] = list
        end
    end
    self.slug = corpus.speakers
    self.world = {
        run = nil, openedAt = nil, lane = "healthy", mood = nil,
        results = 0, winners = {}, winnerOrder = {}, lastWinner = nil, recent = {}, dnfs = {}, firstOf = {},
        resultsByDay = {},
    }
    self.listeners = {}
    self.seq = 0
    return self
end

-- ---- world memory -------------------------------------------------------------------------------------------

function D:hours(now)
    if not self.world.openedAt then return nil end
    return math.max(0, (now - self.world.openedAt) / 3600)
end

function D:day(now)
    local h = self:hours(now)
    return h and (math.floor(h / 24) + 1) or nil
end

local function laneFor(world, now)
    local lane = LANE_OF_MOOD[world.mood or ""] or world.lane or "healthy"
    -- a hostile city with repeated destroyed cars in the last six hours is the bible's cataclysm lane
    local destroyed = 0
    for _, at in ipairs(world.destroyedAt or {}) do
        if now - at <= 6 * 3600 then destroyed = destroyed + 1 end
    end
    if lane == "bad" and destroyed >= 2 then lane = "cata" end
    if lane == "healthy" and destroyed >= 1 then lane = "slight" end
    return lane
end

--- A fact from the simulation. Every fact is remembered (the show has memory, bible §24); a fresh one is queued for
--- every listener it may concern. `f = { id, kind, at, salience, data = {...}, driverId = <player it concerns> }`.
function D:observe(f, now)
    local w = self.world
    local d = f.data or {}
    if f.kind == "week_open" then
        w.run, w.openedAt = d.run, f.at
        w.results, w.winners, w.winnerOrder, w.lastWinner, w.recent, w.dnfs, w.firstOf = 0, {}, {}, nil, {}, {}, {}
        w.resultsByDay, w.destroyedAt, w.mood = {}, {}, nil
    elseif f.kind == "week_vibe" then
        w.mood = d.mood
        return                                   -- tints the lane; never aired on its own
    end
    -- the facts a result-shaped beat reads at airing time are the state BEFORE this fact
    f.before = { results = w.results, winnerCount = d.winner and (w.winners[d.winner] or 0) or 0,
        driverDnfs = d.driver and (w.dnfs[d.driver] or 0) or 0, firstOfKind = not w.firstOf[f.kind] }
    if f.kind == "race_result" then
        w.results = w.results + 1
        f.ordinal = w.results
        if d.winner then
            w.winners[d.winner] = (w.winners[d.winner] or 0) + 1
            w.winnerOrder[#w.winnerOrder + 1] = d.winner
            w.lastWinner = d.winner
        end
        local day = self:day(f.at) or 0
        w.resultsByDay[day] = (w.resultsByDay[day] or 0) + 1
    elseif f.kind == "crash_out" and d.driver then
        w.dnfs[d.driver] = (w.dnfs[d.driver] or 0) + 1
    elseif f.kind == "vehicle_destroyed" then
        w.destroyedAt = w.destroyedAt or {}
        w.destroyedAt[#w.destroyedAt + 1] = f.at
    end
    w.firstOf[f.kind] = true
    w.recent[f.kind] = f.at
    w.lane = laneFor(w, now or f.at)
    local ttl = D.TTL[f.kind]
    if ttl == nil or (now and now - f.at > ttl and f.kind ~= "race_preview") then return end
    for _, L in pairs(self.listeners) do
        if not f.driverId or f.driverId == L.driverId then
            L.queue[#L.queue + 1] = f
        end
    end
end

-- ---- listeners ----------------------------------------------------------------------------------------------

function D:listener(pid, info)
    local L = self.listeners[pid]
    if not L then
        L = { pid = pid, queue = {}, aired = {}, airedTrigger = {}, heard = {}, stats = { starts = 0, podiums = 0, wins = 0, dnfs = 0 },
            lastLead = nil, lastSegment = nil, current = nil, motifs = {}, recentShapes = {} }
        self.listeners[pid] = L
    end
    if info then
        L.driverId = info.driverId or L.driverId
        L.name = info.name or L.name
        if info.stats then L.stats = info.stats end
    end
    return L
end

function D:drop(pid) self.listeners[pid] = nil end

-- ---- eligibility --------------------------------------------------------------------------------------------

local function within(range, v)
    if not range then return true end
    if v == nil then return false end
    return v >= range[1] and v <= range[2]
end

local function inList(list, v)
    if not list then return true end
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local function moodyTone(d)
    local t = tostring(d.effect or d.becomes or d.face or ""):lower()
    if t:find("purse") or t:find("money") or t:find("bounty") then return "economic" end
    if t:find("limit_up") or t:find("faster") or t:find("open") then return "expansive" end
    if t:find("limit_down") or t:find("police") or t:find("curfew") or t:find("slow") then return "restrictive" end
    return nil
end

--- Can this beat air now for this listener, given the fact that summoned it (or nil for station-clock material)?
function D:eligible(b, L, f, now, ctx)
    local g = b.gates or {}
    local w = self.world
    local d = f and f.data or {}
    local day, hours = self:day(now), self:hours(now)
    -- bible §9.10 "seriousness reduces ornament": in a bad or cataclysmic Week the studio still talks, but nothing
    -- performed bright ("Yes!") and no joke-carried utility beat airs unless it was written for that Week
    if (w.lane == "bad" or w.lane == "cata") and not g.lane then
        if b.direction == "bright" then return false end
        for _, sh in ipairs(b.shapes or {}) do if sh == "joke_utility" then return false end end
    end
    -- bible §206: two short joke-carried utility beats never run back to back; a pause is better radio than a third gag
    local last = L.recentShapes and L.recentShapes[1]
    if last and last.joke_utility then
        for _, sh in ipairs(b.shapes or {}) do if sh == "joke_utility" then return false end end
    end
    -- bible §247 show history: a callback airs only after its origin aired for this listener
    for _, m in ipairs(b.needs or {}) do
        if not L.motifs[m] then return false end
    end
    for k, v in pairs(g) do
        if SOFT[k] then
            -- descriptive only
        elseif k == "day" then if not within(v, day) then return false end
        elseif k == "hour" then if not within(v, hours) then return false end
        elseif k == "lane" then if not inList(v, w.lane) then return false end
        elseif k == "week_race" then if not (f and within(v, f.ordinal or (f.before and f.before.results + 1))) then return false end
        elseif k == "winner" then
            if not (f and d.winner) then return false end
            local n = f.before and f.before.winnerCount or 0
            if v == "new" and n > 0 then return false end
            if v == "repeat" and n == 0 then return false end
        elseif k == "close" then
            local m = tonumber(d.marginSeconds)
            if not (d.closeFinish or (m and m < 0.5)) then return false end
        elseif k == "dominant" then
            local m = tonumber(d.marginSeconds)
            if not (m and m >= 5) then return false end
        elseif k == "wet" then if not d.wet then return false end
        elseif k == "cause" then
            local c = tostring(d.cause or ""):lower()
            if v == "mechanical" and not c:find("mechanical") then return false end
            if v == "crash" and not c:find("crash") then return false end
            if v == "hack" and not (d.hack or c:find("hack")) then return false end
        elseif k == "first" then if not (f and f.before and f.before.firstOfKind) then return false end
        elseif k == "repeat" then if not (f and f.before and (f.before.driverDnfs or 0) >= 1) then return false end
        elseif k == "priced" then if not d.price then return false end
        elseif k == "tone" then if not (f and moodyTone(d) == v) then return false end
        elseif k == "needs_recent" then
            local at = w.recent[v]
            if not at or now - at > 6 * 3600 then return false end
        elseif k == "followup" then
            local at = w.recent[b.trigger]
            if not at or now - at > 2 * 3600 or (f and f.at == at) then return false end
        elseif k == "min_results" then if (w.results or 0) < v then return false end
        elseif k == "min_hours" then if not (hours and hours >= v) then return false end
        elseif k == "clock" then
            local slot = ctx.clockSlot
            if v == "nightish" then
                if not (slot == "night" or slot == "midnight" or slot == "dawn") then return false end
            elseif slot ~= v then return false end
        elseif k == "habitation" and ctx and ctx.relax then
            -- the budget paces the studio against the news; it is never the reason the room goes silent
        elseif k == "habitation" then
            local cap = D.HABITATION_PER_HOUR[w.lane] or 0
            local n = 0
            for _, t in ipairs(L.habitation or {}) do if now - t < 3600 then n = n + 1 end end
            if n >= cap then return false end
            if (L.habRun or 0) >= D.HABITATION_RUN then return false end
        elseif k == "rare" then
            -- bible §244 "broad but rare, substantial cooldown": once in two days for a listener
            local last = L.aired[b.id]
            if last and now - last < 48 * 3600 then return false end
        elseif k == "no_recent" then
            -- "avoid during severe incident coverage": not while it is being covered (45 minutes), not for hours after
            local at = w.recent[v]
            if at and now - at < 45 * 60 then return false end
        elseif k == "quiet" then if #L.queue > 0 and not (ctx and ctx.relax) then return false end
        elseif k == "final" then if day ~= 7 then return false end
        elseif k == "player_first" then
            local s = L.stats
            if b.trigger == "player_entered" and s.starts > 0 then return false end
            if b.trigger == "player_podium" and s.podiums > 0 then return false end
            if b.trigger == "player_win" and s.wins > 0 then return false end
        elseif k == "player_starts" then if not within(v, L.stats.starts) then return false end
        elseif k == "player_wins" then if (L.stats.wins or 0) < 1 then return false end
        elseif k == "player_podiums" then if (L.stats.podiums or 0) < 1 then return false end
        elseif k == "player_dnfs" then if (L.stats.dnfs or 0) < v then return false end
        elseif k == "kind" then if not (f and d.kind == v) then return false end
        else
            return false                     -- a premise this code cannot verify yet: never guess it
        end
    end
    return true
end

-- ---- slots --------------------------------------------------------------------------------------------------

local function nthWinner(w, n) return w.winnerOrder[n] end

--- The values a beat may speak, from the fact, the Week and the listener. Nothing here is invented: an absent fact
--- leaves its slot unbound and the beat ineligible.
function D:context(L, f, now, ctx)
    local w = self.world
    local d = f and f.data or {}
    local v = {}
    local function set(names, value, cls)
        if value == nil or value == "" then return end
        for _, n in ipairs(names) do if v[n] == nil then v[n] = { value = value, cls = cls } end end
    end
    set({ "WINNER", "NEW_WINNER" }, d.winner, "name")
    set({ "P2" }, d.second, "name")
    set({ "P3" }, d.third, "name")
    set({ "DRIVER" }, d.driver or d.winner, "name")
    set({ "DRIVER_A", "A" }, d.driverA, "name")
    set({ "DRIVER_B", "B" }, d.driverB, "name")
    set({ "ATTACKER" }, d.attacker, "name")
    set({ "TARGET" }, d.target, "name")
    set({ "CHAMPION" }, d.champion, "name")
    set({ "LEADER" }, d.leader, "name")
    set({ "POINTS" }, d.points, "number")
    set({ "TEAM", "DRIVER_OR_TEAM" }, d.org, "org")
    set({ "SPONSOR" }, d.sponsor, "org")
    set({ "EVENT_NAME", "EVENT", "SERIES" }, d.series, "series")
    set({ "TITLE" }, d.title or d.series, "series")
    set({ "LOCATION", "ROUTE", "VENUE_OR_ROUTE" }, d.route, "route")
    set({ "FIELD_SIZE" }, d.fieldSize, "number")
    set({ "COUNT", "STREAK" }, d.count, "number")
    set({ "STARTS" }, d.starts, "number")
    set({ "MARGIN", "GAP", "SUPPORTED_GAP" }, d.marginSeconds, "margin")
    set({ "ODDS", "SUPPORTED_ODDS" }, d.price, "odds")
    set({ "SUPPORTED_DNF_REASON", "SUPPORTED_REASON" }, d.cause, "phrase")
    set({ "PUBLISHED_MOODY_CHANGE", "PUBLISHED_CHANGE" }, d.line, "phrase")
    set({ "PUBLISHED_POLICY_CHANGE", "PUBLISHED_CHANGE" }, d.announcement, "phrase")
    set({ "POSITION", "FINISH_POSITION" }, d.position, "ordinal")
    set({ "GRID_POSITION" }, d.grid, "ordinal")
    if d.opensHour then set({ "TIME", "START_TIME" }, { d.opensHour, d.opensMinute or 0 }, "clock") end
    -- the listener (bible §6: the player is one subject among many; their name only where the beat says so)
    set({ "PLAYER_NAME" }, L.name, "name")
    -- the Week's memory
    local day = self:day(now)
    set({ "DAY" }, day, "day")
    set({ "R1_WINNER", "WINNER_1" }, nthWinner(w, 1), "name")
    set({ "R2_WINNER", "WINNER_2" }, nthWinner(w, 2), "name")
    set({ "WINNER_3" }, nthWinner(w, 3), "name")
    set({ "WINNER_COUNT" }, (function() local n = 0 for _ in pairs(w.winners) do n = n + 1 end return n > 0 and n or nil end)(), "number")
    -- station material with no fact of its own speaks of the most recent winner (bible §23 "too many names")
    if not f then set({ "DRIVER", "WINNER" }, w.lastWinner, "name") end
    return v
end

--- The spoken words of a bound value, by class.
local function words(entry)
    local c, x = entry.cls, entry.value
    if c == "name" or c == "org" or c == "series" or c == "route" or c == "phrase" then return tostring(x) end
    if c == "number" then return S.number(x) end
    if c == "ordinal" then return S.ordinal(x) end
    if c == "day" then return S.day(x) end
    if c == "margin" then return S.margin(x) end
    if c == "odds" then return S.odds(x) end
    if c == "clock" and type(x) == "table" then return S.clock(x[1], x[2]) end
    return nil
end
D.words = words

--- Perform a beat into clips, or nil + why when any part cannot be performed truthfully.
function D:perform(b, values)
    local corpus = self.corpus
    local gap = corpus.gap_ms or 260
    local clips, total, skipped = {}, 0, 0
    for _, line in ipairs(b.lines) do
        if line.cue then
            local ms = corpus.stings[line.cue]
            if ms and ms > 0 then
                clips[#clips + 1] = { k = line.cue, ms = ms, gap = 180 }
                total = total + ms + 180
            end
        else
            local out, ok, why = {}, true, nil
            local spk = self.slug[line.sp] or line.sp
            -- a role with several voices (different drivers) keeps one voice for the whole beat
            local v = (line.nv and line.nv > 1) and (hash(b.id .. "|" .. line.sp) % line.nv) or 0
            for _, p in ipairs(line.parts) do
                if p.k then
                    local pms = p.ms or 0
                    local key = p.k
                    if v > 0 then key, pms = p.k .. "@" .. v, (p.vms and p.vms[v]) or 0 end
                    if pms <= 0 and self.opts.assumeRendered then pms = 1000 end   -- tests only: the render is a separate gate
                    if pms <= 0 then ok, why = false, "unrendered " .. key break end
                    out[#out + 1] = { k = key, ms = pms, gap = 0 }
                else
                    local entry = values[p.slot]
                    if not entry then ok, why = false, "unbound " .. p.slot break end
                    local said = words(entry)
                    if not said then ok, why = false, "unspeakable " .. p.slot break end
                    local key = "lex/" .. spk .. "/" .. S.slug(said)
                    local ms = corpus.lex[key]
                    if (not ms or ms <= 0) and self.opts.assumeVoiced then ms = 800 end   -- tests only
                    if not ms or ms <= 0 then ok, why = false, "unvoiced " .. key break end
                    out[#out + 1] = { k = key, ms = ms, gap = 0 }
                end
            end
            if ok and #out > 0 then
                out[#out].gap = gap
                for _, c in ipairs(out) do clips[#clips + 1] = c; total = total + c.ms + c.gap end
            else
                -- every line of an authored conversation is said, or the conversation does not air: a dropped line
                -- leaves the others answering nothing ("Okay." after Imani's missing update; owner 2026-10-09)
                return nil, why or "empty line " .. line.id
            end
        end
    end
    if #clips == 0 then return nil, "nothing to say" end
    return clips, total, skipped
end

-- ---- choosing -----------------------------------------------------------------------------------------------

-- A beat rests this long before it may air again for a listener (bible §144); after that, how long ago it aired is a
-- preference, not a wall -- the Week is 72 hours and the station keeps talking (bible §9.8 "repetition is acceptable
-- when human"; owner 2026-10-09 "allowed to repeat during race week"). When nothing has rested, the shortest rest
-- (RELAX) applies before the station would fall silent.
local REAIR_S = 90 * 60
local REAIR_STUDIO_S = 45 * 60
local REAIR_RELAX_S = 20 * 60
-- and the floor: a quiet stretch with little that fits (early Day 1) repeats a conversation rather than going silent
local REAIR_LAST_S = 15 * 60
D.REAIR_S, D.REAIR_STUDIO_S, D.REAIR_RELAX_S, D.REAIR_LAST_S = REAIR_S, REAIR_STUDIO_S, REAIR_RELAX_S, REAIR_LAST_S
-- the triggers a voice that was just handed the air may answer from (bible §76 "deliberate handoff")
local ANSWERS = { "race_start", "race_result", "handoff", "studio", "clock" }
local STATION = { studio = true, clock = true, handoff = true }

--- The best performable beat of `trigger` for this listener, or nil. `opt.lead`: only beats that voice opens (the
--- answer to a handoff); `opt.relax`: the shortest rest; `opt.noHandoff`: no beat that hands the air on.
function D:pick(L, trigger, f, now, ctx, opt)
    opt = opt or {}
    local list = self.byTrigger[trigger]
    if not list then return nil end
    local values = self:context(L, f, now, ctx)
    local best, bestScore, bestClips, bestTotal
    local wasRelax = ctx.relax
    ctx.relax = opt.relax
    for _, b in ipairs(list) do
        local last = L.aired[b.id]
        local fixed = b.gates and b.gates.fixed
        local cool = (opt.relax == "last" and REAIR_LAST_S) or (opt.relax and REAIR_RELAX_S)
            or ((trigger == "studio" or trigger == "clock") and REAIR_STUDIO_S or REAIR_S)
        if (not opt.lead or b.lead == opt.lead) and not (opt.noHandoff and b.handoff)
            and (fixed or not last or now - last > cool) and self:eligible(b, L, f, now, ctx) then
            local clips, total, skipped = self:perform(b, values)
            -- a beat that hands the air on airs only when that voice can answer at once (no "Tommy?" into silence)
            if clips and b.handoff and not self:answerable(L, b.handoff, f, now, ctx, b.id) then clips = nil end
            if clips then
                -- never-aired first, then how long it has rested (capped: after half a day it is fresh again); then a
                -- different lead than the last beat (bible §101); then specificity; a stable hash breaks ties
                local score = (last and math.min((now - last) / 3600, 12) * 2 or 30) + (b.lead ~= L.lastLead and 3 or 0)
                -- bible §76 thread continuity: the conversation the studio is in carries on -- the next beats of the
                -- same section in bible order most of all. Event families are variants of one moment, so those rotate.
                if STATION[trigger] and L.thread and b.section == L.thread.section and (b.section or 0) ~= 0 then
                    score = score + 10
                    if b.order > L.thread.order and b.order <= L.thread.order + 3 then score = score + 20 end
                elseif b.section and b.section == L.lastSection then
                    score = score - 15
                end
                -- a conversation with lines it could not say is a thinner conversation
                score = score - 6 * (skipped or 0)
                -- bible §206: rhetorical shapes heard in the last four beats cool down independently
                for _, sh in ipairs(b.shapes or {}) do
                    -- banter is the show's tonal centre (bible §4), not a manoeuvre to rotate
                    if sh ~= "banter" then
                        -- the beat just before weighs most: a shape heard one beat ago is -12, two to four beats ago -4
                        for i, recent in ipairs(L.recentShapes) do
                            if recent[sh] then score = score - (i == 1 and 12 or 4) end
                        end
                    end
                end
                -- a callback whose origin the listener heard is worth more than a cold conversation
                if b.needs and #b.needs > 0 then score = score + 4 end
                if b.segment ~= L.lastSegment then score = score + 1 end
                for _ in pairs(b.gates or {}) do score = score + 2 end
                score = score + (hash(tostring(L.pid) .. b.id .. tostring(self:day(now))) % 1000) / 1000
                if not best or score > bestScore then best, bestScore, bestClips, bestTotal = b, score, clips, total end
            end
        end
    end
    ctx.relax = wasRelax
    return best, bestClips, bestTotal
end

--- Can `lead` take a handoff right now, with a beat other than `except`? Station material answers without the fact.
function D:answerable(L, lead, f, now, ctx, except)
    for _, t in ipairs(ANSWERS) do
        local ff = STATION[t] and nil or f
        local values
        for _, b in ipairs(self.byTrigger[t] or {}) do
            if b.lead == lead and b.id ~= except and not b.handoff then
                local last = L.aired[b.id]
                if (not last or now - last > REAIR_RELAX_S) and self:eligible(b, L, ff, now, ctx) then
                    values = values or self:context(L, ff, now, ctx)
                    if self:perform(b, values) then return true end
                end
            end
        end
    end
    return false
end

local function salience(f, L)
    local s = f.salience or 20
    if f.driverId and f.driverId == L.driverId then s = s + 30 end
    return s
end

--- The next programme item for listener `pid` at `now` (unix seconds), given `ctx = { hour, minute }` in Night City
--- time. Returns { seq, beat, clips = { {k, ms, gap} }, totalMs, silenceMs } -- or a pure silence item.
function D:next(pid, now, ctx)
    local L = self:listener(pid)
    ctx = ctx or {}
    ctx.clockSlot = clockSlot(ctx.hour or 12)
    self.lastCtx = ctx
    local w = self.world
    local day = self:day(now)

    -- -1. a handoff is answered by the voice it named, before anything else (bible §76)
    if L.follow then
        local fw = L.follow
        L.follow = nil
        if now <= fw.untilAt then
            for _, t in ipairs(ANSWERS) do
                local ff = (not STATION[t]) and fw.fact or nil
                local b, clips, total = self:pick(L, t, ff, now, ctx, { lead = fw.lead, relax = true, noHandoff = true })
                if b then
                    L.answering = true
                    local item = self:air(L, b, clips, total, now, ff)
                    L.answering = nil
                    return item
                end
            end
        end
    end

    -- 0. the studio's own room (bible §210, §246): habitation is budgeted, not emergency filler. After a run of
    --    factual items a conversation airs before the next routine fact; a fact that matters (salience 55+) still
    --    goes first. Healthy Weeks have room to be bored; a troubled Week keeps stealing it; a bad one has none.
    local budget = ({ healthy = 2, slight = 3, subpar = 5 })[w.lane]
    if budget and (L.sinceStudio or 0) >= budget then
        local urgent = false
        for _, f in ipairs(L.queue) do if salience(f, L) >= 55 and now - f.at <= (D.TTL[f.kind] or 0) then urgent = true end end
        if not urgent then
            local b, clips, total = self:pick(L, "studio", nil, now, ctx)
            if b then return self:air(L, b, clips, total, now, nil) end
        end
    end

    -- 1. facts waiting for this listener, freshest-most-salient first; stale ones are learned and dropped
    local keep = {}
    for _, f in ipairs(L.queue) do
        local ttl = D.TTL[f.kind] or 0
        if f.kind == "race_preview" then
            if (f.data.opensAt or 0) > now then keep[#keep + 1] = f end
        elseif now - f.at <= ttl then
            keep[#keep + 1] = f
        end
    end
    -- a total order (salience, recency, id): table.sort is not stable, and Lua 5.4 and LuaJIT must air the same Week
    table.sort(keep, function(a, b)
        local sa, sb = salience(a, L), salience(b, L)
        if sa ~= sb then return sa > sb end
        if a.at ~= b.at then return a.at > b.at end
        return tostring(a.id) < tostring(b.id)
    end)
    L.queue = keep
    -- bible §76: "do not bounce between races" -- while the show is committed to a race, another race's routine news
    -- waits (and may expire: missing a story is allowed); a fact that matters (55+) still breaks in
    local committed = L.race and now <= L.race.untilAt and L.race.id or nil
    local waiting = {}
    for i, f in ipairs(keep) do
        local elsewhere = committed and f.data and f.data.race and f.data.race ~= committed and salience(f, L) < 55
        if elsewhere then
            waiting[#waiting + 1] = f
        else
            local triggers = { f.trigger or f.kind }
            for _, t in ipairs(D.ALSO[f.kind] or {}) do triggers[#triggers + 1] = t end
            -- every family rested first; then the least recently aired fitting treatment, so a result is called
            -- rather than skipped because its words were used an hour ago
            for _, relax in ipairs({ false, true }) do
                for _, t in ipairs(triggers) do
                    local b, clips, total = self:pick(L, t, f, now, ctx, { relax = relax })
                    if b then
                        table.remove(L.queue, i)
                        return self:air(L, b, clips, total, now, f)
                    end
                end
            end
        end
    end
    L.queue = waiting                         -- nothing authored fits what is pending: never invent coverage

    -- 2. the station's own clock
    if w.run and L.heard["open:" .. tostring(w.run)] == nil and self:hours(now) and self:hours(now) < 3 then
        L.heard["open:" .. tostring(w.run)] = now
        local b, clips, total = self:pick(L, "week_open", nil, now, ctx)
        if b then return self:air(L, b, clips, total, now, nil) end
    end
    if day and day >= 2 and not L.heard["dayopen:" .. day] and (self:hours(now) - (day - 1) * 24) < 4 then
        L.heard["dayopen:" .. day] = now
        local b, clips, total = self:pick(L, "day_open", nil, now, ctx)
        if b then return self:air(L, b, clips, total, now, nil) end
    end
    if day and not L.heard["dayclose:" .. day] and (self:hours(now) - (day - 1) * 24) >= 21 then
        L.heard["dayclose:" .. day] = now
        local b, clips, total = self:pick(L, "day_close", nil, now, ctx)
        if b then return self:air(L, b, clips, total, now, nil) end
    end
    local slotKey = "clock:" .. tostring(day) .. ":" .. ctx.clockSlot
    if not L.heard[slotKey] then
        L.heard[slotKey] = now
        local b, clips, total = self:pick(L, "clock", nil, now, ctx)
        if b then return self:air(L, b, clips, total, now, nil) end
    end
    if (w.results or 0) >= 3 and (not L.heard.standings or now - L.heard.standings > 3 * 3600) then
        L.heard.standings = now
        local b, clips, total = self:pick(L, "standings", nil, now, ctx)
        if b then return self:air(L, b, clips, total, now, nil) end
    end

    -- 3. the studio's reservoir: the conversations whose gates the Week satisfies. The hosts' segues ("handoff"
    --    family) are transitions, never filler: chained, they are the chopped-up sound the owner heard (2026-10-09)
    for _, t in ipairs({ "studio" }) do
        local b, clips, total = self:pick(L, t, nil, now, ctx)
        if b then return self:air(L, b, clips, total, now, nil) end
    end
    -- 4. everything has aired lately: the least recently aired material comes round again before the room goes quiet
    for _, relax in ipairs({ true, "last" }) do
        for _, t in ipairs({ "studio", "clock" }) do
            local b, clips, total = self:pick(L, t, nil, now, ctx, { relax = relax })
            if b then return self:air(L, b, clips, total, now, nil) end
        end
    end
    -- 5. truly nothing can be said truthfully: a short silence, then look again
    return self:silence(L, now, 8000)
end

-- The breath between beats (bible §66, §172): about a second, a little longer at night and in a bad Week. The
-- station is a talk station; long silences come only from §5 above, when nothing can be said.
function D:silenceMs(now, ctx)
    local slot = clockSlot(ctx and ctx.hour or 12)
    local base = (slot == "night" or slot == "midnight" or slot == "dawn") and 1800 or 1100
    local lane = self.world.lane
    if lane == "bad" or lane == "cata" then base = base + 700 end
    return base
end

function D:air(L, b, clips, total, now, f)
    self.seq = self.seq + 1
    L.aired[b.id] = now
    L.airedTrigger[b.trigger] = now
    if b.trigger == "week_open" then L.heard["open:" .. tostring(self.world.run)] = now end
    L.lastLead = b.lead
    L.lastSection = b.section
    -- the threads (bible §76): the voice a handoff named answers next; a race the show previews or starts is seen
    -- through to its result; the studio's conversation is remembered across an interruption and returned to
    if b.handoff then L.follow = { lead = b.handoff, fact = f, untilAt = now + 300 } end
    local race = f and f.data and f.data.race
    if race then
        if b.trigger == "race_result" or f.kind == "race_result" then
            if L.race and L.race.id == race then L.race = nil end
        else
            L.race = { id = race, untilAt = now + 40 * 60 }
        end
    end
    if STATION[b.trigger] then L.thread = { section = b.section, order = b.order } end
    for _, m in ipairs(b.gives or {}) do L.motifs[m] = true end
    local set = {}
    for _, sh in ipairs(b.shapes or {}) do set[sh] = true end
    table.insert(L.recentShapes, 1, set)
    L.recentShapes[5] = nil
    L.sinceStudio = (b.trigger == "studio") and 0 or ((L.sinceStudio or 0) + 1)
    if b.gates and b.gates.habitation then
        L.habitation = L.habitation or {}
        table.insert(L.habitation, 1, now)
        L.habitation[9] = nil
        L.habRun = (L.habRun or 0) + 1
    else
        L.habRun = 0
    end
    -- a segment change is audible before its first word (bible §10): the station ident between rooms
    -- -- but never in front of a few words, and never between a handoff and its answer
    if L.lastSegment and L.lastSegment ~= b.segment and self.corpus.stings["sting/ident"] and total >= 8000
        and not L.answering then
        local ms = self.corpus.stings["sting/ident"]
        table.insert(clips, 1, { k = "sting/ident", ms = ms, gap = 300 })
        total = total + ms + 300
    end
    L.lastSegment = b.segment
    local item = { seq = self.seq, beat = b.id, trigger = b.trigger, fact = f and f.id or nil, clips = clips,
        totalMs = total, silenceMs = self:silenceMs(now, self.lastCtx) }
    L.current = item
    return item
end

--- What a listener's show history is, for saving between server restarts (bible §247: "show history"): when each
--- beat last aired, the motifs they have heard, the station-clock moments already used. Pure data, JSON-safe.
function D:history(pid)
    local L = self.listeners[pid]
    if not L then return nil end
    local motifs = {}
    for m in pairs(L.motifs) do motifs[#motifs + 1] = m end
    return { v = 1, run = self.world.run, aired = L.aired, motifs = motifs, heard = L.heard }
end

function D:restore(pid, h)
    local L = self:listener(pid)
    if type(h) ~= "table" or h.v ~= 1 then return false end
    for k, t in pairs(h.aired or {}) do if type(t) == "number" then L.aired[k] = t end end
    for _, m in ipairs(h.motifs or {}) do L.motifs[m] = true end
    -- the station clock's "once per day/Week" marks only hold within the same Week
    if h.run == self.world.run then
        for k, t in pairs(h.heard or {}) do if type(t) == "number" then L.heard[k] = t end end
    end
    return true
end

function D:silence(L, now, ms)
    self.seq = self.seq + 1
    local item = { seq = self.seq, beat = "", clips = {}, totalMs = 0, silenceMs = ms }
    L.current = item
    return item
end
