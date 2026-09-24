-- ncm-core module: data.vehicle_identity
--
-- **The birth certificate, the odometer, and the place the death certificate will eventually go.** Pure.
--
-- NCM production stopped being an inventory count the day it started making individual persistent machines.
-- So each machine should be able to answer: what number NCM vehicle was I, what number from my manufacturer,
-- what number example of my model, how far have I actually travelled, and am I still an active machine.
--
-- ---------------------------------------------------------------------------------------------
-- The identities, which are five different things and are never collapsed (addendum section 29)
-- ---------------------------------------------------------------------------------------------
--
--   `vehicleKey`   the conceptual model              -- makigai_maimai
--   `record`       a TweakDB runtime configuration   -- Vehicle.v_standard2_makigai_maimai
--   `vehicleId`    an ephemeral live OPEN//77 entity -- changes every materialisation
--   `assetId`      THIS specific persistent machine  -- permanent, canonical, never reinterpreted
--   ordinals       immutable provenance numbers attached to that assetId
--
-- A new `vehicleId` after a CALL is not a new car. A new owner is not a new car. New paint is not a new car.
-- The machine remains the machine.
--
-- ---------------------------------------------------------------------------------------------
-- Ordinals are history, not array indices (addendum section 3)
-- ---------------------------------------------------------------------------------------------
--
-- Three independent sequences, because they are three different facts: NCM's whole production history, one
-- manufacturer's history, and one model's history. The first Ferrari need not be global #1 to be Ferrari #1.
--
-- Once assigned they are never changed, reused, compacted, renumbered around a deleted record, or derived
-- from `COUNT(*)`. If Ferrari #13 once legitimately existed, 13 stays consumed forever -- including after that
-- car is eventually retired. **Unique, immutable and auditable beats cosmetically gapless**, so a failed
-- transaction that has already reserved a number simply leaves a gap, and that is correct.
local Core = NcmCore

