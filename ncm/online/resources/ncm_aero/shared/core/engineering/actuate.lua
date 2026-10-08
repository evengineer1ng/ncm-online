-- ncm-core module: engineering.actuate
--
-- How today's runtime is made to EXPRESS a build's physical state (L314: cause, actuator, state, coarse model
-- are four separate things). This module reads `engineering.fit`'s `state` and never writes it back:
-- **NCM's canonical physical state records the modelled mass whatever the hookup** (L314 R3). If the model
-- says 1,947 kg, the state says 1,947 kg, and this module says how closely the runtime can show it and what
-- it cannot.
--
-- Mass has two channels, chosen by E1 (doc 50 Â§1, MASTER_TEST Â§EN1):
--   * `record`   -- the drive model's `.total_mass` / `.chassis_mass` through Carrier's record channel. Real
--                   physics if E1 is positive; spawn-cached; bounded by `machine.flats` (0.70-1.40).
--   * `instance` -- the approximation: drive and brake scaled by m0 / m. Heavier only (Carrier's live levers
--                   only scale down). No weight transfer, no collision mass; listed in `losses`.
local Core = NcmCore

Core.define("engineering.actuate", function(C)
    local M = { version = "0.1.1" }

    local flats = C.get("machine.flats")

    M.INSTANCE_LOSSES = {
        "no weight transfer (pitch and roll unchanged)",
        "no collision mass (contacts behave as the stock car)",
        "cornering unchanged (friction scales with load, to first order)",
        "lighter than stock cannot be expressed (live levers only scale down)",
    }

    function M.mass(state, channel)
        local stock, m = state.stockMassKg, state.massKg
        local out = { channel = channel, stateKg = m, expressedKg = m, unexpressedKg = 0, losses = {} }
        if not stock or stock <= 0 then
            out.channel, out.losses = "none", { "no stock mass to express against" }
            out.expressedKg, out.unexpressedKg = stock or 0, m - (stock or 0)
            return out
        end
        local ratio = m / stock
        if channel == "record" then
            local f = flats.get("mass")
            local r = math.max(f.min, math.min(f.max, ratio))
            out.flats = { { id = "mass", suffix = ".total_mass", multiplier = r },
                          { id = "mass_chassis", suffix = ".chassis_mass", multiplier = r } }
            out.expressedKg = stock * r
        else
            out.channel = "instance"
            local r = math.max(1, ratio)
            out.driveScale, out.brakeScale = 1 / r, 1 / r
            out.expressedKg = stock * r
            for i, l in ipairs(M.INSTANCE_LOSSES) do out.losses[i] = l end
        end
        out.unexpressedKg = m - out.expressedKg
        return out
    end

    -- ----------------------------------------------------------------------------------- lift (L316 F0)
    --
    -- The cause is a force in newtons; the runtime actuator is NCM Thrust's lift lever, a thrust-to-weight ratio
    -- written into the gravity entry and clamped at `LIFT_MAX_TWR` (thrust_levers.hpp `kMaxTwr`). As with mass,
    -- the state keeps the modelled ratio and the actuator reports what it could not express.
    M.LIFT_MAX_TWR = 3.0
    M.G = 9.81
    M.LIFT_LOSSES = {
        "applied through the centre of mass: no lever arm, no torque (attitude is F2)",
        "vertical in the world frame, not the car's: a tilted car still lifts straight up",
    }

    --- Sum the +Z thrust of a body's loads (only `kind = "thrust"`, only the vertical component).
    function M.liftN(body)
        local n = 0
        for _, l in ipairs((body and body.loads) or {}) do
            if l.kind == "thrust" and type(l.magnitudeN) == "number" then
                local d = l.dir or {}
                local x, y, z = d[1] or d.x or 0, d[2] or d.y or 0, d[3] or d.z or 0
                local len = math.sqrt(x * x + y * y + z * z)
                if len > 0 then n = n + l.magnitudeN * z / len end
            end
        end
        return n
    end

    function M.lift(forceN, massKg)
        local out = { channel = "lift_lever", stateTwr = 0, expressedTwr = 0, unexpressedTwr = 0, losses = {} }
        if not massKg or massKg <= 0 then
            out.channel, out.losses = "none", { "no mass to lift against" }
            return out
        end
        local r = math.max(0, forceN or 0) / (massKg * M.G)
        out.stateTwr = r
        out.expressedTwr = math.min(r, M.LIFT_MAX_TWR)
        out.unexpressedTwr = r - out.expressedTwr
        for i, l in ipairs(M.LIFT_LOSSES) do out.losses[i] = l end
        return out
    end

    --- The F0 prediction: burn at ratio r for t seconds from rest; peak vertical speed and the apex above start.
    function M.hopPrediction(r, t)
        local a = (r - 1) * M.G
        if a <= 0 then return 0, 0 end
        local v = a * t
        return v, 0.5 * a * t * t + v * v / (2 * M.G)
    end

    return M
end)
