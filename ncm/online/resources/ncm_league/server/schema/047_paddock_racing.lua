-- Schema 047: Paddock races and results (doc 44 §6, §12).
--
-- NPC results live in their OWN tables. `session_result` carries a foreign key to `ncm_driver`, so an NPC result
-- could not be written there even by mistake -- which is the parallel circuit (L224.1) enforced by the schema.
-- Every race carries its provenance and backend: `simulated` / `simulatedAI` through phases 1-3; `physical`
-- only when a declared physical-authoritative race is corroborated (phase 5, L222). The seed is stored when the
-- race is materialised and `seed_commit` (a hash of it) is what a box score may show; the seed itself is never
-- sent anywhere. `paddock_standing` is the archive written at a Cup or season close, so standings survive
-- result pruning. `paddock_sighting` is created now for phase 3 and stays empty until then.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 47,
    name = "paddock_racing",
    statements = {
        [[CREATE TABLE IF NOT EXISTS paddock_race (
            server_id VARCHAR(96) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            series_id VARCHAR(32) NOT NULL,
            tier VARCHAR(16) NOT NULL,
            season_id VARCHAR(16) NOT NULL,
            cup_id VARCHAR(24) NOT NULL,
            route_id VARCHAR(160) NOT NULL,
            window_opens_at BIGINT NOT NULL,
            window_closes_at BIGINT NULL,
            state ENUM('scheduled','priced','running','resolved','void') NOT NULL DEFAULT 'scheduled',
            seed BIGINT NOT NULL,
            seed_commit CHAR(8) NOT NULL,
            weather VARCHAR(32) NULL,
            road_wetness DECIMAL(4,3) NULL,
            seconds_of_day INT NULL,
            light VARCHAR(8) NULL,
            base_sec DECIMAL(8,3) NULL,
            base_source VARCHAR(16) NULL,
            provenance ENUM('simulated','physical') NOT NULL DEFAULT 'simulated',
            backend VARCHAR(16) NOT NULL DEFAULT 'simulatedAI',
            sim_version INT NULL,
            detail_json MEDIUMTEXT NULL,
            resolved_at BIGINT NULL,
            PRIMARY KEY (server_id, race_id),
            KEY ix_paddock_race_state (server_id, state, window_opens_at),
            KEY ix_paddock_race_series (server_id, series_id, window_opens_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_result (
            server_id VARCHAR(96) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            person_id VARCHAR(16) NOT NULL,
            org_id VARCHAR(16) NOT NULL,
            series_id VARCHAR(32) NOT NULL,
            season_id VARCHAR(16) NOT NULL,
            cup_id VARCHAR(24) NOT NULL,
            position SMALLINT NOT NULL,
            grid SMALLINT NOT NULL,
            state ENUM('finished','dnf','dns') NOT NULL,
            finish_ms INT NULL,
            gap_ms INT NULL,
            points SMALLINT NOT NULL DEFAULT 0,
            purse INT NOT NULL DEFAULT 0,
            dnf_reason VARCHAR(24) NULL,
            at BIGINT NOT NULL,
            PRIMARY KEY (server_id, race_id, person_id),
            KEY ix_paddock_result_person (server_id, person_id, at),
            KEY ix_paddock_result_season (server_id, season_id, series_id),
            KEY ix_paddock_result_org (server_id, org_id, at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_standing (
            server_id VARCHAR(96) NOT NULL,
            season_id VARCHAR(16) NOT NULL,
            cup_id VARCHAR(24) NOT NULL,
            series_id VARCHAR(32) NOT NULL,
            entity_kind ENUM('driver','org') NOT NULL,
            entity_id VARCHAR(16) NOT NULL,
            pos SMALLINT NOT NULL,
            points INT NOT NULL,
            wins SMALLINT NOT NULL,
            podiums SMALLINT NOT NULL,
            starts SMALLINT NOT NULL,
            dnfs SMALLINT NOT NULL,
            PRIMARY KEY (server_id, season_id, cup_id, series_id, entity_kind, entity_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
        [[CREATE TABLE IF NOT EXISTS paddock_sighting (
            sighting_id CHAR(36) NOT NULL,
            server_id VARCHAR(96) NOT NULL,
            race_id VARCHAR(64) NOT NULL,
            at BIGINT NOT NULL,
            cars SMALLINT NOT NULL,
            outcome VARCHAR(24) NULL,
            PRIMARY KEY (sighting_id),
            KEY ix_paddock_sighting_at (server_id, at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
