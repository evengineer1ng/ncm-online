-- L110 (where you log out is where you log in) and L111 (colour is deterministic and supply-constrained).
local ASSET_A = "10000000-0000-4000-8000-000000000001"
local ASSET_B = "10000000-0000-4000-8000-000000000002"

return {
    -- ---------------------------------------------------------------- location
    a_recent_position_is_restored = function(T)
        local L = T.Core.get("world.location")
        local ok = L.shouldRestore({ x = 100, y = -200, z = 12, savedAt = 900 }, 1000)
        T.eq(ok, true, "leave in Pacifica, return in Pacifica")
    end,

    -- The gate is the work: every refusal is nameable, because a silently stranded player looks exactly like
    -- a working one.
    every_refusal_has_a_reason_a_human_can_act_on = function(T)
        local L = T.Core.get("world.location")
        local cases = {
            { nil,                                                    "none" },
            { { x = 1, y = 1, z = 1 },                                "undated" },
            { { x = 0/0, y = 1, z = 1, savedAt = 900 },               "not_finite" },
            { { x = 1e9, y = 1, z = 1, savedAt = 900 },               "out_of_bounds" },
            { { x = 1, y = 1, z = 1, savedAt = 99999 },               "from_the_future" },
            { { x = 1, y = 1, z = 1, savedAt = 900, inVehicle = true }, "was_in_vehicle" },
        }
        for _, c in ipairs(cases) do
            local ok, why = L.shouldRestore(c[1], 1000)
            T.eq(ok, false, "expected refusal: " .. c[2])
            T.eq(why, c[2])
        end
        local _, noClock = L.shouldRestore({ x = 1, y = 1, z = 1, savedAt = 900 }, nil)
        T.eq(noClock, "no_clock")
        -- older than the default week
        local _, stale = L.shouldRestore({ x = 1, y = 1, z = 1, savedAt = 1 }, 8 * 86400)
        T.eq(stale, "stale")
    end,

    -- A seat is not a place: the vehicle it belonged to is very likely gone.
    a_saved_seat_is_never_restored = function(T)
        local L = T.Core.get("world.location")
        local seated = { x = 5, y = 5, z = 5, savedAt = 990, inVehicle = true }
        T.eq(L.shouldRestore(seated, 1000), false)
        T.eq(L.arrivalPose(seated).trusted, false, "the pose still computes, but is marked untrusted")
    end,

    arrival_lifts_off_the_floor = function(T)
        local L = T.Core.get("world.location")
        local pose = L.arrivalPose({ x = 1, y = 2, z = 10, heading = 90, bucket = 3, savedAt = 1000 })
        T.eq(pose.z, 10.5, "the same lift the race resume uses, so a float floor cannot swallow the arrival")
        T.eq(pose.heading, 90); T.eq(pose.bucket, 3)
        T.eq(L.arrivalPose(nil), nil)
    end,

    saving_is_throttled_by_movement_not_by_time = function(T)
        local L = T.Core.get("world.location")
        local at = { x = 0, y = 0, z = 0 }
        T.eq(L.worthSaving(nil, at), true, "nothing stored yet: always write")
        T.eq(L.worthSaving(at, { x = 1, y = 0, z = 0 }), false, "standing still is not a new location")
        T.eq(L.worthSaving(at, { x = 50, y = 0, z = 0 }), true)
        T.eq(L.worthSaving(at, { x = 0/0, y = 0, z = 0 }), false, "never store nonsense")
        T.eq(L.worthSaving({ x = 0/0, y = 0, z = 0 }, at), true, "...but recover from it")
    end,

    -- KB-113. The exact live failure: a placeholder puppet at the world origin was stored during the join
    -- window and replayed as a destination 3 s later. Ten times, three drivers, two days.
    a_position_this_join_wrote_is_not_where_you_logged_out = function(T)
        local L = T.Core.get("world.location")
        local joined = 1000
        local mine = { x = 0, y = 3.6, z = 0, savedAt = 1009 }   -- written 9 s after connecting
        local ok, why = L.shouldRestore(mine, 1012, { connectedAt = joined })
        T.eq(ok, false, "this join wrote it; it cannot also be where the driver left")
        T.eq(why, "same_session")
        T.eq(L.shouldRestore(mine, 1012), true, "a host that cannot say keeps every other guard, and no more")
        local earlier = { x = 0, y = 3.6, z = 0, savedAt = 999 }
        T.eq(L.shouldRestore(earlier, 1012, { connectedAt = joined }), true, "one second before the join is last session")
    end,

    -- KB-113, second half: the row that survived the first guard held z = -906.4 -- a fall, caught by the
    -- 20 s sweep and then replayed, which drops the player straight back into it.
    a_fall_is_not_a_place_and_is_never_stored_or_replayed = function(T)
        local L = T.Core.get("world.location")
        local falling = { x = 0, y = 3.6, z = -906.4 }
        local ok, why = L.valid(falling)
        T.eq(ok, false, "nobody has ever stood 906 m below Night City")
        T.eq(why, "below_world")
        T.eq(L.worthSaving(nil, falling), false, "so it never reaches storage in the first place")
        local _, restore = L.shouldRestore({ x = 0, y = 3.6, z = -906.4, savedAt = 900 }, 1000)
        T.eq(restore, "below_world", "and a row already holding one is refused on the way out")
        T.eq(L.valid({ x = 100, y = -200, z = -5 }), true, "the authored world floor is still a place")
        T.eq(L.valid({ x = 100, y = -200, z = 230 }), true, "and so is the highest authored node")
        local _, above = L.valid({ x = 1, y = 1, z = 4000 })
        T.eq(above, "above_world")
    end,

    -- The owner's report was "why do i spawn in twice every time?" -- the platform places you, then L110
    -- fades you to black and puts you 0.5 m away.
    being_put_back_where_you_already_are_is_not_a_restore = function(T)
        local L = T.Core.get("world.location")
        local pose = L.arrivalPose({ x = 2566.9, y = 112.6, z = 78.6, savedAt = 1000 })
        T.eq(L.alreadyThere({ x = 2566.9, y = 112.6, z = 78.6 }, pose), true, "the default spawn and the stored position agree")
        T.eq(L.alreadyThere({ x = 2566.9, y = 112.6, z = 78.6 }, pose, { arrivedM = 0.1 }), false, "a host may insist on precision")
        T.eq(L.alreadyThere({ x = 2600.0, y = 112.6, z = 78.6 }, pose), false, "30 m away is a real restore")
        T.eq(L.alreadyThere(nil, pose), false)
        T.eq(L.alreadyThere({ x = 0/0, y = 1, z = 1 }, pose), false, "an unreadable position is not an arrival")
    end,

    staleness_is_configurable_because_a_week_is_a_guess = function(T)
        local L = T.Core.get("world.location")
        local p = { x = 1, y = 1, z = 1, savedAt = 0 }
        T.eq(L.shouldRestore(p, 3600), true, "an hour old is fine by default")
        T.eq(L.shouldRestore(p, 3600, { maxAgeSec = 60 }), false, "a host may be stricter")
    end,

    -- ---------------------------------------------------------------- colour
    -- L111: deterministic ACROSS SESSIONS is the whole point -- this is the reported bug.
    the_same_machine_is_always_the_same_colour = function(T)
        local V = T.Core.get("data.vehicle_config")
        local first = V.finishFor("makigai_maimai", ASSET_A)
        for _ = 1, 20 do
            local again = V.finishFor("makigai_maimai", ASSET_A)
            T.eq(again.name, first.name, "brown one session and blue the next is the bug")
            T.eq(again.primary.r, first.primary.r)
        end
        T.ok(V.hash(ASSET_A) ~= V.hash(ASSET_B), "different machines hash differently")
    end,

    two_examples_of_one_model_can_differ = function(T)
        local V = T.Core.get("data.vehicle_config")
        local seen = {}
        for i = 1, 40 do
            local id = ("10000000-0000-4000-8000-%012d"):format(i)
            seen[V.finishFor("makigai_maimai", id).name] = true
        end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        T.ok(n > 1, "a production run is not all one colour")
    end,

    -- Deterministic alone would allow colours no factory ever made. It must come from the range.
    a_colour_is_always_one_the_model_is_produced_in = function(T)
        local V = T.Core.get("data.vehicle_config")
        local range = V.rangeFor("makigai_maimai")
        T.ok(#range > 0)
        for i = 1, 50 do
            local id = ("a%047d"):format(i)
            local got = V.finishFor("makigai_maimai", id)
            local found = false
            for _, f in ipairs(range) do if f.name == got.name then found = true end end
            T.ok(found, "supply-constrained: " .. tostring(got.name) .. " is not in the MaiMai's range")
        end
    end,

    an_unknown_machine_still_gets_a_real_finish = function(T)
        local V = T.Core.get("data.vehicle_config")
        local f = V.finishFor("something_we_have_never_heard_of", ASSET_A)
        T.ok(f and f.name and f.primary, "an asset with no finish is the bug this module removes")
        T.eq(#V.rangeFor(nil) > 0, true, "never an empty range")
        -- no assetId at all: still a colour, not nil
        T.ok(V.finishFor("makigai_maimai", nil).name)
    end,

    hex_round_trips_and_refuses_rubbish = function(T)
        local V = T.Core.get("data.vehicle_config")
        T.eq(V.toHex({ r = 255, g = 0, b = 16 }), "#FF0010")
        T.eq(V.toHex({ r = -5, g = 999, b = 7.9 }), "#00FF07", "clamped and floored, never out of range")
        local back = V.fromHex("#1A2B3C")
        T.eq(back.r, 26); T.eq(back.g, 43); T.eq(back.b, 60)
        T.eq(V.fromHex("nonsense"), nil); T.eq(V.fromHex(nil), nil)
        T.eq(V.toHex("nope"), nil)
    end,

    -- Allocation, when it exists, is the author. The factory default is only a default.
    a_stored_colour_always_wins = function(T)
        local V = T.Core.get("data.vehicle_config")
        local factory = V.paintFor("makigai_maimai", ASSET_A, nil)
        T.eq(factory.source, "factory")
        T.ok(factory.name)
        local stored = V.paintFor("makigai_maimai", ASSET_A, { primary = "#00FF00" })
        T.eq(stored.source, "stored")
        T.eq(stored.primary.g, 255)
        T.eq(stored.secondary.g, 255, "one colour given means a single-tone machine, not a black second tone")
        local two = V.paintFor("makigai_maimai", ASSET_A, { primary = "#00FF00", secondary = "#0000FF" })
        T.eq(two.secondary.b, 255)
        -- a corrupt stored value must not produce a black car
        T.eq(V.paintFor("makigai_maimai", ASSET_A, { primary = "rubbish" }).source, "factory")
    end,
}
