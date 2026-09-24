-- ncm_league schema 030: Driver Card presentation selection (L130).
--
-- Definition, entitlement and selection are separate. This table stores only what the driver chose to show;
-- accomplishments remain the earned truth and the public projection is rebuilt server-side after validating
-- the selection against those facts. Fingerprint values are deliberately absent: V1 calculation is gated.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 30,
    name = "driver_presentation",
    statements = {
        [[CREATE TABLE IF NOT EXISTS driver_presentation (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            banner_id VARCHAR(64) NOT NULL DEFAULT 'ncm_default',
            displayed_badges_json JSON NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (ncm_driver_id, server_id),
            CONSTRAINT fk_driver_presentation_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
