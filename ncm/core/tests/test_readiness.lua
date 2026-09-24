-- KB-60. Every case here is written against the bug report, not against the code:
-- Trip[ABK] was connected, had a position, reported `appearance_failed` 44 times over ~11 minutes,
-- and NCM said nothing. The first test is that exact player.
local function tracker(T, opts)
    return T.Core.get("world.readiness").new(opts)
end

local function only(T, actions, kind)
    local out = {}
    for _, a in ipairs(actions) do if a.kind == kind then out[#out + 1] = a end end
    return out
end

return {
    -- The bug, reproduced: a position is not the ability to play.
    trip_abk_is_seen_despite_having_a_position = function(T)
        local R = T.Core.get("world.readiness")
        local t = tracker(T)
        t:connected(6, 0, "Trip[ABK]")
        -- `onPlayerReady` never fires for this player -- that is the failure.
        T.eq(#t:sweep(5, { { id = 6, inWorld = true } }), 0, "no nagging inside the grace period")
        t:stage(6, "appearance_failed", 15, 15)
        local actions = t:sweep(20, { { id = 6, inWorld = true } })
        T.eq(#actions, 1)
        local a = actions[1]
        T.eq(a.kind, "advise"); T.eq(a.id, 6); T.eq(a.name, "Trip[ABK]")
        T.ok(a.terminal, "appearance_failed is terminal, not slow")
        T.eq(a.stage, "appearance_failed")
        T.ok(a.inWorld, "the old inTheWorld test was satisfied -- and meant nothing")
        T.eq(a.playable, false)
        T.match(R.why(a), "ncm%-ready=NO in%-world=yes platform%-stage=appearance_failed")
        T.match(R.advice(a).chat, "waiting will not fix it")
    end,

    -- Deploy 19 live QA, replayed from the server log. The owner's own join: connected at 0, the platform's
    -- readiness heartbeat fired ONCE at 17 s (`appearance_applying`, reset=complete, bootstrap=ready), NCM
    -- ready at 19 s -- and then the client went quiet, which is how that heartbeat says "I stopped waiting".
    -- The shipped code held that single report for 45 s, warned them at 47 s, and logged them "playable" at
    -- 63 s when all that had expired was its own timer.
    r2_one_heartbeat_does_not_mean_stuck_for_the_next_forty_five_seconds = function(T)
        local t = tracker(T)
        t:connected(1, 0, "easporks")
        t:stage(1, "appearance_applying", 17, 15)   -- exactly one report, as the real log shows
        t:ready(1, 19)
        local warned = 0
        for now = 5, 300, 5 do
            for _, a in ipairs(t:sweep(now, { { id = 1, inWorld = true } })) do
                if a.kind == "advise" then warned = warned + 1 end
            end
        end
        T.eq(warned, 0, "a normal join must never be told to reconnect")
        T.eq(t:state(1, 45, true).playable, true, "the heartbeat expired long before the 45s warning point")
    end,

    r2_but_a_stalled_progressing_load_is_still_caught = function(T)
        local t = tracker(T, { progressingGraceS = 90 })
        t:connected(2, 0, "Stuck")
        t:ready(2, 5)
        local first
        for now = 5, 200, 5 do
            t:stage(2, "appearance_applying", now, now)   -- reported forever, never completes
            for _, a in ipairs(t:sweep(now, { { id = 2, inWorld = true } })) do
                if a.kind == "advise" and not first then first = a.waited end
            end
        end
        T.ok(first and first >= 90, "the long grace is a grace, not an exemption: got " .. tostring(first))
        T.ok(first < 120, "and it is not indefinite")
    end,

    the_three_graces_are_distinct_and_ordered = function(T)
        local t = tracker(T)
        local terminal = t:graceFor({ terminal = true, waiting = true })
        local progressing = t:graceFor({ terminal = false, waiting = true })
        local silent = t:graceFor({ terminal = false, waiting = false })
        T.eq(terminal, 10); T.eq(silent, 45); T.eq(progressing, 90)
        T.ok(terminal < silent and silent < progressing,
            "a failure that cannot resolve is interrupted soonest; visible progress waits longest")
    end,

    terminal_keeps_the_fast_path_that_kb60_needed = function(T)
        -- The regression that matters: the long grace must not slow down the Trip[ABK] case.
        local t = tracker(T)
        t:connected(3, 0, "Trip[ABK]")
        t:stage(3, "appearance_failed", 15, 15)
        local a = t:sweep(30, { { id = 3, inWorld = true } })
        T.eq(#a, 1); T.eq(a[1].kind, "advise"); T.ok(a[1].terminal)
        T.ok(a[1].waited < 45, "terminal is still advised well inside the silent-limbo grace")
    end,

    -- Gap 1: the sweep sees a player no event ever announced.
    sweep_does_not_depend_on_any_readiness_event = function(T)
        local t = tracker(T)
        -- Never connected(), never ready(), never stage(): the sweep is the only input.
        local quiet = t:sweep(0, { { id = 9, name = "Walkin", inWorld = true } })
        T.eq(#quiet, 0, "the clock starts when we first see them")
        local actions = t:sweep(50, { { id = 9, name = "Walkin", inWorld = true } })
        T.eq(#actions, 1); T.eq(actions[1].kind, "advise"); T.eq(actions[1].warned, 1)
        T.eq(actions[1].terminal, false, "no stage evidence: slow, not failed")
    end,

    healthy_player_is_never_warned = function(T)
        local t = tracker(T)
        t:connected(1, 0, "Owner")
        t:ready(1, 8)
        for now = 5, 600, 5 do
            T.eq(#t:sweep(now, { { id = 1, inWorld = true } }), 0, "quiet at " .. now .. "s")
        end
    end,

    ready_without_a_body_is_still_limbo = function(T)
        local t = tracker(T)
        t:connected(2, 0, "Barrier")
        t:ready(2, 3)   -- the hold lifted; the puppet never arrived
        local a = t:sweep(45, { { id = 2, inWorld = false } })
        T.eq(#a, 1); T.eq(a[1].kind, "advise"); T.ok(a[1].ready); T.eq(a[1].inWorld, false)
    end,

    cadence_is_first_then_repeat_then_give_up = function(T)
        local t = tracker(T, { firstWarnS = 45, repeatS = 60, giveUpS = 300 })
        t:connected(3, 0, "Slow")
        local advised, gaveUp = 0, 0
        for now = 5, 400, 5 do
            for _, a in ipairs(t:sweep(now, { { id = 3, inWorld = false } })) do
                if a.kind == "advise" then advised = advised + 1 end
                if a.kind == "gaveup" then gaveUp = gaveUp + 1 end
            end
        end
        T.eq(advised, 5, "45s, then every 60s, and nothing after give-up")
        T.eq(gaveUp, 1, "give up exactly once")
    end,

    terminal_is_advised_promptly_not_after_the_full_grace = function(T)
        local t = tracker(T, { firstWarnS = 45, terminalGraceS = 10 })
        t:connected(4, 0, "Failed")
        t:stage(4, "appearance_failed", 5, 5)
        T.eq(#t:sweep(9, { { id = 4, inWorld = true } }), 0)
        local a = t:sweep(12, { { id = 4, inWorld = true } })
        T.eq(#a, 1); T.eq(a[1].kind, "advise"); T.ok(a[1].terminal)
        -- ...and then settles onto the ordinary repeat cadence rather than every sweep.
        T.eq(#t:sweep(20, { { id = 4, inWorld = true } }), 0)
    end,

    unknown_stage_strings_are_ignored = function(T)
        local t = tracker(T)
        t:connected(5, 0, "Liar")
        T.eq(t:stage(5, "totally_fine", 1, 1), nil)
        T.eq(t:stage(5, 42, 1, 1), nil)
        t:ready(5, 2)
        T.eq(#t:sweep(120, { { id = 5, inWorld = true } }), 0, "a forged stage must not create limbo")
    end,

    a_stale_stage_report_is_not_evidence_about_now = function(T)
        local t = tracker(T, { staleStageS = 45 })
        t:connected(7, 0, "Recovering")
        t:stage(7, "appearance_applying", 10, 10)
        t:ready(7, 12)
        T.eq(t:state(7, 20, true).playable, false, "fresh stage report overrides the position")
        T.eq(t:state(7, 100, true).playable, true, "an old report says nothing about now")
    end,

    recovery_is_reported_and_resets_the_clock = function(T)
        local t = tracker(T)
        t:connected(8, 0, "Retry")
        T.eq(#only(T, t:sweep(50, { { id = 8, inWorld = false } }), "advise"), 1)
        t:ready(8, 55)
        local a = t:sweep(60, { { id = 8, inWorld = true } })
        T.eq(#a, 1); T.eq(a[1].kind, "recovered"); T.eq(a[1].waited, 60)
        T.eq(#t:sweep(65, { { id = 8, inWorld = true } }), 0, "reported once, not every sweep")
        T.eq(t:state(8, 400, true).warned, 0, "the limbo clock is reset, not merely silenced")
    end,

    adoption_across_a_resource_restart_does_not_warn_a_healthy_server = function(T)
        local t = tracker(T)
        -- onPlayerReady will never fire again for someone who was already connected.
        t:adopt(11, 0, "WasHere")
        T.eq(#t:sweep(120, { { id = 11, inWorld = true } }), 0)
        -- ...but a platform stage report still overrides the presumption.
        t:stage(11, "player_reset", 125, 60)
        T.eq(t:state(11, 130, true).playable, false, "the stage report beats the presumption")
        T.eq(#t:sweep(130, { { id = 11, inWorld = true } }), 0,
            "a player who regresses gets a fresh grace, not an instant nag")
        -- The shell keeps heartbeating and never completes: eventually somebody has to be told.
        local first
        for now = 135, 320, 5 do
            t:stage(11, "player_reset", now, now)
            for _, a in ipairs(t:sweep(now, { { id = 11, inWorld = true } })) do
                if a.kind == "advise" and not first then first = a end
            end
        end
        T.ok(first, "a genuinely stuck adopted player is still caught")
        T.eq(first.stage, "player_reset")
        T.ok(first.waited >= 90, "and only after the progressing grace")
    end,

    leaving_while_warned_is_recorded_and_the_entry_is_dropped = function(T)
        local t = tracker(T)
        t:connected(12, 0, "Gone")
        t:stage(12, "appearance_failed", 15, 15)
        t:sweep(30, { { id = 12, inWorld = true } })
        local departure = t:forget(12, 90)
        T.ok(departure); T.eq(departure.id, 12); T.eq(departure.waited, 90); T.ok(departure.terminal)
        T.eq(#t:all(), 0)
        T.eq(t:forget(12, 95), nil, "forgetting twice is not an event")
    end,

    a_quiet_player_leaving_is_not_an_event = function(T)
        local t = tracker(T)
        t:connected(13, 0, "Fine"); t:ready(13, 1)
        t:sweep(5, { { id = 13, inWorld = true } })
        T.eq(t:forget(13, 10), nil)
    end,

    sweep_reaps_players_whose_disconnect_we_missed = function(T)
        local t = tracker(T)
        t:connected(14, 0, "Dropped")
        t:sweep(50, { { id = 14, inWorld = false } })
        local a = t:sweep(60, {})
        T.eq(#a, 1); T.eq(a[1].kind, "vanished"); T.eq(a[1].id, 14)
        T.eq(#t:all(), 0)
        T.eq(#t:sweep(65, {}), 0)
    end,

    a_reused_player_id_starts_clean = function(T)
        local t = tracker(T)
        t:connected(15, 0, "First")
        t:stage(15, "appearance_failed", 10, 10)
        t:sweep(30, { { id = 15, inWorld = true } })
        t:connected(15, 100, "Second")   -- same slot, different person
        local st = t:state(15, 100, true)
        T.eq(st.name, "Second"); T.eq(st.warned, 0); T.eq(st.stage, nil); T.eq(st.waited, 0)
        T.eq(#t:sweep(105, { { id = 15, inWorld = true } }), 0)
    end,

    sweep_is_ordered_and_tolerates_junk_rows = function(T)
        local t = tracker(T)
        local a = t:sweep(0, { { id = 3 }, "nonsense", { id = 1 }, { }, { id = 3, inWorld = true } })
        T.eq(#a, 0)
        local ids = t:all()
        T.eq(#ids, 2); T.eq(ids[1], 1); T.eq(ids[2], 3)
        local warned = t:sweep(50, { { id = 3, inWorld = false }, { id = 1, inWorld = false } })
        T.eq(#warned, 2); T.eq(warned[1].id, 1); T.eq(warned[2].id, 3)
    end,
}
