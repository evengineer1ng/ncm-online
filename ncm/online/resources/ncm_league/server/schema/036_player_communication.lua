-- Schema 036: durable player-message exposure. This stores pacing, not game state and not message copy.
NcmSchema = NcmSchema or {}
NcmSchema[#NcmSchema + 1] = {
    version = 36,
    name = "player_communication",
    statements = {
        [[CREATE TABLE IF NOT EXISTS player_message_exposure (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            message_key VARCHAR(160) NOT NULL,
            shown_count INT NOT NULL DEFAULT 0,
            last_shown_at BIGINT NULL,
            acknowledged_at BIGINT NULL,
            PRIMARY KEY (ncm_driver_id, server_id, message_key),
            CONSTRAINT fk_message_exposure_driver FOREIGN KEY (ncm_driver_id)
                REFERENCES ncm_driver (ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
