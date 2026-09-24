-- ncm-core module: qa.rules
--
-- Verdicts for the QA instrumentation pass. See `wp/QA_INSTRUMENTATION.md` for the mapping from these rules
-- back to the QA corpus (`wp/OFFLINE_TEST_QUEUE.md` defines the items; `wp/MASTER_TEST.md` records results).
--
-- **Facts, never conclusions.** Every function here answers "did a stated invariant hold on this transition?"
-- and nothing else. Three failed CALL attempts followed by opening Help is recorded as three failures and a
-- Help open; it is never recorded as a confused player.
--
-- **Three verdicts, and the difference matters.**
--   PASS    an invariant the QA corpus states was checked on a real transition and held.
--   FAIL    that invariant was violated. This is a defect, not a hint.
--   REVIEW  something worth a human's eye. Suggestive, incomplete, or absence-shaped. NEVER reported as a bug.
--
-- **Repeatability is the point.** A rule that has held four hundred times is much stronger evidence than one
-- that held once, and a one-in-fifty failure is only ever visible through repetition. The host therefore counts
-- occurrences against a fixed set of (item, verdict) pairs rather than appending a row per event -- which is
-- also what stops this becoming a firehose.
--
-- Pure: no clock, no database, no platform. Hosts supply facts and act on verdicts.
local Core = NcmCore

