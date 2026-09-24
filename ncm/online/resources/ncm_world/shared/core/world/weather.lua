-- ncm-core module: world.weather
-- Pure deterministic weather planning, forecast projection and compact session provenance.
-- Hosts own clocks, persistence and OPEN//77 calls.
local Core = NcmCore

Core.define("world.weather", function()
    local M = { version = "0.1.0", generatorVersion = 1, forecastModelVersion = 1 }

    local ALLOWED = {
        sunny=true, lightclouds=true, cloudy=true, rain=true,
        heavyclouds=true, fog=true, pollution=true, sandstorm=true,
    }
    local FAMILY = {
        sunny="dry", lightclouds="dry", cloudy="dry", rain="wet",
        heavyclouds="obscured", fog="obscured", pollution="hazardous", sandstorm="hazardous",
    }

    local function integer(v) return type(v) == "number" and v == math.floor(v) end
    local function copy(row)
        local out = {}; for k, v in pairs(row) do out[k] = v end; return out
    end

    function M.validatePolicy(p)
        if type(p) ~= "table" then return false, "not_a_table" end
        if not integer(p.version) or p.version < 1 then return false, "invalid_version" end
        if type(p.states) ~= "table" or #p.states == 0 then return false, "states_required" end
        local total = 0
        for i, s in ipairs(p.states) do
            if type(s) ~= "table" or not ALLOWED[s.weather] then return false, "invalid_weather:" .. tostring(i) end
            if not integer(s.minDurationSec) or not integer(s.maxDurationSec) or s.minDurationSec < 60 or s.maxDurationSec < s.minDurationSec then
                return false, "invalid_duration:" .. tostring(i)
            end
            if type(s.weight) ~= "number" or s.weight <= 0 then return false, "invalid_weight:" .. tostring(i) end
            total = total + s.weight
        end
        if p.transitionSec ~= nil and (not integer(p.transitionSec) or p.transitionSec < 0) then return false, "invalid_transition" end
        return true, total
    end

    -- Park-Miller: exact in Lua doubles for these operands and identical under Lua 5.4/LuaJIT.
    local function nextRandom(state)
        state = (state * 48271) % 2147483647
        return state, state / 2147483647
    end

    local function choose(policy, state, avoid)
        local total = 0
        for _, s in ipairs(policy.states) do total = total + s.weight end
        local r
        state, r = nextRandom(state)
        local pick, acc = r * total, 0
        local selected = policy.states[#policy.states]
        for _, s in ipairs(policy.states) do
            acc = acc + s.weight
            if pick <= acc then selected = s; break end
        end
        -- Avoid immediate repeats when alternatives exist; deterministic and does not reroll indefinitely.
        if selected.weather == avoid and #policy.states > 1 then
            local at = 1
            for i, s in ipairs(policy.states) do if s == selected then at = i; break end end
            selected = policy.states[(at % #policy.states) + 1]
        end
        state, r = nextRandom(state)
        local span = selected.maxDurationSec - selected.minDurationSec
        local duration = selected.minDurationSec + math.floor(r * (span + 1))
        return selected, duration, state
    end

    function M.generate(opts)
        opts = opts or {}
        local policy = opts.policy
        local ok, why = M.validatePolicy(policy)
        if not ok then error("weather.generate: " .. why, 2) end
        if not integer(opts.startsAtUtc) then error("weather.generate: startsAtUtc_required", 2) end
        if not integer(opts.untilUtc) or opts.untilUtc <= opts.startsAtUtc then error("weather.generate: invalid_untilUtc", 2) end
        if not integer(opts.seed) or opts.seed <= 0 or opts.seed >= 2147483647 then error("weather.generate: invalid_seed", 2) end
        local epoch = tostring(opts.epoch or opts.startsAtUtc)
        local rows, at, state, previous = {}, opts.startsAtUtc, opts.seed, opts.previousWeather
        local index = tonumber(opts.startIndex) or 1
        while at < opts.untilUtc do
            local selected, duration
            selected, duration, state = choose(policy, state, previous)
            rows[#rows + 1] = {
                id = epoch .. ":" .. tostring(index), startsAtUtc = at,
                weather = selected.weather, transitionSec = policy.transitionSec or 30,
                policyVersion = policy.version, generatorVersion = M.generatorVersion,
            }
            previous, at, index = selected.weather, at + duration, index + 1
        end
        return {
            epoch=epoch, seed=opts.seed, randomState=state, policyVersion=policy.version,
            generatorVersion=M.generatorVersion, nextIndex=index, coveredUntilUtc=at, rows=rows,
        }
    end

    function M.extend(plan, policy, untilUtc)
        if type(plan) ~= "table" or type(plan.rows) ~= "table" or #plan.rows == 0 then error("weather.extend: invalid_plan", 2) end
        if not integer(untilUtc) then error("weather.extend: invalid_untilUtc", 2) end
        if untilUtc <= plan.coveredUntilUtc then return plan end
        if policy.version ~= plan.policyVersion then return nil, "policy_version_mismatch" end
        local tail = M.generate{
            policy=policy, startsAtUtc=plan.coveredUntilUtc, untilUtc=untilUtc,
            seed=plan.randomState, epoch=plan.epoch, startIndex=plan.nextIndex,
            previousWeather=plan.rows[#plan.rows].weather,
        }
        local out = copy(plan); out.rows = {}
        for _, row in ipairs(plan.rows) do out.rows[#out.rows + 1] = copy(row) end
        for _, row in ipairs(tail.rows) do out.rows[#out.rows + 1] = row end
        out.randomState, out.nextIndex, out.coveredUntilUtc = tail.randomState, tail.nextIndex, tail.coveredUntilUtc
        return out
    end

    function M.at(rows, utc)
        if type(rows) ~= "table" or #rows == 0 then return nil end
        local found
        for i = 1, #rows do if rows[i].startsAtUtc <= utc then found = rows[i] else break end end
        return found
    end

    local function confidence(lead, bands)
        if lead <= bands.highSec then return "HIGH", "FORECAST" end
        if lead <= bands.mediumSec then return "MED", "FORECAST" end
        return "LOW", "OUTLOOK"
    end

    function M.forecast(plan, issuedAtUtc, opts)
        opts = opts or {}; local bands = opts.confidence or { highSec=5400, mediumSec=86400 }
        local horizon = opts.horizonSec or 604800
        local out = {}
        for i, row in ipairs(plan.rows or {}) do
            local toUtc = (plan.rows[i + 1] and plan.rows[i + 1].startsAtUtc) or plan.coveredUntilUtc
            if toUtc > issuedAtUtc and row.startsAtUtc < issuedAtUtc + horizon then
                local fromUtc = math.max(row.startsAtUtc, issuedAtUtc)
                local lead = math.max(0, fromUtc - issuedAtUtc)
                local conf, kind = confidence(lead, bands)
                out[#out + 1] = { fromUtc=fromUtc, toUtc=math.min(toUtc, issuedAtUtc+horizon), weather=row.weather,
                    family=FAMILY[row.weather], confidence=conf, kind=lead == 0 and "OBSERVED" or kind,
                    transitionSec=row.transitionSec, transitionId=row.id }
            end
        end
        return out
    end

    --- What a scheduled event should expect, from forecast bands (IDEA-133).
    --- `forecast` is M.forecast() output; `startUtc` is the event start; `endUtc` is OPTIONAL.
    ---
    --- Start time alone is not the answer the Race Guide needs: a race beginning at 15:55 with rain from 16:03
    --- is not a dry race. So when an end is supplied this reports every band the event overlaps. When it is not
    --- -- which is today, because no event carries an authoritative duration -- it reports the start honestly
    --- and says `windowKnown = false` rather than guessing a length and calling the guess a forecast.
    ---
    --- Returns nil when the bands cannot answer (empty forecast, or the event starts beyond the horizon):
    --- absent is not "sunny".
    function M.forEvent(forecast, startUtc, endUtc)
        if type(forecast) ~= "table" or #forecast == 0 then return nil end
        if type(startUtc) ~= "number" then return nil end
        local windowEnd = (type(endUtc) == "number" and endUtc > startUtc) and endUtc or startUtc

        local bands, atStart = {}, nil
        for _, b in ipairs(forecast) do
            if b.fromUtc <= startUtc and b.toUtc > startUtc then atStart = b end
            -- overlap, treating a zero-length window as the instant itself
            if b.fromUtc <= windowEnd and b.toUtc > startUtc then bands[#bands + 1] = b end
        end
        if not atStart then return nil end

        -- the weakest confidence over the window is the one worth reporting; a HIGH start followed by a LOW
        -- band is not a high-confidence race
        local RANK = { HIGH = 3, MED = 2, LOW = 1 }
        local worst, changes = atStart.confidence, false
        for _, b in ipairs(bands) do
            if (RANK[b.confidence] or 1) < (RANK[worst] or 1) then worst = b.confidence end
            if b.weather ~= atStart.weather then changes = true end
        end

        return {
            atStart = { weather = atStart.weather, family = atStart.family,
                        confidence = atStart.confidence, kind = atStart.kind },
            confidence = worst,
            changes = changes,
            windowKnown = windowEnd > startUtc,
            bands = bands,
            -- a transition landing near the start is worth saying even when the window is unknown
            transitionNearStart = (atStart.toUtc - startUtc) <= 600 and atStart.toUtc or nil,
        }
    end

    function M.provenance(rows, startedAtUtc, finishedAtUtc, scope, revisions)
        if finishedAtUtc < startedAtUtc then error("weather.provenance: finish_before_start", 2) end
        local start = M.at(rows, startedAtUtc)
        if not start then return nil, "history_unavailable" end
        local transitions, totals, cursor, active = {}, {dry=0, wet=0, obscured=0, hazardous=0}, startedAtUtc, start
        for _, row in ipairs(rows) do
            if row.startsAtUtc > startedAtUtc and row.startsAtUtc <= finishedAtUtc then
                totals[FAMILY[active.weather]] = totals[FAMILY[active.weather]] + (row.startsAtUtc - cursor)
                transitions[#transitions + 1] = { offsetSec=row.startsAtUtc-startedAtUtc, weather=row.weather,
                    transitionSec=row.transitionSec, revision=revisions and revisions[row.id] or nil }
                cursor, active = row.startsAtUtc, row
            end
        end
        totals[FAMILY[active.weather]] = totals[FAMILY[active.weather]] + (finishedAtUtc - cursor)
        return {
            start={utc=startedAtUtc, weather=start.weather, scope=scope or "default", revision=revisions and revisions[start.id] or nil},
            transitions=transitions,
            finish={utc=finishedAtUtc, weather=active.weather, revision=revisions and revisions[active.id] or nil},
            durationByFamilySec=totals,
        }
    end

    function M.family(weather) return FAMILY[weather] end
    return M
end)
