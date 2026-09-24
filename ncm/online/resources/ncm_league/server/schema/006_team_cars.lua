-- ncm_league schema 006: team cars, persisted messages, onboarding metadata (M7-lite; P29, P30, L28).
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 6,
    name = "team_cars",
    statements = {
        -- One row per team car; seat n drives car n. vehicle_def is the TweakDB record, livery the appearance key.
        [[CREATE TABLE IF NOT EXISTS team_car (
            server_id VARCHAR(96) NOT NULL,
            team_id VARCHAR(64) NOT NULL,
            car_index TINYINT UNSIGNED NOT NULL,
            vehicle_def VARCHAR(96) NOT NULL,
            livery VARCHAR(64) NULL,
            number SMALLINT UNSIGNED NOT NULL,
            PRIMARY KEY (server_id, team_id, car_index)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- NCM Messages (P30): the seat offer is the first kind. Delivery stays toast+chat until the panel (M7.5).
        [[CREATE TABLE IF NOT EXISTS message (
            message_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            to_driver_id CHAR(36) NOT NULL,
            from_kind ENUM('team','system','race_control') NOT NULL,
            from_id VARCHAR(64) NULL,
            kind VARCHAR(32) NOT NULL,
            subject VARCHAR(120) NOT NULL,
            body TEXT NOT NULL,
            actions JSON NULL,
            state ENUM('unread','read','accepted','declined','expired') NOT NULL DEFAULT 'unread',
            ref_kind VARCHAR(32) NULL,
            ref_id VARCHAR(96) NULL,
            created_at BIGINT NOT NULL,
            expires_at BIGINT NULL,
            resolved_at BIGINT NULL,
            PRIMARY KEY (message_id),
            KEY ix_message_driver (server_id, to_driver_id, state)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- Onboarding metadata (P29): questionnaire version, answers, affinity vector. Never shown, no gameplay effect.
        [[ALTER TABLE driver_profile
            ADD COLUMN IF NOT EXISTS onboarding_json JSON NULL]],

        -- An entry knows the car it drives once a seat is taken.
        [[ALTER TABLE entry
            ADD COLUMN IF NOT EXISTS car_number SMALLINT UNSIGNED NULL]],
    },
}
