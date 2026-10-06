-- Schema 061: the hall of champions (L303, doc 45 §O).
--
-- Every Racing Week crowns every series at hour 72 and the names outlive the reset: keyed on the server, never on a
-- run's world, written once per (run, series) with INSERT IGNORE. NPC or human alike -- `champion_key` is the
-- standings id (a Paddock person id, or a human's person key) and `ncm_driver_id` is set for humans.
NcmSchema = NcmSchema or {}

NcmSchema[#NcmSchema + 1] = {
    version = 61,
    name = "racing_week_champion",
    statements = {
        [[CREATE TABLE IF NOT EXISTS racing_week_champion (
            server_id VARCHAR(96) NOT NULL,
            run_index INT NOT NULL,
            series_id VARCHAR(32) NOT NULL,
            series_name VARCHAR(96) NOT NULL,
            tier VARCHAR(16) NOT NULL,
            champion_key VARCHAR(16) NOT NULL,
            display VARCHAR(112) NOT NULL,
            org_name VARCHAR(96) NOT NULL DEFAULT '',
            human TINYINT(1) NOT NULL DEFAULT 0,
            ncm_driver_id CHAR(36) NULL,
            points INT NOT NULL,
            wins SMALLINT NOT NULL,
            podiums SMALLINT NOT NULL,
            starts SMALLINT NOT NULL,
            crowned_at BIGINT NOT NULL,
            PRIMARY KEY (server_id, run_index, series_id),
            KEY ix_rwc_driver (server_id, ncm_driver_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
    },
}
