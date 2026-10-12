-- ncm-core module: economy.exchange_posts
-- The posted Exchange (L249 step 5): pure rules for posts, bids and what a settlement moves. The Paddock host
-- (`ncm_paddock/server/exchange.lua`) persists them and settles in one guarded transaction.
--
--   offer  "my stored part X, for N" -- a bid is cash (and may add one of the bidder's parts as a sweetener)
--   want   "a part of family F and tier T, up to N" -- a bid is one of the bidder's parts, at a cash price <= N
--
-- Principals are "driver:<ncm_driver_id>", "org:<org_id>", "person:<person_id>". Nobody bids on their own post. A bid
-- names the post revision it was made against; a post whose terms moved refuses it (Billie's line rule, L224).
local Core = NcmCore

Core.define("economy.exchange_posts", function(C)
    local M = { version = "0.1.0" }
    M.POST_TTL_SEC = 24 * 3600
    M.BID_TTL_SEC = 2 * 3600
    M.MAX_OPEN_POSTS = 5            -- per principal
    M.MAX_OPEN_BIDS = 8             -- per principal
    M.MAX_BIDS_PER_POST = 20
    M.MAX_CASH = 10000000
    M.TIERS = { street = true, sport = true, premium = true }
    -- 2026-10-12 (owner: NPC resales "should never have been able to sell back to manufacturer"): a post may offer a
    -- whole CAR as well as a part. A car post lives longer (a car is a bigger decision) and is bid on in cash.
    M.ASSET_KINDS = { part = true, vehicle = true }
    M.VEHICLE_TTL_SEC = 72 * 3600

    local function families()
        local ok, Cat = pcall(C.get, "parts.catalogue")
        local out = {}
        for _, f in ipairs(ok and Cat.FAMILIES or {}) do out[f] = true end
        return out
    end

    function M.principal(kind, id) return tostring(kind) .. ":" .. tostring(id) end
    function M.split(key)
        local kind, id = tostring(key or ""):match("^(%a+):(.+)$")
        return kind, id
    end
    local KINDS = { driver = true, org = true, person = true }

    local function cashOk(v, allowZero)
        v = tonumber(v)
        if not v or v ~= math.floor(v) then return false end
        if allowZero then return v >= 0 and v <= M.MAX_CASH end
        return v >= 1 and v <= M.MAX_CASH
    end

    --- A new post, checked. `p` = { kind, principal, assetId?, family?, tier?, cash, note? }. Returns ok or nil, reason.
    function M.validatePost(p)
        if type(p) ~= "table" then return nil, "bad_post" end
        local kind = M.split(p.principal)
        if not KINDS[kind or ""] then return nil, "bad_principal" end
        if not cashOk(p.cash) then return nil, "bad_cash" end
        if p.assetKind ~= nil and not M.ASSET_KINDS[p.assetKind] then return nil, "bad_asset_kind" end
        if p.assetKind == "vehicle" and p.kind ~= "offer" then return nil, "cars_are_offered_not_wanted" end
        if p.kind == "offer" then
            if type(p.assetId) ~= "string" or p.assetId == "" then return nil, "offer_needs_a_part" end
        elseif p.kind == "want" then
            if not families()[p.family or ""] then return nil, "unknown_family" end
            if not M.TIERS[p.tier or ""] then return nil, "unknown_tier" end
        else
            return nil, "bad_kind"
        end
        if p.note ~= nil and (type(p.note) ~= "string" or #p.note > 160) then return nil, "bad_note" end
        return true
    end

    --- A bid against `post`, checked. `post` = { kind, principal, state, revision, expiresAt, cash, family?, tier? };
    --- `b` = { principal, postRevision, cash, assetId?, asset? = { family, tier } (the facts of the part offered) }.
    function M.validateBid(post, b, now)
        if type(post) ~= "table" or type(b) ~= "table" then return nil, "bad_bid" end
        if post.state ~= "open" then return nil, "post_closed" end
        if (tonumber(post.expiresAt) or 0) <= (tonumber(now) or 0) then return nil, "post_expired" end
        if b.principal == post.principal then return nil, "own_post" end
        if not KINDS[(M.split(b.principal)) or ""] then return nil, "bad_principal" end
        if tonumber(b.postRevision) ~= tonumber(post.revision) then return nil, "post_changed" end
        if post.kind == "offer" then
            if not cashOk(b.cash, true) then return nil, "bad_cash" end
            if (tonumber(b.cash) or 0) == 0 and not b.assetId then return nil, "empty_bid" end
        else
            if not b.assetId then return nil, "want_needs_a_part" end
            if not cashOk(b.cash, true) then return nil, "bad_cash" end
            if (tonumber(b.cash) or 0) > (tonumber(post.cash) or 0) then return nil, "over_their_price" end
            local a = b.asset or {}
            if a.family ~= post.family or a.tier ~= post.tier then return nil, "not_what_they_want" end
        end
        return true
    end

    --- What settling `post` with `bid` moves: { assets = { { assetId, from, to } }, cash = { from, to, amount } }.
    function M.legs(post, bid)
        local out = { assets = {} }
        if post.kind == "offer" then
            out.assets[#out.assets + 1] = { assetId = post.assetId, from = post.principal, to = bid.principal, kind = post.assetKind or "part" }
            if bid.assetId then out.assets[#out.assets + 1] = { assetId = bid.assetId, from = bid.principal, to = post.principal, kind = "part" } end
            out.cash = { from = bid.principal, to = post.principal, amount = math.floor(tonumber(bid.cash) or 0) }
        else
            out.assets[#out.assets + 1] = { assetId = bid.assetId, from = bid.principal, to = post.principal, kind = "part" }
            out.cash = { from = post.principal, to = bid.principal, amount = math.floor(tonumber(bid.cash) or 0) }
        end
        return out
    end

    --- What a used car asks: its model's new price, less a used discount (22 %), less up to 35 % for distance (all of it
    --- by 150,000 km), less up to 60 % for damage (`severity` 0..1, the weighted Machine Index measure).
    function M.usedAsk(newPrice, odometerM, severity)
        local km = math.max(0, (tonumber(odometerM) or 0) / 1000)
        local s = math.max(0, math.min(1, tonumber(severity) or 0))
        return math.max(1, math.floor((tonumber(newPrice) or 0) * 0.78 * (1 - math.min(0.35, km / 150000 * 0.35)) * (1 - 0.6 * s)))
    end

    --- A stale post comes down: 8 % less for every 12 h it has stood unfilled, never below half its first ask.
    function M.markdown(firstAsk, ageS)
        local steps = math.max(0, math.floor((tonumber(ageS) or 0) / (12 * 3600)))
        return math.max(1, math.floor((tonumber(firstAsk) or 0) * math.max(0.5, 0.92 ^ steps)))
    end

    --- Would an NPC bid on this car, and with what? Only for a car better than the one it drives (higher prestige), only
    --- when the ask is within 60 % of its cash; it opens at 92 % of the ask. Returns the bid or nil.
    function M.npcCarBid(ask, offeredPrestige, ownPrestige, cash)
        ask, cash = tonumber(ask) or 0, tonumber(cash) or 0
        if ask <= 0 or (tonumber(offeredPrestige) or 0) <= (tonumber(ownPrestige) or 0) then return nil end
        if ask > cash * 0.6 then return nil end
        return math.max(1, math.floor(ask * 0.92))
    end

    --- The best open bid on a post for its poster: for an offer, the most cash (a sweetener part counts at
    --- `assetValue(bid)`); for a want, the least cash. Ties to the earliest. `assetValue` may be nil.
    function M.best(post, bids, assetValue)
        local best, bestScore
        for _, b in ipairs(bids or {}) do
            if b.state == "open" then
                local score
                if post.kind == "offer" then
                    score = (tonumber(b.cash) or 0) + ((b.assetId and assetValue) and (assetValue(b) or 0) or 0)
                else
                    score = -(tonumber(b.cash) or 0)
                end
                if not best or score > bestScore or (score == bestScore and (tonumber(b.createdAt) or 0) < (tonumber(best.createdAt) or 0)) then
                    best, bestScore = b, score
                end
            end
        end
        return best, bestScore
    end

    return M
end)
