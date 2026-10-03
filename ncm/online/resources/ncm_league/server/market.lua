-- Base Market host: market-scoped authored stock, starter grant and atomic purchase.
NcmMarket = {}

local Markets = NcmCore.get("economy.markets")
local Production = NcmCore.get("economy.production")
local Supply = NcmCore.get("economy.supply_profiles")
local Json = NcmCore.get("vocabulary.json")
local Chunks = NcmCore.get("vocabulary.chunks")
local Catalogue = NcmCore.get("data.vehicle_catalogue")
local ids = NcmCore.get("vocabulary.ids")
local hostRng = function() return math.random() end
local function now() return math.floor(Open77.time.unix()) end
local function serverId() return NcmCalendar.serverId() end
local function log(fmt, ...) print(("[ncm_league/market] " .. fmt):format(...)) end

local function driver(pid) return NcmCalendar.resolveDriver(tonumber(pid) or 0) end

--- A database flag, whichever way the driver hands it back: boolean, number or numeric string.
local function truthy(v)
    if type(v) == "boolean" then return v end
    return (tonumber(v) or 0) ~= 0
end

local function ensureStarter(driverId)
    return NcmEconomy.ensureStarter(driverId)
end

local function balanceOf(driverId)
    return NcmEconomy.balanceOf(driverId)
end

