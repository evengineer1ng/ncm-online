-- ncm-core module: life.schedule
-- A Paddock person's day, chosen by need over real places on the real Eastern clock (L237 M1, IDEA-765, L240).
--
-- NO TIMETABLES. Every 30-minute block the person scores each thing they could do next -- sleep, eat at a food stall,
-- hang at a street meet, run an errand, hustle at a fixer's spot, stop for fuel, cruise, stay home -- at each of
-- their regular places, and does the best one. The score is the urgency of each need times what the activity gives
-- it, bent by personality, by the district's climate (`life.climate.pressures`), by whether the place is open, how
-- far away it is and how late it is. Commitments are the only fixed points: a garage shift and the person's own race
-- come from the host (`ctx.commitment`) and override choice, as doc 44 §11 and L237 require.
--
-- WHAT IS AUTHORED: the verbs in ACTIVITIES, their gains, and the scoring rules. WHAT IS NOT: who goes where, when.
--
-- LAZY AND STATELESS. A plan is a pure function of (seed, person, Eastern day, climate, commitments), so the host
-- plans only people a player could meet, caches the plan for the day, and a restart recomputes the same day.
-- A plan day runs 04:00 to 04:00 Eastern: the small hours belong to the night before, like a street team's shift.
--
--   plan { day, home, runs = { { activity, placeId, district, startBlock, endBlock, fromUtc, toUtc } }, dawn, dusk }
--   placeId is a `world.places` id, or "home" / "road" / "track" for the three places no body is ever shown.
local Core = NcmCore

