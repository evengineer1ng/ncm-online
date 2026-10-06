-- ncm-core module: economy.production
--
-- **Primary-market supply: how the shelf refills.** Pure. The host hands in an authored line, the clock, and
-- how many unsold examples actually exist; this decides how many to make. It touches no database, mints
-- nothing and knows nothing about vehicles.
--
-- The rule the whole module exists to state (owner, 2026-09-23):
--
-- > **FINITE SUPPLY DOES NOT MEAN FINITE FOREVER.**
--
-- Before this, the Base Market's three bootstrap assets *were* the entire lifetime supply. Buying MaiMai
-- #0000001 did not sell out the MaiMai; it deleted the MaiMai from the world's only market, permanently, with
-- nothing in the code that could ever have made another one.
--
-- ---------------------------------------------------------------------------------------------
-- The four things an authored line says, and why each is a separate lever
-- ---------------------------------------------------------------------------------------------
--
--   * `ceiling`           the most UNSOLD examples allowed on the shelf at once. **Not** a cap on how many
--                        may exist in the world: a purchased car leaves primary inventory and lives forever,
--                        and the vacated capacity refills. Over time a model with a ceiling of 4 will have
--                        produced far more than 4 (packet section 14). Never dynamic.
--   * `initialAllocation` how many enter primary inventory when the offering first opens. Once, ever.
--   * `envelope`          the hard bounds -- min/max batch, min/max interval -- that a manufacturer chooses
--                        its schedule inside and can never leave.
--   * `batch` / `cadence` the STARTING schedule, used until there is enough market history to choose one.
--
-- **Cadence and batch are no longer fixed forever.** They start at an authored schedule and are then chosen
-- each cycle by `economy.supply_profiles`, inside an authored envelope this module owns. What stays static is
-- everything that matters to a player who already bought something: identity, price, shelf capacity, initial
-- allocation, and the bounds themselves. See L118.
--
-- **Cadence and batch are deliberately not collapsed into a rate.** "1 every 30 min" and "2 every 60 min"
-- have the same long-run average and are different supply chains: the first puts a car on the shelf at T+30,
-- the second leaves it empty until T+60 and then puts two there. Averaging them away would delete the only
-- thing that makes one manufacturer feel different from another. Nothing here converts to units-per-hour.
--
-- ---------------------------------------------------------------------------------------------
-- Idempotency (packet section 8, and the addendum's section 17)
-- ---------------------------------------------------------------------------------------------
--
-- Ticks are INDEXED and the index is CLAIMED. The first version derived the index arithmetically from a fixed
-- epoch, which was exactly right while cadence was fixed forever and is meaningless now a manufacturer may
-- change it. A tick index is now simply the next number in a per-line sequence, and the committed instant is
-- persisted alongside it.
--
-- **The guarantee is unchanged, because it never lived in the arithmetic.** It lives in the uniqueness of the
-- claim on (server, market, model, index): the host writes that row before it mints anything and verifies the
-- claim by reading its own nonce back. A restart, a redeploy, a retry or a second scheduler all collide on it.
-- And even if a claim were somehow lost, `plan` is ceiling-seeking, so the worst case is a shelf at exactly
-- its authored maximum. Restarting NCM is not a way to manufacture vehicles or to re-roll a schedule.
local Core = NcmCore

Core.define("economy.production", function(C)
    local Catalogue = C.get("data.vehicle_catalogue")
    local Markets = C.get("economy.markets")
    local M = { version = "0.1.0" }

    --- Manufacturer defaults. A badge has a temperament, but it does not force every model wearing it to
    --- behave the same: a line may name its own profile and the model wins (packet section 5). Keyed by the
    --- catalogue's manufacturer name, lowercased.
    M.MANUFACTURERS = {
        makigai = { profile = "volume_responsive" },   -- cheap, plentiful, chases demand
        thorton = { profile = "steady_hand" },         -- unremarkable and dependable
        archer  = { profile = "scarcity_keeper" },     -- protects scarcity over availability
    }

    --- Alpha supply. Provisional and expected to be tuned once real population is known: these are levers,
    --- not balance. The shape is the deliberate part -- cheaper machines are more plentiful and arrive more
    --- often, so the bottom of the ladder is dependable (packet section 6) while the top stays scarce.
    ---
    --- Each row authors, and the dynamic system may never change:
    ---   `price`             what it costs
    ---   `ceiling`           shelf capacity: the most UNSOLD examples allowed at once
    ---   `initialAllocation` how many enter primary inventory when the offering first opens, once, ever
    ---   `envelope`          the hard bounds the manufacturer chooses its schedule inside
    --- and starts at:
    ---   `batch` / `cadenceSec`   the first committed schedule, before any market history exists
    M.LINES = {
        { marketId = "base_market", vehicleKey = "makigai_maimai", price = 2500,
          ceiling = 8, initialAllocation = 6, batch = 4, cadenceSec = 30 * 60,
          envelope = { batchMin = 1, batchMax = 6, intervalMin = 15 * 60, intervalMax = 8 * 3600 } },
        { marketId = "base_market", vehicleKey = "thorton_galena", price = 4500,
          ceiling = 6, initialAllocation = 4, batch = 3, cadenceSec = 60 * 60,
          envelope = { batchMin = 1, batchMax = 4, intervalMin = 30 * 60, intervalMax = 24 * 3600 } },
        { marketId = "base_market", vehicleKey = "archer_hella",   price = 7500,
          ceiling = 4, initialAllocation = 2, batch = 2, cadenceSec = 120 * 60,
          envelope = { batchMin = 1, batchMax = 2, intervalMin = 60 * 60, intervalMax = 72 * 3600 } },
    }

    -- Every discovered physical terminal owns its own shelves. Values are conservative launch balancing;
    -- identity and placement are authored, while quantities can be tuned after live population evidence.
    local priceByPrestige={ [1]=6000,[2]=12000,[3]=28000,[4]=52000,[5]=90000 }
    for _,market in ipairs(Markets.MARKETS) do
        for _,vehicleKey in ipairs(market.vehicles or {}) do
            local entry=Catalogue.byKey(vehicleKey); local prestige=(entry and entry.prestige) or 3
            M.LINES[#M.LINES+1]={marketId=market.marketId,vehicleKey=vehicleKey,price=priceByPrestige[prestige],
                ceiling=math.max(1,6-prestige),initialAllocation=1,batch=1,cadenceSec=(2+prestige)*3600,
                envelope={batchMin=1,batchMax=math.max(1,3-math.floor(prestige/2)),intervalMin=3600,intervalMax=(12+prestige*12)*3600}}
        end
    end

    --- Which supply profile governs this line: the model's own, else its manufacturer's, else the default.
    function M.profileFor(line, entry)
        if type(line) == "table" and line.profile then return line.profile end
        entry = entry or (type(line) == "table" and Catalogue.byKey(line.vehicleKey)) or nil
        local maker = entry and entry.manufacturer and tostring(entry.manufacturer):lower() or nil
        local defaults = maker and M.MANUFACTURERS[maker] or nil
        return defaults and defaults.profile or nil      -- nil lets supply_profiles apply its own default
    end

    --- The authored envelope, with the module's own conservative fallback for a line that omits one.
    function M.envelopeFor(line)
        if type(line) == "table" and type(line.envelope) == "table" then return line.envelope end
        local batch = (type(line) == "table" and tonumber(line.batch)) or 1
        local cadence = (type(line) == "table" and tonumber(line.cadenceSec)) or 3600
        -- A line with no envelope cannot move: bounds equal to its authored schedule.
        return { batchMin = batch, batchMax = batch, intervalMin = cadence, intervalMax = cadence }
    end

    function M.linesFor(marketId)
        local out = {}
        for _, l in ipairs(M.LINES) do if l.marketId == marketId then out[#out + 1] = l end end
        return out
    end

    function M.line(marketId, vehicleKey)
        for _, l in ipairs(M.LINES) do
            if l.marketId == marketId and l.vehicleKey == vehicleKey then return l end
        end
        return nil
    end

    --- Authored data is only as good as its worst row, and a bad one here is a market that cannot restock.
    --- Refuses at boot rather than producing something nonsensical at three in the morning.
    function M.validate()
        local seen = {}
        for i, l in ipairs(M.LINES) do
            local at = "line " .. i .. " (" .. tostring(l.vehicleKey) .. ")"
            if type(l.marketId) ~= "string" or l.marketId == "" then return false, "bad_market:" .. at end
            if type(l.vehicleKey) ~= "string" or not Catalogue.byKey(l.vehicleKey) then
                return false, "unknown_vehicle:" .. tostring(l.vehicleKey)
            end
            local key = l.marketId .. "/" .. l.vehicleKey
            -- Two lines for one model in one market would race each other for the same shelf.
            if seen[key] then return false, "duplicate_line:" .. key end
            seen[key] = true
            local function whole(v) return type(v) == "number" and v == math.floor(v) end
            if not whole(l.price) or l.price < 0 then return false, "bad_price:" .. at end
            if not whole(l.ceiling) or l.ceiling < 0 then return false, "bad_ceiling:" .. at end
            -- A batch of zero is a line that can never restock; say so now rather than look broken later.
            if not whole(l.batch) or l.batch < 1 then return false, "bad_batch:" .. at end
            if not whole(l.cadenceSec) or l.cadenceSec < 1 then return false, "bad_cadence:" .. at end
            -- The initial allocation is a one-time drop onto the shelf, so it cannot exceed the shelf.
            if l.initialAllocation ~= nil then
                if not whole(l.initialAllocation) or l.initialAllocation < 0 then return false, "bad_initial:" .. at end
                if l.initialAllocation > l.ceiling then return false, "initial_over_ceiling:" .. at end
            end
            -- The envelope is the manufacturer's cage. A malformed one would either pin it or free it, and
            -- both are worse than refusing to start.
            local e = M.envelopeFor(l)
            if not whole(e.batchMin) or e.batchMin < 1 then return false, "bad_envelope_batch_min:" .. at end
            if not whole(e.batchMax) or e.batchMax < e.batchMin then return false, "bad_envelope_batch_max:" .. at end
            if not whole(e.intervalMin) or e.intervalMin < 1 then return false, "bad_envelope_interval_min:" .. at end
            if not whole(e.intervalMax) or e.intervalMax < e.intervalMin then return false, "bad_envelope_interval_max:" .. at end
            -- The starting schedule must itself be legal, or the very first decision would begin by
            -- correcting authored data instead of reading the market.
            if l.batch < e.batchMin or l.batch > e.batchMax then return false, "start_batch_outside_envelope:" .. at end
            if l.cadenceSec < e.intervalMin or l.cadenceSec > e.intervalMax then return false, "start_cadence_outside_envelope:" .. at end
        end
        return true
    end

    --- The schedule a brand-new offering starts on, before any market history exists.
    ---
    --- Ticks used to be derived from the epoch (`epoch + n * cadence`), which was exactly right while cadence
    --- was fixed forever and is meaningless now that a manufacturer may change it. A tick index is now simply
    --- the next number in a per-line sequence, and the committed instant is persisted. Idempotency is
    --- unaffected: the guarantee was always the uniqueness of the claim on (server, market, model, index),
    --- never the arithmetic that produced the index.
    function M.startSchedule(line, at)
        return { batch = line.batch, intervalSec = line.cadenceSec,
                 nextAt = (tonumber(at) or 0) + line.cadenceSec }
    end

    --- The next committed event after one has just fired, given the schedule chosen for it.
    function M.commitNext(schedule, firedAt)
        return { batch = schedule.batch, intervalSec = schedule.intervalSec,
                 nextAt = (tonumber(firedAt) or 0) + schedule.intervalSec }
    end

    --- How many to make right now.
    ---
    ---     mint = min(batch, max(0, ceiling - available))
    ---
    --- Ceiling-SEEKING rather than ceiling-checking, which is what makes the whole system self-healing: a
    --- tick that was skipped, half-finished or lost is corrected by the next one, and no sequence of ticks
    --- can ever put the shelf above its ceiling. A tick with no capacity still happened -- it simply had
    --- nowhere to put anything (packet section 3).
    ---
    --- req = { line, available } -> { mint, capacity, atCeiling }
    function M.plan(req)
        local line = req and req.line
        if type(line) ~= "table" then return { mint = 0, capacity = 0, atCeiling = false } end
        local available = math.max(0, math.floor(tonumber(req.available) or 0))
        -- Negative capacity is not an error and is never corrected downward: a ceiling lowered below current
        -- stock means production pauses, never that real assets are destroyed (packet section 15).
        local capacity = math.max(0, line.ceiling - available)
        local mint = math.min(line.batch, capacity)
        return { mint = mint, capacity = capacity, atCeiling = available >= line.ceiling }
    end

    --- The claim key for one tick of one line. The host writes this as a unique row before minting, so a
    --- restart, a retry or a duplicate scheduler all collide on it instead of manufacturing twice.
    function M.runKey(serverId, line, index)
        return table.concat({ "production", tostring(serverId), line.marketId, line.vehicleKey, tostring(index) }, ":")
    end

    --- What the Market shows for one model, stock or no stock.
    ---
    --- **An offering is not an asset.** That distinction is the packet's central correction: the old Market
    --- payload was a list of individual available assets, so selling the only MaiMai did not sell out the
    --- MaiMai, it deleted it. An offering is a persistent shelf position for a model; the assets are what is
    --- currently standing on it. A shelf with nothing on it is still a shelf.
    ---
    --- req = { line, available, now, schedule, entry } -> the offering read model, or nil without a
    --- catalogue entry. `schedule` is the live committed event ({ batch, intervalSec, nextAt }); without one
    --- the authored starting schedule is described instead, which is what a not-yet-opened offering looks
    --- like.
    function M.offering(req)
        local line = req and req.line
        if type(line) ~= "table" then return nil end
        local entry = req.entry or Catalogue.byKey(line.vehicleKey)
        if not entry then return nil end
        local available = math.max(0, math.floor(tonumber(req.available) or 0))
        local sched = type(req.schedule) == "table" and req.schedule
            or M.startSchedule(line, tonumber(req.now) or 0)
        local nextAt, nextBatch = sched.nextAt, sched.batch
        return {
            marketId = line.marketId,
            vehicleKey = line.vehicleKey,
            displayName = entry.displayName,
            manufacturer = entry.manufacturer,
            category = entry.category,
            price = line.price,
            available = available,
            ceiling = line.ceiling,
            soldOut = available <= 0,
            -- Authored supply, stated honestly: when the next tick is and how much it may make. Never a
            -- promise of inventory -- someone may buy the lot in between (packet section 13).
            nextProductionAt = nextAt,
            nextBatch = nextBatch,
            -- The CURRENT cadence, which is a live fact about this market and may differ from the authored
            -- starting one. Players may see it; they may not see the envelope it moves inside, the profile
            -- that chose it, or why (packet section 15).
            cadenceSec = sched.intervalSec,
            -- Says only THAT schedules move, never how. This is the whole player-facing contract: changing
            -- production must read as the manufacturer responding to the market, not as the operator
            -- intervening (packet section 29).
            scheduleDynamic = true,
        }
    end

    return M
end)
