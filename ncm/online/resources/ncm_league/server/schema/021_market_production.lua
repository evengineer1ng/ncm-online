-- Schema 021: primary-market production runs.
--
-- One row per (server, market, model, tick index). The row IS the claim: the host inserts it before it mints
-- anything, and a second attempt at the same tick collides on the primary key and mints nothing. That is the
-- whole of the "restarting NCM is not a vehicle-printing exploit" guarantee (packet section 8) -- there is no
-- in-memory schedule to lose, because `economy.production.tickIndex` derives the tick from the clock.
--
-- The claim is verified by reading `claim_nonce` back rather than by trusting an affected-rows count:
-- a driver that returns an insert id, a zero, or nothing at all for `INSERT IGNORE` would otherwise
-- decide whether NCM manufactures vehicles. The primary key picks exactly one winner; the nonce is how
-- the winner finds out it won.
--
-- `minted` is written after the fact and is evidence, not control: a tick that legitimately produced nothing
-- because the shelf was full records 0 and is still, correctly, a tick that happened.
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 21,
    name = "market_production",
    statements = {
        [[CREATE TABLE IF NOT EXISTS market_production_run (
            server_id VARCHAR(96) NOT NULL,
            market_id VARCHAR(96) NOT NULL,
            vehicle_key VARCHAR(96) NOT NULL,
            tick_index BIGINT NOT NULL,
            tick_at BIGINT NOT NULL,
            claimed_at BIGINT NOT NULL,
            claim_nonce CHAR(36) NOT NULL,
            available_before INT NOT NULL DEFAULT 0,
            ceiling INT NOT NULL DEFAULT 0,
            batch INT NOT NULL DEFAULT 0,
            minted INT NOT NULL DEFAULT 0,
            PRIMARY KEY (server_id, market_id, vehicle_key, tick_index),
            KEY ix_production_recent (server_id, market_id, vehicle_key, tick_index DESC)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
