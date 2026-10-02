-- Schema 056: the posted Exchange (L249 step 5; the "second product" L194 named; IDEA-142/174).
--
-- L194's Exchange is a live two-party trade. This is the board beside it: anyone -- a player, a Paddock team, an
-- independent racer -- POSTS what they have (an `offer`: one of their stored parts, at an asking price) or what they
-- want (a `want`: a family and tier, up to a price), and anyone else BIDS against a post (cash for an offer, a part
-- for a want). The poster accepts one bid; the trade settles in one guarded transaction (ncm_paddock/server/exchange.lua).
--
--   exchange_post         the board. `revision` moves whenever the post changes, and a bid records the revision it
--                         was made against, so a bid on terms that have since changed is refused (Billie's line rule).
--   exchange_bid          offers against a post.
--   exchange_reservation  a part promised in an open post or bid cannot be promised again or settle twice; released
--                         when the post/bid closes, and swept at boot (expiry recovery -- the gap L194 named).
--   exchange_settlement   the gate: one row per settled trade, written inside the settlement transaction only when every
--                         part has landed with its new owner and the payer can pay; every money step is conditional on it.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 56,
    name = "exchange_posts",
    statements = {
        [[CREATE TABLE IF NOT EXISTS exchange_post (
            post_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            kind ENUM('offer','want') NOT NULL,
            principal_kind VARCHAR(16) NOT NULL,
            principal_id VARCHAR(64) NOT NULL,
            asset_id CHAR(36) NULL,
            want_family VARCHAR(48) NULL,
            want_tier VARCHAR(32) NULL,
            cash BIGINT NOT NULL,
            state ENUM('open','filled','withdrawn','expired') NOT NULL DEFAULT 'open',
            revision INT NOT NULL DEFAULT 1,
            note VARCHAR(160) NULL,
            created_at BIGINT NOT NULL,
            expires_at BIGINT NOT NULL,
            closed_at BIGINT NULL,
            PRIMARY KEY (post_id),
            KEY ix_exchange_post_open (server_id, state, kind, created_at),
            KEY ix_exchange_post_principal (server_id, principal_kind, principal_id, state)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS exchange_bid (
            bid_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            post_id CHAR(36) NOT NULL,
            post_revision INT NOT NULL,
            principal_kind VARCHAR(16) NOT NULL,
            principal_id VARCHAR(64) NOT NULL,
            cash BIGINT NOT NULL,
            asset_id CHAR(36) NULL,
            state ENUM('open','accepted','declined','withdrawn','expired','void') NOT NULL DEFAULT 'open',
            created_at BIGINT NOT NULL,
            expires_at BIGINT NOT NULL,
            closed_at BIGINT NULL,
            PRIMARY KEY (bid_id),
            KEY ix_exchange_bid_post (post_id, state),
            KEY ix_exchange_bid_principal (server_id, principal_kind, principal_id, state)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS exchange_reservation (
            asset_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            holder_kind ENUM('post','bid') NOT NULL,
            holder_id CHAR(36) NOT NULL,
            created_at BIGINT NOT NULL,
            PRIMARY KEY (asset_id),
            KEY ix_exchange_reservation_holder (holder_kind, holder_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS exchange_settlement (
            settlement_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            post_id CHAR(36) NOT NULL,
            bid_id CHAR(36) NOT NULL,
            cash BIGINT NOT NULL,
            payer_kind VARCHAR(16) NOT NULL,
            payer_id VARCHAR(64) NOT NULL,
            payee_kind VARCHAR(16) NOT NULL,
            payee_id VARCHAR(64) NOT NULL,
            detail_json TEXT NOT NULL,
            settled_at BIGINT NOT NULL,
            PRIMARY KEY (settlement_id),
            UNIQUE KEY ux_exchange_settlement_post (post_id),
            KEY ix_exchange_settlement_time (server_id, settled_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
