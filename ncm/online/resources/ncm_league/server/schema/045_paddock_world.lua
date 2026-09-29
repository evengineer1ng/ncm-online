-- Schema 045: the Paddock's persistent world (doc 44 §4, §14.1).
--
-- People, organizations, series and sponsors of the NPC motorsport world. Ids are per server (`p00001`, `o001`),
-- so every key starts with `server_id`. Hidden attributes live in `*_json` columns and are NEVER sent to a client
-- (`paddock.projection`). Names are unique per server by index -- FTB keyed standings by name and merged
-- namesakes; here everything is keyed by id and the unique name is only a courtesy to readers.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 45,
    name = "paddock_world",
    statements = {
        [[CREATE TABLE IF NOT EXISTS paddock_world (
            server_id VARCHAR(96) NOT NULL,
            seed BIGINT NOT NULL,
            genesis_version INT NOT NULL,
            genesis_season VARCHAR(16) NOT NULL,
            season_id VARCHAR(16) NOT NULL,
            season_ordinal INT NOT NULL DEFAULT 0,
            paddock_year INT NOT NULL,
            day_index_applied INT NULL,
            cup_id VARCHAR(24) NULL,
            counters_json JSON NULL,
            created_at BIGINT NOT NULL,
            PRIMARY KEY (server_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_series (
            server_id VARCHAR(96) NOT NULL,
            series_id VARCHAR(32) NOT NULL,
            tier ENUM('street','regional','pro','premier') NOT NULL,
            division TINYINT NOT NULL,
            name VARCHAR(96) NOT NULL,
            PRIMARY KEY (server_id, series_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_org (
            server_id VARCHAR(96) NOT NULL,
            org_id VARCHAR(16) NOT NULL,
            tier ENUM('street','regional','pro','premier') NOT NULL,
            series_id VARCHAR(32) NOT NULL,
            name VARCHAR(64) NOT NULL,
            short VARCHAR(8) NOT NULL,
            colour VARCHAR(16) NOT NULL,
            prestige SMALLINT NOT NULL,
            cash BIGINT NOT NULL,
            facility SMALLINT NOT NULL,
            car_json JSON NOT NULL,
            owner_person_id VARCHAR(16) NULL,
            manager_person_id VARCHAR(16) NULL,
            engineer_person_id VARCHAR(16) NULL,
            strategist_person_id VARCHAR(16) NULL,
            sponsor_ids JSON NULL,
            human_manager_driver_id CHAR(36) NULL,
            origin ENUM('genesis','replacement','human_founded') NOT NULL,
            lifecycle ENUM('active','folded') NOT NULL DEFAULT 'active',
            founded_season VARCHAR(16) NULL,
            seasons_active INT NOT NULL DEFAULT 1,
            red_days INT NOT NULL DEFAULT 0,
            low_cash_days INT NOT NULL DEFAULT 0,
            evidence_json JSON NULL,
            -- a human manager's roster moves, queued until the next Cup boundary (doc 44 §10)
            pending_json JSON NULL,
            folded_at BIGINT NULL,
            PRIMARY KEY (server_id, org_id),
            UNIQUE KEY ux_paddock_org_name (server_id, name),
            KEY ix_paddock_org_series (server_id, series_id, lifecycle),
            KEY ix_paddock_org_human (server_id, human_manager_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_person (
            server_id VARCHAR(96) NOT NULL,
            person_id VARCHAR(16) NOT NULL,
            role ENUM('driver','owner','manager','engineer','strategist') NOT NULL,
            org_id VARCHAR(16) NULL,
            seat VARCHAR(16) NULL,
            first VARCHAR(48) NOT NULL,
            last VARCHAR(48) NOT NULL,
            display VARCHAR(112) NOT NULL,
            region VARCHAR(24) NOT NULL,
            gender CHAR(1) NOT NULL,
            birth_year INT NOT NULL,
            attrs_json JSON NULL,
            personality_json JSON NULL,
            principal_json JSON NULL,
            morale DECIMAL(5,2) NULL,
            state ENUM('active','free_agent','retired') NOT NULL,
            wage INT NOT NULL DEFAULT 0,
            contract_ends INT NULL,
            evidence_json JSON NULL,
            PRIMARY KEY (server_id, person_id),
            UNIQUE KEY ux_paddock_person_display (server_id, display),
            KEY ix_paddock_person_org (server_id, org_id, state)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        -- Contract history. At most one ACTIVE contract per person: the same generated-column unique index the
        -- One-Team Rule uses (doc 14 §3), so a double signing is impossible to write, not merely unlikely.
        [[CREATE TABLE IF NOT EXISTS paddock_contract (
            contract_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            person_id VARCHAR(16) NOT NULL,
            org_id VARCHAR(16) NOT NULL,
            seat VARCHAR(16) NULL,
            wage INT NOT NULL,
            starts_season INT NOT NULL,
            ends_season INT NOT NULL,
            signed_at BIGINT NOT NULL,
            ended_at BIGINT NULL,
            end_reason VARCHAR(32) NULL,
            active_key VARCHAR(120) AS (IF(ended_at IS NULL, CONCAT(server_id, '|', person_id), NULL)) PERSISTENT,
            PRIMARY KEY (contract_id),
            UNIQUE KEY ux_paddock_contract_active (active_key),
            KEY ix_paddock_contract_person (server_id, person_id, signed_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_sponsor (
            server_id VARCHAR(96) NOT NULL,
            sponsor_id VARCHAR(16) NOT NULL,
            name VARCHAR(96) NOT NULL,
            short VARCHAR(48) NOT NULL,
            industry VARCHAR(24) NOT NULL,
            tier VARCHAR(16) NOT NULL,
            personality_json JSON NULL,
            org_id VARCHAR(16) NULL,
            per_day INT NOT NULL,
            PRIMARY KEY (server_id, sponsor_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_person_season (
            server_id VARCHAR(96) NOT NULL,
            person_id VARCHAR(16) NOT NULL,
            season_id VARCHAR(16) NOT NULL,
            summary_json JSON NOT NULL,
            PRIMARY KEY (server_id, person_id, season_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
