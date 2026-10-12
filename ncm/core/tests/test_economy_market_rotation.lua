-- 2026-10-12 markets overhaul: rotating autofixer line-ups, responsive supply, markdown; cars on the Exchange.
return {
    the_rotation_widens_every_autofixer_and_still_validates = function(T)
        local P = T.Core.get("economy.production")
        local added = P.rotate("tapeC#run9")
        T.ok(added > 20, "lines were added across the autofixers")
        local authored, rotating = 0, 0
        for _, l in ipairs(P.LINES) do
            if l.marketId == "autofixer_badlands_07" then
                if l.rotating then rotating = rotating + 1 else authored = authored + 1 end
            end
        end
        T.eq(authored, 2)
        T.eq(rotating, P.ROTATION_SIZE)
        local ok, why = P.validate()
        T.ok(ok, tostring(why))
    end,

    the_rotation_is_deterministic_per_key_and_moves_between_weeks = function(T)
        local P = T.Core.get("economy.production")
        local function lineup(key)
            P.rotate(key)
            local out = {}
            for _, l in ipairs(P.LINES) do if l.rotating and l.marketId == "autofixer_glen_01" then out[#out + 1] = l.vehicleKey end end
            return table.concat(out, ",")
        end
        local a1 = lineup("tapeA#run1")
        local b = lineup("tapeA#run2")
        local a2 = lineup("tapeA#run1")
        T.eq(a1, a2, "same tape and Week, same line-up")
        T.ok(a1 ~= b, "a new Week, a new line-up")
    end,

    rotation_keeps_classes_and_never_doubles_a_model = function(T)
        local P = T.Core.get("economy.production")
        local Cat = T.Core.get("data.vehicle_catalogue")
        local M = T.Core.get("economy.markets")
        P.rotate("tapeB#run3")
        for _, market in ipairs(M.MARKETS) do
            if market.kind == "autofixer" and market.vehicles then
                local classes, seen = {}, {}
                for _, k in ipairs(market.vehicles) do classes[(Cat.byKey(k) or {}).category or ""] = true end
                for _, l in ipairs(P.LINES) do
                    if l.marketId == market.marketId then
                        T.ok(not seen[l.vehicleKey], market.marketId .. " sells " .. l.vehicleKey .. " once")
                        seen[l.vehicleKey] = true
                        if l.rotating then T.ok(classes[Cat.byKey(l.vehicleKey).category], l.vehicleKey .. " fits the shop") end
                    end
                end
            end
        end
    end,

    wanted_cars_restock_in_hours_and_halo_cars_stay_scarce = function(T)
        local P = T.Core.get("economy.production")
        local type66 = P.autofixerLine("autofixer_badlands_07", "quadra_type66")
        T.eq(type66.profile, "volume_responsive")
        T.ok(type66.envelope.intervalMin <= 3600 and type66.ceiling >= 2, "Type-66 can come back within the hour")
        local halo = nil
        for _, e in ipairs(T.Core.get("data.vehicle_catalogue").entries()) do if e.prestige == 5 then halo = e.vehicleKey break end end
        T.eq(P.autofixerLine("autofixer_japantown_01", halo).profile, "scarcity_keeper")
    end,

    dead_stock_comes_down_but_not_below_sixty_percent = function(T)
        local P = T.Core.get("economy.production")
        T.eq(P.markdown(10000, 3600), 10000, "a fresh car asks full price")
        T.eq(P.markdown(10000, 24 * 3600), 9200, "after a day, 8 % off")
        T.eq(P.markdown(10000, 30 * 24 * 3600), 6000, "never below 60 %")
    end,

    a_car_is_offered_on_the_exchange_and_moves_as_a_car = function(T)
        local EX = T.Core.get("economy.exchange_posts")
        T.ok(EX.validatePost({ kind = "offer", assetKind = "vehicle", principal = "person:p1", assetId = "car-1", cash = 9000 }))
        local ok, why = EX.validatePost({ kind = "want", assetKind = "vehicle", principal = "person:p1", family = "brakes", tier = "street", cash = 9000 })
        T.eq(ok, nil); T.eq(why, "cars_are_offered_not_wanted")
        local legs = EX.legs({ kind = "offer", assetKind = "vehicle", assetId = "car-1", principal = "person:p1" },
            { principal = "driver:d1", cash = 8500 })
        T.eq(legs.assets[1].kind, "vehicle")
        T.eq(legs.cash.amount, 8500)
        T.eq(legs.cash.from, "driver:d1")
    end,

    a_used_car_asks_less_with_distance_and_damage_and_marks_down = function(T)
        local EX = T.Core.get("economy.exchange_posts")
        local fresh = EX.usedAsk(10000, 0, 0)
        T.eq(fresh, 7800)
        T.ok(EX.usedAsk(10000, 150000 * 1000, 0) < fresh * 0.7, "a worn-out odometer costs")
        T.ok(EX.usedAsk(10000, 0, 1) < fresh * 0.5, "a wreck costs")
        T.eq(EX.markdown(8000, 11 * 3600), 8000)
        T.eq(EX.markdown(8000, 12 * 3600), 7360)
        T.eq(EX.markdown(8000, 100 * 24 * 3600), 4000, "never below half")
    end,

    npcs_bid_only_on_better_cars_they_can_afford = function(T)
        local EX = T.Core.get("economy.exchange_posts")
        T.eq(EX.npcCarBid(10000, 3, 2, 20000), 9200)
        T.eq(EX.npcCarBid(10000, 2, 2, 20000), nil, "not a better car")
        T.eq(EX.npcCarBid(10000, 4, 2, 15000), nil, "too much of its cash")
    end,
}
