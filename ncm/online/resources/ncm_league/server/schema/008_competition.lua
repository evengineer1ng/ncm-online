-- ncm_league schema 008: competition vocabulary (Batch 1; L53). Discipline × format × class × ruleset become ids
-- on events; sessions gain their kind/ordinal/parent so formats with several sessions persist as one plan.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 8,
    name = "competition",
    statements = {
        [[CREATE TABLE IF NOT EXISTS discipline (
            id VARCHAR(32) NOT NULL,
            name VARCHAR(64) NOT NULL,
            course_adapter ENUM('p2p','laps','lanes','eliminations') NOT NULL DEFAULT 'p2p',
            classifier VARCHAR(32) NULL,
            laps_supported TINYINT(1) NOT NULL DEFAULT 0,
            judged TINYINT(1) NOT NULL DEFAULT 0,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS format (
            id VARCHAR(32) NOT NULL,
            name VARCHAR(64) NOT NULL,
            sessions_json JSON NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS class (
            id VARCHAR(32) NOT NULL,
            name VARCHAR(64) NOT NULL,
            pack_id VARCHAR(64) NULL,
            top_speed_kph SMALLINT NOT NULL DEFAULT 0,
            accel_scale DOUBLE NOT NULL DEFAULT 1,
            taper_kph SMALLINT NOT NULL DEFAULT 12,
            setup_window_json JSON NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS class_vehicle (
            class_id VARCHAR(32) NOT NULL,
            record VARCHAR(96) NOT NULL,
            eligible TINYINT(1) NOT NULL DEFAULT 1,
            variants_json JSON NULL,
            min_licence ENUM('rookie','licensed','pro') NOT NULL DEFAULT 'rookie',
            PRIMARY KEY (class_id, record)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[CREATE TABLE IF NOT EXISTS ruleset (
            id VARCHAR(96) NOT NULL,
            version INT NOT NULL DEFAULT 1,
            json JSON NULL,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

        [[ALTER TABLE event
            ADD COLUMN IF NOT EXISTS discipline_id VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS format_id VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS class_id VARCHAR(32) NULL,
            ADD COLUMN IF NOT EXISTS laps SMALLINT NOT NULL DEFAULT 1]],

        -- superset ENUM keeps existing rows valid; ordinal/parent make multi-session formats one plan
        [[ALTER TABLE session
            MODIFY kind ENUM('race','qualifying','practice','quali','heat','stint') NOT NULL DEFAULT 'race',
            ADD COLUMN IF NOT EXISTS parent_session_id CHAR(36) NULL,
            ADD COLUMN IF NOT EXISTS ordinal TINYINT NOT NULL DEFAULT 1,
            ADD COLUMN IF NOT EXISTS lap_count SMALLINT NOT NULL DEFAULT 1,
            ADD COLUMN IF NOT EXISTS format_id VARCHAR(32) NULL]],
    },
}
