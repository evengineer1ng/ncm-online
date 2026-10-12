-- week.collapse (L303): what survives a Racing Week.
return {
    archive_keys_namespace_a_run = function(T)
        local K = T.Core.get("week.collapse")
        T.eq(K.archiveKey("ncm-dev", 7), "ncm-dev#R007")
    end,

    anchor_slots_grow_with_history = function(T)
        local K = T.Core.get("week.collapse")
        T.eq(K.anchorSlots({}), 1)
        T.eq(K.anchorSlots({ day3Finish = true }), 2)
        T.eq(K.anchorSlots({ day3Finish = true, premierStart = true }), 3)
        T.eq(K.anchorSlots({ premierStart = true }), 2)
    end,

    chosen_anchors_first_default_is_the_most_raced = function(T)
        local K = T.Core.get("week.collapse")
        local cars = {
            { assetId = "a", races = 3, odometerM = 9000 },
            { assetId = "b", races = 12, odometerM = 100 },
            { assetId = "c", races = 12, odometerM = 500 },
            { assetId = "galena", races = 2, conditionGrant = true, sanctionedWins = 0 },
        }
        local d = K.anchors(cars, {}, 1)
        T.eq(#d, 1); T.eq(d[1].assetId, "c"); T.eq(d[1].source, "default")
        local ch = K.anchors(cars, { "a", "b" }, 1)
        T.eq(#ch, 1); T.eq(ch[1].assetId, "a"); T.eq(ch[1].source, "chosen")
        local two = K.anchors(cars, { "a", "b", "c" }, 2)
        T.eq(#two, 2)
        local g, refused = K.anchors(cars, { "galena" }, 1)
        T.eq(#refused, 1, "a condition grant without a win cannot be saved")
        T.eq(g[1].assetId, "c", "... so the default applies")
        cars[4].sanctionedWins = 1
        local saved = K.anchors(cars, { "galena" }, 1)
        T.eq(saved[1].assetId, "galena", "anchor_if_won: the Galena story")
        T.eq(#K.anchors({}, {}, 3), 0, "no cars, no anchors")
    end,

    online_keeps_one_chosen_or_last_driven_car = function(T)
        local K = T.Core.get("week.collapse")
        local cars = {
            { assetId = "old", races = 20, lastDrivenAt = 100 },
            { assetId = "recent", races = 1, lastDrivenAt = 200 },
            { assetId = "grant", lastDrivenAt = 300, conditionGrant = true, sanctionedWins = 0 },
        }
        local auto = K.onlineAnchor(cars, {})
        T.eq(#auto, 1); T.eq(auto[1].assetId, "recent"); T.eq(auto[1].source, "last_driven")
        local chosen = K.onlineAnchor(cars, { "old", "recent" })
        T.eq(#chosen, 1); T.eq(chosen[1].assetId, "old")
        local fallback, refused = K.onlineAnchor(cars, { "grant" })
        T.eq(#refused, 1); T.eq(fallback[1].assetId, "recent")
        T.eq(#K.onlineAnchor({ { assetId = "unseen", races = 99 } }, {}), 0)
    end,

    sr_halves_toward_neutral_and_wallets_reset = function(T)
        local K = T.Core.get("week.collapse")
        T.eq(K.srReset(1.0), 3.0)
        T.eq(K.srReset(9.0), 7.0)
        T.eq(K.srReset(5.0), 5.0)
        local w = K.wallet(48250, 10000)
        T.eq(w.close, -48250); T.eq(w.open, 10000)
        T.eq(K.wallet(-300, 10000).close, 300, "a debt is closed too")
    end,

    paddock_moves_keep_what_was_learned = function(T)
        local K = T.Core.get("week.collapse")
        local m = K.paddockMoves({ "paddock_world", "paddock_calibration", "paddock_result", "paddock_place_check", "vehicle_asset" })
        T.eq(#m, 2); T.eq(m[1], "paddock_result"); T.eq(m[2], "paddock_world")
    end,
}