Core.define("qa.rules", function(C)
    local M = { version = "0.0.1" }

    M.PASS, M.FAIL, M.REVIEW = "pass", "fail", "review"

    local function verdict(qaId, v, detail)
        return { qaId = qaId, verdict = v, detail = detail }
    end

    --- G1 / D6 · Race time precision (KB-23).
    --- A real time looks like `1:04.964`. `0:40.000` was the tell that the clock was being sampled on a tick
    --- rather than dated from the event. Both G1 and D6 state this invariant; they share a rule.
    function M.raceTime(elapsedMs)
        local ms = tonumber(elapsedMs)
        if not ms or ms <= 0 then return verdict("G1", M.REVIEW, "no elapsed time recorded") end
        if ms % 100 == 0 then
            return verdict("G1", M.FAIL, ("elapsed %dms is an exact multiple of 100ms"):format(ms))
        end
        return verdict("G1", M.PASS, ("elapsed %dms"):format(ms))
    end

    --- A2 · No phantom win (IDEA-001, L67). A solo entrant is a time trial: a field of one cannot be won.
    function M.soloResult(fieldSize, accomplishments)
        local n = tonumber(fieldSize) or 0
        local list = type(accomplishments) == "table" and accomplishments or {}
        local won = false
        for _, a in ipairs(list) do if tostring(a) == "first_win" then won = true end end
        if n <= 1 and won then
            return verdict("A2", M.FAIL, "first_win granted for a single-entrant session")
        end
        if n <= 1 then return verdict("A2", M.PASS, "solo session granted no win") end
        return nil   -- not a solo session: this rule has nothing to say
    end

    --- G4 · Once-only accomplishments (KB-38). `alreadyHeld` is what the driver had BEFORE this grant.
    function M.onceOnly(granted, alreadyHeld)
        local held = {}
        for _, a in ipairs(type(alreadyHeld) == "table" and alreadyHeld or {}) do held[tostring(a)] = true end
        local ONCE = { first_finish = true, first_win = true, first_time_trial = true }
        for _, a in ipairs(type(granted) == "table" and granted or {}) do
            local key = tostring(a)
            if ONCE[key] and held[key] then
                return verdict("G4", M.FAIL, ("%s granted twice"):format(key))
            end
        end
        return verdict("G4", M.PASS, "no once-only accomplishment repeated")
    end

    --- P4 · The driver's guidance follows THEIR event (L107, KB-75).
    --- Ring, card, waypoint and venue options must all name the event `driverEvent()` returns. This invariant
    --- was violated in three separate places on 2026-09-23 and nothing noticed.
    function M.guidanceTarget(expectedEventId, shownEventId, surface)
        if expectedEventId == nil then return nil end        -- no live entry: nothing to agree about
        if shownEventId == nil then
            return verdict("P4", M.REVIEW, ("%s showed nothing while an entry was live"):format(tostring(surface)))
        end
        if tostring(expectedEventId) ~= tostring(shownEventId) then
            return verdict("P4", M.FAIL, ("%s showed %s, driver's race is %s")
                :format(tostring(surface), tostring(shownEventId), tostring(expectedEventId)))
        end
        return verdict("P4", M.PASS, tostring(surface))
    end

    --- P1 · A published Guide reaches the player (KB-59/63/65).
    --- `rows` is what the server sent; `drew` is whether the page confirmed it drew. A publish with rows that
    --- never draws is the silent-drop family of defects.
    function M.guideDelivery(rows, drew, ms)
        local n = tonumber(rows) or 0
        if n <= 0 then return nil end                        -- nothing published: not this rule's business
        if drew == false then
            return verdict("P1", M.FAIL, ("%d row(s) published, panel never drew"):format(n))
        end
        if drew == nil then
            return verdict("P1", M.REVIEW, ("%d row(s) published, no draw confirmation"):format(n))
        end
        return verdict("P1", M.PASS, ("%d row(s) drew in %sms"):format(n, tostring(ms or "?")))
    end

    --- T2/T3/T4 · Discovery provenance (spec 1 §A/§B, IDEA-137).
    --- `previousSource` is the source already stored, if this is a repeat encounter.
    function M.discovery(driverId, sourceDriverId, previousSource, holding)
        if sourceDriverId and driverId and tostring(sourceDriverId) == tostring(driverId) then
            return verdict("T4", M.FAIL, "a driver was credited as the source of their own discovery")
        end
        if previousSource ~= nil and sourceDriverId ~= nil
            and tostring(previousSource) ~= tostring(sourceDriverId) then
            return verdict("T3", M.FAIL, "credit was rewritten on a repeat encounter")
        end
        if sourceDriverId == nil and holding ~= "authored" then
            -- legitimate (a showroom, a display), but worth a human glance when it is not authored content
            return verdict("T2", M.REVIEW, ("discovery with no source, holding=%s"):format(tostring(holding)))
        end
        return verdict("T2", M.PASS, ("source recorded, holding=%s"):format(tostring(holding)))
    end

    --- M7 · Ownership survives a restart (IDEA-115). Compared across a boot boundary.
    function M.ownershipSurvived(before, after)
        local b, a = tonumber(before), tonumber(after)
        if b == nil or a == nil then return verdict("M7", M.REVIEW, "no count to compare") end
        if b > 0 and a == 0 then
            return verdict("M7", M.FAIL, ("%d asset(s) before restart, 0 after"):format(b))
        end
        if a < b then
            return verdict("M7", M.REVIEW, ("assets fell %d -> %d across a restart"):format(b, a))
        end
        return verdict("M7", M.PASS, ("%d asset(s) intact"):format(a))
    end

    --- M1 · Migrations applied, and do not re-apply (IDEA-115).
    function M.migrations(pendingCount, appliedThisBoot)
        local pending = tonumber(pendingCount) or 0
        if pending > 0 then
            return verdict("M1", M.FAIL, ("%d migration(s) still pending after boot"):format(pending))
        end
        return verdict("M1", M.PASS, ("0 pending, %d applied this boot"):format(tonumber(appliedThisBoot) or 0))
    end

    --- O1/O8 · The calendar has the shape the championships describe (IDEA-111, IDEA-104).
    --- `series` is a list of { id, routeCount }. `dragRoutes` names the routes drag is confined to.
    function M.calendarShape(series, expectedSeriesCount)
        local n = 0
        for _ in ipairs(type(series) == "table" and series or {}) do n = n + 1 end
        local want = tonumber(expectedSeriesCount) or 5
        if n == 0 then return verdict("O1", M.FAIL, "no championships started") end
        if n ~= want then
            return verdict("O1", M.REVIEW, ("%d championship(s) started, expected %d"):format(n, want))
        end
        return verdict("O1", M.PASS, ("%d championships"):format(n))
    end

    --- N7 · The option list and the server agree (IDEA-113).
    --- `offered` is whether the venue list offered entry; `accepted` is what the server then did.
    function M.entryAgreement(offered, accepted, reason)
        if accepted and offered == false then
            return verdict("N7", M.FAIL, ("entry accepted though the list refused it (%s)"):format(tostring(reason)))
        end
        if (not accepted) and offered == true then
            return verdict("N7", M.REVIEW, ("entry offered then refused (%s)"):format(tostring(reason)))
        end
        return verdict("N7", M.PASS, accepted and "offered and accepted" or "not offered, not accepted")
    end

    --- Every QA id this module can emit. Lets a host assert its wiring matches the mapping document.
    function M.covers()
        return { "A2", "G1", "G4", "M1", "M7", "N7", "O1", "P1", "P4", "T2", "T3", "T4" }
    end

    return M
end)
