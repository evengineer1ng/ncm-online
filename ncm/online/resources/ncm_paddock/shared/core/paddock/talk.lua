-- ncm-core module: paddock.talk
-- What a Paddock person says when a player walks up to them at their garage (doc 44 §11, phase 4).
--
-- The same truth rule as WIRE (`paddock.news`): a line is eligible only when every `{slot}` it names resolves from
-- the facts the host passes in, so a mechanic cannot mention a race, a result or a tag the world does not hold.
-- Facts are PUBLIC facts only: names, the org, the next race, the last result, earned tag labels. Never a stat,
-- a trait or a morale value (`paddock.projection` rules). The pick is keyed by person, Eastern day and how many
-- times this player has met them, so a repeat visit gets a different line and a replay gets the same one.
--
-- This is the phase-4 voice until native dialogue (IDEA-727) passes: one line, spoken through a notification.
local Core = NcmCore

Core.define("paddock.talk", function(C)
    local M = { version = "0.1.0" }
    local Hash = C.get("vocabulary.hash")

    M.ROLE_LABEL = { manager = "team manager", engineer = "race engineer", strategist = "strategist",
        driver = "driver", owner = "owner" }

    -- { id, t = text, first = only on a first meeting, roles = { role = true } or nil for any }
    M.LINES = {
        { id = "in1", first = true, t = "{name}. I run things for {org} around here. You're the one who keeps turning up at the lights." },
        { id = "in2", first = true, t = "You lost? This bay's {org}'s until the shift ends. {name}, {role}." },
        { id = "in3", first = true, roles = { driver = true }, t = "{name}. I drive for {org}. If you're here to talk about the {series}, talk fast." },
        { id = "in4", first = true, roles = { engineer = true, strategist = true }, t = "{name}, {role} with {org}. Mind the jack stands." },
        { id = "nx1", t = "We're on {route} at {when}. {series}. Come watch, or don't." },
        { id = "nx2", roles = { driver = true }, t = "{when} tonight, {route}. I've been over it in my head a hundred times." },
        { id = "nx3", roles = { engineer = true }, t = "Setup for {route} is half done and {when} isn't getting any later." },
        { id = "nx4", roles = { manager = true, strategist = true }, t = "{route}, {when}. {weatherNote}" },
        { id = "ls1", t = "Last time out, {lastDriver} brought it home {lastPlace} on {lastRoute}. {lastVerdict}" },
        { id = "ls2", roles = { driver = true }, t = "{lastPlace} on {lastRoute}. {lastVerdict}" },
        { id = "ls3", roles = { engineer = true }, t = "Car came back from {lastRoute} {lastCarNote}. {lastPlace}, for what it's worth." },
        { id = "tg1", t = "People call {tagSubject} {tagLabel}. They're not wrong." },
        { id = "tg2", roles = { driver = true }, t = "They've started calling me {tagLabel}. I'll take it." },
        { id = "gn1", t = "Rent's due, sponsors want stickers, and the {series} doesn't wait. Same as ever." },
        { id = "gn2", t = "You want a job, go see the Autofixer. You want a race, check the board." },
        { id = "gn3", roles = { engineer = true }, t = "Everything in this garage is borrowed, including the time." },
        { id = "gn4", roles = { manager = true }, t = "Billie's got us on the board. I try not to look." },
    }

    local function fill(t, facts)
        local missing = false
        local s = t:gsub("{(%w+)}", function(k)
            local v = facts[k]
            if v == nil or v == "" then missing = true return "" end
            return tostring(v)
        end)
        if missing then return nil end
        return s
    end

    local function ordinal(n)
        n = tonumber(n)
        if not n then return nil end
        local s = ({ "1st", "2nd", "3rd" })[n]
        return s or (tostring(n) .. "th")
    end
    M.ordinal = ordinal

    --- Public facts from what the host knows. ctx = { person, org, seriesName, next = { route, when, weather },
    --- last = { driver, position, state, route }, tags = { label... }, tagSubject }.
    function M.facts(ctx)
        local p, org = ctx.person or {}, ctx.org or {}
        local f = { name = p.display, role = M.ROLE_LABEL[p.role] or p.role, org = org.name, series = ctx.seriesName }
        if ctx.next then
            f.route, f.when = ctx.next.route, ctx.next.when
            local w = ctx.next.weather
            f.weatherNote = (w == "rain" or w == "heavy_rain" or w == "storm") and "If it rains, it rains on everyone."
                or ((w and w ~= "") and "Forecast says it holds." or nil)
        end
        if ctx.last then
            f.lastRoute, f.lastDriver = ctx.last.route, ctx.last.driver
            if ctx.last.state == "finished" then
                f.lastPlace = ordinal(ctx.last.position)
                f.lastResult = (ctx.last.position == 1 and "win") or ((ctx.last.position or 99) <= 3 and "podium") or "finish"
                f.lastVerdict = (ctx.last.position == 1 and "Drinks were on us.")
                    or ((ctx.last.position or 99) <= 3 and "A podium's a podium.")
                    or "We'll take the points and the lesson."
                f.lastCarNote = (ctx.last.position or 99) <= 3 and "in one piece" or "with a list"
            else
                f.lastPlace = "out early"
                f.lastResult = "dnf"
                f.lastVerdict = "We don't talk about it."
                f.lastCarNote = "in a bag"
            end
        end
        if ctx.tags and ctx.tags[1] then f.tagLabel = ctx.tags[1]; f.tagSubject = ctx.tagSubject end
        return f
    end

    --- One line: { id, text }. `metCount` is how many times this player met this person BEFORE now.
    function M.line(ctx, dayIndex, metCount)
        local p = ctx.person or {}
        local facts = M.facts(ctx)
        local first = (metCount or 0) == 0
        local eligible = {}
        for _, l in ipairs(M.LINES) do
            if (l.first == true) == first and (not l.roles or l.roles[p.role]) then
                local text = fill(l.t, facts)
                if text then eligible[#eligible + 1] = { id = l.id, text = text } end
            end
        end
        if #eligible == 0 then
            return { id = "fallback", text = (facts.name and facts.org) and (facts.name .. ". " .. facts.org .. ".") or "..." }
        end
        return Hash.pick(eligible, "talk", p.id, dayIndex or 0, metCount or 0)
    end

    return M
end)
