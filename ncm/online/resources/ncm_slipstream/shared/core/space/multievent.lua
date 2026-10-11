-- ncm-core module: space.multievent
--
-- Multi-leg events (L322; doc 54 §M): the TRIATHLON in both its forms, as a schema and its scoring.
--   * The original multi-machine triathlon: legs in different machine CLASSES on one world (e.g. bike -> sports car;
--     the open-wheel Formula car is an unlicensed third-party asset and is never a dependency: classes are whatever
--     NCM can legitimately provide).
--   * The CROSS-DOMAIN event: a Night City leg, a Los Santos leg and a Snowglobe leg in the same Race Week -- the
--     crown jewel. Sanctioning formats differ and all are data:
--       points    finishing positions score per leg; most points wins (best last leg breaks a tie)
--       sum       leg race times added; travel between legs does not count; a DNF anywhere is out
--       nonstop   ONE clock from the first green to the last flag: traversal, runtime transfer, logistics and
--                 preparation between legs are part of the race
-- DISCOVERY GATES IT. A leg in a domain the person has not legitimately discovered makes the event invisible to them:
-- `visibleTo` returns false, so nothing in terrestrial Race Week UI can spoil Snowglobe. Executing a cross-domain
-- event needs the cross-server identity and result transport (doc 52), which does not exist yet; the schema and the
-- scoring do not wait for it.
local Core = NcmCore

Core.define("space.multievent", function(C)
    local M = { version = "0.1.0" }

    M.FORMATS = { points = true, sum = true, nonstop = true }
    M.DOMAINS = { night_city = true, los_santos = true, snowglobe = true }
    M.POINTS = { 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 }

    --- event = { id, format, legs = { { domain, discipline, class?, eventRef? } } }
    function M.validate(ev)
        if not M.FORMATS[ev.format] then return false, "unknown format " .. tostring(ev.format) end
        if type(ev.legs) ~= "table" or #ev.legs < 2 then return false, "a multi-event has at least two legs" end
        for i, l in ipairs(ev.legs) do
            if not M.DOMAINS[l.domain] then return false, ("leg %d: unknown domain %s"):format(i, tostring(l.domain)) end
        end
        return true
    end

    --- Whether a person may even SEE the event: every leg's domain must be discovered (person.discovered[domain]).
    --- Night City is everyone's home domain.
    function M.visibleTo(ev, person)
        local d = person and person.discovered or {}
        for _, l in ipairs(ev.legs) do
            if l.domain ~= "night_city" and not d[l.domain] then return false end
        end
        return true
    end

    --- Score. results[legIndex] = { { id, position, state = "finished"|"dnf", raceS, startT?, finishT? } }.
    --- Returns rows { id, position, points? / totalS?, legs = n } best first; incomplete entrants after.
    function M.score(ev, results)
        local by = {}
        local function row(id)
            by[id] = by[id] or { id = id, points = 0, totalS = 0, legs = 0, dnf = false, firstStart = nil, lastFinish = nil, lastPos = 99 }
            return by[id]
        end
        for li, leg in ipairs(results) do
            for _, r in ipairs(leg) do
                local x = row(r.id)
                if r.state == "finished" then
                    x.legs = x.legs + 1
                    x.points = x.points + (M.POINTS[r.position] or 0)
                    x.totalS = x.totalS + (r.raceS or 0)
                    if li == 1 and r.startT then x.firstStart = r.startT end
                    if li == #ev.legs and r.finishT then x.lastFinish = r.finishT end
                    if li == #ev.legs then x.lastPos = r.position end
                else
                    x.dnf = true
                end
            end
        end
        local rows = {}
        for _, x in pairs(by) do rows[#rows + 1] = x end
        local n = #ev.legs
        for _, x in ipairs(rows) do
            x.complete = x.legs == n and not x.dnf
            if ev.format == "nonstop" then
                x.totalS = (x.complete and x.firstStart and x.lastFinish) and (x.lastFinish - x.firstStart) or nil
                x.complete = x.totalS ~= nil
            end
        end
        table.sort(rows, function(a, b)
            if a.complete ~= b.complete then return a.complete end
            if ev.format == "points" then
                if a.points ~= b.points then return a.points > b.points end
                if a.lastPos ~= b.lastPos then return a.lastPos < b.lastPos end
            elseif a.complete and a.totalS ~= b.totalS then
                return a.totalS < b.totalS
            elseif not a.complete and a.legs ~= b.legs then
                return a.legs > b.legs
            end
            return tostring(a.id) < tostring(b.id)
        end)
        for i, x in ipairs(rows) do x.position = i end
        return rows
    end

    return M
end)
