-- The QA observer's verdicts. The rules must be deterministic and must never turn evidence into a conclusion.
return {
    -- KB-23: `0:40.000` was the tell. A real race time is not a round tick.
    race_time_quantisation_is_a_fail_not_a_hint = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.raceTime(40000).verdict, R.FAIL, "an exact multiple of 100ms is the defect")
        T.eq(R.raceTime(64964).verdict, R.PASS)
        T.eq(R.raceTime(0).verdict, R.REVIEW, "no time is not a failed time")
        T.eq(R.raceTime(nil).verdict, R.REVIEW)
        T.eq(R.raceTime(40000).qaId, "G1")
    end,

    a_field_of_one_cannot_be_won = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.soloResult(1, { "first_finish", "first_win" }).verdict, R.FAIL)
        T.eq(R.soloResult(1, { "first_time_trial" }).verdict, R.PASS)
        T.eq(R.soloResult(4, { "first_win" }), nil, "a real field is not this rule's business")
    end,

    once_only_accomplishments = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.onceOnly({ "first_win" }, { "first_win" }).verdict, R.FAIL)
        T.eq(R.onceOnly({ "first_win" }, { "first_finish" }).verdict, R.PASS)
        T.eq(R.onceOnly({ "clean_race" }, { "clean_race" }).verdict, R.PASS, "repeatable ones may repeat")
        T.eq(R.onceOnly(nil, nil).verdict, R.PASS)
    end,

    -- L107 / KB-75: the invariant that was violated in three places in one hour.
    guidance_must_name_the_drivers_own_race = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.guidanceTarget("e1", "e2", "ring").verdict, R.FAIL)
        T.eq(R.guidanceTarget("e1", "e1", "ring").verdict, R.PASS)
        T.eq(R.guidanceTarget("e1", nil, "card").verdict, R.REVIEW, "absence is evidence, not proof")
        T.eq(R.guidanceTarget(nil, "e2", "gps"), nil, "no live entry: nothing to disagree about")
        T.match(R.guidanceTarget("e1", "e2", "gps").detail, "gps")
    end,

    a_publish_that_never_drew_is_a_failure = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.guideDelivery(16, false).verdict, R.FAIL)
        T.eq(R.guideDelivery(16, true, 120).verdict, R.PASS)
        T.eq(R.guideDelivery(16, nil).verdict, R.REVIEW, "unconfirmed is not failed")
        T.eq(R.guideDelivery(0, false), nil, "nothing published, nothing to deliver")
    end,

    discovery_provenance_cannot_be_farmed_or_self_credited = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.discovery("d1", "d1", nil, "issued").verdict, R.FAIL, "self-credit")
        T.eq(R.discovery("d1", "d1", nil, "issued").qaId, "T4")
        local rewrite = R.discovery("d1", "d3", "d2", "owned")
        T.eq(rewrite.verdict, R.FAIL); T.eq(rewrite.qaId, "T3")
        T.eq(R.discovery("d1", "d2", "d2", "owned").verdict, R.PASS, "same source again is the anti-farm rule holding")
        T.eq(R.discovery("d1", nil, nil, "authored").verdict, R.PASS, "an authored display legitimately has no source")
        T.eq(R.discovery("d1", nil, nil, "issued").verdict, R.REVIEW)
    end,

    ownership_must_survive_a_restart = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.ownershipSurvived(12, 0).verdict, R.FAIL, "a ledger that empties on restart was never a ledger")
        T.eq(R.ownershipSurvived(12, 12).verdict, R.PASS)
        T.eq(R.ownershipSurvived(12, 9).verdict, R.REVIEW, "a partial loss needs a human, not an alarm")
        T.eq(R.ownershipSurvived(0, 0).verdict, R.PASS)
        T.eq(R.ownershipSurvived(nil, 3).verdict, R.REVIEW)
    end,

    migrations_and_calendar_shape = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.migrations(0, 2).verdict, R.PASS)
        T.eq(R.migrations(3, 0).verdict, R.FAIL)
        T.eq(R.calendarShape({}, 5).verdict, R.FAIL)
        T.eq(R.calendarShape({ 1, 2, 3, 4, 5 }, 5).verdict, R.PASS)
        T.eq(R.calendarShape({ 1, 2 }, 5).verdict, R.REVIEW, "a different count is a question, not a defect")
    end,

    -- The list is presentation; the server decides. A stale client must never be able to enter.
    the_list_and_the_server_must_agree = function(T)
        local R = T.Core.get("qa.rules")
        T.eq(R.entryAgreement(false, true, "no_car").verdict, R.FAIL)
        T.eq(R.entryAgreement(true, true).verdict, R.PASS)
        T.eq(R.entryAgreement(false, false).verdict, R.PASS)
        T.eq(R.entryAgreement(true, false, "grid_forming").verdict, R.REVIEW, "a race that formed first is not a bug")
    end,

    every_rule_is_deterministic = function(T)
        local R = T.Core.get("qa.rules")
        for _ = 1, 50 do
            T.eq(R.raceTime(40000).verdict, R.FAIL)
            T.eq(R.discovery("d1", "d2", nil, "owned").verdict, R.PASS)
            T.eq(R.guidanceTarget("e1", "e2", "ring").verdict, R.FAIL)
        end
    end,

    the_wiring_matches_the_mapping_document = function(T)
        local R = T.Core.get("qa.rules")
        local ids = R.covers()
        T.ok(#ids >= 12)
        local seen = {}
        for _, id in ipairs(ids) do
            T.eq(seen[id], nil, "duplicate QA id in covers(): " .. id)
            T.match(id, "^[A-Z]+%d+$", "QA ids are corpus ids, never invented names")
            seen[id] = true
        end
    end,
}
