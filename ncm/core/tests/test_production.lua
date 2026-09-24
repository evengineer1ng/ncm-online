-- Primary-market production. The arithmetic that decides whether NCM's bottom rung refills, and the tick
-- numbering that stops a restart from printing vehicles.
return {
    authored_lines_are_valid = function(T)
        local P = T.Core.get("economy.production")
        local ok, why = P.validate()
        T.ok(ok, "authored production data must be valid at boot: " .. tostring(why))
        T.ok(#P.LINES > 0, "a market with no lines can never restock")
        for _, l in ipairs(P.LINES) do
            T.ok(l.ceiling > 0, l.vehicleKey .. " has no shelf")
            T.ok(l.batch >= 1, l.vehicleKey .. " can never produce")
        end
    end,

    -- Acceptance A/B/C: the whole supply rule, in the packet's own numbers.
    production_seeks_the_ceiling_and_never_passes_it = function(T)
        local P = T.Core.get("economy.production")
        local line = { marketId = "m", vehicleKey = "k", price = 0, ceiling = 15, batch = 5, cadenceSec = 60 }
        -- A: room for a whole batch
        T.eq(P.plan({ line = line, available = 10 }).mint, 5, "10/15 with a batch of 5 produces 5")
        -- B: room for part of one. The packet's exact case: 12/15 produces 3, not 5, and lands on 15.
        local near = P.plan({ line = line, available = 12 })
        T.eq(near.mint, 3, "12/15 produces 3, never 5")
        T.eq(near.capacity, 3)
        T.eq(12 + near.mint, 15, "and lands exactly on the ceiling, never 17")
        -- C: no room at all. The tick still happened; it had nowhere to put anything.
        local full = P.plan({ line = line, available = 15 })
        T.eq(full.mint, 0, "15/15 produces nothing")
        T.eq(full.atCeiling, true)
        -- D: a sold-out shelf refills by a batch, not to the ceiling in one go.
        T.eq(P.plan({ line = line, available = 0 }).mint, 5, "sold out still only produces one batch")
    end,

    -- Acceptance H. A ceiling lowered under existing stock pauses production; it never destroys assets.
    -- Nothing in this module can return a negative or a removal, which is the point.
    lowering_a_ceiling_pauses_production_rather_than_destroying_stock = function(T)
        local P = T.Core.get("economy.production")
        local line = { marketId = "m", vehicleKey = "k", price = 0, ceiling = 8, batch = 5, cadenceSec = 60 }
        local over = P.plan({ line = line, available = 12 })
        T.eq(over.mint, 0, "over the ceiling produces nothing")
        T.eq(over.capacity, 0, "capacity floors at zero; it is never a number of cars to remove")
        T.eq(over.atCeiling, true)
        -- and resumes once purchases bring it back under
        T.eq(P.plan({ line = line, available = 7 }).mint, 1, "one slot free produces one")
    end,

    -- Cadence and batch are different supply chains even when their average is identical (packet section 4).
    cadence_and_batch_are_not_averaged_away = function(T)
        local P = T.Core.get("economy.production")
        local fast = { marketId = "m", vehicleKey = "a", price = 0, ceiling = 99, batch = 1, cadenceSec = 1800 }
        local slow = { marketId = "m", vehicleKey = "b", price = 0, ceiling = 99, batch = 2, cadenceSec = 3600 }
        -- Same long-run rate, different behaviour: the 30-minute line commits its next event at T+30 with one
        -- car on it, the 60-minute line commits at T+60 with two.
        local f, s = P.startSchedule(fast, 1000), P.startSchedule(slow, 1000)
        T.eq(f.nextAt, 1000 + 1800); T.eq(f.batch, 1)
        T.eq(s.nextAt, 1000 + 3600); T.eq(s.batch, 2)
        T.eq(P.plan({ line = fast, available = 0 }).mint, 1, "and they put different amounts on the shelf")
        T.eq(P.plan({ line = slow, available = 0 }).mint, 2)
        -- A big infrequent batch is a legal configuration, not something to smooth out.
        local burst = { marketId = "m", vehicleKey = "c", price = 0, ceiling = 50, batch = 10, cadenceSec = 300 }
        T.eq(P.plan({ line = burst, available = 0 }).mint, 10, "ten every five minutes is a valid supply chain")
    end,

    -- Acceptance G. A tick is identified by a CLAIM, not by arithmetic over a fixed cadence -- which is what
    -- lets cadence become dynamic without weakening the restart guarantee.
    tick_identity_is_a_claim_not_a_calculation = function(T)
        local P = T.Core.get("economy.production")
        local line = { marketId = "base_market", vehicleKey = "k", price = 0, ceiling = 8, batch = 4, cadenceSec = 1800 }
        local a = P.runKey("ncm-dev", line, 7)
        T.eq(a, P.runKey("ncm-dev", line, 7), "the same tick always claims the same key")
        T.neq(a, P.runKey("ncm-dev", line, 8), "a different tick is a different claim")
        T.neq(a, P.runKey("other", line, 7), "and a different world is a different claim")
        -- The committed event after one fires is the fired instant plus the CHOSEN interval, not a grid
        -- position -- so a manufacturer that slows down does not retroactively move earlier history.
        local next1 = P.commitNext({ batch = 2, intervalSec = 900 }, 5000)
        T.eq(next1.nextAt, 5900); T.eq(next1.batch, 2); T.eq(next1.intervalSec, 900)
    end,

    the_starting_schedule_states_the_authored_promise_and_no_more = function(T)
        local P = T.Core.get("economy.production")
        local line = { marketId = "m", vehicleKey = "k", price = 0, ceiling = 8, batch = 4, cadenceSec = 1800 }
        local sched = P.startSchedule(line, 100)
        T.eq(sched.nextAt, 1900)
        T.eq(sched.batch, 4, "what it MAY make; capacity and buyers decide the rest")
    end,

    -- Packet addendum section 5: a badge has a temperament, a model may disagree with it.
    manufacturer_defaults_compose_with_model_overrides = function(T)
        local P = T.Core.get("economy.production")
        local hella = P.line("base_market", "archer_hella")
        T.eq(P.profileFor(hella), "scarcity_keeper", "Archer protects scarcity by default")
        local maimai = P.line("base_market", "makigai_maimai")
        T.eq(P.profileFor(maimai), "volume_responsive")
        -- A model's own profile wins over its manufacturer's.
        local override = { marketId = "base_market", vehicleKey = "archer_hella", profile = "steady_hand" }
        T.eq(P.profileFor(override), "steady_hand", "the model wins")
        -- An unknown badge falls through to the engine's own default rather than guessing.
        T.eq(P.profileFor({ marketId = "m", vehicleKey = "nobody_knows" }), nil)
    end,

    -- The envelope is the cage. Authored data that would pin or free a manufacturer must refuse at boot.
    an_envelope_must_actually_bound_the_starting_schedule = function(T)
        local P = T.Core.get("economy.production")
        for _, l in ipairs(P.LINES) do
            local e = P.envelopeFor(l)
            T.ok(l.batch >= e.batchMin and l.batch <= e.batchMax, l.vehicleKey .. " starts outside its batch bounds")
            T.ok(l.cadenceSec >= e.intervalMin and l.cadenceSec <= e.intervalMax, l.vehicleKey .. " starts outside its interval bounds")
            T.ok(l.initialAllocation <= l.ceiling, l.vehicleKey .. " would launch over its own shelf")
        end
        -- A line with no authored envelope cannot move at all, which is the safe reading of silence.
        local pinned = P.envelopeFor({ batch = 3, cadenceSec = 600 })
        T.eq(pinned.batchMin, 3); T.eq(pinned.batchMax, 3)
        T.eq(pinned.intervalMin, 600); T.eq(pinned.intervalMax, 600)
    end,

    -- Packet section 2. The distinction the whole release turns on.
    an_offering_survives_its_stock = function(T)
        local P = T.Core.get("economy.production")
        local line = P.LINES[1]
        local now = 1790200000
        local stocked = P.offering({ line = line, available = 3, now = now })
        T.eq(stocked.available, 3)
        T.eq(stocked.soldOut, false)
        T.ok(stocked.displayName and stocked.displayName ~= "", "an offering names its model")
        -- Zero stock is a STATE of the offering, not its absence. This is the bug the owner reported: the
        -- MaiMai did not sell out, it vanished.
        local empty = P.offering({ line = line, available = 0, now = now })
        T.ok(empty ~= nil, "a sold-out model still has an offering")
        T.eq(empty.soldOut, true)
        T.eq(empty.available, 0)
        T.eq(empty.ceiling, line.ceiling, "and still states what full looks like")
        T.ok(empty.nextProductionAt > now, "and when it will be made again")
        T.eq(empty.scheduleDynamic, true, "and says THAT schedules move, without saying how")
        T.eq(empty.nextBatch, line.batch)
        -- Negative or junk stock never renders as a negative shelf.
        T.eq(P.offering({ line = line, available = -4, now = now }).available, 0)
        -- A live committed schedule wins over the authored starting one: what the player sees is the
        -- manufacturer's CURRENT plan, not the number it launched with.
        local live = P.offering({ line = line, available = 1, now = now,
            schedule = { batch = 1, intervalSec = 7200, nextAt = now + 300 } })
        T.eq(live.nextBatch, 1); T.eq(live.cadenceSec, 7200); T.eq(live.nextProductionAt, now + 300)
    end,
}
