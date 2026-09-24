-- Schema 017: first market-scoped supply, transferable title/history and idempotent money.
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 17,
    name = "market_foundation",
    statements = {
        [[ALTER TABLE ledger
            ADD COLUMN idem_key VARCHAR(190) NULL,
            ADD COLUMN market_id VARCHAR(96) NULL,
            ADD COLUMN asset_id CHAR(36) NULL,
            ADD UNIQUE KEY ux_ledger_idem (idem_key)]],

        [[ALTER TABLE vehicle_asset DROP FOREIGN KEY fk_vehicle_asset_driver]],
        [[ALTER TABLE vehicle_asset
            MODIFY ncm_driver_id CHAR(36) NULL,
            MODIFY acquired_via ENUM('grant','progression','prize','purchase','seed') NULL,
            ADD COLUMN allocation_id VARCHAR(96) NULL,
            ADD COLUMN allocation_slot INT UNSIGNED NULL,
            ADD COLUMN factory_json LONGTEXT NULL,
            ADD UNIQUE KEY ux_vehicle_asset_allocation_slot (server_id, allocation_id, allocation_slot),
            ADD CONSTRAINT fk_vehicle_asset_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver(ncm_driver_id),
            ADD CHECK (JSON_VALID(factory_json) OR factory_json IS NULL)]],

        [[CREATE TABLE IF NOT EXISTS market (
            market_id VARCHAR(96) NOT NULL,
            display_name VARCHAR(96) NOT NULL,
            kind VARCHAR(32) NOT NULL,
            universally_known TINYINT(1) NOT NULL DEFAULT 0,
            policy_json LONGTEXT NULL,
            PRIMARY KEY (market_id),
            CHECK (JSON_VALID(policy_json) OR policy_json IS NULL)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS market_inventory (
            market_id VARCHAR(96) NOT NULL,
            asset_id CHAR(36) NOT NULL,
            price INT UNSIGNED NOT NULL,
            state ENUM('available','sold','withdrawn') NOT NULL DEFAULT 'available',
            listed_at BIGINT NOT NULL,
            sold_at BIGINT NULL,
            sold_to_driver_id CHAR(36) NULL,
            PRIMARY KEY (market_id, asset_id),
            KEY ix_market_inventory_state (market_id, state, listed_at),
            CONSTRAINT fk_market_inventory_market FOREIGN KEY (market_id) REFERENCES market(market_id),
            CONSTRAINT fk_market_inventory_asset FOREIGN KEY (asset_id) REFERENCES vehicle_asset(asset_id),
            CHECK (price >= 0)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS player_market_knowledge (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            market_id VARCHAR(96) NOT NULL,
            first_known_at BIGINT NOT NULL,
            source_kind VARCHAR(48) NOT NULL,
            source_ref VARCHAR(160) NULL,
            access_state VARCHAR(32) NULL,
            PRIMARY KEY (ncm_driver_id, server_id, market_id),
            CONSTRAINT fk_market_knowledge_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver(ncm_driver_id),
            CONSTRAINT fk_market_knowledge_market FOREIGN KEY (market_id) REFERENCES market(market_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS vehicle_asset_transfer (
            transfer_id CHAR(36) NOT NULL,
            idem_key VARCHAR(190) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            asset_id CHAR(36) NOT NULL,
            from_driver_id CHAR(36) NULL,
            to_driver_id CHAR(36) NULL,
            kind VARCHAR(32) NOT NULL,
            market_id VARCHAR(96) NULL,
            amount INT NULL,
            occurred_at BIGINT NOT NULL,
            PRIMARY KEY (transfer_id),
            UNIQUE KEY ux_vehicle_transfer_idem (idem_key),
            KEY ix_vehicle_transfer_asset (asset_id, occurred_at),
            KEY ix_vehicle_transfer_to (server_id, to_driver_id, occurred_at),
            CONSTRAINT fk_vehicle_transfer_asset FOREIGN KEY (asset_id) REFERENCES vehicle_asset(asset_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
