-- ncm-core module: week.vibe
-- Vibe is a simulation OUTPUT (doc 47 §1.7, L310): Day 1/2/3 moods are the trajectory history expects, not skins. How the
-- city sounds is composed from the state -- how much it tolerates racing now, WHY (the reservoir that is moving it, or
-- money holding it together), whether the run is off history's map (past hour 72), and what Moody has on -- so an
-- ordinary Day 3 sounds like disgust, an exceptional one sounds like a city still having a great time, and a Day 4
-- kept alive by money sounds nothing like one kept alive by clean racing.
--
-- It is a PROXY, never a meter: `classify` is server-side; only composed lines go out (the racing radio, every two run
-- hours). No line names a number, a probability or a reservoir. Lines are picked deterministically per (seed, run,
-- hour) so a restart does not repeat or skip one. v1 is the radio; crowds, signs, PA tone and dressing read the same
-- `classify` when they are built (doc 47 §6).
local Core = NcmCore

Core.define("week.vibe", function(C)
    local M = { version = "0.1.0" }
    local Hash = C.get("vocabulary.hash")

    -- the city's mood from its tolerance of racing, absolute (what you would hear on the street)
    M.MOODS = {
        { id = "euphoric", min = 0.75 },
        { id = "buoyant", min = 0.55 },
        { id = "uneasy", min = 0.38 },
        { id = "tense", min = 0.20 },
        { id = "hostile", min = -1 },
    }

    --- { mood, cause, surprise, offMap, money } from a week.curve read, Moody's effects and the run hour.
    ---   cause    safety_bad | safety_good | enforcement | momentum_up | momentum_down | money | none
    ---   surprise how far the city stands from what history expected: "better" | "worse" | nil
    function M.classify(read, fx, hours)
        local tol = tonumber(read and read.tolerance) or 0.5
        local mood = "hostile"
        for _, m in ipairs(M.MOODS) do if tol >= m.min then mood = m.id break end end
        local res = (read and read.reservoirs) or {}
        local best, bestAbs = "none", 0.02
        local cand = {
            { tonumber(res.safety) or 0, "safety_bad", "safety_good" },
            { tonumber(res.enforcement) or 0, "enforcement", "enforcement" },
            { tonumber(res.momentum) or 0, "momentum_down", "momentum_up" },
        }
        for _, c in ipairs(cand) do
            if math.abs(c[1]) > bestAbs then bestAbs = math.abs(c[1]); best = (c[1] < 0) and c[2] or c[3] end
        end
        local purse = 1
        for _, x in pairs((fx and fx.purse) or {}) do purse = math.max(purse, tonumber(x) or 1) end
        local money = purse >= 1.4 or (tonumber(read and read.money) or 1) >= 1.5
        if money and (best == "none" or mood == "tense" or mood == "hostile") then best = "money" end
        local dev = tonumber(read and read.deviation) or 0
        local surprise = (dev > 0.08) and "better" or ((dev < -0.08) and "worse" or nil)
        return { mood = mood, cause = best, surprise = surprise, offMap = (tonumber(hours) or 0) >= 72, money = money }
    end

    M.LINES = {
        euphoric = {
            "Racing Week, and the whole city is out on the curb for it. Nobody wants to go home.",
            "Crowds three deep on every corner tonight. This is the festival they promised.",
            "You can hear it from Watson to the Badlands: Night City loves this.",
        },
        buoyant = {
            "Good racing, good crowds. Racing Week is holding its own.",
            "The city is still on side. Mostly. Keep it that way, drivers.",
            "Grids are full and the bars are fuller. Racing Week rolls on.",
        },
        uneasy = {
            "The welcome is wearing thin in a few districts. People are starting to ask questions.",
            "Racing Week is still on, but the mood on the street has changed.",
            "Mixed reviews tonight. Half the city cheering, half the city calling the council.",
        },
        tense = {
            "Night City is losing patience with Racing Week. You can feel it.",
            "Fewer cheers, more sirens. Racing Week is in trouble.",
            "Call-in lines are jammed and nobody is calling to say congratulations.",
        },
        hostile = {
            "The city has had enough. Racing Week is the most hated thing in Night City tonight.",
            "Torn banners, empty stands, angry streets. Get out while you can.",
            "Nobody is pretending any more. Night City wants Racing Week gone.",
        },
    }
    M.CAUSES = {
        safety_bad = { "Too many wrecks, too many close calls.", "Every crash is on the news.", "The trauma teams are busy." },
        safety_good = { "Somehow nobody has been hurt in hours.", "Clean racing, clean streets -- people noticed.", "Not a scratch on the crowd today." },
        enforcement = { "NCPD is everywhere and everyone is tired of it.", "Speed traps on every corner.", "Tickets are flying." },
        momentum_up = { "The calendar is packed and the city is buzzing.", "Race after race after race.", "There is always a race on somewhere." },
        momentum_down = { "Quiet streets. Too quiet, some say.", "The schedule has thinned out.", "Fewer races, fewer reasons to care." },
        money = { "The money is the only thing keeping it going.", "Purses this big buy a lot of patience.", "Follow the money: everyone else is." },
        none = { "", "", "" },
    }
    M.OFF_MAP = {
        "Nobody has seen a Racing Week go this long. Nobody knows how it ends.",
        "Day by day, the city is writing something new.",
        "This was supposed to be over. It isn't.",
    }
    M.SURPRISE = {
        better = { "Better than anyone expected.", "Against all odds.", "Nobody predicted this." },
        worse = { "Worse than anyone feared.", "It was never supposed to get this bad.", "Even the cynics are surprised." },
    }

    local function pick(list, seed, ...)
        if not list or #list == 0 then return "" end
        return list[1 + Hash.fnv1a32(Hash.key(seed, ...)) % #list]
    end

    --- The radio line for (seed, run, hour), composed from a classification. Never names a number.
    function M.line(seed, run, hour, v)
        local parts = {}
        if v.offMap then parts[#parts + 1] = pick(M.OFF_MAP, seed, "offmap", run, hour) end
        parts[#parts + 1] = pick(M.LINES[v.mood], seed, "mood", run, hour)
        local cause = pick(M.CAUSES[v.cause], seed, "cause", run, hour)
        if cause ~= "" then parts[#parts + 1] = cause end
        if v.surprise and (hour or 0) >= 24 then parts[#parts + 1] = pick(M.SURPRISE[v.surprise], seed, "surprise", run, hour) end
        return table.concat(parts, " ")
    end

    return M
end)
