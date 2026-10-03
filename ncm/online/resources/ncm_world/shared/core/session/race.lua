-- ncm-core module: session.race
-- The race session state machine (M3.2; L19 automated race control, L23 events contain sessions,
-- L20 consequences ruleset-expressed). Pure: the host feeds timestamped facts (clock ticks, gate
-- reports with authoritative positions, presence, departures) and gets back the new state plus a
-- list of events to announce. Nothing here reads the game or the clock.
--
-- Phases:  forming -> gridded -> countdown -> running -> finishing -> complete
--   forming    session exists; entrants may arrive at their marks
--   gridded    grid check done (T-gridHold): absent entrants are DNS
--   countdown  lights (one per second) until green
--   running    green; crossings count
--   finishing  first finisher crossed; window open for the rest
--   complete   classification final
local Core = NcmCore

Core.define("session.race", function(C)
    local M = { version = "0.0.1" }
    local gates = C.get("course.gates")

    M.DEFAULT_RULES = {
        gridHoldBeforeSec = 30,   -- entrants must be at their mark by T-30
        countdownSec = 5,         -- five lights, one per second, green at T-0
        jumpPenaltySec = 5,       -- crossing the start line before green
        finishWindowSec = 60,     -- after the first finisher
        maxRaceSec = 15 * 60,     -- hard stop if nobody finishes
        reconnectGraceSec = 180,  -- a dropped driver may come back within this and resume (L20). A real rejoin (menu -> load -> world) takes 1-2 min; the finish window still bounds the race.
        startTimeoutSec = 90,     -- nobody has crossed the start this long after green -> everyone DNS, session over
        hold = false,             -- holding stage (organized events, TW1): lights wait for the field, see step()
        holdReleasePct = 0.75,    -- ... until this fraction of the field is at its mark ...
        holdMaxWaitSec = 60,      -- ... or this long past the scheduled start, whichever first
        incidents = nil,          -- competition.incidents rule overrides (bands, baseSec, escalation); nil = defaults
        -- Rolling start (Batch 2, owner ask): the lights release the field to roll out in grid order behind the pole
        -- car under a pace cap; the race clock and free racing begin when the LEADER crosses the `green` gate the
        -- host places `formationM` along the course. Faults are incident bands, never restarts (L56/P39).
        start = "standing",       -- "standing" | "rolling"
        formationM = 300,         -- where the green gate goes (host geometry) when start == "rolling"
        paceKph = 80,             -- formation speed cap; over cap * 1.1 = one formation_speed incident per driver
        formationBand = 1,        -- band for formation faults (passing before green, over the cap)
        formationSec = 2,         -- seconds a band-1 formation fault costs (mult 2^(band-1))
    }

    local recompute   -- defined below; report/pace above reference it as an upvalue

    local function copyRules(r)
        local out = {}
        for k, v in pairs(M.DEFAULT_RULES) do out[k] = v end
        for k, v in pairs(r or {}) do out[k] = v end
        return out
    end

    --- Create a session. spec = { sessionId, eventId, startsAt, gates = {...}, entrants = { {driverId, entryId, slot, display} }, rules }
    function M.new(spec)
        if type(spec) ~= "table" then error("session.race.new: spec required") end
        if type(spec.gates) ~= "table" or #spec.gates < 2 then error("session.race.new: gates (start..finish) required") end
        local s = {
            sessionId = spec.sessionId, eventId = spec.eventId, startsAt = spec.startsAt,
            rules = copyRules(spec.rules), gates = spec.gates,
            phase = "forming", greenAt = nil, firstFinishAt = nil, completedAt = nil,
            lightsShown = 0, gridChecked = false,
            originalStartsAt = spec.startsAt, hold = nil,   -- hold = { ready, total, deadline } while holding
            entrants = {},    -- driverId -> record
            order = {},       -- driverIds in slot order
        }
        for _, e in ipairs(spec.entrants or {}) do
            s.entrants[e.driverId] = {
                driverId = e.driverId, entryId = e.entryId, slot = e.slot, display = e.display,
                teamId = e.teamId, seatIndex = e.seatIndex,
                state = "entered",     -- entered | ready | dns | racing | suspended | finished | dnf
                atMark = false, progress = 0, crossings = {}, penaltySec = 0,
                jumpStart = false, finishAt = nil, totalSec = nil, dnfReason = nil, lastCrossingAt = nil,
                suspendedAt = nil,
                incidentSec = 0, incidentCount = 0, incidents = {}, correctedSec = nil,   -- L56 zero-fault incidents
            }
            s.order[#s.order + 1] = e.driverId
        end
        table.sort(s.order, function(a, b) return (s.entrants[a].slot or 0) < (s.entrants[b].slot or 0) end)
        return s
    end

    local function ev(list, type_, fields)
        local e = { type = type_ }
        for k, v in pairs(fields or {}) do e[k] = v end
        list[#list + 1] = e
        return e
    end

    local function activeCount(s)
        local n = 0
        for _, r in pairs(s.entrants) do if r.state == "racing" or r.state == "suspended" then n = n + 1 end end
        return n
    end

    --- A racing entrant dropped (disconnect). They keep their progress for reconnectGraceSec.
    function M.suspend(s, driverId, now, reason)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        if r.state ~= "racing" then return nil, "not_racing" end
        if s.phase ~= "running" and s.phase ~= "finishing" then return nil, "not_running" end
        r.state = "suspended"; r.suspendedAt = now; r.dnfReason = reason or "disconnected"
        local events = {}
        ev(events, "suspended", { driverId = driverId, reason = r.dnfReason, until_ = now + s.rules.reconnectGraceSec })
        return events
    end

    --- The dropped entrant is back. Progress and penalties are untouched; the clock never stopped.
    function M.resume(s, driverId, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        if r.state ~= "suspended" then return nil, "not_suspended" end
        r.state = "racing"; r.suspendedAt = nil; r.dnfReason = nil
        local events = {}
        ev(events, "resumed", { driverId = driverId, at = now, progress = r.progress })
        return events
    end

    --- Presence at the mark (host reads authoritative positions and calls this while forming).
    function M.mark(s, driverId, atMark)
        local r = s.entrants[driverId]
        if not r then return false, "unknown_entrant" end
        -- DNS is decided at green (L288/L289; owner 2026-10-02: one rule for every race). A driver who reaches their
        -- mark during the lights starts: they join the racers the countdown already released. Leaving the mark in the
        -- countdown changes nothing -- small corrections are allowed until green.
        if s.phase == "countdown" then
            if atMark and r.state == "entered" then r.atMark = true; r.state = "racing" end
            return true
        end
        if s.phase ~= "forming" and s.phase ~= "gridded" then return false, "not_forming" end
        r.atMark = atMark and true or false
        if r.state == "entered" or r.state == "ready" then r.state = r.atMark and "ready" or "entered" end
        return true
    end

    --- The race's flag (a mixed Paddock race: the Paddock decides it from the first car of the WHOLE field home). At
    --- `at` the session completes; whoever has not finished is classified by progress. Earlier calls are replaced.
    function M.flag(s, at)
        if type(at) ~= "number" or s.phase == "complete" then return false end
        s.flagAt = at
        return true
    end

    --- An entrant left (disconnect, withdrew). DNS before green, DNF after.
    function M.leave(s, driverId, now, reason)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        if r.state == "finished" or r.state == "dnf" or r.state == "dns" then return nil, "already_classified" end
        local events = {}
        if s.phase == "running" or s.phase == "finishing" then
            r.state = "dnf"; r.dnfReason = reason or "left"
            ev(events, "dnf", { driverId = driverId, reason = r.dnfReason })
        else
            r.state = "dns"; r.dnfReason = reason or "left"
            ev(events, "dns", { driverId = driverId, reason = r.dnfReason })
        end
        return events
    end

    --- A gate report. req = { driverId, gateIndex, now, position (authoritative, optional) }
    --- Returns { ok = true, gate, finished?, penalty? } or { ok = false, reason }.
    function M.report(s, req)
        local r = s.entrants[req.driverId]
        if not r then return { ok = false, reason = "unknown_entrant" } end
        local g = s.gates[req.gateIndex or 0]
        if not g then return { ok = false, reason = "unknown_gate" } end
        if r.state ~= "racing" and r.state ~= "ready" and r.state ~= "entered" then
            return { ok = false, reason = "not_racing", state = r.state }
        end
        if req.gateIndex ~= r.progress + 1 then
            return { ok = false, reason = "out_of_order", expected = r.progress + 1 }
        end
        -- Fail closed: a report without an authoritative position is refused, never waved through.
        if type(req.position) ~= "table" then return { ok = false, reason = "position_unknown" } end
        local near, why, d = gates.nearGate(g, req.position)
        if not near then return { ok = false, reason = why, distanceM = d } end
        local penalty = false
        if g.kind == "start" then
            if s.phase == "countdown" then
                r.jumpStart = true
                r.penaltySec = r.penaltySec + s.rules.jumpPenaltySec
                penalty = true
            elseif s.phase ~= "running" and s.phase ~= "finishing" then
                return { ok = false, reason = "not_started" }
            end
        elseif s.phase ~= "running" and s.phase ~= "finishing" then
            return { ok = false, reason = "not_started" }
        end
        r.progress = req.gateIndex
        r.crossings[req.gateIndex] = req.now
        r.lastCrossingAt = req.now
        local rollingGreen, fault = nil, nil
        if g.kind == "green" then
            -- the first car to the green gate is the leader: the flag drops and the race clock starts here
            if not s.rollingGreenAt then
                s.rollingGreenAt = req.now; s.greenAt = req.now; s.rollingLeader = req.driverId
                rollingGreen = { leader = req.driverId, at = req.now }
            end
            -- order fault: anyone who started ahead of me (lower slot) and has not reached the green yet was passed
            for _, id in ipairs(s.order) do
                local o = s.entrants[id]
                if o ~= r and (o.state == "racing") and (o.slot or 0) < (r.slot or 0) and not o.crossings[req.gateIndex] then fault = "passed_before_green"; break end
            end
            if fault and not r.formationFault then
                r.formationFault = fault
                local seconds = s.rules.formationSec * (2 ^ (s.rules.formationBand - 1))
                r.incidentSec = r.incidentSec + seconds; r.incidentCount = r.incidentCount + 1
                r.incidents[#r.incidents + 1] = { kind = "formation", band = s.rules.formationBand, seconds = seconds, at = req.now, detail = fault }
                recompute(r, s)
            else
                fault = nil
            end
        end
        local finished = false
        if g.kind == "finish" then
            r.state = "finished"
            r.finishAt = req.now
            r.totalSec = (req.now - (s.greenAt or req.now)) + r.penaltySec
            r.correctedSec = r.totalSec + r.incidentSec
            finished = true
            if not s.firstFinishAt then s.firstFinishAt = req.now end
        end
        return { ok = true, gate = g, finished = finished, penalty = penalty, totalSec = r.totalSec, rollingGreen = rollingGreen, formationFault = fault,
                 formationSec = fault and r.incidents[#r.incidents].seconds or nil, incidentSec = r.incidentSec, incidentCount = r.incidentCount }
    end

    --- Rolling start: a speed sample during the formation (running, before the leader's green). Over the cap (with
    --- 10 % slack) is one formation_speed incident per driver. Returns events (possibly empty).
    function M.pace(s, driverId, speedMps, now)
        local events = {}
        local r = s.entrants[driverId]
        if not r or s.rules.start ~= "rolling" or s.phase ~= "running" or s.rollingGreenAt then return events end
        local cap = (s.rules.paceKph / 3.6) * 1.1
        if (tonumber(speedMps) or 0) > cap and not r.formationSpeedFault then
            r.formationSpeedFault = true
            local seconds = s.rules.formationSec * (2 ^ (s.rules.formationBand - 1))
            r.incidentSec = r.incidentSec + seconds; r.incidentCount = r.incidentCount + 1
            r.incidents[#r.incidents + 1] = { kind = "formation", band = s.rules.formationBand, seconds = seconds, at = now, detail = "over_pace" }
            recompute(r, s)
            ev(events, "incident", { driverId = driverId, kind = "formation_speed", band = s.rules.formationBand, seconds = seconds, incidentSec = r.incidentSec, count = r.incidentCount })
        end
        return events
    end

    --- Classification. Finished by total time; then unfinished by progress desc, last crossing asc;
    --- DNS last. Returns an array of { position, driverId, entryId, display, state, totalSec, penaltySec, progress, gapSec }.
    function M.classify(s)
        local list = {}
        for _, id in ipairs(s.order) do list[#list + 1] = s.entrants[id] end
        local rank = { finished = 1, racing = 2, suspended = 2, dnf = 2, ready = 3, entered = 3, dns = 4, dsq = 5 }
        table.sort(list, function(a, b)
            local ra, rb = rank[a.state] or 5, rank[b.state] or 5
            if ra ~= rb then return ra < rb end
            if a.state == "finished" then
                local ca, cb = a.correctedSec or a.totalSec, b.correctedSec or b.totalSec
                if ca ~= cb then return ca < cb end
            else
                if a.progress ~= b.progress then return a.progress > b.progress end
                local la, lb = a.lastCrossingAt or math.huge, b.lastCrossingAt or math.huge
                if la ~= lb then return la < lb end
            end
            return (a.slot or 0) < (b.slot or 0)
        end)
        local out, leader = {}, nil
        for i, r in ipairs(list) do
            if r.state == "finished" and not leader then leader = r end
            out[i] = {
                position = i, driverId = r.driverId, entryId = r.entryId, display = r.display,
                state = r.state, totalSec = r.totalSec, penaltySec = r.penaltySec, jumpStart = r.jumpStart,
                -- **The finish INSTANT, not just the duration** (L166). `totalSec` already folds in the penalty,
                -- so a caller that needs to locate this lap in time cannot recover the moment it ended by
                -- subtracting. A stored ghost needs the interval, and `greenAt` alone is only half of it.
                finishAt = r.finishAt,
                progress = r.progress, gatesTotal = #s.gates, teamId = r.teamId, seatIndex = r.seatIndex,
                penalties = r.penalties,
                incidentSec = r.incidentSec, incidentCount = r.incidentCount, incidents = r.incidents,
                correctedSec = r.correctedSec,
                gapSec = (r.state == "finished" and leader and r ~= leader) and ((r.correctedSec or r.totalSec) - (leader.correctedSec or leader.totalSec)) or nil,
                dnfReason = r.dnfReason,
            }
        end
        return out
    end

    local function complete(s, now, events, why)
        for _, r in pairs(s.entrants) do
            -- A racer who never crossed the start did not start; only a racer with progress is a DNF.
            if r.state == "racing" and r.progress == 0 and (why == "nobody_started" or why == "aborted") then r.state = "dns"; r.dnfReason = why end
            if r.state == "racing" then r.state = "dnf"; r.dnfReason = why end
            if r.state == "suspended" then r.state = "dnf"; r.dnfReason = "disconnected" end
            if r.state == "entered" or r.state == "ready" then r.state = "dns"; r.dnfReason = r.dnfReason or "not_gridded" end
        end
        s.phase = "complete"
        s.completedAt = now
        ev(events, "phase", { phase = "complete", reason = why })
        ev(events, "complete", { results = M.classify(s), reason = why })
    end

    recompute = function(r, s)
        if r.state == "finished" and r.finishAt then
            r.totalSec = (r.finishAt - (s.greenAt or r.finishAt)) + r.penaltySec
            r.correctedSec = r.totalSec + r.incidentSec
        end
    end

    --- Race control (L19): a time penalty in seconds, applied to the classified time (finished or not).
    function M.penalty(s, driverId, seconds, reason, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        if s.phase == "complete" then return nil, "already_complete" end
        if type(seconds) ~= "number" or seconds <= 0 then return nil, "invalid_penalty" end
        r.penaltySec = r.penaltySec + seconds
        recompute(r, s)
        r.penalties = r.penalties or {}
        r.penalties[#r.penalties + 1] = { seconds = seconds, reason = reason or "race_control", at = now }
        local events = {}
        ev(events, "penalty", { driverId = driverId, seconds = seconds, reason = reason or "race_control", totalSec = r.totalSec })
        return events
    end

    --- An incident (L56): seconds already scored by competition.incidents (or given). Zero-fault: the host calls
    --- this once per involved driver. Applies to the corrected time, finished or not.
    function M.incident(s, driverId, inc, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        if s.phase == "complete" then return nil, "already_complete" end
        local seconds = tonumber(inc and inc.seconds) or 0
        if seconds <= 0 then return nil, "no_seconds" end
        r.incidentSec = r.incidentSec + seconds
        r.incidentCount = r.incidentCount + 1
        r.incidents[#r.incidents + 1] = { kind = inc.kind, band = inc.band, seconds = seconds, other = inc.other, at = now or inc.t, dv = inc.dv }
        recompute(r, s)
        local events = {}
        ev(events, "incident", { driverId = driverId, kind = inc.kind, band = inc.band, seconds = seconds, other = inc.other, incidentSec = r.incidentSec, count = r.incidentCount })
        return events
    end

    --- Race control: disqualification. Classified last, whatever the progress.
    function M.disqualify(s, driverId, reason, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        if s.phase == "complete" then return nil, "already_complete" end
        if r.state == "dsq" then return nil, "already_dsq" end
        r.state = "dsq"; r.dnfReason = reason or "race_control"; r.dsqAt = now
        local events = {}
        ev(events, "dsq", { driverId = driverId, reason = r.dnfReason })
        return events
    end

    --- Race control override (L19): end the session now. Unstarted racers are DNS, started ones DNF.
    function M.abort(s, now, reason)
        if s.phase == "complete" then return nil, "already_complete" end
        local events = {}
        complete(s, now, events, reason or "aborted")
        return events
    end

    local function anyStarted(s)
        for _, r in pairs(s.entrants) do
            if r.progress > 0 or r.state == "finished" then return true end
        end
        return false
    end

    --- Advance the clock. Returns the list of events produced by this step.
    function M.step(s, now)
        local events = {}
        local R = s.rules
        if s.phase == "complete" then return events end

        local function dnsAbsent()
            for _, id in ipairs(s.order) do
                local r = s.entrants[id]
                if r.state == "entered" then
                    r.state = "dns"; r.dnfReason = "absent"
                    ev(events, "dns", { driverId = id, reason = "absent" })
                end
            end
        end

        if s.phase == "forming" and now >= s.startsAt - R.gridHoldBeforeSec then
            s.phase = "gridded"; s.gridChecked = true
            ev(events, "phase", { phase = "gridded" })
        end

        if s.phase == "gridded" and now >= s.startsAt - R.countdownSec then
            local ready, total = 0, 0
            for _, r in pairs(s.entrants) do
                if r.state == "ready" or r.state == "entered" then total = total + 1 end
                if r.state == "ready" then ready = ready + 1 end
            end
            local deadline = s.originalStartsAt + R.holdMaxWaitSec
            local release = (not R.hold) or total == 0 or (ready / total) >= R.holdReleasePct or now >= deadline - R.countdownSec
            if not release then
                -- hold: slide the start so the lights wait; announce when the count changes
                s.startsAt = now + R.countdownSec + 1
                local h = s.hold
                if not h or h.ready ~= ready or h.total ~= total then
                    s.hold = { ready = ready, total = total, deadline = deadline }
                    ev(events, "hold", { ready = ready, total = total, until_ = deadline })
                end
                return events
            end
            if R.hold then
                s.hold = nil
                if s.startsAt ~= s.originalStartsAt then s.startsAt = now + R.countdownSec end   -- a held start restarts the full light count
            end
            local anyone = false
            for _, r in pairs(s.entrants) do
                if r.state == "ready" then r.state = "racing"; anyone = true
                elseif r.state == "entered" then anyone = true end
            end
            if not anyone then
                complete(s, now, events, "no_starters")
                return events
            end
            s.phase = "countdown"
            ev(events, "phase", { phase = "countdown" })
        end

        if s.phase == "countdown" then
            local shouldShow = math.min(R.countdownSec, math.floor(now - (s.startsAt - R.countdownSec)) + 1)
            while s.lightsShown < shouldShow and s.lightsShown < R.countdownSec do
                s.lightsShown = s.lightsShown + 1
                ev(events, "light", { n = s.lightsShown, of = R.countdownSec })
            end
            if now >= s.startsAt then
                -- DNS is decided at green, never when the grid closes or the light sequence begins.
                dnsAbsent()
                local starters = 0
                for _, r in pairs(s.entrants) do if r.state == "racing" then starters = starters + 1 end end
                if starters == 0 then
                    complete(s, now, events, "no_starters")
                    return events
                end
                -- KB-23: the lights go out at startsAt; the tick only notices afterwards. Dating green from the
                -- tick (up to raceTickMs late) inflated every race time by a shared, invisible offset -- gaps
                -- stayed right, which is why it went unseen, but absolute times and route records did not.
                s.phase = "running"; s.greenAt = s.startsAt
                ev(events, "phase", { phase = "running" })
                ev(events, "green", { at = s.greenAt })
            end
        end

        -- Reconnect grace expiry (running or finishing).
        if s.phase == "running" or s.phase == "finishing" then
            for _, id in ipairs(s.order) do
                local r = s.entrants[id]
                if r.state == "suspended" and now >= (r.suspendedAt or now) + R.reconnectGraceSec then
                    r.state = "dnf"; r.dnfReason = "disconnected"
                    ev(events, "dnf", { driverId = id, reason = "disconnected" })
                end
            end
        end

        -- the flag (a mixed race): it closes the race whoever is still out, and it is the only window that applies
        if s.flagAt and (s.phase == "running" or s.phase == "finishing") and now >= s.flagAt then
            complete(s, now, events, "flag")
            return events
        end

        if s.phase == "running" then
            if s.firstFinishAt then
                s.phase = "finishing"
                ev(events, "phase", { phase = "finishing", closesAt = s.firstFinishAt + R.finishWindowSec })
            elseif activeCount(s) == 0 then
                complete(s, now, events, "no_runners")
                return events
            elseif now >= s.greenAt + R.maxRaceSec then
                complete(s, now, events, "time_limit")
                return events
            elseif not anyStarted(s) and now >= s.greenAt + R.startTimeoutSec then
                complete(s, now, events, "nobody_started")
                return events
            end
        end

        if s.phase == "finishing" then
            if activeCount(s) == 0 then
                complete(s, now, events, "all_classified")
            elseif not s.flagAt and now >= math.max(s.firstFinishAt + R.finishWindowSec, s.finishHoldUntil or 0) then
                complete(s, now, events, "finish_window")
            end
        end
        return events
    end

    --- JSON-safe public view for replication (no crossings detail).
    function M.publicView(s)
        local entrants = {}
        for _, id in ipairs(s.order) do
            local r = s.entrants[id]
            entrants[#entrants + 1] = {
                driverId = id, display = r.display, slot = r.slot, state = r.state,
                progress = r.progress, totalSec = r.totalSec, penaltySec = r.penaltySec, atMark = r.atMark,
                teamId = r.teamId, seatIndex = r.seatIndex, jumpStart = r.jumpStart,
                incidentSec = r.incidentSec, incidentCount = r.incidentCount, correctedSec = r.correctedSec,
            }
        end
        local g = {}
        for i, x in ipairs(s.gates) do g[i] = { index = i, kind = x.kind, name = x.name, x = x.x, y = x.y, z = x.z, dir = x.dir, halfWidthM = x.halfWidthM, armM = x.armM } end
        return {
            sessionId = s.sessionId, eventId = s.eventId, phase = s.phase, startsAt = s.startsAt,
            greenAt = s.greenAt, lightsShown = s.lightsShown, firstFinishAt = s.firstFinishAt,
            finishWindowSec = s.rules.finishWindowSec, gridHoldBeforeSec = s.rules.gridHoldBeforeSec,
            originalStartsAt = s.originalStartsAt, hold = s.hold, kind = "race", flagAt = s.flagAt,
            start = s.rules.start, rollingGreenAt = s.rollingGreenAt, rollingLeader = s.rollingLeader, paceKph = s.rules.paceKph,
            gates = g, entrants = entrants,
        }
    end

    return M
end)
