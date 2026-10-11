-- ncm-core module: week.moody
-- MOODY, the volatility engine (doc 47, L309-L310): every reconstruction starts from the same Day 1, and Moody keeps
-- each one from asking the same question under the same conditions.
--
-- THE SACRED RULE (doc 47 §1.2): Moody creates CONDITIONS, never outcomes. No face adds or subtracts collapse, touches
-- a reservoir or the continuation judgement. A face changes rules and incentives through systems that exist -- purses
-- (the Paddock's and the craze's), the race calendar's density, police posture, the posted limits -- and lures: how
-- strongly a purse pulls a driver to a race, which each driver weighs through their own character and circumstances
-- (paddock.attendance.lure, paddock.sim's risk). The simulation then does the damage, or does not.
--
-- THE ROLL. A D20, ceremonial and legible: every face is public, named and announced. Rolls come every `cadenceH`
-- (4 h) from hour 4; faces can change the cadence itself (RESTLESS: every 2 h for a while; STABLE WEATHER: the next roll
-- waits; DOUBLE TROUBLE: two more rolls now), so the volatility of a run is itself variable. Deterministic: the n-th
-- roll of run r is the same number from the same seed, so a restart replays nothing twice and an audit can re-derive
-- every face (rows: racing_week_moody, INSERT IGNORE on (run, n)).
--
-- Conditions not backed by any system yet (CROWD SURGE, SAFETY DRIVE's barriers) are not in v1: doc 45 §G's rule, "no
-- fake simulation". They join the table when crowds and barriers exist.
local Core = NcmCore

Core.define("week.moody", function(C)
    local M = { version = "0.1.0", SIDES = 20, FIRST_ROLL_H = 4, CADENCE_H = 4, RESTLESS_H = 2, CHAIN_MAX = 3 }
    local Hash = C.get("vocabulary.hash")

    local ALL = { "street", "regional", "pro", "premier" }
    local function tiers(list, v) local t = {} for _, k in ipairs(list) do t[k] = v end return t end

    -- The faces. `kind`: condition | meta | remove | transform | extend | neutral. `hours`: how long a condition lasts.
    -- `fx`: purse (x per tier), calendar (slot spacing x per tier: < 1 = more races), lure (0..1 per tier: how hard a
    -- purse pulls the needy and the bold), limit (x), policeCap (+), perLevel (x the bar per wanted level).
    -- `opposite`: what TURN OF THE TIDE makes of it. `line`: what the broadcast says (public; never a probability).
    M.FACES = {
        { id = "still_air", name = "STILL AIR", kind = "neutral", line = "The dice say nothing. Racing Week rolls on." },
        { id = "business_as_usual", name = "BUSINESS AS USUAL", kind = "neutral", line = "No change. The schedule stands." },
        { id = "devils_purse", name = "DEVIL'S PURSE", kind = "condition", hours = 6,
            fx = { purse = { street = 2.5 }, lure = { street = 1.0 } },
            line = "Street purses go through the roof. Somebody is paying a lot of money for nights like this." },
        { id = "gold_rush", name = "GOLD RUSH", kind = "condition", hours = 4, opposite = "sponsor_pullout",
            fx = { purse = tiers(ALL, 1.4), lure = tiers(ALL, 0.5) },
            line = "Sponsors pile in. Every purse in the city just got fatter." },
        { id = "sponsor_pullout", name = "SPONSOR PULLOUT", kind = "condition", hours = 6, opposite = "gold_rush",
            fx = { purse = tiers(ALL, 0.7) },
            line = "Sponsors are getting cold feet. Purses shrink across the board." },
        { id = "packed_calendar", name = "PACKED CALENDAR", kind = "condition", hours = 4, opposite = "quiet_hours",
            fx = { calendar = tiers(ALL, 0.7) },
            line = "The organisers cram the calendar. More races, more often." },
        { id = "quiet_hours", name = "QUIET HOURS", kind = "condition", hours = 4, opposite = "packed_calendar",
            fx = { calendar = tiers(ALL, 1.6) },
            line = "The organisers thin the schedule. Fewer races for a while." },
        { id = "crackdown", name = "CRACKDOWN", kind = "condition", hours = 4, opposite = "blind_eye",
            fx = { policeCap = 1, perLevel = 0.75 },
            line = "NCPD steps up patrols around the race routes." },
        { id = "blind_eye", name = "BLIND EYE", kind = "condition", hours = 4, opposite = "crackdown",
            fx = { policeCap = -1, perLevel = 1.3 },
            line = "NCPD has other priorities tonight. Patrols thin out." },
        { id = "open_roads", name = "OPEN ROADS", kind = "condition", hours = 4, opposite = "slow_zones",
            fx = { limit = 1.2 },
            line = "The city raises the posted limits on the race routes." },
        { id = "slow_zones", name = "SLOW ZONES", kind = "condition", hours = 4, opposite = "open_roads",
            fx = { limit = 0.85 },
            line = "Slow zones go up across the city. Posted limits drop." },
        { id = "night_market", name = "NIGHT MARKET", kind = "condition", hours = 6,
            fx = { purse = { street = 1.5 }, calendar = { street = 0.75 }, lure = { street = 0.6 } },
            line = "The street scene booms: more street races, better money, hungrier drivers." },
        { id = "premier_showcase", name = "PREMIER SHOWCASE", kind = "condition", hours = 6,
            fx = { purse = { pro = 1.8, premier = 1.8 }, lure = { pro = 0.4, premier = 0.4 } },
            line = "The big teams put on a show. Pro and Premier purses soar." },
        { id = "headliner", name = "HEADLINER", kind = "condition", hours = 4,
            fx = { calendar = { pro = 0.8, premier = 0.8 }, purse = { pro = 1.3, premier = 1.3 } },
            line = "Prime time: extra Pro and Premier races are on the bill." },
        { id = "calm", name = "CALM", kind = "remove", line = "Something settles. The newest condition lifts early." },
        { id = "turn_of_the_tide", name = "TURN OF THE TIDE", kind = "transform",
            line = "The tide turns: the newest condition becomes its opposite." },
        { id = "restless", name = "RESTLESS", kind = "meta", hours = 8,
            line = "The week is restless. The dice will roll every two hours for a while." },
        { id = "stable_weather", name = "STABLE WEATHER", kind = "meta",
            line = "A steady spell. The next roll will wait." },
        { id = "double_trouble", name = "DOUBLE TROUBLE", kind = "meta", line = "Double trouble: the dice roll twice more, now." },
        { id = "long_haul", name = "LONG HAUL", kind = "extend", line = "Whatever is happening now keeps happening longer." },
    }
    assert(#M.FACES == M.SIDES, "week.moody: a D20 has twenty faces")
    local BY = {}
    for i, f in ipairs(M.FACES) do f.face = i; BY[f.id] = f end
    function M.face(id) return BY[id or ""] end

    function M.newState()
        return { n = 0, nextRollH = M.FIRST_ROLL_H, restlessUntilH = nil, active = {}, log = {} }
    end

    --- The n-th roll of a run, 1..20: the same number from the same seed, always.
    function M.d20(seed, run, n)
        return 1 + Hash.fnv1a32(Hash.key(seed, "moody", run, n)) % M.SIDES
    end

    local function cadence(st, hours)
        return (st.restlessUntilH and hours < st.restlessUntilH) and M.RESTLESS_H or M.CADENCE_H
    end

    --- Drop conditions whose time is up. Returns the ones that ended.
    function M.expire(st, hours)
        local keep, ended = {}, {}
        for _, a in ipairs(st.active) do
            if hours >= a.untilH then ended[#ended + 1] = a else keep[#keep + 1] = a end
        end
        st.active = keep
        return ended
    end

    local function newest(st)
        local best
        for _, a in ipairs(st.active) do if not best or a.fromH > best.fromH or (a.fromH == best.fromH and a.n > best.n) then best = a end end
        return best
    end

    -- Apply one face. Returns the roll record and how many extra rolls it asks for.
    local function apply(st, seed, run, hours)
        st.n = st.n + 1
        local n = st.n
        local d = M.d20(seed, run, n)
        local f = M.FACES[d]
        local rec = { n = n, d20 = d, id = f.id, name = f.name, kind = f.kind, hours = hours, line = f.line }
        local extra = 0
        if f.kind == "condition" then
            st.active[#st.active + 1] = { id = f.id, name = f.name, fromH = hours, untilH = hours + f.hours, n = n }
            rec.untilH = hours + f.hours
        elseif f.kind == "remove" then
            local a = newest(st)
            if a then
                a.untilH = hours
                rec.target = a.id
                M.expire(st, hours)
            end
        elseif f.kind == "transform" then
            local a = newest(st)
            local into = a and BY[a.id] and BY[BY[a.id].opposite or ""]
            if a and into then
                rec.target, rec.into = a.id, into.id
                a.id, a.name, a.n = into.id, into.name, n
            elseif a then
                rec.target = a.id         -- no opposite: the tide turns nothing
            end
        elseif f.kind == "extend" then
            for _, a in ipairs(st.active) do a.untilH = a.untilH + M.CADENCE_H end
            rec.extended = #st.active
        elseif f.id == "restless" then
            st.restlessUntilH = hours + f.hours
            rec.untilH = st.restlessUntilH
        elseif f.id == "stable_weather" then
            rec.delayH = M.CADENCE_H
            st.delayNext = (st.delayNext or 0) + M.CADENCE_H
        elseif f.id == "double_trouble" then
            extra = 2
        end
        return rec, extra
    end

    --- Roll every die that is due at `hours`. Returns the roll records made now (maybe several: a missed roll during
    --- downtime is made late, in order, at the hour it was due; DOUBLE TROUBLE chains at most CHAIN_MAX deep).
    function M.step(st, seed, run, hours)
        local made = {}
        M.expire(st, hours)
        local guard = 0
        while hours >= st.nextRollH and guard < 200 do
            guard = guard + 1
            local at = st.nextRollH
            local pending, depth = 1, 0
            while pending > 0 and depth <= M.CHAIN_MAX * 2 do
                pending = pending - 1
                local rec, extra = apply(st, seed, run, at)
                made[#made + 1] = rec
                if extra > 0 and depth < M.CHAIN_MAX then pending = pending + extra; depth = depth + 1 end
            end
            st.nextRollH = at + cadence(st, at) + (st.delayNext or 0)
            st.delayNext = nil
            M.expire(st, hours)
        end
        for _, r in ipairs(made) do st.log[#st.log + 1] = { n = r.n, id = r.id, hours = r.hours } end
        while #st.log > 60 do table.remove(st.log, 1) end
        return made
    end

    --- The combined effect of every active condition: { purse = {tier=x}, calendar = {tier=x}, lure = {tier=0..1},
    --- limit, policeCap, perLevel }. Multipliers multiply, caps add, lures take the strongest.
    function M.effects(st, hours)
        local out = { purse = tiers(ALL, 1), calendar = tiers(ALL, 1), lure = tiers(ALL, 0), limit = 1, policeCap = 0, perLevel = 1 }
        for _, a in ipairs((st and st.active) or {}) do
            local f = BY[a.id]
            if f and f.fx and (hours == nil or (hours >= a.fromH and hours < a.untilH)) then
                for t, x in pairs(f.fx.purse or {}) do out.purse[t] = out.purse[t] * x end
                for t, x in pairs(f.fx.calendar or {}) do out.calendar[t] = out.calendar[t] * x end
                for t, x in pairs(f.fx.lure or {}) do out.lure[t] = math.max(out.lure[t], x) end
                out.limit = out.limit * (f.fx.limit or 1)
                out.policeCap = out.policeCap + (f.fx.policeCap or 0)
                out.perLevel = out.perLevel * (f.fx.perLevel or 1)
            end
        end
        return out
    end

    --- What everyone may know: the active conditions by name and when they lift, and when the dice roll next.
    function M.public(st, hours)
        local list = {}
        for _, a in ipairs((st and st.active) or {}) do
            list[#list + 1] = { id = a.id, name = a.name, untilH = math.floor(a.untilH * 10 + 0.5) / 10 }
        end
        table.sort(list, function(a, b) if a.untilH ~= b.untilH then return a.untilH < b.untilH end return a.id < b.id end)
        return { active = list, nextRollH = st and st.nextRollH, restless = (st and st.restlessUntilH and hours and hours < st.restlessUntilH) or nil }
    end

    --- How a lured purse reaches ONE person (doc 47 §1.8: "the die doesn't move the pieces; it changes what the pieces
    --- have reasons to do"). `who` = { aggression 0..100, discipline 0..100, need 0..1 (how badly they need money: a
    --- broke independent 1, a rich team 0), shaken 0..1 (saw a bad crash lately) }. Returns
    ---   attend  x on their chance of turning up: the needy and the bold come, the careful and the shaken stay away;
    ---   risk    x on their racing hazard once there: the bait is driven harder by those it caught.
    --- A cautious, wealthy Premier driver says no thanks; a broke street racer says that's life-changing money.
    function M.pull(lure, purseX, who)
        lure, purseX, who = tonumber(lure) or 0, tonumber(purseX) or 1, who or {}
        local draw = lure * math.max(0, math.min(2, purseX - 1)) / 2
        if draw <= 0 then return 1, 1, 0 end
        local bold = (tonumber(who.aggression) or 50) / 100
        local caution = (tonumber(who.discipline) or 50) / 100
        local need = math.max(0, math.min(1, tonumber(who.need) or 0.5))
        local shaken = math.max(0, math.min(1, tonumber(who.shaken) or 0))
        local desire = draw * (0.6 * need + 0.4 * bold - 0.5 * caution - 0.6 * shaken)
        local attend = math.max(0.4, math.min(1.9, 1 + 0.9 * desire))
        local risk = 1 + 0.5 * draw * math.max(0, bold + need - caution)
        return attend, risk, desire
    end

    return M
end)