Core.define("life.schedule", function(C)
    local M = { version = "0.1.0", BLOCKS = 48, DAY_START = 4 * 3600, REGULARS = 2 }
    local Hash = C.get("vocabulary.hash")
    local Clock = C.get("world.clock")
    local Places = C.get("world.places")
    local Needs = C.get("life.needs")
    local Climate = C.get("life.climate")

    local BLOCK = Needs.BLOCK_SEC
    local H = 3600

    -- The verbs. `kinds`: where it happens (world.places kinds); `place`: a bodiless pseudo-place instead.
    -- `gains` per block; `spend` drains money per block; `night`: exposed to the street after dark;
    -- `commitOnly`: never chosen, only imposed by a commitment.
    M.ACTIVITIES = {
        sleep  = { place = "home", gains = { rest = 7.5 }, minBlocks = 6 },
        home   = { place = "home", gains = { rest = 2.0 } },
        eat    = { kinds = { food = true }, gains = { social = 3.0, rest = 1.0 }, spend = 0.6, maxBlocks = 2, meals = true },
        loiter = { kinds = { food = true, clothing = true, junk = true, fuel = true }, gains = { social = 2.5 },
            maxBlocks = 3 },
        hang   = { kinds = { meet = true }, gains = { social = 4.0, drive = 5.0 }, night = true, maxBlocks = 5,
            meets = true },
        errand = { kinds = { clinic = true, ripperdoc = true, weapons = true, clothing = true, junk = true,
            tech = true }, gains = { social = 1.0, money = 0.5 }, spend = 0.6, maxBlocks = 1, base = 0.16 },
        hustle = { kinds = { fixer = true, netrunner = true }, gains = { money = 4.0, social = 1.0 }, night = true,
            maxBlocks = 3 },
        fuel   = { kinds = { fuel = true }, gains = { drive = 3.0 }, spend = 0.4, maxBlocks = 1 },
        cruise = { place = "road", gains = { drive = 4.5 }, spend = 0.3, night = true, maxBlocks = 3 },
        work   = { commitOnly = true, gains = { money = 4.5, social = 1.5, drive = 0.5 } },
        race   = { commitOnly = true, place = "track", gains = { drive = 14, money = 2, social = 2 } },
    }
    M.ORDER = { "sleep", "home", "eat", "loiter", "hang", "errand", "hustle", "fuel", "cruise" }
    M.DRIVER_WORK = { money = 4.5, social = 1.5, drive = 1.5 }   -- a driver's shift includes seat time

    -- How many people a kind of place holds at once. With `ctx.regularCount` (place -> how many people count it
    -- among their regulars, which the host knows) a crowded place is taken in TURNS: in each 2-hour window a person
    -- may use it only if a deterministic draw falls inside its share, so the rest go elsewhere. Measured on dev
    -- 2026-09-30 before this: 121 people at one street meet, 68 at the one Heywood fixer's spot, 844 place-slots
    -- over four. Rules, not situations (L237): who wins a turn is a draw, not a script.
    M.CAPACITY = { food = 12, loiter = 10, meet = 40, fixer = 6, netrunner = 4, clinic = 10, ripperdoc = 4, weapons = 6,
        clothing = 8, junk = 6, tech = 4, fuel = 6 }
    M.TURN_BLOCKS = 4

    -- Some verbs belong to some lives: a premier strategist does not work an angle at a fixer's spot.
    M.TIER_BIAS = { hustle = { street = 1.0, regional = 0.5, pro = 0.25, premier = 0.15 } }
    M.MEALS = 3                 -- a day's meals ...
    M.MEAL_GAP = 6              -- ... at least this many blocks apart
    -- Iteration is always in a fixed order, never `pairs`: each candidate draws noise from the day's stream, so the
    -- order of evaluation IS the plan.
    for _, a in pairs(M.ACTIVITIES) do
        if a.kinds then
            a.kindList = {}
            for k in pairs(a.kinds) do a.kindList[#a.kindList + 1] = k end
            table.sort(a.kindList)
        end
    end
    M.BODILY = {}          -- activities a player can walk up to
    for id, a in pairs(M.ACTIVITIES) do if a.kinds or id == "work" then M.BODILY[id] = true end end

    -- Where each tier tends to live when not near the garage (canon-flavoured, not a rule of fate).
    M.HOME_POOL = {
        street = { "Watson", "Santo Domingo", "Heywood", "Pacifica", "Watson", "Heywood" },
        regional = { "Heywood", "Santo Domingo", "Westbrook", "Watson" },
        pro = { "Westbrook", "Heywood", "City Center" },
        premier = { "Westbrook", "City Center", "Westbrook" },
    }

    --- The district a person lives in: usually near work, otherwise their tier's usual neighbourhoods.
    function M.homeDistrict(seed, person, tier, workDistrict)
        if workDistrict and Hash.unit(seed, "home_near_work", person.id) < 0.6 then return workDistrict end
        return Hash.pick(M.HOME_POOL[tier or "street"] or M.HOME_POOL.street, seed, "home", person.id)
    end

    --- When this person sleeps: Eastern seconds-of-day. Street people keep street hours; temperament pushes later.
    function M.chronotype(seed, person, tier)
        local pers = person.personality or {}
        local base = (tier == "street") and 2.5 * H or 23.5 * H
        local r = Hash.stream(seed, "chronotype", person.id)
        local shift = r:normal(0, 1.0) * H + (pers.temperament or 0) * 0.75 * H
        return math.floor((base + shift) / BLOCK + 0.5) * BLOCK % 86400
    end

    local centroid = {}
    local function districtCentre(d)
        if centroid[d] then return centroid[d] end
        local sx, sy, n = 0, 0, 0
        for _, p in ipairs(Places.inDistrict(d)) do sx, sy, n = sx + p.x, sy + p.y, n + 1 end
        centroid[d] = n > 0 and { x = sx / n, y = sy / n } or { x = 0, y = 0 }
        return centroid[d]
    end
    M.districtCentre = districtCentre

    --- A person's regular places: for each kind, the REGULARS best-ranked places in their home and work districts.
    --- Stable per person, so "where someone is usually found" is a real answer (IDEA-766, F6 DIRECTORY).
    function M.regulars(seed, person, home, work, bad)
        local byKind = {}
        local seen = {}
        for _, d in ipairs({ home, work }) do
            if d and not seen[d] then
                seen[d] = true
                for _, p in ipairs(Places.inDistrict(d, nil, bad)) do
                    byKind[p.kind] = byKind[p.kind] or {}
                    table.insert(byKind[p.kind], { p = p, rank = Hash.fnv1a32(Hash.key(seed, "regular", person.id, p.id)) })
                end
            end
        end
        local out = {}
        for kind, list in pairs(byKind) do
            table.sort(list, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.p.id < b.p.id end)
            local keep = {}
            for i = 1, math.min(M.REGULARS, #list) do keep[i] = list[i].p end
            out[kind] = keep
        end
        return out
    end

    local function inWindow(sod, from, len)
        local rel = (sod - from) % 86400
        return rel < len
    end

    --- The Eastern plan day an instant belongs to (04:00-to-04:00).
    function M.planDay(utc)
        return Clock.eastern(utc - M.DAY_START).dayIndex
    end

    --- Plan one person's day.
    ---   ctx = { seed, person, tier, workDistrict, workPlaceId, climate, bad, commitment = fn(utc) -> activity|nil }
    function M.plan(ctx, dayIndex)
        local seed, person = ctx.seed, ctx.person
        local pers = person.personality or {}
        local tier = ctx.tier or "street"
        local home = M.homeDistrict(seed, person, tier, ctx.workDistrict)
        local regs = M.regulars(seed, person, home, ctx.workDistrict, ctx.bad)
        local sleepFrom = M.chronotype(seed, person, tier)
        local r = Hash.stream(seed, "day", person.id, dayIndex)
        local needs = Needs.dawn(seed, person, dayIndex)
        local dawn = needs
        local noiseSd = 0.05 * (1 + 0.6 * (pers.temperament or 0))
        local valor = pers.valor or 0
        local authority = pers.authority or 0

        local pressureCache = {}
        local function pressure(d)
            if not pressureCache[d] then pressureCache[d] = Climate.pressures(ctx.climate, d) end
            return pressureCache[d]
        end
        local homeP = pressure(home)
        local decay = Needs.decayFor(person, homeP)

        -- Every candidate (verb x regular place) is built ONCE with its constant terms, so a block only adds what
        -- changes: need urgency, distance, the hour. On the host every instruction is metered (KB-211): a plan must
        -- stay far below one slice. Verbs with many places (errands, loitering) are ROTATED: each block scores a
        -- window of ROTATE of them, deterministically, instead of all -- a person does not weigh every shop in the
        -- district every half hour either.
        local cands, groups = {}, {}
        for _, act in ipairs(M.ORDER) do
            local a = M.ACTIVITIES[act]
            if a.kinds then
                for _, kind in ipairs(a.kindList) do
                    for _, place in ipairs(regs[kind] or {}) do
                        local kd, pp = Places.KINDS[place.kind], pressure(place.district)
                        local c = { act = act, a = a, place = place, id = place.id, district = place.district,
                            social = pp.social * (0.5 + kd.crowd), drive = pp.drive, night = pp.night * (1 - valor) * 0.25,
                            fixed = (a.base or 0) + authority * (kd.visibility - 0.5) * 0.1,
                            open = (not a.meets) or pp.meets }
                        cands[#cands + 1] = c
                        groups[act] = groups[act] or {}
                        table.insert(groups[act], c)
                    end
                end
            else
                cands[#cands + 1] = { act = act, a = a, id = a.place, district = home, social = homeP.social * 0.6,
                    drive = homeP.drive, night = homeP.night * (1 - valor) * 0.25, fixed = a.base or 0, open = true }
            end
        end
        for _, act in ipairs(M.ORDER) do
            local list = groups[act]
            if list then for i, c in ipairs(list) do c.slot, c.of = i - 1, #list end end
        end
        -- Turns at crowded places: a share < 1 means this person may use the place only in some 2-hour windows,
        -- drawn once per (place, window) -- never per block, which would cost a hash per candidate per block.
        if ctx.regularCount then
            for _, c in ipairs(cands) do
                if c.place then
                    local cap = M.CAPACITY[c.place.kind]
                    local n = ctx.regularCount[c.place.id]
                    if cap and n and n > cap then c.share = cap / n end
                end
            end
        end
        local function turnOk(c, b)
            if not c.share then return true end
            local w = math.floor(b / M.TURN_BLOCKS)
            c.turns = c.turns or {}
            local ok = c.turns[w]
            if ok == nil then
                ok = Hash.unit(seed, "turn", person.id, c.id, dayIndex, w) < c.share
                c.turns[w] = ok
            end
            return ok
        end
        local bias = {}
        for act, byTier in pairs(M.TIER_BIAS) do bias[act] = byTier[tier] or 1 end
        local ROTATE = 2
        local noiseW = noiseSd * 3.4641                       -- a uniform draw with the same spread as N(0, noiseSd)

        local runs = {}
        local cur, curLen = nil, 0
        local where = districtCentre(home)
        local timesToday = {}
        local meals, lastMeal = 0, nil
        local dayUtc = Clock.utcAt(dayIndex, M.DAY_START)

        for b = 0, M.BLOCKS - 1 do
            if ctx.yield and b > 0 and b % 16 == 0 then ctx.yield() end
            local sodAbs = M.DAY_START + b * BLOCK
            local sod = sodAbs % 86400
            local utc = dayUtc + b * BLOCK
            local night = inWindow(sod, sleepFrom, 8 * H)
            local late = sod >= 22 * H or sod < 5 * H
            local choice
            local committed = ctx.commitment and ctx.commitment(utc)
            if committed == "work" then
                local wp = ctx.workPlaceId and Places.get(ctx.workPlaceId)
                choice = { activity = "work", placeId = ctx.workPlaceId or "home", district = wp and wp.district or home,
                    place = wp }
            elseif committed == "race" then
                choice = { activity = "race", placeId = "track", district = home }
            elseif cur and cur.activity == "sleep" and (curLen < M.ACTIVITIES.sleep.minBlocks or night) then
                choice = cur                          -- nobody naps for half an hour, and a night's sleep runs its course
            else
                local uMoney, uRest = Needs.urgency(needs.money), Needs.urgency(needs.rest)
                local uSocial, uDrive = Needs.urgency(needs.social), Needs.urgency(needs.drive)
                local mealOk = meals < M.MEALS and not (lastMeal and b - lastMeal < M.MEAL_GAP)
                local best, bestU
                for _, c in ipairs(cands) do
                    local a, act = c.a, c.act
                    local current = cur and cur.placeId == c.id and cur.activity == act
                    local inWin = (not c.of) or c.of <= ROTATE or ((c.slot - b) % c.of) < ROTATE or current
                    if inWin and c.open and ((not a.meals) or mealOk) and ((not c.place) or Places.openAt(c.place, sod))
                        and (current or turnOk(c, b)) then
                        local g = a.gains
                        local u = c.fixed + uMoney * (g.money or 0) + uRest * (g.rest or 0)
                            + uSocial * (g.social or 0) * c.social + uDrive * (g.drive or 0) * c.drive
                        if a.spend then u = u - a.spend * 0.08 * (1 + 3 * uMoney) end
                        if bias[act] and u > 0 then u = u * bias[act] end
                        -- Sleep is circadian first: in their own night people sleep; otherwise only exhaustion.
                        if act == "sleep" then
                            if night then u = u * 1.5 + 1.2 else u = u * 0.3 end
                        elseif act ~= "home" and night then
                            u = u * 0.55
                        end
                        if a.night and late then u = u - c.night end
                        if c.place then
                            local dx, dy = c.place.x - where.x, c.place.y - where.y
                            u = u - math.sqrt(dx * dx + dy * dy) * 0.00003          -- a long way to go for a noodle
                        end
                        local skip = false
                        if current then
                            if a.maxBlocks and curLen >= a.maxBlocks then skip = true end
                            u = u + 0.12                                           -- people finish what they start
                        elseif timesToday[act] then
                            u = u - 0.08 * timesToday[act]
                        end
                        if not skip then
                            u = u + (r() - 0.5) * noiseW
                            if not bestU or u > bestU then best, bestU = c, u end
                        end
                    end
                end
                if best then
                    choice = { activity = best.act, placeId = best.id, district = best.district, place = best.place }
                else
                    choice = { activity = "home", placeId = "home", district = home }
                end
            end

            local a = M.ACTIVITIES[choice.activity]
            local gains = a.gains
            if choice.activity == "work" and person.role == "driver" then gains = M.DRIVER_WORK end
            needs = Needs.apply(needs, decay, gains, a.spend)

            if cur and cur.activity == choice.activity and cur.placeId == choice.placeId then
                curLen = curLen + 1
                runs[#runs].endBlock = b + 1
                runs[#runs].toUtc = utc + BLOCK
            else
                if cur and cur.activity ~= "sleep" and cur.activity ~= "home" then
                    timesToday[cur.activity] = (timesToday[cur.activity] or 0) + 1
                end
                if choice.activity == "eat" then meals, lastMeal = meals + 1, b end
                cur, curLen = choice, 1
                runs[#runs + 1] = { activity = choice.activity, placeId = choice.placeId, district = choice.district,
                    startBlock = b, endBlock = b + 1, fromUtc = utc, toUtc = utc + BLOCK }
            end
            if choice.place then where = choice.place elseif choice.placeId == "home" then where = districtCentre(home) end
        end
        return { day = dayIndex, home = home, sleepFrom = sleepFrom, runs = runs, dawn = dawn, dusk = needs }
    end

    --- The run a plan has at `utc`, or nil.
    function M.at(plan, utc)
        if not plan then return nil end
        for _, run in ipairs(plan.runs) do
            if utc >= run.fromUtc and utc < run.toUtc then return run end
        end
        return nil
    end

    --- The place a player could find this person at `utc`, or nil when they are home, on the road or at the track.
    function M.bodyAt(plan, utc)
        local run = M.at(plan, utc)
        if not run or not M.BODILY[run.activity] then return nil end
        local place = Places.get(run.placeId)
        if not place then return nil end
        return place, run
    end

    --- Where someone is usually found, most-used place first: { { placeId, blocks } }. For F6 DIRECTORY.
    function M.usually(plans)
        local count = {}
        for _, plan in ipairs(plans or {}) do
            for _, run in ipairs(plan.runs) do
                if M.BODILY[run.activity] then
                    count[run.placeId] = (count[run.placeId] or 0) + (run.endBlock - run.startBlock)
                end
            end
        end
        local out = {}
        for id, n in pairs(count) do out[#out + 1] = { placeId = id, blocks = n } end
        table.sort(out, function(a, b) if a.blocks ~= b.blocks then return a.blocks > b.blocks end return a.placeId < b.placeId end)
        return out
    end

    return M
end)
