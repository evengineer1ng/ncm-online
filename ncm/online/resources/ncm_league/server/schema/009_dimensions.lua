-- ncm_league schema 009: driver dimensions, incidents, telemetry (Batch 1; L54, L56, L57).
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 9,
    name = "dimensions",
    statements = {
        [[CREATE TABLE IF NOT EXISTS driver_licence (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            discipline_id VARCHAR(32) NOT NULL,
            level ENUM('rookie','licensed','pro') NOT NULL DEFAULT 'rookie',
            clean_sessions INT NOT NULL DEFAULT 0,
            earned_at BIGINT NULL,
            PRIMARY KEY (ncm_driver_id, server_id, discipline_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS driver_rating (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            class_id VARCHAR(32) NOT NULL,
            rating DOUBLE NOT NULL DEFAULT 1000,
            sessions INT NOT NULL DEFAULT 0,
            PRIMARY KEY (ncm_driver_id, server_id, class_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS driver_sr (
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            sr DOUBLE NOT NULL DEFAULT 5.0,
            incidents INT NOT NULL DEFAULT 0,
            clean_sessions INT NOT NULL DEFAULT 0,
            updated_at BIGINT NULL,
            PRIMARY KEY (ncm_driver_id, server_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS accomplishment (
            id BIGINT NOT NULL AUTO_INCREMENT,
            ncm_driver_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            kind VARCHAR(32) NOT NULL,
            ref_kind VARCHAR(32) NULL,
            ref_id VARCHAR(96) NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (id),
            UNIQUE KEY ux_acc (ncm_driver_id, server_id, kind, ref_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS incident (
            id BIGINT NOT NULL AUTO_INCREMENT,
            session_id CHAR(36) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            other_driver_id CHAR(36) NULL,
            kind ENUM('car','object','person','offtrack','cut','lane') NOT NULL,
            band TINYINT NOT NULL DEFAULT 1,
            delta_v DOUBLE NULL,
            seconds DOUBLE NOT NULL DEFAULT 0,
            x DOUBLE NULL, y DOUBLE NULL, z DOUBLE NULL,
            t DOUBLE NULL,
            attributed ENUM('self','both','none') NOT NULL DEFAULT 'both',
            evidence_json JSON NULL,
            overridden_by CHAR(36) NULL,
            PRIMARY KEY (id),
            KEY ix_incident_session (session_id, ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        -- one row per driver per ~10 s of samples (cheaper than a row per sample)
        [[CREATE TABLE IF NOT EXISTS telemetry_chunk (
            session_id CHAR(36) NOT NULL,
            ncm_driver_id CHAR(36) NOT NULL,
            seq INT NOT NULL,
            t_from DOUBLE NOT NULL,
            t_to DOUBLE NOT NULL,
            n SMALLINT NOT NULL,
            samples_json MEDIUMTEXT NOT NULL,
            PRIMARY KEY (session_id, ncm_driver_id, seq)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[ALTER TABLE session_result
            ADD COLUMN IF NOT EXISTS corrected_ms INT NULL,
            ADD COLUMN IF NOT EXISTS incident_ms INT NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS incident_count INT NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS best_ms INT NULL]],
    },
}
