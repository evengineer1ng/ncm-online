-- Schema 070: the Machine Passport (L336). One host-independent description per Machine (machine.passport), and for each
-- host the body that expresses it -- sticky: it changes only by an explicit revision, kept in the history table.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 70,
    name = "machine_passport",
    statements = {
        [[CREATE TABLE IF NOT EXISTS machine_passport (
            asset_id CHAR(36) NOT NULL,
            passport_json MEDIUMTEXT NOT NULL,
            version VARCHAR(16) NOT NULL,
            updated_at BIGINT NOT NULL,
            PRIMARY KEY (asset_id),
            CONSTRAINT fk_machine_passport_asset FOREIGN KEY (asset_id) REFERENCES vehicle_asset(asset_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS machine_expression (
            asset_id CHAR(36) NOT NULL,
            host VARCHAR(32) NOT NULL,
            expression_id VARCHAR(128) NOT NULL,
            variant VARCHAR(128) NULL,
            correspondence DOUBLE NOT NULL,
            tier VARCHAR(16) NOT NULL,
            reason VARCHAR(512) NOT NULL,
            revision INT NOT NULL,
            established_at BIGINT NOT NULL,
            PRIMARY KEY (asset_id, host),
            CONSTRAINT fk_machine_expression_asset FOREIGN KEY (asset_id) REFERENCES vehicle_asset(asset_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS machine_expression_history (
            id BIGINT NOT NULL AUTO_INCREMENT,
            asset_id CHAR(36) NOT NULL,
            host VARCHAR(32) NOT NULL,
            from_id VARCHAR(128) NULL,
            to_id VARCHAR(128) NOT NULL,
            to_score DOUBLE NOT NULL,
            why VARCHAR(512) NOT NULL,
            revision INT NOT NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (id),
            KEY ix_meh_asset (asset_id, host)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
