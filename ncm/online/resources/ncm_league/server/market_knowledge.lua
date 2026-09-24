-- Which markets a Driver has learned of, and on what footing (IDEA-251).
--
-- `player_market_knowledge` was created by migration 017 and then **never read or written** -- its only
-- reference in the whole repository was its own `CREATE TABLE`, and it has carried 0 rows since. `NcmMarket`
-- shipped against the simpler path instead: the payload named `base_market` as a literal and the purchase
-- gate compared against `Markets.BASE_ID`. That works for exactly as long as there is one market.
--
-- It is the channel two designs already depend on:
--
--   * `IDEA-298` -- exclusivity lives in **access**, not in the identity of the asset. A2 ruled that a team
--     machine is an ordinary serialised machine; what is scarce is the channel it comes through. That channel
--     is `access_state`.
--   * `28_MACHINE_KNOWLEDGE.md` section 6 -- a market is an information institution. What a Driver can read
--     about machines depends on which markets they have reached.
--
-- **Nothing here gates Base Market.** `Markets.known()` returns universally-known markets whether or not a
-- row exists, so this table is provenance, not permission, until `IDEA-298` produces a non-universal market.
-- That is deliberate: wiring the write path while the read path still cannot lock anyone out means the
-- migration to real restricted access is a vocabulary change, not a behaviour change.
NcmMarketKnowledge = {}

local Markets = NcmCore.get("economy.markets")
local function now() return math.floor(Open77.time.unix()) end
local function serverId() return NcmCalendar.serverId() end
local function log(fmt, ...) print(("[ncm_league/market_knowledge] " .. fmt):format(...)) end

--- Record that this Driver knows this market exists. **First sight is written once and never updated**, the
--- same rule as `vehicle_discovery.first_discovered_at`: a later re-encounter is not a new discovery, and
--- rewriting the timestamp would destroy the only fact the row exists to hold. `INSERT IGNORE` is what makes
--- that true rather than a convention, so the call is safe to make on every market open.
function NcmMarketKnowledge.learn(driverId, marketId, sourceKind, sourceRef, accessState)
    local fact, why = Markets.discovery({
        driverId = driverId, serverId = serverId(), marketId = marketId, firstKnownAt = now(),
        sourceKind = sourceKind, sourceRef = sourceRef, accessState = accessState })
    if not fact then
        log("refused discovery driver=%s market=%s: %s", tostring(driverId), tostring(marketId), tostring(why))
        return nil, why
    end
    MySQL.insert.await([[INSERT IGNORE INTO player_market_knowledge
        (ncm_driver_id, server_id, market_id, first_known_at, source_kind, source_ref, access_state)
        VALUES (?, ?, ?, ?, ?, ?, ?)]],
        { fact.driverId, fact.serverId, fact.marketId, fact.firstKnownAt,
          fact.sourceKind, fact.sourceRef, fact.accessState })
    return true
end

--- Every universally-known market, recorded for this Driver. Called where `ensureStarter` is called, because
--- that is the first moment the league host has a resolved Driver and a market in the same breath.
function NcmMarketKnowledge.ensureUniversal(driverId)
    for _, market in ipairs(Markets.MARKETS) do
        if market.universallyKnown then
            NcmMarketKnowledge.learn(driverId, market.marketId, "universal", nil, "open")
        end
    end
end

--- Market ids this Driver has learned of **beyond** the universal ones -- exactly the `grants` argument
--- `Markets.known(markets, grants)` has taken since it was written, and never been passed.
function NcmMarketKnowledge.grants(driverId)
    local out = {}
    local rows = MySQL.query.await([[SELECT market_id, access_state FROM player_market_knowledge
        WHERE ncm_driver_id = ? AND server_id = ?]], { driverId, serverId() }) or {}
    for _, row in ipairs(rows) do
        local market = Markets.byId(row.market_id)
        if market and not market.universallyKnown and Markets.accessible(row.access_state) then
            out[#out + 1] = row.market_id
        end
    end
    return out
end

--- What this Driver knows about one market, or nil if they have never heard of it. A universally-known
--- market answers `open` even with no row: the row is the record of the knowledge, not its source.
function NcmMarketKnowledge.state(driverId, marketId)
    local market = Markets.byId(marketId)
    if not market then return nil end
    local row = MySQL.single.await([[SELECT first_known_at, source_kind, source_ref, access_state
        FROM player_market_knowledge WHERE ncm_driver_id = ? AND server_id = ? AND market_id = ?]],
        { driverId, serverId(), marketId })
    if row then
        return { firstKnownAt = tonumber(row.first_known_at), sourceKind = row.source_kind,
                 sourceRef = row.source_ref, accessState = row.access_state }
    end
    if market.universallyKnown then
        return { firstKnownAt = nil, sourceKind = "universal", sourceRef = nil, accessState = "open" }
    end
    return nil
end
