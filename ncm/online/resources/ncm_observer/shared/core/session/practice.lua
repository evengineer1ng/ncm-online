-- ncm-core module: session.practice
-- On-demand practice (P48): the `session.quali` run engine with no window and no countdown. One practice session
-- per event, open from the moment the host creates it until qualifying (or the first session) forms; drivers
-- join when they show interest and run as often as they like; the best run per driver stands on a leaderboard
-- (per event here; the host also folds bests into route records). Incidents count on a run like anywhere else.
local Core = NcmCore

Core.define("session.practice", function(C)
    local M = { version = "0.0.1" }
    local Q = C.get("session.quali")

    M.RULES = { runRestartSec = 3, maxRuns = 99 }

    --- spec = { sessionId, eventId, gates, closesAt, entrants? }
    function M.new(spec)
        if type(spec) ~= "table" or type(spec.closesAt) ~= "number" then error("session.practice.new: closesAt required") end
        local s = Q.new({
            sessionId = spec.sessionId, eventId = spec.eventId, kind = "practice",
            startsAt = spec.openAt or 0, windowSec = math.max(1, spec.closesAt - (spec.openAt or 0)),
            gates = spec.gates, entrants = spec.entrants or {}, rules = M.RULES,
        })
        s.closesAt = spec.closesAt
        s.phase = "open"          -- no forming, no countdown: the window is the event's own life
        s.practice = true
        return s
    end

    --- A driver who shows interest joins the open practice; a second join is a no-op.
    function M.join(s, entrant) return Q.join(s, entrant) end
    function M.leave(s, driverId, now, reason) return Q.leave(s, driverId, now, reason) end
    function M.report(s, req) return Q.report(s, req) end
    function M.incident(s, driverId, inc, now) return Q.incident(s, driverId, inc, now) end
    function M.publicView(s)
        local v = Q.publicView(s)
        v.practice = true
        v.leaderboard = M.leaderboard(s)
        return v
    end

    --- Close the practice (qualifying is forming): completes the kernel so results can be stored like any session.
    function M.close(s, now, reason) return Q.close(s, now, reason or "session_forming") end
    function M.classify(s) return Q.classify(s) end
    function M.suspend(s, driverId, now, reason) return Q.suspend(s, driverId, now, reason) end
    function M.resume(s, driverId, now) return Q.resume(s, driverId, now) end
    function M.mark(s, driverId, atMark) return Q.mark(s, driverId, atMark) end
    function M.penalty(s, driverId, seconds, reason, now) return Q.penalty(s, driverId, seconds, reason, now) end
    function M.disqualify(s, driverId, reason, now) return Q.disqualify(s, driverId, reason, now) end
    function M.abort(s, now, reason) return Q.abort(s, now, reason) end

    --- Step: a practice never closes itself before `closesAt`; a run in progress when it closes is lost.
    function M.step(s, now)
        return Q.step(s, now)
    end

    --- Leaderboard: timed drivers by best, then the rest in join order. Rows carry runs and incidents.
    function M.leaderboard(s)
        local rows = Q.classify(s)
        local out = {}
        for i, r in ipairs(rows) do
            out[i] = { position = i, driverId = r.driverId, display = r.display, bestSec = r.bestSec, runs = r.runs,
                       incidentCount = r.incidentCount, gapSec = r.gapSec, timed = r.bestSec ~= nil }
        end
        return out
    end

    return M
end)
