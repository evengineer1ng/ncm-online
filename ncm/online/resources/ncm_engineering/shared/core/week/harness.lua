-- ncm-core module: week.harness
-- The unattended reconstruction, thousands of times (doc 47 §5, L310). An EMPTY server: no humans, only the Paddock's
-- NPC races feeding `race` and `race_crash` facts (exactly what ncm_paddock emits), Moody rolling its faces through the
-- same effects the hosts apply -- calendar density changes how many races run, lured purses change who races and how
-- hard (week.moody.pull, at an average driver) -- the curve stepping hourly, and the continuation judging every noon.
--
-- It is a model of the model, and it says so: per-tier race rates and the crash rate are dev's measured normal
-- (7.9 races an hour, 0.5 crash DNFs a race), crashes are Poisson. It exists to TUNE `week.continuation.BASE` against
-- the owner's targets and to hold them there: `tests/test_week_harness.lua` runs it in the gate, and
-- `tools/week-harness.lua` prints the full histogram for tuning.
local Core = NcmCore

Core.define("week.harness", function(C)
    local M = { version = "0.1.0" }
    local Hash = C.get("vocabulary.hash")
    local Curve = C.get("week.curve")
    local Moody = C.get("week.moody")
    local Cont = C.get("week.continuation")

    -- dev's normal: Paddock races an hour by tier (sums to ~7.9), and crash DNFs per race
    M.RATE = { street = 4.3, regional = 2.4, pro = 1.0, premier = 0.2 }
    M.CRASH_PER_RACE = 0.5
    M.TIERS = { "street", "regional", "pro", "premier" }

    local function poisson(rng, mean)
        if mean <= 0 then return 0 end
        local l, k, p = math.exp(-mean), 0, 1
        repeat k = k + 1; p = p * rng() until p <= l
        return k - 1
    end

    --- One unattended run. Returns { reached = last boundary survived (0 = collapsed at 72), complete = bool,
    --- verdicts = { ... }, rolls = n }.
    function M.run(seed, run)
        local rng = Hash.stream(seed, "harness", run)
        local st, md = Curve.newState(0), Moody.newState()
        local expected = { race_crash = M.CRASH_PER_RACE, racesPerHour = 0 }
        for _, t in ipairs(M.TIERS) do expected.racesPerHour = expected.racesPerHour + M.RATE[t] end
        local out = { reached = 0, complete = false, verdicts = {}, rolls = 0 }
        for h = 0, Cont.BOUNDARIES[#Cont.BOUNDARIES] - 1 do
            out.rolls = out.rolls + #Moody.step(md, seed, run, h)
            local fx = Moody.effects(md, h)
            local races, crashes = 0, 0
            for _, t in ipairs(M.TIERS) do
                local n = poisson(rng, M.RATE[t] / math.max(0.2, fx.calendar[t] or 1))
                local _, risk = Moody.pull(fx.lure[t], fx.purse[t], { aggression = 50, discipline = 50, need = 0.5 })
                races = races + n
                crashes = crashes + poisson(rng, n * M.CRASH_PER_RACE * risk)
            end
            Curve.step(st, h + 1, { race = races, race_crash = crashes }, expected)
            if Cont.isBoundary(h + 1) then
                local v = Cont.judge(seed, run, h + 1, st)
                out.verdicts[#out.verdicts + 1] = v
                if not v.survive then return out end
                out.reached = h + 1
                if v.kind == "complete" then out.complete = true end
            end
        end
        return out
    end

    --- n unattended runs: { n, survived = { [72] = k, ... } (survived that boundary), complete, meanZ = { [h] = z } }.
    function M.distribution(seed, n)
        local d = { n = n, survived = {}, judged = {}, complete = 0, zsum = {} }
        for _, b in ipairs(Cont.BOUNDARIES) do d.survived[b], d.judged[b], d.zsum[b] = 0, 0, 0 end
        for r = 1, n do
            local o = M.run(seed, r)
            for _, v in ipairs(o.verdicts) do
                d.judged[v.hours] = d.judged[v.hours] + 1
                d.zsum[v.hours] = d.zsum[v.hours] + v.z
                if v.survive then d.survived[v.hours] = d.survived[v.hours] + 1 end
            end
            if o.complete then d.complete = d.complete + 1 end
        end
        d.conditional, d.meanZ = {}, {}
        for _, b in ipairs(Cont.BOUNDARIES) do
            d.conditional[b] = d.judged[b] > 0 and d.survived[b] / d.judged[b] or nil
            d.meanZ[b] = d.judged[b] > 0 and d.zsum[b] / d.judged[b] or nil
        end
        return d
    end

    return M
end)