Core.define("data.vehicle_identity", function(C)
    local M = { version = "0.1.0" }

    -- ---------------------------------------------------------------------------------------------
    -- Origin: what kind of creation this was (addendum section 8)
    -- ---------------------------------------------------------------------------------------------
    --
    -- A temporary runtime spawn is not a manufactured machine, and neither is an admin test car. Only
    -- authoritative production consumes production ordinals -- otherwise `/ncm.mint` during a debugging
    -- session silently burns Ferrari #14 forever.
    M.ORIGIN = {
        PRODUCTION = "production",   -- primary-market manufacture, including the alpha launch allocation
        GRANT      = "grant",        -- admin / progression / test: a real persistent asset, no serial
    }

    --- Does an asset of this origin take numbers out of the production sequences?
    function M.consumesOrdinals(origin) return tostring(origin or "") == M.ORIGIN.PRODUCTION end

    M.SCOPES = { GLOBAL = "global", MAKER = "maker", MODEL = "model" }

    -- ---------------------------------------------------------------------------------------------
    -- Lifecycle (addendum sections 14, 15, 26)
    -- ---------------------------------------------------------------------------------------------
    --
    -- > **TERMINAL DOES NOT MEAN DELETED.** End of active biography, not erase object.
    --
    -- A retired machine keeps its assetId, all three ordinals, its provenance, its owner, its final mileage
    -- and its race history. It simply stops being drivable. Nothing in NCM may express vehicle death as a
    -- `DELETE`.
    M.LIFECYCLE = {
        ACTIVE = "active",
        RETIRED_TERMINAL_FAILURE = "retired_terminal_failure",
    }

    --- **Terminal mechanical failure is architecture only and is switched off.**
    ---
    --- We do not yet have a single kilometre of real NCM mileage evidence, and Night City's scale may make
    --- real-world intuition about lifespans completely wrong. Nothing may retire a vehicle until there is
    --- evidence, a shaped survival curve, simulation, QA, a migration story and a recovery policy for our own
    --- bugs (addendum sections 20 and 25). Irreversible loss of legitimate property is not something to get
    --- approximately right.
    M.TERMINAL_FAILURE_ENABLED = false

    --- The only door to a terminal state, and it is currently locked.
    ---
    --- Note what is NOT a reason: a missing runtime entity, a failed materialisation, a refused CALL, a paint
    --- failure, a migration fault or a corrupt row. "Couldn't spawn the car" is not "the car is dead"
    --- (addendum section 26). Retirement must always be one explicit authoritative transition.
    --- Returns ok, reason.
    function M.canRetire(req)
        if not M.TERMINAL_FAILURE_ENABLED then return false, "terminal_failure_disabled" end
        local from = req and tostring(req.from or M.LIFECYCLE.ACTIVE)
        if from ~= M.LIFECYCLE.ACTIVE then return false, "not_active" end
        if not (req and req.cause) then return false, "cause_required" end
        return true
    end

    function M.isActive(status)
        return tostring(status or M.LIFECYCLE.ACTIVE) == M.LIFECYCLE.ACTIVE
    end

    -- ---------------------------------------------------------------------------------------------
    -- Odometer (addendum sections 10-13)
    -- ---------------------------------------------------------------------------------------------

    --- A car cannot travel faster than this, so anything implying more did not travel at all. Generous on
    --- purpose: the fastest thing in Night City plus a wide margin, because this is a discontinuity filter
    --- and not a speed limit. 150 m/s is 540 km/h.
    M.MAX_SPEED_MPS = 150

    --- Samples further apart than this are not a segment. A gap means a stall, a reconnect or a streaming
    --- pause, and the straight line across it is not a journey.
    M.MAX_GAP_S = 6

    --- Below this, it is sensor noise standing still, not movement. Only used when no speed reading is
    --- available: at 1 Hz it corresponds to 0.9 km/h, which is uncomfortably close to a car genuinely
    --- creeping, and the owner watched the odometer tick up while a parked MaiMai "squirmed a little bit"
    --- (2026-09-23). Speed is the better discriminator where the platform gives us one -- see below.
    M.MIN_SEGMENT_M = 0.25

    --- A vehicle reporting less than this is parked, whatever its coordinates are doing. 0.2 m/s is
    --- 0.72 km/h; a car creeping in a car park does 3-8 km/h, so legitimate slow movement is nowhere near
    --- this and keeps counting. Deliberately NOT a minimum-speed threshold on real driving.
    M.STOPPED_MPS = 0.2

    --- How far past the reported speed a positional delta may go before it is treated as glitch rather than
    --- travel. Generous, because speed is sampled at an instant and the car accelerates between samples.
    M.SPEED_TOLERANCE = 1.6
    M.SPEED_SLACK_M = 2.0

    --- Decide whether the distance between two observations is real travel by one machine.
    ---
    --- **The rule that matters is that reconstruction must not invent kilometres** (addendum section 13). An
    --- asset that despawns at A and is CALLed back at B has not driven A to B, and a server restart, a
    --- streaming reload or an administrative relocation are the same case. Every one of them shows up here as
    --- either a changed asset, a gap in time, or an impossible speed -- so one filter covers all of them
    --- rather than each needing to be special-cased.
    ---
    --- **Speed is an independent witness, and that is the whole point.** Physics jitter moves a parked car's
    --- coordinates while its speedometer reads zero, so a position-only filter cannot tell squirming from
    --- creeping without also throwing away slow driving. Where the platform reports speed, this uses it two
    --- ways: a stationary reading rejects the delta outright, and a moving one CAPS it at what that speed
    --- could plausibly have covered. Capping rather than rejecting is deliberate -- a glitch inside a real
    --- journey should lose its excess, not the whole second of travel.
    ---
    --- Where speed is absent the old positional floor still applies, so this degrades rather than breaks.
    ---
    --- prev/now = { assetId, x, y, z, at, speedMps? }; returns { accept, metres, reason }.
    function M.segment(prev, now)
        if type(prev) ~= "table" or type(now) ~= "table" then return { accept = false, metres = 0, reason = "no_pair" } end
        if not prev.assetId or prev.assetId ~= now.assetId then
            -- Two different machines, or one that was not identified. Never attribute across that.
            return { accept = false, metres = 0, reason = "asset_changed" }
        end
        local dt = (tonumber(now.at) or 0) - (tonumber(prev.at) or 0)
        if dt <= 0 then return { accept = false, metres = 0, reason = "not_forward" } end
        if dt > M.MAX_GAP_S then return { accept = false, metres = 0, reason = "gap" } end
        local dx = (tonumber(now.x) or 0) - (tonumber(prev.x) or 0)
        local dy = (tonumber(now.y) or 0) - (tonumber(prev.y) or 0)
        local dz = (tonumber(now.z) or 0) - (tonumber(prev.z) or 0)
        -- Vertical movement counts: a car climbing a Night City ramp is still travelling.
        local metres = math.sqrt(dx * dx + dy * dy + dz * dz)
        if (metres / dt) > M.MAX_SPEED_MPS then
            -- A teleport, a materialisation somewhere else, or a streaming jump. Never mileage.
            return { accept = false, metres = 0, reason = "discontinuity" }
        end
        local vPrev, vNow = tonumber(prev.speedMps), tonumber(now.speedMps)
        if vPrev or vNow then
            local fastest = math.max(vPrev or 0, vNow or 0)
            if fastest < M.STOPPED_MPS then
                -- Coordinates moved, the car did not. This is the squirming case.
                return { accept = false, metres = 0, reason = "stationary_by_speed" }
            end
            local cap = fastest * dt * M.SPEED_TOLERANCE + M.SPEED_SLACK_M
            if metres > cap then
                return { accept = true, metres = cap, reason = "capped_to_speed" }
            end
            return { accept = true, metres = metres, reason = "travelled" }
        end
        -- No speed reading on this build: fall back to the positional floor.
        if metres < M.MIN_SEGMENT_M then return { accept = false, metres = 0, reason = "stationary" } end
        return { accept = true, metres = metres, reason = "travelled" }
    end

    -- ---------------------------------------------------------------------------------------------
    -- Presentation
    -- ---------------------------------------------------------------------------------------------

    --- `#0000001` is a way of WRITING a number, not the number itself (addendum section 9). Ordinals are
    --- stored as integers with no width limit, so vehicle 10,000,000 is representable and simply renders
    --- wider than seven digits rather than breaking.
    function M.formatOrdinal(n, pad)
        local v = math.floor(tonumber(n) or 0)
        if v <= 0 then return nil end
        local s = tostring(v)
        local width = tonumber(pad) or 7
        while #s < width do s = "0" .. s end
        return "#" .. s
    end

    --- Metres to a readable odometer reading. One decimal below 10 000 km and none above, because a driver
    --- reads this at a glance and 212,481 km says everything 212,481.3 km does.
    function M.formatOdometer(metres)
        local km = math.max(0, tonumber(metres) or 0) / 1000
        local rounded = (km < 10000) and (math.floor(km * 10 + 0.5) / 10) or math.floor(km + 0.5)
        local whole = math.floor(rounded)
        local frac = rounded - whole
        local s = tostring(whole)
        local out = ""
        while #s > 3 do out = "," .. s:sub(-3) .. out; s = s:sub(1, -4) end
        out = s .. out
        if km < 10000 then out = out .. "." .. tostring(math.floor(frac * 10 + 0.5)) end
        return out .. " km"
    end

    return M
end)
