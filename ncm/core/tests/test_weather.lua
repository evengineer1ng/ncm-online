local W = NcmCore.get("world.weather")

local policy = { version=1, transitionSec=30, states={
    {weather="sunny", weight=3, minDurationSec=600, maxDurationSec=1200},
    {weather="cloudy", weight=2, minDurationSec=600, maxDurationSec=1200},
    {weather="rain", weight=1, minDurationSec=300, maxDurationSec=600},
} }

return {
    validates_policy = function(T)
        T.ok(W.validatePolicy(policy)); local ok, why = W.validatePolicy{version=1, states={}}
        T.eq(ok, false); T.eq(why, "states_required")
    end,
    generation_is_deterministic = function(T)
        local a = W.generate{policy=policy, startsAtUtc=1000, untilUtc=10000, seed=77, epoch="wx"}
        local b = W.generate{policy=policy, startsAtUtc=1000, untilUtc=10000, seed=77, epoch="wx"}
        T.eq(#a.rows, #b.rows); T.eq(a.coveredUntilUtc, b.coveredUntilUtc)
        for i=1,#a.rows do T.eq(a.rows[i].id,b.rows[i].id); T.eq(a.rows[i].weather,b.rows[i].weather); T.eq(a.rows[i].startsAtUtc,b.rows[i].startsAtUtc) end
    end,
    extension_preserves_published_rows = function(T)
        local a = W.generate{policy=policy, startsAtUtc=1000, untilUtc=5000, seed=19, epoch="wx"}
        local old = #a.rows; local b = W.extend(a, policy, 15000)
        T.ok(#b.rows > old); for i=1,old do T.eq(b.rows[i].id,a.rows[i].id); T.eq(b.rows[i].weather,a.rows[i].weather) end
        T.eq(#a.rows, old, "input remains immutable")
    end,
    forecast_uses_time_bands_and_ordinal_confidence = function(T)
        local p = W.generate{policy=policy, startsAtUtc=1000, untilUtc=200000, seed=5, epoch="wx"}
        local f = W.forecast(p, 1000, {horizonSec=100000, confidence={highSec=3600, mediumSec=20000}})
        T.eq(f[1].kind,"OBSERVED"); T.eq(f[1].confidence,"HIGH"); T.ok(f[#f].confidence == "LOW")
        for _,x in ipairs(f) do T.ok(x.toUtc > x.fromUtc); T.ok(x.family ~= nil) end
    end,
    provenance_accounts_for_whole_session = function(T)
        local rows = {
            {id="a",startsAtUtc=100,weather="sunny",transitionSec=0},
            {id="b",startsAtUtc=160,weather="rain",transitionSec=20},
            {id="c",startsAtUtc=220,weather="fog",transitionSec=20},
        }
        local p = W.provenance(rows,130,250,"default",{a=7,b=8,c=9})
        T.eq(p.start.weather,"sunny"); T.eq(p.finish.weather,"fog"); T.eq(#p.transitions,2)
        T.eq(p.durationByFamilySec.dry,30); T.eq(p.durationByFamilySec.wet,60); T.eq(p.durationByFamilySec.obscured,30)
    end,
    for_event_answers_the_guides_question_not_just_the_start_instant = function(T)
        -- IDEA-133 / the Race Guide brief: "a race beginning at 15:55 with rain expected at 16:03 is not simply
        -- a dry race forecast." Start-instant lookup cannot say that; overlapping the window can.
        local W = T.Core.get("world.weather")
        local fc = {
            { fromUtc = 0,    toUtc = 1000, weather = "cloudy", family = "dry", confidence = "HIGH", kind = "OBSERVED" },
            { fromUtc = 1000, toUtc = 5000, weather = "rain",   family = "wet", confidence = "MED",  kind = "FORECAST" },
            { fromUtc = 5000, toUtc = 9000, weather = "sunny",  family = "dry", confidence = "LOW",  kind = "OUTLOOK" },
        }
        -- starts in the dry band, ends inside the rain band
        local r = W.forEvent(fc, 900, 1500)
        T.eq(r.atStart.weather, "cloudy"); T.eq(r.changes, true, "rain arrives during the event")
        T.eq(r.windowKnown, true)
        T.eq(r.confidence, "MED", "the weakest band over the window, not the start's own confidence")
        T.eq(#r.bands, 2)

        -- entirely inside one band: stable
        local stable = W.forEvent(fc, 1200, 1400)
        T.eq(stable.changes, false); T.eq(stable.atStart.weather, "rain"); T.eq(stable.confidence, "MED")

        -- no duration known: honest about it rather than guessing a length
        local noWindow = W.forEvent(fc, 900)
        T.eq(noWindow.windowKnown, false)
        T.eq(noWindow.atStart.weather, "cloudy")
        T.eq(noWindow.changes, false, "with no window there is nothing to change within")
        T.eq(noWindow.transitionNearStart, 1000, "but a transition 100s away is still worth flagging")

        -- beyond the forecast horizon, and empty input: absent, never invented
        T.eq(W.forEvent(fc, 99999), nil, "past the bands is unknown, not sunny")
        T.eq(W.forEvent({}, 900), nil)
        T.eq(W.forEvent(nil, 900), nil)
        T.eq(W.forEvent(fc, nil), nil)
    end,

    for_event_never_mutates_the_forecast = function(T)
        local W = T.Core.get("world.weather")
        local fc = { { fromUtc = 0, toUtc = 1000, weather = "rain", family = "wet", confidence = "HIGH", kind = "FORECAST" } }
        local before = T.show(fc)
        W.forEvent(fc, 500, 800)
        T.eq(T.show(fc), before)
    end,
}
