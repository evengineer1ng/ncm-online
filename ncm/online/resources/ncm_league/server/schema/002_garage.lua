-- ncm_league schema 002: issued vehicles log (M2.2). Owned garages (vehicle_asset) and per-session
-- vehicle_assignment (L28) arrive with sessions in M3; this is the provisioning ledger for issued cars.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 2,
    name = "garage",
    statements = {
        [[CREATE TABLE IF NOT EXISTS issued_vehicle (
            issue_id CHAR(36) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            model ENUM('issued','loaner','owned','byo') NOT NULL DEFAULT 'issued',
            class VARCHAR(32) NOT NULL,
            record VARCHAR(256) NOT NULL,
            spawned_record VARCHAR(256) NULL,
            vehicle_id BIGINT UNSIGNED NULL,
            cost INT NOT NULL DEFAULT 0,
            issued_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            returned_at DATETIME NULL,
            return_reason VARCHAR(64) NULL,
            PRIMARY KEY (issue_id),
            KEY ix_issued_driver (ncm_driver_id, server_id, returned_at),
            CONSTRAINT fk_issued_driver FOREIGN KEY (ncm_driver_id) REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
