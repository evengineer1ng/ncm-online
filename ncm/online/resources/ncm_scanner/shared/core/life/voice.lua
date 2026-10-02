-- ncm-core module: life.voice
-- How a Paddock person SOUNDS, and what they say right now (owner, 2026-09-30: "everyone from dex to setup stu to
-- jia sounds like the same person ... prioritizing uniqueness, wide ranges of PERSONALITY axis, and also
-- circumstance locally like the weather today, time of day, what theyre doing now").
--
-- VOICE. Derived once per person, deterministically, from their five FTB2 personality axes (`paddock.attributes`:
-- drive, temperament, authority, valor, warmth, each -1..1), their role, tier and age, plus seeded noise:
--   reg     register: street | plain | tech | corp -- whose vocabulary they reach for
--   warm    warmth: warm | cold | (neutral)
--   temper  edgy | calm | (neutral)
--   conf    cocky | humble | (neutral)
--   talk    terse | chatty | (normal) -- how many moves a conversation gets
--   humor   joker | dry | (none)
--   addr    what they call you ("choom", "driver", "kid", nothing ...)
--   tic     a verbal habit that opens some of their lines ("Look,", "Hm.", "Anyway.")
--   good / bad / swear   their own words, filled into `{good}` `{bad}` `{swear}` slots in shared lines
-- A shared template therefore comes out differently in each mouth, and tagged templates are sayable only by the
-- voices they fit.
--
-- A CONVERSATION is moves, each drawn from `life.voice_bank`: a greeting (first meeting / again / regular), then
-- circumstance -- what they are doing, the weather, the hour, their district's climate reading -- then a Paddock
-- topic, then maybe a closer. Talkativeness decides how many.
--
-- THE TRUTH RULE (as `paddock.news` and `paddock.talk`): a line is eligible only if every `{slot}` resolves from the
-- facts passed in. Facts are public: names, team, series, next race, last result, earned tag labels, where they are,
-- the weather, the hour, the district reading. Never a stat, a need or a personality value.
--
-- Deterministic: the same person, day and meeting count give the same words; a new meeting gives new ones.
local Core = NcmCore

Core.define("life.voice", function(C)
    local M = { version = "0.1.0" }
    local Hash = C.get("vocabulary.hash")
    local Bank = C.get("life.voice_bank")

    -- ------------------------------------------------------------------------------------------------- the voice

    local ADDR = {
        street = { "choom", "choom", "gato", "chica", "hermano", "bud", "kid", "", "", "" },
        plain = { "friend", "pal", "buddy", "", "", "", "mate" },
        tech = { "", "", "", "driver", "friend" },
        corp = { "", "", "", "driver" },
    }
    local TIC = {
        street = { "Look,", "Listen,", "Hey,", "Ayy,", "Nah, listen,", "Straight up,", "Real talk,", "Heh.", "Ha." },
        plain = { "Honestly,", "Well,", "Look,", "So,", "Anyway,", "Hm.", "Right.", "You know,", "I mean," },
        tech = { "Right.", "Okay.", "Hm.", "So.", "Technically,", "Look,", "Point is," },
        corp = { "Frankly,", "To be clear,", "Candidly,", "Well.", "Right.", "Let's be honest," },
    }
    local GOOD = {
        street = { "preem", "nova", "delta", "clean", "sick", "wiz" },
        plain = { "good", "solid", "decent", "not bad", "fine" },
        tech = { "clean", "tidy", "within spec", "sweet", "dialled" },
        corp = { "promising", "encouraging", "on target", "acceptable", "strong" },
    }
    local BAD = {
        street = { "gonk", "zeroed", "scuffed", "flatlined", "busted" },
        plain = { "rough", "ugly", "a mess", "bad", "grim" },
        tech = { "out of spec", "a mess", "cooked", "wrong", "all over the place" },
        corp = { "disappointing", "suboptimal", "below plan", "concerning", "regrettable" },
    }
    local SWEAR = {
        street = { "fuck", "choom", "hell", "frack", "gonk" },
        plain = { "hell", "damn", "Christ", "god" },
        tech = { "hell", "damn", "bloody hell" },
        corp = { "heavens", "goodness", "hell" },
    }

    local function pick(list, ...) return Hash.pick(list, ...) end

    --- A person's voice. `tier` is their org's; `year` the Paddock's current year (for age); both optional.
    function M.voiceOf(seed, person, tier, year)
        local pers = person.personality or {}
        local r = Hash.stream(seed, "voice", person.id)
        local function axis(k) return (pers[k] or 0) + (r() - 0.5) * 0.3 end
        local warmth, temperament, authority, valor, drive =
            axis("warmth"), axis("temperament"), axis("authority"), axis("valor"), axis("drive")
        local role = person.role
        local reg
        if tier == "street" then reg = "street"
        elseif (tier == "premier" or tier == "pro") and (role == "owner" or role == "manager") then reg = "corp"
        elseif role == "engineer" or role == "strategist" then reg = "tech"
        else reg = "plain" end
        local cross = r()
        if cross < 0.12 then reg = ({ street = "plain", plain = "street", tech = "plain", corp = "plain" })[reg]
        elseif cross < 0.18 then reg = ({ street = "tech", plain = "tech", tech = "street", corp = "tech" })[reg] end
        local age = (year and person.birthYear) and (year - person.birthYear) or 35
        local v = {
            reg = reg,
            warm = warmth > 0.3 and "warm" or (warmth < -0.3 and "cold" or nil),
            temper = temperament > 0.35 and "edgy" or (temperament < -0.35 and "calm" or nil),
            conf = ((authority + valor) / 2 > 0.3) and "cocky" or (((authority + valor) / 2 < -0.3) and "humble" or nil),
            talk = (warmth * 0.6 + drive * 0.4 + (r() - 0.5) * 0.4 > 0.3) and "chatty"
                or ((warmth * 0.6 + drive * 0.4 + (r() - 0.5) * 0.4 < -0.3) and "terse" or nil),
            young = age < 27, old = age > 52,
        }
        local hr = r()
        if temperament > 0.1 and warmth > 0 and hr < 0.55 then v.humor = "joker"
        elseif warmth < 0.2 and hr < 0.5 then v.humor = "dry" end
        v.addr = pick(ADDR[reg], seed, "addr", person.id)
        v.tic = (r() < 0.65) and pick(TIC[reg], seed, "tic", person.id) or nil
        v.good = pick(GOOD[reg], seed, "good", person.id)
        v.bad = pick(BAD[reg], seed, "bad", person.id)
        v.swear = (temperament > -0.2 or reg == "street") and pick(SWEAR[reg], seed, "swear", person.id) or nil
        v.tags = { [reg] = true }
        for _, k in ipairs({ "warm", "temper", "conf", "talk", "humor" }) do
            if v[k] then v.tags[v[k]] = true end
        end
        if v.young then v.tags.young = true end
        if v.old then v.tags.old = true end
        v.tags[role or "?"] = true
        return v
    end

    -- ------------------------------------------------------------------------------------------------- circumstance

    function M.hourBand(hour)
        hour = tonumber(hour) or 12
        if hour < 5 then return "late" end
        if hour < 7 then return "dawn" end
        if hour < 11 then return "morning" end
        if hour < 14 then return "midday" end
        if hour < 18 then return "afternoon" end
        if hour < 21 then return "evening" end
        return "night"
    end

    local WEATHER = { sunny = "clear", lightclouds = "clear", cloudy = "grey", heavyclouds = "grey", rain = "rain",
        fog = "fog", pollution = "smog", sandstorm = "sand" }
    function M.weatherBand(w) return WEATHER[w or ""] end

    -- ------------------------------------------------------------------------------------------------- composing

    local function fill(text, facts, v)
        local missing = false
        local s = text:gsub("{(%w+)}", function(k)
            local val
            if k == "addr" then val = v.addr
            elseif k == "good" then val = v.good
            elseif k == "bad" then val = v.bad
            elseif k == "swear" then val = v.swear
            else val = facts[k] end
            if val == nil or val == "" then missing = true return "" end
            return tostring(val)
        end)
        if missing then return nil end
        return s
    end

    -- A line fits a voice when every tag it carries is one the voice has (registers are alternatives: a line tagged
    -- `street plain` is sayable by either). More matching tags = more specific = preferred.
    local REGS = { street = true, plain = true, tech = true, corp = true }
    local function fits(entry, v)
        local regOk, hasReg, score = false, false, 0
        for tag in pairs(entry.tags) do
            if REGS[tag] then
                hasReg = true
                if v.tags[tag] then regOk = true end
            elseif tag == "first" or tag == "again" then
                -- handled by the move
            elseif not v.tags[tag] then
                return nil
            else
                score = score + 1
            end
        end
        if hasReg and not regOk then return nil end
        return score + (hasReg and 1 or 0)
    end

    --- One line for a move, or nil. `used` keeps a conversation from repeating a template.
    function M.line(move, facts, v, key, used)
        local list = Bank.move(move)
        if not list then return nil end
        local best, bestScore = {}, -1
        for _, e in ipairs(list) do
            if not (used and used[e.id]) then
                local s = fits(e, v)
                if s then
                    local text = fill(e.text, facts, v)
                    if text then
                        -- the most specific lines this voice can say, plus everything one step less specific:
                        -- specific enough to sound like them, wide enough never to repeat on a second visit
                        if s > bestScore + 1 then best, bestScore = {}, s end
                        if s >= bestScore - 1 then
                            best[#best + 1] = { id = e.id, text = text, s = s }
                            if s > bestScore then bestScore = s end
                        end
                    end
                end
            end
        end
        local keep = {}
        for _, b in ipairs(best) do if b.s >= bestScore - 1 then keep[#keep + 1] = b end end
        if #keep == 0 then return nil end
        local chosen = keep[1 + Hash.fnv1a32(Hash.key("line", move, key)) % #keep]
        if used then used[chosen.id] = true end
        return chosen
    end

    local ACT_MOVE = { eat = "act_eat", loiter = "act_loiter", fuel = "act_fuel", hang = "act_hang",
        errand = "act_errand", hustle = "act_hustle", work = "act_work" }

    --- What a person says when a player walks up. ctx = {
    ---   seed, person, tier, year, metCount, dayIndex,
    ---   facts    = public Paddock facts (`paddock.talk.facts` shape: name, role, org, series, route, when,
    ---              lastRoute, lastPlace, lastDriver, lastResult = win|podium|finish|dnf, tagLabel, ...)
    ---   activity = eat|loiter|fuel|hang|errand|hustle|work, place = "Fuel Station 19" / "the Glen food stall",
    ---   district, regime (life.climate regime id), crisis (bool), weather (platform id), hour (Eastern 0-23),
    ---   fame     = the player's Spotlight score (paddock.spotlight), playerName = their driver name }
    --- Owner, 2026-09-30: "they shouldnt just refer to me automatically, only if they know me aka (fame meter)".
    --- A stranger to an unknown player talks to a stranger. Lines tagged `known` need a previous meeting; `heard`
    --- needs Spotlight >= MENTION (WIRE names you); `famous` needs >= CALLOUT. `{player}` only resolves for someone
    --- who has met you or heard of you.
    --- Returns { text, moves = { move ids }, lines = { line ids }, voice }.
    M.HEARD, M.FAMOUS = 10, 25           -- paddock.spotlight MENTION and CALLOUT

    function M.say(ctx)
        local p = ctx.person
        local base = M.voiceOf(ctx.seed, p, ctx.tier, ctx.year)
        -- this conversation's tags: the voice's own, plus what this person knows about the player
        local tags = {}
        for k in pairs(base.tags) do tags[k] = true end
        local fame = tonumber(ctx.fame) or 0
        local known = (ctx.metCount or 0) > 0
        if known then tags.known = true end
        if fame >= M.HEARD then tags.heard = true end
        if fame >= M.FAMOUS then tags.famous = true end
        local v = setmetatable({ tags = tags }, { __index = base })
        local facts = {}
        for k, val in pairs(ctx.facts or {}) do facts[k] = val end
        facts.place, facts.district = ctx.place, ctx.district
        if (known or tags.heard) and ctx.playerName and ctx.playerName ~= "" then facts.player = ctx.playerName end
        local key = Hash.key(ctx.seed, p.id, ctx.dayIndex or 0, ctx.metCount or 0)
        local met = ctx.metCount or 0
        local r = Hash.stream("say", key)

        -- the plan of moves
        local moves = {}
        moves[#moves + 1] = met == 0 and "greet_first" or (met < 3 and "greet_again" or "greet_regular")
        local circ = {}
        if ctx.activity and ACT_MOVE[ctx.activity] then circ[#circ + 1] = ACT_MOVE[ctx.activity] end
        local wb = M.weatherBand(ctx.weather)
        if wb then circ[#circ + 1] = "weather_" .. wb end
        if ctx.hour then circ[#circ + 1] = "time_" .. M.hourBand(ctx.hour) end
        if ctx.regime then
            local crisisMove = "district_" .. ctx.regime .. "_crisis"
            circ[#circ + 1] = (ctx.crisis and Bank.move(crisisMove)) and crisisMove or ("district_" .. ctx.regime)
        end
        local topics = {}
        if facts.route and facts.when then topics[#topics + 1] = "topic_next" end
        if facts.lastResult then topics[#topics + 1] = "topic_last_" .. facts.lastResult end
        if facts.tagLabel then topics[#topics + 1] = "topic_tag" end
        topics[#topics + 1] = "topic_role_" .. (p.role or "driver")
        if facts.series then topics[#topics + 1] = "topic_series" end

        -- What they are doing now is the most salient thing about the moment, so it leads when there is one; the
        -- weather and the district compete for the next slot; the hour is the least interesting and comes last.
        local act = (ctx.activity and ACT_MOVE[ctx.activity]) and table.remove(circ, 1) or nil
        local timeMove
        for i = #circ, 1, -1 do if circ[i]:match("^time_") then timeMove = table.remove(circ, i) end end
        for i = #circ, 2, -1 do local j = r:int(1, i); circ[i], circ[j] = circ[j], circ[i] end
        if act then table.insert(circ, 1, act) end
        if timeMove then circ[#circ + 1] = timeMove end
        for i = #topics, 2, -1 do local j = r:int(1, i); topics[i], topics[j] = topics[j], topics[i] end

        -- How much gets said is drawn fresh each conversation within a range the voice sets. Owner, 2026-09-30:
        -- "responses can be long ... we want variance and real persona dont optimize too hard".
        local nCirc, nTopic, closeP = r:int(1, 2), (r() < 0.3) and 2 or 1, 0.25
        if v.talk == "terse" then nCirc, nTopic, closeP = (r() < 0.5) and 1 or 0, 1, 0.05 end
        if v.talk == "chatty" then nCirc, nTopic, closeP = r:int(2, 3), (r() < 0.6) and 2 or 1, 0.5 end
        -- a terse person skips the greeting half the time and just says the one thing
        if v.talk == "terse" and r() < 0.5 then moves = {} end
        for i = 1, math.min(nCirc, #circ) do moves[#moves + 1] = circ[i] end
        for i = 1, math.min(nTopic, #topics) do moves[#moves + 1] = topics[i] end
        if r() < closeP then moves[#moves + 1] = "close" end

        local used, parts, ids, took = {}, {}, {}, {}
        for i, mv in ipairs(moves) do
            local l = M.line(mv, facts, v, key .. "|" .. i, used)
            if l then
                parts[#parts + 1] = l.text
                ids[#ids + 1] = l.id
                took[#took + 1] = mv
            end
        end
        -- one mention of the hour per conversation: a greeting that already said "Evening" drops the time line
        local HOURWORD = { "Morning", "Evening", "Afternoon", "Night", "night", "morning", "evening", "afternoon", "Late", "late" }
        local sawHour = false
        local kept, keptIds, keptMoves = {}, {}, {}
        for i, text in ipairs(parts) do
            local hasHour = false
            for _, w in ipairs(HOURWORD) do if text:find("%f[%a]" .. w .. "%f[%A]") then hasHour = true break end end
            if not (hasHour and sawHour and took[i]:match("^time_")) then
                kept[#kept + 1], keptIds[#keptIds + 1], keptMoves[#keptMoves + 1] = text, ids[i], took[i]
            end
            if hasHour then sawHour = true end
        end
        parts, ids, took = kept, keptIds, keptMoves
        if #parts == 0 then parts[1] = (facts.name and facts.org) and (facts.name .. ". " .. facts.org .. ".") or "..." end
        -- the tic opens the whole thing, sometimes
        local text = table.concat(parts, " ")
        -- A comma tic runs into the sentence ("Look, you need something?"); only an ordinary opening word is
        -- lower-cased, never a name ("Look, Ignacio Escobar here").
        local COMMON = { ["You"] = 1, ["We"] = 1, ["The"] = 1, ["It"] = 1, ["It's"] = 1, ["This"] = 1, ["That"] = 1,
            ["Just"] = 1, ["If"] = 1, ["There"] = 1, ["They"] = 1, ["Nothing"] = 1, ["Everyone"] = 1, ["Car"] = 1,
            ["Rain"] = 1, ["Don't"] = 1, ["Another"] = 1, ["All"] = 1, ["Half"] = 1, ["My"] = 1, ["Our"] = 1, ["Your"] = 1 }
        if v.tic and r() < 0.4 and not text:find("^" .. v.tic:gsub("%p", "%%%0")) then
            if v.tic:sub(-1) == "," then
                -- a comma tic only runs into an ordinary opening word ("Look, you need something?"); before a
                -- name or an interjection ("Listen, Sup.") it would read as a glitch, so it is left off
                local first = text:match("^(%S+)")
                if first and COMMON[first] then text = v.tic .. " " .. text:sub(1, 1):lower() .. text:sub(2) end
            else
                text = v.tic .. " " .. text
            end
        end
        return { text = text, moves = took, lines = ids, voice = base }
    end

    return M
end)
