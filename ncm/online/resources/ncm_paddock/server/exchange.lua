-- ncm_paddock / server / exchange -- the posted Exchange (L249 step 5; owner: "the exchange needs a system where npcs
-- and players can post their desired objects to trade, which npcs and players can offer trades for").
--
-- A BOARD beside L194's live two-party Exchange. Anyone -- a player ("driver:<id>"), a Paddock team ("org:<id>"), an
-- independent racer ("person:<id>") -- posts:
--   offer  one of their STORED parts at an asking price; bids are cash (a part may be added as a sweetener)
--   want   a family and tier, up to a price; bids are a stored part of exactly that, at a cash price <= theirs
-- and the poster accepts one bid. Rules: `economy.exchange_posts`. Persistence: schema 056.
--
-- RESERVATION, NOT TRANSFER. A part in an open post or bid has a row in `exchange_reservation` (primary key: the
-- part), so it cannot be promised twice. Closing a post or bid releases it; `PaddockExchange.sweep` expires and
-- releases at every pass and at boot (the expiry recovery L194 said this second product needed).
--
-- SETTLEMENT IS ONE TRANSACTION AND ONE GATE.
--   1. balance locks for every player whose money moves (the `economy_balance_lock` protocol, wallet.lua);
--   2. each part moves ONLY from the owner and place it is expected at (a player's storage, an NPC's storage);
--   3. the GATE: an `exchange_settlement` row, inserted only if every part now sits with its new owner, the payer can
--      pay, the post is still open at the bid's revision and the bid is still open -- its primary key on the post
--      means a post settles once;
--   4. any part step 2 moved is put back unless the gate exists (a partial move never survives);
--   5. every money step (ledger rows for players; `paddock_org`/`paddock_person` cash plus `npc_money` for NPCs), the
--      post/bid states and the reservation release are conditional on the gate.
-- Before an NPC's money is checked by SQL the store is flushed, so the database holds what the Paddock holds.
PaddockExchange = { stats = { posts = 0, bids = 0, settled = 0, failed = 0, npcPosts = 0, npcBids = 0 } }

local U = PaddockUtil
local log = U.logger("exchange")
local EX = NcmCore.get("economy.exchange_posts")
local NM = NcmCore.get("economy.npc_market")
local ids = NcmCore.get("vocabulary.ids")
local function set(k, d) return PaddockSettings.get(k, d) end
local function rng() return math.random() end
local stats = PaddockExchange.stats

-- ------------------------------------------------------------------------------------------------- SQL fragments

local function ownerIs(key)
    local kind, id = EX.split(key)
    if kind == "driver" then return "ncm_driver_id = ?", { id } end
    return "ncm_driver_id IS NULL AND owner_principal_kind = ? AND owner_principal_id = ?", { kind, id }
end
local function ownerStored(key)
    local kind, id = EX.split(key)
    if kind == "driver" then return "ncm_driver_id = ? AND location_kind = 'storage' AND machine_asset_id IS NULL", { id } end
    return "ncm_driver_id IS NULL AND owner_principal_kind = ? AND owner_principal_id = ? AND location_kind = 'npc_storage'", { kind, id }
end
local function ownerSet(key, t)
    local kind, id = EX.split(key)
    if kind == "driver" then
        return [[ncm_driver_id = ?, owner_principal_kind = NULL, owner_principal_id = NULL, location_kind = 'storage',
            machine_asset_id = NULL, acquired_via = 'exchange', acquired_at = ?]], { id, t }
    end
    return [[ncm_driver_id = NULL, owner_principal_kind = ?, owner_principal_id = ?, location_kind = 'npc_storage',
        machine_asset_id = NULL, acquired_via = 'exchange', acquired_at = ?]], { kind, id, t }
end
local function cat(...)
    local out = {}
    for _, list in ipairs({ ... }) do for _, v in ipairs(list) do out[#out + 1] = v end end
    return out
end

-- --------------------------------------------------------------------------------------------------------- reads

--- A part's facts: { assetId, owner (key), stored, family, tier, price, name }.
function PaddockExchange.part(assetId)
    local r = MySQL.single.await([[SELECT a.asset_id, a.ncm_driver_id, a.owner_principal_kind, a.owner_principal_id, a.location_kind,
        a.machine_asset_id, a.design_id, d.family, d.tier, d.price, d.effect, d.code, d.display_manufacturer, d.subtitle
        FROM component_asset a JOIN component_design d ON d.design_id = a.design_id WHERE a.asset_id = ? AND a.server_id = ?]],
        { tostring(assetId or ""), U.sid() })
    if not r then return nil end
    local owner = r.ncm_driver_id and EX.principal("driver", r.ncm_driver_id)
        or (r.owner_principal_id and EX.principal(r.owner_principal_kind, r.owner_principal_id)) or nil
    local stored = (r.ncm_driver_id and r.location_kind == "storage" and r.machine_asset_id == nil)
        or (not r.ncm_driver_id and r.location_kind == "npc_storage")
    return { assetId = r.asset_id, owner = owner, stored = stored and true or false, family = r.family, tier = r.tier,
        designId = r.design_id, effect = tonumber(r.effect) or 1,   -- L298: fitment and upgrade checks on the NPC's car
        price = tonumber(r.price) or 0, name = ("%s %s"):format(r.display_manufacturer or "", r.code or "") }
end

local function reservedBy(assetId)
    return MySQL.single.await("SELECT holder_kind, holder_id FROM exchange_reservation WHERE asset_id = ?", { assetId })
end

local function postRow(r)
    if not r then return nil end
    return { postId = r.post_id, kind = r.kind, principal = EX.principal(r.principal_kind, r.principal_id), assetId = r.asset_id,
        family = r.want_family, tier = r.want_tier, cash = tonumber(r.cash) or 0, state = r.state, revision = tonumber(r.revision) or 1,
        note = r.note, createdAt = tonumber(r.created_at) or 0, expiresAt = tonumber(r.expires_at) or 0 }
end
local function bidRow(r)
    if not r then return nil end
    return { bidId = r.bid_id, postId = r.post_id, postRevision = tonumber(r.post_revision) or 0,
        principal = EX.principal(r.principal_kind, r.principal_id), cash = tonumber(r.cash) or 0, assetId = r.asset_id,
        state = r.state, createdAt = tonumber(r.created_at) or 0, expiresAt = tonumber(r.expires_at) or 0 }
end
function PaddockExchange.post(postId)
    return postRow(MySQL.single.await("SELECT * FROM exchange_post WHERE post_id = ? AND server_id = ?", { tostring(postId or ""), U.sid() }))
end
function PaddockExchange.bid(bidId)
    return bidRow(MySQL.single.await("SELECT * FROM exchange_bid WHERE bid_id = ? AND server_id = ?", { tostring(bidId or ""), U.sid() }))
end
function PaddockExchange.bidsOn(postId)
    local out = {}
    for _, r in ipairs(MySQL.query.await("SELECT * FROM exchange_bid WHERE post_id = ? AND state = 'open' ORDER BY created_at", { postId }) or {}) do
        out[#out + 1] = bidRow(r)
    end
    return out
end
local function openCount(tbl, key)
    local kind, id = EX.split(key)
    return tonumber(MySQL.scalar.await(("SELECT COUNT(*) FROM %s WHERE server_id = ? AND principal_kind = ? AND principal_id = ? AND state = 'open'"):format(tbl),
        { U.sid(), kind, id })) or 0
end

--- What a principal can pay, as the Paddock or the ledger holds it.
local function cashOf(key)
    local kind, id = EX.split(key)
    if kind == "driver" then return PaddockWallet.balance(id) end
    local w = PaddockStore.world
    local o = kind == "org" and w.orgs[id] or w.people[id]
    return o and (tonumber(o.cash) or 0) or 0
end
PaddockExchange.cashOf = cashOf

-- --------------------------------------------------------------------------------------------------------- posts

--- Post an offer or a want. `p` = { kind, assetId?, family?, tier?, cash, note? }. Returns postId or nil, reason.
function PaddockExchange.postFor(key, p, t)
    p = type(p) == "table" and p or {}
    local spec = { kind = p.kind, principal = key, assetId = p.assetId, family = p.family, tier = p.tier,
        cash = math.floor(tonumber(p.cash) or 0), note = p.note }
    local ok, why = EX.validatePost(spec)
    if not ok then return nil, why end
    if openCount("exchange_post", key) >= EX.MAX_OPEN_POSTS then return nil, "too_many_posts" end
    if spec.kind == "offer" then
        local part = PaddockExchange.part(spec.assetId)
        if not part or part.owner ~= key then return nil, "not_your_part" end
        if not part.stored then return nil, "part_not_in_storage" end
        if reservedBy(spec.assetId) then return nil, "part_already_promised" end
    end
    local kind, id = EX.split(key)
    local postId = ids.uuid4(rng)
    local tx = {
        { query = [[INSERT INTO exchange_post (post_id, server_id, kind, principal_kind, principal_id, asset_id, want_family, want_tier,
            cash, state, revision, note, created_at, expires_at) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?, 'open', 1, NULLIF(?, ''), ?, ?)]],
          values = { postId, U.sid(), spec.kind, kind, id, spec.assetId or "", spec.family or "", spec.tier or "", spec.cash, spec.note or "", t, t + EX.POST_TTL_SEC } },
    }
    if spec.kind == "offer" then
        tx[#tx + 1] = { query = "INSERT INTO exchange_reservation (asset_id, server_id, holder_kind, holder_id, created_at) VALUES (?, ?, 'post', ?, ?)",
            values = { spec.assetId, U.sid(), postId, t } }
    end
    local okT, err = PaddockMarkets.atomic(tx)
    if not okT then return nil, "refused: " .. tostring(err) end
    stats.posts = stats.posts + 1
    return postId
end

--- Bid on a post. `b` = { postId, revision, cash, assetId? }. Returns bidId or nil, reason.
function PaddockExchange.bidFor(key, b, t)
    b = type(b) == "table" and b or {}
    local post = PaddockExchange.post(b.postId)
    if not post then return nil, "no_such_post" end
    local asset
    if b.assetId and b.assetId ~= "" then
        asset = PaddockExchange.part(b.assetId)
        if not asset or asset.owner ~= key then return nil, "not_your_part" end
        if not asset.stored then return nil, "part_not_in_storage" end
        if reservedBy(b.assetId) then return nil, "part_already_promised" end
    end
    local spec = { principal = key, postRevision = tonumber(b.revision) or 0, cash = math.floor(tonumber(b.cash) or 0),
        assetId = asset and asset.assetId or nil, asset = asset }
    local ok, why = EX.validateBid(post, spec, t)
    if not ok then return nil, why end
    if openCount("exchange_bid", key) >= EX.MAX_OPEN_BIDS then return nil, "too_many_bids" end
    if #PaddockExchange.bidsOn(post.postId) >= EX.MAX_BIDS_PER_POST then return nil, "post_full" end
    -- a bid that could never settle is refused now, not at acceptance
    if post.kind == "offer" and cashOf(key) < spec.cash then return nil, "insufficient_funds" end
    local kind, id = EX.split(key)
    local bidId = ids.uuid4(rng)
    local tx = {
        { query = [[INSERT INTO exchange_bid (bid_id, server_id, post_id, post_revision, principal_kind, principal_id, cash, asset_id, state,
            created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''), 'open', ?, ?)]],
          values = { bidId, U.sid(), post.postId, post.revision, kind, id, spec.cash, spec.assetId or "", t,
              math.min(post.expiresAt, t + EX.BID_TTL_SEC) } },
    }
    if spec.assetId then
        tx[#tx + 1] = { query = "INSERT INTO exchange_reservation (asset_id, server_id, holder_kind, holder_id, created_at) VALUES (?, ?, 'bid', ?, ?)",
            values = { spec.assetId, U.sid(), bidId, t } }
    end
    local okT, err = PaddockMarkets.atomic(tx)
    if not okT then return nil, "refused: " .. tostring(err) end
    stats.bids = stats.bids + 1
    PaddockExchange.tell(post.principal, "A bid on your post", ("%s bid %s on your %s."):format(PaddockExchange.nameOf(key),
        "€$" .. spec.cash, post.kind == "offer" and "part" or "want"))
    return bidId
end

--- Withdraw an open post (and void its bids) or an open bid; their reservations are released.
function PaddockExchange.withdraw(key, what, id, t)
    local kind, pid = EX.split(key)
    if what == "post" then
        local tx = {
            { query = [[UPDATE exchange_post SET state = 'withdrawn', closed_at = ?, revision = revision + 1
                WHERE post_id = ? AND principal_kind = ? AND principal_id = ? AND state = 'open']], values = { t, id, kind, pid } },
            { query = [[UPDATE exchange_bid SET state = 'void', closed_at = ? WHERE post_id = ? AND state = 'open'
                AND EXISTS (SELECT 1 FROM exchange_post WHERE post_id = ? AND state = 'withdrawn')]], values = { t, id, id } },
        }
        local ok = PaddockMarkets.atomic(tx)
        PaddockExchange.sweep(t)
        return ok
    end
    local ok = MySQL.update.await([[UPDATE exchange_bid SET state = 'withdrawn', closed_at = ?
        WHERE bid_id = ? AND principal_kind = ? AND principal_id = ? AND state = 'open']], { t, id, kind, pid })
    PaddockExchange.sweep(t)
    return (tonumber(ok) or 0) > 0
end

--- Expire what has run out and release every reservation whose holder is no longer open. Idempotent; runs at boot.
function PaddockExchange.sweep(t)
    MySQL.update.await("UPDATE exchange_post SET state = 'expired', closed_at = ?, revision = revision + 1 WHERE server_id = ? AND state = 'open' AND expires_at <= ?", { t, U.sid(), t })
    MySQL.update.await("UPDATE exchange_bid SET state = 'expired', closed_at = ? WHERE server_id = ? AND state = 'open' AND expires_at <= ?", { t, U.sid(), t })
    MySQL.update.await([[UPDATE exchange_bid b JOIN exchange_post p ON p.post_id = b.post_id SET b.state = 'void', b.closed_at = ?
        WHERE b.server_id = ? AND b.state = 'open' AND p.state <> 'open']], { t, U.sid() })
    MySQL.update.await([[DELETE r FROM exchange_reservation r LEFT JOIN exchange_post p ON p.post_id = r.holder_id
        WHERE r.server_id = ? AND r.holder_kind = 'post' AND (p.post_id IS NULL OR p.state <> 'open')]], { U.sid() })
    MySQL.update.await([[DELETE r FROM exchange_reservation r LEFT JOIN exchange_bid b ON b.bid_id = r.holder_id
        WHERE r.server_id = ? AND r.holder_kind = 'bid' AND (b.bid_id IS NULL OR b.state <> 'open')]], { U.sid() })
end

-- --------------------------------------------------------------------------------------------------------- settle

--- The statements that settle `post` with `bid` (exposed for tools/npc-sql-gen.lua). Returns tx, settlementId, legs.
function PaddockExchange.settlementTx(post, bid, t)
    local legs = EX.legs(post, bid)
    local sid = ids.uuid4(rng)
    local GATE = "EXISTS (SELECT 1 FROM exchange_settlement WHERE settlement_id = ?)"
    local tx = {}
    -- 2. the parts, each only from where it is expected
    for _, a in ipairs(legs.assets) do
        local setSql, setV = ownerSet(a.to, t)
        local fromSql, fromV = ownerStored(a.from)
        tx[#tx + 1] = { query = ("UPDATE component_asset SET %s WHERE asset_id = ? AND server_id = ? AND %s"):format(setSql, fromSql),
            values = cat(setV, { a.assetId, U.sid() }, fromV) }
    end
    -- 3. the gate
    local conds, cv = {}, {}
    for _, a in ipairs(legs.assets) do
        local isSql, isV = ownerIs(a.to)
        conds[#conds + 1] = ("EXISTS (SELECT 1 FROM component_asset WHERE asset_id = ? AND %s)"):format(isSql)
        cv = cat(cv, { a.assetId }, isV)
    end
    local amount = legs.cash and legs.cash.amount or 0
    if amount > 0 then
        local kind, id = EX.split(legs.cash.from)
        if kind == "driver" then
            conds[#conds + 1] = "(SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id = ? AND server_id = ?) >= ?"
            cv = cat(cv, { id, U.sid(), amount })
        else
            conds[#conds + 1] = ("(SELECT cash FROM %s WHERE server_id = ? AND %s = ?) >= ?"):format(kind == "org" and "paddock_org" or "paddock_person",
                kind == "org" and "org_id" or "person_id")
            cv = cat(cv, { U.sid(), id, amount })
        end
    end
    conds[#conds + 1] = "EXISTS (SELECT 1 FROM exchange_post WHERE post_id = ? AND state = 'open' AND revision = ?)"
    conds[#conds + 1] = "EXISTS (SELECT 1 FROM exchange_bid WHERE bid_id = ? AND state = 'open' AND post_revision = ?)"
    cv = cat(cv, { post.postId, post.revision, bid.bidId, post.revision })
    local payer, payee = legs.cash and legs.cash.from or post.principal, legs.cash and legs.cash.to or bid.principal
    local pk, pi = EX.split(payer)
    local qk, qi = EX.split(payee)
    local detail = U.encode({ assets = legs.assets, cash = amount }) or "{}"
    tx[#tx + 1] = { query = ([[INSERT INTO exchange_settlement (settlement_id, server_id, post_id, bid_id, cash, payer_kind, payer_id, payee_kind,
        payee_id, detail_json, settled_at) SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? FROM DUAL WHERE %s]]):format(table.concat(conds, " AND ")),
        values = cat({ sid, U.sid(), post.postId, bid.bidId, amount, pk, pi, qk, qi, detail, t }, cv) }
    -- 4. a part moved without the gate goes back
    for _, a in ipairs(legs.assets) do
        local setSql, setV = ownerSet(a.from, t)
        local isSql, isV = ownerIs(a.to)
        tx[#tx + 1] = { query = ("UPDATE component_asset SET %s WHERE asset_id = ? AND %s AND NOT %s"):format(setSql, isSql, GATE),
            values = cat(setV, { a.assetId }, isV, { sid }) }
    end
    -- 5. money, behind the gate
    local function moneyStep(key, signed, what)
        local kind, id = EX.split(key)
        local idem = ("exchange:%s:%s"):format(sid, what)
        if kind == "driver" then
            tx[#tx + 1] = { query = ([[INSERT IGNORE INTO ledger (ncm_driver_id, server_id, kind, amount, currency, ref, note, idem_key)
                SELECT ?, ?, ?, ?, 'eddies', ?, 'Exchange', ? FROM DUAL WHERE %s]]):format(GATE),
                values = { id, U.sid(), signed < 0 and "exchange_buy" or "exchange_sale", signed, post.postId, idem, sid } }
        else
            local tbl, col = kind == "org" and "paddock_org" or "paddock_person", kind == "org" and "org_id" or "person_id"
            tx[#tx + 1] = { query = ("UPDATE %s SET cash = cash + ? WHERE server_id = ? AND %s = ? AND %s"):format(tbl, col, GATE),
                values = { signed, U.sid(), id, sid } }
            tx[#tx + 1] = { query = ([[INSERT IGNORE INTO npc_money (entry_id, server_id, principal_kind, principal_id, amount, kind, ref, idem_key, created_at)
                SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? FROM DUAL WHERE %s]]):format(GATE),
                values = { ids.uuid4(rng), U.sid(), kind, id, signed, signed < 0 and "exchange_buy" or "exchange_sale", post.postId, idem, t, sid } }
        end
    end
    if amount > 0 then
        moneyStep(legs.cash.from, -amount, "pay")
        moneyStep(legs.cash.to, amount, "paid")
    end
    -- the board, behind the gate
    tx[#tx + 1] = { query = ("UPDATE exchange_post SET state = 'filled', closed_at = ?, revision = revision + 1 WHERE post_id = ? AND %s"):format(GATE),
        values = { t, post.postId, sid } }
    tx[#tx + 1] = { query = ("UPDATE exchange_bid SET state = 'accepted', closed_at = ? WHERE bid_id = ? AND %s"):format(GATE), values = { t, bid.bidId, sid } }
    tx[#tx + 1] = { query = ("UPDATE exchange_bid SET state = 'void', closed_at = ? WHERE post_id = ? AND bid_id <> ? AND state = 'open' AND %s"):format(GATE),
        values = { t, post.postId, bid.bidId, sid } }
    tx[#tx + 1] = { query = ("DELETE FROM exchange_reservation WHERE holder_kind = 'post' AND holder_id = ? AND %s"):format(GATE), values = { post.postId, sid } }
    tx[#tx + 1] = { query = ([[DELETE r FROM exchange_reservation r JOIN exchange_bid b ON r.holder_kind = 'bid' AND r.holder_id = b.bid_id
        WHERE b.post_id = ? AND %s]]):format(GATE), values = { post.postId, sid } }
    -- 1. balance locks for every player whose money moves
    local drivers = {}
    for _, key in ipairs({ payer, payee }) do
        local kind, id = EX.split(key)
        if kind == "driver" and amount > 0 then drivers[#drivers + 1] = id end
    end
    return PaddockWallet.withBalanceLocks(tx, drivers), sid, legs
end

--- Settle `post` with `bid` (the poster accepted it). Returns true or nil, reason.
function PaddockExchange.settle(post, bid, t)
    if not post or not bid or bid.postId ~= post.postId then return nil, "no_such_bid" end
    -- the database must hold what the Paddock holds before SQL checks an NPC's cash
    PaddockStore.flush()
    -- KB-323: a fresh instruction slice before the settlement (the flush alone can spend most of one)
    if coroutine.isyieldable() then Wait(0) end
    local tx, sid, legs = PaddockExchange.settlementTx(post, bid, t)
    local ok, err = PaddockMarkets.atomic(tx)
    if coroutine.isyieldable() then Wait(0) end
    if not ok then stats.failed = stats.failed + 1 return nil, "refused: " .. tostring(err) end
    local landed = (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM exchange_settlement WHERE settlement_id = ?", { sid })) or 0) > 0
    if not landed then
        stats.failed = stats.failed + 1
        MySQL.update.await("UPDATE exchange_bid SET state = 'void', closed_at = ? WHERE bid_id = ? AND state = 'open'", { t, bid.bidId })
        PaddockExchange.sweep(t)
        return nil, "could_not_settle"
    end
    stats.settled = stats.settled + 1
    -- The Paddock's own copy of NPC money is READ BACK from what the transaction committed (KB-328): applying the
    -- increments in memory after the commit left memory richer than the database whenever the handler was cut off
    -- between the two (KB-323), and every later purchase by that NPC failed with SQL 1690.
    local w = PaddockStore.world
    if legs.cash and legs.cash.amount > 0 then
        for _, key in ipairs({ legs.cash.from, legs.cash.to }) do
            local kind, id = EX.split(key)
            local o = (kind == "org" and w.orgs[id]) or (kind == "person" and w.people[id]) or nil
            if o then
                local tbl, col = kind == "org" and "paddock_org" or "paddock_person", kind == "org" and "org_id" or "person_id"
                local okC, cash = pcall(MySQL.scalar.await, ("SELECT cash FROM %s WHERE server_id = ? AND %s = ?"):format(tbl, col), { U.sid(), id })
                if okC and tonumber(cash) then
                    o.cash = tonumber(cash)
                    if kind == "org" then PaddockStore.markOrg(id) else PaddockStore.markPerson(id) end
                end
            end
        end
    end
    -- an NPC that received a part it can use fits it
    for _, a in ipairs(legs.assets) do
        local kind, id = EX.split(a.to)
        if kind ~= "driver" then pcall(PaddockMarkets.fitOwned, kind, id, PaddockExchange.part(a.assetId)) end
    end
    log("SETTLED post %s with bid %s: %s -> %s, %d eddies, %d part(s)", post.postId, bid.bidId, tostring(legs.cash and legs.cash.from),
        tostring(legs.cash and legs.cash.to), legs.cash and legs.cash.amount or 0, #legs.assets)
    PaddockExchange.tell(bid.principal, "Trade done", "Your bid was accepted. The part has moved.")
    PaddockExchange.tell(post.principal, "Trade done", "Your post was filled. The part has moved.")
    return true
end

--- The poster accepts a bid.
function PaddockExchange.accept(key, postId, bidId, t)
    local post = PaddockExchange.post(postId)
    if not post or post.principal ~= key then return nil, "not_your_post" end
    local bid = PaddockExchange.bid(bidId)
    if not bid or bid.state ~= "open" then return nil, "no_such_bid" end
    return PaddockExchange.settle(post, bid, t)
end

-- --------------------------------------------------------------------------------------------------------- names

function PaddockExchange.nameOf(key)
    local kind, id = EX.split(key)
    local w = PaddockStore.world
    if kind == "org" then local o = w.orgs[id] return o and o.name or "A team" end
    if kind == "person" then local p = w.people[id] return p and p.display or "A racer" end
    local d = MySQL.scalar.await("SELECT display FROM driver_profile WHERE ncm_driver_id = ? AND server_id = ?", { id, U.sid() })
    return d or "A driver"
end

--- Tell a player (if it is one, and online) what happened on the board.
function PaddockExchange.tell(key, title, message)
    local kind, id = EX.split(key)
    if kind ~= "driver" then return end
    local pid = PaddockPlayers.pidOf(id)
    if pid then pcall(Open77.notifications.send, pid, { type = "info", title = "EXCHANGE · " .. title, message = message, icon = "NCM", durationMs = 7000 }) end
end

-- ------------------------------------------------------------------------------------------------- NPC traders

local function npcList()
    local w = PaddockStore.world
    local out = {}
    for _, oid in ipairs(w.orgOrder) do
        local o = w.orgs[oid]
        if o.lifecycle == "active" and not o.humanManagerDriverId and (tonumber(o.cash) or 0) > 2000 then out[#out + 1] = { key = EX.principal("org", oid), tier = o.tier, car = o.car, risk = 50 } end
    end
    for _, pid in ipairs(w.personOrder) do
        local p = w.people[pid]
        if p.role == "driver" and p.state == "active" and p.leagueId and not p.orgId and p.car and (tonumber(p.cash) or 0) > 500 then
            out[#out + 1] = { key = EX.principal("person", pid), tier = "street", car = p.car, risk = p.personality and p.personality.risk or 50 }
        end
    end
    return out
end

--- The cheapest list price of a family/tier, for an NPC's want.
local function listPrice(family, tier)
    return tonumber(MySQL.scalar.await("SELECT MIN(price) FROM component_design WHERE family = ? AND tier = ?", { family, tier })) or 0
end

local cursor = 0
--- One trading pass: NPCs post their surplus and their wants, settle the best bids on their posts, and bid on what
--- players post. Bounded per pass.
function PaddockExchange.trade(t)
    if not set("npcExchangeEnabled", true) then return end
    PaddockExchange.sweep(t)
    local y = U.yielder(3)
    local budget = set("npcExchangeActionsPerPass", 6)
    -- 1. NPC posts: surplus parts in storage, offered a little above what they would take
    local surplus = MySQL.query.await([[SELECT a.asset_id, a.owner_principal_kind, a.owner_principal_id, d.family, d.tier, d.price
        FROM component_asset a JOIN component_design d ON d.design_id = a.design_id
        LEFT JOIN exchange_reservation r ON r.asset_id = a.asset_id
        WHERE a.server_id = ? AND a.location_kind = 'npc_storage' AND r.asset_id IS NULL LIMIT 6]], { U.sid() }) or {}
    for _, r in ipairs(surplus) do
        if budget <= 0 then break end
        local key = EX.principal(r.owner_principal_kind, r.owner_principal_id)
        local postId = PaddockExchange.postFor(key, { kind = "offer", assetId = r.asset_id,
            cash = math.floor(NM.askFloor({ price = tonumber(r.price) }, 50) * 1.2) }, t)
        if postId then stats.npcPosts = stats.npcPosts + 1; budget = budget - 1 end
        y()
    end
    -- 2. NPC wants: a few NPCs without one post a want for their neediest area
    local npcs = npcList()
    for _ = 1, math.min(2, #npcs) do
        if budget <= 0 or #npcs == 0 then break end
        cursor = cursor % #npcs + 1
        local n = npcs[cursor]
        local kind, id = EX.split(n.key)
        local open = tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM exchange_post WHERE server_id = ? AND principal_kind = ? AND principal_id = ?
            AND state = 'open' AND kind = 'want']], { U.sid(), kind, id })) or 0
        if open == 0 then
            local area = NM.neediest(n.car)[1].area
            local family = (NM.AREA_FAMILIES[area] or {})[1]
            local tier = (n.tier == "street" or n.tier == "regional") and "street" or "sport"
            local price = family and listPrice(family, tier) or 0
            local max = math.floor(NM.reservation({ family = family, tier = tier, price = price }, n.car, n.tier, n.risk) * 0.9)
            if max > 0 and max <= cashOf(n.key) then
                if PaddockExchange.postFor(n.key, { kind = "want", family = family, tier = tier, cash = max }, t) then
                    stats.npcPosts = stats.npcPosts + 1; budget = budget - 1
                end
            end
        end
        y()
    end
    -- 3. NPC posts with bids: take the best one that clears the NPC's terms
    local mine = MySQL.query.await([[SELECT p.* FROM exchange_post p WHERE p.server_id = ? AND p.state = 'open' AND p.principal_kind <> 'driver'
        AND EXISTS (SELECT 1 FROM exchange_bid b WHERE b.post_id = p.post_id AND b.state = 'open') LIMIT 6]], { U.sid() }) or {}
    for _, r in ipairs(mine) do
        if budget <= 0 then break end
        local post = postRow(r)
        local best = EX.best(post, PaddockExchange.bidsOn(post.postId))
        if best then
            local fine
            if post.kind == "offer" then
                local part = PaddockExchange.part(post.assetId)
                fine = part and best.cash >= NM.askFloor(part, 50)
            else
                fine = best.cash <= post.cash and cashOf(post.principal) >= best.cash
            end
            if fine then PaddockExchange.settle(post, best, t); budget = budget - 1 end
        end
        y()
    end
    -- 4. players' posts: an NPC that values an offered part bids its asking price; one with a matching surplus part
    --    fills a player's want
    local theirs = MySQL.query.await([[SELECT p.* FROM exchange_post p WHERE p.server_id = ? AND p.state = 'open' AND p.principal_kind = 'driver'
        AND NOT EXISTS (SELECT 1 FROM exchange_bid b WHERE b.post_id = p.post_id AND b.state = 'open' AND b.principal_kind <> 'driver')
        ORDER BY p.created_at LIMIT 6]], { U.sid() }) or {}
    for _, r in ipairs(theirs) do
        if budget <= 0 then break end
        local post = postRow(r)
        if post.kind == "offer" then
            local part = PaddockExchange.part(post.assetId)
            if part then
                local buyer
                for _, n in ipairs(npcs) do
                    if NM.reservation(part, n.car, n.tier, n.risk) >= post.cash and cashOf(n.key) >= post.cash then buyer = n break end
                end
                if buyer and PaddockExchange.bidFor(buyer.key, { postId = post.postId, revision = post.revision, cash = post.cash }, t) then
                    stats.npcBids = stats.npcBids + 1; budget = budget - 1
                end
            end
        else
            local s = MySQL.single.await([[SELECT a.asset_id, a.owner_principal_kind, a.owner_principal_id, d.price FROM component_asset a
                JOIN component_design d ON d.design_id = a.design_id LEFT JOIN exchange_reservation r ON r.asset_id = a.asset_id
                WHERE a.server_id = ? AND a.location_kind = 'npc_storage' AND d.family = ? AND d.tier = ? AND r.asset_id IS NULL LIMIT 1]],
                { U.sid(), post.family, post.tier })
            if s then
                local ask = math.max(NM.askFloor({ price = tonumber(s.price) }, 50), math.floor(post.cash * 0.9))
                if ask <= post.cash and PaddockExchange.bidFor(EX.principal(s.owner_principal_kind, s.owner_principal_id),
                    { postId = post.postId, revision = post.revision, cash = ask, assetId = s.asset_id }, t) then
                    stats.npcBids = stats.npcBids + 1; budget = budget - 1
                end
            end
        end
        y()
    end
    -- 5. L298 (audit L297: 225 posts, zero settlements -- NPC offers and NPC wants never met, step 4 served players
    --    only). NPC to NPC: a racer whose car a posted part fits and improves bids the ask; a stored part that matches
    --    an NPC's want is offered to it. Step 3 settles both on the next pass.
    local npcPosts = MySQL.query.await([[SELECT p.* FROM exchange_post p WHERE p.server_id = ? AND p.state = 'open' AND p.principal_kind <> 'driver'
        AND NOT EXISTS (SELECT 1 FROM exchange_bid b WHERE b.post_id = p.post_id AND b.state = 'open')
        ORDER BY p.created_at LIMIT 6]], { U.sid() }) or {}
    for _, r in ipairs(npcPosts) do
        if budget <= 0 then break end
        local post = postRow(r)
        if post.kind == "offer" then
            local part = PaddockExchange.part(post.assetId)
            if part and PaddockMarkets and PaddockMarkets.wouldFit then
                for _, n in ipairs(npcs) do
                    local kind, id = EX.split(n.key)
                    if n.key ~= post.principal and cashOf(n.key) >= post.cash and PaddockMarkets.wouldFit(kind, id, part) then
                        if PaddockExchange.bidFor(n.key, { postId = post.postId, revision = post.revision, cash = post.cash }, t) then
                            stats.npcBids = stats.npcBids + 1; budget = budget - 1
                        end
                        break
                    end
                end
            end
        else
            local sp = MySQL.single.await([[SELECT a.asset_id, a.owner_principal_kind, a.owner_principal_id, d.price FROM component_asset a
                JOIN component_design d ON d.design_id = a.design_id LEFT JOIN exchange_reservation r ON r.asset_id = a.asset_id
                WHERE a.server_id = ? AND a.location_kind = 'npc_storage' AND d.family = ? AND d.tier = ? AND r.asset_id IS NULL
                  AND NOT (a.owner_principal_kind = ? AND a.owner_principal_id = ?) LIMIT 1]],
                { U.sid(), post.family, post.tier, EX.split(post.principal) })
            if sp then
                local ask = math.max(NM.askFloor({ price = tonumber(sp.price) }, 50), math.floor(post.cash * 0.9))
                if ask <= post.cash and PaddockExchange.bidFor(EX.principal(sp.owner_principal_kind, sp.owner_principal_id),
                    { postId = post.postId, revision = post.revision, cash = ask, assetId = sp.asset_id }, t) then
                    stats.npcBids = stats.npcBids + 1; budget = budget - 1
                end
            end
        end
        y()
    end
    -- 6. L298 SCRAP: a part that has sat unsold in an NPC's storage for `npcScrapAfterDays` leaves service -- scrapped
    --    for a fraction of its list price (the sink beside the Exchange: parts circulate, they do not pile up)
    local old = MySQL.query.await([[SELECT a.asset_id, a.owner_principal_kind, a.owner_principal_id, d.price FROM component_asset a
        JOIN component_design d ON d.design_id = a.design_id LEFT JOIN exchange_reservation r ON r.asset_id = a.asset_id
        WHERE a.server_id = ? AND a.location_kind = 'npc_storage' AND r.asset_id IS NULL AND COALESCE(a.acquired_at, a.created_at) < ?
        LIMIT 4]], { U.sid(), t - set("npcScrapAfterDays", 3) * 86400 }) or {}
    for _, r in ipairs(old) do
        local value = math.floor((tonumber(r.price) or 0) * set("npcScrapShare", 0.15))
        local tx = { { query = [[UPDATE component_asset SET location_kind = 'scrapped', lifecycle = 'scrapped' WHERE asset_id = ?
            AND location_kind = 'npc_storage']], values = { r.asset_id } },
            { query = [[INSERT IGNORE INTO component_asset_transfer (transfer_id, idem_key, server_id, asset_id, kind, amount, occurred_at,
                from_principal, reason) VALUES (?, ?, ?, ?, 'scrap', ?, ?, ?, 'scrapped_unsold')]],
              values = { ids.uuid4(rng), "npc_scrap:" .. U.sid() .. ":" .. r.asset_id, U.sid(), r.asset_id, value, t,
                r.owner_principal_kind .. ":" .. r.owner_principal_id } } }
        if PaddockMarkets and PaddockMarkets.moneyStatements then
            for _, st in ipairs(PaddockMarkets.moneyStatements(r.owner_principal_kind, r.owner_principal_id, value, "scrap", r.asset_id, t,
                "scrapped_unsold", nil)) do tx[#tx + 1] = st end
        end
        local okS = PaddockMarkets and PaddockMarkets.atomic(tx)
        if okS then
            local w = PaddockStore.world
            local holder = r.owner_principal_kind == "org" and w.orgs[r.owner_principal_id] or w.people[r.owner_principal_id]
            if holder then holder.cash = (tonumber(holder.cash) or 0) + value end
            log("scrapped %s's unsold part %s for %d", r.owner_principal_id, r.asset_id:sub(1, 8), value)
        end
    end
end

function PaddockExchange.start()
    CreateThread(function()
        Wait(20000)
        pcall(PaddockExchange.sweep, U.now())       -- expiry recovery after a restart
        while true do
            if PaddockSettings.get("paddockEnabled", true) and PaddockWorld.ready then
                local ok, err = pcall(PaddockExchange.trade, U.now())
                if not ok then log("trade FAILED: %s", tostring(err)) end
            end
            Wait(set("npcExchangeEverySec", 180) * 1000)
        end
    end)
end