function NcmMarket.seed()
    local valid, why = Markets.validate()
    if not valid then return nil, why end
    local t = now()
    for _, market in ipairs(Markets.MARKETS) do
        MySQL.insert.await([[INSERT INTO market (market_id, display_name, kind, universally_known)
            VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE display_name=VALUES(display_name), kind=VALUES(kind),
            universally_known=VALUES(universally_known)]],
            { market.marketId, market.displayName, market.kind, market.universallyKnown and 1 or 0 })
    end
    for _, stock in ipairs(Markets.STARTER_STOCK) do
        local entry = Catalogue.byKey(stock.vehicleKey)
        local record = entry and entry.runtimeRecords[1]
        if not record then return nil, "stock_record_missing:" .. stock.vehicleKey end
        MySQL.insert.await([[INSERT IGNORE INTO vehicle_asset
            (asset_id, server_id, ncm_driver_id, vehicle_key, record, class, acquired_via, acquired_at,
             allocation_id, allocation_slot)
            VALUES (?, ?, NULL, ?, ?, ?, NULL, ?, 'alpha_launch', ?)]],
            { stock.assetId, serverId(), stock.vehicleKey, record, entry.category, t, stock.slot })
        MySQL.insert.await([[INSERT IGNORE INTO market_inventory
            (market_id, asset_id, price, state, listed_at) VALUES (?, ?, ?, 'available', ?)]],
            { Markets.BASE_ID, stock.assetId, stock.price, t })
        MySQL.insert.await([[INSERT IGNORE INTO vehicle_asset_transfer
            (transfer_id, idem_key, server_id, asset_id, kind, market_id, occurred_at)
            VALUES (?, ?, ?, ?, 'production', ?, ?)]],
            { ids.uuid4(hostRng), "production:" .. serverId() .. ":" .. stock.assetId,
              serverId(), stock.assetId, Markets.BASE_ID, t })
    end
    log("ready market=%s stock=%d starter=%d", Markets.BASE_ID, #Markets.STARTER_STOCK, Markets.STARTER_GRANT)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- PRIMARY PRODUCTION
--
-- Before this, `NcmMarket.seed()` above was the entire supply system: three hard-coded assets inserted once
-- at first boot. There was no scheduler, no replenishment and no path that could mint primary stock ever
-- again. Buying MaiMai #0000001 did not sell out the MaiMai -- it removed the MaiMai from NCM permanently,
-- because the payload listed available ASSETS and an offering with no assets has no row.
--
-- `economy.production` owns the arithmetic and the tick numbering; everything here is the database half.
-- ---------------------------------------------------------------------------------------------

--- How many unsold primary examples of this model actually exist. **Derived, never counted** -- the Market
--- must not be able to say "8 available" when seven purchasable rows exist. Both halves of the condition
--- matter: listed and available in this market, AND genuinely unowned.
local function availableCount(marketId, vehicleKey)
    return tonumber(MySQL.scalar.await([[SELECT COUNT(*)
        FROM market_inventory mi JOIN vehicle_asset a ON a.asset_id = mi.asset_id
        WHERE mi.market_id = ? AND mi.state = 'available'
          AND a.server_id = ? AND a.vehicle_key = ? AND a.ncm_driver_id IS NULL]],
        { marketId, serverId(), vehicleKey })) or 0
end

--- The asset ids a buyer may actually act on, oldest listing first. The offering is what the player sees;
--- an assetId is still what they buy (L99), so the card hands the purchase an exact individual.
local function availableAssets(marketId, vehicleKey, limit)
    return MySQL.query.await([[SELECT mi.asset_id, mi.price
        FROM market_inventory mi JOIN vehicle_asset a ON a.asset_id = mi.asset_id
        WHERE mi.market_id = ? AND mi.state = 'available'
          AND a.server_id = ? AND a.vehicle_key = ? AND a.ncm_driver_id IS NULL
        ORDER BY mi.listed_at, mi.asset_id LIMIT ]] .. tostring(tonumber(limit) or 12),
        { marketId, serverId(), vehicleKey }) or {}
end

--- Sales during the cycle that just closed: everything this model sold between the previous production
--- event and this one. A count of transactions and nothing else -- there is no buyer in this query, which is
--- why the supply engine structurally cannot treat one player buying ten differently from ten buying one
--- (addendum section 8).
local function soldBetween(marketId, vehicleKey, fromAt, toAt)
    return tonumber(MySQL.scalar.await([[SELECT COUNT(*)
        FROM market_inventory mi JOIN vehicle_asset a ON a.asset_id = mi.asset_id
        WHERE mi.market_id = ? AND mi.state = 'sold' AND a.server_id = ? AND a.vehicle_key = ?
          AND mi.sold_at >= ? AND mi.sold_at < ?]],
        { marketId, serverId(), vehicleKey, math.floor(fromAt or 0), math.floor(toAt or 0) })) or 0
end

--- The completed cycles this manufacturer gets to reason about, oldest first.
---
--- Read entirely from the production ledger, so there is no separate observation store that could drift from
--- what actually happened. Row N records the shelf as it stood when event N fired (`available_before`, i.e.
--- the close of cycle N-1) and the sales during that cycle; the supply that entered it is row N-1's `minted`.
--- That zip is the whole derivation.
local function cyclesFor(line, limit)
    local rows = MySQL.query.await([[SELECT tick_index, tick_at, available_before, ceiling, minted, sold_in_cycle
        FROM market_production_run
        WHERE server_id=? AND market_id=? AND vehicle_key=?
        ORDER BY tick_index DESC LIMIT ]] .. tostring(tonumber(limit) or 12),
        { serverId(), line.marketId, line.vehicleKey }) or {}
    local asc = {}
    for i = #rows, 1, -1 do asc[#asc + 1] = rows[i] end
    local cycles = {}
    for i = 2, #asc do
        cycles[#cycles + 1] = {
            endedAvailable = tonumber(asc[i].available_before) or 0,
            sold = tonumber(asc[i].sold_in_cycle) or 0,
            minted = tonumber(asc[i - 1].minted) or 0,
            capacity = tonumber(asc[i].ceiling) or line.ceiling,
        }
    end
    return cycles
end

--- Load this line's live plan, creating it the first time we ever see the line.
---
--- **The first sight of a line is the one moment initial allocation can happen, and it must be able to tell
--- an offering that has never opened from one that is already running.** An offering with production history
--- is mid-life: it resumes at the next index with its launch already behind it. Only a line with no history
--- at all gets its initial allocation, which is what stops this release from re-dropping stock onto the three
--- alpha models that have been trading for days (addendum section 3, packet section 16).
local function ensureState(line, t)
    local row = MySQL.single.await([[SELECT * FROM market_supply_state
        WHERE server_id=? AND market_id=? AND vehicle_key=?]],
        { serverId(), line.marketId, line.vehicleKey })
    if row then return row end
    local priorMax = tonumber(MySQL.scalar.await([[SELECT MAX(tick_index) FROM market_production_run
        WHERE server_id=? AND market_id=? AND vehicle_key=?]],
        { serverId(), line.marketId, line.vehicleKey }))
    local alreadyRunning = priorMax ~= nil
    local sched = Production.startSchedule(line, t)
    local profileId = Supply.profileId(Production.profileFor(line))
    local state = {
        next_tick_index = alreadyRunning and (priorMax + 1) or 0,
        -- A never-opened offering opens NOW; a running one keeps its cadence.
        next_tick_at = alreadyRunning and sched.nextAt or t,
        batch = sched.batch, interval_sec = sched.intervalSec,
        profile_id = profileId, logic_version = Supply.LOGIC_VERSION,
        sign_runs = 0, last_sign = 0, cycles_since_change = 0,
        initial_done = alreadyRunning and 1 or 0,
    }
    MySQL.insert.await([[INSERT IGNORE INTO market_supply_state
        (server_id, market_id, vehicle_key, next_tick_index, next_tick_at, batch, interval_sec,
         profile_id, logic_version, sign_runs, last_sign, cycles_since_change, initial_done, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { serverId(), line.marketId, line.vehicleKey, state.next_tick_index, state.next_tick_at,
          state.batch, state.interval_sec, state.profile_id, state.logic_version,
          0, 0, 0, state.initial_done, t })
    log("supply state opened %s profile=%s %s", line.vehicleKey, profileId,
        alreadyRunning and ("resuming at tick " .. tostring(state.next_tick_index)) or "launching")
    -- Re-read, so a racing caller gets the row that actually won the insert rather than the one it built.
    return MySQL.single.await([[SELECT * FROM market_supply_state
        WHERE server_id=? AND market_id=? AND vehicle_key=?]],
        { serverId(), line.marketId, line.vehicleKey })
end

--- Fire the committed production event if it is due, then choose the NEXT one.
---
--- **The order is the player-fairness rule** (addendum section 14). A schedule already on screen is never
--- revised: an evaluation always runs after its event has fired and only ever decides the event after it. A
--- player watching "2 vehicles in 47 minutes" will get that event; what changes is what comes next.
---
--- Returns the number minted.
local function runDue(line, state, t)
    if not state then return 0 end
    local nextAt = tonumber(state.next_tick_at) or 0
    if t < nextAt then return 0 end
    local index = tonumber(state.next_tick_index) or 0
    -- **`tonumber(true)` is nil.** The driver returns TINYINT(1) as a Lua boolean, so `tonumber(x) or 0`
    -- reads a stored 1 as 0 -- which made MaiMai tick 113 run as an INITIAL allocation on a line that had
    -- launched days earlier (live, 2026-09-23). It minted nothing only because the shelf happened to be full;
    -- on a line with capacity it would have re-dropped the launch allocation, which is exactly what addendum
    -- section 3 forbids. Accept both shapes, everywhere a flag column is read.
    local isInitial = not truthy(state.initial_done)
    local qty = isInitial and (tonumber(line.initialAllocation) or line.batch) or (tonumber(state.batch) or line.batch)
    local available = availableCount(line.marketId, line.vehicleKey)
    local plan = Production.plan({ line = line, available = available })
    local mintWant = math.min(qty, plan.capacity)

    -- Sales during the cycle that just closed, for the ledger and for the next evaluation.
    local prevAt = tonumber(MySQL.scalar.await([[SELECT tick_at FROM market_production_run
        WHERE server_id=? AND market_id=? AND vehicle_key=? AND tick_index < ?
        ORDER BY tick_index DESC LIMIT 1]],
        { serverId(), line.marketId, line.vehicleKey, index })) or 0
    local soldInCycle = prevAt > 0 and soldBetween(line.marketId, line.vehicleKey, prevAt, t) or 0

    -- **Claim, then verify by reading our own nonce back.** The primary key on
    -- (server, market, model, tick) lets exactly one caller insert; every other caller's INSERT IGNORE is a
    -- no-op. Whether that no-op is reported as 0 affected rows, an insert id, or nothing at all is a detail
    -- of the database driver, and NCM manufacturing vehicles must not rest on it. So the winner is whoever
    -- finds their own nonce in the row afterwards.
    local nonce = ids.uuid4(hostRng)
    local claimed = false
    local okClaim = pcall(function()
        MySQL.insert.await([[INSERT IGNORE INTO market_production_run
            (server_id, market_id, vehicle_key, tick_index, tick_at, claimed_at, claim_nonce,
             available_before, ceiling, batch, minted, sold_in_cycle, was_initial)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)]],
            { serverId(), line.marketId, line.vehicleKey, index, nextAt, t, nonce, available,
              line.ceiling, qty, soldInCycle, isInitial and 1 or 0 })
        local held = MySQL.scalar.await([[SELECT claim_nonce FROM market_production_run
            WHERE server_id=? AND market_id=? AND vehicle_key=? AND tick_index=?]],
            { serverId(), line.marketId, line.vehicleKey, index })
        claimed = (held == nonce)
    end)
    if not okClaim then log("production claim failed %s tick=%d", line.vehicleKey, index); return 0 end

    local minted = 0
    if claimed and mintWant > 0 then
        local entry = Catalogue.byKey(line.vehicleKey)
        local record = entry and entry.runtimeRecords[1]
        if record then
            local runKey = Production.runKey(serverId(), line, index)
            -- ONE reservation for the whole batch: five Hellas take five contiguous numbers out of each
            -- sequence in a single claim, so a concurrent allocation cannot interleave into the middle of
            -- them (addendum section 4).
            local ordinals = NcmProvenance and NcmProvenance.allocate
                and NcmProvenance.allocate(line.vehicleKey, mintWant) or nil
            if not ordinals then
                log("production %s tick=%d: no ordinals reserved; minting nothing rather than unserialled cars",
                    line.vehicleKey, index)
                mintWant = 0
            end
            for slot = 1, mintWant do
                -- Each produced unit is a real, individually identified asset (packet section 7).
                local assetId = NcmOwnership and NcmOwnership.manufacture
                    and NcmOwnership.manufacture(record, { allocationId = runKey, allocationSlot = slot,
                                                           ordinal = ordinals[slot] }) or nil
                if assetId then
                    if NcmComponents and NcmComponents.ensureMachine then
                        local owner = nil
                        local okParts, partsWhy = NcmComponents.ensureMachine(assetId, line.vehicleKey, owner)
                        if okParts == nil then log("factory components failed asset=%s: %s",assetId:sub(1,8),tostring(partsWhy)) end
                    end
                    local okList = pcall(function()
                        MySQL.insert.await([[INSERT IGNORE INTO market_inventory
                            (market_id, asset_id, price, state, listed_at) VALUES (?, ?, ?, 'available', ?)]],
                            { line.marketId, assetId, line.price, t })
                        MySQL.insert.await([[INSERT IGNORE INTO vehicle_asset_transfer
                            (transfer_id, idem_key, server_id, asset_id, kind, market_id, occurred_at)
                            VALUES (?, ?, ?, ?, 'production', ?, ?)]],
                            { ids.uuid4(hostRng), "production:" .. serverId() .. ":" .. assetId,
                              serverId(), assetId, line.marketId, t })
                    end)
                    if okList then minted = minted + 1 end
                end
            end
        else
            log("production %s tick=%d: no runtime record", line.vehicleKey, index)
        end
    end

    -- THE EVALUATION. Always after the event, never before -- see the note on player fairness above.
    local profileId = Supply.profileId(state.profile_id or Production.profileFor(line))
    local p = Supply.profile(profileId)
    local cycles = cyclesFor(line, math.max(4, (p.lookbackCycles or 4) + (p.glutCycles or 4) + 4))
    local facts = Supply.observe(cycles, p)
    facts.capacity = line.ceiling
    local decision = Supply.decide({
        profileId = profileId, envelope = Production.envelopeFor(line),
        current = { batch = tonumber(state.batch) or line.batch, intervalSec = tonumber(state.interval_sec) or line.cadenceSec },
        facts = facts,
        memory = { signRuns = tonumber(state.sign_runs) or 0, lastSign = tonumber(state.last_sign) or 0,
                   cyclesSinceChange = tonumber(state.cycles_since_change) or 0 },
    })
    local committed = Production.commitNext({ batch = decision.batch, intervalSec = decision.intervalSec }, t)

    pcall(function()
        MySQL.update.await([[UPDATE market_supply_state
            SET next_tick_index=?, next_tick_at=?, batch=?, interval_sec=?, profile_id=?, logic_version=?,
                sign_runs=?, last_sign=?, cycles_since_change=?, initial_done=1, updated_at=?
            WHERE server_id=? AND market_id=? AND vehicle_key=?]],
            { index + 1, committed.nextAt, decision.batch, decision.intervalSec, profileId, decision.logicVersion,
              decision.memory.signRuns or 0, decision.memory.lastSign or 0, decision.memory.cyclesSinceChange or 0,
              t, serverId(), line.marketId, line.vehicleKey })
    end)

    if claimed then
        local okJ, encoded = pcall(Json.encode, decision.signals)
        pcall(function()
            MySQL.update.await([[UPDATE market_production_run
                SET minted=?, profile_id=?, logic_version=?, signals_json=NULLIF(?, ''), decision=?,
                    next_batch=?, next_interval_sec=?, clamped=?
                WHERE server_id=? AND market_id=? AND vehicle_key=? AND tick_index=?]],
                -- Dense array, empty-string sentinel, NULL made by SQL. A nil here would truncate the
                -- parameter sequence and fail the whole statement -- the defect that silently lost every
                -- identity reveal on 2026-09-23.
                { minted, profileId, decision.logicVersion, (okJ and type(encoded) == "string") and encoded or "", decision.reason,
                  decision.batch, decision.intervalSec, decision.clamped and 1 or 0,
                  serverId(), line.marketId, line.vehicleKey, index })
        end)
        log("production %s tick=%d%s minted=%d/%d (%d/%d) | sold=%d | %s %s -> %dx/%dmin%s",
            line.vehicleKey, index, isInitial and " INITIAL" or "", minted, qty, available, line.ceiling,
            soldInCycle, profileId, decision.reason, decision.batch, math.floor(decision.intervalSec / 60),
            decision.clamped and " (clamped)" or "")
    else
        -- The event was already run, by another pass or before a restart. Advancing the plan anyway is the
        -- recovery path: without it a crash between the claim and the schedule write would stall this line
        -- forever on a tick that can never be claimed again.
        log("production %s tick=%d already claimed; plan advanced to tick %d", line.vehicleKey, index, index + 1)
    end
    return minted
end

--- One pass over every authored line. Safe to call repeatedly and cheap when nothing is due.
function NcmMarket.produce()
    local valid, why = Production.validate()
    if not valid then log("PRODUCTION DATA INVALID: %s -- no production will run", tostring(why)); return 0 end
    local t = now()
    local total = 0
    for _, line in ipairs(Production.LINES) do
        local okLine, minted = pcall(function()
            local state = ensureState(line, t)
            -- A line whose committed event is long overdue (a lengthy outage) fires ONCE and then re-plans
            -- from now. Replaying every missed event would be noise as well as pointless: production is
            -- ceiling-seeking, so one event reaches the same shelf a dozen would.
            return runDue(line, state, t)
        end)
        if okLine then total = total + (minted or 0)
        else log("production pass failed for %s: %s", line.vehicleKey, tostring(minted)) end
    end
    return total
end

--- The scheduler. One minute is far finer than any authored cadence, so a tick is picked up promptly without
--- the pass itself being what defines when production happens -- the clock does that.
function NcmMarket.start()
    CreateThread(function()
        Wait(8000)
        while true do
            local ok, err = pcall(NcmMarket.produce)
            if not ok then log("production pass failed: %s", tostring(err)) end
            Wait(60000)
        end
    end)
    log("production scheduler started: %d authored line(s)", #Production.LINES)
end

--- Every offering this market carries, stocked or not. This is the read model the panel draws.
--- WHERE DID THEY GO (L298, IDEA-852; owner: "SOLD OUT · 0/4 · Last batch: 4 units · Majestic Auto Sport 2 · Omega
--- Elite Racing 1 · Privateer 1"). The most recent production batch of a model at a market, by who holds each unit:
--- a Paddock team by name, an independent or a player as "Privateer", the unsold as "on the shelf". The full chain
--- (buyer, price, when, why) stays in the database -- `tools/npc-economy-audit.ps1` -- and only this summary is shown.
--- Returns { units, by = { { name, n } } } or nil when the model has never been produced here.
function NcmMarket.lastBatch(marketId, vehicleKey)
    local ok, rows = pcall(MySQL.query.await, [[SELECT mi.state, mi.sold_to_principal, mi.sold_to_driver_id, o.name AS org_name, pp.org_id AS person_org,
            po.name AS person_org_name
        FROM market_inventory mi JOIN vehicle_asset a ON a.asset_id = mi.asset_id
        LEFT JOIN paddock_org o ON o.server_id = a.server_id AND mi.sold_to_principal = CONCAT('org:', o.org_id)
        LEFT JOIN paddock_person pp ON pp.server_id = a.server_id AND mi.sold_to_principal = CONCAT('person:', pp.person_id)
        LEFT JOIN paddock_org po ON po.server_id = a.server_id AND po.org_id = pp.org_id
        WHERE mi.market_id = ? AND a.server_id = ? AND a.vehicle_key = ?
          AND a.allocation_id = (SELECT a2.allocation_id FROM market_inventory m2 JOIN vehicle_asset a2 ON a2.asset_id = m2.asset_id
              WHERE m2.market_id = ? AND a2.server_id = ? AND a2.vehicle_key = ? AND a2.allocation_id IS NOT NULL
              ORDER BY m2.listed_at DESC LIMIT 1)]],
        { marketId, serverId(), vehicleKey, marketId, serverId(), vehicleKey })
    if not ok or type(rows) ~= "table" or #rows == 0 then return nil end
    local counts, order = {}, {}
    local function add(name)
        if not counts[name] then counts[name] = 0; order[#order + 1] = name end
        counts[name] = counts[name] + 1
    end
    for _, r in ipairs(rows) do
        if r.state == "available" then add("on the shelf")
        elseif r.org_name then add(tostring(r.org_name))
        elseif r.person_org_name then add(tostring(r.person_org_name))
        else add("Privateer") end
    end
    local by = {}
    for _, name in ipairs(order) do by[#by + 1] = { name = name, n = counts[name] } end
    table.sort(by, function(x, y) if x.n ~= y.n then return x.n > y.n end return x.name < y.name end)
    return { units = #rows, by = by }
end

function NcmMarket.offerings(marketId)
    local t = now()
    local out = {}
    for _, line in ipairs(Production.linesFor(marketId)) do
        -- The LIVE committed plan, not the authored starting one: what a player sees is this manufacturer's
        -- current intention. The profile that chose it and the envelope it moves in stay server-side.
        local st = MySQL.single.await([[SELECT next_tick_at, batch, interval_sec FROM market_supply_state
            WHERE server_id=? AND market_id=? AND vehicle_key=?]], { serverId(), marketId, line.vehicleKey })
        local schedule = st and { batch = tonumber(st.batch), intervalSec = tonumber(st.interval_sec),
                                  nextAt = tonumber(st.next_tick_at) } or nil
        local o = Production.offering({ line = line, available = availableCount(marketId, line.vehicleKey),
                                        now = t, schedule = schedule })
        if o then
            o.assetIds = {}
            for _, row in ipairs(availableAssets(marketId, line.vehicleKey)) do
                o.assetIds[#o.assetIds + 1] = row.asset_id
            end
            -- The declared top speed, for the first of the six reserved buyer metrics. AUTHORED, not
            -- measured (`L157`) -- the panel labels it so, because section 5 of the capability audit shows
            -- the rated figure and the observed one disagree in a known direction. nil leaves the slot
            -- reading `Not rated`.
            local entry = Catalogue.byKey(line.vehicleKey)
            o.declaredTopSpeedKph = entry and Catalogue.declaredTopSpeedKph(entry) or nil
            o.lastBatch = NcmMarket.lastBatch(marketId, line.vehicleKey)
            out[#out + 1] = o
        end
    end
    return out
end

--- What the Market shows this player.
---
--- **This used to be a list of available assets, and that was the bug.** An offering with no unsold asset
--- produced no row, so buying the only MaiMai deleted the MaiMai from the Market rather than selling it out.
--- The payload is now a list of persistent OFFERINGS, one per authored line, each carrying its own derived
--- stock and the asset ids a buyer may act on. An offering at 0/8 is still an offering.
---
--- **It also used to discover every model in stock simply because the payload was built.** That is not
--- player-facing exposure, and with persistent offerings it would have become "open the Market once, learn
--- the whole shelf" -- exactly what packet section 11 forbids. Discovery now happens when a player selects
--- an offering and looks at it (`ncm:market.inspect`), which works identically whether it is stocked or
--- sold out.
--- **The market list used to be the literal `base_market`** (IDEA-251). It is now what this Driver has
--- learned of: every universally-known market plus their own grants, which is precisely the pair of arguments
--- `Markets.known(markets, grants)` has taken since it was written and never been passed. The shelf follows
--- the list, so a market this Driver has not reached contributes no offerings rather than being filtered out
--- of a payload that already built it.
---
--- Behaviour is unchanged today: Base Market is universally known, it is the only authored market, and
--- `Production.linesFor` returns nothing for anything else. What changes is that a second market becomes a
--- data question rather than an edit to this function.
function NcmMarket.payload(pid)
    local d = driver(pid)
    if not d then return nil, "no_driver" end
    ensureStarter(d.ncmDriverId)
    NcmMarketKnowledge.ensureUniversal(d.ncmDriverId)
    local balance = balanceOf(d.ncmDriverId)
    local known = Markets.known(Markets.MARKETS, NcmMarketKnowledge.grants(d.ncmDriverId))
    local markets, offerings = {}, {}
    for _, market in ipairs(known) do
        markets[#markets + 1] = { marketId = market.marketId, displayName = market.displayName }
        for _, o in ipairs(NcmMarket.offerings(market.marketId)) do
            -- The display name comes from the market that carries the offering. It used to be the string
            -- "Base Market" regardless, which would have mislabelled every line of the second market.
            o.marketName = market.displayName
            offerings[#offerings + 1] = o
        end
    end
    -- **`items` used to be a third copy of the vehicle list and it is gone.**
    --
    -- It was a flat row per purchasable asset -- ten fields, every one of them already present on the
    -- offering it was derived from -- and the reason given was that "an assetId is still what a purchase
    -- names" (`L99`). That is true and it does not need this table: the page purchases from the OFFERING
    -- it rendered (`panel.html`: `emit("panel:market.purchase", { marketId: o.marketId, assetId })`,
    -- where `assetId` comes from that offering's own `assetIds`). The only thing that ever read `items`
    -- was a length, for a badge.
    --
    -- So the count travels and the rows do not.
    local itemCount = 0
    for _, o in ipairs(offerings) do
        o.affordable = balance >= o.price
        o.eligible = true
        itemCount = itemCount + #(o.assetIds or {})
    end
    -- **Components resolve through the same known-market set as vehicles.** They used to bypass this loop
    -- entirely and ask `base_market` by name, so one screen held two different ideas of what a market is.
    -- Nothing changes while Base Market is the only one; the point is that a second component market is now
    -- authored data rather than a rewrite. Each row carries the market that offers it, so a part can say
    -- where it came from -- the vehicle half has done that since the display name bug.
    local componentOfferings = {}
    if NcmComponents and NcmComponents.marketOfferings then
        local keys = {} for _, o in ipairs(offerings) do keys[#keys + 1] = o.vehicleKey end
        for _, market in ipairs(known) do
            for _, c in ipairs(NcmComponents.marketOfferings(d.ncmDriverId, market.marketId, keys)) do
                c.marketName = market.displayName
                componentOfferings[#componentOfferings + 1] = c
            end
        end
    end
    -- **`vehicleOfferings` is not sent any more: it WAS `offerings`, under a second name, in the same
    -- message.** The page never needed it on the wire -- it assigns `marketData.vehicleOfferings =
    -- marketData.offerings` itself in both of its receive paths -- so shipping it doubled the vehicle
    -- half of this payload to tell the client something it was about to write down anyway.
    return { version = 2, markets = markets, offerings = offerings,
        componentOfferings = componentOfferings, itemCount = itemCount, balance = balance,
        partsEnabled = NcmComponents and NcmComponents.enabled and NcmComponents.enabled() or false,
        currency = "eddies", serverNow = now() }
end

--- A player selected an offering and looked at it. That is a legitimate encounter with information about
--- the model, so it is a legitimate Machine Index discovery -- and it stays legitimate at zero stock, since
--- what was encountered was the offering, not a car. Ownership has never been required and is not now.
---
--- `assetId` is passed only when there is a real one to point at; `revealIdentity` treats it as optional
--- evidence. The evidence key is per model, so repeated inspection is idempotent rather than noisy.
function NcmMarket.inspect(pid, marketId, vehicleKey)
    local d = driver(pid)
    if not d then return nil, "no_driver" end
    -- "A market this player can see" was a comment rather than a check: any authored line discovered its
    -- model, whether or not the Driver had reached that market. Now it is the check (IDEA-251).
    local access = NcmMarketKnowledge.state(d.ncmDriverId, tostring(marketId or ""))
    if not access then return nil, "market_unknown" end
    if not Markets.accessible(access.accessState) then return nil, "market_inaccessible" end
    local line = Production.line(tostring(marketId or ""), tostring(vehicleKey or ""))
    -- Only an authored offering of a market this player can see. Canonical catalogue membership alone
    -- discovers nothing (packet section 11, L).
    if not line then return nil, "unknown_offering" end
    if not (NcmCollection and NcmCollection.revealIdentity) then return nil, "collection_unavailable" end
    local first = availableAssets(line.marketId, line.vehicleKey, 1)[1]
    return NcmCollection.revealIdentity(pid, line.vehicleKey, {
        source = "primary_market", assetId = first and first.asset_id or nil })
end

--- Roughly how large a payload is, per section, without paying for a second encode of the whole thing.
--- Measured rather than estimated: `KB-136` was a size limit nobody could see because nothing printed a
--- number, and the same class of bug is not worth having twice.
local function payloadBytes(payload)
    local okAll, all = pcall(Json.encode, payload)
    if not okAll then return -1, "" end
    local parts = {}
    for _, key in ipairs({ "offerings", "componentOfferings", "markets" }) do
        local okPart, encoded = pcall(Json.encode, payload[key] or {})
        parts[#parts + 1] = ("%s=%d"):format(key, okPart and #encoded or -1)
    end
    return #all, table.concat(parts, " ")
end

local marketStreamSeq = 0
local MARKET_ROWS_PER_PACKET = 1

function NcmMarket.push(pid)
    local ok, payload = pcall(NcmMarket.payload, pid)
    if not ok or not payload then
        log("payload failed player=%s: %s", tostring(pid), tostring(payload))
        return
    end
    local bytes, breakdown = payloadBytes(payload)
    -- One line per push, because "the market does not load" and "the market is too large to send" look
    -- identical from a chair and are different bugs.
    log("payload player=%s %d bytes (%s offerings=%d components=%d)", tostring(pid), bytes, breakdown,
        #(payload.offerings or {}), #(payload.componentOfferings or {}))
    -- The 25 component offerings made the once-small NET EVENT itself the packet that disappeared. Client-side
    -- WebUI chunking cannot rescue a payload that never reached the client, so bound this hop independently.
    local head = {}
    for k,v in pairs(payload) do
        if k ~= "offerings" and k ~= "vehicleOfferings" and k ~= "componentOfferings" then head[k] = v end
    end
    local vehicles = Chunks.partition(payload.offerings or {}, MARKET_ROWS_PER_PACKET)
    local components = Chunks.partition(payload.componentOfferings or {}, MARKET_ROWS_PER_PACKET)
    marketStreamSeq = marketStreamSeq + 1
    local streamId = tostring(now()) .. ":" .. tostring(marketStreamSeq) .. ":" .. tostring(pid)
    TriggerClientEvent("ncm:market.stream.begin", pid, {
        id=streamId, head=head, vehicleParts=#vehicles, componentParts=#components,
    })
    for i,items in ipairs(vehicles) do
        TriggerClientEvent("ncm:market.stream.part", pid, {id=streamId,kind="vehicles",index=i,items=items})
    end
    for i,items in ipairs(components) do
        TriggerClientEvent("ncm:market.stream.part", pid, {id=streamId,kind="components",index=i,items=items})
    end
    log("stream player=%s id=%s packets=%d+%d rows-per-packet=%d", tostring(pid),streamId,
        #vehicles,#components,MARKET_ROWS_PER_PACKET)
end

function NcmMarket.purchase(pid, marketId, assetId)
    local d = driver(pid)
    if not d then return nil, "no_driver" end
    if type(assetId) ~= "string" or assetId == "" then return nil, "market_unknown" end
    -- **Knowledge and access are asked here; everything else stays inside the transaction.** The single
    -- statement below is the authority on visible / available / affordable precisely so those three cannot be
    -- read, then change, then acted on. Knowledge has no such race -- it is a durable per-Driver fact -- so it
    -- is the one gate that belongs in front. The refusal strings are `purchaseDecision`'s own; that function
    -- is deliberately still not called, because calling it would mean reading balance and stock out here and
    -- reintroducing the race the transaction exists to remove.
    local access = NcmMarketKnowledge.state(d.ncmDriverId, marketId)
    if not access then return nil, "market_unknown" end
    if not Markets.accessible(access.accessState) then return nil, "market_inaccessible" end
    ensureStarter(d.ncmDriverId)
    NcmMarketKnowledge.ensureUniversal(d.ncmDriverId)
    local t = now()
    local idem = "purchase:" .. serverId() .. ":" .. assetId
    local transferId = ids.uuid4(hostRng)
    local tx = {
        { query = [[UPDATE market_inventory mi
            SET mi.state='sold', mi.sold_at=?, mi.sold_to_driver_id=?
            WHERE mi.market_id=? AND mi.asset_id=? AND mi.state='available'
              AND (SELECT COALESCE(SUM(l.amount),0) FROM ledger l
                   WHERE l.ncm_driver_id=? AND l.server_id=?) >= mi.price]],
          values = { t, d.ncmDriverId, marketId, assetId, d.ncmDriverId, serverId() } },
        { query = [[INSERT IGNORE INTO ledger
            (ncm_driver_id, server_id, kind, amount, currency, ref, note, idem_key, market_id, asset_id)
            SELECT ?, ?, 'vehicle_purchase', -mi.price, 'eddies', mi.asset_id, 'Base Market purchase', ?, mi.market_id, mi.asset_id
            FROM market_inventory mi WHERE mi.market_id=? AND mi.asset_id=? AND mi.state='sold' AND mi.sold_to_driver_id=?]],
          values = { d.ncmDriverId, serverId(), idem, marketId, assetId, d.ncmDriverId } },
        { query = [[UPDATE vehicle_asset a JOIN market_inventory mi ON mi.asset_id=a.asset_id
            SET a.ncm_driver_id=?, a.acquired_via='purchase', a.granted_by=?, a.acquired_at=?
            WHERE a.asset_id=? AND mi.market_id=? AND mi.state='sold' AND mi.sold_to_driver_id=?
              AND a.ncm_driver_id IS NULL]],
          values = { d.ncmDriverId, marketId, t, assetId, marketId, d.ncmDriverId } },
        { query = [[UPDATE component_asset SET ncm_driver_id=?, acquired_at=COALESCE(acquired_at,?)
            WHERE machine_asset_id=? AND location_kind='installed' AND ncm_driver_id IS NULL]],
          values = { d.ncmDriverId, t, assetId } },
        { query = [[INSERT IGNORE INTO vehicle_asset_transfer
            (transfer_id, idem_key, server_id, asset_id, from_driver_id, to_driver_id, kind, market_id, amount, occurred_at)
            SELECT ?, ?, ?, mi.asset_id, NULL, ?, 'primary_purchase', mi.market_id, mi.price, ?
            FROM market_inventory mi WHERE mi.market_id=? AND mi.asset_id=? AND mi.state='sold' AND mi.sold_to_driver_id=?]],
          values = { transferId, idem, serverId(), d.ncmDriverId, t, marketId, assetId, d.ncmDriverId } },
    }
    local ok = MySQL.transaction.await(NcmEconomy.withBalanceLocks(tx,{d.ncmDriverId}))
    if not ok then return nil, "transaction_failed" end
    local owner = MySQL.scalar.await("SELECT ncm_driver_id FROM vehicle_asset WHERE asset_id=?", { assetId })
    if owner ~= d.ncmDriverId then return nil, "unavailable_or_unaffordable" end
    if NcmOwnership and NcmOwnership.invalidate then NcmOwnership.invalidate(d.ncmDriverId) end
    if NcmGuide and NcmGuide.push then NcmGuide.push(pid) end
    NcmMarket.push(pid)
    -- The name used to be looked up in the three-row bootstrap list, so every PRODUCED car would have been
    -- announced as "Vehicle". Ask the asset what it is.
    local key = MySQL.scalar.await("SELECT vehicle_key FROM vehicle_asset WHERE asset_id=?", { assetId })
    local entry = key and Catalogue.byKey(key) or nil
    return true, entry and entry.displayName or "Vehicle"
end

RegisterNetEvent("ncm:market", function() NcmMarket.push(tonumber(source) or 0) end)
RegisterNetEvent("ncm:market.purchase", function(marketId, assetId)
    local pid = tonumber(source) or 0
    CreateThread(function()
        local ok, why = NcmMarket.purchase(pid, tostring(marketId or ""), tostring(assetId or ""))
        TriggerClientEvent("ncm:market.purchase.result",pid,{ok=ok==true,name=ok and why or nil,reason=ok and nil or tostring(why)})
        if ok then NcmComms.send(pid,{id="market.purchase:"..tostring(assetId),category="transaction",priority="actionable",
            title=string.upper(why or "Vehicle").." PURCHASED",
            message="Ownership recorded. Open Machine Index to call this exact Machine.",reference="collection",surface="toast",repeatPolicy={mode="once"},durationMs=8000})
        else NcmComms.send(pid,{id="market.purchase.refused:"..tostring(assetId),category="warning",priority="actionable",
            title="PURCHASE REFUSED",message=tostring(why),reference="market",surface="toast",repeatPolicy={mode="cooldown",cooldownSec=2}}) end
    end)
end)

RegisterNetEvent("ncm:market.inspect", function(marketId, vehicleKey)
    local pid = tonumber(source) or 0
    CreateThread(function() pcall(NcmMarket.inspect, pid, tostring(marketId or ""), tostring(vehicleKey or "")) end)
end)

RegisterCommand("ncm.market", function(source) if (tonumber(source) or 0)>0 then CreateThread(function() NcmMarket.push(source) end) end end, false)

-- Console: what the shelf looks like and when it refills. KB-4 twin for a client with no WebUI, and the
-- fastest way to check production without a player connected.
RegisterCommand("ncm.supply", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function()
        local t = now()
        for _, o in ipairs(NcmMarket.offerings(Markets.BASE_ID)) do
            log("%-22s %2d/%-2d  %s  next %d in %s (every %d min)", o.displayName, o.available, o.ceiling,
                o.soldOut and "SOLD OUT" or "available", o.nextBatch,
                tostring(math.max(0, math.floor((o.nextProductionAt - t) / 60))) .. " min",
                math.floor((o.cadenceSec or 0) / 60))
        end
    end)
end, false)

-- Console: force the current production pass now, for QA. It is the SAME path the scheduler uses, so it is
-- bound by the same tick claims -- this cannot manufacture an extra batch, only run one that is due.
RegisterCommand("ncm.produce", function(source)
    if (tonumber(source) or 0) ~= 0 then return end
    CreateThread(function() log("manual production pass: %d minted", NcmMarket.produce() or 0) end)
end, false)
