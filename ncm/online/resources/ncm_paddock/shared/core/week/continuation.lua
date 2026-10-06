-- ncm-core module: week.continuation
-- At 72 hours, history asks whether it still gets its way (doc 47, L309-L310).
--
-- Racing Week was advertised as seven days. At each possible end -- noon of Day 3 (hour 72) through the scheduled
-- conclusion (hour 168) -- the WORLD STATE yields a probability that the run goes on, and one seeded draw decides.
-- Not a threshold (doc 47: "survival isn't `pressure < 50 = continue`"), never 100 %, never a public number.
--
--   z = deviation / band(hours)     -- how this run stands against history, -1 (as bad as it gets) .. +1
--   p = clamp(logistic(BASE[h] + SLOPE * z), PMIN, PMAX)
--
-- BASE is what an UNATTENDED run faces at that boundary: tuned so that an empty server -- NPCs only, Moody rolling --
-- reaches Day 4 about 1 in 4, then about 1/3, 1/3 and 1/4 (about 1 in 144 see Day 7), and completes the seventh day
-- about 3 in 10 of those (doc 47 §1.4: targets for MODEL OUTPUTS). `tests/test_week_harness.lua` re-measures the
-- distribution over thousands of seeded runs on every gate, so a later change to the curve or Moody that breaks the
-- shape fails the build. SLOPE: a horrible run (z = -1) sees a few per cent at hour 72; an extraordinary one (z = +1)
-- about seven in ten.
--
-- Moody never reaches this function: it changes what happens, and only what happened moves `z` (doc 47 §1.2).
-- The draw is pure: (seed, run, hour) -> u, so a verdict can be re-derived and is recorded with its p and z.
local Core = NcmCore

Core.define("week.continuation", function(C)
    local M = { version = "0.1.0", SLOPE = 2.0, PMIN = 0.01, PMAX = 0.85 }
    local Hash = C.get("vocabulary.hash")
    local Curve = C.get("week.curve")

    M.BOUNDARIES = { 72, 96, 120, 144, 168 }
    -- the conditional survival an unattended run should show at each boundary (doc 47 §0)
    M.TARGET = { [72] = 0.25, [96] = 1 / 3, [120] = 1 / 3, [144] = 0.25, [168] = 0.30 }
    -- logit intercepts, calibrated by the harness against TARGET (see the header); re-tune there, never by hand-waving
    M.BASE = { [72] = -1.07, [96] = -0.69, [120] = -0.69, [144] = -1.10, [168] = -0.85 }

    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    function M.isBoundary(hours) return M.BASE[math.floor((hours or 0) + 0.5)] ~= nil end

    --- The run's standing against history at `hours`, -1..1.
    function M.z(st, hours)
        local b = Curve.band(hours)
        if b <= 0 then return 0 end
        return clamp((st and tonumber(st.deviation) or 0) / b, -1, 1)
    end

    --- The probability that the run goes on past boundary `hours`, given standing z.
    function M.probability(hours, z)
        local base = M.BASE[math.floor((hours or 0) + 0.5)]
        if not base then return nil end
        local x = base + M.SLOPE * (z or 0)
        return clamp(1 / (1 + math.exp(-x)), M.PMIN, M.PMAX)
    end

    --- The one draw for (run, boundary), uniform in [0, 1).
    function M.u(seed, run, hours)
        return Hash.unit(tostring(Hash.fnv1a32(Hash.key(seed, "continue", run, math.floor(hours + 0.5)))), "continue", run, hours)
    end

    --- The verdict at a boundary: { hours, z, p, u, survive, kind = "continue" | "complete" | "collapse" }.
    --- Surviving the last boundary (168) is completing Racing Week; failing any boundary is the collapse.
    function M.judge(seed, run, hours, st)
        hours = math.floor(hours + 0.5)
        local z = M.z(st, hours)
        local p = M.probability(hours, z)
        if not p then return nil, "not_a_boundary" end
        local u = M.u(seed, run, hours)
        local survive = u < p
        local kind = (not survive) and "collapse" or ((hours >= M.BOUNDARIES[#M.BOUNDARIES]) and "complete" or "continue")
        return { hours = hours, z = z, p = p, u = u, survive = survive, kind = kind }
    end

    return M
end)
