return {
    public_projection_is_small_and_unavailable_not_zero = function(T)
        local P = T.Core.get("driver.presentation")
        local ent = P.entitlements({ "first_finish" })
        local p = P.publicProjection({ bannerId = "ncm_default", displayedBadgeIds = { "first_finish" } }, ent)
        T.eq(p.schemaVersion, 1); T.eq(p.bannerId, "ncm_default")
        T.eq(#p.displayedBadgeIds, 1); T.eq(p.displayedBadgeIds[1], "first_finish")
        T.eq(p.fingerprint.sampleState, "unavailable"); T.eq(p.fingerprint.definitionVersion, 0)
        T.eq(#p.fingerprint.values, 0)
        T.eq(p.driverId, nil); T.eq(p.history, nil); T.eq(p.telemetry, nil); T.eq(p.machines, nil)
        T.eq(p.marketKnowledge, nil); T.eq(p.engineeringKnowledge, nil); T.eq(p.onboarding, nil)
    end,

    definitions_entitlements_and_selection_are_distinct = function(T)
        local P = T.Core.get("driver.presentation")
        T.ok(P.BADGES.first_win ~= nil)
        local none = P.entitlements({})
        T.eq(none.badges.first_win, nil)
        local earned = P.entitlements({ "first_win" })
        T.eq(earned.badges.first_win, true)
        local selected = P.validateSelection({ bannerId = "ncm_default", displayedBadgeIds = { "first_win" } }, earned)
        T.eq(selected.displayedBadgeIds[1], "first_win")
        T.eq(earned.badges.first_win, true, "selection does not mutate entitlement")
    end,

    badge_selection_is_bounded_and_deduplicated = function(T)
        local P = T.Core.get("driver.presentation")
        local ent = P.entitlements({}, { development = true })
        local tooMany, reason = P.validateSelection({ displayedBadgeIds = {
            "dev_slot_1", "dev_slot_2", "dev_slot_3", "first_finish",
        } }, ent)
        T.eq(tooMany, nil); T.eq(reason, "too_many_badges")
        local duplicate, why = P.validateSelection({ displayedBadgeIds = { "dev_slot_1", "dev_slot_1" } }, ent)
        T.eq(duplicate, nil); T.eq(why, "duplicate_badge")
    end,

    invalid_or_unentitled_assets_fall_back_in_public_projection = function(T)
        local P = T.Core.get("driver.presentation")
        local ent = P.entitlements({})
        local p = P.publicProjection({ bannerId = "missing", displayedBadgeIds = { "missing", "first_win" } }, ent)
        T.eq(p.bannerId, P.DEFAULT_BANNER_ID); T.eq(#p.displayedBadgeIds, 0)
    end,

    client_sanitizer_drops_private_and_fabricated_fields = function(T)
        local P = T.Core.get("driver.presentation")
        local p = P.sanitizePublicProjection({
            bannerId = "missing", displayedBadgeIds = { "first_win", "missing", "first_finish", "first_time_trial", "dev_slot_1" },
            fingerprint = { definitionVersion = 99, values = { 1, 1, 1, 1, 1, 1 }, sampleState = "ready" },
            telemetry = { secret = true }, history = { "private" },
        })
        T.eq(p.bannerId, P.DEFAULT_BANNER_ID); T.eq(#p.displayedBadgeIds, 3)
        T.eq(p.fingerprint.sampleState, "unavailable"); T.eq(p.fingerprint.definitionVersion, 0)
        T.eq(#p.fingerprint.values, 0); T.eq(p.telemetry, nil); T.eq(p.history, nil)
    end,

    development_badges_are_not_normal_entitlements = function(T)
        local P = T.Core.get("driver.presentation")
        T.eq(P.entitlements({}).badges.dev_slot_1, nil)
        T.eq(P.entitlements({}, { development = true }).badges.dev_slot_1, true)
        T.eq(P.entitlements({}).banners.ncm_development, nil)
        T.eq(P.entitlements({}, { development = true }).banners.ncm_development, true)
        T.eq(P.BANNERS.ncm_default.image, "assets/banners/ncm-default.svg")
        T.eq(P.BANNERS.ncm_development.crop, "58% 50%")
    end,

    modern_axes_are_direction_only_not_a_fake_definition = function(T)
        local P = T.Core.get("driver.presentation")
        T.eq(P.FINGERPRINT_DIRECTION.status, "direction_only")
        T.eq(table.concat(P.FINGERPRINT_DIRECTION.axes, ","),
            "competition,street,engineering,commerce,culture,intensity")
        local p = P.publicProjection({}, P.entitlements({}))
        T.eq(p.fingerprint.definitionVersion, 0); T.eq(#p.fingerprint.values, 0)
    end,
}
