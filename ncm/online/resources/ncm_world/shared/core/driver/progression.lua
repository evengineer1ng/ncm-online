-- ncm-core module: driver.progression
-- Driver dimensions (L54): licence per discipline earned by clean sessions, safety rating from incidents, a rating
-- skeleton per class for seeding, accomplishments. Pure: (state, result, ctx) -> new state + deltas. Nothing here
-- gates anything; hosts read the dimensions, they never block an entry in the first world.
local Core = NcmCore

Core.define("driver.progression", function(C)
    local M = { version = "0.0.1" }

    M.LICENCE_LEVELS = { "rookie", "licensed", "pro" }
    M.LICENCE_CLEAN = { licensed = 3, pro = 10 }   -- clean completed sessions to reach a level
    M.SR = { start = 5.0, min = 0, max = 10, cleanGain = 0.05, perBand = 0.1 }
    M.RATING = { start = 1000, perPlace = 4 }

    function M.newState()
        return { licences = {}, sr = { sr = M.SR.start, incidents = 0, clean = 0 }, ratings = {}, accomplishments = {} }
    end

    local function levelFor(clean)
        if clean >= M.LICENCE_CLEAN.pro then return "pro" end
        if clean >= M.LICENCE_CLEAN.licensed then return "licensed" end
        return "rookie"
    end

    --- L67 / IDEA-001: a field of one is a TIME TRIAL, not a race. It is a real, recorded, classified run -- it
    --- earns the finish, the clean-race credit, SR movement and a route time -- but it cannot be *won*, because
    --- nobody was beaten. Anything derived from finishing position (wins, podiums, rating and, once they exist,
    --- championship points) requires an opponent. Hosts use this to label the result as well.
    function M.isTimeTrial(ctx)
        return (tonumber(ctx and ctx.fieldSize) or 0) <= 1
    end

    local function has(state, kind, refId)
        for _, a in ipairs(state.accomplishments) do if a.kind == kind and (refId == nil or a.refId == refId) then return true end end
        return false
    end

    --- Apply one classified result. result = classify() row (state, position, incidentCount, incidents? = {band…});
    --- ctx = { disciplineId, classId, sessionKind, fieldSize, sessionId }. Returns state, deltas, newAccomplishments.
    function M.apply(state, result, ctx)
        state = state or M.newState()
        ctx = ctx or {}
        local deltas, newAcc = {}, {}
        if ctx.sessionKind and ctx.sessionKind ~= "race" then return state, deltas, newAcc end
        local finished = result.state == "finished"
        local incidents = tonumber(result.incidentCount) or 0
        local clean = finished and incidents == 0
        local contested = not M.isTimeTrial(ctx)

        -- licence per discipline
        if ctx.disciplineId and finished then
            local lic = state.licences[ctx.disciplineId] or { level = "rookie", clean = 0 }
            state.licences[ctx.disciplineId] = lic
            if clean then
                lic.clean = lic.clean + 1
                local before = lic.level
                lic.level = levelFor(lic.clean)
                deltas[#deltas + 1] = { kind = "licence_clean", disciplineId = ctx.disciplineId, clean = lic.clean }
                if lic.level ~= before then deltas[#deltas + 1] = { kind = "licence_level", disciplineId = ctx.disciplineId, level = lic.level } end
            end
        end

        -- safety rating (the badge)
        local sr = state.sr
        if clean then
            sr.sr = math.min(M.SR.max, sr.sr + M.SR.cleanGain); sr.clean = sr.clean + 1
            deltas[#deltas + 1] = { kind = "sr", delta = M.SR.cleanGain, sr = sr.sr }
        elseif incidents > 0 then
            local drop = 0
            for _, inc in ipairs(result.incidents or {}) do drop = drop + M.SR.perBand * (inc.band or 1) end
            if drop == 0 then drop = M.SR.perBand * incidents end
            sr.sr = math.max(M.SR.min, sr.sr - drop); sr.incidents = sr.incidents + incidents
            deltas[#deltas + 1] = { kind = "sr", delta = -drop, sr = sr.sr }
        end

        -- rating skeleton per class (seeding only)
        if ctx.classId and result.position and contested then
            local rt = state.ratings[ctx.classId] or { rating = M.RATING.start, sessions = 0 }
            state.ratings[ctx.classId] = rt
            local delta = ((ctx.fieldSize + 1) / 2 - result.position) * M.RATING.perPlace
            rt.rating = rt.rating + delta; rt.sessions = rt.sessions + 1
            deltas[#deltas + 1] = { kind = "rating", classId = ctx.classId, delta = delta, rating = rt.rating }
        end

        -- accomplishments (record only)
        -- KB-38: `once and nil or refId` always evaluates to refId, because nil is falsy -- so the once-only
        -- guard asked "has this kind for THIS session", which no earlier session can satisfy, and first_finish /
        -- first_win / first_time_trial were re-granted on every single race.
        local function grant(kind, refId, once)
            if once then
                if has(state, kind, nil) then return end        -- any earlier one of this kind is enough
            elseif has(state, kind, refId) then
                return                                          -- repeatable: once per session, not once per life
            end
            local a = { kind = kind, refId = refId, at = ctx.now }
            state.accomplishments[#state.accomplishments + 1] = a
            newAcc[#newAcc + 1] = a
        end
        if finished then grant("first_finish", ctx.sessionId, true) end
        if finished and contested and result.position == 1 then grant("first_win", ctx.sessionId, true) end
        if finished and not contested then grant("first_time_trial", ctx.sessionId, true) end
        if clean then grant("clean_race", ctx.sessionId, false) end
        return state, deltas, newAcc
    end

    --- One-line readout for chat.
    function M.describe(state)
        local parts = {}
        for d, lic in pairs(state.licences or {}) do parts[#parts + 1] = ("%s %s (%d clean)"):format(d, lic.level, lic.clean) end
        table.sort(parts)
        local lic = #parts > 0 and table.concat(parts, ", ") or "no licence yet"
        local rt = {}
        for cid, r in pairs(state.ratings or {}) do rt[#rt + 1] = ("%s %.0f (%d)"):format(cid, r.rating, r.sessions) end
        table.sort(rt)
        local acc = {}
        for _, a in ipairs(state.accomplishments or {}) do acc[a.kind] = (acc[a.kind] or 0) + 1 end
        local accs = {}
        for k, n in pairs(acc) do accs[#accs + 1] = n > 1 and (k .. "×" .. n) or k end
        table.sort(accs)
        return ("Licence: %s · SR %.2f (%d incidents, %d clean) · rating %s · %s"):format(
            lic, (state.sr or {}).sr or M.SR.start, (state.sr or {}).incidents or 0, (state.sr or {}).clean or 0,
            #rt > 0 and table.concat(rt, ", ") or "—", #accs > 0 and table.concat(accs, ", ") or "no accomplishments yet")
    end

    return M
end)
