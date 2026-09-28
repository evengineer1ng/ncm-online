-- Schema 038: append-only component service history. Condition and severity remain derived (L120/L178).
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 38,
    name = "component_wear",
    statements = {
        [[CREATE TABLE IF NOT EXISTS component_service (
            service_id CHAR(36) NOT NULL,
            idem_key VARCHAR(190) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            component_asset_id CHAR(36) NOT NULL,
            condition_id VARCHAR(96) NOT NULL,
            at_exposure_m BIGINT UNSIGNED NOT NULL,
            by_driver_id CHAR(36) NOT NULL,
            provider_kind VARCHAR(32) NOT NULL,
            workmanship_json LONGTEXT NOT NULL,
            relief_m BIGINT UNSIGNED NOT NULL,
            amount INT UNSIGNED NOT NULL DEFAULT 0,
            occurred_at BIGINT NOT NULL,
            PRIMARY KEY (service_id),
            UNIQUE KEY ux_component_service_idem (idem_key),
            KEY ix_component_service_asset (component_asset_id, condition_id, occurred_at),
            CHECK (JSON_VALID(workmanship_json)),
            CONSTRAINT fk_component_service_asset FOREIGN KEY (component_asset_id)
                REFERENCES component_asset (asset_id),
            CONSTRAINT fk_component_service_driver FOREIGN KEY (by_driver_id)
                REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
