return {
    ["every deck grade is cosmetic, nonlethal and harmless to the person"] = function(T)
        local C = T.Core.get("competition.chrome")
        local def = C.deckDefinition()
        T.eq(def.id, C.DECK_ID)
        T.eq(#def.grades, #C.deckHacks())
        for _, g in ipairs(def.grades) do
            T.eq(g.cosmetic, true, g.id); T.eq(g.nonlethal, true, g.id); T.eq(g.damage, 0, g.id)
            T.eq(g.statusMs, 0, g.id)
            T.eq(g.range >= 1 and g.range <= 80, true, g.id .. " range within the platform's 1..80 m")
            T.eq(g.uploadMs >= 500 and g.uploadMs <= 15000, true, g.id .. " upload within 500..15000 ms")
            T.eq(g.recoveryMs >= g.statusMs + 500, true, g.id .. " recovery >= status + 500")
        end
    end,

    ["the implants mirror the definitions grade for grade"] = function(T)
        local C = T.Core.get("competition.chrome")
        local implants = C.implants()
        T.eq(#implants, 3)
        T.eq(implants[1].slot, "operating_system")
        T.eq(#implants[1].grades, #C.deckDefinition().grades)
        for i, g in ipairs(implants[1].grades) do T.eq(g.id, C.deckDefinition().grades[i].id) end
        T.eq(implants[2].slot, "self_ice"); T.eq(implants[3].slot, "purge")
    end,

    ["the whole owner roster exists"] = function(T)
        local C = T.Core.get("competition.chrome")
        for _, id in ipairs({ "limiter", "engine_cut", "limp", "tire_sabotage", "power_surge", "overclock",
                              "self_ice", "purge", "ally_purge", "system_restore", "blackout", "total_failure" }) do
            T.eq(C.hack(id) ~= nil, true, id)
        end
    end,

    ["caps are most-restrictive-wins fractions of the authored baseline, and expire"] = function(T)
        local C = T.Core.get("competition.chrome")
        local effects = {
            { hack = "limiter", startedAt = 0, endsAt = 8000 },
            { hack = "limp", startedAt = 0, endsAt = 12000 },
        }
        T.eq(C.capFactor(effects, 1000), 0.35)
        T.eq(C.capKph(effects, 1000, 151), 53)
        T.eq(C.capKph(effects, 9000, 151), 53, "LIMP outlives LIMITER")
        T.eq(C.capKph({ effects[1] }, 1000, 151), 106)
        T.eq(C.capKph(effects, 13000, 151), nil)
        T.eq(C.capKph(effects, 1000, nil), nil, "no authored baseline, no invented cap")
    end,

    ["surge and overclock push the chrome layer above parts, multiplicatively"] = function(T)
        local C = T.Core.get("competition.chrome")
        local h = C.handling({ { hack = "power_surge", startedAt = 0, endsAt = 5000 } }, 100)
        T.eq(h.driveScale, 1.6); T.eq(h.gripScale, 0.8); T.eq(h.topSpeedScale, 1.15); T.eq(h.source, "chrome")
        T.eq(C.handling({ { hack = "engine_cut", startedAt = 0, endsAt = 5000 } }, 100), nil)
        T.eq(C.handling({ { hack = "limiter", startedAt = 0, endsAt = 5000 } }, 100).driveScale, 0.6)
        local both = C.handling({ { hack = "power_surge", endsAt = 9e9 }, { hack = "overclock", endsAt = 9e9 } }, 0)
        T.eq(math.abs(both.driveScale - 3.2) < 1e-9, true, "composed; the lever clamp bounds it downstream")
    end,

    ["admission says why, distinctly"] = function(T)
        local C = T.Core.get("competition.chrome")
        T.eq(select(2, C.admit({ hack = "nope" })), "unknown_hack")
        T.eq(select(2, C.admit({ hack = "self_ice" })), "passive")
        T.eq(select(2, C.admit({ hack = "limiter", ownVehicle = 1 })), "no_target")
        T.eq(select(2, C.admit({ hack = "limiter", ownVehicle = 1, targetVehicle = 1, distance = 5 })), "own_vehicle")
        T.eq(select(2, C.admit({ hack = "limiter", ownVehicle = 1, targetVehicle = 2, distance = 61 })), "out_of_range")
        T.eq(select(2, C.admit({ hack = "limiter", ownVehicle = 1, targetVehicle = 2, distance = 20, targetBound = true,
            cooldownUntil = 10, now = 5 })), "cooling_down")
        T.eq(select(2, C.admit({ hack = "limiter", ownVehicle = 1, targetVehicle = 2, distance = 20 })),
            "needs_driven_ncm_machine", "governor hacks need a Carrier-bound machine")
        T.eq(C.admit({ hack = "limiter", ownVehicle = 1, targetVehicle = 2, distance = 20, targetBound = true }).id,
            "limiter")
        T.eq(C.admit({ hack = "engine_cut", ownVehicle = 1, targetVehicle = 2, distance = 20 }).id, "engine_cut",
            "native-lever hacks work on AI traffic")
        T.eq(select(2, C.admit({ hack = "purge" })), "not_in_a_vehicle")
        T.eq(C.admit({ hack = "purge", ownVehicle = 3 }).id, "purge")
        T.eq(C.admit({ hack = "blackout", targetVehicle = 2, distance = 20 }).id, "blackout",
            "on foot you can still hack a car")
    end,
}
