-- tools/week-harness.lua -- the unattended Racing Week distribution (doc 47 §5, L310), for tuning.
-- Usage: lua tools/week-harness.lua [runs=4000] [seed=harness]
-- Prints, per possible end, how many runs were judged, how many went on, the conditional rate against the target, and
-- the mean standing z. Tune week.continuation.BASE until the conditionals sit on the targets.
local here = (arg and arg[0] or "tools/week-harness.lua"):gsub("[/\\][^/\\]*$", "")
local root = here .. "/../ncm/core"
local Core = dofile(root .. "/init.lua")
for _, rel in ipairs(dofile(root .. "/MANIFEST.lua")) do dofile(root .. "/" .. rel) end
local H, Cont = Core.get("week.harness"), Core.get("week.continuation")
local n, seed = tonumber(arg[1]) or 4000, arg[2] or "harness"
local t0 = os.clock()
local d = H.distribution(seed, n)
print(("unattended Racing Week, %d runs, seed %q (%.1f s)"):format(n, seed, os.clock() - t0))
for _, b in ipairs(Cont.BOUNDARIES) do
    print(("  hour %3d  judged %5d  went on %5d  conditional %5.3f (target %5.3f)  mean z %+.3f"):format(b, d.judged[b],
        d.survived[b], d.conditional[b] or 0, Cont.TARGET[b], d.meanZ[b] or 0))
end
print(("  reached Day 4: %.3f   reached Day 7: 1 in %.0f   completed: %d of %d"):format(d.survived[72] / n,
    d.survived[144] > 0 and n / d.survived[144] or math.huge, d.complete, n))
