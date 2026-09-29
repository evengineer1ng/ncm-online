-- Schema 050: calibration, manager treasuries and manager offers (doc 44 §7, §10).
--
-- `paddock_calibration`: human medians per (route, NPC tier, condition bucket), recomputed hourly from 043's
-- stamps; the sim uses a bucket only once it clears its minimums, otherwise the declared baseline.
-- `paddock_treasury`: APPEND-ONLY money of HUMAN-managed orgs (deposits, wages, purse, sponsors, development,
-- capped taxed withdrawals). NPC orgs keep `paddock_org.cash`; a human's org gets an auditable book because real
-- eddies cross its boundary. The ledger cannot hold it: `ledger.ncm_driver_id` is NOT NULL.
-- `paddock_manager`: per-human manager state (cooldown after a fold, seasons managed, record).
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 50,
    name = "paddock_economy",
    statements = {
        [[CREATE TABLE IF NOT EXISTS paddock_calibration (
            server_id VARCHAR(96) NOT NULL,
            route_id VARCHAR(160) NOT NULL,
            tier VARCHAR(16) NOT NULL,
            cond_bucket VARCHAR(16) NOT NULL,
            n INT NOT NULL,
            drivers INT NOT NULL,
            median_ms INT NULL,
            p25_ms INT NULL,
            computed_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, route_id, tier, cond_bucket)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_treasury (
            entry_id BIGINT NOT NULL AUTO_INCREMENT,
            server_id VARCHAR(96) NOT NULL,
            org_id VARCHAR(16) NOT NULL,
            kind VARCHAR(32) NOT NULL,
            amount INT NOT NULL,
            idem_key VARCHAR(190) NOT NULL,
            ref VARCHAR(160) NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (entry_id),
            UNIQUE KEY ux_paddock_treasury_idem (idem_key),
            KEY ix_paddock_treasury_org (server_id, org_id, at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_manager_offer (
            offer_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            org_id VARCHAR(16) NOT NULL,
            from_person_id VARCHAR(16) NOT NULL,
            state ENUM('open','accepted','declined','expired','withdrawn') NOT NULL DEFAULT 'open',
            created_at BIGINT NOT NULL,
            expires_at BIGINT NOT NULL,
            PRIMARY KEY (offer_id),
            KEY ix_paddock_offer_driver (server_id, ncm_driver_id, state)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_manager (
            server_id VARCHAR(96) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            cooldown_until_season INT NULL,
            seasons_managed INT NOT NULL DEFAULT 0,
            record DECIMAL(5,3) NOT NULL DEFAULT 0,
            PRIMARY KEY (server_id, ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
