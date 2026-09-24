-- Supply profiles tested AS SYSTEMS, not as formulas (addendum section 27).
--
-- Each case runs a deterministic simulated market history through a real profile and asserts on what the
-- manufacturer did over time. There is no randomness anywhere: the same history always produces the same
-- schedule, which is what makes a live decision reproducible and forensically checkable later.

--- One market, run for `cycles` production cycles.
---
--- Each cycle: produce (capped by the shelf), then let `demand(i)` buyers take what they can, then fold the
--- completed cycles and let the profile choose the NEXT schedule. That order matters -- it is the same
--- commitment model the host uses, where an evaluation always decides the event AFTER the one that just
--- fired, never the one players are already looking at.
local function simulate(Core, opts)
    local SP = Core.get("economy.supply_profiles")
    local p = SP.profile(opts.profileId)
    local env = opts.envelope
    local capacity = opts.capacity
    local available = opts.startAvailable or 0
    local sched = { batch = opts.batch, intervalSec = opts.intervalSec }
    local memory, cycles, log = {}, {}, {}
    for i = 1, opts.cycles do
        local room = math.max(0, capacity - available)
        local minted = math.min(sched.batch, room)
        available = available + minted
        local want = opts.demand(i)
        local sold = math.min(want, available)
        available = available - sold
        cycles[#cycles + 1] = { endedAvailable = available, sold = sold, minted = minted, capacity = capacity }
        local facts = SP.observe(cycles, p)
        local d = SP.decide({ profileId = opts.profileId, envelope = env, current = sched,
                              facts = facts, memory = memory })
        log[#log + 1] = { cycle = i, minted = minted, sold = sold, available = available,
                          batch = sched.batch, intervalSec = sched.intervalSec,
                          reason = d.reason, changed = d.changed, pressure = d.signals.pressure }
        sched = { batch = d.batch, intervalSec = d.intervalSec }
        memory = d.memory
    end
    return { schedule = sched, log = log, available = available, cycles = cycles }
end

--- Units per hour of a schedule. Used ONLY to assert direction of travel in tests; the engine itself never
--- reduces a schedule to a rate.
local function rate(s) return s.batch / (s.intervalSec / 3600) end

local ENV = { batchMin = 1, batchMax = 6, intervalMin = 900, intervalMax = 8 * 3600 }

local function changes(log)
    local n = 0
    for _, r in ipairs(log) do if r.changed then n = n + 1 end end
    return n
end

return {
    -- The ladder is the guarantee of integer production and envelope containment (sections 6 and 24).
    the_ladder_is_whole_cars_inside_the_envelope = function(T)
        local SP = T.Core.get("economy.supply_profiles")
        local rungs = SP.ladder(ENV, "fine")
        T.ok(#rungs > 1, "an envelope with room must offer somewhere to move")
        for _, r in ipairs(rungs) do
            T.eq(r.batch, math.floor(r.batch), "there is no such thing as 1.8 Hellas")
            T.ok(r.batch >= ENV.batchMin and r.batch <= ENV.batchMax, "batch inside the envelope")
            T.ok(r.intervalSec >= ENV.intervalMin and r.intervalSec <= ENV.intervalMax, "interval inside the envelope")
        end
        -- Ordered slowest to fastest, so "one step up" always means "more supply".
        for i = 2, #rungs do T.ok(rungs[i].rate >= rungs[i - 1].rate, "the ladder is ordered by rate") end
        -- **One rung per rate**, so a step always changes the rate. 1-per-30-min and 2-per-60-min have the
        -- same average, and a ladder that held both would let a "decrease" land on an identical rate having
        -- changed only the shape -- which is what happened live on 2026-09-23.
        local env2 = { batchMin = 1, batchMax = 2, intervalMin = 1800, intervalMax = 3600 }
        local fine = SP.ladder(env2, "fine")
        local seen = {}
        for _, r in ipairs(fine) do
            local k = ("%.12f"):format(r.rate)
            T.eq(seen[k], nil, "two rungs share a rate: a step could change nothing")
            seen[k] = true
        end
        -- The distinction lives in `grain` instead: at the SAME rate, a fine manufacturer trickles and a
        -- coarse one drops. Both are legal; they are different machines.
        local coarse = SP.ladder(env2, "coarse")
        local function at(rungs, rate)
            for _, r in ipairs(rungs) do if math.abs(r.rate - rate) < 1e-12 then return r end end
        end
        local fr, cr = at(fine, 1 / 1800), at(coarse, 1 / 1800)
        T.eq(fr.batch, 1, "fine expresses that rate as 1 every 30 min")
        T.eq(cr.batch, 2, "coarse expresses the same rate as 2 every 60 min")
        T.eq(cr.intervalSec, 3600)
        -- A pinned envelope is a manufacturer that cannot move at all.
        T.eq(#SP.ladder({ batchMin = 2, batchMax = 2, intervalMin = 600, intervalMax = 600 }, "fine"), 1)
    end,

    -- G / cold start (section 18). Absence of evidence is not evidence of no demand.
    a_quiet_new_market_does_not_send_anyone_to_an_extreme = function(T)
        local r = simulate(T.Core, { profileId = "steady_hand", envelope = ENV, capacity = 8,
            batch = 4, intervalSec = 1800, cycles = 2, demand = function() return 0 end })
        T.eq(changes(r.log), 0, "two cycles of nothing is not enough to conclude anything")
        T.eq(r.log[1].reason, "cold_start")
        T.eq(r.schedule.batch, 4, "the authored starting schedule still stands")
        T.eq(r.schedule.intervalSec, 1800)
    end,

    -- A: stable moderate demand should leave a steady manufacturer alone.
    stable_demand_does_not_move_a_steady_hand = function(T)
        local r = simulate(T.Core, { profileId = "steady_hand", envelope = ENV, capacity = 8,
            startAvailable = 4, batch = 4, intervalSec = 1800, cycles = 12,
            demand = function() return 4 end })
        T.eq(changes(r.log), 0, "supply already matches demand; there is nothing to correct")
    end,

    -- B / C: sustained sellout and a demand spike push production UP, bounded by the envelope.
    sustained_sellout_increases_supply_within_bounds = function(T)
        local before = { batch = 4, intervalSec = 1800 }
        local r = simulate(T.Core, { profileId = "volume_responsive", envelope = ENV, capacity = 8,
            batch = 4, intervalSec = 1800, cycles = 14, demand = function() return 99 end })
        T.ok(rate(r.schedule) > rate(before), "a permanently empty shelf is answered with more supply")
        T.ok(r.schedule.batch <= ENV.batchMax, "and never leaves the envelope")
        T.ok(r.schedule.intervalSec >= ENV.intervalMin)
        -- Bounded per evaluation: it climbs, it does not teleport to the top on the first sellout.
        T.ok(changes(r.log) >= 2, "it took several cycles to get there")
        local firstChange
        for _, x in ipairs(r.log) do if x.changed then firstChange = x.cycle; break end end
        T.ok(firstChange and firstChange >= 2, "and never on the very first observation")
    end,

    -- A scarcity keeper sees the same sellout and mostly shrugs. Both are correct (section 19).
    scarcity_keeper_barely_chases_the_same_demand = function(T)
        local hot = function() return 99 end
        local volume = simulate(T.Core, { profileId = "volume_responsive",
            envelope = { batchMin = 1, batchMax = 2, intervalMin = 3600, intervalMax = 72 * 3600 },
            capacity = 4, batch = 2, intervalSec = 7200, cycles = 16, demand = hot })
        local scarce = simulate(T.Core, { profileId = "scarcity_keeper",
            envelope = { batchMin = 1, batchMax = 2, intervalMin = 3600, intervalMax = 72 * 3600 },
            capacity = 4, batch = 2, intervalSec = 7200, cycles = 16, demand = hot })
        T.ok(rate(volume.schedule) >= rate(scarce.schedule),
             "the volume manufacturer ends at least as fast as the one protecting scarcity")
        T.ok(changes(scarce.log) <= changes(volume.log), "and it changed its mind less often")
    end,

    -- D / E / 21 / 23: demand collapse fills the shelf and production backs off, destroying nothing.
    demand_collapse_slows_production_and_deletes_nothing = function(T)
        local before = { batch = 6, intervalSec = 900 }
        local r = simulate(T.Core, { profileId = "volume_responsive", envelope = ENV, capacity = 8,
            startAvailable = 8, batch = 6, intervalSec = 900, cycles = 16,
            demand = function() return 0 end })
        T.ok(rate(r.schedule) < rate(before), "a permanently full shelf is answered with less supply")
        T.eq(r.available, 8, "and the shelf still holds every legitimate asset")
        for _, x in ipairs(r.log) do
            T.ok(x.available <= 8, "nothing ever exceeded the shelf")
            T.ok(x.minted >= 0, "and production is never negative -- there is no un-manufacturing")
        end
    end,

    -- F / 22: oscillation must not drive the schedule up and down with it.
    oscillating_demand_does_not_make_the_schedule_flap = function(T)
        -- Alternating famine and glut, for a long time.
        local r = simulate(T.Core, { profileId = "steady_hand", envelope = ENV, capacity = 8,
            startAvailable = 4, batch = 3, intervalSec = 1800, cycles = 40,
            demand = function(i) return (i % 2 == 0) and 99 or 0 end })
        T.ok(changes(r.log) <= 6, "40 cycles of whiplash produced few schedule changes, not twenty")
        -- And it never ping-pongs: no change immediately followed by a change back.
        local last, flips = nil, 0
        for _, x in ipairs(r.log) do
            if x.changed then
                local dir = x.pressure > 0 and 1 or -1
                if last and dir ~= last then flips = flips + 1 end
                last = dir
            end
        end
        T.ok(flips <= 2, "and did not reverse direction on every swing")
    end,

    -- H vs I, the section 27 invariant: the engine cannot tell one buyer from ten, because it is never told.
    one_buyer_and_many_buyers_are_the_same_market_fact = function(T)
        local SP = T.Core.get("economy.supply_profiles")
        local p = SP.profile("volume_responsive")
        -- Ten sales in a cycle. The facts carry no buyer at all, so there is nothing to differ on.
        local history = { { endedAvailable = 0, sold = 10, minted = 4, capacity = 8 } }
        local a = SP.observe(history, p)
        local b = SP.observe({ { endedAvailable = 0, sold = 10, minted = 4, capacity = 8 } }, p)
        T.eq(a.soldInWindow, b.soldInWindow)
        T.eq(a.soldOutCycles, b.soldOutCycles)
        local da = SP.decide({ profileId = "volume_responsive", envelope = ENV,
            current = { batch = 2, intervalSec = 1800 }, facts = a, memory = {} })
        local db = SP.decide({ profileId = "volume_responsive", envelope = ENV,
            current = { batch = 2, intervalSec = 1800 }, facts = b, memory = {} })
        T.eq(da.batch, db.batch); T.eq(da.intervalSec, db.intervalSec)
        -- And the fact bundle has no field that could ever carry an identity.
        for k in pairs(a) do
            T.ok(k ~= "driverId" and k ~= "buyer" and k ~= "owner" and k ~= "players",
                 "a signal named " .. k .. " must not be able to identify anybody")
        end
    end,

    -- 11 / 17: determinism. The same history always yields the same schedule, whoever runs it and whenever.
    the_same_history_always_produces_the_same_schedule = function(T)
        local spec = { profileId = "volume_responsive", envelope = ENV, capacity = 8, startAvailable = 2,
            batch = 3, intervalSec = 1800, cycles = 20,
            demand = function(i) return (i * 7) % 5 end }      -- deterministic, uneven, not random
        local a = simulate(T.Core, spec)
        local b = simulate(T.Core, spec)
        T.eq(a.schedule.batch, b.schedule.batch)
        T.eq(a.schedule.intervalSec, b.schedule.intervalSec)
        T.eq(changes(a.log), changes(b.log))
        -- A restart re-reads persisted state; replaying the decision from the same state must not drift.
        local SP = T.Core.get("economy.supply_profiles")
        local p = SP.profile("volume_responsive")
        local facts = SP.observe(a.cycles, p)
        local mem = { signRuns = 2, lastSign = 1, cyclesSinceChange = 3 }
        local d1 = SP.decide({ profileId = "volume_responsive", envelope = ENV, current = a.schedule, facts = facts, memory = mem })
        local d2 = SP.decide({ profileId = "volume_responsive", envelope = ENV, current = a.schedule, facts = facts, memory = mem })
        T.eq(d1.batch, d2.batch); T.eq(d1.intervalSec, d2.intervalSec); T.eq(d1.reason, d2.reason)
    end,

    -- 12: a single purchase has no event to trigger, so there is no threshold to farm.
    one_purchase_can_never_move_a_schedule = function(T)
        local SP = T.Core.get("economy.supply_profiles")
        local p = SP.profile("volume_responsive")
        -- A long quiet history, then exactly one sale in the newest cycle.
        local cycles = {}
        for _ = 1, 8 do cycles[#cycles + 1] = { endedAvailable = 4, sold = 0, minted = 0, capacity = 8 } end
        cycles[#cycles + 1] = { endedAvailable = 3, sold = 1, minted = 0, capacity = 8 }
        local d = SP.decide({ profileId = "volume_responsive", envelope = ENV,
            current = { batch = 3, intervalSec = 1800 }, facts = SP.observe(cycles, p), memory = {} })
        T.eq(d.changed, false, "one car leaving a healthy shelf is not a supply signal")
    end,

    -- N: the extremes of an envelope are reachable and are hard stops, not soft ones.
    the_envelope_is_a_hard_stop_at_both_ends = function(T)
        local hotEnv = { batchMin = 1, batchMax = 2, intervalMin = 1800, intervalMax = 3600 }
        local up = simulate(T.Core, { profileId = "volume_responsive", envelope = hotEnv, capacity = 20,
            batch = 1, intervalSec = 3600, cycles = 30, demand = function() return 99 end })
        T.eq(up.schedule.batch, 2); T.eq(up.schedule.intervalSec, 1800)
        T.ok(rate(up.schedule) <= 2 / 0.5, "pinned at the fastest legal rung and no faster")
        local down = simulate(T.Core, { profileId = "volume_responsive", envelope = hotEnv, capacity = 20,
            startAvailable = 20, batch = 2, intervalSec = 1800, cycles = 30, demand = function() return 0 end })
        T.eq(down.schedule.batch, 1); T.eq(down.schedule.intervalSec, 3600)
    end,

    -- O: a long dead market settles at its slowest legal schedule and simply stops producing while full.
    a_model_that_never_sells_does_not_fold = function(T)
        local r = simulate(T.Core, { profileId = "steady_hand", envelope = ENV, capacity = 8,
            startAvailable = 8, batch = 4, intervalSec = 1800, cycles = 60,
            demand = function() return 0 end })
        T.eq(r.available, 8, "the shelf is still full and nothing was destroyed")
        T.eq(r.schedule.intervalSec, ENV.intervalMax, "and it has slowed to its slowest legal cadence")
        for _, x in ipairs(r.log) do T.eq(x.minted, 0, "a full shelf produces nothing, every cycle") end
    end,

    -- M: a large batch arriving at a nearly full shelf is capped by capacity, not by the profile.
    a_big_batch_into_a_nearly_full_shelf_is_capped_by_the_shelf = function(T)
        local r = simulate(T.Core, { profileId = "steady_hand", envelope = ENV, capacity = 8,
            startAvailable = 7, batch = 6, intervalSec = 1800, cycles = 1,
            demand = function() return 0 end })
        T.eq(r.log[1].minted, 1, "one free slot takes one car, not six")
        T.eq(r.available, 8)
    end,

    -- 25: a decision can always be attributed to a profile and a logic version.
    every_decision_names_its_profile_and_version = function(T)
        local SP = T.Core.get("economy.supply_profiles")
        local d = SP.decide({ profileId = "scarcity_keeper", envelope = ENV,
            current = { batch = 1, intervalSec = 3600 },
            facts = { available = 0, capacity = 4, soldInWindow = 12, suppliedInWindow = 6, cyclesObserved = 9, soldOutCycles = 9, fullCycles = 0 },
            memory = {} })
        T.eq(d.profileId, "scarcity_keeper")
        T.eq(d.logicVersion, SP.LOGIC_VERSION)
        T.ok(type(d.reason) == "string" and d.reason ~= "", "and says why in words we can grep for")
        T.ok(d.signals and d.signals.pressure ~= nil, "and carries the observations it judged")
        -- An unknown profile id falls back to the default rather than erroring or freezing supply.
        local fallback = SP.decide({ profileId = "no_such_profile", envelope = ENV,
            current = { batch = 1, intervalSec = 3600 },
            facts = { available = 4, capacity = 4, soldInWindow = 0, suppliedInWindow = 0, cyclesObserved = 9, soldOutCycles = 0, fullCycles = 9 },
            memory = {} })
        T.eq(fallback.profileId, SP.DEFAULT_PROFILE)
    end,
}
