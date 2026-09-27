-- ncm-core module: session.quali
-- Time-attack kernel for practice and qualifying sessions (L53 formats). Same public shape as session.race so the
-- host and the HUD treat both alike: phases forming -> open -> complete; a run starts at the start line and ends
-- at the finish; the best run counts. Pure: the host feeds timestamped facts.
local Core = NcmCore

Core.define("session.quali", function(C)
    local M = { version = "0.0.1" }
    local gates = C.get("course.gates")

    M.DEFAULT_RULES = { windowSec = 240, runRestartSec = 3, maxRuns = 99 }

    local complete   -- defined with classify below; join/close above reference it as an upvalue

    local function copyRules(r)
        local out = {}
        for k, v in pairs(M.DEFAULT_RULES) do out[k] = v end
        for k, v in pairs(r or {}) do out[k] = v end
        return out
    end

    --- spec = { sessionId, eventId, kind = "quali"|"practice", startsAt, windowSec?, gates, entrants, rules }
    function M.new(spec)
        if type(spec) ~= "table" then error("session.quali.new: spec required") end
        if type(spec.gates) ~= "table" or #spec.gates < 2 then error("session.quali.new: gates required") end
        local rules = copyRules(spec.rules)
        if spec.windowSec then rules.windowSec = spec.windowSec end
        if spec.maxRuns then rules.maxRuns = spec.maxRuns end   -- qualifying is one run (owner, 2026-09-21)
        local s = {
            sessionId = spec.sessionId, eventId = spec.eventId, kind = spec.kind or "quali",
            startsAt = spec.startsAt, closesAt = spec.startsAt + rules.windowSec,
            rules = rules, gates = spec.gates, phase = "forming", completedAt = nil,
            entrants = {}, order = {},
        }
        for _, e in ipairs(spec.entrants or {}) do
            s.entrants[e.driverId] = {
                driverId = e.driverId, entryId = e.entryId, slot = e.slot, display = e.display, teamId = e.teamId, seatIndex = e.seatIndex,
                state = "entered", runs = 0, run = nil, bestSec = nil, lastSec = nil, progress = 0, atMark = false,
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

    -- The race kernel's presence/departure API, so the host can call either kernel the same way.
    --- A late entrant (on-demand practice, P48: drivers join when they show interest). Idempotent.
    function M.join(s, e)
        if s.phase == "complete" then return nil, "already_complete" end
        if s.entrants[e.driverId] then return s.entrants[e.driverId], "already_joined" end
        s.entrants[e.driverId] = {
            driverId = e.driverId, entryId = e.entryId, slot = e.slot or (#s.order + 1), display = e.display, teamId = e.teamId, seatIndex = e.seatIndex,
            state = "entered", runs = 0, run = nil, bestSec = nil, lastSec = nil, progress = 0, atMark = false,
        }
        s.order[#s.order + 1] = e.driverId
        return s.entrants[e.driverId]
    end

    --- Close the window now (the host decides: qualifying is forming). Same events as a natural close.
    function M.close(s, now, reason)
        if s.phase == "complete" then return nil, "already_complete" end
        local events = {}
        complete(s, now, events, reason or "closed")
        return events
    end

    function M.mark(s, driverId, atMark)
        local r = s.entrants[driverId]
        if not r then return false, "unknown_entrant" end
        r.atMark = atMark and true or false
        return true
    end
    function M.suspend(s, driverId, now, reason)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        r.run = nil; r.progress = 0
        return { { type = "suspended", driverId = driverId, reason = reason or "disconnected" } }
    end
    function M.resume(s, driverId, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        return { { type = "resumed", driverId = driverId, at = now, progress = 0 } }
    end
    function M.leave(s, driverId, now, reason)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        r.run = nil; r.progress = 0
        r.state = r.bestSec and "timed" or "left"
        return { { type = "left", driverId = driverId, reason = reason or "left" } }
    end
    function M.penalty(s, driverId, seconds, reason, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        if r.bestSec then r.bestSec = r.bestSec + seconds end
        return { { type = "penalty", driverId = driverId, seconds = seconds, reason = reason } }
    end
    function M.disqualify(s, driverId, reason, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        r.state = "dsq"; r.bestSec = nil; r.run = nil
        return { { type = "dsq", driverId = driverId, reason = reason } }
    end
    function M.incident(s, driverId, inc, now)
        local r = s.entrants[driverId]
        if not r then return nil, "unknown_entrant" end
        r.incidentSec = (r.incidentSec or 0) + (inc.seconds or 0)
        r.incidentCount = (r.incidentCount or 0) + 1
        if r.run then r.run.incidentSec = (r.run.incidentSec or 0) + (inc.seconds or 0) end
        return { { type = "incident", driverId = driverId, kind = inc.kind, band = inc.band, seconds = inc.seconds, other = inc.other } }
    end

    --- A gate report during the open window. Crossing the start (re)starts a run; the finish closes it.
    function M.report(s, req)
        local r = s.entrants[req.driverId]
        if not r then return { ok = false, reason = "unknown_entrant" } end
        if s.phase ~= "open" then return { ok = false, reason = "not_open" } end
        if r.state == "dsq" then return { ok = false, reason = "dsq" } end
        local g = s.gates[req.gateIndex or 0]
        if not g then return { ok = false, reason = "unknown_gate" } end
        if type(req.position) ~= "table" then return { ok = false, reason = "position_unknown" } end
        local near, why, d = gates.nearGate(g, req.position)
        if not near then return { ok = false, reason = why, distanceM = d } end
        if g.kind == "start" then
            if r.run and (req.now - r.run.startedAt) < s.rules.runRestartSec then return { ok = false, reason = "run_just_started" } end
            if not r.run and r.runs >= s.rules.maxRuns then return { ok = false, reason = "no_runs_left" } end
            -- **The machine is latched HERE, at the start line.** The host reads the seat once and the run
            -- carries it to the finish. Practice attribution used to be read when the SESSION closed, so a
            -- lap was credited to whatever car the driver happened to be sitting in minutes later -- and a
            -- driver who leaves practice, refits and comes back is the ordinary case, not the edge one.
            r.run = { startedAt = req.now, progress = 1, incidentSec = 0, machine = req.machine }
            r.runs = r.runs + 1
            r.progress = 1
            r.state = r.bestSec and "timed" or "running"
            return { ok = true, gate = g, runStarted = true, runs = r.runs }
        end
        if not r.run then return { ok = false, reason = "no_run" } end
        if req.gateIndex ~= r.run.progress + 1 then return { ok = false, reason = "out_of_order", expected = r.run.progress + 1 } end
        r.run.progress = req.gateIndex
        r.progress = req.gateIndex
        if g.kind == "finish" then
            local sec = (req.now - r.run.startedAt) + (r.run.incidentSec or 0)
            local startedAt, machine, incidentSec = r.run.startedAt, r.run.machine, (r.run.incidentSec or 0)
            local improved = not r.bestSec or sec < r.bestSec
            r.lastSec = sec
            if improved then r.bestSec = sec end
            r.run = nil; r.progress = 0; r.state = "timed"
            -- **The interval leaves the kernel.** `r.run` is discarded on this line, and it held the only
            -- record of WHEN the lap happened. Without the boundaries a finished lap is a duration with no
            -- place in time, which is why no stored practice run could be located against the telemetry it
            -- was driven through. `improved` travels with it so the client, the server and the HUD all learn
            -- "this is a new best" from the kernel rather than each recomputing it.
            -- `rawSec` is the pure gate-to-gate duration; `runSec` is the official time and includes the
            -- incident penalty. Both are returned because they answer different questions, and a caller that
            -- has to subtract one from the other to get the first is a caller that will eventually subtract
            -- the wrong thing.
            return { ok = true, gate = g, finished = true, runSec = sec, bestSec = r.bestSec,
                     startedAt = startedAt, finishedAt = req.now, rawSec = req.now - startedAt,
                     incidentSec = incidentSec, improved = improved, machine = machine }
        end
        return { ok = true, gate = g }
    end

    --- Classification by best time; untimed entrants after, in slot order.
    function M.classify(s)
        local list = {}
        for _, id in ipairs(s.order) do list[#list + 1] = s.entrants[id] end
        table.sort(list, function(a, b)
            local ta, tb = a.bestSec or math.huge, b.bestSec or math.huge
            if ta ~= tb then return ta < tb end
            return (a.slot or 0) < (b.slot or 0)
        end)
        local out, leader = {}, nil
        for i, r in ipairs(list) do
            if r.bestSec and not leader then leader = r end
            out[i] = {
                position = i, driverId = r.driverId, entryId = r.entryId, display = r.display,
                state = r.state == "dsq" and "dsq" or (r.bestSec and "timed" or "no_time"),
                bestSec = r.bestSec, lastSec = r.lastSec, runs = r.runs, teamId = r.teamId, seatIndex = r.seatIndex,
                incidentSec = r.incidentSec or 0, incidentCount = r.incidentCount or 0,
                gapSec = (r.bestSec and leader and r ~= leader) and (r.bestSec - leader.bestSec) or nil,
                totalSec = r.bestSec, progress = r.progress, gatesTotal = #s.gates,
            }
        end
        return out
    end

    complete = function(s, now, events, why)
        s.phase = "complete"; s.completedAt = now; s.completeReason = why
        for _, r in pairs(s.entrants) do r.run = nil; r.progress = 0 end
        ev(events, "phase", { phase = "complete", reason = why })
        ev(events, "complete", { results = M.classify(s), reason = why })
    end

    function M.abort(s, now, reason)
        if s.phase == "complete" then return nil, "already_complete" end
        local events = {}
        complete(s, now, events, reason or "aborted")
        return events
    end

    function M.step(s, now)
        local events = {}
        if s.phase == "complete" then return events end
        if s.phase == "forming" and now >= s.startsAt then
            s.phase = "open"
            ev(events, "phase", { phase = "open", closesAt = s.closesAt })
        end
        if s.phase == "open" and now >= s.closesAt then
            complete(s, now, events, "window_closed")
        elseif s.phase == "open" then
            -- every entrant has used their runs and none is on the road: nothing left to wait for
            local all, any = true, false
            for _, r in pairs(s.entrants) do any = true; if r.run or r.runs < s.rules.maxRuns then all = false end end
            if any and all then complete(s, now, events, "all_runs_done") end
        end
        return events
    end

    function M.publicView(s)
        local entrants = {}
        for _, id in ipairs(s.order) do
            local r = s.entrants[id]
            entrants[#entrants + 1] = {
                driverId = id, display = r.display, slot = r.slot, state = r.state, progress = r.progress,
                bestSec = r.bestSec, lastSec = r.lastSec, runs = r.runs, runProgress = r.run and r.run.progress or 0,
                totalSec = r.bestSec, penaltySec = 0, atMark = r.atMark, teamId = r.teamId, seatIndex = r.seatIndex,
                incidentSec = r.incidentSec or 0, incidentCount = r.incidentCount or 0,
            }
        end
        local g = {}
        for i, x in ipairs(s.gates) do g[i] = { index = i, kind = x.kind, name = x.name, x = x.x, y = x.y, z = x.z, dir = x.dir, halfWidthM = x.halfWidthM, armM = x.armM } end
        return {
            sessionId = s.sessionId, eventId = s.eventId, kind = s.kind, phase = s.phase, startsAt = s.startsAt, closesAt = s.closesAt,
            windowSec = s.rules.windowSec, maxRuns = s.rules.maxRuns, gates = g, entrants = entrants,
        }
    end

    return M
end)
