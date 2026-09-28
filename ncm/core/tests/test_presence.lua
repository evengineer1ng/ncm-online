local M = NcmCore.get("world.presence")
local cases = {}

-- `positions` as the platform hands it over: integer keys, a bucket on every row.
local function P(x, y, bucket) return { x = x, y = y, z = 10, bucket = bucket or 0 } end

local function world()
    return {
        [1] = P(0, 0),          -- the viewer
        [2] = P(50, 0),         -- 50 m away
        [3] = P(500, 0),        -- 500 m away
        [4] = P(10, 0, 7),      -- next door, but in another bucket: not in this world
    }
end

-- ------------------------------------------------------------------ rowsFor

cases.rows_exclude_self_and_other_buckets = function(T)
    local rows, note = M.rowsFor(1, world())
    T.eq(#rows, 2)
    T.eq(rows[1].i, 2)
    T.eq(rows[2].i, 3)
    T.eq(note.considered, 3)        -- the viewer is not a candidate at all
end

cases.a_viewer_with_no_snapshot_receives_nothing = function(T)
    local rows, note = M.rowsFor(99, world())
    T.eq(#rows, 0)
    T.eq(note.reason, "viewer_unlocated")
end

cases.rows_are_nearest_first_then_by_id = function(T)
    local rows = M.rowsFor(1, {
        [1] = P(0, 0), [5] = P(0, 300), [6] = P(0, 100), [7] = P(0, 100),
    })
    T.eq(#rows, 3)
    T.eq(rows[1].i, 6); T.eq(rows[2].i, 7); T.eq(rows[3].i, 5)
end

cases.coordinates_are_rounded_to_whole_metres = function(T)
    local rows = M.rowsFor(1, { [1] = P(0, 0), [2] = { x = 12.6, y = -3.4, z = 8.5, bucket = 0 } })
    T.eq(rows[1].x, 13); T.eq(rows[1].y, -3); T.eq(rows[1].z, 9)
end

cases.the_pin_cap_drops_the_farthest_drivers = function(T)
    local positions = { [1] = P(0, 0) }
    for i = 2, 12 do positions[i] = P(i * 10, 0) end
    local rows, note = M.rowsFor(1, positions, { maxPins = 3 })
    T.eq(#rows, 3)
    T.eq(rows[1].i, 2); T.eq(rows[3].i, 4)      -- 20 m, 30 m, 40 m: the near ones
    T.eq(note.droppedForCount, 8)
    T.eq(note.farthestM, 40)
end

cases.the_byte_budget_is_measured_not_counted = function(T)
    local positions = { [1] = P(0, 0) }
    for i = 2, 6 do positions[i] = P(i * 10, 0) end
    -- A measure of 100 bytes a row with a 250-byte budget admits two rows and refuses the third.
    local rows, note = M.rowsFor(1, positions, {
        budgetBytes = 250, measure = function() return 100 end,
    })
    T.eq(#rows, 2)
    T.eq(note.bytes, 200)
    T.eq(note.droppedForBytes, 3)
end

cases.one_oversized_row_still_travels_rather_than_emptying_the_map = function(T)
    -- The budget floor is 256 bytes and this row measures 900. Refusing everything would mean a viewer
    -- whose nearest neighbour has a long name sees an empty city, which is worse than one large packet.
    local rows = M.rowsFor(1, { [1] = P(0, 0), [2] = P(5, 0) }, {
        budgetBytes = 256, measure = function() return 900 end,
    })
    T.eq(#rows, 1)
end

cases.names_are_sanitized_and_cut_to_a_label = function(T)
    local rows = M.rowsFor(1, { [1] = P(0, 0), [2] = P(5, 0) }, {
        nameBytes = 10,
        nameFor = function() return "  Ker\ry\nAmarantos  " end,
    })
    -- Control characters become spaces, runs of whitespace collapse to one, the ends are trimmed, and what
    -- survives is cut to the label length. A carriage return does not silently join two words.
    T.eq(rows[1].n, "Ker y Amar")
end

cases.a_nameless_driver_carries_no_name_field = function(T)
    local rows = M.rowsFor(1, { [1] = P(0, 0), [2] = P(5, 0) }, {
        nameFor = function() return "   " end,
    })
    T.eq(rows[1].n, nil)
end

cases.label_refuses_a_non_string = function(T)
    T.eq(M.label(nil), nil)
    T.eq(M.label(42), nil)
end

-- ------------------------------------------------------------------ settings

cases.settings_clamp_rather_than_trust = function(T)
    local s = M.settings({ tickSeconds = 0, maxPins = 500, budgetBytes = 1, nameBytes = 999 })
    T.eq(s.tickSeconds, 2)
    T.eq(s.maxPins, 96)
    T.eq(s.budgetBytes, 256)
    T.eq(s.nameBytes, 128)
end

cases.settings_fall_back_when_a_tunable_is_absent = function(T)
    local s = M.settings(nil)
    T.eq(s.tickSeconds, M.DEFAULTS.tickSeconds)
    T.eq(s.maxPins, M.DEFAULTS.maxPins)
end

-- ------------------------------------------------------------------ reconcile

cases.an_unheld_row_is_created_once = function(T)
    local plan = M.reconcile({}, { { i = 2, x = 0, y = 0, z = 0, n = "A" } })
    T.eq(#plan.create, 1)
    T.eq(#plan.move, 0)
    T.eq(#plan.remove, 0)
end

cases.a_held_pin_is_moved_never_recreated = function(T)
    local pins = { [2] = { x = 0, y = 0, z = 0, n = "A" } }
    local plan = M.reconcile(pins, { { i = 2, x = 40, y = 0, z = 0, n = "A" } })
    T.eq(#plan.create, 0)
    T.eq(#plan.move, 1)
    T.eq(plan.move[1].x, 40)
end

cases.a_pin_that_barely_moved_is_left_alone = function(T)
    local pins = { [2] = { x = 0, y = 0, z = 0, n = "A" } }
    local plan = M.reconcile(pins, { { i = 2, x = 1, y = 1, z = 0, n = "A" } }, { moveEpsilonM = 3 })
    T.eq(#plan.move, 0)
    T.eq(#plan.retitle, 0)
end

cases.a_renamed_driver_is_retitled_without_a_move = function(T)
    local pins = { [2] = { x = 0, y = 0, z = 0, n = "A" } }
    local plan = M.reconcile(pins, { { i = 2, x = 0, y = 0, z = 0, n = "B" } })
    T.eq(#plan.move, 0)
    T.eq(#plan.retitle, 1)
    T.eq(plan.retitle[1].n, "B")
end

cases.a_driver_who_left_the_payload_loses_their_pin = function(T)
    local pins = { [2] = { x = 0, y = 0, z = 0 }, [3] = { x = 0, y = 0, z = 0 } }
    local plan = M.reconcile(pins, { { i = 3, x = 0, y = 0, z = 0 } })
    T.eq(#plan.remove, 1)
    T.eq(plan.remove[1], 2)
end

cases.pins_keyed_by_string_are_still_recognised = function(T)
    -- A client that built its table from a JSON round-trip has string keys; treating those as absent would
    -- recreate every pin every tick and burn the 128-blip quota.
    local plan = M.reconcile({ ["2"] = { x = 0, y = 0, z = 0 } }, { { i = 2, x = 0, y = 0, z = 0 } })
    T.eq(#plan.create, 0)
    T.eq(#plan.remove, 0)
end

cases.an_empty_payload_clears_every_pin = function(T)
    local plan = M.reconcile({ [2] = { x = 0, y = 0, z = 0 }, [4] = { x = 0, y = 0, z = 0 } }, {})
    T.eq(#plan.remove, 2)
    T.eq(plan.remove[1], 2); T.eq(plan.remove[2], 4)
end

return cases
