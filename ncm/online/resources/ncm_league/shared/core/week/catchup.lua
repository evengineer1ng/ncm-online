-- ncm-core module: week.catchup
-- Calculate the present after an absence (L338; L330 (4) "single player catches up lazily on its seed").
--
-- Racing Week keeps running while nobody is there -- no process has to: every possible end (noon of Day 3 .. Day 7)
-- that passed while the world was not running is judged now, IN ORDER, with the same seeded draw `week.continuation`
-- would have made at the time. A run nobody lived in is judged UNATTENDED (standing 0: history's baseline); the run
-- that was live when the world stopped is judged on the standing it was left with (nothing moves a curve while nobody
-- is there). The result is identical whether a world ran continuously or caught up later from the same records --
-- `test_week_catchup.lua` holds that line -- and nothing is ever simulated second by second.
--
-- `week.clock.locate` alone cannot do this: past an open run's Day 7 it reads the run as ended there UNJUDGED and moves
-- on (the right reading for "what day is it" while a verdict is pending, the wrong one for an absence of weeks).
local Core = NcmCore

Core.define("week.catchup", function(C)
    local M = { version = "0.1.0", MAX_VERDICTS = 20000 }
    local Week = C.get("week.clock")
    local Cont = C.get("week.continuation")

    local function copyRuns(runs)
        local out = {}
        for k, v in pairs(runs or {}) do
            local n = tonumber(k)
            if n and type(v) == "table" then out[n] = { endUtc = tonumber(v.endUtc), endKind = v.endKind, survived = tonumber(v.survived) } end
        end
        return out
    end

    --- Settle every verdict due at or before `nowUtc`.
    --- seedFor(run) -> the run's seed; standingFor(run) -> curve state ({ deviation }) or nil (unattended).
    --- opts.mode = "history" ends every run at hour 72 (the old week), as `ncm_week_verdict` does.
    --- Returns { runs = <new timeline>, verdicts = { { run, hours, kind, p, z, u, atUtc, startUtc, unattended } ... } }.
    function M.settle(cfg, runs, nowUtc, seedFor, standingFor, opts)
        opts = opts or {}
        nowUtc = math.floor(tonumber(nowUtc) or 0)
        local tl = copyRuns(runs)
        local verdicts = {}
        local start = Week.runBounds(cfg, 1)
        if nowUtc < start then return { runs = tl, verdicts = verdicts } end
        local n = 1
        while #verdicts < M.MAX_VERDICTS do
            local rec = tl[n] or {}
            if rec.endUtc then
                if nowUtc < rec.endUtc then break end
                start = rec.endUtc
                n = n + 1
            else
                local survived = math.max(Week.DAYS - 1, math.min(Week.MAX_DAYS - 1, math.floor(tonumber(rec.survived) or 0)))
                local k = survived + 1
                local endAt = Week.boundary(cfg, start, k)
                if nowUtc < endAt then break end
                local hours = k * 24
                local st = standingFor and standingFor(n) or nil
                local v = Cont.judge(seedFor(n), n, hours, st)
                if opts.mode == "history" then v.survive, v.kind = false, "collapse" end
                verdicts[#verdicts + 1] = { run = n, hours = hours, kind = v.kind, p = v.p, z = v.z, u = v.u, atUtc = endAt,
                    startUtc = start, unattended = st == nil }
                tl[n] = tl[n] or {}
                if v.kind == "continue" then
                    tl[n].survived = k
                else
                    tl[n].endUtc, tl[n].endKind, tl[n].survived = endAt, v.kind, survived
                end
            end
        end
        return { runs = tl, verdicts = verdicts }
    end

    --- The present over a settled timeline: `week.clock.nowIn` after `M.settle`. Also returns the settle result.
    function M.present(cfg, runs, nowUtc, seedFor, standingFor, opts)
        local s = M.settle(cfg, runs, nowUtc, seedFor, standingFor, opts)
        return Week.nowIn(cfg, s.runs, nowUtc), s
    end

    return M
end)
