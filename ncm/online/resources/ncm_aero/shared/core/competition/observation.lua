-- ncm-core module: competition.observation
--
-- The first typed observation vocabulary (`31_CAPABILITY_AUDIT.md` section 9, ruled on 2026-09-26).
--
-- `competition.machine_knowledge` owns what an evidence ROW may be. This module owns what a
-- CHARACTERISTIC is: its unit, the values that are physically sayable, and whether a fresh reading is
-- worth persisting at all. Both are pure. Neither touches a database, a clock or a snapshot.
--
-- ---------------------------------------------------------------------------------------------------
-- Every characteristic here is a DEMONSTRATED-CAPABILITY FLOOR, and that is the whole design
-- ---------------------------------------------------------------------------------------------------
--
-- `28_MACHINE_KNOWLEDGE.md` section 7: *"`Highest speed observed: 108 km/h` is evidence. `MaiMai top
-- speed: 108 km/h` is a specification claim. Never silently convert the first into the second."* And
-- section 29: *"A lower bound on demonstrated capability is not an upper bound on maximum."*
--
-- So the running maximum is not stored because maxima are interesting. It is stored because *"this machine
-- has been seen doing at least X"* is the strongest honest sentence an observation can support. Every kind
-- below reads that way, which is why they can share one reducer without any of them lying:
--
--     observed_speed_floor     -- it has gone at least this fast
--     observed_lateral_accel   -- it has held at least this much cornering load
--     observed_yaw_rate        -- it has rotated at least this quickly
--     observed_slip_angle      -- it has slid at least this far out of line
--     observed_speed_retention -- it has carried at least this fraction of its speed through a corner
--     observed_gradient        -- it has climbed at least this steeply
--
-- **None of them is an estimate**, and this module deliberately contains no estimator. The envelope
-- mathematics of `28` sections 23-32 -- asymmetry, anti-midpoint (`IDEA-337`), determinism (`IDEA-338`) --
-- get their own reviewed proposal (`30` section 6, `31` section 10). Evidence first.
--
-- ---------------------------------------------------------------------------------------------------
-- Why two of six have producers and four do not
-- ---------------------------------------------------------------------------------------------------
--
-- The audit found the observation surface split down the middle: the authoritative SERVER snapshot carries
-- `velocity` and `angularVelocity` and no drivetrain; the CLIENT snapshot carries the drivetrain and no
-- velocity vectors. All six characteristics below are server-side and authoritative, which is why section 9
-- called them safe.
--
-- But `wired` is not about what is *reachable*, it is about what is *being read today*. The odometer's 1 Hz
-- server loop already reads speed and already derives cornering load for the thermal model; those two have
-- a real producer this hour. The other four need `velocity`/`angularVelocity` fields that loop does not
-- read yet. Declaring them costs nothing and keeps the vocabulary coherent; **writing one before its
-- producer exists would be exactly the fabrication this whole subsystem is built to refuse.**
local Core = NcmCore

Core.define("competition.observation", function()
    local M = { version = "0.1.0" }

    -- `unit`    -- the canonical name, stored in `evidence_json` so a bare number can never be reinterpreted.
    -- `display` -- how that unit is WRITTEN for a person. It lives here and not in the page because the page
    --              must never invent a unit for a value it did not compute; if a characteristic is ever
    --              restated in different units, this is the one place that changes.
    -- `floor`  -- below this, the reading is real but too ordinary to spend a row on. Not a validity bound.
    -- `ceiling` -- above this, something is wrong with the sample rather than remarkable about the car.
    -- `step`   -- how much better a reading must be before it displaces the stored one (see `promote`).
    M.CHARACTERISTICS = {
        observed_speed_floor = {
            unit = "kph", display = "km/h", label = "Highest speed observed",
            floor = 30.0, ceiling = 500.0, step = 5.0, wired = true,
        },
        observed_lateral_accel = {
            unit = "mps2", display = "m/s²", label = "Highest cornering load observed",
            floor = 2.0, ceiling = 30.0, step = 0.5, wired = true,
        },
        observed_yaw_rate = {
            unit = "radps", display = "rad/s", label = "Highest rotation rate observed",
            floor = 0.2, ceiling = 8.0, step = 0.1, wired = false,
        },
        observed_slip_angle = {
            unit = "deg", display = "°", label = "Largest slip angle observed",
            floor = 3.0, ceiling = 90.0, step = 2.0, wired = false,
        },
        observed_speed_retention = {
            unit = "ratio", display = "", label = "Best speed retention observed",
            floor = 0.3, ceiling = 1.0, step = 0.05, wired = false,
        },
        observed_gradient = {
            unit = "percent", display = "%", label = "Steepest climb observed",
            floor = 3.0, ceiling = 60.0, step = 2.0, wired = false,
        },
    }

    function M.characteristic(kind)
        return type(kind) == "string" and M.CHARACTERISTICS[kind] or nil
    end

    function M.isWired(kind)
        local c = M.characteristic(kind)
        return (c and c.wired) == true
    end

    --- Every characteristic that has a producer today. The host iterates this rather than hard-coding a
    --- list, so wiring the remaining four is a `wired = true` and a producer, not a hunt through callers.
    function M.wired()
        local out = {}
        for kind, c in pairs(M.CHARACTERISTICS) do if c.wired then out[#out + 1] = kind end end
        table.sort(out)
        return out
    end

    -- -----------------------------------------------------------------------------------------------
    -- Is this a sayable reading of this characteristic?
    -- -----------------------------------------------------------------------------------------------
    --
    -- This deliberately does NOT reuse `machine_knowledge.reading()`, which answers a different and lower
    -- question -- *"was this field readable at all?"*, where zero survives and only absence is refused.
    -- Here the question is *"is this a value of this quantity?"*, so a negative speed and a 4000 km/h speed
    -- are both refused by name. A sample that fails this is dropped; it never becomes a row and never
    -- becomes a zero.
    function M.reading(kind, raw)
        local c = M.characteristic(kind)
        if not c then return nil, "unknown_characteristic:" .. tostring(kind) end
        local n = tonumber(raw)
        if n == nil then return nil, "unreadable" end
        if n ~= n then return nil, "not_a_number" end                       -- NaN
        if n == math.huge or n == -math.huge then return nil, "not_finite" end
        if n < 0 then return nil, "negative" end
        if n > c.ceiling then return nil, "implausible" end
        return n
    end

    -- -----------------------------------------------------------------------------------------------
    -- Should this reading become a durable row?
    -- -----------------------------------------------------------------------------------------------
    --
    -- The producer samples at 1 Hz per machine. Writing every sample would be a flood of near-identical
    -- rows, and it would bury the thing the evidence exists for: `28` sections 9-10 want a *small* number
    -- of located, attributable observations that a player can go and investigate -- *"check the
    -- coordinates. Downhill."* -- not a telemetry stream with coordinates bolted on.
    --
    -- So a reading is promoted only when it is a materially better demonstration than the stored one.
    -- `prior` is nil the first time, and `step` keeps a car creeping up by 0.1 km/h from writing a row a
    -- second. The producer holds the running best in memory between promotions.
    --
    -- Returns `true` plus the value, or `false` plus the reason -- the reason is returned rather than
    -- logged so the caller can count refusals without this module knowing what a log is.
    function M.promote(kind, raw, prior)
        local value, why = M.reading(kind, raw)
        if value == nil then return false, why end
        local c = M.CHARACTERISTICS[kind]
        if value < c.floor then return false, "below_floor" end
        local p = tonumber(prior)
        if p ~= nil and value < p + c.step then return false, "not_materially_better" end
        return true, value
    end

    -- -----------------------------------------------------------------------------------------------
    -- The typed body of an evidence row
    -- -----------------------------------------------------------------------------------------------
    --
    -- `evidence_json` has existed unused and untyped since migration 016, and `30` section 2 marks it as
    -- the one column present but carrying nothing. It stayed that way on purpose: typing it before the
    -- capability audit said which characteristics NCM can honestly measure would have been a guess.
    --
    -- The audit has answered, so it gets a shape -- and a narrow one. The unit travels WITH the value
    -- because a bare number in a JSON column is how `101` becomes mph three years from now, and the kind
    -- travels with it so the body is still legible if it is ever read apart from its row.
    function M.body(kind, value)
        local v, why = M.reading(kind, value)
        if v == nil then return nil, why end
        return { kind = kind, value = v, unit = M.CHARACTERISTICS[kind].unit }
    end

    --- Everything the vocabulary currently declares, for the panel and for a human reading the gate output.
    function M.inventory()
        local out = {}
        for kind, c in pairs(M.CHARACTERISTICS) do
            out[#out + 1] = { kind = kind, unit = c.unit, display = c.display, label = c.label, wired = c.wired }
        end
        table.sort(out, function(a, b) return a.kind < b.kind end)
        return out
    end

    return M
end)
