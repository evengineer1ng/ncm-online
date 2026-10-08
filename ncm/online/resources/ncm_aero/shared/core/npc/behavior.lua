-- ncm-core module: npc.behavior
--
-- WHO THE DRIVER IS, independent of what they are driving (L322; doc 54 §N). One NCM driver -- the Paddock person
-- (`paddock.world`: `attrs` from `paddock.attributes`, FTB2 `personality` axes) -- races a Night City street, a Los
-- Santos event or a Snowglobe Fireball and stays recognisably the same competitor. This module turns the persistent
-- character (TRAITS and personality, never the domain SKILLS) into decision parameters any domain's planner reads:
--   riskTolerance   aggression, discipline, valor: how much danger they accept for position
--   marginScale     how much space they leave (x a domain's base separation)
--   commitDelayS    how long they hold a line before abandoning it
--   clutch          pressure_handling, mettle, valor: steadier when it matters most
--   volatility      confidence_volatility and ego: how hard provocation bites, and how slowly it fades
--   mistakeHazard   mistake_rate against consistency and discipline
-- plus a MOOD: provocation rises when the driver is passed, blocked or touched (scaled by volatility) and decays;
-- a provoked driver takes more risk and leaves less room. Domain SKILL is not here -- see `npc.competency`.
-- Pure; no stat ever leaves the server (`paddock.attributes.HIDDEN`).
local Core = NcmCore

Core.define("npc.behavior", function(C)
    local M = { version = "0.1.0" }

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
    local function z(a, k) return ((a and a[k]) or 50) / 50 - 1 end     -- a 0..100 stat -> -1..1; 50 -> 0

    --- The persistent profile of a person { attrs, personality }.
    function M.profile(person)
        local a = person.attrs or {}
        local p = person.personality or {}
        local risk = clamp(0.5 + 0.30 * z(a, "aggression") - 0.20 * z(a, "discipline") + 0.10 * (p.valor or 0)
            + 0.05 * z(a, "ego"), 0.02, 0.98)
        local clutch = clamp(0.5 + 0.25 * z(a, "pressure_handling") + 0.15 * z(a, "mettle") + 0.10 * (p.valor or 0), 0, 1)
        local vol = clamp(0.5 + 0.30 * z(a, "confidence_volatility") + 0.15 * z(a, "ego") - 0.15 * (p.temperament or 0), 0, 1)
        return {
            riskTolerance = risk,
            marginScale = clamp(1.6 - 1.2 * risk, 0.3, 1.6),
            commitDelayS = 0.3 + 1.7 * risk,
            clutch = clutch,
            volatility = vol,
            mistakeHazard = clamp(0.5 + 0.35 * z(a, "mistake_rate") - 0.15 * z(a, "consistency") - 0.10 * z(a, "discipline"), 0.05, 1),
        }
    end

    function M.newMood() return { provocation = 0 } end

    --- Something happened to the driver: "passed", "blocked", "contact". Provocation in 0..1.
    function M.provoke(mood, prof, what)
        local k = ({ passed = 0.25, blocked = 0.15, contact = 0.5 })[what] or 0.1
        mood.provocation = clamp(mood.provocation + k * prof.volatility * 1.6, 0, 1)
        return mood.provocation
    end

    --- Provocation fades: a calm driver in seconds, a volatile one over a long while.
    function M.decay(mood, prof, dt)
        local tau = 5 + 55 * prof.volatility
        mood.provocation = mood.provocation * math.exp(-dt / tau)
    end

    --- The parameters in force now. `stakes` 0..1 (start, final 10 %, a close finish, defending a lead).
    --- noiseScale multiplies execution error: a clutch driver gets steadier under stakes, a brittle one shakier.
    function M.effective(prof, mood, stakes)
        stakes = stakes or 0
        local prov = mood and mood.provocation or 0
        local risk = clamp(prof.riskTolerance + 0.35 * prov, 0, 1)
        return {
            risk = risk,
            marginScale = clamp(1.6 - 1.2 * risk, 0.3, 1.6),
            commitDelayS = 0.3 + 1.7 * risk,
            noiseScale = clamp(1 + stakes * (0.6 - 1.2 * prof.clutch) + 0.4 * prov, 0.4, 2.0),
        }
    end

    return M
end)
