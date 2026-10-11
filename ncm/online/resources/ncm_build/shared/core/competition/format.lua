-- ncm-core module: competition.format
-- A format is the shape of a round (L53, L23): which sessions an event contains and how each one's grid is drawn
-- from the previous. Pure: `plan` turns a format into session specs; `gridFor` orders drivers from prior results.
local Core = NcmCore

Core.define("competition.format", function(C)
    local M = { version = "0.0.1" }

    M.LIST = {
        { id = "sprint",   name = "Sprint",   enabled = true,
          sessions = { { kind = "race" } } },
        -- Practice is not a session of the plan: it is on demand for a listed event (P48, owner QA batch 2) and
        -- arrives with the Race Guide (Batch 2). The `session.quali` run engine is what it will run on.
        { id = "weekend",  name = "Weekend",  enabled = true,
          sessions = { { kind = "quali", windowSec = 240, maxRuns = 1 }, { kind = "race", gridFrom = "quali" } } },
        { id = "two_race", name = "Two races", enabled = true,
          sessions = { { kind = "race", ordinal = 1 }, { kind = "race", ordinal = 2, gridFrom = "reversed_top_n", n = 8 } } },
        { id = "heats",    name = "Heats",    enabled = false, sessions = {} },
        { id = "stints",   name = "Stints",   enabled = false, sessions = {} },
    }
    M.ALIASES = { tworace = "two_race", twoRace = "two_race", weekend = "weekend", sprint = "sprint" }

    local byId
    function M.byId(id)
        if not byId then byId = {}; for _, f in ipairs(M.LIST) do byId[f.id] = f end end
        return byId[M.ALIASES[id] or id]
    end

    --- A time-attack window sized to the route, not a fixed number (owner, 2026-09-21): a generous run estimate
    --- (PACE_MPS is slow on purpose), doubled for the stage-and-go, plus a minute, rounded UP to whole minutes and to
    --- a multiple of five above ten. Never below the format's own windowSec.
    M.PACE_MPS = 15            -- 54 km/h: a careful street pace, so the window is never the pressure
    function M.windowFor(lengthM, minSec)
        local run = (tonumber(lengthM) or 0) / M.PACE_MPS
        local minutes = math.ceil((run * 2 + 60) / 60)
        if minutes > 10 then minutes = math.ceil(minutes / 5) * 5 end
        return math.max(minutes * 60, tonumber(minSec) or 0)
    end

    --- Session specs for a format. Each: { kind, ordinal, windowSec?, gridFrom?, n?, gapSec }.
    --- opts.lengthM sizes practice/qualifying windows to the route (M.windowFor); without it the format's fixed window stands.
    function M.plan(formatId, opts)
        opts = opts or {}
        local f = M.byId(formatId) or M.byId("sprint")
        local out = {}
        for i, s in ipairs(f.sessions) do
            local windowSec = s.windowSec
            if windowSec and opts.lengthM then windowSec = M.windowFor(opts.lengthM, windowSec) end
            out[i] = { kind = s.kind, ordinal = s.ordinal or i, windowSec = windowSec, maxRuns = s.maxRuns, gridFrom = s.gridFrom, n = s.n,
                       gapSec = tonumber(opts.gapSec) or 90, formatId = f.id, index = i, of = #f.sessions }
        end
        return out
    end

    --- Seconds between a session's last result and the next session forming, from the distance the field has to
    --- cover (a qualifying finish can be at the far end of Night City from the grid, P50): travel at PACE_MPS plus a
    --- minute, rounded up to whole minutes, never below the plan's gapSec.
    function M.gapFor(travelM, gapSec)
        local sec = (tonumber(travelM) or 0) / M.PACE_MPS + 60
        return math.max(math.ceil(sec / 60) * 60, tonumber(gapSec) or 90)
    end

    --- Order driverIds for a session from the prior session's results.
    --- prior = { kind, results = classify() rows }. Unknown gridFrom or no prior -> nil (host keeps its default order).
    function M.gridFor(spec, prior)
        if not spec or not spec.gridFrom or not prior or type(prior.results) ~= "table" then return nil end
        local rows = prior.results
        if spec.gridFrom == "quali" then
            local timed, untimed = {}, {}
            for _, r in ipairs(rows) do
                if r.bestSec then timed[#timed + 1] = r else untimed[#untimed + 1] = r end
            end
            table.sort(timed, function(a, b) if a.bestSec ~= b.bestSec then return a.bestSec < b.bestSec end return (a.position or 0) < (b.position or 0) end)
            table.sort(untimed, function(a, b) return (a.position or 0) < (b.position or 0) end)
            local out = {}
            for _, r in ipairs(timed) do out[#out + 1] = r.driverId end
            for _, r in ipairs(untimed) do out[#out + 1] = r.driverId end
            return out
        elseif spec.gridFrom == "reversed_top_n" then
            local n = math.max(1, math.floor(tonumber(spec.n) or 8))
            local classified, back = {}, {}
            for _, r in ipairs(rows) do
                if r.state == "finished" then classified[#classified + 1] = r else back[#back + 1] = r end
            end
            table.sort(classified, function(a, b) return (a.position or 0) < (b.position or 0) end)
            table.sort(back, function(a, b) return (a.position or 0) < (b.position or 0) end)
            local top = math.min(n, #classified)
            local out = {}
            for i = top, 1, -1 do out[#out + 1] = classified[i].driverId end
            for i = top + 1, #classified do out[#out + 1] = classified[i].driverId end
            for _, r in ipairs(back) do out[#out + 1] = r.driverId end
            return out
        end
        return nil
    end

    return M
end)
