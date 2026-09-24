local FanEngine = {}
local i18n = require("modules/i18n")

local RACE_MILESTONES = { 5, 10, 25, 50 }
local WIN_MILESTONES = { 1, 3, 5, 10 }
local PODIUM_MILESTONES = { 3, 5, 10, 20 }
local EDDIES_MILESTONES = { 10000, 50000, 100000, 250000 }
local CLEAN_STREAK_MILESTONES = { 3, 5 }
local WIN_STREAK_MILESTONES = { 3, 5 }
local MIN_PUSH_REAL_SECONDS = 240

local function activeCareer()
    return MTE and MTE.Careers and MTE.Careers.active and MTE.Careers.active() or nil
end

local function saveCareers()
    if MTE and MTE.Careers and MTE.Careers.save then
        pcall(MTE.Careers.save)
    end
end

local function currentRaceCount(career)
    local stats = MTE and MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career and career.stats or {}
    return tonumber(stats and stats.racesFinished or 0) or 0
end

local function champPosition(career)
    local season = career and MTE and MTE.Championships and MTE.Championships.activeSeason
        and MTE.Championships.activeSeason(career)
        or nil
    if not season or not (MTE and MTE.Championships and MTE.Championships.driverStandings) then
        return nil, nil
    end

    for index, row in ipairs(MTE.Championships.driverStandings(season) or {}) do
        if row.driverId == "player" then
            return index, tonumber(row.points or 0) or 0
        end
    end
    return nil, nil
end

local function firstThresholdHit(value, thresholds, sent, prefix)
    local current = tonumber(value or 0) or 0
    for _, threshold in ipairs(thresholds or {}) do
        local key = i18n.format("%s:%d", prefix, threshold)
        if current >= threshold and not sent[key] then
            return threshold, key
        end
    end
    return nil, nil
end

