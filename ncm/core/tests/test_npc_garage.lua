-- economy.npc_garage (L298): an NPC's race car as a real car -- the owner's chain, link by link.
local STREET = { classes = { "Muscle", "Sport", "Tech" }, prestigeMax = 2 }

local function factory()
    local out = {}
    for _, f in ipairs({ "power_unit", "cooling", "transmission", "drivetrain", "tires", "brakes", "suspension",
        "electrical", "aerodynamics", "structure", "chassis" }) do out[#out + 1] = { family = f, effect = 1.0, wear = 1 } end
    return out
end
local function with(list, family, effect, wear)
    for _, p in ipairs(list) do if p.family == family then p.effect, p.wear = effect, wear or 1 end end
    return list
end

return {
    an_independent_owns_their_own_model = function(T)
        local G = T.Core.get("economy.npc_garage")
        local models = G.modelsFor(STREET)
        T.ok(#models >= 4, "the street band has several catalogue models: " .. #models)
        local seen = {}
        for i = 1, 40 do seen[G.startingModel(STREET, 7, "person", ("p%05d"):format(i)).vehicleKey] = true end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        T.ok(n >= 3, "forty independents do not all drive one car (KB-313: they all hashed 'none'): " .. n .. " models")
        T.eq(G.startingModel(STREET, 7, "org", "o001").vehicleKey, G.startingModel(STREET, 7, "org", "o001").vehicleKey, "a team's model is stable")
        for _, m in ipairs(models) do T.ok(m.prestige <= 2, "inside the band") end
    end,

    sport_brakes_change_that_car = function(T)
        -- "If Cesar buys sport brakes ... alter that car's drive/brake/grip characteristics"
        local G = T.Core.get("economy.npc_garage")
        local before = G.levels(2, factory())
        local after = G.levels(2, with(factory(), "brakes", 1.18))
        T.ok(after.tires > before.tires, "the tyres-and-brakes area rises")
        T.eq(after.power_unit, before.power_unit, "and nothing else")
        local lb, la = G.levers(factory()), G.levers(with(factory(), "brakes", 1.18))
        T.ok(la.brakeScale > lb.brakeScale, "the player formula's brake lever rises too")
    end,

    wear_takes_it_back = function(T)
        local G = T.Core.get("economy.npc_garage")
        local fresh = G.levels(2, with(factory(), "tires", 1.18, 1))
        local worn = G.levels(2, with(factory(), "tires", 1.18, 0.8))
        T.ok(worn.tires < fresh.tires, "worn tyres are worth less than new ones")
        local W = T.Core.get("parts.wear")
        local p = { asset_id = "a1", family = "tires", exposure_m = 0 }
        T.eq(G.wearFactor(p, {}), 1, "a new tyre is whole")
        p.exposure_m = 50000000
        T.ok(G.wearFactor(p, {}) < 0.9, "fifty thousand km of racing is not")
        T.ok(W.evaluate(p, {}).status ~= "normal")
    end,

    only_compatible_strict_upgrades_are_bought = function(T)
        local G = T.Core.get("economy.npc_garage")
        T.ok(G.isUpgrade(1.0, { effect = 1.18 }), "sport over factory")
        T.falsy(G.isUpgrade(1.18, { effect = 1.08 }), "never a street part beside a sport one (p01226)")
        T.falsy(G.isUpgrade(1.08, { effect = 1.08 }), "never the same part again (the restart re-buys)")
        T.ok(G.fits("launch:brakes:street", "makigai_maimai"), "a launch street part fits the starter cars")
        T.falsy(G.fits("launch:brakes:sport", "makigai_maimai"), "the sport brakes are Galena/Hella only")
    end,

    the_racer_variant_follows_the_parts = function(T)
        local G = T.Core.get("economy.npc_garage")
        T.eq(G.variant(factory()), 0, "a factory car is the base racer")
        local built = factory()
        for _, f in ipairs({ "power_unit", "transmission", "drivetrain", "brakes", "tires" }) do with(built, f, 1.30) end
        T.ok(G.variant(built) >= 2, "a premium drivetrain and brakes are a faster racer: v" .. G.variant(built))
        T.eq(G.racerRecord("Vehicle.v_standard2_villefort_cortes", 0), "Vehicle.ncm_racer_v_standard2_villefort_cortes")
        T.eq(G.racerRecord("Vehicle.v_standard2_villefort_cortes", 2), "Vehicle.ncm_racer_v_standard2_villefort_cortes_v2")
        T.eq(G.racerRecord("Vehicle.v_standard2_villefort_cortes", 1, true), "Vehicle.ncm_racer_oval_v_standard2_villefort_cortes_v1", "an oval races its own profile")
    end,

    goals_put_worn_parts_first = function(T)
        local G = T.Core.get("economy.npc_garage")
        local W = T.Core.get("parts.wear")
        local worn = { assetId = "b1", asset_id = "b1", family = "brakes", exposure_m = 60000000, effect = 1.0, services = {} }
        worn.state = W.evaluate(worn, {})
        local goals = G.goals({ worn }, G.levels(2, factory()))
        T.ok(goals[1].kind == G.REASON.SERVICE or goals[1].kind == G.REASON.REPLACE, "the worn brakes come first: " .. tostring(goals[1].kind))
        T.eq(goals[#goals].kind, G.REASON.UPGRADE, "then the weakest area")
    end,

    money_is_bounded = function(T)
        local G = T.Core.get("economy.npc_garage")
        local F = T.Core.get("paddock.finance")
        local p = F.purse("street", 12)
        local avg = 0
        for _, v in ipairs(p) do avg = avg + v end
        avg = avg / 12
        T.ok(avg - G.entryFee("street") > 50, "a street independent can live on racing: avg purse " .. math.floor(avg))
        T.ok(G.repairCost(10000, 0.5, false) > 0 and G.repairCost(10000, 1, true) > G.repairCost(10000, 1, false), "a wreck costs a tow")
    end,
}
