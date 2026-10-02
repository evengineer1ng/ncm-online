-- life.voice and its bank (owner, 2026-09-30): unique voices from personality, circumstance-aware lines, nobody
-- who does not know the player talks as if they do, and "the board" is Billie's word, not everyone's. These test
-- CORRECTNESS, not taste: the owner reviews every line before it ships.
local SEED = 4242
local worldCache
local function world(T)
    if not worldCache then worldCache = T.Core.get("paddock.world").genesis(SEED, "2026-S4") end
    return worldCache
end

local KNOWN_TAGS = {
    street = 1, plain = 1, tech = 1, corp = 1, warm = 1, cold = 1, edgy = 1, calm = 1, cocky = 1, humble = 1,
    chatty = 1, terse = 1, joker = 1, dry = 1, young = 1, old = 1, driver = 1, engineer = 1, strategist = 1,
    manager = 1, owner = 1, known = 1, heard = 1, famous = 1,
}
local KNOWN_SLOTS = {
    name = 1, role = 1, org = 1, series = 1, route = 1, when = 1, lastRoute = 1, lastPlace = 1, lastDriver = 1,
    tagLabel = 1, tagSubject = 1, place = 1, district = 1, player = 1, addr = 1, good = 1, bad = 1, swear = 1,
}

local function people(T, n)
    local w = world(T)
    local out = {}
    for _, id in ipairs(w.personOrder) do
        local p = w.people[id]
        local o = p.orgId and w.orgs[p.orgId]
        if o and p.state == "active" then out[#out + 1] = { p = p, o = o } end
        if #out >= n then break end
    end
    return out
end

local function ctxFor(x, extra)
    local ctx = {
        seed = SEED, person = x.p, tier = x.o.tier, year = 2077, metCount = 0, dayIndex = 3,
        facts = { name = x.p.display, role = x.p.role, org = x.o.name, series = "Heywood Street League",
            route = "Hanford Overpass", when = "21:40", lastRoute = "Vista Del Drag", lastPlace = "4th",
            lastResult = "finish", lastDriver = "Mika Sato" },
        activity = "fuel", place = "Fuel Station 19", district = "Heywood", regime = "scene_town", weather = "rain",
        hour = 20, fame = 0, playerName = "Easporks",
    }
    for k, v in pairs(extra or {}) do ctx[k] = v end
    return ctx
end

return {
    bank_lines_use_only_known_tags_and_slots = function(T)
        local Bank = T.Core.get("life.voice_bank")
        local all = Bank.all()
        T.ok(#all >= 900, "the bank is large: " .. #all)
        local seen = {}
        for _, e in ipairs(all) do
            T.falsy(seen[e.id], "unique id " .. e.id); seen[e.id] = true
            for tag in pairs(e.tags) do T.ok(KNOWN_TAGS[tag], "known tag '" .. tag .. "' in " .. e.id) end
            for slot in e.text:gmatch("{(%w+)}") do T.ok(KNOWN_SLOTS[slot], "known slot {" .. slot .. "} in " .. e.id) end
            T.falsy(e.text:find("^%s*$"), "no empty line " .. e.id)
        end
    end,

    the_board_is_billies_word_not_everyones = function(T)
        local Bank = T.Core.get("life.voice_bank")
        local n = 0
        for _, e in ipairs(Bank.all()) do if e.text:lower():find("%f[%a]board%f[%A]") then n = n + 1 end end
        T.ok(n <= 2, "Paddock people mention 'the board' in at most two lines: " .. n)
    end,

    every_register_can_speak_every_core_move = function(T)
        local Bank = T.Core.get("life.voice_bank")
        local core = { "greet_first", "greet_again", "close", "act_eat", "act_loiter", "act_fuel", "act_work",
            "weather_clear", "weather_rain", "topic_next", "topic_last_finish", "topic_last_dnf", "topic_series" }
        for _, mv in ipairs(core) do
            for _, reg in ipairs({ "street", "plain", "tech", "corp" }) do
                local n = 0
                for _, e in ipairs(Bank.move(mv)) do
                    local hasReg = e.tags.street or e.tags.plain or e.tags.tech or e.tags.corp
                    if (not hasReg or e.tags[reg]) and not (e.tags.known or e.tags.heard or e.tags.famous) then n = n + 1 end
                end
                T.ok(n >= 3, ("%s has at least three lines a %s voice can say: %d"):format(mv, reg, n))
            end
        end
    end,

    voices_come_from_personality_and_are_deterministic = function(T)
        local Voice = T.Core.get("life.voice")
        local regs, warms, talks = {}, {}, {}
        for _, x in ipairs(people(T, 120)) do
            local a = Voice.voiceOf(SEED, x.p, x.o.tier, 2077)
            local b = Voice.voiceOf(SEED, x.p, x.o.tier, 2077)
            T.eq(a.reg, b.reg); T.eq(a.tic, b.tic); T.eq(a.addr, b.addr)
            regs[a.reg] = true; warms[tostring(a.warm)] = true; talks[tostring(a.talk)] = true
        end
        local n = 0 for _ in pairs(regs) do n = n + 1 end
        T.ok(n >= 3, "a cast speaks in at least three registers")
        T.ok(warms.warm and warms.cold and warms["nil"], "warm, cold and neutral people all exist")
        T.ok(talks.chatty and talks.terse and talks["nil"], "chatty, terse and ordinary talkers all exist")
    end,

    the_same_moment_sounds_different_in_different_mouths = function(T)
        local Voice = T.Core.get("life.voice")
        local texts, dup = {}, 0
        local cast = people(T, 60)
        for _, x in ipairs(cast) do
            local out = Voice.say(ctxFor(x))
            T.ok(#out.text > 0, "everyone says something")
            if texts[out.text] then dup = dup + 1 end
            texts[out.text] = true
        end
        T.ok(dup <= 2, "sixty people at one fuel stop in the rain say sixty different things: " .. dup .. " repeats")
        local a = Voice.say(ctxFor(cast[1]))
        local b = Voice.say(ctxFor(cast[1]))
        T.eq(a.text, b.text, "the same person, day and meeting say the same thing (replay)")
        local c = Voice.say(ctxFor(cast[1], { metCount = 1 }))
        T.neq(a.text, c.text, "a second meeting says something new")
    end,

    circumstance_reaches_the_words = function(T)
        local Voice = T.Core.get("life.voice")
        local cast = people(T, 40)
        local fuelSaid, rainSaid = 0, 0
        for _, x in ipairs(cast) do
            local out = Voice.say(ctxFor(x))
            for _, mv in ipairs(out.moves) do
                if mv == "act_fuel" then fuelSaid = fuelSaid + 1 end
                if mv == "weather_rain" then rainSaid = rainSaid + 1 end
            end
        end
        T.ok(fuelSaid >= 25, "most people at a fuel stop mention what they are doing: " .. fuelSaid .. "/40")
        T.ok(rainSaid >= 5, "some mention the rain: " .. rainSaid .. "/40")
    end,

    strangers_do_not_talk_as_if_they_know_you = function(T)
        local Voice = T.Core.get("life.voice")
        local cast = people(T, 80)
        for _, x in ipairs(cast) do
            for day = 1, 3 do
                local out = Voice.say(ctxFor(x, { dayIndex = day }))
                T.falsy(out.text:find("Easporks", 1, true), "an unknown player is never named by a stranger")
                for _, id in ipairs(out.lines) do
                    T.falsy(id:match("^greet_regular"), "a first meeting is never a regular's greeting")
                end
            end
        end
        local named = 0
        for _, x in ipairs(cast) do
            local out = Voice.say(ctxFor(x, { fame = 40 }))
            if out.text:find("Easporks", 1, true) then named = named + 1 end
        end
        T.ok(named >= 3, "a famous player is recognised by some strangers: " .. named)
        local metNamed = 0
        for _, x in ipairs(cast) do
            local out = Voice.say(ctxFor(x, { metCount = 4 }))
            if out.text:find("Easporks", 1, true) then metNamed = metNamed + 1 end
        end
        T.ok(metNamed >= 3, "people who have met you sometimes use your name: " .. metNamed)
    end,

    the_truth_rule_holds = function(T)
        local Voice = T.Core.get("life.voice")
        for _, x in ipairs(people(T, 40)) do
            local ctx = ctxFor(x)
            ctx.facts.route, ctx.facts.when, ctx.facts.lastRoute, ctx.facts.lastPlace, ctx.facts.lastResult = nil, nil, nil, nil, nil
            local out = Voice.say(ctx)
            T.falsy(out.text:find("{", 1, true), "no unfilled slot")
            T.falsy(out.text:find("Hanford", 1, true), "no race is invented when there is none")
        end
    end,
}