local function recentRaces(career, limit)
    local out = {}
    for _, summary in ipairs(career and career.raceHistory or {}) do
        if type(summary) == "table" then
            out[#out + 1] = summary
        end
        if #out >= (tonumber(limit) or 5) then
            break
        end
    end
    return out
end

local function telemetrySession(sessionId)
    if type(sessionId) ~= "string" or sessionId == "" then
        return nil
    end
    return MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.getSession and MTE.RaceTelemetry.getSession(sessionId) or nil
end

local function recentTelemetrySessions(career, limit)
    local sessions = {}
    for _, summary in ipairs(recentRaces(career, limit or 5)) do
        local session = telemetrySession(summary and summary.sessionId)
        if type(session) == "table" then
            sessions[#sessions + 1] = session
        end
    end
    return sessions
end

local function telemetrySignals(session)
    local counts = session and session.incidents and session.incidents.counts or {}
    return {
        overtakes = tonumber(counts and counts.overtakes or 0) or 0,
        lapOneGain = tonumber(counts and counts.positionsGainedLap1 or 0) or 0,
        recoveries = tonumber(counts and counts.recoveries or 0) or 0,
        collisions = tonumber(counts and counts.majorCollisions or 0) or 0,
        crashHeavy = session and session.crashHeavy == true or false,
        routeBest = session and session.recordFlags and ((session.recordFlags.routeBestRaceTime == true) or (session.recordFlags.routeBestLap == true)) or false,
    }
end

local function buildRaceDispatchKey(career, summary, data)
    local sessionId = tostring(data and data.sessionId or summary and summary.sessionId or "")
    if sessionId ~= "" then
        return "session:" .. sessionId
    end

    local routeKey = tostring(data and data.routeKey or summary and summary.routeKey or summary and summary.routeId or "?")
    local finishPos = tonumber(summary and summary.position or data and data.position or 0) or 0
    local startPos = tonumber(summary and summary.startPos or data and data.startPos or 0) or 0
    local fieldSize = tonumber(summary and summary.fieldSize or data and data.results and #data.results or 0) or 0
    local payout = tonumber(summary and summary.payout or data and data.payout or 0) or 0
    local timeMark = tonumber(summary and summary.playerTime or data and data.playerTime or 0) or 0
    local raceCount = currentRaceCount(career)
    local cleanFlag = summary and summary.clean == true and 1 or 0

    return i18n.format(
        "race:%d:%s:%d:%d:%d:%d:%d:%d",
        raceCount,
        routeKey,
        startPos,
        finishPos,
        fieldSize,
        math.floor((timeMark * 100.0) + 0.5),
        payout,
        cleanFlag)
end

local function ensureState(career)
    if type(career) ~= "table" then
        return nil
    end

    local state = career.fanState
    local changed = false
    if type(state) ~= "table" then
        state = {}
        career.fanState = state
        changed = true
    end
    if type(state.sentMilestones) ~= "table" then
        state.sentMilestones = {}
        changed = true
    end
    if type(state.identityProfile) ~= "table" then
        state.identityProfile = {}
        changed = true
    end
    if type(state.pending) ~= "table" then
        state.pending = {}
        changed = true
    end
    if type(state.lastPushText) ~= "string" then
        state.lastPushText = ""
        changed = true
    end
    if type(state.lastPushCategory) ~= "string" then
        state.lastPushCategory = ""
        changed = true
    end
    if type(state.lastPushKey) ~= "string" then
        state.lastPushKey = ""
        changed = true
    end
    if type(state.lastPullMode) ~= "string" then
        state.lastPullMode = ""
        changed = true
    end
    if tonumber(state.lastPushRace) == nil then
        state.lastPushRace = -99
        changed = true
    end
    if tonumber(state.lastPushAt) == nil then
        state.lastPushAt = 0
        changed = true
    end
    if tonumber(state.lastIdentityAt) == nil then
        state.lastIdentityAt = 0
        changed = true
    end
    if tonumber(state.lastSignatureAt) == nil then
        state.lastSignatureAt = 0
        changed = true
    end
    if tonumber(state.lastChampPos) == nil then
        state.lastChampPos = 0
        changed = true
    end
    if type(state.lastProcessedSessionId) ~= "string" then
        state.lastProcessedSessionId = ""
        changed = true
    end
    if type(state.lastProcessedRaceKey) ~= "string" then
        state.lastProcessedRaceKey = ""
        changed = true
    end
    if type(state.pending.newRecord) ~= "table" and state.pending.newRecord ~= nil then
        state.pending.newRecord = nil
        changed = true
    end
    if type(state.pending.catchUp) ~= "table" and state.pending.catchUp ~= nil then
        state.pending.catchUp = nil
        changed = true
    end
    if type(state.pending.cleanRun) ~= "table" and state.pending.cleanRun ~= nil then
        state.pending.cleanRun = nil
        changed = true
    end
    if type(state.pending.prestigeChange) ~= "table" and state.pending.prestigeChange ~= nil then
        state.pending.prestigeChange = nil
        changed = true
    end
    return state, changed
end

local function formatEddies(amount)
    return i18n.format("%d eddies", math.floor((tonumber(amount) or 0) + 0.5))
end

local function markMilestone(state, key)
    if key and key ~= "" then
        state.sentMilestones[key] = true
    end
end

local function commitPush(career, state, category, key, text)
    state.lastPushText = tostring(text or "")
    state.lastPushCategory = tostring(category or "")
    state.lastPushKey = tostring(key or "")
    state.lastPushRace = currentRaceCount(career)
    state.lastPushAt = tonumber(os.time() or 0) or 0
    if category == "signature" then
        state.lastSignatureAt = state.lastPushAt
    elseif category == "identity" then
        state.lastIdentityAt = state.lastPushAt
    end
    saveCareers()
    return state.lastPushText
end

local function canPush(career, state, minRaceGap, allowRepeatKey, nextKey, minSeconds)
    local currentRace = currentRaceCount(career)
    local now = tonumber(os.time() or 0) or 0
    local minimumSeconds = tonumber(minSeconds) or MIN_PUSH_REAL_SECONDS
    if not allowRepeatKey and tostring(nextKey or "") ~= "" and tostring(state.lastPushKey or "") == tostring(nextKey) then
        return false
    end
    if minimumSeconds > 0 and (now - (tonumber(state.lastPushAt) or 0)) < minimumSeconds then
        return false
    end
    return (currentRace - (tonumber(state.lastPushRace) or -99)) >= (tonumber(minRaceGap) or 3)
end

local function pick(messages)
    if type(messages) ~= "table" or #messages == 0 then
        return nil
    end
    return tostring(messages[math.random(1, #messages)])
end

local function buildSignatureMessage(summary, context)
    local startPos = tonumber(summary.startPos or 0) or 0
    local finishPos = tonumber(summary.position or 0) or 0
    local delta = startPos > 0 and (startPos - finishPos) or 0
    local clean = summary.clean == true
    local record = context.record == true
    local promoted = context.promoted == true
    local won = finishPos == 1
    local podium = finishPos > 0 and finishPos <= 3
    local fieldSize = tonumber(summary.fieldSize or 0) or 0
    local bigRecovery = delta >= 5
    local solidRecovery = delta >= 3
    local fromBack = fieldSize >= 6 and startPos >= math.max(4, math.floor(fieldSize * 0.6))
    local telemetry = context.telemetry or {}
    local overtakes = tonumber(telemetry.overtakes or 0) or 0
    local lapOneGain = tonumber(telemetry.lapOneGain or 0) or 0
    local crashRecoveries = tonumber(telemetry.recoveries or 0) or 0
    local collisions = tonumber(telemetry.collisions or 0) or 0

    if podium and overtakes >= 6 and clean then
        return pick({
            i18n.format("YOU DID NOT just pull off %d clean passes in one race. I need that replay again.", overtakes),
            i18n.format("They kept sitting in front of you and you kept deleting them. %d clean passes. Unreal.", overtakes),
            i18n.format("%d overtakes and it never even got messy. That's the kind of run people clip instantly.", overtakes),
        })
    end
    if podium and crashRecoveries >= 1 then
        return pick({
            "They hit you and you still took the race back. I can't stop thinking about that.",
            i18n.format("You ate %d big hit%s and still dragged it back to the front half of the story. That's the clip.", collisions, collisions == 1 and "" or "s"),
            "That should have ruined your night and somehow it just turned into your race instead.",
        })
    end
    if podium and lapOneGain >= 3 then
        return pick({
            i18n.format("That launch cracked the whole race open. %d spots in lap one before they even got settled.", lapOneGain),
            i18n.format("%d places on lap one. They were still finding the race and you were already changing it.", lapOneGain),
            i18n.format("You took %d spots right away and the whole field had to start reacting to you.", lapOneGain),
        })
    end

    if won and bigRecovery and clean then
        return pick({
            i18n.format("Started P%d and still won it clean. That's the kind of race people bring up twice.", startPos),
            i18n.format("P%d to P1 with no garbage on it. They had you buried and you still took the whole thing.", startPos),
            i18n.format("They gave you P%d and you turned it into a clean win. I know people are replaying that already.", startPos),
        })
    end
    if won and record then
        return pick({
            "You won and set a mark. That's not just a result. That's people checking the board again.",
            "Win plus a new best? Yeah. That one is going to hang around.",
            "You took the win and left a number behind. People notice that stuff fast.",
        })
    end
    if won and promoted then
        return pick({
            i18n.format("You won and punched straight into %s. Tell me that doesn't feel different now.", tostring(context.newTier or "the next tier")),
            "That win moved you up. They're going to have to talk about you like you belong there now.",
            "You didn't just win. You crossed over.",
        })
    end
    if won and fromBack then
        return pick({
            i18n.format("P%d to P1? They really thought the back half of the grid was going to hold you there?", startPos),
            i18n.format("Deep-grid win. P%d to P1 is the kind of thing people keep sending around all night.", startPos),
            i18n.format("They lined you up P%d and you turned that into a win. That's disrespectful in the best way.", startPos),
        })
    end
    if podium and bigRecovery then
        return pick({
            i18n.format("Started P%d, finished P%d, and somehow made the whole race swing back toward you.", startPos, finishPos),
            i18n.format("That comeback was real. P%d to P%d and you just kept pulling the door back open.", startPos, finishPos),
            i18n.format("They had you buried early and you still dragged it back to P%d. I know people noticed that.", finishPos),
        })
    end
    if podium and clean then
        return pick({
            "That was clean. Like CLEAN clean. No waste, no panic, no free mistakes anywhere.",
            i18n.format("P%d and tidy the whole way. That's the kind of run people trust when they start paying attention.", finishPos),
            "Nothing flashy wasted, nothing thrown away. Just a clean result with your name all over it.",
        })
    end
    if solidRecovery and clean then
        return pick({
            i18n.format("P%d to P%d and clean the whole way. You really do not stay where they leave you.", startPos, finishPos),
            i18n.format("You hauled that back from P%d to P%d without ever tossing the race away. That's the part I love.", startPos, finishPos),
            i18n.format("Clean recovery from P%d to P%d. You kept finding space without losing your head.", startPos, finishPos),
        })
    end
    if solidRecovery then
        return pick({
            i18n.format("That was work. P%d to P%d when the race stopped giving you anything for free.", startPos, finishPos),
            i18n.format("You always seem to come alive late. P%d to P%d again. That's becoming a thing.", startPos, finishPos),
            i18n.format("They started closing doors and you still found your way from P%d to P%d.", startPos, finishPos),
        })
    end
    if record then
        return pick({
            "You left a number behind there. Not just a finish. A number people are going to look at twice.",
            "That run stuck. Times like that don't just disappear once the race is over.",
            "You put something real on the board there. People remember that stuff.",
        })
    end
    return nil
end

local function buildMilestoneMessage(career, summary, context)
    local state = career and career.fanState or {}
    local stats = MTE and MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
    local sent = state.sentMilestones or {}

    if context.cleanStreak and context.cleanStreak >= 3 then
        local threshold, key = firstThresholdHit(context.cleanStreak, CLEAN_STREAK_MILESTONES, sent, "clean_streak")
        if threshold then
            markMilestone(state, key)
            return pick({
                i18n.format("%d straight clean runs. That's not luck hanging around. That's discipline.", threshold),
                i18n.format("That's %d clean ones in a row. People notice when you stop giving races away.", threshold),
            }), key
        end
    end

    if context.prestige and context.prestige.dir == "up" then
        local key = i18n.format("tier_up:%s", tostring(context.prestige.to or "?"))
        if not sent[key] then
            markMilestone(state, key)
            return pick({
                i18n.format("%s now. That's a real step up.", tostring(context.prestige.to or "Up a tier")),
                i18n.format("You climbed into %s. Different room now, and you earned it.", tostring(context.prestige.to or "the next tier")),
            }), key
        end
    end

    local threshold, key = firstThresholdHit(stats.wins, WIN_MILESTONES, sent, "wins")
    if threshold then
        markMilestone(state, key)
        if threshold == 1 then
            return "First win. There it is. You're not chasing one anymore.", key
        end
        return pick({
            i18n.format("%d wins now. This is real.", threshold),
            i18n.format("Win number %d. That's when people stop acting surprised.", threshold),
        }), key
    end

    threshold, key = firstThresholdHit(stats.podiums, PODIUM_MILESTONES, sent, "podiums")
    if threshold then
        markMilestone(state, key)
        return pick({
            i18n.format("%d podiums already. Yeah, people are tracking that now.", threshold),
            i18n.format("Podium number %d. That's how a driver becomes a regular problem.", threshold),
        }), key
    end

    threshold, key = firstThresholdHit(stats.racesFinished, RACE_MILESTONES, sent, "races")
    if threshold then
        markMilestone(state, key)
        return pick({
            i18n.format("%d races in. This is a real file now, not a one-night story.", threshold),
            i18n.format("That's %d finishes. You're established enough that people have receipts.", threshold),
        }), key
    end

    threshold, key = firstThresholdHit(stats.eddiesEarned, EDDIES_MILESTONES, sent, "eddies")
    if threshold then
        markMilestone(state, key)
        return pick({
            i18n.format("%s banked. That's not side-money anymore.", formatEddies(threshold)),
            i18n.format("You crossed %s earned. That's the kind of total people notice.", formatEddies(threshold)),
        }), key
    end

    threshold, key = firstThresholdHit(stats.winStreak, WIN_STREAK_MILESTONES, sent, "win_streak")
    if threshold then
        markMilestone(state, key)
        return pick({
            i18n.format("%d straight. That's a heater, not a coincidence.", threshold),
            i18n.format("A %d-race heater will make the next grid nervous.", threshold),
        }), key
    end

    return nil, nil
end

local function buildIdentityMessage(career)
    local recent = recentRaces(career, 5)
    local telemetry = recentTelemetrySessions(career, 5)
    if #recent < 4 then
        return nil, nil
    end

    local cleanTopRuns = 0
    local totalDelta = 0
    local deltaCount = 0
    local messyRuns = 0
    local strongFinishes = 0
    local highOvertakeRuns = 0
    local recoveryRuns = 0
    local collisionHeavyRuns = 0
    local routeBestRuns = 0
    local gaveItAwayRuns = 0

    for _, summary in ipairs(recent) do
        local finishPos = tonumber(summary.position or 99) or 99
        local startPos = tonumber(summary.startPos or 0) or 0
        if summary.clean == true and finishPos <= 5 then
            cleanTopRuns = cleanTopRuns + 1
        end
        if startPos > 0 and finishPos < 99 then
            totalDelta = totalDelta + (startPos - finishPos)
            deltaCount = deltaCount + 1
        end
        if summary.clean ~= true then
            messyRuns = messyRuns + 1
        end
        if finishPos <= 3 then
            strongFinishes = strongFinishes + 1
        end
        if startPos > 0 and finishPos > (startPos + 1) then
            gaveItAwayRuns = gaveItAwayRuns + 1
        end
    end

    for _, session in ipairs(telemetry) do
        local signals = telemetrySignals(session)
        if signals.overtakes >= 4 then
            highOvertakeRuns = highOvertakeRuns + 1
        end
        if signals.recoveries >= 1 then
            recoveryRuns = recoveryRuns + 1
        end
        if signals.collisions >= 2 or signals.crashHeavy then
            collisionHeavyRuns = collisionHeavyRuns + 1
        end
        if signals.routeBest then
            routeBestRuns = routeBestRuns + 1
        end
    end

    local avgDelta = deltaCount > 0 and (totalDelta / deltaCount) or 0
    if cleanTopRuns >= 3 then
        return pick({
            "I've been watching how you race when it tightens up. You don't panic. You get cleaner.",
            "You race like mistakes are for other people. That's why you keep climbing.",
        }), "identity:clean_operator"
    end
    if routeBestRuns >= 2 then
        return pick({
            "You don't just want the finish. You want the number that stays after.",
            "I've noticed you keep chasing the mark, not just the flag.",
        }), "identity:marker_chaser"
    end
    if recoveryRuns >= 2 then
        return pick({
            "I've noticed this thing you do. The race goes wrong and somehow that's when you wake up.",
            "You keep writing yourself back into races after the bad moment. Not everyone can do that.",
        }), "identity:recovery_artist"
    end
    if highOvertakeRuns >= 3 and strongFinishes >= 2 then
        return pick({
            "You don't sit behind people for long. You start taking them out of the picture.",
            "When you smell space, you go. That's why your races never stay quiet.",
        }), "identity:relentless_hunter"
    end
    if avgDelta >= 2.0 and strongFinishes >= 2 then
        return pick({
            "You always come alive late. It's like you need the race to wear itself out first.",
            "You don't need the perfect start. You just need enough laps to start hunting.",
        }), "identity:late_mover"
    end
    if collisionHeavyRuns >= 3 and strongFinishes >= 2 then
        return pick({
            "You make ugly races look survivable. I still don't know if that's discipline or madness.",
            "There's a wild streak in you. Somehow it keeps cashing results.",
        }), "identity:wild_thing"
    end
    if gaveItAwayRuns >= 2 and collisionHeavyRuns >= 2 then
        return pick({
            "I've noticed you can get the race in your hands and then shake it loose.",
            "The pace is there. The next version of you just keeps it calmer at the end.",
        }), "identity:needs_composure"
    end
    if messyRuns >= 3 then
        return pick({
            "You're fast enough already. I just want to see fewer good races end in a mess.",
            "You'd scare people even more if you stopped donating clean results to dirty endings.",
        }), "identity:needs_cleaner_finishes"
    end
    return nil, nil
end

local function buildPullFallback(career)
    local stats = MTE and MTE.Careers and MTE.Careers.getStats and MTE.Careers.getStats(career) or career.stats or {}
    local pos, pts = champPosition(career)
    local recent = recentRaces(career, 3)
    local last = recent[1] or {}
    local lastSession = telemetrySession(last and last.sessionId)
    local lastSignals = telemetrySignals(lastSession)
    local lastPos = tonumber(last.position or 0) or 0
    local lastStart = tonumber(last.startPos or 0) or 0
    local delta = lastStart > 0 and (lastStart - lastPos) or 0
    local wins = tonumber(stats.wins or 0) or 0
    local podiums = tonumber(stats.podiums or 0) or 0
    local finished = tonumber(stats.racesFinished or 0) or 0
    local streak = tonumber(stats.winStreak or 0) or 0

    local buckets = {}
    local generalBucket = {
        "I knew you were interesting before it was obvious.",
        "You keep giving me new evidence.",
        "Every time I think I have your file straight, you add another line.",
        "This is way past the point where people can call it a lucky run.",
        "You keep giving the city fresh reasons to talk.",
        "I've been here since the start, and you keep making me look right.",
    }

    local function addBucket(options, enabled)
        if enabled == false then
            return
        end
        local clean = {}
        for _, message in ipairs(options or {}) do
            if type(message) == "string" and message ~= "" then
                clean[#clean + 1] = message
            end
        end
        if #clean > 0 then
            buckets[#buckets + 1] = clean
        end
    end

    addBucket({
        i18n.format("%d podiums already. That's how the crowd learns your name.", podiums),
        i18n.format("%d podiums in the file now. People are starting to expect you near the front.", podiums),
        i18n.format("You keep landing on podiums. %d already, and that sticks.", podiums),
    }, podiums > 0)

    addBucket({
        i18n.format("%d wins now. People love acting like they saw it coming.", wins),
        i18n.format("The win column says %d now. That's a serious number.", wins),
        i18n.format("%d wins in the books. That's not fake hype anymore.", wins),
    }, wins > 0)

    addBucket({
        i18n.format("%s banked. That's not hobby money.", formatEddies(stats.eddiesEarned or 0)),
        i18n.format("You're up to %s now. People notice totals like that.", formatEddies(stats.eddiesEarned or 0)),
        i18n.format("%s earned and climbing. That kind of purse total gets attention.", formatEddies(stats.eddiesEarned or 0)),
    })

    addBucket({
        i18n.format("P%d on %d points. I know people are checking that table twice.", tonumber(pos or 0), tonumber(pts or 0)),
        i18n.format("P%d with %d points. That's the kind of line that changes how people talk.", tonumber(pos or 0), tonumber(pts or 0)),
        i18n.format("They keep opening the standings and finding you at P%d on %d. That's pressure.", tonumber(pos or 0), tonumber(pts or 0)),
    }, pos ~= nil)

    addBucket({
        i18n.format("That %d-race heater is making every next grid look tighter.", streak),
        i18n.format("%d straight. That's when people stop calling it a run and start calling it a problem.", streak),
        i18n.format("You're on a %d-race heater and everybody knows it.", streak),
    }, streak >= 2)

    addBucket({
        i18n.format("That last one from P%d to P%d is still stuck in my head.", lastStart, lastPos),
        i18n.format("P%d to P%d again. You really do not stay where they put you.", lastStart, lastPos),
        i18n.format("They lined you up P%d and you still dragged it back to P%d. That's your thing now.", lastStart, lastPos),
    }, delta >= 3)

    addBucket({
        "That last run was clean clean. You make tidy races look mean.",
        "Clean result last time out. That's how trust starts building around a driver.",
        "No waste in that last one. Just a clean result with your name all over it.",
    }, last.clean == true and lastPos > 0 and lastPos <= 5)

    addBucket({
        i18n.format("%d overtakes last time out. You were taking cars off the screen.", lastSignals.overtakes),
        i18n.format("You made %d real passes in the last one. That's dangerous lately behavior.", lastSignals.overtakes),
        i18n.format("%d overtakes in the last run. You were not there to sit in line.", lastSignals.overtakes),
    }, lastSignals.overtakes >= 4)

    addBucket({
        "You got tagged and still came back. That's why I never count you out.",
        "Bad moment, strong finish. You keep surviving the part that ends other people's nights.",
        "That recovery is still all over my head. You got hit and still made the race yours again.",
    }, lastSignals.recoveries >= 1)

    addBucket({
        "Messy race, strong finish. You keep coming out of ugly nights looking harder to deal with.",
        "Even when the race gets rough, you still leave with something worth talking about.",
        "That one got dirty and somehow it still made you look dangerous.",
    }, lastSignals.collisions >= 2 and lastPos > 0 and lastPos <= 5)

    addBucket({
        i18n.format("%d finishes in and your file is starting to look thick.", finished),
        i18n.format("%d classified runs now. This is not a phase.", finished),
        i18n.format("You're %d finishes deep now. People have enough tape on you to start worrying.", finished),
    }, finished >= 5)

    if #buckets == 0 then
        return pick(generalBucket) or "I've been here since the start. You keep giving me reasons to stay loud."
    end

    local available = buckets
    if math.random() <= 0.2 then
        available = {}
        for _, bucket in ipairs(buckets) do
            available[#available + 1] = bucket
        end
        available[#available + 1] = generalBucket
    end

    local bucket = available[math.random(1, #available)]
    return pick(bucket) or pick(generalBucket) or "I've been here since the start. You keep giving me reasons to stay loud."
end

function FanEngine.init()
    local changed = false
    local careers = MTE and MTE.Careers and MTE.Careers.all or {}
    for _, career in pairs(careers or {}) do
        local _, wasChanged = ensureState(career)
        if wasChanged then
            changed = true
        end
    end
    if changed then
        saveCareers()
    end
end

function FanEngine.pullText(career)
    local active = career or activeCareer()
    if not active then
        return "Pick a career and I'll start the fan club myself!"
    end

    local state = ensureState(active)
    if state.lastPushText ~= "" then
        local currentRace = tonumber(active.stats and active.stats.racesFinished or 0) or 0
        if currentRace - (tonumber(state.lastPushRace) or -99) <= 2 and state.lastPullMode ~= state.lastPushKey then
            state.lastPullMode = state.lastPushKey
            saveCareers()
            return state.lastPushText
        end
    end

    state.lastPullMode = "fallback"
    saveCareers()
    return buildPullFallback(active)
end

function FanEngine.onNewRecord(career, data)
    local active = career or activeCareer()
    if not active then
        return nil
    end
    local state = ensureState(active)
    state.pending.newRecord = {
        routeKey = tostring(data and data.routeKey or ""),
        time = tonumber(data and data.time or 0) or 0,
        at = tonumber(os.time() or 0) or 0,
    }
    saveCareers()
    return nil
end

function FanEngine.onCatchUpBonus(career, data)
    local active = career or activeCareer()
    if not active then
        return nil
    end
    local state = ensureState(active)
    state.pending.catchUp = {
        amount = tonumber(data and data.amount or 0) or 0,
        streak = tonumber(data and data.streak or 0) or 0,
        at = tonumber(os.time() or 0) or 0,
    }
    saveCareers()
    return nil
end

function FanEngine.onCleanRun(career, data)
    local active = career or activeCareer()
    if not active then
        return nil
    end
    local state = ensureState(active)
    local payload = type(data) == "table" and (data.data or data) or {}
    state.pending.cleanRun = {
        streak = tonumber(payload and payload.streak or 0) or 0,
        at = tonumber(os.time() or 0) or 0,
    }
    saveCareers()
    return nil
end

function FanEngine.onPrestigeChange(career, data)
    local active = career or activeCareer()
    if not active then
        return nil
    end
    local state = ensureState(active)
    state.pending.prestigeChange = {
        dir = tostring(data and data.dir or ""),
        from = tostring(data and data.from or ""),
        to = tostring(data and data.to or ""),
        at = tonumber(os.time() or 0) or 0,
    }
    saveCareers()
    return nil
end

function FanEngine.onRaceFinished(career, data)
    local active = career or activeCareer()
    if not active then
        return nil
    end

    local state = ensureState(active)
    local summary = type(active.raceHistory) == "table" and active.raceHistory[1] or nil
    if type(summary) ~= "table" then
        return nil
    end

    local currentSessionId = tostring(data and data.sessionId or summary.sessionId or "")
    local raceKey = buildRaceDispatchKey(active, summary, data)
    if currentSessionId ~= "" and tostring(state.lastProcessedSessionId or "") == currentSessionId then
        return nil
    end
    if raceKey ~= "" and tostring(state.lastProcessedRaceKey or "") == raceKey then
        return nil
    end

    local champPos = champPosition(active)
    local previousChampPos = tonumber(state.lastChampPos or 0) or 0
    local champGain = (previousChampPos > 0 and champPos and champPos > 0) and (previousChampPos - champPos) or 0
    local recordPending = type(state.pending.newRecord) == "table" and state.pending.newRecord or nil
    local prestigePending = type(state.pending.prestigeChange) == "table" and state.pending.prestigeChange or nil
    local cleanPending = type(state.pending.cleanRun) == "table" and state.pending.cleanRun or nil
    local catchUpPending = type(state.pending.catchUp) == "table" and state.pending.catchUp or nil

    local finishPos = tonumber(summary.position or 99) or 99
    local startPos = tonumber(summary.startPos or 0) or 0
    local delta = startPos > 0 and (startPos - finishPos) or 0
    local fieldSize = tonumber(summary.fieldSize or (type(data and data.results) == "table" and #data.results or 0) or 0) or 0
    local session = telemetrySession(currentSessionId) or (MTE and MTE.RaceTelemetry and MTE.RaceTelemetry.getLastCompletedSession and MTE.RaceTelemetry.getLastCompletedSession()) or nil
    local telemetry = telemetrySignals(session)
    local context = {
        record = recordPending ~= nil,
        promoted = prestigePending and prestigePending.dir == "up" or false,
        prestige = prestigePending,
        newTier = prestigePending and prestigePending.to or nil,
        cleanStreak = cleanPending and tonumber(cleanPending.streak or 0) or 0,
        champGain = champGain,
        catchUp = catchUpPending,
        telemetry = telemetry,
    }

    local score = 0
    if finishPos == 1 then score = score + 4 end
    if finishPos <= 3 then score = score + 2 end
    if summary.clean == true and finishPos <= 5 then score = score + 2 end
    if delta >= 5 then score = score + 3 elseif delta >= 3 then score = score + 2 end
    if recordPending then score = score + 2 end
    if context.promoted then score = score + 2 end
    if champGain >= 2 then score = score + 2 elseif champGain == 1 then score = score + 1 end
    if catchUpPending and finishPos <= math.max(3, math.ceil(fieldSize / 2)) then score = score + 1 end
    if telemetry.overtakes >= 6 then score = score + 2 elseif telemetry.overtakes >= 4 then score = score + 1 end
    if telemetry.lapOneGain >= 3 then score = score + 1 end
    if telemetry.recoveries >= 1 then score = score + 2 end
    if telemetry.collisions >= 2 and finishPos <= 5 then score = score + 1 end
    if telemetry.routeBest then score = score + 1 end

    local signatureMessage = nil
    local signatureKey = raceKey ~= "" and ("signature:" .. raceKey) or (currentSessionId ~= "" and ("signature:" .. currentSessionId) or "signature")
    if score >= 5 and canPush(active, state, 3, false, signatureKey) then
        signatureMessage = buildSignatureMessage(summary, context)
    end
    if signatureMessage and signatureMessage ~= "" then
        state.lastProcessedSessionId = currentSessionId
        state.lastProcessedRaceKey = raceKey
        state.lastChampPos = tonumber(champPos or 0) or 0
        state.pending.newRecord = nil
        state.pending.catchUp = nil
        state.pending.cleanRun = nil
        state.pending.prestigeChange = nil
        return commitPush(active, state, "signature", signatureKey, signatureMessage)
    end

    local milestoneMessage, milestoneKey = buildMilestoneMessage(active, summary, context)
    if milestoneMessage and canPush(active, state, 2, false, milestoneKey or "milestone") then
        state.lastProcessedSessionId = currentSessionId
        state.lastProcessedRaceKey = raceKey
        state.lastChampPos = tonumber(champPos or 0) or 0
        state.pending.newRecord = nil
        state.pending.catchUp = nil
        state.pending.cleanRun = nil
        state.pending.prestigeChange = nil
        return commitPush(active, state, "milestone", milestoneKey or "milestone", milestoneMessage)
    end

    local identityMessage, identityKey = buildIdentityMessage(active)
    if identityMessage and canPush(active, state, 4, false, identityKey or "identity") then
        state.lastProcessedSessionId = currentSessionId
        state.lastProcessedRaceKey = raceKey
        state.lastChampPos = tonumber(champPos or 0) or 0
        state.pending.newRecord = nil
        state.pending.catchUp = nil
        state.pending.cleanRun = nil
        state.pending.prestigeChange = nil
        return commitPush(active, state, "identity", identityKey or "identity", identityMessage)
    end

    state.lastProcessedSessionId = currentSessionId
    state.lastProcessedRaceKey = raceKey
    state.lastChampPos = tonumber(champPos or 0) or 0
    state.pending.newRecord = nil
    state.pending.catchUp = nil
    state.pending.cleanRun = nil
    state.pending.prestigeChange = nil
    saveCareers()
    return nil
end

return FanEngine


